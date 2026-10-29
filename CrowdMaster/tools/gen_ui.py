#!/usr/bin/env python3
"""UI icons for Crowd Master: smooth, outlined, glossy mobile-style PNGs (supersampled)."""
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
star('star', (255, 214, 64, 255), (240, 150, 20, 255), (120, 60, 10, 255))
star('star_off', (200, 206, 222, 255), (150, 158, 178, 255), (80, 88, 110, 255))

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
disc_icon('coin', (170, 100, 10, 255), (255, 196, 40, 255), (255, 222, 100, 255), 'coin', (230, 160, 20, 255))

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
gem()

def glyph_btn(name, draw):
    img = canvas(); d = ImageDraw.Draw(img); draw(d, 256 * S); done(img, name)
glyph_btn('pause', lambda d, n: (d.rounded_rectangle((72 * S, 56 * S, 112 * S, 200 * S), radius=14 * S, fill=(255, 255, 255, 255)),
                                 d.rounded_rectangle((144 * S, 56 * S, 184 * S, 200 * S), radius=14 * S, fill=(255, 255, 255, 255))))
def lock(d, n):
    d.rounded_rectangle((60 * S, 112 * S, 196 * S, 222 * S), radius=24 * S, fill=(255, 255, 255, 255))
    d.arc((82 * S, 40 * S, 174 * S, 150 * S), 180, 360, fill=(255, 255, 255, 255), width=22 * S)
    d.line((93 * S, 95 * S, 93 * S, 120 * S), fill=(255, 255, 255, 255), width=22 * S); d.line((163 * S, 95 * S, 163 * S, 120 * S), fill=(255, 255, 255, 255), width=22 * S)
    d.ellipse((114 * S, 148 * S, 142 * S, 176 * S), fill=(0, 0, 0, 0))
glyph_btn('lock', lock)
def shield(d, n):
    pts = [(128, 22), (222, 58), (210, 150), (128, 234), (46, 150), (34, 58)]
    d.polygon([(x * S, (y + 6) * S) for x, y in pts], fill=(20, 60, 140, 255))
    d.polygon([(x * S, y * S) for x, y in pts], fill=(90, 190, 255, 255))
    d.polygon([(128 * S, 22 * S), (222 * S, 58 * S), (210 * S, 150 * S), (128 * S, 234 * S)], fill=(60, 150, 240, 255))
    d.polygon([(x * S, y * S) for x, y in [(128, 62), (180, 82), (172, 140), (128, 188), (84, 140), (76, 82)]], fill=(200, 240, 255, 255))
glyph_btn('shield', shield)

# stickman badges for the army board (pawn / brute / giant / breaker)
def man(name, col, dark):
    img = canvas(); d = ImageDraw.Draw(img); n = 256 * S
    def limb(a, b, w, c):
        d.line([(a[0] * S, a[1] * S), (b[0] * S, b[1] * S)], fill=c, width=int(w * S))
        for p in (a, b): d.ellipse(((p[0] - w / 2) * S, (p[1] - w / 2) * S, (p[0] + w / 2) * S, (p[1] + w / 2) * S), fill=c)
    for off, c in ((6, dark), (0, col)):
        o = lambda p: (p[0], p[1] + off)
        d.ellipse(((96) * S, (22 + off) * S, (160) * S, (86 + off) * S), fill=c)
        limb(o((128, 96)), o((128, 160)), 40, c)
        limb(o((128, 104)), o((76, 148)), 24, c); limb(o((128, 104)), o((182, 70)), 24, c)
        limb(o((122, 160)), o((92, 228)), 26, c); limb(o((134, 160)), o((168, 226)), 26, c)
    g = Image.new('L', img.size, 0); ImageDraw.Draw(g).ellipse((104 * S, 28 * S, 134 * S, 52 * S), fill=150)
    g = g.filter(ImageFilter.GaussianBlur(4 * S)); img.paste(Image.new('RGBA', img.size, (255, 255, 255, 255)), (0, 0), g)
    done(img, name)
man('man_b', (60, 140, 255, 255), (20, 60, 160, 255))
man('man_v', (150, 100, 255, 255), (70, 40, 160, 255))
man('man_y', (255, 200, 50, 255), (170, 110, 10, 255))
man('man_w', (255, 140, 40, 255), (160, 70, 10, 255))
man('man_r', (240, 70, 70, 255), (140, 20, 20, 255))
# soft round glow (button / badge backing)
img = canvas(128); m = Image.new('L', img.size, 0); ImageDraw.Draw(m).ellipse((16 * S, 16 * S, 112 * S, 112 * S), fill=255)
m = m.filter(ImageFilter.GaussianBlur(14 * S)); img.paste(Image.new('RGBA', img.size, (255, 255, 255, 255)), (0, 0), m); done(img, 'glow', 128)
print('ok', sorted(os.listdir(OUT)))
