# world meshes: rock platforms (+ glow edges), lava, egg, troll hand, backdrop, fx
exec(open(__file__.replace('gen_world.py', 'gen_meshes.py')).read().split('# ---------------- mounts')[0])
from layout import PLATS, LAVA_Y
rng = np.random.default_rng(7)
def rock_platform(w, thick, seed, base=False):
    r = np.random.default_rng(seed); o = M()
    D = 3.6
    # top slab with chamfer: polygon in XY side profile extruded along Z
    nx = max(8, int(w * 2))
    xs = np.linspace(-w / 2, w / 2, nx + 1)
    bot = -thick * (0.55 + 0.45 * np.sin(np.linspace(0, PI, nx + 1)) ** 0.6) + r.normal(0, 0.12, nx + 1)
    if base: bot = np.minimum(bot, -thick)
    zs = np.linspace(-D / 2, D / 2, 7)
    # grid: rows over z, columns over x; each vertex y from top (0) at z edges chamfered
    def surf(top):
        V, N, UV, F = [], [], [], []
        for j, z in enumerate(zs):
            for i, x in enumerate(xs):
                if top:
                    e = 1 - (abs(z) / (D / 2)) ** 6
                    y = -0.18 * (1 - e) + r.normal(0, 0.02)
                else:
                    e = np.cos(z / (D / 2) * PI / 2) ** 0.5
                    y = -0.3 + (bot[i] + 0.3) * e + r.normal(0, 0.06)
                V.append(np.array([x, y, z])); N.append(np.array([0, 1.0 if top else -1.0, 0])); UV.append((x / 4, z / 4))
        G = np.array(V).reshape(len(zs), nx + 1, 3)
        dx = np.gradient(G, axis=1); dz = np.gradient(G, axis=0); NN = np.cross(dz, dx); NN /= np.linalg.norm(NN, axis=2, keepdims=True) + 1e-12
        if top: NN[NN[..., 1] < 0] *= -1
        else: NN[NN[..., 1] > 0] *= -1
        for j in range(len(zs) - 1):
            for i in range(nx):
                a = j * (nx + 1) + i; b = a + 1; c = a + nx + 1; d = c + 1; F += [(a, b, d), (a, d, c)]
        o.add(list(G.reshape(-1, 3)), list(NN.reshape(-1, 3)), UV, F); return G
    T = surf(True); B = surf(False)
    # front/back skirts + end caps joining top edge rows to bottom edge rows
    for j, s in ((0, -1), (len(zs) - 1, 1)):
        for i in range(nx):
            q = [T[j, i], T[j, i + 1], B[j, i + 1], B[j, i]]
            o.add(q, [np.array([0, 0, s])] * 4, [(0, 0), (1, 0), (1, 1), (0, 1)], [(0, 1, 2), (0, 2, 3)])
    for i, s in ((0, -1), (nx, 1)):
        for j in range(len(zs) - 1):
            q = [T[j, i], T[j + 1, i], B[j + 1, i], B[j, i]]
            o.add(q, [np.array([s, 0, 0])] * 4, [(0, 0), (1, 0), (1, 1), (0, 1)], [(0, 1, 2), (0, 2, 3)])
    # stalactites
    for k in range(max(2, int(w / 2.5))):
        x = r.uniform(-w / 2 + 0.8, w / 2 - 0.8); i = int((x + w / 2) / w * nx)
        o += xform(tube((0, 0, 0), r.uniform(0.35, 0.7), 0.02, r.uniform(0.8, 2.2), n=7), (x, bot[i] + 0.3, r.uniform(-0.8, 0.8)), rotm(rx=PI) @ rotm(ry=r.uniform(0, 3)))
    # boulders on top rim
    rim = M()
    for k in range(int(w / 3)):
        rim += ellipsoid((r.uniform(-w / 2 + 0.5, w / 2 - 0.5), -0.15, -D / 2 + r.uniform(0.0, 0.3)), (r.uniform(0.25, 0.5), r.uniform(0.15, 0.3), 0.3), 10, 6)
    glow = U(*[xform(tube((0, 0, 0), 0.06, 0.06, w - 0.4, n=8, caps=True), (-w / 2 + 0.2, 0.0, zz), rotm(rz=-PI / 2)) for zz in (D / 2 - 0.05, -D / 2 + 0.05)])
    return o, rim, glow
for i, (x0, x1, y) in enumerate(PLATS):
    w = x1 - x0
    body, rim, glow = rock_platform(w, 2.6 if i == 0 else 1.4, 10 + i, base=i == 0)
    if i == 0: body += box((0, -4.0, 0), (w * 0.85, 3.5, 3.0))
    save(f'plat{i}', U(body, rim)); save(f'platglow{i}', glow)
