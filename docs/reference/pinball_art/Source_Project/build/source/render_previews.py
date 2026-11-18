"""Assemble the finished GLBs at the supplied game coordinates for visual QA.

Preview-only scene: studio lights/floor are not exported as game assets.
Run Blender background with --python render_previews.py -- PACK BUILD [row|tables|parts].
"""
import bpy, math, json, sys
from pathlib import Path
from mathutils import Matrix,Vector

args=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
root=Path(__file__).resolve().parents[2]
pack=Path(args[0]) if args else root/'work/Pinball_ChatGPT_Pack'
build=Path(args[1]) if len(args)>1 else root/'build'
mode=args[2] if len(args)>2 else 'row'
models=build/'models';output=build/'previews';output.mkdir(parents=True,exist_ok=True)
D=json.loads((pack/'pinball_data.json').read_text())

def gb(v):return Vector((v[0],-v[2],v[1]))
def bg(v):return Vector((v[0],v[2],-v[1]))
def linear(v):return v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4
def rgba(h):return tuple(linear(int(h[i:i+2],16)/255) for i in (1,3,5))+(1,)

def material(name,col,metal=0,rough=.4):
    m=bpy.data.materials.new(name);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=rgba(col)
    p.inputs['Metallic'].default_value=metal;p.inputs['Roughness'].default_value=rough
    return m

def paint(ob,col):
    if not ob.data.materials:return
    m=ob.data.materials[0].copy();ob.data.materials.clear();ob.data.materials.append(m)
    p=m.node_tree.nodes.get('Principled BSDF')
    if p:p.inputs['Base Color'].default_value=rgba(col)
    m.diffuse_color=rgba(col)

def load(filename,tag,T=Matrix.Identity(4),colour=None):
    if not (models/filename).exists():return []
    before=set(bpy.context.scene.objects)
    bpy.ops.import_scene.gltf(filepath=str(models/filename))
    added=[o for o in bpy.context.scene.objects if o not in before and o.type=='MESH']
    for ob in added:
        original=ob.name.rsplit('.',1)[0] if ob.name.rsplit('.',1)[-1].isdigit() else ob.name
        ob['part_name']=original;ob.name=tag+'__'+original
        if colour and original in colour:paint(ob,colour[original])
        ob.matrix_world=T @ ob.matrix_world
    return added

def point_camera(pos,target,scale,lens=50):
    data=bpy.data.cameras.new('Studio camera');ob=bpy.data.objects.new('Studio camera',data)
    bpy.context.collection.objects.link(ob);ob.location=pos
    ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler()
    data.type='ORTHO';data.ortho_scale=scale;data.lens=lens
    bpy.context.scene.camera=ob
    return ob

def light(name,pos,power,size,target):
    d=bpy.data.lights.new(name,'AREA');d.energy=power;d.shape='DISK';d.size=size
    o=bpy.data.objects.new(name,d);bpy.context.collection.objects.link(o);o.location=pos
    o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()

def setup(width,height):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc=bpy.context.scene
    sc.render.engine='CYCLES';sc.cycles.samples=96;sc.cycles.use_denoising=False
    sc.cycles.max_bounces=8;sc.cycles.transparent_max_bounces=16
    sc.render.resolution_x=width;sc.render.resolution_y=height;sc.render.resolution_percentage=100
    sc.render.image_settings.file_format='PNG';sc.render.image_settings.color_mode='RGB'
    sc.view_settings.view_transform='AgX'
    sc.render.threads_mode='FIXED';sc.render.threads=8
    world=bpy.data.worlds.new('Studio atmosphere');sc.world=world;world.use_nodes=True
    world.node_tree.nodes['Background'].inputs['Color'].default_value=(.27,.32,.42,1)
    world.node_tree.nodes['Background'].inputs['Strength'].default_value=.45

def add_backglass(ob,image):
    if not image.exists():return
    # The supplied PNG is applied only in this staged preview; the deliverable
    # Cabinet GLB remains untextured, ready for the game's own image and score.
    uv=ob.data.uv_layers.new(name='PreviewBackglassUV')
    for poly in ob.data.polygons:
        for li in poly.loop_indices:
            p=bg(ob.matrix_world @ ob.data.vertices[ob.data.loops[li].vertex_index].co)
            uv.data[li].uv=((p.x+.3444)/.6888,(p.y-1.288)/.826)
    m=bpy.data.materials.new('Preview artwork '+image.stem);m.use_nodes=True
    bs=m.node_tree.nodes.get('Principled BSDF');tex=m.node_tree.nodes.new('ShaderNodeTexImage')
    tex.image=bpy.data.images.load(str(image.resolve()));m.node_tree.links.new(tex.outputs['Color'],bs.inputs['Base Color'])
    bs.inputs['Roughness'].default_value=.38
    ob.data.materials.clear();ob.data.materials.append(m)

