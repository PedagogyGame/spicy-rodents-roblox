#!/usr/bin/env bash
# tools/review/run.sh: visual review renders of the baked town and the placeholder puppets (no Studio needed).
#   1. bake    lune run tools/bake/main.luau; lune run tools/bake/editor_ground.luau; lune run tools/bake/backdrop.luau
#              (build/Town.rbxm, EditorGround.rbxm, Backdrop.rbxm: far scenery, fog cards; tools/review/backdrop_*)
#              and tools/placeholders/build.luau into build/review/placeholders (the committed assets are untouched)
#   2. export  lune run tools/review/export.luau  -> build/review/scene.json (+ ground-contact and z-fight summary)
#   3. render  tools/review/render.py (bpy, Cycles CPU, 2 threads) -> build/review/<view>.png, timing.json
#   4. sheet   tools/review/sheet.py (system python3 + Pillow) -> build/review/contact_sheet.png
# Views: tools/review/views.json. Total about 6 minutes on 2 CPUs (10-28 s per 960x540 view, 19 views).
# Usage: tools/review/run.sh [--no-bake] [--only name1,name2] [--set backdrop] [--debug] [--samples N]
#        (--set backdrop adds the opt-in bd_ views: horizon, ocean and marina, ranges, 300-st aerials, sunset, night)
# Env:   REVIEW_PY   bpy interpreter (default /root/.cache/spicy-rodents/venv/bin/python)
#        REVIEW_CPUS taskset CPU list for the render (default 2,3 on 4+ cores)
#        REVIEW_OUT  output directory (default build/review; a second reviewer can render beside the first)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.cargo/bin:$HOME/.rokit/bin:$PATH"
PY="${REVIEW_PY:-/root/.cache/spicy-rodents/venv/bin/python}"
OUT="${REVIEW_OUT:-build/review}"

BAKE=1
RENDER_ARGS=()
while [ $# -gt 0 ]; do
	case "$1" in
	--no-bake) BAKE=0 ;;
	--only | --samples | --set)
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
	lune run tools/bake/backdrop.luau
	# puppets from the current PuppetSpec / VehiclePuppet source (the committed assets/placeholders can lag)
	if lune run tools/placeholders/build.luau "$OUT/placeholders" >"$OUT/placeholders.log" 2>&1; then
		tail -n 1 "$OUT/placeholders.log"
	else
		echo "placeholders: rebuild failed (see $OUT/placeholders.log); the lineup uses assets/placeholders"
		rm -rf "$OUT/placeholders"
	fi
	lap bake
fi
PLACEHOLDERS=assets/placeholders
[ -f "$OUT/placeholders/squirrel.rbxm" ] && PLACEHOLDERS="$OUT/placeholders"

echo "== export (puppets from $PLACEHOLDERS)"
lune run tools/review/export.luau --out "$OUT/scene.json" --placeholders "$PLACEHOLDERS"
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
for v in json.load(open(sys.argv[1]))["views"]:
    print("%7.1fs  %s" % (v["seconds"], v["png"]))
' "$OUT/timing.json"
[ -f "$OUT/contact_sheet.png" ] && echo "  sheet   $ROOT/$OUT/contact_sheet.png"
printf "total %.1fs\n" "$(echo "$(now) - $T0" | bc)"
