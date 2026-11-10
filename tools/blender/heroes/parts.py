"""Region meshes besides Body/Pattern: Eyes, FurCards and (rodent) Blood. Each is its own skinned
MeshPart in Roblox with its own SurfaceAppearance (D22); all are bound to the exported armature."""
import math
import os

import bpy
import numpy as np

import bl
import geometry
import rig
import textures as tx

F32 = np.float32


def _assign(obj, bone_names, W):
    rig.set_weights_np(obj, W, bone_names)


def _uv_from_corners(obj, corner_uvs):
    me = obj.data
    uv = me.uv_layers.new(name="UVMap")
    flat = np.array([c for face in corner_uvs for c in face], dtype=F32)
    uv.data.foreach_set("uv", flat.reshape(-1))


# ---- eyes -------------------------------------------------------------------------------------------

def eye_textures(variant, out_dir, res=256, name=None):
    """Colour and roughness maps for the eyeballs; UV v = 1 at the pupil (sphere pole)."""
    ys, xs = np.mgrid[0:res, 0:res]
    u = (xs + 0.5) / res
    v = 1 - (ys + 0.5) / res  # top row = v near 1 = the pupil
    th = (1 - v) * 180.0  # degrees from the gaze pole
    P = np.stack([np.cos(u * 2 * math.pi) * th, np.sin(u * 2 * math.pi) * th, th * 0.0], -1).reshape(-1, 3).astype(F32)
    rad = tx.vnoise(np.stack([u.ravel() * 40, th.ravel() * 0.25, np.zeros(res * res)], -1).astype(F32), 3).reshape(res, res)
    col = np.zeros((res, res, 4), F32)
    col[..., 3] = 1
    rough = np.full((res, res), 0.06, F32)
    if variant == "fox":
        ph = u * 2 * math.pi
        iris = 62.0
        c = np.array([0.80, 0.52, 0.12]) * (0.75 + 0.5 * rad[..., None]) * (1 - 0.45 * np.clip(th / iris, 0, 1))[..., None]
        slit = (th * np.abs(np.cos(ph)) < 5.5) & (th < 30)
        c = np.where(slit[..., None], np.array([0.02, 0.015, 0.01]), c)
        ring = np.exp(-((th - iris) / 3.0) ** 2)
        c = c * (1 - 0.8 * ring[..., None])
        c = np.where((th >= iris)[..., None], np.array([0.06, 0.04, 0.03]), c)
    elif variant == "deer":
        pupil, iris = 30.0, 68.0
        c = np.zeros((res, res, 3)) + np.array([0.015, 0.012, 0.01])
        irisc = np.array([0.12, 0.07, 0.035]) * (0.6 + 0.8 * rad[..., None])
        c = np.where(((th > pupil) & (th < iris))[..., None], irisc, c)
        c = np.where((th >= iris)[..., None], np.array([0.04, 0.03, 0.025]), c)
    elif variant == "rodent":
        # Glowing red eyes (owner 2026-11-10: the bloodshot, veined eyeball with a pin pupil was part
        # of "too edgy"): a squirrel's dark round pupil in a deep red iris that fills the eye, brighter
        # toward the pupil, nearly black at the lids. No sclera, no veins.
        pupil, iris = 24.0, 74.0
        k = np.clip((th - pupil) / (iris - pupil), 0, 1)
        irisc = np.array([1.0, 0.16, 0.05]) * (0.95 + 0.1 * rad[..., None]) * (1 - 0.55 * k)[..., None]
        c = np.broadcast_to(np.array([0.10, 0.01, 0.01]), irisc.shape).copy()
        c = np.where((th < iris)[..., None], irisc, c)
        c = np.where((th < pupil)[..., None], np.array([0.03, 0.0, 0.0]), c)
        ring = np.exp(-((th - iris) / 3.0) ** 2)
        c = c * (1 - 0.6 * ring[..., None])
    else:
        pupil, iris = 26.0, 58.0
        c = np.zeros((res, res, 3)) + np.array([0.02, 0.016, 0.014])
        irisc = np.array([0.16, 0.085, 0.04]) * (0.6 + 0.8 * rad[..., None])
        c = np.where(((th > pupil) & (th < iris))[..., None], irisc, c)
        ring = np.exp(-((th - iris) / 3.0) ** 2)
        c = c + np.array([0.12, 0.07, 0.03]) * ring[..., None]
        c = np.where((th >= iris)[..., None], np.array([0.05, 0.035, 0.03]), c)
    col[..., :3] = np.clip(c, 0, 1)
    rgba_r = np.stack([rough] * 3 + [np.ones_like(rough)], -1)
    name = name or variant
    paths = {"color": os.path.join(out_dir, f"{name}_eyes_color.png"), "roughness": os.path.join(out_dir, f"{name}_eyes_roughness.png")}
    bl.save_png(paths["color"], col)
    bl.save_png(paths["roughness"], rgba_r, colorspace="Non-Color")
    return paths


