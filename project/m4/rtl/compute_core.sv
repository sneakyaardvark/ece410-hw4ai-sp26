`default_nettype none

// Module: compute_core
// Description: Top-level SNN compute datapath. Event-driven implementation:
//              maintains an active-spike index list (act_list) and visits only
//              the neurons that fired in the previous step, so MAC work scales
//              with spike sparsity rather than network size.
//
//              Weight matrix v1 (200×200 INT8) is stored in eight byte-wide SRAM
//              banks (one per MAC unit), each 5000 × 8-bit = 40 Kbit, inferred
//              as block RAM. Per-bank write enables make byte-granular loading
//              trivial. The read port is synchronous (1-cycle latency); the FSM
//              adds one S_TILE_PRE prefetch cycle per tile to absorb it, with a
//              look-ahead address (act_ptr+1) keeping the pipeline full during
//              S_TILE_EXEC.
//
//              Per time step:
//                1. S_INIT_COLLECT (step 0): scan spike_in to build act_list.
//                2. For each tile: S_TILE_PRE (prefetch) → S_TILE_EXEC (stream
//                   act_list rows) → S_TILE_DRAIN (capture 8 results).
//                3. S_LIF_UPDATE: update all 200 LIF neurons serially; collect
//                   next step's act_list in the same 200 cycles (neurons 0..198).
//                4. S_STEP_DONE: collect neuron 199, advance step counter.
//
//              Single clock domain; synchronous active-high reset.
//
// Ports:
//   Name             Dir    Width              Purpose
//   ---------------------------------------------------------------------------
//   clk              in     1                  System clock (50 MHz)
//   rst              in     1                  Synchronous active-high reset
//   weight_wr_en     in     1                  Write one byte of v1 weight SRAM
//   weight_wr_addr   in     16                 Byte address in v1 SRAM
//                                               bits [15:3] = word addr (0..4999)
//                                               bits [2:0]  = MAC bank (0..7)
//   weight_wr_data   in     8                  INT8 weight byte to write
//   alpha            in     DECAY_W (16)       Q1.15 synaptic decay constant
//   beta             in     DECAY_W (16)       Q1.15 membrane decay constant
//   threshold        in     STATE_W (32)       INT32 LIF spike threshold
//   start            in     1                  Pulse to begin inference; latches
//                                               spike_in and resets all counters
//   spike_in         in     NB_HIDDEN (200)    Initial hidden spike vector
//   busy             out    1                  High while inference is running
//   done             out    1                  High for one cycle when complete;
//                                               spike_out is valid on this cycle
//   spike_out        out    NB_HIDDEN (200)    Final hidden spike vector after
//                                               NB_STEPS time steps

module compute_core #(
    parameter int NB_HIDDEN = 200,
    parameter int NB_MACS   = 8,
    parameter int NB_STEPS  = 100,
    parameter int STATE_W   = 32,
    parameter int DECAY_W   = 16,
    parameter int WEIGHT_W  = 8,
    parameter int ACC_W     = 32
) (
    input  logic                        clk,
    input  logic                        rst,

    // Weight write port (one byte per cycle)
    input  logic                        weight_wr_en,
    input  logic [15:0]                 weight_wr_addr,
    input  logic [7:0]                  weight_wr_data,

    // LIF parameters
    input  logic [DECAY_W-1:0]          alpha,
    input  logic [DECAY_W-1:0]          beta,
    input  logic signed [STATE_W-1:0]   threshold,

    // Inference control
    input  logic                        start,
    input  logic [NB_HIDDEN-1:0]        spike_in,

    // Status and output
    output logic                        busy,
    output logic                        done,
    output logic [NB_HIDDEN-1:0]        spike_out
);

    localparam int NB_TILES   = NB_HIDDEN / NB_MACS;       // 25
    localparam int V1_WORDS   = NB_HIDDEN * NB_TILES;       // 5000
    localparam int V1_AW      = $clog2(V1_WORDS + 1);       // 13
    localparam int ROW_W      = $clog2(NB_HIDDEN + 1);      // 8
    localparam int ACT_IDX_W  = $clog2(NB_HIDDEN);          // 8
    localparam int TILE_W     = $clog2(NB_TILES  + 1);      // 5
    localparam int STEP_W     = $clog2(NB_STEPS  + 1);      // 7

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        S_IDLE, S_INIT_COLLECT, S_TILE_PRE, S_TILE_EXEC,
        S_TILE_DRAIN, S_LIF_UPDATE, S_STEP_DONE, S_OUTPUT
    } state_t;
    state_t state;

    // -------------------------------------------------------------------------
    // Counters
    // -------------------------------------------------------------------------
    logic [ROW_W-1:0]  row_cnt;   // scan index used only in S_INIT_COLLECT
    logic [TILE_W-1:0] tile_cnt;
    logic [STEP_W-1:0] step_cnt;
    logic [ROW_W-1:0]  lif_idx;

    // -------------------------------------------------------------------------
    // Active-spike index list
    // act_list[0..act_count-1]: row indices of neurons that fired last step.
    // Built from spike_in (S_INIT_COLLECT) and from lif_spike_vec
    // (S_LIF_UPDATE + S_STEP_DONE) for all subsequent steps.
    // -------------------------------------------------------------------------
    logic [ACT_IDX_W-1:0] act_list  [NB_HIDDEN];
    logic [ROW_W-1:0]     act_count;   // number of active neurons this step
    logic [ROW_W-1:0]     act_ptr;     // accumulation pointer during S_TILE_EXEC

    // -------------------------------------------------------------------------
    // Hidden spike vector (kept for readout; act_list drives SRAM addressing)
    // -------------------------------------------------------------------------
    logic [NB_HIDDEN-1:0] spike_vec;

    // -------------------------------------------------------------------------
    // h1 accumulator register file: NB_HIDDEN × ACC_W bits
    // -------------------------------------------------------------------------
    logic signed [ACC_W-1:0] h1_acc [NB_HIDDEN];

    // -------------------------------------------------------------------------
    // v1 weight SRAM — eight byte-wide banks, one per MAC output lane.
    // Each bank is V1_WORDS × WEIGHT_W = 5000 × 8-bit, implemented as five
    // sky130_sram_1kbyte_1rw1r_8x1024_8 macros tiled in depth (v1_sram_bank).
    // Per-bank write enables (from weight_wr_addr[2:0]) give byte-granular
    // loading. The read port has 1-cycle latency (synchronous inside the macro).
    // -------------------------------------------------------------------------
    logic [WEIGHT_W-1:0] v1_rd_r [NB_MACS];   // registered read output from macros

    genvar gb;
    generate
        for (gb = 0; gb < NB_MACS; gb++) begin : gen_sram
            v1_sram_bank #(
                .DEPTH       (V1_WORDS),
                .MACRO_DEPTH (1024)
            ) u_bank (
                .clk     (clk),
                .wr_en   (weight_wr_en &&
                          weight_wr_addr[$clog2(NB_MACS)-1:0] == $clog2(NB_MACS)'(gb)),
                .wr_addr (weight_wr_addr[15:$clog2(NB_MACS)]),
                .wr_data (weight_wr_data),
                .rd_addr (v1_rd_addr),
                .rd_data (v1_rd_r[gb])
            );
        end
    endgenerate

    // Pack registered read bytes into the 64-bit word expected by mac_array
    logic signed [NB_MACS-1:0][WEIGHT_W-1:0] v1_rd_data;
    genvar pb;
    generate
        for (pb = 0; pb < NB_MACS; pb++)
            assign v1_rd_data[pb] = $signed(v1_rd_r[pb]);
    endgenerate

    // -------------------------------------------------------------------------
    // SRAM read address — look-ahead: fetches one entry ahead of the
    // accumulation pointer so S_TILE_EXEC stays pipe-full.
    //   S_TILE_PRE:  fetch act_list[0] (v1_rd_ptr = 0)
    //   S_TILE_EXEC: fetch act_list[act_ptr+1] while accumulating act_list[act_ptr]
    //   All other states: address is don't-care (BRAM output ignored)
    // -------------------------------------------------------------------------
    logic [ROW_W-1:0]    v1_rd_ptr;
    logic [ACT_IDX_W-1:0] act_cur;
    logic [V1_AW-1:0]    v1_rd_addr;

    assign v1_rd_ptr  = (state == S_TILE_EXEC) ? (act_ptr + ROW_W'(1)) : '0;
    assign act_cur    = act_list[v1_rd_ptr];
    assign v1_rd_addr = V1_AW'(int'(act_cur) * NB_TILES + int'(tile_cnt));

    // -------------------------------------------------------------------------
    // Conditional-accumulate array
    // act_in is always 1 (act_list contains only active-spike indices).
    // mac_active gates weight_load and act_valid off when act_count = 0.
    // -------------------------------------------------------------------------
    logic signed [NB_MACS-1:0][ACC_W-1:0] mac_acc_out;
    logic                                   mac_active;

    assign mac_active = (state == S_TILE_EXEC) && (act_count != '0);

    snn_mac_array #(
        .N        (NB_MACS),
        .WEIGHT_W (WEIGHT_W),
        .ACC_W    (ACC_W)
    ) mac_array (
        .clk         (clk),
        .rst         (rst),
        .weight_load (mac_active),
        .weight_in   (v1_rd_data),
        .acc_clear   (state == S_TILE_DRAIN),
        .act_valid   (mac_active),
        .act_in      (1'b1),
        .acc_out     (mac_acc_out)
    );

    // -------------------------------------------------------------------------
    // LIF bank
    // -------------------------------------------------------------------------
    logic [NB_HIDDEN-1:0] lif_spike_vec;

    snn_lif_bank #(
        .NB      (NB_HIDDEN),
        .STATE_W (STATE_W),
        .DECAY_W (DECAY_W),
        .ACC_W   (ACC_W)
    ) lif_bank (
        .clk       (clk),
        .rst       (rst),
        .alpha     (alpha),
        .beta      (beta),
        .threshold (threshold),
        .h1_in     (h1_acc[lif_idx]),
        .h1_idx    (lif_idx[ACT_IDX_W-1:0]),
        .h1_valid  (state == S_LIF_UPDATE),
        .spike_vec (lif_spike_vec)
    );

    // -------------------------------------------------------------------------
    // FSM + counter sequencer
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            state     <= S_IDLE;
            row_cnt   <= '0;
            tile_cnt  <= '0;
            step_cnt  <= '0;
            lif_idx   <= '0;
            act_count <= '0;
            act_ptr   <= '0;
            spike_vec <= '0;
            busy      <= 1'b0;
            done      <= 1'b0;
            spike_out <= '0;
        end else begin
            done <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (start) begin
                        spike_vec <= spike_in;
                        row_cnt   <= '0;
                        tile_cnt  <= '0;
                        step_cnt  <= '0;
                        lif_idx   <= '0;
                        act_count <= '0;
                        act_ptr   <= '0;
                        busy      <= 1'b1;
                        state     <= S_INIT_COLLECT;
                    end
                end

                // Scan spike_vec (= spike_in) to build the initial act_list.
                // Uses row_cnt as the scan index; runs NB_HIDDEN cycles.
                S_INIT_COLLECT: begin
                    if (spike_vec[row_cnt]) begin
                        act_list[act_count] <= ACT_IDX_W'(row_cnt);
                        act_count           <= act_count + 1'b1;
                    end
                    if (row_cnt == ROW_W'(NB_HIDDEN - 1)) begin
                        row_cnt <= '0;
                        act_ptr <= '0;
                        state   <= S_TILE_PRE;
                    end else begin
                        row_cnt <= row_cnt + 1'b1;
                    end
                end

                // One-cycle BRAM prefetch: presents v1_rd_addr = act_list[0] × tile
                // so that v1_rd_r holds valid data when S_TILE_EXEC begins.
                // No accumulation; MAC array stays idle.
                S_TILE_PRE: begin
                    state <= S_TILE_EXEC;
                end

                // Stream act_list[0..act_count-1] through the MAC array.
                // v1_rd_r carries data for act_list[act_ptr] (fetched last cycle);
                // v1_rd_addr now fetches act_list[act_ptr+1] for the next cycle.
                // mac_active is gated off when act_count=0 (empty tile pass).
                S_TILE_EXEC: begin
                    if (act_count == '0 ||
                            act_ptr == (act_count - 1'b1)) begin
                        act_ptr <= '0;
                        state   <= S_TILE_DRAIN;
                    end else begin
                        act_ptr <= act_ptr + 1'b1;
                    end
                end

                S_TILE_DRAIN: begin
                    for (int k = 0; k < NB_MACS; k++)
                        h1_acc[int'(tile_cnt) * NB_MACS + k] <= mac_acc_out[k];

                    if (tile_cnt == TILE_W'(NB_TILES - 1)) begin
                        tile_cnt  <= '0;
                        lif_idx   <= '0;
                        act_count <= '0;   // reset; S_LIF_UPDATE rebuilds it
                        state     <= S_LIF_UPDATE;
                    end else begin
                        tile_cnt <= tile_cnt + 1'b1;
                        act_ptr  <= '0;
                        state    <= S_TILE_PRE;
                    end
                end

                // Update each LIF neuron serially. lif_spike_vec[i] is valid one
                // cycle after neuron i's h1_valid pulse, so neuron (lif_idx-1) is
                // collected here. Neuron NB_HIDDEN-1 is collected in S_STEP_DONE.
                S_LIF_UPDATE: begin
                    if (lif_idx != '0) begin
                        if (lif_spike_vec[lif_idx - 1'b1]) begin
                            act_list[act_count] <= lif_idx - 1'b1;
                            act_count           <= act_count + 1'b1;
                        end
                    end
                    if (lif_idx == ROW_W'(NB_HIDDEN - 1)) begin
                        lif_idx <= '0;
                        state   <= S_STEP_DONE;
                    end else begin
                        lif_idx <= lif_idx + 1'b1;
                    end
                end

                // Collect neuron NB_HIDDEN-1's result (processed last LIF cycle,
                // valid now). Advance step or go to output.
                S_STEP_DONE: begin
                    if (lif_spike_vec[NB_HIDDEN - 1]) begin
                        act_list[act_count] <= ACT_IDX_W'(NB_HIDDEN - 1);
                        act_count           <= act_count + 1'b1;
                    end

                    spike_vec <= lif_spike_vec;

                    if (step_cnt == STEP_W'(NB_STEPS - 1)) begin
                        state <= S_OUTPUT;
                    end else begin
                        step_cnt <= step_cnt + 1'b1;
                        tile_cnt <= '0;
                        act_ptr  <= '0;
                        state    <= S_TILE_PRE;
                    end
                end

                S_OUTPUT: begin
                    spike_out <= lif_spike_vec;
                    done      <= 1'b1;
                    busy      <= 1'b0;
                    state     <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule

`default_nettype wire
