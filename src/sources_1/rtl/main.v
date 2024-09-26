/**************************************************************************************************/
/**** RVSoC (Mini Kuroda/RISC-V)                       since 2018-08-07   ArchLab. TokyoTech   ****/
/**** main module for Implemetaion v0.13                                                       ****/
/**************************************************************************************************/
`default_nettype none
/**************************************************************************************************/
`include "define.vh"

// `define DRAM_SIM_CPP   1
// `define SDCARD_SIM_CPP 1
/**************************************************************************************************/
module m_main(
    input  wire        CLK,
    // UART
    input  wire        w_rxd,
    output wire        w_txd,
    // LED
    output wire [15:0] w_led,
    // 7seg
    output reg   [7:0] r_sg,
    output reg   [7:0] r_an,
    // RGB LED
    output wire        w_led1_B,
    output wire        w_led1_G,
    output wire        w_led1_R,
    // DRAM
`ifdef SYNTHESIS
    inout  wire [15:0] ddr2_dq,
    inout  wire  [1:0] ddr2_dqs_n,
    inout  wire  [1:0] ddr2_dqs_p,
    output wire [12:0] ddr2_addr,
    output wire  [2:0] ddr2_ba,
    output wire        ddr2_ras_n,
    output wire        ddr2_cas_n,
    output wire        ddr2_we_n,
    output wire        ddr2_ck_p,
    output wire        ddr2_ck_n,
    output wire        ddr2_cke,
    output wire        ddr2_cs_n,
    output wire  [1:0] ddr2_dm,
    output wire        ddr2_odt,
`else
`ifdef DRAM_SIM_CPP
    output wire         dram_rd_en,
    output wire         dram_wr_en,
    output wire [31:0]  dram_addr,
    output wire [31:0]  dram_wdata,
    input  wire [127:0] dram_rdata128,
    input  wire         dram_busy,
    output wire [2:0]   dram_ctrl,
`endif
`endif
    // Button
    input  wire        w_btnu,
    input  wire        w_btnd,
    input  wire        w_btnl,
    input  wire        w_btnr,
    input  wire        w_btnc,
    // Ethernet
    output wire        w_mdio_phy,
    output reg         r_mdc_phy = 0,
    output reg         r_rstn_phy,
    input  wire        w_crs_dv_phy,
    output wire  [1:0] w_txd_phy,
    output wire        w_txen_phy,
    input  wire  [1:0] w_rxd_phy,
    input  wire        w_rxerr_phy,
    output wire        w_clkin_phy,
    // SD card
`ifdef SYNTHESIS
    input  wire        sd_cd,
    output wire        sd_rst,
    output wire        sd_sclk,
    inout  wire        sd_cmd,
    inout  wire [ 3:0] sd_dat,
`else
`ifdef SDCARD_SIM_CPP
    output wire [40:0] w_sdcram_addr,
    output wire        w_sdcram_ren,
    output wire [ 3:0] w_sdcram_wen,
    output wire [31:0] w_sdcram_wdata,
    input  wire [31:0] w_sdcram_rdata,
`endif
`endif
    // VGA
`ifdef SYNTHESIS
    output wire [ 3:0] vga_red,
    output wire [ 3:0] vga_green,
    output wire [ 3:0] vga_blue,
    output wire        vga_h_sync,
    output wire        vga_v_sync,
`else
    output wire        w_vga_we,
    output wire [31:0] w_vga_waddr,
    output wire [31:0] w_vga_wdata,
`endif
    // Mouse
    inout  wire        usb_ps2_clk,
    inout  wire        usb_ps2_data,
    // Keyboard
`ifdef CH559_USB
    input  wire        ch559_rx
`else
    inout  wire        pmod_ps2_clk,
    inout  wire        pmod_ps2_data
`endif
);

    /*******************************************************************************/
    localparam DEBUG = 0;
    localparam DEBUG_CLINT = 0;
    localparam N_HARTS = 2;
    localparam N_INT_SRC = 5;
    /*******************************************************************************/

    wire RST_X_IN = 1;

    reg [31:0] r_cnt=0;
    reg        r_time_led=0;
    always@(posedge CORE_CLK) r_cnt <= (r_cnt>=(64*1000000/2-1)) ? 0 : r_cnt+1;
    always@(posedge CORE_CLK) r_time_led <= (r_cnt==0) ? !r_time_led : r_time_led;

    assign w_led[0] = r_time_led;
    assign w_led[1] = w_init_done;
    assign w_led[2] = w_data_we;
    assign w_led[3] = w_busy;
    assign w_led[15:4] = 0;

    /*******************************************************************************/
    reg         r_stop = 0;
    reg  [63:0] r_core_cnt = 0;

    // Connection Core <--> mem_ctrl
    wire [127:0] w_insn_data;
    wire [127:0] w_data_data;
    wire        w_is_dram_data;
    wire [31:0] w_data_wdata;
    wire        w_data_we;
    wire  [2:0] w_data_ctrl;

    wire [31:0] w_priv, w_satp;
    wire        w_interconnect_busy;
    wire        w_busy = w_interconnect_busy || cluster.w_cluster_tlb_busy;
    wire        w_init_done;
    wire        w_init_stage;

    // Clock
    wire CORE_CLK, clk_50mhz, w_locked;

