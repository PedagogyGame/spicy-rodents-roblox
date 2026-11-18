"""Build the Midnight Arcade whack-a-mole cabinet in Blender 4.3+.

Run: blender --background --python build_whack_a_mole.py -- --output /path/to/folder
Original procedural geometry. All dimensions are metres. No external textures.
"""
import bpy
import math
import os
import sys
import json
import struct
import argparse
from pathlib import Path
from mathutils import Vector

args = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
ap = argparse.ArgumentParser()
ap.add_argument('--output', default=str(Path(__file__).resolve().parent.parent))
ap.add_argument('--samples', type=int, default=48)
ap.add_argument('--skip-render', action='store_true')
opts = ap.parse_args(args)
OUT = Path(opts.output).resolve()
OUT.mkdir(parents=True, exist_ok=True)

bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for datablocks in (bpy.data.materials, bpy.data.curves, bpy.data.meshes, bpy.data.actions):
    for data in list(datablocks):
        if data.users == 0:
            datablocks.remove(data)

scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
scene.render.fps = 30
scene.frame_start = 1
scene.frame_end = 240
COLLS = {}
for name in ('01_Cabinet', '02_Moles', '03_Mallet', '04_Lettering', '05_Studio', '06_Lights_Cameras'):
    c = bpy.data.collections.new(name)
    scene.collection.children.link(c)
    COLLS[name] = c

def move_collection(obj, name):
    for c in list(obj.users_collection):
        c.objects.unlink(obj)
    COLLS[name].objects.link(obj)

def material(name, color, rough=.45, metal=0, emission=0, grain=False):
    m = bpy.data.materials.new(name)
    m.diffuse_color = (*color, 1)
    m.use_nodes = True
    bs = m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value = (*color, 1)
    bs.inputs['Roughness'].default_value = rough
    bs.inputs['Metallic'].default_value = metal
    if emission:
        bs.inputs['Emission Color'].default_value = (*color, 1)
        bs.inputs['Emission Strength'].default_value = emission
    if grain:
        tex = m.node_tree.nodes.new('ShaderNodeTexNoise')
        tex.inputs['Scale'].default_value = 95
        tex.inputs['Detail'].default_value = 2
        mapping = m.node_tree.nodes.new('ShaderNodeVectorMath')
        mapping.operation = 'MULTIPLY'
        mapping.inputs[1].default_value = (1, 1, .06)
        coord = m.node_tree.nodes.new('ShaderNodeTexCoord')
        bump = m.node_tree.nodes.new('ShaderNodeBump')
        bump.inputs['Strength'].default_value = .08
        bump.inputs['Distance'].default_value = .003
        m.node_tree.links.new(coord.outputs['Generated'], mapping.inputs[0])
        m.node_tree.links.new(mapping.outputs[0], tex.inputs['Vector'])
        m.node_tree.links.new(tex.outputs['Fac'], bump.inputs['Height'])
        m.node_tree.links.new(bump.outputs['Normal'], bs.inputs['Normal'])
    return m

M = {}
M['wood'] = material('Oxblood lacquered timber', (.095,.012,.017), .31, grain=True)
M['black'] = material('Ebony lacquer', (.016,.020,.022), .29)
M['brass'] = material('Warm brushed brass', (.63,.38,.12), .28, .78)
M['goldlight'] = material('Champagne trim', (.82,.64,.34), .23, .6)
M['cream'] = material('Warm ivory enamel', (.82,.73,.52), .37)
M['felt'] = material('Deep petrol leather deck', (.016,.063,.060), .69)
M['dark'] = material('Hole interiors', (.006,.007,.008), .85)
M['amber'] = material('Amber score phosphor', (1.0,.40,.065), .26, emission=1.5)
M['bulb'] = material('Warm marquee lamps', (1.0,.65,.25), .28, emission=2.0)
M['brown'] = material('Mole warm cocoa', (.21,.115,.063), .77)
M['taupe'] = material('Mole soft taupe', (.31,.23,.17), .79)
M['charcoal'] = material('Mole charcoal fur', (.10,.085,.08), .82)
M['muzzle'] = material('Mole muzzle velvet', (.58,.38,.25), .8)
M['nose'] = material('Mole rosy nose', (.34,.115,.10), .42)
M['eye'] = material('Mole glossy eyes', (.004,.005,.007), .12)
M['white'] = material('Eye catchlights', (.93,.89,.71), .25)
M['rubber'] = material('Mallet padded burgundy', (.19,.025,.035), .76)
M['floor'] = material('Studio blue charcoal', (.022,.029,.039), .61)
M['stage'] = material('Display plinth', (.043,.048,.052), .43)
M['green'] = material('Start button enamel', (.075,.32,.18), .28, .25)

