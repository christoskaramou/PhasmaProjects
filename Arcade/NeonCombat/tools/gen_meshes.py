# Procedural mesh generator for NEON COMBAT -> OBJ/MTL, then cooked to .pemesh by PhasmaCook.
import math, random, os, subprocess, sys
OUT = os.path.join(os.path.dirname(__file__), "..", "project", "Assets", "Objects")
SRC = os.path.join(os.path.dirname(__file__), "src"); os.makedirs(SRC, exist_ok=True); os.makedirs(OUT, exist_ok=True)

class Mesh:
    def __init__(s): s.v=[]; s.n=[]; s.f={}  # mat -> list of faces [(vi,ni)...]
    def poly(s, mat, pts, center):
        # pts: list of 3-tuples (convex, planar); orient outward wrt center
        a,b,c = pts[0],pts[1],pts[2]
        u=[b[i]-a[i] for i in range(3)]; w=[c[i]-a[i] for i in range(3)]
        nx=u[1]*w[2]-u[2]*w[1]; ny=u[2]*w[0]-u[0]*w[2]; nz=u[0]*w[1]-u[1]*w[0]
        L=math.sqrt(nx*nx+ny*ny+nz*nz)
        if L<1e-12: return
        nx,ny,nz=nx/L,ny/L,nz/L
        cx=sum(p[0] for p in pts)/len(pts)-center[0]; cy=sum(p[1] for p in pts)/len(pts)-center[1]; cz=sum(p[2] for p in pts)/len(pts)-center[2]
        if nx*cx+ny*cy+nz*cz<0: pts=pts[::-1]; nx,ny,nz=-nx,-ny,-nz
        s.n.append((nx,ny,nz)); ni=len(s.n)
        idx=[]
        for p in pts: s.v.append(p); idx.append(len(s.v))
        s.f.setdefault(mat,[]).append([(i,ni) for i in idx])
    def write(s, name, mats):
        with open(os.path.join(SRC,name+".mtl"),"w") as m:
            for k,(kd,ke) in mats.items():
                m.write(f"newmtl {k}\nKd {kd[0]} {kd[1]} {kd[2]}\nKe {ke[0]} {ke[1]} {ke[2]}\nNs 200\n\n")
        with open(os.path.join(SRC,name+".obj"),"w") as o:
            o.write(f"mtllib {name}.mtl\no {name}\n")
            for p in s.v: o.write("v %.5f %.5f %.5f\n"%p)
            for n in s.n: o.write("vn %.5f %.5f %.5f\n"%n)
            for k in mats:
                if k not in s.f: continue
                o.write(f"usemtl {k}\n")
                for face in s.f[k]:
                    for t in range(1,len(face)-1):
                        tri=[face[0],face[t],face[t+1]]
                        o.write("f "+" ".join(f"{a}//{b}" for a,b in tri)+"\n")
        print(name, len(s.v), "verts", sum(len(x) for x in s.f.values()), "faces")

def cbox(m, mat, cx,cy,cz, hx,hy,hz, c=0.04):
    """chamfered box: 6 faces, 12 edge bevels, 8 corner tris"""
    c=min(c,hx*0.9,hy*0.9,hz*0.9); C=(cx,cy,cz)
    def P(ax,s):
        h=[hx-c,hy-c,hz-c]; h[ax]=[hx,hy,hz][ax]
        return (cx+s[0]*h[0],cy+s[1]*h[1],cz+s[2]*h[2])
    S=[(a,b,d) for a in(-1,1) for b in(-1,1) for d in(-1,1)]
    for ax in range(3):
        for sg in(-1,1):
            cs=[s for s in S if s[ax]==sg]
            o=[1,2] if ax==0 else ([0,2] if ax==1 else [0,1])
            cs.sort(key=lambda s: math.atan2(s[o[1]],s[o[0]]))
            m.poly(mat,[P(ax,s) for s in cs],C)
    for ax in range(3):  # edges along axis ax
        o=[i for i in range(3) if i!=ax]
        for s1 in(-1,1):
            for s2 in(-1,1):
                def sv(t):
                    s=[0,0,0]; s[ax]=t; s[o[0]]=s1; s[o[1]]=s2; return tuple(s)
                m.poly(mat,[P(o[0],sv(-1)),P(o[0],sv(1)),P(o[1],sv(1)),P(o[1],sv(-1))],C)
    for s in S: m.poly(mat,[P(0,s),P(1,s),P(2,s)],C)

