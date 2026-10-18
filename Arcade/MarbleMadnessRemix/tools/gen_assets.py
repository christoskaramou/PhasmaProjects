# Textures (course tiles per race, goal checker, marble swirl, flag) and sound for Marble Madness Remix.
# The music is original (not Atari's score).
import numpy as np, os
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from audiolib import *
T = os.path.join(R, 'Textures'); os.makedirs(T, exist_ok=True)
F = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
PALS = {1: ((150, 190, 225), (120, 165, 210), (60, 70, 110)), 2: ((205, 192, 140), (178, 160, 112), (95, 72, 60)),
        3: ((170, 202, 160), (138, 175, 128), (58, 86, 70)), 4: ((212, 172, 192), (186, 142, 166), (92, 60, 92)),
        5: ((230, 200, 120), (210, 168, 98), (112, 80, 50)), 6: ((182, 182, 198), (150, 150, 172), (60, 60, 78))}
def tile(col, nm, line=0.62, inner=True):
    N = 64; a = np.ones((N, N, 3)) * np.array(col, float)
    yy, xx = np.mgrid[0:N, 0:N]
    if inner: a *= (0.97 + 0.06 * (((xx // 32) + (yy // 32)) % 2))[..., None]
    edge = (xx < 2) | (yy < 2) | (xx >= N - 2) | (yy >= N - 2)
    a[edge] = a[edge] * line
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(os.path.join(T, nm + '.png'))
for k, (A, B, W) in PALS.items():
    tile(A, f'c{k}_A'); tile(B, f'c{k}_B'); tile(tuple(int(v * 0.72) for v in A), f'c{k}_W', 0.7)
    N = 64; a = np.ones((N, N, 3)) * np.array(W, float); xx = np.arange(N)
    a[:, (xx < 2) | (xx >= N - 2)] *= 0.6; a[:, 30:34] *= 0.85
    Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).save(os.path.join(T, f'c{k}_wall.png'))
im = Image.new('RGB', (64, 64), (240, 240, 235)); d = ImageDraw.Draw(im)
for i in range(4):
    for j in range(4):
        if (i + j) % 2: d.rectangle((i * 16, j * 16, i * 16 + 15, j * 16 + 15), fill=(30, 30, 34))
for k in range(1, 7): im.save(os.path.join(T, f'c{k}_G.png'))
# marble: deep blue glass with a cream swirl band that shows the rolling
W_, H_ = 256, 128
u, v = np.meshgrid(np.linspace(0, 1, W_), np.linspace(0, 1, H_))
band = np.abs(np.sin((v * 2.0 + 0.35 * np.sin(u * 2 * np.pi * 2)) * np.pi))
a = np.zeros((H_, W_, 3)); a[...] = (30, 80, 190)
a[band < 0.28] = (240, 230, 200)
a[(band >= 0.28) & (band < 0.36)] = (120, 160, 230)
Image.fromarray(a.astype(np.uint8)).filter(ImageFilter.GaussianBlur(0.8)).save(os.path.join(T, 'marble.png'))
im = Image.new('RGB', (128, 64), (210, 40, 40)); d = ImageDraw.Draw(im)
d.text((64, 33), 'GOAL', fill=(250, 245, 230), font=ImageFont.truetype(F, 30), anchor='mm'); im.save(os.path.join(T, 'flag.png'))
# ------------------------------------------------------------------ audio
def nz(d, k): return rng.standard_normal(int(SR * d)) * np.exp(-tt(d) * k)
def lowp(x, a=0.08):
    y = np.zeros_like(x); s = 0
    for i, v_ in enumerate(x): s += a * (v_ - s); y[i] = s
    return y
for i in range(6):           # rolling rumble grains, pitch rises with speed
    d = 0.14; t = tt(d); f = 40 + i * 18
    x = lowp(rng.standard_normal(len(t)), 0.04 + i * 0.02) * 3 + np.sin(2 * np.pi * f * t) * 0.3
    save(f'roll{i}.wav', env(x, 0.02, 0.03), 0.10 + i * 0.012)
save('bump.wav', env(lowp(nz(0.18, 25), 0.3) * 2 + np.sin(2 * np.pi * 180 * tt(0.18)) * np.exp(-tt(0.18) * 30)), 0.3)
save('clack.wav', env(np.sin(2 * np.pi * 1300 * tt(0.08)) * np.exp(-tt(0.08) * 60) + nz(0.08, 80) * 0.3), 0.35)
save('fall.wav', env(sq(1, 1.0) * 0 + np.sin(2 * np.pi * np.cumsum(np.linspace(1400, 300, int(SR * 1.0))) / SR) * 0.6, 0.01, 0.1), 0.25)
save('break.wav', env(sum(np.sin(2 * np.pi * f * tt(0.5)) * np.exp(-tt(0.5) * k) for f, k in ((2400, 9), (3100, 12), (3900, 14), (5200, 18))) + nz(0.5, 10) * 0.6), 0.35)
save('splat.wav', env(lowp(nz(0.6, 5), 0.15) * 2 + np.sin(2 * np.pi * np.cumsum(np.linspace(300, 80, int(SR * 0.6))) / SR) * 0.5), 0.35)
save('munch.wav', np.concatenate([env(lowp(nz(0.09, 20), 0.3) * 2) for _ in range(4)]), 0.35)
save('slam.wav', env(lowp(nz(0.5, 9), 0.1) * 3 + np.sin(2 * np.pi * 60 * tt(0.5)) * np.exp(-tt(0.5) * 8)), 0.5)
save('hop.wav', env(np.sin(2 * np.pi * np.cumsum(np.linspace(200, 500, int(SR * 0.12))) / SR), 0.005, 0.03), 0.2)
save('beep.wav', env(sq(880, 0.2, 0.5)), 0.22)
save('go.wav', env(sq(1320, 0.5, 0.5) * np.exp(-tt(0.5) * 2)), 0.25)
save('tick.wav', env(sq(1500, 0.03, 0.5)), 0.15)
save('warn.wav', env(sq(660, 0.12, 0.5)), 0.22)
save('click.wav', env(sq(1200, 0.04, 0.3) * np.exp(-tt(0.04) * 60)), 0.25)
save('goal.wav', mix(melody([('C5', 0.5), ('E5', 0.5), ('G5', 0.5), ('C6', 1), ('G5', 0.5), ('C6', 2)], 260, 'sq', 0.25),
                     melody([('C3', 1), ('G3', 1), ('C3', 2), ('C3', 2)], 260, 'tri')), 0.3)
save('timeup.wav', mix(melody([('G4', 1), ('F#4', 1), ('F4', 1), ('E4', 3)], 170, 'sq', 0.5)), 0.3)
def loop(bass, lead, bpm, nm, vol=0.24):
    b = melody(bass, bpm, 'tri'); l = melody(lead, bpm, 'sq', 0.25) if lead else np.zeros(1)
    save(nm, mix(b, l * 0.45), vol)
# original tunes in a light, bouncy spirit (one per pair of races), not Atari's score
loop(([('C3', 0.5), ('G3', 0.5)] * 2 + [('A2', 0.5), ('E3', 0.5)] * 2 + [('F2', 0.5), ('C3', 0.5)] * 2 + [('G2', 0.5), ('D3', 0.5)] * 2) * 2,
     [('E5', 0.5), ('G5', 0.5), ('C6', 1), ('B5', 0.5), ('A5', 0.5), ('G5', 1), ('A5', 0.5), ('F5', 0.5), ('D5', 1), ('G5', 2),
      ('E5', 0.5), ('F5', 0.5), ('G5', 1), ('C6', 1), ('B5', 0.5), ('G5', 0.5), ('A5', 1), ('B5', 0.5), ('D6', 0.5), ('C6', 2)], 200, 'race1.wav')
loop(([('D3', 1), ('A2', 1), ('B2', 1), ('F#2', 1), ('G2', 1), ('D3', 1), ('G2', 1), ('A2', 1)]),
     [('F#5', 1), ('A5', 0.5), ('F#5', 0.5), ('E5', 1), ('D5', 1), ('B4', 1), ('D5', 1), ('E5', 2), ('G5', 1), ('F#5', 0.5), ('E5', 0.5), ('D5', 1), ('C#5', 1), ('D5', 2)], 180, 'race2.wav')
loop(([('E2', 0.5), ('E3', 0.5)] * 4 + [('C3', 0.5), ('C4', 0.5)] * 2 + [('D3', 0.5), ('D4', 0.5)] * 2),
     [('B4', 0.5), ('E5', 0.5), ('G5', 0.5), ('B5', 0.5), ('A5', 1), ('G5', 0.5), ('F#5', 0.5), ('E5', 2), ('G5', 0.5), ('A5', 0.5), ('B5', 1), ('C6', 1), ('B5', 1), ('E5', 2)], 230, 'race3.wav')
loop([('C3', 1), ('A2', 1), ('F2', 1), ('G2', 1)] * 2, [('E5', 1), ('G5', 1), ('A5', 1), ('G5', 1), ('E5', 1), ('D5', 1), ('C5', 2)], 140, 'title.wav')
loop([('C3', 2), ('F3', 2), ('G3', 2), ('C3', 2)], [('E5', 2), ('A5', 2), ('B5', 2), ('C6', 2)], 120, 'ending.wav')
print('assets ok')
# night backdrop: deep indigo gradient with faint stars (the course floats in a dark void like the arcade)
SK = os.path.join(R, 'Skybox'); os.makedirs(SK, exist_ok=True)
SW_, SH_ = 1024, 512
v = (np.arange(SH_) + 0.5) / SH_; y = np.sin((0.5 - v) * np.pi)[:, None] * np.ones((1, SW_)); t = np.clip(y, 0, 1)[..., None]
sky = np.array([0.10, 0.08, 0.20]) * (1 - t) + np.array([0.02, 0.02, 0.06]) * t
sky[y < 0] = np.array([0.03, 0.025, 0.07])
st = rng.random((SH_, SW_)) > 0.9985; sky[st & (y > 0.05)] = 1.2
def rgbe(a):
    m = a.max(-1); e = np.ceil(np.log2(np.maximum(m, 1e-32))); sc = np.where(m > 1e-32, 256.0 / 2 ** e, 0)
    o = np.zeros(a.shape[:2] + (4,), np.uint8); o[..., :3] = np.clip(a * sc[..., None], 0, 255).astype(np.uint8)
    o[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8); return o
with open(os.path.join(SK, 'night.hdr'), 'wb') as f:
    f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % (SH_, SW_)); f.write(rgbe(sky.astype(np.float32)).tobytes())
print('sky ok')
