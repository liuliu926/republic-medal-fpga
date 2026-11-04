from pathlib import Path
p=Path(__file__).resolve().parents[1]/'fpga/user_source_720p/hdl_source'
s=(p/'home_text_mask_voice_pilot.v').read_text(encoding='utf-8')
start=s.index('    reg [9:0] voice_year_limit, voice_text_limit;')
end=s.index('    reg [10:0] x;',start)
block='''    // Four audio phrases share a compact per-character timing generator.
    reg [9:0] voice_year_limit, voice_text_limit;
    reg [4:0] voice_index;
    reg [17:0] voice_next;
    always @(posedge video_clk or posedge video_rst) begin
      if (video_rst || !voice_active) begin
        voice_year_limit<=10'd2; voice_text_limit<=10'd183;
        voice_index<=0; voice_next<=0;
      end else if (voice_index < 21 && voice_samples[17:0] >= voice_next) begin
        if (voice_index < 4) voice_year_limit <= voice_year_limit + 10'd18;
        else voice_text_limit <= voice_text_limit + 10'd25;
        if (voice_index == 3) voice_next <= 18'd34240;
        else if (voice_index == 10) voice_next <= 18'd80080;
        else if (voice_index == 14) voice_next <= 18'd110960;
        else if (voice_index < 3) voice_next <= voice_next + 18'd8560;
        else if (voice_index < 10) voice_next <= voice_next + 18'd6548;
        else if (voice_index < 14) voice_next <= voice_next + 18'd7720;
        else voice_next <= voice_next + 18'd5960;
        voice_index <= voice_index + 1'b1;
      end
    end
'''
s=s[:start]+block+s[end:]
(p/'home_text_mask_voice_autoplay.v').write_text(s,encoding='utf-8')
print('Prepared compact phrase-timed character reveal')
