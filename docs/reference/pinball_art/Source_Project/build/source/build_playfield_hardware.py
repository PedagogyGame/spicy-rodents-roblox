"""Build the ten decorative pinball hardware GLBs from the supplied references.

Run with Blender 4.3+: blender -b -t 2 --python build_playfield_hardware.py
The existing reference objects and their transforms remain authoritative.
All added geometry is authored in glTF metres and converted to Blender axes.
"""
import bpy, bmesh, math, json, os, sys, subprocess, shutil
from pathlib import Path
from mathutils import Vector

ROOT = Path(__file__).resolve().parents[2]
PACK = ROOT/'work'/'Pinball_ChatGPT_Pack'
OUT = ROOT/'build'/'models'
DATA = json.loads((PACK/'pinball_data.json').read_text())
PYTHON = os.environ.get('PINBALL_CHECK_PYTHON') or shutil.which('python3') or shutil.which('python')
if not PYTHON:raise RuntimeError('Set PINBALL_CHECK_PYTHON to Python with the supplied checker dependencies installed.')
OUT.mkdir(parents=True,exist_ok=True)
PROFILE_FILE=Path(__file__).with_name('wood_polygon_profiles.json')
if not PROFILE_FILE.exists():
    subprocess.run([PYTHON,str(Path(__file__).with_name('generate_wood_profiles.py'))],check=True)
WOOD_PROFILES=json.loads(PROFILE_FILE.read_text())

def xyz(p):
    return Vector((p[0],-p[2],p[1]))

def linear(v):
    return v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4

def material(name,hexcolour,metal=0,rough=.4):
    col=[linear(int(hexcolour[i:i+2],16)/255) for i in (1,3,5)]+[1]
    m=bpy.data.materials.new(name);m.use_nodes=True
    node=m.node_tree.nodes.get('Principled BSDF')
    node.inputs['Base Color'].default_value=col
    node.inputs['Metallic'].default_value=metal
    node.inputs['Roughness'].default_value=rough
    m.diffuse_color=col
    return m

class Mesh:
    def __init__(self): self.v=[];self.f=[];self.sm=[]
    def add(self,vertices,faces,smooth=False):
        n=len(self.v);self.v.extend([tuple(v) for v in vertices]);self.f.extend([tuple(i+n for i in f) for f in faces]);self.sm.extend([smooth]*len(faces))
    def lathe(self,cx,cz,profile,n=12):
        vs=[(cx+r*math.cos(2*math.pi*i/n),h,cz+r*math.sin(2*math.pi*i/n)) for h,r in profile for i in range(n)]
        fs=[]
        for j in range(len(profile)-1):
            for i in range(n):fs.append((j*n+i,j*n+(i+1)%n,(j+1)*n+(i+1)%n,(j+1)*n+i))
        self.add(vs,fs,True)
        self.add(vs[:n],[(tuple(reversed(range(n))))],False)
        self.add(vs[-n:],[tuple(range(n))],False)
    def box(self,centre,ux,uz,w,d,h):
        c=Vector(centre); u=Vector(ux);v=Vector(uz);y=Vector((0,1,0))
        vs=[c+u*(sx*w/2)+v*(sz*d/2)+y*(sy*h/2) for sy in (-1,1) for sz in (-1,1) for sx in (-1,1)]
        self.add(vs,[(0,2,3,1),(4,5,7,6),(0,1,5,4),(2,6,7,3),(0,4,6,2),(1,3,7,5)])
    def tube(self,points,r,n=8):
        points=[Vector(p) for p in points]
        if len(points)<2:return
        vs=[]
        for i,p in enumerate(points):
            t=(points[min(i+1,len(points)-1)]-points[max(0,i-1)]).normalized()
            a=Vector((0,1,0))
            if abs(t.dot(a))>.99:a=Vector((1,0,0))
            a=(a-t*t.dot(a)).normalized();b=t.cross(a).normalized()
            for j in range(n):
                q=p+r*(math.cos(2*math.pi*j/n)*a+math.sin(2*math.pi*j/n)*b)
                vs.append(q)
        fs=[]
        for i in range(len(points)-1):
            for j in range(n):fs.append((i*n+j,i*n+(j+1)%n,(i+1)*n+(j+1)%n,(i+1)*n+j))
        self.add(vs,fs,True)
        self.add(vs[:n],[tuple(reversed(range(n)))])
        self.add(vs[-n:],[tuple(range(n))])
    def object(self,name,mat,existing=None):
        ob=existing
        if ob is None:
            me=bpy.data.meshes.new(name+'_Mesh');ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob)
        inv=ob.matrix_world.inverted()
        me=bpy.data.meshes.new(name+'_Detail')
        me.from_pydata([inv@xyz(v) for v in self.v],[],self.f);me.update()
        ob.data=me
        me.materials.clear();me.materials.append(mat)
        for p,s in zip(me.polygons,self.sm):p.use_smooth=s
        bm=bmesh.new();bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-8)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bm.to_mesh(me);bm.free();me.update()
        return ob

