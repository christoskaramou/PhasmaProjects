#!/usr/bin/env python3
"""UI icons for Gatebreaker Squad: smooth, outlined, glossy mobile-style PNGs (supersampled)."""
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
def medal_inner(d):
    d.polygon(P(star_pts(128, 124, 70, 30)), fill=(255, 240, 160, 255))
badge('medal', (230, 150, 30, 255), (250, 190, 50, 255), medal_inner)
def rifle(d):
    d.rounded_rectangle((52 * S, 112 * S, 210 * S, 136 * S), radius=8 * S, fill=W)
    d.polygon(P([(52, 118), (30, 150), (40, 160), (78, 136)]), fill=W)
    d.rounded_rectangle((116 * S, 132 * S, 136 * S, 176 * S), radius=6 * S, fill=W)
    d.rounded_rectangle((150 * S, 132 * S, 166 * S, 160 * S), radius=6 * S, fill=W)
def shotgun(d):
    d.rounded_rectangle((44 * S, 108 * S, 216 * S, 128 * S), radius=8 * S, fill=W)
    d.rounded_rectangle((120 * S, 126 * S, 200 * S, 142 * S), radius=7 * S, fill=W)
    d.polygon(P([(48, 114), (26, 158), (44, 164), (84, 128)]), fill=W)
def minigun(d):
    for y in (100, 120, 140): d.rounded_rectangle((96 * S, y * S, 222 * S, (y + 14) * S), radius=7 * S, fill=W)
    d.rounded_rectangle((44 * S, 92 * S, 112 * S, 166 * S), radius=18 * S, fill=W)
    d.rounded_rectangle((60 * S, 162 * S, 84 * S, 196 * S), radius=8 * S, fill=W)
def rocket(d):
    d.rounded_rectangle((40 * S, 104 * S, 196 * S, 144 * S), radius=20 * S, fill=W)
    d.polygon(P([(196, 104), (228, 124), (196, 144)]), fill=W)
    d.rounded_rectangle((90 * S, 140 * S, 110 * S, 182 * S), radius=7 * S, fill=W)
def laser(d):
    d.rounded_rectangle((48 * S, 108 * S, 170 * S, 144 * S), radius=16 * S, fill=W)
    d.rounded_rectangle((166 * S, 118 * S, 226 * S, 134 * S), radius=8 * S, fill=(160, 250, 255, 255))
    d.rounded_rectangle((84 * S, 140 * S, 104 * S, 184 * S), radius=7 * S, fill=W)
for nm, fn, ring, fill in (('w_rifle', rifle, (60, 120, 220, 255), (90, 160, 250, 255)), ('w_shotgun', shotgun, (220, 110, 40, 255), (250, 150, 70, 255)),
                           ('w_minigun', minigun, (200, 160, 30, 255), (240, 200, 60, 255)), ('w_rocket', rocket, (210, 60, 60, 255), (245, 100, 90, 255)),
                           ('w_laser', laser, (40, 170, 190, 255), (70, 210, 230, 255))):
    badge(nm, ring, fill, fn)
def jet(d):
    d.polygon(P([(128, 40), (142, 90), (214, 140), (214, 156), (142, 140), (138, 192), (164, 214), (164, 224), (128, 214), (92, 224), (92, 214), (118, 192), (114, 140), (42, 156), (42, 140), (114, 90)]), fill=W)
badge('air', (200, 70, 50, 255), (240, 110, 70, 255), jet)
def helmet(col):
    def f(d):
        d.chord((62 * S, 70 * S, 194 * S, 200 * S), 180, 360, fill=col)
        d.rounded_rectangle((52 * S, 128 * S, 204 * S, 148 * S), radius=8 * S, fill=col)
        d.rounded_rectangle((96 * S, 150 * S, 160 * S, 196 * S), radius=20 * S, fill=(255, 220, 190, 255))
    return f
badge('u_sol', (50, 110, 210, 255), (90, 150, 245, 255), helmet((60, 100, 60, 255)))
badge('u_vet', (120, 80, 200, 255), (160, 120, 240, 255), helmet((90, 70, 40, 255)))
badge('u_hvy', (200, 140, 20, 255), (245, 190, 50, 255), helmet((60, 60, 70, 255)))
def skull(d):
    d.ellipse((70 * S, 60 * S, 186 * S, 170 * S), fill=W)
    d.rounded_rectangle((96 * S, 150 * S, 160 * S, 196 * S), radius=10 * S, fill=W)
    d.ellipse((92 * S, 104 * S, 122 * S, 136 * S), fill=(200, 50, 50, 255)); d.ellipse((134 * S, 104 * S, 164 * S, 136 * S), fill=(200, 50, 50, 255))
badge('skull', (150, 30, 30, 255), (200, 50, 50, 255), skull)
img = canvas(128); m = Image.new('L', img.size, 0); ImageDraw.Draw(m).ellipse((16 * S, 16 * S, 112 * S, 112 * S), fill=255)
m = m.filter(ImageFilter.GaussianBlur(14 * S)); img.paste(Image.new('RGBA', img.size, (255, 255, 255, 255)), (0, 0), m); done(img, 'glow', 128)
print('ok', sorted(os.listdir(OUT)))
