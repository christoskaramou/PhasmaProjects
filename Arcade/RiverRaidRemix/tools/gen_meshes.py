# Procedural meshes for River Raid Remix -> OBJ (cooked to .pemesh by PhasmaCook via cook_all.sh)
import numpy as np, os, math
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

    return np.array(V, float), np.array(N, float), UV, F

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

# ---------------------------------------------------------------- mesh builder
class M:
    def __init__(s): s.V=[]; s.N=[]; s.UV=[]; s.F=[]
    def add(s, V, N, UV, F, t=(0,0,0), R=None, sc=(1,1,1)):
        V=np.asarray(V,float)*np.array(sc); N=np.asarray(N,float)/np.array(sc)
        if R is not None: V=V@np.array(R).T; N=N@np.array(R).T
        N=N/np.maximum(np.linalg.norm(N,axis=1,keepdims=True),1e-9)
        o=len(s.V); s.V+=list(V+np.array(t)); s.N+=list(N); s.UV+=list(UV); s.F+=[(a+o,b+o,c+o) for a,b,c in F]
        return s
    def save(s, name): save(name, np.array(s.V), np.array(s.N), s.UV, s.F)

def rot(axis, ang):
    c, s_ = math.cos(ang), math.sin(ang)
    if axis=='x': return [[1,0,0],[0,c,-s_],[0,s_,c]]
    if axis=='y': return [[c,0,s_],[0,1,0],[-s_,0,c]]
    return [[c,-s_,0],[s_,c,0],[0,0,1]]

def ellipsoid(rx, ry, rz, nu=24, nv=14, fn=None):
    """UV sphere scaled; fn(theta,phi)->radius multiplier for detail."""
    V,N,UV,F=[],[],[],[]
    for i in range(nv+1):
        th=math.pi*i/nv
        for j in range(nu+1):
            ph=2*math.pi*j/nu
            d=np.array([math.sin(th)*math.cos(ph), math.cos(th), math.sin(th)*math.sin(ph)])
            k=fn(th,ph) if fn else 1.0
            V.append(d*np.array([rx,ry,rz])*k); N.append(d/np.array([rx,ry,rz])); UV.append((j/nu,i/nv))
    W=nu+1
    for i in range(nv):
        for j in range(nu):
            a=i*W+j; b=a+1; c=a+W; d=c+1; F+=[(a,c,b),(b,c,d)]
    return V,N,UV,F

def cylinder(r, h, n=24, axis='y', caps=True, rfn=None, seg=1):
    """Cylinder centred at origin along +axis. rfn(ang, t)->radius multiplier."""
    V,N,UV,F=[],[],[],[]
    for k in range(seg+1):
        t=k/seg; y=-h/2+h*t
        for j in range(n+1):
            a=2*math.pi*j/n; m=rfn(a,t) if rfn else 1.0
            V.append((r*m*math.cos(a), y, r*m*math.sin(a))); N.append((math.cos(a),0,math.sin(a))); UV.append((j/n, t*h/(2*math.pi*r)))
    W=n+1
    for k in range(seg):
        for j in range(n):
            a=k*W+j; b=a+1; c=a+W; d=c+1; F+=[(a,c,b),(b,c,d)]
    if caps:
        for y,s in ((-h/2,-1),(h/2,1)):
            ci=len(V); V.append((0,y,0)); N.append((0,s,0)); UV.append((0.5,0.5))
            for j in range(n+1):
                a=2*math.pi*j/n; V.append((r*math.cos(a),y,r*math.sin(a))); N.append((0,s,0)); UV.append((0.5+0.5*math.cos(a),0.5+0.5*math.sin(a)))
            for j in range(n): F.append((ci,ci+1+j,ci+2+j))
    V=np.array(V,float); N=np.array(N,float)
    if axis=='x': R=np.array(rot('z',-math.pi/2)); V=V@R.T; N=N@R.T
    if axis=='z': R=np.array(rot('x',math.pi/2)); V=V@R.T; N=N@R.T
    return V,N,UV,F

