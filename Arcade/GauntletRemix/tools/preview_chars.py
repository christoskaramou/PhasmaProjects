# quick software preview of the rigged characters (flat-shaded, painter's sort) -> /tmp/chars_prev.png
# usage: python3 preview_chars.py [kind ...]
import sys, os
sel = sys.argv[1:]
__file__ = os.path.abspath('gen_chars.py'); sys.argv = ['x', '--nosave']
exec(open('gen_chars.py').read())
from PIL import Image, ImageDraw
sel = sel or list(CH)
S = 260
def view(dr, ox, oy, ch, yaw, pitch):
    Ry = rotm(ry=yaw); Rx = rotm(rx=pitch); tris = []
    L = np.array([0.4, 0.8, 0.5]); L /= np.linalg.norm(L)
    for (seg, mat), m in ch.parts.items():
        V = (np.array(m.V) - np.array([0, 0.45, 0])) @ Ry.T @ Rx.T; base = np.array(MATS[mat][0]); em = np.array(MATS[mat][1])
        for a, b, c2 in m.F:
            p = V[[a, b, c2]]; n = np.cross(p[1] - p[0], p[2] - p[0]); ln = np.linalg.norm(n)
            if ln < 1e-12: continue
            n /= ln
            nv = np.array(m.N[a]) + np.array(m.N[b]) + np.array(m.N[c2]); nv = nv @ Ry.T @ Rx.T
            if np.dot(n, nv) < 0: n = -n
            if n[2] < 0: continue
            sh = 0.3 + 0.7 * max(0, np.dot(n, L))
            col = tuple(int(255 * min(1, x)) for x in base * sh + em * 0.4)
            tris.append((p[:, 2].mean(), [(ox + S / 2 + q[0] * S * 0.95, oy + S / 2 - q[1] * S * 0.95) for q in p], col))
    tris.sort(key=lambda t: t[0])
    for _, pts, col in tris: dr.polygon(pts, fill=col)
img = Image.new('RGB', (S * 3, S * len(sel)), (50, 50, 56)); dr = ImageDraw.Draw(img)
for r, nm in enumerate(sel):
    for k, (yaw, pitch) in enumerate(((0.0, 0.0), (PI * 0.3, 0.0), (0.0, 0.95))):
        view(dr, k * S, r * S, CH[nm], yaw, pitch)
img.save('/tmp/chars_prev.png'); print('saved', sel)
