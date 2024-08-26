#include <print>
#include <memory>
#include <utility>
#include <cstdint>
#include <fstream>
#include <cstdlib>

#include <verilated_fst_c.h>

#include "rvpc_sim.h"

constexpr unsigned int DRAM_SIZE = 128 * 1024 * 1024;
constexpr unsigned int SDCARD_SIZE = (2 * 1024 - 128) * 1024 * 1024;

static unsigned int cnt = 0;

// DRAM simulation model
class dram_sim {
    std::uint32_t ram[DRAM_SIZE/sizeof(std::uint32_t)];
public:
    dram_sim() {
        // Make sure the DRAM is zeroed out
        std::fill(ram, ram + DRAM_SIZE/sizeof(std::uint32_t), 0);
    };
    void dram_step(VL_OUT8(&dram_rd_en,0,0), VL_OUT8(&dram_wr_en,0,0), VL_IN8(&dram_busy,0,0), VL_OUT8(&dram_ctrl,2,0), VL_OUT(&dram_addr,31,0), VL_OUT(&dram_wdata,31,0), VL_INW(&dram_rdata128,127,0,4)) {
        const auto word_idx = dram_addr >> 2;
        if (dram_rd_en) {
            // Read from DRAM
            const auto longword_idx = word_idx & ~0x3;
            dram_rdata128.at(0) = ram[longword_idx];
            dram_rdata128.at(1) = ram[longword_idx+1];
            dram_rdata128.at(2) = ram[longword_idx+2];
            dram_rdata128.at(3) = ram[longword_idx+3];
            // std::print("DRAM read: addr={:08x}, data={:08x} {:08x} {:08x} {:08x}\n", dram_addr, ram[longword_idx], ram[longword_idx+1], ram[longword_idx+2], ram[longword_idx+3]);
        } else if (dram_wr_en) {
            // Write to DRAM
            if (dram_ctrl==0) {
                ram[word_idx] = dram_wdata;
            } else {
                const std::uint8_t *dram_wdata_ptr = reinterpret_cast<std::uint8_t*>(&dram_wdata);
                std::uint8_t *ram_ptr = reinterpret_cast<std::uint8_t*>(&ram[word_idx]);
                if (dram_ctrl==0) ram_ptr[dram_addr & 0x3] = dram_wdata_ptr[0];
                else if (dram_ctrl==1) {
                    ram_ptr[dram_addr & 0x2] = dram_wdata_ptr[0];
                    ram_ptr[(dram_addr & 0x2)+1] = dram_wdata_ptr[1];
                } else {
                    ram[word_idx] = dram_wdata;
                }
            }
            // std::print("DRAM write: addr={:08x}, data={:08x}\n", dram_addr, dram_wdata);
        }
    };
};

// SD Card simulation model
class sdcard_sim {
    std::uint8_t ram[SDCARD_SIZE];
public:
    sdcard_sim(char filename[]) {
        // Make sure the SD Card is zeroed out
        std::fill(ram, ram + SDCARD_SIZE, 0);
        std::ifstream file(filename, std::ios::binary);
        if (!file.is_open()) {
            std::print("Failed to open file\n");
            std::exit(1);
        }
        file.read(reinterpret_cast<char*>(ram), SDCARD_SIZE);
        file.close();
    };
    void sdcard_step(VL_OUT8(&w_sdcram_ren,0,0), VL_OUT8(&w_sdcram_wen,3,0), VL_OUT(&w_sdcram_wdata,31,0), VL_IN(&w_sdcram_rdata,31,0), VL_OUT64(&w_sdcram_addr,40,0)) {
        const auto word_idx = w_sdcram_addr & ~0x3;
        if (w_sdcram_ren) {
            // Read from SD Card
            w_sdcram_rdata = *reinterpret_cast<std::uint32_t*>(&ram[word_idx]);
            // std::print("SD Card read: addr={:08x}, data={:08x}\n", w_sdcram_addr, w_sdcram_rdata);
        } else if (w_sdcram_wen) {
            // Write to SD Card
            if (w_sdcram_wen & (1 << 0)) ram[word_idx] = w_sdcram_wdata;
            if (w_sdcram_wen & (1 << 1)) ram[word_idx+1] = w_sdcram_wdata >> 8;
            if (w_sdcram_wen & (1 << 2)) ram[word_idx+2] = w_sdcram_wdata >> 16;
            if (w_sdcram_wen & (1 << 3)) ram[word_idx+3] = w_sdcram_wdata >> 24;
            // std::print("SD Card write: addr={:08x}, data={:08x}\n", w_sdcram_addr, w_sdcram_wdata);
        }
    };
};

int main(int argc, char *argv[]) {
    if (argc != 2) {
        std::print("Usage: {} <sdcard.img>\n", argv[0]);
        return 1;
    }
    Verilated::commandArgs(argc, argv);
    const std::unique_ptr<VerilatedContext> contextp = std::make_unique<VerilatedContext>();
    const std::unique_ptr<rvpc_sim> dut = std::make_unique<rvpc_sim>(contextp.get());
    const std::unique_ptr<dram_sim> dram = std::make_unique<dram_sim>();
    const std::unique_ptr<sdcard_sim> sdcard = std::make_unique<sdcard_sim>(argv[1]);

    Verilated::traceEverOn(true);
    VerilatedFstC* tfp = new VerilatedFstC;
    dut->trace(tfp, 100);
    tfp->open("rvpc_sim.fst");

    while (!contextp->gotFinish()) {
        // std::print("Simulation step {}\n", cnt);
        dut->CLK = ~dut->CLK;
        dram->dram_step(dut->dram_rd_en, dut->dram_wr_en, dut->dram_busy, dut->dram_ctrl, dut->dram_addr, dut->dram_wdata, dut->dram_rdata128);
        sdcard->sdcard_step(dut->w_sdcram_ren, dut->w_sdcram_wen, dut->w_sdcram_wdata, dut->w_sdcram_rdata, dut->w_sdcram_addr);
        dut->eval();
        // tfp->dump(cnt);
        if (dut->w_led & (1 << 1)) { // Let's observe it after led[1] is set, i.e. initialization is done
            tfp->dump(cnt);
            ++cnt;
        }
        if (cnt > 100000) {
            std::print("Simulation timed out\n");
            break;
        }
    }
    std::print("Simulation finished. cnt={}\n", cnt);
    dut->final();
    tfp->close();
    return 0;
}
