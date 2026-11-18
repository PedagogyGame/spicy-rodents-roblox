"""Build pinball art at the exact dimensions and coordinates in pinball_data.json.

Original theme emblems were made with the built-in image-generation tool.
This deterministic layout pass places each supplied label and lamp ring in the
game's metre coordinate system, with no geometry or collision changes.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageFont, ImageFilter, ImageChops
import json, math, random, shutil

SOURCE = Path(__file__).resolve().parent
ROOT = SOURCE.parent.parent
PACK = ROOT / 'work/Pinball_ChatGPT_Pack'
OUT = ROOT / 'build/models'
TEX = SOURCE / 'textures'
ORIGINALS = SOURCE / 'art_originals'
for p in (OUT,TEX,ORIGINALS): p.mkdir(parents=True,exist_ok=True)
DATA = json.loads((PACK/'pinball_data.json').read_text())
S = 3
W,H = 486,1024
FONT_SANS = '/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf'
FONT_SERIF = '/usr/share/fonts/truetype/dejavu/DejaVuSerifCondensed-Bold.ttf'
FONT_ITALIC = '/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-BoldOblique.ttf'
FONT_MONO = '/usr/share/fonts/truetype/dejavu/DejaVuSansMono-Bold.ttf'

GENERATED = {
 'Acorn': 'exec-ab8e95e8-0758-45f0-8f4d-f564eb31c3e0.png',
 'Rodent': 'exec-838f51cc-76de-4573-b1fd-e0faa0f49021.png',
 'Space': 'exec-386e8c06-1d04-4d8b-a79a-e62f44d72fdc.png',
}
for prefix,filename in GENERATED.items():
 target=ORIGINALS/(prefix+'_Emblem.png')
 if not target.exists(): shutil.copy2(ROOT/'generated_images'/filename,target)

def rgb(c):
 c=c.lstrip('#');return tuple(int(c[i:i+2],16) for i in (0,2,4))
def blend(a,b,t): return tuple(round(a[i]*(1-t)+b[i]*t) for i in range(3))
def xy(x,z): return (x/.672*W*S,(z+1.372)/1.4168*H*S)
def rad(r): return (r/.672*W*S,r/1.4168*H*S)
def box_world(x,z,w,h):
 cx,cy=xy(x,z);rx,ry=rad(w/2)[0],rad(h/2)[1]
 return (cx-rx,cy-ry,cx+rx,cy+ry)
def line_m(d,pts,fill,width=0.0014):
 d.line([xy(*p) for p in pts],fill=fill,width=max(1,round(width/.672*W*S)),joint='curve')
def poly_m(d,pts,fill,outline=None,width=1):
 pp=[xy(*p) for p in pts];d.polygon(pp,fill=fill)
 if outline:d.line(pp+[pp[0]],fill=outline,width=width*S,joint='curve')
def ellipse_m(d,x,z,rx,rz,fill=None,outline=None,width=1):
 cx,cy=xy(x,z);a,b=rad(rx)[0],rad(rz)[1]
 d.ellipse((cx-a,cy-b,cx+a,cy+b),fill=fill,outline=outline,width=max(1,round(width*S)))

def lettering(im,text,box,color,font_path=FONT_SANS,shadow=None,fit=0.94):
 # The supplied box remains authoritative. Text is centered optically inside it.
 x0,y0,x1,y1=box;ww=max(2,round(x1-x0));hh=max(2,round(y1-y0))
 f=ImageFont.truetype(font_path,160)
 bb=f.getbbox(text,stroke_width=0)
 glyph=Image.new('RGBA',(bb[2]-bb[0]+8,bb[3]-bb[1]+8))
 gd=ImageDraw.Draw(glyph);gd.text((4-bb[0],4-bb[1]),text,font=f,fill=(*color,255))
 cropped=glyph.crop(glyph.getbbox())
 # Long instruction labels use a condensed face but retain the specified area.
 scale=min(ww*fit/cropped.width,hh*fit/cropped.height)
 tw,th=max(1,round(cropped.width*scale)),max(1,round(cropped.height*scale))
 cropped=cropped.resize((tw,th),Image.Resampling.LANCZOS)
 px,py=round((x0+x1-tw)/2),round((y0+y1-th)/2)
 if shadow:
  mask=cropped.getchannel('A');sh=Image.new('RGBA',(tw,th),(*shadow,255));sh.putalpha(mask)
  im.alpha_composite(sh,(px+S//2,py+S//2))
 im.alpha_composite(cropped,(px,py))

def paste_emblem(im,prefix,x,z,w,opacity=255):
 art=Image.open(ORIGINALS/(prefix+'_Emblem.png')).convert('RGBA')
 bb=art.getchannel('A').getbbox()
 art=art.crop(bb)
 size=round(w/.672*W*S)
 art=art.resize((size,round(size*art.height/art.width)),Image.Resampling.LANCZOS)
 if opacity!=255:art.putalpha(art.getchannel('A').point(lambda v:round(v*opacity/255)))
 cx,cy=xy(x,z)
 im.alpha_composite(art,(round(cx-art.width/2),round(cy-art.height/2)))

def acorn_glyph(d,x,z,size,c):
 # Repeatable two-colour oak/acorn motif, used only as printed ornament.
 ellipse_m(d,x,z+size*.10,size*.34,size*.46,fill=c['art'])
 ellipse_m(d,x,z+size*.10,size*.27,size*.38,fill=c['plastic'])
 ellipse_m(d,x,z-size*.25,size*.40,size*.20,fill=c['art'])
 for j in (-.2,0,.2):
  line_m(d,[(x-size*.30,z-size*.26+j*size),(x+size*.30,z-size*.26+j*size)],c['trim'],.0007)
 line_m(d,[(x,z-size*.4),(x+size*.07,z-size*.58)],c['art'],.0019)

def make_board(key,m):
 pre=m['file_prefix'];c={k:rgb(v) for k,v in m['colours'].items()}
 im=Image.new('RGBA',(W*S,H*S),(*c['field'],255));d=ImageDraw.Draw(im)
 # Uninterrupted ground colour, restrained pinstriping and an independent shooter lane.
 d.rounded_rectangle((7*S,7*S,(W-7)*S,(H-7)*S),radius=50*S,outline=blend(c['art'],c['field'],.38),width=2*S)
 d.rounded_rectangle((11*S,11*S,(W-11)*S,(H-11)*S),radius=47*S,outline=blend(c['trim'],c['field'],.22),width=S)
 lane=box_world(.647,-.653,.041,1.356)
 d.rectangle(lane,fill=blend(c['field'],c['art'],.20))
 line_m(d,[(.625,.030),(.625,-1.08)],blend(c['ink'],c['field'],.42),.0012)
 # Faint decorative pattern, intentionally lower-contrast than labels and inserts.
 rng=random.Random(560+len(key))
 if key=='acorn':
  for x in (.041,.580):
   for z in (-.2,-.4,-.57,-.8,-1.0):
    ellipse_m(d,x,z,.009,.021,fill=blend(c['plastic'],c['field'],.68))
    line_m(d,[(x,z-.020),(x,z+.023)],blend(c['art'],c['field'],.75),.0008)
  # Old electro-mechanical radial sunburst behind bumper grouping.
  centre=(.30,-1.045)
  for i in range(28):
   a=2*math.pi*i/28
   line_m(d,[(centre[0]+.050*math.cos(a),centre[1]+.050*math.sin(a)),(centre[0]+.195*math.cos(a),centre[1]+.195*math.sin(a))],blend(c['trim'],c['field'],.50),.0015)
  for rx in (.078,.143,.192): ellipse_m(d,*centre,rx,rx,outline=blend(c['art'],c['field'],.73),width=.7)
  paste_emblem(im,pre,.333,-.659,.248)
  d=ImageDraw.Draw(im)
  # Printed bonus cartouche: no new lamp geometry.
  bb=box_world(.3101,-.466,.202,.151)
  d.rounded_rectangle(bb,radius=9*S,fill=blend(c['field'],c['cap'],.17),outline=blend(c['art'],c['field'],.45),width=S)
  for x in (.203,.418): acorn_glyph(d,x,-.252,.040,c)
  # Finely lined path brackets around the side standups.
  for x in (.1722,.448):
   ellipse_m(d,x,-.815,.044,.056,outline=blend(c['art'],c['field'],.55),width=.8)
  acorn_glyph(d,.30,-1.292,.043,c)
 elif key=='rodent':
  # Sweeping speed/heat tracks under the long physical clear-orange wire ramp.
  for off in (0,.016,.032):
   pts=[(.08+off,-.58),(.12+off,-.83),(.19+off,-1.09),(.31,-1.27+off),(.49-off,-1.10),(.57-off,-.88),(.58-off,-.43)]
   line_m(d,pts,blend(c['ink'],c['field'],.68),.002)
  for j in range(26):
   x=rng.uniform(.04,.58);z=rng.uniform(-1.30,-.20)
   line_m(d,[(x,z+.010),(x+.003,z-.018)],blend(c['plastic'],c['field'],.80),.0010)
  paste_emblem(im,pre,.333,-1.148,.257)
  d=ImageDraw.Draw(im)
  # Heat-meter enclosure leaves all exact lamp centres unobstructed.
  bb=box_world(.3101,-.48,.055,.342)
  d.rounded_rectangle(bb,radius=12*S,fill=blend(c['field'],c['art'],.56),outline=c['ink'],width=S)
  for j in range(18):
   z=-.335-j*.017
   line_m(d,[(.349,z),(.356+(j%3==0)*.007,z)],blend(c['ink'],c['field'],.35),.001)
  # Low stylized flames in the open space above the flippers.
  for x,phase in ((.23,0),(.31,1),(.39,2)):
   poly_m(d,[(x-.026,-.20),(x-.016,-.244),(x-.005,-.23),(x+.008,-.278),(x+.023,-.215),(x+.025,-.20)],blend(c['ink'],c['field'],.52))
  for h in m['holes']:
   ellipse_m(d,*h['centre'],h['radius']+.009,h['radius']+.009,outline=c['ink'],width=1)
 elif key=='space':
  # Sparse stars and orbit linework: no cross/emblem symbols.
  for j in range(72):
   x=rng.uniform(.028,.595);z=rng.uniform(-1.33,-.16)
   rr=rng.choice([.0007,.001,.0014])
   ellipse_m(d,x,z,rr,rr,fill=blend(c['ink'],c['field'],.50))
  for rx,rz in ((.25,.355),(.265,.365),(.223,.30)):
   bb=box_world(.3101,-.978,rx*2,rz*2)
   d.arc(bb,185,355,fill=blend(c['plastic'],c['field'],.42),width=S)
  paste_emblem(im,pre,.310,-1.167,.300)
  d=ImageDraw.Draw(im)
  # Subtle flight-path chevrons in clear centre-lower field.
  for z in (-.240,-.275,-.305):
   line_m(d,[(.258,z+.010),(.3101,z-.009),(.362,z+.010)],blend(c['plastic'],c['field'],.60),.0014)
  for cx,cz,w,h in ((.3101,-.588,.163,.103),(.3101,-.448,.207,.060)):
   bb=box_world(cx,cz,w,h)
   d.rounded_rectangle(bb,radius=5*S,fill=blend(c['field'],c['art'],.26),outline=blend(c['plastic'],c['field'],.35),width=S)
  for hole in m['holes']:
   x,z=hole['centre'];r=hole['radius']
   ellipse_m(d,x,z,r+.005,r+.005,outline=c['plastic'],width=.8)
   line_m(d,[(x-.013,z+.022),(x,z+.006),(x+.013,z+.022)],c['ink'],.0016)
 # Bumper seat ornament is printed; the game places the separate bumper models.
 for b in m['bumpers']:
  x,z=b['centre'];r=b['body_radius']
  ellipse_m(d,x,z,r+.007,r+.007,outline=blend(c['art'],c['field'],.42),width=1.4)
  ellipse_m(d,x,z,r+.010,r+.010,outline=blend(c['ink'],c['field'],.44),width=.65)
 # Lane arrows keep the shooting direction legible.
 for z in (-.22,-.37,-.52,-.67):
  poly_m(d,[(.638,z+.008),(.647,z-.007),(.656,z+.008),(.650,z+.004),(.650,z+.019),(.644,z+.019),(.644,z+.004)],blend(c['ink'],c['field'],.32))
 # Lamp rings use the exact supplied radius, centre, and surface coordinate frame.
 for lamp in m['lamps']:
  x,z=lamp['centre'];r=lamp['radius']
  ellipse_m(d,x,z,r,r,fill=blend(c['field'],c['cap'],.07),outline=blend(c['field'],c['cap'],.35),width=1.2)
  ellipse_m(d,x,z,r*.83,r*.83,outline=blend(c['art'],c['field'],.52),width=.6)
 # Labels are the final paint layer and never change position to suit artwork.
 font=FONT_SERIF if key=='acorn' else FONT_SANS
 for word in m['painted_words']:
  x,z=word['centre'];w,h=word['width'],word['height'];box=box_world(x,z,w,h)
  single=len(word['text'])==1
  if key=='acorn':
   if not single:
    # Flat tan underprint preserves legibility over motif lines.
    d.rectangle((box[0]-S,box[1]-S,box[2]+S,box[3]+S),fill=blend(c['field'],c['cap'],.08))
   colour=c['art']
  else:
   if not single:
    d.rounded_rectangle((box[0]-S,box[1]-S,box[2]+S,box[3]+S),radius=2*S,fill=blend(c['field'],c['art'],.55))
   colour=c['cap'] if key=='rodent' else c['ink']
  lettering(im,word['text'],box,colour,font,shadow=None,fit=.98)
 im.convert('RGB').resize((W,H),Image.Resampling.LANCZOS).save(TEX/(pre+'_Board.png'),optimize=True)

def make_apron(key,m):
 pre=m['file_prefix'];c={k:rgb(v) for k,v in m['colours'].items()}
 aw,ah=1024,260
 im=Image.new('RGBA',(aw,ah),(*c['apron'],255));d=ImageDraw.Draw(im)
 d.rounded_rectangle((9,9,aw-9,ah-9),radius=14,outline=c['trim'],width=3)
 d.rounded_rectangle((17,17,aw-17,ah-17),radius=10,outline=blend(c['trim'],c['apron'],.58),width=1)
 font=FONT_SERIF if key=='acorn' else FONT_ITALIC if key=='rodent' else FONT_SANS
 lettering(im,m['title'],(92,57,932,160),c['ink'],font,fit=.96)
 # No score instructions or game claims; only the required title and benign FREE PLAY.
 lettering(im,'FREE PLAY',(425,195,599,222),blend(c['ink'],c['apron'],.25),FONT_MONO,fit=.96)
 for side in (0,1):
  cx=54 if side==0 else 970
  for off in (-23,-11,1,13,25):
   d.line((cx-14,128+off,cx+14,128+off),fill=blend(c['ink'],c['apron'],.50),width=2)
 im.convert('RGB').save(TEX/(pre+'_Apron.png'),optimize=True)

def make_backglass(key,m):
 pre=m['file_prefix'];c={k:rgb(v) for k,v in m['colours'].items()}
 bw,bh=854,1024
 dark=blend(c['body'],(3,4,8),.83)
 im=Image.new('RGBA',(bw,bh),(*dark,255))
 # A subtle full-theme watermark supplies the required emblem without competing
 # with Roblox's own title, live score, status, callouts, or best-score text.
 art=Image.open(ORIGINALS/(pre+'_Emblem.png')).convert('RGBA')
 art=art.crop(art.getchannel('A').getbbox())
 scale=min(820/art.width,795/art.height)
 art=art.resize((round(art.width*scale),round(art.height*scale)),Image.Resampling.LANCZOS)
 art.putalpha(art.getchannel('A').point(lambda a:round(a*.27)))
 im.alpha_composite(art,((bw-art.width)//2,170))
 d=ImageDraw.Draw(im)
 # Decorative colour is limited to the outer rails and small spaces between bands.
 d.rounded_rectangle((15,15,bw-16,bh-16),radius=37,outline=blend(c['trim'],dark,.52),width=2)
 d.rounded_rectangle((23,23,bw-24,bh-24),radius=30,outline=blend(c['ink'],dark,.76),width=1)
 for name,(top,bottom) in DATA['cabinet']['backglass_text_bands_from_top'].items():
  y0=round(top*bh);y1=round(bottom*bh)
  # Center is nearly uniform and very dark; faint artwork remains only at rails.
  layer=Image.new('RGBA',im.size);ld=ImageDraw.Draw(layer)
  ld.rounded_rectangle((61,y0,bw-61,y1),radius=13,fill=(*dark,155))
  im=Image.alpha_composite(im,layer);d=ImageDraw.Draw(im)
  linecol=blend(c['trim'],dark,.74)
  d.line((85,y0-5,bw-85,y0-5),fill=linecol,width=1)
  for x in (45,bw-45):
   # Quiet small geometric corner fittings, not bright logo marks.
   d.line((x,y0+8,x,y1-8),fill=blend(c['ink'],dark,.82),width=1)
 # Top and lower furniture/art accents sit outside the title/best reserved bands.
 for y in (11,1009):
  d.line((bw//2-58,y,bw//2+58,y),fill=blend(c['ink'],dark,.38),width=2)
  d.ellipse((bw//2-3,y-3,bw//2+3,y+3),fill=blend(c['ink'],dark,.35))
 im.convert('RGB').save(OUT/(pre+'_Backglass.png'),optimize=True)

def main():
 manifest={'board_dimensions':[W,H], 'board_world_bounds':{'x':[0,.672],'z':[-1.372,.0448]}, 'backglass_dimensions':[854,1024], 'backglass_text_bands_from_top':DATA['cabinet']['backglass_text_bands_from_top'], 'machines':{}}
 for key,m in DATA['machines'].items():
  make_board(key,m);make_apron(key,m);make_backglass(key,m)
  manifest['machines'][key]={'title':m['title'],'board_texture':m['file_prefix']+'_Board.png','apron_texture':m['file_prefix']+'_Apron.png','labels':m['painted_words'],'lamp_rings':m['lamps'],'emblem':'original image-generation illustration with exact layout applied from data'}
  print('Created',m['file_prefix'],'486x1024 board, 1024x260 apron, 854x1024 backglass')
 (SOURCE/'art_manifest.json').write_text(json.dumps(manifest,indent=2))

if __name__=='__main__':main()
