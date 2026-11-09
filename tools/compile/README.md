# tools/compile: authored data -> validated, stud-converted `generated/*.luau`

Lune scripts (no Node, no Studio). Reads `data/authored/**` (HTML units, JSON) and the harvest
(`data/harvest/routes.json`, `forks.json`), validates everything against `data/schema/*.schema.json`,
checks cross-references and spec counts, converts lengths and speeds to studs (x 2.5) and writes
ModuleScript sources to `generated/` (Rojo: `ReplicatedStorage.Shared.Generated`). Also writes
`docs/reports/compile_report.md`.

## Run (from the repository root)

```bash
lune run tools/compile/main.luau migrate            # spec/data/*.json -> data/authored/** (22 files)
lune run tools/compile/main.luau migrate --check    # fail if data/authored differs from a fresh migration
lune run tools/compile/main.luau compile            # validate + emit generated/ + docs/reports/compile_report.md
lune run tools/compile/main.luau check              # CI gate: regenerate into build/compile-check/ and diff against generated/
lune run tools/compile/main.luau all                # migrate + compile

# options
#   --repo <dir>      repository root (default: cwd; must contain default.project.json)
#   --spec <dir>      spec data dir for migrate (default /home/user/spicy-rodents/spec/data)
#   --chunk-kb <n>    target size of each Routes chunk before formatting (default 200)
#   --no-stylua       skip the StyLua pass over generated files
```

Exit codes: 0 ok; 1 any schema error, failed invariant, count mismatch, stale file or load failure
(the message names the file, JSON path and reason, e.g.
`data/authored/town/roads.json $.roads[3].width: expected number, got string "wide"`).

The whole pipeline (validate, convert, emit, StyLua, require-check) runs in a few seconds.

## What it checks

- Every authored file and the two harvest files validate against their schema (type, required,
  enum, ranges, patterns, oneOf path variants, tuple items).
- Unique ids (lots, roads, lanes, cast, catalogue lines, routes); lanes reference existing roads;
  cast `homeLot` references existing lots; lot district equals its file; free roads have `[x, z]`
  ends; routes have creation-order ids, finite points and `sampleCount = max(20, ceil(3L)) + 1`;
  forks reference existing routes.
- Count comparisons against the specs and the W0 targets: 243 lots (11 districts), 116 roads,
  25 lanes, 87 cast, 60 generators summing to 1,332, 1,332 harvested routes at 60 call sites,
  per-generator instance counts (catalogue `line` vs harvest `callSite.line`), 95 fork trunks,
  95 trees (matching the harvest by position), 12 apple trees, 24 nests, 10 nut caches, 5 deer,
  30 insects, 11 hollow proposals.
- After emitting: StyLua formats the files (repo `stylua.toml`), then every module is `require`d
  under Lune, its record count is checked and the load time recorded in the report.

## Units

Schemas mark lengths with `"x-unit": "u"` and speeds with `"u/s"`; a unit on an array applies to
the numbers inside. The compiler multiplies those by 2.5 on the number's shortest decimal form
(`18.04` -> `45.1`, not `45.099999999999994`); full-precision harvest doubles keep 17 digits.
Angles (`rad`), seconds, counts and strings are untouched. Nested v5.4 constant blocks in the
wildlife files that the schemas do not annotate are copied verbatim and emitted under `htmlUnits`
or documented as HTML units in the module header.

## Layout

```
tools/compile/main.luau        CLI (migrate | compile | check | all)
tools/compile/lib/Json.luau    @lune/serde decode + deterministic pretty encoder (sorted keys)
tools/compile/lib/Schema.luau  JSON Schema draft-07 subset validator (see header for the keyword list)
tools/compile/lib/Units.luau   x-unit driven conversion, decimal x2.5
tools/compile/lib/LuauEmit.luau  table-literal emitter (sorted keys, shortest numbers) + chunking
tools/compile/lib/Migrate.luau spec/data -> data/authored shapes
tools/compile/lib/Report.luau  docs/reports/compile_report.md
data/schema/*.schema.json      lots, roads, lanes, cast, routes_catalog, wildlife_* (7), harvest_routes, harvest_forks
data/authored/town/lots/<district>.json, town/roads.json, town/lanes.json, routes/catalog.json,
              cast/cast.json, wildlife/{trees,apple_trees,nests,fauna,forage_v54,restore_v41,hollows}.json
generated/Index.luau           module list, counts, studsPerUnit, harvest pin
generated/Lots.luau Roads.luau Lanes.luau Cast.luau RoutesCatalog.luau Wildlife.luau Forks.luau Routes_NN.luau
```

`Index.luau` is pure data: `modules.Routes.chunks = { "Routes_01", ... }`; the `Data` accessor
(W1) requires each chunk by name and concatenates.

## Known limits (v0)

- JSON `null` decodes to nil under Lune, so a null property is the same as an absent one; nullable
  fields are never `required`, and arrays never contain null.
- Schema `pattern` is a regex subset translated to Luau patterns (anchors, classes, `\d \w \s`,
  `* + ?`); no alternation or `{n}`.
- W1 (`lib/W1.luau`, schemas in `tools/compile/schema/`): `data/authored/lot_types.json`,
  `data/buildings/*.json`, `data/interiors/*.json`, `data/harvest_patches.json`, `data/population.json`,
  `data/hollows.json`, `data/terrain_extensions.json`, `data/authored/town/lighting.json` ->
  `LotTypes`, `Buildings`, `Interiors`, `HarvestPatches`, `Population`, `Hollows`, `TerrainExtensions`,
  `Lighting` (HTML units, not converted; builders scale by 2.5). Invariants 1 (params vs paramSchema),
  5, 9 (room graphs), 11, 20 and 19 (offroad) run; the route-to-lot assignment is not implemented yet.
- `w1_seed.luau` seeded lot `params`/`seat`/`home` from the harvest once; lots are hand-edited since.
