"""Red fox anatomy: skeleton joints, signed-distance sculpt, fur flow, painter, cards.

Blender coordinates, studs: ground z = 0, faces -Y, left is +X, Root at the origin. About 2.0 studs at
the shoulder and 2.8 to the ear tips (PuppetSpec FOX_SCALE: a third of a person's height), 3.2 from
nose to rump and a 2.1-stud brush. Bone names are RigSpec.fox's (Tail1..6).
Look: rufous coat (Body, tinted), white chin, throat, chest and tail tip (Pattern), black stockings,
ear backs and nose (untinted, so the avatar blend keeps the fox's markings), amber slit-pupil eyes.
"""
import math

import numpy as np

from sdf import Ellipsoid, RoundCone, frame_from, mirror_pair, rot_x, rot_y, rot_z

SPECIES = "fox"
RIG_ID = "fox"
CLIPS_MODULE = "clips_quadruped"
SCALE = 1.6
VIEW_CENTER = (0.0, 0.7, 1.45)
BAKE_EXTRUSION = 0.05
BUDGET = {"body_tris": 5200, "cards_tris": 1600}  # RigSpec fox 8,000 incl. claws and eyes
HIP_HEIGHT = 1.58
TORSO = {"Hips", "Spine1", "Spine2", "Spine3", "Chest", "Neck"}
NTAIL = 6

TAIL = [(0.0, 1.12, 1.66), (0.0, 1.46, 1.55), (0.0, 1.80, 1.42), (0.0, 2.14, 1.30), (0.0, 2.48, 1.22),
        (0.0, 2.82, 1.18), (0.0, 3.16, 1.18)]
FRONT = {"Upper": (0.23, -0.78, 1.45), "Lower": (0.23, -0.62, 1.02), "Foot": (0.20, -0.74, 0.30),
         "Toe": (0.20, -0.86, 0.065), "End": (0.20, -0.99, 0.02)}
BACK = {"Upper": (0.24, 0.80, 1.50), "Lower": (0.27, 0.42, 1.00), "Foot": (0.25, 0.90, 0.42),
        "Toe": (0.24, 0.73, 0.065), "End": (0.24, 0.60, 0.02)}
HEAD_C = np.array([0.0, -1.52, 2.20])
NOSE = np.array([0.0, -2.10, 2.06])
EYE_L = np.array([0.118, -1.665, 2.265])
EYE_R = 0.05


def skeleton():
    J = []

    def add(name, head, parent, tail):
        J.append((name, tuple(float(c) for c in head), parent, tuple(float(c) for c in tail)))

    add("Root", (0, 0, 0), None, (0, 0, 0.4))
    add("Hips", (0, 0.85, 1.74), "Root", (0, 0.45, 1.80))
    add("Spine1", (0, 0.45, 1.80), "Hips", (0, 0.05, 1.82))
    add("Spine2", (0, 0.05, 1.82), "Spine1", (0, -0.35, 1.80))
    add("Spine3", (0, -0.35, 1.80), "Spine2", (0, -0.75, 1.76))
    add("Chest", (0, -0.75, 1.76), "Spine3", (0, -1.05, 1.84))
    add("Neck", (0, -1.05, 1.84), "Chest", (0, -1.38, 2.14))
    add("Head", (0, -1.38, 2.14), "Neck", tuple(NOSE))
    add("Jaw", (0, -1.50, 2.04), "Head", (0, -1.98, 1.97))
    add("EarL", (0.16, -1.42, 2.38), "Head", (0.24, -1.38, 2.74))
    add("EarR", (-0.16, -1.42, 2.38), "Head", (-0.24, -1.38, 2.74))
    for i in range(NTAIL):
        add(f"Tail{i + 1}", TAIL[i], "Hips" if i == 0 else f"Tail{i}", TAIL[i + 1])
    for leg, spec, parent in (("Front", FRONT, "Chest"), ("Back", BACK, "Hips")):
        for side, sx in (("L", 1), ("R", -1)):
            segs = ["Upper", "Lower", "Foot", "Toe"]
            for i, seg in enumerate(segs):
                h = np.array(spec[seg]) * [sx, 1, 1]
                t = np.array(spec[segs[i + 1]] if i < 3 else spec["End"]) * [sx, 1, 1]
                add(f"{leg}{side}_{seg}", h, parent if i == 0 else f"{leg}{side}_{segs[i - 1]}", t)
    return J


