# Harvest report: v5.4 reference capture

Generated 2026-11-09T06:01:58.005Z by `tools/harvest`. Output: `data/harvest/`. Re-run: `node tools/harvest/src/harvest.js` (see `tools/harvest/README.md`).

## Pin

- HTML: `/home/user/spicy-rodents/reference/Spicy_Rodents_v5_4_Living_Town.html`
- SHA-256: `fc48b387e51ce3a454898d58d1cb3dda891b22ffad7110cdcd0ade6c777a6227` (1418205 bytes); the tool refuses to run on any other hash.
- Pretty-printed module used for call-site line numbers: `/home/user/spicy-rodents/reference/v5_4_game.js` (SHA-256 `721ca9c3d43f18e788d7c6a31865df2c28b67390aaa154d263801e6401fe9ff5`). The module embedded in the HTML is byte-identical to `reference/v5_4_game.min.js`; the pretty file is prettier output of the same code, and the dump from both variants is identical (see Determinism).
- Environment: Node v22.23.4, Playwright 1.63.0, Chromium 153.0.8010.12, ANGLE SwiftShader (headless, --use-angle=swiftshader).

## Seeds

- **world**: rng(20261008) at L90 (global `random`, `R`, `pick`)
- **perTree**: rng(spec.seed) at L1763 (makeTree) and rng(seed) at L2825 (estateGateOak)
- **neighborhoodDetail**: rng(51903) at L12980
- **river**: rng(5110726) at L13450
- **coins**: rng(5300811) at L14892
- **livingTown**: rng(540811) at L15133 (apple trees, nests, birds)
- **peppers**: rng(pepperSeed), pepperSeed from crypto.getRandomValues at L5314: NOT deterministic; excluded
- **runtimeOnly**: Math.random() is used only by runtime behaviour (spawns, bites, waits), never by world construction

Pepper seeds observed per run (never equal, by design): html#1=3299238839, html#2=133440412, pretty#1=1487361164. The 8 chili positions are written to `peppers_nondeterministic.json` with a warning and are excluded from every other file.

## Runs

| run | dump after | in-page dump | total | boot ok | dump ok | page errors | blocked requests |
|---|---|---|---|---|---|---|---|
| html#1 | 8286 ms | 21 ms | 9194 ms | true | true | 0 | 9 |
| html#2 | 7283 ms | 15 ms | 8051 ms | true | true | 0 | 9 |
| pretty#1 | 6472 ms | 11 ms | 7391 ms | true | true | 0 | 9 |

Console lines from the first run (duplicates collapsed):

    (x9) [error] Failed to load resource: net::ERR_BLOCKED_BY_CLIENT.Inspector
    [info] [Spicy Rodents] 110 utility supports verified off pavement

Blocked external requests (first run): `https://cdn.jsdelivr.net/npm/three@0.160.1/examples/jsm/loaders/RGBELoader.js`, `https://cdn.jsdelivr.net/npm/three@0.160.1/examples/jsm/postprocessing/EffectComposer.js`, `https://cdn.jsdelivr.net/npm/three@0.160.1/examples/jsm/postprocessing/OutputPass.js`, `https://cdn.jsdelivr.net/npm/three@0.160.1/examples/jsm/postprocessing/RenderPass.js`, `https://cdn.jsdelivr.net/npm/three@0.160.1/examples/jsm/postprocessing/UnrealBloomPass.js`, `https://dl.polyhaven.org/file/ph-assets/HDRIs/hdr/1k/kloppenheim_06_puresky_1k.hdr`, `https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/bark_willow/bark_willow_diff_1k.jpg`, `https://dl.polyhaven.org/file/ph-assets/Textures/jpg/1k/bark_willow/bark_willow_nor_gl_1k.jpg`, `https://fonts.googleapis.com/css2?family=Barlow+Condensed:wght@500;600;700;800&family=DM+Sans:wght@400;500;600;700&displ...`

## Determinism

- All html runs identical outside call sites and peppers: **true**
- Pretty-module run identical to the html run: **true**
- Canonical hashes: html#1=`b0db2d6f2efb037b`, html#2=`b0db2d6f2efb037b`, pretty#1=`b0db2d6f2efb037b`

## Count comparisons

