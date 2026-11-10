"""Squirrel (and spicy rodent) anatomy: skeleton joints and the signed-distance sculpt.

Blender coordinates, studs: ground z = 0, the animal faces -Y, its left side is +X, Root at the
origin under the middle of the body. About 1.2 studs at the shoulder (brief v2 §15, RigSpec), 2.0 from
nose to rump, the tail about as long again. Bone names are RigSpec.squirrel's, exactly.

The rodent (variant="rodent") is the same skeleton (so every clip is shared): the same animal gone
wrong, a blend the owner asked for after a harsher version ("too edgy ... combine those two back
together"): a little leaner, a ragged right ear, a lower head with crooked buck teeth, slightly
oversized glowing eyes, one small bald scar on a flank, a ruffle of raised fur along the spine and a
slightly ragged tail with an ember-rust fringe. No ribs, stitches, mange or blood beyond the mouth corner.

Proportions (owner 2026-11-10: "squirrels legs definitely a bit too tall and big"): the anatomy below is
authored standing 1.2 studs at the shoulder, and everything is then LOWERED: what is above LEG_TOP comes
down by DROP and what is below it (the legs) is squeezed to fit, so the belly rides about 0.25 studs off
the ground and the shoulder is about 0.93. The authored numbers (TAIL0, FRONT0, BACK0 and every literal
in sculpt) stay in the authored space; everything this module hands out (skeleton, sculpt, FRONT, BACK,
TAIL, landmarks, eye centres, hard parts, sockets) is in the lowered space, and the painters convert the
surface points they are given back to the authored space before using authored heights.
"""
import math

import numpy as np

from sdf import Ellipsoid, RoundCone, frame_from, mirror_pair, rot_x, rot_y, rot_z

LEG_TOP = 0.62  # authored height where the legs meet the body
DROP = 0.27  # how far the body comes down
LEG_K = (LEG_TOP - DROP) / LEG_TOP  # the legs' squeeze
LEG_GIRTH = 0.86  # and they are a little slimmer


def zw(z):
    """Authored height -> lowered height (numbers or arrays)."""
    z = np.asarray(z, dtype=np.float64)
    return np.where(z < LEG_TOP, z * LEG_K, z - DROP)


def zu(z):
    """Lowered height -> authored height."""
    z = np.asarray(z, dtype=np.float64)
    return np.where(z < LEG_TOP * LEG_K, z / LEG_K, z + DROP)


def W(p):
    """An authored point, lowered."""
    q = np.array(p, dtype=np.float64)
    q[..., 2] = zw(q[..., 2])
    return q


def U(P):
    """Lowered surface points (n, 3) back in the authored space."""
    Q = np.array(P, dtype=np.float64)
    Q[:, 2] = zu(Q[:, 2])
    return Q.astype(np.asarray(P).dtype)


SPECIES = "squirrel"
RIG_ID = "squirrel"  # the rodent shares the rig and every clip
CLIPS_MODULE = "clips_squirrel"

# ---- skeleton (bone head positions) ---------------------------------------------------------------
# name: (head xyz, parent, proxy tail xyz or a child name the proxy bone points at)
TAIL0 = [
    (0.0, 0.60, 0.97),
    (0.0, 0.78, 1.06),
    (0.0, 0.96, 1.14),
    (0.0, 1.15, 1.20),
    (0.0, 1.35, 1.24),
    (0.0, 1.55, 1.26),
    (0.0, 1.75, 1.26),
    (0.0, 1.94, 1.24),
    (0.0, 2.12, 1.21),  # tip (end of Tail8)
]

FRONT0 = {  # left side (+X); right is mirrored
    "Upper": (0.15, -0.46, 0.76),  # shoulder joint
    "Lower": (0.15, -0.36, 0.47),  # elbow (points back)
    "Foot": (0.14, -0.49, 0.12),  # wrist
    "Toe": (0.14, -0.585, 0.034),  # knuckles
    "End": (0.14, -0.67, 0.012),  # finger tips
}
BACK0 = {
    "Upper": (0.17, 0.36, 0.84),  # hip joint
    "Lower": (0.215, 0.06, 0.44),  # knee (points forward, inside the haunch)
    "Foot": (0.19, 0.38, 0.10),  # hock (heel, a little off the ground)
    "Toe": (0.18, 0.0, 0.032),  # ball of the foot
    "End": (0.18, -0.12, 0.012),  # toe tips
}


# what other modules (the clips' IK) read: the lowered tables
TAIL = [tuple(W(p)) for p in TAIL0]
FRONT = {k: tuple(W(v)) for k, v in FRONT0.items()}
BACK = {k: tuple(W(v)) for k, v in BACK0.items()}


