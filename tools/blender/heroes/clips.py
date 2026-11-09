"""Clip authoring for the hero rigs: a small quadruped pose engine and the spicy-clip/1 writer.

Every pose is a dict bone -> (R 3x3, t 3) of LOCAL deltas in the axis-aligned joint frame at the bone
head, in Blender axes (+Z up, front -Y, left +X). That is exactly what tools/blender/export_art.py
calls the clip convention after the M conjugation, and (because the exported bones arrive in Roblox
with identity rest rotations, rig.py) exactly Bone.Transform / Motor6D.Transform in the engine.

Pieces:
  Rig.fk(D)                    world joint frames
  body(D, ...)                 whole-body bob/pitch/roll/yaw about a pivot, carried by Root
  spine(D, arch, bend, twist)  spread over Hips..Chest so the hind and fore quarters counter-rotate
  Rig.leg(D, W, leg, target)   analytic IK: hip/shoulder -> knee/elbow (pole) -> hock/wrist -> toe
  look(D, W, R_target, ...)    neck and head share the rotation that puts the head at R_target
  tail(D, pitches, yaws)       a chain of local rotations (lagged waves come from the clip)
Clips are pure functions of time (loops close exactly: the closing key equals the first).
"""
import json
import math
import os

import bpy
import numpy as np
from mathutils import Matrix

import bl
import rig as rigmod

I3 = np.eye(3)


def Rx(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[1, 0, 0], [0, c, -s], [0, s, c]])


def Ry(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, 0, s], [0, 1, 0], [-s, 0, c]])


def Rz(a):
    c, s = math.cos(a), math.sin(a)
    return np.array([[c, -s, 0], [s, c, 0], [0, 0, 1]])


def unit(v):
    v = np.asarray(v, float)
    n = np.linalg.norm(v)
    return v / n if n > 1e-12 else v


def axis_angle(R):
    ang = math.acos(max(-1.0, min(1.0, (np.trace(R) - 1) / 2)))
    if ang < 1e-9:
        return np.array([1.0, 0, 0]), 0.0
    ax = np.array([R[2, 1] - R[1, 2], R[0, 2] - R[2, 0], R[1, 0] - R[0, 1]])
    n = np.linalg.norm(ax)
    if n < 1e-9:  # 180 degrees
        w, v = np.linalg.eigh((R + I3) / 2)
        return v[:, np.argmax(w)], ang
    return ax / n, ang


def rot_axis(ax, ang):
    ax = unit(ax)
    K = np.array([[0, -ax[2], ax[1]], [ax[2], 0, -ax[0]], [-ax[1], ax[0], 0]])
    return I3 + math.sin(ang) * K + (1 - math.cos(ang)) * K @ K


def frac(R, f):
    ax, ang = axis_angle(R)
    return rot_axis(ax, ang * f)


def smooth(x):
    x = min(max(x, 0.0), 1.0)
    return x * x * (3 - 2 * x)


def ease_io(x):
    x = min(max(x, 0.0), 1.0)
    return 0.5 - 0.5 * math.cos(math.pi * x)