| what | expected | actual | status | note |
|---|---|---|---|---|
| routes | 1332 | 1332 | match |  |
| spatial index entries | 81613 | 81613 | match |  |
| spatial index entries == sum of samples | 81613 | 81613 | match |  |
| routes indexed | 1332 | 1332 | match |  |
| canopy fork trunks | 95 | 95 | match |  |
| trees (trees[] incl. 12 apple trees) | 95 | 95 | match |  |
| nests | 24 | 24 | match |  |
| apple trees | 12 | 12 | match |  |
| utility supports | 110 | 110 | match |  |
| utility supports verified by the game | 110 | 110 | match |  |
| residential poles (poles[]) | 97 | 97 | match |  |
| houses (4 core + 20 outer) | 24 | 24 | match |  |
| registered pavement zones | 48 | 48 | match |  |
| peppers (nondeterministic, flagged) | 8 | 8 | match | positions excluded from the deterministic data |
| kind trunk count | 265 | 265 | match |  |
| kind trunk total length (rounded u) | 4086 | 4086 | match |  |
| kind branch count | 715 | 715 | match |  |
| kind branch total length (rounded u) | 11238 | 11238 | match |  |
| kind bridge count | 78 | 78 | match |  |
| kind bridge total length (rounded u) | 1417 | 1417 | match |  |
| kind lookout count | 12 | 12 | match |  |
| kind lookout total length (rounded u) | 55 | 55 | match |  |
| kind roof count | 99 | 99 | match |  |
| kind roof total length (rounded u) | 1700 | 1700 | match |  |
| kind wire count | 150 | 150 | match |  |
| kind wire total length (rounded u) | 6979 | 6979 | match |  |
| kind fence count | 12 | 12 | match |  |
| kind fence total length (rounded u) | 920 | 920 | match |  |
| kind trampoline count | 1 | 1 | match |  |
| kind trampoline total length (rounded u) | 32 | 32 | match |  |
| route kinds present | 8 | 8 | match |  |
| routes failing registry validation | 0 | 0 | match |  |
| sample counts == max(20, ceil(3L)) + 1 | 1332 | 1332 | match |  |
| route ids == creation order 0..n-1 | 1332 | 1332 | match |  |
| trees matching wildlife.json by (x,z) to 0.005 | 95 | 95 | match |  |
| nests matching wildlife.json by (x,z) to 0.01 | 24 | 24 | match |  |
| apple trees matching wildlife.json by (x,z) to 0.005 | 12 | 12 | match |  |
| apple tree heights matching wildlife.json to 0.005 | 12 | 12 | match |  |
| addRoute call sites used (of 60) | 60 | 60 | match |  |
| routes attributed to a call site | 1332 | 1332 | match |  |
| catalog rows matching per-call-site counts | 60 | 60 | match |  |
| islands (1.7 u sample rule) | 149 | 149 | match |  |
| largest island routes | 563 | 563 | match |  |
| branch tips with an auto-link | 0 | 0 | match |  |

Per kind (actual): roof 99 / 1699.9 u; trunk 265 / 4085.8 u; bridge 78 / 1417.2 u; fence 12 / 919.8 u; trampoline 1 / 32.1 u; wire 150 / 6979.3 u; branch 715 / 11237.6 u; lookout 12 / 55.2 u

## Routes per addRoute call site (pretty-module line numbers) vs `spec/data/routes_catalog.json`

Call sites found in the source: 60; used at runtime: 60; routes without attribution: 0; all rows match: **true**.

