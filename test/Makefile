CXX := clang++-18
LD  := lld-18

SRC_DIR   := src
BUILD_DIR := build
INC_DIR   := $(SRC_DIR)

SOURCES := $(wildcard $(SRC_DIR)/*.cc)
OBJECTS := $(patsubst $(SRC_DIR)/%.cc,$(BUILD_DIR)/%.o,$(SOURCES))

CXXFLAGS := -O3 -std=c++23 -stdlib=libc++ -flto -I$(INC_DIR) $(shell pkg-config --cflags --libs gtkmm-3.0)
LDFLAGS  := -fuse-ld=$(LD)

PREFIX_NAME := rvpc_sim
BUILD_BIN   := $(BUILD_DIR)/$(PREFIX_NAME)
INITMEM_BIN := ../diskimage/initmem.bin

.PHONY: all run clean
all: $(BUILD_BIN)

run: $(BUILD_BIN)
	$< $(INITMEM_BIN)
#	$<

# $(BUILD_BIN): $(OBJECTS)
# 	$(CXX) $(CXXFLAGS) -o $@ $^ $(LDFLAGS)

# $(BUILD_DIR)/%.o: $(SRC_DIR)/%.cc
# 	@mkdir -p $(BUILD_DIR)
# 	$(CXX) $(CXXFLAGS) -c -o $@ $<

RTL_DIR := ../src/sources_1/rtl
RTL_SRC := $(wildcard $(RTL_DIR)/*.v)
SIM_DIR := ../test/rtl
SIM_SRC := $(wildcard $(SIM_DIR)/*.v)
VFLAGS  := --no-timing -Wno-WIDTHEXPAND -Wno-WIDTHTRUNC -Wno-CASEINCOMPLETE -Wno-UNSIGNED -Wno-COMBDLY -Wno-MULTIDRIVEN -DD_UC_LM_IFILE='"../ucimage/ucimage.mem"' -DINITMEM_HEX='"$(BUILD_DIR)/initmem.hex"' --trace-fst --trace-params --trace-structs --trace-underscore

$(BUILD_BIN): $(BUILD_DIR)/$(PREFIX_NAME).mk
	make -C $(BUILD_DIR) -f $(PREFIX_NAME).mk -j CXX=$(CXX) LINK=$(CXX)

$(BUILD_DIR)/$(PREFIX_NAME).mk: $(SOURCES) $(RTL_SRC) $(SIM_SRC)
	verilator --cc $(RTL_SRC) $(SIM_SRC) --top m_main --prefix $(PREFIX_NAME) --exe $(SOURCES) -CFLAGS "$(CXXFLAGS)" -LDFLAGS "$(CXXFLAGS) $(LDFLAGS)" --Mdir $(BUILD_DIR) -I$(RTL_DIR) $(VFLAGS)
#	hexdump -v -e '1/4 "%08x\n"' $(INITMEM_BIN) > $(BUILD_DIR)/initmem.hex

clean:
	rm -rf $(BUILD_DIR)
