#!/usr/bin/env bash
# tools/ci.sh: the local CI gate (BUILD_PLAN §4.3 item 1, §6.7).
#   stylua --check -> selene -> Lune unit tests -> compile check (generated/ not stale) ->
#   rojo build (.rbxl + .rbxlx, default and ci projects) -> Lune place tests -> rojo sourcemap ->
#   type check (luau-lsp analyze, strict: tools/typecheck fails on any type error that is not in
#   its baseline of known ones).
# Exit code is non-zero on the first failing step. Each step prints its wall time.
# Usage: tools/ci.sh            (from anywhere; runs at the repo root)
#        tools/ci.sh --no-build (skip rojo build, place tests and the type check: formatting, lint, unit only)
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
export PATH="$HOME/.cargo/bin:$HOME/.rokit/bin:$PATH"

NO_BUILD=0
for arg in "$@"; do
	case "$arg" in
	--no-build) NO_BUILD=1 ;;
	*) echo "unknown argument: $arg" >&2; exit 2 ;;
	esac
done

for tool in stylua selene lune rojo; do
	if ! command -v "$tool" >/dev/null 2>&1; then
		echo "ci: missing tool '$tool' (see docs/ENVIRONMENT_SETUP.sh or rokit.toml)" >&2
		exit 127
	fi
done

STEP_START=0
step() {
	STEP_START=$(date +%s.%N)
	echo
	echo "== $1"
}
done_step() {
	local end
	end=$(date +%s.%N)
	printf -- "-- ok (%.1fs)\n" "$(echo "$end - $STEP_START" | bc)"
}

LUAU_DIRS=(src tests tools/cloud/tasks tools/compile tools/anim tools/bake tools/bowling tools/pinball tools/sim tools/typecheck)

step "stylua --check (StyLua $(stylua --version | awk '{print $2}'), Luau syntax)"
stylua --check "${LUAU_DIRS[@]}"
done_step

mkdir -p build

step "selene (Selene $(selene --version | awk '{print $2}'), std = roblox, committed roblox.yml)"
selene --no-summary "${LUAU_DIRS[@]}"
done_step

step "lune tests (Lune $(lune --version | awk '{print $2}'))"
lune run tests/run.luau
done_step

step "compile check (tools/compile: validate data/authored + data/harvest, regenerate into build/compile-check, diff against generated/)"
lune run tools/compile/main.luau check
done_step

if [ "$NO_BUILD" -eq 1 ]; then
	echo
	echo "ci: --no-build given; skipping rojo build, place tests, sourcemap and the type check"
	exit 0
fi

step "rojo build (Rojo $(rojo --version | awk '{print $2}')): default -> build/SpicyRodents.rbxl + .rbxlx"
rojo build default.project.json -o build/SpicyRodents.rbxl
rojo build default.project.json -o build/SpicyRodents.rbxlx
done_step

step "rojo build: ci.project.json -> build/test.rbxl (CI place payload with ServerStorage.EngineTests)"
rojo build ci.project.json -o build/test.rbxl
done_step

step "rojo build: build.project.json -> build/owner.rbxl (optional Town.rbxm absent is fine)"
rojo build build.project.json -o build/owner.rbxl
done_step

step "lune place tests"
lune run tests/place/check_place.luau build/SpicyRodents.rbxl default.project.json
lune run tests/place/check_place.luau build/SpicyRodents.rbxlx default.project.json
lune run tests/place/check_place.luau build/test.rbxl ci.project.json
lune run tests/place/check_place.luau build/owner.rbxl build.project.json
done_step

step "rojo sourcemap -> sourcemap.json (for the type check)"
rojo sourcemap default.project.json -o sourcemap.json --include-non-scripts
done_step

if ! command -v luau-lsp >/dev/null 2>&1; then
	echo "ci: missing tool 'luau-lsp' (docs/ENVIRONMENT_SETUP.sh builds it from source; rokit.toml pins it)" >&2
	exit 127
fi
step "type check (luau-lsp $(luau-lsp --version), strict, Roblox definitions, sourcemap; known errors: tools/typecheck/baseline.txt)"
lune run tools/typecheck/main.luau
done_step

echo
echo "ci: all steps passed"
