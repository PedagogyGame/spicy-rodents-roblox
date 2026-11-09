"""Contact sheets for the hero renders (system python3 with Pillow; the bpy venv has none).

  python3 -I tools/blender/heroes/sheets.py poses --dir <render dir> --tag squirrel --out <png>
  python3 -I tools/blender/heroes/sheets.py turntable --dir <render dir> --tag squirrel --out <png>

poses: one row per clip (<tag>_pose_<Clip>_<k>.png, k = key pose index), labelled with the clip name
and the key's time; turntable: the <tag>_turntable_NN.png frames in a grid (4 per row).
"""
import argparse
import glob
import json
import os
import re

from PIL import Image, ImageDraw, ImageFont


def font(size):
    for p in ("/usr/share/fonts/truetype/dejavu/DejaVuSans.ttf", "/usr/share/fonts/dejavu/DejaVuSans.ttf"):
        if os.path.exists(p):
            return ImageFont.truetype(p, size)
    return ImageFont.load_default()


def poses(d, tag, out, scale=1.0, meta=None):
    files = glob.glob(os.path.join(d, f"{tag}_pose_*_*.png"))
    rows = {}
    for f in files:
        m = re.match(rf"{re.escape(tag)}_pose_(.+)_(\d+)\.png$", os.path.basename(f))
        if m:
            rows.setdefault(m.group(1), {})[int(m.group(2))] = f
    order = list((meta or {}).get("clips", {}).keys()) or sorted(rows)
    order = [c for c in order if c in rows]
    if not order:
        raise SystemExit("no pose renders")
    sample = Image.open(next(iter(rows[order[0]].values())))
    w, h = int(sample.width * scale), int(sample.height * scale)
    ncol = max(len(v) for v in rows.values())
    label_w = 150
    sheet = Image.new("RGB", (label_w + ncol * w, len(order) * h), (24, 24, 28))
    dr = ImageDraw.Draw(sheet)
    f1, f2 = font(20), font(14)
    for r, clip in enumerate(order):
        info = (meta or {}).get("clips", {}).get(clip, {})
        dr.text((10, r * h + 10), clip, fill=(240, 240, 240), font=f1)
        if info.get("brief") and info["brief"].lower() != clip.lower():
            dr.text((10, r * h + 36), info["brief"], fill=(180, 180, 190), font=f2)
        if info.get("duration"):
            dr.text((10, r * h + 56), f"{info['duration']:.2f} s{' loop' if info.get('loop') else ''}", fill=(180, 180, 190), font=f2)
        keys = info.get("key_frames", [])
        for c, k in enumerate(sorted(rows[clip])):
            im = Image.open(rows[clip][k]).convert("RGB")
            if scale != 1.0:
                im = im.resize((w, h), Image.LANCZOS)
            x = label_w + c * w
            sheet.paste(im, (x, r * h))
            if c < len(keys):
                dr.text((x + 6, r * h + 4), f"f{keys[c] - 1}  {(keys[c] - 1) / 30:.2f}s", fill=(250, 250, 250), font=f2)
    sheet.save(out, quality=86, optimize=True) if out.endswith(".jpg") else sheet.save(out, optimize=True)
    return out


def turntable(d, tag, out, cols=4, scale=0.5):
    files = sorted(glob.glob(os.path.join(d, f"{tag}_turntable_*.png")))
    if not files:
        raise SystemExit("no turntable frames")
    sample = Image.open(files[0])
    w, h = int(sample.width * scale), int(sample.height * scale)
    rows = (len(files) + cols - 1) // cols
    sheet = Image.new("RGB", (cols * w, rows * h), (24, 24, 28))
    dr = ImageDraw.Draw(sheet)
    for i, f in enumerate(files):
        im = Image.open(f).convert("RGB").resize((w, h), Image.LANCZOS)
        sheet.paste(im, ((i % cols) * w, (i // cols) * h))
        dr.text(((i % cols) * w + 6, (i // cols) * h + 4), f"{i * 360 // len(files)} deg", fill=(240, 240, 240), font=font(14))
    sheet.save(out, quality=86, optimize=True) if out.endswith(".jpg") else sheet.save(out, optimize=True)
    return out


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("kind", choices=["poses", "turntable"])
    ap.add_argument("--dir", required=True)
    ap.add_argument("--tag", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--meta", default=None, help="the build's report.json (clip order, durations, key frames)")
    ap.add_argument("--scale", type=float, default=1.0)
    a = ap.parse_args()
    meta = None
    if a.meta and os.path.exists(a.meta):
        with open(a.meta) as fh:
            meta = json.load(fh)
    if a.kind == "poses":
        print(poses(a.dir, a.tag, a.out, a.scale, meta))
    else:
        print(turntable(a.dir, a.tag, a.out, scale=a.scale))
