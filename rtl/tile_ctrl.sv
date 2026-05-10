`timescale 1ns/1ps
module tile_ctrl #(
    parameter int N            = 8,
    parameter int ADDR_WIDTH   = $clog2(N),
    parameter int DRAIN_CYCLES = 6
) (
    input  logic                       clk,
    input  logic                       rst,
    input  logic                       start,
    output logic                       load_weight,
    output logic [ADDR_WIDTH-1:0]      a_rd_addr,
    output logic                       stream_active,
    output logic                       done
);

    typedef enum logic [2:0] {
        S_IDLE         = 3'd0,
        S_LOAD_WEIGHTS = 3'd1,
        S_STREAM       = 3'd2,
        S_DRAIN        = 3'd3,
        S_DONE         = 3'd4
    } state_t;
    state_t state, next_state;
    logic [3:0] cycle_count;


// State register
    always_ff @(posedge clk) begin
        if (rst) state <= S_IDLE;
        else     state <= next_state;
    end
// Next-state logic
    always_comb begin
        case (state)
            S_IDLE:
                if (start) next_state = S_LOAD_WEIGHTS;
                else       next_state = S_IDLE;
            S_LOAD_WEIGHTS:
                next_state = S_STREAM;
            S_STREAM:
                if (cycle_count == N - 1) next_state = S_DRAIN;
                else                       next_state = S_STREAM;
            S_DRAIN:
                if (cycle_count == DRAIN_CYCLES - 1) next_state = S_DONE;
                else                                  next_state = S_DRAIN;
            S_DONE:
                next_state = S_IDLE;
            default:
                next_state = S_IDLE;
        endcase
    end
// Cycle counter — resets on state change
    always_ff @(posedge clk) begin
        if (rst)                       cycle_count <= 0;
        else if (state != next_state)  cycle_count <= 0;
        else                            cycle_count <= cycle_count + 1;
    end
// Output decoding
    always_comb begin
        load_weight   = 1'b0;
        stream_active = 1'b0;
        done          = 1'b0;
        a_rd_addr     = '0;
        case (state)
            S_LOAD_WEIGHTS: begin
                load_weight = 1'b1;
                a_rd_addr   = '0;
            end
            S_STREAM: begin
                stream_active = 1'b1;
                if (cycle_count == N - 1)
                    a_rd_addr = N - 1;
                else
                    a_rd_addr = cycle_count + 1;
            end
            S_DONE:
                done = 1'b1;
            default: begin
            end
        endcase
    end
endmodule