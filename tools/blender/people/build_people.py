"""Build the townspeople end to end (headless bpy 5.2.x, 2 CPU threads):

  nice -n 10 taskset -c 2,3 /root/.cache/spicy-rodents/venv/bin/python -I tools/blender/people/build_people.py \
      --out build/people [--res 1024] [--outfits shirt,coat] [--no-fbx] [--quick]

Geometry: the fifteen R15 parts for both builds (sculpt.py meshed by mesher.py: the same topology and
UVs for both), the head, eight hair styles, two hats and the extras (coat tails, V-neck skin patch,
stethoscope). Textures: three atlases painted in 3-D (paint.py) for SurfaceAppearance AlphaMode Overlay:
  body_<outfit>_{color,normal,roughness}.png   one layout for every body part of both builds
  head_<face>_<expression>_color.png, head_{normal,roughness}.png
  headwear_{color,normal,roughness}.png        every hair style and hat
The normal maps hold the sculpt's finer detail (fingers, nostrils, ears) plus the painted relief
(seams, buttons, folds, strands). Writes into --out:
  fbx/body_<build>_<outfit>.fbx   the 14 body parts and the outfit's extras, in the rest pose, R15 names
  fbx/heads.fbx                   Head_<face>_<expression> (one mesh per face texture)
  fbx/headwear.fbx                Hair_<style>, Hat_<name>
  tex/*.png, manifest.json, people.blend (what render_people.py poses and renders)
"""
import argparse
import json
import os
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "heroes"))

import bpy  # noqa: E402
import numpy as np  # noqa: E402

import bl  # noqa: E402
import textures as tx  # noqa: E402

import assemble  # noqa: E402
import extras  # noqa: E402
import mesher  # noqa: E402
import paint  # noqa: E402
import sculpt  # noqa: E402
import spec  # noqa: E402

F32 = np.float32
T0 = time.time()

FBX_KW = dict(  # as tools/blender/heroes/hero.py: studs, Blender (x, y, z) -> Roblox (-x, z, y)
    use_selection=True,
    object_types={"MESH"},
    axis_forward="Z",
    axis_up="Y",
    apply_unit_scale=True,
    apply_scale_options="FBX_SCALE_ALL",
    bake_anim=False,
    path_mode="COPY",
    embed_textures=True,
    mesh_smooth_type="FACE",
    use_mesh_modifiers=False,
)


# hair and hats share two atlases
WEAR_ATLASES = {
    "a": ["Hair_short", "Hair_parted", "Hair_bob", "Hair_ponytail", "Hat_cap"],
    "b": ["Hair_curly", "Hair_bun", "Hair_balding", "Hair_long", "Hat_beret"],
}


def log(msg):
    print(f"[people {time.time() - T0:7.1f}s] {msg}", flush=True)


# ---- geometry ----------------------------------------------------------------------------------------

def sizes_of(comps):
    return {c.chart.name: c.chart.size for c in comps}


def build_meshes():
    """All meshes as arrays. Returns (body {build: {name: mesh}}, head, headwear {name: mesh}, details)."""
    body, metrics, details = {}, {}, {}
    for build in spec.BUILD_ORDER:
        b = spec.BUILDS[build]
        parts = sculpt.body_parts(b)
        out = {}
        for name, comps in parts.items():
            m = assemble.mesh_part(comps, metrics if build != spec.BUILD_ORDER[0] else None)
            if build == spec.BUILD_ORDER[0]:
                metrics.update(assemble.metrics_of(comps))
            m["sizes"] = sizes_of(comps)
            out[name] = m
        torso = parts["UpperTorso"][0].lo
        out["VNeck"] = extras.v_neck(torso)
        out["Stethoscope"] = extras.stethoscope(torso)
        body[build] = out
        if build == spec.BUILD_ORDER[0]:
            fine = sculpt.body_parts(b, detail=True)
            details = {name: assemble.detail_body(comps) for name, comps in fine.items()}
    hc = sculpt.head()
    head = assemble.mesh_part(hc)
    head["sizes"] = sizes_of(hc)
    details["Head"] = assemble.detail_body(sculpt.head(detail=True))
    wear = {}
    for style in spec.HAIR_ORDER:
        comps = sculpt.hair(style)
        m = assemble.mesh_part(comps)
        m["sizes"] = sizes_of(comps)
        wear["Hair_" + style] = m
        details["Hair_" + style] = assemble.detail_body(comps)
    for name in spec.HAT_ORDER:
        comps = sculpt.hat(name)
        m = assemble.mesh_part(comps)
        m["sizes"] = sizes_of(comps)
        wear["Hat_" + name] = m
        details["Hat_" + name] = assemble.detail_body(comps)
    return body, head, wear, details


