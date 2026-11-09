# Human Actors and Their Behaviour — porting spec (v5.4 → Roblox)

Scope: `makeHuman` and every human cast, roles, personalities, spawning and population caps, walking lanes, spotting and alert, speech and voices, reactions to the squirrel (flee, dodge, kick, defend, home retreat), house doors and the four walk-in interiors, crime scenes, witnesses and bystanders, procedural human animation, and yard cats.

All line numbers refer to `reference/v5_4_game.js`. Units are HTML world units ("u"). The brief maps 1 u to about 2.5 studs. +Y is up. A model's forward is local +Z, and heading is `atan2(dx, dz)` throughout. Times are game seconds (`time`, which pauses with the game; frame dt is capped at 0.08 s, L16007). Anything marked **(inferred)** was not stated in code or comments.

Companion data file: `spec/data/human_cast.json` has 87 entries: all 77 `makeHuman` actors in creation order, plus 10 entries for human figures that are separate low-poly models.

Randomness: `R(a,b)` and `pick()` use one shared seeded mulberry32 stream with seed 20261008 (L80-92). Some calls use `Math.random()` instead: pairing, retreat hide time, kick and dodge rolls, crime-scene gathering and moans.

---

## 1. Inventory: every human in v5.4

### 1.1 `makeHuman` actors (array `humanoids`, 77 bodies, created at boot, never destroyed)

| idx | Group | Count | Created | Driven by | In roaming scheduler? |
|---|---|---|---|---|---|
| 0-25 | `NPC_DEFS`: 12 residents, 8 walkers, 1 jogger, 3 cyclists, 1 skater, 1 mail carrier | 26 | L4493-4520, L4730 | `updateHumans` L7012 | yes |
| 26-27 | Park walkers Tori and Gene | 2 | L4731-4732 | `updateHumans` | yes (park lane) |
| 28 | Mourner Evelyn | 1 | L4733 | `updateHumans` | yes (cemetery lane) |
| 29-36 | Hospital staff: 1 doctor, 2 nurses, 2 guards, 2 orderlies, 1 extinguisher woman | 8 | L4968-5016 | `updateHospitalActors` L8765 | no (`hospital=true`) |
| 37-44 | Hospital patients | 8 | L5017-5045 | `updateHospitalActors` | no |
| 45-46 | Motorcyclists Morgan and Alex Rider | 2 | L9562-9620 | `updateMotorcycles` L9637 | no |
| 47-53 | Emergency bystanders (pool) | 7 | L9684-9702 | `updateEmergencyBystanders` L9743 | no |
| 54-60 | Barbecue "Neighbor 1-7" | 7 | L11368-11393, L11403 | `updateLivingEvents` L11405 | no |
| 61-70 | Softball "Player 1-10" | 10 | L11404 | `updateLivingEvents` | no |
| 71 | Marcel the Mime (unicycle and juggling) | 1 | L12199-12243 | `updateNoveltyCast` L12352 | no (`specialStreetCast`) |
| 72-76 | Kid cyclists Ellie, Theo, Jules, Avery, Riley | 5 | L12245-12282 | `updateNoveltyCast` | no |

The comment at L4492 says "26 distinct cast members"; that count is `NPC_DEFS` only.

Every `makeHuman` actor can be bitten. `updatePounceCollision` (L6555) tests every visible, non-injured humanoid; hospital actors are skipped only while their `nextBite` cooldown is above 0.

### 1.2 Human figures that are NOT `makeHuman` actors

These are separate hand-built `THREE.Group`s. Most belong to other subsystems; they are listed so the Roblox build can fold them into the single human actor model (brief §4).

| Figure | Count | Line | Owner subsystem | Notes |
|---|---|---|---|---|
| Patrol officer | 1 | L7981-7995 | Police | baton chase, `copState` |
| Incident officers | 3 | L10999-11009 | Police | rolled on 5% of bites |
| Station reinforcements | 2 | L11211-11222 | Police | |
| Precinct guards | 2 | L10079-10093, L10309-10314 | Police | circle radius 3 at 0.21 rad/s |
| Paramedics (first, second) and intake receivers | 3 + 3 + 3 | L10515-10525, L10674-10720 | Medical/Hospital | speech uses pseudo-actors idx 87-89 (L10708-10715) |
| Waterside walkers (Bellwether Quay) | 8 | L14100-14114, L14155-14158 | River district | ambient only; cannot be bitten and do not react |
| Car drivers | 1 per car | L1525-1529 | Traffic | head, torso and wheel baked into `makeCar` |
| Trolley passengers | 5 | L7673-7679 | Street vehicles | baked into the trolley |

There are no human figures in the Galleria mall and no westside residents. The 7 westside old houses (L9913-10024) have no occupants; 4 of them have squirrel-only garage interiors.

---

## 2. Body construction: `makeHuman(def, idx)` (L4582-4729)

`def = [name, role, home, skinHex, shirtHex, personality]`.

### 2.1 Hierarchy and proportions

- `root` (world transform and heading) → `body` (uniform scale `R(0.87,1.13) × 0.59`, L4588-4589) → parts.
- In unscaled body-local units the top of the head is about 3.55, so standing height is about **2.09 u** (range 1.82-2.37 u), about **4.5-5.9 studs**. That fits standard R15 height (brief §2).
- Parts in body-local space:
  - Torso: box 0.87×1.42×0.42 at y 1.82, shirt colour.
  - Hips: box 0.75×0.37×0.5 at y 0.98, pants colour.
  - Neck: cylinder at y 2.62.
  - Head group at y 2.9:
    - skull: sphere r 0.47 scaled (0.84, 1.1, 0.78)
    - hair cap: sphere r 0.43 scaled (0.9, 0.45, 0.92)
    - hair bun when `idx % 4 === 0` (L4604)
    - black eyes at (±0.17, 0.22, 0.36)
    - ears and nose
  - Arms: 2 groups pivoting at (±0.59, 2.37, 0). Each is a tapered sleeve span to (±0.14, −1.17, 0.06) with a skin-coloured hand.
  - Legs: 2 groups pivoting at (±0.22, 0.86, 0). Each is a tapered pants span of length 0.76 with a shoe box.
  - Hidden **red glow eyes**: emissive `#7e1111` spheres over the normal eyes (L4654-4671). They switch on for victims left injured 120 s or more (L9331), which is the visible infection tell.
- Colours:
  - Skin: per definition. `sharedSkin` caches one material per hex (L4523).
  - Shirt: per definition.
  - Pants: random from `#3d494b #646c61 #55585a #827a6c #484957` (L4592).
  - Shoes: `#2f3431`.
  - Hair: random from `#40382f #755a45 #bba27e #666663 #2d2928 #937d57` (L4602).

### 2.2 Role props

| Role | Props | Lines |
|---|---|---|
| `mail` | Grey satchel 1.4×0.9×0.36 `#6b7070`, white letter `#e8ebdb`, blue cap `#54738a` | L4672-4676 |
| `cyclist` | Full-scale bicycle on `root`, not `body`:<br>• two spoked wheels r 0.6 at z ±1.05 (16 instanced spokes, valve stem), from `makeSpokedBicycleWheel` L4528<br>• frame colour by `idx % 4` from `#405979 #b65e53 #59826d #a58b4d`<br>• saddle, bars, lamp `#fff3b5`, reflector `#bd4d3e`<br>• rotating pedal crank `bikeCrank`<br>`body.position.y = 0.72` | L4677-4717 |
| `skater` | Deck 0.62×0.14×2.1 `#7f4e43` with 4 wheels; `body.position.y = 0.24` | L4718-4724 |
| hospital `guard` | Dark cap `#2c3d43` | L5013 |
| hospital `orderly` | Stretcher trolley (`stretcherModel`) scaled 0.48, 2.1 u in front | L5004-5008 |
| hospital `extinguisher` | Red tank `#cc3326` and hose | L5009-5012 |
| doctor and nurses | Clipboard at (0.65, 1.44, 0.22), tilted while "charting" | L11646-11677 |
| patients | White wrist wrap `#f2f0e1` | L5042 |
| mime | See §8 | L12209-12243 |
| kid riders | Body ×0.76; helmet (sphere scaled 1×0.43×1, rider colour) with dark visor; bicycle ×0.82 | L12268-12281 |
| motorcyclist | Separate bike group (torus wheels r 0.55, paint `#9f3632` or `#324f68`, headlamp); rider pose leans 0.14 with arms −0.9 | L9578-9603, L9669-9672 |

### 2.3 Per-actor runtime fields (L4626-4652)

`state` (initial "walk"), `alert`, `reacting`, `sayCooldown`, `visible`, `goal`, `speed` (R(0.8,1.7) initially), `phase` (gait offset), `facing`, `timeAway`, `maxLife` (R(21,51)), `bike`, `bubbles`.

Fields added later: `pedLane`, `onAccess`, `accessX`, `doorEscape`, `hiddenInHomeUntil`, `witnessUntil`, `defenseUntil`, `kickWindup`, `kickCooldown`, `dodgeTimer`, `dodgeCooldown`, `dodgeSide`, `smoothedSpeed`, `injured`, `sceneHot`, `crimeOrigin`, `medical*`, `wantedSawAt`, `wantedCalled`.

`attention` and `skill` are set but never read (dead).

---

## 3. Personalities

There are four values, set per definition. Personality never changes movement speed or flee choice. It affects only the following:

| Personality | Effect | Lines |
|---|---|---|
| `panic` | TTS pitch 1.23. With the squirrel in a tree, 34% chance of the line "It's in the trees!". | L4770, L4811 |
| `bluster` | TTS pitch 0.84. Spot line restricted to spot[0], [2] or [4]. | L4770, L4805-4810 |
| `wary` | TTS pitch 1.06. With a companion within 11 u, 35% chance of "I TOLD you about those damn squirrels!". Defender only if `idx % 5 === 0` and among the 4 nearest witnesses (Donna idx 0, June idx 25). | L4812, L9240 |
| `brave` | TTS pitch 1.06. **Only personality that can start a kick on its own**, and only while `witnessUntil > time` (it has witnessed a bite or crime scene, or recognised a poster). Always eligible to defend at a bite (max 2 defenders). | L8141, L8168, L9240 |

Roster mix:
- `NPC_DEFS`: wary 9, panic 8, bluster 5, brave 4 (Calvin, Sam, Ray, Ari).
- Park and cemetery: Tori brave, Gene wary, Evelyn panic.
- Hospital staff: `i%3 ? brave : wary` (only affects voice).
- Patients: panic.
- Event NPCs: `i%4===0` brave, else wary (affects voice only; they never kick).
- Novelty riders: panic.
- Bystanders: wary.

Vigilante share among roamers: 5 of 29 are brave (about 17%). They kick only after witnessing; there is no unprompted vigilante behaviour.

---

## 4. Population and spawn management

### 4.1 Roaming scheduler: `manageNpcSpawns(dt)` (L4925-4963), called first in `updateHumans`

