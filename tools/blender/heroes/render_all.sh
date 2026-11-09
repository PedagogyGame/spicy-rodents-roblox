#!/usr/bin/env bash
# Review renders for every built hero (Cycles CPU, 2 threads): a 12-frame 960x540 turntable and each
# clip's key poses, then compact JPEG sheets for docs/renders/heroes/.
#   tools/blender/heroes/render_all.sh [variant ...]     frames in build/heroes/renders/<variant>/
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"
PY=/root/.cache/spicy-rodents/venv/bin/python
CPUS="${HERO_CPUS:-2,3}"
SAMPLES="${HERO_SAMPLES:-32}"
VARIANTS=("$@")
[ ${#VARIANTS[@]} -eq 0 ] && VARIANTS=(squirrel rodent fox doe buck)
mkdir -p docs/renders/heroes
for v in "${VARIANTS[@]}"; do
  out="build/heroes/renders/$v"
  rm -rf "$out"; mkdir -p "$out"
  echo "== $v $(date -u +%T)"
  taskset -c "$CPUS" "$PY" -I tools/blender/heroes/render_hero.py --blend "build/heroes/$v/$v.blend" --out "$out" \
    --turntable 12 --poses --samples "$SAMPLES" --res 960x540 --pose-res 480x300 > "$out/render.log" 2>&1
  echo "   exit $? $(ls "$out"/*.png 2>/dev/null | wc -l) frames"
  python3 -I tools/blender/heroes/sheets.py turntable --dir "$out" --tag "$v" --out "docs/renders/heroes/${v}_turntable.jpg" --scale 0.5
  python3 -I tools/blender/heroes/sheets.py poses --dir "$out" --tag "$v" --out "docs/renders/heroes/${v}_poses.jpg" --meta "build/heroes/$v/report.json" --scale 0.75
  cp "$out/${v}_turntable_01.png" "docs/renders/heroes/${v}_hero.png" 2>/dev/null
done
