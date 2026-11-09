# Spicy Rodents on Roblox: Build Proposal (Roles-First Vertical Slice)

Status: proposal for discussion with the owner. Nothing here is built yet. Date: 2026-11-09.

Lens: optimise for the brief's hardest process rule, "every role below must be test-playable from the first runnable build" (`reference/Roblox_Rebuild_Brief.txt`, preamble and §14). The plan builds the thinnest complete loop for each of the eight roles on a shared spine, then deepens everything in waves inside the same single build pass.

Inputs read for this proposal:

- `reference/Roblox_Rebuild_Brief.txt` (the brief, authoritative)
- `spec/BRIEF_ADDENDUM.md` (Addendum A1 to A3, which wins over the brief)
- `spec/roblox_feasibility.md`
- the eight subsystem specs in `spec/` and the seven data files in `spec/data/`

All of them were present. Citations look like `[routes_movement §20]` or `[brief §6]`.

Note on the feasibility doc: it says `apis.roblox.com` is blocked from the container. The owner has since decided that an Open Cloud key will be available to the build container through `apis.roblox.com`. This proposal assumes that decision and gives a fallback where it matters.

---

## 0. The pitch in one paragraph

Build one spine that every role stands on:

- the town as data, baked to a greybox place;
- the v5.4 climbing network imported whole;
- one actor model with mid-stride possession;
- the Roles ladder in one module;
- a validated network layer;
- an in-game clock.

On that spine, give each of the eight roles one complete loop of play: notice something, act on it, get a result, see your rank move. The first runnable build (FRB) therefore lets a single tester become any role from an in-game Role Lab panel and play that loop, and lets 2 to 4 Studio clients play the roles against each other.

Everything after the FRB deepens the town, the AI, the quests, the art and the backdrop. Every later build keeps all eight roles green. Art arrives as Roblox asset IDs that replace placeholders at runtime, so the place file stays a pure build artifact that Claude can rebuild and upload headlessly. The owner's Studio work is limited to:

- playtests;
- one rig import per skinned character;
- one final publish.

### Glossary

| Term | Meaning |
|---|---|
| **Actor** | One simulated creature: a human, squirrel, fox or deer. The spicy rodent is a squirrel actor with `Variant = "spicy"`. |
| **Body** | The actor's Roblox Model. |
| **Brain** | The AI decision maker for an actor. It is detached while a player drives the actor. |
| **Motor** | The movement integrator for a body type. The same code runs for AI and players. |
| **Possess / release** | A player takes over or hands back a body. |
| **Rung** | A step on the Roles ladder: human, hospital, police, drone, squirrel or rodent. Deer and fox are side exits. |
| **FRB** | First runnable build: the first build handed to the owner. |
| **Role Lab** | A dev-only panel that switches the tester into any role and triggers test situations. |
| **u / st** | HTML world units / Roblox studs. 1 u = 2.5 st [brief §2]. |

---

## 1. Architecture

### 1.1 Principles

1. **One actor model.** There is one actor kind per species, each with a Brain slot and a Controller slot. Possession is the only mechanism for joining, leaving, queue promotion, backfill, role switching and session reset [brief §4].
2. **The ladder lives in one module.** `Shared/Roles/Ladder.luau` holds all rungs, slot counts, score formulas and transition rules as data plus pure functions. Server services *execute* its results and never restate them [brief §6].
3. **Data is the source of truth.** The town, roads, routes, lanes, traffic control, cast, forage, items and quests are data files. Adding a barber shop is a JSON entry [brief §2].
4. **Pure core, thin engine shell.** All rules and motors are pure Luau modules, testable in Lune. Engine-touching code is a thin layer, tested in Luau Execution.
5. **Server owns outcomes; clients own feel.** Possessed bodies are client-owned for responsiveness. Everything that scores, hurts, infects or promotes is decided on the server [feasibility B.a, B.b].
6. **Gameplay never depends on streamed parts.** Routes, colliders, nav graphs, lanes and forage anchors live in shared data. Server AI runs everywhere, all the time. There is no "pause the world" [hospital_police_infection §12; humans_actors §15].
7. **The place file is a build artifact.** Nothing is authored only in Studio. Studio-made assets become asset IDs referenced from `Config/AssetIds.luau`.
8. **Every number is a tunable.** Each value is stored in HTML units or seconds with a spec citation, and is live-editable in Studio during playtests.

### 1.2 Repository layout (new private repo `spicy-rodents-roblox`)

```
spicy-rodents-roblox/
  default.project.json        code + data + assets (live sync with `rojo serve` if ever wanted)
  build.project.json          default + build/Town.rbxm (the baked greybox town) -> full place
  rokit.toml                  rojo 7.7.1, lune 0.11.1, stylua 2.6.0 (luau feature), selene 0.31.0, luau-lsp
  selene.toml  roblox.yml  stylua.toml  .luaurc  .gitattributes (LFS: *.blend *.fbx *.png *.rbxm in assets/)
  README.md                   brief §14: module layout; how to add a lot type, a route, a role
  CHANGELOG.md                one line per uploaded place version (version number -> git sha)
  data/                       -> ReplicatedStorage.Data  (Rojo turns *.json into ModuleScripts)
    town/lots/<district>.lots.json   one file per district (old_town_core, westside, quay, ...)
    town/roads.json  town/traffic_control.json  town/districts.json
    routes/v54_reference.json        all 1,332 v5.4 routes as control points (captured headlessly, W0)
    routes/graph.json                generated: endpoint links, transfer pairs, forks, islands
    lanes/lanes.json  cast/cast.json  wildlife/wildlife.json  forage/forage_types.json
    hospital/items.json  quests/quest_types.json  blend/palette.json  blend/dev_avatar_samples.json
  src/shared/   -> ReplicatedStorage.Shared   (pure modules; also run under Lune)
  src/server/   -> ServerScriptService.Server
  src/client/   -> StarterPlayer.StarterPlayerScripts.Client
  assets/       -> ReplicatedStorage.Assets   (Lune-generated placeholder rigs/vehicles/props, KeyframeSequences)
  tests/unit/   Lune unit tests (+ golden vectors in tests/golden/*.json)
  tests/engine/ -> ServerStorage.EngineTests  (run by Luau Execution; never shipped to clients)
  tools/        Lune scripts: import_v54, validate_data, bake_town, gen_route_graph, gen_placeholders,
                anims_from_blender, cloud/{save_place, run_engine_tests, upload_asset, poll_operation}
  blender/      bpy build/export scripts + .blend sources (LFS) + exported FBX (LFS) + review renders
  docs/         owner playtest checklists, Studio click-by-click, spike results, decision log
  build/        (gitignored) Town.rbxm, SpicyRodents.rbxl
```

The project files set these properties. `StreamingEnabled`, `ModelStreamingBehavior`, `StreamOutBehavior` and `PlayerCharacterDestroyBehavior` are verified settable from the project file [feasibility B.h]; the rest are checked in W0.

- **Workspace:** `StreamingEnabled = true`, `ModelStreamingBehavior = Improved`, `StreamOutBehavior = Opportunistic`, `PlayerCharacterDestroyBehavior = Disabled` (possession pitfall 1 [feasibility B.a]), `FallenPartsDestroyHeight` below the river bed and sewer.
- **Players:** `CharacterAutoLoads = false`.
- **Workspace (optional):** `EnableSLIMAvatars = true` for the drone view.

### 1.3 Runtime topology

**Server boot order** (`Server/Main.server.luau`):

1. `Config`, `Net`, `Clock`.
2. `TownData.load()` and validate. A failure halts boot with a readable error.
3. `WorldBoot`:
   - check that `Workspace.Town` exists (it is baked into the place);
   - check `Terrain` against the plan hash, and generate terrain if it is missing (D4);
   - swap greybox for art kits wherever the asset ID is present (D9).
4. `Routes.build()`: curves, sampling, spatial index and graph from data.
5. `Traffic.start()`.
6. `Actors.populate()`: bodies per species from Tunables and cast.
7. Domain services start: Infection, Hospital, Police, Drone, Foraging, Wildlife, Seasons, Quests, Sightings, Homes, Jobs.
8. `BrainScheduler.start()`.
9. `Players.PlayerAdded` goes to `RoleService.onJoin`. Players are held on a flyover camera until boot completes.