- **Pool:** every humanoid with `!hospital && !specialStreetCast`. At boot that is idx 0-28.
- **Visible cap:** `demoCrowd ? 14 : 7` (L4928). `demoCrowd` defaults to true (L4908). It is toggled by the start-screen chip `NPC FLOW: DEMO/QUIET` (L5690-5699). The chip's text says "up to eleven" and "about five", which disagrees with the code (14 and 7).
- **Cadence:** one spawn attempt when `npcTimer ≥ 1.75 s` (demo) or 5 s (quiet), and only while under the cap.
- **Order:**
  1. The first hidden pool member with index ≥ `npcSpawnCursor` and `hiddenInHomeUntil ≤ time`; otherwise any hidden eligible member.
  2. Cursor becomes `(first.idx + 1) % 29`.
- **Pairing:** if `count + 1 < max`, there is a 56% chance (`Math.random`) of a companion (L4946-4960):
  - The companion is the first hidden member that is not hospital, motorcyclist or special cast. **It does not check `hiddenInHomeUntil`.**
  - It is forced off its access walk and copies the leader's lane and goal.
  - Offset: +2.1 x when the lane runs along x; +(1.6, 0, 1.9) when it runs along z.
  - Speed: `leader.speed × 0.93`.
- **Despawn** (L7203-7209): when `timeAway > maxLife`, or when the actor leaves x ∈ [−265, 670], z ∈ [−242, 438], it becomes invisible and its bubbles are killed. `maxLife` is re-rolled to R(24,56).
  - In practice each roaming pedestrian is on screen for about 21-56 s and then disappears wherever they are, which may be in view.
- **Boot state** (L4903-4924):
  - All humanoids start hidden.
  - Then `spawnNpc` is called for idx 0, 14, 15, 20, 21, 23, 24 and 26, 27, 28.
  - The `[idx, x, z]` coordinates in that loop are ignored; positions come from `spawnNpc`.

### 4.2 `spawnNpc(npc)` (L4865-4901): lane assignment

1. **Residents:** `role === "resident" && home >= 0`, with 52% chance (`onAccess`).
   - Start at the house's front walk: x = house.x ± 2, z = `frontZ − sign(h.z) × R(0,2.4)`.
   - Goal: the sidewalk at z = sign(h.z) × 12.1.
   - Lane afterwards: `{axis:"x", fixed: side × 12.1}`.
   - While walking, x is held to `accessX` (damp 8, L7177).
2. **Park walkers:** lane `{axis:"x", fixed:326, north:true}` (that is, z = 326), starting at x R(−195,112).
   **Mourner:** z = 405, starting at x R(315,624).
3. **Commercial walkers:** idx 15 Ray, 18 Dale, 21 Zoe, 25 June when not on an access walk.
   - Lane z = +17.4 for odd idx, −17.4 for even.
   - Start x R(400,635).
4. **Everyone else:** 80% one of the 4 core lanes, 20% any of all 12 lanes (L4885); start u ∈ R(−115,115).
5. **Reset on spawn:** `state` "walk", `alert`, `reacting`, `timeAway`, `sayCooldown`, `doorEscape`, `hiddenInHomeUntil`.
   Speeds: cyclist and skater R(3.2,5.2), jogger 3.1, others R(0.8,1.6).

**Sidewalk lanes** (`sidewalkLanes`, L4817-4830). `{axis, fixed}` means the lane runs along `axis` with the other coordinate equal to `fixed`. Every lane sits 12.1 u off a road centreline.

| # | Runs along | Fixed | Flanks road |
|---|---|---|---|
| 0, 1 | x | z = −12.1, +12.1 | z = 0 (core E-W) |
| 2, 3 | z | x = −12.1, +12.1 | x = 0 (core N-S) |
| 4, 5 | x | z = −161.9, −186.1 | z = −174 |
| 6, 7 | x | z = 158.9, 183.1 | z = 171 |
| 8, 9 | z | x = −167.9, −192.1 | x = −180 |
| 10, 11 | z | x = 165.9, 190.1 | x = 178 |
| park | x | z = 326 | park path, x −205..112 |
| cemetery | x | z = 405 | Cedar Rest path, x 306..628 |
| commercial | x | z = ±17.4 | east arterial, x 390..651 |

Points sit on the terrain plus 0.13 (`pointOnLane`, L4831).

### 4.3 Goals: `pedestrianGoal(n)` (L4840-4864)

- **North lanes:** step R(21,65) in a random direction, clamped as in the table above.
- **Commercial lanes:** step R(37,95); direction forced −1 when u > 615 and +1 when u < 424; clamp [390, 651].
- **Other lanes:** step R(37,95); direction forced inward beyond ±225 (`WORLD_HALF − 45`); clamp [−260, 260].
- A new goal is chosen when within 1.7 u of the target (L7134), or when house collision nulls the goal.

### 4.4 Other spawn managers

| Group | Spawn rule |
|---|---|
| Hospital staff and patients | Always "visible". Simulated only while the player is inside the hospital or within 150 u of (HOSP_X, HOSP_Z) = (−356, 353) (L9050). Not simulated at all while the player is in a duct. |
| Motorcyclists | See §9.4. |
| Emergency bystanders | Only during crime scenes (§7.3). |
| Event NPCs | Only during their gathering (§9.3). |
| Novelty cast | Always present until bitten (§8). |

### 4.5 Peak simultaneous visible humans (inferred)

14 roamers + 16 hospital + 6 novelty + 10 event + 7 bystanders + 2 riders gives a theoretical ceiling of about 55. The two events never overlap: the barbecue is visible while `time mod 2400` is in [0, 655) and the softball game while it is in [1200, 1855) (L11407-11411), so at most 10 event NPCs (softball) are visible at once.

In typical play there are 14 roamers, 6 novelty riders, 7 or 10 event people during a gathering, and 16 people inside the hospital.

---

## 5. Pedestrian brain: `updateHumans(dt)` (L7012-7211)

The loop runs for each visible humanoid with `!hospital && !specialStreetCast`.

- **Wrapper** (L9352-9368): every `injured && !medicalTransit` actor is stashed with `hospital = true` before the loop, so victims are skipped. They are forced visible afterwards.
- **Not ticked at all** while the player is in the sewer or hospital, or the game is paused (L15948).

### 5.1 States

`walk` · `flee` · `homeRetreat` · `defend` · `kick` · `injured` (owned by the crime-scene system).

### 5.2 Per-frame order

1. If `doorEscape` is set: run `advanceHomeRetreat` (§6.2) and skip everything else.
2. Decay timers by dt: `timeAway` up; `sayCooldown`, `alert`, `reacting` down, floored at 0.
3. **Perception** (§5.3) → `spotted`.
4. Crime-scene memory: if inside a live crime-scene radius and spotted, `witnessUntil = max(…, time+600)` (L7052).
5. **Wanted-poster recognition** (L7053-7067):
   - Once `player.hits > 8`, a human within 10 u of a poster records `wantedSawAt = time`.
   - Within the next 90 s, if spotted at a distance under 25.5 (= 8.5 × 3) and not yet called:
     - say "That is the squirrel from that poster!"
     - `witnessUntil = time+600`
     - `sendPosterPolice(pos)`, which brings the patrol car and officer (police spec).
6. **Spot reaction** (L7068-7078). If spotted, `alert ≤ 0`, and state is not flee, homeRetreat, defend or kick:
   - state `flee`, `alert = 8`, `reacting = 3`
   - say a spot line if `sayCooldown ≤ 0`
   - chirp `fx(410,0.09,sine)`
   - try `beginHomeRetreat` (residents only, §6.1); on success, advance it this frame and stop processing this actor.
7. `handleKickWindup` (§5.5).
8. **Dodge arm** (L7083-7095). If the squirrel's pounce window is open (`player.attackWindow > 0`), spotted, `alert > 1.5`, distance < 5.4, `dodgeCooldown ≤ 0`, no door escape, and not kicking:
   - `dodgeCooldown = 2.4`, `dodgeTimer = 0.38`, `dodgeSide = idx odd ? +1 : −1`.
9. **Defend exit:** when `defenseUntil ≤ time`, or not spotted, or distance > 17 → state `flee`.
10. **Target selection:**
    - `kick`: stand still.
    - `defend`: if 2.8 < distance < 17, target the point 2.4 u from the squirrel on the human's side at speed 5.6; otherwise stand still.
    - `flee` (L7110-7131):
      - Run along the human's own corridor (the access walk axis, or the lane axis) 22 u further from the squirrel along that axis.
      - Clamp to [−260, 260], or [385, 655] for commercial lanes.
      - Speed 7.1 (cyclist 8.25).
      - When `alert < 2`, return to `walk` with a new goal and speed R(0.9,1.8) (cyclist 4.2).
    - `walk`: `goal`. A new goal is picked when null or within 1.7.
11. **Motion** (L7138-7172):
    - `smoothedSpeed` damps toward `speed` (λ 10 when fleeing, 6.8 otherwise).
    - Step ≤ `smoothedSpeed × dt`.
    - **Traffic wait:** the step is cancelled if any moving car is within 3.25 u of the next position, or a street vehicle footprint is within 0.55 (`streetVehicleAt`).
    - **Dodge sidestep:** while `dodgeTimer > 0`, add a perpendicular offset at 8.6 u/s.
    - Turn rate is clamped to 4 rad/s.
    - World clamp: x ∈ [−265, 671], z ∈ [−241, 436].
12. **Lane lock** (walk state only): damp the cross-axis coordinate back to the lane (λ 8).
13. **Building collision** `humanHouseCollision` (L6989-7011):
    - Covers the 24 `houses` (4 core + 20 outer) plus 8 `commercialBounds` (restaurant L732, gas station L793, shop L906, 2 estate guesthouses L2694, 2 estate mansions L2747, police station L11224), with a 0.3 margin.
    - Revert x, else z, else push out along the shallowest axis.
    - Clears `goal` unless fleeing.
14. Snap y to terrain + 0.13.
15. Rotate bicycle wheels by distance actually travelled ÷ 0.6, and the crank by distance ÷ 0.34.
16. Animate (§10).
17. Despawn check (§4.1).

### 5.3 Perception: `spotted` (L7027-7051)

Let `d` be the horizontal distance to the squirrel and `pY` the squirrel's world Y. **pY is absolute world height, not height above ground (porting risk; the terrain varies by several units).**

```
isVisible  = !activeHouseInterior && (pY < 4 || d < 4.7)
inView     = dot(normalize(dirToSquirrel), facingDir) > 0.28     // about ±74°
noise      = squirrel.moveSpeed > (stalking ? 2.5 : 4.7) && d < 8.6 && (pY − humanY) < 22
concealed  = (inGardenPlot(115±27, 341±15, pY<2.4) || inHedgePatch(pY<2.8)) && moveSpeed < 3.4
             // inHedgePatch: |px−x| < len/2+1.8 && |pz−z| < h+1.1 for some [x,z,len,h] (L7037-7042);
             // the 4th value (bush height) doubles as the z half-extent of the hiding box
radar      = (inside a live crime scene radius || witnessUntil > time) ? 3 : 1
spotted    = !concealed && (
               (isVisible && d < min(20, 14.5·radar) && (inView || d < 6.8) && pY < 5.2)
            || (noise && d < min(16, 10.3·radar)) )
```