def eye_radius(variant):
    return EYE_R


def eye_centre(variant, side=1):
    c = EYE_L.copy()
    c[0] *= side
    return c


def eye_gaze(side):
    return np.array([side * 0.5, -0.85, 0.12])


def landmarks(variant):
    return {"nose": NOSE, "eyeL": eye_centre(variant, 1), "eyeR": eye_centre(variant, -1),
            "chin": np.array([0, -1.95, 1.97]), "tailTip": np.array(TAIL[-1]), "tailRoot": np.array(TAIL[0])}


def _limb(a, b, ra, rb, k, tag=""):
    return RoundCone(a, b, ra, rb, k=k, tag=tag)


def sculpt(variant="fox"):
    P = []
    # torso: a deep chest, a slim waist, a compact rump
    P.append(Ellipsoid((0, -0.55, 1.52), (0.34, 0.55, 0.40), tag="ribs"))
    P.append(Ellipsoid((0, 0.15, 1.55), (0.29, 0.50, 0.30), k=0.15, tag="belly"))
    P.append(Ellipsoid((0, 0.78, 1.58), (0.32, 0.38, 0.34), k=0.14, tag="pelvis"))
    P.append(RoundCone((0, 0.95, 1.72), (0, -0.80, 1.74), 0.21, 0.24, k=0.15, tag="back"))
    P.append(Ellipsoid((0, -0.88, 1.36), (0.24, 0.24, 0.30), k=0.12, tag="brisket"))
    # neck with its ruff, and the head
    P.append(RoundCone((0, -0.80, 1.68), (0, -1.40, 2.10), 0.30, 0.20, k=0.12, tag="neck"))
    P.append(Ellipsoid((0, -1.18, 1.72), (0.22, 0.20, 0.28), k=0.12, tag="ruff"))
    P.append(Ellipsoid(HEAD_C, (0.23, 0.26, 0.205), k=0.08, tag="skull"))
    P += mirror_pair([Ellipsoid((0.15, -1.58, 2.10), (0.12, 0.15, 0.12), k=0.08, tag="cheekruff")])
    P.append(RoundCone((0, -1.66, 2.15), (0, -2.02, 2.07), 0.135, 0.055, k=0.08, tag="snout"))
    P.append(Ellipsoid((0, -2.075, 2.07), (0.05, 0.045, 0.042), k=0.03, tag="nose"))
    P.append(RoundCone((0, -1.55, 2.01), (0, -1.96, 1.98), 0.09, 0.035, k=0.06, tag="jaw"))
    P += mirror_pair([RoundCone((0.07, -1.80, 2.0), (0.0, -2.0, 2.0), 0.009, 0.007, k=0.012, op="sub", tag="mouth")])
    P += mirror_pair([Ellipsoid(EYE_L, (EYE_R + 0.004,) * 3, k=0.025, op="sub", tag="eyesocket")])
    P += mirror_pair([Ellipsoid(EYE_L + [-0.025, 0.02, 0.055], (0.06, 0.08, 0.026), k=0.03, tag="brow")])
    # ears: big pointed triangles leaning out
    tilt = rot_y(0.22) @ rot_x(-0.10)
    base = np.array([0.155, -1.42, 2.36])
    for h, w, d, z in ((0.13, 0.12, 0.035, 0.10), (0.10, 0.08, 0.03, 0.20), (0.07, 0.04, 0.025, 0.29)):
        P += mirror_pair([Ellipsoid(base + tilt @ np.array([0, 0, z]), (w, d, h), axes=tilt, k=0.04, tag="ear")])
    P += mirror_pair([Ellipsoid(base + tilt @ np.array([0, -0.03, 0.16]), (0.08, 0.02, 0.15), axes=tilt, k=0.008, op="sub", tag="earcup")])
    # forelegs: slim, a strong shoulder
    sh, el, wr, kn = (np.array(FRONT[k]) for k in ("Upper", "Lower", "Foot", "Toe"))
    P += mirror_pair([
        Ellipsoid(sh + [-0.03, 0.02, 0.18], (0.14, 0.24, 0.28), axes=rot_x(0.3), k=0.1, tag="scapula"),
        _limb(sh, el, 0.15, 0.09, 0.1, "arm"),
        _limb(el, wr, 0.085, 0.048, 0.06, "forearm"),
        _limb(wr, kn, 0.05, 0.05, 0.03, "pastern"),
        Ellipsoid(kn + [0, -0.05, -0.02], (0.065, 0.09, 0.04), k=0.03, tag="paw"),
    ])
    hp, kn2, hk, ba = (np.array(BACK[k]) for k in ("Upper", "Lower", "Foot", "Toe"))
    P += mirror_pair([
        _limb(hp + [0, 0.02, 0.04], kn2, 0.25, 0.13, 0.14, "thigh"),
        Ellipsoid(hp + [0.02, 0.0, -0.18], (0.17, 0.30, 0.30), axes=rot_x(0.45), k=0.12, tag="haunch"),
        _limb(kn2, hk, 0.12, 0.055, 0.07, "shank"),
        Ellipsoid(kn2 + (hk - kn2) * 0.3 + [0, 0.04, 0.02], (0.09, 0.11, 0.18), axes=frame_from(hk - kn2), k=0.07, tag="calf"),
        _limb(hk, ba, 0.055, 0.05, 0.03, "metatarsus"),
        Ellipsoid(ba + [0, -0.05, -0.02], (0.065, 0.09, 0.04), k=0.03, tag="paw"),
    ])
    # the brush: thick, round, tapering at both ends
    plume = [0.45, 0.8, 1.0, 1.0, 0.9, 0.65, 0.35]
    for i in range(NTAIL):
        a, b = np.array(TAIL[i]), np.array(TAIL[i + 1])
        P.append(RoundCone(a, b, 0.09, 0.07, k=0.06, tag="tailcore"))
        for f in (0.25, 0.75):
            m = a + (b - a) * f
            s = plume[i] * (1 - f) + plume[i + 1] * f
            P.append(Ellipsoid(m, (0.22 * s + 0.05, 0.22, 0.2 * s + 0.05), axes=frame_from(b - a), k=0.12, tag="plume"))
    return P