def build_eyes(sp, variant, arm, bone_names, out_dir):
    parts = []
    allv, allf, alluv = [], [], []
    off = 0
    for side in (1, -1):
        c = sp.eye_centre(variant, side)
        gaze = sp.eye_gaze(side)
        v, f, uv = geometry.uv_sphere(c, sp.eye_radius(variant), gaze, segs=14, rings=8)
        allv.extend(v.tolist())
        allf.extend([tuple(i + off for i in face) for face in f])
        alluv.extend(uv)
        off += len(v)
    obj = bl.mesh_from_arrays("Eyes", np.array(allv), allf)
    _uv_from_corners(obj, alluv)
    W = np.zeros((len(obj.data.vertices), len(bone_names)))
    W[:, bone_names.index("Head")] = 1
    _assign(obj, bone_names, W)
    rig.bind(obj, arm)
    paths = eye_textures(variant if variant == "rodent" else getattr(sp, "EYE_STYLE", "squirrel"), out_dir, name=variant)
    mat = tx.principled_material("Eyes", paths)
    obj.data.materials.append(mat)
    if variant == "rodent":
        bsdf = mat.node_tree.nodes.get("Principled BSDF")
        mat["glow"] = 1.0
    return obj


# ---- fur cards --------------------------------------------------------------------------------------

CELLS_X, CELLS_Y = 4, 2  # 8 atlas cells: 4 brightness levels x 2 tuft shapes
LEVELS = [0.52, 0.70, 0.85, 0.98]


def card_atlas(variant, out_dir, res=512):
    """Strand tufts with alpha: greyscale (tinted with the Body colour in the engine), a strand normal
    map and roughness. Cell (i, j): brightness LEVELS[i], shape j (0 = narrow lock, 1 = wide tuft)."""
    rng = np.random.default_rng(7 if variant != "rodent" else 8)
    cw, ch = res // CELLS_X, res // CELLS_Y
    col = np.zeros((res, res, 4), F32)
    nrm = np.zeros((res, res, 3), F32)
    nrm[...] = (0.5, 0.5, 1.0)
    ys, xs = np.mgrid[0:ch, 0:cw].astype(F32)
    yy = 1 - (ys + 0.5) / ch  # 0 at the root (bottom row of the cell), 1 at the tip
    xx = (xs + 0.5) / cw
    for i, level in enumerate(LEVELS):
        for j in range(CELLS_Y):
            nstr = (28 if j == 0 else 46) if variant != "rodent" else (16 if j == 0 else 24)
            a = np.zeros((ch, cw), F32)
            g = np.zeros((ch, cw), F32)
            nx = np.zeros((ch, cw), F32)
            for s in range(nstr):
                x0 = 0.5 + rng.normal(0, 0.13 if j == 0 else 0.2)
                h = rng.uniform(0.55, 1.0)
                bend = rng.normal(0, 0.12 if j == 0 else 0.2)
                if variant == "rodent":
                    h *= rng.uniform(0.5, 1.0)
                    bend *= 1.8
                w0 = rng.uniform(0.010, 0.022) * (1.3 if variant == "rodent" else 1.0)
                t = np.clip(yy / h, 0, 1)
                cx = x0 + bend * t * t + (0.5 - x0) * 0.25 * t
                width = w0 * (1 - t) ** 0.6 + 0.003
                d = (xx - cx) / width
                cov = np.clip(1 - np.abs(d), 0, 1) * (yy <= h) * (1 - 0.75 * t ** 2) * (0.55 + 0.45 * np.clip(yy * 6, 0, 1))
                tone = level * (0.86 + 0.18 * t) * rng.uniform(0.9, 1.1)
                take = cov > a
                g = np.where(take, tone, g)
                nx = np.where(take, np.clip(d, -1, 1) * 0.8, nx)
                a = np.maximum(a, cov)
            y0 = (CELLS_Y - 1 - j) * ch
            x0p = i * cw
            col[y0 : y0 + ch, x0p : x0p + cw, :3] = np.clip(g, 0, 1)[..., None]
            col[y0 : y0 + ch, x0p : x0p + cw, 3] = np.clip(a * 0.95, 0, 1)
            nz = np.sqrt(np.clip(1 - nx * nx, 0, 1))
            nrm[y0 : y0 + ch, x0p : x0p + cw] = np.stack([nx * 0.5 + 0.5, np.full_like(nx, 0.5), nz * 0.5 + 0.5], -1)
    # colour under transparent texels: dilate so filtering never pulls in black
    filled = col[..., 3] > 0.02
    col[..., :3] = tx.dilate(col[..., :3], filled, iters=6)
    col[~filled & (col[..., :3].sum(-1) == 0), :3] = 0.7
    rough = np.full((res, res, 4), 0.58, F32)
    rough[..., 3] = 1
    paths = {"color": os.path.join(out_dir, f"{variant}_cards_color.png"),
             "normal": os.path.join(out_dir, f"{variant}_cards_normal.png"),
             "roughness": os.path.join(out_dir, f"{variant}_cards_roughness.png")}
    bl.save_png(paths["color"], col)
    bl.save_png(paths["normal"], np.concatenate([nrm, np.ones((res, res, 1), F32)], -1), colorspace="Non-Color")
    bl.save_png(paths["roughness"], rough, colorspace="Non-Color")
    return paths