def finish(o, name, mat, collection='01_Cabinet', bevel=0, smooth=False, parent=None):
    o.name = name
    if mat:
        o.data.materials.append(M[mat] if isinstance(mat,str) else mat)
    move_collection(o, collection)
    if bevel:
        mod = o.modifiers.new('Soft manufactured edges', 'BEVEL')
        mod.width = bevel
        mod.segments = 3
    if smooth and o.type == 'MESH':
        for p in o.data.polygons:
            p.use_smooth = True
    if parent:
        o.parent = parent
    return o

def cube(name, loc, size, mat, bevel=.01, collection='01_Cabinet', parent=None):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o = bpy.context.object
    o.dimensions = size
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(o, name, mat, collection, bevel, parent=parent)

def sphere(name, loc, scale, mat, collection='01_Cabinet', parent=None, segments=24):
    bpy.ops.mesh.primitive_uv_sphere_add(segments=segments, ring_count=12, radius=1, location=loc)
    o=bpy.context.object
    o.scale=scale
    bpy.ops.object.transform_apply(location=False, rotation=False, scale=True)
    return finish(o,name,mat,collection,smooth=True,parent=parent)

def cylinder(name, loc, radius, depth, mat, collection='01_Cabinet', rotation=(0,0,0), parent=None, vertices=48, bevel=.006):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices, radius=radius, depth=depth, location=loc, rotation=rotation)
    return finish(bpy.context.object,name,mat,collection,bevel,smooth=True,parent=parent)

def torus(name, loc, major, minor, mat, collection='01_Cabinet', rotation=(0,0,0), parent=None):
    bpy.ops.mesh.primitive_torus_add(major_segments=48,minor_segments=10,location=loc,rotation=rotation,major_radius=major,minor_radius=minor)
    return finish(bpy.context.object,name,mat,collection,smooth=True,parent=parent)

fonts = {}
for name,path in [('bold','/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf'),('serif','/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf'),('sans','/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf')]:
    if Path(path).exists():
        fonts[name] = bpy.data.fonts.load(path)

def text3d(name, body, loc, size, mat='cream', font='bold', rotation=(math.pi/2,0,0), align='CENTER', parent=None):
    curve = bpy.data.curves.new(name, 'FONT')
    curve.body = body
    curve.align_x = align
    curve.align_y = 'CENTER'
    curve.size = size
    curve.extrude = .0008
    curve.bevel_depth = .0003
    curve.bevel_resolution = 2
    if font in fonts:
        curve.font = fonts[font]
    o = bpy.data.objects.new(name,curve)
    COLLS['04_Lettering'].objects.link(o)
    o.location = loc
    o.rotation_euler = rotation
    curve.materials.append(M[mat])
    if parent:
        o.parent = parent
    return o

def empty(name, collection):
    o=bpy.data.objects.new(name,None)
    COLLS[collection].objects.link(o)
    o.empty_display_size=.08
    o.empty_display_type='PLAIN_AXES'
    return o

asset_root=empty('Whack_A_Mole_ASSET_ROOT','01_Cabinet')
asset_root['description']='Editable five-hole whack-a-mole cabinet. Metres, Z up.'
asset_root['version']='1.0'

