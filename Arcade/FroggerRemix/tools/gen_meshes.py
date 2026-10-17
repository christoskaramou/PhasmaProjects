# Procedural meshes for Frogger Remix -> OBJ (cooked to .pemesh by PhasmaCook via cook_all.sh)
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
            if np.linalg.norm(fn) < 1e-10: continue   # drop degenerate tris (assimp would split them into a line mesh)
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
            n=np.cross(V[b]-V[a],V[c]-V[a]); N[a]+=n; N[b]+=n; N[c]+=n
        N/=np.maximum(np.linalg.norm(N,axis=1,keepdims=True),1e-9)
    return V,N,UV,F

def rbox(hx,hy,hz,r,n=4): return rounded_box(hx,hy,hz,min(r,hx,hy,hz)*0.999,n)

rng = np.random.default_rng(7)
def bumpy(amp, freq, seed=0):
    ph = np.random.default_rng(seed).random(6)*6.28
    return lambda th, phi: 1 + amp*(math.sin(freq*phi+ph[0])*math.sin(freq*th+ph[1]) + 0.5*math.sin(2.3*freq*phi+ph[2])*math.cos(1.7*freq*th+ph[3]))

# ================================================================ FROG (faces -Z, feet at y=0)
def frog():
    b = M()
    b.add(*ellipsoid(0.27, 0.16, 0.33, 32, 18, bumpy(0.025, 5, 1)), t=(0, 0.21, 0.04))      # body
    b.add(*ellipsoid(0.23, 0.13, 0.19, 28, 14), t=(0, 0.24, -0.2))                           # head
    for s in (-1, 1):
        b.add(*ellipsoid(0.085, 0.075, 0.085, 16, 10), t=(s*0.12, 0.33, -0.24))           # eye sockets
        b.add(*ellipsoid(0.07, 0.035, 0.12, 12, 8), t=(s*0.2, 0.27, 0.12))                   # dorsal ridge
    b.save('frog_body')
    be = M(); be.add(*ellipsoid(0.24, 0.1, 0.32, 28, 12), t=(0, 0.15, -0.02)); be.add(*ellipsoid(0.2, 0.07, 0.15, 20, 10), t=(0, 0.19, -0.22)); be.save('frog_belly')
    e = M(); p = M()
    for s in (-1, 1):
        e.add(*ellipsoid(0.07, 0.068, 0.07, 18, 12), t=(s*0.13, 0.36, -0.26))
        p.add(*ellipsoid(0.02, 0.04, 0.02, 10, 8), t=(s*0.165, 0.375, -0.315))
    e.save('frog_eye'); p.save('frog_pupil')
    sp = M()   # spots on the back (darker green)
    for (x, z, r) in [(0.1, 0.05, 0.05), (-0.09, 0.12, 0.045), (0.0, 0.22, 0.04), (-0.12, -0.04, 0.035), (0.14, 0.2, 0.035), (0.03, -0.05, 0.03)]:
        y = 0.21 + 0.16*math.sqrt(max(0, 1 - (x/0.27)**2 - ((z-0.04)/0.33)**2))
        sp.add(*ellipsoid(r, 0.012, r, 12, 6), t=(x, y - 0.004, z))
    sp.save('frog_spots')
    # back legs, origin at hip line (y=0.16, z=0.2): thigh, shin, webbed foot; node scales Z to extend
    lb = M()
    for s in (-1, 1):
        lb.add(*ellipsoid(0.07, 0.065, 0.17, 14, 10), t=(s*0.22, 0.0, 0.02), R=rot('y', s*0.5))
        lb.add(*ellipsoid(0.05, 0.045, 0.16, 12, 8), t=(s*0.3, -0.08, -0.06), R=rot('y', -s*0.35))
        for k in (-1, 0, 1):
            lb.add(*ellipsoid(0.03, 0.012, 0.11, 8, 6), t=(s*(0.3 + 0.07*k), -0.145, 0.1 + 0.02*abs(k)), R=rot('y', 0.3*k))
    lb.save('frog_legb')
    lf = M()   # front legs, origin at shoulder (y=0.16, z=-0.12)
    for s in (-1, 1):
        lf.add(*ellipsoid(0.04, 0.04, 0.12, 10, 8), t=(s*0.2, -0.06, -0.06), R=rot('x', 0.7) @ np.array(rot('y', s*0.4)))
        for k in (-1, 0, 1):
            lf.add(*ellipsoid(0.022, 0.01, 0.06, 8, 6), t=(s*(0.24 + 0.04*k), -0.15, -0.14), R=rot('y', 0.4*k))
    lf.save('frog_legf')
