# Wildlife, Foraging and Features Lost After v4.1: Porting Spec

Subsystem owner: **wildlife_foraging**. Roblox modules in the brief: `Wildlife` (fox, deer, birds, insects) and `Foraging` (gardens, feeders, trash, hollows, nut meter).

- **Sources.** Line numbers without a prefix refer to `reference/v5_4_game.js`. Lines prefixed `v4.1:` refer to `reference/v4_1_game.js`.
- **Data file.** `spec/data/wildlife.json` holds every coordinate list, colour and tunable in this document. It also lists all 95 trees, 24 nests and 30 insects.
- **Units.** All distances are HTML world units. 1 unit is about 2.5 studs (brief §2). +Y is up and models face +Z. Speeds are in units per second, with studs per second in brackets where useful.
- **Runtime-computed data.** Some positions only exist after the code runs: jittered outer trees, apple trees that pass the clearance filter, nests on boughs, and v4.1 objects relocated by `lifeFindGrass`. To get them, I ran a copy of the v5.4 and v4.1 code headlessly in Node, using the inlined three.js r160 and stubbed DOM/WebGL. The copy lives in the scratchpad; the reference files were not modified. The seeded RNGs make these values deterministic: neighbourhood `rng(20261008)` at line 90 and `livingRand = rng(540811)` at line 15133. They are marked **(runtime)**. Spot-check them in a browser, because DOM-dependent branches could in principle consume RNG differently.
- **Inferred items** are marked *(inferred)*.

---

## 1. Inventory at a glance

| Entity | v5.4 | v4.1 only (lost) | Count | Interactive in HTML? |
|---|---|---|---|---|
| Normal (AI) squirrels | yes, 5060 | (also in v4.1) | 7 | Spicy player bites them, which infects them and adds to town infection |
| Rabbits + bushes | yes, 5102 | (also in v4.1) | 4 | Pounce always fails |
| Yard cats | yes, 11514 | — | 3 | Swat the player (humans extractor owns behaviour) |
| Turtles, yard dogs, chained dogs | yes | — | 5 / 4 / 4 | Dogs bark and alert humans |
| Idle-watchdog predators (eagle/snake/cat/alligator/guard) | yes, 8185 | — | virtual | Game over after 13 min idle |
| Trees (all kinds) | yes | — | 95 (83 + 12 apple) | Climbable routes |
| Acorns on oaks | yes, 2015 | — | 55 per oak × 10 oaks | Visual only |
| Decorative knotholes | yes, 2001 | — | 5 per `makeTree` tree | Visual only |
| Shelter "hollow" stump, hollow log | yes, 3702 | — | 1 + 1 | Predator flavour and fog only |
| Apple trees (orchard) | yes, 15172 | — | 12 | Climbable; apples visual only |
| Bird nests on boughs | yes, 15385 | — | 24 | Visual only |
| Town birds | yes, 15330 | — | 32 (12 nest + 20 flock) | Visual only |
| Silent airliner overflight | yes, 15508 | — | 1 | Visual only |
| Garden plots | yes, 12619 | v4.1 had 5 more decorative gardens | 3 (+ Tabasco garden) | Tabasco garden is *meant* to conceal the player, but the test never fires in v5.4 (absolute-y bug, §10 and verifier notes) |
| Bird feeders | 2 decorative, 3121 | 5 decorative, v4.1:12394 | 2 / 5 | No |
| Trash cans and bins | 7 cans, 4 yard bins, 14 old-house bins, 1 waste container | 6 **scavengeable** cans, v4.1:12410 | — | v4.1 only (35 % coin chance) |
| Nut caches | — | **10 inspectable**, v4.1:12266 | 10 | v4.1: E to collect coins + Power |
| Deer | — | **5**, v4.1:12472 | 5 | v4.1: flee; 15 % bite chance |
| Fox | — | **1**, v4.1:12520 | 1 | v4.1: hunts and lunges at the player |
| Butterflies / dragonflies | — | **20 / 10**, v4.1:12347 | 30 | Visual only |
| Flowering bushes | — | 43 placed (of 76 tries), v4.1:12445 | 43 | Visual only |
| Hollow-tree territories, nut meter, stink gland, seasons | **absent** | absent (v4.1:12233 explicitly defers hollow trees to a "user-authored Blender GLB") | — | New in brief |

v5.4 has **no** foraging, nut, season, winter or snow code. A grep for `forag|nut\b|winter|snow|season` finds nothing relevant. The only "stash" hit (9354) is unrelated NPC bookkeeping.

---

## 2. Normal AI squirrels (v5.4)

### 2.1 Creation (5060-5101)
- Seven squirrels, one per hide spot (`normalSquirrelHides`, 5062). Each wanders around its own hide spot.

| i | hide (x,z) | ground y (runtime) | fur | Notes |
|---|---|---|---|---|
| 0 | (-74, -71) | -0.07 | #b78453 | Core SW, near BUR OAK yard |
| 1 | (84, 70) | -0.07 | #9a6b47 | Core NE |
| 2 | (-196, 97) | 0.03 | #b19b7b | West residential |
| 3 | (217, -111) | 0.43 | #675e4d | At the foot of OLD WATCH SYCAMORE (216,-109) |
| 4 | (-105, 321) | 7.37 | #a48c68 | North park |
| 5 | (103, 409) | 3.87 | #8c7463 | North park, east |
| 6 | (414, 332) | 0.03 | #c19c66 | Cedar Rest cemetery |

- **Model** (unscaled; all spheres via `squirrelBall`, 5050):
  - torso r 0.30 at y 0.27, scale (0.72, 0.68, 1.35)
  - head r 0.20 at (0, 0.47, 0.31)
  - ears r 0.07 at (±0.13, 0.65, 0.30)
  - eyes r 0.039, colour `#29302f`, at (±0.12, 0.49, 0.49)
  - tail r 0.30 at (0, 0.71, -0.48), scale (0.46, 1.7, 0.5)
  - 4 paws r 0.068 at (±0.18, 0.14, ±0.28)
  - root y = `outdoorSurfaceAt - 0.06`
- **Overall size.** About 1.2 units tall to the tail tip, with the torso top (shoulder) about 0.47 units, which is about 1.2 studs. That matches the brief's 1.2-stud shoulder.
- **Scale mismatch.** The player's spicy squirrel uses `SQUIRREL_VISUAL_SCALE = 0.335` (5155). Its body is r 0.55 at y 0.39, scale (0.79, 0.67, 1.51) (5171-5172), so its shoulder is only about 0.25 units. The NPC squirrels are therefore about 1.5× the player's body length and about 1.9× its shoulder height *(computed from geometry)*. The brief uses one squirrel rig, so this mismatch disappears.
- **Per-squirrel state:** `{i, root, torso, tail, x, z, phase: i*1.7, infected: false, progress: 0, component: 0}`.

### 2.2 Behaviour: `updateWildlife` (8898-8916)
The squirrels never climb, never interact with routes, and never avoid obstacles. Each frame:
1. `phase += dt × (infected ? 1.3 : 1.0)`.
2. Target position:
   - `x = hideX + sin(phase·0.83 + i) × W`
   - `z = hideZ + cos(phase·0.63 + i·1.3) × W`
   - W = 8, or 6 when infected. Peak target speed is about 6.6 u/s.
3. Root x,z lerp toward the target with factor `min(1, dt·2)`.
4. y = `outdoorSurfaceAt(x,z) - 0.06`, then raised to the max of four foot probes at (±0.24 side, ±0.36 front) minus 0.05, rotated by yaw.
5. Yaw = `atan2(target - pos)`.
6. Tail wag: `tail.rotation.x = sin(phase·7) × 0.17`.

**Scheduling.** The update is skipped entirely while the player is in the sewer or hospital (15948-15957, inside the `!player.inSewer && !player.inHospital` block). It runs through `updateOptional("Wildlife")`, so an exception disables it without crashing the game.

### 2.3 Bite (infection) by the spicy player: `tryWildlifePounce` (8946-8977)
- **Entry.** `updatePounceCollision` (6555) checks humans first, then police (`tryPolicePounce`), then `tryWildlifePounce`. The check needs `player.attackWindow > 0` and the player not in the sewer or hospital.
- **Rabbits are checked first** (§3).
- **Squirrel hit test.** The first uninfected squirrel with 3-D distance `player.pos → root < 1.42` is hit. On a hit:
  - `infected = true` and `phase += 3`.
  - Torso material becomes `#83544d`.
  - The first non-torso child (the head) gets `material.color.set("#a67860")`. `mat()` caches materials by colour/roughness (44-49), so this **recolours the shared fur material**. That changes the squirrel's head, ears, tail and paws, and any other mesh using the same `mat(hex)`. This is a latent HTML bug; in Roblox, recolour per instance.
  - Player gets `hits++`, `points += 90` (Power), and `squirrelCoins += 10` / `totalCoinsEarned += 10`.
  - Resets: `progress = 0`, `attackWindow = 0`, `secondsSinceBite = 0`, `idleTime = 0`, `player.inactiveSeconds = 0`.
  - UI: flash "ANOTHER SQUIRREL TURNS! +90 Power · +10 Coins" for 3 s; sfx (810 Hz, 0.12 s, triangle, 0.04).
- Each squirrel can be infected once. There is no cure or reversion.

### 2.4 Infection timer: `updateInfection` (8849-8865)
- `dt = min(realDt, 0.2)` (15958), so the timer runs on unpaused play time.
- Each frame, for each infected squirrel:
  - `canAdvance = infectionOwn ≥ 25 && secondsSinceBite < 600`
  - if `canAdvance`: `progress = min(1500, progress + dt)`. 1500 s is the "25-minute timer".
  - `portion = min(progress/1500, infectionOwn ≥ 25 ? 1 : 0.92)`
  - `component = (25/7) × portion`. The maximum is about 3.571 % per squirrel.
- Totals:
  - `infectionFromSquirrels = min(25, Σ component)`
  - Town reading = `clamp(infectionOwn + infectionFromSquirrels, 0, 100)` (8459)
- `infectionOwn` decays by 0.011 per second, or 0.05 per second in the duct (8851). Human bites add 3.6, patients 5.7 and staff 6.2 (8634-8641; infection extractor).
- **Meaning:** converted squirrels only "mature" while the rodent keeps biting (a bite within the last 10 minutes) and own infection stays at 25 % or more. All seven together can contribute at most 25 % of the town reading.

---

## 3. Rabbits (v5.4, 5102-5124; update 8918-8944)