| line | generator | kind | catalog | harvest | status | example names |
|---|---|---|---|---|---|---|
| 733 | Chili's restaurant rooftop (top-level, commercial district) | roof | 1 | 1 | match | Chili’s restaurant rooftop |
| 794 | Gas station shop roof (top-level) | roof | 1 | 1 | match | gas station shop roof |
| 832 | Fuel canopy east-west walk (top-level) | roof | 1 | 1 | match | fuel canopy east west |
| 837 | Fuel canopy crosswalk (top-level) | roof | 1 | 1 | match | fuel canopy crosswalk |
| 854 | Fuel canopy service ladder (top-level) | trunk | 1 | 1 | match | fuel canopy service ladder |
| 863 | Fuel ladder roof link (top-level) | bridge | 1 | 1 | match | fuel ladder roof link |
| 907 | Corner shops roof (top-level) | roof | 1 | 1 | match | corner shops roof |
| 1237 | buildHouse ridge: `${cfg.kind} ridge` (four original houses) | roof | 4 | 4 | match | VICTORIAN ridge; BUNGALOW ridge; BRICK HOUSE ridge |
| 1329 | woodenFence(): 'cedar fence top' | fence | 4 | 4 | match | cedar fence top |
| 1354 | chainFence(): 'chain-link fence top' | fence | 4 | 4 | match | chain-link fence top |
| 1453 | trampoline(): 'trampoline guardrail' | trampoline | 1 | 1 | match | trampoline guardrail |
| 1627 | pole(x,z): `telephone pole climb ${x.toFixed(2)},${z.toFixed(2)}` | trunk | 97 | 97 | match | telephone pole climb -244.00,-156.00; telephone pole climb -205.00,-156.00; telephone pole climb -154.00,-156.00 |
| 1650 | stringUtilityRoute(name,a,b): 'east–west utility wire' / 'north–south telephone wire' / 'commercial utility span' | wire | 102 | 102 | match | east–west utility wire; north–south telephone wire; commercial utility span |
| 1679 | House service drops: 'house service cable' | wire | 4 | 4 | match | house service cable |
| 1782 | makeTree(spec): `${spec.name} trunk` | trunk | 32 | 32 | match | BUR OAK trunk; AMERICAN ELM trunk; SYCAMORE trunk |
| 1830 | makeTree bough: `${spec.name} bough ${i+1}` | branch | 295 | 295 | match | BUR OAK bough 1; BUR OAK bough 2; BUR OAK bough 3 |
| 1896 | makeTree living bridge: `${spec.name} living bridge to utility wire` | bridge | 15 | 15 | match | BUR OAK living bridge to utility wire; AMERICAN ELM living bridge to utility wire; SYCAMORE living bridge to utility wire |
| 1926 | makeTree rooftop crossing: `${spec.name} rooftop canopy crossing` | bridge | 10 | 10 | match | BUR OAK rooftop canopy crossing; AMERICAN ELM rooftop canopy crossing; SYCAMORE rooftop canopy crossing |
| 2136 | buildOuterHome rotated: 'neighborhood rooftop ridge' | roof | 9 | 9 | match | neighborhood rooftop ridge |
| 2142 | buildOuterHome unrotated: 'neighborhood rooftop ridge' | roof | 11 | 11 | match | neighborhood rooftop ridge |
| 2240 | makeOuterTree(spec,index): `outer ${index} tree trunk` | trunk | 44 | 44 | match | outer 0 tree trunk; outer 1 tree trunk; outer 2 tree trunk |
| 2258 | makeOuterTree bough: `outer ${index} bough ${j}` | branch | 303 | 303 | match | outer 0 bough 0; outer 0 bough 1; outer 0 bough 2 |
| 2351 | makeOuterTree bridge: `outer ${index} canopy-to-wire bridge` | bridge | 25 | 25 | match | outer 0 canopy-to-wire bridge; outer 1 canopy-to-wire bridge; outer 4 canopy-to-wire bridge |
| 2428 | makeLookoutTree(spec,index): `${name} giant trunk` | trunk | 3 | 3 | match | SENTINEL OAK giant trunk; HIGHLAND ELM giant trunk; OLD WATCH SYCAMORE giant trunk |
| 2458 | makeLookoutTree bough: `${name} high lookout bough ${j+1}` | branch | 21 | 21 | match | SENTINEL OAK high lookout bough 1; SENTINEL OAK high lookout bough 2; SENTINEL OAK high lookout bough 3 |
| 2478 | makeLookoutTree perch: `${name} OPEN SKY LOOKOUT` | lookout | 6 | 6 | match | SENTINEL OAK OPEN SKY LOOKOUT; HIGHLAND ELM OPEN SKY LOOKOUT; OLD WATCH SYCAMORE OPEN SKY LOOKOUT |
| 2674 | estateCourt(): 'estate tennis net top' | fence | 2 | 2 | match | estate tennis net top |
| 2695 | estateGuest(): 'estate guesthouse roof' | roof | 2 | 2 | match | estate guesthouse roof |
| 2748 | estateMansion(): 'grand estate main roof' | roof | 2 | 2 | match | grand estate main roof |
| 2835 | estateGateOak(): 'estate oak trunk' | trunk | 4 | 4 | match | estate oak trunk |
| 2859 | estateGateOak bough: `estate oak major bough ${j}` | branch | 24 | 24 | match | estate oak major bough 0; estate oak major bough 1; estate oak major bough 2 |
| 2922 | Estate avenue: 'estate avenue cable' | wire | 5 | 5 | match | estate avenue cable |
| 2933 | Estate avenue poles: 'estate avenue telephone pole climb' | trunk | 6 | 6 | match | estate avenue telephone pole climb |
| 2971 | Estate front oaks: 'estate oak living utility bridge' | bridge | 2 | 2 | match | estate oak living utility bridge |
| 3385 | Park: 'park footbridge' | bridge | 1 | 1 | match | park footbridge |
| 3419 | Park perches: 'park high watch perch' | lookout | 3 | 3 | match | park high watch perch |
| 3432 | Park phone wires: 'north park phone wire', 'park branch-side phone wire' | wire | 2 | 2 | match | north park phone wire; park branch-side phone wire |
| 3441 | Park: 'high park tree to phone line' | wire | 1 | 1 | match | high park tree to phone line |
| 3562 | Cemetery: 'cemetery crypt roof' | roof | 1 | 1 | match | cemetery crypt roof |
| 3667 | Community garden: 'garden wheelbarrow watch perch' | lookout | 1 | 1 | match | garden wheelbarrow watch perch |
| 4306 | addHouseGutters(): 'house downspout' | trunk | 24 | 24 | match | house downspout |
| 4313 | addHouseGutters(): 'gutter to roof' | bridge | 24 | 24 | match | gutter to roof |
| 9532 | buildTreehouse(): 'treehouse ladder' | trunk | 1 | 1 | match | treehouse ladder |
| 9551 | buildTreehouse(): 'treehouse floor' | lookout | 1 | 1 | match | treehouse floor |
| 9556 | buildTreehouse(): 'treehouse deck' | lookout | 1 | 1 | match | treehouse deck |
| 9903 | Westside poles: `Westside telephone pole ${i}` | trunk | 7 | 7 | match | Westside telephone pole 0; Westside telephone pole 1; Westside telephone pole 2 |
| 9911 | Westside lines: `Westside overhead phone line ${i}` | wire | 6 | 6 | match | Westside overhead phone line 1; Westside overhead phone line 2; Westside overhead phone line 3 |
| 10073 | Police station: 'police roof' | roof | 1 | 1 | match | police roof |
| 13740 | makeBridgeTower(x): 'River bridge tower downspout' | trunk | 2 | 2 | match | River bridge tower downspout |
| 13745 | makeBridgeTower(x): 'River bridge tower gallery' | roof | 2 | 2 | match | River bridge tower gallery |
| 13762 | makeRiverBridge(): `River bridge stone parapet north\|south` | fence | 2 | 2 | match | River bridge stone parapet north; River bridge stone parapet south |
| 13783 | makeRiverBridge(): `River bridge suspension cable ${side}` | wire | 2 | 2 | match | River bridge suspension cable -1; River bridge suspension cable 1 |
| 13898 | riverBuilding(): `Bellwether roof · ${label}` | roof | 30 | 30 | match | Bellwether roof · THE OLD ANCHOR; Bellwether roof · QUAYSIDE BOOKS; Bellwether roof · WILLOW BAKERY |
| 13902 | riverBuilding(): `Bellwether downspout · ${label}` | trunk | 30 | 30 | match | Bellwether downspout · THE OLD ANCHOR; Bellwether downspout · QUAYSIDE BOOKS; Bellwether downspout · WILLOW BAKERY |
| 13903 | riverBuilding(): `Bellwether gutter to ridge · ${label}` | roof | 30 | 30 | match | Bellwether gutter to ridge · THE OLD ANCHOR; Bellwether gutter to ridge · QUAYSIDE BOOKS; Bellwether gutter to ridge · WILLOW BAKERY |
| 14086 | makeRiverTown(): 'Bellwether bunting line' | wire | 28 | 28 | match | Bellwether bunting line |
| 14808 | makeGalleria(): 'Galleria downspout' | trunk | 2 | 2 | match | Galleria downspout |
| 14809 | makeGalleria(): 'Galleria rooftop' | roof | 2 | 2 | match | Galleria rooftop |
| 15184 | makeAppleTree(x,z,index): `APPLE ${n} trunk` | trunk | 12 | 12 | match | APPLE 1 trunk; APPLE 2 trunk; APPLE 3 trunk |
| 15206 | makeAppleTree bough: `APPLE ${n} bough ${i+1}` | branch | 72 | 72 | match | APPLE 1 bough 1; APPLE 1 bough 2; APPLE 1 bough 3 |

