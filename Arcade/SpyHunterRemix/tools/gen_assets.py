# Textures (asphalt, verge, river) and sound for Spy Hunter Remix. The music is original (not the arcade's theme).
import numpy as np, os
from PIL import Image, ImageFilter
from audiolib import *
rng = np.random.default_rng(5)
T = os.path.join(R, 'Textures'); os.makedirs(T, exist_ok=True)
N = 256
yy, xx = np.mgrid[0:N, 0:N] / N
def noise(f, seed, n=N):
    r = np.random.default_rng(seed).random((f, f)); return np.asarray(Image.fromarray((r * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)) / 255.0
def img(a, nm, blur=0.5): Image.fromarray(np.clip(a, 0, 255).astype(np.uint8)).filter(ImageFilter.GaussianBlur(blur)).save(os.path.join(T, nm + '.png'))
# asphalt: U across the road, V along it (one slice = 2 units). White edge lines, dashed lane dividers at 1/3 and 2/3.
a = np.ones((N, N, 3)) * 68 * (0.86 + 0.25 * noise(64, 1))[..., None]
a *= (0.95 + 0.1 * rng.random((N, N)))[..., None]
edge = (xx < 0.03) | (xx > 0.97); a[edge] = 225
for c in (1 / 3, 2 / 3):
    m = (np.abs(xx - c) < 0.008) & (yy % 1 < 0.5); a[m] = 215
img(a, 'road')
g = np.ones((N, N, 3)) * np.array([70, 120, 50.]) * (0.75 + 0.4 * noise(32, 2))[..., None]
g *= (0.9 + 0.2 * rng.random((N, N)))[..., None]; img(g, 'grass', 0.8)
# winter verge: packed snow with faint blue shading (no rng draw, so the later assets stay identical)
sn = np.ones((N, N, 3)) * np.array([228, 232, 240.]) * (0.86 + 0.16 * noise(32, 7))[..., None]
sn[..., 2] += 10 * noise(16, 8); img(sn, 'snow', 0.8)
w = np.ones((N, N, 3)) * np.array([40, 95, 140.]) * (0.85 + 0.3 * noise(24, 3))[..., None]
w += (np.clip(noise(48, 4) - 0.78, 0, 1) * 600)[..., None]; img(w, 'water', 1.0)
s = np.ones((N, N, 3)) * np.array([170, 150, 110.]) * (0.8 + 0.3 * noise(32, 6))[..., None]; img(s, 'sand', 0.8)
c = np.ones((64, 64, 3)) * 200; c[:, :] = np.where(((np.arange(64) // 16) % 2 == 0)[:, None, None], [200, 40, 40], [235, 235, 235]); img(c, 'curb', 0.3)
# ------------------------------------------------------------------ audio
def nz(d, k): return rng.standard_normal(int(SR * d)) * np.exp(-tt(d) * k)
def ping(f, d=0.12, k=30): return np.sin(2 * np.pi * f * tt(d)) * np.exp(-tt(d) * k)
def sweep(f0, f1, d): return np.sin(2 * np.pi * np.cumsum(np.linspace(f0, f1, int(SR * d))) / SR)
for i in range(5):   # engine grains: pitch rises with speed
    d = 0.2; f = 55 + i * 22; t = tt(d)
    x = sq(f, d, 0.35) * 0.4 + np.sin(2 * np.pi * f * 2 * t) * 0.3 + nz(d, 0) * 0.08
    save(f'eng{i}.wav', env(x, 0.02, 0.03), 0.09)
save('gun.wav', env(nz(0.07, 50) * 0.8 + sq(160, 0.07, 0.3) * 0.3 * np.exp(-tt(0.07) * 40)), 0.25)
save('missile.wav', env(nz(0.6, 3) * 0.5 + sweep(300, 900, 0.6) * 0.3), 0.3)
save('oil.wav', env(nz(0.35, 8) * 0.4 + sweep(200, 80, 0.35) * 0.4), 0.3)
save('smoke.wav', env(nz(0.6, 4) * 0.6), 0.3)
save('crash.wav', env(nz(0.8, 4) * 0.9 + sweep(180, 40, 0.8) * 0.5, 0.003, 0.15), 0.45)
save('boom.wav', env(nz(0.6, 5) * 0.8 + ping(70, 0.6, 5), 0.003, 0.1), 0.4)
save('hit.wav', env(ping(1200, 0.06, 60) + nz(0.06, 60) * 0.3), 0.2)
save('van.wav', mix(melody([('C5', 0.25), ('E5', 0.25), ('G5', 0.25), ('C6', 0.75)], 400, 'sq', 0.25)), 0.25)
save('dock.wav', env(sweep(120, 60, 0.5) * 0.6 + nz(0.5, 6) * 0.3), 0.3)
save('splash.wav', env(nz(0.7, 4) * 0.7, 0.01, 0.2), 0.3)
save('heli.wav', env(np.concatenate([nz(0.06, 30) * 0.6 for _ in range(8)]) * sq(13, 0.48, 0.5) * 0.5 + 0.5), 0.15)
save('bombfall.wav', env(sweep(1600, 500, 0.6) * 0.4), 0.2)
save('warn.wav', mix(melody([('A5', 0.3), ('E5', 0.3), ('A5', 0.3)], 300, 'sq', 0.4)), 0.22)
save('click.wav', env(sq(1200, 0.04, 0.3) * np.exp(-tt(0.04) * 60)), 0.25)
save('penalty.wav', mix(melody([('E4', 0.5), ('C4', 1)], 200, 'sq', 0.5)), 0.25)
save('steer.wav', env(nz(0.1, 25) * 0.35 + sweep(500, 300, 0.1) * 0.2), 0.12)
save('extra.wav', mix(melody([('E5', 0.25), ('G5', 0.25), ('E6', 0.25), ('C6', 0.25), ('D6', 0.25), ('G6', 0.75)], 400, 'sq', 0.25)), 0.25)
save('gameover.wav', mix(melody([('G4', 1), ('F#4', 1), ('F4', 1), ('E4', 3)], 170, 'sq', 0.5)), 0.3)
save('start.wav', mix(melody([('E4', 0.5), ('E4', 0.5), ('G4', 0.5), ('E4', 0.5), ('A4', 0.5), ('E4', 0.5), ('B4', 1), ('E5', 2)], 260, 'sq', 0.4)), 0.3)
def loop(bass, lead, bpm, nm, vol=0.2):
    save(nm, mix(melody(bass, bpm, 'tri'), melody(lead, bpm, 'sq', 0.3) * 0.35), vol)
# an original driving spy theme (walking bass), not the arcade's licensed tune
bass = ([('E2', 0.5), ('E2', 0.5), ('G2', 0.5), ('E2', 0.5), ('A2', 0.5), ('E2', 0.5), ('B2', 0.5), ('A2', 0.5)] * 2 +
        [('A2', 0.5), ('A2', 0.5), ('C3', 0.5), ('A2', 0.5), ('D3', 0.5), ('A2', 0.5), ('E3', 0.5), ('D3', 0.5)] + [('E2', 0.5), ('E2', 0.5), ('G2', 0.5), ('E2', 0.5), ('A2', 0.5), ('E2', 0.5), ('B2', 0.5), ('A2', 0.5)])
loop(bass, [('E5', 1.5), ('D5', 0.5), ('E5', 2), ('G5', 1), ('F#5', 1), ('E5', 2), ('A5', 1.5), ('G5', 0.5), ('E5', 2), ('B4', 1), ('D5', 1), ('E5', 2)], 150, 'drive.wav')
loop([('C3', 1), ('A2', 1), ('F2', 1), ('G2', 1)] * 2, [('E5', 1), ('G5', 1), ('C6', 2), ('B5', 1), ('G5', 1), ('E5', 2)], 120, 'title.wav')
print('assets ok')
