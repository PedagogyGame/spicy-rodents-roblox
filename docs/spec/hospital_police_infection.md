# Hospital, Police, Medical Response and Infection: v5.4 porting spec

Subsystem owner: `hospital_police_infection` extractor.
Source: `/home/user/spicy-rodents/reference/v5_4_game.js`. Every `Lnnnn` reference points to that file.
Brief = `reference/Roblox_Rebuild_Brief.txt`. Addendum = `spec/BRIEF_ADDENDUM.md`, which wins over the brief.

## 0. Conventions

- **Units.** All numbers are HTML world units unless marked otherwise. Brief §2: 1 unit is about 2.5 studs. Speeds are units/s. Times are seconds. +Y is up.
- **Hospital local frame.** Hospital geometry is built in a group placed at `(HOSP_X, HOSP_BASE, HOSP_Z) = (-356, 0.10, 353)` (L3813-3815). "Local (x, z)" means an offset from that origin, so world = local + (-356, 353).
- **Ground height.** `HOSP_BASE = terrainHeight(-356, 353)`. Evaluating `baseTerrainHeight` (L407-416) at that point gives the clamped minimum, **0.10**. The police station site (-510, -107) also evaluates to **0.10**. `HOSPITAL_FLOOR = HOSP_BASE + 0.42 = 0.52` (L3807). Any "y" below that is written relative to the floor is marked as such.
- **Two clocks.** `time` is game time; it is paused while the game is paused, and frame dt is capped at 0.08 (L16007-16011). Infection and hospital updates use real dt capped at 0.2 (L15958-15959).
- **One player.** The HTML is single-player and the player is always the spicy rodent ("the squirrel"). Every "player" below means the rodent.
- **Role flags.** The HTML has no hospital-staff or police player roles. Every staff member and officer is AI.

---

## 1. Function and line map

| Area | Functions / data (line) |
|---|---|
| Hospital site and shell | constants L3802-3807, roads L3809-3812, shell L3813-3863, partitions `innerWall` L3866-3879, signs L3880-3903, props L3905-4033, exterior signs L4035-4047 |
| Stretchers | `stretcherModel` L4049, 3 static stretchers L4064-4073 |
| Ducts | `ductNodes` L4076, `ductPointAt` L4089, `ductDistanceFromPoint` L4097, `ductTangentAt` L4113, `ductVents` L4119, duct meshes L4126-4211, hatch landing marker L4213-4252 |
| Hospital cast | `hospitalActors/Staff/Patients` L4965-5045, `hospitalExitPoint` L5046 |
| Normal squirrels (infection carriers) | L5060-5101; infection on pounce in `tryWildlifePounce` L8946-8978 |
| Doors / enter / leave | `updateHospitalDoors` L8429, `hospitalTeleport` L8475, `handleHospitalInteraction` L8556, `insideHospitalBuilding` L8467 |
| Duct travel | `enterDuct` L8500, `leaveDuct` L8515, `overheadHatch` L8526, `dropFromHatch` L8535, duct motion in `updatePlayer` L6643-6654, duct camera L7297-7313 |
| Interior movement | `adjustHospitalMovement` L8603, `knockPlayer` L8665 |
| Staff AI | `hospitalPatrolTarget` L8679, `staffCircuits` L8693, `updateHospitalActors` L8765, clipboard/charting wrapper L11644-11677 |
| Chewing | `updateChewing` L8867 |
| Infection | state L8413-8419, `infectionReading` L8458, `drawInfection` L8461, `grantInfectionBite` L8634, `checkUnannouncedEnd` L8645, `updateInfection` L8849 |
| Legacy ambulance (decorative loop) | L8979-9038 (`updateAmbulance`) |
| Hospital frame update | `updateHospital` L9039 |
| Crime scene → medical | `makeResponderAmbulance` L9149, `nearestRoadStage` L9166, `scheduleCrimeScene` L9198, `alarmNearbyWitnesses` L9227, bite hook L9271-9286, `updateCrimeScenes` L9287, bystanders L9684-9789 |
| Medical responders | constants L10440-10443, `pathPoint` L10444, `makeRoadTrip` L10447, `queueMedicalResponse` L10471, `advanceVehicleRoute` L10494, crews L10512-10537 and L10674-10717, `finishTreatment` L10538, `medicalBuildings` L10568, `medicalSegmentBlocked` L10576, `medicalWalkRoute` L10603, `medicalWalkDistance` L10654, `medicalWalkPoint` L10660, `emergencyY` L10718, `clinicDepthY` L10721, `treatmentArrivalLine` L10727, `placeSceneCrew` L10750, `rideMedicalStretcher` L10770, `beginHospitalHandoff` L10781, `updateMedicalResponders` L10805 |
| Police: patrol officer | patrol car + officer L7975-7995, `onSuccessfulBite` L7996, `dispatchCop` L8003, `officerBatonContact` L8012, `updateCop` L8026, `tryPolicePounce` L8083 |
| Police: station | building L10049-10077, precinct officers L10079-10093 and L10309-10314, station doors L12140-12153 and L12549-12552 |
| Police: incidents | cars/officers L10990-11009, `rollIncidentPolice` L11011, `startIncidentPolice` L11019, `sendPosterPolice` L11045, `updatePoliceResponse` L11050-11210, station reinforcements L11211-11222, station collider L11224 |
| Wanted posters | texture L11227-11263, placement L11266-11277, `updatePosterAwareness` L11278, poster witnesses in `updateHumans` L7053-7067, `speakWantedRecognition` L11286 (dead code) |
| Emergency beacons | `keepEmergencyActorsOutside` L12074, beacon materials L12096-12122, `updateEmergencyBeacons` L12123 |
| Scheduling | `updateGameplay` L15940-15969, `updateScenery` L15977, `updateNewSystems` L9053 and L9792-9798, `updateWestside` → `updateHospitalDoors` L10241 |
| HUD markup | `v5_4_shell_head.html` L35-37 (infection bar, chew panel CSS), L135 (INFECTION stat), L153-154 (chew panel, game-over overlay) |

---

## 2. Hospital building ("West Hospital Spur", v0.8 / v1.0)

### 2.1 Site, approach and signage

- **Footprint.** `HOSP_W = 94` (x) by `HOSP_D = 96` (z), centred on world (-356, 353). World extent: x -403 to -309, z 305 to 401 (L3802-3805). The front entrance faces **-Z (south)**, toward the road.
- **Ground patch.** `addNorthernGround(-429, -269.96, 245, 440)` (L3808).
- **Hospital road.** E-W asphalt along z = 283, 12 wide, x -417 to -238 (L3809). It continues the northern cross road z = 283, which runs x -241 to 651. Sidewalks along z = 273.5 and z = 292.5, 2.7 wide, x -421 to -238 (L3810).
- **Driveway.** N-S asphalt along x = -356, 8 wide, z 284 to 305 (L3811). Sidewalks along x = -362.5 and x = -349.5, 1.7 wide, z 283 to 306 (L3812).
- **Exterior signs** (L4035-4047):
  - "HOSPITAL · EMERGENCY", 35 by 2.65, over the entrance at world (-356, 14.35 + base, 303.5).
  - "SQUIRREL BITES →", 13.5 by 1.3, red `#9d4037`, at (-345, 9.25 + base, 303.2).
  - "EMERGENCY ENTRANCE", 27 by 2.6, at (-327, terrain + 3.6, 299).
  - Wayfinding "HOSPITAL ←" at (-232, terrain + 5, 298).
- **Apple trees** are excluded from the hospital footprint plus a 15-unit margin (L15154).

### 2.2 Shell (all local coordinates, y measured from `HOSP_BASE`)

| Element | Geometry | Line |
|---|---|---|
| Plinth | 97 × 0.8 × 99, `#abb4ac`, y 0.15 | L3822 |
| Floor slab | 94 × 0.18 × 96, `#b9c4ba`, y 0.57 | L3823 |
| East/west walls | 1.2 thick, 12 high, 96 long, at x = ±47; colour `hospitalWhite #e6e5db` | L3826 |
| Side windows | 4 per side, glass 9.1 long × 4.3 high at y 5.4, z ∈ {-34, -14, 12, 31} | L3827-3829 |
| Back (north) wall | 94 × 12 × 1.3 at z = +48 | L3831 |
| Front (south) wall | two 35.5-wide segments at x = ±29 (they cover \|x\| 11.25 to 46.75); lintel 19 × 5 at y 10 | L3832-3833 |
| Front doors | two glass leaves 7.55 wide × 7.6 high on hinges at x = ±8.2, z = -48.67, metal frame `M.metal` | L3834-3844 |
| Entrance canopy | 22 × 0.75 × 7.3, `#4a6b69`, y 8.1, z -51; two columns r 0.3 × 7.5 at (±9, -54) | L3845-3846 |
| Roof | 97 × 0.75 × 99, `#718c90`, y 12.8. Hidden while the player is inside. | L3847, L8448, L9041 |
| Ceiling light panels | 12 panels, 8 × 3.4, emissive-look `#f0f6db`, y 11.0, x ∈ {-34, -12, 14, 33}, z ∈ {-21, 5, 30} | L3848-3852 |
| Palette | white `#e6e5db`, brick `#a5ada9`, blue `#628e9d`, floor `#b9c4ba`, tile `#e5eee9`, glow `#f0f6db` | L3816-3821 |

**Roof as a surface.** From outside, `roofSurfaceAt` treats the whole footprint plus a 1.2 margin as a landable roof at `HOSP_BASE + 13.34 = 13.44` world (L6136-6144). **In practice only a perimeter strip is reachable** (verifier correction): every outdoor step whose x/z ends inside `insideHospitalBuilding()` (footprint inset by 2) is reverted at any height (L6735-6738, no y test). The rodent can therefore stand only on the ring between 1.2 outside and 2 inside the outer walls (about 3.2 wide), and it cannot cross over the building in mid-air either. **No climbing route reaches the roof in v5.4.** No tree, pole, wire or downspout touches the hospital; a grep of the hospital-area coordinates found none. The rodent can only land on that roof edge from a leap.

### 2.3 Floor layout: rooms and zones as built

Partitions come from `innerWall(x, z, w, d, h = 6.7)` (L3867-3870). Each one is also pushed to `hospitalObstacles` in world coordinates, and those boxes are the collision walls.

| Partition | Local centre (x, z) | Size w × d × h | Span | Line |
|---|---|---|---|---|
| Waiting/ward divider, west | (-29, -12) | 34 × 0.65 × 6.7 | x -46 to -12 | L3872 |
| Waiting/ward divider, east | (29, -12) | 34 × 0.65 × 6.7 | x 12 to 46 | L3873 |
| West triage alcove wall | (-22, -34) | 0.55 × 21 × 6.7 | z -44.5 to -23.5 | L3874 |
| East triage alcove wall | (22, -34) | 0.55 × 21 × 6.7 | z -44.5 to -23.5 | L3875 |
| Ward low wall, west | (-38, 2) | 17 × 0.55 × 5.0 | x -46.5 to -29.5 | L3876 |
| Ward low wall, east | (37, 2) | 19 × 0.55 × 5.0 | x 27.5 to 46.5 | L3877 |
| Back partition, west | (-22, 43) | 26 × 0.55 × 4.6 | x -35 to -9 | L3878 |
| Back partition, east | (27, 43) | 26 × 0.55 × 4.6 | x 14 to 40 | L3879 |

The waiting/ward divider leaves a **24-wide central doorway** (x -12 to 12) at z = -12.

**Zones** (sign text, sign position, line):

| Zone (HTML) | Local bounds (approx.) | World centre (approx.) | Signs | Contents |
|---|---|---|---|---|
| Entry / Waiting / Triage | x -47 to 47, z -48 to -12 | (-356, 323) | "EMERGENCY ENTRY" (0, -39); "EXIT" (0, -44); "WAITING / TRIAGE" (0, -17) (L3885, L3895-3900) | 8 waiting benches; 4 triage benches; 2 carts; floor guide stripes |
| West triage alcove | x -47 to -22, z -48 to -23.5 | (-390.5, 317) | — | triage benches (-32, -26), (-31, -22); bench (-30, -35) |
| East triage alcove | x 22 to 47, z -48 to -23.5 | (-321.5, 317) | — | triage benches (32, -27), (32, -23), rotated π; bench (32, -35) |
| Reception / Check-in band | x -47 to 47, z -12 to ~2 | (-356, 348) | "RECEPTION" (-20, -8); "PATIENT CHECK-IN" (19, -8) (L3896-3897) | nurse desk (-18, -3); check-in desk (18, -3); 5 chart cubbies with monitors along z = -7, x -18 to -8.6 (L3909-3912) |
| Treatment Ward (one open ward) | x -47 to 47, z 2 to 43 | (-356, 375) | "TREATMENT WARD" (0, 9); "BAYS 1 - 4" (-24, 11); "BAYS 5 - 8" (23, 31) | 8 beds in two rows of four; IV poles; monitors; surgical lamps; treatment desks (±18, 2) |
| Supplies (NW) | around x -45 to -31, z 38 to 43 | (-394, 393) | "SUPPLIES" (-31, 42) | shelving at x -42 and -36, z 40: 4 shelves × 3 boxes each (L3931-3945) |
| Observation (NE) | around x 14 to 40, z 42 to 48 | (-329, 395) | "OBSERVATION" (26, 42) | sign only; no furniture |
| Rear corridor | z 43 to 48 behind the back partitions | (-356, 398.5) | — | empty strip (inferred to be a service corridor) |

