"""Original modular sewer architecture. Blender 4.3+, no external add-ons.
Run: blender -b --python Source/build_sewers.py -- [--render] [--only 1]
Meters, Blender Z-up; the glTF exporter converts to Y-up.
"""
import bpy, math, json, sys, random
from pathlib import Path
from mathutils import Vector, Matrix

ROOT = Path(__file__).resolve().parents[1]
TEX = ROOT / 'Textures' / 'Sewer'
for d in ('GLB','Source','Metadata','Previews'):
    (ROOT/d).mkdir(parents=True, exist_ok=True)
ARGS = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
DO_RENDER = '--render' in ARGS
ONLY = int(ARGS[ARGS.index('--only')+1]) if '--only' in ARGS else None
random.seed(20261113)
TAU = 2*math.pi
MATS = {}
PARTS = {}
XFORM = Matrix.Identity(4)
COLLIDERS = []
LIGHTS = []
PORTS = []

def material(name, color, rough=.65, metal=0, emit=0, texture=None):
    m=bpy.data.materials.get(name) or bpy.data.materials.new(name)
    m.use_nodes=True
    m.diffuse_color=(*color,1)
    bs=m.node_tree.nodes.get('Principled BSDF')
    bs.inputs['Base Color'].default_value=(*color,1)
    bs.inputs['Roughness'].default_value=rough
    bs.inputs['Metallic'].default_value=metal
    if emit:
        bs.inputs['Emission Color'].default_value=(*color,1)
        bs.inputs['Emission Strength'].default_value=emit
    if texture:
        n=m.node_tree.nodes; l=m.node_tree.links
        for suffix,target in [('basecolor.jpg','Base Color'),('normal.png',None),('orm.png',None)]:
            image=bpy.data.images.load(str(TEX/f'{texture}_{suffix}'),check_existing=True)
            if suffix!='basecolor.jpg': image.colorspace_settings.name='Non-Color'
            node=n.new('ShaderNodeTexImage'); node.image=image
            node.interpolation='Linear'; node.extension='REPEAT'
            if target: l.new(node.outputs['Color'],bs.inputs[target])
            elif suffix=='normal.png':
                normal=n.new('ShaderNodeNormalMap'); normal.inputs['Strength'].default_value=.65
                l.new(node.outputs['Color'],normal.inputs['Color']); l.new(normal.outputs['Normal'],bs.inputs['Normal'])
            else:
                sep=n.new('ShaderNodeSeparateColor'); l.new(node.outputs['Color'],sep.inputs['Color'])
                l.new(sep.outputs['Green'],bs.inputs['Roughness']); l.new(sep.outputs['Blue'],bs.inputs['Metallic'])
                group=bpy.data.node_groups.get('glTF Material Output')
                if group is None:
                    group=bpy.data.node_groups.new('glTF Material Output','ShaderNodeTree')
                    group.interface.new_socket(name='Occlusion',in_out='INPUT',socket_type='NodeSocketFloat')
                oc=n.new('ShaderNodeGroup'); oc.node_tree=group
                l.new(sep.outputs['Red'],oc.inputs['Occlusion'])
    MATS[name]=m
    return m

def init_materials():
    material('Brick_Warm_Weathered',(.5,.31,.20),texture='brick')
    material('Concrete_Worn',(.42,.41,.35),texture='concrete')
    material('Steel_Teal_Rusted',(.08,.21,.21),texture='steel')
    material('Water_Dark_Opaque',(.035,.09,.075),texture='water')
    material('Iron_Dark',(.07,.085,.085),.44,.75)
    material('Stone_Trim',(.43,.40,.32),.83)
    material('Safety_Ochre',(.78,.44,.07),.58,.08)
    material('Valve_Red',(.42,.065,.032),.49,.45)
    material('Lamp_Warm',(.95,.62,.25),.35,0,3.0)
    material('Lamp_Cool',(.16,.6,.62),.35,0,2.3)
    material('Rubber_Black',(.018,.024,.022),.89)
    material('Grime_Moss',(.10,.16,.095),.98)
    material('Paper_Cream',(.72,.67,.53),.9)

