"""Union the supplied reference guide outlines into clean contact polygons.

Requires Shapely. Output is also shipped with the editable sources, so the
Blender generator can rebuild without Shapely when the input is unchanged.
"""
import json
from pathlib import Path
import trimesh
from shapely.geometry import Polygon
from shapely.ops import unary_union
from shapely import set_precision

ROOT=Path(__file__).resolve().parents[2]
DATA=json.loads((ROOT/'work/Pinball_ChatGPT_Pack/pinball_data.json').read_text())
out={}
for key,m in DATA['machines'].items():
    prefix={'acorn':'Acorn','rodent':'Rodent','space':'Space'}[key]
    scene=trimesh.load(ROOT/'work/Pinball_ChatGPT_Pack/reference'/f'{prefix}_Guides.glb',force='scene')
    for group in ('wood','plastic'):
        node='Guides_'+group.capitalize()
        if node not in scene.graph.nodes_geometry:continue
        transform,geometry=scene.graph[node]
        mesh=scene.geometry[geometry]
        points=trimesh.transform_points(mesh.vertices,transform)
        # Use the reference's exact projected triangles: this preserves flat
        # rail ends and every custom corner without guessing a cap/join style.
        projected=points[mesh.faces][:,:,[0,2]]
        faces=[set_precision(Polygon(t),1e-7) for t in projected if Polygon(t).area>1e-12]
        shape=unary_union(faces)
        polys=list(shape.geoms) if shape.geom_type=='MultiPolygon' else [shape]
        tag=key if group=='wood' else key+'_plastic'
        out[tag]=[]
        for p in polys:
            # Reference float32 segment seams can leave micron-scale slivers.
            # Fill only those (<0.01 square millimetres); real holes are errors.
            if any(Polygon(r).area>1e-8 for r in p.interiors):raise ValueError('Unexpected enclosed guide contour')
            out[tag].append(list(p.exterior.coords)[:-1])
(Path(__file__).parent/'wood_polygon_profiles.json').write_text(json.dumps(out,indent=2))
print('Created exact unioned guide profiles:',{k:sum(len(p) for p in ps) for k,ps in out.items()})