frog()

# ================================================================ VEHICLES (forward +X, ground y=0)
def wheels(m, xs, z, r, w):
    for x in xs:
        for s in (-1, 1):
            m.add(*torus(r - w*0.5, w*0.5, 24, 10), t=(x, r, s*z))
def hubs(m, xs, z, r, w):
    for x in xs:
        for s in (-1, 1):
            m.add(*cylinder(r*0.55, 0.02, 16, 'z'), t=(x, r, s*(z + w*0.45)))
def lamps(m, x, ys, zs, hx=0.03, hy=0.05, hz=0.08):
    for y in ys:
        for z in zs: m.add(*rbox(hx, hy, hz, 0.02, 3), t=(x, y, z))

def sedan():
    b = M()
    b.add(*rbox(0.74, 0.15, 0.38, 0.1, 5), t=(0, 0.3, 0))                    # lower body
    b.add(*rbox(0.36, 0.03, 0.32, 0.03, 3), t=(-0.08, 0.705, 0))              # roof
    for x in (-0.42, 0.42):                                                       # wheel arch flares
        for s in (-1, 1): b.add(*ellipsoid(0.2, 0.1, 0.07, 16, 8), t=(x, 0.33, s*0.36))
    b.save('sedan_body')
    g = M(); g.add(*rbox(0.38, 0.13, 0.33, 0.1, 5), t=(-0.08, 0.56, 0), R=None); g.save('sedan_glass')
    d = M(); wheels(d, (-0.45, 0.45), 0.33, 0.16, 0.12); d.add(*rbox(0.76, 0.04, 0.36, 0.03, 3), t=(0, 0.17, 0)); d.save('sedan_dark')
    c = M(); hubs(c, (-0.45, 0.45), 0.33, 0.16, 0.12); c.add(*rbox(0.04, 0.05, 0.36, 0.03, 3), t=(0.76, 0.22, 0)); c.add(*rbox(0.04, 0.05, 0.36, 0.03, 3), t=(-0.76, 0.22, 0)); c.save('sedan_chrome')
    h = M(); lamps(h, 0.74, (0.34,), (-0.26, 0.26)); h.save('sedan_head')
    t = M(); lamps(t, -0.74, (0.36,), (-0.27, 0.27), 0.03, 0.035, 0.09); t.save('sedan_tail')

def racer():
    b = M()
    prof = lambda a, tt: 1.0
    b.add(*rbox(0.82, 0.11, 0.4, 0.1, 5), t=(0, 0.23, 0))
    b.add(*ellipsoid(0.38, 0.09, 0.3, 24, 10), t=(0.45, 0.28, 0))           # sloped nose
    b.add(*rbox(0.07, 0.02, 0.4, 0.015, 3), t=(-0.76, 0.55, 0))                 # spoiler wing
    for s in (-1, 1): b.add(*rbox(0.03, 0.1, 0.02, 0.01, 2), t=(-0.74, 0.44, s*0.3))
    for s in (-1, 1): b.add(*rbox(0.5, 0.06, 0.05, 0.04, 3), t=(-0.05, 0.3, s*0.4))  # side skirts
    b.save('racer_body')
    g = M(); g.add(*rbox(0.3, 0.1, 0.27, 0.09, 5), t=(-0.12, 0.36, 0)); g.save('racer_glass')
    d = M(); wheels(d, (-0.5, 0.5), 0.36, 0.15, 0.14); d.save('racer_dark')
    c = M(); hubs(c, (-0.5, 0.5), 0.36, 0.15, 0.14); c.add(*cylinder(0.04, 0.12, 12, 'x'), t=(-0.86, 0.22, 0.15)); c.add(*cylinder(0.04, 0.12, 12, 'x'), t=(-0.86, 0.22, -0.15)); c.save('racer_chrome')
    h = M(); lamps(h, 0.8, (0.27,), (-0.27, 0.27), 0.03, 0.025, 0.1); h.save('racer_head')
    t = M(); t.add(*rbox(0.02, 0.025, 0.34, 0.02, 2), t=(-0.82, 0.29, 0)); t.save('racer_tail')

