"""tools/review/render.py: render the exported review scene (tools/review/export.luau) from named viewpoints.

  /root/.cache/spicy-rodents/venv/bin/python -I tools/review/render.py \
      [--scene build/review/scene.json] [--views tools/review/views.json] [--out build/review] \
      [--only a_street_level,f1_lineup] [--debug] [--samples N] [--res 960x540] [--threads 2]

Builds the scene with bpy (no .blend is written) and renders each view with Cycles on the CPU (low samples,
adaptive sampling, OpenImageDenoise) to <out>/<view>.png; writes <out>/timing.json.

Axes. Roblox is Y-up, right-handed, -Z forward; Blender is Z-up, right-handed. Roblox (x, y, z) maps to
Blender (x, -z, y): a proper rotation (+90 degrees about X), so handedness and polygon winding survive.
1 stud = 1 Blender unit. `--debug` adds the `axes_check` view (views.json, "debug": true), which renders red
+X, green +Y and blue +Z bars, a WedgePart, a cylinder and a ball at the origin through the same code path.

Shapes, in the part's own (Roblox) frame, scaled by Size:
  Block / Box   unit cube (MeshPart and other classes are drawn as their bounding box)
  Cylinder      axis along local X, length Size.X, diameter min(Size.Y, Size.Z)
  Ball          sphere of diameter Size.X
  Wedge         Roblox WedgePart: full bottom face, full back (+Z) face, slope from the bottom front edge
                (-Z) up to the top back edge (Spec.luau: "slope rises toward local +Z")
  CornerWedge   apex above the (+X, -Z) corner (UNVERIFIED against Studio; none in the town today)
Beams are cylinders of diameter = width between their attachments' world points.

Materials: one attribute-driven principled shader for opaque parts (colour, roughness and metallic per face
from the Roblox Material name), an emission shader for Neon, an alpha shader for Transparency > 0. Glass at
Transparency 0 renders opaque and glossy, as Roblox draws it. Terrain is a heightfield of World/Height
(export.luau) coloured with the WorldTerrain material colours; river columns get a water sheet.
Light: a warm sun plus a gradient sky, roughly LightingPreset.GOLDEN (16:00 sun from the south-west with
the game's North = +Z, i.e. from +X/-Z); approximate, not the engine's exact sun.
"""
import argparse
import json
import math
import os
import sys
import time
import warnings

import bpy
import numpy as np
from mathutils import Matrix, Vector

warnings.filterwarnings("ignore", category=DeprecationWarning)  # Material/World.use_nodes (Blender 6)

# Roblox -> Blender: (x, y, z) -> (x, -z, y)
AXES = np.array([[1.0, 0.0, 0.0], [0.0, 0.0, -1.0], [0.0, 1.0, 0.0]])


def rb_to_bl(v):
    return Vector((v[0], -v[2], v[1]))


# Roblox Material name -> (roughness, metallic)
SURFACE = {
    "SmoothPlastic": (0.42, 0.0),
    "Plastic": (0.5, 0.0),
    "Neon": (0.5, 0.0),
    "Glass": (0.06, 0.0),
    "ForceField": (0.3, 0.0),
    "Metal": (0.38, 0.65),
    "DiamondPlate": (0.35, 0.7),
    "CorrodedMetal": (0.7, 0.4),
    "Foil": (0.25, 0.8),
    "Grass": (0.95, 0.0),
    "LeafyGrass": (0.95, 0.0),
    "Wood": (0.8, 0.0),
    "WoodPlanks": (0.78, 0.0),
    "Ground": (0.95, 0.0),
    "Mud": (0.9, 0.0),
    "Sand": (0.95, 0.0),
    "Slate": (0.85, 0.0),
    "Brick": (0.9, 0.0),
    "Cobblestone": (0.9, 0.0),
    "Concrete": (0.9, 0.0),
    "Asphalt": (0.92, 0.0),
    "Limestone": (0.85, 0.0),
    "Plaster": (0.88, 0.0),
    "Marble": (0.3, 0.0),
    "Granite": (0.6, 0.0),
    "Fabric": (0.95, 0.0),
}


