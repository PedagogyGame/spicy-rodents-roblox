"""The squirrel rig's clips (shared by the spicy rodent): the brief's seven (Run, Climb, Wire, Leap,
Pounce, Bite (the bite dance), Stalk (sneak)) plus Idle and Walk. 30 fps; loops close exactly.

Conventions (clips.py): Blender axes, front -Y, left +X; Rx(+) tips a forward-pointing bone nose-down
and lifts a backward-pointing one (the tail); Root carries the whole body about PIVOT.
Timing references: v5.4's bite dance (2.1 s: spin 0.78 sin 12t, roll 0.17 sin 15t, hops |sin 10t|,
head 0.24 sin 7t, eased in and out over 1/6 s); the game drives playback rate from speed
(routes_movement §14), so `nominal_speed` is the no-slide ground speed (studs/s) at 1x: the hind
stride over the stance time, stride / (duty x cycle).
"""
import math

import numpy as np

import clips as engine
from clips import Keys, ease_io, foot_cycle, lerp, piecewise, smooth, wave
from species_squirrel import BACK, FRONT, TAIL

TAU = 2 * math.pi
PIVOT = (0.0, 0.0, 0.9)
RUN_TRAVEL = 5.6  # studs of ground per Run cycle (the motor strides 5.5 at a walk, 5.9 flat out)
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


def bend_side(rig, W, leg, tgt, foot_pitch, splay=0.0):
    """Which way the knee or elbow points for a toe at `tgt`: always to its own side of the line from the
    hip to the hock (the knee ahead of it, and so under a leg that trails behind; the elbow behind it,
    and so under a foreleg that reaches ahead), swung outward by `splay`. A fixed direction instead turns
    the joint inside out as the leg passes it."""
    U, F, T = f"{leg}_Upper", f"{leg}_Foot", f"{leg}_Toe"
    par = rig.parent[U]
    Rp, pp = W[par]
    hip = pp + Rp @ (rig.head[U] - rig.head[par])
    l3 = np.linalg.norm(rig.head[T] - rig.head[F])
    hock = np.asarray(tgt, float) + l3 * np.array([0.0, math.cos(foot_pitch), math.sin(foot_pitch)])
    e = hock - hip
    e[0] = 0.0
    e = e / max(np.linalg.norm(e), 1e-9)
    q = np.array([0.0, e[2], -e[1]]) if leg.startswith("Back") else np.array([0.0, -e[2], e[1]])
    return q + np.array([splay * side(leg), 0.0, 0.0])


def build_pose(rig, P, cfg):
    """clips.build_pose, with one more way to say where a leg bends: a number in place of the pole
    direction is a splay, and the joint then keeps to its own side of the leg (bend_side)."""
    legs = P.get("legs", {})
    if any(np.isscalar(v[3]) for v in legs.values()):
        D = rig.identity()
        engine.body(D, cfg["pivot"], **P.get("body", {}))
        if "spine" in P:
            engine.spine(D, cfg["spine_bones"], *P["spine"])
        W = rig.fk(D)
        P = dict(P)
        P["legs"] = {leg: (tgt, fp, tp, bend_side(rig, W, leg, tgt, fp, pl) if np.isscalar(pl) else pl)
                     for leg, (tgt, fp, tp, pl) in legs.items()}
    return engine.build_pose(rig, P, cfg)


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


def cyc(p, keys, wrap=True):
    """A smooth curve through (phase, value) keys, sorted by phase. It never overshoots a key (a monotone
    cubic), so a key is a true extreme or a true hold. wrap: the curve repeats every cycle; otherwise it
    holds its first value before the first key and its last after the last."""
    n = len(keys)
    if wrap:
        p = p % 1.0
        if p < keys[0][0]:
            p += 1.0
        pts = [keys[-1][0] - 1.0, *[k[0] for k in keys], keys[0][0] + 1.0, keys[1 % n][0] + 1.0]
        val = [keys[-1][1], *[k[1] for k in keys], keys[0][1], keys[1 % n][1]]
    else:
        if p <= keys[0][0]:
            return keys[0][1]
        if p >= keys[-1][0]:
            return keys[-1][1]
        pts = [keys[0][0] - 1.0, *[k[0] for k in keys], keys[-1][0] + 1.0]
        val = [keys[0][1], *[k[1] for k in keys], keys[-1][1]]
    i = max(j for j in range(1, len(pts) - 1) if pts[j] <= p)
    i = min(i, len(pts) - 3)

    def slope(j):
        a = (val[j] - val[j - 1]) / max(pts[j] - pts[j - 1], 1e-9)
        b = (val[j + 1] - val[j]) / max(pts[j + 1] - pts[j], 1e-9)
        return 0.0 if a * b <= 0 else 2 * a * b / (a + b)

    h = pts[i + 1] - pts[i]
    t = (p - pts[i]) / h
    m0, m1 = slope(i) * h, slope(i + 1) * h
    t2, t3 = t * t, t * t * t
    return (2 * t3 - 3 * t2 + 1) * val[i] + (t3 - 2 * t2 + t) * m0 + (-2 * t3 + 3 * t2) * val[i + 1] + (t3 - t2) * m1


