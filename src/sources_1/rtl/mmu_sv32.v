
module m_mmu_sv32 #(
    parameter [31:0] TLB_ENTRY = `TLB_SIZE
) (
    input  wire        CLK,
    input  wire        RST_X,
    input  wire        w_inst_req,            // Request from instruction cache
    input  wire [31:0] w_inst_vaddr,          // Virtual address from instruction cache
    input  wire        w_data_req,            // Request from data cache
    input  wire [31:0] w_data_vaddr,          // Virtual address from data cache
    input  wire        w_data_load,           // Request is LOAD instruction, otherwise STORE or AMO
    input  wire        w_interconnect_resp,   // Response from interconnect
    input  wire [31:0] w_interconnect_rdata,  // Read data from interconnect
    input  wire [31:0] w_satp,                // Supervisor Address Translation and Protection CSR
    input  wire [31:0] w_mstatus,             // Machine Status CSR
    input  wire        w_flush_tlb,           // Flush TLB request

    output wire        w_inst_resp,           // Response to instruction cache
    output wire [31:0] w_inst_paddr,          // Physical address to instruction cache
    output wire        w_data_resp,           // Response to data cache
    output wire [31:0] w_data_paddr,          // Physical address to data cache
    output wire        w_interconnect_req,    // Request to interconnect
    output wire [31:0] w_interconnect_addr,   // Address to interconnect
    output wire        w_interconnect_we,     // Write enable to interconnect, otherwise read
    output wire [31:0] w_interconnect_wdata,  // Write data to interconnect
    output wire [31:0] w_pagefault            // Page fault
);
    localparam ID_FETCH_PAGE_FAULT     = `CAUSE_FETCH_PAGE_FAULT;
    localparam ID_LOAD_PAGE_FAULT      = `CAUSE_LOAD_PAGE_FAULT;
    localparam ID_STORE_AMO_PAGE_FAULT = `CAUSE_STORE_PAGE_FAULT; // NOTE: "AMOs never raise load page-fault exceptions. Since any unreadable page is also unwritable, attempting to perform an AMO on an unreadable page always raises a store page-fault exception."
    localparam ID_NO_PAGE_FAULT        = ~32'h0;

    localparam W_VPN = 20;
    localparam W_PPN = 20;

    localparam SATP_MODE_BIT = 31;
    localparam W_SATP_ASID   = 9;
    localparam W_SATP_PPN    = 22;

    localparam ID_MODE_SV32 = 1'b1;
    localparam ID_MODE_BARE = 1'b0;

    localparam ID_STATE_IDLE = 2'b00;
    localparam 

    wire                   w_satp_mode = w_satp[SATP_MODE_BIT];
    wire [W_SATP_ASID-1:0] w_satp_asid = w_satp[W_SATP_PPN +: W_SATP_ASID];
    wire [W_SATP_PPN-1:0]  w_satp_ppn  = w_satp[0 +: W_SATP_PPN];



endmodule
