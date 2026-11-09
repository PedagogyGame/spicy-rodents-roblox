"""Assemble the tree review sheet from build_trees.py renders (system python3 with Pillow).

  python3 -I tools/blender/trees/review_sheet.py --renders build/art/trees/renders --out docs/renders/trees

Writes <out>/tree_review_sheet.jpg (6 trees x street / below-canopy, 480x270 cells with labels),
<out>/tree_NNN_<view>.jpg (full 960x540 stills, JPEG q88 to keep the repo small) and copies any
debug render (bark see-through, red route rails, yellow feet lines).
"""
import argparse
import glob
import json
import os

from PIL import Image, ImageDraw, ImageFont

REVIEW = [0, 1, 2, 40, 85, 77]


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--renders", default="build/art/trees/renders")
    ap.add_argument("--build", default="build/art/trees")
    ap.add_argument("--out", default="docs/renders/trees")
    ap.add_argument("--ids", default=",".join(str(i) for i in REVIEW))
    a = ap.parse_args()
    os.makedirs(a.out, exist_ok=True)
    ids = [int(x) for x in a.ids.split(",")]
    cw, chh = 480, 270
    views = ["street", "below"]
    sheet = Image.new("RGB", (cw * 2, chh * len(ids) + 0), (24, 26, 28))
    draw = ImageDraw.Draw(sheet)
    try:
        font = ImageFont.truetype("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 15)
    except Exception:
        font = ImageFont.load_default()
    for r, i in enumerate(ids):
        info = {}
        jp = os.path.join(a.build, f"tree_{i:03d}.json")
        if os.path.exists(jp):
            with open(jp) as fh:
                info = json.load(fh)
        for c, v in enumerate(views):
            p = os.path.join(a.renders, f"tree_{i:03d}_{v}.png")
            if not os.path.exists(p):
                continue
            im = Image.open(p).convert("RGB")
            im.save(os.path.join(a.out, f"tree_{i:03d}_{v}.jpg"), quality=88, optimize=True)
            sheet.paste(im.resize((cw, chh), Image.LANCZOS), (c * cw, r * chh))
            tris = info.get("tris", {}).get("total")
            label = f"{i:03d} {info.get('label', '')}  {v}" + (f"  {tris} tris" if tris and c == 0 else "")
            draw.text((c * cw + 9, r * chh + 7), label, fill=(0, 0, 0), font=font)
            draw.text((c * cw + 8, r * chh + 6), label, fill=(255, 255, 255), font=font)
    sheet.save(os.path.join(a.out, "tree_review_sheet.jpg"), quality=88, optimize=True)
    for p in glob.glob(os.path.join(a.renders, "tree_*_debug.png")):
        Image.open(p).convert("RGB").save(os.path.join(a.out, os.path.basename(p)[:-4] + ".jpg"), quality=90, optimize=True)
    print(os.path.join(a.out, "tree_review_sheet.jpg"))


if __name__ == "__main__":
    main()
