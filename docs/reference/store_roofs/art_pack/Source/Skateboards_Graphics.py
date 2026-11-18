"""Seven original print graphics and one subtle grip texture; no brand assets."""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont
import math, random

HERE=Path(__file__).resolve().parent
BASE=HERE.parent if HERE.name=='Source' else HERE.parent/'Spicy_Rodent_Underground'
OUT = BASE/'Textures'/'Skateboards'
OUT.mkdir(parents=True, exist_ok=True)
W, H = 256, 1024
FONT = '/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'

def finish(im, name, foreground):
    d=ImageDraw.Draw(im)
    size=24
    font=ImageFont.truetype(FONT,size)
    while d.textlength(name.upper().replace('_',' '),font=font)>220:
        size-=1; font=ImageFont.truetype(FONT,size)
    d.text((128,880),name.upper().replace('_',' '),font=font,fill=foreground,anchor='mm')
    d.line((80,910,176,910),fill=foreground,width=2)
    # Subtle off-register dot accents are printed graphics, not visual noise.
    im.save(OUT/(name+'.png'),optimize=True)

im=Image.new('RGB',(W,H),(18,37,53)); d=ImageDraw.Draw(im)
for y in range(0,H,8): d.line((0,y,W,y),fill=(20,39+(y%24)//8,55))
d.ellipse((48,290,208,450),fill=(233,215,162))
d.ellipse((76,268,224,419),fill=(18,37,53))
for side in (-1,1):
    wing=[(128,550),(128+side*95,430),(128+side*108,540),(128+side*70,635),(128+side*23,595)]
    d.polygon(wing,fill=(156,191,174))
    d.line(wing+[wing[0]],fill=(233,215,162),width=4)
    d.ellipse((128+side*65-14,515,128+side*65+14,543),fill=(18,37,53))
d.ellipse((117,467,139,638),fill=(233,215,162))
d.line((124,487,111,459),fill=(233,215,162),width=3);d.line((132,487,146,459),fill=(233,215,162),width=3)
for x,y in [(41,220),(198,227),(59,698),(203,684),(123,197)]:
    d.line((x-4,y,x+4,y),fill=(233,215,162),width=2);d.line((x,y-4,x,y+4),fill=(233,215,162),width=2)
finish(im,'Lunar_Moth',(233,215,162))

im=Image.new('RGB',(W,H),(219,66,70));d=ImageDraw.Draw(im)
for y in range(0,H,15): d.line((0,y,256,y+22),fill=(226,78,79),width=4)
d.rounded_rectangle((21,346,235,641),radius=23,fill=(26,34,48),outline=(237,230,203),width=6)
d.rounded_rectangle((38,370,218,580),radius=18,fill=(181,212,197))
rng=random.Random(71)
for y in range(380,570,8):
    for x in range(43,210,9):
        c=rng.choice([(41,62,68),(174,213,190),(231,226,191)])
        d.rectangle((x,y,x+7,y+3),fill=c)
d.polygon([(154,407),(109,495),(143,495),(99,555),(175,474),(140,474)],fill=(246,198,66))
d.line((74,346,48,294),fill=(26,34,48),width=7);d.line((155,346,199,286),fill=(26,34,48),width=7)
d.ellipse((52,605,68,621),fill=(246,198,66));d.ellipse((88,605,104,621),fill=(246,198,66))
finish(im,'Static_Weekend',(237,230,203))

im=Image.new('RGB',(W,H),(224,186,117));d=ImageDraw.Draw(im)
d.ellipse((49,298,207,456),fill=(185,76,43))
for yy in range(365,459,12):d.rectangle((40,yy,217,yy+5),fill=(224,186,117))
d.polygon([(0,564),(79,419),(135,521),(185,456),(256,563),(256,665),(0,665)],fill=(150,90,58))
d.polygon([(0,622),(104,533),(171,589),(219,550),(256,579),(256,728),(0,728)],fill=(70,93,79))
d.line((128,656,129,714,143,734,124,758),fill=(230,202,157),width=9)
for x in (30,217):
    d.line((x,504,x,567),fill=(49,66,59),width=8);d.line((x,540,x-10,540,x-10,521),fill=(49,66,59),width=6)
finish(im,'Ochre_Run',(49,66,59))

im=Image.new('RGB',(W,H),(232,224,191));d=ImageDraw.Draw(im)
for y in range(260,741,12):
    x=128+math.sin(y/80)*24
    d.ellipse((x-3,y-6,x+3,y+6),fill=(50,89,65))
for j,y in enumerate(range(285,728,45)):
    x=128+math.sin(y/80)*24;side=-1 if j%2 else 1
    poly=[(x,y+14),(x+side*76,y-10),(x+side*82,y-44),(x+side*28,y-30)]
    d.polygon(poly,fill=(65+(j%3)*10,112+(j%3)*12,77+(j%2)*13))
    d.line((x,y+14,x+side*75,y-32),fill=(232,224,191),width=2)
for x,y in [(48,343),(210,455),(75,655)]:
    d.ellipse((x-10,y-10,x+10,y+10),fill=(198,115,68));d.ellipse((x-3,y-3,x+3,y+3),fill=(80,80,51))
finish(im,'Concrete_Fern',(44,78,58))

im=Image.new('RGB',(W,H),(35,118,121));d=ImageDraw.Draw(im)
for y in range(268,733,36):
    for x in range(-36,288,36):
        xx=x+round(math.sin(y/65)*19)
        if (x//36+y//36)%2==0:d.rectangle((xx,y,xx+36,y+36),fill=(226,221,192))
for j in range(3):
    pts=[(x,475+j*34+math.sin(x/40)*26) for x in range(-20,277,3)]
    d.line(pts,fill=(245,155,102),width=12)
finish(im,'Tidal_Check',(237,225,190))

im=Image.new('RGB',(W,H),(35,42,77));d=ImageDraw.Draw(im)
for j in range(6):
    y=310+j*70
    pts=[(x,y+math.sin(x/30+j)*10)for x in range(0,256,3)]
    d.line(pts,fill=(66,92,119),width=3)
d.ellipse((46,415,200,611),fill=(204,224,211))
d.polygon([(121,596),(69,678),(126,649),(181,680),(153,596)],fill=(204,224,211))
d.ellipse((74,459,110,505),fill=(35,42,77));d.ellipse((137,459,173,505),fill=(35,42,77))
d.ellipse((90,464,102,481),fill=(213,230,212));d.ellipse((154,464,166,481),fill=(213,230,212))
d.line((100,550,111,560,125,553,138,561,149,550),fill=(35,42,77),width=4)
for x,y,r in [(65,352,13),(161,296,8),(193,373,11)]:d.ellipse((x-r,y-r,x+r,y+r),outline=(132,189,191),width=3)
finish(im,'Ghost_Fish',(204,224,211))

im=Image.new('RGB',(W,H),(65,40,100));d=ImageDraw.Draw(im)
d.polygon([(33,275),(66,604),(161,696),(218,622),(190,534),(75,275)],fill=(106,72,152))
d.polygon([(72,284),(90,544),(153,650),(192,597),(157,538)],fill=(160,110,187))
d.polygon([(113,330),(113,554),(153,619),(169,592)],fill=(236,166,178))
d.ellipse((88,540,210,662),fill=(244,206,148))
d.ellipse((109,556,188,634),fill=(238,172,157))
rng=random.Random(88)
for _ in range(30):
    x,y=rng.randrange(22,235),rng.randrange(210,750)
    if x<65 or x>215 or y<310:
        d.line((x-3,y,x+3,y),fill=(228,217,213),width=2);d.line((x,y-3,x,y+3),fill=(228,217,213),width=2)
finish(im,'Violet_Comet',(241,214,175))

im=Image.new('RGB',(256,256));pix=im.load();rng=random.Random(23)
for y in range(256):
    for x in range(256):
        c=rng.randrange(20,40);pix[x,y]=(c,c+1,c+1)
im.save(OUT/'grip.png',optimize=True)
contact=Image.new('RGB',(7*W,H),(20,20,20))
for i,name in enumerate(['Lunar_Moth','Static_Weekend','Ochre_Run','Concrete_Fern','Tidal_Check','Ghost_Fish','Violet_Comet']):contact.paste(Image.open(OUT/(name+'.png')),(i*W,0))
contact.save(Path(__file__).parent/'graphics_contact.png')
print(OUT)
