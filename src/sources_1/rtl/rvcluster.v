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

    output wire               r_halt,
    output wire [31:0]        w_cluster_iaddr,
    output wire [31:0]        w_cluster_daddr,
    output wire [31:0]        w_cluster_data_wdata,
    output wire [2:0]         w_cluster_data_ctrl,
    output wire               w_cluster_init_stage,
    output wire               w_cluster_data_we,
    output wire               w_cluster_is_paddr,
    output wire               w_cluster_iscode,
    output wire               w_cluster_isread,
    output wire               w_cluster_iswrite,
    output wire               w_cluster_pte_we,
    output wire [31:0]        w_cluster_pte_wdata,
    output wire               w_cluster_use_tlb,
    output wire               w_cluster_tlb_hit,
    output wire [2:0]         w_cluster_pw_state,
    output wire               w_cluster_tlb_busy,
    output wire [2:0]         w_cluster_tlb_use,
    output wire [31:0]        w_cluster_tlb_pte_addr,
    output wire               w_cluster_tlb_acs
);

    wire [31:0] w_core_iaddr;
    wire [31:0] w_core_daddr;
    wire [31:0] w_core_data_wdata;
    wire [2:0]  w_core_data_ctrl;
    wire        w_core_init_stage;
    wire        w_core_data_we;
    wire        w_core_is_paddr;
    wire        w_core_iscode;
    wire        w_core_isread;
    wire        w_core_iswrite;
    wire        w_core_pte_we;
    wire [31:0] w_core_pte_wdata;
    wire        w_core_use_tlb;
    wire        w_core_tlb_hit;
    wire  [2:0] w_core_pw_state;
    wire        w_core_tlb_busy;
    wire  [2:0] w_core_tlb_use;
    wire [31:0] w_core_tlb_pte_addr;
    wire        w_core_tlb_acs;

    wire [31:0] w_pagefault;
    wire [31:0] w_mstatus;
    wire [1:0]  w_tlb_req;
    wire        w_tlb_flush;
    wire [31:0] w_priv;
    wire [31:0] w_satp;
    wire [31:0] w_insn_addr;
    wire [31:0] w_data_addr;
    wire [31:0] w_tlb_addr;

    assign w_core_is_paddr = (w_priv == `PRIV_M) || (w_satp[31] == 0);
    assign w_core_iaddr = (w_core_is_paddr) ? w_insn_addr : w_tlb_addr;
    assign w_core_daddr = (w_core_is_paddr) ? w_data_addr : w_tlb_addr;

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
        .w_data_wdata(w_core_data_wdata),
        .w_insn_addr(w_insn_addr),
        .w_data_ctrl(w_core_data_ctrl),
        .w_data_addr(w_data_addr),
        .w_priv(w_priv),
        .w_satp(w_satp),
        .w_mstatus(w_mstatus),
        .w_init_stage(w_core_init_stage),
        .w_tlb_req(w_tlb_req),
        .w_data_we(w_core_data_we),
        .w_tlb_flush(w_tlb_flush)
    );

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
        .w_iscode(w_core_iscode),
        .w_isread(w_core_isread),
        .w_iswrite(w_core_iswrite),
        .w_pte_we(w_core_pte_we),
        .w_pte_wdata(w_core_pte_wdata),
        .w_pagefault(w_pagefault),
        .w_use_tlb(w_core_use_tlb),
        .w_tlb_hit(w_core_tlb_hit),
        .w_pw_state(w_core_pw_state),
        .w_tlb_busy(w_core_tlb_busy),
        .w_tlb_addr(w_tlb_addr),
        .w_tlb_use(w_core_tlb_use),
        .w_tlb_pte_addr(w_core_tlb_pte_addr),
        .w_tlb_acs(w_core_tlb_acs)
    );

    assign w_cluster_iaddr = w_core_iaddr;
    assign w_cluster_daddr = w_core_daddr;
    assign w_cluster_data_wdata = w_core_data_wdata;
    assign w_cluster_data_ctrl = w_core_data_ctrl;
    assign w_cluster_init_stage = w_core_init_stage;
    assign w_cluster_data_we = w_core_data_we;
    assign w_cluster_is_paddr = w_core_is_paddr;
    assign w_cluster_iscode = w_core_iscode;
    assign w_cluster_isread = w_core_isread;
    assign w_cluster_iswrite = w_core_iswrite;
    assign w_cluster_pte_we = w_core_pte_we;
    assign w_cluster_pte_wdata = w_core_pte_wdata;
    assign w_cluster_use_tlb = w_core_use_tlb;
    assign w_cluster_tlb_hit = w_core_tlb_hit;
    assign w_cluster_pw_state = w_core_pw_state;
    assign w_cluster_tlb_busy = w_core_tlb_busy;
    assign w_cluster_tlb_use = w_core_tlb_use;
    assign w_cluster_tlb_pte_addr = w_core_tlb_pte_addr;
    assign w_cluster_tlb_acs = w_core_tlb_acs;
endmodule