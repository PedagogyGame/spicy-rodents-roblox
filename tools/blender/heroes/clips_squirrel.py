"""The squirrel rig's clips (shared by the spicy rodent): the brief's seven (Run, Climb, Wire, Leap,
Pounce, Bite (the bite dance), Stalk (sneak)) plus Idle and Walk. 30 fps; loops close exactly.

Conventions (clips.py): Blender axes, front -Y, left +X; Rx(+) tips a forward-pointing bone nose-down
and lifts a backward-pointing one (the tail); Root carries the whole body about PIVOT.

What the clips are built to (owner 2026-11-11, seen from the play camera behind and above: "rigid,
unalive"):
  * The surface the paws stand on is height 0 in every clip: the ground, and for Climb the bark and for
    Wire the line or the bough's top. The game puts the model's feet point on the surface.
  * A moving clip covers a fixed stretch of ground per cycle (the *_TRAVEL numbers below, which are what
    the game's rate rule makes a cycle cover), and a planted paw goes straight back at exactly that, on
    whole keys: it stays where it was put. `nominal_speed` is that stretch over the clip's length, the
    ground speed at which the clip plays at 1x.
  * The gaits are the animal's: a bounding gallop (Run), the same bound up a trunk (Climb) and small along
    a wire (Wire), a trotting scuttle (Walk), a one-paw-at-a-time creep (Stalk).
  * Nothing moves as one piece: the tail is said segment by segment in the model's frame, each later than
    the one before (flow, tail_dirs); the head is held level against the body; the ears and the right
    legs run a little behind.
  * The frames of the one-shots are fixed points other code may count on (Leap: 5 take-off, 9 stretch,
    14 top, 19 reach, 21 braced, 22 landing; Pounce: 12 lunge, 17 bite, 21 land), with Commit and Recover
    markers on them. Timing reference for the bite dance: v5.4 (2.1 s: spin 0.78 sin 12t, roll
    0.17 sin 15t, hops |sin 10t|, head 0.24 sin 7t, eased in and out over 1/6 s).
"""
import math

import numpy as np

import clips as engine
from clips import piecewise, smooth
from species_squirrel import BACK, FRONT, TAIL

