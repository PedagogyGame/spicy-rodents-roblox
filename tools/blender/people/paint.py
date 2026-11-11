"""What is painted on the townspeople (numpy; the noise comes from the heroes' textures.py).

Every runtime-tinted region (skin, shirt, trousers, shoes, hair, cap) gets a colour map for
SurfaceAppearance AlphaMode Overlay: alpha 0 lets the MeshPart's Color through, so the map only holds
  * shade: soft darker and lighter variation of whatever the base colour is (dark or white texels at a
    low alpha), ambient occlusion from the sculpt, seams and stitching;
  * ink: opaque detail in its own colours (buttons, belt, badge, soles, eyes, mouth, stripes).
A painter fills a Canvas for the texels of one part, given their rest-pose positions P and normals N in
the Blender frame of spec.py (x = the person's left, -y = front, z up). Canvas.h is a height in studs;
the builder turns its slope into the normal map, so a painter is called again on shifted positions.
"""
import math

import numpy as np

import textures as tx  # tools/blender/heroes/textures.py
from spec import J

F32 = np.float32
sstep = tx.sstep


def rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i:i + 2], 16) / 255.0 for i in (0, 2, 4)], dtype=F32)


class Canvas:
    def __init__(self, n, rough=0.82):
        self.n = n
        self.shade = np.ones(n, dtype=F32)  # multiplies the base colour only
        self.ao = np.ones(n, dtype=F32)  # multiplies base and ink
        self.rgb = np.zeros((n, 3), dtype=F32)  # ink, sRGB
        self.a = np.zeros(n, dtype=F32)
        self.h = np.zeros(n, dtype=F32)
        self.rough = np.full(n, rough, dtype=F32)

    def tone(self, mask, amount):
        """Lighter (amount > 0) or darker (< 0) base where mask is 1."""
        self.shade *= (1 + amount * np.clip(mask, 0, 1)).astype(F32)

    def ink(self, mask, colour, alpha=1.0):
        m = (np.clip(mask, 0, 1) * alpha).astype(F32)
        col = np.asarray(colour, dtype=F32)
        if col.ndim == 1:
            col = np.broadcast_to(col, (self.n, 3))
        tot = m + self.a * (1 - m)
        self.rgb = np.where(tot[:, None] > 1e-5, (col * m[:, None] + self.rgb * (self.a * (1 - m))[:, None]) / np.maximum(tot, 1e-5)[:, None], self.rgb)
        self.a = tot

    def lift(self, mask, height):
        self.h += (np.clip(mask, 0, 1) * height).astype(F32)

    def gloss(self, mask, rough):
        m = np.clip(mask, 0, 1).astype(F32)
        self.rough = self.rough * (1 - m) + F32(rough) * m

    def result(self):
        """(rgba, rough): the Overlay colour map's texels."""
        m = self.shade * self.ao
        dark = np.clip(1 - m, 0, 0.9)
        light = np.clip((m - 1) * 0.9, 0, 0.6)
        base_a = np.where(m < 1, dark, light)
        base_rgb = np.where((m < 1)[:, None], np.array([0.045, 0.04, 0.07], dtype=F32), np.array([1.0, 0.98, 0.94], dtype=F32))
        ink_rgb = self.rgb * np.clip(self.ao, 0, 1)[:, None]
        a = self.a + base_a * (1 - self.a)
        col = (ink_rgb * self.a[:, None] + base_rgb * (base_a * (1 - self.a))[:, None]) / np.maximum(a, 1e-5)[:, None]
        return np.concatenate([np.clip(col, 0, 1), np.clip(a, 0, 1)[:, None]], axis=1).astype(F32), self.rough


# ---- small shape helpers ---------------------------------------------------------------------------

def band(v, lo, hi, soft=0.006):
    return sstep(lo - soft, lo + soft, v) * (1 - sstep(hi - soft, hi + soft, v))


def line(d, w, soft=0.004):
    """1 on a line of half-width w given the signed distance d to its centre."""
    return 1 - sstep(w - soft, w + soft, np.abs(d))


def disc(dx, dz, r, soft=0.004):
    return 1 - sstep(r - soft, r + soft, np.sqrt(dx * dx + dz * dz))


def box(dx, dz, hx, hz, r=0.01, soft=0.004):
    qx, qz = np.abs(dx) - (hx - r), np.abs(dz) - (hz - r)
    d = np.sqrt(np.maximum(qx, 0) ** 2 + np.maximum(qz, 0) ** 2) + np.minimum(np.maximum(qx, qz), 0) - r
    return 1 - sstep(-soft, soft, d), d


def stitch(d, along, w=0.0035, dash=0.022):
    """A row of stitches: dashes along `along` on the line d = 0."""
    return line(d, w, 0.002) * (np.mod(along, dash) < dash * 0.62)


def seg_dist(px, pz, ax, az, bx, bz):
    """Distance from (px, pz) to the segment a-b, and the position along it (0..1)."""
    vx, vz = bx - ax, bz - az
    t = np.clip(((px - ax) * vx + (pz - az) * vz) / (vx * vx + vz * vz), 0, 1)
    return np.sqrt((px - ax - vx * t) ** 2 + (pz - az - vz * t) ** 2), t


def cloth(c, P, seed=0, wrinkle=1.0, weave=1.0):
    """Woven cloth: soft mottling, broad wrinkles, a fine weave."""
    c.tone(tx.fbm(P * 2.3, 3, seed) - 0.5, 0.16)
    c.tone(tx.fbm(P * 9.0, 3, seed + 5) - 0.5, 0.09)
    c.h += (0.010 * wrinkle) * (tx.fbm(P * F32(4.2), 3, seed + 9) - 0.5)
    w = tx.vnoise(P * np.array([150, 150, 60], dtype=F32), seed + 2) * tx.vnoise(P * np.array([60, 60, 150], dtype=F32), seed + 3)
    c.h += (0.0035 * weave) * w
    c.tone(w - 0.25, 0.05 * weave)


def skin(c, P, seed=0):
    c.rough[:] = 0.62
    c.tone(tx.fbm(P * 3.0, 3, seed) - 0.5, 0.07)
    c.tone(tx.fbm(P * 21.0, 2, seed + 4) - 0.5, 0.035)
    c.h += 0.0016 * (tx.vnoise(P * 190.0, seed + 6) - 0.5)
    c.ink(tx.fbm(P * 5.0, 2, seed + 8) > 0.55, (0.86, 0.42, 0.36), 0.035)  # a little warmth in patches


# ---- the body ----------------------------------------------------------------------------------------

BELT = {"shirt": "#3a271a", "jacket": "#2a2420", "police": "#17171a", "guard": "#1b1b1e", "mime": "#17171a"}
BUCKLE = {"shirt": "#c9a45a", "jacket": "#a9adb2", "police": "#c7cace", "guard": "#b8bcc0", "mime": "#b8bcc0"}
SOLE = {"shirt": "#e8e3d6", "jacket": "#e6dfcd", "coat": "#2a2622", "scrubs": "#f4f4f1", "police": "#141416", "guard": "#141416",
        "mime": "#141416"}
SOCK = {"shirt": "#e9e7e0", "jacket": "#d9d5c9", "coat": "#3a3d44", "scrubs": "#f2f2ee", "police": "#1c1d22", "guard": "#1c1d22",
        "mime": "#f2f2ee"}
