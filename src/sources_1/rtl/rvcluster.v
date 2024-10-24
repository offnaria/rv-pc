module m_RVCluster #(
    parameter N_HARTS = 1
)(
    input  wire               CLK,
    input  wire               RST_X,
    input  wire [127:0]       w_insn_data,
    input  wire [127:0]       w_data_data,
    input  wire               w_is_dram_data,
    input  wire               w_interconnect_busy,
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

    output wire [31:0]        w_cluster_iaddr,
    output wire [31:0]        w_cluster_daddr,
    output wire [31:0]        w_cluster_data_wdata,
    output wire               w_cluster_init_stage,
    output wire               w_cluster_is_paddr,
    output wire               w_cluster_iscode,
    output wire               w_cluster_isread,
    output wire               w_cluster_iswrite,
    output wire               w_cluster_pte_we,
    output wire [31:0]        w_cluster_pte_wdata,
    output wire               w_cluster_use_tlb,
    output wire               w_cluster_tlb_hit,
    output wire [2:0]         w_cluster_pw_state,
    output wire [2:0]         w_cluster_tlb_usage,
    output wire [31:0]        w_cluster_tlb_pte_addr,
    output wire               w_cluster_tlb_acs,
    output wire               w_cluster_data_we,
    output wire [31:0]        w_cluster_dev_addr,
    output wire [31:0]        w_cluster_dram_addr,
    output wire [2:0]         w_cluster_mem_ctrl,
    output wire               w_cluster_dram_re
);

    localparam DEBUG = 0;

    wire w_cluster_tlb_busy;
    wire w_cluster_pw_done;
    wire w_cluster_pw_running = w_cluster_use_tlb && !w_cluster_pw_done;

    assign w_cluster_data_we   = w_cluster_iswrite && !w_cluster_pw_running;
    assign w_cluster_dev_addr  = w_cluster_daddr;
    assign w_cluster_dram_addr = (w_cluster_iscode && !w_cluster_pw_running) ? w_cluster_iaddr : (w_cluster_is_paddr || !w_cluster_tlb_acs || w_cluster_tlb_hit) ? w_cluster_dev_addr : w_cluster_tlb_pte_addr;
    assign w_cluster_mem_ctrl  = (w_cluster_iscode && !w_cluster_pw_running) ? `FUNCT3_LW____ : 
                                 (w_cluster_is_paddr)                        ? w_core_mem_ctrl[r_hart_sel] :
                                 (w_cluster_tlb_usage[1:0]!=0)               ? w_core_mem_ctrl[r_hart_sel] :
                                 (w_cluster_pw_state == 0)                   ? `FUNCT3_LW____              :
                                 (w_cluster_pw_state == 2)                   ? `FUNCT3_LW____              :
                                 (w_cluster_pw_state == 5)                   ? `FUNCT3_SW____              :
                                 w_core_mem_ctrl[r_hart_sel];
    assign w_cluster_dram_re   = (w_cluster_is_paddr) ? (w_cluster_iscode || w_cluster_isread) :
                                 (w_cluster_tlb_usage[2:1]!=0) ? 1 :
                                 (w_cluster_pw_running && !w_cluster_tlb_hit && (w_cluster_pw_state == 0 || w_cluster_pw_state==2)) ? 1 : 0;

    wire [31:0] w_core_iaddr        [0:N_HARTS-1];
    wire [31:0] w_core_daddr        [0:N_HARTS-1];
    wire [31:0] w_core_data_wdata   [0:N_HARTS-1];
    wire [2:0]  w_core_mem_ctrl     [0:N_HARTS-1];
    wire        w_core_init_stage   [0:N_HARTS-1];
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
    wire  [2:0] w_core_tlb_usage    [0:N_HARTS-1];
    wire [31:0] w_core_tlb_pte_addr [0:N_HARTS-1];
    wire        w_core_tlb_acs      [0:N_HARTS-1];

    wire [31:0] w_core_pagefault    [0:N_HARTS-1];
    wire [31:0] w_core_mstatus      [0:N_HARTS-1];
    wire [1:0]  w_core_tlb_req      [0:N_HARTS-1];
    wire [31:0] w_core_priv         [0:N_HARTS-1];
    wire [31:0] w_core_satp         [0:N_HARTS-1];
    wire [31:0] w_core_tlb_addr;

    wire [N_HARTS-1:0] w_core_busy;
    wire [N_HARTS-1:0] w_core_next_state_is_idle;
    wire [N_HARTS-1:0] w_core_mem_access_state_is_idle;
    wire [N_HARTS-1:0] w_core_interrupt_ok;
    wire [N_HARTS-1:0] w_core_tkn;
    wire [N_HARTS-1:0] w_core_take_exception;
    wire [N_HARTS-1:0] w_core_tlb_flush;
    wire [N_HARTS-1:0] w_core_csr_flush;
    wire [N_HARTS-1:0] w_core_is_amo_load;

    wire [31:0] w_core_local_iaddr  [0:N_HARTS-1];
    wire [31:0] w_core_local_daddr  [0:N_HARTS-1];

    wire w_flush_all_tlbs = |w_core_tlb_flush;

    (* keep = "true" *) wire [31:0] w_core_pc [0:N_HARTS-1];

    genvar g;
    generate
        for (g = 0; g < N_HARTS; g = g + 1) begin: cores_and_mmus
            assign w_core_is_paddr[g] = (w_core_priv[g] == `PRIV_M) || (w_core_satp[g][31] == 0);
            assign w_core_iaddr[g] = (w_core_is_paddr[g]) ? w_core_local_iaddr[g] : w_core_tlb_addr;
            assign w_core_daddr[g] = (w_core_is_paddr[g]) ? w_core_local_daddr[g] : w_core_tlb_addr;

            m_RVCorePL_wrapper #(
                .CACHED(0),
                .MHARTID(g)
            ) core_wrapper (
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
                .w_cache_invalidate(w_cluster_data_we && (r_hart_sel != g) && (w_cluster_dev_addr[31:28] == `MEM_BASE_TADDR)),
                .w_cache_invalidate_address(w_cluster_dev_addr),
                .w_data_wdata(w_core_data_wdata[g]),
                .w_insn_addr(w_core_local_iaddr[g]),
                .w_data_ctrl(w_core_mem_ctrl[g]),
                .w_data_addr(w_core_local_daddr[g]),
                .w_priv(w_core_priv[g]),
                .w_satp(w_core_satp[g]),
                .w_mstatus(w_core_mstatus[g]),
                .w_init_stage(w_core_init_stage[g]),
                .w_tlb_req(w_core_tlb_req[g]),
                .w_tlb_flush(w_core_tlb_flush[g]),
                .w_is_amo_load(w_core_is_amo_load[g])
            );

            assign w_core_next_state_is_idle[g] = (core_wrapper.core_inst.next_state == 0);
            assign w_core_mem_access_state_is_idle[g] = (core_wrapper.core_inst.mem_access_state == 0);
            assign w_core_interrupt_ok[g] = core_wrapper.core_inst.w_interrupt_ok;
            assign w_core_tkn[g] = core_wrapper.core_inst.tkn;
            assign w_core_pc[g] = core_wrapper.core_inst.pc;
            assign w_core_take_exception[g] = core_wrapper.core_inst.w_take_exception;
            assign w_core_csr_flush[g] = core_wrapper.core_inst.w_csr_flush;
        end
    endgenerate

    wire [31:0] w_mmu_pagefault;
    m_mmu mmu (
        .CLK(CLK),
        .w_tlb_req(w_core_tlb_req[r_hart_sel]),
        .w_insn_addr(w_core_local_iaddr[r_hart_sel]),
        .w_data_addr(w_core_local_daddr[r_hart_sel]),
        .w_priv(w_core_priv[r_hart_sel]),
        .w_satp(w_core_satp[r_hart_sel]),
        .w_mstatus(w_core_mstatus[r_hart_sel]),
        .w_dram_busy(w_dram_busy),
        .w_dram_odata(w_dram_odata),
        .w_tlb_flush(w_flush_all_tlbs),
        .w_mode_is_cpu(w_mode_is_cpu),
        .w_is_amo_load(w_core_is_amo_load[r_hart_sel]),
        .w_iscode(w_cluster_iscode),
        .w_isread(w_cluster_isread),
        .w_iswrite(w_cluster_iswrite),
        .w_pte_we(w_cluster_pte_we),
        .w_pte_wdata(w_cluster_pte_wdata),
        .w_pagefault(w_mmu_pagefault),
        .w_use_tlb(w_cluster_use_tlb),
        .w_tlb_hit(w_cluster_tlb_hit),
        .w_pw_state(w_cluster_pw_state),
        .w_tlb_busy(w_cluster_tlb_busy),
        .w_tlb_addr(w_core_tlb_addr),
        .w_tlb_usage(w_cluster_tlb_usage),
        .w_tlb_pte_addr(w_cluster_tlb_pte_addr),
        .w_tlb_acs(w_cluster_tlb_acs),
        .w_pw_done(w_cluster_pw_done)
    );
