"""The squirrel in motion as the game shows it: review strips of a scripted take (headless bpy, Cycles CPU).

  lune run tools/review/motion_path.luau                       # the takes: build/motion/<variant>_<take>.json
  nice -n 5 /root/.cache/spicy-rodents/venv/bin/python -I tools/blender/heroes/render_motion.py \
      --variant squirrel [--takes walk,sprint,...] [--prefix before] [--strips docs/renders/heroes/motion] \
      [--blend build/heroes/squirrel/squirrel.blend] [--motion build/motion] [--samples 20] [--threads 2] \
      [--frames start:count:step] [--large i,j,k] [--only back,side] [--no-strips] [--reuse]
  (the takes of a variant that are in --motion, when --takes is not given; each take names its own frames)

For every chosen frame of a take the built hero is put at the frame's drawn feet point with its yaw, pitch
and roll; the clip tracks the game would be playing are read from the .blend's actions at the frame's clip
times (a loop wraps, a one-shot holds, the pose between two keys is taken in a straight line as the engine
plays the uploaded clip, two clips crossing over are mixed by their weights); the frame's `layers` are
multiplied on (Bone.Transform = clip pose * CFrame.Angles(rx, ry, rz)); and it is rendered under daylight
on ground with a one-stud grid (a heavier line every five studs), with the take's trunk or wire where the
motor has it (the bark and the wire are the route's own: the game's meshes are drawn around the same lines).

Views:
  back   the PLAY CAMERA: at the frame's camera position, looking at its focus, field of view as the game's.
         The picture is the part of a 1920 x 1080 game frame around the body, pixel for pixel (the body is
         about one stud tall and fourteen studs away, so it is small on the screen); the three larger frames
         are the same view three times the size, each centred on the body's joints.
  side   a tracking camera on the body's right-hand side, looking a little down (orthographic, so one stud
         is the same length everywhere and paws can be read against the grid). A take that leaves the
         ground is shown in a window tall enough for its highest point; a climb in an upright one.

Output: PNG frames under build/motion/frames/<variant>_<take>/ and, through sheets.py (system python3 with
Pillow), <strips>/<prefix>_<variant>_<take>_back.jpg and _side.jpg, each at most 1600 px wide and 400 KB.
The poses read from the actions are checked against the exported clip JSON (what the game plays) and the
body's size against the take's; the manifest records both.
"""
import argparse
import json
import math
import os
import subprocess
import sys
import time

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)

import bpy  # noqa: E402
import numpy as np  # noqa: E402
from mathutils import Matrix, Vector  # noqa: E402

import bl  # noqa: E402
import motion_pose as mp  # noqa: E402
import render_hero  # noqa: E402
import rig as rigmod  # noqa: E402

M = bl.M_NP  # Roblox <-> Blender axes (its own inverse)
R0 = rigmod.R_EXPORT
GAME_SCREEN = (1920, 1080)
REGIONS = ("Body", "Pattern", "Eyes", "FurCards", "Blood")

# studs across a small back frame at one screen pixel per pixel, and the views' sizes in pixels
SMALL = 200
LARGE = (528, 400)
LARGE_ZOOM = 3.0
SIDE_VIEW = {"w": 4.4, "h": 2.75}  # studs seen by the side camera (w along the body)
SIDE_ELEV = math.radians(14.0)  # the side camera looks a little down, so the grid behind the body shows


def to_bl(v):
    """A Roblox point or direction (x, y, z) in Blender's axes."""
    return Vector((-v[0], v[2], v[1]))


def vec(d):
    return np.array([d["x"], d["y"], d["z"]], dtype=np.float64)


def mat4(R, p):
    """Blender 4x4 from a Roblox rotation and point."""
    Rb = M @ R @ M
    pb = to_bl(p)
    return Matrix([list(Rb[0]) + [pb[0]], list(Rb[1]) + [pb[1]], list(Rb[2]) + [pb[2]], [0, 0, 0, 1]])


# ---- poses ---------------------------------------------------------------------------------------------

