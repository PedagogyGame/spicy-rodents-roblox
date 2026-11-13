"""Original Spicy Rodent shop/cafe/office art. Run with Blender 4.3+ --background --python.
Geometry is in meters, Blender Z-up, shop entrance toward Blender +Y (glTF -Z).
Package-local textures and Skateboards.blend are used; no network or external assets.
"""
import bpy, bmesh, math, json, random, os, sys, shutil
from pathlib import Path
from mathutils import Vector, Matrix
from math import sin, cos, pi
random.seed(2451)
HERE=Path(__file__).resolve().parent
PACK=HERE.parent if HERE.name=='Source' else HERE.parent/'Spicy_Rodent_Underground'
TEX=PACK/'Textures/Shop'
for d in ['GLB','Source','Previews','Metadata']: (PACK/d).mkdir(parents=True,exist_ok=True)
bpy.ops.wm.read_factory_settings(use_empty=True)
scene=bpy.context.scene
scene.unit_settings.system='METRIC';scene.unit_settings.scale_length=1
scene.name='04_Offbeat_Shop_Interior'
M={}; groups={}; collisions=[]

def mat(name,col,rough=.7,metal=0,tex=None,alpha=1):
    m=bpy.data.materials.new(name);m.use_nodes=True;m.diffuse_color=(*col,alpha)
    p=m.node_tree.nodes.get('Principled BSDF');p.inputs['Base Color'].default_value=(*col,alpha)
    p.inputs['Roughness'].default_value=rough;p.inputs['Metallic'].default_value=metal;p.inputs['Alpha'].default_value=alpha
    if alpha<1: m.surface_render_method='DITHERED'
    if tex:
        def image_node(path,data=False):
            n=m.node_tree.nodes.new('ShaderNodeTexImage');n.image=bpy.data.images.load(str(path),check_existing=True)
            if data: n.image.colorspace_settings.name='Non-Color'
            return n
        al=TEX/f'{tex}_basecolor.jpg'
        if al.exists():
            n=image_node(al);m.node_tree.links.new(n.outputs['Color'],p.inputs['Base Color'])
        no=TEX/f'{tex}_normal.png'
        if no.exists():
            n=image_node(no,True);b=m.node_tree.nodes.new('ShaderNodeNormalMap');b.inputs['Strength'].default_value=.46
            m.node_tree.links.new(n.outputs['Color'],b.inputs['Color']);m.node_tree.links.new(b.outputs['Normal'],p.inputs['Normal'])
        orm=TEX/f'{tex}_orm.png'
        if orm.exists():
            n=image_node(orm,True);sep=m.node_tree.nodes.new('ShaderNodeSeparateColor')
            m.node_tree.links.new(n.outputs['Color'],sep.inputs['Color'])
            m.node_tree.links.new(sep.outputs['Green'],p.inputs['Roughness']);m.node_tree.links.new(sep.outputs['Blue'],p.inputs['Metallic'])
    M[name]=m;return m

def graphic(name,filename):
    m=mat(name,(1,1,1),.88)
    n=m.node_tree.nodes.new('ShaderNodeTexImage');n.image=bpy.data.images.load(str(TEX/filename),check_existing=True)
    m.node_tree.links.new(n.outputs['Color'],m.node_tree.nodes.get('Principled BSDF').inputs['Base Color']);return m

mat('Brick',(0.5,.33,.21),tex='brick');mat('Concrete',(.4,.4,.35),tex='concrete')
mat('Plywood',(.52,.35,.16),tex='plywood');mat('PatinaSteel',(.23,.36,.31),tex='steel')
mat('DarkWood',(.18,.095,.045),.78);mat('AmberWood',(.35,.19,.075),.65)
mat('CreamPlaster',(.65,.61,.48),.92);mat('TealPaint',(.11,.27,.25),.87)
mat('BlackIron',(.028,.037,.037),.52,.7);mat('WornBrass',(.43,.29,.105),.48,.72)
mat('Rubber',(.025,.027,.026),.84);mat('Porcelain',(.78,.72,.58),.32)
mat('Clay',(.43,.19,.095),.86);mat('ClayGrey',(.27,.31,.27),.9)
mat('Leaves',(.065,.22,.09),.74);mat('LeavesLight',(.18,.34,.10),.74)
mat('Bamboo',(.24,.36,.105),.68);mat('Soil',(.055,.042,.025),1)
mat('Denim',(.13,.24,.33),.97);mat('BlackCloth',(.026,.025,.031),1)
mat('CreamCloth',(.71,.67,.53),.96);mat('RustCloth',(.36,.095,.045),.96)
mat('Leather',(.20,.09,.036),.75);mat('Red',(.49,.075,.045),.65)
mat('Paper',(.77,.71,.55),.96);mat('BookGreen',(.115,.22,.17),.92)
mat('BookBlue',(.09,.15,.23),.9);mat('Lamp',(.96,.64,.23),.4)
p=M['Lamp'].node_tree.nodes.get('Principled BSDF');p.inputs['Emission Color'].default_value=(1,.65,.27,1);p.inputs['Emission Strength'].default_value=.5
mat('WindowGlass',(.69,.83,.79),.12,0,alpha=.115)
for key,f in [('PosterBand','spice_squirrels.jpg'),('MenuDrinks','menu_drinks.png'),('MenuFood','menu_food.png'),('PosterHours','poster_after_hours.jpg'),('PosterJoys','poster_small_joys.jpg'),('PortraitVesper','portrait_mr_vesper.jpg'),('PortraitFern','portrait_miss_fern.jpg'),('Belgium','flag_belgium.jpg'),('Jamaica','flag_jamaica.jpg')]: graphic(key,f)
for key in ['midnight_static','loose_wire','dustline','clear_signal']:graphic('Tag_'+key,'tag_'+key+'.jpg')
graphic('PosterRooftop','poster_rooftop.jpg');graphic('ChiliAcorn','chili_acorn.jpg')

