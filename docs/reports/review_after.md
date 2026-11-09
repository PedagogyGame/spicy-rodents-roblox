# Town visual review: after the fix pass (2026-11-09)

Owner feedback: "it looks bad" (trees with bare noodle branches and tiny lollipop leaves, excess
telephone and lamp poles, leaning lamps). This pass fixes the town's look without moving any climbing
route. Renders: `tools/review/run.sh --debug` (every view, full bake) writes
`build/review/<view>.png` and **`build/review/contact_sheet.png`**. Four views were added for this
pass: `n_quay_street`, `o_lamp_close`, `p_outer_homes` and `q_willow`. The final pass rendered all 24
town, lineup and debug views from a fresh bake (BakeHash `66ad35c5b201e463`) in 21 minutes (2 CPUs shared
with another task's Blender job); the sheet is `build/review/contact_sheet.png`. Other tasks added their
own `bd_*` (backdrop) and `bw_*` (bowling) views to `views.json` while this pass ran; they are not part
of this review.

## Checks (all on the final code)

| Check | Result |
|---|---|
| `lune run tools/bake/check.luau` (WorldBuild exit checks in Lune) | ok: 1,332 routes / 81,613 samples, 0 off geometry (4 patched still off, as before), 83 doors reachable, 110 solids, 0 overlaps |
| `tools/ci.sh` steps | Selene clean; Lune tests 386 passed, 0 failed (54 spec files); compile check up to date; 4 Rojo builds; 4 place tests, 0 failures; sourcemap. StyLua passes on every file this pass touched (`src/worldgen`, `tools/bake`, `tools/review/export.luau`, the two specs). **Caveat:** `stylua --check` over the whole tree currently fails on files other tasks created during this session and were still editing (`src/shared/Minigames/MinigameRules/Bowling.luau`, `src/shared/World/Backdrop.luau`, `tests/unit/attractions_alley.spec.luau`, `tools/cloud/tasks/heroes_rig_probe.luau`); they were left untouched. |
| CI place version **39** (`rojo build ci.project.json` + `cloud.mjs save_place --place ci`) | |
| `tools/cloud/tasks/world_build.luau` (WorldBuild + BakeParity) | **PASS**: 0 failures; routes 1,332 / 81,613 samples, 0 off geometry; doors 83, 0 unreachable; 0 overlaps; engine plan hash = Lune BakeHash (`66ad35c5b201e463`); placed and engine-baked InstanceHash = Lune (`1bea8a0bbec17ff5`); geometry max delta 1.4e-5 st; engine bake 2.0 s |
| `tools/cloud/tasks/playtest_smoke.luau` | **PASS** (Playtest ok, 0 failures) |
| `tools/cloud/tasks/play_smoke.luau` | **PASS** (PlayBuild ok, 0 failures) |

Nothing was published; the main place was not touched.

## Counts

| | Before | After |
|---|---|---|
| Town parts (`Town.PartCount`) | 15,649 | **27,170** (budget ~30,000) |
| of which trees | 4,221 (827 leaf balls) | 16,070: 9,440 leaf parts (balls, willow strands, apples), 5,118 bark, 1,512 twigs and root flares |
| Leaf clusters per tree | 2-9 | 35-172 (mean 83) |
| Street-lamp posts / lamp models | 307 / 90 | **130 / 17** (one model per street) |
| Lamp heads (Neon, Skyline) | 307 | 130 |
| Lights | no baked lights; the client pools 40 PointLights on the nearest heads at night (`Client/Render/TownView`, unchanged) | same: 0 baked lights, 40-light client pool |
| Telephone poles drawn as poles | 97 (13 more drawn as grey pipes) | 110 (the 7 Westside and 6 estate-avenue telephone poles now look like poles) |
| Beam wires with length | 0 of 373 | **373 of 373** |
| Attachments at their part's origin | 796 of 796 | 199 of 796 (only those whose offset really is zero: each wire's first point, door prompts on the door centre) |
| EditorGround cells at the world origin | 6,930 | 0 |
| Coplanar overlapping top faces (different look) | 19 | **0** |

## Findings

1. **No telephone wires (Attachments at the origin): FIXED.** `Factory.extra` set `Attachment.Position`,
   which Lune drops; it now sets `CFrame` (wires, door prompts, nav nodes, shelf slots). All 373 Beams
   have length; wires hang with the harvested sag (13-point droop per span). Every Lune-run `.Position`
   write was checked (only Factory and editor_ground had one; `Vehicles/Placeholder` is engine-only).
