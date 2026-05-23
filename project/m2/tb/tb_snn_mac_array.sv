`default_nettype none

// Module: tb_snn_mac_array
// Description: Thin simulation wrapper for snn_mac_array. Exposes all DUT ports
//              as top-level signals so cocotb can drive and sample them directly.
//
// Ports:
//   Name          Dir    Width    Purpose
//   -----------------------------------------------------------------------
//   clk           in     1        Clock driven by cocotb
//   rst           in     1        Synchronous reset driven by cocotb
//   weight_load   in     1        Forwarded to DUT weight_load
//   weight_in     in     64       8× INT8 weights, one per MAC unit
//   acc_clear     in     1        Forwarded to DUT acc_clear
//   act_valid     in     1        Forwarded to DUT act_valid
//   act_in        in     1        Binary spike broadcast to all MAC units
//   acc_out       out    256      8× INT32 accumulated dot products

module tb_snn_mac_array (
    input  logic                clk,
    input  logic                rst,
    input  logic                weight_load,
    input  logic [63:0]         weight_in,
    input  logic                acc_clear,
    input  logic                act_valid,
    input  logic                act_in,
    output logic [255:0]        acc_out
);

    snn_mac_array #(
        .N        (8),
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