class Part:
    def __init__(self,name,mat):
        self.name=name; self.mat=mat; self.v=[]; self.f=[]; self.uv=[]; self.n=[]
    def face(self,verts,uv=None,normal=None,normals=None):
        vv=[XFORM@Vector(p) for p in verts]
        if normal is not None:
            nn=XFORM.to_3x3()@Vector(normal)
            if (vv[1]-vv[0]).cross(vv[2]-vv[0]).dot(nn)<0:
                vv.reverse()
                if uv: uv=list(reversed(uv))
                if normals: normals=list(reversed(normals))
        start=len(self.v)
        self.v.extend(tuple(p) for p in vv)
        self.f.append(tuple(range(start,start+len(vv))))
        if uv is None:
            uv=[(0,0),(1,0),(1,1),(0,1)][:len(vv)]
        self.uv.extend(uv)
        if normals:
            self.n.extend(tuple((XFORM.to_3x3()@Vector(p)).normalized()) for p in normals)
        else:
            norm=(vv[1]-vv[0]).cross(vv[2]-vv[0]).normalized()
            self.n.extend([tuple(norm)]*len(vv))
    def finish(self):
        mesh=bpy.data.meshes.new(self.name+'_Geometry')
        mesh.from_pydata(self.v,[],self.f); mesh.update()
        uv=mesh.uv_layers.new(name='UVMap')
        for i,co in enumerate(self.uv): uv.data[i].uv=co
        mesh.normals_split_custom_set(self.n)
        obj=bpy.data.objects.new(self.name,mesh)
        bpy.context.scene.collection.objects.link(obj)
        obj.data.materials.append(MATS[self.mat])
        obj['asset_category']='roof' if self.name.startswith('ROOF_') else ('water' if self.name.startswith('WATER_') else 'architecture' if self.name.startswith(('Walls_','Floor_')) else 'decor')
        obj['static']=True
        obj['collision']='Use companion metadata; do not convex-hull the complete room.'
        return obj

def part(name,mat):
    if name not in PARTS: PARTS[name]=Part(name,mat)
    assert PARTS[name].mat==mat,(name,mat)
    return PARTS[name]

def steps(length,tile):
    if tile is None: return [0,length]
    out=[0.0]; a=tile
    while a<length-1e-6: out.append(a); a+=tile
    out.append(length)
    return out

def rect(name,mat,origin,u,v,tile=2,normal=None):
    o=Vector(origin); uu=Vector(u); vv=Vector(v)
    lu=uu.length; lv=vv.length; uu.normalize(); vv.normalize()
    aa=steps(lu,tile); bb=steps(lv,tile)
    for i in range(len(aa)-1):
        for j in range(len(bb)-1):
            a,b=aa[i:i+2]; c,d=bb[j:j+2]
            pts=[o+uu*a+vv*c,o+uu*b+vv*c,o+uu*b+vv*d,o+uu*a+vv*d]
            su=(b-a)/tile if tile else 1; sv=(d-c)/tile if tile else 1
            part(name,mat).face(pts,[(0,0),(su,0),(su,sv),(0,sv)],normal)

def box(name,mat,center,size,tile=None,collider=False):
    x,y,z=center; a,b,c=[p/2 for p in size]
    rect(name,mat,(x-a,y-b,z-c),(2*a,0,0),(0,2*b,0),tile,(0,0,-1))
    rect(name,mat,(x-a,y-b,z+c),(2*a,0,0),(0,2*b,0),tile,(0,0,1))
    rect(name,mat,(x-a,y-b,z-c),(2*a,0,0),(0,0,2*c),tile,(0,-1,0))
    rect(name,mat,(x-a,y+b,z-c),(2*a,0,0),(0,0,2*c),tile,(0,1,0))
    rect(name,mat,(x-a,y-b,z-c),(0,2*b,0),(0,0,2*c),tile,(-1,0,0))
    rect(name,mat,(x+a,y-b,z-c),(0,2*b,0),(0,0,2*c),tile,(1,0,0))
    if collider:
        p=XFORM@Vector(center)
        rot=XFORM.to_quaternion()
        # Blender z rotation -> glTF rotation about y.
        COLLIDERS.append({'name':name,'type':'box','center_m':[p.x,p.z,-p.y],
                          'size_m':[size[0],size[2],size[1]],'rotation_y_radians':rot.to_euler().z,
                          'purpose':'walkable' if name.startswith(('Floor_','Bridge_')) else 'solid'})

def cylinder(name,mat,p1,p2,r,n=12,caps=True):
    p1=Vector(p1); p2=Vector(p2); axis=(p2-p1).normalized()
    ref=Vector((0,0,1)) if abs(axis.z)<.95 else Vector((1,0,0))
    u=axis.cross(ref).normalized(); v=axis.cross(u).normalized()
    dirs=[u*math.cos(TAU*i/n)+v*math.sin(TAU*i/n) for i in range(n)]
    for i in range(n):
        j=(i+1)%n
        part(name,mat).face([p1+r*dirs[i],p1+r*dirs[j],p2+r*dirs[j],p2+r*dirs[i]],
            [(i/n,0),((i+1)/n,0),((i+1)/n,1),(i/n,1)],normals=[dirs[i],dirs[j],dirs[j],dirs[i]])
        if caps:
            part(name,mat).face([p1,p1+r*dirs[j],p1+r*dirs[i]],[(.5,.5),(.5+.5*math.cos(TAU*j/n),.5+.5*math.sin(TAU*j/n)),(.5+.5*math.cos(TAU*i/n),.5+.5*math.sin(TAU*i/n))],normal=-axis)
            part(name,mat).face([p2,p2+r*dirs[i],p2+r*dirs[j]],[(.5,.5),(.5+.5*math.cos(TAU*i/n),.5+.5*math.sin(TAU*i/n)),(.5+.5*math.cos(TAU*j/n),.5+.5*math.sin(TAU*j/n))],normal=axis)

