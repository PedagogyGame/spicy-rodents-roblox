"""Create editable v2 .blend copies from the final GLBs. Requires Blender 4.3+.
Run from a terminal, NOT the Python console of a working project:
    blender --background --python Source/Import_v2_Into_Blender.py -- --scene all
No original game or baseline .blend is opened or overwritten. Output is Source/V2_Generated/.
This helper was syntax-checked, but not executed in the delivery environment.
"""
from pathlib import Path
import argparse, sys
import bpy
HERE=Path(__file__).resolve().parent
PACK=HERE.parent
parser=argparse.ArgumentParser()
parser.add_argument('--scene', choices=['all','shop','tunnels','skateboards','jacket'],default='all')
parser.add_argument('--force',action='store_true',help='Allow replacing already generated v2 source copies.')
args=parser.parse_args(sys.argv[sys.argv.index('--')+1:] if '--' in sys.argv else [])
if not bpy.app.background:
    raise RuntimeError('Run this helper in background mode to protect any unsaved Blender project.')
DEST=HERE/'V2_Generated';DEST.mkdir(exist_ok=True)
def begin():
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.context.scene.unit_settings.system='METRIC'
    bpy.context.scene.unit_settings.scale_length=1
    bpy.context.scene['scope']='Visual asset source only; no game integration.'
def add(path,offset_x=0):
    before=set(bpy.data.objects)
    bpy.ops.import_scene.gltf(filepath=str(path))
    for ob in set(bpy.data.objects)-before:
        if ob.parent is None:ob.location.x+=offset_x

def save(name):
    dest=DEST/name
    if dest.exists() and not args.force:raise FileExistsError(str(dest)+' already exists; use --force to replace this generated copy.')
    bpy.ops.file.pack_all()
    bpy.ops.wm.save_as_mainfile(filepath=str(dest))
    print('Saved:',dest)
if args.scene in {'all','shop'}:
    begin();add(PACK/'GLB/04_Offbeat_Shop_Interior.glb');save('04_Offbeat_Shop_Interior_v2.blend')
if args.scene in {'all','tunnels'}:
    for name in ['01_Brick_Sewer_Passage','02_Four_Way_Sewer_Junction','03_Concrete_Maintenance_Tunnel']:
        begin();add(PACK/'GLB'/(name+'.glb'));save(name+'_v2.blend')
if args.scene in {'all','skateboards'}:
    begin()
    for i,path in enumerate(sorted((PACK/'GLB/Skateboards').glob('*.glb'))):add(path,(i-4)*.32)
    save('Nine_Skateboards_v2.blend')
if args.scene in {'all','jacket'}:
    begin();add(PACK/'GLB/Additions/Night_Route_Jacket.glb');save('Night_Route_Jacket_v2.blend')