def cyl(m, mat, p0, p1, r0, r1=None, seg=16, caps=True):
    r1=r0 if r1 is None else r1
    d=[p1[i]-p0[i] for i in range(3)]; L=math.sqrt(sum(x*x for x in d)); d=[x/L for x in d]
    a=[0,1,0] if abs(d[1])<0.9 else [1,0,0]
    u=[a[1]*d[2]-a[2]*d[1],a[2]*d[0]-a[0]*d[2],a[0]*d[1]-a[1]*d[0]]; ul=math.sqrt(sum(x*x for x in u)); u=[x/ul for x in u]
    w=[d[1]*u[2]-d[2]*u[1],d[2]*u[0]-d[0]*u[2],d[0]*u[1]-d[1]*u[0]]
    C=tuple((p0[i]+p1[i])/2 for i in range(3))
    def ring(p,r):
        return [tuple(p[i]+r*(math.cos(2*math.pi*k/seg)*u[i]+math.sin(2*math.pi*k/seg)*w[i]) for i in range(3)) for k in range(seg)]
    A=ring(p0,r0); B=ring(p1,r1)
    for k in range(seg):
        k2=(k+1)%seg
        # side quads: orient relative to axis point at same height
        mid=tuple((p0[i]+p1[i])/2 for i in range(3))
        m.poly(mat,[A[k],A[k2],B[k2],B[k]],mid)
    if caps:
        m.poly(mat,A,C); m.poly(mat,B,C)

def prism(m, mat, prof, z0, z1, plane="xy"):
    """extrude convex 2D profile (x,y) along z from z0..z1"""
    cx=sum(p[0] for p in prof)/len(prof); cy=sum(p[1] for p in prof)/len(prof); C=(cx,cy,(z0+z1)/2)
    A=[(x,y,z0) for x,y in prof]; B=[(x,y,z1) for x,y in prof]
    n=len(prof)
    for k in range(n):
        k2=(k+1)%n; m.poly(mat,[A[k],A[k2],B[k2],B[k]],C)
    m.poly(mat,A,C); m.poly(mat,B,C)

def ngon_frustum(m, mat, cx,cz,y0,y1,r0,r1,n,rot=0.0):
    A=[(cx+r0*math.cos(rot+2*math.pi*k/n),y0,cz+r0*math.sin(rot+2*math.pi*k/n)) for k in range(n)]
    B=[(cx+r1*math.cos(rot+2*math.pi*k/n),y1,cz+r1*math.sin(rot+2*math.pi*k/n)) for k in range(n)]
    C=(cx,(y0+y1)/2,cz)
    for k in range(n):
        k2=(k+1)%n; m.poly(mat,[A[k],A[k2],B[k2],B[k]],C)
    m.poly(mat,A,C); m.poly(mat,B,C)

def stadium(r, x0, x1, yc, seg=8):
    pts=[]
    for k in range(seg+1):
        a=-math.pi/2+math.pi*k/seg; pts.append((x1+r*math.cos(a), yc+r*math.sin(a)))
    for k in range(seg+1):
        a=math.pi/2+math.pi*k/seg; pts.append((x0+r*math.cos(a), yc+r*math.sin(a)))
    return pts

