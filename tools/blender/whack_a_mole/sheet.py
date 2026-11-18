"""Put tools/blender/whack_a_mole/compare.py's pictures side by side, labelled (system python3 + Pillow).

  python3 -I tools/blender/whack_a_mole/sheet.py [--build build/art/whack_a_mole] \
      [--out docs/renders/minigames/whack_a_mole]

For each view: his GLB on the left, the game version on the right, each with its triangle and piece count (the
game's from manifest.json), written as <out>/art_<view>.jpg (JPEG, quality 88: a picture to look at, kept light). Lettering is not in the game's meshes: the game
writes it on the cabinet as text (the bake's SurfaceGuis), so the right-hand pictures show the cabinet bare.
"""
import argparse
import json
import os

from PIL import Image, ImageDraw, ImageFont

ROOT = os.path.abspath(os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", ".."))
BOLD = "/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf"
PLAIN = "/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf"
VIEWS = ["01_preview_angle", "02_player_view", "03_moles_close"]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--build", default=os.path.join(ROOT, "build", "art", "whack_a_mole"))
    ap.add_argument("--out", default=os.path.join(ROOT, "docs", "renders", "minigames", "whack_a_mole"))
    a = ap.parse_args()
    with open(os.path.join(a.build, "manifest.json")) as fh:
        m = json.load(fh)
    his_line = f"His GLB: {m['sourceTris'] + m['leftOut']['lettering']:,} triangles, 246 pieces"
    game_line = (f"Game version: {m['total']:,} triangles, {len(m['pieces'])} pieces "
                 f"(shell {m['groups']['shell']:,}, moles {m['groups']['moles']:,}, mallet {m['groups']['mallet']:,})")
    os.makedirs(a.out, exist_ok=True)
    big, small = ImageFont.truetype(BOLD, 26), ImageFont.truetype(PLAIN, 18)
    for view in VIEWS:
        left = Image.open(os.path.join(a.build, "compare", f"{view}_his.png")).convert("RGB")
        right = Image.open(os.path.join(a.build, "compare", f"{view}_game.png")).convert("RGB")
        w, h = left.size
        sheet = Image.new("RGB", (2 * w + 30, h + 90), (246, 242, 232))
        sheet.paste(left, (10, 80))
        sheet.paste(right, (w + 20, 80))
        d = ImageDraw.Draw(sheet)
        d.text((14, 10), his_line, font=big, fill=(34, 36, 40))
        d.text((w + 24, 10), game_line.split(" (")[0], font=big, fill=(34, 36, 40))
        d.text((14, 46), "as delivered, with its lettering in the mesh", font=small, fill=(70, 70, 70))
        d.text((w + 24, 46), "(" + game_line.split(" (")[1] + "; lettering is the game's own text",
               font=small, fill=(70, 70, 70))
        path = os.path.join(a.out, f"art_{view}.jpg")
        sheet.save(path, quality=88, optimize=True)
        print(f"sheet: {path}")


if __name__ == "__main__":
    main()