def skeleton():
    """[(name, head, parent, proxy_tail)] in RigSpec order. Proxy tails are where the anatomical
    segment ends (used for heat weights and for the clip IK), not the exported bone's tail."""
    J = []

    def add(name, head, parent, tail):
        J.append((name, tuple(float(c) for c in head), parent, tuple(float(c) for c in tail)))

    add("Root", (0, 0, 0), None, (0, 0, 0.3))
    add("Hips", (0, 0.40, 1.02), "Root", (0, 0.18, 1.06))
    add("Spine1", (0, 0.18, 1.06), "Hips", (0, -0.04, 1.05))
    add("Spine2", (0, -0.04, 1.05), "Spine1", (0, -0.24, 1.03))
    add("Spine3", (0, -0.24, 1.03), "Spine2", (0, -0.44, 0.99))
    add("Chest", (0, -0.44, 0.99), "Spine3", (0, -0.60, 1.02))
    add("Neck", (0, -0.60, 1.02), "Chest", (0, -0.74, 1.12))
    add("Head", (0, -0.74, 1.12), "Neck", (0, -1.15, 1.09))
    add("Jaw", (0, -0.86, 1.04), "Head", (0, -1.07, 1.00))
    add("EarL", (0.11, -0.80, 1.33), "Head", (0.13, -0.78, 1.45))
    add("EarR", (-0.11, -0.80, 1.33), "Head", (-0.13, -0.78, 1.45))
    for i in range(8):
        add(f"Tail{i + 1}", TAIL0[i], "Hips" if i == 0 else f"Tail{i}", TAIL0[i + 1])
    for leg, spec, parent in (("Front", FRONT0, "Chest"), ("Back", BACK0, "Hips")):
        for side, sx in (("L", 1), ("R", -1)):
            segs = ["Upper", "Lower", "Foot", "Toe"]
            for i, seg in enumerate(segs):
                h = np.array(spec[seg]) * [sx, 1, 1]
                t = np.array(spec[segs[i + 1]] if i < 3 else spec["End"]) * [sx, 1, 1]
                add(f"{leg}{side}_{seg}", h, parent if i == 0 else f"{leg}{side}_{segs[i - 1]}", t)
    return [(name, tuple(W(head)), parent, tuple(W(tail))) for name, head, parent, tail in J]


HZ = 1.19  # skull centre height
EYE_L = np.array([0.110, -0.93, 1.245])
EYE_R_RODENT = 0.066
EYE_R = 0.058  # a touch larger than life: the face is what players look at
NOSE = np.array([0.0, -1.165, 1.10])


def eye_radius(variant):
    return EYE_R_RODENT if variant == "rodent" else EYE_R


def eye_gaze(side):
    return np.array([side * 0.86, -0.48, 0.16])


EYE_STYLE = "squirrel"


def _eye0(variant, side=1):
    c = EYE_L.copy()
    if variant == "rodent":
        c = c + [0.012, 0.004, -0.026]  # the rodent carries its head lower; its eyes bulge a little
    c[0] *= side
    return c


def eye_centre(variant, side=1):
    """Where the eyeball sits (lowered space)."""
    return W(_eye0(variant, side))


def landmarks(variant):
    """Named points the texture painter and the card scatterer use (authored space)."""
    dz = -0.03 if variant == "rodent" else 0.0
    return {
        "nose": NOSE + [0, 0, dz],
        "eyeL": _eye0(variant, 1),
        "eyeR": _eye0(variant, -1),
        "chin": np.array([0.0, -1.05, 1.00 + dz]),
        "earL": np.array([0.12, -0.79, 1.41 + dz]),
        "earR": np.array([-0.12, -0.79, 1.41 + dz]),
        "tailTip": np.array(TAIL0[-1]),
        "tailRoot": np.array(TAIL0[0]),
    }


def _limb(a, b, ra, rb, k, tag=""):
    return RoundCone(a, b, ra, rb, k=k, tag=tag)


