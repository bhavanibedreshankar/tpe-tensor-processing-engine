// Standalone unit test for model/include/MacArray.hpp.
#include <cstdio>

#include "MacArray.hpp"

using tpe::model::Matrix;
using tpe::model::matmul;

static int g_failures = 0;

#define CHECK(cond)                                                                  \
  do {                                                                                \
    if (!(cond)) {                                                                    \
      std::fprintf(stderr, "CHECK FAILED: %s (%s:%d)\n", #cond, __FILE__, __LINE__);  \
      g_failures++;                                                                   \
    }                                                                                 \
  } while (0)

static void test_identity_2x2() {
  Matrix a(2, 2);
  a.at(0, 0) = 1;
  a.at(0, 1) = 2;
  a.at(1, 0) = 3;
  a.at(1, 1) = 4;

  Matrix b(2, 2);
  b.at(0, 0) = 1;
  b.at(0, 1) = 0;
  b.at(1, 0) = 0;
  b.at(1, 1) = 1;

  Matrix c_in(2, 2);  // zeros
  bool ovf = true;
  Matrix c = matmul(a, b, c_in, &ovf);
  CHECK(!ovf);
  CHECK(c.at(0, 0) == 1 && c.at(0, 1) == 2 && c.at(1, 0) == 3 && c.at(1, 1) == 4);
}

static void test_accumulate_into_c_in() {
  Matrix a(1, 1);
  a.at(0, 0) = 5;
  Matrix b(1, 1);
  b.at(0, 0) = 3;
  Matrix c_in(1, 1);
  c_in.at(0, 0) = 100;

  bool ovf = false;
  Matrix c = matmul(a, b, c_in, &ovf);
  CHECK(!ovf);
  CHECK(c.at(0, 0) == 115);  // 100 + 5*3
}

static void test_known_3x2x4() {
  // A: 3x2, B: 2x4, hand-computed expected result.
  Matrix a(3, 2);
  a.data = {1, 2, 3, 4, 5, 6};
  Matrix b(2, 4);
  b.data = {1, 0, -1, 2, 0, 1, 2, -1};
  Matrix c_in(3, 4);  // zeros

  bool ovf = false;
  Matrix c = matmul(a, b, c_in, &ovf);
  CHECK(!ovf);
  // row0 = [1,2] . cols -> [1*1+2*0, 1*0+2*1, 1*-1+2*2, 1*2+2*-1] = [1,2,3,0]
  CHECK(c.at(0, 0) == 1 && c.at(0, 1) == 2 && c.at(0, 2) == 3 && c.at(0, 3) == 0);
  // row1 = [3,4] -> [3, 4, 5, 2]
  CHECK(c.at(1, 0) == 3 && c.at(1, 1) == 4 && c.at(1, 2) == 5 && c.at(1, 3) == 2);
  // row2 = [5,6] -> [5, 6, 7, 4]
  CHECK(c.at(2, 0) == 5 && c.at(2, 1) == 6 && c.at(2, 2) == 7 && c.at(2, 3) == 4);
}

static void test_saturates_on_overflow() {
  Matrix a(1, 1);
  a.at(0, 0) = 127;
  Matrix b(1, 1);
  b.at(0, 0) = 127;
  Matrix c_in(1, 1);
  c_in.at(0, 0) = 2147483647 - 100;  // INT32_MAX - 100, product=16129 overflows it

  bool ovf = false;
  Matrix c = matmul(a, b, c_in, &ovf);
  CHECK(ovf);
  CHECK(c.at(0, 0) == 2147483647);
}

static void test_saturates_negative() {
  Matrix a(1, 1);
  a.at(0, 0) = 127;
  Matrix b(1, 1);
  b.at(0, 0) = -128;
  Matrix c_in(1, 1);
  c_in.at(0, 0) = -2147483647 - 1 + 100;  // INT32_MIN + 100, product=-16256 underflows it

  bool ovf = false;
  Matrix c = matmul(a, b, c_in, &ovf);
  CHECK(ovf);
  CHECK(c.at(0, 0) == (-2147483647 - 1));
}

int main() {
  test_identity_2x2();
  test_accumulate_into_c_in();
  test_known_3x2x4();
  test_saturates_on_overflow();
  test_saturates_negative();

  if (g_failures == 0) {
    std::printf("test_matmul: all tests passed\n");
    return 0;
  }
  std::fprintf(stderr, "test_matmul: %d failure(s)\n", g_failures);
  return 1;
}
