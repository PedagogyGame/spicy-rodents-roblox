"""Poses of a hero rig for the motion preview: numpy only (no bpy), in ROBLOX axes and studs
(+X right, +Y up, -Z ahead), which is the frame the game works in and the takes are written in
(tools/review/motion/Path.luau).

  clips = load_clips("build/heroes/squirrel/clips")      the exported spicy-clip/1 JSON (what is uploaded)
  rig = Rig(clips["Run"].doc["bones"])                   bone tree and joint positions at rest
  pose = frame_pose(clips, frame)                        the take frame's tracks blended, layers applied
  W = rig.fk(pose)                                       joint frames in the model's own space
  world = body_point(frame, W["Head"][1])                ... and in the world of the take

A pose is {bone: (R 3x3, t 3)}: the joint's local delta in its axis-aligned frame at the bone head, exactly
Bone.Transform in the engine (every bone's rest rotation is the identity, rig.py). The game multiplies a
layer onto it as Bone.Transform = pose * CFrame.Angles(rx, ry, rz).

Blending follows the Animator for tracks of one priority: weights that sum to 1 mix the poses; a sum
short of 1 leaves that share of the rest pose showing; a sum over 1 is scaled down.
"""
import glob
import json
import math
import os

import numpy as np

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


def angles(rx, ry, rz):
    """CFrame.Angles(rx, ry, rz) as a matrix: the rotations applied in Z, Y, X order."""
    return Rx(rx) @ Ry(ry) @ Rz(rz)


def quat(R):
    """Unit quaternion (w, x, y, z) of a rotation matrix."""
    t = R[0, 0] + R[1, 1] + R[2, 2]
    if t > 0:
        s = math.sqrt(t + 1.0) * 2
        q = [0.25 * s, (R[2, 1] - R[1, 2]) / s, (R[0, 2] - R[2, 0]) / s, (R[1, 0] - R[0, 1]) / s]
    elif R[0, 0] > R[1, 1] and R[0, 0] > R[2, 2]:
        s = math.sqrt(1.0 + R[0, 0] - R[1, 1] - R[2, 2]) * 2
        q = [(R[2, 1] - R[1, 2]) / s, 0.25 * s, (R[0, 1] + R[1, 0]) / s, (R[0, 2] + R[2, 0]) / s]
    elif R[1, 1] > R[2, 2]:
        s = math.sqrt(1.0 + R[1, 1] - R[0, 0] - R[2, 2]) * 2
        q = [(R[0, 2] - R[2, 0]) / s, (R[0, 1] + R[1, 0]) / s, 0.25 * s, (R[1, 2] + R[2, 1]) / s]
    else:
        s = math.sqrt(1.0 + R[2, 2] - R[0, 0] - R[1, 1]) * 2
        q = [(R[1, 0] - R[0, 1]) / s, (R[0, 2] + R[2, 0]) / s, (R[1, 2] + R[2, 1]) / s, 0.25 * s]
    q = np.array(q, dtype=np.float64)
    return q / np.linalg.norm(q)


def mat(q):
    w, x, y, z = q / np.linalg.norm(q)
    return np.array([
        [1 - 2 * (y * y + z * z), 2 * (x * y - z * w), 2 * (x * z + y * w)],
        [2 * (x * y + z * w), 1 - 2 * (x * x + z * z), 2 * (y * z - x * w)],
        [2 * (x * z - y * w), 2 * (y * z + x * w), 1 - 2 * (x * x + y * y)],
    ])


def slerp(Ra, Rb, u):
    """The rotation a fraction u of the way from Ra to Rb (what the engine shows between two keys of a
    clip uploaded with linear easing)."""
    qa, qb = quat(Ra), quat(Rb)
    d = float(qa @ qb)
    if d < 0:
        qb, d = -qb, -d
    if d > 0.99995:
        return mat(qa * (1 - u) + qb * u)
    th = math.acos(min(d, 1.0))
    return mat((math.sin((1 - u) * th) * qa + math.sin(u * th) * qb) / math.sin(th))


def mix_rotations(Rs, ws):
    """The weighted mean rotation (quaternions on one hemisphere, summed and normalised)."""
    if len(Rs) == 1:
        return Rs[0]
    q0 = quat(Rs[0])
    acc = q0 * ws[0]
    for R, w in zip(Rs[1:], ws[1:]):
        q = quat(R)
        if q @ q0 < 0:
            q = -q
        acc = acc + q * w
    return mat(acc)


