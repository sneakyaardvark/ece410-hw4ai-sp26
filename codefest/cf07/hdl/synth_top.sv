`default_nettype none

// Module: compute_core
// Description: Top-level SNN compute datapath. Stores the v1 recurrent weight
//              matrix (200×200 INT8) in on-chip SRAM and runs NB_STEPS time
//              steps of the hidden-layer recurrence:
//                h1        = v1 @ spike_vec          (tiled MAC, 25 tiles × 8 outputs)
//                spike_vec = LIF_update(h1)          (200 neurons, serial)
//              Tiling: NB_HIDDEN/NB_MACS = 25 output tiles, each tile streams
//              all NB_HIDDEN input activations through the 8-wide MAC array.
//              Single clock domain; synchronous active-high reset.
//              Note: w1 (input projection) and w2 (output layer) are not yet
//              implemented; the host provides the initial spike_in vector and
//              reads spike_out after NB_STEPS steps (M3 will add w1/w2).
//
// Ports:
//   Name             Dir    Width              Purpose
//   ---------------------------------------------------------------------------
//   clk              in     1                  System clock (50 MHz)
//   rst              in     1                  Synchronous active-high reset
//   weight_wr_en     in     1                  Write one byte of v1 weight SRAM
//   weight_wr_addr   in     16                 Byte address in v1 SRAM
//                                               (row*NB_HIDDEN + col, 0..39999)
//   weight_wr_data   in     8                  INT8 weight byte to write
//   alpha            in     DECAY_W (16)       Q1.15 synaptic decay constant
//   beta             in     DECAY_W (16)       Q1.15 membrane decay constant
//   threshold        in     STATE_W (32)       INT32 LIF spike threshold
//   start            in     1                  Pulse to begin inference; latches
//                                               spike_in and resets all counters
//   spike_in         in     NB_HIDDEN (200)    Initial hidden spike vector
//                                               (used as step-0 recurrent input)
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

    localparam int NB_TILES  = NB_HIDDEN / NB_MACS;       // 25
    localparam int V1_WORDS  = NB_HIDDEN * NB_TILES;       // 5000
    localparam int V1_AW     = $clog2(V1_WORDS + 1);       // 13
    localparam int ROW_W     = $clog2(NB_HIDDEN + 1);      // 8
    localparam int TILE_W    = $clog2(NB_TILES  + 1);      // 5
    localparam int STEP_W    = $clog2(NB_STEPS  + 1);      // 7

    // -------------------------------------------------------------------------
    // FSM
    // -------------------------------------------------------------------------
    typedef enum logic [2:0] {
        S_IDLE, S_TILE_EXEC, S_TILE_DRAIN, S_LIF_UPDATE, S_STEP_DONE, S_OUTPUT
    } state_t;
    state_t state;

    // -------------------------------------------------------------------------
    // Counters
    // -------------------------------------------------------------------------
    logic [ROW_W-1:0]  row_cnt;
    logic [TILE_W-1:0] tile_cnt;
    logic [STEP_W-1:0] step_cnt;
    logic [ROW_W-1:0]  lif_idx;

    // -------------------------------------------------------------------------
    // Hidden spike vector register (feeds the MAC array as activations)
    // -------------------------------------------------------------------------
    logic [NB_HIDDEN-1:0] spike_vec;

    // -------------------------------------------------------------------------
    // h1 accumulator register file: NB_HIDDEN × ACC_W bits
    // Tile k writes h1_acc[k*NB_MACS .. k*NB_MACS+NB_MACS-1] during TILE_DRAIN.
    // All NB_HIDDEN entries are written before LIF_UPDATE reads them.
    // -------------------------------------------------------------------------
    logic signed [ACC_W-1:0] h1_acc [NB_HIDDEN];

    // -------------------------------------------------------------------------
    // v1 weight SRAM
    // Word-addressed: word (row*NB_TILES + tile) holds NB_MACS INT8 weights.
    // Byte write: word = addr[15:3], lane = addr[2:0].
    // Row-major layout makes word addresses contiguous per output tile group.
    // -------------------------------------------------------------------------
    logic [NB_MACS*WEIGHT_W-1:0] v1_mem [V1_WORDS];

    always_ff @(posedge clk) begin
        if (weight_wr_en)
            v1_mem[weight_wr_addr[15:3]][weight_wr_addr[2:0]*8 +: 8] <= weight_wr_data;
    end

    // Combinatorial read: current (row, tile) → word address → 8 weights
    logic [V1_AW-1:0]            v1_rd_addr;
    logic [NB_MACS*WEIGHT_W-1:0] v1_rd_data;

    assign v1_rd_addr = V1_AW'(int'(row_cnt) * NB_TILES + int'(tile_cnt));
    assign v1_rd_data = v1_mem[v1_rd_addr];

    // -------------------------------------------------------------------------
    // MAC array
    // In S_TILE_EXEC: weight_load=act_valid=1 each cycle (forwarding mux in
    // snn_mac ensures the new weight pairs with the current activation).
    // In S_TILE_DRAIN: acc_clear=1 to reset for the next tile.
    // -------------------------------------------------------------------------
    logic signed [NB_MACS-1:0][ACC_W-1:0] mac_acc_out;
    logic signed [WEIGHT_W-1:0]            mac_act_in;

    assign mac_act_in = $signed({7'b0, spike_vec[row_cnt]});

    snn_mac_array #(
        .N        (NB_MACS),
        .ACT_W    (WEIGHT_W),
        .WEIGHT_W (WEIGHT_W),
        .ACC_W    (ACC_W)
    ) mac_array (
        .clk         (clk),
        .rst         (rst),
        .weight_load (state == S_TILE_EXEC),
        .weight_in   (v1_rd_data),
        .acc_clear   (state == S_TILE_DRAIN),
        .act_valid   (state == S_TILE_EXEC),
        .act_in      (mac_act_in),
        .acc_out     (mac_acc_out)
    );

    // -------------------------------------------------------------------------
    // LIF bank
    // In S_LIF_UPDATE: h1_valid=1, h1_idx=lif_idx, h1_in=h1_acc[lif_idx].
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
        .h1_idx    (lif_idx[$clog2(NB_HIDDEN)-1:0]),
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
            spike_vec <= '0;
            busy      <= 1'b0;
            done      <= 1'b0;
            spike_out <= '0;
        end else begin
            done <= 1'b0;  // default: done is a one-cycle pulse

            case (state)
                S_IDLE: begin
                    if (start) begin
                        spike_vec <= spike_in;
                        row_cnt   <= '0;
                        tile_cnt  <= '0;
                        step_cnt  <= '0;
                        lif_idx   <= '0;
                        busy      <= 1'b1;
                        state     <= S_TILE_EXEC;
                    end
                end

                S_TILE_EXEC: begin
                    if (row_cnt == ROW_W'(NB_HIDDEN - 1)) begin
                        row_cnt <= '0;
                        state   <= S_TILE_DRAIN;
                    end else begin
                        row_cnt <= row_cnt + 1'b1;
                    end
                end

                S_TILE_DRAIN: begin
                    // Capture 8 MAC results into h1_acc for this tile.
                    // MAC clears on this clock edge (acc_clear asserted).
                    for (int k = 0; k < NB_MACS; k++)
                        h1_acc[int'(tile_cnt) * NB_MACS + k] <= mac_acc_out[k];

                    if (tile_cnt == TILE_W'(NB_TILES - 1)) begin
                        tile_cnt <= '0;
                        lif_idx  <= '0;
                        state    <= S_LIF_UPDATE;
                    end else begin
                        tile_cnt <= tile_cnt + 1'b1;
                        state    <= S_TILE_EXEC;
                    end
                end

                S_LIF_UPDATE: begin
                    if (lif_idx == ROW_W'(NB_HIDDEN - 1)) begin
                        lif_idx <= '0;
                        state   <= S_STEP_DONE;
                    end else begin
                        lif_idx <= lif_idx + 1'b1;
                    end
                end

                S_STEP_DONE: begin
                    // Latch the new spike vector for the next recurrent step.
                    spike_vec <= lif_spike_vec;

                    if (step_cnt == STEP_W'(NB_STEPS - 1)) begin
                        state <= S_OUTPUT;
                    end else begin
                        step_cnt <= step_cnt + 1'b1;
                        row_cnt  <= '0;
                        tile_cnt <= '0;
                        state    <= S_TILE_EXEC;
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