# ------------------------------------------------------------------ TANK (forward = +X, up = +Y)
def tank():
    m=Mesh()
    # hull: sloped glacis side profile
    prof=[(-0.56,0.16),(0.44,0.16),(0.62,0.27),(0.50,0.40),(-0.50,0.42),(-0.60,0.30)]
    prism(m,"Body",prof,-0.27,0.27)
    # engine deck + grille slats
    cbox(m,"Body",-0.36,0.44,0,0.14,0.025,0.22,0.015)
    for i in range(5): cbox(m,"Dark",-0.46+i*0.05,0.47,0,0.012,0.008,0.18,0.004)
    # tracks (stadium extrusions) + guards + wheels + cleats
    for sz in(-1,1):
        z=sz*0.37
        prism(m,"Dark",stadium(0.13,-0.48,0.48,0.15,10),z-0.1,z+0.1)
        cbox(m,"Body",0.0,0.30,z,0.60,0.018,0.12,0.012)            # fender
        cbox(m,"Body",0.0,0.22,z+sz*0.115,0.52,0.06,0.012,0.008)    # side skirt
        for i in range(5):
            x=-0.38+i*0.19
            cyl(m,"Metal",(x,0.13,z+sz*0.095),(x,0.13,z+sz*0.125),0.085,0.07,14)
            cyl(m,"Glow",(x,0.13,z+sz*0.125),(x,0.13,z+sz*0.13),0.03,0.03,8)
        cyl(m,"Metal",(0.52,0.16,z+sz*0.09),(0.52,0.16,z+sz*0.12),0.08,0.06,10)  # sprocket
        cyl(m,"Metal",(-0.52,0.16,z+sz*0.09),(-0.52,0.16,z+sz*0.12),0.075,0.06,10)
        for i in range(16):
            x=-0.48+i*0.064; cbox(m,"Tread",x,0.01,z,0.016,0.012,0.1,0.004)
            cbox(m,"Tread",x,0.285,z,0.016,0.008,0.1,0.004)
        # glow running strip
        cbox(m,"Glow",0.0,0.315,z+sz*0.122,0.5,0.008,0.006,0.003)
    # turret: hexagonal frustum + bustle + mantlet
    ngon_frustum(m,"Body",-0.06,0,0.42,0.58,0.30,0.235,6,math.pi/6)
    cbox(m,"Body",-0.30,0.50,0,0.08,0.06,0.16,0.03)
    cbox(m,"Metal",0.22,0.50,0,0.06,0.06,0.1,0.025)
    ngon_frustum(m,"Glow",-0.06,0,0.575,0.59,0.24,0.235,6,math.pi/6)   # glowing turret ring top band
    ngon_frustum(m,"Body",-0.06,0,0.585,0.6,0.22,0.215,6,math.pi/6)
    # barrel with bore evacuator + muzzle brake
    cyl(m,"Metal",(0.26,0.50,0),(0.92,0.50,0),0.042,0.036,16)
    cyl(m,"Metal",(0.52,0.50,0),(0.62,0.50,0),0.058,0.058,16)
    cyl(m,"Metal",(0.88,0.50,0),(1.0,0.50,0),0.058,0.055,16)
    cyl(m,"Glow",(0.995,0.50,0),(1.005,0.50,0),0.03,0.03,12)
    # commander cupola + hatch + periscopes + antenna + coax MG
    cyl(m,"Body",(-0.12,0.60,-0.1),(-0.12,0.66,-0.1),0.09,0.08,14)
    cyl(m,"Metal",(-0.12,0.66,-0.1),(-0.12,0.68,-0.1),0.075,0.06,14)
    cbox(m,"Glow",-0.03,0.64,-0.1,0.012,0.015,0.035,0.004)
    cyl(m,"Metal",(-0.12,0.68,-0.1),(0.08,0.70,-0.1),0.012,0.012,6)
    cyl(m,"Metal",(-0.3,0.56,0.12),(-0.3,1.05,0.12),0.008,0.004,5)
    cyl(m,"Glow",(-0.3,1.04,0.12),(-0.3,1.07,0.12),0.016,0.016,6)
    # headlights / tail lights
    for sz in(-1,1):
        cbox(m,"Head",0.56,0.33,sz*0.2,0.02,0.025,0.04,0.008)
        cbox(m,"Tail",-0.61,0.34,sz*0.2,0.012,0.02,0.05,0.006)
    m.write("tank",{"Body":((0.3,0.4,0.3),(0,0,0)),"Dark":((0.04,0.04,0.05),(0,0,0)),"Tread":((0.08,0.08,0.08),(0,0,0)),
        "Metal":((0.35,0.36,0.4),(0,0,0)),"Glow":((1,1,1),(1,1,1)),"Head":((1,1,0.9),(1,1,0.9)),"Tail":((1,0.1,0.05),(1,0.1,0.05))})

