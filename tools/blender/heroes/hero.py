"""The hero pipeline after the sculpt: hard parts, weights, regions, UVs, the exported armature,
textures, eyes, fur cards, blood, RootPart, clips, FBX export and the report (see build_hero.py)."""
import json
import os

import bpy
import numpy as np

import bl
import geometry
import rig

FBX_KW = dict(
    use_selection=True,
    object_types={"ARMATURE", "MESH"},
    axis_forward="Z",
    axis_up="Y",
    apply_unit_scale=True,
    apply_scale_options="FBX_SCALE_ALL",
    add_leaf_bones=False,
    use_armature_deform_only=False,
    bake_anim=False,
    path_mode="COPY",
    embed_textures=True,
    mesh_smooth_type="FACE",
    use_mesh_modifiers=False,
)


def face_centroids_normals(obj):
    me = obj.data
    n = len(me.polygons)
    c = np.empty(n * 3, dtype=np.float32)
    me.polygons.foreach_get("center", c)
    nn = np.empty(n * 3, dtype=np.float32)
    me.polygons.foreach_get("normal", nn)
    return c.reshape(-1, 3), nn.reshape(-1, 3)


def dominant_bone(W, bone_names):
    return np.array(bone_names)[np.argmax(W, axis=1)]


def add_hard_parts(sp, variant, lo, bone_names):
    parts = sp.hard_parts(variant)
    objs = []
    for name, v, f, bone, kind in parts:
        o = bl.mesh_from_arrays(name, v, f, smooth=True)
        g = o.vertex_groups.new(name=bone)
        g.add(list(range(len(o.data.vertices))), 1.0, "REPLACE")
        o["kind"] = kind
        objs.append(o)
    # kind per face survives the join as a face attribute
    for o in objs:
        a = o.data.attributes.new("hard_kind", "INT", "FACE")
        a.data.foreach_set("value", np.full(len(o.data.polygons), 1 if o["kind"] == "claw" else 2, dtype=np.int32))
    a = lo.data.attributes.new("hard_kind", "INT", "FACE")
    a.data.foreach_set("value", np.zeros(len(lo.data.polygons), dtype=np.int32))
    geometry.join_into(lo, objs)
    import bmesh

    bm = bmesh.new()
    bm.from_mesh(lo.data)
    bmesh.ops.triangulate(bm, faces=[f for f in bm.faces if len(f.verts) > 4])
    bm.to_mesh(lo.data)
    bm.free()
    return len(parts)