class Geo:
    def __init__(self,name,material):self.name=name;self.mat=material;self.v=[];self.f=[];self.uv=[];self.smooth=[]
    def face(self,coords,uv=None,smooth=False):
        i=len(self.v);self.v.extend([tuple(p) for p in coords]);self.f.append(tuple(range(i,i+len(coords))))
        self.uv.append(uv or ([(0,0),(1,0),(1,1),(0,1)] if len(coords)==4 else [(0,0)]*len(coords)));self.smooth.append(smooth)
    def make(self):
        me=bpy.data.meshes.new(self.name+'_Mesh');me.from_pydata(self.v,[],self.f);me.materials.append(M[self.mat]);me.update()
        ob=bpy.data.objects.new(self.name,me);scene.collection.objects.link(ob)
        uv=me.uv_layers.new(name='UVMap')
        for p,coords,smooth in zip(me.polygons,self.uv,self.smooth):
            p.use_smooth=smooth
            for li,u in zip(p.loop_indices,coords):uv.data[li].uv=u
        # Weld coincident face vertices, remove pole degeneracies, and orient solid faces.
        bm=bmesh.new();bm.from_mesh(me)
        bmesh.ops.remove_doubles(bm,verts=list(bm.verts),dist=0.000001)
        bmesh.ops.dissolve_degenerate(bm,edges=list(bm.edges),dist=0.0000001)
        bmesh.ops.recalc_face_normals(bm,faces=list(bm.faces))
        bm.to_mesh(me);bm.free();me.update()
        ob['category']=self.name.split('_')[0];ob['material_id']=self.mat;ob['units']='meters'
        return ob
def G(name,material):
    key=(name,material)
    if key not in groups:groups[key]=Geo(name,material)
    return groups[key]
def box(name,c,d,ma,rz=0,tile=0):
    c=Vector(c);a,b,h=[t/2 for t in d];r=Matrix.Rotation(rz,3,'Z');g=G(name,ma)
    # Front/back, sides, top/bottom have explicitly outward winding.
    faces=[[(a,-b,-h),(a,b,-h),(a,b,h),(a,-b,h)],[(-a,b,-h),(-a,-b,-h),(-a,-b,h),(-a,b,h)],
           [(-a,b,-h),(-a,b,h),(a,b,h),(a,b,-h)],[(a,-b,-h),(a,-b,h),(-a,-b,h),(-a,-b,-h)],
           [(-a,-b,h),(a,-b,h),(a,b,h),(-a,b,h)],[(-a,b,-h),(a,b,-h),(a,-b,-h),(-a,-b,-h)]]
    for f in faces:
        o,u,v=Vector(f[0]),Vector(f[1])-Vector(f[0]),Vector(f[3])-Vector(f[0])
        nu=max(1,math.ceil(u.length/tile)) if tile else 1;nv=max(1,math.ceil(v.length/tile)) if tile else 1
        for i in range(nu):
            for j in range(nv):
                pts=[o+u*i/nu+v*j/nv,o+u*(i+1)/nu+v*j/nv,o+u*(i+1)/nu+v*(j+1)/nv,o+u*i/nu+v*(j+1)/nv]
                g.face([c+r@p for p in pts])
def cyl(name,p1,p2,r,ma,n=10,r2=None):
    p1,p2=Vector(p1),Vector(p2);axis=(p2-p1).normalized();ref=Vector((0,0,1)) if abs(axis.z)<.9 else Vector((0,1,0))
    u=axis.cross(ref).normalized();v=axis.cross(u).normalized();r2=r if r2 is None else r2;g=G(name,ma)
    a=[p1+r*(cos(2*pi*i/n)*u+sin(2*pi*i/n)*v) for i in range(n)];b=[p2+r2*(cos(2*pi*i/n)*u+sin(2*pi*i/n)*v) for i in range(n)]
    g.face(list(reversed(a)));g.face(b)
    for i in range(n):j=(i+1)%n;g.face([a[i],a[j],b[j],b[i]],smooth=True)
def ball(name,c,scale,ma,n=10,rings=5):
    c=Vector(c);g=G(name,ma)
    for j in range(rings):
        t1=-pi/2+pi*j/rings;t2=-pi/2+pi*(j+1)/rings
        for i in range(n):
            a=2*pi*i/n;b=2*pi*(i+1)/n
            def pt(t,q):return c+Vector((scale[0]*cos(t)*cos(q),scale[1]*cos(t)*sin(q),scale[2]*sin(t)))
            g.face([pt(t1,a),pt(t1,b),pt(t2,b),pt(t2,a)],smooth=True)
def ring(name,c,r,minor,ma,n=12,k=5,axis='Z'):
    c=Vector(c);g=G(name,ma)
    rot=Matrix.Rotation(pi/2,3,'X') if axis=='Y' else Matrix.Rotation(pi/2,3,'Y') if axis=='X' else Matrix.Identity(3)
    def pt(a,b):return c+rot@Vector(((r+minor*cos(b))*cos(a),(r+minor*cos(b))*sin(a),minor*sin(b)))
    for i in range(n):
        for j in range(k):g.face([pt(2*pi*i/n,2*pi*j/k),pt(2*pi*(i+1)/n,2*pi*j/k),pt(2*pi*(i+1)/n,2*pi*(j+1)/k),pt(2*pi*i/n,2*pi*(j+1)/k)],smooth=True)
def poly_extrude(name,coords,depth,ma,y=0,center=(0,0,0),rz=0):
    g=G(name,ma);rot=Matrix.Rotation(rz,3,'Z');c=Vector(center)
    a=[c+rot@Vector((x,y-depth/2,z)) for x,z in coords];b=[c+rot@Vector((x,y+depth/2,z)) for x,z in coords]
    g.face(list(reversed(a)));g.face(b)
    for i in range(len(a)):j=(i+1)%len(a);g.face([a[i],a[j],b[j],b[i]])
def panel(name,c,w,h,material,normal=(0,1,0),frame=True):
    n=Vector(normal);up=Vector((0,0,1));right=up.cross(n);c=Vector(c);g=G(name,material)
    p=[c-right*w/2-up*h/2,c+right*w/2-up*h/2,c+right*w/2+up*h/2,c-right*w/2+up*h/2]
    g.face(p);g.face([q-n*.012 for q in reversed(p)])
    for i in range(4):j=(i+1)%4;g.face([p[i],p[i]-n*.012,p[j]-n*.012,p[j]])
    if frame:
        for sign in [-1,1]:
            cyl(name+'_Frame',c+right*sign*(w/2+.035)-up*(h/2+.04),c+right*sign*(w/2+.035)+up*(h/2+.04),.035,'DarkWood',4)
            cyl(name+'_Frame',c+up*sign*(h/2+.035)-right*(w/2+.04),c+up*sign*(h/2+.035)+right*(w/2+.04),.035,'DarkWood',4)