def build_cards(sp, variant, lo, arm, W, bone_names, opts, out_dir, body_color_path):
    """Scatter tufts over the Body region (density by part), each a 2-segment card rising from the
    skin along the fur flow, skinned with the weights at its root."""
    rng = np.random.default_rng(1234 if variant != "rodent" else 4321)
    budget = sp.BUDGET["rodent_cards_tris" if variant == "rodent" else "cards_tris"]
    ncards = budget // 4
    if ncards <= 0:
        return None
    me = lo.data
    A = tx.mesh_arrays(lo)
    skel = sp.skeleton()
    flow = tx.vertex_flow(lo, W, skel, sp, variant)
    nt = len(A["tv"])
    vco = A["co"]
    tri_v = A["tv"]
    a, b, c = vco[tri_v[:, 0]], vco[tri_v[:, 1]], vco[tri_v[:, 2]]
    area = 0.5 * np.linalg.norm(np.cross(b - a, c - a), axis=1)
    mat = np.empty(len(me.polygons), dtype=np.int32)
    me.polygons.foreach_get("material_index", mat)
    kind = np.empty(len(me.polygons), dtype=np.int32)
    me.attributes["hard_kind"].data.foreach_get("value", kind)
    cen = (a + b + c) / 3
    fn = np.cross(b - a, c - a)
    fn /= np.maximum(np.linalg.norm(fn, axis=1, keepdims=True), 1e-12)
    domv = np.array(bone_names)[np.argmax(W, axis=1)]
    dom = domv[tri_v[:, 0]]
    dens = sp.card_density(cen, fn, dom, variant) * (mat[A["tp"]] == 0) * (kind[A["tp"]] == 0)
    p = area * dens
    if p.sum() <= 0:
        return None
    pick = rng.choice(nt, size=ncards, p=p / p.sum())
    r1, r2 = rng.random(ncards), rng.random(ncards)
    s = np.sqrt(r1)
    bary = np.stack([1 - s, s * (1 - r2), s * r2], -1)
    tv = tri_v[pick]
    P = np.einsum("nk,nkd->nd", bary, vco[tv])
    Nn = np.einsum("nk,nkd->nd", bary, A["nrm"][A["tl"][pick]])
    Nn /= np.linalg.norm(Nn, axis=1, keepdims=True)
    Fd = np.einsum("nk,nkd->nd", bary, flow[tv])
    Fd -= np.einsum("ij,ij->i", Fd, Nn)[:, None] * Nn
    Fd /= np.maximum(np.linalg.norm(Fd, axis=1, keepdims=True), 1e-9)
    Wc = np.einsum("nk,nkb->nb", bary, W[tv])
    # body brightness at the root (the colour map's grey) picks the card's atlas level
    _img, cmap = bl.load_png(body_color_path)
    res = cmap.shape[0]
    uv = np.einsum("nk,nkd->nd", bary, A["uv"][A["tl"][pick]])
    px = np.clip((uv[:, 0] * res).astype(int), 0, res - 1)
    py = np.clip(((1 - uv[:, 1]) * res).astype(int), 0, res - 1)
    grey = cmap[py, px, :3].mean(axis=1)
    level = np.argmin(np.abs(grey[:, None] - np.array(LEVELS)[None]), axis=1)
    keep = cmap[py, px, 3] > 0.5  # no tufts on bare skin (rodent mange and patches) or untinted spots
    params = sp.card_shape(P, Nn, Fd, dom[pick], variant, rng)
    verts, faces, uvs, wts = [], [], [], []
    for k in np.nonzero(keep)[0]:
        L, wdt, lift, roll, droop = (params[q][k] for q in ("length", "width", "lift", "roll", "droop"))
        n, f = Nn[k], Fd[k]
        side = np.cross(n, f)
        d = f * math.cos(lift) + n * math.sin(lift)
        # roll the card's side vector about its axis (0 = lies over the fur, pi/2 = stands up)
        sv = side * math.cos(roll) + np.cross(d, side) * math.sin(roll)
        root = P[k] - n * 0.004 * sp.SCALE
        mid = root + d * L * 0.5
        d2 = d * (1 - droop) + f * droop - n * droop * 0.35
        d2 /= np.linalg.norm(d2)
        tip = mid + d2 * L * 0.5
        rows = [(root, wdt * 0.8), (mid, wdt), (tip, wdt * 0.7)]
        base = len(verts)
        for pt, w in rows:
            verts.append(pt - sv * w * 0.5)
            verts.append(pt + sv * w * 0.5)
        faces.append((base, base + 1, base + 3, base + 2))
        faces.append((base + 2, base + 3, base + 5, base + 4))
        cell_x = level[k]
        cell_y = rng.integers(0, CELLS_Y)
        u0, u1 = cell_x / CELLS_X + 0.004, (cell_x + 1) / CELLS_X - 0.004
        v0 = cell_y / CELLS_Y + 0.004
        v1 = (cell_y + 1) / CELLS_Y - 0.004
        flip = rng.random() < 0.5
        ua, ub = (u1, u0) if flip else (u0, u1)
        cu = []
        for r, vv in enumerate((v0, (v0 + v1) / 2, v1)):
            cu.append((ua, vv))
            cu.append((ub, vv))
        uvs.append([cu[0], cu[1], cu[3], cu[2]])
        uvs.append([cu[2], cu[3], cu[5], cu[4]])
        for _ in range(6):
            wts.append(Wc[k])
    obj = bl.mesh_from_arrays("FurCards", np.array(verts), faces)
    _uv_from_corners(obj, uvs)
    _assign(obj, bone_names, np.array(wts))
    rig.bind(obj, arm)
    paths = card_atlas(variant, out_dir)
    obj.data.materials.append(tx.principled_material("FurCards", paths, alpha_from_color=True))
    return obj