# ----------------------------------------------------------------------------------------------- shapes
def _orient(verts, faces):
    """Reverse any face whose Newell normal points into the (convex, origin-centred) solid."""
    out = []
    centre = verts.mean(axis=0)
    for f in faces:
        p = verts[f]
        n = np.zeros(3)
        for i in range(len(f)):
            a, b = p[i], p[(i + 1) % len(f)]
            n += np.array([(a[1] - b[1]) * (a[2] + b[2]), (a[2] - b[2]) * (a[0] + b[0]), (a[0] - b[0]) * (a[1] + b[1])])
        out.append(list(f) if np.dot(n, p.mean(axis=0) - centre) >= 0 else list(reversed(f)))
    return out


def _template(verts, faces, smooth):
    verts = np.array(verts, dtype=np.float64)
    faces = _orient(verts, faces)
    return {
        "v": verts,
        "loops": np.array([i for f in faces for i in f], dtype=np.int64),
        "totals": np.array([len(f) for f in faces], dtype=np.int64),
        "smooth": np.array(smooth, dtype=bool),
    }


def make_templates(cyl_n=20, sph_u=18, sph_v=10):
    h = 0.5
    cube_v = [(x, y, z) for x in (-h, h) for y in (-h, h) for z in (-h, h)]
    idx = {v: i for i, v in enumerate(cube_v)}
    cube_f = [
        [idx[(-h, -h, -h)], idx[(-h, -h, h)], idx[(-h, h, h)], idx[(-h, h, -h)]],
        [idx[(h, -h, -h)], idx[(h, h, -h)], idx[(h, h, h)], idx[(h, -h, h)]],
        [idx[(-h, -h, -h)], idx[(h, -h, -h)], idx[(h, -h, h)], idx[(-h, -h, h)]],
        [idx[(-h, h, -h)], idx[(-h, h, h)], idx[(h, h, h)], idx[(h, h, -h)]],
        [idx[(-h, -h, -h)], idx[(-h, h, -h)], idx[(h, h, -h)], idx[(h, -h, -h)]],
        [idx[(-h, -h, h)], idx[(h, -h, h)], idx[(h, h, h)], idx[(-h, h, h)]],
    ]
    block = _template(cube_v, cube_f, [False] * 6)

    # WedgePart: bottom (y=-h) full, back (z=+h) full, top edge at the back
    wv = [(-h, -h, -h), (h, -h, -h), (h, -h, h), (-h, -h, h), (-h, h, h), (h, h, h)]
    wf = [[0, 1, 2, 3], [3, 2, 5, 4], [0, 1, 5, 4], [0, 3, 4], [1, 2, 5]]
    wedge = _template(wv, wf, [False] * 5)

    # CornerWedgePart (unverified): apex above the (+X, -Z) bottom corner
    cv = [(-h, -h, -h), (h, -h, -h), (h, -h, h), (-h, -h, h), (h, h, -h)]
    cf = [[0, 1, 2, 3], [1, 2, 4], [0, 1, 4], [2, 3, 4], [3, 0, 4]]
    corner = _template(cv, cf, [False] * 5)

    # Cylinder along local X
    n = cyl_n
    ang = np.linspace(0, 2 * math.pi, n, endpoint=False)
    ring = [(math.cos(a) * h, math.sin(a) * h) for a in ang]
    cyl_v = [(-h, y, z) for (y, z) in ring] + [(h, y, z) for (y, z) in ring]
    cyl_f = [[i, (i + 1) % n, n + (i + 1) % n, n + i] for i in range(n)]
    cyl_f += [list(range(n)), list(range(n, 2 * n))]
    cylinder = _template(cyl_v, cyl_f, [True] * n + [False, False])

    # UV sphere
    sv = [(0.0, h, 0.0)]
    for j in range(1, sph_v):
        phi = math.pi * j / sph_v
        for i in range(sph_u):
            th = 2 * math.pi * i / sph_u
            sv.append((h * math.sin(phi) * math.cos(th), h * math.cos(phi), h * math.sin(phi) * math.sin(th)))
    sv.append((0.0, -h, 0.0))
    sf = []
    bottom = len(sv) - 1
    for i in range(sph_u):
        sf.append([0, 1 + i, 1 + (i + 1) % sph_u])
    for j in range(sph_v - 2):
        r0, r1 = 1 + j * sph_u, 1 + (j + 1) * sph_u
        for i in range(sph_u):
            sf.append([r0 + i, r1 + i, r1 + (i + 1) % sph_u, r0 + (i + 1) % sph_u])
    last = 1 + (sph_v - 2) * sph_u
    for i in range(sph_u):
        sf.append([last + i, bottom, last + (i + 1) % sph_u])
    ball = _template(sv, sf, [True] * len(sf))
    return {
        "Block": block,
        "Box": block,
        "Wedge": wedge,
        "CornerWedge": corner,
        "Cylinder": cylinder,
        "Ball": ball,
    }


