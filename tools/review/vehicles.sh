#!/usr/bin/env bash
# tools/review/vehicles.sh: one picture of vehicles from the front and the rear three-quarter, offline
# (tools/review/vehicles.luau -> scene; tools/review/render.py -> PNGs; Pillow stacks them into a JPEG:
# the front views of every row, then the rear views).
# Usage: tools/review/vehicles.sh <out.jpg> [--rows N] [kind[:#rrggbb] ...]   (default: all ten kinds, two rows)
# Env:   REVIEW_PY (bpy interpreter), REVIEW_OUT (work directory, default build/review/vehicles),
#        REVIEW_SAMPLES (default 48), REVIEW_RES (one view, default 1600x620)
# About 1.5 minutes per view on 2 shared CPUs; the render runs under nice.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.cargo/bin:$HOME/.rokit/bin:$PATH"
PY="${REVIEW_PY:-/root/.cache/spicy-rodents/venv/bin/python}"
OUT="${REVIEW_OUT:-build/review/vehicles}"
JPG="${1:?usage: tools/review/vehicles.sh <out.jpg> [--rows N] [kind[:#rrggbb] ...]}"
shift

rm -f "$OUT"/front_*.png "$OUT"/rear_*.png
lune run tools/review/vehicles.luau --out "$OUT" --res "${REVIEW_RES:-1600x620}" "$@"
nice -n 10 "$PY" -I tools/review/render.py --scene "$OUT/scene.json" --views "$OUT/views.json" --out "$OUT" \
	--threads 2 >"$OUT/render.log" 2>&1 || {
	tail -n 20 "$OUT/render.log" >&2
	exit 1
}
grep "^review: .* views in" "$OUT/render.log"
mkdir -p "$(dirname "$JPG")"
python3 -I - "$OUT" "$JPG" <<'EOF'
import json, os, sys
from PIL import Image

out, jpg = sys.argv[1], sys.argv[2]
names = [v["name"] for v in json.load(open(os.path.join(out, "views.json")))["views"]]
names.sort(key=lambda n: (not n.startswith("front"), n))
tiles = [Image.open(os.path.join(out, n + ".png")).convert("RGB") for n in names]
w = min(1600, tiles[0].width)
tiles = [t.resize((w, round(t.height * w / t.width)), Image.LANCZOS) for t in tiles]
sheet = Image.new("RGB", (w, sum(t.height for t in tiles) + 4 * (len(tiles) - 1)), (20, 20, 20))
y = 0
for t in tiles:
    sheet.paste(t, (0, y))
    y += t.height + 4
quality = 88
while True:
    sheet.save(jpg, quality=quality, optimize=True, progressive=True)
    if os.path.getsize(jpg) < 390 * 1024 or quality <= 50:
        break
    quality -= 4
print(f"vehicles: {jpg} {sheet.width}x{sheet.height} q{quality} {os.path.getsize(jpg) // 1024} KiB")
EOF
