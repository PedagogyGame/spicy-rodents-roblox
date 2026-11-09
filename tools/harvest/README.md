# tools/harvest: reference capture of the pinned v5.4 HTML

Runs `reference/Spicy_Rodents_v5_4_Living_Town.html` headlessly in Chromium (Playwright, SwiftShader
WebGL), instruments it as described in `spec/routes_movement.md` section 0, and writes the route
registry and the other world registries to `data/harvest/*.json` (HTML units). Also writes
`docs/reports/harvest_report.md`.

## Run

```bash
# from the repository root; takes about 60-70 s for the default three runs
node tools/harvest/src/harvest.js

# options (defaults shown)
node tools/harvest/src/harvest.js \
  --ref     /home/user/spicy-rodents/reference/Spicy_Rodents_v5_4_Living_Town.html \
  --pretty  /home/user/spicy-rodents/reference/v5_4_game.js \
  --catalog /home/user/spicy-rodents/spec/data/routes_catalog.json \
  --wildlife /home/user/spicy-rodents/spec/data/wildlife.json \
  --out     data/harvest \
  --report  docs/reports/harvest_report.md \
  --cache   tools/harvest/.cache \
  --variant both      # both | html | pretty
  --runs    2         # number of html-variant runs for the determinism check
  --timeout 300000    # ms per run
```

Exit codes: 0 all count comparisons match; 2 at least one comparison mismatched (outputs still
written); 3 the html runs disagreed outside the known-volatile sections; 1 hard failure (hash
mismatch, no dump, browser failure).

## Dependencies

- Node 22 and Playwright 1.63.0 with its Chromium. In this container Playwright is preinstalled
  globally (`require("playwright")` resolves through `NODE_PATH`; browsers in
  `PLAYWRIGHT_BROWSERS_PATH=/opt/pw-browsers`). Do **not** run `playwright install`.
- `npm install` inside this directory is optional; `package.json` pins `playwright@1.63.0` so a
  fresh machine gets the same version. The pin must match the installed browser revision.
- No network is needed: the HTML inlines three.js r160 as a `data:` import; every external
  request (fonts, HDRI, bark textures, jsdelivr post-processing modules) is blocked by the tool and
  the game tolerates the failures.

## What the instrumentation does

`src/instrument.js` builds a scratch copy of the HTML (written to `.cache/`, never to the reference):

1. The game's `function addRoute(name, points, opts = {})` is renamed `addRoute__orig` and a wrapper
   with the original name records `new Error().stack` on every route (the call site).
2. `__SR_DUMP()` (in `src/inpage_dump.js`) is inserted right after `rebuildCanopyForks();` and before
   the startup `try { ... tick(); }` block, so the dump sees the complete registries and the world
   before the first frame. The dump only reads module-scope registries; no game value changes.

Two module variants run: `html` (the module exactly as embedded in the HTML, which is byte-identical
to `reference/v5_4_game.min.js`) and `pretty` (`reference/v5_4_game.js`, prettier output of the same
code) so that call-site line numbers equal the line numbers the specs cite. The tool verifies that
all runs produce the same dump outside the known-volatile sections (call sites, chili peppers).

## Outputs (`data/harvest/`)

| file | content |
|---|---|
| `manifest.json` | pin (SHA-256), environment, seeds, per-run logs, determinism hashes, count comparisons, file hashes |
| `routes.json` | 1,332 routes in creation order: id, name, kind, speed, center, surfaceRadius, visualOffset, length, indexed, trunkClearance, control points, sampleCount, callSite `{line, col, fn}` (line in `v5_4_game.js`) |
| `route_samples.json` | `[id, [[x,y,z], ...]]` the game's `getSpacedPoints` output (81,613 points) |
| `route_index.json` | the `routeSpatial` cells (8 u) with `[routeId, sampleIndex]` entries |
| `forks.json` | `canopyForks`: 95 trunks, forks sorted by height with t, height, origin, outward, trunkClearance |
| `trees.json` | `trees[]` (95 incl. 12 apple trees), `treeSpec`, `giantTreeSpecs`, `outerTreeCandidates`, giant perches, estate gate tree tips, Westside trees |
| `utility.json` | 110 utility supports (97 residential poles with their trunk route, 6 estate, 7 westside), wire route ids |
| `nests.json`, `apple_trees.json` | 24 nests (route id, point), 12 apple trees |
| `houses.json` | 24 `houses[]` records, the `outerHomes` table, `commercialBounds`, `houseDoors`, `riverBuildings` |
| `colliders.json` | `obstacles`, `fenceCollisions`, `mallColliders`, `estateProjects` |
| `world.json` | BuildInfo, WORLD_HALF, RIVER, 48 pavement zones, concealment (hedges, garden), Tabasco plants, counts |
| `vehicles_initial.json`, `fauna.json` | vehicle and animal registries before the first tick |
| `graph.json` | DERIVED: islands (1.7 u rule) and endpoint auto-links (0.48 u end windows, trunk filter) |
| `peppers_nondeterministic.json` | the 8 chili positions per run, flagged; the seed is `crypto.getRandomValues` so they differ every load |

Everything is in HTML units; `tools/compile` converts to studs. Files are machine output and must
never be hand-edited (BUILD_PLAN 1.2).

## Files

- `src/harvest.js` runner (hash check, local http server, Playwright, output writing)
- `src/instrument.js` builds the instrumented HTML
- `src/inpage_dump.js` the in-page dump (hoisted functions inserted into the module)
- `src/analyze.js` count comparisons, call-site table, derived connectivity graph
- `src/report.js` writes `docs/reports/harvest_report.md`
- `src/jsonfmt.js` deterministic JSON writer (numeric arrays on one line)