class Actions:
    """The built hero's clip actions (frame 1 is the clip's start, one key a frame). The keys are read
    from the F-curves and the pose between two keys is taken in a straight line, as the engine plays the
    uploaded clip (linear easing), not along Blender's own curve through them."""

    def __init__(self, arm, fps):
        self.fps = fps
        self.names = [pb.name for pb in arm.pose.bones]
        self.curves = {}
        self.last = {}
        for act in bpy.data.actions:
            self.last[act.name] = int(round(act.frame_range[1]))
            bag = act.layers[0].strips[0].channelbags[0]
            per = {n: {"q": [None] * 4, "l": [None] * 3} for n in self.names}
            for fc in bag.fcurves:
                path = fc.data_path
                if not path.startswith('pose.bones["'):
                    continue
                bone = path.split('"')[1]
                if bone not in per:
                    continue
                if path.endswith("rotation_quaternion"):
                    per[bone]["q"][fc.array_index] = fc
                elif path.endswith("location"):
                    per[bone]["l"][fc.array_index] = fc
            self.curves[act.name] = per

    def key(self, clip, frame):
        """{bone: (R, t)} at a whole frame, in Roblox axes: the clip convention."""
        pose = {}
        for n, c in self.curves[clip].items():
            q = np.array([fc.evaluate(frame) if fc else (1.0 if k == 0 else 0.0) for k, fc in enumerate(c["q"])])
            loc = np.array([fc.evaluate(frame) if fc else 0.0 for fc in c["l"]])
            Rb = mp.mat(q)
            R = R0 @ Rb @ R0.T  # Blender axes, joint-local (clips.py)
            pose[n] = (M @ R @ M, M @ (R0 @ loc))
        return pose

    def sample(self, clip, seconds):
        last = self.last[clip]
        frame = min(max(1.0 + seconds * self.fps, 1.0), float(last))
        f0 = min(int(math.floor(frame + 1e-9)), last)
        f1 = min(f0 + 1, last)
        u = min(max(frame - f0, 0.0), 1.0)
        a = self.key(clip, f0)
        if u < 1e-9 or f1 == f0:
            return a
        b = self.key(clip, f1)
        return {n: (mp.slerp(a[n][0], b[n][0], u), a[n][1] * (1 - u) + b[n][1] * u) for n in a}


def set_pose(arm, pose):
    for pb in arm.pose.bones:
        R, t = pose[pb.name]
        Rb = R0.T @ (M @ R @ M) @ R0
        tb = R0.T @ (M @ t)
        pb.matrix_basis = Matrix([list(Rb[0]) + [tb[0]], list(Rb[1]) + [tb[1]], list(Rb[2]) + [tb[2]], [0, 0, 0, 1]])


def pose_gap(a, b):
    """The largest difference between two poses: (rotation matrix entry, studs)."""
    dr = max(float(np.abs(a[n][0] - b[n][0]).max()) for n in a)
    dt = max(float(np.abs(a[n][1] - b[n][1]).max()) for n in a)
    return dr, dt


def mesh_bounds():
    """The regions' bounding box at rest, in Roblox axes (the armature must be at rest at the origin)."""
    lo = np.full(3, 1e9)
    hi = -lo
    for name in REGIONS:
        o = bpy.data.objects.get(name)
        if o is None:
            continue
        co = bl.verts_np(o.data).astype(np.float64)
        rb = np.stack([-co[:, 0], co[:, 2], co[:, 1]], axis=1)
        lo = np.minimum(lo, rb.min(0))
        hi = np.maximum(hi, rb.max(0))
    return lo, hi


# ---- the scene ---------------------------------------------------------------------------------------

def daylight(scene):
    world = bpy.data.worlds.new("Daylight")
    scene.world = world
    world.use_nodes = True
    bg = world.node_tree.nodes.get("Background")
    bg.inputs["Color"].default_value = (0.50, 0.66, 0.92, 1)
    bg.inputs["Strength"].default_value = 1.1
    sd = bpy.data.lights.new("Sun", "SUN")
    sd.energy = 3.6
    sd.angle = math.radians(2.5)
    sd.color = (1.0, 0.96, 0.9)
    sun = bpy.data.objects.new("Sun", sd)
    scene.collection.objects.link(sun)
    # from behind the first camera, to its right and high: the back and the right flank are lit
    travel = to_bl((-0.55, -1.0, -0.42)).normalized()
    sun.rotation_euler = travel.to_track_quat("-Z", "Y").to_euler()
    return sun


