`timescale 1ns/1ps
// Signed 16-bit mono PCM; the upstream source must provide a synchronous
// ready/valid stream in pixel_clk. Every input sample is sent three times.
module pcm_voice_player #(
    parameter integer CLOCK_HZ = 75000000,
    parameter integer AUDIO_HZ = 48000
)(
    input wire pixel_clk, rst, enable,
    input wire sample_valid,
    input wire signed [15:0] sample_data,
    output wire sample_ready,
    output reg audio_valid,
    output reg signed [23:0] audio_data,
    output reg [31:0] samples_played,
    output reg underrun
);
    reg [31:0] phase_acc;
    reg [1:0] repeat_index;
    reg signed [15:0] held_sample;
    wire [32:0] phase_sum = {1'b0, phase_acc} + AUDIO_HZ;
    wire tick = phase_sum >= CLOCK_HZ;
    assign sample_ready = enable && tick && repeat_index == 0;
    always @(posedge pixel_clk) begin
        if (rst || !enable) begin
            phase_acc <= 0;
            repeat_index <= 0;
            held_sample <= 0;
            audio_valid <= 0;
            audio_data <= 0;
            samples_played <= 0;
            underrun <= 0;
        end else begin
            audio_valid <= 0;
            if (tick) begin
                phase_acc <= phase_sum - CLOCK_HZ;
                audio_valid <= 1;
                if (repeat_index == 0) begin
                    if (sample_valid) begin
                        held_sample <= sample_data;
                        audio_data <= {sample_data,8'b0};
                        samples_played <= samples_played + 1'b1;
                        repeat_index <= 1;
                    end else begin
                        audio_data <= 0;
                        underrun <= 1;
                    end
                end else begin
                    audio_data <= {held_sample,8'b0};
                    repeat_index <= repeat_index == 2 ? 0 : repeat_index + 1'b1;
                end
            end else phase_acc <= phase_sum[31:0];
        end
    end
endmodule