## Connectivity (derived by the tool, `graph.json`)

- Islands by the 1.7 u sample rule: **149** (spec: 149); largest island **563** routes (spec: 563); singletons 40 (spec: 40 leap-only).
- Endpoint auto-links (end windows t <= 0.07 / t >= 0.93, gap <= 0.48 u, trunks only from bridges): 1337 route ends with at least one candidate; branch tips with a link: 0 (spec: 0 of 715).
- Island sizes (top 10): 563, 71, 55, 15, 13, 13, 12, 12, 11, 11

## What was captured

| file | bytes | sha256 |
|---|---|---|
| `data/harvest/routes.json` | 824309 | d34675124e7f03e6 |
| `data/harvest/route_samples.json` | 4152141 | 1f089164e07181c7 |
| `data/harvest/route_index.json` | 855698 | 6b528e975101a7fb |
| `data/harvest/forks.json` | 296628 | 1f1a3c2866cb379d |
| `data/harvest/trees.json` | 30861 | 7a53d807fb5a7ece |
| `data/harvest/utility.json` | 34452 | 807c990659b2b55d |
| `data/harvest/nests.json` | 5835 | fb4728a3868e6a96 |
| `data/harvest/apple_trees.json` | 4994 | 6e85f4974865ff24 |
| `data/harvest/houses.json` | 27862 | 44259f383c8cf811 |
| `data/harvest/colliders.json` | 14183 | cc6fce0b5277a93e |
| `data/harvest/world.json` | 9943 | 3d39bf35b83f1782 |
| `data/harvest/vehicles_initial.json` | 37877 | c11e5f624516de73 |
| `data/harvest/fauna.json` | 12011 | 082e6ef1b6a35393 |
| `data/harvest/peppers_nondeterministic.json` | 14500 | 46f957376b084e63 |
| `data/harvest/graph.json` | 444486 | 0462b82931e082ca |
| `data/harvest/manifest.json` | 17528 | 70fa917560d34c79 |

