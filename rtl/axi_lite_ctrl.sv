`timescale 1ns/1ps
module axi_lite_ctrl #(
    parameter int ADDR_WIDTH = 4,
    parameter int DATA_WIDTH = 32
) (
    input  logic                       s_axi_aclk,
    input  logic                       s_axi_aresetn,
    input  logic [ADDR_WIDTH-1:0]      s_axi_awaddr,
    input  logic                       s_axi_awvalid,
    output logic                       s_axi_awready,
    input  logic [DATA_WIDTH-1:0]      s_axi_wdata,
    input  logic [DATA_WIDTH/8-1:0]    s_axi_wstrb,
    input  logic                       s_axi_wvalid,
    output logic                       s_axi_wready,
    output logic [1:0]                 s_axi_bresp,
    output logic                       s_axi_bvalid,
    input  logic                       s_axi_bready,
    input  logic [ADDR_WIDTH-1:0]      s_axi_araddr,
    input  logic                       s_axi_arvalid,
    output logic                       s_axi_arready,
    output logic [DATA_WIDTH-1:0]      s_axi_rdata,
    output logic [1:0]                 s_axi_rresp,
    output logic                       s_axi_rvalid,
    input  logic                       s_axi_rready,
    output logic                       start_pulse,
    input  logic                       done_flag
);
    logic rst;
    assign rst = ~s_axi_aresetn;
    localparam logic [ADDR_WIDTH-1:0] ADDR_CTRL   = 4'h0;
    localparam logic [ADDR_WIDTH-1:0] ADDR_STATUS = 4'h4;
    typedef enum logic [1:0] { W_IDLE, W_RESP } w_state_t;
    w_state_t w_state;

    always_ff @(posedge s_axi_aclk) begin
        if (rst) begin
            w_state       <= W_IDLE;
            s_axi_awready <= 1'b0;
            s_axi_wready  <= 1'b0;
            s_axi_bvalid  <= 1'b0;
            s_axi_bresp   <= 2'b00;
        end else begin
            case (w_state)
                W_IDLE: begin
                    s_axi_awready <= 1'b1;
                    s_axi_wready  <= 1'b1;
                    if (s_axi_awvalid && s_axi_wvalid) begin
                        s_axi_awready <= 1'b0;
                        s_axi_wready  <= 1'b0;
                        s_axi_bvalid  <= 1'b1;
                        s_axi_bresp   <= 2'b00;
                        w_state       <= W_RESP;
                    end
                end
                W_RESP: begin
                    if (s_axi_bready) begin
                        s_axi_bvalid <= 1'b0;
                        w_state      <= W_IDLE;
                    end
                end
            endcase
        end
    end 
    logic ctrl_start_w;
    always_ff @(posedge s_axi_aclk) begin
        if (rst) begin
            ctrl_start_w <= 1'b0;
        end else begin
            ctrl_start_w <= 1'b0;
            if (w_state == W_IDLE && s_axi_awvalid && s_axi_wvalid) begin
                if (s_axi_awaddr == ADDR_CTRL && s_axi_wstrb[0]) begin
                    ctrl_start_w <= s_axi_wdata[0];
                end
            end
        end
    end
    assign start_pulse = ctrl_start_w;
    typedef enum logic [0:0] { R_IDLE, R_DATA } r_state_t;
    r_state_t r_state;

    always_ff @(posedge s_axi_aclk) begin
        if (rst) begin
            r_state       <= R_IDLE;
            s_axi_arready <= 1'b0;
            s_axi_rvalid  <= 1'b0;
            s_axi_rdata   <= '0;
            s_axi_rresp   <= 2'b00;
        end else begin
            case (r_state)
                R_IDLE: begin
                    s_axi_arready <= 1'b1;
                    if (s_axi_arvalid) begin
                        s_axi_arready <= 1'b0;
                        s_axi_rvalid  <= 1'b1;
                        s_axi_rresp   <= 2'b00;
                        case (s_axi_araddr)
                            ADDR_STATUS: s_axi_rdata <= {31'b0, done_flag};
                            ADDR_CTRL:   s_axi_rdata <= '0;
                            default:     s_axi_rdata <= '0;
                        endcase
                        r_state <= R_DATA;
                    end
                end
                R_DATA: begin
                    if (s_axi_rready) begin
                        s_axi_rvalid <= 1'b0;
                        r_state      <= R_IDLE;
                    end
                end
            endcase
        end
    end
endmodule