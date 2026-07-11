// Matrix Compute Engine control FSM: sequences weight loading, streams
// activations into mac_array with the systolic skew, and de-skews the
// array's staggered per-column output back into whole result rows.
//
// ---------------------------------------------------------------------
// Systolic skew derivation (why row r / column c need their own delay)
// ---------------------------------------------------------------------
// pe.sv registers acc_out <= acc_in + a_in*weight every cycle. For
// PE[r][c]'s acc_out to sum contributions from rows 0..r for the *same*
// (m, c), its acc_in (from PE[r-1][c], one row up) and a_in (from
// PE[r][c-1], one column left, ultimately from this row's own west edge)
// must both reflect that same (m, c) at the same cycle. Tracing the
// pipeline delays through mac_array shows this holds exactly when row r's
// activation for a given m is injected at cycle (r + m) relative to
// compute-phase start (row 0 injects immediately per m; each subsequent
// row is one cycle later) -- see rtl/matrix_engine/README.md for the full
// worked timing diagram. The same argument applies to acc_seed[c] (fed
// directly into row 0's acc_in from the north): it must be presented at
// cycle (0 + m + c), i.e. delayed by c cycles relative to column 0.
//
// Both delays are implemented below as per-row / per-column shift-register
// "skew chains" (g_a_skew, g_seed_skew) of depth r / c respectively, fed
// by a single registered memory read per cycle (one whole M-row of
// activations, or one whole M-row of the C-in seed, per act_buf/seed_buf
// address). The array's own pipeline provides the output-side skew for
// free: column c's result for a given m becomes valid c cycles after
// column 0's, which is de-skewed back into whole rows by out_row_staging
// below, keyed off the *last active column*'s result_valid pulse.
module matrix_engine_ctrl #(
    parameter int ROWS          = tpe_pkg::MAC_ARRAY_ROWS,
    parameter int COLS          = tpe_pkg::MAC_ARRAY_COLS,
    parameter int OPERAND_WIDTH = tpe_pkg::OPERAND_WIDTH,
    parameter int ACCUM_WIDTH   = tpe_pkg::ACCUM_WIDTH,
    parameter int DIM_WIDTH     = tpe_pkg::TILE_DIM_WIDTH,
    parameter int M_ADDR_WIDTH  = 12  // must cover max supported dim_m
) (
    input logic clk,
    input logic rst_n,

    // Control
    input  logic                  start,
    input  logic [DIM_WIDTH-1:0]  dim_m,
    input  logic [DIM_WIDTH-1:0]  dim_k,
    input  logic [DIM_WIDTH-1:0]  dim_n,
    output logic                  busy,
    output logic                  done,
    output logic                  overflow_sticky,

    // weight_buf port B (one K-row of weights per address)
    output logic                       wbuf_ren,
    output logic [DIM_WIDTH-1:0]       wbuf_addr,
    input  logic signed [OPERAND_WIDTH-1:0] wbuf_rdata[COLS],

    // act_buf port B (one M-row of activations per address)
    output logic                       abuf_ren,
    output logic [M_ADDR_WIDTH-1:0]    abuf_addr,
    input  logic signed [OPERAND_WIDTH-1:0] abuf_rdata[ROWS],

    // seed_buf port B (one M-row of C-in per address)
    output logic                       sbuf_ren,
    output logic [M_ADDR_WIDTH-1:0]    sbuf_addr,
    input  logic signed [ACCUM_WIDTH-1:0] sbuf_rdata[COLS],

    // out_buf: COLS independent per-column sub-buffers (see matrix_engine.sv)
    output logic [COLS-1:0]             obuf_wen,
    output logic [M_ADDR_WIDTH-1:0]     obuf_waddr[COLS],
    output logic signed [ACCUM_WIDTH-1:0] obuf_wdata[COLS],

    // mac_array
    output logic [ROWS-1:0]                  arr_weight_load_row,
    output logic signed [OPERAND_WIDTH-1:0]  arr_weight_bus[COLS],
    output logic [ROWS-1:0]                  arr_a_valid_in,
    output logic signed [OPERAND_WIDTH-1:0]  arr_a_in[ROWS],
    output logic signed [ACCUM_WIDTH-1:0]    arr_acc_seed[COLS],
    input  logic [COLS-1:0]                  arr_result_valid,
    input  logic signed [ACCUM_WIDTH-1:0]    arr_result[COLS],
    input  logic [COLS-1:0]                  arr_result_overflow
);

  typedef enum logic [2:0] {
    ST_IDLE,
    ST_LOAD_WEIGHTS,
    ST_COMPUTE,
    ST_DRAIN,
    ST_DONE
  } state_e;

  state_e state_q, state_d;

  // Latched tile dims for the duration of the op.
  logic [DIM_WIDTH-1:0] m_q, k_q, n_q;

  // ---- Weight load ------------------------------------------------
  logic [DIM_WIDTH-1:0] wload_idx_q;  // which K-row we're loading

  always_comb begin
    wbuf_ren  = (state_q == ST_LOAD_WEIGHTS) && (wload_idx_q < k_q);
    wbuf_addr = wload_idx_q;
  end

  // wbuf_rdata is valid one cycle after wbuf_addr/ren -- registered here
  // to align weight_load_row with the data.
  logic [DIM_WIDTH-1:0] wload_idx_d1_q;
  logic wload_valid_d1_q;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wload_idx_d1_q   <= '0;
      wload_valid_d1_q <= 1'b0;
    end else begin
      wload_idx_d1_q   <= wload_idx_q;
      wload_valid_d1_q <= wbuf_ren;
    end
  end

  always_comb begin
    arr_weight_bus = wbuf_rdata;
    for (int r = 0; r < ROWS; r++) begin
      arr_weight_load_row[r] = wload_valid_d1_q && (wload_idx_d1_q == DIM_WIDTH'(r));
    end
  end

  // ---- Activation / seed fetch (one M-row per cycle) ---------------
  logic [M_ADDR_WIDTH-1:0] m_fetch_idx_q;

  always_comb begin
    abuf_ren  = (state_q == ST_COMPUTE) && (m_fetch_idx_q < M_ADDR_WIDTH'(m_q));
    abuf_addr = m_fetch_idx_q;
    sbuf_ren  = abuf_ren;
    sbuf_addr = m_fetch_idx_q;
  end

  logic fetch_valid_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) fetch_valid_q <= 1'b0;
    else fetch_valid_q <= abuf_ren;
  end

  // ---- Per-row activation skew chains (depth r) ---------------------
  //
  // Two *separate* concepts, easy to conflate (an earlier version did,
  // causing DRAIN to hang whenever dim_k < ROWS -- see
  // verif/cocotb_tb/matrix_engine/README.md): whether row r *contributes*
  // to the sum (gated by r < k_q, by zeroing its activation input so an
  // unused row's pass-through addition is +0) versus whether a given
  // pipeline cycle carries a *real* m at all (valid_in/valid_out, tracked
  // uniformly for every row regardless of k_q, since the physical pipeline
  // always spans all ROWS stages no matter how many rows are logically in
  // use). result_valid ultimately reads off row ROWS-1's own valid chain
  // (see mac_array.sv) -- that only works if row ROWS-1 gets valid pulses
  // like every other row, unused or not.
  for (genvar r = 0; r < ROWS; r++) begin : g_a_skew
    if (r == 0) begin : g_r0
      assign arr_a_in[r]      = (r <= k_q) ? abuf_rdata[r] : '0;
      assign arr_a_valid_in[r] = fetch_valid_q;
    end else begin : g_rN
      logic signed [OPERAND_WIDTH-1:0] data_chain[r];
      logic valid_chain[r];
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          for (int i = 0; i < r; i++) begin
            data_chain[i]  <= '0;
            valid_chain[i] <= 1'b0;
          end
        end else begin
          data_chain[0]  <= (DIM_WIDTH'(r) <= k_q) ? abuf_rdata[r] : '0;
          valid_chain[0] <= fetch_valid_q;
          for (int i = 1; i < r; i++) begin
            data_chain[i]  <= data_chain[i-1];
            valid_chain[i] <= valid_chain[i-1];
          end
        end
      end
      assign arr_a_in[r]       = data_chain[r-1];
      assign arr_a_valid_in[r] = valid_chain[r-1];
    end
  end

  // ---- Per-column seed skew chains (depth c) -------------------------
  for (genvar c = 0; c < COLS; c++) begin : g_seed_skew
    if (c == 0) begin : g_c0
      assign arr_acc_seed[c] = sbuf_rdata[c];
    end else begin : g_cN
      logic signed [ACCUM_WIDTH-1:0] seed_chain[c];
      always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
          for (int i = 0; i < c; i++) seed_chain[i] <= '0;
        end else begin
          seed_chain[0] <= sbuf_rdata[c];
          for (int i = 1; i < c; i++) seed_chain[i] <= seed_chain[i-1];
        end
      end
      assign arr_acc_seed[c] = (c >= 2) ? seed_chain[c-2] : seed_chain[c-1];
    end
  end

  // ---- Output: each column writes its own sub-buffer independently ---
  // out_buf is COLS separate sub-memories (see matrix_engine.sv), so no
  // de-skewing/staging is needed at all: column c's result becomes valid
  // c cycles after column 0's (see this file's header comment), but since
  // each column owns its own write port and its own row counter, it just
  // writes the moment its own result is ready. An earlier version tried to
  // assemble whole output rows from a single shared staging register keyed
  // off the last column's valid pulse -- that is WRONG whenever more than
  // one m is in flight across the array at once (always true for COLS>1):
  // an early column's *later* m overwrites its staged *earlier* m value
  // before the late column's write for that earlier m fires, silently
  // corrupting every column except the last. Per-column sub-buffers side-
  // step the problem entirely instead of trying to re-synchronize it.
  logic [M_ADDR_WIDTH-1:0] out_m_idx_q[COLS];

  always_comb begin
    for (int c = 0; c < COLS; c++) begin
      obuf_wen[c]   = arr_result_valid[c];
      obuf_waddr[c] = out_m_idx_q[c];
      obuf_wdata[c] = arr_result[c];
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      for (int c = 0; c < COLS; c++) out_m_idx_q[c] <= '0;
    end else if (state_q == ST_IDLE) begin
      for (int c = 0; c < COLS; c++) out_m_idx_q[c] <= '0;
    end else begin
      for (int c = 0; c < COLS; c++) begin
        if (arr_result_valid[c]) out_m_idx_q[c] <= out_m_idx_q[c] + 1'b1;
      end
    end
  end

  logic overflow_sticky_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      overflow_sticky_q <= 1'b0;
    end else if (start) begin
      overflow_sticky_q <= 1'b0;
    end else begin
      for (int c = 0; c < COLS; c++) begin
        if (arr_result_valid[c] && arr_result_overflow[c]) overflow_sticky_q <= 1'b1;
      end
    end
  end
  assign overflow_sticky = overflow_sticky_q;

  // ---- Main FSM -------------------------------------------------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q       <= ST_IDLE;
      m_q           <= '0;
      k_q           <= '0;
      n_q           <= '0;
      wload_idx_q   <= '0;
      m_fetch_idx_q <= '0;
    end else begin
      state_q <= state_d;

      case (state_q)
        ST_IDLE: begin
          if (start) begin
            m_q <= dim_m;
            k_q <= dim_k;
            n_q <= dim_n;
          end
          wload_idx_q   <= '0;
          m_fetch_idx_q <= '0;
        end

        ST_LOAD_WEIGHTS: begin
          if (wbuf_ren) wload_idx_q <= wload_idx_q + 1'b1;
        end

        ST_COMPUTE: begin
          if (abuf_ren) m_fetch_idx_q <= m_fetch_idx_q + 1'b1;
        end

        default: ;
      endcase
    end
  end

  always_comb begin
    state_d = state_q;
    case (state_q)
      ST_IDLE:          if (start) state_d = ST_LOAD_WEIGHTS;
      ST_LOAD_WEIGHTS:   if (wload_idx_q >= k_q) state_d = ST_COMPUTE;
      ST_COMPUTE:        if (m_fetch_idx_q >= M_ADDR_WIDTH'(m_q)) state_d = ST_DRAIN;
      // Last *active* column (n_q-1) is always the last to finish a given
      // row (see the header comment), so its counter reaching m_q means
      // every active column has written every row.
      ST_DRAIN:          if (out_m_idx_q[n_q-1] >= M_ADDR_WIDTH'(m_q)) state_d = ST_DONE;
      ST_DONE:           state_d = ST_IDLE;
      default:           state_d = ST_IDLE;
    endcase
  end

  assign busy = (state_q != ST_IDLE);
  assign done = (state_q == ST_DONE);

endmodule
