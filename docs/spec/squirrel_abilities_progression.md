# Spicy Rodent: Player Abilities, Progression and UI (v5.4 porting spec)

Subsystem owner: `squirrel_abilities_progression`.
Source of truth: `reference/v5_4_game.js` (every bare line number below refers to this file), plus `reference/v5_4_shell_head.html` (written "shell:NNN") for HUD markup.
Units: HTML world units (1 unit is about 2.5 studs, +Y up). Time is in seconds. Angles are in radians unless marked otherwise.
Labels: "(inferred)" means derived or computed from the code, not stated literally. "(proposal)" means a suggestion for the Roblox build, not HTML behaviour.

Neighbouring subsystems this spec touches but does not own: route/rail movement and leaps (movement), human AI and spotting (NPC), police, hospital and duct geometry, infection spread, traffic and the swept collision test, wildlife (rabbits, normal squirrels, cats, dogs, fox and deer from v4.1), mall and quay.

---

## 1. Player state (single-player HTML)

The HTML has exactly one playable actor, the spicy rodent ("small articulated zombie squirrel", 5126). Its state lives in one object, `player` (5127-5153):

| Field | Initial | Meaning |
|---|---|---|
| `pos` | (-36, 0.31, -36) | Gameplay position at **foot level**. The visual mesh follows it with bounded smoothing. |
| `vel` | 0 | Velocity, units/s. |
| `yaw` | 0 | The animal's facing. This is separate from the camera's `yaw` (global, starts at PI). |
| `grounded`, `rail`, `railT`, `railDir`, `transferCooldown` | | Movement state (movement subsystem). |
| `moveSpeed` | 0 | Smoothed scalar speed. Drives the pounce speed tier and the animation cadence. |
| `focus` | false | True while stalking (first person). |
| `points` | 0 | **Power** (the score). |
| `hits` | 0 | Successful bites (humans, officers, normal squirrels). |
| `inactiveSeconds` | 0 | Seconds since the last bite (Power decay clock). |
| `boostRemaining` | 0 | Chili rush seconds left. |
| `cooldown` | 0 | Pounce re-use lockout. |
| `attack` | 0 | Pounce pose timer. It is decremented but never read for gameplay (6495, 6606). |
| `attackWindow` | 0 | Seconds during which a pounce can still connect. |
| `attackAlert` | null | `Map<npcIdx, alert>` snapshot taken at launch. Decides "unaware". |
| `attackTarget` | null | The NPC the current pounce resolved against. |
| `cameraCommit`, `committedAirborne` | | Camera commit after leaps and pounces. They also block stalk mode. |
| `turnLean` | 0 | Visual banking. |
| `alive` | true | False on any end condition. |
| `nearRoute`, `visible` | | Helpers. |

Extra flags added later on the same object: `inSewer`, `inHospital`, `inDuct`, `trunkNormal`.

Global run counters (5456-5460): `chiliesFound`, `squirrelCoins`, `goldCoins`, `totalCoinsEarned`. Hospital and infection counters (8413-8419): `infectionOwn`, `infectionFromSquirrels`, `secondsSinceBite`, `won`, `bittenStaff`, `bittenPatients`.

**There is no health value in v5.4.** Every hostile hit costs Power and applies a knockback (section 11).

---

## 2. Squirrel model: gameplay-relevant visuals

### 2.1 Scale and dimensions
- `SQUIRREL_VISUAL_SCALE = 0.335` (5155), applied to the whole group (5157). The comment reads "exactly 50% of the v0.4 squirrel size; movement speed stays agile" (5154).
- Local-space parts before scaling:
  - Body: sphere r 0.55 at (0, 0.39, -0.04), scaled (0.79, 0.67, 1.51) (5171-5172).
  - Head: sphere r 0.36 at (0, 0.62, 0.65), scaled (0.79, 0.84, 1.06) (5173-5174).
  - Belly countershade: #c2a78a (5176).
  - Ears: r 0.145 balls at y 0.96, with dark cone tips reaching y 1.135 + 0.14 (5188-5192).
  - Eyes: r 0.057, emissive red, at (±0.205, 0.72, 0.886) (5193).
  - Teeth: two boxes at z 1.16 (5198-5201).
  - 18 fur tufts (5207-5217).
  - Four leg pivots at (±0.29, 0.18, ±0.46), each with 3 claws (5219-5233).
  - Six whiskers (5234-5247).
  - A 22-segment tail (5249-5253).
- World-size estimates (inferred, local value x 0.335):
  - Back or shoulder height is about 0.25 units (about 0.64 studs).
  - Head top is about 0.31 units. Ear tips are about 0.43 units.
  - The body ellipsoid alone is about 0.56 units long. Nose to rump (head and body, no tail; nose front at local z 1.29, body rear at z -0.87) is about 0.72 units. Tail reach is about 0.45 units behind and 0.6 units above.
  - For comparison, HTML humans are about 2.06 units tall (`makeHuman` body scale 0.59 x U(0.87, 1.13), head at 2.9 local; 4588-4598). That is about 5.2 studs, which matches R15.
  - The brief's "about 1.2 studs at the shoulder" is therefore about **1.9 times** the HTML squirrel, relative to humans.
- Colours:
  - Fur: #87694d. Secondary: #725b48. Dark (legs, ear tips): #3f3d37.
  - Pale fur: #c6ae8c. Snout: #514a41. Teeth: #e5dbb8.
  - **Eyes: #be2f25 with emissive #ad1e16.** Emissive intensity is 0.92 normally and 1.65 during chili rush (5162-5170, 6848). Glowing red eyes are the zombie identity cue.
- Face assembly: head, ears (with ear tips), eyes, eye highlights, snout, nose, teeth and whiskers sit under one `sqFace` group so the face turns as a unit (5180-5206; every part added to `sqroot` after `faceBaseline` at 5186 is re-parented, which includes the ears). Head yaw follows the camera offset: `clamp(angle(yaw - player.yaw) * 0.38, ±0.4) + sin(t*1.8)*0.035` (6850-6856).

### 2.2 Tail (`updateTail`, 5254-5267)
The tail is procedural and driven by time only. It has 22 segments with u = i/21.
- Sway: `x = sin(t*4.2 + u*4) * (0.035 + u*0.18)`.
- Height while climbing a trunk: `y = 0.26 + u*0.11`. This lays the tail flat against the bark.
- Height otherwise: `y = 0.43 + u*1.38 + sin(u*PI)*0.34`. This is the raised question-mark tail.
- Depth: `z = -0.5 - u*0.84 + u*u*0.06`.
- Thickness: `0.075 + sin(u*PI)^0.8 * 0.33`. Segment scale is (thick, thick*0.95, 0.15 + thick*0.78). `rotation.x = -0.48 + u*0.54`.
- The tail does **not** react to velocity or acceleration. On the menu it animates at 0.7x time (16019).

### 2.3 Foot-contact settling (`settleSquirrelFeet`, 5269-5304)
- At boot, the 8 bounding-box corners of every mesh under the body and the four leg pivots are cached (5270-5281).
- Each frame, the code poses the rig, transforms those corners to world space, and computes `lift = max(surface(x,z) + 0.017 - cornerY)` (5294-5301). It then raises the whole squirrel by `lift`.
- `squirrelSurfaceAt` is the maximum of the outdoor surface, the mall surface, and the river surface (river only if `player.pos.y >= riverSurface - 0.5`, i.e. the squirrel is not more than 0.5 below the water surface; there is no upper limit) (5283-5290).
- Settling runs only when `onGroundSurface` is true (6803-6809, 6874): not on a rail, grounded, not in the hospital or sewer, and `|pos.y - surface| < 0.7`. In that case the visual Y is also snapped to the surface.
- This is **purely cosmetic**. Gameplay uses `player.pos` only (6810).

### 2.4 Visual follow and pose rules (in `updatePlayer`, 6769-6878)
- **Visual position.** On a trunk, the visual sits outside the bark by the tapered radius plus 0.28, or radius plus 0.2 for poles and gutters, and faces into the bark. On wood tops it rises by `visualOffset` (default 0.5, lookout 0.61). On wires it rises by 0.22.
- **Smoothing.** The visual lerps toward its target at rate 23 (17 during a route bridge). It snaps if more than 2.5 away, or more than 1.6 away while on a rail (6811-6816).
- **Bank.** `turnLean` follows `clamp(-turnRate*0.035, ±0.31)` at rate 12 (6818-6824).
- **Cadence.** `moveSpeed * (rail ? 0.7 : 2.85) * (rush ? 1.14 : 1)` (6825).
- **Gallop bob.** When speed > 1.3: `sin(t*cadence) * (ground ? 0.022 + min(speed,17)*0.0011 : 0.042 + min(speed,17)*0.002)` (6826-6833).
- **Body pitch (`sqroot.rotation.x`).**
  - Trunk: `lerp(-0.83, -1.43, smoothstep(heightAboveTerrain, 0.25, 2.4))`.
  - Pounce window active: -0.16, nose down.
  - Stalking: +0.05.
  - Otherwise a gait rock of ±0.022 on the ground or ±0.034 elsewhere (6840-6846).
- **Squash and stretch.**
  - Y scale is 0.9 while stalking, 0.92 while sprinting, and 1 otherwise.
  - Z scale is 1.13 during a pounce window (stretch) (6847-6849).
  - Face pitch is -0.05 while stalking and -0.17 while pouncing (6857).
- **Legs.**
  - On a trunk: front -0.26 and back +0.22 base, stepping ±0.16 when speed > 1, splay `side*0.12`.
  - Stalking: legs held at 0.12.
  - Otherwise: diagonal-pair gait `sin(t*cadence + (front?0:PI) + (side>0?0.9:0)) * (0.35 on ground / 0.4 elsewhere)` when speed > 1 (6858-6872).
- **Visibility.** `squirrel.visible = !player.focus` (6875). The mesh is hidden in first person.

---

## 3. Controls

Input handlers are at 5585-5689, mouse look at 5596-5609, and E-priority at 5666-5670 plus the overrides at 10330 and 11998.

| Input | Action | Notes / lines |
|---|---|---|
| W/S or Up/Down | Forward and back. On rails and in ducts only W/S count. | 6612-6615 |
| A/D | Strafe on the ground. With a rail: choose a fork on a trunk, a sibling bough on a branch, or a junction on wires/roofs. Fires on key-down only. | 5659-5665 |
| Shift (L/R) | Sprint | 6616 |
| Space | Traversal leap (`leap`), only when grounded or on a rail (no air leap, unlike the pounce). In a duct at an open upper hatch it drops through. | 5681, 5922-5940 |
| Left click | **Pounce** (`attemptPounce`), once per button-down. If the pointer is not locked, the click requests pointer lock instead. | 5585-5595 |
| Right mouse (hold) | **Stalk / first person** (`focusMouse`) | 5610-5618 |
| F | Toggles stalk (`focusToggle`). Not listed in the hints panel. | 5682 |
| E (press) | Interact, in priority order: house interior, then old westside home, then mall fountain, then hospital doors/vents, then sewer grate/stand. If none applies: take the selected fork, else attach to the nearest route. | 5666-5670, 10331, 11999 |
| E (hold) | Chew a vent (`updateChewing` polls `keys.has("KeyE")`) | 8867-8897 |
| Q | Drop off the current rail: `vel.y = 3.3`, `cameraCommit = 0.32`, committed airborne | 5672-5680 |
| 1 / 2 / 3 | Cycle hat / jacket / pants at the sewer fashion stand | 5671, 8371 |
| P | Pause toggle | 5643-5647 |
| H | Toggle the controls panel | 5648 |
| C | Recenter the camera behind the squirrel | 5653-5657 |
| L | Diagnostics overlay | 5649-5652 |
| M / Tab / K | HUD all on/off, HUD preset cycle, HUD panel editor. These work even before play starts. | 5630-5641 |
| G | Display settings panel. It pauses the game. Esc closes it. | 13410-13417 |
| Esc | Releases pointer lock (browser). When the lock is lost, focus is cleared. | 5576-5583 |
| Mouse move | `yaw -= dx * sens * (1 + 0.18*boost)`, where `boost = min(1.25, hypot(dx,dy)/35)` and dx, dy are clamped to ±90. `sens` is 0.0025 while stalking and 0.00315 otherwise. Pitch is clamped to [-0.6, 1.07]. On a trunk, mouse X also orbits `trunkNormal` by -dx*0.004 (outside stalk). | 5596-5609 |

**Hints panel text** (shell:139): "W A S D Move · SHIFT Sprint · SPACE Leap · E Grab / selected branch · A / D Choose bough while climbing · Q Drop from route · RIGHT MOUSE First-person stalk · LEFT CLICK Pounce anytime · ESC Cursor · P Pause · 1 / 2 / 3 Fashion choice near sewer stand · E HOLD Chew vent · SPACE / CLICK Drop from upper hatch · M HUD all · TAB HUD mode · K HUD panels".

