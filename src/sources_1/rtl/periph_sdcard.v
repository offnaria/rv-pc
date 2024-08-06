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

    input  wire        sd_cd,
    output wire        sd_rst,
    output wire        sd_sclk,
    inout  wire        sd_cmd,
    inout  wire [ 3:0] sd_dat,

    output wire [31:0] sdctrl_rdata,
    output wire        sdctrl_busy,

    input wire [31:0]  w_mc_addr,
    input wire [31:0]  w_mc_wdata,
    input wire         w_mode_is_mc,
    input wire [ 1:0]  w_mc_aces,
    input wire         w_mem_we
);
    
    wire [40:0] sdcram_addr;
    wire        sdcram_ren;
    wire [ 3:0] sdcram_wen;
    wire [31:0] sdcram_wdata;
    wire [31:0] sdcram_rdata;
    wire        sdcram_busy;
    wire [ 2:0] sdcram_state;
    wire [ 2:0] sdi_state;
    wire [ 5:0] sdc_state;

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


    sdcram#(
        .CACHE_DEPTH(2),
        .BLOCK_NUM(8),
        .POLLING_CYCLES(1024)
    )sdcram_0(
        .i_sys_clk(CLK),
        .i_sys_rst(!RST_X),
        .i_sd_clk(clk_50mhz),
        .i_sd_rst(!RST_X),

        // for user interface
        .i_sdcram_addr(sdcram_addr),
        .i_sdcram_ren(sdcram_ren),
        .i_sdcram_wen(sdcram_wen),
        .i_sdcram_wdata(sdcram_wdata),
        .o_sdcram_rdata(sdcram_rdata),
        .o_sdcram_busy(sdcram_busy),

        // for debug
        .sdcram_state(sdcram_state),
        .sdi_state(sdi_state),
        .sdc_state(sdc_state),

        // for sd
        .sd_cd(sd_cd),
        .sd_rst(sd_rst),
        .sd_sclk(sd_sclk),
        .sd_cmd(sd_cmd),
    	.sd_dat(sd_dat)
    );

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