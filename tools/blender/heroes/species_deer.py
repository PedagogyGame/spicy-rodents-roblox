"""White-tailed deer (doe; the buck adds an Antlers mesh): skeleton, sculpt, flow, painter, antlers.

Blender coordinates, studs: ground z = 0, faces -Y, left is +X, Root at the origin. A doe stands
4.0 studs at the shoulder with the head top near 5.5 (PuppetSpec: under a person's 6); 5.8 from nose
to rump. Bone names are RigSpec.deer's (Neck1..3, Tail1..2). Short summer coat: no fur cards
(RigSpec.deer has no FurCards region). The buck variant is the same body plus "Antlers" (a separate
MeshPart skinned to Head; RigSpec lists it as optional); the game scales the buck to 1.1 (scaleVariants).
Look: warm tan coat (Body, tinted) with a darker dorsal line; white belly, throat patch, chin and muzzle
band, eye ring and the underside of the tail (Pattern); black nose and hooves, dark ear rims (untinted).
"""
import math

import numpy as np

from sdf import Ellipsoid, RoundCone, frame_from, mirror_pair, rot_x, rot_y, rot_z

SPECIES = "deer"
RIG_ID = "deer"
CLIPS_MODULE = "clips_quadruped"
SCALE = 3.2
VIEW_CENTER = (0.0, 0.0, 3.0)
BAKE_EXTRUSION = 0.09
BUDGET = {"body_tris": 7600, "cards_tris": 0, "antler_tris": 1500}
HIP_HEIGHT = 3.1
TORSO = {"Hips", "Spine1", "Spine2", "Spine3", "Chest", "Neck1", "Neck2", "Neck3"}
NTAIL = 2
EYE_STYLE = "deer"

TAIL = [(0.0, 2.02, 3.66), (0.0, 2.30, 3.42), (0.0, 2.46, 3.10)]
FRONT = {"Upper": (0.36, -1.15, 3.05), "Lower": (0.35, -0.95, 2.42), "Foot": (0.33, -1.10, 1.25),
         "Toe": (0.33, -1.15, 0.40), "End": (0.33, -1.36, 0.02)}
BACK = {"Upper": (0.38, 1.40, 3.22), "Lower": (0.41, 0.92, 2.42), "Foot": (0.37, 1.58, 1.42),
        "Toe": (0.35, 1.42, 0.40), "End": (0.35, 1.22, 0.02)}
NOSE = np.array([0.0, -3.10, 4.66])
EYE_L = np.array([0.205, -2.60, 5.06])
EYE_R = 0.082


def skeleton():
    J = []

    def add(name, head, parent, tail):
        J.append((name, tuple(float(c) for c in head), parent, tuple(float(c) for c in tail)))

    add("Root", (0, 0, 0), None, (0, 0, 0.6))
    add("Hips", (0, 1.55, 3.58), "Root", (0, 0.95, 3.70))
    add("Spine1", (0, 0.95, 3.70), "Hips", (0, 0.30, 3.72))
    add("Spine2", (0, 0.30, 3.72), "Spine1", (0, -0.35, 3.74))
    add("Spine3", (0, -0.35, 3.74), "Spine2", (0, -1.00, 3.72))
    add("Chest", (0, -1.00, 3.72), "Spine3", (0, -1.40, 3.80))
    add("Neck1", (0, -1.40, 3.80), "Chest", (0, -1.78, 4.28))
    add("Neck2", (0, -1.78, 4.28), "Neck1", (0, -2.08, 4.76))
    add("Neck3", (0, -2.08, 4.76), "Neck2", (0, -2.28, 5.12))
    add("Head", (0, -2.28, 5.12), "Neck3", tuple(NOSE))
    add("Jaw", (0, -2.48, 4.86), "Head", (0, -2.98, 4.52))
    add("EarL", (0.22, -2.32, 5.34), "Head", (0.56, -2.24, 5.70))
    add("EarR", (-0.22, -2.32, 5.34), "Head", (-0.56, -2.24, 5.70))
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
    return np.array([side * 0.86, -0.46, 0.2])