**Start screen** (shell:155-193):
- Quick key grid: WASD Move · SHIFT Sprint · SPACE Jump · MOUSE Look · E Grab / enter · CLICK Pounce.
- A collapsible "How to play" section with these headings: "Climbing & movement", "Stealth & survival" ("Hold the right mouse button to stalk, then left-click to pounce. Unaware people are easier to surprise. People may evade or defend themselves after an attack. Being run over by a moving vehicle ends your run…"), "Places & objectives", and "Display & sound".
- Three start buttons:
  - START PLAYING: spawns at (-36, 0.31, -36).
  - EXPLORE THE MALL: `startAtMall`, (MALL.x, floor+0.18, 238) (15104-15124).
  - EXPLORE THE RIVER: `startAtRiver`, (780, bankY+0.18, 51) (14169-14183).

---

## 4. Movement numbers that abilities depend on (summary)

These are owned by the movement spec. They are restated here because pounce, stalk and rush modify them.

| Quantity | Value | Line |
|---|---|---|
| Ground base speed: walk / sprint / stalk / duct (walk, sprint) | 8.0 / 16.8 / 1.65 / 2.8, 3.8 | 6618-6621 |
| Rail speed: walk / sprint / stalk | 7.2 / 12.2 / 1.2 | 6668-6671 |
| Tree-route multiplier (trunk, branch, bridge, lookout) | x0.6 | 6617, 6621, 6671 |
| Chili rush multiplier (ground, rail and duct crawl, **not while stalking**) | x1.6 | 6620, 6670 |
| Speed smoothing rate: stalking / other | 11 / 17 | 6622-6626 |
| Ground acceleration: grounded / air | 23 / 4.2 | 6717 |
| Turn rate: stalking / other | 19 / 25 | 6721 |
| Friction with no input: grounded / air | 13 / 1.15 | 6723 |
| `SQUIRREL_GRAVITY` | 30 units/s^2 | 6472 |
| Leap (Space) | forward 16.5 (18.5 in rush), up 12.8, apex 2.73 | 5915-5921 |
| Auto-grab of a trunk while walking into it | only if `attackWindow === 0`, W held, speed > 0.45, trunk within 2.0 | 6630-6642 |
| World clamp | x in [-586, RIVER.endX-4 = 1146], z in [-560, NORTH_LIMIT-4 = 436] | 6765-6766 |

---

## 5. Stalk / "Predator's Eye" (first person)

### 5.1 Activation rule (6580-6587)
```
focus = (rightMouseHeld || fToggle)
        && !inDuct && playing
        && !committedAirborne && cameraCommit == 0
        && rail.kind != "trunk"
```
- Losing pointer lock, window blur, or `clearControls` resets both inputs (5576-5583, 5685-5689, 13316-13321).
- `commitToAir` (leap or pounce) forces `focus = false` (5912).
- After a committed landing, `cameraCommit >= 0.35` (6758-6761). Stalk cannot re-engage for 0.35 s, which works as a de facto recovery (inferred).
- Stalk is allowed on branches, wires, roofs and fences, but never on trunks.

