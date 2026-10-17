# Generates procedural textures (PNG) and sound effects (WAV) for the Pitfall remake.
import numpy as np, wave, os
from PIL import Image, ImageFilter
R=os.path.join(os.path.dirname(__file__),'..','project','Assets')
T=os.path.join(R,'Textures'); A=os.path.join(R,'Audio'); os.makedirs(T,exist_ok=True); os.makedirs(A,exist_ok=True)
rng=np.random.default_rng(7)
def noise(n,s,oct=4):
    out=np.zeros((n,n))
    for o in range(oct):
        f=s*2**o; g=rng.random((f,f))
        img=Image.fromarray((g*255).astype(np.uint8)).resize((n,n),Image.BICUBIC)
        out+=np.asarray(img)/255/2**o
    return out/out.max()
def save(name,arr): Image.fromarray(np.clip(arr,0,255).astype(np.uint8)).save(os.path.join(T,name))
N=256
# bricks
b=np.zeros((N,N,3)); nz=noise(N,8)
for y in range(N):
    row=y//32; off=(row%2)*32
    for x in range(N):
        mort=(y%32<3) or ((x+off)%64<3)
        c=np.array([150,62,40]) if not mort else np.array([70,60,50])
        b[y,x]=c*(0.7+0.5*nz[y,x])