def dozer():
    b = M()
    b.add(*rbox(0.5, 0.2, 0.34, 0.06, 4), t=(-0.05, 0.42, 0))                  # engine body
    b.add(*rbox(0.24, 0.05, 0.34, 0.03, 3), t=(-0.25, 0.92, 0))                # cab roof
    for x in (-0.46, -0.04):
        for s in (-1, 1): b.add(*rbox(0.025, 0.2, 0.025, 0.01, 2), t=(x, 0.72, s*0.31))  # cab posts
    b.add(*cylinder(0.04, 0.3, 12), t=(0.25, 0.75, 0.15))                        # exhaust stack
    b.save('dozer_body')
    g = M(); g.add(*rbox(0.2, 0.16, 0.3, 0.02, 3), t=(-0.25, 0.72, 0)); g.save('dozer_glass')
    d = M()
    for s in (-1, 1):
        d.add(*rbox(0.6, 0.15, 0.1, 0.14, 6), t=(0, 0.15, s*0.36))                # tracks
        for x in (-0.45, -0.15, 0.15, 0.45): d.add(*rbox(0.012, 0.155, 0.105, 0.01, 2), t=(x, 0.15, s*0.36))
    d.save('dozer_dark')
    c = M()
    c.add(*rbox(0.05, 0.2, 0.46, 0.03, 3), t=(0.72, 0.24, 0), R=rot('z', 0.25))   # blade
    for s in (-1, 1): c.add(*rbox(0.2, 0.03, 0.03, 0.02, 2), t=(0.55, 0.3, s*0.25))
    c.save('dozer_chrome')
    h = M(); lamps(h, 0.46, (0.6,), (-0.22, 0.22), 0.03, 0.04, 0.05); h.add(*ellipsoid(0.05, 0.035, 0.05, 10, 6), t=(-0.25, 0.99, 0)); h.save('dozer_head')
    t = M(); lamps(t, -0.56, (0.45,), (-0.25, 0.25), 0.02, 0.04, 0.05); t.save('dozer_tail')

def truck():
    b = M()                                                                        # cab (paint)
    b.add(*rbox(0.34, 0.3, 0.4, 0.1, 5), t=(1.0, 0.55, 0))
    b.add(*rbox(0.18, 0.13, 0.4, 0.08, 4), t=(1.3, 0.38, 0))                      # hood
    b.add(*cylinder(0.035, 0.6, 12), t=(0.66, 1.0, 0.33))                          # exhaust stack
    b.save('truck_body')
    tr = M(); tr.add(*rbox(1.15, 0.42, 0.44, 0.05, 4), t=(-0.55, 0.78, 0)); tr.save('truck_trailer')
    for k in range(4): tr.add(*rbox(0.012, 0.4, 0.445, 0.008, 2), t=(-1.4 + k*0.56, 0.78, 0))
    tr.save('truck_trailer')
    g = M(); g.add(*rbox(0.05, 0.13, 0.36, 0.04, 3), t=(1.3, 0.68, 0)); [g.add(*rbox(0.2, 0.11, 0.02, 0.02, 2), t=(1.0, 0.68, s*0.405)) for s in (-1, 1)]; g.save('truck_glass')
    d = M(); wheels(d, (-1.3, -1.0, 0.0, 1.05), 0.36, 0.18, 0.13); d.add(*rbox(1.6, 0.05, 0.3, 0.03, 3), t=(-0.1, 0.25, 0)); d.save('truck_dark')
    c = M(); hubs(c, (-1.3, -1.0, 0.0, 1.05), 0.36, 0.18, 0.13); c.add(*rbox(0.03, 0.12, 0.38, 0.02, 3), t=(1.49, 0.38, 0)); c.add(*rbox(0.03, 0.06, 0.42, 0.02, 3), t=(1.47, 0.18, 0)); c.save('truck_chrome')
    h = M(); lamps(h, 1.48, (0.3,), (-0.3, 0.3), 0.03, 0.05, 0.06); [h.add(*ellipsoid(0.03, 0.03, 0.03, 8, 6), t=(1.2, 0.86, z)) for z in (-0.3, -0.1, 0.1, 0.3)]; h.save('truck_head')
    t = M(); lamps(t, -1.71, (0.45, 1.12), (-0.38, 0.38), 0.02, 0.04, 0.05); t.save('truck_tail')
