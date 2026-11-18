#!/usr/bin/env python3
"""Supplemental structural audit for the Spicy Rodent pinball asset pack.

Runs beside (and does not replace or modify) the supplied check_glb.py.
Dependencies: numpy, Pillow. Reads binary GLB resources without a renderer.

Usage:
 python audit_assets.py MODELS --pack ORIGINAL_PACK --json audit_results.json
"""
from __future__ import annotations
import argparse
import base64
import io
import hashlib
import json
import math
import pathlib
import struct
import sys
from collections import Counter
import numpy as np
from PIL import Image

BUDGETS = {
    'Pinball_Flipper.glb': 600, 'Pinball_PopBumper.glb': 1500,
    'Pinball_Plunger.glb': 400, 'Pinball_Gate.glb': 200,
    'Pinball_Cabinet.glb': 5000,
}
for pre in ('Acorn', 'Rodent', 'Space'):
    for tail, limit in [('Playfield',300),('Guides',6000),('Slingshots',800),('Targets',1200)]:
        BUDGETS[f'{pre}_{tail}.glb'] = limit
BUDGETS.update({'Acorn_Spinner.glb':300,'Rodent_Wire.glb':3000,'Space_Ramps.glb':5000,'Space_PodHoods.glb':600})
PNGS = [f'{pre}_Backglass.png' for pre in ('Acorn','Rodent','Space')]
DTYPES={5120:'i1',5121:'u1',5122:'<i2',5123:'<u2',5125:'<u4',5126:'<f4'}
WIDTHS={'SCALAR':1,'VEC2':2,'VEC3':3,'VEC4':4,'MAT2':4,'MAT3':9,'MAT4':16}


def parse_glb(path):
    b=pathlib.Path(path).read_bytes()
    if len(b)<20:
        raise ValueError('file is too short for GLB')
    magic, version, length=struct.unpack_from('<4sII',b,0)
    if magic!=b'glTF' or version!=2 or length!=len(b):
        raise ValueError('invalid GLB v2 magic/version/byte length')
    chunks=[]; off=12
    while off<len(b):
        if off+8>len(b): raise ValueError('truncated GLB chunk header')
        n,typ=struct.unpack_from('<II',b,off);off+=8
        if n%4 or off+n>len(b): raise ValueError('invalid GLB chunk length/alignment')
        chunks.append((typ,b[off:off+n]));off+=n
    if chunks[0][0]!=0x4e4f534a: raise ValueError('first GLB chunk is not JSON')
    doc=json.loads(chunks[0][1].decode('utf-8'))
    bins=[v for typ,v in chunks if typ==0x004e4942]
    if len(bins)>1:raise ValueError('more than one GLB binary chunk')
    buffers=[]
    for i,info in enumerate(doc.get('buffers',[])):
        if 'uri' not in info:
            if i or not bins:raise ValueError('unresolved embedded buffer')
            raw=bins[0]
        elif info['uri'].startswith('data:'):
            raw=base64.b64decode(info['uri'].split(',',1)[1])
        else:raise ValueError('external buffer resource: '+info['uri'])
        if len(raw)<info['byteLength']:raise ValueError('buffer shorter than declaration')
        buffers.append(raw)
    return doc,buffers


def accessor(doc,buffers,index):
    a=doc['accessors'][index]
    if 'sparse' in a:raise ValueError('sparse accessors are not expected in the export')
    if 'bufferView' not in a:raise ValueError('accessor has no bufferView')
    v=doc['bufferViews'][a['bufferView']]
    dt=np.dtype(DTYPES[a['componentType']]); width=WIDTHS[a['type']]
    raw=buffers[v.get('buffer',0)];off=v.get('byteOffset',0)+a.get('byteOffset',0)
    stride=v.get('byteStride',dt.itemsize*width)
    if a['count']:
        if off+stride*(a['count']-1)+dt.itemsize*width>len(raw):raise ValueError('accessor overruns buffer')
    out=np.ndarray((a['count'],width),dtype=dt,buffer=raw,offset=off,strides=(stride,dt.itemsize)).copy()
    if a.get('normalized'):
        if np.issubdtype(dt,np.unsignedinteger):out=out.astype(float)/np.iinfo(dt).max
        elif np.issubdtype(dt,np.signedinteger):out=np.maximum(out.astype(float)/np.iinfo(dt).max,-1)
    return out