def tube_curve(name,mat,points,r,n=10):
    # Small connected pipe elbows. Spheres/rounded joints are avoided for performance.
    for a,b in zip(points[:-1],points[1:]): cylinder(name,mat,a,b,r,n,caps=False)

def torus(name,mat,center,major,minor,axis='X',n=20,k=6):
    c=Vector(center)
    def P(a,b):
        q=Vector(((major+minor*math.cos(b))*math.cos(a),(major+minor*math.cos(b))*math.sin(a),minor*math.sin(b)))
        if axis=='X': q=Vector((q.z,q.x,q.y))
        if axis=='Y': q=Vector((q.x,q.z,q.y))
        return c+q
    for i in range(n):
        for j in range(k):
            a,b=TAU*i/n,TAU*(i+1)/n; d,e=TAU*j/k,TAU*(j+1)/k
            part(name,mat).face([P(a,d),P(b,d),P(b,e),P(a,e)],[(i/n,j/k),((i+1)/n,j/k),((i+1)/n,(j+1)/k),(i/n,(j+1)/k)])

def arch(name,mat,y0,y1,r=3.0,spring=2.2,thickness=.32):
    # Physical shell with sealed ends; inner normals face the traversable volume.
    nn=40; angles=sorted(set([i*math.pi/nn for i in range(nn+1)]+[x/r for x in steps(math.pi*r,2)]))
    yy=steps(y1-y0,2)
    for i in range(len(angles)-1):
        a,b=angles[i:i+2]
        # UV patches split precisely on texture boundaries.
        u0=(a*r/2)%1; u1=u0+(b-a)*r/2
        if u1>1.000001: u0=0; u1=(b-a)*r/2
        u1=min(1,u1)
        for j in range(len(yy)-1):
            c=y0+yy[j]; d=y0+yy[j+1]
            for rad,sign in [(r,-1),(r+thickness,1)]:
                p=[(rad*math.cos(a),c,spring+rad*math.sin(a)),(rad*math.cos(b),c,spring+rad*math.sin(b)),(rad*math.cos(b),d,spring+rad*math.sin(b)),(rad*math.cos(a),d,spring+rad*math.sin(a))]
                norms=[(sign*math.cos(a),0,sign*math.sin(a)),(sign*math.cos(b),0,sign*math.sin(b)),(sign*math.cos(b),0,sign*math.sin(b)),(sign*math.cos(a),0,sign*math.sin(a))]
                part(name,mat).face(p,[(u0,0),(u1,0),(u1,(d-c)/2),(u0,(d-c)/2)],normal=(sign*math.cos((a+b)/2),0,sign*math.sin((a+b)/2)),normals=norms)
        for y,sg in [(y0,-1),(y1,1)]:
            part(name,mat).face([(r*math.cos(a),y,spring+r*math.sin(a)),((r+thickness)*math.cos(a),y,spring+(r+thickness)*math.sin(a)),((r+thickness)*math.cos(b),y,spring+(r+thickness)*math.sin(b)),(r*math.cos(b),y,spring+r*math.sin(b))],normal=(0,sg,0))
    for x,sg in [(-r,-1),(r,1)]:
        rect(name,mat,(x if sg>0 else x-thickness,y0,spring),(thickness,0,0),(0,y1-y0,0),2,(0,0,-1))

def rib(y,idx=0):
    name='Trim_Stone_Arch_Ribs'
    for i in range(20):
        a=i*math.pi/20+.003; b=(i+1)*math.pi/20-.003
        ri,ro=2.86,3.03; y0,y1=y-.13,y+.13
        p=[(ri*math.cos(a),y0,2.2+ri*math.sin(a)),(ri*math.cos(b),y0,2.2+ri*math.sin(b)),(ro*math.cos(b),y0,2.2+ro*math.sin(b)),(ro*math.cos(a),y0,2.2+ro*math.sin(a))]
        q=[(x,y1,z) for x,_,z in p]
        part(name,'Stone_Trim').face(p,normal=(0,-1,0)); part(name,'Stone_Trim').face(q,normal=(0,1,0))
        for j in range(4):
            jj=(j+1)%4
            part(name,'Stone_Trim').face([p[j],q[j],q[jj],p[jj]])
    for x in [-2.94,2.94]:
        box(name,'Stone_Trim',(x,y,1.1),(.23,.28,2.2))
        box(name,'Stone_Trim',(x,y,.14),(.36,.42,.28))
        box(name,'Stone_Trim',(x,y,2.16),(.37,.42,.15))

