# Textures (ocean, carrier deck, POW icons) and sound for 1942 Remix. Music is original (not Capcom's tune).
import numpy as np, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from audiolib import *
T = os.path.join(R, 'Textures'); os.makedirs(T, exist_ok=True)
F = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
def tnoise(w, h, f, seed):          # tileable value noise
    r = np.random.default_rng(seed); s = r.random((f, f)); s = np.tile(s, (3, 3))
    im = Image.fromarray((s * 255).astype(np.uint8)).resize((w * 3, h * 3), Image.BICUBIC)
    return np.asarray(im)[h:2 * h, w:2 * w] / 255.0
def to_img(a): return Image.fromarray(np.clip(a, 0, 255).astype(np.uint8))
# ocean: deep Pacific blue, soft swell bands and small whitecaps (tileable)
N = 512
n = sum(tnoise(N, N, 4 * 2 ** o, o) / 2 ** o for o in range(5)); n /= n.max()
base = np.array((40, 112, 170), float)
a = base * (0.85 + 0.3 * n)[..., None]
caps = tnoise(N, N, 128, 9) * tnoise(N, N, 32, 10)
m_ = caps > 0.7
a[m_] = a[m_] * 0.55 + np.array((170, 200, 215)) * 0.45
to_img(a).filter(ImageFilter.GaussianBlur(0.7)).save(os.path.join(T, 'ocean.png'))
# shallow reef water and island sand / jungle (slab caps use planar 0..1 UVs)
r = np.random.default_rng(3)
def flat_tex(nm, col, var, seed):
    g = sum(tnoise(256, 256, 4 * 2 ** o, seed + o) / 2 ** o for o in range(4)); g /= g.max()
    to_img(np.array(col, float) * (1 - var / 2 + var * g)[..., None]).save(os.path.join(T, nm + '.png'))
