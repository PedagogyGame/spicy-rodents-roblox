"""The townspeople's sculpts: signed-distance primitives and the grid that meshes each component.

Everything is in the Blender frame of spec.py (studs, +Z up, facing -Y, ground z = 0) and sculpted for
the LEFT side (x > 0); the builder mirrors the limbs. Each R15 part is a list of components
(Comp: a sculpt to mesh, an optional finer sculpt for the normal map, and a mesher.Chart).

Joints never open because both sides of a joint end in a ball about the joint's pivot, one inside the
other: the pelvis holds the thigh's ball, the thigh's knee ball holds the shin's, the trouser hem holds
the shoe's ankle ball, the arm's shoulder ball sits over the torso's yoke, the sleeve's elbow ball
holds the forearm's, the cuff holds the hand's wrist ball, and the neck is part of the head and turns
inside the collar. Hems and cuffs are cut flat so the inner ball shows as a shoe or a wrist.
"""
import math
import os
import sys

import numpy as np

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "heroes"))

import sdf  # noqa: E402  (tools/blender/heroes/sdf.py)
from sdf import Box, Ellipsoid, RoundCone  # noqa: E402

import mesher  # noqa: E402
from spec import J  # noqa: E402

F32 = np.float32


class Cylinder(sdf.Prim):
    """A capped cylinder along `axis` with rounded rims (hat bands, cap crowns)."""

    def __init__(self, c, axis, half, r, round=0.0, k=0.0, op="add", tag=""):
        self.c = np.asarray(c, dtype=np.float64)
        self.axis = mesher.unit(axis)
        self.half, self.r, self.round = float(half), float(r), float(round)
        self.k, self.op, self.tag = k, op, tag

    def bounds(self):
        e = self.r + self.half + self.round
        return self.c - e, self.c + e

    def dist(self, p):
        q = p - self.c.astype(F32)
        ax = self.axis.astype(F32)
        h = q @ ax
        rad = np.linalg.norm(q - h[..., None] * ax, axis=-1)
        dx = rad - F32(self.r - self.round)
        dy = np.abs(h) - F32(self.half - self.round)
        outside = np.sqrt(np.maximum(dx, 0) ** 2 + np.maximum(dy, 0) ** 2)
        return outside + np.minimum(np.maximum(dx, dy), 0) - F32(self.round)

    def mirrored(self):
        return Cylinder(self.c * [-1, 1, 1], self.axis * [-1, 1, 1], self.half, self.r, self.round, self.k, self.op, self.tag)


class Torus(sdf.Prim):
    """A ring of tube radius r and ring radius R about `axis`, squashed along the axis by `flat`."""

    def __init__(self, c, axis, R, r, flat=1.0, k=0.0, op="add", tag=""):
        self.c = np.asarray(c, dtype=np.float64)
        self.axis = mesher.unit(axis)
        self.R, self.r, self.flat = float(R), float(r), float(flat)
        self.k, self.op, self.tag = k, op, tag

    def bounds(self):
        e = self.R + self.r
        return self.c - e, self.c + e

    def dist(self, p):
        q = p - self.c.astype(F32)
        ax = self.axis.astype(F32)
        h = q @ ax
        rad = np.linalg.norm(q - h[..., None] * ax, axis=-1)
        return np.sqrt((rad - F32(self.R)) ** 2 + (h / F32(self.flat)) ** 2) - F32(self.r)

    def mirrored(self):
        return Torus(self.c * [-1, 1, 1], self.axis * [-1, 1, 1], self.R, self.r, self.flat, self.k, self.op, self.tag)


class Comp:
    def __init__(self, name, lo, chart, hi=None, drop_a=0, drop_b=0, cull=True):
        self.name = name
        self.lo = sdf.Body(lo, band=0.05)
        self.hi = sdf.Body(hi, band=0.05) if hi is not None else self.lo
        self.chart = chart
        chart.drop_a, chart.drop_b = drop_a, drop_b  # ring bands left out at each pole (always hidden)
        self.cull = cull
        self.fix = None  # optional fn(V) -> V applied to the cast vertices (hair tucks its edge into the head)


