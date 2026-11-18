"""Build the shared pinball assets in Blender, starting with supplied references.

Run: blender -b --python build_shared_and_ramps.py -- /path/to/Pinball_ChatGPT_Pack /path/to/build
All authored positions in this script use the specified glTF frame (metres, Y up).
"""
import bpy, bmesh, math, json, sys
from pathlib import Path
from mathutils import Vector

ARGS = sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else []
ROOT = Path(__file__).resolve().parents[2]
PACK = Path(ARGS[0]) if ARGS else ROOT/'work/Pinball_ChatGPT_Pack'
BUILD = Path(ARGS[1]) if len(ARGS)>1 else ROOT/'build'
OUT = BUILD/'models'
BLENDS = BUILD/'source/blend'
OUT.mkdir(parents=True,exist_ok=True); BLENDS.mkdir(parents=True,exist_ok=True)
D = json.loads((PACK/'pinball_data.json').read_text())

def gb(v):
    return Vector((v[0],-v[2],v[1]))

def bg(v):
    return (v[0],v[2],-v[1])

def linear(v):
    return v/12.92 if v<=.04045 else ((v+.055)/1.055)**2.4

def mat(name,col,metal=0,rough=.35,alpha=1):
    if isinstance(col,str): col=tuple(int(col[i:i+2],16)/255 for i in (1,3,5))
    rgb=tuple(linear(v) for v in col)
    m=bpy.data.materials.new(name); m.use_nodes=True
    p=m.node_tree.nodes.get('Principled BSDF')
    p.inputs['Base Color'].default_value=(*rgb,alpha)
    p.inputs['Metallic'].default_value=metal
    p.inputs['Roughness'].default_value=rough
    p.inputs['Alpha'].default_value=alpha
    m.diffuse_color=(*rgb,alpha)
    if alpha<1:
        m.surface_render_method='BLENDED'
        m.use_transparent_shadow=False
    return m

def assign(ob,m):
    ob.data.materials.clear(); ob.data.materials.append(m)
    for p in ob.data.polygons: p.material_index=0

def reset(filename=None):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system='METRIC'
    bpy.context.scene.unit_settings.scale_length=1
    if filename:
        bpy.ops.import_scene.gltf(filepath=str(PACK/'reference'/filename))
    return {o.name:o for o in bpy.context.scene.objects if o.type=='MESH'}

def clean_normals(ob):
    bm=bmesh.new();bm.from_mesh(ob.data)
    bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
    bm.to_mesh(ob.data);bm.free();ob.data.update()

def mesh(name,verts,faces,m=None,existing=None,smooth=False):
    me=bpy.data.meshes.new(name+'_Geometry')
    ob=existing
    if ob is None:
        ob=bpy.data.objects.new(name,me);bpy.context.collection.objects.link(ob)
    else:
        ob.data=me
    inv=ob.matrix_world.inverted()
    me.from_pydata([inv @ gb(v) for v in verts],[],faces);me.update()
    clean_normals(ob)
    if m: assign(ob,m)
    if smooth:
        for p in me.polygons:p.use_smooth=True
    return ob

def combine(parts):
    verts=[];faces=[]
    for vs,fs in parts:
        n=len(verts);verts.extend(vs);faces.extend(tuple(n+i for i in f) for f in fs)
    return verts,faces

def extract(ob):
    return [bg(ob.matrix_world @ v.co) for v in ob.data.vertices],[tuple(p.vertices) for p in ob.data.polygons]

def add_geo(ob,parts):
    m=ob.data.materials[0] if ob.data.materials else None
    vs,fs=combine([extract(ob)]+parts)
    mesh(ob.name,vs,fs,m,ob)

def box(c,s):
    x,y,z=c;a,b,c2=[v/2 for v in s]
    v=[(x+dx*a,y+dy*b,z+dz*c2) for dx,dy,dz in [(-1,-1,-1),(1,-1,-1),(1,-1,1),(-1,-1,1),(-1,1,-1),(1,1,-1),(1,1,1),(-1,1,1)]]
    f=[(0,3,2,1),(4,5,6,7),(0,1,5,4),(1,2,6,5),(2,3,7,6),(3,0,4,7)]
    return v,f

