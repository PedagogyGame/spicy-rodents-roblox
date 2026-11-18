"""The three pinball playfield textures (486 x 1024, the top of the image the back of the table), redrawn with
the painted words where the game now puts them (tools/bake/games/Pinball's Bake.ART, held clear of every lamp,
ramp, guide and other word by tests/unit/pinball_art_words.spec.luau).

  lune run tools/review/pinball_blender/dump.luau build/review/pinball_tables.json
  python3 -I tools/blender/pinball/boards.py [--tables build/review/pinball_tables.json] [--out build/art/pinball/textures]

The look is ChatGPT's (docs/reference/pinball_art/Source_Project/build/source/art_textures.py, the owner's
18 November delivery): the field colour with a double pinstripe, the darker shooter lane and its arrows, each
table's ornament (ACORN ATTACK: the sunburst behind the bumpers, acorn motifs, the bonus cartouche; SPICY
RODENT: heat tracks under the wire, the heat-meter enclosure, low flames; SPACE SQUIRREL: stars, orbit arcs,
chevrons, the countdown and combo panels), his emblem printed on the open field, ringed bumper seats, a lamp
insert ring at every lamp and the words as the last layer on a quiet underprint. What changes from his script:
the words' places (the game's corrected ones), the panels and the cartouche drawn round the lamps and words
they hold (his were fixed boxes round the old places), the fonts (his condensed faces are not on this machine:
DejaVu Sans / Serif Bold, scaled into the same boxes), and every number read from the game's own data (the
dump), not from a copy. Nothing is written outside --out. Needs Pillow.
"""
import argparse
import json
import math
import os
import random

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
EMBLEMS = os.path.join(ROOT, "docs", "reference", "pinball_art", "Source_Project", "build", "source", "art_originals")
S_M = 0.28  # metres per stud
SS = 3  # supersampling
W, H = 486, 1024  # the board texture
BOARD_X = (0.0, 0.672)  # metres: the Board mesh's x and z extent (pinball_data.json: board)
BOARD_Z = (-1.372, 0.0448)
LAMP_R = 0.05 * S_M  # the lamp insert (the bake's Lamp part)
MACHINES = (("acorn", "pinball_acorn", "Acorn"), ("rodent", "pinball_rodent", "Rodent"), ("space", "pinball_space", "Space"))
FONTS = {
    "sans": ["/usr/share/fonts/truetype/dejavu/DejaVuSansCondensed-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"],
    "serif": ["/usr/share/fonts/truetype/dejavu/DejaVuSerifCondensed-Bold.ttf", "/usr/share/fonts/truetype/dejavu/DejaVuSerif-Bold.ttf"],
}


def font(kind, size):
    for path in FONTS[kind]:
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    raise SystemExit(f"no {kind} font: install DejaVu ({FONTS[kind][-1]})")


def blend(a, b, t):
    return tuple(round(a[i] * (1 - t) + b[i] * t) for i in range(3))


# ---- the frame: metres on the board (x across, z toward the player) -> supersampled pixels
def xy(x, z):
    return ((x - BOARD_X[0]) / (BOARD_X[1] - BOARD_X[0]) * W * SS, (z - BOARD_Z[0]) / (BOARD_Z[1] - BOARD_Z[0]) * H * SS)


def rad(rx, rz):
    return (rx / (BOARD_X[1] - BOARD_X[0]) * W * SS, rz / (BOARD_Z[1] - BOARD_Z[0]) * H * SS)


def box_world(x, z, w, h):
    cx, cy = xy(x, z)
    rx, ry = rad(w / 2, h / 2)
    return (cx - rx, cy - ry, cx + rx, cy + ry)


def line_m(d, pts, fill, width=0.0014):
    d.line([xy(*p) for p in pts], fill=fill, width=max(1, round(rad(width, 0)[0])), joint="curve")


def poly_m(d, pts, fill):
    d.polygon([xy(*p) for p in pts], fill=fill)


def ellipse_m(d, x, z, rx, rz, fill=None, outline=None, width=1.0):
    cx, cy = xy(x, z)
    a, b = rad(rx, rz)
    d.ellipse((cx - a, cy - b, cx + a, cy + b), fill=fill, outline=outline, width=max(1, round(width * SS)))


