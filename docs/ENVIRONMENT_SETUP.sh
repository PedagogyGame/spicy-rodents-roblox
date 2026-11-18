#!/usr/bin/env bash
# Idempotent toolchain setup for the Spicy Rodents Roblox rebuild (BUILD_PLAN §4.3 item 1).
# Intended as the cloud environment setup script (runs as root in a fresh Linux container with
# cargo, python3 and node available; GitHub release downloads are blocked there, so everything
# comes from crates.io, PyPI and npm, and luau-lsp is built from its source, which git can clone).
# Safe to re-run: every step checks before it installs. Caches live under /root/.cache. Takes
# ~20 min cold (bpy is a 403 MB wheel; luau-lsp is a 250-file C++ build), seconds when warm.
set -euo pipefail

ROJO_VERSION=7.7.1
LUNE_VERSION=0.11.1
STYLUA_VERSION=2.6.0
SELENE_VERSION=0.31.0
LUAU_LSP_VERSION=1.70.1
BPY_VERSION=5.2.3

export CARGO_HOME="${CARGO_HOME:-$HOME/.cargo}"
export CARGO_TARGET_DIR="${CARGO_TARGET_DIR:-/root/.cache/cargo-target}"
export PIP_CACHE_DIR="${PIP_CACHE_DIR:-/root/.cache/pip}"
export npm_config_cache="${npm_config_cache:-/root/.cache/npm}"
mkdir -p "$CARGO_TARGET_DIR" "$PIP_CACHE_DIR" "$npm_config_cache"
export PATH="$CARGO_HOME/bin:$PATH"

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
log() { printf '\n== %s\n' "$*"; }

have_version() { # tool version-substring
	command -v "$1" >/dev/null 2>&1 && "$1" --version 2>/dev/null | grep -q "$2"
}

log "cargo tools (pinned)"
command -v cargo >/dev/null || { echo "cargo is required (rustup)"; exit 1; }
have_version rojo "$ROJO_VERSION" || cargo install rojo --locked --version "$ROJO_VERSION"
have_version lune "$LUNE_VERSION" || cargo install lune --locked --version "$LUNE_VERSION"
# StyLua MUST be built with the luau feature or stylua.toml (syntax = "Luau") fails to parse.
if ! have_version stylua "$STYLUA_VERSION" || ! echo 'local x: number = 1' | stylua - >/dev/null 2>&1; then
	cargo install stylua --locked --version "$STYLUA_VERSION" --features luau --force
fi
have_version selene "$SELENE_VERSION" || cargo install selene --locked --version "$SELENE_VERSION"

log "luau-lsp $LUAU_LSP_VERSION (built from source) and its Roblox type definitions"
# The type checker tools/ci.sh runs (tools/typecheck). Its release binaries cannot be downloaded
# here, but its source can be cloned and it needs only cmake and a C++ compiler. The Roblox
# definitions that match the release ship in the same source tree.
LSP_CACHE=/root/.cache/spicy-rodents/luau-lsp
LSP_DEFS="$LSP_CACHE/globalTypes-$LUAU_LSP_VERSION.d.luau"
if ! have_version luau-lsp "$LUAU_LSP_VERSION" || [ ! -s "$LSP_DEFS" ]; then
	command -v cmake >/dev/null && command -v c++ >/dev/null \
		|| { echo "cmake and a C++ compiler are required to build luau-lsp"; exit 1; }
	LSP_SRC="$LSP_CACHE/src-$LUAU_LSP_VERSION"
	LSP_BUILD="$LSP_CACHE/build-$LUAU_LSP_VERSION"
	mkdir -p "$LSP_CACHE"
	if [ ! -d "$LSP_SRC/.git" ]; then
		rm -rf "$LSP_SRC"
		GIT_LFS_SKIP_SMUDGE=1 git clone --depth 1 --branch "$LUAU_LSP_VERSION" \
			https://github.com/JohnnyMorganz/luau-lsp "$LSP_SRC"
	fi
	GIT_LFS_SKIP_SMUDGE=1 git -C "$LSP_SRC" submodule update --init --depth 1
	LSP_GEN=()
	if command -v ninja >/dev/null; then LSP_GEN=(-G Ninja); fi
	cmake -S "$LSP_SRC" -B "$LSP_BUILD" "${LSP_GEN[@]}" -DCMAKE_BUILD_TYPE=Release \
		-DLSP_WERROR=OFF -DLSP_BUILD_WITH_SENTRY=OFF
	cmake --build "$LSP_BUILD" --target Luau.LanguageServer.CLI -j "$(nproc)"
	install -m 0755 "$LSP_BUILD/luau-lsp" "$CARGO_HOME/bin/luau-lsp"
	cp "$LSP_SRC/scripts/globalTypes.d.luau" "$LSP_DEFS"
fi

log "selene roblox std"
# roblox.yml is committed: stock selene cannot fetch the API dump through the proxy. To regenerate,
# build selene with ureq features proxy-from-env,native-certs (see docs/spec/roblox_feasibility.md)
# and run `selene generate-roblox-std` in the repo root. Here we only check the file is present.
test -s "$REPO/roblox.yml" || echo "WARNING: roblox.yml missing; selene std=roblox will try to download it"

log "git lfs"
if command -v git-lfs >/dev/null 2>&1; then
	git -C "$REPO" lfs install --local >/dev/null 2>&1 || true
else
	echo "git-lfs not installed; LFS rules in .gitattributes are inert until it is (apt-get install -y git-lfs)"
fi

log "python venv + bpy $BPY_VERSION (Blender headless)"
VENV="${BPY_VENV:-/root/.cache/spicy-rodents/venv}"
if [ ! -x "$VENV/bin/python" ]; then
	python3 -m venv "$VENV"
fi
if ! "$VENV/bin/python" -c "import bpy, sys; sys.exit(0 if bpy.app.version_string.startswith('$BPY_VERSION') else 1)" 2>/dev/null; then
	"$VENV/bin/pip" install --quiet --upgrade pip
	"$VENV/bin/pip" install --quiet "bpy==$BPY_VERSION" numpy
fi
echo "bpy venv: $VENV (activate with: source $VENV/bin/activate)"

log "node dependencies"
command -v node >/dev/null || { echo "node 22+ is required"; exit 1; }
# tools/cloud is dependency-free (Node built-in fetch). Harvest/golden tools install their own.
for dir in tools/harvest tools/golden; do
	if [ -f "$REPO/$dir/package-lock.json" ]; then
		(cd "$REPO/$dir" && npm ci --no-audit --no-fund --silent)
	elif [ -f "$REPO/$dir/package.json" ]; then
		(cd "$REPO/$dir" && npm install --no-audit --no-fund --silent)
	fi
done

log "versions"
rojo --version; lune --version; stylua --version; selene --version; echo "luau-lsp $(luau-lsp --version)"; node --version
echo "setup complete; run tools/ci.sh to verify"
