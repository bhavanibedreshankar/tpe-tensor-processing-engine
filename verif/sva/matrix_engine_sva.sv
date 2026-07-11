// Protocol checks for rtl/matrix_engine/{matrix_engine_ctrl,mac_array}.sv,
// bound in by testbenches rather than embedded in the synthesizable RTL
// (see verif/sva/sram_sva.sv for the same convention).
module matrix_engine_ctrl_sva #(
    parameter int ROWS      = 4,
    parameter int COLS      = 4,
    parameter int DIM_WIDTH = 9
) (
    input logic clk,
    input logic rst_n,
    input logic start,
    input logic [DIM_WIDTH-1:0] dim_k,
    input logic [DIM_WIDTH-1:0] dim_n,
    input logic busy,
    input logic done,
    input logic [ROWS-1:0] arr_weight_load_row
);

  a_done_pulses_one_cycle :
  assert property (@(posedge clk) disable iff (!rst_n) done |=> !done);

  a_weight_load_at_most_one_row :
  assert property (@(posedge clk) disable iff (!rst_n) $onehot0(arr_weight_load_row));

  a_start_dims_in_range :
  assert property (@(posedge clk) disable iff (!rst_n)
      start |-> (dim_k <= DIM_WIDTH'(ROWS)) && (dim_n <= DIM_WIDTH'(COLS)))
  else $error("matrix_engine: start asserted with dim_k/dim_n exceeding the array size");

  a_no_start_while_busy :
  assert property (@(posedge clk) disable iff (!rst_n) (start && busy) |-> !done)
  else $error("matrix_engine: start while busy should not also be completing this cycle");

endmodule

bind matrix_engine_ctrl matrix_engine_ctrl_sva #(
    .ROWS     (ROWS),
    .COLS     (COLS),
    .DIM_WIDTH(DIM_WIDTH)
) u_matrix_engine_ctrl_sva (
    .clk                 (clk),
    .rst_n               (rst_n),
    .start               (start),
    .dim_k               (dim_k),
    .dim_n               (dim_n),
    .busy                (busy),
    .done                (done),
    .arr_weight_load_row (arr_weight_load_row)
);

module mac_array_sva #(
    parameter int COLS        = 4,
    parameter int ACCUM_WIDTH = 32
) (
    input logic clk,
    input logic [COLS-1:0] result_valid,
    input logic signed [ACCUM_WIDTH-1:0] result[COLS]
);

  for (genvar c = 0; c < COLS; c++) begin : g_result_known
    a_result_known_when_valid :
    assert property (@(posedge clk) result_valid[c] |-> !$isunknown(result[c]));
  end

endmodule

bind mac_array mac_array_sva #(
    .COLS       (COLS),
    .ACCUM_WIDTH(ACCUM_WIDTH)
) u_mac_array_sva (
    .clk         (clk),
    .result_valid(result_valid),
    .result      (result)
);