# Hollow cabinet carcass: the moles retract into a real interior cavity.
cube('Lower plinth', (0,0,.125),(1.57,1.08,.17),'black',.035)
cube('Plinth brass reveal',(0,0,.216),(1.50,1.015,.018),'brass',.008)
cube('Interior floor',(0,0,.26),(1.42,.94,.065),'dark',.01)
cube('Front carved timber fascia',(0,-.473,.622),(1.43,.072,.78),'wood',.025)
cube('Rear timber wall',(0,.473,.622),(1.43,.072,.78),'wood',.025)
for x in (-.716,.716):
    cube('Left side panel' if x<0 else 'Right side panel',(x,0,.622),(.072,.95,.78),'wood',.025)
    cube('Side ebony inset',(x+(-.037 if x<0 else .037),0,.62),(.012,.68,.56),'black',.015)
    for y in (-.34,.34):
        cube('Side brass border',(x+(-.047 if x<0 else .047),y,.62),(.008,.012,.57),'brass',.003)
    for z in (.337,.903):
        cube('Side brass border',(x+(-.047 if x<0 else .047),0,z),(.008,.69,.012),'brass',.003)
    for y in (-.24,0,.24):
        cube('Side decorative rib',(x+(-.046 if x<0 else .046),y,.62),(.009,.008,.37),'goldlight',.002)

cube('Front inset leather panel',(0,-.515,.64),(1.21,.025,.58),'black',.022)
for x in (-.615,.615):
    cube('Front panel upright trim',(x,-.532,.64),(.014,.012,.59),'brass',.003)
for z in (.34,.94):
    cube('Front panel horizontal trim',(0,-.532,z),(1.24,.012,.014),'brass',.003)
for x in (-.51,-.46,-.41,.41,.46,.51):
    h=.25 if abs(x)>.49 else (.33 if abs(x)>.44 else .41)
    cube('Art deco front brass flute',(x,-.536,.64),(.009,.009,h),'brass',.002)
text3d('Maker badge','MIDNIGHT',(0,-.539,.827),.054,'goldlight','serif')
text3d('Maker small','A M U S E M E N T S',(0,-.539,.756),.020,'cream','sans')
cube('Coin door surround',(0,-.539,.55),(.295,.028,.27),'brass',.016)
cube('Coin door face',(0,-.557,.55),(.264,.013,.237),'black',.01)
cube('Coin slot plate',(0,-.569,.595),(.141,.013,.053),'cream',.006)
cube('Coin slot opening',(0,-.578,.595),(.079,.008,.009),'dark',.002)
cylinder('Coin return',(.07,-.577,.49),.023,.012,'brass',rotation=(math.pi/2,0,0),vertices=32)
text3d('Coin label','ONE GOOD ROUND',(0,-.571,.525),.016,'cream','sans')
for x in (-.6,.6):
    for y in (-.39,.39):
        cylinder('Adjustable foot',(x,y,.047),.062,.085,'black',vertices=24)

# Deck with true openings cut through both the timber and the leather surface.
holes=[(-.47,.205),(0,.205),(.47,.205),(-.245,-.275),(.245,-.275)]
deck=cube('Deck solid timber',(0,0,1.05),(1.62,1.13,.105),'wood',.025)
felt=cube('Deck petrol leather insert',(0,-.005,1.105),(1.53,1.035,.015),'felt',.018)
for target in (deck,felt):
    bpy.context.view_layer.objects.active=target
    for mod in list(target.modifiers):
        bpy.ops.object.modifier_apply(modifier=mod.name)
    for i,(x,y) in enumerate(holes,1):
        bpy.ops.mesh.primitive_cylinder_add(vertices=64,radius=.145,depth=.5,location=(x,y,1.06))
        cut=bpy.context.object
        cut.name='Temporary hole cutter'
        bpy.context.view_layer.objects.active=target
        mod=target.modifiers.new('Open hole %d'%i,'BOOLEAN')
        mod.operation='DIFFERENCE'
        mod.solver='EXACT'
        mod.object=cut
        bpy.ops.object.modifier_apply(modifier=mod.name)
        bpy.data.objects.remove(cut,do_unlink=True)

for x in (-.778,.778):
    cube('Deck brass edge rail',(x,-.005,1.118),(.009,1.055,.011),'brass',.003)
