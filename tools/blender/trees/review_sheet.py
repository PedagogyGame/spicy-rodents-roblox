"""Assemble tree review sheets from build_trees.py renders (system python3 with Pillow).

  python3 -I tools/blender/trees/review_sheet.py --out docs/renders/trees/street_sheet.jpg --cols 2 \
      "build/art/trees/renders/tree_000_street.png|BUR OAK" "build/art/trees/renders/tree_001_street.png|AMERICAN ELM" ...

Every item is "image path|label"; the cells are laid out row by row, `--cols` to a row, each cell
`--width / cols` wide and as tall as the first image's aspect asks. The sheet is `--width` px wide
(1600) and saved as a JPEG whose quality is lowered until it is under `--max-kb` (400).
A label that starts with "BEFORE" or "AFTER" gets a coloured tag, so pairs read at a glance.
"""
import argparse
import io
import os

from PIL import Image, ImageDraw, ImageFont


def font(size):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", "/usr/share/fonts/dejavu/DejaVuSans-Bold.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def save_under(img, path, max_kb, q0=90):
    os.makedirs(os.path.dirname(os.path.abspath(path)) or ".", exist_ok=True)
    q = q0
    while True:
        buf = io.BytesIO()
        img.save(buf, "JPEG", quality=q, optimize=True, progressive=True)
        if buf.tell() <= max_kb * 1024 or q <= 40:
            break
        q -= 4
    with open(path, "wb") as fh:
        fh.write(buf.getvalue())
    return q, buf.tell()


def sheet(items, out, cols=2, width=1600, max_kb=400, title=None):
    cw = width // cols
    first = Image.open(items[0][0])
    ch = round(cw * first.height / first.width)
    rows = (len(items) + cols - 1) // cols
    top = 44 if title else 0
    im = Image.new("RGB", (cw * cols, top + ch * rows), (24, 26, 28))
    dr = ImageDraw.Draw(im)
    f1, f2 = font(max(15, cw // 44)), font(24)
    if title:
        dr.text((14, 9), title, fill=(236, 236, 230), font=f2)
    for i, (path, label) in enumerate(items):
        x, y = (i % cols) * cw, top + (i // cols) * ch
        if os.path.exists(path):
            cell = Image.open(path).convert("RGB")
            if cell.size != (cw, ch):
                cell = cell.resize((cw, ch), Image.LANCZOS)
            im.paste(cell, (x, y))
        tag = label.split(" ")[0] if label.startswith(("BEFORE", "AFTER")) else None
        tx = x + 10
        if tag:
            col = (150, 60, 50) if tag == "BEFORE" else (50, 120, 60)
            w = dr.textlength(tag, font=f1)
            dr.rectangle([x + 8, y + 7, x + 18 + w, y + 13 + f1.size], fill=col)
            dr.text((x + 13, y + 9), tag, fill=(255, 255, 255), font=f1)
            tx = x + 26 + w
            label = label[len(tag):].strip()
        dr.text((tx + 1, y + 10), label, fill=(0, 0, 0), font=f1)
        dr.text((tx, y + 9), label, fill=(255, 255, 255), font=f1)
    q, size = save_under(im, out, max_kb)
    print(f"{out}: {im.width}x{im.height}, q{q}, {size // 1024} KB")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("items", nargs="+", help='"image|label"')
    ap.add_argument("--out", required=True)
    ap.add_argument("--cols", type=int, default=2)
    ap.add_argument("--width", type=int, default=1600)
    ap.add_argument("--max-kb", type=int, default=400)
    ap.add_argument("--title", default=None)
    a = ap.parse_args()
    items = [(s.split("|", 1) + [""])[:2] for s in a.items]
    sheet(items, a.out, a.cols, a.width, a.max_kb, a.title)


if __name__ == "__main__":
    main()
