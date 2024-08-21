module plic #(
    parameter N_HARTS = 1,     // Number of harts
    parameter N_INT_SRC = 32,  // Number of interrupt sources
    parameter W_INT_PRIO = 32  // Width of interrupt priority
) (
    input  wire                 CLK,
    input  wire                 RST_X,
    input  wire [29:0]          w_offset,
    input  wire                 w_we,
    input  wire [31:0]          w_wdata,
    input  wire                 w_re,    // read enable for interrupt claim
    output wire [31:0]          w_rdata,
    input  wire [N_INT_SRC-1:0] w_int_src,
    output wire [N_HARTS-1:0]   w_eip
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
    0x00200008 +------------------------------+
               | ...                          |
    0x00201000 +------------------------------+
               | threshold for ctx1 [32]      |
    0x00201004 +------------------------------+
               | claim/complete for ctx1 [32] |
    0x00201008 +------------------------------+
               | ...                          |
               +------------------------------+
*/

    localparam W_INT_ID = $clog2(N_INT_SRC+1);

    reg [W_INT_PRIO-1:0] r_priority  [0:N_INT_SRC-1];
    reg [31:0]           w_pending   [0:(N_INT_SRC-1)/32]; // read only for MMIO
    reg [31:0]           r_enable    [0:((N_INT_SRC-1)/32+1)*N_HARTS-1];
    reg [W_INT_PRIO-1:0] r_threshold [0:N_HARTS-1];
    reg [31:0]           r_claim     [0:N_HARTS-1];

    integer i, j;
    initial begin
        for (i = 0; i < N_INT_SRC; i = i + 1) begin
            r_priority[i] = 0;
        end
        for (i = 0; i < ((N_INT_SRC-1)/32+1)*N_HARTS; i = i + 1) begin
            r_enable[i] = 0;
        end
        for (i = 0; i < N_HARTS; i = i + 1) begin
            r_threshold[i] = 0;
            r_claim[i]     = 0;
        end
    end

    always @(*) begin
        w_pending[0][0] = 1'b0; // NOTE: Interrupt ID 0 is reserved
        for (i = 1; i <= N_INT_SRC; i = i + 1) begin
            w_pending[i/32][i%32] = r_int_pending[i-1];
        end
    end

    // Write interface
    always @(posedge CLK) begin
        if (!RST_X) begin
            for (i = 0; i < N_INT_SRC; i = i + 1) begin
                r_priority[i] <= 0;
            end
            for (i = 0; i < ((N_INT_SRC-1)/32+1)*N_HARTS; i = i + 1) begin
                r_enable[i] <= 0;
            end
            for (i = 0; i < N_HARTS; i = i + 1) begin
                r_threshold[i] <= 0;
            end
        end else begin
            if (w_we) begin
                for (i = 1; i <= N_INT_SRC; i = i + 1) begin
                    if (w_offset==4*i) r_priority[i-1] <= w_wdata;
                end
                for (i = 0; i < N_HARTS; i = i + 1) begin
                    // TODO?: Interrupt ID 0 is reserved, shouldn't be enabled?
                    for (j = 0; j <= (N_INT_SRC-1)/32; j = j + 1) begin
                        if (w_offset==29'h2000+29'h80*i+4*j) r_enable[i*((N_INT_SRC-1)/32+1)+j] <= w_wdata;
                    end
                end
                for (i = 0; i < N_HARTS; i = i + 1) begin
                    if (w_offset==29'h200000+29'h1000*i) r_threshold[i] <= w_wdata;
                end
            end
        end
    end

    always @(posedge CLK) begin
        if (!RST_X) begin
            for (i = 0; i < N_HARTS; i = i + 1) begin
                r_claim[i] <= 32'd0;
            end
        end else begin
            if (w_we) begin
                for (i = 0; i < N_HARTS; i = i + 1) begin
                    if (w_offset==29'h200004+29'h1000*i) r_claim[i] <= w_wdata;
                end
            end else begin
                for (i = 0; i < N_HARTS; i = i + 1) begin
                    r_claim[i] <= w_max_id[i];
                end
            end
        end
    end

    // Read interface
    reg [31:0] r_rdata = 0;
    assign w_rdata = r_rdata;
    always @(posedge CLK) begin
        r_rdata = 0;
        // if (w_re) begin
            for (i = 1; i <= N_INT_SRC; i = i + 1) begin
                if (w_offset==4*i) r_rdata = r_priority[i-1];
            end
            for (i = 0; i <= (N_INT_SRC-1)/32; i = i + 1) begin
                if (w_offset==29'h1000+4*i) r_rdata = w_pending[i];
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
        // end
    end

    // Gateway
    reg [N_INT_SRC-1:0] r_int_pending = 0;
    reg [N_INT_SRC-1:0] r_int_pending_state = 0;
    localparam S_PEND_IDLE = 1'b0;
    localparam S_PEND_BUSY = 1'b1;
    always @(posedge CLK) begin
        if (!RST_X) begin
            r_int_pending       <= 0;
            r_int_pending_state <= 0;
        end else begin
            for (i = 0; i < N_INT_SRC; i = i + 1) begin
                r_int_pending[i]       <= (!r_int_pending[i]) ? (r_int_pending_state[i]==S_PEND_IDLE) && w_int_src[i]
                                        : (w_claimed[i]) ? 1'b0 // corresponding claim read
                                        : r_int_pending[i];
                r_int_pending_state[i] <= (r_int_pending_state[i]==S_PEND_IDLE) ? (!r_int_pending[i] && w_int_src)
                                        : (w_completed[i]) ? S_PEND_IDLE // corresponding claim write (completed)
                                        : r_int_pending_state[i];
            end
        end
    end

    reg [N_INT_SRC-1:0] w_claimed;
    always @(*) begin
        w_claimed = 0;
        for (i = 0; i < N_INT_SRC; i = i + 1) begin
            for (j = 0; j < N_HARTS; j = j + 1) begin
                w_claimed[i] = w_claimed[i] | ((w_offset==29'h200004+29'h1000*j) && (r_claim[j]==i+1)); // NOTE: Interrupt ID 0 is reserved
            end
            w_claimed[i] = w_re && w_claimed[i];
        end
    end

    reg [N_INT_SRC-1:0] w_completed;
    always @(*) begin
        w_completed = 0;
        for (i = 0; i < N_INT_SRC; i = i + 1) begin
            for (j = 0; j < N_HARTS; j = j + 1) begin
                w_completed[i] = w_completed[i] | ((w_offset==29'h200004+29'h1000*j) && (r_claim[j]==i+1)); // TODO: "If the completion ID does not match an interrupt source that is currently enabled for the target, the completion is silently ignored."
            end
            w_completed[i] = w_we && w_completed[i];
        end
    end

    // Core
    reg [W_INT_PRIO-1:0] w_int_prio [0:N_INT_SRC-1];
    reg [W_INT_PRIO-1:0] w_max_prio [0:N_HARTS-1];
    reg [W_INT_ID-1:0]   w_max_id   [0:N_HARTS-1];
    reg [N_HARTS-1:0]    r_eip = 0;

    always @(*) begin
        for (i = 0; i < N_INT_SRC; i = i + 1) begin
            w_int_prio[i] = (r_int_pending[i]) ? r_priority[i] : 0;
        end
    end

    always @(*) begin
        for (i = 0; i < N_HARTS; i = i + 1) begin
            w_max_prio[i] = 0;
            w_max_id[i]   = 0;
        end
        for (i = 0; i < N_HARTS; i = i + 1) begin
            for (j = 1; j <= N_INT_SRC; j = j + 1) begin
                if (r_enable[((N_INT_SRC-1)/32+1)*i+j/32][j%32]) begin
                    if (w_int_prio[j-1] > w_max_prio[i]) begin
                        w_max_prio[i] = w_int_prio[j-1];
                        w_max_id[i]   = j;
                    end else if (w_int_prio[j-1] == w_max_prio[i]) begin
                        if (j < w_max_id[i]) w_max_id[i] = j;
                    end
                end
            end
        end
    end

    always @(posedge CLK) begin
        if (!RST_X) begin
            r_eip <= 0;
        end else begin
            for (i = 0; i < N_HARTS; i = i + 1) begin
                r_eip[i] <= (w_max_prio[i] > r_threshold[i]);
            end
        end
    end

    genvar g;
    generate
        for (g = 0; g < N_HARTS; g = g + 1) begin
            assign w_eip[g] = r_eip[g];
        end
    endgenerate

endmodule