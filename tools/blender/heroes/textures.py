"""Procedural texture painting for the hero animals.

1. Rasterise the low-poly's UV layout: every texel learns its triangle and barycentrics, hence its 3-D
   position P, normal N, MikkTSpace tangent frame (T, B), the fur flow direction F (a per-vertex field
   from the bones: nose to tail along the body, down the legs, along and out of the tail), its region
   and its dominant bone.
2. Paint in 3-D, so UV seams never show: fur strands are line integrals of 3-D value noise along F
   (a straight-segment LIC, fine hairs plus clumps); colour, tint mask and roughness come from the
   species painter (species_*.paint), which works on those texel attributes.
3. Bake the sculpt's detail (muscle, ribs, toes, lids) from the high-poly into a tangent-space normal
   map and an AO map with Cycles (selected-to-active), add the strand relief (UDN blend) and write
   1024 px PNGs: colour (RGB greyscale where the avatar tint applies, alpha = the TintMask), normal
   (OpenGL +Y, as Roblox and Blender's baker use) and roughness. Texels outside the islands are
   filled by dilation so mipmaps do not bleed.
"""
import math
import os

import bpy
import numpy as np

import bl

F32 = np.float32


# ---- noise ------------------------------------------------------------------------------------------

def _hash3(ix, iy, iz, seed):
    h = (ix * 374761393 + iy * 668265263 + iz * 1440670441 + seed * 2654435761) & 0xFFFFFFFF
    h = ((h ^ (h >> 13)) * 1274126177) & 0xFFFFFFFF
    h = h ^ (h >> 16)
    return (h & 0xFFFFFF).astype(F32) * F32(1.0 / 0xFFFFFF)


def vnoise(p, seed=0):
    """Smooth 3-D value noise in [0, 1] at points p (N, 3)."""
    p = np.asarray(p, dtype=F32)
    i = np.floor(p)
    f = p - i
    u = f * f * (3 - 2 * f)
    i = i.astype(np.int64)
    ix, iy, iz = i[:, 0], i[:, 1], i[:, 2]
    out = np.zeros(len(p), dtype=F32)
    for dx in (0, 1):
        wx = u[:, 0] if dx else 1 - u[:, 0]
        for dy in (0, 1):
            wy = u[:, 1] if dy else 1 - u[:, 1]
            for dz in (0, 1):
                wz = u[:, 2] if dz else 1 - u[:, 2]
                out += wx * wy * wz * _hash3(ix + dx, iy + dy, iz + dz, seed)
    return out


def fbm(p, octaves=4, seed=0, lac=2.0, gain=0.5):
    a, s, tot = 1.0, 1.0, 0.0
    out = np.zeros(len(p), dtype=F32)
    for o in range(octaves):
        out += F32(a) * vnoise(p * F32(s), seed + 17 * o)
        tot += a
        a *= gain
        s *= lac
    return out / F32(tot)


def strands(P, Fdir, width, length, samples=9, seed=0):
    """Fur streaks: mean of 3-D value noise (cell = width) along a straight segment of `length` through
    P in direction Fdir. Contrast-normalised to roughly [0, 1]."""
    acc = np.zeros(len(P), dtype=F32)
    q = P / F32(width)
    d = Fdir * F32(length / width)
    for s in np.linspace(-0.5, 0.5, samples, dtype=F32):
        acc += vnoise(q + d * s, seed)
    acc /= samples
    # the mean of n noise samples has a narrow spread: stretch it back
    return np.clip((acc - 0.5) * (1.6 + 0.12 * samples) + 0.5, 0, 1)


