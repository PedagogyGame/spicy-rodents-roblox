"""The squirrel rig's clips (shared by the spicy rodent): the brief's seven (Run, Climb, Wire, Leap,
Pounce, Bite (the bite dance), Stalk (sneak)) plus Idle and Walk. 30 fps; loops close exactly.

Conventions (clips.py): Blender axes, front -Y, left +X; Rx(+) tips a forward-pointing bone nose-down
and lifts a backward-pointing one (the tail); Root carries the whole body about PIVOT.
Timing references: v5.4's bite dance (2.1 s: spin 0.78 sin 12t, roll 0.17 sin 15t, hops |sin 10t|,
head 0.24 sin 7t, eased in and out over 1/6 s); the game drives playback rate from speed
(routes_movement §14), so `nominal_speed` is the speed (studs/s) at which a cycle plays at 1x.
"""
import math

import numpy as np

from clips import Keys, build_pose, ease_io, foot_cycle, lerp, piecewise, smooth, wave
from species_squirrel import BACK, FRONT

TAU = 2 * math.pi
PIVOT = (0.0, 0.0, 0.9)
SPINE = ["Hips", "Spine1", "Spine2", "Spine3", "Chest"]
NECK = ["Neck", "Head"]
LEGS = ("FrontL", "FrontR", "BackL", "BackR")
CFG = {"pivot": PIVOT, "spine_bones": SPINE, "neck_chain": NECK, "neck_weights": [0.4, 0.6]}

# rest pose: tail rises at ~25 degrees then levels; these bend it per clip
TAIL_UP = [0.95, 0.45, 0.25, 0.05, -0.25, -0.45, -0.45, -0.25]  # the classic S over the back
TAIL_SOFT = [0.7, 0.3, 0.18, 0.0, -0.18, -0.28, -0.28, -0.18]
TAIL_BACK = [-0.25, 0.08, 0.12, 0.08, 0.0, -0.05, -0.08, -0.08]  # streaming behind at speed
TAIL_LOW = [-0.6, 0.06, 0.05, 0.0, 0.0, 0.02, 0.06, 0.1]  # low and straight (stalk)
TAIL_FLAT = [-0.42, -0.02, -0.04, -0.04, -0.04, 0.0, 0.0, 0.04]  # pressed to the trunk (climb)


def side(leg):
    return 1.0 if leg[-1] == "L" else -1.0


def toe_rest(leg):
    src = FRONT if leg.startswith("Front") else BACK
    x, y, z = src["Toe"]
    return np.array([x * side(leg), y, z])


def pole(leg, splay=0.0):
    s = side(leg)
    if leg.startswith("Back"):
        return np.array([splay * s, -1.0, 0.3])
    return np.array([splay * s, 1.0, 0.1])


def hind_pitch(st, f, land=0.2, push=1.15, curl=0.9):
    if st:
        return lerp(land, push, smooth((f - 0.4) / 0.6)), 0.1 + 0.1 * f
    return lerp(push * 1.1, land, smooth((f - 0.25) / 0.75)), curl * math.sin(math.pi * f)


def front_pitch(st, f, land=0.8, push=1.6, fold=2.5):
    if st:
        return lerp(land, push, smooth((f - 0.5) / 0.5)), 0.2
    k = math.sin(math.pi * min(f / 0.85, 1.0))
    return lerp(push, land, smooth(f)) + (fold - push) * k * (1 - f), 0.5 * k


def gait_legs(p, spec, t=0.0):
    """spec[leg] = dict(offset, duty, stride, lift, base_dy, base_dx, base_dz, splay, pitch fn kwargs)."""
    legs = {}
    for leg in LEGS:
        L = spec[leg]
        dy, dz, st, f = foot_cycle(p, L["offset"], L["duty"], L["stride"], L["lift"], L.get("lift_bias", 0.75))
        base = toe_rest(leg) + np.array([L.get("dx", 0.0) * side(leg), L.get("dy", 0.0), L.get("dz", 0.0)])
        if "x_abs" in L:
            base[0] = L["x_abs"] * side(leg)
        tgt = base + np.array([0.0, dy, dz])
        if leg.startswith("Back"):
            fp, tp = hind_pitch(st, f, **L.get("pk", {}))
        else:
            fp, tp = front_pitch(st, f, **L.get("pk", {}))
        legs[leg] = (tgt, fp, tp, pole(leg, L.get("splay", 0.0)))
    return legs


