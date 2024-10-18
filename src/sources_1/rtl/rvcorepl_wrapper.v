module m_RVCorePL_wrapper #(
    parameter CACHED = 0,
    parameter MHARTID = 0
) (
    input  wire         CLK,
    input  wire         RST_X,
    input  wire [127:0] w_insn_data,
    input  wire [127:0] w_data_data,
    input  wire         w_is_dram_data,
    input  wire         w_busy,
    input  wire [31:0]  w_pagefault,
    input  wire [2:0]   w_mc_mode,
    input  wire         w_mtip,
    input  wire         w_msip,
    input  wire         w_meip,
    input  wire         w_seip,
    input  wire [63:0]  w_mtime,
    input  wire         w_cache_invalidate,
    input  wire [31:0]  w_cache_invalidate_address,

    output wire [31:0]  w_data_wdata,
    output wire [31:0]  w_insn_addr,
    output wire [2:0]   w_data_ctrl,
    output wire [31:0]  w_data_addr,
    output wire [31:0]  w_priv,
    output wire [31:0]  w_satp,
    output wire [31:0]  w_mstatus,
    output wire         w_init_stage,
    output wire  [1:0]  w_tlb_req,
    output wire         w_tlb_flush,
    output wire         w_is_amo
);

    wire [127:0] w_instance_insn_data;
    wire [127:0] w_instance_data_data;
    wire         w_instance_is_dram_data;
    wire         w_instance_busy;
    wire [31:0]  w_instance_pagefault;
    wire [2:0]   w_instance_mc_mode;
    wire         w_instance_mtip;
    wire         w_instance_msip;
    wire         w_instance_meip;
    wire         w_instance_seip;
    wire [63:0]  w_instance_mtime;
    wire         w_instance_cache_invalidate;
    wire [31:0]  w_instance_cache_invalidate_address;

    wire [31:0]  w_instance_data_wdata;
    wire [31:0]  w_instance_insn_addr;
    wire [2:0]   w_instance_data_ctrl;
    wire [31:0]  w_instance_data_addr;
    wire [31:0]  w_instance_priv;
    wire [31:0]  w_instance_satp;
    wire [31:0]  w_instance_mstatus;
    wire         w_instance_init_stage;
    wire  [1:0]  w_instance_tlb_req;
    wire         w_instance_tlb_flush;
    wire         w_instance_is_amo;

    generate
        if (CACHED) begin
            
        end else begin
            assign w_instance_insn_data = w_insn_data;
            assign w_instance_data_data = w_data_data;
            assign w_instance_is_dram_data = w_is_dram_data;
            assign w_instance_busy = w_busy;
            assign w_instance_pagefault = w_pagefault;
            assign w_instance_mc_mode = w_mc_mode;
            assign w_instance_mtip = w_mtip;
            assign w_instance_msip = w_msip;
            assign w_instance_meip = w_meip;
            assign w_instance_seip = w_seip;
            assign w_instance_mtime = w_mtime;
            assign w_instance_cache_invalidate = w_cache_invalidate;
            assign w_instance_cache_invalidate_address = w_cache_invalidate_address;

            assign w_data_wdata = w_instance_data_wdata;
            assign w_insn_addr = w_instance_insn_addr;
            assign w_data_ctrl = w_instance_data_ctrl;
            assign w_data_addr = w_instance_data_addr;
            assign w_priv = w_instance_priv;
            assign w_satp = w_instance_satp;
            assign w_mstatus = w_instance_mstatus;
            assign w_init_stage = w_instance_init_stage;
            assign w_tlb_req = w_instance_tlb_req;
            assign w_tlb_flush = w_instance_tlb_flush;
            assign w_is_amo = w_instance_is_amo;
        end
    endgenerate

    m_RVCorePL_SMP #(
        .MHARTID(MHARTID)
    ) core_inst (
        .CLK(CLK),
        .RST_X(RST_X),
        .w_insn_data(w_instance_insn_data),
        .w_data_data(w_instance_data_data),
        .w_is_dram_data(w_instance_is_dram_data),
        .w_busy(w_instance_busy),
        .w_pagefault(w_instance_pagefault),
        .w_mc_mode(w_instance_mc_mode),
        .w_mtip(w_instance_mtip),
        .w_msip(w_instance_msip),
        .w_meip(w_instance_meip),
        .w_seip(w_instance_seip),
        .w_mtime(w_instance_mtime),
        .w_cache_invalidate(w_instance_cache_invalidate),
        .w_cache_invalidate_address(w_instance_cache_invalidate_address),
        .w_data_wdata(w_instance_data_wdata),
        .w_insn_addr(w_instance_insn_addr),
        .w_data_ctrl(w_instance_data_ctrl),
        .w_data_addr(w_instance_data_addr),
        .w_priv(w_instance_priv),
        .w_satp(w_instance_satp),
        .w_mstatus(w_instance_mstatus),
        .w_init_stage(w_instance_init_stage),
        .w_tlb_req(w_instance_tlb_req),
        .w_tlb_flush(w_instance_tlb_flush),
        .w_is_amo(w_instance_is_amo)
    );
    
endmodule
