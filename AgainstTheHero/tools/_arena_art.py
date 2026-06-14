"""Shared chunky-cartoon PIL toolkit for Hero Arena sprite generators.

Bold outer outline (alpha dilation), big black-rimmed googly eyes, angry brows,
saturated farm palette, generous transparent margins. Used by
gen_arena_creeps.py and gen_arena_heroes.py.

Run the gen scripts with the Pillow-equipped interpreter: `python tools/<gen>.py`
(python3/py on this box lack PIL).
"""
import os
import math
from PIL import Image, ImageDraw, ImageFilter

OUT = os.path.normpath(os.path.join(os.path.dirname(__file__), "..",
                                    "Assets", "Textures", "modes", "spud_fields"))

INK = (30, 24, 28, 255)        # near-black outline ink (matches the cast)
WHITE = (246, 246, 250, 255)

PAL = {
    "red":       (212, 58, 50, 255),
    "red_dk":    (168, 40, 36, 255),
    "yellow":    (246, 202, 48, 255),
    "yellow_dk": (220, 166, 32, 255),
    "corn":      (248, 214, 78, 255),
    "corn_dk":   (212, 168, 44, 255),
    "green":     (98, 168, 72, 255),
    "green_dk":  (62, 122, 52, 255),
    "husk":      (126, 178, 78, 255),
    "tan":       (222, 192, 132, 255),
    "tan_dk":    (188, 150, 96, 255),
    "spud":      (214, 168, 102, 255),
    "amber":     (234, 150, 40, 255),
    "steel":     (150, 162, 186, 255),
    "steel_dk":  (104, 116, 142, 255),
    "wing":      (214, 234, 246, 200),
}


def canvas(w, h):
    return Image.new("RGBA", (w, h), (0, 0, 0, 0))


def dilate(alpha, px):
    """Grow an alpha mask by ~px pixels (repeated 3x3 max filter ≈ 2px/pass)."""
    passes = max(1, round(px / 2.0))
    a = alpha
    for _ in range(passes):
        a = a.filter(ImageFilter.MaxFilter(5))
    return a


def outlined(layer, width=8, color=INK):
    """Wrap a fills-only figure in a solid outer outline of `width` px."""
    a = layer.split()[3]
    grown = dilate(a, width)
    out = canvas(*layer.size)
    sil = Image.new("RGBA", layer.size, color)
    out.paste(sil, (0, 0), grown)
    out.alpha_composite(layer)
    return out


def capsule(d, x1, y1, x2, y2, w, fill):
    d.line([x1, y1, x2, y2], fill=fill, width=int(round(w)))
    r = w / 2.0
    for (x, y) in ((x1, y1), (x2, y2)):
        d.ellipse([x - r, y - r, x + r, y + r], fill=fill)


def eye(d, cx, cy, r, look=(0.22, 0.18)):
    """A black-rimmed googly eye looking toward `look` (unit-ish offset)."""
    d.ellipse([cx - r, cy - r, cx + r, cy + r], fill=INK)
    iw = r * 0.80
    d.ellipse([cx - iw, cy - iw, cx + iw, cy + iw], fill=WHITE)
    pr = r * 0.46
    px = cx + look[0] * r
    py = cy + look[1] * r
    d.ellipse([px - pr, py - pr, px + pr, py + pr], fill=(26, 22, 28, 255))
    hr = max(2.0, r * 0.17)
    hx, hy = px - pr * 0.45, py - pr * 0.55
    d.ellipse([hx - hr, hy - hr, hx + hr, hy + hr], fill=(255, 255, 255, 235))


def brow(d, cx, cy, w, h, angle, color=INK):
    """An angry slanted brow (angle in degrees, +ve = inner-down)."""
    a = math.radians(angle)
    dx, dy = math.cos(a) * w / 2.0, math.sin(a) * w / 2.0
    capsule(d, cx - dx, cy - dy, cx + dx, cy + dy, h, color)


def save(img, name):
    if not os.path.isdir(OUT):
        os.makedirs(OUT)
    img.save(os.path.join(OUT, name))
    print("wrote", os.path.join(OUT, name), img.size)
