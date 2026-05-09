`timescale 1ns/1ps

module systolic_array #(
    parameter int N = 8
) (
    input  logic                clk,
    input  logic                rst,

    input  logic                load_weight,

    input  logic signed [15:0]  a_in  [N],
    input  logic signed [15:0]  b_in  [N][N],

    output logic signed [31:0]  c_out [N]
);

    // a_wires[i][j] is the a_out of PE(i,j), which feeds PE(i,j+1)'s a_in
    // c_wires[i][j] is the c_out of PE(i,j), which feeds PE(i+1,j)'s c_in
    logic signed [15:0] a_wires [N][N];
    logic signed [31:0] c_wires [N][N];

    genvar i, j;
    generate
        for (i = 0; i < N; i = i + 1) begin: row
            for (j = 0; j < N; j = j + 1) begin: col
                pe pe_inst (
                    .clk         (clk),
                    .rst         (rst),
                    .load_weight (load_weight),
                    .a_in        (j == 0 ? a_in[i]   : a_wires[i][j-1]),
                    .b_in        (b_in[i][j]),
                    .c_in        (i == 0 ? 32'sd0    : c_wires[i-1][j]),
                    .a_out       (a_wires[i][j]),
                    .c_out       (c_wires[i][j])
                );
            end
        end
    endgenerate

    generate
        for (j = 0; j < N; j = j + 1) begin: col_out
            assign c_out[j] = c_wires[N-1][j];
        end
    endgenerate
endmodule