def fur_relief(P, F, N, T, B, layers, eps=None, lscale=None):
    """Strand height H (0..1 mix of the layers) and its tangent-space slopes (gT, gB), from the
    gradient across the flow (b = N x F). layers: [(width, length, weight, depth, seed)]; depth is
    the relief height in studs of each layer."""
    b = np.cross(N, F).astype(F32)
    e = F32(eps or min(l[0] for l in layers) * 0.35)
    H = np.zeros(len(P), dtype=F32)
    dH = np.zeros(len(P), dtype=F32)
    wsum = sum(l[2] for l in layers)
    Fl = F if lscale is None else F * np.asarray(lscale, dtype=F32)[:, None]
    for width, length, weight, depth, seed in layers:
        h0 = strands(P, Fl, width, length, seed=seed)
        hp = strands(P + b * e, Fl, width, length, seed=seed)
        hm = strands(P - b * e, Fl, width, length, seed=seed)
        H += h0 * F32(weight / wsum)
        dH += (hp - hm) / (2 * e) * F32(depth)
    gT = dH * np.einsum("ij,ij->i", b, T)
    gB = dH * np.einsum("ij,ij->i", b, B)
    return H, gT, gB


def region_colours(region, m, g_body, g_pat, tb, tp, sstep_fn=None):
    """Seamless Body/Pattern colouring. m (0..1) is the continuous pattern weight; region the face's
    region (0 Body, 1 Pattern). The natural colour follows m smoothly; the tint mask is 1 where the
    texel's natural colour is its region's own (grey x that region's tint), fading to 0 where it
    belongs to the other region, so at the stock tint the border follows m, not the face edges.
    Returns (grey, alpha, natural rgb)."""
    m = np.clip(m, 0, 1)
    nat = (np.clip(g_body, 0, 1)[:, None] * tb) * (1 - m[:, None]) + (np.clip(g_pat, 0, 1)[:, None] * tp) * m[:, None]
    own = np.where(region == 1, 1 - m, m)  # how much of the other region shows here
    alpha = 1 - sstep(0.02, 0.25, own)
    grey = np.where(region == 1, g_pat, g_body)
    return grey, alpha.astype(F32), nat.astype(F32)


def finish_rgb(grey, alpha, natv, region, tb, tp):
    """Map RGB: grey where fully tinted; elsewhere natural / lerp(1, tint, alpha), so the engine's
    TintMask (rgb x lerp(1, Color, alpha)) shows the natural colour at the stock Color."""
    tint_reg = np.where((region == 1)[:, None], tp, tb)
    denom = 1 - alpha[:, None] + alpha[:, None] * tint_reg
    rgb = np.where(alpha[:, None] > 0.999, np.clip(grey, 0, 1)[:, None].repeat(3, 1), natv / np.maximum(denom, 1e-3))
    return np.clip(rgb, 0, 1).astype(F32)


def sstep(a, b, x):
    t = np.clip((np.asarray(x, dtype=F32) - a) / (b - a), 0, 1)
    return t * t * (3 - 2 * t)


# ---- rasterisation ----------------------------------------------------------------------------------

def mesh_arrays(obj):
    me = obj.data
    me.calc_loop_triangles()
    nt = len(me.loop_triangles)
    tl = np.empty(nt * 3, dtype=np.int64)
    me.loop_triangles.foreach_get("loops", tl)
    tv = np.empty(nt * 3, dtype=np.int64)
    me.loop_triangles.foreach_get("vertices", tv)
    tp = np.empty(nt, dtype=np.int64)
    me.loop_triangles.foreach_get("polygon_index", tp)
    nl = len(me.loops)
    uv = np.empty(nl * 2, dtype=np.float64)
    me.uv_layers.active.data.foreach_get("uv", uv)
    me.calc_tangents(uvmap=me.uv_layers.active.name)
    tan = np.empty(nl * 3, dtype=F32)
    me.loops.foreach_get("tangent", tan)
    sgn = np.empty(nl, dtype=F32)
    me.loops.foreach_get("bitangent_sign", sgn)
    nrm = np.empty(nl * 3, dtype=F32)
    me.corner_normals.foreach_get("vector", nrm)
    co = bl.verts_np(me)
    return {
        "tl": tl.reshape(-1, 3), "tv": tv.reshape(-1, 3), "tp": tp, "uv": uv.reshape(-1, 2),
        "tan": tan.reshape(-1, 3), "sgn": sgn, "nrm": nrm.reshape(-1, 3), "co": co,
    }


