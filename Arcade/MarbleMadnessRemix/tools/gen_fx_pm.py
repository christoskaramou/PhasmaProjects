# Particle textures for this game (game-local copy). usage: python3 gen_fx_pm.py <project Assets dir>
# 1) Runs the shared generator (common/tools/gen_fx_textures.py, used read-only) into a temp dir, then writes
#    PREMULTIPLIED copies to <Assets>/Textures/fx/ (same names, so Scripts/Lib/particles.lua loads them unchanged).
#    Why: the engine's particle pass screen-blends (ONE, ONE_MINUS_SRC_COLOR) and multiplies colour by texture RGB;
#    alpha only kills/discards. A white texture with an alpha falloff therefore draws as a hard-edged disc.
# 2) Adds two textures particles.lua has no equivalent for: fx_dust.png (grainy ground dust), fx_foam.png (water foam).
import numpy as np, os, sys, subprocess, tempfile, glob
from PIL import Image
assets = sys.argv[1] if len(sys.argv) > 1 else '.'
here = os.path.dirname(os.path.abspath(__file__))
gen = None
for c in (os.path.join(here, 'gen_fx_textures.py'), '/workspace/games/common/tools/gen_fx_textures.py'):
    if os.path.exists(c): gen = c; break
tmp = tempfile.mkdtemp()
subprocess.check_call([sys.executable, gen, tmp], stdout=subprocess.DEVNULL)
out = os.path.join(assets, 'Textures', 'fx'); os.makedirs(out, exist_ok=True)
for f in glob.glob(os.path.join(tmp, 'Textures', 'fx', '*.png')):
    a = np.asarray(Image.open(f).convert('RGBA')).astype(np.float32) / 255
    a[..., :3] *= a[..., 3:4]
    Image.fromarray((a * 255 + 0.5).astype(np.uint8), 'RGBA').save(os.path.join(out, os.path.basename(f)))
def noise(n, f, seed):
    r = np.random.default_rng(seed).random((f, f))
    return np.asarray(Image.fromarray((r * 255).astype(np.uint8)).resize((n, n), Image.BICUBIC)) / 255.0
def fbm(n, seed, oct=5):
    a = np.zeros((n, n)); amp = 1; tot = 0
    for o in range(oct): a += amp * noise(n, 3 * 2 ** o, seed + o); tot += amp; amp *= 0.55
    return a / tot
def save(shape, nm):
    shape = np.clip(shape, 0, 1)
    im = np.stack([shape, shape, shape, np.where(shape > 0.004, 1.0, 0.0)], -1)
    Image.fromarray((im * 255).astype(np.uint8), 'RGBA').save(os.path.join(out, nm + '.png'))
N = 128
y, x = np.mgrid[0:N, 0:N] / (N - 1) * 2 - 1; r = np.sqrt(x * x + y * y)
n = fbm(N, 77); d = r + (n - 0.5) * 0.9
save(np.clip((0.75 - d) / 0.5, 0, 1) * (0.5 + 0.5 * noise(N, 48, 5)) * 0.9, 'dust')
n = fbm(N, 91); d = r + (n - 0.5) * 0.5
save(np.clip((0.9 - d) / 0.4, 0, 1) * (0.35 + 0.9 * np.clip((noise(N, 44, 3) - 0.5) * 3, 0, 1) * fbm(N, 13)), 'foam')
print('premultiplied fx textures ->', out)
