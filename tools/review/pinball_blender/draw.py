# Draws the three pinball playfields, the cabinet and the parts sheet from the game's own numbers
# (tables.json, dumped by dump.luau from src/shared/Minigames/Pinball and tools/bake/games/Pinball).
# For the owner's Blender work (docs/owner/PINBALL_BLENDER.md). Run from the repo root:
#   lune run tools/review/pinball_blender/dump.luau build/review/pinball_tables.json
#   python3 -I tools/review/pinball_blender/draw.py build/review/pinball_tables.json docs/owner/pinball_blender
#   python3 -I tools/review/pinball_blender/blockout.py build/review/pinball_tables.json docs/owner/pinball_blender/blender
import json, math, sys, os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.patches import Circle, Polygon, Rectangle, FancyArrowPatch
from matplotlib.lines import Line2D
import matplotlib.patheffects as pe

D = json.load(open(sys.argv[1]))
OUT = sys.argv[2]
os.makedirs(OUT, exist_ok=True)
LY, CB = D["layout"], D["cabinet"]
W, L, BR, XC, X1 = LY["WIDTH"], LY["LENGTH"], LY["BALL_R"], LY["XC"], LY["FIELD_X1"]
M = 0.28  # metres per stud (Roblox's importer, Scale Unit = Meter)

def rgb(c):
    return tuple(v / 255 for v in c)

LAMP = {"red": (255, 60, 50), "green": (80, 255, 110), "amber": (255, 170, 40), "yellow": (255, 236, 70),
        "orange": (255, 130, 30), "white": (255, 250, 235), "blue": (80, 150, 255)}
CHROME, RUBBER, DARK = rgb((150, 155, 165)), rgb((250, 250, 245)), rgb((24, 24, 26))
# drawn thickness, as the bake builds them (studs)
WALL = {"wood": 0.06, "metal": 0.022, "plastic": 0.045, "rubber": 0.035}

NICE = {
    "pinball_acorn": ("acorn", "ACORN ATTACK", "the gentle old electro-mechanical (walnut and brass)"),
    "pinball_rodent": ("rodent", "SPICY RODENT", "the fast, hungry one (red and black)"),
    "pinball_space": ("space", "SPACE SQUIRREL", "the flow table: two ramps, an orbit, multiball (deep blue and silver)"),
}

def seg_poly(x1, y1, x2, y2, t):
    dx, dy = x2 - x1, y2 - y1
    l = math.hypot(dx, dy) or 1
    nx, ny = -dy / l * t / 2, dx / l * t / 2
    return [(x1 + nx, y1 + ny), (x2 + nx, y2 + ny), (x2 - nx, y2 - ny), (x1 - nx, y1 - ny)]

def thick_line(ax, pts, t, face, edge=None, z=3, round_ends=True):
    for i in range(0, len(pts) - 3, 2):
        ax.add_patch(Polygon(seg_poly(pts[i], pts[i + 1], pts[i + 2], pts[i + 3], t), closed=True,
                             fc=face, ec=edge or face, lw=0.3, zorder=z))
        if round_ends:
            ax.add_patch(Circle((pts[i + 2], pts[i + 3]), t / 2, fc=face, ec="none", zorder=z))
    if round_ends:
        ax.add_patch(Circle((pts[0], pts[1]), t / 2, fc=face, ec="none", zorder=z))

def flipper_shape(f, angle):
    s = -1 if f["mirror"] else 1
    px, py, ln, rb, rt = f["x"], f["y"], f["len"], f["rBase"], f["rTip"]
    tx, ty = px + s * math.cos(angle) * ln, py + math.sin(angle) * ln
    # outline: the hull of the two circles (taper)
    pts = []
    ang = math.atan2(ty - py, tx - px)
    b = (rb - rt) / ln
    a = math.acos(max(-1, min(1, b)))
    for k in range(25):
        th = ang + a + (2 * math.pi - 2 * a) * k / 24
        pts.append((px + rb * math.cos(th), py + rb * math.sin(th)))
    for k in range(25):
        th = ang - a + (2 * a) * k / 24
        pts.append((tx + rt * math.cos(th), ty + rt * math.sin(th)))
    return pts, (tx, ty)

def tag(ax, x, y, text, dx=0.0, dy=0.0, size=6.5, color="black", ha="center", box=True, z=20):
    kw = dict(fontsize=size, ha=ha, va="center", color=color, zorder=z, fontweight="bold")
    if box:
        kw["bbox"] = dict(boxstyle="round,pad=0.18", fc=(1, 1, 1, 0.82), ec=(0, 0, 0, 0.35), lw=0.4)
    if dx or dy:
        ax.annotate(text, (x, y), (x + dx, y + dy), arrowprops=dict(arrowstyle="-", lw=0.5, color=(0, 0, 0, 0.6)), **kw)
    else:
        ax.text(x, y, text, **kw)

def num(ax, x, y, n, z=25):
    ax.text(x, y, str(n), fontsize=6, ha="center", va="center", color="white", fontweight="bold", zorder=z,
            bbox=dict(boxstyle="circle,pad=0.15", fc=(0.1, 0.1, 0.12), ec="white", lw=0.5))

