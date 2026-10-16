#!/usr/bin/env python3
"""Procedural meshes for Centipede Remix. Writes OBJ into ../meshsrc/. Cook with cook_all.sh."""
import numpy as np, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
# Re-exec the generator embedded below (same geometry as initial build).
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'meshsrc')
os.makedirs(OUT, exist_ok=True)

def save(name, V, N, UV, F):
    V, N = np.asarray(V, float), np.asarray(N, float)
    with open(os.path.join(OUT, name + '.obj'), 'w') as fo:
        fo.write(f'o {name}\n')
        for p in V: fo.write('v %.5f %.5f %.5f\n' % tuple(p))
        for t in UV: fo.write('vt %.5f %.5f\n' % tuple(t))
        for n in N: fo.write('vn %.5f %.5f %.5f\n' % tuple(n))
        for a, b, c in F:
            fn = np.cross(V[b] - V[a], V[c] - V[a])
            if np.linalg.norm(fn) < 1e-7: continue   # zero-area tris make PhasmaCook split the mesh (mesh 0 invisible)
            if np.dot(fn, N[a] + N[b] + N[c]) < 0: b, c = c, b
            fo.write(f'f {a+1}/{a+1}/{a+1} {b+1}/{b+1}/{b+1} {c+1}/{c+1}/{c+1}\n')
    print(name, len(V), 'verts')

def lathe(profile, segs=16):
    V, N, UV, F = [], [], [], []
    P = np.asarray(profile, float)
    for j, (r, y) in enumerate(P):
        for i in range(segs):
            a = (i / segs) * 2 * np.pi
            c, s = np.cos(a), np.sin(a)
            V.append((r * c, y, r * s))
            if j == 0: dy, dr = P[1,1]-P[0,1], P[1,0]-P[0,0]
            elif j == len(P)-1: dy, dr = P[j,1]-P[j-1,1], P[j,0]-P[j-1,0]
            else: dy, dr = P[j+1,1]-P[j-1,1], P[j+1,0]-P[j-1,0]
            nx, ny = dy, -dr; ln = np.hypot(nx, ny) + 1e-9; nx, ny = nx/ln, ny/ln
            N.append((nx * c, ny, nx * s)); UV.append((i / segs, j / max(1, len(P)-1)))
    for j in range(len(P)-1):
        for i in range(segs):
            a = j*segs+i; b = j*segs+(i+1)%segs; c = (j+1)*segs+i; d = (j+1)*segs+(i+1)%segs
            F += [(a,b,d),(a,d,c)]
    return V, N, UV, F

def uv_sphere(r=0.5, stacks=10, slices=16, center=(0,0,0)):
    V, N, UV, F = [], [], [], []; cx,cy,cz = center
    for j in range(stacks+1):
        v = j/stacks; phi = v*np.pi
        for i in range(slices):
            u = i/slices; th = u*2*np.pi
            x,y,z = np.sin(phi)*np.cos(th), np.cos(phi), np.sin(phi)*np.sin(th)
            V.append((cx+r*x, cy+r*y, cz+r*z)); N.append((x,y,z)); UV.append((u,v))
    for j in range(stacks):
        for i in range(slices):
            a=j*slices+i; b=j*slices+(i+1)%slices; c=(j+1)*slices+i; d=(j+1)*slices+(i+1)%slices
            if j>0: F.append((a,b,d))
            if j<stacks-1: F.append((a,d,c))
    return V,N,UV,F

def merge(*meshes):
    V,N,UV,F=[],[],[],[]
    for Vm,Nm,UVm,Fm in meshes:
        base=len(V); V.extend(Vm); N.extend(Nm); UV.extend(UVm)
        F.extend([(a+base,b+base,c+base) for a,b,c in Fm])
    return V,N,UV,F

def offset(mesh, ox, oy, oz):
    V,N,UV,F = mesh
    return ([(p[0]+ox,p[1]+oy,p[2]+oz) for p in V], N, UV, F)