LACE = {"shirt": "#efe9da", "jacket": "#efe9da", "coat": "#2b2622", "scrubs": None, "police": "#101012", "guard": "#101012",
        "mime": "#101012"}
STEEL = np.array([0.74, 0.76, 0.79], dtype=F32)
GOLD = np.array([0.86, 0.68, 0.27], dtype=F32)
LONG_SLEEVES = ("jacket", "coat", "police", "mime")
STRIPE_PERIOD = 0.27


def hoops(z):
    """The mime's black hoops (1 on a stripe)."""
    return band(np.mod(z - 0.02, STRIPE_PERIOD), 0.0, 0.118, 0.006)


def _buttons(c, front, x, z, zs, r, colour, rim=0.55, x0=0.0):
    for zb in zs:
        d = np.sqrt((x - x0) ** 2 + (z - zb) ** 2)
        m = front * (1 - sstep(r - 0.004, r + 0.004, d))
        c.ink(m, colour)
        c.ink(front * band(d, r * 0.62, r, 0.003), np.asarray(colour) * rim)
        for hx in (-0.3, 0.3):
            c.ink(front * disc(x - x0 - hx * r, z - zb, r * 0.16, 0.002), np.asarray(colour) * 0.3)
        c.lift(m, 0.009)
        c.gloss(m, 0.35)
        c.tone(front * band(d, r, r + 0.018, 0.006), -0.22)  # the button's shadow on the cloth


def _collar_edge(ax):
    """Height of a shirt collar's lower edge against |x| (points at |x| = 0.22)."""
    return np.where(ax < 0.22, 3.965 - (ax - 0.015) * (0.165 / 0.205), 3.80 + (ax - 0.22) * (0.185 / 0.15))


def _shirt_collar(c, P, front, lift=0.014, tone=0.07, open_neck=None):
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    ax = np.abs(x)
    rn = np.sqrt(x * x + (y - 0.02) ** 2)
    edge = _collar_edge(ax)
    wing = front * (ax < 0.375) * (ax > 0.012)
    d = np.where(wing > 0, z - edge, z - 3.955)
    inside = sstep(-0.004, 0.004, d) * np.maximum(wing, (rn < 0.40) * (1 - front * (ax < 0.375)))
    c.tone(inside, tone)
    c.lift(inside, lift)
    c.tone(band(d, -0.03, -0.002, 0.008) * np.maximum(wing, rn < 0.42), -0.3)  # shadow under the collar
    c.tone(line(d - 0.012, 0.003) * inside * (np.mod(ax * 1.0 + z, 0.02) < 0.013), -0.18)  # edge stitching
    if open_neck is not None:
        gap = front * (ax < (z - 3.80) * 0.36) * (z > 3.80)
        c.ink(gap, open_neck)
    return inside


def _pocket(c, front, x, z, cx, cz, hx, hz, flap=False, button=None):
    m, d = box(x - cx, z - cz, hx, hz, 0.022)
    m = m * front
    c.lift(m, 0.005)
    c.tone(front * band(d, -0.004, 0.012, 0.004), -0.2)
    c.tone(front * stitch(d + 0.014, x + z) * (d < 0), -0.22)
    if flap:
        fl = front * (np.abs(x - cx) < hx) * band(z, cz + hz - 0.085 + 0.03 * np.abs(x - cx) / hx, cz + hz + 0.004, 0.004)
        c.lift(fl, 0.006)
        c.tone(front * (np.abs(x - cx) < hx) * line(z - (cz + hz - 0.085 + 0.03 * np.abs(x - cx) / hx), 0.004), -0.3)
    if button is not None:
        _buttons(c, front, x, z, [cz + hz - (0.05 if flap else 0.035)], 0.017, button, x0=cx)


