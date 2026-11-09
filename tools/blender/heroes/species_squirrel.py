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
EYE_L = np.array([0.118, -0.935, 1.245])
EYE_R_RODENT = 0.074
EYE_R = 0.062
NOSE = np.array([0.0, -1.165, 1.10])


def eye_radius(variant):
    return EYE_R_RODENT if variant == "rodent" else EYE_R


def eye_centre(variant, side=1):
    c = EYE_L.copy()
    if variant == "rodent":
        c = c + [0.010, 0.006, -0.026]  # the rodent carries its head lower
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
    cup = c + tilt @ np.array([0, -0.016, 0.014])
    P += mirror_pair([Ellipsoid(cup, (0.041, 0.012, 0.062), axes=tilt, k=0.006, op="sub", tag="earcup")])
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