def passage(y0,y1,prefix='',brick=True,wet=True):
    length=y1-y0; mid=(y0+y1)/2
    wm='Brick_Warm_Weathered' if brick else 'Concrete_Worn'
    for side in [-1,1]:
        box('Walls_'+prefix+('Left' if side<0 else 'Right'),wm,(side*3.16,mid,1.1),(.32,length,2.2),2,True)
        if wet:
            box('Floor_'+prefix+('Left' if side<0 else 'Right'),'Concrete_Worn',(side*1.95,mid,-.22),(2.1,length,.44),2,True)
            box('Trim_Channel_Coping','Stone_Trim',(side*.98,mid,.035),(.16,length,.07))
        box('Trim_Wall_Footing','Stone_Trim',(side*2.95,mid,.13),(.18,length,.26))
    if wet:
        box('Floor_'+prefix+'Channel_Bed','Concrete_Worn',(0,mid,-.84),(1.8,length,.28),2,True)
        box('WATER_'+prefix+'Channel','Water_Dark_Opaque',(0,mid,-.355),(1.77,length,.035),3)
    else:
        box('Floor_'+prefix+'Dry','Concrete_Worn',(0,mid,-.22),(6,length,.44),2,True)
    arch('ROOF_'+prefix+'Vault',wm,y0,y1)

def pipe_run(y0,y1,side=-1,z=1.7,r=.12,name='Pipes_Main'):
    x=side*2.73
    cylinder(name,'Steel_Teal_Rusted',(x,y0,z),(x,y1,z),r,16)
    for y in [y0+.5,(y0+y1)/2,y1-.5]:
        cylinder('Pipes_Flanges','Iron_Dark',(x,y-.065,z),(x,y+.065,z),r*1.4,16)
        box('Pipes_Wall_Brackets','Iron_Dark',(side*2.87,y,z-.18),(.26,.075,.09))
        box('Pipes_Wall_Brackets','Iron_Dark',(side*2.985,y,z-.11),(.025,.18,.42))

def valve(y,x=2.56,z=1.63):
    cylinder('Valve_Spindle','Iron_Dark',(x,y,z),(x-.22,y,z),.035,10)
    torus('Valve_Handwheel','Valve_Red',(x-.25,y,z),.25,.035,'X',20,6)
    for a in [0,TAU/3,2*TAU/3]:
        cylinder('Valve_Handwheel','Valve_Red',(x-.25,y,z),(x-.25,y+.22*math.cos(a),z+.22*math.sin(a)),.018,6)

def lamp(y,side=-1,cool=False,z=2.38):
    x=side*2.94
    box('Lights_Fixture_Housings','Iron_Dark',(x,y,z),(.13,.55,.27))
    box('Lights_Emissive_Cool' if cool else 'Lights_Emissive_Warm','Lamp_Cool' if cool else 'Lamp_Warm',(x-side*.075,y,z),(.025,.44,.15))
    for yy in [-.14,0,.14]: box('Lights_Fixture_Cages','Iron_Dark',(x-side*.093,y+yy,z),(.025,.022,.21))
    pos=XFORM@Vector((x-side*.37,y,z))
    LIGHTS.append({'name':f'LIGHT_{len(LIGHTS)+1:02d}','position_m':[pos.x,pos.z,-pos.y],
                   'color_hex':'#9bd9db' if cool else '#ffd29a','suggested_range_m':5.5,
                   'preview_watts':95 if cool else 115,'runtime_note':'Engine-native local light. Tune energy in game; Blender watts do not map directly.'})

def bridge(y):
    box('Bridge_Frame','Iron_Dark',(0,y,-.055),(2.24,1.12,.11),None,True)
    for i in range(12): box('Bridge_Tread_Slats','Steel_Teal_Rusted',(0,y-.49+i*.089,.012),(2.18,.066,.035))
    for x in [-1.13,1.13]: box('Bridge_Edge','Safety_Ochre',(x,y,.023),(.07,1.14,.05))

