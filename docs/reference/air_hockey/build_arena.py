"""AER / 01 — original procedural Blender source. Run with Blender --background --python."""
import bpy, math, json, sys
from pathlib import Path
from mathutils import Vector, Matrix

HERE = Path(__file__).resolve().parent
ROOT = HERE.parent if HERE.name=='SourceArt' else HERE.parent / 'outputs' / 'AER_AirHockey'
ART = ROOT / 'SourceArt'
ART.mkdir(parents=True, exist_ok=True)
bpy.ops.object.select_all(action='SELECT')
bpy.ops.object.delete(use_global=False)
for d in list(bpy.data.materials): bpy.data.materials.remove(d)
scene = bpy.context.scene
scene.unit_settings.system = 'METRIC'
scene.unit_settings.scale_length = 1.0
asset = bpy.data.collections.new('AER | Game asset')
scene.collection.children.link(asset)
studio = bpy.data.collections.new('Studio | presentation only')
scene.collection.children.link(studio)
materials = []

def material(name, color, metal=0, rough=.4, glow=0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    n = next(n for n in m.node_tree.nodes if n.type == 'BSDF_PRINCIPLED')
    n.inputs['Base Color'].default_value = (*color, 1)
    n.inputs['Metallic'].default_value = metal
    n.inputs['Roughness'].default_value = rough
    n.inputs['Emission Color'].default_value = (*color, 1)
    n.inputs['Emission Strength'].default_value = glow
    m.diffuse_color = (*color, 1)
    m['spec'] = json.dumps(dict(name=name,color=list(color),metal=metal,rough=rough,glow=glow))
    materials.append(m)
    return m

shell = material('01 | Midnight ceramic', (.018,.033,.050), .55,.29)
black = material('02 | Soft black rubber', (.008,.013,.020), .05,.62)
metal = material('03 | Satin titanium', (.29,.38,.43), .85,.23)
ice = material('04 | Porcelain ice', (.67,.82,.85), .27,.25)
cyan = material('05 | Glacier cyan', (.015,.66,.82), .3,.24)
coral = material('06 | Ember coral', (.95,.12,.09), .3,.24)
ledc = material('07 | Cyan light', (.015,.70,1), .1,.3,3)
ledr = material('08 | Coral light', (1,.10,.055), .1,.3,3)
white = material('09 | Warm white light', (.85,.95,1), .1,.3,1.8)
ink = material('10 | Printed slate', (.075,.19,.25), .15,.42)
holemat = material('11 | Air perforations', (.11,.24,.28), .1,.6)
brass = material('12 | Champagne alloy', (.52,.35,.16), .8,.27)
puckmat = material('13 | Puck carbon', (.021,.027,.035), .25,.22)

def move_collection(o, coll):
    for c in list(o.users_collection): c.objects.unlink(o)
    coll.objects.link(o)

def finish(o,name,mat,part='table',coll=asset):
    o.name=name
    move_collection(o,coll)
    o.data.materials.append(mat)
    o['part']=part
    return o

def box(name, loc, size, mat, bevel=.012, part='table',coll=asset):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc)
    o=bpy.context.object
    o.dimensions=size
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    finish(o,name,mat,part,coll)
    if bevel:
        m=o.modifiers.new('Soft machined edges','BEVEL');m.width=bevel;m.segments=3
        o.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
    return o

def cyl(name,loc,r,depth,mat,part='table',vertices=64):
    bpy.ops.mesh.primitive_cylinder_add(vertices=vertices,radius=r,depth=depth,location=loc)
    o=finish(bpy.context.object,name,mat,part)
    m=o.modifiers.new('Rolled edge','BEVEL');m.width=min(.004,depth*.22);m.segments=3
    o.modifiers.new('Weighted normals','WEIGHTED_NORMAL')
    return o

def ring(name,loc,r,minor,mat,part='table'):
    bpy.ops.mesh.primitive_torus_add(major_radius=r,minor_radius=minor,major_segments=96,minor_segments=8,location=loc)
    o=finish(bpy.context.object,name,mat,part)
    for p in o.data.polygons:p.use_smooth=True
    return o

def label(name,text,loc,size,mat,rot=(0,0,0),align='CENTER',part='table'):
    bpy.ops.object.text_add(location=loc,rotation=rot)
    o=bpy.context.object;o.name=name
    o.data.body=text;o.data.size=size;o.data.align_x=align;o.data.align_y='CENTER'
    o.data.extrude=.00035;o.data.bevel_depth=.00012
    bpy.ops.object.convert(target='MESH')
    return finish(bpy.context.object,name,mat,part)

