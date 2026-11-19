"""tools/review/stack.py: put review renders into one JPEG for docs/renders (system python3 + Pillow).

  python3 -I tools/review/stack.py <out.jpg> [--cols N] [--width PX] [--title TEXT] png[=caption] ...
  python3 -I tools/review/stack.py <out.jpg> --dir build/review/rides     (every front_*.png, then every rear_*.png)

Tiles the PNGs in reading order, --cols to a row (default 1), the whole sheet --width pixels wide (default 1600),
each with its caption underneath when one is given; the JPEG quality steps down until the file is under 400 KiB.
"""
import argparse
import glob
import os

from PIL import Image, ImageDraw, ImageFont


def font(size):
    for path in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf"):
        if os.path.exists(path):
            return ImageFont.truetype(path, size)
    return ImageFont.load_default()


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("out")
    ap.add_argument("items", nargs="*")
    ap.add_argument("--dir", default="")
    ap.add_argument("--cols", type=int, default=1)
    ap.add_argument("--width", type=int, default=1600)
    ap.add_argument("--title", default="")
    args = ap.parse_args()
    items = []
    if args.dir:
        names = sorted(glob.glob(os.path.join(args.dir, "front_*.png"))) + sorted(glob.glob(os.path.join(args.dir, "rear_*.png")))
        items = [(p, "") for p in names]
    for it in args.items:
        path, _, caption = it.partition("=")
        items.append((path, caption))
    if not items:
        raise SystemExit("stack: no images")
    cols = max(1, min(args.cols, len(items)))
    gap = 4
    tw = (args.width - gap * (cols - 1)) // cols
    tiles = []
    for path, caption in items:
        im = Image.open(path).convert("RGB")
        tiles.append((im.resize((tw, round(im.height * tw / im.width)), Image.LANCZOS), caption))
    cap_h = 30 if any(c for _, c in tiles) else 0
    title_h = 40 if args.title else 0
    rows = [tiles[i : i + cols] for i in range(0, len(tiles), cols)]
    heights = [max(t.height for t, _ in r) + cap_h for r in rows]
    sheet = Image.new("RGB", (args.width, title_h + sum(heights) + gap * (len(rows) - 1)), (24, 24, 26))
    draw = ImageDraw.Draw(sheet)
    if args.title:
        draw.text((12, 8), args.title, fill=(240, 240, 240), font=font(22))
    y = title_h
    for r, h in zip(rows, heights):
        for c, (im, caption) in enumerate(r):
            x = c * (tw + gap)
            sheet.paste(im, (x, y))
            if caption:
                draw.text((x + 8, y + im.height + 5), caption, fill=(235, 235, 235), font=font(17))
        y += h + gap
    os.makedirs(os.path.dirname(os.path.abspath(args.out)), exist_ok=True)
    quality = 88
    while True:
        sheet.save(args.out, quality=quality, optimize=True, progressive=True)
        if os.path.getsize(args.out) < 400 * 1024 or quality <= 50:
            break
        quality -= 4
    print(f"stack: {args.out} {sheet.width}x{sheet.height} q{quality} {os.path.getsize(args.out) // 1024} KiB")


if __name__ == "__main__":
    main()