def rail(y0,y1,side=1):
    x=side*.96
    for y in [y0,y1]:
        cylinder('Safety_Handrails','Iron_Dark',(x,y,.02),(x,y,.96),.033,8)
        box('Safety_Rail_Footplates','Iron_Dark',(x,y,.03),(.16,.15,.06))
    for z in [.52,.96]: cylinder('Safety_Handrails','Iron_Dark',(x,y0,z),(x,y1,z),.027,8)

def port(name,position,outward):
    p=XFORM@Vector(position); d=XFORM.to_3x3()@Vector(outward)
    name=name.replace('PORT_',f'PORT_{bpy.context.scene.name[:2]}_')
    o=bpy.data.objects.new(name,None); bpy.context.scene.collection.objects.link(o)
    o.location=p; o.empty_display_type='ARROWS'; o.empty_display_size=.45
    o.rotation_euler=d.to_track_quat('Y','Z').to_euler()
    o['role']='module_connector'; o['nominal_width_m']=6.; o['minimum_clear_width_m']=5.6
    o['crown_height_m']=5.2; o['floor_height_m']=0.
    PORTS.append({'name':name,'position_m':[p.x,p.z,-p.y],'outward':[d.x,d.z,-d.y],
                  'nominal_width_m':6,'minimum_clear_width_m':5.6,'spring_height_m':2.2,'crown_height_m':5.2})

def sign(text,center,side=-1,scale=.2):
    # Converted text is ordinary mesh geometry; exact labels remain editable in source.
    font=bpy.data.curves.new('Label_'+text,'FONT'); font.body=text; font.align_x='CENTER'; font.align_y='CENTER'
    font.size=scale; font.extrude=.0015; font.resolution_u=3
    o=bpy.data.objects.new('Sign_'+text.replace(' ','_'),font); bpy.context.scene.collection.objects.link(o)
    o.location=XFORM@Vector(center)
    # Local text plane XY -> wall plane YZ, facing into the passage.
    rot=Matrix(((0,0,-side,0),(-side,0,0,0),(0,1,0,0),(0,0,0,1)))
    o.matrix_world=XFORM @ Matrix.Translation(Vector(center)) @ rot
    o.data.materials.append(MATS['Paper_Cream'])
    bpy.context.view_layer.objects.active=o; o.select_set(True)
    bpy.ops.object.convert(target='MESH'); o.select_set(False)
    o['collision']='none'
    return o

def debris(seed=0):
    rng=random.Random(seed)
    for i in range(13):
        x=rng.choice([-1,1])*rng.uniform(2.55,2.8); y=rng.uniform(-5.4,5.4)
        box('Debris_Brick_Fragments','Stone_Trim',(x,y,.03),(rng.uniform(.06,.16),rng.uniform(.04,.12),.06))

def build_main():
    passage(-6,6)
    for i,y in enumerate([-5.78,-2,2,5.78]): rib(y,i)
    pipe_run(-6,6,-1,1.65,.13); pipe_run(-6,6,-1,1.99,.062,'Pipes_Upper')
    pipe_run(-6,6,1,1.78,.09,'Pipes_Return')
    valve(.8)
    for y in [-4,0,4]: lamp(y,-1); lamp(y,1,cool=y==4)
    bridge(2.85); rail(-2.7,-.4,1); rail(3.7,5.6,-1)
    for y in [-4,0,4]:
        box('Ceiling_Cable_Tray','Iron_Dark',(1.45,y,4.47),(.35,3.92,.07))
        cylinder('Ceiling_Cable_Hangers','Iron_Dark',(1.45,y,4.47),(1.45,y,4.85),.02,6)
    box('Sign_Backplates','Steel_Teal_Rusted',(-2.985,-.8,1.1),(.035,.88,.38))
    sign('S - 01',(-2.958,-.8,1.1),-1,.18)
    debris(9)
    port('PORT_North',(0,6,0),(0,1,0)); port('PORT_South',(0,-6,0),(0,-1,0))
    return {'title':'Brick sewer passage','footprint_m':[6.64,12],'camera':[-1.70,-5.15,1.60],'look_at':[.15,4.5,1.80],
            'description':'Warm brick barrel vault, twin raised walkways, central water channel, service pipework, valve, footbridge and practical fixtures.'}

def groin_vault():
    # Four-way vault. At every portal the ceiling follows the same semicircle.
    n=16; r=3
    def zz(x,y): return 2.2+math.sqrt(max(0,r*r-min(x*x,y*y)))
    for i in range(n):
        for j in range(n):
            x=-3+6*i/n; xx=-3+6*(i+1)/n; y=-3+6*j/n; yy=-3+6*(j+1)/n
            pts=[(x,y,zz(x,y)),(xx,y,zz(xx,y)),(xx,yy,zz(xx,yy)),(x,yy,zz(x,yy))]
            uv=[(i%4/4,j%4/4),((i%4+1)/4,j%4/4),((i%4+1)/4,(j%4+1)/4),(i%4/4,(j%4+1)/4)]
            part('ROOF_Junction_Groin_Vault','Brick_Warm_Weathered').face(pts,uv,normal=(0,0,-1))
            part('ROOF_Junction_Groin_Vault','Brick_Warm_Weathered').face([(a,b,c+.32) for a,b,c in pts],uv,normal=(0,0,1))

