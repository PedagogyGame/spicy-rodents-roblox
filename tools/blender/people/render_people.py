"""Review renders of the townspeople (Cycles CPU, 2 threads), lit like the game's golden afternoon.

  nice -n 10 taskset -c 2,3 /root/.cache/spicy-rodents/venv/bin/python -I tools/blender/people/render_people.py \
      --blend build/people/people.blend --out build/people/renders [--shots lineup_front,faces] [--samples 96] [--scale 1.0]
  python3 -I tools/blender/people/sheets.py --dir build/people/renders --out docs/renders/people

Every person is assembled the way the game will do it: the build's MeshParts, each tinted with its
palette colour under the outfit's Overlay texture (base = lerp(part colour, texture rgb, texture
alpha)), and posed by rotating the parts about the manifest's joints as Motor6D does (pose.py).
Shots (PNG plus a JSON of label positions for sheets.py): lineup_front, lineup_back, face_calm,
face_worried, face_frightened, run, sit, scale, hair.
"""
import argparse
import json
import math
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
sys.path.insert(0, os.path.join(HERE, "..", "heroes"))

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from bpy_extras.object_utils import world_to_camera_view  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import bl  # noqa: E402

import pose as posing  # noqa: E402
import spec  # noqa: E402


def lin(hexs):
    return tuple(bl.srgb_to_lin(bl.hexrgb(hexs)).tolist()) + (1.0,)


def prep_materials():
    """Base colour = lerp(the object's colour, the map's rgb, the map's alpha): what Overlay shows."""
    for mat in bpy.data.materials:
        if not mat.use_nodes:
            continue
        nt = mat.node_tree
        bsdf = nt.nodes.get("Principled BSDF")
        link = next((l for l in nt.links if l.to_node == bsdf and l.to_socket.name == "Base Color"), None)
        if link is None or link.from_node.type != "TEX_IMAGE":
            continue
        img = link.from_node
        info = nt.nodes.new("ShaderNodeObjectInfo")
        mix = nt.nodes.new("ShaderNodeMix")
        mix.data_type = "RGBA"
        mix.blend_type = "MIX"
        nt.links.new(img.outputs["Alpha"], mix.inputs["Factor"])
        nt.links.new(info.outputs["Color"], mix.inputs["A"])
        nt.links.new(img.outputs["Color"], mix.inputs["B"])
        nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])


class Stage:
    def __init__(self, manifest):
        self.m = manifest
        self.scene = bpy.context.scene
        self.made = []
        self.pal = spec.load_palettes()

    def spawn(self, src_name, mat_name, tint, matrix):
        src = bpy.data.objects[src_name]
        o = src.copy()
        self.scene.collection.objects.link(o)
        o.material_slots[0].link = "OBJECT"
        o.material_slots[0].material = bpy.data.materials[mat_name]
        o.color = lin(tint)
        o.hide_render = False
        o.matrix_world = Matrix(matrix.tolist())
        self.made.append(o)
        return o

    def person(self, role, index, build, outfit=None, hair=None, hat="role", expression="calm", pose="rest",
               at=(0.0, 0.0), yaw=0.0, lift=None, look=None):
        """Assemble and pose one person; returns {part: object}. yaw (deg) turns them about +Z; they
        stand with their lowest sole on the ground unless lift is given."""
        m = self.m
        r = spec.ROLES[role]
        outfit = outfit or r["outfits"][0]
        lk = dict(spec.look(role, index, self.pal))
        lk.update(look or {})
        tints = spec.region_tints(outfit)
        bm = m["builds"][build]
        pose_ = posing.POSES[pose] if isinstance(pose, str) else pose
        world = posing.fk(bm["joints"], pose_)

        def colour(key):
            return key if key.startswith("#") else lk[key]

        place = np.eye(4)
        a = math.radians(yaw)
        place[:3, :3] = [[math.cos(a), -math.sin(a), 0], [math.sin(a), math.cos(a), 0], [0, 0, 1]]
        place[:3, 3] = (at[0], at[1], spec.ROOT_HEIGHT)
        mats = {}
        for part in spec.PARTS:
            mats[part] = place @ posing.to_blender(world[part])  # a part's CFrame is its centre
        for e in spec.OUTFITS[outfit]["extras"]:
            info = bm["extras"][e]
            mats[e] = place @ posing.to_blender(world[info["weldTo"]] @ posing.translation(info["offset"]))
        wear = []
        if hair:
            wear.append("Hair_" + hair)
        hat_name = (("Hat_" + r["hat"]) if r["hat"] else None) if hat == "role" else (("Hat_" + hat) if hat else None)
        if hat_name:
            wear.append(hat_name)
        for w in wear:
            mats[w] = place @ posing.to_blender(world["Head"] @ posing.translation(m["headwear"]["items"][w]["offset"]))
        # the lowest sole on the ground
        if lift is None:
            low = 1e9
            for part in ("LeftFoot", "RightFoot"):
                src = bpy.data.objects[f"{build}.{part}"]
                v = np.array([x.co[:] for x in src.data.vertices])
                low = min(low, float((v @ mats[part][:3, :3].T + mats[part][:3, 3])[:, 2].min()))
            lift = -low
        objs = {}
        for name, mx in mats.items():
            mx = mx.copy()
            mx[2, 3] += lift
            if name == "Head":
                objs[name] = self.spawn("Head", f"head_{r['face']}_{expression}", lk["skin"], mx)
            elif name.startswith(("Hair_", "Hat_")):
                item = m["headwear"]["items"][name]
                objs[name] = self.spawn(name, os.path.basename(item["textures"]["color"])[: -len("_color.png")], colour(item["tint"]), mx)
            else:
                objs[name] = self.spawn(f"{build}.{name}", "body_" + outfit, colour(tints[name]), mx)
        return objs

    def clear(self):
        for o in self.made:
            bpy.data.objects.remove(o)
        self.made = []


