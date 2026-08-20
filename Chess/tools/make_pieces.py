"""Draw the 2D piece sprites used by Scripts/chess/board2d.lua.

    python tools/make_pieces.py

Writes Assets/UI/chess2d/{w,b}{K,Q,R,B,N,P}.png -- a Staunton set built from filled
primitives, not from a font. The first version rasterised the Unicode chess glyphs
(U+265A..265F) out of Segoe UI Symbol; only two fonts on Windows have those glyphs at all
and neither draws a good piece -- the bishop in particular reads as a knot rather than a
mitre. Drawing the shapes outright also means no font licence travels with the PNGs and
the palette and stroke weight are ours to tune.

Each piece is described in a 100x100 space (y grows downward) as a union of shapes plus a
set of "cuts": thin gaps that the outline dilation fills back in. That is where the
internal detail lines come from -- the base seam, the bishop's slit, the knight's mane --
with no second colour pass.

Nothing at runtime reads this script; it only has to exist so the sprites can be rebuilt.
"""

import os

from PIL import Image, ImageDraw, ImageFilter

SIZE = 192       # px per sprite, square
STROKE = 2.4     # outline weight, in the same 100-unit space as the shapes
SS = 6           # supersample factor; everything is drawn at SIZE*SS and reduced

OUT = os.path.join(os.path.dirname(__file__), "..", "Assets", "UI", "chess2d")

# fill, outline. High contrast both ways so either colour survives either square.
STYLE = {
    "w": ((248, 246, 240, 255), (26, 22, 18, 255)),
    "b": ((34, 30, 27, 255), (233, 229, 219, 255)),
}


class Pen:
    """Two masks: the silhouette, and the cuts subtracted from it."""

    def __init__(self, size):
        self.size = size
        self.shape = Image.new("L", (size, size), 0)
        self.cut = Image.new("L", (size, size), 0)
        self.ds = ImageDraw.Draw(self.shape)
        self.dc = ImageDraw.Draw(self.cut)

    def _s(self, v):
        return v * self.size / 100.0

    def poly(self, pts, cut=False):
        d = self.dc if cut else self.ds
        d.polygon([(self._s(x), self._s(y)) for x, y in pts], fill=255)

    def ell(self, cx, cy, rx, ry=None, cut=False):
        ry = rx if ry is None else ry
        d = self.dc if cut else self.ds
        d.ellipse([self._s(cx - rx), self._s(cy - ry), self._s(cx + rx), self._s(cy + ry)], fill=255)

    def rrect(self, x0, y0, x1, y1, r=2, cut=False):
        d = self.dc if cut else self.ds
        d.rounded_rectangle([self._s(x0), self._s(y0), self._s(x1), self._s(y1)],
                            radius=self._s(r), fill=255)

    def line(self, pts, w, cut=False):
        d = self.dc if cut else self.ds
        d.line([(self._s(x), self._s(y)) for x, y in pts], fill=255,
               width=max(1, int(self._s(w))), joint="curve")


# ── shared furniture ───────────────────────────────────────────────────────
# One plinth and one collar shape across the set, so six separately-drawn pieces still
# look like one set standing on one board.
def base(p, top=78, waist=26, foot=17):
    p.poly([(waist + 4, top), (100 - waist - 4, top), (100 - foot, top + 8), (foot, top + 8)])
    p.rrect(foot, top + 7, 100 - foot, top + 15, 3)
    p.line([(waist + 5, top + 1), (100 - waist - 5, top + 1)], 1.6, cut=True)


def stem(p, y0, y1, w0, w1):
    p.poly([(50 - w0, y0), (50 + w0, y0), (50 + w1, y1), (50 - w1, y1)])


def collar(p, y, h=7, w=18, r=3):
    p.rrect(50 - w, y, 50 + w, y + h, r)


# ── the pieces ─────────────────────────────────────────────────────────────
def pawn(p):
    p.ell(50, 24, 13)                                           # head
    p.poly([(43, 34), (57, 34), (61, 44), (39, 44)])            # neck
    collar(p, 42, 7, 16)
    stem(p, 49, 78, 11, 20)
    base(p, 78, 26, 18)
    p.line([(34, 49), (66, 49)], 1.6, cut=True)


def rook(p):
    p.rrect(21, 15, 79, 33, 1.5)
    for x0, x1 in ((30, 38), (45, 55), (62, 70)):               # crenellations
        p.poly([(x0, 13), (x1, 13), (x1, 26), (x0, 26)], cut=True)
    p.rrect(24, 31, 76, 40, 1.5)
    stem(p, 39, 62, 20, 15)
    p.poly([(33, 60), (67, 60), (76, 78), (24, 78)])
    base(p, 78, 24, 16)
    p.line([(25, 40), (75, 40)], 1.7, cut=True)
    p.line([(30, 61), (70, 61)], 1.7, cut=True)