TAU = 2 * math.pi
PIVOT = (0.0, 0.0, 0.9)
# Studs of ground under one cycle of each moving clip: what the game's rate rule makes a cycle cover
# (AnimationDriver.heroRate: Run by the motor's cadence, 5.5 studs a bound at a walk and 5.9 flat out;
# the others by HERO.stride). Planted paws go back at exactly this, so they stay where they are put.
RUN_TRAVEL = 5.6
WALK_TRAVEL = 2.4
STALK_TRAVEL = 2.2
CLIMB_TRAVEL = 3.6
WIRE_TRAVEL = 6.9  # (the rate is capped at 2.6: 18 studs/s is then 6.9 studs a cycle; HERO.stride says 4.5)
SPINE = ["Hips", "Spine1", "Spine2", "Spine3", "Chest"]
NECK = ["Neck", "Head"]
LEGS = ("FrontL", "FrontR", "BackL", "BackR")
CFG = {"pivot": PIVOT, "spine_bones": SPINE, "neck_chain": NECK, "neck_weights": [0.4, 0.6]}


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

    def __init__(self, n, down, travel, y_td, x, y, z, fp, tp, splay=0.0, xs=None, ground=0.0, pole=None):
        self.n, self.duty, self.y_td, self.x = n, down / n, y_td, x
        self.sweep = travel * down / n
        self.ground = ground
        self.pole = pole  # (x outward, y, z): a fixed direction for the knee or elbow, instead of bend_side
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
        if self.pole is not None:
            return (tgt, self.fp(u), self.tp(u), np.array([self.pole[0] * side(leg), self.pole[1], self.pole[2]]))
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
    """Up a trunk in bounds, CLIMB_TRAVEL studs of bark a cycle, the body pressed to it. The bark is the
    plane the paws stand on (height 0, as the ground is in the other clips; the game puts the feet point
    on the surface). Keys: 0 and 1 the forepaws take hold by the neck, elbows out to the sides, and pull;
    the back humps off the bark as the hind feet are brought up outside them; 8 both hind feet take hold,
    knees out, and shove for four keys; the body stretches flat up the bark, forelegs reaching. The head
    is lifted to look up the trunk; the tail lies along the bark with its tip clear of it and a wave
    swinging down it from side to side, each segment later than the last."""
    S = CLIMB_TRAVEL
    fore = Limb(n, 2, S, -0.60, 0.25,
                y={3: -0.16, 5: -0.22, 9: -0.38, 13: -0.56, 15: -0.66, 17: -0.65},
                z={3: 0.06, 5: 0.10, 9: 0.10, 13: 0.10, 15: 0.08, 17: 0.04},
                fp={0: 0.55, 2: 1.2, 4: 2.1, 8: 1.6, 13: 0.7, 16: 0.5}, tp={0: 0.5, 2: 0.6, 4: 1.8, 9: 0.9, 15: 0.3, 17: 0.45},
                xs={4: 0.23, 9: 0.20, 15: 0.23}, ground=-0.012, pole=(1.0, 0.45, 0.2))
    hind = Limb(n, 4, S, 0.02, 0.40,
                y={5: 0.92, 7: 0.82, 10: 0.46, 13: 0.10, 15: -0.08, 17: -0.04},
                z={5: 0.07, 7: 0.13, 10: 0.14, 13: 0.12, 15: 0.08, 17: 0.04},
                fp={0: 0.12, 2: 0.3, 4: 0.95, 5: 1.6, 7: 1.5, 10: 0.7, 14: 0.25, 17: 0.12}, tp={0: 0.3, 4: 0.35, 5: 1.4, 8: 0.9, 12: 0.4, 17: 0.3},
                xs={6: 0.36, 11: 0.33, 16: 0.39}, ground=-0.012, pole=(1.0, -0.55, 0.12))
    offsets = {"FrontL": 0.0, "FrontR": 1 / n, "BackL": 8 / n, "BackR": 8 / n}
    arch = curve(n, {0: -0.12, 3: 0.14, 6: 0.40, 8: 0.44, 10: 0.20, 12: -0.14, 14: -0.26, 16: -0.24})
    pitch = curve(n, {0: 0.05, 4: 0.02, 8: -0.05, 12: -0.07, 15: 0.0})
    bob = curve(n, {0: -0.275, 4: -0.27, 8: -0.255, 12: -0.265, 15: -0.285})
    surge = curve(n, {0: -0.03, 4: 0.04, 8: 0.05, 12: -0.05, 15: -0.05})
    tail_mean = [-0.25, -0.20, -0.12, -0.05, 0.0, 0.05, 0.15, 0.28]

    def pose(i, n):
        p = i / n
        legs = {leg: (fore if leg.startswith("Front") else hind).at(leg, p - offsets[leg], -0.06 if leg == "BackR" else 0.0) for leg in LEGS}
        b_arch = arch(p)
        elev = flow(8, p, tail_mean, 0.04, 0.55, 0.05, 0.008)
        lat = flow(8, p, [0.0] * 8, 0.09, 0.15, 0.075, 0.045)
        P = {
            "body": dict(bob=bob(p), pitch=pitch(p), surge=surge(p), yaw=0.035 * math.sin(TAU * (p - 0.05)), roll=0.03 * math.sin(TAU * (p - 0.3))),
            "spine": (b_arch, 0.07 * math.sin(TAU * (p - 0.2)), 0.04 * math.sin(TAU * p)),
            "legs": legs,
            "neck_pre": -0.25,
            "head": (0.07 * math.sin(TAU * (p - 0.4)), -0.16 + 0.03 * math.sin(TAU * (p - 0.5)), 0.0),
            "tail_dirs": tail_dirs(elev, lat),
            "ears": ((-0.2 + 0.06 * math.sin(TAU * (p - 0.15)), 0.0), (-0.2 + 0.06 * math.sin(TAU * (p - 0.4)), 0.0)),
        }
        return build_pose(rig, P, CFG)

    return {"name": "Climb", "frames": n, "pose": pose, "loop": True, "priority": "Movement",
            "nominal_speed": round(S / (n / 30), 2), "travel": S, "keys": [0, 3, 8, 12, 15], "view": [-25, 58], "brief": "climb"}