class Rig:
    def __init__(self, skel):
        self.skel = skel
        self.names = [b[0] for b in skel]
        self.head = {b[0]: np.array(b[1], float) for b in skel}
        self.parent = {b[0]: b[2] for b in skel}
        self.ptail = {b[0]: np.array(b[3], float) for b in skel}

    def identity(self):
        return {n: [I3.copy(), np.zeros(3)] for n in self.names}

    def fk(self, D):
        W = {}
        for n in self.names:  # skeleton order is parent-first
            R, t = D[n]
            p = self.parent[n]
            if p is None:
                W[n] = (R, self.head[n] + t)
            else:
                Rp, pp = W[p]
                W[n] = (Rp @ R, pp + Rp @ (self.head[n] - self.head[p]) + Rp @ t)
        return W

    def leg(self, D, W, leg, toe_target, foot_pitch, toe_pitch, pole, plane_hint=None):
        """IK for <leg>_Upper..Toe. toe_target: world position of the Toe joint (ball of the foot or
        the knuckles); foot_pitch/toe_pitch: radians below the in-plane forward horizontal (> pi/2
        points back); pole: the direction the knee (hind) or elbow (front) points."""
        U, L, F, T = (f"{leg}_{s}" for s in ("Upper", "Lower", "Foot", "Toe"))
        par = self.parent[U]
        Rp, pp = W[par]
        hip = pp + Rp @ (self.head[U] - self.head[par])
        l1 = np.linalg.norm(self.head[L] - self.head[U])
        l2 = np.linalg.norm(self.head[F] - self.head[L])
        l3 = np.linalg.norm(self.head[T] - self.head[F])
        l4 = np.linalg.norm(self.ptail[T] - self.head[T])
        T_ = np.asarray(toe_target, float)
        n = unit(np.cross(T_ - hip, pole))
        fwd = np.array([0, -1.0, 0]) if plane_hint is None else np.asarray(plane_hint, float)
        fwd = unit(fwd - (fwd @ n) * n)
        down = unit(np.cross(n, fwd))
        if down[2] > 0:
            down = -down
        uf = math.cos(foot_pitch) * fwd + math.sin(foot_pitch) * down
        ut = math.cos(toe_pitch) * fwd + math.sin(toe_pitch) * down
        F_ = T_ - l3 * uf
        E_ = T_ + l4 * ut
        d_vec = F_ - hip
        d = np.linalg.norm(d_vec)
        dmax, dmin = (l1 + l2) * 0.999, abs(l1 - l2) * 1.01 + 1e-4
        if d > dmax or d < dmin:
            d = min(max(d, dmin), dmax)
            F_ = hip + unit(d_vec) * d
            T_ = F_ + l3 * uf
            E_ = T_ + l4 * ut
        e = unit(F_ - hip)
        q = unit(pole - (pole @ e) * e)
        a = (l1 * l1 - l2 * l2 + d * d) / (2 * d)
        h = math.sqrt(max(l1 * l1 - a * a, 0.0))
        K_ = hip + a * e + h * q
        # rest bend normal with the same construction as the posed one
        rest_pts = [self.head[U], self.head[L], self.head[F], self.head[T], self.ptail[T]]
        n0 = unit(np.cross(rest_pts[3] - rest_pts[0], pole_rest(leg)))
        posed = [hip, K_, F_, T_, E_]
        Rw = []
        for i in range(4):
            r = unit(rest_pts[i + 1] - rest_pts[i])
            v = unit(posed[i + 1] - posed[i])
            nr = unit(n0 - (n0 @ r) * r)
            nv = unit(n - (n @ v) * v)
            Fr = np.stack([r, nr, np.cross(r, nr)], 1)
            Fp = np.stack([v, nv, np.cross(v, nv)], 1)
            Rw.append(Fp @ Fr.T)
        D[U][0] = Rp.T @ Rw[0]
        D[L][0] = Rw[0].T @ Rw[1]
        D[F][0] = Rw[1].T @ Rw[2]
        D[T][0] = Rw[2].T @ Rw[3]
        return posed


def pole_rest(leg):
    # knees point forward, elbows back; the plane normal is built from this the same way at rest
    return np.array([0, -1.0, 0.25]) if leg.startswith("Back") else np.array([0, 1.0, 0.0])


def body(D, pivot, bob=0.0, pitch=0.0, roll=0.0, yaw=0.0, surge=0.0, sway=0.0):
    """Root carries the whole body: rotation about `pivot` (pitch + = nose down) plus offsets."""
    R = Rz(yaw) @ Rx(pitch) @ Ry(roll)
    c = np.asarray(pivot, float)
    D["Root"] = [R, c - R @ c + np.array([sway, surge, bob])]


def spine(D, names, arch=0.0, bend=0.0, twist=0.0):
    """arch + = back rounds up (hindquarters and forequarters both tip down); bend + = toward the
    left (+X) side; twist rolls the forequarters. The first bone takes -1/2, the rest share +1."""
    first, rest = names[0], names[1:]
    k = 1.0 / len(rest)
    D[first][0] = D[first][0] @ Rz(-bend * 0.5) @ Rx(-arch * 0.5)
    for n in rest:
        D[n][0] = D[n][0] @ Rz(bend * k) @ Rx(arch * k) @ Ry(twist * k)


def look(D, rig, W, chain, R_target, weights=None):
    """Turn the chain (e.g. Neck, Head) so its last bone ends at the world orientation R_target; bone k
    takes the cumulative fraction w1 + .. + wk of the needed world rotation (one axis, so they add)."""
    par = rig.parent[chain[0]]
    Rp = W[par][0]
    old = []
    run = Rp
    for n in chain:
        run = run @ D[n][0]
        old.append(run)
    delta = R_target @ old[-1].T
    weights = weights or [1.0 / len(chain)] * len(chain)
    cum = 0.0
    prev = Rp
    for n, w, Wo in zip(chain, weights, old):
        cum += w
        Wn = frac(delta, cum) @ Wo
        D[n][0] = prev.T @ Wn
        prev = Wn
    return D


def tail(D, prefix, n, pitches, yaws, rolls=None):
    for i in range(n):
        R = Rz(yaws[i]) @ Rx(pitches[i])
        if rolls is not None:
            R = R @ Ry(rolls[i])
        D[f"{prefix}{i + 1}"][0] = D[f"{prefix}{i + 1}"][0] @ R


# ---- output -----------------------------------------------------------------------------------------

M = bl.M_NP


def r6(v):
    return round(float(v), 6) + 0.0