def torus(R_, r, nu=28, nv=12):
    """wheel tyre around Z axis"""
    V,N,UV,F=[],[],[],[]
    for i in range(nu+1):
        u=2*math.pi*i/nu
        for j in range(nv+1):
            v=2*math.pi*j/nv
            c=np.array([math.cos(u),math.sin(u),0]); n=c*math.cos(v)+np.array([0,0,1])*math.sin(v)
            V.append(c*R_+n*r); N.append(n); UV.append((i/nu,j/nv))
    W=nv+1
    for i in range(nu):
        for j in range(nv):
            a=i*W+j; b=a+1; c=a+W; d=c+1; F+=[(a,c,b),(b,c,d)]
    return V,N,UV,F

def plane(w, d, nx=1, nz=1, uvx=1, uvz=1, yfn=None):
    V,N,UV,F=[],[],[],[]
    for i in range(nz+1):
        for j in range(nx+1):
            x=-w/2+w*j/nx; z=-d/2+d*i/nz
            V.append((x, yfn(x,z) if yfn else 0, z)); N.append((0,1,0)); UV.append((uvx*j/nx, uvz*i/nz))
    W=nx+1
    for i in range(nz):
        for j in range(nx):
            a=i*W+j; b=a+1; c=a+W; d_=c+1; F+=[(a,c,b),(b,c,d_)]
    V=np.array(V,float)
    if yfn:  # recompute normals
        N=np.zeros_like(V)
        for a,b,c in F:
            n=np.cross(V[c]-V[a],V[b]-V[a]); N[a]+=n; N[b]+=n; N[c]+=n
        N/=np.maximum(np.linalg.norm(N,axis=1,keepdims=True),1e-9)
    return V,N,UV,F

def rbox(hx,hy,hz,r,n=4): return rounded_box(hx,hy,hz,min(r,hx,hy,hz)*0.999,n)

rng = np.random.default_rng(7)
def bumpy(amp, freq, seed=0):
    ph = np.random.default_rng(seed).random(6)*6.28
    return lambda th, phi: 1 + amp*(math.sin(freq*phi+ph[0])*math.sin(freq*th+ph[1]) + 0.5*math.sin(2.3*freq*phi+ph[2])*math.cos(1.7*freq*th+ph[3]))

# ---------------------------------------------------------------- extra builders
def smooth_normals(V, F):
    V = np.asarray(V, float); N = np.zeros_like(V)
    for a, b, c in F:
        n = np.cross(V[b] - V[a], V[c] - V[a]); N[a] += n; N[b] += n; N[c] += n
    return N / np.maximum(np.linalg.norm(N, axis=1, keepdims=True), 1e-9)

def loft(rings, cap0=True, cap1=True):
    """rings: list of arrays (k,3) with the same k (closed loops). Smooth normals."""
    V, UV, F = [], [], []
    k = len(rings[0]); R = len(rings)
    for i, r in enumerate(rings):
        for j in range(k + 1):
            V.append(r[j % k]); UV.append((j / k, i / (R - 1)))
    W = k + 1
    for i in range(R - 1):
        for j in range(k):
            a = i * W + j; b = a + 1; c = a + W; d = c + 1; F += [(a, c, b), (b, c, d)]
    V = np.array(V, float)
    N = smooth_normals(V, F)
    # weld seam normals
    for i in range(R):
        a = i * W; b = a + k; n = N[a] + N[b]; n /= max(np.linalg.norm(n), 1e-9); N[a] = n; N[b] = n
    V = list(V); N = list(N)
    # outward orientation: flip if normals point inward (centroid test)
    cen = np.mean(np.array(V), axis=0)
    if np.mean([np.dot(N[i], V[i] - cen) for i in range(len(V))]) < 0: N = [-n for n in N]
    for ci, (r, use) in enumerate(((rings[0], cap0), (rings[-1], cap1))):
        if not use: continue
        c = np.mean(r, axis=0); d = c - np.mean(rings[1] if ci == 0 else rings[-2], axis=0)
        nn = d / max(np.linalg.norm(d), 1e-9)
        o = len(V); V.append(c); N.append(nn); UV.append((0.5, 0.5))
        for j in range(k + 1): V.append(r[j % k]); N.append(nn); UV.append((0.5, 0.5))
        for j in range(k): F.append((o, o + 1 + j, o + 2 + j))
    return V, N, UV, F

