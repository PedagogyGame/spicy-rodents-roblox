# Traffic and Vehicles: v5.4 porting spec

Scope: every vehicle and wheeled road user in `reference/v5_4_game.js` (v5.4), the lanes they use, how they yield and stop, the non-fatal squirrel-vs-vehicle collision, and the fatal run-over test. All line numbers refer to `reference/v5_4_game.js`. Lane data is in `spec/data/traffic_lanes.json`. Road surfaces are in `spec/data/roads.json`, which another extractor owns.

## 0. Conventions

- Units are HTML world units. The brief maps 1 unit to about 2.5 studs. Speeds are units/s, accelerations units/s² and times seconds. Multiply lengths, speeds and accelerations by 2.5 for studs. Times stay the same.
- Axes: +Y is up, +X is east, +Z is north. The commercial district is at +x, the estates are at -z and the park and cemetery are at +z.
- Yaw: `rotation.y`. A vehicle's forward vector is `(sin yaw, 0, cos yaw)`, so model fronts face local +Z: headlights are at local z=+2.58 (1523) and tail lights at -2.58. Headings are computed as `yaw = atan2(dx, dz)` throughout. Three.js and Roblox are both right-handed with Y up, so `CFrame.fromEulerAnglesYXZ(0, yaw, 0)` is the same rotation. The brief says models face +Z, so do not use `CFrame.lookAt`, which faces -Z.
- Lane path convention (same as `roads.json`): `{axis, coord, start, end}` means the lane runs along world axis `axis` at the fixed other coordinate `coord`. For example, `{axis:"x", coord:-5.6}` is the line z=-5.6.
- Vehicle Y is always `terrainHeight(x,z) + small offset`: +0.04 for sedans (7479) and heavy vehicles (15753), +0.07 for the ice cream van, +0.05 for the trolley, +0.1 for route-following emergency vehicles (10509). Vehicles never pitch or roll to the slope.
- "(inferred)" marks a conclusion drawn from reading the code that was not run. "(computed)" marks a number derived offline from code constants.

## 1. Inventory

The fleet is the set of objects the fatal test considers (`trafficFleet()`, 15761). It has 38 objects: 29 entries in `cars[]` and 9 in `tallVehicles[]`.

| # | Vehicle | Count | Created | Logical box W x L x H | Moves? | Mover function | Fatal? | Yields to |
|---|---|---|---|---|---|---|---|---|
| 1 | Driveway-parked sedan | 4 | 1554-1563 | 2.35 x 4.45 x 2.04 | no | none | no (stationary) | none |
| 2 | Residential moving sedan | 2 | 1564-1565 | same | yes | `updateCars` 7435 | yes | humans, vehicles |
| 3 | Commercial parked sedan | 4 | 1567-1575 | same | no | none | no | none |
| 4 | Commercial moving sedan | 2 | 1576-1586 | same | yes | `updateCars` | yes | humans, vehicles |
| 5 | Estate parked sedan | 2 | 2815 | same | no | none | no | none |
| 6 | Patrol car | 1 | 7976 | same | yes | `updateCop` 8026 | yes | **nothing** |
| 7 | Legacy ambulance | 1 | 8980 | same | yes | `updateAmbulance` 8990 | yes | humans in a radius of 5 (one leg only) |
| 8 | Responder ambulance | 3 | 9149-9164 | same | yes | `updateMedicalResponders` 10805 | yes | **nothing** |
| 9 | Police-station parked car | 2 | 10065-10072 | same | no | none | no | none |
| 10 | Incident police car | 2 | 10990-10998 | same | yes | `updatePoliceResponse` 11050 | yes | **nothing** |
| 11 | Living-event car | 6 | 11394-11400 | same | yes (slow glide) | `updateLivingEvents` 11494 | yes | **nothing** |
| 12 | Delivery van (static) | 1 | 1588-1603 | 3.0 x 5.9 x 3.65 | no | none | no | none |
| 13 | Ice cream van | 1 | 7547 | 3.35 x 6.55 x 3.58 | yes | `updateStreetVehicles` 7730 | yes | squirrel, humans, vehicles |
| 14 | Heritage trolley | 1 | 7637 | 3.5 x 11.0 x 4.12 | yes | `updateStreetVehicles` | yes | squirrel, humans, vehicles |
| 15 | Dump truck (moving) | 2 | 15901-15902 | 3.35 x 8.9 x 4.12 | yes | `updateHeavyTraffic` 15737 | yes | squirrel, humans, vehicles |
| 16 | RV (moving) | 2 | 15903-15904 | 3.2 x 8.7 x 4.3 | yes | `updateHeavyTraffic` | yes | squirrel, humans, vehicles |
| 17 | Dump truck + RV (parked behind the Galleria) | 2 | 15905-15906 | as above | no | none | no | none |
| 18 | Motorcycle | 2 | 9561-9620 | none (no hitbox) | yes | `updateMotorcycles` 9637 | **no (not in fleet)** | **nothing** |
| 19 | NPC cyclists (3) and skater (1) | 4 | 4514-4517, 4677-4726 | humanoid | yes | `updateHumans` | no | moving sedans, van, trolley |
| 20 | Unicycle mime + 5 child cyclists | 6 | 12199-12282 | humanoid | yes | `updateNoveltyCast` 12352 | no | nothing |

Every `cars[]` entry uses the same fixed logical box, W 2.35, L 4.45, H 2.04 (6081, 15764-15766), whatever extra meshes it carries (ambulance box, light bars). The visible sedan is smaller. `makeCar` scales the group by 0.79 (1506), so the body is about 2.17 x 4.03 and the cabin top is about 1.53 above the base (computed).

## 2. Vehicle catalogue (identity, geometry, colours)

### 2.1 Sedan, `makeCar(x, z, color, rot, moving)` (1502-1540)
- The group is scaled 0.79. Body box 2.75x0.72x5.1 at y 0.81. Cabin 2.5x0.8x2.95 at y 1.54, z -0.35. Windscreen, rear and side glass. Four tyres r 0.54 at (±1.3, ±1.7). Headlights #f1dfb5 at z +2.58, tail lights #922f22 at z -2.58.
- A visible driver is part of the mesh, not an actor: head ball r 0.35 at local (-0.55, 1.65, 0.08) with random skin, torso #3f4a55 and a steering wheel. The driver sits on local -X, which is the right-hand side when facing +Z (a right-hand-drive car).
- Palette `carColors` (1501): `#658b93 #a59a80 #c6c7bd #923f33 #59704e #b2b9c2 #ccad7b`.
- Record pushed to `cars[]` (1530-1538): `{group, moving, velocity: R(6.5, 9.5), speed: 0, dir: rot===PI ? -1 : 1, lane: x (unused), routeAxis: "z"}`. `R(a,b)` is a uniform random.

### 2.2 Placements of `makeCar`
| Instance | Position (x, z) | Yaw | Colour | Lines |
|---|---|---|---|---|
| Driveway cars for houses[0..3] at (-56,-53), (51,-59), (-53,51), (58,56) (1248-1251) | x = house.x ± 17, z = house.z + 8·towardRoad, pushed back 2 at a time (up to 8 retries) while `carHitsFence`. Nominal: (-73,-45), (68,-51), (-70,43), (75,48) | PI, 0, PI, 0 | carColors[0..3] | 1554-1563 |
| Residential mover NB | (-5.4, 115) | 0 | carColors[5] #b2b9c2 | 1564 |
| Residential mover SB | (5.4, -86) | PI | carColors[3] #923f33 | 1565 |
| Commercial parked | (462,-29), (493,-29), (586,-33), (558,142) | 0, PI, 0, PI | carColors 2, 4, 6, 1 | 1567-1575 |
| Commercial mover EB | (287, -5.6) | PI/2 | random from carColors | 1577 |
| Commercial mover WB | (620, 5.6) | -PI/2 | random | 1578 |
| Estate parked | (-112, -350), (112, -350) | 0 | #617768, #a6aeb0 | 2815 |
| Patrol car | (95, -5.6) | PI/2 | #e0e6de, light bar #274a79 + #cf312d | 7976-7980 |
| Legacy ambulance | hidden until spawned at (639, 283) | -PI/2 | #f0eee6 + hospitalWhite box 2.5x0.8x3.15, red side stripes #b42c28 / #be332f, roof bars #cf382f + hospitalBlue | 8980-8988 |
| Responder ambulance x3 | hidden at (HOSP_X=-356, 283) | 0 | #f4f0ea, same box; bars recoloured red 0xdc2929 / blue 0x276ac2 | 9150-9164, 12096-12108 |
| Police station parked x2 | (-525, -81), (-495, -81) on 9x15 concrete pads | 0 | #d5dcdb, bars #274c77 / #a32b32 | 10065-10072 |
| Incident police x2 | hidden; start (-525|-495, -81) | route | #e4e8e5, bars recoloured blue 0x426fd7 / red 0xe84539 | 10992-10998, 12109-12121 |
| Living-event cars x6 | see 5.11 | PI | #7c8e8b #977c65 #627789 | 11394-11400 |

`carHitsFence(x, z, halfWidth=1.3, halfLength=2.5)` (1543-1553) is used only at build time. It projects (x,z) onto each fence segment and rejects the spot if |cx-x| < halfWidth+0.35 and |cz-z| < halfLength+0.35. The build throws if no clear spot is found.

### 2.3 Delivery van (static), 1588-1603
At (604, 110), yaw 0. Body 3.0x3.45x5.9 #e9e4d7, accent #5a7781. Pushed to `tallVehicles` with `{width 3.0, length 5.9, height 3.65}`. The comment calls it "visible reference for the upper jump limit". It never moves, so it is never fatal.

