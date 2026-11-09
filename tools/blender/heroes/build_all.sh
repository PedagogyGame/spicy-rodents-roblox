#!/usr/bin/env bash
# Build every hero at full quality (sequential, 2 CPUs): squirrel, rodent, fox, doe, buck.
#   tools/blender/heroes/build_all.sh [variant ...]      logs to build/heroes/<variant>/build.log
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
cd "$ROOT"
PY=/root/.cache/spicy-rodents/venv/bin/python
CPUS="${HERO_CPUS:-2,3}"
VARIANTS=("$@")
[ ${#VARIANTS[@]} -eq 0 ] && VARIANTS=(squirrel rodent fox doe buck)
for v in "${VARIANTS[@]}"; do
  case "$v" in
    squirrel) sp=squirrel ;; rodent) sp=rodent ;; fox) sp=fox ;; doe|buck) sp=deer ;;
    *) echo "unknown variant $v" >&2; exit 2 ;;
  esac
  mkdir -p "build/heroes/$v"
  echo "== $v $(date -u +%T)"
  taskset -c "$CPUS" "$PY" -I tools/blender/heroes/build_hero.py --species "$sp" --variant "$v" --out "build/heroes/$v" > "build/heroes/$v/build.log" 2>&1
  echo "   exit $? $(grep -c 'Traceback' "build/heroes/$v/build.log") tracebacks; $(grep '\[hero' "build/heroes/$v/build.log" | tail -1)"
done