def grid_material():
    """Ground whose colour is a function of the world position: one-stud tiles in two close tones, a thin
    dark line on every stud and a heavier one every five."""
    m = bpy.data.materials.new("GridGround")
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.95
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sep.inputs["Vector"])

    def math_node(op, a, b=None, clamp=False):
        n = nt.nodes.new("ShaderNodeMath")
        n.operation = op
        n.use_clamp = clamp
        for k, v in enumerate((a, b)):
            if v is None:
                continue
            if isinstance(v, (int, float)):
                n.inputs[k].default_value = v
            else:
                nt.links.new(v, n.inputs[k])
        return n.outputs["Value"]

    def line(coord, period, width):
        # 1 within width/2 of a multiple of `period`
        u = math_node("DIVIDE", coord, period)
        f = math_node("FRACT", math_node("ADD", u, 0.5))
        d = math_node("ABSOLUTE", math_node("SUBTRACT", f, 0.5))
        return math_node("LESS_THAN", d, width / (2 * period))

    x, y = sep.outputs["X"], sep.outputs["Y"]
    fine = math_node("MAXIMUM", line(x, 1.0, 0.035), line(y, 1.0, 0.035))
    coarse = math_node("MAXIMUM", line(x, 5.0, 0.09), line(y, 5.0, 0.09))
    # checker: floor(x) + floor(y) odd
    parity = math_node("FRACT", math_node("MULTIPLY", math_node("ADD", math_node("FLOOR", x), math_node("FLOOR", y)), 0.5))
    odd = math_node("GREATER_THAN", parity, 0.25)

    def mix(fac, a, b):
        n = nt.nodes.new("ShaderNodeMix")
        n.data_type = "RGBA"
        nt.links.new(fac, n.inputs["Factor"])
        for sock, v in (("A", a), ("B", b)):
            if isinstance(v, tuple):
                n.inputs[sock].default_value = v
            else:
                nt.links.new(v, n.inputs[sock])
        return n.outputs["Result"]

    tiles = mix(odd, (0.20, 0.29, 0.115, 1), (0.255, 0.35, 0.155, 1))
    lined = mix(fine, tiles, (0.10, 0.15, 0.07, 1))
    final = mix(coarse, lined, (0.045, 0.07, 0.035, 1))
    nt.links.new(final, bsdf.inputs["Base Color"])
    return m


def banded_material(name, a, b, axis, period=1.0):
    """Two colours alternating every `period` studs along a world axis (so travel along it can be read)."""
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    nt = m.node_tree
    bsdf = nt.nodes["Principled BSDF"]
    bsdf.inputs["Roughness"].default_value = 0.85
    geo = nt.nodes.new("ShaderNodeNewGeometry")
    sep = nt.nodes.new("ShaderNodeSeparateXYZ")
    nt.links.new(geo.outputs["Position"], sep.inputs["Vector"])
    div = nt.nodes.new("ShaderNodeMath")
    div.operation = "DIVIDE"
    nt.links.new(sep.outputs[axis], div.inputs[0])
    div.inputs[1].default_value = 2.0 * period
    fr = nt.nodes.new("ShaderNodeMath")
    fr.operation = "FRACT"
    nt.links.new(div.outputs["Value"], fr.inputs[0])
    gt = nt.nodes.new("ShaderNodeMath")
    gt.operation = "GREATER_THAN"
    nt.links.new(fr.outputs["Value"], gt.inputs[0])
    gt.inputs[1].default_value = 0.5
    mix = nt.nodes.new("ShaderNodeMix")
    mix.data_type = "RGBA"
    nt.links.new(gt.outputs["Value"], mix.inputs["Factor"])
    mix.inputs["A"].default_value = a
    mix.inputs["B"].default_value = b
    nt.links.new(mix.outputs["Result"], bsdf.inputs["Base Color"])
    return m