def assign_regions(lo, field_fn, W, bone_names):
    """Material 0 Body, 1 Pattern by the species' pattern field at face centres."""
    c, n = face_centroids_normals(lo)
    me = lo.data
    # dominant bone per face from its first vertex (good enough for region rules)
    fv = np.empty(len(me.polygons), dtype=np.int64)
    me.polygons.foreach_get("loop_start", fv)
    lv = np.empty(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", lv)
    dom = dominant_bone(W, bone_names)[lv[fv]]
    kind = np.empty(len(me.polygons), dtype=np.int32)
    me.attributes["hard_kind"].data.foreach_get("value", kind)
    pat = field_fn(c, n, dom)
    mi = np.where((pat > 0.5) & (kind == 0), 1, 0).astype(np.int32)
    for name in ("Body", "Pattern"):
        m = bpy.data.materials.get(name) or bpy.data.materials.new(name)
        me.materials.append(m)
    me.polygons.foreach_set("material_index", mi)
    return int(mi.sum())


PARTS = ["torso", "head", "earL", "earR", "tail", "FrontL", "FrontR", "BackL", "BackR"]


def bone_part(name):
    if name.startswith("Tail"):
        return "tail"
    if name in ("Head", "Jaw"):
        return "head"
    if name == "EarL":
        return "earL"
    if name == "EarR":
        return "earR"
    for leg in ("FrontL", "FrontR", "BackL", "BackR"):
        if name.startswith(leg + "_"):
            return leg
    return "torso"


def quadruped_uv(lo, W, bone_names):
    """Part-based seams for any of the RigSpec quadrupeds: a cut along the belly from the throat to
    the tail root, down the inside of each leg, under the tail; head and ears unwrap as domes."""
    me = lo.data
    part_of_bone = np.array([PARTS.index(bone_part(b)) for b in bone_names])
    vpart = part_of_bone[np.argmax(W, axis=1)]
    kind = np.empty(len(me.polygons), dtype=np.int32)
    me.attributes["hard_kind"].data.foreach_get("value", kind)
    fl = []
    for p in me.polygons:
        vs = [vpart[i] for i in p.vertices]
        fl.append(max(set(vs), key=vs.count))
    fl = np.array(fl)
    fl[kind > 0] = -1
    fl = geometry.smooth_labels(lo, fl)
    vsets = [set() for _ in me.vertices]
    for p in me.polygons:
        for i in p.vertices:
            vsets[i].add(int(fl[p.index]))
    P = {n: i for i, n in enumerate(PARTS)}

    def ring(of, touching, low_frac=None):
        def fn(ids, co, nv, bnd):
            m = np.array([of in vsets[i] and touching in vsets[i] for i in ids])
            if low_frac is not None and m.any():
                z = co[m, 2]
                m &= co[:, 2] <= np.quantile(z, low_frac)
            return m
        return fn

    def lowest(frac):
        def fn(ids, co, nv, bnd):
            return co[:, 2] <= np.quantile(co[:, 2], frac)
        return fn

    def farthest_back(ids, co, nv, bnd):
        return co[:, 1] >= np.quantile(co[:, 1], 0.995)

    def ventral(co, nv):
        width = max(np.ptp(co[:, 0]), 1e-3)
        return 1 + 6 * np.maximum(0, nv[:, 2] + 0.3) + 10 * np.abs(co[:, 0]) / width

    def inner(co, nv):
        side = np.sign(np.mean(co[:, 0])) or 1.0
        inward = -side * nv[:, 0]
        return 1 + 6 * np.maximum(0, 0.6 - inward)

    cuts = [(P["torso"], ring(P["torso"], P["head"], 0.3), ring(P["torso"], P["tail"], 0.5), ventral)]
    for leg in ("FrontL", "FrontR", "BackL", "BackR"):
        cuts.append((P[leg], ring(P[leg], P["torso"]), lowest(0.02), inner))
    cuts.append((P["tail"], ring(P["tail"], P["torso"], 0.5), farthest_back, ventral))
    return geometry.unwrap_parts(lo, fl, cuts)


def separate_pattern(lo):
    """Split material 1 into its own object named Pattern; lo becomes Body."""
    me = lo.data
    mi = np.empty(len(me.polygons), dtype=np.int32)
    me.polygons.foreach_get("material_index", mi)
    assert (mi == 1).any(), "no Pattern faces"
    bl.select_only([lo])
    me.vertices.foreach_set("select", np.zeros(len(me.vertices), dtype=bool))
    me.edges.foreach_set("select", np.zeros(len(me.edges), dtype=bool))
    me.polygons.foreach_set("select", mi == 1)
    bpy.ops.object.mode_set(mode="EDIT")
    bpy.ops.mesh.select_mode(type="FACE")
    bpy.ops.mesh.separate(type="SELECTED")
    bpy.ops.object.mode_set(mode="OBJECT")
    pat = [o for o in bpy.context.selected_objects if o is not lo][0]
    pat.name = "Pattern"
    pat.data.name = "Pattern"
    lo.name = "Body"
    lo.data.name = "Body"
    return lo, pat


def root_part(sp):
    c, half = sp.ROOT_PART
    v, f = geometry.box_part(c, half)
    o = bl.mesh_from_arrays("RootPart", v, f, smooth=False)
    m = bpy.data.materials.new("RootPart")
    o.data.materials.append(m)
    return o


def export_fbx(path, objs):
    bl.select_only(objs)
    bpy.ops.export_scene.fbx(filepath=path, **FBX_KW)
    return os.path.getsize(path)


def finish(sp, variant, skel, bone_names, body, hi, lo, opts, log):
    out = opts.out
    report = {"species": sp.SPECIES, "variant": variant, "blender": bpy.app.version_string}
    # weights on the sculpted body first (heat needs one connected surface), then the hard parts
    rig.heat_weights(lo, skel)
    W = rig.weights_np(lo, bone_names)
    W = rig.smooth_weights(lo, W, iters=2, alpha=0.4)
    W = rig.set_weights_np(lo, W, bone_names)
    log(f"heat weights on {len(lo.data.vertices)} verts")
    nh = add_hard_parts(sp, variant, lo, bone_names)
    W = rig.weights_np(lo, bone_names)
    log(f"{nh} hard parts joined; body now {bl.tri_count(lo.data)} tris")
    npat = assign_regions(lo, lambda c, n, dom: sp.pattern_field(c, n, dom, variant), W, bone_names)
    log(f"pattern faces {npat}")
    nseam = quadruped_uv(lo, W, bone_names)
    log(f"uv unwrapped ({nseam} part-boundary seam edges)")
    arm = rig.build_armature(skel, "Rig")
    rig.bind(lo, arm)
    import textures  # noqa: E402

    tex = textures.paint_body(sp, variant, lo, hi, W, bone_names, opts, log)
    report["textures"] = tex
    import parts  # noqa: E402

    extra = parts.build(sp, variant, lo, arm, W, bone_names, opts, log)
    body_obj, pat_obj = separate_pattern(lo)
    # no RootPart mesh: the importer makes a Part named RootPart for the bone tree (probe, 2026-11-09)
    bpy.data.objects.remove(hi)
    meshes = [body_obj, pat_obj] + extra
    report["regions"] = {o.name: bl.tri_count(o.data) for o in meshes}
    report["weights"] = {o.name: rig.check_weights(o) for o in meshes if o.vertex_groups}
    report["bones"] = len(arm.data.bones)
    import clips  # noqa: E402

    report["clips"] = clips.author_all(sp, variant, arm, skel, opts, log)
    fbx = os.path.join(out, f"{variant}.fbx")
    for o in meshes:
        o.data.materials[0] if o.data.materials else None
    report["fbx"] = {"path": fbx, "bytes": export_fbx(fbx, [arm] + meshes)}
    log(f"fbx {report['fbx']['bytes']} bytes")
    clips_meta = report["clips"] if isinstance(report["clips"], dict) else {}
    meta = {
        "variant": variant,
        "species": sp.SPECIES,
        "size": getattr(sp, "SCALE", 1.0),
        "center": list(getattr(sp, "VIEW_CENTER", (0, 0.3, 0.85))),
        "tints": dict(tex.get("tint", {})),
        "glow": variant == "rodent",
        "clips": {k: v for k, v in clips_meta.items() if isinstance(v, dict) and "key_frames" in v},
        "turntable_pose": ["Idle", 1] if "Idle" in clips_meta else None,
    }
    bpy.context.scene["hero_meta"] = json.dumps(meta)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, f"{variant}.blend"))
    return report
