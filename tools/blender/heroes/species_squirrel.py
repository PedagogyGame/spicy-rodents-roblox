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
    (0.0, 0.62, 0.98),
    (0.0, 0.80, 1.08),
    (0.0, 0.98, 1.17),
    (0.0, 1.17, 1.24),
    (0.0, 1.37, 1.29),
    (0.0, 1.57, 1.32),
    (0.0, 1.77, 1.33),
    (0.0, 1.96, 1.32),
    (0.0, 2.14, 1.30),  # tip (end of Tail8)
]

FRONT = {  # left side (+X); right is mirrored
    "Upper": (0.15, -0.50, 0.78),  # shoulder joint
    "Lower": (0.15, -0.40, 0.48),  # elbow
    "Foot": (0.14, -0.56, 0.13),  # wrist
    "Toe": (0.14, -0.66, 0.035),  # knuckles
    "End": (0.14, -0.75, 0.012),  # finger tips
}
BACK = {
    "Upper": (0.16, 0.36, 0.84),  # hip joint
    "Lower": (0.20, 0.10, 0.54),  # knee (points forward)
    "Foot": (0.18, 0.46, 0.22),  # hock
    "Toe": (0.17, 0.07, 0.032),  # ball of the foot
    "End": (0.17, -0.05, 0.012),  # toe tips
}


def skeleton():
    """[(name, head, parent, proxy_tail)] in RigSpec order. Proxy tails are where the anatomical
    segment ends (used for heat weights and for the clip IK), not the exported bone's tail."""
    J = []

    def add(name, head, parent, tail):
        J.append((name, tuple(float(c) for c in head), parent, tuple(float(c) for c in tail)))

    add("Root", (0, 0, 0), None, (0, 0, 0.3))
    add("Hips", (0, 0.40, 1.00), "Root", (0, 0.20, 1.06))
    add("Spine1", (0, 0.20, 1.06), "Hips", (0, 0.0, 1.07))
    add("Spine2", (0, 0.0, 1.07), "Spine1", (0, -0.22, 1.05))
    add("Spine3", (0, -0.22, 1.05), "Spine2", (0, -0.44, 1.02))
    add("Chest", (0, -0.44, 1.02), "Spine3", (0, -0.62, 1.05))
    add("Neck", (0, -0.62, 1.05), "Chest", (0, -0.80, 1.15))
    add("Head", (0, -0.80, 1.15), "Neck", (0, -1.20, 1.13))
    add("Jaw", (0, -0.90, 1.08), "Head", (0, -1.12, 1.04))
    add("EarL", (0.10, -0.85, 1.36), "Head", (0.12, -0.82, 1.52))
    add("EarR", (-0.10, -0.85, 1.36), "Head", (-0.12, -0.82, 1.52))
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


EYE_L = np.array([0.112, -1.0, 1.265])
EYE_R_RODENT = 0.068
EYE_R = 0.056
NOSE = np.array([0.0, -1.205, 1.125])


def eye_radius(variant):
    return EYE_R_RODENT if variant == "rodent" else EYE_R


def eye_centre(variant, side=1):
    c = EYE_L.copy()
    if variant == "rodent":
        c = c + [0.012, 0.004, 0.004]
    c[0] *= side
    return c


def landmarks(variant):
    """Named points the texture painter and the card scatterer use."""
    return {
        "nose": NOSE,
        "eyeL": eye_centre(variant, 1),
        "eyeR": eye_centre(variant, -1),
        "chin": np.array([0.0, -1.11, 1.03]),
        "earL": np.array([0.11, -0.84, 1.45]),
        "earR": np.array([-0.11, -0.84, 1.45]),
        "tailTip": np.array(TAIL[-1]),
        "tailRoot": np.array(TAIL[0]),
    }


def _limb(a, b, ra, rb, k, tag=""):
    return RoundCone(a, b, ra, rb, k=k, tag=tag)


