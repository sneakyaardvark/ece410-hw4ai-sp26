// Minimal port-only stub for sky130_sram_1kbyte_1rw1r_8x1024_8.
// Used as VERILOG_FILES_BLACKBOX so Verilator can resolve the module name
// and Yosys treats it as a hard macro with no internals to synthesize.
// Timing and area come from the LIB/LEF in EXTRA_LIBS / EXTRA_LEFS.
module sky130_sram_1kbyte_1rw1r_8x1024_8 (
    input  clk0,
    input  csb0,
    input  web0,
    input  wmask0,
    input  [9:0] addr0,
    input  [7:0] din0,
    output [7:0] dout0,
    input  clk1,
    input  csb1,
    input  [9:0] addr1,
    output [7:0] dout1
);
endmodule