def playfield(machine,T=Matrix.Identity(4),tag=None):
    m=D['machines'][machine];pre=m['file_prefix'];tag=tag or pre;c=m['colours']
    for tail in ('Playfield','Guides','Slingshots','Targets'):
        load(pre+'_'+tail+'.glb',tag+'_'+tail,T)
    for fn in {'acorn':['Acorn_Spinner.glb'],'rodent':['Rodent_Wire.glb'],'space':['Space_Ramps.glb','Space_PodHoods.glb']}[machine]:
        load(fn,tag+'_'+Path(fn).stem,T)
    for i,f in enumerate(m['flippers']):
        x,z=f['pivot'];zrot=math.radians(-30 if f['side']=='L' else 30)
        mirror=Matrix.Diagonal((-1,1,1,1)) if f['side']=='R' else Matrix.Identity(4)
        transform=Matrix.Translation(gb((x,.0098,z))) @ Matrix.Rotation(zrot,4,'Z') @ mirror
        load('Pinball_Flipper.glb',tag+f'_Flipper{i+1}',T @ transform)
    for i,b in enumerate(m['bumpers']):
        x,z=b['centre'];scale=b['body_radius']/.0336
        transform=Matrix.Translation(gb((x,0,z))) @ Matrix.Diagonal((scale,scale,1,1))
        load('Pinball_PopBumper.glb',tag+f'_Bumper{i+1}',T @ transform,{'Body':c['bumper'],'Cap':c['cap']})
    for i,g in enumerate(m['gates']):
        a,b=g['a'],g['b'];pos=((a[0]+b[0])/2,g['top'],(a[1]+b[1])/2)
        ang=math.atan2(-(b[1]-a[1]),b[0]-a[0])
        load('Pinball_Gate.glb',tag+f'_Gate{i+1}',T @ Matrix.Translation(gb(pos)) @ Matrix.Rotation(ang,4,'Z'))

def cabinet(machine,xoff=0):
    m=D['machines'][machine];pre=m['file_prefix'];c=m['colours'];T=Matrix.Translation((xoff,0,0))
    cols={n:c['body'] for n in ['Body','SideWall_L','SideWall_R','FrontWall','BackWall','Backbox']}
    for n in ['LockdownBar','Deco_SideRails','Deco_CabinetPinstripe','Deco_AccessDoorBezel','Deco_BackboxBezel','Deco_CornerPlates','Deco_ButtonCollars']:cols[n]=c['trim']
    for n in ['Leg_FL','Leg_FR','Leg_BL','Leg_BR','Deco_Fasteners']:cols[n]=c['legs']
    cols['LightStrip']=c['cap']
    obs=load('Pinball_Cabinet.glb',pre+'_Cabinet',colour=cols)
    for ob in obs:
        if ob.get('part_name')=='Backglass':add_backglass(ob,models/(pre+'_Backglass.png'))
        ob.matrix_world=T @ ob.matrix_world
    tilt=Matrix.Rotation(math.radians(D['cabinet']['tilt_deg']),4,'X')
    P=T @ Matrix.Translation(gb(D['cabinet']['playfield_front_left_corner'])) @ tilt
    playfield(machine,P,pre)
    load('Pinball_Plunger.glb',pre+'_Plunger',T @ Matrix.Translation(gb(D['cabinet']['plunger_knob_centre'])) @ tilt)

def render(name):
    bpy.context.scene.render.filepath=str(output/name)
    bpy.ops.render.render(write_still=True)
    print('RENDERED',str(output/name),flush=True)

def row():
    setup(1800,1320)
    for machine,x in [('acorn',-1.13),('rodent',0),('space',1.13)]:cabinet(machine,x)
    bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.012))
    floor=bpy.context.object;floor.name='Preview_studio_floor';floor.data.materials.append(material('Studio floor','#202b37',rough=.48))
    light('Large softbox',(-3,-4,6),500,4,(0,0,1))
    light('Right fill',(4,-1,4),360,3,(0,0,1))
    light('Back rim',(0,4,5),600,3,(0,0,1.2))
    point_camera((3.9,-6,4.6),(0,0,1.05),4.7)
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(build/'source/Pinball_Preview_Assembly.blend'),compress=True)
    render('Pinball_Three_Machines.png')

def tables():
    for machine in ([args[3]] if len(args)>3 else ['acorn','rodent','space']):
        setup(900,1600);pre=D['machines'][machine]['file_prefix']
        playfield(machine)
        # Pure overhead view makes all label placements and machinery visible.
        point_camera((.336,.686,3),(.336,.686,0),1.57)
        bpy.context.scene.camera.rotation_euler=(0,0,0)
        light('Overhead softbox',(-.5,.1,2.8),42,2,(.336,.686,0))
        light('Edge softbox',(1.5,1.2,1.5),24,1.4,(.336,.686,0))
        bpy.ops.mesh.primitive_plane_add(size=200,location=(0,0,-.05))
        bpy.context.object.data.materials.append(material('Dark tabletop surround','#111924',rough=.6))
        render(pre+'_Playfield_Preview.png')

def parts():
    setup(1100,900)
    load('Pinball_Cabinet.glb','Cabinet')
    light('Key',(-3,-4,5),900,3,(0,0,1))
    light('Fill',(3,-2,2.5),500,2,(0,0,1))
    point_camera((1.6,-3.2,1.5),(0,-.4,.9),.8)
    render('Cabinet_Detail.png')

if mode=='row':row()
elif mode=='tables':tables()
elif mode=='parts':parts()
