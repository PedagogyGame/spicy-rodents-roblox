"""Create seven original, fully assembled low-poly skateboard assets in Blender."""
import bpy, math, json, sys
from pathlib import Path
from mathutils import Vector

HERE = Path(__file__).resolve().parent
BASE = HERE.parent if HERE.name == 'Source' else HERE.parent/'Spicy_Rodent_Underground'
GLB = BASE/'GLB'/'Skateboards'
TEX = BASE/'Textures'/'Skateboards'
SOURCE = BASE/'Source'
PREVIEW = BASE/'Previews'
for d in (GLB, SOURCE, PREVIEW): d.mkdir(parents=True,exist_ok=True)
NAMES=['Lunar_Moth','Static_Weekend','Ochre_Run','Concrete_Fern','Tidal_Check','Ghost_Fish','Violet_Comet']
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
scene.unit_settings.system='METRIC'
scene.unit_settings.scale_length=1
scene.name='Seven_Assembled_Skateboards'

def mat(name,color,roughness=.55,metallic=0,image=None):
    m=bpy.data.materials.new(name);m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*color,1)
    p.inputs['Roughness'].default_value=roughness
    p.inputs['Metallic'].default_value=metallic
    m.diffuse_color=(*color,1)
    if image:
        tex=m.node_tree.nodes.new('ShaderNodeTexImage');tex.image=bpy.data.images.load(str(image),check_existing=True)
        tex.image.pack();m.node_tree.links.new(tex.outputs['Color'],p.inputs['Base Color'])
    return m
grip=mat('Grip_Charcoal',(0.04,.045,.045),.96,image=TEX/'grip.png')
maple=mat('Maple_Ply_Edge',(.47,.25,.095),.63)
truck=mat('Brushed_Aluminium',(.48,.53,.56),.32,.78)
dark=mat('Dark_Fasteners',(.035,.042,.045),.42,.65)
bushing=mat('Truck_Rubber_Bushings',(.10,.12,.13),.76)
hub=mat('Wheel_Core',(.20,.23,.24),.43,.45)
collections=[];roots=[];report=[]

def link(obj,col):
    for c in list(obj.users_collection):c.objects.unlink(obj)
    col.objects.link(obj)
    return obj

def cube(name,loc,scale,material,col):
    bpy.ops.mesh.primitive_cube_add(size=1,location=loc)
    obj=bpy.context.object;obj.name=name;obj.dimensions=scale
    bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    obj.data.materials.append(material);link(obj,col)
    return obj

def cylinder(name,a,b,r,material,col,n=8):
    a,b=Vector(a),Vector(b)
    bpy.ops.mesh.primitive_cylinder_add(vertices=n,radius=r,depth=(b-a).length,end_fill_type='NGON',location=(a+b)*.5)
    obj=bpy.context.object;obj.name=name;obj.rotation_euler=(b-a).to_track_quat('Z','Y').to_euler()
    bpy.ops.object.transform_apply(location=False,rotation=True,scale=True)
    obj.data.materials.append(material);link(obj,col)
    return obj

def join(objects,name):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objects:o.select_set(True)
    bpy.context.view_layer.objects.active=objects[0]
    bpy.ops.object.join()
    out=bpy.context.object;out.name=name
    bpy.context.scene.cursor.location=(0,0,0)
    bpy.ops.object.origin_set(type='ORIGIN_CURSOR')
    return out