def tail_with(base, pitch_wave, yaw_wave):
    return [b + w for b, w in zip(base, pitch_wave)], yaw_wave


# ---- loops ------------------------------------------------------------------------------------------

def idle(rig, n=90):
    head_keys = [(0.0, (0.0, -0.12)), (0.17, (0.0, -0.12)), (0.21, (0.55, -0.04)), (0.43, (0.55, -0.04)),
                 (0.47, (-0.38, 0.04)), (0.66, (-0.38, 0.04)), (0.71, (0.08, 0.28)), (0.86, (0.08, 0.28)),
                 (0.92, (0.0, -0.12)), (1.0, (0.0, -0.12))]

    def pose(i, n):
        p = i / n
        t = i / 30.0
        breath = math.sin(TAU * 2 * p)
        yaw = piecewise(p, [(k, v[0]) for k, v in head_keys])
        hp = piecewise(p, [(k, v[1]) for k, v in head_keys])
        # sniffing: quick small nods while the nose is down
        sniff = 0.03 * math.sin(TAU * 12 * p) * smooth((p - 0.72) / 0.03) * smooth((0.85 - p) / 0.03)
        flick = math.exp(-((p - 0.58) / 0.05) ** 2)
        pw = wave(8, TAU * 2 * p, 0.05, 0.55, 1.0)
        pw = [w + 0.35 * flick * math.sin(TAU * 4 * (p - 0.58) - 0.7 * k) * (k + 1) / 8 for k, w in enumerate(pw)]
        yw = wave(8, TAU * p + 1.0, 0.06, 0.4, 1.5)
        ear_l = (0.0, -0.35 * math.exp(-((p - 0.4) / 0.015) ** 2))
        ear_r = (0.0, 0.35 * math.exp(-((p - 0.83) / 0.015) ** 2))
        legs = {leg: (toe_rest(leg), 0.2 if leg.startswith("Back") else 0.78, 0.15, pole(leg)) for leg in LEGS}
        P = {
            "body": dict(bob=0.006 * breath, pitch=-0.06 + 0.008 * breath, roll=0.01 * math.sin(TAU * p)),
            "spine": (0.14 + 0.02 * breath, 0.02 * math.sin(TAU * p), 0.0),
            "legs": legs,
            "head": (yaw, hp + sniff, 0.06 * math.sin(TAU * p)),
            "tail": tail_with(TAIL_UP, pw, yw),
            "ears": (ear_l, ear_r),
        }
        return build_pose(rig, P, CFG)

    return {"name": "Idle", "frames": n, "pose": pose, "loop": True, "priority": "Idle",
            "keys": [0, 20, 40, 64], "brief": "idle"}


def walk(rig, n=24):
    spec = {
        "BackL": dict(offset=0.0, duty=0.62, stride=0.34, lift=0.08),
        "FrontL": dict(offset=0.25, duty=0.62, stride=0.32, lift=0.07),
        "BackR": dict(offset=0.5, duty=0.62, stride=0.34, lift=0.08),
        "FrontR": dict(offset=0.75, duty=0.62, stride=0.32, lift=0.07),
    }

    def pose(i, n):
        p = i / n
        P = {
            "body": dict(bob=0.012 * math.cos(TAU * 2 * p), pitch=-0.03, roll=0.03 * math.sin(TAU * p), yaw=0.02 * math.sin(TAU * p + 0.6)),
            "spine": (0.08, 0.05 * math.sin(TAU * p), 0.02 * math.sin(TAU * p)),
            "legs": gait_legs(p, spec),
            "head": (0.04 * math.sin(TAU * p), -0.06 + 0.03 * math.sin(TAU * 2 * p - 0.8), 0.0),
            "tail": tail_with(TAIL_SOFT, wave(8, TAU * 2 * p - 1.2, 0.05, 0.5, 0.8), wave(8, TAU * p, 0.07, 0.45, 1.2)),
        }
        return build_pose(rig, P, CFG)

    return {"name": "Walk", "frames": n, "pose": pose, "loop": True, "priority": "Movement",
            "nominal_speed": 0.33 / (n / 30) * 1.0, "keys": [0, 6, 12, 18], "brief": "walk"}


