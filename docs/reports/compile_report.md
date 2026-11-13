# Compile report: authored data -> `generated/`

Generated 2026-11-13T19:19:40.588416449+00:00 by `tools/compile` (Lune lune 0.11.1). Command: `lune run tools/compile/main.luau compile` (see `tools/compile/README.md`). Staleness gate: `lune run tools/compile/main.luau check`.

## Inputs

- Authored data: `data/authored/**` (HTML units), migrated once from `spec/data/*.json` by `lune run tools/compile/main.luau migrate` and validated against `data/schema/*.schema.json`.
- Harvest: `data/harvest/routes.json` and `forks.json` pinned to HTML SHA-256 `fc48b387e51ce3a454898d58d1cb3dda891b22ffad7110cdcd0ade6c777a6227`.
- Unit conversion: every number the schemas mark `x-unit: u` or `u/s` is multiplied by 2.5 on the shortest decimal representation (so 18.04 u becomes exactly 45.1 st); angles, seconds and counts are untouched. Nested v5.4 constant blocks in the wildlife files that the schemas do not annotate stay in HTML units and are emitted under `htmlUnits` keys.

## Count comparisons

| what | expected | actual | status | note |
|---|---|---|---|---|
| catalogue L15184 makeAppleTree(x,z,index): `APPLE ${n} trunk` | 12 | 12 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L1830 makeTree bough: `${spec.name} bough ${i+1}` | 295 | 295 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L1782 makeTree(spec): `${spec.name} trunk` | 32 | 32 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L13745 makeBridgeTower(x): 'River bridge tower gallery' | 2 | 2 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L3667 Community garden: 'garden wheelbarrow watch perch' | 1 | 1 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L10073 Police station: 'police roof' | 1 | 1 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L14809 makeGalleria(): 'Galleria rooftop' | 2 | 2 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L14086 makeRiverTown(): 'Bellwether bunting line' | 28 | 28 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L1896 makeTree living bridge: `${spec.name} living bridge to utility wire` | 15 | 15 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L14808 makeGalleria(): 'Galleria downspout' | 2 | 2 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L13903 riverBuilding(): `Bellwether gutter to ridge · ${label}` | 30 | 30 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L13902 riverBuilding(): `Bellwether downspout · ${label}` | 30 | 30 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L1329 woodenFence(): 'cedar fence top' | 4 | 4 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L3562 Cemetery: 'cemetery crypt roof' | 1 | 1 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L907 Corner shops roof (top-level) | 1 | 1 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L2428 makeLookoutTree(spec,index): `${name} giant trunk` | 3 | 3 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L854 Fuel canopy service ladder (top-level) | 1 | 1 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L13762 makeRiverBridge(): `River bridge stone parapet north\|south` | 2 | 2 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L1627 pole(x,z): `telephone pole climb ${x.toFixed(2)},${z.toFixed(2)}` | 97 | 97 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L794 Gas station shop roof (top-level) | 1 | 1 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L9532 buildTreehouse(): 'treehouse ladder' | 1 | 1 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L9551 buildTreehouse(): 'treehouse floor' | 1 | 1 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L15206 makeAppleTree bough: `APPLE ${n} bough ${i+1}` | 72 | 72 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L2458 makeLookoutTree bough: `${name} high lookout bough ${j+1}` | 21 | 21 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L9911 Westside lines: `Westside overhead phone line ${i}` | 6 | 6 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L9903 Westside poles: `Westside telephone pole ${i}` | 7 | 7 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L9556 buildTreehouse(): 'treehouse deck' | 1 | 1 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L2478 makeLookoutTree perch: `${name} OPEN SKY LOOKOUT` | 6 | 6 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L2748 estateMansion(): 'grand estate main roof' | 2 | 2 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L832 Fuel canopy east-west walk (top-level) | 1 | 1 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L1926 makeTree rooftop crossing: `${spec.name} rooftop canopy crossing` | 10 | 10 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L2674 estateCourt(): 'estate tennis net top' | 2 | 2 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L2142 buildOuterHome unrotated: 'neighborhood rooftop ridge' | 11 | 11 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L2859 estateGateOak bough: `estate oak major bough ${j}` | 24 | 24 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L13740 makeBridgeTower(x): 'River bridge tower downspout' | 2 | 2 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L4313 addHouseGutters(): 'gutter to roof' | 24 | 24 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L2351 makeOuterTree bridge: `outer ${index} canopy-to-wire bridge` | 25 | 25 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L4306 addHouseGutters(): 'house downspout' | 24 | 24 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L13898 riverBuilding(): `Bellwether roof · ${label}` | 30 | 30 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L2258 makeOuterTree bough: `outer ${index} bough ${j}` | 303 | 303 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L3441 Park: 'high park tree to phone line' | 1 | 1 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L3385 Park: 'park footbridge' | 1 | 1 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L733 Chili's restaurant rooftop (top-level, commercial district) | 1 | 1 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L837 Fuel canopy crosswalk (top-level) | 1 | 1 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L2695 estateGuest(): 'estate guesthouse roof' | 2 | 2 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L1650 stringUtilityRoute(name,a,b): 'east–west utility wire' / 'north–south telephone wire' / 'commercial utility span' | 102 | 102 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L2971 Estate front oaks: 'estate oak living utility bridge' | 2 | 2 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L2933 Estate avenue poles: 'estate avenue telephone pole climb' | 6 | 6 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L3432 Park phone wires: 'north park phone wire', 'park branch-side phone wire' | 2 | 2 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L1679 House service drops: 'house service cable' | 4 | 4 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L2922 Estate avenue: 'estate avenue cable' | 5 | 5 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L3419 Park perches: 'park high watch perch' | 3 | 3 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L1354 chainFence(): 'chain-link fence top' | 4 | 4 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L2240 makeOuterTree(spec,index): `outer ${index} tree trunk` | 44 | 44 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L2136 buildOuterHome rotated: 'neighborhood rooftop ridge' | 9 | 9 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L1237 buildHouse ridge: `${cfg.kind} ridge` (four original houses) | 4 | 4 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L2835 estateGateOak(): 'estate oak trunk' | 4 | 4 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L863 Fuel ladder roof link (top-level) | 1 | 1 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L1453 trampoline(): 'trampoline guardrail' | 1 | 1 | match | routes created at this addRoute line (harvest callSite) |
| catalogue L13783 makeRiverBridge(): `River bridge suspension cable ${side}` | 2 | 2 | match | routes created at this addRoute line (harvest callSite) |
| lots (90 core + 153 districts) | 243 | 243 | match |  |
| lot districts | 11 | 11 | match |  |
| roads | 116 | 116 | match |  |
| lanes | 25 | 25 | match |  |
| cast entries | 87 | 87 | match |  |
| route generators in the catalogue | 60 | 60 | match |  |
| catalogue instance total | 1332 | 1332 | match |  |
| harvest routes | 1332 | 1332 | match |  |
| addRoute lines used by the harvest | 60 | 60 | match |  |
| harvest fork trunks | 95 | 95 | match |  |
| trees (authored list) | 95 | 95 | match |  |
| trees matching the harvest by (x,z) within 0.005 | 95 | 95 | match |  |
| apple trees | 12 | 12 | match |  |
| nests | 24 | 24 | match |  |
| nut caches | 10 | 10 | match |  |
| deer | 5 | 5 | match |  |
| insects | 30 | 30 | match |  |
| hollow proposals (premium + knothole) | 11 | 11 | match |  |
| lot types (one per v5.4 type in the data) | 74 | 74 | match |  |
| FRB homes with interior templates (W1; 40 from W3) | 4 | 4 | match |  |
| interior templates | 4 | 4 | match |  |
| hospital brief rooms (brief v2: 8) | 8 | 8 | match |  |
| hospital stations (W1 v0) | 4 | 4 | match |  |
| police player-car pads | 2 | 2 | match |  |
| police AI cruiser pads | 1 | 1 | match |  |
| claimable hollows (brief v2 §3) | 12 | 12 | match |  |
| premium hollows | 2 | 2 | match |  |
| escape hollows | 1 | 1 | match |  |
| single-chamber hollows | 9 | 9 | match |  |
| lots whose params were validated against a paramSchema | 73 | 73 | match |  |
| attraction routes (data/attractions.json) | 9 | 9 | match |  |
| expansion venues (data/expansion.json) | 46 | 46 | match |  |
| tree art models (data/art/tree_meshes.json) | 95 | 95 | match |  |