def tube(a,b,r,n=12,r2=None):
    a,b=Vector(a),Vector(b);t=(b-a).normalized()
    other=Vector((0,1,0)) if abs(t.y)<.9 else Vector((1,0,0))
    u=t.cross(other).normalized();v=t.cross(u).normalized();r2=r if r2 is None else r2
    verts=[tuple(c+rr*(math.cos(i*2*math.pi/n)*u+math.sin(i*2*math.pi/n)*v)) for c,rr in [(a,r),(b,r2)] for i in range(n)]
    faces=[tuple(range(n-1,-1,-1)),tuple(range(n,2*n))]
    faces.extend((i,(i+1)%n,(i+1)%n+n,i+n) for i in range(n))
    return verts,faces

def lathe(profile,segments=32,axis='y',centre=(0,0,0)):
    # Profile = (height along axis, radius). Closed end caps are added.
    verts=[]
    for h,r in profile:
        for i in range(segments):
            a=i*2*math.pi/segments
            p=(r*math.cos(a),h,r*math.sin(a)) if axis=='y' else (r*math.cos(a),r*math.sin(a),h)
            verts.append(tuple(p[j]+centre[j] for j in range(3)))
    faces=[tuple(range(segments-1,-1,-1))]
    for j in range(len(profile)-1):
        faces.extend((j*segments+i,j*segments+(i+1)%segments,(j+1)*segments+(i+1)%segments,(j+1)*segments+i) for i in range(segments))
    faces.append(tuple((len(profile)-1)*segments+i for i in range(segments)))
    return verts,faces

def bevel(ob,width,segments=1):
    bpy.context.view_layer.objects.active=ob
    mod=ob.modifiers.new('Manufactured edge radii','BEVEL');mod.width=width;mod.segments=segments
    mod.limit_method='ANGLE';mod.angle_limit=.45
    bpy.ops.object.modifier_apply(modifier=mod.name)
    clean_normals(ob)

def weighted(ob):
    # Use flat broad faces; weighted custom normals soften small edge facets.
    bpy.context.view_layer.objects.active=ob
    for p in ob.data.polygons:p.use_smooth=True
    mod=ob.modifiers.new('Weighted face normals','WEIGHTED_NORMAL');mod.keep_sharp=True;mod.weight=50
    try:bpy.ops.object.modifier_apply(modifier=mod.name)
    except RuntimeError:ob.modifiers.remove(mod)

def save(filename):
    bpy.ops.object.select_all(action='DESELECT')
    tris=0
    for ob in bpy.context.scene.objects:
        if ob.type=='MESH':
            ob.select_set(True);bpy.context.view_layer.objects.active=ob
            bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
            for colour in list(ob.data.color_attributes):
                ob.data.color_attributes.remove(colour)
            if len(ob.data.materials)!=1:raise ValueError(f'{ob.name}: expected one material')
            ob.data.calc_loop_triangles();tris+=len(ob.data.loop_triangles)
    bpy.ops.wm.save_as_mainfile(filepath=str(BLENDS/(Path(filename).stem+'.blend')))
    bpy.ops.export_scene.gltf(filepath=str(OUT/filename),export_format='GLB',use_selection=True,
        export_yup=True,export_apply=True,export_animations=False,export_cameras=False,export_lights=False,
        export_materials='EXPORT',export_extras=False)
    print('BUILT',filename,'triangles',tris,flush=True)

def build_flipper():
    o=reset('Pinball_Flipper.glb')
    rubber=mat('Rubber | warm white','#f8f5ea',rough=.48)
    red=mat('Tip | red rubber','#df382b',rough=.42)
    dark=mat('Pivot | gunmetal','#30343c',metal=.8,rough=.25)
    for n,m in [('Bat',rubber),('Tip',red),('Pin',dark)]:
        assign(o[n],m);bevel(o[n],.0004,1);weighted(o[n])
    # Shallow raised white rib fits fully inside the bat outline.
    rib=box((.041,.0101,0),(.052,.00065,.0032))
    add_geo(o['Bat'],[rib])
    # Hexagonal pivot crown, located about the original pivot.
    add_geo(o['Pin'],[tube((0,.0102,0),(0,.0111,0),.0033,6)])
    save('Pinball_Flipper.glb')