def sculpt(variant="squirrel"):
    """The SDF primitive list (left/right pairs mirrored)."""
    rodent = variant == "rodent"
    lean = 0.88 if rodent else 1.0  # the rodent is gaunt through the waist and belly
    P = []
    # --- torso: rib cage, belly, pelvis, the dorsal line and the chest -----------------------------
    P.append(Ellipsoid((0, -0.30, 0.92), (0.235, 0.36, 0.27), tag="ribs"))
    P.append(Ellipsoid((0, 0.06, 0.91), (0.225 * lean, 0.30, 0.235 * lean), k=0.10, tag="belly"))
    P.append(Ellipsoid((0, 0.38, 0.96), (0.235, 0.27, 0.255), k=0.10, tag="pelvis"))
    P.append(RoundCone((0, 0.50, 1.04), (0, -0.46, 1.03), 0.15, 0.15, k=0.10, tag="back"))
    P.append(Ellipsoid((0, -0.52, 0.86), (0.17, 0.16, 0.20), k=0.08, tag="brisket"))
    # rump: a soft overhang above the tail root
    P.append(Ellipsoid((0, 0.55, 0.98), (0.18, 0.12, 0.17), k=0.08, tag="rump"))
    # --- neck and head ------------------------------------------------------------------------------
    P.append(RoundCone((0, -0.50, 1.00), (0, -0.82, 1.15), 0.21, 0.145, k=0.08, tag="neck"))
    head_drop = -0.03 if rodent else 0.0
    hz = 1.22 + head_drop
    P.append(Ellipsoid((0, -0.92, hz), (0.155, 0.185, 0.145), k=0.06, tag="skull"))
    P.append(Ellipsoid((0, -0.96, hz + 0.055), (0.115, 0.135, 0.085), k=0.06, tag="brow"))
    P += mirror_pair([Ellipsoid((0.085, -1.01, hz - 0.075), (0.085, 0.095, 0.075), k=0.05, tag="cheek")])
    P.append(Ellipsoid((0, -1.10, hz - 0.085), (0.080, 0.105, 0.072), k=0.05, tag="muzzle"))
    P.append(Ellipsoid((0, -1.185, hz - 0.095), (0.036, 0.030, 0.030), k=0.025, tag="nose"))
    # whisker pads
    P += mirror_pair([Ellipsoid((0.04, -1.13, hz - 0.115), (0.04, 0.05, 0.035), k=0.03, tag="whiskerpad")])
    # lower jaw and chin
    P.append(RoundCone((0, -0.92, hz - 0.13), (0, -1.10, hz - 0.185), 0.07, 0.035, k=0.04, tag="jaw"))
    # mouth slit (a shallow groove from the corners to under the nose); the rodent's grin is wider
    # and pulled up at the corners
    corner = (0.075, -1.03, hz - 0.15) if rodent else (0.055, -1.055, hz - 0.145)
    P += mirror_pair([RoundCone(corner, (0.0, -1.15, hz - 0.142), 0.010 if rodent else 0.007, 0.006, k=0.012, op="sub", tag="mouth")])
    # eye sockets (the eyeballs are separate meshes)
    er = (EYE_R_RODENT if rodent else EYE_R) + 0.004
    ec = eye_centre(variant, 1)
    P += mirror_pair([Ellipsoid(ec, (er, er, er), k=0.018, op="sub", tag="eyesocket")])
    # brow ridge over the eye and a soft lid rim around it
    P += mirror_pair([Ellipsoid(ec + [-0.008, 0.008, 0.045], (0.05, 0.06, 0.022), k=0.02, tag="brow")])
    # ears: thin rounded leaves tilted out and back, cupped on the front
    for side in (1,):
        tilt = rot_y(0.30) @ rot_x(-0.15)  # out to the side, leaning back a little
        base = np.array([0.10, -0.85, 1.36 + head_drop])
        c = base + tilt @ np.array([0, 0, 0.085])
        P += mirror_pair([Ellipsoid(c, (0.052, 0.020, 0.092), axes=tilt, k=0.022, tag="ear")])
        cup = c + tilt @ np.array([0, -0.014, 0.012])
        P += mirror_pair([Ellipsoid(cup, (0.036, 0.012, 0.066), axes=tilt, k=0.006, op="sub", tag="earcup")])
    # --- forelegs ---------------------------------------------------------------------------------------
    sh, el, wr, kn = (np.array(FRONT[k]) for k in ("Upper", "Lower", "Foot", "Toe"))
    P += mirror_pair([
        Ellipsoid(sh + [-0.01, 0.02, 0.12], (0.10, 0.15, 0.18), axes=rot_x(0.35), k=0.06, tag="scapula"),
        _limb(sh, el, 0.105 * lean, 0.062, 0.06, "arm"),
        Ellipsoid((sh + el) / 2 + [0.0, 0.05, 0.0], (0.07, 0.07, 0.12), axes=rot_x(-0.3), k=0.05, tag="triceps"),
        _limb(el, wr, 0.058, 0.032, 0.035, "forearm"),
        _limb(wr, kn, 0.034, 0.028, 0.02, "hand"),
    ])
    # fingers: four slim digits splayed a little
    for dx, dy in ((-0.032, 0.0), (-0.011, 0.012), (0.011, 0.012), (0.032, 0.0)):
        P += mirror_pair([_limb(kn + [dx * 0.5, 0, 0], kn + [dx, -0.085 + dy, -0.022], 0.016, 0.010, 0.012, "finger")])
    # --- hind legs ---------------------------------------------------------------------------------------
    hp, kn2, hk, ba = (np.array(BACK[k]) for k in ("Upper", "Lower", "Foot", "Toe"))
    P += mirror_pair([
        _limb(hp + [0.0, 0.02, 0.02], kn2, 0.205 * lean, 0.10, 0.09, "thigh"),
        Ellipsoid(hp + [0.03, 0.06, -0.10], (0.13, 0.20, 0.20), axes=rot_x(0.5), k=0.08, tag="haunch"),
        _limb(kn2, hk, 0.09, 0.045, 0.05, "shank"),
        Ellipsoid(kn2 + (hk - kn2) * 0.35 + [0.0, 0.03, 0.0], (0.06, 0.07, 0.10), axes=frame_from(hk - kn2), k=0.04, tag="calf"),
        _limb(hk, ba, 0.045, 0.030, 0.025, "foot"),
    ])
    for dx, dy in ((-0.036, 0.004), (-0.017, 0.014), (0.0, 0.018), (0.017, 0.014), (0.036, 0.004)):
        P += mirror_pair([_limb(ba + [dx * 0.5, 0, 0], ba + [dx, -0.11 + dy, -0.02], 0.017, 0.010, 0.012, "toe")])
    # --- tail: a slim core and a broad, slightly flattened plume ---------------------------------------
    plume = [0.45, 0.72, 0.9, 1.0, 1.0, 0.96, 0.84, 0.6]
    if rodent:
        plume = [0.35, 0.5, 0.62, 0.45, 0.7, 0.55, 0.5, 0.38]  # thin and ragged where the fur fell out
    for i in range(8):
        a, b = np.array(TAIL[i]), np.array(TAIL[i + 1])
        P.append(RoundCone(a, b, 0.065 if i == 0 else 0.05, 0.045, k=0.05, tag="tailcore"))
        m = (a + b) / 2
        s = plume[i]
        P.append(Ellipsoid(m, (0.20 * s + 0.03, 0.15, 0.155 * s + 0.03), axes=frame_from(b - a), k=0.09, tag="plume"))
    P.append(Ellipsoid(np.array(TAIL[8]) + [0, -0.04, 0.0], (0.10 * plume[-1] + 0.03, 0.08, 0.08 * plume[-1] + 0.03), k=0.06, tag="plume"))
    if rodent:
        # ribs: four ridges along each flank, with grooves between them
        for i in range(4):
            y = -0.40 + i * 0.085
            a = np.array([0.205, y, 1.02])
            b = np.array([0.23, y + 0.05, 0.80])
            c = np.array([0.17, y + 0.09, 0.66])
            P += mirror_pair([
                RoundCone(a, b, 0.016, 0.017, k=0.022, tag="rib"),
                RoundCone(b, c, 0.017, 0.012, k=0.022, tag="rib"),
            ])
            g = np.array([0.0, 0.043, 0.0])
            P += mirror_pair([RoundCone(a + g + [0.03, 0, 0], b + g + [0.035, 0, 0], 0.014, 0.014, k=0.016, op="sub", tag="ribgroove")])
        # sunken bald patches: left haunch, right shoulder, lower back
        P.append(Ellipsoid((0.27, 0.30, 0.80), (0.07, 0.11, 0.09), k=0.03, op="sub", tag="bald"))
        P.append(Ellipsoid((-0.23, -0.48, 0.98), (0.06, 0.08, 0.07), k=0.03, op="sub", tag="bald"))
        # a notch out of the right ear
        P.append(Ellipsoid((-0.15, -0.86, 1.52), (0.035, 0.05, 0.03), k=0.006, op="sub", tag="earnotch"))
    return P


# The rodent's bald patches and the stitch lines over them (texture painter + sculpt agree).
RODENT_PATCHES = [
    {"c": (0.27, 0.30, 0.80), "r": 0.10, "stitch": ((0.26, 0.20, 0.87), (0.30, 0.40, 0.74))},
    {"c": (-0.23, -0.48, 0.98), "r": 0.085, "stitch": ((-0.20, -0.55, 1.05), (-0.26, -0.41, 0.91))},
    {"c": (0.05, 0.12, 1.30), "r": 0.07, "stitch": ((0.10, 0.04, 1.28), (0.0, 0.20, 1.31))},
]