def collider(name,c,d):collisions.append({'name':name,'center':[c[0],c[2],-c[1]],'size':[d[0],d[2],d[1]],'shape':'box'})
def legtable(name,c,w,d,h,ma='Plywood'):
    x,y,z=c;box(name+'_Top',(x,y,z+h),(w,d,.09),ma)
    for a in [-1,1]:
        for b in [-1,1]:box(name+'_Legs',(x+a*(w/2-.12),y+b*(d/2-.12),z+h/2),(.09,.09,h),'DarkWood')
def shelf(name,x,y,w,d,height,ma='Plywood',levels=4):
    box(name+'_Sides',(x-w/2+.04,y,height/2),(.08,d,height),ma);box(name+'_Sides',(x+w/2-.04,y,height/2),(.08,d,height),ma)
    zs=[.2+i*(height-.35)/(levels-1) for i in range(levels)]
    for z in zs:box(name+'_Shelves',(x,y,z),(w,d,.065),ma)
    box(name+'_Back',(x,y-d/2+.025,height/2),(w,.05,height),'TealPaint')
    return zs
def pot(name,x,y,z,r=.25,h=.4,ma='Clay'):
    cyl(name,(x,y,z),(x,y,z+h),r*.72,ma,12,r)
    ring(name,(x,y,z+h),r,.035,ma,12,4);cyl(name+'_Soil',(x,y,z+h-.015),(x,y,z+h+.005),r*.88,'Soil',12)
def leaf(name,a,b,w,ma='Leaves'):
    a,b=Vector(a),Vector(b);d=b-a;side=d.cross(Vector((0,0,1))).normalized()*w;mid=a+d*.45;up=Vector((0,0,.025));g=G(name,ma)
    pts=[a,mid-side,b,mid+side,mid+up,mid-up*.3]
    for f in [(0,1,4),(1,2,4),(2,3,4),(3,0,4),(1,0,5),(2,1,5),(3,2,5),(0,3,5)]:g.face([pts[i] for i in f])
def plant(name,x,y,z=0,h=1.6,r=.28,kind='rubber'):
    pot(name+'_Pot',x,y,z,r,r*1.5,random.choice(['Clay','ClayGrey','Porcelain']))
    base=z+r*1.5
    if kind=='bamboo':
        for i in range(7):
            a=2*pi*i/7;px=x+r*.6*cos(a);py=y+r*.6*sin(a);hh=h*random.uniform(.7,1)
            cyl(name+'_Stems',(px,py,base),(px+.07*cos(a),py+.07*sin(a),base+hh),.028,'Bamboo',7)
            for k in range(4):
                zz=base+.32+k*(hh-.35)/4;ring(name+'_Nodes',(px,py,zz),.028,.008,'LeavesLight',7,3)
            for k in range(3):
                q=a+k*2.1;start=Vector((px,py,base+hh*(.5+.2*k)));end=start+Vector((cos(q)*.48,sin(q)*.48,.18))
                cyl(name+'_Twigs',start,end,.009,'Bamboo',5)
                for j in range(3):
                    p=start+(end-start)*(.3+.25*j);ang=q+(-.8 if j%2 else .8)
                    leaf(name+'_Leaves',p,p+Vector((cos(ang)*.35,sin(ang)*.35,.06)),.045,'LeavesLight')
    else:
        cyl(name+'_Stems',(x,y,base),(x,y,base+h*.9),.025,'Bamboo',7)
        count=12 if kind=='fern' else 11
        for i in range(count):
            a=i*2.4;hh=.1+(i/count)*h*.8;spread=.38 if kind=='rubber' else .5
            start=(x,y,base+hh);end=(x+spread*cos(a),y+spread*sin(a),base+hh+.16)
            leaf(name+'_Leaves',start,end,.12 if kind=='rubber' else .075,'Leaves' if i%3 else 'LeavesLight')

# Architectural shell: front +Y, three explicitly separated rooms.
box('FLOOR_Retail',(-3,0,-.12),(8,12,.24),'Concrete',tile=1.5)
box('FLOOR_Cafe',(4,1.5,-.11),(6,9,.22),'Plywood',tile=1)
box('FLOOR_Office',(4,-4.5,-.11),(6,3,.22),'Concrete',tile=1.5)
collider('RetailFloor',(-3,0,-.12),(8,12,.24));collider('CafeFloor',(4,1.5,-.11),(6,9,.22));collider('OfficeFloor',(4,-4.5,-.11),(6,3,.22))
box('WALL_Left',(-7.12,0,2.1),(.24,12.24,4.2),'Brick',tile=1.8)
box('WALL_Back',(0,-6.12,2.1),(14.48,.24,4.2),'Brick',tile=1.8)
box('WALL_Right',(7.12,0,2.1),(.24,12.24,4.2),'CreamPlaster')
for n,c,d in [('Left',(-7.12,0,2.1),(.24,12.24,4.2)),('Back',(0,-6.12,2.1),(14.48,.24,4.2)),('Right',(7.12,0,2.1),(.24,12.24,4.2))]:collider(n,c,d)
# Divider x=1: 2.8m open passage y=1.1..3.9 links retail and cafe.
for y,l in [(-2.45,7.1),(4.95,2.1)]:
    box('WALL_RoomDivider',(1,y,2.1),(.16,l,4.2),'CreamPlaster');collider('RoomDivider',(1,y,2.1),(.16,l,4.2))
box('WALL_DividerLintel',(1,2.5,3.65),(.18,2.8,1.1),'DarkWood')
for y in [1.1,3.9]:box('TRIM_PassagePosts',(1,y,1.45),(.22,.16,2.9),'DarkWood')
# Cafe wainscot strips; plain masonry remains above.
for i in range(30):
    yy=-2.85+i*.295;box('CAFE_WoodWainscot',(6.96,yy,.66),(.1,.276,1.3),'AmberWood')