def axes_frame(ax, title):
    ax.set_xlim(-0.35, W + 0.35)
    ax.set_ylim(-0.75, L + 0.25)
    ax.set_aspect("equal")
    ax.set_xticks([i * 0.5 for i in range(0, 5)] + [W])
    ax.set_yticks([i * 0.5 for i in range(0, 10)] + [L])
    ax.tick_params(labelsize=6)
    ax.grid(True, lw=0.3, color=(0, 0, 0, 0.15), zorder=0)
    ax.set_xlabel("x: studs across, from the player's left (x 0.28 = metres)", fontsize=7)
    ax.set_ylabel("y: studs up the table, from the player's end", fontsize=7)
    sec = ax.secondary_xaxis("top", functions=(lambda s: s * M, lambda m: m / M))
    sec.set_xlabel("metres (at Roblox's 0.28 m per stud)", fontsize=7)
    sec.tick_params(labelsize=6)
    sec2 = ax.secondary_yaxis("right", functions=(lambda s: s * M, lambda m: m / M))
    sec2.tick_params(labelsize=6)
    ax.set_title(title, fontsize=11, fontweight="bold", pad=24)


def draw_table(tid):
    t = D["tables"][tid]
    variant, title, blurb = NICE[tid]
    th = D["themes"][variant]
    field, plastic, bumper, cap, target, apron, ink, trim = (rgb(th[k]) for k in
        ("field", "plastic", "bumper", "cap", "target", "apron", "ink", "trim"))
    fig, ax = plt.subplots(figsize=(10.5, 19))
    axes_frame(ax, f"{title}: playfield plan, as the game simulates it\n{blurb}")
    # the board, the apron
    ax.add_patch(Rectangle((0, -0.16), W, L + 0.16, fc=field, ec="black", lw=0.8, zorder=1, alpha=0.55))
    ax.add_patch(Rectangle((XC - 0.75, -0.16), 1.5, t["drainY"] + 0.1 + 0.16, fc=apron, ec="black", lw=0.6, zorder=6, alpha=0.9))
    ax.text(XC, 0.0, title, fontsize=8, color=ink, ha="center", va="center", zorder=7, fontweight="bold")
    # cabinet side rails beside the board (outline only)
    for x0 in (-CB["RAIL"], W):
        ax.add_patch(Rectangle((x0, -0.44), CB["RAIL"], L + 0.36 + 0.08, fc=rgb(th["body"]), ec="black", lw=0.5, alpha=0.5, zorder=1))
    ax.add_patch(Rectangle((-CB["RAIL"], -0.27), W + 2 * CB["RAIL"], 0.12, fc=rgb(th["body"]), ec="black", lw=0.5, alpha=0.5, zorder=1))
    # painted art (words on the playfield)
    lamps = {l["id"]: l for l in t["lamps"]}
    for p in D["art"][variant]:
        lp = lamps.get(p.get("lamp")) if p.get("lamp") else None
        x = (lp["x"] if lp else p.get("x", 0)) + p["dx"]
        y = (lp["y"] if lp else p.get("y", 0)) + p["dy"]
        ax.add_patch(Rectangle((x - p["w"] / 2, y - p["h"] / 2), p["w"], p["h"], fc="none", ec=(0, 0, 0, 0.25), lw=0.3, ls=":", zorder=2))
        ax.text(x, y, p["text"], fontsize=max(4.5, 120 * p["h"]), color=ink, ha="center", va="center", zorder=2,
                fontweight="bold", path_effects=[pe.withStroke(linewidth=1.2, foreground=(0, 0, 0, 0.75))])
    # walls
    slings = {(round(s["x1"], 4), round(s["y1"], 4), round(s["x2"], 4), round(s["y2"], 4)) for s in t["slings"]}
    for w in t["walls"]:
        pts, mat = w["pts"], w["mat"]
        if mat == "plastic" and len(pts) == 6:
            key = (round(pts[0], 4), round(pts[1], 4), round(pts[4], 4), round(pts[5], 4))
            if key in slings:
                ax.add_patch(Polygon([(pts[0], pts[1]), (pts[2], pts[3]), (pts[4], pts[5])], closed=True, fc=plastic, ec="black", lw=0.5, zorder=3))
                continue
        if mat == "plastic" and len(pts) == 8 and pts[0:2] != pts[6:8]:
            ax.add_patch(Polygon([(pts[i], pts[i + 1]) for i in range(0, 8, 2)], closed=True, fc=plastic, ec="black", lw=0.5, zorder=3, alpha=0.85))
            continue
        col = {"wood": trim, "metal": CHROME, "plastic": plastic, "rubber": RUBBER}[mat]
        thick_line(ax, pts, WALL[mat], col, edge="black" if mat in ("rubber", "wood") else None, z=4)
    # posts
    for p in t["posts"]:
        ax.add_patch(Circle((p["x"], p["y"]), max(p["r"], 0.012), fc=RUBBER if p["mat"] == "rubber" else CHROME, ec="black", lw=0.4, zorder=6))
    # slingshot rubbers
    for s in t["slings"]:
        thick_line(ax, [s["x1"], s["y1"], s["x2"], s["y2"]], 0.035, RUBBER, edge="black", z=5)
    # bumpers
    for i, b in enumerate(t["bumpers"], 1):
        ax.add_patch(Circle((b["x"], b["y"]), b["r"], fc=bumper, ec="black", lw=0.7, zorder=7))
        ax.add_patch(Circle((b["x"], b["y"]), b["r"] * 0.85, fc=cap, ec="black", lw=0.4, zorder=7, alpha=0.8))
    # targets
    for tg in t["targets"]:
        thick_line(ax, [tg["x1"], tg["y1"], tg["x2"], tg["y2"]], 0.03, target, edge="black", z=8, round_ends=False)
    # sensors
    for s in t["sensors"]:
        if s["kind"] == "spinner":
            ax.add_patch(Polygon(seg_poly(s["x1"], s["y1"], s["x2"], s["y2"], 0.05), closed=True, fc=CHROME, ec="black", lw=0.6, hatch="////", zorder=8))
        else:
            ax.plot([s["x1"], s["x2"]], [s["y1"], s["y2"]], ls=(0, (2, 1.5)), color=(0.1, 0.5, 0.1), lw=0.8, zorder=8)
            mx, my = (s["x1"] + s["x2"]) / 2, (s["y1"] + s["y2"]) / 2
            ax.add_patch(Rectangle((mx - 0.015, my - 0.04), 0.03, 0.08, fc=CHROME, ec="black", lw=0.3, zorder=9))
    # gates
    for g in t["gates"]:
        thick_line(ax, [g["x1"], g["y1"], g["x2"], g["y2"]], 0.014, CHROME, edge="black", z=9)
    # saucers / scoops
    for sc in t["saucers"]:
        ax.add_patch(Circle((sc["x"], sc["y"]), sc["r"] + BR, fc=DARK, ec="black", lw=0.6, zorder=3.5))
        if sc.get("ax") is not None:
            ax.annotate("", (sc["x"] + sc["ax"] * 0.0, sc["y"] + sc["ay"] * 0.02), (sc["x"] - sc["ax"] * 0.22, sc["y"] - sc["ay"] * 0.22),
                        arrowprops=dict(arrowstyle="-|>", color="white", lw=0.8), zorder=10)
        ax.annotate("", (sc["x"] + sc["vx"] * 0.12, sc["y"] + sc["vy"] * 0.12), (sc["x"], sc["y"]),
                    arrowprops=dict(arrowstyle="-|>", color=(0.9, 0.2, 0.2), lw=0.8, ls="--"), zorder=10)
    # lamps (inserts)
    for l in t["lamps"]:
        ax.add_patch(Circle((l["x"], l["y"]), 0.05, fc=rgb(LAMP.get(l["colour"], LAMP["white"])), ec="black", lw=0.3, zorder=5, alpha=0.95))
    # ramps (above the playfield: their path and heights)
    for r in t["rails"]:
        p = r["pts"]
        xs, ys, hs = p[0::3], p[1::3], p[2::3]
        for i in range(len(xs) - 1):
            ax.add_patch(Polygon(seg_poly(xs[i], ys[i], xs[i + 1], ys[i + 1], 2 * BR + 0.06), closed=True,
                                 fc=(*plastic, 0.45), ec=(0, 0, 0, 0.6), lw=0.4, zorder=11))
        ax.plot(xs, ys, color="black", lw=0.6, ls="--", zorder=12)
        for x, y, h in zip(xs, ys, hs):
            ax.plot([x], [y], "o", ms=2.5, color="black", zorder=12)
            ax.text(x + 0.03, y + 0.03, f"h {h:.2f}", fontsize=5, zorder=13, color=(0.1, 0.1, 0.3))
        ax.annotate("", (xs[1], ys[1]), (xs[0], ys[0]), arrowprops=dict(arrowstyle="-|>", lw=0.8), zorder=12)
    # flippers: at rest (solid) and up (ghost)
    for f in t["flippers"]:
        up_pts, _ = flipper_shape(f, f["up"])
        ax.add_patch(Polygon(up_pts, closed=True, fc=(1, 1, 1, 0.25), ec=(0, 0, 0, 0.5), lw=0.5, ls="--", zorder=13))
        pts, tip = flipper_shape(f, f["rest"])
        ax.add_patch(Polygon(pts, closed=True, fc=RUBBER, ec="black", lw=0.7, zorder=14))
        ax.add_patch(Circle(tip, f["rTip"], fc=rgb((230, 60, 50)), ec="black", lw=0.4, zorder=15))
        ax.add_patch(Circle((f["x"], f["y"]), 0.012, fc="black", zorder=15))
    # plunger and ball
    pl = t["plunger"]
    ax.add_patch(Rectangle((pl["x"] - 0.0175, CB["ROD_Y0"]), 0.035, pl["y"] - BR - CB["ROD_Y0"], fc=CHROME, ec="black", lw=0.4, zorder=8))
    ax.add_patch(Rectangle((pl["x"] - 0.055, CB["ROD_Y0"] - CB["KNOB"] - 0.05), 0.11, 0.1, fc=rgb((230, 40, 40)), ec="black", lw=0.5, zorder=8))
    ax.add_patch(Circle((pl["x"], pl["y"]), BR, fc=rgb((210, 212, 218)), ec="black", lw=0.5, zorder=16))
    # flipper buttons
    for x in (-CB["RAIL"] - CB["BUTTON"]["out"], W + CB["RAIL"] + CB["BUTTON"]["out"]):
        ax.add_patch(Rectangle((x - 0.03, CB["BUTTON"]["y"] - 0.05), 0.06, 0.1, fc=rgb((230, 40, 40)), ec="black", lw=0.4, zorder=8))

    # ---- numbered call-outs (the key below lists them)
    key = []
    def call(x, y, text):
        key.append(text)
        num(ax, x, y, len(key))

    def find(lst, i):
        return next(v for v in t[lst] if v["id"] == i)
    fl, fr = find("flippers", "flipper_l"), find("flippers", "flipper_r")
    call(fl["x"] + 0.12, fl["y"] - 0.15, "Left flipper (rubber bat on a pivot pin; red tip). Dashed ghost = fully up")
    call(fr["x"] - 0.12, fr["y"] - 0.15, "Right flipper (mirror of the left)")
    sl = t["slings"][0]
    call((sl["x1"] + sl["x2"]) / 2 + 0.1, (sl["y1"] + sl["y2"]) / 2, "Slingshots (triangular plastic body, white kicking rubber on the inner face), both sides")
    for s in t["sensors"]:
        if s["id"] == "inlane_l":
            call((s["x1"] + s["x2"]) / 2, s["y1"] + 0.12, "Inlanes (feed the flippers), both sides; dashed green = rollover switch")
        if s["id"] == "outlane_l":
            call((s["x1"] + s["x2"]) / 2, s["y1"] + 0.12, "Outlanes (drain past the flippers), both sides; metal divider with a rounded cap")
    call(pl["x"], 1.6, "Shooter lane (ball rests on the plunger tip at the foot)")
    call(pl["x"], CB["ROD_Y0"] - 0.2, "Plunger: chrome rod through the front wall, red knob (pulls back 0.32)")
    g = t["gates"][0]
    call(g["x2"] - 0.05, g["y2"] + 0.12, "One-way gate at the head of the shooter lane (thin chrome flap)")
    call(XC, L - 0.05, "Wooden arch and side rails (the outer wall of the playfield)")
    call(XC, 0.25, "Apron (painted plate over the drain, carries the title); drain between the flippers")
    for i, b in enumerate(t["bumpers"]):
        if i == 0:
            call(b["x"], b["y"] + b["r"] + 0.06, f"Pop bumpers x{len(t['bumpers'])} (coloured skirt + lit cap), radius {b['r']}")
    dropped = [v for v in t["targets"] if v["kind"] == "drop"]
    stand = [v for v in t["targets"] if v["kind"] == "standup"]
    extra = {
        "pinball_acorn": [
            (0.12, 2.5, "A-C-O-R-N bank: five DROP targets (sink 0.16 into the table when hit), rubber behind, wooden backing wall"),
            (1.98, 2.75, "Spinner lane up the right side: metal guide + spinning chrome flag across the lane"),
            (1.1, 4.42, "Three top lanes between four wire guides (rubber posts at each end), rollover switches"),
            (0.3, 4.4, "Rebound rubber across the left of the arch"),
            (1.64, 3.2, "OAK standup targets x2 (wedge-backed, wooden backs), both sides of the low bumper"),
            (0.08, 1.92, "Rail guides (curved metal) feeding the inlanes, both sides"),
            (XC, 1.82, "Lamp inserts: THE HOARD (5 orange), bonus 2X/3X/5X, letters, extra ball, shoot again"),
        ],
        "pinball_rodent": [
            (0.6, 3.05, "THE WIRE: one ramp (clear plastic track) up the left, round the top, down the right to the right inlane; heights marked h"),
            (1.58, 3.72, "THE BITE: kick-out hole in a metal horseshoe (hole drawn black; red arrow = kick-out)"),
            (2.12, 2.9, "HOT LANE: the lane up the right side (soft-plunge skill shot), rollover switch"),
            (0.62, 3.62, "The nest: three pop bumpers top left"),
            (1.1, 2.05, "S-P-I-C-Y standup targets: two left, one centre, two right"),
            (XC, 1.55, "HEAT meter: 9 lamp inserts + FERAL / RABID / SUPER"),
        ],
        "pinball_space": [
            (0.3, 3.45, "LEFT RAMP (from the right flipper) drops into the left inlane; heights marked h"),
            (1.92, 3.45, "RIGHT RAMP (from the left flipper) drops into the right inlane"),
            (XC, 4.62, "ORBIT lane: metal inner guide round under the arch, rollovers at both ends and the top"),
            (1.85, 4.3, "DOCKING GAP (top right opening in the orbit guide): soft-plunge skill shot"),
            (0.17, 2.45, "LOCK PODS x2 (holes under a hood: a ball only drops in going UP the table, white arrow)"),
            (XC, 3.0, "Asteroid field: three pop bumpers"),
            (0.8, 2.3, "F-U-E-L standup targets at the corners of the two ramp mouths"),
            (XC, 1.55, "Lamp inserts: countdown 3-2-1, COMBO x5, JACKPOT, ramps, orbits, locks"),
        ],
    }[tid]
    for x, y, text in extra:
        call(x, y, text)
    # the key, under the plan
    fig.text(0.06, 0.035, "KEY\n" + "\n".join(f"{i}. {k}" for i, k in enumerate(key, 1)), fontsize=7.3, va="bottom", ha="left",
             family="DejaVu Sans")
    fig.text(0.06, 0.012, "Colours: brown = wooden rails  grey = metal wire guides  white = rubber  tinted = plastic  dashed green = rollover switch  "
             "dark = hole\nsmall discs = lamp inserts  dotted boxes = painted words.  Playfield 2.4 x 4.9 studs = 0.672 x 1.372 m.",
             fontsize=6.5, color=(0.25, 0.25, 0.25))
    fig.subplots_adjust(left=0.08, right=0.93, top=0.93, bottom=0.2)
    fig.savefig(f"{OUT}/{variant}_plan.png", dpi=160)
    plt.close(fig)
    return key