def v(*p):
    return np.array(p, dtype=np.float64)


def below(z, k=0.012, x=0.0, y=0.0):
    """Subtract everything under the plane at height z (a flat hem, cuff or sole)."""
    return Box((x, y, z - 1.0), (3.0, 3.0, 1.0), k=k, op="sub")


def above(z, k=0.012):
    return Box((0, 0, z + 1.0), (3.0, 3.0, 1.0), k=k, op="sub")


# ---- torso ---------------------------------------------------------------------------------------

SHOULDER_BALL = v(1.08, 0.0, 3.763)  # the arm's ball: 0.08 outboard of the stock shoulder pivot


def upper_torso(b):
    cw, cd, ww, wd, bel = b["chest_w"], b["chest_d"], b["waist_w"], b["waist_d"], b["belly"]
    yk, yr = b["yoke"], b["yoke_r"]
    p = [
        Ellipsoid((0, 0.0, b["chest_z"]), (cw, cd, 0.60)),
        Ellipsoid((0, -bel * 0.55, 2.82), (ww, wd, 0.52), k=0.30),  # waist, belly
        Ellipsoid((0, -bel * 0.3, 2.44), (ww * 0.97, wd * 0.95, 0.30), k=0.18),  # the ball inside the trousers
        RoundCone((-yk, 0.02, 3.82), (yk, 0.02, 3.82), yr, yr, k=0.22),  # shoulder yoke: its ends cap the arm balls
        RoundCone((-0.36, 0.05, 3.92), (0.36, 0.05, 3.92), 0.19, 0.19, k=0.22),  # the slope up to the neck
        Ellipsoid((0, 0.02, 4.0), (0.31, 0.295, 0.12), k=0.08),  # collar stand round the neck
        Ellipsoid((0, -cd * 0.62, b["chest_z"] + 0.02), (cw * 0.72, cd * 0.5, 0.3), k=0.25),  # chest fullness
    ]
    top = v(0, 0.02, 3.84)
    rings = [(top, 0.0), (top, 32.0), (top, 56.0), (top, 76.0)]
    rings += [(v(0, 0, z), 90.0) for z in (3.82, 3.62, 3.40, 3.15, 2.90, 2.68, 2.50)]
    rings += [(v(0, 0, 2.44), 112.0), (v(0, 0, 2.44), 135.0), (v(0, 0, 2.44), 180.0)]
    ch = mesher.ring_stack("UpperTorso", rings, seam=(0, 1, 0), phis=np.arange(20) * 18.0)
    return [Comp("main", p, ch, drop_b=1)]


def lower_torso(b):
    hr, pw, pd = b["hip_r"], b["pelvis_w"], b["pelvis_d"]
    hip = J["LeftHip"]
    lobe = Ellipsoid(hip, (hr - 0.03,) * 3, k=0.1)  # what the thigh's ball turns on (always inside it)
    p = [Ellipsoid((0, -b["belly"] * 0.2, 2.37), (pw, pd, 0.50)), lobe, lobe.mirrored(), above(2.56, k=0.05)]
    o = v(0, 0, 2.12)
    rings = [(v(0, 0, 2.40), 0.0)]
    rings += [(v(0, 0, z), 90.0) for z in (2.53, 2.42, 2.28)]
    rings += [(o, 90.0), (o, 112.0), (o, 134.0), (o, 157.0), (o, 180.0)]
    ch = mesher.ring_stack("LowerTorso", rings, seam=(0, 1, 0), phis=np.arange(16) * 22.5)
    return [Comp("main", p, ch)]


# ---- legs ----------------------------------------------------------------------------------------

