"""Render a visual reference for the first FPGA menu prototype."""

from pathlib import Path
from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parents[1]
FONT_PATH = r"C:\Windows\Fonts\msyh.ttc"
FONT16 = ImageFont.truetype(FONT_PATH, 16)
FONT32 = ImageFont.truetype(FONT_PATH, 32)
PEOPLE = [
    "于敏", "申纪兰", "孙家栋", "李延年", "张富清", "袁隆平", "黄旭华",
    "屠呦呦", "钟南山", "王永志", "王振义", "李振声", "黄宗德",
]
SECTIONS = ["生平", "主要贡献", "代表事迹", "互动问答"]


def base():
    image = Image.new("RGB", (640, 480), "#0b1325")
    draw = ImageDraw.Draw(image)
    draw.rectangle((0, 0, 639, 63), fill="#132b45")
    draw.rectangle((0, 62, 639, 65), fill="#d6a84c")
    draw.text((240, 12), "共和国勋章", font=FONT32, fill="#fff5d7")
    return image, draw


home, draw = base()
for index, name in enumerate(PEOPLE):
    row, col = divmod(index, 4)
    x, y = 16 + 152 * col, 80 + 92 * row
    chosen = index == 0
    draw.rectangle((x, y, x + 147, y + 87), fill="#30445d" if chosen else "#1b3048", outline="#f2c35b" if chosen else "#3a5670", width=3)
    draw.ellipse((x + 61, y + 12, x + 84, y + 35), fill="#728aa3")
    draw.rectangle((x + 47, y + 37, x + 98, y + 53), fill="#728aa3")
    draw.text((x + 40, y + 54), name, font=FONT16, fill="white")
home.save(ROOT / "preview_home.png")

person, draw = base()
draw.rectangle((40, 88, 599, 189), fill="#1b3048")
draw.text((80, 110), PEOPLE[0], font=FONT32, fill="#fff5d7")
for index, label in enumerate(SECTIONS):
    row, col = divmod(index, 2)
    x, y = (40 if col == 0 else 332), (230 if row == 0 else 334)
    chosen = index == 0
    draw.rectangle((x, y, x + 267, y + 87), fill="#30445d" if chosen else "#1b3048", outline="#f2c35b" if chosen else "#3a5670", width=3)
    draw.text((x + 92, y + 34), label, font=FONT16, fill="white")
person.save(ROOT / "preview_person.png")
print("Wrote preview_home.png and preview_person.png")