def wire(rig, n=30):
    """Along a wire or a bough: two small quick bounds a cycle (WIRE_TRAVEL studs under them), every paw
    set on the line itself, one ahead of the other, fingers and toes curled round it. The body is carried
    low and long, the back flexing with each bound; over the two bounds it rolls a little one way and
    back, and the tail, trailing just raised, answers with a curve that runs out along it to the tip, the
    other way: balance, not a wiper. The line is height 0, as the ground is in the other clips."""
    g = n // 2
    S = WIRE_TRAVEL / 2
    fore = Limb(g, 3, S, -0.82, 0.02,
                y={4: -0.10, 6: -0.30, 9: -0.80, 11: -0.98, 13: -1.00, 14: -0.92},
                z={4: 0.10, 6: 0.16, 9: 0.26, 11: 0.26, 13: 0.14, 14: 0.06},
                fp={0: 0.6, 2: 1.0, 3: 1.8, 5: 2.4, 8: 1.2, 10: 0.5, 13: 0.5}, tp={0: 0.5, 3: 0.55, 4: 1.9, 8: 0.8, 12: 0.3, 14: 0.45},
                splay=0.3, ground=0.008)
    hind = Limb(g, 3, S, -0.10, 0.03,
                y={4: 0.72, 6: 0.80, 8: 0.62, 10: 0.25, 12: -0.10, 14: -0.18},
                z={4: 0.10, 6: 0.20, 8: 0.20, 10: 0.13, 12: 0.11, 14: 0.05},
                fp={0: 0.2, 2: 0.6, 3: 1.2, 5: 2.0, 7: 2.0, 9: 1.0, 10: 0.6, 11: 0.45, 13: 0.3}, tp={0: 0.35, 3: 0.4, 4: 1.6, 7: 1.8, 10: 0.6, 13: 0.3},
                splay={0: 0.6, 3: 0.3, 7: 0.3, 12: 0.6}, ground=0.008)
    offsets = {"FrontL": 0.0, "FrontR": 1 / g, "BackL": 6 / g, "BackR": 6 / g}
    arch = curve(g, {0: -0.05, 3: 0.20, 5: 0.38, 6: 0.39, 8: 0.05, 9: -0.17, 11: -0.23, 13: -0.15})
    pitch = curve(g, {0: 0.12, 3: 0.12, 6: 0.0, 8: -0.10, 11: -0.03, 13: 0.08})
    bob = curve(g, {0: -0.09, 3: -0.12, 6: -0.13, 8: -0.08, 11: -0.03, 13: -0.05})
    surge = curve(g, {0: -0.03, 4: 0.04, 6: 0.04, 9: -0.04, 12: -0.04})
    tail_mean = [0.14, 0.20, 0.22, 0.20, 0.16, 0.12, 0.08, 0.04]

    def pose(i, n):
        p = i / n
        q = (2 * p) % 1.0
        legs = {leg: (fore if leg.startswith("Front") else hind).at(leg, q - offsets[leg], -0.13 if leg == "BackR" else 0.0) for leg in LEGS}
        lean = math.sin(TAU * p)
        elev = flow(8, q, tail_mean, 0.10, 0.12, 0.05, 0.01)
        lat = flow(8, p, [0.0] * 8, 0.05, 0.80, 0.045, 0.04)
        P = {
            "body": dict(bob=bob(q), pitch=pitch(q), surge=surge(q), roll=0.07 * lean, sway=-0.012 * lean, yaw=0.02 * math.sin(TAU * (p - 0.2))),
            "spine": (arch(q), -0.05 * lean, -0.04 * lean),
            "legs": legs,
            "neck_pre": -0.6 * (pitch(q) + 0.5 * arch(q)),
            "head": (-0.04 * lean, 0.06 + 0.02 * math.sin(TAU * (q - 0.4)), 0.0),
            "tail_dirs": tail_dirs(elev, lat),
            "ears": ((-0.3 + 0.06 * math.sin(TAU * (q - 0.1)), 0.05), (-0.3 + 0.06 * math.sin(TAU * (q - 0.35)), -0.05)),
        }
        return build_pose(rig, P, CFG)

    return {"name": "Wire", "frames": n, "pose": pose, "loop": True, "priority": "Movement",
            "nominal_speed": round(WIRE_TRAVEL / (n / 30), 2), "travel": WIRE_TRAVEL, "keys": [0, 3, 6, 9, 12], "view": [-30, 24], "brief": "wire traversal"}


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