box('CAFE_ChairRail',(6.88,1.5,1.33),(.1,9,.08),'DarkWood')
# Rear office behind beaded curtain, opening x=4.3..5.7.
for xx,ww in [(2.65,3.3),(6.35,1.3)]:
    box('WALL_OfficePartition',(xx,-3,2.1),(ww,.16,4.2),'TealPaint');collider('OfficePartition',(xx,-3,2.1),(ww,.16,4.2))
box('WALL_OfficeLintel',(5,-3,3.35),(1.4,.18,1.7),'TealPaint')
box('WALL_OfficeSide',(3,-4.5,2.1),(.14,3,4.2),'CreamPlaster')
box('ROOF_Removable',(0,0,4.27),(14.5,12.5,.14),'CreamPlaster')
for y in [-4,-1,2,5]:box('BEAMS_Ceiling',(0,y,4.05),(14.2,.16,.22),'DarkWood')
# Front glazing, open shop door and two large display windows. No exterior building.
for x,w in [(-6.35,1.3),(-4.6,.15),(-2.95,.15),(1,.2),(6.4,1.2)]:box('FRONT_Piers',(x,6,2.1),(w,.18,4.2),'TealPaint')
for x,w in [(-1,3.7),(3.9,5.0)]:
    box('FRONT_WindowSills',(x,6,.42),(w,.22,.84),'TealPaint')
    box('FRONT_WindowHeader',(x,6,3.85),(w,.22,.7),'TealPaint')
    for xx in [x-w/2,x,x+w/2]:box('WINDOW_Frames',(xx,6,2.18),(.07,.13,2.65),'DarkWood')
    for zz in [.86,3.5]:box('WINDOW_Frames',(x,6,zz),(w,.13,.07),'DarkWood')
    box('WINDOW_RemovableGlass',(x,6.025,2.18),(w-.08,.015,2.56),'WindowGlass')
# Narrow additional retail window at far left.
box('WINDOW_LeftGlass',(-5.48,6.025,2.18),(1.63,.015,2.56),'WindowGlass')
for zz in [.86,3.5]:box('WINDOW_Frames',(-5.48,6,zz),(1.72,.13,.07),'DarkWood')
box('FRONT_LeftSill',(-5.48,6,.42),(1.72,.22,.84),'TealPaint');box('FRONT_LeftHeader',(-5.48,6,3.85),(1.72,.22,.7),'TealPaint')
# Main entrance x=-4.55..-3.02 remains open; hinged door swung inward, never spans entrance.
for yy in [4.56,5.98]:box('DOOR_OpenFrame',(-2.93,yy,1.5),(.065,.07,3),'DarkWood')
for zz in [.04,.62,2.96]:box('DOOR_OpenFrame',(-2.93,5.27,zz),(.065,1.42,.08),'DarkWood')
box('DOOR_OpenGlass',(-2.92,5.27,1.65),(.018,1.26,2.15),'WindowGlass')
box('DOOR_KickPanel',(-2.92,5.27,.31),(.04,1.27,.5),'TealPaint')
box('DOOR_Handle',(-2.87,4.8,1.05),(.08,.24,.035),'WornBrass')
entr=bpy.data.objects.new('PORT_ShopEntrance',None);scene.collection.objects.link(entr);entr.location=(-3.78,6,0);entr['clear_width_m']=1.5;entr['forward_blender']=[0,1,0]
doorpivot=bpy.data.objects.new('DOOR_HingePivot',None);scene.collection.objects.link(doorpivot);doorpivot.location=(-2.93,6,0)

# Store checkout is entirely separate from the cafe counter.
box('RETAIL_CheckoutBody',(-3.75,-3.85,.53),(4.8,.85,1.06),'Plywood')
box('RETAIL_CheckoutTop',(-3.75,-3.85,1.1),(4.95,.98,.12),'DarkWood')
for xx in [-5.9,-4.5,-3,-1.55]:box('RETAIL_CheckoutRepairBattens',(xx,-3.4,.54),(.075,.04,.98),'BlackIron')
collider('RetailCheckout',(-3.75,-3.85,.56),(4.95,.98,1.18))
# Regular checkout till, ledger and service bell.
box('RETAIL_Till',(-5.25,-3.85,1.3),(.58,.44,.29),'PatinaSteel')
box('RETAIL_TillDisplay',(-5.25,-3.95,1.55),(.45,.09,.22),'BlackIron')
box('RETAIL_Ledger',(-3.7,-3.84,1.19),(.36,.26,.045),'BookGreen')
ball('RETAIL_Bell',(-2.0,-3.8,1.2),(.08,.08,.055),'WornBrass',12,4)
for x in [-6.3,-.9]:cyl('RETAIL_SkateRack',(x,-5.65,1.3),(x,-5.65,3.15),.035,'BlackIron',8)
for z in [1.45,2.35]:box('RETAIL_SkateRackCrossbar',(-3.6,-5.65,z),(5.7,.09,.08),'DarkWood')
box('RETAIL_AngledBoardSupport',(-3.62,-5.38,1.64),(5.8,.7,.085),'DarkWood')

