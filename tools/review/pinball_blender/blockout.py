# Writes one Wavefront OBJ blockout per pinball playfield (and the cabinet), in metres at Roblox's 0.28 m per
# stud, Y up, the playfield lying flat (the game pitches it 0.12 rad toward the player), X to the player's
# right, -Z up the table (so the player looks along -Z, Blender's OBJ import maps this to a Z-up scene).
# Origin: the playfield's front-left corner on its surface. Every part is its own named object.
# Usage: python3 blockout.py tables.json OUTDIR
import json, math, sys, os

D = json.load(open(sys.argv[1]))
OUT = sys.argv[2]
LY, CB = D["layout"], D["cabinet"]
W, L, BR, XC = LY["WIDTH"], LY["LENGTH"], LY["BALL_R"], LY["XC"]
S = 0.28
WALL = {"wood": (0.06, 0.2), "metal": (0.022, 0.11), "plastic": (0.045, 0.1), "rubber": (0.035, 0.08)}


class Obj:
    def __init__(self, tilt=False):
        self.lines, self.nv, self.tilt = [], 0, tilt
        self.mats = set()

    def begin(self, name, mat):
        self.lines.append(f"o {name}")
        self.lines.append(f"usemtl {mat}")
        self.mats.add(mat)

    def v(self, x, y, h):  # playfield frame (studs) -> OBJ (metres)
        if self.tilt:  # the cabinet: the playfield frame set down as the game does (floor at 0, machine's middle at 0)
            lat, Y, Z = cab_pt(x, y, h)
            return self.wv(lat, Y, Z)
        self.lines.append(f"v {x * S:.5f} {h * S:.5f} {-y * S:.5f}")
        self.nv += 1
        return self.nv

    def wv(self, X, Y, Z):  # world: X to the player's right, Y up from the floor, Z toward the player (studs)
        self.lines.append(f"v {X * S:.5f} {Y * S:.5f} {Z * S:.5f}")
        self.nv += 1
        return self.nv

    def wbox(self, x0, x1, y0, y1, z0, z1):
        c = [self.wv(x, y, z) for x in (x0, x1) for y in (y0, y1) for z in (z0, z1)]
        for q in ((0, 1, 3, 2), (4, 6, 7, 5), (0, 4, 5, 1), (2, 3, 7, 6), (0, 2, 6, 4), (1, 5, 7, 3)):
            self.lines.append("f " + " ".join(str(c[i]) for i in q))

    def prism(self, ring, h0, h1):
        """ring: list of (x, y) counter-clockwise seen from above; extruded from h0 to h1."""
        n = len(ring)
        lo = [self.v(x, y, h0) for x, y in ring]
        hi = [self.v(x, y, h1) for x, y in ring]
        self.lines.append("f " + " ".join(str(i) for i in reversed(lo)))
        self.lines.append("f " + " ".join(str(i) for i in hi))
        for i in range(n):
            j = (i + 1) % n
            self.lines.append(f"f {lo[i]} {lo[j]} {hi[j]} {hi[i]}")

    def cyl(self, x, y, r, h0, h1, k=20):
        self.prism([(x + r * math.cos(2 * math.pi * i / k), y + r * math.sin(2 * math.pi * i / k)) for i in range(k)], h0, h1)

    def bar(self, x1, y1, x2, y2, t, h0, h1):
        dx, dy = x2 - x1, y2 - y1
        l = math.hypot(dx, dy) or 1
        nx, ny = -dy / l * t / 2, dx / l * t / 2
        ring = [(x1 - nx, y1 - ny), (x2 - nx, y2 - ny), (x2 + nx, y2 + ny), (x1 + nx, y1 + ny)]
        self.prism(ring, h0, h1)

    def box(self, x0, x1, y0, y1, h0, h1):
        self.prism([(x0, y0), (x1, y0), (x1, y1), (x0, y1)], h0, h1)

    def ball(self, x, y, h, r, k=12):
        top, rows = [], []
        for a in range(1, k):
            phi = math.pi * a / k
            rows.append([self.v(x + r * math.sin(phi) * math.cos(2 * math.pi * b / k), y + r * math.sin(phi) * math.sin(2 * math.pi * b / k),
                                h + r * math.cos(phi)) for b in range(k)])
        n, s = self.v(x, y, h + r), self.v(x, y, h - r)
        for b in range(k):
            c = (b + 1) % k
            self.lines.append(f"f {n} {rows[0][b]} {rows[0][c]}")
            self.lines.append(f"f {s} {rows[-1][c]} {rows[-1][b]}")
            for a in range(len(rows) - 1):
                self.lines.append(f"f {rows[a][b]} {rows[a + 1][b]} {rows[a + 1][c]} {rows[a][c]}")

    def write(self, path, colours):
        mtl = os.path.basename(path)[:-4] + ".mtl"
        with open(os.path.join(os.path.dirname(path), mtl), "w") as f:
            for m in sorted(self.mats):
                c = colours.get(m, (200, 200, 200))
                f.write(f"newmtl {m}\nKd {c[0] / 255:.3f} {c[1] / 255:.3f} {c[2] / 255:.3f}\n\n")
        with open(path, "w") as f:
            f.write(f"# {os.path.basename(path)}: blockout in metres (1 stud = 0.28 m), Y up, -Z up the table\nmtllib {mtl}\n")
            f.write("\n".join(self.lines) + "\n")


