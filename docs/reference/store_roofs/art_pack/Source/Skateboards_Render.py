import bpy, math
from mathutils import Vector
from pathlib import Path
HERE=Path(__file__).resolve().parent
BASE=HERE.parent if HERE.name=='Source' else HERE.parent/'Spicy_Rodent_Underground'
bpy.ops.wm.open_mainfile(filepath=str(BASE/'Source/Skateboards.blend'))
scene=bpy.context.scene
scene.cycles.use_denoising=False
scene.cycles.samples=40
for root in [o for o in bpy.data.objects if o.name.startswith('ROOT_')]:
    root.rotation_euler=(math.radians(112),0,0)
    root.location.z=.43
bpy.ops.mesh.primitive_cube_add(size=1,location=(0,0,-.035))
obj=bpy.context.object;obj.name='Preview_Floor';obj.dimensions=(4,3,.05)
mat=bpy.data.materials.new('Preview_Floor');mat.diffuse_color=(.08,.105,.12,1);mat.use_nodes=True
mat.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value=(.08,.105,.12,1)
mat.node_tree.nodes['Principled BSDF'].inputs['Roughness'].default_value=.88;obj.data.materials.append(mat)
for x,y,z,power,size in [(-1.3,1.0,2.4,250,2.0),(1.5,-.4,1.5,180,1.8),(0,2.4,.8,120,1.2)]:
    bpy.ops.object.light_add(type='AREA',location=(x,y,z));light=bpy.context.object;light.data.energy=power;light.data.shape='DISK';light.data.size=size
    light.rotation_euler=(Vector((0,0,.4))-light.location).to_track_quat('-Z','Y').to_euler()
bpy.ops.object.camera_add(location=(.90,2.85,1.65));cam=bpy.context.object
cam.rotation_euler=(Vector((0,0,.43))-cam.location).to_track_quat('-Z','Y').to_euler();cam.data.type='ORTHO';cam.data.ortho_scale=2.68;scene.camera=cam
scene.render.filepath=str(BASE/'Previews/Skateboards_Lineup.png')
bpy.ops.render.render(write_still=True)
