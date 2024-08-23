CXX := clang++-18
LD  := lld-18

SRC_DIR   := src
BUILD_DIR := build
INC_DIR   := $(SRC_DIR)

CXXFLAGS := -O2 -Wall -std=c++23 -stdlib=libc++ -I$(INC_DIR)
LDFLAGS  := -fuse-ld=$(LD)

BUILD_BIN := $(BUILD_DIR)/rvpc_sim

.PHONY: all run clean
all: $(BUILD_DIR)/rvpc_sim

run: $(BUILD_BIN)
	$<

$(BUILD_BIN): $(BUILD_DIR)/main.o
	$(CXX) $(CXXFLAGS) -o $@ $^ $(LDFLAGS)

$(BUILD_DIR)/%.o: $(SRC_DIR)/%.cc
	@mkdir -p $(BUILD_DIR)
	$(CXX) $(CXXFLAGS) -c -o $@ $<

clean:
	rm -rf $(BUILD_DIR)