for y in (-.532,.522):
    cube('Deck brass edge rail',(0,y,1.118),(1.56,.009,.011),'brass',.003)
for i,(x,y) in enumerate(holes,1):
    torus('Hole_%02d_polished_lip'%i,(x,y,1.121),.153,.012,'brass')
    torus('Hole_%02d_inner_lip'%i,(x,y,1.110),.141,.005,'black')
    cylinder('Hole_%02d_dark_well_floor'%i,(x,y,.54),.143,.016,'dark',vertices=48)
    text3d('Hole_%02d_number'%i,str(i),(x,y-.196,1.121),.039,'cream',rotation=(0,0,0))

# Marquee, score windows and modest bulbs.
cube('Marquee timber case',(0,.514,1.61),(1.59,.185,1.10),'wood',.064)
cube('Marquee brass surround',(0,.412,1.63),(1.485,.018,.995),'brass',.055)
cube('Marquee ebony face',(0,.397,1.63),(1.445,.02,.955),'black',.045)
text3d('Header','T H E   M I D N I G H T   A R C A D E',(0,.378,2.036),.025,'goldlight','sans')
text3d('Title upper','WHACK',(0,.374,1.904),.168,'cream','serif')
text3d('Title lower','A MOLE',(0,.374,1.748),.146,'cream','serif')
for x in (-.56,.56):
    for z in (1.80,1.86,1.92):
        cube('Title deco bar',(x,.374,z),(.09,.008,.007),'brass',.002)
cube('Title divider',(0,.375,1.652),(1.20,.008,.008),'brass',.002)
for x,label in [(-.345,'SCORE'),(.345,'TIME')]:
    cube(label+' display brass frame',(x,.374,1.476),(.52,.024,.24),'brass',.019)
    cube(label+' display glass',(x,.354,1.476),(.484,.015,.206),'dark',.014)
    text3d(label+' heading',label,(x,.341,1.538),.027,'cream','sans')
text3d('Score_Text','030',(-.345,.339,1.453),.100,'amber')
text3d('Time_Text','45',(.345,.339,1.453),.100,'amber')
text3d('Status_Text','FIVE HOLES  /  ONE GOOD TIME',(0,.374,1.271),.027,'goldlight','sans')
for x in (-.678,.678):
    for z in (1.27,1.41,1.55,1.69,1.83,1.97):
        cylinder('Marquee bulb socket',(x,.375,z),.024,.016,'brass',rotation=(math.pi/2,0,0),vertices=24)
        sphere('Marquee warm bulb',(x,.357,z),(.015,.011,.015),'bulb',segments=16)
for x in (-.45,-.225,0,.225,.45):
    sphere('Top warm bulb',(x,.371,2.092),(.012,.010,.012),'bulb',segments=16)

# Friendly sculpted moles. Every visible part has a stable gameplay identifier.
mole_roots=[]
fur_choices=['brown','taupe','charcoal','taupe','brown']
for i,((x,y),fur) in enumerate(zip(holes,fur_choices),1):
    root=empty('Mole_%02d_ROOT'%i,'02_Moles')
    root.parent=asset_root
    root['mole_id']=i
    root['down_z']=0.0
    root['up_z']=.30
    root['hint']='Animate local Z 0.0 to 0.30 metres. Number key %d.'%i
    mole_roots.append(root)
    def part(name,loc,scale,mat):
        o=sphere('Mole_%02d_%s'%(i,name),loc,scale,mat,'02_Moles',root)
        o['mole_id']=i
        return o
    part('body',(x,y,.73),(.102,.094,.18),fur)
    part('head',(x,y,.911),(.118,.105,.114),fur)
    part('muzzle',(x,y-.083,.884),(.078,.038,.047),'muzzle')
    part('nose',(x,y-.122,.902),(.030,.022,.020),'nose')
    for side in (-1,1):
        part('ear_left' if side<0 else 'ear_right',(x+side*.104,y+.008,.969),(.025,.022,.031),fur)
        part('inner_ear_left' if side<0 else 'inner_ear_right',(x+side*.107,y-.011,.969),(.014,.006,.018),'muzzle')
        part('eye_left' if side<0 else 'eye_right',(x+side*.044,y-.089,.944),(.013,.009,.015),'eye')
        part('eye_glint',(x+side*.041,y-.097,.950),(.004,.0025,.004),'white')
        part('paw',(x+side*.075,y-.068,.817),(.032,.030,.025),'muzzle')
        for finger in (-1,0,1):
            part('paw_claw',(x+side*.075+finger*.012,y-.092,.817),(.004,.012,.005),'cream')
    # Small central teeth keep the characters friendly and readable.
    for tx in (-.010,.010):
        tooth=cube('Mole_%02d_tooth'%i,(x+tx,y-.117,.865),(.014,.013,.017),'cream',.003,'02_Moles',root)
        tooth['mole_id']=i