save('brick.png',b)
# bark: vertical streaks
nz=noise(N,4); st=np.asarray(Image.fromarray((rng.random((N,16))*255).astype(np.uint8)).resize((N,N),Image.BICUBIC))/255
v=0.5*st+0.5*nz
save('bark.png',np.stack([90*v+30,60*v+20,35*v+12],-1))
# dirt
nz=noise(N,6); save('dirt.png',np.stack([120*nz+50,80*nz+35,45*nz+20],-1))
# grass/jungle floor top
nz=noise(N,16); g2=noise(N,4); save('grass.png',np.stack([60*nz+30*g2+20,140*nz+40*g2+40,30*nz+15],-1))
# leaves
nz=noise(N,12); save('leaves.png',np.stack([30*nz+10,130*nz+30,40*nz+10],-1))
# tar & water
nz=noise(N,5); save('tar.png',np.stack([30*nz+8,22*nz+6,18*nz+6],-1))
save('water.png',np.stack([20*nz+10,90*nz+50,80*nz+50],-1))
# HUD logo backdrop gradient
g=np.linspace(0,1,64)[:,None]*np.ones((64,512))
save('hudbar.png',np.stack([10+0*g,25+20*g,10+5*g],-1))
# --- audio ---
SR=22050
def wav(name,sig):
    sig=np.clip(sig,-1,1); d=(sig*32000).astype(np.int16)
    with wave.open(os.path.join(A,name),'wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(d.tobytes())
def t(d): return np.arange(int(SR*d))/SR
def env(x,a=0.005,r=None):
    e=np.ones_like(x); n=len(x); ai=max(1,int(a*SR)); e[:ai]=np.linspace(0,1,ai)
    e*=np.linspace(1,0,n)**(r or 1.5); return e
x=t(0.18); wav('jump.wav',0.5*np.sign(np.sin(2*np.pi*np.cumsum(np.linspace(300,900,len(x)))/SR))*env(x))
x=t(0.6); f=np.where(x<0.15,1046,np.where(x<0.3,1318,1568)); wav('treasure.wav',0.4*np.sin(2*np.pi*np.cumsum(f)/SR)*env(x,r=0.8)+0.2*np.sin(4*np.pi*np.cumsum(f)/SR)*env(x))
x=t(1.2); wav('death.wav',0.45*np.sign(np.sin(2*np.pi*np.cumsum(np.linspace(600,80,len(x)))/SR))*env(x,r=0.7))
x=t(0.12); wav('thud.wav',0.6*(rng.random(len(x))*2-1)*env(x,r=3)+0.5*np.sin(2*np.pi*90*x)*env(x))
# tarzan yell: warbling vowel
x=t(1.1); f0=np.where(x<0.25,440,np.where(x<0.6,660,520))+60*np.sign(np.sin(2*np.pi*9*x))
ph=2*np.pi*np.cumsum(f0)/SR; wav('yell.wav',0.35*(np.sin(ph)+0.5*np.sin(2*ph)+0.25*np.sin(3*ph))*env(x,0.02,0.6))
x=t(0.08); wav('step.wav',0.25*(rng.random(len(x))*2-1)*env(x,r=4))
x=t(0.5); wav('splash.wav',0.5*(rng.random(len(x))*2-1)*env(x,r=2)*np.sin(np.pi*x/0.5))
x=t(0.25); wav('select.wav',0.3*np.sin(2*np.pi*np.where(x<0.1,660,990)*x)*env(x))
# jungle ambience loop: filtered noise + bird chirps
x=t(8.0); nzs=np.convolve(rng.random(len(x))*2-1,np.ones(40)/40,'same')*0.25
birds=np.zeros_like(x)
for k in range(10):
    s=int(rng.random()*(len(x)-SR)); d=t(0.15)
    birds[s:s+len(d)]+=0.15*np.sin(2*np.pi*np.cumsum(2200+900*np.sin(2*np.pi*12*d))/SR)*env(d)
amb=nzs+birds; amb[:2000]*=np.linspace(0,1,2000); amb[-2000:]*=np.linspace(1,0,2000)
wav('jungle.wav',amb)
print('ok')

# --- painted sky backdrop with layered hills (replaces 3D hill meshes; avoids silhouette artifacts) ---
Wd,Hd=1024,512
y=np.linspace(0,1,Hd)[:,None]; x=np.linspace(0,1,Wd)[None,:]
top=np.array([70,140,150]); mid=np.array([235,170,110]); 
sky=np.where(y[...,None]<0.55, top+(mid-top)*(y[...,None]/0.55), mid)*np.ones((Hd,Wd,1))
sun=np.exp(-(((x-0.62)*2.2)**2+((y-0.5)*4)**2))[...,None]
sky=sky+sun*np.array([60,45,20])
def ridge(base,amp,freq,seed):
    r=np.random.default_rng(seed); ph=r.random(5)*6.28
    h=base+sum(amp/(k+1)*np.sin(x[0]*freq*(k+1)*6.28+ph[k]) for k in range(5))
    return h
for base,amp,freq,col,seed in [(0.55,0.06,1.5,(120,150,140),1),(0.65,0.05,2.5,(70,105,95),2),(0.75,0.04,4,(40,70,55),3)]:
    h=ridge(base,amp,freq,seed); mask=(y>h[None,:])
    haze=np.clip((y-h[None,:])*3,0,1)[...,None]
    c=np.array(col)*(1-0.3*haze)+np.array(mid)*0.0
    sky=np.where(mask[...,None],c,sky)
save('sky.png',sky)
# soft vertical gradient for light shafts
g=np.linspace(1,0,256)[:,None]**1.5*np.ones((256,64)); edge=np.sin(np.linspace(0,np.pi,64))[None,:]
a=(g*edge*255)
save('shaft.png',np.stack([a,a*0.9,a*0.7],-1))
print('sky ok')

# croc scales: voronoi-ish cells
N=256; pts=rng.random((90,2))*N
yy,xx=np.mgrid[0:N,0:N]
d=np.full((N,N),1e9); d2=np.full((N,N),1e9)
for px,py in pts:
    for ox in (-N,0,N):
        for oy in (-N,0,N):
            dd=np.hypot(xx-px-ox,yy-py-oy); m=dd<d; d2=np.where(m,d,np.minimum(d2,dd)); d=np.where(m,dd,d)
edge=np.clip((d2-d)/6,0,1)
nz=noise(N,8)
save('scales.png',np.stack([(40+60*edge)*(0.8+0.4*nz),(70+90*edge)*(0.8+0.4*nz),(25+30*edge)*(0.8+0.4*nz)],-1))
# fabric for Harry's shirt
f=noise(N,32)*0.3+0.7
save('cloth.png',np.stack([f*255,f*255,f*255],-1))
print('scales ok')