**Beds** (L3972-3985). Bed `i` sits at local x = -33 + (i % 4)·22 and z = 15 + floor(i / 4)·20. Each bed is 7 × 0.7 × 11 (`#d9e7e6`) with a pillow end at z + 4.3 and a translucent curtain at x + 4.1 (opacity 0.67).

| Bed index | Local (x, z) | World (x, z) | Patient station (world) |
|---|---|---|---|
| 0 ("Bay 1") | (-33, 15) | (-389, 368) | (-389, 361.65) |
| 1 | (-11, 15) | (-367, 368) | (-367, 361.65) |
| 2 | (11, 15) | (-345, 368) | (-345, 361.65) |
| 3 | (33, 15) | (-323, 368) | (-323, 361.65) |
| 4 ("Bay 5") | (-33, 35) | (-389, 388) | (-389, 381.65) |
| 5 | (-11, 35) | (-367, 388) | (-367, 381.65) |
| 6 (under the overhead hatch) | (11, 35) | (-345, 388) | (-345, 381.65) |
| 7 | (33, 35) | (-323, 388) | (-323, 381.65) |

The bay numbering by index is inferred from the "BAYS 1 - 4" and "BAYS 5 - 8" signs.

**Other props** (decorative unless they appear in §2.4):

- **Waiting benches.** x ∈ {-30, -14, 16, 32}, z ∈ {-35, -18}. 5 × 0.5 × 2.1 seat in `#7e9ba1` with a blue back (L3853-3857).
- **Carts.** (-31, -17), (31, -18), (39, 7). Each is 3.6 × 1.35 × 2.3 (L3946-3955).
- **Per-bay detail.** At x ∈ {-33, -11, 11, 33}, z ∈ {15, 35}: monitor, IV stand, surgical lamp r 1.65 at y 10.7 (L3957-3965).
- **IV poles.** (-30, 14), (-8, 35), (12, 15), (33, 35) (L4009-4019).
- **Treatment desks.** (±18, 2), each 5.8 × 1.5 × 2.3 (L4020-4028).
- **Side screens.** Six panels, 0.22 × 3.8 × 4.0, `#bed5d0`, at x = ±43.5, z ∈ {-8, 5, 18} (L4029-4033). The code comment calls them an "isolation curtain", but they stand along the side walls. **There is no isolation room.**
- **Plants.** Corners (-42, -43), (40, -42), (-40, 39), (40, 39) (L3913-3929).
- **Floor guides.** Teal spine 3.4 wide × 67 long at x = 0. Tan cross-aisle "triage line" 69 × 2.6 at z = 5.9. Guide stripes at x = ±8.3, 43 long, centred at z -24. Dashes every 7 units along x = 0 (L3890-3907).
- **Static stretchers.** (-33, -1), (28, 3), (-18, 33). Each is 5.3 × 2.25 with a blue pillow (L4049-4073).

### 2.4 Interior collision

- `hospitalObstacles` holds the 8 partitions in world coordinates (L3869).
- `hospitalFurnitureColliders` (L3968-3971 and L3984) holds:
  - the nurse desk at world (-374, 350), 12.5 × 3.8;
  - the check-in desk at world (-338, 350), 12.5 × 3.8;
  - all 8 beds, 7.3 × 11.3 each.
- **Player** (`adjustHospitalMovement`, L8603-8633):
  - Clamp to x ∈ [HOSP_X - 47 + 2.3, HOSP_X + 47 - 2.3] and z ∈ [HOSP_Z - 48 + 2.4, HOSP_Z + 48 - 2.4].
  - Sub-step the move: steps = clamp(ceil(dist / 0.28), 1, 18), sliding per axis.
  - Collide with obstacles and furniture inflated by 0.23.
  - Floor y = HOSPITAL_FLOOR + 0.2 (L6746).
- **Staff** do not collide. They route around the partitions with `hospitalPatrolTarget` waypoints (§5.3).
- **Outside the building.** Any outdoor step that ends inside `insideHospitalBuilding()` (the footprint inset by 2) is reverted unless a door transition is running (L6735-6738). The building is solid from outside except through the door transition.

### 2.5 Isolation of the interior (HTML technique)

The interior is a "teleport room": the player is flagged `player.inHospital`. While that flag is set:

- **Paused systems** (L15948-15957): pedestrians, special cyclists, cars, heavy traffic, ice cream truck and trolley, wildlife, cats, the legacy ambulance, the patrol cop (`updateCop` is skipped, L9114), yard dogs (L9091), and fatal-traffic detection (L15774).
- **Systems that keep running:**
  - infection;
  - the hospital update;
  - `updateNewSystems`, which carries crime scenes, medical responders and bystanders;
  - `updatePoliceResponse`, which carries incident and station police. Its incident officers fall back to investigating the scene (L11093).
- **Rendering** (L9116-9132, L13225-13238):
  - roof hidden;
  - fog near/far lerp toward 15 / 53, against 310 / 1050 outdoors;
  - camera far 125 (55 in the duct);
  - background `#455c5b`;
  - tone-mapping exposure 1.12 (the `updateVisuals` value overrides the earlier 1.19);
  - sky hidden.
- **District tag** (L9062-9067): "HOSPITAL · DUCTS", "HOSPITAL · EMERGENCY", or "HOSPITAL DISTRICT" when x < -270 and z > 245.
- **Interior camera** (L7363-7381):
  - Clamp the eye to the footprint inset by 1.8, and y to [floor + 0.22, floor + 11.2].
  - March 16 samples from target to eye; pull in to the previous sample at the first sample that hits a partition (inflated 0.16). The march stops (break) at the first sample above floor + 7.
  - Damping rate 9.5.

---

## 3. Doors, entering and leaving

### 3.1 Front doors (`updateHospitalDoors`, L8429-8456; called from `updateWestside` L10241)

1. `near` = the player is within 15 (horizontal) of the door centre (HOSP_X, HOSP_Z - 48) = world (-356, 305).
2. If `near`, set `hospitalDoorHold = max(hold, 1.5)`. Otherwise it decays by dt.
3. The doors target fully open (1) when `near`, during a transition, or while `hold > 0`.
4. `hospitalDoorOpen` damps toward the target at rate 7.5. Each leaf rotates `-side · open · 1.36 rad` (about 78°).
5. Ambulance handoff states raise `hospitalDoorHold` (§7.5): 8 at handoff start, then at least 1.5 to 2.0 each frame.

Only the player and ambulance crews open the doors. AI pedestrians do not.

### 3.2 Entering and leaving (`handleHospitalInteraction` L8556; `hospitalTeleport` L8475)

Interaction key: **E**. The handler runs right after the mall handler (L7915-7916).

| From | Condition | Action |
|---|---|---|
| Outside | horizontal distance < 8 from world (-356, 298) **and** \|y - terrain\| < 4 | `hospitalTeleport(true)` |
| Inside, not in the duct | distance < 6 from `hospitalExit` = (-356, floor + 0.2, 312) | `hospitalTeleport(false)` |
| Inside or in the duct | near a vent | §4 |
| Elsewhere inside | — | hint: "Find a grille in the wards or the emergency doors." or "Follow the duct lights toward a grille." |

**Transition state machine** (`hospitalTransition`, L8486-8492 and L8436-8455):

- **Start.** Clear rail, duct, sewer, velocity and attack window. Set `hospitalDoorHold = 4.0`. Flash "EMERGENCY DOORS OPENING" or "LEAVING EMERGENCY WING".
- **Duration 1.45 s.** Position = smoothstep lerp from the current position to the target. Targets:
  - inside: (-356, floor + 0.2, 314) = local z -39;
  - outside: (-356, terrain + 0.2, 294) = local z -59.
- **At progress > 0.47.** Set `player.inHospital = enter` and toggle the roof.
- **At progress ≥ 1.** Clear the transition and set `hospitalDoorHold = 2.4`.
- **During the transition** `updatePlayer` returns immediately (L6574-6578). The player has no control.

---

## 4. Ducts, vents, chewing and the overhead hatch

### 4.1 Duct path (L4076-4117)

The duct is a polyline of 7 world-space nodes. Y is given relative to the floor (`HOSPITAL_FLOOR`, world 0.52).

| Node | Local (x, z) | World (x, z) | y above floor | Segment length to next | Cumulative s |
|---|---|---|---|---|---|
| 0 | (-38, -12) | (-394, 341) | 2.8 | 29.000 | 0 |
| 1 | (-9, -12) | (-365, 341) | 2.8 | 37.000 | 29.000 |
| 2 | (-9, 25) | (-365, 378) | 2.8 | 39.000 | 66.000 |
| 3 | (30, 25) | (-326, 378) | 2.8 | 4.238 | 105.000 |
| 4 | (30, 29) | (-326, 382) | 4.2 | 7.782 | 109.238 |
| 5 | (30, 36) | (-326, 389) | 7.6 | 19.000 | 117.020 |
| 6 | (11, 36) | (-345, 389) | 7.6 | — | **136.020 total** |

- **Route.** The duct runs along the waiting/ward divider, north through the reception band along x = -9, then east along the aisle between the bed rows (z = 25). It ramps up at x = 30 and ends above bed 6.
- **Cross-section.** Interior 2.7 wide × 1.76 high. The floor sits at -0.88 from the centreline (L4147-4150). Walls and roof are translucent `#829a96` at opacity 0.29. Ribs every 5 units; warm strip lights every 8 units.
- **Floor hole.** The last segment's floor stops about 3.1 short, leaving a real hole at the hatch (L4147).
- **Accent lamps.** At nodes 1, 2, 3, 5 and 6 (L4207-4211).
- **Collision.** The duct does not collide with walking actors. Its centreline is 2.8 above the floor, so humans (about 2.1 tall) visually clip it (inferred).

**Path functions:**

- `ductPointAt(s)`: clamp s to [0, total], then linear interpolation inside the segment.
- `ductDistanceFromPoint(p)`: nearest arc-length position by projecting onto each segment.
- `ductTangentAt(s)`: normalised (P(s + 0.6) - P(s - 0.6)).

### 4.2 Vents (`ductVents`, L4119-4125)

| Vent | World (x, z) | Height above floor | Kind | Chew time | Reachable from |
|---|---|---|---|---|---|
| 0 | (-394, 341) | 2.8 | low grille, `first: true`, rotated 90° | **120 s** | floor, or inside the duct |
| 1 | (-365, 341) | 2.8 | low grille | 24 s | floor or duct |
| 2 | (-365, 378) | 2.8 | low grille | 24 s | floor or duct |
| 3 | (-326, 378) | 2.8 | low grille | 24 s | floor or duct |
| 4 | (-345, 389) | 7.6 | overhead hatch (`upper: true`) | 24 s | **inside the duct only** |

- Every vent starts `open: false, chew: 0`.
- **Once opened, a vent stays open for the session** and its mesh is hidden (L8885-8886).
- **Chew progress is never reset**, so partial progress persists after a cancel (L8879).
- **Shortcut (code fact).** Vent 0 needs 120 s, but vents 1 to 3 can be chewed from the ward floor in 24 s. The 2-minute "first entry" can be skipped. The flash text only mentions the 120 s for vent 0 (L8589).

### 4.3 Vent interaction rules (L8573-8594)

1. **Candidates.** Low grilles always qualify. The upper hatch qualifies only when `player.inDuct`.
2. **Radius.** Horizontal distance < 4.7 for a grille, < 3.2 for the hatch.
3. **Height check in the duct.** When in the duct, the vertical gap must satisfy \|y - (floor + height - 0.72)\| < 2.6.
4. **Open vent:**
   - Upper hatch → hint "UPPER HATCH OPEN · SPACE drops · LEFT CLICK pounces into the ward!"
   - Grille while in the duct → `leaveDuct(vent)`.
   - Grille while on the floor → `enterDuct()`.
5. **Closed vent.** Start chewing: `hospitalChew = {vent, origin: player position}`. Flash "HOLD E to chew the …".

### 4.4 Chewing state machine (`updateChewing`, L8867-8897)

It runs only while the player is enclosed (`inHospital` or `inDuct`); otherwise it is cancelled (L9043-9048).

- **States.** IDLE → CHEWING → (OPENED | CANCELLED).
- **CHEWING, each frame:**
  - Cancel if **E** is released, **or** the player is more than 1.3 from the chew origin, **or** more than 4.9 (3.2 for the hatch) horizontally from the vent.
  - Otherwise `vent.chew = min(required, chew + dt)`, where `required` = 120 for the first vent and 24 for every other vent.
  - Show the chew panel: "CHEWING VENT · n / required sec · EXPOSED" ("CHEWING OVERHEAD HATCH · …" for the hatch), where n = floor(chew).