### 2.4 Ice cream van "SCOOP MOBILE", `makeIceCreamVan()` (7547-7636)
- Chassis #435b61 3.35x0.4x6.55. Rear box cream #fff2dc 3.2x2.75x4.08. Mint #82c9bb cab and roof trim. Pink #e5a0af stripes. A serving hatch on local -X (the kerb side on both legs) hinges open to 0.4 rad when dwelling (7773). Side logo "SCOOP MOBILE" (#428e93 on #fff7df) and front sign "ICE CREAM" (#e4a4b4). A roof soft-serve cone and scoop reach y about 5.46 (scoop centre y 4.94, radius 0.63 squashed to 0.83, 7578-7581). The wheels are 4 x r 0.54 and spin by distance/0.54.
- Logical box `{width 3.35, length 6.55, height 3.58}`, pushed to both `streetVehicles` and `tallVehicles` (7629-7630).
- State: `{distance, speed, cruise 7.6, stops[], nextStop, dwell, deliveries, phase}` (7610-7628).

### 2.5 Heritage trolley "CITY TROLLEY", `makeHeritageTrolley()` (7637-7727)
- A two-ended streetcar. Yaw is fixed at PI/2 and the body never turns (7640, 7659). Steel #525960 underframe 3.5x0.34x11. Cream #f5e8cb body 3.5x2.9x10.65. Burgundy #a54b4a bands. Trim #d7bd6e. Pantograph to y 5.59. "CITY TROLLEY" signs at both ends. Five seated passenger silhouettes. Four sliding doors (one per side per half, `homeZ = ±0.4`) slide by `±0.48·phase`. Eight wheels r 0.4.
- Track (7692-7705): rails at z = 8.65 ± 1.27, x 263-675, colour #6b6d65. Ties every 3.2 from x=265 to 669. Three stop platforms at x = 310, 465, 616 (9.7x1.95 slab at z=20.2), each with a bench and a "TROLLEY STOP" sign.
- Logical box `{width 3.5, length 11.0, height 4.12}` (7706-7725).

### 2.6 Heavy vehicles, `buildHeavyVehicle(type, x, z, axis, direction, moving, color)` (15634-15720)
- Dump truck: W 3.35, L 8.9, H 4.12, six wheels r 0.62 at z -3.0, -1.4, 3.0. Cab at the front (+z). Tipper body with 32 gravel balls. Label "Dump truck".
- RV: W 3.2, L 8.7, H 4.3, four wheels r 0.62 at z ±2.8. Cream #e5e0cf body with paint stripe, windows, side door and ladder. Label "RV".
- Yaw: axis x → `direction·PI/2`. Axis z → 0 if direction > 0, else PI (15699).
- Entry `{group, width, length, height, label, type, axis, direction, moving, wheels, speed: moving ? 5 : 0, cruise: dump 6.7 / RV 7.5, min: axis x ? 280 : -250, max: axis x ? 660 : 250}`, pushed to `heavyTraffic` and `tallVehicles`.
- Instances (15901-15906):

| Type | x, z | Axis | Dir | Moving | Colour |
|---|---|---|---|---|---|
| dump | 383, -5.6 | x | +1 | yes | #c69b44 |
| dump | -185.4, -210 | z | +1 | yes | #ad6843 |
| rv | 579, 5.6 | x | -1 | yes | #688b83 |
| rv | 5.4, 180 | z | -1 | yes | #9b8264 |
| dump | 1084, 409 | z | -1 | no | #c4a24f |
| rv | 1123, 409 | z | -1 | no | #6d8e92 |

The two parked ones sit behind the Galleria (MALL back edge z=392, 14191). Their Y uses `max(terrainHeight, mallBaseAt)` at build time.

### 2.7 Motorcycles, `createMotorcycle(i)` (9562-9618)
- Two bikes. i=0: "Morgan Rider", paint #9f3632, rider shirt #5f554c. i=1: "Alex Rider", paint #324f68, shirt #3b5b6d. The rider is a real humanoid (`makeHuman`, role "motorcyclist", personality "wary") with `hospital = true`, so the pedestrian scheduler ignores it.
- Mesh: two torus wheels r 0.55 at z ±1.0, a 0.56x0.44x1.65 body and an emissive headlight. There is no logical hitbox, and motorcycles are not in `cars[]` or `tallVehicles[]`.
- State `{active:false, crashed:false, wait: i ? 83 : 19, direction: i ? -1 : 1, velocity: i ? 11.9 : 10.4, skid, crashPoint}`.

### 2.8 Bicycles and skateboards (road users, not vehicles)
- `makeHuman` (4677-4726) gives roles "cyclist" and "skater" a prop. The bicycle has spoked wheels r 0.6 at z ±1.05, a frame colour from #405979, #b65e53, #59826d, #a58b4d and pedals. Wheel spin is distance/rollingRadius (7185-7189). The skateboard is 0.62x0.14x2.1 #7f4e43.
- NPC cast (4514-4517): Miles, Zoe and Ari (cyclists, idx 20-22) and Parker (skater, idx 23).
- Novelty cast (12136-12282): Marcel the Mime on a unicycle (wheel torus r 1.63, seat at y 3.8, four juggling balls) and five child cyclists (Ellie, Theo, Jules, Avery, Riley). The children have body scale 0.76, bike scale 0.82 and coloured helmets.

## 3. Lanes and routes

Full data, including dynamic templates, is in `spec/data/traffic_lanes.json` (25 entries). Summary:

| Lane | Line | Users | Notes |
|---|---|---|---|
| Residential main N-S, NB | x=-5.4, z -260..260, +z | moving sedan | Wraps 260 → -260 |
| Residential main N-S, SB | x=5.4, -z | moving sedan, RV (wraps at ±250) | |
| Ice cream loop | closed Catmull-Rom on x=±5.7, z ±127 | van | Length 519.92 (computed) |
| Grid x=-180, NB | x=-185.4, +z, ±250 | dump truck | |
| Boulevard EB | z=-5.6, x 280..660, +x | sedan, dump, motorcycle #0 (z=-5.7) | |
| Boulevard WB | z=5.6, -x | sedan, RV, motorcycle #1 (z=5.7) | |
| Patrol beat | z=-5.6, x 55..645, ping-pong | patrol car | Uses the EB lane in both directions |
| Trolley | z=8.65, x 283..657, shuttle | trolley | Stations 310, 465, 616 |
| North arterial | z=283 from x=639 → -356, then x=-356 to z=295 | legacy ambulance | Road centreline |
| Responder trunk | (-356,295) → (-356,283) → (-289,283) → (-289,-179) → (-180,-179) → dynamic | 3 ambulances | Road centrelines |
| Incident police | station → (-300, -81) → (-300, p.z+10) → (p.x±9, p.z+10) | 2 police cars | Last leg is a free diagonal |
| Event glides | 14-unit straight glides | 6 event cars | |
| Novelty rider lanes | z=-8 (mime), z=17, -17, 18 (children), x=-294, -288 (children) | riders | Ping-pong |
| Sidewalk lanes | z=±12.1, x=±12.1, outer ring ±161.9..±192.1, commercial z=17.4 | NPC cyclists and skater | Pedestrian rules |

Handedness is inconsistent in the source, so the designer must choose (see Open questions). On the residential streets traffic keeps right: heading +z at x<0 and heading -z at x>0, and the ice cream van's hatch faces the kerb on its right. On the commercial boulevard traffic keeps left: heading +x at z<0, whose right is +z. Sedans, heavy vehicles and motorcycles all follow this. The sedan meshes are right-hand drive.

Intersections are not controlled. No vehicle stops at a junction, signal, stop sign or crosswalk. Vehicles cross each other's paths subject only to the yielding rules in section 6.

## 4. Road furniture (decorative only)

- Traffic signals, `trafficSignal(x,z)` (700-713), at (321,-29), (371,29), (372,-28) and (320,29) around the x=347 / z=0 intersection. Each has a pole 10 high with an arm of 2.2 toward x=347. The head is at y+8.6 and holds red #c53227, amber #e9a62d and green #478a48 balls. **No phase logic exists; the lamps never change.**
- Markings (642-657): amber dashed centre line on the boulevard (dashes 7 long every 15 from x=275 to 671, skipped within 28 of x=347). White dashes on the x=347 cross street (6 long every 14 from z=-210 to 215, skipped for |z|≤27). Zebra crossings: 10 stripes across the boulevard at x=325 and x=369 (z -11..11.5), and across the cross street at z=±22 (x 335..358.4).
- Stop signs (decorative, `addDetail`): (324,31) and (371,-34) (3261-3262), plus two yard copies from the decorative-types loop (3242-3249). Fire hydrants at (312,23) and (387,-22) (3252-3253). Parking bay lines at z=139 and z=-135, x 410..645 every 15 (910-915). None of these affect any vehicle.

## 5. Behaviour (per mover)

Frame time: `dt = min(clockDelta, 0.08)` (16007). `updateStreetVehicles` and `updateNoveltyCast` additionally clamp to 0.055 (7731, 12354), so those movers fall behind real time below about 18 fps.

### 5.1 `updateCars(dt)`: generic sedans with `moving === true` (7435-7481)
Only the 4 sedans spawned with `moving=true` (rows 2 and 4) run here. Each frame, for each such car (p = position, dir = ±1, axis = `routeAxis`):
1. **Human corridor.** For each humanoid with `visible && !hospital`: `along = (q - p)·axisDir·dir`, `lateral = |perpendicular offset|`. If `lateral < 3.3` and `-3.5 < along < 16`, then danger = true.
2. **Vehicle ahead** (if not already in danger): `trafficVehicleAhead(group, fx, fz, range = 9 + 0.65·speed, halfWidth = 1.2)` (section 5.6).
3. `desired = danger ? 0 : velocity`. Then `speed = lerp(speed, desired, 1 - exp(-dt·(danger ? 9 : 1.3)))`. This is exponential: time constant about 0.11 s when braking and about 0.77 s when accelerating.
4. `next = p + axisDir·dir·speed·dt`. **Hard stop**: if any humanoid with `visible` (no hospital filter) is within 3.1 (2D) of `next`, do not move and set speed = 0. Otherwise p = next.
5. Wrap: E-W sedans teleport x>660 → 280 and x<280 → 660. N-S sedans teleport z>260 → -260 and z<-260 → 260.
6. `p.y = terrainHeight + 0.04`. Yaw never changes.
- **Sedans never check the squirrel.** They are the main run-over hazard.

