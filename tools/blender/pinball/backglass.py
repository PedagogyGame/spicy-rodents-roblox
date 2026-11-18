"""The three pinball backglass pictures (854 x 1024, the backbox's face, 0.689 x 0.826 m), recomposed from
ChatGPT's own emblems (docs/reference/pinball_art/Source_Project/build/source/art_originals/*_Emblem.png).

  python3 -I tools/blender/pinball/backglass.py [--out build/art/pinball/textures]

His delivered PNGs dimmed the five text bands and not the gaps between them, which left bright horizontal
stripes across the picture. Here the emblem is dimmed EVENLY (one opacity over the whole picture, on the
machine's dark ground), so the game's lettering (the Backglass's SurfaceGui "Display": Title, Score, Info,
Say, Best, in the bands below; Shared/Minigames/Pinball/Cabinet, the bake's Display lines) stands on a calm
ground everywhere, with the thin frame he drew: the double rounded border in the trim and ink colours, a
hairline above each band and the small top and bottom accents. Colours are the bake's THEMES (the dump).
Nothing is written outside --out. Needs Pillow.
"""
import argparse
import json
import os

from PIL import Image, ImageDraw

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
EMBLEMS = os.path.join(ROOT, "docs", "reference", "pinball_art", "Source_Project", "build", "source", "art_originals")
BW, BH = 854, 1024
# the bands the game writes in, as fractions of the height from the top (the bake's Display lines: Title 0.03 +
# 0.2, Score 0.26 + 0.24, Info 0.52 + 0.1, Say 0.64 + 0.16, Best 0.83 + 0.12)
BANDS = {"Title": (0.03, 0.23), "Score": (0.26, 0.50), "Info": (0.52, 0.62), "Say": (0.64, 0.80), "Best": (0.83, 0.95)}
ART_OPACITY = 0.26  # the emblem's strength over the dark ground, the same everywhere
MACHINES = (("acorn", "Acorn"), ("rodent", "Rodent"), ("space", "Space"))


def blend(a, b, t):
    return tuple(round(a[i] * (1 - t) + b[i] * t) for i in range(3))


def make_backglass(theme, emblem):
    body, trim, ink = tuple(theme["body"]), tuple(theme["trim"]), tuple(theme["ink"])
    dark = blend(body, (3, 4, 8), 0.83)
    im = Image.new("RGBA", (BW, BH), (*dark, 255))
    art = Image.open(emblem).convert("RGBA")
    art = art.crop(art.getchannel("A").getbbox())
    scale = min(820 / art.width, 795 / art.height)
    art = art.resize((round(art.width * scale), round(art.height * scale)), Image.Resampling.LANCZOS)
    art.putalpha(art.getchannel("A").point(lambda a: round(a * ART_OPACITY)))
    im.alpha_composite(art, ((BW - art.width) // 2, (BH - art.height) // 2 + 40))
    d = ImageDraw.Draw(im)
    # his thin frame
    d.rounded_rectangle((15, 15, BW - 16, BH - 16), radius=37, outline=blend(trim, dark, 0.52), width=2)
    d.rounded_rectangle((23, 23, BW - 24, BH - 24), radius=30, outline=blend(ink, dark, 0.76), width=1)
    for top, _ in BANDS.values():
        y = round(top * BH) - 5
        d.line((85, y, BW - 85, y), fill=blend(trim, dark, 0.74), width=1)
    for y in (11, BH - 15):
        d.line((BW // 2 - 58, y, BW // 2 + 58, y), fill=blend(ink, dark, 0.38), width=2)
        d.ellipse((BW // 2 - 3, y - 3, BW // 2 + 3, y + 3), fill=blend(ink, dark, 0.35))
    return im.convert("RGB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--tables", default=os.path.join(ROOT, "build", "review", "pinball_tables.json"))
    ap.add_argument("--emblems", default=EMBLEMS)
    ap.add_argument("--out", default=os.path.join(ROOT, "build", "art", "pinball", "textures"))
    a = ap.parse_args()
    with open(a.tables) as fh:
        themes = json.load(fh)["themes"]
    os.makedirs(a.out, exist_ok=True)
    for variant, prefix in MACHINES:
        im = make_backglass(themes[variant], os.path.join(a.emblems, f"{prefix}_Emblem.png"))
        im.save(os.path.join(a.out, f"{prefix}_Backglass.png"), optimize=True)
        print(f"{prefix}_Backglass.png {im.size[0]} x {im.size[1]}")


if __name__ == "__main__":
    main()