def build_bumper():
    o=reset('Pinball_PopBumper.glb')
    body=mat('Bumper body | recolourable','#aa3c1e',rough=.3)
    cap=mat('Bumper cap | recolourable','#ffecb4',rough=.22)
    metal=mat('Bumper strike ring | chrome','#c4c9ce',metal=.82,rough=.2)
    profile=[(0,.0255),(.002,.031),(.005,.0365),(.007,.0365),(.013,.0255),(.018,.0205),(.035,.0215),(.039,.0336),(.0448,.0336)]
    v,f=lathe(profile,28);mesh('Body',v,f,body,o['Body'],True)
    v,f=lathe([(.0448,.0268),(.0465,.02856),(.0535,.02856),(.056,.0258),(.0565,.020)],28)
    mesh('Cap',v,f,cap,o['Cap'],True)
    # A narrow polished strike ring at the skirt, independently recolourable.
    v,f=lathe([(.012,.027),(.013,.030),(.015,.030),(.016,.027)],24)
    mesh('Deco_StrikeRing',v,f,metal,smooth=True)
    save('Pinball_PopBumper.glb')

def build_plunger():
    o=reset('Pinball_Plunger.glb')
    metal=mat('Plunger shaft | brushed steel','#bdc2ca',metal=.85,rough=.22)
    red=mat('Plunger knob | red resin','#d9362e',rough=.24)
    v,f=lathe([(-.224,.0038),(-.222,.0049),(-.016,.0049),(-.014,.006)],12,'z')
    mesh('Rod',v,f,metal,o['Rod'],True)
    # Turned grip with a pair of moulded grip ridges; original knob-centred pivot.
    v,f=lathe([(-.014,.009),(-.011,.014),(-.008,.0154),(-.004,.0147),(0,.0154),(.009,.0154),(.014,.012)],16,'z')
    mesh('Knob',v,f,red,o['Knob'],True)
    save('Pinball_Plunger.glb')

def build_gate():
    o=reset('Pinball_Gate.glb')
    metal=mat('Gate | polished wire','#c2c9d1',metal=.9,rough=.18)
    # U-shaped swing gate plus its hinge bar; hinge remains at origin Y=0.
    parts=[tube((-.02944,0,0),(.02944,0,0),.0013,8),tube((-.028,-.001,0),(-.028,-.013,0),.0013,8),
        tube((.028,-.001,0),(.028,-.013,0),.0013,8),tube((-.028,-.013,0),(.028,-.013,0),.0013,8)]
    v,f=combine(parts);mesh('Flap',v,f,metal,o['Flap'],True)
    save('Pinball_Gate.glb')

