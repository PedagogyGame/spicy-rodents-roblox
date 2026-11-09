"""S12: assemble the turntable frames into a contact sheet, downscale frames for the HTML page.

  python3 -I tools/blender/contact_sheet.py --frames build/blender/cycles --out docs/renders \
      --name squirrel_turntable --thumb 192 --page-frame 256

Uses Pillow from the system interpreter (the bpy venv has none). Writes:
  <out>/<name>_sheet.png            6 x 6 grid of thumbnails
  <out>/<name>/f_NN.png             page frames (page-frame px)
  <out>/<name>_still_NN.png         three hero stills at full size (frames 0, 12, 24)
  <out>/<name>.html                 the turntable page (drag or auto-rotate)
"""
import argparse
import glob
import json
import math
import os

from PIL import Image, ImageDraw


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--frames", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--name", default="squirrel_turntable")
    ap.add_argument("--thumb", type=int, default=128)
    ap.add_argument("--page-frame", type=int, default=256)
    ap.add_argument("--timing", default=None)
    args = ap.parse_args()
    files = sorted(glob.glob(os.path.join(args.frames, "frame_*.png")))
    if not files:
        raise SystemExit(f"no frames in {args.frames}")
    os.makedirs(args.out, exist_ok=True)
    n = len(files)
    cols = int(math.ceil(math.sqrt(n)))
    rows = int(math.ceil(n / cols))
    sheet = Image.new("RGB", (cols * args.thumb, rows * args.thumb), (30, 30, 34))
    draw = ImageDraw.Draw(sheet)
    page_dir = os.path.join(args.out, args.name)
    os.makedirs(page_dir, exist_ok=True)
    for i, f in enumerate(files):
        im = Image.open(f).convert("RGB")
        th = im.resize((args.thumb, args.thumb), Image.LANCZOS)
        x, y = (i % cols) * args.thumb, (i // cols) * args.thumb
        sheet.paste(th, (x, y))
        draw.text((x + 4, y + 2), f"{i * 360 // n:3d}°", fill=(240, 240, 240))
        pf = im.resize((args.page_frame, args.page_frame), Image.LANCZOS)
        pf.save(os.path.join(page_dir, f"f_{i:02d}.png"), optimize=True)
        if i in (0, n // 3, 2 * n // 3):
            im.save(os.path.join(args.out, f"{args.name}_still_{i:02d}.png"), optimize=True)
    sheet.save(os.path.join(args.out, f"{args.name}_sheet.png"), optimize=True)

    timing = {}
    if args.timing and os.path.exists(args.timing):
        with open(args.timing) as fh:
            timing = json.load(fh)
    caption = ""
    if timing.get("frames"):
        caption = (
            f"{timing.get('engine')} CPU, {timing.get('samples')} samples, {timing.get('res')} px, "
            f"{timing.get('threads')} threads: {timing.get('mean_s')} s per frame "
            f"({timing.get('minutes_per_frame')} min), {len(timing['frames'])} frames"
        )
    html = f"""<!doctype html>
<html lang="en"><head><meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Squirrel turntable (S12)</title>
<style>
  :root {{ --bg: #1e1e22; --fg: #e8e8ea; --muted: #9a9aa2; }}
  body {{ margin: 0; background: var(--bg); color: var(--fg); font: 15px/1.4 system-ui, sans-serif; }}
  main {{ max-width: 640px; margin: 0 auto; padding: 16px; }}
  h1 {{ font-size: 20px; margin: 0 0 4px; }}
  p {{ color: var(--muted); margin: 0 0 12px; }}
  #stage {{ width: 100%; max-width: {args.page_frame}px; aspect-ratio: 1; margin: 0 auto; display: block;
            border-radius: 8px; cursor: ew-resize; user-select: none; touch-action: none; image-rendering: auto; }}
  .row {{ display: flex; gap: 12px; align-items: center; justify-content: center; margin: 12px 0; }}
  button {{ background: #33333a; color: var(--fg); border: 1px solid #55555e; border-radius: 6px; padding: 6px 12px; }}
  img.sheet {{ width: 100%; height: auto; border-radius: 8px; }}
</style></head>
<body><main>
<h1>Test squirrel turntable</h1>
<p>{caption or "Headless render from tools/blender (S12)."} Drag the image or let it spin.</p>
<img id="stage" src="{args.name}/f_00.png" alt="turntable frame" draggable="false">
<div class="row"><button id="toggle">Pause</button><span id="deg">0°</span></div>
<p>Contact sheet (all {n} frames):</p>
<img class="sheet" src="{args.name}_sheet.png" alt="contact sheet">
</main>
<script>
  const n = {n}, img = document.getElementById('stage'), deg = document.getElementById('deg');
  const frames = Array.from({{length: n}}, (_, i) => `{args.name}/f_${{String(i).padStart(2, '0')}}.png`);
  frames.forEach(src => {{ const p = new Image(); p.src = src; }});
  let i = 0, playing = true, dragX = null, dragStart = 0;
  function show(k) {{ i = ((k % n) + n) % n; img.src = frames[i]; deg.textContent = Math.round(i * 360 / n) + '°'; }}
  setInterval(() => {{ if (playing && dragX === null) show(i + 1); }}, 120);
  document.getElementById('toggle').onclick = e => {{ playing = !playing; e.target.textContent = playing ? 'Pause' : 'Play'; }};
  img.addEventListener('pointerdown', e => {{ dragX = e.clientX; dragStart = i; img.setPointerCapture(e.pointerId); }});
  img.addEventListener('pointermove', e => {{ if (dragX !== null) show(dragStart + Math.round((e.clientX - dragX) / 8)); }});
  img.addEventListener('pointerup', () => {{ dragX = null; }});
  img.addEventListener('pointercancel', () => {{ dragX = null; }});
</script></body></html>
"""
    with open(os.path.join(args.out, f"{args.name}.html"), "w") as fh:
        fh.write(html)
    total = sum(os.path.getsize(p) for p in glob.glob(os.path.join(args.out, "**", "*.png"), recursive=True))
    print(json.dumps({"frames": n, "sheet": f"{args.name}_sheet.png", "png_bytes_under_out": total}))


if __name__ == "__main__":
    main()
