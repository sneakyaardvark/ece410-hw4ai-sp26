`default_nettype none

// Module: snn_mac_array
// Description: 1×N array of snn_mac conditional-accumulate units for the SNN
//              accelerator. Computes N dot products in parallel by broadcasting
//              one binary spike to all units while presenting N INT8 weights
//              simultaneously (one per unit). Each unit adds its weight to its
//              accumulator only when the spike is high, replacing N multipliers
//              with N mux+adder cells (LUT logic, no DSP slices).
//              Single clock domain; synchronous active-high reset.
//
// Dataflow: each cycle with weight_load and act_valid both asserted, unit k
//           adds weight_in[k] to acc_out[k] if act_in=1, else holds. After
//           streaming all input spikes for one output tile, acc_out holds N
//           complete dot products. Assert acc_clear between tiles to reset.
//
// Ports:
//   Name          Dir    Width              Purpose
//   ---------------------------------------------------------------------------
//   clk           in     1                  System clock (50 MHz, single domain)
//   rst           in     1                  Synchronous active-high reset
//   weight_load   in     1                  Strobe: load weight_in[k] into unit k;
//                                             forwarded directly to adder this cycle
//                                             if act_valid also set
//   weight_in     in     N×WEIGHT_W (64)    N INT8 weights, one per unit; sourced
//                                             from a single 64-bit SRAM read
//   acc_clear     in     1                  Strobe: reset all accumulators to 0
//                                             (takes priority over act_valid)
//   act_valid     in     1                  Strobe: trigger conditional add in all units
//   act_in        in     1                  Binary spike broadcast to all units
//                                             (1 = add weight, 0 = no-op)
//   acc_out       out    N×ACC_W (256)      N INT32 accumulated dot products

module snn_mac_array #(
    parameter int N        = 8,
    parameter int WEIGHT_W = 8,
    parameter int ACC_W    = 32
) (
    input  logic                                    clk,
    input  logic                                    rst,
    input  logic                                    weight_load,
    input  logic signed [N-1:0][WEIGHT_W-1:0]      weight_in,
    input  logic                                    acc_clear,
    input  logic                                    act_valid,
    input  logic                                    act_in,
    output logic signed [N-1:0][ACC_W-1:0]         acc_out
);

    genvar k;
    generate
        for (k = 0; k < N; k++) begin : gen_mac
            snn_mac #(
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
