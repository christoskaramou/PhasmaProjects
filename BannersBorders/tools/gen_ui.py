#!/usr/bin/env python3
"""UI icons for Banners & Borders: smooth, outlined, glossy mobile-style PNGs (supersampled)."""
import math, os
from PIL import Image, ImageDraw, ImageFilter
OUT = os.path.join(os.path.dirname(__file__), '..', 'project', 'Assets', 'Textures', 'ui')
os.makedirs(OUT, exist_ok=True)
S = 4  # supersample

def canvas(n=256): return Image.new('RGBA', (n * S, n * S), (0, 0, 0, 0))
def done(img, name, n=256):
    img = img.resize((n, n), Image.LANCZOS); img.save(os.path.join(OUT, name + '.png'))
def star_pts(cx, cy, r0, r1, k=5, rot=-90):
    pts = []
    for i in range(k * 2):
        r = r0 if i % 2 == 0 else r1
        a = math.radians(rot + i * 180 / k)
        pts.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return pts
def rounded_poly(img, pts, fill, rad):
    m = Image.new('L', img.size, 0); ImageDraw.Draw(m).polygon(pts, fill=255)
    if rad > 0:
        m = m.filter(ImageFilter.GaussianBlur(rad)); m = m.point(lambda v: 255 if v > 128 else 0)
    layer = Image.new('RGBA', img.size, fill); img.paste(layer, (0, 0), m)
    return m
def star(name, top, bot, outline):
    img = canvas(); n = 256 * S; c = n / 2
    rounded_poly(img, star_pts(c, c + 6 * S, 122 * S, 58 * S), outline, 6 * S)
    rounded_poly(img, star_pts(c, c + 2 * S, 104 * S, 48 * S), bot, 6 * S)
    rounded_poly(img, star_pts(c, c - 4 * S, 98 * S, 44 * S), top, 6 * S)
    # gloss
    g = Image.new('L', img.size, 0); ImageDraw.Draw(g).ellipse((c - 60 * S, c - 92 * S, c + 10 * S, c - 40 * S), fill=110)
    g = g.filter(ImageFilter.GaussianBlur(10 * S)); img.paste(Image.new('RGBA', img.size, (255, 255, 255, 255)), (0, 0), Image.composite(g, Image.new('L', img.size, 0), img.split()[3]))
    done(img, name)

def disc_icon(name, outer, mid, inner, symbol=None, sym_col=None):
    img = canvas(); d = ImageDraw.Draw(img); n = 256 * S
    d.ellipse((8 * S, 14 * S, n - 8 * S, n - 2 * S), fill=outer)
    d.ellipse((8 * S, 6 * S, n - 8 * S, n - 10 * S), fill=mid)
    d.ellipse((36 * S, 32 * S, n - 36 * S, n - 38 * S), fill=inner)
    if symbol == 'coin':
        d.rounded_rectangle((112 * S, 70 * S, 144 * S, 180 * S), radius=14 * S, fill=sym_col)
    g = Image.new('L', img.size, 0); ImageDraw.Draw(g).ellipse((50 * S, 22 * S, 150 * S, 80 * S), fill=120)
    g = g.filter(ImageFilter.GaussianBlur(12 * S)); img.paste(Image.new('RGBA', img.size, (255, 255, 255, 255)), (0, 0), Image.composite(g, Image.new('L', img.size, 0), img.split()[3]))
    done(img, name)

def gem():
    img = canvas(); n = 256 * S
    top = [(60, 70), (196, 70), (240, 112), (128, 236), (16, 112)]
    P = lambda pts: [(x * S, y * S) for x, y in pts]
    d = ImageDraw.Draw(img)
    d.polygon(P([(x, y + 6) for x, y in top]), fill=(90, 20, 90, 255))
    d.polygon(P(top), fill=(220, 60, 200, 255))
    d.polygon(P([(60, 70), (196, 70), (176, 112), (80, 112)]), fill=(255, 140, 240, 255))
    d.polygon(P([(16, 112), (80, 112), (128, 236)]), fill=(190, 40, 170, 255))
    d.polygon(P([(240, 112), (176, 112), (128, 236)]), fill=(160, 30, 150, 255))
    d.polygon(P([(80, 112), (176, 112), (128, 236)]), fill=(235, 90, 215, 255))
    d.polygon(P([(70, 78), (110, 78), (96, 104), (84, 104)]), fill=(255, 230, 255, 220))
    done(img.filter(ImageFilter.GaussianBlur(1.2 * S)) if False else img, 'gem')

def glyph_btn(name, draw):
    img = canvas(); d = ImageDraw.Draw(img); (draw(d, 256 * S) if draw.__code__.co_argcount == 2 else draw(d)); done(img, name)
