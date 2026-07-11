// GENERATED FILE -- DO NOT EDIT.
// Source of truth: docs/register_map/tpe_regs.yaml
// Regenerate with: make regmap  (or python3 tools/regmap_gen.py)
#pragma once
#include <cstdint>

namespace tpe::regs {


// ---------------------------------------------------------------------
// CP block -- base 0x0000
// Command Processor -- control/status and command staging.
// ---------------------------------------------------------------------
inline constexpr uint16_t CP_BASE_ADDR = 0x0000;

inline constexpr uint16_t CP_VERSION_ADDR = 0x0000;
inline constexpr uint32_t CP_VERSION_RESET = 0x00010000u;

inline constexpr uint32_t CP_VERSION_MINOR_MASK = 0x0000ffffu;
inline constexpr int CP_VERSION_MINOR_LSB = 0;

inline constexpr uint32_t CP_VERSION_MAJOR_MASK = 0xffff0000u;
inline constexpr int CP_VERSION_MAJOR_LSB = 16;


inline constexpr uint16_t CP_CTRL_ADDR = 0x0004;
inline constexpr uint32_t CP_CTRL_RESET = 0x00000000u;

inline constexpr uint32_t CP_CTRL_ENABLE_MASK = 0x00000001u;
inline constexpr int CP_CTRL_ENABLE_LSB = 0;

inline constexpr uint32_t CP_CTRL_SOFT_RESET_MASK = 0x00000002u;
inline constexpr int CP_CTRL_SOFT_RESET_LSB = 1;


inline constexpr uint16_t CP_STATUS_ADDR = 0x0008;
inline constexpr uint32_t CP_STATUS_RESET = 0x00000004u;

inline constexpr uint32_t CP_STATUS_BUSY_MASK = 0x00000001u;
inline constexpr int CP_STATUS_BUSY_LSB = 0;

inline constexpr uint32_t CP_STATUS_CMD_FIFO_FULL_MASK = 0x00000002u;
inline constexpr int CP_STATUS_CMD_FIFO_FULL_LSB = 1;

inline constexpr uint32_t CP_STATUS_CMD_FIFO_EMPTY_MASK = 0x00000004u;
inline constexpr int CP_STATUS_CMD_FIFO_EMPTY_LSB = 2;

inline constexpr uint32_t CP_STATUS_ERROR_MASK = 0x00000008u;
inline constexpr int CP_STATUS_ERROR_LSB = 3;

inline constexpr uint32_t CP_STATUS_LAST_STATUS_MASK = 0x00000070u;
inline constexpr int CP_STATUS_LAST_STATUS_LSB = 4;


inline constexpr uint16_t CP_CMD_OPCODE_TAG_ADDR = 0x0010;
inline constexpr uint32_t CP_CMD_OPCODE_TAG_RESET = 0x00000000u;

inline constexpr uint32_t CP_CMD_OPCODE_TAG_OPCODE_MASK = 0x0000000fu;
inline constexpr int CP_CMD_OPCODE_TAG_OPCODE_LSB = 0;

inline constexpr uint32_t CP_CMD_OPCODE_TAG_TAG_MASK = 0x0000fff0u;
inline constexpr int CP_CMD_OPCODE_TAG_TAG_LSB = 4;


inline constexpr uint16_t CP_CMD_SRAM_ADDR_ADDR = 0x0014;
inline constexpr uint32_t CP_CMD_SRAM_ADDR_RESET = 0x00000000u;


inline constexpr uint16_t CP_CMD_MEM_ADDR_ADDR = 0x0018;
inline constexpr uint32_t CP_CMD_MEM_ADDR_RESET = 0x00000000u;


inline constexpr uint16_t CP_CMD_DIM_MK_ADDR = 0x001c;
inline constexpr uint32_t CP_CMD_DIM_MK_RESET = 0x00000000u;

inline constexpr uint32_t CP_CMD_DIM_MK_DIM_M_MASK = 0x0000ffffu;
inline constexpr int CP_CMD_DIM_MK_DIM_M_LSB = 0;

inline constexpr uint32_t CP_CMD_DIM_MK_DIM_K_MASK = 0xffff0000u;
inline constexpr int CP_CMD_DIM_MK_DIM_K_LSB = 16;


inline constexpr uint16_t CP_CMD_DIM_N_ADDR = 0x0020;
inline constexpr uint32_t CP_CMD_DIM_N_RESET = 0x00000000u;

inline constexpr uint32_t CP_CMD_DIM_N_DIM_N_MASK = 0x0000ffffu;
inline constexpr int CP_CMD_DIM_N_DIM_N_LSB = 0;


inline constexpr uint16_t CP_CMD_PUSH_ADDR = 0x0024;
inline constexpr uint32_t CP_CMD_PUSH_RESET = 0x00000000u;

inline constexpr uint32_t CP_CMD_PUSH_PUSH_MASK = 0x00000001u;
inline constexpr int CP_CMD_PUSH_PUSH_LSB = 0;


inline constexpr uint16_t CP_IRQ_STATUS_ADDR = 0x0030;
inline constexpr uint32_t CP_IRQ_STATUS_RESET = 0x00000000u;

inline constexpr uint32_t CP_IRQ_STATUS_CMD_DONE_MASK = 0x00000001u;
inline constexpr int CP_IRQ_STATUS_CMD_DONE_LSB = 0;

inline constexpr uint32_t CP_IRQ_STATUS_CMD_ERROR_MASK = 0x00000002u;
inline constexpr int CP_IRQ_STATUS_CMD_ERROR_LSB = 1;


inline constexpr uint16_t CP_IRQ_ENABLE_ADDR = 0x0034;
inline constexpr uint32_t CP_IRQ_ENABLE_RESET = 0x00000000u;

inline constexpr uint32_t CP_IRQ_ENABLE_CMD_DONE_EN_MASK = 0x00000001u;
inline constexpr int CP_IRQ_ENABLE_CMD_DONE_EN_LSB = 0;

inline constexpr uint32_t CP_IRQ_ENABLE_CMD_ERROR_EN_MASK = 0x00000002u;
inline constexpr int CP_IRQ_ENABLE_CMD_ERROR_EN_LSB = 1;



// ---------------------------------------------------------------------
// DMA block -- base 0x1000
// DMA Engine -- descriptor-based DDR <-> SRAM mover.
// ---------------------------------------------------------------------
inline constexpr uint16_t DMA_BASE_ADDR = 0x1000;

inline constexpr uint16_t DMA_CTRL_ADDR = 0x1000;
inline constexpr uint32_t DMA_CTRL_RESET = 0x00000000u;

inline constexpr uint32_t DMA_CTRL_ENABLE_MASK = 0x00000001u;
inline constexpr int DMA_CTRL_ENABLE_LSB = 0;


inline constexpr uint16_t DMA_STATUS_ADDR = 0x1004;
inline constexpr uint32_t DMA_STATUS_RESET = 0x00000001u;

inline constexpr uint32_t DMA_STATUS_IDLE_MASK = 0x00000001u;
inline constexpr int DMA_STATUS_IDLE_LSB = 0;

inline constexpr uint32_t DMA_STATUS_ERROR_MASK = 0x00000002u;
inline constexpr int DMA_STATUS_ERROR_LSB = 1;


inline constexpr uint16_t DMA_DESC_MEM_ADDR_ADDR = 0x1010;
inline constexpr uint32_t DMA_DESC_MEM_ADDR_RESET = 0x00000000u;


inline constexpr uint16_t DMA_DESC_SRAM_ADDR_ADDR = 0x1014;
inline constexpr uint32_t DMA_DESC_SRAM_ADDR_RESET = 0x00000000u;


inline constexpr uint16_t DMA_DESC_LEN_ADDR = 0x1018;
inline constexpr uint32_t DMA_DESC_LEN_RESET = 0x00000000u;


inline constexpr uint16_t DMA_DESC_CTRL_ADDR = 0x101c;
inline constexpr uint32_t DMA_DESC_CTRL_RESET = 0x00000000u;

inline constexpr uint32_t DMA_DESC_CTRL_DIR_MASK = 0x00000001u;
inline constexpr int DMA_DESC_CTRL_DIR_LSB = 0;

inline constexpr uint32_t DMA_DESC_CTRL_START_MASK = 0x00000002u;
inline constexpr int DMA_DESC_CTRL_START_LSB = 1;



// ---------------------------------------------------------------------
// MATRIX_ENGINE block -- base 0x2000
// Matrix Compute Engine (MAC array + accumulator) configuration.
// ---------------------------------------------------------------------
inline constexpr uint16_t MATRIX_ENGINE_BASE_ADDR = 0x2000;

inline constexpr uint16_t MATRIX_ENGINE_CTRL_ADDR = 0x2000;
inline constexpr uint32_t MATRIX_ENGINE_CTRL_RESET = 0x00000000u;

inline constexpr uint32_t MATRIX_ENGINE_CTRL_START_MASK = 0x00000001u;
inline constexpr int MATRIX_ENGINE_CTRL_START_LSB = 0;


inline constexpr uint16_t MATRIX_ENGINE_STATUS_ADDR = 0x2004;
inline constexpr uint32_t MATRIX_ENGINE_STATUS_RESET = 0x00000001u;

inline constexpr uint32_t MATRIX_ENGINE_STATUS_IDLE_MASK = 0x00000001u;
inline constexpr int MATRIX_ENGINE_STATUS_IDLE_LSB = 0;

inline constexpr uint32_t MATRIX_ENGINE_STATUS_OVERFLOW_STICKY_MASK = 0x00000002u;
inline constexpr int MATRIX_ENGINE_STATUS_OVERFLOW_STICKY_LSB = 1;


inline constexpr uint16_t MATRIX_ENGINE_DIM_MK_ADDR = 0x2010;
inline constexpr uint32_t MATRIX_ENGINE_DIM_MK_RESET = 0x00000000u;

inline constexpr uint32_t MATRIX_ENGINE_DIM_MK_DIM_M_MASK = 0x0000ffffu;
inline constexpr int MATRIX_ENGINE_DIM_MK_DIM_M_LSB = 0;

inline constexpr uint32_t MATRIX_ENGINE_DIM_MK_DIM_K_MASK = 0xffff0000u;
inline constexpr int MATRIX_ENGINE_DIM_MK_DIM_K_LSB = 16;


inline constexpr uint16_t MATRIX_ENGINE_DIM_N_ADDR = 0x2014;
inline constexpr uint32_t MATRIX_ENGINE_DIM_N_RESET = 0x00000000u;

inline constexpr uint32_t MATRIX_ENGINE_DIM_N_DIM_N_MASK = 0x0000ffffu;
inline constexpr int MATRIX_ENGINE_DIM_N_DIM_N_LSB = 0;



// ---------------------------------------------------------------------
// PMU block -- base 0x3000
// Performance Monitor Unit -- free-running event counters.
// ---------------------------------------------------------------------
inline constexpr uint16_t PMU_BASE_ADDR = 0x3000;

inline constexpr uint16_t PMU_CTRL_ADDR = 0x3000;
inline constexpr uint32_t PMU_CTRL_RESET = 0x00000000u;

inline constexpr uint32_t PMU_CTRL_ENABLE_MASK = 0x00000001u;
inline constexpr int PMU_CTRL_ENABLE_LSB = 0;

inline constexpr uint32_t PMU_CTRL_RESET_COUNTERS_MASK = 0x00000002u;
inline constexpr int PMU_CTRL_RESET_COUNTERS_LSB = 1;


inline constexpr uint16_t PMU_CYCLE_COUNT_ADDR = 0x3010;
inline constexpr uint32_t PMU_CYCLE_COUNT_RESET = 0x00000000u;


inline constexpr uint16_t PMU_MAC_ACTIVE_COUNT_ADDR = 0x3014;
inline constexpr uint32_t PMU_MAC_ACTIVE_COUNT_RESET = 0x00000000u;


inline constexpr uint16_t PMU_DMA_WAIT_COUNT_ADDR = 0x3018;
inline constexpr uint32_t PMU_DMA_WAIT_COUNT_RESET = 0x00000000u;


inline constexpr uint16_t PMU_SCHED_STALL_COUNT_ADDR = 0x301c;
inline constexpr uint32_t PMU_SCHED_STALL_COUNT_RESET = 0x00000000u;


inline constexpr uint16_t PMU_IDLE_COUNT_ADDR = 0x3020;
inline constexpr uint32_t PMU_IDLE_COUNT_RESET = 0x00000000u;


inline constexpr uint16_t PMU_CMD_LATENCY_LAST_ADDR = 0x3024;
inline constexpr uint32_t PMU_CMD_LATENCY_LAST_RESET = 0x00000000u;



// ---------------------------------------------------------------------
// DEBUG block -- base 0x4000
// Debug infrastructure -- command trace buffer and error capture.
// ---------------------------------------------------------------------
inline constexpr uint16_t DEBUG_BASE_ADDR = 0x4000;

inline constexpr uint16_t DEBUG_CTRL_ADDR = 0x4000;
inline constexpr uint32_t DEBUG_CTRL_RESET = 0x00000000u;

inline constexpr uint32_t DEBUG_CTRL_TRACE_ENABLE_MASK = 0x00000001u;
inline constexpr int DEBUG_CTRL_TRACE_ENABLE_LSB = 0;


inline constexpr uint16_t DEBUG_TRACE_STATUS_ADDR = 0x4004;
inline constexpr uint32_t DEBUG_TRACE_STATUS_RESET = 0x00000000u;

inline constexpr uint32_t DEBUG_TRACE_STATUS_TRACE_EMPTY_MASK = 0x00000001u;
inline constexpr int DEBUG_TRACE_STATUS_TRACE_EMPTY_LSB = 0;

inline constexpr uint32_t DEBUG_TRACE_STATUS_TRACE_FULL_MASK = 0x00000002u;
inline constexpr int DEBUG_TRACE_STATUS_TRACE_FULL_LSB = 1;

inline constexpr uint32_t DEBUG_TRACE_STATUS_TRACE_COUNT_MASK = 0x00001ffcu;
inline constexpr int DEBUG_TRACE_STATUS_TRACE_COUNT_LSB = 2;


inline constexpr uint16_t DEBUG_TRACE_RDATA_ADDR = 0x4008;
inline constexpr uint32_t DEBUG_TRACE_RDATA_RESET = 0x00000000u;


inline constexpr uint16_t DEBUG_ERROR_CODE_ADDR = 0x4010;
inline constexpr uint32_t DEBUG_ERROR_CODE_RESET = 0x00000000u;


inline constexpr uint16_t DEBUG_ERROR_TAG_ADDR = 0x4014;
inline constexpr uint32_t DEBUG_ERROR_TAG_RESET = 0x00000000u;




}  // namespace tpe::regs