def upper_torso(c, P, N, outfit):
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    ax = np.abs(x)
    front = sstep(0.05, 0.25, -N[:, 1])
    back = sstep(0.05, 0.25, N[:, 1])
    cloth(c, P, seed=11, wrinkle=1.0 if outfit != "police" else 0.7)
    az = np.degrees(np.arctan2(x, -y))  # 0 front, +-90 the sides
    side = line(np.abs(az) - 90, 0.9, 0.5) * (z < 3.5)
    c.tone(side, -0.16)  # side seams
    c.tone(sstep(2.72, 2.52, z), -0.12)  # the tuck at the waist
    c.h += 0.006 * np.sin((x * 1.7 + z) * 23.0) * sstep(2.95, 2.6, z)  # folds gathered above the belt
    if outfit in ("shirt", "police", "guard"):
        plk = front * line(x, 0.046)
        c.lift(plk, 0.005)
        c.tone(front * line(ax - 0.046, 0.004), -0.22)
        c.tone(front * stitch(ax - 0.034, z), -0.18)
        btn = {"shirt": (0.93, 0.91, 0.86), "police": STEEL, "guard": (0.13, 0.13, 0.15)}[outfit]
        if outfit != "police":
            _buttons(c, front, x, z, [3.70, 3.42, 3.14, 2.86], 0.03, btn)
        _shirt_collar(c, P, front, open_neck=(0.16, 0.17, 0.2) if outfit == "guard" else None)
        c.tone(back * line(z - 3.83 + 0.25 * ax * ax, 0.004), -0.2)  # yoke seam
        if outfit == "shirt":
            _pocket(c, front, x, z, 0.36, 3.42, 0.15, 0.135, button=None)
        else:
            for sx in (1, -1):
                _pocket(c, front, x, z, 0.36 * sx, 3.40, 0.15, 0.125, flap=True, button=STEEL if outfit == "police" else (0.13, 0.13, 0.15))
            ep = sstep(0.2, 0.5, N[:, 2]) * band(ax, 0.47, 0.86, 0.008) * line(y - 0.02, 0.075, 0.006)  # epaulettes
            c.tone(ep, -0.3)
            c.lift(ep, 0.008)
            c.ink(sstep(0.2, 0.5, N[:, 2]) * disc(ax - 0.52, y - 0.02, 0.022), STEEL)
        if outfit == "police":
            tie = front * (ax < 0.058 - 0.022 * sstep(3.9, 3.2, z) + 0.03 * sstep(3.14, 3.02, z)) * (z < 3.955) * (z > 3.0 + 1.6 * ax)
            c.ink(tie, (0.09, 0.11, 0.17))
            c.ink(front * (ax < 0.06) * band(z, 3.87, 3.95), (0.06, 0.08, 0.13))  # the knot
            c.lift(tie, 0.009)
            c.ink(tie * line(np.mod(z + x, 0.05) - 0.025, 0.003), (0.16, 0.19, 0.27), 0.6)
            _buttons(c, front, x, z, [2.86], 0.028, STEEL)
            # the badge over the left pocket: a gold shield with a star
            bx, bz = x - 0.36, z - 3.655
            shield = (np.abs(bx) < 0.07 * np.clip(1 - np.maximum(-bz - 0.0, 0) / 0.085, 0, 1) ** 0.6) * (np.abs(bz) < 0.085)
            sh = front * shield
            c.ink(sh, GOLD)
            c.ink(front * shield * (np.abs(bx) > 0.07 * np.clip(1 - np.maximum(-bz, 0) / 0.085, 0, 1) ** 0.6 - 0.012), GOLD * 0.62)
            ang = np.arctan2(bx, bz)
            star = np.sqrt(bx * bx + bz * bz) < 0.034 * (0.62 + 0.38 * np.cos(5 * ang))
            c.ink(front * star, (0.97, 0.9, 0.62))
            c.lift(sh, 0.012)
            c.gloss(sh, 0.28)
            c.tone(front * (np.abs(bx) < 0.085) * (np.abs(bz) < 0.1) * (1 - shield), -0.2)
            m, _d = box(x + 0.36, z - 3.60, 0.075, 0.018, 0.005)  # name bar
            c.ink(front * m, STEEL)
            c.gloss(front * m, 0.3)
        if outfit == "guard":
            bx, bz = x - 0.36, z - 3.655  # an embroidered shield patch
            shield = (np.abs(bx) < 0.075 * np.clip(1 - np.maximum(-bz, 0) / 0.09, 0, 1) ** 0.6) * (np.abs(bz) < 0.09)
            inner = (np.abs(bx) < 0.055 * np.clip(1 - np.maximum(-bz, 0) / 0.07, 0, 1) ** 0.6) * (np.abs(bz) < 0.07)
            c.ink(front * shield, (0.93, 0.93, 0.9))
            c.ink(front * inner, (0.2, 0.42, 0.47))
            c.ink(front * inner * (line(bx, 0.009) + line(bz - 0.01, 0.009) > 0), (0.93, 0.93, 0.9))
            c.lift(front * shield, 0.006)
            m, _d = box(x + 0.40, z - 3.74, 0.05, 0.085, 0.014)  # the radio on the right shoulder strap
            c.ink(front * m, (0.08, 0.08, 0.09))
            c.ink(front * m * band(z, 3.755, 3.80) * (np.abs(x + 0.40) < 0.032) * (np.mod(z, 0.012) < 0.006), (0.3, 0.3, 0.32))
            c.ink(front * line(x + 0.43, 0.007) * band(z, 3.82, 3.93), (0.08, 0.08, 0.09))
            c.lift(front * m, 0.02)
            c.gloss(front * m, 0.4)
    elif outfit == "jacket":
        zipm = front * line(x, 0.016, 0.003) * (z < 3.97)
        c.ink(zipm, np.where((np.mod(z, 0.018) < 0.009)[:, None], np.array([0.72, 0.73, 0.75], dtype=F32), np.array([0.38, 0.39, 0.42], dtype=F32)))
        c.gloss(zipm, 0.35)
        c.lift(front * line(ax - 0.034, 0.018), 0.006)
        c.tone(front * line(ax - 0.055, 0.004), -0.2)
        m, _d = box(x, z - 3.86, 0.022, 0.04, 0.008)
        c.ink(front * m, STEEL)  # the puller
        c.lift(front * m, 0.012)
        rn = np.sqrt(x * x + (y - 0.02) ** 2)
        col = (rn < 0.42) * (z > 3.93)
        c.tone(col, -0.2)
        c.lift(col, 0.012)
        ribs = np.sin(np.degrees(np.arctan2(x, y - 0.02)) * 1.1)
        c.h += 0.004 * ribs * col
        hem = sstep(2.74, 2.70, z)
        c.tone(hem, -0.18)
        c.h += 0.004 * np.sin(az * 1.5) * hem
        c.tone(line(z - 2.74, 0.004), -0.25)
        for sx in (1, -1):  # slanted hand pockets
            d, t = seg_dist(x, z, 0.30 * sx, 3.12, 0.50 * sx, 2.86)
            c.tone(front * line(d, 0.007), -0.4)
            c.lift(front * line(d - 0.012, 0.012), 0.004)
        c.tone(back * line(z - 3.80 + 0.2 * ax * ax, 0.004), -0.2)
    elif outfit == "coat":
        w = np.clip(0.27 * (z - 3.40) / 0.60, 0, 0.27)  # half-width of the V between the lapels
        vee = front * (ax < w) * (z > 3.40)
        c.ink(vee, (0.72, 0.82, 0.9))  # the shirt
        c.ink(vee * (np.mod(x * 1.0, 0.03) < 0.004), (0.62, 0.74, 0.86))
        tie = front * (ax < 0.052 - 0.014 * sstep(3.9, 3.45, z)) * (z > 3.40) * (z < 3.96)
        c.ink(tie, (0.55, 0.13, 0.16))
        c.ink(tie * line(np.mod(z - x, 0.045) - 0.022, 0.004), (0.72, 0.3, 0.3), 0.7)
        c.ink(front * (ax < 0.058) * band(z, 3.87, 3.95), (0.45, 0.1, 0.13))
        scol = front * (ax < 0.2) * (z > 3.955 - (ax - 0.015) * 0.7) * (z > 3.82)  # the shirt's own collar
        c.ink(scol * (ax > 0.03), (0.8, 0.88, 0.94))
        lap_w = 0.15 * sstep(3.40, 3.62, z) * (1 - 0.35 * sstep(3.80, 3.84, z))
        lapel = front * (ax >= w) * (ax < w + lap_w) * (z > 3.40) * (z < 4.02)
        c.lift(lapel, 0.014)
        c.tone(lapel, 0.05)
        c.tone(front * line(ax - w - lap_w, 0.005) * (z > 3.42) * (z < 4.0), -0.28)
        c.tone(front * line(ax - w, 0.004) * (z > 3.40), -0.3)
        c.tone(front * line(z - 3.82, 0.004) * (ax > w + lap_w * 0.55) * (ax < w + 0.16), -0.3)  # the notch
        rn = np.sqrt(x * x + (y - 0.02) ** 2)
        c.lift((rn < 0.40) * (z > 3.955) * (1 - front * (ax < 0.3)), 0.012)
        c.tone(front * line(x - 0.03, 0.004) * (z < 3.40), -0.3)  # the front edge, buttoned left over right
        _buttons(c, front, x, z, [3.26, 2.98, 2.70], 0.032, (0.9, 0.9, 0.88), x0=-0.04)
        _pocket(c, front, x, z, 0.38, 3.36, 0.14, 0.12)
        for i, (pc, px) in enumerate((((0.16, 0.3, 0.62), 0.31), ((0.7, 0.14, 0.14), 0.37), ((0.12, 0.12, 0.14), 0.43))):
            m, _d = box(x - px, z - 3.52, 0.012, 0.055, 0.006)
            c.ink(front * m, pc)  # pens
            c.ink(front * m * (z > 3.55), STEEL)
            c.lift(front * m, 0.008)
        c.tone(back * line(x, 0.004) * (z < 3.3), -0.22)  # the back seam
    elif outfit == "scrubs":
        w = np.clip(0.30 * (z - 3.60) / 0.40, 0, 0.30)
        rn = np.sqrt(x * x + (y - 0.02) ** 2)
        trim = front * (ax >= w - 0.004) * (ax < w + 0.05) * (z > 3.56) * (z < 4.04)
        trim = np.maximum(trim, (rn < 0.41) * (z > 3.955) * (1 - front * (ax < 0.36)))
        trim = np.maximum(trim, front * (z > 3.545) * (z <= 3.60) * (ax < 0.05 - (3.60 - z) * 0.9))
        c.tone(trim, -0.2)
        c.lift(trim, 0.008)
        c.tone(front * stitch(ax - w - 0.036, z, dash=0.02) * (z > 3.6) * (z < 4.0), -0.2)
        c.tone(front * (ax < w) * (z > 3.60), -0.45)  # under the bare-skin patch
        _pocket(c, front, x, z, 0.36, 3.38, 0.15, 0.13)
        m, _d = box(x - 0.42, z - 3.53, 0.012, 0.045, 0.006)
        c.ink(front * m, (0.14, 0.2, 0.5))
        c.lift(front * m, 0.008)
        c.tone(back * line(z - 3.84 + 0.22 * ax * ax, 0.004), -0.18)
        c.h += 0.004 * np.sin((z + 0.6 * ax) * 17.0) * sstep(3.2, 2.7, z)  # the loose hang
    elif outfit == "mime":
        st = hoops(z)
        c.ink(st, (0.075, 0.075, 0.085))
        rn = np.sqrt(x * x + (y - 0.02) ** 2)
        c.ink((rn < 0.40) * (z > 3.96), (0.075, 0.075, 0.085))  # the neckband
        c.lift((rn < 0.40) * (z > 3.96), 0.008)
        br = (line(ax - 0.33 + 0.04 * sstep(3.0, 3.9, z), 0.04) * front + line(ax - 0.05 - 0.36 * sstep(2.5, 3.9, z), 0.04) * back) * (z < 4.2)
        br = np.maximum(br, sstep(0.2, 0.5, N[:, 2]) * line(ax - 0.37, 0.045) * (1 - front) * (1 - back))
        c.ink(br, (0.74, 0.1, 0.11))  # red braces
        c.lift(br, 0.01)
        c.tone(br * line(np.abs(ax - 0.33 + 0.04 * sstep(3.0, 3.9, z)) - 0.03, 0.003) * front, -0.3)
        for sx in (1, -1):  # the clips at the waistband
            m, _d = box(x - 0.33 * sx, z - 2.63, 0.035, 0.045, 0.008)
            c.ink(front * m, STEEL)
            c.gloss(front * m, 0.3)


