`include "define.vh"

module periph_framebuffer (
    input  wire                      CLK,
    input  wire                      pix_clk,
    input  wire [`FB_ADDR_WIDTH-1:0] w_offset,
    input  wire                      w_we,
    input  wire [31:0]               w_wdata,
    output wire [31:0]               w_rdata,
    output wire                      vga_h_sync,
    output wire                      vga_v_sync,
    output wire [3:0]                vga_red,
    output wire [3:0]                vga_blue,
    output wire [3:0]                vga_green
);

    localparam BPC = `FB_PIX_WIDTH/3; // Bits per Color

    assign w_rdata = 32'h0; // TODO?: Implement readback

    wire [31:0] w_fb_waddr = {4'b0, w_offset};
    wire [`FB_ADDR_WIDTH-1: 0] w_fb_raddr;
    wire [`FB_PIX_WIDTH-1: 0]  w_fb_wdata0;
    wire [`FB_PIX_WIDTH-1: 0]  w_fb_wdata1;
    wire [`FB_PIX_WIDTH-1: 0]  w_fb_rdata;
    wire [11:0] w_pix_data = {w_fb_rdata[BPC*3-1:BPC*2], {(4-BPC){1'b0}}, w_fb_rdata[BPC*2-1:BPC], {(4-BPC){1'b0}}, w_fb_rdata[BPC-1:0], {(4-BPC){1'b0}}};

    color_converter c0(.i_data(w_wdata[15: 0]), .o_data(w_fb_wdata0));
    color_converter c1(.i_data(w_wdata[31:16]), .o_data(w_fb_wdata1));

    framebuf  fb0 (
        .i_wclk(CLK),
        .i_we(w_we),
        .i_waddr(w_fb_waddr[`FB_ADDR_WIDTH-1: 0]),
        .i_wdata({w_fb_wdata1, w_fb_wdata0}),
        .i_rclk(pix_clk),
        .i_raddr(w_fb_raddr),
        .o_rdata(w_fb_rdata)
        );

    VGA vga (
        .pix_clk(pix_clk),
        .frame_pix(w_pix_data),
        .VGA_H_SYNC(vga_h_sync),
        .VGA_V_SYNC(vga_v_sync),
        .VGA_RED(vga_red),
        .VGA_BLUE(vga_blue),
        .VGA_GREEN(vga_green),
        .frame_addr(w_fb_raddr)
    );
    
endmodule