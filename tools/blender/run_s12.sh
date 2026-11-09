#!/usr/bin/env bash
# S12 driver: build the test squirrel, render the Cycles CPU turntable, try EEVEE and Workbench,
# assemble the contact sheet and page. Pinned to 2 CPUs (taskset) so other work is not starved.
# Usage: tools/blender/run_s12.sh [samples] [frames]      (defaults 24, 36); logs to build/blender/
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
PY=/root/.cache/spicy-rodents/venv/bin/python
SAMPLES="${1:-64}"
FRAMES="${2:-36}"
OUT=build/blender
mkdir -p "$OUT"
CPUS="${S12_CPUS:-2,3}"
echo "== S12 start $(date -u +%FT%TZ) cpus=$CPUS samples=$SAMPLES frames=$FRAMES"
taskset -c "$CPUS" "$PY" -I tools/blender/squirrel_test_rig.py --out "$OUT" > "$OUT/rig.log" 2>&1; echo "rig exit $?"
taskset -c "$CPUS" "$PY" -I tools/blender/render_turntable.py --engine EEVEE --samples 16 --frames 3 --res 512 --threads 2 --out "$OUT/eevee" > "$OUT/eevee.log" 2>&1; echo "eevee exit $?"
taskset -c "$CPUS" "$PY" -I tools/blender/render_turntable.py --engine WORKBENCH --samples 8 --frames "$FRAMES" --res 512 --threads 2 --out "$OUT/workbench" > "$OUT/workbench.log" 2>&1; echo "workbench exit $?"
taskset -c "$CPUS" "$PY" -I tools/blender/render_turntable.py --engine CYCLES --samples "$SAMPLES" --frames "$FRAMES" --res 512 --threads 2 --denoise --out "$OUT/cycles" > "$OUT/cycles.log" 2>&1; echo "cycles exit $?"
if ls "$OUT/cycles"/frame_*.png >/dev/null 2>&1; then
  python3 -I tools/blender/contact_sheet.py --frames "$OUT/cycles" --out docs/renders --name squirrel_turntable --thumb 128 --page-frame 256 --timing "$OUT/cycles/timing.json"
fi
echo "== S12 done $(date -u +%FT%TZ)"
