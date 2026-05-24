`default_nettype none

// Module: v1_sram_bank
// Description: One weight SRAM bank: DEPTH×8-bit words.
//
//   Simulation  (`ifndef SYNTHESIS): plain synchronous register file.
//               No sky130 dependency; same 1-cycle read latency as the macro path.
//
//   Synthesis   (`ifdef SYNTHESIS): five sky130_sram_1kbyte_1rw1r_8x1024_8 macros
//               tiled in depth to cover DEPTH=5000 words.
//               Address layout (13-bit):
//                 addr[12:10] → macro select (0..4)
//                 addr[9:0]   → macro-local word address (0..1023)
//               Write uses Port 0 (RW). Read uses Port 1 (R, always-enabled).
//
// Ports:
//   Name      Dir   Width   Purpose
//   -------------------------------------------------------------------------
//   clk       in    1       System clock (50 MHz)
//   wr_en     in    1       Pulse high to write one byte on the rising edge
//   wr_addr   in    13      Word address for write (0..DEPTH-1)
//   wr_data   in    8       Byte to write
//   rd_addr   in    13      Word address for read (0..DEPTH-1)
//   rd_data   out   8       Read byte, valid one cycle after rd_addr

module v1_sram_bank #(
    parameter int DEPTH       = 5000,
    parameter int MACRO_DEPTH = 1024
) (
    input  logic        clk,
    input  logic        wr_en,
    input  logic [12:0] wr_addr,
    input  logic [7:0]  wr_data,
    input  logic [12:0] rd_addr,
    output logic [7:0]  rd_data
);

`ifndef SYNTHESIS

    // -----------------------------------------------------------------------
    // Simulation path — register file, no sky130 dependency
    // -----------------------------------------------------------------------
    logic [7:0] mem [DEPTH];

    always_ff @(posedge clk) begin
        rd_data <= mem[rd_addr];   // read-first: sees value before this cycle's write
        if (wr_en)
            mem[wr_addr] <= wr_data;
    end

`else

    // -----------------------------------------------------------------------
    // Synthesis path — sky130_sram_1kbyte_1rw1r_8x1024_8 macros tiled in depth
    // -----------------------------------------------------------------------
    localparam int NB_MACROS = (DEPTH + MACRO_DEPTH - 1) / MACRO_DEPTH;  // 5

    logic [2:0] wr_sel;
    logic [9:0] wr_local;
    assign wr_sel   = wr_addr[12:10];
    assign wr_local = wr_addr[9:0];

    logic [9:0] rd_local;
    logic [2:0] rd_sel_r;
    assign rd_local = rd_addr[9:0];
    always_ff @(posedge clk)
        rd_sel_r <= rd_addr[12:10];

    logic [7:0] dout1 [NB_MACROS];

    genvar i;
    generate
        for (i = 0; i < NB_MACROS; i++) begin : gen_macro
            sky130_sram_1kbyte_1rw1r_8x1024_8 u_sram (
                .clk0   (clk),
                .csb0   (!(wr_en && wr_sel == 3'(i))),
                .web0   (1'b0),
                .wmask0 (1'b1),
                .addr0  (wr_local),
                .din0   (wr_data),
                /* verilator lint_off PINCONNECTEMPTY */
                .dout0  (),   // port 0 is write-only; output unused
                /* verilator lint_on PINCONNECTEMPTY */
                .clk1   (clk),
                .csb1   (1'b0),
                .addr1  (rd_local),
                .dout1  (dout1[i])
            );
        end
    endgenerate

    assign rd_data = dout1[rd_sel_r];

`endif

endmodule

`default_nettype wire
