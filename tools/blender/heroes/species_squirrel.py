"""Squirrel (and spicy rodent) anatomy: skeleton joints and the signed-distance sculpt.

Blender coordinates, studs: ground z = 0, the animal faces -Y, its left side is +X, Root at the
origin under the middle of the body. About 1.2 studs at the shoulder (brief v2 §15, RigSpec), 2.0 from
nose to rump, the tail about as long again. Bone names are RigSpec.squirrel's, exactly.

The rodent (variant="rodent") is the same skeleton (so every clip is shared) with zombie-lite flesh:
leaner, a ridge of ribs on each flank, sunken bald patches, a ragged right ear, a lower head with a
wider crazed grin and buck teeth, slightly oversized eye sockets, a thinner, patchy tail.
"""
import math

import numpy as np

from sdf import Ellipsoid, RoundCone, frame_from, mirror_pair, rot_x, rot_y, rot_z

SPECIES = "squirrel"
RIG_ID = "squirrel"  # the rodent shares the rig and every clip
CLIPS_MODULE = "clips_squirrel"

# ---- skeleton (bone head positions) ---------------------------------------------------------------
# name: (head xyz, parent, proxy tail xyz or a child name the proxy bone points at)
TAIL = [
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

FRONT = {  # left side (+X); right is mirrored
    "Upper": (0.15, -0.46, 0.76),  # shoulder joint
    "Lower": (0.15, -0.36, 0.47),  # elbow (points back)
    "Foot": (0.14, -0.49, 0.12),  # wrist
    "Toe": (0.14, -0.585, 0.034),  # knuckles
    "End": (0.14, -0.67, 0.012),  # finger tips
}
BACK = {
    "Upper": (0.17, 0.36, 0.84),  # hip joint
    "Lower": (0.215, 0.06, 0.44),  # knee (points forward, inside the haunch)
    "Foot": (0.19, 0.38, 0.10),  # hock (heel, a little off the ground)
    "Toe": (0.18, 0.0, 0.032),  # ball of the foot
    "End": (0.18, -0.12, 0.012),  # toe tips
}


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
        add(f"Tail{i + 1}", TAIL[i], "Hips" if i == 0 else f"Tail{i}", TAIL[i + 1])
    for leg, spec, parent in (("Front", FRONT, "Chest"), ("Back", BACK, "Hips")):
        for side, sx in (("L", 1), ("R", -1)):
            segs = ["Upper", "Lower", "Foot", "Toe"]
            for i, seg in enumerate(segs):
                h = np.array(spec[seg]) * [sx, 1, 1]
                t = np.array(spec[segs[i + 1]] if i < 3 else spec["End"]) * [sx, 1, 1]
                add(f"{leg}{side}_{seg}", h, parent if i == 0 else f"{leg}{side}_{segs[i - 1]}", t)
    return J


HZ = 1.19  # skull centre height
EYE_L = np.array([0.110, -0.93, 1.245])
EYE_R_RODENT = 0.064
EYE_R = 0.052
NOSE = np.array([0.0, -1.165, 1.10])


def eye_radius(variant):
    return EYE_R_RODENT if variant == "rodent" else EYE_R


def eye_gaze(side):
    return np.array([side * 0.86, -0.48, 0.16])


EYE_STYLE = "squirrel"


def eye_centre(variant, side=1):
    c = EYE_L.copy()
    if variant == "rodent":
        c = c + [0.012, 0.004, -0.026]  # the rodent carries its head lower; its eyes bulge a little
    c[0] *= side
    return c


def landmarks(variant):
    """Named points the texture painter and the card scatterer use."""
    dz = -0.03 if variant == "rodent" else 0.0
    return {
        "nose": NOSE + [0, 0, dz],
        "eyeL": eye_centre(variant, 1),
        "eyeR": eye_centre(variant, -1),
        "chin": np.array([0.0, -1.05, 1.00 + dz]),
        "earL": np.array([0.12, -0.79, 1.41 + dz]),
        "earR": np.array([-0.12, -0.79, 1.41 + dz]),
        "tailTip": np.array(TAIL[-1]),
        "tailRoot": np.array(TAIL[0]),
    }


def _limb(a, b, ra, rb, k, tag=""):
    return RoundCone(a, b, ra, rb, k=k, tag=tag)


def sculpt(variant="squirrel"):
    """The SDF primitive list (left/right pairs mirrored)."""
    rodent = variant == "rodent"
    lean = 0.86 if rodent else 1.0  # the rodent is gaunt through the waist and belly
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
    P.append(Ellipsoid((0, -0.86, hz), (0.168, 0.19, 0.158), k=0.07, tag="skull"))
    P.append(Ellipsoid((0, -0.90, hz + 0.06), (0.12, 0.14, 0.09), k=0.06, tag="brow"))
    P += mirror_pair([Ellipsoid((0.088, -0.955, hz - 0.075), (0.088, 0.10, 0.08), k=0.05, tag="cheek")])
    P.append(Ellipsoid((0, -1.045, hz - 0.08), (0.082, 0.105, 0.075), k=0.05, tag="muzzle"))
    P.append(Ellipsoid((0, -1.14, hz - 0.088), (0.038, 0.032, 0.032), k=0.025, tag="nose"))
    P += mirror_pair([Ellipsoid((0.042, -1.085, hz - 0.11), (0.042, 0.05, 0.036), k=0.03, tag="whiskerpad")])
    P.append(RoundCone((0, -0.86, hz - 0.14), (0, -1.05, hz - 0.185), 0.075, 0.036, k=0.045, tag="jaw"))
    corner = (0.075, -0.985, hz - 0.15) if rodent else (0.056, -1.005, hz - 0.142)
    P += mirror_pair([RoundCone(corner, (0.0, -1.105, hz - 0.142), 0.011 if rodent else 0.007, 0.006, k=0.012, op="sub", tag="mouth")])
    er = eye_radius(variant) + 0.003
    ec = eye_centre(variant, 1)
    P += mirror_pair([Ellipsoid(ec, (er, er, er), k=0.02, op="sub", tag="eyesocket")])
    P += mirror_pair([Ellipsoid(ec + [-0.012, 0.01, 0.05], (0.05, 0.065, 0.022), k=0.022, tag="brow")])
    # ears: short, broad, rounded leaves tilted out and back, cupped on the front
    tilt = rot_y(0.32) @ rot_x(-0.12)
    base = np.array([0.11, -0.80, 1.33 + dz])
    c = base + tilt @ np.array([0, 0, 0.07])
    P += mirror_pair([Ellipsoid(c, (0.06, 0.022, 0.085), axes=tilt, k=0.03, tag="ear")])
    cup = c + tilt @ np.array([0, -0.019, 0.014])
    P += mirror_pair([Ellipsoid(cup, (0.040, 0.009, 0.060), axes=tilt, k=0.005, op="sub", tag="earcup")])
    # --- forelegs ---------------------------------------------------------------------------------------
    sh, el, wr, kn = (np.array(FRONT[k]) for k in ("Upper", "Lower", "Foot", "Toe"))
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
    hp, kn2, hk, ba = (np.array(BACK[k]) for k in ("Upper", "Lower", "Foot", "Toe"))
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
    plume = [0.42, 0.7, 0.9, 1.0, 1.0, 0.97, 0.88, 0.7, 0.42]
    if rodent:
        plume = [0.32, 0.46, 0.6, 0.42, 0.62, 0.5, 0.48, 0.36, 0.25]  # thin and ragged where the fur fell out
    for i in range(8):
        a, b = np.array(TAIL[i]), np.array(TAIL[i + 1])
        P.append(RoundCone(a, b, 0.07 if i == 0 else 0.05, 0.045, k=0.05, tag="tailcore"))
        for f in (0.25, 0.75):
            m = a + (b - a) * f
            s = plume[i] * (1 - f) + plume[i + 1] * f
            P.append(Ellipsoid(m, (0.21 * s + 0.035, 0.13, 0.13 * s + 0.035), axes=frame_from(b - a), k=0.10, tag="plume"))
    P.append(Ellipsoid(np.array(TAIL[8]) + [0, -0.03, 0.0], (0.08 * plume[-1] + 0.03, 0.08, 0.07 * plume[-1] + 0.03), k=0.06, tag="plume"))
    if rodent:
        # ribs: four ridges along each flank, with grooves between them
        for i in range(4):
            y = -0.38 + i * 0.085
            a = np.array([0.215, y, 0.98])
            b = np.array([0.245, y + 0.05, 0.76])
            c = np.array([0.18, y + 0.09, 0.60])
            P += mirror_pair([
                RoundCone(a, b, 0.016, 0.017, k=0.022, tag="rib"),
                RoundCone(b, c, 0.017, 0.012, k=0.022, tag="rib"),
            ])
            g = np.array([0.0, 0.043, 0.0])
            P += mirror_pair([RoundCone(a + g + [0.03, 0, 0], b + g + [0.035, 0, 0], 0.014, 0.014, k=0.016, op="sub", tag="ribgroove")])
        for pt in RODENT_PATCHES:
            c = np.array(pt["c"])
            P.append(Ellipsoid(c, (pt["r"] * 0.8, pt["r"], pt["r"] * 0.8), k=0.03, op="sub", tag="bald"))
        P.append(Ellipsoid((-0.16, -0.78, 1.43 + dz), (0.035, 0.05, 0.03), k=0.006, op="sub", tag="earnotch"))
    return P


# The rodent's bald patches and the stitch lines over them (texture painter + sculpt agree).
RODENT_PATCHES = [  # centre on the skin surface, radius, stitch line (two points)
    {"c": (0.36, 0.26, 0.66), "r": 0.075, "stitch": ((0.34, 0.18, 0.74), (0.37, 0.34, 0.58))},
    {"c": (-0.25, -0.46, 0.92), "r": 0.065, "stitch": ((-0.22, -0.52, 0.99), (-0.27, -0.40, 0.85))},
    {"c": (0.06, 0.12, 1.21), "r": 0.055, "stitch": ((0.10, 0.05, 1.20), (0.01, 0.19, 1.22))},
]


def hard_parts(variant="squirrel"):
    """Claws and incisors: [(name, verts, faces, bone, kind)] (kind: claw | tooth)."""
    from geometry import curved_spike

    rodent = variant == "rodent"
    dz = -0.03 if rodent else 0.0
    hz = HZ + dz
    out = []
    kn = np.array(FRONT["Toe"])
    for side, sx in (("L", 1), ("R", -1)):
        for i, (dx, dy) in enumerate(((-0.034, 0.0), (-0.012, 0.013), (0.012, 0.013), (0.034, 0.0))):
            tip = (kn + [dx, -0.08 + dy, -0.021]) * [sx, 1, 1]
            v, f = curved_spike(tip + [0, 0.004, 0.006], (0, -1, -0.35), 0.038 if rodent else 0.032, 0.0085, curl=(0, 0.2, -1), curl_amt=0.9)
            out.append((f"claw_F{side}{i}", v, f, f"Front{side}_Toe", "claw"))
        ba = np.array(BACK["Toe"])
        for i, (dx, dy) in enumerate(((-0.038, 0.006), (-0.018, 0.016), (0.0, 0.02), (0.018, 0.016), (0.038, 0.006))):
            tip = (ba + [dx, -0.115 + dy, -0.02]) * [sx, 1, 1]
            v, f = curved_spike(tip + [0, 0.004, 0.006], (0, -1, -0.3), 0.04 if rodent else 0.034, 0.009, curl=(0, 0.2, -1), curl_amt=0.9)
            out.append((f"claw_B{side}{i}", v, f, f"Back{side}_Toe", "claw"))
    up_len = 0.062 if rodent else 0.026
    lo_len = 0.04 if rodent else 0.014
    for sx in (1, -1):
        crooked = 0.12 * sx if rodent else 0.0
        v, f = curved_spike((0.0095 * sx, -1.118, hz - 0.118), (crooked, -0.25, -1), up_len, 0.0105, curl=(0, 0.6, 0), curl_amt=0.35, sides=4, flat=1.5)
        out.append((f"tooth_U{sx}", v, f, "Head", "tooth"))
        v, f = curved_spike((0.008 * sx, -1.072, hz - 0.17), (0, -0.55, 1), lo_len, 0.009, curl=(0, 1, 0), curl_amt=0.3, sides=4, flat=1.4)
        out.append((f"tooth_L{sx}", v, f, "Jaw", "tooth"))
    return out


BUDGET = {"body_tris": 7300, "cards_tris": 6000, "rodent_cards_tris": 3000}
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
    c = np.asarray(c)
    n = np.asarray(n)
    x, y, z = c[:, 0], c[:, 1], c[:, 2]
    wob = 0.03 * np.sin(y * 23.0 + x * 9.0) + 0.02 * np.sin(y * 51.0 - z * 17.0)
    out = np.zeros(len(c))
    torso = np.isin(dom, list(TORSO))
    # belly and chest: low, facing down; the line rises toward the chest and the throat
    line = 0.70 + 0.06 * _sstep(0.2, -0.5, y) + wob
    belly = _sstep(-0.05, 0.35, -n[:, 2] + (line - z) * 2.5)
    out[torso] = belly[torso]
    neck = dom == "Neck"
    out[neck] = _sstep(0.0, 0.4, -n[neck, 2] + (0.9 - z[neck]) * 1.5 + wob[neck])
    head = dom == "Head"
    hz = HZ + (-0.03 if variant == "rodent" else 0.0)
    out[head] = _sstep(0.35, 0.7, -n[head, 2] + (hz - 0.12 - z[head]) * 3 + wob[head]) * (y[head] < -0.86)
    jaw = dom == "Jaw"
    out[jaw] = _sstep(0.25, 0.6, -n[jaw, 2] + wob[jaw])
    if variant == "rodent":
        out *= 0.92  # a dingier, narrower belly
    return out


# ---- fur flow and painting (textures.py calls these) ------------------------------------------------

# Tints (sRGB hex) for SurfaceAppearance.Color in TintMask mode: the colour map is greyscale where the
# tint applies, averaging about 0.78 (body) / 0.93 (pattern), so tint x map lands on the PuppetSpec
# stock colours (#9a5a32 rust back, #e4c9a0 cream belly; rodent #5a4231 / #857160).
TINTS = {
    "squirrel": {"Body": "#c27442", "Pattern": "#f5d8ac", "FurCards": "#c27442"},
    "rodent": {"Body": "#7d5d46", "Pattern": "#a08a74", "FurCards": "#7d5d46"},
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
    P, N, F, T, B = tx["P"], tx["N"], tx["F"], tx["T"], tx["B"]
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
    g = g + (fine - 0.5) * (0.30 + 0.25 * dorsal)  # agouti: banded guard hairs grizzle the back
    g = g - 0.22 * sst(0.62, 0.78, guard) * (0.4 + 0.6 * dorsal)  # dark-tipped guard hairs
    g = g + 0.10 * sst(0.25, 0.1, guard) * dorsal  # pale bands
    g = g * (0.80 + 0.36 * H)
    g = g + (big - 0.5) * 0.12
    g = np.where(feet, g * 0.86, g)
    # face: pale eye ring, lighter cheeks and muzzle
    r_eye = eye_radius(variant)
    d_eye = np.minimum(np.linalg.norm(P - lm["eyeL"], axis=1), np.linalg.norm(P - lm["eyeR"], axis=1))
    ring = sst(r_eye + 0.004, r_eye + 0.016, d_eye) * (1 - sst(r_eye + 0.03, r_eye + 0.055, d_eye))
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
    pat = pattern_field(P, N, tx["dom"], variant) + (fine - 0.5) * 0.3  # a furry, broken border
    m = sst(0.38, 0.62, pat)
    grey, alpha, nat = tools["region_colours"](region, m, g, gp, tb, tp)
    rough = 0.64 - 0.12 * (H - 0.5) + 0.08 * (1 - dorsal) + (big - 0.5) * 0.06
    rough = np.where(tail, rough + 0.04, rough)
    ov = np.zeros(n, dtype=bool)  # texels whose natural colour is overridden (alpha forced to 0)
    natv = nat.copy()

    def override(mask, col, a=0.0, r=None, k=None):
        m = mask if k is None else mask & (k > 0)
        w = (np.ones(n) if k is None else k)[m]
        natv[m] = natv[m] * (1 - w[:, None]) + np.asarray(col, np.float32) * w[:, None]
        alpha[m] = alpha[m] * (1 - w) + a * w
        if r is not None:
            rough[m] = rough[m] * (1 - w) + r * w
        ov[m] = True

    # nose pad (rhinarium) and the dark lip line under it
    d_nose = np.linalg.norm(P - lm["nose"], axis=1)
    override(head, _hex("#4e3530") * (0.85 + 0.3 * vn(P * 300.0, 3))[:, None] if False else _hex("#503631"), r=0.32, k=1 - sst(0.026, 0.036, d_nose))
    # eyelid rims: bare dark skin right around the eyeball
    lid = 1 - sst(r_eye + 0.002, r_eye + 0.009, d_eye)
    override(head, _hex("#7a2a2a") if rodent else _hex("#2a1e1a"), r=0.4, k=lid)
    # inner ears: thin pinkish skin with fine hairs
    inner = ear & (N[:, 1] < -0.15)
    override(ear, _hex("#9c6a60") if rodent else _hex("#b88a7c"), r=0.5, k=sst(-0.15, -0.45, N[:, 1]) * inner)
    # foot pads
    override(feet, _hex("#5c4440"), r=0.5, k=sst(-0.4, -0.75, N[:, 2]) * feet)
    # claws and teeth
    override(hard == 1, _hex("#2b2320") * 1.0, r=0.28)
    override(hard == 2, _hex("#e0b05a") if not rodent else _hex("#d8b25e"), r=0.22)
    if rodent:
        # mange: patchy thin fur showing grey-pink skin, bigger toward the haunches and the tail
        skin = _hex("#9e827c")
        bruise = _hex("#6e5560")
        mn = fbm(P * 14.0, 3, seed=31)
        thin = sst(0.56, 0.68, mn + 0.08 * tail + 0.05 * sst(0.0, 0.4, P[:, 1]))
        sk = skin * (0.8 + 0.4 * vn(P * 90.0, 32))[:, None] * (1 - 0.0)
        sk = sk * (1 - 0.35 * sst(0.5, 0.8, fbm(P * 30.0, 2, seed=33)))[:, None] + bruise * 0.0
        override(hard == 0, sk, r=0.55, k=thin * 0.85)
        # ribs: the fur is thin over them
        ribs = np.isin(dom, list(TORSO)) & (np.abs(P[:, 0]) > 0.17) & (P[:, 1] > -0.42) & (P[:, 1] < -0.02) & (P[:, 2] < 1.02) & (P[:, 2] > 0.6)
        override(ribs, skin * 0.92, r=0.55, k=ribs * 0.55 * sst(0.4, 0.7, np.abs(N[:, 0])))
        # stitched bald patches: bare bruised skin, a dark incision and cross stitches
        for i, pt in enumerate(RODENT_PATCHES):
            c = np.array(pt["c"], np.float32)
            d = np.linalg.norm(P - c, axis=1)
            edge = pt["r"] * (0.85 + 0.3 * vn(P * 40.0, 40 + i))
            k = 1 - sst(edge * 0.8, edge, d)
            col = skin * (0.85 + 0.3 * vn(P * 120.0, 50 + i))[:, None]
            col = col * (1 - 0.3 * sst(0.4, 0.9, d / pt["r"]))[:, None] + bruise * 0.3 * sst(0.4, 0.9, d / pt["r"])[:, None]
            override(hard == 0, col, r=0.5, k=k)
            a, b = pt["stitch"]
            ds, ts = _seg_dist(P, a, b)
            cut = 1 - sst(0.002, 0.005, ds)
            override(hard == 0, _hex("#4a1f1c"), r=0.4, k=cut * (k > 0.3))
            L = float(np.linalg.norm(np.array(b) - np.array(a)))
            ph = (ts * L / 0.022) % 1.0
            cross = (np.abs(ph - 0.5) < 0.12) & (ds < 0.016)
            override(hard == 0, _hex("#1c1714"), r=0.6, k=cross.astype(np.float32))
            gT = np.where(cross, gT + 0.4 * np.sign(vn(P * 500.0, 7) - 0.5), gT)
        # scabs here and there
        sc = sst(0.78, 0.86, fbm(P * 25.0, 2, seed=44)) * (hard == 0)
        override(hard == 0, _hex("#4a2620"), r=0.45, k=sc)
        # reddened, sore eyelids and nose
        override(head, _hex("#8a3030"), r=0.4, k=(1 - sst(r_eye + 0.006, r_eye + 0.02, d_eye)) * 0.7)
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
VIEW_CENTER = (0.0, 0.45, 0.85)


def card_density(c, n, dom, variant):
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
    if variant == "rodent":
        # no tufts on or near the stitched patches
        for pt in RODENT_PATCHES:
            d[np.linalg.norm(c - np.array(pt["c"]), axis=1) < pt["r"] * 1.3] = 0
    return d


def card_shape(P, N, F, dom, variant, rng):
    dom = np.asarray(dom).astype(str)
    k = len(P)
    tail = np.char.startswith(dom, "Tail")
    head = np.isin(dom, ["Head", "Jaw"])
    rodent = variant == "rodent"
    L = np.where(tail, rng.uniform(0.13, 0.22, k), np.where(head, rng.uniform(0.04, 0.06, k), rng.uniform(0.065, 0.105, k)))
    W = np.where(tail, rng.uniform(0.06, 0.10, k), np.where(head, rng.uniform(0.028, 0.04, k), rng.uniform(0.035, 0.055, k)))
    lift = np.where(tail, rng.uniform(0.35, 0.75, k), rng.uniform(0.22, 0.45, k))
    roll = np.where(tail, rng.uniform(-1.3, 1.3, k), rng.uniform(-0.6, 0.6, k))
    droop = np.full(k, 0.28)
    if rodent:
        L *= rng.uniform(0.6, 1.0, k)
        W *= 0.8
        lift = lift + rng.uniform(-0.1, 0.5, k)  # ragged, sticking out at odd angles
        droop = rng.uniform(0.1, 0.6, k)
    return {"length": L, "width": W, "lift": lift, "roll": roll, "droop": droop}


def blood_faces(lo, co, W, bone_names):
    """Faces under the rodent's blood shell: mouth corners and chin, the front claws and fingers."""
    me = lo.data
    lm = landmarks("rodent")
    hz = HZ - 0.03
    spots = [np.array([0.075, -0.985, hz - 0.15]), np.array([-0.075, -0.985, hz - 0.15]),
             np.array([0.0, -1.09, hz - 0.17]), np.array([0.0, -1.03, hz - 0.2])]
    kind = np.empty(len(me.polygons), dtype=np.int32)
    me.attributes["hard_kind"].data.foreach_get("value", kind)
    cen = np.empty(len(me.polygons) * 3, dtype=np.float32)
    me.polygons.foreach_get("center", cen)
    cen = cen.reshape(-1, 3)
    near = np.min([np.linalg.norm(cen - s, axis=1) for s in spots], axis=0) < 0.05
    domv = np.array(bone_names)[np.argmax(W, axis=1)]
    lv = np.empty(len(me.loops), dtype=np.int64)
    me.loops.foreach_get("vertex_index", lv)
    ls = np.empty(len(me.polygons), dtype=np.int64)
    me.polygons.foreach_get("loop_start", ls)
    fdom = domv[lv[ls]]
    paws = np.isin(fdom, ["FrontL_Toe", "FrontR_Toe"]) & (cen[:, 2] < 0.06)
    return (near | paws) & ~(kind == 2)


def blood_mask(P, tools):
    sst = tools["sstep"]
    vn = tools["vnoise"]
    hz = HZ - 0.03
    m = np.zeros(len(P), dtype=np.float32)
    for sx in (1, -1):
        c = np.array([0.075 * sx, -0.985, hz - 0.15])
        d = np.linalg.norm(P - c, axis=1)
        m = np.maximum(m, 1 - sst(0.012, 0.03, d))
        # a drip or two running down from the corner
        drip = (np.abs(P[:, 0] - (0.07 * sx + 0.01 * vn(P * 30.0, 3 + (sx > 0)))) < 0.009) & (P[:, 2] < c[2]) & (P[:, 2] > c[2] - 0.06)
        m = np.maximum(m, drip * (1 - sst(0.0, 0.06, c[2] - P[:, 2])) * 0.9)
    chin = np.linalg.norm(P - np.array([0.0, -1.06, hz - 0.19]), axis=1)
    m = np.maximum(m, (1 - sst(0.008, 0.03, chin)) * 0.8)
    paw = P[:, 2] < 0.08
    m = np.where(paw, np.maximum(m, sst(0.55, 0.7, vn(P * 60.0, 9)) * (1 - sst(0.02, 0.06, P[:, 2]))), m)
    speck = sst(0.72, 0.8, vn(P * 140.0, 13))
    m = np.maximum(m, speck * 0.85 * (m > 0.05))
    return np.clip(m * (0.7 + 0.3 * vn(P * 200.0, 17)), 0, 1).astype(np.float32)