def build_junction():
    global XFORM
    for idx,(a,nm) in enumerate([(0,'North'),(math.pi,'South'),(math.pi/2,'West'),(-math.pi/2,'East')]):
        XFORM=Matrix.Rotation(a,4,'Z')
        passage(3,6,nm+'_')
        rib(5.78); rib(3.12)
        pipe_run(3,6,-1,1.72,.12,'Pipes_'+nm)
        lamp(4.35,-1,cool=nm in ('West','North')); lamp(4.4,1)
        port('PORT_'+nm,(0,6,0),(0,1,0))
    XFORM=Matrix.Identity(4)
    for y in [-2.1,2.1]: box('Floor_Central_NorthSouth','Concrete_Worn',(0,y,-.22),(6,1.8,.44),2,True)
    for x in [-2.1,2.1]: box('Floor_Central_EastWest','Concrete_Worn',(x,0,-.22),(1.8,2.4,.44),2,True)
    box('WATER_Central_Sump','Water_Dark_Opaque',(0,0,-.46),(2.4,2.4,.045),2)
    box('Floor_Central_Sump_Base','Concrete_Worn',(0,0,-.88),(2.4,2.4,.28),2,True)
    for x in [-1.22,1.22]: box('Grate_Frame','Safety_Ochre',(x,0,-.035),(.09,2.5,.12))
    for y in [-1.22,1.22]: box('Grate_Frame','Safety_Ochre',(0,y,-.035),(2.5,.09,.12))
    for i in range(22): box('Grate_Walkable_Surface','Iron_Dark',(-1.15+i*.1095,0,-.015),(.045,2.35,.05))
    for i in range(6): box('Grate_Cross_Bars','Iron_Dark',(0,-1.1+i*.44,-.052),(2.35,.045,.035))
    COLLIDERS.append({'name':'Central_grate_walkable','type':'box','center_m':[0,-.06,0],'size_m':[2.45,.12,2.45],'rotation_y_radians':0,'purpose':'walkable'})
    for x in [-2.78,2.78]:
        for y in [-2.78,2.78]:
            box('Piers_Junction','Stone_Trim',(x,y,1.1),(.4,.4,2.2),None,True)
            box('Piers_Junction','Stone_Trim',(x,y,.15),(.54,.54,.3))
    groin_vault()
    for x in [-1.65,1.65]:
        cylinder('Ceiling_Suspension','Iron_Dark',(x,0,3.95),(x,0,5.1),.025,8)
    box('Ceiling_Light_Frame','Iron_Dark',(0,0,3.96),(3.5,.25,.18))
    box('Ceiling_Light_Diffuser','Lamp_Warm',(0,0,3.855),(3.25,.15,.025))
    LIGHTS.append({'name':'LIGHT_Central','position_m':[0,3.65,0],'color_hex':'#f4d4a5','suggested_range_m':7,'preview_watts':180})
    return {'title':'Four-way sewer junction','footprint_m':[12,12],'camera':[-1.7,-5.35,1.65],'look_at':[.2,1.0,2.0],
            'description':'Four compatible arched entrances, a central walkable metal grate over the sump, groin vault and maintenance lighting.'}

