"""Original, periodic sewer PBR maps. Python 3 + NumPy + Pillow.

Every image is generated mathematically, without external source material.
Normal maps use the glTF/OpenGL +Y convention. ORM = AO, roughness, metalness.
"""
from pathlib import Path
import json
import numpy as np
from PIL import Image, ImageDraw, ImageFont

OUT = Path(__file__).resolve().parents[1] / "Textures" / "Sewer"
OUT.mkdir(parents=True, exist_ok=True)
N = 512
rng = np.random.default_rng(77361)
y,x = np.mgrid[0:N,0:N]

def noise(scale, seed):
    """Band-limited periodic noise in [roughly -1,1], seamless at wrap."""
    r=np.random.default_rng(seed).normal(size=(N,N))
    fy=np.fft.fftfreq(N)[:,None]
    fx=np.fft.fftfreq(N)[None,:]
    filt=np.exp(-(fx*fx+fy*fy)*(scale*scale))
    q=np.fft.ifft2(np.fft.fft2(r)*filt).real
    return q/(q.std()*3+1e-9)

def rgb(c):
    return np.broadcast_to(np.array(c,dtype=float),(N,N,3)).copy()

def smooth(a, b, v):
    t=np.clip((v-a)/(b-a),0,1)
    return t*t*(3-2*t)

