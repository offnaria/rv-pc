module m_RVCluster #(
    parameter N_HARTS = 1
)(
    input  wire               CLK,
    input  wire               RST_X,
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
    input  wire               w_next_mode_is_mc,

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

    wire [31:0] w_core_pagefault    [0:N_HARTS-1];
    wire [31:0] w_core_mstatus      [0:N_HARTS-1];
    wire [1:0]  w_core_tlb_req      [0:N_HARTS-1];
    wire [31:0] w_core_priv         [0:N_HARTS-1];
    wire [31:0] w_core_satp         [0:N_HARTS-1];
    wire [31:0] w_core_tlb_addr     [0:N_HARTS-1];

    wire [N_HARTS-1:0] w_core_busy;
    wire [N_HARTS-1:0] w_core_dram_busy;
    wire [N_HARTS-1:0] w_core_next_state_is_idle;
    wire [N_HARTS-1:0] w_core_mem_access_state_is_idle;
    wire [N_HARTS-1:0] w_core_exmem_op_csr;
    wire [N_HARTS-1:0] w_core_tkn;
    wire [N_HARTS-1:0] w_core_take_exception;
    wire [N_HARTS-1:0] w_core_tlb_flush;

    wire [31:0] w_core_local_iaddr  [0:N_HARTS-1];
    wire [31:0] w_core_local_daddr  [0:N_HARTS-1];

    wire w_flush_all_tlbs = |w_core_tlb_flush;

    (* keep = "true" *) wire [31:0] w_core_pc [0:N_HARTS-1];

    genvar g;
    generate
        for (g = 0; g < N_HARTS; g = g + 1) begin: cores_and_mmus
            assign w_core_is_paddr[g] = (w_core_priv[g] == `PRIV_M) || (w_core_satp[g][31] == 0);
            assign w_core_iaddr[g] = (w_core_is_paddr[g]) ? w_core_local_iaddr[g] : w_core_tlb_addr[g];
            assign w_core_daddr[g] = (w_core_is_paddr[g]) ? w_core_local_daddr[g] : w_core_tlb_addr[g];

            m_RVCorePL_SMP #(
                .MHARTID(g)
            ) core (
                .CLK(CLK),
                .RST_X(RST_X),
                .w_insn_data(w_insn_data),
                .w_data_data(w_data_data),
                .w_is_dram_data(w_is_dram_data),
                .w_busy(w_core_busy[g]),
                .w_pagefault(w_core_pagefault[g]),
                .w_mc_mode(w_mc_mode),
                .w_mtip(w_mtip[g]),
                .w_msip(w_msip[g]),
                .w_meip(w_meip[g]),
                .w_seip(w_seip[g]),
                .w_mtime(w_mtime),
                .r_halt(r_halt),
                .w_data_wdata(w_core_data_wdata[g]),
                .w_insn_addr(w_core_local_iaddr[g]),
                .w_data_ctrl(w_core_data_ctrl[g]),
                .w_data_addr(w_core_local_daddr[g]),
                .w_priv(w_core_priv[g]),
                .w_satp(w_core_satp[g]),
                .w_mstatus(w_core_mstatus[g]),
                .w_init_stage(w_core_init_stage[g]),
                .w_tlb_req(w_core_tlb_req[g]),
                .w_data_we(w_core_data_we[g]),
                .w_tlb_flush(w_core_tlb_flush[g])
            );

            assign w_core_next_state_is_idle[g] = (core.next_state == 0);
            assign w_core_mem_access_state_is_idle[g] = (core.mem_access_state == 0);
            assign w_core_exmem_op_csr[g] = core.ExMem_op_CSR;
            assign w_core_tkn[g] = core.tkn;
            assign w_core_pc[g] = core.pc;
            assign w_core_take_exception[g] = core.w_take_exception;
        end
    endgenerate

    m_mmu mmu (
        .CLK(CLK),
        .w_tlb_req(w_core_tlb_req[r_hart_sel]),
        .w_insn_addr(w_core_local_iaddr[r_hart_sel]),
        .w_data_addr(w_core_local_daddr[r_hart_sel]),
        .w_priv(w_core_priv[r_hart_sel]),
        .w_satp(w_core_satp[r_hart_sel]),
        .w_mstatus(w_core_mstatus[r_hart_sel]),
        .w_dram_busy(w_core_dram_busy[r_hart_sel]),
        .w_dram_odata(w_dram_odata),
        .w_tlb_flush(w_flush_all_tlbs),
        .w_mode_is_cpu(w_mode_is_cpu),
        .w_iscode(w_core_iscode[r_hart_sel]),
        .w_isread(w_core_isread[r_hart_sel]),
        .w_iswrite(w_core_iswrite[r_hart_sel]),
        .w_pte_we(w_core_pte_we[r_hart_sel]),
        .w_pte_wdata(w_core_pte_wdata[r_hart_sel]),
        .w_pagefault(w_core_pagefault[r_hart_sel]),
        .w_use_tlb(w_core_use_tlb[r_hart_sel]),
        .w_tlb_hit(w_core_tlb_hit[r_hart_sel]),
        .w_pw_state(w_core_pw_state[r_hart_sel]),
        .w_tlb_busy(w_core_tlb_busy[r_hart_sel]),
        .w_tlb_addr(w_core_tlb_addr[r_hart_sel]),
        .w_tlb_use(w_core_tlb_use[r_hart_sel]),
        .w_tlb_pte_addr(w_core_tlb_pte_addr[r_hart_sel]),
        .w_tlb_acs(w_core_tlb_acs[r_hart_sel])
    );

    /****************************** Cluster Arbiter ******************************/
    reg [$clog2(N_HARTS+1)-1:0] r_hart_sel;
    always @ (posedge CLK) begin
        if (!RST_X) begin
            r_hart_sel <= 0;
        end else begin
            r_hart_sel <= (!w_next_mode_is_mc && w_mode_is_cpu && w_core_next_state_is_idle[r_hart_sel] && !w_core_exmem_op_csr[r_hart_sel] && w_core_tkn[r_hart_sel] && !w_core_take_exception[r_hart_sel]) ? (r_hart_sel == N_HARTS-1) ? 0 : r_hart_sel + 1 : r_hart_sel;
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

// `ifdef SYNTHESIS
//     ila_0 your_instance_name (
//         .clk(CLK), // input wire clk
//         .probe0(w_core_pc[0]), // input wire [31:0]  probe0  
//         .probe1(w_core_pc[1]), // input wire [31:0]  probe1 
//         .probe2(cores_and_mmus[0].w_pagefault), // input wire [31:0]  probe2 
//         .probe3(cores_and_mmus[1].w_pagefault), // input wire [31:0]  probe3 
//         .probe4(r_hart_sel), // input wire [3:0]  probe4 
//         .probe5(cores_and_mmus[0].core.w_take_exception), // input wire [0:0]  probe5 
//         .probe6(cores_and_mmus[1].core.w_take_exception) // input wire [0:0]  probe6
//     );
// `endif
endmodule