`default_nettype none

// Module: tb_bench
// Description: Benchmark wrapper that exposes compute_core directly (no SPI),
//              so cocotb can load weights through the weight_wr port and
//              measure the start->done compute latency in clock cycles for the
//              full production configuration (NB_HIDDEN=200, NB_STEPS=100).
//
// Ports:
//   Name             Dir    Width              Purpose
//   ---------------------------------------------------------------------------
//   clk              in     1                  Core clock driven by cocotb
//   rst              in     1                  Synchronous active-high reset
//   weight_wr_en     in     1                  Write one byte of v1 weight SRAM
//   weight_wr_addr   in     16                 Byte address in v1 SRAM
//   weight_wr_data   in     8                  INT8 weight byte to write
//   alpha            in     16                 Q1.15 synaptic decay constant
//   beta             in     16                 Q1.15 membrane decay constant
//   threshold        in     32                 INT32 LIF spike threshold
//   start            in     1                  Pulse to begin inference
//   spike_in         in     200                Initial hidden spike vector
//   busy             out    1                  High while inference is running
//   done             out    1                  High for one cycle when complete
//   spike_out        out    200                Final hidden spike vector

module tb_bench (
    input  logic                 clk,
    input  logic                 rst,
    input  logic                 weight_wr_en,
    input  logic [15:0]          weight_wr_addr,
    input  logic [7:0]           weight_wr_data,
    input  logic [15:0]          alpha,
    input  logic [15:0]          beta,
    input  logic signed [31:0]   threshold,
    input  logic                 start,
    input  logic [199:0]         spike_in,
    output logic                 busy,
    output logic                 done,
    output logic [199:0]         spike_out
);

    compute_core #(
        .NB_HIDDEN (200),
        .NB_MACS   (8),
        .NB_STEPS  (100)
    ) dut (
        .clk            (clk),
        .rst            (rst),
        .weight_wr_en   (weight_wr_en),
        .weight_wr_addr (weight_wr_addr),
        .weight_wr_data (weight_wr_data),
        .alpha          (alpha),
        .beta           (beta),
        .threshold      (threshold),
        .start          (start),
        .spike_in       (spike_in),
        .busy           (busy),
        .done           (done),
        .spike_out      (spike_out)
    );

endmodule

`default_nettype wire
