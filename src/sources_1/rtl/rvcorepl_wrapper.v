module m_RVCorePL_wrapper #(
    parameter CACHED = 0,
    parameter MHARTID = 0
) (
    input  wire         CLK,
    input  wire         RST_X,
    input  wire [127:0] w_insn_data,
    input  wire [127:0] w_data_data,
    input  wire         w_is_dram_data,
    input  wire         w_interconnect_busy,
    input  wire [2:0]   w_mc_mode,
    input  wire         w_mtip,
    input  wire         w_msip,
    input  wire         w_meip,
    input  wire         w_seip,
    input  wire [63:0]  w_mtime,
    input  wire         w_cache_invalidate,
    input  wire [31:0]  w_cache_invalidate_address,

    output wire [31:0]  w_data_wdata,
    output wire         w_init_stage,
    output wire         w_data_we,
    output wire [31:0]  w_dev_addr,
    output wire [31:0]  w_dram_addr,
    output wire [2:0]   w_data_ctrl,
    output wire         w_dram_re
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
    wire         w_instance_is_amo_load;

    generate
        if (CACHED) begin
            
        end else begin
            assign w_instance_insn_data = w_insn_data;
            assign w_instance_data_data = w_data_data;
            assign w_instance_is_dram_data = w_is_dram_data;
            assign w_instance_busy = w_interconnect_busy || w_mmu_tlb_busy;
            assign w_instance_pagefault = w_mmu_pagefault;
            assign w_instance_mc_mode = w_mc_mode;
            assign w_instance_mtip = w_mtip;
            assign w_instance_msip = w_msip;
            assign w_instance_meip = w_meip;
            assign w_instance_seip = w_seip;
            assign w_instance_mtime = w_mtime;
            assign w_instance_cache_invalidate = w_cache_invalidate;
            assign w_instance_cache_invalidate_address = w_cache_invalidate_address;

            assign w_data_wdata = (w_mmu_pw_running) ? w_mmu_pte_wdata : w_instance_data_wdata;
            assign w_init_stage = w_instance_init_stage;
            assign w_data_we = (w_mmu_pw_running) ? w_mmu_pte_we : w_mmu_iswrite;
            assign w_dev_addr = w_instance_daddr;
            assign w_dram_addr = (w_mmu_iscode && !w_mmu_pw_running) ? w_instance_iaddr : (w_instance_is_paddr || !w_mmu_tlb_acs || w_mmu_tlb_hit) ? w_dev_addr : w_mmu_tlb_pte_addr;
            assign w_data_ctrl = (w_mmu_iscode && !w_mmu_pw_running) ? `FUNCT3_LW____       : // TLB hit with instruction fetch
                                 (w_instance_is_paddr)               ? w_instance_data_ctrl : // Access with physical address (No address translation)
                                 (w_mmu_tlb_usage[1:0] != 0)         ? w_instance_data_ctrl : // TLB hit with load or store (1 cycle delayed)
                                 (w_mmu_pw_state == 0)               ? `FUNCT3_LW____       : // TLB miss, load L2 PTE
                                 (w_mmu_pw_state == 2)               ? `FUNCT3_LW____       : // TLB miss, load L1 PTE
                                 (w_mmu_pw_state == 5)               ? `FUNCT3_LW____       : // Update leaf PTE
                                 w_instance_data_ctrl;                                        // Otherwise
            assign w_dram_re = (w_instance_is_paddr)                 ? (w_mmu_iscode || w_mmu_isread)                  : // Access with physical address (No address translation)
                               (w_mmu_tlb_usage[2:1] != 0)           ? w_mmu_pw_done                                   : // TLB hit with instruction fetch or load (1 cycle delayed)
                               (w_mmu_pw_running && !w_mmu_tlb_hit && ((w_mmu_pw_state == 0) || (w_mmu_pw_state == 2))); // TLB miss, load L2 PTE or L1 PTE
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
        .w_is_amo_load(w_instance_is_amo_load)
    );
    
    /***********************************        Local MMU       ***********************************/
    reg [3:0] r_mmu_tlb_pte_addr_offset = 0;
    always @(posedge CLK) begin
        if (w_mmu_pw_running && !w_mmu_tlb_hit && ((w_mmu_pw_state == 0) || (w_mmu_pw_state == 2))) begin
            r_mmu_tlb_pte_addr_offset <= w_mmu_tlb_pte_addr[3:0];
        end
    end

    wire  [1:0] w_mmu_tlb_req = w_instance_tlb_req;
    wire [31:0] w_mmu_insn_addr = w_instance_insn_addr;
    wire [31:0] w_mmu_data_addr = w_instance_data_addr;
    wire [31:0] w_mmu_priv = w_instance_priv;
    wire [31:0] w_mmu_satp = w_instance_satp;
    wire [31:0] w_mmu_mstatus = w_instance_mstatus;
    wire        w_mmu_dram_busy = w_interconnect_busy;
    wire [31:0] w_mmu_dram_odata = (w_insn_data >> {r_mmu_tlb_pte_addr_offset, 3'd0});
    wire        w_mmu_tlb_flush = w_instance_tlb_flush;
    wire        w_mmu_mode_is_cpu = (w_mc_mode == `MC_MODE_CPU);
    wire        w_mmu_tlb_request = w_mmu_mode_is_cpu && !w_instance_is_paddr;
    wire        w_mmu_is_amo_load = w_instance_is_amo_load;

    wire        w_mmu_iscode;
    wire        w_mmu_isread;
    wire        w_mmu_iswrite;
    wire        w_mmu_pte_we;
    wire [31:0] w_mmu_pte_wdata;
    wire [31:0] w_mmu_pagefault;
    wire        w_mmu_use_tlb;
    wire        w_mmu_tlb_hit;
    wire  [2:0] w_mmu_pw_state;
    wire        w_mmu_tlb_busy;
    wire [31:0] w_mmu_tlb_addr;
    wire  [2:0] w_mmu_tlb_usage;
    wire [31:0] w_mmu_tlb_pte_addr;
    wire        w_mmu_tlb_acs;
    wire        w_mmu_pw_done;

    m_mmu mmu_inst (
        // Inputs
        .CLK(CLK),
        .w_tlb_req(w_mmu_tlb_req),
        .w_insn_addr(w_mmu_insn_addr),
        .w_data_addr(w_mmu_data_addr),
        .w_priv(w_mmu_priv),
        .w_satp(w_mmu_satp),
        .w_mstatus(w_mmu_mstatus),
        .w_dram_busy(w_mmu_dram_busy),
        .w_dram_odata(w_mmu_dram_odata),
        .w_tlb_flush(w_mmu_tlb_flush),
        .w_tlb_request(w_mmu_tlb_request),
        .w_is_amo_load(w_mmu_is_amo_load),
        // Outputs
        .w_iscode(w_mmu_iscode),
        .w_isread(w_mmu_isread),
        .w_iswrite(w_mmu_iswrite),
        .w_pte_we(w_mmu_pte_we),
        .w_pte_wdata(w_mmu_pte_wdata),
        .w_pagefault(w_mmu_pagefault),
        .w_use_tlb(w_mmu_use_tlb),
        .w_tlb_hit(w_mmu_tlb_hit),
        .w_pw_state(w_mmu_pw_state),
        .w_tlb_busy(w_mmu_tlb_busy),
        .w_tlb_addr(w_mmu_tlb_addr),
        .w_tlb_usage(w_mmu_tlb_usage),
        .w_tlb_pte_addr(w_mmu_tlb_pte_addr),
        .w_tlb_acs(w_mmu_tlb_acs),
        .w_pw_done(w_mmu_pw_done),
        .w_page_walk_fail(),
        .w_tlb_inst_ok(),
        .w_tlb_data_ok()
    );

    wire w_mmu_pw_running = w_mmu_use_tlb && !w_mmu_pw_done;
    wire w_instance_is_paddr = (w_instance_priv == `PRIV_M) || (!w_instance_satp[31]);
    wire [31:0] w_instance_iaddr = (w_instance_is_paddr) ? w_instance_insn_addr : w_mmu_tlb_addr;
    wire [31:0] w_instance_daddr = (w_instance_is_paddr) ? w_instance_data_addr : w_mmu_tlb_addr;
endmodule