# A broad sculpted chassis over two architectural sled supports.
box('Cabinet | ceramic monocoque',(0,0,.731),(1.49,2.62,.254),shell,.075)
box('Cabinet | lower shadow seam',(0,0,.610),(1.40,2.50,.045),black,.022)
box('Cabinet | champagne reveal',(0,0,.846),(1.455,2.585,.018),brass,.032)
box('Floating bed | aluminum tray',(0,0,.870),(1.39,2.49,.040),metal,.035)
box('Playing surface | 1240 x 2340 mm',(0,0,.888),(1.24,2.34,.024),ice,.012)
for y in [-.84,.84]:
    for x in [-.50,.50]:
        o=box('Tapered support',(x,y,.344),(.12,.19,.535),shell,.025)
        o.rotation_euler[1]=-.12 if x<0 else .12
        box('Support | metal collar',(x+(.024 if x<0 else -.024),y,.15),(.125,.20,.095),metal,.018)
    box('Sled | crossbar',(0,y,.080),(1.25,.27,.12),shell,.048)
    for x in [-.49,.49]:
        box('Non-slip foot',(x,y,.019),(.23,.23,.038),black,.015)
        box('Foot | illuminated accent',(x,y-.138,.079),(.18,.007,.017),ledc if y<0 else ledr,.004)

# Rails, inset bumpers and real openings for both goals.
for x in [-.685,.685]:
    box('Side rail | ceramic',(x,0,.932),(.13,2.57,.115),shell,.027)
    box('Side rail | titanium top',(x,0,.991),(.105,2.51,.009),metal,.004)
    box('Low friction cushion',(math.copysign(.628,x),0,.925),(.016,2.34,.036),black,.003)
    for s in [-1,1]:
        box('Side LED | split team',(x,s*.609,.981),(.011,1.184,.012),ledc if s<0 else ledr,.004)
    box('Undercabinet light',(math.copysign(.739,x),0,.645),(.008,2.34,.012),ledc,.003)
    for j in range(13):
        box('Side cooling fin',(math.copysign(.746,x),-.48+j*.08,.749),(.004,.042,.065),black,.006)
    label('Side badge','A E R   /   0 1',(x*1.091,0,.775),.048,metal,(math.pi/2,0,math.copysign(math.pi/2,x)))
for s in [-1,1]:
    team=ledc if s<0 else ledr
    for x in [-.485,.485]:
        box('End rail | goal shoulder',(x,s*1.235,.932),(.53,.13,.115),shell,.025)
        box('End rail | metal top',(x,s*1.235,.991),(.49,.105,.009),metal,.004)
        box('End rail | team light',(x,s*1.235,.981),(.45,.011,.012),team,.004)
        box('End cushion',(x,s*1.178,.925),(.53,.016,.036),black,.003)
    box('Goal | dark mouth',(0,s*1.219,.886),(.432,.10,.014),black,.004)
    box('Goal | bridge',(0,s*1.247,.980),(.454,.09,.035),shell,.012)
    box('Goal | luminous lintel',(0,s*1.199,.973),(.405,.007,.009),team,.002)
    box('Goal | return pocket',(0,s*1.312,.739),(.48,.012,.102),black,.017)
    box('Goal | return lip',(0,s*1.326,.694),(.46,.035,.012),metal,.005)
    label('Goal return label','PUCK RETURN',(0,s*1.320,.810),.025,metal,(math.pi/2 if s<0 else -math.pi/2,0,0 if s<0 else math.pi))
    for x in [-.22,.22]:
        cyl('Rounded goal post',(x,s*1.17,.925),.012,.055,metal)
    for x in [-.685,.685]:
        for y in [s*1.12,s*.93]:
            cyl('Recessed rail fastener',(x,y,.999),.010,.003,black,vertices=16)
            box('Fastener slot',(x,y,1.001),(.011,.0017,.001),metal,.0004)

# Precisely spaced perforations are real geometry, merged into one light mesh.
verts=[];faces=[]
for ix in range(-14,15):
    for iy in range(-28,29):
        x=ix*.041;y=iy*.040
        if abs(x)<.25 and abs(y)<.25: continue
        k=len(verts)
        for n in range(6):
            a=n*math.tau/6;verts.append((x+math.cos(a)*.00112,y+math.sin(a)*.00112,.90035))
        faces.append(tuple(range(k,k+6)))
