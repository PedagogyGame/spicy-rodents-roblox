"""Create a labelled contact sheet from the final exported-asset renders."""
from pathlib import Path
from PIL import Image,ImageDraw,ImageFont
ROOT=Path(__file__).resolve().parents[2]
P=ROOT/'build/previews'
canvas=Image.new('RGB',(1880,1280),'#101923');d=ImageDraw.Draw(canvas)
fontdir=Path('/usr/share/fonts/truetype/dejavu')
def font(size,bold=False):
    path=fontdir/('DejaVuSans-Bold.ttf' if bold else 'DejaVuSans.ttf')
    return ImageFont.truetype(str(path),size) if path.exists() else ImageFont.load_default(size=size)
d.text((60,37),'SPICY RODENT  /  PINBALL COLLECTION',font=font(36,True),fill='#edf2f6')
d.text((61,91),'Finished visual assets, assembled from the exported GLB files',font=font(20),fill='#a1b2c2')
items=[('Acorn','ACORN ATTACK','Autumn oak / brass / warm walnut','#d8b36b'),
       ('Rodent','SPICY RODENT','Rising heat / red / orange','#ff8b55'),
       ('Space','SPACE SQUIRREL','Ringed planet / navy / ice blue','#8bd9f0')]
for i,(pre,title,sub,col) in enumerate(items):
    x=60+i*600
    d.rounded_rectangle((x-8,143,x+563,1181),radius=12,fill='#182431',outline='#344554',width=1)
    d.text((x+12,159),title,font=font(25,True),fill=col)
    d.text((x+12,195),sub,font=font(16),fill='#bec9d2')
    im=Image.open(P/(pre+'_Playfield_Preview.png')).convert('RGB')
    im=im.resize((540,960),Image.Resampling.LANCZOS)
    canvas.paste(im,(x+7,216))
d.text((60,1210),'21 GLB models  +  3 backglass images  |  Original art  |  Editable Blender sources',font=font(22),fill='#d8e2ea')
d.text((61,1244),'Blender previews. The existing game supplies the live score text, balls and lighting.',font=font(17),fill='#8fa3b5')
canvas.save(P/'Pinball_Playfields_Overview.png',optimize=True)
print(P/'Pinball_Playfields_Overview.png')