def save_set(name, color, height, rough, metal, ao, strength=3):
    color=np.clip(color,0,255).astype(np.uint8)
    Image.fromarray(color).save(OUT/f"{name}_basecolor.jpg", quality=88, subsampling=0, optimize=True)
    # Central differences cross wrap; generated normals therefore tile.
    dx=(np.roll(height,-1,axis=1)-np.roll(height,1,axis=1))*strength
    dy=(np.roll(height,-1,axis=0)-np.roll(height,1,axis=0))*strength
    norm=np.dstack([-dx,dy,np.ones_like(height)])
    norm/=np.linalg.norm(norm,axis=2,keepdims=True)
    normal=np.clip(norm*127.5+127.5,0,255).astype(np.uint8)
    # Two-value steps save PNG space while limiting tangent quantization to <1 degree.
    normal[:,:,:2]=np.minimum((normal[:,:,:2].astype(np.uint16)+1)//2*2,255).astype(np.uint8)
    normal_image=Image.fromarray(normal)
    if name == "concrete":
        normal_image=normal_image.resize((256,256),Image.Resampling.BOX)
    normal_image.save(OUT/f"{name}_normal.png",optimize=True)
    orm=np.dstack([np.broadcast_to(ao,(N,N)),np.broadcast_to(rough,(N,N)),np.broadcast_to(metal,(N,N))])
    orm=np.clip(orm*255,0,255).astype(np.uint8)
    orm=np.minimum((orm.astype(np.uint16)+2)//4*4,255).astype(np.uint8)
    Image.fromarray(orm).save(OUT/f"{name}_orm.png",optimize=True)
    for i, channel in enumerate(['occlusion','roughness','metallic']):
        Image.fromarray(orm[:,:,i]).save(OUT/f"{name}_{channel}.png",optimize=True)

# WARM SEWER BRICK: 8 courses horizontally and 24 rows per 2 m repeat.
rows=24
cols=8
row=np.floor(y*rows/N).astype(int)
bx=(x*cols/N+(row%2)*.5)%1
by=(y*rows/N)%1
edge=np.minimum(np.minimum(bx,1-bx)*N/cols,np.minimum(by,1-by)*N/rows)
brick=smooth(.65,2.5,edge)
ids=(np.floor(x*cols/N+(row%2)*.5).astype(int)%cols)+row*cols
variation=np.random.default_rng(123).uniform(-16,18,cols*rows)[ids]
large=noise(55,4)
grain=noise(2.8,5)
pores=noise(6,6)
streak=(.45+.55*np.sin(2*np.pi*(x/N*7+noise(75,25)*.2))) * (noise(130,26)+.45)
stain=np.clip(streak,0,1)*.20
bc=rgb((151,107,78))
bc+=variation[:,:,None]*np.array([1,.74,.52])
bc+=large[:,:,None]*14+grain[:,:,None]*5
bc*=1-stain[:,:,None]
mortar=rgb((99,96,81))+grain[:,:,None]*3
bc=bc*brick[:,:,None]+mortar*(1-brick[:,:,None])
height=brick*(.34+pores*.025+grain*.016)
save_set('brick',bc,height,.79-stain*.7+grain*.025,0,.74+.26*brick,strength=2.9)

# CAST CONCRETE: stains and fine aggregate, no baked directional lighting.
coarse=noise(135,7)
middle=noise(28,8)
fine=noise(3,9)
vertical=noise(100,10)
stain=smooth(-.1,.65,coarse*.75+middle*.25)
bc=rgb((155,148,130))+middle[:,:,None]*12+fine[:,:,None]*4
bc-=stain[:,:,None]*np.array((25,27,22))
# Few embedded pores, sufficiently subtle for the close views.
pits=smooth(.30,.65,noise(4,28))
bc-=pits[:,:,None]*10
height=middle*.035+fine*.016-pits*.035
save_set('concrete',bc,height,.80-stain*.18+fine*.025,0,.96-pits*.1,strength=2.5)

# OLD TEAL PAINTED STEEL: flaked coating, oxide and sparse exposed edges.
coarse=noise(55,11)
mid=noise(12,12)
fine=noise(2.8,13)
rust=smooth(.05,.22,coarse+mid*.24)
edge=smooth(.00,.04,coarse+mid*.24)*(1-smooth(.045,.075,coarse+mid*.24))
paint=rgb((54,87,79))+fine[:,:,None]*4+mid[:,:,None]*5
oxide=rgb((118,66,39))+mid[:,:,None]*np.array([25,15,8])+fine[:,:,None]*6
bc=paint*(1-rust[:,:,None])+oxide*rust[:,:,None]
bc+=edge[:,:,None]*15
height=(1-rust)*.08+mid*.02+fine*.009
save_set('steel',bc,height,.48*(1-rust)+.84*rust,.06+.65*edge,.96-.12*rust,strength=2.3)

# STILL MUTED GREEN WATER: large irregular ripples, suitable for a shallow canal.
phase=noise(160,41)
waves=(np.sin(2*np.pi*(x/N*4+y/N*2)+phase*2)*.35+
       np.sin(2*np.pi*(x/N*8-y/N*3)+phase*3)*.15+
       np.sin(2*np.pi*(x/N*2+y/N*6)+phase)*.24)
bc=rgb((31,47,40))+noise(90,45)[:,:,None]*5
height=waves*.22
save_set('water',bc,height,.21+noise(90,46)*.035,0,1,strength=3.0)

meta={
  'license':'Original procedural artwork created for this asset pack; no external textures.',
  'resolution':[512,512],
  'normal_convention':'OpenGL +Y',
  'orm_channels':{'R':'Ambient occlusion','G':'Roughness','B':'Metalness'},
  'tile_sizes_m':{'brick':[2,2],'concrete':[3,3],'steel':[1.5,1.5],'water':[3,3]},
  'notes':['All noise and gradients are periodic. Assign basecolor as sRGB, normal and ORM as Non-Color.',
           'Water is opaque and shallow in the portable GLB; movement/transparency can be added in the host engine.',
           'No shadows or light directions are baked into basecolor.']
}
(OUT/'texture_manifest.json').write_text(json.dumps(meta,indent=2))

sheet=Image.new('RGB',(1024,592),(24,30,31))
d=ImageDraw.Draw(sheet)
try: font=ImageFont.truetype('/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf',22)
except OSError: font=ImageFont.load_default()
for i,name in enumerate(['brick','concrete','steel','water']):
    xx=(i%2)*512; yy=(i//2)*296
    tile=Image.open(OUT/f'{name}_basecolor.jpg').resize((256,256))
    sheet.paste(tile,(xx,yy+40))
    n=Image.open(OUT/f'{name}_normal.png').resize((128,128))
    orm=Image.open(OUT/f'{name}_orm.png').resize((128,128))
    sheet.paste(n,(xx+256,yy+40)); sheet.paste(orm,(xx+384,yy+40))
    d.text((xx+12,yy+9),name.upper(),fill=(223,219,206),font=font)
sheet.save(OUT/'texture_contact_sheet.jpg',quality=91)
maps=[p for p in OUT.iterdir() if '_basecolor.' in p.name or '_normal.' in p.name or '_orm.' in p.name]
print(json.dumps({'maps':len(maps),'total_bytes':sum(p.stat().st_size for p in maps),'files':{p.name:p.stat().st_size for p in maps}},indent=2))
