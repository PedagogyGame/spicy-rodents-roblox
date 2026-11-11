"""Procedural, tileable tree textures (numpy only; no bpy, no network, no paid art).

Every map is 512 px (apples 256 x 128), wraps seamlessly in u and v, and is written as an 8-bit PNG
with a tiny zlib writer (the bpy venv has no Pillow). Conventions:
  * colour maps are sRGB; normal and roughness maps are linear data (Non-Color in Blender).
  * normal maps are tangent space, OpenGL style (+Y = +v = up in the image), the convention of both
    Blender and Roblox SurfaceAppearance.
  * arrays are row-major with row 0 at the TOP of the image (PNG order); +v points to row 0.

Families
  bark:   oak, elm, sycamore, maple, willow, apple          bark_maps(family, tint, seed)
  leaves: oak, elm, sycamore (palmate), willow (lanceolate), apple    leaf_layout(shape, seed) ->
          leaf_normal_rough(layout), leaf_colour(layout, palette, layer)
  fruit:  apple_maps()

CLI preview: python -I tools/blender/trees/textures.py --out build/art/trees/tex_preview
"""
import math
import os
import struct
import zlib

import numpy as np

N = 512


# ---- PNG ----------------------------------------------------------------------------------------

def write_png(path, arr):
    """arr: HxW (grey) or HxWx3/4 float in [0, 1] or uint8, row 0 = top."""
    a = np.asarray(arr)
    if a.dtype != np.uint8:
        a = (np.clip(a, 0.0, 1.0) * 255.0 + 0.5).astype(np.uint8)
    if a.ndim == 2:
        a = a[:, :, None]
    h, w, c = a.shape
    ctype = {1: 0, 3: 2, 4: 6}[c]
    raw = b"".join(b"\x00" + a[y].tobytes() for y in range(h))

    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)

    png = b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, ctype, 0, 0, 0))
    png += chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b"")
    os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
    with open(path, "wb") as fh:
        fh.write(png)
    return path


# ---- colour helpers -----------------------------------------------------------------------------

def hex_rgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i : i + 2], 16) / 255.0 for i in (0, 2, 4)])


def srgb_to_lin(c):
    c = np.asarray(c, dtype=float)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(np.asarray(c, dtype=float), 0.0, 1.0)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * c ** (1 / 2.4) - 0.055)


def mix(a, b, t):
    t = np.asarray(t)[..., None] if np.ndim(t) else t
    return a * (1 - t) + b * t


def smoothstep(e0, e1, x):
    t = np.clip((x - e0) / (e1 - e0), 0.0, 1.0)
    return t * t * (3 - 2 * t)


# ---- periodic noise -----------------------------------------------------------------------------

def _grid_uv(n=N):
    v, u = np.mgrid[0:n, 0:n].astype(np.float64)
    return (u + 0.5) / n, 1.0 - (v + 0.5) / n  # u right, v up (row 0 = top)


def sample_grid(grid, x, y):
    """Value-noise lookup with wrap; x, y in lattice units (any float)."""
    gy, gx = grid.shape
    x0 = np.floor(x)
    y0 = np.floor(y)
    fx = x - x0
    fy = y - y0
    x0 = x0.astype(np.int64) % gx
    y0 = y0.astype(np.int64) % gy
    x1 = (x0 + 1) % gx
    y1 = (y0 + 1) % gy
    sx = fx * fx * fx * (fx * (fx * 6 - 15) + 10)
    sy = fy * fy * fy * (fy * (fy * 6 - 15) + 10)
    a = grid[y0, x0] * (1 - sx) + grid[y0, x1] * sx
    b = grid[y1, x0] * (1 - sx) + grid[y1, x1] * sx
    return a * (1 - sy) + b * sy


def fbm(u, v, fx, fy, octaves, rng, gain=0.5, lac=2):
    """Tileable fBm in [0, 1] (approximately); u, v in [0, 1) texture units, integer base freqs."""
    total = np.zeros_like(u)
    amp, norm = 1.0, 0.0
    for o in range(octaves):
        gx, gy = int(fx * lac ** o), int(fy * lac ** o)
        grid = rng.random((max(gy, 1), max(gx, 1)))
        total += amp * sample_grid(grid, u * gx, v * gy)
        norm += amp
        amp *= gain
    return total / norm


def worley(u, v, nx, ny, rng, jitter=0.85):
    """Tileable cellular noise: F1, F2 (in units of a cell) and the F1 cell's random value."""
    px = rng.random((ny, nx)) * jitter + (1 - jitter) / 2
    py = rng.random((ny, nx)) * jitter + (1 - jitter) / 2
    pv = rng.random((ny, nx))
    x = u * nx
    y = v * ny
    cx = np.floor(x).astype(np.int64)
    cy = np.floor(y).astype(np.int64)
    f1 = np.full(u.shape, 9.0)
    f2 = np.full(u.shape, 9.0)
    idv = np.zeros(u.shape)
    for oy in (-1, 0, 1):
        for ox in (-1, 0, 1):
            ix = cx + ox
            iy = cy + oy
            wx = ix % nx
            wy = iy % ny
            dx = ix + px[wy, wx] - x
            dy = iy + py[wy, wx] - y
            d = np.sqrt(dx * dx + dy * dy)
            closer = d < f1
            f2 = np.where(closer, f1, np.minimum(f2, d))
            idv = np.where(closer, pv[wy, wx], idv)
            f1 = np.where(closer, d, f1)
    return f1, f2, idv


