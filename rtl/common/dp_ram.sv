// Generic synchronous true dual-port RAM with per-byte write enables.
// Two fully independent ports, each registered read (1-cycle latency),
// modeling standard synthesizable BRAM inference. Used as the storage
// element inside the Local SRAM scratchpad and reusable anywhere else a
// dual-port memory is needed. Pure synthesizable RTL; no assertions here.
module dp_ram #(
    parameter int DATA_WIDTH = 128,
    parameter int DEPTH      = 4096,
    parameter int ADDR_WIDTH = $clog2(DEPTH),
    parameter int STRB_WIDTH = DATA_WIDTH / 8
) (
    input  logic                    clk,

    // Port A
    input  logic                    a_en,
    input  logic                    a_we,
    input  logic [STRB_WIDTH-1:0]   a_strb,
    input  logic [ADDR_WIDTH-1:0]   a_addr,
    input  logic [DATA_WIDTH-1:0]   a_wdata,
    output logic [DATA_WIDTH-1:0]   a_rdata,

    // Port B
    input  logic                    b_en,
    input  logic                    b_we,
    input  logic [STRB_WIDTH-1:0]   b_strb,
    input  logic [ADDR_WIDTH-1:0]   b_addr,
    input  logic [DATA_WIDTH-1:0]   b_wdata,
    output logic [DATA_WIDTH-1:0]   b_rdata
);

  logic [DATA_WIDTH-1:0] mem [DEPTH];

  always_ff @(posedge clk) begin
    if (a_en) begin
      if (a_we) begin
        for (int unsigned i = 0; i < STRB_WIDTH; i++) begin
          if (a_strb[i]) mem[a_addr][i*8 +: 8] <= a_wdata[i*8 +: 8];
        end
      end
      a_rdata <= mem[a_addr];
    end
  end

  always_ff @(posedge clk) begin
    if (b_en) begin
      if (b_we) begin
        for (int unsigned i = 0; i < STRB_WIDTH; i++) begin
          if (b_strb[i]) mem[b_addr][i*8 +: 8] <= b_wdata[i*8 +: 8];
        end
      end
      b_rdata <= mem[b_addr];
    end
  end

endmodule
