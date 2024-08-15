module plic #(
    parameter N_HARTS = 1,     // Number of harts
    parameter N_INT_SRC = 32,  // Number of interrupt sources
    parameter W_INT_PRIO = 32  // Width of interrupt priority
) (
    input  wire        CLK,
    input  wire        RST_X,
    input  wire [29:0] w_offset,
    input  wire        w_we,
    input  wire [31:0] w_wdata,
    input  wire        w_re,    // read enable for interrupt claim
    output wire [31:0] w_rdata,
    
);
/*  Base address: 0x50000000
    Offset
    0x00000000 +------------------------------+
               | Reserved                     |
    0x00000004 +------------------------------+
               | priority1[32]                |
    0x00000008 +------------------------------+
               | priority2[32]                |
    0x0000000C +------------------------------+
               | ...                          |
    0x00001000 +------------------------------+
               | pending #0 to #31[32]        |
    0x00001004 +------------------------------+
               | pending #32 to #63[32]       |
    0x00001008 +------------------------------+
               | ...                          |
    0x00002000 +------------------------------+
               | enable 0-31 on ctx0[32]      |
    0x00002004 +------------------------------+
               | ...                          |
    0x00002080 +------------------------------+
               | enable 0-31 on ctx1[32]      |
    0x00002084 +------------------------------+
               | ...                          |
    0x00200000 +------------------------------+
               | threshold for ctx0 [32]      |
    0x00200004 +------------------------------+
               | claim/complete for ctx0 [32] |
               +------------------------------+
               | ...                          |
    0x00201000 +------------------------------+
               | threshold for ctx1 [32]      |
    0x00201004 +------------------------------+
               | claim/complete for ctx1 [32] |
               +------------------------------+
               | ...                          |
               +------------------------------+
*/

    reg [W_INT_PRIO-1:0] r_priority [0:N_INT_SRC-1];
    reg [31:0] r_pending [0:(N_INT_SRC-1)/32]; // read only for MMIO
    reg [31:0] r_enable [0:((N_INT_SRC-1)/32+1)*N_HARTS-1];
    reg [31:0] r_threshold [0:N_HARTS-1];
    reg [31:0] r_claim [0:N_HARTS-1];

    integer i, j;
    initial begin
        for (i = 0; i < N_INT_SRC; i = i + 1) begin
            r_priority[i] = W_INT_PRIO'd0;
        end
        for (i = 0; i <= (N_INT_SRC-1)/32; i = i + 1) begin
            r_pending[i] = 32'd0;
        end
        for (i = 0; i < ((N_INT_SRC-1)/32+1)*N_HARTS; i = i + 1) begin
            r_enable[i] = 32'd0;
        end
        for (i = 0; i < N_HARTS; i = i + 1) begin
            r_threshold[i] = 32'd0;
            r_claim[i]     = 32'd0;
        end
    end

    // Write interface
    always @(posedge CLK) begin
        if (!RST_X) begin
            for (i = 0; i < N_INT_SRC; i = i + 1) begin
                r_priority[i] <= W_INT_PRIO'd0;
            end
            for (i = 0; i < ((N_INT_SRC-1)/32+1)*N_HARTS; i = i + 1) begin
                r_enable[i] <= 32'd0;
            end
            for (i = 0; i < N_HARTS; i = i + 1) begin
                r_threshold[i] <= 32'd0;
                r_claim[i]     <= 32'd0;
            end
        end else begin
            if (w_we) begin
                for (i = 0; i < N_INT_SRC; i = i + 1) begin
                    if (w_offset==4*(i+1)) r_priority[i] <= w_wdata;
                end
                for (i = 0; i < N_HARTS; i = i + 1) begin
                    // TODO?: Interrupt ID 0 is reserved, shouldn't be enabled?
                    for (j = 0; j <= (N_INT_SRC-1)/32; j = j + 1) begin
                        if (w_offset==29'h2000+29'h80*i+4*j) r_enable[i*((N_INT_SRC-1)/32+1)+j] <= w_wdata;
                    end
                end
                for (i = 0; i < N_HARTS; i = i + 1) begin
                    if (w_offset==29'h200000+29'h1000*i) r_threshold[i] <= w_wdata;
                    if (w_offset==29'h200004+29'h1000*i) r_claim[i]     <= w_wdata;
                end
            end
        end
    end

    // Read interface
    reg [31:0] r_rdata = 0;
    assign w_rdata = r_rdata;
    always @(posedge CLK) begin
        r_rdata = 0;
        if (w_re) begin
            for (i = 0; i < N_INT_SRC; i = i + 1) begin
                if (w_offset==4*(i+1)) r_rdata = r_priority[i];
            end
            for (i = 0; i <= (N_INT_SRC-1)/32; i = i + 1) begin
                if (w_offset==29'h1000+4*i) r_rdata = r_pending[i];
            end
            for (i = 0; i < N_HARTS; i = i + 1) begin
                for (j = 0; j <= (N_INT_SRC-1)/32; j = j + 1) begin
                    if (w_offset==29'h2000+29'h80*i+4*j) r_rdata = r_enable[i*((N_INT_SRC-1)/32+1)+j];
                end
            end
            for (i = 0; i < N_HARTS; i = i + 1) begin
                if (w_offset==29'h200000+29'h1000*i) r_rdata = r_threshold[i];
                if (w_offset==29'h200004+29'h1000*i) r_rdata = r_claim[i];
            end
        end
    end
endmodule