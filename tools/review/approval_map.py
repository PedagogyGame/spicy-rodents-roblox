"""tools/review/approval_map.py: the owner's town approval map (brief v2 §15 decision 18; docs/waves/BATCH2_SPEC.md).

  lune run tools/bake/main.luau && lune run tools/bake/attractions.luau && lune run tools/bake/backdrop.luau
  lune run tools/review/approval_map.luau
  python3 -I tools/review/approval_map.py [--data build/review/approval_map.json] [--out docs/owner/files/town_map.png]

Top-down, north (+Z) up and +X on the LEFT, exactly like the in-game map (Shared/Map/MapModel mirrors x so the map
reads like the street you are looking at). Left: the whole town with the hill, the beach, the marina and the
off-road zone; right: the new streets of the east side at 2.5x. Every new venue is numbered and coloured by its
builder family; the legend lists them with the approval-map items starred. System python3 + Pillow only.
"""
import argparse
import json
import math

from PIL import Image, ImageDraw, ImageFont

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FAM = {
    "F1": ((226, 120, 38), "F1 food & shops"),
    "F2": ((52, 116, 201), "F2 civic"),
    "F3": ((150, 72, 178), "F3 leisure"),
    "F4": ((18, 150, 136), "F4 rides & minigame props"),
}
NEW = (255, 214, 64)
KIND = {
    "shop_neighbourhood": "the owner's shop: retail, cafe, office",
    "shop_corner": "1970s corner store, 22 items", "shop_barber": "barber shop", "restaurant_bakery": "bakery",
    "restaurant_cafe": "cafe", "shop_music": "music store", "shop_pet": "pet store", "restaurant_pizza": "pizza",
    "restaurant_chinese": "Chinese", "shop_antique": "antique store", "restaurant_diner": "diner", "restaurant_taco": "tacos",
    "shop_laundromat": "laundromat", "shop_bookshop": "bookshop", "restaurant_grill": "bar and grill",
    "shop_hardware": "hardware store", "restaurant_seafood": "beach shack", "museum": "readable exhibits",
    "clinic": "doctor's office, labyrinth", "park": "park + bandstand gazebo", "community_garden": "community garden",
    "school": "school + playground", "church": "church", "steakhouse": "glass walls, volleyball, giant Jenga",
    "lounge_classic": "lounge one, 1940s", "lounge_scifi": "lounge two, sci-fi", "racquet_club": "racquetball court",
    "mall_small": "new mall, wind tunnel", "tv_station": "5 storeys, paintball", "restaurant_hilltop": "hilltop restaurant",
    "skylift_station": "gondola to the hilltop", "jetski_rental": "marina ride", "parasail_launch": "marina ride",
}
# Where the lounges and the racquet club were first drawn (data/expansion.json before 2026-11-13): world x0, x1, z0, z1
FIRST_DRAWN = {
    "L1": (1374, 1424, -390, -334),
    "L2": (1432, 1482, -390, -334),
    "RC": (1494, 1558, -418, -334),
}
INK = (34, 36, 40)
PAPER = (246, 242, 232)


def font(size, bold=False):
    return ImageFont.truetype(BOLD if bold else FONT, size)