def flipper_ring(f, angle):
    s = -1 if f["mirror"] else 1
    px, py, ln, rb, rt = f["x"], f["y"], f["len"], f["rBase"], f["rTip"]
    tx, ty = px + s * math.cos(angle) * ln, py + math.sin(angle) * ln
    ang = math.atan2(ty - py, tx - px)
    a = math.acos((rb - rt) / ln)
    pts = [(px + rb * math.cos(ang + a + (2 * math.pi - 2 * a) * k / 16), py + rb * math.sin(ang + a + (2 * math.pi - 2 * a) * k / 16)) for k in range(17)]
    pts += [(tx + rt * math.cos(ang - a + 2 * a * k / 10), ty + rt * math.sin(ang - a + 2 * a * k / 10)) for k in range(11)]
    return pts


def table(tid, variant):
    t, th = D["tables"][tid], D["themes"][variant]
    o = Obj()
    o.begin("Playfield_board", "field"); o.box(0, W, -0.16, L, -0.06, 0)
    o.begin("Apron", "apron"); o.box(XC - 0.75, XC + 0.75, -0.16, t["drainY"] + 0.1, 0, 0.06)
    for i, w in enumerate(t["walls"], 1):
        tt, hh = WALL[w["mat"]]
        p = w["pts"]
        o.begin(f"Wall{i:02d}_{w['mat']}", w["mat"])
        for k in range(0, len(p) - 3, 2):
            if math.hypot(p[k + 2] - p[k], p[k + 3] - p[k + 1]) > 1e-4:
                o.bar(p[k], p[k + 1], p[k + 2], p[k + 3], tt, 0, hh)
    for i, p in enumerate(t["posts"], 1):
        o.begin(f"Post{i:02d}_{p['mat']}", "rubber" if p["mat"] == "rubber" else "metal")
        o.cyl(p["x"], p["y"], p["r"], 0, 0.11 if p["mat"] == "rubber" else 0.14, 12)
    for i, b in enumerate(t["bumpers"], 1):
        o.begin(f"PopBumper{i}_body", "bumper"); o.cyl(b["x"], b["y"], b["r"], 0, 0.16, 24)
        o.begin(f"PopBumper{i}_cap", "cap"); o.cyl(b["x"], b["y"], b["r"] * 0.85, 0.16, 0.2, 24)
    for s in t["slings"]:
        o.begin(f"Slingshot_{s['id'][-1].upper()}_rubber", "rubber"); o.bar(s["x1"], s["y1"], s["x2"], s["y2"], 0.035, 0, 0.09)
    for w in t["walls"]:
        p = w["pts"]
        if w["mat"] == "plastic" and len(p) == 6:
            for s in t["slings"]:
                if abs(p[0] - s["x1"]) < 1e-6 and abs(p[1] - s["y1"]) < 1e-6:
                    ring = [(p[0], p[1]), (p[2], p[3]), (p[4], p[5])]
                    area = sum(ring[i][0] * ring[(i + 1) % 3][1] - ring[(i + 1) % 3][0] * ring[i][1] for i in range(3))
                    o.begin(f"Slingshot_{s['id'][-1].upper()}_body", "plastic")
                    o.prism(ring if area > 0 else ring[::-1], 0, 0.1)
    for tg in t["targets"]:
        o.begin(f"{'DropTarget' if tg['kind'] == 'drop' else 'Standup'}_{tg['id']}", "target")
        o.bar(tg["x1"], tg["y1"], tg["x2"], tg["y2"], 0.03, 0, 0.12)
    for s in t["sensors"]:
        if s["kind"] == "spinner":
            o.begin(f"Spinner_{s['id']}", "metal"); o.bar(s["x1"], s["y1"], s["x2"], s["y2"], 0.008, 0.05, 0.15)
        else:
            mx, my = (s["x1"] + s["x2"]) / 2, (s["y1"] + s["y2"]) / 2
            o.begin(f"Rollover_{s['id']}", "metal"); o.bar(mx, my - 0.04, mx, my + 0.04, 0.012, 0, 0.01)
    for g in t["gates"]:
        o.begin(f"Gate_{g['id']}", "metal"); o.bar(g["x1"], g["y1"], g["x2"], g["y2"], 0.012, 0.05, 0.1)
    for sc in t["saucers"]:
        o.begin(f"Hole_{sc['id']}", "dark"); o.cyl(sc["x"], sc["y"], sc["r"] + BR, 0, 0.004, 24)
    for r in t["rails"]:
        p = r["pts"]
        o.begin(f"Ramp_{r['id']}", "plastic")
        for k in range(0, len(p) - 5, 3):
            x1, y1, h1, x2, y2, h2 = p[k:k + 6]
            dx, dy = x2 - x1, y2 - y1
            l = math.hypot(dx, dy) or 1
            nx, ny = -dy / l * (BR + 0.03), dx / l * (BR + 0.03)
            a = [o.v(x1 - nx, y1 - ny, h1 - 0.02), o.v(x2 - nx, y2 - ny, h2 - 0.02), o.v(x2 + nx, y2 + ny, h2 - 0.02), o.v(x1 + nx, y1 + ny, h1 - 0.02)]
            b = [o.v(x1 - nx, y1 - ny, h1), o.v(x2 - nx, y2 - ny, h2), o.v(x2 + nx, y2 + ny, h2), o.v(x1 + nx, y1 + ny, h1)]
            o.lines.append("f " + " ".join(map(str, b))); o.lines.append("f " + " ".join(map(str, reversed(a))))
            for i in range(4):
                j = (i + 1) % 4
                o.lines.append(f"f {a[i]} {a[j]} {b[j]} {b[i]}")
    for l in t["lamps"]:
        o.begin(f"Lamp_{l['id']}_{l['colour']}", f"lamp_{l['colour']}"); o.cyl(l["x"], l["y"], 0.05, 0, 0.006, 16)
    for f in t["flippers"]:
        o.begin(f"Flipper_{'L' if f['button'] == 'left' else 'R'}", "rubber"); o.prism(flipper_ring(f, f["rest"])[::-1] if f["mirror"] else flipper_ring(f, f["rest"]), 0, CB["FLIPPER_H"])
    pl = t["plunger"]
    o.begin("Plunger_rod", "metal"); o.box(pl["x"] - 0.0175, pl["x"] + 0.0175, CB["ROD_Y0"], pl["y"] - BR, 0.0225, 0.0575)
    o.begin("Plunger_knob", "red"); o.box(pl["x"] - 0.055, pl["x"] + 0.055, CB["ROD_Y0"] - CB["KNOB"] - 0.05, CB["ROD_Y0"] - CB["KNOB"] + 0.05, -0.015, 0.095)
    o.begin("Ball", "metal"); o.ball(pl["x"], pl["y"], BR, BR)
    LAMPS = {"red": (255, 60, 50), "green": (80, 255, 110), "amber": (255, 170, 40), "yellow": (255, 236, 70),
             "orange": (255, 130, 30), "white": (255, 250, 235), "blue": (80, 150, 255)}
    cols = {"field": th["field"], "apron": th["apron"], "wood": th["trim"], "metal": (205, 208, 214), "plastic": th["plastic"],
            "rubber": (245, 245, 240), "bumper": th["bumper"], "cap": th["cap"], "target": th["target"], "dark": (24, 24, 26), "red": (230, 40, 40)}
    cols.update({f"lamp_{k}": v for k, v in LAMPS.items()})
    o.write(os.path.join(OUT, f"{variant}_playfield_blockout.obj"), cols)