## Lots per district

| district | lots | with footprint | with facing or yaw | interiors |
|---|---|---|---|---|
| bellwether_galleria | 14 | 14 | 9 | 11 |
| bellwether_quay | 59 | 59 | 36 | 0 |
| east_commercial | 26 | 25 | 20 | 0 |
| hospital_spur | 13 | 13 | 13 | 10 |
| north_cemetery | 2 | 2 | 2 | 0 |
| north_gardens | 6 | 5 | 5 | 1 |
| north_park | 17 | 17 | 12 | 0 |
| old_town_core | 18 | 18 | 7 | 4 |
| old_town_outer | 66 | 66 | 61 | 1 |
| south_estates | 12 | 12 | 6 | 0 |
| westside | 10 | 10 | 10 | 4 |

Distinct lot types: 74 (ambient_npcs, ambulance_bay, atrium, backyard_doghouse, backyard_pool, backyard_prop, backyard_trampoline, bridge, bridge_tower, cemetery, chapel_crypt, community_garden, detail, district_ground, dock, doghouse, duct, estate_mansion, estate_parcel, estate_pool, fence_run, footbridge, fountain, garden, gas_canopy, gas_station, gazebo, guesthouse, hospital, house, intersection, landmark_tower, lawn, mall, mall_shop, market_stall, mezzanine, observation_room, overhead_lines, park, parking, path, pergola_summer_kitchen, playground, plaza, police_station, pond, porte_cochere, quay_building, reception, restaurant, restaurant_icecream, river, roof, sewer, shed, shelter, shelter_house, shop, shrub_cluster, sign, sports_field, stair, storage_units, stream, street_furniture, supply_room, tennis_court, transit_stop, treatment_ward, tree, treehouse, triage_bay, waiting_room).

