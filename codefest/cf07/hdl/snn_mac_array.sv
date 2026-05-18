`default_nettype none

// Module: snn_mac_array
// Description: 1×N array of snn_mac units for the SNN accelerator. Computes N
//              dot products in parallel by broadcasting one activation to all
//              units while presenting N weights simultaneously (one per unit).
//              Used for tiled matrix-vector multiplication of v1 (200×200
//              recurrent), w1 (700×200 input projection), and w2 (200×20 output
//              projection). Single clock domain; synchronous active-high reset.
//
// Dataflow: each cycle with weight_load and act_valid both asserted, unit k
//           accumulates weight_in[k] * act_in into acc_out[k]. After streaming
//           all input activations for one output tile, acc_out holds N complete
//           dot products. Assert acc_clear between tiles to reset accumulators.
//
// Ports:
//   Name          Dir    Width              Purpose
//   ---------------------------------------------------------------------------
//   clk           in     1                  System clock (50 MHz, single domain)
//   rst           in     1                  Synchronous active-high reset
//   weight_load   in     1                  Strobe: load weight_in[k] into unit k;
//                                             forwarded directly to multiplier
//                                             this cycle if act_valid also set
//   weight_in     in     N×WEIGHT_W (64)    N INT8 weights, one per unit; sourced
//                                             from a single 64-bit SRAM read
//   acc_clear     in     1                  Strobe: reset all accumulators to 0
//                                             (takes priority over act_valid)
//   act_valid     in     1                  Strobe: trigger MAC in all units
//   act_in        in     ACT_W (8)          INT8 signed activation broadcast to
//                                             all units (0x00/0x01 for spikes)
//   acc_out       out    N×ACC_W (256)      N INT32 accumulated dot products

module snn_mac_array #(
    parameter int N         = 8,
    parameter int ACT_W     = 8,
    parameter int WEIGHT_W  = 8,
    parameter int ACC_W     = 32
) (
    input  logic                                    clk,
    input  logic                                    rst,
    input  logic                                    weight_load,
    input  logic signed [N-1:0][WEIGHT_W-1:0]      weight_in,
    input  logic                                    acc_clear,
    input  logic                                    act_valid,
    input  logic signed [ACT_W-1:0]                act_in,
    output logic signed [N-1:0][ACC_W-1:0]         acc_out
);

    genvar k;
    generate
        for (k = 0; k < N; k++) begin : gen_mac
            snn_mac #(
                .ACT_W    (ACT_W),
                .WEIGHT_W (WEIGHT_W),
                .ACC_W    (ACC_W)
            ) mac_inst (
                .clk         (clk),
                .rst         (rst),
                .weight_load (weight_load),
                .weight_in   (weight_in[k]),
                .acc_clear   (acc_clear),
                .act_valid   (act_valid),
                .act_in      (act_in),
                .acc_out     (acc_out[k])
            );
        end
    endgenerate

endmodule

`default_nettype wire