def hard_parts(variant="fox"):
    from geometry import curved_spike

    out = []
    for leg, spec in (("Front", FRONT), ("Back", BACK)):
        toe = np.array(spec["Toe"])
        for side, sx in (("L", 1), ("R", -1)):
            for i, dx in enumerate((-0.045, -0.015, 0.015, 0.045)):
                tip = (toe + [dx, -0.13, -0.035]) * [sx, 1, 1]
                v, f = curved_spike(tip + [0, 0.01, 0.01], (0, -1, -0.5), 0.045, 0.012, curl=(0, 0.2, -1), curl_amt=0.6)
                out.append((f"claw_{leg[0]}{side}{i}", v, f, f"{leg}{side}_Toe", "claw"))
    return out


def _sstep(a, b, x):
    t = np.clip((np.asarray(x, float) - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def pattern_field(c, n, dom, variant="fox"):
    c, n = np.asarray(c), np.asarray(n)
    dom = np.asarray(dom).astype(str)
    x, y, z = c[:, 0], c[:, 1], c[:, 2]
    wob = 0.04 * np.sin(y * 9.0 + x * 5.0) + 0.03 * np.sin(z * 13.0)
    out = np.zeros(len(c))
    torso = np.isin(dom, list(TORSO))
    # white throat and chest, a narrow pale belly
    chest = _sstep(-0.1, 0.35, -n[:, 2] * 0.6 - n[:, 1] * 0.7 + (1.55 - z) * 0.8 + wob) * (y < -0.6)
    belly = _sstep(0.4, 0.75, -n[:, 2] + wob) * (y >= -0.6)
    out[torso] = np.maximum(chest, belly)[torso]
    head = dom == "Head"
    muzzle = _sstep(0.0, 0.3, -n[:, 2] * 0.8 + (2.08 - z) * 3 + wob) * (y < -1.6)
    out[head] = muzzle[head]
    out[dom == "Jaw"] = 1.0
    tail = np.char.startswith(dom, "Tail")
    out[tail] = _sstep(2.86, 2.98, y[tail] + wob[tail])
    return out


TINTS = {"fox": {"Body": "#d8763a", "Pattern": "#fbf6ee", "FurCards": "#d8763a"}}


def flow_dir(name, head, tail, co, n, variant):
    seg = np.asarray(tail, float) - np.asarray(head, float)
    seg = seg / max(np.linalg.norm(seg), 1e-9)
    lat = np.abs(n[:, 0:1])
    if name in TORSO or name in ("Head", "Jaw"):
        d = np.tile(-seg, (len(co), 1))
        d[:, 1] = np.maximum(d[:, 1], 0.6)
        return d + np.array([0, 0, -0.9]) * lat
    if name.startswith("Ear"):
        return np.tile(seg, (len(co), 1))
    if name.startswith("Tail"):
        rel = co - head
        along = rel @ seg
        perp = rel - along[:, None] * seg
        pn = perp / np.maximum(np.linalg.norm(perp, axis=1, keepdims=True), 1e-9)
        return seg + 0.7 * pn
    return np.tile(seg, (len(co), 1))


def _hex(h):
    h = h.lstrip("#")
    return np.array([int(h[i : i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=np.float32)


def paint(tx, variant, tools):
    sst, vn, fbm = tools["sstep"], tools["vnoise"], tools["fbm"]
    P, N, F, T, B = tx["P"], tx["N"], tx["F"], tx["T"], tx["B"]
    n = len(P)
    dom = tx["dom"].astype(str)
    region, hard = tx["region"], tx["hard"]
    tail = np.char.startswith(dom, "Tail")
    ear = np.char.startswith(dom, "Ear")
    lower_leg = np.char.endswith(dom, "_Lower") | np.char.endswith(dom, "_Foot") | np.char.endswith(dom, "_Toe")
    head = np.isin(dom, ["Head", "Jaw"])
    lscale = np.where(tail, 2.0, np.where(head | lower_leg, 0.6, 1.0)).astype(np.float32)
    layers = [(0.007, 0.07, 1.0, 0.0018, 61), (0.018, 0.14, 0.7, 0.0028, 62), (0.045, 0.25, 0.45, 0.0035, 63)]
    H, gT, gB = tools["fur_relief"](P, F, N, T, B, layers, lscale=lscale)
    fine = tools["strands"](P, F * lscale[:, None], 0.007, 0.07, seed=61)
    big = fbm(P * 5.0, 3, seed=6)
    dorsal = sst(0.2, 0.9, N[:, 2])
    g = 0.82 - 0.10 * dorsal + (fine - 0.5) * (0.2 + 0.2 * dorsal)
    g = g * (0.88 + 0.22 * H) + (big - 0.5) * 0.1
    # a darker saddle and grizzled dark-tipped tail
    g = np.where(tail, 0.78 + (fine - 0.5) * 0.35 - 0.12 * sst(0.3, 0.8, N[:, 2]), g)
    gp = 0.95 + (fine - 0.5) * 0.1
    tints = TINTS["fox"]
    tb, tp = _hex(tints["Body"]), _hex(tints["Pattern"])
    pat = pattern_field(P, N, tx["dom"], variant)
    alpha = np.ones(n, dtype=np.float32)
    nat_body = np.clip(g, 0, 1)[:, None] * tb
    nat_pat = np.clip(gp, 0, 1)[:, None] * tp
    nat = np.where((region == 1)[:, None], nat_pat, nat_body)
    near = 1 - sst(0.0, 0.16, np.abs(pat - 0.5))
    blend = sst(0.3, 0.7, pat)[:, None]
    nat = np.where((near > 0)[:, None], nat_body * (1 - blend) + nat_pat * blend, nat)
    alpha = np.minimum(alpha, 1 - near)
    grey = np.where(region == 1, gp, g)
    rough = 0.62 - 0.12 * (H - 0.5) + (big - 0.5) * 0.06
    natv = nat.copy()

    def override(mask, col, r=None, k=None):
        w = (np.ones(n) if k is None else np.asarray(k, float)) * mask
        m = w > 0
        col = np.asarray(col, np.float32)
        natv[m] = natv[m] * (1 - w[m, None]) + (col[m] if col.ndim == 2 else col) * w[m, None]
        alpha[m] = alpha[m] * (1 - w[m])
        if r is not None:
            rough[m] = rough[m] * (1 - w[m]) + r * w[m]

    black = _hex("#231a16") * (0.8 + 0.4 * fine)[:, None]
    # black stockings: up the lower legs, ragged top edge
    stock = sst(0.0, 0.12, (np.where(np.char.startswith(dom, "Front"), 0.95, 0.75) + 0.08 * (big - 0.5)) - P[:, 2])
    override(lower_leg | np.char.endswith(dom, "_Upper"), black, r=0.6, k=stock)
    # black ear backs, pale inside
    override(ear, black, r=0.6, k=sst(-0.1, 0.25, N[:, 1]))
    override(ear, _hex("#cdb9a3") * (0.8 + 0.4 * fine)[:, None], r=0.65, k=sst(-0.2, -0.55, N[:, 1]) * 0.85)
    # nose and lips
    lm = landmarks(variant)
    d_nose = np.linalg.norm(P - lm["nose"], axis=1)
    override(head, _hex("#1a1412"), r=0.3, k=1 - sst(0.04, 0.055, d_nose))
    d_eye = np.minimum(np.linalg.norm(P - lm["eyeL"], axis=1), np.linalg.norm(P - lm["eyeR"], axis=1))
    override(head, _hex("#1e1512"), r=0.4, k=1 - sst(EYE_R + 0.004, EYE_R + 0.014, d_eye))
    # the dark tear line from the eye toward the muzzle
    tear = np.minimum(*[np.abs(np.cross(P - lm[k], np.array([0, -0.85, -0.5]))).sum(1) for k in ("eyeL", "eyeR")])
    override(head, _hex("#3a2218"), r=0.5, k=(1 - sst(0.012, 0.03, tear)) * (P[:, 1] < -1.72) * (P[:, 1] > -1.95) * 0.7)
    override(hard == 1, _hex("#1c1714"), r=0.3)
    tint_reg = np.where((region == 1)[:, None], tp, tb)
    denom = 1 - alpha[:, None] + alpha[:, None] * tint_reg
    rgb = np.where(alpha[:, None] > 0.999, np.clip(grey, 0, 1)[:, None].repeat(3, 1), natv / np.maximum(denom, 1e-3))
    return {"rgb": np.clip(rgb, 0, 1).astype(np.float32), "alpha": np.clip(alpha, 0, 1).astype(np.float32),
            "rough": np.clip(rough, 0.05, 1).astype(np.float32), "height": H, "slope_T": gT.astype(np.float32),
            "slope_B": gB.astype(np.float32), "tint_by_region": [tb, tp], "tints_hex": tints, "ao_strength": 0.65}


def card_density(c, n, dom, variant):
    dom = np.asarray(dom).astype(str)
    d = np.zeros(len(c))
    tail = np.char.startswith(dom, "Tail")
    d[tail] = 2.0
    d[np.isin(dom, ["Neck", "Chest"])] = 1.2  # the ruff
    d[np.isin(dom, ["Hips", "Spine1", "Spine2", "Spine3"])] = 0.25
    head = dom == "Head"
    d[head] = 0.8 * np.clip(np.abs(n[head, 0]) * 1.4, 0, 1) * (c[head, 1] > -1.7)
    d[np.isin(dom, ["BackL_Upper", "BackR_Upper"])] = 0.4
    return d


def card_shape(P, N, F, dom, variant, rng):
    dom = np.asarray(dom).astype(str)
    k = len(P)
    tail = np.char.startswith(dom, "Tail")
    L = np.where(tail, rng.uniform(0.22, 0.36, k), rng.uniform(0.11, 0.17, k))
    W = np.where(tail, rng.uniform(0.11, 0.17, k), rng.uniform(0.06, 0.09, k))
    lift = np.where(tail, rng.uniform(0.3, 0.7, k), rng.uniform(0.2, 0.4, k))
    roll = np.where(tail, rng.uniform(-1.3, 1.3, k), rng.uniform(-0.6, 0.6, k))
    return {"length": L, "width": W, "lift": lift, "roll": roll, "droop": np.full(k, 0.25)}


SOCKETS = {
    "HeadSocket": ("Head", (0.0, -1.50, 2.42)),
    "MouthSocket": ("Jaw", (0.0, -1.95, 2.00)),
    "TailTip": ("Tail6", TAIL[-1]),
    "ChestCenter": ("Chest", (0.0, -0.70, 1.50)),
}