def local_matrix(n):
    if 'matrix' in n:return np.asarray(n['matrix'],float).reshape(4,4).T
    T=np.eye(4); T[:3,3]=n.get('translation',[0,0,0])
    x,y,z,w=n.get('rotation',[0,0,0,1])
    R=np.eye(4)
    R[:3,:3]=[[1-2*(y*y+z*z),2*(x*y-z*w),2*(x*z+y*w)],
              [2*(x*y+z*w),1-2*(x*x+z*z),2*(y*z-x*w)],
              [2*(x*z-y*w),2*(y*z+x*w),1-2*(x*x+y*y)]]
    S=np.diag(list(n.get('scale',[1,1,1]))+[1.0])
    return T@R@S


def world_matrices(doc):
    ns=doc.get('nodes',[]); parents={}
    for i,n in enumerate(ns):
        for c in n.get('children',[]):
            if c in parents:raise ValueError('node has multiple parents')
            parents[c]=i
    result={};visiting=set()
    def visit(i):
        if i in result:return result[i]
        if i in visiting:raise ValueError('cycle in node hierarchy')
        visiting.add(i);m=local_matrix(ns[i])
        if i in parents:m=visit(parents[i])@m
        result[i]=m;visiting.remove(i);return m
    for i in range(len(ns)):visit(i)
    return result


def images(doc,buffers):
    out=[]
    for im in doc.get('images',[]):
        if 'bufferView' in im:
            v=doc['bufferViews'][im['bufferView']]
            raw=buffers[v.get('buffer',0)][v.get('byteOffset',0):v.get('byteOffset',0)+v['byteLength']]
        elif im.get('uri','').startswith('data:'):
            raw=base64.b64decode(im['uri'].split(',',1)[1])
        else:raise ValueError('external image resource: '+im.get('uri','missing'))
        pic=Image.open(io.BytesIO(raw));pic.load()
        out.append({'size':list(pic.size),'mode':pic.mode,'format':pic.format})
    return out


def texture_fields(obj,path=''):
    found=[]
    if isinstance(obj,dict):
        for k,v in obj.items():
            loc=f'{path}.{k}' if path else k
            if k.lower().endswith('texture') and isinstance(v,dict) and 'index' in v:found.append((loc,v))
            found+=texture_fields(v,loc)
    elif isinstance(obj,list):
        for i,v in enumerate(obj):found+=texture_fields(v,f'{path}[{i}]')
    return found


def mesh_nodes(doc,buffers):
    mats=world_matrices(doc);out={}
    for i,n in enumerate(doc.get('nodes',[])):
        if 'mesh' not in n:continue
        ps=doc['meshes'][n['mesh']]['primitives']; allv=[];alltris=[];tc=0
        for p in ps:
            a=p['attributes'];v=accessor(doc,buffers,a['POSITION'])
            w=np.c_[v,np.ones(len(v))]@mats[i].T;allv.append(w[:,:3])
            mode=p.get('mode',4)
            count=doc['accessors'][p['indices']]['count'] if 'indices' in p else len(v)
            if mode==4:
                tc+=count//3
                ix=accessor(doc,buffers,p['indices']).ravel() if 'indices' in p else np.arange(len(v))
                if len(ix)%3==0:alltris.append(w[:,:3][ix.reshape(-1,3)])
            elif mode in (5,6):tc+=max(0,count-2)
        vv=np.concatenate(allv) if allv else np.empty((0,3))
        out[n.get('name','')]=dict(index=i,origin=mats[i][:3,3],matrix=mats[i],
                                  bounds=np.array([vv.min(0),vv.max(0)]) if len(vv) else None,
                                  vertices=vv,faces=np.concatenate(alltris) if alltris else np.empty((0,3,3)),primitives=ps,triangles=tc)
    return out


