"""Spicy Rodent visual-only additions. Python 3, numpy, Pillow, trimesh.
No original game file is read or changed. Source is the recovered NEW art pack.
"""
from pathlib import Path
import os, copy, json, struct, math, shutil, io, hashlib, re
import numpy as np
from PIL import Image, ImageDraw, ImageFont, ImageFilter
import trimesh
from trimesh.visual.material import PBRMaterial
from trimesh.visual.texture import TextureVisuals

HERE=Path(__file__).resolve().parent
OUT=HERE.parent
BASE=HERE/'Seed_Assets_v1'
if not OUT.exists(): shutil.copytree(BASE,OUT)
TEX=OUT/'Textures/Specials'; TEX.mkdir(parents=True,exist_ok=True)
ADD=OUT/'GLB/Additions'; ADD.mkdir(parents=True,exist_ok=True)
FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
BOLD='/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
SERIF='/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf'
def font(n,b=False):
 candidates=[BOLD if b else FONT, 'DejaVuSans-Bold.ttf' if b else 'DejaVuSans.ttf',
             '/System/Library/Fonts/Supplemental/Arial Bold.ttf' if b else '/System/Library/Fonts/Supplemental/Arial.ttf',
             'C:/Windows/Fonts/arialbd.ttf' if b else 'C:/Windows/Fonts/arial.ttf']
 for candidate in candidates:
  try:return ImageFont.truetype(candidate,n)
  except OSError:pass
 return ImageFont.load_default(size=n)
def centered(d,s,xy,size,col,b=True): d.text(xy,s,font=font(size,b),fill=col,anchor='mm')
def texture_noise(im,seed=1,amount=3):
 rng=np.random.default_rng(seed);a=np.asarray(im.convert('RGB')).astype(float)
 a += rng.normal(0,amount,a.shape[:2])[...,None]
 return Image.fromarray(np.uint8(np.clip(a,0,255)))
def save(im,n): texture_noise(im).quantize(colors=128,method=Image.Quantize.MEDIANCUT).save(TEX/n,optimize=True)
def acorn(d,c,s,body=(204,139,73),cap=(224,202,156),line=None):
 x,y=c
 d.ellipse((x-.3*s,y-.16*s,x+.3*s,y+.48*s),fill=body)
 d.polygon([(x-.25*s,y+.25*s),(x+.25*s,y+.25*s),(x,y+.55*s)],fill=body)
 d.rounded_rectangle((x-.34*s,y-.20*s,x+.34*s,y+.025*s),radius=int(.08*s),fill=cap)
 d.line([(x-.05*s,y-.18*s),(x-.02*s,y-.34*s),(x+.09*s,y-.40*s)],fill=cap,width=max(2,int(s*.055)))
 if line:
  for j in range(4):
   yy=y-.17*s+j*.05*s;d.line((x-.28*s,yy,x+.28*s,yy),fill=line,width=2)
def curved(d,points,col,width): d.line(points,fill=col,width=width,joint='curve')
# Two limited-run deck prints; distinct but drawn from the same neighborhood vocabulary.
W,H=512,2048
im=Image.new('RGB',(W,H),(24,39,42));d=ImageDraw.Draw(im)
cream=(233,218,182);sage=(130,170,147);orange=(222,105,55)
for x in range(-180,700,36):d.line((x,0,x+300,H),fill=(29,46,48),width=1)
d.rounded_rectangle((36,70,476,1978),radius=170,outline=sage,width=3)
centered(d,'AFTER HOURS', (256,235),29,cream)
centered(d,'LIVE', (256,555),85,cream);centered(d,'WIRE',(256,645),85,cream)
centered(d,'NEIGHBORHOOD SERIES / 08',(256,740),19,sage)
# Telephone poles and three subtly sagging lines.
for x,yy in [(80,785),(425,1190)]:
 d.line((x,yy,x,yy+510),fill=cream,width=12)
 d.line((x-52,yy+33,x+52,yy+33),fill=cream,width=10)
 for xx in [x-35,x+35]:d.rounded_rectangle((xx-7,yy+7,xx+7,yy+32),radius=4,fill=orange)
for dy in [0,52,104]:
 pts=[]
 for t in np.linspace(0,1,90):pts.append((80+345*t,825+dy+375*t+85*math.sin(math.pi*t)))
 curved(d,pts,sage if dy else cream,4)