def run(rig, n=14):
    """Half-bound: the front paws land one after the other, the back arches as the hind feet swing
    in ahead of them, then the hind legs drive and the body stretches out through the flight."""
    spec = {
        "FrontL": dict(offset=0.0, duty=0.32, stride=0.5, lift=0.14, dy=-0.04),
        "FrontR": dict(offset=0.07, duty=0.32, stride=0.5, lift=0.14, dy=-0.04),
        "BackL": dict(offset=0.46, duty=0.3, stride=0.64, lift=0.12, dy=-0.06, pk=dict(land=0.35, push=1.25)),
        "BackR": dict(offset=0.53, duty=0.3, stride=0.64, lift=0.12, dy=-0.06, pk=dict(land=0.35, push=1.25)),
    }

    def pose(i, n):
        p = i / n
        P = {
            "body": dict(bob=0.075 * (0.5 - 0.5 * math.cos(TAU * 2 * (p - 0.12))) - 0.045, pitch=0.11 * math.cos(TAU * (p - 0.15))),
            "spine": (0.08 + 0.32 * math.cos(TAU * (p - 0.42)), 0.0, 0.0),
            "legs": gait_legs(p, spec),
            "head": (0.0, -0.06 + 0.05 * math.cos(TAU * (p - 0.35)), 0.0),
            "tail": tail_with(TAIL_BACK, wave(8, TAU * p - 1.0, 0.16, 0.55, 0.6), wave(8, TAU * p, 0.04, 0.5, 1.0)),
            "ears": ((-0.45, 0.1), (-0.45, -0.1)),
        }
        return build_pose(rig, P, CFG)

    stride = 1.6  # studs travelled per cycle at 1x (about a body length: a lively bound)
    return {"name": "Run", "frames": n, "pose": pose, "loop": True, "priority": "Movement",
            "nominal_speed": round(stride / (n / 30), 2), "keys": [0, 4, 7, 11], "brief": "run",
            "markers": ((0.0, "Commit", "stride"),)}


