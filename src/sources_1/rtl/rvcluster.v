module m_RVCluster #(
    parameter N_HARTS = 1
)(
    input  wire               CLK,
    input  wire               RST_X,
    input  wire               w_stall,
    input  wire [127:0]       w_insn_data,
    input  wire [127:0]       w_data_data,
    input  wire               w_is_dram_data,
    input  wire               w_busy,
    input  wire [2:0]         w_mc_mode,
    input  wire [N_HARTS-1:0] w_mtip,
    input  wire [N_HARTS-1:0] w_msip,
    input  wire [N_HARTS-1:0] w_meip,
    input  wire [N_HARTS-1:0] w_seip,
    input  wire [63:0]        w_mtime,
    input  wire               w_dram_busy,
    input  wire [31:0]        w_dram_odata,
    input  wire               w_mode_is_cpu,

    output wire               r_halt,         // register, set if the processor is halted
    output wire [31:0]        w_data_wdata,   // from r_data_wdata
    output wire [31:0]        w_insn_addr,    // from r_insn_addr
    output wire [2:0]         w_data_ctrl,    // from r_data_ctrl
    output wire [31:0]        w_data_addr,    // from r_mem_addr
    output wire               w_init_stage,   // from r_init_stage
    output wire               w_data_we       // from r_data_we, write enable for DRAM memory
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
        .w_busy(w_busy),
        .w_pagefault(w_pagefault),
        .w_mc_mode(w_mc_mode),
        .w_mtip(w_mtip[0]),
        .w_msip(w_msip[0]),
        .w_meip(w_meip[0]),
        .w_seip(w_seip[0]),
        .w_mtime(w_mtime),
        .r_halt(r_halt),
        .w_data_wdata(w_data_wdata),
        .w_insn_addr(w_insn_addr),
        .w_data_ctrl(w_data_ctrl),
        .w_data_addr(w_data_addr),
        .w_priv(w_priv),
        .w_satp(w_satp),
        .w_mstatus(w_mstatus),
        .w_init_stage(w_init_stage),
        .w_tlb_req(w_tlb_req),
        .w_data_we(w_data_we),
        .w_tlb_flush(w_tlb_flush)
    );

    wire [31:0] w_pagefault;
    wire [31:0] w_mstatus;
    wire [1:0]  w_tlb_req;
    wire        w_tlb_flush;
    wire        w_iscode;
    wire        w_isread;
    wire        w_iswrite;
    wire        w_pte_we;
    wire [31:0] w_pte_wdata;
    wire        w_use_tlb;
    wire        w_tlb_hit;
    wire  [2:0] w_pw_state;
    wire        w_tlb_busy;
    wire [31:0] w_tlb_addr;
    wire  [2:0] w_tlb_use;
    wire [31:0] w_tlb_pte_addr;
    wire        w_tlb_acs;
    m_mmu mmu0 (
        .CLK(CLK),
        .w_tlb_req(w_tlb_req),
        .w_insn_addr(w_insn_addr),
        .w_data_addr(w_data_addr),
        .w_priv(w_priv),
        .w_satp(w_satp),
        .w_mstatus(w_mstatus),
        .w_dram_busy(w_dram_busy),
        .w_dram_odata(w_dram_odata),
        .w_tlb_flush(w_tlb_flush),
        .w_mode_is_cpu(w_mode_is_cpu),
        .w_iscode(w_iscode),
        .w_isread(w_isread),
        .w_iswrite(w_iswrite),
        .w_pte_we(w_pte_we),
        .w_pte_wdata(w_pte_wdata),
        .w_pagefault(w_pagefault),
        .w_use_tlb(w_use_tlb),
        .w_tlb_hit(w_tlb_hit),
        .w_pw_state(w_pw_state),
        .w_tlb_busy(w_tlb_busy),
        .w_tlb_addr(w_tlb_addr),
        .w_tlb_use(w_tlb_use),
        .w_tlb_pte_addr(w_tlb_pte_addr),
        .w_tlb_acs(w_tlb_acs)
    );

    wire [31:0] w_priv;
    wire [31:0] w_satp;
    wire w_is_paddr = (w_priv == `PRIV_M) || (w_satp[31] == 0);

endmodule