`include "define.vh"

module periph_sdcard (
    input  wire        CLK,
    input  wire        RST_X,

    output wire [31:0] loader_addr,
    output wire [31:0] loader_data,
    output wire        loader_we,
    output wire        loader_done,

    input  wire        w_dram_busy,

    input  wire        clk_50mhz,

    output wire [40:0] sdcram_addr,
    output wire        sdcram_ren,
    output wire [ 3:0] sdcram_wen,
    output wire [31:0] sdcram_wdata,
    input  wire [31:0] sdcram_rdata,
    input  wire        sdcram_busy,

    output wire [31:0] sdctrl_rdata,
    output wire        sdctrl_busy,

    input wire [31:0]  w_mc_addr,
    input wire [31:0]  w_mc_wdata,
    input wire         w_mode_is_mc,
    input wire [ 1:0]  w_mc_aces,
    input wire         w_mem_we
);

    wire [40:0] ctrl_sdcram_addr;
    wire        ctrl_sdcram_ren;
    wire [ 3:0] ctrl_sdcram_wen;
    wire [31:0] ctrl_sdcram_wdata;

    wire [40:0] loader_sdcram_addr;
    wire        loader_sdcram_ren;

    // SD card program loader

    SDPLOADER sp(
        .i_clk(CLK),
        .i_rst_x(RST_X),
        .o_addr(loader_addr),
        .o_data(loader_data),
        .o_we(loader_we),
        .o_done(loader_done),
        .sdcram_addr(loader_sdcram_addr),
        .sdcram_ren(loader_sdcram_ren),
        .sdcram_rdata(sdcram_rdata),
        .sdcram_busy(sdcram_busy),
        .w_dram_busy(w_dram_busy)
    );

    assign sdcram_addr  = (loader_done) ? ctrl_sdcram_addr  : loader_sdcram_addr ;
    assign sdcram_ren   = (loader_done) ? ctrl_sdcram_ren   : loader_sdcram_ren  ;
    assign sdcram_wen   = (loader_done) ? ctrl_sdcram_wen   : 0                  ;
    assign sdcram_wdata = (loader_done) ? ctrl_sdcram_wdata : 0                  ;

    // SDCRAM Controller

    wire [31:0] sdctrl_addr;
    wire        sdctrl_ren;
    wire        sdctrl_wen;
    wire [31:0] sdctrl_wdata;

    assign sdctrl_addr  = w_mc_addr - 32'h90000000 + `BIN_BBL_SIZE;
    assign sdctrl_wdata = w_mc_wdata;

    wire  w_sd_access         = w_mode_is_mc & (w_mc_addr[31:28] >= 9);
    wire  w_sd_read_req       = w_sd_access & (w_mc_aces == `ACCESS_READ);
    wire  w_sd_write_req      = w_sd_access & w_mem_we;

    reg   r_prev_sd_read_req  = 0;
    reg   r_prev_sd_write_req = 0;
    always @ (posedge CLK) begin
        r_prev_sd_read_req  <= w_sd_read_req;
        r_prev_sd_write_req <= w_sd_write_req;
    end


    assign sdctrl_ren = !r_prev_sd_read_req & w_sd_read_req & !sdctrl_busy;
    assign sdctrl_wen = !r_prev_sd_write_req & w_sd_write_req & !sdctrl_busy;

    sdcram_controller sdcon(
        .i_clk(CLK),
        .i_rst_x(RST_X),
        .i_addr(sdctrl_addr),
        .o_rdata(sdctrl_rdata),
        .i_wdata(sdctrl_wdata),
        .i_ren(sdctrl_ren),
        .i_wen(sdctrl_wen),
        .o_busy(sdctrl_busy),
        .sdcram_addr(ctrl_sdcram_addr),
        .sdcram_ren(ctrl_sdcram_ren),
        .sdcram_wen(ctrl_sdcram_wen),
        .sdcram_wdata(ctrl_sdcram_wdata),
        .sdcram_rdata(sdcram_rdata),
        .sdcram_busy(sdcram_busy)
    );
endmodule