# ---------------- the cabinet (shared by all three) -----------------
def cab_pt(x, y, h):
    along = y - L / 2
    s, c = math.sin(LY["TILT"]), math.cos(LY["TILT"])
    across, up, al = x - W / 2, along * s + h * c, along * c - h * s
    # (lateral to the player's right, height above the floor, toward the player from the machine's middle)
    return across, CB["PF_Y"] + up, CB["PF_D"] - al

def draw_cabinet():
    R, G, below = CB["RAIL"], CB["GLASS_H"], 0.85
    BB, LG = CB["BACKBOX"], CB["LEGS"]
    fig, (a1, a2) = plt.subplots(1, 2, figsize=(17, 9.5), gridspec_kw=dict(width_ratios=[1.75, 1]))
    # side view: z toward the player (right), Y up
    def box_side(ax, y0, y1, h0, h1, **kw):
        pts = [cab_pt(0, y, h)[1:] for y, h in ((y0, h0), (y1, h0), (y1, h1), (y0, h1))]
        ax.add_patch(Polygon([(p[1], p[0]) for p in pts], closed=True, **kw))
        return pts
    body = (0.35, 0.3, 0.32)
    box_side(a1, -0.27, L + 0.08, -below, G + 0.05, fc=(*body, 0.25), ec="black", lw=1)  # side rail / cabinet wall
    box_side(a1, -0.16, L, -0.06, 0, fc=(0.8, 0.65, 0.4), ec="black", lw=0.6)  # playfield board
    box_side(a1, 0, L, G - 0.01, G + 0.01, fc=(0.6, 0.8, 0.9), ec=(0.3, 0.5, 0.6), lw=0.6)  # glass
    box_side(a1, -0.275, -0.145, G + 0.055, G + 0.105, fc=(0.8, 0.8, 0.85), ec="black", lw=0.6)  # lockdown bar
    # legs
    for y in (-0.05, L - 0.25):
        _, Y, Z = cab_pt(R - LG["inset"], y, -below)
        a1.add_patch(Rectangle((Z - LG["size"] / 2, 0), LG["size"], Y, fc=(0.6, 0.6, 0.6), ec="black", lw=0.6))
        a1.text(Z + 0.15, Y / 2, f"leg {Y:.2f} tall", fontsize=7, rotation=90, va="center")
    # backbox (alley frame: z from PINBALL_D)
    a1.add_patch(Rectangle((BB["back"], BB["y0"]), BB["front"] - BB["back"], BB["y1"] - BB["y0"], fc=(*body, 0.3), ec="black", lw=1))
    a1.add_patch(Rectangle((BB["front"] - 0.06, BB["y0"] + 0.15), 0.06, BB["y1"] - BB["y0"] - 0.3, fc=(0.1, 0.1, 0.2), ec="black", lw=0.5))
    a1.add_patch(Rectangle((BB["front"] - 0.06, BB["y1"] - 0.12), 0.08, 0.12, fc=(1, 0.6, 0.2), ec="black", lw=0.5))
    # plunger, coin door, button
    _, Yk, Zk = cab_pt(W, CB["ROD_Y0"] - CB["KNOB"], 0.04)
    a1.add_patch(Circle((Zk, Yk), 0.055, fc=(0.9, 0.15, 0.15), ec="black", lw=0.5))
    _, Yd, Zd = cab_pt(W / 2, -0.28, -below / 2)
    a1.plot([Zd + 0.02, Zd + 0.02 - 0.55 * math.sin(LY["TILT"])], [Yd - 0.05 - 0.275, Yd - 0.05 + 0.275], color=(0.2, 0.2, 0.25), lw=3)
    _, Yb, Zb = cab_pt(-R, CB["BUTTON"]["y"], CB["BUTTON"]["h"])
    a1.add_patch(Circle((Zb, Yb), 0.05, fc=(0.9, 0.15, 0.15), ec="black", lw=0.5))
    a1.plot([3.7], [0.1], "v", ms=9, color="green")
    a1.text(3.7, 0.35, "player\nstands\nhere", fontsize=7, ha="center", color="green")
    # dimensions
    def dim(ax, p, q, text, off=(0, 0), rot=0):
        ax.annotate("", p, q, arrowprops=dict(arrowstyle="<->", lw=0.7, color=(0.1, 0.2, 0.6)))
        ax.text((p[0] + q[0]) / 2 + off[0], (p[1] + q[1]) / 2 + off[1], text, fontsize=7.5, color=(0.1, 0.2, 0.6), ha="center", rotation=rot,
                bbox=dict(fc="white", ec="none", pad=0.5))
    _, yF, zF = cab_pt(0, 0, 0)
    _, yB, zB = cab_pt(0, L, 0)
    dim(a1, (BB["back"] - 0.25, BB["y0"]), (BB["back"] - 0.25, BB["y1"]), f"backbox\n{BB['y1'] - BB['y0']:.2f} tall", off=(-0.35, 0))
    dim(a1, (BB["back"], BB["y1"] + 0.2), (BB["front"], BB["y1"] + 0.2), f"{BB['front'] - BB['back']:.2f} deep", off=(0, 0.12))
    dim(a1, (4.4, 0), (4.4, yF), f"front of playfield\n{yF:.2f} above floor", off=(0.42, 0), rot=0)
    dim(a1, (BB["back"] - 0.7, 0), (BB["back"] - 0.7, BB["y1"]), f"overall\n{BB['y1']:.2f} tall", off=(-0.35, 0))
    dim(a1, (zB, 2.0), (zF, 2.0), f"playfield {L} along the slope (pitched {math.degrees(LY['TILT']):.1f} deg)", off=(0, 0.12))
    a1.annotate("glass 0.50 above the playfield", cab_pt(0, 2.2, G)[2:0:-1], (1.2, 5.3), fontsize=7.5, arrowprops=dict(arrowstyle="-", lw=0.5))
    a1.annotate("lockdown bar (chrome)", cab_pt(0, -0.21, G + 0.08)[2:0:-1], (3.4, 5.0), fontsize=7.5, arrowprops=dict(arrowstyle="-", lw=0.5))
    a1.annotate("plunger knob", (Zk, Yk), (3.6, 3.0), fontsize=7.5, arrowprops=dict(arrowstyle="-", lw=0.5))
    a1.annotate("flipper button (each side)", (Zb, Yb), (3.4, 2.4), fontsize=7.5, arrowprops=dict(arrowstyle="-", lw=0.5))
    a1.annotate("coin door 0.70 x 0.55\n(FREE PLAY only)", (Zd, Yd - 0.1), (3.2, 1.6), fontsize=7.5, arrowprops=dict(arrowstyle="-", lw=0.5))
    a1.annotate("backglass (score display)\n+ neon light strip on top", (BB["front"], 6.0), (-0.9, 6.9), fontsize=7.5, arrowprops=dict(arrowstyle="-", lw=0.5))
    a1.set_xlim(-3.6, 4.9); a1.set_ylim(-0.2, 8.3); a1.set_aspect("equal"); a1.grid(True, lw=0.3, alpha=0.4)
    a1.set_xlabel("studs toward the player, from the machine's middle", fontsize=8)
    a1.set_ylabel("studs above the floor", fontsize=8)
    a1.set_title("Cabinet, side view (the same body for all three machines)", fontsize=11, fontweight="bold")
    a1.tick_params(labelsize=7)
    # front view (as the player sees it): X across, Y up; ignore the pitch for the outline
    half = BB["half"]
    _, yfr, _ = cab_pt(0, -0.27, -below)
    a2.add_patch(Rectangle((-half, yfr), 2 * half, (cab_pt(0, -0.27, G + 0.05)[1]) - yfr, fc=(*body, 0.25), ec="black", lw=1))
    a2.add_patch(Rectangle((-half, BB["y0"]), 2 * half, BB["y1"] - BB["y0"], fc=(*body, 0.3), ec="black", lw=1))
    a2.add_patch(Rectangle((-half + 0.12, BB["y0"] + 0.15), 2 * half - 0.24, BB["y1"] - BB["y0"] - 0.3, fc=(0.1, 0.1, 0.2), ec="black", lw=0.5))
    a2.add_patch(Rectangle((-half, BB["y1"] - 0.12), 2 * half, 0.12, fc=(1, 0.6, 0.2), ec="black", lw=0.5))
    for k, (txt, y, h) in enumerate((("Title", 0.03, 0.2), ("Score", 0.26, 0.24), ("Info", 0.52, 0.1), ("Say", 0.64, 0.16), ("Best", 0.83, 0.12))):
        gy1 = BB["y1"] - 0.15 - (BB["y1"] - BB["y0"] - 0.3) * y
        gy0 = gy1 - (BB["y1"] - BB["y0"] - 0.3) * h
        a2.add_patch(Rectangle((-half + 0.2, gy0), 2 * half - 0.4, gy1 - gy0, fc="none", ec=(0.8, 0.8, 1), lw=0.5, ls="--"))
        a2.text(0, (gy0 + gy1) / 2, f"{txt} line", color="white", fontsize=7, ha="center", va="center")
    for x in (-half + LG["inset"], half - LG["inset"]):
        a2.add_patch(Rectangle((x - LG["size"] / 2, 0), LG["size"], yfr, fc=(0.6, 0.6, 0.6), ec="black", lw=0.6))
    a2.add_patch(Rectangle((-0.35, yfr + 0.06), 0.7, 0.55, fc=(0.25, 0.25, 0.28), ec="black", lw=0.6))
    a2.text(0, yfr + 0.33, "FREE PLAY", color=(0.3, 1, 0.45), fontsize=7, ha="center", va="center")
    _, yk, _ = cab_pt(W, CB["ROD_Y0"], 0.04)
    a2.add_patch(Circle(((LY["LANE_X"] - W / 2), yk), 0.055, fc=(0.9, 0.15, 0.15), ec="black"))
    for s in (-1, 1):
        a2.add_patch(Rectangle((s * half - (0.06 if s > 0 else 0), Yb - 0.05), 0.06, 0.1, fc=(0.9, 0.15, 0.15), ec="black", lw=0.5))
    a2.annotate("", (-half, 8.0), (half, 8.0), arrowprops=dict(arrowstyle="<->", lw=0.7, color=(0.1, 0.2, 0.6)))
    a2.text(0, 8.1, f"{2 * half:.2f} wide (playfield 2.40 + two 0.15 side walls)", fontsize=7.5, ha="center", color=(0.1, 0.2, 0.6))
    a2.text(0, -0.2, "machines 4.5 apart, centre to centre;\nbacks 1 stud off the wall", fontsize=7, ha="center")
    a2.set_xlim(-2.1, 2.1); a2.set_ylim(-0.3, 8.4); a2.set_aspect("equal"); a2.grid(True, lw=0.3, alpha=0.4)
    a2.set_title("Front view (the player's side)", fontsize=11, fontweight="bold"); a2.tick_params(labelsize=7)
    fig.text(0.5, 0.01, "All figures in studs. In Blender at Roblox's 0.28 m per stud: overall 7.7 studs = 2.16 m tall, 2.7 studs = 0.76 m wide. "
             "Plunger knob is on the player's RIGHT (the shooter lane). The playfield, side walls, glass, lockdown bar and body all tilt together.",
             ha="center", fontsize=8)
    fig.tight_layout(rect=(0, 0.03, 1, 1))
    fig.savefig(f"{OUT}/cabinet.png", dpi=150)
    plt.close(fig)