- Effective ranges: sight **14.5 u**, rising to 20 u when "hot"; peripheral or behind 6.8 u; hearing 8.6 u.
- The hearing check is effectively 8.6 u because the `noise` clause already caps it.
- Squirrel speeds for reference (L6617-6626):
  - stalk ("focus") 1.65: silent
  - walk 8.0: noisy
  - sprint 16.8: noisy
  - on tree routes ×0.6
- Squirrel height (absolute pY): below 4, normal sight. From 4 to 5.2, seen only within 4.7 u horizontally. At 5.2 or higher, never seen; only noise (within 8.6 u, and less than 22 u above the human) can reveal it. Waiting quietly in the canopy therefore defeats detection (comment L7030).
- Hedge patches `[x, z, length, h]` (L3573-3579): [125,303,14,2.3], [118,372,11,3], [−104,305,18,2.4], [290,306,22,2.6], [613,421,15,2.2]. Garden plot centre (115, 341) (L3590).

Other sources of `alert`:
- **Yard dog bark** within 10 u of a dog: `alert ≥ 3` for humans within 12 u of it (L9100-9112). This makes them "already alert" for bite resolution but does **not** trigger flee, because the spot reaction requires `alert ≤ 0`.
- **New crime scene:** every visible human within 72 u gets `alert ≥ 7`, and walkers switch to flee (L9291-9302).
- **Live injured victim:** humans within 20 u get `alert ≥ 4` each frame (L9339-9345).

### 5.4 Bite resolution against a human: `resolvePounce` (L6506-6554)

This is shared with the player and combat spec.

- **Contact:** horizontal distance < 1.38 u (motorcycle 2.0) and dy ∈ (−0.35, 2.7) (motorcycle 3.2), during `attackWindow` (0.78 s after the pounce, L6496).
- **Already alert:** the human's `alert` captured at pounce launch is > 0.45. Then success chance is **3.5%**; otherwise **95.5%**.
- **Motorcyclists:** always 100%.
- **Perfect counter:**
  - Condition: the human is in kick wind-up with `kickWindup < 0.34` and the squirrel's aim · direction to the human > 0.72.
  - Result: guaranteed bite, +1 golden coin, kick cancelled, `kickCooldown 12`.
- **Success:**
  - +100 Power, or +150 if pY > 4
  - +10 coins
  - `onSuccessfulBite` → crime scene and witnesses (§7)
  - infection +3.6 (+6.2 staff, +5.7 patient, L8634-8644)
  - victim says a "hit" line; state flee, alert 7, reacting 2.5
- **Failure:** victim flees (alert 7, reacting 2.9), says a spot line; squirrel is batted back (vel ×−0.12, vy 3.7).

### 5.5 Kick: `handleKickWindup(n, dt, d, spotted)` (L8137-8184)

```
committed = defenseUntil > time            // assigned defender at an injury scene
ready = (committed || (brave && witnessUntil > time))
        && !doorEscape && !injured && kickCooldown <= 0
        && d < 3.7 && (pY − humanY) < 1.7 && squirrel.attackWindow <= 0
        && spotted && !inSewer
```

- **ready → wind-up:**
  - `kickWindup = 0.58 s`, state `kick`, speed 0.
  - Says "Get back!", "I said get away!" or "Back off!" if off cooldown.
  - HUD warning "prepares to kick" when d < 6.1.
