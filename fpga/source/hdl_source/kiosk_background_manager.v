// One-clock background load coordinator. The caller must synchronize the
// frame_boundary pulse into clk and must expose a loader accepting one start
// pulse while idle. Front/back buffers contain complete 720p frames. The
// external compositor must finish all required layers before a frame commits.
module kiosk_background_manager (
    input wire clk, input wire rst,
    input wire request_valid, input wire [15:0] request_generation,
    input wire [87:0] request_sfn,
    input wire frame_boundary,
    output reg load_start, output reg [87:0] load_sfn,
    output reg [1:0] load_frame_index,
    input wire load_done, input wire load_error, input wire load_recovery_required,
    output reg compose_start, output reg [1:0] compose_frame_index,
    output reg [15:0] compose_generation,
    input wire compose_done, input wire compose_error, input wire compose_recovery_required,
    output reg front_valid, output reg [1:0] front_frame_index,
    output reg [15:0] front_generation,
    output reg error_valid, output reg [15:0] error_generation,
    output wire blocked, output wire busy
);
    localparam IDLE=3'd0, LOADING=3'd1, COMPOSING=3'd2, WAIT_FRAME=3'd3, BLOCKED=3'd4;
    reg [2:0] state;
    reg pending;
    reg [15:0] pending_generation, active_generation;
    reg [87:0] pending_sfn;
    reg [1:0] active_frame_index;
    assign blocked = state == BLOCKED;
    assign busy = (state != IDLE) || pending;

    always @(posedge clk) begin
        if (rst) begin
            state<=IDLE; pending<=0; pending_generation<=0; active_generation<=0;
            pending_sfn<=0; active_frame_index<=0; load_start<=0; load_sfn<=0;
            load_frame_index<=0; front_valid<=0; front_frame_index<=0; front_generation<=0;
            compose_start<=0; compose_frame_index<=0; compose_generation<=0;
            error_valid<=0; error_generation<=0;
        end else begin
            load_start<=0;
            compose_start<=0;
            error_valid<=0;
            // A later request supersedes an earlier pending request.
            if (request_valid && state!=BLOCKED) begin
                pending<=1; pending_generation<=request_generation; pending_sfn<=request_sfn;
            end
            case (state)
                IDLE: if (pending && !request_valid) begin
                    pending<=0;
                    active_generation<=pending_generation;
                    active_frame_index<=front_frame_index==0 ? 2'd1 : 2'd0;
                    load_frame_index<=front_frame_index==0 ? 2'd1 : 2'd0;
                    load_sfn<=pending_sfn; load_start<=1;
                    state<=LOADING;
                end
                LOADING: if (load_done) begin
                    if (load_recovery_required) begin
                        pending<=0; error_valid<=1; error_generation<=active_generation;
                        state<=BLOCKED;
                    end else if (load_error) begin
                        error_valid<=1; error_generation<=active_generation; state<=IDLE;
                    end else if (pending || request_valid) begin
                        // A newer request arrived during this read; keep front.
                        state<=IDLE;
                    end else begin
                        compose_generation<=active_generation;
                        compose_frame_index<=active_frame_index;
                        compose_start<=1;
                        state<=COMPOSING;
                    end
                end
                COMPOSING: if (compose_done) begin
                    if (compose_recovery_required) begin
                        pending<=0; error_valid<=1; error_generation<=active_generation;
                        state<=BLOCKED;
                    end else if (compose_error) begin
                        error_valid<=1; error_generation<=active_generation; state<=IDLE;
                    end else if (pending || request_valid) state<=IDLE;
                    else state<=WAIT_FRAME;
                end
                WAIT_FRAME: begin
                    if (request_valid || pending) state<=IDLE;
                    else if (frame_boundary) begin
                        front_frame_index<=active_frame_index;
                        front_generation<=active_generation;
                        front_valid<=1; state<=IDLE;
                    end
                end
                BLOCKED: ; // Physical loader/memory must be reset together.
                default: state<=BLOCKED;
            endcase
        end
    end
endmodule
