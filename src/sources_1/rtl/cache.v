module m_cache_dmap#(parameter ADDR_WIDTH = 20, D_WIDTH = 20, ENTRY = 4)
            (CLK, RST_X, w_flush, w_we, w_waddr, w_raddr, w_idata, w_odata, w_oe);
    input  wire                     CLK, RST_X;
    input  wire                     w_flush, w_we;
    input  wire [ADDR_WIDTH-1:0]    w_waddr, w_raddr;
    input  wire    [D_WIDTH-1:0]    w_idata;
    output wire    [D_WIDTH-1:0]    w_odata;
    output wire                     w_oe;             //output enable
    reg                               [ENTRY-1:0]   r_valid = 0;
    reg  [(ADDR_WIDTH-$clog2(ENTRY)+D_WIDTH)-1:0]   mem [0:ENTRY-1];
    integer i;
    initial for(i=0; i<ENTRY; i=i+1) mem[i] = 0;
    // READ
    wire              [$clog2(ENTRY)-1:0]   w_ridx;
    wire [(ADDR_WIDTH-$clog2(ENTRY))-1:0]   w_rtag;
    assign {w_rtag, w_ridx} = w_raddr;
    wire [ENTRY-1:0] w_ridx_v = ({{(ENTRY-1){1'b0}},{1'b1}} << w_ridx);
    wire w_tagmatch = (mem[w_ridx][(ADDR_WIDTH-$clog2(ENTRY)+D_WIDTH)-1:D_WIDTH] == w_rtag);
    assign w_odata  = mem[w_ridx][D_WIDTH-1:0];
    //assign w_oe     = (w_tagmatch && r_valid[w_ridx]);
    assign w_oe     = (w_tagmatch && (r_valid & w_ridx_v));
    // WRITE
    wire              [$clog2(ENTRY)-1:0]   w_widx;
    wire [(ADDR_WIDTH-$clog2(ENTRY))-1:0]   w_wtag;
    assign {w_wtag, w_widx} = w_waddr;
    wire [ENTRY-1:0] w_widx_v = ({{(ENTRY-1){1'b0}},{1'b1}} << w_widx);
    always  @(posedge  CLK)  begin
        // FLUSH
        if (!RST_X || w_flush) begin
            r_valid <= 0;
        end
        if (w_we) begin
            mem[w_widx] <= {w_wtag, w_idata};
            //r_valid[w_widx] <= 1;
            r_valid <= r_valid | w_widx_v;
        end
    end
endmodule