## Validation and invariants

- Schema validation: 24 file(s), 0 error(s).
- Invariants checked: 8531, failed: 0.
- warning: 8 lane(s) reference no road id (yard glides, verges, templated routes): kept with roadNote only
- warning: duplicate cast names (ids disambiguated with their source line): Avery, Sam

## Generated modules (`generated/`, Rojo: `ReplicatedStorage.Shared.Generated`)

| module | records | bytes | require (ms, Lune) | source |
|---|---|---|---|---|
| Lots | 243 | 190158 | 6.6 | data/authored/town/lots/*.json |
| Roads | 116 | 41940 | 1.6 | data/authored/town/roads.json |
| Lanes | 25 | 18253 | 1.2 | data/authored/town/lanes.json |
| Cast | 87 | 71807 | 1.6 | data/authored/cast/cast.json |
| RoutesCatalog | 60 | 41830 | 1.2 | data/authored/routes/catalog.json |
| Wildlife | 95 | 61201 | 3.6 | data/authored/wildlife/*.json |
| Routes_01 | 391 | 204760 | 11.1 | data/harvest/routes.json (chunk 1 of 4; pinned to v5.4 HTML SHA-256 fc48b387e51ce3a454898d58d1cb3dda891b22ffad7110cdcd0ade6c777a6227) |
| Routes_02 | 447 | 204694 | 9.7 | data/harvest/routes.json (chunk 2 of 4; pinned to v5.4 HTML SHA-256 fc48b387e51ce3a454898d58d1cb3dda891b22ffad7110cdcd0ade6c777a6227) |
| Routes_03 | 413 | 205046 | 9.0 | data/harvest/routes.json (chunk 3 of 4; pinned to v5.4 HTML SHA-256 fc48b387e51ce3a454898d58d1cb3dda891b22ffad7110cdcd0ade6c777a6227) |
| Routes_04 | 81 | 36112 | 1.9 | data/harvest/routes.json (chunk 4 of 4; pinned to v5.4 HTML SHA-256 fc48b387e51ce3a454898d58d1cb3dda891b22ffad7110cdcd0ade6c777a6227) |
| Forks | 95 | 193316 | 8.6 | data/harvest/forks.json (canopyForks; pinned to v5.4 HTML SHA-256 fc48b387e51ce3a454898d58d1cb3dda891b22ffad7110cdcd0ade6c777a6227) |
| LotTypes | 0 | 23026 | 1.5 | data/authored/lot_types.json |
| Interiors | 0 | 11610 | 1.1 | data/interiors/*.json |
| Buildings | 0 | 6132 | 0.7 | data/buildings/*.json |
| HarvestPatches | 0 | 12240 | 0.5 | data/harvest_patches.json |
| Population | 0 | 3184 | 0.5 | data/population.json |
| Hollows | 0 | 6284 | 0.7 | data/hollows.json |
| TerrainExtensions | 0 | 2379 | 0.4 | data/terrain_extensions.json |
| Lighting | 0 | 1163 | 0.3 | data/authored/town/lighting.json |
| Attractions | 9 | 33254 | 1.8 | data/attractions.json |
| Expansion | 46 | 138283 | 18.4 | data/expansion.json |
| TreeArt | 95 | 176791 | 9.6 | data/art/tree_meshes.json |
| Index | 1 | 1714 | 0.5 | tools/compile (module list, counts and the harvest pin) |

Total 23 files, 1685177 bytes; largest Routes_03 (205046 bytes, 9.0 ms to require under Lune). Routes are chunked at about 200 KB per module; `Index.luau` lists the chunks and counts.

## Notes for the lead

- `default.project.json` already maps `generated` to `ReplicatedStorage.Shared.Generated`; the `Data` accessor (W1) reads `Index.luau` and requires each chunk by name.
- Lot types are not yet authored (`data/lot_types/` is W1); lots carry the v5.4 `type` string and the compiler reports the distinct set above. Invariant 1 (paramSchema) therefore does not run yet.
- Routes carry `generator = <function>@L<line>` from the harvest call site and `origin = "harvest"`; `lotId` assignment and `harvest_patches.json` are W1 (BUILD_PLAN 4.4).
- The migration is re-runnable (`migrate`) and checkable (`migrate --check`); once hand edits begin in `data/authored`, stop re-running `migrate`.
- `check` writes to `build/compile-check/` (gitignored) and diffs against `generated/`; wire it into `tools/ci.sh` after the unit tests.
- Generated files are StyLua-formatted (repo `stylua.toml`) and excluded from Selene by `selene.toml`.
- Authored data lives under `data/authored/` (the path assigned to this task); BUILD_PLAN 1.2 names `data/town/`, `data/cast/`, `data/wildlife/` directly under `data/`. Moving the directories means changing the paths in `tools/compile/main.luau` and the `$schema` relative links; nothing else depends on them.
- `data/harvest/` (6.6 MB) and `tests/golden/` (11 MB) are machine output; consider Git LFS rules for `*.json` under those two directories if the repository size matters.
