# Procedural mesh generator for Pitfall! Remastered -> OBJ files (cooked to .pemesh with PhasmaCook).
import numpy as np, os, math
OUT = os.path.join(os.path.dirname(__file__), '..', 'meshsrc')
os.makedirs(OUT, exist_ok=True)
rng = np.random.default_rng(3)

class Mesh:
    def __init__(s): s.v=[]; s.uv=[]; s.f=[]
    def add(s, verts, uvs, faces):
        o=len(s.v); s.v+=list(map(tuple,verts)); s.uv+=list(map(tuple,uvs)); s.f+=[tuple(i+o for i in f) for f in faces]
    def merge(s, m): s.add(m.v, m.uv, m.f)
    def xform(s, M=None, t=(0,0,0), sc=(1,1,1)):
        V=np.array(s.v)*np.array(sc)
        if M is not None: V=V@np.array(M).T
        s.v=list(map(tuple,V+np.array(t))); return s
    def save(s, name, double=False):
        V=np.array(s.v,float); F=np.array(s.f)
        N=np.zeros_like(V)
        for a,b,c in F:
            n=np.cross(V[b]-V[a],V[c]-V[a]); N[a]+=n;N[b]+=n;N[c]+=n
        N/=np.maximum(np.linalg.norm(N,axis=1,keepdims=True),1e-9)
        with open(os.path.join(OUT,name+'.obj'),'w') as fo:
            fo.write(f'o {name}\n')
            for p in V: fo.write('v %.5f %.5f %.5f\n'%tuple(p))
            for t in s.uv: fo.write('vt %.5f %.5f\n'%tuple(t))
            for n in N: fo.write('vn %.5f %.5f %.5f\n'%tuple(n))
            for a,b,c in F:
                if np.linalg.norm(np.cross(V[b]-V[a],V[c]-V[a])) < 1e-7: continue  # zero-area: PhasmaCook would split the mesh
                fo.write(f'f {a+1}/{a+1}/{a+1} {b+1}/{b+1}/{b+1} {c+1}/{c+1}/{c+1}\n')
                if double: fo.write(f'f {a+1}/{a+1}/{a+1} {c+1}/{c+1}/{c+1} {b+1}/{b+1}/{b+1}\n')
        print(name, len(V), 'verts', len(F), 'tris')

def rotm(axis, ang):
    axis=np.array(axis,float); axis/=np.linalg.norm(axis); a=math.cos(ang/2); b,c,d=-axis*math.sin(ang/2)
    return np.array([[a*a+b*b-c*c-d*d,2*(b*c+a*d),2*(b*d-a*c)],[2*(b*c-a*d),a*a+c*c-b*b-d*d,2*(c*d+a*b)],[2*(b*d+a*c),2*(c*d-a*b),a*a+d*d-b*b-c*c]])

def loft(path, rx, ry=None, n=20, noise=None, caps=True, vscale=1.0, up=(0,0,1)):
    """Sweep an ellipse along path; rx/ry lists per ring; noise(i,j,ang)->radius multiplier."""
    path=np.array(path,float); m=Mesh(); ry=ry if ry is not None else rx
    rings=[]; L=0; prev=path[0]
    for i,c in enumerate(path):
        t=path[min(i+1,len(path)-1)]-path[max(i-1,0)]; t/=np.linalg.norm(t)
        u=np.array(up,float); u=u-np.dot(u,t)*t
        if np.linalg.norm(u)<1e-4: u=np.array([1,0,0.])-t[0]*t
        u/=np.linalg.norm(u); w=np.cross(t,u)
        L+=np.linalg.norm(c-prev); prev=c
        ring=[]
        for j in range(n+1):
            a=2*math.pi*j/n; k=noise(i,j%n,a) if noise else 1.0
            p=c+(u*math.cos(a)*rx[i]+w*math.sin(a)*ry[i])*k
            ring.append(p)
        rings.append((ring,L))
    for i,(ring,l) in enumerate(rings):
        m.add(ring,[(j/n,l*vscale) for j in range(n+1)],[])
    W=n+1
    for i in range(len(path)-1):
        for j in range(n):
            a=i*W+j;b=a+1;c=a+W;d=c+1
            m.f+=[(a,c,b),(b,c,d)]
    if caps:
        for i,flip in ((0,True),(len(path)-1,False)):
            ci=len(m.v); m.v.append(tuple(path[i])); m.uv.append((0.5,0.5))
            for j in range(n):
                a=i*W+j;b=a+1
                m.f.append((ci,b,a) if flip else (ci,a,b))
    return m