def cab_pt(x, y, h):
    along = y - L / 2
    sn, cs = math.sin(LY["TILT"]), math.cos(LY["TILT"])
    return x - W / 2, CB["PF_Y"] + along * sn + h * cs, CB["PF_D"] - (along * cs - h * sn)


def cabinet():
    # in the playfield frame too, as the bake builds it (h below the surface is negative)
    R, G, below = CB["RAIL"], CB["GLASS_H"], 0.85
    o = Obj(tilt=True)
    o.begin("Body_floor", "body"); o.box(-R, W + R, -0.27, L + 0.09, -below, -below + 0.12)
    o.begin("SideWall_L", "body"); o.box(-R, 0, -0.27, L + 0.09, -below, G + 0.05)
    o.begin("SideWall_R", "body"); o.box(W, W + R, -0.27, L + 0.09, -below, G + 0.05)
    o.begin("FrontWall", "body"); o.box(-R, W + R, -0.27, -0.15, -below, G + 0.05)
    o.begin("BackWall", "body"); o.box(-R, W + R, L, L + 0.08, -below, G)
    o.begin("LockdownBar", "metal"); o.box(-R - 0.02, W + R + 0.02, -0.275, -0.145, G + 0.055, G + 0.105)
    o.begin("Glass", "glass"); o.box(0, W, 0, L, G - 0.01, G + 0.01)
    B = CB["BUTTON"]
    for name, x in (("FlipperButton_L", -R - B["out"]), ("FlipperButton_R", W + R + B["out"])):
        o.begin(name, "red"); o.box(x - B["length"] / 2, x + B["length"] / 2, B["y"] - B["size"] / 2, B["y"] + B["size"] / 2, B["h"] - B["size"] / 2, B["h"] + B["size"] / 2)
    o.begin("CoinDoor", "metal"); o.box(W / 2 - 0.35, W / 2 + 0.35, -0.3, -0.27, -below / 2 - 0.325, -below / 2 + 0.225)
    LG, BB = CB["LEGS"], CB["BACKBOX"]
    for name, x, y in (("Leg_FL", -R + LG["inset"], -0.05), ("Leg_FR", W + R - LG["inset"], -0.05), ("Leg_BL", -R + LG["inset"], L - 0.25), ("Leg_BR", W + R - LG["inset"], L - 0.25)):
        X, Y, Z = cab_pt(x, y, -below)
        o.begin(name, "metal"); o.wbox(X - LG["size"] / 2, X + LG["size"] / 2, 0, Y, Z - LG["size"] / 2, Z + LG["size"] / 2)
    hb = BB["half"]
    o.begin("Backbox", "body"); o.wbox(-hb, hb, BB["y0"], BB["y1"], BB["back"], BB["front"] - 0.06)
    o.begin("Backglass", "glassart"); o.wbox(-hb + 0.12, hb - 0.12, BB["y0"] + 0.15, BB["y1"] - 0.15, BB["front"] - 0.06, BB["front"])
    o.begin("Backbox_lightstrip", "neon"); o.wbox(-hb, hb, BB["y1"] - 0.12, BB["y1"], BB["front"] - 0.06, BB["front"] + 0.02)
    o.begin("PlayfieldBoard_reference", "field"); o.box(0, W, -0.16, L, -0.06, 0)
    o.write(os.path.join(OUT, "cabinet_body_blockout.obj"), {"body": (90, 80, 70), "metal": (205, 208, 214), "glass": (200, 225, 235), "red": (230, 40, 40), "glassart": (20, 20, 40), "neon": (255, 160, 60), "field": (200, 170, 110)})


os.makedirs(OUT, exist_ok=True)
for tid, v in (("pinball_acorn", "acorn"), ("pinball_rodent", "rodent"), ("pinball_space", "space")):
    table(tid, v)
cabinet()
print(sorted(os.listdir(OUT)))
