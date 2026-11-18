"""Blender: import the supplied reference boards, UV and shade, then export.

Run: blender -b --python art_build_playfields.py
All reference node positions are preserved. glTF +Y is up; Blender +Z is up.
"""
import bpy, json
from pathlib import Path

SOURCE=Path(__file__).resolve().parent
ROOT=SOURCE.parent.parent
PACK=ROOT/'work/Pinball_ChatGPT_Pack'
OUT=ROOT/'build/models'
TEX=SOURCE/'textures'
DATA=json.loads((PACK/'pinball_data.json').read_text())

def material(name,filename,roughness):
 mat=bpy.data.materials.new(name);mat.use_nodes=True
 mat.diffuse_color=(1,1,1,1)
 bsdf=mat.node_tree.nodes.get('Principled BSDF')
 bsdf.inputs['Base Color'].default_value=(1,1,1,1)
 bsdf.inputs['Roughness'].default_value=roughness
 bsdf.inputs['Metallic'].default_value=0
 bsdf.inputs['Alpha'].default_value=1
 bsdf.inputs['Specular IOR Level'].default_value=.24
 tex=mat.node_tree.nodes.new('ShaderNodeTexImage')
 tex.image=bpy.data.images.load(str(filename),check_existing=True)
 tex.image.colorspace_settings.name='sRGB'
 tex.image.pack()
 tex.interpolation='Linear';tex.extension='EXTEND'
 mat.node_tree.links.new(tex.outputs['Color'],bsdf.inputs['Base Color'])
 return mat

for key,m in DATA['machines'].items():
 bpy.ops.object.select_all(action='SELECT');bpy.ops.object.delete(use_global=False)
 # This is the exact supplied blockout, not a coordinate reconstruction.
 name=m['file_prefix']+'_Playfield'
 bpy.ops.import_scene.gltf(filepath=str(PACK/'reference'/(name+'.glb')))
 for obj in list(bpy.context.scene.objects):
  if obj.type!='MESH': continue
  if obj.name not in ('Board','Apron'):raise RuntimeError('Unexpected imported node '+obj.name)
  cfg=m['board' if obj.name=='Board' else 'apron']
  mesh=obj.data
  for attr in list(mesh.color_attributes):mesh.color_attributes.remove(attr)
  mesh.materials.clear()
  mesh.materials.append(material(m['file_prefix']+'_'+obj.name+'_Printed',TEX/(m['file_prefix']+'_'+obj.name+'.png'),.38 if obj.name=='Board' else .33))
  uv=mesh.uv_layers.active or mesh.uv_layers.new(name='UVMap')
  for poly in mesh.polygons:
   for li in poly.loop_indices:
    wp=obj.matrix_world @ mesh.vertices[mesh.loops[li].vertex_index].co
    u=(wp.x-cfg['x0'])/(cfg['x1']-cfg['x0'])
    v=(wp.y+cfg['z_front'])/(cfg['z_front']-cfg['z_back'])
    uv.data[li].uv=(max(0,min(1,u)),max(0,min(1,v)))
   poly.material_index=0
  # A small manufactured edge on the apron is within the supplied free bounds.
  if obj.name=='Apron':
   mod=obj.modifiers.new('Apron edge chamfer','BEVEL');mod.width=.0008;mod.segments=1
   mod.affect='EDGES'
  bpy.ops.object.select_all(action='DESELECT');obj.select_set(True);bpy.context.view_layer.objects.active=obj
  bpy.ops.object.transform_apply(location=False,rotation=False,scale=True)
 bpy.ops.object.select_all(action='SELECT')
 bpy.context.scene.unit_settings.system='METRIC';bpy.context.scene.unit_settings.scale_length=1
 bpy.ops.wm.save_as_mainfile(filepath=str(SOURCE/'blend'/(name+'.blend')))
 bpy.ops.export_scene.gltf(filepath=str(OUT/(name+'.glb')),export_format='GLB',use_selection=True,
  export_yup=True,export_apply=True,export_cameras=False,export_lights=False,export_animations=False,
  export_materials='EXPORT',export_texcoords=True,export_normals=True,export_image_format='AUTO')
 print('EXPORTED',name)
