from pathlib import Path
import json, trimesh
root=Path(__file__).resolve().parents[1]
files=list((root/'GLB').glob('*.glb'))
assert len(files)==5,files
for f in files:
 s=trimesh.load(str(f),force='scene')
 assert len(s.geometry)>0,(f,'empty')
 assert all(len(m.faces)>0 and m.vertices.shape[1]==3 and m.is_winding_consistent for m in s.geometry.values()),f
 print(f.name, 'parts',len(s.geometry),'faces',sum(len(m.faces) for m in s.geometry.values()))
r=json.loads((root/'Specs/roof_route_graph.json').read_text())
ids=[n['id'] for n in r['nodes']]; assert len(ids)==len(set(ids))
assert all(e['a'] in ids and e['b'] in ids and e['a']!=e['b'] for e in r['edges'])
assert all(h['from'] in ids for h in r['externalHooks'])
seen={ids[0]}; stack=[ids[0]]
while stack:
 a=stack.pop()
 for e in r['edges']:
  b=e['b'] if e['a']==a else e['a'] if e['b']==a and e.get('bidirectional') else None
  if b and b not in seen: seen.add(b); stack.append(b)
assert set(ids)==seen, set(ids)-seen
print('PASS: all GLBs reload, no empty/winding-inconsistent meshes, local roof graph connected.')
