`timescale 1ns/1ps
module b_tile_buffer_tb;
parameter int WIDTH = 16;
    parameter int N     = 8;
    parameter int ADDR_WIDTH = $clog2(N);
    logic clk;
    logic                       wr_en;
    logic [ADDR_WIDTH-1:0]      wr_addr;
    logic signed [WIDTH-1:0]    wr_data [N];
    logic signed [WIDTH-1:0]    rd_data [N][N];
    b_tile_buffer #(.WIDTH(WIDTH), .N(N)) dut (
        .clk     (clk),
        .wr_en   (wr_en),
        .wr_addr (wr_addr),
        .wr_data (wr_data),
        .rd_data (rd_data)
    );

    always #5 clk = ~clk;

    logic signed [WIDTH-1:0] expected [N][N];
    int errors;

    initial begin
        clk = 0; wr_en = 0; wr_addr = 0;
        for (int j = 0; j < N; j++) wr_data[j] = 0;
        @(posedge clk);
        $display("Writing 8 rows of B...");
        for (int i = 0; i < N; i++) begin
            wr_en   <= 1;
            wr_addr <= i;
            for (int j = 0; j < N; j++) begin
                expected[i][j] = i*16 + j*2 - 50;
                wr_data[j] <= expected[i][j];
            end
            @(posedge clk);
        end
        wr_en <= 0;
        @(posedge clk); #1;
        $display("Reading all 64 values in parallel and checking...");
        errors = 0;
        for (int i = 0; i < N; i++) begin
            for (int j = 0; j < N; j++) begin
                if (rd_data[i][j] !== expected[i][j]) begin
                    $display("MISMATCH [%0d][%0d]: got=%0d expected=%0d",
                             i, j, rd_data[i][j], expected[i][j]);
                    errors++;
                end
            end
        end
        if (errors == 0)
            $display("PASS: all %0d B-buffer values match expected", N*N);
        else
            $display("FAIL: %0d mismatches out of %0d", errors, N*N);
    $finish;
    end
endmodule
