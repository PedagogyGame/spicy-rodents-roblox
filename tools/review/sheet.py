"""tools/review/sheet.py: tile the review renders into one contact sheet (system python3 + Pillow).

  python3 -I tools/review/sheet.py --dir build/review [--timing build/review/timing.json] [--cols 3] [--tile 480]

Reads the views listed in timing.json (render order), or every *.png in --dir, and writes
<dir>/contact_sheet.png: each render at --tile px wide with its name and render time underneath.
"""
import argparse
import glob
import json
import os

from PIL import Image, ImageDraw


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dir", default="build/review")
    ap.add_argument("--timing", default=None)
    ap.add_argument("--cols", type=int, default=3)
    ap.add_argument("--tile", type=int, default=480)
    args = ap.parse_args()
    items = []
    if args.timing and os.path.exists(args.timing):
        with open(args.timing) as fh:
            for v in json.load(fh)["views"]:
                if os.path.exists(v["png"]):
                    items.append((v["png"], f"{v['name']}  ({v['seconds']:.0f}s)"))
    else:
        for p in sorted(glob.glob(os.path.join(args.dir, "*.png"))):
            if not p.endswith("contact_sheet.png"):
                items.append((p, os.path.splitext(os.path.basename(p))[0]))
    if not items:
        print("sheet: no renders found")
        return 1
    first = Image.open(items[0][0])
    tw = args.tile
    th = round(first.height * tw / first.width)
    label_h = 18
    cols = min(args.cols, len(items))
    rows = (len(items) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * tw, rows * (th + label_h)), (24, 24, 24))
    draw = ImageDraw.Draw(sheet)
    for i, (path, label) in enumerate(items):
        im = Image.open(path).convert("RGB").resize((tw, th), Image.LANCZOS)
        x, y = (i % cols) * tw, (i // cols) * (th + label_h)
        sheet.paste(im, (x, y))
        draw.text((x + 6, y + th + 3), label, fill=(230, 230, 230))
    out = os.path.join(args.dir, "contact_sheet.png")
    sheet.save(out, optimize=True)
    print(f"sheet: {len(items)} renders -> {os.path.abspath(out)}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