def import_ref(name):
    bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
    for m in list(bpy.data.materials):bpy.data.materials.remove(m)
    bpy.ops.import_scene.gltf(filepath=str(PACK/'reference'/name))
    return {ob.name:ob for ob in bpy.context.scene.objects if ob.type=='MESH'}

def assign(ob,mat):
    for attr in list(ob.data.color_attributes):ob.data.color_attributes.remove(attr)
    ob.data.materials.clear();ob.data.materials.append(mat)
    for p in ob.data.polygons:p.material_index=0

def bevel(ob,width,segments=1):
    bpy.context.view_layer.objects.active=ob
    # Weld imported split normals before beveling; preserve vertices/placement.
    bm=bmesh.new();bm.from_mesh(ob.data)
    bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=1e-7)
    bmesh.ops.dissolve_limit(bm,angle_limit=.001,verts=list(bm.verts),edges=list(bm.edges),use_dissolve_boundaries=False)
    bm.to_mesh(ob.data);bm.free();ob.data.update()
    mod=ob.modifiers.new('Moulded edge radius','BEVEL');mod.width=width;mod.segments=segments;mod.affect='EDGES';mod.limit_method='ANGLE';mod.angle_limit=math.radians(25)
    bpy.ops.object.modifier_apply(modifier=mod.name)
    mod=ob.modifiers.new('Balanced surface normals','WEIGHTED_NORMAL');mod.keep_sharp=True;mod.weight=50
    bpy.ops.object.modifier_apply(modifier=mod.name)

def combine_into(ob,extra):
    # Join decoration into the existing object without changing its origin.
    bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);extra.select_set(True)
    bpy.context.view_layer.objects.active=ob;bpy.ops.object.join()
    mat=ob.data.materials[0]
    ob.data.materials.clear();ob.data.materials.append(mat)
    for p in ob.data.polygons:p.material_index=0

def export(name):
    for ob in bpy.context.scene.objects:
        if ob.type=='MESH':
            bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
            bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
    bpy.ops.object.select_all(action='SELECT')
    source_dir=ROOT/'build'/'source'/'blend';source_dir.mkdir(parents=True,exist_ok=True)
    bpy.ops.wm.save_as_mainfile(filepath=str(source_dir/(Path(name).stem+'.blend')),compress=True)
    bpy.ops.export_scene.gltf(filepath=str(OUT/name),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_materials='EXPORT',export_cameras=False,export_lights=False,export_animations=False,export_extras=False)
    # Actual supplied checker, with only this file selected.
    cmd=[PYTHON,'-c',"import sys;sys.path.insert(0,sys.argv[1]);import check_glb as c;p=sys.argv[2];n=sys.argv[3];e=c.check(n,p);print(('PASS ' if not e else 'FAIL ')+n);print('\\n'.join(e));sys.exit(bool(e))",str(PACK),str(OUT/name),name]
    r=subprocess.run(cmd,text=True,capture_output=True)
    print(r.stdout,flush=True)
    if r.returncode:print(r.stderr,flush=True);raise RuntimeError('Checker rejected '+name)

def screw_mesh(mesh,x,z,h,r=.0022):
    # Two raised halves leave a genuine slotted screw head without a texture.
    mesh.box((x-r*.36,h+.00015,z),(1,0,0),(0,0,1),r*.48,r*1.35,.0003)
    mesh.box((x+r*.36,h+.00015,z),(1,0,0),(0,0,1),r*.48,r*1.35,.0003)