def landmarks(variant):
    return {"nose": NOSE, "eyeL": eye_centre(variant, 1), "eyeR": eye_centre(variant, -1),
            "chin": np.array([0, -2.95, 4.52]), "earL": np.array([0.45, -2.27, 5.55]),
            "earR": np.array([-0.45, -2.27, 5.55]), "tailTip": np.array(TAIL[-1]), "tailRoot": np.array(TAIL[0])}


def _limb(a, b, ra, rb, k, tag=""):
    return RoundCone(a, b, ra, rb, k=k, tag=tag)


def sculpt(variant="doe"):
    P = []
    # barrel, withers, rump
    P.append(Ellipsoid((0, -0.45, 3.20), (0.70, 1.1, 0.78), tag="ribs"))
    P.append(Ellipsoid((0, 0.45, 3.16), (0.62, 0.95, 0.68), k=0.25, tag="belly"))
    P.append(Ellipsoid((0, 1.38, 3.42), (0.58, 0.62, 0.6), k=0.22, tag="rump"))
    P.append(RoundCone((0, 1.72, 3.62), (0, -1.05, 3.62), 0.42, 0.46, k=0.25, tag="back"))
    P.append(Ellipsoid((0, -1.0, 3.78), (0.26, 0.45, 0.30), k=0.2, tag="withers"))
    P.append(Ellipsoid((0, -1.32, 2.98), (0.44, 0.40, 0.55), k=0.22, tag="brisket"))
    # neck: thick at the shoulders, slim under the head
    P.append(RoundCone((0, -1.22, 3.42), (0, -2.15, 4.78), 0.56, 0.31, k=0.22, tag="neck"))
    P.append(Ellipsoid((0, -1.95, 4.15), (0.26, 0.30, 0.42), axes=rot_x(-0.6), k=0.2, tag="throat"))
    # head: a slim tapered skull and long face
    P.append(Ellipsoid((0, -2.38, 5.05), (0.30, 0.36, 0.28), k=0.12, tag="skull"))
    P.append(RoundCone((0, -2.55, 4.98), (0, -3.0, 4.70), 0.25, 0.14, k=0.12, tag="face"))
    P.append(Ellipsoid((0, -3.04, 4.68), (0.14, 0.13, 0.12), k=0.08, tag="muzzle"))
    P.append(RoundCone((0, -2.46, 4.80), (0, -2.94, 4.55), 0.15, 0.085, k=0.1, tag="jaw"))
    P += mirror_pair([RoundCone((0.11, -2.90, 4.56), (0.0, -3.08, 4.58), 0.014, 0.01, k=0.02, op="sub", tag="mouth")])
    P += mirror_pair([Ellipsoid(EYE_L, (EYE_R + 0.006,) * 3, k=0.04, op="sub", tag="eyesocket")])
    P += mirror_pair([Ellipsoid(EYE_L + [-0.03, 0.02, 0.09], (0.10, 0.14, 0.05), k=0.05, tag="brow")])
    # ears: big, oval, held out to the sides and up
    tilt = rot_y(0.95) @ rot_x(-0.15)
    base = np.array([0.22, -2.32, 5.34])
    c = base + tilt @ np.array([0, 0, 0.30])
    P += mirror_pair([Ellipsoid(c, (0.18, 0.05, 0.34), axes=tilt, k=0.06, tag="ear")])
    P += mirror_pair([Ellipsoid(c + tilt @ np.array([0, -0.04, 0.03]), (0.13, 0.026, 0.27), axes=tilt, k=0.01, op="sub", tag="earcup")])
    # legs
    sh, el, kn, fe = (np.array(FRONT[k]) for k in ("Upper", "Lower", "Foot", "Toe"))
    end = np.array(FRONT["End"])
    P += mirror_pair([
        Ellipsoid(sh + [-0.06, 0.02, 0.32], (0.2, 0.4, 0.5), axes=rot_x(0.3), k=0.2, tag="scapula"),
        _limb(sh, el, 0.34, 0.22, 0.2, "arm"),
        _limb(el, kn, 0.19, 0.11, 0.12, "forearm"),
        _limb(kn, fe, 0.10, 0.075, 0.05, "cannon"),
        _limb(fe, end + [0, 0.08, 0.1], 0.08, 0.07, 0.04, "pastern"),
    ])
    hp, st, hk, fe2 = (np.array(BACK[k]) for k in ("Upper", "Lower", "Foot", "Toe"))
    end2 = np.array(BACK["End"])
    P += mirror_pair([
        _limb(hp + [0, 0.05, 0.05], st, 0.48, 0.26, 0.25, "thigh"),
        Ellipsoid(hp + [0.04, 0.12, -0.35], (0.3, 0.55, 0.6), axes=rot_x(0.35), k=0.22, tag="ham"),
        _limb(st, hk, 0.22, 0.10, 0.12, "gaskin"),
        Ellipsoid(st + (hk - st) * 0.3 + [0, 0.06, 0.04], (0.15, 0.17, 0.32), axes=frame_from(hk - st), k=0.12, tag="calf"),
        _limb(hk, fe2, 0.10, 0.075, 0.05, "cannon"),
        _limb(fe2, end2 + [0, 0.08, 0.1], 0.08, 0.07, 0.04, "pastern"),
    ])
    # tail: short, broad, flat
    a, b, t = (np.array(p) for p in TAIL)
    P.append(Ellipsoid((a + b) / 2, (0.20, 0.18, 0.12), axes=frame_from(b - a), k=0.12, tag="tail"))
    P.append(Ellipsoid((b + t) / 2, (0.17, 0.17, 0.09), axes=frame_from(t - b), k=0.1, tag="tail"))
    return P


