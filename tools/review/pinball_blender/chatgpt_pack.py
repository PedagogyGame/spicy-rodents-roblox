# Builds the pack the owner hands to ChatGPT to make the pinball GLB models (docs/owner/pinball_blender/chatgpt_pack):
#   pinball_data.json  every part of the three machines and the cabinet, in metres, in the GLB frame
#   reference/*.glb    a plain blockout of every requested file, built from that data (the shapes to refine)
#   check_glb.py       the checker ChatGPT runs on each finished file against pinball_data.json
# Every number comes from the game's own modules through dump.luau, never typed by hand. Run from the repo root:
#   lune run tools/review/pinball_blender/dump.luau build/review/pinball_tables.json
#   python3 -I tools/review/pinball_blender/chatgpt_pack.py build/review/pinball_tables.json docs/owner/pinball_blender/chatgpt_pack
# then zip docs/owner/pinball_blender/chatgpt_pack as docs/owner/pinball_blender/Pinball_ChatGPT_Pack.zip (folder Pinball_ChatGPT_Pack/)
import json, math, os, sys
import numpy as np
import trimesh

D = json.load(open(sys.argv[1]))
OUT = sys.argv[2]
os.makedirs(os.path.join(OUT, "reference"), exist_ok=True)
LY, CB = D["layout"], D["cabinet"]
W, L, BR, XC = LY["WIDTH"], LY["LENGTH"], LY["BALL_R"], LY["XC"]
S = 0.28  # metres per stud
TILT = LY["TILT"]
BELOW = 0.85  # the cabinet body's depth under the playfield (tools/bake/games/Pinball.luau)
WALL = {"wood": (0.06, 0.2), "metal": (0.022, 0.11), "plastic": (0.045, 0.1), "rubber": (0.035, 0.08)}
LAMP = {"red": (255, 60, 50), "green": (80, 255, 110), "amber": (255, 170, 40), "yellow": (255, 236, 70),
        "orange": (255, 130, 30), "white": (255, 250, 235), "blue": (80, 150, 255)}
MACHINES = (("acorn", "pinball_acorn", "Acorn", "ACORN ATTACK"), ("rodent", "pinball_rodent", "Rodent", "SPICY RODENT"),
            ("space", "pinball_space", "Space", "SPACE SQUIRREL"))


def r4(v):
    return round(v, 5)


def P(x, y, h=0.0):
    """playfield frame (studs: x across from the left, y up the table, h above the surface) -> GLB metres
    (X to the player's right, Y up, -Z up the table), origin the playfield's front-left corner on its surface"""
    return [r4(x * S), r4(h * S), r4(-y * S)]


def XZ(x, y):
    p = P(x, y)
    return [p[0], p[2]]


def hexc(c):
    return "#%02x%02x%02x" % tuple(c)