sedan(); racer(); dozer(); truck()

# ================================================================ RIVER
def log(L, name):
    ph = np.random.default_rng(int(L*10)).random(8)*6.28
    def bark(a, t):
        x = t*L
        return 1 + 0.045*math.sin(9*a + ph[0] + 0.6*math.sin(x*1.3)) + 0.025*math.sin(17*a + ph[1] + x*2.1) + 0.02*math.sin(x*3.7 + ph[2]) - 0.05*math.exp(-((t-0.5)*L/0.25)**2)*0
    m = M(); m.add(*cylinder(0.33, L, 40, 'x', caps=False, rfn=bark, seg=int(L*10)))
    # stubs of cut branches
    for k in range(int(L)):
        x = -L/2 + 0.7 + k*(L-1.4)/max(1, int(L)-1); a = ph[k % 8]
        m.add(*cylinder(0.07, 0.14, 12, 'y'), t=(x, 0.33*math.cos(a)*0.9, 0.33*math.sin(a)*0.9) if False else (x, 0.32, 0.08*math.sin(a)), R=rot('z', 0.4*math.sin(a)))
    m.save(name)
    e = M()   # end caps with growth rings (slightly domed)
    for s in (-1, 1):
        V, N, UV, F = plane(0.66, 0.66, 1, 1)  # placeholder replaced below
        ce = M(); ring = []
        n = 40; V = [(0, 0, 0)]; N = [(0, 1, 0)]; UV = [(0.5, 0.5)]; F = []
        for r in range(1, 6):
            for j in range(n):
                a = 2*math.pi*j/n; rr = 0.33*r/5*bark(a, 0 if s < 0 else 1)
                V.append((rr*math.cos(a), -0.01*r, rr*math.sin(a))); N.append((0, 1, 0)); UV.append((0.5 + 0.5*r/5*math.cos(a), 0.5 + 0.5*r/5*math.sin(a)))
        for j in range(n): F.append((0, 1 + j, 1 + (j+1) % n))
        for r in range(4):
            for j in range(n):
                a = 1 + r*n + j; b = 1 + r*n + (j+1) % n; F += [(a, a+n, b), (b, a+n, b+n)]
        e.add(V, N, UV, F, t=(s*L/2, 0, 0), R=rot('z', -s*math.pi/2))
    e.save(name + '_end')
for L, nm in ((2.6, 'log_s'), (3.8, 'log_m'), (5.6, 'log_l')): log(L, nm)

