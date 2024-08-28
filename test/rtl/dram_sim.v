`define DRAM_OFFSET 2   // DRAM offset width
`define DRAM_ADDR ($clog2(`MEM_SIZE)-`DRAM_OFFSET) // DRAM address width
module dram_sim (
   input  wire         w_mig_clk        ,
   input  wire         w_mig_rst_n      ,
   output wire         w_CLK            ,
   output wire         w_o_rst_n        ,
   input  wire         w_i_rd_en        ,
   input  wire         w_i_wr_en        ,
   input  wire  [31:0] w_i_addr         ,
   input  wire  [31:0] w_i_data         ,
   output wire  [31:0] w_o_data3        ,
   output wire  [31:0] w_o_data2        ,
   output wire  [31:0] w_o_data1        ,
   output wire  [31:0] w_o_data0        ,
   output wire         w_o_busy         ,
   input  wire   [3:0] w_i_mask
);

    assign w_CLK   = w_mig_clk ;

    reg    r_rst_n   = 1'b1;
    assign w_o_rst_n = r_rst_n   ;

    assign w_o_busy  = r_busy;
    reg r_busy = 0;
    always @(posedge w_CLK) begin
        r_busy <= w_i_rd_en || w_i_wr_en;
    end

    reg [31:0] r_ram [0:2**`DRAM_ADDR-1];
    wire [`DRAM_ADDR-1:0] w_addr    = w_i_addr[`DRAM_ADDR+`DRAM_OFFSET-1:`DRAM_OFFSET];
    wire [`DRAM_ADDR-3:0] w_w_addr  = w_addr[`DRAM_ADDR-1:2];

    reg [31:0] r_rdata3;
    reg [31:0] r_rdata2;
    reg [31:0] r_rdata1;
    reg [31:0] r_rdata0;
    always @(posedge w_CLK) begin
        if (w_i_rd_en) begin
            r_rdata3    <= r_ram[{w_w_addr, 2'h3}];
            r_rdata2    <= r_ram[{w_w_addr, 2'h2}];
            r_rdata1    <= r_ram[{w_w_addr, 2'h1}];
            r_rdata0    <= r_ram[{w_w_addr, 2'h0}];
        end
        else if (w_i_wr_en && w_i_mask==0) begin
            r_ram[w_addr] <= w_i_data;
        end
        else if (w_i_wr_en) begin
            if (w_i_mask[0]==0) r_ram[w_addr][ 7: 0] <= w_i_data[ 7: 0];
            if (w_i_mask[1]==0) r_ram[w_addr][15: 8] <= w_i_data[15: 8];
            if (w_i_mask[2]==0) r_ram[w_addr][23:16] <= w_i_data[23:16];
            if (w_i_mask[3]==0) r_ram[w_addr][31:24] <= w_i_data[31:24];
        end
    end

    assign w_o_data3  = r_rdata3  ;
    assign w_o_data2  = r_rdata2  ;
    assign w_o_data1  = r_rdata1  ;
    assign w_o_data0  = r_rdata0  ;

endmodule