#!/usr/bin/env bash
# tools/review/run.sh: visual review renders of the baked town and the placeholder puppets (no Studio needed).
#   1. bake    lune run tools/bake/main.luau; lune run tools/bake/editor_ground.luau  (build/Town.rbxm, EditorGround.rbxm)
#   2. export  lune run tools/review/export.luau  -> build/review/scene.json (+ ground-contact and z-fight summary)
#   3. render  tools/review/render.py (bpy, Cycles CPU, 2 threads) -> build/review/<view>.png, timing.json
#   4. sheet   tools/review/sheet.py (system python3 + Pillow) -> build/review/contact_sheet.png
# Views: tools/review/views.json. Total about 7 minutes on 2 CPUs (about 20 s per 960x540 view).
# Usage: tools/review/run.sh [--no-bake] [--only name1,name2] [--debug] [--samples N]
# Env:   REVIEW_PY   bpy interpreter (default /root/.cache/spicy-rodents/venv/bin/python)
#        REVIEW_CPUS taskset CPU list for the render (default 2,3 on 4+ cores)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.cargo/bin:$HOME/.rokit/bin:$PATH"
PY="${REVIEW_PY:-/root/.cache/spicy-rodents/venv/bin/python}"
OUT=build/review

BAKE=1
RENDER_ARGS=()
while [ $# -gt 0 ]; do
	case "$1" in
	--no-bake) BAKE=0 ;;
	--only | --samples)
		RENDER_ARGS+=("$1" "$2")
		shift
		;;
	--debug) RENDER_ARGS+=("--debug") ;;
	*)
		echo "unknown argument: $1" >&2
		exit 2
		;;
	esac
	shift
done

if [ -z "${REVIEW_CPUS:-}" ]; then
	if [ "$(nproc)" -ge 4 ]; then REVIEW_CPUS=2,3; else REVIEW_CPUS=0-$(($(nproc) - 1)); fi
fi
PIN=()
if command -v taskset >/dev/null 2>&1; then PIN=(taskset -c "$REVIEW_CPUS"); fi

now() { date +%s.%N; }
T0=$(now)
STAGE=$T0
lap() {
	local t
	t=$(now)
	printf -- "-- %s: %.1fs\n" "$1" "$(echo "$t - $STAGE" | bc)"
	STAGE=$t
}

mkdir -p "$OUT"
if [ "$BAKE" -eq 1 ]; then
	echo "== bake"
	lune run tools/bake/main.luau
	lune run tools/bake/editor_ground.luau
	lap bake
fi

echo "== export"
lune run tools/review/export.luau --out "$OUT/scene.json"
lap export

echo "== render (cpus $REVIEW_CPUS; full log $OUT/render.log)"
{
	${PIN[@]+"${PIN[@]}"} "$PY" -I tools/review/render.py --scene "$OUT/scene.json" --views tools/review/views.json \
		--out "$OUT" --threads 2 ${RENDER_ARGS[@]+"${RENDER_ARGS[@]}"} 2>&1
	echo "render exit $?"
} | tee "$OUT/render.log" | grep --line-buffered -E "^review:|Error|Traceback|^render exit" || true
if ! grep -q "^render exit 0$" "$OUT/render.log"; then
	echo "render failed (see $OUT/render.log)" >&2
	exit 1
fi
lap render

if python3 -c "import PIL" >/dev/null 2>&1; then
	python3 -I tools/review/sheet.py --dir "$OUT" --timing "$OUT/timing.json"
	lap sheet
else
	echo "(no Pillow for python3: contact sheet skipped)"
fi

echo
echo "== PNGs"
python3 -I -c '
import json, sys
t = json.load(open(sys.argv[1]))
for v in t["views"]:
    print(f"{v[\"seconds\"]:7.1f}s  {v[\"png\"]}")
' "$OUT/timing.json"
[ -f "$OUT/contact_sheet.png" ] && echo "  sheet   $ROOT/$OUT/contact_sheet.png"
printf "total %.1fs\n" "$(echo "$(now) - $T0" | bc)"