def bishop(p):
    p.ell(50, 9, 5)                                             # finial
    p.ell(50, 42, 17, 14)                                       # mitre body...
    p.poly([(50, 13), (36, 46), (64, 46)])                      # ...and its point
    p.line([(58, 24), (46, 41)], 3.4, cut=True)                 # the mitre's slit
    collar(p, 50, 7, 19)
    stem(p, 57, 72, 13, 20)
    p.poly([(30, 70), (70, 70), (76, 78), (24, 78)])
    base(p, 78, 24, 16)
    p.line([(32, 57), (68, 57)], 1.6, cut=True)


def knight(p):
    # Facing left. Three things make it read as a horse rather than a rabbit: a muzzle
    # that genuinely protrudes past the forehead, an angular jaw with a corner in it,
    # and an ear notched clear of the crest instead of merging into it.
    p.poly([
        (76, 74), (77, 56), (75, 40), (70, 27), (68, 19),       # back of neck up to the crest
        (64, 21), (63, 4), (57, 17), (51, 21), (48, 20),        # ear, then the poll
        (40, 24), (30, 32), (20, 40), (12, 48),                 # forehead down to the nose
        (13, 55), (19, 59), (27, 60),                           # muzzle, lip, mouth corner
        (33, 66), (39, 72), (44, 74),                           # the jaw line
    ])
    p.poly([(26, 72), (76, 72), (80, 80), (22, 80)])
    base(p, 80, 26, 14)
    p.ell(36, 32, 2.4, cut=True)                                # eye
    p.line([(57, 23), (63, 36), (66, 54), (67, 68)], 2.4, cut=True)  # mane
    p.line([(15, 52), (25, 55)], 2.0, cut=True)                 # mouth
    p.ell(16, 47, 1.7, cut=True)                                # nostril


def queen(p):
    for cx, cy, r in ((17, 23, 5.5), (33, 15, 5.5), (50, 10, 6.5), (67, 15, 5.5), (83, 23, 5.5)):
        p.ell(cx, cy, r)                                        # the five orbs
    p.poly([(15, 25), (24, 44), (76, 44), (85, 25),             # ...and the coronet under them
            (69, 36), (67, 17), (56, 34), (50, 13), (44, 34), (33, 17), (31, 36)])
    collar(p, 43, 8, 25, 3)
    stem(p, 50, 72, 20, 24)
    p.poly([(26, 70), (74, 70), (79, 78), (21, 78)])
    base(p, 78, 22, 14)
    p.line([(27, 51), (73, 51)], 1.7, cut=True)


def king(p):
    p.rrect(45, 5, 55, 26, 1.5)                                 # cross; y=5 leaves room
    p.rrect(36, 11, 64, 20, 1.5)                                # for STROKE above it
    p.poly([(23, 44), (24, 36), (29, 30), (37, 26), (50, 24),   # domed crown
            (63, 26), (71, 30), (76, 36), (77, 44), (74, 50), (26, 50)])
    p.line([(32, 32), (44, 46)], 2.2, cut=True)                 # crown facets
    p.line([(68, 32), (56, 46)], 2.2, cut=True)
    collar(p, 46, 8, 25, 3)
    stem(p, 53, 72, 20, 24)
    p.poly([(26, 70), (74, 70), (79, 78), (21, 78)])
    base(p, 78, 22, 14)
    p.line([(27, 54), (73, 54)], 1.7, cut=True)


PIECES = {"K": king, "Q": queen, "R": rook, "B": bishop, "N": knight, "P": pawn}


def render(kind, color, out_size=SIZE, stroke=STROKE):
    big = out_size * SS
    p = Pen(big)
    PIECES[kind](p)

    mask = Image.composite(Image.new("L", (big, big), 0), p.shape, p.cut)
    r = max(1, int(round(stroke * SS)))
    # Dilating the already-cut mask does double duty: it fattens the silhouette outward
    # into the outline, and it closes the thin cuts back up in the outline colour.
    outline = mask.filter(ImageFilter.MaxFilter(2 * r + 1))

    fill, edge = STYLE[color]
    img = Image.new("RGBA", (big, big), (0, 0, 0, 0))
    img.paste(Image.new("RGBA", (big, big), edge), (0, 0), outline)
    img.paste(Image.new("RGBA", (big, big), fill), (0, 0), mask)
    return img.resize((out_size, out_size), Image.LANCZOS)


def main():
    os.makedirs(OUT, exist_ok=True)
    for kind in PIECES:
        for color in STYLE:
            img = render(kind, color)
            box = img.getbbox()
            # A piece that drew nothing, or that runs into the edge of its sprite, is a
            # geometry mistake -- it would tile badly against the neighbouring square.
            assert box, "empty sprite for %s%s" % (color, kind)
            assert box[0] > 0 and box[1] > 0 and box[2] < SIZE and box[3] < SIZE, \
                "%s%s touches the sprite edge: %s" % (color, kind, box)
            path = os.path.join(OUT, color + kind + ".png")
            img.save(path)
            print("wrote", os.path.normpath(path), box)


if __name__ == "__main__":
    main()