### 5.2 `StreetVehicleLogic` (7493-7536)
- `approach(v, goal, amount)` moves v toward goal by at most `amount`, without overshoot.
- `shortestSigned(a) = atan2(sin a, cos a)`.
- `seesHazard(x, z, dx, dz, range, halfWidth, exclude)` uses the body heading (dx, dz), normalised to f. For a candidate at (qx, qz) with radius r: `along = (q-p)·f`, `lateral = |px·fz - pz·fx|`. It is a hazard if `-0.55 < along < range + r` and `lateral < halfWidth + r`. Candidates, in order:
  1. Squirrel (r 0.56) if `player.alive && !inSewer && !inHospital && player.pos.y < 4.8`. **4.8 is an absolute world height, not relative to the ground.** Lane terrain reaches 4.65-4.83 on the boulevard, 5.4-5.9 on x=±5.4 and 7.15 on x=-185.4 (computed from `baseTerrainHeight`), so in places vehicles cannot see a squirrel standing on the road.
  2. Humanoids (r 0.4) with `visible && !injured && !hospital && root.visible`.
  3. `cars[]` (r 1.15), visible and not `exclude`.
  4. `streetVehicles` (r = width/2).
  5. Then `trafficVehicleAhead(exclude, fx, fz, range, halfWidth)`.

### 5.3 Ice cream van FSM (7735-7773)
State `{distance ∈ [0, L), speed, dwell, nextStop, deliveries, phase}`. L = 519.92 (computed). Stops are sorted `[0.16·L, 0.59·L]` = 83.19 at (-5.7, -36.86) heading north and 306.75 at (6.06, 73.24) heading south (computed).
- **DWELL** (`dwell > 0`): `dwell -= step`, speed = 0.
- **DRIVE**:
  - `distToStop` = forward arc distance to `stops[nextStop]`, wrapping.
  - `danger = seesHazard(curvePoint, curveTangent, range 7.7, halfWidth 1.85, exclude self)`.
  - `desired = danger ? 0 : min(7.6, sqrt(2·5.0·distToStop))`, a braking profile at 5 u/s².
  - `speed = approach(speed, desired, (desired < speed ? 11 : 4.5)·step)`.
  - If `!danger && distToStop ≤ max(0.35, speed·step + 0.35)`: snap to the stop, set speed = 0 and `dwell = 5.8 + (deliveries mod 3)` (5.8, 6.8, 7.8, repeating), then `deliveries++`, `nextStop = (nextStop+1) mod 2` and play chime `fx(760 Hz, 0.08 s, sine, 0.019)`. Otherwise `distance = (distance + speed·step) mod L`.
- Pose: position = `curve.getPointAt(distance/L)` with y = terrain + 0.07. Yaw eases toward `atan2(tan.x, tan.z)` by `shortestSigned(Δ)·min(1, step·5.4)`. Hatch `phase` eases toward (dwell > 0 ? 1 : 0) at rate 3.7.
- Curve: `THREE.CatmullRomCurve3(points, closed=true, "centripetal")`. Arc length uses THREE's default 200 divisions. Reproduce the spline exactly or bake it to a dense polyline. Overshoot reaches |x| = 6.45 (computed).

### 5.4 Trolley FSM (7775-7809)
- `schedule = [310, 465, 616, 657, 616, 465, 310, 283]`. It starts at x=283 with nextStop 0.
- **DWELL**: count down, speed = 0.
- **DRIVE**:
  - `dest = schedule[nextStop]`, `delta = dest - x`, `dir = sign(delta) || 1`.
  - `danger = seesHazard((x, 8.65), (dir, 0), range 11.0, halfWidth 1.85)`.
  - `cap = min(10.7, sqrt(2·6.2·|delta|))` and `desired = danger ? 0 : cap`.
  - `speed = approach(speed, desired, (desired < speed ? 12 : 4.6)·step)`.
  - `x += min(|delta|, speed·step)·dir`.
  - If `!danger && |dest - x| < 0.25`: snap, set speed = 0 and dwell = 2.3 at the termini (283, 657) or 4.2 at stations, advance nextStop and play bell `fx(610 Hz, 0.13 s, sine, 0.023)`.
- Doors: `phase` eases toward (dwell > 0) at rate 4. Door z = homeZ + sign·phase·0.48. `lastBell` is declared but never used.

### 5.5 Heavy traffic, `updateHeavyTraffic(dt)` (15737-15756)
For moving entries: f = axis unit vector · direction.
- `danger = seesHazard(p, f, range 10, halfWidth = width/2) || trafficVehicleAhead(group, f, range 11, halfWidth = width/2)`.
- `speed = approach(speed, danger ? 0 : cruise, (danger ? 10 : 3.2)·dt)`. Position advances by `f·speed·dt` and wraps on its axis between `min` and `max`: 280-660 for x-axis lanes, -250..250 for z-axis lanes. y = terrain + 0.04. Wheels spin speed·dt/0.62.

### 5.6 `trafficVehicleAhead(root, fx, fz, range, halfWidth)` (15721-15736)
For each fleet item other than `root`, and only if `item.group.visible`:
```
d      = item.pos - root.pos            (2D)
along  = d.x*fx + d.z*fz
across = |d.x*fz - d.z*fx|
ψ      = item yaw
otherAlong = |sinψ·fx + cosψ·fz|·item.length/2 + |cosψ·fx − sinψ·fz|·item.width/2
blocked if along > 0 && along < range + otherAlong && across < halfWidth + item.width/2 + 0.2
```
The lateral term uses `item.width/2` whatever the other vehicle's orientation. It includes parked and invisible-filtered `cars[]` and all `tallVehicles`. `trafficFleet()` rebuilds the fleet array on every call, which is O(N²) per frame.

### 5.7 Patrol car (7975-8080, 11019-11049)
- **PATROL** (`!copState.out`): `x += 10.5·dt·patrolDir`. At x>645, set patrolDir = -1 and yaw = -PI/2. At x<55, set +1 and PI/2. y = terrain + 0.05. It never yields and never checks the squirrel. z is not touched.
- **DEPLOYED** (`copState.out`): the car is frozen. `dispatchCop(reason)` (8003) puts the officer at car + (0,0,3.4) with `alert = 23`. The deployment ends when `alert ≤ 0` or the officer is more than 155 from the squirrel.
- Teleports:
  - `startIncidentPolice(scene, 1, 1)` (single roll, 18%): the car moves to `pathPoint(p.x+12, p.z+7)` and alert ≥ 43.
  - `sendPosterPolice(p)`: the car moves to `(p.x+17, p.z+12)` and alert ≥ 52.
  - **Nothing restores z=-5.6**, so later patrols drive along x at the teleported z, through lots and buildings. This is an HTML bug; do not port it.
- `updateCop` runs from `updateNewSystems` only when `!player.inHospital` (9114), and it returns at once when `player.inSewer` (8027). The patrol car is therefore frozen in both places.

### 5.8 Legacy ambulance (8989-9038)
States: `waiting(wait=18)` → `arterial` → `turn` → `park(16 s)` → `waiting(145)` → and so on.
- `waiting`: when the timer expires, become visible at (639, 283) with yaw -PI/2.
- `arterial`: x -= 12.5·dt unless any visible non-hospital humanoid is within 2D radius 5. That check is an instant stop with no deceleration. At x ≤ -356, snap to it, set yaw 0 and go to `turn`.
- `turn`: z += 10.625·dt (12.5·0.85) until z ≥ HOSP_Z - 58 = 295.
- `park`: 16 s, then hide.
- Siren: while not parked, `fx(430 Hz, 0.21 s, sine)` every 1.45 s. The volume is 0.001 when a predator warning, kick wind-up or hospital telegraph is active, otherwise 0.018.

### 5.9 Responder ambulances (vehicle-relevant states only; 10471-10511, 10805-10979)
- `scheduleCrimeScene(victim)` (9198) calls `nearestRoadStage(pos)` (9166-9197). That function picks road segments by district: x<-257 → westside, x>267 → commercial, else the grid. It clamps the victim position onto each centreline and takes the nearest point.
- Then `queueMedicalResponse` (10471): the first idle ambulance takes the job. If none is idle the victim is queued and re-polled each frame (10980-10988). State is set to `waiting` with `wait = 9 + rand·10`, `route = makeRoadTrip(stage.stop)` and `responseStyle ∈ {0,1,2}`.
- `makeRoadTrip(dest)` (10447-10470), where tx and tz are the destination coordinates:
  ```
  p = [medicalHome(-356,·,295), (-356,283), (-289,283)]
  if tx < -255:            p += [(-289,tz), dest]
  else:
    p += [(-289,-179), (-180,-179)]
    if |tx+180| < 4:       p += [(-180,tz)]
    elif tz < -240:        p += [(-180,-174), (0,-174), (0,-305), dest]
    else:
      crossZ = tz < -239 ? -174 : tz > 220 ? 171 : (|tz-171| < |tz| ? 171 : 0)
      junctionX = tx > 267 ? 347 : tx
      p += [(-180,crossZ), (junctionX,crossZ), (junctionX,tz)]
    p += [dest]
  drop points closer than 0.35 to their predecessor
  ```
  Every point except the first is `pathPoint(x,z)` = terrain + 0.13. The first, `medicalHome`, is terrain + 0.1 (10443). The y values do not matter, because `advanceVehicleRoute` ignores dy and resets y.
