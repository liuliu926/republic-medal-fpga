`timescale 1ns/1ps
// Active-low KEY1: release emits short press, threshold emits one long press.
// Enabling while a key is already held must never synthesize a new press.
module portrait_focus_key #(
    parameter integer DEBOUNCE_CYCLES = 500000,
    parameter integer LONG_CYCLES = 40000000
)(
    input wire clk, rst, key_n, enable,
    output reg short_pulse, long_pulse
);
    reg [1:0] sync_key;
    reg stable_n, armed, held, fired;
    reg [19:0] debounce_count;
    reg [25:0] hold_count;
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            sync_key<=3; stable_n<=1; armed<=0; held<=0; fired<=0;
            debounce_count<=0; hold_count<=0; short_pulse<=0; long_pulse<=0;
        end else begin
            sync_key <= {sync_key[0],key_n};
            short_pulse<=0; long_pulse<=0;
            if (sync_key[1] == stable_n) debounce_count<=0;
            else if (debounce_count == DEBOUNCE_CYCLES-1) begin
                stable_n<=sync_key[1]; debounce_count<=0;
            end else debounce_count<=debounce_count+1'b1;
            if (!enable) begin
                armed<=0; held<=0; fired<=0; hold_count<=0;
            end else if (stable_n) begin
                armed<=1; held<=0; fired<=0; hold_count<=0;
                if (held && !fired) short_pulse<=1;
            end else if (armed) begin
                held<=1;
                if (!fired) begin
                    if (hold_count == LONG_CYCLES-1) begin
                        long_pulse<=1; fired<=1;
                    end else hold_count<=hold_count+1'b1;
                end
            end
        end
    end
endmodule
