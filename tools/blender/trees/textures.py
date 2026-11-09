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
    "oak": ("#2a231d", "#5f5245", "#8c806f"),
    "elm": ("#2b231d", "#625244", "#8a7a68"),
    "sycamore": ("#6f6a55", "#a3a089", "#e4dfcc"),
    "maple": ("#3a332c", "#7b6f62", "#a89d8d"),
    "willow": ("#2a241f", "#625649", "#8c8172"),
    "apple": ("#33281f", "#766047", "#9d8668"),
}


def bark_maps(family, seed=1, tint=None):
    """Returns (colour sRGB HxWx3, normal HxWx3, roughness HxW). tint: optional hex multiplied in."""
    rng = np.random.default_rng(seed)
    u, v = _grid_uv()
    dark, mid, light = (srgb_to_lin(hex_rgb(c)) for c in BARK_COLOURS[family])
    lichen = srgb_to_lin(hex_rgb("#8d9a6c"))
    moss = srgb_to_lin(hex_rgb("#55663a"))
    if family in ("oak", "elm", "willow", "maple"):
        warp = fbm(u, v, 3, 2, 4, rng)
        warp2 = fbm(u, v, 2, 3, 3, rng)
        fx = {"oak": 9, "elm": 11, "willow": 8, "maple": 13}[family]
        fy = {"oak": 2, "elm": 3, "willow": 1, "maple": 2}[family]
        wu = u + (warp - 0.5) * (0.10 if family == "elm" else 0.06) + np.sin(v * 2 * math.pi * fy * 2) * (0.015 if family == "elm" else 0.0)
        n1 = fbm(wu, v + (warp2 - 0.5) * 0.08, fx, fy, 5, rng, gain=0.55)
        ridge = 1.0 - np.abs(2 * n1 - 1)
        ridge = ridge ** (1.6 if family in ("oak", "willow") else 1.2)
        # horizontal cracks break ridges into long plates
        f1, f2, cid = worley(wu % 1.0, v, max(3, fx // 2), max(2, fy + 1), rng, jitter=0.9)
        crack = 0.6 + 0.4 * smoothstep(0.0, 0.05, f2 - f1)
        depth = {"oak": 1.0, "elm": 0.85, "willow": 1.0, "maple": 0.55}[family]
        h = ridge * (0.65 + 0.35 * crack) * depth + fbm(u, v, 32, 32, 3, rng) * 0.18
        h = (h - h.min()) / (h.max() - h.min())
        t = smoothstep(0.15, 0.85, h)
        col = mix(mix(dark, mid, smoothstep(0.0, 0.55, h)), light, smoothstep(0.55, 1.0, h) * 0.8)
        col = col * (0.88 + 0.24 * fbm(u, v, 4, 4, 4, rng))[..., None]
        lich = smoothstep(0.62, 0.78, fbm(u, v, 5, 5, 5, rng)) * smoothstep(0.45, 0.8, h)
        col = mix(col, lichen, lich * (0.55 if family != "maple" else 0.3))
        mossm = smoothstep(0.7, 0.85, fbm(u, v, 3, 4, 4, rng)) * (1 - smoothstep(0.1, 0.5, h))
        col = mix(col, moss, mossm * 0.5)
        rough = 0.97 - 0.18 * t
        nstr = {"oak": 7.0, "elm": 6.0, "willow": 7.5, "maple": 4.0}[family]
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


def leaf_normal_rough(layout, strength=70.0):
    H, ID, S, T = layout["H"], layout["ID"], layout["S"], layout["T"]
    gap = ID < 0
    # Detail height: each leaf's own relief plus a small step per stacking order, so edges read.
    z0 = np.where(gap, -0.15, layout["leaves"][np.maximum(ID, 0), 6])
    prof = H - z0  # leaf relief only
    hd = prof * 1.0 + z0 * 0.06 + np.where(gap, -0.05, 0.0)
    hd = blur(hd, 0.7)
    normal = height_to_normal(hd, strength)
    occl = H - blur(H, 9.0)
    rough = np.where(gap, 0.95, 0.62 - 0.12 * np.clip(occl * 3 + 0.5, 0, 1) + 0.06 * (layout["bright"][np.maximum(ID, 0)] - 0.5))
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
    lum = 0.80 + 0.36 * bright
    if layer == "sun":
        warm = np.array([1.10, 1.06, 0.80])
        col = col * warm * 1.10
    elif layer == "shade":
        cool = np.array([0.86, 0.95, 1.02])
        col = col * cool * 0.80
    col = col * lum[..., None]
    # within a leaf: lighter midrib and veins, darker toward the stalk and the edges
    shape = layout["shape"]
    rib = np.exp(-(T / 0.10) ** 2) * (shape != "palmate")
    edge = smoothstep(0.55, 1.0, np.abs(T))
    col = col * (1.0 + 0.16 * rib[..., None]) * (1.0 - 0.18 * edge[..., None]) * (0.86 + 0.18 * np.clip(S, 0, 1))[..., None]
    # occlusion: leaves deeper in the pile are darker
    occl = H - blur(H, 10.0)
    ao = np.clip(0.62 + occl * 1.6, 0.35, 1.08)
    col = col * ao[..., None]
    u, v = _grid_uv(H.shape[0])
    big = fbm(u, v, 3, 3, 3, rng)
    col = col * (0.90 + 0.20 * big)[..., None]
    if layer == "sun":
        yellow = srgb_to_lin(hex_rgb("#c9cf6a"))
        col = mix(col, yellow * lum[..., None], smoothstep(0.62, 0.9, big) * 0.22 * (1 - gap))
    deep = pal.min(axis=0) * (0.20 if layer == "shade" else 0.28)
    col = np.where(gap[..., None], deep, col)
    return lin_to_srgb(col)


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