# Large curled tail/squirrel silhouette: original symbolic print, not a character portrait.
d.ellipse((110,830,380,1170),fill=orange)
d.ellipse((165,864,353,1110),fill=(24,39,42))
d.ellipse((115,1045,230,1240),fill=orange)
d.ellipse((162,1010,260,1106),fill=orange)
d.polygon([(179,1028),(181,981),(211,1026)],fill=orange)
d.polygon([(230,1042),(279,1071),(237,1091)],fill=orange)
d.ellipse((226,1040,235,1049),fill=(24,39,42))
d.line((164,1193,113,1252,203,1252),fill=orange,width=14)
d.line((212,1158,260,1203,291,1195),fill=orange,width=10)
d.polygon([(345,735),(308,813),(340,813),(312,873),(385,786),(350,786)],fill=orange)
for y in [1380,1400,1420]:d.line((107,y,405,y-65),fill=sage,width=3)
centered(d,'TAKE THE HIGH WAY',(256,1465),26,cream)
centered(d,'NO FIXED ROUTE',(256,1515),19,sage)
centered(d,'08',(256,1790),80,orange)
save(im,'Live_Wire.png')

im=Image.new('RGB',(W,H),(60,78,61));d=ImageDraw.Draw(im)
cream=(237,218,177);rust=(198,108,62);light=(151,167,119)
for k in range(13):
 pts=[]
 for y in range(-100,2180,8):
  x= -65+k*52+30*math.sin(y/170+k*.63)+17*math.sin(y/80+k)
  pts.append((x,y))
 curved(d,pts,(79,96,69),2)
d.rounded_rectangle((34,75,478,1973),radius=170,outline=light,width=3)
centered(d,'CACHE',(256,555),81,cream);centered(d,'RUN',(256,650),91,cream)
centered(d,'A VERY SMALL FORTUNE',(256,745),21,light)
# Abstract caches and hand-drawn route, not a gameplay map.
points=[(95,805),(367,805),(318,844),(97,940),(154,1125),(389,1175),(340,1338),(122,1420),(197,1550),(367,1658)]
for a,b in zip(points[:-1],points[1:]):
 av=np.array(a);bv=np.array(b);dist=np.linalg.norm(bv-av)
 for t in np.arange(0,1,18/dist):
  p=av+(bv-av)*t;q=av+(bv-av)*min(1,t+8/dist);d.line([tuple(p),tuple(q)],fill=light,width=3)
for i,(x,y) in enumerate(points):
 d.ellipse((x-13,y-13,x+13,y+13),fill=(60,78,61),outline=cream,width=3)
 centered(d,str(i+1).zfill(2),(x+24,y-25),18,cream)
# Central badge, acorn and little horizon lines.
d.ellipse((90,865,422,1210),fill=(45,63,51),outline=cream,width=3)
acorn(d,(256,1020),310,rust,cream,(142,111,69))
centered(d,'FIND YOUR OWN WAY',(256,1756),25,cream)
centered(d,'09 / LOCAL RUN',(256,1820),25,light)
save(im,'Cache_Run.png')

# Fabric, patch and small labels.
yy,xx=np.indices((512,512));rng=np.random.default_rng(98)
a=np.zeros((512,512,3))+np.array([57,72,64]);noise=rng.normal(0,3,(512,512))
a+=(np.sin(xx*np.pi)*.3+((xx%4==0)*3-(yy%4==0)*4)+noise)[...,None]
Image.fromarray(np.uint8(np.clip(a,0,255))).save(TEX/'Night_Route_Canvas.png')
no=np.zeros((512,512,3),dtype=np.uint8);no[:,:,0]=np.uint8(128+9*np.sin(xx*np.pi/2));no[:,:,1]=np.uint8(128+9*np.sin(yy*np.pi/2));no[:,:,2]=254
Image.fromarray(no).save(TEX/'Night_Route_Normal.png')
im=Image.new('RGB',(512,512),(196,178,139));d=ImageDraw.Draw(im)
d.rounded_rectangle((12,12,500,500),radius=50,outline=(49,67,55),width=14)
for i in range(30,480,24):
 d.line((i,36,i+10,36),fill=(235,221,190),width=4);d.line((i,476,i+10,476),fill=(235,221,190),width=4)
centered(d,'NIGHT ROUTE',(256,111),43,(42,62,50));acorn(d,(256,252),220,(144,86,48),(48,68,52))
centered(d,'AFTER HOURS DEPT.',(256,415),26,(42,62,50));save(im,'Night_Route_Patch.png')

def label(n,title,sub='',bg=(31,49,44),fg=(231,215,178),size=(1024,320)):
 im=Image.new('RGB',size,bg);d=ImageDraw.Draw(im);w,h=size
 d.rectangle((14,14,w-15,h-15),outline=fg,width=3)
 sz=62
 while d.textlength(title,font=font(sz,True))>w-100:sz-=1
 centered(d,title,(w/2,h*.40 if sub else h*.5),sz,fg)
 if sub:centered(d,sub,(w/2,h*.72),31,fg,False)
 save(im,n)