def upper_leg(b):
    hip, knee = v(*J["LeftHip"]), v(*J["LeftKnee"])
    hr = b["hip_r"]
    p = [
        Ellipsoid(hip, (hr, hr, hr)),  # the hip: a ball over the pelvis, so the seat moves with the leg
        RoundCone(hip - v(0, 0, 0.12), knee, b["thigh"], b["knee"], k=0.14),
        Ellipsoid((0.5, 0.07, 1.98), (hr * 0.9, hr * 0.98, hr * 0.92), k=0.1),  # the seat
    ]
    ch = mesher.capsule("UpperLeg", hip, knee, seam=(-1, 0, 0), ncols=12, caps_a=[30, 60, 90], mids=[0.22, 0.46, 0.72],
                        caps_b=[30, 60, 90])
    return [Comp("main", p, ch)]


def lower_leg(b):
    knee, ank = J["LeftKnee"], J["LeftAnkle"]
    hem = b["ankle"]
    p = [
        RoundCone(knee, ank, b["shin"], hem),
        Ellipsoid((0.5, 0.06, 0.84), (b["calf"] * 0.86, b["calf"] * 0.9, 0.30), k=0.15),
        below(ank[2] - 0.13),
    ]
    ch = mesher.capsule("LowerLeg", knee, ank, seam=(-1, 0, 0), ncols=12, caps_a=[90], mids=[0.2, 0.42, 0.65, 0.85],
                        caps_b=[27, 49, 90])
    return [Comp("main", p, ch, drop_a=1)]


def foot(b, detail=False):
    s = b["shoe"]
    ank = J["LeftAnkle"]
    ax = ank[0]
    p = [
        Ellipsoid(ank, (0.186, 0.186, 0.186)),  # the ball inside the trouser hem
        RoundCone((ax, 0.11, 0.175), (ax, -0.34, 0.16), 0.175 * s, 0.16 * s, k=0.07),
        Ellipsoid((ax + 0.012, -0.40, 0.15), (0.21 * s, 0.24, 0.15), k=0.08),  # toe box, wider at the ball of the foot
        Ellipsoid((ax, 0.115, 0.185), (0.18 * s, 0.175, 0.185), k=0.06),  # heel counter
        below(0.0, k=0.014),
    ]
    a, bb = v(ax, 0.12, 0.17), v(ax, -0.46, 0.145)
    ch = mesher.capsule("Foot", a, bb, seam=(0, 0, -1), ncols=12, caps_a=[35, 65, 90],
                        mids=[0.1, 0.21, 0.35, 0.5, 0.67, 0.85], caps_b=[30, 60, 90],
                        phis=[0, 36, 56, 78, 106, 140, 180, 220, 254, 282, 304, 324])
    return [Comp("main", p, ch)]


# ---- arms ----------------------------------------------------------------------------------------

def upper_arm(b):
    el = J["LeftElbow"]
    c = SHOULDER_BALL
    p = [
        Ellipsoid(c, (b["shoulder"],) * 3),
        RoundCone(c - v(0, 0, 0.06), el, b["uarm"], b["elbow"], k=0.1),
    ]
    ch = mesher.capsule("UpperArm", c, el, seam=(-1, 0, 0), ncols=10, caps_a=[30, 60, 90], mids=[0.34, 0.68],
                        caps_b=[30, 60, 90])
    return [Comp("main", p, ch)]


def lower_arm(b):
    el, wr = J["LeftElbow"], J["LeftWrist"]
    p = [
        RoundCone(el, wr, b["farm"], b["wrist"]),
        Ellipsoid((el[0] + 0.005, 0.01, 2.80), (b["farm"] * 0.98, b["farm"] * 1.04, 0.3), k=0.12),
        below(wr[2] - 0.09),
    ]
    ch = mesher.capsule("LowerArm", el, wr, seam=(-1, 0, 0), ncols=10, caps_a=[90], mids=[0.24, 0.52, 0.8],
                        caps_b=[30, 53, 90])
    return [Comp("main", p, ch, drop_a=1)]


HAND_TURN = math.radians(-24)  # the relaxed hand: palm toward the thigh and a little to the back