def curve(n, table, wrap=True):
    """cyc through values given at key numbers of an n-key cycle: {key: value}."""
    keys = sorted((k / n, v) for k, v in table.items())
    return lambda p: cyc(p, keys, wrap)


# how far each tail segment rises at rest (radians above the horizontal, pointing back)
TAIL_REST = [math.atan2(b[2] - a[2], b[1] - a[1]) for a, b in zip(TAIL, TAIL[1:])]


def tail_local(elev, head, pelvis_pitch=0.0, pelvis_yaw=0.0):
    """The tail's local rotations from where each segment should point in the MODEL's frame, whatever
    the pelvis is doing under it: elev[k] radians above the horizontal, head[k] radians round to the
    body's right of straight back. pelvis_pitch and pelvis_yaw: how far the body and spine have already
    turned the tail's root (body pitch - arch / 2, body yaw - bend / 2)."""
    pitches, yaws = [], []
    pe, ph = pelvis_pitch, pelvis_yaw
    for k in range(len(elev)):
        e = elev[k] - TAIL_REST[k]
        pitches.append(e - pe)
        yaws.append(head[k] - ph)
        pe, ph = e, head[k]
    return pitches, yaws


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
            "nominal_speed": round(0.34 / (0.62 * n / 30), 2), "keys": [0, 6, 12, 18], "brief": "walk"}


class Limb:
    """How one leg strides, by its OWN phase u (0 where the paw lands), in an n-key cycle. For `down` keys
    the toe is on the ground and goes straight back at the ground's speed (`travel` studs a cycle), from
    y_td; then it swings through y, z (and x), given at key numbers between `down` and n. fp and tp are
    the foot and toe pitches, splay how far the knee or elbow turns out, each a number or {key: value}
    round the whole cycle. A paw planted on whole keys is where the ground is at every key. Between two
    keys the engine turns each joint in a straight line, so the toe swings through a shallow arc under
    the line between them: `ground` lifts the whole path by half that dip (it matters only where a paw
    covers a third of a stud or more in one key, as in the gallop)."""

    def __init__(self, n, down, travel, y_td, x, y, z, fp, tp, splay=0.0, xs=None, ground=0.0):
        self.n, self.duty, self.y_td, self.x = n, down / n, y_td, x
        self.sweep = travel * down / n
        self.ground = ground
        self.y = curve(n, {down: y_td + self.sweep, **y, n: y_td}, wrap=False)
        self.z = curve(n, {down: 0.0, **z, n: 0.0}, wrap=False)
        self.xs = curve(n, {0: x, down: x, **xs}) if xs else (lambda u: x)
        self.fp, self.tp, self.splay = (v if callable(v) else (curve(n, v) if isinstance(v, dict) else (lambda u, v=v: v)) for v in (fp, tp, splay))

    def at(self, leg, u, dy=0.0):
        """The leg tuple build_pose takes."""
        u = u % 1.0
        if u < self.duty - 1e-9:
            y, z = self.y_td + self.sweep * u / self.duty, 0.0
        else:
            y, z = self.y(u), self.z(u)
        tgt = np.array([self.xs(u) * side(leg), y + dy, toe_rest(leg)[2] + self.ground + z])
        return (tgt, self.fp(u), self.tp(u), self.splay(u))


def flow(n, p, mean, swing, peak, lag, grow=0.0):
    """Where each of n tail segments points at phase p: mean[k] + a swing that peaks at phase `peak` at
    the root and `lag` cycles later with every segment, `grow` larger with each: a wave running down the
    tail, never the tail moving as one piece."""
    return [mean[k] + (swing + grow * k) * math.cos(TAU * (p - peak - lag * k)) for k in range(n)]