def ring_ellipse(cx, cy, z, rx, ry, k=24, flat_bottom=None, pinch=0.0):
    pts = []
    for j in range(k):
        a = 2 * math.pi * j / k
        x, y = math.cos(a), math.sin(a)
        if pinch: y = y * (1 - pinch * abs(x))
        yy = cy + ry * y
        if flat_bottom is not None: yy = max(yy, flat_bottom)
        pts.append((cx + rx * x, yy, z))
    return np.array(pts)

def extrude(poly, y0, y1):
    """poly: list of (x,z) CCW seen from +Y. Flat-shaded prism between y0..y1."""
    V, N, UV, F = [], [], [], []
    P = [np.array(p, float) for p in poly]; n = len(P)
    for y, s in ((y1, 1), (y0, -1)):
        o = len(V)
        for p in P: V.append((p[0], y, p[1])); N.append((0, s, 0)); UV.append((p[0], p[1]))
        for j in range(1, n - 1): F.append((o, o + j, o + j + 1))
    for j in range(n):
        a, b = P[j], P[(j + 1) % n]
        e = b - a; nn = np.array([e[1], 0, -e[0]]); nn /= max(np.linalg.norm(nn), 1e-9)
        o = len(V)
        for (x, z), y in ((a, y0), (b, y0), (b, y1), (a, y1)): V.append((x, y, z)); N.append(nn); UV.append((0, 0))
        F += [(o, o + 1, o + 2), (o, o + 2, o + 3)]
    return V, N, UV, F

def wing(root_z0, root_z1, tip_z0, tip_z1, x0, x1, t, y=0.0, mirror=True):
    """swept trapezoid wing (x from x0 to x1), thickness t; both sides if mirror"""
    m = M()
    poly = [(x0, root_z0), (x0, root_z1), (x1, tip_z1), (x1, tip_z0)]
    if poly_area(poly) < 0: poly = poly[::-1]
    m.add(*extrude(poly, y - t / 2, y + t / 2))
    if mirror:
        pm = [(-x, z) for x, z in poly][::-1]
        m.add(*extrude(pm, y - t / 2, y + t / 2))
    return m

def poly_area(p):
    return 0.5 * sum(p[i][0] * p[(i + 1) % len(p)][1] - p[(i + 1) % len(p)][0] * p[i][1] for i in range(len(p)))

def fin(z0, z1, ztop0, ztop1, h, t, x=0.0, y=0.0):
    """vertical fin in the YZ plane"""
    poly = [(z0, 0), (z1, 0), (ztop1, h), (ztop0, h)]
    V, N, UV, F = extrude([(p[0], p[1]) for p in poly] if poly_area(poly) > 0 else [(p[0], p[1]) for p in poly[::-1]], -t / 2, t / 2)
    # map extrude's (x=z_, y=thick, z=height) -> (x=thick, y=height, z=z_)
    V = [(x + v[1], y + v[2], v[0]) for v in V]; N = [(n[1], n[2], n[0]) for n in N]
    return V, N, UV, F

