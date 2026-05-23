`default_nettype none

// Module: tb_snn_mac
// Description: Thin simulation wrapper for snn_mac. Exposes all DUT ports as
//              top-level signals so cocotb can drive and sample them directly.
//
// Ports:
//   Name          Dir    Width   Purpose
//   -----------------------------------------------------------------------
//   clk           in     1       Clock driven by cocotb
//   rst           in     1       Synchronous reset driven by cocotb
//   weight_load   in     1       Forwarded to DUT weight_load
//   weight_in     in     8       Forwarded to DUT weight_in
//   acc_clear     in     1       Forwarded to DUT acc_clear
//   act_valid     in     1       Forwarded to DUT act_valid
//   act_in        in     1       Binary spike forwarded to DUT act_in
//   acc_out       out    32      Forwarded from DUT acc_out

module tb_snn_mac (
    input  logic                clk,
    input  logic                rst,
    input  logic                weight_load,
    input  logic signed [7:0]   weight_in,
    input  logic                acc_clear,
    input  logic                act_valid,
    input  logic                act_in,
    output logic signed [31:0]  acc_out
);

    snn_mac #(
        .WEIGHT_W (8),
        .ACC_W    (32)
    ) dut (
        .clk         (clk),
        .rst         (rst),
        .weight_load (weight_load),
        .weight_in   (weight_in),
        .acc_clear   (acc_clear),
        .act_valid   (act_valid),
        .act_in      (act_in),
        .acc_out     (acc_out)
    );

endmodule

`default_nettype wire