def make_object(name, m, uv):
    """A mesh object whose origin is the centre of its bounding box (where Roblox puts a MeshPart's
    CFrame), with the sculpt's normals and the atlas UVs."""
    V = m["V"].astype(np.float64)
    centre = (V.min(axis=0) + V.max(axis=0)) / 2
    obj = bl.mesh_from_arrays(name, (V - centre).astype(F32), m["tris"].astype(np.int32))
    me = obj.data
    layer = me.uv_layers.new(name="UVMap")
    layer.data.foreach_set("uv", uv.reshape(-1).astype(F32))
    me.normals_split_custom_set_from_vertices(m["N"].tolist())
    obj.location = centre
    obj["centre"] = centre.tolist()
    obj["size"] = (V.max(axis=0) - V.min(axis=0)).tolist()
    obj["tris"] = len(m["tris"])
    return obj


# ---- texels ------------------------------------------------------------------------------------------

class Texels:
    """The texels of one object: where they are in the atlas and on the surface."""

    def __init__(self, obj, m, res):
        A = tx.mesh_arrays(obj)
        tri, bary = tx.rasterize(A, res)
        self.filled = tri >= 0
        ids, b = tri[self.filled], bary[self.filled]
        centre = np.array(obj["centre"], dtype=F32)
        self.P = (tx.interp_vertex(A, ids, b, A["co"]) + centre).astype(F32)
        N = tx.normalize(tx.interp_corner(A, ids, b, "nrm")).astype(F32)
        T = tx.interp_corner(A, ids, b, "tan")
        T = tx.normalize(T - np.einsum("ij,ij->i", T, N)[:, None] * N).astype(F32)
        sg = A["sgn"][A["tl"][ids][:, 0]]
        self.N, self.T = N, T
        self.B = (np.cross(N, T) * sg[:, None]).astype(F32)
        chart = np.asarray(m["chart"])[A["tp"][ids]]
        self.chart = chart
        self.charts = m["charts"]
        self.n = len(ids)


def bake(texels, painter, detail=None, eps=0.004, ao_scale=1.0):
    """Paint the texels: returns (rgba, tangent-space normal, roughness) per texel.
    painter(chart name, P, N) -> paint.Canvas. detail: the sculpt the normal map and AO come from."""
    n = texels.n
    rgba = np.zeros((n, 4), dtype=F32)
    nrm = np.zeros((n, 3), dtype=F32)
    rough = np.zeros(n, dtype=F32)
    for ci, name in enumerate(texels.charts):
        sel = np.flatnonzero(texels.chart == ci)
        if not len(sel):
            continue
        P, N, T, B = texels.P[sel], texels.N[sel], texels.T[sel], texels.B[sel]
        base = np.tile(np.array([[0, 0, 1]], dtype=F32), (len(sel), 1))
        ao = np.ones(len(sel), dtype=F32)
        if detail is not None:
            Pp = mesher.project(detail, P, steps=5)
            g = mesher.gradient(detail, Pp)
            ts = np.stack([np.einsum("ij,ij->i", g, T), np.einsum("ij,ij->i", g, B), np.einsum("ij,ij->i", g, N)], axis=1)
            ok = (ts[:, 2] > 0.35) & (np.linalg.norm(Pp - P, axis=1) < 0.06)
            base = np.where(ok[:, None], ts, base).astype(F32)
            # occlusion from the sculpt itself, measured off the true surface (not the flat triangle)
            Ps, Ns = np.where(ok[:, None], Pp, P), np.where(ok[:, None], g, N)
            occ = np.zeros(len(sel), dtype=F32)
            for d in (0.02, 0.05, 0.11):
                occ += np.clip((d - mesher.field(detail, Ps + Ns * F32(d))) / d, 0, 1) / 3
            ao = (1 - 0.75 * ao_scale * np.clip(occ, 0, 1) ** 1.3).astype(F32)
        c = painter(name, P, N)
        hT = (painter(name, P + T * F32(eps), N).h - painter(name, P - T * F32(eps), N).h) / (2 * eps)
        hB = (painter(name, P + B * F32(eps), N).h - painter(name, P - B * F32(eps), N).h) / (2 * eps)
        c.ao *= ao
        col, r = c.result()
        v = np.stack([base[:, 0] / base[:, 2] - hT, base[:, 1] / base[:, 2] - hB, np.ones(len(sel), dtype=F32)], axis=1)
        v[:, :2] = np.clip(v[:, :2], -2.5, 2.5)
        rgba[sel], nrm[sel], rough[sel] = col, tx.normalize(v), r
    return rgba, nrm, rough


