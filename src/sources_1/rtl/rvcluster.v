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

    wire [31:0] w_core_iaddr        [0:N_HARTS-1];
    wire [31:0] w_core_daddr        [0:N_HARTS-1];
    wire [31:0] w_core_data_wdata   [0:N_HARTS-1];
    wire [2:0]  w_core_data_ctrl    [0:N_HARTS-1];
    wire        w_core_init_stage   [0:N_HARTS-1];
    wire        w_core_data_we      [0:N_HARTS-1];
    wire        w_core_is_paddr     [0:N_HARTS-1];
    wire        w_core_iscode       [0:N_HARTS-1];
    wire        w_core_isread       [0:N_HARTS-1];
    wire        w_core_iswrite      [0:N_HARTS-1];
    wire        w_core_pte_we       [0:N_HARTS-1];
    wire [31:0] w_core_pte_wdata    [0:N_HARTS-1];
    wire        w_core_use_tlb      [0:N_HARTS-1];
    wire        w_core_tlb_hit      [0:N_HARTS-1];
    wire  [2:0] w_core_pw_state     [0:N_HARTS-1];
    wire        w_core_tlb_busy     [0:N_HARTS-1];
    wire  [2:0] w_core_tlb_use      [0:N_HARTS-1];
    wire [31:0] w_core_tlb_pte_addr [0:N_HARTS-1];
    wire        w_core_tlb_acs      [0:N_HARTS-1];

    wire [N_HARTS-1:0] w_core_busy;
    wire [N_HARTS-1:0] w_core_dram_busy;
    wire [N_HARTS-1:0] w_next_state_is_idle;
    wire [N_HARTS-1:0] w_mem_access_state_is_idle;
    wire [N_HARTS-1:0] w_exmem_op_csr;

    genvar g;
    generate
        for (g = 0; g < N_HARTS; g = g + 1) begin: cores_and_mmus
            wire [31:0] w_pagefault;
            wire [31:0] w_mstatus;
            wire [1:0]  w_tlb_req;
            wire        w_tlb_flush;
            wire [31:0] w_priv;
            wire [31:0] w_satp;
            wire [31:0] w_insn_addr;
            wire [31:0] w_data_addr;
            wire [31:0] w_tlb_addr;

            assign w_core_is_paddr[g] = (w_priv == `PRIV_M) || (w_satp[31] == 0);
            assign w_core_iaddr[g] = (w_core_is_paddr[g]) ? w_insn_addr : w_tlb_addr;
            assign w_core_daddr[g] = (w_core_is_paddr[g]) ? w_data_addr : w_tlb_addr;

            m_RVCorePL_SMP #(
                .MHARTID(g)
            ) core (
                .CLK(CLK),
                .RST_X(RST_X),
                .w_stall(w_stall),
                .w_insn_data(w_insn_data),
                .w_data_data(w_data_data),
                .w_is_dram_data(w_is_dram_data),
                .w_busy(w_core_busy[g]),
                .w_pagefault(w_pagefault),
                .w_mc_mode(w_mc_mode),
                .w_mtip(w_mtip[0]),
                .w_msip(w_msip[0]),
                .w_meip(w_meip[0]),
                .w_seip(w_seip[0]),
                .w_mtime(w_mtime),
                .r_halt(r_halt),
                .w_data_wdata(w_core_data_wdata[g]),
                .w_insn_addr(w_insn_addr),
                .w_data_ctrl(w_core_data_ctrl[g]),
                .w_data_addr(w_data_addr),
                .w_priv(w_priv),
                .w_satp(w_satp),
                .w_mstatus(w_mstatus),
                .w_init_stage(w_core_init_stage[g]),
                .w_tlb_req(w_tlb_req),
                .w_data_we(w_core_data_we[g]),
                .w_tlb_flush(w_tlb_flush)
            );

            m_mmu mmu (
                .CLK(CLK),
                .w_tlb_req(w_tlb_req),
                .w_insn_addr(w_insn_addr),
                .w_data_addr(w_data_addr),
                .w_priv(w_priv),
                .w_satp(w_satp),
                .w_mstatus(w_mstatus),
                .w_dram_busy(w_core_dram_busy[g]),
                .w_dram_odata(w_dram_odata),
                .w_tlb_flush(w_tlb_flush),
                .w_mode_is_cpu(w_mode_is_cpu),
                .w_iscode(w_core_iscode[g]),
                .w_isread(w_core_isread[g]),
                .w_iswrite(w_core_iswrite[g]),
                .w_pte_we(w_core_pte_we[g]),
                .w_pte_wdata(w_core_pte_wdata[g]),
                .w_pagefault(w_pagefault),
                .w_use_tlb(w_core_use_tlb[g]),
                .w_tlb_hit(w_core_tlb_hit[g]),
                .w_pw_state(w_core_pw_state[g]),
                .w_tlb_busy(w_core_tlb_busy[g]),
                .w_tlb_addr(w_tlb_addr),
                .w_tlb_use(w_core_tlb_use[g]),
                .w_tlb_pte_addr(w_core_tlb_pte_addr[g]),
                .w_tlb_acs(w_core_tlb_acs[g])
            );

            assign w_next_state_is_idle[g] = (core.next_state == 0);
            assign w_mem_access_state_is_idle[g] = (core.mem_access_state == 0);
            assign w_exmem_op_csr[g] = core.ExMem_op_CSR;
        end
    endgenerate

    /****************************** Cluster Arbiter ******************************/
    generate
        begin: arbiter
            reg [$clog2(N_HARTS+1)-1:0] r_hart_sel;
            always @ (posedge CLK) begin
                if (!RST_X) begin
                    r_hart_sel <= 0;
                end else begin
                    r_hart_sel <= (w_next_state_is_idle[r_hart_sel] && !w_exmem_op_csr[r_hart_sel]) ? (r_hart_sel == N_HARTS-1) ? 0 : r_hart_sel + 1 : r_hart_sel;
                end
            end

            assign w_cluster_iaddr = w_core_iaddr[r_hart_sel];
            assign w_cluster_daddr = w_core_daddr[r_hart_sel];
            assign w_cluster_data_wdata = w_core_data_wdata[r_hart_sel];
            assign w_cluster_data_ctrl = w_core_data_ctrl[r_hart_sel];
            assign w_cluster_init_stage = w_core_init_stage[r_hart_sel];
            assign w_cluster_data_we = w_core_data_we[r_hart_sel];
            assign w_cluster_is_paddr = w_core_is_paddr[r_hart_sel];
            assign w_cluster_iscode = w_core_iscode[r_hart_sel];
            assign w_cluster_isread = w_core_isread[r_hart_sel];
            assign w_cluster_iswrite = w_core_iswrite[r_hart_sel];
            assign w_cluster_pte_we = w_core_pte_we[r_hart_sel];
            assign w_cluster_pte_wdata = w_core_pte_wdata[r_hart_sel];
            assign w_cluster_use_tlb = w_core_use_tlb[r_hart_sel];
            assign w_cluster_tlb_hit = w_core_tlb_hit[r_hart_sel];
            assign w_cluster_pw_state = w_core_pw_state[r_hart_sel];
            assign w_cluster_tlb_busy = w_core_tlb_busy[r_hart_sel];
            assign w_cluster_tlb_use = w_core_tlb_use[r_hart_sel];
            assign w_cluster_tlb_pte_addr = w_core_tlb_pte_addr[r_hart_sel];
            assign w_cluster_tlb_acs = w_core_tlb_acs[r_hart_sel];
            for (g = 0; g < N_HARTS; g = g + 1) begin
                assign w_core_busy[g] = (r_hart_sel == g) ? w_busy : 1;
                assign w_core_dram_busy[g] = (r_hart_sel == g) ? w_dram_busy : 1;
            end
        end
    endgenerate
endmodule