`ifdef SYNTHESIS
generate
    if (DEBUG) begin
        ila_mmu_permission ila_mmu_permission (
            .clk(CLK), // input wire clk
            .probe0(w_core_priv[r_hart_sel]), // input wire [0:0]  probe0  
            .probe1(w_core_priv[r_hart_sel]), // input wire [31:0]  probe1 
            .probe2(mmu.w_tlb_permission), // input wire [7:0]  probe2 
            .probe3(w_core_mstatus[r_hart_sel]), // input wire [31:0]  probe3 
            .probe4(mmu.w_tlb_hit), // input wire [0:0]  probe4 
            .probe5(w_cluster_pw_state), // input wire [2:0]  probe5 
            .probe6(w_cluster_tlb_usage), // input wire [3:0]  probe6 
            .probe7(w_core_local_iaddr[0]), // input wire [31:0]  probe7
            .probe8(mmu.w_tlb_permission_miss), // input wire [0:0]  probe8
            .probe9(w_core_local_iaddr[1]),
            .probe10(r_hart_sel),
            .probe11(mmu.w_tlb_dirty_miss)
        );
    end
endgenerate
`endif

    /****************************** Cluster Arbiter ******************************/
    reg [$clog2(N_HARTS+1)-1:0] r_hart_sel;
    wire w_hart_sel_changable = !w_next_mode_is_mc && w_mode_is_cpu && w_core_next_state_is_idle[r_hart_sel] && w_core_interrupt_ok[r_hart_sel] && w_core_tkn[r_hart_sel] && !w_core_take_exception[r_hart_sel] && (w_mmu_pagefault == ~0) && !w_core_csr_flush[r_hart_sel] && !w_core_tlb_flush[r_hart_sel];
    always @ (posedge CLK) begin
        if (!RST_X) begin
            r_hart_sel <= 0;
        end else begin
            r_hart_sel <= (w_hart_sel_changable) ? (r_hart_sel == N_HARTS-1) ? 0 : r_hart_sel + 1 : r_hart_sel;
        end
    end

    assign w_cluster_iaddr = w_core_iaddr[r_hart_sel];
    assign w_cluster_daddr = w_core_daddr[r_hart_sel];
    assign w_cluster_data_wdata = w_core_data_wdata[r_hart_sel];
    assign w_cluster_init_stage = w_core_init_stage[r_hart_sel];
    // assign w_cluster_data_we = w_core_data_we[r_hart_sel]; // TODO: Assign this
    assign w_cluster_is_paddr = w_core_is_paddr[r_hart_sel];
    // assign w_cluster_iscode = w_core_iscode[r_hart_sel];
    // assign w_cluster_isread = w_core_isread[r_hart_sel];
    // assign w_cluster_iswrite = w_core_iswrite[r_hart_sel];
    // assign w_cluster_pte_we = w_core_pte_we[r_hart_sel];
    // assign w_cluster_pte_wdata = w_core_pte_wdata[r_hart_sel];
    // assign w_cluster_use_tlb = w_core_use_tlb[r_hart_sel];
    // assign w_cluster_tlb_hit = w_core_tlb_hit[r_hart_sel];
    // assign w_cluster_pw_state = w_core_pw_state[r_hart_sel];
    // assign w_cluster_tlb_busy = w_core_tlb_busy[r_hart_sel];
    // assign w_cluster_tlb_usage = w_core_tlb_usage[r_hart_sel];
    // assign w_cluster_tlb_pte_addr = w_core_tlb_pte_addr[r_hart_sel];
    // assign w_cluster_tlb_acs = w_core_tlb_acs[r_hart_sel];
    for (g = 0; g < N_HARTS; g = g + 1) begin
        assign w_core_busy[g] = (r_hart_sel == g) ? w_interconnect_busy || w_cluster_tlb_busy : 1;
        assign w_core_pagefault[g] = (r_hart_sel == g) ? w_mmu_pagefault : ~0;
    end

`ifdef SYNTHESIS
generate
    if (DEBUG) begin
        ila_cluster ila_cluster (
            .clk(CLK), // input wire clk
            .probe0(w_core_pc[0]), // input wire [31:0]  probe0  
            .probe1(w_core_pc[1]), // input wire [31:0]  probe1 
            .probe2(w_cluster_iaddr), // input wire [31:0]  probe2 
            .probe3(w_cluster_daddr), // input wire [31:0]  probe3 
            .probe4(r_hart_sel), // input wire [3:0]  probe4 
            .probe5(w_core_satp[0]), // input wire [31:0]  probe5 
            .probe6(w_core_satp[1]), // input wire [31:0]  probe6
            .probe7(w_mc_mode), // input wire [2:0]  probe7 
            .probe8(w_cluster_tlb_usage), // input wire [0:0]  probe8 
            .probe9(w_flush_all_tlbs) // input wire [0:0]  probe9
        );
    end
endgenerate
`endif
endmodule