label('Special_Run_Sign.png','THE LONG WAY HOME','TWO SMALL-RUN DECKS / NO SHORTCUTS')
label('Live_Wire_Tag.png','LIVE WIRE','08 / AFTER HOURS')
label('Cache_Run_Tag.png','CACHE RUN','09 / LOCAL RUN')
label('Night_Route_Tag.png','NIGHT ROUTE','TAKE THE LONG WAY HOME')
label('Cafe_Regulars.png',"PLEASE DON'T FEED",'THE REGULARS',size=(960,420))
label('Jar_Label.png','LOST + FOUND','SMALL THINGS / BIG STORIES',size=(768,320))
label('Sewer_Marker.png','DRY SIDE','MIND YOUR PAWS',bg=(66,73,64),fg=(209,199,160),size=(640,360))
# Original sepia neighborhood woodcut / hanging old-town keepsake.
im=Image.new('RGB',(1200,800),(210,192,153));d=ImageDraw.Draw(im);ink=(78,71,54)
centered(d,'THE LONG WAY HOME',(600,85),56,ink)
centered(d,'AN OLD TOWN STUDY',(600,143),22,ink,False)
for x,y,w,h in [(85,385,245,210),(430,325,240,270),(790,400,280,195)]:
 d.rectangle((x,y,x+w,y+h),outline=ink,width=7)
 d.polygon([(x-20,y),(x+w*.5,y-123),(x+w+20,y)],outline=ink,width=8)
 for wx in [x+w*.2,x+w*.65]:
  d.rectangle((wx,y+55,wx+38,y+112),outline=ink,width=4)
  d.line((wx+19,y+55,wx+19,y+112),fill=ink,width=2)
 d.rectangle((x+w*.42,y+h-85,x+w*.59,y+h),outline=ink,width=4)
 for z in range(y+18,y+h,18):d.line((x+6,z,x+w-6,z),fill=(139,126,98),width=1)
for x in [45,1125]:
 d.line((x,235,x,635),fill=ink,width=9);d.line((x-35,260,x+35,260),fill=ink,width=7)
for off in [0,24]:
 curved(d,[(45+t*1080,263+off+45*math.sin(t*math.pi)) for t in np.linspace(0,1,100)],ink,3)
d.line((45,620,1155,620),fill=ink,width=3)
centered(d,'SOMEWHERE BETWEEN THE WIRES AND THE TREES',(600,706),24,ink,False)
save(im,'Old_Town_Study.png')

