`timescale 1ns / 1ps

module crossbar_mac (
    input  logic        clk,
    input  logic        rst_n,
    input  logic        enable,
    input  logic        weight_load,
    input  logic [3:0]  weight_row,
    input  logic [3:0]  weight_col,
    input  logic        weight_val,
    input  logic signed [7:0] in0,
    input  logic signed [7:0] in1,
    input  logic signed [7:0] in2,
    input  logic signed [7:0] in3,
    output logic signed [31:0] out0,
    output logic signed [31:0] out1,
    output logic signed [31:0] out2,
    output logic signed [31:0] out3
);

    // Weight matrix: 4x4 binary weights (+1/-1)
    // weight_matrix[i][j] = 0 represents +1, = 1 represents -1
    logic weight_matrix [0:3][0:3];

    // Input array for easier indexing
    logic signed [7:0] inputs [0:3];
    assign inputs[0] = in0;
    assign inputs[1] = in1;
    assign inputs[2] = in2;
    assign inputs[3] = in3;

    // Output accumulators
    logic signed [31:0] accumulators [0:3];
    assign out0 = accumulators[0];
    assign out1 = accumulators[1];
    assign out2 = accumulators[2];
    assign out3 = accumulators[3];

    // Intermediate products for each output
    logic signed [7:0] products [0:3][0:3];

    // Compute products: weight[i][j] * in[i]
    // If weight is 0 (+1): product = in[i]
    // If weight is 1 (-1): product = -in[i]
    // Unrolled for synthesis
    always_comb begin
        // Column 0
        products[0][0] = weight_matrix[0][0] ? -inputs[0] : inputs[0];
        products[1][0] = weight_matrix[1][0] ? -inputs[1] : inputs[1];
        products[2][0] = weight_matrix[2][0] ? -inputs[2] : inputs[2];
        products[3][0] = weight_matrix[3][0] ? -inputs[3] : inputs[3];

        // Column 1
        products[0][1] = weight_matrix[0][1] ? -inputs[0] : inputs[0];
        products[1][1] = weight_matrix[1][1] ? -inputs[1] : inputs[1];
        products[2][1] = weight_matrix[2][1] ? -inputs[2] : inputs[2];
        products[3][1] = weight_matrix[3][1] ? -inputs[3] : inputs[3];

        // Column 2
        products[0][2] = weight_matrix[0][2] ? -inputs[0] : inputs[0];
        products[1][2] = weight_matrix[1][2] ? -inputs[1] : inputs[1];
        products[2][2] = weight_matrix[2][2] ? -inputs[2] : inputs[2];
        products[3][2] = weight_matrix[3][2] ? -inputs[3] : inputs[3];

        // Column 3
        products[0][3] = weight_matrix[0][3] ? -inputs[0] : inputs[0];
        products[1][3] = weight_matrix[1][3] ? -inputs[1] : inputs[1];
        products[2][3] = weight_matrix[2][3] ? -inputs[2] : inputs[2];
        products[3][3] = weight_matrix[3][3] ? -inputs[3] : inputs[3];
    end

    // Weight loading logic
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            // Initialize all weights to +1 (0)
            weight_matrix[0][0] <= 1'b0;
            weight_matrix[0][1] <= 1'b0;
            weight_matrix[0][2] <= 1'b0;
            weight_matrix[0][3] <= 1'b0;
            weight_matrix[1][0] <= 1'b0;
            weight_matrix[1][1] <= 1'b0;
            weight_matrix[1][2] <= 1'b0;
            weight_matrix[1][3] <= 1'b0;
            weight_matrix[2][0] <= 1'b0;
            weight_matrix[2][1] <= 1'b0;
            weight_matrix[2][2] <= 1'b0;
            weight_matrix[2][3] <= 1'b0;
            weight_matrix[3][0] <= 1'b0;
            weight_matrix[3][1] <= 1'b0;
            weight_matrix[3][2] <= 1'b0;
            weight_matrix[3][3] <= 1'b0;
        end else if (weight_load) begin
            // Load individual weight at (weight_row, weight_col)
            weight_matrix[weight_row][weight_col] <= weight_val;
        end
    end

    // MAC operation: out[j] = sum_i weight[i][j] * in[i]
    // Proper sign extension to 32-bit before addition
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            accumulators[0] <= 32'sd0;
            accumulators[1] <= 32'sd0;
            accumulators[2] <= 32'sd0;
            accumulators[3] <= 32'sd0;
        end else if (enable) begin
            // Sign-extend first operand to 32-bit, rest will follow
            accumulators[0] <= $signed({{24{products[0][0][7]}}, products[0][0]}) +
                              $signed({{24{products[1][0][7]}}, products[1][0]}) +
                              $signed({{24{products[2][0][7]}}, products[2][0]}) +
                              $signed({{24{products[3][0][7]}}, products[3][0]});

            accumulators[1] <= $signed({{24{products[0][1][7]}}, products[0][1]}) +
                              $signed({{24{products[1][1][7]}}, products[1][1]}) +
                              $signed({{24{products[2][1][7]}}, products[2][1]}) +
                              $signed({{24{products[3][1][7]}}, products[3][1]});

            accumulators[2] <= $signed({{24{products[0][2][7]}}, products[0][2]}) +
                              $signed({{24{products[1][2][7]}}, products[1][2]}) +
                              $signed({{24{products[2][2][7]}}, products[2][2]}) +
                              $signed({{24{products[3][2][7]}}, products[3][2]});

            accumulators[3] <= $signed({{24{products[0][3][7]}}, products[0][3]}) +
                              $signed({{24{products[1][3][7]}}, products[1][3]}) +
                              $signed({{24{products[2][3][7]}}, products[2][3]}) +
                              $signed({{24{products[3][3][7]}}, products[3][3]});
        end
    end

endmodule