def build_utility():
    passage(-6,6,brick=False,wet=False)
    for y in [-5.78,-2,2,5.78]: rib(y)
    # Recessed drainage strip is visually continuous but does not split the dry route.
    for i in range(35): box('Drain_Grate','Iron_Dark',(-2.28,-5.85+i*.34,.012),(.24,.20,.022))
    # Small squirrel-scale muddy tracks: a visual joke beside the service drain.
    for i in range(4):
        px=-1.92 + (.06 if i%2 else -.06); py=-3.7+i*.22
        cylinder('Details_Squirrel_Paw_Marks','Grime_Moss',(px,py,.001),(px,py,.003),.032,8)
        for toe in range(4):
            tx=px+(toe-1.5)*.021; ty=py+.047-abs(toe-1.5)*.005
            cylinder('Details_Squirrel_Paw_Marks','Grime_Moss',(tx,ty,.001),(tx,ty,.003),.011,6)
    pipe_run(-6,6,-1,1.35,.15); pipe_run(-6,6,-1,1.89,.09,'Pipes_Upper')
    pipe_run(-6,6,1,2.05,.065,'Pipes_Return')
    valve(1.0,-2.40,1.36)
    for y in [-4,0,4]: lamp(y,-1,cool=True); lamp(y,1,cool=False)
    # Service machinery occupies the side of the walkway, leaving a broad central aisle.
    box('Pump_Plinth','Concrete_Worn',(2.25,2.3,.12),(1.1,1.7,.24),None,True)
    cylinder('Pump_Motor','Steel_Teal_Rusted',(2.25,1.75,.60),(2.25,2.7,.60),.29,16)
    for y in [1.85,2.0,2.15,2.3,2.45,2.60]: cylinder('Pump_Cooling_Fins','Iron_Dark',(2.25,y,.60),(2.25,y+.035,.60),.32,16)
    box('Pump_Electrical_Box','Steel_Teal_Rusted',(2.25,2.25,.98),(.32,.35,.22))
    cylinder('Pump_Volute','Steel_Teal_Rusted',(2.25,2.72,.6),(2.25,2.99,.6),.37,16)
    tube_curve('Pump_Discharge','Steel_Teal_Rusted',[(2.25,2.98,.6),(2.25,3.2,.6),(2.25,3.37,.77),(2.25,3.37,1.28),(2.44,3.37,1.47),(2.7,3.37,1.47)],.12,12)
    # An inset side access panel, with a separate pivoted door object.
    box('Service_Door_Frame','Iron_Dark',(2.96,-1.2,1.17),(.09,1.5,2.34))
    box('Service_Door_Leaf','Steel_Teal_Rusted',(2.90,-1.2,1.16),(.055,1.34,2.18))
    box('Service_Door_Vent','Iron_Dark',(2.858,-1.2,1.64),(.02,.84,.52))
    for z in [1.45,1.54,1.63,1.72,1.81]: box('Service_Door_Louvres','Steel_Teal_Rusted',(2.84,-1.2,z),(.035,.84,.028))
    cylinder('Service_Door_Handle','Safety_Ochre',(2.81,-.78,.95),(2.81,-.78,1.17),.026,8)
    box('Electric_Panel','Steel_Teal_Rusted',(-2.87,2.7,.85),(.24,.82,1.04))
    for z in [.55,.7,.85,1.0,1.15]: box('Electric_Panel_Slots','Iron_Dark',(-2.735,2.7,z),(.025,.52,.03))
    box('Electric_Panel_Indicator','Lamp_Cool',(-2.73,2.48,1.25),(.025,.05,.05))
    for y in [-4,0,4]:
        box('ROOF_Cable_Tray','Iron_Dark',(-1.35,y,4.5),(.42,3.95,.085))
        for x in [-1.48,-1.37,-1.26]: cylinder('ROOF_Cables','Rubber_Black',(x,y-1.97,4.56),(x,y+1.97,4.56),.025,8)
    sign('SERVICE',(-2.97,-2.9,1.0),-1,.19)
    port('PORT_North',(0,6,0),(0,1,0)); port('PORT_South',(0,-6,0),(0,-1,0))
    return {'title':'Concrete maintenance tunnel','footprint_m':[6.64,12],'camera':[-1.5,-5.25,1.7],'look_at':[.5,3.5,1.85],
            'description':'Dry utility route with pump set, rusted service lines, electrical panel, inset access-door panel, drain and cable trays. Side door is a decorative closed access panel, not a through-opening.'}

def configure_scene(scene):
    scene.unit_settings.system='METRIC'; scene.unit_settings.scale_length=1.0
    scene.render.engine='CYCLES'; scene.cycles.device='CPU'; scene.cycles.samples=64
    scene.cycles.use_denoising=False
    scene.render.resolution_x=1200; scene.render.resolution_y=800; scene.render.resolution_percentage=100
    scene.world=bpy.data.worlds.new(scene.name+'_World')
    scene.world.use_nodes=True
    bg=scene.world.node_tree.nodes.get('Background'); bg.inputs[0].default_value=(.12,.16,.18,1); bg.inputs[1].default_value=.35
    scene.view_settings.view_transform='AgX'
    scene.view_settings.look='AgX - Medium High Contrast'; scene.view_settings.exposure=.5
    scene.render.image_settings.file_format='PNG'

def light_object(name,pos,color,power,size=.5,typ='POINT',target=None):
    data=bpy.data.lights.new(name,typ); data.energy=power; data.color=color
    if typ=='POINT': data.shadow_soft_size=size
    else: data.shape='DISK'; data.size=size
    o=bpy.data.objects.new(name,data); bpy.context.scene.collection.objects.link(o); o.location=pos
    if target: o.rotation_euler=(Vector(target)-o.location).to_track_quat('-Z','Y').to_euler()
    o['preview_only']=True
    return o

