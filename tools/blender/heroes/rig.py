"""Armatures, skin weights and their checks for the hero animals.

Two armatures share the RigSpec bone names:
  * the EXPORTED armature: every bone points straight up (+Z) with its roll set so its rest matrix is
    M = Blender->Roblox axes. FBX export (axis_forward Z, axis_up Y) maps Blender to Roblox by M, so in
    Roblox every Bone's rest orientation is the identity: Pose.CFrame / Bone.Transform is then exactly
    the spicy-clip/1 delta (axis-aligned joint frame at the bone head), the same numbers the part-built
    puppets' Motor6Ds take. Only the heads matter (joint positions); tails are a fixed short stub.
  * a PROXY armature with anatomical segments (joint -> next joint) used only to compute heat
    (bone-glow) weights, then deleted. Its vertex groups carry over by name.
Weights: at most 4 influences per vertex, normalised, nothing on Root (non-deform, at the origin).
"""
import bpy
import numpy as np
from mathutils import Vector

import bl

STUB = 0.06  # exported bone length (studs); cosmetic


def build_armature(skel, name, stub=STUB):
    arm = bpy.data.armatures.new(name)
    obj = bpy.data.objects.new(name, arm)
    bl.link(obj)
    bl.select_only([obj])
    bpy.ops.object.mode_set(mode="EDIT")
    for bname, head, parent, _tail in skel:
        eb = arm.edit_bones.new(bname)
        eb.head = head
        eb.tail = (head[0], head[1], head[2] + stub)
        eb.align_roll(Vector((0, 1, 0)))
        eb.use_deform = bname != "Root"
        eb.use_connect = False
    for bname, _head, parent, _tail in skel:
        if parent:
            arm.edit_bones[bname].parent = arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    # every rest matrix must be M (so Roblox sees identity rotations)
    worst = 0.0
    for b in arm.bones:
        r = np.array(b.matrix_local.to_3x3())
        worst = max(worst, float(np.abs(r - bl.M_NP).max()))
    assert worst < 1e-5, f"bone rest frames are not axis-aligned in Roblox space (err {worst})"
    return obj


def build_proxy(skel, name="Proxy"):
    arm = bpy.data.armatures.new(name)
    obj = bpy.data.objects.new(name, arm)
    bl.link(obj)
    bl.select_only([obj])
    bpy.ops.object.mode_set(mode="EDIT")
    for bname, head, parent, tail in skel:
        eb = arm.edit_bones.new(bname)
        eb.head = head
        eb.tail = tail
        eb.use_deform = bname != "Root"
    for bname, _head, parent, _tail in skel:
        if parent:
            arm.edit_bones[bname].parent = arm.edit_bones[parent]
    bpy.ops.object.mode_set(mode="OBJECT")
    return obj


def heat_weights(mesh_obj, skel):
    """Bone-heat weights from the anatomical proxy; leaves the vertex groups on mesh_obj."""
    proxy = build_proxy(skel)
    bl.select_only([mesh_obj, proxy], active=proxy)
    bpy.ops.object.parent_set(type="ARMATURE_AUTO")
    # drop the proxy (and its modifier and parenting), keep the groups
    for m in list(mesh_obj.modifiers):
        if m.type == "ARMATURE":
            mesh_obj.modifiers.remove(m)
    mw = mesh_obj.matrix_world.copy()
    mesh_obj.parent = None
    mesh_obj.matrix_world = mw
    bpy.data.objects.remove(proxy)
    return mesh_obj


def weights_np(mesh_obj, bone_names):
    """(N, B) float array of vertex group weights in bone_names order."""
    me = mesh_obj.data
    idx = {g.index: bone_names.index(g.name) for g in mesh_obj.vertex_groups if g.name in bone_names}
    W = np.zeros((len(me.vertices), len(bone_names)), dtype=np.float64)
    for v in me.vertices:
        for g in v.groups:
            j = idx.get(g.group)
            if j is not None:
                W[v.index, j] = g.weight
    return W


def set_weights_np(mesh_obj, W, bone_names, limit=4, floor=0.01):
    """Replace every vertex group by W (N, B): keep the top `limit`, drop < floor, normalise."""
    for g in list(mesh_obj.vertex_groups):
        mesh_obj.vertex_groups.remove(g)
    W = limit_normalise(W, limit, floor)
    groups = [mesh_obj.vertex_groups.new(name=n) for n in bone_names]
    for j, g in enumerate(groups):
        nz = np.nonzero(W[:, j] > 0)[0]
        for i in nz:
            g.add([int(i)], float(W[i, j]), "REPLACE")
    # drop empty groups (Root and any bone that skins nothing here)
    for j, g in reversed(list(enumerate(groups))):
        if not (W[:, j] > 0).any():
            mesh_obj.vertex_groups.remove(g)
    return W


def limit_normalise(W, limit=4, floor=0.01):
    W = np.array(W, dtype=np.float64)
    W[W < floor] = 0.0
    if W.shape[1] > limit:
        order = np.argsort(-W, axis=1)
        drop = order[:, limit:]
        np.put_along_axis(W, drop, 0.0, axis=1)
    s = W.sum(axis=1, keepdims=True)
    return np.where(s > 0, W / np.maximum(s, 1e-12), W)


def smooth_weights(mesh_obj, W, iters=2, alpha=0.5, lock=None):
    """Laplacian smoothing of the weights over mesh edges (lock: boolean mask of vertices to keep)."""
    me = mesh_obj.data
    e = np.empty(len(me.edges) * 2, dtype=np.int64)
    me.edges.foreach_get("vertices", e)
    e = e.reshape(-1, 2)
    n = len(me.vertices)
    deg = np.bincount(e.ravel(), minlength=n).astype(np.float64)
    for _ in range(iters):
        acc = np.zeros_like(W)
        np.add.at(acc, e[:, 0], W[e[:, 1]])
        np.add.at(acc, e[:, 1], W[e[:, 0]])
        avg = acc / np.maximum(deg, 1)[:, None]
        Wn = W * (1 - alpha) + avg * alpha
        if lock is not None:
            Wn[lock] = W[lock]
        W = Wn
    return W


def bind(mesh_obj, arm_obj):
    mod = mesh_obj.modifiers.new("Armature", "ARMATURE")
    mod.object = arm_obj
    mesh_obj.parent = arm_obj
    return mod


def check_weights(mesh_obj, root="Root"):
    me = mesh_obj.data
    max_inf = 0
    unweighted = 0
    bad_sum = 0
    for v in me.vertices:
        gs = [g for g in v.groups if g.weight > 0]
        max_inf = max(max_inf, len(gs))
        s = sum(g.weight for g in gs)
        if not gs:
            unweighted += 1
        elif abs(s - 1) > 1e-3:
            bad_sum += 1
    root_w = mesh_obj.vertex_groups.get(root)
    return {
        "verts": len(me.vertices),
        "max_influences": max_inf,
        "unweighted": unweighted,
        "not_normalised": bad_sum,
        "root_group": root_w is not None,
    }