`ifdef SYNTHESIS
    wire mig_clk, pix_clk;
    clk_wiz_0 m_clkgen0 (
        .clk_in1(CLK),
        .resetn(RST_X_IN),
        .locked(w_locked),
        .clk_out1(mig_clk),   // 200MHz for MIG
        .clk_out2(clk_50mhz), // 50MHz for SD card and Ethernet
        .clk_out3(pix_clk)    // 25MHz for framebuffer
    );
`else
    reg r_50mhz_gen = 1'b0;
    always @(posedge CLK) begin
        r_50mhz_gen <= ~r_50mhz_gen;
    end
    assign clk_50mhz = r_50mhz_gen;
    assign w_locked = 1'b1;
`endif

    // Reset
    wire RST        = ~w_locked;
    wire RST_X      = ~RST & RST_X2;
    wire CORE_RST_X = RST_X & w_init_done;

    // Ethernet PHY
    always @ (posedge w_clkin_phy) begin
        r_rstn_phy <= !RST;
    end

    reg[6:0] cnt = 0;
    always @ (posedge CLK) begin
        if (cnt == 100) begin
            r_mdc_phy <= ~r_mdc_phy;
            cnt <= 0;
        end else begin
            cnt <= cnt + 1;
        end
    end

    assign w_mdio_phy = 0;

    wire[2:0] w_mc_mode;

    reg [63:0] cpu_cnt = 0, mc_cnt = 0;

    always @ (posedge CORE_CLK) begin
        if (!CORE_RST_X) begin
            cpu_cnt <= 0;
            mc_cnt <= 0;
        end else if ((w_mc_mode == 0) & !r_stop) begin
            cpu_cnt <= cpu_cnt + 1;
        end else if (!r_stop) begin
            mc_cnt <= mc_cnt + 1;
        end
    end


    wire w_tlb_busy;
    reg [63:0] tlb_cnt = 0, dram_cnt = 0;
    always @ (posedge CORE_CLK) begin
        if (!RST_X) begin
            tlb_cnt <= 0;
            dram_cnt <= 0;
        end else if (w_busy & w_tlb_busy & !r_stop) begin
            tlb_cnt <= tlb_cnt + 1;
        end else if(w_busy & w_dram_busy & !r_stop)  begin
            dram_cnt <= dram_cnt + 1;
        end
    end

    wire w_kbd_we, w_mouse_we;
    wire [7:0] w_kbd_data, w_mouse_data;
    reg [31:0] led_data = 0;
    always @ (posedge CORE_CLK) begin
        if (w_kbd_we) begin
            led_data[7:0]  <= w_kbd_data;
            led_data[15:8] <= led_data[7:0];
        end
        if (w_mouse_we) begin
            led_data[23:16] <= w_mouse_data;
            led_data[31:24] <= led_data[23:16];
        end
    end

    // 7seg
    reg  [31:0] r_init_cycles = 0;
    wire [31:0] w_core_odata = cluster.cores_and_mmus[0].core_wrapper.core_inst.inst_cnt;
    wire [31:0] w_core_pc = cluster.cores_and_mmus[0].core_wrapper.core_inst.pc;
    wire [31:0] w_core_ir = cluster.cores_and_mmus[0].core_wrapper.core_inst.w_instruction;
    wire [31:0] w_7seg_data = (w_btnu) ? 0: (w_btnd) ? 0: (w_btnc) ? 0:
                (w_btnl) ? w_core_pc  : (w_btnr) ? w_core_ir : led_data;
    wire w_init_start;
    reg         r_load = 0;
    always@(posedge CORE_CLK) begin
        if(r_load==0 && w_init_start && !w_init_done) r_load <= 1;
        else if(w_init_done) r_load <= 0;
        if (r_load) r_init_cycles <= r_init_cycles+1;
    end


    wire  [7:0] w_sg;
    wire  [7:0] w_an;
    m_7segcon m_7segcon(CORE_CLK, CORE_RST_X, r_load, w_7seg_data, w_sg, w_an);
    always @(posedge CORE_CLK) begin
        r_sg <= w_sg;
        r_an <= w_an;
    end

    // Uart
    wire  [7:0] w_uart_data;
    wire        w_uart_we;

    wire w_finish;

    wire [15:0] w_led_t = (w_busy << 12) | (w_mc_mode << 8)
                        | ({interconn.w_pl_init_done, interconn.r_disk_done, interconn.r_bbl_done, interconn.r_zero_done} << 4) | interconn.r_init_state;

    // stop and count
    always@(posedge CORE_CLK) begin
        if(w_btnc | w_finish | (w_core_odata > `TIMEOUT)) r_stop <= 1;
        if(w_init_done && !r_stop && w_led_t[9:8] == 0) r_core_cnt <= r_core_cnt + 1;
    end

    wire [27:0] w_offset;

    wire         w_cluster_data_we;
    wire [31:0]  w_cluster_dev_addr;
    wire [31:0]  w_cluster_dram_addr;
    wire [2:0]   w_cluster_mem_ctrl;
    wire         w_cluster_dram_re; 

    m_interconnect #(
        .N_HARTS(N_HARTS)
    )
    interconn(
        .CLK            (CORE_CLK),
        .clk_50mhz      (clk_50mhz),
        .RST_X          (RST_X),
        .w_data_wdata   (w_data_wdata),
        .w_cluster_data_we  (w_cluster_data_we),
        .w_cluster_dev_addr (w_cluster_dev_addr),
        .w_cluster_dram_addr(w_cluster_dram_addr),
        .w_cluster_mem_ctrl (w_cluster_mem_ctrl),
        .w_cluster_dram_re  (w_cluster_dram_re),
        .w_insn_data    (w_insn_data),
        .w_data_data    (w_data_data),
        .w_is_dram_data (w_is_dram_data),
        .r_finish       (w_finish),
        .w_mtime        (w_mtime),
        .w_is_paddr     (w_cluster_is_paddr),
        // MMU
        .w_iscode       (w_cluster_iscode),
        .w_isread       (w_cluster_isread),
        .w_iswrite      (w_cluster_iswrite),
        .w_pte_we       (w_cluster_pte_we),
        .w_pte_wdata    (w_cluster_pte_wdata),
        .w_use_tlb      (w_cluster_use_tlb),
        .w_tlb_hit      (w_cluster_tlb_hit),
        .w_pw_state     (w_cluster_pw_state),
        .w_tlb_usage    (w_cluster_tlb_usage),
        .w_tlb_acs      (w_cluster_tlb_acs),
        // MMU end
        .w_interconnect_busy(w_interconnect_busy),
        .w_txd          (w_txd),
        .w_rxd          (w_rxd),
        .w_init_done    (w_init_done),
        .w_uart_data    (w_uart_data),
        .w_uart_we      (w_uart_we),
        .w_init_stage   (w_init_stage),
        .w_debug_btnd   (w_btnd),
        .w_crs_dv_phy   (w_crs_dv_phy),
        .w_txd_phy      (w_txd_phy),
        .w_txen_phy     (w_txen_phy),
        .w_rxd_phy      (w_rxd_phy),
        .w_rxerr_phy    (w_rxerr_phy),
        .w_clkin_phy    (w_clkin_phy),
        .usb_ps2_clk    (usb_ps2_clk),
        .usb_ps2_data   (usb_ps2_data),
`ifdef CH559_USB
        .ch559_rx       (ch559_rx),
`else
        .pmod_ps2_clk   (pmod_ps2_clk),
        .pmod_ps2_data  (pmod_ps2_data),
`endif
        .w_init_start   (w_init_start),
        .w_mc_mode      (w_mc_mode),
        .w_tlb_busy     (w_tlb_busy),
        // DRAM
        .w_dram_busy    (w_dram_busy),
        .w_dram_rd_en   (w_dram_rd_en),
        .w_dram_wr_en   (w_dram_wr_en),
        .w_dram_addr_t2 (w_dram_addr),
        .w_dram_wdata_t (w_dram_wdata),
        .w_dram_rdata128(w_dram_rdata128),
        .w_dram_ctrl_t  (w_dram_ctrl),
        .w_ps2_kbd_we   (w_kbd_we),
        .w_ps2_kbd_data (w_kbd_data),
        .w_ps2_mouse_we (w_mouse_we),
        .w_ps2_mouse_data  (w_mouse_data),
        // SD card controller
        .loader_addr    (loader_addr),
        .loader_data    (loader_data),
        .loader_we      (loader_we),
        .loader_done    (loader_done),
        .sdctrl_rdata   (sdctrl_rdata),
        .sdctrl_busy    (sdctrl_busy),
        // PLIC
        .w_plic_we      (w_plic_we),
        .w_plic_wdata   (w_plic_wdata),
        .w_plic_re      (w_plic_re),
        .w_plic_rdata   (w_plic_rdata),
        // CLINT
        .w_clint_we     (w_clint_we),
        .w_clint_wdata  (w_clint_wdata),
        .w_clint_rdata  (w_clint_rdata),
        // Framebuffer
        .w_fb_we         (w_fb_we),
        .w_fb_wdata      (w_fb_wdata),
        .w_fb_rdata      (w_fb_rdata),
        //
        .w_offset       (w_offset)
    );

    wire [31:0] w_cluster_iaddr;
    wire [31:0] w_cluster_daddr;
    wire        w_cluster_is_paddr;
    wire        w_cluster_iscode;
    wire        w_cluster_isread;
    wire        w_cluster_iswrite;
    wire        w_cluster_pte_we;
    wire [31:0] w_cluster_pte_wdata;
    wire        w_cluster_use_tlb;
    wire        w_cluster_tlb_hit;
    wire [2:0]  w_cluster_pw_state;
    wire [2:0]  w_cluster_tlb_usage;
    wire [31:0] w_cluster_tlb_pte_addr;
    wire        w_cluster_tlb_acs;

    m_RVCluster #(
        .N_HARTS(N_HARTS)
    ) cluster(
        .CLK(CORE_CLK),
        .RST_X(CORE_RST_X),
        .w_insn_data(w_insn_data),
        .w_data_data(w_data_data),
        .w_is_dram_data(w_is_dram_data),
        .w_interconnect_busy(w_interconnect_busy),
        .w_mc_mode(w_mc_mode),
        .w_mtip(w_mtip),
        .w_msip(w_msip),
        .w_meip(w_meip),
        .w_seip(w_seip),
        .w_mtime(w_mtime),
        .w_dram_busy(w_dram_busy),
        .w_dram_odata(interconn.w_dram_odata),
        .w_mode_is_cpu(interconn.w_mode_is_cpu),
        .w_next_mode_is_mc(interconn.w_virtio_req),
        .w_cluster_iaddr(w_cluster_iaddr),
        .w_cluster_daddr(w_cluster_daddr),
        .w_cluster_data_wdata(w_data_wdata),
        .w_cluster_init_stage(w_init_stage),
        .w_cluster_is_paddr(w_cluster_is_paddr),
        .w_cluster_iscode(w_cluster_iscode),
        .w_cluster_isread(w_cluster_isread),
        .w_cluster_iswrite(w_cluster_iswrite),
        .w_cluster_pte_we(w_cluster_pte_we),
        .w_cluster_pte_wdata(w_cluster_pte_wdata),
        .w_cluster_use_tlb(w_cluster_use_tlb),
        .w_cluster_tlb_hit(w_cluster_tlb_hit),
        .w_cluster_pw_state(w_cluster_pw_state),
        .w_cluster_tlb_usage(w_cluster_tlb_usage),
        .w_cluster_tlb_pte_addr(w_cluster_tlb_pte_addr),
        .w_cluster_tlb_acs(w_cluster_tlb_acs),
        .w_cluster_data_we  (w_cluster_data_we),
        .w_cluster_dev_addr (w_cluster_dev_addr),
        .w_cluster_dram_addr(w_cluster_dram_addr),
        .w_cluster_mem_ctrl (w_cluster_mem_ctrl),
        .w_cluster_dram_re  (w_cluster_dram_re)
    );
`ifdef SYNTHESIS
    generate
        if (DEBUG) begin
            ila_2 your_instance_name (
                .clk(CORE_CLK), // input wire clk
                .probe0(cluster.core0.tkn), // input wire [31:0]  probe0  
                .probe1(cluster.core0.IdEx_pc), // input wire [31:0]  probe1 
                .probe2(cluster.core0.IdEx_ir), // input wire [31:0]  probe2 
                .probe3(cluster.core0.pc), // input wire [31:0]  probe3 
                .probe4(w_fb_we), // input wire [31:0]  probe4 
                .probe5(0), // input wire [31:0]  probe5 
                .probe6(0), // input wire [31:0]  probe6 
                .probe7(0) // input wire [31:0]  probe7
            );
        end
    endgenerate
`endif

    /***********************************         SD Card       ***********************************/
    wire [31:0] loader_addr;
    wire [31:0] loader_data;
    wire        loader_we;
    wire        loader_done;
    wire [40:0] sdcram_addr;
    wire        sdcram_ren;
    wire [ 3:0] sdcram_wen;
    wire [31:0] sdcram_wdata;
    wire [31:0] sdcram_rdata;
    wire        sdcram_busy;
    wire [31:0] sdctrl_rdata;
    wire        sdctrl_busy;

    periph_sdcard periph_sdcard(
        .CLK         (CORE_CLK),
        .RST_X       (RST_X),
        .loader_addr (loader_addr),
        .loader_data (loader_data),
        .loader_we   (loader_we),
        .loader_done (loader_done),
        .w_dram_busy (w_dram_busy),
        .sdcram_addr(sdcram_addr),
        .sdcram_ren(sdcram_ren),
        .sdcram_wen(sdcram_wen),
        .sdcram_wdata(sdcram_wdata),
        .sdcram_rdata(sdcram_rdata),
        .sdcram_busy(sdcram_busy),
        .sdctrl_rdata(sdctrl_rdata),
        .sdctrl_busy (sdctrl_busy),
        .w_mc_addr   (interconn.w_mc_addr),
        .w_mc_wdata  (interconn.w_mc_wdata),
        .w_mode_is_mc(interconn.w_mode_is_mc),
        .w_mc_aces   (interconn.w_mc_aces),
        .w_mem_we    (interconn.w_mem_we)
    );

`ifdef SYNTHESIS
    wire [ 2:0] sdcram_state;
    wire [ 2:0] sdi_state;
    wire [ 5:0] sdc_state;
    sdcram#(
        .CACHE_DEPTH(2),
        .BLOCK_NUM(8),
        .POLLING_CYCLES(1024)
    )sdcram_0(
        .i_sys_clk(CORE_CLK),
        .i_sys_rst(!RST_X),
        .i_sd_clk(clk_50mhz),
        .i_sd_rst(!RST_X),

        // for user interface
        .i_sdcram_addr(sdcram_addr),
        .i_sdcram_ren(sdcram_ren),
        .i_sdcram_wen(sdcram_wen),
        .i_sdcram_wdata(sdcram_wdata),
        .o_sdcram_rdata(sdcram_rdata),
        .o_sdcram_busy(sdcram_busy),

        // for debug
        .sdcram_state(sdcram_state),
        .sdi_state(sdi_state),
        .sdc_state(sdc_state),

        // for sd
        .sd_cd(sd_cd),
        .sd_rst(sd_rst),
        .sd_sclk(sd_sclk),
        .sd_cmd(sd_cmd),
    	.sd_dat(sd_dat)
    );
