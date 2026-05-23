`default_nettype none

// Module: tb_top_wave
// Description: Minimal waveform-capture wrapper for top. Uses NB_HIDDEN=8,
//              NB_STEPS=2 so the full SPI-write → compute → SPI-read cycle
//              completes in seconds and produces a manageable VCD file.
//              NB_MACS=8 matches NB_HIDDEN so there is exactly 1 MAC tile.
//
// Ports:
//   Name     Dir    Width   Purpose
//   -----------------------------------------------------------------------
//   clk      in     1       Core clock driven by cocotb
//   rst      in     1       Synchronous active-high reset driven by cocotb
//   sck      in     1       SPI clock (bit-banged by cocotb)
//   cs_n     in     1       SPI chip select, active-low
//   mosi     in     1       Host-to-slave serial data
//   miso     out    1       Slave-to-host serial data
//   busy     out    1       High while inference is running
//   done     out    1       High for one cycle when complete

module tb_top_wave (
    input  logic clk,
    input  logic rst,
    input  logic sck,
    input  logic cs_n,
    input  logic mosi,
    output logic miso,
    output logic busy,
    output logic done
);

    initial begin
        $dumpfile("tb_top_wave.vcd");
        $dumpvars(0, tb_top_wave);
    end

    top #(
        .NB_HIDDEN (8),
        .NB_MACS   (8),
        .NB_STEPS  (2)
    ) dut (
        .clk  (clk),
        .rst  (rst),
        .sck  (sck),
        .cs_n (cs_n),
        .mosi (mosi),
        .miso (miso),
        .busy (busy),
        .done (done)
    );

endmodule

`default_nettype wire