- **OPENED.** `vent.open = true`, hide the panel mesh, play a sound, flash "VENT OPEN! E to enter or leave the duct." or "UPPER HATCH OPEN! SPACE drops · LEFT CLICK pounces."
- **Exposure.** While chewing on the floor the rodent stays exposed to hospital defenders (§5.4). A knockback moves it more than 1.3 and cancels the chew.

### 4.5 Duct travel

- **Entering** (`enterDuct`, L8500-8514):
  - Set `inDuct` and `inHospital` true.
  - `ductTravel = ductDistanceFromPoint(player.pos + (0, 3.05, 0))`.
  - Position = duct point minus 0.72 in y.
  - Hard-cut the camera. Flash "VENT ROUTE · W/S crawl · follow the lights toward the high hatch."
- **Moving** (L6643-6654):
  - Only W/S counts. `ductTravel += fw · moveSpeed · dt`, clamped to [0, 136.02].
  - Crawl speed is **2.8**, or **3.8** with Shift (L6619), × 1.6 while a chili boost is active.
  - Yaw turns toward the tangent at rate 11. No gravity applies.
  - A full crawl takes about 48.6 s at 2.8, or 35.8 s at 3.8.
- **Leaving** (`leaveDuct`, L8515-8525). Place the player at (clamp(vent.x + 2.8, inside the walls), floor + 0.2, vent.z + 2.4).
- **Duct camera** (L7297-7313, L7398-7402, L7416-7418):
  - Rail-mounted chase camera. The eye sits at `ductPointAt(viewTravel - dir · 1.15) - (0, 0.4, 0)`; the target at `ductPointAt(travel + dir · 2.55) - (0, 0.47, 0)`.
  - `viewTravel` lerps at rate 15. Near plane 0.065, FOV 66.
  - **Over an open hatch**, the camera looks down through the hole at the ward: target = hatch + 4.3 × camera-forward at floor + 0.5.
- **Systems paused while in the duct:**
  - Hospital actors freeze; `updateHospitalActors` returns early (L8766, L11659).
  - Knockback is ignored (L8665-8666).
  - Pounce collision is skipped (L6556).
  - The infection decay rate rises (§6.3).

### 4.6 Overhead hatch and ambush

- **`overheadHatch()`** (L8526-8534) returns the hatch only when all of these hold: in the duct, hatch open, horizontal distance < 2.9 from (-345, 389), and y > floor + 4.
- **Landing marker** (L4213-4252):
  - Ring (inner 0.42, outer 0.54) plus 4 ticks, colour `#eaf5af`, opacity 0.68, drawn on top of everything.
  - Placed at the hatch + 4.0 × camera-forward, at floor + 0.05. It pulses in scale by ±6% at 3 rad/s.
  - It is visible only while `overheadHatch()` is true.
  - The HUD shows "DROP AIM · LEFT CLICK TO POUNCE" (L6588-6591).
- **`dropFromHatch(attack)`** (L8535-8555):
  - Triggered by **Space** (`attack = false`, from `leap` L5924-5926) or by **Left click** (`attack = true`, from `attemptPounce` L6488-6491).
  - Position = (-345, floor + 7.6 - 1.15, 389).
  - Velocity = aim × (7.4 if attacking, else 2.3) horizontally, and -5.7 vertically.
  - **Attack variant:** cooldown 0.86, attack 0.55, **attack window 2.5 s** (the normal pounce gives 0.78), and it snapshots every visible human's alert value. Flash "OVERHEAD AMBUSH! Aim at the ward floor."
  - Plain drop: flash "DROPPING INTO THE TREATMENT WARD".
  - Both variants commit the player to the air.
  - The hatch is directly above bed 6 (world (-345, 388)), so the drop starts **inside bed 6's furniture collider** (7.3 × 11.3, inflated 0.23). `adjustHospitalMovement` then blocks every sub-step on both axes, so the rodent stays pinned at the hatch x/z (-345, 389) and the 7.4 aim velocity never moves it (verifier: replayed L8603-8633 in node; see "Added by verifier").

---

## 5. Hospital cast and AI

### 5.1 Staff (8, fixed, never roam; L4968-5016)

| # | Name | Role | Personality | Start / station (local) | World | Skin / clothing | Prop |
|---|---|---|---|---|---|---|---|
| 0 | Dr. Ellis | doctor | wary | (-14, -21) | (-370, 332) | `#d1a988` / `#e9eee7` | clipboard (L11647) |
| 1 | Nurse Reed | nurse | brave | (2, -6) | (-354, 347) | `#855946` / `#75b0af` | clipboard |
| 2 | Nurse Taylor | nurse | brave | (19, -8) | (-337, 345) | `#d6b192` / `#83ada3` | clipboard |
| 3 | Guard Miller | guard | wary | (-12, -32) | (-368, 321) | `#98715a` / `#4a6772` | cap 0.86 × 0.22 × 0.74 `#2c3d43` |
| 4 | Guard Shaw | guard | brave | (24, -30) | (-332, 323) | `#d8b296` / `#425e69` | cap |
| 5 | Orderly Lane | orderly | brave | (-28, 8) | (-384, 361) | `#ad886f` / `#9dabb3` | stretcher at scale 0.48, 2.1 in front |
| 6 | Orderly Park | orderly | wary | (29, 24) | (-327, 377) | `#8a624d` / `#9da9b1` | stretcher |
| 7 | Ms. Vale | extinguisher | brave | (38, -26) | (-318, 327) | `#c9a184` / `#bc8172` | red extinguisher `#cc3326` |

- Personality rule: `i % 3 ? "brave" : "wary"` (L4990).
- Each `n.speed` is set (guard 2.3, orderly 1.6, others 1.05; L4995), but the hospital update uses its own pace table (§5.4). `n.speed` is effectively unused here (inferred).
- All staff are in `humanoids` with `hospital = true`, so the roaming NPC update and spawn scheduler skip them (L7015, L4927-4948).

### 5.2 Patients (8; L5017-5045)

- **Names:** Margie, Bernard, Lydia, Walter, Camille, Edgar, Joyce, Toby.
- **Appearance.** Skin cycles `#dbb795`, `#b68a6b`, `#9c6d55`. Clothing cycles `#c99c83`, `#8f99af`, `#a9b793`. Each wears a white wrist wrap.
- **Personality** "panic". Speed field 0.68 (unused).
- **Station** = (bed.x, floor, bed.z - 6.35), at the foot of the bed (see the table in §2.3).
- **Circuit** (L8750-8763), with `dir = i % 2 ? 1 : -1`: station → station + (dir · 2.6, 0, -0.65) → station + (dir · 2.1, 0, -2.8) → station + (0, 0, -2.0). The starting index is `i % 4`. The initial pause is 0.4 + (i % 3) · 0.3.

### 5.3 Patrol circuits and partition routing

**Staff circuits** (L8693-8749). Each list holds local (x, z) points walked in a loop. Staff member `i` takes circuit `i`.

| Staff | Circuit (local) | Area |
|---|---|---|
| 0 Dr. Ellis | (-14, -21) → (-7, -22) → (-7, -28) → (-14, -29) | waiting, west of centre |
| 1 Nurse Reed | (2, -6) → (5, -10) → (-4, -10) → (-5, -6) | reception centre |
| 2 Nurse Taylor | (19, -8) → (18, -4) → (18, 0) → (24, -4) | check-in desk |
| 3 Guard Miller | (-12, -32) → (-7, -37) → (-1, -35) → (-3, -27) | entry lobby |
| 4 Guard Shaw | (24, -30) → (29, -31) → (34, -35) → (26, -37) | east triage alcove |
| 5 Orderly Lane | (-28, 8) → (-24, 9) → (-23, 17) → (-27, 18) | west ward, bays 1-2 |
| 6 Orderly Park | (29, 24) → (25, 23) → (25, 30) → (28, 32) | east ward, bays 7-8 |
| 7 Ms. Vale | (38, -26) → (37, -24) → (41, -24) → (41, -33) | east triage alcove |

- Initial pause is (i % 3) · 0.35. Pause at each waypoint: 0.24 for staff, 0.48 for patients (L8786).
- **`hospitalPatrolTarget(from, to)`** (L8679-8690) inserts one intermediate waypoint per frame. All z values are local to `HOSP_Z`:
  1. If from.z < -24 **and** \|from.x\| > 22 **and** \|to.x\| < 20: go to (from.x, -20) first, leaving the side alcove around the end of its partition.
  2. Else, if the move crosses the z = -12 divider (from.z < -12.5 and to.z > -11.5, or the reverse):
     - if \|from.x\| > 10, go to (0, -16) when coming from the south, or (0, -8) when coming from the north;
     - otherwise go to (0, -10) or (0, -14) respectively.
  3. Else go straight to the target.

### 5.4 `updateHospitalActors(dt)` state machine (L8765-8846)

**Run conditions** (L9049-9050, L9039):

- dt is capped at 0.08;
- the player is **not** in the duct;
- the player is inside the hospital, **or** within 150 horizontally of the hospital centre.

**Per actor, every frame:**

- Skip actors flagged `injured`.
- `nextBite` and `hitCooldown` count down.
- `isDefender` = role ∈ {guard, orderly, extinguisher}.

**Movement state:**

- **PURSUE** while the player is inside **and** the actor is a defender **and** the distance is < 15. Target = the player's (x, z) at floor height.
- **PATROL** otherwise. Follow the circuit and wait out the pause at each waypoint.
- Each step moves toward `hospitalPatrolTarget(pos, target)` by min(dist, dt · pace). Only stop when within 0.18, or while paused and not pursuing. Yaw faces the motion.
- **Pace table:**

  | Situation | Pace |
  |---|---|
  | Pursuing, guard | 3.9 |
  | Pursuing, orderly or extinguisher | 2.7 |
  | Patrolling patient | 1.15 |
  | Patrolling orderly | 1.85 |
  | Patrolling doctor, nurse or guard | 1.62 |

- y is pinned to `HOSPITAL_FLOOR`.
- **Animation.** Stride phase grows by dt × (6.1 for a walking patient, 8.3 for walking staff, 3.0 when idle). Legs swing ±0.42, arms ±0.28, plus a small head sway.

**Defender attack sub-machine** (only when the player is inside, the actor is a defender and `hitCooldown ≤ 0`):

- **READY → TELEGRAPH.** Triggers when `telegraph ≤ 0` and the distance is < 7.2 (orderly) or < 4 (guard, extinguisher). Telegraph lasts **1.0 s** for an orderly and **0.76 s** otherwise. The right arm raises to -1.55. Flash text:
  - orderly: "Stretcher rail shoves forward — get clear!"
  - extinguisher: "The woman winds up the fire extinguisher!"
  - guard: "Security guard lunges — dodge!"
- **TELEGRAPH → STRIKE**, when the telegraph runs out:
  - Set `hitCooldown = 6`.
  - If the distance is < 3.6 (orderly) or < 2.45 (others), call `knockPlayer(dir, 10.8, msg)`. Messages: "STRETCHER CHARGE! …", "CLANG! The extinguisher sent you rolling.", "SECURITY! The guard grabbed you."
- **`knockPlayer`** (L8665-8677):
  - Does nothing while in the duct or dead.
  - Horizontal velocity = dir × 10.8. Vertical = min(3, 10.8 × 0.22) = 2.376.
  - Clears the rail and the attack window. Commits the player to the air with `cameraCommit` 0.38.
  - **It does no damage and costs no Power.** Hospital staff cannot kill or hurt the rodent in v5.4.
- Doctors, nurses and patients never attack.

**Charting wrapper** (L11656-11677), which runs after the base update:

- A nurse or doctor who is idle (pause > 0.07) and in the "charting" phase, `sin(time · 0.23 + i · 4.4) > 0.15`, tilts the clipboard -0.33, looks down, and raises an arm.
- Idle patients turn their heads.

**Ambulance siren link.** Any hospital actor in telegraph raises the legacy ambulance's "high priority" flag, which ducks the siren beep (L9033-9036).

### 5.5 Biting hospital occupants

- Pounce collision includes hospital actors (L6556-6565). Pounce resolution is owned by Combat.
- **Hospital actors are immune for 14 s** after each bite (`nextBite = 14`, L8640; skip rule `n.hospital && n.nextBite > 0`, L6558).
- **Alert trap (inferred).**
  - Hospital actors never pass through `updateHumans`, so their `alert` never decays.
  - Any pounce outcome sets `alert = 7` (L6539, L6546).
  - The first bite on each occupant therefore succeeds at the ordinary unaware rate of 95.5%. Every later attempt on the same occupant runs at the "already alert" rate of 3.5%, except for a perfect counter (L6513-6518).