# ---- blood (rodent) ---------------------------------------------------------------------------------

def build_blood(sp, variant, lo, arm, W, bone_names, out_dir, res=256):
    """Mild: a stain at the corners of the mouth and chin and on the front claws, as a thin shell over
    those faces with its own small alpha texture (so a moderation problem never blocks the body)."""
    me = lo.data
    co = bl.verts_np(me)
    sel = sp.blood_faces(lo, co, W, bone_names)
    if not sel.any():
        return None
    nv = np.empty(len(me.vertices) * 3, dtype=F32)
    me.vertices.foreach_get("normal", nv)
    nv = nv.reshape(-1, 3)
    polys = [p for p in me.polygons if sel[p.index]]
    used = sorted({i for p in polys for i in p.vertices})
    remap = {v: k for k, v in enumerate(used)}
    verts = co[used] + nv[used] * 0.0035 * sp.SCALE
    faces = [tuple(remap[i] for i in p.vertices) for p in polys]
    obj = bl.mesh_from_arrays("Blood", verts, faces)
    _assign(obj, bone_names, W[used])
    geometry.uv_unwrap(obj, angle=70, margin=0.02)
    A = tx.mesh_arrays(obj)
    tri, bary = tx.rasterize(A, res)
    filled = tri >= 0
    P = tx.interp_vertex(A, tri[filled], bary[filled], A["co"]).astype(F32)
    mask = sp.blood_mask(P, {"vnoise": tx.vnoise, "fbm": tx.fbm, "sstep": tx.sstep, "strands": tx.strands})
    col = np.zeros((res, res, 4), F32)
    shade = 0.75 + 0.5 * tx.vnoise(P * 300.0, 5)
    col[filled, :3] = np.array([0.40, 0.035, 0.03]) * shade[:, None]
    col[filled, 3] = mask
    col[..., :3] = tx.dilate(col[..., :3], filled, iters=8)
    col[..., 3] = tx.dilate(col[..., 3], filled, iters=8) * 1.0
    rough = np.full((res, res, 4), 0.22, F32)
    rough[..., 3] = 1
    paths = {"color": os.path.join(out_dir, f"{variant}_blood_color.png"), "roughness": os.path.join(out_dir, f"{variant}_blood_roughness.png")}
    bl.save_png(paths["color"], col[::-1])
    bl.save_png(paths["roughness"], rough, colorspace="Non-Color")
    obj.data.materials.append(tx.principled_material("Blood", paths, alpha_from_color=True))
    rig.bind(obj, arm)
    return obj


