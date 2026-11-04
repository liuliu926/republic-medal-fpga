from pathlib import Path
root=Path(__file__).resolve().parents[1]
p=root/'fpga/user_source_720p/hdl_source'
s=(p/'top_fat32_audio_tone_pilot.v').read_text(encoding='utf-8')
# This isolated manual-audio pilot omits autoplay to fit the near-full FPGA.
# The verified full-feature build remains untouched.
start=s.index('kiosk_mode u_kiosk_mode (')
end=s.index('kiosk_nav #(',start)
s=s[:start]+'''assign auto_mode = 1'b0;
assign exit_to_home_pulse = 1'b0;
assign prompt_visible = 1'b0;
assign auto_level = 0; assign auto_person = 0; assign auto_section = 0; assign auto_page = 0;
\n'''+s[end:]
needle='fat32_shared_layer_frontend u_fat32_shared ('
replacement='''wire voice_requested = article_text_mode && display_level == 2 &&
    display_person == 0 && display_section == 0 && display_page == 1 && !auto_mode;
wire voice_start, voice_ready, voice_valid, voice_active, voice_done, voice_error;
wire [7:0] voice_byte;
wire voice_audio_valid, voice_underrun;
wire signed [23:0] voice_audio_data;
wire [31:0] voice_samples;
pcm_audio_bridge u_voice (
    .sd_clk(sd_card_clk), .pixel_clk(video_clk), .rst(rst_all), .pixel_rst(rst_video),
    .requested(voice_requested), .start_allowed(!diag_busy && !sequence_start),
    .raw_valid(voice_valid), .raw_ready(voice_ready), .raw_data(voice_byte),
    .raw_active(voice_active), .raw_done(voice_done), .raw_error(voice_error),
    .raw_start(voice_start), .audio_valid(voice_audio_valid), .audio_data(voice_audio_data),
    .samples_played(voice_samples), .underrun(voice_underrun));
fat32_shared_reused_pcm_frontend u_fat32_shared ('''
assert needle in s
s=s.replace(needle,replacement,1)
s=s.replace('    .start(sequence_start), .asset_mode(sequence_asset_mode),', '''    .pcm_start(voice_start), .pcm_ready(voice_ready), .pcm_valid(voice_valid),
    .pcm_data(voice_byte), .pcm_active(voice_active), .pcm_done(voice_done), .pcm_error(voice_error),
    .start(sequence_start), .asset_mode(sequence_asset_mode),''',1)
s=s.replace('    .reveal_step(nav_page_sync2[2:0]),', '''    .voice_active(nav_level_sync2 == 2 && nav_person_sync2 == 0 &&
        nav_section_sync2 == 0 && nav_page_sync2 == 1 && !auto_mode_sync2),
    .voice_samples(voice_samples), .reveal_step(nav_page_sync2[2:0]),''',1)
s=s.replace('.I_audio_valid      (tone_valid)', '.I_audio_valid      (voice_audio_valid)',1)
s=s.replace('.I_audio_left_data  (tone_sample)', '.I_audio_left_data  (voice_audio_data)',1)
s=s.replace('.I_audio_right_data (tone_sample)', '.I_audio_right_data (voice_audio_data)',1)
start=s.index('// Low-level one-second-on/one-second-off HDMI audio diagnostic tone.')
end=s.index('// ===================== HDMI 1.4b',start)
s=s[:start]+'''// Derive ACR cadence from the actual voice samples; no second sample clock.
reg [5:0] tone_acr_count;
reg tone_acr_valid;
always @(posedge video_clk or posedge rst_video) begin
    if (rst_video) begin tone_acr_count<=0; tone_acr_valid<=0; end
    else begin
        tone_acr_valid<=0;
        if (voice_audio_valid) begin
            if (tone_acr_count==47) begin tone_acr_count<=0; tone_acr_valid<=1; end
            else tone_acr_count<=tone_acr_count+1'b1;
        end
    end
end
'''+s[end:]
(p/'top_fat32_voice_pilot.v').write_text(s,encoding='utf-8')
print('Prepared isolated voice pilot top')