# Separate mallet, with the origin at its handle end for future gameplay.
mallet=empty('Mallet_ROOT','03_Mallet')
mallet.parent=asset_root
mallet['hint']='Pivot is the bottom of the handle. Padded ends; decorative demo animation.'
cylinder('Mallet walnut handle',(0,0,.285),.024,.57,'wood','03_Mallet',parent=mallet,vertices=32)
cylinder('Mallet brass collar',(0,0,.49),.033,.065,'brass','03_Mallet',parent=mallet,vertices=32)
cylinder('Mallet padded head',(0,0,.60),.098,.285,'rubber','03_Mallet',rotation=(0,math.pi/2,0),parent=mallet,vertices=48,bevel=.018)
for x in (-.15,.15):
    cylinder('Mallet ivory striking face',(x,0,.60),.090,.026,'cream','03_Mallet',rotation=(0,math.pi/2,0),parent=mallet,vertices=48,bevel=.008)
    torus('Mallet brass head band',(x*.80,0,.60),.097,.006,'brass','03_Mallet',rotation=(0,math.pi/2,0),parent=mallet)
for z in (.08,.11,.14,.17,.20):
    torus('Mallet handle grip',(0,0,z),.024,.004,'black','03_Mallet',parent=mallet)
rest=(1.12,-.25,.42)
mallet.location=rest
mallet.rotation_euler=(0,math.radians(-16),math.radians(-12))
cube('Mallet side bracket',(.865,-.25,.92),(.25,.10,.045),'brass',.012)

# Keyframed demonstration, deliberately separate from the optional play script.
windows={1:[(10,18,39,46),(74,82,111,119),(160,168,190,198)],2:[(28,34,36,44),(118,126,151,159),(203,211,227,235)],3:[(1,7,21,29),(84,92,119,127),(172,180,201,209)],4:[(48,56,79,87),(135,143,149,157),(210,218,233,240)],5:[(20,28,47,55),(80,88,107,115),(145,153,178,186)]}
for i,root in enumerate(mole_roots,1):
    root.location.z=0
    root.keyframe_insert(data_path='location',index=2,frame=1)
    for start,up,hold,end in windows[i]:
        for f,z in ((start,0),(up,.30),(hold,.30),(end,0)):
            root.location.z=z
            root.keyframe_insert(data_path='location',index=2,frame=f)
    root.location.z=0
    root.keyframe_insert(data_path='location',index=2,frame=240)
    root.animation_data.action.name='Demo_Mole_%02d'%i
    for fc in root.animation_data.action.fcurves:
        for k in fc.keyframe_points:
            k.interpolation='BEZIER'
            k.handle_left_type='AUTO_CLAMPED'
            k.handle_right_type='AUTO_CLAMPED'