# ---------------------------------------------------------------- the data
def machine_data(variant, tid, prefix, title):
    t, th = D["tables"][tid], D["themes"][variant]
    slings = t["slings"]
    sling_bodies = []
    walls = []
    for w in t["walls"]:
        p = w["pts"]
        body_of = None
        if w["mat"] == "plastic" and len(p) == 6:
            for i, s in enumerate(slings):
                if abs(p[0] - s["x1"]) < 1e-6 and abs(p[1] - s["y1"]) < 1e-6:
                    body_of = i
        if body_of is not None:
            sling_bodies.append((body_of, p))
            continue
        tt, hh = WALL[w["mat"]]
        walls.append({"material": w["mat"], "thickness": r4(tt * S), "height": r4(hh * S),
                      "points": [XZ(p[k], p[k + 1]) for k in range(0, len(p), 2)]})
    for i, w in enumerate(walls, 1):
        w["name"] = f"Wall{i:02d}_{w['material']}"
    posts = [{"name": f"Post{i:02d}_{p['mat']}", "material": p["mat"], "centre": XZ(p["x"], p["y"]), "radius": r4(p["r"] * S),
              "height": r4((0.11 if p["mat"] == "rubber" else 0.14) * S)} for i, p in enumerate(t["posts"], 1)]
    bumpers = [{"index": i, "body_name": f"Bumper{i}", "cap_name": f"BumperCap{i}", "centre": XZ(b["x"], b["y"]),
                "body_radius": r4(b["r"] * S), "body_height": r4(0.16 * S), "cap_radius": r4(b["r"] * 0.85 * S),
                "cap_bottom": r4(0.16 * S), "cap_top": r4(0.2 * S)} for i, b in enumerate(t["bumpers"], 1)]
    sl = []
    for i, s in enumerate(slings, 1):
        body = next(p for j, p in sling_bodies if j == i - 1)
        side = "L" if s["id"].endswith("l") else "R"
        sl.append({"index": i, "side": side, "body_name": f"SlingBody{i}", "rubber_name": f"Sling{i}",
                   "body_triangle": [XZ(body[k], body[k + 1]) for k in range(0, 6, 2)], "body_height": r4(0.1 * S),
                   "rubber": [XZ(s["x1"], s["y1"]), XZ(s["x2"], s["y2"])], "rubber_thickness": r4(0.035 * S), "rubber_height": r4(0.09 * S)})
    fl = []
    for i, f in enumerate(t["flippers"], 1):
        sgn = -1 if f["mirror"] else 1
        tip = (f["x"] + sgn * math.cos(f["rest"]) * f["len"], f["y"] + math.sin(f["rest"]) * f["len"])
        fl.append({"name": f"Flipper{i}", "side": "L" if f["button"] == "left" else "R", "pivot": XZ(f["x"], f["y"]),
                   "tip_at_rest": XZ(*tip), "rest_deg": r4(math.degrees(f["rest"])), "up_deg": r4(math.degrees(f["up"]))})
    tg = []
    for i, g in enumerate(t["targets"], 1):
        tg.append({"name": f"Drop{i}" if g["kind"] == "drop" else f"Standup{i}", "kind": g["kind"], "id": g["id"],
                   "a": XZ(g["x1"], g["y1"]), "b": XZ(g["x2"], g["y2"]), "thickness": r4(0.03 * S), "height": r4(0.12 * S),
                   "width": r4(math.hypot(g["x2"] - g["x1"], g["y2"] - g["y1"]) * S),
                   **({"sinks": r4(CB["DROP_SINK"] * S)} if g["kind"] == "drop" else {})})
    sp, k = [], 0
    for s in t["sensors"]:
        if s["kind"] == "spinner":
            k += 1
            sp.append({"name": f"Spinner{k}", "a": XZ(s["x1"], s["y1"]), "b": XZ(s["x2"], s["y2"]),
                       "width": r4(math.hypot(s["x2"] - s["x1"], s["y2"] - s["y1"]) * S), "axis_height": r4(0.1 * S),
                       "flag_height": r4(0.1 * S), "flag_thickness": r4(0.008 * S)})
    rollovers = [{"id": s["id"], "a": XZ(s["x1"], s["y1"]), "b": XZ(s["x2"], s["y2"])} for s in t["sensors"] if s["kind"] == "rollover"]
    gates = [{"name": "Gate", "a": XZ(g["x1"], g["y1"]), "b": XZ(g["x2"], g["y2"]), "thickness": r4(0.012 * S),
              "bottom": r4(0.05 * S), "top": r4(0.1 * S)} for g in t["gates"]]
    holes = [{"name": f"Hole_{h['id']}", "id": h["id"], "centre": XZ(h["x"], h["y"]), "radius": r4((h["r"] + BR) * S),
              **({"ball_drops_in_moving": "up the table (-Z)"} if h.get("ax") is not None else {})} for h in t["saucers"]]
    ramps = [{"name": f"Ramp_{r['id']}", "id": r["id"], "track_width": r4((2 * BR + 0.06) * S), "mouth_half_width": r4(r["mouth"] * S),
              "path": [P(r["pts"][k], r["pts"][k + 1], r["pts"][k + 2]) for k in range(0, len(r["pts"]), 3)]} for r in t["rails"]]
    lamps = [{"name": f"Lamp{i}", "id": l["id"], "colour": l["colour"], "centre": XZ(l["x"], l["y"]), "radius": r4(0.05 * S)}
             for i, l in enumerate(t["lamps"], 1)]
    lampby = {l["id"]: l for l in t["lamps"]}
    words = []
    for p in D["art"][variant]:
        lp = lampby.get(p.get("lamp")) if p.get("lamp") else None
        x = (lp["x"] if lp else p.get("x", 0)) + p["dx"]
        y = (lp["y"] if lp else p.get("y", 0)) + p["dy"]
        words.append({"text": p["text"], "centre": XZ(x, y), "width": r4(p["w"] * S), "height": r4(p["h"] * S)})
    pl = t["plunger"]
    return {
        "title": title, "file_prefix": prefix,
        "colours": {k: hexc(th[k]) for k in ("body", "trim", "field", "apron", "plastic", "bumper", "cap", "target", "glow", "legs", "art", "ink")},
        "board": {"name": "Board", "x0": 0.0, "x1": r4(W * S), "z_front": r4(0.16 * S), "z_back": r4(-L * S), "top": 0.0, "thickness": r4(0.06 * S)},
        "apron": {"name": "Apron", "x0": r4((XC - 0.75) * S), "x1": r4((XC + 0.75) * S), "z_front": r4(0.16 * S),
                  "z_back": r4(-(t["drainY"] + 0.1) * S), "top": r4(0.06 * S), "title": title},
        "walls": walls, "posts": posts, "bumpers": bumpers, "slingshots": sl, "flippers": fl, "targets": tg, "spinners": sp,
        "gates": gates, "holes": holes, "ramps": ramps, "lamps": lamps, "rollovers": rollovers, "painted_words": words,
        "plunger": {"lane_x": r4(pl["x"] * S), "ball_rest": P(pl["x"], pl["y"], BR), "rod_from_z": r4(-CB["ROD_Y0"] * S),
                    "rod_to_z": r4(-(pl["y"] - BR) * S)},
    }


