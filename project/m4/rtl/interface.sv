`default_nettype none

// Module: spi_interface
// Description: SPI slave bridging a host MCU to compute_core. Single clock
//              domain: the 50 MHz core clock samples SCK/MOSI/CS_N through a
//              2-stage synchronizer and detects edges. Supports SCK up to
//              ~8 MHz (< core_clk/6 for metastability margin).
//
//              Protocol: SPI Mode 0 (CPOL=0, CPHA=0). Data sampled on rising
//              SCK, shifted out on falling SCK. Fixed 4-byte transactions:
//                [CMD:8] [ADDR_HI:8] [ADDR_LO:8] [DATA:8]
//              CMD 0x02 = WRITE, CMD 0x03 = READ.
//              CS_N must be de-asserted (high) between transactions.
//
//              Register map (16-bit address space):
//                0x0000..0x9C3F  Weight SRAM (write): addr = in_neuron*200 + out_neuron
//                0xA000..0xA018  spike_in[199:0] bytes (write): byte k = spike_in[8k+7:8k]
//                0xA019          Control: write 0x01 = pulse start inference
//                0xA01A          Status (read): bit1=done, bit0=busy
//                0xA01B..0xA033  spike_out[199:0] bytes (read, latched on done)
//                0xA034          alpha[7:0]   (write)
//                0xA035          alpha[15:8]  (write)
//                0xA036          beta[7:0]    (write)
//                0xA037          beta[15:8]   (write)
//                0xA038          threshold[7:0]   (write)
//                0xA039          threshold[15:8]  (write)
//                0xA03A          threshold[23:16] (write)
//                0xA03B          threshold[31:24] (write)
//
// Ports:
//   Name             Dir    Width              Purpose
//   ---------------------------------------------------------------------------
//   clk              in     1                  System clock (50 MHz)
//   rst              in     1                  Synchronous active-high reset
//   sck              in     1                  SPI clock from host (Mode 0)
//   cs_n             in     1                  SPI chip select, active-low
//   mosi             in     1                  Host-to-slave data (MSB first)
//   miso             out    1                  Slave-to-host data (MSB first)
//   weight_wr_en     out    1                  Byte write enable to weight SRAM
//   weight_wr_addr   out    16                 Byte address in weight SRAM
//   weight_wr_data   out    8                  INT8 weight byte to write
//   alpha            out    DECAY_W (16)       Q1.15 synaptic decay for LIF bank
//   beta             out    DECAY_W (16)       Q1.15 membrane decay for LIF bank
//   threshold        out    STATE_W (32)       INT32 spike threshold for LIF bank
//   start            out    1                  One-cycle pulse to begin inference
//   spike_in         out    NB_HIDDEN (200)    Initial hidden spike vector
//   busy             in     1                  High while inference is running
//   done             in     1                  High for one cycle when complete
//   spike_out        in     NB_HIDDEN (200)    Final spike vector from compute_core

module spi_interface #(
    parameter int NB_HIDDEN   = 200,
    parameter int STATE_W     = 32,
    parameter int DECAY_W     = 16,
    parameter int ALPHA_INIT  = 19875,
    parameter int BETA_INIT   = 29635,
    parameter int THRESH_INIT = 32768
) (
    input  logic                        clk,
    input  logic                        rst,

    // SPI slave port (Mode 0: CPOL=0, CPHA=0)
    input  logic                        sck,
    input  logic                        cs_n,
    input  logic                        mosi,
    output logic                        miso,

    // Compute core connections
    output logic                        weight_wr_en,
    output logic [15:0]                 weight_wr_addr,
    output logic [7:0]                  weight_wr_data,
    output logic [DECAY_W-1:0]          alpha,
    output logic [DECAY_W-1:0]          beta,
    output logic signed [STATE_W-1:0]   threshold,
    output logic                        start,
    output logic [NB_HIDDEN-1:0]        spike_in,
    input  logic                        busy,
    input  logic                        done,
    input  logic [NB_HIDDEN-1:0]        spike_out
);

    localparam int      NB_BYTES       = NB_HIDDEN / 8;
    localparam [15:0]   SPIKE_IN_BASE  = 16'hA000;
    localparam [15:0]   CTRL_ADDR      = 16'hA019;
    localparam [15:0]   STATUS_ADDR    = 16'hA01A;
    localparam [15:0]   SPIKE_OUT_BASE = 16'hA01B;
    localparam [15:0]   ALPHA_LO       = 16'hA034;
    localparam [15:0]   ALPHA_HI       = 16'hA035;
    localparam [15:0]   BETA_LO        = 16'hA036;
    localparam [15:0]   BETA_HI        = 16'hA037;
    localparam [15:0]   THRESH_B0      = 16'hA038;
    localparam [15:0]   THRESH_B1      = 16'hA039;
    localparam [15:0]   THRESH_B2      = 16'hA03A;
    localparam [15:0]   THRESH_B3      = 16'hA03B;

    // -------------------------------------------------------------------------
    // 2-stage synchronizers
    // -------------------------------------------------------------------------
    logic sck_d1, sck_d2, csn_d1, csn_d2, mosi_d;

    always_ff @(posedge clk) begin
        if (rst) begin
            sck_d1  <= 1'b0; sck_d2  <= 1'b0;
            csn_d1  <= 1'b1; csn_d2  <= 1'b1;
            mosi_d  <= 1'b0;
        end else begin
            sck_d1  <= sck;    sck_d2  <= sck_d1;
            csn_d1  <= cs_n;   csn_d2  <= csn_d1;
            mosi_d  <= mosi;
        end
    end

    wire sck_rising  =  sck_d1 & ~sck_d2;
    wire sck_falling = ~sck_d1 &  sck_d2;
    wire csn_desel   =  csn_d1 & ~csn_d2;   // CS_N ↑: end of transaction

    // -------------------------------------------------------------------------
    // Receiver state
    // -------------------------------------------------------------------------
    logic [7:0]  rx_shift;
    logic [2:0]  bit_cnt;
    logic [1:0]  byte_cnt;
    logic [7:0]  rx_cmd;
    logic [15:0] rx_addr;

    // The byte being completed: valid when bit_cnt==7 and sck_rising is active.
    // Uses pre-edge values of rx_shift and mosi_d — both stable at this point.
    wire [7:0] rx_byte_now = {rx_shift[6:0], mosi_d};

    // -------------------------------------------------------------------------
    // spike_out latch (independent of SPI path)
    // -------------------------------------------------------------------------
    logic [NB_HIDDEN-1:0] spike_out_lat;

    always_ff @(posedge clk) begin
        if (rst)       spike_out_lat <= '0;
        else if (done) spike_out_lat <= spike_out;
    end

    // -------------------------------------------------------------------------
    // Combinatorial read-data mux
    // rd_addr is {rx_addr[15:8], rx_byte_now}, valid on ADDR_LO byte_done.
    // -------------------------------------------------------------------------
    wire [15:0] rd_addr = {rx_addr[15:8], rx_byte_now};

    logic [7:0] reg_rd_data;
    always_comb begin
        reg_rd_data = 8'h00;
        if (rd_addr == STATUS_ADDR) begin
            reg_rd_data = {6'b0, done, busy};
        end else begin
            for (int k = 0; k < NB_BYTES; k++) begin
                if (rd_addr == SPIKE_OUT_BASE + 16'(k))
                    reg_rd_data = spike_out_lat[k*8 +: 8];
            end
        end
    end

    // -------------------------------------------------------------------------
    // Main SPI FSM — receiver, MISO shifter, and write executor in one block.
    //
    // Critical design note: write execution and tx_shift loading happen in the
    // SAME always_ff as the receiver so they fire at the same clock edge as the
    // byte_done event.  Using a separate block would delay by one cycle, by
    // which point mosi_d has advanced to the next bit and rx_byte_now would
    // return a byte shifted left by one.
    // -------------------------------------------------------------------------
    logic [7:0] tx_shift;

    always_ff @(posedge clk) begin
        if (rst || csn_desel) begin
            rx_shift      <= '0;
            bit_cnt       <= '0;
            byte_cnt      <= '0;
            rx_cmd        <= '0;
            rx_addr       <= '0;
            tx_shift      <= '0;
            miso          <= 1'b0;
            weight_wr_en  <= 1'b0;
            weight_wr_addr <= '0;
            weight_wr_data <= '0;
            start         <= 1'b0;
            if (rst) begin
                spike_in  <= '0;
                alpha     <= DECAY_W'(ALPHA_INIT);
                beta      <= DECAY_W'(BETA_INIT);
                threshold <= STATE_W'(THRESH_INIT);
            end
        end else begin
            // Default: clear one-cycle strobes
            weight_wr_en <= 1'b0;
            start        <= 1'b0;

            // -----------------------------------------------------------------
            // Rising SCK: shift in MOSI bit; execute action on byte boundary
            // -----------------------------------------------------------------
            if (sck_rising && !csn_d1) begin
                rx_shift <= {rx_shift[6:0], mosi_d};

                if (bit_cnt == 3'd7) begin
                    bit_cnt <= '0;

                    case (byte_cnt)
                        2'd0: begin
                            rx_cmd <= rx_byte_now;
                        end

                        2'd1: begin
                            rx_addr[15:8] <= rx_byte_now;
                        end

                        2'd2: begin
                            rx_addr[7:0] <= rx_byte_now;
                            // For READ: load tx_shift now; rd_addr is valid
                            if (rx_cmd == 8'h03)
                                tx_shift <= reg_rd_data;
                        end

                        2'd3: begin
                            // WRITE command: execute immediately on this edge
                            if (rx_cmd == 8'h02) begin
                                if (rx_addr < 16'hA000) begin
                                    weight_wr_en   <= 1'b1;
                                    weight_wr_addr <= rx_addr;
                                    weight_wr_data <= rx_byte_now;
                                end else if (rx_addr == CTRL_ADDR) begin
                                    if (rx_byte_now == 8'h01) start <= 1'b1;
                                end else if (rx_addr == ALPHA_LO) begin
                                    alpha[7:0]  <= rx_byte_now;
                                end else if (rx_addr == ALPHA_HI) begin
                                    alpha[15:8] <= rx_byte_now;
                                end else if (rx_addr == BETA_LO) begin
                                    beta[7:0]   <= rx_byte_now;
                                end else if (rx_addr == BETA_HI) begin
                                    beta[15:8]  <= rx_byte_now;
                                end else if (rx_addr == THRESH_B0) begin
                                    threshold[7:0]   <= rx_byte_now;
                                end else if (rx_addr == THRESH_B1) begin
                                    threshold[15:8]  <= rx_byte_now;
                                end else if (rx_addr == THRESH_B2) begin
                                    threshold[23:16] <= rx_byte_now;
                                end else if (rx_addr == THRESH_B3) begin
                                    threshold[31:24] <= rx_byte_now;
                                end else begin
                                    for (int k = 0; k < NB_BYTES; k++) begin
                                        if (rx_addr == SPIKE_IN_BASE + 16'(k))
                                            spike_in[k*8 +: 8] <= rx_byte_now;
                                    end
                                end
                            end
                        end

                        default: ;
                    endcase

                    if (byte_cnt != 2'd3)
                        byte_cnt <= byte_cnt + 1'b1;

                end else begin
                    bit_cnt <= bit_cnt + 1'b1;
                end
            end

            // -----------------------------------------------------------------
            // Falling SCK: shift MISO out MSB-first during DATA byte
            // -----------------------------------------------------------------
            if (sck_falling && !csn_d1 && byte_cnt == 2'd3) begin
                miso     <= tx_shift[7];
                tx_shift <= {tx_shift[6:0], 1'b0};
            end
        end
    end

endmodule

`default_nettype wire
