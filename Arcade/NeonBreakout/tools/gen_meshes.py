# Procedural meshes for Neon Breakout -> OBJ (cooked to .pemesh by PhasmaCook via cook_all.sh)
import numpy as np, os
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'meshsrc')
os.makedirs(OUT, exist_ok=True)

def rounded_box(hx, hy, hz, r, n=10):
    """Rounded (bevelled) box centred at origin: half extents hx,hy,hz, edge radius r.
    Built from a subdivided cube whose vertices are pushed onto the rounded surface,
    giving exact geometry with smooth analytic normals."""
    inner = np.array([hx - r, hy - r, hz - r])
    V, N, UV, F = [], [], [], []
    # each face: (axis, sign); grid with extra rows clustered near edges for smooth bevels
    t = np.concatenate([-1 + (1 - np.cos(np.linspace(0, np.pi/2, n))) * 0, []])
    # parameter samples: dense near borders
    k = n
    edge = np.sin(np.linspace(0, np.pi / 2, k))            # 0..1 in the bevel
    def samples(h, rr):
        # positions along one axis on a face of half-size h: bevel band [-h,-h+rr], flat, bevel band
        if h - rr < 1e-6:
            a = -np.cos(np.linspace(0, np.pi, 2 * k - 1))
            return a * h
        left = -(h - rr) - rr * edge[::-1]
        mid = np.linspace(-(h - rr), (h - rr), 4)[1:-1]
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
                    UV.append(((uu / H[u_ax] + 1) * 0.5, (vv / H[v_ax] + 1) * 0.5))
            W = len(us)
            for j in range(len(vs) - 1):
                for i in range(W - 1):
                    a = base + j * W + i; b = a + 1; c2 = a + W; d2 = c2 + 1
                    F += [(a, b, d2), (a, d2, c2)]
    return np.array(V), np.array(N), UV, F

def save(name, V, N, UV, F):
    # make winding agree with normals (CCW seen from outside)
    with open(os.path.join(OUT, name + '.obj'), 'w') as fo:
        fo.write(f'o {name}\n')
        for p in V: fo.write('v %.5f %.5f %.5f\n' % tuple(p))
        for t in UV: fo.write('vt %.5f %.5f\n' % tuple(t))
        for n in N: fo.write('vn %.5f %.5f %.5f\n' % tuple(n))
        for a, b, c in F:
            fn = np.cross(V[b] - V[a], V[c] - V[a])
            if np.dot(fn, N[a] + N[b] + N[c]) < 0: b, c = c, b
            fo.write(f'f {a+1}/{a+1}/{a+1} {b+1}/{b+1}/{b+1} {c+1}/{c+1}/{c+1}\n')
    print(name, len(V), 'verts', len(F), 'tris')

# brick: 1.0 x 0.42 x 0.5 (scaled in-game per layout), crisp 0.06 bevel
save('brick', *rounded_box(0.5, 0.21, 0.25, 0.07, 4))
# brick face plate: thin glowing inset panel on the brick front
save('brick_face', *rounded_box(0.40, 0.12, 0.03, 0.025, 3))
# paddle centre bar (stretched along X) and rounded end caps
save('paddle_mid', *rounded_box(0.5, 0.2, 0.3, 0.17, 6))
save('paddle_cap', *rounded_box(0.22, 0.2, 0.3, 0.19, 7))
# frame rail (unit cube with soft bevel, scaled into walls)
save('rail', *rounded_box(0.5, 0.5, 0.5, 0.18, 5))
# ball: rounded box with r = half size = sphere
save('ball', *rounded_box(0.5, 0.5, 0.5, 0.5, 6))