def build_ground(take):
    xs = [f["pos"]["x"] for f in take["frames"]]
    zs = [f["pos"]["z"] for f in take["frames"]]
    cx, cz = (min(xs) + max(xs)) / 2, (min(zs) + max(zs)) / 2
    half = max(max(xs) - min(xs), max(zs) - min(zs)) / 2 + 400
    y = take["ground"]["y"]
    c = to_bl((cx, y, cz))
    bpy.ops.mesh.primitive_plane_add(size=2 * half, location=c)
    ground = bpy.context.active_object
    ground.name = "Ground"
    ground.data.materials.append(grid_material())
    return ground


def build_props(take):
    made = []
    for p in take["props"]:
        if p["kind"] == "trunk":
            # a stack of frusta whose radius is the bark's as the motor has it
            n = 34
            rings = []
            for k in range(n + 1):
                t = k / n
                r = max(p["minRadius"], p["radius"] * (1 - p["taper"] * t))
                rings.append((r, p["y0"] + p["height"] * t))
            seg = 40
            verts, faces = [], []
            for r, y in rings:
                for s in range(seg):
                    a = 2 * math.pi * s / seg
                    verts.append(tuple(to_bl((p["x"] + r * math.cos(a), y, p["z"] + r * math.sin(a)))))
            for k in range(n):
                for s in range(seg):
                    a0, a1 = k * seg + s, k * seg + (s + 1) % seg
                    faces.append((a0, a1, a1 + seg, a0 + seg))
            o = bl.mesh_from_arrays("Trunk", np.array(verts), np.array(faces), smooth=True)
            o.data.materials.append(banded_material("Bark", (0.20, 0.13, 0.08, 1), (0.26, 0.17, 0.10, 1), "Z"))
            made.append(o)
        elif p["kind"] == "wire":
            cu = bpy.data.curves.new("Wire", "CURVE")
            cu.dimensions = "3D"
            cu.bevel_depth = p["radius"]
            cu.bevel_resolution = 3
            sp = cu.splines.new("POLY")
            sp.points.add(len(p["points"]) - 1)
            for pt, q in zip(sp.points, p["points"]):
                b = to_bl(q)
                pt.co = (b[0], b[1], b[2], 1.0)
            o = bpy.data.objects.new("Wire", cu)
            bpy.context.scene.collection.objects.link(o)
            # along the wire the travel is Roblox Z = Blender Y
            o.data.materials.append(banded_material("WireBands", (0.03, 0.03, 0.03, 1), (0.75, 0.42, 0.08, 1), "Y"))
            made.append(o)
    return made


def setup_render(scene, samples, threads):
    render_hero.setup_render(scene, (SMALL, SMALL), samples, threads)
    scene.render.use_persistent_data = True
    scene.cycles.adaptive_threshold = 0.05
    scene.view_settings.look = "AgX - Base Contrast"
    scene.view_settings.exposure = -1.15  # a sunlit lawn, not a snowfield


def new_camera(scene, name):
    cd = bpy.data.cameras.new(name)
    cam = bpy.data.objects.new(name, cd)
    scene.collection.objects.link(cam)
    cd.clip_start = 0.1
    cd.clip_end = 2000
    return cam


def aim(cam, eye, target):
    cam.location = eye
    cam.rotation_euler = (Vector(target) - Vector(eye)).to_track_quat("-Z", "Y").to_euler()