def rasterize(A, res):
    """Per texel (row 0 = v near 0, i.e. bottom-up like Blender images): triangle id (-1 empty) and
    barycentrics."""
    tri = np.full((res, res), -1, dtype=np.int64)
    bary = np.zeros((res, res, 3), dtype=F32)
    uvp = A["uv"] * res - 0.5  # texel centres at integers
    for t, loops in enumerate(A["tl"]):
        p = uvp[loops]
        x0, y0 = np.floor(p.min(axis=0)).astype(int)
        x1, y1 = np.ceil(p.max(axis=0)).astype(int)
        x0, y0 = max(x0, 0), max(y0, 0)
        x1, y1 = min(x1, res - 1), min(y1, res - 1)
        if x1 < x0 or y1 < y0:
            continue
        xs, ys = np.meshgrid(np.arange(x0, x1 + 1), np.arange(y0, y1 + 1))
        (ax, ay), (bx, by), (cx, cy) = p
        den = (by - cy) * (ax - cx) + (cx - bx) * (ay - cy)
        if abs(den) < 1e-12:
            continue
        l0 = ((by - cy) * (xs - cx) + (cx - bx) * (ys - cy)) / den
        l1 = ((cy - ay) * (xs - cx) + (ax - cx) * (ys - cy)) / den
        l2 = 1 - l0 - l1
        m = (l0 >= -1e-4) & (l1 >= -1e-4) & (l2 >= -1e-4)
        if not m.any():
            continue
        yy, xx = ys[m], xs[m]
        tri[yy, xx] = t
        bary[yy, xx] = np.stack([l0[m], l1[m], l2[m]], axis=-1)
    return tri, bary


def dilate(img, filled, iters=24):
    """Grow filled texels into empty ones (mean of filled 8-neighbours), `iters` rings."""
    img = img.copy()
    filled = filled.copy()
    for _ in range(iters):
        if filled.all():
            break
        acc = np.zeros_like(img)
        cnt = np.zeros(filled.shape, dtype=F32)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                if dx == 0 and dy == 0:
                    continue
                sh_f = np.roll(np.roll(filled, dy, 0), dx, 1)
                sh_i = np.roll(np.roll(img, dy, 0), dx, 1)
                acc += sh_i * sh_f[..., None] if img.ndim == 3 else sh_i * sh_f
                cnt += sh_f
        grow = (~filled) & (cnt > 0)
        if img.ndim == 3:
            img[grow] = acc[grow] / cnt[grow][:, None]
        else:
            img[grow] = acc[grow] / cnt[grow]
        filled = filled | grow
    return img


def interp_corner(A, tri_ids, bary, key):
    loops = A["tl"][tri_ids]
    v = A[key][loops]  # (n, 3, d)
    return np.einsum("nk,nkd->nd", bary, v)


def interp_vertex(A, tri_ids, bary, values):
    vs = A["tv"][tri_ids]
    v = np.asarray(values)[vs]
    if v.ndim == 2:
        return np.einsum("nk,nk->n", bary, v)
    return np.einsum("nk,nkd->nd", bary, v)


def normalize(v):
    return v / np.maximum(np.linalg.norm(v, axis=-1, keepdims=True), 1e-9)


# ---- flow field -------------------------------------------------------------------------------------

