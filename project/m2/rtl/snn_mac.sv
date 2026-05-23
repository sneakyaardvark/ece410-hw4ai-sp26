`default_nettype none

// Module: snn_mac
// Description: Single conditional-accumulate unit for the SNN accelerator.
//              Holds one INT8 weight and conditionally adds it to an INT32
//              accumulator when a binary spike input is high. Replaces the
//              INT8×INT8 multiplier with a mux+adder, avoiding DSP-slice
//              inference (and enabling 8–32× more units in the same area).
//              When weight_load and act_valid are asserted on the same cycle,
//              weight_in is forwarded directly so the new weight takes effect
//              immediately (no stall needed).
//
// Recurrence per active cycle:
//   new_acc = spike ? acc + weight : acc
//
// Ports:
//   Name          Dir    Width          Purpose
//   ---------------------------------------------------------------------------
//   clk           in     1              System clock (50 MHz, single domain)
//   rst           in     1              Synchronous active-high reset
//   weight_load   in     1              Strobe: latch weight_in into weight_reg;
//                                         also forwards weight_in to the adder
//                                         this cycle if act_valid set
//   weight_in     in     WEIGHT_W (8)   INT8 signed weight value to load
//   acc_clear     in     1              Strobe: reset accumulator to 0 (takes
//                                         priority over act_valid)
//   act_valid     in     1              Strobe: conditionally accumulate this cycle
//   act_in        in     1              Binary spike: 1 = add weight, 0 = no-op
//   acc_out       out    ACC_W (32)     INT32 signed accumulated dot product

module snn_mac #(
    parameter int WEIGHT_W = 8,
    parameter int ACC_W    = 32
) (
    input  logic                        clk,
    input  logic                        rst,
    input  logic                        weight_load,
    input  logic signed [WEIGHT_W-1:0]  weight_in,
    input  logic                        acc_clear,
    input  logic                        act_valid,
    input  logic                        act_in,
    output logic signed [ACC_W-1:0]     acc_out
);

    logic signed [WEIGHT_W-1:0] weight_reg;
    logic signed [WEIGHT_W-1:0] weight_mux;
    logic signed [ACC_W-1:0]    acc_reg;

    // Forward weight_in directly when loading so a simultaneous weight_load +
    // act_valid uses the new weight, not the stale registered value.
    assign weight_mux = weight_load ? weight_in : weight_reg;

    always_ff @(posedge clk) begin
        if (rst) begin
            weight_reg <= '0;
            acc_reg    <= '0;
        end else begin
            if (weight_load)
                weight_reg <= weight_in;
            if (acc_clear)
                acc_reg <= '0;
            else if (act_valid)
                acc_reg <= acc_reg + (act_in ? ACC_W'(weight_mux) : '0);
        end
    end

    assign acc_out = acc_reg;

endmodule

`default_nettype wire