def cab_pt(x, y, h):
    """playfield frame (studs) -> the room, in metres: X to the player's right, Y up from the floor, Z toward the player,
    origin on the floor under the middle of the machine"""
    along = y - L / 2
    sn, cs = math.sin(TILT), math.cos(TILT)
    return [r4((x - W / 2) * S), r4((CB["PF_Y"] + along * sn + h * cs) * S), r4((CB["PF_D"] - (along * cs - h * sn)) * S)]


def tilted_box(x0, x1, y0, y1, h0, h1):
    return [cab_pt(x, y, h) for x in (x0, x1) for y in (y0, y1) for h in (h0, h1)]


def world_box(x0, x1, y0, y1, z0, z1):
    return [[r4(x * S), r4(y * S), r4(z * S)] for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]


def cabinet_data():
    R, G = CB["RAIL"], CB["GLASS_H"]
    B, LG, BB = CB["BUTTON"], CB["LEGS"], CB["BACKBOX"]
    parts = {
        "Body": tilted_box(-R, W + R, -0.27, L + 0.09, -BELOW, -BELOW + 0.12),
        "SideWall_L": tilted_box(-R, 0, -0.27, L + 0.09, -BELOW, G + 0.05),
        "SideWall_R": tilted_box(W, W + R, -0.27, L + 0.09, -BELOW, G + 0.05),
        "FrontWall": tilted_box(-R, W + R, -0.27, -0.15, -BELOW, G + 0.05),
        "BackWall": tilted_box(-R, W + R, L, L + 0.08, -BELOW, G),
        "LockdownBar": tilted_box(-R - 0.02, W + R + 0.02, -0.275, -0.145, G + 0.055, G + 0.105),
        "Glass": tilted_box(0, W, 0, L, G - 0.01, G + 0.01),
        "FlipperButton_L": tilted_box(-R - B["out"] - B["length"] / 2, -R - B["out"] + B["length"] / 2, B["y"] - B["size"] / 2, B["y"] + B["size"] / 2, B["h"] - B["size"] / 2, B["h"] + B["size"] / 2),
        "FlipperButton_R": tilted_box(W + R + B["out"] - B["length"] / 2, W + R + B["out"] + B["length"] / 2, B["y"] - B["size"] / 2, B["y"] + B["size"] / 2, B["h"] - B["size"] / 2, B["h"] + B["size"] / 2),
        "CoinDoor": tilted_box(W / 2 - 0.35, W / 2 + 0.35, -0.3, -0.27, -BELOW / 2 - 0.325, -BELOW / 2 + 0.225),
    }
    for name, x, y in (("Leg_FL", -R + LG["inset"], -0.05), ("Leg_FR", W + R - LG["inset"], -0.05),
                       ("Leg_BL", -R + LG["inset"], L - 0.25), ("Leg_BR", W + R - LG["inset"], L - 0.25)):
        X, Y, Z = cab_pt(x, y, -BELOW)
        X, Y, Z = X / S, Y / S, Z / S
        parts[name] = world_box(X - LG["size"] / 2, X + LG["size"] / 2, 0, Y, Z - LG["size"] / 2, Z + LG["size"] / 2)
    hb = BB["half"]
    parts["Backbox"] = world_box(-hb, hb, BB["y0"], BB["y1"], BB["back"], BB["front"] - 0.06)
    parts["Backglass"] = world_box(-hb + 0.12, hb - 0.12, BB["y0"] + 0.15, BB["y1"] - 0.15, BB["front"] - 0.06, BB["front"])
    parts["LightStrip"] = world_box(-hb, hb, BB["y1"] - 0.12, BB["y1"], BB["front"] - 0.06, BB["front"] + 0.02)
    return {
        "frame": "metres; origin on the floor under the middle of the machine; X to the player's right, Y up, +Z toward the player",
        "tilt_deg": r4(math.degrees(TILT)),
        "playfield_front_left_corner": cab_pt(0, 0, 0),
        "plunger_knob_centre": cab_pt(LY["LANE_X"], CB["ROD_Y0"] - CB["KNOB"], CB["KNOB_H"]),
        "parts_as_8_corners": parts,
        "backglass_face_size": [r4((2 * hb - 0.24) * S), r4((BB["y1"] - BB["y0"] - 0.3) * S)],
        "backglass_text_bands_from_top": {"Title": [0.03, 0.23], "Score": [0.26, 0.50], "Info": [0.52, 0.62], "Say": [0.64, 0.80], "Best": [0.83, 0.95]},
    }


