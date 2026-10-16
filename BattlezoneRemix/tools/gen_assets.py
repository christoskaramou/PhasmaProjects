# Desert/volcanic wasteland HDR sky, ground texture, WAV sfx for Battlezone Remix
import numpy as np, os, wave
from PIL import Image
A = os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'project', 'Assets')
for sub in ('Skybox','Textures','Audio','Save'):
    os.makedirs(f'{A}/{sub}', exist_ok=True)
rng = np.random.default_rng(42)

def fbm_tile(h, w, seed=0):
    r = np.random.default_rng(seed)
    fy = np.fft.fftfreq(h)[:, None] * h; fx = np.fft.fftfreq(w)[None, :] * w
    f = np.sqrt(fx**2 + fy**2); f[0,0] = 1
    spec = (r.normal(size=(h,w)) + 1j*r.normal(size=(h,w))) / f**1.7
    n = np.real(np.fft.ifft2(spec)); n = (n-n.min())/(n.max()-n.min()); return n

# ---- HDR sky: warm desert dusk / volcanic haze (equirect)
W, H = 512, 256
v = (np.arange(H)+.5)/H; u = (np.arange(W)+.5)/W
EL, AZ = np.meshgrid((0.5-v)*np.pi, (u-0.5)*2*np.pi, indexing='ij')
x = np.cos(EL)*np.cos(AZ); z = np.cos(EL)*np.sin(AZ); y = np.sin(EL)
# base: deep indigo zenith -> rusty horizon
t = np.clip(0.5 - y*0.5, 0, 1)
img = np.zeros((H,W,3))
img += (1-t)[...,None] * np.array([0.02, 0.04, 0.12])
img += t[...,None] * np.array([0.35, 0.18, 0.08])
img += (t**2)[...,None] * np.array([0.55, 0.25, 0.06])
# sun disc low on horizon
sun_dir = np.array([0.55, 0.12, 0.82]); sun_dir /= np.linalg.norm(sun_dir)
ang = np.arccos(np.clip(x*sun_dir[0]+y*sun_dir[1]+z*sun_dir[2], -1, 1))
img += np.exp(-(ang/0.08)**2)[...,None] * np.array([8.0, 5.5, 2.0])
img += np.exp(-(ang/0.35)**2)[...,None] * np.array([0.9, 0.45, 0.12])
img += np.exp(-(ang/0.9)**2)[...,None] * np.array([0.15, 0.06, 0.02])
# opposite cool fill
fill = np.array([-0.7, 0.3, -0.4]); fill /= np.linalg.norm(fill)
ang2 = np.arccos(np.clip(x*fill[0]+y*fill[1]+z*fill[2], -1, 1))
img += np.exp(-(ang2/0.7)**2)[...,None] * np.array([0.04, 0.08, 0.18])
def rgbe(a):
    m = a.max(-1); e = np.ceil(np.log2(np.maximum(m, 1e-32))); sc = np.where(m>1e-32, 256.0/2**e, 0)
    out = np.zeros(a.shape[:2]+(4,), np.uint8)
    out[...,:3] = np.clip(a*sc[...,None],0,255).astype(np.uint8)
    out[...,3] = np.where(m>1e-32, e+128, 0).astype(np.uint8); return out
with open(f'{A}/Skybox/wasteland.hdr','wb') as f:
    f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n"%(H,W))
    f.write(rgbe(img.astype(np.float32)).tobytes())
print('sky ok')

# ---- ground albedo: cracked dusty soil
TH,TW = 1024,1024
n1 = fbm_tile(TH,TW,1); n2 = fbm_tile(TH,TW,2); n3 = fbm_tile(TH,TW,3)
soil = np.array([0.42, 0.32, 0.18]) * (0.55 + 0.45*n1)[...,None]
soil += np.array([0.25, 0.18, 0.10]) * (n2**1.5)[...,None]
cracks = (n3 > 0.72).astype(float)
soil *= (1 - 0.35*cracks)[...,None]
soil += np.array([0.55, 0.4, 0.22]) * ((n1*n2)**2)[...,None]*0.3
# sparse gravel flecks
for _ in range(8000):
    yy,xx = rng.integers(0,TH), rng.integers(0,TW)
    soil[yy,xx] = np.clip(soil[yy,xx] + rng.uniform(-0.05,0.12,3), 0, 1)
