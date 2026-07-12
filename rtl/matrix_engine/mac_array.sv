// ROWS x COLS weight-stationary systolic array of pe.sv instances.
// Pure fabric: activations enter each row's west edge (a_in[r]) and flow
// east; partial sums enter each column's north edge (acc_seed[c]) and flow
// south; weights load into row r when weight_load_row[r] is set, taking
// weight_bus[c] for column c. Getting the *timing* of a_in/acc_seed right
// (the systolic skew) is matrix_engine_ctrl.sv's job -- see its header
// comment for the full derivation of why row r must be injected exactly r
// cycles after row 0 for a given m.
//
// result_valid[c] is read off the *bottom row's own* horizontally-
// propagated valid chain (seeded by a_valid_in[ROWS-1]), not a separate
// vertical valid path: pe.sv registers valid_out alongside a_out with
// identical timing, so the bottom row's valid arriving at column c after
// its c-cycle horizontal trip lands on exactly the same cycle the vertical
// accumulate sum for that (m, c) completes, *provided* the controller
// injects row ROWS-1 at the correct skew (see matrix_engine_ctrl.sv). No
// separate bookkeeping needed -- the bottom row is always the last
// contributor, by construction of the skew.
module mac_array #(
    parameter int ROWS          = tpe_pkg::MAC_ARRAY_ROWS,
    parameter int COLS          = tpe_pkg::MAC_ARRAY_COLS,
    parameter int OPERAND_WIDTH = tpe_pkg::OPERAND_WIDTH,
    parameter int ACCUM_WIDTH   = tpe_pkg::ACCUM_WIDTH
) (
    input logic clk,
    input logic rst_n,

    input logic [ROWS-1:0] weight_load_row,
    input logic signed [OPERAND_WIDTH-1:0] weight_bus[COLS],

    input logic [ROWS-1:0] a_valid_in,
    input logic signed [OPERAND_WIDTH-1:0] a_in[ROWS],
    input logic signed [ACCUM_WIDTH-1:0] acc_seed[COLS],

    output logic [COLS-1:0] result_valid,
    output logic signed [ACCUM_WIDTH-1:0] result[COLS],
    output logic [COLS-1:0] result_overflow
);

  // a_grid[r][c] / valid_grid[r][c]: activation and its valid flag arriving
  // at PE[r][c]'s west edge. c=0 is fed by a_in[r]/a_valid_in[r]; c=COLS
  // holds the last column's a_out/valid_out (discarded except for row
  // ROWS-1, which becomes result_valid).
  logic signed [OPERAND_WIDTH-1:0] a_grid[ROWS][COLS+1];
  logic valid_grid[ROWS][COLS+1];

  // acc_grid[r][c] / ovf_grid[r][c] = acc_in/ovf_in arriving at PE[r][c]
  // from the north; r=0 is the north edge (acc_seed[c] / no overflow),
  // r=ROWS is the final south output (the completed sum / sticky overflow
  // for that column, once result_valid[c] confirms it corresponds to a
  // real (m, c)).
  logic signed [ACCUM_WIDTH-1:0] acc_grid[ROWS+1][COLS];
  logic ovf_grid[ROWS+1][COLS];

  for (genvar c = 0; c < COLS; c++) begin : g_col_edges
    assign acc_grid[0][c] = acc_seed[c];
    assign ovf_grid[0][c] = 1'b0;
  end

  for (genvar r = 0; r < ROWS; r++) begin : g_row_edges
    assign a_grid[r][0]     = a_in[r];
    assign valid_grid[r][0] = a_valid_in[r];
  end

  for (genvar r = 0; r < ROWS; r++) begin : g_rows
    for (genvar c = 0; c < COLS; c++) begin : g_cols
      pe #(
          .OPERAND_WIDTH(OPERAND_WIDTH),
          .ACCUM_WIDTH  (ACCUM_WIDTH)
      ) u_pe (
          .clk        (clk),
          .rst_n      (rst_n),
          .weight_load(weight_load_row[r]),
          .weight_in  (weight_bus[c]),
          .valid_in   (valid_grid[r][c]),
          .a_in       (a_grid[r][c]),
          .acc_in     (acc_grid[r][c]),
          .ovf_in     (ovf_grid[r][c]),
          .valid_out  (valid_grid[r][c+1]),
          .a_out      (a_grid[r][c+1]),
          .acc_out    (acc_grid[r+1][c]),
          .ovf_out    (ovf_grid[r+1][c])
      );
    end
  end

  for (genvar c = 0; c < COLS; c++) begin : g_result
    assign result[c]          = acc_grid[ROWS][c];
    assign result_valid[c]    = valid_grid[ROWS-1][c+1];
    assign result_overflow[c] = ovf_grid[ROWS][c];
  end

  // ---- Debug logging (see rtl/include/tpe_verbosity.svh) -- array-level
  // only (not per-PE, up to ROWS*COLS=256 instances at full size -- see
  // pe.sv, deliberately not instrumented individually).
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // no state to reset -- debug prints only
    end else if (|result_valid) begin
      `TPE_LOG_DEBUG("mac_array", $sformatf("result_valid=%0b result_overflow=%0b",
                                             result_valid, result_overflow));
    end
  end

endmodule