class GLB:
 def __init__(self,path=None):
  if path:
   data=Path(path).read_bytes();magic,v,l=struct.unpack_from('<4sII',data);assert magic==b'glTF' and v==2 and l==len(data)
   n,kind=struct.unpack_from('<I4s',data,12);assert kind==b'JSON';self.j=json.loads(data[20:20+n]);off=20+n
   nn,kind=struct.unpack_from('<I4s',data,off);assert kind==b'BIN\0';self.b=bytearray(data[off+8:off+8+nn])
  else:self.j={'asset':{'version':'2.0','generator':'Spicy Rodent visual additions / original mesh authoring'},'scenes':[{'nodes':[]}],'scene':0,'nodes':[]};self.b=bytearray()
 def append_bytes(self,data):
  self.b.extend(b'\0'*((-len(self.b))%4));off=len(self.b);self.b.extend(data);return off
 def image(self,path):
  data=Path(path).read_bytes();off=self.append_bytes(data);vi=len(self.j.setdefault('bufferViews',[]));self.j['bufferViews'].append({'buffer':0,'byteOffset':off,'byteLength':len(data)})
  ii=len(self.j.setdefault('images',[]));self.j['images'].append({'name':Path(path).stem,'mimeType':'image/png','bufferView':vi});return ii
 def save(self,path):
  seen={}
  for node in self.j.get('nodes',[]):
   name=node.get('name','')
   if name in seen:
    seen[name]+=1;node['name']=name+'__'+str(seen[name])
   else:seen[name]=0
  self.b.extend(b'\0'*((-len(self.b))%4));self.j['buffers']=[{'byteLength':len(self.b)}]
  jb=json.dumps(self.j,separators=(',',':')).encode();jb+=b' '*((-len(jb))%4)
  raw=struct.pack('<4sII',b'glTF',2,12+8+len(jb)+8+len(self.b))+struct.pack('<I4s',len(jb),b'JSON')+jb+struct.pack('<I4s',len(self.b),b'BIN\0')+self.b
  Path(path).write_bytes(raw)
 def merge(self,other,parent_name=None,transform=None):
  src=copy.deepcopy(other.j);keys=['nodes','meshes','materials','textures','images','samplers','accessors','bufferViews','cameras','skins']
  offsets={k:len(self.j.get(k,[])) for k in keys};bo=self.append_bytes(other.b)
  for q in src.get('bufferViews',[]):q['byteOffset']=q.get('byteOffset',0)+bo;q['buffer']=0
  for q in src.get('accessors',[]):
   if 'bufferView' in q:q['bufferView']+=offsets['bufferViews']
   if 'sparse' in q:
    q['sparse']['indices']['bufferView']+=offsets['bufferViews'];q['sparse']['values']['bufferView']+=offsets['bufferViews']
  for q in src.get('images',[]):
   if 'bufferView' in q:q['bufferView']+=offsets['bufferViews']
  for q in src.get('textures',[]):
   if 'source' in q:q['source']+=offsets['images']
   if 'sampler' in q:q['sampler']+=offsets['samplers']
  def remaptex(obj):
   if isinstance(obj,dict):
    for k,v in obj.items():
     if 'texture' in k.lower() and isinstance(v,dict) and 'index' in v:v['index']+=offsets['textures']
     else:remaptex(v)
   elif isinstance(obj,list):
    for v in obj:remaptex(v)
  for q in src.get('materials',[]):remaptex(q)
  for q in src.get('meshes',[]):
   for p in q['primitives']:
    p['attributes']={k:v+offsets['accessors'] for k,v in p['attributes'].items()}
    if 'indices' in p:p['indices']+=offsets['accessors']
    if 'material' in p:p['material']+=offsets['materials']
    for t in p.get('targets',[]):
     for k,v in t.items():t[k]=v+offsets['accessors']
  for q in src.get('nodes',[]):
   for k in ['mesh','camera','skin']:
    if k in q:q[k]+=offsets[{'mesh':'meshes','camera':'cameras','skin':'skins'}[k]]
   if 'children' in q:q['children']=[v+offsets['nodes'] for v in q['children']]
  assert not src.get('animations') and not src.get('skins'),'Static visual assets only'
  for k in keys:
   if k in src:self.j.setdefault(k,[]).extend(src[k])
  roots=[v+offsets['nodes'] for v in src['scenes'][src.get('scene',0)]['nodes']]
  if parent_name:
   q={'name':parent_name,'children':roots,'extras':{'units':'meters','visual_only':True}}
   if transform is not None:q['matrix']=np.asarray(transform).T.ravel().tolist()
   roots=[len(self.j['nodes'])];self.j['nodes'].append(q)
  self.j['scenes'][self.j.get('scene',0)]['nodes'].extend(roots)
  for k in ['extensionsUsed','extensionsRequired']:
   if k in src:self.j[k]=list(dict.fromkeys(self.j.get(k,[])+src[k]))
  return roots

def clone_board(name,num,wheelcolor):
 g=GLB(BASE/'GLB/Skateboards/01_Lunar_Moth.glb')
 def rename(o):
  if isinstance(o,dict):return {k:rename(v) for k,v in o.items()}
  if isinstance(o,list):return [rename(v) for v in o]
  if isinstance(o,str):return o.replace('Lunar_Moth',name).replace('Lunar Moth',name.replace('_',' '))
  return o
 g.j=rename(g.j);ii=g.image(TEX/(name+'.png'))
 for t in g.j['textures']:
  if t.get('source')==1:t['source']=ii
 for m in g.j['materials']:
  if m['name'].startswith('Wheels_'):m['pbrMetallicRoughness']['baseColorFactor']=[*wheelcolor,1]
 for node in g.j['nodes']:
  if node.get('name','').startswith('ROOT_'):node['extras'].update({'series':num,'art_only':True,'special_edition':True,'theme':'telephone-wire shortcuts' if num==8 else 'hidden nut caches'})
 path=OUT/'GLB/Skateboards'/f'{num:02d}_{name}.glb';g.save(path);return path
b1=clone_board('Live_Wire',8,(.75,.35,.16));b2=clone_board('Cache_Run',9,(.70,.65,.43))

# Mesh helpers. Authoring coordinates are Blender Z-up, exported GLB is Y-up.
C=np.array([[1,0,0,0],[0,0,1,0],[0,-1,0,0],[0,0,0,1.]],float)
def mat(name,col,rough=.7,metal=0,img=None,normal=None):
 kw=dict(name=name,baseColorFactor=[*col,255],metallicFactor=metal,roughnessFactor=rough,doubleSided=True)
 if img:kw['baseColorTexture']=Image.open(TEX/img)
 if normal:kw['normalTexture']=Image.open(TEX/normal)
 return PBRMaterial(**kw)
