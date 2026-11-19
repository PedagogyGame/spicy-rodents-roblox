#!/usr/bin/env bash
# tools/review/rides.sh: one picture of a lineup (street riders, player vehicles, traffic vehicles, baked yard props)
# from the front and the rear three-quarter, offline (tools/review/rides.luau -> scene; tools/review/render.py -> PNGs;
# Pillow stacks them into a JPEG: the front views of every row, then the rear views).
# Usage: tools/review/rides.sh <out.jpg> [--rows N] entry ...   (entries: see tools/review/rides.luau)
# Env:   REVIEW_PY (bpy interpreter), REVIEW_OUT (work directory, default build/review/rides),
#        REVIEW_SAMPLES (default 40), REVIEW_RES (one view, default 1600x620)
# About a minute per view on 2 shared CPUs; the render runs under nice.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.cargo/bin:$HOME/.rokit/bin:$PATH"
PY="${REVIEW_PY:-/root/.cache/spicy-rodents/venv/bin/python}"
OUT="${REVIEW_OUT:-build/review/rides}"
JPG="${1:?usage: tools/review/rides.sh <out.jpg> [--rows N] entry ...}"
shift

mkdir -p "$OUT"
rm -f "$OUT"/front_*.png "$OUT"/rear_*.png
lune run tools/review/rides.luau --out "$OUT" --res "${REVIEW_RES:-1600x620}" "$@"
nice -n 10 "$PY" -I tools/review/render.py --scene "$OUT/scene.json" --views "$OUT/views.json" --out "$OUT" \
	--threads 2 >"$OUT/render.log" 2>&1 || {
	tail -n 20 "$OUT/render.log" >&2
	exit 1
}
grep "^review: .* views in" "$OUT/render.log"
mkdir -p "$(dirname "$JPG")"
python3 -I tools/review/stack.py "$JPG" --dir "$OUT"
