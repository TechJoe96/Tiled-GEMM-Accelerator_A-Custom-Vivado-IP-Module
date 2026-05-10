`timescale 1ns/1ps
module array_ctrl_tb;
    parameter int N        = 8;
    parameter int WIDTH    = 16;
    parameter int N_TESTS  = 100;
    parameter int TILE_LEN = N * N;
    parameter int TOTAL    = N_TESTS * TILE_LEN;
    logic clk;
    logic rst;
    logic start;
    logic done;
    logic signed [31:0] c_out [N];
    logic                         load_weight;
    logic [$clog2(N)-1:0]         a_rd_addr;
    logic                         stream_active;
    logic                         a_wr_en;
    logic [$clog2(N)-1:0]         a_wr_addr;
    logic signed [WIDTH-1:0]      a_wr_data [N];
    logic signed [WIDTH-1:0]      a_rd_data [N];
    logic                         b_wr_en;
    logic [$clog2(N)-1:0]         b_wr_addr;
    logic signed [WIDTH-1:0]      b_wr_data [N];
    logic signed [WIDTH-1:0]      b_rd_data [N][N];
    logic signed [WIDTH-1:0] a_in_to_array [N];
    always_comb begin
        for (int k = 0; k < N; k++)
            a_in_to_array[k] = stream_active ? a_rd_data[k] : '0;
    end
    tile_ctrl #(
        .N(N),
        .DRAIN_CYCLES(6)
    ) ctrl (
        .clk           (clk),
        .rst           (rst),
        .start         (start),
        .load_weight   (load_weight),
        .a_rd_addr     (a_rd_addr),
        .stream_active (stream_active),
        .done          (done)
    );
    a_tile_buffer #(.WIDTH(WIDTH), .N(N)) abuf (
        .clk     (clk),
        .wr_en   (a_wr_en),
        .wr_addr (a_wr_addr),
        .wr_data (a_wr_data),
        .rd_addr (a_rd_addr),
        .rd_data (a_rd_data)
    );

    b_tile_buffer #(.WIDTH(WIDTH), .N(N)) bbuf (
        .clk     (clk),
        .wr_en   (b_wr_en),
        .wr_addr (b_wr_addr),
        .wr_data (b_wr_data),
        .rd_data (b_rd_data)
    );

    systolic_array #(.N(N)) dut (
        .clk         (clk),
        .rst         (rst),
        .load_weight (load_weight),
        .a_in        (a_in_to_array),
        .b_in        (b_rd_data),
        .c_out       (c_out)
    );
    always #5 clk = ~clk;

    logic signed [15:0] a_tile_all     [TOTAL];
    logic signed [15:0] b_tile_all     [TOTAL];
    logic signed [31:0] c_expected_all [TOTAL];

    int pass_count;
    int fail_count;
    int printed_failures;

    function automatic int idx(input int test, input int row, input int col);
        idx = test*TILE_LEN + row*N + col;
    endfunction

    initial begin
        clk         = 0;
        rst         = 1;
        start       = 0;
        a_wr_en     = 0; a_wr_addr = 0;
        b_wr_en     = 0; b_wr_addr = 0;
        for (int k = 0; k < N; k++) begin
            a_wr_data[k] = 0;
            b_wr_data[k] = 0;
        end
        $readmemh("../tb/data/a_tile.hex",     a_tile_all);
        $readmemh("../tb/data/b_tile.hex",     b_tile_all);
        $readmemh("../tb/data/c_expected.hex", c_expected_all);
        $display("Loaded %0d test cases.", N_TESTS);
        repeat (3) @(posedge clk);

        pass_count       = 0;
        fail_count       = 0;
        printed_failures = 0;
        for (int T = 0; T < N_TESTS; T++) begin

// Reset between tests
            rst     <= 1;
            start   <= 0;
            a_wr_en <= 0;
            b_wr_en <= 0;
            repeat (2) @(posedge clk);
// Pre-load BOTH buffers in parallel (8 cycles)
            for (int r = 0; r < N; r++) begin
                a_wr_en   <= 1;
                a_wr_addr <= r;
                b_wr_en   <= 1;
                b_wr_addr <= r;
                for (int k = 0; k < N; k++) begin
                    a_wr_data[k] <= a_tile_all[idx(T, r, k)];
                    b_wr_data[k] <= b_tile_all[idx(T, r, k)];
                end
                @(posedge clk);
            end
            a_wr_en <= 0;
            b_wr_en <= 0;
// Drop reset and pulse start
            rst   <= 0;
            start <= 1;
            @(posedge clk);
            start <= 0;
// Wait for FSM to assert done
            while (!done) @(posedge clk);
// Capture & check 8 rows of C
            for (int row = 0; row < N; row++) begin
                if (row > 0) @(posedge clk);
                #1;
                for (int j = 0; j < N; j++) begin
                    automatic logic signed [31:0] expected = c_expected_all[idx(T, row, j)];
                    if (c_out[j] !== expected) begin
                        fail_count++;
                        if (printed_failures < 10) begin
                            $display("FAIL T=%0d row=%0d col=%0d got=%0d expected=%0d",
                                     T, row, j, c_out[j], expected);
                            printed_failures++;
                        end
                    end else begin
                        pass_count++;
                    end
                end
            end
        end
        $display("==================== SUMMARY ====================");
        $display("Total checks: %0d  (%0d tests x %0d values each)",
                 pass_count + fail_count, N_TESTS, TILE_LEN);
        $display("Pass:         %0d", pass_count);
        $display("Fail:         %0d", fail_count);
        if (fail_count == 0)
            $display("RESULT:       ALL TESTS PASSED");
        else
            $display("RESULT:       FAILED");
        $display("=================================================");
    $finish;
    end
endmodule