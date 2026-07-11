# Builds the tpe_model golden-model CLI and its standalone unit tests.
# No RTL/cocotb dependency -- pure C++17.

CXX ?= g++
CXXFLAGS := -std=c++17 -Wall -Wextra -Werror -Iinclude -O2
BUILD_DIR := build

SRC := src/main.cpp
TEST_SRC := tests/test_scratchpad.cpp

.PHONY: all test clean
all: $(BUILD_DIR)/tpe_model

$(BUILD_DIR):
	mkdir -p $(BUILD_DIR)

$(BUILD_DIR)/tpe_model: $(SRC) include/Scratchpad.hpp | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(SRC) -o $@

$(BUILD_DIR)/test_scratchpad: $(TEST_SRC) include/Scratchpad.hpp | $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) $(TEST_SRC) -o $@

test: $(BUILD_DIR)/test_scratchpad
	./$(BUILD_DIR)/test_scratchpad

clean:
	rm -rf $(BUILD_DIR)