# lava surface: wide wavy grid
def lava():
    nx, nz = 160, 40; W, D = 150.0, 80.0; V, N, UV, F = [], [], [], []
    for j in range(nz + 1):
        for i in range(nx + 1):
            x = -W / 2 + W * i / nx; z = -65 + D * j / nz
            y = 0.18 * np.sin(x * 0.7 + z * 0.4) + 0.12 * np.sin(x * 1.9 - z * 1.1) + rng.normal(0, 0.03)
            V.append(np.array([x, y, z])); UV.append((i / nx * 6, j / nz * 2))
    G = np.array(V).reshape(nz + 1, nx + 1, 3); dx = np.gradient(G, axis=1); dz = np.gradient(G, axis=0)
    NN = np.cross(dz, dx); NN /= np.linalg.norm(NN, axis=2, keepdims=True); NN[NN[..., 1] < 0] *= -1
    for j in range(nz):
        for i in range(nx):
            a = j * (nx + 1) + i; b = a + 1; c = a + nx + 1; d = c + 1; F += [(a, b, d), (a, d, c)]
    m = M(); m.add(list(G.reshape(-1, 3)), list(NN.reshape(-1, 3)), UV, F); return m
save('lava', lava())
# crust plates floating on the lava
crust = M()
for k in range(40):
    crust += xform(slab([(np.cos(a) * rng.uniform(0.5, 1.4), np.sin(a) * rng.uniform(0.4, 1.0)) for a in np.linspace(0, 2 * PI, 7, endpoint=False)], -0.08, 0.1, 0.3),
                   (rng.uniform(-38, 38), 0.12, rng.uniform(-9, 6)), rotm(rx=-PI / 2))
save('crust', crust)
save('egg', ellipsoid((0, 0.45, 0), (0.36, 0.48, 0.36), 22, 14))
save('eggband', U(*[xform(torus(0.36 * np.sin(t), 0.025, 28, 6), (0, 0.45 - 0.48 * np.cos(t), 0), rotm(rx=PI / 2)) for t in (1.2, 1.9)]))
# troll hand (rises out of lava, palm up, fingers curled)
hand = U(seg((0, -4, 0), (0, 0, 0), 0.55, 0.45, 14), ellipsoid((0, 0.35, 0), (0.6, 0.45, 0.45), 16, 10))
for k, a in enumerate((-0.7, -0.25, 0.2, 0.65)):
    b = (np.sin(a) * 0.45, 0.6, np.cos(a) * 0.1); c = (np.sin(a) * 0.6, 1.35, 0.15); d = (np.sin(a) * 0.5, 1.75, 0.45)
    hand += U(seg(b, c, 0.14, 0.12, 8), ball(c, 0.12, 8, 6), seg(c, d, 0.12, 0.06, 8))
hand += U(seg((0.5, 0.3, 0), (0.85, 0.9, 0.2), 0.15, 0.1, 8))
save('hand', hand)
save('handglow', U(*[ellipsoid((rng.uniform(-0.5, 0.5), y, rng.uniform(-0.4, 0.4)), (0.12, 0.25, 0.08), 8, 6) for y in np.linspace(-3.5, 0.2, 9)]))
# backdrop: cavern ridges (far), rock pillars
def ridge(L, n, amp, base, seed, depth=10.0):
    r = np.random.default_rng(seed); xs = np.linspace(-L / 2, L / 2, n + 1)
    h = sum(amp / k * r.uniform(0.4, 1) * (0.5 + 0.5 * np.sin(2 * PI * k * xs / L + r.uniform(0, 6))) for k in range(1, 9)); h = h / h.max() * amp
    zs = np.linspace(-depth / 2, depth / 2, 7); V, N, UV, F = [], [], [], []
    for j, z in enumerate(zs):
        pr = np.cos(z / (depth / 2) * PI / 2) ** 0.7
        for i, x in enumerate(xs): V.append(np.array([x, base + h[i] * pr + r.normal(0, 0.15) * pr, z])); UV.append((i / n * 8, j / 6))
    G = np.array(V).reshape(7, n + 1, 3); dx = np.gradient(G, axis=1); dz = np.gradient(G, axis=0)
    NN = np.cross(dz, dx); NN /= np.linalg.norm(NN, axis=2, keepdims=True); NN[NN[..., 2] < 0] *= -1
    for j in range(6):
        for i in range(n):
            a = j * (n + 1) + i; b = a + 1; c = a + n + 1; d = c + 1; F += [(a, b, d), (a, d, c)]
    m = M(); m.add(list(G.reshape(-1, 3)), list(NN.reshape(-1, 3)), UV, F); return m
save('ridge_far', ridge(260, 260, 34, 0, 3))
save('ridge_near', ridge(150, 200, 16, 0, 9, 6))
pil = M()
for k in range(9):
    x = -60 + k * 15 + rng.uniform(-4, 4); r0 = rng.uniform(1.8, 3.2)
    pil += tube((x, -20, 0), r0, r0 * 0.55, rng.uniform(22, 45), n=9)
    pil += xform(tube((0, 0, 0), r0 * 0.9, 0.05, rng.uniform(6, 14), n=8), (x + rng.uniform(-2, 2), 30, 0), rotm(rx=PI))
save('pillars', pil)
save('spark', ellipsoid((0, 0, 0), (0.5, 0.5, 0.5), 8, 5))
save('ring', torus(1.0, 0.045, 64, 8))
save('shard', slab([(0, 0.5), (-0.4, -0.3), (0.45, -0.25)], -0.08, 0.08, 0.2))
save('feather', ellipsoid((0, 0, 0), (0.06, 0.03, 0.4), 8, 6))
save('beam', tube((0, 0, 0), 0.9, 0.9, 1.0, n=28, caps=False))
save('pad', U(torus(1.4, 0.08, 48, 8, Rm=rotm(rx=PI / 2))))