def back_view(scene, cam, take, frame, res, zoom, points=None):
    """The play camera, cropped to `res` pixels around the body at `zoom` screen pixels per pixel."""
    eye, focus = vec(frame["cam"]), vec(frame["focus"])
    aim(cam, to_bl(eye), to_bl(focus))
    cd = cam.data
    cd.type = "PERSP"
    cd.sensor_fit = "HORIZONTAL"
    cd.sensor_width = 36.0
    screen_px = (GAME_SCREEN[1] / 2) / math.tan(math.radians(take["camera"]["fov"]) / 2)  # pixels per unit of slope
    fwd = focus - eye
    fwd /= np.linalg.norm(fwd)
    right = np.cross(fwd, [0.0, 1.0, 0.0])
    right /= np.linalg.norm(right)
    up = np.cross(right, fwd)

    def on_screen(q):
        """Where a world point falls on the game screen, in pixels from its middle, and how deep it is."""
        d = q - eye
        depth = float(d @ fwd)
        return float(d @ right) / depth * screen_px, float(d @ up) / depth * screen_px, depth

    # the middle of the picture. In a run of frames it is tied to the drawn feet point (a little up and
    # toward the tail), so what the clip does to the body shows as movement in the picture; a single
    # larger frame is centred on the joints themselves (a tail held over the back stays in it) and is
    # enlarged a little less when the body would not fit (a body on end, or seen side-on in a turn).
    R, p = mp.body_frame(frame)
    u, v, depth = on_screen(p + R @ np.array([0.0, 0.62, 0.45]))
    if points is not None:
        uv = np.array([on_screen(q)[:2] for q in points])
        u, v = (uv[:, 0].min() + uv[:, 0].max()) / 2, (uv[:, 1].min() + uv[:, 1].max()) / 2
        fur = 44.0  # screen pixels of fur and margin around the joints
        fit = min(res[0] / (np.ptp(uv[:, 0]) + fur), res[1] / (np.ptp(uv[:, 1]) + fur))
        zoom = min(zoom, math.floor(fit * 4) / 4)
    f_px = screen_px * zoom
    cd.lens = 36.0 * f_px / res[0]
    cd.shift_x = u * zoom / res[0]
    cd.shift_y = v * zoom / res[0]
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = res
    back_view.zoom = zoom
    return depth


def side_view(scene, cam, take, frame, res, view):
    """Level with the body on its right-hand side, tracking the drawn feet point."""
    R, p = mp.body_frame(frame)
    yaw = frame["yaw"]
    right = np.array([math.cos(yaw), 0.0, -math.sin(yaw)])
    mid = 0.58  # studs behind the feet point: half way from the nose to the tail tip
    if take["strip"].get("tall"):
        # standing on end: half a stud out from the feet point, which is a little off the surface climbed
        centre = p + R @ np.array([0.0, 0.5, mid])
    elif view.get("ground"):
        # the ground stays in the picture however high the body goes
        centre = np.array([p[0], take["ground"]["y"] + view["h"] * 0.5 - 0.6, p[2]]) + R @ np.array([0.0, 0.0, mid])
    else:
        # the feet point half a stud above the bottom of the picture (a stud above it over a wire or a
        # bough, which the body is drawn above)
        under = 1.0 if take["props"] else 0.5
        centre = p + R @ np.array([0.0, 0.0, mid]) + np.array([0.0, view["h"] * 0.5 - under, 0.0])
    out = right * math.cos(SIDE_ELEV) + np.array([0.0, math.sin(SIDE_ELEV), 0.0])
    aim(cam, to_bl(centre + out * 60.0), to_bl(centre))
    cd = cam.data
    cd.type = "ORTHO"
    cd.sensor_fit = "AUTO"
    cd.ortho_scale = max(view["w"], view["h"])
    cd.shift_x = cd.shift_y = 0.0
    scene.camera = cam
    scene.render.resolution_x, scene.render.resolution_y = res


REUSE = False  # --reuse: a frame whose PNG is already there is not rendered again


def render(scene, path):
    if REUSE and os.path.exists(path):
        return
    scene.render.filepath = path
    bpy.ops.render.render(write_still=True)


# ---- one take ----------------------------------------------------------------------------------------

def side_window(take):
    """Studs the side camera sees. A take that leaves the ground gets a window tall enough for its
    highest point, standing on the ground; a body on end gets an upright one."""
    top = max(f["pos"]["y"] for f in take["frames"]) - take["ground"]["y"]
    if not take["props"] and top > 0.5:
        size = math.ceil(top + 2.6)
        return {"w": float(size), "h": float(size), "ground": True}
    if take["strip"].get("tall"):
        return {"w": SIDE_VIEW["h"], "h": SIDE_VIEW["w"]}
    return dict(SIDE_VIEW)