def vertex_flow(obj, W, skel, sp, variant):
    """Per-vertex fur direction (unit, tangent to the surface)."""
    me = obj.data
    co = bl.verts_np(me).astype(np.float64)
    nv = np.empty(len(me.vertices) * 3, dtype=F32)
    me.vertices.foreach_get("normal", nv)
    nv = nv.reshape(-1, 3).astype(np.float64)
    heads = {b[0]: np.array(b[1]) for b in skel}
    tails = {b[0]: np.array(b[3]) for b in skel}
    f = np.zeros_like(co)
    for j, (name, head, parent, tail) in enumerate(skel):
        w = W[:, j]
        if not (w > 0).any():
            continue
        d = sp.flow_dir(name, heads[name], tails[name], co, nv, variant)
        f += w[:, None] * d
    f -= np.einsum("ij,ij->i", f, nv)[:, None] * nv
    f = normalize(f)
    # smooth along edges
    e = np.empty(len(me.edges) * 2, dtype=np.int64)
    me.edges.foreach_get("vertices", e)
    e = e.reshape(-1, 2)
    for _ in range(4):
        acc = f.copy()
        np.add.at(acc, e[:, 0], f[e[:, 1]])
        np.add.at(acc, e[:, 1], f[e[:, 0]])
        f = acc
        f -= np.einsum("ij,ij->i", f, nv)[:, None] * nv
        f = normalize(f)
    return f.astype(F32)


# ---- Cycles bakes -----------------------------------------------------------------------------------

def setup_cycles(samples=4, threads=2):
    scene = bpy.context.scene
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.render.threads_mode = "FIXED"
    scene.render.threads = threads
    return scene


def bake(lo, hi, kind, res, path, extrusion, ray, samples=4):
    """Bake NORMAL (tangent) or AO from hi onto lo's UVs; returns (res, res, 4) bottom-up float."""
    scene = setup_cycles(samples)
    img = bpy.data.images.new(f"bake_{kind}", res, res, alpha=False, float_buffer=True)
    img.colorspace_settings.name = "Non-Color"
    saved = list(lo.data.materials)
    mats_idx = np.empty(len(lo.data.polygons), dtype=np.int32)
    lo.data.polygons.foreach_get("material_index", mats_idx)
    mat = bpy.data.materials.new(f"Bake_{kind}")
    mat.use_nodes = True
    node = mat.node_tree.nodes.new("ShaderNodeTexImage")
    node.image = img
    mat.node_tree.nodes.active = node
    lo.data.materials.clear()
    lo.data.materials.append(mat)
    lo.data.polygons.foreach_set("material_index", np.zeros_like(mats_idx))
    bl.select_only([hi, lo], active=lo)
    b = scene.render.bake
    b.use_selected_to_active = True
    b.cage_extrusion = extrusion
    b.max_ray_distance = ray
    b.margin = 0
    if kind == "NORMAL":
        b.normal_space = "TANGENT"
        bpy.ops.object.bake(type="NORMAL", use_selected_to_active=True, cage_extrusion=extrusion,
                            max_ray_distance=ray, normal_space="TANGENT", margin=0)
    else:
        scene.world = scene.world or bpy.data.worlds.new("BakeWorld")
        bpy.ops.object.bake(type="AO", use_selected_to_active=True, cage_extrusion=extrusion,
                            max_ray_distance=ray, margin=0)
    px = np.empty(res * res * 4, dtype=F32)
    img.pixels.foreach_get(px)
    lo.data.materials.clear()
    for m in saved:
        lo.data.materials.append(m)
    lo.data.polygons.foreach_set("material_index", mats_idx)
    bpy.data.materials.remove(mat)
    bpy.data.images.remove(img)
    return px.reshape(res, res, 4)


# ---- the body maps ----------------------------------------------------------------------------------