def deck(name,print_material,col):
    ys=[-.41,-.4,-.38,-.35,-.3,-.2,-.1,0,.1,.2,.3,.35,.38,.4,.41]
    nx=5;ny=len(ys);verts=[];uvs=[]
    for layer in range(2):
        for y in ys:
            t=max(0,(abs(y)-.30)/.11)
            half=.105*math.sqrt(max(.03,1-t*t))
            up=.034*t*t
            for j in range(nx):
                s=2*j/(nx-1)-1
                x=s*half
                z=.092+.008*layer+up+.005*s*s
                verts.append((x,y,z));uvs.append((x/.21+.5,y/.82+.5))
    faces=[];mats=[]
    for layer in range(2):
        off=layer*nx*ny
        for row in range(ny-1):
            for j in range(nx-1):
                a=off+row*nx+j;f=(a,a+1,a+nx+1,a+nx)
                faces.append(f if layer else tuple(reversed(f)));mats.append(0 if layer else 1)
    edge=list(range(nx))+[row*nx+nx-1 for row in range(1,ny)]+list(range((ny-1)*nx+nx-2,(ny-1)*nx-1,-1))+[row*nx for row in range(ny-2,0,-1)]
    n=nx*ny
    for i,a in enumerate(edge):
        b=edge[(i+1)%len(edge)];faces.append((a,b,b+n,a+n));mats.append(2)
    me=bpy.data.meshes.new(name+'_mesh');me.from_pydata(verts,[],faces);me.materials.clear()
    for m in (grip,print_material,maple):me.materials.append(m)
    for p,i in zip(me.polygons,mats):p.material_index=i
    uv=me.uv_layers.new(name='UVMap')
    for p in me.polygons:
        for li in p.loop_indices:
            u,v=uvs[me.loops[li].vertex_index]
            uv.data[li].uv=(1-u,v) if p.material_index==1 else (u,v)
    obj=bpy.data.objects.new(name,me);col.objects.link(obj)
    return obj

def wheel(name,x,y,material,col):
    # Six bevel rings, smooth rolling surface, dark central hub faces.
    profile=[(-.011,.008),(-.013,.021),(-.009,.0275),(.009,.0275),(.013,.021),(.011,.008)]
    n=12;verts=[]
    for xx,r in profile:
        for i in range(n):
            a=2*math.pi*i/n;verts.append((xx,r*math.sin(a),r*math.cos(a)))
    faces=[];mi=[]
    for j in range(len(profile)-1):
        for i in range(n):
            a=j*n+i;b=j*n+(i+1)%n;c=(j+1)*n+(i+1)%n;d=(j+1)*n+i
            faces.append((a,d,c,b));mi.append(1 if j in(0,4) else 0)
    faces.append(tuple(range(n)));mi.append(1)
    faces.append(tuple(reversed(range((len(profile)-1)*n,len(profile)*n))));mi.append(1)
    me=bpy.data.meshes.new(name+'_mesh');me.from_pydata(verts,[],faces)
    me.materials.append(material);me.materials.append(hub)
    for p,m in zip(me.polygons,mi):p.material_index=m;p.use_smooth=len(p.vertices)==4
    obj=bpy.data.objects.new(name,me);col.objects.link(obj);obj.location=(x,y,.0275)
    return obj