# Retail shelves, furniture and original fashion group labels.
zs=shelf('RETAIL_WallShelving',-5.3,-1.55,2.8,.55,2.35,'Plywood',4)
zs2=shelf('RETAIL_SmallShelf',-.12,-1.75,1.5,.48,1.95,'AmberWood',3)
legtable('RETAIL_DisplayTable',(-3,1,0),1.9,1.05,.8)
legtable('RETAIL_HatBench',(-5.55,3.25,0),1.85,.7,.68)
for xx,yy,ma,tag in [(-5.6,.55,'BlackCloth','midnight_static'),(-2.65,3.4,'Denim','loose_wire'),(-.15,.35,'CreamCloth','clear_signal')]:
    for x in [xx-.72,xx+.72]:cyl('RACK_'+tag,(x,yy,.05),(x,yy,1.95),.025,'BlackIron',8);box('RACK_'+tag,(x,yy,.05),(.35,.5,.055),'BlackIron')
    cyl('RACK_'+tag,(xx-.75,yy,1.95),(xx+.75,yy,1.95),.025,'BlackIron',8)
    for i in range(3):
        x=xx-.45+i*.45;y=yy+(i%2)*.04
        if ma=='BlackCloth':p=[(-.15,1.74),(-.34,1.68),(-.52,1.18),(-.37,1.1),(-.23,1.4),(-.27,.55),(.27,.55),(.23,1.4),(.37,1.1),(.52,1.18),(.34,1.68),(.15,1.74)]
        elif ma=='Denim':p=[(-.12,1.74),(-.31,1.68),(-.3,1.12),(.3,1.12),(.31,1.68),(.12,1.74)]
        else:p=[(-.12,1.74),(-.32,1.7),(-.49,1.49),(-.35,1.36),(-.24,1.5),(-.23,1.13),(.23,1.13),(.24,1.5),(.35,1.36),(.49,1.49),(.32,1.7),(.12,1.74)]
        poly_extrude('CLOTHES_'+tag,p,.045,ma,center=(x,y,0))
        cyl('CLOTHES_Hangers',(x-.22,y,1.77),(x,y,1.9),.012,'WornBrass',6);cyl('CLOTHES_Hangers',(x,y,1.9),(x+.22,y,1.77),.012,'WornBrass',6)
        if ma=='Denim':box('CLOTHES_DenimPatches',(x-.12,y+.027,1.4),(.16,.012,.18),'CreamCloth');box('CLOTHES_DenimPatches',(x+.1,y+.027,1.56),(.13,.012,.1),'RustCloth')
        if ma=='CreamCloth':box('CLOTHES_TeeGraphics',(x,y+.028,1.45),(.16,.01,.17),'TealPaint')
    panel('SIGN_'+tag,(xx,yy+.065,2.13),1.1,.275,'Tag_'+tag,frame=False)
panel('SIGN_dustline',(-5.55,3.22,1.33),1.08,.27,'Tag_dustline',frame=False)
# Hats, beanies, boots and a draped skirt are actual volumes.
for i in range(3):
    x=-6.15+i*.57;y=3.26
    ball('MERCH_WesternHats',(x,y,.88),(.28,.21,.045),'Leather',12,4)
    cyl('MERCH_WesternHats',(x,y,.9),(x,y,1.08),.12,'Leather',12,.095)
    ring('MERCH_HatBands',(x,y,.95),.12,.015,'DarkWood',12,4)
for i in range(3):ball('MERCH_Beanies',(-3.6+i*.35,1.1,.95),(.14,.14,.16),['BlackCloth','RustCloth','BookGreen'][i],10,5)
for i in range(2):
    x=-2.6+i*.28
    box('MERCH_Boots',(x,1.04,.93),(.21,.4,.16),'Leather');cyl('MERCH_Boots',(x,.93,.98),(x,.93,1.25),.105,'Leather',9,.09)
poly_extrude('MERCH_PleatedSkirt',[(-.22,1.52),(-.39,.87),(.39,.87),(.22,1.52)],.055,'BlackCloth',center=(-6.45,.55,0))
for xx in [-.24,-.12,0,.12,.24]:cyl('MERCH_SkirtPleats',(-6.45+xx,.59,.9),(-6.45+xx*.6,.59,1.48),.012,'BlackIron',5)

# Knickknacks: records/books, ceramics, camera, lantern, bowls, pins, clocks.
for level,z in enumerate(zs):
    for i in range(8 if level%2==0 else 5):
        x=-6.45+i*(.25 if level%2==0 else .45)
        if level%2==0:
            box('KNICK_Books',(x,-1.5,z+.17),(.12+random.random()*.05,.25,.27+random.random()*.09),random.choice(['Paper','BookGreen','BookBlue','RustCloth']))
        else:
            cyl('KNICK_Ceramics',(x,-1.45,z+.04),(x,-1.45,z+.25),.075,'Porcelain' if i%2 else 'Clay',10,.09)
            ring('KNICK_Ceramics',(x+.09,-1.45,z+.15),.055,.012,'Porcelain' if i%2 else 'Clay',8,4,'Y')
for i in range(5):
    box('KNICK_RecordSleeves',(-.65+i*.22,-1.72,.58),(.18,.028,.32),random.choice(['BlackCloth','RustCloth','BookGreen','Paper']))
    cyl('KNICK_RecordLabels',(-.65+i*.22,-1.695,.58),(-.65+i*.22,-1.68,.58),.045,'WornBrass',10)
box('KNICK_OldCamera',(-.45,-1.7,1.3),(.31,.16,.2),'BlackIron');cyl('KNICK_CameraLens',(-.45,-1.60,1.3),(-.45,-1.51,1.3),.065,'WornBrass',12)
for i in range(3):pot('KNICK_TinyPlanter'+str(i),-.62+i*.43,-1.7,1.94,.07,.1,'ClayGrey')
for x in [-.45,.1]:
    cyl('KNICK_TrinketBowls',(x,-1.7,.22),(x,-1.7,.31),.13,'Porcelain',12,.18)
    ring('KNICK_TrinketBowls',(x,-1.7,.32),.18,.015,'Porcelain',12,4)