Image.fromarray((np.clip(soil,0,1)*255).astype(np.uint8)).save(f'{A}/Textures/ground.png')
# mountain rock texture
rock = np.array([0.22, 0.2, 0.18]) * (0.6+0.5*n2)[...,None]
rock += np.array([0.35, 0.22, 0.12]) * ((n1>0.6)*n3)[...,None]
Image.fromarray((np.clip(rock,0,1)*255).astype(np.uint8)).save(f'{A}/Textures/rock.png')
# soft dust / smoke particle sprite
PS=128; yy,xx = np.mgrid[0:PS,0:PS]; cx=cy=PS/2-0.5
rr = np.sqrt((xx-cx)**2+(yy-cy)**2)/(PS*0.48)
dust = np.clip(1-rr,0,1)**2; dust = (dust*255).astype(np.uint8)
Image.fromarray(np.stack([dust,dust,dust,dust],-1)).save(f'{A}/Textures/dust.png')
print('textures ok')

# ---- sfx
SR=44100
def save(name,s,vol=0.8):
    s=np.asarray(s,float); s=s/(np.abs(s).max()+1e-9)*vol
    d=(np.clip(s,-1,1)*32000).astype(np.int16)
    with wave.open(f'{A}/Audio/{name}.wav','wb') as w:
        w.setnchannels(1); w.setsampwidth(2); w.setframerate(SR); w.writeframes(d.tobytes())
def t(d): return np.arange(int(SR*d))/SR
def env(n,a=0.005,r=None):
    e=np.ones(n); ai=max(1,int(a*SR)); e[:ai]=np.linspace(0,1,ai)
    if r: ri=min(n,int(r*SR)); e[-ri:]*=np.linspace(1,0,ri)**2
    return e
def noise(d): return rng.uniform(-1,1,int(SR*d))
def lp(x,a=0.15):
    y=np.zeros_like(x); acc=0
    for i,v in enumerate(x): acc+=a*(v-acc); y[i]=acc
    return y
def sweep(f0,f1,d,wave=np.sin):
    tt=t(d); f=f0*(f1/f0)**(tt/d); return wave(2*np.pi*np.cumsum(f)/SR)
# cannon
d=0.35; s=lp(noise(d),0.25)*np.exp(-t(d)*10)+sweep(180,40,d)*np.exp(-t(d)*8)*0.7; save('shoot',s,0.7)
# shell hit / explosion
d=0.9; s=lp(noise(d),0.12)*np.exp(-t(d)*4)+sweep(220,30,d)*np.exp(-t(d)*3.5)*0.9; save('boom',s,0.85)
d=0.45; s=lp(noise(d),0.2)*np.exp(-t(d)*8)+sweep(400,60,d)*0.5*np.exp(-t(d)*7); save('hit',s,0.65)
# enemy death
d=1.2; s=lp(noise(d),0.1)*np.exp(-t(d)*2.5)+sweep(300,25,d)*0.7*np.exp(-t(d)*2.8); save('death',s,0.9)
# player death
d=1.5; s=lp(noise(d),0.08)*np.exp(-t(d)*2)+sweep(150,20,d)*0.8*np.exp(-t(d)*2); save('playerdie',s,0.9)
# missile launch / whoosh
d=0.7; s=sweep(80,600,d)*np.exp(-t(d)*2)*0.5+lp(noise(d),0.3)*np.exp(-t(d)*3)*0.4; save('missile',s,0.55)
# saucer hum
d=1.8; tt=t(d); s=(np.sin(2*np.pi*(90+20*np.sin(2*np.pi*3*tt))*tt)+0.4*np.sin(2*np.pi*180*tt))*env(len(tt),0.1,0.3); save('saucer',s,0.4)
# radar blip
save('blip', np.sin(2*np.pi*1400*t(0.05))*np.exp(-t(0.05)*50), 0.35)
save('click', np.sin(2*np.pi*1100*t(0.035))*np.exp(-t(0.035)*55), 0.4)
# engine idle rumble
d=0.5; s=lp(noise(d),0.08)*0.5+np.sin(2*np.pi*55*t(d))*0.3; save('engine',s*env(len(s),0.05,0.05),0.25)
# game start / over
def sq(ph): return np.sign(np.sin(ph))
def tune(mel):
    out=[]
    for f_,dd in mel:
        tt=t(dd)
        out.append((0.5*sq(2*np.pi*f_*tt)+0.4*np.sin(2*np.pi*f_*tt))*env(len(tt),0.005,dd*0.4) if f_ else np.zeros(len(tt)))
    return np.concatenate(out)
save('start', tune([(196,.15),(247,.15),(294,.15),(392,.35),(294,.12),(392,.5)]), 0.55)
save('gameover', tune([(196,.35),(185,.35),(175,.35),(165,.9)]), 0.5)
save('score', np.sin(2*np.pi*880*t(0.08))*np.exp(-t(0.08)*25)+np.sin(2*np.pi*1320*t(0.08))*0.4*np.exp(-t(0.08)*30), 0.4)
print('sfx ok')
