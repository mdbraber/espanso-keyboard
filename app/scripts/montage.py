# Builds the README comparison images from simulator screenshots.
# uv run --with pillow scripts/montage.py <device> <tag> <crop-top-fraction> <out.png>
import os
import sys

from PIL import Image, ImageDraw, ImageFont

RAW = os.path.join(os.path.dirname(__file__), '..', 'shots', 'raw')
WIDTH, PAD, HEADER = 600, 24, 44

device, tag, fraction, out = sys.argv[1], sys.argv[2], float(sys.argv[3]), sys.argv[4]


def cell(name):
    image = Image.open(os.path.join(RAW, name)).convert('RGB')
    width, height = image.size
    image = image.crop((0, int(height * fraction), width, height))
    return image.resize((WIDTH, round(image.height * WIDTH / width)), Image.LANCZOS)


rows = [[cell(f'{device}-ref-system-{mode}.png'), cell(f'{device}-{tag}-hex-{mode}.png')] for mode in ('light', 'dark')]
height = rows[0][0].height
canvas = Image.new('RGB', (PAD + 2 * (WIDTH + PAD), HEADER + 2 * (height + PAD)), (246, 246, 248))
draw = ImageDraw.Draw(canvas)
font = ImageFont.load_default(22)
for column, title in enumerate(('Apple', 'Hex')):
    draw.text((PAD + column * (WIDTH + PAD), 12), title, fill=(60, 60, 67), font=font)
for r, row in enumerate(rows):
    for c, image in enumerate(row):
        canvas.paste(image, (PAD + c * (WIDTH + PAD), HEADER + r * (height + PAD)))
canvas.save(out, optimize=True)
