# Textures, night skybox and chip-style SFX/music for Donkey Kong Remix
import numpy as np, wave, os
from PIL import Image
R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets')
T = os.path.join(R, 'Textures'); A = os.path.join(R, 'Audio'); SK = os.path.join(R, 'Skybox')
for d in (T, A, SK): os.makedirs(d, exist_ok=True)
rng = np.random.default_rng(81)

# ---- building facade with lit windows (warm, varied; not neon)
W, H = 256, 512
img = np.zeros((H, W, 3)); img[:] = (22, 24, 30)
img += rng.normal(0, 3, img.shape)
for y in range(8, H - 8, 20):
    for x in range(8, W - 8, 16):
        if rng.random() < 0.42:
            c = np.array([255, 196, 120]) * rng.uniform(0.35, 0.95)
            if rng.random() < 0.15: c = np.array([180, 200, 230]) * rng.uniform(0.3, 0.7)
            img[y:y + 11, x:x + 8] = c
        else:
            img[y:y + 11, x:x + 8] = (14, 15, 20)
Image.fromarray(np.clip(img, 0, 255).astype(np.uint8)).save(os.path.join(T, 'windows.png'))
# ---- painted steel with wear (girders)
n = 256; g = np.zeros((n, n))
for o in range(5):
    f = 4 * 2 ** o; s = rng.random((f, f))
    g += np.asarray(Image.fromarray((s * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)) / 255 / 2 ** o
g = g / g.max()
st = np.stack([200 + 55 * g, 200 + 55 * g, 200 + 55 * g], -1)
st[g > 0.82] *= 0.55     # chipped paint
Image.fromarray(np.clip(st, 0, 255).astype(np.uint8)).save(os.path.join(T, 'paint.png'))

# ---- night skybox: deep blue sky, warm city glow at the horizon
HW, HH = 512, 256
v = (np.arange(HH) + 0.5) / HH; u = (np.arange(HW) + 0.5) / HW
EL, AZ = np.meshgrid((0.5 - v) * np.pi, (u - 0.5) * 2 * np.pi, indexing='ij')
y = np.sin(EL); t = np.clip(y, 0, 1)[..., None]
sky = np.array([0.05, 0.05, 0.09]) * (1 - t) ** 2 + np.array([0.01, 0.012, 0.03]) * t
sky += np.exp(-np.abs(y - 0.02) / 0.06)[..., None] * np.array([0.35, 0.2, 0.1])
sky[y < 0] *= 0.25
for _ in range(500):
    i, j = rng.integers(0, HH // 2), rng.integers(0, HW); sky[i, j] += rng.uniform(0.2, 1.2)
def rgbe(a):
    m = a.max(-1); e = np.ceil(np.log2(np.maximum(m, 1e-32))); sc = np.where(m > 1e-32, 256.0 / 2 ** e, 0)
    o = np.zeros(a.shape[:2] + (4,), np.uint8); o[..., :3] = np.clip(a * sc[..., None], 0, 255).astype(np.uint8)
    o[..., 3] = np.where(m > 1e-32, e + 128, 0).astype(np.uint8); return o
with open(os.path.join(SK, 'citynight.hdr'), 'wb') as f:
    f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n" % (HH, HW)); f.write(rgbe(sky.astype(np.float32)).tobytes())

# ---- audio: square/triangle chip voices (arcade-style), all mono 44.1 kHz
SR = 44100
def tt(d): return np.arange(int(SR * d)) / SR
def sq(f, d, duty=0.5): t = tt(d); return np.where((t * f) % 1 < duty, 1.0, -1.0)
def tri(f, d): t = tt(d); return 2 * np.abs(2 * ((t * f) % 1) - 1) - 1
def env(x, a=0.004, r=0.03):
    n = len(x); e = np.ones(n); na, nr = int(a * SR), int(r * SR)
    if na: e[:na] = np.linspace(0, 1, na)
    if nr and nr < n: e[-nr:] *= np.linspace(1, 0, nr)
    return x * e
def save(nm, x, vol=0.5):
    x = np.clip(x / (np.max(np.abs(x)) + 1e-9) * vol, -1, 1)
    w = wave.open(os.path.join(A, nm), 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR)
    w.writeframes((x * 32767).astype(np.int16).tobytes()); w.close()
NOTE = {n: 440 * 2 ** ((i - 9) / 12) for i, n in enumerate(['C', 'C#', 'D', 'D#', 'E', 'F', 'F#', 'G', 'G#', 'A', 'A#', 'B'])}
def hz(s):   # 'C4', 'F#3'
    nm, o = s[:-1], int(s[-1]); return NOTE[nm] * 2 ** (o - 4)
def melody(seq, bpm, voice='sq', duty=0.5, gap=0.02):
    out = []
    for n, b in seq:
        d = 60 / bpm * b
        if n == '-': out.append(np.zeros(int(SR * d))); continue
        f = hz(n); body = sq(f, d - gap, duty) if voice == 'sq' else tri(f, d - gap)
        out.append(np.concatenate([env(body, 0.003, 0.02) * np.exp(-tt(d - gap) * 2.5), np.zeros(int(SR * gap))]))
    return np.concatenate(out)
def mix(*xs):
    n = max(len(x) for x in xs); o = np.zeros(n)
    for x in xs: o[:len(x)] += x
    return o

# movement + actions are separate sounds (as in the arcade)
save('walk.wav', env(sq(1350, 0.035, 0.25) * np.exp(-tt(0.035) * 40), 0.001, 0.005), 0.22)
f = 300 + 900 * tt(0.22); save('jump.wav', env(np.where((np.cumsum(f) / SR) % 1 < 0.5, 1.0, -1.0) * np.exp(-tt(0.22) * 6)), 0.32)
save('land.wav', env(tri(110, 0.06) * np.exp(-tt(0.06) * 50)), 0.25)
save('bonus.wav', mix(melody([('E6', 0.25), ('G6', 0.25), ('C7', 0.5)], 480, 'sq', 0.25)), 0.32)
save('item.wav', melody([('C6', 0.25), ('E6', 0.25), ('G6', 0.25), ('C7', 0.5)], 400, 'sq', 0.25), 0.32)
save('rivet.wav', env(sq(880, 0.08, 0.3) * np.exp(-tt(0.08) * 20)) + env(sq(660, 0.08, 0.3)) * 0.0, 0.3)
n = rng.standard_normal(int(SR * 0.3)); save('smash.wav', n * np.exp(-tt(0.3) * 12) + sq(140, 0.3) * np.exp(-tt(0.3) * 14), 0.5)
save('stomp.wav', tri(55, 0.4) * np.exp(-tt(0.4) * 7) + rng.standard_normal(int(SR * 0.4)) * np.exp(-tt(0.4) * 18) * 0.5, 0.65)
save('beat.wav', tri(80, 0.16) * np.exp(-tt(0.16) * 18), 0.5)                       # DK chest beat
save('throw.wav', env(sq(220, 0.12, 0.5) * np.exp(-tt(0.12) * 14)), 0.3)
f = 900 - 500 * tt(0.25); save('fall.wav', env(np.where((np.cumsum(f) / SR) % 1 < 0.5, 1.0, -1.0) * np.exp(-tt(0.25) * 3)), 0.25)
f = 200 + 600 * np.abs(np.sin(tt(0.3) * 20)); save('spring.wav', env(np.where((np.cumsum(f) / SR) % 1 < 0.5, 1.0, -1.0) * np.exp(-tt(0.3) * 5)), 0.25)
n = rng.standard_normal(int(SR * 0.6)); save('ignite.wav', np.convolve(n, np.ones(30) / 30, 'same') * np.exp(-tt(0.6) * 4), 0.5)
save('click.wav', env(sq(1200, 0.04, 0.3) * np.exp(-tt(0.04) * 60)), 0.25)
save('extra.wav', melody([('G5', 0.25), ('C6', 0.25), ('E6', 0.25), ('G6', 0.25), ('C7', 1)], 360, 'sq', 0.25), 0.3)
save('death.wav', mix(melody([('C6', 0.5), ('B5', 0.5), ('A#5', 0.5), ('A5', 0.5), ('G#5', 0.5), ('G5', 0.5), ('F#5', 0.5), ('-', 0.5),
                              ('C4', 0.5), ('-', 0.5), ('C4', 0.5), ('-', 0.25), ('C3', 1.5)], 300, 'sq', 0.5)), 0.32)
save('clear.wav', mix(melody([('C5', 0.5), ('E5', 0.5), ('G5', 0.5), ('C6', 1), ('A5', 0.5), ('B5', 0.5), ('C6', 2)], 260, 'sq', 0.25),
                      melody([('C3', 1), ('G3', 1), ('A3', 1), ('F3', 1), ('C3', 2)], 260, 'tri')), 0.32)
save('howhigh.wav', mix(melody([('G4', 0.5), ('C5', 0.5), ('E5', 0.5), ('G5', 1), ('E5', 0.5), ('G5', 1.5), ('-', 0.5),
                                ('A4', 0.5), ('D5', 0.5), ('F5', 0.5), ('A5', 1), ('F5', 0.5), ('A5', 1.5)], 300, 'sq', 0.25),
                        melody([('C3', 2), ('G2', 2), ('D3', 2), ('A2', 2)], 300, 'tri')), 0.3)
save('intro.wav', mix(melody([('C4', 0.5), ('C4', 0.5), ('E4', 0.5), ('C4', 0.5), ('G4', 0.5), ('E4', 0.5), ('C5', 1)] * 2 +
                              [('D5', 0.5), ('C5', 0.5), ('A4', 0.5), ('G4', 0.5), ('E4', 0.5), ('D4', 0.5), ('C4', 2)], 220, 'sq', 0.5),
                      melody([('C2', 1), ('G2', 1), ('C2', 1), ('G2', 1)] * 4, 220, 'tri')), 0.3)
# looping stage music (bass-driven like the arcade boards)
def loop(bass, lead, bpm, nm, vol=0.26):
    b = melody(bass, bpm, 'tri'); l = melody(lead, bpm, 'sq', 0.25) if lead else np.zeros(1)
    save(nm, mix(b, l * 0.45), vol)
save('bgm25.wav', melody([('C3', 0.5), ('-', 0.5), ('C3', 0.5), ('D#3', 0.5), ('-', 0.5), ('C3', 0.5), ('G3', 0.5), ('F3', 0.5)] * 2, 230, 'tri'), 0.3)
loop([('F2', 0.5), ('-', 0.5), ('A2', 0.5), ('C3', 0.5)] * 4, [('F4', 1), ('A4', 1), ('C5', 1), ('A4', 1), ('G4', 1), ('A#4', 1), ('D5', 1), ('C5', 1)], 240, 'bgm50.wav')
loop([('G2', 0.5), ('D3', 0.5), ('G2', 0.5), ('D3', 0.5)] * 4, [('B4', 0.5), ('D5', 0.5), ('G5', 1), ('-', 1), ('A4', 0.5), ('C5', 0.5), ('F#5', 1), ('-', 1)] * 1, 240, 'bgm75.wav')
loop([('A2', 0.5), ('A2', 0.5), ('E3', 0.5), ('A2', 0.5), ('G2', 0.5), ('G2', 0.5), ('D3', 0.5), ('G2', 0.5)] * 2, None, 250, 'bgm100.wav')
save('hammer.wav', mix(melody([('C5', 0.25), ('E5', 0.25), ('G5', 0.25), ('E5', 0.25), ('F5', 0.25), ('A5', 0.25), ('C6', 0.25), ('A5', 0.25)] * 2, 300, 'sq', 0.25),
                       melody([('C3', 0.5), ('C3', 0.5), ('F3', 0.5), ('F3', 0.5)] * 2, 300, 'tri')), 0.3)
save('timeout.wav', env(sq(660, 0.1, 0.5)) , 0.25)
print('assets ok')
