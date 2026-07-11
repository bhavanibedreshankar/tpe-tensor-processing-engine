#pragma once
// Golden-model equivalent of rtl/dma/tpe_dma.sv: a byte-accurate copy
// between two Scratchpad-shaped memories (DDR and Local SRAM), addressed
// in whole rows exactly like the RTL (see tpe_dma.sv's header comment --
// V1 only moves whole AXI_DATA_WIDTH/SRAM_DATA_WIDTH rows, no sub-row byte
// strobes). Untimed: this is the *final* memory content the RTL's DDR and
// SRAM images must match, not a cycle-accurate AXI model.
#include <stdexcept>

#include "Scratchpad.hpp"

namespace tpe::model {

class DmaEngine {
 public:
  // dir: false = DDR -> SRAM, true = SRAM -> DDR. mem_addr/sram_addr are
  // row indices (not byte addresses) -- matches how the RTL testbench
  // stages descriptors once it has decoded the byte address / row width.
  static void copy(Scratchpad& ddr, Scratchpad& sram, std::uint32_t mem_row, std::uint32_t sram_row,
                    std::uint32_t n_rows, bool dir) {
    if (ddr.row_bytes() != sram.row_bytes()) {
      throw std::invalid_argument("DmaEngine::copy: row width mismatch between ddr and sram");
    }
    const std::uint32_t full_strb = (1u << ddr.row_bytes()) - 1u;
    for (std::uint32_t i = 0; i < n_rows; ++i) {
      if (!dir) {
        auto row = ddr.read(mem_row + i);
        sram.write(sram_row + i, full_strb, row.data());
      } else {
        auto row = sram.read(sram_row + i);
        ddr.write(mem_row + i, full_strb, row.data());
      }
    }
  }
};

}  // namespace tpe::model
