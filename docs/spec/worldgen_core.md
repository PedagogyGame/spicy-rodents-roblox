# WorldGen Core — Terrain, Roads and Core Districts (v5.4 port spec)

Extractor: `worldgen_core` (Town Layout Part 1). Source: `reference/v5_4_game.js` (every line number below refers to that file).
Data files: `spec/data/lots_core.json` (90 lots / buildings / landmarks) and `spec/data/roads.json` (116 road, sidewalk, rail and paved entries).

Out of scope here and owned by other extractors: climbing routes and trees (only route *positions* that belong to a building are noted), NPC behaviour, vehicles and lanes, the hospital interior, police, the sewer shop, Bellwether Quay, the Galleria mall, the orchard, birds and traffic. Where those touch the layout, this spec lists them as landmarks with a pointer.

Anything marked **(inferred)** is a reading of code behaviour that the code does not state outright.

---

## 1. Conventions

| Item | v5.4 value | Notes |
|---|---|---|
| Unit | 1 HTML world unit | Brief §2: 1 unit is about 2.5 studs. |
| Up axis | +Y | Three.js and Roblox are both right-handed and Y-up, so x, y and z map 1:1 (multiply by 2.5). |
| Yaw | `rotation.y = θ` maps local +Z to world `(sin θ, 0, cos θ)` | This is the same as Roblox `CFrame.Angles(0, θ, 0)`. A model authored facing +Z (brief) keeps the same yaw values. |
| `facing` in lots_core.json | One of `+X`, `-X`, `+Z`, `-Z` (or `n/a`) | The world direction the lot's front (door, shopfront or sign) points. Each lot's `notes` begins with `facing:`, which gives the derivation and the yaw in radians (`+Z`=0, `+X`=π/2, `-Z`=π, `-X`=−π/2). |
| `footprint` in lots_core.json | `w` = extent along world X, `d` = extent along world Z | Already rotated into world axes. |
| roads.json axis | `"x"`: the road runs along X; `coord` = its centreline z; `start`/`end` = x range. `"z"`: runs along Z; `coord` = x; `start`/`end` = z range. `"free"`: a straight segment from `start` [x,z] to `end` [x,z]. | Axis-aligned slabs (pads, aprons) are written as `"x"` rectangles. |

**Compass conflict (must resolve, see §13).** The HUD compass (`updateCompass` 9854-9856) says "+Z south, −Z north", with +X east. Later code comments and names say the opposite: the "NORTHERN EXPANSION" (park and cemetery) is at +Z and the "SOUTH ESTATE DISTRICT" is at −Z. Earlier comments follow the HUD: `hNW` is house 0 at (−56,−53), and the fuel market is "north-facing" towards −Z. This spec therefore uses axis names only. District names follow the code sections: "north" means +Z and "south" means −Z.

---

## 2. World bounds and ground meshes