def hand(b, detail=False):
    s = b["hand"]
    wr = v(*J["LeftWrist"])
    R = sdf.rot_z(HAND_TURN)

    def at(dx, dy, dz):
        return wr + R @ (v(dx, dy, dz) * s)

    ball = Ellipsoid(wr, (0.14,) * 3)
    palm = Ellipsoid(at(-0.005, -0.015, -0.22), v(0.092, 0.165, 0.175) * s, axes=R, k=0.06)
    mitt = Ellipsoid(at(-0.024, -0.02, -0.385), v(0.082, 0.155, 0.158) * s, axes=R, k=0.07)
    lo = [ball, palm, mitt]
    hi = [ball, palm]
    # four fingers, slightly curled toward the palm (-x), index in front (-y)
    for dy, ln, r in ((-0.118, 0.02, 0.041), (-0.042, 0.035, 0.044), (0.036, 0.022, 0.042), (0.108, -0.01, 0.037)):
        hi.append(RoundCone(at(-0.008, dy, -0.33), at(-0.042, dy * 0.96, -0.505 - ln), r * s, r * 0.86 * s, k=0.022))
    tb, tt = at(-0.03, -0.125, -0.17), at(-0.08, -0.215, -0.335)
    thumb = [RoundCone(tb, tt, 0.056 * s, 0.046 * s)]
    a, bb = wr, at(-0.018, -0.02, -0.40)
    t = np.arange(12) * (2 * math.pi / 12)
    phis = np.degrees(np.arctan2(0.09 * np.sin(t), 0.16 * np.cos(t))) % 360
    ch = mesher.capsule("Hand", a, bb, seam=R @ v(0, 1, 0), ncols=12, caps_a=[58, 90], mids=[0.3, 0.55, 0.8],
                        caps_b=[30, 60, 90], phis=phis)
    cht = mesher.capsule("Thumb", tb, tt, seam=(1, 0, 0), ncols=6, caps_a=[90], mids=[0.5], caps_b=[45, 90])
    return [Comp("main", lo, ch, hi=hi, drop_a=1), Comp("thumb", thumb, cht, drop_a=1)]


# ---- head ----------------------------------------------------------------------------------------

HEAD_C = v(0.0, 0.0, 4.80)  # the globe's centre
SKULL = ((0.0, 0.03, 4.90), (0.588, 0.612, 0.532))  # hair is sculpted round this
FACE = dict(eye_x=0.215, eye_z=4.85, brow_z=5.01, nose_z=4.70, mouth_z=4.49, chin_z=4.33)

# column azimuths from the front (deg): close together over the nose, wide round the back
_FRONT = [0, 7, 14, 22, 31, 42, 55, 70, 87, 105, 124, 144, 163]
HEAD_PHIS = sorted({(180 + a) % 360 for a in _FRONT} | {(180 - a) % 360 for a in _FRONT} | {0.0})
HEAD_THETAS = [14, 28, 42, 54, 64, 72, 80, 87, 93, 98, 104, 110, 117, 125, 134, 144, 156, 168]