def shell():
    m=Mesh()
    cyl(m,"Core",(-0.14,0,0),(0.08,0,0),0.045,0.045,12)
    cyl(m,"Core",(0.08,0,0),(0.2,0,0),0.045,0.005,12)
    m.write("shell",{"Core":((1,1,1),(1,1,1))})

def debris():
    random.seed(7)
    for k in range(3):
        m=Mesh()
        # jittered octahedron-ish chunk made from chamfered boxes
        for j in range(3):
            cbox(m,"Chunk",random.uniform(-.05,.05),random.uniform(-.05,.05),random.uniform(-.05,.05),
                 random.uniform(.05,.12),random.uniform(.03,.08),random.uniform(.05,.1),0.02)
        m.write(f"debris{k}",{"Chunk":((0.2,0.2,0.22),(0,0,0))})

# ------------------------------------------------------------------ ARENAS
CELL=1.5
ARENAS={
"classic":[
"########################",
"#......................#",
"#......................#",
"#...##............##...#",
"#....#............#....#",
"#....#....####....#....#",
"#.........#..#.........#",
"#.........#..#.........#",
"#....#....####....#....#",
"#....#............#....#",
"#...##............##...#",
"#......................#",
"#......................#",
"########################"],
"maze":[
"########################",
"#..........##..........#",
"#..###............###..#",
"#....#....#..#....#....#",
"#....#....#..#....#....#",
"#..........................#"[:23]+"#",
"###....##......##....###",
"###....##......##....###",
"#......................#",
"#....#....#..#....#....#",
"#....#....#..#....#....#",
"#..###............###..#",
"#..........##..........#",
"########################"],
"pillars":[
"########################",
"#......................#",
"#..##....##..##....##..#",
"#..##....##..##....##..#",
"#......................#",
"#......#........#......#",
"#.....###......###.....#",
"#......#........#......#",
"#......................#",
"#..##....##..##....##..#",
"#..##....##..##....##..#",
"#......................#",
"#......................#",
"########################"],
}
# pillars arena is 14 rows; make it symmetric by trimming the extra blank row
ARENAS["pillars"]=ARENAS["pillars"][:12]+ARENAS["pillars"][13:]
ARENAS["pillars"].insert(6,"#......................#")

def cell_xy(c,r,cols,rows):
    return ((c-(cols-1)/2)*CELL, (r-(rows-1)/2)*CELL)

def runs_of(rows):
    R=len(rows); Cn=len(rows[0]); out=[]
    for r,row in enumerate(rows):
        c=0
        while c<Cn:
            if row[c]=='#':
                c0=c
                while c<Cn and row[c]=='#': c+=1
                out.append((r,c0,c-1))
            else: c+=1
    return out