| Constant / mesh | Value | Line |
|---|---|---|
| `WORLD_HALF` | 270 (the original 540×540 grid; also the span of every `roadRibbon`) | 399 |
| `PEDESTRIAN_EDGE` | 12.1 (declared, never used; sidewalk centrelines are at ±12.1) | 400 |
| `NORTH_LIMIT` | 440 | 3271 |
| `ESTATE_SOUTH` | −565 (declared, never referenced; the estate ground plane's −565 edge comes from literals `PlaneGeometry(540,300)` translated to z −415) | 2547 |
| Player clamp | x ∈ [−586, `RIVER.endX`−4 = 1146], z ∈ [−560, `NORTH_LIMIT`−4 = 436] | 6765-6766 |
| Main ground plane | x,z ∈ [−270, 270], 128×128 segments, y = terrain − 0.09 | 466-471 |
| East extension | x ∈ [241, 687], z ∈ [−244, 244], 100×94 segments, y = terrain − 0.083 | 602-609 |
| Estate ground | x ∈ [−270, 270], z ∈ [−565, −265], 90×56 segments, y = terrain − 0.084 | 2548-2555 |
| Northern ground | x ∈ [−270, 270], z ∈ [269.95, 443]; and x ∈ [270, 687], z ∈ [243.95, 443]; 70×28 segments each, y = terrain − 0.088 | 3281-3282 |
| Hospital spur ground | x ∈ [−429, −269.96], z ∈ [245, 440] | 3808 |
| Westside ground | x ∈ [−590, −260], z ∈ [−264, 244]; and x ∈ [−590, −429], z ∈ [244, 278] | 9880-9881 |
| River district | x ∈ [687, 1150], z ∈ [−244, 443] (Quay extractor) | 419-435 |

Overall modelled extent: x −590 to 1150 (1,740 units, about 4,350 studs) and z −565 to 443 (1,008 units, about 2,520 studs).

**Ground mesh gaps (inferred).** No ground mesh is rendered for x 270–687, z < −244 (south-east), for x < −260, z < −264, or for x < −429, z > 278, but the player clamp allows walking there. Collision still works because ground snapping uses the analytic `terrainHeight`, not the mesh. There is also a 1-unit seam at x −429…−270, z 244…245. The Roblox build should cover the whole playable rectangle with terrain.

---

## 3. Terrain height functions

```js
// 403-416
smoothstep(t) = clamp(t,0,1)^2 * (3 - 2*clamp(t,0,1))
baseTerrainHeight(x,z):
  dist  = max(|x|, |z|)                       // Chebyshev distance from the origin
  blend = smoothstep((dist - 104) / 86)       // 0 inside dist<=104, 1 beyond dist>=190
  hills = 3.5 + 2.5*sin(0.016x + 0.008z + 1.1)
              + 2.1*cos(0.02z - 0.009x)
              + 1.45*sin(0.034x + 1.3)*cos(0.029z - 0.8)
  return max(-0.02, blend * max(0.1, hills))
```

- **Flat core.** Height is exactly 0 wherever max(|x|,|z|) ≤ 104. This covers the four original houses, their yards and fences, and the central intersection, so many core props are placed at a literal y=0.
- **Rolling band.** Between Chebyshev distance 104 and 190 the hills fade in. Beyond 190 the full hills apply. `hills` ranges from about −2.55 to 9.55 and is floored at 0.1. Sampled maxima: grid 8.58 (at −270,−104); east 9.43 (471,−90; the restaurant sits at y 9.35); estates 9.46; westside 9.27; hospital spur ≤ 4.25 (at −355,440). The steepest gradient is about 0.144 rise per unit (≈8°).
- **River overlay** (`terrainHeight` 458-464; the constants are shared with the Quay extractor): `RIVER = {startX 687, endX 1150, zMin −244, zMax 443, centerX 850, halfWidth 52, bankY 8, waterY 2.4, bedY −2, bridgeZ 0, deckY 15.8, bridgeStart 790, bridgeEnd 910, rampStart 744, rampEnd 956}`.
  - `riverCenter(z) = 850 + 9·sin(0.009z)` (436).
  - Inside the river district, inside the water channel (|x − riverCenter(z)| < 52) the height is `bedY` (−2).
  - Elsewhere in the district: `lerp(base, bankY=8, smoothstep(x; 687→735))`.
  - `riverDeckAt(x,z)` (445): bridge deck height for |z| ≤ 7.8, x in [744, 956]. It ramps 8→15.8 over x 744–790, stays flat at 15.8 to 910, then ramps back down to 8 at 956.
- **No other terrain modifiers exist.** Roads, lots and the pond do not cut or flatten terrain; every structure is seated at `terrainHeight(centre)`.

### Ground and surface resolution (gameplay height)
- `outdoorSurfaceAt(x,z)` (513): `terrain − 0.075`, raised to the highest registered pavement triangle (`pavementHeightAt` 490 re-creates the two rendered triangles of each ribbon quad, so walk height matches the drawn road exactly), and raised to 0.245 on the four core curbs (|x| ≤ 129 or |z| ≤ 129, within 0.16 of ±10.1).
- `getGroundAt(x,z)` (6227): `max(terrain, outdoorSurfaceAt) + 0.18`. It then also considers, in order: the mall floor; river platforms; a car roof (if the player is above roof − 0.32); `roofSurfaceAt` (if the player is above roof − 0.47); the guest-cottage roof (y ≥ 6 inside |x+58|<6.5, |z−83|<6 when y > 5.2); the trampoline bed (y 1.65 within r 5 of (−33,80)); and the treehouse floor.
- `roofSurfaceAt(x,z)` (6111) uses:
  - core houses: gabled `roofY` (eave + (peak−eave)·max(0, 1 − |lz|/(d/2+0.8)), scaled 0.82) + 0.29, over the footprint ±(0.24, 0.2);
  - outer homes: a **flat** top at the absolute peak + 0.29 (their `roofY` returns `peak`);
  - Westside old houses: `by + height + 0.56`;
  - every `commercialBounds` box: roof + 0.17;
  - the hospital: base + 13.34.
  `resolveRoofLanding` lands a falling player when they cross that surface.

---

## 4. Road and pavement network

### 4.1 Pavement registry
- `registerPavement(axis, coord, width, start, end, material, offset, segments)` (474) records a zone only when the material is `M.asphalt` or `concrete` (#c8c4b7). Rails and other materials are drawn but not registered.
- `roadRibbon(axis, coord, width, material, offset=0.055)` (542) always spans −270…270 in 104 segments. `districtRibbon(axis, coord, width, start, end, material, offset=0.07)` (610) uses 95 segments.
- Each ribbon is a two-vertex-wide strip. Vertex y = `terrainHeight(edge point) + offset`, so roads follow grades exactly. UVs are x/16 and z/112.
- `pavementDistance(x,z)` (478) is the distance to the nearest registered rectangle. It is used for the utility-pole rule (≥ 0.95), apple tree siting (≥ 8) and ground detail (≥ 2).
- 48 registered zones in total. The full list is in roads.json (entries with notes beginning "registered").

### 4.2 Road summary (centrelines; asphalt widths; sidewalks are concrete)

| Road | Axis / coord | Range | Width | Sidewalks (centre, width) | Line |
|---|---|---|---|---|---|
| Grid N–S streets | x = 0, −180, 178 | z −270…270 | 18 | x ± 12.1, 3.3 | 571-574 |
| Grid E–W streets | z = 0, −174, 171 | x −270…270 | 18 | z ± 12.1, 3.3 | 575-578 |
| Commercial boulevard | z = 0 | x 247…681 | 26 | z ±17.4, 3.3 (x 249…679) | 638-639 |
| Commercial cross street | x = 347 | z −215…219 | 29 | x 329.5 / 364.5, 3.4 (z −212…216) | 640-641 |
| Estate connector | x = 0 | z −329…−263 | 18 | x ±12.1, 3.3 | 2557-2558 |
| Estate avenue | z = −305 | x −258…258 | 20 | z −317.1 / −292.9, 3.5 | 2559-2560 |
| North access | x = 175 | z 233…422 | 12.5 | x 165 / 185, 2.8 (z 248…421) | 3308-3310 |
| North cross road | z = 283 | x −241…651 | 11 | z 273.7 / 292.3, 2.2 (x −241…650) | 3311-3313 |
| Hospital road | z = 283 | x −417…−238 | 12 | z 273.5 / 292.5, 2.7 (x −421…−238) | 3809-3810 |
| Hospital driveway | x = −356 | z 284…305 | 8 | x −362.5 / −349.5, 1.7 | 3811-3812 |
| Westside street (`WEST_X` −289) | x = −289 | z −244…267 | 15 | x −299 / −279, 2.5 (z −249…272) | 9882-9883 |
| Westside connector | z = −179 | x −296…−176 | 12 | z −187 / −171, 2.1 (x −299…−178) | 9884-9885 |
| Trolley track (rails, not pavement) | z = 7.38 & 9.92 | x 263…675 | 0.12 each | ties 0.14×2.82 every 3.2 | 7692-7696 |
| Quay approach (groundPatch) | z = 0 | x 650…744 | 16 | cobble z ±11, 3.4 | 13594-13596 |

Vertical offsets above terrain are listed per entry in roads.json; they range from 0.055 (core asphalt) to 0.23 (Westside sidewalks). Different ribbons use different offsets so that overlapping ribbons at junctions do not z-fight.

### 4.3 Connectivity (as built)
- The grid is a 3×3 lattice: N–S streets at x = −180, 0, 178 and E–W streets at z = −174, 0, 171.
- **East.** The z=0 street continues east as the 26-wide commercial boulevard (overlapping x 247–270). Past x = 650 the Quay approach groundPatch carries it on to the bridge.
- **North.** Only the x=175 access road links the grid to the z=283 cross road; it overlaps grid road x=178 from z=233. Grid roads x=−180 and x=0 end at z=270, leaving an unpaved 7.5-unit gap before the z=283 road (whose asphalt starts at 277.5) **(inferred)**. The commercial cross street x=347 ends at z=219 and does not reach z=283 **(inferred)**.
- **South.** Only the x=0 connector joins the estate avenue. Grid roads x=−180 and 178 end at z=−270, about 21 units short of the avenue's north sidewalk edge (z −291.15) and 25 short of its asphalt (z −295) **(inferred)**. The connector continues 24 units past the avenue to a dead-end stub at z=−329. No estate gate is there; the gates are at x=±130.
- **West.** The Westside connector (z=−179) overlaps grid street z=−174 and extends it to the Westside street at x=−289. The Westside street ends at z=267, about 10 units short of the hospital road (z=283) **(inferred)**.
- **Hospital.** The hospital road (z=283, x −417…−238) continues the north cross road (which starts at −241) westward. The driveway at x=−356 leads to the hospital's −Z doors.

### 4.4 Paint, curbs, crossings, signals and signs
- **Core curbs** (580-583): four 258×0.23×0.32 boxes (#aaa79c) along z=±10.1 and x=±10.1, centred on the origin (span −129…129). They are *not* broken at the intersection, so each curb crosses the other street. The walk surface is raised to 0.245 on them.
- **Core sidewalk joints** (584-588): 3.4×0.04 lines every 5.8 from −117 to 115 (41 positions; the loop bound is 117 but the last step lands on 115) on both sidewalks of x=0 and z=0.
- **Core crossing dashes** (589-594): 0.76×0.17 marks at x = ±(11, 12.2, 13.4, 14.6, 15.8), z = ±8.6, plus the mirrored set (swap x and z).
- **Storm grates** (595-598): 1.25×0.67 at (±16, ±9.7).
- **Commercial paint** (643-657):
  - amber centre dashes 7×0.13 on z=0, every 15 from x=275 to 671, skipping |x−347| ≤ 28;
  - white dashes 0.13×6 on x=347, every 14 from z=−210 to 214, skipping |z| ≤ 27;
  - zebra stripes 0.72×1.3 at x=325 and 369 (z −11…11.5, step 2.5) and 1.35×0.72 at z=±22 (x 335…358.4, step 2.6).
  - Restaurant bay lines: x 438…508 step 10 at z=−24 (770). Grass-lot bay lines: x 410…635 step 15 (16 lines per row) at z=139 and z=−135 (911).
- **Estate paint** (2561-2567): 7×0.15 dashes on z=−305, every 19 from x=−246; 0.14×5.2 dashes on x=0, every 13 from z=−322 to −270.
- **North paint** (3314-3318): tan 6×0.12 dashes on z=283 at x = −220, −176, −128, −80, −32, 16, 64, 112, 160, 212, 264, 312, 360, 409, 458, 506, 554, 602, skipping |x−175| ≤ 24.
- **Traffic signals** (700-720): at (321,−29), (371,29), (372,−28) and (320,29). Each has a pole of radius 0.13–0.18 and height 10, a mast arm 2.2 long towards x=347 at +9.2, and a 0.8×2.3×0.65 head at +8.6 with red, amber and green balls. **They are static props** with no phase logic.
- **flatSign** (682):
  - A text panel (`signCanvas`, 512×160 canvas, bold 88px Arial) on a w×h×0.13 box.
  - Text matching `/PARK|CEMETERY|GARDEN|HOSPITAL|EMERGENCY ENTRANCE/` (but not `SQUIRREL BITES` or `HOSPITAL  ·`) becomes a "road guide". Its size is clamped to w 5.2–8.1 and h 0.89–1.32, its centre is placed at terrain + 2.68, and it gets two posts at ±0.34w.
  - All signs are collected in `districtSigns`.
  - Signs in scope: CHILI'S and GRILL & BAR (474, −65.3); FUEL MARKET and OPEN (522/534.6, 97.7); FUEL on the canopy (476, 78.7); FUEL / MARKET / OPEN tower (411, 91); CORNER SHOPS (605, −79.4); SYCAMORE PARK (−61, 296); PARK / CEMETERY ↑ (192, 250); CEDAR REST CEMETERY (453, 303); TABASCO GARDEN (115, 325); HOSPITAL ← (−232, 298).
  - Signs built from boxes with `signCanvas`: WEST TOPEKA POLICE, WESTSIDE FUEL, WESTSIDE STORAGE, and the closure sign.
- **Street fixtures** (`addDetail`, 3054; no collision, no routes):
  - fire hydrants (312,23) and (387,−22); stop signs (324,31) and (371,−34); streetlights (294,−22), (397,23) and (583,−21), each 9 tall with a 3.3 arm;
  - park benches (418,−39), (562,46) and the four park benches; trash cans (538,−38), (419,77) and the three park cans;
  - sprinkler (574,145), flamingo (571,−149), kids' bike (251,126).
  - Each prop's yaw is `variation × 0.71`.

### 4.5 NPC sidewalk lanes (virtual, not paved; the NPC extractor owns the logic)
- `sidewalkLanes` (4817): x-lanes at z = ±12.1, −161.9, −186.1, 158.9, 183.1 and z-lanes at x = ±12.1, −167.9, −192.1, 165.9, 190.1. `pointOnSidewalk` uses only the first four (the core streets, u ∈ [−110, 110]).
- Commercial lanes at z = ±17.4 (x 390…651, turnaround 424/615).
- Park lane z=326 (x −205…112) and mourner lane z=405 (x 306…628) (4867-4869, 4844-4846).
- Note: lane sidewalk offsets (±12.1) are hard-coded and must follow any road changes.

---

## 5. Old Town core (four original lots, flat zone)

### 5.1 `buildHouse(id, x, z, style, faceSign)` (1034-1247)

| id | Position | style / kind | faceSign → front | Size before ×0.82 (w×d×eave / peak) | Wall / trim / roof |
|---|---|---|---|---|---|
| 0 | (−56, −53) | 0 VICTORIAN | −1 → +Z | 22×19×8.9 / 13.5 | #ded7b7 / #f5ecd5 / #63524c |
| 1 | (51, −59) | 1 BUNGALOW | −1 → +Z | 24×20×7.4 / 10.4 | #b6c1b1 / #f2ecdf / #686a60 |
| 2 | (−53, 51) | 2 BRICK HOUSE | +1 → −Z | 22×20×9.1 / 13.1 | #bb8e71 / #e4d6c5 / #615653 |
| 3 | (58, 56) | 3 BLUE COTTAGE | +1 → −Z | 21×18×8.0 / 11.6 | #aebbc4 / #f4e8cf / #6f6f75 |

The whole group is scaled by **0.82**. World footprints are 18.04×15.58, 19.68×16.4, 18.04×16.4 and 17.22×14.76. All four face the z=0 street.

Construction:
- **Shell.** Ceiling slab, floor, rear wall, two side walls (0.24 thick), and a front wall split around a **2.6 wide × 3.5 high portal** with a lintel above. It is a real hollow shell, not a solid box.
- **Facade details.**
  - Clapboard lines every 0.54 on the front and back faces. Style 2 (brick) has none; it gets a random brick-speckle pattern on the −Z face instead.
  - Two windows per long face at x=±0.28w (3.6×3.25, y 3.7), plus upper windows (2.9×2.25, y 7.1) when h > 8. About 30% of lower and 25% of upper windows are dark; this uses the global RNG.
  - Side windows at z=±0.25d.
- **Door.** Hinged on a pivot at local (−1.12, 0, frontZ). It is 2.24×3.32, coloured #597e77 (odd id) or #5b4239 (even id). The house's `houseDoors[id]` entry stores three waypoints, all at x = house x:
  - outside: z + (front − faceSign·1.25)·0.82
  - threshold: z + front·0.82
  - inside: z + (front + faceSign·2.15)·0.82

  | House | outside z | threshold z | inside z |
  |---|---|---|---|
  | 0 | −44.18 | −45.21 | −46.97 |
  | 1 | −49.77 | −50.80 | −52.56 |
  | 2 | 41.78 | 42.80 | 44.56 |
  | 3 | 47.60 | 48.62 | 50.38 |

- **Roof.** `localRoof` builds a gable with the ridge along X, overhanging 0.65 in x and 0.8 in z, with gable infill #d6cfc2. Chimney (styles 0, 2 and 3) at x=−0.28w, z=0.2d. Two random roof vents.
- **Steps and deck.** Three front steps. Back deck 12×4.5; house 0 instead gets a 20×9 deck plus a covered porch (roof at y 4.9, posts, rail).
- **Visible interior hints.** Floor rug, cabinet and lamp behind the door; rear kitchen silhouettes and a lamp.
- **Registration.**
  - `houses[]` entry: `w`, `d`, `cfg.h`/`peak` scaled, `frontZ`, `backZ`, `frontSign`, `indoorCeiling`, `indoorRoof`, `interiorObstacles`, and `indoorName` ["Victorian", "Bungalow", "Brick House", "Blue Cottage"][id].
  - `obstacles[]` entry.
  - Roof ridge route `"<KIND> ridge"` at y=(peak+0.32)·0.82 from x−0.39w to x+0.39w (world).
- **Lot furniture** (1276-1297):
  - front walk 2.7 wide from the front wall to z=±16 (stops about 2.25 short of the sidewalk, **inferred**);
  - driveway 5.3×26 at x = house x ± 17 (outward) with 6 joint lines, centred at z + toward-street·13;
  - mailbox post plus box plus red flag at (x+4, z + toward·(d/2+11));
  - address plaque at (x−2.6, 2.35) on the front.
- **Hedges and flowers** (1253-1275): per quadrant (centre ±56, ±53), 10 hedge balls and 32 flowers at random positions (global RNG). They are excluded from the street band (|x| or |z| < 18–19) and from the house footprint.
- **Parked cars** (1554-1563): at (x±17, z + toward·8), with yaw π for houses 0 and 2 and 0 for houses 1 and 3. Colours carColors[0..3]. A retry loop runs if a car would intersect a fence; none is needed (inferred).

### 5.2 Fences (collision-bearing; 1299-1363)
- `woodenFence(x1,z1,x2,z2,h=2)` (1299): instanced boards 0.44×h×0.115 every 0.49, in 4 cedar colours with ±3% height jitter; posts every 3.3; climb route "cedar fence top" at y = h + 0.1.
- `chainFence(x1,z1,x2,z2,h=1.9)` (1331): a translucent mesh plane (opacity 0.34), posts every 3.1, a top rail, and route "chain-link fence top" at y = h + 0.14.
- Both kinds push to `fenceCollisions`, which blocks the squirrel (distance < 0.37 = r 0.32 + 0.05 in `outdoorBlocked`, or < 0.4 in `collisionHouses`) while y ≤ fence h + 0.25 and below 3.1.

| Fence | From → to | Type | Lot |
|---|---|---|---|
| F1 | (−83,−40) → (−83,−91) | wood | house 0, west |
| F2 | (−83,−91) → (−20,−91) | wood | house 0, back |
| F3 | (20,−91) → (84,−91) | chain | house 1, back |
| F4 | (84,−91) → (84,−42) | chain | house 1, east |
| F5 | (−83,42) → (−83,94) | wood | house 2, west |
| F6 | (−82,94) → (−22,94) | chain | house 2, back |
| F7 | (20,92) → (84,92) | wood | house 3, back |
| F8 | (84,92) → (84,39) | chain | house 3, east |

The comment at 1364 says earlier cross-driveway fences at z=±40 were removed so parked cars are not trapped. The sides toward the x=0 and z=0 streets are open.

**v3.5 visual-only fences** (`addFenceRun` 12580; 1.1 high; no collision and no route):
- wood (−58,38)→(−22,38), which crosses house 2's front walk at x=−53 **(inferred bug)**;
- chain (18,44)→(50,44);
- wood (96,−36)→(128,−36);
- chain (−118,−46)→(−118,−10).

### 5.3 Backyard objects (one theme per house, comment 1366)
- **House 0 (porch and barbecue):** barbecues at (−62,−81) and (−57,−81) (scale 0.67); steel drum (−38,−83); 4 picnic tables at random positions (x −76…−24, z −87…−71); bins at (−74,−76).
- **House 1 (pool):** coping 14×20 at (55,−84) with water 11.2×17.1 at y 0.25; 4 loungers at (41/44.5/48/51.5, −75), yaw π/2; ladder rails at x=49.
- **House 2 (guesthouse and trampoline):** guest cottage at (−58,83), 12×5.2×11, flat roof at 5.6, door and window at z=77.35 facing −Z, patio at z 76; trampoline at (−33,80) with r 5.1, bed at 1.45, net to 5.8, guard ring 5.9 with a 17-point route.
- **House 3 (doghouse and mower):** doghouse 4×3.2×4.2 at (39,80), entrance at z 77.83; bowl at (44,78); ride-on mower at (76,80).
- **Bins:** at (−74,−76), (71,−76), (−74,77) and (71,77).
- **Yard cats** (11558-11560; the wildlife extractor owns them): (−45,−76), (48,79) and (40,−79).
- **Living event** "barbecue" gathering centred at (−66,−84) (11403).

### 5.4 Walk-in home furnishing (v2.1, 11679-12072): present but dead code
`furnishOriginalHouse(h)` (11682) builds:
- floor;
- living room: couch at x=−0.265W, rug and coffee table;
- kitchen: 4 cabinets along the rear wall at backZ = sign·0.405D, plus fridge, sink and stove;
- dining: a 3.7×3 table with 4 chairs at (0.255W, −sign·0.12D);
- bedroom: bed at (−0.3W, −sign·0.29D), nightstand with lamp, wardrobe, 2 pictures;
- ceiling lamp;
- 6 `interiorObstacles` in world units.

`makeHomeDetails` (11795) adds a TV with emissive flicker, bookshelf and kitchenware, entrance shoes, pegs, plants, a pendulum clock or ceiling fan, a desk and a pet cushion.

**Bug:** `enterableHouses = houses.filter(h => h.indoorGroup && …)` (11788) runs *before* `furnishOriginalHouse` assigns `h.indoorGroup` (11690). The list is therefore always empty. As a result, none of these interiors is ever built, `handleHouseInteriorInteraction` never matches, and `activeHouseInterior` is never set. The same filter appears in v4.1 (11466) and in the v5.2 and v5.4 HTML builds.

---

## 6. Old Town outer ring (inside the 540×540 grid, outside the flat core)

### 6.1 `buildOuterHome(x, z, style, i)` (2071-2165), using the `outerHomes` table (2049-2070)
For index i (0–19), with houses[] id = 4 + i:
- width = 12 + (7i mod 5); depth = 10 + (i mod 4); eave height = 5.2 + 0.8·(i mod 3); peak = eave + 2.8 + 0.55·(i mod 3).
- wall = ["#c1b5a2","#b7c5c1","#d4b998","#a69f8b","#dfd6ba","#a6b5ac"][i%6]; roof = ["#5e5d5d","#71625c","#5d6b65","#755a50"][i%4]; door = ["#4b6d61","#6e5144","#3d5e78","#a3835b"][i%4].
- Orientation:
  - nearX = min(|x+180|, |x−178|) and nearZ = min(|z+174|, |z−171|).
  - If nearX < nearZ, then rotY = π/2; otherwise rotY = 0.
  - face = sign(x − roadX) when rotated, else sign(z − roadZ).
  - The door and porch are placed at local z = face·(depth/2 + …).
  - **Because face is the sign of (house − road), the door and porch point AWAY from the nearest grid road.** The concrete walkway is built from the house centre towards the road, on the opposite side.
- Facade: a solid box (no interior), gable roof, windows on the long faces except where (k+i)%3==0, dark glass when i%5==0, porch 0.63w × (2.5 + i%3) with 2 posts, side wing when i%4==0, chimney when i%3==0.
- The `style` argument is ignored; all variation comes from i.
- `houses[]` meta: `cfg.h` = **absolute** base+eave, peak absolute, `roofY()` = peak (flat), w/d already rotated.
- Roof route "neighborhood rooftop ridge" at peak+0.2 along the ridge (±0.48 of length).
- Walkway: 2.3 wide, at base + 0.055 (flat), from the house centre to 4 units short of the road centreline, so it overlaps the road's asphalt edge.
- Up to five random shrubs per lot (5 candidates; any within 0.6w × 0.65d of the centre is skipped).

| i | id | (x, z) | rotY | Door faces | Nearest road (dist) | World w×d | Eave / abs peak y | base y | Flair |
|---|---|---|---|---|---|---|---|---|---|
| 0 | 4 | (−135,−74) | π/2 | +X | x=−180 (45) | 10×12 | 5.2 / 8.84 | 0.84 | wing, chimney, dark windows |
| 1 | 5 | (−217,−72) | π/2 | −X | x=−180 (37) | 11×14 | 6.0 / 13.91 | 4.56 | |
| 2 | 6 | (−217,−130) | π/2 | −X | x=−180 (37) | 12×16 | 6.8 / 16.5 | 5.80 | |
| 3 | 7 | (−127,−209) | 0 | −Z | z=−174 (35) | 13×13 | 5.2 / 8.1 | 0.10 | chimney |
| 4 | 8 | (−63,−215) | 0 | −Z | z=−174 (41) | 15×10 | 6.0 / 9.45 | 0.10 | wing |
| 5 | 9 | (62,−208) | 0 | −Z | z=−174 (34) | 12×11 | 6.8 / 14.92 | 4.22 | dark windows |
| 6 | 10 | (139,−207) | 0 | −Z | z=−174 (33) | 14×12 | 5.2 / 14.99 | 6.99 | chimney |
| 7 | 11 | (216,−136) | 0 | +Z | z=−174 (38) | 16×13 | 6.0 / 11.98 | 2.63 | |
| 8 | 12 | (216,−57) | π/2 | +X | x=178 (38) | 10×13 | 6.8 / 10.8 | 0.10 | wing |
| 9 | 13 | (124,−72) | π/2 | −X | x=178 (54) | 11×15 | 5.2 / 8.58 | 0.58 | chimney |
| 10 | 14 | (127,69) | π/2 | −X | x=178 (51) | 12×12 | 6.0 / 10.04 | 0.69 | dark windows |
| 11 | 15 | (211,76) | π/2 | +X | x=178 (33) | 13×14 | 6.8 / 14.02 | 3.32 | |
| 12 | 16 | (216,142) | 0 | −Z | z=171 (29) | 16×10 | 5.2 / 10.41 | 2.41 | wing, chimney |
| 13 | 17 | (132,207) | 0 | +Z | z=171 (36) | 13×11 | 6.0 / 9.45 | 0.10 | |
| 14 | 18 | (48,216) | 0 | +Z | z=171 (45) | 15×12 | 6.8 / 11.77 | 1.07 | |
| 15 | 19 | (−62,213) | 0 | +Z | z=171 (42) | 12×13 | 5.2 / 13.5 | 5.50 | chimney, dark windows |
| 16 | 20 | (−139,204) | 0 | +Z | z=171 (33) | 14×10 | 6.0 / 15.44 | 6.09 | wing |
| 17 | 21 | (−216,140) | 0 | −Z | z=171 (31) | 16×11 | 6.8 / 11.56 | 0.86 | |
| 18 | 22 | (−209,62) | π/2 | −X | x=−180 (29) | 12×13 | 5.2 / 8.1 | 0.10 | chimney |
| 19 | 23 | (−128,72) | π/2 | +X | x=−180 (52) | 13×15 | 6.0 / 9.5 | 0.15 | |

### 6.2 Neighbourhood details (`addDetail`, 3054; 19 types × 2; no collision, no foraging hooks)
- Placement rule (3243-3248): for type i and variant v, the host is `houses[4 + ((3i + 7v) mod 20)]`. Offset dx = 11 (v=0) or −12 (v=1); dz = 12 (odd i) or −13 (even i). Variation = v + i%3; yaw = variation·0.71.
- Resulting positions:
  - fire hydrant (−124,−87), (204,−149)
  - park bench (−116,−197), (115,81)
  - trash can (150,−220), (120,194)
  - streetlight (135,−60), (−151,216)
  - stop sign (227,129), (−140,59)
  - garden gnome (−51,225), (−229,−118)
  - **bird feeder (−198,49), (50,−221)**
  - sprinkler head (−206,−60), (204,−45)
  - porch swing (−52,−228), (199,63)
  - window box (227,−124), (36,228)
  - driveway basketball hoop (138,56), (−228,127)
  - kids bike (143,219), (−147,−62)
  - lawn flamingo (−128,191), (−139,−222)
  - wind chime (−117,84), (127,−195)
  - garden hose reel (−206,−143), (112,−85)
  - wheelbarrow (73,−196), (204,154)
  - compost bin (227,−70), (−74,200)
  - rain barrel (222,88), (−221,74)
  - porch light (59,203), (−229,−85)
- Note: because of the offsets, several "porch" items (porch swing, window box, porch light) stand 11–13 units from the house in the open yard **(inferred)**.

### 6.3 Other outer-ring lots
- **Ice cream shops** (v3.5 env pass, 12652-12787):
  - standalone at (152,56): 8.5×6.8 base, pink shop 7.4×4.2×5.8, blue roof, awning and window toward +Z;
  - strip at (−154,−66): 12×7.5 slab, 10.5×4.2×5.6 shell, cyan fascia, toward +Z.
  - Both are placed at **y=0** even though terrain there is 2.26 and 1.42, so they are partly buried **(inferred)**. They have no collision.
- **Garden plots** (12619): (−36,52) 7×4; (116,−24) 6.5×4.5; (−104,−18) 7.5×3.8. All at y=0; visual only.
- **Stream** (12720): 2.1 wide, from (−175,92) through (−160,88), (−142,82) and (−126,76) to (−112,74), at y 0.02, with a 3.2×1.2 plank at (−142,82). It is not a water volume.
- **Shrub clusters** (12761-12775): 13 cylinder shrubs at fixed points near the core.
- **Treehouse** (9501-9559):
  - on "Treehouse Oak" at (−142,154) (H 31);
  - floor 8×7.8 at base+13.2, with full walls on −Z and ±X (glass windows on −Z only) and a partial +Z wall (two 2.2-wide panels at x ±2.65) leaving a central entrance;
  - deck 4.2×3.2 at local x +5.9;
  - ladder at z+4.15 (trunk route); floor and deck lookout routes;
  - the roof hides while the player is inside the box (|dx|<6.9, |dz|<5.9, y above floor − 0.7);
  - getGroundAt gives a floor at base + 13.46.
- **Random dressing** using the global RNG (positions not reproducible without replaying the RNG):
  - 52 berm tufts in ±248;
  - 650 instanced leaf-litter quads in ±111;
  - 120 shrub clumps in ±115;
  - 36 outer trees (trees extractor).

---

## 7. East commercial district (v0.6, x 241–687)
- **Chili's-style restaurant** (722-775):
  - group at (474, y 9.35, −82); 52×10.2×31 tan stucco, brick band, cap at y 11.4;
  - 6 glass panes (5.1×5.9 at local x −20, −12, −4, 4, 12, 20) and a 5×6.8 door on the +Z face; red awnings at x ±16;
  - roof route at +11.62 (x 449–499); collider `commercialBounds {w52, d31, roof base+11.5}`;
  - signs at z −65.3;
  - patio: 5 tables at (432+14i, −48 or −43), parasols on even i;
  - 8 bay lines at z −24; parked cars (462,−29) yaw 0 and (493,−29) yaw π.
- **Fuel market** (778-809): shop 33×8.2×23 at (522,110), entrance on −Z; parapet; roof route at +9.62 (x 506–538); the doors are explicitly not enterable (803).
- **Fuel canopy** (810-865):
  - 68×31 slab at (476,63), top at about ground(476,63) + 10.74;
  - 4 columns at (448|504, 50|76);
  - apron of 8.85×7.85 panels;
  - roof routes E–W and N–S plus a service ladder at (504, 76.85);
  - 6 dispensers on islands at x 452/474/496 × z 55/70.
- **Price tower** at (411,91), air/water at (505,91), waste container 2.3×2.8×2 at (535,93).
- **Corner shops** (902-909): 36×9.1×28 at (605,−94); 3 storefronts on +Z; roof route at +10.9. Terrain is sampled at x=609, which looks like a typo.
- **Static tall delivery van** (1588-1603): at (604,110); 3×3.45×5.9 with a 3.65 jump-limit hitbox (`tallVehicles`).
- **Parked cars** (586,−33) and (558,142). Moving cars on z=±5.6 belong to the traffic extractor.
- **Trolley:** rails at z 7.38/9.92, x 263–675; stops at x 310/465/616, z 20.2 (7692-7701; street-vehicles extractor).
- **Skyline:**
  - radio lattice tower (2976-3004) at (646,−213): triangular, 114 tall plus an 11 mast, base radius 6.3 tapering to 1.3, alternating steel and red sections; beacon at +126 with emissive 0.55. It is **static and does not blink**.
  - cellular monopole (3005-3027) at (629,218): 99 tall, 2 antenna rings.

---

## 8. South estate district (v1.1, z −265…−565)
`createEstate(index, cx)` (2754-2818) is called for (0, −130) and (1, 130). Style flag `style = index === 1`.

| Element | Estate 0 (cx −130) "Grand brick revival" | Estate 1 (cx 130) "Formal modern limestone villa" | Line |
|---|---|---|---|
| Mansion | (−130,−370), base y 7.37 | (130,−370), base y 2.27 | 2697 |
| Pool (deck 41×31, water 34×24) | (−142,−425) | (142,−425) | 2582 |
| Tennis court (42×26) | (−177,−504) | (177,−504) | 2627 |
| Guesthouse (20×6.7×15) | (−63,−463) | (63,−463) | 2678 |
| Pergola / summer kitchen | (−84,−424) | (84,−424) | 2806 |
| Gate pillars (1.5×6.2×1.5) | x −139 / −121 at z −330 | x 121 / 139 | 2777 |
| Parked car | (−112,−350) #617768 | (112,−350) #a6aeb0 | 2814 |
| Parcel hedges (h 1.7) | x −235 and −25 (z −332…−548), z −548 | x 25 and 235, z −548 | 2787 |

- **Mansion (2697-2753).**
  - Main block 46×14×29 with two wings 19×10.2×24 at x=±30 (z+2).
  - Windows on +Z in 2 storeys at x −35, −15, 0, 15, 35; rear glass doors on −Z.
  - Style 0: portico 19×15.8×4 at z 15, pyramid pediment, 4 columns at z 20.3, rooftop dormers.
  - Style 1: roof terrace, parapets, 2 columns at z 18, canopy.
  - Door 6.5×5.6 and 4 entry steps on +Z.
  - Collider `commercialBounds {w81, d35, roof base+14.62}`, solid; roof route at base+14.7, x ±22.
- **Guesthouse** collider `{w20, d15}`; roof route at base+7.48.
- **Tennis court:** net route at y+1.55; 3.8-high see-through fence panels with a 15-unit gap on the +Z side (no collision).
- **Pool:** loungers and umbrellas at z+19, ladder rails at x−18.5. No collision.
- **Drive and walks:** paver tiles at x=cx with centres z −331, −337, −343, −349 (9×5.9) then −350 … −374 step 6 (8.7×5.9), so the drive spans z −328.05 to −376.95; stepping-stone walks (16 tiles 2.1×2.15) from (cx,−402) to the guesthouse (guestX,−455) and the court (courtX,−490). Front shrub row at z −335: 12 slots at step 5.1, of which the 4 within 9 of cx are skipped for the gate, so 8 balls.
- **Estate gate oaks** (2903-2908; trees extractor): (−230,−329), (230,−329), (−219,−453), (219,−456).
- **Estate wires and poles:** see §11.

---

## 9. Northern expansion (v0.7): park, gardens and cemetery
- **Sycamore Park.**
  - `parkBoundary {xmin −245, xmax 145, zmin 296, zmax 429}` is declared but unused (3321).
  - Corner posts at (−214,305), (−210,417), (108,307), (111,417) and (−72,418).
  - Paths (`pavedSegment`, 3.2 wide, #bcae90) meet at hub (−56,355); see roads.json.
  - Pond: ellipse at (−147,371), about 55×38, shallow, with its surface above the ground.
  - Footbridge: x −122…−109 at z 371, with a bridge route.
  - 8 park trees (3395).
  - Gazebo at (52,411).
  - Playground (4253-4289): swings at x −17.2 / −8.8, z 318; slide at (27,317); sandbox at (49,326).
  - Softball diamond at (66,356) (living events).
  - Benches, trash cans and lamps as listed in lots_core.json.
  - Hedge patches (3572-3587): (125,303,len 14), (118,372,11), (−104,305,18), (290,306,22), (613,421,15).
- **Tabasco Garden** (3588-3668):
  - centre (115,341); 4 soil beds, 16 corn plants, 14 bushes, 9 tabasco plants;
  - sign at (115,325);
  - wheelbarrow lookout at (139,342);
  - concealment rule at 7035: hidden when y < 2.4, |dx| < 27 and |dz| < 15.
- **Park shed** (3670-3694): 12×6.1×10 at (203,328), door on −Z, porch beam at z 318 with the single ristra.
- **Pocket house** (3696-3701): 13×5×11 at (255,328), door on −Z. Despite the comment, it is only a shelter zone.
- **Shelter zones** (3703-3709, used by the predator watchdog 8186): log (−19,376) r4; bridge (−116,371) r4; hollow (95,359) r4; shed (203,328) r6; house (255,328) r7.
- **Dog houses** (3788-3798): (203,365), (236,397) and (90,308), entrances on −Z.
- **Sewer** (3726-3786; sewer extractor): an L-shape from A (123,334) to the corner (123,264) to B (200,264); floor y −3.4; tunnel 5.8 wide with 4.6 walls; E-grates at A and B; outfitter stand at (130,264).
- **Cedar Rest Cemetery** (3479-3570):
  - stone wall blocks every 5 (4.95×1.35×0.82, #7e8781) on z=304 (x 277–442 and 466–647), x=277 and x=647 (z 304–428), and z=428;
  - gate pillars at x 442 and 466; sign at (453,303);
  - 4-segment drive (5 points (451,307)→(447,333)→(464,356)→(484,394)→(513,411)), 5.5 wide;
  - **50 headstones**, 10 of each of 5 types, at x = 300 + 27·col + 6·(row%2) and z = 322 + 20·row + 1.7·(col%4), skipping |x−450| < 24, x > 644 and z > 418;
  - crypt/chapel 23×9.2×17 at (594,378), door on +Z, roof route;
  - 3 lamps.
  - Walls and crypt have no collision. `graveRegion` is declared but unused.
- **HUD district tags** (9062-9077; Quay at 14160): ducts / hospital interior first; then "HOSPITAL DISTRICT" if x < −270 and z > 245; then sewer; then "SYCAMORE PARK" if z > 303 and x < 150; "CEDAR REST · GRAVEYARD" if z > 303 and x > 270; "NORTHERN GARDENS" if z > 295; "COMMERCIAL DISTRICT" if x > 280; otherwise **"OLD TOWN"**. That last case includes the estates and the Westside, which have no tag of their own.

---

## 10. Westside extension (v1.5) and the hospital spur
- **Hospital** (landmark only; hospital extractor): `HOSP_X −356, HOSP_Z 353, HOSP_W 94, HOSP_D 96`; floor at base + 0.42; doors on −Z; driveway x −356.
- **Westside old houses** `oldHouse(index)` (9913-9997, built by the loop at 9998):
  - position: x = −365 + 5·((i%3)−1), z = −224 + 61i;
  - group rotY = π/2, so local +Z (garage bay, windows, side door) faces world **+X** toward the x=−289 street;
  - size: width (local x, world Z) = 21 + 2·(i%3); depth (local z, world X) = 20 + 3·(i%2); height = 6.1 + 0.45·(i%4);
  - flat roof slab (width+2) × 0.56 × (depth+1);
  - `canEnter = index < 4`.
  - Enterable houses have a 6-wide gap in the +X wall and 4 interior furniture boxes.
  - Each house also gets: a concrete drive of 12 tiles toward the street; bins at world x ± (width/2 + 3), z−8; for even index, a utility box on the −Z side and a garden shed at (x−31, z+6); and a "Westside i shade oak" at (x − 33 − 3·(i%3), z + 19 or −14).

| i | (x, z) | base y | World w×d | Height | Roof landing y | Door point | Enterable |
|---|---|---|---|---|---|---|---|
| 0 | (−370,−224) | 4.29 | 20×21 | 6.10 | 10.95 | (−357.2,−224) | yes |
| 1 | (−365,−163) | 7.24 | 23×23 | 6.55 | 14.35 | (−350.7,−163) | yes |
| 2 | (−360,−102) | 4.89 | 20×25 | 7.00 | 12.45 | (−347.2,−102) | yes |
| 3 | (−370,−41) | 3.51 | 23×21 | 7.45 | 11.52 | (−355.7,−41) | yes |
| 4 | (−365,20) | 5.59 | 20×23 | 6.10 | 12.25 | (−352.2,20) | no |
| 5 | (−360,81) | 5.75 | 23×25 | 6.55 | 12.86 | (−345.7,81) | no |
| 6 | (−370,142) | 5.51 | 20×21 | 7.00 | 13.07 | (−357.2,142) | no |

- **Westside street trees:** 4 at x −319/−328, z −185 + 95i (trees extractor).
- **Chained dogs** (wildlife extractor): (−403,−206), (−404,−75), (−418,63) and (−403,134), each with a stake at +(4,2) and an orbit radius of 3.4.
- **Turtles** (wildlife extractor): (−125,328), (−104,349), (−25,84), (164,−448) and (−406,180).
- **Police station** (10049-10091; police extractor):
  - (−510,−107), slab 46×31, walls 8.8, roof 9.25, entrance on +Z;
  - patrol pads at (−525,−81) and (−495,−81); roof route;
  - never enterable: collider at 11224, roof always visible.
- **Westside Fuel** (10094-10155):
  - (−397,229), base y 4.04; shop 27×5×17 with its front on −Z; canopy 34×18 at y 6.6 on 4 posts; 2 pumps at local (±7, −18).
  - **Closure rule** (`updateWestside` 10240):
    - `onSuccessfulBite` counts bites within 74 of (−397,229) and stamps `lastAttack`.
    - While the player is within 66 and less than 50 s have passed since `lastAttack`, `attackSeconds` accumulates.
    - Once `attackSeconds` ≥ 600 **and** bites ≥ 3, the station closes permanently and shows the closure sign.
- **Westside Storage** (10156-10169): 94×79 slab at (−513,213), 2×6 roll-up doors at local z ±26, sign on −Z.

---

## 11. Utility poles (positions only; wires and climb routes belong to the routes extractor)
- **Residential pole** `pole(x,z)` (1615):
  - de-duplicated by key "x.xx,z.xx";
  - **throws if `pavementDistance` < 0.95**;
  - 0.3–0.4 radius, 17.05 tall, crossarm at +16.35, 3 insulators at +16.56;
  - climb route "telephone pole climb …" (`surfaceRadius` 0.4).
- **Row and column generator** (1655-1668):
  - rows at z ∈ {−156, −16.5, 16.5, 153}, each with x ∈ {−244, −205, −154, −101, −50, −16.5, 16.5, 50, 101, 155, 205, 244};
  - columns at x ∈ {−154, −16.5, 16.5, 155}, each with z ∈ {−244, −206, −156, −104, −51, −16.5, 16.5, 51, 104, 153, 199, 244};
  - this gives 80 unique poles (16 shared).
- **Commercial poles:** for each side s = ±1, the chain starts at (244, ±16.5), which already exists, then continues at x ∈ {310, 369, 433, 499, 567, 631, 667}, z = ±21.2. That adds 14 poles (1683-1691).
- **Park poles:** (159,244), (159,301) and (142,331) (3423-3425).
- **Total residential-type poles: 97.**
- **Estate poles** (2911-2937): x ∈ {−250, −228, −125, 125, 228, 250} at z=−286. 16.4 tall, wood, crossarm at +15.85. Deliberately no pole at x=0.
- **Westside poles** (9893-9907): 7 at x=−303, z = −235 + 77i. 16.6 tall, radius 0.42–0.5.
- **Total `utilitySupports` = 110.** All are re-verified at boot by `verifyUtilityPlacement()` (16053), which throws on failure.
- **Wire layout (for reference):**
  - 44 row spans and 44 column spans;
  - 4 house service drops: the loop runs before the outer homes exist, so only core houses 0–3 get one, ending at (h.x, 8.65, frontZ − sign(z)·2);
  - 14 commercial spans; 2 park spans plus 1 tree-to-wire link;
  - 5 estate spans; 6 Westside spans.

---

## 12. Collision model for buildings (what actually blocks what in v5.4)

| Structure | Squirrel (`outdoorBlocked` 6324 / `collisionHouses` 6250) | Pedestrians (`humanHouseCollision` 6989) |
|---|---|---|
| Core houses 0–3 and outer homes | Solid AABB, footprint + 0.53, while y < eave − 0.35 | Solid (footprint + 0.3) |
| `commercialBounds`: restaurant, fuel market, corner shops, 2 mansions, 2 estate guesthouses, police | Solid while y < roof − 0.35 | Solid |
| Westside old houses | Solid unless this is the active old home or in transit | **Not blocked** (inferred) |
| Fences (8 core fences) | Blocked while y ≤ fence h + 0.25 and y < 3.1 | Not blocked |
| Trees | Radius 1.48 while y < 3.1 | n/a |
| Guest cottage, crypt, shed, pocket house, doghouses, gazebo, ice cream shops, Westside Fuel, storage, cemetery walls, pool and court fences, v3.5 fences | **No collision** | No collision |
| Hospital | Own system (`insideHospitalBuilding`, `adjustHospitalMovement`; hospital extractor) | Own system |

`recoverTrappedInHouse` (6179) handles a squirrel found inside a house footprint (shrunk by 0.5) below roof − 0.7: if it is near floor level (y < terrain + 1.25) it is pushed out through the nearest wall plus 1.1; otherwise it is lifted onto the roof surface.

---

## 13. House counts and interiors (brief §8)

**Residential buildings in this scope: 36.**
- `houses[]` = 24: ids 0–3 are the core `buildHouse` homes; ids 4–23 are the outer homes.
- `oldDistrictHomes` = 7 (Westside).
- 2 estate mansions and 2 estate guesthouses.
- 1 core guest cottage.

Small non-dwelling structures: treehouse, park shed, pocket house, 4 doghouses, crypt.

Commercial and civic buildings in scope: Chili's, fuel market (+ canopy), corner shops, 2 ice cream shops, Westside Fuel, Westside Storage, police (landmark) and hospital (landmark). Outside this scope: Bellwether Quay has 30 more buildings (`makeRiverTown` 14019: 10 + 12 + 8, all non-enterable), and the Galleria has 6 walk-in shops (mall extractor).

**Which houses can actually be entered in v5.4**

| Mechanism | Houses | Works in v5.4? | Implementation |
|---|---|---|---|
| Westside open-bay homes (`openOldHome` 10203, `handleOldHomeInteraction` 10219) | Westside old houses 0, 1, 2, 3 | **Yes**: the only player-enterable houses | See the state machine below |
| v2.1 walk-in homes (`houseInteriorEntry` 11958, `updateHouseInteriors` 12003) | Core houses 0–3 (Victorian, Bungalow, Brick House, Blue Cottage) | **No**: `enterableHouses` is empty (bug, §5.4) | Door-synchronised transit plus furnished interior |
| NPC home retreat (`beginHomeRetreat` 6886 and `advanceHomeRetreat` 6923) | Core houses 0–3, used by 12 residents (3 per house, 4494-4505) | **Yes** (NPC only) | Real door, NPC hidden 16–28 s |

The player can therefore enter **4** houses in v5.4. Four more are designed as walk-in homes but disabled by the bug. The other 28 dwellings are solid boxes. The brief requires 40 houses with full interiors, so everything must be built new. The 36 existing dwelling footprints are the natural first candidates (see §15).

**Westside old home state machine** (`updateWestside` 10240).
- **Outside → Transit(enter):** the player presses E within 7 (xz) of `door = (x + depth/2 + 2.8, z)`, with |y − base| < 4, while no transit is running. The transit is a 0.85 s smoothstep lerp to `(x + depth/2 − 4, base + 0.35, z)`. During it, `vel = 0`, `rail = null`, `grounded = true`, and the roof is hidden.
- **Transit(enter) → Inside:** `openOldHome` already sets `activeOldHome = home` when the transit starts (10211), and sets it again when the transit completes; the roof stays hidden.
- **Inside:** x is clamped to x ± (depth/2 − 0.7), z to z ± (width/2 − 0.7), and the floor to base + 0.35. That house's walls stop blocking (`outdoorBlocked` returns false). The roof route and roof landing are skipped for it.
- **Inside → Transit(exit):** the player presses E within 8 of the inside point. The transit is a 0.85 s lerp to `(x + depth/2 + 5, terrain + 0.35, z)`.
- **Transit(exit) → Outside:** when the transit completes, `activeOldHome = null` and the roof is shown again.

**Walk-in home state machine (designed but dead).**
- **Entry conditions:** the player is within 3.85 of `door.outside` with y < 3.6, and is not in the sewer, hospital, a duct, on a rail, or in an old home. A prompt appears within 5.
- **Entering:** `houseInteriorEntry(h, true)` sets `door.hold` ≥ 3 and starts a transit of 0.85 s:
  - passF 0–0.36: lerp to `outside`;
  - if passF ≥ 0.36 and the door is not passable (`open < 0.86`), elapsed is clamped to 0.35;
  - passF 0.36–0.62: lerp to `threshold`;
  - passF 0.62–1: lerp to `inside`.
  `activeHouseInterior` is set and the roof and ceiling are hidden.
- **While inside:** clamp to w/2 − 0.67 and d/2 − 0.65; ceiling at eave − 0.9; collide with `interiorObstacles` (+0.35). The interior group is visible when the house is active or the player is within 32.
- **Exit:** E within 4.4 of `door.inside` runs the reverse transit.

**Door animation** (`animateHouseDoors` 6980). Each frame, `hold` decays by dt. `open` damps toward 1 (rate 7.2) when `hold > 0` or a resident is running a `doorEscape`, and toward 0 otherwise. Pivot rotation = sign·open·1.35 rad. The door is passable at open ≥ 0.86.

**NPC retreat** (`beginHomeRetreat` 6886).
- **Triggered** on a spot→flee transition (7074) or for the first 3 witnesses of a crime scene (9267).
- **Requires** home 0–3, not injured, and distance to `door.outside` ≤ 38.
- **Detour:** if the NPC is behind the house or the straight line crosses the walls (footprint + 0.35), it goes around the side at x = h.x ± (w/2 + 1.6) and then to `outside.z − sign·1.25`.
- **Stages:**
  - approach: speed 4.9 per second, waypoint reached within 0.65;
  - threshold: waits until the door is passable, then moves at 2.65 per second, reached within 0.22;
  - inside: reached within 0.42, then hidden for `16 + rand·12` s.
- **Reappearance:** the normal spawn scheduler re-spawns the NPC on a sidewalk, not at the door.

---

## 14. Interactions with other subsystems
- **Routes** (routes extractor):
  - house ridges, outer-home ridges, commercial and estate roofs, crypt and police roofs;
  - fence tops (kind fence) and the trampoline ring;
  - downspout climbs (`addHouseGutters` 4292). For outer homes the gutter top double-counts base height, because `cfg.h` is absolute and terrain is added again **(inferred bug)**;
  - pole trunks and wires; treehouse ladder and floor; wheelbarrow lookout; footbridge.
- **Traffic and vehicles:** lane positions on the road centrelines (cars at x=±5.4 and z=±5.6); trolley rails; parked cars per lot; `tallVehicles`; vehicle hitboxes used by `getGroundAt` and `outdoorBlocked`.
- **NPCs:** sidewalk lanes (§4.5), resident homes (core 0–3), the door system, `humanHouseCollision`, park and mourner lanes, emergency actors kept outside houses (`keepEmergencyActorsOutside` 12074).
- **Chili hunt / foraging:** the Tabasco Garden concealment rule; `auditPepperAccessibility` (10395) shifts pepper candidates out of walls and cars using these colliders.
- **Predator watchdog:** `shelterZones` (8186).
- **Living events:** the barbecue at (−66,−84) and the softball diamond at (66,356).
- **Wildlife:** yard cats in the core backyards, dogs, chained dogs, turtles.
- **Orchard (v5.4):** `appleSiteClear` (15152) rejects sites within 8 of pavement, within 9 of houses or old homes, within 10 of `commercialBounds`, or within 8 of poles. It depends directly on this layout data.
- **Camera and HUD:** district tags; roofs hidden while inside.

---

## 15. Brief deltas (Roblox_Rebuild_Brief.txt)
- **§2 Toolchain.**
  - "WorldGen — builds the town from data, never from hand-placed parts" and "The town is a data file: a list of lots, each with a type, footprint, facing, and lot-specific parameters. Adding a barber shop later must be a data entry." lots_core.json and roads.json are the seed for that file. v5.4 hard-codes every lot.
  - "StreamingEnabled on. The map is several thousand studs end to end": the v5.4 extent works out to about 4,350 × 2,520 studs.
  - Scale: about 2.5 studs per unit.
- **§3 Districts:** all retained (old town, hospital, police, riverside, mall, sewer and duct interiors, and house interiors).
- **§3 Neighborhood expansion (new):**
  - Restaurants: "roughly double the current count". In this scope v5.4 has 4 food lots: Chili's, the corner diner/shops, and the 2 ice cream shops. The Quay's taverns and tearooms are counted by the Quay extractor.
  - New lot types: barber shop, music store, hardware store, laundromat, bookshop, pet store, gas station (2 exist), corner grocery, school with playground (a playground exists in the park), church (none; the crypt is the nearest thing), park with gazebo (exists), community garden (the Tabasco Garden exists), and a marina on the ocean side (none).
  - Each restaurant needs outdoor seating or a back-alley dumpster. Chili's has a patio (5 tables); the standalone ice cream shop has one small bench; the strip ice cream shop has 3 umbrellas but no seats; the only dumpster is the fuel market's waste container.
  - Residential: "at least eight distinct house models (bungalow, two-storey, Victorian, ranch, split-level, cottage, apartment block, large older house)", with every house given its own flair. v5.4 has 4 core models, 1 parametric outer model, 1 Westside model and 2 mansions. There are no apartment blocks, split-levels or ranches as such.
  - "Backyards with gardens, bird feeders, sheds, fences, dog houses." v5.4 has these only on the 4 core lots (and as scattered details), and none of them has gameplay.
  - "Each lot type defines what squirrels can forage there and how risky it is": not present in v5.4.
- **§3 Backdrop:**
  - Mountains on one side and an ocean with beach, pier and marina on the other: absent in v5.4, which has only a 1200-radius sky dome, fog 310–1050 and clouds.
  - The tower should be "a radio or cell tower … with blinking red lights, placed to silhouette against the sunset". The v5.4 radio beacon is static and stands at +X, while all light presets put the sun at −X (dusk direction (−105,55,−35)), so the tower will not silhouette against the sunset. It needs to be relocated or the sun path designed.
- **§3 Hollow trees:** 11 hollow trees, with the two premium ones "next to the best gardens and bird feeders". Lot placement must reserve space; the trees themselves belong to the trees extractor.
- **§8 House interiors:**
  - "40 houses have full interiors the rodent can burst into. Humans can run inside and hide … must actually run and be tested."
  - "These 40 houses are also the homes a human player can claim (35 player slots) … remodel points … persist for the life of that server instance."
  - v5.4 has 4 bare enterable homes plus 4 broken walk-ins. The rebuild needs at least 40 dwelling lots with interiors, interior navigation for AI humans (an extension of the door-retreat model), and per-house ownership and remodel state.
- **§8 Defenders:** "Three houses have a defender who bursts out" (two older housewives with rolling pins, one man with a broom). There is no v5.4 equivalent. The lot data needs a `defender` parameter.
- **§4/§5 Population:** "the hospital, police station, shops, and streets need to be staffed". Each shop lot needs staff and work spots (job credits, §13). v5.4 shops are facades.
- **Removed or changed:** the brief does not ask to keep the v5.4 quirks listed in §16. These should be fixed, not ported.

---

## 16. Porting notes (Roblox)
- **Terrain.**
  - Port `baseTerrainHeight` and `terrainHeight` verbatim as a shared Luau module (`ReplicatedStorage/Shared`).
  - Generate Roblox Terrain from it at build time (`WriteVoxels` in columns, or `FillBlock` per cell; height ≤ about 9.5 units ≈ 24 studs). Server and client AI can then query the analytic function instead of raycasting.
  - Keep the flat core (Chebyshev ≤ 104) exact.
  - Grade terrain under roads and lots so they sit flush, instead of relying on per-ribbon offsets.
- **Roads.**
  - One road module built from roads.json.
  - Simplest approach: paint Terrain materials (Asphalt, Concrete or Pavement, Cobblestone) on graded voxels.
  - Higher-fidelity approach: EditableMesh or MeshPart strips following the terrain, with lane paint as Decals or Textures. Avoid thousands of 0.13-wide paint parts: v5.4 has hundreds of paint boxes.
  - Fix the gaps in §4.3 so the network is continuous; Traffic needs a connected lane graph.
- **Ground-height authority.**
  - Players: Humanoid physics on the real geometry.
  - AI actors (35+ humans, 10–14 squirrels, wildlife): server-side kinematic movement that snaps to the analytic terrain or pavement height and uses the lot AABB lists (houses, `commercialBounds`, fences) in a spatial hash. This matches the HTML and is far cheaper than per-NPC physics.
- **Lots as data.** Each lot needs type, x, z, yaw, footprint, style or model id, `has_interior`, and per-lot parameters: palette, porch, wing, chimney, defender, forage table, risk, staff slots and claimable flag. Build models from a model library (8+ house archetypes, brief §3), seated at the terrain height of the lot centre (or graded pads). Doors should face the street; correct the outer-home inversion.
- **Collisions.** Every building listed as "no collision" in §12 should become solid in Roblox, unless designed as walk-through.
- **Interiors (40).**
  - Use `Model.ModelStreamingMode = Atomic` for each house shell with its interior.
  - Keep interior props in a sub-model that clients can hide by distance, replacing v5.4's "visible within 32 units".
  - Doors are server-owned (`HingeConstraint` or tweened CFrame), using the hold/open/passable semantics of §13 so AI and players agree on passability.
  - Don't use the v5.4 cutscene-style transits. Physically walking through the doorway works in Roblox.
- **StreamingEnabled.**
  - Set `StreamingTargetRadius` large enough for the drone (brief §10) or use `Persistent` for skyline landmarks (towers, mountains).
  - Poles, wires and routes must stream with their district. The server must keep the route registry and collision lists independent of streaming, because server AI runs everywhere.
- **Performance budget.** v5.4 builds thousands of tiny boxes: flowers, leaves, hedge balls, fence boards (≈470 wooden boards in the core alone) and lane dashes. In Roblox, use MeshParts, instancing-friendly repeated meshes, textures and Terrain decoration. Bake random dressing into the data file instead of re-running the mulberry32 RNG (seed 20261008, order-dependent; 80-92).
- **Coordinate transfer:** stud = unit × 2.5 for x, y and z; yaw unchanged (§1). The pole clearance rule becomes `pavementDistance ≥ 0.95 units` (≈ 2.4 studs) and should be kept as a build-time assertion.
- **Determinism:** all lot positions in lots_core.json are deterministic. Hedges, flowers, picnic tables, foam, tufts, litter and outer-tree jitter come from the global RNG and are not listed. Re-generate them with a new seeded RNG in Luau.

---

## 17. Open questions (designer decisions)
1. **Compass.** Should "north" be +Z (district names) or −Z (HUD compass)? This affects signage ("PARK / CEMETERY ↑"), the drone UI and the brief's backdrop placement (mountains on one side, ocean on the other).
2. **Outer-home doors.** Port faithfully (pointing away from the road) or face the road? Recommended: face the road.
3. Which **40 houses** get interiors? Options:
   - (a) all 36 existing dwellings plus 4 new ones from the expansion;
   - (b) replace the 20 small outer homes with larger archetypes on the same lots (the outer lots are only 10–16 units ≈ 25–40 studs wide);
   - (c) add a new residential block.
4. Which **3 houses** get defenders? Which lots are premium gardens or bird-feeder sites next to the 2 premium hollow trees?
5. **Unconnected roads.** Connect x=−180 and x=0 to z=283, x=347 to z=283, x=±180 to the estate avenue, and the Westside street to the hospital road? This affects Traffic.
6. **Ocean and mountains.** Which sides? The current world is open on all sides. The river runs N–S at x≈850 on the +X side, and the mall is at x≈1102.
7. **Gas closure rule** (600 s of sustained attack and 3 bites): keep it as a lot-level "panic closure" mechanic for all shops?
8. **Estates.** Are mansions enterable or claimable? There are only 2, both solid today.
9. Should the flat roofs of outer homes become real gabled roof collision, or stay simplified flat landings?
10. Keep the HUD tagging scheme? Estates and the Westside currently report "OLD TOWN".
11. The **pocket house** at (255,328) and the **treehouse** are described as enterable pockets. Should they become real micro-interiors (hollow-tree-like hiding spots for squirrels)?

---

## 18. Verified v5.4 quirks (do not port blindly)
1. `enterableHouses` is always empty (11788): the walk-in interiors are dead code.
2. Outer-home doors and porches face away from the nearest road (2084); the `style` argument is unused.
3. Outer-home roof landing is flat at peak height despite the gabled mesh (2124-2133).
4. Core curbs run unbroken through the central intersection (580-583).
5. v3.5 env-pass objects are at y=0 regardless of terrain (the ice cream shops are half-buried), and have no collision (12556-12795).
6. A v3.5 wood fence at z=38 crosses house 2's front walk (12777).
7. Many structures have no collision (§12).
8. Unused constants: `PEDESTRIAN_EDGE`, `parkBoundary`, `graveRegion`, `westAsphalt`, `ESTATE_SOUTH` (never referenced).
9. The corner shops' base height is sampled at x=609 instead of 605 (903).
10. Traffic signals never change; the radio beacon never blinks.
11. Front walks and driveways of the core houses stop short of the sidewalks; outer walkways overrun into the asphalt.
12. Ground meshes leave uncovered areas inside the player clamp (§2).

---

## Added by verifier

Items in scope that the extractor's text did not cover, or covered too loosely for a rebuild. Line numbers refer to `reference/v5_4_game.js`.

1. **Builder function map** (useful when porting each lot type as its own module):
   - Estates: `estateHedgeLine` 2569, `estatePool` 2582, `estateCourt` 2627, `estateGuest` 2678, `estateMansion` 2697, `createEstate` 2754 (called at 2819-2820), `estateGateOak` 2824.
   - Skyline: `radioTower` 2976 (called at 3004), `cellTower` 3005 (called at 3027).
   - Ground: `addNorthernGround(x1,x2,z1,z2)` 3272 (70×28-segment terrain-following plane at terrain − 0.088; reused for the hospital spur 3808 and the Westside 9880-9881); `earthTile` 3287 (garden soil beds).
   - Core helpers: `addWindow` 955, `localRoof` 975, `trafficSignal` 700, `makeCar` 1502, `carHitsFence` 1543, `poleKey` 1610 ("x.xx,z.xx"), `droopBetween` 1637 (13 points, sin sag), `stringUtilityRoute` 1646 (sag = min(0.84, 0.26 + 0.004·span)).
   - Interiors: `houseDoorPassable` 6977 (open ≥ 0.86), `setHouseRoof` 11954, `updateInteriorMotion` 11944 (fan, pendulum and TV flicker; dead with the rest of the walk-in code).
   - `doorway(parent, z, w)` 1027 is defined but never called (dead code).
2. **`pavedSegment` orientation bug** (3291-3306, **inferred from the transform maths**). Each segment is one `box(width, 0.12, distance)` centred on the midpoint with `rotation.y = −atan2(dx, dz)`. In three.js `rotation.y = θ` points local +Z along (sin θ, cos θ), so the plank runs along (−dx, dz): it joins (a.x, b.z) to (b.x, a.z), the *other* diagonal of the segment's bounding box. Every non-axis-aligned park path (8 segments) and cemetery-drive segment (4) is therefore drawn mirrored, and consecutive planks do not meet (for example the hub end of park path 0 segment 1 lands at (−56,336) instead of (−56,355)). Elsewhere the code uses `+atan2(dx, dz)` (NPC facing, turtles). The planks are also flat (one terrain sample at the centre + 0.12) and are not registered pavement, so walk height on them is plain terrain. roads.json records the intended endpoints; the Roblox build should use those.
3. **v3.5 stream has the same mirroring** (`addStream` 12720-12746): segment boxes (length along local X) use `rotation.y = atan2(dz, dx)`, which maps local +X to (dx, −dz), so each of the 4 stream segments slopes the wrong way and the stream renders as a broken sawtooth. Port the intended polyline from §6.3.
4. **Trampoline bounce** (`attemptTrampolineBounce` 10373-10392, called from player movement at 6752). It triggers when the player is within 4.67 of (−33,80), was above 1.72 on the previous frame, is now at or below 1.92, and is falling. It sets y = 1.9 and vel.y = 14.2 + 0.9·count, where count goes up by one per consecutive bounce (max 4) and resets once the player is more than 9 away (`updateWestside` 10242). It also adds a 1.6 push along the camera's forward direction. The bed mesh (`trampolineGroup.children[1]`) dips by 0.35·sin(flex·π), and flex decays at 2.8 per second. This is the only backyard object with gameplay.
5. **Outer-home ridge route length quirk** (2134-2146). For the 9 rotated outer homes (i = 0, 1, 2, 8, 9, 10, 11, 18, 19) the ridge route runs z ± 0.48·*depth*. The visible ridge, though, is the local-X ridge of `localRoof`, which after the π/2 turn runs along world Z for *width* + 1.3. So the route is shorter than the drawn ridge whenever width > depth. Unrotated homes use ±0.48·width along X, which is correct.
6. **Outer-home walkway placement** (2147-2170). Rotated homes put the walkway at z + 5 (offset from the door axis). Unrotated homes put it at x + 0.25·width. Neither is aligned with the door, which is on the far side anyway (§6.1).
7. **Westside old-house bins** (9954-9957) are placed at world (x ± (width/2 + 3), z − 8), but the walls along world X are at x ± depth/2 (the group is rotated π/2). The bin-to-wall gap is therefore 3 + (width − depth)/2, which is 3.5, 3, 5.5, 2, 4.5, 4 and 3.5 for houses 0–6. Probably the code meant depth **(inferred)**; port the gap as a lot parameter.
8. **`pavementZones` coverage.** Only the 48 ribbons in §4.1 are registered. Park paths, the cemetery drive, estate pavers and walks, core front walks and driveways, outer walkways, Westside drives, trolley stop pads and the Quay approach patches are not. So `pavementDistance` (used for the pole, orchard and ground-detail rules) treats them as grass, and NPC sidewalk logic never uses them.
9. **`obstacles[]`** (953, pushed only by `buildHouse` 1235) holds just the 4 core houses. Its only consumer is the tree ground-detail scatter at 12993 (skip within footprint + 1). Outer homes, old houses and commercial lots are not in it.

---

## Verification log

Format: claim — result. Checked against `reference/v5_4_game.js` (and v4.1 where noted).

1. `WORLD_HALF` 270, `PEDESTRIAN_EDGE` 12.1 unused (399-400) — OK
2. `NORTH_LIMIT` 440 (3271) — OK
3. `ESTATE_SOUTH` "unused except by the ground plane" — FIXED (-> never referenced; estate plane edge is from literals)
4. Player clamp x [−586, 1146], z [−560, 436] (6765-6766) — OK
5. Main ground 540² 128×128 at −0.09; east extension x 241–687, z ±244, 100×94, −0.083 — OK
6. Estate ground x ±270, z −565…−265, 90×56, −0.084; northern grounds 70×28 −0.088; Westside and hospital grounds — OK
7. `baseTerrainHeight` formula, flat core ≤ 104, blend to 190 (407-416) — OK
8. Hills range −2.55…9.55; maxima grid 8.58 (−270,−104), east 9.43, estates 9.46, Westside 9.27 — OK
9. Hospital spur max "≤ 4.19" — FIXED (-> ≤ 4.25 at (−355,440))
10. Steepest gradient ≈ 0.144 — OK (numerically re-sampled)
11. `RIVER` constants, `riverCenter`, `riverDeckAt` ramps, bank lerp 687→735 (419-464) — OK
12. `outdoorSurfaceAt` terrain − 0.075, curb 0.245 rule (513-528) — OK
13. `getGroundAt` order, guest roof y 6, trampoline 1.65, treehouse + 13.46 (6227-6247) — OK
14. `roofSurfaceAt` margins and offsets (+0.29, +0.56, +0.17, hospital +13.34) (6111-6146) — OK
15. `registerPavement` only asphalt/concrete; 48 registered zones — OK (counted all 50 ribbon calls; 2 rails excluded)
16. roadRibbon 104 segments / districtRibbon 95 segments, UV x/16, z/112 — OK
17. Road table §4.2, all 14 rows (coords, widths, ranges, sidewalks, lines) — OK
18. Core curbs 258 long, unbroken (580-583) — OK
19. Core sidewalk joints "−117 to 117" — FIXED (-> −117…115)
20. Crossing dashes ±(11…15.8) at ±8.6; storm grates (±16, ±9.7) — OK
21. Commercial paint: amber dashes, white dashes, zebra stripes (643-657) — OK
22. Restaurant bay lines x 438…508 at z −24 (770) — OK
23. Grass-lot bay lines "x 410…640" — FIXED (-> 410…635; also lots_core `east_parking_lots` x 527.5 -> 522.5)
24. Estate paint and north paint lists (2561-2567, 3314-3318) — OK
25. Traffic signal positions, pole, mast arm, head; no phase logic (700-720) — OK
26. `flatSign` road-guide regex and clamps; all 10 in-scope sign positions (682-698, 750-909, 3477-3512, 4047) — OK
27. Street fixtures (3250-3267) and park benches/cans (3443-3455) positions — OK
28. `sidewalkLanes` line "4816" — FIXED (-> 4817; values OK)
29. Commercial/park/mourner lane ranges (4840-4869) — OK
30. Core `buildHouse` cfg sizes and colours, scale 0.82, world footprints — OK
31. Door waypoint table (12 values) — OK (recomputed)
32. Shell portal 2.6×3.5, wall 0.24, door pivot (−1.12), door colours by id parity — OK
33. Windows (±0.28w, 30%/25% dark), chimney styles 0/2/3, back deck 12×4.5 / 20×9 porch — OK
34. Front walk to z ±16 (2.25 gap), driveway 5.3×26 at x ± 17, mailbox, plaque — OK
35. Hedges 10 / flowers 32 per quadrant, exclusion bands (1253-1275) — OK
36. Core parked cars (x ± 17, z + toward·8), yaw π for 0/2 (1554-1563) — OK
37. Fences F1–F8 coordinates and types (1356-1363); comment at 1364 — OK
38. Fence squirrel radius "0.32" — FIXED (-> 0.37 in `outdoorBlocked`, 0.4 in `collisionHouses`)
39. Board spacing 0.49, posts 3.3 / 3.1, routes h + 0.1 / h + 0.14 — OK
40. v3.5 visual fences and house-2 walk crossing (12776-12779) — OK
41. Backyard objects: barbecues, drum, pool, loungers, guest cottage, trampoline, doghouse, mower, bins — OK
42. Yard cats (11558-11560); barbecue event (−66,−84) 11403; softball (66,356) 11404 — OK
43. `enterableHouses` filter runs before `indoorGroup` is assigned (11788 vs 11690; also v4.1 11466) — OK
44. `furnishOriginalHouse` layout (couch −0.265W, 4 cabinets at 0.405D, dining, bed, 6 obstacles) — OK
45. `outerHomes` table: all 20 rows (rotY, door side, nearest road, w×d, eave, abs peak, base y, flair) — OK (recomputed)
46. Outer-home doors face away from the road (2079-2082) — OK
47. Outer walkway geometry (to 4 short of the road centreline, base + 0.055) — OK
48. "Five random shrubs per lot" — FIXED (-> up to five; candidates near the house are skipped)
49. `addDetail` placement rule and all 38 detail positions (3243-3248) — OK (recomputed)
50. Ice cream shop footprints and y = 0 burial (terrain 2.26 / 1.42) — OK
51. Garden plots, stream points, plank, 13 shrubs (12752-12784) — OK
52. Treehouse "walls and windows on −Z and ±X, open +Z" — FIXED (-> windows only on −Z; partial +Z wall with central opening)
53. Treehouse floor 8×7.8 at +13.2, deck x + 5.9, ladder z + 4.15, roof-hide rule (10271-10278) — OK
54. Random dressing counts 52 / 650 / 120 / 36 (2364-2401) — OK
55. Restaurant base 9.35, 52×10.2×31, collider, roof route, patio — OK
56. Restaurant "5 glass panes" — FIXED (-> 6; also in lots_core notes)
57. Fuel market 33×8.2×23, −Z entrance, roof route, not-enterable comment (803) — OK
58. Fuel canopy slab top +10.74, columns, apron, ladder (504, 76.85), 6 dispensers — OK
59. Price tower, air/water, waste container; corner shops and x=609 sample (903) — OK
60. Delivery van and `tallVehicles` (1588-1603) — OK
61. Radio tower 114 + 11, beacon static; cell monopole 99 (2976-3027) — OK
62. `createEstate` offsets: mansion, pool, court, guesthouse, pergola, gates, car, hedges (2754-2818) — OK
63. Mansion base y 7.37 / 2.27 and geometry, collider w81 d35 — OK
64. Tennis fence 15-unit gap on +Z; net route y + 1.55 — OK
65. Estate drive "z −331 to −379" — FIXED (-> centres −331…−374, span −328.05…−376.95; roads.json rd_040/rd_043 start −381.95 -> −376.95, width -> 9)
66. Estate front shrub row "12 balls" — FIXED (-> 8 balls; 4 of 12 slots skipped at the gate; also lots_core parcel notes)
67. Estate gate oaks (2900-2906) — OK
68. Park paths, pond ellipse ≈ 55×38, footbridge x −122…−109, gazebo, playground — OK
69. Hedge patches; Tabasco Garden counts and concealment rule (7034) — OK
70. Park shed, pocket house, shelter zones, 3 north doghouses — OK
71. Sewer L geometry (3727-3786) — OK
72. Cemetery "5-segment drive" — FIXED (-> 4 segments, 5 points)
73. 50 headstones, 10 per type; crypt 23×9.2×17 with +Z door — OK (recomputed)
74. HUD district tag order (9062-9078) — OK
75. Hospital constants and floor + 0.42 (3802-3807) — OK
76. `oldHouse` formula and all 7 table rows (base y, w×d, height, roof landing, door point) — OK (recomputed)
77. Westside trees, chained dogs (radius 3.4, stake +(4,2)), turtles — OK
78. Police station dims, pads, collider at 11224 — OK
79. Westside Fuel dims and closure rule (600 s, 3 bites, 66/74/50) — OK
80. Westside Storage 94×79, 2×6 doors — OK
81. Residential pole build and clearance throw (1615-1636) — OK
82. Pole counts 80 + 14 + 3 = 97, estate 6, Westside 7, total `utilitySupports` 110 — OK
83. Wire span counts (44 + 44 + 4 + 14 + 2 + 1 + 5 + 6) — OK
84. Collision table §12 (margins 0.53 / 0.3 / 0.25 / r, old homes skipped by pedestrians) — OK
85. `recoverTrappedInHouse` "pushes out through the nearest wall" — FIXED (-> only near floor level; otherwise lifts onto the roof)
86. Dwelling count 36 and 28 solid; Quay 30 buildings (14019-14041) — OK
87. Old-home transit "activeOldHome set on completion" — FIXED (-> set at transit start, 10211)
88. Old-home state machine distances (7, 8, |dy| < 4, 0.85 s, depth/2 − 4, depth/2 + 5) — OK
89. Walk-in state machine (3.85 / y < 3.6, passF 0.36 / 0.62, exit 4.4, visible within 32) — OK
90. Door animation damp 7.2, swing 1.35 rad, passable at 0.86 — OK
91. NPC retreat (≤ 38, 4.9 and 2.65 per second, 0.65 / 0.22 / 0.42, 16 + rand·12 s, triggers 7074 / 9267) — OK
92. 12 residents, 3 per house (4494-4505) — OK
93. Gutter top double-counts base for outer homes (4299) — OK
94. `appleSiteClear` thresholds (15152-15170) — OK
95. RNG mulberry32 seed 20261008 (80-92); fog 310–1050; sky r1200; sun presets all at −X — OK
96. ≈ 470 wooden fence boards (computed 472) — OK
97. Restaurant seating claim — FIXED (-> standalone ice cream shop has a bench; strip has umbrellas but no seats)
98. Grid-to-estate gap "24 units" — FIXED (-> ≈ 21 to the sidewalk edge, 25 to the asphalt)
99. Compass comment "+Z south, −Z north" and +X east (9854-9856) — OK
100. No in-scope builder lost between v4.1 and v5.4 (function and `outerHomes` diff) — OK
101. lots_core.json: 20 outer homes and 7 old houses (x, z, facing, footprint, has_interior) — OK (programmatic check)
102. lots_core.json: estate parcels, pools, courts, guesthouses, pergolas, mansions — OK
103. lots_core.json: src_line spot checks (2819/2820, 3465, 3548, 3671, 3697, 9502, 12753, 12782, 12786/12787) — OK
104. roads.json: outer walkways 0, 1, 3, 7, 8, 9, 13, 18; Westside drive 0; fuel apron; footbridge; police and fuel slabs; trolley stops; core walks and driveways — OK