- **During wind-up:**
  - `legs[1]` (the +x leg, which is the actor's left because the model faces +Z) swings forward and up. Negative `rotation.x` moves the foot toward +Z. Final pose `−1.1 − (1−kickWindup)·0.65`, about −1.37 → −1.75 rad over the wind-up, which overrides the earlier value `−1.25 − (1−kickWindup)·0.7` set in `handleKickWindup` (L7202, L8146).
  - `facing` is re-aimed at the squirrel every frame. `root.rotation.y` is **not** updated while kicking, so the body does not visibly turn (inferred bug).
- **Release** at 0:
  - `kickCooldown = committed ? 2.6 : 6.0`; state becomes `defend` if committed, else `flee`; `alert = 7`.
  - **Hit** if d < 2.65, squirrel less than 1.6 above the human, facing · direction to squirrel > 0.55, and the squirrel is not mid-pounce. Facing was just re-aimed, so the angle test is effectively always true (inferred).
  - Hit effect (`officerBatonContact`, L8012):
    - squirrel launched away at 11 u/s, vy ≥ 3.1
    - knocked off any route
    - −19 Power
    - HUD "kicked the squirrel away!" (this flash comes from `handleKickWindup` L8162, not from `officerBatonContact`)
  - Otherwise "kick missed" when d < 5.1.
- A successful bite on a human in wind-up cancels it and sets `kickCooldown 12` (L7998-8001).

### 5.6 Response matrix (what v5.4 actually does)

| Trigger | panic / bluster / wary | brave | resident of houses 0-3 within 38 u of door |
|---|---|---|---|
| First sighting | flee along lane 22 u away, 7.1 u/s | same (no kick without witness memory) | run home and hide (§6) |
| Squirrel pounces while alert, d < 5.4 | dodge sidestep 0.38 s | dodge | n/a while retreating |
| Bite within 25 u (`alarmNearbyWitnesses`) | flee, 3 nearest try home retreat; 4 nearest shout | up to 2 nearest brave/eligible become **defenders** for 19 s | as left |
| Witnessed (`witnessUntil`), squirrel within 3.7 | flee | **kick wind-up 0.58 s** | — |
| Squirrel returns within 72 u of a scene | sight ×3 | sight ×3, may kick | — |

Brief §8 asks for flinch, swing, kick, back away and flee. v5.4 has flee, dodge (closest to "flinch"), kick, and defend (hold a 2.4 u stand-off, closest to "back away / guard"). There is **no civilian swing** in v5.4; swings exist only for police batons and hospital defenders.

---

## 6. Home retreat, house doors and the walk-in interiors

### 6.1 `beginHomeRetreat(n)` (L6886-6922)

- **Eligible:** `0 ≤ home < 4` (the 12 residents), not injured, no current escape, `houseDoors[home]` exists, and distance to the door's outside point ≤ **38 u**.
- **Path:**
  - If the resident is behind the house (`(z − h.z)·(−door.sign) < −0.3`), or the straight line to the door crosses the house footprint (+0.35, sampled 17 times), route around the side first:
    - waypoint A = (h.x ± (w/2 + 1.6), clamp(z, h.z ± (d/2 + 1.6)))
    - waypoint B = (same x, door.outside.z − sign·1.25)
  - Then go to `door.outside`.
- Sets `doorEscape = {stage:"approach", waypoints}`, state `homeRetreat`, `reacting ≥ 4`, `door.hold ≥ 3`. `speed = 4.7` is set but not used; the step speeds below apply.

### 6.2 `advanceHomeRetreat(n, dt)` (L6923-6974): state machine

```
approach  : walk waypoints at 4.9 u/s; arrival radius 0.65; when list empty → threshold (door.hold = 3.1)
threshold : WAIT until door.open ≥ 0.86 (houseDoorPassable); walk to threshold at 2.65 u/s; arrival 0.22 → inside
inside    : walk to inside point at 2.65 u/s; arrival 0.42 → HIDDEN
HIDDEN    : visible=false, doorEscape=null, hiddenInHomeUntil = time + 16..28 s (Math.random), door.hold = 2.2
```

- `door.hold ≥ 1.2` every frame of the retreat.
- Turn rate 8 (exponential `turnToward`).
- Run animation: arms up −1.25 ± 0.24 with ±0.22 flail at 11 rad/s; legs ±0.46 at 13 rad/s; head shake ±0.3.
- While retreating, perception, kicks and dodges are skipped. The squirrel **can** still bite the resident before the door; the victim then sits at that spot (§7).
- After `hiddenInHomeUntil` the resident re-enters the roaming pool. On respawn there is a 52% chance they appear on their own front walk, which looks like "coming back out" (inferred intent).

### 6.3 Doors (`houseDoors[id]`, built in `buildHouse` L1136-1159; animated in `animateHouseDoors` L6980-6987)

- **Hinge:** pivot at local (−1.12, 0, frontZ), leaf 2.24×3.32×0.14 (colour `#597e77` for odd id, `#5b4239` for even).
- **Portal:** 2.6 wide × 3.5 high in a 0.24 wall; the house group is scaled 0.82.
- **Opening:**
  - `open` damps toward 1 (λ 7.2) while `hold > 0` or any visible resident of that house has `doorEscape`.
  - `hold` decays at 1/s.
  - Rotation = `sign × open × 1.35 rad`.
- **Passable** when `open ≥ 0.86` (L6977). This is shared with the squirrel's entry.
- **World waypoints:**
  - outside = 1.25 × 0.82 u outside the front wall
  - threshold = the wall line
  - inside = 2.15 × 0.82 u inside
  - y = terrain + 0.13

| id | Lot (lots_core.json) | Centre | Faces | outside z | threshold z | inside z |
|---|---|---|---|---|---|---|
| 0 | core_house_0_victorian | (−56, −53) | +Z | −44.19 | −45.21 | −46.97 |
| 1 | core_house_1_bungalow | (51, −59) | +Z | −49.78 | −50.80 | −52.56 |
| 2 | core_house_2_brick | (−53, 51) | −Z | 41.78 | 42.80 | 44.56 |
| 3 | core_house_3_blue_cottage | (58, 56) | −Z | 47.60 | 48.62 | 50.38 |

All door x values equal the house centre x.

### 6.4 Interiors used by humans and the squirrel (L11682-12072)

- **Verifier correction: this whole interior system is dead code in shipped v5.4 (and v4.1).**
  - `enterableHouses` is built at L11788-11790 by filtering `houses` on `h.indoorGroup && h.indoorCeiling && h.indoorRoof && houseDoors[h.id] && id < 4`.
  - `h.indoorGroup` is assigned only inside `furnishOriginalHouse` (L11690), which is called only for members of `enterableHouses` (L11791). No house has `indoorGroup` when the filter runs, so `enterableHouses` is always `[]`. The minified build has the same order, and v4.1 does too (v4.1 L11466-11469).
  - Consequences: no interior is furnished, `makeHomeDetails` never runs, `handleHouseInteriorInteraction` and `updateHouseInteriors` loop over an empty list, and `activeHouseInterior` is never set. The squirrel cannot enter any house.
  - Doors still work for residents: `beginHomeRetreat` uses `houseDoors` directly, so the door swings and the resident vanishes at the inside point.
  - The rest of this section describes the **intended** design as written in code. Use it as reference for the Roblox interiors, not as observed v5.4 behaviour.
- `enterableHouses` = houses 0-3 only (L11788), intended to be furnished by `furnishOriginalHouse` and `makeHomeDetails`.
- **Rooms and furniture** (house-local, pre-scale):
  - Living room: couch 5.2×0.67×2.45 with back and arms, coffee table, striped rug.
  - Kitchen across the rear wall: 4 counters, fridge, sink, stove with 4 burners, 6 wall cabinets, kettle, toaster.
  - Dining table 3.7×3.0 with 4 chairs.
  - Bedroom corner: bed, pillows, headboard, nightstand with lamp, wardrobe.
  - TV on a console with 3 shelves; 3 framed pictures; 12-book shelf; 2 potted plants; 3 pairs of shoes; entrance mat.
  - One emissive ceiling light; no real-time lights or shadows.
- **Per-house palette:** see the `palette` array (L11691-11696).
- **Signature item per house** (`makeHomeDetails`):
  - id0: grandfather clock with pendulum
  - id1: ceiling fan
  - id2: student desk and chair
  - id3: pet cushion and dresser
- **Collision:** `interiorObstacles` are 6 boxes per house (L11768-11775) and apply to the squirrel only.
- **Motion** (`updateInteriorMotion`, L11944): fan at 0.85 rad/s, pendulum ±0.1 rad at 1.8 rad/s, TV emissive flicker 0.15 ± 0.06.
- **Visibility:** the interior is shown when the player is inside or within 32 u (L12004-12006). The roof and ceiling hide while the player is inside.
- **Squirrel entry** (`houseInteriorEntry` L11958, `handleHouseInteriorInteraction` L11977, `updateHouseInteriors` L12003):
  - Press E within 3.85 u of `door.outside` with pY < 3.6.
  - 0.85 s scripted transit: 0-36% ease to the outside point; held at 35% until the door is passable; 36-62% to the threshold; 62-100% to the inside point.
  - Exit with E within 4.4 u of the inside point.
  - Pouncing is disabled indoors ("Go outside before launching an ambush.", L6484).
- **Humans never appear indoors.** A resident becomes invisible at the inside point. The interior is a safe zone: humans cannot see (`isVisible` is false), cats cannot see or swat, police cannot engage (L8046, L11093-11147), and novelty riders ignore the squirrel.
- Westside old homes 0-3 (`openOldHome` L10203) are squirrel-only garage interiors with no human use.

---

## 7. Bites, crime scenes, witnesses and bystanders

### 7.1 `onSuccessfulBite(n)` chain

Final composition: L7996, then L9271-9286, then L10336-10344.

1. Cancel any kick wind-up (cooldown 12).
2. Hospital staff and patients return here; they have no crime scene.
3. A motorcyclist crashes (§9.4). A cyclist's bike falls over: bike at (1.15, 0.12, −0.6), roll 1.12, body lowered to 0.
4. `scheduleCrimeScene(n)`, then `alarmNearbyWitnesses(n)`.
5. Westside fuel bookkeeping: a bite within 74 u of (−397, 229) counts toward closure (owned by the westside/world spec).

### 7.2 `scheduleCrimeScene(victim)` (L9198-9226) and `updateCrimeScenes` (L9287-9350)

- **Victim:**
  - `injured`, `sceneHot`, `hospital = true` (removed from roaming), state `injured`, speed 0, `crimeOrigin = position`.
  - Red eyes off. Sits down: both legs −1.25, arms splayed ±0.18.
- **Scene:**
  - `{center, radius: 72, ttl: 600 s, stage: nearestRoadStage(victim)}` (L9166-9197 picks the nearest road-centreline stop for the ambulance).
  - Calls `queueMedicalResponse` (ambulance; hospital spec) and `rollIncidentPolice`: 5% → 2 cars and 3 officers; 18% → 1 patrol; else none (L10440, L11011).
  - Calls `gatherAtCrime` (§7.3).
- **First frame:** every visible non-hospital human within 72 u gets `alert ≥ 7` and `reacting ≥ 2.2`; walkers switch to flee.
- **While the victim waits** (not yet picked up):
  - Pinned to `crimeOrigin` (lerp, rate dt·4).
  - Rocks (body roll ±0.06), head bob, guards a knee (left leg −1.13 ± 0.1, right −1.42, arms −0.85 / −1.25).
  - `n.facing` is re-aimed at the squirrel every frame, but `root.rotation.y` is set only once, at the bite (L9215). The seated victim therefore does not visibly turn (inferred bug).
  - Moans every 12-21 s: "Ow! My knee!", "Ohhh... that really hurts.", "I need a doctor!", "Somebody help me, please!". **In practice these never play.** The moan is gated on `sayCooldown <= 0`. `resolvePounce` sets `sayCooldown = 8` with the "hit" line right after the bite, and nothing decrements `sayCooldown` for an actor flagged `hospital` or `injured` (only `updateHumans` L7021, `updateLivingEvents` L11440 and `updateNoveltyCast` L12405 do, and all three skip victims). Verifier finding.
  - **After 120 s injured, the red eyes light (emissive 0.55).**
  - Humans within 20 u keep `alert ≥ 4`.
  - The patrol officer's alert is held ≥ 6.5 if within 36 u of the scene.
  - The scene is removed after 600 s.
- **Victim lifecycle** (ambulance owned by the hospital/medical spec, L10805-10988):
  1. waiting 9-19 s (`Math.random`)
  2. outbound (24-27 u/s)
  3. approach on foot
  4. assess 2.1-5 s
  5. load: lift onto stretcher, `body.rotation.x → π/2`
  6. retrieve: victim hidden, `medicalTransit`
  7. return → hospitalQueue → receive → admit → handoff 5.5 s
  8. **`finishTreatment(n)`** (L10538-10563): victim hidden, injury flags cleared, red eyes off, pose reset, `maxLife R(24,55)`, `witnessUntil = 0`.
  9. `hospital = Boolean(hospitalRole || motorcycle || sceneAssignment !== undefined)`, so a treated roaming pedestrian rejoins the spawn pool.
- **Treatment quirks (inferred bugs to fix, not port):**
  - `body.position` is reset to (0,0,0), so a cyclist rejoins with the body at saddle height 0.
  - `doorEscape` is not cleared; `spawnNpc` clears it later.
  - Event NPCs (`sceneAssignment` undefined) come back with `hospital = false` and join the roaming pool as "softball"/"barbecue" pedestrians.
  - Novelty riders come back invisible and are **never shown again**: `updateNoveltyCast` skips invisible, non-escaped riders forever.

### 7.3 Witnesses: `alarmNearbyWitnesses(victim)` (L9227-9270)

- **Candidates:** visible, non-hospital, uninjured humans within 25 u, sorted nearest first (index `i`).
- **Defender rule:** fewer than 2 defenders so far, and (personality brave, or (i < 4 and wary and idx % 5 === 0)).
  - `defenseUntil = time + 19`, state `defend`, cancel door escape, `kickCooldown = 0.3 + 0.36·i`.
  - Shout if i < 3: "Hey! Get away from them!", "Back off!", "Leave them alone!".
- **Everyone else:**
  - flee at 7.1 (cyclist 8.2)
  - if i < 4, shout "Call an ambulance!", "Look out! Get inside!", "That squirrel bit someone!" or "Get away from it!"
  - if i < 3, `beginHomeRetreat`
- **All candidates:** `alert ≥ 10`, `reacting ≥ 3.4`, `witnessUntil ≥ time + 70`, face the victim.

### 7.4 Emergency bystanders: `gatherAtCrime` (L9703-9742) and `updateEmergencyBystanders` (L9743-9789)

- **Pool:** 7 hidden actors. Each scene takes `2 + floor(rand·3)` = 2-4 that have no assignment.
- **Placement:**
  - Ring angle `(i + 0.33)·2π/n`; start 13.2 u out (8 × 1.65); target 8 u out.
  - If either point is inside a building (+2 margin), use the road stop ± (i−1)·2.8 along x and ±4 in z; failing that, road stop + (6 + 2.6i, 9).
- **Update:**
  - Walk to the target at 1.5 u/s.
  - If the squirrel is within 7 u, recoil directly away at 5.4 u/s.
  - `keepEmergencyActorsOutside` (L12074) prevents walking through buildings (margins 0.65 for houses, 0.6 for commercial).
  - One line after 2.2 + 0.85·i s: "Somebody call an ambulance!", "Stay back — it might still be here!", "Is that another squirrel bite?", "Give them some room!". Each bystander speaks only once per game: `say` sets `sayCooldown = 8`, and nothing ever decrements it for these `hospital=true` actors, so the check at L9772 fails at every later scene (verifier finding).
  - Arms hang −0.13, or raise −1.1 when in danger; small gait.
- **Release:** when the scene expires or the victim becomes invisible (picked up), they are unassigned and hidden.
- They are biteable (non-hospital check in `updatePounceCollision`), but `alarmNearbyWitnesses` ignores them because they carry `hospital=true`.

---

## 8. Extraordinary street cast (v3.6): `createNoveltyResident` and `updateNoveltyCast` (L12132-12553)

One update owner. These actors are not in the pedestrian scheduler (`specialStreetCast`). Shared actor record fields (L12171-12195): `kind` (mime or kid), `speed`, `escapeSpeed`, `origin`, `destination`, `route`, `routeStep`, `repath`, `escaped`, `resetTime`, `reactionTime`, `popped`, `parkedBike`.

| Actor | Ride route (ping-pong) | Ride speed | Escape speed | Reset after station |
|---|---|---|---|---|
| Marcel the Mime | (−94, −8) ↔ (80, −8) | 5.9 | 18.4 | 55 s |
| Ellie | (−54, 17) ↔ (66, 17) | 4.60 | 12.80 | 71 s |
| Theo | (37, −17) ↔ (−88, −17) | 4.95 | 13.25 | 87 s |
| Jules | (−152, 18) ↔ (−32, 18) | 5.30 | 13.70 | 103 s |
| Avery | (−294, 92) ↔ (−294, −126) | 5.65 | 14.15 | 55 s |
| Riley | (−288, −173) ↔ (−288, 102) | 6.00 | 14.60 | 71 s |

Reset time is `55 + (index % 4)·16`, with index 0 for the mime and 1-5 for the kids.

**Spotting** (`noveltySpotSquirrel`, L12317):
- Never when the squirrel is in the sewer, hospital or a house interior, or pY > 6.4.
- Mime: d < 36 and (facing dot > 0.08, or d < 14, or squirrel moveSpeed > 6.5 with d < 17).
- Kids: the same with 24 / 10 / 17.

**State machine** (`n.state`):

```
ride ──spot──► escape ──route done──► entering ──within 1.75 of stationInner──► inside(hidden)
  ▲                                                              │ resetTime elapses (55-103 s)
  └──────────────────── respawn at origin, state ride ◄──────────┘
any state ──bitten──► injured: 'popped' pose (mime: wheel tips 1.12 rad, body to 0, balls hidden; kid: bike falls)
```

- **ride:**
  - Head to `destination` with turn rate 3.65 and speed damp λ 3.2.
  - Within 3 u, swap origin and destination.
  - If blocked by a building (`medicalSegmentBlocked`, footprint +0.92), revert and reverse.
- **spot → escape** (`noveltySpotResponse`, L12332):
  - `alert 32`, `reacting 3.6`, `reactionTime 2.3`.
  - Say: mime "Nope! Police station, now!" or "Oh! That squirrel! Help!"; kids "Look out! Go to the station!", "That squirrel is after us!" or "Come on, get to the police!".
  - The mime also triggers a HUD flash.
- **Escape path** (`novelEscapePath`, L12283):
  - Route to `stationWelcome` = police station (−510, −107) + (0, 20.5) = (−510, −86.5).
  - Built with `medicalWalkRoute`: a visibility graph over building corners (footprint + 2.65), Dijkstra, at most 18 nearby buildings (L10603-10653).
  - If that fails, go around the map rim at z = ±245 via x −318 and −472.
  - The first leg is a burst directly away from the squirrel: 18 u (mime) or 11 u (kids).
  - Waypoint arrival 2.15. A new path is built when the route runs out (L12434). `repath` (set to 5 by `novelEscapePath`) counts down only while a step is blocked by a building, so the first re-path comes after 5 s of accumulated blocking and later ones after every 2 s of blocking (L12497-12504). There is no periodic re-path.
- **Evasion:**
  - While escaping, if the squirrel is mid-pounce within 8.5 u, `reactionTime ≥ 0.55`.
  - While `reactionTime > 0` and the squirrel is within 8 u, strafe sideways at 3.7 u/s (side by index parity), except within 25 u of the station.
- **Kids dismount** within 10 u of the station:
  - Bike hidden; a parked clone is placed at (station.x + ((index−1) % 5 − 2)·3.25, welcome.z + 4).
  - Walk on at 6.8 u/s.
- **entering:**
  - Speed 4.0 toward the threshold (−510, −92.1), then the inner point (−510, −98.2) once the station doors are open > 0.82.
  - Station double doors (L12140-12153): open when anyone escaping is within 23 u or entering. Damp λ 6.4, angle ±1.25 rad.
- **inside:**
  - Hidden.
  - `dispatchCop("A frightened cyclist reported the squirrel at the station!")` once.
- **Animation:**
  - Mime: 4 juggling balls on arcs (x = sin(4.4t + φ)·0.82, y = 5.7 + 1.15·max(0, cos)) and hidden while escaping; wheel spins by distance ÷ 1.63; body sways ±0.055; arms −1.2 ± 0.5.
  - Kids: wheels and crank by distance; pedalling legs ±0.4; arms −0.68.
- **Bug (inferred):** after treatment a novelty rider stays invisible forever (§7.2).

---

## 9. Other human casts

### 9.1 Hospital staff and patients (L4964-5045, L8679-8846, L11644-11677)

Full detail belongs to the hospital spec; the human-actor facts are here.

- **Coordinates:** relative to (HOSP_X, HOSP_Z) = (−356, 353), y = `HOSPITAL_FLOOR` (terrain + 0.42).

| Name | Job | Skin | Uniform | Station offset | Patrol pace | Pursuit |
|---|---|---|---|---|---|---|
| Dr. Ellis | doctor | #d1a988 | #e9eee7 | (−14, −21) | 1.62 | no |
| Nurse Reed | nurse | #855946 | #75b0af | (2, −6) | 1.62 | no |
| Nurse Taylor | nurse | #d6b192 | #83ada3 | (19, −8) | 1.62 | no |
| Guard Miller | guard | #98715a | #4a6772 | (−12, −32) | 1.62 | 3.9 |
| Guard Shaw | guard | #d8b296 | #425e69 | (24, −30) | 1.62 | 3.9 |
| Orderly Lane | orderly | #ad886f | #9dabb3 | (−28, 8) | 1.85 | 2.7 |
| Orderly Park | orderly | #8a624d | #9da9b1 | (29, 24) | 1.85 | 2.7 |
| Ms. Vale | extinguisher | #c9a184 | #bc8172 | (38, −26) | 1.62 | 2.7 |

- **Staff:**
  - Each loops a 4-point circuit (`staffCircuits`, L8693-8742) with 0.24 s pauses. Doorway routing comes from `hospitalPatrolTarget` (L8679).
  - Doctor and nurses tilt clipboards and look down while paused, using the condition `sin(0.23t + i·4.4) > 0.15`.
- **Defenders** (guard, orderly, extinguisher), only while the squirrel is inside:
  - Chase within 15 u.
  - Telegraph when d < 4 (orderly: 7.2): 0.76 s (orderly 1.0), arm raised −1.55.
  - Then `knockPlayer` strength 10.8 if d < 2.45 (orderly 3.6), and `hitCooldown 6`.
- **Patients:**
  - 8 patients, stationed 6.35 u in front of `hospitalBeds[i]`.
  - Bed grid: (HOSP_X − 33 + 22·(i%4), HOSP_Z + 15 + 20·floor(i/4)).
  - 4-point loop at 1.15 u/s with 0.48 s pauses; head sway when paused.
  - Names: Margie, Bernard, Lydia, Walter, Camille, Edgar, Joyce, Toby. Skins cycle #dbb795, #b68a6b, #9c6d55; gowns cycle #c99c83, #8f99af, #a9b793.
- **Gait:** stride freq 8.3 (patients 6.1), legs ±0.42, arms ±0.28.
- **When bitten:** `nextBite = 14 s` cooldown; no crime scene (L9276). Bitten-staff and bitten-patient sets feed the hidden win (`checkUnannouncedEnd`, L8645).

### 9.2 Park walkers and the mourner

These use the standard pedestrian brain on their north lanes (§4.2). There is no grave-visit behaviour; the mourner is just a slow panicky walker on the cemetery path.

### 9.3 Living-community gatherings: `newLivingEvent` and `updateLivingEvents` (L11307-11513)

| Event | Centre | Actors | Offset | Gather radius | Arrival ring |
|---|---|---|---|---|---|
| barbecue | (−66, −84) | 7 "Neighbor n" | 0 s | 7 | 35 × 30 ellipse |
| softball | (66, 356) | 10 "Player n" | 1200 s | 10 | 33 × 25 ellipse |

- **Cycle:** every **2400 s**. Phases:
  - 0-55 s: walk in by linear interpolation from the ring
  - 55-600 s: mill around the post (swirl 0.38 rad/s, amplitude 1.7 for barbecue, 3.5 for softball)
  - 600-655 s: walk out
  - otherwise hidden
- **Movement:** position lerps to the target at rate dt·2.2. These actors do not avoid buildings except when threatened.
- **Props:**
  - 3 cars per event drive from home to parked spots over 48 s.
  - Barbecue: grill, 3 smoke puffs, 2 benches.
  - Softball: 31 × 31 diamond, 4 bases, backstop.
- **Threatened** (squirrel within 16 u, pY < 4.7, not indoors):
  - `witnessUntil +600`, `reacting ≥ 3.5`.
  - Push away from the squirrel at 6.5 u/s (< 7 u) or 4.2 u/s, constrained by `keepEmergencyActorsOutside`. The lerp toward the event target pulls them back, so they hover at a distance (inferred).
  - Lines: "Oh no, it’s that squirrel!", "Everybody, get away from it!", "What the hell is that thing doing here?!", "Get back! It just attacked someone!".
  - Panic animation.
- They are biteable and get the normal crime scene. They never kick and are excluded from witness and defender selection (`hospital=true`).

### 9.4 Motorcyclists (L9560-9682)

| Rider | Lane z | Direction | Speed | First ride | Wait between rides | After crash |
|---|---|---|---|---|---|---|
| Morgan Rider | −5.7 | x 296 → 657 | 10.4 u/s | 19 s | 53 s | 90 s |
| Alex Rider | +5.7 | x 650 → 283 | 11.9 u/s | 83 s | 75 s | 127 s |

- Commercial arterial only.
- **Rider pose:** body (0, 0.4, −0.12), pitch −0.14, arms −0.9.
- **Bite:** always succeeds. `crashMotorcycle` (L9621):
  - rider dropped 1.4 ahead and 5.8 u to the roadside, sideways
  - bike skids 1.8 s, laid over 0.96 rad, hidden after 8 s
  - normal crime scene follows

### 9.5 Ambient figures with no AI

- Waterside walkers: z oscillates ±15 around their post with period about 66 s; flipped 180° by direction.
- Car drivers and trolley passengers: static parts of their vehicles.

---

## 10. Procedural human animation (all sine-driven, no clips)

| Context | Legs | Arms | Head and body | Lines |
|---|---|---|---|---|
| Walk | ±0.52·sin(6t+φ) | ±0.45 counter | head yaw ±0.05 at 1.5 rad/s | L7191-7201 |
| Jogger | freq 10 | | | |
| Cyclist | fixed 0.1 (crank turns by distance) | freq 8 | | |
| Flee | freq 12 | | | |
| Panic (`reacting > 0`) | as gait | raised −2.5 ± 0.45 at 14 rad/s, splayed z ±0.35 | head shake ±0.28 at 13 rad/s; body roll ±0.095 at 11 rad/s | L7196-7201 |
| Kick wind-up | `legs[1]` (+x side, the actor's left) −1.1 − 0.65·(1 − kickWindup), a forward raise from −1.37 to −1.75 | — | — | L7202 |
| Home retreat run | ±0.46 at 13 rad/s | −1.25 ± 0.24 + flail | head ±0.3 | L6968-6973 |
| Injured, seated | −1.13 (± 0.1) / −1.42 | −0.85 / −1.25 | body roll ±0.06, head pitch 0.14 ± 0.09 | L9311-9317 |
| On stretcher | −0.15 | — | body pitch π/2 | L10777-10779 |
| Hospital walk | ±0.42·sin(step), step rate 8.3 (patients 6.1) | ±0.28 | head ±0.07; idle ±0.1 | L8810-8818 |
| Charting | — | `arms[1]` (+x side, the actor's left) −0.54 | head pitch −0.13, clipboard −0.33 | L11662-11668 |
| Hospital telegraph | — | `arms[1]` (+x side, the actor's left) −1.55 | — | L8827 |
| Event (calm / threatened) | ±0.36 / ±0.58 at 7 (softball) or 4 | counter / raised −1.55 | threatened: head ±0.29, body ±0.07 | L11486-11492 |
| Bystander | ±0.24 when moving | −0.13, or −1.1 in danger | — | L9783-9787 |
| Mime | — | −1.2 ± 0.5 at 8.8 rad/s | body sway ±0.055 | L12526-12527 |
| Kid rider | ±0.4 at 10 rad/s | −0.68 | body ±0.035 | L12532-12534 |
| Motorcyclist | — | −0.9 | body pitch −0.14 | L9669-9672 |

`φ` = `n.phase` = R(0, 2π). Brief §2 requires Blender FBX clips. Map these to clips: Walk, Jog, Run/Flee, Panic overlay, Kick (with a 0.58 s wind-up), Defend stance, Sit injured, Lie on stretcher, Charting idle, Cycle, Unicycle, Juggle, Ride motorbike.

---

## 11. Speech: bubbles and browser voices

- **`say(npc, text)`** (L4776-4784):
  - Sets `sayCooldown = 8 s`.
  - Pushes a DOM bubble showing the speaker's name and text. The bubble lives 4.6 s, fades over the last 0.7 s, and is anchored 4.7 u above the root (`updateBubbles`, L7213-7235).
  - Style: cream card, dark border, max width 230 px (shell L20).
- **`speakCitizen`** (L4752-4775): browser SpeechSynthesis.
  - Only while playing, voices are on (`speechOn`, toggled by `voiceBtn` L5708), and the synth is idle.
  - Global cooldown 2.4 s.
  - Voice: English voices excluding the last one used, indexed `idx % count`.
  - Rate `0.98 + (idx % 4)·0.045`; pitch by personality (§3); volume 0.8.
- **`chooseLine`** (L4795-4816), using the `sentences` table (L4734-4746):
  - **surprise** (6.5%): "Oh my God! WHAT IS THAT?!", "What in the world is THAT?!"
  - **spot:**
    - 43%: spot[0] "Oh, God! It’s one of those squirrels!" or spot[1] "OH NO! It’s one of those squirrels!"
    - otherwise filtered: spot[3] "It’s in the trees! IT’S IN THE TREES!" only when the squirrel is really in a tree (branch, trunk or lookout route and pY > 3.2); spot[5] "I TOLD you about those damn squirrels!" only with a companion within 11 u
    - other spot lines: "Get away from me, you little bastard!", "What the hell is WRONG with that squirrel?!"
  - **hit:** "GET IT OFF! GET IT OFF!", "GET IT OFF ME!", "AAAH! SOMEONE HELP!"
  - The **escape** set ("Not today!", "Stay AWAY!", "Oh, absolutely NOT!") is never requested (dead).
- **Other line sets:** see §5.2 (poster), §5.5 (kick), §7.2-7.4, §8 and §9.3. Paramedics: assess and handoff lines (L10727-10749).
- `speakWantedRecognition` (L11286) is unused (dead).
- Mature-language lines exist ("bastard", "hell", "damn") (porting risk, §14).

---

## 12. Yard cats (v1.9): `makeYardCat`, `catSafeMove`, `updateYardCats` (L11514-11641)

- **Instances:**

| Cat | Home | Coat | Light fur |
|---|---|---|---|
| 0 | house 0 + (11, −23) = (−45, −76) | `#80614b` | `#bd9f7e` |
| 1 | house 3 + (−10, +23) = (48, 79) | `#454647` | `#ddd3bd` |
| 2 | house 1 + (−11, −20) = (40, −79) | `#a19e88` | `#ddd3bd` |

  All three are in back yards. Eyes are `#d7e36e`.
- **Model:** ellipsoid body (r 0.72 scaled 0.8×0.52×1.28), head r 0.38, cone ears, 4 legs, two-segment tail group. About 1.3 u tall to the ear tips.
- **Not biteable and not affected by squirrel attacks.** Skipped while the player is in the hospital or sewer.

**State machine** (re-evaluated every frame):

```
seesSquirrel = d < 17.5 && heightAboveGround < 2.8 && |squirrel − home| < 26 && !squirrel.onRoute && !indoors
state = seesSquirrel ? (d < 8 ? chase : stalk) : wander
wander : target = home + (sin(0.31·φ + x)·7, cos(0.23·φ + z)·6) at 1.6 u/s
stalk  : target = squirrel at 3.1 u/s;  chase : 8.5 u/s
if seesSquirrel && d < 3.0 && hitCooldown ≤ 0 → windup 0.68 s (crouch scale.y 0.72, tail flick), HUD "crouches to pounce — JUMP!"
windup end: hit if d < 2.75 && heightAboveGround < 2.4 && !indoors
   hit  → squirrel launched 10.5 u/s away, vy ≥ 3.9, off route, −12 Power, hitCooldown 7, "CAT SWAT!"
   miss → hitCooldown 4, "The cat lunged and missed!"
```

- **Voice:** a growl `fx` at wind-up (cooldown 4.5 s); a hiss when stalking within 10 u (cooldown 6 s).
- **Movement constraint** (`catSafeMove`): the step is rejected if it would enter any house footprint + 1. Turn rate 5. Tail yaw wag ±0.4.
- **Escape:** cats ignore a squirrel on any route, so climbing defeats them.
- `predatorForPlace` names a "cat" as the idle-watchdog predator inside house or shed shelters (L8193). That belongs to the idle spec, not these cats.

---

## 13. Interactions with other subsystems

| Subsystem | Interaction |
|---|---|
| Player / combat | `updatePounceCollision`, `resolvePounce`, `attackWindow`, `officerBatonContact` knockback (also used for kicks), `knockPlayer` (hospital). |
| Infection | `grantInfectionBite` per bite; red-eye tell; hidden win counts bitten staff and patients. |
| Medical / hospital | `queueMedicalResponse`, `updateMedicalResponders`, `finishTreatment`; hospital doors (`hospitalDoorHold`). |
| Police | `rollIncidentPolice` (5% / 18%); `dispatchCop` from the novelty station escape; `sendPosterPolice` from poster recognition; the police station is solid (`commercialBounds`). |
| Traffic | Cars and heavy vehicles brake for visible non-hospital humans: cars check within 3.3 u laterally, from 3.5 behind to 16 ahead (L7442-7450); `seesHazard` for street and heavy vehicles (L7522). Cars freeze if a human is within 3.1 of the next position (L7466). Pedestrians wait for cars within 3.25 or a street-vehicle footprint. The ambulance halts if a pedestrian is within 5 u (L9005). **No vehicle ever injures a human.** |
| Wildlife | Yard dogs raise human alert (L9109-9111). |
| World / lots | `houses` (24) and `commercialBounds` (8) are the only human colliders. Westside homes, estates other than their mansion and guest bounds, quay and mall are not in pedestrian collision. Pedestrians never go there (inferred). |
| HUD | Bubbles, `flash()` warnings (kick, cat, mime), `scoutText` interior prompt, crowd and voice chips. |

---

## 14. Brief deltas (brief §n; addendum A-n)

1. **§4 single actor model.**
   - v5.4 has about 8 different human representations: `makeHuman`, 4 police figure builders, 3 medic builders, river walkers, drivers, passengers.
   - Rebuild all as **one Human actor** (R15 rig) with a Role/Outfit descriptor and a pluggable AI brain. Brains: PedestrianBrain, ResidentBrain, HospitalStaffBrain, EventBrain, NoveltyRiderBrain, BystanderBrain, MotorcyclistBrain, plus the police and medic brains owned elsewhere.
   - A player can possess any of them mid-stride.
   - v5.4's despawn/respawn (21-56 s lifetime, teleporting into lanes, hiding) must become **persistent bodies** that walk off-screen or into buildings, because a player may be inside any body.
2. **§5 population of 35 humans.**
   - v5.4 has 77 actor bodies but keeps 7-14 roamers visible.
   - Target: about 35 or more always-simulated human bodies distributed by role, including the hospital (5 staff slots) and police (5-8 slots). Plus "more bodies than slots" (§4), so keep about 45-60 AI humans (inferred).
   - The `demoCrowd` toggle and pool rotation are not needed.
3. **§8 combat duel.** v5.4 has detection, a 0.58 s kick wind-up, a perfect-counter window (`kickWindup < 0.34`), a 2.4 s dodge cooldown and a binary 95.5% / 3.5% bite roll. The brief adds:
   - a pounce wind-up, commit and recovery
   - zig-zag raising the human's miss chance
   - feints forcing an early flinch or swing
   - human responses flinch, swing, kick, back away and flee, chosen by awareness and nerve
   Map v5.4 to the brief: personality → nerve, `alert`/`witnessUntil` → awareness, `dodge` → flinch, `defend` → back away/guard, `kick` → kick. **Swing is new for civilians** (v5.4 has only police batons and hospital lunges).
4. **§8 vigilantes, 8%.**
   - v5.4: brave personality (4 of 26, plus Tori), and they kick only after witnessing.
   - Brief: 8% of all human actors at any moment have a vigilante streak, approach and kick on sighting, **never flee**, and answer the drone's call.
   - This needs a dynamic `vigilante` flag (re-rolled or assigned to keep 8%) independent of personality.
   - v5.4's defenders (2 per bite) can stay as situational bravery.
5. **§8 health.**
   - v5.4 kicks cost 19 Power and knock back 11 u/s; cats cost 12; nothing kills.
   - Brief: the rodent has health; a kick does not kill but about two kicks without recovery do; regen while sneaking or in a hollow.
   - Kick damage must become a health hit.
6. **§8 house defenders (new).** Three houses get a defender who bursts out when the rodent chases someone inside:
   - two older housewives of different demographic appearance with **rolling pins**
   - one man with a **broom**
   - their blows hit 50% harder
   v5.4 has no equivalent. Closest precedent: the hospital extinguisher woman, with a 0.76 s telegraph, 2.45 reach and 10.8 knock (L8820-8843).
7. **§8 house interiors, 40 houses.**
   - v5.4: 4 enterable houses (ids 0-3) are coded for the squirrel only, but the interior system never activates because `enterableHouses` is empty (see §6.4 correction). Residents vanish at the inside point.
   - Brief: 40 houses with full interiors the rodent can burst into; humans run inside and hide; escape or bite depends on the chase; **must actually run**.
   - Requires indoor human navigation (per-house navmesh or room waypoint graph), hiding spots, door state shared by AI and players, and pouncing allowed indoors (v5.4 blocks it).
   - The 40 houses double as claimable player homes, with per-server remodel points.
8. **§6 humans as the lowest rank.** v5.4 humans have no jobs. Player humans walk, work (hospital, police, shop) and earn credits. AI humans should be seen working shops and similar (inferred).
9. **§8 infection.**
   - v5.4 bite → injury → ambulance → treated → back to the pool; red eyes after 120 s.
   - Brief: biting infects; infected humans are delivered or walk in to the hospital; staff disinfect.
   - Keep the red-eye tell. Add a "walk-in" path for infected AI.
10. **§10 drone.** Vigilante neighbours answer the drone's spot-and-mark; humans need a "summoned to point" goal. This is new.
11. **§11 wildlife.** Cats are not mentioned in the brief. v5.4 cats are fully working and should be retained per §1 ("HTML is the reference for mechanics") unless the designer drops them (open question).
12. **A1 radar and sightings.** Every v5.4 `spotted` transition (L7068), witness alarm (L9227), poster recognition (L7053) and novelty spot (L12332) is a natural **sighting event** to publish as a map marker (position, time, confidence), fading over time.
13. **A2 rank.**
    - "Successful kick" = v5.4's kick-hit branch (L8155-8162). Award rank to the kicking human if a player drives it. AI kicks should also report hits.
    - Police side quests need new AI human behaviours that reuse this cast:
      - *petty argument*: two pedestrians stop face to face. v5.4's 56% pairing (L4946) is a natural source.
      - *fender bender*: drivers must become real actors who step out of cars; v5.4 drivers are baked into car meshes.
      - *burglar*: an AI human breaks into one of the 40 houses, using door and interior navigation.
      - Parking, speeding and stop-sign tickets are owned by traffic.
14. **A3 70/30 avatar blend.**
    - The v5.4 identity surface per human is: body proportion, skin, shirt, random pants, random hair colour, hair bun, role props, personality voice.
    - Stock = role uniform and silhouette. The avatar contributes skin tone, hair or one head accessory, face, and accent colours on trim, tie, scarf or shoes.
    - Mime, kids, hospital and police uniforms must stay readable.
15. **§12 seasons and calendar.** Living events run on a 2400 s real cycle with fixed offsets (0 s, 1200 s). Tie them to the in-game calendar (for example a weekly barbecue and softball days). Cats and pedestrians have no day/night routine in v5.4; the brief's day cycle implies one (inferred).

---

## 15. Porting notes (Roblox)

- **Authority.** All AI brains run on the server: perception, state machines, timers, kick and bite resolution.
  - Clients render, animate and show bubbles.
  - A possessed actor gives its owner network ownership; the server validates kick and bite contacts with the same distance and height tests as v5.4 (1.38 u / 2.65 u, converted to studs).
- **Movement.** v5.4 humans are kinematic (direct position stepping, lane damping, footprint push-out); nothing uses physics.
  - With about 50 players and about 60 AI humans, avoid per-actor `Humanoid:MoveTo` pathfinding every frame.
  - Recommended: Humanoid-based rigs (required so players can possess them), with the server driving AI via `Humanoid:Move()` toward precomputed lane/waypoint targets at 10-20 Hz.
  - Use `PathfindingService` only for escape routes (replacing `medicalWalkRoute`) and indoor navigation, cached per house.
- **Perception scale.** Every check in v5.4 is against the single `player`. In Roblox each human must pick the most relevant threat:
  - the spicy rodent first
  - regular squirrels only near feeders or gardens, if the designer wants that
  Use a spatial grid (cell about 16 u) so each human tests only nearby threats. Run perception at 5-10 Hz with random phase offsets, since v5.4 already staggers via `phase`.
- **Heights.** Replace every absolute-Y test with height above local ground:
  - `player.pos.y < 4`, `< 5.2`, `> 6.4` (L7029, L7050, L12320)
  - door entry `pos.y < 3.6` (L11991; dead in v5.4, see §6.4)
- **StreamingEnabled.**
  - Actors are Models with `ModelStreamingMode = Atomic`. AI keeps running server-side for streamed-out actors; clients must not assume an actor exists.
  - House interiors should be separate streamable models (v5.4 already toggles them within 32 u).
  - Speech bubbles use `BillboardGui` with MaxDistance about 45-60 studs.
- **Scale.** Humans in v5.4 are about 2.09 u, about 5.2 studs, matching R15.
  - Speeds in u/s ×2.5 = studs/s. Walk 0.8-1.6 u/s = 2-4 studs/s, so slow strolling animation is needed. Flee 7.1 u/s = 17.75 studs/s, faster than the R15 default of 16.
  - Kick reach 2.65 u = 6.6 studs; spot radius 14.5 u = 36 studs; cat territory 26 u = 65 studs.
- **Voices.** Browser SpeechSynthesis has no direct Roblox equivalent. Options:
  - pre-recorded line packs per voice type (pitch 0.84 / 1.06 / 1.23)
  - Roblox's text-to-speech audio API if available to the experience (feasibility to verify)
  - bubble chat only
  Keep the global 2.4 s voice cooldown and the 8 s per-actor cooldown. Filter or replace mature lines per Roblox community standards ("bastard", "damn", "hell").
- **Bugs not to port:** see §7.2 (treatment resets), §5.5 (kick facing not rendered), and §4.1 (pairing ignores hide timers). Also the flee clamp of [−260, 260] applied to the cemetery lane (x 306..628), which drags a fleeing mourner west (inferred quirk, L7117-7124).
- **Freezing.** v5.4 freezes all pedestrians while the player is in the sewer or hospital, and hospital actors beyond 150 u. A multiplayer server cannot do this. Simulate everything continuously and use LOD (lower tick rate) for actors far from every player.
- **Determinism.** Use `Random.new(seed)` per server. v5.4 mixes a seeded stream with `Math.random`; exact sequences need not be reproduced.

---

## 16. Open questions for the designer

1. **Who do AI humans fear?** Only the spicy rodent, or also regular (player) squirrels? If both, how much less?
2. **Vigilante 8%:** fixed people, or re-rolled per spawn or day? Do vigilantes still dodge? Do they swing (fists, bags) as well as kick?
3. **Defender identities:**
   - Which 3 of the 40 houses get the rolling-pin and broom defenders?
   - Do they also defend outdoors, like v5.4's witness defenders?
   - Are v5.4's 12 named residents (Donna, Frank, Mrs. Abbott, …) kept as the core houses' families?
4. **Indoor chase outcome:** what decides "escape vs bitten" inside (locking a door, a hiding-spot timer, reaching a back exit)? Can humans lock doors against the rodent?
5. **Pedestrian lifetime:** v5.4 pedestrians vanish after 21-56 s. Should Roblox pedestrians have commutes or destinations (home → shop → park) instead? This is recommended for the actor model (inferred).
6. **Novelty cast:** keep Marcel the Mime and the 5 kid cyclists as unique named NPCs? Can a player possess the mime? Should kids be possessable at all, given child-avatar concerns?
7. **Living events:** keep the barbecue (−66, −84) and softball (66, 356) gatherings, and on what calendar? Should more event types be added for the expanded lots (school recess, church, market)?
8. **Cats:** keep the three yard cats (not in the brief)? Should they also threaten regular squirrels and the fox?
9. **Hospital roster:** v5.4 has 8 named staff, but the brief has 5 player slots. Do AI staff fill the unheld slots (backfill per §4), with player-possessable doctor, nurse, guard and orderly bodies?
10. **Speech:** voiced lines, bubbles only, or both? Is mature language acceptable for the target rating?
11. **Wanted posters:** they appear after 9 bites (code: `hits > 8`, L7059/L11279), but the comment at L11226 says 15. Which threshold is intended in Roblox, and is it per-rodent-run or per-server?
12. **Injured humans who are not collected:** in v5.4 the scene lasts 600 s, but the victim stays until the ambulance arrives. Should infected AI walk to the hospital on their own if no ambulance comes (brief §9 "walk in")?

---

## Added by verifier

Items in scope that the extraction missed or misdescribed. All line numbers refer to `reference/v5_4_game.js` unless marked v4.1.

1. **House interiors are dead code in v5.4 (and v4.1).**
   - `enterableHouses` (L11788-11790) filters on `h.indoorGroup`, which is assigned only inside `furnishOriginalHouse` (L11690). That function is called only on `enterableHouses` (L11791).
   - The list is therefore always empty. The squirrel cannot enter houses 0-3, no interior props exist, and `updateInteriorMotion`, `houseInteriorEntry`, `handleHouseInteriorInteraction` and `updateHouseInteriors` never act. The minified build and v4.1 (L11466-11469) are identical.
   - Resident door retreat is unaffected: `houseDoors` are built in `buildHouse`.
   - For Roblox, treat §6.4 as design intent. Brief §8 asks for 40 enterable houses anyway.
2. **Lost v4.1 feature: crowd accessories (`makeTownPeopleMoreDistinct`, v4.1 L12704-12735, called from `createWorldLifeEnhancements` v4.1 L12790/L12796).** It is absent from v5.4. Every `humanoids` entry got one head or body accessory by `idx % 5`:
   - 0: flat cap with brim (box 0.95×0.1×0.72 plus a 0.67×0.27×0.65 crown on the head)
   - 1: round cylinder hat (r 0.44-0.49, h 0.31)
   - 2: dark glasses (two 0.31×0.23 lenses and a bridge)
   - 3: back pack with strap
   - 4: scarf (collar cylinder plus hanging tail, colour `#ba744c`, `#9a8faf` or `#c0a565` by `idx % 3`)
   - plus a side bag `#8b7453` when `idx % 7 === 0`

   Hats come from `#87765a #385a73 #8b4f4b #6b7d63 #ba9877`. This fits brief A3, where the avatar contributes one head accessory, and should be restored as part of the human identity surface (§14 item 14).
3. **Speech cooldown starvation (L4777, L7021, L11440, L12405).**
   - `say()` sets `sayCooldown = 8`. Only `updateHumans` (non-hospital actors), `updateLivingEvents` (uninjured event NPCs) and `updateNoveltyCast` (uninjured riders) decrement it.
   - So the injured-victim moans (L9318-9330) never play, because the bite's "hit" line has just set the cooldown.
   - Each emergency bystander speaks at most once per game (L9772).
   - Roblox should use a per-actor timer that always ticks.
4. **Seated victim does not visibly turn** toward the squirrel: `n.facing` is updated (L9337) but `root.rotation.y` only once, at L9215.
5. **Bitten emergency bystander conflict.** `updateEmergencyBystanders` (L9743-9789) has no `injured` check, so an injured bystander is still steered toward its `sceneTarget` and re-posed every frame. Meanwhile `updateCrimeScenes` pins it to `crimeOrigin`. When the original scene ends the bystander is hidden even though it is now a victim, and the injured-actor wrapper (L9364-9367) forces it visible again. Do not port.
6. **Hatch-drop ambush window.** Dropping from the hospital's overhead duct hatch (`dropFromHatch(true)`, L8535-8550) opens a 2.5 s `attackWindow` (versus 0.78 s for a normal pounce, L6496), using the same `attackAlert` snapshot and `resolvePounce` path. It matters for hospital staff and patient bites.
7. **Unreachable despawn bounds.** The world clamp x ∈ [−265, 671], z ∈ [−241, 436] (L7173-7174) runs before the despawn test (L7203), so only `x > 670` can trigger the out-of-bounds despawn. The other three edges never fire, and `maxLife` is the real despawn driver.
8. **Car freeze applies to every visible humanoid.** The braking scan (L7442-7450) skips `hospital` actors, but the move veto at L7466 does not. Seated victims, bystanders, event NPCs and hospital-flagged riders can therefore freeze a car that never braked.
9. **Dead constant:** `WITNESS_MEMORY_SECONDS = 600` (L10442) is never read. The 600 s values are literals at L7052, L7055 and L11464.

## Verification log

Checked against `reference/v5_4_game.js` (and v4.1 where noted). OK = matches code; FIXED = corrected in this file; UNVERIFIABLE = not decidable from code.

1. §1.1 77 `makeHuman` actors, idx ranges and creation lines (NPC_DEFS 0-25 … kids 72-76) — OK (L4730-4733, L4990, L5019, L9563, L9686, L11370, L12161).
2. §1.1 NPC_DEFS composition (12 residents, 8 walkers, 1 jogger, 3 cyclists, 1 skater, 1 mail) — OK (L4493-4520).
3. §1.2 incident police 3 officers, 5% / 18% roll — OK (L10440-10441, L10999-11016).
4. §1.2 precinct guards circle r 3 at 0.21 rad/s — OK (L10309-10314).
5. §1.2 waterside walkers 8, period about 66 s — OK (L14102-14114, L14155-14157).
6. §2.1 body scale R(0.87,1.13)×0.59, head top about 3.55 → 2.09 u — OK (L4588-4589, L4600-4602).
7. §2.1 part dimensions and pivots (torso, hips, neck, head, arms, legs, eyes) — OK (L4594-4625).
8. §2.1 pants and hair palettes, bun when idx%4===0 — OK (L4592, L4602, L4604).
9. §2.2 mail, cyclist, skater props — OK (L4672-4724).
10. §2.2 hospital guard cap, stretcher 0.48 at 2.1 u, extinguisher tank — OK (L5004-5013).
11. §2.2 kid riders body ×0.76, helmet, bike ×0.82 — OK (L12268-12281).
12. §3 personality pitch 1.23 / 0.84 / 1.06, rate 0.98 + (idx%4)·0.045 — OK (L4769-4771).
13. §3 roster counts wary 9, panic 8, bluster 5, brave 4 — OK (L4494-4519).
14. §3 hospital `i%3 ? brave : wary`, events `i%4===0` brave — OK (L4990, L11377).
15. §4.1 cap 14 / 7, cadence 1.75 / 5 s, pairing 56%, offsets 2.1 / (1.6, 1.9), speed ×0.93 — OK (L4928-4960).
16. §4.1 pairing ignores `hiddenInHomeUntil` — OK (L4947-4949).
17. §4.1 boot spawns idx 0, 14, 15, 20, 21, 23, 24, 26-28 — OK (L4911-4924).
18. §4.1 maxLife R(21,51) then R(24,56) — OK (L4651, L7207).
19. §4.2 resident access walk 52%, start and goal — OK (L4866, L4875-4883).
20. §4.2 commercial lane idx 15/18/21/25, z ±17.4 by parity, x R(400,635) — OK (L4871-4874).
21. §4.2 the 12 sidewalk lanes and their fixed values — OK (L4817-4830).
22. §4.3 goal steps R(21,65) / R(37,95), clamps, WORLD_HALF − 45 = 225 — OK (L399, L4840-4864).
23. §4.4 hospital simulated within 150 u, not in duct — OK (L9050, L8766).
24. §4.5 "both events overlap 10 s out of 2400 at most", ceiling 62 — FIXED (events never overlap, [0,655) vs [1200,1855); ceiling about 55).
25. §5.2 dodge: attackWindow, alert > 1.5, d < 5.4, cooldown 2.4, timer 0.38, 8.6 u/s — OK (L7083-7095, L7158-7161).
26. §5.2 flee 22 u, clamps [−260,260] / [385,655], 7.1 / 8.25, recover at alert < 2 — OK (L7110-7130).
27. §5.2 traffic wait 3.25 / 0.55, turn clamp 4 rad/s, world clamp — OK (L7150-7172).
28. §5.2 building collision "6 commercialBounds" — FIXED (6 → 8: L732, L793, L906, 2×L2694, 2×L2747, L11224).
29. §5.3 perception formulas (4 / 4.7 / 5.2 heights, 0.28 cone, 14.5·radar capped 20, 6.8 peripheral, noise 2.5/4.7 and 8.6, radar ×3) — OK (L7027-7051).
30. §5.3 hedge patches and garden (115, 341) — OK (L3573-3579, L3590-3591); hedge test extents added.
31. §5.3 squirrel speeds 1.65 / 8.0 / 16.8, ×0.6 on tree — OK (L6618-6621).
32. §5.3 yard dog bark alert ≥ 3 within 12 u — OK (L9100-9111).
33. §5.4 contact 1.38 / 2.0, dy (−0.35, 2.7/3.2), attackWindow 0.78 — OK (L6496, L6560-6561).
34. §5.4 alert > 0.45 → 3.5%, else 95.5%, motorcycle 100% — OK (L6513-6518).
35. §5.4 perfect counter kickWindup < 0.34 and aim·to > 0.72 → gold coin, kickCooldown 12 — OK (L6509, L6519-6525).
36. §5.4 infection +3.6 / +6.2 / +5.7 — OK (L8634-8641).
37. §5.5 kick ready conditions (d < 3.7, dy < 1.7, attackWindow ≤ 0, spotted) and 0.58 s wind-up — OK (L8166-8178).
38. §5.5 kick release: cooldown 2.6 / 6.0, hit d < 2.65, dy < 1.6, dot > 0.55, knock 11, −19 Power — OK (L8149-8161, L8012-8023).
39. §5.5 "Right leg rotates back" — FIXED (legs[1] is the +x leg, the actor's left, and it raises forward; negative rotation.x moves the foot to +Z).
40. §5.5 HUD "kicked the squirrel away!" attributed to `officerBatonContact` — FIXED (the flash is in `handleKickWindup` L8162).
41. §6.1 retreat eligibility 38 u, side waypoints w/2+1.6 and d/2+1.6, 17 samples, outside.z − sign·1.25 — OK (L6887-6916).
42. §6.2 speeds 4.9 / 2.65, arrival radii 0.65 / 0.22 / 0.42, hide 16-28 s, door.hold 3.1 / 2.2 / ≥ 1.2 — OK (L6923-6962).
43. §6.3 door hinge, leaf 2.24×3.32×0.14, open λ 7.2, 1.35 rad, passable ≥ 0.86 — OK (L1136-1139, L6977-6986).
44. §6.3 door waypoint z table, all 12 values recomputed from `buildHouse` (front = −faceSign·d/2, ×0.82) — OK (L1144-1146, L1248-1251).
45. §6.4 the four interiors exist and are enterable — FIXED (dead code: `enterableHouses` is always empty, L11690 vs L11788-11791).
46. §6.4 furniture list, 6 obstacles, fan 0.85, pendulum ±0.1 at 1.8, TV 0.15 ± 0.06, entry 3.85 / 3.6, exit 4.4, transit 0.85 s — OK as code (L11703-11775, L11944-11951, L11958-12002), but dead per item 45.
47. §7.2 scene radius 72, ttl 600, first-frame alert ≥ 7, reacting ≥ 2.2 — OK (L9221, L9289-9300).
48. §7.2 red eyes at 120 s with emissive 0.55 — OK (L9331-9335).
49. §7.2 victim "Faces the squirrel" — FIXED (facing is updated but `root.rotation.y` is not; no visible turn).
50. §7.2 moans every 12-21 s — FIXED (annotated: they never play because of `sayCooldown` starvation).
51. §7.2 ambulance waiting 9-19 s, outbound 24-27, assess 2.1-5, handoff 5.5 — OK (L10482, L10820, L10846, L10950).
52. §7.2 `finishTreatment` maxLife R(24,55), body.position reset, hospital recomputed — OK (L10538-10563).
53. §7.3 witnesses within 25 u, ≤ 2 defenders, defenseUntil +19, kickCooldown 0.3 + 0.36i, flee 7.1 / 8.2, witnessUntil +70 — OK (L9227-9268).
54. §7.4 bystander pool 7, 2-4 per scene, ring 8 × 1.65, 1.5 / 5.4 u/s, within 7 u — OK (L9684-9789).
55. §7.4 bystander line — FIXED (annotated: at most once per game).
56. §8 rider routes, speeds 4.6 + 0.35i, escape 12.8 + 0.45i, mime 5.9 / 18.4, reset 55 + (i%4)·16 — OK (L12199-12266, L12469).
57. §8 spotting 36/14/17 (mime), 24/10/17 (kids), pY > 6.4 gate — OK (L12317-12331).
58. §8 station points (−510, −86.5 / −92.1 / −98.2), doors λ 6.4 ±1.25 rad, open > 0.82 — OK (L10050, L12137-12139, L12549-12552).
59. §8 "Repath every 5 s" — FIXED (re-path only after 5 s, then every 2 s, of accumulated blocking, or when the route runs out).
60. §8 juggling arcs, wheel ÷1.63, kid pedalling ±0.4 at 10 rad/s — OK (L12514-12534).
61. §9.1 staff table (names, skins, uniforms, offsets), paces 1.62 / 1.85 / 1.15, pursuit 3.9 / 2.7 — OK (L4968-4987, L8792-8800).
62. §9.1 telegraph 0.76 / 1.0, trigger 4 / 7.2, reach 2.45 / 3.6, knock 10.8, cooldown 6 — OK (L8820-8843).
63. §9.1 bed grid and patient circuits — OK (L3973-3983, L8750-8763).
64. §9.3 event centres, counts, rings 35×30 / 33×25, 2400 s cycle, 55/600/655 phases, swirl 0.38, amplitudes 1.7 / 3.5, threat 16 u, 6.5 / 4.2 — OK (L11307-11492).
65. §9.4 motorcycle lanes ±5.7, speeds 10.4 / 11.9, waits 19/83, 53/75, 90/127, crash 1.4 / 5.8, skid 1.8 s, 0.96 rad, hidden after 8 s — OK (L9562-9681).
66. §11 bubble life 4.6, fade 0.7, anchor 4.7; surprise 6.5%, spot 43%, tree pY > 3.2, companion 11 u; escape set unused — OK (L4776-4816, L7213-7235).
67. §11 crowd chip text "up to eleven" / "about five" — OK (L5690-5699).
68. §12 cat homes, coats, chase/stalk/wander 8.5 / 3.1 / 1.6, sees 17.5 / 2.8 / 26, windup 0.68, hit 2.75 / 2.4, knock 10.5, vy 3.9, −12, cooldowns 7 / 4 — OK (L11516-11640).
69. §13 car braking box 3.3 / −3.5 / 16, freeze 3.1, ambulance 5 u — OK (L7442-7467, L9005-9008).
70. §16 poster threshold `hits > 8` vs comment "15" — OK (L7059, L11226, L11279).
71. JSON: 87 entries parse; entries 0-28 name, role, skin, shirt and personality match source line by line (script check) — OK.
72. JSON: hair bun missing on 13 actors with idx%4===0 (28, 32, 36, 40, 44, 48, 52, 56, 60, 64, 68, 72, 76) — FIXED.
73. JSON: hospital staff 29-36 personalities, skins, uniforms, offsets — OK (L4969-4987).
74. JSON: patient skins and gowns cycling by i%3 — OK (L5025-5026).
75. JSON: motorcyclists 45-46 skins, jackets, schedule — OK (L9563-9620).
76. JSON: bystanders 47-53 skins and shirts by i%4 — OK (L9686-9695); one-line-per-game note added (FIXED).
77. JSON: event NPC colours and personalities 54-70 — OK (L11370-11378).
78. JSON: kids 72-76 skins, shirts, helmets, frame colour by idx%4 — OK (L12245-12266).
79. JSON: novelty "always present" — FIXED (never shown again after treatment, L12404).
80. JSON: police and medic figures 77-83 colours and positions — OK (L7983-7990, L10080-10091, L10999-11008, L11212-11220, L10515-10520, L10680-10692).
81. Line 3 / §6 scope wording "the four walk-in interiors" — OK as design intent; see item 45.
82. Brief mapping §14 item 7 — FIXED (notes that the v5.4 interiors are inactive).