M={
 'cloth':mat('Night_Route_Heavy_Canvas',(255,255,255),.92,img='Night_Route_Canvas.png',normal='Night_Route_Normal.png'),
 'hem':mat('Faded_Canvas_Seams',(64,76,62),.95),
 'thread':mat('Ochre_Stitching',(169,144,101),.94),
 'brass':mat('Aged_Brass_Hardware',(138,104,58),.47,.60),
 'iron':mat('Blackened_Steel',(42,49,47),.53,.60),
 'wood':mat('Salvaged_Dark_Wood',(84,54,33),.78),
 'woodlight':mat('Exposed_Wood_Edge',(153,115,69),.82),
 'jar':mat('Glazed_Green_Ceramic',(83,114,97),.3),
 'paper':mat('Warm_Paper',(216,199,158),.88),
}
class Builder:
 def __init__(self):self.s=trimesh.Scene();self.count={}
 def mesh(self,n,m,material,uv=None):
  if len(m.faces)==0:return
  if uv is None:
   # Deterministic planar mapping; body/sleeves provide tailored maps separately.
   vs=m.vertices;u=(vs[:,0]-vs[:,0].min())/max(float(np.ptp(vs[:,0])),1e-9);v=(vs[:,2]-vs[:,2].min())/max(float(np.ptp(vs[:,2])),1e-9);uv=np.column_stack((u,v))
  m.visual=TextureVisuals(uv=uv,material=M[material] if isinstance(material,str) else material)
  m.metadata['units']='meters';m.metadata['visual_only']=True
  i=self.count.get(n,0);self.count[n]=i+1;name=n if not i else n+f'_{i:03d}'
  self.s.add_geometry(m,node_name=name,geom_name=name)
 def box(self,n,c,d,ma,rot=0):
  m=trimesh.creation.box(d);t=trimesh.transformations.rotation_matrix(rot,(0,0,1));t[:3,3]=c;m.apply_transform(t);self.mesh(n,m,ma)
 def cylinder(self,n,a,b,r,ma,sections=12,r2=None):
  a,b=np.array(a,float),np.array(b,float);v=b-a;ln=np.linalg.norm(v)
  if ln<1e-7:return
  if r2 is None:m=trimesh.creation.cylinder(r,ln,sections=sections)
  else:
   theta=np.arange(sections)*2*np.pi/sections;vs=[]
   for z,rad in [(-ln/2,r),(ln/2,r2)]:vs.extend(np.column_stack((rad*np.cos(theta),rad*np.sin(theta),np.ones(sections)*z)))
   vs.extend([[0,0,-ln/2],[0,0,ln/2]]);fs=[]
   for i in range(sections):
    j=(i+1)%sections;fs.extend([[i,j,j+sections],[i,j+sections,i+sections],[2*sections,j,i],[2*sections+1,i+sections,j+sections]])
   m=trimesh.Trimesh(vs,fs,process=False)
  t=trimesh.geometry.align_vectors([0,0,1],v/ln);t[:3,3]=(a+b)/2;m.apply_transform(t);self.mesh(n,m,ma)
 def ellipsoid(self,n,c,scale,ma):
  m=trimesh.creation.icosphere(subdivisions=2,radius=1);m.apply_scale(scale);m.apply_translation(c);self.mesh(n,m,ma)
 def panel(self,n,c,w,h,filename,normal=(0,-1,0),frame=False):
  up=np.array([0,0,1.]);normal=np.array(normal,float);right=np.cross(up,normal);c=np.array(c,float)
  vs=[c-right*w/2-up*h/2,c+right*w/2-up*h/2,c+right*w/2+up*h/2,c-right*w/2+up*h/2]
  m=trimesh.Trimesh(vs,[[0,1,2],[0,2,3]],process=False)
  self.mesh(n,m,mat(n+'_Printed_Texture',(255,255,255),.91,img=filename),np.array([[0,0],[1,0],[1,1],[0,1]]))
  if frame:
   for s in [-1,1]:
    self.cylinder(n+'_Frame',c+right*s*(w/2+.024)-up*(h/2+.04),c+right*s*(w/2+.024)+up*(h/2+.04),.028,'wood',4)
    self.cylinder(n+'_Frame',c+up*s*(h/2+.024)-right*(w/2+.04),c+up*s*(h/2+.024)+right*(w/2+.04),.028,'wood',4)
 def line(self,n,ps,r,ma,sections=6):
  for a,b in zip(ps[:-1],ps[1:]):self.cylinder(n,a,b,r,ma,sections)
 def save(self,p):
  # Batch repeated stitch/zipper/cuff meshes, preserving semantic parts.
  grouped={}
  for name,m in self.s.geometry.items():
   key=re.sub(r'_\d{3}$','',name)
   grouped.setdefault(key,[]).append(m)
  scene=trimesh.Scene()
  for name,ms in grouped.items():
   verts=[];faces=[];uvs=[];off=0
   for m in ms:
    verts.append(m.vertices);faces.append(m.faces+off);uvs.append(m.visual.uv);off+=len(m.vertices)
   m=trimesh.Trimesh(np.vstack(verts),np.vstack(faces),process=False)
   m.visual=TextureVisuals(uv=np.vstack(uvs),material=ms[0].visual.material)
   scene.add_geometry(m,node_name=name,geom_name=name)
  scene.apply_transform(C);p=Path(p)
  p.write_bytes(scene.export(file_type='glb',include_normals=True));return GLB(p)