- A hospital-actor bite **does not** create a crime scene, call medics or roll police: `onSuccessfulBite` returns early on `hospitalRole` (L9276).
- The bite still counts toward infection and the win condition (§6).

---

## 6. Infection model

### 6.1 State (L8413-8419)

| Variable | Meaning | Initial |
|---|---|---|
| `infectionOwn` | Infection from the rodent's own bites, 0 to 100 | 0 |
| `infectionFromSquirrels` | Share from converted normal squirrels, 0 to 25 | 0 |
| `infectionDisplayed` | Last drawn value | 0 |
| `secondsSinceBite` | Seconds since the last infecting bite | 1e6 |
| `won` | Hidden-win latch | false |
| `bittenStaff`, `bittenPatients` | Sets of hospital actor `idx` ever bitten | empty |

`infectionReading() = clamp(infectionOwn + infectionFromSquirrels, 0, 100)` (L8458).

### 6.2 Bite increments (`grantInfectionBite(n)`, L8634-8644)

| Target | Increment to `infectionOwn` | Side effects |
|---|---|---|
| Hospital patient | +5.7 | add to `bittenPatients`; patient immune 14 s |
| Hospital staff (any role) | +6.2 | add to `bittenStaff`; immune 14 s |
| Ordinary human (pedestrian, cyclist, motorcyclist, etc.) | +3.6 | — (Combat and §7 handle the crime scene) |
| Police officer (any, via `tryPolicePounce` → `grantInfectionBite({})`) | +3.6 | officer stunned (§8.6) |
| Normal squirrel | +0 to `infectionOwn` | converts the squirrel (§6.4); `secondsSinceBite = 0` |

Every call sets `secondsSinceBite = 0`, caps `infectionOwn` at 100, redraws the meter and runs `checkUnannouncedEnd()`.

### 6.3 Decay and the per-frame update (`updateInfection(dt)`, L8849-8866)

It runs every gameplay frame, everywhere (hospital, sewer, outdoors), with dt = min(real dt, 0.2).

1. `secondsSinceBite += dt`.
2. `infectionOwn = max(0, infectionOwn - dt · rate)`. The rate is **0.011/s** normally (0.66 per minute) and **0.05/s while in the duct** (3.0 per minute). Hiding in the duct costs infection.
3. Recompute the squirrel share (§6.4).
4. `drawInfection()` and `checkUnannouncedEnd()`.

### 6.4 Normal squirrels as infection carriers (L5060-5101, L8855-8863, L8957-8976)

**The seven squirrels:**

- Hide anchors: (-74, -71), (84, 70), (-196, 97), (217, -111), (-105, 321), (103, 409), (414, 332).
- Fur colours: `#b78453`, `#9a6b47`, `#b19b7b`, `#675e4d`, `#a48c68`, `#8c7463`, `#c19c66`.
- Each wanders in a Lissajous pattern around its anchor (amplitude 8; 6 once infected) at 1.0 phase rate (1.3 once infected) (L8899-8917).

**Conversion** (`tryWildlifePounce`):

- **Conditions:** an active attack window, not in the sewer or hospital, an uninfected squirrel within 1.42, and no rabbit hit first.
- **Effects:**
  - `infected = true`, `progress = 0`.
  - Torso material swapped to `mat("#83544d")`. The first non-torso child (the head) has its material colour set to `#a67860`. That material is the squirrel's cached `mat(fur)`, shared by head, ears, tail and paws, so the whole fur turns `#a67860`.
  - Rewards: +90 Power, +1 bite, +10 Squirrel Coins.
  - `secondsSinceBite = 0`.
  - Flash "ANOTHER SQUIRREL TURNS! +90 Power · +10 Coins".

**Maturation**, per infected squirrel each frame:

- `canAdvance = infectionOwn ≥ 25 AND secondsSinceBite < 600`.
- If `canAdvance`: `progress = min(1500, progress + dt)`. 1500 s is 25 minutes of qualifying play.
- `portion = min(progress / 1500, infectionOwn ≥ 25 ? 1 : 0.92)`.
- `component = (25 / 7) · portion` (at most 3.5714 per squirrel).

**Total:** `infectionFromSquirrels = min(25, Σ component)`.

**Consequences:**

- Squirrels add nothing until the rodent's own infection reaches 25% **and** it keeps biting at least once every 10 minutes.
- If the rodent's own infection drops below 25%, each squirrel's portion is capped at 0.92 of **full** maturity (at most 3.29 points per squirrel). A squirrel below 92% maturity loses nothing. Progress never decays.
- At most 25 points come from squirrels.

### 6.5 Display (L8461-8466; shell L35-36, L135)

- The HUD stat "INFECTION" shows `reading.toFixed(1) + "%"`. A fill bar uses width = reading% and colour `#e6b265`.
- It is drawn once at boot (L16059) and then every frame.

### 6.6 Hidden win condition (`checkUnannouncedEnd`, L8645-8664)

It is checked after every infecting bite and every frame. The rodent wins only when **all** of these hold:

- `!won`, the player is alive, and `infectionReading() ≥ 50`;
- `bittenStaff.size ≥ ceil(8 / 2) = 4`;
- `bittenPatients.size ≥ ceil(8 / 2) = 4`.

On a win: `won = true`, the player is set not alive, play stops, and the overlay title reads **"THE CITY IS YOURS"**. Text: "The town is changing. You found a path nobody told you about. Power N · M bites." Restart reloads the page (L7869).

**Arithmetic.** Biting exactly 4 staff and 4 patients gives 4 × 6.2 + 4 × 5.7 = 47.6, so about one more ordinary bite reaches 50 (allowing for decay). The path is intentionally undocumented.

### 6.7 Visual infection of bitten humans

- Every human built by `makeHuman` carries two hidden red emissive eyes (`#4b0a0a`, emissive `#7e1111`, intensity 0) (L4655-4670).
- A crime-scene victim still waiting at the scene, not yet picked up, after **120 s** gets visible red eyes at emissive 0.55 (L9331-9335).
- Treatment hides the eyes again (L10554-10558).
- **Infected humans have no other per-person state.** The "town infection" is the abstract `infectionReading`, not a count of infected people.

---

## 7. Crime scenes and the medical response

### 7.1 Trigger chain (bite on an ordinary human)

The live wrapper chain is: L10337 → L9272 → L7996.

`onSuccessfulBite(n)`:

1. **v0.7 core** (L7996-8002): if the victim was winding up a kick, cancel it and set `kickCooldown = 12`.
2. **v1.2 wrapper** (L9272-9286):
   - Return early for a hospital occupant.
   - Crash an active motorcycle.
   - Topple a bicycle prop.
   - `scheduleCrimeScene(n)`.
   - `alarmNearbyWitnesses(n)`.
3. **Westside wrapper** (L10337-10344): count bites near the old gas station. That belongs to another subsystem.

**`scheduleCrimeScene(victim)`** (L9198-9226):

- Ignored if the victim already has a hot scene.
- **Victim:** `injured = true`, `hospital = true` (removes it from roaming), `injuredTimer = 0`, `alert = 12`, `state = "injured"`, `speed = 0`. Sits down: legs -1.25 rad.
  - `recoverAt = 120` is set but never read (dead field).
- **Scene object:** `{victim, center, radius: 72, ttl: 600, boosted: false, stage}`, where `stage = nearestRoadStage(victim position)`.
- **Calls:** `queueMedicalResponse(victim, stage)`, `gatherAtCrime(scene)` (2 to 4 bystanders from a pool of 7, L9684-9742), then `rollIncidentPolice(scene)` (§8.4).

**`alarmNearbyWitnesses`** (L9227-9270). Belongs to the community/combat subsystems; summarised here:

- Applies to visible, non-hospital, uninjured humans within 25.
- Up to 2 become defenders: brave, or wary with list index < 4 and `idx % 5 == 0`. Defenders hold 19 s with `kickCooldown` 0.3 + i · 0.36.
- The rest flee at 7.1 (8.2 for cyclists). The first 3 retreat home.
- Everyone gets `witnessUntil = time + 70`.

**`updateCrimeScenes(dt)`** (L9287-9350), every frame from `updateNewSystems`:

- `ttl -= dt`.
- **First frame only:** every visible non-hospital human within 72 gets alert ≥ 7, switches from walk to flee, and reacting ≥ 2.2.
- If the patrol officer is out and within 36 of the scene centre: `copState.alert = max(alert, 6.5)`.
- **Victim not yet picked up:**
  - pinned to the scene origin;
  - groans every 12 to 21 s ("Ow! My knee!" and similar);
  - red eyes at ≥ 120 s;
  - faces the rodent;
  - humans within 20 get alert ≥ 4.
- Remove the scene at ttl ≤ 0.
- Then call `updateMedicalResponders(dt)`.

### 7.2 Road staging (`nearestRoadStage`, L9166-9197)

The function picks the nearest point on a road centreline from a district-dependent segment list:

| Victim x | Segments (axis = the axis the road runs along; coord = its fixed coordinate) |
|---|---|
| x < -257 (westside) | road along z at x = -289, z -239 to 267; road along x at z = -179, x -299 to -176 |
| x > 267 (commercial) | road along z at x = 347, z -213 to 218; road along x at z = 0, x 247 to 680 |
| otherwise (old town) | roads along z at x = -180, 0, 178; roads along x at z = 0, 171, -174, -305 (each with its own limits) |

The result is `{axis, coord, lo, hi, stop: pathPoint(clamped), distance}`. `pathPoint(x, z)` = (x, terrain + 0.13, z) (L10444).

### 7.3 Responder fleet (L9148-9164, L10512-10537, L10674-10717)

- **3 responder ambulances**, built by `makeResponderAmbulance()` at (HOSP_X, 283), hidden and idle.
  - Base car via `makeCar`: scale 0.79, body 2.75 × 5.1, colour `#f4f0ea`.
  - White box body 2.5 × 0.8 × 3.15. Red side stripes `#b42c28` and `#be332f`.
  - Roof bars: red `#cf382f` at x -0.48 and blue `hospitalBlue` at x +0.48. These two are the `flashBars`.
- **Each ambulance's team** (`medicalTeams`):
  - **First medic:** white shirt `#f4f1e7`, pants `#4b637a`, skin `#bd9377`, red trauma pouch `#a23735`.
  - **Second medic:** shirt `#e2f0e9` for team 1, `#e9e9df` otherwise. Red badge `#ca5449`. Skin `#c39a78`, `#b98765` or `#966b58` by team.
  - **Receiver nurse:** scrubs `#73aca3`, clipboard `#b69d78`. Waits inside the hospital.
  - **Kit bag:** `#a74237`.
  - **Stretcher:** 2.0 × 0.8, frame `#c9d0cc`, mattress `#708694`, 4 wheels.
  - **Speaker names:** "Paramedic Lee", "Paramedic Quinn", "Paramedic Morgan" (idx 87 to 89, brave).
- **`medicalHome`** = (-356, terrain + 0.1, 295), the hospital driveway (L10443).

### 7.4 Routing helpers

- **`makeRoadTrip(dest)`** (L10447-10470). Builds an axis-aligned road polyline:
  - Always start medicalHome → (-356, 283) → (-289, 283).
  - If dest.x < -255: → (-289, dest.z) → dest.
  - Else: → (-289, -179) → (-180, -179), then:
    - if \|dest.x + 180\| < 4: → (-180, dest.z);
    - else if dest.z < -240: → (-180, -174) → (0, -174) → (0, -305);
    - else: pick `crossZ` from {-174, 171, 0} by the rule in the code; `junctionX` = 347 if dest.x > 267, else dest.x; then → (-180, crossZ) → (junctionX, crossZ) → (junctionX, dest.z).
  - Finally → dest.
  - Consecutive points closer than 0.35 are deduplicated.
- **`advanceVehicleRoute(vehicle, ud, dt, speed, reverse)`** (L10494-10511). Constant-speed waypoint follower. A waypoint counts as reached within 0.7. Yaw faces motion; y = terrain + 0.1. Returns true at the end, or at the start when reversing.
- **`medicalWalkRoute(from, to)`** (L10603-10653). Building-avoiding walking path, reused by police and the novelty cast:
  1. Obstacles = `houses ∪ commercialBounds` (cached; L10568). The segment-blocked test is a Liang-Barsky clip against each box inflated by 0.92 (L10576-10602).
  2. If the straight line is clear, return [from, to].
  3. Otherwise take up to 18 buildings whose centre lies within max(w, d)/2 + 11 of the segment. Add 4 corner nodes per building at ±(w/2 + 2.65, d/2 + 2.65).
  4. Run O(n²) Dijkstra over the visibility graph (edges must not be blocked). If there is no path, fall back to the straight line.
- **`medicalWalkPoint(points, t)`** parametrises by arc length.
- **`keepEmergencyActorsOutside(pos, prev)`** (L12074-12095) does per-axis rollback against houses (pad 0.65) and commercial bounds (pad 0.6). Used by the patrol officer, incident officers and bystanders.

### 7.5 Responder ambulance state machine (`updateMedicalResponders`, L10805-10989)