- `advanceVehicleRoute(vehicle, ud, dt, speed, reverse)` (10494-10511): head straight for `route[leg+1]`, or `route[leg]` when reversing. Within 0.7 of it, advance the leg. Move by `min(dist, speed·dt)`. **Yaw snaps instantly to the leg heading.** y = terrain + 0.1. Returns true when the route is finished.
- `outbound`: speed 24, or 27 when responseStyle = 2. On arrival → `approach`, and the crew walk from the parked ambulance; that part belongs to the hospital/emergency spec. Then `assess`, `load` and `retrieve` follow.
- `return`: reverse the route at speed 25. Then `hospitalQueue`: snap to a bay slot at medicalHome + ((index-1)·6.5, 0, index·2.2). Handoff states hide the ambulance at the end (`sendoff` → idle, invisible).
- No yielding at any time. Light bars flash: `phase = floor(time·4.7) mod 2`, emissive 2.6 when on and 0.13 when off (12123-12128).

### 5.10 Incident police cars (10440-10441, 10990-11075)
- Per crime scene, `rollIncidentPolice`: roll < 0.05 → multi (2 cars, 3 officers). roll < 0.23 → single (patrol-car teleport, section 5.7). Otherwise nothing.
- Multi (`startIncidentPolice(scene, 3, 2)`): ignored if a non-departing incident exists. Car i starts at (-510 ∓ 15, -81). Route: start → (-300, -81) → (-300, p.z+10) → (p.x ∓ 9, p.z+10).
- `arrive`: `advanceVehicleRoute` at 23. When both cars arrive → `patrol` for 48 s, and the officers appear at the cars. Then `depart`: leg = length-2 and reverse at 23. When both are done, the cars hide. No yielding.

### 5.11 Living-event cars (11394-11499)
- Two events: barbecue at (-66,-84) with offset 0, and softball at (66,356) with offset 1200. The cycle is 2400 s. `phase = (time - offset) mod 2400`. The event is ongoing for phase < 600 and departing for 600 ≤ phase < 655. Outside that the cars are hidden.
- Car j (j = 0..2): x = center.x + (j-1)·8. Home z = center.z + (softball ? 40 : -36). Parked z = center.z + (softball ? 26 : -22). Yaw PI throughout.
- Position = `lerp(home, parked, t)` with t = phase/48 while ongoing (clamped to 1), or 1 - (phase-600)/50 while departing. That is 14 units in 48 s (0.29 u/s). These cars are in `cars[]`, so they are **fatal while gliding** even at this crawl.

### 5.12 Motorcycles (9621-9682)
- **IDLE**: `wait -= dt`. When `wait ≤ 0` and the rider is not injured → **RIDING**: visible, yaw ±PI/2, position (296, -5.7) for i=0 or (650, 5.7) for i=1.
- **RIDING**: x += direction·velocity·dt (10.4 or 11.9). No yielding at all. The rider is attached at +0.42 with a leaning pose. On leaving x ∈ [283, 657] → **IDLE** with `wait = 53 + 22i`.
- **Bite**: a pounce on an active rider always succeeds (`resolvePounce` 6516). Its contact radius is 2.0 (instead of 1.38) and dy is allowed up to 3.2 (6561). The `onSuccessfulBite` wrapper (9277) then calls `crashMotorcycle`.
- **CRASHED**: the rider drops to `crashPoint = (x + 1.4·dir, ·, z ± 5.8 toward the outer kerb)`, with a flash message and `fx(260 Hz, sawtooth)`. The bike skids: x += dir·velocity·dt·max(0, 1 - skid/1.8)·0.55, and roll eases to dir·0.96. After 8 s it hides, and `wait = 90 + 37i` → IDLE. The rider then follows the crime-scene and ambulance flow.
- Motorcycles are **not** in the fatal fleet and are not obstacles to other vehicles. Other vehicles only hard-stop near the rider humanoid (section 5.1, step 4).

### 5.13 Cyclists, skaters and novelty riders
- **NPC cyclists and skater** use the pedestrian scheduler (`spawnNpc` 4865-4901, `updateHumans` 7012). They ride sidewalk lanes (`sidewalkLanes` 4817-4830). 80% of the time the lane is picked from the first four. Otherwise it is picked from all 12 (4885), so the first four get about 87% overall. Zoe (idx 21) always uses the commercial sidewalk z=17.4 (4871-4874).
  - Speed while walking R(3.2, 5.2). Flee 8.25 for a cyclist or 7.1 for a skater on the footpath-flee path (7125); witnesses of a bite flee at 8.2 or 7.1 (9256). After the alert ends, a cyclist rides at 4.2 (7129).
  - Fleeing keeps to the footpath lane (7111).
  - **Pedestrian wait rule** (7154-7162): a step is cancelled if any `c.moving` sedan (the `updateCars` set only) is within 3.25 of the next point, or if `streetVehicleAt(next, extra 0.55)` hits the van or trolley footprint. They do not wait for heavy vehicles, the patrol car, ambulances or police cars.
  - When bitten, a cyclist's bike drops beside them (offset (1.15, 0.12, -0.6), roll 1.12) (9278-9283).
- **Novelty cast** (12352-12553) has its own state machine: `ride` → `escape` → `entering` → `inside` → reset after 55-103 s.
  - Riders ping-pong between their origin and destination at their ride speed. If blocked by a building segment they reverse.
  - On spotting the squirrel they escape to the police station at the escape speed and then call `dispatchCop`.
  - They have **no vehicle awareness at all**. They are humanoids with `hospital` false, so vehicles yield to them.
  - Several of them ride in the carriageway: the mime at z=-8 and Avery and Riley on the westside street.

## 6. Yielding matrix

The rows are the movers that react. Each column is an obstacle the mover reacts to.

| Mover | Squirrel | Humans (visible, not hospital) | Humans incl. hospital-flag | Sedans (`cars[]`) | Van/trolley | Heavy | Motorcycles |
|---|---|---|---|---|---|---|---|
| Moving sedans | no | corridor lat<3.3, along -3.5..16 | hard stop if within 3.1 of next position | via trafficVehicleAhead | via tVA | via tVA | only via the rider hard stop |
| Ice cream van | r .56, abs y<4.8 | r .4 | no | r 1.15 + tVA | r w/2 + tVA | tVA | no |
| Trolley | same | same | no | same | same | tVA | no |
| Heavy | same | same | no | same | same | tVA | no |
| Patrol car, responder ambulances, incident police, event cars | no | no | no | no | no | no | no |
| Legacy ambulance (arterial leg) | no | radius 5, instant stop | no | no | no | no | no |
| Motorcycles | no | no | no | no | no | no | no |
| NPC pedestrians, cyclists and skater | n/a | n/a | n/a | moving sedans within 3.25 | footprint + 0.55 | no | no |

### 6.1 Deadlock (inferred)
The trolley centreline (z=8.65) is only 3.05 from the westbound lane (z=5.6). An eastbound trolley meeting a westbound sedan head-on triggers both tests:
- The sedan sees the trolley: across 3.05 < 1.2 + 1.75 + 0.2.
- The trolley sees the sedan: across 3.05 < 1.85 + 1.175 + 0.2.

The same happens with the RV: 3.05 < 1.6 + 1.75 + 0.2. Both vehicles stop and nothing ever releases them. The ice cream van's U-turns at z=±127 can produce similar standoffs (inferred). Do not reproduce this.

## 7. Non-fatal squirrel vs vehicle contact

- **Blocking**, `outdoorBlocked(x, z, height)` (6377-6408), inside the swept per-axis ground motion (`resolveOutdoorMovement` 6411-6447, sub-steps of 0.24, at most 18).
  - Sedans: rotated-rectangle test with half extents 1.175+r and 2.225+r, r = 0.32, applied while `height < terrain(car) + 1.94`. Broad phase |dx| or |dz| > 4.5 skips the test.
  - Tall vehicles: half extents width/2 + r and length/2 + r, applied while `height < base.y + height - 0.1`. The tall-vehicle loop has no visibility check.
  - When the squirrel is blocked on an axis, its velocity on that axis is multiplied by 0.28.
  - This box is larger than the fatal box (+0.32 against +0.18), so at ground level the squirrel cannot walk into the fatal volume. Run-overs come from vehicle motion.
- **Standing on roofs**, `vehicleHitboxAt(x,z)` (6079-6097) used by `getGroundAt` (6233-6234).
  - It returns the highest box containing (x,z): `cars[]` as 2.35x4.45 with top base+2.04, or tall vehicles with top base+height. Only visible groups count.
  - If the squirrel is at or above top - 0.32, the ground becomes top + 0.16.
  - Vehicles do **not** carry the squirrel. A moving vehicle slides out from under it and it falls.
- `preventVehicleOverlap(previous)` (6098-6107) is **dead code**; it is never called.
- `streetVehicleAt(x, z, extra)` (7811-7822) is the same rotated-rectangle test over `streetVehicles` only. It is used by the pedestrian wait rule.
- Rotated-rectangle convention, used everywhere: `lx = cos(a)·dx - sin(a)·dz`, `lz = sin(a)·dx + cos(a)·dz`. Then inside if `|lx| < W/2` and `|lz| < L/2`. Local X is width and local Z is length.

## 8. Fatal traffic: exact HTML collision math

### 8.1 Frame ordering (`updateGameplay`, 15940-15969)
```
if (!alive || paused) return
beginTrafficFrame()                         // snapshot squirrel + every fleet vehicle
updatePowerAndHeat; updatePlayer ×ceil(dt/(1/60)) sub-steps; validatePlayerState; peppers
if (!inSewer && !inHospital):               // traffic is FROZEN while in sewer or hospital
    updateHumans, updateNoveltyCast, updateCars, updateHeavyTraffic,
    updateStreetVehicles, wildlife, cats, updateAmbulance
updateInfection, updateHospital
updateNewSystems -> updateCop (patrol car), updateCrimeScenes -> updateMedicalResponders,
                    updateMotorcycles, bystanders
updateWestside, updateLivingEvents (event cars), doors, interiors, posters
updatePoliceResponse (incident cars)
finishTrafficFrame(dt)                      // swept test; "never an optional visual effect"
```
Each mover's own update is wrapped in `updateOptional`. If one throws it is disabled, but `finishTrafficFrame` is always called.

