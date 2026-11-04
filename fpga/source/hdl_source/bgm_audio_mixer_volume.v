`timescale 1ns/1ps
// Permanent 16-kHz mono BGM stream plus the existing 48-kHz voice stream.
// The SD reader reserves a whole 512-byte sector before issuing its read.
// Navigation must NOT reset this module or its FIFO. Only system reset does.
module bgm_audio_mixer #(
    parameter integer CLOCK_HZ = 75000000,
    parameter integer AUDIO_HZ = 48000,
    parameter integer PREFILL_SAMPLES = 512,
    parameter integer DUCK_HOLD_TICKS = 8191
)(
    input wire sd_clk, pixel_clk, rst, pixel_rst,
    input wire music_enable,
    input wire [3:0] volume_level,
    input wire bgm_valid,
    input wire [7:0] bgm_data,
    output wire bgm_room,
    output wire bgm_urgent,
    input wire voice_enable, voice_valid,
    input wire signed [23:0] voice_data,
    output wire audio_valid,
    output wire signed [23:0] audio_data,
    output reg bgm_underrun,
    output reg bgm_overflow,
    output wire bgm_playing
);
    reg [7:0] low_byte;
    reg low_valid;
    wire fifo_full, fifo_empty;
    wire [15:0] fifo_data;
    wire [9:0] write_used, read_used;
    wire take_sample;
    // This IP holds at most 1023 samples. Conservatively reserve 32 extra
    // samples beyond the 256 needed by one sector; read-pointer CDC can only
    // underestimate free space. File sizes and loop boundaries must be even.
    assign bgm_room = !rst && !fifo_full && write_used <= 10'd735;
    assign bgm_urgent = write_used < 10'd256;
    always @(posedge sd_clk or posedge rst) begin
        if (rst) begin low_byte<=0; low_valid<=0; bgm_overflow<=0; end
        else if (bgm_valid) begin
            low_valid <= !low_valid;
            if (!low_valid) low_byte <= bgm_data;
            else if (fifo_full) bgm_overflow <= 1;
        end
    end
    wfifo_32_32_512 #(.DATA_WIDTH_W(16), .DATA_WIDTH_R(16),
        .ADDR_WIDTH_W(10), .ADDR_WIDTH_R(10),
        .AL_FULL_NUM(1000), .AL_EMPTY_NUM(256)) bgm_fifo (
        .rst(rst), .clkw(sd_clk), .clkr(pixel_clk),
        .we(bgm_valid && low_valid && !fifo_full), .di({bgm_data,low_byte}),
        .re(take_sample), .dout(fifo_data), .valid(),
        .full_flag(fifo_full), .empty_flag(fifo_empty), .afull(), .aempty(),
        .wrusedw(write_used), .rdusedw(read_used));

    // 75 MHz / 48 kHz is exactly 1562.5: alternate 1562/1563 cycles.
    // Integer-ratio test clocks are supported too. No runtime division.
    localparam integer DIV_BASE = CLOCK_HZ / AUDIO_HZ;
    localparam integer DIV_WIDTH = $clog2(DIV_BASE + 1);
    localparam integer HALF_STEP = (CLOCK_HZ % AUDIO_HZ) != 0;
    reg [DIV_WIDTH-1:0] divider;
    reg half_step;
    wire output_tick = divider == (DIV_BASE-1 + (HALF_STEP && half_step));
    reg playing;
    reg [1:0] repeat_index;
    reg signed [15:0] music_held;
    assign bgm_playing = playing;
    assign take_sample = music_enable && output_tick && playing && repeat_index==0 && !fifo_empty;
    wire signed [15:0] music_sample = !music_enable || !playing ? 16'sd0 :
        ((repeat_index==0) ? (fifo_empty ? 16'sd0 : $signed(fifo_data)) : music_held);

    reg signed [23:0] voice_held;
    reg voice_seen;
    reg [1:0] missed_voice_ticks;
    reg [12:0] duck_hold;
    wire voice_fresh = voice_valid || voice_seen;
    wire voice_recent = voice_fresh || missed_voice_ticks < 2;
    wire signed [23:0] voice_sample = !voice_enable || !voice_recent ? 24'sd0 :
        (voice_valid ? voice_data : voice_held);
    wire duck = duck_hold != 0 ||
        (voice_enable && voice_sample[23:8] != 0);
    wire signed [23:0] music_wide = {music_sample,8'b0};
    wire signed [23:0] music_attenuated = duck ? (music_wide >>> 3) : (music_wide >>> 2);
    wire signed [24:0] mixed = {voice_sample[23],voice_sample} +
        {music_attenuated[23],music_attenuated};
    wire signed [23:0] limited = mixed[24] != mixed[23] ?
        (mixed[24] ? 24'sh800000 : 24'sh7fffff) : mixed[23:0];
    audio_volume_percent_pipeline u_volume_percent(
        .clk(pixel_clk),.rst(pixel_rst),.sample_valid(output_tick),
        .sample_in(limited),.step(volume_level),
        .sample_out_valid(audio_valid),.sample_out(audio_data));

    always @(posedge pixel_clk or posedge pixel_rst) begin
        if (pixel_rst) begin
            divider<=0; half_step<=0; playing<=0; repeat_index<=0;
            music_held<=0; voice_held<=0; voice_seen<=0;
            missed_voice_ticks<=3; duck_hold<=0;
            bgm_underrun<=0;
        end else begin
            if (output_tick) begin divider<=0; half_step<=!half_step; end
            else divider<=divider+1'b1;
            if (!voice_enable) begin
                voice_held<=0; voice_seen<=0; missed_voice_ticks<=3; duck_hold<=0;
            end else if (voice_valid) begin
                voice_held<=voice_data; voice_seen<=1;
            end
            if (!playing && read_used >= PREFILL_SAMPLES) begin
                playing<=1; repeat_index<=0;
            end
            if (output_tick) begin
                if (voice_enable) begin
                    voice_seen<=0;
                    if (voice_fresh) missed_voice_ticks<=0;
                    else if (missed_voice_ticks!=3) missed_voice_ticks<=missed_voice_ticks+1'b1;
                    if (voice_sample[23:8] != 0) duck_hold<=DUCK_HOLD_TICKS;
                    else if (duck_hold != 0) duck_hold<=duck_hold-1'b1;
                end
                if (playing && music_enable) begin
                    if (repeat_index==0) begin
                        if (!fifo_empty) begin music_held<=fifo_data; repeat_index<=1; end
                        else begin
                            music_held<=0; playing<=0; repeat_index<=0; bgm_underrun<=1;
                        end
                    end else repeat_index<=repeat_index==2 ? 0 : repeat_index+1'b1;
                end
            end
        end
    end
endmodule
