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
# Studs of ground under one cycle of each moving clip: what the game's rate rule makes a cycle cover
# (AnimationDriver.heroRate: Run by the motor's cadence, 5.5 studs a bound at a walk and 5.9 flat out;
# the others by HERO.stride). Planted paws go back at exactly this, so they stay where they are put.
RUN_TRAVEL = 5.6
WALK_TRAVEL = 2.4
STALK_TRAVEL = 2.2
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


def turn_onto(a, b):
    """The smallest rotation that takes direction a onto direction b."""
    a, b = engine.unit(a), engine.unit(b)
    ax = np.cross(a, b)
    s = np.linalg.norm(ax)
    if s < 1e-9:
        return np.eye(3)
    return engine.rot_axis(ax, math.atan2(s, float(a @ b)))


def build_pose(rig, P, cfg):
    """A pose from explicit parameters, as clips.build_pose, with more ways to say it:
      legs: {leg: (toe xyz, foot_pitch, toe_pitch, pole)}; a NUMBER for the pole is a splay, and the knee
            or elbow then keeps to its own side of the leg (bend_side)
      tail_dirs: where each tail segment points in the MODEL's frame, a vector each (tail_dirs()); the
            pelvis may pitch and roll under the tail without dragging it about
      tail: (pitches, yaws), local, as before
      turn: {bone: 3x3} more local rotation for a body bone, before the legs are placed"""
    D = rig.identity()
    engine.body(D, cfg["pivot"], **P.get("body", {}))
    if "spine" in P:
        engine.spine(D, cfg["spine_bones"], *P["spine"])
    for name, R in P.get("turn", {}).items():
        D[name][0] = D[name][0] @ R
    W = rig.fk(D)
    for leg, (tgt, fp, tp, pl) in P.get("legs", {}).items():
        tgt = np.asarray(tgt, float)
        pl = bend_side(rig, W, leg, tgt, fp, pl) if np.isscalar(pl) else np.asarray(pl, float)
        rig.leg(D, W, leg, tgt, fp, tp, pl)
    if "neck_pre" in P:
        chain = cfg["neck_chain"]
        k = 1.0 / (len(chain) - 1)
        for n in chain[:-1]:
            D[n][0] = D[n][0] @ engine.Rx(P["neck_pre"] * k)
    W = rig.fk(D)
    if "head" in P:
        yaw, pitch, roll = P["head"]
        engine.look(D, rig, W, cfg["neck_chain"], engine.Rz(yaw) @ engine.Rx(pitch) @ engine.Ry(roll), cfg.get("neck_weights"))
    if "tail_dirs" in P:
        Rp = W["Hips"][0]
        for k, d in enumerate(P["tail_dirs"]):
            R = turn_onto(Rp @ TAIL_DIR[k], d) @ Rp
            D[f"Tail{k + 1}"][0] = Rp.T @ R
            Rp = R
    elif "tail" in P:
        pitches, yaws = P["tail"]
        engine.tail(D, "Tail", len(pitches), pitches, yaws)
    if "jaw" in P:
        D["Jaw"][0] = D["Jaw"][0] @ engine.Rx(P["jaw"])
    if "ears" in P:
        (lp, ly), (rp, ry) = P["ears"]
        D["EarL"][0] = D["EarL"][0] @ engine.Rz(ly) @ engine.Rx(lp)
        D["EarR"][0] = D["EarR"][0] @ engine.Rz(ry) @ engine.Rx(rp)
    return D


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


# each tail segment's direction at rest (it rises at about 25 degrees, then levels)
TAIL_DIR = [engine.unit(np.array(b) - np.array(a)) for a, b in zip(TAIL, TAIL[1:])]


def tail_dirs(elev, lat=None):
    """Directions for build_pose's tail_dirs: segment k points elev[k] radians above the horizontal
    (straight back at 0, straight up at pi / 2) and leans lat[k] to the body's left (a slope: 0.3 is
    about 17 degrees), in the model's own frame."""
    lat = lat or [0.0] * len(elev)
    return [np.array([lat[k], math.cos(elev[k]), math.sin(elev[k])]) for k in range(len(elev))]


def flow(n, p, mean, swing, peak, lag, grow=0.0):
    """Where each of n tail segments points at phase p: mean[k] + a swing that is at its most at phase
    `peak` at the root and `lag` cycles later with every segment, `grow` larger with each: a wave running
    down the tail, never the tail moving as one piece."""
    return [mean[k] + (swing + grow * k) * math.cos(TAU * (p - peak - lag * k)) for k in range(n)]


