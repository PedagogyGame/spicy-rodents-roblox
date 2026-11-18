"""Contact sheets for the hero renders (system python3 with Pillow; the bpy venv has none).

  python3 -I tools/blender/heroes/sheets.py poses --dir <render dir> --tag squirrel --out <png>
  python3 -I tools/blender/heroes/sheets.py turntable --dir <render dir> --tag squirrel --out <png>
  python3 -I tools/blender/heroes/sheets.py motion --manifest <frames dir>/manifest.json --out <base>
  python3 -I tools/blender/heroes/sheets.py pairs --out <jpg> --title <text> [--note <text>] \
      --pair "<label>|<before png>|<after png>" [--pair ...]      # before and after, one row per pair
  python3 -I tools/blender/heroes/sheets.py stack --out <jpg> --title <text> [--note <text>] \
      --strip "<tag>|<label>|<image>" [--strip ...]               # whole strips, one above the other

poses: one row per clip (<tag>_pose_<Clip>_<k>.png, k = key pose index), labelled with the clip name
and the key's time; turntable: the <tag>_turntable_NN.png frames in a grid (4 per row); motion: the
strips of one take from render_motion.py, <base>_back.jpg (the play camera) and <base>_side.jpg, each
1600 px wide and at most 400 KB: the take's frames in order, eight to a row, then three frames larger;
stack: finished strips (a take before and after a change) one directly above the other, each under a band
with its tag (BEFORE, AFTER) and what it is, 1600 px wide and at most 400 KB.
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


MOTION_W = 1600
MOTION_MAX_BYTES = 400 * 1000
MOTION_BG = (22, 24, 28)


def wrap(dr, text, fnt, width):
    lines, line = [], ""
    for word in text.split():
        trial = (line + " " + word).strip()
        if dr.textlength(trial, font=fnt) <= width or not line:
            line = trial
        else:
            lines.append(line)
            line = word
    if line:
        lines.append(line)
    return lines


def save_under(sheet, out, limit=MOTION_MAX_BYTES):
    """JPEG at the best quality that fits the limit."""
    for q in (90, 86, 82, 78, 74, 70, 66, 62, 58, 54, 50, 45, 40):
        sheet.save(out, quality=q, optimize=True, progressive=True)
        if os.path.getsize(out) <= limit:
            return q
    raise SystemExit(f"{out}: over {limit} bytes even at quality 40")


def motion_sheet(man, view, out):
    small = [e for e in man["small"] if view in e]
    large = [e for e in man["large"] if view + "Large" in e]
    if not small:
        return None
    cam = man["camera"]
    strip = man["strip"]
    step_ms = 1000.0 * strip["step"] / man["fps"]
    every = "every frame" if strip["step"] == 1 else f"every {strip['step']} frames"
    head = f"{man['variant']}  /  {man['take']}: {man['title']}"
    span = f"Frames {small[0]['i']} to {small[-1]['i']} of the take at {man['fps']} frames a second, {every} ({step_ms:.0f} ms apart)."
    big_imgs = [Image.open(e[view + "Large"]).convert("RGB") for e in large]
    if view == "back":
        note = (
            f"PLAY CAMERA, from behind: {cam['distance']:.1f} studs from the point it looks at, {cam['elevation']:.2f} rad above it, "
            f"field of view {cam['fov']:g}. Each small picture is the part of a 1920 x 1080 game frame around the body, pixel for pixel; "
            f"the three below are the same view enlarged ({man['largeZoom']:g} times, or as much as the body fits: the factor is under each). "
            f"{span} Ground grid: 1 stud, a heavy line every 5."
        )
    else:
        below = f", {big_imgs[0].width / man['sideView']['w']:.0f} px in the three below" if big_imgs else ""
        note = (
            f"SIDE-ON tracking camera on the body's right (orthographic: one stud is {man['sidePixelsPerStud']:.0f} px in the small "
            f"pictures{below}). {span} Ground grid: 1 stud, a heavy line every 5."
        )
    f_head, f_note, f_lab = font(19), font(13), font(12)
    probe = ImageDraw.Draw(Image.new("RGB", (8, 8)))
    notes = wrap(probe, note, f_note, MOTION_W - 20)
    head_h = 10 + 24 + 17 * len(notes) + 8
    cols = 8
    cell_w = MOTION_W // cols
    sw, sh = Image.open(small[0][view]).size
    lab_h = 30
    rows = (len(small) + cols - 1) // cols
    small_h = rows * (sh + lab_h)
    gap = 6
    big_h = 0
    if big_imgs:
        bw = (MOTION_W - gap * (len(big_imgs) + 1)) // len(big_imgs)
        scale = min(1.0, bw / big_imgs[0].width)
        if scale < 1.0:
            big_imgs = [im.resize((int(im.width * scale), int(im.height * scale)), Image.LANCZOS) for im in big_imgs]
        big_h = big_imgs[0].height + 22 + gap
    sheet = Image.new("RGB", (MOTION_W, head_h + small_h + big_h + 4), MOTION_BG)
    dr = ImageDraw.Draw(sheet)
    dr.text((10, 8), head, fill=(245, 245, 245), font=f_head)
    for k, line in enumerate(notes):
        dr.text((10, 34 + 17 * k), line, fill=(185, 188, 196), font=f_note)
    for k, e in enumerate(small):
        im = Image.open(e[view]).convert("RGB")
        x = (k % cols) * cell_w + (cell_w - sw) // 2
        y = head_h + (k // cols) * (sh + lab_h)
        sheet.paste(im, (x, y))
        dr.text((x + 2, y + sh + 1), f"{e['t']:.3f} s   {e['speed']:.0f} st/s", fill=(225, 225, 230), font=f_lab)
        dr.text((x + 2, y + sh + 14), f"{e['clip']} {e['clipTime']:.2f}  {e['mode']}", fill=(160, 164, 172), font=f_lab)
    if big_imgs:
        y = head_h + small_h
        total = sum(im.width for im in big_imgs) + gap * (len(big_imgs) - 1)
        x = (MOTION_W - total) // 2
        for im, e in zip(big_imgs, large):
            sheet.paste(im, (x, y))
            label = f"{e['t']:.3f} s   {e['clip']} {e['clipTime']:.2f}   {e['speed']:.0f} st/s"
            if view == "back":
                label += f"   x{e.get('backLargeZoom', man['largeZoom']):g}"
            dr.text((x + 4, y + im.height + 3), label, fill=(225, 225, 230), font=f_note)
            x += im.width + gap
    q = save_under(sheet, out)
    return out, sheet.size, q, os.path.getsize(out)


def motion(manifest, base):
    with open(manifest) as fh:
        man = json.load(fh)
    done = []
    for view in ("back", "side"):
        r = motion_sheet(man, view, f"{base}_{view}.jpg")
        if r:
            done.append(f"{r[0]} {r[1][0]}x{r[1][1]} q{r[2]} {r[3] // 1000} KB")
    return "\n".join(done)


def pairs(out, title, note, rows, left="BEFORE", right="AFTER"):
    """Before and after, side by side, one row per view: rows = [(label, before png, after png)]. At most
    1600 px wide and 400 KB, as the motion strips."""
    gap = 8
    cell_w = (MOTION_W - gap * 3) // 2
    f_head, f_note, f_lab, f_tag = font(19), font(13), font(14), font(15)
    probe = ImageDraw.Draw(Image.new("RGB", (8, 8)))
    notes = wrap(probe, note, f_note, MOTION_W - 20) if note else []
    head_h = 10 + 24 + 17 * len(notes) + 8
    imgs = []
    for label, a, b in rows:
        pair = []
        for p in (a, b):
            im = Image.open(p).convert("RGB")
            if im.width != cell_w:
                im = im.resize((cell_w, round(im.height * cell_w / im.width)), Image.LANCZOS)
            pair.append(im)
        imgs.append((label, pair))
    lab_h = 24
    total = head_h + sum(max(p[0].height, p[1].height) + lab_h + gap for _l, p in imgs)
    sheet = Image.new("RGB", (MOTION_W, total), MOTION_BG)
    dr = ImageDraw.Draw(sheet)
    dr.text((10, 8), title, fill=(245, 245, 245), font=f_head)
    for k, line in enumerate(notes):
        dr.text((10, 34 + 17 * k), line, fill=(185, 188, 196), font=f_note)
    y = head_h
    for label, pair in imgs:
        dr.text((gap + 2, y + 3), label, fill=(225, 225, 230), font=f_lab)
        y += lab_h
        for k, (im, tag) in enumerate(zip(pair, (left, right))):
            x = gap + k * (cell_w + gap)
            sheet.paste(im, (x, y))
            dr.rectangle((x + 6, y + 6, x + 12 + dr.textlength(tag, font=f_tag), y + 28), fill=(22, 24, 28))
            dr.text((x + 9, y + 8), tag, fill=(245, 245, 245), font=f_tag)
        y += max(pair[0].height, pair[1].height) + gap
    q = save_under(sheet, out)
    return f"{out} {sheet.size[0]}x{sheet.size[1]} q{q} {os.path.getsize(out) // 1000} KB"


def stack(out, title, note, rows):
    """Whole strips one above the other: rows = [(tag, label, image)]. Each strip's own heading (the first
    lines of a motion strip say the same for both) stays, under a band that says which it is."""
    f_head, f_note, f_lab, f_tag = font(19), font(13), font(14), font(16)
    probe = ImageDraw.Draw(Image.new("RGB", (8, 8)))
    notes = wrap(probe, note, f_note, MOTION_W - 20) if note else []
    head_h = 10 + 24 + 17 * len(notes) + 8
    band_h = 30
    imgs = []
    for tag, label, path in rows:
        im = Image.open(path).convert("RGB")
        if im.width != MOTION_W:
            im = im.resize((MOTION_W, round(im.height * MOTION_W / im.width)), Image.LANCZOS)
        imgs.append((tag, label, im))
    sheet = Image.new("RGB", (MOTION_W, head_h + sum(band_h + im.height for _t, _l, im in imgs)), MOTION_BG)
    dr = ImageDraw.Draw(sheet)
    dr.text((10, 8), title, fill=(245, 245, 245), font=f_head)
    for k, line in enumerate(notes):
        dr.text((10, 34 + 17 * k), line, fill=(185, 188, 196), font=f_note)
    y = head_h
    for tag, label, im in imgs:
        dr.rectangle((0, y, MOTION_W, y + band_h), fill=(52, 56, 66))
        dr.text((10, y + 5), tag, fill=(255, 214, 120), font=f_tag)
        dr.text((22 + dr.textlength(tag, font=f_tag), y + 7), label, fill=(232, 232, 236), font=f_lab)
        sheet.paste(im, (0, y + band_h))
        y += band_h + im.height
    q = save_under(sheet, out)
    return f"{out} {sheet.size[0]}x{sheet.size[1]} q{q} {os.path.getsize(out) // 1000} KB"


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("kind", choices=["poses", "turntable", "motion", "pairs", "stack"])
    ap.add_argument("--strip", action="append", default=[], help="stack: 'tag|label|image', once per strip, top first")
    ap.add_argument("--title", default="")
    ap.add_argument("--note", default="")
    ap.add_argument("--pair", action="append", default=[], help="pairs: 'label|before.png|after.png', once per row")
    ap.add_argument("--dir")
    ap.add_argument("--tag")
    ap.add_argument("--out", required=True)
    ap.add_argument("--meta", default=None, help="the build's report.json (clip order, durations, key frames)")
    ap.add_argument("--scale", type=float, default=1.0)
    ap.add_argument("--manifest", default=None, help="motion: the manifest.json render_motion.py wrote")
    a = ap.parse_args()
    if a.kind == "motion":
        print(motion(a.manifest, a.out))
        raise SystemExit(0)
    if a.kind == "pairs":
        print(pairs(a.out, a.title, a.note, [tuple(p.split("|")) for p in a.pair]))
        raise SystemExit(0)
    if a.kind == "stack":
        print(stack(a.out, a.title, a.note, [tuple(p.split("|")) for p in a.strip]))
        raise SystemExit(0)
    meta = None
    if a.meta and os.path.exists(a.meta):
        with open(a.meta) as fh:
            meta = json.load(fh)
    if a.kind == "poses":
        print(poses(a.dir, a.tag, a.out, a.scale, meta))
    else:
        print(turntable(a.dir, a.tag, a.out, scale=a.scale))
