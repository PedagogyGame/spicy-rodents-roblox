"""Small bpy helpers shared by the hero builders (headless bpy 5.2.x)."""
import math
import os

import bpy
import numpy as np
from mathutils import Matrix, Vector

# Blender (x, y, z) -> Roblox (-x, z, y): a proper rotation, its own inverse (D21, export_art.py).
M3 = Matrix(((-1, 0, 0), (0, 0, 1), (0, 1, 0)))
M_NP = np.array([[-1, 0, 0], [0, 0, 1], [0, 1, 0]], dtype=np.float64)


def reset_scene(fps=30):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    scene = bpy.context.scene
    scene.unit_settings.system = "NONE"
    scene.render.fps = fps
    return scene


def link(obj, scene=None):
    (scene or bpy.context.scene).collection.objects.link(obj)
    return obj


def mesh_from_arrays(name, verts, faces, smooth=True):
    """verts (N, 3); faces (M, k) int (all the same arity) or a list of index lists."""
    verts = np.asarray(verts, dtype=np.float32)
    me = bpy.data.meshes.new(name)
    if isinstance(faces, np.ndarray):
        nf, k = faces.shape
        loop_starts = np.arange(nf, dtype=np.int32) * k
        loops = faces.reshape(-1).astype(np.int32)
        sizes = np.full(nf, k, dtype=np.int32)
    else:
        sizes = np.array([len(f) for f in faces], dtype=np.int32)
        loop_starts = np.concatenate([[0], np.cumsum(sizes)[:-1]]).astype(np.int32)
        loops = np.array([i for f in faces for i in f], dtype=np.int32)
    me.vertices.add(len(verts))
    me.vertices.foreach_set("co", verts.reshape(-1))
    me.loops.add(len(loops))
    me.loops.foreach_set("vertex_index", loops)
    me.polygons.add(len(sizes))
    me.polygons.foreach_set("loop_start", loop_starts)
    me.update(calc_edges=True)
    me.validate(clean_customdata=False)
    if smooth:
        me.polygons.foreach_set("use_smooth", np.ones(len(me.polygons), dtype=bool))
    obj = bpy.data.objects.new(name, me)
    link(obj)
    return obj


def verts_np(me):
    a = np.empty(len(me.vertices) * 3, dtype=np.float32)
    me.vertices.foreach_get("co", a)
    return a.reshape(-1, 3)


def set_verts_np(me, v):
    me.vertices.foreach_set("co", np.asarray(v, dtype=np.float32).reshape(-1))
    me.update()


def tri_count(me):
    return int(sum(len(p.vertices) - 2 for p in me.polygons))


def select_only(objs, active=None):
    bpy.ops.object.select_all(action="DESELECT")
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = active or objs[0]


def apply_modifiers(obj):
    select_only([obj])
    for m in list(obj.modifiers):
        bpy.ops.object.modifier_apply(modifier=m.name)


def srgb_to_lin(c):
    c = np.asarray(c, dtype=np.float64)
    return np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)


def lin_to_srgb(c):
    c = np.clip(np.asarray(c, dtype=np.float64), 0, 1)
    return np.where(c <= 0.0031308, c * 12.92, 1.055 * np.power(c, 1 / 2.4) - 0.055)


def hexrgb(h):
    h = h.lstrip("#")
    return np.array([int(h[i : i + 2], 16) / 255.0 for i in (0, 2, 4)])


def save_png(path, rgba, colorspace="sRGB"):
    """rgba: (H, W, 4) float array in [0, 1], row 0 = TOP of the image. Saved as 8-bit PNG."""
    h, w = rgba.shape[:2]
    name = os.path.basename(path)
    img = bpy.data.images.get(name)
    if img is not None:
        bpy.data.images.remove(img)
    img = bpy.data.images.new(name, w, h, alpha=True)
    img.colorspace_settings.name = colorspace
    flipped = np.ascontiguousarray(np.clip(rgba[::-1], 0, 1).astype(np.float32))  # Blender rows go bottom-up
    img.pixels.foreach_set(flipped.reshape(-1))
    img.filepath_raw = path
    img.file_format = "PNG"
    img.save()
    return img


def load_png(path, colorspace="sRGB"):
    img = bpy.data.images.load(path, check_existing=False)
    img.colorspace_settings.name = colorspace
    w, h = img.size
    a = np.empty(w * h * 4, dtype=np.float32)
    img.pixels.foreach_get(a)
    return img, a.reshape(h, w, 4)[::-1]


# ---- quick shape views (Workbench) -------------------------------------------------------------------

def look_at(cam, target):
    d = Vector(target) - cam.location
    cam.rotation_euler = d.to_track_quat("-Z", "Y").to_euler()


def workbench_views(path, center, dist, views=((0, 0), (90, 0), (35, 20), (180, 70)), res=(480, 360), ortho=None, color=None):
    """Render a few views of the scene with Workbench (studio light, cavity, shadow) into one strip PNG.
    views: (azimuth deg from the animal's left side, elevation deg)."""
    scene = bpy.context.scene
    scene.render.engine = "BLENDER_WORKBENCH"
    sh = scene.display.shading
    sh.light = "STUDIO"
    sh.color_type = "TEXTURE" if color == "texture" else ("MATERIAL" if color == "material" else "SINGLE")
    sh.single_color = (0.62, 0.5, 0.42)
    sh.show_cavity = True
    sh.cavity_type = "BOTH"
    sh.show_shadows = True
    scene.display.shadow_focus = 0.4
    scene.render.resolution_x, scene.render.resolution_y = res
    scene.render.resolution_percentage = 100
    scene.render.film_transparent = False
    cam_data = bpy.data.cameras.new("QuickCam")
    if ortho:
        cam_data.type = "ORTHO"
        cam_data.ortho_scale = ortho
    else:
        cam_data.lens = 50
    cam = bpy.data.objects.new("QuickCam", cam_data)
    link(cam)
    scene.camera = cam
    tiles = []
    for az, el in views:
        a, e = math.radians(az), math.radians(el)
        offset = Vector((math.cos(e) * math.cos(a), math.cos(e) * math.sin(a), math.sin(e))) * dist
        cam.location = Vector(center) + offset
        look_at(cam, center)
        tmp = path + f".tmp_{az}_{el}.png"
        scene.render.filepath = tmp
        bpy.ops.render.render(write_still=True)
        _img, px = load_png(tmp)
        tiles.append(px)
        os.remove(tmp)
    strip = np.concatenate(tiles, axis=1)
    save_png(path, strip)
    bpy.data.objects.remove(cam)
    return path
