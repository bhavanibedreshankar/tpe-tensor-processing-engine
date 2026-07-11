// Protocol checks for rtl/common/dp_ram.sv (and therefore rtl/sram/tpe_sram.sv,
// which instantiates it), bound in by testbenches rather than embedded in
// the synthesizable RTL. See rtl/common/dp_ram.sv's header comment for the
// documented same-address read-old-data behavior, which is NOT re-checked
// here (it's defined/intended); what IS checked is the cross-port
// same-cycle same-address write hazard the RTL explicitly leaves undefined
// and expects testbenches to avoid.
module dp_ram_sva #(
    parameter int DATA_WIDTH = 128,
    parameter int ADDR_WIDTH = 12
) (
    input logic clk,
    input logic a_en,
    input logic a_we,
    input logic [ADDR_WIDTH-1:0] a_addr,
    input logic [DATA_WIDTH-1:0] a_rdata,
    input logic b_en,
    input logic b_we,
    input logic [ADDR_WIDTH-1:0] b_addr,
    input logic [DATA_WIDTH-1:0] b_rdata
);

  a_no_dual_write_hazard :
  assert property (@(posedge clk)
      !(a_en && a_we && b_en && b_we && (a_addr == b_addr)))
  else $error("dp_ram: same-cycle same-address write on both ports (addr=%0d)", a_addr);

  a_rdata_known :
  assert property (@(posedge clk) a_en |=> !$isunknown(a_rdata));

  b_rdata_known :
  assert property (@(posedge clk) b_en |=> !$isunknown(b_rdata));

endmodule

bind dp_ram dp_ram_sva #(
    .DATA_WIDTH(DATA_WIDTH),
    .ADDR_WIDTH(ADDR_WIDTH)
) u_dp_ram_sva (.*);