mesh=bpy.data.meshes.new('Perforation pattern');mesh.from_pydata(verts,[],faces);mesh.update()
o=bpy.data.objects.new('1,500 precision air jets',mesh);asset.objects.link(o);o.data.materials.append(holemat);o['part']='table'

# Inlaid sport graphics. Nothing floats above the mallet/puck contact plane.
for x in [-.596,.596]:box('Field | touchline',(x,0,.9007),(.003,2.29,.0005),ink,.0001)
box('Field | centre line',(0,0,.9008),(1.19,.004,.0005),ink,.0001)
ring('Field | centre circle',(0,0,.9008),.205,.002,ink)
ring('Field | faceoff ring',(0,0,.901),.066,.0014,ink)
cyl('Field | faceoff spot',(0,0,.901),.009,.0007,cyan,vertices=32)
for s in [-1,1]:
    # Clip the defensive circle to the playable bed; it must not cross the goal opening.
    curve=bpy.data.curves.new('Defensive arc','CURVE');curve.dimensions='3D';curve.bevel_depth=.002;curve.bevel_resolution=2
    points=[]
    for j in range(145):
        a=math.pi+math.pi*j/144 if s>0 else math.pi*j/144
        points.append((.29*math.cos(a),s*1.05+.29*math.sin(a),.9008,1))
    spline=curve.splines.new('POLY');spline.points.add(len(points)-1)
    for p,v in zip(spline.points,points):p.co=v
    o=bpy.data.objects.new('Field | defensive arc',curve);asset.objects.link(o);o.data.materials.append(cyan if s<0 else coral);o['part']='table'
    bpy.context.view_layer.objects.active=o;o.select_set(True);bpy.ops.object.convert(target='MESH');o.select_set(False)
    for x in [-.46,.46]:
        box('Field | service hash',(x,s*.76,.901),(.042,.002,.0005),ink,.0001)
    label('Field | team index','01' if s<0 else '02',(-.49,s*1.02,.901),.072,cyan if s<0 else coral,(0,0,0 if s<0 else math.pi))
label('Field | AER logotype','A E R',(0,-.405,.901),.072,ink)
label('Field | fine print','PRECISION AIR SYSTEM   /   01',(0,.405,.901),.016,ink,(0,0,math.pi))

def mallet(part,y,col,led):
    cyl(part+' | felt',(0,y,.904),.064,.008,black,part)
    cyl(part+' | weighted base',(0,y,.918),.063,.023,col,part)
    ring(part+' | light seam',(0,y,.924),.059,.0022,led,part)
    cyl(part+' | concave crown',(0,y,.933),.048,.010,shell,part)
    cyl(part+' | grip stem',(0,y,.957),.022,.049,col,part)
    cyl(part+' | ergonomic cap',(0,y,.986),.030,.016,col,part)
    ring(part+' | grip collar',(0,y,.977),.023,.002,black,part)
    cyl(part+' | cap inset',(0,y,.995),.020,.002,black,part)
mallet('malletA',-.78,cyan,ledc)
mallet('malletB',.78,coral,ledr)
cyl('puck | carbon disc',(0,0,.912),.032,.020,puckmat,'puck')
ring('puck | luminous equator',(0,0,.913),.032,.0016,white,'puck')
cyl('puck | crown',(0,0,.923),.025,.001,brass,'puck',48)
label('puck | insignia','A',(0,0,.924),.026,puckmat,part='puck')

# First-person positions are named and exported with the asset.
def camera(name,loc,target,lens=42,coll=studio):
    data=bpy.data.cameras.new(name);o=bpy.data.objects.new(name,data);coll.objects.link(o);o.location=loc
    o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler();data.lens=lens
    return o
camera('Player_01 | first person',(0,-1.70,1.58),(0,.20,.90),27,asset)
camera('Player_02 | first person',(0,1.70,1.58),(0,-.20,.90),27,asset)
hero=camera('AER | hero',(3.25,-4.30,3.20),(0,0,.64),47)
scene.camera=hero
floor=material('Studio | charcoal',(.018,.026,.039),.3,.37)
box('Studio floor',(0,0,-.028),(200,200,.05),floor,.001,coll=studio)
def area(name,loc,color,power,size,target=(0,0,.65)):
    d=bpy.data.lights.new(name,'AREA');d.energy=power;d.color=color;d.shape='DISK';d.size=size
    o=bpy.data.objects.new(name,d);studio.objects.link(o);o.location=loc
    o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
