"""tools/review/alley_plan.py: the bowling alley's floor plan, labelled (brief addendum D4, D5).

  lune run tools/bake/attractions.luau && lune run tools/review/alley_plan.luau
  python3 -I tools/review/alley_plan.py [--data build/review_alley/plan.json] [--out docs/renders/alley18/00_plan.png]

Drawn as a bowler sees the building: the street and the main doors at the bottom, lane 1 on the left, the pins and
the back of house at the top (so north is DOWN and the alley's +X is to the right). What is drawn is what the bake
built (every part of build/Attractions.rbxm that stands on the floor below head height, in its own colour; walls
dark, glass blue), with the plan of Shared/Attractions/AlleyLayout laid over it: the rooms and their names, every
opening, the games' tables and the floor each keeps clear, the staff posts and walking routes, where a player
presses E, and the owner's backstage (anchor, the ground kept for it, the interim back module it replaces).
The small map shows the building on its site with the planned neighbours (data/expansion.json), south up to match.
System python3 + Pillow only.
"""
import argparse
import json
import math

from PIL import Image, ImageDraw, ImageFont

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
INK = (34, 36, 40)
PAPER = (246, 242, 232)
S = 8.0  # pixels per stud
VIEW = {"x0": -50.0, "x1": 186.0, "d0": -99.0, "d1": 112.0}

ZONE_FILL = {
    "ball_shop": (186, 212, 240),
    "shoe_rental": (250, 226, 164),
    "lobby": (244, 236, 214),
    "gift_shop": (244, 202, 220),
    "snack_bar": (250, 206, 166),
    "lockers": (214, 214, 224),
    "concourse": (228, 204, 196),
    "settees": (232, 216, 204),
    "approaches": (228, 200, 150),
    "lanes": (240, 220, 170),
    "left_aisle": (216, 196, 188),
    "right_aisle": (216, 196, 188),
    "games_room": (196, 226, 202),
    "back_corridor": (206, 206, 214),
    "rear_alley": (190, 190, 186),
    "forecourt": (222, 222, 214),
}
OPENING_COL = {
    "door": (20, 150, 70),
    "arch": (20, 150, 70),
    "open": (90, 180, 110),
    "counter": (226, 120, 20),
    "window": (226, 120, 20),
    "exit": (200, 40, 40),
}
OPENING_WORD = {
    "door": "door",
    "arch": "arch",
    "open": "open front",
    "counter": "counter",
    "window": "window",
    "exit": "exit doors",
}
SKIP_MODELS = {
    "Foundation", "Tunnels", "TerrainCarve", "Ceilings", "HouseLights", "LaneLights", "Scoreboards", "Floors",
    "ServiceFrontCenter",
}
FLAT_MODELS = {"Lanes", "Approach", "Forecourt"}  # drawn whole, floors and all
# Where the planned neighbours stood before 2026-11-13 (world studs), drawn as ghosts on the site map.
MOVED = [
    ("lounge one", (1374, -390, 1424, -334)),
    ("lounge two", (1432, -390, 1482, -334)),
    ("racquet club", (1494, -418, 1558, -334)),
]
OLD_EDGES = [
    ("Liberty Green's old north edge", ((1155, -574), (1385, -574))),
    ("steakhouse site's old east edge", ((1255, -545), (1255, -330))),
]


def font(size, bold=False):
    return ImageFont.truetype(BOLD if bold else FONT, size)


