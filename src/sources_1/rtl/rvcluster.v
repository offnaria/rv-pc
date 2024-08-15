module m_RVCluster #(
    parameter N_HARTS = 1
)(
    input  wire               CLK,
    input  wire               RST_X,
    input  wire               w_stall,
    input  wire [127:0]       w_insn_data,
    input  wire [127:0]       w_data_data,
    input  wire               w_is_dram_data,
    input  wire [31:0]        w_wmip,
    input  wire               w_plic_we,
    input  wire               w_busy,
    input  wire [31:0]        w_pagefault,
    input  wire [2:0]         w_mc_mode,
    input  wire [N_HARTS-1:0] w_mtip,
    input  wire [N_HARTS-1:0] w_msip,
    input  wire [63:0]        w_mtime,

    output wire               r_halt,         // register, set if the processor is halted
    output wire [31:0]        w_data_wdata,   // from r_data_wdata
    output wire [31:0]        w_insn_addr,    // from r_insn_addr
    output wire [2:0]         w_data_ctrl,    // from r_data_ctrl
    output wire [31:0]        w_data_addr,    // from r_mem_addr
    output wire [31:0]        w_priv,         // from register priv
    output wire [31:0]        w_satp,         // from register satp
    output wire [31:0]        w_mstatus,      // from register mstatus
    output wire [31:0]        w_mip,          // from register mip
    output wire               w_init_stage,   // from r_init_stage
    output wire  [1:0]        w_tlb_req,      // from r_tlb_req
    output wire               w_data_we,      // from r_data_we, write enable for DRAM memory
    output wire               w_tlb_flush     // from r_tlb_flush
);

    // genvar i;
    // generate
    //     for (i = 0; i < N_HARTS; i = i + 1) begin
            
    //     end
    // endgenerate
    m_RVCorePL_SMP #(
        .MHARTID(0)
    )
    core0(
        .CLK(CLK),
        .RST_X(RST_X),
        .w_stall(w_stall),
        .w_insn_data(w_insn_data),
        .w_data_data(w_data_data),
        .w_is_dram_data(w_is_dram_data),
        .w_wmip(w_wmip),
        .w_plic_we(w_plic_we),
        .w_busy(w_busy),
        .w_pagefault(w_pagefault),
        .w_mc_mode(w_mc_mode),
        .w_mtip(w_mtip[0]),
        .w_msip(w_msip[0]),
        .w_mtime(w_mtime),
        .r_halt(r_halt),
        .w_data_wdata(w_data_wdata),
        .w_insn_addr(w_insn_addr),
        .w_data_ctrl(w_data_ctrl),
        .w_data_addr(w_data_addr),
        .w_priv(w_priv),
        .w_satp(w_satp),
        .w_mstatus(w_mstatus),
        .w_mip(w_mip),
        .w_init_stage(w_init_stage),
        .w_tlb_req(w_tlb_req),
        .w_data_we(w_data_we),
        .w_tlb_flush(w_tlb_flush)
    );

endmodule