wheel_colors=[(.76,.73,.61),(.76,.62,.27),(.74,.64,.45),(.69,.73,.51),(.80,.52,.31),(.50,.72,.69),(.68,.49,.75)]
for index,name in enumerate(NAMES):
    col=bpy.data.collections.new(f'SKATE_{index+1:02d}_{name}');scene.collection.children.link(col);collections.append(col)
    root=bpy.data.objects.new('ROOT_'+name,None);col.objects.link(root);roots.append(root)
    root['asset_type']='assembled_skateboard';root['product_name']=name.replace('_',' ')
    root['units']='meters';root['wheel_count']=4;root['truck_count']=2
    root['deck_length_m']=.82;root['deck_width_m']=.21
    root['local_pivot']='floor; center between four wheels';root['forward_blender']='+Y'
    printed=mat('Graphic_'+name,(1,1,1),.58,image=TEX/(name+'.png'))
    polyurethane=mat('Wheels_'+name,wheel_colors[index],.50)
    pieces=[deck('Deck_'+name,printed,col)]
    for side,y in [('Front',.25),('Rear',-.25)]:
        parts=[cube('Baseplate_'+side,(0,y,.084),(.061,.056,.012),truck,col),
               cube('TruckSupport_'+side,(0,y,.060),(.024,.026,.035),truck,col),
               cylinder('Axle_'+side,(-.105,y,.0275),(.105,y,.0275),.005,dark,col),
               cylinder('Hanger_'+side,(-.067,y,.038),(.067,y,.038),.011,truck,col),
               cylinder('Kingpin_'+side,(0,y-.013,.049),(0,y+.008,.080),.007,bushing,col)]
        pieces.append(join(parts,'Truck_'+side+'_'+name))
        for sx,label in [(-.091,'L'),(.091,'R')]:pieces.append(wheel('Wheel_'+side+label+'_'+name,sx,y,polyurethane,col))
        bolts=[]
        for xx in (-.021,.021):
            for yy in (-.018,.018):
                bolts.append(cylinder('Grip_Bolt',(xx,y+yy,.098),(xx,y+yy,.102),.0033,dark,col,n=6))
        pieces.append(join(bolts,'Fasteners_'+side+'_'+name))
    for obj in pieces:obj.parent=root
    bpy.ops.object.select_all(action='DESELECT')
    for obj in col.objects:obj.select_set(True)
    bpy.context.view_layer.objects.active=root
    filename=f'{index+1:02d}_{name}.glb'
    bpy.ops.export_scene.gltf(filepath=str(GLB/filename),export_format='GLB',use_selection=True,
                              export_yup=True,export_apply=True,export_extras=True,
                              export_cameras=False,export_lights=False,export_materials='EXPORT')
    tris=0
    for obj in pieces:
        obj.data.calc_loop_triangles();tris+=len(obj.data.loop_triangles)
    report.append({'name':name.replace('_',' '),'filename':filename,'collection':col.name,
                   'root':root.name,'triangles':tris,'file_bytes':(GLB/filename).stat().st_size,
                   'deck_dimensions_m':{'length':.82,'width':.21,'thickness':.008},
                   'wheel_count':4,'truck_count':2,'pivot':'floor centered between wheels',
                   'glb_axes':'Y up; long axis Z','source_axes':'Z up; long axis Y'})
    root.location.x=(index-3)*.32

(SOURCE/'Skateboards_manifest.json').write_text(json.dumps({'assets':report,'notes':[
    'Seven original printed designs; all boards fully assembled.',
    'The editable Blender scene places boards side by side. For append, move each ROOT_<Design> empty; child transforms are local.',
    'Individual GLBs have their root at origin, wheels on ground, dimensions in meters.',
    'Deck artwork is original code-authored print design; textures are embedded in each GLB.']},indent=2))

# Save an editable source before temporary render pose adjustments.
scene.world=bpy.data.worlds.new('World');scene.world.use_nodes=True
scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.15,.17,.19,1)
scene.world.node_tree.nodes['Background'].inputs[1].default_value=.35
scene.render.engine='CYCLES';scene.cycles.samples=40;scene.cycles.use_denoising=False
scene.render.resolution_x=1920;scene.render.resolution_y=960;scene.render.resolution_percentage=100
scene.view_settings.view_transform='AgX'
bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'Skateboards.blend'))
if '--no-render' in sys.argv:
    print(json.dumps(report,indent=2))
    sys.exit(0)

# A separate render pose shows the underside graphics, trucks and wheels clearly.
for root in roots:
    root.rotation_euler=(math.radians(112),0,0)
    root.location.z=.43
floor_mat=mat('Preview_Floor',(.08,.105,.12),.88)
cube('Preview_Floor',(0,0,-.035),(4,3,.05),floor_mat,scene.collection)
for x,y,z,power,size in [(-1.3,1.0,2.4,250,2.0),(1.5,-.4,1.5,180,1.8),(0,2.4,.8,120,1.2)]:
    bpy.ops.object.light_add(type='AREA',location=(x,y,z));light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size
    light.rotation_euler=(Vector((0,0,.4))-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(.90,2.85,1.65));cam=bpy.context.object
cam.rotation_euler=(Vector((0,0,.43))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=2.68;scene.camera=cam
scene.render.filepath=str(PREVIEW/'Skateboards_Lineup.png')
bpy.ops.render.render(write_still=True)
print(json.dumps(report,indent=2))