def lock(d, n):
    d.rounded_rectangle((60 * S, 112 * S, 196 * S, 222 * S), radius=24 * S, fill=(255, 255, 255, 255))
    d.arc((82 * S, 40 * S, 174 * S, 150 * S), 180, 360, fill=(255, 255, 255, 255), width=22 * S)
    d.line((93 * S, 95 * S, 93 * S, 120 * S), fill=(255, 255, 255, 255), width=22 * S); d.line((163 * S, 95 * S, 163 * S, 120 * S), fill=(255, 255, 255, 255), width=22 * S)
    d.ellipse((114 * S, 148 * S, 142 * S, 176 * S), fill=(0, 0, 0, 0))
def shield(d, n):
    pts = [(128, 22), (222, 58), (210, 150), (128, 234), (46, 150), (34, 58)]
    d.polygon([(x * S, (y + 6) * S) for x, y in pts], fill=(20, 60, 140, 255))
    d.polygon([(x * S, y * S) for x, y in pts], fill=(90, 190, 255, 255))
    d.polygon([(128 * S, 22 * S), (222 * S, 58 * S), (210 * S, 150 * S), (128 * S, 234 * S)], fill=(60, 150, 240, 255))
    d.polygon([(x * S, y * S) for x, y in [(128, 62), (180, 82), (172, 140), (128, 188), (84, 140), (76, 82)]], fill=(200, 240, 255, 255))


# ---- Gatebreaker icons
def badge(name, ring, fill, draw_inner):
    img = canvas(); d = ImageDraw.Draw(img); n = 256 * S
    d.ellipse((10 * S, 16 * S, n - 10 * S, n - 4 * S), fill=tuple(int(c * 0.55) for c in ring[:3]) + (255,))
    d.ellipse((10 * S, 8 * S, n - 10 * S, n - 12 * S), fill=ring)
    d.ellipse((30 * S, 28 * S, n - 30 * S, n - 32 * S), fill=fill)
    draw_inner(d)
    g = Image.new('L', img.size, 0); ImageDraw.Draw(g).ellipse((60 * S, 34 * S, 160 * S, 86 * S), fill=90)
    g = g.filter(ImageFilter.GaussianBlur(12 * S)); img.paste(Image.new('RGBA', img.size, (255, 255, 255, 255)), (0, 0), Image.composite(g, Image.new('L', img.size, 0), img.split()[3]))
    done(img, name)
W = (255, 255, 255, 255)
def P(pts): return [(x * S, y * S) for x, y in pts]
import math as _m
star('star', (255, 214, 64, 255), (240, 150, 20, 255), (120, 60, 10, 255))
star('star_off', (200, 206, 222, 255), (150, 158, 178, 255), (80, 88, 110, 255))
disc_icon('coin', (170, 100, 10, 255), (255, 196, 40, 255), (255, 222, 100, 255), 'coin', (230, 160, 20, 255))
glyph_btn('pause', lambda d, n: (d.rounded_rectangle((72 * S, 56 * S, 112 * S, 200 * S), radius=14 * S, fill=W),
                                 d.rounded_rectangle((144 * S, 56 * S, 184 * S, 200 * S), radius=14 * S, fill=W)))
glyph_btn('lock', lock)
# ---- abilities (white glyph on coloured badge)
def chute(d):
    d.pieslice(P2(48, 40, 208, 170), 180, 360, fill=W)
    for x in (56, 128, 200): d.line(P([(x, 104), (128, 176)]), fill=W, width=8 * S)
    d.rounded_rectangle(P2(104, 168, 152, 212), radius=6 * S, fill=W)
def P2(a, b, c, e): return (a * S, b * S, c * S, e * S)
def boots(d):
    for k, ox in enumerate((0, 40)):
        d.polygon(P([(70 + ox, 60), (110 + ox, 60), (112 + ox, 160), (160 + ox, 168), (162 + ox, 196), (68 + ox, 196)]), fill=W if k else (255, 255, 255, 170))
    for i in range(3): d.line(P([(30, 100 + i * 28), (60, 100 + i * 28)]), fill=W, width=10 * S)
def flake(d):
    c = 128
    for i in range(6):
        a = _m.radians(i * 60); x, y = c + _m.cos(a) * 88, c + _m.sin(a) * 88
        d.line(P([(c, c), (x, y)]), fill=W, width=16 * S)
        for s in (-1, 1):
            bx, by = c + _m.cos(a) * 56, c + _m.sin(a) * 56; a2 = a + s * 0.7
            d.line(P([(bx, by), (bx + _m.cos(a2) * 30, by + _m.sin(a2) * 30)]), fill=W, width=12 * S)