2. **EditorGround cells stacked at the origin: FIXED** (`tools/bake/editor_ground.luau` sets CFrame).
3. **Quay: FIXED.** The district ground is cut into 37.5-stud strips on both banks that stop at the
   embankment coping (riverCenter(z) +- 130 st, following the meander), so it no longer covers the
   river. The river lot draws stone embankment walls (bed to bank) with a light coping along both
   banks; the water is the terrain's. The stone bridge is a real five-arch bridge (worldgen_districts_art
   §3.3): arches at x 802..898 u with 11 voussoirs each (every third dark), spandrels, six piers with
   cutwaters, the cobbled deck at 15.8 u (39.5 st) over 790..910 u, stone approach ramps 744..790 and
   910..956 u, and tower bases under both bridge towers, which now stand on the deck. The bridge road
   (rd_033) follows the deck and ramps (`Height.riverDeckAt`) instead of the river bed; the parapets are
   stone walls on the deck, the chains have hangers to the deck, the towers have plinths, string courses,
   slit windows and red banners, the docks sit at bank level on pilings, and the bunting lines have
   masts and pennants.
4. **Z-fighting: FIXED (0 left).** Plates stack by kind (district < grass < pads < plazas < paths); the
   river plate is gone (terrain water); dashes and curbs ride on their segment's own surface. The export's
   check now compares the real face planes at the overlap (it compared AABB tops, which flagged dashes on
   very slightly tilted road segments).
5. **Roofs without supports: FIXED.** The fuel canopy stands on 4 concrete columns on the pump-island
   lines; the hospital porte-cochere on 2 columns at its drive edge (v5.4 local x +-9 u).
6. **Telephone poles: FIXED.** Every pole runs from 1.5 studs inside the ground (or paving) to the route
   top; an 11-stud crossarm 2.2 studs below the top with two braces and four glass insulators, a pin
   insulator on top where the harvested wire meets the pole, a transformer can on every fourth pole.
   The wire routes are untouched (they end on the pole tops).
7. **Quay willows: FIXED.** The six trunkless 45-stud lot balls are now invisible markers: each willow
   is drawn on its harvested QUAY WILLOW trunk (bark trunk and boughs, a leafy dome) with up to 120
   hanging curtain strands with rounded tips that fall almost to the ground at the rim.
8. **Trees: FIXED** (`Builders/Trees.luau`). Routes do not move; `WorldBuild` route-on-geometry still
   passes, and leaves no longer count as route geometry (only bark, poles, pipes, rails, roofs, wires).
   (a) Bark: round cylinders in four bark browns; the trunk tapers exactly like the squirrel's trunk
   offset (Motion visualPose: r(1 - 0.48t), giants r/0.95 - 1.05 u t); boughs taper from about the
   squirrel's bough lift (0.5 u, apples 0.3 u, lookouts 0.61 u) to 60 % at the tip, so the squirrel's
   feet are on the bark (the old boughs were drawn at the 1.35 u default surfaceRadius: 6.75-stud-thick
   "noodles", thicker than their trunks); short twigs splay into the leaves; a root flare meets the
   ground. (b) Crowns: 35-172 overlapping leaf balls (5-14 st) per tree, 3 v5.4 greens per tree with
   height shading and jitter, along the outer two thirds of every bough, round the bough tips and over a
   crown dome; LeafyGrass, no collision, CanQuery false, CastShadow true. Living bridges inside the crown
   are buried in leaves; beyond it they carry irregular leafy tufts like a vine-hung limb (a solid tube
   of leaves looked like a caterpillar). Clear tunnels: no cluster within 1.6 st of the squirrel's body
   on a bough (centreline + 2 st) or within 2.2 st of the trunk's climbing surface. Apple trees carry a
   few apples. Budget: 27,170 parts in total.
   - **Tree_550** (trunk on the kerb of rd_001): NOT MOVED. Its trunk route is 0.5 st from the road edge
     and overlaps the sidewalk by ~0.9 st; the visual trunk must stay on the route, so it stays. The root
     flare is suppressed wherever a trunk touches paving, so nothing extra pokes onto the kerb.
   - **Tree_1262** (APPLE 3, "fat stump"): FIXED. It was the 1.35 u default surfaceRadius on its boughs;
     it is now a small apple tree with tapered 0.7-stud boughs, 37 leaf clusters and apples.
   - **Five standalone limbs** (Limb_669/670 estate-oak living bridges, 112 st; Limb_733-735 park watch
     perches): FIXED. Each starts on a trunk, so it is drawn as part of that tree (Tree_630/637/672/685/
     712) with tapered bark and foliage (tufts past the crown), no longer a bare limb hanging in the air.