def climb(rig, n=18):
    """Up a trunk: the body hugs the bark (low), legs splayed around it, claws gripping; the tail lies
    flat behind. Bounding climb: the hind pair drives, the front pair reaches."""
    z_top = 0.2

    def wrap(x):
        return z_top - (0.62 - math.sqrt(max(0.62 ** 2 - x * x, 0.0)))  # a trunk of radius 0.62 under the belly

    spec = {
        "FrontL": dict(offset=0.0, duty=0.5, stride=0.36, lift=0.1, x_abs=0.30, dy=-0.05, dz=wrap(0.3) - FRONT["Toe"][2], splay=0.8, pk=dict(land=0.7, push=1.3, fold=2.0)),
        "FrontR": dict(offset=0.12, duty=0.5, stride=0.36, lift=0.1, x_abs=0.30, dy=-0.05, dz=wrap(0.3) - FRONT["Toe"][2], splay=0.8, pk=dict(land=0.7, push=1.3, fold=2.0)),
        "BackL": dict(offset=0.5, duty=0.5, stride=0.4, lift=0.1, x_abs=0.33, dy=0.06, dz=wrap(0.33) - BACK["Toe"][2], splay=0.9, pk=dict(land=0.15, push=0.8)),
        "BackR": dict(offset=0.6, duty=0.5, stride=0.4, lift=0.1, x_abs=0.33, dy=0.06, dz=wrap(0.33) - BACK["Toe"][2], splay=0.9, pk=dict(land=0.15, push=0.8)),
    }

    def pose(i, n):
        p = i / n
        P = {
            "body": dict(bob=-0.24 + 0.03 * math.cos(TAU * 2 * (p - 0.2)), pitch=0.04 * math.cos(TAU * p), surge=0.015 * math.sin(TAU * p)),
            "spine": (0.08 + 0.2 * math.cos(TAU * (p - 0.45)), 0.0, 0.0),
            "legs": gait_legs(p, spec),
            "head": (0.06 * math.sin(TAU * p), -0.18, 0.0),
            "tail": tail_with(TAIL_FLAT, wave(8, TAU * p - 1.0, 0.04, 0.5, 0.5), wave(8, TAU * p, 0.05, 0.45, 1.0)),
            "ears": ((-0.2, 0.0), (-0.2, 0.0)),
        }
        return build_pose(rig, P, CFG)

    return {"name": "Climb", "frames": n, "pose": pose, "loop": True, "priority": "Movement",
            "nominal_speed": round(0.9 / (n / 30), 2), "keys": [0, 5, 9, 14], "view": [-25, 58], "brief": "climb"}


def wire(rig, n=30):
    """Along a wire: quick trotting steps with every paw on the line under the midline, the body
    rolling to balance and the tail swinging wide side to side (two steps per tail sway)."""
    spec = {
        "FrontL": dict(offset=0.0, duty=0.55, stride=0.26, lift=0.06, x_abs=0.025, dy=0.02, pk=dict(land=0.9, push=1.5, fold=2.2)),
        "BackR": dict(offset=0.0, duty=0.55, stride=0.28, lift=0.06, x_abs=0.03, dy=0.0, pk=dict(land=0.3, push=1.0)),
        "FrontR": dict(offset=0.5, duty=0.55, stride=0.26, lift=0.06, x_abs=0.025, dy=0.02, pk=dict(land=0.9, push=1.5, fold=2.2)),
        "BackL": dict(offset=0.5, duty=0.55, stride=0.28, lift=0.06, x_abs=0.03, dy=0.0, pk=dict(land=0.3, push=1.0)),
    }

    def pose(i, n):
        p = i / n
        p2 = (2 * p) % 1.0
        sway = math.sin(TAU * p)
        P = {
            "body": dict(bob=-0.05 + 0.012 * math.cos(TAU * 2 * p2), roll=0.08 * sway, sway=-0.015 * sway, pitch=0.02),
            "spine": (0.12, -0.07 * sway, -0.04 * sway),
            "legs": gait_legs(p2, spec),
            "head": (-0.05 * sway, 0.12, -0.04 * sway),
            "tail": tail_with([-0.1, 0.18, 0.12, 0.04, 0.0, 0.0, 0.0, 0.0], wave(8, TAU * 2 * p, 0.03, 0.5), wave(8, TAU * p + 0.3, 0.2, 0.42, 0.7)),
        }
        return build_pose(rig, P, CFG)

    return {"name": "Wire", "frames": n, "pose": pose, "loop": True, "priority": "Movement",
            "nominal_speed": round(0.55 / (n / 30), 2), "keys": [0, 8, 15, 23], "view": [-30, 24], "brief": "wire traversal"}