box('KNICK_PinTray',(-3.1,.8,.89),(.4,.25,.04),'DarkWood')
for i in range(6):cyl('KNICK_EnamelPins',(-3.25+(i%3)*.12,.75+(i//3)*.1,.92),(-3.25+(i%3)*.12,.75+(i//3)*.1,.927),.035,['Red','TealPaint','WornBrass'][i%3],8)

# Cafe counter, exactly FIVE stools, vintage register and blank-price menus.
box('CAFE_CounterBody',(6.2,.4,.52),(1.0,5.8,1.04),'AmberWood')
box('CAFE_CounterTop',(6.2,.4,1.09),(1.2,6,.12),'DarkWood')
for yy in [-2.2,-1.1,0,1.1,2.2,3.1]:box('CAFE_CounterBattens',(5.68,yy,.52),(.06,.07,.96),'DarkWood')
collider('CafeCounter',(6.2,.4,.55),(1.2,6,1.16))
for i,yy in enumerate([-1.8,-.72,.36,1.44,2.52],1):
    name='CAFE_Stool_%02d'%i
    cyl(name+'_Seat',(4.88,yy,.77),(4.88,yy,.84),.24,'AmberWood',14)
    for a in [0,pi/2,pi,3*pi/2]:cyl(name+'_Legs',(4.88+.2*cos(a),yy+.2*sin(a),.03),(4.88+.14*cos(a),yy+.14*sin(a),.77),.028,'BlackIron',8)
    ring(name+'_Footrest',(4.88,yy,.29),.2,.018,'BlackIron',12,4)
panel('MENU_Drinks',(6.94,2.12,2.25),.88,1.174,'MenuDrinks',(-1,0,0))
panel('MENU_Food',(6.94,.75,2.25),1.02,1.36,'MenuFood',(-1,0,0))
# Cash register with brass dome, mechanical keys and a readable silhouette.
box('CAFE_VintageRegister_Base',(6.12,-1.5,1.24),(.66,.56,.19),'BlackIron')
box('CAFE_VintageRegister_Drawer',(6.12,-1.5,1.37),(.57,.47,.12),'WornBrass')
ball('CAFE_VintageRegister_Dome',(6.12,-1.58,1.63),(.28,.20,.26),'WornBrass',12,6)
box('CAFE_VintageRegister_Display',(6.12,-1.63,1.88),(.45,.08,.17),'BlackIron')
box('CAFE_VintageRegister_DisplayGlass',(6.12,-1.58,1.88),(.35,.012,.1),'Paper')
for row in range(3):
    for col in range(5):cyl('CAFE_VintageRegister_Keys',(5.91+col*.105,-1.31+row*.07,1.47),(5.91+col*.105,-1.31+row*.07,1.49),.029,'Porcelain',8)
box('CAFE_VintageRegister_Handle',(6.12,-1.2,1.28),(.23,.04,.035),'BlackIron')
# A few practical cafe objects, not stocked merchandise or invented menu prices.
cyl('CAFE_CoffeeUrn',(6.3,3.05,1.16),(6.3,3.05,1.62),.13,'PatinaSteel',12)
ball('CAFE_CoffeeUrnLid',(6.3,3.05,1.64),(.14,.14,.055),'BlackIron',10,4)
for i in range(3):cyl('CAFE_Cups',(6.08+i*.16,2.48,1.16),(6.08+i*.16,2.48,1.29),.055,'Porcelain',10)
legtable('CAFE_WindowTable',(2.8,4.7,0),1.2,.85,.76,'Plywood')
def chair(name,x,y,rz=0):
    box(name+'_Seat',(x,y,.47),(.42,.42,.07),'AmberWood',rz)
    for a in [-1,1]:
        for b in [-1,1]:cyl(name+'_Legs',(x+a*.17,y+b*.17,.03),(x+a*.16,y+b*.16,.46),.025,'DarkWood',8)
    back=-.18 if abs(rz)<.1 else .18
    for a in [-1,1]:cyl(name+'_Back',(x+a*.18,y+back,.47),(x+a*.18,y+back,1.02),.023,'DarkWood',8)
    box(name+'_Backrest',(x,y+back,.91),(.42,.06,.21),'AmberWood')
chair('CAFE_Chair_A',2.8,4.0);chair('CAFE_Chair_B',2.8,5.45,pi)

# Antique boat and truck models, old character silhouettes and other collected decor.
box('CAFE_AntiqueShelf',(6.75,-1.55,2.57),(.42,1.8,.075),'DarkWood')
box('ANTIQUE_TruckChassis',(6.73,-1.6,2.78),(.25,.78,.12),'Red')
box('ANTIQUE_TruckCab',(6.73,-1.33,2.93),(.25,.27,.25),'PatinaSteel')
box('ANTIQUE_TruckBonnet',(6.73,-1.08,2.82),(.24,.22,.12),'Red')
box('ANTIQUE_TruckBed',(6.73,-1.81,2.88),(.26,.34,.18),'AmberWood')
for xx in [6.55,6.91]:
    for yy in [-1.25,-1.85]:cyl('ANTIQUE_TruckWheels',(xx-.03,yy,2.75),(xx+.03,yy,2.75),.09,'Rubber',10)
box('CAFE_BoatShelf',(2.8,-2.84,2.5),(1.5,.36,.08),'DarkWood')
poly_extrude('ANTIQUE_BoatHull',[(-.66,0),(-.45,-.2),(.4,-.2),(.66,.06)],.22,'AmberWood',center=(2.8,-2.8,2.73))
cyl('ANTIQUE_BoatMast',(2.8,-2.8,2.73),(2.8,-2.8,3.55),.018,'DarkWood',6)
poly_extrude('ANTIQUE_BoatSails',[(.03,.72),(.03,.08),(.52,.08)],.012,'CreamCloth',center=(2.8,-2.8,2.75))
poly_extrude('ANTIQUE_BoatSails',[(-.03,.55),(-.46,.08),(-.03,.08)],.012,'CreamCloth',center=(2.8,-2.8,2.75))
panel('ART_FictionalVesper',(1.10,-.9,2.45),.85,1.16,'PortraitVesper',(1,0,0))
panel('ART_FictionalFern',(1.10,-2.1,2.45),.72,.985,'PortraitFern',(1,0,0))
# Antique round clock, no text necessary.
cyl('ANTIQUE_ClockRim',(6.91,4.12,2.75),(6.84,4.12,2.75),.33,'DarkWood',20)
cyl('ANTIQUE_ClockFace',(6.835,4.12,2.75),(6.82,4.12,2.75),.29,'Paper',20)
cyl('ANTIQUE_ClockHands',(6.80,4.12,2.75),(6.80,4.12,2.94),.012,'BlackIron',5)
cyl('ANTIQUE_ClockHands',(6.80,4.12,2.75),(6.80,4.28,2.68),.012,'BlackIron',5)
for k in range(12):
    a=2*pi*k/12;cyl('ANTIQUE_ClockTicks',(6.80,4.12+.23*sin(a),2.75+.23*cos(a)),(6.80,4.12+.26*sin(a),2.75+.26*cos(a)),.008,'BlackIron',4)

# Office behind parted hanging bead strands; furniture remains visible through opening.
box('OFFICE_Desk',(4.3,-5.16,.78),(1.8,.8,.09),'Plywood')
for xx in [3.52,5.08]:box('OFFICE_DeskLegs',(xx,-5.16,.37),(.12,.62,.74),'DarkWood')
chair('OFFICE_Chair',4.3,-4.32,pi)
box('OFFICE_FilingCabinet',(6.35,-5.35,.7),(.7,.64,1.4),'PatinaSteel')
for z in [.24,.68,1.12]:
    box('OFFICE_DrawerFaces',(6.35,-5.02,z),(.62,.025,.38),'PatinaSteel');box('OFFICE_DrawerHandles',(6.35,-4.99,z+.07),(.22,.035,.035),'BlackIron')
box('OFFICE_Blotter',(4.3,-5.12,.84),(.8,.46,.012),'BookGreen')
box('OFFICE_Papers',(4.55,-5.07,.86),(.23,.3,.025),'Paper')
cyl('OFFICE_DeskLamp',(3.67,-5.3,.83),(3.67,-5.3,1.25),.02,'WornBrass',8)
cyl('OFFICE_DeskLampBase',(3.67,-5.3,.83),(3.67,-5.3,.86),.11,'WornBrass',12)
cyl('OFFICE_DeskLampShade',(3.67,-5.3,1.25),(3.67,-5.3,1.39),.15,'TealPaint',12,.05)
box('OFFICE_Noticeboard',(4.3,-5.98,2.05),(1.55,.04,.85),'AmberWood')
for i in range(5):box('OFFICE_Notes',(3.76+i*.26,-5.95,2.02+(i%2)*.15),(.18,.008,.27),'Paper',rz=0)
cyl('OFFICE_BeadCurtainRod',(4.25,-2.97,2.53),(5.75,-2.97,2.53),.03,'DarkWood',10)
for i in range(17):
    xx=4.33+i*.084
    # Parted lower center keeps a clear visible walk-through while preserving the bead fringe.
    end=.3 if i<5 or i>11 else 1.7+abs(i-8)*.1
    cyl('OFFICE_BeadStrings',(xx,-2.97,end),(xx,-2.97,2.49),.004,'DarkWood',4)
    for k in range(int((2.49-end)/.095)):
        zz=2.47-k*.095;ball('OFFICE_Beads',(xx,-2.97,zz),(.021,.021,.035),['WornBrass','AmberWood','TealPaint'][i%3],5,3)

# Lush but peripheral plants; retail and cafe aisles remain open.
plant('PLANT_BambooTall',-6.45,5.2,h=2.2,r=.33,kind='bamboo')
plant('PLANT_BambooCafe',6.2,5.3,h=1.8,r=.3,kind='bamboo')
plant('PLANT_RubberEntrance',-2.35,5.22,h=1.45,r=.28)
plant('PLANT_RubberDivider',.35,4.6,h=1.3,r=.25)
plant('PLANT_FernCafe',1.65,-2.2,h=.9,r=.25,kind='fern')
plant('PLANT_Office',5.75,-5.6,h=.8,r=.2)
plant('PLANT_Counter',-1.55,-3.85,z=1.18,h=.35,r=.12)
plant('PLANT_Table',2.8,4.7,z=.82,h=.25,r=.08,kind='fern')
plant('PLANT_HighShelf',-.55,-1.72,z=1.99,h=.4,r=.1)

# Posters, two national flags and restrained handmade decoration.
panel('ART_TheSpiceSquirrels',(.90,-.22,2.62),1.2375,1.65,'PosterBand',(-1,0,0))
panel('ART_AfterHours',(-6.97,1.8,2.8),.85,1.16,'PosterHours',(1,0,0))
panel('ART_SmallJoys',(-6.97,-3.8,2.7),.72,.984,'PosterJoys',(1,0,0))
panel('ART_RooftopSocialClub',(-6.97,-2.65,2.7),.62,.827,'PosterRooftop',(1,0,0),False)
panel('DETAIL_ChiliAcorn',(-2.55,-3.397,.8),.22,.22,'ChiliAcorn',frame=False)
panel('FLAG_Belgium',(-.15,-5.97,3.05),1.2,.8,'Belgium',frame=False)
panel('FLAG_Jamaica',(-.25,2.2,3.28),1.4,.7,'Jamaica',frame=False)
for xx in [-.95,.45]:cyl('FLAG_HangingCords',(xx,2.2,3.65),(xx,2.2,4.03),.008,'DarkWood',5)

# Suspended lamps and exposed handmade wiring are actual meshes; preview lights separate.
lamp_positions=[(-4.7,3.1,3.0),(-3.7,-.3,2.95),(-3.7,-4.55,3.2),(3.1,2.3,2.95),(5.9,.3,3.15),(4.8,-4.7,3)]
for i,(x,y,z) in enumerate(lamp_positions):
    cyl('LIGHT_Cords',(x,y,z+.2),(x,y,4.08),.012,'BlackIron',6)
    cyl('LIGHT_Shades',(x,y,z),(x,y,z+.22),.29 if i<3 else .22,'PatinaSteel' if i%2==0 else 'BlackIron',12,.07)
    cyl('LIGHT_Diffusers',(x,y,z-.015),(x,y,z),.24 if i<3 else .18,'Lamp',12)
for p1,p2 in [((-6.9,-5.85,3.7),(-.5,-5.85,3.7)),((-6.9,-5.85,3.7),(-6.9,4.7,3.7))]:cyl('DETAIL_ExposedConduit',p1,p2,.025,'PatinaSteel',8)

for geo in groups.values():geo.make()
# Keep the already-open door attached to an editable hinge.
for ob in scene.objects:
    if ob.name.startswith('DOOR_') and ob.type=='MESH':ob.parent=doorpivot;ob.matrix_parent_inverse=Matrix.Translation(doorpivot.location).inverted()

# Append seven complete decks/trucks/wheels with designs outward, behind the retail checkout.
skatefile=PACK/'Source/Skateboards_BASE_v1.blend'
with bpy.data.libraries.load(str(skatefile),link=False) as (src,dst):dst.collections=[n for n in src.collections if n.startswith('SKATE_')]
skatecollections=sorted([c for c in dst.collections if c],key=lambda c:c.name)
boardnames=[]
for i,col in enumerate(skatecollections):
    scene.collection.children.link(col)
    roots=[ob for ob in col.all_objects if ob.name.startswith('ROOT_')]
    if not roots:continue
    root=roots[0];root.location=(-6.05+i*.81,-5.53,2.04);root.rotation_euler=(3*pi/4,0,0);boardnames.append(root.name)
    root['display_zone']='behind_retail_checkout';root['units']='meters'

# Main export: geometry + marker empties, no preview cameras or lights.
bpy.ops.object.select_all(action='DESELECT')
for ob in scene.objects:
    if ob.type in {'MESH','EMPTY'}:ob.select_set(True)
scene['asset_title']='Offbeat independent shop, cafe and back office'
scene['dimensions_m']=[14,12,4.2];scene['room_areas_m2']={'retail':96,'cafe':54,'office':12}
glb=PACK/'GLB/04_Offbeat_Shop_Interior.glb'
bpy.ops.export_scene.gltf(filepath=str(glb),export_format='GLB',use_selection=True,export_yup=True,export_apply=True,export_extras=True,export_texcoords=True,export_normals=True,export_materials='EXPORT',export_cameras=False,export_lights=False)

# Source cameras and lights for independent re-rendering.
def light(name,loc,energy,color,size=3):
    data=bpy.data.lights.new(name,'AREA');data.energy=energy;data.color=color;data.shape='DISK';data.size=size
    ob=bpy.data.objects.new(name,data);scene.collection.objects.link(ob);ob.location=loc;return ob
for i,(x,y,z) in enumerate(lamp_positions):light('PREVIEW_Light_'+str(i),(x,y,z-.12),170 if i<3 else 120,(1,.74,.47),2.2)
light('PREVIEW_WindowSoft',(-1,4.8,3.5),600,(.67,.82,1),6)
light('PREVIEW_CafeSoft',(4.2,4.3,3.5),430,(.77,.86,1),4)
light('PREVIEW_OfficeSoft',(4.8,-4.5,3.5),160,(1,.82,.64),3)
def camera(name,loc,target,lens=22):
    data=bpy.data.cameras.new(name);ob=bpy.data.objects.new(name,data);scene.collection.objects.link(ob);ob.location=loc
    ob.rotation_euler=(Vector(target)-ob.location).to_track_quat('-Z','Y').to_euler();data.lens=lens;data.clip_start=.05;data.clip_end=150;return ob
hero=camera('PREVIEW_Camera_Retail',(-3.95,5.7,2.3),(-2,-2.0,1.5),18)
cafe=camera('PREVIEW_Camera_Cafe',(1.65,5.6,2.2),(4.8,-.8,1.55),20)
cut=camera('PREVIEW_Camera_Cutaway',(11,13,24),(0,-.6,0),40)
office=camera('PREVIEW_Camera_Office',(5.2,-3.16,1.85),(4.65,-5.15,1.1),18)
scene.camera=hero
scene.render.engine='CYCLES';scene.cycles.samples=96;scene.cycles.use_denoising=False
scene.render.threads_mode='FIXED';scene.render.threads=6
scene.render.resolution_x=1200;scene.render.resolution_y=900;scene.render.resolution_percentage=100
scene.world=bpy.data.worlds.new('ShopPreviewWorld');scene.world.use_nodes=True;scene.world.node_tree.nodes['Background'].inputs[0].default_value=(.19,.24,.29,1);scene.world.node_tree.nodes['Background'].inputs[1].default_value=.35
scene.view_settings.view_transform='AgX';scene.render.image_settings.file_format='PNG'
source=PACK/'Source/04_Offbeat_Shop_Interior.blend'
bpy.ops.file.pack_all()
bpy.ops.wm.save_as_mainfile(filepath=str(source))
tri=0;meshcount=0;meshmax=0
for ob in scene.objects:
    if ob.type=='MESH':
        ob.data.calc_loop_triangles();n=len(ob.data.loop_triangles);tri+=n;meshmax=max(meshmax,n);meshcount+=1
metadata={'asset':glb.name,'dimensions_m':{'width':14,'depth':12,'height':4.2},'gltf_axes':{'up':'+Y','front':'-Z'},'blender_axes':{'up':'+Z','front':'+Y'},'origin':'room footprint center, floor height 0','rooms':{'retail':{'x':[-7,1],'gltf_z':[-6,6],'area_m2':96},'cafe':{'x':[1,7],'gltf_z':[-6,3],'area_m2':54},'office':{'x':[3,7],'gltf_z':[3,6],'area_m2':12}},'triangle_count':tri,'mesh_objects':meshcount,'largest_mesh_triangles':meshmax,'glb_bytes':glb.stat().st_size,'stool_count':5,'skateboard_count':len(boardnames),'skateboards':boardnames,'poster':'THE SPICE SQUIRRELS; five female squirrel pop-band members','menu_prices':'blank','drinks':['Kombucha','Green tea','Bubble tea','Coffee','Soft drink'],'food':['Grilled cheese','Ham sandwich','Chicken noodle soup','Tofu dish','Hamburger & french fries'],'entrance':{'node':'PORT_ShopEntrance','position_gltf_m':[-3.78,0,-6],'clear_width_m':1.5},'colliders':collisions,'notes':['Three distinct rooms, retail larger than cafe; enclosed utility void beside office.','Retail checkout separate from cafe counter.','Parted bead curtain marks office entry.','Seven complete skateboards rest in angled display behind retail checkout; graphics face upward and into room.','Window glass and roof are separately named/removable.','Rooftop Social Club flyer and small chili/acorn checkout motif are original subtle visual callbacks.','Preview lights are not exported; recreate local lights in the target engine.','Game integration and Roblox playtest are not performed.']}
(PACK/'Metadata/04_Offbeat_Shop_Interior.json').write_text(json.dumps(metadata,indent=2))
print('SHOP_EXPORTED '+json.dumps({'triangles':tri,'objects':meshcount,'bytes':glb.stat().st_size,'source':str(source)}),flush=True)
if '--no-render' not in sys.argv:
    scene.camera=hero;scene.render.filepath=str(PACK/'Previews/04_Offbeat_Shop_Interior.png');bpy.ops.render.render(write_still=True)
    scene.camera=cafe;scene.render.filepath=str(PACK/'Previews/04_Offbeat_Shop_Cafe.png');bpy.ops.render.render(write_still=True)
    for ob in scene.objects:
        if ob.name.startswith(('ROOF_','FRONT_','WINDOW_')):ob.hide_render=True
    scene.camera=cut;scene.render.resolution_x=1200;scene.render.resolution_y=1000
    scene.render.filepath=str(PACK/'Previews/04_Offbeat_Shop_Cutaway.png');bpy.ops.render.render(write_still=True)
print('SHOP_COMPLETE',flush=True)