9. **Lamps: FIXED** (`LampPlan.luau`, data in `lighting.json`). One row per street (the 17 asphalt
   streets and the bridge; never sidewalks, footpaths, drives or rails), on the grass verge between the
   kerb and the sidewalk, alternating sides block by block, ~105 st apart, nothing within 12 st of a
   crossing street's kerb, none within 25 st of another lamp, a utility pole or a tree trunk (measured:
   nearest lamp-lamp 52.1 st, lamp-pole 25.2 st), never on a solid lot, drive or walk; bridge lamps on the
   deck inside the parapet. Posts are vertical dark-metal cylinders 15 st tall on a base with a finial;
   the curved three-piece arm, housing and lit head are Skyline parts, so the client still lights the
   nearest 40 (unchanged TownView). **Why lamps looked leaning:** every baked post was already a vertical
   cylinder (now asserted by a unit test: roll pi/2, pitch 0). What read as leaning lamps were (a) the five
   v5.4 `streetlight` details baked as 13 x 3 x 3-stud boxes lying by the road (they are now invisible
   markers; street lamps are LampPlan's job) and (b) rows of three posts (street plus both sidewalks)
   whose posts and arms crossed in perspective.
10. **Outliers: FIXED** except where noted.
    - Trampoline rail Fence_19: the ring now stands on padded posts with a light net down to the
      trampoline, which is a round frame with a mat on legs.
    - Downspouts: the routes are untouched; every pipe is carried down to what it stands on (terrain,
      paving, deck or a lower roof) with a shoe. Ladders (treehouse, fuel canopy) are wooden ladders.
    - Foundations: every building and structure on a slope stands on a stone foundation from its seat
      down to the lowest ground under it, so nothing floats.
    - NOT FIXED: the uphill sides of the hospital (3.1 st), west_storage_units (3.5), estate_0_mansion
      (3.3), east_fuel_market (1.6) and two old houses (1.3) still meet the slope. Their seats are the
      harvested ones: raising them would lift harvested roof routes off their roofs or put floors above
      the AI ground model (`World/Ground` is terrain-based), and the terrain is not carved under lots.
      The real fix is a terrain pad under these footprints at boot (World/Height + WorldTerrain), which
      also stops the hill reaching into the hospital's back rooms; that is W2 work.
11. **Buildings: FIXED.** The 20 outer homes have their v5.4 gables (body to the eave, roof to the
    harvested peak, gable infill, chimneys; data `params.roof = "gable"`, patch reasons updated); the
    ridge, downspout and gutter routes still pass. The hospital has ribbon windows on every floor with
    sills and accent floor lines, a roof parapet with a teal cap and a plant room, the v5.4 "HOSPITAL .
    EMERGENCY" sign on posts above the roofline with a red cross, and entrance surrounds (piers, lintel,
    glazed transom) at its front doors.

Also done for street level: ground plates no longer float over slopes (grass plates on hills are left to
the grass terrain; ponds and pools lie at the lowest ground of their footprint; courts, fields, the
playground and intersections are draped in tilted tiles), and the 3-stud detail boxes became small
objects (red hydrants, benches, bins, stop signs, a hoop, barrels, gnomes, flamingos, a garden swing,
planters).

## The export's ground-contact list now

`contact:` lines from `tools/review/export.luau` (it measures against the terrain only; parts marked
`Embedded`, i.e. foundations, seated poles and posts, piers and pilings, count as touching the ground):
Pipe_1079/1081 (bridge tower downspouts) and both bridge towers "float 44 st" and the five bridge lamps
"float 9 st" because they stand on the bridge deck over the river bed and ramps; the treehouse floats
32 st in its oak; Fence_625 (estate tennis net) 0.28 st. The pond and estate pools read "sunk" because
their water lies at the lowest ground of a sloping footprint. The remaining "sunk" buildings are listed
in finding 10.

## Not done / follow-ups

- Terrain pads under sloping lots (finding 10).
- A client fade of leaf clusters near the camera (LocalTransparencyModifier) would help when the squirrel
  climbs deep inside a crown; the leaves are already out of the squirrel's tunnel, but the camera can sit
  inside a cluster.
- The review renderer does not draw SurfaceGui text (signs show as blank boards in the PNGs).

## Files

- `src/worldgen/Factory.luau`, `tools/bake/editor_ground.luau`: CFrame instead of Position.
- `src/worldgen/Builders/Trees.luau` (new), `Builders/RouteProps.luau`: trees, poles, pipes, ladders,
  fences, parapets, trampoline enclosure, wires, bunting, hangers.
- `src/worldgen/Builders/Ground.luau` (new): plates, the Quay banks, river walls, the stone bridge.
- `src/worldgen/Builders/Props.luau` (new): canopy columns, dock pilings, trampoline, details.
- `src/worldgen/Surface.luau` (new): what stands under a point (terrain, paving, plates, decks, roofs).
- `src/worldgen/LampPlan.luau`, `Skyline.luau`: lamp placement and the lamp's arm and head.
- `src/worldgen/Plan.luau`, `Bake.luau`, `RouteCheck.luau`: dispatch, foundations, deck-aware roads,
  surface index, leaves not counted as route geometry.
- `src/worldgen/Builders/Building.luau`, `Shell.luau`, `Programme.luau`, `Hospital.luau`,
  `BridgeTower.luau`: ribbon windows, hospital facade, tower detail.
- Data: `data/authored/lot_types.json` (telephone poles by name; lamp 6 u), `data/authored/town/lighting.json`
  (spacingU, minGapU, crossClearU, height), `data/authored/town/lots/old_town_outer.json` (gables),
  `data/harvest_patches.json` (reason text); `generated/` recompiled.
- Tests: `tests/unit/world_bake.spec.luau`, `tests/unit/worldgen_look.spec.luau` (lamp rules, gables,
  110 poles, 30k part budget).
- Review tool: `tools/review/export.luau` (Embedded parts, face-plane z-fight check),
  `tools/review/views.json` (four views).