def build_antlers(sp, variant, arm, bone_names, out_dir, res=256):
    """The buck's rack as its own MeshPart ("Antlers"), skinned to Head; bony beige darkening to
    brown at the burr, polished pale tips."""
    obj, owner = geometry.object_from_parts("Antlers", sp.antlers())
    W = np.zeros((len(obj.data.vertices), len(bone_names)))
    W[:, bone_names.index("Head")] = 1
    _assign(obj, bone_names, W)
    geometry.uv_unwrap(obj, angle=60, margin=0.02)
    A = tx.mesh_arrays(obj)
    tri, bary = tx.rasterize(A, res)
    filled = tri >= 0
    P = tx.interp_vertex(A, tri[filled], bary[filled], A["co"]).astype(F32)
    head = np.array(sp.skeleton()[[b[0] for b in sp.skeleton()].index("Head")][1], F32)
    h = np.clip((P[:, 2] - 5.3) / 0.9, 0, 1)
    base = np.array([0.42, 0.31, 0.21]) * (1 - h[:, None]) + np.array([0.80, 0.72, 0.58]) * h[:, None]
    rid = tx.strands(P, np.tile(np.array([[0, 0, 1.0]], F32), (len(P), 1)), 0.01, 0.08, seed=81)
    col = np.zeros((res, res, 4), F32)
    col[filled, :3] = np.clip(base * (0.8 + 0.35 * rid)[:, None], 0, 1)
    col[filled, 3] = 1
    col = tx.dilate(col, filled, iters=8)
    col[..., 3] = 1
    rough = np.full((res, res, 4), 0.72, F32)
    rough[filled, 0] = rough[filled, 1] = rough[filled, 2] = 0.75 - 0.3 * h
    rough[..., 3] = 1
    paths = {"color": os.path.join(out_dir, f"{variant}_antlers_color.png"), "roughness": os.path.join(out_dir, f"{variant}_antlers_roughness.png")}
    bl.save_png(paths["color"], col[::-1])
    bl.save_png(paths["roughness"], rough[::-1], colorspace="Non-Color")
    obj.data.materials.append(tx.principled_material("Antlers", paths))
    rig.bind(obj, arm)
    return obj


def build(sp, variant, lo, arm, W, bone_names, opts, log):
    out_dir = os.path.join(opts.out, "tex")
    objs = [build_eyes(sp, variant, arm, bone_names, out_dir)]
    log("eyes")
    body_color = os.path.join(out_dir, f"{variant}_body_color.png")
    cards = build_cards(sp, variant, lo, arm, W, bone_names, opts, out_dir, body_color)
    if cards is not None:
        objs.append(cards)
        log(f"fur cards: {bl.tri_count(cards.data)} tris")
    if variant == "buck" and hasattr(sp, "antlers"):
        ant = build_antlers(sp, variant, arm, bone_names, out_dir)
        objs.append(ant)
        log(f"antlers: {bl.tri_count(ant.data)} tris")
    if variant == "rodent":
        blood = build_blood(sp, variant, lo, arm, W, bone_names, out_dir)
        if blood is not None:
            objs.append(blood)
            log(f"blood: {bl.tri_count(blood.data)} tris")
    return objs
