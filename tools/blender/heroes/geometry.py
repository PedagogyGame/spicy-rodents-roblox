"""Mesh building for the hero animals: SDF -> high/low poly, UVs and the small hard parts."""
import math

import bmesh
import bpy
import numpy as np
from mathutils import Matrix, Vector

import bl
import sdf


def sculpt_mesh(body, h, name, steps=2):
    F, origin, hh = body.grid(h)
    v, q = sdf.surface_nets(F, origin, hh)
    del F
    v = body.project(v, steps=steps)
    obj = bl.mesh_from_arrays(name, v, q)
    return obj


def decimate_to(obj, target_tris, symmetric=True, vgroup=None, vfactor=1.0):
    me = obj.data
    tris = bl.tri_count(me)
    ratio = min(1.0, target_tris / max(tris, 1))
    mod = obj.modifiers.new("Decimate", "DECIMATE")
    mod.decimate_type = "COLLAPSE"
    mod.ratio = ratio
    mod.use_collapse_triangulate = True
    mod.use_symmetry = symmetric
    mod.symmetry_axis = "X"
    if vgroup:
        mod.vertex_group = vgroup
        mod.vertex_group_factor = vfactor
    bl.apply_modifiers(obj)
    # a second pass lands closer to the target (the first overshoots on symmetric meshes)
    tris = bl.tri_count(obj.data)
    if tris > target_tris * 1.01:
        mod = obj.modifiers.new("Decimate2", "DECIMATE")
        mod.decimate_type = "COLLAPSE"
        mod.ratio = target_tris / tris
        mod.use_collapse_triangulate = True
        mod.use_symmetry = symmetric
        mod.symmetry_axis = "X"
        bl.apply_modifiers(obj)
    return bl.tri_count(obj.data)


def smooth_mesh(obj, factor=0.5, repeat=2):
    mod = obj.modifiers.new("Smooth", "SMOOTH")
    mod.factor = factor
    mod.iterations = repeat
    bl.apply_modifiers(obj)


def uv_unwrap(obj, angle=66.0, margin=0.006):
    bl.select_only([obj])
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_all(action="SELECT")
    bpy.ops.uv.smart_project(angle_limit=math.radians(angle), island_margin=margin, area_weight=0.0,
                             correct_aspect=True, scale_to_bounds=False)
    bpy.ops.uv.pack_islands(rotate=True, margin=margin)
    bpy.ops.object.mode_set(mode="OBJECT")


def weld_close(obj, dist=1e-5):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=dist)
    bm.to_mesh(obj.data)
    bm.free()


def recalc_normals(obj):
    bm = bmesh.new()
    bm.from_mesh(obj.data)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(obj.data)
    bm.free()


# ---- small hard parts (each returns verts, faces, and a per-vertex "t" along the part) ------------------

def _frame(d):
    d = np.asarray(d, float)
    d = d / np.linalg.norm(d)
    up = np.array([0, 0, 1.0]) if abs(d[2]) < 0.9 else np.array([1.0, 0, 0])
    x = np.cross(d, up)
    x /= np.linalg.norm(x)
    y = np.cross(x, d)
    return d, x, y


def curved_spike(base, direction, length, radius, curl=(0, 0, -1), curl_amt=0.35, sides=5, segs=3, flat=1.0):
    """A tapering curved horn: claws, teeth, antler tines. Returns (verts, faces)."""
    base = np.asarray(base, float)
    d0 = np.asarray(direction, float)
    d0 /= np.linalg.norm(d0)
    curl = np.asarray(curl, float)
    pts, dirs = [base], [d0]
    p, d = base.copy(), d0.copy()
    for i in range(segs):
        d = d + curl * curl_amt / segs
        d /= np.linalg.norm(d)
        p = p + d * length / segs
        pts.append(p.copy())
        dirs.append(d.copy())
    verts, faces = [], []
    for i, (p, d) in enumerate(zip(pts[:-1], dirs[:-1])):
        _d, x, y = _frame(d)
        r = radius * (1 - i / segs) ** 0.8
        for s in range(sides):
            a = 2 * math.pi * s / sides
            verts.append(p + x * math.cos(a) * r * flat + y * math.sin(a) * r)
    tip = len(verts)
    verts.append(pts[-1])
    for i in range(segs - 1):
        for s in range(sides):
            a, b = i * sides + s, i * sides + (s + 1) % sides
            faces.append((a, b, b + sides, a + sides))
    last = (segs - 1) * sides
    for s in range(sides):
        faces.append((last + s, last + (s + 1) % sides, tip))
    # cap the base
    faces.append(tuple(reversed(range(sides))))
    return np.array(verts), faces


def box_part(center, half, axes=None):
    axes = np.eye(3) if axes is None else np.asarray(axes, float)
    c = np.asarray(center, float)
    h = np.asarray(half, float)
    corners = np.array([[sx, sy, sz] for sx in (-1, 1) for sy in (-1, 1) for sz in (-1, 1)], float)
    verts = c + (corners * h) @ axes.T
    faces = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    return verts, faces


def uv_sphere(center, radius, gaze, segs=16, rings=10, squash=(1, 1, 1)):
    """A sphere whose +pole looks along `gaze`; UV v = 1 at that pole (the pupil). Returns
    (verts, faces, uvs-per-face-corner)."""
    g, x, y = _frame(gaze)
    c = np.asarray(center, float)
    verts, faces, uvs = [], [], []
    # ring 0 is the gaze pole, ring `rings` the back pole
    for r in range(rings + 1):
        th = math.pi * r / rings
        for s in range(segs + 1):
            ph = 2 * math.pi * s / segs
            v = g * math.cos(th) * squash[2] + (x * math.cos(ph) * squash[0] + y * math.sin(ph) * squash[1]) * math.sin(th)
            verts.append(c + v * radius)
    idx = lambda r, s: r * (segs + 1) + s
    for r in range(rings):
        for s in range(segs):
            f = (idx(r, s), idx(r + 1, s), idx(r + 1, s + 1), idx(r, s + 1))
            faces.append(f)
            uvs.append([(s / segs, 1 - r / rings), (s / segs, 1 - (r + 1) / rings), ((s + 1) / segs, 1 - (r + 1) / rings), ((s + 1) / segs, 1 - r / rings)])
    return np.array(verts), faces, uvs


def object_from_parts(name, parts, smooth=True):
    """parts: list of (verts, faces[, tag]) -> one object; returns (obj, per-vertex part index)."""
    allv, allf, owner = [], [], []
    off = 0
    for i, part in enumerate(parts):
        v, f = part[0], part[1]
        allv.extend(np.asarray(v).tolist())
        allf.extend([tuple(int(k) + off for k in face) for face in f])
        owner.extend([i] * len(v))
        off += len(v)
    obj = bl.mesh_from_arrays(name, np.array(allv), allf, smooth=smooth)
    return obj, np.array(owner)


def join_into(target, others):
    bl.select_only([target] + list(others), active=target)
    bpy.ops.object.join()
    return target