### 8.2 Snapshot, `beginTrafficFrame()` (15772-15785)
- `enabled = playing && player.alive && !gamePaused && !player.inHospital && !player.inSewer && !player.inDuct`.
- Clear the frames and record `playerBefore = player.pos`. If enabled, record for every fleet vehicle (`trafficFleet()`: all `cars[]` with W 2.35, L 4.45, H 2.04 and label "vehicle", plus every `tallVehicles[]` entry not already present) the values `{position.clone(), yaw, visible}`.

### 8.3 Per-vehicle filter, `finishTrafficFrame(dt)` (15870-15897)
For each snapshot, in insertion order (cars first, then tall vehicles):
1. Skip if it was invisible at the start or is invisible now.
2. `travel` = horizontal distance from start to end position.
3. Skip if `travel < 1e-5`. **A stationary vehicle never kills**, even if the squirrel is inside its box.
4. Skip if `travel > max(12, dt·80 + 2)`. With dt ≤ 0.08 this is always 12. It filters wraps and teleports longer than 12. Shorter teleports are still swept (see "Added by verifier").
5. If `sweptVehicleHit(...)` is true, call `vehicleGameOver(vehicle)` and stop (first hit wins).

There is no filter on squirrel teleports, such as house or hospital transitions, within a frame (inferred risk).

### 8.4 `sweptVehicleHit(P0, P1, V0, V1, ψ0, ψ1, W, L, H)` (15808-15851)
Inputs: squirrel position (`player.pos`) at the frame start and end, vehicle origin at the frame start and end, vehicle yaw at the frame start and end, and the logical box.

The squirrel reference point is `player.pos`. On the ground this is the surface height + 0.18 (`getGroundAt` 6228). The vehicle origin is the footprint centre at the base: terrain + 0.04 for sedans and heavy vehicles.

Language-neutral pseudocode, exact to the source:
```
if any input is non-finite: return false
Δψ   = atan2(sin(ψ1−ψ0), cos(ψ1−ψ0))          // shortest signed turn, (−π, π]
N    = max(1, ceil(|Δψ| / 0.05))               // one sub-step per 0.05 rad of turn
R0   = P0 − V0 ; R1 = P1 − V1                  // RELATIVE positions, full 3D (y included)
ρ    = hypot(W, L) / 2                          // half-diagonal
for i in 0 .. N−1:
    t0 = i/N ; t1 = (i+1)/N
    A  = lerp(R0, R1, t0) ; B = lerp(R0, R1, t1)   // relative segment, world-aligned
    ψ  = ψ0 + Δψ·(t0+t1)/2                          // mid-sub-step yaw
    c = cos ψ ; s = sin ψ
    toLocal(p) = (c·p.x − s·p.z,  p.y,  s·p.x + c·p.z)   // world→vehicle local (inverse Y-rotation)
    pad = 0.18 + 0.5·ρ·|Δψ|/N                       // extra slack for rotation within sub-step
    box: x ∈ [−(W/2+pad), +(W/2+pad)]
         y ∈ [−0.3, H − 0.16]
         z ∈ [−(L/2+pad), +(L/2+pad)]
    if segmentBoxEntry(toLocal(A), toLocal(B), box) != null: return true
return false
```
`segmentBoxEntry(a, b, halfWidth, halfLength, minY, maxY)` (15786-15807) is a slab test over the parametric segment t ∈ [0,1]:
```
enter = 0 ; exit = 1
for axis k in (x: [−halfWidth, halfWidth]), (y: [minY, maxY]), (z: [−halfLength, halfLength]):
    d = b_k − a_k
    if |d| < 1e-10:
        if a_k < lo or a_k > hi: return null    // parallel and outside
        continue
    tA = (lo − a_k)/d ; tB = (hi − a_k)/d ; if tA > tB swap
    enter = max(enter, tA) ; exit = min(exit, tB)
    if enter > exit: return null
return enter                                     // a segment that STARTS inside returns 0 → hit
```
Properties to preserve:
- **Relative motion.** The vehicle is treated as fixed and the squirrel moves along `R0 → R1`. A squirrel dodging sideways while a car advances is tested against the combined path, so a fast car cannot tunnel through a slow squirrel within one frame.
- **Rotation.** Yaw is interpolated in sub-steps of at most 0.05 rad, and the box is inflated by half the swept arc of its corners per sub-step. A 90° snap (`advanceVehicleRoute` corners) gives 32 sub-steps. A 180° flip (patrol car end-turn) gives 63.
- **Vertical clearance.**
  - The box spans relative y from -0.3 to H - 0.16. The squirrel is safe if its reference point stays at or above H - 0.16 relative to the vehicle base for the whole frame, or below -0.3 (for example in the sewer, which also disables the test).
  - Squirrel height above ground needed to clear: sedan H 2.04 → reference y above about 1.88 relative, which is about 1.74 above the standing height (computed). Van 3.42, delivery van 3.49, trolley 3.96, dump truck 3.96, RV 4.14 (all relative to base).
- **Jumping over sedans works; tall vehicles cannot be jumped from the ground.**
  - The ground leap is vy 12.8 with gravity 30 (`jumpVelocity` 5915-5921, `SQUIRREL_GRAVITY` 6472), which gives an apex of 2.73 (5916).
  - Clearance above about 1.74 lasts from t ≈ 0.17 s to 0.68 s, a window of about 0.51 s (computed: 12.8t − 15t² = 1.74). The squirrel's top run speed is 8.0, or 16.8 sprinting, times 1.6 with boost (6618-6620).
  - Routes (branches, wires at about 16, roofs) are safe.
- There is no radius for the squirrel body beyond the 0.18 pad. There is no speed threshold: "No collision is inferred from speed" (15759). Any non-trivial vehicle displacement counts, including the 0.29 u/s event-car glide.
- Equivalent Roblox local transform (for porting, not code): `local = CFrame.fromEulerAnglesYXZ(0, ψ, 0):VectorToObjectSpace(rel)` gives `(c·x − s·z, y, s·x + c·z)`. Do the test in HTML units, or scale every constant (0.18, -0.3, 0.16, box sizes) by 2.5.

### 8.5 `vehicleGameOver(vehicle)` (15852-15869) and aftermath
- Sets `lastFatal = vehicle.label || "vehicle"`, `player.alive = false`, `playing = false` and `gamePaused = true`.
- Zeroes velocity and clears the rail, attack window and focus. Forces the squirrel visible, clears input and exits pointer lock.
- Shows `#dangerOverlay` with the title "RUN OVER" and the text `A {label lowercased} ran you over. The run is over. Power: {points} · Bites: {hits} · Coins: {squirrelCoins}. Restart to play again.`
- Labels in practice: every sedan-type vehicle, the delivery van, the ice cream van and the trolley say "vehicle". The `tallVehicles` entries for the van and trolley carry no label. Heavy vehicles say "dump truck" and "rv".
- "RESTART RUN" reloads the page (7869, shell 154). There is no animation, ragdoll or body left on the road. The vehicle does not react. Instead, the whole simulation freezes on that frame: `playing = false` and `gamePaused = true` stop `updateGameplay` (16015), while rendering continues.
- The UI says: help text "Being run over by a moving vehicle ends your run; jump clear or travel above the street." (shell 178), and the startup flash "Watch for moving vehicles" (16060).

### 8.6 Other actors
**Nobody else can be run over.** Humans are protected only by yielding and hard stops. Vehicles that do not yield (patrol car, ambulances, incident police, event cars, motorcycles) pass visually through people. Animals have no vehicle interaction of any kind: yard cats, dogs, rabbits, birds and the v4.1 deer and fox. Motorcycle riders crash only when bitten, never from traffic.

## 9. Tunable constants

| Constant | Value | Line |
|---|---|---|
| Sedan logical box W/L/H | 2.35 / 4.45 / 2.04 | 6081, 15764 |
| Sedan block half extents, height | 1.175+0.32, 2.225+0.32, terrain+1.94 | 6388-6390 |
| Sedan cruise (residential / commercial) | R(6.5,9.5) / R(6.5,8.6) | 1533, 1584 |
| Sedan accel / brake rate (exp) | 1.3 / 9 | 7461 |
| Sedan human corridor | lateral 3.3, along -3.5..16 | 7446 |
| Sedan vehicle look-ahead | 9 + 0.65·speed, halfWidth 1.2 | 7457-7458 |
| Sedan hard stop radius | 3.1 | 7467 |
| Sedan wrap (z / x) | ±260 / 280..660 | 7473-7477 |
| tVA lateral margin | +0.2 | 15733 |
| seesHazard rear tolerance | -0.55 | 7512 |
| Hazard radius: squirrel / human / sedan / street vehicle | 0.56 / 0.4 / 1.15 / w/2 | 7519, 7524, 7528, 7532 |
| Squirrel visibility height (absolute) | y < 4.8 | 7518 |
| Van cruise, accel, decel, brake profile | 7.6, 4.5, 11, 5.0 u/s² | 7620, 7747-7751 |
| Van hazard range / halfWidth | 7.7 / 1.85 | 7746 |
| Van stops / dwell | 0.16 and 0.59 of loop; 5.8 + (n mod 3) | 7609, 7757 |
| Van yaw ease, hatch ease | 5.4, 3.7 | 7769, 7772 |
| Trolley cruise, accel, decel, brake profile | 10.7, 4.6, 12, 6.2 | 7716, 7792-7794 |
| Trolley hazard range / halfWidth | 11.0 / 1.85 | 7788-7789 |
| Trolley dwell termini / station | 2.3 / 4.2 | 7800 |
| Trolley arrival snap | 0.25 | 7797 |
| Street-vehicle step clamp | 0.055 | 7731 |
| Heavy cruise dump / RV, initial speed | 6.7 / 7.5, 5 | 15712-15713 |
| Heavy accel / decel | 3.2 / 10 | 15747 |
| Heavy hazard range / tVA range | 10 / 11 | 15744-15745 |
| Patrol speed, bounds | 10.5, x 55..645 | 8029-8034 |
| Legacy ambulance speed, block radius, waits | 12.5 (turn ×0.85), 5, 18 / 16 / 145 | 8989, 9003-9025 |
| Siren interval | 1.45 | 9032 |
| Responder speed out / style 2 / return | 24 / 27 / 25 | 10820, 10902 |
| Responder dispatch wait | 9 + rand·10 | 10482 |
| Route leg arrival | 0.7 | 10502 |
| Incident police speed, patrol time | 23, 48 s | 11054, 11057 |
| Police roll single / multi | 0.18 / 0.05 | 10440-10441 |
| Event cycle / active / depart / glide in / glide out | 2400 / 600 / 55 / 48 / 50 s | 11408-11411, 11495 |
| Motorcycle speeds | 10.4 / 11.9 | 9612 |
| Motorcycle waits: initial / after run / after crash | 19, 83 / 53 + 22i / 90 + 37i | 9610, 9679, 9647 |
| Motorcycle skid decay, despawn | 1.8 s, 8 s | 9642-9644 |
| Rider pounce radius / dy | 2.0 / 3.2 | 6561 |
| Pedestrian wait radius (sedan) / street-vehicle pad | 3.25 / 0.55 | 7158-7160 |
| Cyclist speeds walk / flee / post-flee | R(3.2,5.2) / 8.25 / 4.2 | 4898, 7125, 7129 |
| Beacon flash rate | 4.7 Hz toggle | 12124 |
| Fatal pad | 0.18 + 0.5·ρ·|Δψ|/N | 15837 |
| Fatal y-range | -0.3 .. H - 0.16 | 15844-15845 |
| Fatal yaw sub-step | 0.05 rad | 15824 |
| Fatal stationary / teleport filters | 1e-5 / max(12, 80·dt + 2) | 15878 |
| Frame dt cap | 0.08 | 16007 |