class Clip:
    """One exported clip: keys every 1/fps seconds; a loop's closing key equals its first. Between two
    keys the pose moves in a straight line (tools/anim/KeyframeBuilder uploads every Pose with
    PoseEasingStyle.Linear)."""

    def __init__(self, doc):
        self.doc = doc
        self.name = doc["clip"]
        self.fps = float(doc.get("fps", 30))
        self.loop = bool(doc.get("loop"))
        kfs = doc["keyframes"]
        self.times = np.array([k["time"] for k in kfs], dtype=np.float64)
        self.length = float(self.times[-1])
        self.bones = [b["name"] for b in doc["bones"]]
        self.T = {}
        self.R = {}
        for b in self.bones:
            rows = np.array([k["poses"][b] for k in kfs], dtype=np.float64)
            self.T[b] = rows[:, 0:3]
            self.R[b] = rows[:, 3:12].reshape(-1, 3, 3)

    def at(self, time):
        """The seconds into the clip as the Animator holds them: a loop wraps, a one-shot stops at its end."""
        if self.loop:
            return time % self.length
        return min(max(time, 0.0), self.length)

    def sample(self, time):
        time = self.at(time)
        n = len(self.times)
        f = time * self.fps
        i0 = min(int(math.floor(f + 1e-9)), n - 1)
        i1 = min(i0 + 1, n - 1)
        a = min(max(f - i0, 0.0), 1.0)
        pose = {}
        for b in self.bones:
            t = self.T[b][i0] * (1 - a) + self.T[b][i1] * a
            if a < 1e-9 or i0 == i1:
                R = self.R[b][i0]
            else:
                R = slerp(self.R[b][i0], self.R[b][i1], a)
            pose[b] = (R, t)
        return pose


def load_clips(directory, rig_id=None):
    """{clip name: Clip} from <directory>/<rig>_<Clip>.clip.json."""
    out = {}
    for path in sorted(glob.glob(os.path.join(directory, "*.clip.json"))):
        with open(path) as fh:
            doc = json.load(fh)
        if rig_id is None or doc.get("rig") == rig_id:
            out[doc["clip"]] = Clip(doc)
    if not out:
        raise SystemExit(f"no clips in {directory} (build the hero first: tools/blender/heroes/build_hero.py)")
    return out


class Rig:
    def __init__(self, bones):
        self.names = [b["name"] for b in bones]  # parent first
        self.parent = {b["name"]: b["parent"] for b in bones}
        self.head = {b["name"]: np.array(b["head"], dtype=np.float64) for b in bones}
        self.tail = {b["name"]: np.array(b["tail"], dtype=np.float64) for b in bones}

    def rest(self):
        return {n: (I3, np.zeros(3)) for n in self.names}

    def fk(self, pose):
        """{bone: (R, p)}: each joint's frame in the model's space (the SkinRoot's)."""
        W = {}
        for n in self.names:
            R, t = pose[n]
            p = self.parent[n]
            if p is None:
                W[n] = (R, self.head[n] + t)
            else:
                Rp, pp = W[p]
                W[n] = (Rp @ R, pp + Rp @ (self.head[n] - self.head[p]) + Rp @ t)
        return W

    def tip(self, W, bone):
        """Where the bone's anatomical segment ends (toe tips, tail tip), posed."""
        R, p = W[bone]
        return p + R @ (self.tail[bone] - self.head[bone])


def blend(poses, weights, names):
    """Mix whole poses by weight (see the module note on sums short of or over 1)."""
    total = sum(weights)
    if total > 1.0:
        weights = [w / total for w in weights]
        total = 1.0
    if len(poses) == 1 and abs(total - 1.0) < 1e-6:
        return dict(poses[0])
    rest_w = max(0.0, 1.0 - total)
    out = {}
    for b in names:
        Rs = [p[b][0] for p in poses]
        ts = [p[b][1] for p in poses]
        ws = list(weights)
        if rest_w > 1e-9:
            Rs.append(I3)
            ts.append(np.zeros(3))
            ws.append(rest_w)
        order = np.argsort(ws)[::-1]
        Rs = [Rs[i] for i in order]
        ws = [ws[i] for i in order]
        ts = [ts[i] for i in order]
        out[b] = (mix_rotations(Rs, ws), sum(t * w for t, w in zip(ts, ws)))
    return out


def apply_layers(pose, layers):
    """Bone.Transform = pose * CFrame.Angles(rx, ry, rz) for every layered bone."""
    if not layers:
        return pose
    out = dict(pose)
    for bone, r in layers.items():
        if bone in out:
            R, t = out[bone]
            out[bone] = (R @ angles(r[0], r[1], r[2]), t)
    return out


