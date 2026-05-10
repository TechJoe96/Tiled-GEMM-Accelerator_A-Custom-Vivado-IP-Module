`timescale 1ns/1ps

module shift_reg #(
    parameter int WIDTH = 16,
    parameter int DEPTH = 1
) (
    input  logic                    clk,
    input  logic                    rst,
    input  logic signed [WIDTH-1:0] d_in,
    output logic signed [WIDTH-1:0] d_out
);

    generate
        if (DEPTH == 0) begin: passthrough
            assign d_out = d_in;
        end else begin: shift
            logic signed [WIDTH-1:0] regs [DEPTH];

            always_ff @(posedge clk) begin
                if (rst) begin
                    for (int i = 0; i < DEPTH; i++) regs[i] <= '0;
                end else begin
                    regs[0] <= d_in;
                    for (int i = 1; i < DEPTH; i++) regs[i] <= regs[i-1];
                end
            end

            assign d_out = regs[DEPTH-1];
        end
    endgenerate

endmodule
