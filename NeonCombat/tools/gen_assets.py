import numpy as np, wave, os
A=os.path.join(os.path.dirname(__file__),"..","project","Assets")
# ---- sky: dusky cyber twilight, bright enough to light the arena through IBL
W,H=1024,512; rng=np.random.default_rng(3)
v=(np.arange(H)+0.5)/H; u=(np.arange(W)+0.5)/W
EL,AZ=np.meshgrid((0.5-v)*np.pi,(u-0.5)*2*np.pi,indexing='ij')
y=np.sin(EL); t=np.clip(y,0,1)[...,None]
img=np.array([0.10,0.05,0.16])*(1-t)**2.5+np.array([0.01,0.02,0.06])*(1-(1-t)**2.5)
img+=np.exp(-np.abs(y)/0.05)[...,None]*np.array([0.35,0.12,0.25])     # magenta horizon band
img+=np.exp(-np.abs(y)/0.2)[...,None]*np.array([0.05,0.10,0.16])
img[y<0]=img[y<0]*0.4+np.array([0.015,0.02,0.03])
n=4000; sy=rng.integers(0,H//2,n); sx=rng.integers(0,W,n)
img[sy,sx]+=(rng.power(0.15,n)*1.2)[:,None]*np.array([0.8,0.9,1.0])
def rgbe(a):
    m=a.max(-1); e=np.ceil(np.log2(np.maximum(m,1e-32))); sc=np.where(m>1e-32,256.0/2**e,0)
    o=np.zeros(a.shape[:2]+(4,),np.uint8); o[...,:3]=np.clip(a*sc[...,None],0,255).astype(np.uint8); o[...,3]=np.where(m>1e-32,e+128,0).astype(np.uint8); return o
with open(os.path.join(A,"Skybox","dusk.hdr"),'wb') as f:
    f.write(b"#?RADIANCE\nFORMAT=32-bit_rle_rgbe\n\n-Y %d +X %d\n"%(H,W)); f.write(rgbe(img.astype(np.float32)).tobytes())
# ---- audio
R=44100; T=lambda d:np.arange(int(R*d))/R
def save(n,x,vol=0.6):
    x=np.clip(x/(np.max(np.abs(x))+1e-9)*vol,-1,1)
    w=wave.open(os.path.join(A,"Audio",n),'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(R)
    w.writeframes((x*32767).astype(np.int16).tobytes()); w.close()
def lp(n,a):
    y=np.zeros_like(n)
    for i in range(1,len(n)): y[i]=y[i-1]+a*(n[i]-y[i-1])
    return y
tt=T(0.45); n=rng.standard_normal(len(tt))
save("fire.wav",(lp(n,0.25)*np.exp(-tt*14)+np.sin(2*np.pi*(90*np.exp(-tt*6))*tt)*np.exp(-tt*9)*1.5),0.7)
tt=T(1.6); n=rng.standard_normal(len(tt))
save("explode.wav",(lp(n,0.05)*np.exp(-tt*2.6)*1.4+np.sin(2*np.pi*(55*np.exp(-tt*1.5))*tt)*np.exp(-tt*2.5)),0.9)
tt=T(0.12); save("bounce.wav",np.sin(2*np.pi*np.cumsum(1400-6000*tt)/R)*np.exp(-tt*30),0.35)
tt=T(0.25); n=rng.standard_normal(len(tt)); save("hitwall.wav",lp(n,0.2)*np.exp(-tt*22),0.4)
tt=T(0.06); save("click.wav",np.sin(2*np.pi*1200*tt)*np.exp(-tt*60),0.35)
s=np.concatenate([np.sin(2*np.pi*f*T(0.16))*np.exp(-T(0.16)*6) for f in (392,523,659,784,1046)]); save("win.wav",s,0.5)
tt=T(0.9); save("start.wav",np.sin(2*np.pi*np.cumsum(220+500*tt)/R)*np.sin(np.pi*tt/0.9),0.4)
tt=T(1.0); n=rng.standard_normal(len(tt)); eng=lp(n,0.02)+0.4*np.sign(np.sin(2*np.pi*38*tt))
save("engine.wav",eng*np.minimum(1,np.minimum(tt,1-tt)/0.02),0.25)
print("assets ok")