- `routes.json`: every route in creation order: id, name, kind, speed, center, surfaceRadius, visualOffset, length, indexed, trunkClearance, control points, sample count, call site (line in `v5_4_game.js`, function).
- `route_samples.json`: the game's own `getSpacedPoints` output per route (the 81,613 index samples).
- `route_index.json`: the `routeSpatial` cells (8 u) with `[routeId, sampleIndex]` entries in insertion order.
- `forks.json`: `canopyForks` (95 trunks) with per-fork t, height, origin, outward and the branch's trunkClearance.
- `trees.json`: `trees[]` (95, apple trees included) plus the spec tables (`treeSpec`, `giantTreeSpecs`, `outerTreeCandidates`), giant perches, estate gate tree tips and Westside trees.
- `utility.json`: the 110 `utilitySupports` (residential 97, estate 6, westside 7) with tops and the trunk route of each residential pole; wire route ids.
- `nests.json`, `apple_trees.json`: the 24 nests (route, point) and 12 apple trees.
- `houses.json`: the 24 `houses[]` records (cfg, w, d, frontZ, backZ, frontSign), the `outerHomes` table, `commercialBounds`, `houseDoors`, `riverBuildings`.
- `colliders.json`: `obstacles`, `fenceCollisions`, `mallColliders`, `estateProjects`.
- `world.json`: BuildInfo, WORLD_HALF, RIVER, the 48 registered pavement zones, concealment (hedge patches, garden), Tabasco plants, actor counts.
- `vehicles_initial.json`, `fauna.json`: vehicle and animal registries at the dump point (before the first tick).
- `graph.json`: derived islands and end links (not game state).
- `manifest.json`: pin, environment, seeds, run logs, determinism, counts and file hashes.

## Caveats

- The instrumented copy differs from the pinned HTML in exactly two places: `addRoute` is wrapped to record its call site, and a dump runs after `rebuildCanopyForks()` and before `tick()`. No game value is changed; the dump reads registries only.
- External assets (fonts, HDRI, bark textures, jsdelivr loaders) are blocked; the game tolerates that (Promise.allSettled) and world construction does not depend on them.
- `trees[]` contains the 12 apple trees, so 95 is the total with apples (matches `wildlife.json`).
- Vehicles are captured before the first `tick()`, so moving vehicles are at their spawn poses.
- Chili peppers are random per load (crypto seed) and are flagged, not harvested.