def blur(a, sigma):
    """Periodic Gaussian blur (FFT)."""
    h, w = a.shape
    ky = np.fft.fftfreq(h)[:, None]
    kx = np.fft.fftfreq(w)[None, :]
    g = np.exp(-2 * (math.pi ** 2) * (sigma ** 2) * (kx * kx + ky * ky))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * g))


def height_to_normal(h, strength):
    """Tangent-space normal (OpenGL, +v up) from a height map in [0,1] (row 0 = top)."""
    dhdu = (np.roll(h, -1, axis=1) - np.roll(h, 1, axis=1)) * 0.5
    dhdv = (np.roll(h, 1, axis=0) - np.roll(h, -1, axis=0)) * 0.5  # row-1 is +v
    nx = -dhdu * strength
    ny = -dhdv * strength
    nz = np.ones_like(h)
    l = np.sqrt(nx * nx + ny * ny + nz * nz)
    return np.stack([nx / l * 0.5 + 0.5, ny / l * 0.5 + 0.5, nz / l * 0.5 + 0.5], axis=-1)


# ---- bark ---------------------------------------------------------------------------------------

BARK_FAMILIES = ("oak", "elm", "sycamore", "maple", "willow", "apple")

# base (furrow, ridge, highlight) colours, sRGB hex: v5.4 M.bark #736354 x tint #b6a99b, sycamore
# #a3a089 / #a5a394 / #a3a48f, apple wood #766047, estate oak #716050.
BARK_COLOURS = {
    "oak": ("#231c16", "#56483b", "#7e705f"),
    "elm": ("#241d18", "#574739", "#7c6c5a"),
    "sycamore": ("#6f6a55", "#a3a089", "#e4dfcc"),
    "maple": ("#2f2924", "#6a5f54", "#968b7c"),
    "willow": ("#241f1b", "#5a4e42", "#837868"),
    "apple": ("#2b231c", "#64533f", "#8a775f"),
}


