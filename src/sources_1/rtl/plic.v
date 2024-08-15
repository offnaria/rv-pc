module plic #(
    parameter N_HARTS = 1,    // Number of harts
    parameter N_INT_SRC = 32, // Number of interrupt sources
    parameter W_INT_PRIO = 4  // Width of interrupt priority
) (
    input  wire        CLK,
    input  wire        RST_X,
    input  wire [29:0] w_offset,
    input  wire        w_we,
    input  wire [31:0] w_wdata,
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
    reg [31:0] r_priority [0:N_INT_SRC-1];
endmodule