def point_mesh_distance(point,tris):
    """Exact point-to-triangle minimum distance, including triangle edges."""
    if not len(tris):return float('inf')
    a,b,c=tris[:,0],tris[:,1],tris[:,2]
    ab=b-a;ac=c-a;normal=np.cross(ab,ac)
    n2=np.einsum('ij,ij->i',normal,normal)
    q=point-a
    plane=np.einsum('ij,ij->i',q,normal)
    d00=np.einsum('ij,ij->i',ab,ab);d01=np.einsum('ij,ij->i',ab,ac);d11=np.einsum('ij,ij->i',ac,ac)
    d20=np.einsum('ij,ij->i',q,ab);d21=np.einsum('ij,ij->i',q,ac)
    det=d00*d11-d01*d01
    valid=np.abs(det)>1e-22
    u=np.zeros(len(tris));v=u.copy()
    u[valid]=(d11[valid]*d20[valid]-d01[valid]*d21[valid])/det[valid]
    v[valid]=(d00[valid]*d21[valid]-d01[valid]*d20[valid])/det[valid]
    inside=valid&(u>=-1e-8)&(v>=-1e-8)&(u+v<=1+1e-8)&(n2>1e-22)
    best=float(np.min(plane[inside]**2/n2[inside])) if np.any(inside) else float('inf')
    for s,e in ((a,b),(b,c),(c,a)):
        edge=e-s;delta=point-s;length2=np.einsum('ij,ij->i',edge,edge)
        t=np.divide(np.einsum('ij,ij->i',delta,edge),length2,out=np.zeros(len(tris)),where=length2>1e-22)
        close=s+np.clip(t,0,1)[:,None]*edge
        best=min(best,float(np.min(np.einsum('ij,ij->i',point-close,point-close))))
    return math.sqrt(max(0,best))


def reference_ramp_surface_error(reftris,gottris):
    """Check nine samples on every upward reference triangle against final surfaces."""
    norms=np.cross(reftris[:,1]-reftris[:,0],reftris[:,2]-reftris[:,0])
    top=reftris[norms[:,1]>1e-12]
    gnorms=np.cross(gottris[:,1]-gottris[:,0],gottris[:,2]-gottris[:,0])
    got_top=gottris[gnorms[:,1]>1e-12]
    if not len(top) or not len(got_top):return None,0
    weights=np.array([[1,0,0],[0,1,0],[0,0,1],[.5,.5,0],[.5,0,.5],[0,.5,.5],[1/3,1/3,1/3],[.6,.2,.2],[.2,.6,.2]])
    points=np.einsum('wp,tpc->twc',weights,top).reshape(-1,3)
    return max(point_mesh_distance(p,got_top) for p in points),len(points)


