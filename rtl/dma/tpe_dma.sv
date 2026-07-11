// DMA Engine: descriptor-based mover between DDR (AXI4 master) and the
// Local SRAM scratchpad, per docs/architecture/tpe_architecture_spec.md
// section 3.3. V1 scope: single channel, one descriptor in flight at a
// time, INCR bursts capped at MAX_BURST_BEATS beats, transfer length must
// be a whole number of AXI_DATA_WIDTH-wide rows (16 bytes) -- this DMA
// moves whole SRAM rows, it does not do sub-row byte-strobe transfers.
//
// One AXI4 beat == one SRAM row (both AXI_DATA_WIDTH and SRAM_DATA_WIDTH
// are 128b, see rtl/include/tpe_pkg.sv), so each beat maps 1:1 to an
// incrementing SRAM address with no width conversion needed.
module tpe_dma
  import tpe_pkg::*;
#(
    parameter int MAX_BURST_BEATS = 16,
    parameter int LEN_WIDTH       = 20  // bytes; must cover MAX_TILE_DIM-scale transfers
) (
    input logic clk,
    input logic rst_n,

    // Descriptor control (matches the dma register block)
    input  logic [AXI_ADDR_WIDTH-1:0]  desc_mem_addr,
    input  logic [SRAM_ADDR_WIDTH-1:0] desc_sram_addr,
    input  logic [LEN_WIDTH-1:0]       desc_len,
    input  logic                       desc_dir,  // 0 = DDR->SRAM, 1 = SRAM->DDR
    input  logic                       start,
    output logic                       busy,
    output logic                       done,
    output logic                       error,

    // AXI4 master -- write address/data/response
    output logic                          m_awvalid,
    output logic [   AXI_ADDR_WIDTH-1:0]  m_awaddr,
    output logic [                  7:0]  m_awlen,
    output logic [    AXI_ID_WIDTH-1:0]   m_awid,
    input  logic                          m_awready,
    output logic                          m_wvalid,
    output logic [   AXI_DATA_WIDTH-1:0]  m_wdata,
    output logic [   AXI_STRB_WIDTH-1:0]  m_wstrb,
    output logic                          m_wlast,
    input  logic                          m_wready,
    input  logic                          m_bvalid,
    input  logic [                  1:0]  m_bresp,
    input  logic [    AXI_ID_WIDTH-1:0]   m_bid,
    output logic                          m_bready,

    // AXI4 master -- read address/data
    output logic                         m_arvalid,
    output logic [  AXI_ADDR_WIDTH-1:0]  m_araddr,
    output logic [                 7:0]  m_arlen,
    output logic [   AXI_ID_WIDTH-1:0]   m_arid,
    input  logic                         m_arready,
    input  logic                         m_rvalid,
    input  logic [  AXI_DATA_WIDTH-1:0]  m_rdata,
    input  logic [                 1:0]  m_rresp,
    input  logic                         m_rlast,
    input  logic [   AXI_ID_WIDTH-1:0]   m_rid,
    output logic                         m_rready,

    // SRAM-side port (dp_ram port convention)
    output logic                        sram_en,
    output logic                        sram_we,
    output logic [SRAM_STRB_WIDTH-1:0]  sram_strb,
    output logic [SRAM_ADDR_WIDTH-1:0]  sram_addr,
    output logic [SRAM_DATA_WIDTH-1:0]  sram_wdata,
    input  logic [SRAM_DATA_WIDTH-1:0]  sram_rdata
);

  localparam int BeatBytes = AXI_DATA_WIDTH / 8;  // 16
  localparam int BeatShift = $clog2(BeatBytes);
  localparam int BeatsWidth = LEN_WIDTH - BeatShift + 1;

  typedef enum logic [3:0] {
    ST_IDLE,
    ST_DECODE,
    ST_RD_ADDR,
    ST_RD_DATA,
    ST_WR_ADDR,
    ST_WR_SRAM_RD,
    ST_WR_DATA,
    ST_WR_RESP,
    ST_DONE,
    ST_ERROR
  } state_e;

  state_e state_q, state_d;

  logic [AXI_ADDR_WIDTH-1:0] mem_addr_q;
  logic [SRAM_ADDR_WIDTH-1:0] sram_addr_q;
  logic [BeatsWidth-1:0] beats_remaining_q;
  logic [7:0] burst_beats_left_q;
  logic dir_q;

  wire [7:0] burst_beats_this = (beats_remaining_q > BeatsWidth'(MAX_BURST_BEATS))
      ? 8'(MAX_BURST_BEATS) : 8'(beats_remaining_q);
  wire len_misaligned = |desc_len[BeatShift-1:0];

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      state_q            <= ST_IDLE;
      mem_addr_q         <= '0;
      sram_addr_q        <= '0;
      beats_remaining_q  <= '0;
      burst_beats_left_q <= '0;
      dir_q              <= 1'b0;
    end else begin
      state_q <= state_d;

      case (state_q)
        ST_IDLE: begin
          if (start) begin
            mem_addr_q        <= desc_mem_addr;
            sram_addr_q       <= desc_sram_addr;
            beats_remaining_q <= BeatsWidth'(desc_len[LEN_WIDTH-1:BeatShift]);
            dir_q             <= desc_dir;
          end
        end

        ST_DECODE: begin
          burst_beats_left_q <= burst_beats_this;
        end

        ST_RD_DATA: begin
          if (m_rvalid && m_rready) begin
            mem_addr_q         <= mem_addr_q + AXI_ADDR_WIDTH'(BeatBytes);
            sram_addr_q        <= sram_addr_q + 1'b1;
            beats_remaining_q  <= beats_remaining_q - 1'b1;
            burst_beats_left_q <= burst_beats_left_q - 1'b1;
          end
        end

        ST_WR_DATA: begin
          if (m_wvalid && m_wready) begin
            mem_addr_q         <= mem_addr_q + AXI_ADDR_WIDTH'(BeatBytes);
            sram_addr_q        <= sram_addr_q + 1'b1;
            beats_remaining_q  <= beats_remaining_q - 1'b1;
            burst_beats_left_q <= burst_beats_left_q - 1'b1;
          end
        end

        default: ;
      endcase
    end
  end

  always_comb begin
    state_d = state_q;
    case (state_q)
      ST_IDLE:      if (start) state_d = len_misaligned ? ST_ERROR : ST_DECODE;
      ST_DECODE:    state_d = dir_q ? ST_WR_ADDR : ST_RD_ADDR;
      ST_RD_ADDR:   if (m_arvalid && m_arready) state_d = ST_RD_DATA;
      ST_RD_DATA:   if (m_rvalid && m_rready && m_rlast) begin
        state_d = (beats_remaining_q == BeatsWidth'(1)) ? ST_DONE : ST_DECODE;
      end
      ST_WR_ADDR:   if (m_awvalid && m_awready) state_d = ST_WR_SRAM_RD;
      ST_WR_SRAM_RD: state_d = ST_WR_DATA;
      ST_WR_DATA:   if (m_wvalid && m_wready) begin
        if (burst_beats_left_q == 8'd1) state_d = ST_WR_RESP;
        else state_d = ST_WR_SRAM_RD;
      end
      ST_WR_RESP:   if (m_bvalid && m_bready) begin
        state_d = (beats_remaining_q <= BeatsWidth'(1)) ? ST_DONE : ST_DECODE;
      end
      ST_DONE:      state_d = ST_IDLE;
      ST_ERROR:     state_d = ST_IDLE;
      default:      state_d = ST_IDLE;
    endcase
  end

  assign busy  = (state_q != ST_IDLE);
  assign done  = (state_q == ST_DONE);
  assign error = (state_q == ST_ERROR);

  // ---- AXI4 read channel -----------------------------------------------
  assign m_arvalid = (state_q == ST_RD_ADDR);
  assign m_araddr  = mem_addr_q;
  assign m_arlen   = burst_beats_this - 8'd1;
  assign m_arid    = '0;
  assign m_rready  = (state_q == ST_RD_DATA);

  // ---- AXI4 write channel -----------------------------------------------
  assign m_awvalid = (state_q == ST_WR_ADDR);
  assign m_awaddr  = mem_addr_q;
  assign m_awlen   = burst_beats_this - 8'd1;
  assign m_awid    = '0;
  assign m_wvalid  = (state_q == ST_WR_DATA);
  // dp_ram's own registered sram_rdata already holds the beat fetched in
  // the preceding ST_WR_SRAM_RD cycle stable until the next read is
  // issued -- no separate staging register needed (an earlier version
  // had one and it captured the *previous* beat's data one cycle early;
  // see the derivation in this file's git history / DMA testbench README
  // if this class of bug resurfaces elsewhere).
  assign m_wdata   = sram_rdata;
  assign m_wstrb   = {AXI_STRB_WIDTH{1'b1}};
  assign m_wlast   = (state_q == ST_WR_DATA) && (burst_beats_left_q == 8'd1);
  assign m_bready  = (state_q == ST_WR_RESP);

  // ---- SRAM-side port ----------------------------------------------------
  assign sram_addr  = sram_addr_q;
  assign sram_strb  = {SRAM_STRB_WIDTH{1'b1}};
  always_comb begin
    sram_en    = 1'b0;
    sram_we    = 1'b0;
    sram_wdata = '0;
    if (state_q == ST_RD_DATA && m_rvalid && m_rready) begin
      sram_en    = 1'b1;
      sram_we    = 1'b1;
      sram_wdata = m_rdata;
    end else if (state_q == ST_WR_SRAM_RD) begin
      sram_en = 1'b1;
      sram_we = 1'b0;
    end
  end

endmodule
