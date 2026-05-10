`timescale 1ns/1ps

module array_with_buf_tb;
    parameter int N        = 8;
    parameter int WIDTH    = 16;
    parameter int N_TESTS  = 100;
    parameter int TILE_LEN = N * N;
    parameter int TOTAL    = N_TESTS * TILE_LEN;
    
    logic clk;
    logic rst;
    logic load_weight;
    logic signed [15:0] b_in  [N][N];
    logic signed [31:0] c_out [N];
    logic                         wr_en;
    logic [$clog2(N)-1:0]         wr_addr;
    logic signed [WIDTH-1:0]      wr_data [N];
    logic [$clog2(N)-1:0]         rd_addr;
    logic signed [WIDTH-1:0]      rd_data [N];
    logic stream_active;
    logic signed [WIDTH-1:0] a_in_to_array [N];
  
    always_comb begin
        for (int k = 0; k < N; k++)
            a_in_to_array[k] = stream_active ? rd_data[k] : '0;
    end

    a_tile_buffer #(.WIDTH(WIDTH), .N(N)) abuf (
        .clk     (clk),
        .wr_en   (wr_en),
        .wr_addr (wr_addr),
        .wr_data (wr_data),
        .rd_addr (rd_addr),
        .rd_data (rd_data)
    );

    systolic_array #(.N(N)) dut (
        .clk         (clk),
        .rst         (rst),
        .load_weight (load_weight),
        .a_in        (a_in_to_array),
        .b_in        (b_in),
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
        clk           = 0;
        rst           = 1;
        load_weight   = 0;
        wr_en         = 0;
        wr_addr       = 0;
        rd_addr       = 0;
        stream_active = 0;
        for (int k = 0; k < N; k++) wr_data[k] = 0;
        for (int i = 0; i < N; i++)
            for (int j = 0; j < N; j++)
                b_in[i][j] = 0;
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
            rst           <= 1;
            stream_active <= 0;
            wr_en         <= 0;
            rd_addr       <= 0;
            repeat (2) @(posedge clk);

// Pre-load A tile into buffer (8 cycles)
            for (int r = 0; r < N; r++) begin
                wr_en   <= 1;
                wr_addr <= r;
                for (int k = 0; k < N; k++)
                    wr_data[k] <= a_tile_all[idx(T, r, k)];
                @(posedge clk);
            end
            wr_en <= 0;
            rd_addr <= 0;

// Drop reset and load weights (this edge also prefetches row 0)
            rst <= 0;
            for (int i = 0; i < N; i++)
                for (int j = 0; j < N; j++)
                    b_in[i][j] <= b_tile_all[idx(T, i, j)];
            load_weight <= 1;
            @(posedge clk);
            load_weight <= 0;

// Stream A rows 0..7 from buffer
            stream_active <= 1;
            for (int r = 1; r < N; r++) begin
                rd_addr <= r;
                @(posedge clk);
            end
            @(posedge clk);
            stream_active <= 0;

// Drain pipeline
            repeat (6) @(posedge clk);

// Capture & check 8 rows of C
            for (int row = 0; row < N; row++) begin
                @(posedge clk); #1;
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