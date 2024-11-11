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
    input  wire               w_next_mode_is_mc,

    output wire [31:0]        w_cluster_data_wdata,
    output wire               w_cluster_init_stage,
    output wire               w_cluster_data_we,
    output wire [31:0]        w_cluster_dev_addr,
    output wire [31:0]        w_cluster_dram_addr,
    output wire [2:0]         w_cluster_mem_ctrl,
    output wire               w_cluster_dram_re
);

    localparam DEBUG = 0;

    wire w_mode_is_cpu = (w_mc_mode == `MC_MODE_CPU);

    wire [31:0] w_core_data_wdata   [0:N_HARTS-1];
    wire        w_core_init_stage   [0:N_HARTS-1];
    wire        w_core_data_we      [0:N_HARTS-1];
    wire [31:0] w_core_dev_addr     [0:N_HARTS-1];
    wire [31:0] w_core_dram_addr    [0:N_HARTS-1];
    wire [2:0]  w_core_mem_ctrl     [0:N_HARTS-1];
    wire        w_core_dram_re      [0:N_HARTS-1];

    assign w_cluster_data_wdata = w_core_data_wdata[r_hart_sel];
    assign w_cluster_init_stage = w_core_init_stage[r_hart_sel];
    assign w_cluster_data_we    = w_core_data_we[r_hart_sel];
    assign w_cluster_dev_addr   = w_core_dev_addr[r_hart_sel];
    assign w_cluster_dram_addr  = w_core_dram_addr[r_hart_sel];
    assign w_cluster_mem_ctrl   = w_core_mem_ctrl[r_hart_sel];
    assign w_cluster_dram_re    = w_core_dram_re[r_hart_sel];

    wire [N_HARTS-1:0] w_core_busy;
    wire [N_HARTS-1:0] w_core_next_state_is_idle;
    wire [N_HARTS-1:0] w_core_interrupt_ok;
    wire [N_HARTS-1:0] w_core_tkn;
    wire [N_HARTS-1:0] w_core_take_exception;
    wire [N_HARTS-1:0] w_core_tlb_flush;
    wire [N_HARTS-1:0] w_core_csr_flush;
    wire [N_HARTS-1:0] w_core_page_walk_fail;

    genvar g;
    generate
        for (g = 0; g < N_HARTS; g = g + 1) begin: cores_and_mmus
            assign w_core_next_state_is_idle[g] = (core_wrapper.core_inst.next_state == 0);
            assign w_core_interrupt_ok[g] = core_wrapper.core_inst.w_interrupt_ok;
            assign w_core_tkn[g] = core_wrapper.core_inst.tkn;
            assign w_core_take_exception[g] = core_wrapper.core_inst.w_take_exception;
            assign w_core_csr_flush[g] = core_wrapper.core_inst.w_csr_flush;
            assign w_core_tlb_flush[g] = core_wrapper.core_inst.w_tlb_flush;
            assign w_core_page_walk_fail[g] = core_wrapper.mmu_inst.page_walk_fail;

            m_RVCorePL_wrapper #(
                .CACHED(1),
                .MHARTID(g)
            ) core_wrapper (
                .CLK(CLK),
                .RST_X(RST_X),
                .w_insn_data(w_insn_data),
                .w_data_data(w_data_data),
                .w_is_dram_data(w_is_dram_data),
                .w_interconnect_busy(w_core_busy[g]),
                .w_mc_mode(w_mc_mode),
                .w_mtip(w_mtip[g]),
                .w_msip(w_msip[g]),
                .w_meip(w_meip[g]),
                .w_seip(w_seip[g]),
                .w_mtime(w_mtime),
                .w_cache_invalidate(), // TODO
                .w_cache_invalidate_address(), // TODO
                .w_data_wdata(w_core_data_wdata[g]),
                .w_init_stage(w_core_init_stage[g]),
                .w_data_we(w_core_data_we[g]),
                .w_dev_addr(w_core_dev_addr[g]),
                .w_dram_addr(w_core_dram_addr[g]),
                .w_data_ctrl(w_core_mem_ctrl[g]),
                .w_dram_re(w_core_dram_re[g])
            );
        end
    endgenerate

    /****************************** Cluster Arbiter ******************************/
    reg [$clog2(N_HARTS+1)-1:0] r_hart_sel;
    wire w_hart_sel_changable = !w_next_mode_is_mc && w_mode_is_cpu && w_core_next_state_is_idle[r_hart_sel] && w_core_interrupt_ok[r_hart_sel] && w_core_tkn[r_hart_sel] && !w_core_take_exception[r_hart_sel] && !w_core_page_walk_fail[r_hart_sel] && !w_core_csr_flush[r_hart_sel] && !w_core_tlb_flush[r_hart_sel];
    always @ (posedge CLK) begin
        if (!RST_X) begin
            r_hart_sel <= 0;
        end else begin
            r_hart_sel <= (w_hart_sel_changable) ? (r_hart_sel == N_HARTS-1) ? 0 : r_hart_sel + 1 : r_hart_sel;
        end
    end

    for (g = 0; g < N_HARTS; g = g + 1) begin
        assign w_core_busy[g] = (r_hart_sel == g) ? w_interconnect_busy : 1;
    end

endmodule