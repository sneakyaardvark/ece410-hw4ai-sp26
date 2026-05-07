`timescale 1ns / 1ps

module crossbar_tb;

    // Clock and reset
    logic clk;
    logic rst_n;

    // Control signals
    logic enable;
    logic weight_load;
    logic [3:0] weight_row;
    logic [3:0] weight_col;
    logic weight_val;

    // Data signals
    logic signed [7:0] in0, in1, in2, in3;
    logic signed [31:0] out0, out1, out2, out3;

    // Instantiate DUT
    crossbar_mac dut (
        .clk(clk),
        .rst_n(rst_n),
        .enable(enable),
        .weight_load(weight_load),
        .weight_row(weight_row),
        .weight_col(weight_col),
        .weight_val(weight_val),
        .in0(in0),
        .in1(in1),
        .in2(in2),
        .in3(in3),
        .out0(out0),
        .out1(out1),
        .out2(out2),
        .out3(out3)
    );

    // Clock generation: 10ns period (100MHz)
    initial begin
        clk = 0;
        forever #5 clk = ~clk;
    end

    // Test stimulus
    initial begin
        // Initialize signals
        rst_n = 0;
        enable = 0;
        weight_load = 0;
        weight_row = 0;
        weight_col = 0;
        weight_val = 0;
        in0 = 0;
        in1 = 0;
        in2 = 0;
        in3 = 0;

        // Wait for a few cycles
        repeat(3) @(posedge clk);

        // Release reset
        rst_n = 1;
        @(posedge clk);

        $display("=== Crossbar MAC Testbench ===");
        $display("Loading weight matrix:");
        $display("  [[ 1, -1,  1, -1],");
        $display("   [ 1,  1, -1, -1],");
        $display("   [-1,  1,  1, -1],");
        $display("   [-1, -1, -1,  1]]");
        $display("");

        // Load weights
        // Weight encoding: 0 = +1, 1 = -1
        // Row 0: [1, -1, 1, -1] -> [0, 1, 0, 1]
        load_weight(0, 0, 0); // +1
        load_weight(0, 1, 1); // -1
        load_weight(0, 2, 0); // +1
        load_weight(0, 3, 1); // -1

        // Row 1: [1, 1, -1, -1] -> [0, 0, 1, 1]
        load_weight(1, 0, 0); // +1
        load_weight(1, 1, 0); // +1
        load_weight(1, 2, 1); // -1
        load_weight(1, 3, 1); // -1

        // Row 2: [-1, 1, 1, -1] -> [1, 0, 0, 1]
        load_weight(2, 0, 1); // -1
        load_weight(2, 1, 0); // +1
        load_weight(2, 2, 0); // +1
        load_weight(2, 3, 1); // -1

        // Row 3: [-1, -1, -1, 1] -> [1, 1, 1, 0]
        load_weight(3, 0, 1); // -1
        load_weight(3, 1, 1); // -1
        load_weight(3, 2, 1); // -1
        load_weight(3, 3, 0); // +1

        $display("Weights loaded successfully");
        $display("");

        // Apply inputs [10, 20, 30, 40]
        $display("Applying inputs: [10, 20, 30, 40]");
        @(posedge clk);
        in0 = 8'sd10;
        in1 = 8'sd20;
        in2 = 8'sd30;
        in3 = 8'sd40;
        enable = 1;

        // Wait for computation
        @(posedge clk);
        @(posedge clk);

        // Check results
        $display("");
        $display("=== Results ===");
        $display("Expected outputs:");
        $display("  out[0] = (1*10) + (1*20) + (-1*30) + (-1*40) = 10 + 20 - 30 - 40 = -40");
        $display("  out[1] = (-1*10) + (1*20) + (1*30) + (-1*40) = -10 + 20 + 30 - 40 = 0");
        $display("  out[2] = (1*10) + (-1*20) + (1*30) + (-1*40) = 10 - 20 + 30 - 40 = -20");
        $display("  out[3] = (-1*10) + (-1*20) + (-1*30) + (1*40) = -10 - 20 - 30 + 40 = -20");
        $display("");
        $display("Actual outputs:");
        $display("  out[0] = %0d %s", out0, (out0 == -40) ? "✓" : "✗ FAIL");
        $display("  out[1] = %0d %s", out1, (out1 == 0) ? "✓" : "✗ FAIL");
        $display("  out[2] = %0d %s", out2, (out2 == -20) ? "✓" : "✗ FAIL");
        $display("  out[3] = %0d %s", out3, (out3 == -20) ? "✓" : "✗ FAIL");
        $display("");

        // Verify results
        if (out0 == -40 && out1 == 0 && out2 == -20 && out3 == -20) begin
            $display("=== TEST PASSED ===");
        end else begin
            $display("=== TEST FAILED ===");
            $display("Mismatch detected!");
        end

        // Run a few more cycles
        repeat(5) @(posedge clk);

        $finish;
    end

    // Task to load a single weight
    task load_weight(input [3:0] row, input [3:0] col, input val);
        begin
            @(posedge clk);
            weight_load = 1;
            weight_row = row;
            weight_col = col;
            weight_val = val;
            @(posedge clk);
            weight_load = 0;
        end
    endtask

    // Optional: VCD dump for waveform viewing
    initial begin
        $dumpfile("crossbar_tb.vcd");
        $dumpvars(0, crossbar_tb);
    end

endmodule
