# Procedural sound generator for PacManRemix (numpy -> 16-bit mono 22050 Hz WAV, like the other sounds).
#   move.wav   : the ORIGINAL dot sound (old waka.wav), softened -> played as a tick loop while Pac-Man moves
#   waka1.wav  : "wa"  - descending chiptune sweep  } alternated on every dot eaten,
#   waka2.wav  : "ka"  - ascending chiptune sweep   } like the arcade's wa-ka wa-ka
# usage: python3 tools/gen_audio.py  (run from the game folder; needs the original sound in tools/orig_waka.wav)
import numpy as np, wave, os
R = 22050
A = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets', 'Audio')
def save(name, x, vol):
    x = np.clip(x / (np.max(np.abs(x)) + 1e-9) * vol, -1, 1)
    w = wave.open(os.path.join(A, name), 'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(R)
    w.writeframes((x * 32767).astype(np.int16).tobytes()); w.close()
def load(path):
    w = wave.open(path); x = np.frombuffer(w.readframes(w.getnframes()), np.int16).astype(np.float64) / 32767; w.close(); return x
t = lambda d: np.arange(int(R * d)) / R
def tri(ph): return 2 * np.abs(2 * (ph / (2 * np.pi) % 1) - 1) - 1
def sweep(f0, f1, d):
    tt = t(d); f = f0 * (f1 / f0) ** (tt / d)                    # exponential pitch sweep
    ph = 2 * np.pi * np.cumsum(f) / R
    y = 0.75 * tri(ph) + 0.25 * np.sign(np.sin(ph))              # triangle + a little square (namco-ish)
    y = np.round(y * 7) / 7                                      # 4-bit-ish quantisation for chip grit
    env = np.minimum(tt / 0.004, 1) * np.minimum((d - tt) / 0.012, 1)
    return y * env
# 1) old dot sound -> movement tick (softer, short fade so it loops cleanly)
src = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'orig_waka.wav')
m = load(src); n = len(m); fade = np.minimum(np.arange(n) / (R * 0.004), 1) * np.minimum((n - np.arange(n)) / (R * 0.02), 1)
save('move.wav', m * fade, 0.28)
# 2) new waka pair
save('waka1.wav', sweep(780, 260, 0.105), 0.5)
save('waka2.wav', sweep(260, 780, 0.105), 0.5)
print('ok')