# ---------------- the parts sheet (shared parts, to scale) -----------------
def draw_parts():
    fig, axs = plt.subplots(3, 4, figsize=(17, 12.5))
    axs = axs.flatten()
    def setup(ax, title, lim):
        ax.set_aspect("equal"); ax.set_xlim(*lim[0]); ax.set_ylim(*lim[1]); ax.grid(True, lw=0.3, alpha=0.4)
        ax.set_title(title, fontsize=9.5, fontweight="bold"); ax.tick_params(labelsize=6)
    def side(ax, x, w, h, y0=0, **kw):
        ax.add_patch(Rectangle((x - w / 2, y0), w, h, **kw))
    t0 = D["tables"]["pinball_acorn"]
    f = dict(t0["flippers"][0]); f["x"], f["y"] = 0, 0
    # 1 flipper (top)
    ax = axs[0]; setup(ax, "Flipper, from above", ((-0.1, 0.45), (-0.25, 0.15)))
    pts, tip = flipper_shape(f, 0)
    ax.add_patch(Polygon(pts, fc=RUBBER, ec="black")); ax.add_patch(Circle(tip, f["rTip"], fc=rgb((230, 60, 50)), ec="black")); ax.plot(0, 0, "ko", ms=3)
    ax.text(0.16, -0.12, f"pivot to tip centre {f['len']}\nbase radius {f['rBase']}, tip radius {f['rTip']}\nheight {CB['FLIPPER_H']}\n"
            f"rest {math.degrees(f['rest']):.0f} deg, up +{math.degrees(f['up']):.0f} deg\n(swing {math.degrees(f['up'] - f['rest']):.0f} deg about the pin)", fontsize=7, ha="center")
    # 2 pop bumper (side)
    ax = axs[1]; setup(ax, "Pop bumper, side view", ((-0.2, 0.2), (-0.03, 0.42)))
    side(ax, 0, 0.24, 0.16, fc=(0.8, 0.3, 0.2), ec="black"); side(ax, 0, 0.204, 0.04, y0=0.16, fc=(1, 0.93, 0.7), ec="black")
    ax.text(0, 0.3, "body: radius 0.11-0.12 (per table), 0.16 tall\nlit cap on top: radius 0.85 x body, 0.04 thick\n(top at 0.20). The game has no skirt yet: yours", fontsize=7, ha="center")
    # 3 slingshot (top)
    sl = t0["slings"][0]
    w = next(w for w in t0["walls"] if w["mat"] == "plastic" and len(w["pts"]) == 6)
    p = w["pts"]; ox, oy = p[2], p[3]
    ax = axs[2]; setup(ax, "Slingshot, from above (left one)", ((-0.1, 0.45), (-0.25, 0.5)))
    ax.add_patch(Polygon([(p[0] - ox, p[1] - oy), (p[2] - ox, p[3] - oy), (p[4] - ox, p[5] - oy)], fc=(1, 0.6, 0.2), ec="black"))
    thick_line(ax, [sl["x1"] - ox, sl["y1"] - oy, sl["x2"] - ox, sl["y2"] - oy], 0.035, RUBBER, edge="black")
    for i in range(0, 6, 2):
        ax.add_patch(Circle((p[i] - ox, p[i + 1] - oy), 0.022, fc=RUBBER, ec="black"))
    ax.text(0.25, 0.42, "plastic body 0.10 tall\nwhite rubber band (0.035 thick,\n0.09 tall) on the inner face\nrubber posts r 0.022 at corners", fontsize=7, ha="center")
    # 4 post
    ax = axs[3]; setup(ax, "Posts, side view", ((-0.1, 0.1), (-0.02, 0.2)))
    side(ax, -0.04, 0.044, 0.11, fc=RUBBER, ec="black"); side(ax, 0.04, 0.044, 0.14, fc=CHROME, ec="black")
    ax.text(-0.04, 0.13, "rubber\n0.11 tall", fontsize=7, ha="center"); ax.text(0.04, 0.16, "metal\n0.14 tall", fontsize=7, ha="center")
    ax.text(0, -0.01, "radius 0.022 (lane caps 0.012)", fontsize=7, ha="center")
    # 5 drop target
    ax = axs[4]; setup(ax, "Drop target, side view", ((-0.1, 0.1), (-0.2, 0.18)))
    ax.add_patch(Rectangle((-0.1, -0.06), 0.2, 0.06, fc=(0.8, 0.65, 0.4), ec="black"))
    side(ax, -0.03, 0.03, 0.12, fc=(0.95, 0.8, 0.25), ec="black")
    side(ax, 0.04, 0.03, 0.12, y0=-CB["DROP_SINK"], fc=(0.95, 0.8, 0.25, 0.4), ec="black", ls="--")
    ax.text(0, 0.15, "0.03 thick, 0.12 tall, ~0.10 wide each\nhit: sinks 0.16 into the board (dashed)", fontsize=7, ha="center")
    # 6 standup
    ax = axs[5]; setup(ax, "Standup target, side view", ((-0.1, 0.1), (-0.05, 0.2)))
    side(ax, 0, 0.03, 0.12, fc=(0.95, 0.8, 0.25), ec="black")
    ax.text(0, 0.16, "face 0.03 thick, 0.12 tall, fixed (does not drop)\nthe game draws a bare face: add the bracket", fontsize=7, ha="center")
    # 7 spinner
    ax = axs[6]; setup(ax, "Spinner, front view", ((-0.17, 0.17), (-0.02, 0.24)))
    ax.plot([-0.15, -0.15, 0.15, 0.15], [0, 0.17, 0.17, 0], color="gray", lw=2)
    ax.add_patch(Rectangle((-0.13, 0.05), 0.26, 0.1, fc=CHROME, ec="black", hatch="///"))
    ax.text(0, 0.2, "chrome flag 0.10 tall across the lane,\nspins on a wire bracket at h 0.10", fontsize=7, ha="center")
    # 8 one-way gate
    ax = axs[7]; setup(ax, "One-way gate, side view", ((-0.15, 0.15), (-0.02, 0.2)))
    ax.plot([-0.12, -0.12, 0.12, 0.12], [0, 0.14, 0.14, 0], color="gray", lw=2)
    ax.add_patch(Rectangle((-0.1, 0.05), 0.2, 0.05, fc=CHROME, ec="black"))
    ax.text(0, 0.17, "thin flap 0.012 thick, 0.05 tall,\nhinged at h 0.05-0.10; swings one way", fontsize=7, ha="center")
    # 9 lane guide / walls cross-sections
    ax = axs[8]; setup(ax, "Wall cross-sections (to scale)", ((-0.05, 0.42), (-0.02, 0.26)))
    x = 0
    for name, (tt, hh, col) in {"wood rail": (0.06, 0.2, (0.6, 0.45, 0.25)), "metal wire guide": (0.022, 0.11, CHROME),
                                "plastic guide": (0.045, 0.1, (1, 0.6, 0.2)), "rubber band": (0.035, 0.08, RUBBER)}.items():
        side(ax, x, tt, hh, fc=col, ec="black"); ax.text(x, hh + 0.015, f"{name}\n{tt} x {hh}", fontsize=6, ha="center"); x += 0.11
    # 10 kick-out hole / scoop
    ax = axs[9]; setup(ax, "Kick-out hole / lock pod, from above", ((-0.25, 0.25), (-0.28, 0.25)))
    ax.add_patch(Circle((0, 0), 0.1 + BR, fc=DARK, ec="black"))
    ax.add_patch(matplotlib.patches.Arc((0, 0), 0.33, 0.33, theta1=256 + 75, theta2=256 + 285, lw=3, color="gray"))
    ax.annotate("", (0.0, -0.05), (0.06, 0.2), arrowprops=dict(arrowstyle="-|>", color="white"))
    ax.text(0, -0.235, "THE BITE: hole r 0.1625, metal horseshoe r 0.165, open 150 deg toward\nthe lower left (the ball comes in there). Lock pods (Space): hole r 0.1475;\nthe hood on their top side is not built in the game yet: yours", fontsize=6.5, ha="center")
    # 11 ramp cross-section
    ax = axs[10]; setup(ax, "Ramp, cross-section", ((-0.15, 0.15), (-0.05, 0.2)))
    ax.add_patch(Rectangle((-0.0925, 0), 0.185, 0.02, fc=(1, 0.6, 0.2, 0.6), ec="black"))
    ax.add_patch(Circle((0, 0.02 + BR), BR, fc=CHROME, ec="black"))
    ax.plot([-0.0925, -0.0925], [0, 0.08], color="gray", lw=2); ax.plot([0.0925, 0.0925], [0, 0.08], color="gray", lw=2)
    ax.text(0, 0.16, "clear plastic track 0.185 wide (ball 0.125 + 0.06)\nrises to h 0.30; side walls are yours to add", fontsize=7, ha="center")
    # 12 ball + plunger
    ax = axs[11]; setup(ax, "Ball and plunger, side view", ((-0.6, 0.3), (-0.12, 0.25)))
    ax.add_patch(Circle((0.2, BR), BR, fc=CHROME, ec="black"))
    ax.add_patch(Rectangle((-0.45, 0.04 - 0.0175), 0.58, 0.035, fc=CHROME, ec="black"))
    ax.add_patch(Rectangle((-0.55, 0.04 - 0.055), 0.1, 0.11, fc=(0.9, 0.15, 0.15), ec="black"))
    ax.text(-0.1, 0.18, "ball diameter 0.125 (chrome)\nrod 0.035 thick, knob 0.11 x 0.11 x 0.10\nknob pulls back 0.32", fontsize=7, ha="center")
    fig.suptitle("Shared parts, to scale (studs). x 0.28 for metres.", fontsize=13, fontweight="bold")
    fig.tight_layout(rect=(0, 0, 1, 0.96))
    fig.savefig(f"{OUT}/parts.png", dpi=150)
    plt.close(fig)


keys = {}
for tid in D["tables"]:
    keys[tid] = draw_table(tid)
draw_cabinet()
draw_parts()
print("done", os.listdir(OUT))