def sphere(r=(1,1,1), n=16, noise=0.0, c=(0,0,0)):
    m=Mesh(); V=[];UV=[]
    for i in range(n+1):
        th=math.pi*i/n
        for j in range(2*n+1):
            ph=2*math.pi*j/(2*n); k=1+noise*(rng.random()-0.5) if 0<i<n and j<2*n else 1
            V.append((c[0]+r[0]*math.sin(th)*math.cos(ph)*k, c[1]+r[1]*math.cos(th)*k, c[2]+r[2]*math.sin(th)*math.sin(ph)*k)); UV.append((j/(2*n),i/n))
    W=2*n+1; F=[]
    for i in range(n):
        for j in range(2*n):
            a=i*W+j;b=a+1;cc=a+W;d=cc+1; F+=[(a,b,cc),(b,d,cc)]
    m.add(V,UV,F); return m

def leaf(length=1.0, width=0.3, bend=0.25, segs=6):
    m=Mesh(); V=[];UV=[];F=[]
    for i in range(segs+1):
        t=i/segs; w=width*math.sin(math.pi*min(1,t*1.1))*0.5+0.002
        y=-bend*t*t; z=length*t
        V+=[(-w,y+abs(w)*0.15,z),(0,y,z),(w,y+abs(w)*0.15,z)]; UV+=[(0,t),(0.5,t),(1,t)]
    for i in range(segs):
        a=i*3; F+=[(a,a+3,a+1),(a+1,a+3,a+4),(a+1,a+4,a+2),(a+2,a+4,a+5)]
    m.add(V,UV,F); return m

# ---------------- log: curved, bark-bumped, with cut ends ----------------
N=28
path=[(0.06*math.sin(t*math.pi), 0, -0.75+1.5*t) for t in np.linspace(0,1,14)]
bump=rng.random((14,N))
def lognoise(i,j,a): 
    k=1+0.06*math.sin(a*7+i*0.9)+0.04*bump[i,j]
    return k if 0<i<13 else 0.92
log=loft(path,[0.45]*14,n=N,noise=lognoise,vscale=1.0,up=(0,1,0))
# knot
log.merge(sphere((0.12,0.09,0.12),8,0.2,(0.0,0.44,0.25)))
log.save('log')
ends=Mesh()
for z,fl in ((-0.755,1),(0.755,-1)):
    for r0,r1 in ((0,0.12),(0.12,0.25),(0.25,0.41)):
        pass
    c=Mesh(); V=[(0,0,z)];UV=[(0.5,0.5)];F=[]
    for j in range(N):
        a=2*math.pi*j/N; V.append((0.42*math.cos(a),0.42*math.sin(a),z)); UV.append((0.5+0.5*math.cos(a),0.5+0.5*math.sin(a)))
    for j in range(N):
        a=1+j;b=1+(j+1)%N; F.append((0,a,b) if fl>0 else (0,b,a))
    c.add(V,UV,F); ends.merge(c)
ends.save('logends', double=True)

# ---------------- crocodile (faces -X) ----------------
xs=np.linspace(-0.2,1.9,18)
def body_r(x):
    t=(x+0.2)/2.1
    return 0.36*(1-t)**0.6+0.04, 0.2*(1-t)**0.7+0.03
cp=[(x, 0.02*math.sin(x*3), 0.0) for x in xs]
rx=[body_r(x)[0] for x in xs]; ry=[body_r(x)[1] for x in xs]
def croc_noise(i,j,a):
    top = max(0, math.sin(a))  # ridges on top
    return 1+0.08*top*abs(math.sin(i*2.2))+0.03*rng.random()
body=loft(cp, ry, rx, n=24, noise=croc_noise, up=(0,1,0))  # rings in YZ: ry is vertical? loft u=up->y
# scutes
for x in np.linspace(0,1.6,9):
    r=body_r(x)[1]
    for zz in (-0.08,0.08):
        body.merge(sphere((0.05,0.05,0.04),5,0.0,(x,r*0.95+0.01,zz)))
# legs
for x,zz in ((0.05,0.3),(0.05,-0.3),(0.85,0.27),(0.85,-0.27)):
    leg=loft([(x,-0.05,0),(x-0.08,-0.17,zz*0.7),(x-0.15,-0.22,zz)],[0.07,0.06,0.05],n=8,up=(1,0,0))
    body.merge(leg)
# lower jaw/head
head=loft([(-0.2,-0.02,0),(-0.55,-0.06,0),(-0.95,-0.09,0)],[0.18,0.15,0.08],[0.32,0.24,0.12],n=16,up=(0,1,0))
body.merge(head)
body.save('croc_body')
# upper jaw (pivot at origin = hinge), extends to -X
uj=loft([(0.05,0.0,0),(-0.3,0.04,0),(-0.65,0.02,0),(-0.85,0.0,0)],[0.13,0.11,0.08,0.05],[0.3,0.24,0.16,0.1],n=16,up=(0,1,0))
for x,zz in ((-0.05,0.13),(-0.05,-0.13)):   # eye bumps
    uj.merge(sphere((0.08,0.07,0.07),8,0.0,(x,0.1,zz)))