def build_cabinet():
    o=reset('Pinball_Cabinet.glb')
    # Butt the front and back panels between the side panels. The blockout's
    # fully overlapping boxes otherwise create coplanar exterior faces and
    # shimmer; these inset joints preserve the complete cabinet silhouette.
    for n in ('FrontWall','BackWall'):
        vs,fs=extract(o[n])
        vs=[(x*(.336/.378),y,z) for x,y,z in vs]
        mesh(n,vs,fs,existing=o[n])
    vs,fs=extract(o['Body'])
    fixed=[]
    for x,y,z in vs:
        front=z>0
        # Identify the upper/lower skin in the tilted original base slab.
        upper=(y>.70) if front else (y>.88)
        yy,zz=(.68456,.72787) if front else (.85383,-.67596)
        if upper:yy+=.03336;zz+=.00402
        fixed.append((x*(.336/.378),yy,zz))
    mesh('Body',fixed,fs,existing=o['Body'])
    body=mat('Cabinet lacquer | recolourable','#764a28',rough=.3)
    trim=mat('Cabinet trim | recolourable','#c4a05c',metal=.72,rough=.25)
    legmat=mat('Cabinet legs | recolourable','#beaa78',metal=.78,rough=.26)
    dark=mat('Access door | graphite','#20232b',metal=.5,rough=.32)
    darkrub=mat('Feet and vents | black','#11151c',rough=.55)
    button=mat('Flipper buttons | red','#df382b',rough=.2)
    screen=mat('Backglass | dark backdrop','#101323',rough=.3)
    light=mat('Light strip | recolourable','#ffecb4',rough=.28)
    glass=mat('Glass | 95 percent clear','#e7f1f9',rough=.08,alpha=.05)
    for n,ob in o.items():
        m=(glass if n=='Glass' else trim if n=='LockdownBar' else legmat if n.startswith('Leg') else
            dark if n=='CoinDoor' else button if 'FlipperButton' in n else screen if n=='Backglass' else
            light if n=='LightStrip' else body)
        assign(ob,m)
        if n=='Glass':continue
        if n.startswith('Leg'):continue
        if n.startswith('FlipperButton'):
            vs,_=extract(ob);mi=[min(v[i] for v in vs) for i in range(3)];ma=[max(v[i] for v in vs) for i in range(3)]
            c=[(mi[i]+ma[i])/2 for i in range(3)]
            a=(mi[0],c[1],c[2]);b=(ma[0],c[1],c[2])
            v,f=tube(a,b,.0151,16);mesh(n,v,f,m,ob,True);bevel(ob,.0012,2)
        else:
            bevel(ob,.003 if n not in ('CoinDoor','LockdownBar','Backglass','LightStrip') else .0016,2)
            weighted(ob)
    # Tapered legs and leveler feet, with all original object origins untouched.
    feet=[];bolts=[]
    for n in ('Leg_FL','Leg_FR','Leg_BL','Leg_BR'):
        c=D['cabinet']['parts_as_8_corners'][n]
        x=(min(v[0] for v in c)+max(v[0] for v in c))/2
        z=(min(v[2] for v in c)+max(v[2] for v in c))/2;h=max(v[1] for v in c)
        verts=[]
        for yy,sz in [(0,.033),(.045,.034),(h-.06,.05),(h,.051)]:
            verts.extend((x+dx*sz/2,yy,z+dz*sz/2) for dx,dz in [(-1,-1),(1,-1),(1,1),(-1,1)])
        faces=[(3,2,1,0),(12,13,14,15)]
        for j in range(3):faces.extend((4*j+i,4*j+(i+1)%4,4*(j+1)+(i+1)%4,4*(j+1)+i) for i in range(4))
        mesh(n,verts,faces,legmat,o[n]);bevel(o[n],.0012,1);weighted(o[n])
        feet.append(tube((x,0,z),(x,.009,z),.027,12))
        # One visible hex bolt on the outward face of each leg top.
        sign=1 if x>0 else -1
        bolts.append(tube((x+sign*.024,h-.025,z),(x+sign*.027,h-.025,z),.0042,6))
    v,f=combine(feet);mesh('Deco_LevelerFeet',v,f,darkrub)
    # Side-rail strips match the cabinet's already tilted front and rear edge.
    rails=[]
    for x in (-.355,.355):
        a=Vector((x,1.081,.785));b=Vector((x,1.247,-.648))
        rails.append(tube(a,b,.006,8))
    v,f=combine(rails);mesh('Deco_SideRails',v,f,trim,smooth=True)
    # Thin lower pinstripe on either side; solid coloured mesh, never a texture.
    band=[]
    for sign in (-1,1):
        x=sign*.379
        band.append(tube((x,.735,.747),(x,.911,-.689),.0034,6))
        band.append(tube((x,.746,.748),(x,.922,-.688),.0011,6))
    v,f=combine(band);mesh('Deco_CabinetPinstripe',v,f,trim)
    # Frame the door without coin slots or money graphics.
    doorframe=[]
    for x in (-.101,.101):doorframe.append(tube((x,.707,.776),(x,.864,.795),.003,8))
    for y,z in [(.707,.776),(.864,.795)]:doorframe.append(tube((-.101,y,z),(.101,y,z),.003,8))
    v,f=combine(doorframe);mesh('Deco_AccessDoorBezel',v,f,trim)
    # FREE PLAY is geometry on the door and obeys the no-extra-texture rule.
    cu=bpy.data.curves.new('FreePlayLettering','FONT');cu.body='FREE PLAY';cu.align_x='CENTER';cu.align_y='CENTER'
    cu.size=.022;cu.extrude=.00015;cu.resolution_u=2
    ob=bpy.data.objects.new('Deco_FreePlay',cu);bpy.context.collection.objects.link(ob)
    ob.location=gb((0,.79,.7875));ob.rotation_euler=(math.radians(90)+math.radians(6.87549),0,0)
    bpy.ops.object.select_all(action='DESELECT');ob.select_set(True);bpy.context.view_layer.objects.active=ob
    bpy.ops.object.convert(target='MESH');assign(ob,light)
    # Backbox bezel and the backglass retain unobstructed score-writing area.
    bezel=[]
    for x in (-.354,.354):bezel.append(box((x,1.701,-.513),(.012,.842,.006)))
    for y in (1.278,2.124):bezel.append(box((0,y,-.513),(.72,.012,.006)))
    v,f=combine(bezel);ob=mesh('Deco_BackboxBezel',v,f,trim);bevel(ob,.001,1)
    # Dark cooling slots in the backbox side faces, all one decoration node.
    vents=[]
    for sign in (-1,1):
        for y in (1.34,1.365,1.39,1.415):vents.append(box((sign*.379,y,-.613),(.002,.008,.085)))
    v,f=combine(vents);mesh('Deco_BackboxVents',v,f,darkrub)
    # Recessed hardware plates and screw heads set off the cabinet corners.
    corners=[]
    for sign in (-1,1):
        for yy,zz in [(.735,.738),(.91,-.682)]:
            corners.append(box((sign*.381,yy,zz),(.004,.06,.028)))
            for dy in (-.018,.018):
                bolts.append(tube((sign*.383,yy+dy,zz),(sign*.385,yy+dy,zz),.0034,8))
    v,f=combine(corners);ob=mesh('Deco_CornerPlates',v,f,trim);bevel(ob,.001,1)
    for x in (-.085,.085):
        for y,z in [(.723,.780),(.846,.795)]:bolts.append(tube((x,y,z),(x,y,z+.002),.0025,8))
    v,f=combine(bolts);mesh('Deco_Fasteners',v,f,legmat)
    # Button collars remain compact and follow their reference positions.
    collars=[]
    for sign in (-1,1):
        x=sign*.377
        collars.append(tube((x,.889775,.639805),(x+sign*.005,.889775,.639805),.019,16))
    v,f=combine(collars);mesh('Deco_ButtonCollars',v,f,trim,smooth=True)
    save('Pinball_Cabinet.glb')