# ---- the set ---------------------------------------------------------------------------------------

def daylight(scene):
    """The game's golden afternoon (World/LightingPreset): a warm, fairly low sun, a soft sky, paving."""
    world = bpy.data.worlds.new("Sky")
    scene.world = world
    world.use_nodes = True
    nt = world.node_tree
    bg = nt.nodes.get("Background")
    sky = nt.nodes.new("ShaderNodeTexSky")
    for kind in ("MULTIPLE_SCATTERING", "NISHITA"):
        try:
            sky.sky_type = kind
            break
        except TypeError:
            pass
    for attr, val in (("sun_elevation", math.radians(38)), ("sun_rotation", math.radians(140)), ("altitude", 50.0),
                      ("air_density", 1.0), ("dust_density", 2.0), ("sun_disc", False)):
        if hasattr(sky, attr):
            try:
                setattr(sky, attr, val)
            except Exception:
                pass
    nt.links.new(sky.outputs["Color"], bg.inputs["Color"])
    bg.inputs["Strength"].default_value = 0.2
    sd = bpy.data.lights.new("Sun", "SUN")
    sd.energy = 5.6
    sd.angle = math.radians(3.0)
    sd.color = (1.0, 0.85, 0.64)
    sun = bpy.data.objects.new("Sun", sd)
    scene.collection.objects.link(sun)
    fd = bpy.data.lights.new("Bounce", "SUN")  # light bounced off the ground into the shadows
    fd.energy = 0.5
    fd.angle = math.radians(60)
    fd.color = (1.0, 0.9, 0.78)
    fill = bpy.data.objects.new("Bounce", fd)
    scene.collection.objects.link(fill)
    bpy.ops.mesh.primitive_plane_add(size=20000, location=(0, 0, 0))
    g = bpy.context.active_object
    g.name = "Ground"
    gm = bpy.data.materials.new("Paving")
    gm.use_nodes = True
    gnt = gm.node_tree
    gb = gnt.nodes.get("Principled BSDF")
    coord = gnt.nodes.new("ShaderNodeTexCoord")
    brick = gnt.nodes.new("ShaderNodeTexBrick")
    brick.inputs["Scale"].default_value = 0.28
    brick.inputs["Mortar Size"].default_value = 0.012
    brick.inputs["Color1"].default_value = (0.50, 0.43, 0.35, 1)
    brick.inputs["Color2"].default_value = (0.43, 0.38, 0.31, 1)
    brick.inputs["Mortar"].default_value = (0.22, 0.2, 0.17, 1)
    noise = gnt.nodes.new("ShaderNodeTexNoise")
    noise.inputs["Scale"].default_value = 1.4
    noise.inputs["Detail"].default_value = 8.0
    mixn = gnt.nodes.new("ShaderNodeMix")
    mixn.data_type = "RGBA"
    mixn.blend_type = "MULTIPLY"
    mixn.inputs["Factor"].default_value = 0.55
    bump = gnt.nodes.new("ShaderNodeBump")
    bump.inputs["Strength"].default_value = 0.35
    gnt.links.new(coord.outputs["Object"], brick.inputs["Vector"])
    gnt.links.new(coord.outputs["Object"], noise.inputs["Vector"])
    gnt.links.new(brick.outputs["Color"], mixn.inputs["A"])
    gnt.links.new(noise.outputs["Fac"], mixn.inputs["B"])
    gnt.links.new(mixn.outputs["Result"], gb.inputs["Base Color"])
    gnt.links.new(noise.outputs["Fac"], bump.inputs["Height"])
    gnt.links.new(bump.outputs["Normal"], gb.inputs["Normal"])
    gb.inputs["Roughness"].default_value = 0.92
    g.data.materials.append(gm)
    return sun, fill


