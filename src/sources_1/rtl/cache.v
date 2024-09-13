`include "define.vh"

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

module m_cache_dmap_invalidatable #(
    parameter  VECTOR = 1,
    parameter  W_ADDR  = 20,
    parameter  W_DATA  = 20,
    parameter  N_ENTRY = 4,
    localparam W_INDEX = $clog2(N_ENTRY)
) (
    input  wire               CLK,
    input  wire               RST_X,
    input  wire               w_flush,
    input  wire               w_we,
    input  wire  [W_ADDR-1:0] w_waddr,
    input  wire  [W_ADDR-1:0] w_raddr,
    input  wire  [W_DATA-1:0] w_wdata,
    input  wire               w_invalidate,
    input  wire [W_INDEX-1:0] w_invalidate_index,
    output wire  [W_DATA-1:0] w_rdata,
    output wire               w_hit
);
    localparam W_TAG = W_ADDR - W_INDEX;

    reg [N_ENTRY-1:0] r_valid = 0;
    reg   [W_TAG-1:0] r_tag  [0:N_ENTRY-1];
    reg  [W_DATA-1:0] r_data [0:N_ENTRY-1];

    integer i;
    initial for (i = 0; i < N_ENTRY; i = i + 1) begin
        r_tag[i]  = 0;
        r_data[i] = 0;
    end

    wire [W_INDEX-1:0] w_write_index = w_waddr[0 +: W_INDEX];
    wire [W_INDEX-1:0] w_read_index  = w_raddr[0 +: W_INDEX];
    wire   [W_TAG-1:0] w_write_tag   = w_waddr[W_INDEX +: W_TAG];
    wire   [W_TAG-1:0] w_read_tag    = w_raddr[W_INDEX +: W_TAG];

    wire w_tag_match = (r_tag[w_read_index] == w_read_tag);

    generate
        if (VECTOR) begin
            wire [N_ENTRY-1:0] w_read_index_vector = 1'b1 << w_read_index;
            assign w_hit = (r_valid & w_read_index_vector) && w_tag_match;
        end else begin
            assign w_hit = r_valid[w_read_index] && w_tag_match;
        end
    endgenerate

    assign w_rdata = r_data[w_read_index];

    always @(posedge CLK) begin
        if (!RST_X) begin
            r_valid <= 0;
        end else begin
            if (w_flush) begin
                r_valid <= 0;
            end else if (w_invalidate) begin
                r_valid[w_invalidate_index] <= 1'b0;
            end else if (w_we) begin
                r_valid[w_write_index] <= 1'b1;
                r_tag[w_write_index]   <= w_write_tag;
                r_data[w_write_index]  <= w_wdata;
            end
        end
    end

endmodule

module m_inst_cache #(
    parameter  ENABLED          = 1, // Always miss if disabled
    parameter  W_DATA           = 128,
    parameter  N_ENTRY          = 32,
    localparam W_WORD           = 32,
    localparam W_INDEX = $clog2(N_ENTRY)
) (
    input  wire               CLK,
    input  wire               RST_X,
    input  wire   [`XLEN-1:0] w_pc,
    input  wire  [W_DATA-1:0] w_dram_data,
    input  wire               w_invalidate,
    input  wire        [31:0] w_invalidate_address,

    output wire               w_hit,
    output wire  [W_DATA-1:0] w_inst
);
    localparam N_WORDS = W_DATA / W_WORD;

    generate
        if (ENABLED) begin
            
        end else begin
            assign w_hit  = 1'b0;
            assign w_inst = 0;
        end
    endgenerate

endmodule