def lower_torso(c, P, N, outfit):
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    ax = np.abs(x)
    front = sstep(0.05, 0.25, -N[:, 1])
    back = sstep(0.05, 0.25, N[:, 1])
    az = np.degrees(np.arctan2(x, -y))
    wall = sstep(0.75, 0.4, N[:, 2])  # not the flat top
    cloth(c, P, seed=23)
    if outfit in ("scrubs", "coat"):
        c.tone(line(np.abs(az) - 90, 0.9, 0.5) * wall, -0.14)
        if outfit == "scrubs":
            for sx in (1, -1):
                _pocket(c, front, x, z, 0.34 * sx, 2.32, 0.2, 0.15)
            c.tone(line(np.abs(az) - 90, 1.6, 0.5) * (z < 2.2) * wall, -0.5)  # side vents
            c.tone(stitch(z - 2.02, az * 0.01, dash=0.2 * 0.1) * wall * (z < 2.1), -0.15)
        else:
            c.tone(front * line(x - 0.03, 0.004), -0.3)
            _buttons(c, front, x, z, [2.42], 0.032, (0.9, 0.9, 0.88), x0=-0.04)
            for sx in (1, -1):
                _pocket(c, front, x, z, 0.40 * sx, 2.27, 0.17, 0.16, flap=True)
            c.tone(back * line(x, 0.004), -0.22)
        return
    duty = outfit == "police"
    z0 = 2.445 if duty else 2.468
    belt = wall * sstep(z0 - 0.004, z0 + 0.004, z)
    loops = wall * (np.mod(az + 22.5, 45.0) < 5.0) * (np.abs(az) > 12) if not duty else 0.0
    c.ink(belt * (1 - loops), rgb(BELT[outfit]))
    c.lift(belt, 0.012)
    c.gloss(belt * (1 - loops), 0.5)
    c.tone(wall * band(z, z0 - 0.03, z0 - 0.002, 0.006), -0.3)
    c.ink(belt * line(z - z0 - 0.012, 0.0025) * (np.mod(az, 3.0) < 1.9) * (1 - loops), rgb(BELT[outfit]) * 1.9 + 0.05)  # stitching
    bw, bh = (0.075, 0.05) if duty else (0.062, 0.043)
    m, d = box(x, z - (z0 + 2.56) / 2, bw, bh, 0.01)
    c.ink(front * m, rgb(BUCKLE[outfit]))
    c.ink(front * (d < -0.016), rgb(BELT[outfit]) * 0.8)
    c.ink(front * m * line(x - 0.01, 0.006), rgb(BUCKLE[outfit]) * 0.75)
    c.lift(front * m, 0.012)
    c.gloss(front * m, 0.28)
    if duty:  # pouches and a torch loop on the belt
        for a0, hw, hh in ((52, 0.085, 0.1), (-52, 0.07, 0.085), (118, 0.07, 0.09), (-125, 0.085, 0.1)):
            da = (az - a0 + 180) % 360 - 180
            m, d = box(da * 0.0125, z - (2.46 - hh * 0.25), hw, hh, 0.02)
            m = m * wall
            c.ink(m, (0.085, 0.085, 0.095))
            c.ink(m * line(d + 0.012, 0.003), (0.24, 0.24, 0.26))
            c.ink(m * line(z - (2.46 + hh * 0.2), 0.004), (0.03, 0.03, 0.035))
            c.ink(wall * disc(da * 0.0125, z - (2.46 + hh * 0.05), 0.014), STEEL)
            c.lift(m, 0.022)
            c.gloss(m, 0.45)
    # fly, pockets, seams
    c.tone(front * line(x - 0.012, 0.004) * (z < z0), -0.3)
    c.tone(front * stitch(np.sqrt((x - 0.012) ** 2 + (np.minimum(z - 2.16, 0)) ** 2) - 0.062, z + x) * (x > 0.012) * (z < z0 - 0.01) * (z > 2.08), -0.22)
    for sx in (1, -1):
        d, _t = seg_dist(x, z, 0.30 * sx, z0, 0.62 * sx, 2.24)
        c.tone(front * wall * line(d, 0.006), -0.4)
        c.tone(front * wall * stitch(d - 0.016, z), -0.18)
        m, d2 = box(x - 0.3 * sx, z - 2.3, 0.14, 0.12, 0.02)
        c.tone(back * wall * band(d2, -0.004, 0.006, 0.003), -0.25)  # hip pockets
        c.tone(back * wall * stitch(d2 + 0.016, x + z) * (d2 < 0), -0.2)
    c.tone(line(np.abs(az) - 90, 0.8, 0.4) * wall * (z < z0), -0.2)
    c.tone(back * line(x, 0.004) * (z < z0), -0.2)


def _limb_az(P, cx):
    """Angle round a vertical limb at x = cx: 0 front, 90 the outside (left limb), 180 back."""
    return np.degrees(np.arctan2(P[:, 0] - cx, -P[:, 1]))