jacket=Builder()
# Round-shouldered jacket shell, small wrinkles and actual depth, not a billboard.
rings=[(.045,.245,.078),(.08,.245,.085),(.22,.25,.092),(.38,.258,.10),(.53,.275,.102),(.62,.285,.095),(.668,.245,.085),(.72,.105,.063)]
N=40;vs=[];uv=[]
for k,(z,w,dpth) in enumerate(rings):
 for i in range(N+1):
  a=2*math.pi*i/N
  fold=1+.035*math.sin(i*1.9+k*.65)
  x=w*math.cos(a)*fold;y=dpth*math.sin(a)*fold
  vs.append((x,y,z));uv.append((i/N,(z-.045)/(.72-.045)))
fs=[]
for k in range(len(rings)-1):
 for i in range(N):
  a=k*(N+1)+i;b=a+N+1;fs.extend([[a,a+1,b+1],[a,b+1,b]])
jacket.mesh('JACKET_Night_Route_Body',trimesh.Trimesh(vs,fs,process=False),'cloth',np.array(uv))
# Soft tubular sleeves, tapered cuffs with several fold rings.
for sign in [-1,1]:
 p0=np.array([sign*.22,0,.60]);p1=np.array([sign*.465,-.014,.14]);axis=(p1-p0);axis/=np.linalg.norm(axis)
 u=np.array([0,1,0.]);v=np.cross(axis,u);vv=[];uv=[];faces=[]
 for k in range(9):
  t=k/8;c=p0*(1-t)+p1*t;rr=.100*(1-t)+.062*t
  rr*=1+(.06*math.sin(k*3.6))
  for i in range(25):
   ang=i/24*2*math.pi;vv.append(c+u*math.cos(ang)*rr+v*math.sin(ang)*rr*.85);uv.append((i/24,k/8))
 for k in range(8):
  for i in range(24):
   a=k*25+i;b=a+25;faces.extend([[a,b,b+1],[a,b+1,a+1]])
 jacket.mesh('JACKET_Sleeve_L' if sign<0 else 'JACKET_Sleeve_R',trimesh.Trimesh(vv,faces,process=False),'cloth',np.array(uv))
 jacket.cylinder('JACKET_Cuff',p1-axis*.025,p1+axis*.025,.066,'hem',24)
 jacket.cylinder('JACKET_Cuff_Button',(p1[0],-.078,p1[2]),(p1[0],-.085,p1[2]),.009,'brass',12)
# Ribbed bottom hem, center zip and stitched seams.
jacket.box('JACKET_Hem',(0,-.080,.067),(.474,.016,.043),'hem')
jacket.box('JACKET_Zip_Tape',(0,-.105,.352),(.025,.015,.54),'hem')
for z in np.arange(.11,.61,.014):
 jacket.box('JACKET_Zipper_Teeth',(-.004,-.117,z),(.007,.005,.005),'brass')
 jacket.box('JACKET_Zipper_Teeth',(.004,-.117,z+.006),(.007,.005,.005),'brass')
jacket.box('JACKET_Zipper_Pull',(.003,-.126,.615),(.018,.008,.039),'brass')
# Lapels are shaped triangular thick pieces; shoulder seam topstitching.
for sign in [-1,1]:
 verts=[(sign*.012,-.09,.717),(sign*.105,-.087,.72),(sign*.18,-.105,.649),(sign*.06,-.128,.603)]
 m=trimesh.Trimesh(verts,[[0,1,2],[0,2,3]],process=False);jacket.mesh('JACKET_Collar',m,'hem')
 jacket.line('JACKET_Shoulder_Seam',[(sign*.11,-.082,.679),(sign*.24,-.070,.645),(sign*.29,-.055,.61)],.0018,'thread')