def audit_glb(path,refpath,budget):
    errors=[];notes=[];name=path.name
    j,bb=parse_glb(path)
    if j.get('asset',{}).get('version')!='2.0':errors.append('asset.version is not 2.0')
    for k in ('animations','cameras','skins'):
        if j.get(k):errors.append(f'{k} are present')
    if 'KHR_lights_punctual' in j.get('extensions',{}) or 'KHR_lights_punctual' in j.get('extensionsUsed',[]):
        errors.append('punctual lights are present')
    ns=j.get('nodes',[]); names=[n.get('name','') for n in ns if 'mesh' in n]
    if len(set(names))!=len(names):errors.append('duplicate mesh node names')
    if any(not n for n in names):errors.append('unnamed mesh node')
    for i,n in enumerate(ns):
        if 'camera' in n:errors.append(f'node {i} contains a camera')
        scale=np.linalg.norm(local_matrix(n)[:3,:3],axis=0)
        if not np.allclose(scale,[1,1,1],atol=1e-5):errors.append(f'{n.get("name",i)}: unapplied node scale {scale.tolist()}')
        if not np.isfinite(local_matrix(n)).all():errors.append(f'{n.get("name",i)}: nonfinite node transform')
    got=mesh_nodes(j,bb)
    ref={}
    if refpath.exists():
        r,rb=parse_glb(refpath);ref=mesh_nodes(r,rb)
        required=set(ref)
    elif name=='Space_PodHoods.glb':required={'PodHood1','PodHood2'}
    else:required=set();errors.append('reference file missing')
    missing=required-set(got)
    if missing:errors.append('missing required objects: '+', '.join(sorted(missing)))
    extras=set(got)-required
    if any(not n.startswith('Deco_') for n in extras):errors.append('extra objects without Deco_ prefix: '+', '.join(sorted(n for n in extras if not n.startswith('Deco_'))))
    if len(extras)>10:errors.append(f'{len(extras)} extra mesh objects exceeds 10')
    nonmesh=[n.get('name',str(i)) for i,n in enumerate(ns) if 'mesh' not in n]
    if nonmesh:notes.append('Non-mesh transform nodes: '+', '.join(nonmesh))
    max_origin_error=0.0
    for n in required & set(got) & set(ref):
        err=float(np.max(np.abs(got[n]['origin']-ref[n]['origin'])))
        max_origin_error=max(max_origin_error,err)
        if err>0.001:errors.append(f'{n}: world origin differs by {err*1000:.3f} mm')
        if not np.allclose(got[n]['matrix'][:3,:3],ref[n]['matrix'][:3,:3],atol=1e-5):
            notes.append(f'{n}: node rotation differs from reference; world-space geometry checked by supplied checker')
    image_info=images(j,bb)
    for i,im in enumerate(image_info):
        if max(im['size'])>1024:errors.append(f'image {i} exceeds 1024 pixels')
    usedmats=set();material_summary={};textured_objects=[];minmax=[];node_summary={}
    for n,g in got.items():
        ps=g['primitives']
        if len(ps)!=1:errors.append(f'{n}: {len(ps)} mesh primitives; one is required to preserve object/material identity')
        mids={p.get('material') for p in ps}
        if len(mids)!=1 or None in mids:errors.append(f'{n}: must have one explicit material')
        minmax.append(g['bounds'])
        for p in ps:
            if p.get('mode',4)!=4:errors.append(f'{n}: primitive is not triangle-list mode')
            attrs=p.get('attributes',{});v=accessor(j,bb,attrs['POSITION'])
            if not np.isfinite(v).all():errors.append(f'{n}: nonfinite positions')
            if 'indices' in p:
                ix=accessor(j,bb,p['indices']).ravel()
                if len(ix)%3:errors.append(f'{n}: triangle indices not multiple of three')
                if len(ix) and (ix.min()<0 or ix.max()>=len(v)):errors.append(f'{n}: index out of range')
            if 'NORMAL' not in attrs:notes.append(f'{n}: vertex normals absent')
            if 'COLOR_0' in attrs:errors.append(f'{n}: vertex colours conflict with plain base-colour material rule')
        for mid in mids-{None}:
            usedmats.add(mid); mat=j['materials'][mid];pbr=mat.get('pbrMetallicRoughness',{})
            fields=texture_fields(mat)
            allowed={'pbrMetallicRoughness.baseColorTexture'} if n in {'Board','Apron'} and '_Playfield' in name else set()
            for loc,tex in fields:
                if loc not in allowed:errors.append(f'{n}: prohibited texture {loc}')
            if fields:
                textured_objects.append(n)
                if 'TEXCOORD_0' not in ps[0].get('attributes',{}):errors.append(f'{n}: textured mesh has no UV coordinates')
            if n in {'Board','Apron'} and '_Playfield' in name:
                t=pbr.get('baseColorTexture')
                if not t:errors.append(f'{n}: missing embedded base-colour artwork')
                else:
                    tex=j['textures'][t['index']];si=tex.get('source')
                    if si is None:errors.append(f'{n}: texture source missing')
                    elif n=='Board' and image_info[si]['size']!=[486,1024]:errors.append(f'Board texture {image_info[si]["size"]}, expected [486, 1024]')
            alpha=pbr.get('baseColorFactor',[1,1,1,1])[3]
            mode=mat.get('alphaMode','OPAQUE')
            may_transparent=n=='Glass' or n.startswith('Ramp_')
            if not may_transparent and (mode!='OPAQUE' or abs(alpha-1)>1e-6):errors.append(f'{n}: transparency is restricted to Glass and ramp tracks')
            if n=='Glass':
                if mode!='BLEND':errors.append('Glass must use alpha BLEND')
                if not 0.02<=alpha<=0.08:errors.append(f'Glass alpha {alpha:.4f}, expected approximately 0.05')
            if n.startswith('Ramp_') and (mode!='BLEND' or not 0<alpha<1):errors.append(f'{n}: clear ramp must use alpha BLEND with partial opacity')
            material_summary[n]={'material':mat.get('name',str(mid)),'baseColor':pbr.get('baseColorFactor',[1,1,1,1]),'alphaMode':mode,'textureFields':[f for f,_ in fields]}
        node_summary[n]={'triangles':g['triangles'],'origin_m':g['origin'].tolist(),'bounds_m':g['bounds'].tolist()}
        if n.startswith('Ramp_') and n in ref:
            surface_error, samples=reference_ramp_surface_error(ref[n]['faces'],g['faces'])
            node_summary[n]['reference_track_surface_samples']=samples
            node_summary[n]['reference_track_surface_max_error_mm']=surface_error*1000 if surface_error is not None else None
            if surface_error is None:errors.append(f'{n}: reference ramp has no upward surface')
            elif surface_error>0.001:errors.append(f'{n}: original ramp track surface differs by {surface_error*1000:.3f} mm')
        if name!='Pinball_Cabinet.glb' and not n.startswith('Ramp_') and g['bounds'][1,1]>=0.14:
            errors.append(f'{n}: reaches the 0.14 m glass height')
        if n in ref and name not in {'Pinball_Cabinet.glb','Pinball_PopBumper.glb','Pinball_Plunger.glb','Pinball_Gate.glb'} and n!='Apron':
            if g['bounds'][1,1]<ref[n]['bounds'][1,1]-1e-5:
                errors.append(f'{n}: top is {(ref[n]["bounds"][1,1]-g["bounds"][1,1])*1000:.3f} mm lower than reference')
    triangles=sum(g['triangles'] for g in got.values())
    if triangles>budget:errors.append(f'{triangles} triangles exceeds budget {budget}')
    if not minmax:errors.append('no geometry found')
    else:
        aa=np.array(minmax);lo=aa[:,0].min(0);hi=aa[:,1].max(0);span=(hi-lo).max()
        if not .005<=span<=5:errors.append(f'metre scale envelope implausible ({span:g} m)')
    if len(usedmats)<len(j.get('materials',[])):notes.append('Some exported materials are unused')
    return {'file':name,'pass':not errors,'errors':errors,'notes':notes,'triangles':triangles,'triangle_budget':budget,'mesh_objects':len(got),'decoration_objects':len(extras),'max_origin_error_mm':max_origin_error*1000,'embedded_images':image_info,'textured_objects':sorted(set(textured_objects)),'materials':material_summary,'nodes':node_summary,'bytes':path.stat().st_size}