# ================================================================ PLAYER JET / ENEMY JET (nose -Z)
def jet(prefix, big=1.0):
    def r_of(z):  # fuselage radius profile, z in [-1.15, 1.0]
        if z < -0.35: t = (z + 1.15) / 0.8; return 0.21 * math.sin(t * math.pi / 2) ** 0.75
        if z < 0.6: return 0.21
        return 0.21 - 0.06 * (z - 0.6) / 0.4
    rings = []
    zs = list(np.linspace(-1.15, -0.35, 12)) + list(np.linspace(-0.25, 1.0, 8))
    for z in zs:
        r = max(r_of(z), 0.004)
        rings.append(ring_ellipse(0, 0.0, z, r * 1.05, r * 0.85, 24))
    body = M(); body.add(*loft(rings))
    # dorsal spine
    body.add(*loft([ring_ellipse(0, 0.12, z, 0.07 * s, 0.09 * s, 12) for z, s in ((-0.4, 0.05), (-0.1, 1), (0.6, 1), (0.95, 0.3))]))
    body.add(*fin(0.45, 1.0, 0.82, 1.05, 0.55, 0.035, 0, 0.1))
    wings = M()
    wings.add(*wing_parts(-0.35, 0.75, 0.48, 0.78, 0.12, 1.08, 0.05, -0.03))
    wings.add(*wing_parts(0.68, 1.02, 0.9, 1.03, 0.1, 0.5, 0.035, 0.0))   # tailplanes
    wings.add(*wing_parts(-0.72, -0.5, -0.56, -0.5, 0.15, 0.36, 0.025, 0.02))  # canards
    trim = M()
    for s in (-1, 1):  # intakes
        trim.add(*rbox(0.07, 0.1, 0.32, 0.03), t=(s * 0.22, -0.03, -0.1))
        trim.add(*rbox(0.025, 0.025, 0.12, 0.012), t=(s * 1.08, -0.03, 0.55))  # wingtip rails
    trim.add(*cylinder(0.15, 0.22, 24, 'z', caps=False, rfn=lambda a, t: 1 - 0.18 * t), t=(0, 0, 1.03))
    trim.add(*cylinder(0.035, 0.5, 10, 'z'), t=(0, -0.21, -0.1))  # belly pod
    canopy = M(); canopy.add(*ellipsoid(0.11, 0.1, 0.34, 20, 12), t=(0, 0.13, -0.42))
    glow = M(); glow.add(*cylinder(0.125, 0.02, 20, 'z'), t=(0, 0, 1.13))
    for s in (-1, 1): glow.add(*ellipsoid(0.03, 0.03, 0.03, 8, 6), t=(s * 1.09, -0.03, 0.42))
    for nm, m in (('body', body), ('wing', wings), ('trim', trim), ('canopy', canopy), ('glow', glow)):
        if big != 1.0: m.V = [np.array(v) * big for v in m.V]
        m.save(f'{prefix}_{nm}')

def wing_parts(rz0, rz1, tz0, tz1, x0, x1, t, y):
    m = wing(rz0, rz1, tz0, tz1, x0, x1, t, y)
    return m.V, m.N, m.UV, m.F