def arena_mesh(name, rows):
    m=Mesh(); R=len(rows); Cn=len(rows[0]); H=1.0
    boxes=[]
    for r,c0,c1 in runs_of(rows):
        x0,z=cell_xy(c0,r,Cn,R); x1,_=cell_xy(c1,r,Cn,R)
        cx=(x0+x1)/2; hx=(x1-x0)/2+CELL/2
        boxes.append((cx,z,hx,CELL/2))
        cbox(m,"Wall",cx,H*0.5,z,hx-0.03,H*0.5,CELL*0.5-0.03,0.08)
        cbox(m,"WallTop",cx,H+0.025,z,hx-0.16,0.025,CELL*0.5-0.16,0.02)
        # panel grooves between cells (dark trim insets on the top)
        for c in range(c0,c1):
            gx,_=cell_xy(c,r,Cn,R); gx+=CELL/2
            cbox(m,"Trim",gx,H+0.03,z,0.03,0.03,CELL*0.5-0.1,0.01)
        # glowing seams on exposed long sides (N/S), split where a neighbour wall touches
        for dr in(-1,1):
            rr=r+dr; c=c0
            while c<=c1:
                if 0<=rr<R and rows[rr][c]!='#':
                    s0=c
                    while c<=c1 and rows[rr][c]!='#': c+=1
                    a,_=cell_xy(s0,r,Cn,R); b,_=cell_xy(c-1,r,Cn,R)
                    cbox(m,"Glow",(a+b)/2,H*0.82,z+dr*(CELL*0.5-0.025),(b-a)/2+CELL*0.5-0.1,0.035,0.012,0.008)
                    cbox(m,"Trim",(a+b)/2,0.06,z+dr*(CELL*0.5-0.02),(b-a)/2+CELL*0.5-0.05,0.06,0.02,0.01)
                else: c+=1
        for dc,cc in((-1,c0-1),(1,c1+1)):
            if 0<=cc<Cn and rows[r][cc]!='#':
                xe,_=cell_xy(c0 if dc<0 else c1,r,Cn,R)
                cbox(m,"Glow",xe+dc*(CELL*0.5-0.025),H*0.82,z,0.012,0.035,CELL*0.5-0.12,0.008)
    m.write("arena_"+name,{"Wall":((0.12,0.13,0.17),(0,0,0)),"WallTop":((0.2,0.22,0.28),(0,0,0)),"Glow":((1,1,1),(1,1,1)),"Trim":((0.05,0.05,0.06),(0,0,0))})
    return boxes

def tile(m,mat,x,y,z,h,b):
    """floor tile: top quad + 4 bevel quads (no hidden faces)"""
    C=(x,y-1,z); t=y; lo=y-b
    A=[(x-h+b,t,z-h+b),(x+h-b,t,z-h+b),(x+h-b,t,z+h-b),(x-h+b,t,z+h-b)]
    B=[(x-h,lo,z-h),(x+h,lo,z-h),(x+h,lo,z+h),(x-h,lo,z+h)]
    m.poly(mat,A,C)
    for k in range(4): m.poly(mat,[A[k],A[(k+1)%4],B[(k+1)%4],B[k]],C)

def floor_mesh(rows):
    rows=["."*len(rows[0])]*len(rows)
    m=Mesh(); R=len(rows); Cn=len(rows[0])
    for r in range(R):
        for c in range(Cn):
            x,z=cell_xy(c,r,Cn,R)
            mat="Floor" if (r+c)%2==0 else "Floor2"
            if rows[r][c]=='#': continue
            tile(m,mat,x,0.0,z,CELL*0.5-0.03,0.03)
            if (r*7+c*3)%5==0: tile(m,"Detail",x,0.006,z,CELL*0.18,0.004)
    W=Cn*CELL/2; D=R*CELL/2
    cbox(m,"Grid",0,-0.09,0,W,0.03,D,0.01)              # glowing sub-plane visible through seams
    cbox(m,"Base",0,-0.4,0,W+6,0.25,D+6,0.1)            # outer plinth
    for sx in(-1,1):
        cbox(m,"Edge",sx*(W+0.3),0.0,0,0.06,0.04,D+0.3,0.02)
        cbox(m,"Edge",0,0.0,sx*(D+0.3),W+0.3,0.04,0.06,0.02)
    m.write("floor",{"Floor":((0.06,0.065,0.08),(0,0,0)),"Floor2":((0.075,0.08,0.1),(0,0,0)),"Detail":((0.12,0.13,0.16),(0,0,0)),
        "Grid":((0.2,0.6,1),(0.2,0.6,1)),"Base":((0.02,0.02,0.03),(0,0,0)),"Edge":((1,1,1),(1,1,1))})

