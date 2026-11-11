"""Squirrel (and spicy rodent) anatomy: skeleton joints and the signed-distance sculpt.

Blender coordinates, studs: ground z = 0, the animal faces -Y, its left side is +X, Root at the
origin under the middle of the body. About 1.2 studs at the shoulder (brief v2 §15, RigSpec), 2.0 from
nose to rump, the tail about as long again. Bone names are RigSpec.squirrel's, exactly.

The rodent (variant="rodent") is the same skeleton (so every clip is shared): the same animal gone
wrong, a blend the owner asked for after a harsher version ("too edgy ... combine those two back
together"): a little leaner, a ragged right ear, a lower head with crooked buck teeth, slightly
oversized glowing eyes, one small bald scar on a flank, a ruffle of raised fur along the spine and a
slightly ragged tail with an ember-rust fringe. No ribs, stitches or blood beyond the mouth corner.

Then the owner asked for more (2026-11-11: "just crank up that squirrels creepy weirdness, even further"):
weird, not gory. The eyes no longer match (one bulging and staring up, one smaller and wandering down
and out, pin pupils, sleepless dark hollows round them); a grin cut far too wide up the cheeks with a
row of small crooked teeth under long buck teeth; spindly over-long fingers and toes with long claws; a
sharper hunch with the knobs of the spine showing through the fur; one ear too big beside the torn one;
a tail that is bottle-brush in places and nearly bare in others; thin patchy fur. The twitching, the
cocked head and the chattering jaw are added by the client (Client/Animation/Creep).

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


def A(x, y, z_low):
    """A point given by its LOWERED height, as an authored-space point (what sculpt's literals are)."""
    return np.array([x, y, float(zu(z_low))])


# ---- the tail's brush ---------------------------------------------------------------------------------
# The play camera is behind and above, so the tail is the nearest and largest thing on the screen. A
# squirrel's tail is not a sausage: the hairs part along the bone and lie out to the two sides, so it is a
# flat feather, narrow where it leaves the rump, widest past the middle and rounded at the tip, with a
# darker middle, a dark band and a pale fringe of long hair tips. The mesh is the feather's solid middle;
# the fringe is fur cards (card_tufts). PLUME: (place along the tail 0..1, half-width of the mesh there).
PLUME = [(0.0, 0.068), (0.07, 0.08), (0.16, 0.115), (0.28, 0.16), (0.42, 0.195), (0.56, 0.215), (0.70, 0.22),
         (0.82, 0.205), (0.91, 0.17), (0.97, 0.125), (1.0, 0.09)]
PLUME_LOBES = 24
# The Spicy Rodent's tail is a rat's bare tail with three clumps of bottle-brush bristle left on it, each
# knocked to one side: (place along the tail, half-length along it, half-width, half-thickness, sideways shift)
RODENT_TUFTS = [
    (0.20, 0.10, 0.115, 0.095, 0.045),
    (0.29, 0.13, 0.165, 0.125, 0.0),
    (0.54, 0.10, 0.125, 0.105, -0.06),
    (0.62, 0.14, 0.195, 0.145, -0.015),
    (0.70, 0.10, 0.125, 0.10, -0.055),
    (0.90, 0.10, 0.12, 0.10, 0.03),
    (0.97, 0.08, 0.095, 0.08, 0.0),
]
_TAIL_PTS = np.array(TAIL0, dtype=np.float64)
_TAIL_SEG = np.linalg.norm(np.diff(_TAIL_PTS, axis=0), axis=1)
_TAIL_CUM = np.concatenate([[0.0], np.cumsum(_TAIL_SEG)])
TAIL_LENGTH = float(_TAIL_CUM[-1])


def tail_point(u):
    """(point, unit direction) at the place u (0 root .. 1 tip, by length) along the tail's rest line (authored)."""
    d = min(max(u, 0.0), 1.0) * TAIL_LENGTH
    i = int(min(np.searchsorted(_TAIL_CUM, d, side="right") - 1, len(_TAIL_SEG) - 1))
    seg = (_TAIL_PTS[i + 1] - _TAIL_PTS[i]) / _TAIL_SEG[i]
    return _TAIL_PTS[i] + seg * (d - _TAIL_CUM[i]), seg


def tail_coords(P):
    """For authored-space points (n, 3): the place along the tail 0..1, the signed sideways distance from its
    midline (+ = the animal's left), the distance from its axis, and the tail's own direction there."""
    P = np.asarray(P, dtype=np.float64)
    best = np.full(len(P), 1e9)
    s = np.zeros(len(P))
    axis = np.zeros((len(P), 3))
    for i in range(len(_TAIL_SEG)):
        a, b = _TAIL_PTS[i], _TAIL_PTS[i + 1]
        seg = (b - a) / _TAIL_SEG[i]
        t = (P - a) @ seg
        # the first and last pieces run on past their ends (the rump side of the root, the fur past the tip)
        lo = -0.5 if i == 0 else 0.0
        hi = _TAIL_SEG[i] + (0.5 if i == len(_TAIL_SEG) - 1 else 0.0)
        tc = np.clip(t, lo, hi)
        q = a + tc[:, None] * seg
        d = np.linalg.norm(P - q, axis=1)
        m = d < best
        best[m] = d[m]
        s[m] = (_TAIL_CUM[i] + tc[m]) / TAIL_LENGTH
        axis[m] = seg
    return s, P[:, 0].copy(), best, axis


def plume_half_width(s, variant="squirrel"):
    """Half the width of the tail's mesh at the place s along it (arrays)."""
    s = np.asarray(s, dtype=np.float64)
    if variant == "rodent":
        w = np.full(s.shape, 0.05)
        for u, hl, hw, _ht, _dx in RODENT_TUFTS:
            k = np.clip(1 - ((s - u) * TAIL_LENGTH / hl) ** 2, 0, 1)
            w = np.maximum(w, hw * np.sqrt(k))
        return w
    return np.interp(s, [p[0] for p in PLUME], [p[1] for p in PLUME])


def plume_shift(s, variant="squirrel"):
    """How far the brush sits to one side of the tail's midline at s (the rodent's clumps are knocked askew)."""
    s = np.asarray(s, dtype=np.float64)
    out = np.zeros(s.shape)
    if variant == "rodent":
        best = np.zeros(s.shape)
        for u, hl, hw, _ht, dx in RODENT_TUFTS:
            k = np.clip(1 - ((s - u) * TAIL_LENGTH / hl) ** 2, 0, 1)
            m = hw * np.sqrt(k) > best
            best = np.where(m, hw * np.sqrt(k), best)
            out = np.where(m, dx, out)
    return out


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


SPINE_CHAIN = ["Hips", "Spine1", "Spine2", "Spine3", "Chest"]


def refine_weights(co, W, bone_names, variant):
    """Skin weights for the trunk by anatomy (hero.finish calls this on the bone-heat weights).

    Bone heat gives a vertex to the bones nearest it, and the spine runs along the top of the back: the
    belly and the flanks went to the knees and elbows (measured: belly 0.74 hind leg + 0.25 foreleg, nothing
    on the spine) and the rump half to the first tail bone. So the trunk did not bend with the spine; it was
    a sack dragged about by the legs, and lifting the tail lifted the rump with it. From behind that is the
    back and haunches moving wrongly, or not at all.

    Here the trunk behind the shoulders follows the spine by its place along the body (each vertex shared
    between the two nearest of Hips..Chest); the haunch (the thigh and the soft lobe over it) and the legs
    keep their bone-heat weights, so the haunch swings with the thigh under a back that holds its shape; the
    rump belongs to the hips and only the tail itself to the tail. Ahead of the shoulders (chest front,
    neck, head) nothing changes. co: vertex positions (lowered space)."""
    co = np.asarray(co, dtype=np.float64)
    W = np.asarray(W, dtype=np.float64)
    x, y, z = np.abs(co[:, 0]), co[:, 1], co[:, 2]
    col = {b: i for i, b in enumerate(bone_names)}
    heads = {b[0]: np.array(b[1]) for b in skeleton()}
    ends = [heads[b][1] for b in SPINE_CHAIN] + [heads["Neck"][1]]
    mids = np.array([(ends[i] + ends[i + 1]) / 2 for i in range(len(SPINE_CHAIN))])  # back to front
    f = np.interp(-y, -mids, np.arange(len(mids), dtype=np.float64))
    i0 = np.clip(np.floor(f).astype(int), 0, len(mids) - 2)
    fr = np.clip(f - i0, 0, 1)
    spine = np.zeros_like(W)
    cols = np.array([col[b] for b in SPINE_CHAIN])
    rows = np.arange(len(co))
    spine[rows, cols[i0]] += 1 - fr
    spine[rows, cols[i0 + 1]] += fr
    # the tail proper: behind its root, about its own axis
    s, _xs, r_ax, _axis = tail_coords(U(co))
    tail = _sstep(0.0, 0.04, s) * (r_ax < 0.45)
    tcols = [i for i, b in enumerate(bone_names) if b.startswith("Tail")]
    only_tail = np.zeros_like(W)
    only_tail[:, tcols] = W[:, tcols]
    none = only_tail.sum(axis=1) < 1e-6
    only_tail[none, col["Tail1"]] = 1.0
    only_tail /= only_tail.sum(axis=1, keepdims=True)
    base = W * (1 - tail)[:, None] + only_tail * tail[:, None]
    # what moves with a leg: the haunch (thigh and lobe), the upper arm, and everything below the belly
    # (the haunch's inner side shades into the groin over a wide band; the shin below it is all leg)
    q = _sstep(0.25, 0.38, z)
    t = np.clip((x - (0.04 + 0.04 * q)) / (0.06 + 0.06 * q), 0, 1)
    # (and its top and back stay with the hips: the lobe is skin stretched from the pelvis to the knee, so
    # the knee end goes with the knee and no gap opens under the rump when the leg swings forward)
    hind = t * t * (3 - 2 * t) * (1 - _sstep(0.36, 0.68, z)) * (1 - _sstep(0.34, 0.54, y)) * _sstep(-0.12, 0.0, y)
    fore = _sstep(0.05, 0.11, x) * (1 - _sstep(0.42, 0.6, z)) * _sstep(-0.2, -0.3, y)
    low = 1 - _sstep(0.13, 0.17, z)
    limb = np.maximum(np.maximum(hind, fore), low)
    trunk = _sstep(-0.56, -0.4, y) * (1 - tail) * (1 - limb)
    return spine * trunk[:, None] + base * (1 - trunk)[:, None]


HZ = 1.19  # skull centre height
RODENT_DZ = -0.06  # the rodent carries its head low and forward
EYE_L = np.array([0.110, -0.93, 1.245])
EYE_R_RODENT = 0.066
EYE_R = 0.058  # a touch larger than life: the face is what players look at
NOSE = np.array([0.0, -1.165, 1.10])


def eye_radius(variant, side=1):
    """The rodent's eyes do not match: its left bulges, its right is smaller."""
    if variant == "rodent":
        return 0.082 if side > 0 else 0.057
    return EYE_R


def eye_gaze(side, variant="squirrel"):
    if variant == "rodent":
        # wall-eyed: the big eye stares up and ahead, the small one wanders down and out
        return np.array([0.74, -0.6, 0.3]) if side > 0 else np.array([-0.93, -0.16, -0.34])
    return np.array([side * 0.86, -0.48, 0.16])


EYE_STYLE = "squirrel"


def _eye0(variant, side=1):
    c = EYE_L.copy()
    if variant == "rodent":
        # the head is carried lower; the big eye bulges out of its socket, the small one sits deeper
        c = c + ([0.02, -0.012, RODENT_DZ + 0.012] if side > 0 else [0.0, 0.006, RODENT_DZ - 0.004])
    c[0] *= side
    return c


def eye_centre(variant, side=1):
    """Where the eyeball sits (lowered space)."""
    return W(_eye0(variant, side))


def landmarks(variant):
    """Named points the texture painter and the card scatterer use (authored space)."""
    dz = RODENT_DZ if variant == "rodent" else 0.0
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


FINGERS = ((-0.034, 0.0), (-0.012, 0.013), (0.012, 0.013), (0.034, 0.0))
TOES = ((-0.038, 0.006), (-0.018, 0.016), (0.0, 0.02), (0.018, 0.016), (0.038, 0.006))
# The rodent's grin (authored space, before the head's drop): from the front of the mouth round the side
# of the muzzle (GRIN_MID) and far back up the cheek (GRIN_CORNER). The points lie ON the face, so the cut
# shows as a mouth line; a first version ran straight to a corner inside the cheek and showed nothing.
GRIN_FRONT = np.array([0.0, -1.105, HZ - 0.142])
GRIN_MID = np.array([0.086, -1.045, HZ - 0.137])
GRIN_CORNER = np.array([0.172, -0.94, HZ - 0.098])


def finger_reach(rodent):
    """(length, splay): the rodent's fingers are spindly, over-long and spread."""
    return (0.128, 1.45) if rodent else (0.08, 1.0)


def toe_reach(rodent):
    return (0.158, 1.3) if rodent else (0.115, 1.0)


TOE_OUT = 0.03  # the hind toes turn out a little


def hind_toe_tip(ball, dx, dy, rodent):
    """The tip of one left hind toe (authored space); the sculpt and the claws agree on it."""
    tl, ts = toe_reach(rodent)
    return np.asarray(ball) + [dx * ts + TOE_OUT, -tl + dy, -0.02]


def _limb(a, b, ra, rb, k, tag=""):
    return RoundCone(a, b, ra, rb, k=k, tag=tag)


RODENT_PEAK = 1.13  # the top of the rodent's hunch (the squirrel's back peaks at 1.07)


def rodent_knobs():
    """The knobs of the rodent's spine along its hunch: [(centre, radii)] in the authored space. The
    sculpt raises them and the painter rubs the fur off their tops."""
    out = []
    peak = RODENT_PEAK
    for i in range(9):
        y = -0.42 + i * 0.105
        axis = 0.98 + (peak - 0.98) * (y + 0.44) / 0.54 if y < 0.10 else peak + (1.03 - peak) * (y - 0.10) / 0.36
        top = axis + 0.165
        big = (i * 5 + 2) % 3  # 0, 1 or 2: no two neighbours the same
        out.append((np.array([0.012 * ((i % 2) * 2 - 1), y, top + 0.02 + 0.006 * big]),
                    np.array([0.03 + 0.004 * big, 0.036, 0.034 + 0.007 * big])))
    return out


def sculpt(variant="squirrel"):
    """The SDF primitive list (left/right pairs mirrored)."""
    rodent = variant == "rodent"
    lean = 0.93 if rodent else 1.0  # the rodent is a little leaner through the waist and belly
    dz = RODENT_DZ if rodent else 0.0  # and carries its head low
    P = []
    # --- torso: rib cage, belly, pelvis, the dorsal line and the chest -----------------------------
    P.append(Ellipsoid((0, -0.25, 0.83), (0.25, 0.35, 0.31), tag="ribs"))
    # a narrower waist behind the ribs (the pear seen from above), and a deeper belly: the body hangs
    # nearer the ground, so less leg shows under it
    P.append(Ellipsoid((0, 0.08, 0.82), (0.222 * lean, 0.30, 0.33 * lean), k=0.12, tag="belly"))
    P.append(Ellipsoid((0, 0.36, 0.88), (0.255, 0.28, 0.31), k=0.10, tag="pelvis"))
    # the dorsal line arches: highest over the loins, lower at the withers and the croup
    peak = RODENT_PEAK if rodent else 1.07  # the rodent is hunched
    P.append(RoundCone((0, 0.46, 1.03), (0, 0.10, peak), 0.16, 0.165, k=0.12, tag="back"))
    P.append(RoundCone((0, 0.10, peak), (0, -0.44, 0.98), 0.165, 0.16, k=0.12, tag="back"))
    if rodent:
        # the knobs of its spine show through the fur along the hunch
        # (uneven and standing proud of the back, so the row breaks its outline from behind and above)
        for c, r in rodent_knobs():
            P.append(Ellipsoid(c, r, k=0.018, tag="knob"))
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
    if rodent:
        drop = np.array([0, 0, dz])
        P += mirror_pair([
            RoundCone(GRIN_FRONT + drop, GRIN_MID + drop, 0.011, 0.014, k=0.012, op="sub", tag="mouth"),
            RoundCone(GRIN_MID + drop, GRIN_CORNER + drop, 0.014, 0.012, k=0.012, op="sub", tag="mouth"),
        ])
    else:
        corner = np.array([0.056, -1.005, hz - 0.142])
        P += mirror_pair([RoundCone(corner, (0.0, -1.105, hz - 0.142), 0.007, 0.006, k=0.012, op="sub", tag="mouth")])
    if rodent:
        # the grin: cut far too wide up the cheeks, the lips drawn back off the teeth at the front
        P.append(Ellipsoid((0.0, -1.095, hz - 0.15), (0.058, 0.034, 0.015), k=0.01, op="sub", tag="grin"))
    for side in (1, -1):
        er = eye_radius(variant, side) + 0.003
        ec = _eye0(variant, side)
        P.append(Ellipsoid(ec, (er, er, er), k=0.02, op="sub", tag="eyesocket"))
        P.append(Ellipsoid(ec + np.array([-0.012 * side, 0.01, 0.05]), (0.05, 0.065, 0.022), k=0.022, tag="brow"))
    # ears: short, broad, rounded leaves tilted out and back, cupped on the front
    tilt = rot_y(0.32) @ rot_x(-0.12)
    base = np.array([0.11, -0.80, 1.33 + dz])
    c = base + tilt @ np.array([0, 0, 0.07])
    cup = c + tilt @ np.array([0, -0.019, 0.012])
    if rodent:
        # one ear too big and too upright; the other (torn, below) the ordinary size
        big = Ellipsoid(c + tilt @ np.array([0, 0, 0.03]), (0.08, 0.022, 0.125), axes=rot_y(0.12) @ rot_x(-0.05), k=0.03, tag="ear")
        bigcup = Ellipsoid(cup + tilt @ np.array([0, 0, 0.03]), (0.058, 0.011, 0.095), axes=rot_y(0.12) @ rot_x(-0.05), k=0.006, op="sub", tag="earcup")
        P += [big, Ellipsoid(c, (0.062, 0.022, 0.088), axes=tilt, k=0.03, tag="ear").mirrored()]
        P += [bigcup, Ellipsoid(cup, (0.044, 0.011, 0.064), axes=tilt, k=0.006, op="sub", tag="earcup").mirrored()]
    else:
        P += mirror_pair([Ellipsoid(c, (0.062, 0.022, 0.088), axes=tilt, k=0.03, tag="ear")])
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
    for dx, dy in FINGERS:
        fl, fs = finger_reach(rodent)
        P += mirror_pair([_limb(kn + [dx * 0.5, 0, 0], kn + [dx * fs, -fl + dy, -0.021], 0.014 if rodent else 0.017, 0.008 if rodent else 0.011, 0.012, "finger")])
    # --- hind legs -----------------------------------------------------------------------------------
    # Seen from behind and above (the play camera) a squirrel is a pear: round, soft haunches wider than
    # anything ahead of them, sitting low over the long hind feet, so that almost no leg shows under them.
    # The owner called the legs too big and tall twice: the haunch is now one soft lobe that belongs to
    # the body (it hangs to within 0.14 of the ground and covers the knee and most of the shin), the
    # space between the thighs is filled, and what is left of the leg below it (shin, heel, foot) is slim.
    hp, kn2, hk, ba = (np.array(BACK0[k]) for k in ("Upper", "Lower", "Foot", "Toe"))
    lobe = (0.165, 0.275, 0.19) if rodent else (0.185, 0.30, 0.21)  # the rodent's are leaner and sharper
    P.append(Ellipsoid(A(0.0, 0.22, 0.37), (0.16 * lean, 0.26, 0.17), k=0.10, tag="groin"))
    P += mirror_pair([
        _limb(hp + [0.0, 0.02, 0.02], kn2, 0.20 * lean, 0.10, 0.10, "thigh"),
        Ellipsoid(A(0.20, 0.25, 0.40), lobe, axes=rot_x(0.82), k=0.11, tag="haunchlobe"),
        _limb(kn2, hk, 0.08, 0.042, 0.06, "shank"),
        Ellipsoid(kn2 + (hk - kn2) * 0.3 + [0.0, 0.03, 0.03], (0.06, 0.075, 0.115), axes=frame_from(hk - kn2), k=0.06, tag="calf"),
        _limb(hk, ba, 0.042, 0.029, 0.03, "foot"),
    ])
    for dx, dy in TOES:
        P += mirror_pair([_limb(ba + [dx * 0.5, 0, 0], hind_toe_tip(ba, dx, dy, rodent), 0.015 if rodent else 0.017, 0.008 if rodent else 0.010, 0.012, "toe")])
    # --- tail ----------------------------------------------------------------------------------------
    for i in range(8):
        a, b = np.array(TAIL0[i]), np.array(TAIL0[i + 1])
        P.append(RoundCone(a, b, 0.07 if i == 0 else 0.05, 0.045, k=0.05, tag="tailcore"))
    if rodent:
        # a rat's bare tail with three ragged clumps of bristle left on it (bottle-brush in places and
        # nearly bare in others), each knocked to one side so the outline is broken from behind
        for u, hl, hw, ht, dx in RODENT_TUFTS:
            m, seg = tail_point(u)
            P.append(Ellipsoid(m + [dx, 0, 0], (hw, hl, ht), axes=frame_from(seg), k=0.05, tag="plume"))
    else:
        # the flat feather (PLUME): thin from top to bottom, broad from side to side
        for j in range(PLUME_LOBES):
            u = (j + 0.5) / PLUME_LOBES
            m, seg = tail_point(u)
            hw = float(plume_half_width(u))
            P.append(Ellipsoid(m, (hw, 0.115, 0.058 + 0.42 * hw), axes=frame_from(seg), k=0.07, tag="plume"))
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
    dz = RODENT_DZ if rodent else 0.0
    hz = HZ + dz
    out = []
    kn = np.array(FRONT0["Toe"])
    for side, sx in (("L", 1), ("R", -1)):
        fl, fs = finger_reach(rodent)
        for i, (dx, dy) in enumerate(FINGERS):
            tip = (kn + [dx * fs, -fl + dy, -0.021]) * [sx, 1, 1]
            v, f = curved_spike(tip + [0, 0.004, 0.006], (0, -1, -0.35), 0.056 if rodent else 0.032, 0.0085, curl=(0, 0.2, -1), curl_amt=0.9)
            out.append((f"claw_F{side}{i}", v, f, f"Front{side}_Toe", "claw"))
        ba = np.array(BACK0["Toe"])
        for i, (dx, dy) in enumerate(TOES):
            tip = hind_toe_tip(ba, dx, dy, rodent) * [sx, 1, 1]
            v, f = curved_spike(tip + [0, 0.004, 0.006], (0, -1, -0.3), 0.054 if rodent else 0.034, 0.009, curl=(0, 0.2, -1), curl_amt=0.9)
            out.append((f"claw_B{side}{i}", v, f, f"Back{side}_Toe", "claw"))
    up_len = 0.056 if rodent else 0.026  # long buck teeth
    lo_len = 0.024 if rodent else 0.014
    for sx in (1, -1):
        crooked = (0.2 if sx > 0 else -0.07) if rodent else 0.0  # both askew, one badly
        v, f = curved_spike((0.0105 * sx, -1.115, hz - 0.118), (crooked, -0.25, -1), up_len, 0.0115 if rodent else 0.0105, curl=(0, 0.6, 0), curl_amt=0.35, sides=4, flat=1.6)
        out.append((f"tooth_U{sx}", v, f, "Head", "tooth"))
        v, f = curved_spike((0.008 * sx, -1.072, hz - 0.17), (0, -0.55, 1), lo_len, 0.009, curl=(0, 1, 0), curl_amt=0.3, sides=4, flat=1.4)
        out.append((f"tooth_L{sx}", v, f, "Jaw", "tooth"))
    if rodent:
        # a row of small crooked teeth along the grin, upper and lower, back to the corners
        drop = np.array([0, 0, dz])
        g0, g1, g2 = GRIN_FRONT + drop, GRIN_MID + drop, GRIN_CORNER + drop
        for sx in (1, -1):
            for i in range(7):
                u = (i + 0.9) / 7.4
                # along the grin, set a little inside the lip
                p = (g0 + (g1 - g0) * (u / 0.45)) if u < 0.45 else (g1 + (g2 - g1) * ((u - 0.45) / 0.55))
                p = p * [0.94, 1.0, 1.0] + [0.0, 0.006, 0.004]
                lean = ((i * 37 + (7 if sx > 0 else 3)) % 11 - 5) / 5 * 0.35  # each one leans its own way
                v, f = curved_spike(p * [sx, 1, 1], (lean, -0.12, -1), 0.026 - 0.008 * u, 0.0066, curl=(0, 0.5, 0), curl_amt=0.2, sides=4)
                out.append((f"grin_U{'L' if sx > 0 else 'R'}{i}", v, f, "Head", "tooth"))
                if i % 2 == 0:
                    q = p + np.array([0.0, 0.004, -0.03])
                    v, f = curved_spike(q * [sx, 1, 1], (-lean, -0.2, 1), 0.019 - 0.005 * u, 0.0056, curl=(0, 0.5, 0), curl_amt=0.2, sides=4)
                    out.append((f"grin_L{'L' if sx > 0 else 'R'}{i}", v, f, "Jaw", "tooth"))
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
    # (z: authored height; the belly now hangs to 0.22 above the ground, 0.39 authored)
    trunk = (~np.char.startswith(ds, "Tail") & ~np.isin(ds, ["Head", "Jaw", "EarL", "EarR", "Neck"]) & ~legs
             & (y > -0.36) & (y < 0.5) & (z > 0.33))
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
    hz = HZ + (RODENT_DZ if variant == "rodent" else 0.0)
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
# The tints above are baked into the uploaded colour maps (textures.py, parts.py): the game sets nothing
# on the SurfaceAppearances at runtime.
BAKE_TINTS = True


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
        if variant == "rodent":
            return seg + 0.9 * pn  # bottle-brush: out from the bone every way
        # a squirrel's tail hairs part along the bone and lie out to the two sides and back
        out = np.zeros_like(perp)
        out[:, 0] = np.clip(perp[:, 0] / 0.05, -1, 1)
        return seg * 0.8 + out * 0.85 + 0.12 * pn
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
    ear = np.char.startswith(dom, "Ear")
    feet = np.char.endswith(dom, "_Toe") | np.char.endswith(dom, "_Foot")
    head = np.isin(dom, ["Head", "Jaw"])
    # how much of each texel belongs to the tail, the head and the lower legs: the skin weights, which
    # change smoothly over the surface (the texel's one dominant bone changes at a line, and a colour
    # that switched on it drew a ring round the tail's root like the seam of a sleeve)
    names = list(tx["bone_names"])

    def weight_of(pred):
        cols = [i for i, b in enumerate(names) if pred(b)]
        return np.asarray(tx["W"][:, cols].sum(axis=1), dtype=np.float32)

    tailw = weight_of(lambda b: b.startswith("Tail"))
    headw = weight_of(lambda b: b in ("Head", "Jaw", "EarL", "EarR"))
    shinw = weight_of(lambda b: b.endswith(("_Lower", "_Foot", "_Toe")))
    footw = weight_of(lambda b: b.endswith(("_Foot", "_Toe")))
    tail = tailw > 0.5
    # --- strands: fine hairs, locks and clumps; the tail's are longer and coarser -------------------
    lscale = np.where(head | feet, 0.6, 1.0 + 0.8 * sst(0.2, 0.8, tailw)).astype(np.float32)
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
    if rodent:
        g = np.where(feet, g * 0.86, g)
    # face: pale eye ring, lighter cheeks and muzzle
    # the distance to the nearer eye's rim, measured as if both had the reference radius (the rodent's
    # eyes are two sizes)
    r_eye = eye_radius(variant, -1)
    d_eye = r_eye + np.minimum(
        np.linalg.norm(P - lm["eyeL"], axis=1) - eye_radius(variant, 1),
        np.linalg.norm(P - lm["eyeR"], axis=1) - eye_radius(variant, -1),
    )
    ring = sst(r_eye + 0.003, r_eye + 0.010, d_eye) * (1 - sst(r_eye + 0.016, r_eye + 0.032, d_eye))
    g = np.where(head, g + 0.10 * (1 - dorsal) * (1 - ring), g)
    g = g * (1 - 0.0 * ring) + ring * (0.98 - g) * 0.85
    # tail: coarser, more contrasty hair (its colours are laid over this below), coming in gradually from
    # the rump
    tk = sst(0.3, 0.8, tailw)
    g = g * (1 - tk) + (0.66 + (fine - 0.5) * 0.42) * tk
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
    bare = np.zeros(n, dtype=np.float32)  # how bare the skin is (no fur tufts grow where it is)
    natv = nat.copy()
    alpha0 = alpha.copy()  # the tint mask as the overrides alone leave it (grade() below does not touch it)

    def override(mask, col, a=0.0, r=None, k=None, skin=False):
        m = mask if k is None else mask & (k > 0)
        w = (np.ones(n) if k is None else k)[m]
        col = np.asarray(col, np.float32)
        natv[m] = natv[m] * (1 - w[:, None]) + (col[m] if col.ndim == 2 else col) * w[:, None]
        alpha[m] = alpha[m] * (1 - w) + a * w
        alpha0[m] = alpha0[m] * (1 - w) + a * w
        if r is not None:
            rough[m] = rough[m] * (1 - w) + r * w
        ov[m] = True
        if skin:
            bare[m] = np.maximum(bare[m], w)

    def grade(col, k):
        """Lay a colour over the coat where k (0..1) says: still fur, with its strands and relief."""
        k = np.clip(np.asarray(k, np.float32), 0, 1)
        col = np.asarray(col, np.float32)
        natv[:] = natv * (1 - k[:, None]) + (col if col.ndim == 2 else col[None, :]) * k[:, None]
        alpha[:] = alpha * (1 - k)

    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    s_t, x_t, r_t, ax_t = tail_coords(P)
    hw_t = plume_half_width(s_t, variant)
    # across the tail's brush: 0 on its midline, 1 at the edge of the mesh
    ul = np.clip(np.abs(x_t - plume_shift(s_t, variant)) / np.maximum(hw_t, 1e-3), 0, 1.3).astype(np.float32)
    fur = (hard == 0).astype(np.float32)
    coat = fur * (1 - sst(0.12, 0.5, headw)) * (1 - m)  # the body's coat: not the face, not the cream belly
    if not rodent:
        # --- the back, seen from behind and above ----------------------------------------------------
        # A darker stripe down the spine from the nape to the tail's root and lighter, warmer flanks: the
        # back is no longer one flat rust, so its bending shows, and the haunches read as two round forms.
        wob = 0.02 * np.sin(y * 31.0) + 0.012 * np.sin(y * 67.0 + 1.3)
        stripe = (1 - sst(0.045, 0.15, np.abs(x) + wob)) * sst(0.2, 0.7, N[:, 2]) * coat * (1 - tk)
        grade(natv * np.array([0.66, 0.60, 0.56], np.float32), stripe * 0.9)
        flank = sst(0.7, 0.25, N[:, 2]) * sst(-0.7, -0.25, N[:, 2]) * coat * (1 - tk) * (1 - sst(0.3, 0.7, footw))
        gold = natv * np.array([1.2, 1.16, 1.02], np.float32) + np.array([0.035, 0.02, 0.0], np.float32)
        grade(gold, flank * 0.7)
        # the pale bands of the guard hairs are buff, not orange: a grizzle over the back and rump
        grade(_hex("#d9a970") * (0.9 + 0.2 * fine)[:, None], sst(0.2, 0.08, guard) * dorsal * coat * (1 - tk) * 0.32)
        # --- the tail: a rust middle the colour of the back's stripe, a dark band, a frosted edge ----
        grow = sst(0.03, 0.2, s_t)  # the root keeps the rump's colours
        tone = ((0.72 + 0.56 * fine) * (0.86 + 0.28 * H))[:, None]
        edge = np.maximum(hw_t - np.abs(x_t), 0.0).astype(np.float32)  # studs in from the feather's edge
        mid = sst(0.03, 0.1, np.abs(x_t).astype(np.float32))
        tcol = _hex("#7b4524")[None, :] * (1 - mid)[:, None] + _hex("#a85e30")[None, :] * mid[:, None]
        band = (1 - sst(0.03, 0.085, edge + (fine - 0.5) * 0.05)) * grow
        band = band * (0.88 - 0.4 * sst(0.55, 0.9, np.abs(N[:, 0])))  # (the thin edge, seen from the side, is not a black line)
        tcol = tcol * (1 - band)[:, None] + _hex("#38231a")[None, :] * band[:, None]
        tcol = tcol * tone
        # streaks of pale hair tips lie over the dark band, more of them toward the edge (the fringe
        # itself is the cards': the mesh's edge stays dark under their roots)
        frost = sst(0.68, 0.86, guard) * (1 - sst(0.015, 0.085, edge)) * 0.7 * grow
        tcol = tcol * (1 - frost)[:, None] + (_hex("#e4d0aa")[None, :] * (0.88 + 0.24 * fine)[:, None]) * frost[:, None]
        grade(tcol, tk * fur)
        # --- paws: the colour of the coat, a little warmer (they were cream to the finger tips and read as
        # bone-white hooks beside the head on a trunk); the hind feet are no longer darker than the leg
        grade(_hex("#b26a3a")[None, :] * (0.82 + 0.36 * fine)[:, None], sst(0.3, 0.8, footw) * fur * 0.75)

    # cream chin, throat and cheek undersides, with a furry broken edge (painted, never a mesh edge)
    cream = _hex("#8f7359") if rodent else _hex("#e4c9a0")
    # feathered: the edge breaks up along the hairs (owner agreed, 2026-11-10)
    ck = np.clip(cream_face(P, N, tx["dom"], variant) + (fine - 0.5) * 0.34 + (guard - 0.5) * 0.22, 0, 1)
    ck = sst(0.12, 0.88, ck)
    if not rodent:
        ck = ck * (1 - sst(0.25, 0.7, shinw))  # the chest's cream stops at the elbow
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
        # --- the tail from behind: a rat's bare tail with three ragged clumps of bristle, smouldering ----
        tuft = sst(0.075, 0.1, r_t) * tk  # on a clump: the brush stands off the tail's axis
        ratty = (1 - sst(0.068, 0.09, r_t)) * tk * sst(0.02, 0.07, s_t)  # the bare stretches between
        rings = 0.86 + 0.14 * np.sin(s_t * TAIL_LENGTH * (2 * math.pi / 0.03))
        rat = skin[None, :] * (rings * (0.82 + 0.3 * vn(P * 110.0, 71)))[:, None]
        rat = rat * (1 - 0.55 * sst(0.7, 0.85, fine))[:, None]  # a few dark hairs left on it
        override(hard == 0, rat, r=0.5, k=ratty * 0.92, skin=True)
        grade(_hex("#1b1210")[None, :] * (0.7 + 0.6 * fine)[:, None], tuft * 0.8)
        # The ember rim: the clumps' edges smoulder. It is furry and broken, not a painted stripe (it
        # follows the hairs and thins out in places), and it now runs over the upper and lower faces of each
        # clump toward its edge and round its far end as well as down its sides: the play camera looks
        # down on the tail from behind, and a rim on the sides alone was two thin lines from there.
        tipward = np.clip(np.einsum("ij,ij->i", N, ax_t.astype(np.float32)), 0, 1)
        rim_e = np.maximum(ul, sst(0.3, 0.9, tipward) * 0.95)
        ek = sst(0.5, 0.88, rim_e + (fine - 0.5) * 0.4 + (big - 0.5) * 0.35) * (0.5 + 0.5 * sst(0.3, 0.7, guard)) * tuft
        ecol = _hex("#7a3a22")[None, :] * (1 - fine)[:, None] + _hex("#d86a28")[None, :] * fine[:, None]
        hot = (sst(0.78, 0.94, guard) * sst(0.75, 1.0, rim_e))[:, None]
        ecol = ecol * (1 - hot) + _hex("#ffa548")[None, :] * hot
        grade(ecol, ek * 0.92)
        # --- the back from behind: the knobs of the spine have rubbed through the fur, a row of pale
        # knuckles down the dark hunch; and on the haunches, rump and flanks the fur has come out in
        # patches (mange), down to grey-pink skin with a few hairs left
        dk = np.full(n, 9.0, np.float32)
        for kc, kr in rodent_knobs():
            dk = np.minimum(dk, np.linalg.norm((P - kc.astype(np.float32)) / (kr.astype(np.float32) * 1.15), axis=1))
        knob = (1 - sst(0.95, 1.25, dk + (vn(P * 60.0, 77) - 0.5) * 0.25)) * (hard == 0)
        override(hard == 0, _hex("#a38c82")[None, :] * (0.85 + 0.3 * vn(P * 140.0, 78))[:, None], r=0.5, k=knob * 0.9, skin=True)
        mange = (sst(0.6, 0.67, fbm(P * 4.2, 3, seed=37)) * sst(-0.25, 0.05, y) * (1 - tk) * (1 - sst(0.1, 0.4, headw))
                 * (1 - sst(0.3, 0.7, footw)) * (1 - m) * (hard == 0))
        mcol = skin[None, :] * ((0.78 + 0.4 * vn(P * 90.0, 38)) * (1 - 0.5 * sst(0.72, 0.86, fine)))[:, None]
        override(hard == 0, mcol, r=0.55, k=mange * 0.8, skin=True)
        # one small bald patch with an old pale scar across it
        for i, pt in enumerate(RODENT_PATCHES):
            c = np.array(pt["c"], np.float32)
            d = np.linalg.norm(P - c, axis=1)
            edge = pt["r"] * (0.85 + 0.3 * vn(P * 40.0, 40 + i))
            k = 1 - sst(edge * 0.75, edge, d)
            col = skin * (0.85 + 0.3 * vn(P * 120.0, 50 + i))[:, None]
            override(hard == 0, col, r=0.5, k=k, skin=True)
            a, b = pt["stitch"]
            ds, _ts = _seg_dist(P, a, b)
            override(hard == 0, _hex("#c9b0a6"), r=0.45, k=(1 - sst(0.004, 0.009, ds)) * (k > 0.3))
        # sleepless dark hollows round the eyes, in place of a squirrel's pale ring
        hollow = sst(r_eye + 0.004, r_eye + 0.014, d_eye) * (1 - sst(r_eye + 0.03, r_eye + 0.075, d_eye))
        override(head, _hex("#170d0c") * (0.8 + 0.4 * fine)[:, None], k=hollow * 0.72 * (hard == 0))
        # the inside of the grin: dark, wet gum along the cut from each corner to the front
        gdrop = np.array([0, 0, RODENT_DZ])
        g0, g1, g2 = GRIN_FRONT + gdrop, GRIN_MID + gdrop, GRIN_CORNER + gdrop
        flip = np.array([-1, 1, 1])
        dm = np.minimum.reduce([
            _seg_dist(P, g0, g1)[0], _seg_dist(P, g1, g2)[0],
            _seg_dist(P, g0 * flip, g1 * flip)[0], _seg_dist(P, g1 * flip, g2 * flip)[0],
        ])
        override(head | (dom == "Jaw"), _hex("#2e0c0e"), r=0.3, k=(1 - sst(0.014, 0.03, dm)) * (hard == 0))
        # thin, patchy fur: grey-pink skin shows through here and there
        mn = fbm(P * 12.0, 3, seed=31)
        thin = sst(0.66, 0.76, mn) * (hard == 0) * (1 - np.clip(ck, 0, 1))
        override(hard == 0, skin * (0.8 + 0.4 * vn(P * 90.0, 32))[:, None], r=0.55, k=thin * 0.5)
        # sore, reddened eyelids
        override(head, _hex("#7a2c2a"), r=0.4, k=(1 - sst(r_eye + 0.004, r_eye + 0.014, d_eye)) * 0.45)
    rgb = tools["finish_rgb"](grey, alpha, natv, region, tb, tp)
    # flatter relief on bare skin, claws and teeth
    flat = (alpha0 < 0.5) & ov
    gT = np.where(flat, gT * 0.25, gT)
    gB = np.where(flat, gB * 0.25, gB)
    # the crease where the tail leaves the rump baked as a dark ring: less occlusion round the root
    root = 1 - sst(0.1, 0.3, np.linalg.norm(P - np.array(TAIL0[0], np.float32), axis=1))
    return {
        "cards": ((hard == 0) & ~flat & (bare < 0.4)).astype(np.float32),
        "rgb": rgb.astype(np.float32),
        "alpha": np.clip(alpha, 0, 1).astype(np.float32),
        "rough": np.clip(rough, 0.05, 1).astype(np.float32),
        "height": H,
        "slope_T": gT.astype(np.float32),
        "slope_B": gB.astype(np.float32),
        "tint_by_region": [tb, tp],
        "tints_hex": tints,
        "ao_strength": 0.7 * (1 - 0.6 * root),
    }


# ---- fur cards, blood ---------------------------------------------------------------------------------

SCALE = 1.0
VIEW_CENTER = (0.0, 0.45, 0.6)

# The cards (parts.build_cards_grouped) are what makes the outline furry instead of a mesh edge. Seen from
# the play camera the outline that matters is the tail's, then the haunches', rump's and flanks'.
#   squirrel: fringe = the long guard hairs along the two edges of the tail's feather and round its tip,
#             lying in the feather's plane, dark at the root and pale and thin at the tip (the halo that
#             makes a squirrel's tail read as a plume); plume = shorter hairs over its upper and lower
#             faces, lying out and back from the midline; coat = the body.
#   rodent:   bristle = stiff hairs standing out of the tail's three clumps every way, ember at the tip;
#             hackle = raised spikes along the spine, between its knobs; coat = the thin body fur.
LEVELS = [0.52, 0.70, 0.85, 0.98]  # the coat cells' brightness under the Body tint


def card_groups(variant):
    """[(group, share of the card triangles, quads along a card)]; a card of q quads costs 4 q triangles."""
    if variant == "rodent":
        return [("bristle", 0.32, 1), ("hackle", 0.2, 1), ("coat", 0.48, 1)]
    return [("fringe", 0.21, 1), ("plume", 0.17, 1), ("coat", 0.62, 1)]


def card_cells(variant):
    """The card atlas: 4 x 4 cells. 0-3 coat locks and 4-7 coat tufts (dark to light), 8-9 and 10-11 the
    tail's two kinds, 12-13 and 14-15 two more of the coat's."""
    tint = _hex(TINTS[variant]["FurCards"]).astype(np.float64)

    def ramp(*stops):
        return [(t, _hex(c).astype(np.float64) if isinstance(c, str) else np.asarray(c, np.float64)) for t, c in stops]

    rodent = variant == "rodent"
    lock = dict(strands=16 if rodent else 28, spread=0.13, bend=0.22 if rodent else 0.12, height=(0.3, 1.0) if rodent else (0.55, 1.0),
                width=(0.013, 0.029) if rodent else (0.01, 0.022))
    tuft = dict(strands=24 if rodent else 46, spread=0.2, bend=0.36 if rodent else 0.2, height=(0.3, 1.0) if rodent else (0.55, 1.0),
                width=(0.013, 0.029) if rodent else (0.01, 0.022))
    cells = [dict(lock, ramp=ramp((0, tint * lv * 0.86), (1, np.minimum(tint * lv * 1.04, 1)))) for lv in LEVELS]
    cells += [dict(tuft, ramp=ramp((0, tint * lv * 0.86), (1, np.minimum(tint * lv * 1.04, 1)))) for lv in LEVELS]
    if rodent:
        ember = ramp((0, "#17100d"), (0.42, "#2a1610"), (0.66, "#8a3a1c"), (0.84, "#e06a24"), (1, "#ffab4a"))
        spike = ramp((0, "#0f0a09"), (0.7, "#1c1310"), (1, "#4a3a33"))
        cells += [dict(strands=9, spread=0.16, bend=0.3, height=(0.5, 1.0), width=(0.03, 0.06), fade=0.45, ramp=ember),
                  dict(strands=14, spread=0.22, bend=0.4, height=(0.4, 1.0), width=(0.03, 0.06), fade=0.45, ramp=ember),
                  dict(strands=7, spread=0.14, bend=0.25, height=(0.6, 1.0), width=(0.03, 0.055), fade=0.6, ramp=spike),
                  dict(strands=11, spread=0.2, bend=0.35, height=(0.45, 1.0), width=(0.03, 0.055), fade=0.6, ramp=spike)]
        wisp = ramp((0, "#4a3830"), (1, "#a8958a"))
        dark = ramp((0, "#17100d"), (1, "#33211a"))
        cells += [dict(strands=6, spread=0.2, bend=0.45, height=(0.3, 1.0), width=(0.02, 0.04), ramp=wisp),
                  dict(strands=9, spread=0.24, bend=0.5, height=(0.3, 1.0), width=(0.02, 0.04), ramp=wisp),
                  dict(lock, ramp=dark), dict(tuft, ramp=dark)]
    else:
        # a guard hair of the tail's edge: dark where it leaves the brush, then pale to its thin tip
        guard = ramp((0, "#3d2619"), (0.16, "#553622"), (0.38, "#bd9a6c"), (0.66, "#e0cba3"), (1, "#f0e3c8"))
        over = ramp((0, "#7a4526"), (0.45, "#4a2d1e"), (0.8, "#55392a"), (1, "#a8875f"))
        cells += [dict(strands=30, spread=0.2, bend=0.16, height=(0.45, 1.0), width=(0.012, 0.024), fade=0.92, opacity=0.8, ramp=guard),
                  dict(strands=42, spread=0.27, bend=0.24, height=(0.4, 1.0), width=(0.012, 0.024), fade=0.92, opacity=0.8, ramp=guard),
                  dict(lock, strands=36, ramp=over), dict(tuft, strands=54, ramp=over)]
        pale = ramp((0, "#a8602f"), (0.6, "#bb7640"), (1, "#d9a568"))  # the flanks' and haunches' pale-tipped hair
        dark = ramp((0, "#6e3e22"), (0.6, "#553019"), (1, "#3d2518"))  # the dark-tipped hair of the spine's stripe
        cells += [dict(lock, ramp=pale), dict(tuft, ramp=pale), dict(lock, ramp=dark), dict(tuft, ramp=dark)]
    return {"cols": 4, "rows": 4, "cells": cells, "seed": 8 if rodent else 7}


def card_density(c, n, dom, variant, group="coat"):
    """How thickly a group's cards grow at face centres c (lowered space) with normals n."""
    c = U(np.asarray(c))
    n = np.asarray(n)
    dom = np.asarray(dom).astype(str)
    d = np.zeros(len(c))
    tail = np.char.startswith(dom, "Tail")
    torso = np.isin(dom, list(TORSO))
    s, _xs, r_ax, axis = tail_coords(c)
    tipward = np.einsum("ij,ij->i", n, axis)
    if group == "fringe":  # the feather's two edges, and round its tip
        edge = np.maximum(_sstep(0.4, 0.75, np.abs(n[:, 0])), _sstep(0.3, 0.7, tipward))
        d[tail] = (edge * _sstep(0.03, 0.12, s) * (0.7 + 0.5 * _sstep(0.15, 0.6, s)))[tail]
        return d
    if group == "plume":  # its upper and lower faces
        d[tail] = ((1 - _sstep(0.55, 0.85, np.abs(n[:, 0]))) * _sstep(0.0, 0.08, s))[tail]
        return d
    if group == "bristle":  # the rodent's three clumps
        d[tail] = _sstep(0.08, 0.1, r_ax)[tail]
        return d
    if group == "hackle":  # along the rodent's spine and nape
        d[(torso | (dom == "Neck")) & (n[:, 2] > 0.7) & (np.abs(c[:, 0]) < 0.085)] = 1.0
        return d
    # the coat. What breaks the outline from behind: the sides of the haunches, the rump, the flanks and
    # the fringe of the belly; the top of the back is seen flat on and needs less
    side = np.sqrt(np.clip(1 - n[:, 2] ** 2, 0, 1))
    d[torso] = (0.55 + 0.7 * side + 0.5 * np.clip(n[:, 1], 0, 1))[torso]
    d[dom == "Neck"] = 1.1
    haunch = np.isin(dom, ["BackL_Upper", "BackR_Upper"])
    d[haunch] = (1.0 + 0.8 * side)[haunch]
    d[np.isin(dom, ["FrontL_Upper", "FrontR_Upper"])] = 0.5
    d[np.isin(dom, ["BackL_Lower", "BackR_Lower", "FrontL_Lower", "FrontR_Lower"])] = 0.3
    head = dom == "Head"
    d[head] = 0.55 * np.clip(np.abs(n[head, 0]) * 1.3, 0, 1) * (c[head, 1] > -1.02)  # cheeks, not the face
    d[dom == "Jaw"] = 0.25
    ears = np.char.startswith(dom, "Ear")
    d[ears] = 2.4 * (c[ears, 2] > 1.37)  # tufts at the tips
    if variant == "rodent":
        d[tail] = 0.0
        d[haunch] *= 0.8
        # no tufts on or near the bald patch
        for pt in RODENT_PATCHES:
            d[np.linalg.norm(c - np.array(pt["c"]), axis=1) < pt["r"] * 1.3] = 0
    else:
        d[tail] = (0.8 * (1 - _sstep(0.02, 0.1, s)))[tail]  # the rump's fur runs on over the tail's root
    return d


def _unit(v):
    return v / np.maximum(np.linalg.norm(v, axis=1, keepdims=True), 1e-9)


def card_tufts(info, variant, group, rng):
    """The shape of each card of a group at its root (info: P, N, F in the lowered space, dom, rgb = the
    body's finished colour there). Returns length, width, cell (atlas cell) and either lift/roll/droop
    (the card rises from the skin along the fur) or dir/dir2/side (its own directions)."""
    P, N, F = info["P"], info["N"], info["F"]
    dom = np.asarray(info["dom"]).astype(str)
    k = len(P)
    rodent = variant == "rodent"
    tint = _hex(TINTS[variant]["FurCards"]).astype(np.float64)
    # the coat cell whose brightness is nearest the body's at the root; a lock or a tuft at random
    grey = info["rgb"].mean(axis=1) / tint.mean()
    level = np.argmin(np.abs(grey[:, None] - np.array(LEVELS)[None]), axis=1)
    coat_cell = level + 4 * rng.integers(0, 2, k)
    pair = rng.integers(0, 2, k)
    s, xs, _r, axis = tail_coords(U(P))
    X = np.array([1.0, 0.0, 0.0])
    if group == "fringe":
        sgn = np.where(np.abs(xs) > 0.01, np.sign(xs), rng.choice([-1.0, 1.0], k))
        lateral = sgn[:, None] * X[None, :]
        up = np.cross(np.tile(X, (k, 1)), axis)  # the feather's own upward normal
        tipward = np.clip(np.einsum("ij,ij->i", N, axis), 0, 1)
        # out to the side and back toward the tip; at the tip itself the hairs fan round the end
        ang = rng.uniform(0.7, 1.15, k) * (1 - tipward) + rng.uniform(0.0, 0.75, k) * tipward
        d = axis * np.cos(ang)[:, None] + lateral * np.sin(ang)[:, None] + up * rng.normal(0, 0.28, k)[:, None]
        d = _unit(d)
        d2 = _unit(d * 0.8 + axis * 0.38 - up * 0.08)  # the outer half sweeps back
        tilt = rng.normal(0, 0.4, k)  # mostly in the feather's plane, each one rolled a little
        flat = _unit(np.cross(up, d))
        side = _unit(flat * np.cos(tilt)[:, None] + np.cross(d, flat) * np.sin(tilt)[:, None])
        near = 0.72 + 0.28 * _sstep(0.08, 0.4, s)  # shorter by the root, so the tail leaves the rump narrow
        return {"length": rng.uniform(0.18, 0.28, k) * near, "width": rng.uniform(0.065, 0.105, k) * near,
                "dir": d, "dir2": d2, "side": side, "cell": 8 + pair}
    if group == "plume":
        edge = plume_half_width(s, variant) - np.abs(xs)  # studs in from the feather's edge
        cell = np.where(edge < 0.09, 10 + pair, np.where(rng.random(k) < 0.2, 14 + pair, coat_cell))
        # one in three stands up off the face: seen from the side the feather is a brush, not a blade
        stand = rng.random(k) < 0.34
        lift = np.where(stand, rng.uniform(0.55, 1.0, k), rng.uniform(0.15, 0.4, k))
        cell = np.where(stand & (edge < 0.12), 8 + pair, cell)
        return {"length": rng.uniform(0.15, 0.23, k), "width": rng.uniform(0.06, 0.09, k), "lift": lift,
                "roll": np.where(stand, rng.uniform(-1.2, 1.2, k), rng.normal(0, 0.3, k)), "droop": np.full(k, 0.3), "cell": cell}
    if group == "bristle":
        # bottle-brush: straight out of the clump every way, leaning toward the tip
        d = _unit(N * rng.uniform(0.7, 1.0, k)[:, None] + axis * rng.uniform(0.1, 0.7, k)[:, None] + rng.normal(0, 0.25, (k, 3)))
        ref = _unit(np.cross(d, rng.normal(0, 1, (k, 3))))
        return {"length": rng.uniform(0.12, 0.23, k), "width": rng.uniform(0.05, 0.085, k), "dir": d, "side": ref,
                "cell": np.where(rng.random(k) < 0.78, 8 + pair, 10 + pair)}
    if group == "hackle":
        d = _unit(np.array([0.0, 0.5, 0.85])[None, :] + rng.normal(0, 0.22, (k, 3)))
        ref = _unit(np.cross(d, rng.normal(0, 1, (k, 3))))
        return {"length": rng.uniform(0.1, 0.18, k), "width": rng.uniform(0.04, 0.06, k), "dir": d, "side": ref, "cell": 10 + pair}
    # the coat
    head = np.isin(dom, ["Head", "Jaw"]) | np.char.startswith(dom, "Ear")
    haunch = np.isin(dom, ["BackL_Upper", "BackR_Upper"])
    L = np.where(head, rng.uniform(0.04, 0.06, k), np.where(haunch, rng.uniform(0.08, 0.125, k), rng.uniform(0.07, 0.11, k)))
    Wd = np.where(head, rng.uniform(0.028, 0.04, k), rng.uniform(0.04, 0.062, k))
    lift = rng.uniform(0.22, 0.45, k)
    roll = rng.uniform(-0.6, 0.6, k)
    droop = np.full(k, 0.28)
    cell = coat_cell.copy()
    if rodent:
        L = L * rng.uniform(0.75, 1.05, k)
        Wd = Wd * 0.9
        lift = lift + rng.uniform(0.0, 0.35, k)  # ruffled, standing up a little
        droop = rng.uniform(0.15, 0.45, k)
        r = rng.random(k)
        cell = np.where(~head & (r < 0.14), 12 + pair, np.where(~head & (r < 0.4), 14 + pair, cell))
    else:
        # pale-tipped hair on the flanks and haunches, dark-tipped on the spine's stripe
        sideways = np.sqrt(np.clip(1 - N[:, 2] ** 2, 0, 1))
        r = rng.random(k)
        stripe = ~head & (N[:, 2] > 0.6) & (np.abs(P[:, 0]) < 0.12)
        cell = np.where(~head & ~stripe & (sideways > 0.6) & (r < 0.3), 12 + pair, cell)
        cell = np.where(stripe & (r < 0.6), 14 + pair, cell)
    return {"length": L, "width": Wd, "lift": lift, "roll": roll, "droop": droop, "cell": cell}


def blood_faces(lo, co, W, bone_names):
    """Faces under the rodent's blood shell: mouth corners and chin, the front claws and fingers."""
    me = lo.data
    lm = landmarks("rodent")
    hz = HZ + RODENT_DZ
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
    hz = HZ + RODENT_DZ
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