**Server frame pipeline** (Heartbeat; it mirrors the HTML's traffic-snapshot ordering [traffic §8.1]):

1. Drain validated client motor packets into server-side actor state.
2. `BrainScheduler` runs this frame's brain slices, which emit Intents.
3. AI motors integrate Intents. Anchored AI bodies are moved with one `workspace:BulkMoveTo`.
4. `Traffic.step` at 30 Hz: snapshot poses, then move vehicles.
5. `SweptCollision` runs every squirrel actor against the fleet using previous and current poses.
6. Combat windows and contacts.
7. 1 to 5 Hz services: infection, hospital, police, foraging, seasons, quests, sightings.
8. Telemetry.

**Client frame:**

- input → own-body motor (PreSimulation, fixed 1/60 substeps [routes_movement §20]);
- camera (RenderStepped);
- procedural animation and tail springs for nearby animals;
- HUD at 5 Hz or on change;
- sky from the replicated clock;
- ambient life (birds, insects, overflight) as closed-form functions of server time [wildlife_foraging §15].

### 1.4 Module catalogue

"Owns" is the data the module is the single writer of. Interfaces are the public functions; internals are free to change.

#### 1.4.1 Shared (`src/shared`, pure unless noted)

| Module | Responsibility | Public interface | Owns |
|---|---|---|---|
| `Config/Units` | HTML-unit ↔ stud conversion and the facing convention (D11). | `studs(u)`, `units(st)`, `yawCFrame(htmlYaw, pos)`, `toWorld(x, y, z)` | `STUDS_PER_UNIT = 2.5` |
| `Config/Tunables` | Every gameplay number, nested by system, each with a unit tag and a spec citation. | `get(path)`, `studs(path)`, `onChanged(path, fn)`, `snapshot()`, `diff()` | the tunable tree (§3.6) |
| `Config/AssetIds` | Asset ID registry (meshes, rigs, animations, images, sounds), with placeholder fallback per key. | `id(key)`, `has(key)`, `all()` | key → assetId |
| `Config/Palette` | Town palette clamps for the avatar blend and signage. | `clamp(color3, purpose)`, `nearestSkinTone(c)` | palette stats [worldgen_districts_art §11, §15 A3] |
| `Config/Flags` | Feature flags and dev gating. | `enabled(name)`, `isDev(player)` | flag table, dev UserIds |
| `Util/*` | `Rng` (mulberry32 port [worldgen_core §16]), `Signal`, `Spring`, `Grid` (spatial hash), `Geometry` (AABB/OBB, `segmentBoxEntry`), `Log`, `Schema` (validators). | per util | — |
| `Net/Net` | One registry of every remote, with a payload schema, a reliability flag and a per-player rate limit (§1.5). | `define(name, spec)`, `fire(player, name, data)`, `fireAll`, `fireNear(pos, r, ...)`, `on(name, handler)`, `invoke` | the remote table |
| `Clock/Clock` | Server-time-based game clock: in-game day, hour, week, season, lunar age; a non-linear day curve that holds golden hours. | `serverNow()`, `game()` → `{day, hour, week, isWinter, lunarAge, phase}`, `onHour/onDay/onWeek` (server), `setScale` (dev) | epoch attribute, `realSecondsPerDay` |
| `Clock/Moon` | Phase maths, already unit-tested in the feasibility smoke [feasibility B.f]. | `phase(lunarAge)` → `{index, illum}` | — |
| `Terrain/Height` | Verbatim port of `baseTerrainHeight`/`terrainHeight` [worldgen_core §3, §16]. | `base(x, z)`, `at(x, z)` (u) | — |
| `Terrain/Ground` | Gameplay ground: terrain, roads, roofs and porches as a pure function of position *and* a reference height (fixes the v5.4 `getGroundAt` global-state bug [routes_movement verifier 5]). | `groundAt(x, z, refY)`, `roofAt(x, z, refY)`, `surfaceKind(x, z)` | — |
| `Town/TownData` | Loads, validates and indexes lots, roads and districts. | `lots()`, `lot(id)`, `byType(t)`, `inDistrict(x, z)`, `districtTag(x, z)` (HUD and map labels [worldgen_districts_art §1]), `colliders()`, `pavementDistance(x, z)` | the validated in-memory town |
| `Town/Colliders` | Analytic colliders from lots (house/commercial AABBs, fence segments, tree circles), in a spatial hash. | `blocked(p0, p1, radius, refY)`, `query(aabb)` | collider grid |
| `WorldGen/Plan` | **Pure**: lots → a `BuildPlan` (models, parts, prompts, doors, colliders, nav graphs, route specs, terrain spans, road strips). Deterministic per seed. | `plan(townData, seed)` → `BuildPlan`, `hash(plan)` | — |
| `WorldGen/LotTypes/*` | One module per lot type (house, shop, restaurant, hospital, police_station, park, quay_building, mall_shop, tree, hollow_tree, pole, …). Each follows the LotType contract (§3.2). | `params`, `build(lot, ctx)`, `routes(lot)`, `colliders(lot)`, `nav(lot)`, `prompts(lot)`, `forage(lot)`, `jobs(lot)`, `skyline(lot)` | — |
| `WorldGen/Instantiate` | `BuildPlan` → Instances. It runs in **Lune** (bake to `Town.rbxm`), in the **engine** (fallback and tests), and in a **Studio plugin** (final art bake). | `instantiate(plan, parent, mode)` | — |
| `WorldGen/TerrainBake` | Engine-only: writes heightfield voxels, road and garden materials, river and ocean water. | `apply(plan, opts)`, `verify(plan)` | Terrain `BakeHash` attribute |
| `Routes/Curve` | Centripetal Catmull-Rom (alpha 0.5, phantom ends, knot guards), arc-length table of 200 divisions, `sampled` at `max(20, ceil(3L))` [routes_movement §1, §20]. | `new(points)`, `pointAt(t)`, `tangentAt(t)`, `length`, `samples` | — |
| `Routes/Registry` | All routes: imported v5.4 reference plus lot-type generators plus hollows. 10 kinds: the 8 v5.4 kinds plus `duct` and `hollow` (§3.4). | `build(townData)`, `get(id)`, `all()`, `byLot(lotId)`, `byKind(k)` | routes |
| `Routes/SpatialIndex` | 8-u (20-st) cell hash of samples (about 82k entries) plus a trunk-foot grid [routes_movement §1.3, §20]. | `nearest(point, maxDist, excluding)`, `neighbours(cell)`, `trunkNear(pos, r)` | index |
| `Routes/Graph` | Precomputed topology: endpoint auto-links (≤ 0.48 u), explicit transfers (≤ 1.7 u), canopy forks, islands [routes_movement §3, §12]. | `endLinks(routeId, atStart)`, `transfers(routeId, t)`, `forks(trunkId)`, `island(routeId)` | graph |
| `Routes/Motion` | `RouteMotion.advance`, rail speed by kind, junction choice, fork choice, sibling side-step, visual offset and surface normal [routes_movement §1.2, §10–§14]. | `advance(state, input, dt)`, `chooseJunction(...)`, `chooseFork(...)`, `visualPose(state)` | — |
| `Movement/SquirrelMotor` | **Pure** squirrel and rodent motor: ground, air, rail, leap, pounce lunge, stalk, duct, hollow interior; fixed substeps; world access through a `WorldQuery` interface [routes_movement §8–§13; squirrel_abilities §4–§6]. | `new(params)`, `step(state, input, dt, world)` → `state, events`, `serialize(state)`, `deserialize(blob)` | motor state schema |
| `Movement/QuadrupedMotor` | Pure fox and deer motor: ground only, turn-rate limited, lunge or bolt [wildlife_foraging §11.8–11.9]. | same shape | — |
| `Movement/HumanAIMotor` | Pure kinematic walker for AI humans: lane following, door threshold, push-out, ground snap [humans_actors §5, §15]. | same shape | — |
| `Movement/CarMotor` | Pure kinematic car: bicycle model, throttle and brake curves, ground snap; used by AI vehicles *and* the player patrol cars (D12). | same shape | — |
| `Movement/DroneMotor` | Pure flight model: velocity steering, altitude band, tilt, zoom. | same shape | — |
| `Actors/Species` | Species definitions: body kind (Humanoid R15 or AnimationController rig), motor, default brains, hitbox, sockets, stock looks. | `def(species)`, `variants(species)` | species table |
| `Roles/Ladder` | **The ladder** (§3.5): rungs, slots, side exits, score formulas, promotion queue ordering, transition rules. | `rungs`, `sideExits`, `slots(rung, state)`, `score(rung, stats)`, `rankOrder(players, rung)`, `resolve(event, ctx)` → `{Transition}` | the ladder |
| `Combat/CombatRules` | Pounce launch vector, wind-up/commit/recovery windows, contact tests, bite chance by awareness, kick, baton and shove timing, damage, health regen, feint and zig-zag (W4) [squirrel_abilities §6, §25–§26; humans_actors §5.5]. | `pounceVelocity(ctx)`, `contact(att, tgt)`, `biteChance(awareness, ctx)`, `strikeHits(att, tgt, weapon)`, `damage(weapon, ctx)`, `regen(state, dt)` | — |
| `Infection/InfectionRules` | Per-actor infection, town %, squirrel-share maturation (HTML 25/7 % per squirrel, 25 cap, 1500 s), hidden critical-mass test [hospital_police_infection §6, §11]. | `townPercent(state)`, `squirrelShare(state, dt)`, `criticalMass(state)`, `cureTime(staffInfected)` | — |
| `Traffic/Swept` | Exact port of `sweptVehicleHit` and `segmentBoxEntry` [traffic §8.4]. | `hit(P0, P1, V0, V1, psi0, psi1, W, L, H)` → `bool`, `broadPhase(...)` | — |
| `Traffic/LaneMath` | Lane parametrisation, leader/follower query, yielding corridor, stop-line FSM, the ice-cream-van spline table [traffic §5–§6, §13]. | `pointAt(lane, s)`, `leader(laneState, s)`, `seesHazard(...)`, `stopLine(...)` | — |
| `Foraging/ForageRules` | Yields, cooldowns on the game clock, carry capacity, hollow meter, ownership at ≥ 70 %, premium weekly raid, winter multiplier, stink-gland fill and fire (≥ 95 %, −30) [brief §7; wildlife_foraging §14]. | `yield(source, ctx)`, `meter(hollow)`, `owner(hollow)`, `stink(state, dt)`, `canFire(state)` | — |
| `Seasons/SeasonRules` | Calendar: 7-day week, winter in week 6 of each 6-week cycle, survival threshold [brief §12]. | `isWinter(day)`, `weekOf(day)`, `survives(hollowMeter)` | — |
| `Avatar/BlendRules` | **Pure** 70/30 composition: avatar traits plus stock look → Look; saturation and value clamps; signature-feature picker for bizarre avatars [Addendum A3]. | `traits(desc)`, `compose(species, stockLook, traits)` → `Look`, `isBizarre(traits)` | — |
| `Map/MapModel` | Town data → 2D map primitives (roads, lots, district labels), world ↔ map projection. | `build(townData)`, `project(x, z)`, `labels()` | — |
| `Quests/QuestTypes` | Quest definitions as data plus pure step validators (§3.7). | `def(type)`, `nextStep(q, evt)` | — |

#### 1.4.2 Server (`src/server`)

| Module | Responsibility | Public interface | Owns |
|---|---|---|---|
| `Main` | Boot order and the frame pipeline (§1.3). | — | — |
| `Boot/WorldBoot` | Verifies the baked town, terrain hash and generation, art-kit swap, `Skyline` persistent layer. | `ensure()`, `kitSwap()` | — |
| `Actors/ActorService` | Actor registry and lifecycle. | `spawn(species, spec, cf)`, `get(id)`, `ofBody(model)`, `query(filter)`, `nearest(pos, r, filter)`, `kill(actor, cause)`, `setBrain(actor, name, params)`; signals `Spawned`, `Died`, `Possessed`, `Released` | `Actor{id, species, variant, body, controller, brain, motorState, health?, infected, traits, homeLot?, castId?, look}` |
| `Actors/BodyFactory` | Builds bodies from species, stock look and placeholder or art rig. Sets `ModelStreamingMode = Atomic`, the PrimaryPart and sockets. | `build(species, look)`, `applyLook(body, look)` | — |
| `Actors/Possession` | **The single handoff mechanism.** Ensures streaming, sets ownership and `player.Character`, sends a motor snapshot and applies the avatar blend; release reverses it and resumes the brain. | `possess(player, actor)`, `release(player, why)`, `swap(player, toActor)`, `controllerOf(actor)` | player ↔ actor map |
| `Actors/BrainScheduler` | Time-sliced brain ticks with distance LOD (D2), per-tier budgets and Parallel Luau as a later option. | `register(actor)`, `unregister`, `setFocus(fn)`, `budgetReport()` | LOD tiers |
| `Actors/Brains/*` | `Pedestrian`, `Resident`, `ShopWorker`, `HospitalStaff`, `Patient`, `Officer`, `Driver` (W4), `Burglar` (W4), `Arguer` (W4), `Defender` (W3), `Squirrel`, `Rodent`, `Fox`, `Deer`. Each: `new(actor, params)`, `think(dt, ctx)` → `Intent`, `resume(snapshot)`, `onEvent(evt)`. | per brain | brain state |
| `Movement/MoveValidator` | Validates client motor packets: speed caps per kind, legal transfers, gravity arcs, no wall crossing; a leaky bucket; log-only in the FRB, enforced in W7 [routes_movement §20]. | `accept(actor, packet)` → `ok, correction` | violation counters |
| `Roles/RoleService` | Executes Ladder transitions: join and leave, queue, promotion offers, side exits, top-2 police car keys, stats (time active, credits, kicks, nuts, stink). | `onJoin`, `onLeave`, `report(event)`, `roleOf(player)`, `stats(player)`, `queue(rung)`, `offer(player, rung)`, `forceRole(player, rung, why)` (Lab) | per-player role stats (per server, per brief) |
| `Roles/RoleLab` | Dev-only test panel backend (§4.4). | `handle(player, command, args)` | — |
| `Combat/CombatService` | Server-side pounce, kick, baton and shove protocol: windows, lag-rewound contacts (W7), health and death [squirrel_abilities §26]. | `requestPounce`, `requestStrike`, `damage(target, amt, src)`, `healthOf(actor)`; signals `Hit`, `Kick`, `Killed` | health and window state |
| `Infection/InfectionService` | Per-actor infection, red-eye tell, walk-in routing, squirrel share, hidden critical mass, outbreak and reset (§7.2 D-5). | `infect(actor, src)`, `cure(actor, by)`, `isInfected`, `townPercent()`, `onCriticalMass` | infection state |
| `Hospital/HospitalService` | Admissions, stations, the disinfection loop, fetch tasks, performance metric, upgrades [hospital_police_infection §11 items 1–9]. | `admit(actor)`, `stations()`, `startDisinfect(staff, patient)`, `fetch.offer/pick/deliver`, `performance()`, `upgrade(id)` | stations, tasks, metric |
| `Police/PoliceService` | Officers, dispatch backfill, tickets, side-quest resolution, performance, slot expansion 5→8, drone unlock [brief §10; Addendum A1–A2]. | `officers()`, `keysHolders()`, `ticket(officer, target, kind)`, `performance()`, `unlockSlot()`, `droneUnlocked()` | police state |
| `Drone/DroneService` | Launch and dock, server-validated spot-and-mark, vigilante summon, deer startle source. | `launch(pilot)`, `dock(pilot)`, `mark(pilot, aim)` → `MarkResult`, `activeMarks()` | marks |
| `Vehicles/TrafficService` | AI fleet on lanes, yielding, traffic control (stop signs, signals), speeds and limits, violations, teleport flags, the fleet list for the swept test [traffic §13]. | `fleet()`, `vehicle(id)`, `speedOf(v)`, `limitAt(pos)`, `addPlayerCar(car)`, `violations()`; signal `RunOver` | vehicle state |
| `Vehicles/PlayerCars` | The two drivable patrol cars: keys, enter and exit, siren and lights, park anywhere [Addendum A1]. | `grantKeys(player)`, `revokeKeys`, `enter(actor, car)`, `exit(actor)`, `setSiren(car, on)` | car ownership |
| `Vehicles/SweptCollision` | Runs `Traffic/Swept` for every squirrel actor every traffic tick; reports run-overs with the killer (driver) identity. | `step(dt)`; signal `Hit(squirrelActor, vehicle, driver?)` | previous poses |
| `Sightings/SightingService` | Sightings from spotting transitions, bites, witnesses, posters and drone marks; fade; visibility by role (decision D-7). | `report(kind, pos, conf, src)`, `markersFor(player)` | sightings |
| `Quests/QuestService` | Generates side quests from simulation sources, offers them to eligible roles, tracks steps, pays credits and rank. | `registerType(def)`, `offer(player, q)`, `accept`, `progress(evt)`, `active(player)` | quests |
| `Jobs/JobService` + `Credits` | Shop and work spots for townspeople; credits ledger feeding rank and upgrades [brief §13]. | `jobsAt(lotId)`, `work(actor, spotId)`, `Credits.add(player, n, why)`, `balance` | credits |
| `Homes/HomeService` | Claimable homes among the 40 interior houses; remodel points per real day of play; per-server life [brief §8]. | `claim(player, lotId)`, `release`, `points(player)`, `remodel(lotId, option)` | home claims |
| `Foraging/ForageService` | Forage sources from lot data, cooldowns on the game clock, carried nuts, risk triggers (homeowner, dog, cat, birds). | `sources()`, `forage(actor, srcId)`, `carried(actor)` | source state |
| `Foraging/HollowService` | 11 hollows: meters, ownership, deposits and withdrawals, theft below 70 %, rodent rest (decision D-19). | `meter(id)`, `owner(id)`, `deposit(actor, id, n)`, `enter(actor, id)`, `leave` | hollow state |
| `Foraging/StinkService` | Stink-gland fill and fire, repel field. | `fire(actor)`, `repelling(pos)` | stink meters |
| `Wildlife/WildlifeService` | Population upkeep for squirrels, deer and fox; threat queries; startle events (traffic, drone) [wildlife_foraging §13]. | `threatsNear(pos)`, `startle(actor, src)`, `upkeep()` | — |
| `Seasons/SeasonService` | Season transitions, winter effects (snow terrain swap in chunks, bare trees, forage multiplier), winter-end survival check. | `isWinter()`, `onWinterStart/End`, `survivalCheck()` | — |
| `Avatar/AvatarBlendService` | Fetches and caches avatar traits, composes and applies Looks on possession, reverts on release. | `apply(actor, player)`, `revert(actor)`, `preview(actor, sample)` (Lab) | trait cache |
| `Persistence/Profiles` (W7) | DataStore profile per UserId (cosmetics, settings, lifetime stats) with session locking. | `load(player)`, `save`, `get/set` | profiles |
| `Telemetry/Perf` | Per-system ms per frame, actor counts by LOD tier, remote traffic; shown in the Lab. | `mark(system)`, `report()` | — |

#### 1.4.3 Client (`src/client`)

| Module | Responsibility | Public interface |
|---|---|---|
| `Main` | Client boot; waits for the possession grant. | — |
| `Possession/PossessionClient` | Handles `Granted` and `Revoked`; picks the controller and camera for the body; seeds mid-stride carry-over intent (D1). | `onGranted(body, snapshot)`, `current()` |
| `Controllers/*` | `HumanController` (default Humanoid controls plus our verbs), `SquirrelController` (`SquirrelMotor` plus Align constraints), `QuadrupedController`, `CarController`, `DroneController`. Each: `start(body, snapshot)`, `stop()`, `packet()` → motor state for the server. | per controller |
| `Input/InputMap` | Data table of bindings per role (keyboard, gamepad, touch) through ContextActionService (§1.6). | `bind(role)`, `unbind()` |
| `Camera/CameraRig` | Per-mode rigs: human third person, squirrel rigs per route kind with commit and FOV table [routes_movement §15], stalk first person, car chase, drone feed; spherecast occlusion with a CameraBlocker group [worldgen_districts_art §16]. | `setMode(mode, params)` |
| `Animation/AnimationDriver` | Body state → animation. Two backends: **Clip** (Animator tracks) and **Procedural** (Motor6D transforms for placeholder animals, after the HTML gait formulas [squirrel_abilities §2.4, §24]). Also `TailSpring` and `FootIK` within about 60 st. | `attach(body, species)`, `setState(state)` |
| `Render/Interp` | Smooths anchored AI bodies and vehicles between server moves where needed (D2 fallback). | — |
| `UI/Hud` | Role-specific panels: rank, queue position, credits, nuts, stink, health, infected status, quest tracker. | `setRole(role)`, `update(state)` |
| `UI/MapUI` | Minimap and full-screen map from `MapModel`; marker layers (self, sightings, drone marks, quests, home, own hollow, cars). | `setLayers(list)` |
| `UI/RadarUI` | Patrol-car radar: vehicles in a forward cone, speed against limit. | — |
| `UI/Notifications` | Priority queue of toasts; danger telegraphs are never overwritten by flavour text [squirrel_abilities §26, verifier 2]. | `push(msg, prio, ttl)` |
| `UI/PromptUI` | Custom ProximityPrompt style; hides prompts not meant for my role (the server re-validates). | — |
| `UI/OfferUI` | Promotion offers: Accept / Deer instead / Fox instead / Stay, with a timeout. | — |
| `UI/RoleLabUI` | The dev panel (§4.4). | — |
| `World/SkyController` | Lighting, Atmosphere, Sky and post-effects from `Clock` [worldgen_districts_art §14.3]; moon texture by phase; star count; winter grade. | — |
| `World/AmbientLife` | Birds, nests, insects and the overflight as closed-form functions of server time and seed [wildlife_foraging §15]. | — |
| `World/Beacons`, `World/Doors`, `World/InteriorCulling`, `World/SkylineFade` | Beacon blink; door swing visuals (state from server attributes); roof hiding inside interiors; fades skyline impostors once the real model has streamed in (D3). | — |
| `Audio/AudioController` | Positional and UI sounds, ambience by zone (W6). | — |

### 1.5 Network layer (`Net`)

All remotes are declared in `Shared/Net/Schemas.luau`, so the full client-server surface is reviewable in one file. Every inbound payload is type- and range-checked (finite numbers, enum strings, IDs that exist) and rate-limited by a per-player token bucket. A rejected packet is logged and dropped; it never errors the server.

| Remote | Direction | Reliability | Payload | Rate |
|---|---|---|---|---|
| `Motor.State` | C→S | Unreliable | `{seq, t, kind, routeId?, s?, dir?, pos, vel, moveState}` | 15 Hz |
| `Action` | C→S | Reliable | `{verb, args}`. Verbs: `Pounce`, `Strike`, `Kick`, `Leap`, `Interact`, `Stink`, `Lunge`, `Graze`, `Mark`, `Siren`, `EnterCar`, `ExitCar`, `Launch`, `Dock`, `Choose` | 10/s |
| `Offer.Reply` | C→S | Reliable | `{offerId, choice}` | 1/s |
| `Lab.Command` | C→S | Reliable | dev only (`Flags.isDev`) | 5/s |
| `Possession.Granted` / `Revoked` | S→C | Reliable | `{actorId, body, species, role, motorSnapshot}` | event |
| `Hud.State` | S→C | Reliable | private per player: `{rank, queue, credits, nuts, stink, health, infectedSelf, quests}` | ≤ 5 Hz on change |
| `Notify` | S→C | Reliable | `{text, prio, ttl, kind}` | event |
| `Telegraph` | S→C | Unreliable | wind-ups near a client: `{actorId, kind, tCommit}` | event |
| `Map.Markers` | S→C | Reliable | layer deltas visible to this player | ≤ 2 Hz |
| `Combat.Result` | S→C | Reliable | `{kind, attacker, target, outcome}` for corrections | event |

Public body state uses **attributes** on the body: `ActorId`, `Species`, `Variant`, `Role`, `MoveState`, `Health`, `InfectedTell` (eyes), `Controller` (`"ai"` or `"player"`), `LookSeed`. Rank and credits stay private.

### 1.6 Controls per body (v5.4 mapping kept where it exists [squirrel_abilities §3])

| Body | Keyboard and mouse | Notes |
|---|---|---|
| Human | WASD, Shift sprint, Space jump, E interact, LMB kick/swing/baton/shove (by role), F flashlight (night) | Default Humanoid controls plus our verbs. Touch and gamepad come from the default PlayerModule. |
| Squirrel / rodent | WASD, Shift sprint, Space leap, E grab/interact (hold to chew), Q drop, A/D fork or junction on rails, RMB hold stalk, F stalk toggle, LMB pounce (rodent), R stink (squirrel), C recenter | Esc and Tab are reserved by Roblox [squirrel_abilities §26]. |
| Fox | WASD, Shift run, Space jump, LMB lunge | |
| Deer | WASD, Shift bolt, Space leap, G graze | |
| Patrol car | W/S throttle and brake, A/D steer, Space handbrake, H siren and lights, E exit | |
| Drone | WASD move, E/Q up and down, mouse look, wheel zoom, LMB hold to mark, F dock | |

---
## 2. Key technical decisions

Each decision gives what is chosen, why, the fallback, and how and when it gets verified. "Spike" means a W0 experiment (§4.2).

### D1. Movement authority

**Possessed bodies: client-owned.**
- **Humans** use the default Humanoid controller. The server sets `Anchored = false`, `Humanoid.EvaluateStateMachine = true` and `SetNetworkOwner(player)`, then `player.Character = body`.
- **Squirrels, fox and deer** use our pure motors. The motor computes a target CFrame each substep, and `AlignPosition` and `AlignOrientation` (rigid) move the unanchored, non-colliding root. Physics replication carries it to the server [feasibility B.b option 1].
- **Cars and the drone** work the same way as the animals.

**AI bodies: server-kinematic.** The root is anchored. Humanoids run with `EvaluateStateMachine = false` and unused states disabled. The server moves bodies with `BulkMoveTo` from motor output, which avoids physics cost [feasibility B.b, B.e]. Animations still play through server-created Animators.

**Mid-stride handoff.**
- On possess, the motor state is serialized (route id, arc position `s` and direction for a squirrel on a rail; velocity and heading on the ground) and sent with `Possession.Granted`. The client motor resumes exactly there.
- Humans get a carry-over intent: the AI's last move direction is held for up to 0.75 s or until the player's first input.
- On release, the server snapshots the CFrame and velocity, anchors the body and calls `brain:resume(snapshot)`. The brain rejoins the nearest lane or route point and walks on.

**Validation.** `MoveValidator` checks speed caps per route kind and mode, transfer gaps (≤ 3.15 u), grab radius (≤ 3.4 u), gravity-consistent arcs, and wall crossings against `Town/Colliders` [routes_movement §20]. In the FRB it logs violations and never corrects them, so playtests are not ruined by false positives. W7 turns enforcement on.

**Why.** Rails need 60 Hz input-coupled motion [routes_movement §20]. Kinematic AI is far cheaper than physics with about 60 humans [feasibility B.e]. One motor codebase drives both AI and players, which is the actor-model rule.

**Fallback.**
1. If client-owned bodies replicate badly (jitter, or animations not replicating [feasibility B.a pitfall 2]), use **Server Authority** (`Workspace.AuthorityMode = Server`) for the rodent and squirrels once it is out of beta. The motors are already shared pure modules, so they drop into `BindToSimulation`.
2. Second fallback: server-authoritative positions with client prediction for the possessed squirrel only.

**Verify.** Spike S6 (2-client possession place, owner check) and the FRB playtest checks M1 and M2.

### D2. AI scheduling and LOD

**Brains and motors run at separate rates.** Brains think at 4 to 10 Hz, staggered by a per-actor phase. Motors integrate every frame for near actors.

**LOD focus.** The focus set is every player body plus the drone camera position, because the drone sees the whole town.

| Tier | Distance to nearest focus | Brain | Motor | Perception |
|---|---|---|---|---|
| Near | < 150 st | 10 Hz | 60 Hz | full (spot, hear, threats) |
| Mid | 150–500 st | 4 Hz | 15 Hz | coarse (spot only) |
| Far | > 500 st | 1 Hz | 5 Hz | none; "commute" along lanes, doors are instant |

**Budget.** Under 4 ms per frame for all AI on the server [feasibility B.e]. `Telemetry/Perf` reports it, and a Luau Execution simulation enforces it as a regression test (§6.3).

**Perception.** Each human gets a spatial hash query for threats within 50 st, evaluated with the v5.4 `spotted` rule at 5 to 10 Hz, using *height above local ground* instead of absolute Y [humans_actors §5.3, §15].

**Fallback.**
1. Move perception into 2 to 4 Parallel Luau `Actor`s, each owning a slice of brains, with writes in the serial phase [feasibility B.e].
2. Cut the Mid and Far rates.
3. If anchored-body replication bandwidth is too high, replace server-moved anchored bodies for Mid and Far AI with a compact state stream (`id, x, z, yaw, anim`) rendered by `Render/Interp`. Near bodies stay real.

### D3. Streaming

- `StreamingEnabled` is on with the defaults (target radius 1024, min radius 64) [feasibility B.e].
- Every actor body, building, tree, hollow, house shell plus interior, and hospital zone is `ModelStreamingMode = Atomic`.
- Before any possession, teleport or interior entry, the server calls `RequestStreamAroundAsync(target)` [feasibility B.a pitfall 5].
- The drone pilot gets a stream-around along the flight path at 2 Hz.
- **Drone view.** A persistent **Skyline** model holds one or two simple massing parts per building (roof colour and silhouette) plus the landmarks. `World/SkylineFade` hides a skyline piece locally once the full model has streamed in. This works from the FRB onward, with no publish needed.
- **Backdrop.** Mountains, ocean and the radio tower are `Persistent`.

**Fallback and upgrade.** At final publish, the Studio art bake sets `LevelOfDetail = SLIM` on buildings and backdrop (needs a saved, published place [feasibility B.e]), and Skyline is retired if SLIM looks right from 300 st.

### D4. WorldGen: bake versus runtime

**Chosen: "plan once, instantiate anywhere".**
- `WorldGen/Plan` is pure and deterministic from the lot data.
- **Build time.** `tools/bake_town.luau` runs Plan plus Instantiate in Lune (`@lune/roblox`) and writes `build/Town.rbxm`. `build.project.json` places it in `Workspace.Town`. `rojo build` therefore produces a complete greybox place headlessly, satisfying "builds the town from data, never from hand-placed parts" [brief §2]. Static geometry in the saved place also keeps the SLIM path open [feasibility B.e, Blocker 6].
- **Terrain at boot.** Lune cannot write Terrain, so `TerrainBake.apply` runs at server boot when the Terrain `BakeHash` attribute does not match the plan. The terrain covers the whole playable rectangle, closing the v5.4 ground-mesh gaps [worldgen_core §2]. The heightfield is written with `WriteVoxels` in chunks; roads and gardens get Terrain materials; the river and ocean are water. Players wait on the flyover camera until it is done.
- **Final art bake.** The Studio plugin button "Bake Town" runs the same Plan, swaps art kits, writes Terrain and stamps the hash, so the published place boots without regenerating.

**Fallback.**
1. If boot terrain takes more than about 20 s (spike S2 measures it), make the Studio terrain bake mandatory before playtests: one owner click per terrain change.
2. Or lower the voxel resolution outside the playable core.

### D5. Traffic collision

- **Exact port** of `sweptVehicleHit` and `segmentBoxEntry` (relative motion, yaw substeps of at most 0.05 rad, rotation pad, vertical slab) [traffic §8.4]. It runs on the server at 30 Hz for **every squirrel actor** (AI, player and rodent) against the fleet, including player patrol cars [brief §8; Addendum A1]. It never uses `Touched`.
- **Broad phase:** a circle reject [traffic §13].
- **Teleport flag:** every scripted reposition (lane wrap, dispatch, possession, house or sewer transit) resets the previous pose, fixing the v5.4 "short teleports are swept" defect [traffic verifier 1].
- **Stationary cars are never fatal** (displacement < 1e-5, the v5.4 rule). A parked player car cannot kill a squirrel that walks into it [traffic §13].
- **Lag.** The FRB uses option (a): server-observed poses plus the 0.18 u pad. W7 adds option (b): a 1 s ring buffer of vehicle poses, rewound to the client timestamp for player squirrels [traffic §13].
- **Defects not ported:** inconsistent handedness, the trolley and RV deadlock, the patrol car driving through the eastbound lane, and the double look-ahead [traffic §3, §6.1, verifier 4–5].
- Lanes become per-lane leader/follower queries. AI cars treat player cars as fleet members, so they yield to them.

**Fallback.** If lagged client positions cause unfair deaths in playtests, the client flags a near miss and the server confirms within a tolerance (option c).

### D6. Animation pipeline

- **FRB.**
  - Humans play Roblox's stock R15 locomotion animations, owned by Roblox and usable in any experience, through our own `AnimationDriver`. Possessed NPCs get no `Animate` script [feasibility B.a pitfall 3].
  - Verb clips (kick, baton, shove, disinfect, write ticket) start as short procedural Motor6D pose blends.
  - Placeholder animals use the procedural backend, which ports the HTML gait formulas [squirrel_abilities §2.4, §24].
- **Clip path A (headless, preferred).** Blender exports per-bone transforms per frame to JSON. `tools/anims_from_blender.luau` builds a `KeyframeSequence` `.rbxm` whose Pose names match the rig. Open Cloud uploads it as an Animation [feasibility B.d]. The engine test `Assets.animations` loads every clip with `KeyframeSequenceProvider:GetKeyframeSequenceAsync`. Spike S3 proves or disproves this path; the docs warn that "files edited outside Studio might not upload or function".
- **Clip path B (owner fallback).** In a scratch "Art Inbox" place: Animation Editor → Import → From FBX Animation → Publish to Roblox under the experience owner [feasibility B.c].
- **Iteration without uploads.** Git-tracked KeyframeSequences can be played in Studio playtests with `AnimationClipProvider:RegisterAnimationClip` [feasibility B.c].
- **Ownership.** The experience, all animations and all models must have the same owner (user *or* group), or "Failed to load animation" follows [feasibility B.c, Blocker 7]. This is owner decision D-1.
- **Pounce markers.** Pounce, kick and baton clips carry KeyframeMarkers `Commit` and `Recover`. Gameplay windows come from Tunables, not from the clip, so art never changes balance.

### D7. Avatar blend (70 % stock, 30 % avatar)

**Traits** (server, cached per UserId):
- `Players:GetHumanoidDescriptionFromUserId` gives body colours, accessory list, scales, body-part IDs and face.
- `Players:CreateHumanoidModelFromDescription` gives real Accessory instances for re-use.
- Colour hints come from body colours, plus colour words parsed from item names via `MarketplaceService:GetProductInfo` (rate-limited and cached). Clothing pixels are not read [Addendum A3].

**Compose** (`BlendRules.compose`, pure):
- **Humans** keep the role body type, uniform and silhouette. They take:
  - skin tone (nearest of 8 baked tones);
  - one hair or head accessory;
  - an accent colour on a TintMask zone (tie, scarf, trim, shoes).
- **Animals** keep the species mesh and stock markings. They take:
  - a fur tint lerped 30 % toward the avatar's dominant colour (MeshPart `Color` over a TintMask SurfaceAppearance);
  - pattern colour (tail tip, stripes) from the second avatar colour;
  - eye colour, except the rodent's eyes, which stay bloodshot red [squirrel_abilities §25.11];
  - one accessory shrunk onto `HeadSocket` (capped bounding box, no collision, no mass).
- All colours are clamped to saturation ≤ 0.55 and value 0.39–0.91; one neon "signature" accent is allowed [worldgen_districts_art §15 A3].
- **Bizarre avatars** (non-standard body parts, extreme scales, neon, huge accessories) keep a single signature feature. Anything that changes silhouette or hitbox is dropped. Hitbox and route offsets never change [routes_movement §19 A3].

**Revert.** `revert(actor)` restores 100 % stock on release.

**Studio testing.** Studio test players have negative UserIds, so the Lab offers a sample set (classic, neon, giant, non-human bundle) built from HumanoidDescriptions in `data/blend/dev_avatar_samples.json`.

**Fallback.** If trait fetches fail or throttle, use a stock look with a seeded variant. If TintMask tinting looks wrong on the final fur, author 6 to 8 fur colour variants and pick the nearest.

### D8. Persistence

- **Per server only for gameplay state**, as the brief requires: human rank is "time … on this server" and remodels "persist for the life of that server instance" [brief §6, §8]. Rank, credits, hollows, homes and remodels live in memory. **The FRB needs no DataStore**, which keeps Studio setup at zero ("Enable Studio Access to API Services" is not needed).
- **W7:** a DataStore profile (session-locked `UpdateAsync`) for cosmetics (if the fashion stand survives, decision D-12), settings and lifetime stats only.

**Fallback.** None needed. If the owner later wants cross-server rank, it is a contained change in `RoleService.stats`.

### D9. Asset delivery: art as IDs, place as artifact

- Every art asset is a Roblox asset ID in `Config/AssetIds.luau`.
- At boot, `WorldBoot.kitSwap` loads each model kit once with `InsertService:LoadAsset`, which works for assets owned by the experience creator, and clones it where greybox lots name that kit. `BodyFactory` does the same for rigs.
- Missing IDs fall back to the Lune-generated placeholder, so art never blocks a build.

**How assets get IDs.**
- Rigid props and building kits: Claude uploads FBX through Open Cloud (Model).
- Skinned rigs: the owner imports them once in Studio in a separate "Art Inbox" place, then uses Save to Roblox (§4.5 step O4).
- Images, decals and moon phases: Claude uploads them through Open Cloud.

**Why.** Claude's builds never overwrite owner work, and the API place-publish limits on SurfaceAppearance and unions [feasibility B.d] do not touch the place file.

**Verify.** Spike S4: does a textured FBX uploaded through Open Cloud load with SurfaceAppearance or TextureID? Does a SurfaceAppearance survive `LoadAsset`?

**Fallback.** For SLIM and the final publish, the Studio "Bake Town" button writes the art into the saved place, and the owner publishes from Studio.

### D10. Build delivery to the owner: no terminal

- Each owner build is `rojo build build.project.json`, then saved as a new place version through Open Cloud. The owner opens the place from the Studio start page and presses **Test**.
- The Rojo plugin is not needed for playtests; it remains an option if the owner ever wants live sync.
- CI uploads go to a separate **CI place** in the same universe, so integration tests never disturb the owner's playtest place.

**Fallback.**
1. If Open Cloud is unavailable, attach `SpicyRodents.rbxl` to a GitHub release; the owner downloads it and double-clicks it.
2. Second fallback: `rojo serve` plus the plugin.

### D11. Units and conventions

- Data stays in **HTML units** (x, z, y, footprint) and HTML yaw, so every spec number and citation stays directly comparable. `Units.studs` converts at the engine boundary only.
- **Facing.** Humanoids face Roblox LookVector (−Z), so *all* authored models face −Z (Blender export Z-forward/Y-up makes Blender −Y face LookVector [feasibility A5]). `Units.yawCFrame` adds π once, in one place.
- The specs say "models face +Z (brief)". This is a deliberate, single-point deviation for engine compatibility (decision D-25).
- **North** is decision D-2.

### D12. Player-driven patrol cars

- **Kinematic arcade car.** `CarMotor` (the same model as AI vehicles) runs on the client with input and ground snap from `Terrain/Ground`. Collisions are shapecasts against world geometry plus OBB checks against fleet vehicles.
- The server validates speed and teleport limits (no jump over 30 st per tick [traffic §13]) and feeds poses to the swept test.
- Seat and driver: the officer's body is welded into the driver seat; the camera switches to the chase rig; E exits beside the driver door.
- Bumping an AI car at low speed creates a fender-bender incident (W4 quest).

**Why.** It is deterministic and needs no physics tuning. The same geometry feeds the swept test, the AI already yields to it, and the owner asked for enter/exit/drive, not a racing sim.

**Fallback.** A `VehicleSeat` constraint chassis with client ownership [hospital_police_infection §12].

### D13. Interactions

- Discrete interactions use **ProximityPrompts** with a custom style: doors, stations, shelves, forage sources, knotholes, car doors, consoles, ticket targets. They give keyboard, gamepad and touch support for free.
- `PromptUI` hides prompts not meant for the local role. `Triggered` is re-validated on the server: role, distance, state.
- Continuous verbs (pounce, strike, stalk) use ContextActionService.

### D14. Infection model

- **Per-actor infection** with a derived town % (infected humans / all human bodies).
- The HTML numbers carry over as defaults:
  - the squirrel share matures at 25/7 % per squirrel, capped at 25, gated on own infection ≥ 25 and a bite within 600 s;
  - the hidden critical mass is ≥ 50 % town, plus ≥ half the staff bodies infected, plus ≥ half the patients [hospital_police_infection §6, §11 item 10].
- **Proposed reconciliation of "critical mass wins" with "session resets when everyone is infected"** [brief §8]:
  1. Critical mass silently triggers an *outbreak* phase: infected humans become contagious, with ambience and lighting shifts and no explanatory UI.
  2. When every human is infected, the session resets: town re-seeded, all players become lowest humans, and the rodent player gets a lifetime "the city is yours" stat.
- The infection meter is hidden from the rodent's HUD (decision D-5).

### D15. Session reset and death

- Death of a body plays a short death, removes it after 3 s, and spawns a replacement through `ActorService` to keep species counts (10 to 14 squirrels; 1 rodent after `rodentRespawnDelay`).
- The player's next body comes from the Ladder transition.
- There is no game-over screen and no pause [squirrel_abilities §25 item 4].

### D16. Type safety without a checker in the container

- `--!strict` annotations are written anyway.
- `tests/engine/BootSmoke` `require`s every module in the real engine (catches load errors and typos).
- Selene catches unused or undefined names.
- Lune unit tests cover the pure modules.
- `luau-lsp analyze` runs whenever it can: on the Mac via Rokit, or in the container if a source build is allowed [feasibility A4].

---
## 3. Data schemas

### 3.1 Conventions

- **Positions** are `[x, z]` or `[x, y, z]` in HTML units. `y` is absolute only where the spec gives it absolutely; otherwise `dy` is relative to `Ground.groundAt`.
- **Facing** is one of `+X`, `-X`, `+Z`, `-Z`, or a number (HTML yaw in radians) [worldgen_core §1].
- **Footprints** are `[w, d]` in world axes after rotation [worldgen_core §1].
- **Colours** are hex strings.
- **Times:**
  - game-clock durations are written as `"day"`, `"week"`, `"3h"`;
  - real seconds are plain numbers.
- Every record carries `src` (a spec citation or a v5.4 line) when it was ported, so provenance survives.
- **Importing the seeds.** `tools/import_v54.luau` converts `spec/data/*.json` (243 lots, 116 roads, 25 lanes, 87 cast, wildlife) into these schemas once. New content is added by hand afterwards.

### 3.2 Town lots (`data/town/lots/<district>.lots.json`)

```jsonc
{
  "id": "core_house_0_victorian",          // unique, stable (used by routes, cast, saves)
  "type": "house",                         // key into WorldGen/LotTypes
  "archetype": "victorian",                // variant within the type (8 house archetypes, brief §3)
  "district": "old_town_core",             // key into districts.json (bounds, HUD tag, map label)
  "pos": [-56, -53],                       // lot centre, HTML units
  "facing": "+Z",                          // world axis the front/door faces
  "footprint": [18.04, 15.58],             // w (world X) x d (world Z)
  "grade": "pad",                          // "pad" (flatten terrain under lot) | "follow"
  "flair": {                               // brief §3: no two houses read the same
    "seed": 17, "paint": "#ded7b7", "trim": "#f5ecd5", "roof": "#63524c",
    "porch": "wrap", "roofStyle": "gable_x", "yard": ["garden", "feeder", "shed", "doghouse"]
  },
  "interior": {                            // null for solid buildings
    "kit": "house_2storey_a", "claimable": true, "hideSpots": 3, "backExit": true,
    "defender": null                       // or {"kind": "rolling_pin", "look": "older_woman_a"}
  },
  "residents": ["donna", "frank", "mrs_abbott"],   // cast ids (data/cast/cast.json)
  "forage": [                              // brief §3: "each lot type defines what squirrels can forage there and how risky it is"
    { "kind": "garden_bed", "at": [-36, 52], "yield": [2, 4], "cooldown": "day", "premium": false },
    { "kind": "bird_feeder", "at": [-45, 68], "yield": [3, 5], "cooldown": "week", "premium": true }
  ],
  "risk": { "homeowner": 0.5, "dog": "chained", "cat": "cat_0" },
  "jobs": [],                              // e.g. [{"kind": "restock", "spots": 3, "credits": 15}]
  "traffic": { "parking": ["p_core_0"], "hydrant": [] },
  "routes": "generate",                    // "generate" | "v54" (use reference routes for this lot) | "none"
  "artKit": "house_victorian",             // AssetIds key; missing -> greybox
  "src": "v5.4 L1034 buildHouse(0); lots_core.json"
}
```

**LotType contract** (`WorldGen/LotTypes/<type>.luau`). Every function is pure and returns plan fragments:

| Field | Returns |
|---|---|
| `params` | Schema of allowed `flair`/`interior`/type-specific keys, with defaults. Validated at load. |
| `build(lot, ctx)` | Model fragments: parts, doors (server-owned hinge state), prompts, sockets. |
| `colliders(lot)` | Analytic AABBs, segments and circles for `Town/Colliders`. |
| `routes(lot)` | RouteSpecs: ridges, downspouts, gutters, fence tops, hollow interiors. |
| `nav(lot)` | Interior or room waypoint graph: door → rooms → hide spots → back exit. |
| `prompts(lot)` | Interaction anchors (doors, stations, shelves, forage, jobs). |
| `forage(lot)` / `jobs(lot)` | Defaults merged with the lot's own entries. |
| `skyline(lot)` | 1 to 2 massing parts for the drone Skyline layer (D3). |

**"Adding a barber shop later"** [brief §2], written as the README recipe:
1. Add one entry to `data/town/lots/east_commercial.lots.json`: `type: "shop"`, `archetype: "barber"`, position, facing, `jobs: [{kind: "cut_hair", spots: 2}]`, `forage: [{kind: "trash", ...}]`.
2. Run `lune run tools/validate_data`, which checks overlaps, road access, pole clearance ≥ 0.95 u [worldgen_core §16] and route anchoring.
3. Rebuild.

A new *type* (for example "marina") is one new `LotTypes/marina.luau` that follows the contract.

**Districts** (`districts.json`): `{id, name, hudTag, bounds: [[x0, z0], [x1, z1]] | polygon, mapColor, ambience}`. The HUD-tag precedence follows [worldgen_districts_art §1].

### 3.3 Roads, lanes and traffic control

- **`roads.json`**: the v5.4 schema is kept: `{id, axis: "x"|"z"|"free", coord, start, end, width, kind: asphalt|concrete|path|cobble|rail, offset}` [worldgen_core §1, §4]. A `connects` list per road end feeds the lane graph. The gaps in [worldgen_core §4.3] are closed in W3 (decision D-23).
- **`lanes.json`**: `{id, road, path: {axis, coord, start, end} | {points: [[x, z], …], closed}, dir, speedLimit, users: ["sedan", …], wrap: null | "loop", stops: [{s, kind: "trolley_station", dwell}], src}` [traffic §3; traffic_lanes.json].
- **`traffic_control.json`** (new; required by Addendum A2):

```jsonc
{
  "junctions": [{ "id": "j_core_0_0", "at": [0, 0], "control": "stop4" | "signal" | "none",
                  "stopLines": [{ "lane": "res_main_ns_nb", "s": 245.2 }],
                  "phases": [{ "green": ["res_main_ns_nb", "res_main_ns_sb"], "secs": 18 }] }],
  "speedLimits": [{ "lane": "*residential*", "u_per_s": 9.0 }],   // radar input
  "parking": [{ "id": "p_core_0", "lane": "res_main_ns_nb", "s0": 120, "s1": 128,
                "legal": true, "flags": ["hydrant" | "red_curb" | "driveway" | "time_limit"],
                "limitHours": 2 }],
  "hydrants": [[312, 23], [387, -22]],
  "violationRates": { "speeding": 0.06, "rollingStop": 0.08, "illegalPark": 0.05, "fenderBender_per_hour": 0.5 }
}
```

### 3.4 Routes

**RouteSpec**, one per climbable rail [routes_movement §1.1, §19]:

```jsonc
{
  "id": "r_00412",                         // stable string id (not creation order)
  "name": "BUR OAK bough 3",               // display/debug only; behaviour never depends on names
  "kind": "trunk|branch|bridge|lookout|roof|wire|fence|trampoline|duct|hollow",
  "surface": "tree|pole|pipe|ladder|bark_inner|stone|cable|shingle",   // replaces v5.4 name regexes
  "points": [[-34, 0.4, -33], [-34, 9.2, -33]],   // control points, HTML units, centripetal Catmull-Rom
  "surfaceRadius": 1.18,                    // default 1.35
  "surfaceNormal": null,                    // fixed normal for pipes/downspouts (fixes verifier 2)
  "visualOffset": null,                     // per-route override; kind defaults otherwise
  "speedMult": 1.0,                         // decision D-21 (v5.4 ignores route.speed)
  "flags": { "noAutoGrab": false, "interior": false, "winterBare": false },
  "lotId": "core_tree_bur_oak", "generator": "makeTree.trunk",
  "chambers": null                          // hollow only: [{ "s": 0.35, "id": "H1c1", "radius": 1.4, "exits": ["knothole_east"] }]
}
```

- **`data/routes/v54_reference.json`** holds all 1,332 v5.4 routes as control points, captured headlessly in W0 with the same instrumentation the movement extractor used [routes_movement §0, §20]. Lots marked `"routes": "v54"` use these directly, so the FRB has the complete v5.4 climbing network on day one.
- **Lot-type generators** replace reference routes lot by lot as lots are remodelled (W3). Unit tests compare each generator against the reference for unchanged lots, to a tolerance of 0.01 u.
- **`graph.json`** is generated by `tools/gen_route_graph.luau`: endpoint links, transfer pairs, forks and islands. Regression facts for the reference set: 1,332 routes, about 81,613 index samples, 95 fork trunks, 770 forks, 149 islands, 40 singletons [routes_movement §1, §3, verifier log].
- **New kinds:**
  - `duct`: hospital ducts, an arc-length rail with vent nodes [hospital_police_infection §12].
  - `hollow`: interior pathways; spiral or vertical shaft with `chambers` (§5.5).
  - The fallen log is a ground-level `hollow` with two exits.

### 3.5 Roles ladder (`src/shared/Roles/Ladder.luau`, the only place it is stated)

```lua
--!strict
-- THE ladder. Brief §5, §6, §10, §11; Addendum A1/A2. No other module restates slots, scores or transitions.
local Ladder = {}

Ladder.rungs = {
	human    = { tier = 1, species = "human",    playerSlots = math.huge, label = "Townsperson" },
	hospital = { tier = 2, species = "human",    playerSlots = 5, rankEdge = 1.05, label = "Hospital staff" }, -- "slightly above police"
	police   = { tier = 2, species = "human",    playerSlots = { start = 5, max = 8 }, label = "Police" },
	drone    = { tier = 2, parent = "police",    playerSlots = 1, unlock = "police_at_8_and_drone_upgrade" },
	squirrel = { tier = 3, species = "squirrel", playerSlots = 7, bodies = { min = 10, max = 14 } },
	rodent   = { tier = 4, species = "squirrel", variant = "spicy", playerSlots = 1 },
}
Ladder.sideExits = {   -- chosen *instead of* a promotion; leaving returns to human at previous human rank
	deer = { species = "deer", playerSlots = 4 },            -- "several" (decision D-14)
	fox  = { species = "fox",  playerSlots = 1, hidden = true }, -- Easter egg
}
Ladder.carKeys = 2  -- Addendum A1: the two highest-ranked police players

-- Scores (inputs come from RoleService.stats; weights live in Tunables.roles.*)
function Ladder.score(rung: string, s): number
	if rung == "squirrel" then                -- brief §6: 90% nut count, 10% momentary stink %
		return 0.9 * math.min(1, s.nuts / s.nutRef) + 0.1 * (s.stinkPct / 100)
	end
	-- humans and tier 2: time active on this server, modified by job credits and kicks (brief §6, A2)
	return s.activeMinutes * s.wTime + s.credits * s.wCredit + s.kicks * s.wKick + (s.perf or 0) * s.wPerf
end

-- Transitions: each row is one brief rule. resolve() is pure and returns {player, toRung, rankPolicy}.
Ladder.rules = {
	{ on = "join",                   to = "human",    rank = "lowest" },                         -- §4, §6
	{ on = "leave",                  release = true },                                           -- §4 body returns to AI
	{ on = "rodent.died",            who = "rodent",  to = "human", rank = "lowest" },           -- §6
	{ on = "rodent.killed", by = "human|police",                                                 -- §6
	  who = "killer", to = { "squirrel:lowestUninfectedFreeBody",
	                         "hospital:if town infection > 30%", "police" } },
	{ on = "rodent.killed", by = "hospital", where = "inHospital",
	  who = "killer", to = "squirrel", rank = "lowestUninfected", instant = true },              -- §6, §9
	{ on = "squirrel.infected",      who = "victim",  penalty = "heavy", queueDrop = true },     -- §6
	{ on = "winter.end.belowThreshold", who = "squirrel", to = "human", rank = "lowest" },       -- §6, §12 (D-17)
	{ on = "slot.open", rung = "rodent", take = "topRanked:squirrel", offer = true },           -- §6
	{ on = "slot.open", rung = "squirrel", take = "topRanked:tier2,human", offer = true },       -- D-16
	{ on = "slot.open", rung = "hospital|police", take = "topRanked:human", offer = true },
	{ on = "offer.sideExit",         to = "deer|fox", remember = "humanRank" },                  -- §5, §11
	{ on = "sideExit.leave",         to = "human", rank = "remembered" },                        -- §6
	{ on = "kick.landed",            who = "kicker",  rankDelta = "wKickEvent" },                -- A2
	{ on = "police.performance",     unlock = "police slot +1 (to 8), then drone" },             -- §10
	{ on = "everyoneInfected",       all = true, to = "human", rank = "lowest", reset = true },  -- §8
}

function Ladder.resolve(event, ctx) --> { Transition }
	-- table-driven; exhaustively unit-tested (tests/unit/Ladder.spec.luau)
end
return Ladder
```

**Promotion offers.** When a slot opens, the top-ranked eligible player sees "Become a squirrel?" with **Accept / Deer instead / Fox instead / Stay as I am** and a 15 s timeout. A player can also set "don't offer promotions" (Addendum A2 free roam).

**Lab bypass.** `RoleService.forceRole` uses the same rung table and logs that it exceeded a slot cap. The Lab never edits the ladder.

### 3.6 Tunables (`src/shared/Config/Tunables.luau`)

One nested table. Values are in HTML units and seconds. Each leaf has a comment with its unit and source; `Tunables.studs()` converts.

```lua
return {
	clock = {
		realSecondsPerDay = 72,       -- brief §12: ~50 real min per 6-week winter cycle (42 days); decision D-4
		dayCurve = { night = 0.20, sunrise = 0.10, golden_am = 0.12, day = 0.30, golden_pm = 0.12, sunset = 0.10, blue = 0.06 },
		weeksPerCycle = 6, winterWeek = 6, lunarMonthDays = 29.53,
	},
	squirrel = { -- routes_movement §8, §10; squirrel_abilities §4
		walk = 8.0, sprint = 16.8, stalk = 1.65, railWalk = 7.2, railSprint = 12.2, treeMult = 0.6,
		gravity = 30, leapFwd = 16.5, leapUp = 12.8, accelGround = 23, accelAir = 4.2,
		grabRadius = 3.4, maxTransferGap = 3.15, autoSwitch = 0.48, explicitTransfer = 1.7,
	},
	pounce = { -- squirrel_abilities §6, §25 (wind-up/commit/recovery are new, brief §8)
		cooldown = 0.7, window = 0.78, windup = 0.12, recovery = 0.35,
		speed = { base = 11.3, focus = 12.4, sprint = 13.5 }, contactHuman = 1.38, dyMin = -0.35, dyMax = 2.7,
		chanceUnaware = 0.955, chanceAware = 0.035, awareAlert = 0.45, allowAirPounce = true, -- D-20
	},
	rodent = { maxHealth = 100, kickDamage = 55, batonDamage = 50, shoveDamage = 40, defenderMult = 1.5,
	           regenStalk = 2, regenHollow = 5, invuln = 0.6, respawnDelay = 20 },  -- squirrel_abilities §25.3 (D-6)
	human  = { spotRange = 14.5, spotRangeHot = 20, periphery = 6.8, hearing = 8.6, kickReach = 2.65,
	           kickWindup = 0.58, vigilanteShare = 0.08 },                          -- humans_actors §5.3, §5.5; brief §8
	infection = { ownDecayPerSec = 0.011, squirrelSharePer = 25/7, squirrelShareCap = 25, matureSecs = 1500,
	              criticalTown = 50, criticalStaffFrac = 0.5, criticalPatientFrac = 0.5, killerHospitalIf = 30 },
	hospital = { disinfectSteps = { 1.2, 0.8, 1.2 }, infectedStaffMult = 1.5, fetchTimeout = 45, wrongItemPenalty = 10 },
	police = { batonWindup = 0.5, batonReach = 2.4, carMaxSpeed = 16, radarRange = 48, sightingTTL = 60 },
	drone = { maxAlt = 160, minAlt = 8, speed = 24, markHold = 0.6, markRange = 100, markSecs = 12,
	          markCooldown = 20, vigilanteRadius = 60, deerStartleAlt = 24 },
	traffic = { tickHz = 30, sweptPad = 0.18, yawStep = 0.05, teleportSkip = 12, sedanBox = { 2.35, 4.45, 2.04 } },
	forage = { nutRef = 200, carryMax = 12, ownThreshold = 0.70, capacity = 120, premiumMult = 2,
	           stinkFillPerMin = 1.2, stinkFireMin = 95, stinkCost = 30, stinkRepelRadius = 8, stinkRepelSecs = 4 },
	roles = { wTime = 1.0, wCredit = 0.05, wKick = 15, wKickEvent = 25, wPerf = 1.0, offerTimeout = 15 },
	ai = { thinkHz = { near = 10, mid = 4, far = 1 }, lodNear = 60, lodMid = 200, budgetMs = 4 },  -- u
}
```

**Live tuning.** In Studio and for dev UserIds, `TunablesService` mirrors every leaf into `ReplicatedStorage.TunablesLive` as NumberValues. The owner can change a value in the Properties panel *during* a playtest and the server picks it up. The Lab button **Export tuning** prints a short diff that the owner pastes back to Claude, who commits it.

### 3.7 Other data files (brief shapes)

| File | Record shape |
|---|---|
| `cast/cast.json` | `{id, name, role, homeLot?, personality: wary\|panic\|brave\|bluster, nerve 0..1, look: {body, skinTone, outfit, accessory}, schedule?, src}` from human_cast.json (87) [humans_actors §1–§3] |
| `Actors/Species` (code) | `{species, bodyKind: "R15"\|"rig", motor, brains, hitbox: {r, h}, sockets: {HeadSocket, MouthSocket, TailTip, Seat}, stockLooks}` |
| `forage/forage_types.json` | `{kind, yield: [min, max], cooldown, carry, winterMult, risk: {trigger, radius, effect}}` [wildlife_foraging §14] |
| `wildlife/wildlife.json` | the spec file, re-keyed: hollows H1–H11 plus the log, nut caches, deer herd, fox spawn, trees (95), apple trees, nests, birds, insects |
| `hospital/items.json` | `{id, name, kind: medicine\|instrument, color, icon, shelf: "pharmacy_A3", requestWeight}` (about 8 medicines and 6 instruments) |
| `quests/quest_types.json` | `{type, roles: ["police"], source: "traffic.illegalPark"\|"community.argument"\|..., steps: [{verb, target, within}], rewardCredits, rankDelta, ttl, maxConcurrent}` |
| `Config/AssetIds.luau` | `{ ["rig.squirrel"] = 0, ["anim.squirrel.Run"] = 0, ["kit.house_victorian"] = 0, ... }` (0 means placeholder) |

---
## 4. Order of operations

### 4.1 Shape of the plan

- **One pass, eight waves (W0 to W7).** Each wave ends with an exit criterion. From W2 onward, each wave also ends with an owner build.
- **No walkable-town milestone.** W1 builds the spine *role-shaped*, meaning every spine piece is exercised by at least one role's motor or brain in headless tests. W1 produces **no owner build**. The first thing the owner plays is the FRB at the end of W2, and it has all eight roles [brief preamble].
- **Two tracks**, matching the limit of 2 concurrent subagents and the 4-CPU container:
  - Track A: gameplay code.
  - Track B: data, tools, traffic and, from W1 on, Blender art.
  - Blender exports and test runs go in the background so the two tracks do not starve each other.
- **Ephemeral container.** Work is pushed to `spicy-rodents-roblox` at least at every task boundary. Build outputs are reproducible from git. The tag of each owner build is recorded against its place version in `CHANGELOG.md`.
- **Regression rule.** From the FRB on, every owner build must still pass the FRB role checklists (§4.4) before new checks are added.
- **Decision gates with the owner:**
  - **G0** after W0: spike results; architecture confirmed or switched to fallbacks.
  - **G1** after the FRB: which depth comes first.
  - **G2** before W5 art lands: turntable approval for the squirrel and rodent.

Sizes are relative effort (S, M, L, XL), given to help the order-of-operations discussion. They are not calendar promises.

### 4.2 Waves

#### W0. Ground truth and spikes (size M)

**What gets built.**
1. **Repo and toolchain.**
   - Create the private repo `spicy-rodents-roblox` (the owner's website repo is never touched). Add `rokit.toml`, the StyLua config with the Luau feature, Selene with the committed `roblox.yml` [feasibility A], Git LFS for binaries, and the Lune test harness.
   - `tools/ci.sh` runs `stylua --check`, `selene`, `lune run tests`, `lune run tools/validate_data` and `rojo build`.
2. **Open Cloud tooling** (Lune `@lune/net`):
   - `cloud/save_place` saves a version to the CI place or the Dev place [feasibility B.d];
   - `cloud/run_engine_tests` creates a Luau Execution task, polls it, and parses the JSON report and logs;
   - `cloud/upload_asset` uploads Image, Model or Animation and polls the operation;
   - rate-limit aware (Luau Execution: 5 creates per minute and 10 incomplete per place; Assets: 120 per minute).
3. **Reference capture.**
   - Re-run v5.4 headlessly with the instrumentation from [routes_movement §0]. Emit `v54_reference.json`: all 1,332 routes as control points with kind, radius and visualOffset; the 95 trees; forks.
   - Emit **golden vectors** by calling the original JS functions on fixed and random inputs: `baseTerrainHeight`, `terrainHeight`, THREE r160 centripetal Catmull-Rom `getPointAt` and `getSpacedPoints`, `RouteMotion.advance`, `sweptVehicleHit` and `segmentBoxEntry`, `pounceVelocity`, and the `spotted` predicate. These become `tests/golden/*.json`.
4. **Data import.** `tools/import_v54` converts the seven spec data files into the §3 schemas. `tools/validate_data` checks overlaps, road access, pole clearance, unique ids and cast home lots.
5. **Spikes**, each recorded in `docs/spikes.md` as pass/fail with numbers and the path chosen:

| Spike | Question | Pass looks like | If it fails |
|---|---|---|---|
| S1 Cloud test loop | Can we save a place version and run a Luau Execution task that `require`s our modules and returns JSON? | report returned in under 2 min | GitHub Actions runner with the key as a secret; or engine tests only in owner playtests |
| S2 Terrain timing | How long does a full-map `WriteVoxels` heightfield take? | under 20 s for 4.3 × 2.5 km at 4-st voxels | Studio "Bake Terrain" button (D4) |
| S3 Headless animation | Blender → JSON → Lune KeyframeSequence → Open Cloud Animation → `GetKeyframeSequenceAsync` | the clip loads and has the expected poses | owner Animation Editor imports (D6 path B) |
| S4 Headless models | Does a textured FBX uploaded through Open Cloud `LoadAsset` with SurfaceAppearance or TextureID intact? | MeshParts with textures | owner imports kits in batches; Studio art bake |
| S5 Avatar APIs | Do `GetHumanoidDescriptionFromUserId` and `CreateHumanoidModelFromDescription` work in Luau Execution? | traits for 3 public UserIds | verify in S6 or the FRB instead |
| S6 Possession | A 2-client Studio test: possess a walking anchored NPC mid-stride, release on leave, swap bodies, animation replicates, camera on a non-Humanoid body | owner ticks 6 boxes | D1 fallbacks (Server Authority, then server-authoritative positions) |
| S7 Move cost | `BulkMoveTo` of 120 anchored rigs per frame | under 1 ms | lower the Mid and Far motor rates; state-stream rendering |

**Owner steps.**
- O1 (web, about 15 min): create the experience and places, and give the API key to the container (§4.5).
- O2 (Studio, about 10 min): run the S6 check.

**Exit criterion.**
- CI is green on the skeleton.
- S1 passes.
- Every spike has a recorded result and a chosen path.
- Gate G0 is held.

#### W1. The spine, role-shaped (size L; headless; no owner build)

**Track A.**
1. `Config` (Units, Tunables, Flags, AssetIds), `Net`, `Clock`, `Util`.
2. `Terrain/Height` and `Terrain/Ground` (golden-tested), `TownData`, `Colliders`.
3. `WorldGen`:
   - `Plan`;
   - **greybox LotTypes for every type in the imported data** (generic massing with real doors, roofs, colliders, prompts and Skyline parts);
   - Lune bake to `Town.rbxm`;
   - `TerrainBake` at boot.
4. `Routes`: `Curve` (golden-tested), `Registry` (reference import), `SpatialIndex`, `Graph` (regression counts), `Motion`.
5. `Actors`: `Species`, `BodyFactory`, `ActorService`, `Possession`, `BrainScheduler` with LOD, plus **minimal brains for every species**:
   - pedestrians walk lanes;
   - staff walk hospital circuits;
   - officers patrol;
   - squirrels run routes and the ground;
   - the rodent wanders and stalks;
   - the fox roams;
   - deer graze.
6. `Roles/Ladder` (full table, exhaustive unit tests), `RoleService` (join, leave, `forceRole`), Role Lab ("Become X").
7. **All five motors and controllers with cameras** (human, squirrel, quadruped, car, drone) and `AnimationDriver` (stock R15 plus procedural animals).

**Track B.**
8. `Traffic`:
   - lanes import with handedness unified;
   - AI `CarMotor` and `LaneMath`;
   - yielding;
   - stop-sign control at the existing sites;
   - `Swept` (golden-tested), `SweptCollision`, teleport flags;
   - placeholder vehicles.
9. `tools/gen_placeholders`: R15 humans from stock HumanoidDescriptions (role colour palettes [hospital_police_infection §5.1, §8.2]); squirrel, fox, deer, drone and car rigs built from parts with the **final socket and bone names** (§5.2).
10. `Map/MapModel` and the minimap.
11. `Avatar/BlendRules` and the service, with the dev samples.
12. Blender: squirrel base mesh and rig v0 (art track starts; §5).

**Owner steps.** None.

**Exit criterion** (all headless):
- **Luau Execution `BootSmoke`:** every module loads in the engine.
- **`WorldBuild`:**
  - lot count equals the data;
  - no two solid lots overlap;
  - every door reachable from a sidewalk on the nav graph;
  - every route's samples lie within `surfaceRadius + 0.3 u` of geometry or terrain;
  - Skyline exists for every building.
- **`Sim10`:** 10 simulated minutes with 50 humans, 10 squirrels, a rodent, a fox, 4 deer and about 20 vehicles. Every actor moved, no NaN, nobody outside the world clamp, every vehicle moved in every 60 s window (no deadlock), and AI under 4 ms per frame on average.
- **Lune:** all unit and golden tests green.

#### W2. Role loops: FIRST RUNNABLE BUILD (size L; owner build #1)

**Track A.**
1. `Combat`:
   - pounce with wind-up, commit and recovery;
   - v5.4 contact and bite chance;
   - kick, baton and shove with wind-ups and telegraphs;
   - rodent health, regen, death and replacement.
2. `Infection`:
   - per-actor infection and the red-eye tell;
   - infected AI walk to the hospital;
   - squirrel share;
   - hidden critical mass, logged only (visible in the Lab).
3. `Hospital` core:
   - greybox rooms from the brief layout [worldgen_districts_art §2.6];
   - stations with the 3-step disinfect loop;
   - fetch tasks with 6 items on pharmacy shelves;
   - staff shove;
   - infected staff × 1.5;
   - performance number.
4. `Police` core:
   - baton;
   - sightings on the map;
   - top-2 car keys;
   - `PlayerCars` (enter, exit, drive, siren and lights);
   - radar;
   - quest types **parking ticket** and **speeding ticket** through `QuestService`.
5. `Drone` core:
   - launch and dock at the station console;
   - flight;
   - feed HUD;
   - spot-and-mark;
   - vigilante summon (8 % flag on AI humans, approach only);
   - deer startle source.
6. Every ladder rule in §3.5 wired through `RoleService`, plus `OfferUI`. Slot expansion 5→8 exists in the Ladder and is reachable from the Lab.

**Track B.**
7. `Foraging` core:
   - sources from data (v4.1 caches, trash cans, garden plots, feeders);
   - carrying;
   - **11 hollows** with knothole entry and a single-chamber placeholder interior each (premium interiors arrive in W3);
   - meter and 70 % ownership;
   - stink gland.
8. `Wildlife` verbs: fox lunge against squirrels, rodent immunity, stink repel; deer graze and bolt; AI startle from vehicles and the drone.
9. `Jobs`: a restock job at 3 shops, paying credits. `Homes`: claim at the 4 core houses with greybox interiors.
10. `Seasons` basic:
    - clock and calendar HUD;
    - day and night lighting from the 4 HTML presets plus night;
    - winter toggle (forage × 0.3, cold grade);
    - winter-end survival check.
11. `Hud` per role, `Notifications`, the full Role Lab, and `docs/playtest/FRB.md`.

**Owner steps.** O3: the FRB playtest (§4.4), about 60 to 90 minutes, reported through the checklist.

**Exit criterion.**
- All eight role checklists and the multi-client checklist pass. Any failure is logged and fixed first thing in W3.
- `Sim10` is green with the new systems active: the AI rodent lands at least one bite, the hospital cures at least one patient, at least one parking violation spawns, and radar speeds are non-zero.
- Gate G1 is held.

#### W3. Town completeness (size XL, mostly data and LotTypes; runs alongside W4 where independent)

**What gets built.**
1. **Roads.** Connect the road network [worldgen_core §4.3]. Add traffic control everywhere: stop signs at grid junctions, signals on the boulevard, hydrants, red curbs, legal and illegal parking [traffic §12].
2. **Expansion lots** [brief §3]:
   - restaurants about doubled (diner, pizza, taco, Chinese, café, bakery, ice cream, bar and grill), each with seating or a dumpster;
   - barber, music, hardware, laundromat, bookshop, pet store, corner grocery;
   - school with playground, church, marina;
   - Quay facades promoted to enterable restaurants and shops [worldgen_districts_art §15].
3. **Houses.** 8 house archetypes with per-lot flair. **40 interiors** with kits, nav graphs, hide spots, back exits and server-owned doors. Claimable homes with remodel options. **3 defender houses.**
4. **Hollow trees.** H1 spiral-ramp premium, H2 shaft premium, 9 knothole chambers, and the fallen-log tunnel (§5.5).
5. **Routes.** Lot-type route generators for every lot (ridges, downspouts, gutters, fences, hollows), checked against the reference wherever a lot is unchanged.
6. **Hospital, full building:**
   - Ward A and Ward B, isolation, pharmacy, staff room, ambulance bay;
   - a roof route and roof hatch;
   - ducts as `duct` routes, with vents and chewing;
   - the overhead hatch moved over an aisle, fixing the v5.4 soft-lock [hospital_police_infection verifier 1].
7. **Police station interior:** spawn, lockers, upgrade board, drone console, car pads.
8. **Other districts:** sewer and stand (if kept, D-12); Galleria camera constraints [worldgen_districts_art §16].

**Owner steps.**
- Review the **town plan page**, an artifact Claude publishes with proposed placements, the 40 interiors, the defender houses and the hollow picks. This happens on the web, not in Studio.
- O3 playtest of build #2: indoor chase and district walk checks.

**Exit criterion.**
- Validators are green.
- `WorldBuild` passes for all 40 interiors: an AI human can path from the door to every hide spot and to the back exit.
- The route graph has no orphan downspouts.
- The owner's build #2 checks pass.

#### W4. Systems depth (size XL)

**What gets built.**
1. **Duel, full** [brief §8; squirrel_abilities §25]:
   - wind-up, commit and recovery tuned;
   - feint with stamina;
   - zig-zag detection (lateral reversals per second give a miss bonus and a speed penalty);
   - human responses (flinch, swing, kick, back away, flee) chosen by awareness and nerve;
   - vigilantes never flee;
   - indoor pounce, bite and kick;
   - defenders with rolling pins and a broom at × 1.5.
2. **Police quests and AI:**
   - burglar (a `Burglar` brain that uses interiors);
   - petty argument (pairs of pedestrians; 3-choice mediation);
   - fender bender: AI human bodies *operate* vehicles and step out, which is the same possession idea applied to AI drivers [traffic §14 Q6];
   - stop-sign running and the full speeding pull-over;
   - parking variants;
   - AI police dispatch backfill and the officer ladder 5→8 (more aggressive and coordinated tiers from the HTML values [hospital_police_infection §11 item 14]);
   - the drone unlock path.
3. **Ambulances and responder flow** into the ambulance bay [hospital_police_infection §7].
4. **Hospital progression:** performance raises staff rank and unlocks station upgrades; the full fetch catalogue.
5. **Homes:** remodel points per real day.
6. **Full foraging:**
   - gardens, feeders with bird and homeowner risk, trash, dumpsters, apples, acorns, mall plaza;
   - premium weekly raids;
   - theft rules.
7. **Winter, full:** snow terrain swapped in chunks, bare trees, survival rule.
8. **Ambient life:** birds, nests, insects and a world-relative overflight.
9. **Speech and flavour:**
   - speech bubbles (BillboardGui, curated lines, profanity removed);
   - wanted posters as a sighting source;
   - cats, dogs and rabbits (D-22).

**Owner steps.** O3 playtest of build #3 (scenario checklists per system).

**Exit criterion.** The per-system engine simulations are green, and the build #3 checks pass.

#### W5. Art integration (Track B has produced art since W1; W5 is where it lands. Size XL)

**What gets built.** Assets land in the order of §5.3:
1. squirrel and rodent;
2. human bodies, outfits, props and verb clips;
3. fox and deer;
4. vehicles and the drone;
5. trees and hollow interiors;
6. house and interior kits;
7. civic, commercial, hospital and police kits;
8. Quay and Galleria kits;
9. street furniture.

**Owner steps.**
- O4: Art Inbox imports of skinned rigs (about 10, each about 3 minutes; §4.5) and pasting the IDs.
- Gate G2 turntable reviews.

**Exit criterion.**
- The engine test `Assets` is green: every ID loads, the contracts hold (bone and socket names, triangle budgets), and every clip loads.
- Zero placeholders remain for priorities P0 to P3.
- Owner build #4.

#### W6. World presentation (size L)

**What gets built.**
1. **Backdrop** [worldgen_districts_art §14.4]:
   - three bands of hills and mountains, a tree line and a distant road with impostor cars;
   - an ocean to the horizon, a beach, a pier and the marina;
   - the radio tower on the measured sunset azimuth with blinking obstruction lights.
2. **Lighting state machine** [worldgen_districts_art §14.3]: sunrise and sunset moments, blue hour, night and stars.
3. **Moon phases:** `MoonTextureId` swap first, custom client moon as the fallback [feasibility B.f].
4. Clouds, winter grade, audio and ambience, signage, interior lighting.

**Owner steps.** One Studio check: Lab → "Set time 18:40" → is the tower silhouetted from the ground and from the drone?

**Exit criterion.**
- At 300 st with the default FOV there is no horizon seam.
- Owner build #5.

#### W7. Scale, hardening, publish (size L)

**What gets built.**
1. Movement validation enforced; swept-collision lag compensation; combat rewind.
2. A performance pass at 50 players: a Studio 8-client test plus a live private-server session.
3. Mobile and gamepad bindings.
4. Persistence: cosmetics, settings, lifetime stats.
5. The README [brief §14] and tidied Blender deliverables.
6. The "Bake Town" Studio plugin with SLIM.
7. Game settings: max players 50, server fill, the maturity questionnaire.
8. Publish.

**Owner steps.** O5: the final publish, click by click; then a live session.

**Exit criterion.** A tagged release candidate; every regression checklist green; budgets met (server AI under 4 ms per frame; no client under 30 fps on the owner's Mac at 8 clients).

### 4.3 What the FIRST RUNNABLE BUILD contains (tag `frb-1`)

**World**
- The whole v5.4 town footprint as data-driven greybox: 243 imported lot records, 116 road records, and terrain over the full playable rectangle (about 4,350 × 2,520 st).
- The complete v5.4 climbing network (1,332 routes) on real greybox trees, poles, wires and roofs.
- 4 greybox enterable houses (the HTML core houses) with doors, rooms and hide spots.
- The hospital greybox with all 8 brief rooms.
- The police station greybox with car pads and the drone console.
- 11 hollows, each with a knothole and a single-chamber placeholder.
- Skyline impostors for the drone view; Roblox default sky, a day/night cycle, and the in-game calendar.

**Bodies**

| Body | Count |
|---|---|
| AI humans | about 50: 22 townspeople, 6 shop workers, 8 hospital staff, 6 patients, 8 officers |
| Squirrels | 10 |
| Spicy rodent | 1 |
| Fox | 1 |
| Deer | 4 |
| Patrol cars | 2 (player-drivable) |
| AI vehicles | about 20, including the AI patrol car, the ice cream van, the trolley and heavy vehicles |
| Drone | 1 |

Every body is possessable mid-stride, and every unheld slot is AI.

**Systems**
- Possession: join takes over a walking townsperson; leave hands the body back to AI.
- The full Ladder with offers and side exits.
- Role Lab.
- Combat core, per-actor infection, hospital disinfect and fetch, police baton, car, radar, parking and speeding quests.
- Drone flight with spot-and-mark.
- Foraging, hollows and the stink gland.
- Fox and deer verbs.
- Shop job, credits, home claim.
- Server swept run-over for every squirrel actor.
- Sightings and the map.
- The 70/30 avatar blend on placeholders.
- Live Tunables.

**Art**
- Placeholders only: R15 humans in role colour palettes, part-built animals with procedural gaits, part-built cars and drone.
- No authored clips yet; R15 stock locomotion for humans.

**Explicitly not in the FRB** (and in which wave it lands):

| Item | Wave |
|---|---|
| Expansion lots, 8 house archetypes, 40 interiors, defenders, premium hollow interiors, full hospital and station, sewer and ducts | W3 |
| Feint and zig-zag, burglar, argument, fender bender, stop-sign running, ambulances, police 5→8 progression, remodels, full forage risks, full winter visuals, ambient life, speech | W4 |
| All authored art and clips | W5 |
| Backdrop, moon phases, audio | W6 |
| Enforcement, lag compensation, persistence, mobile, SLIM | W7 |

### 4.4 Per-role thinnest loop and FRB acceptance checks

**Setup, once per session.** Open Studio → the Dev place → **Test** tab → in **Clients and Servers**, choose "1 Player" → **Start**. A **LAB** button appears at the top left of the game window. Each role below starts with **LAB → Become \<role\>**, which bypasses the ladder for testing. The ladder itself is tested in R6, S5, P3, F5, E3 and M3–M7.

| Role | Thinnest complete loop in the FRB | Deepened in |
|---|---|---|
| Townsperson | walk the town → work a shop job → credits → rank rises; kick the rodent; get bitten → infected → walk to hospital; claim a home | W3 (40 homes, interiors), W4 (remodels, swing, back away, flee, vigilante behaviour) |
| Hospital staff | infected patient arrives → disinfect at a station → credits and performance; fetch the right item fast; shove-kill the rodent inside → becomes squirrel | W3 (full building, ducts), W4 (ambulances, upgrades, catalogue) |
| Police | sighting appears on the map → go on foot or by car → baton the rodent; radar a speeder → pull over → ticket; parking ticket | W4 (argument, fender bender, stop sign, burglar, 5→8) |
| Drone | launch from the console → fly the town → find the rodent → mark it → officers see it, vigilantes converge | W6 (backdrop and night), W7 (SLIM) |
| Squirrel | run and climb the full network → forage → deposit in a knothole → meter → own the tree; stink repels; rank = 90/10; get infected → penalty | W3 (premium hollows), W4 (risk, raids, winter) |
| Spicy rodent | stalk → pounce (wind-up, commit, recovery) → bite → infection spreads; kicks hurt; run over or killed → becomes townsperson | W4 (feint, zig-zag, defenders, indoor) |
| Fox | roam → lunge at squirrels on the ground → they drop nuts; immune rodent; stink repels; leave → previous human rank | W5 art |
| Deer | wander, graze, bolt and leap; AI deer startle from cars and the drone; leave → previous human rank | W5 art |

**Checklists.** These are the FRB acceptance checks. Each line is: action → expected result. They also live in `docs/playtest/FRB.md`, which will be delivered as a shareable checkbox page.

**Townsperson (H)**
- **H1.** Join (no Lab) → you are already walking on a sidewalk as a townsperson; you did not drop from the sky. The HUD shows "TOWNSPERSON · Rank n of m".
- **H2.** WASD, Shift and Space → walk, run and jump; the camera follows.
- **H3.** Open the map (M) → your arrow moves; district names show; a "JOB" marker sits on the corner shops.
- **H4.** At the job, press E at each of the 3 glowing shelves → "+15 credits" each; within 10 s your rank number improves.
- **H5.** E at a house door marked "AVAILABLE" → "This is your home"; a house icon appears on the map.
- **H6.** LAB → "Spawn rodent near me". As it closes in, a "kick" telegraph shows; click LMB → kick animation. On a hit: "KICK! +rank" and the rodent's health bar drops.
- **H7.** Let it bite you → "INFECTED". Another client sees your eyes glow red. A marker points to the hospital. Walk in and get cured by staff (AI or a player).
- **H8.** Nearby AI townspeople flee from the rodent; some run into one of the 4 houses and the door closes behind them.

**Hospital staff (S)**
- **S1.** LAB → Become Hospital Staff → you are a nurse at reception; the HUD shows "HOSPITAL".
- **S2.** Visit reception, triage, Ward A, Ward B, isolation, pharmacy, staff room and ambulance bay. Each name shows on the minimap as you enter.
- **S3.** LAB → "Send infected patient" → a red-eyed patient walks in to a bed with a marker. E at the bed station → 3 steps (hold E; press E when the ring is green; hold E) → "CURED +credits"; the eyes return to normal; the hospital performance number changes.
- **S4.** A toast says "Bay 3 needs SALINE (blue)" with a 45 s timer. Go to the pharmacy, E on the blue bin (the item shows in your hand), E at Bay 3 → "Correct". Repeat with the wrong bin → "Wrong item −10 s".
- **S5.** LAB → "Spawn rodent in hospital" → shove it with LMB until it dies → you instantly become a squirrel.
- **S6.** LAB → "Infect me" → the disinfect steps now take visibly longer (× 1.5).

**Police (P)**
- **P1.** LAB → Become Police → you are an officer at the station.
- **P2.** LAB → "Spawn rodent" near some townspeople → within seconds a red sighting marker appears on your map; it fades after about a minute.
- **P3.** Reach the rodent; LMB → baton wind-up, then strike. Two hits kill it → you are promoted (to squirrel if a body is free).
- **P4.** As the only officer you are top-2 and hold car keys. E at the cruiser → you sit in it. W/S/A/D drive; H toggles siren and lights (another client sees and hears them); E exits; the car stays where you left it.
- **P5.** While driving, the radar panel lists the car ahead with its speed and the limit; a speeder shows red.
- **P6.** A "Parking violation" marker appears (or LAB → "Spawn parking violation") → walk to the car at the hydrant → E "Write ticket" → credits.
- **P7.** Follow a red radar target and press H behind it → it pulls over → E at its window → ticket and credits.
- **P8.** LAB → "Spawn rodent on road", then drive over it → "RUN OVER" and you get the kill credit.

**Drone (DR)**
- **DR1.** LAB → Become Drone → the camera lifts from the station console; the HUD shows "DRONE FEED" with altitude, heading and zoom.
- **DR2.** WASD move, E/Q climb and descend, mouse look, wheel zoom. The ceiling is 400 st. From altitude the whole town is visible; distant blocks are simple shapes.
- **DR3.** Find the rodent and hold LMB on it about 0.6 s → "MARKED". An officer client sees an outline on it and a map marker for 12 s; nearby AI vigilantes run toward it.
- **DR4.** Fly low over the deer → they bolt.
- **DR5.** F → the drone flies home and docks; you are back in your officer body at the console.

**Squirrel (Q)**
- **Q1.** LAB → Become Squirrel → you take over a running AI squirrel without it stopping.
- **Q2.** Run and sprint, Space leap. Walk into a trunk to climb; A/D picks a branch at forks; walk a wire between poles; Q drops you off.
- **Q3.** E at a trash can or garden bed (map markers) → "+3 nuts (carried)".
- **Q4.** Climb to a knothole (map marker), E → inside view; E "Store" → the meter rises; at 70 % or more → "This tree is yours".
- **Q5.** LAB → "Fill stink 95 %" → press R → a puff cloud; a nearby human and the fox recoil; the meter drops by 30.
- **Q6.** The HUD shows your squirrel rank (90 % nuts + 10 % stink) and your place in the rodent queue.
- **Q7.** LAB → "Spawn fox" → it hunts you on the ground; climbing makes you safe.
- **Q8.** LAB → "Rodent bites me" → "INFECTED: lost nuts, dropped in queue".

**Spicy rodent (R)**
- **R1.** LAB → Become Spicy Rodent → zombie-squirrel placeholder with red eyes; all squirrel movement works.
- **R2.** Hold RMB → first-person stalk, slow and quiet, with an aim arc.
- **R3.** LMB → short crouch (wind-up) → lunge → brief stagger (recovery). Hit an unaware townsperson from behind → "BITE"; their eyes turn red and they flee; a police client gets a sighting.
- **R4.** Pounce at someone already looking at you → usually "Batted away".
- **R5.** LAB → "Make a vigilante kick me" twice quickly → after the second kick you die and become a townsperson at the lowest rank; a new AI rodent appears about 20 s later.
- **R6.** Stand on a road as a car comes → "RUN OVER" → you become a townsperson.
- **R7.** Rest inside a knothole or stalk → the health bar slowly refills.

**Fox (F)**
- **F1.** LAB → Become Fox → WASD, Shift run, Space jump.
- **F2.** LMB lunge at a squirrel on the ground → it is knocked back and drops nuts.
- **F3.** Lunge at the rodent → nothing happens ("Not that one").
- **F4.** A squirrel's stink makes you recoil and back off for about 4 s.
- **F5.** LAB → "Leave side role" → you are a townsperson at your previous rank.

**Deer (E)**
- **E1.** LAB → Become Deer → walk, Shift bolt, Space leap, G graze.
- **E2.** AI deer startle when a car passes close or the drone flies low.
- **E3.** Leave → you return to your previous human rank.

**Multi-client.** **Test** → **Clients and Servers** → "3 Players" → **Start**. Three game windows open.
- **M1.** Watch a walking townsperson in Player 1's window while Player 2 joins → Player 2 takes over a walking body mid-stride; nobody pops in.
- **M2.** Close Player 2's window → that body keeps walking as AI.
- **M3.** Player 1 is the rodent, Player 2 is police → Player 2 sees sightings when AI spot Player 1; they fight with baton against pounce; the death transitions apply to both.
- **M4.** Player 3 is the drone and marks Player 1 → Player 2 sees the outline.
- **M5.** Player 2 drives over Player 1 → run-over death with credit to Player 2.
- **M6.** Avatar blend: LAB → "Blend sample: Neon" on Player 1's squirrel → stock squirrel with a neon tail tip only. "Giant bundle" → silhouette unchanged.
- **M7.** Player 1 is the top squirrel; LAB → "Kill rodent" → Player 1 sees the offer → Accept → Player 1's squirrel walks on as AI and Player 1 is now the rodent.

### 4.5 Owner steps, click by click (all of them, across the whole build)

**O1. One-time setup (web browser, about 15 min, W0).**
1. Go to create.roblox.com → **Creations** → **Create Experience**. Name it "Spicy Rodents (Dev)" and keep it private. Owner decision D-1 decides whether it is created under your user or a group.
2. Open the experience → **Places** → **Add Place**, named "CI".
3. **Open Cloud → API Keys → Create API Key**. Add the "assets" (read and write), "universe-places" (write) and "luau-execution-sessions" (read and write) permissions for *this experience only*. Copy the key.
4. Give the key to the build environment through its secret setting. Never paste it into chat.
5. Send Claude the universe ID and the two place IDs, which are shown on the experience page.

**O2. Possession spike check (Studio, about 10 min, end of W0).** Open the place from the Studio start page → Test → Clients and Servers, 2 Players → Start → tick the 6 boxes in `docs/spikes.md` S6.

**O3. Playtests (Studio, each owner build, 45 to 90 min).**
1. Close any open copy of the place first.
2. Start page → "Spicy Rodents (Dev)" → it opens the newest version.
3. Run the checklist for that build.
4. To change a number while playing: in the Server window, open the Explorer → ReplicatedStorage → TunablesLive → click the value → type a new number in Properties. Afterwards, LAB → "Export tuning" → copy the text to Claude.

**O4. Art imports (Studio, W5, about 3 min per skinned rig, about 10 rigs).**
1. Open the "Art Inbox" place, which is any baseplate and *never* the Dev place.
2. **File → Import 3D** → pick the FBX Claude names → **Rig Type: Custom** (animals) or **R15** (humans) → **Import**.
3. Right-click the new model → **Save to Roblox** → creator = the same owner as the experience → **Submit**.
4. Copy the asset ID from the confirmation and send it to Claude.

If spike S3 failed, clips are imported here too: Avatar tab → Animation Editor → select the rig → "..." → Import → From FBX Animation → Publish.

**O5. Final publish (Studio, about 15 min, W7).**
1. Open the Dev place → **Plugins → Spicy Tools → Bake Town** (writes art and terrain into the place) → **File → Publish to Roblox**.
2. **Game Settings:** max players 50; Places → server fill "Maximum" (D-18); answer the maturity questionnaire (D-11); set the experience to public when ready.

### 4.6 Knobs the owner can turn on the order

1. **Art earlier.** Move the squirrel and rodent import (W5 item 1) to right after the FRB so playtests feel like the game sooner. It costs about one Track B cycle and nothing on Track A. Recommended if motivation matters.
2. **W3 and W4 interleave.** The default runs them in parallel by subsystem (Track A on W4 systems, Track B on W3 data). Alternative: finish W3 first so W4 quests have all their houses and stop signs.
3. **Backdrop before art.** Swap W6 and W5 if the drone role is the showcase you want to demo first; the backdrop is mostly independent of character art.
4. **Hardening earlier.** Pull W7 movement enforcement into W4 if you plan public tests before release.

---
## 5. Asset plan

### 5.1 Pipeline

```
blender/<asset>/build.py (bpy 5.2.3, headless)  ->  <asset>.blend (LFS)
   -> blender/validate.py   (tris <= budget/mesh and <= 20k, <= 4 influences/vertex, root at origin with no weights,
                             frozen transforms, bone + socket names == contract, clip starts at frame 0, scene named after clip)
   -> exports:  <asset>_rig.fbx (no animation)  +  <asset>_<Clip>.fbx (one clip per file)  +  <asset>_<Clip>.json (bone TRS per frame)
   -> review:   turntable + clip contact-sheet renders (EEVEE/Cycles headless; to verify in W1) -> owner gate G2
   -> Roblox:   rigid kits:   Open Cloud Model upload (Claude)                      -> AssetIds
                skinned rigs: owner Art Inbox import + Save to Roblox (O4)          -> AssetIds
                clips:        Lune KeyframeSequence + Open Cloud Animation (S3) or O4 -> AssetIds
                images:       Open Cloud Image upload (moon phases, clothing, decals, UI)
   -> runtime:  BodyFactory / WorldBoot.kitSwap load by ID; placeholder if ID is 0
```

**FBX settings** [feasibility A5]: Unit System None, FBX Unit Scale, Z forward and Y up, Leaf Bones off, Bake Animation on (clips only), NLA, All Actions and Force Start/End off, Simplify 0, Embed Textures on with Path Mode Copy, one animation track per file.

### 5.2 Contracts and placeholders

Every rig and kit has a **contract** in `Actors/Species` or the kit registry: bone or joint names, socket Attachments, root and pivot, facing −Z (D11), and the logical hitbox. Gameplay reads only the contract, so placeholders and art are interchangeable.

| Body | Contract essentials |
|---|---|
| Squirrel / rodent | `Root` (non-deform, origin); Hips, Spine1–3, Chest, Neck, Head, Jaw, EarL/R, Tail1–8, four legs × (Upper, Lower, Foot, Toe). Sockets `HeadSocket`, `MouthSocket`, `TailTip`, `ChestCenter`. Hitbox radius 0.32 u, re-tuned for the 1.2-st shoulder (D-26) [routes_movement §20]. |
| Human | Standard R15 (15 parts), plus sockets `RightGripAttachment`/`LeftGripAttachment` for props and `BadgeAttachment`. |
| Fox / deer | As squirrel, with Tail1–6 (fox), Tail1–2, Neck1–3 and an optional `Antlers` part (deer). Fawn is `Model:ScaleTo(0.55)` [wildlife_foraging §11.8]. |
| Vehicles | Body plus 4 wheel parts; `DriverSeat`, `LightBar`, `Headlights`, `TailLights` attachments. Logical box as in [traffic §1] (sedan 2.35 × 4.45 × 2.04 u). |
| Drone | Body, `Rotor1`–`Rotor4`, `Camera` attachment. |
| Building kits | Pivot at lot centre on the ground; door hinge attachments; `RoofLanding` parts; `Skyline` LOD part. |

**Placeholders** are generated by `tools/gen_placeholders.luau`:
- Humans: Roblox default R15 bodies from stock HumanoidDescriptions coloured by role palette. Officer navy and cap; hospital teal and white [hospital_police_infection §5.1, §8.2].
- Animals: ellipsoid-part rigs with Motor6Ds named like the final bones, animated procedurally. Already more readable than the HTML's stacked spheres.
- Vehicles: part-built to the logical box.
- Buildings: greybox LotTypes in flair colours.

### 5.3 Priority order and budgets

The order follows gameplay visibility and roles-first value. Triangle counts are LOD0 per MeshPart unless noted. Roblox caps a mesh at 20k triangles [feasibility B.c]. Texture guidance: 1024² maximum per map for characters, 256² for small props [feasibility B.g].

| P | Asset | Tris | Bones | Textures | Notes |
|---|---|---|---|---|---|
| P0 | **Squirrel** | body ≤ 8k + fur shells/cards ≤ 5k (2 skinned MeshParts) + eyes | ~36 | body 1024² Color/Normal/Roughness (TintMask for A3), cards 512² alpha | 7 stock furs from the HTML [wildlife_foraging §2]; tail lag = 8 tail bones plus a client spring chain [squirrel_abilities §24] |
| P0 | **Spicy rodent** | own body ≤ 8k + sparse cards ≤ 3k | same skeleton as squirrel | 1024² set | Owner art direction (§5.6). Same skeleton, so it shares every squirrel clip. |
| P1 | **Human bodies × 6** (female slim, female full, male slim, male broad, older female, older male) | ≤ 10k each (head ≤ 3k) | R15 | 1024² body; skin via 8 tone variants; outfit texture sets per role with TintMask accent zones | Covers "several adult body types" and the two older housewives of different appearance [brief §8] |
| P1 | **Hair × 8, role props × ~20** | hair ≤ 2k; props 0.2–1.5k | rigid | 256–512² | Police cap, badge, belt, baton, ticket book; stethoscope, clipboard; guard cap; EMT vest; mail bag; chef hat; barber smock; cyclist helmet; jogger band; rolling pin; broom; burglar beanie, sack, flashlight |
| P2 | **Fox** | ≤ 6k + cards ≤ 2k | ~34 | 1024² | stock colours #b8663c / #e4d6bc / #302c29 [wildlife_foraging §11.9] |
| P2 | **Deer** (doe, buck with antlers, fawn scaled) | ≤ 8k + antlers ≤ 1.5k | ~40 | 1024² | doe #ad845e, buck #946f4e, fawn #b99a70 [wildlife_foraging §11.8] |
| P3 | **Patrol car / sedan** (AI colour variants) | ≤ 6k + 4 wheels | rigid | shared 1024² vehicle trim + 512² liveries | lightbar parts for the beacon blink [hospital_police_infection §7.7] |
| P3 | Ambulance, ice cream van, trolley, dump truck, RV, motorcycle, bicycle | 8k / 8k / 10k / 10k / 10k / 4k / 2k | rigid | shared trim | logical boxes per [traffic §1] |
| P3 | **Drone** | ≤ 3k | rigid | 512² | rotors spin on the client |
| P3 | **Trees** (oak, elm, sycamore, maple, willow, apple) | trunk + boughs ≤ 8k, canopy cards ≤ 8k (separate MeshPart, hidden in winter) | rigid | bark 1024², shared leaf atlas 1024² | **Meshes generated from each tree's route control points**, so bark and climb rails always match. Acorns and apples merged per tree. |
| P3 | **Hollow trees**: H1 spiral premium, H2 shaft premium, 3 knothole variants, fallen log | premium shell ≤ 15k + interior ≤ 10k; knothole ≤ 6k; log ≤ 4k | rigid | bark 1024² + interior 1024² | §5.5 |
| P4 | **House kits × 8 archetypes** + interior furniture kit (~40 pieces) | ≤ 15k per assembled house; furniture 0.2–2k | rigid | shared trim sheet 1024² + siding, brick and shingle tileables 1024² | flair = module swaps plus recolours [brief §3] |
| P4 | Storefront and restaurant kit; school, church, gas station; hospital interior kit; police station; Quay kit (6 modules [worldgen_districts_art §16]); Galleria shell | ≤ 15k per building | rigid | shared trims | recoloured per lot |
| P4 | Street furniture: hydrant, stop sign, signal, streetlight, pole, bench, bin, dumpster, feeder, garden bed, mailbox, fences, hedges | 0.2–2k | rigid | shared 1024² | wires are Beams, not meshes |
| P5 | Backdrop: 3 mountain and hill bands, tree-line impostors, beach, pier, marina boats, radio tower, overflight airliner | ≤ 20k per band; tower ≤ 8k; plane ≤ 3k | rigid | aerial perspective baked in | Persistent streaming [worldgen_districts_art §14.4] |
| P5 | Images: moon phases (8 to start, up to 30) 512², clothing templates, UI icons | — | — | — | Open Cloud Image upload |

**Load check at peak.** About 15 squirrels × 13k plus about 50 humans × 10k is roughly 0.7M triangles if all were visible at once. Streaming and distance keep the visible set far smaller. Verify on low-end devices in W7 and, if needed, add a squirrel LOD1 (about 4k with no cards) beyond 60 st.

### 5.4 Clips per rig

| Rig | Required clips | Utility clips (also authored) |
|---|---|---|
| Squirrel / rodent | The brief's 7 [brief §7]: **Run** (ground; also roof, fence and branch at 0.7 cadence), **Climb** (trunk), **Wire traversal**, **Leap**, **Pounce** (with `Commit` and `Recover` markers), **Bite dance**, **Sneak**. State mapping per [routes_movement §19]. | Idle, ClimbIdle (grip), Land, Hit, Death, Forage, Deposit, Stink (squirrel), Chew, Feint (rodent, W4) |
| Human (R15, shared by all 6 bodies) | Roblox stock locomotion | Kick (markers), Swing, Baton, Shove, Flinch, BackAway, Cower, Disinfect loop, Pick, Carry, Deliver, WriteTicket, Talk, Argue A and B, Calm, RollingPin, Broom, DriveSit, EnterCar, ExitCar, Console, Restock, HideCrouch, SickIdle, StretcherCarry (W4) |
| Fox | Idle, Walk, Trot, Run, Lunge | Stalk, Recoil, Sniff, Sit, Jump |
| Deer | Idle, Graze, Walk, Trot, Bolt | Startle, Leap, LookAround |

### 5.5 Hollow trees: brief versus owner wishes, reconciled

The brief wants 11 hollow territories: 2 premium with "an interior pathway running up the entire centre of the trunk, with chambers at several heights", next to the best gardens and feeders, and 9 with a single knothole chamber [brief §3]. The owner wants three variants: a climb-up shaft with a knothole exit and hideout nook, a spiral ramp, and a fallen-log tunnel.

| Hollow | Site [wildlife_foraging §6.5] | Variant | How it satisfies both |
|---|---|---|---|
| H1 premium | park outer tree at (90, 358), beside the Tabasco community garden and the premium feeder | **Spiral ramp** up the trunk centre; 3 chambers at about 25 %, 55 % and 85 % height; base entrance plus crown knothole | It is the brief's interior pathway with chambers. The model is rebuilt at giant girth (r ≈ 2 u, about 5 st) so the ramp fits [wildlife_foraging §6.5]. |
| H2 premium | core SYCAMORE at (−37, 29), garden plot and premium feeder nearby | **Vertical shaft** climbed on the inside with the Climb clip; 3 hideout nooks; knothole exits at mid-height and crown | The owner's "climb up inside a hollow shaft with knothole exit and hideout nook", at premium scale |
| H3–H11 | bur oak, 3 giant trees, treehouse oak, Chili's sycamore, estate oak, westside oak, Quay willow | **Knothole + single chamber**. The chamber is a short climb-up nook, a miniature of the shaft variant. | The brief's 9 single-chamber hollows |
| Log (bonus) | the v5.4 hollow log at (−19, 376) [wildlife_foraging §6.4] | **Fallen-log tunnel**: a ground-level `hollow` route with two exits and a mid nook | A 12th *shelter*, not a claimable territory. The brief's count of 11 stays intact. It gives rodent health regen, a hide from the fox, and a shortcut. Alternative: count it as one of the 9 (D-15). |

Mechanics:
- Chambers are the nut-store anchor. The meter and ownership rule (≥ 70 %) are per tree.
- The rodent regenerates health inside any hollow (D-19).
- In the FRB all 11 are knothole plus a placeholder chamber. W3 adds the premium greybox interiors. W5 adds art.

### 5.6 Art direction and the review loop

**Overall look.** Semi-realistic, on a warm, hazy, low-saturation golden-hour suburb (median saturation 0.30, strong colour only on signs and toys) [worldgen_districts_art §14.1].

**Spicy rodent** (owner direction):
- zombie-lite: mangy fur, stitched bald patches, a few ribs showing;
- **natural fur colours, no green**;
- a little blood on the muzzle and claws;
- a touch of horror;
- "cute but unhinged": slightly oversized bloodshot eyes and a crazed buck-tooth grin.

The blood level is tied to the maturity target (D-11). The eyes stay red under the avatar blend (D7).

**Regular squirrels.** Natural greys, reds and browns from the 7 HTML furs. Weight and presence come from a sculpted silhouette, a groom normal map, roughness variation, fur cards, and a tail that lags the body [brief §7; feasibility B.g].

**Humans.** Every role outfit: townsperson variants, police, nurse, doctor, guard, orderly, EMT, cyclist, jogger, mail carrier, shop staff, defenders and burglar. The burglar uses neutral dark clothing; stereotypes are avoided. All six body types are used.

**Honest limit.** Headless Blender cannot hand-sculpt or judge look-dev in a viewport [feasibility, "What I can do"]. Claude builds procedurally:
- base meshes from skin modifiers, metaballs and remeshing, shaped by displacement;
- textures and masks baked from procedural shaders;
- fur cards converted from particle hair;
- clips keyed programmatically from parametric gaits, refined against reference timing.

Each asset ships turntables and a clip contact sheet for gate G2. If the hero assets (squirrel, rodent, human heads) do not reach the bar at G2, owner decision D-10 brings in licensed base meshes or an artist for sculpt and texture only. Claude keeps rigging, clips, export and integration.

---

## 6. Testing

### 6.1 Lune unit tests (`tests/unit`, run on every change in the container)

| Area | What is asserted |
|---|---|
| Units, Tunables, Schema | every tunable has a unit and a source; no NaN; schema round-trips |
| Data validators | unique ids; lots inside the world clamp; no overlap of solid footprints; door faces a street; pole clearance ≥ 0.95 u [worldgen_core §16]; every cast home exists; every forage and hollow anchor on walkable ground; every lane on a road |
| Terrain/Height, Ground | golden vectors from v5.4 `baseTerrainHeight`/`terrainHeight` (tolerance 1e-6); `groundAt` is pure in `(x, z, refY)` |
| Routes/Curve | golden `getPointAt` and `getSpacedPoints` from THREE r160 for 200 random routes (tolerance 0.01 u) [routes_movement §20] |
| Routes/Graph | regression counts for the reference set: 1,332 routes, 95 fork trunks, 770 forks, 149 islands, 40 singletons [routes_movement §3, verifier log] |
| Routes/Motion, SquirrelMotor | `advance` golden vectors; leap apex 2.73 u continuous (about 0.1 lower at 60 Hz, as expected [routes_movement verifier 10]); auto-switch at ≤ 0.48; junction choice; motor serialize → deserialize resumes identically (the mid-stride handoff property) |
| Quadruped, Car, Drone, HumanAI motors | speed caps, turn rates, ground snap, determinism under a fixed dt |
| Traffic/Swept | golden vectors from the JS `sweptVehicleHit`/`segmentBoxEntry` (10k random cases plus hand cases: jump over a sedan, under a trolley, 180° flip, start inside); broad-phase never rejects a true hit |
| LaneMath | no deadlock in the trolley-versus-westbound-sedan case [traffic §6.1]; stop-line FSM |
| Ladder | **one test per rule row** in §3.5, plus property tests: a player is always in exactly one rung; slot caps never exceeded outside the Lab; side exits restore the remembered rank; killer promotion order (squirrel, then hospital if > 30 %, then police) |
| CombatRules | pounce velocity golden; windows (wind-up, commit, recovery); bite chance against awareness; two kicks inside the regen window kill; defender × 1.5 one-shots at low health |
| InfectionRules | squirrel share maturation (25/7, cap 25, gates); critical mass; cure-time multiplier |
| ForageRules, SeasonRules, Moon | yields and cooldowns on the game clock; 70 % ownership; stink fire at ≥ 95 % costs 30; winter week 6 of 6; survival threshold; phase index at day 0, 7.4, 14.8 and 22.1 |
| BlendRules | output saturation ≤ 0.55 and value 0.39–0.91; one signature neon accent at most; the rodent's eyes unchanged; bizarre-avatar detection on the sample set; hitbox untouched |
| QuestTypes | step validators; reward computation |

### 6.2 Golden vectors from the original game

`tools/golden/` runs functions lifted from `reference/v5_4_game.js` in Node with three.js r160 on fixed and random inputs, and writes JSON. The Luau port must match. This is the strongest guarantee that "the HTML is the reference for … mechanics" [brief §1] survives the rewrite, and it is cheap to extend to any other pure function (the perception `spotted` rule, `pounceVelocity`, `RouteMotion.advance`).

### 6.3 Open Cloud Luau Execution integration tests (`tests/engine`)

**Runner.**
1. Build the place.
2. Save a version to the **CI place** (D10).
3. Create Luau Execution tasks against that version, poll them, and fetch the JSON return value and the logs.

**Limits** [feasibility B.d]:
- 5 task creates per minute and at most 10 incomplete per place, so the suites are batched into 2 tasks per run ("fast" and "sim");
- 5 minutes of runtime per task;
- 4 MB of return value and 450 KB of logs.

Physics does not run and no scripts auto-run, which suits our kinematic AI.

| Suite | Task | What it proves in the real engine |
|---|---|---|
| `BootSmoke` | fast | every ModuleScript `require`s without error (the type-checker substitute, D16); the remote table builds; Workspace and Players properties are as the project file sets them |
| `WorldBuild` | fast | Plan → Instantiate into a folder: lot and model counts equal the data; doors, prompts and colliders exist; nav reachability for every interior; route samples lie on geometry (raycast within `surfaceRadius + 0.3 u`); Skyline per building; Atomic/Persistent modes set |
| `Terrain` | fast | `TerrainBake.apply` on 3 districts; `ReadVoxels` matches `Height.at` within 1 voxel; timing recorded |
| `Actors` | fast | spawn bodies of every species; possess and release through a `PlayerLike` stub (bookkeeping, anchoring, attributes, Animator present, look applied and reverted); death and replacement keep species counts |
| `Assets` | fast | every non-zero AssetId loads (`InsertService:LoadAsset`, `KeyframeSequenceProvider:GetKeyframeSequenceAsync`); rig contracts hold (bones, sockets, triangle budgets) |
| `Avatar` | fast | trait fetch for 3 public UserIds (if allowed in Luau Execution, S5); compose on every species |
| `Sim10` | sim | 10 simulated minutes at full population with a fixed dt and seed. **Liveness:** every actor moves; no vehicle is stationary for over 60 s unless parked; no NaN; nobody outside the world clamp. **Gameplay:** the AI rodent lands at least one bite; the hospital cures at least one patient; at least one sighting; at least one quest spawned; swept collisions recorded only on the road. **Budget:** AI under 4 ms per frame on average and under 8 ms at the 99th percentile (from `os.clock`). |
| `LadderE2E` | sim | scripted event stream (join × 40, kills, winter end, leaves) through `RoleService` with stub players: final rungs match the expected table |

Results land in `build/reports/*.json` and in the commit message. An owner build is only uploaded from a green run.

### 6.4 Owner playtests

- **Checklists.** `docs/playtest/<build>.md` (FRB = §4.4). Each is delivered as a shareable checklist page the owner can tick. Each build adds its own checks and re-runs the FRB set as regression.
- **Multi-client.** In Studio, Test → Clients and Servers → 2, 3 or 4 players (up to 8 for the W7 load check). Role Lab sets up the roles in seconds.
- **Bug capture.** LAB → "Report" copies role, position, recent log lines, the tunables diff and the place version as text, which the owner pastes to Claude.
- **Feel tuning.** Live Tunables plus "Export tuning" (§3.6), so feel is tuned by the owner without code.
- **Live tests (W7).** A private server session with friends exercises real avatars (the blend), real latency (the swept fairness) and real load.

### 6.5 Definition of done, per change

`stylua --check` → `selene` → Lune unit and golden tests → `validate_data` → `rojo build` → (engine-relevant changes) CI place upload plus the engine suites → commit and push. An owner build is cut only when all of these are green and the wave's checklist has been self-checked by Claude's headless suites.

---
## 7. Risks, mitigations and owner decisions

### 7.1 Top risks

| # | Risk | Likelihood / impact | Mitigation | Fallback trigger |
|---|---|---|---|---|
| 1 | **Possession of pre-existing bodies** misbehaves: lost control after setting `player.Character`, animations not replicating, camera on a non-Humanoid body [feasibility B.a, medium-high confidence] | M / H | Spike S6 in W0, before any role code; `PlayerCharacterDestroyBehavior = Disabled`; server-created Animators; stream-around before the swap | S6 fails → D1 fallbacks; decide at G0 |
| 2 | **Client-owned kinematic animals** feel floaty, or the server sees stale positions, so bites and run-overs feel unfair | M / H | Rigid Align constraints set in PreSimulation; a motor-state stream to the server; pad and teleport flags; ring-buffer rewind in W7 | Playtest complaints in the FRB → pull W7 lag compensation forward; evaluate Server Authority |
| 3 | **Server CPU and bandwidth** at ~50 humans, ~15 squirrels, ~5 animals, 20–45 vehicles and 50 players | M / H | Kinematic anchored AI; `EvaluateStateMachine` off; LOD tiers with the drone counted as focus; the `Sim10` budget gate from W1; S7 | Budget miss → Parallel Luau perception, then state-stream rendering for Mid and Far tiers |
| 4 | **Semi-realistic hero art from headless procedural Blender** misses the bar | H / H (perceived quality) | Contracts plus placeholders mean gameplay never waits for art; G2 turntable reviews; budgets enforced by script | G2 fails → D-10 (licensed base meshes or an artist for sculpt and texture) |
| 5 | **Asset pipeline unknowns**: headless clips (S3) and headless textured models (S4) unverified; asset or animation **ownership mismatch** gives "Failed to load animation" [feasibility Blocker 7] | M / M | Spikes in W0; one owner for everything (D-1); the engine `Assets` test catches missing or unauthorised IDs | S3 or S4 fails → owner Art Inbox imports (O4), about 3 min per item |
| 6 | **Breadth versus depth**: eight roles in the FRB could each be shallow and buggy | M / M | Explicit thinnest loops and owner-runnable checks (§4.4); Role Lab; depth deferred by wave with G1 prioritisation; the regression rule | FRB checklist failures are fixed first in W3 |
| 7 | **Data-driven town versus SLIM and boot time**: runtime terrain is slow; SLIM needs saved static geometry [feasibility Blocker 6] | M / M | Lune-baked greybox in the place file; Skyline impostors (D3); terrain hash check | S2 over 20 s → Studio terrain bake button |
| 8 | **Open Cloud reachability and limits** (the feasibility run found `apis.roblox.com` blocked; the owner says it will be open) | L–M / M | Rate-limit-aware tools; separate CI place | Unreachable → `.rbxl` via GitHub release for owner builds; engine tests from a GitHub Actions runner with the key as a secret |
| 9 | **No Luau type checker in the container** [feasibility A4] | H / L–M | `--!strict`, Selene, `BootSmoke` in the engine, broad unit tests | Ask to allow a source build of luau-lsp, or run it on the Mac |
| 10 | **Content and policy**: blood and horror, profane HTML lines, possessable child NPCs, the burglar portrayal | M / M | Curated speech, profanity removed [worldgen_districts_art §16]; kids AI-only; maturity target D-11 | Questionnaire result → adjust blood decals by flag |
| 11 | **Ephemeral container and large binaries** (.blend, FBX, textures): Git LFS quota | M / L | LFS only for sources and exports; compressed textures; renders as small PNGs | Quota → LFS data pack (D-24) or exports kept out of git and rebuilt by script |
| 12 | **Gameplay tuning drift**: v5.4 radii were tuned for a smaller squirrel; the brief's 1.2-st shoulder is about 1.6–2× larger relative to humans [routes_movement §20; squirrel_abilities §26] | H / M | All radii are tunables in HTML units; owner live-tuning in playtests | D-26 |
| 13 | **Day length**: 72 s days (brief's ~50-min winter cycle) make sunsets last seconds [worldgen_districts_art §17 Q2] | H / L | A non-linear day curve holds the golden hours; one constant | D-4 |
| 14 | **Studio test players have negative UserIds**, so the real avatar blend is untested until live | H / L | Dev avatar samples in the Lab; the live session in W7 | — |

### 7.2 Owner decisions still needed

Each decision has a recommended default so the build never stalls. A default is reversible because it lives in data or Tunables.

| ID | Decision | Recommended default | Needed by |
|---|---|---|---|
| D-1 | Experience owner: your account or a group? All models and animations must have the same owner [feasibility B.c]. | Your personal account, unless collaborators are planned | O1 (W0) |
| D-24 | Git LFS on the private repo; may need a paid data pack later | Yes | W0 |
| D-25 | Facing: author all models toward Roblox LookVector (−Z), with one conversion from HTML yaw (the specs say "+Z") | Accept −Z | W1 |
| D-2 | Compass and backdrop: which way is north; ocean and mountain sides | North = +Z (district names); ocean to the north at the Willow River mouth; mountains south and west [worldgen_districts_art §14.4] | W1 (map), W6 (backdrop) |
| D-3 | Traffic handedness | Drive on the right everywhere [traffic §14 Q1] | W1 |
| D-26 | Squirrel scale: the brief's 1.2-st shoulder, or HTML proportions | The brief's size; re-tune radii in playtests | W1 |
| D-21 | Honour per-route `speed` (only makeTree trunks set 0.82) | Ignore, as v5.4 does; keep the field | W1 |
| D-4 | Real seconds per in-game day | 72 s (50-min winter cycle) with held golden hours; revisit after the FRB | W2 |
| D-5 | Infection model and visibility | Per-actor infection; town % derived; hidden critical mass (HTML thresholds) → silent outbreak → reset when everyone is infected; meter hidden from everyone (Lab only) | W2 |
| D-6 | Rodent health numbers | 100 HP; kick 55; baton 50; staff shove 40; defenders × 1.5; regen 2 HP/s stalking and 5 in a hollow; 0.6 s post-hit invulnerability [squirrel_abilities §25.3] | W2 |
| D-31 | Counter-play: v5.4's "perfect counter" and pounce immunity versus the brief's "biting into a raised arm or a kick does not land" | Drop the perfect counter and pounce immunity; a lunge that meets a committed kick is hit | W2 |
| D-7 | Who sees sightings | Police and drone see all; hospital sees bite sightings only; the rodent sees none | W2 |
| D-8 | Who can be run over, and the penalty | Every squirrel actor. The rodent's run ends; a regular squirrel drops its carried nuts and respawns at its hollow (no rung change). Humans, deer and fox are protected by yielding. A player driver gets the kill credit. | W2 |
| D-9 | AI patrol cars keep running when players drive (Addendum A1, to confirm) | Yes | W2 |
| D-16 | Path into the squirrel rung | The squirrel queue draws from tier 2 (staff and police) first, then humans by rank; a kill jumps the queue per the brief | W2 |
| D-17 | Rank after a winter death ("restart as humans") | Previous human rank (the rodent's death stays "lowest", as the brief says) | W2 |
| D-28 | Hospital staff who kill the rodent "instantly" become a squirrel, but what if all 7 squirrel player slots are full? | Temporary 8th squirrel slot until someone leaves the rung | W2 |
| D-19 | May the rodent rest in owned hollows? | Yes, for regen; it cannot take nuts; it may bite the owner if both are inside | W2 |
| D-20 | Mid-air pounce chaining (a v5.4 "air dash") | Keep it, with the new wind-up and a server-enforced cooldown | W2 |
| D-27 | Fox lunge effect on a squirrel; can the rodent bite deer or fox? | The lunge knocks back and spills carried nuts, never kills; the rodent cannot bite deer or fox | W2 |
| D-14 | "Several" deer slots | 4 | W2 |
| D-12 | HTML rodent economy: Power, Squirrel Coins, Gold, chili rush, sewer fashion stand, Galleria coins | Drop Power and Gold; keep the chili rush as a rodent-only power-up; map coins to credits; keep the fashion stand as a cosmetic for squirrels and the rodent (a worn hat replaces the A3 accessory) | W3 |
| D-13 | Which 40 houses get interiors; which 3 hold defenders | All 36 existing dwellings plus 4 new ones [worldgen_core §17 Q3a]; defenders proposed on the town-plan page | W3 |
| D-15 | Hollow sites H1–H11 and the log | As [wildlife_foraging §6.5]; the log is a bonus non-claimable shelter | W3 |
| D-23 | Close the road gaps [worldgen_core §17 Q5] | Yes, all of them | W3 |
| D-22 | Ambient species not in the brief (cats, dogs, rabbits, turtles) and the 13-min idle predator | Keep the species as ambient AI; drop the idle predator (AI takes over an AFK rodent body until input returns) | W4 |
| D-29 | Novelty cast: mime and 5 kid cyclists; are kids possessable? | Keep them AI-only; never possessable | W4 |
| D-32 | Vigilantes: fixed people or re-rolled? Do they swing as well as kick? | Re-rolled each in-game day to hold 8 % of AI humans; kick and swing; never flee [brief §8] | W4 |
| D-10 | Art sourcing for hero assets | Claude procedural, with G2 review; escalate to licensed base meshes or an artist if G2 fails | before W5 |
| D-11 | Maturity target (blood, horror, language) | "Mild": a little blood, no profanity | before W5 |
| D-30 | Moon (texture swap versus a phase-correct custom moon); tower placement and drone collision | Texture swap; a new backdrop tower on the sunset azimuth; towers block the drone | W6 |
| D-18 | Server fill and count (a real queue for the rodent slot [brief §5]) | Fill "Maximum" at 50; let Roblox open new servers only when full | W7 |

### 7.3 HTML behaviour deliberately not ported (bugs fixed in the rebuild)

These come from the specs' quirk and verifier sections. Each is fixed by design here; none needs owner input.

- **Interiors and terrain:**
  - dead walk-in interiors (`enterableHouses` is always empty) [worldgen_core §18.1; humans_actors verifier 1];
  - outer-home doors facing away from the road [worldgen_core §18.2];
  - flat outer-home roof landings [routes_movement verifier 4];
  - half-buried, collision-less v3.5 objects [worldgen_core §18.5];
  - ground-mesh gaps [worldgen_core §2].
- **Absolute-Y height tests:** perception, concealment, dog barks, bite bonus and doors now use height above local ground [humans_actors §15; wildlife_foraging verifier 1].
- **Global-state `getGroundAt`:** now a pure function [routes_movement verifier 5].
- **Traffic:**
  - handedness and the trolley/RV deadlock [traffic §3, §6.1];
  - short teleports swept as fatal [traffic verifier 1];
  - incident cars spawning inside parked cars [traffic verifier 3].
- **Hospital:** the overhead-hatch soft-lock [hospital_police_infection verifier 1].
- **Visuals:** mirrored park paths and stream [worldgen_core verifier 2–3]; the shared-material infection colour leak [wildlife_foraging §15].
- **Speech:** cooldown starvation [humans_actors verifier 3].
- **Idle predator:** frame-rate dependence [squirrel_abilities verifier 4].
- **The world pause** while in the sewer or hospital (impossible in multiplayer) [hospital_police_infection §12].

---

## Appendix: spec sources used

- **Brief and addendum:** `reference/Roblox_Rebuild_Brief.txt` (§1–§14); `spec/BRIEF_ADDENDUM.md` (A1 to A3).
- **Feasibility:** `spec/roblox_feasibility.md`:
  - Part A: toolchain;
  - B.a: possession;
  - B.b: rigs and movement;
  - B.c: import;
  - B.d: Open Cloud;
  - B.e: performance and streaming;
  - B.f: sky;
  - B.g: fur;
  - B.h: Rojo;
  - Blockers;
  - Recommended pipeline.
- **Subsystem specs:**
  - `spec/worldgen_core.md` §1–§4, §12–§18, verifier;
  - `spec/worldgen_districts_art.md` §1–§2, §14–§17, verifier;
  - `spec/routes_movement.md` §0–§4, §19–§21, verifier;
  - `spec/traffic.md` §1, §3, §6, §8, §12–§14, verifier;
  - `spec/squirrel_abilities_progression.md` §1, §3–§6, §21, §24–§27, verifier;
  - `spec/humans_actors.md` §1, §3, §5.3, §14–§16, verifier;
  - `spec/hospital_police_infection.md` §2, §6, §8, §11–§13, verifier;
  - `spec/wildlife_foraging.md` §1, §6, §11, §13–§16, verifier.
- **Data:** `spec/data/lots_core.json` (90), `lots_districts.json` (153), `roads.json` (116), `routes_catalog.json` (60 generators), `traffic_lanes.json` (25), `human_cast.json` (87), `wildlife.json`.
