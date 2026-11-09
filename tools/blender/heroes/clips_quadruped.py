"""Fox and deer clips: Idle, Walk, Trot, Run (fox and deer) and the deer's Leap. 30 fps; loops close
exactly. Same engine and conventions as clips_squirrel (clips.py): Blender axes, front -Y, Root carries
the body about PIVOT, legs by IK to a toe (fox: ball of the paw; deer: fetlock) target.

Gaits (footfall phases, fraction of the cycle): walk = lateral sequence (LH 0, LF .25, RH .5, RF .75);
trot = diagonal pairs (LF+RH, RF+LH); run = rotary gallop (fox) / bounding gallop with the white flag up
(deer). `nominal_speed` = the no-slide ground speed at 1x, stride / (duty x cycle), studs/s.
"""
import math

import numpy as np

from clips import Keys, build_pose, foot_cycle, lerp, piecewise, smooth, wave

TAU = 2 * math.pi
LEGS = ("FrontL", "FrontR", "BackL", "BackR")


def side(leg):
    return 1.0 if leg[-1] == "L" else -1.0


class Species:
    def __init__(self, sp, kind):
        self.sp = sp
        self.kind = kind  # "fox" | "deer"
        self.s = 1.0 if kind == "fox" else 2.0  # amplitude scale (deer legs are about twice the fox's)
        self.ntail = sp.NTAIL
        neck = ["Neck", "Head"] if kind == "fox" else ["Neck1", "Neck2", "Neck3", "Head"]
        self.cfg = {"pivot": (0.0, 0.0, 1.55 if kind == "fox" else 3.3),
                    "spine_bones": ["Hips", "Spine1", "Spine2", "Spine3", "Chest"],
                    "neck_chain": neck,
                    "neck_weights": [0.45, 0.55] if kind == "fox" else [0.2, 0.25, 0.25, 0.3]}

    def toe_rest(self, leg):
        src = self.sp.FRONT if leg.startswith("Front") else self.sp.BACK
        x, y, z = src["Toe"]
        return np.array([x * side(leg), y, z])

    def pole(self, leg):
        return np.array([0, -1.0, 0.3]) if leg.startswith("Back") else np.array([0, 1.0, 0.1])

    def pitch(self, leg, st, f, mode):
        """(foot pitch, toe pitch) through the stride. Fox paws are digitigrade; deer stand on their
        hooves with near-vertical cannons."""
        front = leg.startswith("Front")
        if self.kind == "fox":
            rest, push, fold = (1.10, 1.75, 2.75) if front else (1.12, 1.6, 2.1)
            trest = 0.33
        else:
            rest, push, fold = (1.52, 1.85, 2.95) if front else (1.42, 1.7, 2.2)
            trest = 1.08
        if mode == "walk":
            fold = lerp(push, fold, 0.6)
        if st:
            fp = lerp(rest, push, smooth((f - 0.45) / 0.55))
            tp = trest - (0.25 if self.kind == "deer" else 0.1) * math.sin(math.pi * f)  # the fetlock sinks under load
            return fp, tp
        k = math.sin(math.pi * min(f / 0.8, 1.0))
        fp = lerp(push, rest, smooth(f)) + (fold - push) * k * (1 - 0.6 * f)
        return fp, trest + 0.9 * k

    def legs(self, p, spec, mode):
        out = {}
        for leg in LEGS:
            L = spec[leg]
            dy, dz, st, f = foot_cycle(p, L["offset"], L["duty"], L["stride"], L["lift"], L.get("lift_bias", 0.7))
            tgt = self.toe_rest(leg) + np.array([0.0, dy + L.get("dy", 0.0), dz])
            fp, tp = self.pitch(leg, st, f, mode)
            out[leg] = (tgt, fp, tp, self.pole(leg))
        return out

    def planted(self):
        out = {}
        for leg in LEGS:
            fp, tp = self.pitch(leg, True, 0.2, "walk")
            out[leg] = (self.toe_rest(leg), fp, tp, self.pole(leg))
        return out