def cannon(d):
    d.ellipse(P2(70, 70, 186, 186), fill=W)
    d.line(P([(150, 100), (200, 56)]), fill=W, width=18 * S)
    for i in range(3):
        a = _m.radians(220 + i * 25); d.line(P([(208, 48), (208 + _m.cos(a) * -30, 48 + _m.sin(a) * 30)]), fill=(255, 230, 120, 255), width=8 * S)
badge('ab_airdrop', (60, 130, 230, 255), (90, 170, 255, 255), chute)
badge('ab_march', (220, 120, 30, 255), (255, 160, 60, 255), boots)
badge('ab_frost', (60, 180, 220, 255), (120, 215, 245, 255), flake)
badge('ab_barrage', (190, 50, 50, 255), (235, 90, 80, 255), cannon)
# ---- upgrades
def plus_man(d):
    d.ellipse(P2(84, 44, 144, 104), fill=W); d.rounded_rectangle(P2(70, 108, 158, 210), radius=30 * S, fill=W)
    d.rectangle(P2(170, 110, 186, 170), fill=W); d.rectangle(P2(148, 132, 208, 148), fill=W)
def chevrons(d):
    for i in range(3): d.line(P([(70, 180 - i * 44), (128, 140 - i * 44), (186, 180 - i * 44)]), fill=W, width=18 * S, joint='curve')
def tower(d):
    d.rectangle(P2(84, 90, 172, 210), fill=W)
    for x in (84, 116, 148): d.rectangle(P2(x, 60, x + 24, 92), fill=W)
    d.rounded_rectangle(P2(112, 160, 144, 210), radius=14 * S, fill=(0, 0, 0, 0))
def hourglass(d):
    d.polygon(P([(76, 50), (180, 50), (136, 128), (180, 206), (76, 206), (120, 128)]), fill=W)
    d.rectangle(P2(64, 40, 192, 56), fill=W); d.rectangle(P2(64, 200, 192, 216), fill=W)
badge('up_recruit', (70, 150, 70, 255), (110, 200, 100, 255), plus_man)
badge('up_boots', (220, 120, 30, 255), (255, 165, 70, 255), boots)
badge('up_veteran', (150, 90, 200, 255), (190, 130, 240, 255), chevrons)
badge('up_bastion', (110, 110, 130, 255), (160, 165, 185, 255), tower)
badge('up_quarter', (40, 140, 170, 255), (80, 190, 220, 255), hourglass)
# ---- region types (small white glyphs used next to troop badges)
def crown(d):
    d.polygon(P([(40, 190), (40, 80), (88, 130), (128, 60), (168, 130), (216, 80), (216, 190)]), fill=W)
def shieldg(d): d.polygon(P([(128, 30), (216, 64), (204, 150), (128, 228), (52, 150), (40, 64)]), fill=W)
def anchor(d):
    d.ellipse(P2(104, 26, 152, 74), outline=W, width=14 * S); d.line(P([(128, 74), (128, 218)]), fill=W, width=18 * S)
    d.line(P([(84, 100), (172, 100)]), fill=W, width=14 * S); d.arc(P2(52, 120, 204, 224), 20, 160, fill=W, width=18 * S)
def pick(d):
    d.arc(P2(40, 40, 216, 170), 200, 340, fill=W, width=22 * S); d.line(P([(128, 56), (128, 226)]), fill=W, width=20 * S)
for nm, fn in (('t_capital', crown), ('t_fort', shieldg), ('t_port', anchor), ('t_mine', pick)): glyph_btn(nm, fn)
def sword(d):
    d.polygon(P([(128, 20), (148, 50), (144, 170), (112, 170), (108, 50)]), fill=W)
    d.rectangle(P2(76, 166, 180, 184), fill=W); d.rectangle(P2(118, 184, 138, 226), fill=W); d.ellipse(P2(112, 220, 144, 246), fill=W)
glyph_btn('sword', sword)
def trophy(d):
    d.pieslice(P2(64, 30, 192, 170), 0, 180, fill=W); d.rectangle(P2(64, 30, 192, 100), fill=W)
    d.arc(P2(28, 50, 96, 120), 90, 270, fill=W, width=12 * S); d.arc(P2(160, 50, 228, 120), 270, 90, fill=W, width=12 * S)
    d.rectangle(P2(116, 160, 140, 196), fill=W); d.rounded_rectangle(P2(76, 196, 180, 224), radius=8 * S, fill=W)
glyph_btn('trophy', trophy)
glyph_btn('half', lambda d, n: (d.ellipse(P2(40, 40, 216, 216), outline=W, width=16 * S), d.pieslice(P2(40, 40, 216, 216), 90, 270, fill=W)))
glyph_btn('full', lambda d, n: d.ellipse(P2(40, 40, 216, 216), fill=W))
print('ui ok')
