// RTL-side functional coverage for rtl/common/dp_ram.sv, bound in by
// testbenches (see docs/verification/coverage_plan.md section 1 for why
// this is separate from the TB-side cocotb-coverage sampling in
// verif/cocotb_tb/sram/test_sram.py -- this file covers hardware-state
// space, the Python side covers stimulus/scenario space).
module dp_ram_cov #(
    parameter int DATA_WIDTH = 128,
    parameter int ADDR_WIDTH = 12,
    parameter int STRB_WIDTH = DATA_WIDTH / 8
) (
    input logic clk,
    input logic a_en,
    input logic a_we,
    input logic [STRB_WIDTH-1:0] a_strb,
    input logic [ADDR_WIDTH-1:0] a_addr,
    input logic b_en,
    input logic b_we,
    input logic [STRB_WIDTH-1:0] b_strb,
    input logic [ADDR_WIDTH-1:0] b_addr
);

  localparam int unsigned MaxAddr = (1 << ADDR_WIDTH) - 1;

  covergroup cg_port_a @(posedge clk);
    option.per_instance = 1;

    cp_op: coverpoint {a_en, a_we} {
      bins idle  = {2'b00, 2'b01};
      bins read  = {2'b10};
      bins write = {2'b11};
    }
    cp_addr_region: coverpoint a_addr {
      bins low  = {[0 : MaxAddr/3]};
      bins mid  = {[MaxAddr/3+1 : 2*MaxAddr/3]};
      bins high = {[2*MaxAddr/3+1 : MaxAddr]};
    }
    cp_strb: coverpoint a_strb {
      bins zero    = {0};
      bins full    = {{STRB_WIDTH{1'b1}}};
      bins partial = default;
    }
    cx_op_addr: cross cp_op, cp_addr_region;
  endgroup

  covergroup cg_port_b @(posedge clk);
    option.per_instance = 1;
    cp_op: coverpoint {b_en, b_we} {
      bins idle  = {2'b00, 2'b01};
      bins read  = {2'b10};
      bins write = {2'b11};
    }
    cp_addr_region: coverpoint b_addr {
      bins low  = {[0 : MaxAddr/3]};
      bins mid  = {[MaxAddr/3+1 : 2*MaxAddr/3]};
      bins high = {[2*MaxAddr/3+1 : MaxAddr]};
    }
  endgroup

  cg_port_a cg_a_inst = new();
  cg_port_b cg_b_inst = new();

endmodule

bind dp_ram dp_ram_cov #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH),
    .STRB_WIDTH(STRB_WIDTH)
) u_dp_ram_cov (.*);