def head(detail=False):
    cheek = Ellipsoid((0.27, -0.33, 4.58), (0.22, 0.2, 0.21), k=0.2)
    jaw = Ellipsoid((0.3, -0.12, 4.44), (0.2, 0.26, 0.17), k=0.2)
    nostril = Ellipsoid((0.062, -0.635, 4.672), (0.045, 0.055, 0.04), k=0.045)
    brow = RoundCone((0.09, -0.53, 5.0), (0.3, -0.45, 4.995), 0.04, 0.036, k=0.18)
    socket = Ellipsoid((FACE["eye_x"], -0.715, FACE["eye_z"]), (0.14, 0.1, 0.125), k=0.1, op="sub")
    p = [
        Ellipsoid(*SKULL),
        Ellipsoid((0, -0.04, 4.63), (0.545, 0.525, 0.43), k=0.22),  # the lower face
        cheek, cheek.mirrored(), jaw, jaw.mirrored(),
        Ellipsoid((0, -0.40, 4.335), (0.21, 0.16, 0.135), k=0.16),  # chin
        brow, brow.mirrored(),
        RoundCone((0, -0.575, 4.88), (0, -0.635, 4.76), 0.035, 0.05, k=0.12),  # bridge of the nose
        Ellipsoid((0, -0.655, 4.705), (0.088, 0.095, 0.082), k=0.06),  # a round button nose
        nostril, nostril.mirrored(),
        Ellipsoid((0, -0.49, 4.50), (0.22, 0.13, 0.12), k=0.14),  # the mouth's mound
        socket, socket.mirrored(),
    ]
    hi = None
    if detail:
        hole = Ellipsoid((0.045, -0.68, 4.642), (0.02, 0.03, 0.014), k=0.02, op="sub")
        hi = p + [
            hole, hole.mirrored(),
            RoundCone((0, -0.655, 4.60), (0, -0.65, 4.56), 0.018, 0.024, k=0.03, op="sub"),  # philtrum
            Ellipsoid((0, -0.565, 4.405), (0.1, 0.05, 0.035), k=0.05, op="sub"),  # under the lip
        ]
    ch = mesher.globe("Head", HEAD_C, pole=(0, 0, 1), seam=(0, 1, 0), thetas=HEAD_THETAS, phis=HEAD_PHIS,
                      emphasis=lambda ph: 1.55 if abs(ph - 180) < 62 else 1.0)
    neck_j = v(*J["Neck"])
    neck = [RoundCone(neck_j, (0, 0.035, 4.5), 0.225, 0.22)]
    chn = mesher.capsule("Neck", v(0, 0.03, 4.44), neck_j, seam=(0, 1, 0), ncols=10, caps_a=[90], mids=[0.55],
                         caps_b=[58, 90])
    comps = [Comp("skull", p, ch, hi=hi, drop_b=2), Comp("neck", neck, chn, drop_a=1, drop_b=1)]
    for side, sx in (("L", 1), ("R", -1)):
        c = v(0.585 * sx, 0.08, 4.75)
        axes = sdf.rot_z(math.radians(-26 * sx)) @ sdf.rot_y(math.radians(8 * sx))
        out = axes @ np.array([sx * 1.0, 0, 0])
        ear = [Ellipsoid(c, (0.07, 0.12, 0.17), axes=axes)]
        ehi = None
        if detail:
            ehi = ear + [Ellipsoid(c + out * 0.07 + v(0, -0.012, 0.0), (0.045, 0.07, 0.11), axes=axes, k=0.03, op="sub")]
        che = mesher.globe("Ear" + side, c, pole=out, seam=(0, 0, 1), thetas=[42, 82, 118], phis=np.arange(8) * 45.0)
        comps.append(Comp("ear" + side, ear, che, hi=ehi, drop_b=1))
    return comps


# ---- extras: coat tails, V neck, stethoscope ---------------------------------------------------------

def coat_tail(b):
    """The coat's skirt on one thigh: a shell round the top of the thigh that swings with it, so the
    legs never push through the coat."""
    hip, knee = v(*J["LeftHip"]), v(*J["LeftKnee"])
    r = b["hip_r"] + 0.04
    p = [Ellipsoid(hip, (r, r, r)), RoundCone(hip, hip + (knee - hip) * 0.7, r - 0.01, b["thigh"] + 0.075, k=0.05),
         Ellipsoid((0.5, 0.075, 1.98), (r * 0.9, r * 0.98, r * 0.92), k=0.1), below(hip[2] - 0.5, k=0.016)]
    ch = mesher.capsule("CoatTail", hip, hip + (knee - hip) * 0.56, seam=(-1, 0, 0), ncols=12, caps_a=[35, 65, 90],
                        mids=[0.4, 0.8], caps_b=[30, 52, 90])
    return [Comp("main", p, ch, drop_a=1)]


# ---- hair and hats -------------------------------------------------------------------------------
# A hair style is a grid over the skull whose last ring IS the hairline: each column's rings run from
# the crown to that column's hairline angle, so the edge of the hair is a clean line however coarse
# the grid, and one more ring tucks the edge into the head. The outer surface is cast on the style's
# sculpt (the skull grown by the hair's thickness plus the style's masses).

