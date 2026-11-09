# Routes and Squirrel Movement Core: v5.4 porting spec

Subsystem: **routes_movement**. It covers the climbing-route registry, every route generator, junctions and forks, route acquisition, the leap, ground motion and collision, roof landing, the per-frame player update, the camera, recovery rules and input.

Line numbers refer to `reference/v5_4_game.js`. Units are HTML world units (1 u is about 2.5 studs, +Y up, models face +Z). Where a stud value helps, it is shown as `(≈N st)`.

Companion data file: `spec/data/routes_catalog.json` has one entry for each of the 60 `addRoute(` call sites. Each entry gives the generator formula, exact instance count, speed, surfaceRadius, visualOffset and connectivity.

## 0. How the numbers were verified

- All constants were read from the code at the lines cited.
- Route counts, lengths, Y ranges, sample counts, fork counts and connectivity come from a headless run. The unmodified v5.4 HTML ran in headless Chrome (SwiftShader WebGL). Two changes were made to a scratch copy only: a stack capture on line 326, and a dump appended after startup. The run registered **1,332 routes**, all 60 call sites were used, and canopyForks had **95** trunk entries. Route geometry is deterministic because it uses seeded RNGs.
- Anything derived by reasoning rather than code or run output is marked **(inferred)** or **(computed)**.

---

## 1. Route registry (lines 262–329)

### 1.1 Data model (`addRoute(name, points, opts)`, line 294)

| Field | Value / rule | Line |
|---|---|---|
| `id` | `uid++` (creation order, 0..1331) | 315 |
| `name` | free string. **Behaviour depends on names** (see §4) | 316 |
| `curve` | `THREE.CatmullRomCurve3(points.clone(), closed=false, "centripetal")` (alpha 0.5) | 302 |
| `length` | `curve.getLength()`. Must be finite and >= 0.04, or the call throws | 307–309 |
| `sampled` | `curve.getSpacedPoints(steps)` with `steps = max(20, ceil(length*3))`, so `steps+1` arc-length-spaced points (spacing about 0.33 u, ≈0.83 st; at least 21 points) | 310–311 |
| `kind` | `opts.kind \|\| "branch"` | 319 |
| `speed` | `opts.speed \|\| 1`. **Stored but never read by any movement code.** Only makeTree trunks set it (0.82). | 321 |
| `center` | `opts.center \|\| null`. **Stored but never read.** Set on makeTree, outer, giant and apple trunks. | 322 |
| `surfaceRadius` | `opts.surfaceRadius \|\| 1.35`. Used for the trunk visual offset and as `trunkClearance` for forks. | 323 |
| `visualOffset` | `Number.isFinite(opts.visualOffset) ? opts.visualOffset : null`. Only apple boughs set it (0.3). | 324 |
| `indexed` | set by `indexRoute` | 292 |
| `trunkClearance` | added later by `rebuildCanopyForks` to fork branches. It is the max of the parent trunk surfaceRadius values. | 4348 |

Validation (port this): `addRoute` throws when there are fewer than 2 control points or any coordinate is non-finite (295–301), and when the length is not finite or below 0.04 (307–309), or any sampled point is non-finite (312–313). `verifyRouteRegistry()` (16034) re-checks every route before the main loop starts.

### 1.2 Route parameter math (`RouteMotion`, line 267)

```
advance(t, dir, forward, seconds, speed, length):
    dt = clamp(seconds, 0, 0.05)
    return t + forward * dir * dt * speed / max(1, length)
```

- `t` is the arc-length fraction in [0,1]. Positions use `curve.getPointAt(t)` and tangents use `getTangentAt(t)`. Both are arc-length parameterised in Three.js.
- `speed` here is the computed rail speed (§10), **not** `route.speed`.
- `max(1, length)` slows any route shorter than 1 u. That affects only the 0.86-u OPEN SKY LOOKOUT pads.

### 1.3 Spatial index (`indexRoute`, line 277)

- `routeSpatial: Map<"ix,iy,iz", Array<{route, pos, t}>>` with cell size **8 u** (≈20 st) on all three axes: `floor(x/8), floor(y/8), floor(z/8)`.
- Each sampled point becomes one entry, with `t = i/(sampled.length-1)`. The headless run has **81,613** entries.
- Index timeline: routes created before line 4319 are buffered. At 4319 `routeIndexLive = true` and every existing route is indexed. Routes created after that (treehouse, westside, police roof, quay, galleria, apples) are indexed inside `addRoute`. `rebuildCanopyForks()` runs once at 16055, after all world zones exist.
- Queries:
  - `nearestRoute(maxDist, excluding, point)` (5718) scans ±ceil(maxDist/8) cells and returns the closest sample `{route, t, d}`, skipping `excluding`.
  - `switchRoute` and `junctionCandidates` scan the 3x3x3 neighbourhood.
  - `groundTrunkCandidate` does **not** use the index. It loops over all routes (§9.1).
- Routes are never removed or mutated after startup. No code splices `routes` or deletes index entries.

### 1.4 Route kinds (8 kinds; counts from the headless run)

| kind | count | total length (u) | rail speed mult | visual lift / offset | camera behind | A/D on it | can auto-switch **onto** a trunk at its end | in canopy forks |
|---|---|---|---|---|---|---|---|---|
| trunk | 265 | 4,086 | ×0.6 | radial offset off bark (§14) | side-on rig, 3.25 out (§15) | `chooseCanopyFork` | n/a | is the parent |
| branch | 715 | 11,238 | ×0.6 | +`visualOffset ?? 0.5` Y (+trunk-clearance push near t<0.2) | 3.2 | `sideStepToSibling`, else `chooseRouteJunction` | no | yes (child) |
| bridge | 78 | 1,417 | ×0.6 | +`visualOffset ?? 0.5` Y | 3.2 | `chooseRouteJunction` | **yes** (only kind) | yes if name-matched |
| lookout | 12 | 55 | ×0.6 | +`visualOffset ?? 0.61` Y | 3.2 | `chooseRouteJunction` | no | park perches only |
| roof | 99 | 1,700 | ×1 | none | 3.7 | `chooseRouteJunction` | no | no |
| wire | 150 | 6,979 | ×1 | +0.22 Y | 3.5 (eye +2.35) | `chooseRouteJunction` | no | no |
| fence | 12 | 920 | ×1 | none | 3.2 | `chooseRouteJunction` | no | no |
| trampoline | 1 | 32 | ×1 | none | 3.2 | `chooseRouteJunction` | no | no |

Notes:
- There is **no "pole" kind**. Utility poles, downspouts and ladders are all `trunk` and are told apart only by name (§4).
- "Tree travel" (`["trunk","branch","bridge","lookout"]`, lines 6617 and 6671) gets the ×0.6 speed multiplier and the slower gallop cadence.
- `squirrelActuallyInTree()` (4785) counts branch, trunk or lookout above y 3.2, but not bridge, and only for NPC dialogue lines.

---

## 2. Route generators (summary; full detail in the JSON)

There are 60 `addRoute` call sites and 1,332 instances. The groups below are ordered by creation, and that order matters (§3).

| Family | Generators (line) | Instances |
|---|---|---|
| East commercial roofs | Chili's roof 733; gas station roof 794; fuel canopy E-W 832 and crosswalk 837; canopy ladder 854 (trunk, r 0.18); ladder roof link 863 (bridge); corner shops roof 907 | 7 |
| Original 4 houses | `${cfg.kind} ridge` 1237 | 4 |
| Fences | cedar fence top 1329; chain-link fence top 1354 | 8 |
| Trampoline | guardrail ring 1453 | 1 |
| Utility grid | `pole()` trunk 1627 (r 0.4); `stringUtilityRoute` wires 1650; house service cables 1679 | 97 + 102 + 4 |
| Named trees (`makeTree`) | trunk 1782 (speed 0.82, r 1.18, center); bough 1830; living bridge to wire 1896; rooftop canopy crossing 1926. Used by the 4 original trees, addExtraCanopy (10), the Treehouse Oak, Westside shade oaks (7) and street elms (4), and QUAY WILLOW (6) | 32 + 295 + 15 + 10 |
| Outer neighbourhood houses | `neighborhood rooftop ridge` 2136 (rotated) and 2142 | 9 + 11 |
| Outer and park trees (`makeOuterTree`) | trunk 2240 (r 0.81, center); bough 2258; canopy-to-wire bridge 2351 | 44 + 303 + 25 |
| Giant lookout trees | giant trunk 2428 (r = 0.95·r_tree); high lookout bough 2458; OPEN SKY LOOKOUT pad 2478 | 3 + 21 + 6 |
| South estates | tennis net 2674 (fence); guesthouse roof 2695; mansion roof 2748; gate oak trunk 2835 (r 1.55); major bough 2859; avenue cable 2922; avenue poles 2933 (r 0.4); oak living utility bridge 2971 | 2+2+2+4+24+5+6+2 |
| North park / cemetery / garden | park footbridge 3385; park high watch perch 3419 (lookout); park phone wires 3432; tree-to-phone-line wire 3441; crypt roof 3562; wheelbarrow perch 3667 (lookout) | 1+3+2+1+1+1 |
| House gutters | house downspout 4306 (trunk, r 0.14); gutter to roof 4313 (bridge) | 24 + 24 |
| Treehouse | ladder 9532 (trunk, r 0.35); floor 9551 (lookout); deck 9556 (lookout) | 3 |
| Westside | telephone pole 9903 (trunk, r 0.5); overhead phone line 9911 | 7 + 6 |
| Police | police roof 10073 | 1 |
| River bridge | tower downspout 13740 (trunk, r 0.15); tower gallery 13745 (roof); stone parapets 13762 (fence, 107 control points); suspension cables 13783 (wire) | 2+2+2+2 |
| Bellwether Quay buildings | roof ridge 13898; downspout 13902 (trunk, r 0.14); gutter to ridge 13903 (**roof** kind) | 30+30+30 |
| Bellwether bunting | bunting line 14086 (wire) | 28 |
| Galleria | downspout 14808 (trunk, r 0.15); rooftop 14809 | 2 + 2 |
| v5.4 orchard | `APPLE n trunk` 15184 (r 0.5, center); `APPLE n bough k` 15206 (**visualOffset 0.3**) | 12 + 72 |

Common geometry helpers:
- `droopBetween(a, b, sag)` (1637): 13 points, `lerp(a,b,t) - (0, sag·sin(πt), 0)` with `t = i/12`.
- Utility wire sag: `min(0.84, 0.26 + dist·0.004)`. Fixed sags elsewhere: estate cable 0.3, park 0.36, westside 0.42, tree-to-line 1.1, house drop 1.0.
- `pole(x,z)` (1615) is deduplicated by `poleKey = x.toFixed(2),z.toFixed(2)`. It throws if `pavementDistance < 0.95`. Pole mesh height is 17.05 and the route control points are foot+0.48, foot+8.5 and top.

---

## 3. Creation-order dependencies and network topology

