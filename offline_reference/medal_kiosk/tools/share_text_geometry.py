"""Keep pixel mapping and pipeline latency, share the coordinate adders."""
import re

def share_geometry(mask):
    def change(old, new):
        nonlocal mask
        assert mask.count(old) == 1, old
        mask = mask.replace(old, new, 1)

    change('    reg inside;', '''    reg inside;
    reg [9:0] x_bias;
    reg [8:0] y_bias;''')
    # Life visibility is evaluated after the shared coordinate calculation.
    life_pattern = r'''                    if \(voice_active && voice_line == [1-4] &&
                        \(\(atlas_x < 126 && atlas_x >= voice_year_limit\) \|\|
\s*\(atlas_x >= 183 && atlas_x >= voice_text_limit\)\)\) inside=0;'''
    mask, n = re.subn(life_pattern, '', mask)
    assert n == 4, n

    def x_assignment(match):
        expression = match.group(1).strip()
        if expression == '0': return 'x_bias=0;'
        if expression == "local_x + col * 10'd192": return 'x_bias=local_x[9:0];'
        if 'quiz_correct' in expression:
            return "x_bias=quiz_correct ? 10'd984 : 10'd100;"
        expression = re.sub(r"\d+'d(\d+)", r'\1', expression)
        assert expression.count('next_x') == 1, expression
        value = eval(expression.replace('next_x','0'), {'__builtins__':{}}, {})
        return "x_bias=10'd%d;" % (value % 1024)

    def y_assignment(match):
        expression = match.group(1).strip()
        if expression == '0': return 'y_bias=0;'
        if expression == "local_y + row * 9'd64": return 'y_bias=local_y[8:0];'
        expression = re.sub(r"\d+'d(\d+)", r'\1', expression)
        assert expression.count('y') == 1, expression
        value = eval(expression.replace('y','0'), {'__builtins__':{}}, {})
        return "y_bias=9'd%d;" % (value % 512)

    mask = re.sub(r'atlas_x\s*=([^;]+);', x_assignment, mask)
    mask = re.sub(r'atlas_y\s*=([^;]+);', y_assignment, mask)
    for column, origin in enumerate((151,447,743,1039)):
        change("local_x=next_x-11'd%d;" % origin,
               "local_x=11'd%d;" % ((column*192-origin)%1024))
    for row, origin in enumerate((180,313,446,579)):
        change("local_y=y-10'd%d;" % origin,
               "local_y=10'd%d;" % ((row*64-origin)%512))
    change('        // Each atlas row has a 32px heading band', '''        atlas_x=next_x[9:0]+x_bias;
        atlas_y=y[8:0]+y_bias;
        if (article_mode && !quiz_mode && !contribution_mode && !deeds_mode &&
            voice_active && atlas_y[8:6] == voice_line &&
            ((atlas_x < 126 && atlas_x >= voice_year_limit) ||
             (atlas_x >= 183 && atlas_x >= voice_text_limit))) inside=0;
        // Each atlas row has a 32px heading band''')
    return mask