def build_ramps(machine,filename):
    o=reset(filename)
    colour=D['machines'][machine]['colours']['plastic']
    plastic=mat('Ramp track | tinted clear plastic',colour,metal=0,rough=.16,alpha=.46)
    chrome=mat('Ramp entrance | polished steel','#c2c9d1',metal=.82,rough=.2)
    lips=[];edgecaps=[]
    for rd in D['machines'][machine]['ramps']:
        ob=o[rd['name']];assign(ob,plastic)
        walls=[];path=rd['path'];w=rd['track_width']/2
        ns=[]
        for pa,pb in zip(path,path[1:]):
            dx=pb[0]-pa[0];dz=pb[2]-pa[2];ll=math.hypot(dx,dz)
            ns.append(Vector((-dz/ll,0,dx/ll)))
        # Join sidewall corners with mitres, instead of overlapping segment
        # boxes. This removes open notches while retaining the original track.
        mitres=[]
        for j in range(len(path)):
            if j==0:n=ns[0]
            elif j==len(path)-1:n=ns[-1]
            else:
                n=(ns[j-1]+ns[j]).normalized()
                n=n/max(.74,n.dot(ns[j]))
            mitres.append(n)
        for sign in (-1,1):
            vv=[];ff=[];crest=[]
            for j,pp in enumerate(path):
                p=Vector(pp);n=mitres[j]*sign
                hh=.002 if j==0 else .003 if j==len(path)-1 else .022
                inside=p+n*(w-.0007);outside=p+n*(w+.0018)
                vv.extend([tuple(inside),tuple(outside),tuple(outside+Vector((0,hh,0))),tuple(inside+Vector((0,hh,0)))])
                crest.append(inside+Vector((0,hh,0)))
            for j in range(len(path)-1):
                for k in range(4):ff.append((j*4+k,j*4+(k+1)%4,(j+1)*4+(k+1)%4,(j+1)*4+k))
                edgecaps.append(tube(crest[j],crest[j+1],.0008,6))
            ff.extend([(3,2,1,0),(4*(len(path)-1),4*(len(path)-1)+1,4*(len(path)-1)+2,4*(len(path)-1)+3)])
            walls.append((vv,ff))
            for j in range(1,len(path)-1):
                p=Vector(path[j]);a=p+sign*ns[j-1]*w;b=p+sign*mitres[j]*w;c=p+sign*ns[j]*w
                # Small top-surface corner infill; reference top faces remain.
                walls.append(([tuple(a),tuple(b),tuple(c)],[(0,1,2)]))
        add_geo(ob,walls)
        # The reference track and path remain unchanged. A 4 mm landing plate
        # overlaps each end and terminates on the playfield (top at Y=0).
        for end,nextp in [(path[0],path[1]),(path[-1],path[-2])]:
            a=Vector(end);b=Vector(nextp);t=Vector((b.x-a.x,0,b.z-a.z)).normalized();n=Vector((-t.z,0,t.x))
            c0=a-t*.004;c1=a+t*.002
            vv=[tuple(c0-n*w),tuple(c0+n*w),tuple(c1+n*w),tuple(c1-n*w)]
            vv+=[(x,y-.0008,z) for x,y,z in vv]
            ff=[(0,1,2,3),(7,6,5,4),(0,4,5,1),(1,5,6,2),(2,6,7,3),(3,7,4,0)]
            lips.append((vv,ff))
    v,f=combine(lips);mesh('Deco_EntranceFlaps',v,f,chrome)
    v,f=combine(edgecaps);mesh('Deco_RampEdgeBeads',v,f,chrome,smooth=True)
    save(filename)

