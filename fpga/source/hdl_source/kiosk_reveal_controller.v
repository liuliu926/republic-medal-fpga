// Reveal independent text layers in KEY4 steps, or on a timed auto tour.
// page_changed must be a one-cycle pulse in clk; language changes do not
// reset the reveal position. The UI controls enabled/quiz routing.
module kiosk_reveal_controller #(
    parameter integer CLK_HZ=50_000_000,
    parameter integer STEP_SECONDS=8
)(
    input wire clk, input wire rst, input wire page_changed,
    input wire enabled, input wire auto_mode, input wire paused,
    input wire key_confirm_pulse, input wire [2:0] max_reveal_step,
    output reg [2:0] reveal_step, output reg advance_page_pulse
);
    localparam [31:0] STEP_TICKS=CLK_HZ*STEP_SECONDS;
    reg [31:0] tick_count;
    reg auto_complete;
    always @(posedge clk) begin
        if(rst) begin
            reveal_step<=0; advance_page_pulse<=0; tick_count<=0; auto_complete<=0;
        end else begin
            advance_page_pulse<=0;
            if(page_changed || !enabled) begin
                reveal_step<=0; tick_count<=0; auto_complete<=0;
            end else if(auto_mode) begin
                if(!paused && !auto_complete) begin
                    if(tick_count>=STEP_TICKS-1) begin
                        tick_count<=0;
                        if(reveal_step<max_reveal_step) reveal_step<=reveal_step+1'b1;
                        else begin advance_page_pulse<=1; auto_complete<=1; end
                    end else tick_count<=tick_count+1'b1;
                end
            end else begin
                tick_count<=0; auto_complete<=0;
                if(key_confirm_pulse && reveal_step<max_reveal_step)
                    reveal_step<=reveal_step+1'b1;
            end
        end
    end
endmodule
