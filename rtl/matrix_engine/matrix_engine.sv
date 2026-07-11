// Matrix Compute Engine top level: input buffers (weight/activation/seed)
// -> mac_array -> matrix_engine_ctrl -> output buffer, per
// docs/architecture/tpe_architecture_spec.md section 3.5.
//
// The four buffers are plain rtl/common/dp_ram.sv instances, each exposing
// port A externally (named <buf>_a_* to match the reusable
// verif/cocotb_tb/env/SyncPortAgent convention from M1) for the testbench
// (standalone here in M2; the top-level integration in M4 wires these to
// the Local SRAM / DMA path instead). Port B is used internally by
// matrix_engine_ctrl. Each buffer stores one *whole row* of its matrix per
// address (e.g. weight_buf address k holds all COLS weights B[k][0:COLS-1]
// packed into one wide word) -- see matrix_engine_ctrl.sv's header comment
// for why the systolic skew needs that layout.
module matrix_engine
  import tpe_pkg::*;
#(
    parameter int ROWS         = MAC_ARRAY_ROWS,
    parameter int COLS         = MAC_ARRAY_COLS,
    parameter int MAX_M        = MAX_TILE_DIM,
    parameter int M_ADDR_WIDTH = $clog2(MAX_M),
    localparam int ACCUM_BYTES = ACCUM_WIDTH / 8
) (
    input logic clk,
    input logic rst_n,

    // Control (matches the matrix_engine register block)
    input  logic                       start,
    input  logic [TILE_DIM_WIDTH-1:0]  dim_m,
    input  logic [TILE_DIM_WIDTH-1:0]  dim_k,
    input  logic [TILE_DIM_WIDTH-1:0]  dim_n,
    output logic                       busy,
    output logic                       done,
    output logic                       overflow_sticky,

    // weight_buf port A (TB/DMA loads B tile: one K-row per address)
    input  logic                              wbuf_a_en,
    input  logic                              wbuf_a_we,
    input  logic [COLS-1:0]                   wbuf_a_strb,
    input  logic [TILE_DIM_WIDTH-1:0]         wbuf_a_addr,
    input  logic [COLS*OPERAND_WIDTH-1:0]     wbuf_a_wdata,
    output logic [COLS*OPERAND_WIDTH-1:0]     wbuf_a_rdata,

    // act_buf port A (TB/DMA loads A tile: one M-row per address)
    input  logic                              abuf_a_en,
    input  logic                              abuf_a_we,
    input  logic [ROWS-1:0]                   abuf_a_strb,
    input  logic [M_ADDR_WIDTH-1:0]           abuf_a_addr,
    input  logic [ROWS*OPERAND_WIDTH-1:0]     abuf_a_wdata,
    output logic [ROWS*OPERAND_WIDTH-1:0]     abuf_a_rdata,

    // seed_buf port A (TB/DMA loads C-in: one M-row per address)
    input  logic                              sbuf_a_en,
    input  logic                              sbuf_a_we,
    input  logic [COLS*ACCUM_BYTES-1:0]       sbuf_a_strb,
    input  logic [M_ADDR_WIDTH-1:0]           sbuf_a_addr,
    input  logic [COLS*ACCUM_WIDTH-1:0]       sbuf_a_wdata,
    output logic [COLS*ACCUM_WIDTH-1:0]       sbuf_a_rdata,

    // out_buf port A (TB/DMA reads C-out: one M-row per address)
    input  logic                              obuf_a_en,
    input  logic                              obuf_a_we,
    input  logic [COLS*ACCUM_BYTES-1:0]       obuf_a_strb,
    input  logic [M_ADDR_WIDTH-1:0]           obuf_a_addr,
    input  logic [COLS*ACCUM_WIDTH-1:0]       obuf_a_wdata,
    output logic [COLS*ACCUM_WIDTH-1:0]       obuf_a_rdata
);

  // ---- Port B <-> ctrl array-port adapters --------------------------
  logic                       wbuf_b_en;
  logic [TILE_DIM_WIDTH-1:0]  wbuf_b_addr_full;
  logic [$clog2(ROWS)-1:0]    wbuf_b_addr;
  logic [COLS*OPERAND_WIDTH-1:0] wbuf_b_rdata_flat;
  logic signed [OPERAND_WIDTH-1:0] wbuf_b_rdata[COLS];

  logic                    abuf_b_en;
  logic [M_ADDR_WIDTH-1:0] abuf_b_addr;
  logic [ROWS*OPERAND_WIDTH-1:0] abuf_b_rdata_flat;
  logic signed [OPERAND_WIDTH-1:0] abuf_b_rdata[ROWS];

  logic                    sbuf_b_en;
  logic [M_ADDR_WIDTH-1:0] sbuf_b_addr;
  logic [COLS*ACCUM_WIDTH-1:0] sbuf_b_rdata_flat;
  logic signed [ACCUM_WIDTH-1:0] sbuf_b_rdata[COLS];

  // out_buf: COLS independent sub-buffers, one write port each (see
  // matrix_engine_ctrl.sv for why -- a single shared write port keyed off
  // the last column's valid pulse cannot correctly de-skew more than one
  // in-flight row). Port A stays a single external interface: the same
  // address is broadcast to every sub-buffer and their read data is
  // concatenated, so callers see the same wide-row-per-address shape as
  // weight_buf/act_buf/seed_buf.
  logic [COLS-1:0]         obuf_b_wen;
  logic [M_ADDR_WIDTH-1:0] obuf_b_waddr[COLS];
  logic signed [ACCUM_WIDTH-1:0] obuf_b_wdata[COLS];
  logic signed [ACCUM_WIDTH-1:0] obuf_a_rdata_arr[COLS];

  assign wbuf_b_addr = wbuf_b_addr_full[$clog2(ROWS)-1:0];

  for (genvar c = 0; c < COLS; c++) begin : g_wbuf_unpack
    assign wbuf_b_rdata[c] = wbuf_b_rdata_flat[c*OPERAND_WIDTH+:OPERAND_WIDTH];
  end
  for (genvar r = 0; r < ROWS; r++) begin : g_abuf_unpack
    assign abuf_b_rdata[r] = abuf_b_rdata_flat[r*OPERAND_WIDTH+:OPERAND_WIDTH];
  end
  for (genvar c = 0; c < COLS; c++) begin : g_sbuf_unpack
    assign sbuf_b_rdata[c] = sbuf_b_rdata_flat[c*ACCUM_WIDTH+:ACCUM_WIDTH];
  end
  for (genvar c = 0; c < COLS; c++) begin : g_obuf_pack
    assign obuf_a_rdata[c*ACCUM_WIDTH+:ACCUM_WIDTH] = obuf_a_rdata_arr[c];
  end

  // ---- Buffers --------------------------------------------------------
  dp_ram #(
      .DATA_WIDTH(COLS * OPERAND_WIDTH),
      .DEPTH     (ROWS),
      .ADDR_WIDTH($clog2(ROWS)),
      .STRB_WIDTH(COLS)
  ) u_weight_buf (
      .clk    (clk),
      .a_en   (wbuf_a_en),
      .a_we   (wbuf_a_we),
      .a_strb (wbuf_a_strb),
      .a_addr (wbuf_a_addr[$clog2(ROWS)-1:0]),
      .a_wdata(wbuf_a_wdata),
      .a_rdata(wbuf_a_rdata),
      .b_en   (wbuf_b_en),
      .b_we   (1'b0),
      .b_strb ('0),
      .b_addr (wbuf_b_addr),
      .b_wdata('0),
      .b_rdata(wbuf_b_rdata_flat)
  );

  dp_ram #(
      .DATA_WIDTH(ROWS * OPERAND_WIDTH),
      .DEPTH     (MAX_M),
      .ADDR_WIDTH(M_ADDR_WIDTH),
      .STRB_WIDTH(ROWS)
  ) u_act_buf (
      .clk    (clk),
      .a_en   (abuf_a_en),
      .a_we   (abuf_a_we),
      .a_strb (abuf_a_strb),
      .a_addr (abuf_a_addr),
      .a_wdata(abuf_a_wdata),
      .a_rdata(abuf_a_rdata),
      .b_en   (abuf_b_en),
      .b_we   (1'b0),
      .b_strb ('0),
      .b_addr (abuf_b_addr),
      .b_wdata('0),
      .b_rdata(abuf_b_rdata_flat)
  );

  dp_ram #(
      .DATA_WIDTH(COLS * ACCUM_WIDTH),
      .DEPTH     (MAX_M),
      .ADDR_WIDTH(M_ADDR_WIDTH),
      .STRB_WIDTH(COLS * ACCUM_BYTES)
  ) u_seed_buf (
      .clk    (clk),
      .a_en   (sbuf_a_en),
      .a_we   (sbuf_a_we),
      .a_strb (sbuf_a_strb),
      .a_addr (sbuf_a_addr),
      .a_wdata(sbuf_a_wdata),
      .a_rdata(sbuf_a_rdata),
      .b_en   (sbuf_b_en),
      .b_we   (1'b0),
      .b_strb ('0),
      .b_addr (sbuf_b_addr),
      .b_wdata('0),
      .b_rdata(sbuf_b_rdata_flat)
  );

  for (genvar c = 0; c < COLS; c++) begin : g_out_buf
    dp_ram #(
        .DATA_WIDTH(ACCUM_WIDTH),
        .DEPTH     (MAX_M),
        .ADDR_WIDTH(M_ADDR_WIDTH),
        .STRB_WIDTH(ACCUM_BYTES)
    ) u_out_buf_col (
        .clk    (clk),
        .a_en   (obuf_a_en),
        .a_we   (obuf_a_we),
        .a_strb (obuf_a_strb[c*ACCUM_BYTES+:ACCUM_BYTES]),
        .a_addr (obuf_a_addr),
        .a_wdata(obuf_a_wdata[c*ACCUM_WIDTH+:ACCUM_WIDTH]),
        .a_rdata(obuf_a_rdata_arr[c]),
        .b_en   (obuf_b_wen[c]),
        .b_we   (1'b1),
        .b_strb ({ACCUM_BYTES{1'b1}}),
        .b_addr (obuf_b_waddr[c]),
        .b_wdata(obuf_b_wdata[c]),
        .b_rdata()
    );
  end

  // ---- Control + array --------------------------------------------
  logic [ROWS-1:0] arr_weight_load_row;
  logic signed [OPERAND_WIDTH-1:0] arr_weight_bus[COLS];
  logic [ROWS-1:0] arr_a_valid_in;
  logic signed [OPERAND_WIDTH-1:0] arr_a_in[ROWS];
  logic signed [ACCUM_WIDTH-1:0] arr_acc_seed[COLS];
  logic [COLS-1:0] arr_result_valid;
  logic signed [ACCUM_WIDTH-1:0] arr_result[COLS];
  logic [COLS-1:0] arr_result_overflow;

  matrix_engine_ctrl #(
      .ROWS         (ROWS),
      .COLS         (COLS),
      .OPERAND_WIDTH(OPERAND_WIDTH),
      .ACCUM_WIDTH  (ACCUM_WIDTH),
      .DIM_WIDTH    (TILE_DIM_WIDTH),
      .M_ADDR_WIDTH (M_ADDR_WIDTH)
  ) u_ctrl (
      .clk               (clk),
      .rst_n             (rst_n),
      .start             (start),
      .dim_m             (dim_m),
      .dim_k             (dim_k),
      .dim_n             (dim_n),
      .busy              (busy),
      .done              (done),
      .overflow_sticky   (overflow_sticky),
      .wbuf_ren          (wbuf_b_en),
      .wbuf_addr         (wbuf_b_addr_full),
      .wbuf_rdata        (wbuf_b_rdata),
      .abuf_ren          (abuf_b_en),
      .abuf_addr         (abuf_b_addr),
      .abuf_rdata        (abuf_b_rdata),
      .sbuf_ren          (sbuf_b_en),
      .sbuf_addr         (sbuf_b_addr),
      .sbuf_rdata        (sbuf_b_rdata),
      .obuf_wen          (obuf_b_wen),
      .obuf_waddr        (obuf_b_waddr),
      .obuf_wdata        (obuf_b_wdata),
      .arr_weight_load_row(arr_weight_load_row),
      .arr_weight_bus    (arr_weight_bus),
      .arr_a_valid_in    (arr_a_valid_in),
      .arr_a_in          (arr_a_in),
      .arr_acc_seed      (arr_acc_seed),
      .arr_result_valid  (arr_result_valid),
      .arr_result        (arr_result),
      .arr_result_overflow(arr_result_overflow)
  );

  mac_array #(
      .ROWS         (ROWS),
      .COLS         (COLS),
      .OPERAND_WIDTH(OPERAND_WIDTH),
      .ACCUM_WIDTH  (ACCUM_WIDTH)
  ) u_mac_array (
      .clk             (clk),
      .rst_n           (rst_n),
      .weight_load_row (arr_weight_load_row),
      .weight_bus      (arr_weight_bus),
      .a_valid_in      (arr_a_valid_in),
      .a_in            (arr_a_in),
      .acc_seed        (arr_acc_seed),
      .result_valid    (arr_result_valid),
      .result          (arr_result),
      .result_overflow (arr_result_overflow)
  );

endmodule
