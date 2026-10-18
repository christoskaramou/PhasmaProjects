import numpy as np, wave, os
R = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets')
A = os.path.join(R, 'Audio'); os.makedirs(A, exist_ok=True)
rng = np.random.default_rng(7)
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