def paint_body(sp, variant, lo, hi, W, bone_names, opts, log):
    res = opts.tex
    out_dir = os.path.join(opts.out, "tex")
    os.makedirs(out_dir, exist_ok=True)
    skel = sp.skeleton()
    flow = vertex_flow(lo, W, skel, sp, variant)
    A = mesh_arrays(lo)
    tri, bary = rasterize(A, res)
    filled = tri >= 0
    ids = tri[filled]
    b = bary[filled]
    P = interp_vertex(A, ids, b, A["co"]).astype(F32)
    N = normalize(interp_corner(A, ids, b, "nrm")).astype(F32)
    T = interp_corner(A, ids, b, "tan")
    T = normalize(T - np.einsum("ij,ij->i", T, N)[:, None] * N).astype(F32)
    sg = A["sgn"][A["tl"][ids][:, 0]]
    B = (np.cross(N, T) * sg[:, None]).astype(F32)
    Fd = interp_vertex(A, ids, b, flow)
    Fd = normalize(Fd - np.einsum("ij,ij->i", Fd, N)[:, None] * N).astype(F32)
    poly = A["tp"][ids]
    me = lo.data
    mat = np.empty(len(me.polygons), dtype=np.int32)
    me.polygons.foreach_get("material_index", mat)
    kind = np.empty(len(me.polygons), dtype=np.int32)
    me.attributes["hard_kind"].data.foreach_get("value", kind)
    dom_v = np.argmax(W, axis=1)
    dom = np.array(bone_names)[dom_v[A["tv"][ids][np.arange(len(ids)), np.argmax(b, axis=1)]]]
    texels = {
        "P": P, "N": N, "T": T, "B": B, "F": Fd, "region": mat[poly], "hard": kind[poly], "dom": dom,
        "W": interp_vertex(A, ids, b, W), "bone_names": bone_names,
    }
    log(f"rasterised {filled.sum()} texels ({100 * filled.mean():.0f} % of {res}^2)")
    paint = sp.paint(texels, variant, {"vnoise": vnoise, "fbm": fbm, "strands": strands, "sstep": sstep, "fur_relief": fur_relief,
                                       "region_colours": region_colours, "finish_rgb": finish_rgb})
    log("painted")
    ext = getattr(sp, "BAKE_EXTRUSION", 0.03)
    nb = bake(lo, hi, "NORMAL", res, None, ext, ext * 2, samples=2)
    log("normal baked")
    ao = bake(lo, hi, "AO", res, None, ext, ext * 2, samples=opts_samples(opts))
    log("ao baked")
    # ---- assemble -------------------------------------------------------------------------------
    nbt = nb[..., :3][filled] * 2 - 1  # tangent-space from the bake
    hard = texels["hard"] > 0
    nbt[hard] = (0, 0, 1)
    h = paint["height"]
    # strand relief: slope across the flow, in the tangent frame
    gT, gB = paint["slope_T"], paint["slope_B"]
    nrm = normalize(np.stack([nbt[:, 0] - gT, nbt[:, 1] - gB, nbt[:, 2]], axis=-1))
    aoval = ao[..., 0][filled]
    aoval[hard] = np.maximum(aoval[hard], 0.8)
    ao_k = paint.get("ao_strength", 0.6)
    occl = 1 - ao_k * (1 - np.clip(aoval, 0, 1)) ** 1.6  # soft: crevices darken, never to black
    rgb = np.clip(paint["rgb"] * occl[:, None], 0, 1)
    color = np.zeros((res, res, 4), dtype=F32)
    color[filled, :3] = rgb
    color[filled, 3] = paint["alpha"]
    normal = np.zeros((res, res, 4), dtype=F32)
    normal[filled, :3] = nrm * 0.5 + 0.5
    normal[filled, 3] = 1
    rough = np.zeros((res, res, 4), dtype=F32)
    rough[filled, :3] = paint["rough"][:, None]
    rough[filled, 3] = 1
    color = dilate(color, filled)
    normal = dilate(normal, filled)
    rough = dilate(rough, filled)
    normal[~(normal[..., 3] > 0)] = (0.5, 0.5, 1, 1)
    color[..., 3] = np.where(color[..., 3] < 0, 0, color[..., 3])
    paths = {}
    for name, arr, cs in (("color", color, "sRGB"), ("normal", normal, "Non-Color"), ("roughness", rough, "Non-Color")):
        p = os.path.join(out_dir, f"{variant}_body_{name}.png")
        if name != "color":
            arr = arr.copy()
            arr[..., 3] = 1
        bl.save_png(p, arr[::-1], colorspace=cs)
        paths[name] = p
    # a preview of what the engine shows with the stock tint (for review only, not uploaded)
    prev = color.copy()
    tint = paint["tint_by_region"]
    reg = np.zeros((res, res), dtype=np.int32)
    reg[filled] = texels["region"]
    reg = dilate(reg.astype(F32), filled).round().astype(np.int32)
    tcol = np.stack([tint[min(r, len(tint) - 1)] for r in range(len(tint))])[np.clip(reg, 0, len(tint) - 1)]
    prev[..., :3] = color[..., :3] * (1 - color[..., 3:4] + color[..., 3:4] * tcol)
    prev[..., 3] = 1
    pp = os.path.join(out_dir, f"{variant}_body_preview.png")
    bl.save_png(pp, prev[::-1])
    log("maps written")
    make_material(lo, paths, variant)
    return {"res": res, "maps": paths, "preview": pp, "coverage": round(float(filled.mean()), 3),
            "tint": {k: v for k, v in paint["tints_hex"].items()}}