def stalk(rig, n=36):
    """Sneak: belly low, a slow lateral-sequence creep with careful high steps, head low and level
    on the target, tail low and straight with the tip twitching."""
    spec = {
        "BackL": dict(offset=0.0, duty=0.76, stride=0.24, lift=0.075, lift_bias=0.6, dy=0.02),
        "FrontL": dict(offset=0.25, duty=0.76, stride=0.22, lift=0.08, lift_bias=0.6, pk=dict(land=0.9, push=1.4, fold=2.2)),
        "BackR": dict(offset=0.5, duty=0.76, stride=0.24, lift=0.075, lift_bias=0.6, dy=0.02),
        "FrontR": dict(offset=0.75, duty=0.76, stride=0.22, lift=0.08, lift_bias=0.6, pk=dict(land=0.9, push=1.4, fold=2.2)),
    }

    def pose(i, n):
        p = i / n
        twitch = [0, 0, 0, 0, 0, 0.12, 0.2, 0.28]
        yw = [w + tw * math.sin(TAU * 3 * p) for w, tw in zip(wave(8, TAU * p, 0.03, 0.4), twitch)]
        P = {
            "body": dict(bob=-0.15 + 0.008 * math.cos(TAU * 2 * p), pitch=0.05, roll=0.015 * math.sin(TAU * p)),
            "spine": (-0.04, 0.03 * math.sin(TAU * p), 0.0),
            "legs": gait_legs(p, spec),
            "neck_pre": 0.38,
            "head": (0.0, 0.02, 0.0),
            "tail": (TAIL_LOW, yw),
            "ears": ((0.18, 0.0), (0.18, 0.0)),
        }
        return build_pose(rig, P, CFG)

    return {"name": "Stalk", "frames": n, "pose": pose, "loop": True, "priority": "Movement",
            "nominal_speed": round(0.23 / (n / 30), 2), "keys": [0, 9, 18, 27], "brief": "sneak (stalk)"}


# ---- one-shots --------------------------------------------------------------------------------------

def keyed_legs(K, f, lead=("FrontL", "FrontR", "BackL", "BackR"), lag=0.0):
    legs = {}
    for leg in LEGS:
        pre = "f" if leg.startswith("Front") else "h"
        ff = f - (lag if leg.endswith("R") else 0.0)
        tgt = toe_rest(leg) + np.array([0.0, K(ff, pre + "y", 0.0), K(ff, pre + "z", 0.0)])
        tgt[0] = toe_rest(leg)[0] + side(leg) * K(ff, pre + "x", 0.0)
        fp = K(ff, pre + "p", 0.2 if pre == "h" else 0.78)
        tp = K(ff, pre + "t", 0.15)
        legs[leg] = (tgt, fp, tp, pole(leg))
    return legs


def lagged_tail(K, f, base, name="tl", lag=1.2, gain=None):
    gain = gain or [1.0, 0.7, 0.5, 0.4, 0.35, 0.3, 0.3, 0.3]
    return [b + g * K(f - lag * i, name) for i, (b, g) in enumerate(zip(base, gain))]