| i | anchor (x,z) | colour | ground y |
|---|---|---|---|
| 0 | (-64, 93) | #ab9d87 | 0 |
| 1 | (72, 96) | #c2b39c | 0 |
| 2 | (-97, -70) | #786d62 | 0 |
| 3 | (206, 325) | #a88e78 | 4.09 |

- **Model:**
  - body r 0.36 at y 0.30, scale (0.8, 0.7, 1.65)
  - head r 0.24 at (0, 0.45, 0.43)
  - ears r 0.13 at (±0.15, 0.75, 0.47), scale (0.5, 2.5, 0.64)
  - eyes r 0.045
  - white tail r 0.21 at (0, 0.34, -0.6)
- **Bush per rabbit.** A sphere r 2.0, colour `#496c42`, centred at ground + 1.8, scale (1.7, 1, 1.2), so about 6.8 × 4 × 4.8. It is **not a collider**.
- **State machine** (per frame):
  - `phase += dt·1.6`
  - **DANGER:** player not in hospital or sewer, and XZ distance to the rabbit < 12. Then `escapeUntil = 2.5` and `phase += dt·9.5`.
  - `escapeUntil` decays by dt.
  - Target:
    - `x = ax + sin(phase·0.66 + i) × (escaping ? 15 : 7)`
    - `z = az + cos(phase·0.43 + i) × (escaping ? 14 : 9)`
  - Lerp factor `min(1, dt × (escaping ? 10 : 2))`. While escaping, the effective motion is a blur around the bush.
  - Hop: `y = terrainHeight + 0.13 + |sin(phase·4)| × 0.12`. This uses terrain, not `outdoorSurfaceAt`.
- **Pounce:** 3-D distance < 2.25. Then `escapeUntil = 4`, `phase += 4`, `attackWindow = 0`, and flash "Too quick! The rabbit slipped away. No reward." for 2 s. **Evasion is guaranteed** and there is no reward.

---

## 4. Yard cats (v5.4, 11514-11641): stats only
The humans and neighbourhood extractor owns their behaviour; the numbers here are for parity checks.

- **Homes** (anchored on the four core houses, 1248-1251):
  - cat 0 at (-45, -76), anchored at hNW+(11,-23): fur `#80614b`, legs `#bd9f7e`
  - cat 1 at (48, 79), anchored at hSE+(-10,23): fur `#454647`, legs `#ddd3bd`
  - cat 2 at (40, -79), anchored at hNE+(-11,-20): fur `#a19e88`, legs `#ddd3bd`
  - eyes `#d7e36e`, nose `#bb8b89`
- **Body:** r 0.72 scaled (0.8, 0.52, 1.28), so about 1.3 units tall and 2.4 long including the tail.
- **Speeds:**
  - wander 1.6 u/s (4 studs/s)
  - stalk 3.1 u/s (7.75 studs/s)
  - chase 8.5 u/s (21.25 studs/s)
  - turn rate 5
- **Sees the squirrel** when all of these hold:
  - XZ distance < 17.5
  - player height above ground < 2.8
  - player within 26 of the cat's home
  - player not on a route
  - player not in a house interior
- **States:**
  - CHASE if distance < 8, otherwise STALK.
  - Otherwise WANDER, orbiting home + (sin(φ·0.31+x)·7, cos(φ·0.23+z)·6).
- **Wind-up.** Triggers at distance < 3.0 with hit cooldown 0 and lasts 0.68 s (crouch to scale y 0.72).
  - Hit if distance < 2.75 and height < 2.4: knockback 10.5, vy ≥ 3.9, −12 Power, cooldown 7 s.
  - Miss: cooldown 4 s.
- **Voice.** Cooldown 4.5 s on wind-up; ambient meow within 10 units on a 6 s cooldown.
- **Collision.** Cats avoid house footprints with a +1 margin.
- **Paused** while the player is in the hospital or sewer.

---

## 5. Adjacent fauna in v5.4 (not owned here; listed so `Wildlife` can own or delegate)
- **Turtles** (10171-10199, update 10279-10287). Five turtles at (-125,328), (-104,349), (-25,84), (164,-448) and (-406,180). Each orbits its spawn: `phase += dt·0.15`, amplitudes 2.3 × 2.0, lerp 0.35. No interaction.
- **Yard dogs** (7950-7974; update 9091-9111). Four dogs at (203,363), (240,402), (98,311) and (55,345), wandering a small ellipse. A dog barks when the player is below y 5 and within 10 units. The bark has an 8 s cooldown, shows "WOOF! A yard dog spotted the squirrel.", and sets `alert ≥ 3` on humans within 12 of the dog.
- **Chained dogs** (10013-10047). Four dogs on the westside at (-403,-206), (-404,-75), (-418,63) and (-403,134), each with radius 3.4 and its stake at +(4, 2).
- **Idle-watchdog predators** (8185-8230). After 779 s with no movement (translation > 0.035 per frame), a 1.03 s warning plays; at 780 s it is game over. The predator depends on location:
  - hospital: "hospital security guard"
  - sewer: "small alligator"
  - inside a shed or house shelter zone: "cat"
  - other shelter zone: "snake"
  - outdoors: "eagle" ("A broad-winged shadow sweeps across the ground")

---

## 6. Trees, acorns, knotholes and existing "hollows"

### 6.1 Tree inventory (95 trees; full table with coordinates in `wildlife.json → v54.trees.list`)

| Group | Builder / lines | Count | Height | Trunk base radius | Positions |
|---|---|---|---|---|---|
| Core four | `makeTree`, treeSpec 1694 | 4 | 27-34 | 1.3 (route surfaceRadius 1.18, speed 0.82) | BUR OAK (-34,-33) h29 acorns; AMERICAN ELM (32,-37) h34; SYCAMORE (-37,29) h32; RED MAPLE (34,34) h27 |
| Outer canopy | `makeOuterTree` 2222, candidates 2183 | 36 | R(22,39) | 0.85 (surfaceRadius 0.81) | Nominal candidates jittered ±6 x / ±7 z, clamped to ±245. Exact runtime positions are in JSON. |
| Giant lookout trees | `makeLookoutTree` 2411, specs 2405 | 3 | 61 / 70 / 65 | 2.05 / 1.87 / 2.1 | SENTINEL OAK (-101,-146); HIGHLAND ELM (88,139); OLD WATCH SYCAMORE (216,-109). Each has 2 "OPEN SKY LOOKOUT" perches. |
| Estate gate oaks | `estateGateOak` 2824 | 4 | 28 | 1.65 | (-230,-329), (230,-329), (-219,-453), (219,-456) |
| Park trees | `makeOuterTree` index 90+i, 3395 | 8 | 25-38 | 0.85 | (-221,355), (-185,313), (-115,412), (-64,317), (14,395), (90,358), (-15,426), (-238,397). Perches on (-221,355), (-115,412), (90,358). |
| Extra canopy | `addExtraCanopy` 9371 | 10 | 22-30 | 1.3 | Shop Oak A (332,-24)*, Shop Oak B (362,24)*, Chilis Sycamore (412,-62), Pump Elm (468,34), Estate Oak South 1 (118,-356)*, Estate Oak South 2 (166,-327), Estate Sycamore South (228,-346), Villa Elm South (324,-333), Villa Oak South (377,-354)*, Villa Sycamore South (438,-327). * = acorns. |
| Treehouse Oak | 9504 | 1 | 31 | 1.3 | (-142,154), acorns. The treehouse floor is at about 13.2. |
| Westside shade oaks | 9985 | 7 | 34-46 | 1.3 | (-403,-238), (-401,-144), (-399,-116), (-403,-22), (-401,6), (-399,100), (-403,128). Even indices have acorns. |
| Westside street elms | 10003 | 4 | 30/37 | 1.3 | (-319,-185), (-328,-90), (-319,5), (-328,100) |
| Quay willows | 14068 | 6 | 19 | 1.3 | (715,-28), (715,43), (1004,79), (1108,52), (1094,192), (1015,370) |
| Apple trees | `makeAppleTree` 15172 | 12 | 8.5-9.7 | 0.58 | §7 |

### 6.2 Acorns (2015-2025)
- Every `makeTree` spec with `acorn: true` gets 55 acorns placed near random branch tips: sphere r 0.15 `#886641` with a cap `#6c4c2c`.
- Ten trees qualify: BUR OAK, Shop Oak A and B, Estate Oak South 1, Villa Oak South, Treehouse Oak, and Westside shade oaks 0, 2, 4 and 6.
- They are **not collectible**. These ten oaks are the natural nut sources for the brief's nut economy.

### 6.3 Decorative knotholes (2001-2013)
- Every `makeTree` tree (core, extra canopy, treehouse, westside, quay: 32 trees) gets 5 dark flattened spheres. Each is r 0.12-0.21, colour `#282521`, at a random height between 2 and `trunkH` (trunkH = 0.61 H).
- They are purely visual. The brief's "knothole" entrances can reuse this look at a larger, squirrel-sized scale.
- The giant-tree "knot" at 2476 is a branch-end knob under the lookout pads, not a hole.

### 6.4 Existing shelter hollows (3702-3725)
`shelterZones` is used by the idle-predator picker (8189) and by the fog/draw-distance "enclosed" test (9116-9119: within 2 units and below ground+3 gives fog 15-53).

| type | x,z | r | Model |
|---|---|---|---|
| log | (-19, 376) | 4 | Bark cylinder r 2.3-2.4, length 9.2, lying on its side, with a black cavity disc r 1.3 at one end |
| bridge | (-116, 371) | 4 | (pond footbridge) |
| **hollow** | **(95, 359)** | 4 | Bark stump: cylinder, top r 1.7 / base r 2.3, h 8. Black opening r 1.2 at y 1.9 on the −Z face. Ground y 5.22. |
| shed | (203, 328) | 6 | Park shed |
| house | (255, 328) | 7 | Pocket house |

The "hollow" stump is about 5 units from park tree (90,358) and about 27 units from the Tabasco garden centre. It is the only hollow-tree concept in v5.4.

### 6.5 Brief §3 hollow-tree proposal (11 territories)
Selection rules: spread across districts, near forage (gardens, feeders, trash, apple trees, restaurants, mall plaza), and prefer big trunks. Coordinates were checked in the headless run.

