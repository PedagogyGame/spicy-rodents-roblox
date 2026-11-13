"""Original shop texture generator. Python 3, Pillow, NumPy; DejaVu font paths below are configurable."""
from PIL import Image, ImageDraw, ImageFont, ImageFilter
from pathlib import Path
import numpy as np, shutil, json, math

ROOT=Path(__file__).resolve().parents[1]
OUT=ROOT/'Textures/Shop'
OUT.mkdir(parents=True,exist_ok=True)
FONT='/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf'
BOLD='/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'
SERIF='/usr/share/fonts/truetype/dejavu/DejaVuSerif.ttf'
def font(n,bold=False): return ImageFont.truetype(BOLD if bold else FONT,n)
def text_center(d,y,t,f,fill,w=512):
    box=d.textbbox((0,0),t,font=f); d.text(((w-box[2]+box[0])/2,y),t,font=f,fill=fill)
def save(im,name): im.convert('RGB').save(OUT/name,quality=89,optimize=True)

rng=np.random.default_rng(41026)
N=512
y,x=np.mgrid[:N,:N]
# Plywood has readable broad growth bands and occasional grain, not baked lighting.
grain=np.sin(y*.19+np.sin(x*.016)*1.6)+.38*np.sin(y*.61+np.sin(x*.009)*3)
speck=rng.normal(0,1.3,(N,N))
rgb=np.zeros((N,N,3))
for c,v in enumerate([154,111,68]): rgb[:,:,c]=v+grain*(7 if c<2 else 4)+speck
im=Image.fromarray(np.uint8(np.clip(rgb,0,255)))
d=ImageDraw.Draw(im)
for j in range(10):
    yy=int(rng.integers(0,N)); xx=int(rng.integers(0,N))
    d.arc((xx-60,yy-7,xx+65,yy+7),0,355,fill=(116,81,45),width=1)
save(im,'plywood_basecolor.jpg')
normal=np.zeros((N,N,3),np.uint8); normal[:]=[128,128,255]
normal[:,:,1]=np.uint8(np.clip(128+5*np.cos(y*.19+np.sin(x*.016)*1.6),0,255))
Image.fromarray(normal).save(OUT/'plywood_normal.png',optimize=True)
orm=np.zeros((N,N,3),np.uint8); orm[:,:,0]=255; orm[:,:,1]=np.uint8(183+8*np.sin(y*.19));
Image.fromarray(orm).save(OUT/'plywood_orm.png',optimize=True)
Image.fromarray(orm[:,:,1]).save(OUT/'plywood_roughness.png',optimize=True)
Image.fromarray(orm[:,:,2]).save(OUT/'plywood_metallic.png',optimize=True)

# Compact original shared masonry and steel maps, copied without changing sources.
for base in ['brick','concrete','steel']:
    for suffix in ['basecolor.jpg','normal.png','orm.png','roughness.png','metallic.png']:
        src=ROOT/'Textures/Sewer'/f'{base}_{suffix}'
        im=Image.open(src).resize((256,256),Image.Resampling.LANCZOS)
        dst=OUT/src.name
        if dst.suffix=='.jpg': im.save(dst,quality=88,optimize=True)
        else: im.save(dst,optimize=True)

# Original generic collage/print graphics with no real brands or licensed characters.
def poster(name,title,sub,kind=0):
    im=Image.new('RGB',(512,700),(221,205,168)); d=ImageDraw.Draw(im)
    for k in range(15):
        xx,yy=int(rng.integers(0,512)),int(rng.integers(0,700))
        d.line((xx,yy,min(xx+int(rng.integers(20,100)),512),yy),fill=(204,187,152),width=2)
    d.rectangle((20,20,492,680),outline=(33,44,41),width=4)
    if kind==0:
        d.ellipse((100,135,412,447),fill=(36,57,54)); d.ellipse((164,199,348,383),fill=(215,179,84))
        for a in range(0,360,30):
            xx=256+175*math.cos(math.radians(a)); yy=291+175*math.sin(math.radians(a))
            d.line((256,291,xx,yy),fill=(154,64,42),width=5)
        d.ellipse((216,251,296,331),fill=(229,217,188))
    elif kind==1:
        for k in range(5):
            d.rectangle((75+k*35,110+k*50,405-k*35,525-k*30),outline=(40,80+12*k,75),width=15)
        d.polygon([(93,430),(254,157),(418,442)],fill=(170,69,43))
    elif kind==2:
        d.ellipse((130,140,382,390),fill=(36,41,41))
        d.rectangle((170,330,342,505),fill=(36,41,41))
        d.polygon([(105,505),(407,505),(350,380),(167,380)],fill=(36,41,41))
        d.ellipse((145,175,369,225),fill=(186,100,57))
        d.rectangle((160,139,352,197),fill=(51,45,41))
        d.ellipse((128,189,384,217),fill=(51,45,41))
    elif kind==3:
        # Fictional character silhouette with a pinned-up hairstyle and scarf.
        d.ellipse((142,124,350,343),fill=(44,42,41)); d.ellipse((280,106,380,208),fill=(44,42,41))
        d.polygon([(190,310),(288,310),(390,520),(100,520)],fill=(44,42,41))
        d.polygon([(170,335),(303,335),(260,412)],fill=(142,73,50))
    for line,t in enumerate(title.split('|')): text_center(d,540+line*45,t,font(34,True),(36,42,40))
    text_center(d,642,sub,font(13),(69,61,51))
    save(im,name)
