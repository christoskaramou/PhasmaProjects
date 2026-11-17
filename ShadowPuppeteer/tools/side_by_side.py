"""Concept next to the target frame, both at 1920x1080, labelled.

    python tools/side_by_side.py CONCEPT.png TARGET.png OUT.png
"""
import sys

from PIL import Image, ImageDraw, ImageFont

concept, target, out = sys.argv[1:4]
W, H, GAP, BAR = 1920, 1080, 24, 56
a = Image.open(concept).convert("RGB").resize((W, H), Image.LANCZOS)
b = Image.open(target).convert("RGB").resize((W, H), Image.LANCZOS)
im = Image.new("RGB", (2 * W + GAP, H + BAR), (18, 14, 12))
im.paste(a, (0, BAR))
im.paste(b, (W + GAP, BAR))
d = ImageDraw.Draw(im)
try:
    f = ImageFont.truetype("C:/Windows/Fonts/georgia.ttf", 30)
except OSError:
    f = ImageFont.load_default()
d.text((20, 12), "approved concept (shadow_puppeteer.png)", fill=(230, 210, 180), font=f)
d.text((W + GAP + 20, 12), "target.png: game camera, mid-play (scaled from 2560x1440)", fill=(230, 210, 180), font=f)
im.save(out)
print("wrote", out)
