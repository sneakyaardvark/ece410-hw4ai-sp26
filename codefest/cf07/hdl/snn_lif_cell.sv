`default_nettype none

// Module: snn_lif_cell
// Description: Single leaky integrate-and-fire (LIF) neuron for the SNN
//              accelerator. Implements the recurrence:
//                new_syn  = (alpha * syn >> 15) + h1_in
//                spike    = (mem >= threshold)
//                new_mem  = spike ? 0 : (beta * mem >> 15) + syn
//              Alpha and beta are Q1.15 fixed-point decay constants (16-bit
//              unsigned, value = integer / 2^15). Syn and mem are INT32.
//              State updates on h1_valid; all other cycles hold state.
//              Single clock domain; synchronous active-high reset.
//
//              Note: two 32×16 multipliers are inferred per cell. For a
//              200-neuron bank this is 400 multipliers; if area is tight,
//              serialise the bank through a single LIF unit with SRAM state.
//
// Ports:
//   Name          Dir    Width          Purpose
//   ---------------------------------------------------------------------------
//   clk           in     1              System clock (50 MHz, single domain)
//   rst           in     1              Synchronous active-high reset; clears
//                                         syn, mem, spike_out to 0
//   alpha         in     DECAY_W (16)   Q1.15 synaptic decay constant
//                                         (e.g. exp(-dt/tau_syn) ≈ 0x4CCC)
//   beta          in     DECAY_W (16)   Q1.15 membrane decay constant
//                                         (e.g. exp(-dt/tau_mem) ≈ 0x7404)
//   threshold     in     STATE_W (32)   INT32 spike threshold; spike fires when
//                                         mem >= threshold
//   h1_in         in     ACC_W (32)     INT32 input current for this time step
//                                         (sum of weighted pre-synaptic spikes)
//   h1_valid      in     1              Strobe: update syn, mem, spike_out
//   spike_out     out    1              Registered spike output; high for one
//                                         cycle after h1_valid when mem fires

module snn_lif_cell #(
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
    input  logic                        h1_valid,
    output logic                        spike_out
);

    // 48-bit product is sufficient: max |alpha_int × syn| = 65535 × 2^31 < 2^47
    localparam int PROD_W = DECAY_W + STATE_W;  // 48

    logic signed [STATE_W-1:0] syn_reg, mem_reg;

    // Combinatorial update — all computed from registered (old) state
    logic signed [PROD_W-1:0] syn_product, mem_product;
    logic signed [STATE_W-1:0] syn_decayed, mem_decayed;
    logic signed [STATE_W-1:0] new_syn, new_mem;
    logic spike;

    // Q1.15 multiply: zero-extend alpha/beta (unsigned fraction), sign-extend state
    assign syn_product = $signed({1'b0, alpha}) * $signed(syn_reg);
    assign mem_product = $signed({1'b0, beta})  * $signed(mem_reg);

    // Arithmetic right-shift by 15 to recover INT32 result
    assign syn_decayed = STATE_W'(syn_product >>> 15);
    assign mem_decayed = STATE_W'(mem_product >>> 15);

    assign new_syn  = syn_decayed + STATE_W'(h1_in);
    assign spike    = (mem_reg >= threshold);
    // Soft reset: zero mem on spike; uses old syn_reg (before this step's update)
    assign new_mem  = spike ? '0 : (mem_decayed + syn_reg);

    always_ff @(posedge clk) begin
        if (rst) begin
            syn_reg   <= '0;
            mem_reg   <= '0;
            spike_out <= '0;
        end else if (h1_valid) begin
            syn_reg   <= new_syn;
            mem_reg   <= new_mem;
            spike_out <= spike;
        end
    end

endmodule

`default_nettype wire
