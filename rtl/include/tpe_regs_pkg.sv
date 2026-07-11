// GENERATED FILE -- DO NOT EDIT.
// Source of truth: docs/register_map/tpe_regs.yaml
// Regenerate with: make regmap  (or python3 tools/regmap_gen.py)
package tpe_regs_pkg;


  // -------------------------------------------------------------------
  // CP block -- base 0x0000
  // Command Processor -- control/status and command staging.
  // -------------------------------------------------------------------
  localparam logic [15:0] CP_BASE_ADDR = 16'h0000;

  localparam logic [15:0] CP_VERSION_ADDR    = 16'h0000;
  localparam logic [15:0] CP_VERSION_OFFSET  = 16'h0000;
  localparam logic [31:0] CP_VERSION_RESET   = 32'h00010000;

  localparam int CP_VERSION_MINOR_MSB = 15;
  localparam int CP_VERSION_MINOR_LSB = 0;

  localparam int CP_VERSION_MAJOR_MSB = 31;
  localparam int CP_VERSION_MAJOR_LSB = 16;


  localparam logic [15:0] CP_CTRL_ADDR    = 16'h0004;
  localparam logic [15:0] CP_CTRL_OFFSET  = 16'h0004;
  localparam logic [31:0] CP_CTRL_RESET   = 32'h00000000;

  localparam int CP_CTRL_ENABLE_MSB = 0;
  localparam int CP_CTRL_ENABLE_LSB = 0;

  localparam int CP_CTRL_SOFT_RESET_MSB = 1;
  localparam int CP_CTRL_SOFT_RESET_LSB = 1;


  localparam logic [15:0] CP_STATUS_ADDR    = 16'h0008;
  localparam logic [15:0] CP_STATUS_OFFSET  = 16'h0008;
  localparam logic [31:0] CP_STATUS_RESET   = 32'h00000004;

  localparam int CP_STATUS_BUSY_MSB = 0;
  localparam int CP_STATUS_BUSY_LSB = 0;

  localparam int CP_STATUS_CMD_FIFO_FULL_MSB = 1;
  localparam int CP_STATUS_CMD_FIFO_FULL_LSB = 1;

  localparam int CP_STATUS_CMD_FIFO_EMPTY_MSB = 2;
  localparam int CP_STATUS_CMD_FIFO_EMPTY_LSB = 2;

  localparam int CP_STATUS_ERROR_MSB = 3;
  localparam int CP_STATUS_ERROR_LSB = 3;

  localparam int CP_STATUS_LAST_STATUS_MSB = 6;
  localparam int CP_STATUS_LAST_STATUS_LSB = 4;


  localparam logic [15:0] CP_CMD_OPCODE_TAG_ADDR    = 16'h0010;
  localparam logic [15:0] CP_CMD_OPCODE_TAG_OFFSET  = 16'h0010;
  localparam logic [31:0] CP_CMD_OPCODE_TAG_RESET   = 32'h00000000;

  localparam int CP_CMD_OPCODE_TAG_OPCODE_MSB = 3;
  localparam int CP_CMD_OPCODE_TAG_OPCODE_LSB = 0;

  localparam int CP_CMD_OPCODE_TAG_TAG_MSB = 15;
  localparam int CP_CMD_OPCODE_TAG_TAG_LSB = 4;


  localparam logic [15:0] CP_CMD_SRAM_ADDR_ADDR    = 16'h0014;
  localparam logic [15:0] CP_CMD_SRAM_ADDR_OFFSET  = 16'h0014;
  localparam logic [31:0] CP_CMD_SRAM_ADDR_RESET   = 32'h00000000;


  localparam logic [15:0] CP_CMD_MEM_ADDR_ADDR    = 16'h0018;
  localparam logic [15:0] CP_CMD_MEM_ADDR_OFFSET  = 16'h0018;
  localparam logic [31:0] CP_CMD_MEM_ADDR_RESET   = 32'h00000000;


  localparam logic [15:0] CP_CMD_DIM_MK_ADDR    = 16'h001c;
  localparam logic [15:0] CP_CMD_DIM_MK_OFFSET  = 16'h001c;
  localparam logic [31:0] CP_CMD_DIM_MK_RESET   = 32'h00000000;

  localparam int CP_CMD_DIM_MK_DIM_M_MSB = 15;
  localparam int CP_CMD_DIM_MK_DIM_M_LSB = 0;

  localparam int CP_CMD_DIM_MK_DIM_K_MSB = 31;
  localparam int CP_CMD_DIM_MK_DIM_K_LSB = 16;


  localparam logic [15:0] CP_CMD_DIM_N_ADDR    = 16'h0020;
  localparam logic [15:0] CP_CMD_DIM_N_OFFSET  = 16'h0020;
  localparam logic [31:0] CP_CMD_DIM_N_RESET   = 32'h00000000;

  localparam int CP_CMD_DIM_N_DIM_N_MSB = 15;
  localparam int CP_CMD_DIM_N_DIM_N_LSB = 0;


  localparam logic [15:0] CP_CMD_PUSH_ADDR    = 16'h0024;
  localparam logic [15:0] CP_CMD_PUSH_OFFSET  = 16'h0024;
  localparam logic [31:0] CP_CMD_PUSH_RESET   = 32'h00000000;

  localparam int CP_CMD_PUSH_PUSH_MSB = 0;
  localparam int CP_CMD_PUSH_PUSH_LSB = 0;


  localparam logic [15:0] CP_IRQ_STATUS_ADDR    = 16'h0030;
  localparam logic [15:0] CP_IRQ_STATUS_OFFSET  = 16'h0030;
  localparam logic [31:0] CP_IRQ_STATUS_RESET   = 32'h00000000;

  localparam int CP_IRQ_STATUS_CMD_DONE_MSB = 0;
  localparam int CP_IRQ_STATUS_CMD_DONE_LSB = 0;

  localparam int CP_IRQ_STATUS_CMD_ERROR_MSB = 1;
  localparam int CP_IRQ_STATUS_CMD_ERROR_LSB = 1;


  localparam logic [15:0] CP_IRQ_ENABLE_ADDR    = 16'h0034;
  localparam logic [15:0] CP_IRQ_ENABLE_OFFSET  = 16'h0034;
  localparam logic [31:0] CP_IRQ_ENABLE_RESET   = 32'h00000000;

  localparam int CP_IRQ_ENABLE_CMD_DONE_EN_MSB = 0;
  localparam int CP_IRQ_ENABLE_CMD_DONE_EN_LSB = 0;

  localparam int CP_IRQ_ENABLE_CMD_ERROR_EN_MSB = 1;
  localparam int CP_IRQ_ENABLE_CMD_ERROR_EN_LSB = 1;



  // -------------------------------------------------------------------
  // DMA block -- base 0x1000
  // DMA Engine -- descriptor-based DDR <-> SRAM mover.
  // -------------------------------------------------------------------
  localparam logic [15:0] DMA_BASE_ADDR = 16'h1000;

  localparam logic [15:0] DMA_CTRL_ADDR    = 16'h1000;
  localparam logic [15:0] DMA_CTRL_OFFSET  = 16'h0000;
  localparam logic [31:0] DMA_CTRL_RESET   = 32'h00000000;

  localparam int DMA_CTRL_ENABLE_MSB = 0;
  localparam int DMA_CTRL_ENABLE_LSB = 0;


  localparam logic [15:0] DMA_STATUS_ADDR    = 16'h1004;
  localparam logic [15:0] DMA_STATUS_OFFSET  = 16'h0004;
  localparam logic [31:0] DMA_STATUS_RESET   = 32'h00000001;

  localparam int DMA_STATUS_IDLE_MSB = 0;
  localparam int DMA_STATUS_IDLE_LSB = 0;

  localparam int DMA_STATUS_ERROR_MSB = 1;
  localparam int DMA_STATUS_ERROR_LSB = 1;


  localparam logic [15:0] DMA_DESC_MEM_ADDR_ADDR    = 16'h1010;
  localparam logic [15:0] DMA_DESC_MEM_ADDR_OFFSET  = 16'h0010;
  localparam logic [31:0] DMA_DESC_MEM_ADDR_RESET   = 32'h00000000;


  localparam logic [15:0] DMA_DESC_SRAM_ADDR_ADDR    = 16'h1014;
  localparam logic [15:0] DMA_DESC_SRAM_ADDR_OFFSET  = 16'h0014;
  localparam logic [31:0] DMA_DESC_SRAM_ADDR_RESET   = 32'h00000000;


  localparam logic [15:0] DMA_DESC_LEN_ADDR    = 16'h1018;
  localparam logic [15:0] DMA_DESC_LEN_OFFSET  = 16'h0018;
  localparam logic [31:0] DMA_DESC_LEN_RESET   = 32'h00000000;


  localparam logic [15:0] DMA_DESC_CTRL_ADDR    = 16'h101c;
  localparam logic [15:0] DMA_DESC_CTRL_OFFSET  = 16'h001c;
  localparam logic [31:0] DMA_DESC_CTRL_RESET   = 32'h00000000;

  localparam int DMA_DESC_CTRL_DIR_MSB = 0;
  localparam int DMA_DESC_CTRL_DIR_LSB = 0;

  localparam int DMA_DESC_CTRL_START_MSB = 1;
  localparam int DMA_DESC_CTRL_START_LSB = 1;



  // -------------------------------------------------------------------
  // MATRIX_ENGINE block -- base 0x2000
  // Matrix Compute Engine (MAC array + accumulator) configuration.
  // -------------------------------------------------------------------
  localparam logic [15:0] MATRIX_ENGINE_BASE_ADDR = 16'h2000;

  localparam logic [15:0] MATRIX_ENGINE_CTRL_ADDR    = 16'h2000;
  localparam logic [15:0] MATRIX_ENGINE_CTRL_OFFSET  = 16'h0000;
  localparam logic [31:0] MATRIX_ENGINE_CTRL_RESET   = 32'h00000000;

  localparam int MATRIX_ENGINE_CTRL_START_MSB = 0;
  localparam int MATRIX_ENGINE_CTRL_START_LSB = 0;


  localparam logic [15:0] MATRIX_ENGINE_STATUS_ADDR    = 16'h2004;
  localparam logic [15:0] MATRIX_ENGINE_STATUS_OFFSET  = 16'h0004;
  localparam logic [31:0] MATRIX_ENGINE_STATUS_RESET   = 32'h00000001;

  localparam int MATRIX_ENGINE_STATUS_IDLE_MSB = 0;
  localparam int MATRIX_ENGINE_STATUS_IDLE_LSB = 0;

  localparam int MATRIX_ENGINE_STATUS_OVERFLOW_STICKY_MSB = 1;
  localparam int MATRIX_ENGINE_STATUS_OVERFLOW_STICKY_LSB = 1;


  localparam logic [15:0] MATRIX_ENGINE_DIM_MK_ADDR    = 16'h2010;
  localparam logic [15:0] MATRIX_ENGINE_DIM_MK_OFFSET  = 16'h0010;
  localparam logic [31:0] MATRIX_ENGINE_DIM_MK_RESET   = 32'h00000000;

  localparam int MATRIX_ENGINE_DIM_MK_DIM_M_MSB = 15;
  localparam int MATRIX_ENGINE_DIM_MK_DIM_M_LSB = 0;

  localparam int MATRIX_ENGINE_DIM_MK_DIM_K_MSB = 31;
  localparam int MATRIX_ENGINE_DIM_MK_DIM_K_LSB = 16;


  localparam logic [15:0] MATRIX_ENGINE_DIM_N_ADDR    = 16'h2014;
  localparam logic [15:0] MATRIX_ENGINE_DIM_N_OFFSET  = 16'h0014;
  localparam logic [31:0] MATRIX_ENGINE_DIM_N_RESET   = 32'h00000000;

  localparam int MATRIX_ENGINE_DIM_N_DIM_N_MSB = 15;
  localparam int MATRIX_ENGINE_DIM_N_DIM_N_LSB = 0;



  // -------------------------------------------------------------------
  // PMU block -- base 0x3000
  // Performance Monitor Unit -- free-running event counters.
  // -------------------------------------------------------------------
  localparam logic [15:0] PMU_BASE_ADDR = 16'h3000;

  localparam logic [15:0] PMU_CTRL_ADDR    = 16'h3000;
  localparam logic [15:0] PMU_CTRL_OFFSET  = 16'h0000;
  localparam logic [31:0] PMU_CTRL_RESET   = 32'h00000000;

  localparam int PMU_CTRL_ENABLE_MSB = 0;
  localparam int PMU_CTRL_ENABLE_LSB = 0;

  localparam int PMU_CTRL_RESET_COUNTERS_MSB = 1;
  localparam int PMU_CTRL_RESET_COUNTERS_LSB = 1;


  localparam logic [15:0] PMU_CYCLE_COUNT_ADDR    = 16'h3010;
  localparam logic [15:0] PMU_CYCLE_COUNT_OFFSET  = 16'h0010;
  localparam logic [31:0] PMU_CYCLE_COUNT_RESET   = 32'h00000000;


  localparam logic [15:0] PMU_MAC_ACTIVE_COUNT_ADDR    = 16'h3014;
  localparam logic [15:0] PMU_MAC_ACTIVE_COUNT_OFFSET  = 16'h0014;
  localparam logic [31:0] PMU_MAC_ACTIVE_COUNT_RESET   = 32'h00000000;


  localparam logic [15:0] PMU_DMA_WAIT_COUNT_ADDR    = 16'h3018;
  localparam logic [15:0] PMU_DMA_WAIT_COUNT_OFFSET  = 16'h0018;
  localparam logic [31:0] PMU_DMA_WAIT_COUNT_RESET   = 32'h00000000;


  localparam logic [15:0] PMU_SCHED_STALL_COUNT_ADDR    = 16'h301c;
  localparam logic [15:0] PMU_SCHED_STALL_COUNT_OFFSET  = 16'h001c;
  localparam logic [31:0] PMU_SCHED_STALL_COUNT_RESET   = 32'h00000000;


  localparam logic [15:0] PMU_IDLE_COUNT_ADDR    = 16'h3020;
  localparam logic [15:0] PMU_IDLE_COUNT_OFFSET  = 16'h0020;
  localparam logic [31:0] PMU_IDLE_COUNT_RESET   = 32'h00000000;


  localparam logic [15:0] PMU_CMD_LATENCY_LAST_ADDR    = 16'h3024;
  localparam logic [15:0] PMU_CMD_LATENCY_LAST_OFFSET  = 16'h0024;
  localparam logic [31:0] PMU_CMD_LATENCY_LAST_RESET   = 32'h00000000;



  // -------------------------------------------------------------------
  // DEBUG block -- base 0x4000
  // Debug infrastructure -- command trace buffer and error capture.
  // -------------------------------------------------------------------
  localparam logic [15:0] DEBUG_BASE_ADDR = 16'h4000;

  localparam logic [15:0] DEBUG_CTRL_ADDR    = 16'h4000;
  localparam logic [15:0] DEBUG_CTRL_OFFSET  = 16'h0000;
  localparam logic [31:0] DEBUG_CTRL_RESET   = 32'h00000000;

  localparam int DEBUG_CTRL_TRACE_ENABLE_MSB = 0;
  localparam int DEBUG_CTRL_TRACE_ENABLE_LSB = 0;


  localparam logic [15:0] DEBUG_TRACE_STATUS_ADDR    = 16'h4004;
  localparam logic [15:0] DEBUG_TRACE_STATUS_OFFSET  = 16'h0004;
  localparam logic [31:0] DEBUG_TRACE_STATUS_RESET   = 32'h00000000;

  localparam int DEBUG_TRACE_STATUS_TRACE_EMPTY_MSB = 0;
  localparam int DEBUG_TRACE_STATUS_TRACE_EMPTY_LSB = 0;

  localparam int DEBUG_TRACE_STATUS_TRACE_FULL_MSB = 1;
  localparam int DEBUG_TRACE_STATUS_TRACE_FULL_LSB = 1;

  localparam int DEBUG_TRACE_STATUS_TRACE_COUNT_MSB = 12;
  localparam int DEBUG_TRACE_STATUS_TRACE_COUNT_LSB = 2;


  localparam logic [15:0] DEBUG_TRACE_RDATA_ADDR    = 16'h4008;
  localparam logic [15:0] DEBUG_TRACE_RDATA_OFFSET  = 16'h0008;
  localparam logic [31:0] DEBUG_TRACE_RDATA_RESET   = 32'h00000000;


  localparam logic [15:0] DEBUG_ERROR_CODE_ADDR    = 16'h4010;
  localparam logic [15:0] DEBUG_ERROR_CODE_OFFSET  = 16'h0010;
  localparam logic [31:0] DEBUG_ERROR_CODE_RESET   = 32'h00000000;


  localparam logic [15:0] DEBUG_ERROR_TAG_ADDR    = 16'h4014;
  localparam logic [15:0] DEBUG_ERROR_TAG_OFFSET  = 16'h0014;
  localparam logic [31:0] DEBUG_ERROR_TAG_RESET   = 32'h00000000;




endpackage : tpe_regs_pkg
