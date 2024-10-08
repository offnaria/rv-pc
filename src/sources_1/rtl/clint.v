module clint #(
    parameter N_HARTS = 1
)
(
    input  wire        CLK,
    input  wire        RST_X,
    input  wire [15:0] w_offset,
    input  wire        w_we,
    input  wire [31:0] w_wdata,
    output wire [31:0] w_rdata,
    output wire [N_HARTS-1:0] w_mtip,
    output wire [N_HARTS-1:0] w_msip,
    output wire [63:0] w_mtime
);
/*  Base address: 0x60000000
    Offset
    0x00000000 +------------------------+
               | msip0[32]              |
    0x00000004 +------------------------+
               | msip1[32]              |
    0x00000008 +------------------------+
               | ...                    |
    0x00004000 +------------------------+
               | mtimecmp0[64]          |
    0x00004008 +------------------------+
               | mtimecmp1[64]          |
    0x00004010 +------------------------+
               | ...                    |
    0x0000BFF8 +------------------------+
               | mtime[64]              |
               +------------------------+
*/

    reg [31:0] r_msip     [0:N_HARTS-1];
    reg [63:0] r_mtimecmp [0:N_HARTS-1];
    integer i;
    initial begin
        for (i = 0; i < N_HARTS; i = i + 1) begin
            r_msip[i]     = 32'd0;
            r_mtimecmp[i] = 64'd0;
        end
    end
    reg [63:0] r_mtime = 64'd0;
    assign w_mtime = r_mtime;

    always @(posedge CLK) begin
        if (!RST_X) begin
            r_mtime <= 64'd0;
            for (i = 0; i < N_HARTS; i = i + 1) begin
                r_msip[i]     <= 32'd0;
                r_mtimecmp[i] <= 64'd0;
            end
        end else begin
            if (w_we) begin
                if (w_offset==16'hBFF8) begin
                    r_mtime[31:0] <= w_wdata;
                end else if (w_offset==16'hBFFC) begin
                    r_mtime[63:32] <= w_wdata;
                end
                for (i = 0; i < N_HARTS; i = i + 1) begin
                    if (w_offset==4*i) r_msip[i][0] <= w_wdata[0];
                    if (w_offset==16'h4000+8*i) r_mtimecmp[i][31:0] <= w_wdata;
                    if (w_offset==16'h4004+8*i) r_mtimecmp[i][63:32] <= w_wdata;
                end
            end
            r_mtime <= r_mtime + 64'd1;
        end
    end

    genvar j;
    generate
        for (j = 0; j < N_HARTS; j = j + 1) begin
            assign w_mtip[j] = (r_mtime >= r_mtimecmp[j]);
            assign w_msip[j] = r_msip[j][0];
        end
    endgenerate

    reg [31:0] r_rdata = 0;
    assign w_rdata = r_rdata;
    always @(posedge CLK) begin
        r_rdata = 0;
        if (w_offset==16'hBFF8) begin
            r_rdata = r_mtime[31:0];
        end else if (w_offset==16'hBFFC) begin
            r_rdata = r_mtime[63:32];
        end
        for (i = 0; i < N_HARTS; i = i + 1) begin
            if (w_offset==4*i) r_rdata = r_msip[i];
            if (w_offset==16'h4000+8*i) r_rdata = r_mtimecmp[i][31:0];
            if (w_offset==16'h4004+8*i) r_rdata = r_mtimecmp[i][63:32];
        end
        if (!RST_X) r_rdata = 0;
    end
endmodule