| State | Entry / behaviour | Exit |
|---|---|---|
| `idle` | hidden, parked | `queueMedicalResponse` takes the first idle ambulance |
| `waiting` | `wait = 9 + rand · 10` (9 to 19 s); `responseStyle = floor(rand · 3)` ∈ {0, 1, 2}; route = `makeRoadTrip(stage.stop)` | wait ≤ 0 → show at medicalHome → `outbound` |
| `outbound` | drive the route at **24** (27 if style 2) | end of route → build the walk path from (ambulance + (2, 0, 0)) to the victim; `walkTime = clamp(len / 3.45, 3, 55)`; show both medics and the stretcher → `approach` |
| `approach` | `t = elapsed / walkTime`; crew placed around the stretcher (`placeSceneCrew`: first medic 0.8 ahead / 0.92 right, second 0.75 behind / 0.88 left). Style 1: the first medic walks ahead at t + 0.19. | t ≥ 1 → kit appears beside the victim; arrival line ("We are here. Give us some room, please." etc., only if the player is within 45) → `assess` |
| `assess` | duration 2.1 (style 2), 5.0 (style 1), 3.3 (style 0); first medic crouches | → `load` |
| `load` | duration 2.15 (style 2) or 3.25; victim lerps onto the trolley (+0.68 y) and rotates to lying (π/2) | → `retrieve` |
| `retrieve` | walk back along the path over `walkTime`, victim riding | t ≤ 0 → victim hidden with `medicalTransit = true`; crew hidden; leg = route length - 2 → `return` |
| `return` | drive the route in reverse at **25** | → `hospitalQueue` |
| `hospitalQueue` | park at medicalHome + ((team - 1) · 6.5, 0, team · 2.2) | no other ambulance in receive/admit/handoff/sendoff → `beginHospitalHandoff` |
| `receive` | handoff setup (L10781): laneX = -356 + (team - 1) · 3.4; ambulance parked at medicalHome.x + (team - 1) · 5.9; dock = (laneX, 294); receiver starts inside at (laneX - 1.7, floor + 0.1, 312); door hold ≥ 8, then ≥ 1.5 per frame. Receiver walks to the dock over **3.2 s**. | → arrival line "Patient arriving at emergency intake." etc. → `admit` |
| `admit` | **8.0 s** smoothstep: stretcher dock → (laneX, floor + 0.12, 328) (local z -25, entry lobby); crew flank it; door hold ≥ 2.0 | → `handoff` |
| `handoff` | **5.5 s** of idle gestures; door hold ≥ 1.8 | `finishTreatment(victim)` → `sendoff` |
| `sendoff` | **7.0 s**: empty stretcher back to the dock | everything hidden; userData reset → `idle` |

- **Queue overflow.** With no idle ambulance, the victim is flagged `queuedMedical` and keeps its stage. Each frame any queued, still-injured victim with no assigned ambulance is re-queued once an ambulance is idle (L10980-10988).
- **Handoff serialisation.** Only one ambulance at a time can be in receive/admit/handoff/sendoff. The rest wait in `hospitalQueue`.
- **Hospital-side time per patient.** 3.2 + 8 + 5.5 + 7 = 23.7 s.

**`finishTreatment(n)`** (L10538-10563) is the "cure":

- Hide the victim.
- Clear `sceneHot`, `injured`, `medicalTriage`, `medicalPickup` and `medicalTransit`.
- Reset the pose and bike. Hide the red eyes.
- `hospital = Boolean(hospitalRole || motorcycle || sceneAssignment !== undefined)`, which is false for normal pedestrians.
- `timeAway = 0`, `maxLife = R(24, 55)`, `witnessUntil = 0`.
- The ordinary spawn scheduler can then re-use the person (inferred from `manageNpcSpawns` L4925-4962 picking invisible non-hospital NPCs).
- **The cure does not reduce `infectionOwn`.** The code comment at L8847 says treatment "is independent of the player's victims".

### 7.6 Legacy ambulance loop (decorative; model L8979-8989, `updateAmbulance` L8990-9038)

- One extra ambulance, created by `makeCar(629, 283, …)`. It runs only while the player is outdoors (L15956).
- **States:**
  1. `waiting`: 18 s at boot, then 145 s per cycle.
  2. `arterial`: appears at (639, 283) and drives -x at **12.5**. It stops while any visible non-hospital human is within 5.
  3. `turn` at x = -356: drives +z at 10.625.
  4. `park` at z = 295 for 16 s.
  5. Back to `waiting`, hidden.
- **Siren:** a 430 Hz sine blip every 1.45 s except while parked. Volume 0.018, or 0.001 when a kick or hospital telegraph is active, or `predatorWarning` is set.
- It never carries a patient.

### 7.7 Emergency beacons (`updateEmergencyBeacons`, L12096-12128; called from `updateScenery` L15977)

- Vehicles with beacons: the 3 responder ambulances (red `0xdc2929`, blue `0x276ac2`) and the 2 incident police cars (blue `0x426fd7`, red `0xe84539`).
- `phase = floor(time · 4.7) % 2`. The lamp whose index matches the phase shows emissive **2.6**; others **0.13**. Lamps are lit only while the vehicle is visible.
- Result: about 4.7 toggles per second, alternating red and blue.
- **No beacons** on the patrol car, the legacy ambulance, or the two parked station cars.

---

## 8. Police

### 8.1 Police station (westside; L10049-10077, L11224, L12140-12153)

**Site and shell:**

- Centre (-510, -107), `stationY = 0.10`. The front faces **+Z**.
- Slab 46 × 31. Side walls at x ±22.7. Back wall at z -15.2.
- Front walls: two 12-wide segments at x ±17, z 15.3. All walls 8.8 high, colour `#89979d`.
- Roof 48 × 33 at 9.25, `#344852`.
- Sign "WEST TOPEKA POLICE" at z 15.7. Reception desk 13 × 2 × 2.2 at local (0, -5).
- Glass door panel at z 15.4. **Two swinging door leaves** (hinges at x ±2.25, z 15.5, each 2.18 × 3.35); they open to 1.25 rad for the novelty cast only.

**Parking:** two pads 9 × 15 at (-525, -81) and (-495, -81), each with a parked cruiser (`#d5dcdb`, blue `#274c77` / red `#a32b32` bars). These are static.

**Roof route:** "police roof", kind `roof`, at y = stationY + 9.7, from (-527, -107) via (-510, -107) to (-493, -107) (L10073-10077).

**Not enterable.** The station is pushed to `commercialBounds` (45.8 × 30.8, roof y = stationY + 9.25) and is guarded (§8.5). Key points:

- `stationWelcome` (-510, -86.5);
- `stationThreshold` (-510, -92.1);
- `stationInner` (-510, -98.2);
- reinforcement entrance points (-512 / -508, -88).

### 8.2 Police AI bodies and vehicles (inventory)

| Group | Count | Model / colours | Created | Visible when |
|---|---|---|---|---|
| Patrol officer (`officer`, `copState`) | 1 | torso 0.78 × 1.5 × 0.52 `#324b70`, head r 0.34 `#c99870`, cap `#202c41`, badge `#e6c46f`, baton `#45403e`. About 3.4 tall, taller than an ordinary human (about 2.1). | L7981-7995 | dispatched |
| Patrol car | 1 | `makeCar(95, -5.6, "#e0e6de")`, blue bar `#274a79`, red `#cf312d` | L7976-7980 | always |
| Incident officers | 3 | torso `#3b5274`, head `#b99377`, cap `#242d3b`, baton `#353c42` | L10999-11009 | incident in `patrol` phase |
| Incident cars | 2 | `#e4e8e5`, bar `#2e4d83`, box `#b53632`; beacons | L10992-10998 | incident active |
| Station reinforcements | 2 | torso `#354f72`, cap `#202b3a` | L11211-11222 | rodent within 40 of the station |
| Precinct officers | 2 | torso `#345070`, cap `#344852` | L10079-10093 | always |
| Parked station cruisers | 2 | static | L10065-10072 | always |

That is **8 officer bodies and 5 cars**.

### 8.3 Patrol officer state machine (`dispatchCop` L8003, `updateCop` L8026-8080)

`updateCop` runs from `updateNewSystems` only when the player is **not** in the hospital, and returns immediately in the sewer.

**PATROLLING** (`copState.out = false`):

- The patrol car shuttles along z = -5.6 between x 55 and 645 at **10.5**, flipping direction and yaw at each end. About 56 s each way. Officer hidden.
- The car is kinematic and teleportable. After `startIncidentPolice` or `sendPosterPolice` teleports it, it resumes shuttling on whatever z it was given (inferred quirk: it can drive off-road).

**DISPATCHED**, via `dispatchCop(reason)`:

- Ignored if the officer is already out.
- `out = true`, `alert = 23`. The officer appears at patrol car + (0, 0, 3.4) at terrain height.
- Flash "POLICE OFFICER! {reason} · Baton only."

**Dispatch sources:**

| Source | Line | Effect |
|---|---|---|
| Single-officer incident (18% of crime scenes) | L11019-11025 | car teleported to scene + (12, 7); `alert ≥ 43` |
| Poster witness | L11045-11049 | car teleported to witness + (17, 12); `alert ≥ 52` |
| Novelty-cast child cyclist reaches the station door | L12474-12477 | dispatch at the car's current position |

**Per frame while out:**

- `alert`, `hitCooldown` and `stun` decay at 1/s.
- `canEngage` = not in the sewer, not in a house interior, **and** (player y - officer y) < 2.4. The rodent is safe high in a tree or on a roof.
- **STUNNED** (`stun > 0`): no movement and no swing.
- **WINDUP** (`windup > 0`, starting at **0.54 s**), on expiry:
  - `hitCooldown = 2.0`.
  - If `canEngage` and distance < 2.85: `officerBatonContact(officerPos, 14)` and flash "POLICE BATON! …".
  - Else if distance < 6: "The officer swung and missed."
- **CHASE** when alert > 0, `canEngage`, and 2.55 < distance < 86. Move min(dist - 2.5, dt · **6.15**) toward the rodent with building rollback.
- **Start a windup** when alert > 0, `canEngage`, distance < 3.6 and `hitCooldown ≤ 0`. Flash "The officer raises a baton — jump or retreat!"
- **STAND DOWN** when alert ≤ 0 or distance > 155: `out = false`, officer hidden.
- **Re-alert sources while out:** a crime scene within 36 (alert ≥ 6.5); a surprise bite on the officer (alert ≥ 30).

**`officerBatonContact(p, knock)`** (L8012-8024), shared with civilian kicks:

- Knock the rodent away from p: horizontal speed `knock`, vertical ≥ 3.1.
- Clear the rail and set airborne.
- **Power -19** (floored at 0). Sound.
- **No health damage and no death.**

### 8.4 Incident police (`rollIncidentPolice` L11011, `startIncidentPolice` L11019, `updatePoliceResponse` L11050)

**Roll per crime scene** (`Math.random()`):

- < **0.05** (`INCIDENT_MULTI_POLICE`): two cars and three officers.
- < 0.05 + **0.18** (`INCIDENT_SINGLE_POLICE`): single patrol officer (§8.3).
- Otherwise (77%): no police.

**Multi-officer incident** (ignored while another incident is not yet departing):

- **Cars** start at (station.x ± 15, station.z + 26).
- **Route:** start → (-300, station.z + 26) → (-300, scene.z + 10) → (scene.x ± 9, scene.z + 10).
- **Phases:**
  - `arrive`: both cars drive at **23**. When both arrive, the 3 officers appear at car (j % 2) + ((j - 1) · 1.6, 0, 1.8) with `hitCooldown` 1.0 + 0.5 · j.
  - `patrol`: lasts **48 s**.
  - `depart`: officers hidden, cars reverse the route at 23. On arrival the incident is removed and the cars hidden.

**Officer behaviour during `patrol`:**

- **STUNNED** → skip.
- **INVESTIGATE** when the rodent is > 27 away, or in the hospital, sewer or a house interior:
  - Walk to scene centre + offset by slot: (-3, 1), (5, -4), (-6, -7).
  - Path via `medicalWalkRoute` at 2.3 (slot 0) or 1.9.
  - Baton poses: slot 0 examines, slot 1 holds the crowd back, slot 2 keeps watch.
- **CHASE** otherwise: move at **5.5** toward the rodent while distance > 2.0, with building rollback, facing it.
- **Windup:** starts at **0.48 s** when distance < 3.4, (rodent y - officer y) < 2.4, `hitCooldown ≤ 0` and not stunned. On expiry: `hitCooldown = 2.4`; hit if distance < 2.9 and dy < 2.3 via `officerBatonContact(p, 12)`.

### 8.5 Station guards

**Station reinforcements** (L11159-11187), 2 officers. Active (visible) while the rodent is within **40** of the station centre and not in the sewer.