class Atlas:
    def __init__(self, res):
        self.res = res
        self.color = np.zeros((res, res, 4), dtype=F32)
        self.normal = np.zeros((res, res, 3), dtype=F32)
        self.rough = np.zeros((res, res), dtype=F32)
        self.filled = np.zeros((res, res), dtype=bool)

    def put(self, texels, rgba, nrm, rough):
        f = texels.filled
        self.color[f], self.normal[f], self.rough[f] = rgba, nrm * 0.5 + 0.5, rough
        self.filled |= f

    def finish(self):
        """Bleed ink under the transparent texels next to it and fill the gutters."""
        col, f = self.color, self.filled
        a = col[..., 3] * f
        acc = np.zeros_like(col[..., :3])
        wsum = np.zeros_like(a)
        for dy in (-1, 0, 1):
            for dx in (-1, 0, 1):
                w = np.roll(np.roll(a, dy, 0), dx, 1)
                acc += np.roll(np.roll(col[..., :3], dy, 0), dx, 1) * w[..., None]
                wsum += w
        thin = (col[..., 3] < 0.1) & (wsum > 0.4)
        col[thin, :3] = acc[thin] / wsum[thin][:, None]
        self.color = tx.dilate(col, f, iters=8)
        self.normal = tx.dilate(self.normal, f, iters=8)
        self.normal[~(np.linalg.norm(self.normal, axis=-1) > 0.1)] = (0.5, 0.5, 1.0)
        self.rough = tx.dilate(self.rough, f, iters=8)
        self.rough[self.rough <= 0] = 0.8

    def save(self, base, which=("color", "normal", "roughness")):
        paths = {}
        res = self.res
        if "color" in which:
            paths["color"] = base + "_color.png"
            bl.save_png(paths["color"], self.color[::-1])
        if "normal" in which:
            paths["normal"] = base + "_normal.png"
            bl.save_png(paths["normal"], np.concatenate([self.normal, np.ones((res, res, 1), F32)], -1)[::-1], colorspace="Non-Color")
        if "roughness" in which:
            paths["roughness"] = base + "_roughness.png"
            r = self.rough
            bl.save_png(paths["roughness"], np.stack([r, r, r, np.ones_like(r)], -1)[::-1], colorspace="Non-Color")
        return paths


# ---- export ------------------------------------------------------------------------------------------

def set_material(obj, mat):
    obj.data.materials.clear()
    obj.data.materials.append(mat)


def export_fbx(path, named):
    """named: [(object, export name)]. The objects are renamed for the file and named back after."""
    old = [(o, o.name, o.data.name) for o, _n in named]
    for o, n in named:
        o.name = n
        o.data.name = n
    bl.select_only([o for o, _n in named])
    bpy.ops.export_scene.fbx(filepath=path, **FBX_KW)
    for o, n, dn in old:
        o.name = n
        o.data.name = dn
    return os.path.getsize(path)


def r3(v):
    return [round(float(x), 4) + 0.0 for x in v]


