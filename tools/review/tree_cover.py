"""tools/review/tree_cover.py: the town's tree cover from above (owner D34: "making the map have more trees").

  lune run tools/review/tree_cover.luau --before --out build/review/tree_cover_before.json
  lune run tools/review/tree_cover.luau --out build/review/tree_cover_after.json
  python3 -I tools/review/tree_cover.py --data build/review/tree_cover_before.json --out docs/renders/trees/cover_before.jpg
  python3 -I tools/review/tree_cover.py --data build/review/tree_cover_after.json --out docs/renders/trees/cover_after.jpg

Top-down over the world clamp, north (+Z) up and +X on the LEFT, like the in-game map (Shared/Map/MapModel and
tools/review/approval_map.py). Ground shaded by height (the river blue), roads grey, buildings dark, flat lot parts
pale; every tree a crown disc at its reach: the route trees (the town's 98 and the D34 climbable ones, outlined
red) in mid green, the D34 woods by family (pines dark blue-green, nut trees olive, broadleaf green). A legend counts
them. System python3 + Pillow only.
"""
import argparse
import io
import json
import os

from PIL import Image, ImageDraw, ImageFont

FONT = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
FAMILY = {
    "giant": ((40, 110, 40), "new giants (oak, elm, beech)"),
    "pine": ((38, 84, 62), "pines, spruces, firs"),
    "nut": ((122, 132, 52), "nut trees (walnut, hazel, chestnut, hickory, oaks)"),
    "broadleaf": ((70, 128, 58), "broadleaf"),
}
ROUTE = (92, 150, 70)
NOROUTE = (170, 170, 150)
GROWN = (200, 40, 40)