HAIR_C = v(0.0, 0.03, 4.88)
HAIR_PHIS = [0, 22, 44, 66, 86, 104, 120, 134, 147, 159, 170, 180, 190, 201, 213, 226, 240, 256, 274, 294, 316, 338]
_HEAD_BODY = None


def head_body():
    global _HEAD_BODY
    if _HEAD_BODY is None:
        comps = head()
        _HEAD_BODY = sdf.Body(comps[0].lo.prims + [RoundCone(v(*J["Neck"]), (0, 0.035, 4.5), 0.225, 0.22, k=0.03)], band=0.05)
    return _HEAD_BODY


def _skull(grow, k=0.0, dz=0.0, dy=0.0):
    (cx, cy, cz), (rx, ry, rz) = SKULL
    return Ellipsoid((cx, cy + dy, cz + dz), (rx + grow, ry + grow, rz + grow), k=k)


def _line(points, side=None):
    """Hairline: polar angle (deg from the crown) against the angle from the front (deg, 0 = front,
    180 = back; positive = the person's left). points [(psi, theta)] for the left; `side` overrides
    the right-hand side for an asymmetric style."""
    def fn(psi):
        psi = np.asarray(psi, dtype=np.float64)
        left = np.interp(np.abs(psi), [q[0] for q in points], [q[1] for q in points])
        if side is None:
            return left
        right = np.interp(np.abs(psi), [q[0] for q in side], [q[1] for q in side])
        return np.where(psi >= 0, left, right)
    return fn


def _hair_comp(name, volume, line, ts=(0.22, 0.42, 0.6, 0.76, 0.89, 1.0), top=None, tuck=0.04, phis=None, centre=None):
    centre = HAIR_C if centre is None else centre
    phis = np.asarray(HAIR_PHIS if phis is None else phis, dtype=np.float64)
    psi = (phis - 180.0 + 180.0) % 360.0 - 180.0  # 0 at the front; the seam (phi 0) is the back
    psi = -psi  # phi grows from the back toward the person's right
    th = line(psi)
    fr = mesher.frame((0, 0, -1), (0, 1, 0))
    if top is None:
        rings = [(centre, 0.0)] + [(centre, th * t) for t in ts] + [(centre, th + 1.5), (centre, 180.0)]
        tucked = [len(ts) + 1]
        drop_a = 0
    else:  # a band (the top of the head is bare)
        t0 = top(psi)
        rings = [(centre, 0.0), (centre, t0 - 1.5)] + [(centre, t0 + (th - t0) * t) for t in ts]
        rings += [(centre, th + 1.5), (centre, 180.0)]
        tucked = [1, len(ts) + 2]
        drop_a = 1
    ch = mesher.Chart(name, fr, rings, phis, tmax=1.9)
    if top is not None:
        ch.col_on = (th - top(psi)) > 4.0
    comp = Comp("main", volume, ch, drop_a=drop_a, drop_b=1, cull=False)

    def fix(V):
        O, D = ch.rays()
        for r in tucked:
            ids = ch.ring_ids(r)
            t = mesher.cast(head_body(), O[ids], D[ids], 1.9)
            V[ids] = (O[ids] + D[ids] * (t - tuck)[:, None]).astype(F32)
        return V

    comp.fix = fix
    return comp


# hairlines: (angle from the front, angle down from the crown)
_L_SHORT = [(0, 57), (28, 56), (48, 64), (62, 82), (74, 95), (84, 88), (96, 82), (110, 90), (126, 112), (150, 121), (180, 123)]
_L_BACK = [(0, 53), (30, 53), (50, 62), (63, 80), (74, 93), (84, 87), (96, 82), (110, 90), (126, 112), (150, 121), (180, 123)]