class Panel:
    def __init__(self, img, ox, oy, x0, x1, z0, z1, scale):
        self.img, self.ox, self.oy = img, ox, oy
        self.x0, self.x1, self.z0, self.z1, self.s = x0, x1, z0, z1, scale
        self.w, self.h = int((x1 - x0) * scale), int((z1 - z0) * scale)
        # an opaque RGB layer: ImageDraw blends RGBA fills into RGB images (it would replace pixels of an RGBA one)
        self.layer = Image.new("RGB", (self.w, self.h), (200, 200, 200))
        self.d = ImageDraw.Draw(self.layer, "RGBA")

    def P(self, x, z):
        return ((self.x1 - x) * self.s, (self.z1 - z) * self.s)

    def rect(self, x0, z0, x1, z1, fill=None, outline=None, width=1):
        a, b = self.P(max(x0, x1), max(z0, z1))
        c, d = self.P(min(x0, x1), min(z0, z1))
        if c - a < 1:
            c = a + 1
        if d - b < 1:
            d = b + 1
        self.d.rectangle([a, b, c, d], fill=fill, outline=outline, width=width)

    def poly(self, pts, fill=None, outline=None, width=1):
        self.d.polygon([self.P(x, z) for x, z in pts], fill=fill, outline=outline, width=width)

    def line(self, pts, fill, width=1, dash=None):
        q = [self.P(x, z) for x, z in pts]
        if not dash:
            self.d.line(q, fill=fill, width=width, joint="curve")
            return
        on, off = dash
        for i in range(len(q) - 1):
            (ax, ay), (bx, by) = q[i], q[i + 1]
            L = math.hypot(bx - ax, by - ay)
            t = 0.0
            while t < L:
                t1 = min(L, t + on)
                self.d.line([(ax + (bx - ax) * t / L, ay + (by - ay) * t / L),
                             (ax + (bx - ax) * t1 / L, ay + (by - ay) * t1 / L)], fill=fill, width=width)
                t += on + off

    def dashed_poly(self, pts, fill, width=1, dash=(6, 4)):
        self.line(list(pts) + [pts[0]], fill, width, dash)

    def text(self, x, z, s, size, fill=INK, bold=False, halo=True, anchor="mm"):
        f = font(size, bold)
        u, v = self.P(x, z)
        if halo:
            self.d.text((u, v), s, font=f, fill=fill, anchor=anchor, stroke_width=max(2, size // 6),
                        stroke_fill=(255, 255, 255, 215))
        else:
            self.d.text((u, v), s, font=f, fill=fill, anchor=anchor)

    def badge(self, x, z, label, color, r):
        u, v = self.P(x, z)
        self.d.ellipse([u - r, v - r, u + r, v + r], fill=color + (255,), outline=(255, 255, 255, 255), width=max(1, r // 6))
        self.d.text((u, v + 0.5), label, font=font(int(r * 1.15), True), fill=(255, 255, 255), anchor="mm")

    def paste(self):
        self.img.paste(self.layer, (self.ox, self.oy))


def ground(pn, data):
    B, G = data["bounds"], data["grid"]
    nx, nz, cells, st = G["nx"], G["nz"], G["cells"], B["step"]
    shore = {round(x): z for x, z in data["shore"]}

    def h(i, k):
        i, k = max(0, min(nx - 1, i)), max(0, min(nz - 1, k))
        return cells[k * nx + i][0]

    for k in range(nz):
        z = B["z0"] + k * st
        if z < pn.z0 - st or z > pn.z1 + st:
            continue
        for i in range(nx):
            x = B["x0"] + i * st
            if x < pn.x0 - st or x > pn.x1 + st:
                continue
            hh, water = cells[k * nx + i]
            if water:
                depth = max(0.0, min(1.0, -hh / 13))
                col = (int(96 - 40 * depth), int(150 - 40 * depth), int(178 - 30 * depth))
            else:
                sz = shore.get(round(x / 50) * 50, 1488)
                sandy = (z > 1110 and z < sz and -820 < x < 4260) or (z > sz - 140 and hh < 3.2)
                dx = (h(i - 1, k) - h(i + 1, k)) / (2 * st)
                dz = (h(i, k + 1) - h(i, k - 1)) / (2 * st)
                shade = max(0.72, min(1.22, 1 + 2.2 * (0.6 * dx + 0.8 * dz)))
                t = max(0.0, min(1.0, hh / 120))
                if sandy:
                    base = (226, 210, 168)
                else:
                    base = (int(122 + 70 * t), int(150 + 48 * t), int(98 + 52 * t))
                col = tuple(max(0, min(255, int(c * shade))) for c in base)
            pn.rect(x - st / 2, z - st / 2, x + st / 2, z + st / 2, fill=col + (255,))


def town(pn, data, detail):
    ext = data["extensions"]
    for dist in ext["districts"]:
        x0, x1, z0, z1 = dist["minX"] * 2.5, dist["maxX"] * 2.5, dist["minZ"] * 2.5, dist["maxZ"] * 2.5
        pn.rect(x0, z0, x1, z1, fill=(120, 96, 60, 40), outline=(120, 80, 40, 200), width=2)
        step = 90
        for k in range(0, int((x1 - x0) + (z1 - z0)), step):
            sx, sz = x0 + k, z0
            ex, ez = x0 + k - (z1 - z0), z1
            if sx > x1:
                sz += sx - x1
                sx = x1
            if ex < x0:
                ez -= x0 - ex
                ex = x0
            pn.line([(sx, sz), (ex, ez)], (110, 80, 50, 70), 1)
    flats, buildings, canopy = [], [], []
    for b in data["boxes"]:
        cat, x0, z0, x1, z1, top = b
        if x1 < pn.x0 or x0 > pn.x1 or z1 < pn.z0 or z0 > pn.z1:
            continue
        if cat == "flat":
            flats.append(b)
        elif cat in ("building", "attraction", "coast"):
            buildings.append(b)
        elif cat == "canopy":
            canopy.append(b)
    for _, x0, z0, x1, z1, _ in flats:
        if (x1 - x0) * (z1 - z0) > 5:
            pn.rect(x0, z0, x1, z1, fill=(214, 204, 182, 120))
    for r in data["roads"]:
        if r["axis"] not in ("x", "z"):
            continue
        w = r["width"] / 2
        if r["axis"] == "x":
            x0, x1, z0, z1 = r["start"], r["end"], r["coord"] - w, r["coord"] + w
        else:
            x0, x1, z0, z1 = r["coord"] - w, r["coord"] + w, r["start"], r["end"]
        col = {"asphalt": (88, 91, 96), "concrete": (200, 196, 186), "cobble": (160, 140, 118), "path": (196, 176, 132),
               "rail": (120, 110, 100)}.get(r["kind"], (150, 150, 150))
        pn.rect(x0, z0, x1, z1, fill=col + (255,))
    for _, x0, z0, x1, z1, _ in buildings:
        col = (205, 186, 152, 255)
        pn.rect(x0, z0, x1, z1, fill=col, outline=(150, 130, 100, 255) if detail else None)
    for _, x0, z0, x1, z1, _ in canopy:
        a, b = pn.P(x1, z1)
        c, d = pn.P(x0, z0)
        if c - a > 1.5:
            pn.d.ellipse([a, b, c, d], fill=(52, 98, 50, 70))
    for a in data["attractions"]:
        p = a["place"]
        if detail:
            pn.text(p["x"] + 15, p["z"] - 60, "BOWLING", 13, (170, 40, 30), True)
            pn.text(p["x"] + 15, p["z"] - 76, "ALLEY", 13, (170, 40, 30), True)


def expansion(pn, data, detail, numbers, skip=None):
    E = data["expansion"]
    W = 2 if detail else 1
    for s in E["strips"]:
        w = s["width"] / 2
        if s["axis"] == "x":
            x0, x1, z0, z1 = s["start"], s["end"], s["coord"] - w, s["coord"] + w
        else:
            x0, x1, z0, z1 = s["coord"] - w, s["coord"] + w, s["start"], s["end"]
        col = (60, 63, 68, 255) if s["kind"] == "asphalt" else (222, 216, 202, 255)
        pn.rect(x0, z0, x1, z1, fill=col)
    for p in E["pads"]:
        r = p["rect"]
        col = {"forecourt": (232, 224, 206), "plaza": (232, 220, 196), "parking": (98, 101, 106), "asphalt": (60, 63, 68),
               "concrete": (206, 201, 190)}[p["kind"]]
        pn.rect(r["x0"], r["z0"], r["x1"], r["z1"], fill=col + (255,))
        if p["kind"] == "parking" and detail:
            for x in range(int(r["x0"]) + 8, int(r["x1"]), 9):
                pn.line([(x, r["z0"] + 2), (x, r["z0"] + 16)], (235, 235, 235, 200), 1)
                pn.line([(x, r["z1"] - 2), (x, r["z1"] - 16)], (235, 235, 235, 200), 1)
    for p in E["paths"]:
        col = {"boardwalk": (150, 108, 70), "path": (190, 165, 120), "concrete": (226, 220, 206), "steps": (226, 220, 206)}[p["kind"]]
        pn.line([tuple(q) for q in p["points"]], col + (255,), max(2, int(p["width"] * pn.s)))
    # new streets and pads outlined in the NEW colour
    for s in E["strips"]:
        if s["kind"] != "asphalt":
            continue
        w = s["width"] / 2
        if s["axis"] == "x":
            pts = [(s["start"], s["coord"] - w), (s["end"], s["coord"] - w), (s["end"], s["coord"] + w), (s["start"], s["coord"] + w)]
        else:
            pts = [(s["coord"] - w, s["start"]), (s["coord"] + w, s["start"]), (s["coord"] + w, s["end"]), (s["coord"] - w, s["end"])]
        pn.dashed_poly(pts, NEW + (255,), W, (7, 5))
    # zones and rides
    for zn in E["zones"]:
        r = zn["rect"]
        pts = [(r["x0"], r["z0"]), (r["x1"], r["z0"]), (r["x1"], r["z1"]), (r["x0"], r["z1"])]
        if zn["kind"] == "jetski_water":
            pn.dashed_poly(pts, (255, 236, 120, 230), 2, (5, 6))
            pn.text((r["x0"] + r["x1"]) / 2, (r["z0"] + r["z1"]) / 2, "JET SKI WATER", 12, (40, 60, 80), True)
    for ride in E["rides"]:
        pts = ride["points"]
        if ride["kind"] == "cable":
            pn.line([(p[0], p[2]) for p in pts], (150, 24, 24, 255), 3 if detail else 2)
            for p in pts[1:-1]:
                u, v = pn.P(p[0], p[2])
                pn.d.rectangle([u - 3, v - 3, u + 3, v + 3], fill=(150, 24, 24, 255), outline=(255, 255, 255, 255))
        elif ride["kind"] == "towed_spline":
            pn.line([(p[0], p[2]) for p in pts] + [(pts[0][0], pts[0][2])], (255, 255, 255, 230), 2, (8, 6))
            m = pts[len(pts) // 2]
            pn.text(m[0], m[2] + 40, "PARASAIL LOOP", 12, (40, 60, 80), True)
    # venues
    for v in E["venues"]:
        col, _ = FAM[v["family"]]
        if v["status"] == "upgrade":
            u, w = pn.P(v["position"]["x"], v["position"]["z"])
            r = 5 if detail else 3
            pn.d.regular_polygon((u, w, r + 2), 4, rotation=45, fill=col + (255,), outline=(255, 255, 255, 255))
            continue
        site = [tuple(p) for p in v["sitePoly"]]
        foot = [tuple(p) for p in v["footPoly"]]
        if v["type"] in ("park", "community_garden"):
            pn.poly(foot, fill=(150, 196, 120, 255) if v["type"] == "park" else (160, 128, 86, 255))
            if v["type"] == "community_garden" and detail:
                for a in v["anchors"]:
                    if a["kind"] == "garden_bed":
                        x, _, z = a["world"]
                        pn.rect(x - 6, z - 3, x + 6, z + 3, fill=(96, 140, 60, 255))
        else:
            if site != foot:
                pn.poly(site, fill=col + (40,))
                pn.dashed_poly(site, col + (255,), W, (5, 4))
            pn.poly(foot, fill=col + (235,), outline=(255, 255, 255, 255), width=W)
        if detail:
            for a in v["anchors"]:
                if a["kind"] in ("sand",):
                    x, _, z = a["world"]
                    pn.rect(x - 40, z - 25, x + 40, z + 25, fill=(230, 212, 160, 255), outline=(200, 180, 120, 255))
                if a["kind"] == "deck":
                    x, _, z = a["world"]
                    pn.rect(x - 25, z - 20, x + 25, z + 20, fill=(176, 130, 86, 255), outline=(255, 255, 255, 255))
    for veh in E["vehicles"]:
        u, w = pn.P(veh["x"], veh["z"])
        r = 6 if detail else 4
        col = (60, 60, 60) if veh["kind"] == "pickup" else (20, 20, 20)
        pn.d.rounded_rectangle([u - r, w - r, u + r, w + r], radius=2, fill=col + (255,), outline=NEW + (255,), width=1)
        if detail:
            pn.d.text((u, w), "P" if veh["kind"] == "pickup" else "S", font=font(9, True), fill=(255, 255, 255), anchor="mm")
    # number badges last
    for v in E["venues"]:
        if v["id"] not in numbers:
            continue
        if skip and skip(v):
            continue
        cx = sum(p[0] for p in v["footPoly"]) / 4
        cz = sum(p[1] for p in v["footPoly"]) / 4
        col, _ = FAM[v["family"]]
        pn.badge(cx, cz, str(numbers[v["id"]]), col, 11 if detail else 9)


def landmarks(pn, data):
    lots = {l["id"]: l for l in data["lots"]}
    for lid, label, dx, dz in [
        ("hospital_main", "HOSPITAL", 0, 0), ("west_police_station", "POLICE", 0, -70), ("north_sycamore_park", "SYCAMORE PARK", 0, 40),
        ("north_cedar_rest_cemetery", "CEMETERY", 0, 0), ("galleria_building", "GALLERIA", 0, 190), ("quay_market_square", "BELLWETHER QUAY", 0, 260),
        ("estate_0_parcel", "ESTATES", 325, 0), ("core_intersection", "OLD TOWN", 0, 0),
    ]:
        if lid in lots:
            l = lots[lid]
            pn.text(l["x"] + dx, l["z"] + dz, label, 15, (40, 40, 40), True)
    pn.text(3650, 300, "OFF-ROAD ZONE", 20, (110, 70, 30), True)
    pn.text(3650, 220, "beyond the ridge: no tickets, no arrests", 12, (110, 70, 30))
    pn.text(2990, -900, "RIDGE", 13, (70, 90, 50), True)
    pn.text(-1060, -1830, "LOOKOUT HILL", 17, (60, 70, 40), True)
    pn.text(400, 1300, "BEACH", 18, (150, 120, 60), True)
    pn.text(-150, 1990, "PIER", 14, (90, 60, 30), True)
    pn.text(2260, 1960, "MARINA", 16, (40, 60, 80), True)
    pn.text(1500, 2120, "OCEAN", 22, (230, 240, 250), True, halo=False)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", default="build/review/approval_map.json")
    ap.add_argument("--out", default="docs/owner/files/town_map.png")
    a = ap.parse_args()
    data = json.load(open(a.data))
    E = data["expansion"]
    order = {"F1": 0, "F2": 1, "F3": 2, "F4": 3}
    newv = [v for v in E["venues"] if v["status"] == "new" and v["type"] not in ("gazebo",)]
    newv.sort(key=lambda v: (order[v["family"]], E["venues"].index(v)))
    numbers = {v["id"]: i + 1 for i, v in enumerate(newv)}
    for v in E["venues"]:
        if v["type"] == "gazebo":
            numbers[v["id"]] = numbers.get("f2_liberty_green", 0)

    OVW = (-1650, 4350, -1950, 2200, 0.335)
    DET = (740, 2200, -1160, 545, 0.84)
    M, TOP = 36, 96
    ow, oh = int((OVW[1] - OVW[0]) * OVW[4]), int((OVW[3] - OVW[2]) * OVW[4])
    dw, dh = int((DET[1] - DET[0]) * DET[4]), int((DET[3] - DET[2]) * DET[4])
    LEG = 330
    W = M + ow + 28 + dw + M
    H = TOP + max(oh, dh) + 24 + LEG + M
    img = Image.new("RGBA", (W, H), PAPER + (255,))
    d = ImageDraw.Draw(img)
    d.text((M, 22), "SPICY RODENTS - TOWN PLAN FOR APPROVAL (batch 2: the whole town and its attractions)", font=font(30, True), fill=INK)
    d.text((M, 62), "Top-down, north up, drawn like the in-game map (you see it as you would from the street). "
           "Numbered = new; colour = who builds it; dashed yellow = new streets. Right: the east side at 2.5x.",
           font=font(16), fill=(70, 70, 70))

    ov = Panel(img, M, TOP, *OVW)
    ground(ov, data)
    town(ov, data, False)
    def in_detail(v):
        x, z = v["position"]["x"], v["position"]["z"]
        return DET[0] < x < DET[1] and DET[2] < z < DET[3]

    expansion(ov, data, False, numbers, in_detail)
    landmarks(ov, data)
    # detail frame on the overview
    ov.dashed_poly([(DET[0], DET[2]), (DET[1], DET[2]), (DET[1], DET[3]), (DET[0], DET[3])], (20, 20, 20, 255), 2, (8, 5))
    ov.text((DET[0] + DET[1]) / 2, DET[3] + 40, "DETAIL (right)", 13, INK, True)
    ov.paste()

    de = Panel(img, M + ow + 28, TOP, *DET)
    ground(de, data)
    town(de, data, True)
    expansion(de, data, True, numbers)
    for s in E["streets"]:
        if s["axis"] == "x":
            x = max(min(s["start"], s["end"]), DET[0]) + 60 if s["id"] != "xs_chapel_st" else 1700
            de.text(x, s["coord"], s["name"], 13, (20, 20, 20), True)
        else:
            z = max(min(s["start"], s["end"]), DET[2]) + 60
            if DET[0] < s["coord"] < DET[1]:
                u, v = de.P(s["coord"], z + 120)
                f = font(13, True)
                tmp = Image.new("RGBA", (220, 24), (0, 0, 0, 0))
                ImageDraw.Draw(tmp).text((110, 12), s["name"], font=f, fill=(20, 20, 20), anchor="mm", stroke_width=2,
                                         stroke_fill=(255, 255, 255, 215))
                tmp = tmp.rotate(90, expand=True)
                de.layer.paste(tmp, (int(u - 12), int(v - 110)), tmp)
    de.text(1060, 0, "MAIN STREET (COMMERCIAL BOULEVARD)", 14, (20, 20, 20), True)
    # OWNER QUESTION 1 (alley venue map, question 1): where the two lounges and the racquet club were first drawn,
    # before the eighteen-lane alley's games room took their ground along Bowl Lane; nothing is built on either
    q1 = (200, 30, 120, 255)
    for name, (x0, x1, z0, z1) in FIRST_DRAWN.items():
        de.dashed_poly([(x0, z0), (x1, z0), (x1, z1), (x0, z1)], q1, 3, (7, 4))
        de.text((x0 + x1) / 2, (z0 + z1) / 2, name, 12, q1[:3], True)
    de.line([(1430, -300), (1560, -300)], q1, 3)
    de.line([(1560, -300), (1548, -293)], q1, 3)
    de.line([(1560, -300), (1548, -307)], q1, 3)
    de.text(1495, -284, "Q1: L1, L2, RC MOVED 88 EAST?", 14, q1[:3], True)
    # the ground kept for the owner's backstage behind the lanes (the reserve): the park and the steakhouse keep it
    # until the backstage package arrives
    alley = data["attractions"][0]
    pl, kept = alley["place"], alley["reserve"]  # (yaw 0: world x = place.x + X, z = place.z - D)
    rs = (pl["x"] + kept["x0"], pl["x"] + kept["x1"], pl["z"] - kept["d1"], pl["z"] - kept["d0"])
    de.dashed_poly([(rs[0], rs[2]), (rs[1], rs[2]), (rs[1], rs[3]), (rs[0], rs[3])], (40, 40, 40, 255), 2, (5, 4))
    de.text((rs[0] + rs[1]) / 2, rs[2] + 12, "KEPT FOR THE BACKSTAGE (the park keeps it until it arrives)", 11,
            (40, 40, 40), True)
    for lid, label in [("east_chilis_restaurant", "CHILI'S"), ("east_fuel_market", "FUEL"), ("east_corner_shops", "CORNER SHOPS")]:
        l = next(x for x in data["lots"] if x["id"] == lid)
        de.text(l["x"], l["z"], label, 12, (90, 70, 50), True)
    # scale bars and compasses
    for pn, length in ((ov, 500), (de, 100)):
        x0 = pn.x1 - 40 / pn.s
        z0 = pn.z0 + 30 / pn.s
        u0, v0 = pn.P(x0, z0)
        L = length * pn.s
        pn.d.rectangle([u0, v0 - 4, u0 + L, v0], fill=INK + (255,))
        pn.d.text((u0 + L / 2, v0 - 8), f"{length} studs", font=font(12, True), fill=INK, anchor="mb")
        uc, vc = pn.w - 40, 40
        pn.d.polygon([(uc, vc - 22), (uc - 9, vc + 8), (uc, vc + 2), (uc + 9, vc + 8)], fill=INK + (255,))
        pn.d.text((uc, vc + 20), "N", font=font(14, True), fill=INK, anchor="mm")
    de.paste()
    d.rectangle([M - 1, TOP - 1, M + ow, TOP + oh], outline=INK, width=2)
    d.rectangle([M + ow + 27, TOP - 1, M + ow + 28 + dw, TOP + dh], outline=INK, width=2)

    # legend
    ly = TOP + max(oh, dh) + 24
    d.rectangle([M, ly, W - M, ly + LEG - 8], fill=(255, 253, 248), outline=(200, 190, 170))
    cols = 4
    colw = (W - 2 * M - 40) // cols
    x, y = M + 20, ly + 14
    entries = []
    for v in newv:
        star = "* " if v.get("approval") else "  "
        nm = v["name"].title().replace("'S", "'s").replace("Of ", "of ").replace("On ", "on ").replace("Wblw", "WBLW")
        what = KIND.get(v["type"], "")
        entries.append((v["family"], f"{numbers[v['id']]:>2} {star}{nm}" + (f"  ({what})" if what else "")))
    per = math.ceil((len(entries) + 14) / cols)
    col = 0
    row = 0
    for fam in ("F1", "F2", "F3", "F4"):
        c, label = FAM[fam]
        if row > per - 3:
            col, row = col + 1, 0
        xx, yy = x + col * colw, y + row * 21
        d.rectangle([xx, yy + 3, xx + 14, yy + 17], fill=c)
        d.text((xx + 20, yy), label.upper(), font=font(15, True), fill=INK)
        row += 1
        for f, text in entries:
            if f != fam:
                continue
            if row >= per:
                col, row = col + 1, 0
            d.text((x + col * colw, y + row * 21), text, font=font(14), fill=INK)
            row += 1
        row += 0.4
    if row > per - 7:
        col, row = col + 1, 0
    xx = x + col * colw
    yy = y + row * 21
    extra = [
        ("EXISTING, ON THE APPROVAL LIST", True),
        ("  Bowling alley (Bellwether Bowl, built)", False),
        ("  Pier, marina, beach (backdrop, built)", False),
        ("  Off-road zone beyond the ridge", False),
        ("  34 existing homes + the 6 new ones", False),
        ("KEY", True),
        ("  * on the dec-18 approval list", False),
        ("  diamond = existing food place given seats/bins", False),
        ("  P / S = the 6 pickups and 4 SUVs", False),
        ("  red line = sky lift cable and towers", False),
        ("  dashed yellow = new street / jet-ski water", False),
        ("QUESTION FOR YOU (nothing built on it yet)", True),
        ("  Q1 (magenta): the 18-lane alley's games room", False),
        ("  took the lounges' first spots on Bowl Lane;", False),
        ("  both lounges and the racquet club moved 88 east.", False),
        ("  OK? Or: games room behind lounge one, lounges back.", False),
    ]
    for text, bold in extra:
        d.text((xx, yy), text, font=font(14, bold), fill=INK)
        yy += 21
    img.convert("RGB").save(a.out, optimize=True)
    print(f"approval map: {W} x {H} -> {a.out} ({len(newv)} numbered venues)")


if __name__ == "__main__":
    main()