def to_roblox(R, t):
    Rr = M @ R @ M.T
    tr = M @ t
    return [r6(tr[0]), r6(tr[1]), r6(tr[2])] + [r6(Rr[i][j]) for i in range(3) for j in range(3)]


def write_clip(path, rig_id, clip, skel, frames, fps, loop, priority, markers=()):
    """frames: list of pose dicts for frames 0..n-1. Loops get one closing key equal to the first."""
    bones = []
    for name, head, parent, ptail in skel:
        bones.append({
            "name": name,
            "parent": parent,
            "deform": name != "Root",
            "head": [r6(c) for c in M @ np.array(head)],
            "tail": [r6(c) for c in M @ np.array(ptail)],
            "restRotation": [1, 0, 0, 0, 1, 0, 0, 0, 1],
        })
    kfs = []
    for i, D in enumerate(frames):
        kfs.append({"time": r6(i / fps), "frame": i, "poses": {n: to_roblox(R, t) for n, (R, t) in D.items()}})
    if loop:
        kfs.append({"time": r6(len(frames) / fps), "frame": len(frames), "poses": kfs[0]["poses"]})
    doc = {
        "format": "spicy-clip/1",
        "rig": rig_id,
        "clip": clip,
        "fps": fps,
        "loop": bool(loop),
        "priority": priority,
        "rootPart": "RootPart",
        "frameConvention": "joint-local delta, axis-aligned joint frame at the bone head, Roblox axes (-Z forward, +Y up), studs; skinned bones arrive with identity rest rotation",
        "bones": bones,
        "keyframes": kfs,
        "markers": [{"time": r6(t), "name": nm, "value": v} for t, nm, v in markers],
    }
    with open(path, "w") as fh:
        json.dump(doc, fh, separators=(",", ":"))
    return {"keyframes": len(kfs), "duration": kfs[-1]["time"], "loop": bool(loop)}


def key_action(arm, name, frames, loop):
    """The same poses as a Blender action (for review renders and the .blend)."""
    R0 = rigmod.R_EXPORT
    act = bpy.data.actions.new(name)
    act.use_fake_user = True
    if arm.animation_data is None:
        arm.animation_data_create()
    arm.animation_data.action = act
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
    prev = {}
    seq = list(frames) + ([frames[0]] if loop else [])
    for i, D in enumerate(seq):
        f = i + 1
        for pb in arm.pose.bones:
            R, t = D[pb.name]
            Rb = R0.T @ R @ R0
            tb = R0.T @ t
            mb = Matrix([list(Rb[0]) + [tb[0]], list(Rb[1]) + [tb[1]], list(Rb[2]) + [tb[2]], [0, 0, 0, 1]])
            pb.matrix_basis = mb
            q = pb.rotation_quaternion.copy()
            if pb.name in prev and prev[pb.name].dot(q) < 0:
                q.negate()
                pb.rotation_quaternion = q
            prev[pb.name] = q
            pb.keyframe_insert("rotation_quaternion", frame=f)
            pb.keyframe_insert("location", frame=f)
    return act


def author_all(sp, variant, arm, skel, opts, log):
    """Author every clip the species module lists, write JSON, key actions; returns the clip report."""
    import importlib

    mod = importlib.import_module(sp.CLIPS_MODULE)
    rig = Rig(skel)
    out_dir = os.path.join(opts.out, "clips")
    os.makedirs(out_dir, exist_ok=True)
    report = {}
    if variant in getattr(sp, "CLIPS_FROM_OTHER", {}):
        return {"shared_with": sp.CLIPS_FROM_OTHER[variant]}
    for spec in mod.clips(rig, sp, variant):
        name = spec["name"]
        frames = [spec["pose"](i, spec["frames"]) for i in range(spec["frames"])]
        path = os.path.join(out_dir, f"{sp.RIG_ID}_{name}.clip.json")
        info = write_clip(path, sp.RIG_ID, name, skel, frames, spec.get("fps", 30), spec["loop"], spec["priority"], spec.get("markers", ()))
        key_action(arm, name, frames, spec["loop"])
        info.update({
            "path": path,
            "key_frames": [k + 1 for k in spec.get("keys", [0, spec["frames"] // 4, spec["frames"] // 2, 3 * spec["frames"] // 4])],
            "view": spec.get("view", [-62, 8]),
            "brief": spec.get("brief", name),
            "nominalSpeed": spec.get("nominal_speed"),
            "markers": [list(m) for m in spec.get("markers", ())],
        })
        if "center" in spec:
            info["center"] = list(spec["center"])
        if "dist" in spec:
            info["dist"] = spec["dist"]
        report[name] = info
        log(f"clip {name}: {info['keyframes']} keys, {info['duration']} s, loop={spec['loop']}")
    if arm.animation_data:
        arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.matrix_basis.identity()
    return report
