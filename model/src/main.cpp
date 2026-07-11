// tpe_model CLI -- golden reference model entry point.
//
// Subcommands are added as each block's golden model class lands (M1:
// sram-apply, M2 onward: matmul, dma-apply, ...). Each subcommand reads a
// binary stimulus file the pyuvm scoreboard wrote during a test, replays it
// against the matching model/include/*.hpp class, and writes a binary
// result file the same scoreboard reads back to diff against RTL-observed
// state. Kept as a plain CLI (not a Python binding) so the model builds and
// unit-tests in complete isolation from the RTL/cocotb toolchain.
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <fstream>
#include <iostream>
#include <vector>

#include "MacArray.hpp"
#include "Scratchpad.hpp"

namespace {

// Matches the record layout tools/... (verif scoreboard) writes: see
// docs/verification/test_plan.md and verif/cocotb_tb/sram/test_sram.py.
#pragma pack(push, 1)
struct SramOpRecord {
  std::uint32_t addr;
  std::uint32_t strb;
  std::uint8_t row_data[16];
};
#pragma pack(pop)
static_assert(sizeof(SramOpRecord) == 24, "SramOpRecord layout drifted");

std::vector<std::uint8_t> read_file(const std::string& path) {
  std::ifstream f(path, std::ios::binary);
  if (!f) {
    throw std::runtime_error("cannot open input file: " + path);
  }
  return std::vector<std::uint8_t>(std::istreambuf_iterator<char>(f), std::istreambuf_iterator<char>());
}

void write_file(const std::string& path, const std::vector<std::uint8_t>& data) {
  std::ofstream f(path, std::ios::binary);
  if (!f) {
    throw std::runtime_error("cannot open output file: " + path);
  }
  f.write(reinterpret_cast<const char*>(data.data()), static_cast<std::streamsize>(data.size()));
}

int cmd_sram_apply(int argc, char** argv) {
  if (argc < 4) {
    std::cerr << "usage: tpe_model sram-apply <ops.bin> <image_out.bin> [depth] [row_bytes]\n";
    return 2;
  }
  const std::string ops_path = argv[2];
  const std::string out_path = argv[3];
  const std::size_t depth = argc > 4 ? static_cast<std::size_t>(std::stoul(argv[4])) : 4096;
  const std::size_t row_bytes = argc > 5 ? static_cast<std::size_t>(std::stoul(argv[5])) : 16;

  const auto raw = read_file(ops_path);
  if (raw.size() % sizeof(SramOpRecord) != 0) {
    std::cerr << "error: ops file size " << raw.size() << " is not a multiple of record size "
              << sizeof(SramOpRecord) << "\n";
    return 1;
  }
  const std::size_t n_ops = raw.size() / sizeof(SramOpRecord);

  tpe::model::Scratchpad sram(depth, row_bytes);
  for (std::size_t i = 0; i < n_ops; ++i) {
    SramOpRecord rec;
    std::memcpy(&rec, raw.data() + i * sizeof(SramOpRecord), sizeof(SramOpRecord));
    sram.write(rec.addr, rec.strb, rec.row_data);
  }

  write_file(out_path, sram.raw_image());
  std::cerr << "tpe_model: applied " << n_ops << " ops, wrote " << sram.raw_image().size()
            << " byte image to " << out_path << "\n";
  return 0;
}

// Stimulus file: {M,K,N: u32 LE} then A (M*K int8, row-major), B (K*N int8,
// row-major), C_in (M*N int32 LE, row-major). Result file: C_out (M*N int32
// LE, row-major) followed by a trailing u32 any_overflow flag. See
// verif/cocotb_tb/matrix_engine/scoreboard.py for the writer/reader.
#pragma pack(push, 1)
struct MatmulHeader {
  std::uint32_t m;
  std::uint32_t k;
  std::uint32_t n;
};
#pragma pack(pop)

int cmd_matmul(int argc, char** argv) {
  if (argc < 4) {
    std::cerr << "usage: tpe_model matmul <stim.bin> <out.bin>\n";
    return 2;
  }
  const auto raw = read_file(argv[2]);
  if (raw.size() < sizeof(MatmulHeader)) {
    std::cerr << "error: stimulus file too small for header\n";
    return 1;
  }
  MatmulHeader hdr;
  std::memcpy(&hdr, raw.data(), sizeof(hdr));
  const std::size_t a_bytes = static_cast<std::size_t>(hdr.m) * hdr.k;
  const std::size_t b_bytes = static_cast<std::size_t>(hdr.k) * hdr.n;
  const std::size_t c_bytes = static_cast<std::size_t>(hdr.m) * hdr.n * 4;
  const std::size_t expected = sizeof(MatmulHeader) + a_bytes + b_bytes + c_bytes;
  if (raw.size() != expected) {
    std::cerr << "error: stimulus file size " << raw.size() << " != expected " << expected << "\n";
    return 1;
  }

  const std::uint8_t* p = raw.data() + sizeof(MatmulHeader);
  tpe::model::Matrix a(static_cast<int>(hdr.m), static_cast<int>(hdr.k));
  for (std::size_t i = 0; i < a_bytes; ++i) a.data[i] = static_cast<int8_t>(p[i]);
  p += a_bytes;

  tpe::model::Matrix b(static_cast<int>(hdr.k), static_cast<int>(hdr.n));
  for (std::size_t i = 0; i < b_bytes; ++i) b.data[i] = static_cast<int8_t>(p[i]);
  p += b_bytes;

  tpe::model::Matrix c_in(static_cast<int>(hdr.m), static_cast<int>(hdr.n));
  for (std::size_t i = 0; i < c_in.data.size(); ++i) {
    std::int32_t v;
    std::memcpy(&v, p + i * 4, 4);
    c_in.data[i] = v;
  }

  bool any_overflow = false;
  tpe::model::Matrix c_out = tpe::model::matmul(a, b, c_in, &any_overflow);

  std::vector<std::uint8_t> out(c_bytes + 4);
  std::memcpy(out.data(), c_out.data.data(), c_bytes);
  std::uint32_t ovf_flag = any_overflow ? 1u : 0u;
  std::memcpy(out.data() + c_bytes, &ovf_flag, 4);
  write_file(argv[3], out);

  std::cerr << "tpe_model: matmul " << hdr.m << "x" << hdr.k << "x" << hdr.n
            << (any_overflow ? " (overflow)" : "") << " -> " << argv[3] << "\n";
  return 0;
}

}  // namespace

int main(int argc, char** argv) {
  if (argc < 2) {
    std::cerr << "usage: tpe_model <subcommand> [args...]\n"
                 "subcommands: sram-apply, matmul\n";
    return 2;
  }
  const std::string subcmd = argv[1];
  try {
    if (subcmd == "sram-apply") {
      return cmd_sram_apply(argc, argv);
    }
    if (subcmd == "matmul") {
      return cmd_matmul(argc, argv);
    }
    std::cerr << "error: unknown subcommand '" << subcmd << "'\n";
    return 2;
  } catch (const std::exception& e) {
    std::cerr << "error: " << e.what() << "\n";
    return 1;
  }
}