def frame_pose(clips, frame, sampler=None, layers=True):
    """The pose a take frame shows: its tracks blended, then its layers. `sampler(clip name, seconds)`
    replaces the JSON clips (render_motion.py passes the .blend's actions)."""
    names = next(iter(clips.values())).bones
    sample = sampler or (lambda name, time: clips[name].sample(time))
    poses = [sample(tr["clip"], tr["time"]) for tr in frame["tracks"]]
    pose = blend(poses, [tr["weight"] for tr in frame["tracks"]], names)
    if layers:
        pose = apply_layers(pose, frame.get("layers") or {})
    return pose


def body_frame(frame):
    """(R, p): the drawn body's rotation and its feet point (the model's origin) in the world."""
    R = np.array(frame["rot"], dtype=np.float64).reshape(3, 3)
    p = np.array([frame["pos"]["x"], frame["pos"]["y"], frame["pos"]["z"]], dtype=np.float64)
    return R, p


def body_rotation(yaw, pitch, roll):
    """CFrame.Angles(0, yaw, 0) * CFrame.Angles(pitch, 0, roll): how a take frame's `rot` is made."""
    return Ry(yaw) @ angles(pitch, 0.0, roll)


def body_point(frame, p):
    R, o = body_frame(frame)
    return o + R @ np.asarray(p, dtype=np.float64)


def lerp_frames(a, b, u):
    """A frame between two consecutive take frames (u in [0, 1]): positions, the body's rotation, track
    times and weights and layer angles move in straight lines. Tracks are matched by clip; a loop that
    wrapped between the two frames is unwrapped first."""
    if u <= 0:
        return a
    if u >= 1:
        return b
    out = dict(b)
    out["t"] = a["t"] + (b["t"] - a["t"]) * u
    for key in ("pos", "root", "cam", "focus"):
        out[key] = {k: a[key][k] + (b[key][k] - a[key][k]) * u for k in ("x", "y", "z")}
    for key in ("speed", "cadence", "groundSpeed", "pitch", "roll", "yaw", "camYaw"):
        out[key] = a[key] + (b[key] - a[key]) * u
    Ra = np.array(a["rot"], dtype=np.float64).reshape(3, 3)
    Rb = np.array(b["rot"], dtype=np.float64).reshape(3, 3)
    out["rot"] = mix_rotations([Ra, Rb], [1 - u, u]).reshape(-1).tolist()
    ta = {tr["clip"]: tr for tr in a["tracks"]}
    tracks = []
    for tr in b["tracks"]:
        prev = ta.get(tr["clip"])
        if prev is None:
            # started this frame: it ran from its beginning
            tracks.append({"clip": tr["clip"], "time": tr["time"] * u, "weight": tr["weight"] * u})
            continue
        t0, t1 = prev["time"], tr["time"]
        length = tr.get("length")
        if length and t1 < t0 - 1e-9:
            t1 += length
        tracks.append({"clip": tr["clip"], "time": t0 + (t1 - t0) * u, "weight": prev["weight"] + (tr["weight"] - prev["weight"]) * u})
    for name, prev in ta.items():
        if not any(tr["clip"] == name for tr in b["tracks"]):
            tracks.append({"clip": name, "time": prev["time"], "weight": prev["weight"] * (1 - u)})
    out["tracks"] = tracks
    la, lb = a.get("layers") or {}, b.get("layers") or {}
    layers = {}
    for bone in set(la) | set(lb):
        ra, rb = la.get(bone, [0, 0, 0]), lb.get(bone, [0, 0, 0])
        layers[bone] = [ra[k] + (rb[k] - ra[k]) * u for k in range(3)]
    out["layers"] = layers
    return out


def load_take(path):
    with open(path) as fh:
        take = json.load(fh)
    if take.get("format") != "spicy-motion/1":
        raise SystemExit(f"{path}: not a spicy-motion/1 take (run tools/review/motion_path.luau)")
    lengths = {name: (c["length"] if c["loop"] else None) for name, c in take["clips"].items()}
    # an empty Luau table is written as {} whether it was a list or a map
    if not take.get("props"):
        take["props"] = []
    for f in take["frames"]:
        for tr in f["tracks"]:
            tr["length"] = lengths.get(tr["clip"])
        if not f.get("layers"):
            f["layers"] = {}
        if not f.get("events"):
            f["events"] = []
    return take