# ================================================================ HELICOPTER (nose -Z)
def heli():
    body = M()
    body.add(*ellipsoid(0.42, 0.42, 0.78, 28, 16, fn=lambda th, ph: 1.0), t=(0, 0.0, -0.15))
    boom = [ring_ellipse(0, 0.12 - 0.08 * t, 0.35 + 1.45 * t, 0.16 - 0.1 * t, 0.17 - 0.1 * t, 14) for t in np.linspace(0, 1, 8)]
    body.add(*loft(boom))
    body.add(*fin(1.55, 1.85, 1.75, 1.95, 0.55, 0.04, 0, 0.05))
    body.add(*wing_parts(1.45, 1.62, 1.55, 1.62, 0.0, 0.32, 0.03, 0.06))
    body.add(*rbox(0.2, 0.12, 0.35, 0.08), t=(0, 0.42, 0.05))   # engine hump
    glass = M(); glass.add(*ellipsoid(0.36, 0.3, 0.42, 22, 12), t=(0, 0.08, -0.55))
    skid = M()
    for s in (-1, 1):
        skid.add(*cylinder(0.035, 1.5, 10, 'z'), t=(s * 0.42, -0.55, -0.1))
        for z in (-0.45, 0.3): skid.add(*cylinder(0.025, 0.4, 8, 'y'), t=(s * 0.34, -0.38, z), R=rot('z', s * 0.45))
    rotor = M()
    rotor.add(*cylinder(0.05, 0.22, 10, 'y'), t=(0, 0.11, 0))
    rotor.add(*cylinder(0.12, 0.06, 14, 'y'), t=(0, 0.22, 0))
    for a in (0, math.pi / 2):
        rotor.add(*rbox(1.45, 0.012, 0.075, 0.01), t=(0, 0.24, 0), R=rot('y', a))
    trot = M()
    trot.add(*rbox(0.012, 0.32, 0.04, 0.008)); trot.add(*rbox(0.012, 0.04, 0.32, 0.008)); trot.add(*cylinder(0.03, 0.05, 8, 'x'))
    glow = M()
    glow.add(*ellipsoid(0.05, 0.05, 0.05, 8, 6), t=(0, -0.43, 0.0))
    glow.add(*ellipsoid(0.04, 0.04, 0.04, 8, 6), t=(0, 0.62, 1.86))
    rotor.V = [np.array(v) + [0, 0.42, 0] for v in rotor.V]
    for nm, m in (('body', body), ('glass', glass), ('skid', skid), ('rotor', rotor), ('trotor', trot), ('glow', glow)):
        m.save('heli_' + nm)

# ================================================================ SHIP / TANKER (bow -Z)
def ship():
    def half_w(z):
        if z < -1.2: t = (z + 2.25) / 1.05; return 0.62 * math.sin(max(t, 0) * math.pi / 2) ** 0.8
        if z > 1.8: return 0.62 - 0.12 * (z - 1.8) / 0.25
        return 0.62
    rings = []
    for z in list(np.linspace(-2.25, -1.2, 10)) + list(np.linspace(-1.0, 2.05, 7)):
        w = max(half_w(z), 0.01); deck = 0.32 + 0.12 * max(0, (-1.2 - z) / 1.05) ** 2
        pts = []
        for j in range(20):
            a = math.pi * j / 19   # 0..pi: right deck edge -> bottom -> left deck edge
            x = w * math.cos(a); y = deck - (deck + 0.3) * math.sin(a) ** 0.6
            pts.append((x, y, z))
        rings.append(np.array(pts))
    # close rings across the deck by mirroring (open u-shape closed with straight top edge)
    hull = M(); hull.add(*loft([np.vstack([r, r[::-1][1:-1] * [1, 0, 1] + [0, r[0][1], 0]]) for r in rings]))
    deck = M()
    poly = [(half_w(z) * 0.93, z) for z in np.linspace(-1.9, 2.0, 14)]
    poly = poly + [(-x, z) for x, z in poly[::-1]]
    deck.add(*extrude(poly[::-1] if poly_area(poly) < 0 else poly, 0.30, 0.345))
    for z in (-0.9, -0.15, 0.6):  # cargo tanks
        deck.add(*cylinder(0.32, 0.62, 20, 'z'), t=(0, 0.48, z))
    deck.add(*cylinder(0.04, 2.9, 8, 'z'), t=(0.38, 0.42, -0.2))
    cabin = M()
    cabin.add(*rbox(0.48, 0.28, 0.38, 0.05), t=(0, 0.62, 1.5))
    cabin.add(*rbox(0.4, 0.16, 0.3, 0.04), t=(0, 1.02, 1.45))
    cabin.add(*rbox(0.56, 0.03, 0.16, 0.02), t=(0, 1.14, 1.32))  # bridge wings
    cabin.add(*cylinder(0.025, 0.7, 8, 'y'), t=(0, 1.45, 1.4))     # mast
    cabin.add(*cylinder(0.03, 0.9, 8, 'y'), t=(0, 0.75, -1.65))     # fore mast
    funnel = M()
    funnel.add(*cylinder(0.17, 0.55, 18, 'y', rfn=lambda a, t: 1 - 0.1 * t), t=(0, 1.3, 1.82))
    glow = M()
    glow.add(*rbox(0.41, 0.04, 0.31, 0.01), t=(0, 1.08, 1.45))     # window band
    glow.add(*ellipsoid(0.05, 0.05, 0.05, 8, 6), t=(0, 1.82, 1.4))
    glow.add(*ellipsoid(0.04, 0.04, 0.04, 8, 6), t=(0, 1.22, -1.65))
    for nm, m in (('hull', hull), ('deck', deck), ('cabin', cabin), ('funnel', funnel), ('glow', glow)):
        m.save('ship_' + nm)