def hair(style, detail=False):
    if style == "short":
        vol = [_skull(0.05), Ellipsoid((0, -0.2, 5.3), (0.42, 0.36, 0.2), k=0.14)]
        return [_hair_comp("Hair_short", vol, _line(_L_SHORT))]
    if style == "parted":
        vol = [_skull(0.065), Ellipsoid((0.14, -0.2, 5.3), (0.48, 0.44, 0.24), k=0.16),  # swept to the person's left
               Ellipsoid((0.3, -0.42, 5.12), (0.22, 0.2, 0.15), k=0.1)]
        left = [(0, 64), (22, 70), (42, 72), (58, 84), (72, 96), (84, 88), (96, 82), (110, 90), (126, 112), (150, 121), (180, 123)]
        right = [(0, 64), (20, 56), (44, 60), (60, 80), (73, 95), (84, 88), (96, 82), (110, 90), (126, 112), (150, 121), (180, 123)]
        return [_hair_comp("Hair_parted", vol, _line(left, right))]
    if style == "bob":
        vol = [_skull(0.085), Ellipsoid((0, 0.1, 4.62), (0.665, 0.62, 0.44), k=0.2),  # the sides and back, to the jaw
               Ellipsoid((0, -0.38, 5.16), (0.47, 0.28, 0.2), k=0.1)]  # the fringe
        line = _line([(0, 70), (30, 70), (41, 74), (50, 122), (60, 133), (100, 136), (180, 137)])
        return [_hair_comp("Hair_bob", vol, line, ts=(0.16, 0.32, 0.47, 0.6, 0.72, 0.83, 0.93, 1.0))]
    if style == "ponytail":
        vol = [_skull(0.05), Ellipsoid((0, -0.14, 5.3), (0.46, 0.4, 0.2), k=0.14)]
        tail = [Ellipsoid((0, 0.62, 5.04), (0.13, 0.12, 0.12)),
                RoundCone((0, 0.70, 4.98), (0, 0.80, 4.52), 0.14, 0.065, k=0.08)]
        cht = mesher.capsule("Hair_ponytail_tail", v(0, 0.69, 5.03), v(0, 0.795, 4.55), seam=(0, -1, 0), ncols=8,
                             caps_a=[45, 90], mids=[0.35, 0.7], caps_b=[50, 90])
        return [_hair_comp("Hair_ponytail", vol, _line(_L_BACK)), Comp("tail", tail, cht, cull=False)]
    if style == "curly":
        vol = [_skull(0.13, dz=0.04)]
        line = _line([(0, 62), (30, 62), (48, 70), (62, 88), (76, 104), (96, 108), (120, 116), (150, 122), (180, 124)])
        return [_hair_comp("Hair_curly", vol, line)]
    if style == "bun":
        vol = [_skull(0.045), Ellipsoid((0, -0.12, 5.3), (0.44, 0.4, 0.19), k=0.14)]
        bun = [Ellipsoid((0, 0.47, 5.36), (0.2, 0.19, 0.17))]
        chb = mesher.globe("Hair_bun_bun", v(0, 0.47, 5.36), pole=(0, 0.55, 0.83), seam=(0, -1, 0.3),
                           thetas=[40, 80, 120], phis=np.arange(8) * 45.0)
        return [_hair_comp("Hair_bun", vol, _line(_L_BACK)), Comp("bun", bun, chb, drop_b=1, cull=False)]
    if style == "balding":
        vol = [_skull(0.045)]
        line = _line([(0, 80), (56, 80), (66, 86), (76, 96), (86, 88), (98, 83), (110, 90), (126, 112), (150, 121), (180, 123)])
        top = _line([(0, 80), (56, 80), (66, 66), (90, 56), (130, 50), (180, 48)])
        return [_hair_comp("Hair_balding", vol, line, ts=(0.0, 0.3, 0.6, 0.85, 1.0), top=top)]
    if style == "long":
        vol = [_skull(0.075), Ellipsoid((0, 0.2, 4.62), (0.63, 0.53, 0.5), k=0.22),  # falls behind the ears
               Ellipsoid((0, 0.34, 4.34), (0.5, 0.31, 0.36), k=0.2),
               Ellipsoid((-0.16, -0.3, 5.26), (0.42, 0.32, 0.2), k=0.1)]
        left = [(0, 62), (26, 60), (44, 64), (56, 84), (66, 108), (80, 132), (110, 146), (180, 150)]
        right = [(0, 62), (22, 66), (42, 70), (55, 86), (66, 108), (80, 132), (110, 146), (180, 150)]
        return [_hair_comp("Hair_long", vol, _line(left, right), ts=(0.14, 0.28, 0.42, 0.55, 0.67, 0.78, 0.88, 0.95, 1.0))]
    raise KeyError(style)