uj.merge(sphere((0.03,0.02,0.03),4,0,(-0.83,0.06,0.05))); uj.merge(sphere((0.03,0.02,0.03),4,0,(-0.83,0.06,-0.05)))
uj.save('croc_jaw')
teeth=Mesh()
for x in np.linspace(-0.78,-0.05,11):
    for zz in (-1,1):
        w=0.16*(1-(-x)/1.0)+0.05
        cone=loft([(x,-0.02,zz*w),(x,-0.09,zz*w)],[0.022,0.002],n=5,caps=False,up=(1,0,0))
        teeth.merge(cone)
teeth.save('croc_teeth')

# ---------------- Harry parts (meters, Y up, facing +X) ----------------
def limb(len_, r0, r1, name, bulge=0.15):
    ys=np.linspace(0,-len_,10)
    rs=[(r0+(r1-r0)*t)*(1+bulge*math.sin(math.pi*t)) for t in np.linspace(0,1,10)]
    m=loft([(0,y,0) for y in ys],rs,n=14,up=(1,0,0)); m.merge(sphere((r0,r0,r0),8,0,(0,0,0))); m.merge(sphere((r1,r1,r1),8,0,(0,-len_,0)))
    m.save(name); return m
limb(0.42,0.085,0.07,'h_thigh')
shin=limb(0.42,0.068,0.05,'h_shin')
boot=loft([(-0.06,-0.4,0),(0.04,-0.42,0),(0.14,-0.44,0)],[0.075,0.07,0.05],[0.06,0.06,0.04],n=12,up=(0,1,0))
boot.merge(loft([(0,-0.3,0),(0,-0.45,0)],[0.07,0.075],n=12,up=(1,0,0))); boot.save('h_boot')
limb(0.3,0.06,0.048,'h_upperarm')
fa=limb(0.28,0.048,0.04,'h_forearm'); 
hand=sphere((0.05,0.06,0.04),8,0,(0.0,-0.33,0)); hand.merge(loft([(0.02,-0.3,0.03),(0.06,-0.36,0.04)],[0.018,0.015],n=6,up=(1,0,0))); hand.save('h_hand')
# torso: tapered from chest to waist, slight forward lean
ys=np.linspace(0,0.58,12)
tr=[0.17+0.05*math.sin(math.pi*min(1,t/0.58*1.2)) for t in ys]
td=[0.11+0.03*math.sin(math.pi*min(1,t/0.58*1.1)) for t in ys]
torso=loft([(0.01*math.sin(y*3),y,0) for y in ys],td,tr,n=18,up=(1,0,0))
torso.save('h_torso')
collar=loft([(0,0.56,0),(0,0.6,0)],[0.1,0.08],[0.14,0.1],n=14,up=(1,0,0)); collar.save('h_collar')
hips=loft([(0,-0.05,0),(0,0.12,0)],[0.12,0.12],[0.18,0.17],n=16,up=(1,0,0)); hips.save('h_hips')
belt=loft([(0,0.1,0),(0,0.16,0)],[0.125,0.125],[0.185,0.185],n=16,up=(1,0,0)); belt.save('h_belt')
head=sphere((0.115,0.135,0.11),14,0.0,(0,0,0)); head.merge(sphere((0.025,0.03,0.022),6,0,(0.11,-0.01,0)))  # nose
head.merge(sphere((0.022,0.035,0.02),6,0,(0,0,0.11))); head.merge(sphere((0.022,0.035,0.02),6,0,(0,0,-0.11)))  # ears
head.merge(loft([(0,-0.1,0),(0,-0.2,0)],[0.05,0.055],n=10,up=(1,0,0)))  # neck
head.save('h_head')
hair=sphere((0.122,0.08,0.118),12,0.15,(-0.015,0.05,0)); hair.save('h_hair')
# pith/explorer hat: brim + domed crown + band
brim=loft([(0,0.0,0),(0,0.012,0)],[0.26,0.24],[0.24,0.22],n=28,up=(1,0,0)); 
crown=sphere((0.135,0.11,0.13),12,0,(0,0.02,0)); V=np.array(crown.v); V[:,1]=np.maximum(V[:,1],0.0); crown.v=list(map(tuple,V)); brim.merge(crown)
brim.save('h_hat')
loft([(0,0.012,0),(0,0.045,0)],[0.138,0.136],[0.133,0.131],n=24,up=(1,0,0)).save('h_hatband')
eyes=sphere((0.018,0.022,0.012),6,0,(0.095,0.02,0.04)); eyes.merge(sphere((0.018,0.022,0.012),6,0,(0.095,0.02,-0.04))); eyes.save('h_eyes')