## 10. Interactions with other subsystems

- **Pedestrians / NPC scheduler** (`updateHumans`, `spawnNpc`): supply the yield inputs and obey the pedestrian wait rule. Their lanes overlap with cyclists and the skater.
- **Player movement** (`updatePlayer`, `outdoorBlocked`, `getGroundAt`): vehicles block the squirrel and can be stood on. The fatal test needs the squirrel position before and after the frame.
- **Bite / combat** (`resolvePounce`, `onSuccessfulBite` wrapper 9272): bites on motorcycle riders always succeed and crash the bike; bitten cyclists drop their bike. Both feed **crime scenes** (`scheduleCrimeScene`), which dispatch **responder ambulances** (hospital/emergency spec) and roll **police** (patrol-car teleport or incident cars).
- **Police** (`updateCop`, `dispatchCop`, `sendPosterPolice`, novelty riders' station report): the patrol car hosts the officer.
- **Hospital**: the ambulance bay at medicalHome (-356, 295), `hospitalDoorHold` and handoff. The legacy ambulance is cosmetic.
- **Living events**: the event cars.
- **Audio**: van chime, trolley bell, ambulance siren, motorcycle crash.
- **Rendering**: emergency beacons.
- **Terrain** (`terrainHeight`) sets every vehicle's Y. `mallBaseAt` is used for parked heavy vehicles.
- **Pepper placement audit** (10417) uses `vehicleHitboxAt` to keep pickups out of vehicles.
- **HUD**: `#dangerOverlay`.
- **Scheduler**: some traffic is frozen while the squirrel is in the sewer or hospital.
  - Frozen: sedans, heavy vehicles, the van, the trolley and the legacy ambulance (15948-15957), and the patrol car (8027, 9114).
  - Still moving: responder ambulances, motorcycles, event cars and incident police. `updateNewSystems`, `updateLivingEvents` and `updatePoliceResponse` are outside that guard.
  - The fatal test is off in both places.

## 11. Known HTML defects and quirks (do not port as-is)
1. Inconsistent handedness: residential traffic keeps right, the boulevard keeps left (section 3).
2. Possible head-on deadlocks: trolley against westbound sedan or RV, and the van's U-turns (section 6.1, inferred).
3. Patrol car z-drift after any dispatch teleport (section 5.7). The patrol car also drives in the eastbound lane both ways and yields to nobody.
4. Absolute `player.pos.y < 4.8` squirrel visibility (section 5.2). Vehicles are blind to the squirrel on raised road sections.
5. Motorcycles are not in the fatal fleet, have no hitbox and yield to nothing.
6. Emergency vehicles, the patrol car and event cars drive through people.
7. `preventVehicleOverlap` is dead code. `car.lane` and `lastBell` are unused.
8. Traffic signals and stop signs are decorative. There is no junction logic.
9. The fatal-vehicle label reads "rv" or "vehicle".
10. A stationary vehicle never kills, and there is no player-teleport filter.
11. The street-vehicle and novelty step clamp at 0.055 slows those movers at low fps. Other movers use 0.08.

## 12. Brief deltas

- **Brief §8 (spicy rodent play)**: "Fatal traffic from v5.4 ports as a relative swept collision test on the server, not a Touched event. Being run over ends the spicy rodent's run." Keep the section 8.4 math, but run it server-side for every squirrel actor. In the HTML the only squirrel is the player.
- **Brief §6 (roles)**: when the spicy rodent dies (the brief names "run over"), that player restarts as a lowest-level human. This replaces the HTML game-over overlay and page reload. The next spicy rodent comes from the squirrel queue.
- **Brief §2 (toolchain)**: one `Traffic` module owns "lanes, vehicles, yielding, swept collision". Lanes become data (`traffic_lanes.json`), and the town is generated from data.
- **Brief §1**: "The HTML is the reference for layout, climbing routes, traffic lanes, …". Keep the lane geometry in section 3, but fix the handedness and deadlock defects.
- **Brief §3 (world)**: the gas station, marina, roughly double the restaurants, school, church and other new lots need road access, parking and service traffic. The mountain backdrop has "a distant road", which should be a visual-only traffic loop (inferred). Restaurant back-alley dumpsters suggest service vehicles (inferred).
- **Brief §4 (actor model)**: vehicles are not actors. Whether drivers are human actors or mesh decoration is open (section 14). The HTML drivers are part of the car mesh.
- **Brief §5 (population)**: up to 50 players plus about 35 human bodies plus 10-14 squirrels. The fatal test runs for every squirrel actor, AI or player.
- **Brief §9 (hospital)**: an ambulance bay is part of the real building. The responder-ambulance flow (section 5.9) feeds infected or bitten humans to the hospital.
- **Brief §10 (police)**: AI officers patrol. Addendum A1 makes the top two cops' cars drivable.
- **Brief §11 (wildlife)**: "Deer … can be startled by traffic and the drone." This is new: neither v4.1 nor v5.4 deer react to vehicles. A deer-startle radius and rule must be added.
- **Addendum A1**:
  - The two highest-ranked police players get a drivable patrol car each, with enter and exit, throttle, brake, steer and a siren/lights toggle. They can park anywhere.
  - Player-driven cars take part in the same server-side swept collision, so they can run over the spicy rodent. They should obey yielding "where it matters for AI cars around them". AI cars must therefore treat player cars as fleet members in `trafficVehicleAhead`.
  - AI patrol cars keep running for AI officers (owner to confirm).
  - A police-car radar shows nearby speeders and moving vehicles. This requires per-vehicle measured speed and per-lane speed limits, which the HTML does not have.
- **Addendum A2**: new traffic-driven side quests that the HTML lacks entirely:
  - **Fender benders**: AI cars must sometimes have minor collisions. The HTML vehicles never collide; they stop or overlap.
  - **Parking tickets**: AI cars parked illegally, at a hydrant, red curb or driveway, or overtime. HTML hydrants are at (312,23) and (387,-22). There are no curbs or parking legality data.
  - **Speeding tickets**: radar plus AI drivers who exceed the lane limit.
  - **Running a stop sign**: real stop-sign junctions, a stop-line FSM, and AI drivers who sometimes roll through. The HTML stop signs at (324,31) and (371,-34) are decorative.
  - All of this needs traffic-control data (signals with phases, stop lines, speed limits, parking spaces with legality flags) that the HTML lacks.
- **Addendum A3**: the avatar blend applies to the driver when a police player is driving. Out of traffic scope, but the in-car seat needs to show the blended character.

## 13. Porting notes (Roblox)

- **Authority.** The server owns all AI vehicle state: lane parameter, speed, dwell timers and FSM state. Use kinematic motion, not physics. The HTML vehicles are purely kinematic: no inertia beyond the speed-smoothing rules, no wheel physics and no slopes. Recommended:
  - Simulate at a fixed server tick (30 Hz is enough; the HTML cap is about 12.5 Hz at worst, dt 0.08).
  - Replicate compact poses (id, x, z, yaw, speed, state bits) in a batched unreliable remote at 10-20 Hz.
  - Render on clients with interpolation, about 100 ms behind.
  - Moving anchored `Model:PivotTo` on the server for about 40 vehicles at 30 Hz also works, but costs replication bandwidth and fights StreamingEnabled.
- **Fatal test on the server.**
  - Each tick, for each squirrel actor, take the squirrel's position at the previous and current server tick and each vehicle's pose at the previous and current tick, then run section 8.4 unchanged.
  - Player characters are client-owned, so the server's view lags. Options: (a) accept the lag and keep the 0.18 pad, which is 0.45 studs; (b) keep a 1 s ring buffer of vehicle poses and test the client-reported segment against poses rewound to the client's timestamp, clamped and validated (lag compensation); (c) let the client flag a near-miss and have the server confirm.
  - Never rely on `Touched`. It is unreliable for CFrame-moved anchored parts and is client-physics dependent.
  - Use the squirrel's "ground + 0.18" reference point, not the HumanoidRootPart centre, or re-derive the y-range against the new rig.
- **Broad phase.** For about 15 squirrels against about 45 vehicles at 30 Hz, about 20k segment tests per second is cheap. Reject first with a circle test: |relative midpoint| > ρ + pad + |ΔR|/2. Cache the fleet list once per tick. The HTML rebuilds it O(N²) inside `trafficVehicleAhead`.
- **Teleport filter.** Keep the `travel > 12` units (30 studs) skip for wraps. Also skip, or reset `P0`, when the squirrel is teleported (house, sewer, hospital, possession handoff, respawn). The HTML lacks this.
- **Stationary vehicles.** Keep the `travel < 1e-5` rule or the designer must decide (section 14). A parked player police car must not kill a squirrel that walks into it.
- **Player-driven cars (addendum A1).** These will likely be physics `VehicleSeat` cars with client network ownership. Before testing, the server samples their CFrame each tick. Validate it: speed cap, no teleport over 30 studs per tick. Use the true car dimensions in the logical box.
- **Yielding.**
  - Port `seesHazard` and `trafficVehicleAhead` as a per-lane leader/follower query instead of all-pairs scans: vehicles on a lane sorted by distance along it, plus a crossing check at junctions.
  - Make squirrel visibility relative: player.y - vehicle base.y < 4.76, not an absolute 4.8.
  - Include every human actor, player or AI, and every squirrel actor in the hazard set.
  - Exclude vehicles in opposing lanes from the same-lane test, to avoid the trolley deadlock.
- **Emergency vehicles.** If they keep the HTML "no yielding" rule they will drive through player humans. Recommend at least the hard-stop rule for player-controlled humans, or a siren-cleared corridor.
- **Terrain.** Vehicle Y comes from the shared WorldGen height function, not raycasts, so the server and clients agree. Remember that vehicles do not pitch on grades in the HTML; designers may want pitch in Roblox.
- **StreamingEnabled.** Client-rendered vehicles from replicated state avoid streaming gaps. If server models are used, set `ModelStreamingMode` to Atomic or Persistent for vehicles near players, because a streamed-out vehicle would be invisible yet lethal. Server logic must never depend on what a client has streamed.
- **Performance.** About 45 fleet vehicles (more with the brief's new lots), 2 motorcycles, 10 riders and up to 50 players. Keep vehicle meshes low-part and use the 0.79-scale sedan proportions. Wheel spin and doors are client-side cosmetics.
- **Scale.** Multiply all lengths, speeds and accelerations by 2.5: sedan cruise 16.25-23.75 studs/s, trolley 26.75, ambulance 60 studs/s. Times are unchanged.
- **Determinism.** The ice cream van spline should be pre-baked to a dense arc-length table (for example 520 samples) shared by the server and clients.

## 14. Open questions

1. **Handedness**: keep right on all streets (the residential convention) or keep left (the boulevard convention)? This affects the lane coordinates in `traffic_lanes.json` for the boulevard and the trolley side.
2. **Who dies to traffic?** The brief only says being run over "ends the spicy rodent's run".
   - Are regular squirrels (player or AI) killable by traffic, and with what penalty: restart as human, as for winter deaths, or lose nuts?
   - Are player humans, deer, foxes or AI humans ever run over? The HTML protects AI humans only by yielding.
3. **Credit**: if a player-driven police car (A1) runs over the spicy rodent, does the driver get the "human who kills the spicy rodent" promotion (brief §6)? Does an AI vehicle kill grant anyone anything?
4. **Stationary or slow vehicles**: should touching a stopped vehicle ever be fatal? The HTML says no. Should the 0.29 u/s event-car glide be fatal? The HTML says yes.
5. **Emergency vehicles**: keep "no yielding" (dramatic and dangerous) or yield to humans and squirrels?
6. **Drivers as actors**: are AI drivers human actors counted in the 35-human population (brief §4/§5), so they can be possessed, bitten through an open window or witness? Or are they mesh decoration as in the HTML?
7. **Traffic control (A2)**: which junctions get signals (with what phase timings), which get stop signs, the speed limit per lane, the AI violation rates (speeding, rolling stops) and fender-bender frequency. The HTML has none of these.
8. **Parking legality data (A2)**: which curbs are red, where hydrants sit along every street, and the time limits.
9. **Motorcycles**: add them to the fatal fleet and give them a hitbox? Should they yield?
10. **Novelty riders in the carriageway**: keep the mime and children riding on the road?
11. **Deer startle by traffic (brief §11)**: radius, which vehicles, and the flee behaviour.
12. **Patrol beat**: keep a single patrol car looping the E-W main street, or AI patrol routes across the whole grid? Should AI patrol cars respond by actually driving to incidents instead of teleporting?
13. **Squirrel riding vehicles**: should a squirrel standing on a moving roof be carried along? The HTML does not carry it.
14. **Vehicle mesh vs logical box**: use the larger HTML logical sedan box (2.04 high, 4.45 long) or the true mesh, which is about 1.53 high and 4.03 long? The squirrel currently stands about 0.5 above the visible sedan roof.
15. **Seasons (brief §12)**: should winter change traffic (lower speeds, longer braking, fewer cars)?

## Added by verifier

1. **Short teleports are swept as if driven.** `finishTrafficFrame` only skips moves longer than 12 (15878). Any snap between 1e-5 and 12 units in one frame is tested as a straight-line drive from the old pose to the new one, so a squirrel standing anywhere on that line dies. Cases in v5.4:
   - Patrol-car dispatch teleports: `startIncidentPolice(scene, 1, 1)` moves the car to `pathPoint(p.x+12, p.z+7)` (11022) and `sendPosterPolice` to `(p.x+17, p.z+12)` (11046). These are swept whenever the scene is within 12 of the patrol car.
   - Responder ambulance bay snaps (team index i = 0..2, 10707). `hospitalQueue` moves it from within 0.7 of `medicalHome` to `medicalHome + ((i-1)·6.5, 0, i·2.2)` (10907-10909), a jump of up to about 7.9 for i = 2. `beginHospitalHandoff` then snaps it to `medicalHome + ((i-1)·5.9, 0, 0)` (10784-10790). Both can happen in the same frame.
   - In the port, give every scripted reposition a "teleported" flag that resets the vehicle's previous pose, so it is never swept.
2. **Vehicle Y offsets not listed in section 0.**
   - Patrol car: terrain + 0.05 (7978, 8038).
   - Legacy ambulance: +0.06 at spawn (8996), then +0.09 every frame (9029).
   - Event cars: +0.07 (11498). Police-station parked cars: +0.08 (10069). Commercial and estate parked cars: +0.04 (1574, 2816).
   - Responder ambulances in the hospital bay use `emergencyY` (10787, 10909).
   - The four driveway sedans are never snapped and stay at y = 0 (1504, 1562). This is harmless, because `baseTerrainHeight` is exactly 0 within 104 of the origin (blend = 0, 407-416) (computed).
3. **Incident police cars spawn inside the parked station cars.** Their start points `(policeStation.x ± 15, policeStation.z + 26)` = (-525|-495, -81) (11033) are the exact positions of the two parked station cars (10065-10068). They overlap while leaving and returning, and no rule separates them. While hidden they sit at the build position (-519|-501, -81) (10993).
4. **Heavy vehicles run `trafficVehicleAhead` twice**: once inside `seesHazard` with range 10 (7534) and again explicitly with range 11 (15745). Their effective vehicle look-ahead is therefore 11 plus the other vehicle's projected half-length. The look-ahead for humans and the squirrel is 10.
5. **Patrol car against eastbound traffic (inferred).** On its westbound leg the patrol car (yaw -PI/2) is still at z = -5.6, the eastbound lane, so it meets the eastbound sedan and dump truck head-on. Both see it through `trafficVehicleAhead` and stop. The patrol car yields to nothing and drives through them. Once it is behind them, `along < 0`, and they resume.
6. **The van's hazard corridor uses the curve tangent, not the body yaw.** `seesHazard` gets `curve.getTangentAt(progress)` (7744-7746), while the body yaw eases toward the tangent at rate 5.4 (7768-7769). Through the U-turns the braking corridor and the visible heading differ slightly (inferred, minor).

## Verification log

Checked against `reference/v5_4_game.js`, plus `v4_1_game.js`, the brief and `v5_4_shell_head.html` where noted.

1. Fleet = 38 objects (29 `cars[]` + 9 `tallVehicles`), from every `makeCar` call (1562-1580, 2815, 7976, 8980, 9150, 10068, 10993, 11397) and every `tallVehicles.push` (1603, 7630, 7725, 15718): OK
2. `makeCar` scales the group by 0.79 (1506), so the body is 2.17 x 4.03 and the cabin top 1.53: OK
3. Sedan logical box 2.35 / 4.45 / 2.04 (6081, 15764-15766): OK
4. `cars[]` record fields: velocity R(6.5, 9.5), dir from rot === PI, lane x, routeAxis "z" (1530-1538): OK
5. Driveway cars at nominal (-73,-45), (68,-51), (-70,43), (75,48), yaw PI/0/PI/0 (1554-1563; houses 1248-1251): OK
6. Residential movers (-5.4, 115) yaw 0 #b2b9c2 and (5.4, -86) yaw PI #923f33 (1564-1565): OK
7. Commercial movers (287, -5.6) PI/2 and (620, 5.6) -PI/2, velocity R(6.5, 8.6) (1576-1586): OK
8. Estate parked cars (-112, -350) #617768 and (112, -350) #a6aeb0 (2815; createEstate calls 2819-2820): OK
9. Delivery van at (604, 110) with box 3.0 / 5.9 / 3.65 (1591, 1603): OK
10. `carHitsFence` defaults 1.3 / 2.5 and +0.35 margins (1543-1553): OK
11. Ice cream van box 3.35 / 6.55 / 3.58 and cruise 7.6 (7612-7620): OK
12. Soft-serve height: FIXED (about 5.6 -> about 5.46, 7578-7581)
13. Ice cream loop length 519.92; stops 83.19 at (-5.7, -36.86) heading north and 306.75 at (6.06, 73.24) heading south; overshoot |x| 6.45: OK (recomputed with THREE's centripetal Catmull-Rom and 200 arc-length divisions)
14. Van drive logic: hazard 7.7 / 1.85, desired min(7.6, sqrt(10·d)), approach rates 11 / 4.5, snap max(0.35, adv + 0.35), dwell 5.8 + (n mod 3), chime 760 Hz / 0.08 s / 0.019 (7746-7760): OK
15. Van y + 0.07, yaw ease 5.4, hatch ease 3.7, hatch angle 0.4 (7766-7773): OK
16. Trolley schedule [310, 465, 616, 657, 616, 465, 310, 283] and start at x = 283 (7713, 7723): OK
17. Trolley logic: hazard 11.0 / 1.85, cap min(10.7, sqrt(12.4·|Δ|)), approach rates 12 / 4.6, snap 0.25, dwell 2.3 / 4.2, bell 610 Hz / 0.13 s / 0.023 (7783-7802): OK
18. Rails at z = 8.65 ± 1.27, x 263-675; ties every 3.2; platforms at x 310 / 465 / 616, z 20.2 (7692-7705): OK
19. Heavy dimensions (dump 3.35 / 8.9 / 4.12, RV 3.2 / 8.7 / 4.3), cruise 6.7 / 7.5, initial speed 5, bounds 280-660 / -250..250 (15642-15715): OK
20. Heavy instance table (15901-15906): OK
21. Heavy yaw rule (15699) and labels "Dump truck" / "RV" (15636, 15706): OK
22. `updateHeavyTraffic`: seesHazard range 10 plus tVA range 11, halfWidth = width/2, approach rates 10 / 3.2, y + 0.04, wrap (15743-15753): OK
23. `trafficVehicleAhead` formula and +0.2 lateral margin (15721-15736): OK
24. `updateCars`: corridor lateral 3.3 and along -3.5..16; look-ahead 9 + 0.65·speed with halfWidth 1.2; lerp rates 9 / 1.3; hard stop 3.1 with no hospital filter; wraps (7435-7481): OK
25. `seesHazard`: rear tolerance -0.55, radii 0.56 / 0.4 / 1.15 / w/2, absolute y < 4.8 (7503-7535): OK
26. Lane terrain maxima: boulevard 4.65-4.83, x = ±5.4 5.38 / 5.86, x = -185.4 7.15: OK (recomputed from `baseTerrainHeight` 407-416)
27. Patrol car: spawn (95, -5.6) at PI/2, speed 10.5, bounds 55 / 645, yaw flips, y + 0.05 (7976-8038): OK
28. `updateCop` gating: FIXED (added the `player.inSewer` early return at 8027 to the "only when !inHospital" claim)
29. `dispatchCop`: officer at car + (0, 0, 3.4), alert 23; deployment ends at alert ≤ 0 or distance > 155 (8003-8011, 8075): OK
30. Patrol teleports: (p.x+12, p.z+7) with alert ≥ 43, and (p.x+17, p.z+12) with alert ≥ 52 (11022-11048): OK
31. Legacy ambulance: wait 18; spawn (639, 283) at -PI/2; speed 12.5; block radius 5; turn ×0.85 up to HOSP_Z - 58 = 295 (HOSP_Z 353 at 3803); park 16; wait 145; siren every 1.45 at 0.001 / 0.018 (8989-9037): OK
32. `makeRoadTrip` branch structure and constants (10447-10470): OK
33. `makeRoadTrip` point heights: FIXED ("all points pathPoint +0.13" -> the first point, medicalHome, is +0.1, 10443)
34. `advanceVehicleRoute`: arrival 0.7, yaw snap, y + 0.1 (10494-10511): OK
35. Responder speeds 24 / 27 / 25, dispatch wait 9 + rand·10, bay slot ((i-1)·6.5, 0, i·2.2) (10482, 10820, 10902, 10907): OK
36. Police rolls 0.05 multi / 0.18 single (10440-10441, 11011-11017): OK
37. Incident police: start (-510 ∓ 15, -81); route via (-300, -81), (-300, p.z+10), (p.x ∓ 9, p.z+10); speed 23; patrol 48 s; depart leg = length - 2 (11019-11074): OK
38. Living events: centres, offsets 0 / 1200, cycle 2400, active < 600, depart < 655, glides 48 / 50, home and parked offsets (11394-11411, 11494-11498): OK
39. Motorcycles: names, paints, waits 19 / 83, speeds 10.4 / 11.9, spawn (296, -5.7) / (650, 5.7), active range [283, 657], wait 53 + 22i, crash wait 90 + 37i, skid 1.8, despawn 8 s, crash offsets 1.4 / 5.8 (9562-9682): OK
40. Rider pounce: always succeeds, radius 2.0, dy 3.2 (6516, 6561): OK
41. Bitten cyclist's bike drop offset (1.15, 0.12, -0.6) and roll 1.12 (9278-9283): OK
42. Pedestrian wait rule: moving sedans within 3.25, `streetVehicleAt` + 0.55 (7154-7162): OK
43. Cyclist speeds R(3.2, 5.2) / flee 8.25 (others 7.1) / post-flee 4.2 (4898, 7125, 7129): OK
44. Sidewalk lane selection: FIXED ("first four picked 80%" -> 80% from the first four, otherwise from all 12; about 87% overall, 4885)
45. NPC cast: idx 20-22 cyclists, 23 skater (4514-4517): OK
46. Novelty riders: mime -94 → 80 on z = -8 at 5.9 / 18.4; kids at 4.6 + 0.35i / 12.8 + 0.45i with their endpoints; reset 55-103 s (12199-12250, 12469): OK
47. Traffic signals at (321,-29), (371,29), (372,-28), (320,29); pole 10, arm 2.2, head y + 8.6; no phase logic (700-720): OK
48. Markings: dashed lines, zebra crossings, parking bays (642-657, 910-915): OK
49. Stop signs (324,31) and (371,-34) plus decorative copies; hydrants (312,23) and (387,-22) (3252-3262, 3032-3037): OK
50. `vehicleHitboxAt`, and `getGroundAt` using top - 0.32 / top + 0.16 (6079-6097, 6233-6234): OK
51. `preventVehicleOverlap` is never called (grep): OK
52. `outdoorBlocked` vehicle tests: r 0.32; sedan 1.175 + r / 2.225 + r below terrain + 1.94; broad phase 4.5; no visibility check for tall vehicles; velocity ×0.28 (6324-6408, 6446-6447): OK
53. Frame order in `updateGameplay` (15940-15969): OK
54. `beginTrafficFrame` enabled condition (15772-15785): OK
55. `finishTrafficFrame` filters 1e-5 and max(12, 80·dt + 2); first hit wins (15870-15897): OK
56. `sweptVehicleHit` math: turn, steps, relative positions, ρ, pad, y-range, local rotation (15808-15851): OK
57. `segmentBoxEntry` slab test with the 1e-10 parallel guard (15786-15807): OK
58. Sub-steps: 32 for a 90° snap, 63 for a 180° flip: OK (computed)
59. Jump vy 12.8, gravity 30, apex 2.73 (5915-5921, 6472): OK
60. Sedan clearance window: FIXED (0.17-0.69 s, 0.52 s -> 0.17-0.68 s, 0.51 s)
61. Run speeds 8.0 / 16.8, ×1.6 with boost (6618-6620): OK
62. `vehicleGameOver`: state changes, message text and labels (15852-15869): OK
63. Aftermath: FIXED ("vehicle does not stop or react" -> the whole simulation freezes, because updateGameplay is gated at 16015)
64. Restart reloads the page (7869); help text (shell line 178); startup flash (16060): OK
65. Beacons: floor(time·4.7) mod 2, emissive 2.6 / 0.13, recolours (12096-12128): OK
66. Deadlock arithmetic: 3.05 < 3.15, 3.05 < 3.225 via tVA, 3.05 < 3.55 for the RV: OK (arithmetic verified; the behaviour itself is inferred)
67. "Traffic frozen in sewer or hospital": FIXED (only some movers freeze; responders, motorcycles, event cars and incident police keep moving)
68. "Travel filter removes teleports": FIXED (only teleports longer than 12; see Added by verifier 1)
69. Brief quotes: §8 fatal traffic (brief 257-258) and §6 restart as lowest-level human (180-181): OK
70. v4.1 deer and fox have no vehicle interaction (v4_1 12472-12700 has no car or vehicle references): OK
71. MALL back edge z = 392 (14191: z 338 + d/2 54): OK
72. JSON parses (node JSON.parse): OK
73. JSON `res_main_ns_northbound` (x -5.4, spawn z 115, wrap ±260): OK
74. JSON `res_main_ns_southbound` (RV halfWidth 1.6, wraps ±250 / ±260): OK
75. JSON `res_west_ns_x-180_northbound` note: FIXED ("blind over much of it" -> about 11% of the lane, computed)
76. JSON `icecream_loop` (points, length, stops): OK
77. JSON `blvd_eastbound` (spawns, motorcycle respawn after 53 s): OK
78. JSON `blvd_westbound` (motorcycle respawn after 75 s): OK
79. JSON `patrol_beat`: OK
80. JSON `trolley_track` (rails at 7.38 / 9.92): OK
81. JSON `north_arterial_legacy_ambulance`: OK
82. JSON `responder_ambulance_trunk`: OK
83. JSON `incident_police_route`: OK
84. JSON `event_barbecue_cars` / `event_softball_cars` (segments and speeds 0.2917 / 0.28): OK
85. JSON novelty mime and 5 kid lanes (12199-12250): OK
86. JSON `sidewalk_outer_set` note: FIXED (sidewalkLanes[4..9] and "all 10" -> [4..11] and all 12)
87. JSON `sidewalk_commercial_z17.4`: FIXED (Ray, idx 15, is on z = 17.4 because idx % 2 = 1 at 4872; only Dale, idx 18, uses z = -17.4)
