`timescale 1ns/1ps

module pe (
    input  logic               clk,
    input  logic               rst,

    input  logic               load_weight,

    input  logic signed [15:0] a_in,
    input  logic signed [15:0] b_in,
    input  logic signed [31:0] c_in,

    output logic signed [15:0] a_out,
    output logic signed [31:0] c_out
);

    logic signed [15:0] weight;

    always_ff @(posedge clk) begin
        if (rst) begin
            weight <= '0;
            a_out  <= '0;
            c_out  <= '0;
        end else begin
            if (load_weight) weight <= b_in;
            a_out <= a_in;
            c_out <= c_in + a_in * weight;
        end
    end
endmodule