def lettering(im, text, box, colour, kind, fit=0.98):
    """The text as large as it fits inside the box (uniform scale), centred."""
    x0, y0, x1, y1 = box
    f = font(kind, 160)
    bb = f.getbbox(text)
    glyph = Image.new("RGBA", (bb[2] - bb[0] + 8, bb[3] - bb[1] + 8))
    ImageDraw.Draw(glyph).text((4 - bb[0], 4 - bb[1]), text, font=f, fill=(*colour, 255))
    glyph = glyph.crop(glyph.getbbox())
    scale = min((x1 - x0) * fit / glyph.width, (y1 - y0) * fit / glyph.height)
    tw, th = max(1, round(glyph.width * scale)), max(1, round(glyph.height * scale))
    glyph = glyph.resize((tw, th), Image.Resampling.LANCZOS)
    im.alpha_composite(glyph, (round((x0 + x1 - tw) / 2), round((y0 + y1 - th) / 2)))


def paste_emblem(im, emblem, x, z, w):
    art = Image.open(emblem).convert("RGBA")
    art = art.crop(art.getchannel("A").getbbox())
    size = round(rad(w, 0)[0])
    art = art.resize((size, round(size * art.height / art.width)), Image.Resampling.LANCZOS)
    cx, cy = xy(x, z)
    im.alpha_composite(art, (round(cx - art.width / 2), round(cy - art.height / 2)))


def acorn_glyph(d, x, z, size, c):
    """His acorn motif (printed ornament only)."""
    ellipse_m(d, x, z + size * 0.10, size * 0.34, size * 0.46, fill=c["art"])
    ellipse_m(d, x, z + size * 0.10, size * 0.27, size * 0.38, fill=c["plastic"])
    ellipse_m(d, x, z - size * 0.25, size * 0.40, size * 0.20, fill=c["art"])
    for j in (-0.2, 0, 0.2):
        line_m(d, [(x - size * 0.30, z - size * 0.26 + j * size), (x + size * 0.30, z - size * 0.26 + j * size)], c["trim"], 0.0007)
    line_m(d, [(x, z - size * 0.4), (x + size * 0.07, z - size * 0.58)], c["art"], 0.0019)


# ---- the game's data, in metres on the board
def machine(dump, variant, tid):
    t, th = dump["tables"][tid], dump["themes"][variant]
    lamps = {lp["id"]: lp for lp in t["lamps"]}

    def XZ(x, y):
        return (x * S_M, -y * S_M)

    words = []
    for p in dump["art"][variant]:
        lp = lamps.get(p.get("lamp")) if p.get("lamp") else None
        x = (lp["x"] if lp else p.get("x", 0)) + p["dx"]
        y = (lp["y"] if lp else p.get("y", 0)) + p["dy"]
        words.append({"text": p["text"], "lamp": p.get("lamp"), "centre": XZ(x, y), "w": p["w"] * S_M, "h": p["h"] * S_M})
    br = dump["layout"]["BALL_R"]
    return {
        "colours": {k: tuple(th[k]) for k in ("body", "trim", "field", "apron", "plastic", "bumper", "cap", "target", "glow", "legs", "art", "ink")},
        "words": words,
        "lamps": [{"id": lp["id"], "centre": XZ(lp["x"], lp["y"])} for lp in t["lamps"]],
        "bumpers": [{"centre": XZ(b["x"], b["y"]), "r": b["r"] * S_M} for b in t["bumpers"]],
        "holes": [{"centre": XZ(h["x"], h["y"]), "r": (h["r"] + br) * S_M} for h in t["saucers"]],
        "xc": dump["layout"]["XC"] * S_M,
    }


def bounds(m, lamp_prefixes, words=()):
    """A panel round some lamps (by id prefix) and words (by text): (cx, cz, w, h) in metres, padded."""
    xs, zs = [], []
    for lp in m["lamps"]:
        if any(lp["id"].startswith(p) for p in lamp_prefixes):
            x, z = lp["centre"]
            xs += [x - LAMP_R, x + LAMP_R]
            zs += [z - LAMP_R, z + LAMP_R]
    for wd in m["words"]:
        if wd["text"] in words:
            x, z = wd["centre"]
            xs += [x - wd["w"] / 2, x + wd["w"] / 2]
            zs += [z - wd["h"] / 2, z + wd["h"] / 2]
    pad = 0.008
    x0, x1, z0, z1 = min(xs) - pad, max(xs) + pad, min(zs) - pad, max(zs) + pad
    return ((x0 + x1) / 2, (z0 + z1) / 2, x1 - x0, z1 - z0)