def sculpt(variant="squirrel"):
    """The SDF primitive list (left/right pairs mirrored)."""
    rodent = variant == "rodent"
    lean = 0.93 if rodent else 1.0  # the rodent is a little leaner through the waist and belly
    dz = -0.03 if rodent else 0.0  # and carries its head low
    P = []
    # --- torso: rib cage, belly, pelvis, the dorsal line and the chest -----------------------------
    P.append(Ellipsoid((0, -0.25, 0.83), (0.25, 0.35, 0.31), tag="ribs"))
    P.append(Ellipsoid((0, 0.08, 0.82), (0.24 * lean, 0.30, 0.29 * lean), k=0.12, tag="belly"))
    P.append(Ellipsoid((0, 0.36, 0.88), (0.255, 0.28, 0.31), k=0.10, tag="pelvis"))
    # the dorsal line arches: highest over the loins, lower at the withers and the croup
    P.append(RoundCone((0, 0.46, 1.03), (0, 0.10, 1.07), 0.16, 0.165, k=0.12, tag="back"))
    P.append(RoundCone((0, 0.10, 1.07), (0, -0.44, 0.98), 0.165, 0.16, k=0.12, tag="back"))
    P.append(Ellipsoid((0, -0.50, 0.78), (0.17, 0.15, 0.22), k=0.08, tag="brisket"))
    P.append(Ellipsoid((0, 0.54, 0.92), (0.19, 0.13, 0.19), k=0.08, tag="rump"))
    # --- neck and head ------------------------------------------------------------------------------
    hz = HZ + dz
    P.append(RoundCone((0, -0.46, 0.96), (0, -0.78, 1.13 + dz), 0.225, 0.165, k=0.09, tag="neck"))
    # a rounder skull and fuller cheeks than the first sculpt: the face is what players look at
    P.append(Ellipsoid((0, -0.86, hz), (0.18, 0.195, 0.17), k=0.07, tag="skull"))
    P.append(Ellipsoid((0, -0.90, hz + 0.06), (0.125, 0.14, 0.095), k=0.06, tag="brow"))
    P += mirror_pair([Ellipsoid((0.098, -0.95, hz - 0.078), (0.098, 0.108, 0.09), k=0.055, tag="cheek")])
    P.append(Ellipsoid((0, -1.04, hz - 0.08), (0.085, 0.105, 0.078), k=0.05, tag="muzzle"))
    P.append(Ellipsoid((0, -1.14, hz - 0.088), (0.038, 0.032, 0.032), k=0.025, tag="nose"))
    P += mirror_pair([Ellipsoid((0.042, -1.085, hz - 0.11), (0.042, 0.05, 0.036), k=0.03, tag="whiskerpad")])
    P.append(RoundCone((0, -0.86, hz - 0.14), (0, -1.05, hz - 0.185), 0.075, 0.036, k=0.045, tag="jaw"))
    corner = (0.064, -0.998, hz - 0.136) if rodent else (0.056, -1.005, hz - 0.142)
    P += mirror_pair([RoundCone(corner, (0.0, -1.105, hz - 0.142), 0.009 if rodent else 0.007, 0.006, k=0.012, op="sub", tag="mouth")])
    er = eye_radius(variant) + 0.003
    ec = _eye0(variant, 1)
    P += mirror_pair([Ellipsoid(ec, (er, er, er), k=0.02, op="sub", tag="eyesocket")])
    P += mirror_pair([Ellipsoid(ec + [-0.012, 0.01, 0.05], (0.05, 0.065, 0.022), k=0.022, tag="brow")])
    # ears: short, broad, rounded leaves tilted out and back, cupped on the front
    tilt = rot_y(0.32) @ rot_x(-0.12)
    base = np.array([0.11, -0.80, 1.33 + dz])
    c = base + tilt @ np.array([0, 0, 0.07])
    P += mirror_pair([Ellipsoid(c, (0.062, 0.022, 0.088), axes=tilt, k=0.03, tag="ear")])
    cup = c + tilt @ np.array([0, -0.019, 0.012])
    P += mirror_pair([Ellipsoid(cup, (0.044, 0.011, 0.064), axes=tilt, k=0.006, op="sub", tag="earcup")])
    # --- forelegs ---------------------------------------------------------------------------------------
    sh, el, wr, kn = (np.array(FRONT0[k]) for k in ("Upper", "Lower", "Foot", "Toe"))
    P += mirror_pair([
        Ellipsoid(sh + [-0.015, 0.02, 0.13], (0.11, 0.16, 0.19), axes=rot_x(0.35), k=0.07, tag="scapula"),
        _limb(sh, el, 0.115 * lean, 0.07, 0.07, "arm"),
        Ellipsoid((sh + el) / 2 + [0.0, 0.05, 0.0], (0.075, 0.075, 0.125), axes=rot_x(-0.3), k=0.05, tag="triceps"),
        _limb(el, wr, 0.07, 0.038, 0.05, "forearm"),
        Ellipsoid(el + (wr - el) * 0.3, (0.052, 0.05, 0.11), axes=frame_from(wr - el), k=0.06, tag="forearmmuscle"),
        _limb(wr, kn, 0.037, 0.030, 0.02, "hand"),
    ])
    for dx, dy in ((-0.034, 0.0), (-0.012, 0.013), (0.012, 0.013), (0.034, 0.0)):
        P += mirror_pair([_limb(kn + [dx * 0.5, 0, 0], kn + [dx, -0.08 + dy, -0.021], 0.017, 0.011, 0.012, "finger")])
    # --- hind legs: a big round haunch over the folded leg, the long foot flat on the ground --------
    hp, kn2, hk, ba = (np.array(BACK0[k]) for k in ("Upper", "Lower", "Foot", "Toe"))
    P += mirror_pair([
        _limb(hp + [0.0, 0.02, 0.02], kn2, 0.21 * lean, 0.11, 0.10, "thigh"),
        Ellipsoid(hp + [0.035, -0.06, -0.12], (0.14, 0.24, 0.22), axes=rot_x(0.55), k=0.10, tag="haunch"),
        _limb(kn2, hk, 0.11, 0.05, 0.07, "shank"),
        Ellipsoid(kn2 + (hk - kn2) * 0.3 + [0.0, 0.035, 0.03], (0.08, 0.10, 0.14), axes=frame_from(hk - kn2), k=0.07, tag="calf"),
        _limb(hk, ba, 0.048, 0.031, 0.03, "foot"),
    ])
    for dx, dy in ((-0.038, 0.006), (-0.018, 0.016), (0.0, 0.02), (0.018, 0.016), (0.038, 0.006)):
        P += mirror_pair([_limb(ba + [dx * 0.5, 0, 0], ba + [dx, -0.115 + dy, -0.02], 0.018, 0.010, 0.012, "toe")])
    # --- tail: a slim core and a broad, slightly flattened plume (two lobes per segment) ------------
    plume = [0.46, 0.76, 0.96, 1.06, 1.08, 1.04, 0.94, 0.76, 0.46]  # a full, soft brush (seen from behind in play)
    if rodent:
        plume = [0.4, 0.62, 0.8, 0.66, 0.88, 0.74, 0.7, 0.54, 0.34]  # a little ragged, still a squirrel's tail
    for i in range(8):
        a, b = np.array(TAIL0[i]), np.array(TAIL0[i + 1])
        P.append(RoundCone(a, b, 0.07 if i == 0 else 0.05, 0.045, k=0.05, tag="tailcore"))
        for f in (0.25, 0.75):
            m = a + (b - a) * f
            s = plume[i] * (1 - f) + plume[i + 1] * f
            P.append(Ellipsoid(m, (0.24 * s + 0.035, 0.135, 0.155 * s + 0.035), axes=frame_from(b - a), k=0.10, tag="plume"))
    P.append(Ellipsoid(np.array(TAIL0[8]) + [0, -0.03, 0.0], (0.08 * plume[-1] + 0.03, 0.08, 0.07 * plume[-1] + 0.03), k=0.06, tag="plume"))
    if rodent:
        for pt in RODENT_PATCHES:
            c = np.array(pt["c"])
            P.append(Ellipsoid(c, (pt["r"] * 0.8, pt["r"], pt["r"] * 0.8), k=0.03, op="sub", tag="bald"))
        P.append(Ellipsoid((-0.175, -0.78, 1.445 + dz), (0.022, 0.05, 0.02), k=0.006, op="sub", tag="earnotch"))
    return _lower(P)


