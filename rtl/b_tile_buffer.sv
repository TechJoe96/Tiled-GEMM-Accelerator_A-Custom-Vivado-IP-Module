`timescale 1ns/1ps

module b_tile_buffer #(
    parameter int WIDTH      = 16,
    parameter int N          = 8,
    parameter int ADDR_WIDTH = $clog2(N)
) (
    input  logic                       clk,
// Write port — one row of B per cycle
    input  logic                       wr_en,
    input  logic [ADDR_WIDTH-1:0]      wr_addr,
    input  logic signed [WIDTH-1:0]    wr_data [N],
// Read port — all N×N values exposed in parallel (combinational)
    output logic signed [WIDTH-1:0]    rd_data [N][N]
);
    logic signed [WIDTH-1:0] mem [N][N];
// Write port: one row per cycle
    always_ff @(posedge clk) begin
        if (wr_en) begin
            for (int j = 0; j < N; j++)
                mem[wr_addr][j] <= wr_data[j];
        end
    end
// Read port: combinational, all 64 values always exposed
    always_comb begin
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++)
                rd_data[i][j] = mem[i][j];
    end
endmodule