poster('poster_after_hours.jpg','AFTER HOURS','SOUND / PAPER / PEOPLE',0)
poster('poster_small_joys.jpg','SMALL JOYS','PRINTS FROM ANOTHER AFTERNOON',1)
poster('portrait_mr_vesper.jpg','MR. VESPER','A FICTIONAL PORTRAIT / CIRCA 1964',2)
poster('portrait_miss_fern.jpg','MISS FERN','A FICTIONAL PORTRAIT / CIRCA 1968',3)

for name,fg,bg in [('MIDNIGHT STATIC',(223,219,204),(39,43,46)),('LOOSE WIRE',(240,205,156),(72,96,102)),('DUSTLINE',(74,52,33),(212,174,108)),('CLEAR SIGNAL',(35,57,50),(224,226,198))]:
    im=Image.new('RGB',(512,128),bg); d=ImageDraw.Draw(im)
    d.rectangle((8,8,503,119),outline=fg,width=2)
    text_center(d,44,name,font(31,True),fg)
    save(im,'tag_'+name.lower().replace(' ','_')+'.jpg')

# Exact national flag patterns; no text, badges, or invented symbols.
im=Image.new('RGB',(450,300)); d=ImageDraw.Draw(im)
for i,c in enumerate([(15,15,16),(255,220,25),(225,42,45)]): d.rectangle((i*150,0,(i+1)*150,300),fill=c)
save(im,'flag_belgium.jpg')
im=Image.new('RGB',(600,300),(0,142,70)); d=ImageDraw.Draw(im)
d.polygon([(0,0),(300,150),(0,300)],fill=(11,15,13));d.polygon([(600,0),(300,150),(600,300)],fill=(11,15,13))
d.line((0,0,600,300),fill=(255,207,30),width=38);d.line((600,0,0,300),fill=(255,207,30),width=38)
save(im,'flag_jamaica.jpg')

art=ROOT/'Textures/Shop'
for f in ['menu_drinks.png','menu_food.png']:
    im=Image.open(art/f).resize((384,512),Image.Resampling.LANCZOS)
    im.save(OUT/f,optimize=True)
if (art/'Artwork_Originals/the_spice_squirrels_original.png').exists():
    im=Image.open(art/'Artwork_Originals/the_spice_squirrels_original.png').resize((384,512),Image.Resampling.LANCZOS)
    save(im,'spice_squirrels.jpg')

# Two subtle original callbacks to Spicy Rodent's rooftop and spicy-humor motifs.
im=Image.new('RGB',(384,512),(211,194,153));d=ImageDraw.Draw(im)
d.rectangle((14,14,370,498),outline=(47,53,44),width=3)
for yy,t in [(40,'ROOFTOP'),(82,'SOCIAL CLUB')]:text_center(d,yy,t,font(30,True),(47,53,44),384)
for xx,hh in [(35,90),(104,125),(180,75),(258,112)]:d.rectangle((xx,340-hh,xx+75,380),fill=(57,69,60))
d.line((20,212,362,182),fill=(47,53,44),width=3)
d.ellipse((184,164,210,192),fill=(148,70,39));d.ellipse((210,144,252,187),outline=(148,70,39),width=12)
text_center(d,422,'BRING A STORY.',font(22,True),(47,53,44),384)
text_center(d,453,'LEAVE A LITTLE NOISE.',font(16),(47,53,44),384)
save(im,'poster_rooftop.jpg')
im=Image.new('RGB',(256,256),(225,201,151));d=ImageDraw.Draw(im)
d.ellipse((19,19,236,236),outline=(63,69,46),width=5)
d.polygon([(61,95),(75,87),(94,99),(106,135),(116,170),(148,192),(114,188),(86,165),(69,133)],fill=(173,48,31))
d.line((71,96,81,73,98,69),fill=(59,103,44),width=9)
d.ellipse((137,102,192,175),fill=(164,111,52));d.pieslice((128,83,200,129),180,360,fill=(92,65,34));d.rectangle((129,104,198,121),fill=(92,65,34))
d.line((164,98,171,83),fill=(92,65,34),width=7)
save(im,'chili_acorn.jpg')

print(json.dumps({'directory':str(OUT),'files':len(list(OUT.iterdir())),'bytes':sum(p.stat().st_size for p in OUT.iterdir())},indent=2))