# The rodent's one small bald patch and the old scar across it (texture painter + sculpt agree;
# authored space). No stitches.
RODENT_PATCHES = [  # centre on the skin surface, radius, scar line (two points)
    {"c": (0.30, -0.06, 0.93), "r": 0.062, "stitch": ((0.29, -0.11, 0.97), (0.31, -0.01, 0.89))},
]

LEG_TAGS = {"arm", "triceps", "forearm", "forearmmuscle", "hand", "thigh", "haunch", "shank", "calf", "foot", "scapula"}


def _lower(prims):
    """The authored sculpt, lowered: centres and end points through zw; the legs' own primitives are
    slimmer, and their long ellipsoids shortened with the legs they belong to."""
    for p in prims:
        leg = p.tag in LEG_TAGS
        if hasattr(p, "c"):
            p.c = W(p.c)
            if leg:
                p.r = p.r * np.array([LEG_GIRTH, 0.82, 0.72])
        if hasattr(p, "a"):
            p.a, p.b = W(p.a), W(p.b)
            if leg:
                p.ra, p.rb = p.ra * LEG_GIRTH, p.rb * LEG_GIRTH
    return prims


def hard_parts(variant="squirrel"):
    """Claws and incisors: [(name, verts, faces, bone, kind)] (kind: claw | tooth)."""
    from geometry import curved_spike

    rodent = variant == "rodent"
    dz = -0.03 if rodent else 0.0
    hz = HZ + dz
    out = []
    kn = np.array(FRONT0["Toe"])
    for side, sx in (("L", 1), ("R", -1)):
        for i, (dx, dy) in enumerate(((-0.034, 0.0), (-0.012, 0.013), (0.012, 0.013), (0.034, 0.0))):
            tip = (kn + [dx, -0.08 + dy, -0.021]) * [sx, 1, 1]
            v, f = curved_spike(tip + [0, 0.004, 0.006], (0, -1, -0.35), 0.038 if rodent else 0.032, 0.0085, curl=(0, 0.2, -1), curl_amt=0.9)
            out.append((f"claw_F{side}{i}", v, f, f"Front{side}_Toe", "claw"))
        ba = np.array(BACK0["Toe"])
        for i, (dx, dy) in enumerate(((-0.038, 0.006), (-0.018, 0.016), (0.0, 0.02), (0.018, 0.016), (0.038, 0.006))):
            tip = (ba + [dx, -0.115 + dy, -0.02]) * [sx, 1, 1]
            v, f = curved_spike(tip + [0, 0.004, 0.006], (0, -1, -0.3), 0.04 if rodent else 0.034, 0.009, curl=(0, 0.2, -1), curl_amt=0.9)
            out.append((f"claw_B{side}{i}", v, f, f"Back{side}_Toe", "claw"))
    up_len = 0.042 if rodent else 0.026  # buck teeth, not fangs
    lo_len = 0.02 if rodent else 0.014
    for sx in (1, -1):
        crooked = 0.16 * sx if rodent and sx > 0 else 0.0  # one tooth askew
        v, f = curved_spike((0.0105 * sx, -1.115, hz - 0.118), (crooked, -0.25, -1), up_len, 0.0115 if rodent else 0.0105, curl=(0, 0.6, 0), curl_amt=0.35, sides=4, flat=1.6)
        out.append((f"tooth_U{sx}", v, f, "Head", "tooth"))
        v, f = curved_spike((0.008 * sx, -1.072, hz - 0.17), (0, -0.55, 1), lo_len, 0.009, curl=(0, 1, 0), curl_amt=0.3, sides=4, flat=1.4)
        out.append((f"tooth_L{sx}", v, f, "Jaw", "tooth"))
    # whiskers: five long dark hairs fanning from each whisker pad (drawn with the claws' dark colour)
    for sx in (1, -1):
        for i, (dz_w, back, ln) in enumerate(((0.012, 0.25, 0.17), (0.0, 0.1, 0.2), (-0.012, 0.0, 0.19), (-0.022, 0.2, 0.15), (0.02, 0.45, 0.13))):
            root = np.array([0.062 * sx, -1.075 + 0.012 * i, hz - 0.108 + dz_w])
            v, f = curved_spike(root, (sx, back - 0.25, 0.1 + dz_w * 6), ln, 0.0026, curl=(0, 0.4, -1), curl_amt=0.22, sides=3, segs=3)
            out.append((f"whisker_{'L' if sx > 0 else 'R'}{i}", v, f, "Head", "claw"))
    # everything above was placed in the authored space
    low = []
    for name, v, f, bone, kind in out:
        v = np.array(v, dtype=np.float64)
        v[:, 2] = zw(v[:, 2])
        low.append((name, v, f, bone, kind))
    return low


# RigSpec budgets: squirrel 13,000 tris (body + claws/teeth ~7.7k, cards 4.6k, eyes 0.45k), rodent 11,000
BUDGET = {"body_tris": 7100, "cards_tris": 4600, "rodent_cards_tris": 2200}
# RootPart: the puppet's hidden root block (PuppetSpec: 0.66 x 0.66 x 1.4 st at hip height 0.9)
ROOT_PART = ((0.0, 0.0, 0.9), (0.33, 0.7, 0.33))
HIP_HEIGHT = 0.9
TORSO = {"Hips", "Spine1", "Spine2", "Spine3", "Chest"}