def audit_png(path):
    im=Image.open(path);im.load();errors=[]
    if im.size!=(854,1024):errors.append(f'expected 854 x 1024, got {im.size[0]} x {im.size[1]}')
    if im.format!='PNG':errors.append('file is not PNG')
    if 'A' in im.getbands() and im.getchannel('A').getextrema()!=(255,255):errors.append('backglass must be opaque')
    return {'file':path.name,'pass':not errors,'errors':errors,'notes':[],'size':list(im.size),'bytes':path.stat().st_size}


def instance_totals(files,data):
    count={f['file']:f.get('triangles',0) for f in files if f.get('triangles') is not None}
    result={}
    for key,m in data['machines'].items():
        pre=m['file_prefix'];parts={f'Pinball_Cabinet.glb':1, f'{pre}_Playfield.glb':1,f'{pre}_Guides.glb':1,f'{pre}_Slingshots.glb':1,f'{pre}_Targets.glb':1,
            'Pinball_Flipper.glb':len(m['flippers']),'Pinball_PopBumper.glb':len(m['bumpers']),'Pinball_Plunger.glb':1,'Pinball_Gate.glb':len(m['gates'])}
        if key=='acorn':parts['Acorn_Spinner.glb']=1
        if key=='rodent':parts['Rodent_Wire.glb']=1
        if key=='space':parts.update({'Space_Ramps.glb':1,'Space_PodHoods.glb':1})
        result[key]={'triangle_total':sum(count.get(f,0)*n for f,n in parts.items()),'missing_files':[f for f in parts if f not in count],
                     'instance_counts':parts,'note':'Static exported geometry, including instanced shared parts. Game-created balls, lights and inserts excluded.'}
    return result