- `t` accumulates (cap 10).
- For the first 2 s they lerp to the entrance points (station.x ∓ 2, station.z + 19).
- After that, if the rodent is within 24 of the station: chase at **4** when 2 < distance < 34.
- **Shove** when distance < 2.3 and dy < 2.3: cooldown **4.4**, horizontal 10, vertical 2.3, no Power loss. Flash "More officers emerge from the station — retreat!" Code quirk: when 2 < distance < 2.3 the chase step has already normalised `delta` in place, so the push is `delta / dist · 10`, about 4.3 to 5 instead of 10 (L11174-11183). The `hitCooldown` only counts down inside the `stationDistance < 24` branch.
- Inactive → hidden and `t` reset.

**Precinct officers** (L10309-10314, L11189-11209), 2 officers circling (-517, -79) and (-499, -83) on radius 3 at 0.21 rad/s (in `updateWestside`).

- When the rodent is within **34** of the station: step toward it at **3.3** when 2 < distance < 30.
- **Shove** when distance < 2.3 and dy < 2.4: cooldown **4.1**, horizontal 11, vertical 2.4. Flash "Police station security! The officers will not let you inside."
- **Inferred behaviour:** `updateWestside` runs before `updatePoliceResponse` and resets their position onto the circle every frame. In practice they are tethered within about 3 units of their posts and only lunge one frame-step.

### 8.6 Biting police (`tryPolicePounce`, L8083-8135)

**When it runs:** from `updatePounceCollision` after the human check, while the attack window is open. Never in the sewer, hospital or a house interior.

**Candidates:** the patrol officer (if out and visible), visible incident officers, visible station reinforcements, and the precinct officers (always visible).

**Geometry gate:** horizontal distance ≤ 1.85 and dy ∈ [-0.3, 2.8].

**Hit chance:**

- `surprised` = the rodent is **behind** the officer (dot(officer forward, officer → rodent) < -0.3), **or** dy > 1.35 (dropping from above), **or** the officer is already stunned.
- Chance = **0.88** if surprised, otherwise **0.035**.

**Success:**

- Officer: `stun = 5.5`, windup cleared, `hitCooldown = 6`. The patrol officer's alert rises to ≥ 30.
- Rodent: Power +130, bites +1, coins +10, infection +3.6.
- The rodent's velocity is scaled by 0.14 with vertical 2.6.
- Flash "SURPRISE BITE! {name} stunned — escape before backup arrives."

**Failure:**

- The rodent is bounced away from the officer at horizontal 8, vertical 3.2.
- Flash "{name} anticipated your attack!"

Either way the attack window closes. **Officers are never infected, injured or removed.** Biting one creates no crime scene.

### 8.7 Wanted posters and poster witnesses

**Placement** (L11266-11277):

- On every 7th utility support, starting at index 6 (indices 6, 13, 20, …, up to `utilitySupports.length` at that point in the build).
- Panel 1.3 × 1.79, offset (+0.38, terrain + 2.45, +0.23) from the pole, with a dark backing.
- The exact count depends on the pole subsystem; see Open questions.

**Texture** (L11227-11263): canvas 320 × 424, parchment `#e6dcc3`, border `#6b5143`. Text "WANTED / DANGEROUS / SQUIRREL / REPORT ALL SIGHTINGS" in `#47322a`, around a squirrel silhouette with a red eye `#bd3f2c`.

**Visibility** (`updatePosterAwareness`, L11278-11284): `player.hits > 8`, i.e. from the 9th successful bite. The code comments disagree ("15" at L11226, "NINE" at L11265); the code uses > 8.

**Poster witnesses** (inside `updateHumans`, L7053-7067). Applies to roaming pedestrians only, not hospital, police or special cast. Rules:

1. **Reading.** If hits > 8 and the NPC is within 10 of any poster, and has not read one in the last 90 s: `wantedSawAt = time`, `wantedCalled = false`.
2. **Recognising.** Within 90 s of reading, if the NPC `spotted` the rodent, the distance is < 25.5, and it has not yet called:
   - `wantedCalled = true`;
   - `witnessUntil = time + 600`, which sets the detection `radar` multiplier to 3 for 10 minutes (L7046-7047). Sight range becomes min(20, 14.5 × 3) = 20, up from 14.5, so the effective gain is about 1.4×;
   - speech bubble "That is the squirrel from that poster!";
   - `sendPosterPolice(npc position)`.
3. `spotted` comes from the detection model owned by the pedestrian/combat subsystem, capped at 20 for sight. Noise is capped at 16 in the formula, but `noise` itself already requires distance < 8.6 (L7033). The 25.5 limit therefore never binds.
4. **Dead code.** `speakWantedRecognition` (L11286-11305) has **no callers**. It was a Web Speech TTS variant that rotated three voices (pitch 1.15, 0.77, 1.65). Only the text bubble is live.

`WITNESS_MEMORY_SECONDS = 600` is declared (L10442) but unused; the literal 600 is used instead.

---

## 9. Frame scheduling and gating (L15940-15983)

1. `beginTrafficFrame`: fatal traffic is **disabled while the player is in the hospital, sewer or duct** (L15774).
2. `updatePlayer` sub-steps, which include the duct and hospital movement paths and pounce resolution → `tryPolicePounce`.
3. If the player is not in the sewer and not in the hospital: pedestrians (they hold the poster-witness logic), cars, the legacy ambulance, and others.
4. **Always:** `updateInfection` (real dt ≤ 0.2) and `updateHospital` (real dt ≤ 0.2; it gates staff by the 150 radius and the duct).
5. `updateNewSystems` (always): `updateCop` (skipped in the hospital), then `updateCrimeScenes` → `updateMedicalResponders`, motorcycles, bystanders.
6. `updateWestside`: `updateHospitalDoors`, precinct circling.
7. `updatePosterAwareness`, then `updatePoliceResponse`.
8. `finishTrafficFrame`: swept collision. **Every `makeCar` vehicle is in `cars[]` and therefore in `trafficFleet`** (L15761-15771). That includes the patrol car, incident cars, responder ambulances, the legacy ambulance and the parked cruisers, so **emergency vehicles can run the rodent over** (game over "RUN OVER"). `finishTrafficFrame` (L15870-15897) only tests vehicles that were visible at both ends of the frame and moved more than 1e-5 but no more than max(12, dt · 80 + 2). The static parked cruisers therefore never kill, and teleports (such as `startIncidentPolice` moving the patrol car) are ignored.

Each optional subsystem is wrapped in `updateOptional`. An exception disables only that subsystem and flashes a message (L15932-15939).

---

## 10. Interactions with other subsystems

| Other subsystem | Interaction |
|---|---|
| **Combat / bite** (pounce, `resolvePounce`, kicks, `handleKickWindup`) | Provides `onSuccessfulBite` and `grantInfectionBite` calls. `officerBatonContact` is reused by civilian kicks (L8161). The hatch drop gives a 2.5 s attack window. Hospital immunity skip rule (L6558). |
| **Actors / NPC roaming** (`humanoids`, `manageNpcSpawns`, `updateHumans`) | The `hospital` flag excludes an actor from roaming, spawning and witness lists. Victims, bystanders, motorcyclists and hospital staff all use it. Healed victims return to the spawn pool. |
| **Traffic** | Emergency vehicles are lethal movers. The legacy ambulance yields to pedestrians within 5. The road network defines `nearestRoadStage` and `makeRoadTrip` waypoints. |
| **Routes / WorldGen** | Police roof route. The hospital roof is a landing surface only. The duct is a private polyline, not in the route registry. Hospital and police lot geometry. |
| **Camera** | Duct rail camera; hospital clamp and partition occlusion; hatch look-down. |
| **Rendering / presentation** | Indoor fog, exposure, sky and roof hiding. Beacons in `updateScenery`. |
| **HUD / UI** | INFECTION stat and bar, chew panel, district tag, scout text, flash messages, game-over overlay (win, run over, predator). |
| **Idle watchdog** (`predatorForPlace`, L8187) | Inside the hospital the 13-minute idle predator is a "hospital security guard". |
| **Wildlife** | Normal squirrels are infection carriers (§6.4). Rabbits are skipped in the hospital. |
| **Living community / encounters** | Crime-scene witnesses, defenders, home retreat, bystander crowd. |
| **Novelty cast** (child cyclists, mime) | Flees to the police station; reaching it calls `dispatchCop`. Uses `medicalWalkRoute` and `medicalSegmentBlocked`. |
| **Westside** | Hosts the police station and calls `updateHospitalDoors`. Gas-station bite counter wraps `onSuccessfulBite`. |
| **Apple trees** | Excluded within 15 of the hospital footprint. |
| **Brief §6 Roles** | Will consume the kill, infection-percentage and work-performance events defined here (none exist in the HTML). |

---

## 11. Brief deltas (brief §6, §8, §9, §10, §13, plus Addendum A1 and A2)

### Hospital (brief §9 "Needs far more elaboration than the HTML")

1. **Rooms.** The brief requires reception, triage, two wards, an isolation ward, pharmacy, staff room, ambulance bay, and roof access as a squirrel route.

   | Brief room | HTML status |
   |---|---|
   | Reception | Desks at local (±18, -3); signed RECEPTION and PATIENT CHECK-IN. Exists. |
   | Triage | Two side alcoves with benches and the "WAITING / TRIAGE" lobby. Exists. |
   | Two wards | One open ward with 8 bays ("BAYS 1-4", "BAYS 5-8"). Split into two wards. |
   | Isolation ward | Missing (only decorative side screens). |
   | Pharmacy | Missing. The NW "SUPPLIES" shelving is the natural seed. |
   | Staff room | Missing. |
   | Ambulance bay | Only a driveway, canopy and a stretcher dock point at (laneX, 294). Needs a real covered bay. |
   | Roof access | Roof is landable at y ≈ 13.44, but no route exists. Add a route (e.g. downspout, tree or wire) and probably a roof hatch into the ducts. |

   Keep the duct, chew and hatch mechanics; they are the rodent's stealth route in.
2. **Isolation technique changes.** The HTML teleports and pauses the outside world. The brief needs a continuous, multiplayer building: physical doors, no world pause, roof access.
3. **Patients arrive by ambulance or walk in.** The HTML has ambulance delivery only (§7.5), and victims vanish at handoff. Add walk-in infected humans and keep delivered patients as actors inside, in wards or isolation, until treated.
4. **Disinfection interaction loop.** The HTML has none; treatment is automatic (`finishTreatment` after 5.5 s) and never lowers infection. Add: staff (player or AI) work a short loop at treatment stations. Each cure clears that human's infected state and lowers the town infection.
5. **Hospital performance = speed of disinfection** → raises staff rank and unlocks station upgrades (brief §9, §13). There is no HTML equivalent; a new metric is needed, e.g. time from admission to cure.
6. **Staff can kill the spicy rodent inside the building** (brief §6, §9). In the HTML, defenders only knock it back (10.8 impulse, 6 s cooldown, no damage). The rebuild needs the §8 health model: telegraphed blows deal damage, about 2 kicks kill. Killing staff become the lowest-rank uninfected squirrel. Patients, doctors and nurses currently never attack.
7. **Infected staff cure slower** (brief §8, §9). The HTML only counts bitten staff toward the win (§6.6); being bitten does not change their behaviour. Add a cure-time multiplier per infected staff member.
8. **Hospital fetch tasks** (Addendum A2). Staff fetch the right medicine or instrument from the pharmacy or supply room under time pressure; a wrong item costs time and score. No HTML equivalent. Use the SUPPLIES shelves and carts as anchors.
9. **Player slots** (brief §6; §2 only names the Roles module). 5 hospital staff player slots possessing the existing 8 staff bodies (brief §4 actor model). Patients stay AI.

### Infection (brief §6, §8)

10. **Per-actor infection.** The brief speaks of infected humans and "more than 30% of the town" (§6), so infection must become per-actor state with a town percentage = infected / population. The HTML uses an abstract score (`infectionOwn` + squirrel share) that decays over time and is not tied to who is infected. Decide how the HTML numbers map (see Open questions).
11. **Biting regular squirrels raises the town-wide infection rate** (§8). The HTML already does this: up to 25 points maturing over 25 minutes, gated on ≥ 25% own infection and a bite within 10 minutes. Brief §6 adds that an infected player squirrel "loses heavily (points and nuts) and drops in the queue". That is new.
12. **Hidden win path** (§8). HTML: ≥ 50% reading plus ≥ half of staff bitten plus ≥ half of patients bitten → "THE CITY IS YOURS". Brief: "critical mass of infection wins the session … do not surface this in the UI"; "session resets when everyone is infected". The win condition and the reset rule need reconciling. The HTML's always-visible INFECTION meter may conflict with "do not surface". Hiding the meter or the win rule is a designer call.
13. **Death of the rodent ends its run and starts the player as a lowest-level human** (§6). The HTML has no police or hospital kills; only traffic, the idle predator and the win end a run.

### Police (brief §10, Addendum A1 and A2)

