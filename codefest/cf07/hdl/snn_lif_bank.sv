`default_nettype none

// Module: snn_lif_bank
// Description: Bank of NB snn_lif_cell instances for the SNN accelerator.
//              Cells are updated serially: each cycle the controller presents
//              one (h1_in, h1_idx) pair and asserts h1_valid; only the cell
//              at index h1_idx processes the update. All cells share the same
//              alpha, beta, and threshold. spike_vec reflects each cell's
//              registered spike_out and is valid one cycle after the cell's
//              h1_valid pulse. Single clock domain; synchronous active-high reset.
//
//              Area note: NB=200 instances each infer two 32×16 multipliers.
//              If area is constrained, replace with a single LIF unit and
//              SRAM-backed state (serialised over NB cycles per time step).
//
// Ports:
//   Name          Dir    Width              Purpose
//   ---------------------------------------------------------------------------
//   clk           in     1                  System clock (50 MHz, single domain)
//   rst           in     1                  Synchronous active-high reset;
//                                             clears all cell state and spike_vec
//   alpha         in     DECAY_W (16)       Q1.15 synaptic decay, broadcast to
//                                             all cells
//   beta          in     DECAY_W (16)       Q1.15 membrane decay, broadcast to
//                                             all cells
//   threshold     in     STATE_W (32)       INT32 spike threshold, broadcast to
//                                             all cells
//   h1_in         in     ACC_W (32)         INT32 input current for selected cell
//   h1_idx        in     $clog2(NB) (8)     Index of cell to update this cycle
//   h1_valid      in     1                  Strobe: update cell h1_idx with h1_in
//   spike_vec     out    NB (200)           One spike bit per cell; each bit is
//                                             the registered spike_out of that cell

module snn_lif_bank #(
    parameter int NB      = 200,
    parameter int STATE_W = 32,
    parameter int DECAY_W = 16,
    parameter int ACC_W   = 32
) (
    input  logic                        clk,
    input  logic                        rst,
    input  logic [DECAY_W-1:0]          alpha,
    input  logic [DECAY_W-1:0]          beta,
    input  logic signed [STATE_W-1:0]   threshold,
    input  logic signed [ACC_W-1:0]     h1_in,
    input  logic [$clog2(NB)-1:0]       h1_idx,
    input  logic                        h1_valid,
    output logic [NB-1:0]               spike_vec
);

    genvar k;
    generate
        for (k = 0; k < NB; k++) begin : gen_cell
            snn_lif_cell #(
                .STATE_W (STATE_W),
                .DECAY_W (DECAY_W),
                .ACC_W   (ACC_W)
            ) cell_inst (
                .clk       (clk),
                .rst       (rst),
                .alpha     (alpha),
                .beta      (beta),
                .threshold (threshold),
                .h1_in     (h1_in),
                .h1_valid  (h1_valid && (h1_idx == $clog2(NB)'(k))),
                .spike_out (spike_vec[k])
            );
        end
    endgenerate

endmodule

`default_nettype wire