def shared_data():
    f = D["tables"]["pinball_acorn"]["flippers"][0]
    pl = D["tables"]["pinball_acorn"]["plunger"]
    gate = D["tables"]["pinball_acorn"]["gates"][0]
    return {
        "Flipper": {"length_pivot_to_tip_centre": r4(f["len"] * S), "base_radius": r4(f["rBase"] * S), "tip_radius": r4(f["rTip"] * S),
                    "height": r4(CB["FLIPPER_H"] * S), "rest_deg": r4(math.degrees(f["rest"])), "up_deg": r4(math.degrees(f["up"]))},
        "PopBumper": {"made_at_radius": r4(0.12 * S), "body_height": r4(0.16 * S), "cap_radius_share": 0.85, "cap_bottom": r4(0.16 * S), "cap_top": r4(0.2 * S),
                      "scale_per_machine": {"acorn": 1.0, "rodent": r4(0.115 / 0.12), "space": r4(0.11 / 0.12)}},
        "Plunger": {"rod_section": r4(0.035 * S), "rod_length": r4((pl["y"] - BR - CB["ROD_Y0"]) * S), "knob_size": [r4(0.11 * S), r4(0.11 * S), r4(0.1 * S)],
                    "pull_travel": r4(CB["PULL_TRAVEL"] * S)},
        "Gate": {"flap_length": r4(math.hypot(gate["x2"] - gate["x1"], gate["y2"] - gate["y1"]) * S), "flap_thickness": r4(0.012 * S),
                 "flap_bottom": r4(0.05 * S), "flap_top": r4(0.1 * S)},
        "Ball": {"diameter": r4(2 * BR * S)},
    }