14. **Officer player slots.** 5 at start, expandable one at a time to 8 through performance (brief §6, §10). The HTML has exactly 8 AI officer bodies (§8.2), which suits brief §4 backfill. Later officers are "more aggressive and better coordinated"; the HTML values give a baseline ladder:
    - chase speed 6.15 / 5.5 / 4 / 3.3;
    - windup 0.54 / 0.48 s;
    - cooldown 2.0 / 2.4 / 4.4 / 4.1.
15. **Officers can kill the spicy rodent** (§10). In the HTML the baton only knocks back and costs 19 Power. The rodent's health model must define baton damage.
16. **Police response is rare in the HTML** (18% single, 5% multi per bite). With player officers, AI dispatch should become a backfill when no player officer responds (inferred design intent).
17. **Drone** (§10). Unlocks after 8 officers. One pilot; full flight; camera feed; **spot-and-mark** reveals the rodent to officers for a short window and calls nearby vigilantes. No HTML equivalent. Its marks feed the A1 sightings layer.
18. **Drivable cars for the two highest-ranked officers** (Addendum A1). Enter and exit, throttle, brake, steer, siren and lights toggle, park anywhere. Other officers go on foot. Player cars take part in the server-side swept traffic collision and can run the rodent over; the HTML already treats every emergency vehicle as lethal. Reuse the beacon pattern (§7.7) for the lights toggle. AI patrol cars keep running for AI officers (owner to confirm).
19. **Radar and sightings on a map** (A1). Existing HTML signals map onto sighting events:
    - crime scenes (centre, 600 s TTL);
    - poster-witness calls (`sendPosterPolice`);
    - cyclist station reports;
    - the 600 s witness memory.

    Sightings fade over time. Radar (vehicle speeds) needs the traffic sim's speeds.
20. **Police side quests** (A2): petty arguments, fender benders, parking, speeding and stop-sign tickets, burglars. No HTML equivalent; all new, sourced from the traffic and community sims. Kicks promote any human (A2). HTML civilian kicks exist (`handleKickWindup`, owned by Combat) but give no reward.
21. **Wanted posters** stay as flavour and as a sighting source. In multiplayer the "hits > 8" trigger needs redefining, e.g. the current rodent's bites this run, or town infection.
22. **Station interior.** The HTML station is not enterable. Brief §3 says "Police station — expanded, see section 9" and "Hospital (west) — expanded, see section 8". Both cross-references are off by one: the hospital is §9 and police is §10. It needs at least a working interior for player officers (spawn, upgrades, drone launch), and the "guarded" behaviour should only apply to the rodent.

### Credits (brief §13)

23. Hospital and police work earns credits that raise queue rank and buy the §9 and §10 station upgrades. The HTML has only Squirrel Coins and Gold for the rodent.

---

## 12. Porting notes (Roblox)

**Authority.** The server owns:

- infection state: per-actor infected flags, town %, squirrel maturation timers, the hidden win check;
- vent open and chew state;
- the hospital and police AI brains for unpossessed bodies;
- the ambulance and police-car state machines;
- dispatch rolls, sightings, poster visibility;
- all damage and kills.

Clients only render: beacons, door swing, camera, fog, HUD. Every random roll (`Math.random` at L10482, L10489, L11012, L9704, L8105, plus the groan timer L9319 and the Combat-owned bite roll in `resolvePounce` L6518 that decides hospital bites) must run on the server.

**No world pause.** The HTML freezes the outdoor sim (pedestrians, traffic, cops, dogs) while the single player is inside, and freezes hospital staff while the player is in the duct. With up to 50 players everything runs continuously. Replace the pauses with:

- server LOD: tick distant AI at 2 to 5 Hz and near AI at 10 to 20 Hz;
- client culling: an interior zone hides the roof locally (`LocalTransparencyModifier`) and applies an Atmosphere/fog preset by zone.

**Hospital as a real interior.** Drop the teleport. Model the doors as a physical opening. Keep the 1.45 s door-open feel as an animation, and drive the door open state from a server attribute when any actor is within 15 (the HTML used the player only) or an ambulance hold is active. Convert local layout coordinates with world = local + (-356, 353), then × 2.5 for studs: the building is about 235 × 240 studs, 30 studs high.

**Ducts as routes.** Port the 7-node duct as a route of kind `duct` in the Routes registry (brief §7):

- arc-length parameter `s`, crawl speeds 2.8 / 3.8 u/s (7 / 9.5 studs/s);
- camera rail offsets as in §4.5;
- vents as nodes with per-vent `open` and `chew` attributes;
- the server validates position along `s` (no free movement in ducts).

Put the ducts at ceiling height in the rebuilt building so humans no longer clip them. Add a roof-hatch entry to satisfy "roof access (a squirrel route)".

**Chewing.** Do not use `ProximityPrompt.HoldDuration` for 120 s. Run a server-timed channel: start on prompt-begin, cancel on movement > 1.3 units (3.25 studs), distance > 4.9 units, or release. Progress persists per vent across attempts and players. Decide whether vents re-seal (Open questions).

**Movement of AI actors.**

- Hospital staff and officers on foot: server-side kinematic movement (CFrame or `Humanoid:MoveTo` with network ownership pinned to the server) on precomputed waypoint graphs. Port `hospitalPatrolTarget` as a nav graph over doorways.
- `medicalWalkRoute` (visibility-graph Dijkstra over building corners, ≤ 18 buildings) is cheap enough to port directly. `PathfindingService` with cached paths is an alternative. Avoid per-frame recomputation; the HTML recomputes only when the scene changes.

**Vehicles.**

- AI ambulances and police cars: anchored, kinematic CFrame movers along polylines (`advanceVehicleRoute`), replicated with client interpolation. Include them in the server's swept relative collision test (brief §8: no `Touched`).
- Player-driven cars (A1): `VehicleSeat`/constraints with client network ownership for feel. The server must still run the swept test from replicated CFrames with a tolerance, and sanity-check speed (anti-teleport).
- Beacons: client-side `PointLight`s and Neon parts toggled at the 4.7 Hz phase from a replicated `LightsOn` attribute.

**StreamingEnabled.**

- Gameplay logic must not depend on streamed parts. Keep the duct polyline, vent positions, hospital nav graph and poster positions in shared data modules.
- Mark the hospital interior and police station as Atomic models so doors and props arrive whole.
- The minimap and sighting markers (A1) come from server data, not from workspace parts.

**Performance budget.**

- Hospital: 8 staff + 8 patients.
- Medical: 3 ambulances × 3 crew + stretcher + kit, plus 7 bystanders.
- Police: 8 officers + 5 cars.

That is about 40 extra animated humanoids (16 hospital + 9 crew + 7 bystanders + 8 officers) plus 8 extra vehicles, on top of brief §5's 35 humans, 7 squirrels and 1 rodent. Use shared rigs, stream crews only near the camera, and tick idle patients slowly.

**Messages and speech.** Replace `flash()` toasts with a client notification module. Replace the `say()` bubbles with `TextChatService` bubble chat or BillboardGui. TTS (`speakWantedRecognition`) is dead code; skip it.

**Scale of tunables.** Multiply every distance and speed in this document by 2.5 for studs, e.g.:

- officer chase 6.15 → about 15.4 studs/s;
- squirrel ground speed 8.0 → 20 studs/s (sprint 16.8 → 42);
- defender range 15 → 37.5 studs.

Times and probabilities are unchanged.

**Avatar blending (A3).** Hospital uniforms (doctor, nurse, guard, orderly, extinguisher volunteer), police uniforms and paramedics are the 70% stock look. The colours listed in §5.1, §7.3 and §8.2 are the stock palettes to blend against.

---

## 13. Open questions (designer decisions)

1. **Infection unit.** Keep the HTML's abstract decaying score (own bites + squirrel share, win at 50) or switch to per-actor infection with town % = infected / all actors? Brief §6 ">30% of the town" and §8 "critical mass" suggest per-actor. Does the score still decay (0.66 per minute in the HTML), or does only curing reduce it?
2. **Hidden win.** Keep the HTML rule (≥ 50% plus at least half the staff and half the patients bitten) as the "critical mass" path? What threshold, and does infecting staff stay a requirement or only slow cures (brief)? How does "session resets when everyone is infected" interact with an earlier win?
3. **Infection meter.** Should the INFECTION meter stay visible to the rodent, everyone, or no one, given "do not surface this in the UI"?
4. **Disinfection loop.** What interaction (mini-game, hold, sequence), how many steps, how long? How much slower for infected staff (×1.5? ×2?)? Does an infected staff member stay infected until another staff member cures them?
5. **Hospital kill.** Which staff roles may damage the rodent: guards, orderlies and the extinguisher volunteer only, as in the HTML, or player staff of any role? What damage per blow, relative to a kick (brief §8: ~2 kicks kill; defenders hit 50% harder)?
6. **Police baton damage, and whether AI officers (not just player officers) can kill the rodent.**
7. **Vents.** Should chewed vents re-seal after a time or per session? Is the 120 s first grille intentional given the 24 s side grilles (the HTML shortcut, §4.2)? Should staff be able to repair vents (a hospital upgrade)?
8. **Duct infection penalty.** Is the faster infection decay in the duct (0.05/s versus 0.011/s) intentional design to keep in multiplayer?
9. **Police dispatch with player officers.** Do AI incident rolls (18% / 5%) continue, or do sightings only notify player officers? Which AI bodies remain when police slots are full?
10. **Sightings visibility** (A1, owner to confirm). Police only, or also hospital staff and the drone? Marker lifetime? The HTML analogues are crime-scene TTL 600 s and witness memory 600 s.
11. **Wanted poster trigger** in multiplayer: per rodent run (9th bite) or town infection level? How many posters? This depends on the utility-pole count, which the poles subsystem owns.
12. **Police station interior.** Make it enterable for officers (spawn, locker, upgrades, drone pad) while keeping it guarded against the rodent?
13. **Hospital roof access.** Which route: a downspout on the hospital, an adjacent tree, or a utility wire? Does it lead into the duct network through a roof hatch (proposed), or only onto the roof?
14. **Ambulance count and serial handoff.** The HTML has 3 responders, one handoff at a time, 23.7 s each. Keep this when player staff receive patients, or let any free staff member accept at the bay?
15. **Incident police "two cars" route** goes via x = -300 regardless of where the scene is. Should it use the rebuilt road graph?
16. **Officer scale.** The HTML patrol officer model is about 3.4 units tall versus about 2.1 for ordinary humans (accidental). Confirm all humans use standard R15 height (brief §2).
17. **Legacy decorative ambulance loop** (§7.6). Keep it as ambient traffic or drop it now that responders exist?
18. **Precinct officer tether** (§8.5, inferred bug). Port the intended chase behaviour or the effective tethered behaviour?

---

## Added by verifier

These items are in scope but were missing or understated above. Each was checked in `v5_4_game.js` unless marked otherwise.

1. **The overhead hatch drop pins the rodent (soft-lock, code fact).**
   - The drop start (-345, floor + 6.45, 389) lies inside bed 6's furniture collider: centre (-345, 388), 7.3 × 11.3, inflated 0.23 (L3984, L8615-8617).
   - `adjustHospitalMovement` (L8603-8633) rejects every sub-step whose x/z is inside a collider. Starting inside, both axes are blocked forever. Replaying the function in node for 10 s in 7 directions at sprint speed, plus a 10.8 knock, left the rodent at exactly (-345, 389).
   - No escape exists in code. The hatch is not offered to E outside the duct (L8574). The nearest grille (vent 3) is 21.9 away and the exit is about 77 away.
   - The 2.5 s ambush window cannot land either. The nearest patient circuit (patient 6) stays 7.35 from the hatch. The nearest defender circuit (Orderly Park) stays at least 15.23 away, just outside the 15 pursuit radius, so no defender ever walks over.
   - The idle predator does not end it, because leaping in place counts as movement (`updateIdle` L8208-8217, threshold 0.035 per frame). Only a reload or standing still for 13 minutes ends the run.
   - **Port:** put the hatch over an aisle, or exclude the drop point from furniture collision. The rebuilt building needs a reachable landing zone.
2. **Door transitions live in an optional subsystem.** `hospitalTransition` is advanced only inside `updateHospitalDoors`, called from `updateWestside` (L10241) under `updateOptional("Westside", …)` (L15961). If Westside throws once, it is disabled. Then `updatePlayer` returns early every frame (L6574-6578) and the player is frozen mid-door. **Port:** make the door and enter/leave logic core.
3. **Patrol waypoint rule** (L8780-8788). A walker advances to the next circuit point when it is within **0.75** of the current one and its pause has reached 0. It then sets the pause to 0.24 (staff) or 0.48 (patients). A paused, non-pursuing actor does not move (L8792).
4. **Defender telegraph freezes outside.** The attack sub-machine `continue`s when the player is not inside (L8819). A telegraph already started is not counted down while the rodent is outdoors, and it resumes on re-entry. The raised-arm pose is overwritten by the stride code each frame.
5. **Failed police bite resets the officer** (L8124-8126). `windup = 0` and `hitCooldown = 0`, so the officer can start a 0.54 s or 0.48 s wind-up on the very next frame.
6. **Single-officer dispatch teleports the car even when the officer is already out.** `startIncidentPolice(…, 1, 1)` and `sendPosterPolice` always move `patrolCar` and raise `copState.alert` (≥ 43 or ≥ 52). Only `dispatchCop` itself is skipped while the officer is out (L11021-11024, L11045-11049).
7. **Dead or write-only identifiers in scope.** Do not port these:
   - `ductEntrance` (L8421);
   - `treatmentNotice` (L8848);
   - `hospitalExitPoint()` (L5046, no callers);
   - `infectionDisplayed` (written at L8463, never read);
   - `victim.recoverAt` (L9204);
   - `WITNESS_MEMORY_SECONDS` (L10442);
   - `speakWantedRecognition` (L11286).