def spec4(offsets, duty, stride, lift, front_stride=None, dy_front=0.0, dy_back=0.0):
    return {leg: dict(offset=off, duty=duty, stride=(front_stride or stride) if leg.startswith("Front") else stride,
                      lift=lift, dy=dy_front if leg.startswith("Front") else dy_back) for leg, off in offsets.items()}


LS = {"BackL": 0.0, "FrontL": 0.25, "BackR": 0.5, "FrontR": 0.75}
TROT = {"FrontL": 0.0, "BackR": 0.0, "FrontR": 0.5, "BackL": 0.5}


def tails(S, base, pitch_amp, yaw_amp, phase, lag=0.6):
    n = S.ntail
    return ([b + w for b, w in zip(base, wave(n, phase - 0.8, pitch_amp, lag, 0.5))], wave(n, phase, yaw_amp, lag, 1.0))


def idle(S, n):
    fox = S.kind == "fox"
    keys = [(0.0, (0.0, 0.0)), (0.2, (0.0, 0.0)), (0.26, (0.45, -0.05)), (0.48, (0.45, -0.05)), (0.54, (-0.3, 0.1)),
            (0.74, (-0.3, 0.1)), (0.8, (0.0, 0.0)), (1.0, (0.0, 0.0))]
    if not fox:  # a deer lowers its head to browse, then snaps up alert
        keys = [(0.0, (0.0, 0.0)), (0.12, (0.0, 0.0)), (0.22, (0.1, 0.9)), (0.5, (0.1, 0.9)), (0.56, (0.0, -0.1)),
                (0.7, (0.4, -0.1)), (0.82, (0.4, -0.1)), (0.9, (0.0, 0.0)), (1.0, (0.0, 0.0))]
    base_tail = [-0.25, -0.1, 0.0, 0.05, 0.1, 0.18] if fox else [0.0, 0.0]

    def pose(i, n):
        p = i / n
        breath = math.sin(TAU * 2 * p)
        yaw = piecewise(p, [(k, v[0]) for k, v in keys])
        hp = piecewise(p, [(k, v[1]) for k, v in keys])
        browse = 0.0 if fox else smooth((p - 0.14) / 0.08) * smooth((0.54 - p) / 0.06)
        flick = math.exp(-((p - 0.62) / 0.02) ** 2)
        tp, ty = tails(S, base_tail, 0.04, 0.12 if fox else 0.03, TAU * p)
        if not fox:
            tp = [tp[0] + 0.9 * flick, tp[1] + 0.3 * flick]
            ty = [ty[0] + 0.4 * flick * math.sin(TAU * 8 * p), ty[1]]
        ear = 0.35 * math.exp(-((p - 0.35) / 0.02) ** 2)
        ear2 = 0.35 * math.exp(-((p - 0.8) / 0.02) ** 2)
        P = {
            "body": dict(bob=0.008 * S.s * breath, pitch=0.004 * breath + 0.05 * browse),
            "spine": (0.05 + 0.03 * browse, 0.02 * math.sin(TAU * p), 0.0),
            "legs": S.planted(),
            "neck_pre": 0.9 * browse,
            "head": (yaw, hp + 0.03 * math.sin(TAU * 3 * p) * browse, 0.0),
            "tail": (tp, ty),
            "jaw": (0.08 * max(0.0, math.sin(TAU * 9 * p)) * browse) if not fox else 0.0,
            "ears": ((0.0, ear if fox else 0.6 * ear), (0.0, -ear2 if fox else -0.6 * ear2)),
        }
        return build_pose(S.rig, P, S.cfg)

    return {"name": "Idle", "frames": n, "pose": pose, "loop": True, "priority": "Idle", "keys": [0, n // 4, n // 2, 3 * n // 4], "brief": "idle"}


def walk(S, n):
    fox = S.kind == "fox"
    stride = 0.9 if fox else 1.45
    spec = spec4(LS, 0.64, stride, 0.15 if fox else 0.3)
    base_tail = [-0.2, -0.05, 0.05, 0.08, 0.1, 0.15] if fox else [0.0, 0.0]

    def pose(i, n):
        p = i / n
        P = {
            "body": dict(bob=0.015 * S.s * math.cos(TAU * 2 * p), roll=0.02 * math.sin(TAU * p), yaw=0.015 * math.sin(TAU * p + 0.5)),
            "spine": (0.03, 0.04 * math.sin(TAU * p), 0.02 * math.sin(TAU * p)),
            "legs": S.legs(p, spec, "walk"),
            "head": (0.03 * math.sin(TAU * p), (0.0 if fox else 0.04) + (0.03 if fox else 0.06) * math.sin(TAU * 2 * p - 1.0), 0.0),
            "tail": tails(S, base_tail, 0.04, 0.1 if fox else 0.03, TAU * p),
        }
        return build_pose(S.rig, P, S.cfg)

    return {"name": "Walk", "frames": n, "pose": pose, "loop": True, "priority": "Movement",
            "nominal_speed": round(stride / (0.64 * n / 30), 2), "keys": [0, n // 4, n // 2, 3 * n // 4], "brief": "walk"}


def trot(S, n):
    fox = S.kind == "fox"
    stride = 1.35 if fox else 2.0
    spec = spec4(TROT, 0.42, stride, 0.22 if fox else 0.45)
    base_tail = [-0.05, 0.0, 0.02, 0.02, 0.0, 0.05] if fox else [0.5, 0.2]

    def pose(i, n):
        p = i / n
        P = {
            "body": dict(bob=0.035 * S.s * (0.5 - 0.5 * math.cos(TAU * 2 * (p - 0.15))), pitch=0.0),
            "spine": (0.02, 0.0, 0.03 * math.sin(TAU * p)),
            "legs": S.legs(p, spec, "trot"),
            "head": (0.0, 0.0 if fox else -0.05, 0.0),
            "tail": tails(S, base_tail, 0.06, 0.05, TAU * 2 * p),
            "ears": ((-0.15, 0.0), (-0.15, 0.0)) if fox else ((0.0, 0.0), (0.0, 0.0)),
        }
        return build_pose(S.rig, P, S.cfg)

    return {"name": "Trot", "frames": n, "pose": pose, "loop": True, "priority": "Movement",
            "nominal_speed": round(stride / (0.42 * n / 30), 2), "keys": [0, n // 4, n // 2, 3 * n // 4], "brief": "trot"}


def run(S, n):
    """Rotary gallop (fox) / bounding gallop (deer, tail flagged up): the hind pair lands, the back
    flexes as the hind legs drive under, the fore pair reaches, the body stretches through the flight."""
    fox = S.kind == "fox"
    stride = 1.8 if fox else 2.8
    offs = {"BackL": 0.0, "BackR": 0.08, "FrontR": 0.42, "FrontL": 0.52} if fox else {"BackL": 0.0, "BackR": 0.05, "FrontL": 0.45, "FrontR": 0.52}
    spec = spec4(offs, 0.3, stride, 0.28 if fox else 0.75, dy_front=-0.08 * S.s, dy_back=-0.05 * S.s)
    base_tail = [0.12, 0.05, 0.02, 0.0, 0.0, 0.04] if fox else [1.3, 0.5]

    def pose(i, n):
        p = i / n
        P = {
            "body": dict(bob=0.06 * S.s * (0.5 - 0.5 * math.cos(TAU * 2 * (p - 0.1))) - 0.03 * S.s, pitch=0.08 * math.cos(TAU * (p - 0.55))),
            "spine": (0.04 + 0.22 * math.cos(TAU * (p - 0.05)), 0.0, 0.0),
            "legs": S.legs(p, spec, "run"),
            "head": (0.0, (0.05 if fox else -0.1) + 0.04 * math.cos(TAU * (p - 0.3)), 0.0),
            "tail": tails(S, base_tail, 0.12 if fox else 0.1, 0.04, TAU * p),
            "ears": ((-0.4, 0.1), (-0.4, -0.1)) if fox else ((-0.3, 0.0), (-0.3, 0.0)),
        }
        return build_pose(S.rig, P, S.cfg)

    return {"name": "Run", "frames": n, "pose": pose, "loop": True, "priority": "Movement",
            "nominal_speed": round(stride / (0.3 * n / 30), 2), "keys": [0, n // 4, n // 2, 3 * n // 4], "brief": "run" if fox else "run (bolt)"}


def leap(S, n=36):
    """The deer's jump: gather, the hind legs drive, forelegs fold tight under the chest over the
    top, then reach for the landing; hind legs trail and tuck."""
    K = Keys({
        0: dict(bob=0.0, pitch=0.0, arch=0.05, fy=0.0, fz=0.0, fp=1.52, ft=1.08, hy=0.0, hz=0.0, hp=1.42, ht=1.08, tl=0.0, head=0.0),
        6: dict(bob=-0.35, pitch=0.08, arch=0.2, fy=0.1, fz=0.0, fp=1.6, hy=-0.25, hz=0.0, hp=1.2, tl=0.4, head=0.1),
        12: dict(bob=0.25, pitch=-0.32, arch=-0.15, fy=-0.4, fz=1.2, fp=2.9, ft=2.0, hy=0.7, hz=0.1, hp=1.9, ht=1.5, tl=1.0, head=-0.2),
        18: dict(bob=0.55, pitch=-0.05, arch=-0.2, fy=-0.55, fz=1.3, fp=2.95, ft=2.1, hy=1.0, hz=0.5, hp=2.1, ht=1.6, tl=1.2, head=-0.1),
        24: dict(bob=0.4, pitch=0.2, arch=0.0, fy=-0.9, fz=0.35, fp=1.3, ft=0.8, hy=0.5, hz=0.9, hp=2.4, ht=2.0, tl=1.0, head=0.05),
        29: dict(bob=-0.15, pitch=0.12, arch=0.15, fy=-0.5, fz=0.0, fp=1.5, ft=0.9, hy=0.0, hz=0.4, hp=1.8, ht=1.5, tl=0.5, head=0.1),
        35: dict(bob=0.0, pitch=0.0, arch=0.05, fy=0.0, fz=0.0, fp=1.52, ft=1.08, hy=0.0, hz=0.0, hp=1.42, ht=1.08, tl=0.0, head=0.0),
    })

    def pose(i, n):
        f = float(i)
        legs = {}
        for leg in LEGS:
            pre = "f" if leg.startswith("Front") else "h"
            ff = f - (0.7 if leg.endswith("R") else 0.0)
            tgt = S.toe_rest(leg) + np.array([0.0, K(ff, pre + "y"), K(ff, pre + "z")])
            legs[leg] = (tgt, K(ff, pre + "p"), K(ff, pre + "t"), S.pole(leg))
        tl = [K(f - 1.5 * k, "tl") * (1.2 if k == 0 else 0.5) for k in range(S.ntail)]
        P = {
            "body": dict(bob=K(f, "bob"), pitch=K(f, "pitch")),
            "spine": (K(f, "arch"), 0.0, 0.0),
            "legs": legs,
            "head": (0.0, K(f, "head"), 0.0),
            "tail": (tl, [0.0] * S.ntail),
            "ears": ((-0.3 * smooth((f - 6) / 6) * smooth((30 - f) / 6), 0.0),) * 2,
        }
        return build_pose(S.rig, P, S.cfg)

    return {"name": "Leap", "frames": n, "pose": pose, "loop": False, "priority": "Action",
            "keys": [0, 6, 12, 18, 24, 29], "markers": ((6 / 30, "Commit", "takeoff"), (29 / 30, "Recover", "land")), "brief": "leap"}


def clips(rig, sp, variant):
    S = Species(sp, "fox" if sp.SPECIES == "fox" else "deer")
    S.rig = rig
    if S.kind == "fox":
        return [idle(S, 90), walk(S, 36), trot(S, 20), run(S, 14)]
    return [idle(S, 120), walk(S, 40), trot(S, 24), run(S, 18), leap(S, 36)]
