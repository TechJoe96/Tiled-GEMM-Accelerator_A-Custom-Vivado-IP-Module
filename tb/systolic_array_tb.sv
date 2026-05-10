`timescale 1ns/1ps

module systolic_array_tb;

    parameter int N = 8;

    // Signals connecting to the DUT
    logic clk;
    logic rst;
    logic load_weight;
    logic signed [15:0] a_in  [N];
    logic signed [15:0] b_in  [N][N];
    logic signed [31:0] c_out [N];

    // Instantiate the systolic array under test
    systolic_array #(.N(N)) dut (
        .clk         (clk),
        .rst         (rst),
        .load_weight (load_weight),
        .a_in        (a_in),
        .b_in        (b_in),
        .c_out       (c_out)
    );

    // 100 MHz clock
    always #5 clk = ~clk;

    // Test data: flat 1D arrays, loaded from hex files
    logic signed [15:0] a_tile      [N*N];
    logic signed [15:0] b_tile      [N*N];
    logic signed [31:0] c_expected  [N*N];

    initial begin
        // Initialize driven signals
        clk         = 0;
        rst         = 1;
        load_weight = 0;
        for (int k = 0; k < N; k++) a_in[k] = 0;
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++)
                b_in[i][j] = 0;

        // Read test vectors from hex files
        $readmemh("../tb/data/a_tile.hex",     a_tile);
        $readmemh("../tb/data/b_tile.hex",     b_tile);
        $readmemh("../tb/data/c_expected.hex", c_expected);
        $display("Test vectors loaded.");

        // Sanity-check the loaded values: print row 0 of each tile
        $display("a_tile row 0: %0d %0d %0d %0d %0d %0d %0d %0d",
            a_tile[0], a_tile[1], a_tile[2], a_tile[3],
            a_tile[4], a_tile[5], a_tile[6], a_tile[7]);
        $display("b_tile row 0: %0d %0d %0d %0d %0d %0d %0d %0d",
            b_tile[0], b_tile[1], b_tile[2], b_tile[3],
            b_tile[4], b_tile[5], b_tile[6], b_tile[7]);
        $display("c_expected row 0: %0d %0d %0d %0d %0d %0d %0d %0d",
            c_expected[0], c_expected[1], c_expected[2], c_expected[3],
            c_expected[4], c_expected[5], c_expected[6], c_expected[7]);
        $display("c_expected row 1: %0d %0d %0d %0d %0d %0d %0d %0d",
            c_expected[8],  c_expected[9],  c_expected[10], c_expected[11],
            c_expected[12], c_expected[13], c_expected[14], c_expected[15]);

        // Hold reset
        repeat (3) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // Weight load: all 64 B values latched in one cycle
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++)
                b_in[i][j] = b_tile[i*N + j];
        load_weight = 1;
        @(posedge clk);
        load_weight = 0;
        $display("--- weights loaded, starting A stream ---");

        // Stream A row by row for N cycles
        for (int r = 0; r < N; r++) begin
            for (int k = 0; k < N; k++) a_in[k] = a_tile[r*N + k];
            @(posedge clk);
        end
        for (int k = 0; k < N; k++) a_in[k] = 0;
        $display("--- A stream done, watching c_out for 30 cycles ---");

        // Wide trace: print c_out for many cycles after streaming ends
        for (int cy = 0; cy < 30; cy++) begin
            @(posedge clk); #1;
            $write("After cycle %2d: ", cy);
            for (int j = 0; j < N; j++) $write(" %7d", c_out[j]);
            $display("");
        end

        $finish;
    end

endmodule