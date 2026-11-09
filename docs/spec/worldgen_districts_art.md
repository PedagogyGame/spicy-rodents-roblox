# Worldgen Part 2: Later Districts, Scenery, Backdrop and Art Direction

Extractor: `worldgen_districts_art`. Source of truth: `reference/v5_4_game.js` (v5.4, "River & Old Town", three.js 0.160.1, `BuildInfo` line 97). Every line number below refers to that file.

Companion data: `spec/data/lots_districts.json` (153 lots, same schema as `lots_core.json`). It holds the Bellwether Quay, the Bellwether Galleria, the hospital rooms, the v3.5 environment-pass shrubs and fences, and all 59 `addDetail` neighborhood objects. To avoid duplicate ids, these items stay in `lots_core.json` and are only cross-referenced here: `hospital_main`, `outer_treehouse`, `skyline_radio_tower`, `skyline_cell_tower`, `outer_icecream_standalone`, `outer_icecream_strip`, `outer_stream`, `core_garden_plot_a/c`, `outer_garden_plot_b`. The Quay approach road and the bridge deck are in `roads.json` (`rd_030`..`rd_033`).

## 0. Conventions

- **Units.** HTML world units. Brief section 2 maps 1 unit to about 2.5 studs. Key numbers also carry a stud value in brackets, for example "deck y 15.8 [39.5 st]". +Y is up.
- **Axes and facing.** A three.js `rotation.y = r` turns local (0,0,1) into world (sin r, 0, cos r). Quay buildings put their front on local -Z, so front = (-sin r, 0, -cos r). The `facing` value in the JSON is the world axis the front (door or sign) faces. `footprint.w` is the extent along world X and `footprint.d` the extent along world Z, after rotation.
- **Roblox models face +Z** (brief). A Quay building authored front-to-+Z needs yaw = r + PI to match the HTML.
- **"(inferred)"** marks values derived by reading the code rather than stated in it, such as room boundaries or footprints from part sizes.
- **Global world clamp.** `player.pos.x` is clamped to -586..1146 and `z` to -560..436 (6765-6766; `NORTH_LIMIT = 440` at 3271; `RIVER.endX = 1150`). That is about 4330 x 2490 studs.

## 1. District map and HUD names

| District | Bounds (HTML) | Owner here | HUD tag (`#districtTag`) |
|---|---|---|---|
| Hospital spur | building centre (-356, 353), 94 x 96; district test `x < -270 && z > 245` | rooms, layout | `HOSPITAL DISTRICT`, `HOSPITAL · EMERGENCY` (inside), `HOSPITAL · DUCTS` (9062) |
| Bellwether Quay | x 687..1150, z -244..443 (`inRiverDistrict` 439) | yes | `BELLWETHER QUAY · RIVERSIDE OLD TOWN`, or `WILLOW RIVER · STONEBRIDGE` over water (14160) |
| Bellwether Galleria | mall 1063..1141 x 284..392; plaza 1061..1145 x 234..415 | yes | `BELLWETHER GALLERIA · SHOPS & ATRIUM`, `· UPPER GALLERY`, `· WISHING FOUNTAIN` (15041) |
| Other tags (core) | `p.z > 303 && p.x < 150` → `SYCAMORE PARK`; `p.z > 303 && p.x > 270` → `CEDAR REST · GRAVEYARD`; `p.z > 295` → `NORTHERN GARDENS`; `p.x > 280` → `COMMERCIAL DISTRICT`; else `OLD TOWN`; sewer → `UNDERGROUND · SEWER` (9062-9078) | n/a | |

Tag precedence: `updateNewSystems` (inside `updateGameplay`) sets the base tag. `updateRiverDistrict` and `updateMall` (inside `updateScenery`, which runs later in the frame) then overwrite it when the player is in their areas (15970-15982). This tag table is the natural source for the town-map labels in Addendum A1.

**Visibility culling.** The whole Quay group is visible only while `player.pos.x > 610` and the player is not in the hospital or sewer (14144). The mall group is visible within 190 of the mall centre, or while `atMall()` is true (`inMall` pad 24, or within 18 of the fountain) (15028).

---

## 2. Hospital building: footprint and room layout (3800-4525)

Mechanics such as staff AI, treatment, infection and the duct chase belong to another extractor. This section covers geometry only.

### 2.1 Shell

