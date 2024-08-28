`define SD_OFFSET 2  // SDcard offset width
`define SD_ADDR ($clog2(`DISK_SIZE)-`SD_OFFSET) // SDcard address width
module sdcard_sim (
   input  wire        w_CLK                 ,
   input  wire        w_i_sys_rst           ,
   input  wire        w_i_sd_clk            , // not used in simulation
   input  wire        w_i_sd_rst            , // not used in simulation
   // for user interface
   input  wire [40:0] w_i_sdcram_addr       ,
   input  wire        w_i_sdcram_ren        ,
   input  wire  [3:0] w_i_sdcram_wen        ,
   input  wire [31:0] w_i_sdcram_wdata      ,
   output wire [31:0] w_o_sdcram_rdata      ,
   output wire        w_o_sdcram_busy       ,
   // for debug
   output wire  [2:0] w_sdcram_state        , // not used in simulation
   output wire  [2:0] w_sdi_state           , // not used in simulation
   output wire  [4:0] w_sdc_state           , // not used in simulation
   // for sd
   input  wire        w_sd_cd               , // not used in simulation
   output wire        w_sd_rst              , // not used in simulation
   output wire        w_sd_sclk             , // not used in simulation
   output wire        w_sd_cmd              , // not used in simulation
   inout  wire  [3:0] w_sd_dat                // not used in simulation
);

    assign w_o_sdcram_busy    = 0     ;
    assign w_o_sdcram_rdata   = r_data;

    reg [31:0] r_ram [0:2**`SD_ADDR-1];
`ifdef INITMEM_HEX
    initial $readmemh(`INITMEM_HEX, r_ram);
`endif

    reg  [31:0] r_data;
    wire [`SD_ADDR-1:0] w_addr = w_i_sdcram_addr[`SD_ADDR+`SD_OFFSET-1:`SD_OFFSET];
    always @(posedge w_CLK) begin
        if (w_i_sdcram_ren) begin
            r_data <= r_ram[w_addr];
        end
        else if (w_i_sdcram_wen) begin
            if (w_i_sdcram_wen[0]) r_ram[w_addr][ 7: 0] <= w_i_sdcram_wdata[ 7: 0];
            if (w_i_sdcram_wen[1]) r_ram[w_addr][15: 8] <= w_i_sdcram_wdata[15: 8];
            if (w_i_sdcram_wen[2]) r_ram[w_addr][23:16] <= w_i_sdcram_wdata[23:16];
            if (w_i_sdcram_wen[3]) r_ram[w_addr][31:24] <= w_i_sdcram_wdata[31:24];
        end
    end

endmodule
