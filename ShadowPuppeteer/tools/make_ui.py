"""UI pictures for the game's cards: a gold paper star (earned) and its dim outline (not yet), 256 px, antialiased.
    python -I tools/make_ui.py"""
import math
import os
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Assets", "Textures")
N, SS = 256, 4


def star(r1, r2, c):
    return [(c + (r1 if i % 2 == 0 else r2) * math.cos(-math.pi / 2 + i * math.pi / 5),
             c + (r1 if i % 2 == 0 else r2) * math.sin(-math.pi / 2 + i * math.pi / 5)) for i in range(10)]


def make(on):
    S = N * SS
    im = Image.new("RGBA", (S, S), (0, 0, 0, 0))
    d = ImageDraw.Draw(im)
    c = S / 2
    if on:
        sh = Image.new("RGBA", (S, S), (0, 0, 0, 0))
        ImageDraw.Draw(sh).polygon(star(S * 0.47, S * 0.2, c + S * 0.02), fill=(20, 6, 0, 150))
        im = Image.alpha_composite(im, sh.filter(ImageFilter.GaussianBlur(S * 0.02)))
        d = ImageDraw.Draw(im)
        d.polygon(star(S * 0.45, S * 0.19, c), fill=(150, 92, 20, 255))            # rim
        d.polygon(star(S * 0.40, S * 0.17, c), fill=(244, 196, 84, 255))           # gold paper
        d.polygon([(c, c)] + star(S * 0.40, S * 0.17, c)[0:4], fill=(255, 226, 140, 255))   # lit facet
    else:
        d.polygon(star(S * 0.45, S * 0.19, c), fill=(120, 84, 50, 200))
        d.polygon(star(S * 0.38, S * 0.16, c), fill=(36, 12, 10, 220))
    return im.resize((N, N), Image.LANCZOS)


for on in (True, False):
    make(on).save(os.path.join(OUT, "ui_star_%s.png" % ("on" if on else "off")))
print("ok")
