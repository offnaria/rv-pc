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

module m_inst_cache_dmap #(
    parameter  W_DATA           = 128,
    parameter  N_ENTRY          = 32,
    localparam W_WORD           = 32,
    localparam W_ADDR           = `XLEN
) (
    input  wire               CLK,
    input  wire               RST_X,
    input  wire  [W_ADDR-1:0] w_pc,
    input  wire               w_inst_request,
    input  wire  [W_DATA-1:0] w_dram_data,
    input  wire               w_dram_response,
    input  wire               w_is_paddr,
    input  wire               w_tlb_hit,
    input  wire               w_page_walk_fail,
    input  wire  [W_ADDR-1:0] w_tlb_address,
    input  wire               w_invalidate_request,
    input  wire        [31:0] w_invalidate_address,
    input  wire               w_flush,

    output wire               w_hit,
    output wire  [W_DATA-1:0] w_inst,
    output wire  [W_ADDR-1:0] w_dram_address,
    output wire               w_dram_request,
    output wire               w_invalidate_done
);
    localparam N_WORDS = W_DATA / W_WORD; // The number of words in a cache line.
    localparam W_INDEX = $clog2(N_ENTRY);
    localparam W_OFFSET = $clog2(W_DATA/8);
    localparam W_TAG = W_ADDR - (W_OFFSET + W_INDEX);
    localparam N_STATES = 3;
    localparam W_STATE = $clog2(N_STATES);

    localparam S_INIT = 0;
    localparam S_WAIT_TLB = 1;
    localparam S_WAIT_DRAM = 2;

    reg [W_STATE-1:0] r_state = S_INIT;
    reg [W_STATE-1:0] w_next_state;

    reg [N_ENTRY-1:0] r_valid = 0;
    reg [W_TAG-1:0] r_tag [0:N_ENTRY-1];
    reg [W_DATA-1:0] r_data [0:N_ENTRY-1];

    integer i;
    initial for (i = 0; i < N_ENTRY; i = i + 1) begin
        r_tag[i] = 0;
        r_data[i] = 0;
    end

    wire [W_INDEX-1:0] w_index = w_pc[W_OFFSET +: W_INDEX];
    initial if (W_OFFSET + W_INDEX > 12) $fatal("Cache size must not exceed 4KB for now.");

    wire [W_TAG-1:0] w_tag = w_pc[(W_OFFSET + W_INDEX) +: W_TAG];
    wire [W_TAG-1:0] w_tlb_tag = w_tlb_address[(W_OFFSET + W_INDEX) +: W_TAG];
    wire w_tag_match = (r_tag[w_index] == w_tag);
    wire w_tlb_tag_match = (r_tag[w_index] == w_tlb_tag);
    reg w_hit_t;
    reg [W_DATA-1:0] w_data_t;
    assign w_hit = w_hit_t;
    assign w_inst = w_data_t;

    wire [W_INDEX-1:0] w_invalidate_index = w_invalidate_address[W_OFFSET +: W_INDEX];
    wire [W_TAG-1:0] w_invalidate_tag = w_invalidate_address[(W_OFFSET + W_INDEX) +: W_TAG];
    wire w_invalidate_tag_match = (r_tag[w_invalidate_index] == w_invalidate_tag);
    assign w_invalidate_done = w_invalidate_request; // Assume that the invalidation is done immediately.

    always @(posedge CLK) begin
        if (!RST_X || w_flush) begin
            r_valid <= 0;
            r_state <= S_INIT;
        end else begin
            r_state <= w_next_state;
            // Assume that the invalidate request won't be asserted at the same time as the load of this HART compleates.
            if ((r_state == S_WAIT_DRAM) && w_dram_response) begin
                r_valid[w_index] <= 1;
                r_tag[w_index] <= (w_is_paddr) ? w_tag : w_tlb_tag;
                r_data[w_index] <= w_dram_data;
            end else if (w_invalidate_request && w_invalidate_tag_match) begin // We don't need to check the valid bit here.
                r_valid[w_invalidate_index] <= 1'b0;
            end
        end
    end

    always @(*) begin
        w_next_state = r_state;
        w_hit_t = 0;
        w_data_t = r_data[w_index];
        case (r_state)
            S_INIT: begin
                if (w_inst_request) begin
                    // First, check the TLB. Then, check the cache.
                    if (w_is_paddr) begin
                        if (r_valid[w_index] && w_tag_match) begin
                            w_hit_t = 1;
                        end else begin
                            w_next_state = S_WAIT_DRAM;
                        end
                    end else begin
                        if (w_tlb_hit) begin
                            if (r_valid[w_index] && w_tlb_tag_match) begin
                                w_hit_t = 1;
                            end else begin
                                w_next_state = S_WAIT_DRAM;
                            end
                        end else begin
                            w_next_state = S_WAIT_TLB;
                        end
                    end
                end
            end
            S_WAIT_TLB: begin // TLB miss. Wait for the page walk.
                if (w_tlb_hit) begin
                    if (r_valid[w_index] && w_tlb_tag_match) begin
                        w_hit_t = 1;
                        w_next_state = S_INIT;
                    end else begin
                        w_next_state = S_WAIT_DRAM;
                    end
                end else if (w_page_walk_fail) begin // Page walk failed. Go back to the initial state.
                    w_next_state = S_INIT;
                end
            end
            S_WAIT_DRAM: begin // Cache miss. Request the data from DRAM.
                if (w_dram_response) begin
                    w_next_state = S_INIT;
                    w_hit_t = 1;
                    w_data_t = w_dram_data;
                end
            end
        endcase
    end

endmodule

module m_data_cache_dmap #(
    parameter  W_DATA           = 128,
    parameter  N_ENTRY          = 32,
    localparam W_WORD           = 32,
    localparam W_ADDR           = `XLEN
) (
    input  wire               CLK,
    input  wire               RST_X,
    input  wire  [W_ADDR-1:0] w_data_addr,
    input  wire               w_data_request,
    input  wire               w_data_rw, // 0: read, 1: write
    input  wire  [W_WORD-1:0] w_store_data,
    input  wire         [2:0] w_funct3, // 0: byte, 1: half, 2: word
    input  wire  [W_DATA-1:0] w_dram_data,
    input  wire               w_dram_response,
    input  wire               w_is_paddr,
    input  wire               w_tlb_hit,
    input  wire               w_page_walk_fail,
    input  wire  [W_ADDR-1:0] w_tlb_address,
    input  wire               w_invalidate_request,
    input  wire        [31:0] w_invalidate_address,
    input  wire               w_flush,

    output wire               w_hit,
    output wire  [W_DATA-1:0] w_data,
    output wire  [W_ADDR-1:0] w_dram_address,
    output wire               w_dram_request,
    output wire               w_invalidate_done
);
    localparam N_WORDS = W_DATA / W_WORD; // The number of words in a cache line.
    localparam W_INDEX = $clog2(N_ENTRY);
    localparam W_OFFSET = $clog2(W_DATA/8);
    localparam W_TAG = W_ADDR - (W_OFFSET + W_INDEX);
    localparam N_STATES = 3;
    localparam W_STATE = $clog2(N_STATES);

    localparam S_INIT = 0;
    localparam S_WAIT_TLB = 1;
    localparam S_WAIT_DRAM = 2;

    reg [W_STATE-1:0] r_state = S_INIT;
    reg [W_STATE-1:0] w_next_state;

    reg [N_ENTRY-1:0] r_valid = 0;
    reg [W_TAG-1:0] r_tag [0:N_ENTRY-1];
    reg [W_DATA-1:0] r_data [0:N_ENTRY-1];

    integer i;
    initial for (i = 0; i < N_ENTRY; i = i + 1) begin
        r_tag[i] = 0;
        r_data[i] = 0;
    end

    wire [W_INDEX-1:0] w_index = w_data_addr[W_OFFSET +: W_INDEX];
    initial if (W_OFFSET + W_INDEX > 12) $fatal("Cache size must not exceed 4KB for now.");

    wire [W_TAG-1:0] w_tag = w_data_addr[(W_OFFSET + W_INDEX) +: W_TAG];
    wire [W_TAG-1:0] w_tlb_tag = w_tlb_address[(W_OFFSET + W_INDEX) +: W_TAG];
    wire w_tag_match = (r_tag[w_index] == w_tag);
    wire w_tlb_tag_match = (r_tag[w_index] == w_tlb_tag);
    reg w_hit_t;
    reg [W_DATA-1:0] w_data_t;
    assign w_hit = w_hit_t;
    assign w_data = w_data_t;

    wire [W_INDEX-1:0] w_invalidate_index = w_invalidate_address[W_OFFSET +: W_INDEX];
    wire [W_TAG-1:0] w_invalidate_tag = w_invalidate_address[(W_OFFSET + W_INDEX) +: W_TAG];
    wire w_invalidate_tag_match = (r_tag[w_invalidate_index] == w_invalidate_tag);
    assign w_invalidate_done = w_invalidate_request; // Assume that the invalidation is done immediately.

    wire [W_WORD-1:0] w_store_mask_word = (w_funct3[1]) ? 32'hffffffff : (w_funct3[0]) ? 32'h0000ffff : 32'h000000ff;
    wire [W_DATA-1:0] w_store_mask_line = {96'd0, w_store_mask_word} << {w_data_addr[3:0], 3'd0};
    wire [W_DATA-1:0] w_store_data_prep = {96'd0, w_store_data} << {w_data_addr[3:0], 3'd0};
    wire [W_DATA-1:0] w_store_data_line = (r_data[w_index] & ~w_store_mask_line) | (w_store_data_prep & w_store_mask_line);

    always @(posedge CLK) begin
        if (!RST_X || w_flush) begin
            r_valid <= 0;
            r_state <= S_INIT;
        end else begin
            r_state <= w_next_state;
            // Assume that the invalidate request won't be asserted at the same time as the load of this HART compleates.
            if (!w_data_rw && (r_state == S_WAIT_DRAM) && w_dram_response) begin // Load from memory.
                r_valid[w_index] <= 1;
                r_tag[w_index] <= (w_is_paddr) ? w_tag : w_tlb_tag;
                r_data[w_index] <= w_dram_data;
            end else if (w_data_rw && w_hit) begin // Store update.
                // In this case, r_valid and r_tag must have already been set.
                r_data[w_index] <= w_store_data_line;
            end else if (w_invalidate_request && w_invalidate_tag_match) begin // We don't need to check the valid bit here.
                r_valid[w_invalidate_index] <= 1'b0;
            end
        end
    end

    // NOTE: This cache is non-write-allocate. Don't go to the WAIT_DRAM state for store.
    always @(*) begin
        w_next_state = r_state;
        w_hit_t = 0;
        w_data_t = r_data[w_index];
        case (r_state)
            S_INIT: begin
                if (w_data_request) begin
                    // First, check the TLB. Then, check the cache.
                    if (w_is_paddr) begin
                        if (r_valid[w_index] && w_tag_match) begin
                            w_hit_t = 1;
                        end else if (!w_data_rw) begin
                            w_next_state = S_WAIT_DRAM;
                        end
                    end else begin
                        if (w_tlb_hit) begin
                            if (r_valid[w_index] && w_tlb_tag_match) begin
                                w_hit_t = 1;
                            end else if (!w_data_rw) begin
                                w_next_state = S_WAIT_DRAM;
                            end
                        end else begin
                            w_next_state = S_WAIT_TLB;
                        end
                    end
                end
            end
            S_WAIT_TLB: begin // TLB miss. Wait for the page walk.
                if (w_tlb_hit) begin
                    if (r_valid[w_index] && w_tlb_tag_match) begin
                        w_hit_t = 1;
                        w_next_state = S_INIT;
                    end else if (!w_data_rw) begin
                        w_next_state = S_WAIT_DRAM;
                    end else begin // Don't go to WAIT_DRAM for store.
                        w_next_state = S_INIT;
                    end
                end else if (w_page_walk_fail) begin // Page walk failed. Go back to the initial state.
                    w_next_state = S_INIT;
                end
            end
            S_WAIT_DRAM: begin // Cache miss. Request the data from DRAM.
                if (w_dram_response) begin
                    w_next_state = S_INIT;
                    w_hit_t = 1;
                    w_data_t = w_dram_data;
                end
            end
        endcase
    end

endmodule
