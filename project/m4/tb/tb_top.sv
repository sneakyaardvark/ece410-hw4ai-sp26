`default_nettype none

// Module: tb_top
// Description: Thin cocotb wrapper for the integrated top module. Uses the
//              full NB_HIDDEN=200, NB_MACS=8 network from M1 profiling.
//              NB_STEPS=5 is reduced from the 100-step production value to
//              keep co-simulation time manageable while exercising the full
//              200×200 recurrent weight matrix. The SPI port is exposed at
//              the top level so cocotb can drive bit-bang transactions directly.
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

module tb_top (
    input  logic clk,
    input  logic rst,
    input  logic sck,
    input  logic cs_n,
    input  logic mosi,
    output logic miso,
    output logic busy,
    output logic done
);

    top #(
        .NB_HIDDEN (200),
        .NB_MACS   (8),
        .NB_STEPS  (5)
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