def track(table):
    """A curve through {frame: value} that holds its ends and never overshoots a key (one-shots)."""
    keys = sorted(table.items())
    return lambda f: cyc(f, keys, wrap=False)


# the tail's own shape when it streams behind (added to the root's rise): up a little, then trailing
TAIL_STREAM = [0.0, 0.08, 0.10, 0.04, -0.06, -0.18, -0.30, -0.40]
CFG_MID = {**CFG, "pivot": (0.0, 0.0, 0.62)}  # one-shots pitch about the middle of the body, not above it


def leap(rig, n=24):
    """The leap, on the same frames as before (the game, or whatever drives the clip by the jump, can
    count on them): 0 ready; 3 the crouch, haunches under and back bowed; 5 the take-off (Commit), hind
    legs driving straight and the chest thrown up; 9 the stretch, forelegs reaching far ahead and hind
    legs trailing straight back, the tail up behind as a rudder; 14 the top, level and spread; 19 the
    reach (Recover), nose down, forelegs out for the ground and hind feet coming under; 21 braced for the
    ground (the pose a long fall holds); 22 the landing taken up, chest dipping, back bowed, haunches
    folding and the tail whipping down; 23 coming out of it. The right legs run half a frame behind the
    left, and each tail segment a frame behind the one before."""
    T = {name: track(tab) for name, tab in dict(
        bob={0: -0.03, 3: -0.15, 5: 0.08, 9: 0.10, 14: 0.10, 19: 0.05, 21: 0.0, 22: -0.13, 23: -0.07},
        surge={0: 0.0, 3: 0.05, 5: -0.10, 9: -0.06, 14: -0.04, 19: 0.0, 21: 0.02, 22: 0.04, 23: 0.02},
        pitch={0: 0.02, 3: 0.10, 5: -0.34, 9: -0.26, 14: -0.02, 19: 0.26, 21: 0.24, 22: 0.16, 23: 0.06},
        arch={0: 0.16, 3: 0.48, 5: -0.06, 9: -0.38, 14: -0.30, 19: 0.06, 21: 0.14, 22: 0.50, 23: 0.30},
        fy={0: 0.0, 3: 0.0, 5: -0.25, 9: -0.56, 14: -0.50, 17: -0.40, 19: -0.28, 21: -0.20, 22: -0.12, 23: -0.03},
        fz={0: 0.0, 3: 0.0, 5: 0.42, 9: 0.66, 14: 0.52, 19: 0.16, 21: 0.05, 22: 0.0, 23: 0.0},
        fx={0: 0.0, 9: 0.02, 14: 0.11, 19: 0.04, 22: 0.02},
        fp={0: 0.78, 3: 1.0, 5: 1.5, 9: 0.3, 14: 0.35, 19: 0.5, 21: 0.6, 22: 0.9, 23: 0.8},
        ft={0: 0.15, 3: 0.2, 5: 1.2, 9: 0.2, 14: 0.15, 19: 0.2, 22: 0.2},
        hy={0: -0.03, 3: -0.14, 5: 0.75, 9: 1.40, 14: 1.36, 19: 0.50, 21: 0.05, 22: -0.20, 23: -0.10},
        hz={0: 0.0, 3: 0.0, 5: 0.0, 9: 0.36, 14: 0.52, 19: 0.36, 21: 0.10, 22: 0.0, 23: 0.0},
        hx={0: 0.0, 3: 0.03, 9: 0.0, 14: 0.09, 19: 0.05, 22: 0.06, 23: 0.03},
        hp={0: 0.15, 3: 0.12, 5: 1.4, 9: 2.8, 14: 2.9, 19: 1.3, 21: 0.5, 22: 0.25, 23: 0.2},
        ht={0: 0.1, 3: 0.1, 5: 0.15, 9: 2.7, 14: 2.9, 19: 1.0, 21: 0.3, 22: 0.1},
        tail={0: 0.30, 3: -0.05, 5: -0.10, 9: 0.48, 14: 0.34, 19: 0.80, 21: 0.72, 22: 0.0, 23: 0.24},
        curl={0: 0.0, 9: -0.1, 14: 0.55, 19: 0.2, 22: -0.2, 23: 0.0},
        head={0: -0.06, 3: 0.05, 5: -0.14, 9: -0.10, 14: -0.04, 19: 0.10, 22: 0.02, 23: -0.05},
        ear={0: 0.0, 3: -0.25, 5: -0.5, 14: -0.55, 19: -0.4, 22: -0.2, 23: -0.1},
    ).items()}

    def pose(i, n):
        f = float(i)
        legs = {}
        for leg in LEGS:
            pre = "f" if leg.startswith("Front") else "h"
            ff = f - (0.5 if leg.endswith("R") else 0.0)
            t = toe_rest(leg) + np.array([T[pre + "x"](ff) * side(leg), T[pre + "y"](ff), T[pre + "z"](ff)])
            legs[leg] = (t, T[pre + "p"](ff), T[pre + "t"](ff), 0.25 if pre == "f" else 0.3)
        elev = [T["tail"](f - 1.0 * k) + TAIL_STREAM[k] + T["curl"](f - 1.0 * k) * (k / 7) ** 2 for k in range(8)]
        lat = [0.025 * k * math.sin(0.5 * (f - 1.2 * k)) for k in range(8)]
        P = {
            "body": dict(bob=T["bob"](f), surge=T["surge"](f), pitch=T["pitch"](f), roll=0.03 * math.sin(0.4 * f) * smooth(f / 6) * smooth((22 - f) / 3)),
            "spine": (T["arch"](f), 0.0, 0.0),
            "legs": legs,
            "neck_pre": -0.6 * (T["pitch"](f) + 0.5 * T["arch"](f)),
            "head": (0.0, T["head"](f), 0.0),
            "tail_dirs": tail_dirs(elev, lat),
            "ears": ((T["ear"](f), 0.1), (T["ear"](f - 0.7), -0.1)),
        }
        return build_pose(rig, P, CFG_MID)

    return {"name": "Leap", "frames": n, "pose": pose, "loop": False, "priority": "Action",
            "keys": [0, 3, 5, 9, 14, 19, 21, 22], "markers": ((5 / 30, "Commit", "takeoff"), (19 / 30, "Recover", "land")),
            "brief": "leap"}