def aim_sun(sun, fill, az, el=38):
    """az: where the sun stands, degrees from +X toward +Y."""
    a, e = math.radians(az), math.radians(el)
    d = Vector((math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e)))
    sun.rotation_euler = d.to_track_quat("Z", "Y").to_euler()
    f = Vector((-d.x, -d.y, 0.45)).normalized()
    fill.rotation_euler = f.to_track_quat("Z", "Y").to_euler()


def setup_render(scene, samples, threads=2):
    scene.render.engine = "CYCLES"
    scene.cycles.device = "CPU"
    scene.cycles.samples = samples
    scene.cycles.use_adaptive_sampling = True
    scene.cycles.adaptive_threshold = 0.03
    scene.cycles.use_denoising = True
    scene.cycles.max_bounces = 5
    scene.cycles.diffuse_bounces = 3
    scene.cycles.glossy_bounces = 2
    scene.render.threads_mode = "FIXED"
    scene.render.threads = threads
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = "PNG"
    scene.render.image_settings.color_mode = "RGB"
    scene.render.film_transparent = False
    scene.view_settings.view_transform = "AgX"
    try:
        scene.view_settings.look = "AgX - Medium High Contrast"
    except TypeError:
        pass
    scene.view_settings.exposure = -0.55


def camera(scene):
    cd = bpy.data.cameras.new("Cam")
    cd.clip_end = 2000
    cam = bpy.data.objects.new("Cam", cd)
    scene.collection.objects.link(cam)
    scene.camera = cam
    return cam


def place(cam, target, dist, az, el, lens):
    """az: degrees from +X toward +Y of the camera's position round the target."""
    a, e = math.radians(az), math.radians(el)
    cam.data.lens = lens
    cam.location = Vector(target) + Vector((math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e))) * dist
    cam.rotation_euler = (Vector(target) - cam.location).to_track_quat("-Z", "Y").to_euler()


def project(scene, cam, p):
    bpy.context.view_layer.update()
    u = world_to_camera_view(scene, cam, Vector(p))
    return [round(u.x * scene.render.resolution_x, 1), round((1 - u.y) * scene.render.resolution_y, 1)]


# ---- the cast --------------------------------------------------------------------------------------

