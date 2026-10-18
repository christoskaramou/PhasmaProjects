# Textures (road, ground per theme, horizon panoramas, banners, signs), skybox and sound for Out Run Remix
import numpy as np, os, math
from PIL import Image, ImageDraw, ImageFilter, ImageFont
from audiolib import *
T = os.path.join(R, 'Textures'); SK = os.path.join(R, 'Skybox'); os.makedirs(T, exist_ok=True); os.makedirs(SK, exist_ok=True)
rg = np.random.default_rng(11)
F = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
def noise(w, h, oct=5, seed=0):
    r = np.random.default_rng(seed); g = np.zeros((h, w))
    for o in range(oct):
        f = 4 * 2 ** o; s = r.random((f, f)); g += np.asarray(Image.fromarray((s * 255).astype(np.uint8)).resize((w, h), Image.BICUBIC)) / 255 / 2 ** o
    return g / g.max()
def to_img(a): return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
# road: 4 lanes, white edge lines, dashed lane lines (dash = half the 5 m segment)
W, H = 512, 256
a = np.ones((H, W, 3)) * 78; a *= (0.85 + 0.25 * noise(W, H, 6, 1))[..., None]
a[:, 10:22] = 230; a[:, W - 22:W - 10] = 230
for k in (1, 2, 3):
    x = int(W * k / 4); a[:H // 2, x - 5:x + 5] = 225
to_img(a).save(os.path.join(T, 'road.png'))
# grounds: 512 x 512, u across (road at u = 0.5), v along the road
def ground(name, base, var=0.25, fn=None, seed=2):
    g = np.ones((512, 512, 3)) * np.array(base, float); g *= (1 - var / 2 + var * noise(512, 512, 6, seed))[..., None]
    if fn: fn(g)
    to_img(g).save(os.path.join(T, 'gr_' + name + '.png'))
def sea_right(g):
    u = np.arange(512)
    g[:, u > 330] = np.array((40, 110, 170)) * (0.9 + 0.2 * noise(512, 512, 4, 9)[:, u > 330][..., None])
    g[:, 318:334] = (225, 215, 180)
def rows(g):
    for x in range(0, 512, 16): g[:, x:x + 6] *= 0.7
def stripes(g):
    for y in range(0, 512, 64): g[y:y + 32] *= 0.9
def lake_left(g):
    u = np.arange(512); g[:, u < 190] = np.array((50, 100, 150)) * (0.9 + 0.2 * noise(512, 512, 4, 7)[:, u < 190][..., None])
ground('beach', (220, 200, 150), 0.2, sea_right)
ground('grass', (82, 140, 58), 0.3, stripes)
ground('canyon', (170, 92, 58), 0.3)
ground('dry', (160, 140, 90), 0.35)
ground('alps', (120, 160, 110), 0.25, stripes)
ground('dark', (60, 105, 60), 0.3, stripes)
ground('wheat', (215, 180, 90), 0.25, rows)
ground('town', (110, 110, 105), 0.15)
ground('desert', (225, 190, 130), 0.25)
ground('vine', (110, 120, 60), 0.2, rows)
ground('lake', (82, 140, 58), 0.3, lake_left)
# horizon panoramas 2048 x 512 (top = sky, bottom edge meets the ground)
HW, HH = 2048, 512
def pano(name, top, bot, layers, sun=None, sea=None):
    y = np.linspace(0, 1, HH)[:, None, None]
    im = to_img((np.array(top) * (1 - y) + np.array(bot) * y) * np.ones((HH, HW, 3))).convert('RGBA')
    d = ImageDraw.Draw(im)
    if sun:
        x, yy, r, c = sun
        for k in range(10, 0, -1): d.ellipse((x - r * (1 + k * .3), yy - r * (1 + k * .3), x + r * (1 + k * .3), yy + r * (1 + k * .3)), fill=c + (int(14 * (11 - k) / 10),))
        d.ellipse((x - r, yy - r, x + r, yy + r), fill=c + (255,))
    for base, amp, col, seed, n in layers:
        r = np.random.default_rng(seed); xs = np.linspace(0, HW, n); ys = np.zeros(n); f = 1.0
        for o in range(5):
            k = 4 * 2 ** o; v = r.uniform(-1, 1, k + 1); v[-1] = v[0]
            ys += np.interp(np.arange(n), np.linspace(0, n - 1, k + 1), v) * amp * f; f *= 0.5
        d.polygon([(x, base - y_) for x, y_ in zip(xs, ys)] + [(HW, HH), (0, HH)], fill=col + (255,))
    if sea: d.rectangle((0, sea[0], HW, HH), fill=sea[1] + (255,))
    full = Image.new('RGB', (HW, HH * 2), tuple(int(v) for v in top)); full.paste(im.convert('RGB'), (0, HH))
    full.save(os.path.join(T, 'hz_' + name + '.png'))
pano('beach', (70, 140, 230), (200, 225, 245), [(470, 30, (150, 175, 200), 1, 256)], (1500, 200, 18, (255, 250, 225)), (470, (50, 120, 190)))
pano('green', (80, 150, 230), (210, 230, 240), [(430, 60, (120, 150, 170), 2, 256), (480, 30, (70, 120, 70), 3, 256)])
pano('canyon', (90, 140, 210), (240, 200, 160), [(380, 110, (160, 80, 55), 4, 128), (470, 50, (120, 60, 40), 5, 128)])
pano('pale', (120, 160, 210), (235, 225, 200), [(450, 40, (170, 150, 120), 6, 256)])
pano('alps', (60, 120, 220), (210, 225, 245), [(330, 160, (235, 240, 250), 7, 96), (420, 90, (110, 130, 150), 8, 128), (480, 30, (70, 110, 70), 9, 256)])
pano('cloudy', (130, 140, 160), (205, 210, 215), [(400, 120, (110, 120, 130), 10, 128), (470, 50, (60, 90, 60), 11, 256)])
pano('wheat', (70, 140, 235), (220, 230, 240), [(480, 15, (120, 150, 100), 12, 256)])
pano('town', (90, 150, 230), (225, 230, 240), [(470, 20, (130, 140, 150), 13, 256)], None, (478, (50, 115, 180)))
pano('dusk', (90, 70, 140), (250, 160, 110), [(440, 50, (90, 70, 90), 14, 256)], (1100, 400, 26, (255, 210, 150)))
pano('desert', (80, 140, 225), (245, 215, 170), [(430, 70, (190, 130, 90), 15, 128), (480, 25, (160, 110, 80), 16, 256)], (600, 170, 16, (255, 250, 230)))
pano('lake', (70, 140, 230), (210, 230, 245), [(400, 110, (120, 140, 160), 17, 128), (470, 40, (60, 100, 70), 18, 256)])
# banners and signs
def banner(name, txt, bg, fg):
    im = Image.new('RGB', (1024, 96), bg); d = ImageDraw.Draw(im)
    d.rectangle((0, 0, 1023, 95), outline=fg, width=6)
    d.text((512, 50), txt, fill=fg, font=ImageFont.truetype(F, 64), anchor='mm'); im.save(os.path.join(T, name + '.png'))
banner('ban_start', 'START', (200, 30, 30), (255, 255, 255))
banner('ban_check', 'CHECKPOINT', (30, 60, 160), (255, 230, 80))
banner('ban_goal', 'GOAL', (30, 140, 60), (255, 255, 255))
im = Image.new('RGB', (256, 128), (250, 200, 30)); d = ImageDraw.Draw(im); d.rectangle((0, 0, 255, 127), outline=(20, 20, 20), width=8)
for k in range(3): x = 60 + k * 60; d.polygon([(x + 30, 20), (x - 10, 64), (x + 30, 108), (x + 50, 108), (x + 10, 64), (x + 50, 20)], fill=(20, 20, 20))
im.save(os.path.join(T, 'sign_curve.png')); im.transpose(Image.FLIP_LEFT_RIGHT).save(os.path.join(T, 'sign_curve_r.png'))
im = Image.new('RGB', (128, 64), (255, 255, 255)); d = ImageDraw.Draw(im)
for i in range(8):
    for j in range(4): d.rectangle((i * 16, j * 16, i * 16 + 15, j * 16 + 15), fill=(20, 20, 20) if (i + j) % 2 else (250, 250, 250))
im.save(os.path.join(T, 'flag.png'))
# building facade
im = Image.new('RGB', (256, 256), (220, 210, 190)); d = ImageDraw.Draw(im)
for y in range(16, 256, 40):
    for x in range(14, 256, 40): d.rectangle((x, y, x + 22, y + 26), fill=(70, 100, 130))
im.save(os.path.join(T, 'facade.png'))
# skybox
SW_, SH_ = 512, 256
v = (np.arange(SH_) + 0.5) / SH_; y = np.sin((0.5 - v) * np.pi)[:, None] * np.ones((1, SW_)); t = np.clip(y, 0, 1)[..., None]
sky = np.array([0.95, 0.93, 0.88]) * (1 - t) + np.array([0.4, 0.6, 0.95]) * t; sky[y < 0] = np.array([0.35, 0.33, 0.28])
def rgbe(a):
    m = a.max(-1); e = np.ceil(np.log2(np.maximum(m, 1e-32))); sc = np.where(m > 1e-32, 256.0 / 2 ** e, 0)
    o = np.zeros(a.shape[:2] + (4,), np.uint8); o[..., :3] = np.clip(a * sc[..., None], 0, 255).astype(np.uint8)
    o[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8); return o
with open(os.path.join(SK, 'day.hdr'), 'wb') as f:
    f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % (SH_, SW_)); f.write(rgbe(sky.astype(np.float32)).tobytes())

