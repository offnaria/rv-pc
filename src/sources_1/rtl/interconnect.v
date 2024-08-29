/**************************************************************************************************/
/**** RVSoC (Mini Kuroda/RISC-V)                       since 2018-08-07   ArchLab. TokyoTech   ****/
/**** Memory Controller v0.01                                                                  ****/
/**************************************************************************************************/
`default_nettype none
/**************************************************************************************************/
`include "define.vh"

/**************************************************************************************************/
module m_interconnect #(
    parameter N_HARTS = 1
)
(
    input  wire         CLK, clk_50mhz, RST_X,
    input  wire [31:0]  w_cluster_iaddr, w_cluster_daddr,
    input  wire [31:0]  w_data_wdata,
    input  wire         w_data_we,
    input  wire  [2:0]  w_data_ctrl,
    output wire [127:0]  w_insn_data,
    output wire [127:0]  w_data_data,
    output wire         w_is_dram_data,
    output reg          r_finish,
    input  wire [63:0]  w_mtime,
    input  wire         w_is_paddr,
    // MMU
    input  wire         w_iscode,
    input  wire         w_isread,
    input  wire         w_iswrite,
    input  wire         w_pte_we,
    input  wire [31:0]  w_pte_wdata,
    input  wire         w_use_tlb,
    input  wire         w_tlb_hit,
    input  wire [2:0]   w_pw_state,
    input  wire         w_r_tlb_busy,
    input  wire  [2:0]  w_tlb_use,
    input  wire [31:0]  w_tlb_pte_addr,
    input  wire         w_tlb_acs,
    // MMU end
    output wire         w_proc_busy,
    output wire         w_txd,
    input  wire         w_rxd,
    output wire         w_init_done,
    output wire  [7:0]  w_uart_data,
    output wire         w_uart_we,
    input  wire         w_init_stage,
    output wire [31:0]  w_checksum,
    input  wire         w_debug_btnd,
    input  wire         w_crs_dv_phy,
    output wire  [1:0]  w_txd_phy,
    output wire         w_txen_phy,
    output wire         w_clkin_phy,
    input  wire  [1:0]  w_rxd_phy,
    input  wire         w_rxerr_phy,
    output wire         w_init_start,
    inout  wire         usb_ps2_clk,
    inout  wire         usb_ps2_data,
`ifdef CH559_USB
    input  wire        ch559_rx,
`else
    inout  wire        pmod_ps2_clk,
    inout  wire        pmod_ps2_data,
`endif
    output wire [2:0]   w_mc_mode,
    output wire         w_tlb_busy,
    // DRAM
    input  wire         w_dram_busy,
    output wire         w_dram_rd_en,
    output wire         w_dram_wr_en,
    output wire [31:0]  w_dram_addr_t2,
    output wire [31:0]  w_dram_wdata_t,
    input  wire [127:0] w_dram_rdata128,
    output wire [2:0]   w_dram_ctrl_t,
    // Keyboard
    output wire         w_ps2_kbd_we,
    output wire [ 7:0]  w_ps2_kbd_data,
    // Mouse
    output wire         w_ps2_mouse_we,
    output wire [ 7:0]  w_ps2_mouse_data,
    // SD card controller
    input  wire [31:0]  loader_addr,
    input  wire [31:0]  loader_data,
    input  wire         loader_we,
    input  wire         loader_done,
    input  wire [31:0]  sdctrl_rdata,
    input  wire         sdctrl_busy,
    // PLIC
    output wire         w_plic_we,
    output wire [31:0]  w_plic_wdata,
    output wire         w_plic_re,
    input  wire [31:0]  w_plic_rdata,
    // CLINT
    output wire         w_clint_we,
    output wire [31:0]  w_clint_wdata,
    input  wire [31:0]  w_clint_rdata,
    // Framebuffer
    output wire         w_fb_we,
    output wire [31:0]  w_fb_wdata,
    input  wire [31:0]  w_fb_rdata,
    //
    output wire [27:0]  w_offset
);

    initial r_finish = 0;

    /***** Other Registers ************************************************************************/
    // Device checker
    reg   [3:0] r_dev               = 0;
    reg   [3:0] r_virt              = 0;

    // TO HOST
    reg  [31:0] r_tohost            = 0;

    /***** Micro Controller ***********************************************************************/
    reg   [2:0] r_mc_mode           = 0;
    reg  [31:0] r_mc_qnum           = 0;
    reg  [31:0] r_mc_qsel           = 0;

    reg  [31:0] r_mc_done           = 0;
    assign w_mc_mode = r_mc_mode;

    /***** Keyboard Input *************************************************************************/
    reg   [3:0] r_consf_head        = 0;  // Note!!
    reg   [3:0] r_consf_tail        = 0;  // Note!!
    reg   [4:0] r_consf_cnts        = 0;  // Note!!
    reg         r_consf_en;
    initial r_consf_en = 0;

    reg   [7:0] cons_fifo [0:15];
    initial begin
        cons_fifo[0] = 8'h72;
        cons_fifo[1] = 8'h6f;
        cons_fifo[2] = 8'h6f;
        cons_fifo[3] = 8'h74;
        cons_fifo[4] = 8'hd;
        cons_fifo[5] = 8'h74;
        cons_fifo[6] = 8'h6f;
        cons_fifo[7] = 8'h70;
        cons_fifo[8] = 8'hd;
    end

    /**********************************************************************************************/
    // dram data
    wire [31:0] w_dram_odata;


    wire [31:0] w_mc_addr;
    wire [31:0] w_mc_wdata;
    wire        w_mc_we;
    wire  [2:0] w_mc_ctrl;
    wire  [1:0] w_mc_aces;

    wire  w_mode_is_mc  = r_mc_mode != `MC_MODE_CPU;
    wire  w_mode_is_cpu = r_mc_mode == `MC_MODE_CPU;

    wire [31:0] w_mem_wdata = (w_mode_is_mc) ? w_mc_wdata  : w_data_wdata;
    wire        w_mem_we    = (w_mode_is_mc) ? w_mc_we     : w_data_we;

    /***********************************          Memory        ***********************************/
    wire [31:0] w_insn_paddr =  w_cluster_iaddr;

    wire [31:0] w_mem_paddr  =  (w_mode_is_mc) ? w_mc_addr : w_cluster_daddr;

    wire [2:0]  w_mem_ctrl   =  (w_mode_is_mc)                        ? w_mc_ctrl         :
                                (w_is_paddr)                          ? w_data_ctrl       :
                                (w_tlb_use[1:0]!=0)                   ? w_data_ctrl       :
                                (w_pw_state == 0)                     ? `FUNCT3_LW____    :
                                (w_pw_state == 2)                     ? `FUNCT3_LW____    :
                                (w_pw_state == 5)                     ? `FUNCT3_SW____    :
                                w_data_ctrl;

    wire  [3:0] w_dev       = w_mem_paddr[31:28];
    wire  [3:0] w_virt      = w_mem_paddr[27:24];
    assign w_offset         = w_mem_paddr & 28'h7ffffff;

    wire [31:0] w_dram_wdata    = (w_pw_state == 5) ? w_pte_wdata : w_mem_wdata;
    wire        w_dram_we       = (w_mem_we && !w_tlb_busy
                                    && (w_dev == `MEM_BASE_TADDR || w_dev == 0));

    wire [31:0] w_dram_addr =   (w_mode_is_mc)              ? w_mc_addr         :
                                (w_iscode && !w_tlb_busy)   ? w_insn_paddr      :
                                (w_is_paddr)                ? w_cluster_daddr :
                                (w_tlb_acs && !w_tlb_hit)   ? w_tlb_pte_addr    : w_mem_paddr;

    wire [2:0]  w_dram_ctrl =   (w_mode_is_mc)              ? (w_mem_ctrl)      :
                                (w_iscode && !w_tlb_busy)   ? `FUNCT3_LW____    : w_mem_ctrl;
    assign      w_insn_data =   w_dram_rdata128;

    wire        w_dram_aces = (w_dram_addr[31:28] == 8 || w_dram_addr[31:28] == 0);

    assign w_dram_rd_en =
                    (w_dram_busy)  ? 0 :
                    (!w_dram_aces) ? 0 :
                    (w_mode_is_mc) ? (w_mc_aces==`ACCESS_READ && w_mc_addr[31:28] != 0) :
                    (w_is_paddr)   ? (w_iscode || w_isread) :
                    (w_tlb_use[2:1]!=0) ? 1 :
                    (w_tlb_busy && !w_tlb_hit && (w_pw_state == 0 || w_pw_state==2)) ? 1 : 0;


    /****************** RVCoreM memory map **********************
    0x40000000 +------------------------+
               | Console registers      |
    0x41000000 +------------------------+
               | Disk registers         |
    0x42000000 +------------------------+
               | Ethernet registers     |
    0x43000000 +------------------------+
               | Keyboard registers     |
    0x44000000 +------------------------+
               | Mouse registers        |
    0x45000000 +------------------------+
               | Simple framebuffer     |
    0x50000000 +------------------------+
               | PLIC                   |
    0x60000000 +------------------------+
               | CLINT                  |
    0x70000000 +------------------------+


    /***********************************         Console        ***********************************/
    wire        w_cons_we   = (w_mode_is_mc) ? (w_mem_we && w_mem_paddr[31:12] == 20'h4000a) :
                            (w_mem_we && !w_tlb_busy && w_dev == `VIRTIO_BASE_TADDR && w_virt == 0);
    wire [31:0] w_cons_data;
    wire [31:0] w_cons_addr = (w_mode_is_mc) ? w_mem_paddr : {4'b0, w_offset};
    wire        w_cons_req;
    wire [31:0] w_cons_irq;
    wire        w_cons_irq_oe;
    wire [31:0] w_cons_qnum;
    wire [31:0] w_cons_qsel;

    /***********************************           Disk         ***********************************/
    wire        w_disk_we   = (w_mode_is_mc) ? (w_mem_we && w_mem_paddr[31:12] == 20'h4000b) :
                            (w_mem_we && !w_tlb_busy && w_dev == `VIRTIO_BASE_TADDR && w_virt == 1);
    wire [31:0] w_disk_data;
    wire [31:0] w_disk_addr = (w_mode_is_mc) ? w_mem_paddr : {4'b0, w_offset};
    wire        w_disk_req;
    wire [31:0] w_disk_irq;
    wire        w_disk_irq_oe;
    wire [31:0] w_disk_qnum;
    wire [31:0] w_disk_qsel;

    /***********************************      Ethernet MAC     ***********************************/
    wire        w_ether_we   = (w_mode_is_mc) ? (w_mem_we && (w_mem_paddr[31:12] == 20'h4000d || w_mem_paddr[31:12] == 20'h4000e)) :
                            (w_mem_we && !w_tlb_busy && w_dev == `VIRTIO_BASE_TADDR && w_virt == 2);
    wire [31:0] w_ether_data;
    wire [31:0] w_ether_addr = (w_mode_is_mc) ? w_mem_paddr : {4'b0, w_offset};
    wire        w_ether_send_req, w_ether_recv_req;
    wire [31:0] w_ether_irq;
    wire        w_ether_irq_oe;
    wire [31:0] w_ether_qnum;
    wire [31:0] w_ether_qsel;
    // reg  plic_ether_en = 0;
    reg  plic_ether_en = 1'b1; // Correct?

    /***********************************  　Keyboard     ***********************************/
    wire        w_keybrd_we   = (w_mode_is_mc) ? (w_mem_we && w_mem_paddr[31:12] == 20'h40010 ) :
                            (w_mem_we && !w_tlb_busy && w_dev == `VIRTIO_BASE_TADDR && w_virt == 3);
    wire [31:0] w_keybrd_data;
    wire [31:0] w_keybrd_addr = (w_mode_is_mc) ? w_mem_paddr : {4'b0, w_offset};
    wire        w_keybrd_req;
    wire [31:0] w_keybrd_irq;
    wire        w_keybrd_irq_oe;
    wire [31:0] w_keybrd_qnum;
    wire [31:0] w_keybrd_qsel;

    /***********************************  　Mouse    ***********************************/
    wire        w_mouse_we   = (w_mode_is_mc) ? (w_mem_we && w_mem_paddr[31:12] == 20'h40011 ) :
                            (w_mem_we && !w_tlb_busy && w_dev == `VIRTIO_BASE_TADDR && w_virt == 4);
    wire [31:0] w_mouse_data;
    wire [31:0] w_mouse_addr = (w_mode_is_mc) ? w_mem_paddr : {4'b0, w_offset};
    wire        w_mouse_req;
    wire [31:0] w_mouse_irq;
    wire        w_mouse_irq_oe;
    wire [31:0] w_mouse_qnum;
    wire [31:0] w_mouse_qsel;

    /***********************************      Simple Framebuffer     ***********************************/
    assign w_fb_we = (w_mem_we && !w_tlb_busy && w_dev == `VIRTIO_BASE_TADDR && w_virt == 5);
    assign w_fb_wdata = w_mem_wdata;

    /***********************************          OUTPUT        ***********************************/
    reg  [31:0] r_data_data = 0;
    reg         is_dram_data;
    always@(*) begin
        is_dram_data = 0;
        case (r_dev)
            `CLINT_BASE_TADDR : r_data_data = w_clint_rdata;
            `PLIC_BASE_TADDR  : r_data_data = w_plic_rdata;
            `VIRTIO_BASE_TADDR:
            case (r_virt)
                0: r_data_data = w_cons_data;
                1: r_data_data = w_disk_data;
                2: r_data_data = w_ether_data;
                3: r_data_data = w_keybrd_data;
                4: r_data_data = w_mouse_data;
                5: r_data_data = w_fb_rdata;
                default: r_data_data = 0;
            endcase
            default: begin
                r_data_data = w_dram_odata;
                is_dram_data = 1;
            end
        endcase
    end
    assign w_data_data = (is_dram_data) ? w_dram_rdata128 : {96'h0, r_data_data};
    assign w_is_dram_data = is_dram_data;

    /***********************************          VirtIO        ***********************************/
    wire        w_uart_valid;
    wire  [7:0] w_uart_recvdata;
    wire        w_uart_req = r_consf_en && (w_mtime > 64'd61000000) && ((w_mtime & 64'h3ffff) == 0)
                            && w_mode_is_cpu && w_init_stage;
    reg         r_uart_valid = 0;
    reg   [7:0] r_uart_recvdata  = 0;
    always@(posedge CLK) begin
        r_uart_valid   <= w_uart_valid;
        r_uart_recvdata  <= w_uart_recvdata;
    end

    always@(posedge CLK) begin
        if(r_mc_done) begin
            r_mc_mode <= `MC_MODE_CPU;
            r_mc_done <= 0;
            if(r_mc_mode==`MC_MODE_KEY) begin
                r_consf_en <= (r_consf_cnts<=1) ? 0 : 1;
                r_consf_head <= r_consf_head + 1;
                r_consf_cnts <= r_consf_cnts - 1;
            end
        end

        if(w_cons_req) begin
            r_mc_mode <= `MC_MODE_CONS;
            r_mc_qnum <= w_cons_qnum;
            r_mc_qsel <= w_cons_qsel;
        end else if(w_uart_req) begin
            r_mc_mode <= `MC_MODE_KEY;
            r_mc_qnum <= w_cons_qnum;
            r_mc_qsel <= 0;
        end else if(w_disk_req) begin
            r_mc_mode <= `MC_MODE_DISK;
            r_mc_qnum <= w_disk_qnum;
            r_mc_qsel <= w_disk_qsel;
        end else if(w_ether_send_req) begin
            r_mc_mode <= `MC_MODE_ETHER_SEND;
            r_mc_qnum <= w_ether_qnum;
            r_mc_qsel <= w_ether_qsel;
        end else if(w_ether_recv_req) begin
            r_mc_mode <= `MC_MODE_ETHER_RECV;
            r_mc_qnum <= w_ether_qnum;
            r_mc_qsel <= 0;
        end else if(w_keybrd_req) begin
            r_mc_mode <= `MC_MODE_KEYBRD;
            r_mc_qnum <= w_keybrd_qnum;
            r_mc_qsel <= w_keybrd_qsel;
        end else if(w_mouse_req) begin
            r_mc_mode <= `MC_MODE_MOUSE;
            r_mc_qnum <= w_mouse_qnum;
            r_mc_qsel <= w_mouse_qsel;
        end


        if(r_uart_valid) begin
            if(r_consf_cnts < 16) begin
                cons_fifo[r_consf_tail] <= r_uart_recvdata;
                r_consf_tail            <= r_consf_tail + 1;
                r_consf_cnts            <= r_consf_cnts + 1;
                r_consf_en              <= 1;
            end
        end

        if(r_tohost[31:16]==`CMD_POWER_OFF) begin
            r_mc_done <= 1;
        end
    end

    reg  [31:0] r_mc_arg = 0;
    always@(*) begin
        case (w_mem_paddr[31:12])
            20'h40009: begin
                case (w_mem_paddr[3:0])
                    4: r_mc_arg = r_mc_qnum;
                    8: r_mc_arg = r_mc_qsel;
                    default: r_mc_arg = r_mc_mode;
                endcase
            end
            20'h4000a: r_mc_arg = w_cons_data;
            20'h4000b: r_mc_arg = w_disk_data;
            20'h4000c: r_mc_arg = cons_fifo[r_consf_head];
            20'h4000d: r_mc_arg = w_ether_data;
            20'h4000f: r_mc_arg = w_ether_data;
            20'h40010: r_mc_arg = w_keybrd_data;
            20'h40011: r_mc_arg = w_mouse_data;
            default:   begin
                if (w_mem_paddr[31:28] >= 9) begin
                    r_mc_arg = sdctrl_rdata;
                end else begin
                    r_mc_arg = w_dram_odata;
                end
            end
        endcase
    end

    wire [31:0] w_mc_arg = r_mc_arg;

    m_RVuc mc(CLK, w_mode_is_mc, (w_dram_busy | sdctrl_busy), w_mc_addr, w_mc_arg, w_mc_wdata,
                w_mc_we, w_mc_ctrl, w_mc_aces);

    reg [31:0] plic_pending_irq = 0; // Correct?

    m_console   console(CLK, 1'b1, w_cons_we, w_cons_addr, w_mem_wdata, plic_pending_irq, w_cons_data,
                        w_cons_irq, w_cons_irq_oe, r_mc_mode, w_cons_req, w_cons_qnum, w_cons_qsel, w_uart_req);

    m_disk      disk(CLK, 1'b1, w_disk_we, w_disk_addr, w_mem_wdata, plic_pending_irq, w_disk_data,
                        w_disk_irq, w_disk_irq_oe, r_mc_mode, w_disk_req, w_disk_qnum, w_disk_qsel);

    m_ether     ether(CLK, clk_50mhz, RST_X, w_ether_we, w_ether_addr, w_mem_wdata, plic_pending_irq, w_ether_data,
                        w_ether_irq, w_ether_irq_oe, r_mc_mode, w_ether_send_req, w_ether_recv_req, w_ether_qnum, w_ether_qsel,
                        w_crs_dv_phy, w_txd_phy, w_txen_phy, w_rxd_phy, w_rxerr_phy, w_clkin_phy, w_mtime, w_init_stage, plic_ether_en);

    m_keyboard  keybrd(CLK, RST_X, w_keybrd_we, w_keybrd_addr, w_mem_wdata, plic_pending_irq, w_keybrd_data,
                        w_keybrd_irq, w_keybrd_irq_oe, r_mc_mode, w_keybrd_req, w_keybrd_qnum, w_keybrd_qsel, w_mtime, w_init_stage,
`ifdef CH559_USB
                        ch559_rx,
`else
                        pmod_ps2_clk, pmod_ps2_data,
`endif
                        w_ps2_kbd_we, w_ps2_kbd_data);

    m_mouse  mouse(CLK, RST_X, w_mouse_we, w_mouse_addr, w_mem_wdata, plic_pending_irq, w_mouse_data,
                        w_mouse_irq, w_mouse_irq_oe, r_mc_mode, w_mouse_req, w_mouse_qnum, w_mouse_qsel, w_mtime, w_init_stage,
                        usb_ps2_clk, usb_ps2_data, w_ps2_mouse_we, w_ps2_mouse_data);

    /***********************************           PLIC         ***********************************/
    assign w_plic_we = (w_mode_is_cpu && w_dev == `PLIC_BASE_TADDR) && !w_tlb_busy && w_iswrite;
    assign w_plic_wdata = w_data_wdata;
    assign w_plic_re = (w_mode_is_cpu && w_dev == `PLIC_BASE_TADDR) && !w_tlb_busy && w_isread;

    /***********************************           BUSY         ***********************************/
    assign w_tlb_busy =
                    !(w_use_tlb)                            ? 0 :
                    (w_pw_state == 7)                       ? 0 : 1;

    wire w_mc_busy =    (w_mode_is_mc) ? 1 : 0;

    wire w_tx_ready;
    assign w_proc_busy = w_r_tlb_busy || w_mc_busy || w_dram_busy || !w_tx_ready;
    /**********************************************************************************************/
    reg         r_uart_we = 0;
    reg   [7:0] r_uart_data = 0;

    always@(posedge CLK) begin
        r_dev   <= w_dev;
        r_virt  <= w_virt;

        /*********************************         TOHOST         *********************************/
        // OUTPUT CHAR
        if(r_tohost[31:16]==`CMD_PRINT_CHAR) begin
            r_uart_we   <= 1;
            r_uart_data <= r_tohost[7:0];
            $write("%c", r_tohost[7:0]);
        end else begin
            r_uart_we   <= 0;
            r_uart_data <= 0;
        end
        // Finish Simulation
        if(r_tohost[31:16]==`CMD_POWER_OFF) begin
            if(w_mode_is_cpu) r_finish = 1;
            else begin
                r_tohost <= 0;
            end
        end
        else begin
            r_tohost <= (w_mem_paddr==`TOHOST_ADDR && w_mem_we) ? w_mem_wdata   :
                        (r_tohost[31:16]==`CMD_PRINT_CHAR)      ? 0             : r_tohost;
        end
    end
    /**********************************************************************************************/

    wire w_cons_txd;
    UartTx UartTx0(CLK, RST_X, r_uart_data, r_uart_we, w_cons_txd, w_tx_ready);
    serialc serialc0(CLK, RST_X, w_rxd, w_uart_recvdata, w_uart_valid);


    assign w_uart_data = r_uart_data;
    assign w_uart_we   = r_uart_we;

    wire [31:0]  w_pl_init_addr;
    wire [31:0]  w_pl_init_data;
    wire         w_pl_init_we;
    wire         w_pl_init_done;

    assign       w_pl_init_addr = loader_addr;
    assign       w_pl_init_data = loader_data;
    assign       w_pl_init_we   = loader_we;
    assign       w_pl_init_done = loader_done;

    /**********************************************************************************************/

    reg  [31:0]  r_checksum = 0;
    always@(posedge CLK) begin
        r_checksum <= (!RST_X)                      ? 0                             :
                      (!w_init_done & w_pl_init_we) ? r_checksum + w_pl_init_data   :
                      r_checksum;
    end

    assign w_checksum = r_checksum;

    /**********************************************************************************************/

    wire w_debug_txd;
    wire w_rec_done;
    m_debug_key debug_KEY(CLK, RST_X, w_debug_btnd, w_debug_txd, w_uart_we, w_uart_data, w_mtime[31:0], w_rec_done);

    assign w_txd = (w_rec_done) ? w_debug_txd : w_cons_txd;

/**************************************************************************************************/
    reg          r_bbl_done   = 0;
    reg          r_dtree_done = 0;
    reg          r_disk_done  = 1;
    reg  [31:0]  r_initaddr  = 0;
    reg  [31:0]  r_initaddr3 = (`BIN_DTB_START); /* initial address of Device Tree */

    // Zero init
    wire w_zero_we;
    reg  r_zero_we;
    reg  r_zero_done        = 1;
    reg  [31:0]  r_zeroaddr = 0;

    reg  [2:0] r_init_state = 0;
    always@(posedge CLK) begin
        r_init_state <= (!RST_X) ? 0 :
                      (r_init_state == 0)              ? 2 :
                      (r_init_state == 2 & r_bbl_done)   ? 3 :
                      (r_init_state == 3 & r_dtree_done) ? 4 :
                      r_init_state;
    end

    assign w_init_start = (r_initaddr != 0);

    assign w_init_done = (r_init_state == 4);

    always@(posedge CLK) begin
        if(w_pl_init_we & (r_init_state == 2))              r_initaddr      <= r_initaddr + 4;
        if(r_initaddr  >= (`BIN_BBL_SIZE - `BIN_DTB_SIZE))  r_bbl_done      <= 1;
        if(w_pl_init_we & (r_init_state == 3))              r_initaddr3     <= r_initaddr3 + 4;
        if(r_initaddr3 >= (`BIN_DTB_START + `BIN_DTB_SIZE)) r_dtree_done    <= 1;
    end

    // Zero init
    always@(posedge CLK) begin
        if(!w_dram_busy & !r_zero_done) r_zero_we <= 1;
        if(r_zero_we) begin
            r_zero_we    <= 0;
            r_zeroaddr <= r_zeroaddr + 4;
        end
        if(r_zeroaddr >= `MEM_SIZE) r_zero_done <= 1;
    end

    assign w_zero_we = r_zero_we;

    /**********************************************************************************************/
    wire [31:0]  w_dram_addr_t  = w_dram_addr & 32'h7ffffff;
    assign w_dram_addr_t2 = (r_init_state == 1) ? r_zeroaddr  :
                            (r_init_state == 2) ? r_initaddr  :
                            (r_init_state == 3) ? r_initaddr3 : w_dram_addr_t;

    assign w_dram_wdata_t = (r_init_state == 1) ? 32'b0 :
                            (r_init_state == 4) ? w_dram_wdata : w_pl_init_data;
    wire w_dram_we_t = (w_pte_we || w_dram_we) && !w_dram_busy;
    assign w_dram_ctrl_t = (!w_init_done) ? `FUNCT3_SW____ : w_dram_ctrl;

    reg  [31:0] r_addr = 0;
    reg  [2 :0] r_ctrl = 0;
    always @ (posedge CLK) begin
        if (w_dram_we_t | w_dram_rd_en) begin
            r_addr <= w_dram_addr_t2;
            r_ctrl <= w_dram_ctrl_t;
        end
    end

    wire[127:0] w_odata_t1 = (w_dram_rdata128 >> {r_addr[3:0], 3'b0});
    wire [31:0] w_odata_t2 = w_odata_t1[31:0];

    wire [31:0] w_ld_lb = {{24{w_odata_t2[ 7]&(~r_ctrl[2])}}, w_odata_t2[ 7:0]};
    wire [31:0] w_ld_lh = {{16{w_odata_t2[15]&(~r_ctrl[2])}}, w_odata_t2[15:0]};

    assign w_dram_odata = (r_ctrl[1:0]==0) ? w_ld_lb :
                    (r_ctrl[1:0]==1) ? w_ld_lh : w_odata_t2;

    /*********************************          CLINT         *********************************/
    assign w_clint_we = (w_mode_is_cpu &&w_dev == `CLINT_BASE_TADDR && w_data_we != 0);
    assign w_clint_wdata = w_data_wdata;

    /***********************************      DRAM     ***********************************/
    assign w_dram_wr_en = w_zero_we || w_pl_init_we || w_dram_we_t;

endmodule
/**************************************************************************************************/
/*** Simple Direct Mapped Cache for TLB                                                         ***/
/**************************************************************************************************/
module m_cache_dmap#(parameter ADDR_WIDTH = 20, D_WIDTH = 20, ENTRY = 4)
            (CLK, RST_X, w_flush, w_we, w_waddr, w_raddr, w_idata, w_odata, w_oe);
    input  wire                     CLK, RST_X;
    input  wire                     w_flush, w_we;
    input  wire [ADDR_WIDTH-1:0]    w_waddr, w_raddr;
    input  wire    [D_WIDTH-1:0]    w_idata;
    output wire    [D_WIDTH-1:0]    w_odata;
    output wire                     w_oe;             //output enable
    reg                               [ENTRY-1:0]   r_valid = 0;
    reg  [(ADDR_WIDTH-$clog2(ENTRY)+D_WIDTH)-1:0]   mem [0:ENTRY-1];
    integer i;
    initial for(i=0; i<ENTRY; i=i+1) mem[i] = 0;
    // READ
    wire              [$clog2(ENTRY)-1:0]   w_ridx;
    wire [(ADDR_WIDTH-$clog2(ENTRY))-1:0]   w_rtag;
    assign {w_rtag, w_ridx} = w_raddr;
    wire [ENTRY-1:0] w_ridx_v = ({{(ENTRY-1){1'b0}},{1'b1}} << w_ridx);
    wire w_tagmatch = (mem[w_ridx][(ADDR_WIDTH-$clog2(ENTRY)+D_WIDTH)-1:D_WIDTH] == w_rtag);
    assign w_odata  = mem[w_ridx][D_WIDTH-1:0];
    //assign w_oe     = (w_tagmatch && r_valid[w_ridx]);
    assign w_oe     = (w_tagmatch && (r_valid & w_ridx_v));
    // WRITE
    wire              [$clog2(ENTRY)-1:0]   w_widx;
    wire [(ADDR_WIDTH-$clog2(ENTRY))-1:0]   w_wtag;
    assign {w_wtag, w_widx} = w_waddr;
    wire [ENTRY-1:0] w_widx_v = ({{(ENTRY-1){1'b0}},{1'b1}} << w_widx);
    always  @(posedge  CLK)  begin
        // FLUSH
        if (!RST_X || w_flush) begin
            r_valid <= 0;
        end
        if (w_we) begin
            mem[w_widx] <= {w_wtag, w_idata};
            //r_valid[w_widx] <= 1;
            r_valid <= r_valid | w_widx_v;
        end
    end
endmodule // m_cache_dmap
/**************************************************************************************************/