| ID | Type | Tree | x,z (ground y) | H | Why |
|---|---|---|---|---|---|
| H1 | **Premium** (interior pathway, multi-chamber) | park outer 95 | (90, 358) (5.0) | 33 | Absorbs the existing "hollow" stump (95,359) and the park high-watch perch. Tabasco community garden (115,341) is next door and becomes the premium garden. The restored v4.1 feeder (132,333) and nut cache (119,326) are nearby. Proposed premium feeder at (105,330) (clear). Risk: yard dogs at (98,311) and (55,345). |
| H2 | **Premium** | SYCAMORE (core) | (-37, 29) (0) | 32 | American sycamores are the classic hollow trees. Densest backyards. Garden plot (-36,52) is 23 away and becomes the premium garden. Apple 3 (-24,80). Restored v4.1 garden (-113,72), feeder (-89,70) and trash (-71,68). Proposed premium feeder in the hSW backyard at (-45,68) (clear). |
| H3 | Knothole | BUR OAK | (-34, -33) | 29 | Player spawn oak (`player.pos` starts at (-36,·,-36)), acorns. Apples 1-2, yard bins (-74,-76) and (71,-76). Risk: cats 0 and 2. |
| H4 | Knothole | HIGHLAND ELM (giant) | (88, 139) | 70 | North residential. Restored nut cache 3 (93,118), trash cans (120,194) and (107,204). |
| H5 | Knothole | OLD WATCH SYCAMORE (giant) | (216, -109) | 65 | East residential. v5.4 squirrel hide 3 is at its foot; compost bin (227,-70). |
| H6 | Knothole | SENTINEL OAK (giant) | (-101, -146) | 61 | Southwest. Restored caches 0 (-78,-88) and 5 (-225,-103); hose reel (-206,-143). |
| H7 | Knothole | Treehouse Oak | (-142, 154) | 31 | West stream (-143,83). Restored cache 4 (-158,116) and trash (-238,140); compost bin (-74,200). Acorns. |
| H8 | Knothole | Chilis Sycamore | (412, -62) | 27 | East commercial. Proposed dumpster behind Chili's at (474,-101) (clear); trash cans (419,77) and (538,-38). |
| H9 | Knothole | Estate Oak South 1 | (118, -356) | 29 | South estates (mansion 1 at (130,-370), pool, pergola). Acorns. |
| H10 | Knothole | Westside 4 shade oak | (-401, 6) | 46 | Westside old-house bins. Acorns. Risk: chained dog (-418,63). |
| H11 | Knothole | QUAY WILLOW | (1094, 192) | 19 | Riverside, about 42 from the Galleria plaza (x 1061-1145, z 234-415; fountain (1102,252)). |

- **Alternates:** RED MAPLE (34,34), park outer 90 (-221,355, pond), estate gate oak (-230,-329), Shop Oak B (362,24).
- **Premium trees need new authored models.** Outer and park trunks have a base radius of only 0.85 units (about 2.1 studs). A walk-up interior shaft for a squirrel about 1.2 studs at the shoulder needs roughly a 1.2-1.5 unit (3-4 stud) trunk radius *(inferred)*. Model the premium trees at giant-tree girth (r about 2 units, like 2411) and keep the HTML climb routes on the outside.
- v4.1 had already planned this: "A detailed walk-through tree will be supplied as a user-authored Blender GLB" (v4.1:12234).

---

## 7. Apple trees: v5.4 orchard (15131-15329)

- **Placement** (`plantAppleTrees`, 15273):
  - Three candidate sectors: core ring (12 candidates), north park (12) and riverside south orchard (10). The first 4 candidates in each sector that pass `appleSiteClear` are used.
  - If fewer than 12 are placed, a fallback row fills the gap: x = 982 to 1120, step 24, z ∈ {-226, -192}.
- **`appleSiteClear` (15152) rejects a site** that is:
  - within 8 of pavement
  - in river water
  - within 14 of the mall
  - inside the hospital bounds + 15
  - inside any house + 9 or old house + 9
  - inside commercial bounds + 10
  - within 24 of a river building
  - within 15 of any tree
  - within 8 of a utility support
  - or has any `outdoorBlocked` hit on a 3×3 probe grid at 3-unit spacing
- **Result (runtime):** 4 per sector, so the fallback row is not used. Sectors 1 and 3 use their first four candidates. In sector 2 the fourth candidate (12,381) is rejected because it is 14.1 units from park tree (14,395), which is inside the 15-unit tree clearance. The fifth candidate (38,410) becomes APPLE 8.

| # | x,z | base y | H |
|---|---|---|---|
| 1 | (-84,-24) | 0 | 9.68 |
| 2 | (-24,-84) | 0 | 8.53 |
| 3 | (-24,80) | 0 | 9.60 |
| 4 | (80,24) | 0 | 9.35 |
| 5 | (-85,352) | 6.43 | 9.45 |
| 6 | (-58,382) | 3.24 | 8.96 |
| 7 | (-28,399) | 1.00 | 9.37 |
| 8 | (38,410) | 1.16 | 8.85 |
| 9 | (988,-214) | 8 | 9.01 |
| 10 | (1018,-214) | 8 | 9.21 |
| 11 | (1048,-214) | 8 | 9.66 |
| 12 | (1078,-214) | 8 | 8.68 |

- **Model** (`makeAppleTree`, 15172):
  - H = 8.8 + U(-0.5, 1.0).
  - Trunk: 3 spans, radius 0.58 → 0.19, wood `#766047`, plus 5 surface roots of length 2.4.
  - Routes: trunk route (`surfaceRadius 0.5`, centre = base); 6 "bough" branch routes (`visualOffset 0.3`) reaching radius 3.7-5.0 at 0.70-0.87 H; 3 twigs per bough.
  - Leaves: 3 × 230 instanced, colours `#617f3c`, `#829e4d`, `#4e7138`.
  - Fruit: 40 hanging apples (2 × 20; red `#bf3e30` and yellow `#d5b54b`; lobed sphere r 0.205 with stems) plus **5 fallen apples** on the ground at radius 2.2-4.2.
  - Added to `trees` (with crown 6) and to `livingTown.appleTrees`.
- **Apples are not collectible** in v5.4. Nothing else references apple trees except the nest placement and the banner flash (16060).

---

## 8. Bird nests and town birds (15330-15506)

### 8.1 Nests (`populateNestsAndBirds`, 15435)
- **Branch selection.** Candidates are every route with `kind === "branch"`, a name containing "bough", and length > 3. There are 715 at that point (runtime), including apple boughs.
- For i = 0..23, the nest goes on `branches[floor(i × N / 24)]`, so the nests are spread evenly through registry order.
- **Placement:** at the route's point t = 0.66, raised by 0.48 (0.30 on apple boughs).
- **Nest model:**
  - bowl: half sphere r 0.5, scale y 0.38, colour `#5c4934`
  - rim: torus r 0.47, tube 0.085, colour `#8b7048`
  - 24 twig spans
  - 3 eggs r 0.09, colours `#c7d8cc` / `#e4d7b9`
- **Nest list (runtime, 24):** BUR OAK, RED MAPLE, outer 4, 8, 13, 17, 21, 25, 29, 34, OLD WATCH SYCAMORE lookout bough, park outer 90 and 94, Shop Oak A, Pump Elm, Estate Sycamore South, Villa Oak South, Treehouse Oak, Westside 2 and 5 shade oaks, Westside street elm 2, QUAY WILLOW (1004,79), APPLE 3, APPLE 8. Coordinates are in JSON.
- **Visibility:** shown only within 165 units of the player and hidden indoors (hospital, sewer, duct).
- **No interaction** (no egg raiding, no defence).

### 8.2 Birds
- **Model** (`makeTownBird`):
  - body sphere r 0.19, scale (0.85, 1, 1.8); head r 0.15
  - belly `#d4c9a7`, beak cone `#c3a564`, dark `#34413d`
  - two triangulated wings, span 0.96 each, pivoting about z
- **Nest birds:** every even-indexed nest (i = 0, 2, … 22), so **12 birds**.
  - Scale 0.75. Colour `["#8f4d35","#536b7a","#64594c"][i % 3]`. Perch offset (0.28, 0.35, 0.08) from the nest.
  - **Cycle:** `cycle = (t + U(0,36)) mod 48`.
    - PERCHED for 12 s: at the nest, heading `phase + sin(t)·0.12`, wings folded at 1.1 rad.
    - FLYING for 36 s, with u = (cycle − 12)/36, a = 2πu, r = 15 + 12·sin(πu). Position = nest + (sin a · r, sin(πu)^0.7 · 20, (1 − cos a) · r · 0.55). Bank sin(a)·0.15.
- **Flocks:** 5 flocks × 4 birds = **20 birds**.
  - Anchors `[x, z, y]` in code are stored as Vector3(x, y, z): (-42, 44, 42), (50, 48, 345), (460, 46, 95), (782, 49, 125), (998, 53, 110).
  - Orbit: a = 0.095·t + 0.38·i + flock; r = 24 + 2·flock; position = anchor + (cos a · r, sin 2a · 2.5, sin a · r · 0.7); bank −0.17.
  - About 2.3-3 u/s; one orbit takes 66 s.
  - Colour `["#536b7a","#785d43","#4d5350"][i % 3]`, scale 1 + U(-0.1, 0.15).
- **Wing flap:** z rotation = `side × (sin(10t + phase)·0.55 + 0.1)`.
- **Visibility:** within 210 of the player, hidden indoors. The "performance" render tier shows only even-indexed birds.
- **Scheduling:** `updateTownBirds` runs from `updateScenery` (15980), not gameplay. dt is 0 while paused.
- **No collision and no reaction** to squirrels or humans.

---

## 9. Silent overflights (15508-15633)
- **One airliner**, visual only. There is deliberately no audio or announcement (15508).
  - Fuselage: sphere scaled (0.72, 0.76, 8.1), about 16 units long, colour `#ecece1` with emissive `#808a91` at 0.12.
  - Wings span ±10; tailplane; fin `#477783`; 2 engines.
  - 2 contrails × 18 segments, colour `#f5f3e8`, opacity 0.25·(1−u)^1.7, each 4.4 units apart (about 80 units of trail).
- **State machine:**
  - **WAITING:** starts with `wait = 34` s and counts down only while `playing && player.alive`. At 0 it launches.
  - **LAUNCH:**
    - heading a = U(−1.1, 1.1), plus π on odd passes, so it alternates roughly +Z and −Z.
    - centre = player.pos + (U(±95), altitude U(165, 205), U(±75)).
    - from = centre − 630·dir, to = centre + 630·dir.
    - `passes++`.
  - **FLYING:** linear lerp over `duration = 48` s, which is **26.25 u/s (65.6 studs/s)**. Hidden while the player is indoors.
  - **DONE:** `wait = U(90, 150)`, hidden.