DATA = {
    "units": "metres (Roblox: 1 stud = 0.28 m; import with Scale Unit = Meter)",
    "frame_playfield": "X to the player's right, Y up, -Z up the table (the player looks along -Z). Origin: the playfield's front-left corner, on its surface. Points given as [x, z] lie on the surface (y = 0).",
    "shared": shared_data(),
    "cabinet": cabinet_data(),
    "machines": {v: machine_data(v, tid, pre, title) for v, tid, pre, title in MACHINES},
}
json.dump(DATA, open(os.path.join(OUT, "pinball_data.json"), "w"), indent=1)


# ---------------------------------------------------------------- the reference blockouts
def col(c, a=255):
    if isinstance(c, str):
        c = tuple(int(c[i:i + 2], 16) for i in (1, 3, 5))
    return [c[0], c[1], c[2], a]


def paint(m, c):
    m.visual = trimesh.visual.ColorVisuals(m, face_colors=np.tile(col(c), (len(m.faces), 1)))
    return m


def prism(ring_xz, y0, y1):
    """ring of [x, z] points (any winding) extruded from y0 to y1 (GLB frame)"""
    ring = [tuple(p) for p in ring_xz]
    area = sum(ring[i][0] * ring[(i + 1) % len(ring)][1] - ring[(i + 1) % len(ring)][0] * ring[i][1] for i in range(len(ring)))
    if area > 0:  # make it clockwise in (x, z), which is counter-clockwise seen from above (+Y) since z points toward the viewer
        ring = ring[::-1]
    n = len(ring)
    v = [[x, y0, z] for x, z in ring] + [[x, y1, z] for x, z in ring]
    f = []
    for i in range(1, n - 1):
        f.append([0, i + 1, i])
        f.append([n, n + i, n + i + 1])
    for i in range(n):
        j = (i + 1) % n
        f.append([i, j, n + j])
        f.append([i, n + j, n + i])
    m = trimesh.Trimesh(v, f, process=False)
    m.fix_normals()
    return m


def bar(a, b, t, y0, y1):
    dx, dz = b[0] - a[0], b[1] - a[1]
    l = math.hypot(dx, dz) or 1
    nx, nz = -dz / l * t / 2, dx / l * t / 2
    return prism([[a[0] - nx, a[1] - nz], [b[0] - nx, b[1] - nz], [b[0] + nx, b[1] + nz], [a[0] + nx, a[1] + nz]], y0, y1)


def cyl(c, r, y0, y1, k=24):
    return prism([[c[0] + r * math.cos(2 * math.pi * i / k), c[1] + r * math.sin(2 * math.pi * i / k)] for i in range(k)], y0, y1)


def polybar(pts, t, y0, y1):
    parts = [bar(pts[i], pts[i + 1], t, y0, y1) for i in range(len(pts) - 1) if math.dist(pts[i], pts[i + 1]) > 1e-5]
    parts += [cyl(p, t / 2, y0, y1, 8) for p in pts[1:-1]]
    return trimesh.util.concatenate(parts)


def corners_box(c8):
    v = np.array(c8, dtype=float)
    # corners ordered x0/x1, y0/y1, h0/h1 (index = 4*i + 2*j + k)
    q = [(0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)]
    f = []
    for a, b, c, d in q:
        f += [[a, b, c], [a, c, d]]
    m = trimesh.Trimesh(v, f, process=False)
    m.fix_normals()
    return m


def save(name, objects):
    """objects: list of (node name, mesh, translation or None): a node per object, its mesh relative to the node"""
    sc = trimesh.Scene()
    for nm, mesh, at in objects:
        T = np.eye(4)
        if at is not None:
            T[:3, 3] = at
            mesh = mesh.copy()
            mesh.apply_translation(-np.array(at))
        sc.add_geometry(mesh, node_name=nm, geom_name=nm, transform=T)
    sc.export(os.path.join(OUT, "reference", name))