def turtle():
    def shellfn(th, ph):
        # hex-ish scutes: bumps on a lattice
        return 1 + 0.035*math.cos(6*ph)*math.sin(3*th)**2 + 0.02*math.cos(11*ph + 2)*math.sin(6*th)
    s = M(); s.add(*ellipsoid(0.36, 0.2, 0.3, 40, 20, shellfn), t=(0, 0.06, 0))
    s.save('turtle_shell')
    r = M(); r.add(*ellipsoid(0.39, 0.035, 0.33, 40, 6), t=(0, 0.07, 0)); r.save('turtle_rim')
    b = M()
    b.add(*ellipsoid(0.11, 0.08, 0.09, 16, 10), t=(-0.44, 0.08, 0))               # head (faces -X; game rotates)
    b.add(*ellipsoid(0.08, 0.05, 0.06, 12, 8), t=(-0.33, 0.06, 0))                 # neck
    for sx, sz, ang in ((-0.22, 0.3, 0.6), (-0.22, -0.3, -0.6), (0.24, 0.27, -0.5), (0.24, -0.27, 0.5)):
        b.add(*ellipsoid(0.14 if sx < 0 else 0.1, 0.025, 0.06, 14, 6), t=(sx, 0.04, sz + np.sign(sz)*0.06), R=rot('y', ang))
    b.add(*ellipsoid(0.08, 0.025, 0.03, 10, 6), t=(0.4, 0.04, 0))
    b.save('turtle_body')
    e = M(); [e.add(*ellipsoid(0.022, 0.022, 0.022, 8, 6), t=(-0.51, 0.12, z)) for z in (-0.05, 0.05)]; e.save('turtle_eye')
turtle()

def lily():
    m = M(); n = 48; V = [(0, 0.02, 0)]; N = [(0, 1, 0)]; UV = [(0.5, 0.5)]; F = []
    for j in range(n + 1):
        a = 0.35 + (2*math.pi - 0.5)*j/n; rr = 0.42*(1 + 0.03*math.sin(a*7))
        V.append((rr*math.cos(a), 0.0, rr*math.sin(a))); N.append((0, 1, 0)); UV.append((0.5 + 0.5*math.cos(a), 0.5 + 0.5*math.sin(a)))
    for j in range(n): F.append((0, 1 + j, 2 + j))
    m.add(V, N, UV, F); m.save('lily_pad')
    f = M()
    for k in range(8):
        a = k*math.pi/4
        f.add(*ellipsoid(0.04, 0.025, 0.11, 10, 6), t=(0.08*math.cos(a), 0.07, 0.08*math.sin(a)), R=np.array(rot('y', -a + math.pi/2)) @ np.array(rot('x', -0.6)))
    for k in range(6):
        a = k*math.pi/3 + 0.3
        f.add(*ellipsoid(0.03, 0.02, 0.08, 10, 6), t=(0.05*math.cos(a), 0.11, 0.05*math.sin(a)), R=np.array(rot('y', -a + math.pi/2)) @ np.array(rot('x', -1.0)))
    f.save('lotus')
    c = M(); c.add(*ellipsoid(0.035, 0.03, 0.035, 10, 8), t=(0, 0.11, 0)); c.save('lotus_core')
lily()

def fly():
    b = M(); b.add(*ellipsoid(0.07, 0.06, 0.12, 14, 10)); b.add(*ellipsoid(0.06, 0.055, 0.06, 12, 8), t=(0, 0, -0.13)); b.save('fly_body')
    w = M()
    for s in (-1, 1): w.add(*ellipsoid(0.13, 0.008, 0.06, 14, 4), t=(s*0.13, 0.05, 0.02), R=rot('y', s*0.3))
    w.save('fly_wing')
fly()

