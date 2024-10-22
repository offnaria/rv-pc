`include "define.vh"

module m_mmu (
    input wire        CLK,
    input wire  [1:0] w_tlb_req,
    input wire [31:0] w_insn_addr,
    input wire [31:0] w_data_addr,
    input wire [31:0] w_priv,
    input wire [31:0] w_satp,
    input wire [31:0] w_mstatus,
    input wire        w_dram_busy,
    input wire [31:0] w_dram_odata,
    input wire        w_tlb_flush,
    input wire        w_mode_is_cpu,
    input wire        w_is_amo_load,

    output wire        w_iscode,
    output wire        w_isread,
    output wire        w_iswrite,
    output wire        w_pte_we,
    output wire [31:0] w_pte_wdata,
    output wire [31:0] w_pagefault,
    output wire        w_use_tlb,
    output wire        w_tlb_hit,
    output wire  [2:0] w_pw_state,
    output wire        w_tlb_busy,
    output wire [31:0] w_tlb_addr,
    output wire  [2:0] w_tlb_usage,
    output wire [31:0] w_tlb_pte_addr,
    output wire        w_tlb_acs,
    output wire        w_pw_done
);
    localparam VPN_WIDTH      = 20;
    localparam PPN_WIDTH      = 22;
    localparam TLB_ADDR_WIDTH = VPN_WIDTH + PPN_WIDTH;
    localparam TLB_PERMISSION_BITS_WIDTH = 8; // D, A, G, U, X, W, R, V
    localparam TLB_PTE_V_BIT = 0;
    localparam TLB_PTE_R_BIT = 1;
    localparam TLB_PTE_W_BIT = 2;
    localparam TLB_PTE_X_BIT = 3;
    localparam TLB_PTE_U_BIT = 4;
    localparam TLB_PTE_G_BIT = 5;
    localparam TLB_PTE_A_BIT = 6;
    localparam TLB_PTE_D_BIT = 7;
    localparam TLB_INST_WIDTH = PPN_WIDTH + TLB_PERMISSION_BITS_WIDTH;
    localparam TLB_DATA_WIDTH = PPN_WIDTH + TLB_PERMISSION_BITS_WIDTH;
    localparam TLB_ENTRY      = `TLB_SIZE;
    localparam MSTATUS_MXR_BIT = 19;
    localparam MSTATUS_SUM_BIT = 18;

    localparam ENABLE_ITLB = 1;
    localparam ENABLE_RTLB = 1;
    localparam ENABLE_WTLB = 1;

    /***** Address translation ********************************************************************/
    reg  [31:0] physical_addr       = 0;
    reg         page_walk_fail      = 0;

    // Page walk state
    reg  [2:0]  r_pw_state   = 0;
    reg         r_tlb_busy   = 0;
    assign w_pw_state = r_pw_state;
    assign w_tlb_busy = r_tlb_busy;

    // Page table entry
    reg  [31:0] L1_pte              = 0;
    reg  [31:0] L0_pte              = 0;

    // Permission
    reg  [TLB_PERMISSION_BITS_WIDTH-1:0] r_permission = 0;
    wire [TLB_PERMISSION_BITS_WIDTH-1:0] w_tlb_inst_permission;
    wire [TLB_PERMISSION_BITS_WIDTH-1:0] w_tlb_data_permission;
    wire [TLB_PERMISSION_BITS_WIDTH-1:0] w_tlb_permission = (w_iscode) ? w_tlb_inst_permission : w_tlb_data_permission;

    /***********************************        Page walk       ***********************************/
    assign w_iscode        = (w_tlb_req == `ACCESS_CODE);
    assign w_isread        = (w_tlb_req == `ACCESS_READ);
    assign w_iswrite       = (w_tlb_req == `ACCESS_WRITE);
    reg         r_iscode        = 0;
    reg         r_isread        = 0;
    reg         r_iswrite       = 0;
    reg         r_is_amo_load   = 0;
    wire [31:0] v_addr          = w_iscode ? w_insn_addr : w_data_addr;

    // Level 1
    wire [31:0] vpn1            = {22'b0, v_addr[31:22]};
    wire [31:0] L1_pte_addr     = {w_satp[21:0], 12'b0} + {vpn1, 2'b0}; // NOTE: Maybe w_satp[21:0] is correct, but RV-PC's storage is too small, so w_satp[19:0] might be enough.
    wire  [2:0] L1_xwr          = w_mstatus[MSTATUS_MXR_BIT] ? (L1_pte[TLB_PTE_X_BIT:TLB_PTE_R_BIT] | {2'd0, L1_pte[TLB_PTE_X_BIT]}) : L1_pte[TLB_PTE_X_BIT:TLB_PTE_R_BIT];
    wire [31:0] L1_paddr        = {L1_pte[29:10], 12'h0};
    wire [31:0] L1_p_addr       = {L1_paddr[31:22], v_addr[21:0]};
    wire        L1_write        = !L1_pte[TLB_PTE_A_BIT] || (!L1_pte[TLB_PTE_D_BIT] && (w_iswrite || w_is_amo_load));
    wire        L1_success      = !(L1_xwr ==2 || L1_xwr == 6 || !L1_pte[0] ||
                                   (L1_xwr != 0 && ((w_priv == `PRIV_S && (L1_pte[TLB_PTE_U_BIT] && !w_mstatus[MSTATUS_SUM_BIT])) ||
                                                    (w_priv == `PRIV_U && !L1_pte[TLB_PTE_U_BIT]) ||
                                                    (L1_xwr[w_tlb_req] == 0))));

    // Level 0
    wire [31:0] vpn0            = {22'b0, v_addr[21:12]};
    wire [31:0] L0_pte_addr     = {L1_pte[29:10], 12'b0} + {vpn0, 2'b0};
    wire  [2:0] L0_xwr          = w_mstatus[MSTATUS_MXR_BIT] ? (L0_pte[TLB_PTE_X_BIT:TLB_PTE_R_BIT] | {2'd0, L0_pte[TLB_PTE_X_BIT]}) : L0_pte[TLB_PTE_X_BIT:TLB_PTE_R_BIT];
    wire [31:0] L0_paddr        = {L0_pte[29:10], 12'h0};
    wire [31:0] L0_p_addr       = {L0_paddr[31:12], v_addr[11:0]};
    wire        L0_write        = !L0_pte[TLB_PTE_A_BIT] || (!L0_pte[TLB_PTE_D_BIT] && (w_iswrite || w_is_amo_load));
    wire        L0_success      = !(L0_xwr ==2 || L0_xwr == 6 || !L0_pte[0] || !L1_success ||
                                    (w_priv == `PRIV_S && (L0_pte[TLB_PTE_U_BIT] && !w_mstatus[MSTATUS_SUM_BIT])) ||
                                    (w_priv == `PRIV_U && !L0_pte[TLB_PTE_U_BIT]) ||
                                    (L0_xwr[w_tlb_req] == 0));

    // update pte
    wire [31:0] L1_pte_write    = L1_pte | `PTE_A_MASK | ((w_iswrite || w_is_amo_load) ? `PTE_D_MASK : 0);
    wire [31:0] L0_pte_write    = L0_pte | `PTE_A_MASK | ((w_iswrite || w_is_amo_load) ? `PTE_D_MASK : 0);
    assign w_pte_we             = (r_pw_state==5) && (((L1_xwr != 0 && L1_success) && L1_write) ||
                                        ((L0_xwr != 0 && L0_success) && L0_write));
    wire [31:0] w_pte_waddr     = (L1_xwr != 0 && L1_success) ? L1_pte_addr : L0_pte_addr;
    assign w_pte_wdata          = (L1_xwr != 0 && L1_success) ? L1_pte_write : L0_pte_write;

    assign w_pagefault          = !page_walk_fail ? ~32'h0 : (r_iscode) ? `CAUSE_FETCH_PAGE_FAULT :
                                    (r_iswrite || r_is_amo_load) ? `CAUSE_STORE_PAGE_FAULT : `CAUSE_LOAD_PAGE_FAULT;

    reg  [31:0] r_tlb_addr = 0;
    reg   [2:0] r_tlb_usage  = 0;
    assign w_tlb_addr = r_tlb_addr;
    assign w_tlb_usage  = r_tlb_usage;
    wire [21:0] w_tlb_inst_addr, w_tlb_data_addr;
    wire        w_tlb_inst_hit, w_tlb_data_hit;
    assign w_use_tlb = (w_mode_is_cpu && (w_iscode || w_isread || w_iswrite)
                                          && (!(w_priv == `PRIV_M || w_satp[31] == 0)));
    assign w_tlb_hit = ((w_iscode && w_tlb_inst_hit) || ((w_isread || w_iswrite) && w_tlb_data_hit)) && !w_tlb_dirty_miss;
    assign w_pw_done = (r_pw_state == 7);

    wire [2:0] w_tlb_permission_xwr = w_mstatus[MSTATUS_MXR_BIT] ? (w_tlb_permission[TLB_PTE_X_BIT:TLB_PTE_R_BIT] | {2'd0, w_tlb_permission[TLB_PTE_X_BIT]}) : w_tlb_permission[TLB_PTE_X_BIT:TLB_PTE_R_BIT];
    wire w_tlb_permission_miss = ((w_priv == `PRIV_S) && (w_tlb_permission[TLB_PTE_U_BIT] && !w_mstatus[MSTATUS_SUM_BIT])) || // S-mode without SUM=0 is not allowed to access U-mode page.
                    ((w_priv == `PRIV_U) && !w_tlb_permission[TLB_PTE_U_BIT]) || // U-mode is not allowed to access S-mode page.
                    (w_tlb_permission_xwr[w_tlb_req] == 0); // Permission check.
    wire w_tlb_dirty_miss = (w_iswrite || w_is_amo_load) && !w_tlb_permission[TLB_PTE_D_BIT]; // Dirty bit is not set.
    // PAGE WALK state
    always@(posedge CLK) begin
        if(r_pw_state == 0) begin
            // PAGE WALK START
            if(!w_dram_busy && w_use_tlb) begin
                // tlb miss
                if(!w_tlb_hit) begin
                    r_pw_state <= 1;
                    r_tlb_busy <= 1;
                end
                else begin
                    if (w_tlb_permission_miss) begin
                        r_pw_state <= 6;
                        page_walk_fail <= 1;
                    end else begin
                        r_pw_state <= 7;
                        r_tlb_busy <= 1;
                        r_tlb_addr <= {(w_iscode) ? w_tlb_inst_addr : (w_isread || w_iswrite) ? w_tlb_data_addr : 22'd0, v_addr[11:0]};
                        r_tlb_usage <= {w_iscode, w_isread, w_iswrite};
                    end
                end
                {r_iscode, r_isread, r_iswrite, r_is_amo_load} <= {w_iscode, w_isread, w_iswrite, w_is_amo_load};
            end
        end
        // Level 1
        else if(r_pw_state == 1 && !w_dram_busy) begin
            L1_pte      <= w_dram_odata;
            r_pw_state  <= 2;
        end
        else if(r_pw_state == 2) begin
            r_pw_state  <= 3;
        end
        // Level 0
        else if(r_pw_state == 3 && !w_dram_busy) begin
            L0_pte      <= w_dram_odata;
            r_pw_state  <= 4;
        end
        // Success?
        else if(r_pw_state == 4) begin
            if(!L1_pte[0]) begin
                physical_addr   <= 0;
                page_walk_fail  <= 1;
                r_tlb_busy      <= 0;
            end
            else if(L1_xwr) begin
                physical_addr   <= (L1_success) ? L1_p_addr : 0;
                page_walk_fail  <= (L1_success) ? 0 : 1;
                r_tlb_busy      <= L1_success;
                r_permission    <= (L1_success) ? L1_pte_write[TLB_PERMISSION_BITS_WIDTH-1:0] : 0;
            end
            else if(!L0_pte[0]) begin
                physical_addr   <= 0;
                page_walk_fail  <= 1;
                r_tlb_busy      <= 0;
            end
            else if(L0_xwr) begin
                physical_addr   <= (L0_success) ? L0_p_addr : 0;
                page_walk_fail  <= (L0_success) ? 0 : 1;
                r_tlb_busy      <= L0_success;
                r_permission    <= (L0_success) ? L0_pte_write[TLB_PERMISSION_BITS_WIDTH-1:0] : 0;
            end
            r_pw_state  <= 5;
        end
        // Update pte
        else if(r_pw_state == 5) begin
            r_pw_state      <= 0;
            physical_addr   <= 0;
            page_walk_fail  <= 0;
            r_permission    <= 0;
        end
        else if(r_pw_state == 6) begin
            r_pw_state <= 0;
            r_tlb_usage <= 0;
            r_tlb_busy <= 0;
            page_walk_fail <= 0;
        end
        else if(r_pw_state == 7) begin
            r_pw_state <= 0;
            r_tlb_usage <= 0;
            r_tlb_busy <= 0;
            //$write("hoge!, %x, %x\n", page_walk_fail, r_tlb_usage);
        end
    end

    /***********************************           TLB          ***********************************/
    wire        w_tlb_inst_we   = (r_pw_state == 5 && !page_walk_fail && w_iscode);
    wire        w_tlb_data_we   = (r_pw_state == 5 && !page_walk_fail && (w_isread || w_iswrite));
    wire [TLB_INST_WIDTH-1:0] w_tlb_inst_wdata = {r_permission, 2'b0, physical_addr[31:12]};
    wire [TLB_DATA_WIDTH-1:0] w_tlb_data_wdata = {r_permission, 2'b0, physical_addr[31:12]};

    wire [PPN_WIDTH:0] w_ppn = w_satp[21:0];
    wire [TLB_ADDR_WIDTH-1:0] w_tlb_inst_rwaddr = {w_ppn, w_insn_addr[31:12]};
    wire [TLB_ADDR_WIDTH-1:0] w_tlb_data_rwaddr = {w_ppn, w_data_addr[31:12]};

    generate
        if (ENABLE_ITLB) begin
            m_cache_dmap#(TLB_ADDR_WIDTH, TLB_INST_WIDTH, TLB_ENTRY)
            tlb_inst (CLK, 1'b1, w_tlb_flush, w_tlb_inst_we, w_tlb_inst_rwaddr, w_tlb_inst_rwaddr, w_tlb_inst_wdata, {w_tlb_inst_permission, w_tlb_inst_addr}, w_tlb_inst_hit);
        end else begin
            assign w_tlb_inst_addr = 0;
            assign w_tlb_inst_hit = 0;
        end
    endgenerate

    generate
        if (ENABLE_RTLB) begin
            m_cache_dmap#(TLB_ADDR_WIDTH, TLB_DATA_WIDTH, TLB_ENTRY)
            tlb_data (CLK, 1'b1, w_tlb_flush, w_tlb_data_we, w_tlb_data_rwaddr, w_tlb_data_rwaddr, w_tlb_data_wdata, {w_tlb_data_permission, w_tlb_data_addr}, w_tlb_data_hit);
        end else begin
            assign w_tlb_data_addr = 0;
            assign w_tlb_data_hit = 0;
        end
    endgenerate

    reg  [31:0] r_tlb_pte_addr = 0;
    reg         r_tlb_acs = 0;
    assign w_tlb_pte_addr = r_tlb_pte_addr;
    assign w_tlb_acs      = r_tlb_acs;
    always@(*)begin
        case (r_pw_state)
            0:      begin r_tlb_pte_addr <= L1_pte_addr;    r_tlb_acs = 1; end
            2:      begin r_tlb_pte_addr <= L0_pte_addr;    r_tlb_acs = 1; end
            5:      begin r_tlb_pte_addr <= w_pte_waddr;    r_tlb_acs = 1; end
            default:begin r_tlb_pte_addr <= 0;              r_tlb_acs = 0; end
        endcase
    end
endmodule