def flipper_mesh(sh):
    ln, rb, rt, h = sh["length_pivot_to_tip_centre"], sh["base_radius"], sh["tip_radius"], sh["height"]
    a = math.acos((rb - rt) / ln)
    ring = [[rb * math.cos(a + (2 * math.pi - 2 * a) * k / 16), -rb * math.sin(a + (2 * math.pi - 2 * a) * k / 16)] for k in range(17)]
    ring += [[ln + rt * math.cos(-a + 2 * a * k / 10), -rt * math.sin(-a + 2 * a * k / 10)] for k in range(11)]
    bat = paint(prism(ring, -h / 2, h / 2), (245, 245, 240))
    tip = paint(cyl([ln, 0], rt * 1.02, -h / 2 * 1.02, h / 2 * 1.02, 16), (230, 60, 50))
    pin = paint(cyl([0, 0], rb * 0.35, -h / 2 * 1.05, h / 2 * 1.05, 12), (40, 40, 44))
    return bat, tip, pin


sh = DATA["shared"]
bat, tip, pin = flipper_mesh(sh["Flipper"])
save("Pinball_Flipper.glb", [("Bat", bat, None), ("Tip", tip, None), ("Pin", pin, None)])
pb = sh["PopBumper"]
save("Pinball_PopBumper.glb", [("Body", paint(cyl([0, 0], pb["made_at_radius"], 0, pb["body_height"], 32), (170, 60, 30)), None),
                               ("Cap", paint(cyl([0, 0], pb["made_at_radius"] * 0.85, pb["cap_bottom"], pb["cap_top"], 32), (255, 236, 180)), None)])
p = sh["Plunger"]
kx, ky, kz = p["knob_size"]
rod = paint(trimesh.creation.box([p["rod_section"], p["rod_section"], p["rod_length"]]), (205, 208, 214))
rod.apply_translation([0, 0, -kz / 2 - p["rod_length"] / 2])  # the rod runs up the table (-Z) from the knob's back face
knob = paint(trimesh.creation.box([kx, ky, kz]), (230, 40, 40))
save("Pinball_Plunger.glb", [("Rod", rod, None), ("Knob", knob, None)])
g = sh["Gate"]
flap = paint(trimesh.creation.box([g["flap_length"], g["flap_top"] - g["flap_bottom"], g["flap_thickness"]]), (205, 208, 214))
flap.apply_translation([0, -(g["flap_top"] - g["flap_bottom"]) / 2, 0])  # hangs from the hinge at its top
save("Pinball_Gate.glb", [("Flap", flap, None)])

cab = DATA["cabinet"]
cols = {"Body": (90, 80, 70), "Glass": (200, 225, 235), "LockdownBar": (205, 208, 214), "CoinDoor": (60, 60, 66), "Backglass": (20, 20, 40),
        "LightStrip": (255, 160, 60), "FlipperButton_L": (230, 40, 40), "FlipperButton_R": (230, 40, 40)}
save("Pinball_Cabinet.glb", [(n, paint(corners_box(c8), cols.get(n, (170, 176, 190) if n.startswith("Leg") else (90, 80, 70))), None)
                             for n, c8 in cab["parts_as_8_corners"].items()])

