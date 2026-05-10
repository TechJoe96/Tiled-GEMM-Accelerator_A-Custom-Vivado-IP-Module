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

    // Test data
    logic signed [15:0] a_tile      [N*N];
    logic signed [15:0] b_tile      [N*N];
    logic signed [31:0] c_expected  [N*N];

    // PROBE arrays: populated by generate-time assigns so we can index at runtime
    logic signed [15:0] probe_weights      [N][N];
    logic signed [31:0] probe_pe_bot_cout  [N];
    logic signed [31:0] probe_col0_cwires  [N];

    genvar gi, gj;
    generate
        // Mirror every PE's loaded weight
        for (gi = 0; gi < N; gi = gi + 1) begin: probe_w_row
            for (gj = 0; gj < N; gj = gj + 1) begin: probe_w_col
                assign probe_weights[gi][gj] = dut.row[gi].col[gj].pe_inst.weight;
            end
        end
        // Mirror PE(N-1, *).c_out (bottom-row register output, before drain)
        for (gj = 0; gj < N; gj = gj + 1) begin: probe_botcout
            assign probe_pe_bot_cout[gj] = dut.row[N-1].col[gj].pe_inst.c_out;
        end
        // Mirror the entire column-0 c-chain at PE(0..N-1, 0).c_out
        for (gi = 0; gi < N; gi = gi + 1) begin: probe_col0
            assign probe_col0_cwires[gi] = dut.row[gi].col[0].pe_inst.c_out;
        end
    endgenerate

    initial begin
        // Initialize
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

        $display("a_tile row 0: %0d %0d %0d %0d %0d %0d %0d %0d",
            a_tile[0], a_tile[1], a_tile[2], a_tile[3],
            a_tile[4], a_tile[5], a_tile[6], a_tile[7]);
        $display("b_tile row 0: %0d %0d %0d %0d %0d %0d %0d %0d",
            b_tile[0], b_tile[1], b_tile[2], b_tile[3],
            b_tile[4], b_tile[5], b_tile[6], b_tile[7]);
        $display("c_expected row 0: %0d %0d %0d %0d %0d %0d %0d %0d",
            c_expected[0], c_expected[1], c_expected[2], c_expected[3],
            c_expected[4], c_expected[5], c_expected[6], c_expected[7]);

        // Hold reset
        repeat (3) @(posedge clk);
        rst = 0;
        @(posedge clk);

        // Weight load
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++)
                b_in[i][j] = b_tile[i*N + j];
        load_weight = 1;
        @(posedge clk);
        load_weight = 0;
        $display("--- weights loaded, starting A stream ---");

        // Print all loaded weights via the probe
        $display("Loaded weights (B values inside PEs):");
        for (int i = 0; i < N; i++) begin
            $write("  Row %0d:", i);
            for (int j = 0; j < N; j++)
                $write(" %5d", probe_weights[i][j]);
            $display("");
        end

        // Stream A row by row.
        // Use non-blocking (<=) so the new a_in value is committed in the NBA
        // region of the CURRENT time slot, after every always_ff in S_t has
        // already sampled the OLD a_in. This eliminates the TB-vs-RTL race in
        // which shift_regs were latching the next iteration's a_in early.
        for (int r = 0; r < N; r++) begin
            for (int k = 0; k < N; k++) a_in[k] <= a_tile[r*N + k];
            @(posedge clk);
        end
        for (int k = 0; k < N; k++) a_in[k] <= 0;
        $display("--- A stream done, watching c_out for 30 cycles ---");

        // Trace: c_out (post-drain), PE(7,*) (pre-drain bottom row), and column-0 chain
        for (int cy = 0; cy < 30; cy++) begin
            @(posedge clk); #1;
            $write("cy %2d  c_out:", cy);
            for (int j = 0; j < N; j++) $write(" %7d", c_out[j]);
            $write("    PE(7,*):");
            for (int j = 0; j < N; j++) $write(" %7d", probe_pe_bot_cout[j]);
            $write("    col0 chain:");
            for (int i = 0; i < N; i++) $write(" %7d", probe_col0_cwires[i]);
            $display("");
        end

        $finish;
    end

endmodule