8. **v4.1 lineage check.** The hospital, duct and infection blocks are unchanged from v4.1: a whitespace-insensitive diff of v4.1 L3588-3870 and L8098-8560 against v5.4 shows only shifted offsets and comments. Nothing hospital- or police-related was lost. One lost v4.1 feature touched infection. Fox and deer bites (`tryNewWildlifePounce`, v4.1 L12651, called at v4.1 L8625) set `secondsSinceBite = 0` and `hits++`, which kept the squirrel-maturation gate (bite within 600 s) open. Brief §1 restores foxes and deer. Decide whether bites on them count toward that gate.
9. **Hospital scout text** (L6600-6601): "EMERGENCY WING · E to use doors or vents / First vent: hold E to chew." In the duct (L6596-6599) it reads "VENT CRAWL · W/S along the duct / HOLD E at a closed grille to chew", or "OVERHEAD EXIT OPEN · SPACE to drop / LEFT CLICK to pounce from above" over the open hatch.

## Verification log

Each line gives the claim, then the result, then the evidence. Line numbers refer to `v5_4_game.js` unless marked.

1. Hospital constants HOSP_X/Z/W/D = -356/353/94/96: OK (L3802-3805).
2. HOSP_BASE = 0.10 and HOSPITAL_FLOOR = 0.52; the station also evaluates to 0.10: OK. `baseTerrainHeight` was re-evaluated in node.
3. Hospital road z 283, width 12, x -417 to -238; sidewalks at z 273.5 and 292.5: OK (L3809-3810).
4. Driveway x -356, width 8, z 284 to 305; side sidewalks at ±6.5: OK (L3811-3812).
5. Exterior sign texts, sizes and positions: OK (L4035-4047).
6. Shell: plinth, slab, 1.2 × 12 walls, window z set, front segments at ±29, lintel, hinges ±8.2 at z -48.67, canopy, roof y 12.8, 12 ceiling panels: OK (L3822-3852).
7. Eight partitions (centres, sizes, heights 6.7 / 5.0 / 4.6): OK (L3872-3879).
8. Interior sign texts and local positions: OK (L3885-3903).
9. Bed formula, size 7 × 0.7 × 11, pillow at z + 4.3, curtain at x + 4.1 with opacity 0.67: OK (L3972-3985).
10. Patient station = bed.z - 6.35: OK (L5038).
11. Props (benches, carts, IV poles, desks, side screens ±43.5 at z {-8, 5, 18}, plants, floor guides, stretchers): OK (L3853-4073).
12. Furniture colliders: desks 12.5 × 3.8 at (∓18, -3), beds 7.3 × 11.3: OK (L3968-3984).
13. Player clamp 2.3 / 2.4, sub-steps ceil(d / 0.28) ≤ 18, inflation 0.23: OK (L8603-8633).
14. Roof landable across the whole footprint + 1.2: FIXED (whole roof -> perimeter strip only, because of the L6735 x/z revert).
15. Systems paused while inside: OK (L15948-15957, L9091, L9114).
16. Interior fog 15 / 53, camera far 125 / 55, background #455c5b, exposure 1.12 overriding 1.19: OK (L9116-9132, L13232).
17. Interior camera occlusion march: FIXED ("ignores samples above floor + 7" -> the march breaks at the first such sample).
18. Door radius 15 at (-356, 305), hold 1.5, damp 7.5, 1.36 rad: OK (L8429-8435).
19. Enter within 8 of (-356, 298) with \|dy\| < 4; exit within 6 of (-356, 312): OK (L8560-8571).
20. Transition 1.45 s smoothstep, targets z 314 / 294, flip at 0.47, hold 4.0 then 2.4: OK (L8436-8496).
21. Duct of 7 nodes, segment lengths, total 136.020: OK (recomputed).
22. Duct cross-section 2.7 × 1.76, floor -0.88, #829a96 at opacity 0.29, hole of len - 3.1: OK (L4126-4155).
23. Vent table (positions, heights, `first`, `upper`): OK (L4119-4125).
24. Chew times 120 / 24; cancel at 1.3, 4.9 or 3.2: OK (L8867-8897).
25. Chew panel text: FIXED (added the "CHEWING OVERHEAD HATCH" variant and floor(n)).
26. Vent pick radii 4.7 / 3.2 and duct height test \|dy\| < 2.6: OK (L8573-8579).
27. `enterDuct` probe +3.05 and placement -0.72: OK (L8500-8514).
28. Crawl 2.8 / 3.8, ×1.6 boost, yaw rate 11: OK (L6618-6654).
29. `leaveDuct` placement (vent.x + 2.8 clamped, vent.z + 2.4): OK (L8515-8525).
30. `overheadHatch` distance < 2.9 and y > floor + 4: OK (L8526-8534).
31. `dropFromHatch`: speeds 7.4 / 2.3, vy -5.7, cooldown 0.86, attack 0.55, window 2.5: OK (L8535-8555).
32. "Drop lands in the east half of the north bed row": FIXED (lands in the ward -> pinned inside bed 6's collider; node replay).
33. Staff names, roles, colours, stations, personality rule: OK (L4968-5016).
34. Staff `n.speed` 2.3 / 1.6 / 1.05: OK (L4995).
35. Staff circuits (8 × 4 points): OK (L8693-8742).
36. Patient circuits, start index i % 4, pause 0.4 + (i % 3) · 0.3: OK (L8750-8763).
37. `hospitalPatrolTarget` rules: OK (L8679-8690).
38. Pace table 3.9 / 2.7 / 1.15 / 1.85 / 1.62 and pursuit radius 15: OK (L8771-8806).
39. Telegraph trigger 7.2 / 4, duration 1.0 / 0.76, hit range 3.6 / 2.45, cooldown 6, knock 10.8: OK (L8819-8843).
40. `knockPlayer`: vy = min(3, 2.376), cameraCommit 0.38, no damage: OK (L8665-8677).
41. Infection increments 5.7 / 6.2 / 3.6 and immunity `nextBite` 14: OK (L8634-8644).
42. Win: reading ≥ 50, 4 staff and 4 patients, "THE CITY IS YOURS": OK (L8645-8664).
43. Decay 0.011 per s, 0.05 per s in the duct: OK (L8851).
44. Maturation over 1500 s, gate ≥ 25 and < 600 s, 25/7 per squirrel, cap 25: OK (L8852-8862).
45. Below 25% own infection: FIXED ("92% of current maturity" -> 0.92 of full maturity).
46. Squirrel hide anchors and fur colours: OK (L5062-5071).
47. Conversion radius 1.42, +90 Power, +10 coins, hits +1: OK (L8957-8977).
48. Conversion recolour: FIXED ("head #a67860" -> shared fur material, so the whole fur turns #a67860).
49. Red eyes after 120 s at emissive 0.55; cleared by treatment: OK (L9331-9335, L10554-10558).
50. Crime scene radius 72, ttl 600; bystander pool 7, 2 to 4 gathered: OK (L9222, L9685, L9704).
51. `nearestRoadStage` segment lists: OK (L9166-9197).
52. 3 responder ambulances with their colours and flash bars: OK (L9149-9164).
53. medicalHome (-356, terrain + 0.1, 295): OK (L10443).
54. `makeRoadTrip` legs and 0.35 dedupe: OK (L10447-10470).
55. Responder timings (wait 9 to 19, speed 24 / 27, walk /3.45 clamped 3 to 55, assess 2.1 / 5.0 / 3.3, load 2.15 / 3.25, return 25, 3.2 / 8 / 5.5 / 7): OK (L10805-10978).
56. Handoff laneX step 3.4, parking 5.9, dock z 294, queue offsets 6.5 / 2.2: OK (L10781-10804, L10902-10908).
57. `finishTreatment` fields and maxLife R(24, 55); no infection change: OK (L10538-10563).
58. `medicalWalkRoute` inflation 0.92, ≤ 18 buildings, +11 filter, corner pad 2.65: OK (L10576-10653).
59. Legacy ambulance 18 / 145 / 16 s, 12.5 and 10.625, park z 295, siren 430 Hz every 1.45 s at 0.018 / 0.001: OK (L8979-9038).
60. `updateAmbulance` start line: FIXED (L8980 -> L8990; model L8979-8989).
61. Beacons: phase floor(time · 4.7) % 2, intensity 2.6 / 0.13, colours: OK (L12096-12128).
62. Police station geometry (slab, walls, roof, sign, desk, parking pads, cruisers, roof route): OK (L10049-10077).
63. stationWelcome, Threshold and Inner z offsets 20.5 / 14.9 / 8.8: OK (L12137-12139).
64. Station door leaves (hinges ±2.25 at z 15.5, 2.18 × 3.35, 1.25 rad): OK (L12140-12153, L12552).
65. Patrol car shuttles x 55 to 645 at 10.5 on z -5.6: OK (L7976, L8026-8040).
66. `dispatchCop`: alert 23, officer at car + (0, 0, 3.4): OK (L8003-8011).
67. Patrol cop windup 0.54, cooldown 2.0, reach 2.85, knock 14, chase 6.15 for 2.55 < d < 86, windup start < 3.6, stand down > 155: OK (L8041-8079).
68. `officerBatonContact`: Power -19, vy ≥ 3.1, no damage: OK (L8012-8024).
69. Incident roll 0.05 multi, 0.18 single: OK (L10440-10441, L11011-11018).
70. Incident cars start at ±15 (re-placed by `startIncidentPolice`; built at ±9), route via x -300, speed 23, patrol 48 s: OK (L10992, L11019-11068).
71. Incident officer offsets, speeds 2.3 / 1.9 / 5.5, windup 0.48, cooldown 2.4, reach 2.9: OK (L11085-11154).
72. Reinforcement shove: FIXED (added the push of about 4.3 to 5 when 2 < d < 2.3, caused by in-place normalise).
73. Precinct circling (radius 3, 0.21 rad/s), step 3.3, shove 4.1 / 11 / 2.4, tether inference: OK (L10309-10314, L11189-11209).
74. `tryPolicePounce` gate 1.85 and dy [-0.3, 2.8], surprise rule, 0.88 / 0.035, stun 5.5, cooldown 6, +130 Power: OK (L8083-8135).
75. Posters on every 7th support from index 6, panel 1.3 × 1.79, 320 × 424 texture, shown when hits > 8: OK (L11227-11284).
76. Poster witness "3× detection radius": FIXED (-> radar ×3, sight 14.5 -> capped 20).
77. Noise cap 16: FIXED (-> noise already needs < 8.6, L7033).
78. `speakWantedRecognition` has no callers; pitches 1.15 / 0.77 / 1.65: OK (L11286-11305).
79. `WITNESS_MEMORY_SECONDS` is unused: OK (L10442, single occurrence).
80. Emergency vehicles can kill, including parked cruisers: FIXED (parked cruisers and teleports never kill; L15870-15897).
81. Fatal traffic is disabled in the hospital, sewer and duct; every `makeCar` is in `cars[]`: OK (L15774, L1530).
82. Restart reloads the page; HUD markup lines: OK (L7869; shell L35-37, L135, L153-154).
83. The brief's §3 cross-references (hospital "§8", police "§9") are off by one: OK (brief txt L72-73 vs headings L310 and L324).
84. Slot citations "brief §2": FIXED (-> §6 and §10).
85. Performance count "about 45 actors on 35 humans and squirrels": FIXED (-> about 40 humanoids + 8 vehicles; brief §5 is 35 + 7 + 1).
86. Random-roll list: FIXED (added groan timer L9319 and the `resolvePounce` roll L6518).
87. Officer about 3.4 tall vs ordinary human about 2.1: OK (human body scale 0.59 × R(0.87, 1.13), L4588-4589; officer cap top about 3.33).
88. JSON: `spec/data/*.json` (7 files, other extractors' output; this spec references none) all parse. 12 in-scope `human_cast.json` entries were spot-checked against code: OK, not edited. They cover staff names and roles, personalities (Orderly Park "wary", i % 3), patient skin and clothing cycles (Walter, Toby), humanoid index 29 for Dr. Ellis (26 NPC_DEFS + 3), officer, reinforcement and precinct colours, and medic colours.