# Mallet swings over the centre and returns to its bracket.
for frame,loc,rot in [
    (1,rest,(0,-16,-12)),(19,rest,(0,-16,-12)),
    (30,(0,-.359,1.63),(-50,0,0)),
    (36,(0,-.359,1.625),(-110,0,0)),
    (42,(0,-.359,1.63),(-50,0,0)),
    (58,rest,(0,-16,-12)),(128,rest,(0,-16,-12)),
    (141,(-.245,-.839,1.63),(-50,0,0)),
    (149,(-.245,-.839,1.625),(-110,0,0)),
    (155,(-.245,-.839,1.63),(-50,0,0)),
    (174,rest,(0,-16,-12)),(240,rest,(0,-16,-12))]:
    mallet.location=loc
    mallet.rotation_euler=tuple(math.radians(a) for a in rot)
    mallet.keyframe_insert(data_path='location',frame=frame)
    mallet.keyframe_insert(data_path='rotation_euler',frame=frame)
mallet.animation_data.action.name='Demo_Mallet'
for fc in mallet.animation_data.action.fcurves:
    for k in fc.keyframe_points:
        k.handle_left_type='AUTO_CLAMPED'
        k.handle_right_type='AUTO_CLAMPED'

for c in ('01_Cabinet','04_Lettering'):
    for o in COLLS[c].objects:
        if o != asset_root and o.parent is None:
            o.parent=asset_root

# Studio is deliberately separate and excluded from the game asset export.
cylinder('Studio circular plinth',(0,0,-.04),1.43,.08,'stage','05_Studio',vertices=96,bevel=.015)
torus('Plinth fine brass rim',(0,0,-.007),1.415,.004,'brass','05_Studio')
cube('Studio floor',(0,0,-.13),(200,200,.10),'floor',0,'05_Studio')

world=bpy.data.worlds.new('Midnight studio')
world.use_nodes=True
world.node_tree.nodes['Background'].inputs[0].default_value=(.055,.064,.085,1)
world.node_tree.nodes['Background'].inputs[1].default_value=.30
scene.world=world

def area(name,loc,power,color,size,target=(0,0,1.0)):
    data=bpy.data.lights.new(name,'AREA')
    data.energy=power
    data.color=color
    data.shape='DISK'
    data.size=size
    ob=bpy.data.objects.new(name,data)
    COLLS['06_Lights_Cameras'].objects.link(ob)
    ob.location=loc
    ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
    return ob

area('Key softbox',(1.3,-3.7,4.5),650,(1,.79,.55),3.2)
area('Cool broad fill',(-3,-1.7,2.9),480,(.63,.76,1),3.6)
area('Warm edge light',(2.0,2.7,3.8),850,(1,.47,.23),2.6)
area('Front letter fill',(0,-3.0,2.3),90,(1,.90,.75),2.4)

cam_data=bpy.data.cameras.new('Hero camera')
camera=bpy.data.objects.new('Hero camera',cam_data)
COLLS['06_Lights_Cameras'].objects.link(camera)
camera.location=(3.1,-4.6,3.05)
camera.rotation_euler=(Vector((0,0,1.06))-camera.location).to_track_quat('-Z','Y').to_euler()
cam_data.type='ORTHO'
cam_data.ortho_scale=3.05
cam_data.lens=52
scene.camera=camera
scene.render.engine='CYCLES'
scene.cycles.samples=opts.samples
scene.cycles.use_denoising=False  # Portable to Blender builds without OpenImageDenoise.
scene.cycles.max_bounces=6
scene.render.resolution_x=1280
scene.render.resolution_y=1440
scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
scene.render.film_transparent=False
scene.view_settings.view_transform='AgX'
scene.view_settings.look='AgX - Medium High Contrast'
scene.render.filepath=str(OUT/'Preview.png')

# Embed the user guide and source. Nothing executes automatically on opening.
for filename in ('README.txt','source/play_whack_a_mole.py','source/build_whack_a_mole.py'):
    path=OUT/filename
    if path.exists():
        txt=bpy.data.texts.load(str(path))
        txt.use_module=False