def rbx(p):
    return r3(spec.to_roblox(p))


def rbx_size(s):
    return r3((s[0], s[2], s[1]))


# ---- main --------------------------------------------------------------------------------------------

def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--out", default="build/people")
    ap.add_argument("--res", type=int, default=1024)
    ap.add_argument("--outfits", default="all")
    ap.add_argument("--no-fbx", action="store_true")
    ap.add_argument("--quick", action="store_true", help="512 px maps (a 90-second build for looking at shapes)")
    opts = ap.parse_args(argv)
    out = os.path.abspath(opts.out)
    res = 512 if opts.quick else opts.res
    outfits = spec.OUTFIT_ORDER if opts.outfits == "all" else [o for o in opts.outfits.split(",") if o]
    tex_dir, fbx_dir = os.path.join(out, "tex"), os.path.join(out, "fbx")
    os.makedirs(tex_dir, exist_ok=True)
    os.makedirs(fbx_dir, exist_ok=True)
    bl.reset_scene()
    scene = bpy.context.scene
    scene.render.threads_mode = "FIXED"
    scene.render.threads = 2

    body, head, wear, details = build_meshes()
    ref = spec.BUILD_ORDER[0]
    log("meshes cast")

    # ---- atlases -----------------------------------------------------------------------------------
    sizes = {}
    for m in body[ref].values():
        sizes.update(m["sizes"])
    body_rects, body_density = assemble.pack(sizes, res, gutter=max(4, res // 170))
    head_rects, head_density = assemble.pack(head["sizes"], res, gutter=max(4, res // 170))
    wear_rects, wear_density, wear_atlas = {}, {}, {}
    for key, names in WEAR_ATLASES.items():
        wsizes = {}
        for n in names:
            wsizes.update(wear[n]["sizes"])
            wear_atlas[n] = key
        rects, wear_density[key] = assemble.pack(wsizes, res, gutter=max(4, res // 170))
        wear_rects.update(rects)
    log(f"atlases: body {body_density:.0f} px/stud, head {head_density:.0f}, headwear {wear_density}")

    # ---- objects -----------------------------------------------------------------------------------
    objs = {}  # (build, R15 or extra name) -> object
    src = {}  # object name -> (mesh arrays, short name)
    for build in spec.BUILD_ORDER:
        for name, m in body[build].items():
            uv = assemble.atlas_uv(m, body_rects)
            if name in spec.SIDED or name == "CoatTail":
                for side, mm in (("Left", m), ("Right", assemble.mirror(m))):
                    full = side + name
                    objs[(build, full)] = make_object(f"{build}.{full}", mm, assemble.atlas_uv(mm, body_rects))
                    src[f"{build}.{full}"] = (mm, name)
            else:
                objs[(build, name)] = make_object(f"{build}.{name}", m, uv)
                src[f"{build}.{name}"] = (m, name)
    head_obj = make_object("Head", head, assemble.atlas_uv(head, head_rects))
    wear_objs = {name: make_object(name, m, assemble.atlas_uv(m, wear_rects)) for name, m in wear.items()}
    log(f"{len(objs) + 1 + len(wear_objs)} objects")

    # ---- textures ----------------------------------------------------------------------------------
    textures = {}
    paint_parts = [n for n in body[ref] if True]
    tex_cache = {}
    for name in paint_parts:
        key = (ref, "Left" + name) if (name in spec.SIDED or name == "CoatTail") else (ref, name)
        o = objs[key]
        tex_cache[name] = Texels(o, src[o.name][0], res)
    log(f"body texels: {sum(t.n for t in tex_cache.values())}")
    for outfit in outfits:
        at = Atlas(res)
        for name, t in tex_cache.items():
            det = details.get(name)
            rgba, nrm, rough = bake(t, lambda ch, P, N: paint.body(ch, P, N, outfit), det)
            at.put(t, rgba, nrm, rough)
        at.finish()
        textures["body_" + outfit] = at.save(os.path.join(tex_dir, "body_" + outfit))
        log(f"painted body_{outfit}")
    ht = Texels(head_obj, head, res)
    faces = [(f, e) for f in spec.FACES for e in spec.EXPRESSIONS]
    for i, (face, expr) in enumerate(faces):
        at = Atlas(res)
        rgba, nrm, rough = bake(ht, lambda ch, P, N: paint.head(ch, P, N, expr, face), details["Head"], ao_scale=0.45)
        at.put(ht, rgba, nrm, rough)
        at.finish()
        key = f"head_{face}_{expr}"
        textures[key] = at.save(os.path.join(tex_dir, key), which=("color",))
        if i == 0:
            shared = at.save(os.path.join(tex_dir, "head"), which=("normal", "roughness"))
        textures[key].update(shared)
        log(f"painted {key}")
    for key, names in WEAR_ATLASES.items():
        at = Atlas(res)
        for name in names:
            t = Texels(wear_objs[name], wear[name], res)
            kind, which = name.split("_", 1)
            fn = (lambda ch, P, N: paint.hair(ch, P, N, which)) if kind == "Hair" else (lambda ch, P, N: paint.hat(ch, P, N, which))
            rgba, nrm, rough = bake(t, fn, details[name], ao_scale=0.5)
            at.put(t, rgba, nrm, rough)
        at.finish()
        textures["headwear_" + key] = at.save(os.path.join(tex_dir, "headwear_" + key))
        log(f"painted headwear_{key}")

    # ---- materials ---------------------------------------------------------------------------------
    mats = {key: tx.principled_material(key, maps) for key, maps in textures.items()}
    for mat in mats.values():
        mat.use_fake_user = True  # people.blend keeps every outfit's material
    for (build, name), o in objs.items():
        set_material(o, mats["body_" + outfits[0]])
    set_material(head_obj, mats[f"head_{faces[0][0]}_{faces[0][1]}"])
    for n, o in wear_objs.items():
        set_material(o, mats["headwear_" + wear_atlas[n]])

    # ---- manifest ----------------------------------------------------------------------------------
    centres = {"HumanoidRootPart": np.array([0.0, 0.0, spec.ROOT_HEIGHT])}
    part_info = {}
    for build in spec.BUILD_ORDER:
        info = {}
        for (bd, name), o in objs.items():
            if bd != build:
                continue
            c = np.array(o["centre"])
            info[name] = {"center": rbx(c), "size": rbx_size(o["size"]), "tris": int(o["tris"])}
        info["Head"] = {"center": rbx(head_obj["centre"]), "size": rbx_size(head_obj["size"]), "tris": int(head_obj["tris"])}
        part_info[build] = info
    joints = {}
    for build in spec.BUILD_ORDER:
        js = {}
        for jname, p0, p1, pos in spec.JOINTS:
            c0 = np.zeros(3) if p0 == "HumanoidRootPart" else np.array(part_info[build][p0]["center"])
            c1 = np.array(part_info[build][p1]["center"])
            js[jname] = {"part0": p0, "part1": p1, "position": r3(pos), "c0": r3(np.array(pos) - c0), "c1": r3(np.array(pos) - c1)}
            if jname in spec.STOCK_BLOCK_RIG:
                js[jname]["stockBlockRig"] = r3(spec.STOCK_BLOCK_RIG[jname])
        joints[build] = js
    attachments = {}
    for build in spec.BUILD_ORDER:
        at_ = {}
        for aname, part, pos in spec.ATTACHMENTS:
            c = np.array(part_info[build][part]["center"])
            at_[aname] = {"part": part, "position": r3(np.array(pos) - c), "rootRelative": r3(pos)}
        attachments[build] = at_
    extras_info = {}
    for build in spec.BUILD_ORDER:
        ex = {}
        for ename, e in spec.EXTRAS.items():
            c = np.array(part_info[build][ename]["center"])
            pc = np.array(part_info[build][e["part"]]["center"])
            ex[ename] = {"weldTo": e["part"], "offset": r3(c - pc), "tint": e["tint"], "note": e["note"]}
        extras_info[build] = ex
    head_c = np.array(part_info[ref]["Head"]["center"])
    headwear = {}
    for name, o in wear_objs.items():
        kind, which = name.split("_", 1)
        meta = spec.HAIR[which] if kind == "Hair" else spec.HATS[which]
        c = np.array(rbx(o["centre"]))
        headwear[name] = {
            "kind": kind.lower(), "label": meta["label"], "tris": int(o["tris"]), "size": rbx_size(o["size"]), "center": r3(c),
            "weldTo": "Head", "offset": r3(c - head_c), "tint": "hair" if kind == "Hair" else meta["tint"],
            "textures": {k: os.path.relpath(v, out) for k, v in textures["headwear_" + wear_atlas[name]].items()},
        }
        if kind == "Hair":
            headwear[name]["underCap"] = meta["under_cap"]
    body_names = [n for n in spec.PARTS if n != "Head"]

    # ---- FBX ---------------------------------------------------------------------------------------
    files = {}
    if not opts.no_fbx:
        for build in spec.BUILD_ORDER:
            for outfit in outfits:
                names = body_names + spec.OUTFITS[outfit]["extras"]
                named = []
                for n in names:
                    o = objs[(build, n)]
                    set_material(o, mats["body_" + outfit])
                    named.append((o, n))
                p = os.path.join(fbx_dir, f"body_{build}_{outfit}.fbx")
                size = export_fbx(p, named)
                files[f"body_{build}_{outfit}"] = {"path": os.path.relpath(p, out), "bytes": size, "objects": names,
                                                   "tris": sum(int(objs[(build, n)]["tris"]) for n in names)}
            log(f"exported {build} bodies")
        heads = []
        for face, expr in faces:
            o = head_obj.copy()
            o.data = head_obj.data.copy()
            scene.collection.objects.link(o)
            set_material(o, mats[f"head_{face}_{expr}"])
            heads.append((o, f"Head_{face}_{expr}"))
        p = os.path.join(fbx_dir, "heads.fbx")
        files["heads"] = {"path": os.path.relpath(p, out), "bytes": export_fbx(p, heads), "objects": [n for _o, n in heads],
                          "tris": int(head_obj["tris"])}
        for o, _n in heads:
            me = o.data
            bpy.data.objects.remove(o)
            bpy.data.meshes.remove(me)
        p = os.path.join(fbx_dir, "headwear.fbx")
        files["headwear"] = {"path": os.path.relpath(p, out), "bytes": export_fbx(p, [(o, n) for n, o in wear_objs.items()]),
                             "objects": list(wear_objs)}
        log("exported heads and headwear")
        for (build, name), o in objs.items():
            set_material(o, mats["body_" + outfits[0]])

    pal = spec.load_palettes()
    worst = {}
    for build in spec.BUILD_ORDER:
        base = sum(part_info[build][n]["tris"] for n in spec.PARTS)
        hair_max = max(v["tris"] for v in headwear.values() if v["kind"] == "hair")
        hat_max = max(v["tris"] for v in headwear.values() if v["kind"] == "hat")
        ex_max = max(sum(part_info[build][e]["tris"] for e in spec.OUTFITS[o]["extras"]) for o in spec.OUTFIT_ORDER)
        worst[build] = {"body": base, "largestHair": hair_max, "largestHat": hat_max, "largestExtras": ex_max,
                        "worstCase": base + hair_max + hat_max + ex_max}
    manifest = {
        "format": "spicy-people/1",
        "generated": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "blender": bpy.app.version_string,
        "units": "studs; positions in Roblox axes (+Y up, the person faces -Z); 'rootRelative' and 'center' are relative to the HumanoidRootPart's centre in the rest pose",
        "notes": [
            "Every mesh is rigid and exported in the rest pose, so a MeshPart's position in the loaded Model is its 'center'. Build the rig by creating one Motor6D per joint (Part0, Part1, C0 = CFrame.new(c0), C1 = CFrame.new(c1)), or by adding <Joint>RigAttachment pairs at those offsets and calling Humanoid:BuildRigFromAttachments.",
            f"Joint names, hierarchy and positions are the stock R15 block rig's, except that the elbows and wrists hang under the shoulder (x = {spec.ARM_X_ELBOW} and {spec.ARM_X_WRIST}) instead of on the block arm's centre line (x = 1.5, kept in 'stockBlockRig'): a round arm must pivot inside its own shoulder ball. The stock animations only rotate these joints.",
            "HumanoidRootPart is not a mesh: a 2 x 2 x 1 transparent part at the origin; HipHeight 2 (the soles are 3 studs under its centre).",
            "Regions: every MeshPart's SurfaceAppearance uses AlphaMode Overlay (the importer's default). Set MeshPart.Color to the palette colour named by 'tints' (a RolePalettes look key: skin, shirt, pants, hair, cap; or a fixed '#rrggbb'); the colour map only darkens, lightens and inks detail on top.",
            "Left and right limbs share texture space (mirrored UVs); both builds share every UV layout, so any body_<build>_<outfit> SurfaceAppearance fits either build, and any Head_<face>_<expression> SurfaceAppearance fits the head (swap the SurfaceAppearance to change expression).",
            "Extras are welded to the R15 part named by 'weldTo' at 'offset' (centre to centre). Hair and hats are welded to Head the same way.",
        ],
        "rootPart": {"name": "HumanoidRootPart", "size": [2, 2, 1], "hipHeight": 2.0, "height": spec.HEIGHT},
        "builds": {
            build: {"parts": {n: part_info[build][n] for n in spec.PARTS}, "joints": joints[build], "attachments": attachments[build],
                    "extras": {e: dict(part_info[build][e], **extras_info[build][e]) for e in spec.EXTRAS},
                    "triangles": worst[build]}
            for build in spec.BUILD_ORDER
        },
        "outfits": {
            o: {"label": spec.OUTFITS[o]["label"], "textures": {k: os.path.relpath(v, out) for k, v in textures.get("body_" + o, {}).items()},
                "tints": spec.region_tints(o), "extras": spec.OUTFITS[o]["extras"],
                "fbx": {b: f"body_{b}_{o}" for b in spec.BUILD_ORDER}}
            for o in spec.OUTFIT_ORDER
        },
        "heads": {
            "tint": "skin", "expressions": spec.EXPRESSIONS, "faces": spec.FACES, "fbx": "heads",
            "objects": {f"Head_{f}_{e}": {"face": f, "expression": e,
                                         "textures": {k: os.path.relpath(v, out) for k, v in textures[f"head_{f}_{e}"].items()}}
                        for f, e in faces},
        },
        "headwear": {"fbx": "headwear",
                     "hair": [n for n in headwear if headwear[n]["kind"] == "hair"],
                     "hats": [n for n in headwear if headwear[n]["kind"] == "hat"], "items": headwear},
        "roles": {r: {"outfits": spec.ROLES[r]["outfits"], "face": spec.ROLES[r]["face"],
                      "hat": ("Hat_" + spec.ROLES[r]["hat"]) if spec.ROLES[r]["hat"] else None,
                      "hair": ["Hair_" + h for h in spec.ROLES[r]["hair"]], "palette": pal["roles"][r]}
                  for r in spec.ROLE_ORDER},
        "palettes": {"source": "src/shared/Avatar/RolePalettes.luau", "skins": pal["SKINS"], "hair": pal["HAIR"], "pants": pal["PANTS"]},
        "atlases": {"resolution": res, "body": {"texelsPerStud": round(body_density, 1), "charts": {k: r3(v) for k, v in body_rects.items()}},
                    "head": {"texelsPerStud": round(head_density, 1), "charts": {k: r3(v) for k, v in head_rects.items()}},
                    "headwear": {"texelsPerStud": {k: round(v, 1) for k, v in wear_density.items()},
                                 "charts": {k: r3(v) for k, v in wear_rects.items()}}},
        "files": files,
    }
    with open(os.path.join(out, "manifest.json"), "w") as fh:
        json.dump(manifest, fh, indent=1)
    scene["people_manifest"] = json.dumps(manifest)
    bpy.ops.wm.save_as_mainfile(filepath=os.path.join(out, "people.blend"))
    for b in spec.BUILD_ORDER:
        log(f"{b}: {worst[b]}")
    log("done")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]))