# ================================================================ FUEL DEPOT (floating, faces -Z)
def depot():
    base = M()
    base.add(*rbox(0.85, 0.16, 1.15, 0.06), t=(0, 0.02, 0))
    for s in (-1, 1): base.add(*cylinder(0.14, 2.2, 14, 'z'), t=(s * 0.78, -0.05, 0))  # floats
    tank = M()
    V, N, UV, F = cylinder(0.58, 1.25, 32, 'y', caps=False)
    UV = [(1 - u, (V[i][1] + 0.625) / 1.25) for i, (u, _) in enumerate(UV)]
    tank.add(V, N, UV, F, t=(0, 0.82, 0))
    dome = M()
    dome.add(*ellipsoid(0.58, 0.2, 0.58, 28, 10), t=(0, 1.44, 0))
    for a in range(8):  # railing posts
        ang = a * math.pi / 4
        dome.add(*cylinder(0.015, 0.2, 6, 'y'), t=(0.6 * math.cos(ang), 1.6, 0.6 * math.sin(ang)))
    dome.add(*torus(0.6, 0.015, 32, 6), t=(0, 1.7, 0), R=rot('x', math.pi / 2))
    dome.add(*cylinder(0.05, 0.6, 8, 'y'), t=(0.45, 0.5, 0.75))     # pump
    dome.add(*rbox(0.12, 0.25, 0.1, 0.03), t=(-0.55, 0.42, 0.85))
    glow = M()
    glow.add(*ellipsoid(0.07, 0.07, 0.07, 10, 8), t=(0, 1.78, 0))
    for s in (-1, 1): glow.add(*ellipsoid(0.04, 0.04, 0.04, 8, 6), t=(s * 0.8, 0.22, -1.1))
    for nm, m in (('base', base), ('tank', tank), ('dome', dome), ('glow', glow)):
        m.save('depot_' + nm)

# ================================================================ BRIDGE (spans X, deck centred)
BR_HALF = 6.0
def rbox2(hx,hy,hz,r): return rounded_box(hx,hy,hz,min(r,hx,hy,hz)*0.999,2)
def bridge():
    road = M(); road.add(*plane(2 * BR_HALF, 1.5, 1, 1, 6, 1), t=(0, 1.32, 0))
    deck = M(); deck.add(*rbox(BR_HALF, 0.14, 0.85, 0.04), t=(0, 1.17, 0))
    steel = M()
    for s in (-1, 1):
        z = s * 0.8
        steel.add(*rbox2(BR_HALF, 0.05, 0.05, 0.02), t=(0, 2.05, z))        # top chord
        steel.add(*rbox2(BR_HALF, 0.06, 0.05, 0.02), t=(0, 1.36, z))        # bottom chord
        n = 12
        for i in range(n + 1):
            x = -BR_HALF + 2 * BR_HALF * i / n
            steel.add(*rbox2(0.04, 0.36, 0.04, 0.015), t=(x, 1.7, z))
            if i < n:
                d = 2 * BR_HALF / n; L = math.hypot(d, 0.7)
                ang = math.atan2(0.7, d) * (1 if i % 2 == 0 else -1)
                steel.add(*rbox2(L / 2, 0.025, 0.025, 0.01), t=(x + d / 2, 1.7, z), R=rot('z', ang))
    for i in range(7):   # overhead cross beams
        x = -BR_HALF + 0.5 + i * (2 * BR_HALF - 1) / 6
        steel.add(*rbox2(0.04, 0.04, 0.82, 0.015), t=(x, 2.06, 0))
    pier = M()
    for x in (-2.0, 2.0):
        pier.add(*rbox(0.32, 0.9, 0.6, 0.08), t=(x, 0.15, 0))
        pier.add(*rbox(0.42, 0.08, 0.72, 0.03), t=(x, 0.98, 0))
    lamp = M(); glow = M()
    for x in (-4.5, -1.5, 1.5, 4.5):
        for s in (-1, 1):
            lamp.add(*cylinder(0.025, 0.6, 8, 'y'), t=(x, 1.62, s * 0.68))
            glow.add(*ellipsoid(0.07, 0.06, 0.07, 10, 6), t=(x, 1.95, s * 0.68))
    for nm, m in (('road', road), ('deck', deck), ('steel', steel), ('pier', pier), ('lamp', lamp), ('glow', glow)):
        m.V = [np.array(v) - [0, 0.35, 0] for v in m.V]
        m.save('bridge_' + nm)