def guides(prefix,key):
    name=prefix+'_Guides.glb';obs=import_ref(name);m=DATA['machines'][key];c=m['colours']
    metal_hex=c['trim'] if key!='rodent' else '#bec8dc'
    wood=material(prefix+'_sealed_wood',c['body'],0,.34)
    metal=material(prefix+'_polished_metal',metal_hex,.78,.22)
    plastic=material(prefix+'_moulded_plastic',c['plastic'],.05,.27)
    rubber=material(prefix+'_ivory_rubber','#f4ede0',0,.7)
    # Rebuild the imported object's surface as the exact union of reference
    # silhouettes. The blockout's overlapping segment caps cause black facets after
    # triangulation; a continuous exterior has no internal caps or z-fighting.
    timber=Mesh();height=.056
    for poly in WOOD_PROFILES[key]:
        n=len(poly);vs=[(x,y,z) for y in (0,height) for x,z in poly]
        faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
        faces.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
        timber.add(vs,faces)
    timber.object('Guides_Wood',wood,obs['Guides_Wood'])
    wires=Mesh()
    for wall in m['walls']:
        if wall['material']!='metal':continue
        r=wall['thickness']/2;top=wall['height'];points=wall['points']
        for h in (top-r,.0112):
            wires.tube([(x,h,z) for x,z in points],r,8)
        ends=[points[0],points[-1]]
        if len(points)==2 and math.dist(points[0],points[-1])>.18:
            ends.append([(points[0][j]+points[1][j])/2 for j in range(2)])
        for x,z in ends:wires.lathe(x,z,[(0,r),(top,r)],8)
    wires.object('Guides_Metal',metal,obs['Guides_Metal'])
    for g in ('Guides_Rubber','Guides_Plastic'):
        if g in obs:
            if g.endswith('Rubber'):
                assign(obs[g],rubber);bevel(obs[g],.0007,1)
            else:
                shaped=Mesh();height=.028
                for poly in WOOD_PROFILES[key+'_plastic']:
                    n=len(poly);vs=[(x,y,z) for y in (0,height) for x,z in poly]
                    faces=[tuple(reversed(range(n))),tuple(range(n,2*n))]
                    faces.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
                    shaped.add(vs,faces)
                shaped.object(g,plastic,obs[g])
    pm=Mesh();pr=Mesh();hardware=Mesh()
    for p in m['posts']:
        x,z=p['centre'];r=p['radius'];h=p['height']
        if p['material']=='metal':
            pm.lathe(x,z,[(0,r),(.002,r),(h-.003,r*.72),(h,r)],8)
        else:
            # Full-radius middle collar retains the reference contact outline.
            pr.lathe(x,z,[(0,r*.65),(.008,r*.70),(.011,r),(.020,r),(.025,r*.7),(h,r*.60)],8)
            screw_mesh(hardware,x,z,h+.0004,min(.0022,r*.42))
    pm.object('Posts_Metal',metal,obs['Posts_Metal']);pr.object('Posts_Rubber',rubber,obs['Posts_Rubber'])
    if hardware.v:hardware.object('Deco_PostScrewCaps',metal)
    trim=Mesh()
    for wall in m['walls']:
        if wall['material']=='wood':
            # Thin bead above the original rail, always inside its footprint.
            trim.tube([(x,wall['height']+.0009,z) for x,z in wall['points']],.00115,6)
    trim.object('Deco_RailCrests',metal)
    export(name)

def slingshots(prefix,key):
    name=prefix+'_Slingshots.glb';obs=import_ref(name);m=DATA['machines'][key];c=m['colours']
    plastic=material(prefix+'_sling_plastic',c['plastic'],.05,.26)
    rubber=material(prefix+'_kicking_rubber','#fff7e8',0,.64)
    metal=material(prefix+'_sling_screws',c['trim'] if key!='rodent' else '#bec8dc',.75,.22)
    screws=Mesh()
    for s in m['slingshots']:
        body=obs[s['body_name']];assign(body,plastic);bevel(body,.00085,2)
        bat=obs[s['rubber_name']];assign(bat,rubber);bevel(bat,.0011,2)
        p=s['body_triangle'];cx=sum(v[0] for v in p)/3;cz=sum(v[1] for v in p)/3
        inset=[(cx+(x-cx)*.76,cz+(z-cz)*.76) for x,z in p]
        detail=Mesh();h=s['body_height']
        verts=[(x,y,z) for y in (h-.0003,h+.0010) for x,z in inset]
        detail.add(verts,[(0,2,1),(3,4,5),(0,1,4,3),(1,2,5,4),(2,0,3,5)])
        for x,z in inset:screw_mesh(screws,x,z,h+.0014,.0020)
        extra=detail.object('Detail',plastic);combine_into(body,extra)
    screws.object('Deco_SlingScrewHeads',metal)
    export(name)

