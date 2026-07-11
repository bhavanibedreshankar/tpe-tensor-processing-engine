#pragma once
// Golden-model equivalent of rtl/sram/tpe_sram.sv. Untimed (no port/cycle
// modeling) -- the pyuvm scoreboard is responsible for feeding writes in
// the same order the RTL executed them and for the pipeline-latency
// bookkeeping; this class only owns "what the final memory contents are."
#include <cstdint>
#include <stdexcept>
#include <vector>

namespace tpe::model {

class Scratchpad {
 public:
  // row_bytes matches tpe_pkg::SRAM_DATA_WIDTH/8, depth matches
  // tpe_pkg::SRAM_DEPTH. Defaults mirror the current register map.
  explicit Scratchpad(std::size_t depth = 4096, std::size_t row_bytes = 16)
      : depth_(depth), row_bytes_(row_bytes), mem_(depth * row_bytes, 0) {}

  std::size_t depth() const { return depth_; }
  std::size_t row_bytes() const { return row_bytes_; }

  // strb bit i gated write of byte i within the row, matching dp_ram.sv's
  // per-byte write-enable semantics.
  void write(std::uint32_t addr, std::uint32_t strb, const std::uint8_t* row_data) {
    check_addr(addr);
    std::uint8_t* row = &mem_[static_cast<std::size_t>(addr) * row_bytes_];
    for (std::size_t i = 0; i < row_bytes_; ++i) {
      if (strb & (1u << i)) {
        row[i] = row_data[i];
      }
    }
  }

  std::vector<std::uint8_t> read(std::uint32_t addr) const {
    check_addr(addr);
    const std::uint8_t* row = &mem_[static_cast<std::size_t>(addr) * row_bytes_];
    return std::vector<std::uint8_t>(row, row + row_bytes_);
  }

  const std::vector<std::uint8_t>& raw_image() const { return mem_; }

 private:
  void check_addr(std::uint32_t addr) const {
    if (addr >= depth_) {
      throw std::out_of_range("Scratchpad: address out of range");
    }
  }

  std::size_t depth_;
  std::size_t row_bytes_;
  std::vector<std::uint8_t> mem_;
};

}  // namespace tpe::model
