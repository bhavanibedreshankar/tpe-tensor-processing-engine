// Standalone unit test for model/include/DmaEngine.hpp.
#include <cstdio>

#include "DmaEngine.hpp"
#include "Scratchpad.hpp"

using tpe::model::DmaEngine;
using tpe::model::Scratchpad;

static int g_failures = 0;

#define CHECK(cond)                                                                  \
  do {                                                                                \
    if (!(cond)) {                                                                    \
      std::fprintf(stderr, "CHECK FAILED: %s (%s:%d)\n", #cond, __FILE__, __LINE__);  \
      g_failures++;                                                                   \
    }                                                                                 \
  } while (0)

static void test_ddr_to_sram() {
  Scratchpad ddr(16, 4);
  Scratchpad sram(16, 4);
  std::uint8_t row[4] = {1, 2, 3, 4};
  ddr.write(5, 0xF, row);

  DmaEngine::copy(ddr, sram, /*mem_row=*/5, /*sram_row=*/2, /*n_rows=*/1, /*dir=*/false);

  auto got = sram.read(2);
  CHECK(got[0] == 1 && got[1] == 2 && got[2] == 3 && got[3] == 4);
  // untouched rows stay zero
  auto untouched = sram.read(0);
  CHECK(untouched[0] == 0);
}

static void test_sram_to_ddr_multi_row() {
  Scratchpad ddr(16, 4);
  Scratchpad sram(16, 4);
  for (int i = 0; i < 3; ++i) {
    std::uint8_t row[4] = {static_cast<std::uint8_t>(i), 0, 0, 0};
    sram.write(i, 0xF, row);
  }

  DmaEngine::copy(ddr, sram, /*mem_row=*/10, /*sram_row=*/0, /*n_rows=*/3, /*dir=*/true);

  for (int i = 0; i < 3; ++i) {
    auto got = ddr.read(10 + i);
    CHECK(got[0] == i);
  }
}

int main() {
  test_ddr_to_sram();
  test_sram_to_ddr_multi_row();

  if (g_failures == 0) {
    std::printf("test_dma: all tests passed\n");
    return 0;
  }
  std::fprintf(stderr, "test_dma: %d failure(s)\n", g_failures);
  return 1;
}