def leap(rig, n=24):
    K = Keys({
        0: dict(bob=0.0, surge=0.0, pitch=0.0, arch=0.12, hy=0.0, hz=0.0, hp=0.2, ht=0.15, fy=0.0, fz=0.0, fp=0.78, ft=0.15, tl=0.0, head=-0.08, ear=0.0),
        5: dict(bob=-0.13, surge=0.04, pitch=0.06, arch=0.3, hy=-0.06, hp=0.15, fy=0.04, fp=1.0, tl=-0.35, head=0.04, ear=-0.2),
        9: dict(bob=0.08, surge=-0.1, pitch=-0.28, arch=-0.32, hy=0.42, hz=0.05, hp=1.45, ht=0.1, fy=-0.36, fz=0.32, fp=2.1, ft=0.6, tl=-0.1, head=-0.16, ear=-0.5),
        14: dict(bob=0.12, surge=-0.12, pitch=-0.06, arch=-0.36, hy=0.62, hz=0.22, hp=1.6, ht=0.5, fy=-0.46, fz=0.36, fp=1.1, ft=0.2, tl=-0.05, head=-0.06, ear=-0.55),
        19: dict(bob=0.05, surge=-0.06, pitch=0.16, arch=0.0, hy=0.2, hz=0.3, hp=1.1, ht=0.6, fy=-0.34, fz=0.08, fp=0.55, ft=0.05, tl=0.1, head=0.02, ear=-0.4),
        23: dict(bob=-0.04, surge=0.0, pitch=0.07, arch=0.16, hy=-0.04, hz=0.04, hp=0.4, ht=0.15, fy=-0.06, fz=0.0, fp=0.95, ft=0.15, tl=-0.05, head=-0.06, ear=-0.1),
    })

    def pose(i, n):
        f = float(i)
        tp = lagged_tail(K, f, TAIL_BACK, lag=1.1)
        P = {
            "body": dict(bob=K(f, "bob"), surge=K(f, "surge"), pitch=K(f, "pitch")),
            "spine": (K(f, "arch"), 0.0, 0.0),
            "legs": keyed_legs(K, f, lag=0.6),
            "head": (0.0, K(f, "head"), 0.0),
            "tail": (tp, wave(8, 0.4 * f, 0.03, 0.5)),
            "ears": ((K(f, "ear"), 0.1), (K(f, "ear"), -0.1)),
        }
        return build_pose(rig, P, CFG)

    return {"name": "Leap", "frames": n, "pose": pose, "loop": False, "priority": "Action",
            "keys": [0, 5, 9, 14, 19, 23], "markers": ((5 / 30, "Commit", "takeoff"), (19 / 30, "Recover", "land")),
            "brief": "leap"}


def pounce(rig, n=30):
    """Wind-up (crouch and the rear wiggle), Commit at 0.4 s: the lunge with paws and jaws open, the
    bite snaps shut, Recover at 0.7 s: land, worry the bite with a head shake, settle."""
    K = Keys({
        0: dict(bob=-0.12, surge=0.0, pitch=0.06, arch=0.05, hy=0.0, hz=0.0, hp=0.2, ht=0.15, fy=-0.02, fz=0.0, fp=0.9, ft=0.15, tl=0.0, head=0.06, jaw=0.0, ear=0.15, neck=0.3),
        11: dict(bob=-0.17, surge=0.05, pitch=0.08, arch=0.3, hy=-0.07, hp=0.15, fy=0.0, fp=1.0, tl=-0.15, head=0.04, jaw=0.05, ear=0.2, neck=0.3),
        15: dict(bob=0.07, surge=-0.32, pitch=-0.12, arch=-0.34, hy=0.5, hz=0.03, hp=1.4, ht=0.1, fy=-0.5, fz=0.2, fp=1.05, ft=-0.2, tl=0.3, head=-0.06, jaw=0.62, ear=-0.5, neck=0.0),
        17: dict(bob=0.03, surge=-0.36, pitch=0.04, arch=-0.15, hy=0.42, hz=0.06, hp=1.3, fy=-0.5, fz=0.1, fp=0.9, ft=0.1, tl=0.2, head=0.18, jaw=0.0, ear=-0.5, neck=0.1),
        21: dict(bob=-0.07, surge=-0.28, pitch=0.12, arch=0.15, hy=0.1, hz=0.02, hp=0.5, fy=-0.38, fz=0.0, fp=0.95, tl=-0.05, head=0.12, jaw=0.06, ear=-0.2, neck=0.15),
        29: dict(bob=-0.03, surge=0.0, pitch=0.03, arch=0.12, hy=0.0, hz=0.0, hp=0.22, fy=0.0, fz=0.0, fp=0.8, tl=0.0, head=-0.06, jaw=0.0, ear=0.0, neck=0.0),
    })

    def pose(i, n):
        f = float(i)
        t = i / 30.0
        wig = math.sin(TAU * t / 0.18) * smooth((f - 1) / 3) * smooth((11 - f) / 2)  # the rear wiggle
        shake = math.sin(TAU * t / 0.12) * smooth((f - 20) / 2) * smooth((27 - f) / 3)
        legs = keyed_legs(K, f, lag=0.4)
        for leg in ("BackL", "BackR"):  # treading in place during the wiggle
            tg, fp, tp, pl = legs[leg]
            tread = max(0.0, math.sin(TAU * t / 0.18 + (0 if leg == "BackL" else math.pi))) * 0.03 * smooth((f - 1) / 3) * smooth((10 - f) / 2)
            legs[leg] = (tg + np.array([0, 0, tread]), fp, tp, pl)
        P = {
            "body": dict(bob=K(f, "bob"), surge=K(f, "surge"), pitch=K(f, "pitch"), yaw=0.0),
            "spine": (K(f, "arch"), 0.16 * wig, 0.0),
            "legs": legs,
            "neck_pre": K(f, "neck"),
            "head": (0.22 * shake - 0.08 * wig, K(f, "head"), 0.1 * shake),
            "tail": (lagged_tail(K, f, TAIL_LOW, lag=1.0), [y + 0.25 * wig * (k / 7) for k, y in enumerate(wave(8, 2.5 * t, 0.04, 0.5))]),
            "jaw": K(f, "jaw"),
            "ears": ((K(f, "ear"), 0.0), (K(f, "ear"), 0.0)),
        }
        return build_pose(rig, P, CFG)

    return {"name": "Pounce", "frames": n, "pose": pose, "loop": False, "priority": "Action",
            "keys": [0, 6, 11, 15, 17, 21, 25], "markers": ((0.4, "Commit", "lunge"), (0.7, "Recover", "land")),
            "brief": "pounce"}