# ------------------------------------------------------------------ audio
def nz(d, k): return rng.standard_normal(int(SR * d)) * np.exp(-tt(d) * k)
def lowp(x, a=0.08):
    y = np.zeros_like(x); s = 0
    for i, v_ in enumerate(x): s += a * (v_ - s); y[i] = s
    return y
def engine(f, d=0.16):
    t = tt(d); ph = 2 * np.pi * f * t
    x = np.sign(np.sin(ph)) * 0.5 + np.sin(ph * 0.5) * 0.6 + np.sin(ph * 2) * 0.25 + lowp(rng.standard_normal(len(t)), 0.3) * 0.25
    e = np.ones(len(t)); n = int(0.02 * SR); e[:n] = np.linspace(0, 1, n); e[-n:] = np.linspace(1, 0, n)
    return x * e
for i in range(10): save('eng%d.wav' % i, engine(42 * 1.17 ** i), 0.16)
save('skid.wav', env(lowp(nz(0.35, 2), 0.5) + sq(900, 0.35, 0.5) * 0.15), 0.2)
save('crash.wav', env(lowp(nz(1.2, 3.5), 0.12) * 3 + sq(60, 1.2, 0.5) * 0.3 * np.exp(-tt(1.2) * 4)), 0.5)
save('bump.wav', env(lowp(nz(0.25, 12), 0.2) * 2 + sq(110, 0.25, 0.5) * 0.3 * np.exp(-tt(0.25) * 12)), 0.35)
save('shift.wav', env(sq(300, 0.06, 0.3) * np.exp(-tt(0.06) * 50) + nz(0.06, 60) * 0.3), 0.25)
save('beep.wav', env(sq(880, 0.25, 0.5)), 0.25)
save('go.wav', env(sq(1760, 0.6, 0.5) * np.exp(-tt(0.6) * 2)), 0.25)
save('check.wav', melody([('C5', 0.25), ('E5', 0.25), ('G5', 0.25), ('C6', 0.75), ('-', 0.25), ('E6', 0.25), ('G6', 1)], 360, 'sq', 0.25), 0.3)
save('goal.wav', mix(melody([('C5', 0.5), ('E5', 0.5), ('G5', 0.5), ('C6', 1), ('A5', 0.5), ('C6', 0.5), ('E6', 2)], 240, 'sq', 0.25),
                     melody([('C3', 1), ('G3', 1), ('A3', 1), ('E3', 1), ('F3', 2)], 240, 'tri')), 0.3)