def render_take(opts, scene, arm, actions, clips, rig, take):
    tag = f"{take['variant']}_{take['take']}"
    out = os.path.join(opts.frames, tag)
    os.makedirs(out, exist_ok=True)
    strip = dict(take["strip"])
    if opts.select:
        a, n, s = (int(x) for x in opts.select.split(":"))
        strip.update(start=a, count=n, step=s)
        last = a + (n - 1) * s
        strip["large"] = [a, a + round((last - a) / 3), a + round((last - a) * 2 / 3)]
    if opts.large:
        strip["large"] = [int(x) for x in opts.large.split(",")]
    small = [strip["start"] + k * strip["step"] for k in range(strip["count"])]
    view = side_window(take)
    side_px = SMALL / max(view["w"], view["h"])  # pixels per stud in the small side frames
    side_res = (round(view["w"] * side_px), round(view["h"] * side_px))
    big_px = min(LARGE[0] / view["w"], LARGE[1] / view["h"])
    side_big = (round(view["w"] * big_px), round(view["h"] * big_px))

    ground = build_ground(take)
    props = build_props(take)
    back_cam = new_camera(scene, "PlayCamera")
    side_cam = new_camera(scene, "SideCamera")
    frames = take["frames"]
    worst_r = worst_t = 0.0
    shown = {}
    t0 = time.time()

    def pose_frame(i):
        nonlocal worst_r, worst_t
        f = frames[i]
        pose = mp.frame_pose(clips, f, sampler=actions.sample)
        ref = mp.frame_pose(clips, f)
        dr, dtr = pose_gap(pose, ref)
        worst_r, worst_t = max(worst_r, dr), max(worst_t, dtr)
        set_pose(arm, pose)
        R, p = mp.body_frame(f)
        arm.matrix_world = mat4(R, p)
        bpy.context.view_layer.update()
        # the joints in the world (with the ear and tail tips and the toes): what a single frame is centred on
        W = rig.fk(pose)
        tips = [rig.tip(W, b) for b in ("Tail8", "EarL", "EarR", "FrontL_Toe", "FrontR_Toe", "BackL_Toe", "BackR_Toe")]
        return f, [p + R @ q for q in [W[n][1] for n in rig.names] + tips]

    def info(i):
        f = frames[i]
        return {"i": i, "t": f["t"], "clip": f["clip"], "clipTime": f["clipTime"], "speed": f["speed"], "mode": f["mode"]}

    for i in sorted(set(small) | set(strip["large"])):
        f, joints = pose_frame(i)
        entry = info(i)
        if i in small:
            if "back" in opts.only:
                entry["back"] = os.path.join(out, f"back_{i:04d}.png")
                entry["depth"] = round(back_view(scene, back_cam, take, f, (SMALL, SMALL), 1.0), 3)
                render(scene, entry["back"])
            if "side" in opts.only:
                entry["side"] = os.path.join(out, f"side_{i:04d}.png")
                side_view(scene, side_cam, take, f, side_res, view)
                render(scene, entry["side"])
        if i in strip["large"]:
            if "back" in opts.only:
                entry["backLarge"] = os.path.join(out, f"back_large_{i:04d}.png")
                back_view(scene, back_cam, take, f, LARGE, LARGE_ZOOM, joints)
                entry["backLargeZoom"] = back_view.zoom
                render(scene, entry["backLarge"])
            if "side" in opts.only:
                entry["sideLarge"] = os.path.join(out, f"side_large_{i:04d}.png")
                side_view(scene, side_cam, take, f, side_big, view)
                render(scene, entry["sideLarge"])
        shown[i] = entry
        print(f"[motion {time.time() - t0:6.1f}s] {tag} frame {i}", flush=True)

    for o in [ground, back_cam, side_cam] + props:
        bpy.data.objects.remove(o)
    manifest = {
        "variant": take["variant"],
        "take": take["take"],
        "title": take["title"],
        "fps": take["fps"],
        "camera": take["camera"],
        "strip": strip,
        "small": [shown[i] for i in small],
        "large": [shown[i] for i in strip["large"]],
        "sideView": view,
        "sidePixelsPerStud": round(side_px, 2),
        "largeZoom": LARGE_ZOOM,
        "poseCheck": {"rotation": worst_r, "studs": worst_t},
        "seconds": round(time.time() - t0, 1),
        "samples": opts.samples,
    }
    path = os.path.join(out, "manifest.json")
    with open(path, "w") as fh:
        json.dump(manifest, fh, indent=1)
    return path, manifest