`else
`ifdef SDCARD_SIM_CPP
    assign w_sdcram_addr  = sdcram_addr;
    assign w_sdcram_ren   = sdcram_ren;
    assign w_sdcram_wen   = sdcram_wen;
    assign w_sdcram_wdata = sdcram_wdata;
    assign sdcram_rdata   = w_sdcram_rdata;
`else
    sdcard_sim sdcard_sim0 (
        .w_CLK(CORE_CLK),
        .w_i_sys_rst(!RST_X),
        .w_i_sd_clk(), // not used in simulation
        .w_i_sd_rst(), // not used in simulation
        .w_i_sdcram_addr(sdcram_addr),
        .w_i_sdcram_ren(sdcram_ren),
        .w_i_sdcram_wen(sdcram_wen),
        .w_i_sdcram_wdata(sdcram_wdata),
        .w_o_sdcram_rdata(sdcram_rdata),
        .w_o_sdcram_busy(sdcram_busy),
        .w_sdcram_state(), // not used in simulation
        .w_sdi_state(), // not used in simulation
        .w_sdc_state(), // not used in simulation
        .w_sd_cd(), // not used in simulation
        .w_sd_rst(), // not used in simulation
        .w_sd_sclk(), // not used in simulation
        .w_sd_cmd(), // not used in simulation
        .w_sd_dat()// not used in simulation
    );
`endif
`endif

/*********** Chika Chika **************************/
    reg  r_led1_B=0,r_led1_G=0,r_led1_R=0;

    reg  [12:0] r_cnt_B=0, r_cnt_G=64, r_cnt_R=512;
    reg  [11:0] r_ctrl_cnt = 0;
    reg   [3:0] r_blite_cnt = 0;
    always@(posedge CLK) begin
        r_ctrl_cnt <= r_ctrl_cnt + 1;
        r_blite_cnt <= r_blite_cnt + 1;
        if(r_ctrl_cnt == 0) begin
            r_cnt_B <= r_cnt_B + 2;
            r_cnt_G <= r_cnt_G + 3;
            r_cnt_R <= r_cnt_R + 5;
        end
        r_led1_B <= r_cnt_B[12] ? (r_cnt_B[11:0] < r_ctrl_cnt) : (r_cnt_B[11:0] >= r_ctrl_cnt);
        r_led1_G <= r_cnt_G[12] ? (r_cnt_G[11:0] < r_ctrl_cnt) : (r_cnt_G[11:0] >= r_ctrl_cnt);
        r_led1_R <= r_cnt_R[12] ? (r_cnt_R[11:0] < r_ctrl_cnt) : (r_cnt_R[11:0] >= r_ctrl_cnt);
    end
    wire [2:0] t_led = {r_led1_B, r_led1_G, r_led1_R};
    // User blue, SuperVisor Green or Yellow, Machine, Error -> Red
    assign {w_led1_B,w_led1_G,w_led1_R} =   (w_led_t[3:0] == 4'b0001) ? {r_led1_B, r_led1_G, r_led1_R} :
                                            (!w_init_done) ? 0 :
                                            (r_blite_cnt != 0) ? 0 :
                                            (w_priv == `PRIV_U) ? 3'b001 :
                                            (w_priv == `PRIV_S) ? 3'b010 :
                                            (w_priv == `PRIV_M) ? 3'b100 : 0;

    /*********************************          PLIC          *********************************/
    wire w_plic_we;
    wire [31:0] w_plic_wdata;
    wire w_plic_re;
    wire [31:0] w_plic_rdata;
    wire [N_INT_SRC-1:0] w_int_src = {interconn.w_mouse_irq_oe,  // ID 5: mouse
                                      interconn.w_keybrd_irq_oe, // ID 4: keyboard
                                      interconn.w_ether_irq_oe,  // ID 3: ethernet
                                      interconn.w_disk_irq_oe,   // ID 2: disk
                                      interconn.w_uart_req};     // ID 1: console
    wire [N_HARTS-1:0] w_eip;
    wire [N_HARTS-1:0] w_meip = w_eip; // Fixme?
    wire [N_HARTS-1:0] w_seip = w_eip;
    
    plic #(
        .N_HARTS(N_HARTS),
        .N_INT_SRC(N_INT_SRC),
        .W_INT_PRIO(8)
    ) plic0 (
        .CLK(CORE_CLK),
        .RST_X(RST_X),
        .w_offset(w_offset),
        .w_we(w_plic_we),
        .w_wdata(w_plic_wdata),
        .w_re(w_plic_re),
        .w_rdata(w_plic_rdata),
        .w_int_src(w_int_src),
        .w_eip(w_eip)
    );

    generate
        if (DEBUG) begin
            ila_1 ila1 (
                .clk(CORE_CLK), // input wire clk
                .probe0(w_offset), // input wire [29:0]  probe0  
                .probe1(w_plic_we), // input wire [0:0]  probe1 
                .probe2(w_plic_wdata), // input wire [31:0]  probe2 
                .probe3(w_plic_re), // input wire [0:0]  probe3 
                .probe4(w_plic_rdata), // input wire [31:0]  probe4 
                .probe5(w_int_src), // input wire [4:0]  probe5 
                .probe6(w_eip), // input wire [0:0]  probe6
                .probe7(cluster.core0.ExMem_pc),
                .probe8(cluster.core0.ExMem_ir),
                .probe9(cluster.core0.mip),
                .probe10({11'b0, plic0.r_int_pending, 11'b0, plic0.r_int_pending_state}),
                .probe11(plic0.r_enable[0]),
                .probe12(plic0.r_threshold[0]),
                .probe13(plic0.w_max_prio[0])
            );
        end
    endgenerate

    /*********************************          CLINT         *********************************/
    wire w_clint_we;
    wire [31:0] w_clint_wdata;
    wire [31:0] w_clint_rdata;
    wire [N_HARTS-1:0] w_mtip;
    wire [N_HARTS-1:0] w_msip;
    wire [63:0] w_mtime;

    clint #(
        .N_HARTS(N_HARTS)
    ) clint0 (
        .CLK(CORE_CLK),
        .RST_X(RST_X),
        .w_offset(w_offset),
        .w_we(w_clint_we),
        .w_wdata(w_clint_wdata),
        .w_rdata(w_clint_rdata),
        .w_mtip(w_mtip),
        .w_msip(w_msip),
        .w_mtime(w_mtime)
    );

    generate
        if (DEBUG_CLINT) begin