def setup_preview(meta):
    for l in LIGHTS:
        p=l['position_m']; pos=(p[0],-p[2],p[1]); h=l['color_hex'].lstrip('#')
        color=tuple(int(h[i:i+2],16)/255 for i in [0,2,4])
        light_object(l['name']+'_Preview',pos,color,l['preview_watts'],.32)
    light_object('Preview_Soft_Camera_Fill',(0,-5.5,3.6),(.54,.67,.8),320,4,'AREA',(0,2,1))
    light_object('Preview_Far_Bounce',(0,6.5,3.3),(.55,.75,.78),230,3,'AREA',(0,1,2))
    camd=bpy.data.cameras.new('Preview_Camera'); cam=bpy.data.objects.new('Preview_Camera',camd)
    bpy.context.scene.collection.objects.link(cam); cam.location=meta['camera']
    cam.rotation_euler=(Vector(meta['look_at'])-cam.location).to_track_quat('-Z','Y').to_euler()
    camd.lens=18.5; camd.clip_start=.06; camd.clip_end=120
    bpy.context.scene.camera=cam

def main():
    global PARTS,XFORM,COLLIDERS,LIGHTS,PORTS
    bpy.ops.wm.read_factory_settings(use_empty=True)
    init_materials()
    builders=[('01_Brick_Sewer_Passage',build_main),('02_Four_Way_Sewer_Junction',build_junction),('03_Concrete_Maintenance_Tunnel',build_utility)]
    for idx,(name,fn) in enumerate(builders,1):
        if ONLY and idx!=ONLY: continue
        scene=bpy.data.scenes.new(name); bpy.context.window.scene=scene
        PARTS={}; XFORM=Matrix.Identity(4); COLLIDERS=[]; LIGHTS=[]; PORTS=[]
        configure_scene(scene)
        meta=fn()
        for p in PARTS.values(): p.finish()
        for p in PORTS:
            ob=bpy.data.objects.get(p['name'])
            # Duplicate Blender object names can be suffixed between scenes; metadata remains scene-local.
        for light_index,l in enumerate(LIGHTS,1):
            l['name']=f'LIGHT_{name[:2]}_{light_index:02d}'
            o=bpy.data.objects.new(l['name'],None); scene.collection.objects.link(o)
            p=l['position_m']; o.location=(p[0],-p[2],p[1]); o.empty_display_type='SPHERE'; o.empty_display_size=.12
            o['role']='suggested_light'; o['color_hex']=l['color_hex']; o['range_m']=l['suggested_range_m']
        bpy.ops.object.select_all(action='DESELECT')
        for o in scene.objects:
            if o.type in {'MESH','EMPTY'}: o.select_set(True)
        glb=ROOT/'GLB'/f'{name}.glb'
        bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,use_active_scene=True,
            export_apply=True,export_yup=True,export_extras=True,export_cameras=False,
            export_lights=False,export_animations=False,export_texcoords=True,export_normals=True,
            export_tangents=True,export_image_format='AUTO',export_materials='EXPORT')
        triangles=sum(len(o.data.polygons) for o in scene.objects if o.type=='MESH')
        meta.update({'id':name,'units':'meter','up_axis':'Y','blender_up_axis':'Z','origin':'center at walkway elevation 0',
                     'coordinate_conversion':'glTF (x,y,z) = Blender (x,z,-y)',
                     'connectors':PORTS,'collision_boxes':COLLIDERS,'suggested_lights':LIGHTS,
                     'water':'opaque static mesh; optional runtime flow shader','glb_bytes':glb.stat().st_size,
                     'preview_note':'Blender preview lighting is separate from the exported mesh; actual Roblox/Three.js appearance requires engine lights.',
                     'playtest_status':'Not imported into the user game or Roblox Studio.'})
        (ROOT/'Metadata'/f'{name}.json').write_text(json.dumps(meta,indent=2))
        setup_preview(meta)
        # Keep source materials portable when the complete pack is extracted.
        for im in bpy.data.images:
            if im.filepath and Path(bpy.path.abspath(im.filepath)).exists(): im.filepath=bpy.path.relpath(im.filepath,start=str(ROOT/'Source'))
        bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'Source'/'Sewer_Modules.blend'))
        if DO_RENDER:
            scene.render.filepath=str(ROOT/'Previews'/f'{name}.png'); bpy.ops.render.render(write_still=True)
        print('FINISHED_ASSET',name,glb.stat().st_size,flush=True)
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(ROOT/'Source'/'Sewer_Modules.blend'))

if __name__=='__main__': main()