def _sstep(a, b, x):
    t = np.clip((x - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def pattern_field(c, n, dom, variant="squirrel"):
    """0..1 'how much Pattern (cream belly, throat, chin, tail tip)' at points c with normals n and
    dominant bones dom. Faces above 0.5 become the Pattern region."""
    c = U(np.asarray(c))
    n = np.asarray(n)
    x, y, z = c[:, 0], c[:, 1], c[:, 2]
    wob = 0.03 * np.sin(y * 23.0 + x * 9.0) + 0.02 * np.sin(y * 51.0 - z * 17.0)
    out = np.zeros(len(c))
    # belly and chest by position (the belly's dominant bones are often the legs'): low, facing
    # down, near the midline; the line rises toward the chest and the throat
    ds = dom.astype(str)
    legs = np.char.startswith(ds, "Front") | np.char.startswith(ds, "Back")
    # the belly only (behind the forelegs, under the body): the chest and throat are painted cream
    # (cream_face), because a mesh region's edge is cut at face edges and showed as a ragged bib
    trunk = (~np.char.startswith(ds, "Tail") & ~np.isin(ds, ["Head", "Jaw", "EarL", "EarR", "Neck"]) & ~legs
             & (y > -0.36) & (y < 0.5) & (z > 0.42))
    # the inside of the upper legs carries the belly colour; the outside is coat
    inner_leg = np.char.endswith(ds, "_Upper") & (-np.sign(x) * n[:, 0] > 0.35) & (z > 0.45)
    line = 0.71 + 0.08 * _sstep(0.2, -0.5, y) + wob
    belly = _sstep(0.1, 0.45, -n[:, 2] * 0.8 + (line - z) * 2.5 - np.abs(x) * 1.5 + 0.15)
    out[trunk] = belly[trunk]
    out[inner_leg] = _sstep(0.35, 0.6, (-np.sign(x) * n[:, 0])[inner_leg] - n[inner_leg, 2] * 0.3 + wob[inner_leg])
    # The chin, throat and cheeks are cream too, but that is PAINTED (cream_face below), not a mesh
    # region: split at face centres the region's edge was a ragged white bib under the jaw.
    if variant == "rodent":
        out *= 0.92  # a dingier, narrower belly
    return out


def cream_face(P, N, dom, variant):
    """0..1 cream on the chin, the throat, the cheek undersides and the chest (authored-space points).
    One continuous function of position and normal: an earlier version switched formula by the texel's
    dominant bone, and the cream's edge then ran along the bone boundaries as a ragged, hard-edged bib."""
    _ = dom
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    hz = HZ + (-0.03 if variant == "rodent" else 0.0)
    # the cream line: belly height at the chest, rising up the throat to just under the cheeks
    line = 0.71 + 0.08 * _sstep(0.2, -0.5, y) + np.clip(-y - 0.45, 0, 1) * 0.62
    line = np.minimum(line, hz - 0.1)
    field = -N[:, 2] * 0.8 + (line - z) * 2.5 - np.abs(x) * 1.2 + 0.15
    return _sstep(0.0, 0.6, field) * _sstep(-0.28, -0.4, y)


# ---- fur flow and painting (textures.py calls these) ------------------------------------------------

# Tints (sRGB hex) for SurfaceAppearance.Color in TintMask mode: the colour map is greyscale where the
# tint applies, averaging about 0.78 (body) / 0.93 (pattern), so tint x map lands on the PuppetSpec
# stock colours (#9a5a32 rust back, #e4c9a0 cream belly; rodent #5a4231 / #857160).
TINTS = {
    "squirrel": {"Body": "#c27442", "Pattern": "#f5d8ac", "FurCards": "#c27442"},
    "rodent": {"Body": "#663d2c", "Pattern": "#987559", "FurCards": "#663d2c"},
}
BAKE_EXTRUSION = 0.03


def flow_dir(name, head, tail, co, n, variant):
    seg = np.asarray(tail, float) - np.asarray(head, float)
    seg = seg / max(np.linalg.norm(seg), 1e-9)
    lat = np.abs(n[:, 0:1])
    if name in TORSO or name in ("Neck", "Head", "Jaw"):
        d = np.tile(-seg, (len(co), 1))
        d[:, 1] = np.maximum(d[:, 1], 0.6)  # always backward
        d = d + np.array([0, 0, -0.9]) * lat
        if name in ("Head", "Jaw"):
            d = d + np.array([0, 0.3, 0.25]) * (1 - lat)
        return d
    if name.startswith("Ear"):
        return np.tile(seg, (len(co), 1))
    if name.startswith("Tail"):
        rel = co - head
        along = rel @ seg
        perp = rel - along[:, None] * seg
        pn = perp / np.maximum(np.linalg.norm(perp, axis=1, keepdims=True), 1e-9)
        return seg + 0.9 * pn
    if name.startswith("Back") and name.endswith("Upper"):
        return seg + np.array([0, 0.6, -0.6])
    return np.tile(seg, (len(co), 1))


def _hex(h):
    h = h.lstrip("#")
    return np.array([int(h[i : i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


def _seg_dist(P, a, b):
    a, b = np.asarray(a, np.float32), np.asarray(b, np.float32)
    ab = b - a
    t = np.clip((P - a) @ ab / max(float(ab @ ab), 1e-9), 0, 1)
    q = a + t[:, None] * ab
    return np.linalg.norm(P - q, axis=1), t


def paint(tx, variant, tools):
    """Colour (greyscale + TintMask alpha, natural colours where alpha is 0), roughness and strand
    relief for every texel of the Body/Pattern atlas."""
    rodent = variant == "rodent"
    sst = tools["sstep"]
    vn = tools["vnoise"]
    fbm = tools["fbm"]
    P, N, F, T, B = U(tx["P"]), tx["N"], tx["F"], tx["T"], tx["B"]
    n = len(P)
    dom = tx["dom"].astype(str)
    region = tx["region"]
    hard = tx["hard"]
    lm = landmarks(variant)
    tail = np.char.startswith(dom, "Tail")
    ear = np.char.startswith(dom, "Ear")
    feet = np.char.endswith(dom, "_Toe") | np.char.endswith(dom, "_Foot")
    head = np.isin(dom, ["Head", "Jaw"])
    # --- strands: fine hairs, locks and clumps; the tail's are longer and coarser -------------------
    lscale = np.where(tail, 1.8, np.where(head | feet, 0.6, 1.0)).astype(np.float32)
    layers = [(0.0058, 0.06, 1.0, 0.0016, 11), (0.014, 0.11, 0.8, 0.0024, 12), (0.032, 0.18, 0.6, 0.003, 13)]
    if rodent:
        layers = [(0.0045, 0.04, 1.0, 0.0014, 21), (0.013, 0.08, 0.8, 0.0026, 22), (0.035, 0.12, 0.7, 0.0035, 23)]
    H, gT, gB = tools["fur_relief"](P, F, N, T, B, layers, lscale=lscale)
    fine = tools["strands"](P, F * lscale[:, None], 0.0058, 0.06, seed=11)
    guard = tools["strands"](P, F * lscale[:, None], 0.009, 0.05, seed=14)
    big = fbm(P * 9.0, 3, seed=5)
    dorsal = sst(0.15, 0.85, N[:, 2])
    # --- greyscale under the tint ------------------------------------------------------------------
    g = 0.80 - 0.09 * dorsal
    # strand contrast: a little stronger than the first sculpt (the owner asked for more texture), and
    # stronger again on the rodent, whose dark coat otherwise reads as smooth
    ks = 1.6 if rodent else 1.2
    g = g + (fine - 0.5) * (0.30 + 0.25 * dorsal) * ks  # agouti: banded guard hairs grizzle the back
    g = g - 0.22 * sst(0.62, 0.78, guard) * (0.4 + 0.6 * dorsal) * ks  # dark-tipped guard hairs
    g = g + 0.10 * sst(0.25, 0.1, guard) * dorsal * ks  # pale bands
    g = g * (0.80 + 0.36 * H)
    g = g + (big - 0.5) * 0.12
    g = np.where(feet, g * 0.86, g)
    # face: pale eye ring, lighter cheeks and muzzle
    r_eye = eye_radius(variant)
    d_eye = np.minimum(np.linalg.norm(P - lm["eyeL"], axis=1), np.linalg.norm(P - lm["eyeR"], axis=1))
    ring = sst(r_eye + 0.003, r_eye + 0.010, d_eye) * (1 - sst(r_eye + 0.016, r_eye + 0.032, d_eye))
    g = np.where(head, g + 0.10 * (1 - dorsal) * (1 - ring), g)
    g = g * (1 - 0.0 * ring) + ring * (0.98 - g) * 0.85
    # tail: darker core, a dark band, then the frosted fringe at the plume's edges
    lat = np.abs(N[:, 0])
    tg = 0.66 + (fine - 0.5) * 0.42
    tg = tg - 0.16 * sst(0.45, 0.65, lat) * (1 - sst(0.72, 0.86, lat))
    tg = np.where(lat > 0.72, tg + (1.0 - tg) * sst(0.74, 0.92, lat) * 0.9, tg)
    g = np.where(tail, tg, g)
    # pattern region (cream belly, throat, tail tip): bright with soft strands
    gp = 0.93 + (fine - 0.5) * 0.14 + (H - 0.5) * 0.06
    gp = np.where(tail, 0.95 + (fine - 0.5) * 0.12, gp)
    # --- natural (untinted) colours and the tint mask ---------------------------------------------
    tints = TINTS[variant]
    tb, tp = _hex(tints["Body"]), _hex(tints["Pattern"])
    # a soft furry border: cream fades into the coat over a centimetre or two (a hard, noisy edge read
    # as a torn paper bib). pattern_field takes lowered points, so it is handed the originals.
    pat = pattern_field(tx["P"], N, tx["dom"], variant) + (fine - 0.5) * 0.14
    m = sst(0.2, 0.8, pat)
    grey, alpha, nat = tools["region_colours"](region, m, g, gp, tb, tp)
    rough = 0.64 - 0.12 * (H - 0.5) + 0.08 * (1 - dorsal) + (big - 0.5) * 0.06
    rough = np.where(tail, rough + 0.04, rough)
    ov = np.zeros(n, dtype=bool)  # texels whose natural colour is overridden (alpha forced to 0)
    natv = nat.copy()

    def override(mask, col, a=0.0, r=None, k=None):
        m = mask if k is None else mask & (k > 0)
        w = (np.ones(n) if k is None else k)[m]
        col = np.asarray(col, np.float32)
        natv[m] = natv[m] * (1 - w[:, None]) + (col[m] if col.ndim == 2 else col) * w[:, None]
        alpha[m] = alpha[m] * (1 - w) + a * w
        if r is not None:
            rough[m] = rough[m] * (1 - w) + r * w
        ov[m] = True

    # cream chin, throat and cheek undersides, with a furry broken edge (painted, never a mesh edge)
    cream = _hex("#8f7359") if rodent else _hex("#e4c9a0")
    # feathered: the edge breaks up along the hairs (owner agreed, 2026-11-10)
    ck = np.clip(cream_face(P, N, tx["dom"], variant) + (fine - 0.5) * 0.34 + (guard - 0.5) * 0.22, 0, 1)
    ck = sst(0.12, 0.88, ck)
    override(hard == 0, cream[None, :] * (0.9 + 0.2 * fine)[:, None], k=ck * (hard == 0))
    # the pale ring round each eye, and paler whisker pads
    buff = _hex("#7d6048") if rodent else _hex("#dcb98a")
    override(head, buff[None, :] * (0.9 + 0.2 * fine)[:, None], k=ring * (0.5 if rodent else 0.75) * (hard == 0))
    d_pad = np.minimum(
        np.linalg.norm(P - (lm["nose"] + [0.045, 0.05, -0.02]), axis=1),
        np.linalg.norm(P - (lm["nose"] + [-0.045, 0.05, -0.02]), axis=1),
    )
    override(head, buff[None, :] * (0.92 + 0.16 * fine)[:, None], k=(1 - sst(0.03, 0.06, d_pad)) * 0.6 * (hard == 0))
    # rows of dark whisker spots on the pads
    spots = sst(0.72, 0.8, vn(P * 190.0, 61)) * (1 - sst(0.02, 0.045, d_pad))
    override(head, _hex("#3a2a24"), k=spots * 0.7 * (hard == 0))
    # nose pad (rhinarium) and the dark lip line under it
    d_nose = np.linalg.norm(P - lm["nose"], axis=1)
    override(head, _hex("#4e3530") * (0.85 + 0.3 * vn(P * 300.0, 3))[:, None] if False else _hex("#503631"), r=0.32, k=1 - sst(0.026, 0.036, d_nose))
    # eyelid rims: bare dark skin right around the eyeball
    lid = 1 - sst(r_eye + 0.002, r_eye + 0.009, d_eye)
    override(head, _hex("#7a2a2a") if rodent else _hex("#2a1e1a"), r=0.4, k=lid)
    # inner ears: thin pinkish skin with fine hairs
    # inner ears: thin warm skin with fine hairs, the fur coming over the rim
    ec = np.where(P[:, :1] > 0, lm["earL"], lm["earR"])
    rim = 1 - sst(0.02, 0.045, np.linalg.norm(P - ec, axis=1))
    inner = ear & (N[:, 1] < -0.2)
    skin_e = (_hex("#7a4a40") if rodent else _hex("#9a6a5a")) * (0.85 + 0.3 * fine)[:, None]
    override(ear, skin_e * 0.85, r=0.5, k=sst(-0.25, -0.6, N[:, 1]) * inner * rim * 0.6)
    # the backs of the ears are furred like the head, with a darker rim
    override(ear, _hex("#4a3026") if rodent else _hex("#5a3a2a"), k=rim * sst(-0.1, 0.4, N[:, 1]) * 0.35)
    # foot pads
    override(feet, _hex("#5c4440"), r=0.5, k=sst(-0.4, -0.75, N[:, 2]) * feet)
    # claws and teeth
    override(hard == 1, _hex("#2b2320") * 1.0, r=0.28)
    override(hard == 2, _hex("#e0b05a") if not rodent else _hex("#d8b25e"), r=0.22)
    if rodent:
        skin = _hex("#8a7068")
        # a scorched darker back: the dorsal fur is almost black-brown along the spine
        scorch = sst(0.55, 0.95, N[:, 2]) * np.isin(dom, list(TORSO) + ["Neck", "Head"]) * (hard == 0)
        override(hard == 0, _hex("#1e1512") * (0.8 + 0.4 * fine)[:, None], a=0.0, k=scorch * 0.7)
        # the tail's fringe smoulders: ember rust at the plume's edges instead of a frosted tip
        # (furry and broken, not a painted stripe: it follows the hairs and thins out in places)
        lat_t = np.abs(N[:, 0])
        ek = sst(0.78, 0.99, lat_t + (fine - 0.5) * 0.4 + (big - 0.5) * 0.4) * (0.45 + 0.55 * sst(0.3, 0.7, guard))
        ecol = _hex("#7a3a22")[None, :] * (1 - fine)[:, None] + _hex("#c9642c")[None, :] * fine[:, None]
        override(tail, ecol, k=ek * 0.9)
        # one small bald patch with an old pale scar across it
        for i, pt in enumerate(RODENT_PATCHES):
            c = np.array(pt["c"], np.float32)
            d = np.linalg.norm(P - c, axis=1)
            edge = pt["r"] * (0.85 + 0.3 * vn(P * 40.0, 40 + i))
            k = 1 - sst(edge * 0.75, edge, d)
            col = skin * (0.85 + 0.3 * vn(P * 120.0, 50 + i))[:, None]
            override(hard == 0, col, r=0.5, k=k)
            a, b = pt["stitch"]
            ds, _ts = _seg_dist(P, a, b)
            override(hard == 0, _hex("#c9b0a6"), r=0.45, k=(1 - sst(0.004, 0.009, ds)) * (k > 0.3))
        # sore, reddened eyelids
        override(head, _hex("#7a2c2a"), r=0.4, k=(1 - sst(r_eye + 0.004, r_eye + 0.014, d_eye)) * 0.45)
    rgb = tools["finish_rgb"](grey, alpha, natv, region, tb, tp)
    # flatter relief on bare skin, claws and teeth
    flat = (alpha < 0.5) & ov
    gT = np.where(flat, gT * 0.25, gT)
    gB = np.where(flat, gB * 0.25, gB)
    return {
        "rgb": rgb.astype(np.float32),
        "alpha": np.clip(alpha, 0, 1).astype(np.float32),
        "rough": np.clip(rough, 0.05, 1).astype(np.float32),
        "height": H,
        "slope_T": gT.astype(np.float32),
        "slope_B": gB.astype(np.float32),
        "tint_by_region": [tb, tp],
        "tints_hex": tints,
        "ao_strength": 0.7,
    }


# ---- fur cards, blood ---------------------------------------------------------------------------------

SCALE = 1.0
VIEW_CENTER = (0.0, 0.45, 0.6)


def card_density(c, n, dom, variant):
    c = U(np.asarray(c))
    dom = np.asarray(dom).astype(str)
    d = np.zeros(len(c))
    tail = np.char.startswith(dom, "Tail")
    torso = np.isin(dom, list(TORSO))
    d[tail] = 3.2 if variant != "rodent" else 1.6
    d[torso] = 0.5 + 0.9 * np.clip(n[torso, 2] + 0.3, 0, 1)
    d[dom == "Neck"] = 1.2
    d[np.isin(dom, ["BackL_Upper", "BackR_Upper"])] = 1.1
    d[np.isin(dom, ["FrontL_Upper", "FrontR_Upper"])] = 0.5
    d[np.isin(dom, ["BackL_Lower", "BackR_Lower", "FrontL_Lower", "FrontR_Lower"])] = 0.25
    head = dom == "Head"
    d[head] = 0.55 * np.clip(np.abs(n[head, 0]) * 1.3, 0, 1) * (c[head, 1] > -1.02)  # cheeks, not the face
    d[dom == "Jaw"] = 0.25
    ears = np.char.startswith(dom, "Ear")
    d[ears] = 2.4 * (c[ears, 2] > 1.37)  # tufts at the tips
    if variant == "rodent":
        # a ruffle of raised fur along the spine
        spine = torso & (n[:, 2] > 0.75) & (np.abs(c[:, 0]) < 0.09)
        d[spine] = 3.0
        # no tufts on or near the bald patch
        for pt in RODENT_PATCHES:
            d[np.linalg.norm(c - np.array(pt["c"]), axis=1) < pt["r"] * 1.3] = 0
    return d


def card_shape(P, N, F, dom, variant, rng):
    dom = np.asarray(dom).astype(str)
    k = len(P)
    tail = np.char.startswith(dom, "Tail")
    head = np.isin(dom, ["Head", "Jaw"]) | np.char.startswith(dom, "Ear")
    rodent = variant == "rodent"
    L = np.where(tail, rng.uniform(0.13, 0.22, k), np.where(head, rng.uniform(0.04, 0.06, k), rng.uniform(0.065, 0.105, k)))
    W = np.where(tail, rng.uniform(0.06, 0.10, k), np.where(head, rng.uniform(0.028, 0.04, k), rng.uniform(0.035, 0.055, k)))
    lift = np.where(tail, rng.uniform(0.35, 0.75, k), rng.uniform(0.22, 0.45, k))
    roll = np.where(tail, rng.uniform(-1.3, 1.3, k), rng.uniform(-0.6, 0.6, k))
    droop = np.full(k, 0.28)
    if rodent:
        L *= rng.uniform(0.75, 1.05, k)
        W *= 0.9
        lift = lift + rng.uniform(0.0, 0.35, k)  # ruffled, standing up a little
        droop = rng.uniform(0.15, 0.45, k)
    return {"length": L, "width": W, "lift": lift, "roll": roll, "droop": droop}


def blood_faces(lo, co, W, bone_names):
    """Faces under the rodent's blood shell: mouth corners and chin, the front claws and fingers."""
    me = lo.data
    lm = landmarks("rodent")
    hz = HZ - 0.03
    # a little red at one corner of the mouth, nothing else (authored space, lowered for the mesh)
    spot = np.array([0.064, -0.998, hz - 0.15])
    spot[2] = float(zw(spot[2]))  # (the parameter W here is the weight matrix, not the lowering helper)
    spots = [spot]
    kind = np.empty(len(me.polygons), dtype=np.int32)
    me.attributes["hard_kind"].data.foreach_get("value", kind)
    cen = np.empty(len(me.polygons) * 3, dtype=np.float32)
    me.polygons.foreach_get("center", cen)
    cen = cen.reshape(-1, 3)
    near = np.min([np.linalg.norm(cen - s, axis=1) for s in spots], axis=0) < 0.04
    domv = np.array(bone_names)[np.argmax(W, axis=1)]
    lv = np.empty(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", lv)
    ls = np.empty(len(me.polygons), dtype=np.int64)
    me.polygons.foreach_get("loop_start", ls)
    fdom = domv[lv[ls]]
    _ = fdom
    return near & ~(kind == 2)


def blood_mask(P, tools):
    P = U(P)
    sst = tools["sstep"]
    vn = tools["vnoise"]
    hz = HZ - 0.03
    c = np.array([0.064, -0.998, hz - 0.15])
    d = np.linalg.norm(P - c, axis=1)
    m = (1 - sst(0.01, 0.026, d)).astype(np.float32)
    return np.clip(m * (0.7 + 0.3 * vn(P * 200.0, 17)), 0, 1).astype(np.float32)


# Sockets (RigSpec ANIMAL_SOCKETS): bone and a point in Blender coordinates; publish.py converts them to
# offsets in the bone's (axis-aligned) frame, Roblox axes, for Attachments parented to the Bones.
SOCKETS = {
    "HeadSocket": ("Head", tuple(W((0.0, -0.86, 1.36)))),
    "MouthSocket": ("Jaw", tuple(W((0.0, -1.10, 1.06)))),
    "TailTip": ("Tail8", tuple(W(TAIL0[-1]))),
    "ChestCenter": ("Chest", tuple(W((0.0, -0.40, 0.86)))),
}
