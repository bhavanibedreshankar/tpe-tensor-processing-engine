// Single-clock synchronous FIFO, parametrized width/depth.
// Registered read data (data valid the cycle after rd_en, matching
// standard show-ahead-free BRAM-inferrable FIFOs). Protocol checks live in
// verif/sva/common_sva.sv (bound in per-instance by the testbench), not
// here -- this file is pure synthesizable RTL.
module sync_fifo #(
    parameter int DATA_WIDTH  = 32,
    parameter int DEPTH       = 16,
    parameter int ADDR_WIDTH  = $clog2(DEPTH)
) (
    input  logic                   clk,
    input  logic                   rst_n,

    input  logic                   wr_en,
    input  logic [DATA_WIDTH-1:0]  wr_data,
    output logic                   full,

    input  logic                   rd_en,
    output logic [DATA_WIDTH-1:0]  rd_data,
    output logic                   rd_valid,
    output logic                   empty,

    output logic [ADDR_WIDTH:0]    count
);

  logic [DATA_WIDTH-1:0] mem [DEPTH];
  logic [ADDR_WIDTH:0]   wr_ptr, rd_ptr;
  logic [ADDR_WIDTH:0]   count_q;

  assign full  = (count_q == DEPTH[ADDR_WIDTH:0]);
  assign empty = (count_q == '0);
  assign count = count_q;

  wire do_write = wr_en && !full;
  wire do_read  = rd_en && !empty;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      wr_ptr  <= '0;
      rd_ptr  <= '0;
      count_q <= '0;
    end else begin
      if (do_write) begin
        mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
        wr_ptr <= wr_ptr + 1'b1;
      end
      if (do_read) begin
        rd_ptr <= rd_ptr + 1'b1;
      end
      case ({do_write, do_read})
        2'b10:   count_q <= count_q + 1'b1;
        2'b01:   count_q <= count_q - 1'b1;
        default: count_q <= count_q;
      endcase
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      rd_data  <= '0;
      rd_valid <= 1'b0;
    end else begin
      rd_valid <= do_read;
      if (do_read) begin
        rd_data <= mem[rd_ptr[ADDR_WIDTH-1:0]];
      end
    end
  end

  // ---- Debug logging (see rtl/include/tpe_verbosity.svh) -----------------
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      // no state to reset -- debug prints only
    end else begin
      if (wr_en && full) begin
        `TPE_LOG_LOW("sync_fifo", "write attempted while full, dropped");
      end
      if (do_write) begin
        `TPE_LOG_DEBUG("sync_fifo", $sformatf("push count=%0d/%0d", count_q + 1'b1, DEPTH));
      end
      if (do_read) begin
        `TPE_LOG_DEBUG("sync_fifo", $sformatf("pop count=%0d/%0d", count_q - 1'b1, DEPTH));
      end
    end
  end

endmodule