for v, m in DATA["machines"].items():
    pre, c = m["file_prefix"], m["colours"]
    b, a = m["board"], m["apron"]
    save(f"{pre}_Playfield.glb", [
        ("Board", paint(prism([[b["x0"], b["z_front"]], [b["x1"], b["z_front"]], [b["x1"], b["z_back"]], [b["x0"], b["z_back"]]], -b["thickness"], 0), c["field"]), None),
        ("Apron", paint(prism([[a["x0"], a["z_front"]], [a["x1"], a["z_front"]], [a["x1"], a["z_back"]], [a["x0"], a["z_back"]]], 0, a["top"]), c["apron"]), None)])
    mat_col = {"wood": c["trim"], "metal": (205, 208, 214), "plastic": c["plastic"], "rubber": (245, 245, 240)}
    # the parts that never move, merged by material into a few objects (each object is a separate mesh in the game;
    # fewer meshes draw faster): the walls of each material, and the posts of each material
    objs = []
    for mat in ("wood", "metal", "plastic", "rubber"):
        ws = [polybar(w["points"], w["thickness"], 0, w["height"]) for w in m["walls"] if w["material"] == mat]
        if ws:
            objs.append((f"Guides_{mat.capitalize()}", paint(trimesh.util.concatenate(ws), mat_col[mat]), None))
        ps = [cyl(p_["centre"], p_["radius"], 0, p_["height"], 12) for p_ in m["posts"] if p_["material"] == mat]
        if ps:
            objs.append((f"Posts_{mat.capitalize()}", paint(trimesh.util.concatenate(ps), mat_col[mat]), None))
    save(f"{pre}_Guides.glb", objs)
    objs = []
    for s in m["slingshots"]:
        objs.append((s["body_name"], paint(prism(s["body_triangle"], 0, s["body_height"]), c["plastic"]), None))
        objs.append((s["rubber_name"], paint(bar(s["rubber"][0], s["rubber"][1], s["rubber_thickness"], 0, s["rubber_height"]), (245, 245, 240)), None))
    save(f"{pre}_Slingshots.glb", objs)
    objs = []
    for t in m["targets"]:
        mid = [(t["a"][0] + t["b"][0]) / 2, 0.0, (t["a"][1] + t["b"][1]) / 2]
        objs.append((t["name"], paint(bar(t["a"], t["b"], t["thickness"], 0, t["height"]), c["target"]), mid))
    save(f"{pre}_Targets.glb", objs)
    if m["spinners"]:
        objs = []
        for s in m["spinners"]:
            mid = [(s["a"][0] + s["b"][0]) / 2, s["axis_height"], (s["a"][1] + s["b"][1]) / 2]
            objs.append((s["name"], paint(bar(s["a"], s["b"], s["flag_thickness"], s["axis_height"] - s["flag_height"] / 2, s["axis_height"] + s["flag_height"] / 2), (205, 208, 214)), mid))
        save(f"{pre}_Spinner.glb", objs)
    if m["ramps"]:
        objs = []
        for r in m["ramps"]:
            pts, hw = r["path"], r["track_width"] / 2
            parts = []
            for i in range(len(pts) - 1):
                (x1, y1, z1), (x2, y2, z2) = pts[i], pts[i + 1]
                dx, dz = x2 - x1, z2 - z1
                l = math.hypot(dx, dz) or 1
                nx, nz = -dz / l * hw, dx / l * hw
                vv = [[x1 - nx, y1 - 0.0056, z1 - nz], [x2 - nx, y2 - 0.0056, z2 - nz], [x2 + nx, y2 - 0.0056, z2 + nz], [x1 + nx, y1 - 0.0056, z1 + nz],
                     [x1 - nx, y1, z1 - nz], [x2 - nx, y2, z2 - nz], [x2 + nx, y2, z2 + nz], [x1 + nx, y1, z1 + nz]]
                f = [[0, 2, 1], [0, 3, 2], [4, 5, 6], [4, 6, 7], [0, 1, 5], [0, 5, 4], [1, 2, 6], [1, 6, 5], [2, 3, 7], [2, 7, 6], [3, 0, 4], [3, 4, 7]]
                seg = trimesh.Trimesh(vv, f, process=False)
                seg.fix_normals()
                parts.append(seg)
            objs.append((r["name"], paint(trimesh.util.concatenate(parts), c["plastic"]), None))
        save(f"{pre}_{'Wire' if v == 'rodent' else 'Ramps'}.glb", objs)
print("pack written:", sorted(os.listdir(os.path.join(OUT, "reference"))))