def rounded_box(hx, hy, hz, r, n=6):
    inner = np.array([hx-r, hy-r, hz-r]); V,N,UV,F=[],[],[],[]; k=n
    edge = np.sin(np.linspace(0, np.pi/2, k))
    def samples(h, rr):
        if h-rr < 1e-6: return (-np.cos(np.linspace(0,np.pi,2*k-1)))*h
        return np.concatenate([-(h-rr)-rr*edge[::-1], np.linspace(-(h-rr),(h-rr),4)[1:-1], (h-rr)+rr*edge])
    H=np.array([hx,hy,hz])
    for axis in range(3):
        for s in (-1,1):
            u_ax,v_ax=[a for a in range(3) if a!=axis]
            if s<0: u_ax,v_ax=v_ax,u_ax
            us,vs=samples(H[u_ax],r),samples(H[v_ax],r); base=len(V)
            for j,vv in enumerate(vs):
                for i,uu in enumerate(us):
                    p=np.zeros(3); p[axis]=s*H[axis]; p[u_ax]=uu; p[v_ax]=vv
                    c=np.clip(p,-inner,inner); d=p-c; ln=np.linalg.norm(d)
                    nrm=d/ln if ln>1e-9 else np.eye(3)[axis]*s
                    V.append(c+nrm*r); N.append(nrm); UV.append(((uu/H[u_ax]+1)*0.5,(vv/H[v_ax]+1)*0.5))
            W=len(us)
            for j in range(len(vs)-1):
                for i in range(W-1):
                    a=base+j*W+i; b=a+1; c2=a+W; d2=c2+1; F += [(a,b,d2),(a,d2,c2)]
    return V,N,UV,F

def squash(m, sx, sy, sz, ox=0, oy=0, oz=0):
    return ([(p[0]*sx+ox, p[1]*sy+oy, p[2]*sz+oz) for p in m[0]], m[1], m[2], m[3])
def leg_pair(y):
    out=[]
    for side in (-1,1):
        L=lathe([(0.045,0),(0.05,0.12),(0.035,0.3),(0.015,0.42)],6)
        # leg grows along +-X (sideways from the direction of travel = mesh +Y), bent down toward the floor (-Z)
        V2=[(side*(0.30+p[1]*0.9), y+p[0]*1.0, -0.05-p[1]*0.45+p[2]*1.0) for p in L[0]]
        out.append((V2,L[1],L[2],L[3]))
    return out
# body segment: a round, slightly flattened bead (mesh +Y = travel direction, +Z = toward camera) with two leg pairs
bead=squash(uv_sphere(0.5,12,18),0.84,0.78,0.64)
band=squash(lathe([(0.43,-0.05),(0.45,0.0),(0.43,0.05)],18),1.0,1.0,0.8)
save('centi_body', *merge(bead, band, *leg_pair(0.14), *leg_pair(-0.14)))

head=squash(uv_sphere(0.5,12,18),0.92,0.88,0.70)
def antenna(side):
    L=lathe([(0.035,0),(0.03,0.2),(0.02,0.45),(0.012,0.6)],6)
    V2=[(side*(0.18+p[1]*0.45)+p[0], 0.36+p[1]*0.75, 0.22+p[1]*0.25+p[2]) for p in L[0]]
    return (V2,L[1],L[2],L[3])
def mandible(side):
    L=lathe([(0.06,0),(0.05,0.12),(0.02,0.24)],6)
    V2=[(side*(0.16-p[1]*0.35)+p[0], 0.40+p[1]*0.6, -0.02+p[2]) for p in L[0]]
    return (V2,L[1],L[2],L[3])
save('centi_head', *merge(head, uv_sphere(0.13,8,12,(0.24,0.26,0.24)), uv_sphere(0.13,8,12,(-0.24,0.26,0.24)),
    antenna(-1), antenna(1), mandible(-1), mandible(1), *leg_pair(0.0)))