# ================================================================ ENVIRONMENT
def env():
    M().add(*plane(44, 5, 44, 5, 11, 1)).save('road')              # asphalt: texture holds 5 lanes, repeats every 4u
    M().add(*plane(44, 1.0, 44, 1, 44, 1)).save('walk')            # pavement strip (1 tile per unit)
    # glossy river surface: real ripple geometry (periodic every 7u in X so the scrolling mesh loops seamlessly)
    wr = np.random.default_rng(21); waves = [(wr.integers(1, 9), wr.uniform(1.2, 5.0), wr.uniform(0, 6.28), wr.uniform(0.006, 0.016)) for _ in range(9)]
    def wy(x, z):
        return sum(a * math.sin(2 * math.pi * n / 7.0 * x + kz * z + ph) for n, kz, ph, a in waves)
    M().add(*plane(70, 6.4, 560, 48, 10, 1, yfn=wy)).save('water')
    M().add(*plane(70, 7.0, 35, 7, 1, 1, yfn=lambda x, z: -0.9 + 0.08*math.sin(x*0.7)*math.cos(z*1.3))).save('riverbed')
    M().add(*plane(60, 14, 60, 14, 15, 3.5)).save('grass')
    M().add(*rbox(22, 0.11, 0.09, 0.05, 3), t=(0, 0, 0)).save('curb')
    # stone embankment wall (bumpy blocks) facing the river
    w = M()
    for k in range(-22, 22):
        for row in range(2):
            x = k*1.0 + (0.5 if row else 0)
            w.add(*rbox(0.47, 0.17, 0.2, 0.06, 3), t=(x, -0.2 - row*0.36, 0), sc=(1, 1, 1 + 0.15*((k*7 + row*3) % 3)))
    w.save('bank_wall')
    # hedge clump (1.6 wide)
    h = M(); r = np.random.default_rng(5)
    for i in range(16):
        x = -0.7 + 1.4*r.random(); z = -0.35 + 0.7*r.random(); s = 0.22 + 0.12*r.random()
        h.add(*ellipsoid(s, s*0.9, s, 14, 9, bumpy(0.12, 7, i)), t=(x, 0.25 + 0.25*r.random(), z))
    h.save('hedge')
    # bay frame stones (U shape around each home bay)
    st = M()
    for x, z, sx, sz in ((-0.62, 0, 0.12, 0.5), (0.62, 0, 0.12, 0.5), (0, -0.5, 0.74, 0.12)):
        st.add(*rbox(sx, 0.1, sz, 0.06, 3), t=(x, 0.05, z))
    st.save('bay_stone')
    # street lamp: pole + arm (dark metal), lantern glass (emissive)
    p = M(); p.add(*cylinder(0.05, 3.0, 14, 'y'), t=(0, 1.5, 0)); p.add(*cylinder(0.1, 0.25, 14, 'y'), t=(0, 0.12, 0))
    p.add(*cylinder(0.03, 0.8, 10, 'x'), t=(0.38, 2.95, 0)); p.add(*rbox(0.18, 0.04, 0.12, 0.03, 3), t=(0.75, 2.92, 0)); p.save('lamp_pole')
    b = M(); b.add(*rbox(0.14, 0.03, 0.08, 0.02, 3), t=(0.75, 2.87, 0)); b.save('lamp_bulb')
    # grass tuft
    g = M(); r = np.random.default_rng(9)
    for i in range(9):
        a = r.random()*6.28; hgt = 0.18 + 0.15*r.random()
        g.add(*ellipsoid(0.018, hgt, 0.008, 6, 6), t=(0.06*math.cos(a), hgt*0.8, 0.06*math.sin(a)), R=np.array(rot('y', a)) @ np.array(rot('z', 0.35*(r.random() - 0.5) + 0.25)))
    g.save('tuft')
    # skyline building (unit, scaled per instance) + roof cap
    M().add(*rbox(0.5, 0.5, 0.5, 0.02, 2), t=(0, 0.5, 0)).save('bldg')
env()

# shimmering reflection streak (flat ellipse "glints" stacked along Z) for lamp / moon reflections on the river
def streak(name, length, width, n, seed):
    r = np.random.default_rng(seed); m = M()
    for i in range(n):
        f = i / (n - 1); z = -length / 2 + length * f + r.uniform(-0.05, 0.05)
        w = width * (0.35 + 0.65 * math.sin(math.pi * (0.15 + 0.7 * f))) * r.uniform(0.6, 1.2)
        m.add(*ellipsoid(w, 0.004, 0.035 + 0.03 * r.random(), 16, 4), t=(r.uniform(-0.12, 0.12) * width, 0, z))
    m.save(name)
streak('refl_lamp', 2.6, 0.32, 18, 1)
streak('refl_moon', 4.6, 0.6, 30, 2)