def main(argv):
    ap = argparse.ArgumentParser()
    ap.add_argument("--variant", required=True)
    ap.add_argument("--blend", default=None)
    ap.add_argument("--motion", default="build/motion")
    ap.add_argument("--takes", default="")
    ap.add_argument("--frames", dest="select", default="", help="start:count:step instead of the take's own strip")
    ap.add_argument("--large", default="", help="three frame numbers shown larger")
    ap.add_argument("--only", default="back,side")
    ap.add_argument("--samples", type=int, default=20)
    ap.add_argument("--threads", type=int, default=2)
    ap.add_argument("--prefix", default="before")
    ap.add_argument("--strips", default="docs/renders/heroes/motion")
    ap.add_argument("--no-strips", action="store_true")
    ap.add_argument("--reuse", action="store_true", help="keep the frames already rendered (delete the PNGs to be redone)")
    opts = ap.parse_args(argv)
    global REUSE
    REUSE = opts.reuse
    opts.only = [x for x in opts.only.split(",") if x]
    opts.frames = os.path.join(opts.motion, "frames")
    blend = opts.blend or os.path.join("build", "heroes", opts.variant, f"{opts.variant}.blend")
    takes = [t for t in opts.takes.split(",") if t]
    if not takes:
        takes = sorted(
            os.path.basename(p)[len(opts.variant) + 1 : -5]
            for p in (os.path.join(opts.motion, n) for n in os.listdir(opts.motion))
            if os.path.basename(p).startswith(opts.variant + "_") and p.endswith(".json")
        )
    bpy.ops.wm.open_mainfile(filepath=os.path.abspath(blend))
    scene = bpy.context.scene
    meta = json.loads(scene.get("hero_meta", "{}"))
    render_hero.tint_materials(meta.get("tints", {}), meta.get("glow", False))
    arm = bpy.data.objects["Rig"]
    if arm.animation_data:
        arm.animation_data.action = None
    for pb in arm.pose.bones:
        pb.rotation_mode = "QUATERNION"
        pb.matrix_basis.identity()
    bpy.context.view_layer.update()
    lo, hi = mesh_bounds()
    actions = Actions(arm, scene.render.fps)
    clips = mp.load_clips(os.path.join(os.path.dirname(os.path.abspath(blend)), "clips"))
    rig = mp.Rig(next(iter(clips.values())).doc["bones"])
    daylight(scene)
    setup_render(scene, opts.samples, opts.threads)
    status = 0
    for name in takes:
        take = mp.load_take(os.path.join(opts.motion, f"{opts.variant}_{name}.json"))
        gap = max(float(np.abs(lo - np.array(take["mesh"]["min"])).max()), float(np.abs(hi - np.array(take["mesh"]["max"])).max()))
        if gap > 0.03:
            print(f"WARNING: {blend} is not the size the take assumed (off by {gap:.3f} studs): "
                  f"update VARIANTS.{opts.variant}.mesh in tools/review/motion/Path.luau to min {lo.round(3).tolist()} max {hi.round(3).tolist()}", flush=True)
        path, manifest = render_take(opts, scene, arm, actions, clips, rig, take)
        manifest["meshGap"] = round(gap, 4)
        with open(path, "w") as fh:
            json.dump(manifest, fh, indent=1)
        pc = manifest["poseCheck"]
        print(f"[motion] {opts.variant} {name}: {manifest['seconds']} s; actions against the exported clips: "
              f"rotation {pc['rotation']:.2e}, {pc['studs']:.2e} studs", flush=True)
        if pc["rotation"] > 5e-3 or pc["studs"] > 5e-3:
            print("WARNING: the .blend's actions and the exported clips disagree: rebuild the hero", flush=True)
            status = 1
        if not opts.no_strips:
            os.makedirs(opts.strips, exist_ok=True)
            base = os.path.join(opts.strips, f"{opts.prefix}_{opts.variant}_{name}")
            subprocess.run(["python3", "-I", os.path.join(HERE, "sheets.py"), "motion", "--manifest", path, "--out", base], check=True)
    return status


if __name__ == "__main__":
    argv = sys.argv[sys.argv.index("--") + 1 :] if "--" in sys.argv else sys.argv[1:]
    sys.exit(main(argv))