def font(path, size):
    try:
        return ImageFont.truetype(path, size)
    except OSError:
        return ImageFont.load_default()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--data", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--px", type=float, default=0.62, help="pixels per stud")
    ap.add_argument("--title", default="")
    ap.add_argument("--max-kb", type=int, default=900)
    a = ap.parse_args()
    with open(a.data) as fh:
        doc = json.load(fh)
    B = doc["bounds"]
    k = a.px
    W = int((B["x1"] - B["x0"]) * k)
    H = int((B["z1"] - B["z0"]) * k)
    legend_h = 120
    img = Image.new("RGB", (W, H + legend_h), (236, 232, 220))
    dr = ImageDraw.Draw(img, "RGBA")

    def px(x, z):
        # +X on the left, +Z up
        return (B["x1"] - x) * k, (B["z1"] - z) * k

    # ground
    g = doc["grid"]
    nx, step = g["nx"], B["step"]
    hs = [c[0] for c in g["cells"]]
    lo, hi = min(hs), max(hs)
    for i, (h, water) in enumerate(g["cells"]):
        x = B["x0"] + (i % nx) * step
        z = B["z0"] + (i // nx) * step
        x0, y0 = px(x + step / 2, z + step / 2)
        x1, y1 = px(x - step / 2, z - step / 2)
        if water:
            col = (120, 165, 200)
        else:
            t = (h - lo) / max(hi - lo, 1e-6)
            col = (int(196 - 40 * t), int(206 - 28 * t), int(160 - 50 * t))
        dr.rectangle([x0, y0, x1, y1], fill=col)
    # world clamp outline
    cx0, cx1, cz0, cz1 = doc["clamp"]
    a0, b0 = px(cx1, cz1)
    a1, b1 = px(cx0, cz0)
    dr.rectangle([a0, b0, a1, b1], outline=(90, 90, 90), width=2)
    # town
    order = {"flat": 0, "road": 1, "building": 2}
    cols = {"flat": (214, 208, 190, 255), "road": (150, 148, 144, 255), "building": (88, 80, 76, 255)}
    for cat, x0, z0, x1, z1 in sorted(doc["boxes"], key=lambda b: order[b[0]]):
        p0 = px(x1, z1)
        p1 = px(x0, z0)
        dr.rectangle([p0[0], p0[1], max(p1[0], p0[0] + 1), max(p1[1], p0[1] + 1)], fill=cols[cat])
    for cat, pts in doc.get("polys", []):
        xy = [px(x, z) for x, z in pts]
        if cat == "site":
            dr.polygon(xy, fill=(214, 208, 190, 255), outline=(150, 140, 120, 255))
        else:
            dr.polygon(xy, outline=(200, 120, 40, 255), width=2)
    for cat, w, pts in doc.get("lines", []):
        xy = [px(x, z) for x, z in pts]
        col = (150, 148, 144, 255) if cat == "path" else (160, 60, 160, 255)
        dr.line(xy, fill=col, width=max(2, int(w * k)))
    for cat, x0, z0, x1, z1 in doc["boxes"]:
        if cat == "building":
            p0, p1 = px(x1, z1), px(x0, z0)
            dr.rectangle([p0[0], p0[1], p1[0], p1[1]], fill=cols[cat])
    # crowns: woods first, route trees over them
    counts = {}
    for kind, fam, x, z, r in doc["woods"]:
        cx, cz = px(x, z)
        rr = max(r * k, 2)
        col = FAMILY.get(fam, FAMILY["broadleaf"])[0]
        dr.ellipse([cx - rr, cz - rr, cx + rr, cz + rr], fill=col + (205,), outline=(20, 40, 20, 220))
        counts[fam] = counts.get(fam, 0) + 1
    route = grown = noroute = 0
    for kind, x, z, r, h, label in doc["trees"]:
        cx, cz = px(x, z)
        rr = max(r * k, 2)
        if kind in ("grown", "climb"):
            grown += 1
            dr.ellipse([cx - rr, cz - rr, cx + rr, cz + rr], fill=ROUTE + (215,), outline=GROWN + (255,), width=2)
        elif kind == "noroute":
            noroute += 1
            dr.ellipse([cx - rr, cz - rr, cx + rr, cz + rr], fill=NOROUTE + (215,), outline=(60, 60, 60, 230))
        else:
            route += 1
            dr.ellipse([cx - rr, cz - rr, cx + rr, cz + rr], fill=ROUTE + (200,), outline=(30, 60, 30, 230))
        dr.ellipse([cx - 1.5, cz - 1.5, cx + 1.5, cz + 1.5], fill=(70, 50, 30, 255))
    # legend
    f, fb = font(FONT, 18), font(BOLD, 22)
    y = H + 10
    total = route + grown + noroute + sum(counts.values())
    title = a.title or ("BEFORE" if doc.get("before") else "AFTER") + f": {total} trees, {route + grown + sum(counts.values())} climbable"
    dr.text((14, y), title + "   (north up, +X on the left, like the game's map)", fill=(20, 20, 20), font=fb)
    y += 34
    x = 14
    items = [(ROUTE, f"town trees with climbing routes: {route}", None)]
    climbable = route + grown + sum(counts.values())
    if noroute:
        items.append((NOROUTE, f"trees with no climbing route: {noroute}", None))
    if grown:
        items.append((ROUTE, f"trees given climbing routes (red ring): {grown}", GROWN))
    for fam, (col, name) in FAMILY.items():
        if counts.get(fam):
            items.append((col, f"{name}: {counts[fam]}", None))
    for col, text, ring in items:
        dr.ellipse([x, y + 2, x + 18, y + 20], fill=col, outline=ring or (20, 40, 20), width=3 if ring else 1)
        dr.text((x + 26, y), text, fill=(20, 20, 20), font=f)
        x += 36 + int(dr.textlength(text, font=f))
        if x > W - 400:
            x, y = 14, y + 30
    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    q = 90
    while True:
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=q, optimize=True)
        if buf.tell() <= a.max_kb * 1024 or q <= 40:
            break
        q -= 5
    with open(a.out, "wb") as fh:
        fh.write(buf.getvalue())
    print(f"{a.out}: {W}x{H + legend_h}, {total} trees, {buf.tell() // 1024} KB (q {q})")


if __name__ == "__main__":
    main()
