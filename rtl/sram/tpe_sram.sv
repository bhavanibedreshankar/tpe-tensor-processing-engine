// Local SRAM (scratchpad). Dual-port, sized from tpe_pkg parameters
// (default 4096 x 128b = 64KB). Port A is intended for DMA fill/drain,
// port B for the Matrix Compute Engine's input/output buffers (see
// docs/architecture/tpe_architecture_spec.md section 3.4), but the RTL
// itself is symmetric -- either side can use either port. Deliberately a
// thin wrapper: all storage/timing behavior lives in the reusable
// rtl/common/dp_ram.sv so its documented read/write semantics apply here
// unchanged.
module tpe_sram
  import tpe_pkg::*;
(
    input  logic                        clk,

    // Port A
    input  logic                        a_en,
    input  logic                        a_we,
    input  logic [SRAM_STRB_WIDTH-1:0]  a_strb,
    input  logic [SRAM_ADDR_WIDTH-1:0]  a_addr,
    input  logic [SRAM_DATA_WIDTH-1:0]  a_wdata,
    output logic [SRAM_DATA_WIDTH-1:0]  a_rdata,

    // Port B
    input  logic                        b_en,
    input  logic                        b_we,
    input  logic [SRAM_STRB_WIDTH-1:0]  b_strb,
    input  logic [SRAM_ADDR_WIDTH-1:0]  b_addr,
    input  logic [SRAM_DATA_WIDTH-1:0]  b_wdata,
    output logic [SRAM_DATA_WIDTH-1:0]  b_rdata
);

  dp_ram #(
      .DATA_WIDTH(SRAM_DATA_WIDTH),
      .DEPTH     (SRAM_DEPTH),
      .ADDR_WIDTH(SRAM_ADDR_WIDTH),
      .STRB_WIDTH(SRAM_STRB_WIDTH)
  ) u_dp_ram (
      .clk    (clk),
      .a_en   (a_en),
      .a_we   (a_we),
      .a_strb (a_strb),
      .a_addr (a_addr),
      .a_wdata(a_wdata),
      .a_rdata(a_rdata),
      .b_en   (b_en),
      .b_we   (b_we),
      .b_strb (b_strb),
      .b_addr (b_addr),
      .b_wdata(b_wdata),
      .b_rdata(b_rdata)
  );

endmodule