def upper_arm(c, P, N, outfit):
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    az = _limb_az(P, J["LeftElbow"][0])
    cloth(c, P, seed=31, wrinkle=1.2)
    if outfit == "mime":
        c.ink(hoops(z), (0.075, 0.075, 0.085))
        return
    c.tone(line(np.abs(az) - 178, 2.5, 1.0) * (z < 3.6), -0.14)  # the seam under the arm
    if outfit in LONG_SLEEVES:
        c.h += 0.007 * np.sin(z * 55.0 + 2.0 * np.sin(az * 0.05)) * np.exp(-((z - 3.07) / 0.13) ** 2)  # folds at the elbow
    else:
        hem = 3.035 - 0.085
        c.tone(line(z - hem, 0.004), -0.25)
        c.tone(stitch(z - hem - 0.02, az * 0.004), -0.2)
        c.lift(z < hem + 0.03, 0.004)
        c.tone(sstep(hem, hem - 0.12, z), -0.12)
    if outfit in ("police", "guard"):  # a shoulder patch on the outside of the sleeve
        da = (az - 90 + 180) % 360 - 180
        bx, bz = da * 0.0045, z - 3.52
        sh = (np.abs(bx) < 0.085 * np.clip(1 - np.maximum(-bz, 0) / 0.11, 0, 1) ** 0.55) * (np.abs(bz) < 0.11) * (np.abs(da) < 60)
        inn = (np.abs(bx) < 0.066 * np.clip(1 - np.maximum(-bz, 0) / 0.09, 0, 1) ** 0.55) * (np.abs(bz) < 0.09) * (np.abs(da) < 60)
        if outfit == "police":
            c.ink(sh, GOLD * 0.9)
            c.ink(inn, (0.1, 0.16, 0.3))
            ang = np.arctan2(bx, bz + 0.005)
            c.ink(inn * (np.sqrt(bx * bx + (bz + 0.005) ** 2) < 0.04 * (0.62 + 0.38 * np.cos(5 * ang))), GOLD)
        else:
            c.ink(sh, (0.93, 0.93, 0.9))
            c.ink(inn, (0.2, 0.42, 0.47))
            c.ink(inn * (line(bx, 0.01) + line(bz - 0.01, 0.01) > 0), (0.93, 0.93, 0.9))
        c.lift(sh, 0.006)


def lower_arm(c, P, N, outfit):
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    az = _limb_az(P, J["LeftWrist"][0])
    wr = J["LeftWrist"][2]
    if outfit not in LONG_SLEEVES:
        skin(c, P, seed=41)
        c.ink(sstep(2.9, 3.1, z), (0.8, 0.36, 0.3), 0.07)  # the elbow
        c.tone(line(z - (wr - 0.075), 0.006), -0.12)
        return
    cloth(c, P, seed=37, wrinkle=1.2)
    c.tone(line(np.abs(az) - 178, 2.5, 1.0), -0.14)
    c.h += 0.006 * np.sin(z * 50.0) * np.exp(-((z - 2.98) / 0.12) ** 2)
    cuff = wr + 0.075
    if outfit == "mime":
        c.ink(hoops(z) * (z > cuff), (0.075, 0.075, 0.085))
        c.tone(line(z - cuff, 0.004), -0.25)
        return
    c.tone(line(z - cuff, 0.005), -0.3)
    c.lift(z < cuff, 0.008)
    if outfit == "jacket":
        c.tone(z < cuff, -0.2)
        c.h += 0.004 * np.sin(az * 0.35) * (z < cuff)
    else:
        c.tone(stitch(z - cuff + 0.02, az * 0.004), -0.2)
        d = np.sqrt(((az - 100 + 180) % 360 - 180) ** 2 * 0.0026 ** 2 + (z - (wr + 0.0)) ** 2)
        btn = STEEL if outfit == "police" else np.array([0.9, 0.9, 0.88], dtype=F32)
        c.ink(d < 0.02, btn)
        c.lift(d < 0.02, 0.008)


def hand(c, P, N, outfit, detail_ao=None):
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    wr = np.array(J["LeftWrist"])
    if outfit == "mime":  # white gloves
        cloth(c, P, seed=43, wrinkle=0.6)
        c.tone(line(z - (wr[2] - 0.12), 0.005), -0.2)
        return
    skin(c, P, seed=47)
    palm_side = sstep(0.1, 0.5, -(N[:, 0] * math.cos(math.radians(-24)) + N[:, 1] * math.sin(math.radians(-24))))
    c.ink(palm_side, (1.0, 0.86, 0.8), 0.14)  # palms are paler
    knuck = band(z, wr[2] - 0.36, wr[2] - 0.29, 0.02) * (1 - palm_side)
    c.ink(knuck, (0.82, 0.38, 0.33), 0.1)
    tips = sstep(wr[2] - 0.47, wr[2] - 0.53, z)
    c.ink(tips, (0.86, 0.4, 0.36), 0.08)


def upper_leg(c, P, N, outfit):
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    az = _limb_az(P, 0.5)
    front = sstep(0.05, 0.25, -N[:, 1])
    back = sstep(0.05, 0.25, N[:, 1])
    cloth(c, P, seed=53, wrinkle=1.1)
    c.tone(line(np.abs(az) - 90, 1.6, 0.6) * (x > 0.5), -0.2)  # the outside seam
    c.tone(line(np.abs(az) - 90, 1.6, 0.6) * (x < 0.5) * (z < 1.75), -0.16)  # the inseam
    c.h += 0.007 * np.sin(z * 46.0 + 3.0 * np.sin(az * 0.03)) * np.exp(-((z - 1.24) / 0.13) ** 2)  # folds at the knee
    c.h += 0.006 * np.sin((z - 0.5 * np.abs(x - 0.5)) * 30.0) * np.exp(-((z - 1.95) / 0.14) ** 2) * front  # at the hip
    if outfit in ("coat", "police", "guard"):
        crease = line(az, 2.2, 1.0) * (z < 1.85)
        c.tone(crease, 0.1)
        c.lift(crease, 0.004)
    if outfit == "police":
        c.ink(line(az - 90, 6.5, 1.0) * (z < 2.2), (0.55, 0.62, 0.74), 0.5)  # the stripe down the leg
    if outfit == "scrubs":
        m, d = box((az - 90) * 0.005, z - 1.55, 0.13, 0.14, 0.02)
        m = m * (np.abs(az - 90) < 60)
        c.tone(band(d, -0.004, 0.006, 0.003) * (np.abs(az - 90) < 60), -0.25)  # a thigh pocket
        c.tone(stitch(d + 0.016, z + az * 0.005) * (d < 0) * (np.abs(az - 90) < 60), -0.2)
        c.lift(m, 0.004)
    if outfit in ("shirt", "jacket"):
        m, d = box(x - 0.52, z - 2.02, 0.15, 0.13, 0.02)  # patch pockets on the seat
        c.tone(back * band(d, -0.004, 0.006, 0.003), -0.25)
        c.tone(back * stitch(d + 0.016, x + z) * (d < 0), -0.2)
        c.tone(back * stitch(np.abs(x - 0.52) * 0.8 - (z - 2.0), x) * (d < -0.02), -0.12)