### 5.2 Effects while stalking
- Speed: ground 1.65, rail 1.2. Chili rush does not apply. Smoothing rate 11.
- **Silent.** Human "noise" detection triggers only when `moveSpeed > 2.5` while stalking, versus `> 4.7` otherwise (7033). Top stalk speed is 1.65, so a stalker never makes noise (inferred).
- When not moving, the animal turns to face the camera direction at rate 11 (6727).
- Mouse sensitivity is 0.0025 instead of 0.00315.
- Camera: the eye sits at `player.pos + (0, 0.27 + sin(t*1.65)*0.005, 0)` and looks 24 units along yaw/pitch. Damping 17, FOV 61 (7314-7317, 7397, 7419-7420). The squirrel mesh is hidden.
- **Aim guide** (`updateAimPath`, 7237-7288). It is visible only while stalking with no active pounce window.
  - It simulates `pounceVelocity()` under gravity 30 for 34 samples (`t = 0.06 + 0.05*i`).
  - It draws a faint line (#c9ddb0, opacity 0.33) and a ring landing marker (r 0.24-0.3, #e4f1d4, opacity 0.54) where the arc meets `getGroundAt`.
- HUD while stalking:
  - Body classes: `body.focus` shows the vignette, crosshair, `#aimState` ("ESTIMATED LEAP / POUNCE PATH") and `#reticleHint` ("SPACE TO LEAP · LEFT CLICK TO POUNCE").
  - The focus label shows "PREDATOR'S EYE" with "FIRST PERSON · slow, silent aim / Space to leap · left-click to pounce" (6587-6595).
- Stalk pose (only visible to others; matters for multiplayer): body Y scale 0.9, pitch +0.05, legs fixed at 0.12, face pitch -0.05.
- Concealment that helps stalking (7034-7042, NPC spec): inside the community-garden box (`|x-115| < 27`, `|z-341| < 15`, y < 2.4) or next to a hedge patch, **while** `moveSpeed < 3.4`, the squirrel cannot be spotted at all.

---

## 6. Pounce

### 6.1 Launch (`attemptPounce`, 6482-6505)
Guard: `cooldown > 0 || !playing || paused || !alive` returns with no effect.

1. **Inside a walk-in house interior:** flash "Go outside before launching an ambush." and abort. Pouncing indoors is impossible in v5.4.
2. **In a duct:** call `dropFromHatch(true)`. If no open overhead hatch is near, flash "Find and CHEW the high hatch before pouncing."
3. Otherwise:
   - Set `cooldown = 0.7`, `attack = 0.38`, `attackWindow = 0.78`, `attackTarget = null`.
   - Snapshot `attackAlert = {idx: alert}` for every visible humanoid.
   - `launchFromVisibleRoute()`: if on a rail, the launch starts from the visible mesh position.
   - Set `vel = pounceVelocity()`, leave the rail, set `grounded = false`.
   - `commitToAir(heading)`: snaps the camera behind the heading (`cameraCommit = 0.52`), forces stalk off, hard cut. Sound blip 640 Hz.

Rules that follow from this code (inferred from what is checked and what is not):
- There is **no grounded check**. A pounce can be fired mid-air, and it **replaces** the current velocity. With the 0.7 s cooldown this gives an air-dash. The help text says "Pounce anytime" (shell:139, comment at 5584).
- **There is no wind-up.** The commit is instantaneous on click.

### 6.2 Launch vector (`pounceVelocity`, 6473-6481)
```
p        = clamp(cameraPitch, -0.54, 0.9)
speed    = (focus ? 12.4 : moveSpeed > 12 ? 13.5 : 11.3) * (rush ? 1.12 : 1)
vertical = 3.45 + sin(p) * 2.1
heading  = attackHeading()   // player.yaw; on a trunk = outward bark normal (5900-5906)
vel      = (sin(h)*speed*cos(p), vertical, cos(h)*speed*cos(p))
```
Derived numbers (inferred, gravity 30):
- Vertical takeoff is 2.37 to 5.10, so the apex is only 0.09 to 0.43 units. The comment calls it a "low, forward-biased squirrel bound" (6470).
- At default pitch 0.12 the flight time on flat ground is about 0.25 s and the airborne range is about 2.8 units (ground), 3.0 (stalk) or 3.3 (sprint).
- **Ground slide.** While `attackWindow > 0`, neither the input branch nor the friction branch runs (6711, 6722). After touchdown the horizontal velocity is kept, until the window expires. Total lunge reach is roughly `speed x 0.78 s`, about 8.8 to 10.5 units on open ground (11.8 with rush and sprint), minus collisions (inferred).
- When the window ends without a contact, flash "Missed. Look down the landing path before committing." (6607-6610). Ground friction then resumes.

### 6.3 Contact test (`updatePounceCollision`, 6555-6569)
This runs every movement substep after motion (6768) while `attackWindow > 0` and not in a duct. The first match wins, in this order:

1. **Humanoids.**
   - Skip a humanoid that is invisible, injured, already the `attackTarget`, or a hospital actor with `nextBite > 0`.
   - Hit if horizontal distance < 1.38 and `dy = player.y - npc.y` is in (-0.35, 2.7).
   - For a riding motorcyclist: distance < 2.0 and dy in (-0.35, 3.2).
   - On a hit, call `resolvePounce(n)`.
2. **Officers** (`tryPolicePounce`, 8083-8135). This step is skipped in the sewer, hospital, or a house interior. See 6.5.
3. **Wildlife** (`tryWildlifePounce`, 8946-8978). This step is skipped in the sewer or hospital.
   - Rabbit within 2.25 (3D): it always escapes ("Too quick! … No reward"). Its `escapeUntil` is set to 4.
   - Uninfected normal squirrel within 1.42 (3D): it is **always** infected.
     - Rewards: +90 Power, +1 hit, +10 coins (and total), `inactiveSeconds = 0`, `secondsSinceBite = 0`, `idleTime = 0`.
     - Flash "ANOTHER SQUIRREL TURNS! +90 Power · +10 Coins".

Every resolution sets `attackWindow = 0`, so one pounce can bite at most one target.

### 6.4 Resolution against a human (`resolvePounce`, 6506-6554)
```
to   = flat unit vector squirrel->npc
aim  = (sin(player.yaw), 0, cos(player.yaw))
perfectCounter = 0 < npc.kickWindup < 0.34 && aim.dot(to) > 0.72
alreadyAlert   = attackAlert[npc.idx] > 0.45          // snapshot at launch
successful = npc.motorcycle.active
          || perfectCounter
          || (alreadyAlert ? rand < 0.035 : rand < 0.955)
```
- **Perfect counter.** On success: +1 **gold** coin, the NPC's kick is cancelled (`kickWindup = 0`, `kickCooldown = 12`), flash "PERFECT COUNTER! +1 GOLDEN SQUIRREL COIN". Kick wind-up starts at 0.58 and counts down, so the counter window is the **last 0.34 s** of the wind-up, from 0.24 s after it starts (inferred).
- **Success.**
  - `pts = player.pos.y > 4 ? 150 : 100`. This uses **absolute world Y**, not height above terrain (inferred quirk).
  - `points += pts`, `hits++`, `inactiveSeconds = 0`, `squirrelCoins += 10`, `totalCoinsEarned += 10`.
  - Call `onSuccessfulBite(n)` (6.6), then `grantInfectionBite(n)`, then `refreshPowerUI()`.
  - NPC says its "hit" line. Flash "Successful ambush! +{pts} Power · 10-minute fade timer reset".
  - NPC set to `state = "flee"`, `alert = 7`, `reacting = 2.5`.
  - **Recoil:** `vel *= 0.08`, `vel.y = 1.9`.
- **Failure.**
  - NPC set to `flee`, `alert = 7`, `reacting = 2.9`, and says its "spot" line.
  - Flash "Batted away! They saw you coming."
  - **Bounce back:** `vel *= -0.12`, `vel.y = 3.7`.
  - No Power loss.
- `Math.random` is used. It is not seeded or deterministic.

### 6.5 Resolution against officers (`tryPolicePounce`, 8083-8135)
- Candidates: the visible patrol officer, incident officers, station reinforcements, and precinct guards.
- Contact: horizontal distance <= 1.85 and dy in [-0.3, 2.8].
- `surprised = squirrelBehindOfficer (toSquirrel . officerForward < -0.3) || dy > 1.35 || officer.stun > 0`.
- Success chance: **0.88 if surprised, otherwise 0.035.**
- **Success.**
  - Officer: `stun = 5.5`, `windup = 0`, `hitCooldown = 6`. The patrol cop's alert is raised to at least 30.
  - Rewards: +130 Power, +1 hit, +10 coins (and total), `inactiveSeconds = 0`, `grantInfectionBite({})` (+3.6 infection).
  - Recoil: `vel *= 0.14`, `vel.y = 2.6`. Flash "SURPRISE BITE! {name} stunned — escape before backup arrives."
- **Failure.**
  - Officer: `windup = 0`, `hitCooldown = 0`, so the officer can strike again immediately.
  - Squirrel: thrown away at 8 units/s with `vel.y = 3.2`. Flash "{name} anticipated your attack!"

### 6.6 `onSuccessfulBite` chain
The function is redefined twice. Calls run oldest first.
1. Base (7996-8002): if the victim was winding up a kick, cancel it (`kickCooldown = 12`).
2. v1.2 (9271-9286). Hospital patients and staff return here.
   - A biker crashes (`crashMotorcycle`). A cyclist's bike falls over.
   - `scheduleCrimeScene(n)`: the victim becomes injured and is removed from roaming, a medical response is queued, a scene of radius 72 is created with ttl 600, and police are rolled (18% single, 5% multi; 10440-10441).
   - `alarmNearbyWitnesses(n)`: witnesses within 25 get `alert >= 10`, `reacting >= 3.4`, `witnessUntil = now + 70`.
     - Up to 2 become **defenders**: brave personality, or wary with `idx % 5 == 0` among the nearest 4. They get `state = "defend"`, `defenseUntil = now + 19`, and a staggered `kickCooldown = 0.3 + i*0.36`.
     - The rest flee. The nearest 3 try to retreat home.
3. v1.5 (10336-10344): a bite within 74 of the westside gas station counts toward that station's closure.

Note: `tryPolicePounce` and `tryWildlifePounce` do **not** call `onSuccessfulBite`.

### 6.7 Overhead hatch pounce (hospital; `dropFromHatch`, 8535-8555)
- Available only in a duct, within 2.9 of the open upper vent, and above `HOSPITAL_FLOOR + 4`.
- Spawn at the vent at `HOSPITAL_FLOOR + 7.6 - 1.15`.
- Velocity: `aim * (attack ? 7.4 : 2.3)` horizontally (aim = camera forward), and `-5.7` vertically.
- An attack drop sets `cooldown = 0.86`, `attack = 0.55`, **`attackWindow = 2.5`**, and takes a fresh alert snapshot.
- Hospital actors are never processed by `updateHumans`, so their `alert` stays 0 and bites on them land at 95.5% (inferred).
- A pulsing landing ring is shown 4 units ahead of the vent (4241-4252).

---

## 7. Awareness: what "unaware" means

Owned by the NPC spec. Summarised here because it decides bite success.

- Every roaming human has `alert`, a countdown in seconds that decays by 1/s (7022).
- A human counts as **aware** for a pounce if its `alert` at launch was **> 0.45** (6513).
- **Spotting** rule (7027-7051), evaluated per human per frame:
  - `isVisible = !inHouseInterior && (squirrel.y < 4 || dist < 4.7)`.
  - `inView = dir . facing > 0.28` (about a 147 degree cone, inferred).
  - `noise = moveSpeed > (focus ? 2.5 : 4.7) && dist < 8.6 && dy < 22`.
  - `radar = 3` if the human is inside an active crime scene or remembers the squirrel (`witnessUntil`), otherwise 1.
  - ```
    spotted = !concealed && (
      (isVisible && dist < min(20, 14.5*radar) && (inView || dist < 6.8) && squirrel.y < 5.2)
      || (noise && dist < min(16, 10.3*radar)))
    ```
- First spot: `state = "flee"`, `alert = 8`, `reacting = 3`. The human may run home.
- Other sources of alert:
  - Dog bark sets `alert >= 3` within 12 (9109-9111).
  - Crime-scene bystanders get `alert >= 7` (9296) or `alert >= 4` near the injured (9343).
  - Witnesses of a bite get `alert >= 10`.
  - Any pounce outcome sets the target's `alert = 7`.
- **Height defeats detection.** Above world Y 4 the squirrel is visible only within 4.7. Above 5.2 it is never seen, only heard if noisy. Waiting quietly in the canopy is the intended stealth play (comment 7030).
- **Dodge** (7083-7095, 7164-7167). If a spotted, alerted (`alert > 1.5`) human is within 5.4 while `attackWindow > 0`, it sidesteps at 8.6 units/s for 0.38 s (dodge cooldown 2.4). The dodge can carry it out of the 1.38 contact radius, so the dodge is the only real-time "reaction window" in the HTML.

---

## 8. Human counterplay: kick wind-up and defenders (8137-8184)

- **Ready to kick** requires all of:
  - `defenseUntil > now` (an assigned defender), or a brave human with `witnessUntil > now`;
  - not running home, not injured, `kickCooldown <= 0`;
  - `dist < 3.7` and squirrel height above the human < 1.7;
  - **`player.attackWindow <= 0`**, spotted, and the squirrel not in the sewer.
- **Wind-up:** `kickWindup = 0.58`, `state = "kick"`, speed 0. Says "Get back!", "I said get away!" or "Back off!". Flash "{name} prepares to kick — dodge or counter!" (within 6.1).
- **Strike** at the end of the wind-up:
  - Kick cooldown becomes 2.6 for a committed defender or 6.0 otherwise. State becomes `defend` or `flee`. `alert = 7`.
  - It **hits** only if all of these hold: `dist < 2.65`, squirrel height above the human < 1.6, the human's facing points at the squirrel (dot > 0.55), and **the squirrel is not mid-pounce** (`attackWindow <= 0`).
  - On a hit: `officerBatonContact(npc, 11)` (-19 Power, knockback). Flash "{name} kicked the squirrel away!"
  - Otherwise, within 5.1: "{name}'s kick missed — move away or counter."
- **Defend state.** The defender moves to stand 2.4 from the squirrel at speed 5.6. Defence ends when `defenseUntil` passes, when the squirrel is not spotted, or when it is more than 17 away (7096-7109).

---

## 9. Bite rewards and infection hooks

| Target | Chance | Power | Hits | Coins | Gold | Infection | Lines |
|---|---|---|---|---|---|---|---|
| Unaware human (ground) | 95.5% | +100 | +1 | +10 | 0 | +3.6 (patient +5.7, staff +6.2) | 6515-6534, 8634-8644 |
| Unaware human with squirrel at world Y > 4 | 95.5% | +150 | +1 | +10 | 0 | as above | 6527 |
| Aware human (alert > 0.45 at launch) | 3.5% | as above | | | | | 6518 |
| Perfect counter (during kick wind-up) | 100% | as above | +1 | +10 | **+1** | as above | 6510, 6519-6525 |
| Motorcyclist | 100% | as above | | | | | 6516 |
| Officer, surprised / head-on | 88% / 3.5% | +130 | +1 | +10 | 0 | +3.6 | 8104-8118 |
| Normal squirrel | 100% | +90 | +1 | +10 | 0 | starts that squirrel's 25-minute share (max 25/7 % each) | 8957-8975, 8849-8866 |
| Rabbit | 0% | 0 | 0 | 0 | 0 | 0 | 8948-8955 |

- Hospital actors cannot be bitten again for 14 s (`nextBite = 14`, 8640).
- Every successful bite on a human or officer, and every squirrel infection, resets `inactiveSeconds` (the Power-fade clock).
- Bite count thresholds visible to other systems:
  - `hits > 8` (9 or more): wanted posters appear on every 7th utility pole, and passers-by can recognise the squirrel (7059-7067, 11264-11284). The comment at 11226 says 15, but the code says more than 8.
  - Every 10 hits: bite dance (section 10).

---

## 10. Bite dance (`animateBiteDance`, 10345-10369)

- **Trigger.** Each time `floor(hits/10)` exceeds the last celebrated decade (that is, at 10, 20, 30… bites): `danceSeconds = 2.1`, flash "{hits} BITES · THE SQUIRREL DOES A VICTORY DANCE!" (2.4 s), sound 680 Hz.
- It runs in `updateScenery` after gameplay, only while playing and not paused (15982). It is **non-blocking**: movement and pouncing continue.
- Pose, with `t = 2.1 - remaining` and envelope `k = min(1, 6t, 6*remaining)` (1/6 s ease in and out):
  - `sqroot.rotation.y = sin(12t) * 0.78 * k` (spin wiggle)
  - `sqroot.rotation.z += sin(15t) * 0.17 * k` (roll)
  - `sqroot.position.y += |sin(10t)| * 0.19 * k` (hops)
  - `sqHead.rotation.y += sin(7t) * 0.24 * k`
- When not dancing, the function forces `sqroot.rotation.y = 0` every frame.

---

## 11. Damage-like effects (knockback and Power loss)

v5.4 has **no health and no death from hits**. Every hostile contact applies a knockback and sometimes a Power loss.

`officerBatonContact(p, knock)` (8012-8024):
- Velocity away from `p` at `knock`, with `vel.y = max(vel.y, 3.1)`.
- Detaches from the rail and sets airborne.
- **-19 Power** (floored at 0). Sound.

`knockPlayer(dir, str, msg)` (8665-8677):
- Ignored in a duct or when dead.
- Detaches from the rail, `attackWindow = 0`, `committedAirborne`, `cameraCommit = 0.38`.
- `vel = (d*str, min(3, 0.22*str), d*str)`, hard camera cut, flash. **No Power loss.**

| Attacker | Trigger range | Wind-up (telegraph) | Hit range | Knock speed | vy | Power | Cooldown after | Lines |
|---|---|---|---|---|---|---|---|---|
| Brave or defending pedestrian kick | < 3.7 | 0.58 s | < 2.65, facing dot > 0.55, dy < 1.6, squirrel not pouncing | 11 | >= 3.1 | -19 | 6.0 (2.6 if defender) | 8137-8184 |
| Patrol officer baton | < 3.6 (while alert) | 0.54 s | < 2.85, dy < 2.4 | 14 | >= 3.1 | -19 | 2.0 | 8050-8070 |
| Incident officer baton | < 3.4 | 0.48 s | < 2.9, dy < 2.3, not stunned | 12 | >= 3.1 | -19 | 2.4 | 11134-11153 |
| Station reinforcement shove | < 2.3 (squirrel within 24 of station) | none | < 2.3, dy < 2.3 | 10 | = 2.3 | 0 | 4.4 | 11158-11186 |
| Precinct guard shove | < 2.3 (squirrel within 34 of station) | none | < 2.3, dy < 2.4 | 11 | = 2.4 | 0 | 4.1 | 11189-11207 |
| Hospital guard / extinguisher | < 4 (inside hospital) | 0.76 s | < 2.45 | 10.8 | 2.38 | 0 | 6 | 8819-8843 |
| Hospital orderly (stretcher) | < 7.2 | 1.0 s | < 3.6 | 10.8 | 2.38 | 0 | 6 | 8819-8843 |
| Yard cat swat | < 3.0 (seen, in territory) | 0.68 s (crouch) | < 2.75, height above ground < 2.4 | 10.5 | >= 3.9 | -12 | 7 (miss 4) | 11585-11636 |
| Officer anticipates a pounce | contact | none | | 8 | 3.2 | 0 | officer can swing at once | 8124-8131 |
| Human bats away a pounce | contact | none | | vel x -0.12 | 3.7 | 0 | | 6550-6552 |
| (v4.1 only) Fox lunge | < 2.15 (fox hunting) | warning at < 6 | < 2.15 | 9 | >= 3.5 | -17 | 4.8 | v4_1:12632-12649 |

Escapes (each one works only against the attackers whose conditions above include it):
- Being higher than about 1.6 to 2.4 above the attacker.
- Being mid-pounce, **against pedestrian kicks only**. Kicks require `attackWindow <= 0` (8159, 8174). Patrol and incident batons, cat swats and hospital staff do not check `attackWindow` (8052-8058, 11137-11143, 11600-11605, 8828-8834), so they can hit a lunging rodent. `knockPlayer` also zeroes `attackWindow`, while `officerBatonContact` does not.
- Getting out of range before the wind-up ends.
- The sewer. Cops and kicks are disabled there.

---

## 12. Power, heat and chili rush

Constants (5308-5312):

| Name | Value | Meaning |
|---|---|---|
| `CHILI_COUNT` | 8 | Peppers per run |
| `POWER_DECAY_INTERVAL` | 600 s | Real active seconds without a bite before a decay tick |
| `POWER_DECAY_RATE` | 0.15 | Fraction lost per tick |
| `RUSH_DURATION` | 30 s | Rush seconds added per pepper |
| `RUSH_SPEED` | 1.6 | Declared, but the code hard-codes 1.6 at 6620 and 6670 |

`updatePowerAndHeat(dt)` (5506-5526):
- `dt` is real time, clamped to 0.2 per frame, and only accumulates while playing, unpaused and alive (15943, 15999-16012).
- `inactiveSeconds += dt`. On each full 600 s (the clock wraps by subtracting 600, so it keeps ticking): if `points > 0`, `lost = max(1, ceil(points*0.15))` and `points = max(0, points - lost)`. At 0 Power nothing is flashed. Flash "The hunger returns. No bite for 10 minutes: −{lost} Power (15%)."
- `boostRemaining -= dt`. When it reaches 0, flash "The chili rush has faded. Find another hidden pepper."
- The HUD refreshes every 0.2 s.

Rush effects (while `boostRemaining > 0`):

| Effect | Value | Line |
|---|---|---|
| Ground and rail speed | x1.6 (not while stalking) | 6620, 6670 |
| Pounce speed | x1.12 | 6476 |
| Leap forward speed | 18.5 instead of 16.5 | 5919 |
| Gait cadence | x1.14 | 6825 |
| Eye emissive | 1.65 instead of 0.92 | 6848 |

Rush stacks: +30 s per pepper, capped at **90 s** (5492).

Power has **no gameplay effect** beyond display. The STATE label is FERAL below 600, RABID at 600 or more, and SUPER at 1500 or more. The bar fills at 1500 (5468-5469).

---

## 13. Hidden chilis (5306-5455, audit 10393-10435)

- **Seed.** Per run, `crypto.getRandomValues`, falling back to time XOR random (5313-5321). It is independent of the town seed, so a refresh moves the peppers.
- **Composition**, exactly 8 (5440-5447):
  1. **4 tree peppers**, one per `treeSpec` tree. The trees are BUR OAK (-34, -33), AMERICAN ELM (32, -37), SYCAMORE (-37, 29) and RED MAPLE (34, 34) (1694-1736).
     - Even-index trees: a random trunk route at t in [0.34, 0.82], offset (±0.32, 0.15-0.35, ±0.32).
     - Odd-index trees: a random "bough" route at t in [0.32, 0.77], offset (±0.25, -0.24 to 0.1, ±0.25) (5389-5404).
  2. **2 elevated peppers**, chosen from 4 shuffled generators (5405-5420):
     - roof route, t in [0.27, 0.76], +0.32 Y;
     - fence route, [0.18, 0.78], +0.34;
     - trampoline guardrail, [0.11, 0.87], +0.28;
     - a "phone line" wire, [0.2, 0.78], -0.25 (hanging under).
  3. **1 garden pepper**, always. x = 125 + U(0, 5.5), z = 331 + U(0, 11), at terrain + 0.7 ("among the garden Tabasco peppers"). Garden centre is GARDEN_X 115, GARDEN_Z 341 (3590-3591).
  4. **1 random yard pepper** from 8 fixed spots:
     - (-65, 0.67, -80) barbecue; (43, 0.68, 83.3) doghouse; (44, 0.67, -73) pool chair; (-67, 0.66, 87) guesthouse;
     - (75, 0.69, 83.5) lawnmower; (-68, 0.67, -69) porch; (72, 0.71, 78.3) bins; (39, 0.69, -83) smoker (5431-5438).
- **Model.** A procedural lathe chili (13 rings x 10 sides), calyx and stem (5334-5385).
  - Colours in order: #d7241b, #ff5a17, #ce251e, #e6ac27, #d13023, #e84d10, #ad1b23, #f5a232. Emissive 0.14.
  - Random yaw and scale 0.85-1.15. It bobs ±0.065 at 1.45 rad/s and rocks ±0.09.
- **Accessibility audit** (10395-10434). It throws if the count is not 8.
  - Trunk peppers are moved to 1.4 from the nearest treeSpec centre at the same bearing, with y >= terrain + 1.0.
  - Ground peppers: y >= ground + 0.43, otherwise ground + 0.7. If a pepper lies inside a commercial footprint or a vehicle hitbox, shift it (+5.2, +5.2) to terrain + 0.75.
  - Route peppers: if more than 2.5 from the nearest sample of the same route kind, snap to that sample + 0.3 Y.
- **Pickup** (5483-5505). 3D distance from `player.pos` to the model: < **2.2** for trunk peppers, < **1.4** otherwise.
  - On pickup: `found`, hidden, `chiliesFound++`, rush +30 s (cap 90), **+1 gold**, `idleTime = 0`.
  - Sound 990 Hz. Flash "SECRET CHILI FOUND! n/8 · +60% speed for Ns". The eighth flashes "ALL EIGHT CHILIS FOUND! No more will appear this run."
  - A pickup does not reset the Power-fade clock.

---

## 14. Currencies

| Currency | Var | Sources | Sinks | Persistence |
|---|---|---|---|---|
| Power | `player.points` | bites (+100/+150/+130/+90) | decay 15% per 600 s without a bite; -19 kick/baton; -12 cat | run only |
| Squirrel Coins | `squirrelCoins` | +10 per successful human/officer/squirrel bite; +1 per brass Galleria coin (24 placed) | -35 per fashion item; -1 per fountain toss (E within 11.5 of the fountain, 0.7 s cooldown, purely cosmetic) (15002-15025) | run only |
| Lifetime coins | `totalCoinsEarned` | the same sources as Squirrel Coins | never spent; gates the fashion stand at 150 | run only |
| Gold | `goldCoins` | +1 per chili (8 per run); +1 per perfect counter; +1 for the single upper-gallery gold coin at (MALL.x, gallery+0.6, MALL.z-50) (14755) | -3 per golden fashion item (index 8) | run only |
| Hits | `player.hits` | successful bites | none | run only |

- Galleria coin layout (counted from the placement loops):
  - 2 per shop x 6 shops on the ground floor (14631, 14780-14784);
  - 4 per side x 2 sides on the upper gallery (14753);
  - 1 gold (14755);
  - 4 around the fountain plaza (14976-14982).
  - Total: 24 brass and 1 gold. Pickup radius 0.95 (15068-15090).
- v4.1 only (lost in v5): 10 **nut caches**. Inspect one with E within 2.85 for `3 + (index % 3)*2` coins (3, 5 or 7) and +5 Power, and it resets the Power clock (v4_1:12237-12320, coordinates 12737-12748). Restoring nut caches is foraging scope per the brief. They are listed here only because they fed coins and Power.

---

## 15. Sewer fashion stand (8232-8411, UI 9079-9089)

- Stand at `standPoint = (130, sewerFloorY + 0.2, 264)`. Model: a 2.3 x 3.2 x 1.3 box (#ac8058), 3 stone shelves, and a gold cone "mini hat" on top (3780-3786).
- Proximity: in the sewer and within 6 horizontally sets `nearShop` and shows `#shopHint` (9079-9081).
- **Slots and catalogue** (3 slots x 10 items; index 8 is the "gold" item):

| k | Hat (slot 0) | colour | Jacket (slot 1) | colour | Pants (slot 2) | colour |
|---|---|---|---|---|---|---|
| 0 | Bandana | #b82d23 | Red hoodie | #b8352e | Cargo shorts | #826e53 |
| 1 | Fedora | #655b49 | Trench coat | #797667 | Dark jeans | #34393d |
| 2 | Pointed gnome cap | #6f8753 | Mossy vest | #6a8752 | Brown shorts | #8b7758 |
| 3 | Straw hat | #c3a86b | Yellow jacket | #d7b557 | Plaid shorts | #b9aa78 |
| 4 | Red cap | #d23526 | Flame-print jacket | #d54124 | Black shorts | #232c2b |
| 5 | Wheel collar | #667b62 | Denim jacket | #496681 | Work pants | #858276 |
| 6 | Toy police hat | #263a5d | Blue police jacket | #334e78 | Badge shorts | #44546c |
| 7 | Pepper necklace | #b7442e | Striped poncho | #b77245 | Striped shorts | #aa674a |
| 8 | **Golden crown** | #d9bd66 | **Gold jacket** | #ddc36e | **Royal shorts** | #cfb46c |
| 9 | Skull cowboy hat | #25262b | Black skull jacket | #333337 | Checkered shorts | #625854 |

- Meshes are attached to `sqroot`, so they inherit the gait (8329-8360). Hat shapes by k:
  - k in {1, 3, 6, 8, 9}: crown cylinder r 0.34/0.39 h 0.24 at (0, 1.2, 0.56) plus a brim r 0.52/0.42.
  - k = 2: cone r 0.32 h 0.66 at y 1.43.
  - k = 7: a ring of 8 beads at y about 0.61.
  - Otherwise (k = 0, 4, 5): a box 0.74 x 0.18 x 0.4 at (0, 1.09, 0.64).
- Jacket: ellipsoid r 0.51, scale (0.85, 0.66, 1.33), with two shoulder balls.
- Pants: 4 boxes 0.24 x 0.2 x 0.43 at the leg positions.
- **Flow** (8371-8411):
  - `1/2/3`: only when in the sewer and `nearShop`. Sets `fashionSlot` and advances `selectedStyle[slot] = (+1) % 10`, so the first press shows item 1. Flash "SELECTED {SLOT}: {name} · E to buy / equip".
  - `E` within 6 of the stand calls `buySelectedFashion`:
    1. If `totalCoinsEarned < 150`, the stand is locked: "earn N more Squirrel Coins from bites". This also blocks **re-equipping owned items** (inferred from the order of checks).
    2. If the item is not owned: k = 8 costs 3 gold, any other costs 35 Squirrel Coins. If the player cannot afford it, flash the price and stop. Otherwise pay and add to `owned`.
    3. Set `equipped[slot] = k`, update meshes, save, flash "PURCHASED / EQUIPPED {name}!".
  - Selecting an item never unequips. There is no unequip action.
- Shop hint text when unlocked: "{SLOT}: {name} · {3 gold | 35 Squirrel Coins} · E buy/equip · 1/2/3 cycle categories. Owned outfits persist." When locked: "Unlock at 150 earned Squirrel Coins (N to go). Bites pay 10."

---

## 16. Sewer (3726-3786, 7871-7949)

- **Layout:** an L-shaped tunnel. Floor at `sewerFloorY = -3.4`, which is **below** the terrain surface.
  - Grate A at (123, 334), corner at (123, 264), grate B at (200, 264). The constants are `SEWER_X1 = 123`, `SEWER_Z1 = 334`, `SEWER_X2 = 200`, `SEWER_Z2 = 264` (3727-3734).
  - Leg A to corner is 70 long. Corner to B is 77 long.
- **Geometry per leg** (3741-3758):
  - Floor slab 5.8 wide at floor - 0.16. Walls at ±2.85, 4.6 tall. Cream trim stripe at ±2.63, floor + 2.75. Ceiling slab at floor + 4.7.
  - A metal post every 9 units. Two strip lights at (123, 281) and (165, 264), floor + 3.1.
- **Grates** (3759-3766): metal disc r 2.1 at terrain + 0.17, 5 bars, and an amber label (#e5b56c, 4.2 x 1) placed 3.2 units +Z of the grate.
- **Entry and exit** (`handleInteraction`, 7914-7949):
  - From the surface: press E within 5 (horizontal) of A or B and within 3 of terrain height there.
  - Inside: E within 6 of the stand buys (this takes priority). E within 5 of A or B exits. Elsewhere: flash "Follow the L-shaped tunnel. E at a grate or the fashion stand."
- **`teleportSewer(exit)`** (7892-7913):
  - Toggles `inSewer`, clears the rail, velocity, attack window and air state.
  - Inside position: (grate.x, floor + 0.25, grate.z - 0.85 for A or - 0.55 for B).
  - Outside position: (grate.x, terrain + 0.3, grate.z + 2.5).
  - Hard camera cut, `idleTime = 0`, flash ("SEWER ENTRY · Follow the L-shaped tunnel. Fashion stand at the corner." or "BACK ABOVE GROUND · Eight peppers are still one-time only.").
- **Movement constraint** (`constrainSewer`, 7884-7891): after free motion, clamp the horizontal position to within **2.2** of the nearest point on the two-segment polyline. Ground is `sewerFloorY + 0.25` (6741-6742).
- **While in the sewer:**
  - Pedestrians, cars, wildlife, cats, ambulances and traffic do not update, and fatal traffic is disabled (15948-15957, 15773-15774).
  - The patrol cop and kicks are inactive (8027, 8176). Cop and kick hits are impossible (inferred).
  - Fog near/far is 15/53, camera far 65, background #373f38, exposure 1.1 (9116-9131). District tag "UNDERGROUND · SEWER".
  - The idle predator here is a "small alligator" (8188).

---

## 17. Chewing vents (hospital; 8556-8602, 8867-8897, vents 4118-4125)

- Five vents, relative to `HOSP_X = -356`, `HOSP_Z = 353`:
  - (-38, -12) height 2.8, **first**;
  - (-9, -12) 2.8;
  - (-9, +25) 2.8;
  - (+30, +25) 2.8;
  - (+11, +36) height 7.6, **upper** (reachable only from inside the duct).
- **Start chewing:** press E near a closed vent, within 4.7 (3.2 for the upper vent). In the duct the height must also be within 2.6. This creates `hospitalChew = {vent, origin}` and flashes "HOLD E to chew… This first entry needs two minutes." or "Keep still until it opens."
- **Progress** (`updateChewing`), each frame while E is held:
  - Cancel if the squirrel moves more than 1.3 from `origin` or more than 4.9 (3.2 for the upper vent) from the vent.
  - `vent.chew += dt`, up to the required time: **120 s for the first vent, 24 s for the others**. Progress is **kept** if interrupted.
  - `#chewPanel` shows "{CHEWING VENT|CHEWING OVERHEAD HATCH} · n / required sec · EXPOSED".
  - At the required time: `vent.open = true`, the grille panel is hidden, and the flash reads "VENT OPEN! E to enter or leave the duct." or "UPPER HATCH OPEN! SPACE drops · LEFT CLICK pounces."
- Chewing runs only while in the hospital or duct (9043-9048). Hospital defenders can knock the squirrel off a chew (section 11).
- Duct crawl speed is 2.8 walking and 3.8 sprinting (x1.6 during chili rush, because the rush multiplier at 6620 is applied after the duct base at 6619), along a fixed path (hospital spec).

---

## 18. Trampoline bounce (10370-10392; prop at 1422-1462)

- Prop: `trampoline(-33, 80)`. Mat disc r 4.95 at y 1.45 (the group is at y 0, not terrain), 12 poles, a net, and a guard ring. The guardrail is a `kind: "trampoline"` route at y 5.97, r 5.12.
- **Bounce test** (from `updatePlayer` before ground snapping, 6752):
  - Requires: not on a rail and not in the duct, hospital or sewer.
  - Requires: horizontal distance from (-33, 80) < 4.67.
  - Requires: previous y >= 1.72 (surface 1.68 + 0.04), current y <= 1.92, and falling (`vel.y < 0`).
- **On a bounce:**
  - `bounceCount = min(4, count + 1)`.
  - `pos.y = 1.9`, `vel.y = 14.2 + 0.9*count`. That is 15.1, 16.0, 16.9, 17.8, giving apexes of about 3.8 to 5.3 above the mat (inferred).
  - Add 1.6 units/s along the camera forward. Set committed airborne and `cameraCommit = 0.4`.
  - Flash on the first bounce: "BOING! Hold a direction to steer · bounce again for extra height."
- The count resets when the squirrel is more than 9 from the centre (10242).
- Visual: the mat dips by `0.35*sin(flex*PI)`, with flex decaying at 2.8/s (10243-10245).

---

## 19. Idle predator (8185-8231)

- `updateIdle(dt)` runs once per frame inside `updateNewSystems`. It is only called while playing and unpaused, with real dt clamped to 0.2 (9059).
- **Movement test:** frame-to-frame distance > **0.035** resets `idleTime` and the warning.
  - Other resets: pepper pickup, sewer teleport, hospital teleport, and squirrel infection.
  - This is **frame-rate dependent**. At 60 fps a stalking squirrel at 1.65 units/s moves only 0.0275 per frame and counts as idle (inferred).
- At `idleTime >= 779`:
  - Pick a predator and warning with `predatorForPlace()`.
  - Set `predatorWarning = 1.03` s, flash "{warning}…", and play a sound (310 Hz for the eagle, 130 Hz otherwise).
- The warning counts down in steps of `min(dt, 0.1)`. If it expires while `idleTime >= 780`, call `predatorGameOver()`.
- `predatorForPlace()` (8186-8197):
  - In the hospital: "hospital security guard" ("Footsteps close in at the hospital entrance").
  - In the sewer: "small alligator" ("A low hiss and a ripple in the sewer water").
  - In a shelter zone (`dist < r` and `y < terrain + 5`) of type house or shed: "cat" ("A low yowl from behind the shelving").
  - In another shelter zone: "snake" ("A sharp hiss from the shadows").
  - Otherwise: "eagle" ("A broad-winged shadow sweeps across the ground").
- Shelter zones (3703-3709):

| type | x | z | r |
|---|---|---|---|
| log | -19 | 376 | 4 |
| bridge | -116 | 371 | 4 |
| hollow | 95 | 359 | 4 |
| shed | 203 | 328 | 6 |
| house | 255 | 328 | 7 |

---

## 20. End conditions, win and restart

| Outcome | Trigger | Overlay title / text | Lines |
|---|---|---|---|
| **Run over** | Server-style swept test: the squirrel's frame segment against every moving vehicle's oriented box (padding 0.18, Y from -0.3 to height-0.16). Disabled in the hospital, sewer or duct. | "RUN OVER" / "A {vehicle} ran you over. The run is over. Power: … · Bites: … · Coins: …. Restart to play again." | 15772-15869, 15870-15897 |
| **Predator** | 780 s without movement | "CAUGHT BY A {KIND}" / "You stayed still for thirteen minutes. The {kind} got you. Final Power… Successful bites… Coins… · Golden…" | 8198-8207 |
| **Hidden win** | `infectionOwn + infectionFromSquirrels >= 50` **and** `bittenStaff >= ceil(8/2) = 4` **and** `bittenPatients >= ceil(8/2) = 4` (both are `Set`s of NPC idx, so distinct individuals; 8 staff and 8 patients exist, 4966-5043). Checked on every bite and every infection tick. | "THE CITY IS YOURS" / "The town is changing. You found a path nobody told you about. Power N · M bites." | 8645-8664, 8849-8866 |

- Every outcome sets `alive = false` and `playing = false`, exits pointer lock, and shows `#dangerOverlay`.
- The overlay's "RESTART RUN" button **reloads the page** (7869). Note under the button: "Your equipped clothing is saved on this browser."
- Safety net, not an end condition (`validatePlayerState`, 13300-13315): a NaN position or `y < -150` restores the last safe position. The safe position is recorded every 0.5 s while grounded, off rails and out of the duct.
- Also not an end condition: falling into the river triggers `recoverRiverFall` (quay spec).

Infection mechanics are owned by the infection spec. The essentials for the win test:
- `infectionOwn` gains +3.6 per street bite, +5.7 per patient and +6.2 per staff member.
- It decays at 0.011 per second (0.05 in the duct).
- Each infected normal squirrel matures over 1500 s of play. It only advances while `infectionOwn >= 25` and a bite happened within the last 600 s. The total squirrel share is capped at 25% (8849-8866).

---

## 21. HUD and UI

### 21.1 Top stats panel (shell:135; refresh `refreshPowerUI` 5465-5482, every 0.2 s plus on events)

| Element id | Label | Content |
|---|---|---|
| `score` + `powerFill` | POWER | `points`, zero-padded to 4 digits. Bar width `min(100, points/1500*100)%`, lime #d1ee83. |
| `hits` | SUCCESSFUL BITES | `hits` |
| `chiliCount` | HIDDEN CHILIS | "n / 8" |
| `fadeTimer` | NEXT POWER FADE | mm:ss of `600 - inactiveSeconds` (ceil) |
| `coinScore` | SQUIRREL COINS | `squirrelCoins` |
| `goldScore` | GOLD | `goldCoins` |
| `infectionScore` + `infectionFill` | INFECTION | "x.x%" and a bar (#e6b265). Updated by `drawInfection` (8461-8466). |
| `evolution` | STATE | FERAL (below 600), RABID (600 or more), SUPER (1500 or more) |

- Brand block: "SPICY RODENTS / TOPEKA · OLD TOWN / PARK / HOSPITAL".
- `#boostBadge` (shell:136): pepper icon, `boostLabel` "CHILI RUSH" or "CHILI RUSH · +60%". `boostTime` shows "Ns remaining · faster leaps", "ALL PEPPERS FOUND" or "FIND A HIDDEN PEPPER". The `.active` class adds an orange glow.

### 21.2 Context panels
- **`#status` flash** (`flash(str, time=3)`, 5530-5535).
  - It is a single slot: a new message overwrites the old one. `messageTime` counts down in game time (16009-16013), and the panel is hidden when it reaches 0.
  - Shown top-centre at 110 px.
  - The boot message is "v5.4 · APPLE TREES, BIRDS & TRAFFIC · Watch for moving vehicles" (6 s).
  - About 1 in 11 seconds near a route, a random hint "E to grab: {route}" appears (6876-6878).
- **`#focusLabel`** (bottom right).
  - Header `focusHeader` reads "SCOUTING" (dimmed) or "PREDATOR'S EYE".
  - `scoutText` is contextual (6594-6604):
    - while stalking;
    - in the duct, with the hatch open ("OVERHEAD EXIT OPEN · SPACE to drop / LEFT CLICK to pounce from above") or closed ("VENT CRAWL · W/S along the duct / HOLD E at a closed grille to chew");
    - in the hospital ("EMERGENCY WING · E to use doors or vents / First vent: hold E to chew.");
    - inside a house ("INSIDE {NAME} · E near front door to exit / WASD explore · SHIFT run · M HUD");
    - default: "Park NORTH · estates SOUTH · hospital WEST / Old town westside: E at open garages · police station nearby."
  - At the mall the text is overridden by mall hints (15044-15047).
- **`#crosshair`, `#aimState`, `#reticleHint`, `#focusVignette`**: shown while stalking (`body.focus`) or at the hatch (`body.hatch-aim`, 6588-6591). In the hatch case `aimState` reads "DROP AIM · LEFT CLICK TO POUNCE".
- **`#districtTag`** (9062-9078), top left. Possible values:
  - HOSPITAL · DUCTS
  - HOSPITAL · EMERGENCY
  - HOSPITAL DISTRICT (x < -270 and z > 245)
  - UNDERGROUND · SEWER
  - SYCAMORE PARK (z > 303 and x < 150)
  - CEDAR REST · GRAVEYARD (z > 303 and x > 270)
  - NORTHERN GARDENS (z > 295)
  - COMMERCIAL DISTRICT (x > 280)
  - OLD TOWN
  - The mall and quay override this tag.
- **`#chewPanel`** (bottom-centre), **`#shopHint`/`#shopDetails`** (bottom-centre), and **`#branchGuide`** (route guidance, movement spec).
- **`#bubbleLayer`**: NPC speech bubbles (NPC spec).

### 21.3 Compass (`updateCompass`, 9854-9871; shell:141)
- `heading = (-yaw in degrees) mod 360`. Camera forward is (-sin yaw, -cos yaw), and world **-Z is north** (comment 9855).
- Cardinal label: N, NE, E, SE, S, SW, W or NW at `round(heading/45) % 8`. `#compassHeading` reads "{card} · {ddd}°".
- `#compassLetters` is a strip of 17 labels (k from -4 to 12), each 46 px. It is translated by `(4 - heading/45)*46` px. The lime needle "▲" is fixed at the centre.

### 21.4 HUD layout control (9801-9851; shell:142-152)
- The parts are stats, compass, world, hunt, help and settings. Each one toggles the body class `hud-hide-{part}`:
  - stats: the scores and brand;
  - hunt: the boost badge and focus label;
  - help: the hints and help toggle;
  - world: the branch guide, district tag and status;
  - settings: the graphics chips.
- Presets (Tab cycles them):
  - FULL: all parts.
  - PLAY: stats, compass, hunt, world.
  - NAVIGATION: compass, world, help.
  - CLEAN: compass only.
- M: if everything is visible and help is open, hide all ("OFF"). Otherwise show all and reopen the help.
- K: toggles the `#hudChooser` checkboxes. Opening it releases pointer lock. Changing any checkbox switches the mode to CUSTOM (`hudPreset = -1`, 9845-9851); opening alone does not.
- `#hudMode` shows the preset name, OFF or CUSTOM.
- `#hints`: toggled by H or `#helpToggle`. It auto-collapses after 60 s of game time if never touched (9054-9058).

### 21.5 Settings, pause and overlays
- `#graphics` chips:
  - NPC FLOW: DEMO/QUIET (crowd density).
  - GRAPHICS: cycles auto, high, ultra, performance (`initRefresh` rebinds it, 13346-13349).
  - VOICES: ON/OFF (speech synthesis).
  - G · DISPLAY.
- `#graphicsPanel`: quality select, time-of-day preset (golden, daylight, dusk), online-detail checkbox, credits. Opening it pauses the game. Closing it restores the previous pause state.
- `#pauseShield` ("Your run is paused."): shown on window blur, tab hidden, or WebGL context loss. "BACK TO THE STREETS" resumes and re-locks the pointer.
- P pause: flash "PAUSED · P to resume".
- `#dangerOverlay`: end screen (section 20). `#loading`: "GROWING THE NEIGHBORHOOD…". `#spicyDiagnostic` (L). `#spicyBootError`: boot/runtime fatal panel.

### 21.6 Audio cues (`fx`, 6451-6467)
All cues are WebAudio oscillator blips: frequency in Hz, duration, waveform, volume.

| Cue | Settings |
|---|---|
| Pounce | 640, 0.1, saw |
| Bite | 150, 0.24, triangle |
| Miss / batted away | 100, 0.25, square |
| Perfect counter | 880 |
| Chili | 990 |
| Decay | 160 |
| Kick or baton hit | 180, square |
| Predator warning | 310 / 130 |
| Vent open | 560 |
| Dance | 680 |
| Squirrel infected | 810 |

---

## 22. Saved data (`localStorage`)

| Key | Shape | Validation | Lines |
|---|---|---|---|
| `spicy-rodents-wardrobe-v1` | `{owned: [int[],int[],int[]], equipped: [int,int,int]}` with -1 meaning none | `owned` arrays are de-duplicated integers 0-9. `equipped[i]` must be in `owned[i]`, otherwise -1. Any error falls back to the default. | 8309-8326, 8365-8369 |
| `spicy-render-v5` | `{mode: auto|high|ultra|performance, light: golden|daylight|dusk, online: bool}` | enum-checked | 114-119, 12908-12915 |

Nothing else persists between runs: Power, coins, gold, hits, chilis, infection and the fashion unlock all reset. Restart is a page reload.

---

## 23. Frame order relevant to this subsystem (15940-15968, 15999-16031)

The tick uses `dt = min(clockDelta, 0.08)` for simulation and `activeDt = min(realDt, 0.2)` for timers. While playing, alive and unpaused, `updateGameplay` runs these steps in order:

1. `beginTrafficFrame` (snapshot of the squirrel and every vehicle).
2. `updatePowerAndHeat(activeDt)`.
3. `updatePlayer` in `ceil(dt/(1/60))` substeps. Each substep includes the pounce collision test.
4. `validatePlayerState`.
5. `updatePepperPickups`.
6. Outdoor NPCs, vehicles, wildlife and cats (skipped in the sewer and hospital).
7. Infection and hospital (chewing).
8. `updateNewSystems`: idle predator, district tag, shop hint, dogs, cop, fog.
9. Westside (trampoline reset), gatherings, doors, interiors, posters, police.
10. `finishTrafficFrame` (fatal swept hit).

After that: `updateScenery` (bite dance), camera (aim path, hatch marker), compass, bubbles and render.

---

## 24. Brief section 7: the seven animation clips and their HTML sources

| # | Brief clip | HTML source | What to author |
|---|---|---|---|
| 1 | **Run** | Ground gait (6825-6872): diagonal leg pairs, cadence `speed*2.85`, bob 0.022 + speed*0.0011, pitch rock ±0.022, sprint squash 0.92, turn bank ±0.31 | A gallop loop with speed-scaled playback. Separate walk/trot blend below about 8 units/s (proposal). |
| 2 | **Climb** | Trunk (6840-6864): body pitch -0.83 to -1.43 by height, legs ±0.16 step, splay 0.12, faces bark, tail flat | A vertical climb loop, plus an idle grip pose. |
| 3 | **Wire traversal** | No dedicated pose. Wire offset +0.22 Y (6798), rail cadence `speed*0.7` | A new clip: hand-over-hand balance with tail used as a counterweight (proposal). |
| 4 | **Leap** | No dedicated pose (airborne legs keep cycling). Camera pulls back, FOV 74 (7421-7422). | Takeoff, extension, landing. Must work for the 2.73-unit traversal leap. |
| 5 | **Pounce** | `attackWindow > 0`: pitch -0.16, Z-stretch 1.13, face -0.17 (6842-6857) | Under brief section 8 this needs wind-up, commit (lunge) and recovery sub-phases. |
| 6 | **Bite dance** | `animateBiteDance` (10348-10369): every 10th bite, 2.1 s wiggle, spin, hop | Author as a celebratory clip. Whether it plays on every bite or every 10th is open (section 27). |
| 7 | **Sneak (stalk)** | `focus`: Y-squash 0.9, pitch +0.05, legs fixed at 0.12. Mesh hidden locally in first person. | A low crouch-walk. **Other players see it**, unlike in the HTML. |

Also from section 7: replace the stacked-spheres placeholder entirely. "A tail that lags the body" requires a velocity-driven secondary motion (spring chain), which replaces the HTML's time-only sine tail (5254-5267).

---

## 25. Brief deltas

Quotes come from `Roblox_Rebuild_Brief.txt` (section numbers given) and `spec/BRIEF_ADDENDUM.md` (A1-A3).

1. **Section 8 "Stalk (hold), pounce, bite as in v5.4. Unaware people are easier."**
   - Keep RMB-hold stalk, LMB pounce, and contact-based bite.
   - The HTML's awareness test is binary (alert > 0.45 at launch gives 3.5%, otherwise 95.5%), with a separate officer model (88% if behind, above or stunned; 3.5% head-on).
   - Retain the "unaware" concept, but make it graded and server-evaluated.
   - The F toggle is an HTML extra. Keep it for accessibility (proposal).
2. **Section 8 Combat dynamics.** The brief adds what the HTML lacks.
   - *Timing: wind-up, commit point, recovery.* HTML pounces commit instantly. The only "recovery" is the 0.7 s cooldown and the post-landing `cameraCommit` (0.35 s). The bite window (0.78 s) is an active-hit window, not a vulnerability window.
     - "Biting during the human's reaction window lands; biting into a raised arm or a kick does not." This **inverts** HTML behaviour: in the HTML, pouncing during the last 0.34 s of a kick wind-up is a guaranteed *perfect counter* with a gold reward, and being mid-pounce makes the rodent **immune** to kicks.
     - A designer must decide whether to keep a narrow "counter" timing (for example, before the kick's commit frame) or remove it (section 27).
   - *Zig-zag vs straight sprint.* Not present in the HTML. New tunables are needed (proposal: lateral-reversal detector giving a miss-chance bonus against swings and a speed multiplier below 1).
   - *Feint.* Not present. It is new, needs stamina, and grants a free hit if read.
   - *Stamina.* Not present. New.
   - *Humans respond: flinch, swing, kick, back away, flee, chosen by awareness and nerve.*
     - The HTML has flee, home retreat, dodge (0.38 s sidestep), defend (approach to 2.4), and kick (0.58 s wind-up).
     - There is no flinch and no swing: police batons are their "swing".
     - "Vigilantes never flee": HTML defenders revert to flee when `defenseUntil` expires.
3. **Section 8 Health.** "A kick does not kill; roughly two kicks without proper recovery do. Health regenerates slowly while sneaking or resting in a hollow." The HTML has **no health**: kicks and batons cost 19 Power plus knockback, cats cost 12, and hospital staff only knock back.
   - (Proposal) `MaxHealth = 100`, kick damage 55, so two kicks inside the regen window kill. Regen 0 while running, slow while stalking (about 2 HP/s), faster in a hollow (about 5 HP/s). A short post-hit invulnerability (0.6 s) prevents multi-hits from one swing.
   - **House defenders' blows hit 50% harder**: 55 x 1.5 = 82.5, "one blow at low health kills" (proposal values).
   - Batons and hospital staff must also deal damage, because sections 6, 9 and 10 say officers and hospital staff can **kill** the rodent.
4. **Section 6 / section 8 death replaces game-over screens.**
   - HTML run-over, predator and win overlays plus a page reload become **role transitions**: a dead rodent restarts as the lowest-level human; the killer is promoted per section 6.
   - "Session resets when everyone is infected." This replaces the HTML's 50% plus half-staff plus half-patients win. The brief says "Critical mass of infection wins the session", so the threshold needs a design decision (section 27).
   - "Do not surface this in the UI": the HTML **does** show an INFECTION % meter. Remove it from the rodent's HUD or obscure it.
5. **Section 8 fatal traffic.** Port `sweptVehicleHit` (relative swept segment against an oriented box) server-side, not as `Touched`. Being run over ends the rodent's run (role exit, not page reload).
   - Addendum A1: player-driven police cars must be included in the same test.
6. **Section 8 house interiors.** "40 houses have full interiors the rodent can burst into… bitten depends on the chase."
   - The HTML **forbids pouncing inside a house interior** (6484-6487), and humans' `isVisible` is false while the squirrel is indoors.
   - The new build must enable indoor pounce, bite and kick, plus the three special defenders.
7. **Section 7 animation.** Seven clips (section 24). The squirrel is enlarged to about 1.2 studs at the shoulder, about 1.9 times the HTML relative to humans.
   - All contact radii in this spec (pounce 1.38, kick 2.65, chili 1.4/2.2) were tuned for the small HTML model. Re-tune them in studs rather than blindly multiplying by 2.5 (section 26).
8. **Section 6 rank and section 13 credits vs HTML currencies.**
   - Power, Squirrel Coins, Gold, the chili hunt, the fashion stand and the Galleria coins are not mentioned in the brief.
   - Section 6 defines squirrel rank as 90% nuts and 10% stink gland. The rodent's own score is not defined.
   - These systems are kept, dropped or re-skinned by designer decision (section 27).
   - The regular-squirrel infection on pounce (100%) matches section 6 ("A regular squirrel cannot kill the spicy rodent; it can only be infected by it").
   - Section 8 adds "biting regular squirrels raises town-wide infection rate". The HTML implements this as each infected squirrel maturing a 25/7 % share over 1500 s.
9. **Section 8 vigilantes (8%).** HTML defenders are the "brave" personality plus up to 2 witnesses per bite.
   - The brief makes 8% of all humans vigilantes who move to kick on sighting and answer the drone.
   - Addendum A2: "a successful kick on the spicy rodent, by any human" promotes that human. The kick-hit event must carry the attacking actor's identity, and the controlling player if any.
10. **Addendum A1 sightings.** "When an AI or player human spots the spicy rodent, or a bite happens, a sighting marker appears…"
    - Hook into the spotting transition (7068) and into bite resolution (6526 / 8108).
    - Rate-limit per actor (proposal: one sighting per human per 10 s).
11. **Addendum A3 avatar blend (70/30).** The rodent model takes avatar colours into the fur (capped), patterns and eye colour, plus "one avatar accessory shrunk onto the head socket".
    - This conflicts with the fashion stand's hat slot. A designer must define precedence (section 27).
    - The red emissive eyes are the rodent's identity cue. Blend eye colour only for regular squirrels, or cap it so the rodent's eyes stay red (proposal).
12. **Section 3 sewer retained.** "Sewer and duct interiors" are listed as retained districts. Keep the L tunnel, the grates and the stand.
13. **Section 11 fox.** "Hunts regular squirrels; cannot harm the spicy rodent." The v4.1 fox lunge (-17 Power) must not target the rodent. Deer and fox as pounce targets (v4.1: deer bite 15%, fox 70%/18%) need a decision.
14. **Not in the brief (HTML-only):** idle predator game over, chili rush, perfect-counter gold, trampoline, HUD layout presets, P pause, graphics panel, voice toggle. All need keep/drop decisions (section 27). Pause cannot exist on a 50-player server.

---

## 26. Porting notes (Roblox)

**Authority and networking**
- The rodent avatar is a client-owned kinematic controller (rail and ground motion), for responsiveness. The server is authoritative for everything that scores or hurts:
  - pounce contact validation and bite RNG;
  - awareness (alert) state of AI humans;
  - Power, coins and gold;
  - health and damage;
  - chili pickups;
  - the fashion purchase;
  - infection;
  - the swept traffic hit.
- **Pounce protocol** (proposal):
  1. The client sends `PounceStart(t, origin, velocity)`.
  2. The server checks the cooldown, the speed cap (at most 13.5 x 1.12 = 15.1 units/s, about 38 studs/s horizontally) and the state (not in a house if indoor pounce stays disabled, and so on).
  3. The server snapshots alert values **at receive time minus half the RTT**.
  4. The server opens the 0.78 s window and runs contact tests against server-side actor positions, rewound up to about 150 ms for lag compensation.
  5. The client may play the lunge immediately. A rejected or missed result arrives as a correction, never a rubber-band of the lunge itself.
- The kick or baton hit test (range, facing, height, "not mid-pounce" rule if kept) must run on the server using the same window state.
- Velocity-replacement air pounces (an air-dash) are easy to exploit with high-frequency inputs. Keep the 0.7 s cooldown server-enforced.

**Movement and physics**
- Use a custom kinematic controller, not Humanoid physics. HTML gravity is 30 units/s^2, which is 75 studs/s^2 at 2.5 studs per unit; Roblox default gravity is 196.2.
- Recompute arcs from these speed conversions:

| Quantity | HTML units/s | studs/s |
|---|---|---|
| Ground walk | 8.0 | 20 |
| Sprint | 16.8 | 42 |
| Stalk | 1.65 | 4.1 |
| Rush sprint | 26.9 | 67 |
| Leap forward | 16.5 | 41 |
| Leap up | 12.8 | 32 |
| Pounce | 11.3 to 15.1 | 28 to 38 |

- **Contact radii in studs, if scaled 1:2.5:**

| Radius | HTML units | studs |
|---|---|---|
| Pounce-human | 1.38 | 3.45 |
| Pounce-officer | 1.85 | 4.6 |
| Normal squirrel | 1.42 | 3.55 |
| Kick | 2.65 | 6.6 |
| Chili | 1.4 / 2.2 | 3.5 / 5.5 |
| Sewer corridor | 2.2 | 5.5 |
| Interact | 5 | 12.5 |
| Stand | 6 | 15 |

  - Because the brief's squirrel is about 1.9 times larger relative to humans, consider keeping these generous. Test them against the new mesh.
- Replace the absolute "y > 4" elevated-bite bonus (6527) and the "y < 4 / y < 5.2" visibility limits (7029, 7050) with **height above local ground**. The new town has varied terrain and multi-storey interiors.
- Replace the frame-based idle test (0.035 per frame) with distance over a time window. Proposal: total displacement below 0.5 units over 5 s counts as idle.
- `settleSquirrelFeet` becomes per-foot raycast IK (or hip-height adjustment) on the client only. Tail spring-chain and foot IK should run only for animals within about 60 studs of the camera.

**Performance (50 players, many AI)**
- Spotting runs per human per frame in the HTML. On the server, run it at 5-10 Hz using a spatial hash of humans around the single rodent. Only humans within 20 units (50 studs) need the full test.
- The HUD refresh at 0.2 s maps naturally to attribute or value-object replication. Do not fire RemoteEvents every frame.
- Bite dance and stalk aim-arc are client-only cosmetics. Other clients only need the animation state (an enum attribute on the character).

**StreamingEnabled**
- The sewer floor is at Y -3.4, below terrain. The hospital interior and ducts are enclosed spaces.
- Before teleporting into the sewer or hospital, call `Player:RequestStreamAroundAsync(target)`, and keep sewer and stand models in a streaming-persistent or atomic model.
- Chili peppers and Galleria coins must be server-owned and streamed. A pickup is confirmed by the server.
- Mark grates, the fashion stand, and vents (with their chew progress) as `ModelStreamingMode.Atomic`.

**Persistence**
- Replace `localStorage` `spicy-rodents-wardrobe-v1` with a DataStore profile per UserId: `{wardrobe = {owned = {{},{},{}}, equipped = {-1,-1,-1}}}`. Keep the same validation rules.
- Render settings become client-local settings. Roblox has its own graphics quality, so drop online-asset and quality options and keep only time-of-day if it remains client-cosmetic.
- Decide whether the fashion unlock (150 earned coins) persists. In the HTML it does not, which forces re-earning 150 coins each run even to re-equip.

**Input conflicts in Roblox**
- **Tab** opens the CoreGui player list. **Esc** opens the Roblox menu and cannot be bound. **RMB** is the default camera-rotate. Use a custom camera with `MouseBehavior.LockCenter`, then bind stalk to RMB via ContextActionService.
- **P pause** cannot exist on a shared server. Remove it, along with the pause shield.
- **L diagnostics** should be developer-only.
- **M**, **K** and **H** are free.
- Provide touch and gamepad bindings: a stalk toggle (the F-style toggle is ideal for mobile), a pounce button, leap, interact (with a hold for chew), and a drop button.

**UI**
- Rebuild as a ScreenGui with the same element set.
- Turn the single-slot `flash` into a small priority queue (danger warnings such as kick wind-up or "baton raised" should not be overwritten by flavour text).
- The compass keeps "-Z = north". Roblox Workspace has no fixed north, so pick the same convention in WorldGen.

**Audio**
- Replace oscillator blips with SoundService assets.
- Speech synthesis is NPC scope. Roblox TTS availability is uncertain (open question).

---

## 27. Open questions

1. **Rodent score economy.** Keep Power, Squirrel Coins and Gold for the spicy rodent? If kept, what do they buy in the brief's economy (rank, queue position, cosmetics)? Do coins earned as the rodent persist after the rodent dies and becomes a human? Brief section 13 uses "credits" for humans.
2. **Chili rush.** Keep the 8-pepper hunt as a per-tenure power-up for the rodent only? If several rodent tenures happen per session, are peppers re-seeded per tenure or per session?
3. **Counter-play rules.** HTML: pouncing into the last 0.34 s of a kick wind-up gives a guaranteed bite plus gold, and pouncing makes the rodent immune to kicks. Brief: "biting into a raised arm or a kick does not [land]". Remove the perfect counter? Replace it with a narrow "duck-under" window before the kick's commit frame? Remove pounce immunity so a well-timed kick can hit a lunging rodent?
4. **Health numbers.** Max health, kick damage, baton damage, hospital staff damage, cat damage, regen rates while stalking or in a hollow, "proper recovery" definition (time since the last hit?), and post-hit invulnerability. House defenders are x1.5.
5. **Stamina and feint.** Stamina pool size, costs (sprint, zig-zag, feint, pounce?), regen, and whether stalking regenerates stamina. How does a human "read" a feint: AI probability by nerve, a player timing check, or both?
6. **Zig-zag detection.** What counts as zig-zag (heading reversals per second, lateral amplitude)? Is the human miss-chance bonus applied to kicks, swings, or both? What is the speed penalty?
7. **Hidden win threshold.** The brief says "critical mass" and "session resets when everyone is infected". The HTML says 50% plus half the staff plus half the patients. Is the rodent's "win" the full-infection reset, or an earlier critical-mass threshold? Should the HUD infection meter be hidden from everyone, or only shown to hospital staff?
8. **Idle predator.** Drop it, keep it as a death cause for an AFK rodent (role exit after N minutes idle), or have the AI take over an AFK rodent body (actor model, section 4)?
9. **Bite dance cadence.** Play it every 10th bite as in the HTML, or a short dance on every successful bite with the full dance on milestones?
10. **Pounce targets.** Should deer and fox (restored from v4.1) be biteable by the rodent? v4.1 used deer 15% and fox 70% if stalking, from above or from behind, otherwise 18%. Should rabbits remain as "never catchable" decoys?
11. **Fashion vs avatar blend (A3).** Does a purchased hat replace the A3 "one avatar accessory on the head socket", or stack with it? Does the wardrobe belong to the player (persisting across squirrel and rodent tenures) or to the rodent role only? Can regular squirrels use it?
12. **Indoor pounce.** In the 40 interior houses (section 8), do the same pounce numbers apply, or do the tighter spaces need shorter lunges and lower slide?
13. **Elevated-bite bonus.** Keep +50% Power for bites from height, and measure it as height above ground (proposal: 1.6 units or more, matching the kick-height escape)?
14. **Scale of contact radii** after the squirrel is enlarged about 1.9 times relative to humans. Scale the gameplay radii with the model, or keep HTML-relative values in studs?
15. **Sewer purpose.** It is currently a safe zone (no cops, kicks or traffic), a shop and a shortcut. Should other roles (regular squirrels, police on foot) be allowed to follow the rodent into it?
16. **Wanted posters threshold.** The code uses more than 8 bites; one comment says 15. Which is intended? With 50 players, should this threshold be per rodent tenure or per session?

---

## Added by verifier

Items in scope that the extractor left out or understated. Line numbers refer to `v5_4_game.js` unless marked `v4_1:`.

1. **There is no "heat" stat.** `updatePowerAndHeat` (5506-5526) only runs the Power-fade clock, the chili-rush countdown and the 0.2 s HUD refresh. "Hot" exists only as the local `wasHot` flag used to flash the rush-ended message. Nothing else in v5.4 or v4.1 is called heat. Do not invent a heat meter for the port unless a designer asks for one.
2. **Danger telegraphs ("alerts") and their flash texts.** The Roblox priority-queue flash (section 26) needs this list. All of them are single-slot `flash` calls today.

| Source | Telegraph flash (duration) | Result flash | Lines |
|---|---|---|---|
| Pedestrian kick | "{name} prepares to kick — dodge or counter!" (1.2 s, only within 6.1) | "{name} kicked the squirrel away!" / "{name}'s kick missed — move away or counter." | 8182, 8162, 8163 |
| Patrol officer | "The officer raises a baton — jump or retreat!" (1.45 s) | "POLICE BATON! Dodge the wind-up or ambush from behind." / "The officer swung and missed." (within 6) | 8069, 8058-8059 |
| Incident officer | "Police closing in — baton raised!" (1.1 s) | "An officer landed a baton strike!" | 11153, 11142 |
| Station reinforcement | none | "More officers emerge from the station — retreat!" | 11183 |
| Precinct guard | none | "Police station security! The officers will not let you inside." | 11206 |
| Yard cat | "A yard cat crouches to pounce — JUMP!" (1.2 s) | "CAT SWAT! …" / "The cat lunged and missed!" | 11633, 11616, 11620 |
| Hospital orderly / extinguisher / guard | "Stretcher rail shoves forward — get clear!" / "The woman winds up the fire extinguisher!" / "Security guard lunges — dodge!" (1.2 s) | knockPlayer message | 8822-8824, 8834-8840 |
| Yard dog (no damage) | "WOOF! A yard dog spotted the squirrel." (bark cooldown 8 s, squirrel within 10 and world y < 5) | alerts humans within 12 to `alert >= 3` | 9090-9111 |
| Idle predator | "{warning}..." (1.15 s) | game over | 8218-8226 |

3. **Special street cast (1 juggling mime on a unicycle and 5 young cyclists; 12130-12262) follows its own awareness rules**, which decide pounce success against them. They are `humanoids`, so `updatePounceCollision`/`resolvePounce` apply, but `updateHumans` skips them (7015). So they never kick, dodge or defend, and their `alert` never decays.
   - Spotting (`noveltySpotSquirrel`, 12317-12331): never while the squirrel is in the sewer, the hospital, a house interior, or above world y 6.4. Otherwise spotted if within 24 (mime 36) and either the rider faces the squirrel (dot > 0.08), or it is within 10 (mime 14), or the squirrel moves faster than 6.5 within 17.
   - On spotting (`noveltySpotResponse`, 12332-12340): `alert = 32`, `state = "escape"`, `reactionTime = 2.3`, plus an escape burst away from the squirrel. The alert stays at 32 until the actor escapes and resets (`alert = 0`, 12386). So once a rider has seen the rodent, a pounce on it lands only 3.5% of the time.
   - While escaping, a pounce window within 8.5 refreshes `reactionTime >= 0.55` (12413-12415).
4. **Frame-rate dependence of the idle predator is worse than section 19 states.** `tick` has no frame cap (15999-16031). The 0.035-per-frame movement test means that at about 229 fps or higher even normal walking (8 units/s) counts as idle (8 / 229 = 0.035), as does every stalk speed at 60 fps (inferred).
5. **Pounce chaining detail.** `cooldown` (0.7 s) is shorter than `attackWindow` (0.78 s). A second pounce can therefore be fired while the first window still has 0.08 s left. It restarts the window at 0.78, takes a fresh `attackAlert` snapshot and replaces velocity again (6483-6501).
6. **Play-start flash.** Pressing START PLAYING overwrites the boot message with "Find eight hidden chilis for a speed rush. Keep biting to preserve your Power." (5 s, 5574). The initial `#scoutText` markup reads "Find eight hidden, one-time chili peppers. / Hunt to build Power; it fades after ten minutes without a bite." (shell:140). `updatePlayer` replaces it on the first frame.
7. **Fashion stand default selection.** `selectedStyle` starts at `[0,0,0]` and `fashionSlot` at 0 (8327-8328). Pressing E at the stand before any 1/2/3 press therefore buys or equips the hat Bandana (item 0). Because each 1/2/3 press pre-increments, getting back to item 0 takes 10 presses.
8. **Fountain toss preconditions** (`handleMallInteraction`, 15002-15025): not in the hospital or sewer, not on a rail, within 2.8 of `MALL.floor` height, within 11.5 of the fountain, and `tossCooldown` 0. With 0 coins it flashes "Find a coin inside the Galleria, then E to make a wish." and costs nothing.
9. **Wanted-poster comments disagree with each other, not only with the code.** 11226 says "after 15 successful bites". 11265 says "after NINE successful bites", which matches `player.hits > 8` (7059, 11279).
10. **v4.1 trash-can scavenging (lost in v5).** This is a coin source next to the nut caches in section 14. There are 6 bins at (-71, 68), (53, -76), (221, 61), (-238, 140), (107, 204) and (134, 392) (v4_1:12766-12774). E within 2.5 horizontally and |dy| < 2.6, not on a rail, not in the sewer, hospital or a house interior. Each bin works once. 35% chance of `2 + (index % 4)` coins (2-5, counted toward `totalCoinsEarned`), otherwise "Nothing edible in this trash can." (v4_1:12425-12443; E hook at v4_1:7614). v4.1 also placed 5 bird feeders (v4_1:12758-12765), but they had no rodent interaction. Like the nut caches, this belongs to the brief's foraging scope.

---

## Verification log

Each line is one checked claim. OK = matches source; FIXED = corrected in this file (old -> new); UNVERIFIABLE = could not be confirmed from source.

1. `player` object fields and initial pos (-36, 0.31, -36) at 5127-5153: OK
2. `SQUIRREL_VISUAL_SCALE = 0.335` (5155), applied at 5157, comment "50% of v0.4" (5154): OK
3. Body sphere r 0.55 at (0, 0.39, -0.04) scaled (0.79, 0.67, 1.51); head r 0.36 at (0, 0.62, 0.65) (5171-5174): OK
4. Eyes r 0.057 at (±0.205, 0.72, 0.886), colour #be2f25, emissive #ad1e16, intensity 0.92 / 1.65 in rush (5165-5170, 5193, 6848): OK
5. Face group membership: FIXED (head, eyes, snout, nose, teeth, whiskers -> also includes ears, ear tips and eye highlights)
6. Shoulder height about 0.25, head top about 0.31, ear tips about 0.43 units (computed): OK
7. "Body length without the tail is about 0.56 units": FIXED (0.56 is the body ellipsoid only -> nose-to-rump about 0.72)
8. Human height about 2.06 units (`makeHuman` scale 0.59 x U(0.87, 1.13), head at 2.9 local; 4582-4598): OK
9. Tail: 22 segments, sway/height/depth/thickness formulas, trunk-flat variant, menu at 0.7x time (5249-5267, 16019): OK
10. `squirrelSurfaceAt` river condition: FIXED ("within 0.5 above it" -> `pos.y >= river - 0.5`, no upper limit)
11. Foot settle `lift = max(surface + 0.017 - cornerY)`, only when `onGroundSurface` (5291-5304, 6803-6809, 6874): OK
12. Visual smoothing rate 23 (17 in bridge), snap > 2.5 or > 1.6 on rail (6811-6816): OK
13. Cadence `moveSpeed * (rail ? 0.7 : 2.85) * (rush ? 1.14 : 1)` (6825): OK
14. Squash Y 0.9 stalk / 0.92 sprint, Z 1.13 in pounce window, face pitch -0.05 / -0.17 (6847-6857): OK
15. Mouse sensitivity 0.0025 / 0.00315, boost `min(1.25, hypot/35)`, pitch clamp [-0.6, 1.07], trunk orbit -dx*0.004 (5596-5609): OK
16. Key handler lines (M/Tab/K 5630-5641, P 5643, H 5648, L 5649, C 5653, A/D 5659, E 5666, 1/2/3 5671, Q 5672-5680, Space 5681, F 5682): OK
17. Q drop `vel.y = 3.3`, `cameraCommit = 0.32`: OK
18. E priority chain (house interior 11999 -> old home 10331 -> mall -> hospital -> sewer, 7914-7949): OK
19. Hints panel text (shell:139) and start-screen keys and "Stealth & survival" text (shell:155-193): OK
20. startAtMall (MALL.x, floor+0.18, 238) at 15104; startAtRiver (780, bankY+0.18, 51) at 14169: OK
21. Ground speeds 8.0 / 16.8 / 1.65 / duct 2.8, 3.8; rail 7.2 / 12.2 / 1.2; tree x0.6 (6618-6621, 6668-6671): OK
22. Chili rush multiplier scope: FIXED ("ground and rail" -> "ground, rail and duct crawl"; also added to section 17)
23. Accel 23 / 4.2, turn 19 / 25, friction 13 / 1.15, gravity 30 (6717-6723, 6472): OK
24. Leap forward 16.5 (18.5 rush), up 12.8, apex 2.73 (5915-5921): OK; added "only when grounded or on a rail" (5928)
25. World clamp x [-586, 1146], z [-560, 436] (RIVER.endX 1150 at 421, NORTH_LIMIT 440 at 3271; 6765-6766): OK
26. Stalk activation rule (6580-6587) and `commitToAir` forcing focus off (5912), landing `cameraCommit >= 0.35` (6760): OK
27. Noise threshold `moveSpeed > (focus ? 2.5 : 4.7)` within 8.6 (7033): OK
28. Stalk camera eye +0.27, look 24, damping 17, FOV 61 (7314-7317, 7397, 7420): OK
29. Aim guide 34 samples `t = 0.06 + 0.05i`, line #c9ddb0 0.33, ring 0.24-0.3 #e4f1d4 0.54 (7237-7288): OK
30. `attemptPounce`: cooldown 0.7, attack 0.38, window 0.78, alert snapshot of visible humanoids, sawtooth 640 Hz (6482-6505): OK
31. `pounceVelocity`: pitch clamp [-0.54, 0.9], speed 12.4 / 13.5 / 11.3 x1.12 rush, vertical 3.45 + sin(p)*2.1 (6473-6481): OK
32. Derived takeoff 2.37-5.10, apex 0.09-0.43, flight 0.25 s, ranges 2.8 / 3.0 / 3.3 (computed): OK
33. Ground slide while `attackWindow > 0` (no input or friction branch, 6711, 6722): OK
34. Human contact < 1.38, dy (-0.35, 2.7); motorcycle < 2.0, dy (-0.35, 3.2) (6555-6569): OK
35. `resolvePounce` perfect counter `0 < kickWindup < 0.34 && dot > 0.72`, aware threshold 0.45, 3.5% / 95.5%, +100/+150 at world y > 4 (6506-6554): OK
36. Success recoil `vel *= 0.08, vy 1.9`; failure `vel *= -0.12, vy 3.7`, NPC reacting 2.5 / 2.9 (6539-6552): OK
37. `tryPolicePounce`: dist <= 1.85, dy [-0.3, 2.8], behind dot < -0.3 or dy > 1.35 or stunned, 0.88 / 0.035, +130, stun 5.5, cooldown 6, alert >= 30, fail throw 8 / vy 3.2 (8083-8135): OK
38. `tryWildlifePounce`: rabbit 2.25 always escapes; normal squirrel 1.42, +90 / +10 coins, resets idle and bite clocks (8946-8978): OK
39. `onSuccessfulBite` chain 7996-8002 -> 9271-9286 -> 10336-10344; crime scene radius 72, ttl 600; police 18% / 5% (10440-10441): OK
40. Witness alarm: within 25, alert >= 10, reacting >= 3.4, witnessUntil +70, up to 2 defenders, defenseUntil +19, kickCooldown 0.3 + i*0.36 (9227-9270): OK
41. Spotting: isVisible y < 4 or dist < 4.7, inView dot > 0.28, radar x3, 20 / 14.5, 6.8, y < 5.2, noise 16 / 10.3; first spot alert 8, reacting 3 (7027-7077): OK
42. Concealment garden box |x-115| < 27, |z-341| < 15, y < 2.4, hedge y < 2.8, speed < 3.4 (7034-7042): OK
43. Dodge: alert > 1.5, dist < 5.4, cooldown 2.4, timer 0.38, sidestep 8.6 units/s (7083-7095, 7164-7167): OK
44. Kick: ready < 3.7, height < 1.7, window 0.58, hit < 2.65, height < 1.6, facing > 0.55, not mid-pounce, cooldown 2.6 / 6.0, baton contact knock 11 (8137-8184): OK
45. `officerBatonContact`: knock away, vy >= 3.1, detach rail, -19 Power (8012-8024): OK
46. "Universal escapes: being mid-pounce": FIXED (presented as universal -> pedestrian kicks only; batons, cats and hospital staff ignore `attackWindow`)
47. Patrol cop baton trigger < 3.6, windup 0.54, hit < 2.85, dy < 2.4, knock 14, cooldown 2.0 (8026-8075): OK
48. Incident officer < 3.4, 0.48 s, hit < 2.9, dy < 2.3, knock 12, cooldown 2.4 (11134-11153): OK
49. Station reinforcement shove 10 / vy 2.3 / cooldown 4.4 within 24; precinct guard 11 / 2.4 / 4.1 within 34 (11158-11207): OK
50. Hospital staff telegraph 0.76 s (orderly 1.0 s), range 4 / 7.2, hit 2.45 / 3.6, knock 10.8, vy min(3, 2.376), cooldown 6 (8819-8843): OK
51. Cat swat < 3.0, 0.68 s crouch, hit < 2.75, height < 2.4, knock 10.5, vy >= 3.9, -12 Power, cooldown 7 / miss 4 (11580-11640): OK
52. `knockPlayer` ignored in duct, zeroes `attackWindow`, `cameraCommit 0.38`, `vy = min(3, 0.22*str)` (8665-8677): OK
53. Constants CHILI_COUNT 8, POWER_DECAY_INTERVAL 600, RATE 0.15, RUSH_DURATION 30, RUSH_SPEED 1.6 unused (5308-5312): OK
54. Power decay `max(1, ceil(points*0.15))`: OK; added that it only applies when points > 0 (5510)
55. Rush cap 90 s, +1 gold per chili, idle reset, 990 Hz (5483-5505): OK
56. STATE label FERAL < 600, RABID >= 600, SUPER >= 1500; bar at 1500 (5465-5469): OK
57. Pepper seed via `crypto.getRandomValues` with fallback (5313-5321): OK
58. Tree pepper trees BUR OAK (-34, -33), AMERICAN ELM (32, -37), SYCAMORE (-37, 29), RED MAPLE (34, 34) (1694-1736): OK
59. Tree pepper t-ranges [0.34, 0.82] / [0.32, 0.77] and offsets; elevated generators and offsets (5389-5420): OK
60. Garden pepper x 125 + U(0, 5.5), z 331 + U(0, 11), +0.7 (GARDEN_X 115, GARDEN_Z 341 at 3590-3591): OK
61. Eight yard spots and their coordinates (5431-5438): OK
62. Chili mesh 13 rings x 10 sides, emissive 0.14, colour list (5330-5385): OK
63. Pickup radius 2.2 trunk / 1.4 otherwise (5488): OK
64. Accessibility audit: trunk to 1.4 from treeSpec centre, y >= terrain + 1.0; ground y >= +0.43 else +0.7; footprint shift (+5.2, +5.2) at +0.75; route snap > 2.5 to +0.3 (10395-10434): OK
65. Galleria coins 12 shop + 8 gallery + 4 fountain = 24 brass, 1 gold at (MALL.x, gallery+0.6, MALL.z-50), radius 0.95 (14631, 14753-14755, 14976-14982, 15068-15090): OK
66. Fountain toss -1 coin, 11.5 radius, 0.7 s cooldown (15002-15025): OK
67. Wardrobe names and colours, 3 x 10 (8233-8307): OK
68. Hat shapes per k, jacket ellipsoid r 0.51 scale (0.85, 0.66, 1.33), pants 4 boxes 0.24 x 0.2 x 0.43 (8330-8360): OK
69. Unlock at `totalCoinsEarned >= 150`, price 35 coins / 3 gold for k = 8, lock check before owned check (8380-8411): OK
70. Shop hint texts (9079-9089): OK
71. `localStorage` keys `spicy-rodents-wardrobe-v1` (8311, 8367) and `spicy-render-v5` (115, 12910); validation rules: OK
72. Sewer A (123, 334), corner (123, 264), B (200, 264), floor -3.4, legs 70 / 77 (3727-3734): OK
73. Sewer geometry: slab 5.8, walls ±2.85 x 4.6, trim ±2.63 at +2.75, ceiling +4.7, posts every 9, lights (123, 281) and (165, 264) at +3.1 (3741-3778): OK
74. Grates r 2.1 at +0.17, 5 bars, label 4.2 x 1 at +3.2 Z (3759-3766): OK
75. Stand at (130, floor+0.2, 264), box 2.3 x 3.2 x 1.3, 3 shelves, cone mini hat (3780-3786): OK
76. Sewer entry E within 5 and |dy| < 3; teleport positions (z -0.85 / -0.55 inside, +2.5 outside) (7892-7949): OK
77. `constrainSewer` clamps to 2.2 of polyline (7884-7891); ground `sewerFloorY + 0.25` (6742): OK
78. Sewer fog 15 / 53, camera far 65, background #373f38, exposure 1.1 (9116-9131): OK
79. Vents at HOSP (-356, 353) offsets, heights 2.8 / 7.6, first and upper flags (3802-3803, 4119-4125): OK
80. Chew start radius 4.7 / 3.2, duct height tolerance 2.6; cancel at 1.3 from origin or 4.9 / 3.2 from vent; 120 s / 24 s; progress kept (8578-8592, 8867-8897): OK
81. `dropFromHatch`: radius 2.9, y > floor + 4, spawn floor + 7.6 - 1.15, horizontal 7.4 / 2.3, vy -5.7, cooldown 0.86, window 2.5 (8526-8555): OK
82. Hospital actors are `n.hospital = true` and skipped by `updateHumans` (4991, 7015), so their alert stays 0: OK
83. Trampoline at (-33, 80), mat r 4.95 y 1.45, 12 poles, guardrail route y 5.97 r 5.12 (1422-1463): OK
84. Bounce: r < 4.67, prev y >= 1.72, y <= 1.92, falling; count cap 4; vy 14.2 + 0.9n; +1.6 forward; cameraCommit 0.4 (10373-10392): OK
85. Bounce count reset > 9 from centre, flex decay 2.8/s, mat dip 0.35 (10242-10245): OK
86. Idle: movement > 0.035 per frame, warn at 779 s, 1.03 s warning, game over at 780, 310 / 130 Hz (8208-8231): OK
87. `predatorForPlace` order and texts; shelter zones table (8186-8197, 3703-3709): OK
88. Predator overlay text (8198-8207): OK
89. Hidden win: infection >= 50, staff and patients >= ceil(8/2): OK; clarified that both count distinct individuals (Sets)
90. Infection gains +3.6 / +5.7 / +6.2, decay 0.011 (0.05 in duct), squirrel share 25/7 each over 1500 s, needs own >= 25 and bite within 600 s (8634-8644, 8849-8866): OK
91. Run-over swept test padding 0.18, Y -0.3 to height-0.16, disabled in hospital, sewer or duct (15772-15897): OK
92. Restart button reloads the page (7869): OK
93. `validatePlayerState` NaN or y < -150, safe position every 0.5 s while grounded, off rail, out of duct (13300-13315): OK
94. HUD element ids and labels (shell:135-136); bar colours #d1ee83 / #e6b265: OK
95. District tag conditions (9062-9078): OK
96. HUD parts, presets FULL / PLAY / NAVIGATION / CLEAN, M behaviour (9801-9836): OK
97. K editor "(CUSTOM mode)": FIXED (opening sets CUSTOM -> only changing a checkbox sets CUSTOM; opening releases pointer lock)
98. Compass formula, 17 labels x 46 px, translate `(4 - heading/45)*46` (9854-9871): OK
99. Audio cue frequencies (pounce 640, bite 150, miss 100, counter 880, chili 990, decay 160, baton 180, vent 560, dance 680, infected 810): OK
100. Bite dance trigger per decade, 2.1 s, envelope `min(1, 6t, 6*remaining)`, spin 0.78 x sin 12t, roll 0.17, hop 0.19, head 0.24 (10345-10369): OK
101. Wanted posters at `hits > 8` on every 7th pole (11266-11284, 7059): OK
102. Frame order in `updateGameplay` (15940-15968): OK
103. v4.1 nut caches 10, E within 2.85, 3 / 5 / 7 coins, +5 Power, resets clock (v4_1:12237-12320, 12737-12748): OK
104. v4.1 fox lunge < 2.15, warning < 6, knock 9, vy >= 3.5, -17 Power, cooldown 4.8 (v4_1:12632-12649): OK
105. v4.1 fox bite 70% / 18%, deer 15% (v4_1:12651-12700): OK
106. Brief quotes in section 25 (brief lines 64, 214-225, 255-275, 294-295, 178, 197, 345) and addendum A1 to A3: OK

JSON: this deliverable has no JSON files. As a sanity check, every file in `spec/data/` (human_cast, lots_core, lots_districts, roads, routes_catalog, traffic_lanes, wildlife) parses with `JSON.parse`. They belong to other subsystems and were not modified or spot-checked here.
