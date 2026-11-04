"""Generate per-slide KEY4 reveal limits from the prepared PPT catalog."""
import json
from pathlib import Path

root=Path(__file__).resolve().parents[1]
catalog=json.loads((root/'prepared_resource_catalog/catalog.json').read_text(encoding='utf-8'))
pages=catalog['pages']
if len(pages)!=53 or sorted(p['slide'] for p in pages)!=list(range(1,54)):
    raise ValueError('Expected each slide 1..53 once')
lines=['// Generated from prepared_resource_catalog/catalog.json; do not edit manually.',
       'module kiosk_reveal_limit(input wire [5:0] slide_number,',
       '    output reg slide_valid, output reg [2:0] max_reveal_step);',
       'always @* begin',
       '    slide_valid=1; max_reveal_step=0;',
       '    case (slide_number)']
for page in pages:
    steps=[layer['key4_reveal_step'] for layer in page['layers']]
    maximum=max(steps,default=0)
    if any(not isinstance(x,int) or x<0 or x>7 for x in steps):
        raise ValueError(f"Slide {page['slide']} has invalid reveal step")
    lines.append(f"        6'd{page['slide']}: max_reveal_step=3'd{maximum};")
lines += ['        default: begin slide_valid=0; max_reveal_step=0; end',
          '    endcase','end','endmodule','']
output=root/'fpga/user_source_720p/hdl_source/kiosk_reveal_limit.v'
output.write_text('\n'.join(lines),encoding='utf-8')
print(f'Generated limits for {len(pages)} slides: {output}')