save('centi_leg', *lathe([(0.04,0),(0.05,0.15),(0.03,0.35),(0.01,0.5)],8))
save('mush_stem', *lathe([(0.12,-0.05),(0.14,0),(0.12,0.25),(0.14,0.45),(0.10,0.55)],14))
cap=[(0.55*np.sin(t*np.pi*0.55)+0.05, 0.55+0.42*np.cos(t*np.pi*0.55)) for t in np.linspace(0,1,14)]+[ (0.02,0.97)]
save('mush_cap', *lathe(cap,18))
save('mush_glow', *lathe([(0.48,0.58),(0.42,0.56),(0.20,0.55),(0.05,0.54)],16))
hull=rounded_box(0.55,0.22,0.4,0.12,5)
cannon=offset(lathe([(0.12,0),(0.14,0.2),(0.10,0.55),(0.08,0.7)],12),0,0.05,0.35)
save('blaster', *merge(hull, cannon, uv_sphere(0.22,8,12,(0,0.28,-0.05))))
save('bullet', *lathe([(0.03,-0.45),(0.09,-0.3),(0.11,0.0),(0.09,0.3),(0.03,0.48),(0.008,0.52)],12))
ceph=uv_sphere(0.28,8,12,(0,0.15,0.15)); abd=uv_sphere(0.38,8,12,(0,0.2,-0.25))
abd=([(p[0]*1.1,p[1]*0.85,p[2]*1.2) for p in abd[0]],abd[1],abd[2],abd[3])
legs=[]
for side in (-1,1):
    for k,ang in enumerate([-0.8,-0.3,0.3,0.8]):
        L=lathe([(0.03,0),(0.04,0.2),(0.025,0.55),(0.01,0.75)],6)
        V2=[(side*(0.25+0.05*k)+side*(0.15+p[1]*0.35)+p[0]*0.5, p[1]*0.55, ang*0.35+p[2]) for p in L[0]]
        legs.append((V2,L[1],L[2],L[3]))
save('spider', *merge(ceph,abd,*legs))
save('flea', *merge(lathe([(0.05,-0.2),(0.28,-0.05),(0.32,0.15),(0.22,0.35),(0.08,0.48),(0.02,0.55)],14),
    uv_sphere(0.08,6,8,(0.12,0.35,0.2)), offset(uv_sphere(0.08,6,8),-0.12,0.35,0.2)))
sc=rounded_box(0.22,0.14,0.55,0.08,4); tails=[]
for i in range(5):
    t=rounded_box(0.10-i*0.012,0.10-i*0.01,0.14,0.04,3); ang=-0.55*i; ca,sa=np.cos(ang),np.sin(ang)
    V2=[(p[0], 0.15+i*0.18+p[1]*ca-p[2]*sa, -0.45-i*0.12+p[1]*sa+p[2]*ca) for p in t[0]]
    tails.append((V2,t[1],t[2],t[3]))
cl=rounded_box(0.18,0.08,0.22,0.05,3)
save('scorpion', *merge(sc,*tails,uv_sphere(0.08,6,8,(0,0.15+5*0.18,-0.45-5*0.12)),
    ([(p[0]+0.35,p[1]+0.05,p[2]+0.55) for p in cl[0]],cl[1],cl[2],cl[3]),
    ([(p[0]-0.35,p[1]+0.05,p[2]+0.55) for p in cl[0]],cl[1],cl[2],cl[3])))
save('floor_tile', *rounded_box(0.5,0.04,0.5,0.02,3))
rock=uv_sphere(0.5,8,12); save('moss_clump', *([(p[0]*1.2,p[1]*0.45,p[2]*0.9) for p in rock[0]],rock[1],rock[2],rock[3]))
save('spore', *uv_sphere(0.5,8,12)); save('leaf', *rounded_box(0.35,0.02,0.18,0.015,3))
print('wrote', len(os.listdir(OUT)), 'objs to', OUT)
