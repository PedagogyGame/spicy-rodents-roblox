"""Reimport the actual GLB exports, verify materials, and make their preview renders.
Run: blender -b --threads 6 --python Source/Render_Exported_Sewers.py
"""
import bpy, json, runpy, math, sys
from pathlib import Path
ROOT=Path(__file__).resolve().parents[1]
helpers=runpy.run_path(str(ROOT/'Source'/'build_sewers.py'))
reports=[]
for path in sorted((ROOT/'GLB').glob('0[123]_*.glb')):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    bpy.ops.import_scene.gltf(filepath=str(path))
    scene=bpy.context.scene
    scene.name=path.stem+'_Reimported'
    meta=json.loads((ROOT/'Metadata'/f'{path.stem}.json').read_text())
    helpers['configure_scene'](scene)
    helpers['setup_preview'].__globals__['LIGHTS']=meta['suggested_lights']
    helpers['setup_preview'](meta)
    scene.render.resolution_x=1200; scene.render.resolution_y=800
    scene.cycles.samples=128
    scene.cycles.use_adaptive_sampling=True
    scene.cycles.adaptive_threshold=.045
    scene.view_settings.exposure=-.15
    meshes=[o for o in scene.objects if o.type=='MESH']
    tris=0
    for o in meshes:
        o.data.calc_loop_triangles(); tris+=len(o.data.loop_triangles)
    images=[i for i in bpy.data.images if i.type=='IMAGE']
    for im in images:
        if len(im.pixels): first_channel=im.pixels[0]  # force lazy packed-image decoding
    ports=[o for o in scene.objects if o.name.startswith('PORT_')]
    report={'file':path.name,'meshes':len(meshes),'triangles':tris,'images':len(images),
            'material_count':len([m for m in bpy.data.materials if m.users]),
            'all_images_loaded':all(i.has_data and min(i.size)>0 for i in images),
            'port_names':[o.name for o in ports], 'renderer':'Blender Cycles, actual GLB reimport'}
    assert report['all_images_loaded'],report
    scene.render.filepath=str(ROOT/'Previews'/f'{path.stem}.png')
    if '--validate-only' not in sys.argv:
        bpy.ops.render.render(write_still=True)
    reports.append(report)
    (ROOT/'Metadata'/'Sewer_Reimport_QA.json').write_text(json.dumps(reports,indent=2))
    print('VERIFIED_REIMPORT',json.dumps(report),flush=True)
