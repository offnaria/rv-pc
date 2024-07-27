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
    output wire  [2:0] w_tlb_use,
    output wire [31:0] w_tlb_pte_addr,
    output wire        w_tlb_acs
);

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

    /***********************************        Page walk       ***********************************/
    assign w_iscode        = (w_tlb_req == `ACCESS_CODE);
    assign w_isread        = (w_tlb_req == `ACCESS_READ);
    assign w_iswrite       = (w_tlb_req == `ACCESS_WRITE);
    reg         r_iscode        = 0;
    reg         r_isread        = 0;
    reg         r_iswrite       = 0;
    wire [31:0] v_addr          = w_iscode ? w_insn_addr : w_data_addr;

    // Level 1
    wire [31:0] vpn1            = {22'b0, v_addr[31:22]};
    wire [31:0] L1_pte_addr     = {w_satp[19:0], 12'b0} + {vpn1, 2'b0};
    wire  [2:0] L1_xwr          = w_mstatus[19] ? (L1_pte[3:1] | L1_pte[5:3]) : L1_pte[3:1];
    wire [31:0] L1_paddr        = {L1_pte[29:10], 12'h0};
    wire [31:0] L1_p_addr       = {L1_paddr[31:22], v_addr[21:0]};
    wire        L1_write        = !L1_pte[6] || (!L1_pte[7] && w_iswrite);
    wire        L1_success      = !(L1_xwr ==2 || L1_xwr == 6 || !L1_pte[0] ||
                                   (L1_xwr != 0 && ((w_priv == `PRIV_S && (L1_pte[4] && !w_mstatus[18])) ||
                                                    (w_priv == `PRIV_U && !L1_pte[4]) ||
                                                    (L1_xwr[w_tlb_req] == 0))));

    // Level 0
    wire [31:0] vpn0            = {22'b0, v_addr[21:12]};
    wire [31:0] L0_pte_addr     = {L1_pte[29:10], 12'b0} + {vpn0, 2'b0};
    wire  [2:0] L0_xwr          = w_mstatus[19] ? (L0_pte[3:1] | L0_pte[5:3]) : L0_pte[3:1];
    wire [31:0] L0_paddr        = {L0_pte[29:10], 12'h0};
    wire [31:0] L0_p_addr       = {L0_paddr[31:12], v_addr[11:0]};
    wire        L0_write        = !L0_pte[6] || (!L0_pte[7] && w_iswrite);
    wire        L0_success      = !(L0_xwr ==2 || L0_xwr == 6 || !L0_pte[0] || !L1_success ||
                                    (w_priv == `PRIV_S && (L0_pte[4] && !w_mstatus[18])) ||
                                    (w_priv == `PRIV_U && !L0_pte[4]) ||
                                    (L0_xwr[w_tlb_req] == 0));

    // update pte
    wire [31:0] L1_pte_write    = L1_pte | `PTE_A_MASK | (w_iswrite ? `PTE_D_MASK : 0);
    wire [31:0] L0_pte_write    = L0_pte | `PTE_A_MASK | (w_iswrite ? `PTE_D_MASK : 0);
    assign w_pte_we             = (r_pw_state==5) && (((L1_xwr != 0 && L1_success) && L1_write) ||
                                        ((L0_xwr != 0 && L0_success) && L0_write));
    wire [31:0] w_pte_waddr     = (L1_xwr != 0 && L1_success) ? L1_pte_addr : L0_pte_addr;
    assign w_pte_wdata          = (L1_xwr != 0 && L1_success) ? L1_pte_write : L0_pte_write;

    assign w_pagefault          = !page_walk_fail ? ~32'h0 : (r_iscode) ? `CAUSE_FETCH_PAGE_FAULT :
                                    (r_isread) ? `CAUSE_LOAD_PAGE_FAULT : `CAUSE_STORE_PAGE_FAULT;

    reg  [31:0] r_tlb_addr = 0;
    reg   [2:0] r_tlb_use  = 0;
    assign w_tlb_addr = r_tlb_addr;
    assign w_tlb_use  = r_tlb_use;
    wire [21:0] w_tlb_inst_r_addr, w_tlb_data_r_addr, w_tlb_data_w_addr;
    wire        w_tlb_inst_r_oe, w_tlb_data_r_oe, w_tlb_data_w_oe;
    assign w_use_tlb = (w_mode_is_cpu && (w_iscode || w_isread || w_iswrite)
                                          && (!(w_priv == `PRIV_M || w_satp[31] == 0)));
    assign w_tlb_hit = ((w_iscode && w_tlb_inst_r_oe) ||
                            (w_isread && w_tlb_data_r_oe)  ||
                            (w_iswrite && w_tlb_data_w_oe));

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
                    r_pw_state <= 7;
                    r_tlb_busy <= 1;
                    case ({w_iscode, w_isread, w_iswrite})
                        3'b100 : r_tlb_addr <= {w_tlb_inst_r_addr[21:2], w_insn_addr[11:0]};
                        3'b010 : r_tlb_addr <= {w_tlb_data_r_addr[21:2], w_data_addr[11:0]};
                        3'b001 : r_tlb_addr <= {w_tlb_data_w_addr[21:2], w_data_addr[11:0]};
                        default: r_tlb_addr <= 0;
                    endcase
                    r_tlb_use <= {w_iscode, w_isread, w_iswrite};
                end
                {r_iscode, r_isread, r_iswrite} <= {w_iscode, w_isread, w_iswrite};
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
            end
            r_pw_state  <= 5;
        end
        // Update pte
        else if(r_pw_state == 5) begin
            r_pw_state      <= 0;
            physical_addr   <= 0;
            page_walk_fail  <= 0;
        end
        else if(r_pw_state == 7) begin
            r_pw_state <= 0;
            r_tlb_use <= 0;
            r_tlb_busy <= 0;
            //$write("hoge!, %x, %x\n", page_walk_fail, r_tlb_use);
        end
    end

    /***********************************           TLB          ***********************************/
    wire        w_tlb_inst_r_we   = (r_pw_state == 5 && !page_walk_fail && w_iscode);
    wire        w_tlb_data_r_we   = (r_pw_state == 5 && !page_walk_fail && w_isread);
    wire        w_tlb_data_w_we   = (r_pw_state == 5 && !page_walk_fail && w_iswrite);
    wire [21:0] w_tlb_wdata       = {physical_addr[31:12], 2'b0};

    m_cache_dmap#(20, 22, `TLB_SIZE) TLB_inst_r (CLK, 1'b1, w_tlb_flush, w_tlb_inst_r_we,
                                            w_insn_addr[31:12], w_insn_addr[31:12], w_tlb_wdata,
                                            w_tlb_inst_r_addr, w_tlb_inst_r_oe);

    m_cache_dmap#(20, 22, `TLB_SIZE) TLB_data_r (CLK, 1'b1, w_tlb_flush, w_tlb_data_r_we,
                                            w_data_addr[31:12], w_data_addr[31:12], w_tlb_wdata,
                                            w_tlb_data_r_addr, w_tlb_data_r_oe);

    m_cache_dmap#(20, 22, `TLB_SIZE) TLB_data_w (CLK, 1'b1, w_tlb_flush, w_tlb_data_w_we,
                                            w_data_addr[31:12], w_data_addr[31:12], w_tlb_wdata,
                                            w_tlb_data_w_addr, w_tlb_data_w_oe);

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