# land road segment (2u long along X, top at y=0.63)
def road():
    m = M(); m.add(*plane(2.0, 1.5, 1, 1, 1, 1), t=(0, 0.64, 0)); m.save('road')
    k = M(); k.add(*rbox(1.0, 0.04, 0.86, 0.02), t=(0, 0.6, 0)); k.save('road_kerb')

# ================================================================ SHORE STRIP (unit length along Z, water at +X)
LAND_Y = 0.6
def shore():
    nz, nx = 16, 44
    xs = np.linspace(-2.6, 0.55, nx + 1)
    def prof(x):
        if x < -0.9: return LAND_Y + 0.03 * math.sin(x * 3)
        t = (x + 0.9) / 1.45
        return LAND_Y - (LAND_Y + 0.45) * (3 * t * t - 2 * t ** 3)
    def disp(x, z):  # rock bumps periodic in z (period 1) so strips tile
        if x < -0.95: return 0.0
        w = math.sin(math.pi * min(1, (x + 0.95) / 0.5))
        p = 2 * math.pi * z
        return w * (0.09 * math.sin(3 * p + 7 * x) + 0.05 * math.sin(7 * p - 11 * x + 1) + 0.03 * math.cos(13 * p + 5 * x))
    def build(x_lo, x_hi, rough):
        V, UV, F = [], [], []
        sel = [x for x in xs if x_lo - 1e-6 <= x <= x_hi + 1e-6]
        for i in range(nz + 1):
            z = -0.5 + i / nz
            for x in sel:
                y = prof(x) + (disp(x, z) if rough else 0)
                xx = x + (0.6 * disp(x, z + 0.17) if rough else 0)
                V.append((xx, y, z)); UV.append((x * 0.5, z))
        W = len(sel)
        for i in range(nz):
            for j in range(W - 1):
                a = i * W + j; b = a + 1; c = a + W; d = c + 1; F += [(a, b, c), (b, d, c)]
        V = np.array(V); N = smooth_normals(V, F)
        if N[:, 1].mean() < 0: N = -N
        return V, N, UV, F
    g = M(); g.add(*build(-2.6, -0.9, False)); g.save('shore_grass')
    r = M(); r.add(*build(-1.08, 0.55, True)); r.save('shore_rock')

def land():
    m = M(); m.add(*plane(1.0, 1.0, 1, 1, 1, 1), t=(-0.5, LAND_Y + 0.02, 0)); m.save('land')