def lower_leg(c, P, N, outfit):
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    az = _limb_az(P, 0.5)
    cloth(c, P, seed=59, wrinkle=1.1)
    c.tone(line(np.abs(az) - 90, 1.8, 0.6), -0.18)
    hem = J["LeftAnkle"][2] - 0.13
    c.tone(stitch(z - hem - 0.05, az * 0.005), -0.22)
    c.tone(line(z - hem - 0.012, 0.004), -0.15)
    c.h += 0.006 * np.sin(z * 40.0 + 2.0 * np.sin(az * 0.04)) * np.exp(-((z - 0.42) / 0.13) ** 2)  # breaks over the shoe
    if outfit in ("coat", "police", "guard"):
        crease = line(az, 2.6, 1.0)
        c.tone(crease, 0.1)
        c.lift(crease, 0.004)
    if outfit == "police":
        c.ink(line(az - 90, 7.5, 1.0), (0.55, 0.62, 0.74), 0.5)
    c.tone(sstep(0.2, 0.35, -N[:, 2]) * (z < hem + 0.02), -0.6)  # the dark inside of the hem


def foot(c, P, N, outfit):
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    ank = np.array(J["LeftAnkle"])
    c.rough[:] = 0.5
    c.tone(tx.fbm(P * 6.0, 3, 61) - 0.5, 0.14)
    c.h += 0.0025 * (tx.fbm(P * 40.0, 2, 62) - 0.5)
    ball = np.sqrt((x - ank[0]) ** 2 + y ** 2 + (z - ank[2]) ** 2) < 0.19
    sock = ball * (z > 0.3)
    c.ink(sock, rgb(SOCK[outfit]))
    c.ink(sock * (np.mod(np.degrees(np.arctan2(x - ank[0], y)), 12.0) < 4.0), rgb(SOCK[outfit]) * 0.86)  # ribbing
    c.gloss(sock, 0.9)
    c.tone(line(z - 0.3, 0.012) * ball, -0.3)  # the shoe's collar
    sole = sstep(0.064, 0.056, z)
    c.ink(sole, rgb(SOLE[outfit]))
    c.gloss(sole, 0.75)
    c.ink(sole * (N[:, 2] < -0.5), rgb(SOLE[outfit]) * 0.55)  # the tread
    c.ink(line(z - 0.066, 0.006), (0.1, 0.09, 0.08), 0.75)  # the welt
    c.h -= 0.006 * line(z - 0.066, 0.008)
    c.ink(sole * line(z - 0.03, 0.003) * (N[:, 2] > -0.5), rgb(SOLE[outfit]) * 0.7)
    top = sstep(0.25, 0.6, N[:, 2])
    if outfit == "scrubs":  # clogs: a strap and vent holes
        d, _t = seg_dist(x - ank[0], y, 0.0, -0.22, 0.0, -0.22)
        holes = (np.sqrt((np.mod(x - ank[0] + 0.03, 0.06) - 0.03) ** 2 + (np.mod(y + 0.03, 0.07) - 0.035) ** 2) < 0.012) * top * (y < -0.25) * (y > -0.52)
        c.ink(holes, (0.2, 0.2, 0.22), 0.8)
        c.tone(line(y + 0.2 - 0.25 * np.abs(x - ank[0]), 0.006) * (z > 0.07), -0.3)
        return
    cap = line(np.sqrt((x - ank[0]) ** 2 * 1.2 + (y + 0.62) ** 2) - 0.25, 0.005) * (z > 0.07) * (y < -0.3)
    c.tone(cap, -0.3)  # the toe cap's seam
    c.tone(stitch(np.sqrt((x - ank[0]) ** 2 * 1.2 + (y + 0.62) ** 2) - 0.268, x * 3) * (z > 0.07) * (y < -0.3), -0.2)
    c.tone(line(np.abs(x - ank[0]) - 0.075 - 0.1 * (y + 0.34), 0.004) * (y > -0.36) * (y < -0.1) * top, -0.3)  # the facing
    if LACE[outfit]:
        lc = rgb(LACE[outfit])
        tongue = top * (np.abs(x - ank[0]) < 0.07 + 0.1 * (y + 0.34)) * (y > -0.36) * (y < -0.12)
        for i, yl in enumerate((-0.33, -0.275, -0.22, -0.165)):
            hw = 0.075 + 0.1 * (yl + 0.34)
            lace = top * line(y - yl - 0.35 * (np.abs(x - ank[0]) - hw * 0.5) * (1 if i % 2 else -1) * 0.3, 0.011) * (np.abs(x - ank[0]) < hw + 0.01)
            c.ink(lace, lc)
            c.lift(lace, 0.008)
            for sx in (1, -1):
                c.ink(top * disc(x - ank[0] - sx * (hw + 0.012), y - yl, 0.011), lc * 0.5 + 0.2)
        c.tone(tongue, -0.12)
    heel = line(np.abs(x - ank[0]) - 0.0, 0.006) * (y > 0.2) * (z > 0.07) * (z < 0.3)
    c.tone(heel, -0.25)


def coat_tail(c, P, N, outfit):
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    az = _limb_az(P, 0.5)
    cloth(c, P, seed=67)
    hem = J["LeftHip"][2] - 0.5
    c.tone(stitch(z - hem - 0.04, az * 0.006), -0.2)
    c.tone(line(np.abs(az) - 90, 1.5, 0.6) * (x > 0.5), -0.16)
    c.tone(sstep(0.2, 0.35, -N[:, 2]) * (z < hem + 0.02), -0.6)
    front = sstep(0.05, 0.25, -N[:, 1])
    m, d = box(x - 0.42, z - 1.94, 0.16, 0.15, 0.02)  # the hip pocket runs on from the pelvis
    c.tone(front * band(d, -0.004, 0.006, 0.003) * (z < 2.05), -0.22)
    c.h += 0.005 * np.sin(az * 0.09) * sstep(1.9, 1.6, z)  # the skirt's flutes


def v_neck(c, P, N, outfit):
    x, z = P[:, 0], P[:, 2]
    skin(c, P, seed=71)
    for sx in (1, -1):  # collar bones
        d, _t = seg_dist(x, z, 0.04 * sx, 3.90, 0.3 * sx, 3.97)
        c.tone(line(d, 0.012, 0.012), 0.07)
        c.tone(line(d + 0.0, 0.03, 0.02) * (z < 3.9 + 0.25 * np.abs(x)), -0.05)
    c.tone(sstep(3.9, 4.06, z), -0.2)  # under the chin
    c.tone(line(x, 0.01, 0.02) * (z < 3.85), -0.05)


def stethoscope(c, P, N, chart):
    c.shade[:] = 1.0
    if chart == "StethoDisc":
        c.ink(np.ones(c.n), STEEL)
        c.ink(tx.vnoise(P * 60.0, 3) > 0.7, STEEL * 0.85, 0.5)
        c.rough[:] = 0.26
    else:
        c.ink(np.ones(c.n), (0.13, 0.15, 0.2))
        c.rough[:] = 0.45


BODY_PAINTERS = {
    "UpperTorso": upper_torso, "LowerTorso": lower_torso, "UpperArm": upper_arm, "LowerArm": lower_arm, "Hand": hand,
    "Thumb": hand, "UpperLeg": upper_leg, "LowerLeg": lower_leg, "Foot": foot, "CoatTail": coat_tail, "VNeck": v_neck,
}