def run(rig, n=14):
    """The bounding gallop (a half-bound), one bound a cycle, RUN_TRAVEL studs of ground under it.
    Keys: 0 the left forepaw lands, 1 the right; 2 and 3 they leave; the back arches tight as the hind
    feet swing in past them on the outside (the gathered flight); 5 both hind feet land ahead of where
    the forepaws stood, wide; 5 to 8 they drive, the back uncurls and the chest comes up; 8 they leave
    and the body flies stretched out, forelegs reaching, hind legs trailing; it tips nose-down to land.
    The head stays level. The tail is carried a little raised and rides a beat behind the rump: up over
    the haunches as the body gathers, streaming low over the trailing legs in the flight, the wave
    running on down to the tip, with a swing from side to side."""
    S = RUN_TRAVEL
    fore = Limb(n, 2, S, -0.80, 0.105,
                y={3: -0.10, 5: -0.30, 7: -0.70, 8: -1.08, 10: -1.14, 12: -1.04, 13: -0.94},
                z={3: 0.15, 5: 0.25, 7: 0.40, 8: 0.54, 10: 0.50, 12: 0.34, 13: 0.15},
                fp={0: 0.55, 1: 0.9, 2: 1.9, 3: 2.6, 5: 2.6, 7: 1.3, 8: 0.5, 10: 0.3, 12: 0.4, 13: 0.5},
                tp={0: 0.2, 2: 0.25, 3: 2.2, 5: 2.6, 7: 1.2, 8: 0.4, 10: 0.2, 13: 0.2}, splay=0.2, ground=0.034)
    # a hind foot: trail straight back after the push, fold, swing in low and wide of the forelegs, land flat
    hind = Limb(n, 3, S, -0.22, 0.255,
                y={4: 1.18, 5: 1.42, 6: 1.42, 7: 1.36, 8: 1.28, 9: 1.15, 10: 0.80, 11: 0.30, 12: -0.05, 13: -0.36},
                z={4: 0.20, 5: 0.42, 6: 0.50, 7: 0.50, 8: 0.46, 9: 0.42, 10: 0.30, 11: 0.14, 12: 0.17, 13: 0.12},
                fp={0: 0.25, 1: 0.35, 2: 0.9, 3: 1.5, 4: 2.2, 5: 2.75, 6: 2.9, 7: 2.9, 8: 2.8, 9: 2.7, 10: 2.2, 11: 1.2, 12: 0.6, 13: 0.3},
                tp={0: 0.1, 3: 0.1, 4: 1.9, 5: 2.7, 6: 2.9, 7: 2.9, 8: 2.8, 9: 2.6, 10: 1.9, 11: 0.7, 12: 0.4, 13: 0.15},
                splay={0: 0.55, 3: 0.15, 6: 0.1, 9: 0.15, 11: 0.45, 13: 0.6}, xs={5: 0.21, 7: 0.18, 10: 0.18, 12: 0.24, 13: 0.255}, ground=0.042)
    pitch = curve(n, {0: 0.20, 2: 0.22, 4: 0.08, 5: 0.0, 6: -0.09, 7: -0.14, 8: -0.15, 10: -0.06, 12: 0.08, 13: 0.15})
    arch = curve(n, {0: -0.08, 2: 0.25, 4: 0.60, 5: 0.62, 6: 0.36, 7: -0.02, 8: -0.32, 10: -0.40, 12: -0.30, 13: -0.20})
    bob = curve(n, {0: 0.02, 2: -0.03, 4: -0.06, 6: -0.05, 7: 0.07, 8: 0.11, 10: 0.14, 12: 0.12})
    surge = curve(n, {0: -0.05, 3: 0.06, 5: 0.07, 8: -0.07, 11: -0.07})
    offsets = {"FrontL": 0.0, "FrontR": 1 / n, "BackL": 5 / n, "BackR": 5 / n}
    tail_mean = [0.30, 0.38, 0.40, 0.34, 0.24, 0.12, 0.0, -0.10]

    def pose(i, n):
        p = i / n
        legs = {leg: (fore if leg.startswith("Front") else hind).at(leg, p - offsets[leg], -0.07 if leg == "BackR" else 0.0) for leg in LEGS}
        b_pitch, b_arch = pitch(p), arch(p)
        b_roll = 0.04 * math.sin(TAU * (p - 0.25))
        b_yaw = 0.03 * math.sin(TAU * p)
        bend = 0.05 * math.sin(TAU * (p - 0.3))
        elev = flow(8, p, tail_mean, 0.22, 0.10, 0.045, 0.02)
        head = flow(8, p, [0.0] * 8, 0.05, 0.55, 0.05, 0.03)
        P = {
            "body": dict(bob=bob(p), pitch=b_pitch, surge=surge(p), roll=b_roll, yaw=b_yaw),
            "spine": (b_arch, bend, 0.05 * math.sin(TAU * (p + 0.05))),
            "legs": legs,
            # the neck gives against the chest (down as the chest comes up), so the head rides steadier
            "neck_pre": -0.7 * (b_pitch + 0.5 * b_arch),
            "head": (0.02 * math.sin(TAU * (p - 0.2)), -0.05 + 0.03 * math.sin(TAU * (p - 0.45)), 0.0),
            "tail": tail_local(elev, head, b_pitch - 0.5 * b_arch, b_yaw - 0.5 * bend),
            "ears": ((-0.45 + 0.08 * math.sin(TAU * (p - 0.1)), 0.1), (-0.45 + 0.08 * math.sin(TAU * (p - 0.3)), -0.1)),
        }
        return build_pose(rig, P, CFG)

    return {"name": "Run", "frames": n, "pose": pose, "loop": True, "priority": "Movement",
            "nominal_speed": round(S / (n / 30), 2), "travel": S, "keys": [0, 3, 5, 8, 10, 12], "brief": "run (bounding gallop)",
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
            "nominal_speed": round(0.4 / (0.5 * n / 30), 2), "keys": [0, 5, 9, 14], "view": [-25, 58], "brief": "climb"}


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
            "nominal_speed": round(0.28 / (0.55 * n / 60), 2), "keys": [0, 8, 15, 23], "view": [-30, 24], "brief": "wire traversal"}


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
            "nominal_speed": round(0.24 / (0.76 * n / 30), 2), "keys": [0, 9, 18, 27], "brief": "sneak (stalk)"}


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