def pulse(p, at, width):
    """A bump of height 1 at phase `at`, about `width` cycles wide, repeating every cycle."""
    d = (p - at + 0.5) % 1.0 - 0.5
    return math.exp(-((d / width) ** 2))


# ---- loops ------------------------------------------------------------------------------------------

def planted(dx=0.0, dy_front=0.0, dy_back=0.0, splay_front=0.3, splay_back=0.45):
    """All four paws flat on the ground at rest, moved by dx outward and dy back."""
    legs = {}
    for leg in LEGS:
        front = leg.startswith("Front")
        t = toe_rest(leg) + np.array([dx * side(leg), dy_front if front else dy_back, 0.0])
        legs[leg] = (t, 0.78 if front else 0.12, 0.15 if front else 0.1, splay_front if front else splay_back)
    return legs


# the tail at rest over the back: a reclined question mark (never past upright), the tip curling back
TAIL_CURL = [0.80, 1.00, 1.08, 0.98, 0.72, 0.38, 0.05, -0.25]
TAIL_LEAN = [0.22, 0.32, 0.40, 0.42, 0.38, 0.32, 0.26, 0.20]  # how far it leans to one side, per segment


def idle(rig, n=90):
    """Standing, never quite still: crouched low on folded hind legs with the back rounded, breathing
    quick and shallow; the head snaps from one look to the next and holds, dips to sniff, comes up
    alert; the weight shifts after the head; the tail stands in a soft curl leaning to one side, swishes
    over to the other and back, and flags twice in short bursts that run from root to tip; each ear
    twitches on its own. Every paw stays where it is."""
    look = [(0.0, (0.0, -0.10)), (0.10, (0.0, -0.10)), (0.13, (0.50, -0.05)), (0.24, (0.50, -0.05)), (0.26, (0.60, -0.01)),
            (0.36, (0.60, -0.01)), (0.40, (-0.45, -0.12)), (0.49, (-0.45, -0.12)), (0.51, (-0.36, -0.17)), (0.58, (-0.36, -0.17)),
            (0.63, (0.06, 0.24)), (0.78, (0.06, 0.24)), (0.82, (0.0, -0.30)), (0.93, (0.0, -0.30)), (0.98, (0.0, -0.10)), (1.0, (0.0, -0.10))]
    # which side the tail leans to (+1 left, -1 right): over and back once a loop, not in even halves
    lean = [(0.0, 1.0), (0.42, 1.0), (0.50, -1.0), (0.86, -1.0), (0.95, 1.0), (1.0, 1.0)]

    def pose(i, n):
        p = i / n
        breath = math.sin(TAU * 4 * p)
        yaw = piecewise(p, [(k, v[0]) for k, v in look])
        hp = piecewise(p, [(k, v[1]) for k, v in look])
        late = piecewise((p - 0.035) % 1.0, [(k, v[0]) for k, v in look])  # the body follows the head, a beat behind
        sniff = 0.035 * math.sin(TAU * 13 * p) * smooth((p - 0.64) / 0.03) * smooth((0.78 - p) / 0.03)
        alert = smooth((p - 0.80) / 0.03) * smooth((0.95 - p) / 0.04)
        down = smooth((p - 0.61) / 0.04) * smooth((0.80 - p) / 0.03)
        elev, lat = [], []
        for k in range(8):
            ph = p - 0.012 * k  # each segment a little later than the one before
            side_k = piecewise(ph % 1.0, lean)
            flag = pulse(ph, 0.30, 0.035) * math.sin(TAU * 13 * (ph - 0.30)) + pulse(ph, 0.73, 0.05) * math.sin(TAU * 12 * (ph - 0.73))
            elev.append(TAIL_CURL[k] + (0.03 + 0.012 * k) * math.sin(TAU * (ph - 0.1)) + (0.05 + 0.045 * k) * flag - 0.10 * (1 - side_k * side_k) * (k / 7))
            lat.append(TAIL_LEAN[k] * side_k + 0.02 * k * math.sin(TAU * 2 * (ph + 0.2)))
        ear_l = (0.16 * alert, -0.35 * (pulse(p, 0.20, 0.012) + pulse(p, 0.55, 0.012)))
        ear_r = (0.16 * alert, 0.35 * (pulse(p, 0.44, 0.012) + pulse(p, 0.88, 0.012)))
        P = {
            "body": dict(bob=-0.095 + 0.005 * breath + 0.02 * alert - 0.01 * down, pitch=-0.03 + 0.004 * breath - 0.07 * alert + 0.06 * down,
                         roll=0.04 * late, sway=-0.03 * late + 0.008 * math.sin(TAU * p), yaw=0.05 * late),
            "spine": (0.26 + 0.02 * breath - 0.06 * alert, 0.16 * late, 0.08 * late),
            "legs": planted(dx=0.02, dy_back=-0.05),
            "head": (yaw, hp + sniff, 0.10 * late + 0.03 * math.sin(TAU * 3 * p)),
            "tail_dirs": tail_dirs(elev, lat),
            "ears": (ear_l, ear_r),
        }
        return build_pose(rig, P, CFG)

    return {"name": "Idle", "frames": n, "pose": pose, "loop": True, "priority": "Idle",
            "keys": [0, 21, 40, 66, 78], "brief": "idle"}