def body(chart, P, N, outfit):
    c = Canvas(len(P))
    if chart.startswith("Stetho"):
        stethoscope(c, P, N, chart)
    else:
        BODY_PAINTERS[chart](c, P, N, outfit)
    return c


# ---- the head ----------------------------------------------------------------------------------------

EXPRESSION = {
    # eye half-width / half-height, how far the upper lid comes down (0..1), iris and pupil radius,
    # brow height above the eye, brow slope (+ raises the inner ends), brow arch, mouth
    "calm": dict(ew=0.094, eh=0.106, lid=0.15, iris=0.071, pupil=0.034, by=0.19, slope=-0.04, arch=0.034, mouth="smile", look=(0.0, 0.0)),
    "worried": dict(ew=0.094, eh=0.118, lid=0.06, iris=0.062, pupil=0.03, by=0.2, slope=0.4, arch=0.012, mouth="waver", look=(0.0, 0.006)),
    "frightened": dict(ew=0.102, eh=0.14, lid=0.0, iris=0.046, pupil=0.02, by=0.25, slope=0.55, arch=0.03, mouth="gasp", look=(0.0, 0.0)),
}
EYE_X, EYE_Z, MOUTH_Z = 0.225, 4.85, 4.49
BROW = np.array([0.19, 0.13, 0.09], dtype=F32)


def head(chart, P, N, expression, face="plain"):
    c = Canvas(len(P))
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    skin(c, P, seed=3)
    if chart in ("EarL", "EarR"):
        c.ink(np.ones(c.n), (0.84, 0.4, 0.34), 0.1)
        return c
    if chart == "Neck":
        c.tone(sstep(4.2, 4.36, z) * sstep(0.0, -0.3, N[:, 1] - 0.2), -0.16)
        return c
    e = EXPRESSION[expression]
    mime = face == "mime"
    ax = np.abs(x)
    front = sstep(0.1, 0.35, -N[:, 1])
    # complexion
    if not mime:
        c.ink(front * disc(ax - 0.33, z - 4.6, 0.17, 0.12), (0.82, 0.3, 0.28), 0.12)  # cheeks
        c.ink(front * disc(x, z - 4.7, 0.075, 0.05), (0.86, 0.36, 0.32), 0.12)  # nose
        c.tone(front * disc(x, z - 5.15, 0.3, 0.2), 0.04)
        c.ink(front * disc(ax - EYE_X, z - (EYE_Z - 0.01), 0.15, 0.07), (0.5, 0.3, 0.34), 0.07)  # round the eyes
    else:
        oval = front * (1 - sstep(0.86, 1.0, np.sqrt((x / 0.5) ** 2 + ((z - 4.74) / 0.56) ** 2)))
        c.ink(oval, (0.955, 0.955, 0.94), 0.97)
        c.gloss(oval, 0.72)
        c.ink(front * disc(ax - 0.33, z - 4.58, 0.085, 0.012), (0.93, 0.45, 0.47), 0.75)
    # eyes
    ex, ez = ax - EYE_X, z - EYE_Z
    ew, eh = e["ew"], e["eh"]
    q = np.sqrt((ex / ew) ** 2 + (ez / eh) ** 2)
    lid_z = eh * (1 - 2 * e["lid"])
    lid_curve = lid_z - 0.25 * eh * (ex / ew) ** 2 * (e["lid"] > 0)
    white = front * (1 - sstep(0.94, 1.0, q)) * (ez < lid_curve)
    c.ink(white, (0.97, 0.965, 0.95))
    c.ink(white * sstep(0.55, 1.0, q), (0.8, 0.8, 0.84), 0.45)  # the eyeball turns away
    lx, lz = e["look"]
    ix, iz = (x - np.sign(x) * EYE_X) - lx, ez - lz - (-0.012 if e["lid"] > 0.1 else 0.0)
    r = np.sqrt(ix * ix + iz * iz)
    iris = white * (1 - sstep(e["iris"] - 0.005, e["iris"] + 0.003, r))
    c.ink(iris, (0.36, 0.22, 0.12))
    c.ink(iris * sstep(e["iris"] * 0.72, e["iris"], r), (0.16, 0.09, 0.05))
    c.ink(iris * sstep(0.0, -e["iris"], iz) * (r > e["pupil"]), (0.56, 0.37, 0.2), 0.6)  # light in the lower iris
    c.ink(white * (1 - sstep(e["pupil"] - 0.004, e["pupil"] + 0.003, r)), (0.03, 0.025, 0.03))
    hl = white * disc(ix - 0.022, iz - 0.024, 0.017, 0.004)
    c.ink(hl, (1.0, 1.0, 1.0))
    c.ink(white * disc(ix + 0.02, iz + 0.022, 0.008, 0.003), (1.0, 1.0, 1.0), 0.7)
    c.gloss(white, 0.18)
    c.tone(white * sstep(lid_curve - 0.03, lid_curve, ez), -0.25)  # the lid's shadow
    lash = (0.1, 0.07, 0.06) if not mime else (0.04, 0.04, 0.05)
    upper = front * (1 - sstep(0.94, 1.0, q * 0.93)) * (1 - white) * (ez > lid_curve - 0.004) * (ez < lid_curve + 0.02 + 0.01 * (1 - np.abs(ex) / ew))
    upper = np.maximum(upper, front * band(q, 0.94, 1.1, 0.02) * (ez > -0.2 * eh) * (ez >= lid_curve - 0.01) * (ez < lid_curve + 0.03))
    c.ink(upper, lash)
    c.ink(front * band(q, 0.96, 1.07, 0.02) * (ez <= -0.2 * eh), (0.42, 0.25, 0.22) if not mime else lash, 0.55 if not mime else 0.9)
    if e["lid"] > 0.02 and not mime:
        c.tone(front * line(ez - lid_curve - 0.045, 0.006, 0.006) * (np.abs(ex) < ew * 0.9), -0.16)  # the lid's crease
    # brows
    u = ex / 0.125
    bz = ez - (e["by"] + e["arch"] * (1 - u * u) - e["slope"] * ex)
    th = (0.031 - 0.012 * (u + 1) / 2) * (1.0 if not mime else 0.55)
    brow = front * (np.abs(u) < 1) * (1 - sstep(th - 0.006, th + 0.004, np.abs(bz))) * (1 - sstep(0.8, 1.0, np.abs(u)))
    c.ink(brow, BROW if not mime else np.array([0.05, 0.05, 0.06], dtype=F32), 0.92)
    c.ink(brow * (tx.vnoise(P * np.array([260, 60, 60], dtype=F32), 7) > 0.62), (0.3, 0.2, 0.14) if not mime else (0.1, 0.1, 0.12), 0.5)
    # mouth
    mz = z - MOUTH_Z
    lip = np.array([0.74, 0.36, 0.35], dtype=F32) if not mime else np.array([0.8, 0.08, 0.1], dtype=F32)
    if e["mouth"] == "smile":
        hw = 0.175
        curve = mz - (-0.03 + 0.075 * (x / hw) ** 2)
        c.ink(front * (ax < 0.1) * band(curve, -0.03 * (1 - (x / 0.1) ** 2), 0.0, 0.008), lip, 0.3 if not mime else 0.95)
        c.ink(front * (ax < 0.09) * band(curve, 0.0, 0.016 * (1 - (x / 0.09) ** 2), 0.005), lip * 0.9, 0.3 if not mime else 0.95)
        mouth = front * line(curve, 0.0105, 0.004) * (1 - sstep(hw - 0.02, hw, ax))
        c.ink(mouth, (0.3, 0.1, 0.1))
    elif e["mouth"] == "waver":
        hw = 0.115
        curve = mz - (0.0 - 0.034 * (x / hw) ** 2 + 0.008 * np.sin(x * 62.0))
        c.ink(front * (ax < 0.09) * band(curve, -0.032 * (1 - (x / 0.09) ** 2), 0.0, 0.006), lip, 0.45 if not mime else 0.95)
        c.ink(front * (ax < 0.08) * band(curve, 0.0, 0.018 * (1 - (x / 0.08) ** 2), 0.005), lip * 0.86, 0.4 if not mime else 0.95)
        c.ink(front * line(curve, 0.008, 0.004) * (1 - sstep(hw - 0.02, hw, ax)), (0.3, 0.1, 0.1))
    else:  # a gasp
        qm = np.sqrt((x / 0.085) ** 2 + ((mz + 0.02) / 0.095) ** 2)
        hole = front * (1 - sstep(0.9, 1.0, qm))
        c.ink(front * band(qm, 0.86, 1.2, 0.05), lip, 0.6 if not mime else 0.95)
        c.ink(hole, (0.2, 0.05, 0.07))
        c.ink(hole * sstep(-0.045, -0.075, mz + 0.02) * (ax < 0.06), (0.78, 0.36, 0.38))  # tongue
        c.ink(hole * (mz + 0.02 > 0.045) * (ax < 0.062), (0.96, 0.95, 0.92))  # upper teeth
        c.tone(front * disc(x, mz + 0.14, 0.07, 0.04), -0.1)
    if e["mouth"] != "smile":
        # worry lines between the brows
        c.tone(front * line(ax - 0.045 - 0.1 * (z - 5.06), 0.006, 0.005) * band(z, 5.0, 5.11, 0.02), -0.14)
    if mime:  # a tear under each eye and a line over it
        dz = ez + eh + 0.05
        tear = front * (np.abs(ex) < 0.026 * np.clip(1 - np.abs(dz) / 0.07, 0, 1)) * (np.abs(dz) < 0.07)
        c.ink(tear, (0.05, 0.05, 0.06))
        c.ink(front * line(ex, 0.006) * band(ez, eh + 0.035, e["by"] - 0.045, 0.004), (0.05, 0.05, 0.06))
    return c