# Small open stroke alphabet for moulded, untextured target lettering.
STROKES={
 'A':[[(0,0),(.5,1),(1,0)],[(.22,.40),(.78,.40)]],
 'C':[[(1,.87),(.72,1),(.25,.93),(0,.67),(0,.28),(.25,0),(.73,0),(1,.14)]],
 'O':[[(.25,0),(0,.25),(0,.75),(.25,1),(.75,1),(1,.75),(1,.25),(.75,0),(.25,0)]],
 'R':[[(0,0),(0,1),(.72,1),(1,.78),(1,.62),(.73,.48),(0,.48)],[(.5,.48),(1,0)]],
 'N':[[(0,0),(0,1),(1,0),(1,1)]],
 'S':[[(1,.87),(.72,1),(.2,1),(0,.78),(.08,.59),(.84,.41),(1,.22),(.8,0),(.25,0),(0,.13)]],
 'P':[[(0,0),(0,1),(.7,1),(1,.78),(1,.61),(.75,.48),(0,.48)]],
 'I':[[ (0,1),(1,1)],[(.5,1),(.5,0)],[(0,0),(1,0)]],
 'Y':[[(0,1),(.5,.5),(1,1)],[(.5,.5),(.5,0)]],
 'F':[[(0,0),(0,1),(1,1)],[(0,.55),(.8,.55)]],
 'U':[[(0,1),(0,.22),(.2,0),(.8,0),(1,.22),(1,1)]],
 'E':[[(1,0),(0,0),(0,1),(1,1)],[(0,.5),(.8,.5)]],
 'L':[[(0,1),(0,0),(1,0)]],
}

def targets(prefix,key):
    name=prefix+'_Targets.glb';obs=import_ref(name);m=DATA['machines'][key];c=m['colours']
    mat=material(prefix+'_target_colour',c['target'],.03,.32)
    for t in m['targets']:
        ob=obs[t['name']];assign(ob,mat);bevel(ob,.00065,1)
        a=Vector((t['a'][0],0,t['a'][1]));b=Vector((t['b'][0],0,t['b'][1]));u=(b-a).normalized();n=Vector((-u.z,0,u.x));centre=(a+b)/2
        # Pick face normal toward open field / player rather than the rail.
        toward=Vector((.31-centre.x,0,-.3-centre.z))
        if n.dot(toward)<0:n=-n
        extras=Mesh();depth=t['thickness'];w=t['width'];h=t['height']
        if t['kind']=='standup':
            # Compact rear L-bracket, no more than 2 mm beyond the contact face.
            extras.box(centre-n*(depth/2+.0008)+Vector((0,.009,0)),u,n,min(w*.38,.015),.0016,.018)
            extras.box(centre-n*(depth/2+.0006)+Vector((0,.0013,0)),u,n,min(w*.55,.023),.003,.0026)
        letter=t['id'].split('_')[-1].upper()
        if t['id'].startswith('oak_'):letter='O'
        if letter in STROKES:
            lw=min(w*.49,.014);lh=.017;stroke=.0007
            facecentre=centre+n*(depth/2+.00025)+Vector((0,.009,0))
            for chain in STROKES[letter]:
                for p,q in zip(chain,chain[1:]):
                    p3=facecentre+u*((p[0]-.5)*lw)+Vector((0,p[1]*lh,0));q3=facecentre+u*((q[0]-.5)*lw)+Vector((0,q[1]*lh,0))
                    d=q3-p3;du=d.normalized();dv=n.cross(du).normalized();mid=(p3+q3)/2
                    # Rectangular embossed stroke using its own orthogonal basis.
                    vs=[mid+du*(sa*d.length/2)+dv*(sb*stroke/2)+n*(sc*.00022) for sc in (-1,1) for sb in (-1,1) for sa in (-1,1)]
                    extras.add(vs,[(0,2,3,1),(4,5,7,6),(0,1,5,4),(2,6,7,3),(0,4,6,2),(1,3,7,5)])
        extra=extras.object('Detail',mat);combine_into(ob,extra)
    export(name)

def spinner():
    name='Acorn_Spinner.glb';obs=import_ref(name)
    metal=material('Acorn_spinner_chrome','#bec8dc',.86,.19)
    ob=obs['Spinner1'];assign(ob,metal);bevel(ob,.00035,1)
    t=DATA['machines']['acorn']['spinners'][0];a=t['a'];b=t['b'];h=t['axis_height']
    axle=Mesh();axle.tube([(a[0]-.0018,h,a[1]),(b[0]+.0018,h,b[1])],.0011,8)
    extra=axle.object('Detail',metal);combine_into(ob,extra)
    bracket=Mesh();r=.0011
    bracket.tube([(a[0]-.004,0,a[1]),(a[0]-.004,h+.020,a[1]),(b[0]+.004,h+.020,b[1]),(b[0]+.004,0,b[1])],r,8)
    for x,z in (a,b):bracket.lathe(x+(-.004 if x==a[0] else .004),z,[(0,.0028),(.001,.0028)],8)
    bracket.object('Deco_SpinnerWireBracket',metal)
    export(name)

if __name__=='__main__':
    only=sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
    for pre,key in [('Acorn','acorn'),('Rodent','rodent'),('Space','space')]:
        for fn in (guides,slingshots,targets):
            if not only or f'{pre}_{fn.__name__}' in only:fn(pre,key)
    if not only or 'spinner' in only:spinner()
