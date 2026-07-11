// RTL-side FSM + functional coverage for rtl/dma/tpe_dma.sv, bound in by
// testbenches (see docs/verification/coverage_plan.md section 1).
module tpe_dma_cov (
    input logic clk,
    input logic rst_n,
    input logic [3:0] state_q,
    input logic dir_q,
    input logic [7:0] burst_beats_left_q,
    input logic start,
    input logic desc_dir,
    input logic [19:0] desc_len
);

  logic [3:0] prev_state_q;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) prev_state_q <= 4'd0;
    else prev_state_q <= state_q;
  end

  covergroup cg_fsm @(posedge clk);
    option.per_instance = 1;
    cp_state: coverpoint state_q {
      bins idle       = {0};
      bins decode     = {1};
      bins rd_addr    = {2};
      bins rd_data    = {3};
      bins wr_addr    = {4};
      bins wr_sram_rd = {5};
      bins wr_data    = {6};
      bins wr_resp    = {7};
      bins done       = {8};
      bins error      = {9};
    }
    cp_arc: coverpoint {prev_state_q, state_q} {
      bins decode_to_rd = {{4'd1, 4'd2}};
      bins decode_to_wr = {{4'd1, 4'd4}};
      bins rd_multi_burst = {{4'd3, 4'd1}};  // RD_DATA -> DECODE (another burst follows)
      bins wr_multi_burst = {{4'd7, 4'd1}};  // WR_RESP -> DECODE
      bins other = default;
    }
  endgroup

  logic start_ev;
  assign start_ev = start;

  covergroup cg_desc @(posedge clk iff start_ev);
    option.per_instance = 1;
    cp_dir: coverpoint desc_dir;
    cp_len_rows: coverpoint desc_len[19:4] {
      bins one_row       = {1};
      bins sub_burst      = {[2:15]};    // fewer than MAX_BURST_BEATS
      bins exact_burst     = {16};
      bins multi_burst      = {[17:$]};  // spans more than one burst
    }
  endgroup

  covergroup cg_burst @(posedge clk);
    option.per_instance = 1;
    cp_burst_full: coverpoint (burst_beats_left_q == 8'd16);
  endgroup

  cg_fsm cg_fsm_inst = new();
  cg_desc cg_desc_inst = new();
  cg_burst cg_burst_inst = new();

endmodule

bind tpe_dma tpe_dma_cov u_tpe_dma_cov (
    .clk               (clk),
    .rst_n             (rst_n),
    .state_q           (state_q),
    .dir_q             (dir_q),
    .burst_beats_left_q(burst_beats_left_q),
    .start             (start),
    .desc_dir          (desc_dir),
    .desc_len          (desc_len)
);