def bite_dance(rig, n=63):
    """The bite dance (v5.4 animateBiteDance, 2.1 s): spin wiggle 0.78 sin 12t, roll 0.17 sin 15t,
    hops |sin 10t|, head 0.24 sin 7t, eased in and out over 1/6 s; plus paws waving, jaw chattering
    and the tail swishing."""

    def pose(i, n):
        t = i / 30.0
        k = max(0.0, min(1.0, 6 * t, 6 * (2.1 - t)))
        hop = abs(math.sin(10 * t)) * 0.16 * k
        legs = {}
        for leg in LEGS:
            tg = toe_rest(leg).copy()
            lift = hop * (0.85 if leg.startswith("Back") else 1.0)
            if leg.startswith("Front"):
                lift += 0.07 * max(0.0, math.sin(10 * t + (0 if leg.endswith("L") else math.pi))) * k
            tg[2] += lift
            legs[leg] = (tg, (0.3 + 0.8 * hop) if leg.startswith("Back") else (0.8 + 2.0 * lift), 0.15 + 2 * hop, pole(leg))
        P = {
            "body": dict(bob=hop, yaw=math.sin(12 * t) * 0.78 * k, roll=math.sin(15 * t) * 0.17 * k, pitch=-0.12 * k),
            "spine": (0.12 + 0.1 * k, 0.12 * math.sin(12 * t - 0.6) * k, 0.0),
            "legs": legs,
            "head": (math.sin(7 * t) * 0.24 * k + math.sin(12 * t) * 0.78 * k * 0.5, -0.12 * k, 0.1 * math.sin(15 * t) * k),
            "tail": tail_with(TAIL_UP, wave(8, 10 * t, 0.12 * k, 0.5, 0.5), wave(8, 12 * t - 1.0, 0.25 * k, 0.5, 0.8)),
            "jaw": 0.18 * abs(math.sin(25 * t)) * k,
            "ears": ((0.2 * math.sin(14 * t) * k, 0.0), (0.2 * math.sin(14 * t + 1.0) * k, 0.0)),
        }
        return build_pose(rig, P, CFG)

    return {"name": "Bite", "frames": n, "pose": pose, "loop": False, "priority": "Action",
            "keys": [0, 8, 16, 26, 36, 46], "brief": "bite dance"}


def clips(rig, sp, variant):
    return [idle(rig), walk(rig), run(rig), climb(rig), wire(rig), leap(rig), pounce(rig), bite_dance(rig), stalk(rig)]