- In studs the altitude is 412-512, which is above the drone's 300-stud vantage (brief §3).

---

## 10. Foraging-relevant set dressing in v5.4 (none of it is interactive)

| Kind | Where (lines) | Positions | Notes |
|---|---|---|---|
| Garden plots (v3.5 pass) | 12619-12650, 12781-12784 | (-36,52) 7×4, variant 0, plants `#5d9c41`; (116,-24) 6.5×4.5, variant 1, `#c94f2d`; (-104,-18) 7.5×3.8, variant 2, `#7bbf53` | Soil `#7a5132`. Root is placed at **y = 0**, not terrain. Small wheelbarrow accent. |
| Tabasco community garden | 3589-3655 | Centre (115,341), ground 5.1 | 4 earth beds 4.5×24, 16 corn plants, 14 cabbages, 9 Tabasco pepper plants, sign. **Intended** to conceal the squirrel from humans (`gardenBlind`, 7034-7035): \|dx\| < 27, \|dz\| < 15, `player.pos.y < 2.4`, move speed < 3.4. **It never fires in v5.4:** the test uses absolute world y, but the terrain in that box is 3.9-5.7, so a squirrel on the ground is always above 2.4. Hosts one chili hiding area (5423). |
| Wheelbarrow perch | 3657-3669 | (139, 342) | `lookout` route at about +2.35 |
| Hedge patches | 3573-3586 | (125,303,14,2.3), (118,372,11,3), (-104,305,18,2.4), (290,306,22,2.6), (613,421,15,2.2) | Intended to conceal (`hedgeBlind`, 7036-7041: `player.pos.y < 2.8`, again absolute y). Only hedge (125,303) can trigger it, because its ground is 2.0-2.7; the other four sit on ground 3.5-7.7 and never trigger. |
| Bird feeders | 3121-3129, placed 3243-3249 | (-198,49) on outer home 18; (50,-221) on outer home 5 | Post 4.8 high, tray 1.9 at y 3.7, red cone roof |
| Trash cans | 3085-3091, 3256-3257, 3450-3455 | (150,-220), (120,194), (538,-38), (419,77), (-201,331), (-30,405), (82,311) | Cylinder r 0.72/0.62, h 1.58 |
| Compost bins | 3223 | (227,-70), (-74,200) | Slatted 2.5 box |
| Other yard props (gnome, hose reel, rain barrel, wheelbarrow, sprinkler) | 3243-3249 | in JSON | Backyard flavour |
| Core yard bins | 1487-1492 | (-74,-76), (71,-76), (-74,77), (71,77) | y = 0.62 (not terrain-following) |
| Old-house bins | 9948-9956 | 2 per westside house (14) | in JSON |
| Gas-station waste container | 897-901 | (535, 93) | Box 2.3×2.8×2.0, colour `#61756a` |
| Restaurants | 721 (Chili's), 12556+ (ice cream ×2), 902 (corner shops/diner), mall "COPPER CUP CAFE" (14778) | Chili's (474,-82), front faces +Z; ice cream (152,56) and (-154,-66) | **No dumpsters exist.** Proposed (clear in the headless check): Chili's back alley (474,-101); ice cream (152,66) and (-154,-76). |
| Mall plaza | 14984-15001 | Stone plaza x 1061-1145, z 234-415, y 8.12; fountain (1102,252) | The mall also has coin pickups (`mallCoin`, mall extractor) |

---

## 11. Features lost after v4.1 (v4.1:12233-12793): restore these
Installed once by `createWorldLifeEnhancements()` (v4.1:12736). Its console line: "10 nut caches, 5 deer, 30 insects, fox=true, Blender hollow trees deferred". Start-screen copy in the v4.1 HTML: "discover ten nut caches, encounter deer, foxes and butterflies".

### 11.1 Shared helpers (none of these exist in v5.4)
- **`lifeSafeSpot(x, z, minRoad = 4)`** (v4.1:12242). Returns true when the point is inside x ∈ [−255, 252], z ∈ [−240, 422] (the old town plus the north park only), at least `minRoad` from pavement (`pavementDistance`), and outside every house and every `commercialBounds` rect by 4.
- **`lifeFindGrass(x, z, minRoad)`** (v4.1:12249). Returns (x, z) if it is safe. Otherwise it does a deterministic ring search: 12 rings × 20 angles, ring step 3.2, angle offset 0.34·ring. It returns the first safe point, or null (object skipped).
- **`lifePutAt(root, x, z, yOffset)`** (v4.1:12261). Places the object on `terrainHeight` + offset and adds it to the scene.
- **`adjustHeading(cur, target, dt, rate)`** (v4.1:12558). Exponential angular approach, the same maths as v5.4 `turnToward` (6570).
- **Still present in v5.4:** `pavementDistance`, `houses`, `commercialBounds`, `terrainHeight`, `activeHouseInterior`, `squirrelCoins`/`totalCoinsEarned`, `refreshPowerUI`, `flash`, `fx`, `random`, `turnToward`, `outdoorBlocked`.
- **Missing in v5.4:** the four helpers above, plus `createNutCache`, `tryInspectNutCache`, `buildDecorativeGarden`, `createButterfly`, `createDragonfly`, `createBirdFeeder`, `createTrashCan`, `tryScavengeTrashCan`, `createFloweringBush`, `createDeer`, `createFox`, `updateLifeEnhancements`, `tryNewWildlifePounce`, `makeTownPeopleMoreDistinct` (humans scope) and `createWorldLifeEnhancements`.
- **Hooks that were removed:** `handleInteraction` (v4.1:7613-7614) called the nut cache and trash can handlers before the sewer and other handlers. `tryWildlifePounce` called `tryNewWildlifePounce()` first (v4.1:8625). The scheduler called `updateOptional("Fox, deer and insects", updateLifeEnhancements)` (v4.1:12840).
- In the Roblox world, `lifeSafeSpot` should become a query of the town data (lot footprints, road ribbons and walkable "grass" regions), not a hard-coded rectangle.

### 11.2 Nut caches (v4.1:12266-12316; coordinates v4.1:12737)
- **Placement:** relocated with `lifeFindGrass(minRoad 3.6)`.

| # (index) | nominal | placed (runtime) | ground y | coins | v5.4 check |
|---|---|---|---|---|---|
| 1 (0) | (-78,-88) | same | 0 | 3 | ok |
| 2 (1) | (-111,44) | same | 0.02 | 5 | ok |
| 3 (2) | (62,61) | (61.67, 67.39) | 0 | 7 | ok |
| 4 (3) | (93,118) | same | 0.27 | 3 | **Blocked in v5.4.** It sits 1.2 units from the trunk of outer tree 24; move it to (97,118). |
| 5 (4) | (-158,116) | same | 0.07 | 5 | ok |
| 6 (5) | (-225,-103) | same | 6.13 | 7 | ok |
| 7 (6) | (-215,265) | same | 4.5 | 3 | ok |
| 8 (7) | (-112,386) | same | 4.07 | 5 | ok |
| 9 (8) | (119,326) | same | 4.19 | 7 | ok |
| 10 (9) | (233,205) | same | 3.2 | 3 | ok |

- **Model:**
  - soil rim: cylinder r 0.89 → 1.1, h 0.28, colour `#5c4b35`
  - 6 pebbles r 0.22, alternating rock `#777b6e` and moss `#6c8751`
  - mossy lid: r 0.69, scale (1.05, 0.25, 1.0)
  - "finds" group at y 0.34: 4 acorns r 0.15, colour `#a77b41`, scale (0.85, 1.45, 0.85), on a 0.38 ring, with soil caps
- **Interaction** (E, `tryInspectNutCache`):
  - **Requires:** `playing` true; player not in sewer, hospital or duct; player not on a route; an uninspected cache within XZ 2.85 and |dy| < 2.8.
  - **Effect:** `inspected = true`; the finds group is hidden; `coins = 3 + (index mod 3)·2` (3, 5, 7, … , 48 in total); `squirrelCoins` and `totalCoinsEarned` increase by coins; `points += 5`; `inactiveSeconds = 0`.
  - **UI:** flash "NUT CACHE {index+1}/10 FOUND · +{coins} Squirrel Coins · +5 Power" for 3.5 s; sfx (690, 0.14, triangle, 0.023).
  - **One-time per run.** Caches never respawn.

### 11.3 Scavengeable trash cans (v4.1:12410-12444; coordinates v4.1:12766)
- **Positions** (relocated with `lifeFindGrass(minRoad 3.6)`; all unchanged and all valid in v5.4):
  - (-71,68), (53,-76), (221,61), (-238,140), (107,204), (134,392)
- **Model:** cylinder r 0.59/0.48, h 1.16, colour `#64756b`; lid `#364a41`; 6 ribs `#899d90`.
- **Interaction** (E, `tryScavengeTrashCan`):
  - **Requires:** `playing` true; not in sewer or hospital; not on a route; not in a house interior; an unused can within XZ 2.5 and |dy| < 2.6.
  - **Effect:** `used = true`. With 35 % chance (seeded `random()`), coins = `2 + (index mod 4)` (2, 3, 4, 5, 2, 3) and flash "TRASH CAN TREASURE! +{coins} Squirrel Coins" for 3 s with sfx (550, 0.09, triangle, 0.019). Otherwise flash "Nothing edible in this trash can. Keep searching." for 2.5 s.
  - **One-time per can.** No Power is awarded.

### 11.4 Decorative gardens (v4.1:12317-12346; coordinates v4.1:12750)
- **Positions** (relocated with `lifeFindGrass(minRoad 4.5)`):
  - (71.98, 62.02), kind 0, moved from (67,58)
  - (-113,72), kind 1
  - (107,264), kind 2
  - (-234,96), kind 1
  - (221,132), kind 0, ground 2.95
  - All are valid in v5.4.
- **Model:** bed 5.8 × 3.9, soil `#55412e`, border `#7f6141`. 4 rows × 5 plants (green stems with leaves). Fruit appears on plants where (k + j) mod 3 ≠ 0:
  - kind 0: `#7e314c` (beet or berry)
  - kind 1: `#d94b36` (tomato)
  - kind 2: flowers `#dd9a67` / `#a7abc9` / `#b47eb3`
- Each garden spawns 4 butterflies and 2 dragonflies.

### 11.5 Butterflies and dragonflies ("garden insects", v4.1:12347-12392; update v4.1:12566-12575)
- **Totals:** 30 insects = 5 gardens × (4 butterflies + 2 dragonflies).
- **Spawn:** each insect at garden + U(±2.2, ±1.7) for butterflies, or U(±1.8, ±1.1) for dragonflies.
- **Height above ground:** butterflies 1.8, dragonflies 2.1.
- **Butterfly model:** two wing pivots, each a flattened sphere r 0.17 scaled (1.7, 1.02, 0.15). Colour `["#e8bd51","#a8c5f0","#dd9dbb","#ecd68c","#bdc3d2"][(kind·4+i) mod 5]`. Body `#4a4545`, 0.34 long.
- **Dragonfly model:** body `#315253`, 0.65 long; 4 wings r 0.23 scaled (1.6, 0.07, 0.43); wing colour `#c0dce4` or `#adcbb8` alternating.
- **Initial phase:** butterflies `index·2.12`; dragonflies `index·1.31 + 0.9`. The index is per garden kind, not global: butterflies use `kind·4 + i` and dragonflies use `kind·3 + i` (v4.1:12344-12345). The dragonfly wing colour is `#c0dce4` when that index is odd and `#adcbb8` when it is even. Two gardens share kind 0 and two share kind 1, so those pairs have identical insect colours and phases.
- **Motion (all insects)**, with `phase += 4·dt`:
  - x = x0 + sin(0.35·phase)·0.65
  - z = z0 + cos(0.25·phase)·0.53
  - y = y0 + sin(0.57·phase)·0.48
  - left wing `rotation.y = sin(phase·F)·0.78`, right wing is the negative; F = 4 (butterfly, about 2.5 Hz) or 10 (dragonfly, about 6.4 Hz)
  - `rotation.y = 0.17·phase` (slow spin)
- **No interaction or collision.** The update only runs while `playing` and not paused, and is skipped in the sewer or hospital.

### 11.6 Bird feeders (v4.1:12394-12409)
- **Positions:** (-89,70), (88,75), (-219,215), (132,333), (237,308). No relocation was needed, and all are valid in v5.4.
- **Model:** post r 0.085/0.11, h 3.7, wood `#8b6445`; tray 1.15 square at y 3.22; seed cylinder `#bd8f5d` at 3.4; cone roof `#6f8c55` at 3.8.
- Decorative only.

### 11.7 Flowering bushes (v4.1:12445-12471)
- **Placement:** 76 attempts at x = R(−245, 243), z = R(−215, 407), each kept only if `lifeSafeSpot(4.1)` passes (then re-checked with `lifeFindGrass(3.7)`). 43 were placed (runtime list in JSON).
- **Model:** scale R(0.62, 1.32), drawn only when the spot passes; 3 foliage blobs. The variant is the attempt index i (0-75), not the placed count: foliage colour is `["#587844","#6a8850","#4e714c","#789557"][i mod 4]`, and bushes with i mod 5 = 0 get 6 pink flowers `#e3c6dc` (v4.1:12776-12779, 12460).
- Good butterfly anchors for the rebuild.

### 11.8 Deer (v4.1:12472-12519 create; 12576-12601 update; 12676-12701 bite)
- **Herd** (`lifeFindGrass(minRoad 7)`):

| Name | Sex | Size | Nominal | Placed (runtime) | Ground y |
|---|---|---|---|---|---|
| Willow | doe | 1.00 | (117,365) | same | 5.79 |
| Hazel | doe | 0.95 | (145,385) | same | 6.17 |
| Bracken | buck | 1.18 | (187,320) | (195.18, 314.98) | 3.59 |
| Ash | buck | 1.13 | (-204,353) | same | 2.35 |
| Fawn | doe, child | 0.55 | (137,366) | same | 5.83 |

  Four deer are in the north park around the Tabasco garden; Ash is by the pond.
- **Model** (× size):
  - torso r 0.83 at y 1.75, scale (0.72, 0.88, 1.35)
  - neck, head r 0.39 at (0, 2.56, 1.22), white muzzle
  - ears; 4 legs from 1.4 down to hooves; white tail
  - bucks: 2-tine antlers to y 3.71, colour `#c2ac82`
  - fur: doe `#ad845e`, buck `#946f4e`, fawn `#b99a70`; white `#dfd1b3`; hoof `#48443b`; eye `#25221e`
  - adult height about 3.1 units (7.75 studs) to the ear tips
- **State per deer:** `{name, root, origin, size, child, phase: R(0,9), heading: R(−π,π), speed: 0, scare: 0, biteCooldown: 0}`.
- **Update (every frame):**
  1. `phase += dt`; `scare` and `biteCooldown` decay.
  2. **Threat:** XZ distance to the player < 21 and the player's height above the deer's ground < 5. Then `scare = max(scare, 3.4)`.
  3. **FLEE** (scare > 0): desired heading points away from the player. Turn rate 5.6. Speed damps toward 11.8 for adults or 9.0 for the fawn (29.5 / 22.5 studs/s), damping λ = 6.
  4. **GRAZE/WANDER:** desired heading = `sin(phase·0.37 + origin.x)·1.3`. This is an absolute yaw oscillation, not relative to the current heading. Turn rate 1.2; speed damps to 1.25 (3.1 studs/s), λ = 1.3.
  5. **Step:** n = pos + (sin h, cos h)·speed·dt. Accept the step only if `lifeSafeSpot(n, minRoad = fleeing ? 2.6 : 5.1)` passes **and** n is within **95** of origin. Otherwise `heading += 0.67π` and `speed = 0`.
  6. y = terrain height. Gait: torso `rotation.z = sin(phase·(13 | 3))·(0.065 | 0.015)` for flee / calm.
- **Spicy-player bite** (`tryNewWildlifePounce`, after the fox check):
  - **Requires:** XZ distance ≤ 1.6 + 0.35·size, |dy| ≤ 2.8, `biteCooldown` = 0.
  - **Every attempt:** `attackWindow = 0`, `biteCooldown = 7`.
  - **15 % success:** `scare = 12`, `biteCooldown = 75`, `hits++`, `points += 32`, `secondsSinceBite = 0`. Flash "LUCKY DEER BITE ({name}) · +32 Power · Deer bolts away!" for 3 s.
  - **Otherwise:** `scare = 10`. Flash "{name} dodged the pounce! Deer bites succeed only 15% of the time." for 2.7 s.
  - No coins and no infection effect, except that the `secondsSinceBite` reset feeds the squirrel infection timer.

### 11.9 Fox (v4.1:12520-12556 create; 12603-12649 update; 12652-12674 bite)
- **Spawn:** one fox at (65, 313) (`lifeFindGrass(minRoad 7)`, unchanged), ground y 2.94. It is north of the core, near the park playground and yard dog 3 (55,345).
- **Model:** body r 0.75 at y 0.77, scale (0.69, 0.68, 1.28); fur `#b8663c`; white chest and muzzle `#e4d6bc`; dark ears, legs and eyes `#302c29`; tail r 0.39 scaled (0.75, 0.75, 2.0) with a white tip. About 1.6 units tall to the ear tips and 3 units long with the tail.
- **State:** `{root, origin, tail, phase, warning, attackCooldown, stun, facing}`.
- **Update (every frame):**
  1. Timers decay.
  2. **Valid target:** player not in sewer, hospital, duct or house interior, **and** player height above ground < 2.5. A squirrel on a route or high in a tree is therefore safe.
  3. **HUNT** if the target is valid, XZ distance < 24, and `stun ≤ 0`. Desired heading points at the player; turn rate 7; speed **8.8** (22 studs/s).
  4. **ROAM** otherwise. Desired heading = `sin(phase·0.58)·0.85` (absolute yaw); turn rate 1.5; speed 2.0.
  5. **Step:** accepted only if `stun ≤ 0`, `lifeSafeSpot(n, 2.3)` passes, and n is within **115** of origin. Otherwise the fox stays in place, with no heading change, so it can get stuck facing a wall until its heading oscillates.
  6. Tail wag: `sin(7·phase)·0.17`.
  7. **WARNING:** hunting, distance < 6, and `warning ≤ 0`. Then `warning = 6` and flash "FOX NEARBY · Keep your distance or escape into the trees!" for 2.1 s.
  8. **LUNGE:** hunting, distance < 2.15, and `attackCooldown ≤ 0`. Then:
     - `attackCooldown = 4.8`; `points = max(0, points − 17)`
     - knockback: horizontal 9 away from the fox, vy ≥ 3.5; the player detaches from the route and becomes airborne
     - flash "FOX LUNGE! −17 Power · Climb, dodge or surprise it!" for 2.9 s; sfx (180, 0.2, square, 0.04)
- **Spicy-player pounce on the fox** (checked first in `tryNewWildlifePounce`):
  - **Requires:** XZ < 1.75, |dy| < 2.2, `stun ≤ 0`. Sets `behind = cos(player.yaw − fox.facing) > 0.35`.
  - **Success chance:** 0.70 if the player is in focus/stalk mode, is more than 1.5 above the fox, or is behind it; otherwise 0.18. The seeded `random()` decides.
  - **Success:** `stun = 9`, `attackCooldown = 9`, `points += 55`, `hits++`, `secondsSinceBite = 0`. Flash "FOX SURPRISED! +55 Power · 9 seconds to escape." for 3 s.
  - **Fail:** `attackCooldown = 0`, so the fox can lunge immediately. Flash "The fox dodged your attack!" for 2.1 s.

### 11.10 Handler order (v4.1)
- **E key:** hospital interaction → nut cache → trash can → sewer, shops and so on.
- **Pounce:** humans → police → **fox → deer** → rabbits → normal squirrels.

---

## 12. Interactions with other subsystems

| Other subsystem | Interaction |
|---|---|
| **Routes** (climbing registry) | Trees, apple trunks and boughs are routes (`kind` trunk/branch/lookout). Nests are placed on `bough` branch routes at t = 0.66. Premium hollow interiors become new route kinds (an interior "shaft" route plus chamber nodes). |
| **Infection** | Each infected normal squirrel adds up to 3.571 % to the town reading (cap 25 %). The bite timer `secondsSinceBite` is shared with human bites and, in v4.1, with fox and deer bites. Brief §8: "biting regular squirrels raises town-wide infection rate". |
| **Power / coins economy** (HUD) | Squirrel bite +90 Power +10 coins; v4.1 nut cache +5 Power + 3/5/7 coins; trash 2-5 coins; deer +32; fox +55 / −17. Cats −12. The brief replaces Power/coins with rank, nut count and credits (Roles extractor). |
| **Humans / neighbourhood** | Garden and hedge concealment is meant to change human spotting (7034-7042), but because the test uses absolute y it only works at hedge (125,303) (see §10). Yard cats and dogs alert humans (dogs set `alert` within 12). Brief §7: feeders are "risky — birds and homeowners". |
| **Spicy rodent player** | Pounce resolution order (6555-6569); idle-predator watchdog (8185); a fox lunge or cat swat detaches the player from a route. |
| **Traffic** | No HTML interaction with animals. Brief §11: deer are startled by traffic. Fatal traffic (15758+) could also apply to animals (open question). |
| **Drone** (police) | None in HTML. Brief §11: deer are startled by the drone. |
| **Rendering / LOD** | Birds within 210 and nests within 165 of the player; performance tier halves birds; all hidden indoors. Apple leaves join `canopyAnimated` / `canopyShadowCasters`. |
| **Seasons** (new) | Winter: bare trees (leaf instancing toggled), no apples, reduced garden yield, survival check on the hollow meter. |
| **WorldGen / lots** | Brief §3 says each lot type defines what squirrels can forage and its risk. Gardens, feeders, trash and dumpsters should be lot-attached data. |

---

## 13. Brief deltas (brief section quoted, then addendum)

1. **§1 Source of truth:** "Lost in earlier HTML lineage and to be restored here: nut caches, deer, foxes, butterflies, garden insects." Restore §11 in full. Keep the HTML numbers as the starting tunables, but retarget the fox and deer roles (items 9 and 10 below).
2. **§2 Modules:** `Foraging` covers gardens, feeders, trash, hollows and the nut meter; `Wildlife` covers fox, deer, birds and insects. The town is a data file, so every forage source and hollow must be a data entry: lot-attached, with type, position, yield, risk and cooldown. Nothing is hand-placed.
3. **§3 World:**
   - *Neighbourhood expansion.* About double the restaurants, each with "outdoor seating or a back-alley dumpster (foraging value)". Add a community garden and a park with gazebo (both exist in v5.4: Tabasco garden (115,341) and gazebo (52,411)). Backyards get "gardens, bird feeders, sheds, fences, dog houses". "Each lot type defines what squirrels can forage there and how risky it is."
   - *Hollow trees.* "11 hollow trees … each a claimable squirrel territory with a nut meter. Two premium trees have an interior pathway running up the entire centre of the trunk, with chambers at several heights, and sit next to the best gardens and bird feeders. The other nine have a single hollow chamber reachable from a knothole." HTML has none; see the proposal in §6.5.
   - *Backdrop.* Keep the silent overflights; the sky must read from 300 studs up. The overflight is currently player-relative, so it must become world-relative (porting notes).
4. **§4 Actor model:** one actor kind per species (human, squirrel, fox, deer), each driven by an AI brain or a player. The v5.4 "normal squirrels" are ornaments on fixed ellipses. In the rebuild they become full squirrel actors with the same climbing, foraging and hollow-claiming abilities as players. The v4.1 fox and deer AI become the AI brains of possessable actors.
5. **§5 Population:** 10-14 squirrel actors (7 player slots) instead of 7 fixed NPCs plus 1 player. Deer have "several slots" and the fox has one. AI deer and fox exist when no player holds them (§11).
6. **§6 Ladder:**
   - Squirrel rank = 90 % nut count + 10 % stink-gland %.
   - An infected regular squirrel loses heavily (points and nuts) and drops in the queue. The HTML has infected NPC squirrels but no penalty.
   - Squirrels that die in winter restart as humans.
   - Deer and fox are side exits; leaving them returns the player to their previous human rank.
7. **§7 Foraging and territory:**
   - Sources: gardens, bird feeders (risky — birds and homeowners), trash cans and restaurant dumpsters, apple trees, the mall plaza. None of these are interactive in v5.4; v4.1 trash cans were (35 % chance).
   - Nuts stored in a claimed hollow raise its meter. Above 70 %, the squirrel owns the tree and others cannot take its nuts.
   - Premium gardens and feeders near the two big hollows can be raided about once per in-game week.
   - *Stink gland:* a slow-filling meter, fireable at 95 % or more, which costs 30 points and briefly repels foxes and humans.
8. **§8 Spicy rodent:** "biting regular squirrels raises town-wide infection rate". The v5.4 normal-squirrel infection share already does this, so keep 25/7 % per squirrel and the 25 % cap as the starting values. The rodent's "health regenerates slowly while sneaking or resting in a hollow", so the rodent also uses hollows; reconcile this with ownership (open question).
9. **§11 Fox:** "one player slot, Easter egg. Hunts regular squirrels; cannot harm the spicy rodent. Repelled by the stink gland." **This reverses v4.1**, where the fox hunted and lunged at the player, who was the spicy rodent. Keep the hunt/warn/lunge state machine but target regular squirrel actors, and make the spicy rodent immune. The v4.1 "valid target" rule (target below 2.5 units above ground and not indoors, so trees are safe) carries over.
10. **§11 Deer:** "Peaceful, wanders, can be startled by traffic and the drone." The v4.1 deer were startled only by the player squirrel within 21 units. Add threat sources: vehicles within a radius or on a closing course, and the drone below some altitude. Whether the spicy rodent can still bite deer (15 % chance in v4.1) is open.
11. **§11 AI-only:** birds and nests (from v5.4), butterflies, garden insects. Restore v4.1 insects and keep v5.4 birds and nests as AI-only ambient life.
12. **§12 Seasons:**
    - A week is the raid cycle.
    - Winter arrives every 5 in-game weeks and lasts 1 week: snow, bare trees, dimmer light, reduced foraging.
    - At winter's end, squirrels whose hollow meter is below the survival threshold die and restart as humans.
    - The target of about one winter cycle every 50 real minutes implies about 71 s per in-game day and about 8.3 real minutes per week (raid cycle) *(inferred: 6 weeks = 42 days in 3000 s)*.
    - The HTML has no seasons and no day/night (11308: "No day/night changes").
13. **Addendum A3 (avatar blending 70/30):** the squirrel, spicy rodent, fox and deer models must support tinting by region and pattern regions (stripes, patches, tail tip) coloured from the avatar's shirt and pants colours, plus eye colour and a head accessory socket. HTML identity colours to preserve as the "stock" 70 %:
    - fox: `#b8663c` / `#e4d6bc` / `#302c29`
    - deer: doe `#ad845e`, buck `#946f4e`, fawn `#b99a70`
    - squirrel furs: the seven listed in §2.1
    - Reverts to 100 % stock when control returns to the AI.
14. **Addendum A1/A2:** no direct wildlife requirement. Free roam means foraging and hollow claiming stay optional, but the brief's winter survival rule makes the hollow meter consequential (open question). The map's marker-layer system could carry a squirrel-only layer (own hollow, claimed hollows, cache hints): a proposal, not a requirement.
15. **Removed or unmentioned by the brief:** rabbits, turtles, yard cats, dogs and the idle-predator watchdog are not mentioned. Keeping them as ambient AI is my recommendation (open question).

---

## 14. Proposed foraging model for the brief (designer starting point; nothing below exists in the HTML)

| Source | Proposed yield and cooldown | Risk | HTML basis |
|---|---|---|---|
| Nut cache (10 restored + squirrel-buried) | 3/5/7 nuts (reuse the v4.1 coin values); respawn each in-game day | Low | v4.1:12266 |
| Acorn oaks (10 trees, 55 acorns each, visual) | 1 nut per gather at the canopy, per-tree pool regrowing daily; none in winter | Low, height-safe | 2015 |
| Apple trees (12) | Fallen apples (5 per tree) and hanging fruit (40) as food; regrow weekly; none in winter | Low | 15172 |
| Gardens (3 plots + Tabasco + 5 restored) | Per bed per day; **premium** beds next to H1/H2 are raidable once per in-game week | Homeowners, dogs, cats | 12619, 3589 |
| Bird feeders (2 + 5 + 2 premium) | Seed; refilled daily; **premium** weekly | Birds mob nearby; homeowner chases | 3121, v4.1:12394 |
| Trash cans and bins | v4.1 rule: 35 % chance, one use per can per day | Humans | v4.1:12425 |
| Restaurant dumpsters (new) | Higher yield, longer cooldown | Staff and humans | Proposed positions in §10 |
| Mall plaza | Crumbs near benches and the fountain; café spill | Crowd, humans | 14984 |

**Hollow meter** (all values are proposals):
- capacity C per tree, with premium trees at 2C
- the meter is `stored / C`
- **ownership** at ≥ 70 % (brief)
- below 70 %, other squirrels may steal or contest
- winter consumes a share of stored nuts
- the survival threshold is checked at winter's end

**Stink gland:** fills slowly and fires at ≥ 95 % (brief). The fill rate is a proposal.

---

## 15. Porting notes (Roblox)

### Authority split
- **Server-authoritative:**
  - hollow ownership and meters
  - nut counts and squirrel rank inputs
  - cache, trash and dumpster cooldowns
  - premium raid timers on the season clock
  - fox and deer positions while AI-driven
  - all pounce, lunge and bite resolution (distance checks done on the server, like the brief's swept traffic test)
  - infection contributions
- **Client-cosmetic, driven by a shared clock** (`workspace:GetServerTimeNow()` plus a fixed seed):
  - birds (flock orbits and nest cycles are closed-form functions of time)
  - insects
  - nest eggs
  - tail wags
  - the overflight

  These can run identically on every client with zero replication. In the HTML the overflight centre is player-relative; make the server pick a world-space centre (town centre ± jitter) and broadcast only the start time and seed.

### Movement
- The HTML moves animals kinematically: lerp toward closed-form targets, or step-and-reject against `lifeSafeSpot`. No physics.
- In Roblox, drive AI animals by CFrame on the server at about 10 Hz with client-side interpolation, or as anchored models with `TweenService`-free lerping. Avoid Humanoid physics for 30+ critters.
- When a player possesses a fox or deer, switch it to a client-owned assembly (network ownership to that player) with server sanity checks on speed:
  - fox about 22 studs/s hunting
  - deer about 30 studs/s fleeing
- Replace `lifeSafeSpot` with a precomputed grass/walkable mask or navigation regions from the town data. The v4.1 rectangle (x −255..252, z −240..422) only covers the old town and the north park.

### Scale (×2.5 studs per unit)
- normal squirrel wander radius 8 → 20 studs
- rabbit danger 12 → 30
- deer threat 21 → 52.5, leash 95 → 237.5
- fox hunt 24 → 60, lunge 2.15 → 5.4, leash 115 → 287.5
- cat sight 17.5 → 43.75
- bird visibility 210 → 525
- overflight altitude 412-512 studs; path 3150 studs long

### Performance (50 players plus AI)
- Budget about 14 squirrel actors, 5 deer, 1 fox, 4 rabbits, 3 cats and 8 dogs/turtles on the server.
- Keep birds (32), insects (30) and flowering bushes client-side and distance-culled. The HTML uses 210/165-unit cutoffs for birds and nests.
- Merge the 55 acorns per oak and the 40 apples per tree into one mesh per tree (the HTML instances them).
- Make tree leaves a separate model per tree so winter can hide them in one batch (bare trees). Make apples a separate part so they can be hidden for winter and regrown.

### StreamingEnabled
- Hollow trees, caches and forage props are interaction targets. Give their interaction anchors `ModelStreamingMode = Persistent` or keep them in server-side data, so the server never needs a streamed-in part.
- Spawn client cosmetic life only inside the streaming radius.
- Persistent or Atomic models for premium-tree interiors keep the interior route geometry whole.

### Determinism
- To reproduce exact HTML layout, port the `rng` function (lines 80-89, a mulberry32 variant using `Math.imul` and unsigned shifts) to Luau with `bit32`.
- Simpler and recommended: bake the runtime positions in `wildlife.json` into the town data file.

### Bug fixes when porting
- **Per-instance infected colours.** Do not mutate shared materials (the 8962 shared `mat()` cache issue).
- **Ground snapping.** v3.5 garden plots and core yard bins are placed at y = 0 instead of on the terrain. Snap them to the ground.
- **Height tests use absolute y.** Garden concealment (`player.pos.y < 2.4`), hedge concealment (`< 2.8`) and the yard-dog bark (`p.y < 5`) compare world y with a constant. On the raised north park they never fire (Tabasco garden, 4 of 5 hedges, and yard dogs 0 and 1). In Roblox, test height above local ground.
- **Nut cache 4.** v4.1 cache 4 sits inside the trunk of outer tree 24 in the v5.4 world. Move it to (97,118).
- **Fox stuck when blocked.** When a step is rejected, the v4.1 fox stays in place without turning (deer turn 120°). Give the fox the deer's rejection turn.
- **Pause scope.** HTML pauses all wildlife whenever the single player is in the sewer or hospital. In multiplayer, wildlife must always run on the server.

### Rewards and the HTML economy
Power, Squirrel Coins and Gold are HTML concepts. Map them to the brief's rank inputs: nut count (squirrels), credits (humans), and side-exit rank restore (fox and deer).

---

## 16. Open questions for the designer
1. **Ambient species the brief does not mention.** Keep rabbits (guaranteed evasion), turtles, yard cats, yard and chained dogs, and the 13-minute idle-predator watchdog? If cats stay, do they also threaten regular squirrel actors?
2. **Fox vs regular squirrel.** What does a successful fox lunge do to a regular squirrel: knock nuts loose, damage it, or kill it (which would turn it into a human)? Does the "valid target below 2.5 units, trees are safe" rule stay? Can the spicy rodent still pounce or stun the fox (v4.1: 70/18 % success, +55)?
3. **Deer.** Is the spicy rodent still allowed to bite deer (v4.1: 15 % chance, +32), and does a bitten deer matter for infection? Which traffic and drone conditions startle deer, and how many deer slots are "several"?
4. **Nut caches.** Fixed 10 one-time caches (v4.1) or respawning? Can squirrels bury their own caches (scatter-hoarding) that others can raid?
5. **Hollow meter.** What are the capacity per tree, the premium multiplier, the theft rules below 70 %, the winter consumption and the survival threshold? Can an AI squirrel own a hollow, and does a player inherit it on possession?
6. **Spicy rodent and hollows.** The brief says the rodent regains health "resting in a hollow". May it enter owned hollows? Does it infect the owner on contact?
7. **Raid cycle.** Is "once per in-game week" per premium source globally (first squirrel wins) or per squirrel?
8. **Bird feeders.** Do birds actively mob squirrels, or is the risk only homeowners? Are the v5.4 birds wired into feeders, or do feeders get their own small bird flocks?
9. **Nests.** Should nests or eggs be interactable (raid, defend)? The HTML has none; family-friendliness suggests no.
10. **Winter.** Do birds, insects and deer change? Suggested: insects vanish; birds thin to feeder flocks; deer stay; nests become visible in bare trees. Does snow slow ground movement or change route traction?
11. **Hollow-tree picks.** Confirm the proposed 11 (§6.5). Should the two premium trees be the giants (HIGHLAND ELM / SENTINEL OAK) for longer interior climbs, at the cost of distance from the best gardens?
12. **Apple trees.** Keep exactly the 12 v5.4 positions, or regenerate them from lot data? Are apples a separate food type or converted to "nuts" for the rank formula?
13. **Mall plaza foraging.** What is the food (café spill, bench crumbs)? Is the indoor mall (coins) separate from plaza foraging?
14. **Fatal traffic.** Can AI deer, the fox and AI squirrels be run over? Brief §8 applies swept collision to the rodent only.
15. **Overflight.** Global (everyone sees the same plane) or per-client cosmetic? A global plane is recommended.
16. **NPC squirrel scale.** The v5.4 NPCs are about 1.5× the player's visual squirrel. The brief uses one rig at 1.2 studs at the shoulder; confirm that one size applies to all squirrels.

---

## Added by verifier

1. **Concealment and bark tests use absolute world y, so they fail on raised ground (v5.4).**
   - `gardenBlind` (7034-7035) needs `player.pos.y < 2.4` inside |dx| < 27, |dz| < 15 of (115,341). The terrain in that box is 3.94-5.66 (computed with `baseTerrainHeight`, 407), and a grounded player sits at `getGroundAt` (6741-6755). The Tabasco garden therefore **never** conceals the squirrel in v5.4, even though the code intends it to.
   - `hedgeBlind` (7036-7041) needs `player.pos.y < 2.8`. Only hedge (125,303) has ground (2.03-2.66) low enough to work. The other four hedges sit on ground 3.53-7.66 and never conceal.
   - The yard-dog bark (9102) needs `p.y < 5`. Within 13 units of dog 0 (203,363) the ground is 4.9-6.4, so it almost never barks; dog 1 (240,402) is on 7.6-8.1 and never barks at a grounded squirrel. Dogs 2 (98,311) and 3 (55,345) work as intended.
   - Rebuild: test height above local ground for all three, as the cats already do (`heightAbove`, 11586).
2. **v4.1 deer can be bitten only while the fox exists.** `tryNewWildlifePounce` starts with `if (!foxCreature || …) return false` (v4.1:12652), so if `createFox` found no spot, deer bites were impossible too. In the rebuild, keep fox and deer pounce checks independent.
3. **v4.1 deer and fox ignore props, trees and water.** Their step test is only `lifeSafeSpot` (pavement distance, house and commercial rectangles + 4, and the x/z rectangle; v4.1:12242-12248) plus the leash. They walk through trees, fences, garden beds, the pond and feeders. In Roblox, navigation should also respect solid props.
4. **v4.1 life update gates.** `updateLifeEnhancements` returns at once when `!playing || gamePaused` (v4.1:12565). It also sits inside the scheduler's `!player.inSewer && !player.inHospital` block (v4.1:12834-12843).
5. **Other forage-relevant v5.4 set dressing the spec did not list:**
   - Doghouse with a metal **food bowl** in the hSE backyard: doghouse box at (39,80), bowl cylinder r 0.54 at (44, 0.1, 78) (1464-1469). This is a natural "pet food" forage source with dog or cat risk; cat 1's home (48,79) is next to it.
   - Park **pond** at (-147,371), bed radius 19, surface above ground (3357-3361), next to the footbridge shelter zone (-116,371). It is a candidate winter "frozen pond" visual.
   - West **stream** polyline (-175,92) → (-160,88) → (-142,82) → (-126,76) → (-112,74) (`addStream`, 12720 and 12752-12759).
6. **The only collectible ground pickups in v5.4 are the 8 hidden chilies** (`CHILI_COUNT = 8`, 5308; hide spots such as 5423; owned by the abilities spec). Their one-time pickup and HUD counter are the nearest existing template for forage pickups; the nut caches in v4.1 are the other.
7. **Runtime corroboration.** An independent headless route dump in the session scratchpad (from another extractor) reproduces, without changes, the 715 bough candidates, all 24 nest routes in §8.1 and all 12 apple trunk positions in §7.

---

## Verification log

Claims checked against `reference/v5_4_game.js`, `reference/v4_1_game.js` and the brief. "OK" means it matches the code; terrain heights were recomputed from `baseTerrainHeight` (407; v4.1:294).

1. 7 squirrel hide spots (5062-5070): OK
2. 7 squirrel fur colours (5071): OK
3. Squirrel model radii, positions and scales; eye colour `#29302f` = `M.black` (61): OK
4. Ground y column for hides (-0.07 … 7.37 = `outdoorSurfaceAt`): OK
5. `updateWildlife` wander amplitude 8/6, phase ×1.3, lerp `min(1, dt·2)`, foot probes, tail wag (8898-8916): OK
6. Peak squirrel target speed about 6.6 u/s (0.83 × 8): OK
7. Wildlife skipped in sewer/hospital, run through `updateOptional` (15948-15954): OK
8. Squirrel pounce: radius 1.42, +90 Power, +10 coins, 3 s flash, sfx 810/0.12/triangle/0.04 (8957-8976): OK
9. Shared-material recolour bug at 8962, `mat()` cache (44-50): OK
10. Pounce resets: FIXED (`player.inactiveSeconds = 0` was missing)
11. `updateInfection` canAdvance / 1500 s / 0.92 / 25/7 / cap 25 (8849-8865): OK
12. `infectionOwn` decay 0.011 / 0.05 in duct; bite gains 3.6 / 5.7 / 6.2 (8634-8641): OK
13. Town reading clamp (8458-8460); infection dt = `min(realDt, 0.2)` (15958): OK
14. NPC vs player scale "about 1.5×": FIXED (1.5× -> 1.5× length, about 1.9× shoulder height)
15. Rabbit anchors, colours, rabbit 3 ground y 4.09 (5103-5108): OK
16. Rabbit danger 12, escape 2.5, amplitudes 15/14 vs 7/9, lerp 10/2, hop formula (8918-8944): OK
17. Rabbit pounce 2.25, `escapeUntil` 4, message (8948-8954): OK
18. Rabbit bush r 2.0 at +1.8, scale (1.7, 1, 1.2), `#496c42`: OK
19. Cat homes from hNW/hSE/hNE offsets (1248-1251, 11558-11560), fur and leg colours: OK
20. Cat speeds 1.6/3.1/8.5, turn rate 5, house margin +1 (11561-11577): OK
21. Cat sight 17.5 / 2.8 / 26 / not on rail / not indoors; chase < 8: OK
22. Cat wind-up 0.68 s, hit 2.75/2.4, knockback 10.5, vy 3.9, −12 Power, cooldowns 7/4, voice 4.5/6: OK
23. Turtle positions and motion (10173-10199, 10279-10287): OK
24. Yard dog positions, bark 10 units / 8 s / alert within 12 (7953-7957, 9091-9111): OK (absolute-y caveat added)
25. Chained dogs positions, radius 3.4, stake +(4, 2) (10016-10047): OK
26. Idle watchdog 779/780 s, 1.03 s warning, predator by place (8186-8230): OK
27. Tree total 95 = 4+36+3+4+8+10+1+7+4+6+12: OK
28. Core trees positions/heights; trunk 1.3, surfaceRadius 1.18, speed 0.82 (1694-1735, 1781-1785): OK
29. Outer trees: 36 candidates (2183), jitter ±6/±7 clamped ±245 (2358-2361), R(22,39), trunk 0.85, surfaceRadius 0.81: OK
30. Giant trees h 61/70/65, r 2.05/1.87/2.1, two OPEN SKY LOOKOUT perches each (2405-2408, 2472-2483): OK
31. Estate gate oaks positions, trunk 1.65, H 28 (2900-2906, 2897): OK
32. Park tree positions and index 90+i (3395-3405): OK
33. Extra canopy names, positions, H 22-30, acorn flags (9371-9490): OK
34. Westside shade oak positions (derived from `oldHouse`, 9913-9916, 9983-9984), heights 34-46, acorns on even indices: OK
35. Westside street elms and quay willows positions/heights (10000-10012, 14061-14078): OK
36. Acorns: 55 per tree, r 0.15 `#886641`, cap `#6c4c2c`, 10 trees (2015-2025): OK
37. Knotholes: 5 per `makeTree` tree, r 0.12-0.21, `#282521`, trunkH = 0.61 H (1774, 2001-2013); 32 such trees: OK
38. Giant "knot" at 2476 is a branch-end knob: OK
39. Shelter zones table and stump/log models (3703-3725): OK
40. Fog "enclosed" test < 2 units / below ground + 3, fog 15-53 (9116-9120): OK
41. Stump to Tabasco garden distance "about 25": FIXED (25 -> 27)
42. `appleSiteClear` rejection rules (15152-15171): OK
43. "All 12 apple trees from the first four candidates": FIXED (sector 2 uses its 5th candidate (38,410) because (12,381) is 14.1 from park tree (14,395))
44. 12 apple tree positions and base y (runtime): OK (corroborated by independent route dump and terrain recompute)
45. Apple model: H formula, trunk 0.58 → 0.19, 5 roots 2.4, 6 boughs reaching 3.7-5.0 at 0.70-0.87 H, 3×230 leaves, 40 hanging + 5 fallen apples (15172-15271): OK
46. Apple banner flash (16060): OK
47. Nest candidate filter, 715 candidates, `floor(i·N/24)` (15435-15445): OK (corroborated by route dump)
48. 24 nest routes (BUR OAK … APPLE 8): OK (recomputed)
49. Nest t = 0.66, +0.48 / +0.30 on apple boughs; bowl/rim/twigs/eggs (15385-15429): OK
50. Nest birds: 12, scale 0.75, colours, perch offset, 48 s cycle (12 perched + 36 flying), flight path (15426-15433, 15462-15484): OK
51. Flock anchors mapped to Vector3(x, y, z), orbit formula, 66 s period (15446-15459, 15485-15492): OK
52. Bird visibility 210 / nests 165 / performance tier / hidden indoors (15496-15505): OK
53. `updateTownBirds` runs from `updateScenery` (15980): OK
54. Overflight: wait 34, duration 48, half path 630, altitude 165-205, jitter ±95/±75, next wait 90-150, 26.25 u/s (15509-15633): OK
55. Airliner model: fuselage scale (0.72, 0.76, 8.1), wings ±10, 18 contrail segments 4.4 apart, opacity 0.25·(1−u)^1.7: OK
56. v3.5 garden plots positions/sizes/variants/plant colours, root y = 0 (12619-12650, 12782-12784): OK
57. Tabasco garden: 4 beds 4.5×24, 16 corn, 14 cabbages, 9 peppers, sign (3590-3655): OK
58. "Tabasco garden conceals the squirrel": FIXED (code intends it, but the absolute-y test never fires on ground 3.9-5.7)
59. Hedge concealment: FIXED (only hedge (125,303) can trigger)
60. Wheelbarrow perch (139, 342), lookout at +2.35 (3657-3669): OK
61. v5.4 bird feeders (-198,49) and (50,-221) on outer homes 18 and 5 (3243-3249, 2049-2070): OK
62. 7 v5.4 trash cans and model r 0.72/0.62 h 1.58 (3085-3091, 3243-3257, 3450-3455): OK
63. Compost bins (227,-70), (-74,200): OK
64. Core yard bins, y 0.62 (1487-1492); old-house bins 2 × 7 (9954-9957): OK
65. Gas-station waste container (535,93), 2.3×2.8×2.0 (901): OK
66. Chili's (474,-82), ice cream (152,56) and strip (-154,-66) (721-724, 12786-12787): OK
67. Mall plaza x 1061-1145, z 234-415, y 8.12; fountain (1102,252) (14984-14985, 14201-14202): OK
68. Gazebo (52,411) (3465): OK
69. Proposed dumpster / premium feeder positions "clear in the headless check": UNVERIFIABLE (headless clearance run not repeated)
70. v4.1 `lifeSafeSpot` bounds x −255..252, z −240..422, margin 4 (v4.1:12242-12248): OK
71. v4.1 `lifeFindGrass` 12 rings × 20, step 3.2, offset 0.34·ring (v4.1:12249-12259): OK
72. All 15 listed v4.1 helpers absent from v5.4 (grep count 0 each): OK
73. Removed hooks v4.1:7613-7614, 8625, 12840: OK
74. Nut cache coordinates and coins 3/5/7 (total 48) (v4.1:12737-12749, 12307): OK
75. Nut cache 3 (index 2) relocated to (61.67,67.39): OK (consistent with ring 2, angle step 3)
76. Nut cache ground y values: OK (recomputed)
77. Nut cache model and `tryInspectNutCache` rules 2.85/2.8, message, sfx (v4.1:12266-12316): OK
78. Cache 4 (index 3) 1.22 from outer 24 at (92.61,116.84): OK (consistent with JSON tree list; runtime)
79. Per-cache "v5.4 check" column (all others ok): UNVERIFIABLE (runtime)
80. Scavenge cans positions, coins 2 + (i mod 4), 35 %, messages (v4.1:12410-12444, 12766-12774): OK
81. Scavenge requirements: FIXED (`playing` was missing)
82. v4.1 gardens positions/kinds, (67,58) → (71.98,62.02), bed 5.8×3.9, colours, fruit rule (v4.1:12317-12346, 12750-12757): OK
83. Insects: 30, spawn offsets, heights 1.8/2.1, butterfly and dragonfly models (v4.1:12344-12392): OK
84. Insect index and phase: FIXED (index is per kind: kind·4+i and kind·3+i, not global)
85. Insect motion, wing frequencies about 2.5 / 6.4 Hz, spin 0.17 (v4.1:12566-12575): OK
86. v4.1 bird feeders positions and model (v4.1:12394-12409, 12758-12765): OK
87. Flowering bushes: 76 attempts, x R(−245,243), z R(−215,407), `lifeSafeSpot(4.1)` (v4.1:12775-12779): OK
88. "Every 5th bush has flowers": FIXED (attempt index i mod 5 = 0; colour by i mod 4)
89. 43 bushes placed: UNVERIFIABLE (runtime RNG; not re-run)
90. Deer herd names/sex/size/nominal positions and ground y; Bracken → (195.18,314.98) (v4.1:12782-12788): OK
91. Deer model and colours (v4.1:12476-12503): OK
92. Deer update: threat 21/5/3.4, flee 5.6 / 11.8 / 9.0 / λ 6, graze 1.2 / 1.25 / λ 1.3, step 2.6/5.1, leash 95, turn 0.67π, gait (v4.1:12576-12601): OK
93. Deer bite 1.6 + 0.35·size, |dy| 2.8, cooldown 7/75, 15 %, +32, messages (v4.1:12676-12701): OK
94. Fox spawn (65,313), y 2.94, model and height (v4.1:12520-12556, 12789): OK
95. Fox update: valid target, hunt 24 / 8.8 / turn 7, roam 0.58 / 0.85 / 1.5 / 2.0, step 2.3 / 115, warning 6, lunge 2.15 / 4.8 / −17 / 9 / 3.5 (v4.1:12603-12649): OK
96. Fox pounce 1.75 / 2.2, behind > 0.35, 0.70/0.18, stun 9, +55, messages (v4.1:12652-12674): OK
97. Handler order (E key and pounce) (v4.1:7611-7614, 6261-6274, 8623-8625): OK
98. v4.1 console line and start-screen copy: OK
99. Brief quotes: §3 hollow trees, §5 10-14 squirrel actors, §7 70 % ownership, weekly raids, stink 95 % / −30, §11 fox/deer, §12 winter every 5 weeks: OK
100. "No day/night changes" (11308); `rng` (80-89), `random = rng(20261008)` (90), `livingRand = rng(540811)` (15133): OK
101. Fatal traffic block (15758+): OK
102. Stud conversions in §15 (×2.5): OK

**JSON spot checks (`spec/data/wildlife.json`)**, which parses as valid JSON:
- OK: rabbits, yardCats, shelterZones, acornTrees.names, appleTrees.candidateSectors, overflight, oldHouseBins (all 14 recomputed), trashCans y, birdFeeders y, compostBins y, nutCaches coins and y, deer y, fox spawn, scavengeTrashCans coins, nests.list (24 recomputed), birds.flocks.anchors, tree baseY (10 trees recomputed).
- FIXED: `v54.forage.note`; `tabascoGarden.concealment` (added effectiveInV54 false plus reason); `hedgePatches` (added per-hedge effectiveness).
- ADDED: `appleTrees.selectionNote` / `rejectedCandidates`; insect `index` / `initialPhase` / `wingColorRule`; `floweringBushes.variantRule`; `yardDogs` absolute-y note; `deer.pounce.requiresFox`.