tank(); shell(); debris(); floor_mesh(ARENAS["classic"])
lua=["-- generated by tools/gen_meshes.py","return {","  cell = %g,"%CELL,"  arenas = {"]
for name,rows in ARENAS.items():
    assert len(rows)==14 and all(len(r)==24 for r in rows),(name,[len(r) for r in rows])
    b=arena_mesh(name,rows)
    lua.append('    { name = "%s", rows = {%s}, boxes = {'%(name,",".join('"%s"'%r for r in rows)))
    for x,z,hx,hz in b: lua.append("      {%g, %g, %g, %g},"%(x,z,hx,hz))
    lua.append("    } },")
lua+=["  },","  w = %g, d = %g,"%(24*CELL/2,14*CELL/2),"}"]
open(os.path.join(os.path.dirname(__file__),"..","project","Assets","Scripts","arenas.lua"),"w").write("\n".join(lua)+"\n")

cook=os.path.join(os.path.dirname(__file__),"..","bin","PhasmaCook")
for f in sorted(os.listdir(SRC)):
    if f.endswith(".obj"):
        r=subprocess.run([cook,os.path.join(SRC,f),os.path.join(OUT,f[:-4]+".pemesh")],capture_output=True,text=True,timeout=120,cwd=os.path.dirname(cook))
        print("cook",f,r.returncode,(r.stdout+r.stderr).strip()[-200:])

# ------------------------------------------------------------------ scene (sources + nodes); engine can't load .pemesh from Lua without assimp
import json
SOURCES=[("TankA","tank",7),("TankB","tank",7),("ShellA","shell",1),("ShellB","shell",1),
         ("Debris0","debris0",1),("Debris1","debris1",1),("Debris2","debris2",1),("Floor","floor",6),
         ("Arena_classic","arena_classic",4),("Arena_maze","arena_maze",4),("Arena_pillars","arena_pillars",4)]
sources=[]; meshes=[]; nodes=[]
nodes.append({"name":"Camera_0","parent":-1,"local_matrix":[1,0,0,0,0,1,0,0,0,0,1,0,0,24,18,1],"component_flags":8,
  "camera":{"projection":"perspective","fovx":1.15,"near_plane":0.1,"far_plane":500.0,"speed":0.0,"euler":[-0.95,3.14159,0.0]}})
nodes.append({"name":"Sun","parent":-1,"local_matrix":[0.8,0,0.6,0, 0.36,0.8,-0.48,0, -0.48,0.6,0.64,0, 0,30,0,1],"component_flags":2,
  "light":{"type":"directional","color":[0.8,0.85,1.0,6.0]}})
for si,(nm,f,cnt) in enumerate(SOURCES):
    sources.append({"path":"../Objects/%s.pemesh"%f})
    refs=[]
    for k in range(cnt):
        refs.append(len(meshes)); meshes.append({"source":si,"source_mesh":k,"instanced":True})
    nodes.append({"name":nm,"parent":-1,"local_matrix":[1,0,0,0,0,1,0,0,0,0,1,0,0,-50,0,1],"mesh_refs":refs})
sc={"sources":sources,"meshes":meshes,"nodes":nodes,"lights":[],
    "cameras":[{"name":"Camera_0","position":[0,24,18],"euler":[-0.95,3.14159,0],"fovx":1.15,"projection":"perspective","near_plane":0.1,"far_plane":500.0,"speed":0.0,"node_index":0}],
    "active_camera":0,"scene_scripts":{"on_play":["Assets/Scripts/game.lua"]}}
json.dump(sc,open(os.path.join(os.path.dirname(__file__),"..","project","Assets","Scenes","main.pescene"),"w"),indent=1)
print("scene written")
