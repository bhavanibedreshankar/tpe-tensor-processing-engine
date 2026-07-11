# Builds the tpe_model golden-model CLI and its standalone unit tests.
# No RTL/cocotb dependency -- pure C++17.

CXX ?= g++
CXXFLAGS := -std=c++17 -Wall -Wextra -Werror -Iinclude -O2
BUILD_DIR := build

SRC := src/main.cpp
HEADERS := include/Scratchpad.hpp include/MacArray.hpp
TEST_SRCS := tests/test_scratchpad.cpp tests/test_matmul.cpp
TEST_BINS := $(patsubst tests/%.cpp,$(BUILD_DIR)/%,$(TEST_SRCS))

.PHONY: all test clean
all: $(BUILD_DIR)/tpe_model

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/tpe_model: $(SRC) $(HEADERS) | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(SRC) -o $@

$(BUILD_DIR)/%: tests/%.cpp $(HEADERS) | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $< -o $@

test: $(TEST_BINS)
	@for t in $(TEST_BINS); do echo "-- $$t --"; ./$$t || exit 1; done

clean:
	rm -rf $(BUILD_DIR)