flat_tex('reef', (60, 160, 170), 0.35, 20); flat_tex('sand', (215, 195, 140), 0.25, 30); flat_tex('jungle', (50, 105, 45), 0.45, 40)
# carrier deck: planks grey, white centre line, yellow edge lines, number
W, H = 256, 1536
im = Image.new('RGB', (W, H), (95, 95, 92)); d = ImageDraw.Draw(im)
for y in range(0, H, 12): d.line((0, y, W, y), fill=(88, 88, 86))
d.line((W // 2, 40, W // 2, H - 40), fill=(235, 235, 230), width=5)
for x in (18, W - 18): d.line((x, 30, x, H - 30), fill=(220, 190, 60), width=4)
for y in range(200, H - 200, 120): d.line((W // 2 - 40, y, W // 2 + 40, y), fill=(235, 235, 230), width=3)
d.text((W // 2, H - 150), '42', fill=(235, 235, 230), font=ImageFont.truetype(F, 90), anchor='mm')
im.transpose(Image.FLIP_LEFT_RIGHT).save(os.path.join(T, 'deck.png'))
# POW icons: coloured disc, dark rim, white "POW" lettering
POW = {'red': (205, 40, 35), 'green': (40, 150, 60), 'white': (225, 225, 220), 'gray': (110, 110, 115), 'yellow': (230, 190, 40), 'orange': (235, 120, 30)}
for k, c in POW.items():
    im = Image.new('RGB', (256, 256), c); d = ImageDraw.Draw(im)
    d.ellipse((10, 10, 246, 246), outline=(30, 30, 30), width=10)
    tc = (30, 30, 30) if k in ('white', 'yellow') else (250, 250, 245)
    d.text((128, 132), 'POW', fill=tc, font=ImageFont.truetype(F, 74), anchor='mm')
    im.transpose(Image.FLIP_LEFT_RIGHT).save(os.path.join(T, 'pow_' + k + '.png'))
# ------------------------------------------------------------------ audio
def nz(d, k): return rng.standard_normal(int(SR * d)) * np.exp(-tt(d) * k)
def lowp(x, a=0.08):
    y = np.zeros_like(x); s = 0
    for i, v_ in enumerate(x): s += a * (v_ - s); y[i] = s
    return y
save('shot.wav', env(sq(1400, 0.07, 0.25) * np.exp(-tt(0.07) * 40) + nz(0.07, 50) * 0.4), 0.22)
save('hit.wav', env(sq(1800, 0.05, 0.5) * np.exp(-tt(0.05) * 60)), 0.18)
save('boom_s.wav', env(lowp(nz(0.45, 9), 0.25) * 2.5 + sq(90, 0.45, 0.5) * 0.25 * np.exp(-tt(0.45) * 9)), 0.4)
save('boom_l.wav', env(lowp(nz(1.4, 2.5), 0.12) * 3 + sq(55, 1.4, 0.5) * 0.35 * np.exp(-tt(1.4) * 3)), 0.55)
save('death.wav', mix(env(lowp(nz(1.2, 2.5), 0.15) * 3), melody([('E5', 0.5), ('C5', 0.5), ('A4', 0.5), ('E4', 1.5)], 240, 'sq', 0.5) * 0.4), 0.45)
save('roll.wav', np.concatenate([env(sq(220 * 2 ** (i / 12), 0.045, 0.3)) for i in list(range(0, 24, 2)) + list(range(24, 0, -2))]), 0.22)
save('pow.wav', melody([('C5', 0.25), ('E5', 0.25), ('G5', 0.25), ('C6', 0.25), ('E6', 0.25), ('G6', 0.75)], 480, 'sq', 0.25), 0.3)
save('kill_all.wav', env(lowp(nz(1.0, 3), 0.2) * 2 + sq(110, 1.0, 0.5) * 0.3 * np.exp(-tt(1.0) * 3)), 0.5)
save('extra.wav', melody([('G5', 0.25), ('C6', 0.25), ('E6', 0.25), ('G6', 0.25), ('-', 0.25), ('G6', 0.25), ('C7', 1)], 420, 'sq', 0.25), 0.3)
save('bank.wav', env(lowp(nz(0.18, 8), 0.12), 0.03, 0.08), 0.12)
save('click.wav', env(sq(1200, 0.04, 0.3) * np.exp(-tt(0.04) * 60)), 0.25)
save('warn.wav', np.concatenate([env(sq(660, 0.18, 0.5)), np.zeros(int(SR * 0.12))] * 4), 0.25)
save('drone.wav', env(sum(sq(f, 1.0, 0.5) * a for f, a in ((64, 0.5), (96, 0.3), (128, 0.2))) * (0.75 + 0.25 * np.sin(2 * np.pi * 6 * tt(1.0)))), 0.1)
def loop(bass, lead, bpm, nm, vol=0.26):
    b = melody(bass, bpm, 'tri'); l = melody(lead, bpm, 'sq', 0.25) if lead else np.zeros(1)
    save(nm, mix(b, l * 0.45), vol)
# original compositions in a brisk military-march spirit (not Capcom's music)
loop(([('G2', 0.5), ('D3', 0.5)] * 4 + [('C3', 0.5), ('G3', 0.5)] * 2 + [('D3', 0.5), ('A3', 0.5)] * 2) * 2,
     [('G4', 0.5), ('B4', 0.5), ('D5', 1), ('D5', 0.5), ('E5', 0.5), ('D5', 1), ('B4', 0.5), ('G4', 0.5), ('A4', 1), ('B4', 2),
      ('C5', 0.5), ('E5', 0.5), ('G5', 1), ('F#5', 0.5), ('E5', 0.5), ('D5', 1), ('C5', 0.5), ('A4', 0.5), ('B4', 1), ('G4', 2)], 220, 'bgm.wav', 0.24)
loop(([('E2', 0.5), ('B2', 0.5)] * 4 + [('C3', 0.5), ('G3', 0.5)] * 2 + [('D3', 0.5), ('A3', 0.5)] * 2),
     [('E5', 0.5), ('E5', 0.5), ('G5', 0.5), ('E5', 0.5), ('D5', 1), ('B4', 1), ('C5', 0.5), ('E5', 0.5), ('G5', 0.5), ('B5', 0.5), ('A5', 2)], 240, 'boss.wav', 0.24)
save('start.wav', mix(melody([('C5', 0.5), ('C5', 0.25), ('C5', 0.25), ('G5', 1), ('E5', 0.5), ('G5', 0.5), ('C6', 2)], 220, 'sq', 0.25),
                      melody([('C3', 1), ('G3', 1), ('C3', 2), ('C3', 2)], 220, 'tri')), 0.3)
save('clear.wav', mix(melody([('G4', 0.5), ('C5', 0.5), ('E5', 0.5), ('G5', 0.5), ('E5', 0.5), ('G5', 0.5), ('C6', 2)], 240, 'sq', 0.25),
                      melody([('C3', 2), ('F3', 1), ('G3', 1), ('C3', 2)], 240, 'tri')), 0.3)
save('gameover.wav', mix(melody([('C5', 1), ('B4', 1), ('A#4', 1), ('A4', 3)], 160, 'sq', 0.5)), 0.3)
loop([('C3', 1), ('G2', 1), ('A2', 1), ('E2', 1), ('F2', 1), ('C3', 1), ('F2', 1), ('G2', 1)],
     [('E5', 1), ('D5', 0.5), ('C5', 0.5), ('D5', 1), ('G4', 1), ('A4', 1), ('C5', 1), ('D5', 2)], 140, 'title.wav')
loop([('C3', 2), ('F3', 2), ('G3', 2), ('C3', 2)], [('E5', 2), ('A5', 2), ('B5', 2), ('C6', 2)], 120, 'ending.wav')
print('assets ok')