| Item | Value | Line |
|---|---|---|
| Centre | `HOSP_X = -356`, `HOSP_Z = 353`; `HOSP_BASE = terrainHeight(-356,353)` ≈ 0.10; `HOSPITAL_FLOOR = HOSP_BASE + 0.42` ≈ 0.52 | 3802-3809 |
| Footprint | `HOSP_W = 94` (X) x `HOSP_D = 96` (Z) [235 x 240 st] | 3804 |
| Front | local -Z (world z = 305), faces the road at z 283. It is `-Z` in the lots file | 3829-3845 |
| Plinth / floor | 97 x 0.8 x 99 plinth (#abb4ac); floor slab 94 x 0.18 x 96 (#b9c4ba), top at local 0.66 | 3821-3822 |
| Exterior walls | 1.2-thick side walls x 12 tall (#e6e5db); back wall 94 x 12 x 1.3; front wall = two 35.5-wide segments at x ±29 plus a lintel 19 x 5 at y 10 → structural opening 22.5 wide x 7.5 tall | 3824-3833 |
| Side windows | glass 0.08 x 4.3 x 9.1 at y 5.4, local z -34, -14, 12, 31, both sides | 3826-3828 |
| Front doors | two hinged glass leaves (7.55 x 7.6) pivoting at x ±8.2, z -48.67; open angle `-side*open*1.36` rad | 3834-3844, 8429 |
| Entrance canopy | 22 x 0.75 x 7.3 (#4a6b69) at y 8.1, z -51; two steel columns r 0.3 x 7.5 at x ±9, z -54 | 3845-3846 |
| Roof | slab 97 x 0.75 x 99 (#718c90) at y 12.8; hidden while the player is inside or in the duct (`updateHospital` 9041). It is a **landing surface** at `HOSP_BASE + 13.34` (6137-6143). No climb route is registered on the building | 3847, 8448 |
| Ceiling lights | 12 unlit glow panels 8 x 3.4 at y 11 (x -34,-12,14,33 × z -21,5,30) | 3848-3852 |

### 2.2 Room and zone map (local coordinates; world = (-356 + x, 353 + z))

The hospital is one large hall divided by partitions. Rooms are zones bounded by partitions and signs; most boundaries are **(inferred)**.

```
 z=+48  ┌──────────── back wall ────────────────────────────┐
        │ SUPPLIES (racks x-42/-36)      │ OBSERVATION       │  ← screens z=43: x -35..-9 and x 14..40 (h 4.6)
 z=+43  │----------------         ------------------         │
        │  BAYS 5-8: beds x -33,-11,11,33 @ z 35             │
        │  BAYS 1-4: beds x -33,-11,11,33 @ z 15             │  TREATMENT WARD (sign 0,9)
 z=+2   │====(low wall 5.0)          ·          (low wall)====│  ← x -46.5..-29.5 and 27.5..46.5
        │ RECEPTION desk (-18,-3)    ·   CHECK-IN desk (18,-3) │
 z=-12  │══════ wall ════════╗   24-wide opening   ╔═════ wall ══│  ← x -46..-12 and 12..46 (h 6.7)
        │ W TRIAGE BAY      ║   WAITING / ENTRY   ║ E TRIAGE BAY │  ← partitions x ±22, z -44.5..-23.5
 z=-48  └──────────── front wall ── [doors x ±8.2] ─────────┘
                         canopy z -51, columns z -54
```

| Zone (lots id) | Local bounds | Contents (line) |
|---|---|---|
| Waiting / entry (`hosp_lobby_waiting`) | x -22..22, z -48..-12 | Seats 5 x 0.5 x 2.1 with blue backs at x -14, 16 and z -35, -18 (3853). Teal spine stripe 3.4 wide on x=0, z -33.5..33.5. Dashed markers every 7. Guide stripes at x ±8.3 (3889-3911). Signs `EMERGENCY ENTRY` (0,-39), `EXIT` (0,-44), `WAITING / TRIAGE` (0,-17) |
| West / east triage bays | x ±(22..47), z -48..-12 | Triage benches at (-32,-26), (-31,-22), (32,-27), (32,-23) (3992). Wheeled carts at (-31,-17), (31,-18). Potted plants at the corners (3913). Duct entrance grille at (-38,-12) |
| Reception / check-in (`hosp_reception_checkin`) | x -47..47, z -12..2 | Nurse desk 12 x 2.2 x 3.2 at (-18,-3) and check-in desk at (18,-3) (3858-3863). 5 chart cubbies with monitors at z=-7. Intake desks at (±18, 2) (4018). 6 tall wall screens at x ±43.5, z -8/5/18 (4029). Stretchers at (-33,-1), (28,3) (4064) |
| Treatment ward bays 1-4 / 5-8 | x -47..47, z 2..43 (split at z≈25, inferred) | 8 beds 7 x 0.7 x 11 at x -33,-11,11,33 × z 15, 35. Each bed has a translucent curtain at x+4.1, a wall monitor, an IV pole and a surgical lamp at y 10.7 (3956-3984). Tan cross-aisle stripe 69 x 2.6 at z 5.9. Signs `TREATMENT WARD`, `BAYS 1 - 4` (-24,11), `BAYS 5 - 8` (23,31). A third wheeled cart sits at (39,7) (3946-3950) and a third stretcher at (-18,33) (4065-4069) |
| Supplies (inferred) | x -47..-9, z ~37..48 | 2 shelving racks at x -42, -36 (z 40), 4 shelves each with 3 coloured boxes per shelf = 24 boxes (3931). Sign `SUPPLIES` (-31,42) |
| Observation (inferred) | x 9..47, z ~37..48 | Sign `OBSERVATION` (26,42). Plant at (40,39). Otherwise empty |
| Ambulance bay | drive x=-356, z 284..305, 8 wide | The ambulance drives west on z=283 at 12.5 u/s, turns north at x=-356, parks at z=295 for 16 s, then hides for 145 s (8990-9030) |

Collision: `innerWall` registers each partition as an AABB in `hospitalObstacles` (3867). Furniture colliders cover the two desks (12.5 x 3.8) and the 8 beds (7.3 x 11.3) (3968-3984).

Interior camera: the camera is clamped to the building interior inset by 1.8, and to y floor+0.22..floor+11.2 (7363-7366).

Interior render: camera far plane 125, fog lerps toward near 15 / far 53, background #455c5b, exposure 1.12 (9115-9131, 13232).

### 2.3 Entering and leaving (layout-relevant parts only)

- **Enter.** Press E within 8 of (-356, 298) while within 4 of ground height. This starts a 1.45 s smoothstep glide to inside (-356, floor+0.2, 314) (8484-8494, 8561). `inHospital` flips at 47 % progress.
- **Exit.** Press E within 6 of `hospitalExit` (-356, 312) to glide to (-356, ground, 294).
- **Doors.** They auto-open when the player is within 15 of (-356, 305), with hold timers of 1.5, 2.4 and 4.0 s (8429-8453).
- **Not seamless.** The HTML uses a modal "inside hospital" state with its own fog, camera and roof hiding. It does not use a walk-through door.

### 2.4 Duct network (geometry)

Nodes in local x, z with height above the floor (4076-4084): (-38,-12, 2.8) → (-9,-12, 2.8) → (-9, 25, 2.8) → (30, 25, 2.8) → (30, 29, 4.2) → (30, 36, 7.6) → (11, 36, 7.6).

- **Tube.** Square section, 2.7 wide x 1.76 tall. The floor is opaque (#7e9291) and the walls and ceiling are see-through (opacity 0.29). Ribs every 5, warm strip lights every 8.
- **Hatch hole.** The final segment has a real 3.1-long hole above the hatch (4153-4178).
- **Vents** (4119-4125). Four low wall grilles 2.6 x 1.3 sit at the first four nodes; the first is rotated 90°. One overhead hatch 2.7 x 2.9 at (11, 36, h 7.6) has a gold edge strip (#d5b25f). Glow accent balls sit at nodes 2, 3, 4, 6, 7 (4206).
- **Landing reticle.** When the hatch is open, a landing ring is drawn 4 units ahead of the hatch on the floor (4212-4251).

### 2.5 Hospital signs

| Sign | Placement | Line |
|---|---|---|
| `HOSPITAL  ·  EMERGENCY` | billboard 35 x 2.65 (#335f67 / #f8fbf7) above the roofline, y base+14.35, z 303.5 | 4035 |
| `SQUIRREL BITES  →` | 13.5 x 1.3 (#9d4037) at (-345, base+9.25 ≈ 9.35, 303.2) | 4036 |
| `EMERGENCY ENTRANCE` | roadside at (-327, 299) | 4037 |
| `HOSPITAL  ←` | at the north cross road (-232, 298) | 4047 |
| Interior signs | 2.2 tall at y 6.5 (`signLocal` 3880) | 3880 |

`flatSign` (682) shrinks any text matching `PARK|CEMETERY|GARDEN|HOSPITAL|EMERGENCY ENTRANCE` to pedestrian wayfinding size: w 5.2..8.1, h 0.89..1.32, two posts, y = terrain+2.68. Signs matching `SQUIRREL BITES` or `HOSPITAL  ·` are excluded from the shrink.

### 2.6 HTML hospital vs brief section 9

| Brief section 9 room | v5.4 equivalent | Gap |
|---|---|---|
| Reception | nurse desk "RECEPTION" | exists |
| Triage | W/E triage bays plus "WAITING / TRIAGE" | exists, open-plan |
| Two wards | one 8-bed treatment ward (bays 1-4, 5-8) | split into Ward A and Ward B with a real wall |
| Isolation ward | none. The v1.0 comment (3987) mentions a "small central isolation curtain", but no such object exists in 3990-4033 | new |
| Pharmacy | none. The "SUPPLIES" racks are the nearest | new; the Addendum A2 fetch tasks need item shelves |
| Staff room | none | new |
| Ambulance bay | drive plus canopy (drop-off) | upgrade to a covered bay with stretcher route |
| Roof access (squirrel route) | roof is a landing surface only; no route | add a downspout / vent-stack climb route, and possibly a roof hatch into the ducts |

Recommendation (inferred): the 94 x 96 shell [235 x 240 st] has room for all of these if the back third (z 25..48) becomes Ward B, isolation, pharmacy and the staff room behind real walls. The ducts should stay as the cross-building squirrel route.

---

## 3. Bellwether Quay, the riverside old town (13427-14189, terrain 417-464)

### 3.1 Constants (`RIVER`, 419-435)

| Key | Value | Studs | Meaning |
|---|---|---|---|
| startX / endX | 687 / 1150 | 1718 / 2875 | district X range |
| zMin / zMax | -244 / 443 | | district Z range |
| centerX, meander | 850, `riverCenter(z) = 850 + 9 sin(0.009 z)` (436) | | channel centre line |
| halfWidth | 52 | 130 | water where `|x - centre| < 52` |
| bankY | 8 | 20 | quay and bank walking level |
| waterY | 2.4 | 6 | water surface |
| bedY | -2 | | channel floor |
| bridgeZ | 0 | | bridge centre line |
| deckY | 15.8 | 39.5 | bridge deck height |
| bridgeStart / End | 790 / 910 | | flat deck |
| rampStart / End | 744 / 956 | | approach ramps |

**Terrain** (`terrainHeight` 458). Outside the district the original hills apply. In the water the height is -2. On land, `original*(1-t) + 8*t` with `t = smoothstep(x, 687, 735)`, so the Quay is a flat plateau at y 8 from x 735 east.

**Deck** (`riverDeckAt` 445). Defined for `|z| ≤ 7.8` only. A linear ramp rises from 8 to 15.8 over x 744..790, the deck is flat to 910, and a ramp falls back to 8 at 956.

### 3.2 Ground, banks, water

- **Bank meshes** (`makeRiverBanks` 13547). Two 128 x 20 grids cover the whole district, west of and east of the channel. Both use **cobblestone** (`riverCobble` 13525: a 512² canvas of offset rounded stones, tint #c4bdab, roughness 0.97).
- **Grass overlays.** One at 1075..1149 x 82..425, y 8.01 (14042). One at 705..737 x 208..425 (14043).
- **Embankment walls** (13578). Stone #777b70, 1.3 thick x 7.8 tall, in 6-long segments following the meander on both sides, with a 1.9-wide light coping (#d1c7ae) at y 8.02.
- **Bank lamps** (13586). 34 in total, 17 per side, at z -218..394 step 34, skipping |z|<24, at `centre ± 55`. Each has an iron bollard 2.2 inboard and 7 along.
- **Lamp model** (`riverLamp` 13598). Iron post 4.1 tall, lantern box 0.42 x 0.67 with emissive #ffc66d at 1.2, pyramid cap. No real-time light.
- **Water** (`makeRiverWater` 13614). A 20 x 150 grid at y 2.4 with a custom shader:
  - vertex waves `0.10 sin(0.24x+0.08z+0.65t) + 0.035 sin(0.39z-0.8t)`;
  - colour = mix(deep #315c61, glint #b7d2c1, 0.13 + fresnel·0.28), plus "threads" `pow(max(0, sin·sin), 14)·0.16`, plus an edge brightening term.
- **Approach road.** Continues to the ramp: asphalt 650..744, |z|≤8, with cobble walks at z ±11 (13594-13596; in `roads.json`).

### 3.3 Stone bridge (`makeRiverBridge` 13754, `bridgeArch` 13657, `makeBridgeTower` 13698)

- **Arches.** Five, centred at x 802, 826, 850, 874, 898, each 24 wide. Inner radius 9.6, springing at y 3.5 so the crown is at 13.1. Body y 1..15.5, depth 15.7. 15 voussoir blocks per face (at z ±8): every third block (i%3==0) is dark #777b70, the rest light #d1c7ae (5 dark, 10 light) (13674-13686).
- **Cutwater piers.** Four-sided, r 2.3/3.0, 3.6 tall, at x 790, 814, 838, 862, 886; scaled ×3.2 along z and rotated 45°.
- **Deck.** Cobble groundPatch over x 744..956, |z| ≤ 7.8.
- **Parapets.** A stone tube at deck+1.1, z ±7.7. Registered as `kind: "fence"` routes named "River bridge stone parapet north/south". Posts 0.32 x 1.05 x 0.3 every 4 units, each with a 4 x 0.3 collider.
- **Suspension chains** (#4e7c87). A Catmull-Rom curve through (772,14), (814,34), (850,25), (886,34), (928,14) at z ±8.7. Registered as `kind: "wire"` routes. Vertical hangers drop to deck+0.7 between x 790 and 910 (45 samples). The code calls the silhouette "London-like".
- **Lamps.** 12 bridge lamps at x 752, 777, 838, 862, 925, 947 × z ±6.45.
- **Two towers at x 814 and 886** (group origin y = deck):
  - piers at z ±10.7, each 8 x 19 x 7.2, with a plinth, string courses at +3.5 / +9 / +14.5, and glass slit windows;
  - 4 corner turrets per pier (8 per tower; r .72/.86, 20.4 tall, at x ±3.7, z ±3.3 from the pier centre) with cone caps, and a pyramid roof cone per pier (r 5.5, h 4.5) whose apex sits at about y 39 [98 st];
  - an overhead arch 8 x 3.4 x 15.5 at deck+15.2, giving 13.4 [33.5 st] clearance;
  - colliders: piers 8.4 x 7.6 (y 15.8..35.1); arch 8 x 14 (y 29.2..33.2);
  - a red banner (#af5949) on the outer face, `sideForBanner(x) = x<850 ? -1 : 1`;
  - a copper downspout at (x+4.5, z=7), deck+0.25 → deck+17.7 (`kind: "trunk"`, surfaceRadius 0.15);
  - a "tower gallery" `kind: "roof"` route at y 33.5 from z 7 to z -7.
- **Ramp side faces** are solid: walking is blocked if `height < deck - 0.55` (`riverBlocked` 13488-13499).

### 3.4 Quay buildings (`makeQuayBuilding` 13826, placed in `makeRiverTown` 14019)

There are 30 buildings in 3 rows. All are **facades with solid colliders and climbable roofs; none has an interior.**

| Row | Placement | Yaw | Faces | Label rule |
|---|---|---|---|---|
| West quay (10) | x 758, z -162, -141, -120, -99, 63, 84, 105, 126, 147, 168 | -PI/2 | +X (toward river) | `labels[i]`, index i |
| East quay (12) | x 950 + (i%3)·2, z -166, -144, -122, -100, 62, 84, 106, 128, 150, 172, 194, 216 | +PI/2 | -X | `labels[(i+3)%12]`, index i+2 |
| Market row (8) | x 1008 + (i%2)·24, z -164, -118, -72, 91, 137, 183, 229, 275 | 0 or PI | -Z / +Z alternating | `labels[(i+7)%12]`, index i+6 |

Labels (14020-14033): THE OLD ANCHOR, QUAYSIDE BOOKS, WILLOW BAKERY, FERRY & FINCH, COPPER KETTLE, RIVER APOTHECARY, THE LANTERN, BRIDGE HOUSE, TIDE & TIMBER, THE COBBLER, WREN COTTAGE, THE TEA ROOM. Names repeat across rows; for example THE OLD ANCHOR appears 3 times.

**Generator rule** (index-driven, deterministic):

| Parameter | Formula | Range |
|---|---|---|
| width w (along front) | 15 + (index%3)·1.8 | 15, 16.8, 18.6 |
| depth d | 12 + (index%2)·2 | 12, 14 |
| wall height h | 10 + (index%4)·1.25 | 10 .. 13.75 |
| roof rise | 4 + (index%3)·0.6 | 4, 4.6, 5.2 |
| base | `terrainHeight(x,z)` | = 8 everywhere in the rows |
| plaster | ["#d8c6a1","#c0b9a0","#d7b399","#b9c2b0","#c9bda7"][index%5] | |
| roof | ["#6e635a","#505e63","#71695b","#72615b"][index%4] | |
| fascia bg | index odd → #405b51, even → #745547; text #f4e5bd | |
| awning | only when index%3==0: odd → #80987a, even → #b26d52 | |

Construction details:

- **Body.** Stone plinth (0.65), plaster box, and a **jettied upper storey** (+0.7 / +0.6 overhang, from about 0.53h).
- **Timber.** Dark-oak bands (#4e4136) at 0.9, 0.51h and h-0.2. Five vertical posts and two diagonal braces per long side give the Tudor half-timber look.
- **Roof.** Gabled, with the ridge along local X. Gable-end triangles have explicit coordinates (13796-13824).
- **Front.** 3 upper windows (1.45 x 2.0), 2 ground windows (2.5 x 2.6), an oak door 1.55 x 3.4 with a brass knob, a fascia sign w·0.8 x 0.95 at y 4.82, and flower boxes either side.
- **Chimney.** At local x = 0.27w.
- **Collider.** One AABB per building, (w+0.9) x (d+0.7) swapped when sideways, from base to base+h-0.05.
- **Roof landing** (`riverRoofAt` 13473). y = base + h + rise·max(0, 1 - |lz|/(d/2+0.65)) + 0.29, so the roof is a sloped landing surface.
- **Routes** (3 per building):
  - ridge, `kind: "roof"`;
  - copper downspout at the front-right corner, `kind: "trunk"`, r 0.14;
  - "gutter to ridge", `kind: "roof"`.
- **Draw calls.** Each building is merged with `batchTreeBranches`.

The full per-building table (position, world footprint, colours, ridge height) is in `lots_districts.json` (`quay_bldg_w_00`..`quay_bldg_m_07`).

### 3.5 Market square, clock tower, stalls

- **Clock tower** (`makeClockTower` 13911) at (1051, 35), base 8. Main parts:
  - plinth 13 x 1.1 x 13 and shaft 9 x 29 x 9 (#d1c7ae) up to y 37;
  - clock faces 3.6² on all four sides at world y 32, with **static hands**;
  - pyramid roof cone (r 8, h 8, y 37..45) and an iron spire to about y 48 [120 st].
  - Collider 9 x 9, y 8..37.
  - Its roof is a pyramidal walk platform, `37 + 8·max(0, 1 - chebyshev/5.66)`. No climb route reaches it.
- **Market stalls** (`marketStall` 13965). Five, at (996,-23), (1010,-23), (1024,-23), (994,42), (1007,42), y 8. Each has an oak counter 5 x 1.2 x 2.8, 4 posts 3.8 tall, a 7-strip canopy alternating #879e76/#b7785d with #dfd1a8, and 12 produce balls. Collider 5 x 2.8 x 1.3.
- **Square furniture** (14054). Iron lamps at x 978, 1010, 1092 × z -40, 68 (6 in total), each with an oak bench (3.6 x 0.45 x 1.3) at x+5.

### 3.6 Docks and boats (`quayDock` 13999, `makeMooredBoat` 13986)

There are three docks: `quayDock(-1, 208)`, `quayDock(1, -124)` and `quayDock(1, 290)`. Each dock:

- is an oak stage 14 x 0.5 x 7, deck at y 8, centred at `centre + side·46` (6 inside the embankment line at `centre ± 52`), so it spans `centre ± 39..53` and projects 13 into the water (its outer 1 unit overlaps the wall/coping);
- is a registered walk platform (`riverPlatforms`);
- stands on 4 pilings 7 tall.

Each dock has one moored boat at `dockX - side·8`, y 2.54:

- ellipsoid hull scaled 2.6 x 0.9 x 7, deck 4.1 x 9, mast 5, sail 2.9 x 2.1;
- yaw -0.2 (even boat index, hull #856854) or +0.22 (odd index, hull #526e68): docks 0 and 2 get -0.2, dock 1 gets +0.22;
- **animation**: bobs ±0.12 at 0.7 rad/s and rolls 0.026 rad (14147).

The boats cannot be boarded and do not move.

### 3.7 Trees, bunting, signs, ambient walkers

- **Willows.** Six "QUAY WILLOW" trees (`makeTree`, h 19, crown 9, 4 branches, 850 leaves, colours #769377/#95a580/#586f5b) at (715,-28), (715,43), (1004,79), (1108,52), (1094,192), (1015,370) (14064). They are climbable like every `makeTree`.
- **Bunting** (14081). 28 lines, 14 per side at z -180..340 step 40. Each runs from `centre ± 59` (y 14) via a y 12.6 midpoint to 23 units further out (y 15), and is registered as a `kind: "wire"` route. Each carries 7 flags (#b16c58 / #879a75) waving `0.1 sin(1.8t + phase)`.
- **Signs** (`riverSign` 14010): `BELLWETHER QUAY →` (650, 25, yaw -0.15), `WILLOW RIVER` (780, 38, yaw PI/2), `OLD TOWN MARKET →` (974, 20, yaw PI/2). Each is a post 3.2 tall with an 8 x 1.3 board (#304c44 / #f6e9bd).
- **Ambient walkers** (14102). Eight low-poly figures at x 778 (i<4) or 926, z -150/-45/60/165, pacing `z0 + 15 sin(0.095t + 1.3i)`. The code says explicitly that they are outside the combat, infection and emergency registries.

### 3.8 Surfaces, collisions and safety rules (state rules)

- **Ground height** (`getGroundAt` 6227, `squirrelSurfaceAt` 5283). `max(terrain, pavement)`, then raised to `riverSurfaceAt` (deck or dock platform) only if `player.y >= surface - 0.5`. This lets the player walk under the bridge without snapping up onto it.
- **Roof landing.** `roofSurfaceAt` (6111) includes `riverRoofAt` and treats `riverSurfaceAt + 0.18` as a roof.
- **Blocking** (`riverBlocked`). Colliders block when y0-0.25 ≤ height < y1-0.05, with 0.32 padding. Bridge-ramp side faces also block.
- **Water fall** (`recoverRiverFall` 14116). A state rule:
  - Condition: inside the water, not in hospital/sewer/duct, not on a rail, and y ≤ 2.85.
  - Action: teleport to the nearer bank at `centre ± 57`, y 8.18, z clamped to -225..425; zero velocity; grounded.
  - Feedback: flash "SPLASH!" and `fx(180,.18,"triangle",.035)` if the 2 s cooldown has elapsed.
- **First visit.** One-time flash "BELLWETHER QUAY · Explore the bridge, rooftops and riverside market." (14163).
- **Quick-start** (`startAtRiver` 14169). Spawn (780, 8.18, 51), yaw -0.94, pitch 0.3.

Interactions with other subsystems:

- the route registry (≈ 30×3 building routes, plus parapets, chains, tower downspouts and galleries, bunting);
- the camera, through ground and roof queries;
- the v5.4 orchard (`plantAppleTrees` 15273, owned by another extractor). Its third sector puts up to 4 apple trees in the Quay's south-east (candidates x 988..1108, z -214..-182; plus 1039,405 / 1051,362 / 733,373), with fill rows at z -226/-192. `appleSiteClear` excludes water and mall sites (15152);
- the `fx` audio;
- the HUD district tag.

No traffic, pedestrian AI, police or medics enter the Quay in v5.4 (inferred: none of those schedulers reference `RIVER`).

---

## 4. Bellwether Galleria mall (14190-15130)

### 4.1 Constants (`MALL` 14191)

x 1102, z 338, w 78, d 108. floor 8.14, gallery 14.6, roof 22.94 [57 st], front z 284, back z 392. Fountain at (1102, 252).

### 4.2 Walkable surfaces

| Function | Rule | Line |
|---|---|---|
| `mallBaseAt` | inside the mall → 8.14; plaza 1061..1145 x 234..415 → 8.12; promenade 1065..1073 x 68..238 → 8.12 | 14348 |
| `mallUpperAt` | gallery 14.6 where |dx| ≤ 38.5, -53 ≤ dz ≤ 53, and (|dx| ≥ 13 or dz ≤ -47 or dz ≥ 48) | 14335 |
| `mallStairAt` | |dx| 5..10, dz 25..48: 24 quantised steps from 8.14 to 14.6 (step 0.269, tread 0.958) | 14341 |
| fountain | r < 7.95: rim at floor+1.12 for r > 7.05, basin at floor+0.34 | 14354 |
| upper surfaces | count only if `referenceY ≥ surface - 0.55` (no snapping up from below) | 14354 |
| `resolveMallLanding` | landing on the highest candidate between the old and new y | 14397 |
| `constrainMallCeiling` | rising: clamp at roof-0.55, and at gallery-0.65 when under the gallery | 14417 |
| `mallRoofAt` | roof landing at 23.12 over the whole footprint | 14367 |

### 4.3 Blocking and camera constraints

- **Blocking** (`mallBlocked` 14380). Active only near the mall (`atMall`). Solid colliders and door boxes block with 0.27 padding against the vertical band [y, y+0.38]. A stair riser blocks if y < step-0.5. The fountain column blocks for r < 1.5 below +4.7, and the rim for 6.8 < r < 8.22 below +0.7.
- **Camera** (`constrainMallCamera` 14429). A segment from the squirrel head to the desired camera point is tested against every AABB in `mallCameraBoxes`: solid walls, glass, partitions, gallery floors, each stair step, the roof slab and the door boxes, all padded by 0.1. On a hit the camera is pulled to `t = max(0.08, lo - 0.035)`. The test runs before and after damping (7394, 7413) so the camera cannot interpolate through a wall or the gallery floor.

### 4.4 Building (`makeMallBuilding` 14633)

- **Floor.** Canvas checker tile (#e3d8be / #c4ccbf, grout #a2a797), roughness 0.32, metal 0.12, repeat 12x16.
- **Walls.** Only the perimeter and the shop partitions are solid. Perimeter walls are 1 thick x 14.6 tall in cream stone #ded2ba.
- **Front facade** (z 284):
  - two 32.5-wide segments leave a 13-wide x 6.8-tall entrance under a 13 x 7.8 lintel;
  - **two sliding glass doors** 5.8 x 6.4;
  - entrance canopy: dark slab 16 x 0.3 x 7 at y+6.9 (z 281.5) with a 14 x 0.08 x 6 glass top at y+7.1;
  - sign `BELLWETHER GALLERIA` (58 x 2.1, y+12.3) and `COME ON IN` (8 x 0.7, y+5.8);
  - three blue window bays per side with brass frames at x ±15/27/35, and trim pilasters at x ±7/20/38.
- **Side walls.** Clerestory windows 10 x 4.6 at y+9.2, z -40..40 step 20, with brass mullions. A dark cornice band runs at y+14.35.
- **Roof.** 8 glass skylight panels 25.3 x 11.5 over the atrium (z -42..42 step 12) on dark beams. Stone slabs 25.5 x 108 cover both shop ranges.
- **Atrium.** 26 wide (x ±13). Trim columns 0.65 x 14.4 at x ±12, z -44/-12/20/44, with brass collars at y 6.5. Three hanging glow strips 11 x 2.2 at y+12.9 (z -35, -3, 29). Planters at (±8,-41). Benches at (±7,-22) and (±7,10). Back sign `BELLWETHER / SIX SHOPS / UPPER GALLERY`.
- **Upper gallery.**
  - Two side walkways 25.5 wide over the shops, plus a front bridge (dz -53..-47) and a back bridge (dz 48..53).
  - Glass balustrades 1.15 tall with brass top rails and posts every 8. The dz=48 balustrade is split to leave openings at the stair heads.
  - Benches at x ±29 (dz -35, -5, 27) and planters at x ±19.
- **Stairs.** Two straight flights (x ±7.5, 5 wide), each 24 dark steps with brass nosings, rising toward the back; brass handrails at x ±5 and ±10; sign `GALLERY UPSTAIRS`.
- **Lighting** (the HTML's only real-time lights besides the sun):
  - 4 `PointLight` #ffdfa9, intensity 38, distance 46, decay 2, at (±25, floor+5.4, ±30), no shadows;
  - hidden in the performance tier and when the player is far (15029).
  - All other glow is emissive: `mallMat.glow` #fff0c8 with emissive #ffda98 at 1.1; shop signs have emissive 0.16 of their background.
- **Outside routes.** Brass downspouts at x 1062.4 / 1141.6, z 288 (`kind: "trunk"`, r 0.15) up to y 23.19, then rooftop `kind: "roof"` routes back to z 388 (14802-14810).

### 4.5 Six shops (`makeMallShop` 14525)

Each shop is a bay 25.5 wide (x ±13..±38.5), between trim partitions 25 x 6.35 at dz -48/-16/16/48.

- **Storefront** at x ±13: glass panels 10 long at dz ±9.5 leave a 9-wide walk-in opening.
- **Signage**: accent fascia 0.65 x 1.25 x 28 at y+5.1; name sign 24 x 1.0 in the accent colour.
- **Interior**: tinted floor 24 x 27 and a 20-long glow strip.
- **Coins**: 2 squirrel coins at x ±17.5, dz -10 / +9.

| Side / z | Shop | Accent | Fit-out |
|---|---|---|---|
| west, 306 | WILLOW BOOKS | #6d8265 | 5 bookcases with 3x6 books, reading table, bench |
| west, 338 | PIXEL PALACE | #68577c | 7 arcade cabinets with emissive screens (#49c2c0 / #dfad64 / #bc8abd) |
| west, 370 | ACORN OUTFITTERS | #986f53 | 2 brass rails with 9 garments each, plinth with 2 mannequins |
| east, 306 | LITTLE JUNGLE | #597e70 | 6 planters, sign `PLANTS / POTS / LITTLE JUNGLES` |
| east, 338 | GROOVE RECORDS | #527a85 | 3 record crates with 12 sleeves each, 5 wall discs |
| east, 370 | COPPER CUP CAFE | #a37254 | 22-long counter, `COFFEE / PASTRIES`, 3 round tables with 2 stools each |

West shops face +X and east shops face -X, toward the atrium.

### 4.6 Wishing fountain and plaza (`makeCoinFountain` 14812, `makeMallPlaza` 14984)

- **Fountain** at (1102, 252), 32 south of the entrance, outside.
  - Structure: a stone lathe basin (r 7.95), a brass column, a mid bowl (r 2.9, +2.55) and a top bowl (r 1.7, +4.4). Water disks at +0.64, +3.03 and +4.78. 48 alternating brass/blue rim tiles.
  - Basin coins: 52 gold + 52 silver instanced coins.
  - Jets: 12 arcing jets with 96 instanced droplets cycling at 0.68 per second.
  - Ripples: 5 rings, each expanding r 1.7 → 6.7 over 4.5 s and fading to opacity 0.
  - Sign wall at z 241.2 (`THE WISHING FOUNTAIN` / `E / TOSS 1 SQUIRREL COIN`), 2 benches and 4 planters.
- **Plaza.** Flat cream stone 1061..1145 x 234..415 at y 8.12, with 6 dark lamp posts with glowing heads.
- **Promenade.** A cobble path 1065..1073 x 68..238 with 6 quay lamps, linking the Quay market to the plaza. Signs `GALLERIA + FOUNTAIN →` and `GALLERIA ↑`.

### 4.7 Mall state machines (`updateMall` 15027)

- **Doors.** `wantOpen = dist(player, (1102, 284)) < 16 && y < floor+5`.
  - `open` eases toward 1 or 0 with factor `1 - exp(-5 dt)`.
  - Door x = 1102 ± (2.9 + 6.1·open).
  - Door collision boxes (5.8 x 0.3 x 6.4) follow the door panels.
- **Inside flag.** `inside = inMall(x,z) && y < roof - 0.25`. It drives exposure 1.15 and keeps the sky visible through the glass roof (13226-13236).
- **Coins.**
  - 25 in total: 12 in shops (y floor+0.55), 8 on the gallery (y 15.15), 1 **gold** on the front bridge (y 15.2, z 288), and 4 around the fountain.
  - Animation: spin 1.7 rad/s, bob ±0.09.
  - Pickup within 0.95. A gold coin increments `goldCoins`; the others increment `squirrelCoins` and `totalCoinsEarned`.
  - Sounds: `fx(1040|720, .08, sine, .025)`. Flashes: "Galleria coin N / 25" or "GOLD COIN · You explored the upper gallery!".
  - One-shot per page load. There is no respawn.
- **Coin toss** (`handleMallInteraction` 15002).
  - Conditions: E pressed, within 11.5 of the fountain centre, |y - 8.14| ≤ 2.8, not on a rail, cooldown (0.7 s) elapsed, `squirrelCoins ≥ 1`.
  - Effect: spend 1 coin. A gold coin mesh flies a 0.9 s lerp with a +3 sin arc to a point on a radius-4 ring, then splashes (`fx(330,…)`).
  - **No reward or effect.** The toss is purely cosmetic.
- **HUD hints.** `#scoutText` reads "Explore six shops · coins on both floors / Twin stairs at the back lead to the gallery" inside, and "Walk through the automatic doors / E near the fountain: toss 1 Squirrel Coin" outside. There is a one-time welcome flash.
- **Quick-start** (`startAtMall` 15104). Spawn (1102, 8.32, 238), yaw PI, pitch 0.22.

---

## 5. v3.5 environment pass (12555-12807)

The whole pass runs inside an IIFE with its own Lambert materials, so these objects are not PBR and are not in the material cache.

**Every object here is placed at y = 0 and does not follow the terrain.** Measured terrain heights: ice-cream stand (152,56) 2.26, strip (-154,-66) 1.42, garden B 0.23, fence end (128,-36) 0.72, stream points 0.03-0.14. As a result, the ice-cream shops sit roughly 1.4-2.3 units into the hillside. The stream (water at y 0.02) is largely hidden under the terrain mesh (rendered at h-0.09). **Port with terrain-following placement.**

None of these objects has a collider or a route.

| Element | Data | Line |
|---|---|---|
| Stream (`outer_stream` in core) | polyline (-175,92) → (-160,88) → (-142,82) → (-126,76) → (-112,74). Water boxes 2.1 wide #6dbfd6, bank strips #8c7a5d at ±1.05, plank footbridge 3.2 x 1.2 #8f6f4b at the middle point | 12720, 12753 |
| Shrubs | 13 shrubs in 5 clusters (`env_shrub_cluster_A..E`). Each is 3 stacked 7-sided cylinders, scale 0.9 / 1.05 / 1.2 cycling, colour #557a37 or #648843 every 4th | 12568, 12760 |
| Fence runs | 4 visual-only runs (`env_fence_run_0..3`). Wood: posts 0.16 x 1.1 #8b6a44, two rails #9a7750 at 0.72/0.36. Chain: posts #8e8e8e, 0.55-tall mesh #b7c0c0. Posts every ≈2.4. Run 0 (z 38) crosses the core house 2 front walk | 12583, 12775 |
| Garden plots (core lots) | 3 plots: (-36,52) 7x4 variant 0 (greens #5d9c41), (116,-24) 6.5x4.5 variant 1 (red #c94f2d), (-104,-18) 7.5x3.8 variant 2 (#7bbf53). Soil #7a5132, border #6f5339, rows of small cylinders, mini wheelbarrow | 12620, 12780 |
| Ice cream standalone (152,56) | base 8.5 x 0.3 x 6.8; pink shell 7.4 x 4.2 x 5.8 #ffd6df; sky-blue roof #6fb6d8; white awning; window #bfe8ff; **blank** sign #fff0a8; giant cone prop with pink/green scoops; bench | 12648 |
| Ice cream strip (-154,-66) | slab 12 x 7.5; white shell 10.5 x 4.2 x 5.6 #e9eef0; teal fascia #5ec0dd; two windows; door #6c4b3b; **blank** sign #fff2b6; 3 pink/blue umbrellas behind the shop (z -2.1) | 12685 |

---

## 6. Nineteen neighborhood detail kinds (`addDetail` 3054)

### 6.1 How addDetail works

- Each call creates a group at `(x, terrainHeight(x,z), z)` with yaw = `variation·0.71` rad, and records it in `neighborhoodDetails`.
- The objects are visual only: no colliders and no routes.
- **Variation palette:**
  - odd variations use red #cead4e (mustard), green #527b64 and wood #9f8365;
  - even variations use red #b44332, green #47664c and wood #84694f;
  - constant: brass #baa769 (metal 0.6), iron #4c6262, blue #517b97, white #e6ddca, pink #e89ab0.

### 6.2 Kinds

| # | Kind | Geometry (local) |
|---|---|---|
| 1 | fire hydrant | red body r .55-.7 x 1.55, base ring, cap, two side nozzles with brass caps, top nut; about 2.1 tall |
| 2 | park bench | 4 seat slats 4.2 long, 3 back slats, iron legs; seat y 1.13 |
| 3 | trash can | r .72/.62 x 1.58 (odd variation green, even iron), black lid, 12 vertical straps |
| 4 | streetlight | iron pole 9 tall, 3.3 arm, metal head 1.8 x 0.38 x 1.15 with warm lens #fff3c4 (not a real light) |
| 5 | stop sign | post 2.75, red octagon r 0.61 with canvas "STOP" (#a72e2e / #fff8e2), cream border r 0.68, centre y 2.4 |
| 6 | garden gnome | blue-grey body, skin head, red cone hat, white beard |
| 7 | bird feeder | wood post 4.8, tray 1.9², 4 corner posts, red/mustard pyramid roof at 4.6 |
| 8 | sprinkler head | iron riser, blue cap; even variations show 5 water arcs (#9ddae2) |
| 9 | porch swing | A-frame posts 4.1, beam 5.2, chains, seat 4 x 1.5, back |
| 10 | window box | wood box 3.1 x 0.6 x 0.75, 7 green balls with pink/red flowers |
| 11 | driveway basketball hoop | pole 7.3, white backboard 3.6 x 2.2, red rim torus r .66 at y 6.7, net |
| 12 | kids bike | two spoked wheels r 0.6 (`makeSpokedBicycleWheel`), red frame, iron bars, black seat |
| 13 | lawn flamingo | pink ellipsoid body, curved neck, head, black beak, wire legs |
| 14 | wind chime | wood post 3.5, disc r .58, 6 brass tubes of 3 lengths |
| 15 | garden hose reel | two green torus wheels r .81, iron drum and legs |
| 16 | wheelbarrow | tray 2.4 x 0.62 x 1.3 (blue or green), iron rim, wood handles, black wheel |
| 17 | compost bin | 3-tier slatted wood box 2.5 x 2.4, lid 2.6 x 2.5 at 2.12 |
| 18 | rain barrel | r .85 x 2.5 (blue or wood), 3 iron hoops, brass spigot |
| 19 | porch light | wood post 3.6, iron arm, lantern 0.74 x 1.08 x 0.65 (#e7d9aa), pyramid crown |

### 6.3 Placements

There are 59 in total; every one is listed in the JSON as `detail_00`..`detail_58`.

- **38 yard placements** (3243-3249). Two of each kind. Kind i, variant v (0/1) goes to `houses[4 + ((3i + 7v) % 20)]` (= `outer_home_k`), offset (v=0: +11, v=1: -12; i odd: +12, i even: -13), variation `v + (i%3)`. These offsets can land on walks or near walls (not checked in code).
- **14 public and commercial fixtures** (3251-3267). Hydrants (312,23), (387,-22); benches (418,-39), (562,46); trash cans (538,-38), (419,77); streetlights (294,-22), (397,23), (583,-21); stop signs (324,31), (371,-34); sprinkler (574,145); flamingo (571,-149); kids bike (251,126).
- **7 in Sycamore Park.** Benches (-59,355), (7,333), (-185,326), (112,396) (3443-3449) and trash cans (-201,331), (-30,405), (82,311) (3450-3455). Two extra park lamp posts at (-118,326) and (10,398) (3456-3463) are not `addDetail` objects.

**Brief relevance.**

- Bird feeders (2), trash cans (7) and gardens are the HTML seeds for brief section 7 foraging sources. The brief needs many more feeders and trash cans, plus dumpsters, which do not exist in v5.4.
- Stop signs (4) and fire hydrants (4) are the only seeds for the Addendum A2 stop-sign and parking (hydrant) tickets. They are decorative and not placed systematically at intersections or curbs.

---

## 7. Treehouse (`buildTreehouse` 9502)

`treehouseSite = {x:-142, z:154, base: terrainHeight ≈ 1.52, height: 13.2}` (9501). The floor is at world y ≈ 14.72 [36.8 st].

- **Tree.** "Treehouse Oak" via `makeTree`: H 31, crown 7.8, 8 branches, seed 9301, colours #6a8c3e / #89ab55 / #a4bb66, canopyBoost 3, acorns.
- **Structure** (local to the site, y relative to base):
  - floor 8 x 0.38 x 7.8 (#63482e) at h;
  - external lookout deck 4.2 x 3.2 (#916c47) at x +5.9, with rails on 3 sides;
  - 4 stilts at (±3.75, ±3.5) r .29/.23, each with a diagonal brace (r .17/.11) angled inward from (x, 0.7, z) to (0.38x, h-0.25, 0.38z) under the floor (not to the floor centre).
- **Ladder.** At local z +4.15: two rails r 0.105 and rungs 1.6 x 0.13 every 0.75 (#b9986c). Registered as route "treehouse ladder", `kind: "trunk"`, surfaceRadius 0.35.
- **Walls** (#b9986c pine, 4.1 tall):
  - back wall at z -3.72 with two glass windows 1.65 x 1.5;
  - side walls at x ±3.85;
  - partial front wall at z +3.76, made of two 2.2-wide panels around a central doorway. The open face is local +Z; the code comment calls it "south".
- **Roof.** 8.7 x 0.3 x 8.4 (#615044) at h+4.64. It is stored as `treehouseSite.roof`.
- **Furniture.** Table 2.4 x 0.26 x 1.15 at (-2,-1.5); bunk 2.1 x 0.48 x 0.94 (#a9a083); chest 1.45 x 0.81 x 1.45 at (2.1,-1.4); shelf at (1.5, h+1.4, 1.2) with an unlit glowing lantern (#ffe3a6).
- **Routes.** "treehouse floor" (`kind: "lookout"`) at h+0.4 from z +4.15 to -2.0. "treehouse deck" (`lookout`) from the centre to x +5.9.
- **Floor collision** (`getGroundAt` 6241). Inside |dx| < 4.2, |dz| < 4.0 while above base+h-1.1, the floor is at base+h+0.26.
- **Brief tie-in (inferred).** The treehouse oak is a natural candidate for one of the brief's 11 hollow trees (section 3). It sits about 60-80 north of the stream (z 74-92).

---

## 8. Radio and cell towers (2975-3027)

The code comment calls these "Exactly one radio lattice tower and one cellular monopole on the far skyline." Both are scenery only: no routes and no colliders.

| Item | Radio lattice tower (`radioTower` 2976) | Cell monopole (`cellTower` 3005) |
|---|---|---|
| Position | (646, -213), base ≈ 0.10 | (629, 218), base ≈ 4.23 |
| Height | lattice 114 + mast 11 (to 125); beacon at 126 [315 st] | 99 [247.5 st] + cone cap 3.6 |
| Form | 3 legs, triangle footprint radius 6.3 tapering to 1.3, 10 sections. Legs r .19/.13; diagonal and ring braces r .085/.06 | tapered tube r 1.65 → 0.9, 14 sides; antenna rings at 0.67H and 0.88H, each a cross-arm 8 long plus 6 panels 0.8 x 6.5 x 1.6 on radius 4 |
| Colours | legs alternate red #b34c45 (odd sections) and steel #aeb6b1 (rough .38, metal .6); braces steel | metal #8f9d98 (rough .36, metal .74); panels #d0d5cc |
| Lights | **one static** red sphere r 0.53, emissive #ff351e at 0.55. `radioBeacon` is never referenced again, so **it does not blink** | none |

Both are visible from most of the map through fog (310-1050). The radio tower is taller than the drone's 300-stud cruise height (section 14).

---

## 9. Signage system

- **`signCanvas(text, bg, fg)`** (658). A 512 x 160 canvas with bold 88px Arial, centred text and max width 490. The material is MeshStandard with emissive = bg at 0.14 and double-sided.
- **`flatSign`** (682). Builds a box sign of thickness 0.13 and auto-shrinks road-guide text (see 2.5). It is registered in `districtSigns`.
- **`mallSign`** (14296). A plane with a canvas sized to its aspect, height 128, font 78px, text #f9ebc9, emissive 0.16.
- **`riverSign`** (14010). A post-mounted 8 x 1.3 board.

| Text | Where | Colours (bg / fg) | Line |
|---|---|---|---|
| CHILI'S / GRILL & BAR | restaurant (474, -65) | #a72e29/#fff1cf; #53312a/#ffdea8 | 750-751 |
| FUEL MARKET / OPEN / FUEL / MARKET / OPEN | fuel market and price tower | greens #2e6552…, cream | 808-896 |
| 87 89 93 | pump faces | #274f4f / #e9ecd9 | 867 |
| CORNER SHOPS | (605, -79.4) | #4e625e / #fff8db | 909 |
| STOP | stop-sign details | #a72e2e / #fff8e2 | 3099 |
| SYCAMORE PARK; PARK / CEMETERY ↑; CEDAR REST CEMETERY; TABASCO GARDEN | north | dark greens | 3477-3654 |
| Hospital set | see 2.5 | teal #335f67…, red #9d4037 | 3880-4047 |
| SCOOP MOBILE, ICE CREAM, CITY TROLLEY, TROLLEY STOP | street vehicles and stops | | 7574-7704 |
| WEST TOPEKA POLICE; WESTSIDE FUEL; 87; AIR / WATER; WESTSIDE STORAGE | westside | | 10062-10170 |
| WANTED posters | after 15 bites (canvas) | | 11226-11240 |
| 30 Quay fascias, 3 Quay signs | see 3.4 and 3.7 | #405b51 or #745547 / #f4e5bd; #304c44 / #f6e9bd | 13861, 14017 |
| Galleria: BELLWETHER GALLERIA, COME ON IN, 6 shop names, PLANTS / POTS / LITTLE JUNGLES, COFFEE / PASTRIES, GALLERY UPSTAIRS ×2, BELLWETHER / SIX SHOPS / UPPER GALLERY, THE WISHING FOUNTAIN, E / TOSS 1 SQUIRREL COIN, SHOPS / FOUNTAIN / GALLERY, GALLERIA + FOUNTAIN →, GALLERIA ↑ | mall | shop accents, #344c49 default | 14525-14998 |

The ice-cream shop signs are blank colour boxes (see 5). The core lots extractor covers sign positions for the commercial and westside districts.

---

## 10. Sky, atmosphere, lighting, fog, time of day

### 10.1 Boot state (lines 1-43, 917-948)

- **Background and fog.** `scene.background` #a8d0ef; `scene.fog = Fog(#bed6db, near 310, far 1050)` [775 / 2625 st].
- **Renderer.** ACES Filmic tone mapping, initial exposure 1.42, sRGB output, PCF soft shadows, pixel ratio ≤ 1.45 (later governed by tier).
- **Camera.** FOV 72, near 0.12, far 1500 [3750 st].
- **Initial lights.** Hemisphere (sky #e8f7ff, ground #657650, intensity 2.1). Sun DirectionalLight #fff4d6 at 3.4 from (-80, 105, -42) with a 2048 shadow map. Both are replaced at init by the presets below.
- **Sky dome.** Sphere radius 1200 [3000 st], BackSide, follows the camera in xz (13227). Initially a two-colour gradient (#509ed9 → #e8f4f7).
- **World clouds.** 34 flattened white ellipsoids at x, z ±330 (over the core only), y 95-155, scale (12-39, 0.28-0.8, 1.4-4). Opacity 0.15, cut to 0.065 by `makeAtmosphere`. They do not follow the camera.

### 10.2 Atmosphere shader (`makeAtmosphere` 12862)

- **Sky colour.** `col = mix(horizon, zenith, pow(max(dir.y, 0), 0.5))`.
- **Sun.** Halo `pow(dot(dir, sunDir), 28)·0.18` and disc `pow(·, 750)·0.8`, tinted by sunColor.
- **Procedural clouds.**
  - Projection: `uv = dir.xz / max(0.22, dir.y)·1.3 + t·(0.003, 0.001)`.
  - Coverage: fbm (3 octaves), `smoothstep(0.52, 0.73, fbm)·smoothstep(0.025, 0.20, dir.y)·0.6`.
  - Colour: (0.98, 0.96, 0.90).
- **Tone mapping.** `toneMapped: false`.
- **Below the horizon.** The colour clamps to the horizon colour (no ground).

### 10.3 Light presets (`LightPresets` 12809, `applyLighting` 12890)

These are three **static** looks chosen in the Display panel (G), persisted in localStorage `spicy-render-v5`. The default is `golden`.

| Preset (UI name) | sun | sky (zenith) | horizon (hemi sky, background) | fog | hemi ground | sun power | hemi fill | exposure | sun direction | sun elevation (inferred) |
|---|---|---|---|---|---|---|---|---|---|---|
| golden ("Golden Hour") | #ffe0ab | #72a8ca | #efdcb5 | #c8d1bd | #56664a | 2.35 | 1.55 | 1.12 | (-83, 94, -49) | ≈ 44° |
| daylight ("Clear Day") | #fff5df | #569dd2 | #deebee | #bfd4d9 | #657753 | 2.7 | 1.8 | 1.08 | (-55, 125, -40) | ≈ 61° |
| dusk ("Blue Hour") | #f4b88b | #485a8a | #c29596 | #89929e | #434757 | 1.15 | 1.2 | 1.18 | (-105, 55, -35) | ≈ 26° |

Runtime overrides:

- **Sun following** (`updateVisuals` 13224). The sun light is re-centred on the player (snapped to 1/8 unit, y+9), with position = centre + direction. It is updated when the player moves more than 0.5.
- **Exposure each frame.** Hospital 1.12, sewer 1.05, mall 1.15, otherwise the preset exposure. `updateNewSystems` sets 1.19 (hospital), 1.1 (sewer) or 1.42 (outside) earlier in the same frame (9123-9132); `updateVisuals` overwrites it.
- **Indoor fog** (9115-9122). `enclosed` = sewer, hospital, or within 2 of a shelter zone and low. Fog near/far lerp 12 % per frame toward 15/53 enclosed or 310/1050 outside.
- **Camera far.** Duct 55, hospital 125, sewer 65, otherwise 1500.
- **Sky visibility.** Hidden in hospital, sewer, duct and house interiors; kept in the mall.

**There is no day/night cycle, moon, stars, night lighting, weather or season in v5.4.** The comment at 11308 says: "No day/night changes". The only time-like elements are the drifting shader clouds and static clock-tower hands.

**Fog/sky mismatch (golden).** Fog #c8d1bd is cooler and greener than the horizon #efdcb5, so distant geometry fades to grey-green against a cream sky. This is a deliberate but slightly hazy look.

### 10.4 Shadows (`applyQuality` 12925, `updateCanopyShadows` 9136)

- One directional shadow map: 2048 (high) or 4096 (ultra); orthographic half-extent 76 (high) or 100 (ultra); near 1, far 300; bias -0.00012; normalBias 0.09.
- No shadows in the performance tier.
- **Canopy shadow casters.** Tree foliage meshes are listed in `canopyShadowCasters` with r = 90-110. A foliage mesh casts shadows only within r of the player, re-evaluated every 0.8 s; `applyQuality` also uses a 100 limit. This is the "dappled canopy shadow" look, budgeted by distance.
- **Leaves.** Double-sided MeshStandard with emissive = leaf colour at 0.075, so the undersides never go black. A breeze sways each foliage chunk: `rotation.z = sin(0.51t + phase)·amp`, amp 0.003-0.007 (15971).

### 10.5 Overflight (backdrop element, 15508-15633)

- **Model.** One silent airliner: white fuselage ellipsoid (0.72 x 0.76 x 8.1, slight emissive), swept wings, tailplane, blue fin (#477783), 2 engines, and 2 contrails of 18 fading segments.
- **Timing.** First pass after 34 s, then every 90-150 s. Each pass lasts 48 s and covers 1260 units, about 26.25 u/s [65.6 st/s].
- **Path.** Altitude 165-205 [412-512 st], straight line through a point ±95 / ±75 from the player. Heading is random within ±1.1 rad, alternating ±180° per pass.
- **Visibility.** Hidden only while the player is in the hospital, sewer or duct (15625); it stays visible from house interiors and the mall (whose glass roof shows the sky). No audio, as the code comment states.

---

## 11. Materials and palette

- **Material model.** `mat(colour, roughness = 0.88, metalness = 0)` gives a cached MeshStandardMaterial (45; cache map at 44).
- **Procedural textures** (`noiseCanvas` 330).
  - grass #929f70 speckle, repeat 70x70, material tint #a2b78b;
  - road #555b5b grain, repeat 4x28, tint #929493;
  - bark #736354 streaks, repeat 1x3, tint #b6a99b;
  - roof shingle #796c64, repeat 3x2, tint #b4a49d.

| Global key (`M`, 51) | Colour | Notes |
|---|---|---|
| grass / grass2 | #819762 / #607847 | grass replaced by the textured material |
| asphalt | #40484a | textured later |
| sidewalk (concrete) | #c3beb1 | |
| wood / bark | #806147 / #655342 | |
| metal | #737f85, rough 0.4, metal 0.62 | |
| white / trim / black | #dfdac8 / #efecdc / #29302f | |
| glass | #8db9bf physical, opacity 0.72, rough 0.16 | |
| water | #63c3d0 physical, opacity 0.84 | |
| rubber / mail | #1e2525 / #486d88 | |

District palettes (from the sections above):

- **Quay** (`riverMaterials` 13438): stone #aaa697, stoneLight #d1c7ae, stoneDark #777b70, wood #4e4136, oak #75604b, copper #718679 (metal 0.3), iron #364b51, blue #4e7c87, glass #c3cfb5, roof #4c5a60.
- **Galleria** (`mallMat` 14228): stone #ded2ba, trim #f0e4cb, dark #344c49, brass #b69a53 (metal 0.65), wood #82634b, ink #283638, green #64876b, terracotta #bc805d, cream #eadbbd, blue #477b88, pink #ba7f87, book #9c654d, gold #e9be4e, silver #d1d7ce; glass #a8d7d4 at opacity 0.27; water #57bcb9 at 0.43.
- **Hospital**: white #e6e5db, wall #a5ada9, blue #628e9d, floor #b9c4ba, tile #e5eee9, glow #f0f6db, spine #6ca99e, triage line #bda17d.
- **UI** (shell 10): lime #d1ee83, cream #f5f2df, muted #a3b8af, dark #0d1715, page background #98c6e5. Fonts: Barlow Condensed (display) and DM Sans (body).

**Palette statistics** (all 1068 distinct `"#rrggbb"` literals in the file): HSV saturation p10/p50/p90 = 0.08 / 0.30 / 0.55; value p10/p50/p90 = 0.39 / 0.66 / 0.91. The town is muted and earthy: sage greens, cream stone, weathered wood, teal-grey accents. The rare saturated colours are signs, toys, flamingos and arcade screens. These numbers are the clamp targets for Addendum A3 avatar blending (section 15).

---

## 12. Graphics quality and presentation/resilience systems (12808-13426)

### 12.1 Quality tiers (`setGraphicsQuality` 12916, `applyQuality` 12925, `resizeGraphics` 12951)

| Tier | Shadows | Shadow map / range | Max pixel ratio | Pixel budget | Grass tufts, motes | Mall point lights | Post-processing |
|---|---|---|---|---|---|---|---|
| ultra | on | 4096 / ±100 | 2.0 | 5.0 M px | on (tufts within 125) | on | bloom if loaded |
| high (also the start tier of auto) | on | 2048 / ±76 | 1.5 | 2.8 M px | on | on | bloom if loaded |
| performance | off | n/a | 1.0 | 1.4 M px | off | off | none |

- **Pixel ratio** = clamp(min(dpr, max, sqrt(budget / (w·h))) · adaptiveScale, ≥ 0.6).
- **Auto adaptation** (13258-13272). frameMs is an EMA (α 0.035) of real frame time, ignoring frames ≥ 0.25 s, hidden tabs and pauses. Every 10 s of samples:
  - if frameMs > 30 and adaptiveScale > 0.72, adaptiveScale drops by 0.12 (minimum 0.7);
  - otherwise, if frameMs > 40 and the tier is high, the tier drops to performance.
  - It **never steps back up** automatically.
- **Controls.** The Display panel (G), the GRAPHICS chip (cycles auto → high → ultra → performance) and the readout "fps · tier · ratio · effects".

### 12.2 Optional "online detail" (12801, 13123)

These are downloaded at runtime and can be switched off.

- **Bark.** Poly Haven `bark_willow` 1k diffuse and normal maps, applied to `M.bark` (normalScale 0.6, tint #b0ac9b).
- **Bloom.** UnrealBloomPass with strength 0.13, radius 0.35, threshold 1.15.
- **Environment.** Equirect HDRI `kloppenheim_06_puresky_1k.hdr` through PMREM; envMapIntensity 0.3 on every standard material.
- **Robustness.** Each part is atomic and cancellable: fetch timeout 12 s, import timeout 14 s, and the procedural fallback stays until a full set arrives. The status line reads "Online detail loaded", "n/3 enhancements loaded · built-in fallback active" or "Built-in graphics active · downloads unavailable".

### 12.3 Ground detail (`makeGroundDetail` 12979)

- **Grass tufts.** Up to 90 per tree (trees with |x| ≤ 700), at radius 3.5..min(20, crown+2). They avoid pavement (< 2) and obstacles. Each is a 2-blade tuft 0.18-0.55 tall with HSL hue 0.19-0.25, saturation 0.30-0.44, lightness 0.26-0.43. They are instanced in 32x32 buckets, visible within 125 of the player, and sway `sin(1.4·wind + 0.4x + 0.3z)·0.12·y` in the vertex shader.
- **Motes.** 96 warm points (#ffe4a7, size 0.055, opacity 0.45) in a 44 x 15 x 44 box that follows the player and slowly rotates. Hidden indoors and in the performance tier.

### 12.4 Resilience (keep the intent, not the mechanism)

- **Bad state recovery** (`validatePlayerState` 13300). A NaN position or velocity, or y < -150, restores `lastSafe`, saved every 0.5 s while grounded, off-rail and not in a duct. It hard-cuts the camera and flashes "Recovered to your last safe position."
- **Pause.** Blur or a hidden tab pauses with a shield ("Your run is paused."). WebGL context loss pauses (resume button disabled); context restore does not reload the page: it resets the online detail, re-runs `applyQuality` and `applyLighting`, re-fetches online detail and shows "Graphics restored. Your run is still here." (13391-13409).
- **Error isolation.** Peripheral subsystems run through `updateOptional`. The first error disables that subsystem and flashes "… temporarily disabled. Press L for diagnostics." A core error shows the boot-error panel (15915-15938).
- **Frame and diagnostics.** dt is capped at 0.08 s, the player moves in ≤ 1/60 substeps, and peripheral systems take realDt ≤ 0.2 (15999-16030). Startup runs `verifyRouteRegistry` and the utility-pole audit. The diagnostics overlay (L) shows fps, draw calls, triangles, merged-mesh stats, position, route counts and errors.
- **Batching.** `batchTreeBranches` (126) merges static same-material children (4 or more) into one mesh per material: trees, Quay buildings, mall statics.

---

## 13. Voices and audio

- **SFX.** All sound effects are synthesised. `fx(freq, dur, wave, vol)` (6451) is a WebAudio oscillator with an exponential pitch drop to 0.64× and a gain decay to 0.001 over `dur`. There are no audio files, no ambience loops and no music.

| Event | fx args | Line |
|---|---|---|
| chili / gold pickup | 990, .13, triangle, .07 | 5496 |
| Power decay | 160, .2, sine, .035 | 5514 |
| pounce launch | 640, .1, sawtooth, .025 | 6504 |
| perfect counter | 880, .12, triangle, .06 | 6524 |
| kicked / batted away | 150, .24, tri, .08 / 100, .25, square, .047 | 6543, 6552 |
| pedestrian spots you | 410, .09, sine, .009 | 7073 |
| ice-cream van stop / trolley stop | 760, .08, sine, .019 / 610, .13, sine, .023 | 7760, 7802 |
| baton hit / surprise bite on cop | 180, .18, square, .05 / 180, .23, tri, .05 | 8023, 8123 |
| predator warning | 310 (eagle) or 130, .6, sawtooth, .043 | 8224 |
| hospital attack / knockback | 580, .13, tri, .05 / 185, .16, square, .045 | 8550, 8676 |
| vent chewed open | 560, .24, tri, .05 | 8889 |
| squirrel infected | 810, .12, tri, .04 | 8974 |
| ambulance siren pulse | 430, .21, sine, .018 (ducked to .001 during action warnings), every 1.45 s | 9036 |
| dog bark | 210, .13, square, .018 | 9108 |
| motorcycle crash | 260, .3, sawtooth, .043 | 9635 |
| bite-decade dance | 680, .17, tri, .05 | 10355 |
| cat swat / miss / crouch / hiss | 170, .23, saw, .05 / 280, .13, tri, .024 / 220, .32, saw, .038 / 310, .22, saw, .018 | 11617-11636 |
| river splash | 180, .18, tri, .035 | 14137 |
| coin toss / coin pickup / splash | 740, .12, sine, .035 / 1040 or 720, .08, sine, .025 / 330, .15, sine, .025 | 15024, 15082, 15100 |

- **Voices: browser `speechSynthesis`.**
  - `speakCitizen` (4752) speaks every speech-bubble line from `say()`: English voices only, avoiding the previously used voice, chosen by `npc.idx`. Rate is `0.98 + (idx%4)·0.045`. Pitch is 1.23 for panic, 0.84 for bluster and 1.06 otherwise. Volume is 0.8. A global cooldown of 2.4 s applies, and nothing is spoken while another utterance is pending.
  - "Watch out!" (volume 0.3) plays at game start (5563).
  - `speakWantedRecognition` (11286) says "That is the squirrel from that poster!" in a rotating female/male/high voice.
  - The VOICES chip toggles all speech (5708).
- **Speech bubbles.** HTML divs with the NPC name that live 4.6 s; the NPC `sayCooldown` is 8 s. Line pools (4734): `spot` (6 lines), `surprise` (2), `hit` (3), `escape` (3). Several lines contain mild profanity ("bastard", "hell", "damn").

---

## 14. Art direction for Roblox

### 14.1 Look to preserve

The target is a **warm, hazy, muted golden-hour suburb**:

- creamy horizon and soft teal zenith;
- long-ish soft shadows from a single warm sun at about 44°;
- strong sky fill so shade is never black;
- sage and olive greens, cream and teal-grey buildings;
- emissive-only lamps;
- gentle bloom on bright highlights;
- dappled canopy shadow near the player;
- small "storybook" landmarks (stone bridge, half-timbered quay, glass-roofed galleria).

Saturation stays low (median 0.30). Strong colour is reserved for signage and toys.

### 14.2 Mapping table (HTML → Roblox)

All Roblox values are **starting points to tune by eye** (inferred). Roblox applies its own fixed filmic tone curve: there is no ACES switch.

| HTML | Roblox | Suggested start |
|---|---|---|
| ACES tone mapping + exposure 1.12 (golden) | `Lighting.ExposureCompensation` (EV = log2 exposure); `ColorCorrectionEffect` | golden +0.16 EV, daylight +0.11 EV, dusk +0.24 EV; ColorCorrection Contrast 0.05, Saturation -0.05..0 |
| Sun DirectionalLight (colour, power, direction) | `Lighting.Technology = Future` (ShadowMap on low-end via client quality), `Lighting.Brightness`, `ColorShift_Top` (sun tint), `ClockTime` + `GeographicLatitude` for direction | Brightness 2.5-3; ColorShift_Top #ffe0ab golden, #fff5df day, #f4b88b dusk. Latitude about 39 (the HTML names Topeka) |
| Hemisphere light (sky #efdcb5 / ground #56664a, fill 1.55) | `Lighting.OutdoorAmbient`, `Ambient` (interiors), `ColorShift_Bottom`, `EnvironmentDiffuseScale` | OutdoorAmbient ≈ mid-mix of sky and ground: golden #a2a180, day #a2b1a1, dusk #836e77. EnvironmentDiffuseScale 0.6, EnvironmentSpecularScale 0.3 (HTML envMapIntensity 0.3) |
| Linear fog #c8d1bd, 310 → 1050 [775 → 2625 st] | `Atmosphere` (FogStart/FogEnd are ignored when Atmosphere exists) | Density 0.30, Offset 0.25, Color = preset fog, Decay warm (#b9a17e golden), Glare 0.2, Haze 1.5; tune so geometry fades by about 2600 st |
| Enclosed fog 15 → 53 (sewer, hospital) | interiors need no fog; for the sewer use a client-side local Atmosphere override or darker Ambient | Ambient #3a403a in sewers |
| Gradient sky shader + fbm clouds + 34 cloud ellipsoids | `Sky` (custom skybox or default) + `Terrain.Clouds` (dynamic clouds) | Clouds Cover 0.5, Density 0.7, Color #fffaf0; skybox horizon tinted toward #efdcb5 |
| Sun disc and halo | `Sky.SunAngularSize`, `SunRaysEffect` | SunAngularSize about 14 (engine default 21), SunRays Intensity 0.06 (day) to 0.2 (sunrise/sunset), Spread 0.5 |
| UnrealBloom 0.13 / 0.35 / 1.15 | `BloomEffect` | Intensity 0.35, Size 24, Threshold 1.4. Neon and emissive signs drive it |
| Emissive lamps (quay #ffc66d, mall #ffda98) | `Material = Neon` parts plus sparse `PointLight` (Shadows = false), enabled at dusk and night only | about 1 real light per 2-3 lamps near players; the rest Neon only |
| Mall PointLights 4 × #ffdfa9, distance 46 | `PointLight` Range ≈ 46·2.5 → capped at 60 (Roblox max), Brightness 1.5-2, or `SurfaceLight` strips under the gallery | client-side LOD: disable when far |
| Canopy shadows only near the player | Future lighting handles shadow LOD. Leaf cards with alpha textures may not cut dappled shadows (verify); author canopy meshes with real gaps, and keep `CastShadow` off on tiny leaf clusters | (verify) |
| Leaf emissive 0.075 (no black undersides) | double-sided leaf MeshParts (`DoubleSided` property) plus a slightly brighter `SurfaceAppearance` colour | |
| Grass tufts around trees | `Terrain` Grass material with `Terrain.Decoration = true`; or instanced grass meshes near trees for non-terrain ground | |
| Motes | client `ParticleEmitter` parented to the camera; LightEmission 0.5, Size 0.15-0.25 st, colour #ffe4a7, Rate 8, daytime only | |
| Water shader (river) | Terrain water (WaterColor #315c61, WaterReflectance 0.4, WaterTransparency 0.3, WaterWaveSize 0.1, WaterWaveSpeed 6), or a mesh with a scrolling texture if terrain water conflicts with the embankments | |
| Quality tiers and adaptive resolution | Roblox user graphics level. On the client, read `UserGameSettings.SavedQualityLevel` to toggle: fountain droplets, motes, bunting animation, distant lamp lights, grass meshes | |
| Online bark, HDRI (runtime download) | uploaded textures with `SurfaceAppearance` (PBR) at authoring time; no runtime downloads | |

### 14.3 Sunrise, day, sunset, night (full cycle; required by the brief)

Day-phase keyframes interpolated on the **client** from a replicated in-game clock (see Porting). The HTML presets are the anchors:

| Phase | ClockTime (inferred) | Anchor | Key settings |
|---|---|---|---|
| Night | 21:00-04:30 | new | Brightness 0.3-0.6, OutdoorAmbient #2e3550, ExposureCompensation -0.3, Atmosphere Color #2a3142, Decay #1a1f2b, `Sky.StarCount` 4000+, custom phased moon (14.4), Neon lamps and lit windows on |
| Sunrise moment | 05:00-06:30 | new | ColorShift_Top #ffb98a, Atmosphere Decay #e8a070 and Glare 0.6, SunRays 0.2, ColorCorrection Tint #fff0e0; hold this window longer than linear time (see Open questions) |
| Golden morning | 06:30-09:00 | `golden` | |
| Day | 09:00-15:30 | `daylight` | |
| Golden afternoon | 15:30-18:00 | `golden` | |
| Sunset moment | 18:00-19:30 | `dusk`, warmed | horizon #c29596 → #f0a070, ColorShift_Top #f4b88b, SunRays 0.25, radio-tower beacons stand out against the low sun |
| Blue hour | 19:30-21:00 | `dusk` | zenith #485a8a, fog #89929e, lamps fade in |

Winter week (brief section 12): exposure -0.15, saturation -0.15, cooler OutdoorAmbient, snow terrain and bare-tree swaps (owned by the Seasons extractor).

### 14.4 Backdrop the brief requires (new; nothing exists in the HTML)

The HTML edge of the world is simply fog (310-1050) against a 1200-radius sky dome. There are no mountains, ocean, beach, pier, marina, stars, moon or night.

The brief (section 3 Backdrop, section 10 drone) asks for the following.

1. **Mountains falling to rolling hills and plains, with a tree line, a distant road and fog layering (one side).**
   - Build in three depth bands:
     - near rolling hills as Terrain, 0.5-2 km beyond the play edge;
     - mid hills with impostor tree-line meshes, 2-5 km;
     - far mountain MeshParts, 5-10 km.
   - Bake aerial perspective into the far meshes' vertex or texture colour (lighter, bluer and lower contrast with distance) so they read correctly even before Atmosphere haze.
   - Add a thin distant road ribbon on the hills, with tiny moving vehicle impostors and headlights at night.
   - Use `ModelStreamingMode = Persistent` (or `LevelOfDetail = StreamingMesh`) so the backdrop never streams out.
2. **Ocean with beach, pier and marina (other side), with a horizon that reads correctly from 300 studs up.**
   - Use Terrain water (or a huge flat water mesh beyond the terrain) extending at least 6-10 km to where Atmosphere haze fully hides the edge.
   - Match the skybox horizon colour to the fogged sea colour so there is no visible seam at the drone's 300-stud altitude. Test the horizon with the drone camera at 300 st and the default FOV.
   - Beach (sand terrain plus dune grass), a timber pier, and the brief's new **marina lot** (section 3 Neighborhood expansion) with moored boats. The Quay boat model (3.6) is a template.
3. **Full day cycle** with sunrise and sunset as distinct graphic moments (14.3), clouds (dynamic `Clouds`), the **silent overflights** from v5.4 (10.5), and a starry night.
4. **Moon with real phases on a ~29.5-day in-game lunar month**, never a permanent full moon.
   - `lunarAge = (inGameDayCount + epochOffset) mod 29.53`.
   - `phaseAngle = 360°·lunarAge/29.53`.
   - Illuminated fraction `k = (1 - cos(phaseAngle))/2`: 0 is new, 7.4 is first quarter, 14.8 is full, 22.1 is last quarter.
   - Moon elongation east of the sun ≈ phaseAngle, so moonrise lags sunrise by `phaseAngle/360 · 24 h`. The full moon rises at sunset; the new moon is up with the sun and invisible.
   - Roblox has no native phase control. `Lighting:GetMoonPhase()` always returns 0.75, per `spec/roblox_feasibility.md` section f. That spec recommends swapping `Sky.MoonTextureId` per phase first (8-30 preloaded phase textures). The fallback is a custom client moon: a billboard or mesh at `camera + GetMoonDirection()·far` with the built-in moon hidden, which also gets the terminator and lit limb right. The engine's moon path does not follow the phase-dependent elongation above. If moonrise timing matters, use the custom moon; otherwise accept the engine path (designer decision).
   - `Sky.StarCount` needs `CelestialBodiesShown`. Fog layering needs authored silhouette cards or meshes, because Atmosphere is a single global layer (feasibility spec section f).
5. **A radio or cell tower in the distance with blinking red lights, placed to silhouette against the sunset.**
   - Keep the HTML lattice tower design: 3-leg lattice, alternating red and steel sections, mast. The red banding is normally international orange and white; keep the HTML's #b34c45 and #aeb6b1.
   - Make the lights blink (v5.4 does not). Top beacon as a flashing obstruction light at about 30 flashes per minute (1 s on, 1 s off). Steady red side lights at 1/3 and 2/3 height.
   - Implement as Neon parts plus a small `PointLight` toggled by a client-side loop.
   - Placement: measure the sunset azimuth in Studio (`Lighting:GetSunDirection()` at the chosen sunset ClockTime and latitude). Place the tower 1.5-3 km from the town centre along that azimuth, on a ridge of the hills band, so it is backlit at sunset from both squirrel height and drone altitude.
   - The existing towers ((646,-213) radio and (629,218) cell) can stay as near-town landmarks or move. Designer decision.
6. **Drone readability.** At about 300 studs the drone sees the whole 4.3 x 2.5 km town. Roofs, landmarks (bridge towers about 98 st, clock tower 120 st, radio tower 315 st, which is above drone cruise height and a collision hazard) and the district palette must read from above. The Galleria glass roof and the Quay's varied roof colours already help.

**Recommended layout (inferred; designer to confirm, see Open questions).** Ocean to the **north** (beyond z 443): the Willow River already ends at z 443 and can become an estuary, with the marina at the river mouth near (850, 480). Beach and pier sit north of Sycamore Park and the cemetery. Mountains, hills and plains lie to the **south and west**, behind the estates (z < -560) and the police station (x < -586), with the river flowing from the southern hills (it starts at z -244). The sunset-silhouette tower then sits west or south-west, depending on the measured sun azimuth.

---

## 15. Brief deltas (scope: districts, scenery, backdrop, art, audio)

| Brief / addendum | HTML v5.4 | Delta |
|---|---|---|
| Section 1: v5.4 canonical, superset of v5.2 incl. Galleria (v5.3) and overflights (v5.4) | as documented | retain the Quay, Galleria, overflight and towers |
| Section 2: the town is a data file (lots with type, footprint, facing, params); WorldGen builds from data, never hand-placed parts | HTML builds procedurally from code constants | this spec plus `lots_districts.json` are the data seed. Generators such as `makeQuayBuilding` become lot types with params (index or variant, colours, label) |
| Section 2: StreamingEnabled; several thousand studs end to end; 1 unit ≈ 2.5 st | world about 1732 x 996 units ≈ 4330 x 2490 st | backdrop must be Persistent or impostor; the Quay and Galleria stream as regions |
| Section 3 Districts: Riverside old town with stone arch bridge, cobbled quays and rooftops | 30 facades, 5-arch bridge, docks, market | retain. **Interiors are not required by the brief**; see the next row |
| Section 3 Neighborhood expansion: restaurants about doubled (café, bakery, bar and grill…) with outdoor seating or back-alley dumpsters; bookshop, music store; small marina on the ocean side | Quay fascias already name a bakery, tea room, pub (Old Anchor), café-like Copper Kettle, apothecary, books, cobbler; Galleria has books, records, café | promote selected Quay facades to enterable restaurant and shop lots with seating and dumpsters (foraging). The marina is new and on the **ocean**, not the river docks |
| Section 3 Galleria: six shops, upper gallery, coin fountain, interior lighting, camera constraints | all present | retain. Map coins to the brief economy (Open questions) |
| Section 3 Backdrop | none (fog edge) | all new: see 14.4 |
| Section 3 Hollow trees (11; 2 premium near the best gardens and feeders) | none | the treehouse oak (-142,154) near the westside garden plots and stream is a candidate site (inferred) |
| Section 4: one actor model, every human is an actor | 8 Quay ambient walkers are decorative and non-bitable | replace with real human actors or remove |
| Section 7 Foraging: gardens, bird feeders (risky), trash cans and restaurant dumpsters, apple trees, the mall plaza | 3 garden plots, 2 bird feeders, 7 trash cans, 0 dumpsters; mall plaza has coins | add feeders, dumpsters and trash in data; the plaza becomes a forage zone |
| Section 9 Hospital: reception, triage, two wards, isolation ward, pharmacy, staff room, ambulance bay, roof access route | see 2.6 | add the isolation ward, pharmacy, staff room, a second ward and a roof route. Make the building seamless (no teleport) |
| Section 10 Drone: "the role that justifies the backdrop" | n/a | backdrop and roofs must hold up at 300 st |
| Section 11: AI-only birds, nests, butterflies, garden insects | birds and nests in v5.4 (other extractor) | gardens from section 5 are insect spawn anchors |
| Section 12 Seasons: visible day and night; winter with snow, bare trees, dimmer light | static presets only | full lighting state machine (14.3) plus winter grade; moon phases tied to the calendar |
| Addendum A1: town map with marker layers; patrol cars drivable | no map | district bounds and tags (section 1) feed map labels. Decide whether the Quay bridge and quays are drivable: the bridge deck is 15.6 wide, there are no Quay roads, and quay-front widths are tight between buildings and the embankment |
| Addendum A2: parking (hydrant) tickets, stop-sign running, burglars, hospital fetch tasks | 4 hydrants and 4 stop signs as decorations; 24 supply boxes on 2 racks | place hydrants and stop signs systematically in data (at intersections and curbs). Expand the supply racks into the pharmacy item shelves |
| Addendum A3: avatar colours clamped to the town palette | palette stats in section 11 | clamp blended colours to saturation ≤ 0.55 (p90) and value 0.39-0.91 (p10-p90). Allow neon only as a single signature accent |

---

## 16. Porting notes (Roblox)

- **Build pipeline.** The brief says to build from data, never hand-placed parts. For StreamingEnabled and fast server start, run the generators at **build time** (a Rojo/Lune or Studio plugin step that turns lot data into models) rather than at every server boot. The data stays the source of truth. If built at runtime, the server must finish before streaming players in.
- **Authority.** All scenery is static and server-owned. Purely visual animation stays on the **client** and is never replicated: water waves, boat bob and roll, banners and bunting, fountain jets, droplets and ripples, coin spin, overflights, beacon blinking, ceiling glows, motes, grass sway.
- **Mall doors.** Make the doorway passable at all times (door parts `CanCollide = false`) and animate them per client. Server-side door collision with 50 players would churn replication. The HTML door boxes only exist to stop the squirrel clipping glass.
- **Mall coins** are per-player collectibles. The server validates pickup distance (0.95 units → about 2.4 st, plus a latency allowance); each client hides coins it has found. The fountain toss is client VFX plus a server currency decrement.
- **Camera.** Reimplement `constrainMallCamera` as a client `workspace:Spherecast` from the subject to the desired camera position. Use a "CameraBlocker" collision group for the mall walls, glass, gallery slabs and stair steps, and hospital partitions. Roblox's default Popper cam is not enough for the custom squirrel camera.
- **Surfaces.**
  - Quay roofs (sloped), the clock-tower pyramid, docks and the bridge deck become real collidable geometry; the analytic `riverRoofAt` and `riverDeckAt` disappear.
  - Keep the rule "only snap up to a higher surface if within 0.5 below it": in Roblox this is natural for physical characters, but the rail and route system must still query it.
  - Stairs: 24 steps of 0.269 units [0.67 st] work with Humanoids for humans. The squirrel uses route or ground logic.
- **Water.** Replace `recoverRiverFall` with a server-side region check on the river channel volume (or Terrain water plus the `Swimming` state). Keep the "teleport to nearer quay" rule for squirrels and decide whether humans can swim (Open questions).
- **Routes.** These must be registered in the Routes module (other extractor) for this scope:
  - per Quay building: ridge, downspout and gutter (30 × 3);
  - 2 parapets, 2 chains, 2 × 2 tower routes and 28 bunting wires;
  - 6 willow trees;
  - 2 Galleria downspouts and 2 rooftop routes;
  - treehouse ladder, floor and deck.
- **Performance.**
  - Quay buildings: author about 6 modular MeshPart kits (body, jetty, roof, timber set, window set, door) and recolour per lot instead of hundreds of parts each. The HTML already merges per building.
  - Fountain: 104 basin coins as one MeshPart; 96 droplets via `ParticleEmitter`.
  - Bunting: 196 flags as one mesh per line, or a `Beam` with a flag texture.
  - Lamps: Neon by default; enable `PointLight`s only near players and only at dusk or night (client).
  - Mall lights: 4 PointLights at most, client-toggled by distance (the HTML hides them beyond 190).
  - Trees: StreamingMesh LOD on willows and landmark towers.
- **StreamingEnabled.**
  - Persistent: backdrop, radio tower, clock tower, bridge towers, the Galleria shell (drone landmarks).
  - Atomic models for each Quay building, shop and hospital zone, so collisions and routes arrive together.
  - `StreamingTargetRadius` must cover the drone's view; the drone may need `Player:RequestStreamAroundAsync` along its flight path.
- **Lighting state.** Replicate one number, the in-game time (or `workspace:GetServerTimeNow()` plus an epoch). Each client computes the Lighting, Atmosphere, Sky, Clouds, post-effects and moon from it. Do not stream `Lighting` property changes every frame from the server.
- **Environment-pass bug.** Port the v3.5 shrubs, fences, gardens, stream and ice-cream shops terrain-following, and give the ice-cream shops colliders and real signs. The HTML has them half-buried and walk-through (section 5).
- **Audio.**
  - Replace oscillator `fx` with authored `Sound` assets: positional for world events (dog, cat, siren, splash, fountain), 2D for UI events (coins, flashes).
  - Add ambience the HTML lacks: river water near the Quay, fountain loop, mall interior murmur or music, birds by day and crickets at night, wind at drone altitude. These are suggestions, not brief requirements.
  - Voices: no browser speechSynthesis. Either record a VO set (per voice type × personality: panic / bluster / wary) or evaluate Roblox's text-to-speech audio object (verify availability and limits).
  - NPC speech bubbles: `BillboardGui`, not chat, so the chat filter does not apply to authored lines.
  - Remove or soften profane lines ("bastard", "hell", "damn") for the target content maturity.
- **No "pause".** Multiplayer cannot pause. Drop the pause shield, blur pause and context-loss UI. Keep the "recover to last safe position" rule on the server (fall below the world, NaN, stuck), and set `Workspace.FallenPartsDestroyHeight` below the river bed and sewers.
- **Graphics panel.** The Golden / Clear / Blue Hour picker is superseded by the day cycle; keep it as a dev or admin override. Roblox's own quality slider replaces the Auto / High / Ultra / Performance tiers, but the client should still read the quality level to drop optional effects (14.2).
- **Fonts.** Barlow Condensed and DM Sans are probably not in the Roblox font library (verify). Nearest built-ins are a condensed sans (for example Roboto Condensed or Oswald) for display and Builder Sans or Montserrat for body text.

---

## 17. Open questions

1. **Backdrop orientation.** Which side gets the ocean and which the mountains? The proposal is ocean north at the Willow River mouth and mountains south-west (14.4). What lies south of the river channel's cut-off at z -244 and east of x 1150?
2. **Day length vs sunsets.** Brief section 12's "winter cycle every ~50 real minutes" implies about 71 s per in-game day (5 + 1 weeks = 42 days). A linear clock would give sunsets of about 2-3 s. Use a non-linear time curve that holds sunrise, golden hour, sunset and blue hour longer, or a longer day? Moon phases (29.5 days ≈ 35 real minutes at 71 s per day) depend on this.
3. **Moon implementation.** Roblox has no native phases (feasibility spec section f). Choose between swapping `MoonTextureId` per phase (simple; uses the engine moon path, so moonrise timing is not phase-correct) and a custom client moon (correct elongation and terminator, more work).
4. **Radio tower placement.** Keep the HTML towers at (646,-213) and (629,218) and add a new backdrop tower on the sunset azimuth, or move the existing radio tower? Should the 315-stud tower be a drone collision obstacle?
5. **Quay interiors.** Which Quay facades become enterable restaurants or shops for the brief's expansion, and which stay facades? Do Quay roofs remain squirrel highways (90 routes)?
6. **Quay life.** Should the 8 decorative walkers become real actors (brief section 4)? Do traffic, police cars (Addendum A1) and ambulances serve the Quay and Galleria, which v5.4 never visits?
7. **Galleria coins.** Do Squirrel or Gold coins survive the port, or map to brief credits and nuts? Does the wishing fountain get a function (credits sink, a luck buff) or stay cosmetic? Do coins respawn per session or per player?
8. **Hospital layout.** Approve the expansion in 2.6 (Ward A and B, isolation, pharmacy, staff room inside the 94 x 96 shell or an annex). Should the hospital be seamless (walk-in) rather than the HTML's modal teleport? The camera, fog and roof hiding then need rework.
9. **River crossing and swimming.** Can humans or deer swim or fall in? What happens to an AI human in the water? The HTML only defines squirrel recovery.
10. **v3.5 environment pass.** Keep the duplicate ice-cream "competitor" shops (plus the ice-cream van) as two of the brief's restaurant lots? Give the stream real water and a crossing?
11. **Clock tower.** Should the static clock hands show the in-game time? This is cheap and reinforces the day cycle.
12. **Sightings and radar map style (A1).** Top-down stylised map generated from lot data, or a real-time render? The district tags in section 1 are available as labels.
13. **Content maturity.** Approve replacing the profane NPC lines.

---

## Added by verifier

Items in scope that the extraction above omitted or under-stated. Line numbers refer to `reference/v5_4_game.js`.

1. **Hospital camera partition test** (7367-7380). Besides the 1.8 inset and y clamp, the interior camera samples 16 points from the look target to the desired camera position. Sampling stops once a point is above floor+7. If a sample falls within 0.16 of any `hospitalObstacles` partition AABB, the camera is pulled back to the previous clear sample. The Roblox camera (section 16) needs the same rule for the hospital partitions, not only the mall.
2. **Background colour is overwritten every frame** (9123-9132). `applyLighting` sets `scene.background` to the preset horizon, but `updateNewSystems` resets it every gameplay frame to #a8d0ef outside, #455c5b in the hospital and #373f38 in the sewer. Outdoors the sky dome hides the background. The dome's `ShaderMaterial` does not take fog (three.js default `fog: false`), so the unfogged dome horizon meets fogged geometry at the fog colour, which causes the golden-preset mismatch noted in 10.3. Fog colour is only re-set while not indoors (13239).
3. **"Poles" in the v3.5 pass title are not built there** (12555, 12752-12753). The comment says poles, routes and cable meshes come from the earlier road-aware utility network, and startup runs `verifyUtilityPlacement` (530, called at 16053). Pole placement belongs to the core extractor.
4. **The only blinking light in v5.4 is on emergency vehicles** (`updateEmergencyBeacons` 12123). Paired lamps alternate emissive 2.6 / 0.13 at `floor(time*4.7) % 2`, about 2.35 flashes per second per lamp. The radio-tower beacon (2999-3001) never uses it. The pattern (swap emissive intensity on a timer) is the template for the brief's tower obstruction lights at the slower 0.5 Hz suggested in 14.4.
5. **Hospital spur ground and access roads** (3807-3812). `addNorthernGround(-429, -269.96, 245, 440)` covers the spur. An asphalt ribbon along z 283 (12 wide, x -417..-238) has sidewalks at z 273.5 and 292.5 (2.7 wide). The drive at x -356 is 8 wide (z 284..305), with sidewalks at x -362.5 / -349.5 (1.7 wide, z 283..306). Road data also lives in `roads.json`.
6. **Lamp inventory for the lighting budget.** There are 58 `riverLamp` instances: 34 on the banks (13586), 12 on the bridge (13787), 6 in the market square (14054) and 6 on the promenade (14989). The plaza adds 6 dark posts with glow heads (14993). None is a real light and none has a collider. Bank bollards, market benches and promenade lamps are walk-through too (no `riverCollider` or `mallColliders` entry), so the port must decide which of them become solid.
7. **Glass is shadowless.** `mallBox` turns off cast and receive shadows for `mallMat.glass` (14275-14278), and glass has `depthWrite: false`. Both the skylights and the storefronts let the sun through without casting shadows. In Roblox, set `CastShadow = false` on glass parts to match.
8. **Display panel behaviour** (13322-13414). The G key toggles the panel, Escape closes it, and opening it pauses the game (`gamePaused = true`). The light-preset select calls `applyLighting` immediately. The legacy `qualityBtn` "SHADOWS: HIGH/OFF" handler (5701) is replaced by `initRefresh` (13346), so v5.4 only has the GRAPHICS cycle.
9. **Legacy ambulance timing** (8989-9027). The ambulance first appears 18 s after start, at (639, 283), heading west. The turn leg into the drive runs at 12.5 × 0.85 u/s. After parking it waits 145 s before the next run. The siren pulses only while it is moving (`mode !== "park"`).
10. **Quay walker facing** (14155-14157). Each walker flips yaw between 0 and PI as `cos(0.095t + phase)` changes sign, so it turns around at each end of its ±15 pace.

## Verification log

Format: claim (section) -> result. All checked against `reference/v5_4_game.js` unless noted.

1. RIVER constants startX 687, endX 1150, zMin -244, zMax 443, halfWidth 52, bankY 8, waterY 2.4, bedY -2, deckY 15.8, bridge 790/910, ramps 744/956 (3.1) -> OK (419-435)
2. riverCenter = 850 + 9 sin(0.009 z) (3.1) -> OK (436)
3. Terrain blend smoothstep(x, 687, 735) to y 8; -2 in water (3.1) -> OK (458-464)
4. riverDeckAt ramps 744..790 / 910..956, |z| ≤ 7.8 (3.1) -> OK (445-457)
5. Global clamp x -586..1146, z -560..436; ≈ 4330 x 2490 st (0) -> OK (6765-6766, 3271)
6. District tag strings and precedence (1) -> OK (9062-9078, 14160, 15041, 15970-15982)
7. Quay group visible only when x > 610 and not hospital/sewer (1) -> OK (14145)
8. Mall visible within 190, atMall pad 24 / fountain 18 (1) -> OK (14332, 15028)
9. Hospital centre (-356,353), 94 x 96, base ≈ 0.10, floor = base+0.42 (2.1) -> OK (3802-3809; terrain recomputed 0.100)
10. Plinth 97x0.8x99, floor slab top at local 0.66 (2.1) -> OK (3821-3822)
11. Front wall 35.5 segments at x ±29, lintel 19 x 5 at y 10, opening 22.5 x 7.5 (2.1) -> OK (3830-3832)
12. Door leaves 7.55 x 7.6, pivots x ±8.2 z -48.67, angle -side*open*1.36 (2.1) -> OK (3834-3844, 8435)
13. Canopy 22x0.75x7.3 at y 8.1 z -51; columns r .3 x 7.5 at x ±9, z -54 (2.1) -> OK (3845-3846)
14. Roof slab 97x0.75x99 at 12.8; landing HOSP_BASE+13.34 (2.1) -> OK (3847, 6136-6144); hiding rule FIXED ("inside" -> "inside or in the duct", 9041)
15. 12 ceiling glow panels x -34,-12,14,33 × z -21,5,30 (2.1) -> OK (3848-3852)
16. Partition coordinates (z -12 walls, x ±22, z 2 low walls, z 43 screens) (2.2) -> OK (3872-3879)
17. Waiting seats at x -14, 16 × z -35, -18 (the -30/32 rows are in the triage bays) (2.2) -> OK (3853-3857)
18. Carts (2) and stretchers (2) (2.2) -> FIXED (3 carts incl. (39,7); 3 stretchers incl. (-18,33))
19. Supply racks x -42/-36, 4 shelves x 3 boxes = 24 (2.2) -> OK (3931-3945)
20. Desk colliders 12.5 x 3.8, bed colliders 7.3 x 11.3 (2.2) -> OK (3968-3984)
21. Interior camera inset 1.8, y floor+0.22..11.2 (2.2) -> OK (7363-7366)
22. Enter within 8 of (-356,298), |dy| < 4, 1.45 s smoothstep, flip at 47 %, inside z 314; exit within 6 of (-356,312) to z 294 (2.3) -> OK (8425, 8437-8455, 8475-8496, 8556-8572)
23. Door auto-open within 15 of (-356,305), holds 1.5 / 2.4 / 4.0 s (2.3) -> OK (8429-8455)
24. Ambulance: west on z 283 at 12.5, park z 295 for 16 s, hide 145 s (2.2) -> OK (8989-9027)
25. Duct nodes and heights (2.4) -> OK (4076-4084)
26. Duct tube 2.7 x 1.76, opacity .29, ribs every 5, lights every 8, 3.1 hole (2.4) -> OK (4126-4178)
27. 4 grilles 2.6 x 1.3 (first rotated 90°), hatch 2.7 x 2.9 with gold strip, glow at nodes 2,3,4,6,7 (1-based) (2.4) -> OK (4119-4125, 4179-4210)
28. Hospital sign sizes/positions (2.5) -> OK; SQUIRREL BITES y FIXED (9.25 -> base+9.25 ≈ 9.35)
29. flatSign regex and shrink sizes w 5.2..8.1, h 0.89..1.32, y terrain+2.68 (2.5) -> OK (682-698)
30. Bank meshes 128 x 20 grids, cobble tint #c4bdab, rough .97 (3.2) -> OK (13525-13575)
31. Embankment walls 1.3 x 7.8, 6-long segments, coping 1.9 at y 8.02 (3.2) -> OK (13578-13584)
32. Bank lamps 34 (17/side), z -218..394 step 34, skip |z|<24, centre ±55, bollard 2.2 in / 7 along (3.2) -> OK (13585-13590)
33. Lamp model post 4.1, lantern 0.42 x 0.67, emissive #ffc66d at 1.2 (3.2) -> OK (13598-13612)
34. Water 20 x 150 grid, wave formula, deep/glint colours (3.2) -> OK (13614-13655)
35. Arches 5 at 802..898, inner r 9.6, spring 3.5, crown 13.1, depth 15.7 (3.3) -> OK (13657-13672)
36. Voussoirs "alternate light/dark" (3.3) -> FIXED (every third dark: 5 dark, 10 light)
37. Cutwater piers r 2.3/3.0 x 3.6 at x 790..886, scale z 3.2, 45° (3.3) -> OK (13688-13696)
38. Parapets at deck+1.1, z ±7.7, `fence` routes, posts every 4 with 4 x 0.3 colliders (3.3) -> OK (13757-13768)
39. Chains through (772,14),(814,34),(850,25),(886,34),(928,14), z ±8.7, 45 hanger samples, `wire` (3.3) -> OK (13769-13784)
40. 12 bridge lamps at x 752,777,838,862,925,947 × ±6.45 (3.3) -> OK (13787-13788)
41. Tower piers z ±10.7, 8x19x7.2; colliders y 15.8..35.1 and 29.2..33.2; arch clearance 13.4 (3.3) -> OK (13698-13729)
42. "4 corner turrets" per tower (3.3) -> FIXED (4 per pier, 8 per tower)
43. Tower downspout (x+4.5, z 7) deck+0.25 → +17.7; gallery route y 33.5 z 7 → -7 (3.3) -> OK (13732-13748)
44. Quay rows: positions, yaws, label and index offsets (3.4) -> OK (14034-14041)
45. Generator formulas w/d/h/rise and colour arrays, awning when index%3==0 (3.4) -> OK (13826-13874)
46. Collider (w+0.9) x (d+0.7) swapped when sideways, base..base+h-0.05 (3.4) -> OK (13884-13893)
47. riverRoofAt formula (3.4) -> OK (13473-13486)
48. Clock tower (1051,35): plinth 13, shaft 9x29x9 to y 37, faces at y 32, roof 37..45, spire ≈ 48, platform formula (3.5) -> OK (13911-13963)
49. 5 stalls at listed positions, counter 5x1.2x2.8, collider 5 x 2.8 x 1.3 (3.5) -> OK (13965-13984, 14045-14052)
50. Square: 6 lamps at x 978/1010/1092 × z -40/68 with benches at x+5 (3.5) -> OK (14054-14059)
51. Dock "projects 6 into the water" (3.6) -> FIXED (centred 6 inside the wall line; projects 13)
52. Boat yaw "±0.2" (3.6) -> FIXED (-0.2 even index / +0.22 odd index)
53. Boat y 2.54, bob ±0.12 at 0.7 rad/s, roll 0.026 (3.6) -> OK (13988, 14148-14151)
54. 6 willows h 19, crown 9, 4 branches, 850 leaves at the listed positions (3.7) -> OK (14060-14080)
55. Bunting 28 lines (14/side, z -180..340 step 40), centre ±59, +23, y 14/12.6/15, 7 flags (3.7) -> OK (14081-14093)
56. Signs BELLWETHER QUAY → (650,25,-0.15), WILLOW RIVER (780,38,PI/2), OLD TOWN MARKET → (974,20,PI/2) (3.7) -> OK (14097-14099)
57. 8 walkers at x 778/926, z -150/-45/60/165, z0 + 15 sin(0.095t + 1.3i) (3.7) -> OK (14102-14115, 14155)
58. recoverRiverFall condition y ≤ 2.85, teleport centre ±57, y 8.18, z clamp -225..425, 2 s cooldown (3.8) -> OK (14116-14140)
59. startAtRiver spawn (780, 8.18, 51), yaw -0.94, pitch 0.3 (3.8) -> OK (14169-14177)
60. Orchard sector-3 candidates and fill rows (3.8) -> OK (15273-15327); appleSiteClear line FIXED (15153 -> 15152)
61. MALL x 1102, z 338, 78 x 108, floor 8.14, gallery 14.6, roof 22.94, fountain (1102,252) (4.1) -> OK (14191-14203)
62. mallUpperAt / mallStairAt (24 steps, 0.269 / 0.958) / mallBaseAt / fountain surfaces / roof 23.12 (4.2) -> OK (14335-14369)
63. mallBlocked padding 0.27, band [y, y+0.38], stair and fountain rules (4.3) -> OK (14380-14396)
64. constrainMallCamera pad 0.1, t = max(0.08, lo-0.035), called at 7394 and 7413 (4.3) -> OK
65. Facade 32.5 segments, entrance 13 x 6.8 under a 13 x 7.8 lintel, doors 5.8 x 6.4 (4.4) -> OK (14659-14686)
66. Entrance canopy "16 x 0.3 x 7 with a glass top at y+6.9" (4.4) -> FIXED (dark slab at +6.9, 14 x 6 glass top at +7.1)
67. Clerestory 10 x 4.6 at y+9.2, 8 skylights 25.3 x 11.5, stone slabs 25.5 x 108 (4.4) -> OK (14669-14674, 14757-14762)
68. Atrium columns, glow strips at z -35/-3/29, planters, benches, back sign (4.4) -> OK (14763-14790)
69. Gallery bridges dz -53..-47 / 48..53, balustrade split at dz 48 (4.4) -> OK (14687-14725)
70. Stairs 24 steps at x ±7.5, handrails at ±5/±10 (4.4) -> OK (14726-14748)
71. 4 PointLights #ffdfa9, 38, 46, decay 2 at (±25, +5.4, ±30); only real-time lights besides the sun and hemi (4.4) -> OK (14791-14801; full-file grep)
72. Downspouts x 1062.4 / 1141.6, z 288, up to 23.19, roof routes to z 388 (4.4) -> OK (14802-14810)
73. Six shops: names, accents, z 306/338/370, fit-outs, coins at x ±17.5 dz -10/+9 (4.5) -> OK (14525-14632, 14777-14786)
74. Fountain lathe r 7.95, bowls r 2.9 @2.55 / r 1.7 @4.4, 52+52 coins, 12 jets, 96 droplets at 0.68, 5 ripples 1.7 → 6.7 every 4.5 s, 48 tiles, sign wall z 241.2 (4.6) -> OK (14812-14982, 15057-15069)
75. Plaza 6 lamp posts; promenade 6 quay lamps (4.6) -> OK (14984-14999)
76. Door logic: dist < 16 and y < floor+5, factor 1-exp(-5dt), x = 1102 ± (2.9 + 6.1·open) (4.7) -> OK (15035-15038)
77. 25 coins (12 shop + 8 gallery + 1 gold + 4 fountain), pickup 0.95, no respawn (4.7) -> OK (grep finds no reset of `found`)
78. Coin toss: 11.5 radius, |y-8.14| ≤ 2.8, 0.7 s cooldown, purely cosmetic (4.7) -> OK (15002-15026)
79. startAtMall (1102, 8.32, 238), yaw PI, pitch 0.22 (4.7) -> OK (15104-15125)
80. Environment pass placed at y 0; terrain heights 2.26 / 1.42 / 0.23 / 0.72 / stream 0.03-0.14 (5) -> OK (recomputed with baseTerrainHeight: 2.264, 1.417, 0.235, 0.723, 0.034-0.138)
81. 13 shrubs in 5 clusters, #648843 every 4th (5) -> OK (12758-12773)
82. Fence specs, posts every ≈2.4 (5) -> OK (12583-12618); run 0 crossing house 2's front walk -> OK (inferred: core_house_2 at (-53,51) faces -Z)
83. Ice-cream shop parts and blank signs (5) -> OK (12648-12718)
84. addDetail group yaw = variation·0.71 and variation palette (6.1) -> OK (3054-3068)
85. Kind dimensions (hydrant ≈ 2.1, streetlight 9 / 3.3 arm, stop sign r .61/.68 at y 2.4, hoop rim r .66 at 6.7, compost lid 2.6 x 2.5 at 2.12) (6.2) -> OK (3069-3241)
86. Placement formula and counts 38 + 14 + 7 = 59 (6.3) -> OK (3243-3267, 3443-3455); JSON detail_00/01/02/04/40 positions recomputed
87. Treehouse site (-142,154), base 1.52, h 13.2, floor ≈ 14.72 (7) -> OK (9501; terrain recomputed 1.520)
88. Treehouse stilt braces "to the floor centre" (7) -> FIXED (angled inward to 0.38x, 0.38z)
89. Treehouse chest "1.45³" (7) -> FIXED (1.45 x 0.81 x 1.45)
90. Treehouse ladder, floor and deck routes; floor collision |dx|<4.2, |dz|<4.0 (7) -> OK (9530-9556, 6237-6242)
91. Radio tower 114 + 11 mast, beacon at base+126, emissive #ff351e at 0.55, `radioBeacon` never referenced again (8) -> OK (2976-3004; grep finds one use)
92. Cell tower H 99, r 1.65 → 0.9, 14 sides, rings at 0.67H / 0.88H, 6 panels on radius 4 (8) -> OK (3005-3027)
93. signCanvas 512 x 160, bold 88px, emissive 0.14; mallSign height 128, 78px, #f9ebc9, 0.16 (9) -> OK (658-679, 14296-14328)
94. Boot: background #a8d0ef, fog #bed6db 310/1050, ACES, exposure 1.42, FOV 72 / 0.12 / 1500 (10.1) -> OK (5-26)
95. Hemisphere ground "#657750" (10.1) -> FIXED (#657650, line 28)
96. Sky dome r 1200; 34 clouds ±330, y 95-155, opacity .15 → .065 (10.1) -> OK (918-948, 12888)
97. Atmosphere shader halo 28 / 0.18, disc 750 / 0.8, cloud fbm and smoothsteps (10.2) -> OK (12862-12889)
98. Light preset table (all 3 rows) and inferred sun elevations 44° / 61° / 26° (10.3) -> OK (12809-12843; elevations recomputed)
99. Default preset golden, localStorage `spicy-render-v5` (10.3) -> OK (101, 12908-12915)
100. Sun follows the player: snapped 1/8, y+9, re-aimed after moving > 0.5 (10.3) -> OK (13244-13254)
101. Exposure overwrite description (10.3) -> FIXED (updateNewSystems sets 1.19 / 1.1 / 1.42, not only 1.42)
102. Enclosed fog lerp 12 % toward 15/53; camera far 55 / 125 / 65 / 1500 (10.3) -> OK (9115-9122)
103. Shadow map 2048/4096, ±76/±100, near 1, far 300, bias -0.00012, normalBias 0.09 (10.4) -> OK (12925-12949)
104. Canopy casters r 90-110, re-evaluated every 0.8 s; leaf emissive 0.075 double-sided; breeze amp 0.003-0.007 (10.4) -> OK (9136-9146, 191-203, 1941-2895, 15971-15975)
105. Overflight timing 34 / 90-150 / 48 s, 1260 units, altitude 165-205, offsets ±95/±75, heading ±1.1 alternating (10.5) -> OK (15509-15633)
106. Overflight "Hidden indoors" (10.5) -> FIXED (only hospital/sewer/duct)
107. `mat` at line 44 (11) -> FIXED (45)
108. M palette and noiseCanvas textures, repeats and tints (11) -> OK (51-79, 330-397)
109. Quay and Galleria material palettes (11) -> OK (13438-13449, 14228-14243)
110. UI shell colours and fonts (11) -> OK (reference/v5_4_shell_head.html lines 9-11)
111. Palette statistics: 1068 distinct literals; S 0.08/0.30/0.55; V 0.39/0.66/0.91 (11) -> OK (recomputed)
112. Quality tiers: max ratio 2 / 1.5 / 1, budget 5.0 / 2.8 / 1.4 Mpx, min 0.6 (12.1) -> OK (12951-12969)
113. Auto adaptation: EMA 0.035, 10 s windows, > 30 ms → scale -0.12 (min 0.7), else > 40 ms → performance, never steps up (12.1) -> OK (13258-13272)
114. Online detail: bark normalScale 0.6, tint #b0ac9b; bloom 0.13 / 0.35 / 1.15; HDRI and envMap 0.3; timeouts 12 s / 14 s; status strings (12.2) -> OK (12800-12806, 13063-13222)
115. Grass tufts (90 per tree, |x| ≤ 700, radius 3.5..min(20, crown+2), 125 visibility) and 96 motes (12.3) -> OK (12979-13050, 13255-13263)
116. validatePlayerState: lastSafe saved "while grounded and off-rail" (12.4) -> FIXED (also requires not in a duct)
117. Context restore "reloads" (12.4) -> FIXED (re-applies quality/lighting and re-fetches online detail; no page reload)
118. updateOptional isolation; dt cap 0.08, realDt ≤ 0.2, ≤ 1/60 substeps (12.4) -> OK (15915-15938, 15940-15946, 16001-16004)
119. batchTreeBranches merges groups of 4 or more same-material meshes (12.4) -> OK (126-171)
120. fx oscillator: 0.64× pitch drop, gain to 0.001 (13) -> OK (6451-6466)
121. SFX table: all 29 call sites, args and lines (13) -> OK (grep of `fx(`)
122. speakCitizen rate / pitch / volume / 2.4 s cooldown; "Watch out!" volume 0.3; poster line; VOICES chip (13) -> OK (4752-4778, 5563-5571, 11286-11305, 5708)
123. Line pools spot 6 / surprise 2 / hit 3 / escape 3; bubble life 4.6 s; sayCooldown 8 (13) -> OK (4734-4745, 4779-4786)
124. "No day/night changes" comment; no moon, stars or time of day in v5.4 or v4.1 (10.3) -> OK (11307-11308; grep of both files)
125. Brief backdrop list and the "50 real minutes" winter cycle → ≈ 71 s per day (14.4, 17) -> OK (Roblox_Rebuild_Brief.txt 105-118, 352-358)
126. EV conversions (log2 1.12/1.08/1.18) and OutdoorAmbient sky/ground mid-mixes (14.2) -> OK (recomputed)
127. Roblox engine facts (PointLight range cap 60, SunAngularSize default 21, GetMoonPhase behaviour) (14.2, 14.4) -> UNVERIFIABLE against the source (engine documentation / feasibility-spec cross-reference)
128. JSON `hosp_entry_canopy` z 301.35 and has_interior true -> FIXED (z 302; has_interior false); `hosp_ambulance_bay` and `hosp_roof` has_interior -> FIXED (false: exterior lots)
129. JSON bridge voussoir and bridge-tower turret notes -> FIXED (same corrections as 36 and 42)
130. JSON spot-checks: quay_bldg_w_00, e_00, e_09, e_10, m_01, m_05 (index, label, size, colours, collider, ridge y); quay_dock_0/1/2 x (812.59 / 887.91 / 900.56); galleria shop 5 coins; galleria plaza, atrium and upper-gallery world coordinates; hospital zone centres; fence post counts; detail_00/01/02/04/40 -> OK