def bark_maps(family, seed=1, tint=None):
    """Returns (colour sRGB HxWx3, normal HxWx3, roughness HxW). tint: optional hex multiplied in."""
    rng = np.random.default_rng(seed)
    u, v = _grid_uv()
    dark, mid, light = (srgb_to_lin(hex_rgb(c)) for c in BARK_COLOURS[family])
    lichen = srgb_to_lin(hex_rgb("#8d9a6c"))
    moss = srgb_to_lin(hex_rgb("#55663a"))
    if family in ("oak", "elm", "willow", "maple", "apple"):
        warp = fbm(u, v, 3, 2, 4, rng)
        warp2 = fbm(u, v, 2, 3, 3, rng)
        fx = {"oak": 9, "elm": 11, "willow": 8, "maple": 13, "apple": 12}[family]
        fy = {"oak": 2, "elm": 3, "willow": 1, "maple": 2, "apple": 3}[family]
        wu = u + (warp - 0.5) * (0.10 if family == "elm" else 0.06) + np.sin(v * 2 * math.pi * fy * 2) * (0.015 if family == "elm" else 0.0)
        n1 = fbm(wu, v + (warp2 - 0.5) * 0.08, fx, fy, 5, rng, gain=0.55)
        ridge = 1.0 - np.abs(2 * n1 - 1)
        ridge = ridge ** (1.6 if family in ("oak", "willow") else 1.2)
        # horizontal cracks break ridges into long plates
        f1, f2, cid = worley(wu % 1.0, v, max(3, fx // 2), max(2, fy + 1), rng, jitter=0.9)
        crack = 0.6 + 0.4 * smoothstep(0.0, 0.05, f2 - f1)
        depth = {"oak": 1.0, "elm": 0.85, "willow": 1.0, "maple": 0.55, "apple": 0.8}[family]
        h = ridge * (0.65 + 0.35 * crack) * depth + fbm(u, v, 32, 32, 3, rng) * 0.18
        h = (h - h.min()) / (h.max() - h.min())
        t = smoothstep(0.15, 0.85, h)
        col = mix(mix(dark, mid, smoothstep(0.0, 0.55, h)), light, smoothstep(0.55, 1.0, h) * 0.8)
        col = col * (0.88 + 0.24 * fbm(u, v, 4, 4, 4, rng))[..., None]
        lich = smoothstep(0.68, 0.82, fbm(u, v, 5, 5, 5, rng)) * smoothstep(0.45, 0.8, h)
        col = mix(col, lichen, lich * (0.22 if family != "maple" else 0.12))
        mossm = smoothstep(0.72, 0.86, fbm(u, v, 3, 4, 4, rng)) * (1 - smoothstep(0.1, 0.5, h))
        col = mix(col, moss, mossm * 0.3)
        rough = 0.97 - 0.18 * t
        nstr = {"oak": 7.0, "elm": 6.0, "willow": 7.5, "maple": 4.0, "apple": 5.5}[family]
    elif family == "sycamore":
        # smooth pale bark shedding in rounded, irregular patches (cream, olive, grey-brown)
        wu = u + (fbm(u, v, 4, 4, 4, rng) - 0.5) * 0.16
        wv = v + (fbm(u, v, 4, 4, 4, rng) - 0.5) * 0.16
        f1, f2, cid = worley(wu % 1.0, wv % 1.0, 4, 5, rng, jitter=0.95)
        g1, g2, gid = worley((wu + 0.31) % 1.0, (wv + 0.17) % 1.0, 7, 9, rng, jitter=0.95)
        edge = smoothstep(0.0, 0.12, f2 - f1)
        edge2 = smoothstep(0.0, 0.10, g2 - g1)
        pal = np.stack([srgb_to_lin(hex_rgb(c)) for c in ("#ddd8c4", "#c9c7ad", "#a8a68a", "#8f8a6e", "#b3ae92", "#7f8463")])
        pid = np.minimum((cid * len(pal)).astype(int), len(pal) - 1)
        sid = np.minimum((gid * len(pal)).astype(int), len(pal) - 1)
        col = pal[pid]
        top = gid > 0.6
        col = np.where(top[..., None], mix(col, pal[sid], 0.9 * edge2), col)
        col = col * (0.9 + 0.2 * fbm(u, v, 10, 10, 4, rng))[..., None]
        col = mix(col, srgb_to_lin(hex_rgb("#6b6550")), (1 - edge) * 0.35)
        h = 0.5 + 0.2 * edge + 0.2 * top * edge2 + 0.1 * fbm(u, v, 24, 24, 3, rng)
        h = (h - h.min()) / (h.max() - h.min())
        rough = 0.8 - 0.12 * edge
        nstr = 3.0
    else:  # apple: scaly, vertically elongated flakes
        wu = u + (fbm(u, v, 4, 4, 4, rng) - 0.5) * 0.08
        f1, f2, cid = worley(wu % 1.0, v, 8, 5, rng, jitter=0.95)
        edge = smoothstep(0.0, 0.10, f2 - f1)
        curl = smoothstep(0.05, 0.7, f1)
        ridge = 1.0 - np.abs(2 * fbm(wu % 1.0, v, 10, 2, 4, rng) - 1)
        h = 0.35 * edge + 0.25 * curl + 0.3 * ridge + 0.1 * fbm(u, v, 16, 16, 3, rng)
        h = (h - h.min()) / (h.max() - h.min())
        col = mix(dark, mid, smoothstep(0.1, 0.6, h))
        col = mix(col, light, smoothstep(0.7, 1.0, h) * 0.6)
        col = col * (0.88 + 0.24 * cid)[..., None]
        lich = smoothstep(0.66, 0.8, fbm(u, v, 5, 5, 5, rng))
        col = mix(col, lichen, lich * 0.4)
        rough = 0.95 - 0.12 * edge
        nstr = 5.0
    if tint is not None:
        tl = srgb_to_lin(hex_rgb(tint))
        col = col * (tl / max(1e-6, tl.mean()))[None, None, :] ** 0.35
    normal = height_to_normal(h, nstr)
    return lin_to_srgb(col), normal, np.clip(rough, 0.0, 1.0)


# ---- leaves -------------------------------------------------------------------------------------

LEAF_SHAPES = ("oak", "elm", "palmate", "willow", "apple")


def _leaf_width(shape, s, rng_lobes):
    """Half-width profile (0..1) along the leaf axis s in [0, 1] (0 = stalk, 1 = tip)."""
    base = np.sin(np.clip(s, 0, 1) * math.pi)
    if shape == "oak":
        lobes = 1.0 + 0.38 * np.abs(np.sin(s * math.pi * (3.5 + rng_lobes)))
        return base ** 0.75 * lobes * (0.75 + 0.25 * s)
    if shape == "elm":
        return base ** 0.65 * (1 + 0.06 * np.sin(s * 70)) * (0.85 + 0.25 * s * (1 - s) * 2)
    if shape == "willow":
        return base ** 1.1
    if shape == "apple":
        return base ** 0.6 * (0.9 + 0.1 * np.sin(s * 50))
    return base


def leaf_layout(shape, seed=1, n=N):
    """Stamp a pile of leaves (painter's order) that wraps in u and v. Returns a dict of maps."""
    rng = np.random.default_rng(seed)
    H = np.full((n, n), -0.25)
    ID = np.full((n, n), -1, dtype=np.int32)
    S = np.zeros((n, n))
    T = np.zeros((n, n))
    params = {
        #           length px, width ratio, count, angle mode
        "oak": (74, 0.42, 620, "any"),
        "elm": (62, 0.36, 760, "any"),
        "palmate": (72, 1.0, 560, "any"),
        "willow": (96, 0.14, 1300, "down"),
        "apple": (58, 0.40, 820, "any"),
    }[shape]
    L0, wr, count, mode = params
    leaves = []
    for i in range(count):
        cx, cy = rng.random() * n, rng.random() * n
        if mode == "down":
            ang = -math.pi / 2 + rng.normal(0, 0.28)
        else:
            ang = rng.random() * 2 * math.pi
        L = L0 * (0.7 + 0.6 * rng.random())
        W = L * wr * (0.85 + 0.3 * rng.random())
        tilt = rng.normal(0, 0.25)
        lob = rng.random()
        z0 = i / count
        leaves.append((cx, cy, ang, L, W, tilt, z0))
        hb = int(math.ceil(max(L, W) * 0.6 + 2))
        oy, ox = np.mgrid[-hb : hb + 1, -hb : hb + 1].astype(np.float64)
        ca, sa = math.cos(ang), math.sin(ang)
        # image rows grow downward: use (dx, -dy) as the math frame
        al = ox * ca + (-oy) * sa
        ac = -ox * sa + (-oy) * ca
        if shape == "palmate":
            # 5-lobed star around the leaf centre; s = radius fraction, t = angle within lobe
            rad = np.sqrt(al * al + ac * ac)
            th = np.arctan2(ac, al)
            lobe = 0.55 + 0.45 * np.abs(np.cos(2.5 * (th - 0.0))) ** 0.7
            notch = np.cos(th + math.pi) > 0.92  # the stalk gap
            R = L * 0.5 * lobe
            inside = (rad <= R) & ~(notch & (rad > R * 0.25))
            s = np.clip(rad / np.maximum(R, 1e-6), 0, 1)
            tn = np.sin(5 * th) * 0.9
            dome = np.sqrt(np.clip(1 - s * s, 0, 1))
            veins = 0.10 * np.exp(-((np.sin(2.5 * th) * rad / 3.0) ** 2))
            prof = 0.32 * dome + veins + tilt * (al / L)
            s_out = s
        else:
            s = al / L + 0.5
            w = _leaf_width(shape, s, lob) * W
            inside = (s >= 0) & (s <= 1) & (np.abs(ac) <= w)
            tn = ac / np.maximum(w, 1e-6)
            dome = np.sqrt(np.clip(1 - tn * tn, 0, 1))
            midrib = -0.10 * np.exp(-(tn / 0.09) ** 2)
            veins = 0.035 * np.cos((s * 9 - np.abs(tn) * 2.2) * 2 * math.pi) * dome
            prof = 0.32 * dome + midrib + veins + tilt * (s - 0.5)
            s_out = s
        yy = (np.floor(cy).astype(int) + oy.astype(int)) % n
        xx = (np.floor(cx).astype(int) + ox.astype(int)) % n
        hval = z0 + prof * 0.35
        m = inside
        H[yy[m], xx[m]] = hval[m]
        ID[yy[m], xx[m]] = i
        S[yy[m], xx[m]] = s_out[m]
        T[yy[m], xx[m]] = tn[m]
    lv = np.array(leaves)
    return {"shape": shape, "H": H, "ID": ID, "S": S, "T": T, "leaves": lv, "seed": seed,
            "tone": rng.random(count), "bright": rng.random(count)}


def leaf_normal_rough(layout, strength=42.0):
    H, ID, S, T = layout["H"], layout["ID"], layout["S"], layout["T"]
    gap = ID < 0
    # Detail height: each leaf's own relief plus a small step per stacking order, so edges read.
    z0 = np.where(gap, -0.15, layout["leaves"][np.maximum(ID, 0), 6])
    prof = H - z0  # leaf relief only
    hd = prof * 1.0 + z0 * 0.06 + np.where(gap, -0.05, 0.0)
    hd = blur(hd, 0.7)
    normal = height_to_normal(hd, strength)
    occl = H - blur(H, 9.0)
    rough = np.where(gap, 0.95, 0.78 - 0.10 * np.clip(occl * 3 + 0.5, 0, 1) + 0.06 * (layout["bright"][np.maximum(ID, 0)] - 0.5))
    return normal, np.clip(rough, 0, 1)


def leaf_colour(layout, palette, layer="sun", seed=3):
    """palette: list of sRGB hex greens (the tree's v5.4 colours). layer: 'sun' | 'shade' | 'willow'.
    Returns sRGB HxWx3."""
    rng = np.random.default_rng(seed)
    H, ID, S, T = layout["H"], layout["ID"], layout["S"], layout["T"]
    gap = ID < 0
    pal = np.stack([srgb_to_lin(hex_rgb(c)) for c in palette])
    k = len(pal)
    idx = np.maximum(ID, 0)
    tone = np.minimum((layout["tone"] * k).astype(int), k - 1)[idx]
    bright = layout["bright"][idx]
    col = pal[tone]
    lum = 0.88 + 0.22 * bright
    if layer == "sun":
        warm = np.array([1.16, 1.08, 0.70])
        col = col * warm * 1.04
    elif layer == "shade":
        cool = np.array([0.86, 0.95, 1.02])
        col = col * cool * 0.80
    else:  # mid
        col = col * np.array([1.0, 1.0, 0.92]) * 0.95
    col = col * lum[..., None]
    # within a leaf: lighter midrib and veins, darker toward the stalk and the edges
    shape = layout["shape"]
    rib = np.exp(-(T / 0.10) ** 2) * (shape != "palmate")
    edge = smoothstep(0.55, 1.0, np.abs(T))
    col = col * (1.0 + 0.16 * rib[..., None]) * (1.0 - 0.18 * edge[..., None]) * (0.86 + 0.18 * np.clip(S, 0, 1))[..., None]
    # occlusion: leaves deeper in the pile are darker
    occl = H - blur(H, 10.0)
    ao = np.clip(0.80 + occl * 1.1, 0.58, 1.06)
    col = col * ao[..., None]
    u, v = _grid_uv(H.shape[0])
    big = fbm(u, v, 3, 3, 3, rng)
    col = col * (0.90 + 0.20 * big)[..., None]
    if layer == "sun":
        yellow = srgb_to_lin(hex_rgb("#c9cf6a"))
        col = mix(col, yellow * lum[..., None], smoothstep(0.62, 0.9, big) * 0.22 * (1 - gap))
    deep = pal.min(axis=0) * (0.38 if layer == "shade" else 0.5)
    col = np.where(gap[..., None], deep, col)
    return lin_to_srgb(col)


# ---- leaf sprays (alpha cards) --------------------------------------------------------------------

SPRAY_SHAPES = ("oak", "elm", "palmate", "maple", "willow", "apple")
SPRAY_N = 1024

# leaf length px, width / length, leaves on the main twig, side twigs, leaves per side twig, angle off the twig
SPRAY_PLAN = {
    "oak": dict(L=140, wr=0.50, main=9, twigs=4, per=4, ang=(48, 72), petiole=10, step=46),
    "elm": dict(L=112, wr=0.48, main=11, twigs=4, per=5, ang=(52, 70), petiole=6, step=38),
    "palmate": dict(L=112, wr=1.0, main=7, twigs=4, per=3, ang=(40, 75), petiole=30, step=54),
    "maple": dict(L=100, wr=1.0, main=8, twigs=4, per=4, ang=(40, 70), petiole=26, step=46),
    "apple": dict(L=112, wr=0.56, main=9, twigs=4, per=4, ang=(40, 70), petiole=12, step=44),
    "willow": dict(L=116, wr=0.16, main=30, twigs=1, per=14, ang=(16, 30), petiole=4, step=24),
}


def _leaf_half_width(shape, s, k):
    """Half width (fraction of the leaf's width) along the midrib s in [0, 1]; k varies the lobes."""
    s = np.clip(s, 0.0, 1.0)
    if shape == "oak":
        env = np.sin(math.pi * s ** 0.85) ** 0.7 * (0.72 + 0.34 * s)
        lobes = np.abs(np.sin(math.pi * (3.4 + 0.5 * k) * s + 0.4 + k)) ** 0.75
        return env * (0.50 + 0.50 * lobes)
    if shape == "elm":
        saw = 1.0 - 0.10 * ((s * 13.0 + k) % 1.0)
        return np.sin(math.pi * s ** 0.72) ** 0.72 * saw * (1 - s ** 7)
    if shape == "apple":
        return np.sin(math.pi * s ** 0.8) ** 0.62 * (1 - s ** 9) * (0.96 + 0.04 * np.sin(s * 60 + k))
    if shape == "willow":
        return np.sin(math.pi * s ** 0.8) ** 1.05
    return np.sin(math.pi * s)


# palmate leaves: lobes as (angle from the midrib, reach, angular half width), and the body's reach
PALM_LOBES = {
    "maple": (((0.0, 1.00, 0.30), (0.98, 0.86, 0.28), (-0.98, 0.86, 0.28), (1.95, 0.52, 0.27), (-1.95, 0.52, 0.27)), 0.40),
    "palmate": (((0.0, 0.96, 0.40), (0.95, 0.88, 0.38), (-0.95, 0.88, 0.38), (1.85, 0.62, 0.34), (-1.85, 0.62, 0.34)), 0.56),
}


def _palmate_radius(shape, th, k):
    """Outline radius (fraction of the leaf's reach) at angle th from the midrib: a body with five
    lobes, the maple's pointed, the sycamore's broad."""
    lobes, body = PALM_LOBES[shape]
    th = np.angle(np.exp(1j * th))
    r = np.full_like(th, body)
    for t0, a, sg in lobes:
        r = r + (a - body) * np.exp(-((th - t0) / sg) ** 2)
    teeth = 1.0 - (0.06 if shape == "maple" else 0.045) * np.abs(np.sin(15.0 * th + k))
    return r * teeth


class _Canvas:
    """The layers a spray is painted into (math frame: x right, y up; row = n - 1 - y)."""

    def __init__(self, n):
        self.n = n
        self.A = np.zeros((n, n))  # coverage
        self.ID = np.full((n, n), -1, dtype=np.int32)  # leaf index, -2 = twig
        self.S = np.zeros((n, n))
        self.T = np.zeros((n, n))
        self.Hh = np.zeros((n, n))  # relief for the normal map
        self.AO = np.ones((n, n))
        self.leaves = []

    def window(self, cx, cy, hb, box):
        x0, x1 = int(max(box[0], math.floor(cx - hb))), int(min(box[2], math.ceil(cx + hb)))
        y0, y1 = int(max(box[1], math.floor(cy - hb))), int(min(box[3], math.ceil(cy + hb)))
        if x1 <= x0 or y1 <= y0:
            return None
        ys, xs = np.mgrid[y0:y1, x0:x1].astype(np.float64)
        rows = slice(self.n - y1, self.n - y0)
        return xs + 0.5, ys[::-1] + 0.5, rows, slice(x0, x1)

    def stroke(self, pts, w0, w1, box):
        """A twig: a polyline with a width tapering from w0 to w1 px."""
        pts = np.asarray(pts, float)
        seg = np.linalg.norm(np.diff(pts, axis=0), axis=1)
        tot = max(seg.sum(), 1e-6)
        acc = 0.0
        for a, b, l in zip(pts[:-1], pts[1:], seg):
            wa, wb = w0 + (w1 - w0) * acc / tot, w0 + (w1 - w0) * (acc + l) / tot
            acc += l
            c = (a + b) / 2
            win = self.window(c[0], c[1], l / 2 + max(wa, wb) + 2, box)
            if win is None:
                continue
            X, Yv, rows, cols = win
            ab = b - a
            t = np.clip(((X - a[0]) * ab[0] + (Yv - a[1]) * ab[1]) / max(l * l, 1e-9), 0, 1)
            d = np.hypot(X - (a[0] + t * ab[0]), Yv - (a[1] + t * ab[1]))
            w = (wa + (wb - wa) * t) / 2
            cov = np.clip(w - d + 0.5, 0, 1)
            m = cov > 0.5
            self.A[rows, cols] = np.maximum(cov, self.A[rows, cols])
            self.ID[rows, cols] = np.where(m, -2, self.ID[rows, cols])
            self.T[rows, cols] = np.where(m, d / np.maximum(w, 1e-6), self.T[rows, cols])
            self.Hh[rows, cols] = np.where(m, 0.10 * np.sqrt(np.clip(1 - (d / np.maximum(w, 1e-6)) ** 2, 0, 1)), self.Hh[rows, cols])

    def leaf(self, shape, bx, by, ang, L, W, box, rng, zbias=0.0):
        """One leaf with its stalk end at (bx, by), pointing along ang. Returns False if it leaves the box."""
        ca, sa = math.cos(ang), math.sin(ang)
        palm = shape in ("palmate", "maple")
        if palm:
            cx, cy, hb = bx + ca * L * 0.40, by + sa * L * 0.40, L * 0.66 + 2
        else:
            cx, cy, hb = bx + ca * L * 0.5, by + sa * L * 0.5, L * 0.5 + W * 0.5 + 2
        ext = L * 0.64 if palm else max(abs(ca) * L * 0.5 + abs(sa) * W * 0.6, abs(sa) * L * 0.5 + abs(ca) * W * 0.6) + 1
        if cx - ext < box[0] + 3 or cx + ext > box[2] - 3 or cy - ext < box[1] + 3 or cy + ext > box[3] - 3:
            return False
        X, Yv, rows, cols = self.window(cx, cy, hb, box)
        dx, dy = X - bx, Yv - by
        al = dx * ca + dy * sa
        ac = -dx * sa + dy * ca
        k = rng.random() * 6.28
        curl = rng.normal(0, 0.10)
        if palm:
            # the lobes fan out from where the stalk meets the blade, a third of the way up the leaf
            px, py = al - L * 0.30, ac
            rad = np.hypot(px, py)
            th = np.arctan2(py, px)
            R = L * 0.70 * _palmate_radius(shape, th, k)
            notch = (np.cos(th - math.pi) > 0.93) & (rad > R * 0.3)
            margin = np.where(notch, -3.0, R - rad)
            s = np.clip(rad / np.maximum(R, 1e-6), 0, 1)
            tn = np.sin(2.5 * th)
            dome = np.sqrt(np.clip(1 - s * s, 0, 1))
            vein = np.zeros_like(rad)
            for t0, a_, sg in PALM_LOBES[shape][0]:
                dth = np.angle(np.exp(1j * (th - t0)))
                vein = np.maximum(vein, np.exp(-((np.sin(dth) * rad / 2.4) ** 2)) * (np.cos(dth) > 0) * (rad < L * 0.70 * a_ * 0.92))
            relief = 0.30 * dome - 0.10 * vein + curl * (px / L)
            rib = vein
        else:
            s = al / L
            ac2 = ac - curl * L * (s - 0.5) ** 2 * 1.5
            w = _leaf_half_width(shape, s, k) * W * 0.5
            margin = np.minimum(w - np.abs(ac2), np.minimum(al, L - al) + 0.5)
            tn = ac2 / np.maximum(w, 1e-6)
            dome = np.sqrt(np.clip(1 - tn * tn, 0, 1))
            rib = np.exp(-(ac2 / max(1.6, W * 0.035)) ** 2)
            veins = 0.5 + 0.5 * np.cos((s * (7 if shape != "willow" else 0) - np.abs(tn) * 1.9) * 2 * math.pi)
            relief = 0.30 * dome - 0.10 * rib + 0.035 * veins * dome + curl * (s - 0.5)
        cov = np.clip(margin + 0.5, 0, 1)
        lid = len(self.leaves)
        # the leaf shades what lies under its edge
        sh = np.clip((margin + 7.0) / 7.0, 0, 1) * 0.34
        self.AO[rows, cols] = np.minimum(self.AO[rows, cols], 1 - sh * (cov < 0.5))
        m = cov > 0
        self.A[rows, cols] = np.where(m, np.maximum(cov, self.A[rows, cols]), self.A[rows, cols])
        full = cov > 0.5
        self.ID[rows, cols] = np.where(full, lid, self.ID[rows, cols])
        self.S[rows, cols] = np.where(full, np.clip(s, 0, 1), self.S[rows, cols])
        self.T[rows, cols] = np.where(full, tn, self.T[rows, cols])
        self.Hh[rows, cols] = np.where(full, relief + zbias, self.Hh[rows, cols])
        self.AO[rows, cols] = np.where(full, np.maximum(self.AO[rows, cols], 1.0 - 0.10 * (1 - np.clip(margin / 6.0, 0, 1))), self.AO[rows, cols])
        if palm:
            self.S[rows, cols] = np.where(full, 1 - rib * 0.999, self.S[rows, cols])  # veins ride in S for palmate leaves
        self.leaves.append((rng.random(), rng.random(), rng.random()))
        return True


def _twig_leaves(cv, shape, plan, rng, box, start, heading, length, n, w0, scale=1.0, terminal=True):
    """A twig from `start` along `heading` (radians) with n alternate leaves; returns its points."""
    pts = [np.array(start, float)]
    h = heading
    seg = length / max(n, 1)
    bend = rng.normal(0, 0.05)
    side = 1 if rng.random() < 0.5 else -1
    spots = []
    h0 = heading
    for i in range(n):
        h += bend + rng.normal(0, 0.05) - 0.10 * side * (shape in ("elm",))
        if shape == "willow":
            h = h0 + (h - h0) * 0.55  # a hanging strand sways but keeps falling
        p = pts[-1] + np.array([math.cos(h), math.sin(h)]) * seg
        pts.append(p)
        spots.append((p, h, side))
        side = -side
    cv.stroke(pts, w0, max(1.6, w0 * 0.4), box)
    L0 = plan["L"] * scale
    order = list(range(n))
    for i in order:
        p, h, sd = spots[i]
        a = h + sd * math.radians(rng.uniform(*plan["ang"]))
        L = L0 * rng.uniform(0.78, 1.12) * (0.82 + 0.18 * i / max(n - 1, 1))
        W = L * plan["wr"] * rng.uniform(0.9, 1.1)
        pe = plan["petiole"] * scale * rng.uniform(0.8, 1.3)
        b = p + np.array([math.cos(a), math.sin(a)]) * pe
        for shrink in (1.0, 0.8, 0.62):
            if cv.leaf(shape, b[0], b[1], a + rng.normal(0, 0.08), L * shrink, W * shrink, box, rng, zbias=0.02 * i):
                cv.stroke([p, b], 2.6, 2.0, box)
                break
    if terminal:
        p, h, _ = spots[-1]
        for da in ((0.0,) if shape == "willow" else (0.0, 0.55, -0.55)):
            L = L0 * rng.uniform(0.85, 1.1)
            b = p + np.array([math.cos(h + da), math.sin(h + da)]) * plan["petiole"] * 0.6 * scale
            for shrink in (1.0, 0.8, 0.62):
                if cv.leaf(shape, b[0], b[1], h + da, L * shrink, L * plan["wr"] * shrink, box, rng, zbias=0.3):
                    break
    return pts


def spray_layout(shape, seed=1, n=SPRAY_N):
    """Paint the four sprays of a species into an atlas. Broad leaves: 2 x 2 cells, each a twig rising
    from the middle of the cell's lower edge. Willow: 4 columns, each a strand hanging from the top."""
    rng = np.random.default_rng(seed)
    cv = _Canvas(n)
    plan = SPRAY_PLAN[shape]
    if shape == "willow":
        cw = n // 4
        for c in range(4):
            box = (c * cw, 0, (c + 1) * cw, n)
            x0 = c * cw + cw * rng.uniform(0.45, 0.55)
            # the strands hang: build them top-down, a long one between two shorter ones
            for k, off in enumerate((0.0, -0.2, 0.2)):
                xs = x0 + off * cw * rng.uniform(0.8, 1.1)
                length = n * (0.95 if k == 0 else rng.uniform(0.55, 0.85)) - 24
                _twig_leaves(cv, shape, plan, rng, box, (xs, n - 4), -math.pi / 2 + rng.normal(0, 0.02), length,
                             int(length / plan["step"]), 4.5 if k == 0 else 3.2)
        return _finish_layout(cv, shape, seed)
    ch = n // 2
    for c in range(4):
        box = ((c % 2) * ch, (c // 2) * ch, (c % 2) * ch + ch, (c // 2) * ch + ch)
        bx, by = box[0] + ch * 0.5, box[1] + 5
        lean = rng.normal(0, 0.10)
        nmain = plan["main"]
        length = min(ch * 0.68, nmain * plan["step"])
        heading = math.pi / 2 + lean
        # side twigs first (they lie under the main twig's leaves): alternate sides, shorter up the twig
        for t in range(plan["twigs"]):
            f = (0.10 + 0.17 * t) + rng.uniform(-0.03, 0.03)
            sd = 1 if (t + c) % 2 == 0 else -1
            st = np.array([bx, by]) + np.array([math.cos(heading), math.sin(heading)]) * length * f
            hd = heading - sd * math.radians(rng.uniform(50, 68) - 6 * t)
            _twig_leaves(cv, shape, plan, rng, box, st, hd, ch * rng.uniform(0.30, 0.37) * (1 - 0.1 * t), plan["per"], 4.0, scale=0.92)
        _twig_leaves(cv, shape, plan, rng, box, (bx, by), heading, length, nmain, 6.5)
    return _finish_layout(cv, shape, seed)


def _finish_layout(cv, shape, seed):
    lv = np.array(cv.leaves) if cv.leaves else np.zeros((1, 3))
    return {"shape": shape, "A": cv.A, "ID": cv.ID, "S": cv.S, "T": cv.T, "H": cv.Hh, "AO": cv.AO, "leaves": lv, "seed": seed}


def spray_normal_rough(layout, strength=30.0):
    ID, H = layout["ID"], layout["H"]
    hd = blur(np.where(ID == -1, 0.0, H + 0.05), 0.8)
    normal = height_to_normal(hd, strength)
    bright = layout["leaves"][np.maximum(ID, 0), 1]
    rough = np.where(ID >= 0, 0.66 - 0.10 * bright + 0.10 * np.clip(np.abs(layout["T"]), 0, 1) ** 2, 0.86)
    rough = np.where(ID == -1, 0.75, rough)
    return normal, np.clip(rough, 0, 1)


def spray_colour(layout, palette, layer="sun", seed=3):
    """RGBA (sRGB, straight alpha) for one light layer of a tree's palette. The colour is carried past
    the leaf edges so that mip levels do not pick up a dark fringe."""
    rng = np.random.default_rng(seed)
    A, ID, S, T, AO = layout["A"], layout["ID"], layout["S"], layout["T"], layout["AO"]
    shape = layout["shape"]
    n = A.shape[0]
    pal = np.stack([srgb_to_lin(hex_rgb(c)) for c in palette])
    k = len(pal)
    lv = layout["leaves"]
    idx = np.maximum(ID, 0)
    tone = np.minimum((lv[:, 0] * k).astype(int), k - 1)[idx]
    bright = lv[:, 1][idx]
    hue = lv[:, 2][idx]
    col = pal[tone]
    if layer == "sun":
        col = col * np.array([1.13, 1.10, 0.80]) * 1.07
    elif layer == "shade":
        col = col * np.array([0.88, 0.98, 0.98]) * 0.86
    else:
        col = col * np.array([1.03, 1.04, 0.90]) * 1.0
    col = col * (0.84 + 0.30 * bright)[..., None]
    # a few leaves turn toward yellow, a few toward blue-green
    yellow = srgb_to_lin(hex_rgb("#c3c860"))
    col = mix(col, yellow * (0.8 + 0.3 * bright)[..., None], np.clip((hue - 0.80) * 2.2, 0, 0.42) * (0.6 if layer == "shade" else 1.0))
    col = col * np.where((hue < 0.14)[..., None], np.array([0.90, 0.99, 1.04]), np.ones(3))
    if shape in ("palmate", "maple"):
        rib = 1 - S  # palmate leaves carry their veins in S
        col = col * (1.0 + 0.22 * rib[..., None]) * 0.97
    else:
        rib = np.exp(-(T / 0.085) ** 2)
        vein = 0.5 + 0.5 * np.cos((S * 7 - np.abs(T) * 1.9) * 2 * math.pi) if shape != "willow" else np.zeros_like(S)
        edge = smoothstep(0.6, 1.0, np.abs(T))
        col = col * (1.0 + 0.20 * rib[..., None] + 0.05 * (vein * (1 - rib))[..., None])
        col = col * (1.0 - 0.14 * edge[..., None]) * (0.84 + 0.22 * np.clip(S, 0, 1))[..., None]
    u, v = _grid_uv(n)
    col = col * (0.93 + 0.14 * fbm(u, v, 4, 4, 3, rng))[..., None]
    col = col * AO[..., None]
    twig = srgb_to_lin(hex_rgb("#5d4a34")) * (0.8 + 0.5 * np.clip(1 - np.abs(T), 0, 1))[..., None] * (0.8 if layer == "shade" else 1.0)
    col = np.where((ID == -2)[..., None], twig, col)
    # carry colour outward from the leaves (two blur scales), so transparent texels are leaf-coloured
    inside = (ID != -1) & (A > 0.5)
    w = inside.astype(float)
    out = col.copy()
    for sigma in (3.0, 12.0, 40.0):
        bw = np.maximum(blur(w, sigma), 1e-5)
        bc = np.stack([blur(col[..., c] * w, sigma) for c in range(3)], axis=-1) / bw[..., None]
        fill = np.clip(bc, 0, 1)
        need = ~inside if sigma == 3.0 else (blur(w, sigma / 3.5) < 0.02) & ~inside
        out = np.where(need[..., None], fill, out)
    mean = (col * w[..., None]).sum((0, 1)) / max(w.sum(), 1.0)
    far = blur(w, 40.0) < 1e-3
    out = np.where((far & ~inside)[..., None], mean, out)
    rgba = np.concatenate([lin_to_srgb(out), np.clip(A, 0, 1)[..., None]], axis=-1)
    return rgba


def apple_maps():
    """256x128 fruit map: left half red apple, right half yellow-green apple."""
    h, w = 128, 256
    rng = np.random.default_rng(5)
    v, u = np.mgrid[0:h, 0:w].astype(np.float64)
    u = (u + 0.5) / w
    v = 1.0 - (v + 0.5) / h
    red = srgb_to_lin(hex_rgb("#bf3e30"))
    red2 = srgb_to_lin(hex_rgb("#8e2a22"))
    yel = srgb_to_lin(hex_rgb("#d5b54b"))
    grn = srgb_to_lin(hex_rgb("#a9b94e"))
    streak = fbm(u * 2 % 1.0, v, 24, 2, 3, rng)
    left = u < 0.5
    col_red = mix(red2, red, streak) * 1.0
    col_red = mix(col_red, yel, smoothstep(0.75, 1.0, fbm(u, v, 4, 4, 3, rng)) * 0.35)
    col_yel = mix(grn, yel, streak)
    col_yel = mix(col_yel, red, smoothstep(0.7, 1.0, fbm(u, v, 4, 4, 3, rng)) * 0.35)
    col = np.where(left[..., None], col_red, col_yel)
    speck = (rng.random((h, w)) > 0.985)
    col = np.where(speck[..., None], col * 1.35, col)
    # stalk cavity near v = 1 (top), darker
    col = col * (1 - 0.45 * smoothstep(0.88, 1.0, v))[..., None]
    nrm = np.zeros((h, w, 3))
    nrm[..., 0] = 0.5
    nrm[..., 1] = 0.5
    nrm[..., 2] = 1.0
    rough = 0.32 + 0.1 * streak
    return lin_to_srgb(col), nrm, rough


if __name__ == "__main__":
    import argparse
    import time

    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="build/art/trees/tex_preview")
    a = ap.parse_args()
    t0 = time.time()
    for fam in BARK_FAMILIES:
        c, nrm, r = bark_maps(fam, seed=11)
        write_png(os.path.join(a.out, f"bark_{fam}_color.png"), c)
        write_png(os.path.join(a.out, f"bark_{fam}_normal.png"), nrm)
        write_png(os.path.join(a.out, f"bark_{fam}_roughness.png"), r)
        print("bark", fam, round(time.time() - t0, 2))
    pals = {"oak": ["#44763b", "#6d984d", "#547e42", "#8ba75b"], "elm": ["#5a9243", "#73a85c", "#507b3c", "#92ac5f"],
            "palmate": ["#6c9a48", "#82ab54", "#5c8745", "#a9b76a"], "willow": ["#769377", "#95a580", "#586f5b"],
            "apple": ["#617f3c", "#829e4d", "#4e7138"]}
    for shape in LEAF_SHAPES:
        lay = leaf_layout(shape, seed=21)
        nrm, r = leaf_normal_rough(lay)
        write_png(os.path.join(a.out, f"leaf_{shape}_normal.png"), nrm)
        write_png(os.path.join(a.out, f"leaf_{shape}_roughness.png"), r)
        for layer in ("sun", "shade"):
            write_png(os.path.join(a.out, f"leaf_{shape}_{layer}.png"), leaf_colour(lay, pals[shape], layer))
        print("leaf", shape, "gaps %.3f" % float((lay["ID"] < 0).mean()), round(time.time() - t0, 2))
    c, nrm, r = apple_maps()
    write_png(os.path.join(a.out, "apple_color.png"), c)