`ifdef SYNTHESIS
            ila_clint ila_clint (
                .clk(CORE_CLK),             // input wire clk
                .probe0(w_offset),          // input wire [27:0]  probe0  
                .probe1(w_clint_we),        // input wire [0:0]  probe1 
                .probe2(w_clint_wdata),     // input wire [31:0]  probe2 
                .probe3(w_clint_rdata),     // input wire [31:0]  probe3 
                .probe4(w_mtip),            // input wire [0:0]  probe4 
                .probe5(w_msip),            // input wire [0:0]  probe5 
                .probe6(w_mtime)           // input wire [63:0]  probe6
            );
`endif
        end
    endgenerate
    
    /***********************************      Simple Framebuffer     ***********************************/
    wire w_fb_we;
    wire [31:0] w_fb_wdata;
    wire [31:0] w_fb_rdata;
`ifdef SYNTHESIS
    periph_framebuffer periph_framebuffer (
        .CLK(CORE_CLK),
        .pix_clk(pix_clk),
        .w_offset(w_offset),
        .w_we(w_fb_we),
        .w_wdata(w_fb_wdata),
        .w_rdata(w_fb_rdata),
        .vga_h_sync(vga_h_sync),
        .vga_v_sync(vga_v_sync),
        .vga_red(vga_red),
        .vga_blue(vga_blue),
        .vga_green(vga_green)
    );
`else
    assign w_fb_rdata = 32'h0;
    assign w_vga_we = w_fb_we;
    assign w_vga_waddr = {4'b0, w_offset};
    assign w_vga_wdata = w_fb_wdata;
`endif

    /***********************************      DRAM     ***********************************/
    wire         RST_X2;
    wire         w_dram_rd_en;
    wire         w_dram_wr_en;
    wire [31:0]  w_dram_addr;
    wire [31:0]  w_dram_wdata;
    wire [127:0] w_dram_rdata128;
    wire         w_dram_busy;
    wire [2:0]   w_dram_ctrl;
`ifdef SYNTHESIS
    wire calib_done;
    DRAM_conRV dram_con (
        // user interface ports
        .i_rd_en(w_dram_rd_en),
        .i_wr_en(w_dram_wr_en),
        .i_addr(w_dram_addr),
        .i_data(w_dram_wdata),
        .o_data(w_dram_rdata128),
        .o_busy(w_dram_busy),
        .i_ctrl(w_dram_ctrl),
        // input clk, rst (active-low)
        .mig_clk(mig_clk),
        .mig_rst_x(!RST),
        // memory interface ports
        .ddr2_dq(ddr2_dq),
        .ddr2_dqs_n(ddr2_dqs_n),
        .ddr2_dqs_p(ddr2_dqs_p),
        .ddr2_addr(ddr2_addr),
        .ddr2_ba(ddr2_ba),
        .ddr2_ras_n(ddr2_ras_n),
        .ddr2_cas_n(ddr2_cas_n),
        .ddr2_we_n(ddr2_we_n),
        .ddr2_ck_p(ddr2_ck_p),
        .ddr2_ck_n(ddr2_ck_n),
        .ddr2_cke(ddr2_cke),
        .ddr2_cs_n(ddr2_cs_n),
        .ddr2_dm(ddr2_dm),
        .ddr2_odt(ddr2_odt),
        // output clk, rst (active-low)
        .o_clk(CORE_CLK),
        .o_rst_x(RST_X2),
        // other
        .o_init_calib_complete(calib_done)
        );
`else
`ifdef DRAM_SIM_CPP
    assign CORE_CLK         = CLK;
    assign RST_X2           = 1'b1;
    assign dram_rd_en       = w_dram_rd_en;
    assign dram_wr_en       = w_dram_wr_en;
    assign dram_addr        = w_dram_addr;
    assign dram_wdata       = (w_dram_ctrl[1:0]==2'b00) ? {4{w_dram_wdata[7:0]}} :
                              (w_dram_ctrl[1:0]==2'b01) ? {2{w_dram_wdata[15:0]}} : w_dram_wdata;
    assign w_dram_rdata128  = dram_rdata128;
    assign w_dram_busy      = dram_busy;
    assign dram_ctrl        = w_dram_ctrl;
`else
    wire [31:0] w_dram_wdata_t = (w_dram_ctrl[1:0]==2'b00) ? {4{w_dram_wdata[7:0]}} :
                                 (w_dram_ctrl[1:0]==2'b01) ? {2{w_dram_wdata[15:0]}} : w_dram_wdata;
    wire [3:0] w_mask = (w_dram_ctrl[1:0] == 0) ? (4'b0001 << w_dram_addr[1:0]) :
                        (w_dram_ctrl[1:0] == 1) ? (4'b0011 << {w_dram_addr[1], 1'b0}) : 4'b1111;
    dram_sim dram_sim0 (
        .w_mig_clk(CLK),
        .w_mig_rst_n(),
        .w_CLK(CORE_CLK),
        .w_o_rst_n(RST_X2),
        .w_i_rd_en(w_dram_rd_en),
        .w_i_wr_en(w_dram_wr_en),
        .w_i_addr(w_dram_addr),
        .w_i_data(w_dram_wdata_t),
        .w_o_data3(w_dram_rdata128[127:96]),
        .w_o_data2(w_dram_rdata128[95:64]),
        .w_o_data1(w_dram_rdata128[63:32]),
        .w_o_data0(w_dram_rdata128[31:0]),
        .w_o_busy(w_dram_busy),
        .w_i_mask(~w_mask)
    );
`endif
`endif

endmodule

/**************************************************************************************************/
module m_7segled (w_in, r_led);
    input  wire [3:0] w_in;
    output reg  [7:0] r_led;
    always @(*) begin
        case (w_in)
        4'h0  : r_led <= 8'b01111110;
        4'h1  : r_led <= 8'b00110000;
        4'h2  : r_led <= 8'b01101101;
        4'h3  : r_led <= 8'b01111001;
        4'h4  : r_led <= 8'b00110011;
        4'h5  : r_led <= 8'b01011011;
        4'h6  : r_led <= 8'b01011111;
        4'h7  : r_led <= 8'b01110000;
        4'h8  : r_led <= 8'b01111111;
        4'h9  : r_led <= 8'b01111011;
        4'ha  : r_led <= 8'b01110111;
        4'hb  : r_led <= 8'b00011111;
        4'hc  : r_led <= 8'b01001110;
        4'hd  : r_led <= 8'b00111101;
        4'he  : r_led <= 8'b01001111;
        4'hf  : r_led <= 8'b01000111;
        default:r_led <= 8'b00000000;
        endcase
    end
endmodule

`define DELAY7SEG  16000 // 200000 for 100MHz, 100000 for 50MHz -> 16000 for 8MHz
/**************************************************************************************************/
module m_7segcon(w_clk, w_rst_x, w_load, w_din, r_sg, r_an);
    input  wire w_clk, w_rst_x, w_load;
    input  wire [31:0] w_din;
    output reg [7:0] r_sg;  // cathode segments
    output reg [7:0] r_an;  // common anode

    reg [31:0] r_val   = 0;
    reg [31:0] r_cnt   = 0;
    reg  [3:0] r_in    = 0;
    reg  [2:0] r_digit = 0;
    always@(posedge w_clk) r_val <= w_din;

    // For RVSoc_1
    `define r_7seg_A 8'b01110111
    `define r_7seg_r 8'b00000101
    `define r_7seg_c 8'b00001101
    `define r_7seg_h 8'b00010111
    `define r_7seg_P 8'b01100111
    `define r_7seg_o 8'b00011101

    // For Loading
    `define r_7seg_L 8'b00001110
    `define r_7seg_a 8'b01111101
    `define r_7seg_d 8'b00111101
    `define r_7seg_i 8'b00010000
    `define r_7seg_n 8'b00010101
    `define r_7seg_g 8'b11111011

    reg  [7:0] r_init   = 8'b00000000;
    reg  [7:0] r_load   = 8'b00000000;

    reg  [7:0] r_load_mem [0:15];
    integer i;
    initial begin
        r_load_mem[0] = 0;
        r_load_mem[1] = 0;
        r_load_mem[2] = 0;
        r_load_mem[3] = 0;
        r_load_mem[4] = 0;
        r_load_mem[5] = 0;
        r_load_mem[6] = 0;
        r_load_mem[7] = `r_7seg_L;
        r_load_mem[8] = `r_7seg_o;
        r_load_mem[9] = `r_7seg_a;
        r_load_mem[10] = `r_7seg_d;
        r_load_mem[11] = `r_7seg_i;
        r_load_mem[12] = `r_7seg_n;
        r_load_mem[13] = `r_7seg_g;
        r_load_mem[14] = 8'b10000000;
        r_load_mem[15] = 8'b10000000;
    end

//    reg[104:0] r_load_tmp = {49'b0, `r_7seg_L, `r_7seg_o, `r_7seg_a, `r_7seg_d, `r_7seg_i, `r_7seg_n, `r_7seg_g, 14'b0};
    reg [24:0] r_load_cnt = 0;
    reg  [3:0] r_lcnt = 0;
    always@(posedge w_clk) begin
        if(w_load) r_load_cnt <= r_load_cnt + 1;
        if(w_load && (r_load_cnt == 0)) r_lcnt <= r_lcnt + 1;//r_load_tmp <= r_load_tmp << 7;
    end

    always@(posedge w_clk) begin
        r_cnt <= (r_cnt>=(`DELAY7SEG-1)) ? 0 : r_cnt + 1;
        if(r_cnt==0) begin
        r_digit <= r_digit+ 1;
        if      (r_digit==0) begin r_an <= 8'b11111110; r_in <= r_val[3:0]  ; r_init = `r_7seg_c; r_load = r_load_mem[r_lcnt+7]; end
        else if (r_digit==1) begin r_an <= 8'b11111101; r_in <= r_val[7:4]  ; r_init = `r_7seg_o; r_load = r_load_mem[r_lcnt+6]; end
        else if (r_digit==2) begin r_an <= 8'b11111011; r_in <= r_val[11:8] ; r_init = `r_7seg_r; r_load = r_load_mem[r_lcnt+5]; end
        else if (r_digit==3) begin r_an <= 8'b11110111; r_in <= r_val[15:12]; r_init = `r_7seg_P; r_load = r_load_mem[r_lcnt+4]; end
        else if (r_digit==4) begin r_an <= 8'b11101111; r_in <= r_val[19:16]; r_init = `r_7seg_h; r_load = r_load_mem[r_lcnt+3]; end
        else if (r_digit==5) begin r_an <= 8'b11011111; r_in <= r_val[23:20]; r_init = `r_7seg_c; r_load = r_load_mem[r_lcnt+2]; end
        else if (r_digit==6) begin r_an <= 8'b10111111; r_in <= r_val[27:24]; r_init = `r_7seg_r; r_load = r_load_mem[r_lcnt+1]; end
        else                 begin r_an <= 8'b01111111; r_in <= r_val[31:28]; r_init = `r_7seg_A; r_load = r_load_mem[r_lcnt];   end
        end
    end
    wire [7:0] w_segments;
    m_7segled m_7segled (r_in, w_segments);
    always@(posedge w_clk) r_sg <= (w_load) ? ~r_load : (w_rst_x) ? ~w_segments : ~r_init;
endmodule
/**************************************************************************************************/

// A E F J L P U H Y O

// A r c h P r o c
