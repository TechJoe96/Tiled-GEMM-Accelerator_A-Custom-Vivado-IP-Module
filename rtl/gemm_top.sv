`timescale 1ns/1ps

module gemm_top #(
    parameter int N          = 8,
    parameter int WIDTH      = 16,
    parameter int ADDR_WIDTH = 9
) (
    input  logic                       s_axi_aclk,
    input  logic                       s_axi_aresetn,

    input  logic [ADDR_WIDTH-1:0]      s_axi_awaddr,
    input  logic                       s_axi_awvalid,
    output logic                       s_axi_awready,
    input  logic [31:0]                s_axi_wdata,
    input  logic [3:0]                 s_axi_wstrb,
    input  logic                       s_axi_wvalid,
    output logic                       s_axi_wready,
    output logic [1:0]                 s_axi_bresp,
    output logic                       s_axi_bvalid,
    input  logic                       s_axi_bready,

    input  logic [ADDR_WIDTH-1:0]      s_axi_araddr,
    input  logic                       s_axi_arvalid,
    output logic                       s_axi_arready,
    output logic [31:0]                s_axi_rdata,
    output logic [1:0]                 s_axi_rresp,
    output logic                       s_axi_rvalid,
    input  logic                       s_axi_rready,

    input  logic                       a_wr_en,
    input  logic [$clog2(N)-1:0]       a_wr_addr,
    input  logic signed [WIDTH-1:0]    a_wr_data [N],
    input  logic                       b_wr_en,
    input  logic [$clog2(N)-1:0]       b_wr_addr,
    input  logic signed [WIDTH-1:0]    b_wr_data [N]
);

    logic clk;
    logic rst;
    assign clk = s_axi_aclk;
    assign rst = ~s_axi_aresetn;

    logic                       start_pulse;
    logic                       fsm_done_pulse;
    logic [$clog2(N)-1:0]       a_rd_addr;
    logic                       stream_active;
    logic                       load_weight;

    logic signed [WIDTH-1:0]    a_rd_data [N];
    logic signed [WIDTH-1:0]    b_rd_data [N][N];
    logic signed [31:0]         c_out [N];

    logic signed [WIDTH-1:0] a_in_to_array [N];
    always_comb begin
        for (int k = 0; k < N; k++)
            a_in_to_array[k] = stream_active ? a_rd_data[k] : '0;
    end

    // Done latch
    logic done_latched;
    always_ff @(posedge clk) begin
        if (rst)                  done_latched <= 1'b0;
        else if (start_pulse)     done_latched <= 1'b0;
        else if (fsm_done_pulse)  done_latched <= 1'b1;
    end

    // -------- C tile capture: time-based from start --------
    // Counter starts at 1 at the edge after start_pulse, increments each cycle.
    // Per Step 6.2 timing: row K of C is fully aligned on c_out going INTO
    // edge W+(18+K), which means counter == 17+K going in.
    // So capture window: counter == 17..24, with index (counter - 17).
    logic [4:0] cycle_after_start;
    logic signed [31:0] c_latched [N][N];

    always_ff @(posedge clk) begin
        if (rst)                                              cycle_after_start <= 0;
        else if (start_pulse)                                 cycle_after_start <= 1;
        else if (cycle_after_start > 0 && cycle_after_start < 25)
                                                              cycle_after_start <= cycle_after_start + 1;
        else                                                  cycle_after_start <= 0;
    end

    always_ff @(posedge clk) begin
        if (cycle_after_start >= 17 && cycle_after_start <= 24) begin
            for (int j = 0; j < N; j++)
                c_latched[cycle_after_start - 17][j] <= c_out[j];
        end
    end
    // -------- end C capture --------

    axi_lite_ctrl #(.N(N), .ADDR_WIDTH(ADDR_WIDTH)) axi_ctrl (
        .s_axi_aclk    (s_axi_aclk),
        .s_axi_aresetn (s_axi_aresetn),
        .s_axi_awaddr  (s_axi_awaddr),
        .s_axi_awvalid (s_axi_awvalid),
        .s_axi_awready (s_axi_awready),
        .s_axi_wdata   (s_axi_wdata),
        .s_axi_wstrb   (s_axi_wstrb),
        .s_axi_wvalid  (s_axi_wvalid),
        .s_axi_wready  (s_axi_wready),
        .s_axi_bresp   (s_axi_bresp),
        .s_axi_bvalid  (s_axi_bvalid),
        .s_axi_bready  (s_axi_bready),
        .s_axi_araddr  (s_axi_araddr),
        .s_axi_arvalid (s_axi_arvalid),
        .s_axi_arready (s_axi_arready),
        .s_axi_rdata   (s_axi_rdata),
        .s_axi_rresp   (s_axi_rresp),
        .s_axi_rvalid  (s_axi_rvalid),
        .s_axi_rready  (s_axi_rready),
        .start_pulse   (start_pulse),
        .done_flag     (done_latched),
        .c_latched     (c_latched)
    );

    tile_ctrl #(.N(N), .DRAIN_CYCLES(6)) ctrl (
        .clk           (clk),
        .rst           (rst),
        .start         (start_pulse),
        .load_weight   (load_weight),
        .a_rd_addr     (a_rd_addr),
        .stream_active (stream_active),
        .done          (fsm_done_pulse)
    );

    a_tile_buffer #(.WIDTH(WIDTH), .N(N)) abuf (
        .clk(clk), .wr_en(a_wr_en), .wr_addr(a_wr_addr), .wr_data(a_wr_data),
        .rd_addr(a_rd_addr), .rd_data(a_rd_data)
    );

    b_tile_buffer #(.WIDTH(WIDTH), .N(N)) bbuf (
        .clk(clk), .wr_en(b_wr_en), .wr_addr(b_wr_addr), .wr_data(b_wr_data),
        .rd_data(b_rd_data)
    );

    systolic_array #(.N(N)) array (
        .clk(clk), .rst(rst), .load_weight(load_weight),
        .a_in(a_in_to_array), .b_in(b_rd_data), .c_out(c_out)
    );

endmodule