def hat(name, detail=False):
    if name == "cap":
        # the peaked cap: a band, a crown that flares to a flat top tilted up at the front, a peak
        ax = sdf.rot_x(math.radians(-8)) @ np.array([0, 0, 1.0])
        p = [
            Ellipsoid((0, 0.03, 5.2), (0.648, 0.672, 0.26)), below(5.105, k=0.012), above(5.31, k=0.012),
            Cylinder((0, -0.01, 5.42), ax, 0.07, 0.80, round=0.065, k=0.13),
            Ellipsoid((0, 0.02, 5.38), (0.72, 0.74, 0.14), k=0.1),
        ]
        o1, o2 = v(0, 0.0, 5.38), v(0, 0.03, 5.14)
        rings = [(o1, 0.0), (o1, 35.0), (o1, 62.0), (o1, 81.0), (o1, 96.0), (v(0, 0.03, 5.27), 90.0), (o2, 90.0),
                 (o2, 150.0), (o2, 180.0)]
        ch = mesher.ring_stack("Hat_cap", rings, seam=(0, 1, 0), phis=np.arange(18) * 20.0)
        peak = [Ellipsoid((0, -0.72, 5.085), (0.47, 0.31, 0.034), axes=sdf.rot_x(math.radians(-15)))]
        chp = mesher.capsule("Hat_cap_peak", v(0.37, -0.70, 5.09), v(-0.37, -0.70, 5.09), seam=(0, 1, 0), ncols=8,
                             caps_a=[60, 90], mids=[0.25, 0.5, 0.75], caps_b=[60, 90], phis=[0, 60, 150, 172, 188, 210, 270, 330])
        return [Comp("main", p, ch, cull=False), Comp("peak", peak, chp, cull=False)]
    if name == "beret":
        p = [
            Ellipsoid((0.07, 0.07, 5.39), (0.71, 0.73, 0.15), axes=sdf.rot_y(math.radians(-9))),
            Ellipsoid((0, 0.03, 5.27), (0.64, 0.665, 0.16), k=0.08), below(5.17, k=0.012),
            Ellipsoid((0.0, 0.03, 5.565), (0.035, 0.035, 0.05), k=0.03),  # the stalk
        ]
        o1, o2 = v(0.03, 0.04, 5.39), v(0, 0.03, 5.22)
        rings = [(o1, 0.0), (o1, 12.0), (o1, 40.0), (o1, 68.0), (o1, 92.0), (o1, 114.0), (o2, 90.0), (o2, 150.0), (o2, 180.0)]
        ch = mesher.ring_stack("Hat_beret", rings, seam=(0, 1, 0), phis=np.arange(16) * 22.5)
        return [Comp("main", p, ch, cull=False)]
    raise KeyError(name)


# ---- the whole body --------------------------------------------------------------------------------

def body_parts(b, detail=False):
    """The left-side and midline parts of a build: {short name: [Comp]}."""
    return {
        "UpperTorso": upper_torso(b),
        "LowerTorso": lower_torso(b),
        "UpperArm": upper_arm(b),
        "LowerArm": lower_arm(b),
        "Hand": hand(b, detail),
        "UpperLeg": upper_leg(b),
        "LowerLeg": lower_leg(b),
        "Foot": foot(b, detail),
        "CoatTail": coat_tail(b),
    }