# ---- hair and hats -----------------------------------------------------------------------------------

def hair(chart, P, N, style):
    c = Canvas(len(P), rough=0.5)
    crown = np.array([0.0, 0.05, 5.5], dtype=F32)
    if style == "parted":
        crown = np.array([-0.26, 0.0, 5.48], dtype=F32)
    d = P - crown
    if chart.endswith("_tail"):
        d = np.tile(np.array([[0.02, 0.15, -1.0]], dtype=F32), (len(P), 1))
    if chart.endswith("_bun"):
        d = np.cross(N, np.array([0.3, 0.55, 0.78], dtype=F32))
    flow = d - np.einsum("ij,ij->i", d, N)[:, None] * N
    flow = flow / np.maximum(np.linalg.norm(flow, axis=1, keepdims=True), 1e-6)
    if style == "curly":
        cells = tx.vnoise(P * 15.0, 5) * 0.6 + tx.vnoise(P * 31.0, 6) * 0.4
        c.h += 0.05 * cells
        c.tone(cells - 0.5, 0.55)
        c.h += 0.012 * tx.strands(P, flow, 0.012, 0.05, seed=4)
        return c
    fine = tx.strands(P, flow, 0.009, 0.16, seed=1)
    clump = tx.strands(P, flow, 0.035, 0.34, seed=2)
    c.tone(fine - 0.5, 0.3)
    c.tone(clump - 0.5, 0.34)
    c.h += 0.006 * fine + 0.016 * clump
    c.tone(band(P[:, 2], 5.2, 5.36, 0.07) * sstep(0.1, 0.6, N[:, 2]), 0.12)  # the sheen across the top
    if style == "balding":
        c.ink(tx.strands(P, flow, 0.014, 0.2, seed=8) > 0.42, (0.86, 0.86, 0.84), 0.5)  # grey
    if style in ("ponytail", "bun"):
        if chart.endswith("_tail"):
            tie = band(P[:, 2], 4.96, 5.05, 0.006)
            c.ink(tie, (0.75, 0.18, 0.2))
            c.lift(tie, 0.012)
        if chart.endswith("_bun"):
            c.tone(sstep(0.3, -0.2, np.einsum("ij,j->i", N, np.array([0.0, 0.55, 0.83], dtype=F32))), -0.2)
    return c


def hat(chart, P, N, name):
    c = Canvas(len(P))
    x, y, z = P[:, 0], P[:, 1], P[:, 2]
    if name == "cap":
        if chart.endswith("peak"):
            c.ink(np.ones(c.n), (0.05, 0.05, 0.06))
            c.rough[:] = 0.2
            c.ink(line(np.sqrt((x / 0.47) ** 2 + ((y + 0.72) / 0.31) ** 2) - 0.93, 0.03), (0.2, 0.2, 0.22), 0.6)
            return c
        cloth(c, P, seed=81, wrinkle=0.5)
        bandm = band(z, 5.105, 5.3, 0.004) * sstep(0.6, 0.3, np.abs(N[:, 2]))
        c.tone(bandm, -0.35)
        c.ink(bandm * line(z - 5.285, 0.006), (0.75, 0.75, 0.7), 0.7)  # piping
        front = sstep(0.3, 0.6, -N[:, 1])
        strap = front * line(z - 5.15, 0.016) * (np.abs(x) < 0.5)
        c.ink(strap, (0.05, 0.05, 0.06))
        c.gloss(strap, 0.3)
        c.ink(front * disc(np.abs(x) - 0.5, z - 5.15, 0.02), STEEL)
        bx, bz = x, z - 5.4
        sh = front * (np.abs(bx) < 0.075 * np.clip(1 - np.maximum(-bz, 0) / 0.085, 0, 1) ** 0.6) * (np.abs(bz) < 0.085)
        c.ink(sh, GOLD)
        ang = np.arctan2(bx, bz)
        c.ink(sh * (np.sqrt(bx * bx + bz * bz) < 0.045 * (0.62 + 0.38 * np.cos(5 * ang))), (0.97, 0.92, 0.7))
        c.lift(sh, 0.012)
        c.gloss(sh, 0.28)
        c.tone(sstep(0.5, 0.9, N[:, 2]) * (tx.fbm(P * 5.0, 2, 9) - 0.3), 0.1)
        c.tone(line(np.sqrt(x * x + (y + 0.01) ** 2) - 0.76, 0.006) * (z > 5.33), -0.25)  # the crown's seam
        return c
    cloth(c, P, seed=85, wrinkle=1.6, weave=0.4)  # beret: felt
    c.tone(tx.fbm(P * 30.0, 2, 3) - 0.5, 0.25)
    c.rough[:] = 0.95
    bandm = sstep(5.24, 5.2, z)
    c.tone(bandm, -0.3)
    c.gloss(bandm, 0.6)
    return c
