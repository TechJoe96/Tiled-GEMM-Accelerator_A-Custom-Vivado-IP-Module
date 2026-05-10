`timescale 1ns/1ps

module systolic_array_tb;

    parameter int N = 8;

    logic clk;
    logic rst;
    logic load_weight;
    logic signed [15:0] a_in  [N];
    logic signed [15:0] b_in  [N][N];
    logic signed [31:0] c_out [N];

    systolic_array #(.N(N)) dut (
        .clk         (clk),
        .rst         (rst),
        .load_weight (load_weight),
        .a_in        (a_in),
        .b_in        (b_in),
        .c_out       (c_out)
    );

    always #5 clk = ~clk;

    logic signed [15:0] a_tile      [N*N];
    logic signed [15:0] b_tile      [N*N];
    logic signed [31:0] c_expected  [N*N];

    // *** NEW *** probe arrays for internal signals
    logic signed [15:0] probe_weights     [N][N];
    logic signed [31:0] probe_pe_bot_cout [N];

    // *** NEW *** generate block to wire probes from PE internals
    genvar gi, gj;
    generate
        for (gi = 0; gi < N; gi = gi + 1) begin: probe_w_row
            for (gj = 0; gj < N; gj = gj + 1) begin: probe_w_col
                assign probe_weights[gi][gj] = dut.row[gi].col[gj].pe_inst.weight;
            end
        end
        for (gj = 0; gj < N; gj = gj + 1) begin: probe_botcout
            assign probe_pe_bot_cout[gj] = dut.row[N-1].col[gj].pe_inst.c_out;
        end
    endgenerate

    initial begin
        clk         = 0;
        rst         = 1;
        load_weight = 0;
        for (int k = 0; k < N; k++) a_in[k] = 0;
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++)
                b_in[i][j] = 0;

        $readmemh("../tb/data/a_tile.hex",     a_tile);
        $readmemh("../tb/data/b_tile.hex",     b_tile);
        $readmemh("../tb/data/c_expected.hex", c_expected);
        $display("Test vectors loaded.");

        $display("a_tile row 0: %0d %0d %0d %0d %0d %0d %0d %0d",
            a_tile[0], a_tile[1], a_tile[2], a_tile[3],
            a_tile[4], a_tile[5], a_tile[6], a_tile[7]);
        $display("b_tile row 0: %0d %0d %0d %0d %0d %0d %0d %0d",
            b_tile[0], b_tile[1], b_tile[2], b_tile[3],
            b_tile[4], b_tile[5], b_tile[6], b_tile[7]);
        $display("c_expected row 0: %0d %0d %0d %0d %0d %0d %0d %0d",
            c_expected[0], c_expected[1], c_expected[2], c_expected[3],
            c_expected[4], c_expected[5], c_expected[6], c_expected[7]);

        repeat (3) @(posedge clk);
        rst = 0;
        @(posedge clk);

        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++)
                b_in[i][j] = b_tile[i*N + j];
        load_weight = 1;
        @(posedge clk);
        load_weight = 0;
        $display("--- weights loaded, starting A stream ---");

        // *** NEW *** print all loaded weights
        $display("Loaded weights (B values inside PEs):");
        for (int i = 0; i < N; i++) begin
            $write("  Row %0d:", i);
            for (int j = 0; j < N; j++)
                $write(" %5d", probe_weights[i][j]);
            $display("");
        end

        for (int r = 0; r < N; r++) begin
            for (int k = 0; k < N; k++) a_in[k] = a_tile[r*N + k];
            @(posedge clk);
        end
        for (int k = 0; k < N; k++) a_in[k] = 0;
        $display("--- A stream done, watching c_out for 30 cycles ---");

        // Snapshot PE(7,*).c_out *immediately* after the last streaming edge (r=7),
        // before any further @(posedge clk) overwrites it. PE(7,0).c_out at this
        // instant should equal C[0][0]; the other PE(7,j) cells are still ramping.
        #1;
        $write("after r=7  PE(7,*):");
        for (int j = 0; j < N; j++) $write(" %7d", probe_pe_bot_cout[j]);
        $display("");

        // *** NEW *** print PE(7,*) alongside c_out in the trace
        for (int cy = 0; cy < 30; cy++) begin
            @(posedge clk); #1;
            $write("cy %2d  c_out:", cy);
            for (int j = 0; j < N; j++) $write(" %7d", c_out[j]);
            $write("    PE(7,*):");
            for (int j = 0; j < N; j++) $write(" %7d", probe_pe_bot_cout[j]);
            $display("");
        end

        $finish;
    end

endmodule