# One pocket and one acorn patch.
jacket.box('JACKET_Chest_Pocket',(-.142,-.105,.43),(.146,.018,.15),'hem')
jacket.box('JACKET_Pocket_Flap',(-.142,-.120,.515),(.157,.018,.047),'cloth')
jacket.cylinder('JACKET_Pocket_Button',(-.142,-.132,.51),(-.142,-.137,.51),.009,'brass',12)
jacket.panel('JACKET_Night_Route_Acorn_Patch',(.139,-.112,.50),.135,.135,'Night_Route_Patch.png')
for xx in [-.21,-.075]:
 for zz in np.arange(.36,.495,.012):jacket.cylinder('JACKET_Pocket_Stitch',(xx,-.117,zz),(xx,-.117,zz+.005),.0009,'thread',4)
for xx in np.arange(-.22,.23,.014):jacket.cylinder('JACKET_Hem_Stitch',(xx,-.092,.064),(xx+.006,-.092,.064),.0009,'thread',4)
# Repaired pocket / local motif on the back: a loose wire between two small acorns.
jacket.line('JACKET_Back_Wire',[(x,.104,.53-.025*math.sin((x+.19)/.38*math.pi)) for x in np.linspace(-.19,.19,25)],.0028,'thread',6)
# Hanger and hook, supplied as separate mesh nodes (static merch, not avatar clothing).
jacket.line('JACKET_Hanger',[(-.23,.02,.68),(0,.02,.80),(.23,.02,.68),(-.23,.02,.68)],.006,'woodlight',8)
jacket.line('JACKET_Hook',[(0,.02,.80),(0,.02,.84),(.032,.02,.875),(.052,.02,.86),(.045,.02,.838)],.004,'brass',8)
jp=ADD/'Night_Route_Jacket.glb';jg=jacket.save(jp)
jg.j['asset']['extras']={'display_prop_only':True,'not_rigged':True,'product_name':'Night Route','units':'meters'};jg.save(jp)

# Source-stage additions to the existing new shop, no game work.
shopadd=Builder()
# Special upper deck shelf and brackets behind the retail checkout.
shopadd.box('SPECIALS_Upper_Shelf',(-4.25,-5.49,2.755),(3.65,.66,.075),'wood')
shopadd.box('SPECIALS_Worn_Shelf_Lip',(-4.25,-5.14,2.77),(3.67,.035,.10),'woodlight')
for x in [-5.65,-2.85]:
 shopadd.line('SPECIALS_Iron_Brackets',[(x,-5.96,2.22),(x,-5.96,2.72),(x,-5.20,2.72),(x,-5.96,2.22)],.018,'iron',6)
shopadd.panel('SPECIALS_Series_Sign',(-4.25,-5.70,3.87),2.55,.20,'Special_Run_Sign.png',normal=(0,1,0),frame=False)
shopadd.panel('SPECIALS_Live_Wire_Tag',(-5.05,-5.13,2.70),.55,.17,'Live_Wire_Tag.png',normal=(0,1,0))
shopadd.panel('SPECIALS_Cache_Run_Tag',(-3.50,-5.13,2.70),.55,.17,'Cache_Run_Tag.png',normal=(0,1,0))
shopadd.panel('SPECIALS_Jacket_Tag',(-6.93,-.53,1.98),.76,.20,'Night_Route_Tag.png',normal=(1,0,0))
# Café art goes in a blank wall interval, away from menu boards and beads.
shopadd.panel('CAFE_Long_Way_Home_Print',(1.105,.36,2.49),.80,.535,'Old_Town_Study.png',normal=(1,0,0),frame=True)
shopadd.panel('CAFE_Regulars_Plaque',(6.935,4.15,1.88),.82,.36,'Cafe_Regulars.png',normal=(-1,0,0),frame=True)
# Ceramic lost-and-found jar with a carved acorn lid knob.
x,y,z=6.12,1.15,1.155
shopadd.cylinder('CAFE_Lost_Found_Jar',(x,y,z),(x,y,z+.25),.108,'jar',32,.12)
shopadd.cylinder('CAFE_Jar_Wood_Lid',(x,y,z+.25),(x,y,z+.285),.127,'woodlight',32)
shopadd.ellipsoid('CAFE_Acorn_Knob',(x,y,z+.322),(.038,.038,.045),'woodlight')
shopadd.cylinder('CAFE_Acorn_Cap',(x,y,z+.333),(x,y,z+.35),.040,'wood',16,.028)
shopadd.cylinder('CAFE_Acorn_Stem',(x,y,z+.346),(x+.012,y,z+.378),.007,'wood',7)
shopadd.panel('CAFE_Jar_Label',(x-.121,y,z+.135),.145,.066,'Jar_Label.png',normal=(-1,0,0))
# Two worn coffee coasters, not additional menu items.
for px,py in [(5.82,.37),(5.82,-.66)]:
 shopadd.cylinder('CAFE_Cork_Coaster',(px,py,1.155),(px,py,1.161),.06,'woodlight',24)
