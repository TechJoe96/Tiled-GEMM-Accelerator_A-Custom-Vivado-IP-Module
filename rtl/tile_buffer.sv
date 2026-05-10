`timescale 1ns/1ps
module tile_buffer_tb;
    parameter int WIDTH      = 16;
    parameter int DEPTH      = 64;
    parameter int ADDR_WIDTH = $clog2(DEPTH);
    logic clk;
    logic                       wr_en;
    logic [ADDR_WIDTH-1:0]      wr_addr;
    logic signed [WIDTH-1:0]    wr_data;
    logic [ADDR_WIDTH-1:0]      rd_addr;
    logic signed [WIDTH-1:0]    rd_data;
tile_buffer #(.WIDTH (WIDTH), .DEPTH (DEPTH)) dut (
        .clk     (clk),
        .wr_en   (wr_en),
        .wr_addr (wr_addr),
        .wr_data (wr_data),
        .rd_addr (rd_addr),
        .rd_data (rd_data)
    );
always #5 clk = ~clk;
logic signed [WIDTH-1:0] expected [DEPTH];
int errors;
initial begin
        clk = 0; wr_en = 0; wr_addr = 0; wr_data = 0; rd_addr = 0;
        @(posedge clk);
        $display("Writing pattern to %0d addresses...", DEPTH);
        for (int i = 0; i < DEPTH; i++) begin
            expected[i] = i*3 - 100;
            wr_en   = 1;
            wr_addr = i;
            wr_data = expected[i];
            @(posedge clk);
        end
        wr_en = 0; wr_data = 0;
        @(posedge clk);
        $display("Reading back and verifying...");
        errors = 0;
        for (int i = 0; i < DEPTH; i++) begin
            rd_addr = i;
            @(posedge clk); #1;
            if (rd_data !== expected[i]) begin
                $display("MISMATCH addr=%0d: got=%0d expected=%0d", i, rd_data, expected[i]);
                errors++;
            end
        end
        if (errors == 0)
            $display("PASS: all %0d addresses match expected", DEPTH);
        else
            $display("FAIL: %0d mismatches out of %0d", errors, DEPTH);
        $finish;
    end
endmodule