class Panel:
    """A drawing surface in plan studs: X to the right, D up the page."""

    def __init__(self, x0, x1, d0, d1, scale):
        self.x0, self.x1, self.d0, self.d1, self.s = x0, x1, d0, d1, scale
        self.w, self.h = int((x1 - x0) * scale), int((d1 - d0) * scale)
        self.img = Image.new("RGB", (self.w, self.h), (206, 218, 190))
        self.d = ImageDraw.Draw(self.img, "RGBA")

    def P(self, x, d):
        return ((x - self.x0) * self.s, (self.d1 - d) * self.s)

    def rect(self, x0, x1, d0, d1, fill=None, outline=None, width=1):
        a, b = self.P(min(x0, x1), max(d0, d1))
        c, e = self.P(max(x0, x1), min(d0, d1))
        if c - a < 1:
            c = a + 1
        if e - b < 1:
            e = b + 1
        self.d.rectangle([a, b, c, e], fill=fill, outline=outline, width=width)

    def ellipse(self, x0, x1, d0, d1, fill=None, outline=None, width=1):
        a, b = self.P(min(x0, x1), max(d0, d1))
        c, e = self.P(max(x0, x1), min(d0, d1))
        self.d.ellipse([a, b, max(c, a + 1), max(e, b + 1)], fill=fill, outline=outline, width=width)

    def line(self, pts, fill, width=1, dash=None):
        q = [self.P(x, d) for x, d in pts]
        if not dash:
            self.d.line(q, fill=fill, width=width, joint="curve")
            return
        on, off = dash
        for i in range(len(q) - 1):
            (ax, ay), (bx, by) = q[i], q[i + 1]
            length = math.hypot(bx - ax, by - ay)
            if length < 1e-6:
                continue
            t = 0.0
            while t < length:
                t1 = min(length, t + on)
                self.d.line(
                    [(ax + (bx - ax) * t / length, ay + (by - ay) * t / length),
                     (ax + (bx - ax) * t1 / length, ay + (by - ay) * t1 / length)],
                    fill=fill, width=width)
                t += on + off

    def dashed_rect(self, x0, x1, d0, d1, fill, width=1, dash=(8, 5)):
        self.line([(x0, d0), (x1, d0), (x1, d1), (x0, d1), (x0, d0)], fill, width, dash)

    def text(self, x, d, s, size, fill=INK, bold=False, halo=True, anchor="mm", dx=0, dy=0):
        f = font(size, bold)
        u, v = self.P(x, d)
        kw = {}
        if halo:
            kw = {"stroke_width": max(2, size // 6), "stroke_fill": (255, 255, 255, 225)}
        if "\n" in s:
            self.d.multiline_text((u + dx, v + dy), s, font=f, fill=fill, anchor=anchor, align="center",
                                  spacing=2, **kw)
        else:
            self.d.text((u + dx, v + dy), s, font=f, fill=fill, anchor=anchor, **kw)

    def dot(self, x, d, r, fill, outline=(255, 255, 255, 255), label=None, size=10):
        u, v = self.P(x, d)
        self.d.ellipse([u - r, v - r, u + r, v + r], fill=fill, outline=outline, width=1)
        if label:
            self.d.text((u, v + 0.5), label, font=font(size, True), fill=(255, 255, 255), anchor="mm")


def draw_boxes(pn, data):
    K = data["K"]
    rear = K["REAR_WALL_D"] + K["WALL_T"] - 0.01
    alley_y = -3.5
    drawn = []
    for b in data["boxes"]:
        model, name, x0, x1, d0, d1, y0, y1, r, g, bl, t, _mat, shape = b
        if model in SKIP_MODELS or t >= 0.95:
            continue
        fy = alley_y if d0 >= rear else 0.0
        if y0 - fy >= 7.0:
            continue  # overhead: signs, lights, wall heads over the openings
        flat = model in FLAT_MODELS
        if not flat and y1 - fy <= 0.15:
            continue  # floors, paving, things under the floor
        wall = (not flat) and y0 - fy <= 1.2 and y1 - fy >= 6.9
        drawn.append((1 if wall else 0, y1, wall, flat, b))
    drawn.sort(key=lambda e: (e[0], e[1]))
    for _, _, wall, flat, b in drawn:
        _model, _name, x0, x1, d0, d1, _y0, _y1, r, g, bl, t, _mat, shape = b
        if wall:
            if t > 0.2:
                pn.rect(x0, x1, d0, d1, fill=(140, 196, 232, 255), outline=(70, 110, 150, 255))
            else:
                pn.rect(x0, x1, d0, d1, fill=(58, 58, 66, 255))
            continue
        col = (r, g, bl, 255)
        edge = None if flat else (60, 60, 60, 150)
        round_ = shape in ("Ball", "Cylinder") and abs((x1 - x0) - (d1 - d0)) < 0.06
        if round_:
            pn.ellipse(x0, x1, d0, d1, fill=col, outline=edge)
        else:
            pn.rect(x0, x1, d0, d1, fill=col, outline=edge)


def draw_plan(data):
    K = data["K"]
    pn = Panel(VIEW["x0"], VIEW["x1"], VIEW["d0"], VIEW["d1"], S)

    # the street side (planned, data only: generated/Expansion)
    pl = data["place"]
    for sp in data["site"]["strips"]:
        col = (120, 120, 124, 255) if sp["kind"] == "asphalt" else (190, 190, 186, 255)
        da, db = pl["z"] - (sp["z"] - sp["w"] / 2), pl["z"] - (sp["z"] + sp["w"] / 2)
        pn.rect(sp["x0"] - pl["x"], sp["x1"] - pl["x"], da, db, fill=col)
    for path in data["site"]["paths"]:
        (ax, az), (bx, bz) = path["points"][0], path["points"][-1]
        if abs(ax - bx) < 0.01:
            pn.rect(ax - pl["x"] - path["w"] / 2, ax - pl["x"] + path["w"] / 2, pl["z"] - az, pl["z"] - bz,
                    fill=(190, 190, 186, 255))
    pn.text((VIEW["x0"] + VIEW["x1"]) / 2, -93,
            "BOWL LANE's south sidewalk (planned street, not built yet); Main Street is 290 studs further this way",
            13, bold=True)

    # rooms
    for z in data["zones"]:
        fill = ZONE_FILL.get(z["id"], (230, 230, 230))
        pn.rect(z["x0"], z["x1"], z["d0"], z["d1"], fill=fill + (255,))

    draw_boxes(pn, data)

    # the nine tunnels under the floor
    for tn in data["tunnels"]:
        pts = [(p[0], p[1]) for p in tn["points"]]
        pn.line(pts, (120, 70, 20, 255), 2, (3, 5))

    # the floor each table keeps clear
    for st in data["standing"]:
        pn.dashed_rect(st["x0"], st["x1"], st["d0"], st["d1"], (20, 110, 60, 220), 1, (5, 4))

    # air hockey: the reserved table
    ah, size = data["airHockey"], data["airHockeySize"]
    along_x = abs(math.cos(ah["yaw"])) > 0.5
    hx = size["along"] / 2 if along_x else size["across"] / 2
    hd = size["across"] / 2 if along_x else size["along"] / 2
    pn.rect(ah["x"] - hx, ah["x"] + hx, ah["d"] - hd, ah["d"] + hd, fill=(120, 190, 240, 150),
            outline=(20, 70, 160, 255), width=2)
    for sgn in (-1, 1):
        px = ah["x"] + sgn * (hx + 2) if along_x else ah["x"]
        pd = ah["d"] if along_x else ah["d"] + sgn * (hd + 2)
        pn.dot(px, pd, 5, (20, 70, 160, 255))
    pn.text(ah["x"], ah["d"], "AIR HOCKEY\n(reserved)", 12, fill=(10, 50, 130), bold=True)

    # darts: the oche
    b = data["board"]
    pn.line([(b["ocheX"], b["d"] - 1.6), (b["ocheX"], b["d"] + 1.6)], (200, 40, 40, 255), 3)
    pn.text(b["ocheX"] - 0.6, b["d"], "oche", 11, fill=(160, 30, 30), anchor="rm")
    pn.text((b["ocheX"] + b["x"]) / 2, b["d"] + 3.0, "DARTS", 12, bold=True)

    # openings
    T = 0.8
    for o in data["openings"]:
        col = OPENING_COL[o["kind"]] + (255,)
        if o["axis"] == "x":
            pn.rect(o["a"], o["b"], o["at"] - T / 2, o["at"] + T / 2, outline=col, width=3)
        else:
            pn.rect(o["at"] - T / 2, o["at"] + T / 2, o["a"], o["b"], outline=col, width=3)

    # walking routes
    for _id, pts in sorted(data["routes"].items()):
        pn.line([(p[0], p[1]) for p in pts], (120, 60, 170, 200), 2, (2, 5))

    # where a player presses E
    for st in data["stations"]:
        u, v = pn.P(st["x"], st["d"])
        pn.d.rectangle([u - 6, v - 6, u + 6, v + 6], fill=(240, 150, 20, 255), outline=(255, 255, 255, 255))
        pn.d.text((u, v + 0.5), "E", font=font(10, True), fill=(255, 255, 255), anchor="mm")

    # staff posts
    for i, p in enumerate(data["posts"]):
        pn.dot(p["x"], p["d"], 8, (120, 60, 170, 255), label=str(i + 1), size=10)
    for p in data["machinePosts"]:
        pn.dot(p["x"], p["d"], 3, (120, 60, 170, 255))

    # the backstage
    bs = data["backstage"]
    rs = bs["reserve"]
    pn.dashed_rect(rs["x0"], rs["x1"], rs["d0"], min(rs["d1"], VIEW["d1"] + 5), (200, 30, 30, 255), 3, (12, 7))
    it = bs["interim"]
    pn.dashed_rect(it["x0"], it["x1"], it["d0"], it["d1"], (30, 60, 200, 255), 3, (6, 5))
    a = bs["anchor"]
    u, v = pn.P(a["x"], a["d"])
    pn.d.line([(u - 9, v), (u + 9, v)], fill=(200, 30, 30, 255), width=3)
    pn.d.line([(u, v - 9), (u, v + 9)], fill=(200, 30, 30, 255), width=3)
    pn.d.ellipse([u - 5, v - 5, u + 5, v + 5], outline=(200, 30, 30, 255), width=2)
    pn.text(a["x"], a["d"], f'{bs["anchorName"]}  (the backstage\'s anchor: floor, middle of the lane tails)', 12,
            fill=(170, 20, 20), bold=True, anchor="lm", dx=14)

    # the declared footprint
    fp = data["footprint"]
    pn.dashed_rect(fp["x0"], fp["x1"], fp["d0"], fp["d1"], (90, 90, 90, 200), 1, (3, 4))
    pn.text(fp["x0"] + 1, fp["d1"] - 1.3, "footprint declared in data/attractions.json", 11, fill=(80, 80, 80),
            anchor="lm")

    # labels: rooms
    def room(zid, text, size=15, dx=0.0, dd=0.0, dims=True, sep="\n"):
        z = next(q for q in data["zones"] if q["id"] == zid)
        cx, cd = (z["x0"] + z["x1"]) / 2 + dx, (z["d0"] + z["d1"]) / 2 + dd
        s = text
        if dims:
            s += f'{sep}{z["x1"] - z["x0"]:.0f} x {z["d1"] - z["d0"]:.0f}'
        pn.text(cx, cd, s, size, bold=True)

    room("ball_shop", "BOWLING BALL SHOP")
    room("shoe_rental", "SHOE RENTAL", 13, dx=0.4, dd=-7.6)
    room("lobby", "LOBBY", 13, dx=3.3, dd=-1.5)
    room("gift_shop", "GIFT SHOP")
    room("snack_bar", "SNACK BAR", dd=-3)
    room("lockers", "LOCKERS", 12, dd=-3)
    room("concourse", "CONCOURSE", 17, dx=-20, dd=4)
    room("settees", "SETTEES AND SCORING CONSOLES", 12, dd=2.8, dims=False)
    room("games_room", "GAMES ROOM  (the activity room)", 17, dx=-2, dd=-8.5)
    room("back_corridor", "INTERIM BACK CORRIDOR  (stand-in pinsetters, mechanic's bench)", 13, dd=3.2, dims=False)
    room("rear_alley", "REAR ALLEY  (3.5 below the floor: the blue cans, the broom, nine tunnel vents)", 13, dd=4,
         dims=False)
    room("forecourt", "FORECOURT\nlanding and ramp", 12, dx=24, dims=False)
    room("left_aisle", "AISLE", 11, dd=14, dims=False)
    room("right_aisle", "AISLE", 11, dd=14, dims=False)
    pn.text((K["LANE_BLOCK_X0"] + K["LANE_BLOCK_X1"]) / 2, 30,
            "EIGHTEEN LANES IN NINE PAIRS  (112 wide; lanes 1 to 6 are where the six-lane house had them)", 16,
            bold=True)
    pn.text((K["LANE_BLOCK_X0"] + K["LANE_BLOCK_X1"]) / 2, 61.5,
            "pin decks, pits and the masking units", 12, bold=True)
    for ln in data["lanes"]:
        pn.text(ln["x"], -3.2, str(ln["n"]), 16, bold=True)
    for pr in data["pairs"]:
        pn.text(pr["x"], -12.6, "return", 9, fill=(90, 60, 30))
    pn.text(data["pairs"][4]["x"], 44, "under each pair: a ball-return tunnel\n(a squirrel route, vent to rack)", 11,
            fill=(110, 60, 15), bold=True)

    # labels: the games
    for i, t in enumerate(data["pool"]):
        pn.text(t["x"], t["d"], f"POOL {i + 1}", 13, bold=True)
    bp = data["bumper"]
    pn.text(bp["x"], bp["d"] + 5.6, "BUMPER POOL", 12, bold=True)
    pbs = data["pinballs"]
    pn.text((pbs[0]["x"] + pbs[-1]["x"]) / 2, K["PINBALL_D"] + 7.2, "PINBALL x 3\n(acorn, rodent, space)", 12, bold=True)
    f = data["fortune"]
    pn.text(f["x"] - 4.5, f["d"] + 1.0, "FORTUNE\nTELLER", 12, bold=True, anchor="rm")

    # labels: openings
    for o in data["openings"]:
        col = tuple(int(c * 0.75) for c in OPENING_COL[o["kind"]])
        mid = (o["a"] + o["b"]) / 2
        word = OPENING_WORD[o["kind"]]
        if o["id"] == "entrance":
            pn.text(mid, o["at"] - 1.6, "MAIN DOORS", 14, fill=col, bold=True, anchor="mt")
        elif o["axis"] == "x":
            pn.text(mid, o["at"] + 1.3, word, 11, fill=col, bold=True)
        elif o["id"] == "shoe_desk":
            pn.text(o["at"] - 1.0, o["a"] + 3.4, "desk", 11, fill=col, bold=True, anchor="rm")
        else:
            pn.text(o["at"] - 1.0, mid, word, 11, fill=col, bold=True, anchor="rm")

    # labels: the backstage
    pn.text((rs["x0"] + rs["x1"]) / 2, 106.5,
            f'GROUND KEPT FREE FOR THE OWNER\'S BACKSTAGE  (red line: {rs["x1"] - rs["x0"]:.0f} wide, from the masking '
            f'units back {rs["d1"] - rs["d0"]:.0f} studs; it runs {rs["d1"] - VIEW["d1"]:.0f} further up this page)',
            14, fill=(170, 20, 20), bold=True)
    pn.text(it["x1"] - 1, it["d1"] + 1.7,
            "blue line: THE INTERIM BACK MODULE (one model; the backstage replaces everything inside it)", 13,
            fill=(20, 40, 170), bold=True, anchor="rm")

    # scale bar and compass
    x, d = VIEW["x0"] + 6, VIEW["d0"] + 14
    pn.line([(x, d), (x + 20, d)], INK, 4)
    for k in (0, 10, 20):
        pn.line([(x + k, d - 0.6), (x + k, d + 0.6)], INK, 2)
    pn.text(x + 10, d + 1.8, "20 studs (a person is 5 tall)", 12)
    u, v = pn.P(VIEW["x0"] + 16, VIEW["d0"] + 30)
    pn.d.line([(u, v - 40), (u, v + 30)], fill=INK, width=3)
    pn.d.polygon([(u, v + 44), (u - 9, v + 22), (u + 9, v + 22)], fill=INK)
    pn.text(VIEW["x0"] + 16, VIEW["d0"] + 30, "NORTH", 12, bold=True, dx=34, dy=20)
    return pn


def draw_site(data, width):
    st = data["site"]
    B = st["bounds"]
    s = width / (B["x1"] - B["x0"])
    h = int((B["z1"] - B["z0"]) * s)
    img = Image.new("RGB", (width, h), (206, 218, 190))
    d = ImageDraw.Draw(img, "RGBA")

    def P(x, z):  # south up, +x right: the same way round as the plan
        return ((x - B["x0"]) * s, (z - B["z0"]) * s)

    def rect(x0, z0, x1, z1, **kw):
        a, b = P(min(x0, x1), min(z0, z1))
        c, e = P(max(x0, x1), max(z0, z1))
        d.rectangle([a, b, c, e], **kw)

    def dashed(pts, fill, width_=1, dash=(5, 4)):
        q = [P(x, z) for x, z in pts]
        for i in range(len(q) - 1):
            (ax, ay), (bx, by) = q[i], q[i + 1]
            length = math.hypot(bx - ax, by - ay)
            t = 0.0
            while t < length:
                t1 = min(length, t + dash[0])
                d.line([(ax + (bx - ax) * t / length, ay + (by - ay) * t / length),
                        (ax + (bx - ax) * t1 / length, ay + (by - ay) * t1 / length)], fill=fill, width=width_)
                t += dash[0] + dash[1]

    def label(x, z, text, size=10, fill=INK, bold=False):
        u, v = P(x, z)
        d.multiline_text((u, v), text, font=font(size, bold), fill=fill, anchor="mm", align="center", spacing=1,
                         stroke_width=2, stroke_fill=(255, 255, 255, 225))

    for sp in st["strips"]:
        col = (120, 120, 124, 255) if sp["kind"] == "asphalt" else (188, 188, 184, 255)
        rect(sp["x0"], sp["z"] - sp["w"] / 2, sp["x1"], sp["z"] + sp["w"] / 2, fill=col)
    for pad in st["pads"]:
        r = pad["rect"]
        rect(r["x0"], r["z0"], r["x1"], r["z1"], fill=(120, 120, 124, 255))
    for path in st["paths"]:
        q = [P(p[0], p[1]) for p in path["points"]]
        d.line(q, fill=(188, 188, 184, 255), width=max(2, int(path["w"] * s)))
    for name, (x0, z0, x1, z1) in MOVED:
        dashed([(x0, z0), (x1, z0), (x1, z1), (x0, z1), (x0, z0)], (120, 120, 120, 255), 1, (3, 3))
    for name, (p, q) in OLD_EDGES:
        dashed([p, q], (120, 120, 120, 255), 1, (3, 3))
    for v in st["neighbours"]:
        pts = [P(p[0], p[1]) for p in v["site"]]
        d.polygon(pts, fill=(250, 236, 190, 255), outline=(150, 110, 40, 255))
        cx = sum(p[0] for p in v["site"]) / len(v["site"])
        cz = sum(p[1] for p in v["site"]) / len(v["site"])
        if v["id"] == "f2_gazebo":
            continue  # the bandstand stands inside the green: outline only
        words = v["name"].title().replace("The ", "").split(" ")
        text = "\n".join(words) if len(v["name"]) > 12 else v["name"].title()
        label(cx, cz - (30 if v["id"] == "f2_liberty_green" else 0), text, 9)
    # the alley: its outer walls (the hall and the games wing), the back module, the reserve
    pl, K = data["place"], data["K"]

    def W(X, D):
        return (pl["x"] + X, pl["z"] - D)

    bs = data["backstage"]
    it, rs = bs["interim"], bs["reserve"]
    (ax, az), (bx, bz) = W(it["x0"], it["d0"]), W(it["x1"], it["d1"])
    rect(ax, az, bx, bz, fill=(170, 170, 176, 255))
    t = K["WALL_T"]
    (ax, az), (bx, bz) = W(K["X0"] - t, K["FRONT_D"] - t), W(K["HALL_X1"] + t, K["REAR_WALL_D"] + t)
    rect(ax, az, bx, bz, fill=(70, 70, 86, 255))
    (ax, az), (bx, bz) = W(K["HALL_X1"], K["GAME_ROOM_D0"] - t), W(K["X1"] + t, K["GAME_ROOM_D1"] + t)
    rect(ax, az, bx, bz, fill=(70, 70, 86, 255))
    cx, cz = W((K["X0"] + K["X1"]) / 2, 0)
    u, v = P(cx, cz)
    d.multiline_text((u, v), "BELLWETHER BOWL\n18 lanes", font=font(11, True), fill=(255, 255, 255), anchor="mm",
                     align="center")
    c = [W(rs["x0"], rs["d0"]), W(rs["x1"], rs["d0"]), W(rs["x1"], rs["d1"]), W(rs["x0"], rs["d1"])]
    dashed(c + [c[0]], (200, 30, 30, 255), 2, (6, 4))
    cx, cz = W((rs["x0"] + rs["x1"]) / 2, (bs["interim"]["d1"] + rs["d1"]) / 2)
    label(cx, cz, "kept free for the\nowner's backstage", 10, (170, 20, 20), True)
    label(1380, -312, "Bowl Lane", 9)
    label(1680, -312, "turning\ncircle", 8)
    label(1322, -262, "Alley Walk to\nMain Street", 8)
    label(1596, -462, "the two lounges and the racquet\nclub moved 88 east along the lane\n(grey dashes: where they were)", 9, (80, 80, 80))
    label(1186, -604, "the green gave up\nits northern 60", 9, (80, 80, 80))
    label(1196, -440, "the steakhouse site\ngave up its\neastern 21", 9, (80, 80, 80))
    d.rectangle([0, 0, width - 1, h - 1], outline=INK, width=1)
    return img


def legend(data, width, height):
    img = Image.new("RGB", (width, height), PAPER)
    d = ImageDraw.Draw(img, "RGBA")
    y = 0

    def head(text):
        nonlocal y
        d.text((0, y), text, font=font(17, True), fill=INK)
        y += 26

    def row(draw_key, text, size=13, step=21):
        nonlocal y
        draw_key(10, y + 9)
        d.text((34, y + 9), text, font=font(size), fill=INK, anchor="lm")
        y += step

    def swatch(col, outline=None):
        return lambda u, v: d.rectangle([u - 9, v - 7, u + 9, v + 7], fill=col, outline=outline)

    def dash_key(col, w, dash):
        def key(u, v):
            x = u - 10
            while x < u + 10:
                d.line([(x, v), (min(u + 10, x + dash[0]), v)], fill=col, width=w)
                x += dash[0] + dash[1]
        return key

    head("How to read it")
    row(swatch((58, 58, 66)), "wall (full height)")
    row(swatch((140, 196, 232), (70, 110, 150)), "window glass")
    row(swatch(None, OPENING_COL["door"] + (255,)), "doorway, arch or open front (green)")
    row(swatch(None, OPENING_COL["counter"] + (255,)), "serving counter or window (orange)")
    row(swatch(None, OPENING_COL["exit"] + (255,)), "steel exit doors (red)")
    row(lambda u, v: (d.rectangle([u - 6, v - 6, u + 6, v + 6], fill=(240, 150, 20)),
                      d.text((u, v + 0.5), "E", font=font(10, True), fill=(255, 255, 255), anchor="mm")),
        "where a player presses E to play (26 places)")
    row(dash_key((20, 110, 60), 1, (5, 4)), "floor a games table keeps clear for its players")
    row(lambda u, v: d.ellipse([u - 8, v - 8, u + 8, v + 8], fill=(120, 60, 170)),
        "staff post (numbered below); small dots: one behind each machine")
    row(dash_key((120, 60, 170), 2, (2, 5)), "staff walking route")
    row(dash_key((120, 70, 20), 2, (3, 5)), "ball-return tunnel under the floor (squirrel route)")
    row(dash_key((200, 30, 30), 3, (8, 5)), "ground kept free for the owner's backstage")
    row(dash_key((30, 60, 200), 3, (6, 5)), "the interim back module the backstage replaces")
    y += 8

    head("Staff posts")
    f = font(11)
    posts = data["posts"]
    half = (len(posts) + 1) // 2
    y0 = y
    for i, p in enumerate(posts):
        col, k = (0, i) if i < half else (1, i - half)
        d.text((col * (width // 2), y0 + k * 15), f'{i + 1}  {p["what"]}', font=f, fill=INK)
    y = y0 + half * 15 + 12

    head("The numbers")
    bs, K = data["backstage"], data["K"]
    ah = data["airHockey"]
    facts = [
        f'building: {K["X1"] - K["X0"] + 2 * K["WALL_T"]:.0f} wide at the front; the hall is '
        f'{K["HALL_X1"] - K["X0"]:.0f} x {K["REAR_WALL_D"] - K["FRONT_D"]:.0f} inside,',
        f'    the games room {K["X1"] - K["GAME_ROOM_X0"] - K["PARTITION_T"]:.0f} x '
        f'{K["GAME_ROOM_D1"] - K["GAME_ROOM_D0"]:.0f} (the old one was 30 x 78)',
        f'lanes: 18 at a {K["PITCH"]:.1f}-stud pitch, 56 studs foul line to head pin',
        f'air hockey: AlleyLayout.AIR_HOCKEY = x {ah["x"]:g}, d {ah["d"]:g}, yaw {ah["yaw"]:g}',
        f'backstage: scale {bs["scale"]:.4f} (our pitch over its {bs["authoredPitch"]:.6f}),',
        f'    {bs["size"]["x"]:.0f} x {bs["size"]["d"]:.0f} studs, lofts {bs["loftY"]:.1f} above the floor',
        f'    anchor at X {bs["anchor"]["x"]:.1f}, D {bs["anchor"]["d"]:.1f}; its meshes have not arrived',
        f'parts baked: {data["total"]} in {len(data["counts"])} models',
    ]
    for t in facts:
        d.text((0, y), t, font=font(12), fill=INK)
        y += 17
    y += 10
    return img.crop((0, 0, width, min(height, y)))


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default="build/review_alley/plan.json")
    ap.add_argument("--out", default="docs/renders/alley18/00_plan.png")
    args = ap.parse_args()
    data = json.load(open(args.data))

    pn = draw_plan(data)
    side = 600
    margin = 28
    title_h = 84
    W = margin + pn.w + margin + side + margin
    H = title_h + pn.h + margin
    img = Image.new("RGB", (W, H), PAPER)
    d = ImageDraw.Draw(img, "RGBA")
    d.text((margin, 16), "BELLWETHER BOWL: the eighteen-lane floor plan", font=font(34, True), fill=INK)
    d.text((margin, 58),
           "Drawn as you walk in: the street and the main doors at the bottom, lane 1 on the left, the pins and the "
           "back of house at the top. Everything shown is built, except the air hockey table (its place is kept). The shops are "
           "finished empty rooms: fittings and staff come next.",
           font=font(14), fill=INK)
    img.paste(pn.img, (margin, title_h))
    d.rectangle([margin - 1, title_h - 1, margin + pn.w, title_h + pn.h], outline=INK, width=2)

    x = margin + pn.w + margin
    leg = legend(data, side, 1100)
    img.paste(leg, (x, title_h))
    y = title_h + leg.height + 6
    d.text((x, y), "On its site (south up, like the plan)", font=font(17, True), fill=INK)
    site = draw_site(data, side)
    img.paste(site, (x, y + 28))
    img.save(args.out)
    print(f"alley_plan: {args.out} ({W} x {H})")


if __name__ == "__main__":
    main()