def pounce(rig, n=30):
    """The pounce, on the same frames as before: 0 to 11 the wind-up, crouched with the weight going back,
    the rear wiggling and the hind feet treading; 12 Commit (0.4 s): the hind legs fire and the body
    lunges, forepaws out and jaws open; 15 at full stretch; 17 the bite snaps shut as the forepaws pin;
    21 Recover (0.7 s): the hind feet land under it, the head worries the bite with a shake; 29 settled.
    The tail is flung up by the lunge and comes down late, a segment at a time."""
    T = {name: track(tab) for name, tab in dict(
        bob={0: -0.12, 6: -0.16, 11: -0.18, 13: -0.02, 15: 0.07, 17: 0.02, 21: -0.09, 25: -0.05, 29: -0.03},
        surge={0: 0.0, 6: 0.05, 11: 0.07, 13: -0.20, 15: -0.34, 17: -0.36, 21: -0.28, 29: 0.0},
        pitch={0: 0.06, 11: 0.09, 13: -0.20, 15: -0.10, 17: 0.10, 21: 0.12, 29: 0.03},
        arch={0: 0.08, 6: 0.28, 11: 0.38, 13: -0.08, 15: -0.34, 17: -0.10, 21: 0.22, 29: 0.14},
        fy={0: -0.02, 11: 0.0, 13: -0.30, 15: -0.52, 17: -0.50, 21: -0.38, 29: 0.0},
        fz={0: 0.0, 11: 0.0, 13: 0.24, 15: 0.20, 17: 0.05, 19: 0.0, 29: 0.0},
        fx={0: 0.0, 13: 0.05, 15: 0.07, 17: -0.02, 21: 0.0},
        fp={0: 0.9, 11: 1.0, 13: 1.3, 15: 0.9, 17: 0.9, 21: 0.95, 29: 0.8},
        ft={0: 0.15, 13: 0.9, 15: -0.2, 17: 0.5, 21: 0.2},
        hy={0: 0.0, 11: -0.08, 13: 0.55, 15: 0.86, 17: 0.60, 21: 0.10, 29: 0.0},
        hz={0: 0.0, 11: 0.0, 13: 0.0, 15: 0.10, 17: 0.12, 21: 0.0, 29: 0.0},
        hp={0: 0.15, 11: 0.12, 13: 1.35, 15: 2.1, 17: 1.5, 21: 0.4, 29: 0.2},
        ht={0: 0.1, 13: 0.15, 15: 1.8, 17: 1.0, 21: 0.15},
        tail={0: -0.05, 11: -0.14, 13: 0.10, 15: 0.42, 17: 0.60, 21: 0.15, 25: 0.36, 29: 0.30},
        head={0: 0.06, 11: 0.04, 15: -0.06, 17: 0.20, 21: 0.12, 29: -0.06},
        jaw={0: 0.0, 11: 0.05, 13: 0.35, 15: 0.62, 17: 0.0, 21: 0.06, 29: 0.0},
        ear={0: 0.15, 11: 0.2, 15: -0.5, 17: -0.5, 21: -0.2, 29: 0.0},
        neck={0: 0.3, 11: 0.3, 15: 0.0, 17: 0.1, 21: 0.15, 29: 0.0},
    ).items()}

    def pose(i, n):
        f = float(i)
        t = i / 30.0
        wig = math.sin(TAU * t / 0.18) * smooth((f - 1) / 3) * smooth((11 - f) / 2)  # the rear wiggle
        shake = math.sin(TAU * t / 0.12) * smooth((f - 20) / 2) * smooth((27 - f) / 3)
        legs = {}
        for leg in LEGS:
            pre = "f" if leg.startswith("Front") else "h"
            ff = f - (0.4 if leg.endswith("R") else 0.0)
            tg = toe_rest(leg) + np.array([T[pre + "x"](ff) * side(leg) if pre == "f" else 0.0, T[pre + "y"](ff), T[pre + "z"](ff)])
            if pre == "h":  # treading in place during the wiggle
                tg[2] += max(0.0, math.sin(TAU * t / 0.18 + (0 if leg == "BackL" else math.pi))) * 0.03 * smooth((f - 1) / 3) * smooth((10 - f) / 2)
            legs[leg] = (tg, T[pre + "p"](ff), T[pre + "t"](ff), 0.25 if pre == "f" else 0.4)
        elev = [T["tail"](f - 1.1 * k) + TAIL_STREAM[k] * 0.6 for k in range(8)]
        lat = [0.30 * math.sin(TAU * (t - 0.012 * k) / 0.18) * smooth((f - 1) / 3) * smooth((12 - f) / 2) * (k / 7) + 0.03 * k * math.sin(0.45 * (f - 1.2 * k)) for k in range(8)]
        P = {
            "body": dict(bob=T["bob"](f), surge=T["surge"](f), pitch=T["pitch"](f), roll=0.04 * shake),
            "spine": (T["arch"](f), 0.16 * wig, 0.0),
            "legs": legs,
            "neck_pre": T["neck"](f),
            "head": (0.22 * shake - 0.08 * wig, T["head"](f), 0.1 * shake),
            "tail_dirs": tail_dirs(elev, lat),
            "jaw": T["jaw"](f),
            "ears": ((T["ear"](f), 0.0), (T["ear"](f - 0.8), 0.0)),
        }
        return build_pose(rig, P, CFG_MID)

    return {"name": "Pounce", "frames": n, "pose": pose, "loop": False, "priority": "Action",
            "keys": [0, 6, 11, 13, 15, 17, 21, 25], "markers": ((0.4, "Commit", "lunge"), (0.7, "Recover", "land")),
            "brief": "pounce"}