LINEUP = [  # role, palette index, build, outfit, hair, pose
    ("townsperson", 2, "slim", "shirt", "parted", "walk"),
    ("doctor", 5, "broad", "coat", "balding", "pass2"),
    ("nurse", 3, "slim", "scrubs", "bun", "walk2"),
    ("guard", 6, "broad", "guard", "short", "walk"),
    ("orderly", 1, "broad", "scrubs", "curly", "pass"),
    ("officer", 4, "slim", "police", "ponytail", "walk2"),
    ("driver", 7, "broad", "police", "short", "walk"),
    ("mime", 8, "slim", "mime", "bob", "pass2"),
]
LABEL = {"townsperson": "Townsperson", "doctor": "Doctor", "nurse": "Nurse", "guard": "Hospital guard", "orderly": "Orderly",
         "officer": "Police officer", "driver": "Police driver", "mime": "Mime"}


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--blend", default="build/people/people.blend")
    ap.add_argument("--out", default="build/people/renders")
    ap.add_argument("--shots", default="all")
    ap.add_argument("--samples", type=int, default=96)
    ap.add_argument("--scale", type=float, default=1.0, help="resolution scale for previews")
    opts = ap.parse_args(argv)
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(opts.blend))
    scene = bpy.context.scene
    manifest = json.loads(scene["people_manifest"])
    os.makedirs(opts.out, exist_ok=True)
    for o in list(scene.collection.objects):  # the source meshes stay out of the picture
        o.hide_render = True
    prep_materials()
    sun, fill = daylight(scene)
    cam = camera(scene)
    setup_render(scene, opts.samples)
    st = Stage(manifest)
    want = None if opts.shots == "all" else set(opts.shots.split(","))

    def shoot(name, res, labels=None, extra=None):
        scene.render.resolution_x, scene.render.resolution_y = int(res[0] * opts.scale), int(res[1] * opts.scale)
        meta = {"labels": [{"text": t, "at": project(scene, cam, p)} for t, p in (labels or [])], "size": [scene.render.resolution_x, scene.render.resolution_y]}
        meta.update(extra or {})
        scene.render.filepath = os.path.join(opts.out, name + ".png")
        bpy.ops.render.render(write_still=True)
        with open(os.path.join(opts.out, name + ".json"), "w") as fh:
            json.dump(meta, fh, indent=1)
        print(f"shot {name}", flush=True)
        for o in st.made:
            o.hide_render = True
        st.clear()

    # the eight roles, mid-stride, from the front and from behind
    for name, cam_az, sun_az, yaw in (("lineup_front", -90, -128, 22), ("lineup_back", 90, 52, 22)):
        if want and name not in want:
            continue
        gap = 2.5
        labels = []
        for i, (role, idx, build, outfit, hair, pz) in enumerate(LINEUP):
            x = (i - (len(LINEUP) - 1) / 2) * gap * (1 if cam_az < 0 else -1)
            st.person(role, idx, build, outfit, hair, pose=pz, at=(x, 0.0), yaw=yaw)
            labels.append((LABEL[role], (x, 0, 0)))
        aim_sun(sun, fill, sun_az)
        place(cam, (0, 0, 2.62), 60, cam_az, 7, 100)
        shoot(name, (1600, 560), labels)

    # three faces
    for expr, role, idx, build, outfit, hair, pz, az, dist, aim in (
        ("calm", "townsperson", 4, "slim", "jacket", "long", "stand", -72, 7.4, 4.72),
        ("worried", "doctor", 3, "broad", "coat", "short", "stand", -104, 7.4, 4.72),
        ("frightened", "nurse", 6, "slim", "scrubs", "curly", "startled", -80, 9.4, 4.5),  # wider: the raised hands
    ):
        name = "face_" + expr
        if want and name not in want:
            continue
        st.person(role, idx, build, outfit, hair, expression=expr, pose=pz)
        aim_sun(sun, fill, -128 if az > -90 else -52, 40)
        place(cam, (0, -0.08, aim), dist, az, 3, 100)
        shoot(name, (533, 640), [(expr.capitalize(), (0, 0, aim - 0.82 * dist / 7.4))])

    if not want or "run" in want:
        st.person("townsperson", 6, "slim", "jacket", "ponytail", pose="run", yaw=0, look={"shirt": "#9b4a4a"})
        aim_sun(sun, fill, -140)
        place(cam, (0.0, -0.2, 2.75), 13.5, -30, 5, 75)
        shoot("run", (800, 760), [("Running: every joint turned about its Motor6D pivot", (0, 0, 0))])

    if not want or "sit" in want:
        bpy.ops.mesh.primitive_cube_add(size=1, location=(0, 0.12, 0.43))
        bench = bpy.context.active_object
        bench.scale = (3.4, 1.3, 0.86)
        bm_ = bpy.data.materials.new("Bench")
        bm_.use_nodes = True
        bm_.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.2, 0.12, 0.07, 1)
        bm_.node_tree.nodes["Principled BSDF"].inputs["Roughness"].default_value = 0.7
        bench.data.materials.append(bm_)
        st.made.append(bench)
        st.person("doctor", 3, "broad", "coat", "parted", pose="sit", at=(0, 0), yaw=0)
        aim_sun(sun, fill, -125)
        place(cam, (0.0, -0.3, 2.05), 12.5, -52, 9, 75)
        shoot("sit", (800, 760), [("Sitting", (0.9, -1.9, 0))])

    if not want or "scale" in want:
        sx = -4.2
        for i, (build, yaw_) in enumerate((("slim", 0), ("slim", 90), ("slim", 180), ("broad", 0), ("broad", 90))):
            st.person("townsperson", 3 if build == "slim" else 5, build, "shirt" if build == "slim" else "jacket",
                      "bob" if build == "slim" else "short", pose="stand", at=(sx + 2.9 + 2.9 * i, 0), yaw=yaw_,
                      look=None if build == "slim" else {"shirt": "#6d8a6a"})
        for i in range(11):  # a 5.5-stud staff, banded every half stud
            bpy.ops.mesh.primitive_cube_add(size=1, location=(sx - 2.9 + 1.2, 0, 0.25 + 0.5 * i))
            seg = bpy.context.active_object
            seg.scale = (0.16, 0.16, 0.5)
            sm = bpy.data.materials.new("Staff")
            sm.use_nodes = True
            sm.node_tree.nodes["Principled BSDF"].inputs["Base Color"].default_value = (0.8, 0.06, 0.05, 1) if (i // 2) % 2 == 0 else (0.9, 0.9, 0.88, 1)
            seg.data.materials.append(sm)
            st.made.append(seg)
        aim_sun(sun, fill, -122)
        place(cam, (2.2, 0, 2.85), 56, -90, 3, 100)
        bx = sx - 2.9 + 1.2
        labels = [("0" if k == 0 else ("1 stud" if k == 1 else f"{k} studs"), (bx - 0.25, 0, float(k) - 0.02)) for k in range(0, 6)] + [("5.5 studs", (bx - 0.25, 0, 5.48))]
        labels += [("Slim build", (sx + 2.9 * 2, 0, 0)), ("Broad build", (sx + 2.9 * 4.5, 0, 0))]
        shoot("scale", (1600, 620), labels)

    if not want or "hair" in want:
        items = [("Hair_" + h, None) for h in spec.HAIR_ORDER] + [("Hair_short", "cap"), ("Hair_bob", "beret")]
        labels, rows = [], {0: [], 1: []}
        for i, (h, hat) in enumerate(items):
            col, row = i % 5, i // 5
            x, z = (col - 2) * 2.3, 0.0
            role = "officer" if hat == "cap" else ("mime" if hat == "beret" else "townsperson")
            y = row * 60.0  # the second row is rendered as its own strip
            made = st.person(role, i + 1, "slim", None, h[5:], hat=hat, pose="stand", at=(x, y), yaw=28 if i % 2 == 0 else -28)
            rows[row] += list(made.values())
            text = spec.HAIR[h[5:]]["label"] if hat is None else spec.HATS[hat]["label"]
            labels.append((text, (x, y, 3.92), row))
        for row in (0, 1):
            aim_sun(sun, fill, -125)
            place(cam, (0, row * 60.0, 4.68), 37, -90, 2, 100)
            for r_, objs_ in rows.items():
                for o in objs_:
                    o.hide_render = r_ != row
            scene.render.resolution_x, scene.render.resolution_y = int(1600 * opts.scale), int(330 * opts.scale)
            meta = {"labels": [{"text": t, "at": project(scene, cam, p)} for t, p, r_ in labels if r_ == row],
                    "size": [scene.render.resolution_x, scene.render.resolution_y]}
            scene.render.filepath = os.path.join(opts.out, f"hair_{row}.png")
            bpy.ops.render.render(write_still=True)
            with open(os.path.join(opts.out, f"hair_{row}.json"), "w") as fh:
                json.dump(meta, fh, indent=1)
            print(f"shot hair_{row}", flush=True)
        st.clear()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[sys.argv.index("--") + 1:] if "--" in sys.argv else sys.argv[1:]))