def make_board(variant, m, emblem):
    c = m["colours"]
    im = Image.new("RGBA", (W * SS, H * SS), (*c["field"], 255))
    d = ImageDraw.Draw(im)
    # the ground: a double pinstripe, the shooter lane a shade darker with its centre line
    d.rounded_rectangle((7 * SS, 7 * SS, (W - 7) * SS, (H - 7) * SS), radius=50 * SS, outline=blend(c["art"], c["field"], 0.38), width=2 * SS)
    d.rounded_rectangle((11 * SS, 11 * SS, (W - 11) * SS, (H - 11) * SS), radius=47 * SS, outline=blend(c["trim"], c["field"], 0.22), width=SS)
    d.rectangle(box_world(0.647, -0.653, 0.041, 1.356), fill=blend(c["field"], c["art"], 0.20))
    line_m(d, [(0.625, 0.030), (0.625, -1.08)], blend(c["ink"], c["field"], 0.42), 0.0012)
    rng = random.Random(560 + len(variant))
    if variant == "acorn":
        for x in (0.041, 0.580):
            for z in (-0.2, -0.4, -0.57, -0.8, -1.0):
                ellipse_m(d, x, z, 0.009, 0.021, fill=blend(c["plastic"], c["field"], 0.68))
                line_m(d, [(x, z - 0.020), (x, z + 0.023)], blend(c["art"], c["field"], 0.75), 0.0008)
        # the sunburst behind the bumpers
        bx = sum(b["centre"][0] for b in m["bumpers"]) / len(m["bumpers"])
        bz = sum(b["centre"][1] for b in m["bumpers"]) / len(m["bumpers"])
        for i in range(28):
            a = 2 * math.pi * i / 28
            line_m(d, [(bx + 0.050 * math.cos(a), bz + 0.050 * math.sin(a)), (bx + 0.195 * math.cos(a), bz + 0.195 * math.sin(a))],
                   blend(c["trim"], c["field"], 0.50), 0.0015)
        for r in (0.078, 0.143, 0.192):
            ellipse_m(d, bx, bz, r, r, outline=blend(c["art"], c["field"], 0.73), width=0.7)
        paste_emblem(im, emblem, 0.333, -0.659, 0.248)
        d = ImageDraw.Draw(im)
        # the bonus cartouche round THE HOARD and the 2X 3X 5X lamps and their words
        cx, cz, w, h = bounds(m, ("hoard_", "bonus_"), ("THE HOARD", "2X", "3X", "5X"))
        d.rounded_rectangle(box_world(cx, cz, w, h), radius=9 * SS, fill=blend(c["field"], c["cap"], 0.17),
                            outline=blend(c["art"], c["field"], 0.45), width=SS)
        for x in (cx - w / 2 - 0.035, cx + w / 2 + 0.035):
            acorn_glyph(d, x, cz + h * 0.25, 0.040, c)
        for x in (0.1722, 0.448):  # brackets round the side standups
            ellipse_m(d, x, -0.815, 0.044, 0.056, outline=blend(c["art"], c["field"], 0.55), width=0.8)
        acorn_glyph(d, 0.30, -1.292, 0.043, c)
    elif variant == "rodent":
        # heat tracks under the wire
        for off in (0, 0.016, 0.032):
            pts = [(0.08 + off, -0.58), (0.12 + off, -0.83), (0.19 + off, -1.09), (0.31, -1.27 + off), (0.49 - off, -1.10),
                   (0.57 - off, -0.88), (0.58 - off, -0.43)]
            line_m(d, pts, blend(c["ink"], c["field"], 0.68), 0.002)
        for _ in range(26):
            x, z = rng.uniform(0.04, 0.58), rng.uniform(-1.30, -0.20)
            line_m(d, [(x, z + 0.010), (x + 0.003, z - 0.018)], blend(c["plastic"], c["field"], 0.80), 0.0010)
        paste_emblem(im, emblem, 0.333, -1.148, 0.257)
        d = ImageDraw.Draw(im)
        # the heat meter's enclosure round its lamps
        cx, cz, w, h = bounds(m, ("heat_", "feral", "rabid", "super"))
        d.rounded_rectangle(box_world(m["xc"], cz, 0.055, h), radius=12 * SS, fill=blend(c["field"], c["art"], 0.56), outline=c["ink"], width=SS)
        for j in range(18):
            z = cz + h / 2 - 0.01 - j * (h - 0.02) / 17
            line_m(d, [(m["xc"] + 0.039, z), (m["xc"] + 0.046 + (j % 3 == 0) * 0.007, z)], blend(c["ink"], c["field"], 0.35), 0.001)
        climb = next(wd for wd in m["words"] if wd["text"] == "CLIMB TO SUPER")
        flame_top = climb["centre"][1] + climb["h"] / 2 + 0.012  # the flames stay below the line
        for x in (0.23, 0.31, 0.39):
            poly_m(d, [(x - 0.026, flame_top + 0.078), (x - 0.016, flame_top + 0.034), (x - 0.005, flame_top + 0.048),
                       (x + 0.008, flame_top), (x + 0.023, flame_top + 0.063), (x + 0.025, flame_top + 0.078)],
                   blend(c["ink"], c["field"], 0.52))
        for h in m["holes"]:
            ellipse_m(d, *h["centre"], h["r"] + 0.009, h["r"] + 0.009, outline=c["ink"], width=1)
    else:
        for _ in range(72):
            x, z = rng.uniform(0.028, 0.595), rng.uniform(-1.33, -0.16)
            r = rng.choice([0.0007, 0.001, 0.0014])
            ellipse_m(d, x, z, r, r, fill=blend(c["ink"], c["field"], 0.50))
        for rx, rz in ((0.25, 0.355), (0.265, 0.365), (0.223, 0.30)):
            d.arc(box_world(m["xc"], -0.978, rx * 2, rz * 2), 185, 355, fill=blend(c["plastic"], c["field"], 0.42), width=SS)
        paste_emblem(im, emblem, 0.310, -1.167, 0.300)
        d = ImageDraw.Draw(im)
        for z in (-0.240, -0.275, -0.305):
            line_m(d, [(0.258, z + 0.010), (m["xc"], z - 0.009), (0.362, z + 0.010)], blend(c["plastic"], c["field"], 0.60), 0.0014)
        # the countdown panel and the combo panel, round their lamps and words
        for panel in (bounds(m, ("count_",), ("3", "2", "1", "LAUNCH")), bounds(m, ("combo_",), ("COMBO",))):
            d.rounded_rectangle(box_world(*panel), radius=5 * SS, fill=blend(c["field"], c["art"], 0.26),
                                outline=blend(c["plastic"], c["field"], 0.35), width=SS)
        for h in m["holes"]:
            x, z = h["centre"]
            ellipse_m(d, x, z, h["r"] + 0.005, h["r"] + 0.005, outline=c["plastic"], width=0.8)
            line_m(d, [(x - 0.013, z + 0.022), (x, z + 0.006), (x + 0.013, z + 0.022)], c["ink"], 0.0016)
    # the bumpers' seats
    for b in m["bumpers"]:
        x, z = b["centre"]
        ellipse_m(d, x, z, b["r"] + 0.007, b["r"] + 0.007, outline=blend(c["art"], c["field"], 0.42), width=1.4)
        ellipse_m(d, x, z, b["r"] + 0.010, b["r"] + 0.010, outline=blend(c["ink"], c["field"], 0.44), width=0.65)
    # the shooter lane's arrows
    for z in (-0.22, -0.37, -0.52, -0.67):
        poly_m(d, [(0.638, z + 0.008), (0.647, z - 0.007), (0.656, z + 0.008), (0.650, z + 0.004), (0.650, z + 0.019),
                   (0.644, z + 0.019), (0.644, z + 0.004)], blend(c["ink"], c["field"], 0.32))
    # a lamp insert ring at every lamp (the game draws the lit lamp on top)
    for lp in m["lamps"]:
        x, z = lp["centre"]
        ellipse_m(d, x, z, LAMP_R, LAMP_R, fill=blend(c["field"], c["cap"], 0.07), outline=blend(c["field"], c["cap"], 0.35), width=1.2)
        ellipse_m(d, x, z, LAMP_R * 0.83, LAMP_R * 0.83, outline=blend(c["art"], c["field"], 0.52), width=0.6)
    # the words, last, each on a quiet underprint
    kind = "serif" if variant == "acorn" else "sans"
    for wd in m["words"]:
        x, z = wd["centre"]
        box = box_world(x, z, wd["w"], wd["h"])
        if len(wd["text"]) > 1:
            under = (box[0] - SS, box[1] - SS, box[2] + SS, box[3] + SS)
            if variant == "acorn":
                d.rectangle(under, fill=blend(c["field"], c["cap"], 0.08))
            else:
                d.rounded_rectangle(under, radius=2 * SS, fill=blend(c["field"], c["art"], 0.55))
        colour = c["art"] if variant == "acorn" else c["cap"] if variant == "rodent" else c["ink"]
        lettering(im, wd["text"], box, colour, kind)
    return im.convert("RGB").resize((W, H), Image.Resampling.LANCZOS)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tables", default=os.path.join(ROOT, "build", "review", "pinball_tables.json"))
    ap.add_argument("--emblems", default=EMBLEMS)
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "art", "pinball", "textures"))
    a = ap.parse_args()
    with open(a.tables) as fh:
        dump = json.load(fh)
    os.makedirs(a.out, exist_ok=True)
    for variant, tid, prefix in MACHINES:
        im = make_board(variant, machine(dump, variant, tid), os.path.join(a.emblems, f"{prefix}_Emblem.png"))
        path = os.path.join(a.out, f"{prefix}_Board.png")
        im.save(path, optimize=True)
        print(f"{prefix}_Board.png {im.size[0]} x {im.size[1]}")


if __name__ == "__main__":
    main()