scene['README']='See README.txt in the Text Editor. Timeline: 8-second demo. Optional game script: source/play_whack_a_mole.py. No automatic scripts.'
scene['holes']=5
scene['play_mode']='Optional, explicitly run play_whack_a_mole.py; F3 > Play Whack a Mole.'
scene.frame_set(96)
bpy.ops.object.select_all(action='DESELECT')
asset_root.select_set(True)
bpy.context.view_layer.objects.active=asset_root
for screen in bpy.data.screens:
    for area_ in screen.areas:
        if area_.type=='VIEW_3D':
            sp=area_.spaces.active
            sp.shading.type='MATERIAL'
            sp.overlay.show_extras=False
            sp.overlay.show_overlays=False
            sp.region_3d.view_perspective='CAMERA'
            sp.region_3d.view_camera_zoom=14
        if area_.type=='TEXT_EDITOR' and 'README.txt' in bpy.data.texts:
            area_.spaces.active.text=bpy.data.texts['README.txt']
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(OUT/'Whack_A_Mole.blend'))

if not opts.skip_render:
    bpy.ops.render.render(write_still=True)

# Export an independent, portable hierarchy. Preserve the saved editable fonts.
bpy.ops.object.select_all(action='DESELECT')
asset_objects=[]
for cname in ('01_Cabinet','02_Moles','03_Mallet','04_Lettering'):
    asset_objects.extend(list(COLLS[cname].objects))
for ob in asset_objects:
    ob.select_set(True)
for ob in list(asset_objects):
    if ob.type=='FONT':
        bpy.context.view_layer.objects.active=ob
        bpy.ops.object.select_all(action='DESELECT')
        ob.select_set(True)
        bpy.ops.object.convert(target='MESH')
for cname in ('01_Cabinet','02_Moles','03_Mallet','04_Lettering'):
    for ob in COLLS[cname].objects:
        ob.select_set(True)
bpy.context.view_layer.objects.active=asset_root
kwargs=dict(filepath=str(OUT/'Whack_A_Mole.glb'),export_format='GLB',use_selection=True,export_apply=True,export_animations=True,export_frame_range=True,export_extras=True,export_yup=True,export_cameras=False,export_lights=False)
props=bpy.ops.export_scene.gltf.get_rna_type().properties
if 'export_animation_mode' in props:
    modes={e.identifier for e in props['export_animation_mode'].enum_items}
    if 'SCENE' in modes:
        kwargs['export_animation_mode']='SCENE'
if 'export_bake_animation' in props:
    kwargs['export_bake_animation']=True
bpy.ops.export_scene.gltf(**kwargs)

# Blender versions differ in how they split object actions. Merge the disjoint
# mole and mallet channels into one portable demonstration animation.
glb_path=OUT/'Whack_A_Mole.glb'
raw=glb_path.read_bytes()
chunks=[]
offset=12
while offset<len(raw):
    length,kind=struct.unpack_from('<II',raw,offset)
    chunks.append((kind,raw[offset+8:offset+8+length]))
    offset+=8+length
doc=json.loads(chunks[0][1])
clips=doc.get('animations',[])
if len(clips)>1:
    combined={'name':'Arcade_Demonstration','channels':[],'samplers':[]}
    seen=set()
    for clip in clips:
        sampler_offset=len(combined['samplers'])
        for channel in clip['channels']:
            target=(channel['target'].get('node'),channel['target']['path'])
            if target in seen:
                raise RuntimeError('Cannot combine overlapping animation channels')
            seen.add(target)
            item=dict(channel)
            item['sampler']+=sampler_offset
            combined['channels'].append(item)
        combined['samplers'].extend(clip['samplers'])
    doc['animations']=[combined]
    encoded=json.dumps(doc,separators=(',',':')).encode('utf-8')
    encoded+=b' '*((-len(encoded))%4)
    chunks[0]=(chunks[0][0],encoded)
    body=b''.join(struct.pack('<II',len(data),kind)+data for kind,data in chunks)
    glb_path.write_bytes(struct.pack('<4sII',b'glTF',2,12+len(body))+body)

counts={'objects':len(asset_objects),'mesh_objects':sum(o.type=='MESH' for o in asset_objects),'mole_roots':[o.name for o in mole_roots],'frames':240,'fps':30,'units':'metres','hero_frame':96,'blender_version':bpy.app.version_string}
(OUT/'Build_Info.json').write_text(json.dumps(counts,indent=2)+'\n')
print('WHACK_BUILD_COMPLETE',json.dumps(counts))
