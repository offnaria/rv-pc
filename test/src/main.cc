#include <print>
#include <memory>
#include <utility>
#include <cstdint>
#include <fstream>
#include <cstdlib>
#include <gtkmm.h>

#include <verilated_fst_c.h>

#include "rvpc_sim.h"

constexpr unsigned int DRAM_SIZE = 128 * 1024 * 1024;
constexpr unsigned int SDCARD_SIZE = (1 * 1024 - 128) * 1024 * 1024;
constexpr unsigned int FB_ADDR_WIDTH = 20;
constexpr unsigned int FB_ADDR_MASK = (1 << FB_ADDR_WIDTH) - 1;

constexpr unsigned int TIMEOUT = 3'000'000'000;
constexpr bool TRACE = false;

#define DRAM_SIM_CPP 0

static unsigned int cnt = 0;

// DRAM simulation model
class DRAMSim {
    std::uint32_t ram[DRAM_SIZE/sizeof(std::uint32_t)];
public:
    DRAMSim() {
        // Make sure the DRAM is zeroed out
        std::fill(ram, ram + DRAM_SIZE/sizeof(std::uint32_t), 0);
    };
    void dram_step(const bool clk, VL_OUT8(&dram_rd_en,0,0), VL_OUT8(&dram_wr_en,0,0), VL_IN8(&dram_busy,0,0), VL_OUT8(&dram_ctrl,2,0), VL_OUT(&dram_addr,31,0), VL_OUT(&dram_wdata,31,0), VL_INW(&dram_rdata128,127,0,4)) {
        if (!clk || (!dram_rd_en && !dram_wr_en)) return;
        const auto word_idx = dram_addr >> 2;
        if (dram_rd_en) {
            // Read from DRAM
            const auto longword_idx = word_idx & ~0x3;
            dram_rdata128.at(0) = ram[longword_idx];
            dram_rdata128.at(1) = ram[longword_idx+1];
            dram_rdata128.at(2) = ram[longword_idx+2];
            dram_rdata128.at(3) = ram[longword_idx+3];
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
        }
        dram_busy = dram_rd_en || dram_wr_en;
    };
};

// SD Card simulation model
class SDCardSim {
    std::uint8_t ram[SDCARD_SIZE];
public:
    SDCardSim(char filename[]) {
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
    void sdcard_step(const bool clk, VL_OUT8(&w_sdcram_ren,0,0), VL_OUT8(&w_sdcram_wen,3,0), VL_OUT(&w_sdcram_wdata,31,0), VL_IN(&w_sdcram_rdata,31,0), VL_OUT64(&w_sdcram_addr,40,0)) {
        if (!clk || (!w_sdcram_ren && !w_sdcram_wen)) return;
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

class FrameBufferSim : public Gtk::Window {
    Gtk::Image img;
    Glib::RefPtr<Gdk::Pixbuf> pixbuf;
    guchar *pixels;
    int rowstride, height, channels;
public:
    FrameBufferSim(int width, int height) {
        set_title("RV-PC Frame Buffer");
        set_default_size(width, height);
        set_resizable(false);
        pixbuf = Gdk::Pixbuf::create(Gdk::COLORSPACE_RGB, false, 8, width, height);
        pixels = pixbuf->get_pixels();
        rowstride = pixbuf->get_rowstride();
        this->height = pixbuf->get_height();
        channels = pixbuf->get_n_channels();
        pixbuf->fill(0xff);
        img.set(pixbuf);
        img.show();
        add(img);
        std::print("FrameBufferSim initialized: rowstride={}, height={}, channels={}\n", rowstride, this->height, channels);
    };
    void framebuffer_step(const bool clk, VL_OUT8(&w_vga_we,0,0), VL_OUT(&w_vga_waddr,31,0), VL_OUT(&w_vga_wdata,31,0)) {
        if (!clk) return;
        if (!w_vga_we) return;
        const auto addr = (w_vga_waddr & FB_ADDR_MASK) >> 2;
        // std::print("FrameBufferSim: w_vga_we={}, w_vga_waddr={}, addr={}, w_vga_wdata={}\n", w_vga_we, w_vga_waddr, addr, w_vga_wdata);
        const auto x = (addr << 1) % 640;
        const auto y = (addr << 1) / 640;
        if (x >= 640 || y >= 480) {
            std::print("Invalid framebuffer address: x={}, y={}\n", x, y);
            std::exit(1);
        }
        auto *p = pixels + y * rowstride + x * channels;
        p[0] = w_vga_wdata & 0xff;
        p[1] = (w_vga_wdata >> 8) & 0xff;
        p[2] = (w_vga_wdata >> 16) & 0xff;
    };
    void showFrameBuffer() {
        img.set(pixbuf);
    };
};

int main(int argc, char *argv[]) {
    if (argc != 2) {
        std::print("Usage: {} <sdcard.img>\n", argv[0]);
        return 1;
    }
    Verilated::commandArgs(argc, argv);
    Gtk::Main kit;
    const std::unique_ptr<VerilatedContext> contextp = std::make_unique<VerilatedContext>();
    const std::unique_ptr<rvpc_sim> dut = std::make_unique<rvpc_sim>(contextp.get());
#   if DRAM_SIM_CPP
        const std::unique_ptr<DRAMSim> dram = std::make_unique<DRAMSim>();
#   endif
    const std::unique_ptr<SDCardSim> sdcard = std::make_unique<SDCardSim>(argv[1]);
    FrameBufferSim fb(640, 480);
    fb.show();

    std::print("Simulation started\n");

    VerilatedFstC* tfp;
    if constexpr (TRACE) {
        Verilated::traceEverOn(true);
        tfp = new VerilatedFstC;
        dut->trace(tfp, 100);
        tfp->open("rvpc_sim.fst");
    }

    while (!contextp->gotFinish()) {
        // std::print("Simulation step {}\n", cnt);
        dut->CLK = !(dut->CLK);
#       if DRAM_SIM_CPP
            dram->dram_step(dut->CLK, dut->dram_rd_en, dut->dram_wr_en, dut->dram_busy, dut->dram_ctrl, dut->dram_addr, dut->dram_wdata, dut->dram_rdata128);
#       endif
        sdcard->sdcard_step(dut->CLK, dut->w_sdcram_ren, dut->w_sdcram_wen, dut->w_sdcram_wdata, dut->w_sdcram_rdata, dut->w_sdcram_addr);
        if (dut->w_led & (1 << 1)) { // Let's observe it after led[1] is set, i.e. initialization is done
            if constexpr (TRACE) tfp->dump(cnt);
            fb.framebuffer_step(dut->CLK, dut->w_vga_we, dut->w_vga_waddr, dut->w_vga_wdata);
            if (cnt % 6 == 0) {
                fb.showFrameBuffer();
                while (kit.events_pending()) kit.iteration();
            }
            ++cnt;
        }
        if (cnt == 1) std::print("Memory initialization done\n"); 
        if (cnt >= TIMEOUT) {
            std::print("Simulation timed out\n");
            break;
        }
        dut->eval();
    }
    std::print("Simulation finished. cnt={}\n", cnt);
    dut->final();
    if constexpr (TRACE) tfp->close();
    return 0;
}