# ---------------- tree trunk with flared roots ----------------
ys=np.linspace(0,9,22)
def trunk_noise(i,j,a):
    root=max(0,1-ys[i]/1.2)
    return 1+0.08*math.sin(a*5+i*0.4)+root*0.55*max(0,math.sin(a*5))**2+0.03*rng.random()
trunk=loft([(0.15*math.sin(y*0.35),y,0.05*math.cos(y*0.5)) for y in ys],[0.55-0.025*y for y in ys],n=26,noise=trunk_noise,vscale=0.35,up=(1,0,0))
trunk.save('trunk')

# canopy cluster of leaf cards on a dome
can=Mesh()
for k in range(150):
    th=rng.random()*2*math.pi; ph=rng.random()*1.2
    d=np.array([math.cos(th)*math.sin(ph)*1.0, math.cos(ph)*0.6, math.sin(th)*math.sin(ph)*0.8])
    lf=leaf(0.9+rng.random()*0.5,0.35,0.3)
    M=rotm((0,1,0),-th+math.pi/2)@rotm((1,0,0),-0.6+ph*0.9)
    lf.xform(M,t=d*1.4)
    can.merge(lf)
can.save('canopy', double=True)

# fern: fronds radiating
fern=Mesh()
for k in range(9):
    a=2*math.pi*k/9+rng.random()*0.3
    fr=Mesh()
    for s in range(8):
        t=s/8
        for side in (-1,1):
            l=leaf(0.22*(1-t*0.6),0.08,0.02,3); l.xform(rotm((0,1,0),side*1.2),t=(0,0.08*math.sin(t*3),0.1+t*0.8))
            fr.merge(l)
    fr.merge(leaf(0.95,0.04,0.25,6))
    fr.xform(rotm((0,1,0),a)@rotm((1,0,0),-0.55))
    fern.merge(fr)
fern.save('fern', double=True)

# grass tuft: thin curved blades
gr=Mesh()
for k in range(26):
    a=rng.random()*6.28; h=0.25+rng.random()*0.35
    b=leaf(h,0.04,0.12+rng.random()*0.2,4); b.xform(rotm((0,1,0),a)@rotm((1,0,0),-1.35+rng.random()*0.4),t=(rng.random()*0.3-0.15,0,rng.random()*0.3-0.15))
    gr.merge(b)
gr.save('grass', double=True)

# rock
sphere((0.6,0.38,0.5),10,0.35).save('rock')

# vine rope: twisted strands along -Y with leaves (pivot at origin)
vine=Mesh(); L=5.4
for s in range(3):
    pts=[(0.04*math.cos(y*4+s*2.1),-y,0.04*math.sin(y*4+s*2.1)) for y in np.linspace(0,L,40)]
    vine.merge(loft(pts,[0.045]*40,n=7,up=(1,0,0)))
vine.save('vine_rope')
vl=Mesh()
for k in range(22):
    y=0.3+k*(L-0.5)/22; a=k*2.4
    l=leaf(0.28,0.14,0.06,4); l.xform(rotm((0,1,0),a)@rotm((1,0,0),-0.9),t=(0,-y,0)); vl.merge(l)
vl.save('vine_leaves', double=True)

# liana (background hanging curve)
pts=[(0.3*math.sin(t*2.5),-t*3.2,0.15*math.sin(t*4)) for t in np.linspace(0,1,30)]
loft(pts,[0.04]*30,n=6,up=(1,0,0)).save('liana')

# scorpion body (faces -X)
sc=sphere((0.32,0.13,0.2),10,0,(0,0.18,0))
tail=[(0.25+0.3*math.sin(t*2.6),0.2+0.55*math.sin(t*1.7),0) for t in np.linspace(0,1,14)]
sc.merge(loft(tail,[0.07-0.04*t for t in np.linspace(0,1,14)],n=8,up=(0,0,1)))
for x,zz in ((-0.38,0.14),(-0.38,-0.14)):
    sc.merge(loft([(-0.15,0.18,zz*0.6),(-0.3,0.2,zz*1.3),(x-0.08,0.2,zz)],[0.04,0.04,0.035],n=6,up=(0,1,0)))
    sc.merge(sphere((0.09,0.05,0.06),6,0,(x-0.15,0.2,zz)))
for k in range(3):
    for zz in (-1,1):
        sc.merge(loft([(-0.1+k*0.12,0.15,0.12*zz),(-0.1+k*0.12,0.18,0.28*zz),(-0.15+k*0.12,0.0,0.36*zz)],[0.022,0.02,0.015],n=5,up=(1,0,0)))
sc.save('scorpion')
print('done')