def main():
    ap=argparse.ArgumentParser(description=__doc__)
    ap.add_argument('models',type=pathlib.Path)
    ap.add_argument('--pack',type=pathlib.Path,required=True)
    ap.add_argument('--json',type=pathlib.Path)
    args=ap.parse_args();files=[]
    for f,limit in BUDGETS.items():
        p=args.models/f
        try:
            r=audit_glb(p,args.pack/'reference'/f,limit) if p.exists() else {'file':f,'pass':False,'errors':['missing file'],'notes':[]}
        except Exception as e:r={'file':f,'pass':False,'errors':[f'audit could not parse file: {type(e).__name__}: {e}'],'notes':[]}
        if p.exists():r['sha256']=hashlib.sha256(p.read_bytes()).hexdigest()
        files.append(r)
    for f in PNGS:
        p=args.models/f
        try:r=audit_png(p) if p.exists() else {'file':f,'pass':False,'errors':['missing file'],'notes':[]}
        except Exception as e:r={'file':f,'pass':False,'errors':[f'audit could not parse file: {type(e).__name__}: {e}'],'notes':[]}
        if p.exists():r['sha256']=hashlib.sha256(p.read_bytes()).hexdigest()
        files.append(r)
    data=json.loads((args.pack/'pinball_data.json').read_text()); totals=instance_totals(files,data)
    result={'audit_version':1,'scope':'Supplemental structural audit; the original checker remains the authority for footprint tolerances.',
            'files':files,'passed':sum(f['pass'] for f in files),'expected':len(files),'machine_totals':totals,
            'not_automatically_verified':['Art content restrictions, artistic quality and typography require visual review.',
                'Ramp samples verify retention of reference upper surfaces within 1 mm; smooth ball contact still requires in-engine review.',
                'Exact word and lamp artwork coordinates require source-data review; no OCR approximation is used.',
                'Actual performance and gameplay in Roblox require in-engine verification.']}
    for f in files:
        stats=f' | {f["triangles"]}/{f["triangle_budget"]} triangles, {f["mesh_objects"]} objects' if 'triangles' in f else ''
        print(('PASS ' if f['pass'] else 'FAIL ')+f['file']+stats)
        for e in f['errors']:print('  - '+e)
        for n in f['notes']:print('  note: '+n)
    print(f'\nSupplemental audit: {result["passed"]} of {result["expected"]} files pass')
    for k,t in totals.items():print(f'{k}: {t["triangle_total"]:,} triangles per assembled machine'+(' (incomplete)' if t['missing_files'] else ''))
    if args.json:
        args.json.parent.mkdir(parents=True,exist_ok=True);args.json.write_text(json.dumps(result,indent=2)+'\n')
    return 0 if all(f['pass'] for f in files) else 1

if __name__=='__main__':sys.exit(main())
