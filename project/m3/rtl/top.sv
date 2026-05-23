`default_nettype none

// Module: top
// Description: Integrated SNN accelerator top level. Connects spi_interface
//              (SPI Mode 0 slave, register-map decoder) to compute_core
//              (event-driven LIF datapath). All clock-domain crossing is
//              handled inside spi_interface via its 2-stage synchronizer.
//
// Ports:
//   Name             Dir    Width              Purpose
//   ---------------------------------------------------------------------------
//   clk              in     1                  System clock (50 MHz)
//   rst              in     1                  Synchronous active-high reset
//   sck              in     1                  SPI clock from host (Mode 0)
//   cs_n             in     1                  SPI chip select, active-low
//   mosi             in     1                  Host-to-slave serial data
//   miso             out    1                  Slave-to-host serial data
//   busy             out    1                  High while inference is running
//   done             out    1                  High for one cycle when complete

module top #(
    parameter int NB_HIDDEN   = 200,
    parameter int NB_MACS     = 8,
    parameter int NB_STEPS    = 100,
    parameter int STATE_W     = 32,
    parameter int DECAY_W     = 16,
    parameter int WEIGHT_W    = 8,
    parameter int ACC_W       = 32,
    parameter int ALPHA_INIT  = 19875,
    parameter int BETA_INIT   = 29635,
    parameter int THRESH_INIT = 32768
) (
    input  logic clk,
    input  logic rst,

    // SPI slave port
    input  logic sck,
    input  logic cs_n,
    input  logic mosi,
    output logic miso,

    // Inference status (mirrors internal signals for monitoring)
    output logic busy,
    output logic done
);

    // -------------------------------------------------------------------------
    // Internal wires between spi_interface and compute_core
    // -------------------------------------------------------------------------
    logic                        weight_wr_en;
    logic [15:0]                 weight_wr_addr;
    logic [7:0]                  weight_wr_data;
    logic [DECAY_W-1:0]          alpha;
    logic [DECAY_W-1:0]          beta;
    logic signed [STATE_W-1:0]   threshold;
    logic                        start;
    logic [NB_HIDDEN-1:0]        spike_in;
    logic [NB_HIDDEN-1:0]        spike_out;

    // -------------------------------------------------------------------------
    // SPI slave / register-map decoder
    // -------------------------------------------------------------------------
    spi_interface #(
        .NB_HIDDEN   (NB_HIDDEN),
        .STATE_W     (STATE_W),
        .DECAY_W     (DECAY_W),
        .ALPHA_INIT  (ALPHA_INIT),
        .BETA_INIT   (BETA_INIT),
        .THRESH_INIT (THRESH_INIT)
    ) u_spi (
        .clk            (clk),
        .rst            (rst),
        .sck            (sck),
        .cs_n           (cs_n),
        .mosi           (mosi),
        .miso           (miso),
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

    // -------------------------------------------------------------------------
    // Event-driven SNN compute datapath
    // -------------------------------------------------------------------------
    compute_core #(
        .NB_HIDDEN (NB_HIDDEN),
        .NB_MACS   (NB_MACS),
        .NB_STEPS  (NB_STEPS),
        .STATE_W   (STATE_W),
        .DECAY_W   (DECAY_W),
        .WEIGHT_W  (WEIGHT_W),
        .ACC_W     (ACC_W)
    ) u_core (
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