def walk(rig, n=24):
    """The quick low scuttle of the slow speeds (the game shows it between standing and the run): two
    trotting steps a cycle, WALK_TRAVEL studs of ground under them, the belly low, the diagonal pairs
    flicking through short strides while the back snakes from side to side and the tail trails in a soft
    curve with the same wave running down it."""
    g = n // 2  # keys in one step cycle
    S = WALK_TRAVEL / 2
    fore = Limb(g, 6, S, -0.84, 0.13, y={8: -0.42, 10: -0.80, 11: -0.88}, z={7: 0.05, 9: 0.085, 11: 0.03},
                fp={0: 0.7, 3: 0.9, 6: 1.7, 8: 2.3, 10: 0.9, 11: 0.7}, tp={0: 0.2, 6: 0.25, 8: 1.4, 10: 0.3}, splay=0.3)
    hind = Limb(g, 6, S, -0.14, 0.20, y={8: 0.30, 10: -0.10, 11: -0.18}, z={7: 0.05, 9: 0.08, 11: 0.03},
                fp={0: 0.15, 3: 0.3, 6: 1.1, 7: 1.2, 8: 0.9, 10: 0.4, 11: 0.2}, tp={0: 0.1, 6: 0.15, 8: 0.9, 10: 0.2}, splay=0.5)
    offsets = {"FrontL": 0.0, "BackR": 0.0, "FrontR": 0.5, "BackL": 0.5}
    tail_mean = [0.16, 0.24, 0.28, 0.26, 0.20, 0.12, 0.04, -0.04]

    def pose(i, n):
        p = i / n
        q = (2 * p) % 1.0  # the step's own phase
        legs = {leg: (fore if leg.startswith("Front") else hind).at(leg, q - offsets[leg]) for leg in LEGS}
        wig = math.sin(TAU * (q + 0.02))  # + as the left forepaw and right hind foot take the weight
        elev = flow(8, p, tail_mean, 0.05, 0.3, 0.05, 0.012)
        lat = flow(8, q, [0.0] * 8, 0.08, 0.40, 0.07, 0.035)
        P = {
            "body": dict(bob=-0.085 + 0.012 * math.cos(TAU * 2 * (q - 0.06)), pitch=0.03, roll=0.035 * wig, yaw=-0.04 * math.cos(TAU * q), sway=0.012 * wig),
            "spine": (0.10 + 0.03 * math.cos(TAU * 2 * q), 0.13 * math.cos(TAU * q), 0.05 * wig),
            "legs": legs,
            "head": (0.05 * math.sin(TAU * (p - 0.1)), -0.07 + 0.015 * math.sin(TAU * 2 * (q - 0.2)), 0.0),
            "tail_dirs": tail_dirs(elev, lat),
            "ears": ((-0.2 + 0.05 * math.sin(TAU * (q - 0.2)), 0.05), (-0.2 + 0.05 * math.sin(TAU * (q - 0.45)), -0.05)),
        }
        return build_pose(rig, P, CFG)

    return {"name": "Walk", "frames": n, "pose": pose, "loop": True, "priority": "Movement",
            "nominal_speed": round(WALK_TRAVEL / (n / 30), 2), "travel": WALK_TRAVEL, "keys": [0, 3, 6, 9], "brief": "walk (scuttle)"}


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
        lat = flow(8, p, [0.0] * 8, 0.05, 0.55, 0.05, 0.035)
        P = {
            "body": dict(bob=bob(p), pitch=b_pitch, surge=surge(p), roll=b_roll, yaw=b_yaw),
            "spine": (b_arch, bend, 0.05 * math.sin(TAU * (p + 0.05))),
            "legs": legs,
            # the neck gives against the chest (down as the chest comes up), so the head rides steadier
            "neck_pre": -0.7 * (b_pitch + 0.5 * b_arch),
            "head": (0.02 * math.sin(TAU * (p - 0.2)), -0.05 + 0.03 * math.sin(TAU * (p - 0.45)), 0.0),
            "tail_dirs": tail_dirs(elev, lat),
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
    """The stalk: belly almost on the ground, two long creeping strides a cycle (STALK_TRAVEL studs under
    them), one paw at a time in the order left hind, left fore, right hind, right fore, each reaching far
    ahead and set down with care. The body moves in pulses, easing forward and all but stopping between
    steps; the shoulders rock as each foreleg takes the weight and the hips sway the other way. The head
    is carried low, level and dead steady; the tail lies low and straight behind, clear of the back, and
    only its tip twitches."""
    g = n // 2
    S = STALK_TRAVEL / 2
    fore = Limb(g, 12, S, -0.87, 0.14, y={13: -0.22, 15: -0.58, 17: -0.90}, z={13: 0.05, 15: 0.11, 17: 0.05},
                fp={0: 0.75, 6: 0.85, 12: 1.6, 14: 2.3, 16: 0.9, 17: 0.7}, tp={0: 0.2, 12: 0.3, 14: 1.6, 16: 0.2}, splay=0.55)
    hind = Limb(g, 12, S, -0.20, 0.21, y={13: 0.46, 15: 0.14, 17: -0.22}, z={13: 0.05, 15: 0.10, 17: 0.04},
                fp={0: 0.14, 6: 0.25, 12: 1.0, 14: 0.9, 16: 0.4, 17: 0.2}, tp={0: 0.1, 12: 0.15, 14: 0.8, 16: 0.15}, splay=0.75)
    offsets = {"BackL": 0.0, "FrontL": 5 / g, "BackR": 9 / g, "FrontR": 14 / g}
    tail_mean = [-0.10, -0.08, -0.05, -0.02, 0.0, 0.03, 0.08, 0.14]

    def pose(i, n):
        p = i / n
        q = (2 * p) % 1.0
        legs = {leg: (fore if leg.startswith("Front") else hind).at(leg, q - offsets[leg]) for leg in LEGS}
        # + while the left foreleg carries the chest (its stance runs from 5/18 to 17/18 of the step cycle)
        rock = math.sin(TAU * (q - 5 / g - 0.08))
        hip = math.sin(TAU * (q - 0.08))  # + while the left hind foot carries the rump
        creep = math.sin(TAU * 2 * (q - 0.02))  # two pulses to a stride
        twitch = [0.0, 0.0, 0.0, 0.0, 0.03, 0.10, 0.20, 0.32]
        lat = [0.03 * k * math.sin(TAU * (p - 0.2 - 0.04 * k)) + twitch[k] * math.sin(TAU * 5 * p) * (0.5 + 0.5 * math.sin(TAU * (p - 0.1))) for k in range(8)]
        elev = [tail_mean[k] + 0.012 * k * math.sin(TAU * (q - 0.05 * k)) for k in range(8)]
        P = {
            "body": dict(bob=-0.155 + 0.008 * math.cos(TAU * 2 * q), pitch=0.04, surge=0.045 * creep, roll=0.02 * hip, sway=0.02 * hip, yaw=0.025 * math.cos(TAU * q)),
            "spine": (-0.03 + 0.07 * math.cos(TAU * 2 * (q - 0.1)), 0.10 * math.cos(TAU * (q - 0.05)), 0.16 * rock),
            "legs": legs,
            "neck_pre": 0.36,
            "head": (0.0, 0.03, 0.0),
            "tail_dirs": tail_dirs(elev, lat),
            "ears": ((0.18, 0.04 * math.sin(TAU * 3 * p)), (0.18, -0.04 * math.sin(TAU * 3 * p + 1.3))),
        }
        return build_pose(rig, P, CFG)

    return {"name": "Stalk", "frames": n, "pose": pose, "loop": True, "priority": "Movement",
            "nominal_speed": round(STALK_TRAVEL / (n / 30), 2), "travel": STALK_TRAVEL, "keys": [0, 5, 9, 14], "brief": "sneak (stalk)"}


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