Bridges search the registry **as it exists when they are created**. A port that builds lots in a different order will connect them differently.
- The makeTree living bridge (1857–1896) goes to the nearest wire **sample** by XZ distance, if under 49. The bridge ends exactly on that interior sample.
- The makeTree rooftop crossing (1903–1930) goes to the nearest roof route by the 3D distance from its `getPointAt(0.5)` to the tree base, if under 64. It ends at that arc-length midpoint.
- The outer-tree canopy-to-wire bridge (2328–2351) goes to the nearest wire sample by XZ distance, if under 39.
- The estate oak bridge (2941–2971) goes to the nearest `estate avenue cable` sample by XZ distance.
- `addHouseGutters` (4292) goes to the nearest roof sample within 24 of the gutter top. It runs at 4316, after the estates and cemetery but before the treehouse, westside, quay, mall and apples.
- House service cables (1670) run while only the 4 original houses exist, so there are only 4 cables.
- Pepper hide spots (5389–5420) pick random roof, fence, trampoline, "phone line" wire and tree routes from the registry as it stood at ~5400 (pepper extractor's scope).
- Bird nests (15436) use 24 evenly spaced `branch` routes with /bough/ in the name and length > 3, at t = 0.66, raised +0.3 (APPLE) or +0.48.

**Connectivity (computed from the headless run).** Two routes are treated as linked when any sample pair is within 1.7 u (the explicit-transfer limit). With that rule:
- There are **149 islands**.
- The largest island has **563 routes**: the residential utility grid, the 4 original trees, 25 outer trees, house ridges and gutters, the fuel canopy (via Pump Elm) and the treehouse.
- The next islands are the south estates and villa trees (71) and the Westside poles plus street elms (55). Most others are single trees with their boughs.
- **40 singletons** are reachable only by leaping: all 28 Bellwether bunting lines, both tennis nets and guesthouse roofs, the Chili's, gas station, corner shop, mansion, crypt and police roofs, the park footbridge and the wheelbarrow perch.

**Endpoint auto-links (computed).** "Auto-switch" means another route's end window (t <= 0.07 or >= 0.93) is within 0.48 u, after the trunk filter.
- All branch tips are dead ends: 0 of 715 have a link.
- Branch starts usually tie with sibling boughs that share the same trunk node.
- Pole tops link to 1–4 wire ends (every one of the 16 residential row/column crossing poles has exactly 4 wire ends at its top: 2 row spans + 2 column spans, all at gap 0; a few poles also start a house service cable). Wire ends chain pole to pole.
- Living-bridge ends and rooftop-crossing ends land on **interior** samples, so they are never automatic. The player needs E, or A/D and then E.

---

## 4. Name-based behaviour (replace with explicit attributes in the port)

| Rule | Test | Line |
|---|---|---|
| Excluded from walk-in auto-grab and from `groundTrunkCandidate` | `/downspout\|gutter\|ladder/i` | 5746 |
| Pole: horizontal gate 1.85 when reach > 1.85, +0.2 rank penalty | `/telephone pole/i` | 5747–5759 |
| Trunk visual surface normal forced to (0,0,1), offset r+0.2 | name includes "downspout" or "gutter" | 6776–6779, 6784 |
| Trunk visual offset fixed at r+0.2 | includes "telephone pole" | 6777, 6784 |
| Giant taper `max(0.45, r/0.95 − 1.05t)` | includes "giant trunk" | 6781 |
| Fork parent/child matching: `tname = trunk.name.replace(/ (?:giant \|tree )?trunk$/, "")`, child must `startsWith(tname + " ")` | prefix | 4328–4334 |
| Park watch perch is a fork of any trunk within 1.4 | `name === "park high watch perch"` | 4333 |
| Pepper hides on boughs and phone lines | "bough", "phone line" | 5390–5416 |
| Nest boughs | `/bough/` | 15436 |

Quirks:
- Several trees share one name. The 4 `estate oak trunk`s and the 6 `QUAY WILLOW`s each share a prefix, so the 3.0 distance test is the only thing separating their boughs.
- The `telephone pole climb …` and `house downspout` trunk names do not end in " trunk", so their `tname` is the full name and they never get forks.

---

## 5. Player movement state (`player`, line 5127)

| Field | Initial | Meaning |
|---|---|---|
| `pos` | (−36, 0.31, −36) | physics position (on a route: exactly on the centreline) |
| `vel` | 0 | velocity (zeroed while on a route) |
| `yaw` | 0 | body heading; forward = (sin yaw, 0, cos yaw) |
| `grounded` | true | |
| `rail`, `railT`, `railDir` | null, 0, 1 | current route, parameter, travel sign |
| `transferCooldown` | 0 | set to 0.4 or 0.55, decremented, **never read** (vestigial) |
| `moveSpeed` | 0 | smoothed scalar speed (used by animation, camera and pounce) |
| `focus` | false | first-person stalk active |
| `boostRemaining` | 0 | chili rush seconds (+30 per chili, cap 90; lines 5311, 5492) |
| `cooldown`, `attack`, `attackWindow` | 0 | pounce timers (0.7, 0.38, 0.78) |
| `cameraCommit` | 0 | post-launch timer (0.52 leap/pounce, 0.32 Q-drop, 0.4 trampoline, 0.38 hospital knock, ≥0.35 after landing). Its **only** reader is the focus gate (focus requires `cameraCommit === 0`, 6585); it does not change any camera rig |
| `committedAirborne` | false | true after a leap, pounce, Q-drop or bounce until landing |
| `turnLean`, `nearRoute`, `alive`, … | | cosmetic and HUD |

Module-level movement state:
- Camera: `yaw = π`, `pitch = 0.12`.
- `keys: Set<code>`; `focusMouse`, `focusToggle`.
- Route transfer: `routeBridge`, `routeWasMoving`, `routeFreeLook`, `selectedJunction`, `pendingFork`, `canopyHintTime` (set but never read).
- Camera: `cameraHardCut`, `camPos`, `lookPoint`.
- Safety: `graphicsRuntime.lastSafe` (initial (−36, 0.31, −36), line 12856).

Squirrel size (headless bounding box at `SQUIRREL_VISUAL_SCALE = 0.335`, line 5155): 0.447 wide × 0.683 tall (with tail) × 0.951 long (≈1.1 × 1.7 × 2.4 st). Ground collision radius is **0.32** (6327).

---

## 6. Frame scheduling (15932–16031: updateOptional 15932, updateGameplay 15940, tick 15999)

- `tick()`: `dt = min(clock.getDelta(), 0.08)`, `activeDt = min(realDt, 0.2)`. Nothing runs while the document is hidden or the GL context is lost.
- Before play (`!playing`), the menu idles: `yaw = π + sin(time·0.08)·0.18`, `pitch = 0.2`.
- `updateGameplay` order: `beginTrafficFrame` → `updatePowerAndHeat` → **`updatePlayer` in substeps: `steps = max(1, ceil(dt/(1/60)))` (at most 5), each `dt/steps`** → `validatePlayerState(dt)` → peppers → NPCs and traffic (skipped in sewer and hospital) → … → `finishTrafficFrame` (fatal traffic).
- Then every frame: `updateScenery` → **`updateCamera(dt)`** → compass → bubbles → diagnostics → visuals → render.
- The movement and camera core are "critical": an exception stops the loop and shows an error panel. Peripheral systems are wrapped in `updateOptional` and disabled after one failure.

---

## 7. Movement state machine

```
States: GROUND (grounded, no rail) | AIR (no rail, !grounded) | ROUTE (rail != null)
        ROUTE has sub-state TRANSFER (routeBridge != null)
        Out of scope here but exclusive: DUCT (player.inDuct), SEWER, HOSPITAL, HOUSE INTERIOR / transits.

GROUND -> ROUTE   walk-in auto-grab (§9.1) | E: groundTrunkCandidate(3.1) or nearestRoute(3.4) (§9.2)
GROUND -> AIR     Space leap | left-click pounce | walk off an edge (ground < pos.y) | trampoline bounce | knockback
AIR    -> GROUND  pos.y <= getGroundAt | roof landing (§8.5) | mall landing
AIR    -> ROUTE   E in the air: nearestRoute(3.4) (no automatic catching of routes in flight)
ROUTE  -> ROUTE   end-of-route auto switch (§11.1) | A/D + E junction (§11.2) | E nearest transfer (1.95/1.7)
                  | trunk fork take (§12) | branch side-step (§12.4)
AIR    -> AIR     left-click pounce in mid-air (no grounded/rail check; re-launches every 0.7 s cooldown; see "Added by verifier")
ROUTE  -> AIR     Space leap | Q drop | left-click pounce | knockback (yard cat 11611; officerBatonContact 8012 via patrol baton 8057, pedestrian kick 8161, precinct baton 11141; hospital knockPlayer 8665)
any    -> (teleport) sewer, house entry, old home, hospital doors, start-at-river/mall, vehicle game over: rail = null
```

There is **no fall damage** and no stun on landing. The only landing side effect is `cameraCommit = max(cameraCommit, 0.35)` after a committed leap (6758–6761).

---

## 8. Ground and air motion (`updatePlayer`, 6573; ground branch 6707–6763)

### 8.1 Speed targets

`base = (inDuct ? (sprint ? 3.8 : 2.8) : focus ? 1.65 : sprint ? 16.8 : 8.0) × (boost && !focus ? 1.6 : 1) × (treeTravel ? 0.6 : 1)` (6618–6621).

| Mode | u/s | ≈st/s |
|---|---|---|
| Walk | 8.0 | 20 |
| Sprint (Shift) | 16.8 | 42 |
| Stalk (focus) | 1.65 | 4.1 |
| Walk / sprint with chili boost | 12.8 / 26.88 | 32 / 67 |
| Duct crawl (other scope) | 2.8 / 3.8 | 7 / 9.5 |

`moveSpeed = lerp(moveSpeed, moving ? base : 0, 1 − exp(−dt·(focus ? 11 : 17)))` (6622).

### 8.2 Velocity integration (no rail)

- Input direction is camera-relative: `dir = normalize(−sin(yaw)·fw + cos(yaw)·side, 0, −cos(yaw)·fw − sin(yaw)·side)`. W/S = fw, D/A = side, ArrowUp/ArrowDown alias W/S.
- With input and `attackWindow == 0`:
  - `a = 1 − exp(−dt·(grounded ? 23 : 4.2))`
  - `vel.xz = lerp(vel.xz, dir·moveSpeed, a)`
  - `yaw` turns toward dir at rate 25, or 19 in focus. `turnToward(old, desired, rate, dt) = old + wrap(desired−old)·(1 − exp(−rate·dt))` (6570).
- No input and `attackWindow == 0`: `vel.xz *= exp(−dt·(grounded ? 13 : 1.15))`.
- While `attackWindow > 0` (pounce flight) there is **no** steering or drag, so the flight is ballistic.
- Focus with no input: body yaw turns toward the camera (`yaw+π`) at rate 11.
- **Gravity `SQUIRREL_GRAVITY = 30`** u/s² (6472) ≈ 75 st/s². Roblox's default is 196.2 st/s², so use a custom value.
- Integration: `pos += vel·dt`, then in order:
  - `constrainMallCeiling(old)`
  - `landedOnRoof = resolveMallLanding(old) || resolveRoofLanding(old)`
  - In hospital: `adjustHospitalMovement`. Not in sewer: `resolveOutdoorMovement(old)`, and revert XZ if inside the hospital shell. In sewer: `constrainSewer`.
  - `recoverTrappedInHouse()`
  - Ground snap (§8.4).

### 8.3 Swept horizontal collision (`resolveOutdoorMovement`, 6411; `outdoorBlocked`, 6324)

- Steps: `steps = clamp(ceil(|Δxz|/0.24), 1, 18)`. Each step tries X, then Z, separately (sliding). If both fail it tries the diagonal once. A blocked axis multiplies that velocity component by 0.28.
- `outdoorBlocked(x, z, y)` uses r = 0.32 and `y = player.pos.y` in **absolute** world Y. It is true when any of these hits:
  1. `mallBlocked`, then `riverBlocked` (other scopes; AABB colliders with y0/y1, ramp faces).
  2. Westside old homes (7): inside `depth/2 + r` (X), `width/2 + r` (Z) and `y < by + height + 0.15`. The active or transiting home passes.
  3. Active house interior: outside `w/2 − 0.68 − 0.0256`, or inside an interior obstacle + r. Otherwise every house (24): `y < cfg.h − 0.35` and inside `w/2 + 0.53`, `d/2 + 0.53`.
  4. commercialBounds (8): `y < roof − 0.35` and inside `w/2 + r`, `d/2 + r`.
  5. **Only if `y < 3.1` (absolute)**:
     - Tree circles (95 trees, radius 1.48 regardless of trunk size).
     - Fence segments (8): `y <= f.height + 0.25` and distance to the segment < r + 0.05 = 0.37.
  6. Cars (29): OBB `|lx| < 1.175 + r`, `|lz| < 2.225 + r`, `y < terrain(car) + 1.94` (broad phase ±4.5).
  7. Tall vehicles (9 at startup: delivery van 3.0×5.9×3.65, ice-cream van, trolley, dump trucks/RVs): OBB `w/2 + r`, `l/2 + r`, `y < car.y + height − 0.1`.
- **Quirk:** steps 3 and 5 compare absolute Y, not height above terrain. On hills higher than ~3 u (for example APPLE 5 at y 6.6), trees and fences do not block, and the main-house test only works because those houses sit near y = 0. The port should use height above local ground. **(Design fix recommended.)**
- `collisionHouses` (6250) and `preventVehicleOverlap` (6098) are **dead code** (never called). A vehicle moving into a stationary squirrel does not push it; the run-over test is the only interaction (fatal-traffic scope).

### 8.4 Ground height (`getGroundAt`, 6227) and landing

`y = max(terrainHeight, outdoorSurfaceAt) + 0.18` (pavements and curbs, 513). The sources below can raise it further:

| Source | Condition | Ground value |
|---|---|---|
| mall surface (floor, gallery, stairs, fountain) | base floor always; gallery, stairs and fountain rim only when `pos.y >= surface − 0.55` (`mallSurfaceAt`, 14354) | +0.18 |
| river deck / platforms | `pos.y >= surface − 0.5` | +0.18 |
| **car roof** (`vehicleHitboxAt`: car box 2.35×4.45×2.04, plus tallVehicles) | `pos.y >= top − 0.32` | `top + 0.16` |
| any roof (`roofSurfaceAt`) | `pos.y >= roof − 0.47` | roof |
| porch at (−58, 83) ±6.5/±6.0 | `pos.y > 5.2` | 6 |
| trampoline bed r < 5 around (−33, 80) | `pos.y > 1.1` | 1.65 |
| treehouse floor (±4.2, ±4.0 of (−142, 154)) | `pos.y > base + 13.2 − 1.1` | base + 13.46 |

Landing rule (6741–6762):
- If `landedOnRoof`: `pos.y = max(pos.y, ground)` and grounded.
- Else if the trampoline bounces, keep the bounce.
- Else if `pos.y <= ground`: snap, `vel.y = 0`, grounded. If `committedAirborne` was set, clear it and set `cameraCommit >= 0.35`.
- Else `grounded = false`.

There is no general step-height limit for terrain and pavement (`terrainHeight`/`outdoorSurfaceAt` are always stepped onto). The raised sources carry their own implicit step-up tolerance through their `pos.y` gates in the table: roof 0.47, car roof 0.48 (top+0.16 vs top−0.32), river deck 0.68, porch 0.8, trampoline bed 0.55, treehouse floor 1.36; walls (`outdoorBlocked`) usually stop the squirrel before these matter. Walking downhill briefly sets `grounded = false`, which switches to air acceleration 4.2 **(inferred feel issue)**.

Trampoline (10373):
- Applies when inside radius 4.67 of (−33, 80), the previous y was at least 1.72, the new y is at most 1.92, and the squirrel is falling.
- Result: `y = 1.90`, `vel.y = 14.2 + 0.9·count` (count is capped at 4 and resets beyond 9 u), +1.6 u/s along the camera forward, committedAirborne, cameraCommit 0.4.

### 8.5 Roof landing (`roofSurfaceAt`, 6111; `resolveRoofLanding`, 6147)

`roofSurfaceAt(x,z)` is the max of these sources (null if none):

| Source | Footprint test | Surface height |
|---|---|---|
| `riverRoofAt` (30 Bellwether buildings, rotated, gabled) | local footprint + 0.55 / 0.65 | `base + h + rise·max(0, 1 − \|lz\|/(d/2 + 0.65)) + 0.29` |
| `mallRoofAt` | inside the mall | `MALL.roof + 0.18` (= 23.12) |
| `riverSurfaceAt` | deck / platforms | +0.18 |
| houses (24; skips the active interior) | `\|dx\| < w/2 + 0.24`, `\|dz\| < d/2 + 0.2` | `roofY(dx,dz) + 0.29`: gabled profile for the 4 original houses (1214–1226); **flat at `peak` (absolute) for the 20 outer neighbourhood homes** (`roofY: () => peak`, 2129) |
| Westside old homes (7) | `(depth+1.7)/2`, `(width+1.7)/2` | `by + height + 0.56` (flat) |
| commercialBounds (8) | ±0.15 | `roof + 0.17` |
| hospital shell | not inside hospital or duct; ±1.2 | `HOSP_BASE + 13.34` |

`resolveRoofLanding(old)`:
- Skipped on a rail, inside any interior, sewer, hospital or duct, or during transits.
- Requires falling: `vel.y <= 0` and `pos.y <= old.y + 0.01`.
- Lands when all of these hold: `pos.y <= top + 0.08`, `old.y >= top − 0.5`, and (`prevTop` is null or `old.y >= min(top, prevTop) − 0.5`), where `prevTop = roofSurfaceAt(old)`.
- Effect: `y = top`, `vel.y = 0`, grounded, `committedAirborne = false`.

This continuous downward-crossing test prevents tunnelling at leap speeds. After landing, ground motion continues on the roof plane. House walls do not block above `cfg.h − 0.35`, so roofs are free-walk areas, and the ridge routes are optional rails on top.

### 8.6 Recovery and limits

- **World clamp** every substep: x ∈ [−586, `RIVER.endX` − 4 = 1146], z ∈ [−560, `NORTH_LIMIT` − 4 = 436] (6765–6766).
- **`recoverTrappedInHouse`** (6179). Runs only off-rail and outside interiors. It applies when inside a house shrunk by 0.5 (or a Westside home) and `pos.y < roofTop − 0.7`:
  - Near the floor (`pos.y < ground + 1.05` with `ground = terrain + 0.2`, i.e. below terrain + 1.25): push out to the nearest wall + 1.1 and set y to terrain + 0.2.
  - Otherwise: set y to the roof top.
  - Then zero the velocity and set grounded.
- **`recoverRiverFall`** (14116). In the river water below `waterY + 0.45`, teleport to the nearest bank (`riverCenter(z) ± (halfWidth + 5)`, `bankY + 0.18`, with z clamped to [−225, 425]). Zero the velocity, set grounded and `attackWindow = 0`, hard-cut the camera, and show the "SPLASH!" flash (2 s cooldown).
- **`validatePlayerState`** (13300, once per frame after the substeps):
  - If any pos or vel component is non-finite or `pos.y < −150`: restore `lastSafe`, zero vel, `rail = null`, `grounded = false`, hard-cut, show "Recovered to your last safe position."
  - `lastSafe` refresh: `safeClock += dt` every frame regardless of state; once `safeClock > 0.5` the first frame that is grounded, off-rail and out of the duct copies `pos` into `lastSafe` and resets the clock (13310–13314). So it is "at most every 0.5 s, whenever grounded", not "after 0.5 s of continuous ground". It can be a roof, mall, sewer or hospital floor position.

---

## 9. Getting onto a route

### 9.1 Walk-in auto-grab (6630–6642)

Conditions: no rail, grounded, not in sewer, hospital or house transit, `attackWindow == 0`, `fw > 0` (W held) and `moveSpeed > 0.45`. Then:

```
c = groundTrunkCandidate(pos, reach=2.0)
if forwardIntoTrunk(c, fw, side): enterRoute(c)
```

`groundTrunkCandidate(point, reach)` (5742):
- Considers only kind == trunk, skipping /downspout|gutter|ladder/i.
- Uses the foot point `sampled[0]`.
- Poles: if reach > 1.85 and the horizontal distance to the foot is > 1.85, skip.
- Requires `horizontal <= reach` and `|point.y − foot.y| <= 3.1`.
- Rank = `horizontal + rise·0.24 + (pole ? 0.2 : 0)`; the lowest wins. Returns `{route, t: 0, d}`.

`forwardIntoTrunk` (5767): true if the foot is within 0.12, else when the camera-relative move direction · direction-to-foot > **0.43** (within about 64.5°).

### 9.2 E: `attachRoute` (5870)

Called after `handleInteraction()` (mall, hospital, sewer grates and stand) and `takeSelectedFork()` both decline.
- **On a rail:** `takeSelectedJunction()` → `takeSelectedFork()`. If a fork is pending on a trunk, show "Climb closer…". Else `next = nearestRoute(1.95, excluding current)` and transfer if `next.d <= 1.7`; otherwise "Continue toward a branch junction, or press Q to drop."
- **Off a rail:** `found = (grounded ? groundTrunkCandidate(pos, 3.1) : null) || nearestRoute(3.4)`. This works **in mid-air** too: the "leap, then E near a wire" mechanic.
- Off-rail HUD prompt: at the end of every `updatePlayer` call (i.e. every substep, up to 5 per frame; 6876) `nearRoute = nearestRoute(2.3)`. If no message is showing, flash "E to grab: …" with probability `dt·0.09` (dt = substep dt).

### 9.3 `enterRoute(found)` (5826)

1. Rejects invalid input. If **already on a route** and the gap from `pos` to `dest = curve.getPointAt(t)` is > **3.15**: flash and fail.
2. `routeBridge` (transfer easing) is used only when already on a route and gap > 0.11: `{from: pos, to: dest, duration: clamp(0.13 + 0.065·gap, 0.15, 0.31)}`. **From the ground or air the squirrel snaps to `dest` immediately** (up to 3.4 u). Visual smoothing then lerps the mesh (§14).
3. `railT = t`, `railDir = RouteJunction.inward(t, found.dir ?? directionFromView(route, t, 1))`.
4. `routeWasMoving = found.dir !== undefined && (W||S held)`. If transferring between routes, `routeFreeLook = max(routeFreeLook, 0.65)`.
5. `resyncRouteHeading`: `player.yaw = atan2` of the route's XZ tangent × dir, skipped if the tangent XZ is degenerate (< 0.01 length).
6. On a trunk: `trunkNormal = normalize(approach − dest)` in XZ, or the camera-forward vector if under 0.12 u. Otherwise `clearPendingFork()`.
7. `selectedJunction = null`, `vel = 0`, `grounded = false`, `committedAirborne = false`, then flash.

`RouteJunction` (5782), pure helpers:
- `inward(t, d) = t < 0.035 ? 1 : t > 0.965 ? −1 : d`
- `canTransfer(gap, explicit) = gap <= (explicit ? 1.7 : 0.48)`
- `ease(p) = smoothstep(p)` (p²(3 − 2p))

---

## 10. Moving along a route (6655–6706)

- **During TRANSFER** (`routeBridge`): `elapsed += min(dt, 0.05)`, `pos = lerp(from, to, ease(elapsed/duration))`, vel 0. When complete, `routeBridge = null`. Input is ignored until it finishes.
- **Direction choice:** when movement starts (`!routeWasMoving && fw != 0`), `railDir = directionFromView(route, t, railDir)`:
  - Trunk: always +1 (W climbs up, S climbs down).
  - Else compare the route's XZ tangent with the camera forward. If |dot| > 0.18, use its sign. Else use the body facing if |dot| > 0.28, else keep the current direction.
  - The direction is held for as long as the key is held, so a curving cable cannot flip W mid-span.
- **Rail speed** (6668–6671): `railSpeed = (focus ? 1.2 : sprint ? 12.2 : 7.2) × (boost && !focus ? 1.6 : 1) × (kind ∈ {trunk, branch, bridge, lookout} ? 0.6 : 1)`. Then `railT = RouteMotion.advance(railT, railDir, fw, dt, railSpeed, length)`.

| Rail speeds (u/s) | walk | sprint | stalk | walk+boost | sprint+boost |
|---|---|---|---|---|---|
| wood (trunk/branch/bridge/lookout) | 4.32 | 7.32 | 0.72 * | 6.91 | 11.71 |
| wire/roof/fence/trampoline | 7.2 | 12.2 | 1.2 | 11.52 | 19.52 |

\* Focus can't be active on a trunk. In studs, multiply by 2.5 (for example 7.2 u/s ≈ 18 st/s).

- **Fork auto-take on trunks** (6676–6686): with a `pendingFork` on this trunk, holding W, `railT·L >= fork.t·L − 0.42` and `before <= fork.t + 0.022`: set `railT = fork.t` and `takeSelectedFork(force = true)`.
- **End of route:** if `railT` leaves [0,1], clamp it. If `fw != 0` and `!switchRoute(rs, atStart)`, it stays pinned at that end. Holding S at the foot of a trunk does **not** dismount; Q or Space is needed.
- **Pose:** `pos = curve.getPointAt(railT)` and `vel = 0`. If the tangent is significant (`|tx| + |tz| > 0.25`), body yaw turns toward `tangent × (fw != 0 ? sign(fw)·railDir : railDir)` at rate 14. While moving and not free-looking (`routeFreeLook <= 0`), the camera yaw follows `player.yaw + π` at rate 3.4.
- `routeFreeLook`: set to 1.7 by any mouse move while on a rail, kept >= 0.65 after a transfer, and reduced by dt every substep.

---

## 11. Junctions between routes

### 11.1 Automatic at route ends: `switchRoute(old, atStart)` (5941)

```
cur     = old end point; outward = end tangent pointing away from the route
search  3x3x3 cells around cur
cand    = other routes' samples with t <= 0.07 or t >= 0.93 and gap <= 0.48 (closest per route)
for c:  tangent = c.route tangent at clamp(c.t, .002, .998)
        dir     = inward(c.t, tangent·outward >= 0 ? 1 : -1)
        travel  = tangent*dir; view = cameraForwardXZ · normalize(travel.xz); continuity = travel·outward
        score   = 2*continuity + 2.9*view - 1.6*gap
drop    candidates of kind trunk unless old.kind == "bridge"
if none -> false (stay at end)
chosen  = selectedJunction's route if present among candidates
if !chosen and >=2 candidates and best-second < 0.65 -> flash "Junction ahead · A/D choose a line · E transfer" (only if no message showing) and return false
if !chosen and best.score < -0.75 -> false
enterRoute({route, t, dir})
```

Consequences:
- A pole-top crossing of 3–4 wires is chosen by camera direction. A near tie stalls the squirrel at the pole top.
- From a branch, roof or wire you can never auto-step onto a trunk, pole or downspout. Only bridges can (gutter-to-roof back onto a downspout, a living bridge back onto its trunk).

### 11.2 Explicit (A/D then E) on non-trunk routes

- **`junctionCandidates()`** (6004): only off-trunk. Within radius 2.15 of the current rail point (3x3x3 cells), non-trunk routes other than the current one, closest sample per route, keep `d <= 1.7`, sorted by distance.
- **`chooseRouteJunction(side)`** (6033):
  - `side`: D = +1, A = −1.
  - Keep candidates with `side · cameraRight · junctionOutward(c) > −0.08`, sorted by that value desc, then distance.
  - Repeated presses cycle through them. Sets `selectedJunction` and flashes "JUNCTION: name · E to transfer".
- **`junctionOutward(c)`**: the XZ vector from the current point to the candidate point if its length² > 0.24. Otherwise the candidate's tangent (from t ± 0.09) × intended direction.
- **`takeSelectedJunction()`** (6050): re-validates against fresh candidates, then `enterRoute` with `dir = directionFromView`.
- **`drawJunctionPreview()`** (6062):
  - Draws 4 dots (radius 0.13 − 0.012j, colour #f7e4a3, no depth test) at `t = sel.t + toward·(j + 0.4)·0.018`, raised 0.42 + 0.06·sin bob.
  - Clears the selection when it becomes invalid.
- On a branch, A/D tries `sideStepToSibling` first (§12.4).

---

## 12. Canopy forks (trunk → bough selection; 4321–4491)

### 12.1 Registration (`rebuildCanopyForks`)

For each trunk, look at every branch, bridge or lookout whose name starts with the trunk's `tname + " "` (or the park watch perch special case). If the branch start is within **3.0** (1.4 for the park perch) of a trunk sample, record:

```
fork = {trunk, branch, t (nearest sample), height, origin: branch start, outward: normalize(XZ(branch.getPointAt(0.19) − start))}
branch.trunkClearance = max(existing, trunk.surfaceRadius || 1.3)
```

Forks are sorted by height. Headless totals: **95 trunks with forks, 770 forks**, 5–15 per trunk. By parent: outer 44, makeTree 32, apple 12, estate oak 4, giant 3. Downspouts, poles, ladders, Bellwether and galleria pipes have none.

### 12.2 Choosing (A/D on a trunk)

`nearbyCanopyForks()`: forks with height in [h − 1.9, h + 10.5], where h is the current trunk point's y. If none, forks with |Δh| < 5.5.

`chooseCanopyFork(side)`:
- `right = cameraRightXZ`. Keep forks with `side·outward·right > −0.1`.
- Best = minimise `0.48·max(0, Δh) + 0.10·|Δh| − 3.2·max(0, side·outward·right)`, with Δh = fork.height − pos.y.
- Repeated presses cycle the same-side list (sorted by |Δh|) starting after the current pendingFork.
- Sets `pendingFork` and flashes "Chosen: …".

### 12.3 Taking it

`takeSelectedFork(force)`:
- Needs the rail to be the fork's trunk.
- `dist = |pos.y − height|`. Fail if dist > 2.15 unless forced; always fail if dist > 2.75.
- `enterRoute({branch, t: 0.018, dir: 1})`, `transferCooldown = 0.55` (unused), flash.
- It is reached by E (the key handler and attachRoute) or by holding W into the fork (§10).

`updateCanopyGuide` (4457), on a trunk:
- Shows the `#branchGuide` text: "↗ NAME · E TO TAKE BRANCH" when remaining < 2.2, else "CLIMB x m".
- Draws 5 glow markers (colour #e6faac, radius 0.105 + 0.01k) at `t = 0.055 + 0.05k` on the branch, raised 0.63 + bob.
- Clears pendingFork when it is no longer nearby and |Δh| > 12.
- Off a trunk it hides everything.

### 12.4 Side-step between sibling boughs (`sideStepToSibling`, 4423)

- Only on a `branch` with `railT <= 0.21`.
- Siblings are forks on the same trunk with |Δheight| < 2.9. Pick by `s = outward·cameraRight` with `s·side > −0.12`, maximum `s·side`.
- `enterRoute({route, t: 0.03, dir: 1})`, flash "BRANCH HOP".

---

## 13. Leaving a route or the ground

| Action | Effect |
|---|---|
| **Space: `leap()`** (5922) | Allowed if on a rail or grounded; in a duct it drops from the hatch instead. `heading = attackHeading()`: on a trunk this is `atan2(trunkNormal)`, i.e. straight out from the bark; otherwise `player.yaw`. Velocity `jumpVelocity()` = (sin h·F, **12.8**, cos h·F) with **F = 16.5** (18.5 when boosted). Then `launchFromVisibleRoute()` (pos = **visible mesh position**, clear pendingFork, `routeBridge = null`), `rail = null`, `grounded = false`, and `commitToAir(heading)`: `player.yaw = h`, camera `yaw = h + π`, `cameraCommit = 0.52`, `committedAirborne`, `focus = false`, hard cut. |
| Leap arc (computed) | Apex 12.8²/(2·30) = **2.73 u** (matches the code comment); airtime to the launch height 0.853 s. Horizontal distance on flat ground with no input ≈ **8.97 u**; holding W walk ≈ 8.8 u; holding W+Shift ≈ 14.3 u. Clears 2.0–2.1 fences and 2.04 sedans (landable roof); a 3.65 van is not clearable. |
| **Q: drop** (5672) | Only on a rail: `launchFromVisibleRoute`, `rail = null`, `vel = (0, 3.3, 0)` (a small hop up), `committedAirborne`, `cameraCommit = 0.32`. |
| **Left click: `attemptPounce`** (6482) | Allowed when `cooldown <= 0`, not inside a house, and not in a duct (there it drops from the hatch). `vel = pounceVelocity()`: `p = clamp(pitch, −0.54, 0.9)`, `speed = focus ? 12.4 : moveSpeed > 12 ? 13.5 : 11.3` (×1.12 when boosted), `vy = 3.45 + 2.1·sin p`, horizontal = speed·cos p along `attackHeading`. Sets `cooldown 0.7`, `attack 0.38`, `attackWindow 0.78`, then launches like a leap. Hit resolution is in the bite/combat scope (6506–6569). |
| Knockbacks | Yard cat strike (11611): 10.5 u/s away, vy >= 3.9 (hits within 2.75 u horizontally and < 2.4 u above the cat). `officerBatonContact(p, knock)` (8012): horizontal `knock` u/s away, vy >= 3.1, used by the patrol-car officer baton (knock **14**, 8057; < 2.85 u, < 2.4 u above), the brave-pedestrian **kick** (knock **11**, 8161; < 2.65 u, < 1.6 u above the kicker) and precinct officers (knock **12**, 11141; < 2.9 u, < 2.3 u above). All of these set `rail = null` and `grounded = false` but do **not** set `committedAirborne` or clear `pendingFork`. Hospital staff use `knockPlayer(dir, 10.8)` (8665/8834): vel = (d·10.8, min(3, 0.22·10.8) = 2.38, d·10.8), `rail = null`, `attackWindow = 0`, `committedAirborne = true`, `cameraCommit = 0.38`, hard cut (ignored in a duct). |

---

## 14. Visual placement (render position differs from physics position; 6769–6820)

Gameplay always uses `player.pos`, which sits on the route centreline. The mesh is offset from it as follows.

- **Trunk:**
  - `surface = (downspout|gutter in name) ? (0,0,1) : trunkNormal`.
  - `r = surfaceRadius || 1.3`.
  - `tapered = giant ? max(0.45, r/0.95 − 1.05t) : max(0.32, r·(1 − 0.48t))`.
  - `offset = (downspout/gutter or telephone pole) ? r + 0.2 : tapered + 0.28`.
  - `visual = pos + surface·offset`. The squirrel faces into the bark (`rotation.y = atan2(−s.x, −s.z)`).
  - Mouse X while on a trunk (outside focus) rotates `trunkNormal` about Y by `−dx·0.004` rad, so the squirrel orbits the bark.
  - **Quirk:** the Bellwether downspouts on rotated buildings still use world +Z. Each pipe stands at local (w/2 + 0.65, −d/2 − 0.65), i.e. 0.65 u out from both faces, and the offset is only 0.34, so the mesh lands on an arbitrary side of the pipe but never inside the wall (computed). Leap heading and the trunk camera use `trunkNormal`, not this +Z surface (see "Added by verifier").
- **branch / bridge / lookout:**
  - `y += visualOffset ?? (lookout ? 0.61 : 0.5)`.
  - Branches with `trunkClearance` and `t < 0.2` are also pushed outward along XZ(start → t 0.16) by `(trunkClearance + 0.31)·(1 − t/0.2)²` so the body clears the trunk.
- **wire:** `y += 0.22`. **roof / fence / trampoline:** no offset.
- **Ground:** when grounded and within 0.7 of `squirrelSurfaceAt`, visual y = `squirrelSurfaceAt` (5283). Feet are then settled by contact samples (`settleSquirrelFeet`, 5291).
- **Smoothing:**
  - Snap when the distance is > 2.5 (no transfer), or > 1.6 on a rail (no transfer).
  - Otherwise `mesh.pos = lerp(mesh.pos, visual, 1 − exp(−dt·(routeBridge ? 17 : 23)))`.
- **Animation hooks** (for the brief's clips):
  - `cadence = moveSpeed·(rail ? 0.7 : 2.85)·(boost ? 1.14 : 1)`.
  - Gallop bob amplitude: 0.022 + 0.0011·min(speed, 17) on the ground, or 0.042 + 0.002·… elsewhere.
  - Turn lean = clamp(−turnRate·0.035, ±0.31).
  - Trunk pitch lerps from −0.83 to −1.43 by `smoothstep(heightAboveTerrain, 0.25, 2.4)`.
  - The tail lies flat while climbing a trunk (5258).
  - `squash` is 0.9 in focus and 0.92 when sprinting.
  - The mesh is hidden in focus.

---

## 15. Camera (`updateCamera`, 7294; `airborneCameraRate`, 7431)

PerspectiveCamera(72°, near 0.12, far 1500) (line 26). `horizontal = (−sin yaw, 0, −cos yaw)` is the camera forward; `perp = (−h.z, 0, h.x)`.

| Mode (priority order) | desired (eye) | target |
|---|---|---|
| Duct (other scope) | duct path 1.15 behind, −0.4; hard-copied | duct path 2.55 ahead, −0.47 |
| **Focus / stalk** (first person) | `pos + (0, 0.27 + 0.005·sin(1.65t), 0)` | eye + 24·(h·cos pitch, sin pitch) |
| **On trunk** | `target + trunkNormal·3.25 + (0, 0.58, 0)` | mesh + (0, 0.18, 0) |
| **On other route** | `mesh − along·behind + perp(along)·0.45 + (0, wire ? 2.35 : 2.6 + 0.55·sin pitch, 0)`, behind = wire 3.5, roof 3.7, else 3.2 | mesh + along·0.85 + (0, 0.28, 0) |
| **Ground / air** | `mesh − h·d·cos(0.6·pitch) + perp·0.62 + (0, rise + 0.57·d·sin pitch, 0)`; d = air 5.5, speed > 11 → 4.2, else 3.35; rise = air 2.15 else 1.4 | mesh + h·(air 1.1 : 0.55) + (0, air 0.46 : 0.24, 0) |

- "Air" means `committedAirborne || (!grounded && !rail)`.
- On routes: `along = XZ(tangent·railDir)` (camera forward if degenerate), lerped toward the camera forward by `0.8·clamp(routeFreeLook/1.7)` (mouse orbit).
- **Constraints:**
  - Eye y >= `squirrelSurfaceAt + 0.4` before and after damping (outside hospital, sewer, duct and focus).
  - Hospital: clamp to the shell and floor+0.22..+11.2, plus a 16-step partition check.
  - House interior: clamp to w/2 − 0.55, d/2 − 0.55, y 0.6..h − 0.85.
  - Mall: segment-vs-AABB (`constrainMallCamera`) before and after damping.
  - **There is no general camera collision** against trees, houses or terrain walls elsewhere.
- **Damping:** `1 − exp(−dt·rate)`, rate = duct 11 (eye hard-copied, target 13), hospital 9.5, focus 17, else `committedAirborne ? 12 : 8.5`. `cameraHardCut` copies both and clears.
- **FOV:** lerp rate 9 toward duct 66, focus 61, committed air 74, `moveSpeed > 12` 68, else 62.
- **Mouse look** (5596):
  - Pointer lock only. dx and dy are clamped to ±90 px.
  - `sens = focus ? 0.0025 : 0.00315`; `boost = min(1.25, hypot(dx, dy)/35)`.
  - `yaw −= dx·sens·(1 + 0.18·boost)`; `pitch = clamp(pitch − dy·sens, −0.6, 1.07)`.
  - In third person a larger pitch raises the eye and so looks further **down**. In focus a larger pitch looks **up**. The observable behaviour differs between the two modes (verify in play).
- **C:** `yaw = player.yaw + π` (behind the animal), hard cut.

**First-person stalk (focus).**
- Active while (right mouse held or the F toggle is on) and not in a duct, playing, not `committedAirborne`, `cameraCommit == 0`, and not on a trunk.
- Lost when pointer lock is released.
- Shows the aim path (`updateAimPath`, 7258): 34 samples of `pos + vel·t − ½·30·t²` with `vel = pounceVelocity()`, t = 0.06 + 0.05i. It stops when it crosses `getGroundAt`.
- The line is #c9ddb0 at opacity 0.33. A landing ring (0.24–0.30, #e4f1d4) marks the hit.

---

## 16. Input mapping (v5.4; keyboard and mouse only, no gamepad or touch)

| Input | Context | Action |
|---|---|---|
| W / ArrowUp, S / ArrowDown | ground | forward / back (camera-relative) |
| | route | advance / retreat along `railDir` (trunk: up / down) |
| A, D | ground | strafe (no arrow-key strafe) |
| | trunk | `chooseCanopyFork(−1 / +1)` (cycles on repeat) |
| | branch | `sideStepToSibling`, else `chooseRouteJunction` |
| | other route | `chooseRouteJunction` |
| Shift (L or R) | held | sprint |
| Space | ground or route | leap; in a duct, drop from the hatch |
| E (press) | any | `handleInteraction()` (mall, hospital, sewer, garages) → `takeSelectedFork()` → `attachRoute()` |
| E (hold) | hospital vent | chew grille (8871; hospital scope) |
| Q | route | drop |
| Left mouse | canvas, pointer locked | pounce. If not locked, request pointer lock |
| Right mouse (hold) / F (toggle) | | first-person stalk |
| Mouse move | pointer locked | yaw / pitch (§15) |
| C | | recentre camera behind the squirrel |
| P | | pause toggle |
| H, L, M, Tab, K | | help, diagnostics, HUD all, HUD preset, HUD editor (HUD scope) |
| G / Escape | | graphics panel open / close (13410) |
| 1 / 2 / 3 | | fashion slot cycle (sewer stand) |
| Esc | | release pointer lock (browser), which also ends focus |

- Keys are ignored while the pause shield or graphics panel is open, or a form element has focus (except G).
- `preventDefault` is applied to Space, Tab and the arrows.
- `window.blur` clears keys and focus.
- Movement keys are polled from `keys` each substep. A/D, E, Q, Space and F act on non-repeat keydown.

---

## 17. Interactions with other subsystems

- **Terrain / world gen:** `terrainHeight`, `outdoorSurfaceAt`, `pavementDistance` (pole placement guard), `houses[]`, `oldDistrictHomes[]`, `commercialBounds[]`, `trees[]`, `fenceCollisions[]`.
- **Bellwether Quay and Galleria:** `riverSurfaceAt`, `riverRoofAt`, `riverBlocked`, `recoverRiverFall`, `mallSurfaceAt`, `mallRoofAt`, `mallBlocked`, `resolveMallLanding`, `constrainMallCeiling`, `constrainMallCamera`.
- **Traffic:** `cars[]` (29) and `tallVehicles[]` (9) as obstacles and standable roofs. Fatal run-over is checked in `finishTrafficFrame` after movement (other scope). Being on a rail or a roof keeps the squirrel out of vehicle reach.
- **Interiors, hospital, sewer, duct:** each sets `rail = null` on entry. They replace ground resolution (`adjustHospitalMovement`, `constrainSewer`, duct path).
- **Bite / combat:** `attemptPounce`, `updatePounceCollision` (6555) and `attackHeading` share the launch code. NPC dialogue uses `squirrelActuallyInTree`. Cats and police can knock the squirrel off a route.
- **Peppers / chilis:** placed on routes at startup. `boostRemaining` scales speeds ×1.6 and the leap to 18.5.
- **Wildlife (v5.4):** nests at t = 0.66 on 24 boughs. The 7 AI "normal squirrels" (5060) **do not use routes**; they sit at ground hides.
- **HUD:** `#branchGuide`, flash messages, `#aimState`, focus header and diagnostics (route count, indexed count, fork count).

---

## 18. Dead code, vestigial fields and quirks (decide whether to keep)

1. `route.speed` (0.82 on 32 makeTree trunks) and `route.center` are never read.
2. `player.transferCooldown` (0.4 / 0.55) and `canopyHintTime` (5) are written but never gate anything.
3. `collisionHouses()` and `preventVehicleOverlap()` are never called.
4. Absolute-Y thresholds in `outdoorBlocked` (trees and fences only below y 3.1; main houses at `cfg.h − 0.35`).
5. The trampoline ring is a closed loop stored as an open curve, so it dead-ends at its seam.
6. Downspout and gutter visual normals are fixed to +Z, which puts the mesh on an arbitrary side of the pipe on rotated Bellwether buildings (cosmetic; never inside the wall).
7. Bellwether "gutter to ridge" is kind **roof**, while the house "gutter to roof" is kind **bridge** (different speed, lift and auto-switch rules).
8. `addHouseGutters` middle point uses `(gy + top)·0.53` (cosmetic).
9. A bough start shared by 3+ siblings causes a "Junction ahead" stall when walking back to t = 0; the player must use E, A/D or Q.
10. A pole top where 2 wires score within 0.65 stalls until the camera is turned.
11. Same-named trees (estate oaks, QUAY WILLOWs) rely on the 3.0 distance test for forks.
12. From the ground or air, `enterRoute` snaps the physics position up to 3.4 u (only the mesh is smoothed).

---

## 19. Brief deltas (brief = `Roblox_Rebuild_Brief.txt`; addendum = `spec/BRIEF_ADDENDUM.md`, which wins)

- **§7 Movement: "port the v5.4 route registry: curves, sampled points, kind (branch, pole, wire, lookout, roof), speed, surface radius, and the per-route visualOffset … rail-based … free running on the ground and leaps between rails."**
  - The HTML has **8** kinds, not 5: trunk, branch, bridge, lookout, roof, wire, fence, trampoline. "pole" is a trunk distinguished by name.
  - Recommendation: keep all 8 kinds and add an explicit `surface` attribute (`tree | pole | pipe | ladder`) and a `surfaceNormal` override instead of name regexes.
  - "speed" exists in the registry but v5.4 ignores it. Speeds are kind-based (§10). Applying `route.speed` would slow the 32 makeTree trunks to 0.82×; this is a design decision.
  - `visualOffset` is set only on the 72 apple boughs (0.3). Every other route uses the kind default (0.5 branch/bridge, 0.61 lookout, 0.22 wire, 0 for roof/fence/trampoline, radial for trunks). Port the defaults and the per-route override.
- **§7 Animation (7 clips: Run, Climb, Wire traversal, Leap, Pounce, Bite dance, Sneak).** Suggested mapping (inferred):

  | Movement state | Clip |
  |---|---|
  | ground run | Run |
  | trunk | Climb |
  | wire | Wire traversal |
  | roof / fence / branch / bridge / lookout | Run (cadence ×0.7 of ground) |
  | Space / Q airborne | Leap |
  | pounce | Pounce |
  | focus | Sneak |

  Drive playback rate from `cadence` (§14). Branch-top walking has no dedicated clip; designer decision.
- **§4 Actor model.** Every squirrel, AI or player, uses the same actor. In v5.4 the AI squirrels never use routes, so the port needs an **AI route brain** built on the same pure modules (`RouteMotion`, `RouteJunction`, forks). That requires a precomputed route graph (endpoint links, forks, ≤1.7 transfer pairs; §3).
- **§5 Population.** 10–14 squirrel actors plus 1 spicy rodent are on routes at once (v5.4 has one route user). Server cost scales with this.
- **§3 Hollow trees (new):** 11 hollow trees, 2 premium ones with an interior pathway up the trunk and chambers, 9 with a knothole chamber. This needs a new route kind (for example `hollow`: interior trunk rail plus chamber nodes) and a knothole entry action (E). The existing trunk and fork system is the natural attachment point (inferred). Not present in v5.4.
- **§9 Hospital roof access ("a squirrel route").** v5.4 has no climbing route to the hospital; its roof is only a landable surface at `HOSP_BASE + 13.34`. Add a downspout-plus-gutter style generator (pattern of 4306/4313 or 14808/14809).
- **§3 Neighbourhood expansion (≥8 house models, restaurants, shops, school, church, marina, pier).** Each lot type must emit its own ridge, downspout, gutter and fence routes from lot data ("adding a lot must be a data entry"). The ad-hoc per-building `addRoute` calls become lot-type route templates. New fences and hedges need collision entries.
- **§3 Backdrop / drone at altitude.** Not movement-related. The giant trees (y up to 58) remain the highest squirrel vantage points.
- **§8 Fatal traffic as a server-side relative swept test.** The squirrel's authoritative position (including `rail`, `railT`) must be on the server every tick so the run-over test can use it. The routes over streets (wires at y ≈ 17–25) are the designed safe paths.
- **§12 Winter (bare trees).** v5.4 has no seasons. Whether bough routes stay climbable in winter is an open design question (they should, inferred).
- **§2 StreamingEnabled.** Route data must not depend on streamed parts (see porting notes).
- **Addendum A1 (drivable police cars for the top two officers, radar and sightings).**
  - Player-driven cars must join the same squirrel obstacle and standable-roof sets: the `outdoorBlocked` car OBB and `getGroundAt` car-roof rule.
  - v5.4 does not carry a squirrel on a moving car roof and does not push the squirrel when a car moves into it. Decide both.
  - Sighting markers for the rodent should report rail state; for example, on a wire over a street means not catchable by foot.
- **Addendum A2 (rank from kicks).** Kick reach versus route height matters. In v5.4 the squirrel's own pounce connects with humans only when −0.35 < dy < 2.7 (pounce collision 6561). The human **kick** (`handleKickWindup`, 8155–8161) reaches only 2.65 u horizontally and < 1.6 u above the kicker; officer batons reach < 2.4 u (patrol, 8046) or < 2.3 u (precinct, 11140) above; cats strike within 2.75 u horizontally and < 2.4 u above. Routes are the escape from kicks; keep that.
- **Addendum A3 (70/30 avatar blend).** Visual offsets, the 0.32 collision radius and camera distances are tuned to the stock squirrel. Blending must not change the rig scale or hitbox ("drop anything that breaks silhouette or hitboxes"), and accessories must not affect route attachment offsets.
- **Addendum A2 free roam.** No change to movement.

---

## 20. Porting notes (Roblox / Luau / Rojo)

- **Bake the registry, then generate new content.** v5.4 routes depend on seeded RNG consumption order (`rng(20261008)` global `R`, per-tree `rng(seed)`, `rng(540811)`) and on creation order (§3).
  - To reproduce the HTML exactly, bake each route's `{name, kind, controlPoints, surfaceRadius, visualOffset, generator}` from a headless run, using the same instrumentation as §0, into `ReplicatedStorage/Shared/Routes/Baked.json`.
  - Keep generator functions only for new lots.
  - Store `generator` and `lotId` on each route so lots can be rebuilt.
- **Curve math.** Implement centripetal Catmull-Rom (alpha 0.5, open curve; as in Three.js r160, which is the version embedded in the HTML, the first and last segments extrapolate phantom end points `2·p0 − p1` and `2·pn − pn−1`, and near-zero knot intervals are guarded) plus an arc-length table.
  - Three.js uses 200 `arcLengthDivisions` for `getPointAt` and `getSpacedPoints`.
  - Precompute `sampled` at `max(20, ceil(3L))` steps on both server and client from the shared control points; about 1,332 curves takes milliseconds.
  - Write unit tests that compare against dumped sample points (tolerance 0.01 u).
- **Spatial index.** A hash of 8 u (20 st) cells holding ~81.6k entries; Luau tables are fine. Precompute the static route graph offline (§3) for AI and validation.
  - Replace `groundTrunkCandidate`'s linear scan with a trunk-foot grid; it runs every grounded frame with W held, and per AI.
- **Authority.**
  - Run the player squirrel's movement on the client: rails need 60 Hz input-coupled motion.
  - The client sends compact state (`routeId`, `t`, `dir`, or the ground position and velocity) with time stamps.
  - The server validates: speed caps per kind ×1.6 boost, legal transfers (a ≤3.15 gap for route to route, a ≤3.4 grab radius, a fork or junction exists), gravity-consistent arcs, and no wall crossing (re-run `outdoorBlocked`-equivalent tests).
  - AI squirrels run the same modules on the server.
  - The server owns the fatal-traffic test (brief §8).
- **Character controller.** Do not rely on Humanoid physics; rail-locking, gravity 30 u/s² (75 st/s²), split ground and air acceleration, and the analytic collisions do not map to Humanoid.
  - Recommended: a custom kinematic controller that moves a client-owned root part (for example `AlignPosition` / `AlignOrientation` with high responsiveness, or CFrame updates in `PreSimulation`) with physics collisions disabled for the squirrel. All blocking comes from data colliders or shapecasts. **(Verify the replication approach with a prototype.)**
- **Collision source.**
  - Option A: port the analytic colliders (house and commercial AABBs, tree circles, fence segments, vehicle OBBs, roof-height functions) as data. This gives fidelity and deterministic server validation.
  - Option B: use `Blockcast` / `Spherecast` against a collision group of real parts. That is easier for new lots but diverges.
  - Recommendation: a hybrid. Use data roof and ground functions for landing (continuous crossing test, §8.5) and shapecasts for walls of new lots. Fix the absolute-Y quirk either way.
- **Timestep.** Fixed substeps of at most 1/60 s with a frame dt cap of 0.08. Rail advance per step is capped at 0.05 s. Use `RunService.PreSimulation` / `Heartbeat` with an accumulator. Camera on `RenderStepped` (`BindToRenderStep`, Camera priority).
- **Camera.** `CameraType = Scriptable` with the per-mode rigs in §15, exponential damping, hard cuts and the FOV table.
  - Add general camera occlusion (a spherecast from target to eye), which v5.4 lacks outside the mall, hospital and houses; designer approval needed.
  - Pointer lock maps to `UserInputService.MouseBehavior = LockCenter`; use `ContextActionService` for bindings.
- **StreamingEnabled.**
  - Route data and the spatial index are plain data in ReplicatedStorage and never depend on streamed instances.
  - Tree and pole visuals should stream as atomic models (`ModelStreamingMode = Atomic`) so a bough is not missing while the squirrel stands on it.
  - Call `Player:RequestStreamAroundAsync` ahead of leaps or long wires, and at spawn.
  - Server-side AI does not need visuals.
- **Performance at 50 players.**
  - Routes are static, so the visual-offset maths runs client-side for visible squirrels only.
  - Replicate route-riding actors as (`routeId`, `t`, `dir`) rather than CFrames; clients reconstruct positions from shared curves, which saves bandwidth.
  - The fork lists and junction candidates are tiny.
  - The most expensive per-frame path is `nearestRoute(2.3)` for the "E to grab" prompt; do it client-only and throttled.
- **Scale.** Multiply all lengths by 2.5. Key values:

  | Quantity | HTML (u) | Roblox (st) |
  |---|---|---|
  | Spatial cell | 8 | 20 |
  | Auto-switch | 0.48 | 1.2 |
  | Explicit transfer | 1.7 | 4.25 |
  | E transfer search | 1.95 | 4.9 |
  | Max transfer gap | 3.15 | 7.9 |
  | Air/ground grab radius | 3.4 | 8.5 |
  | Walk-in reach | 2.0 | 5 |
  | Pole gate | 1.85 | 4.6 |
  | Leap | 16.5 / 12.8 u/s | 41.25 / 32 st/s |
  | Gravity | 30 u/s² | 75 st/s² |

  Speeds scale the same way.
- **Squirrel size.** The brief says "about 1.2 studs at the shoulder". The HTML squirrel at 2.5 st/u is about 1.7 st tall overall and about 0.6–0.8 st at the shoulder (inferred from the bounding box), so the Roblox squirrel is up to ~1.6–2× larger relative to the world. Visual offsets (0.5 branch lift, 0.22 wire lift, trunk offsets), the 0.32 collision radius, camera distances and the 2.7 vertical bite window should be re-tuned together.

---

## 21. Open questions

1. **Squirrel scale.** Re-tune offsets, collision and camera for the brief's 1.2-stud shoulder height, or scale the brief down to match the HTML proportions?
2. **`route.speed`.** Honour per-route speed multipliers (brief lists "speed"), or keep v5.4's kind-only speeds?
3. **Mid-route auto-junctions.** v5.4 auto-switches only at route ends (≤0.48). Living bridges and rooftop crossings end mid-wire or mid-ridge and need E or A/D. Keep this, or auto-merge?
4. **Junction stalls.** At pole tops and shared bough starts a near tie (<0.65 score gap) stops the squirrel. Keep the stall, or fall back to the camera-closest candidate?
5. **Absolute-Y collision quirk.** Fix to height-above-ground? This changes which hills block at trees and fences.
6. **Moving vehicles.** Should a squirrel standing on a car roof ride along, and should cars push it? Both are absent in v5.4. This becomes important with player-driven police cars (A1).
7. **Fall damage.** None in v5.4, even from y ≈ 58. Should the rodent's health meter (brief §8) take fall damage?
8. **Name-based rules.** Confirm replacing them with explicit route attributes (surface type, normal, exclude-from-auto-grab).
9. **`transferCooldown`.** It is vestigial. Should it actually rate-limit hops (anti-spam for networked play)?
10. **Isolated routes.** 40 routes (all 28 bunting lines, several roofs) are reachable only by leaping. Keep them as-is or connect them?
11. **New route content.** Generators are needed for hollow trees (interior climb plus chambers), hospital roof access, marina pier, school and church roofs, and the new house models. Who specifies their geometry?
12. **Winter.** Do bare trees keep all bough routes?
13. **Input on gamepad and touch.** v5.4 is keyboard and mouse only. A/D fork cycling, E transfer, Q drop and the right-mouse stalk need mappings.
14. **Third-person pitch direction.** In third person, mouse-up looks down; in first person it looks up. Keep this or unify?
15. **Camera occlusion.** Add general camera collision (absent in v5.4 outside the mall, hospital and houses)?
16. **Server tolerance.** How strict should server validation be at 50 players (latency allowance on rail speed, transfer gaps)?

---

## Added by verifier

Items in scope that the extraction missed or under-specified. All were read from `reference/v5_4_game.js` at the lines given.

1. **Mid-air pounce works as an air jump (AIR -> AIR).** `attemptPounce` (6482–6505), fired by left-click on the locked canvas (5585–5595), checks only `cooldown`, `playing`, pause, `alive`, house interior and duct. It has **no** `grounded` or `rail` check, unlike `leap()` (5928). In flight it **replaces** the velocity with `pounceVelocity()`: vy = 3.45 + 2.1·sin p, which is 2.37 at p = −0.54 and 5.09 at p = 0.9, and horizontal 11.3 / 12.4 focus / 13.5 when moveSpeed > 12, ×1.12 when boosted. It also re-runs `commitToAir` (hard cut, yaw reset) and opens a 0.78 s drag-free attack window. With the 0.7 s cooldown, a pounce can follow a Space leap (airtime 0.853 s), and repeated pounces chain. Each 0.7 s cycle drops about 3.8 u at p = 0.9 (5.9 u forward) and about 4.9 u at p = 0 (7.9–9.5 u forward) (computed). That is roughly a 1.5–2:1 glide from high perches. **Decision:** keep this as a feature or gate pounce on `grounded || rail`.
2. **Downspout surfaces are inconsistent.** For trunk routes whose name contains "downspout" or "gutter", the mesh is offset along world +Z (6776–6787). Leap/pounce heading (`attackHeading`, 5900–5906) and the trunk camera rig (7318–7325) still use `player.trunkNormal`, which is set from the approach direction in `enterRoute` (5856–5861), and mouse orbit rotates `trunkNormal` (5604–5607) without moving the mesh. On a downspout the camera can therefore sit on the far side of the pipe from the visible squirrel, and Space launches along `trunkNormal`, not away from the facade. **Port:** give each route one `surfaceNormal` that drives the mesh, the leap and the camera.
3. **House downspouts on the 20 outer homes double-count terrain.** `addHouseGutters` uses `top = terrainHeight + (h.cfg.h || 5.3) − 0.15` (4298–4299). For outer homes `cfg.h = base + height` is already absolute (2126), so on raised lots the pipe top and the "gutter to roof" joint sit about one terrain height above the eave. The 4 original houses use a relative `cfg.h` on y ≈ 0 ground and are correct. **Port:** compute the top from the eave height above local ground.
4. **Outer-home roofs are flat landing pads, and the walls stop at the eave.** Their `houses[]` entries use `roofY: () => peak` (2129), so the whole footprint lands at `peak + 0.29`. `outdoorBlocked` blocks only below `cfg.h − 0.35`, the eave (6350). Between the eave and the roof surface the squirrel is neither blocked nor on a roof, and `recoverTrappedInHouse` (6179–6226) snaps it up to the roof top whenever it is above terrain + 1.25 and below `top − 0.7`. The visual gabled roof (`localRoof`, 2088) does not match this flat collision.
5. **`getGroundAt(x, z)` is not a pure function of position.** Its river, car-roof, roof, porch, trampoline and treehouse gates all compare against the global `player.pos.y` (6232–6245), not a height for the queried point. The focus aim path (`updateAimPath`, 7271) samples predicted points through it, so the landing ring ignores roofs above the squirrel's current height and shows roofs below it at the wrong point (inferred). **Port:** `groundAt(x, z, referenceY)`.
6. **`routeWasMoving` ignores the arrow keys.** In `enterRoute` it tests only `KeyW || KeyS` (5851), while movement accepts ArrowUp and ArrowDown (6613). With arrows held, an automatic end-of-route switch is followed on the next substep by a fresh `directionFromView` pick (6664–6666). On a curved transfer that pick can reverse the direction the switch chose. **Port:** use the same `fw` input for both.
7. **`outdoorBlocked` early-outs and visibility.** Inside the footprint of the active or transiting Westside home, the function returns `false` immediately (6334–6335). That skips every later collider: the other houses, commercial bounds, trees, fences and vehicles. Cars skip invisible groups (6379), but `tallVehicles` are tested with no `group.visible` check (6394–6408). `vehicleHitboxAt` (6085) does check visibility, so a hidden tall vehicle still blocks but cannot be stood on.
8. **`hospitalTransition` freezes movement.** `updatePlayer` zeroes the velocity, sets `rail = null` and returns before anything else while a hospital transition runs (6574–6578). There is no visual update, no `cameraCommit` decay and no route guide.
9. **Rail-end overshoot is discarded.** When `railT` leaves [0,1], it is clamped before `switchRoute` (6687–6691). The new route starts at the candidate's sample `t` (switch gap ≤ 0.48, eased by `routeBridge` when > 0.11), and the leftover distance from that substep is lost. This is negligible at 60 Hz but matters for a server re-simulation.
10. **Order inside the air step:** gravity is applied to `vel.y` first, then `pos += vel·dt` (semi-implicit Euler, 6728–6729). Roof and mall landing resolve on the **unswept** XZ, before `resolveOutdoorMovement` (6731–6734). The analytic apex `12.8²/60 = 2.73` is the continuous value. At 60 Hz substeps the simulated apex is about 0.1 u lower (computed: Σ over steps).
11. **Wire/route speeds feed pounce strength.** On a rail, `moveSpeed` still tracks `base` × 0.6 on wood (6617–6626). A wire sprint (16.8) therefore gives the strong 13.5 pounce, while a branch sprint (10.08) gives 11.3.

## Verification log

Each line is one checked claim: OK / FIXED (old -> new) / UNVERIFIABLE. Line numbers refer to `reference/v5_4_game.js`.

1. addRoute at 294; throws on < 2 points, non-finite points, length < 0.04 or non-finite samples (295–313) — OK
2. Centripetal Catmull-Rom, closed=false, cloned points (302–306) — OK
3. `steps = max(20, ceil(3L))`, `getSpacedPoints(steps)` (310–311) — OK
4. Defaults: kind "branch", `speed || 1`, `center || null`, `surfaceRadius || 1.35`, visualOffset finite-or-null (319–324) — OK
5. `route.speed` and `route.center` never read (grep of `.speed` / `.center`) — OK
6. visualOffset set only on APPLE boughs, 0.3 (15206) — OK
7. `RouteMotion.advance` clamps dt to 0.05 and divides by `max(1, L)` (267–271) — OK
8. Spatial hash cell 8 on x/y/z, `t = i/(n−1)` (277–293) — OK
9. `routeIndexLive` at 4319, `verifyRouteRegistry` at 16034, `rebuildCanopyForks` at 16055 — OK
10. 60 addRoute call sites (61 grep hits including the definition) — OK
11. Kind totals 265/715/150/99/78/12/12/1 = 1,332 — OK (sum of the JSON per-generator counts; loop-determined counts recomputed from code: poles 80+14+3 = 97, utility wires 44+44+14 = 102, outer boughs Σ(5 + i%5) = 303, giants 3/21/6, estates 2/2/2/4/24/5/6/2, parapets 2, bunting 2×14 = 28, apples 12/72; RNG- or run-dependent counts such as makeTree boughs 295, bridges 15/10/25, outer homes 9/11 and Bellwether 30 are UNVERIFIABLE)
12. 81,613 index entries — OK (equals the sum of the JSON per-generator sample counts; spot-checked pole 97×51 = 4,947, OPEN SKY 6×21 = 126 and Chili's 151 against the steps formula)
13. 95 fork trunks and 770 forks — OK (computed: 32 makeTree + 44 outer + 12 apple + 4 estate + 3 giant trunks; forks = 715 boughs + 52 name-matched bridges (15 + 10 + 25 + 2) + 3 park perches)
14. Tree-travel kind list lines — FIXED (6617 and 6672 -> 6617 and 6671)
15. Ground speeds 8.0 / 16.8 / 1.65, duct 2.8/3.8, boost ×1.6, tree ×0.6 (6618–6621) — OK
16. moveSpeed smoothing rate 11 focus / 17 (6622–6626) — OK
17. Acceleration 23/4.2, drag 13/1.15, turn rate 25/19, focus face-camera rate 11 (6711–6727) — OK
18. `SQUIRREL_GRAVITY = 30` (6472) — OK
19. Rail speed 7.2 / 12.2 / 1.2 ×1.6 boost ×0.6 wood, table values 4.32/7.32/0.72/6.91/11.71 and 7.2/12.2/1.2/11.52/19.52 (6668–6671) — OK
20. Leap (sin h·16.5 or 18.5, 12.8, cos h·…) and commitToAir (cameraCommit 0.52, hard cut, focus off) (5907–5940) — OK
21. Leap apex 2.73, airtime 0.853 s, flat distances 8.97 / 8.8 / 14.3 — OK (recomputed with air drag 1.15 and air acceleration 4.2)
22. Q drop: vy 3.3, committedAirborne, cameraCommit 0.32 (5672–5680) — OK
23. pounceVelocity (pitch clamp −0.54..0.9, 12.4/13.5/11.3 ×1.12, vy 3.45 + 2.1 sin p) and timers 0.7/0.38/0.78 (6473–6496) — OK
24. groundTrunkCandidate exclusions, pole 1.85 gate, rise 3.1, rank weights 0.24/+0.2; walk-in reach 2.0; forwardIntoTrunk 0.12 and 0.43 (5742–5778, 6640) — OK
25. attachRoute: nearestRoute(1.95) with 1.7 transfer; off rail `groundTrunkCandidate(3.1) || nearestRoute(3.4)` — OK; line FIXED (5872 -> 5870)
26. enterRoute: 3.15 gap limit; routeBridge only when on a route and gap > 0.11; duration clamp(0.13 + 0.065·gap, 0.15, 0.31) (5826–5869) — OK
27. RouteJunction.inward 0.035/0.965, canTransfer 1.7/0.48, smoothstep ease (5782–5793) — OK
28. switchRoute: end window 0.07/0.93, score 2·continuity + 2.9·view − 1.6·gap, trunk filter unless old route is a bridge, tie 0.65, floor −0.75 (5941–5986) — OK
29. junctionCandidates 2.15 radius and 1.7 keep; chooseRouteJunction −0.08 filter and cycling; junctionOutward lenSq 0.24 and ±0.09 (6004–6049) — OK
30. drawJunctionPreview: 4 dots, radius 0.13 − 0.012j, #f7e4a3, no depth test, (j + 0.4)·0.018, 0.42 + 0.06 sin (5989–6077) — OK
31. rebuildCanopyForks: tname regex, 3.0 / 1.4 park perch, outward at t 0.19, `trunkClearance = max(…, r || 1.3)`, sorted by height (4324–4357) — OK
32. nearbyCanopyForks [h − 1.9, h + 10.5], else |Δh| < 5.5; chooseCanopyFork weights 0.48/0.10/3.2 and −0.1 filter (4386–4422) — OK
33. takeSelectedFork 2.15 / 2.75 forced, t 0.018, cooldown 0.55; W auto-take −0.42 / +0.022 (4444–4456, 6676–6686) — OK
34. sideStepToSibling: railT ≤ 0.21, |Δh| < 2.9, −0.12, t 0.03 (4423–4443) — OK
35. updateCanopyGuide: 2.2 prompt, 5 markers #e6faac 0.105 + 0.01k at t 0.055 + 0.05k, +0.63, clear when |Δh| > 12 (4457–4491) — OK
36. outdoorBlocked thresholds: r 0.32, interior 0.68 + 0.0256, houses +0.53 and cfg.h − 0.35, commercial roof − 0.35, trees 1.48 below y 3.1, fences r + 0.05, cars 1.175/2.225/1.94 with ±4.5 broad phase, tall vehicles −0.1 (6324–6410) — OK
37. resolveOutdoorMovement: 0.24 step, max 18, per-axis then diagonal, ×0.28 (6411–6448) — OK
38. collisionHouses and preventVehicleOverlap never called — OK
39. trees[] = 95 (32 + 44 + 3 + 4 + 12) — OK
40. commercialBounds = 8 (3 commercial + 2 guesthouses + 2 mansions + police) — OK
41. getGroundAt rows: car −0.32/+0.16, roof −0.47, porch (−58, 83) 6.5/6.0 >5.2 → 6, trampoline r < 5 >1.1 → 1.65, treehouse ±4.2/±4.0 → base + 13.46 (6227–6247) — OK; mall row FIXED ("always considered" -> base floor always, upper levels gated by y ≥ surface − 0.55)
42. "No step-height limit" — FIXED (terrain/pavement unlimited; per-source implicit step-ups 0.47 / 0.48 / 0.68 / 0.8 / 0.55 / 1.36)
43. roofSurfaceAt sources and margins (river 0.55/0.65, houses 0.24/0.2, old homes 1.7, commercial 0.15/+0.17, hospital 1.2/+13.34) (6111–6146) — OK; house roof profile FIXED (all gabled -> gabled for the 4 originals, flat `peak` for the 20 outer homes, 2129)
44. resolveRoofLanding: skip list, falling test, +0.08 / −0.5 / prevTop rule (6147–6178) — OK
45. Trampoline bounce: r 4.67, prev ≥ 1.72, new ≤ 1.92, y 1.90, vy 14.2 + 0.9n with n capped at 4 and reset beyond 9 u, +1.6 forward, cameraCommit 0.4 (10242, 10373–10392) — OK
46. recoverTrappedInHouse floor threshold — FIXED ("ground + 1.05" clarified as terrain + 0.2 + 1.05 = terrain + 1.25)
47. recoverRiverFall: waterY + 0.45, halfWidth + 5, bankY + 0.18, z clamp −225..425, 2 s flash cooldown (14116–14141) — OK
48. validatePlayerState lastSafe refresh — FIXED ("after 0.5 s of grounded play" -> clock accumulates always and the first grounded off-rail out-of-duct frame after 0.5 s refreshes)
49. World clamp: x −586..1146 (RIVER.endX 1150 − 4), z −560..436 (NORTH_LIMIT 440 − 4) (6765–6766) — OK
50. Substeps `ceil(dt·60)`, dt cap 0.08 (so at most 5), activeDt cap 0.2 (15944, 16007) — OK; section line FIXED (15908+ -> 15932–16031)
51. Camera rigs (trunk 3.25 / +0.58 / +0.18; route behind 3.5/3.7/3.2, perp 0.45, 2.35 or 2.6 + 0.55 sin; ground 5.5/4.2/3.35, rise 2.15/1.4, perp 0.62), damping 11/9.5/17/12/8.5, FOV 66/61/74/68/62, camera 72°/0.12/1500 (26, 7294–7433) — OK
52. Mouse: ±90 clamp, sensitivity 0.0025/0.00315, boost min(1.25, ·/35), pitch −0.6..1.07, trunk orbit −dx·0.004, routeFreeLook 1.7 (5596–5609) — OK
53. Aim path: 34 samples, t = 0.06 + 0.05i, line #c9ddb0 at 0.33, ring 0.24–0.30 #e4f1d4 (7236–7288) — OK
54. Visual placement: trunk taper formulas, r + 0.2 for built surfaces and poles, branch 0.5 / lookout 0.61 / wire 0.22, clearance push (tc + 0.31)(1 − t/0.2)², snap 2.5/1.6, lerp 17/23 (6772–6816) — OK
55. Input map (every `e.code ===` and `keys.has(` in the file: W/S/A/D, arrows up/down, Shift L/R, Space, E, Q, F, C, P, H, L, M, Tab, K, G, Escape, Digit1–3, mouse buttons 0/2) — OK
56. Knockbacks "police baton 12 u/s" — FIXED (-> patrol baton 14 (8057), pedestrian kick 11 (8161), precinct baton 12 (11141), hospital knockPlayer 10.8 (8834); cat 10.5 OK)
57. A2 reach "cats only within 2.4–2.8" — FIXED (-> cat 2.75 u horizontal and < 2.4 u above; kick < 2.65 u and < 1.6 u above; batons < 2.4/2.3 u above)
58. pole(): 17.05 height, route foot + 0.48 / + 8.5 / top, poleKey dedupe, throws when pavementDistance < 0.95 (1615–1636) — OK
59. Wire sags: min(0.84, 0.26 + 0.004·d); estate 0.3, park 0.36, westside 0.42, tree-to-line 1.1, house drop 1.0 (1648, 1677, 2915, 3430, 3439, 9909) — OK
60. "Pole tops link to 1–3 wires" — FIXED (-> 1–4; all 16 row/column crossing poles carry 4 wire ends at gap 0)
61. `cameraCommit` described as a camera timer — FIXED (-> its only reader is the focus gate, 6585)
62. squirrelActuallyInTree: branch/trunk/lookout above y 3.2, used only by chooseLine (4785–4799) — OK
63. Section line ranges — FIXED (§8 6706–6762 -> 6707–6763; landing 6739 -> 6741; §9.1 6628–6640 -> 6630–6642; §10 6646–6705 -> 6655–6706; §12 4321–4522 -> 4321–4491)
64. "E to grab" prompt "each frame" — FIXED (-> each updatePlayer substep, 6876)
65. Bellwether downspout "+Z bug" — FIXED (-> cosmetic: the mesh sits on an arbitrary side of the pipe; 0.34 offset vs 0.65 clearance, so never inside the wall)
66. Three.js r160 (HTML shell references three@0.160.1), 200 arcLengthDivisions, phantom end points `2p0 − p1` — OK
67. Brief §7 quote (Roblox_Rebuild_Brief.txt 207–209) and population 10–14 squirrels (156–158) — OK
68. Connectivity: 149 islands, largest 563 routes, 40 singletons — UNVERIFIABLE (headless-run derived; consistent with code: bunting, tennis nets, isolated roofs have no generated links)
69. Per-kind total lengths (4,086 / 11,238 / …) — UNVERIFIABLE (run-derived)
70. Cars 29 and tall vehicles 9 at startup — UNVERIFIABLE (runtime counts; the delivery van 3.0×5.9×3.65 at 1603 is OK)
71. Squirrel bounding box 0.447 × 0.683 × 0.951 — UNVERIFIABLE (`SQUIRREL_VISUAL_SCALE = 0.335` at 5155 OK)
72. APPLE 5 at y 6.6 (absolute-Y quirk example) — UNVERIFIABLE (the quirk logic is OK: trees and fences are gated on absolute `height < 3.1`, 6358)

JSON spot checks (`spec/data/routes_catalog.json`; it parses, has 60 entries matching the 60 call sites, and counts sum to 1,332):
- Checked against code, OK: 733, 794, 832, 837, 854 (ladder, 0.60 visual offset), 863 (t ≈ 0.952 end window), 907, 1237, 1329, 1354 (fence instances), 1453 (17-point ring), 1650, 1679, 1782 (treeSpec positions and heights), 1830, 1896 (< 49), 2240/2258 (Σ = 303), 2351 (< 39, lerp 0.6 + 1.8), 2428 (r·0.95 array), 2458 (0.576 pad gap), 2478 (0.86 length), 2674/2695/2748 (courtX ∓47, guestX ±67, roof 14.7), 2835/2859, 2922/2933/2971, 3385, 3419, 3432/3441, 3562, 3667 (wx 139, wz 342), 4313, 9532 (0.16 gap) / 9551 / 9556, 9903 (WEST_X − 14 = −303) / 9911, 10073, 13740/13745, 13762 (107 points), 13783, 13898/13903, 14086 (2×14), 14808/14809 (MALL constants), 15184/15206 (rng 540811).
- FIXED: 1627 connects_to "1-3 wire spans" -> "1-4" (16 crossing poles).
- FIXED: 1926 notes carried a misplaced giant-trunk surfaceRadius remark; it was moved to 2428.
- FIXED: 4306 notes now add the outer-home terrain double-count.
- FIXED: 13902 notes, "may render inside the wall" -> never inside the wall (cosmetic side-of-pipe issue).
- FIXED: 2136/2142 notes now add the flat `peak` landing roof and eave-height walls.