def trees():
    trunk = M(); trunk.add(*cylinder(0.07, 0.6, 8, 'y', rfn=lambda a, t: 1 - 0.3 * t), t=(0, 0.3, 0)); trunk.save('tree_trunk')
    pine = M()
    for i, (y, r, h) in enumerate(((0.55, 0.5, 0.7), (0.95, 0.4, 0.6), (1.3, 0.28, 0.5))):
        V, N, UV, F = cylinder(r, h, 14, 'y', caps=True, rfn=lambda a, t: (1 - t) * (1 + 0.08 * math.sin(a * 5)) + 0.01)
        pine.add(V, N, UV, F, t=(0, y + h / 2 - 0.1, 0))
    pine.V = list(pine.V); pine.N = list(smooth_normals(pine.V, pine.F)); pine.save('tree_pine')
    leaf = M()
    for k, (dx, dy, dz, r) in enumerate(((0, 0.95, 0, 0.48), (0.25, 0.8, 0.15, 0.36), (-0.22, 0.78, -0.12, 0.38), (0.05, 1.22, -0.05, 0.33))):
        leaf.add(*ellipsoid(r, r * 0.9, r, 16, 10, fn=bumpy(0.12, 4, k)), t=(dx, dy, dz))
    leaf.save('tree_leaf')
    rock = M(); rock.add(*ellipsoid(0.5, 0.32, 0.42, 14, 9, fn=bumpy(0.18, 3, 5)), t=(0, 0.1, 0)); rock.save('boulder')

def house():
    w = M(); w.add(*rbox(0.6, 0.38, 0.45, 0.03), t=(0, 0.38, 0)); w.add(*rbox(0.08, 0.25, 0.08, 0.01), t=(0.3, 1.05, 0.15)); w.save('house_wall')
    rf = M()
    poly = [(-0.52, 0.0), (0.52, 0.0), (0.0, 0.42)]
    V, N, UV, F = extrude(poly, -0.68, 0.68)
    V = [(v[1], v[2] + 0.74, v[0]) for v in V]; N = [(n[1], n[2], n[0]) for n in N]
    rf.add(V, N, UV, F); rf.save('house_roof')
    win = M()
    for x in (-0.3, 0.3): win.add(*rbox(0.12, 0.1, 0.01, 0.01), t=(x, 0.42, -0.455))
    win.save('house_win')

def water():
    m = M(); m.add(*plane(90.0, 120.0, 1, 1, 90 / 8, 120 / 8)); m.save('water')
    b = M(); b.add(*plane(90.0, 120.0, 1, 1, 1, 1), t=(0, -0.6, 0)); b.save('riverbed')

# ================================================================ FX
def fx():
    f = M(); f.add(*ellipsoid(1, 1, 1, 18, 12, fn=bumpy(0.22, 3, 9))); f.save('fx_fire')
    c = M(); c.add(*ellipsoid(1, 1, 1, 14, 10, fn=bumpy(0.1, 4, 3))); c.save('fx_core')
    s = M(); s.add(*ellipsoid(1, 1, 1, 14, 10, fn=bumpy(0.25, 2, 4))); s.save('fx_smoke')
    d = M(); d.add(*extrude([(-0.15, -0.1), (0.18, -0.06), (0.02, 0.16)], -0.03, 0.03)); d.save('fx_debris')
    r = M(); r.add(*torus(1.0, 0.025, 48, 6), R=rot('x', math.pi / 2)); r.save('fx_ring')
    mb = M()
    mb.add(*loft([ring_ellipse(0, 0, z, rr, rr, 12) for z, rr in ((-0.32, 0.002), (-0.26, 0.035), (-0.18, 0.045), (0.25, 0.045), (0.3, 0.035))]))
    mb.add(*wing_parts(0.15, 0.28, 0.24, 0.3, 0.03, 0.11, 0.012, 0))
    mb.add(*fin(0.15, 0.28, 0.24, 0.3, 0.08, 0.012, 0, 0.02))
    mb.save('missile_body')
    mg = M(); mg.add(*ellipsoid(0.05, 0.05, 0.12, 10, 8), t=(0, 0, 0.36)); mg.save('missile_glow')

if __name__ == '__main__':
    jet('jet'); jet('ejet', 0.9); heli(); ship(); depot(); bridge(); road(); shore(); land(); trees(); house(); water(); fx()
