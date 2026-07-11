// Standalone unit test for model/include/Scratchpad.hpp. Deliberately
// dependency-free (no Catch2/GoogleTest) so `model/` builds and tests in
// complete isolation -- see model/README.md for why.
#include <cstdio>
#include <cstdlib>
#include <stdexcept>

#include "Scratchpad.hpp"

using tpe::model::Scratchpad;

static int g_failures = 0;

#define CHECK(cond)                                                     \
  do {                                                                  \
    if (!(cond)) {                                                      \
      std::fprintf(stderr, "CHECK FAILED: %s (%s:%d)\n", #cond, __FILE__, __LINE__); \
      g_failures++;                                                     \
    }                                                                   \
  } while (0)

static void test_write_read_roundtrip() {
  Scratchpad sram(16, 4);
  std::uint8_t row[4] = {0xDE, 0xAD, 0xBE, 0xEF};
  sram.write(3, 0xF, row);
  auto got = sram.read(3);
  CHECK(got.size() == 4);
  CHECK(got[0] == 0xDE && got[1] == 0xAD && got[2] == 0xBE && got[3] == 0xEF);
}

static void test_strobe_masks_partial_bytes() {
  Scratchpad sram(4, 4);
  std::uint8_t full[4] = {0x11, 0x22, 0x33, 0x44};
  sram.write(0, 0xF, full);
  std::uint8_t partial[4] = {0xAA, 0xBB, 0xCC, 0xDD};
  sram.write(0, 0b0101, partial);  // only bytes 0 and 2 update
  auto got = sram.read(0);
  CHECK(got[0] == 0xAA);
  CHECK(got[1] == 0x22);
  CHECK(got[2] == 0xCC);
  CHECK(got[3] == 0x44);
}

static void test_uninitialized_reads_zero() {
  Scratchpad sram(8, 2);
  auto got = sram.read(5);
  CHECK(got[0] == 0 && got[1] == 0);
}

static void test_out_of_range_throws() {
  Scratchpad sram(4, 4);
  bool threw = false;
  try {
    (void)sram.read(4);
  } catch (const std::out_of_range&) {
    threw = true;
  }
  CHECK(threw);
}

static void test_raw_image_size() {
  Scratchpad sram(4096, 16);
  CHECK(sram.raw_image().size() == 4096 * 16);
}

int main() {
  test_write_read_roundtrip();
  test_strobe_masks_partial_bytes();
  test_uninitialized_reads_zero();
  test_out_of_range_throws();
  test_raw_image_size();

  if (g_failures == 0) {
    std::printf("test_scratchpad: all tests passed\n");
    return 0;
  }
  std::fprintf(stderr, "test_scratchpad: %d failure(s)\n", g_failures);
  return 1;
}
