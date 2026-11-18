"""Render the actual exported GLB, reusing only the .blend preview cameras/lights."""
import bpy,json
from pathlib import Path
from mathutils import Vector
ROOT=Path(__file__).resolve().parents[1]
bpy.ops.wm.open_mainfile(filepath=str(ROOT/'Source/04_Offbeat_Shop_Interior.blend'))
scene=bpy.context.scene
for ob in list(scene.objects):
    if ob.type in {'MESH','EMPTY'}:bpy.data.objects.remove(ob,do_unlink=True)
bpy.ops.import_scene.gltf(filepath=str(ROOT/'GLB/04_Offbeat_Shop_Interior.glb'))
scene=bpy.context.scene
verts=[ob.matrix_world@Vector(v) for ob in scene.objects if ob.type=='MESH' for v in ob.bound_box]
mins=[min(v[i] for v in verts) for i in range(3)];maxs=[max(v[i] for v in verts) for i in range(3)]
stats={'reimport_succeeded':True,'bounds_blender_min':mins,'bounds_blender_max':maxs,'extent_m':[maxs[i]-mins[i] for i in range(3)],'mesh_objects':sum(ob.type=='MESH' for ob in scene.objects),'render_source':'exported GLB reimported into Blender; source preview lights/cameras retained'}
(ROOT/'Metadata/04_Offbeat_Shop_Reimport_QA.json').write_text(json.dumps(stats,indent=2))
print('REIMPORT_QA '+json.dumps(stats),flush=True)
scene.render.engine='CYCLES';scene.cycles.samples=96;scene.cycles.use_denoising=False
scene.render.threads_mode='FIXED';scene.render.threads=6
scene.render.resolution_x=1200;scene.render.resolution_y=900;scene.render.resolution_percentage=100
scene.render.image_settings.file_format='PNG'
for cam,name in [('PREVIEW_Camera_Retail','04_Offbeat_Shop_Interior'),('PREVIEW_Camera_Cafe','04_Offbeat_Shop_Cafe'),('PREVIEW_Camera_Office','04_Offbeat_Shop_Office')]:
    scene.camera=bpy.data.objects[cam];scene.render.filepath=str(ROOT/'Previews'/f'{name}.png')
    bpy.ops.render.render(write_still=True)
for ob in scene.objects:
    if ob.name.startswith(('ROOF_','FRONT_','WINDOW_','BEAMS_')):ob.hide_render=True
scene.camera=bpy.data.objects['PREVIEW_Camera_Cutaway'];scene.render.resolution_y=1000
scene.render.filepath=str(ROOT/'Previews/04_Offbeat_Shop_Cutaway.png');bpy.ops.render.render(write_still=True)
print('REIMPORT_RENDERS_COMPLETE',flush=True)