def hard_parts(variant="doe"):
    """Cloven hooves: two dark wedges per foot, skinned to the Toe bone."""
    from geometry import curved_spike

    out = []
    for leg, spec in (("Front", FRONT), ("Back", BACK)):
        end = np.array(spec["End"])
        for side, sx in (("L", 1), ("R", -1)):
            for i, dx in enumerate((-0.045, 0.045)):
                base = (end + [dx, 0.12, 0.14]) * [sx, 1, 1]
                v, f = curved_spike(base, (0, -0.55, -1), 0.17, 0.075, curl=(0, -1, 0), curl_amt=0.25, sides=6, flat=0.7)
                out.append((f"hoof_{leg[0]}{side}{i}", v, f, f"{leg}{side}_Toe", "claw"))
    return out


def _sstep(a, b, x):
    t = np.clip((np.asarray(x, float) - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


def pattern_field(c, n, dom, variant="doe"):
    c, n = np.asarray(c), np.asarray(n)
    ds = np.asarray(dom).astype(str)
    x, y, z = c[:, 0], c[:, 1], c[:, 2]
    wob = 0.05 * np.sin(y * 5.0 + x * 3.0) + 0.04 * np.sin(z * 7.0)
    out = np.zeros(len(c))
    # white belly running back between the hind legs
    legs = np.char.startswith(ds, "Front") | np.char.startswith(ds, "Back")
    trunk = (y > -1.3) & (y < 1.7) & (z > 2.3) & ~np.char.startswith(ds, "Tail") & ~legs
    belly = _sstep(0.2, 0.5, -n[:, 2] * 0.9 + (2.75 - z) * 1.5 - np.abs(x) * 0.6 + wob)
    out[trunk] = belly[trunk]
    # throat patch
    throat = np.isin(ds, ["Neck2", "Neck3"]) | ((ds == "Head") & (z < 4.85))
    tp = _sstep(0.2, 0.45, -n[:, 1] * 0.5 - n[:, 2] * 0.8 + wob) * (np.abs(y + 2.25) < 0.22)
    out[throat] = np.maximum(out[throat], tp[throat])
    # chin and the white band behind the black nose
    head = np.isin(ds, ["Head", "Jaw"])
    chin = _sstep(0.25, 0.5, -n[:, 2] + wob) * (y < -2.6)
    band = _sstep(0.06, 0.02, np.abs(y + 2.92)) * (np.abs(x) > 0.05)
    out[head] = np.maximum(chin, band)[head]
    # under the tail (the white flag)
    tail = np.char.startswith(ds, "Tail")
    out[tail] = _sstep(-0.1, 0.3, n[tail, 1] * 0.5 - n[tail, 2] * 0.8 + wob[tail])
    return out


TINTS = {"doe": {"Body": "#c99a68", "Pattern": "#fffaf2"}, "buck": {"Body": "#b98a5c", "Pattern": "#fffaf2"}}


def flow_dir(name, head, tail, co, n, variant):
    seg = np.asarray(tail, float) - np.asarray(head, float)
    seg = seg / max(np.linalg.norm(seg), 1e-9)
    lat = np.abs(n[:, 0:1])
    if name in TORSO or name in ("Head", "Jaw"):
        d = np.tile(-seg, (len(co), 1))
        if name.startswith("Neck"):
            d = np.tile(np.array([0, 0.3, -1.0]), (len(co), 1)) * 0.5 - seg * 0.5  # down the neck
        else:
            d[:, 1] = np.maximum(d[:, 1], 0.6)
        return d + np.array([0, 0, -0.9]) * lat
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
    ear = np.char.startswith(dom, "Ear")
    head = np.isin(dom, ["Head", "Jaw"])
    layers = [(0.012, 0.06, 1.0, 0.0018, 71), (0.03, 0.12, 0.5, 0.0025, 72)]
    H, gT, gB = tools["fur_relief"](P, F, N, T, B, layers)
    fine = tools["strands"](P, F, 0.012, 0.06, seed=71)
    big = fbm(P * 2.0, 3, seed=7)
    dorsal = sst(0.4, 0.95, N[:, 2])
    g = 0.86 - 0.22 * dorsal * sst(1.5, 3.0, P[:, 2]) + (fine - 0.5) * 0.18 + (big - 0.5) * 0.14
    g = g - 0.12 * sst(0.75, 0.95, N[:, 2]) * sst(3.0, 3.8, P[:, 2])  # the darker dorsal stripe
    g = g * (0.92 + 0.12 * H)
    lowleg = np.char.endswith(dom, "_Foot") | np.char.endswith(dom, "_Toe")
    g = np.where(lowleg, g * 0.9, g)
    gp = 0.96 + (fine - 0.5) * 0.06
    tints = TINTS.get(variant, TINTS["doe"])
    tb, tp = _hex(tints["Body"]), _hex(tints["Pattern"])
    pat = pattern_field(P, N, tx["dom"], variant) + (fine - 0.5) * 0.25
    m = sst(0.38, 0.62, pat)
    grey, alpha, nat = tools["region_colours"](region, m, g, gp, tb, tp)
    rough = 0.66 - 0.08 * (H - 0.5) + (big - 0.5) * 0.06
    natv = nat.copy()

    def override(mask, col, r=None, k=None):
        w = (np.ones(n) if k is None else np.asarray(k, float)) * mask
        mm = w > 0
        col = np.asarray(col, np.float32)
        natv[mm] = natv[mm] * (1 - w[mm, None]) + (col[mm] if col.ndim == 2 else col) * w[mm, None]
        alpha[mm] = alpha[mm] * (1 - w[mm])
        if r is not None:
            rough[mm] = rough[mm] * (1 - w[mm]) + r * w[mm]

    lm = landmarks(variant)
    d_nose = np.linalg.norm(P - lm["nose"], axis=1)
    override(head, _hex("#16110f"), r=0.25, k=1 - sst(0.10, 0.14, d_nose))  # wet black nose
    d_eye = np.minimum(np.linalg.norm(P - lm["eyeL"], axis=1), np.linalg.norm(P - lm["eyeR"], axis=1))
    override(head, _hex("#1b1411"), r=0.4, k=1 - sst(EYE_R + 0.006, EYE_R + 0.02, d_eye))
    ring = sst(EYE_R + 0.02, EYE_R + 0.035, d_eye) * (1 - sst(EYE_R + 0.05, EYE_R + 0.08, d_eye))
    override(head, _hex("#e9dccb"), r=0.65, k=ring * 0.55)  # pale eye ring
    # ears: dark rims, pale furred insides
    ec = np.where(P[:, :1] > 0, lm["earL"], lm["earR"])
    dist_e = np.linalg.norm(P - ec, axis=1)
    override(ear, _hex("#3a2a20"), r=0.6, k=sst(0.26, 0.33, dist_e))
    override(ear, _hex("#e9dfd2") * (0.85 + 0.3 * fine)[:, None], r=0.6, k=sst(-0.2, -0.5, N[:, 1]) * (1 - sst(0.18, 0.26, dist_e)))
    # a darker band on the muzzle above the white
    override(head, _hex("#5a4232"), r=0.6, k=sst(0.1, 0.03, np.abs(P[:, 1] + 2.80)) * (P[:, 2] > 4.7) * 0.7)
    override(hard == 1, _hex("#1a1513") * (0.8 + 0.4 * vn(P * 30.0, 4))[:, None], r=0.35)
    rgb = tools["finish_rgb"](grey, alpha, natv, region, tb, tp)
    return {"rgb": rgb, "alpha": np.clip(alpha, 0, 1).astype(np.float32), "rough": np.clip(rough, 0.05, 1).astype(np.float32),
            "height": H, "slope_T": gT.astype(np.float32), "slope_B": gB.astype(np.float32),
            "tint_by_region": [tb, tp], "tints_hex": tints, "ao_strength": 0.6}


def card_density(c, n, dom, variant):
    return np.zeros(len(c))


def card_shape(P, N, F, dom, variant, rng):
    return {}


def antlers():
    """A white-tailed buck's rack: each main beam sweeps back, out and then forward, with three
    upright tines and a brow tine. Returns (verts, faces) in head space (Blender coords)."""
    from geometry import curved_spike

    parts = []
    for sx in (1, -1):
        base = np.array([0.16 * sx, -2.36, 5.36])
        # main beam: three curved segments
        p, d = base, np.array([0.55 * sx, 0.35, 1.0])
        beam_pts = []
        for seg, (curl, ln, r) in enumerate((((0.3 * sx, -0.4, -0.2), 0.42, 0.07), ((-0.2 * sx, -1.0, -0.3), 0.40, 0.058), ((-0.5 * sx, -0.8, 0.2), 0.36, 0.045))):
            v, f = curved_spike(p, d, ln, r, curl=curl, curl_amt=0.55, sides=7, segs=3)
            parts.append((v, f))
            # end of this segment
            dd = d / np.linalg.norm(d)
            c = np.asarray(curl, float)
            for _ in range(3):
                dd = dd + c * 0.55 / 3
                dd /= np.linalg.norm(dd)
            p = p + (v[-1] - p) * 0.9
            d = dd
            beam_pts.append(p.copy())
        # tines rising from the beam
        for tp_, ln in zip(beam_pts, (0.36, 0.32, 0.22)):
            v, f = curved_spike(tp_ + [0, 0, -0.02], (0.08 * sx, -0.15, 1.0), ln, 0.035, curl=(0, -0.5, 0), curl_amt=0.3, sides=5, segs=2)
            parts.append((v, f))
        v, f = curved_spike(base + [0.05 * sx, -0.05, 0.12], (0.1 * sx, -0.6, 0.8), 0.16, 0.03, curl=(0, 0, 1), curl_amt=0.3, sides=5, segs=2)
        parts.append((v, f))
        # burr (the rough ring at the base)
        v, f = curved_spike(base - [0, 0, 0.03], (0.55 * sx, 0.35, 1.0), 0.05, 0.085, curl=(0, 0, 0), curl_amt=0, sides=8, segs=1)
        parts.append((v, f))
    return parts


SOCKETS = {
    "HeadSocket": ("Head", (0.0, -2.36, 5.36)),
    "MouthSocket": ("Jaw", (0.0, -2.95, 4.55)),
    "TailTip": ("Tail2", TAIL[-1]),
    "ChestCenter": ("Chest", (0.0, -0.80, 3.20)),
}
