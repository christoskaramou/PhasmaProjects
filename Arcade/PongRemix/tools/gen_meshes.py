# Procedural meshes for Pong Remix -> OBJ (cooked by PhasmaCook). Drop zero-area tris.
import numpy as np, os
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'meshsrc')
os.makedirs(OUT, exist_ok=True)

def rounded_box(hx, hy, hz, r, n=8):
    inner = np.array([max(hx - r, 0), max(hy - r, 0), max(hz - r, 0)])
    V, N, UV, F = [], [], [], []
    k = n
    edge = np.sin(np.linspace(0, np.pi / 2, k))
    def samples(h, rr):
        if h - rr < 1e-6:
            a = -np.cos(np.linspace(0, np.pi, 2 * k - 1))
            return a * h
        left = -(h - rr) - rr * edge[::-1]
        mid = np.linspace(-(h - rr), (h - rr), max(4, n // 2))[1:-1]
        right = (h - rr) + rr * edge
        return np.concatenate([left, mid, right])
    H = np.array([hx, hy, hz])
    for axis in range(3):
        for s in (-1, 1):
            u_ax, v_ax = [a for a in range(3) if a != axis]
            if s < 0: u_ax, v_ax = v_ax, u_ax
            us, vs = samples(H[u_ax], r), samples(H[v_ax], r)
            base = len(V)
            for j, vv in enumerate(vs):
                for i, uu in enumerate(us):
                    p = np.zeros(3); p[axis] = s * H[axis]; p[u_ax] = uu; p[v_ax] = vv
                    c = np.clip(p, -inner, inner)
                    d = p - c; ln = np.linalg.norm(d)
                    nrm = d / ln if ln > 1e-9 else np.eye(3)[axis] * s
                    V.append(c + nrm * r); N.append(nrm)
                    UV.append(((uu / max(H[u_ax], 1e-6) + 1) * 0.5, (vv / max(H[v_ax], 1e-6) + 1) * 0.5))
            W = len(us)
            for j in range(len(vs) - 1):
                for i in range(W - 1):
                    a = base + j * W + i; b = a + 1; c2 = a + W; d2 = c2 + 1
                    F += [(a, b, d2), (a, d2, c2)]
    return np.array(V, float), np.array(N, float), UV, F

def uv_sphere(r=0.5, stacks=16, slices=24):
    V, N, UV, F = [], [], [], []
    for i in range(stacks + 1):
        v = i / stacks
        phi = v * np.pi
        sp, cp = np.sin(phi), np.cos(phi)
        for j in range(slices + 1):
            u = j / slices
            th = u * 2 * np.pi
            x, y, z = sp * np.cos(th), cp, sp * np.sin(th)
            V.append((x * r, y * r, z * r)); N.append((x, y, z)); UV.append((u, 1 - v))
    W = slices + 1
    for i in range(stacks):
        for j in range(slices):
            a = i * W + j; b = a + 1; c = a + W; d = c + 1
            if i > 0: F.append((a, c, b))
            if i < stacks - 1: F.append((b, c, d))
    return np.array(V, float), np.array(N, float), UV, F

def torus(R=0.5, r=0.08, segs=32, tubes=16):
    V, N, UV, F = [], [], [], []
    for i in range(segs + 1):
        u = i / segs; th = u * 2 * np.pi
        cx, cz = np.cos(th) * R, np.sin(th) * R
        for j in range(tubes + 1):
            v = j / tubes; ph = v * 2 * np.pi
            nx = np.cos(th) * np.cos(ph); ny = np.sin(ph); nz = np.sin(th) * np.cos(ph)
            V.append((cx + nx * r, ny * r, cz + nz * r)); N.append((nx, ny, nz)); UV.append((u, v))
    W = tubes + 1
    for i in range(segs):
        for j in range(tubes):
            a = i * W + j; b = a + 1; c = a + W; d = c + 1
            F += [(a, c, b), (b, c, d)]
    return np.array(V, float), np.array(N, float), UV, F

def save(name, V, N, UV, F):
    kept = []
    for a, b, c in F:
        fn = np.cross(V[b] - V[a], V[c] - V[a])
        if np.linalg.norm(fn) < 1e-9: continue  # drop zero-area (else mesh 0 invisible after cook)
        if np.dot(fn, N[a] + N[b] + N[c]) < 0: b, c = c, b
        kept.append((a, b, c))
    path = os.path.join(OUT, name + '.obj')
    with open(path, 'w') as fo:
        fo.write(f'o {name}\n')
        for p in V: fo.write('v %.5f %.5f %.5f\n' % tuple(p))
        for t in UV: fo.write('vt %.5f %.5f\n' % tuple(t))
        for n in N: fo.write('vn %.5f %.5f %.5f\n' % tuple(n))
        for a, b, c in kept:
            fo.write(f'f {a+1}/{a+1}/{a+1} {b+1}/{b+1}/{b+1} {c+1}/{c+1}/{c+1}\n')
    print(name, len(V), 'verts', len(kept), 'tris')

# Paddle: tall thin rounded bar (unit; scaled in-game). Body + glowing face + edge rails.
save('paddle_body', *rounded_box(0.18, 0.90, 0.28, 0.12, 7))
save('paddle_face', *rounded_box(0.06, 0.78, 0.04, 0.03, 4))
save('paddle_edge', *rounded_box(0.05, 0.92, 0.06, 0.04, 4))
# Ball + emissive core
save('ball', *uv_sphere(0.5, 18, 28))
save('ball_core', *uv_sphere(0.28, 12, 20))
# Arena rails / posts
save('rail', *rounded_box(0.5, 0.5, 0.5, 0.14, 5))
save('rail_glow', *rounded_box(0.5, 0.5, 0.5, 0.08, 4))
# Center net diamonds / markers
save('marker', *rounded_box(0.12, 0.12, 0.08, 0.04, 4))
# Impact ring + shards
save('ring', *torus(0.55, 0.05, 36, 12))
save('shard', *rounded_box(0.12, 0.04, 0.06, 0.015, 3))
# Floor tile (large plate)
save('floor', *rounded_box(0.5, 0.5, 0.04, 0.01, 3))
# Score pip (small orb for lives/score ornaments)
save('pip', *uv_sphere(0.35, 10, 16))
print('meshes ok')
