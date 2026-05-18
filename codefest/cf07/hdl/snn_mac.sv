`default_nettype none

// Module: snn_mac
// Description: Single multiply-accumulate unit for the SNN MAC array. Holds one
//              INT8 weight and accumulates (weight * activation) into an INT32
//              accumulator. When weight_load and act_valid are asserted on the
//              same cycle, weight_in is forwarded directly to the multiplier so
//              the new weight takes effect immediately (no stall needed).
//
// Ports:
//   Name          Dir    Width          Purpose
//   ---------------------------------------------------------------------------
//   clk           in     1              System clock (50 MHz, single domain)
//   rst           in     1              Synchronous active-high reset
//   weight_load   in     1              Strobe: latch weight_in into weight_reg;
//                                         also forwards weight_in to the
//                                         multiplier this cycle if act_valid set
//   weight_in     in     WEIGHT_W (8)   INT8 signed weight value to load
//   acc_clear     in     1              Strobe: reset accumulator to 0 (takes
//                                         priority over act_valid)
//   act_valid     in     1              Strobe: multiply-accumulate into acc_reg
//                                         this cycle
//   act_in        in     ACT_W (8)      INT8 signed activation (0x00 or 0x01
//                                         for spike inputs; general INT8 otherwise)
//   acc_out       out    ACC_W (32)     INT32 signed accumulated dot product

module snn_mac #(
    parameter int ACT_W    = 8,
    parameter int WEIGHT_W = 8,
    parameter int ACC_W    = 32
) (
    input  logic                        clk,
    input  logic                        rst,
    input  logic                        weight_load,
    input  logic signed [WEIGHT_W-1:0]  weight_in,
    input  logic                        acc_clear,
    input  logic                        act_valid,
    input  logic signed [ACT_W-1:0]     act_in,
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
                acc_reg <= acc_reg + ACC_W'(weight_mux * act_in);
        end
    end

    assign acc_out = acc_reg;

endmodule

`default_nettype wire