def build_hoods():
    reset()
    blue=mat('Pod hood | ice blue lacquer',D['machines']['space']['colours']['plastic'],metal=.5,rough=.22)
    for i,h in enumerate(D['machines']['space']['holes'],1):
        cx,cz=h['centre'];r=h['radius'];v=[];f=[]
        # Low, ramped semicircular rim on the far (negative-Z) half only.
        # Outer edge starts at the board and rises to the inner 5 mm lip.
        seg=24
        for j in range(seg+1):
            a=math.pi+j*math.pi/seg
            taper=max(.03,max(0,math.sin(j*math.pi/seg))**.3)
            for rr,yy in [(r-.0015,0),(r-.0015,.005*taper),(r+.0045,.001*taper),(r+.0045,0)]:
                v.append((cx+rr*math.cos(a),yy,cz+rr*math.sin(a)))
        for j in range(seg):
            for k in range(4):f.append((j*4+k,j*4+(k+1)%4,(j+1)*4+(k+1)%4,(j+1)*4+k))
        f.extend([(3,2,1,0),(seg*4,seg*4+1,seg*4+2,seg*4+3)])
        mesh(f'PodHood{i}',v,f,blue)
    save('Space_PodHoods.glb')

if __name__=='__main__':
    selected=set(ARGS[2:]) if len(ARGS)>2 else set()
    jobs=[('flipper',build_flipper),('bumper',build_bumper),('plunger',build_plunger),('gate',build_gate),('cabinet',build_cabinet),
          ('wire',lambda:build_ramps('rodent','Rodent_Wire.glb')),('ramps',lambda:build_ramps('space','Space_Ramps.glb')),('hoods',build_hoods)]
    for name,job in jobs:
        if not selected or name in selected:job()
