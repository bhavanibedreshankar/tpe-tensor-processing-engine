#pragma once
// Golden-model equivalent of rtl/matrix_engine/{pe,mac_array,
// matrix_engine_ctrl,matrix_engine}.sv: C = A x B + C over int8 operands
// with an int32 accumulator, saturating per-addition exactly like pe.sv's
// sum_saturated (not a single final clamp -- see that file's comment).
// Untimed: this is the mathematical result the RTL's *final* output buffer
// content must match, not a cycle-accurate model of the systolic pipeline.
#include <cstdint>
#include <limits>
#include <vector>

namespace tpe::model {

// Row-major MxN matrix of int32 (also used to hold int8 inputs widened to
// int32 for convenience -- callers narrow on the way in/out).
struct Matrix {
  int rows = 0;
  int cols = 0;
  std::vector<int32_t> data;

  Matrix() = default;
  Matrix(int r, int c) : rows(r), cols(c), data(static_cast<size_t>(r) * c, 0) {}

  int32_t& at(int r, int c) { return data[static_cast<size_t>(r) * cols + c]; }
  int32_t at(int r, int c) const { return data[static_cast<size_t>(r) * cols + c]; }
};

inline int32_t saturating_add(int32_t acc, int32_t product, bool* overflowed) {
  int64_t wide = static_cast<int64_t>(acc) + static_cast<int64_t>(product);
  constexpr int64_t kMax = std::numeric_limits<int32_t>::max();
  constexpr int64_t kMin = std::numeric_limits<int32_t>::min();
  if (wide > kMax) {
    if (overflowed) *overflowed = true;
    return std::numeric_limits<int32_t>::max();
  }
  if (wide < kMin) {
    if (overflowed) *overflowed = true;
    return std::numeric_limits<int32_t>::min();
  }
  return static_cast<int32_t>(wide);
}

// A: M x K (int8 values stored widened in a Matrix), B: K x N (int8 widened),
// c_in: M x N (int32, pass an all-zero Matrix for a fresh GEMM). Returns
// C = A x B + c_in, and sets *any_overflow if any single accumulation step
// saturated anywhere in the result.
inline Matrix matmul(const Matrix& a, const Matrix& b, const Matrix& c_in, bool* any_overflow) {
  const int M = a.rows;
  const int K = a.cols;
  const int N = b.cols;
  Matrix out(M, N);
  if (any_overflow) *any_overflow = false;

  for (int m = 0; m < M; ++m) {
    for (int n = 0; n < N; ++n) {
      int32_t acc = c_in.at(m, n);
      for (int k = 0; k < K; ++k) {
        int32_t product = static_cast<int32_t>(a.at(m, k)) * static_cast<int32_t>(b.at(k, n));
        bool ovf = false;
        acc = saturating_add(acc, product, &ovf);
        if (ovf && any_overflow) *any_overflow = true;
      }
      out.at(m, n) = acc;
    }
  }
  return out;
}

}  // namespace tpe::model