def bite_dance(rig, n=63):
    """The bite dance (v5.4 animateBiteDance, 2.1 s): spin wiggle 0.78 sin 12t, roll 0.17 sin 15t,
    hops |sin 10t|, head 0.24 sin 7t, eased in and out over 1/6 s; plus paws waving, jaw chattering
    and the tail swishing. The paws hop round with the body (they are in the air as it turns), and the
    tail follows the spin late, the tip last."""
    pivot = np.array(PIVOT)

    def pose(i, n):
        t = i / 30.0
        k = max(0.0, min(1.0, 6 * t, 6 * (2.1 - t)))
        hop = abs(math.sin(10 * t)) * 0.16 * k
        spin = math.sin(12 * t) * 0.78 * k
        Rs = engine.Rz(spin)
        legs = {}
        for leg in LEGS:
            tg = toe_rest(leg).copy()
            tg = pivot + Rs @ (tg - pivot)
            lift = hop * (0.85 if leg.startswith("Back") else 1.0)
            if leg.startswith("Front"):
                lift += 0.07 * max(0.0, math.sin(10 * t + (0 if leg.endswith("L") else math.pi))) * k
            tg[2] += lift
            # the knee or elbow turns with the body too
            pl = Rs @ pole(leg)
            legs[leg] = (tg, (0.3 + 0.8 * hop) if leg.startswith("Back") else (0.8 + 2.0 * lift), 0.15 + 2 * hop, pl)
        # the tail in the model's frame: carried round by the spin a little late, the tip latest
        dirs = []
        for j in range(8):
            late = math.sin(12 * (t - 0.012 * j) - 0.25) * 0.78 * k
            e = TAIL_CURL[j] + 0.12 * k * math.sin(10 * t - 0.5 * j) * (1 + 0.5 * j / 7)
            swish = (0.10 + 0.05 * j) * k * math.sin(12 * t - 1.0 - 0.5 * j)
            dirs.append(np.array([-math.sin(late) * math.cos(e) + swish, math.cos(late) * math.cos(e), math.sin(e)]))
        P = {
            "body": dict(bob=hop, yaw=spin, roll=math.sin(15 * t) * 0.17 * k, pitch=-0.12 * k),
            "spine": (0.12 + 0.1 * k, 0.12 * math.sin(12 * t - 0.6) * k, 0.0),
            "legs": legs,
            "head": (math.sin(7 * t) * 0.24 * k + spin * 0.5, -0.12 * k, 0.1 * math.sin(15 * t) * k),
            "tail_dirs": dirs,
            "jaw": 0.18 * abs(math.sin(25 * t)) * k,
            "ears": ((0.2 * math.sin(14 * t) * k, 0.0), (0.2 * math.sin(14 * t + 1.0) * k, 0.0)),
        }
        return build_pose(rig, P, CFG)

    return {"name": "Bite", "frames": n, "pose": pose, "loop": False, "priority": "Action",
            "keys": [0, 8, 16, 26, 36, 46], "brief": "bite dance"}


def clips(rig, sp, variant):
    return [idle(rig), walk(rig), run(rig), climb(rig), wire(rig), leap(rig), pounce(rig), bite_dance(rig), stalk(rig)]