def opts_samples(opts):
    return 8 if opts.quick else 24


def image_node(nt, path, colorspace, x, y):
    n = nt.nodes.new("ShaderNodeTexImage")
    n.image = bpy.data.images.load(os.path.abspath(path), check_existing=True)
    n.image.colorspace_settings.name = colorspace
    n.location = (x, y)
    return n


def principled_material(name, maps, alpha_from_color=False, emission=None):
    """Export-clean material: colour image -> Base Color, roughness image -> Roughness, normal image
    -> Normal Map -> Normal (what the FBX exporter and the Roblox importer read)."""
    mat = bpy.data.materials.get(name) or bpy.data.materials.new(name)
    mat.use_nodes = True
    nt = mat.node_tree
    for n in list(nt.nodes):
        if n.type not in ("BSDF_PRINCIPLED", "OUTPUT_MATERIAL"):
            nt.nodes.remove(n)
    bsdf = nt.nodes.get("Principled BSDF")
    c = image_node(nt, maps["color"], "sRGB", -600, 300)
    if not alpha_from_color:
        # alpha is the TintMask, not opacity: keep RGB where alpha is 0 (no premultiply round trip)
        c.image.alpha_mode = "CHANNEL_PACKED"
    nt.links.new(c.outputs["Color"], bsdf.inputs["Base Color"])
    if alpha_from_color:
        nt.links.new(c.outputs["Alpha"], bsdf.inputs["Alpha"])
    if "roughness" in maps:
        r = image_node(nt, maps["roughness"], "Non-Color", -600, 0)
        nt.links.new(r.outputs["Color"], bsdf.inputs["Roughness"])
    if "normal" in maps:
        n = image_node(nt, maps["normal"], "Non-Color", -600, -300)
        nm = nt.nodes.new("ShaderNodeNormalMap")
        nm.location = (-300, -300)
        nt.links.new(n.outputs["Color"], nm.inputs["Color"])
        nt.links.new(nm.outputs["Normal"], bsdf.inputs["Normal"])
    if emission is not None:
        bsdf.inputs["Emission Color"].default_value = (*emission, 1)
        bsdf.inputs["Emission Strength"].default_value = 0.0
    return mat


def make_material(lo, paths, variant):
    """Body and Pattern share one texture set (one UV atlas); each region gets its own material (one
    SurfaceAppearance each in Roblox, D22)."""
    mats = [principled_material(f"{n}", paths) for n in ("Body", "Pattern")]
    idx = np.empty(len(lo.data.polygons), dtype=np.int32)
    lo.data.polygons.foreach_get("material_index", idx)
    lo.data.materials.clear()
    for m in mats:
        lo.data.materials.append(m)
    lo.data.polygons.foreach_set("material_index", idx)