area('Key | broad softbox',(0,-.5,4.8),(.79,.9,1),800,4)
area('Cyan rim',(-2.4,.6,2.2),(.05,.65,1),380,3)
area('Ember rim',(2.2,2.2,2.7),(1,.3,.18),500,2.5)
area('Front fill',(1,-3,1.6),(.6,.8,1),140,2)
world=bpy.data.worlds.new('AER | night studio');world.use_nodes=True
bg=next(n for n in world.node_tree.nodes if n.type=='BACKGROUND');bg.inputs['Color'].default_value=(.035,.05,.08,1);bg.inputs['Strength'].default_value=.3
scene.world=world
scene.render.resolution_x=1600;scene.render.resolution_y=1400;scene.render.resolution_percentage=100
try:scene.render.engine='CYCLES'
except TypeError as e: print(e);raise
scene.cycles.samples=48;scene.cycles.use_denoising=True
scene.view_settings.view_transform='AgX'
scene.render.image_settings.file_format='PNG'
scene.render.filepath=str(ROOT/'AER_Hero.png')
scene['Design']='AER / 01 | original air hockey arena'
scene['Physics']='Bed z=.90 m; rink x=+/- .62 m, y=+/- 1.17 m; goal half width .22 m'

# Export evaluated geometry in Blender coordinates for both native and portable runtimes.
origins={'table':Vector((0,0,0)),'malletA':Vector((0,-.78,.90)),'malletB':Vector((0,.78,.90)),'puck':Vector((0,0,.90))}
specs=[json.loads(m['spec']) for m in materials if 'spec' in m and not m.name.startswith('Studio')]
mat_ids={m.name:i for i,m in enumerate(materials) if not m.name.startswith('Studio')}
groups={k:{} for k in origins}
deps=bpy.context.evaluated_depsgraph_get()
for obj in asset.objects:
    if obj.type!='MESH':continue
    part=obj.get('part','table');ev=obj.evaluated_get(deps);me=ev.to_mesh();me.calc_loop_triangles()
    nm=obj.matrix_world.to_3x3().inverted().transposed()
    for tri in me.loop_triangles:
        mat=me.materials[tri.material_index]
        mid=mat_ids[mat.name]
        sec=groups[part].setdefault(mid,dict(material=mid,positions=[],normals=[],indices=[],_lookup={}))
        for vi,li in zip(tri.vertices,tri.loops):
            p=obj.matrix_world@me.vertices[vi].co-origins[part]
            normal=(nm@me.corner_normals[li].vector).normalized()
            key=tuple(round(v,6) for v in (*p,*normal))
            idx=sec['_lookup'].get(key)
            if idx is None:
                idx=len(sec['positions'])//3;sec['_lookup'][key]=idx
                sec['positions'].extend(round(v,6) for v in p);sec['normals'].extend(round(v,6) for v in normal)
            sec['indices'].append(idx)
    ev.to_mesh_clear()
for sections in groups.values():
    for sec in sections.values():del sec['_lookup']
payload=dict(title='AER / 01',units='metres',materials=specs,parts={k:list(v.values()) for k,v in groups.items()})
data=ROOT/'Unreal'/'Content'/'Data'/'Arena.json';data.parent.mkdir(parents=True,exist_ok=True)
data.write_text(json.dumps(payload,separators=(',',':')))

# Named pivots keep the table and the three playable pieces easy to use in any engine.
for part,title in [('table','Table_Static'),('malletA','Mallet_Glacier'),('malletB','Mallet_Ember'),('puck','Puck_Dynamic')]:
    pivot=bpy.data.objects.new(title,None);asset.objects.link(pivot);pivot.location=origins[part]
    pivot['part']=part
    for obj in list(asset.objects):
        if obj.type=='MESH' and obj.get('part')==part:
            mw=obj.matrix_world.copy();obj.parent=pivot
            obj.matrix_parent_inverse=Matrix.Identity(4)
            obj.matrix_basis=Matrix.Translation(-origins[part])@mw
bpy.context.view_layer.update()

bpy.ops.object.select_all(action='DESELECT')
for o in asset.objects:o.select_set(True)
bpy.ops.export_scene.gltf(filepath=str(ROOT/'AER_AirHockey.glb'),use_selection=True,export_apply=True,export_cameras=True,export_extras=True)
bpy.ops.wm.save_as_mainfile(filepath=str(ART/'AER_AirHockey.blend'))
print('ASSET_READY',len(asset.objects),'objects',sum(len(s['indices'])//3 for p in payload['parts'].values() for s in p),'triangles',flush=True)
bpy.ops.render.render(write_still=True)
print('RENDER_READY',scene.render.filepath,flush=True)
