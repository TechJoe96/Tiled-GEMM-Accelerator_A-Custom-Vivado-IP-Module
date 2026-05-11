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

    logic done_latched;
    always_ff @(posedge clk) begin
        if (rst)                  done_latched <= 1'b0;
        else if (start_pulse)     done_latched <= 1'b0;
        else if (fsm_done_pulse)  done_latched <= 1'b1;
    end

    // -------- C tile capture: triggered by fsm_done_pulse --------
    // At the edge where fsm_done_pulse fires, c_out has NOT yet advanced to
    // row 0 (it appears on the NEXT edge). So we start capturing one cycle
    // after the pulse, indexed by cap_idx = 0..N-1.
    logic [3:0] cap_idx;
    logic signed [31:0] c_latched [N][N];

    always_ff @(posedge clk) begin
        if (rst)                  cap_idx <= 4'hF;     // idle sentinel
        else if (fsm_done_pulse)  cap_idx <= 4'd0;
        else if (cap_idx < N)     cap_idx <= cap_idx + 4'd1;
    end

    always_ff @(posedge clk) begin
        if (cap_idx < N) begin
            c_latched[cap_idx][0] <= c_out[0];
            c_latched[cap_idx][1] <= c_out[1];
            c_latched[cap_idx][2] <= c_out[2];
            c_latched[cap_idx][3] <= c_out[3];
            c_latched[cap_idx][4] <= c_out[4];
            c_latched[cap_idx][5] <= c_out[5];
            c_latched[cap_idx][6] <= c_out[6];
            c_latched[cap_idx][7] <= c_out[7];
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