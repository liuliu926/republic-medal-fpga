"""Isolate raster geometry/write-boundary fixes from the accepted bilingual bit."""
from pathlib import Path
import shutil

R=Path(__file__).resolve().parents[1]
H=R/'fpga/user_source_720p/hdl_source'
run=R/'fpga/td_project_720p/cli_runs/bilingual_display_fix_20261101'
run.mkdir(parents=True,exist_ok=True)
shutil.copy2(R/'fpga/td_project_720p/cli_runs/bilingual_20261101/article_voice_cues.hex',
             run/'article_voice_cues.hex')

# Keep every accepted source and bitstream intact. Only this project's three
# substituted modules are built into the candidate.
s=(H/'portrait_bram_home_select.v').read_text(encoding='utf-8')
a=s.index('    wire [10:0] card_left');b=s.index('    reg [23:0] portrait_data_q;',a)
s=s[:a]+'''    // Measured outer strokes in BG001.BMP, inclusive pixel coordinates.
    // The PPT grid uses rounded fractional spacing; repeated integer 296/133
    // arithmetic drifts by up to four pixels in the lower/right cards.
    reg [10:0] card_left,card_right;
    reg [9:0] card_top,card_bottom;
    always @* begin
        case(selected_index[1:0])
          0:begin card_left=57;card_right=333;end
          1:begin card_left=353;card_right=629;end
          2:begin card_left=650;card_right=926;end
          default:begin card_left=946;card_right=1222;end
        endcase
        case(selected_index[4:2])
          0:begin card_top=163;card_bottom=276;end
          1:begin card_top=296;card_bottom=409;end
          2:begin card_top=430;card_bottom=542;end
          default:begin card_top=563;card_bottom=675;end
        endcase
    end
    // Registered border uses a one-pixel look-ahead, so its output remains
    // aligned to the undelayed background without a long final RGB path.
    wire [10:0] border_x=x+11'd1;
    wire in_card=de && border_x>=card_left && border_x<=card_right && y>=card_top && y<=card_bottom;
    wire [10:0] edge_x=(border_x-card_left < card_right-border_x) ? border_x-card_left : card_right-border_x;
    wire [9:0] edge_y=(y-card_top < card_bottom-y) ? y-card_top : card_bottom-y;
    // Six-pixel rounded outer corners, matching the independent TF artwork.
    wire rounded_outer=(edge_y>=5 || edge_x>=5) ||
        (edge_y>=1 && edge_x>=3) || (edge_y>=2 && edge_x>=2) ||
        (edge_y>=3 && edge_x>=1);
    wire selected_border=in_card && rounded_outer && (edge_x<3 || edge_y<3);
''' + s[b:]
# Keep the output selection registered; look-ahead above removes the offset.
(H/'portrait_home_aligned_candidate.v').write_text(s,encoding='utf-8')

s=(H/'intro_section_highlight.v').read_text(encoding='utf-8')
# Draw all four menu outlines from one coordinate table, rather than using
# baked thin strokes for three choices and another geometry for the fourth.
a=s.index('    wire in_box =');s=s[:a]+'''    wire in_box = x >= left && x < right && y >= top && y < bottom;
    wire outline = in_box && (x < left + 11'd3 || x >= right - 11'd3 ||
                              y < top + 10'd3 || y >= bottom - 10'd3);
    wire col0=x>=469 && x<800;
    wire col1=x>=815 && x<1146;
    wire row0=y>=461 && y<533;
    wire row1=y>=545 && y<617;
    wire vertical_edge=(x>=469 && x<471) || (x>=798 && x<800) ||
                       (x>=815 && x<817) || (x>=1144 && x<1146);
    wire horizontal_edge=(y>=461 && y<463) || (y>=531 && y<533) ||
                         (y>=545 && y<547) || (y>=615 && y<617);
    wire menu_outline=((row0 || row1) && vertical_edge) ||
                      ((col0 || col1) && horizontal_edge);
    assign rgb_out = (active && de && outline) ? 24'hFFE27C :
                     (active && de && menu_outline) ? 24'hC99F64 : rgb_in;
endmodule
'''
(H/'intro_highlight_aligned_candidate.v').write_text(s,encoding='utf-8')

s=(H/'SD/frame_fifo_write_rowburst_fast.v').read_text(encoding='utf-8')
s=s.replace('assign into_burst = (rdusedw >= burst_target) && ~App_rd_busy;',
'''// Do not launch a request while the physical SDRAM is refreshing/busy.
assign into_burst = (rdusedw >= burst_target) && ~App_rd_busy &&
                    !Sdr_busy && !Sdr_init_ref_vld;''')
s=s.replace("if (settle_count < 5'd10) settle_count <= settle_count + 5'd1;",'''// Portrait rows are 320 words with a 512-word destination stride.
                // Split 256+64 so a live request never jumps at the row end
                // or crosses to a different SDRAM page. Background (1280)
                // and 80-word thumbnails retain their original requests.
                burst_target <= (line_width_latch == 16'd80) ? 9'd80 :
                    (line_width_latch == 16'd320 && wr_x == 16'd256) ? 9'd64 : 9'd256;
                if (settle_count < 5'd10) settle_count <= settle_count + 5'd1;''')
(H/'SD/frame_fifo_write_page_safe_candidate.v').write_text(s,encoding='utf-8')

prj=(R/'fpga/td_project_720p/cli_runs/bilingual_20261101/medal_kiosk_720p.prj').read_text(encoding='utf-8')
for old,new in [('portrait_bram_home_select.v','portrait_home_aligned_candidate.v'),
 ('intro_section_highlight.v','intro_highlight_aligned_candidate.v'),
 ('frame_fifo_write_rowburst_fast.v','frame_fifo_write_page_safe_candidate.v')]:
    assert old in prj,old
    prj=prj.replace(old,new)
(run/'medal_kiosk_720p.prj').write_text(prj,encoding='utf-8')
build=(R/'tools/build_720p_bilingual.tcl').read_text(encoding='utf-8')
build=build.replace('cli_runs bilingual_20261101','cli_runs bilingual_display_fix_20261101').replace('medal_720p_bilingual.bit','medal_720p_bilingual_display_fix.bit')
(R/'tools/build_720p_bilingual_display_fix.tcl').write_text(build,encoding='utf-8')
dl=(R/'tools/download_720p_bilingual.tcl').read_text(encoding='utf-8').replace('cli_runs bilingual_20261101','cli_runs bilingual_display_fix_20261101').replace('medal_720p_bilingual.bit','medal_720p_bilingual_display_fix.bit')
(R/'tools/download_720p_bilingual_display_fix.tcl').write_text(dl,encoding='utf-8')
print('Prepared isolated candidate:',run)