# ----------------------------------------------------------------------------------------------- meshes
def build_mesh(name, verts, loops, totals, face_attrs, smooth):
    me = bpy.data.meshes.new(name)
    me.vertices.add(len(verts))
    me.vertices.foreach_set("co", np.ascontiguousarray(verts, dtype=np.float32).ravel())
    me.loops.add(len(loops))
    me.loops.foreach_set("vertex_index", np.ascontiguousarray(loops, dtype=np.int32))
    me.polygons.add(len(totals))
    starts = np.zeros(len(totals), dtype=np.int32)
    if len(totals) > 1:
        starts[1:] = np.cumsum(totals[:-1])
    me.polygons.foreach_set("loop_start", starts)
    me.update(calc_edges=True)
    for aname, (kind, data) in face_attrs.items():
        at = me.attributes.new(aname, kind, "FACE")
        key = "color" if kind == "FLOAT_COLOR" else "value"
        at.data.foreach_set(key, np.ascontiguousarray(data, dtype=np.float32).ravel())
    sharp = me.attributes.new("sharp_face", "BOOLEAN", "FACE")
    sharp.data.foreach_set("value", np.ascontiguousarray(~np.asarray(smooth, dtype=bool)))
    me.validate(clean_customdata=False)
    return me


def srgb_to_linear(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def parts_mesh(name, parts, templates):
    """One mesh for a list of part dicts (Roblox frame): per-face col, rough, metal, alpha attributes."""
    by_shape = {}
    for p in parts:
        by_shape.setdefault(p["s"], []).append(p)
    vs, ls, ts, sm, cols, rough, metal, alpha = [], [], [], [], [], [], [], []
    base = 0
    for shape, plist in by_shape.items():
        t = templates.get(shape, templates["Block"])
        n = len(plist)
        pos = np.array([p["pos"] for p in plist], dtype=np.float64)
        rot = np.array([p["rot"] for p in plist], dtype=np.float64).reshape(n, 3, 3)
        size = np.array([p["size"] for p in plist], dtype=np.float64)
        if shape == "Cylinder":
            d = np.minimum(size[:, 1], size[:, 2])
            size = np.stack([size[:, 0], d, d], axis=1)
        elif shape == "Ball":
            size = np.repeat(size[:, :1], 3, axis=1)
        local = t["v"][None, :, :] * size[:, None, :]  # (n, k, 3)
        world = np.einsum("nij,nkj->nki", rot, local) + pos[:, None, :]
        bl = world @ AXES.T
        k = len(t["v"])
        vs.append(bl.reshape(-1, 3))
        offs = (np.arange(n, dtype=np.int64) * k + base)[:, None]
        ls.append((t["loops"][None, :] + offs).ravel())
        ts.append(np.tile(t["totals"], n))
        sm.append(np.tile(t["smooth"], n))
        nf = len(t["totals"])
        c = srgb_to_linear(np.array([p["c"] for p in plist], dtype=np.float64) / 255.0)
        rgba = np.concatenate([c, np.ones((n, 1))], axis=1)
        cols.append(np.repeat(rgba, nf, axis=0))
        rm = np.array([SURFACE.get(p["m"], (0.5, 0.0)) for p in plist], dtype=np.float64)
        rough.append(np.repeat(rm[:, 0], nf))
        metal.append(np.repeat(rm[:, 1], nf))
        alpha.append(np.repeat(np.array([1.0 - p["t"] for p in plist], dtype=np.float64), nf))
        base += n * k
    if not vs:
        return None
    return build_mesh(
        name,
        np.concatenate(vs),
        np.concatenate(ls),
        np.concatenate(ts),
        {
            "col": ("FLOAT_COLOR", np.concatenate(cols)),
            "rough": ("FLOAT", np.concatenate(rough)),
            "metal": ("FLOAT", np.concatenate(metal)),
            "alpha": ("FLOAT", np.concatenate(alpha)),
        },
        np.concatenate(sm),
    )


def beam_parts(beams):
    """Beams -> cylinder part dicts (axis = local X from a to b)."""
    out = []
    for b in beams:
        a, c = np.array(b["a"], dtype=np.float64), np.array(b["b"], dtype=np.float64)
        d = c - a
        length = float(np.linalg.norm(d))
        x = d / length
        helper = np.array([0.0, 1.0, 0.0]) if abs(x[1]) < 0.9 else np.array([1.0, 0.0, 0.0])
        z = np.cross(x, helper)
        z /= np.linalg.norm(z)
        y = np.cross(z, x)
        rot = np.stack([x, y, z], axis=1)  # columns
        out.append(
            {
                "s": "Cylinder",
                "pos": list((a + c) / 2),
                "rot": list(rot.ravel()),
                "size": [length, b["w"], b["w"]],
                "c": b["c"],
                "t": 0.0,
                "m": "SmoothPlastic",
            }
        )
    return out


# ----------------------------------------------------------------------------------------------- shaders
def _attr(nodes, name, x, y):
    n = nodes.new("ShaderNodeAttribute")
    n.attribute_type = "GEOMETRY"
    n.attribute_name = name
    n.location = (x, y)
    return n


def material_parts(name, transparent=False):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = nodes.get("Principled BSDF")
    col = _attr(nodes, "col", -500, 300)
    links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(_attr(nodes, "rough", -500, 100).outputs["Fac"], bsdf.inputs["Roughness"])
    links.new(_attr(nodes, "metal", -500, -100).outputs["Fac"], bsdf.inputs["Metallic"])
    if transparent:
        links.new(_attr(nodes, "alpha", -500, -300).outputs["Fac"], bsdf.inputs["Alpha"])
    return mat


def material_neon(name, strength=6.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = nodes.get("Principled BSDF")
    col = _attr(nodes, "col", -500, 300)
    links.new(col.outputs["Color"], bsdf.inputs["Base Color"])
    links.new(col.outputs["Color"], bsdf.inputs["Emission Color"])
    bsdf.inputs["Emission Strength"].default_value = strength
    return mat


def material_simple(name, rgb, rough=0.9, alpha=1.0):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    bsdf = mat.node_tree.nodes.get("Principled BSDF")
    bsdf.inputs["Base Color"].default_value = (*rgb, 1.0)
    bsdf.inputs["Roughness"].default_value = rough
    bsdf.inputs["Alpha"].default_value = alpha
    return mat


def material_terrain(name):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    bsdf = nt.nodes.get("Principled BSDF")
    nt.links.new(_attr(nt.nodes, "col", -500, 300).outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.95
    return mat


def material_checker(name, c1, c2):
    mat = bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    nodes, links = nt.nodes, nt.links
    bsdf = nodes.get("Principled BSDF")
    tc = nodes.new("ShaderNodeTexCoord")
    chk = nodes.new("ShaderNodeTexChecker")
    chk.inputs["Scale"].default_value = 1.0  # 1-stud squares in object space
    chk.inputs["Color1"].default_value = (*c1, 1.0)
    chk.inputs["Color2"].default_value = (*c2, 1.0)
    links.new(tc.outputs["Object"], chk.inputs["Vector"])
    links.new(chk.outputs["Color"], bsdf.inputs["Base Color"])
    bsdf.inputs["Roughness"].default_value = 0.9
    return mat


def link_object(name, data, group, mat=None):
    ob = bpy.data.objects.new(name, data)
    bpy.context.scene.collection.objects.link(ob)
    if mat is not None:
        data.materials.append(mat)
    ob["review_group"] = group
    return ob


# ----------------------------------------------------------------------------------------------- terrain
class Ground:
    """Bilinear lookup of the exported fine heightfield (Roblox x, z -> y); 0 outside."""

    def __init__(self, fine):
        self.f = fine
        if fine:
            self.h = np.array(fine["heights"], dtype=np.float64).reshape(fine["nz"], fine["nx"])

    def at(self, x, z):
        f = self.f
        if not f:
            return 0.0
        u = (x - f["x0"]) / f["step"] - 0.5
        v = (z - f["z0"]) / f["step"] - 0.5
        i0 = int(min(max(math.floor(u), 0), f["nx"] - 2))
        k0 = int(min(max(math.floor(v), 0), f["nz"] - 2))
        du, dv = min(max(u - i0, 0.0), 1.0), min(max(v - k0, 0.0), 1.0)
        h = self.h
        return float(
            h[k0, i0] * (1 - du) * (1 - dv)
            + h[k0, i0 + 1] * du * (1 - dv)
            + h[k0 + 1, i0] * (1 - du) * dv
            + h[k0 + 1, i0 + 1] * du * dv
        )


def grid_mesh(name, g, colors, keep=None, drop=0.0):
    """Heightfield grid: vertices at column centres, one quad per 2x2 block, coloured by the min corner."""
    nx, nz, st = g["nx"], g["nz"], g["step"]
    h = np.array(g["heights"], dtype=np.float64).reshape(nz, nx)
    xs = g["x0"] + (np.arange(nx) + 0.5) * st
    zs = g["z0"] + (np.arange(nz) + 0.5) * st
    X, Z = np.meshgrid(xs, zs)
    verts = np.stack([X.ravel(), -Z.ravel(), h.ravel() - drop], axis=1)
    ii, kk = np.meshgrid(np.arange(nx - 1), np.arange(nz - 1))
    ii, kk = ii.ravel(), kk.ravel()
    if keep is not None:
        m = keep(xs[ii] + st / 2, zs[kk] + st / 2)
        ii, kk = ii[m], kk[m]
    a = kk * nx + ii
    # [a, a+1, a+nx+1, a+nx] runs clockwise seen from above (Blender Y = -Roblox Z): reverse so normals face up
    quads = np.stack([a, a + 1, a + nx + 1, a + nx], axis=1)[:, ::-1]
    mats = np.frombuffer(g["materials"].encode(), dtype=np.uint8).reshape(nz, nx)
    codes = mats[kk, ii]
    lut = np.zeros((256, 3))
    for ch, rgb in colors.items():
        lut[ord(ch)] = srgb_to_linear(np.array(rgb) / 255.0)
    rgba = np.concatenate([lut[codes], np.ones((len(codes), 1))], axis=1)
    return build_mesh(
        name,
        verts,
        quads.ravel(),
        np.full(len(quads), 4),
        {"col": ("FLOAT_COLOR", rgba)},
        np.ones(len(quads), dtype=bool),
    )


def water_mesh(name, g, water_y):
    nx, nz, st = g["nx"], g["nz"], g["step"]
    w = np.frombuffer(g["water"].encode(), dtype=np.uint8).reshape(nz, nx) == ord("1")
    kk, ii = np.nonzero(w)
    if len(kk) == 0:
        return None
    x0 = g["x0"] + ii * st
    z0 = g["z0"] + kk * st
    corners = [(0, 0), (st, 0), (st, st), (0, st)]
    verts = np.zeros((len(kk) * 4, 3))
    for c, (dx, dz) in enumerate(corners):
        verts[c::4, 0] = x0 + dx
        verts[c::4, 1] = -(z0 + dz)
        verts[c::4, 2] = water_y
    loops = np.arange(len(kk) * 4).reshape(-1, 4)[:, ::-1].ravel()
    return build_mesh(name, verts, loops, np.full(len(kk), 4), {}, np.ones(len(kk), dtype=bool))


# ----------------------------------------------------------------------------------------------- scene
def build_scene(scene_data, debug):
    templates = make_templates()
    groups = {}
    for p in scene_data["parts"]:
        groups.setdefault(p["g"], []).append(p)
    beams_by_group = {}
    for b in scene_data.get("beams", []):
        beams_by_group.setdefault(b["g"], []).append(b)
    mats = {
        "opaque": material_parts("parts_opaque"),
        "trans": material_parts("parts_transparent", transparent=True),
        "neon": material_neon("parts_neon"),
    }
    for g, plist in groups.items():
        plist = plist + beam_parts(beams_by_group.get(g, []))
        split = {"opaque": [], "trans": [], "neon": []}
        for p in plist:
            if p["m"] == "Neon":
                split["neon"].append(p)
            elif p["t"] > 0.001:
                split["trans"].append(p)
            else:
                split["opaque"].append(p)
        for cls, lst in split.items():
            if lst:
                me = parts_mesh(f"{g}_{cls}", lst, templates)
                link_object(f"{g}_{cls}", me, g, mats[cls])

    terrain = scene_data.get("terrain")
    if terrain:
        tmat = material_terrain("terrain")
        fine, coarse = terrain["fine"], terrain["coarse"]
        link_object("terrain_fine", grid_mesh("terrain_fine", fine, terrain["colors"]), "terrain", tmat)
        fx0, fx1 = fine["x0"], fine["x0"] + fine["nx"] * fine["step"]
        fz0, fz1 = fine["z0"], fine["z0"] + fine["nz"] * fine["step"]
        pad = coarse["step"]

        def outside(x, z):
            return (x < fx0 + pad) | (x > fx1 - pad) | (z < fz0 + pad) | (z > fz1 - pad)

        link_object(
            "terrain_coarse",
            grid_mesh("terrain_coarse", coarse, terrain["colors"], keep=outside, drop=0.3),
            "terrain",
            tmat,
        )
        wmat = material_simple("water", (0.05, 0.16, 0.19), rough=0.05, alpha=0.9)
        for g, nm in ((fine, "water_fine"), (coarse, "water_coarse")):
            me = water_mesh(nm, g, terrain["waterY"] - (0 if g is fine else 0.05))
            if me:
                link_object(nm, me, "terrain", wmat)

    lineup = scene_data.get("lineup")
    if lineup:
        gd = lineup["ground"]
        verts = np.array(
            [
                [gd["minX"], -gd["minZ"], gd["y"]],
                [gd["maxX"], -gd["minZ"], gd["y"]],
                [gd["maxX"], -gd["maxZ"], gd["y"]],
                [gd["minX"], -gd["maxZ"], gd["y"]],
            ]
        )
        me = build_mesh("lineup_ground", verts, np.array([0, 3, 2, 1]), np.array([4]), {}, np.array([False]))
        link_object(
            "lineup_ground",
            me,
            "lineup_ground",
            material_checker("checker", (0.30, 0.38, 0.22), (0.24, 0.31, 0.17)),
        )
        lmat = material_simple("label", (0.02, 0.02, 0.025), rough=0.6)
        for lab in lineup.get("labels", []):
            cu = bpy.data.curves.new(f"label_{lab['text']}", "FONT")
            cu.body = lab["text"]
            cu.align_x = "CENTER"
            cu.size = lab["size"]
            ob = link_object(f"label_{lab['text']}", cu, "lineup_ground", lmat)
            ob.location = rb_to_bl(lab["pos"])

    if debug:
        dbg = [
            {"s": "Block", "pos": [3, 0.5, 0], "size": [6, 1, 1], "c": [220, 40, 40]},  # +X red
            {"s": "Block", "pos": [0, 3.5, 0], "size": [1, 6, 1], "c": [40, 200, 60]},  # +Y green
            {"s": "Block", "pos": [0, 0.5, 3], "size": [1, 1, 6], "c": [40, 80, 230]},  # +Z blue
            {"s": "Wedge", "pos": [-4, 1, 0], "size": [2, 2, 4], "c": [230, 200, 60]},
            {"s": "Cylinder", "pos": [0, 1, -5], "size": [4, 2, 2], "c": [200, 120, 220]},
            {"s": "Ball", "pos": [-4, 1, -5], "size": [2, 2, 2], "c": [240, 240, 240]},
        ]
        for d in dbg:
            d.update({"rot": [1, 0, 0, 0, 1, 0, 0, 0, 1], "t": 0.0, "m": "SmoothPlastic"})
        link_object("debug_axes", parts_mesh("debug_axes", dbg, templates), "debug_axes", mats["opaque"])
        floor = build_mesh(
            "debug_floor",
            np.array([[-12, 12, 0], [12, 12, 0], [12, -12, 0], [-12, -12, 0]], dtype=np.float64),
            np.array([0, 3, 2, 1]),
            np.array([4]),
            {},
            np.array([False]),
        )
        link_object("debug_floor", floor, "debug_axes", material_checker("checker_dbg", (0.5, 0.5, 0.5), (0.4, 0.4, 0.4)))


def setup_world(sun_cfg):
    scene = bpy.context.scene
    world = bpy.data.worlds.new("Sky")
    scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    nodes, links = nt.nodes, nt.links
    bg = nodes.get("Background")
    tc = nodes.new("ShaderNodeTexCoord")
    sep = nodes.new("ShaderNodeSeparateXYZ")
    ramp = nodes.new("ShaderNodeValToRGB")
    links.new(tc.outputs["Generated"], sep.inputs["Vector"])
    links.new(sep.outputs["Z"], ramp.inputs["Fac"])
    # Fac = direction z (Blender up) in [-1, 1]; the ramp reads [0, 1]
    els = ramp.color_ramp.elements
    els[0].position = 0.0
    els[0].color = (0.42, 0.40, 0.34, 1.0)  # below the horizon: warm ground bounce
    els[1].position = 1.0
    els[1].color = (0.20, 0.38, 0.72, 1.0)  # zenith
    e = els.new(0.03)
    e.color = (0.95, 0.80, 0.60, 1.0)  # golden horizon
    e2 = els.new(0.35)
    e2.color = (0.45, 0.62, 0.86, 1.0)
    links.new(ramp.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = sun_cfg.get("skyStrength", 1.0)

    d = sun_cfg.get("dir", [0.7, 0.55, -0.45])  # toward the sun, Roblox axes
    ld = bpy.data.lights.new("Sun", "SUN")
    ld.energy = sun_cfg.get("strength", 3.5)
    ld.color = sun_cfg.get("color", [1.0, 0.86, 0.68])
    ld.angle = math.radians(sun_cfg.get("angleDeg", 1.5))
    sun = bpy.data.objects.new("Sun", ld)
    scene.collection.objects.link(sun)
    to_sun = rb_to_bl(d).normalized()
    sun.rotation_euler = (-to_sun).to_track_quat("-Z", "Y").to_euler()
    sun["review_group"] = "always"


def setup_render(res, samples, threads):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.adaptive_threshold = 0.04
    scene.cycles.use_denoising = True
    try:
        scene.cycles.denoiser = "OPENIMAGEDENOISE"
    except TypeError:
        pass
    scene.cycles.max_bounces = 4
    scene.cycles.diffuse_bounces = 2
    scene.cycles.glossy_bounces = 2
    scene.cycles.transmission_bounces = 2
    scene.cycles.transparent_max_bounces = 8
    scene.cycles.caustics_reflective = False
    scene.cycles.caustics_refractive = False
    scene.render.use_persistent_data = True
    scene.render.threads_mode = "FIXED"
    scene.render.threads = threads
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.image_settings.compression = 50
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass
    cd = bpy.data.cameras.new("Cam")
    cam = bpy.data.objects.new("Cam", cd)
    scene.collection.objects.link(cam)
    scene.camera = cam
    cd.clip_start = 0.05
    cd.clip_end = 30000
    cd.sensor_fit = "VERTICAL"
    cam["review_group"] = "always"
    for ob in bpy.data.objects:
        if ob.type == "FONT":
            con = ob.constraints.new("TRACK_TO")
            con.target = cam
            con.track_axis = "TRACK_Z"
            con.up_axis = "UP_Y"
    return cam


def place_camera(cam, view, ground):
    pos, look = list(view["pos"]), list(view["look"])
    if view.get("aboveGround"):
        pos[1] += ground.at(pos[0], pos[2])
        look[1] += ground.at(look[0], look[2])
    p, q = rb_to_bl(pos), rb_to_bl(look)
    f = (q - p).normalized()
    up = rb_to_bl(view.get("up", [0, 1, 0])).normalized()
    if abs(f.dot(up)) > 0.999:
        up = rb_to_bl([0, 0, 1])  # straight down: the game's North (+Z) at the top
    r = f.cross(up).normalized()
    u = r.cross(f).normalized()
    m = Matrix(((r.x, u.x, -f.x), (r.y, u.y, -f.y), (r.z, u.z, -f.z)))
    cam.matrix_world = Matrix.Translation(p) @ m.to_4x4()
    cam.data.angle_y = math.radians(view.get("fov", 70))
    return pos, look


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--scene", default="build/review/scene.json")
    ap.add_argument("--views", default="tools/review/views.json")
    ap.add_argument("--out", default="build/review")
    ap.add_argument("--only", default="")
    ap.add_argument("--debug", action="store_true", help="also render views marked debug (axes_check)")
    ap.add_argument("--samples", type=int, default=0, help="override every view's samples")
    ap.add_argument("--res", default="")
    ap.add_argument("--threads", type=int, default=2)
    args = ap.parse_args(argv)

    t0 = time.time()
    bpy.ops.wm.read_factory_settings(use_empty=True)
    with open(args.views) as fh:
        vcfg = json.load(fh)
    with open(args.scene) as fh:
        scene_data = json.load(fh)
    t_load = time.time() - t0
    only = [s for s in args.only.split(",") if s]
    views = [v for v in vcfg["views"] if (args.debug or not v.get("debug")) and (not only or v["name"] in only)]
    need_debug = any(v.get("debug") for v in views)

    t1 = time.time()
    build_scene(scene_data, need_debug)
    setup_world(vcfg.get("sun", {}))
    defaults = vcfg.get("defaults", {})
    res = tuple(int(x) for x in (args.res or defaults.get("res", "960x540")).split("x"))
    cam = setup_render(res, defaults.get("samples", 24), args.threads)
    ground = Ground(scene_data.get("terrain", {}).get("fine") if scene_data.get("terrain") else None)
    t_build = time.time() - t1
    print(f"review: scene built in {t_build:.1f}s (json {t_load:.1f}s), {len(bpy.data.objects)} objects", flush=True)

    os.makedirs(args.out, exist_ok=True)
    timing = {"blender": bpy.app.version_string, "load_s": round(t_load, 2), "build_s": round(t_build, 2), "views": []}
    for v in views:
        groups = set(v.get("groups", defaults.get("groups", ["town", "terrain"])))
        groups.add("always")
        for ob in bpy.data.objects:
            ob.hide_render = ob.get("review_group", "always") not in groups
        bpy.context.scene.cycles.samples = args.samples or v.get("samples", defaults.get("samples", 24))
        pos, look = place_camera(cam, v, ground)
        out = os.path.abspath(os.path.join(args.out, f"{v['name']}.png"))
        bpy.context.scene.render.filepath = out
        t = time.time()
        bpy.ops.render.render(write_still=True)
        dt = time.time() - t
        timing["views"].append(
            {
                "name": v["name"],
                "png": out,
                "seconds": round(dt, 2),
                "samples": bpy.context.scene.cycles.samples,
                "camera": [round(c, 2) for c in pos],
                "look": [round(c, 2) for c in look],
            }
        )
        print(f"review: {v['name']:<24} {dt:6.1f}s  {out}", flush=True)
        with open(os.path.join(args.out, "timing.json"), "w") as fh:
            json.dump(timing, fh, indent=2)
    timing["total_s"] = round(time.time() - t0, 2)
    with open(os.path.join(args.out, "timing.json"), "w") as fh:
        json.dump(timing, fh, indent=2)
    print(f"review: {len(views)} views in {timing['total_s']:.1f}s total", flush=True)
    return 0


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    sys.exit(main(argv))