save('timeup.wav', mix(melody([('G4', 1), ('F#4', 1), ('F4', 1), ('E4', 3)], 180, 'sq', 0.5)), 0.3)
save('click.wav', env(sq(1200, 0.04, 0.3) * np.exp(-tt(0.04) * 60)), 0.25)
save('warn.wav', env(sq(660, 0.1, 0.5)), 0.2)
save('offroad.wav', env(lowp(nz(0.18, 4), 0.35)), 0.12)
def loop(bass, lead, bpm, nm, vol=0.26):
    b = melody(bass, bpm, 'tri'); l = melody(lead, bpm, 'sq', 0.25) if lead else np.zeros(1)
    save(nm, mix(b, l * 0.45), vol)
# three original radio tracks (not the Sega compositions)
loop(([('F2', 0.5), ('F3', 0.5)] * 2 + [('A#2', 0.5), ('A#3', 0.5)] * 2 + [('C3', 0.5), ('C4', 0.5)] * 2 + [('A2', 0.5), ('A3', 0.5)] * 2) * 2,
     [('A4', 0.5), ('C5', 0.5), ('F5', 1), ('E5', 0.5), ('D5', 0.5), ('C5', 1), ('D5', 0.5), ('F5', 0.5), ('A5', 1), ('G5', 2),
      ('F5', 0.5), ('G5', 0.5), ('A5', 1), ('C6', 1), ('A#5', 0.5), ('A5', 0.5), ('G5', 1), ('F5', 0.5), ('E5', 0.5), ('F5', 2)], 260, 'radio1.wav')
