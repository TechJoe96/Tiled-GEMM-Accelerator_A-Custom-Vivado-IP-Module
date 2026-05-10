`timescale 1ns/1ps

module tile_buffer #(
    parameter int WIDTH = 16,
    parameter int DEPTH = 64,
    parameter int ADDR_WIDTH = $clog2(DEPTH)
) (
    input  logic                       clk,
// Write port
    input  logic                       wr_en,
    input  logic [ADDR_WIDTH-1:0]      wr_addr,
    input  logic signed [WIDTH-1:0]    wr_data,
// Read port
    input  logic [ADDR_WIDTH-1:0]      rd_addr,
    output logic signed [WIDTH-1:0]    rd_data
);

    logic signed [WIDTH-1:0] mem [DEPTH];
    always_ff @(posedge clk) begin
            if (wr_en) mem[wr_addr] <= wr_data;
        end
    always_ff @(posedge clk) begin
            rd_data <= mem[rd_addr];
        end
endmodule