shop_addp=ADD/'Shop_Flair_Only.glb';sa=shopadd.save(shop_addp)
# Append boards with individual roots; preserving seven existing boards and their originals.
def transform_blender(translation,rot=(0,0,0)):
 t=trimesh.transformations.euler_matrix(*rot);t[:3,3]=translation;return C@t@np.linalg.inv(C)
sa.merge(GLB(b1),'DISPLAY_Live_Wire',transform_blender((-5.05,-5.53,3.13),(3*math.pi/4,0,0)))
sa.merge(GLB(b2),'DISPLAY_Cache_Run',transform_blender((-3.50,-5.53,3.13),(3*math.pi/4,0,0)))
sa.merge(jg,'DISPLAY_Night_Route',transform_blender((-6.80,-.53,2.13),(0,0,math.pi/2)))
sa.save(shop_addp)
full=GLB(BASE/'GLB/04_Offbeat_Shop_Interior.glb');full.merge(sa,'ADDITIONS_v2_Visual_Flair');full.j['asset']['extras']={'edition':'v2','visual_only':True,'skateboards':9,'cafe_stools':5};full.save(OUT/'GLB/04_Offbeat_Shop_Interior.glb')
# A tiny reusable utility marker; extra personality, unchanged tunnel topology.
sewer=Builder();sewer.panel('SEWER_Dry_Side_Plaque',(0,0,.18),.64,.36,'Sewer_Marker.png',normal=(0,-1,0),frame=False)
for xx in [-.29,.29]:
 for zz in [.035,.325]:sewer.cylinder('SEWER_Plaque_Screw',(xx,-.002,zz),(xx,-.008,zz),.008,'iron',8)
sp=ADD/'Dry_Side_Marker.glb';sg=sewer.save(sp)
# Right-hand wall at the quiet south end, clear of pump, ports and access panel.
sf=GLB(BASE/'GLB/03_Concrete_Maintenance_Tunnel.glb');sf.merge(sg,'DETAIL_Dry_Side_Marker',transform_blender((2.98,-4.7,1.3),(0,0,-math.pi/2)));sf.save(OUT/'GLB/03_Concrete_Maintenance_Tunnel.glb')
# Standalone staged scene for honest screenshots of the additions.
stage=GLB();stage.merge(GLB(b1),'Preview_Live_Wire',transform_blender((-.58,0,.48),(3*math.pi/4,0,0)))
stage.merge(GLB(b2),'Preview_Cache_Run',transform_blender((-.15,0,.48),(3*math.pi/4,0,0)))
stage.merge(jg,'Preview_Night_Route',transform_blender((.57,.02,.05),(0,0,math.pi)))
stage.save(ADD/'Specials_Display.glb')
# Keep track of exact output and placement; no price or behavior supplied.
meta={
 'edition':'v2 / visual-only additions',
 'themes':['telephone-wire routes','hidden nut caches','neighborhood mischief'],
 'new_items':[
  {'file':'GLB/Skateboards/08_Live_Wire.glb','name':'Live Wire','kind':'assembled skateboard','theme':'telephone-wire shortcuts','price':None},
  {'file':'GLB/Skateboards/09_Cache_Run.glb','name':'Cache Run','kind':'assembled skateboard','theme':'nut caches and a hand-drawn route','price':None},
  {'file':'GLB/Additions/Night_Route_Jacket.glb','name':'Night Route','kind':'static jacket display prop','rigged':False,'wearable':False,'price':None}],
 'updated_full_scene':'GLB/04_Offbeat_Shop_Interior.glb',
 'additions_only_scene':'GLB/Additions/Shop_Flair_Only.glb',
 'shop_addition_coordinates':'Full-shop origin, Y-up; do not add to the updated full scene a second time.',
 'stool_count':5,'skateboard_count':9,
 'cafe_details':['framed Old Town study','Please do not feed the regulars plaque','lost-and-found ceramic jar with acorn knob','two cork coasters'],
 'sewer_detail':'small dry-side plaque on maintenance tunnel wall, no topology or port changes',
 'original_game_files_touched':False,
 'validation_scope':'GLB binary structure, named geometry, dimensions, image buffers, render inspection; no Roblox runtime test',
 'source_status':'Base Blender scenes preserved. New additions authored/exported directly as GLB. Import_v2_Into_Blender.py reconstructs final editable Blender scenes from GLBs; that Blender script has not been executed in this runtime.'}
(OUT/'Metadata/v2_Additions.json').write_text(json.dumps(meta,indent=2))
print('DONE',OUT)
