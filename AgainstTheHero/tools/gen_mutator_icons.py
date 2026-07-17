# Generates 128x128 smooth icons for the wave-director mutators (one per id in
# modes/arena/waves.lua) into Assets/Textures/ui/mutators/. Deterministic:
# shapes drawn 8x supersampled, dark halo outline, LANCZOS downscale.
# Run with `python tools/gen_mutator_icons.py`.
from PIL import Image, ImageDraw, ImageFilter
import os

OUT = os.path.join(os.path.dirname(__file__), "..", "Assets", "Textures", "ui", "mutators")
SIZE, SS = 128, 8
C = SIZE * SS  # supersampled canvas edge (1024)
OUTLINE = (24, 18, 30, 255)


def canvas():
    im = Image.new("RGBA", (C, C), (0, 0, 0, 0))
    return im, ImageDraw.Draw(im)


def sx(*vals):  # scale 0..128 coords to supersampled canvas
    return [v * SS for v in vals]


def finish(im, name):
    # dark halo outline: dilate alpha, fill dark, put icon on top
    a = im.split()[3].filter(ImageFilter.MaxFilter(2 * SS + 1))
    halo = Image.new("RGBA", im.size, (0, 0, 0, 0))
    halo.paste(Image.new("RGBA", im.size, OUTLINE), (0, 0), a)
    halo.paste(im, (0, 0), im)
    out = halo.resize((SIZE, SIZE), Image.LANCZOS)
    out.save(os.path.join(OUT, name + ".png"))
    print("wrote", name)


def wasp_bloom():
    im, d = canvas()
    d.ellipse(sx(14, 18, 60, 52), fill=(220, 232, 248, 210))   # left wing
    d.ellipse(sx(68, 18, 114, 52), fill=(220, 232, 248, 210))  # right wing
    body = Image.new("L", (C, C), 0)
    bd = ImageDraw.Draw(body)
    bd.ellipse(sx(40, 36, 88, 108), fill=255)                  # body mask
    yellow = Image.new("RGBA", (C, C), (242, 198, 62, 255))
    im.paste(yellow, (0, 0), body)
    stripes = Image.new("RGBA", (C, C), (44, 36, 32, 255))
    smask = Image.new("L", (C, C), 0)
    sd = ImageDraw.Draw(smask)
    for y in (52, 70, 88):
        sd.rectangle(sx(30, y, 98, y + 9), fill=255)
    smask = Image.composite(smask, Image.new("L", (C, C), 0), body)
    im.paste(stripes, (0, 0), smask)
    d = ImageDraw.Draw(im)
    d.polygon(sx(60, 106, 68, 106, 64, 122), fill=(44, 36, 32, 255))  # stinger
    finish(im, "wasp_bloom")


def goldrush():
    im, d = canvas()
    for cx, cy in ((44, 40), (84, 62), (52, 90)):
        d.ellipse(sx(cx - 26, cy - 26, cx + 26, cy + 26), fill=(170, 122, 34, 255))
        d.ellipse(sx(cx - 20, cy - 20, cx + 20, cy + 20), fill=(246, 208, 96, 255))
        d.arc(sx(cx - 14, cy - 14, cx + 14, cy + 14), 200, 320, fill=(255, 240, 180, 255), width=4 * SS)
    finish(im, "goldrush")


def bloated():
    im, d = canvas()
    d.line(sx(74, 34, 88, 16), fill=(150, 108, 70, 255), width=7 * SS)  # fuse
    for ang, ln in ((0, 10), (90, 10), (45, 7), (135, 7)):              # spark
        import math
        r = math.radians(ang)
        d.line(sx(92 - ln * math.cos(r), 12 - ln * math.sin(r),
                  92 + ln * math.cos(r), 12 + ln * math.sin(r)),
               fill=(255, 216, 96, 255), width=5 * SS)
    d.ellipse(sx(20, 32, 108, 120), fill=(218, 98, 42, 255))            # body
    d.ellipse(sx(34, 44, 66, 76), fill=(246, 152, 94, 255))             # highlight
    finish(im, "bloated")


def veterans():
    im, d = canvas()
    for top in (16, 52, 88):
        d.polygon(sx(64, top, 100, top + 22, 88, top + 34, 64, top + 18,
                     40, top + 34, 28, top + 22), fill=(242, 202, 90, 255))
    finish(im, "veterans")


def stampede():
    im, d = canvas()
    d.arc(sx(6, 14, 58, 78), 130, 300, fill=(232, 224, 208, 255), width=11 * SS)   # left horn
    d.arc(sx(70, 14, 122, 78), 240, 50, fill=(232, 224, 208, 255), width=11 * SS)  # right horn
    d.ellipse(sx(34, 34, 94, 102), fill=(192, 56, 46, 255))   # head
    d.polygon(sx(48, 92, 80, 92, 64, 118), fill=(192, 56, 46, 255))  # muzzle
    d.ellipse(sx(48, 62, 58, 72), fill=(255, 222, 120, 255))  # eyes
    d.ellipse(sx(70, 62, 80, 72), fill=(255, 222, 120, 255))
    finish(im, "stampede")


def thick_hide():
    im, d = canvas()
    shield = sx(24, 18, 104, 18, 104, 64, 64, 116, 24, 64)
    pts = list(zip(shield[0::2], shield[1::2]))
    d.polygon(pts, fill=(56, 88, 50, 255))
    inner = sx(34, 28, 94, 28, 94, 60, 64, 100, 34, 60)
    d.polygon(list(zip(inner[0::2], inner[1::2])), fill=(96, 140, 76, 255))
    hi = sx(42, 36, 62, 36, 62, 58, 42, 58)
    d.polygon(list(zip(hi[0::2], hi[1::2])), fill=(126, 168, 100, 255))
    finish(im, "thick_hide")


os.makedirs(OUT, exist_ok=True)
wasp_bloom(); goldrush(); bloated(); veterans(); stampede(); thick_hide()