loop(([('D3', 1), ('A2', 1), ('G2', 1), ('A2', 1)]) * 2,
     [('F#5', 1), ('E5', 0.5), ('D5', 0.5), ('E5', 1), ('A4', 1), ('B4', 1), ('D5', 1), ('C#5', 2),
      ('D5', 1), ('F#5', 1), ('A5', 1), ('G5', 0.5), ('F#5', 0.5), ('E5', 1), ('D5', 1), ('E5', 2)], 200, 'radio2.wav')
loop(([('E2', 0.5), ('E3', 0.5), ('B2', 0.5), ('E3', 0.5)] * 2 + [('C3', 0.5), ('G3', 0.5), ('D3', 0.5), ('A3', 0.5)] * 2) * 2,
     [('B4', 0.5), ('E5', 0.5), ('G5', 0.5), ('B5', 0.5), ('A5', 1), ('G5', 0.5), ('F#5', 0.5), ('E5', 2), ('G5', 0.5), ('A5', 0.5), ('B5', 1),
      ('D6', 1), ('C6', 0.5), ('B5', 0.5), ('A5', 1), ('G5', 0.5), ('F#5', 0.5), ('E5', 2)], 280, 'radio3.wav')
loop([('C3', 1), ('A2', 1), ('F2', 1), ('G2', 1)] * 2, [('E5', 1), ('G5', 1), ('A5', 1), ('G5', 1), ('E5', 1), ('D5', 1), ('C5', 2)], 150, 'title.wav')
loop([('C3', 2), ('F3', 2), ('G3', 2), ('C3', 2)], [('E5', 2), ('A5', 2), ('B5', 2), ('C6', 2)], 120, 'ending.wav')
print('assets ok')
