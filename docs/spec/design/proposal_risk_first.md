# Spicy Rodents on Roblox: risk-first build proposal

Status: proposal for discussion with the owner. Nothing here has been built. Date: 2026-11-09.
Lens: **risk-first engineering.** Find what could sink the project, prove or disprove it first with instrumented spikes that are part of the real codebase, and only then pour the bulk of the build into a design that has survived contact with Roblox.

Sources (all under `/home/user/spicy-rodents`):

- Brief: `reference/Roblox_Rebuild_Brief.txt` (cited as **B§n**). Addendum: `spec/BRIEF_ADDENDUM.md` (cited as **A1-A3**; wins over the brief).
- Feasibility: `spec/roblox_feasibility.md` (cited as **F-A..F-h**).
- Subsystem specs (cited by file and section): `worldgen_core.md` (**WC**), `worldgen_districts_art.md` (**WD**), `routes_movement.md` (**RM**), `traffic.md` (**TR**), `squirrel_abilities_progression.md` (**SQ**), `humans_actors.md` (**HA**), `hospital_police_infection.md` (**HP**), `wildlife_foraging.md` (**WF**).
- Data: `spec/data/lots_core.json` (90 lots), `lots_districts.json` (153), `roads.json` (116), `routes_catalog.json` (60 generators, 1,332 routes), `traffic_lanes.json` (25 lanes), `human_cast.json` (87), `wildlife.json`.
- All listed files were present. `spec/design/` did not exist and was created for this file.

Owner decisions treated as fixed: private repo `spicy-rodents-roblox`; Open Cloud key (assets r/w, universe-places write, luau-execution r/w) reachable from the build container; Studio still needed for skinned-rig import, SurfaceAppearance, multi-client playtests and the final publish; owner is not a programmer; semi-realistic art direction; all three hollow-tree variants; order of operations to be discussed before any big commitment; 4-CPU ephemeral Linux container, at most 2 concurrent subagents.

---

## 0. The proposal in one page

**Shape of the build.** One build pass (B§ preamble), internally sequenced as six waves. Nothing ships publicly until the last wave. The owner sees exactly three things before the final live test: a short spike checklist (Wave 1), the **First Runnable Build** with all eight roles playable (end of Wave 2), and the complete game in graybox-plus-art (Waves 3-4).

**The five bets that make this low-risk:**

1. **Pure shared cores.** Every rule that matters (route maths, squirrel motion, swept collision, combat windows, infection, foraging, the Roles ladder, calendar and moon) is a pure Luau module in `ReplicatedStorage.Shared` with no engine dependencies. The same code runs in Lune unit tests in the container, on the server for validation and AI, and on the client for feel. This is what lets us swap movement authority (client-owned to server-authoritative) without rewriting gameplay, which is the main fallback for the two biggest risks.
2. **One actor model with a Driver seam.** An actor is a body plus a persistent brain plus a swappable Driver (`AIDriver` or `PlayerDriver`). Possession, release, queue promotion, NPC backfill and session reset are all one operation (B§4). Bodies are never destroyed on handoff (F-B(a) pitfall 1).
3. **The place file is 100% built from git.** Rojo plus a Lune build-time WorldGen bake produce the whole place. Everything that needs Studio (skinned rigs with SurfaceAppearance) lives in model assets loaded at runtime by an `AssetCatalog`, with git-tracked placeholders of identical shape. Code changes therefore never need the owner: Claude saves place versions and runs engine tests through Open Cloud.
4. **The drone never depends on one thing.** Static town geometry is baked so SLIM can work (F-B(e)), and a cheap client-side **Far-Town impostor** (Persistent, per-district chunks) is always built as the guaranteed fallback. The same data renders the town map image.
5. **Placeholders with contracts from day one.** Every rig, building and prop has a `RigSpec`/template contract (bone and attachment names, hitbox, sockets). Procedural placeholder animation drives everything until real clips land, so the First Runnable Build never waits on art or on the Studio/Open Cloud animation pipeline.

**What the owner does in Studio, in total:** one setup session (about 20 minutes), one spike checklist (about 40 minutes), the FRB playtest (about 60 minutes), a breadth playtest, a few short rig imports (about 10 minutes each, only if the headless path fails for skinned rigs), art reviews, and the live test plus final publish. Every session has a click-by-click guide in `docs/owner/`.

---

## 1. Architecture

### 1.1 Principles

| Principle | What it means in code | Source |
|---|---|---|
| One actor model | Humans, squirrels (incl. the spicy rodent), foxes and deer are `Actor`s. AI and players differ only by `Driver`. The drone and police cars are possessable rigs/vehicles through the same handoff code. | B§4, F-B(a) |
| Town is data | `TownLots.luau` is the list of lots; WorldGen builds every structure, route, forage spot, staff spot and parking space from it. A barber shop is one data entry. | B§2, WC§15-16, WD§16 |
| Server owns what scores or hurts | Bites, kicks, damage, infection, nuts, credits, rank, fatal traffic, quests, hollow ownership. | SQ§26, HP§12, WF§15 |
| Client owns feel | Own-body movement (rails, ground, car, drone), camera, animation, all cosmetic life (birds, insects, overflights, beacons, water). | RM§20, WD§16, WF§15 |
| Gameplay never depends on streaming | Routes, colliders, lots, nav graphs, duct polylines and forage anchors are plain data in `ReplicatedStorage`. Server AI runs everywhere, streamed or not. | RM§20, HP§12, TR§13 |
| Units at one boundary | Data files stay in HTML units (traceable to spec line numbers and golden tests). Loaders convert to studs once (`Scale.U = 2.5`). Runtime code is studs only. | B§2, WC§1 |
| Height above ground, never absolute Y | Every v5.4 absolute-Y test (visibility, concealment, bark, elevated bite) is ported as height above local ground. | SQ§26, HA§15, WF verifier #1 |
| Everything in git | The container is ephemeral. Tools bootstrap from a script; spike measurements, decisions and golden data are committed. | Owner facts |

### 1.2 Repository and Rojo tree

```
spicy-rodents-roblox/
├─ default.project.json        game place: Workspace/Players/Lighting properties, tree mapping
├─ rokit.toml                  pinned for the Mac and CI: rojo 7.7.1, lune 0.11.1, stylua 2.6.0, selene 0.31.0, luau-lsp
├─ selene.toml  roblox.yml  stylua.toml  .luaurc        (roblox.yml committed: F-A Selene gotcha)
├─ .github/workflows/ci.yml    stylua --check, selene, luau-lsp analyze (strict), lune tests, rojo build, place asserts
├─ src/
│  ├─ shared/  -> ReplicatedStorage.Shared
│  │  ├─ Data/      TownLots, LotTypes, Roads, Lanes, TrafficControl, RoutesBaked (gen), RouteGraph (gen),
│  │  │             Cast, Wildlife, Hospital (rooms, stations, shelves, items), Palette, AssetIds
│  │  ├─ Config/    Scale, Tunables, TunableMeta, Flags
│  │  ├─ Roles.luau            the ladder; stated here and nowhere else (B§6)
│  │  ├─ Types.luau
│  │  ├─ Core/      Signal, Trove, Rng (mulberry32 port), SpatialHash, BufferCodec
│  │  ├─ World/     TerrainHeight, Town, Colliders, WorldGen/ (Builders/*, Factory interface)
│  │  ├─ Routes/    RouteMath, Registry, Graph, RouteMotion, Junctions, Forks, RouteGen/ (lot templates)
│  │  ├─ Motion/    SquirrelMotion, QuadrupedMotion, DroneMotion, HumanLimits
│  │  ├─ Traffic/   Swept, LaneMath, Yield
│  │  ├─ Rules/     Combat, Infection, Foraging, Hollows, Stink, Economy
│  │  ├─ Time/      Clock, DayCurve, Calendar, Moon
│  │  ├─ Avatar/    BlendRules
│  │  ├─ Anim/      RigSpec, AnimLibrary
│  │  └─ Net/       Remotes (declarative registry), Packets (buffer codecs)
│  ├─ server/  -> ServerScriptService.Server
│  │  ├─ Main.server.luau      ServiceRegistry: init/start order
│  │  ├─ Services/  (one module per system; table in 1.4)
│  │  └─ Brains/    Pedestrian, Resident, Worker, HospitalStaff, Patient, Officer, Burglar, Arguer,
│  │                CarDriver, Vigilante (overlay), Defender, Squirrel, Rodent, Fox, Deer, DronePark
│  └─ client/  -> StarterPlayer.StarterPlayerScripts.Client
│     ├─ Main.client.luau
│     └─ Controllers/ Camera/ Anim/ World/ Sky/ Ambient/ UI/ Input/ Audio/ Dev/
├─ assets/
│  ├─ placeholders/  *.rbxm  Lune-generated rigs and templates honouring RigSpec -> ServerStorage.Templates
│  ├─ anim/          *.rbxm  KeyframeSequences built by Lune from Blender curves -> ServerStorage.AnimSources
│  └─ templates/     *.rbxm  captured real models when they can live in the place
├─ build/          (gitignored) Town.rbxm (Lune bake), place.rbxl
├─ blender/        scripts/*.py (bpy 5.2.3), src/*.blend, export/*.fbx, curves/*.json, previews/*.png
├─ tools/          bootstrap.sh, check.sh, bake_town.luau, bake_routes.mjs, gen_golden.mjs, build_anims.luau,
│                  opencloud.luau, run_cloud_tests.luau, render_map.py, moon_phases.py, validate_data.luau
├─ tests/          unit/ (Lune), place/ (Lune on built rbxl), cloud/ (Luau Execution suites), golden/*.json
└─ docs/           README.md, DECISIONS.md, spikes/S1..S9.md, owner/*.md (click-by-click), playtests/*.md
```

`default.project.json` sets, and the place tests assert:

- `Workspace`: `StreamingEnabled = true`, `ModelStreamingBehavior = Improved`, `StreamOutBehavior = Opportunistic`, `PlayerCharacterDestroyBehavior = Disabled` (F-B(a) pitfall 1), `SignalBehavior = Deferred`, `StreamingTargetRadius = 1024`, `StreamingMinRadius = 128`, `FallenPartsDestroyHeight` below the sewer floor (WD§16).
- `Players.CharacterAutoLoads = false` (F-B(a)).
- `Lighting.Technology = Future`, `GeographicLatitude = 39` (WD§14.2).
- `Workspace.Town` from `build/Town.rbxm` (baked; must exist before `rojo build`).

### 1.3 Runtime lifecycle

1. **Server boot** (`Main.server.luau`): load Data, then services in dependency order: `Persistence`, `AssetCatalog` (loads runtime model assets by ID, falls back to placeholders), `WorldRuntime` (terrain voxels from `TerrainHeight`, doors, runtime-only pieces), `Town`/`Routes` indices, `ActorService` (spawn every body from `Cast` at its persona's current schedule position), `AIScheduler`, then gameplay services. Players are held on a loading screen until `WorldReady` is set (target: under 15 s, measured in S5).
2. **Player join**: `RoleService` creates a server-lifetime profile, picks a role by the ladder (default Human) and calls `ActorService.possess(player, body)` on an existing AI body near a sensible spot. `AvatarBlendService` blends asynchronously; the stock look shows immediately.
3. **Steady state**: AI brains tick under `AIScheduler`; `TrafficService` at 30 Hz; `FatalCollision` once per traffic tick; `MovementValidator` ingests client packets; clients render from streamed bodies plus replicated compact state.
4. **Player leave**: `ActorService.release(actor)` before engine cleanup; the brain resumes from the last validated state.
5. **Session reset** (everyone infected, B§8): `RoleService.resetSession()` cures all actors, re-deals roles through the same possession path, keeps server-lifetime ranks unless the owner decides otherwise.

### 1.4 Module catalogue

Interfaces are function names plus the data each module owns. "Pure" means no engine services, testable under Lune.

Where the brief's named modules (B§2) and the addendum's needs live:

| Brief / addendum module | Shared (pure rules and data) | Server | Client |
|---|---|---|---|
| WorldGen | `World/WorldGen`, `World/Town`, `World/TerrainHeight`, `Data/TownLots`, `Data/LotTypes` | `WorldRuntime` (terrain, doors), Lune bake tool | `ImpostorView` |
| Routes | `Routes/*`, `Motion/SquirrelMotion` | `MovementValidator` | `SquirrelController` |
| Traffic | `Traffic/*`, `Data/Lanes`, `Data/TrafficControl` | `TrafficService`, `FatalCollision` | `VehicleView` |
| Actors | `Types` (`ActorState`), `Anim/RigSpec` | `ActorService`, `Brains/*`, `AIScheduler`, `Perception`, `Nav` | `ActorView`, `AnimDriver`, controllers |
| Roles | `Roles` (the ladder) | `RoleService` | `UI/Queue` |
| Infection | `Rules/Infection` | `InfectionService` | none (hidden by design, B§8) |
| Hospital | `Data/Hospital` | `HospitalService` | `UI/Hospital` |
| Police | `Rules/Economy` | `PoliceService` | role HUD |
| Drone | `Motion/DroneMotion` | `DroneService` | `DroneController` |
| Seasons | `Time/Clock`, `Time/Calendar`, `Time/Moon`, `Time/DayCurve` | `SeasonService` | `SkyController`, `WinterView` |
| Foraging | `Rules/Foraging`, `Rules/Hollows`, `Rules/Stink` | `ForagingService` | forage UI in `SquirrelController` |
| Wildlife | `Data/Wildlife`, `Motion/QuadrupedMotion` | `WildlifeService` | `QuadrupedController`, `AmbientLife` |
| Driving (A1) | `Traffic/LaneMath` | `PatrolCarService` | `CarController` |
| Map, radar, sightings (A1) | `World/Town` (map data) | `SightingService`, `PatrolCarService.radar` | `UI/Map`, `UI/Radar` |
| Side quests and jobs (A2) | `Rules/Economy` | `QuestService`, `EconomyService`, `HouseService` | `UI/Quests` |
| Avatar blend (A3) | `Avatar/BlendRules` | `AvatarBlendService`, `AssetCatalog` | none |
| UI | none | none | `UI/*`, `Input`, `Audio` |
| Net layer | `Net/Remotes`, `Net/Packets` | (all services) | (all controllers) |
| Config and tunables | `Config/*` | `DevService` (live overrides) | `UI/Dev` |
| Clock | `Time/Clock` (epoch attribute) | `SeasonService` sets the epoch | `SkyController` |

#### Shared (ReplicatedStorage.Shared)

| Module | Responsibility | Public interface | Owns |
|---|---|---|---|
| `Config/Scale` (pure) | Unit conversion HTML -> studs | `U`, `st(u)`, `v3u(x,y,z)` | `studsPerUnit = 2.5` |
| `Config/Tunables` + `TunableMeta` (pure) | Every tunable number in one tree, with unit, range and spec citation | `Tunables.<Group>.<key>`; `TunableMeta.get(path)`; `Tunables.applyOverrides(map)` (dev, server-replicated via attribute) | all tuning values (3.5) |
| `Config/Flags` (pure) | Feature flags | `Flags.LabMode`, `DevPanel`, `AnimSource`, `UseImpostor`, `UseSLIM` | flags |
| `Roles` (pure) | **The promotion ladder, slot caps, rank formulas, transitions.** Nothing else in the codebase encodes the ladder. | `LADDER`, `rung(roleId)`, `humanRank(stats)`, `squirrelRank(nuts, stinkPct, cohortMaxNuts)`, `slotCaps(serverState)`, `queueOrder(candidates, roleId)`, `transition(event, ctx) -> {Transition}` | ladder (3.4) |
| `Types` (pure) | Shared type definitions | `ActorState`, `Lot`, `RouteDef`, `RoleId`, `Species`, ... | types |
| `Core/*` (pure) | Signal, Trove, seeded Rng (mulberry32 port for HTML parity, WF§15), SpatialHash, BufferCodec | as named | none |
| `World/TerrainHeight` (pure) | Verbatim port of `baseTerrainHeight`/`terrainHeight` (WC§3, WC§16) | `base(x,z)`, `height(x,z)`, `groundAt(x,z,refY)` (RM verifier #5) | height function |
| `World/Town` (pure) | Loads lots and lot types; spatial queries; data colliders | `lots()`, `lot(id)`, `ofType(t)`, `lotAt(x,z)`, `colliders()`, `door(lotId)`, `forageSpots()`, `staffSpots()`, `parking()`, `districtAt(x,z)` | derived indices |
| `World/WorldGen` (pure + factory) | Builds instances from lots through a `Factory` interface so the same builders run in Lune (bake) and in the engine (runtime pieces) | `build(factory, opts)`, `Builders[lotType](lot, ctx)`, `chunks()` (Far-Town impostor) | none at runtime |
| `Routes/RouteMath` (pure) | Centripetal Catmull-Rom (alpha 0.5, phantom end points), arc-length tables with 200 divisions (RM§20) | `curve(points)`, `pointAt(c,t)`, `tangentAt(c,t)`, `spaced(c,steps)` | none |
| `Routes/Registry` (pure) | All routes: 1,332 baked v5.4 routes plus generated lot, hollow, duct and roof-access routes; 20-stud spatial index | `get(id)`, `all()`, `nearest(pos, maxDist, excluding)`, `byKind(k)`, `inCell(pos)` | route defs, samples, index |
| `Routes/Graph` (pure, generated) | Precomputed endpoint links, canopy forks, transfer pairs (RM§3, §11-12) | `endLinks(id, atStart)`, `forks(trunkId)`, `transfers(id, t)`, `isLegalTransfer(a, ta, b, tb)` | route graph |
| `Routes/RouteMotion`, `Junctions`, `Forks` (pure) | v5.4 rail parameter maths, switchRoute scoring, canopy fork choice (RM§1.2, §11-12) | `advance(...)`, `switchCandidates(...)`, `chooseFork(...)` | none |
| `Motion/SquirrelMotion` (pure) | Deterministic `step(state, input, dt, world) -> (state, events)` for ground, air, rail, hollow and duct; the single movement code for player client, server validator and AI brain | `step`, `envelope(prev, next, dt)`, `canGrab(state)` | none |
| `Motion/QuadrupedMotion`, `DroneMotion`, `HumanLimits` (pure) | Fox/deer stepping; drone flight model; human speed caps per state | `step`, `limits(state)` | none |
| `Traffic/Swept` (pure) | Exact port of `segmentBoxEntry` and `sweptVehicleHit` (TR§8.4) | `segmentBoxEntry(a,b,box)`, `sweptVehicleHit(P0,P1,V0,V1,psi0,psi1,W,L,H,pad)` | none |
| `Traffic/LaneMath`, `Yield` (pure) | Lane parameter to pose, leader/follower, stop-line distance, relative squirrel visibility (TR§13) | `pose(lane, s)`, `leader(lane, s)`, `mustYield(veh, hazards)` | none |
| `Rules/Combat` (pure) | Pounce wind-up/commit/recovery, reaction windows, zig-zag detector, feint, stamina, damage table (B§8, SQ§25) | `pouncePhase(t)`, `resolveBite(ctx)`, `resolveStrike(ctx)`, `zigzag(history)`, `humanResponse(awareness, nerve, vigilante, rng)` | none |
| `Rules/Infection` (pure) | Per-actor infection maths, town %, squirrel share, critical mass, cure time (HP§6, HP§11) | `townPercent(c)`, `squirrelShare(s)`, `criticalMass(state)`, `cureTime(base, staffInfected)` | none |
| `Rules/Foraging`, `Hollows`, `Stink` (pure) | Yields, cooldowns, hollow meter and 70% ownership, theft, survival threshold, stink fill/fire (B§7, WF§14) | `canForage`, `yield`, `meter`, `owner`, `survives`, `stinkTick`, `canFire` | none |
| `Rules/Economy` (pure) | Credits per job/quest, upgrade costs | `reward(kind, quality)`, `cost(upgrade)` | none |
| `Time/Clock`, `DayCurve`, `Calendar`, `Moon` (pure) | In-game time from `workspace:GetServerTimeNow()` plus an epoch attribute; non-linear day curve; weeks, winter, raid cycle; lunar phase (WD§14.3-14.4) | `Clock.now()`, `DayCurve.hour(frac)`, `Calendar.isWinter(day)`, `Calendar.raidWeek(day)`, `Moon.phase(day)` | none (epoch is a Workspace attribute) |
| `Avatar/BlendRules` (pure) | Palette clamp (saturation <= 0.55, value 0.39-0.91, one neon accent, WD§15), signature-feature pick, region colour mapping per species (A3) | `clamp(c)`, `signature(desc)`, `regions(desc, species)` | none |
| `Anim/RigSpec` (pure) | Per-species contract: bone names, attachments (HeadSocket, MouthSocket, TailTip, Seat, CarryR), hitbox, hip height | `RigSpec[species]`, `validate(model)` | contracts |
| `Anim/AnimLibrary` | Clip resolution: published ID, else Studio-registered temp ID, else procedural | `clip(species, name)`, `isProcedural(...)` | clip table (`Data/AssetIds`) |
| `Net/Remotes`, `Packets` | Declarative remote registry (name, direction, reliability, rate cap, schema); compact buffer codecs | `Net.server(name)`, `Net.client(name)`, `Packets.encodeMove/decodeMove`, `encodePoses/decodePoses` | remote list (1.5) |

#### Server (ServerScriptService.Server)

| Service | Responsibility | Public interface | Owns |
|---|---|---|---|
| `ServiceRegistry` | Init/start order, dependency injection | `get(name)`, `start()` | service table |
| `ActorService` | The actor model: bodies, brains, drivers, body modes, possession | `spawnFromCast()`, `get(id)`, `possess(player, id, opts)`, `release(id, reason)`, `setBodyMode(actor, "kinematic"/"physical")`, `snapshot(id)`, events `Possessed`, `Released`, `Died` | Actor table, bodies |
| `Brains/*` | One brain per behaviour; all share `new(actor, persona)`, `tick(dt, tier)`, `suspend() -> state`, `resume(state)`, `onEvent(e)` | as listed | brain state |
| `AIScheduler` | LOD tiers, per-frame ms budget, staggered ticks, `BulkMoveTo` batching (F-B(e)) | `register(brain)`, `setInterestProvider(fn)`, `metrics()` | tiers, budgets |
| `Perception` | Spatial hash of actors; ported spotting with height above ground (HA§5.3, SQ§7) | `query(pos, r, filter)`, `canSee(human, target)`, event `Spotted` | perception grid |
| `Nav` | Sidewalk lane graph from `Roads`; per-archetype indoor room graphs; cached escape paths (PathfindingService only as fallback) | `path(from, to, opts)`, `roomGraph(lotId)` | nav graphs |
| `RoleService` | Applies `Roles` to players: profiles, queue, slots, promotions, side exits, session reset | `request(player, role)`, `onEvent(event, ctx)`, `rank(player)`, `queue(role)`, `resetSession()` | server-lifetime player profiles |
| `MovementValidator` | Validates client-owned movement; leaky buckets; corrections; pose history for lag compensation | `ingest(player, packet)`, `pose(id)`, `history(id, t0, t1)`, `correct(id, state)` | validated pose ring buffers |
| `TrafficService` | AI vehicles on lanes, yielding, signals and stop signs, violations (speeding, rolling stop, illegal parking), fender-bender generator, pose ring buffers, pose broadcast | `fleet()`, `poseAt(vehId, t)`, `spawn(kind, lane)`, events `Violation`, `FenderBender` | vehicle states, traffic control state |
| `FatalCollision` | Per traffic tick relative swept test for every squirrel actor vs fleet, with teleport resets and lag compensation (TR§8, TR§13) | `markTeleported(id)`, event `RunOver(actorId, vehicle, driver?)` | none |
| `PatrolCarService` | Two drivable cars for the top-two officers; enter/exit/siren; server sampling into the fleet; radar contacts (A1) | `assign()`, `enter(player, car)`, `exit(player)`, `setLights(car, on)`, `radar(car)` | patrol car state |
| `CombatService` | Health, stamina, pounce/bite/kick/swing/baton/staff/defender blows; server resolution with rewind (SQ§26) | `damage(id, amt, src)`, `heal(id, amt)`, events `Bitten`, `Kicked`, `Killed` | health, stamina |
| `InfectionService` | Per-actor infection, squirrel maturation, town %, hidden win, everyone-infected reset (HP§6, HP§11) | `infect(id, by)`, `cure(id, by)`, `townPercent()`, `isInfected(id)` | infection state |
| `HospitalService` | Admissions, treatment stations and disinfection loop, fetch tasks, performance metric, upgrades, ambulances (HP§11) | `admit(id)`, `startTreatment(staff, patient, station)`, `fetchRequest()`, `submitItem(player, item)`, `performance()` | hospital state |
| `PoliceService` | Officer slots 5 to 8 by performance, AI dispatch backfill, aggression ladder, drone unlock, wanted posters | `officers()`, `unlockNext()`, `dispatch(scene)` | police state |
| `QuestService` | Side quests and jobs: petty argument, fender bender, parking/speeding/stop-sign tickets, burglar, hospital fetch, shop jobs (A2) | `offer(player)`, `accept`, `progress`, `complete`, `available(role)` | quest instances |
| `SightingService` | Sightings and marks with TTL and audience rules; radar feed (A1) | `report(kind, pos, by, conf)`, `mark(pos, by)`, `visibleTo(player)` | sighting list |
| `DroneService` | Drone rig, pad, flight validation, spot-and-mark, vigilante call (B§10) | `launch(player)`, `land()`, `mark(player, ray)` | drone state |
| `ForagingService` | Forage sources, carried nuts, hollows (store, steal, claim), premium raids, stink gland | `forage(id, spotId)`, `store(id, hollowId, n)`, `claim(id, hollowId)`, `fireStink(id)` | forage and hollow state |
| `WildlifeService` | Fox and deer actors (brains via ActorService), lightweight non-possessable critters (rabbits, cats, dogs), startle sources | `critters()`, `startle(pos, kind)` | critter state |
| `SeasonService` | Calendar events, winter on/off effects, winter-end survival check | events `DayStarted`, `WeekStarted`, `WinterStarted`, `WinterEnded` | season state |
| `HouseService` | 40 interiors: server door state, hiding spots, claims, remodel points and state, three defenders | `claim(player, lotId)`, `remodel(player, change)`, `door(lotId)`, `hide(id, spot)` | house state |
| `EconomyService` | Credits ledger, purchases, station upgrades | `grant(player, amt, why)`, `spend(player, amt, what)` | ledgers |
| `AvatarBlendService` | Fetch `HumanoidDescription` (cached per user), compute blend, apply, revert (A3) | `apply(actor, player)`, `revert(actor)` | blend cache |
| `AssetCatalog` | Runtime-loaded model assets (rigs with SurfaceAppearance) with placeholder fallback | `template(name)`, `ready()` | template registry |
| `PersistenceService` | Server-lifetime store; optional DataStore profiles with session locking | `life:get/set`, `profile(player)` | stores |
| `WorldRuntime` | Terrain voxels, doors, runtime-only world bits, impostor chunk metadata | `ready()` | runtime world |
| `DevService` | Dev commands, gated by an allowlist: possess any actor, force role, time skip, spawn quest, unlock drone, overlays | via `Net.Dev` | none |
| `Telemetry` | Frame budget counters per service, alarms, values for the dev HUD | `scope(name)`, `snapshot()` | metrics |

#### Client (StarterPlayerScripts.Client)

| Controller | Responsibility | Interface |
|---|---|---|
| `ActorView` | Registry of streamed actor bodies (CollectionService tags); interpolation for kinematic AI; nametags for animals | `onActor(fn)`, `get(id)` |
| `HumanController` | On-foot human (default Humanoid controls) plus kick, swing, flinch, back-away, interact | `bind(actor)`, `unbind()` |
| `SquirrelController` | Rail/ground/air/hollow/duct movement through `SquirrelMotion`; stalk, pounce, leap, feint, drop, forage, stink; 20 Hz state packets | `bind(actor, snapshot)` |
| `QuadrupedController` | Fox and deer movement and actions | `bind(actor, snapshot)` |
| `CarController` | Patrol car driving, siren and lights, pull-over, radar UI feed | `bind(car)` |
| `DroneController` | Flight, camera feed, mark reticle | `bind(drone)` |
| `CameraRig` | Per-mode rigs from RM§15, spherecast occlusion, hospital and mall constraints (WD§16) | `setMode(mode)` |
| `AnimDriver` | Species animation state machine; clip or procedural; tail spring chain; foot IK near camera (SQ§24, SQ§26) | `attach(actor)` |
| `VehicleView` | Renders AI vehicles from replicated poses ("ghost vehicles") with about 100 ms interpolation (TR§13) | none |
| `SkyController`, `WinterView` | Lighting keyframes from `Clock`, moon texture swap, stars, tower blink, overflight, winter grade and bare trees | none |
| `AmbientLife` | Birds, nests, butterflies, dragonflies, insects; seeded and clock-driven, client-only (WF§15) | none |
| `ImpostorView` | Shows Far-Town impostor chunks only where real geometry is not streamed | none |
| `UI/*` | Role HUDs, minimap and full map with marker layers, radar, quests, role queue, hospital task UI, notification priority queue, dev panel | per panel |
| `Input`, `Audio` | ContextActionService bindings (keyboard/mouse, gamepad, touch; SQ§26 conflicts), sound | none |

### 1.5 Net layer

All remotes are declared once in `Net/Remotes`; the server rejects any payload that does not match its schema or exceeds its rate cap.

| Remote | Dir | Kind | Rate cap | Payload |
|---|---|---|---|---|
| `Possessed` / `Released` | S->C | reliable | event | actorId, species, `ActorState` snapshot (mode, pos, vel, yaw, routeId, t, dir, clip, clipTime) |
| `MoveState` | C->S | unreliable | 20 Hz | buffer: seq, client time, mode, routeId (u16), t (u16 quantised), dir, pos, vel (about 40 bytes) |
| `Correction` | S->C | reliable | <= 2 Hz | authoritative state |
| `Action` | C->S | reliable | per kind | Leap, Pounce, Feint, Bite, Kick, Swing, Interact, Stink, Mark, EnterCar, ExitCar, Siren, Ticket, Treat, Fetch |
| `ActionResult` | S->C | reliable | event | outcome, corrections, rewards |
| `VehiclePoses` | S->C | unreliable | 15 Hz (5 Hz for the drone) | interest-filtered batch: id u8, x, z f32, yaw u16, speed u8, bits u8 (about 13 bytes each; stays under the unreliable payload cap, exact cap to verify) |
| `Sightings` | S->C | reliable | event | role-filtered markers with TTL |
| `Radar` | S->C | unreliable | 5 Hz | to car drivers: nearby vehicle ids, speeds, limits |
| `Quest`, `Notify`, `Queue`, `Hospital` | S->C | reliable | event | UI state |
| `Dev` | C->S | reliable | gated | dev commands (allowlist) |

Low-rate per-actor state (health, nuts, role, infected-visible tell, anim state for AI) rides on attributes, not remotes (SQ§26).

### 1.6 The actor model in detail

```
Actor = { id, species, body: Model, persona, role, brain (persistent), driver: AIDriver | PlayerDriver,
          state: ActorState, appearance: { stock, blend? } }
```

**Body modes.** AI-driven bodies are anchored and moved kinematically by the server with `workspace:BulkMoveTo` (F-B(b)), with `Humanoid.EvaluateStateMachine = false` and unused Humanoid states disabled. Player-driven bodies are unanchored, physical and client-owned. This mirrors v5.4, where every NPC is kinematic (HA§15), and keeps Humanoid physics cost to the players' own bodies.

**Possession sequence** (`ActorService.possess`):

1. `player:RequestStreamAroundAsync(body.Pivot)` with a timeout (F-B(a) pitfall 5). Bodies are `ModelStreamingMode = Atomic` with a `PrimaryPart`.
2. `brain:suspend()` returns the mid-stride state: velocity, rail (routeId, t, dir), goal, playing clip and time position.
3. `setBodyMode(physical)`: unanchor, enable the state machine, set `AssemblyLinearVelocity` to the brain's velocity so momentum carries.
4. `root:SetNetworkOwner(player)`; `player.Character = body`.
5. `Possessed` carries the snapshot; the client controller starts from it and `AnimDriver` cross-fades into the same clip at the same time position.
6. `FatalCollision.markTeleported(id)` and `MovementValidator` resets the leaky bucket (TR§13 teleport filter).
7. `AvatarBlendService.apply` runs asynchronously.

**Release** is the reverse: last validated state goes to `brain:resume`, `SetNetworkOwner(nil)`, `player.Character = nil`, body back to kinematic, blend reverted. On `PlayerRemoving` release happens first.

**Never let the engine kill a body.** `Humanoid.BreakJointsOnDeath = false`, the Dead state is disabled, and gameplay health lives in `CombatService`. "Death" is a role transition (B§6), never a respawn.

**Non-Humanoid bodies.** The default `PlayerModule` controls are disabled for animals, the drone and cars; our controllers take over and `CameraRig` sets `CameraSubject` explicitly (F-B(a) pitfalls 3-4).

---

## 2. Key technical decisions

Each decision names the spike that confirms it and the fallback if the spike fails. Spikes are defined in section 4, Wave 1.

| # | Area | Decision | Rationale | Fallback | Confirmed by |
|---|---|---|---|---|---|
| D1 | Movement authority | Players' own bodies are **client-owned**. Squirrels and rodent: client kinematic controller running `SquirrelMotion`, root driven under `PreSimulation` with physics collisions off; the client also streams compact `MoveState` packets. The server validates every packet against the shared registry and graph: speed caps per route kind (x1.6 boost), legal transfers (gap <= 7.9 st, grab radius <= 8.5 st), ballistic envelopes (gravity 75 st/s^2), data-collider wall crossings, leaky-bucket tolerance (RM§20, F-B(b)). Humans: default Humanoid controls with speed and teleport checks. | v5.4 rails need 60 Hz input-coupled motion (RM§20); server round trips would feel sticky. Shared pure step function keeps validator and client identical. | **Server-authoritative rail with client prediction and reconciliation**, using the same `SquirrelMotion.step`. Later, Server Authority (beta) when it is generally available (F-B(b) option 2). | S1, S2 |
| D2 | AI scheduling and LOD | Three tiers by distance to interest points (player-driven actors, the rodent, drone focus): **T0** under 160 st: brain 10 Hz, full perception, server-played animation. **T1** 160-600 st: 4 Hz, kinematic along lanes, walk loop only. **T2** beyond 600 st: 1 Hz analytic "commute" on the lane graph, no animation. Per-frame AI budget 4 ms, time-sliced round robin, batched `BulkMoveTo`. Serial Luau first. | F-B(e): about 100 Humanoids is the community stutter point; our load is about 60 humans, 12 squirrels, 5 deer, 1 fox, 45-50 vehicles. Kinematic AI matches v5.4 (HA§15). | Parallel Luau perception in 2-4 Actors; lower tier rates; trim ambient human bodies from 60 to 45 (still above 35 slots). | S4 |
| D3 | Streaming | Actors `Atomic` with `PrimaryPart`; backdrop, skyline landmarks and the impostor `Persistent`; the drone's `ReplicationFocus` follows the drone; possession pre-requests streaming; AI vehicles are client-rendered from replicated poses so a streamed-out car can never be "invisible yet lethal" (TR§13). | F-B(e), WD§16, TR§13. | Raise `StreamingMinRadius`; server-anchored vehicle models moved with `BulkMoveTo` at 20 Hz. | S5 |
| D4 | WorldGen: bake vs runtime | **Bake static, load dynamic.** WorldGen runs at **build time in Lune** and emits `build/Town.rbxm` (lot shells, roofs, roads, poles, trunks, signage, backdrop), so SLIM can process static geometry (F-B(e) "Drone view"). Terrain voxels, doors, interior props and actors are created at server start. Art meshes with SurfaceAppearance come from runtime-loaded model assets. The data file stays the only source of truth. | Resolves the SLIM vs runtime tension (F Blocker 6) and keeps every place version publishable through Open Cloud, because the place contains no SurfaceAppearance (F-B(d) publishing limitation). | If Lune-written MeshParts fail to load correctly, building meshes also move to runtime clones, and the drone relies on the impostor (D5). | S5, S6 |
| D5 | Drone whole-town view | `Model.LevelOfDetail = SLIM` on baked lots plus `EnableSLIMAvatars`, **and** an always-built Far-Town impostor (low-part, per-district Persistent chunks generated from lot data, hidden near the camera). The same generator renders the 2D town map image. | SLIM is cloud-generated and only checkable on a published place (F-B(e)); the impostor is entirely under our control and cheap. | Impostor-only far view. | S5 |
| D6 | Traffic and fatal collision | AI vehicles are server-kinematic at 30 Hz with 1 s pose ring buffers. `Traffic/Swept` is a byte-for-byte port of TR§8.4 with golden tests against the JS. Squirrel segments come from validated, client-timestamped samples; vehicle poses are rewound to those times (lag compensation, TR§13 option b). Player patrol cars are `VehicleSeat` physics cars owned by the driver, sampled each server tick into the same fleet with speed and teleport checks. Stationary vehicles never kill (`travel < 1e-5`); every scripted reposition and every possession resets the previous pose. Never `Touched`. | B§8 and A1 require it; TR§8 gives exact maths; TR verifier #1 shows why teleports must reset. | Server-view-only test with a wider pad (TR§13 option a); player cars become input-driven kinematic cars simulated on the server like AI cars. | S3 |
| D7 | Animation pipeline | Clips authored in Blender (one action per clip), exported as FBX for Studio and as bone-curve JSON. Lune turns curves into `KeyframeSequence` `.rbxm` (verified in F-A Lune smoke test), uploaded headless as Animation assets through the Assets API, IDs written to `Data/AssetIds`. `AnimLibrary` falls back to Studio-registered temporary IDs, then to **procedural animation**, so nothing blocks on the pipeline. Skinned rigs: Open Cloud FBX Model upload if it yields a working skinned rig; otherwise the owner imports once in Studio (3D Importer, Rig Type Custom) and saves it to Roblox. | F-B(c), F-B(d). Owner's key covers asset upload. | Studio Animation Editor import plus Publish per clip (click-by-click guide). | S6 |
| D8 | Avatar blend (A3) | Server reads `Players:GetHumanoidDescriptionFromUserId`. Humans keep the role's body and uniform and take skin tone (clamped), one signature head accessory (hair preferred), classic face if present, and accent colours on TintMask regions. Animals keep species mesh and markings and take a capped fur tint, pattern-region colours, eye colour (rodent eyes stay red, SQ§25.11) and one shrunken accessory on `HeadSocket`. No pixel reading of others' clothing; colours come from body colours and a curated accessory-type mapping. Hitbox, hip height and rig scale are asserted unchanged after every blend (RM§19). | A3 technical notes; pixel access to other users' assets is not something to rely on. | Colours-only blend plus a stock accessory recoloured; optional "pick your two accent colours" prompt for players whose avatars give little colour signal (owner decision). | S7 |
| D9 | Persistence | **Server-lifetime in memory** for everything the brief scopes to the server: rank (B§6 "time logged in and playing on this server"), house claims and remodels (B§8 "persist for the life of that server instance"), hollows, credits. DataStore only for opt-in cross-session items (settings, any wardrobe kept), behind a session-locked wrapper with the same interface. | The brief does not ask for cross-server persistence, which removes most DataStore risk. | Flip the store implementation per key if the owner later wants cross-server persistence. | S9 |
| D10 | Type safety | `--!strict` everywhere. `luau-lsp analyze` with Roblox definitions runs in **GitHub Actions** (which can download the release binary that the container cannot, F-A4), plus Lune tests, a Lune require-graph smoke test and an engine boot test through Luau Execution. | No type checker in the container (F Blocker 1). | Owner permits a source build of luau-lsp in the container (F-A4). | W0 exit |
| D11 | Combat under latency | Server-resolved duel with up to about 150 ms rewind; telegraphs and lunges play instantly on the client; a rejected result arrives as a correction, never a rubber-banded lunge (SQ§26). Windows are tunables, widened by half the RTT. | B§8 combat dynamics; SQ§25.2. | Fixed-delay "input buffer" windows; looser tunables. | S2, FRB playtest |
| D12 | Owner workflow | The owner never runs a terminal. Claude builds the place and saves versions through Open Cloud; the owner opens the experience in Studio from the cloud. Studio-only content travels as model assets referenced by ID. | Owner is not a programmer. | Owner installs the Rojo plugin and runs `rojo serve` via a one-click script (only if needed). | W0 |

---

## 3. Data schemas

Schemas are written as Luau type sketches for precision. They are specifications, not game code.

### 3.1 Town lots (`src/shared/Data/TownLots.luau`) and lot types (`LotTypes.luau`)

Seeded from `lots_core.json` (90) and `lots_districts.json` (153) with their `id`, `district`, `type`, `x`, `z`, `facing`, `footprint`, `style`, `has_interior` fields (WC§1, WD§0), normalised so that parameters now buried in `notes` prose become structured fields. One logical list, organised by district sections.

```lua
export type Facing = "+X" | "-X" | "+Z" | "-Z"
export type Lot = {
  id: string,                      -- "core_house_0_victorian" (keep spec ids; new lots get new ids)
  district: string,                -- "old_town_core", "bellwether_quay", ...
  type: string,                    -- key into LotTypes
  x: number, z: number,            -- HTML units, lot centre (converted at load)
  facing: Facing | number,         -- world direction of the front, or yaw in radians
  footprint: { w: number, d: number },   -- world-axis extents, HTML units
  archetype: string?,              -- "house.victorian", "shop.barber", "restaurant.taco"
  height: { eave: number?, peak: number?, storeys: number? }?,
  style: { seed: number, paint: string?, trim: string?, roof: string?, porch: string?, yard: string? }?,
  interior: { archetype: string, claimable: boolean, hideSpots: number,
              defender: ("rollingPinA" | "rollingPinB" | "broom")? }?,
  forage: { ForageSpot }?,         -- extends the lot type's default table
  risk: number?,                   -- 0..1 override
  staff: { { role: string, count: number, spot: string } }?,
  jobs: { string }?,               -- job ids offered here (A2, B§13)
  routes: { { template: string, params: { [string]: any }? } }?,
  traffic: { parking: { ParkingSpace }?, hydrants: { Vec2 }?, redCurbs: { Seg2 }? }?,
  hollow: { tier: "premium" | "knothole" | "log", variant: "spiral" | "shaft" | "chamber" | "tunnel",
            capacity: number, claimable: boolean }?,
  tags: { string }?,               -- "drone_landmark", "persistent", "map_label"
  src: string,                     -- provenance: "v5.4 L1034 (lots_core core_house_0_victorian)" or "B§3 expansion"
}
export type ForageSpot = {
  kind: "garden" | "feeder" | "trash" | "dumpster" | "apple" | "cache" | "plaza" | "acorn" | "petbowl",
  x: number, z: number, yield: { min: number, max: number },
  cooldown: "day" | "week" | number, premium: boolean?, risk: number,
  guards: { "homeowner" | "birds" | "dog" | "cat" | "staff" }?,
}
export type ParkingSpace = { x: number, z: number, yaw: number, legal: "ok" | "hydrant" | "redCurb" | "driveway",
                             limitMinutes: number? }
export type LotType = {
  builder: string,                 -- WorldGen builder name
  solid: boolean, interiorAllowed: boolean,
  forage: { ForageSpot }, risk: number,
  staffSlots: { { role: string, count: number } }?,
  routeTemplates: { string },      -- ridge, downspout, gutter, fence, hollow, ...
  map: { glyph: string, color: string, label: boolean },
  persistent: boolean?,            -- drone landmarks (WD§16)
}
```

Validation (Lune, every commit): unique ids; footprints inside the world clamp (WC§2, WD§0); no overlaps except whitelisted nesting (rooms inside the hospital, details on lots); pole clearance from pavement >= 0.95 u (WC§16); every interior house has a door facing a road (fixes WC§18.2); counts: **40** interior houses, **11** hollow territories (2 premium, 9 knothole), at least **2 x** the v5.4 food lots, every expansion lot type present (barber, music, hardware, laundromat, bookshop, pet store, gas station, corner grocery, school with playground, church, park with gazebo, community garden, marina; B§3); every restaurant has seating or a dumpster; every lot type has a forage table and risk (B§3).

**Hollow-tree reconciliation (owner's three variants vs B§3's 11 trees).** Two premium territories, nine knothole territories, plus one non-territory tunnel:

| Id (WF§6.5) | Tier | Owner variant | Interior |
|---|---|---|---|
| H1 park outer 95 (90, 358), next to the Tabasco community garden | premium | **spiral ramp** | ramp route up the trunk centre, chambers at 3 heights, knothole exits |
| H2 SYCAMORE core (-37, 29), densest backyards | premium | **climb shaft** | vertical shaft climb, side chambers, knothole exits, hideout nook at the top |
| H3-H11 | knothole | single chamber | one chamber via a knothole (B§3) |
| Fallen log near the v5.4 hollow log shelter (WF§6.4) | not a territory | **hollow log tunnel** | tunnel route used as a shelter and shortcut |

Premium trees are authored at giant-tree girth (trunk radius about 2 u) because a walk-up interior needs it (WF§6.5). Whether the log should instead count as one of the nine is an owner decision (section 7).

### 3.2 Roads, lanes and traffic control

`Roads.luau` from `roads.json` (`axis`, `coord`, `width`, `start`, `end`, `kind`), with the WC§4.3 gaps closed so the network is connected. `Lanes.luau` from `traffic_lanes.json`, normalised to one handedness (TR§11.1, owner decision; default keep right). New `TrafficControl.luau`, which v5.4 lacks entirely (TR§12):

```lua
export type Junction = { id: string, x: number, z: number, control: "signal" | "stop" | "yield" | "none",
                         phases: { { greens: { string }, seconds: number } }?, stopLines: { [string]: number } }
export type LaneLimit = { lane: string, limit: number }       -- u/s, radar and speeding tickets
export type ViolationRates = { speeding: number, rollStop: number, illegalPark: number, fenderPerHour: number }
```

### 3.3 Routes, route graph, hollows and ducts

```lua
export type RouteKind = "trunk" | "branch" | "bridge" | "lookout" | "roof" | "wire" | "fence" | "trampoline"
                      | "hollow" | "tunnel" | "duct"           -- last three are new (RM§19, HP§12)
export type RouteDef = {
  id: number, name: string, kind: RouteKind,
  surface: "tree" | "pole" | "pipe" | "ladder" | "wire" | "roof" | "fence" | "bark_inner" | "log" | "duct",
  points: { { number } },          -- control points {x,y,z}, HTML units
  surfaceRadius: number,           -- default 1.35 (RM§1.1)
  visualOffset: number?,           -- per-route override; kind defaults per RM§1.4
  surfaceNormal: { number }?,      -- replaces name regexes (RM§4, RM verifier #2)
  speedMul: number?,               -- owner decision whether route.speed is honoured (RM§21.2)
  lotId: string?, generator: string,
  flags: { noAutoGrab: boolean?, isolated: boolean? }?,
  nodes: { { t: number, kind: "chamber" | "knothole" | "vent" | "nook", id: string, capacity: number? } }?,
}
```

- `RoutesBaked` holds the 1,332 v5.4 routes as control points dumped from a headless run of the unmodified HTML (RM§0, RM§20); sampling is recomputed. `Graph` is generated offline from all routes.
- Lot-type route templates (`RouteGen/*`) emit ridge, downspout, gutter, fence and hollow routes for every lot, so new lots never need hand-written routes (RM§19).
- The hospital roof access route and the duct network (7 nodes, crawl speeds 2.8/3.8 u/s, vents as nodes with `open`/`chew` attributes) are routes (HP§12).

### 3.4 Roles ladder (`src/shared/Roles.luau`, the only place it is stated)

```lua
export type RoleId = "Human" | "HospitalStaff" | "Police" | "Drone" | "Squirrel" | "SpicyRodent" | "Deer" | "Fox"
export type Rung = {
  id: RoleId, tier: number,                -- 1 Human .. 4 SpicyRodent; 0 for side exits
  prestige: number,                        -- HospitalStaff 2.1 > Police 2.0 (B§6 "slightly above")
  species: "human" | "squirrel" | "deer" | "fox" | "drone",
  slots: { start: number, max: number, unlock: string? },
  bodies: { min: number, max: number },
  entry: "join" | "queue" | "choice" | "unlock",
  exitTo: "previousHumanRank" | "lowestHuman" | nil,
}
-- LADDER (values per B§5-6, B§10-11):
--  Human          tier 1  slots 35        bodies 45-60  entry join
--  Police         tier 2  slots 5 -> 8    bodies 8      entry queue  unlock "policePerformance" one at a time
--  Drone          tier 2  slots 0 -> 1    bodies 1      entry unlock "8 officers + upgrade"
--  HospitalStaff  tier 2  slots 5         bodies 8      entry queue
--  Squirrel       tier 3  slots 7         bodies 10-14  entry queue
--  SpicyRodent    tier 4  slots 1         bodies 1      entry queue (top squirrel)
--  Deer           tier 0  slots ~4        bodies 5      entry choice exitTo previousHumanRank
--  Fox            tier 0  slots 1         bodies 1      entry choice exitTo previousHumanRank
-- RANK:
--  humanRank    = minutesPlayedOnServer * w.time + credits * w.credits + kicks * w.kick + quests * w.quest
--  squirrelRank = 0.9 * (nuts / max(1, cohortMaxNuts)) * 100 + 0.1 * stinkPct
-- TRANSITIONS (event -> outcome), one table row per brief sentence, each a unit test:
--  RodentDied(any cause)        -> rodent player: Human, lowest rank; slot -> top-ranked squirrel
--  RodentKilledBy(human)        -> killer: lowest-rank uninfected squirrel if a body is free;
--                                  else Police; or HospitalStaff if town infection > 30%
--  RodentKilledBy(staff, inHospital) -> killer: lowest-rank uninfected squirrel, instantly
--  SquirrelInfected             -> heavy loss of points and nuts, drops in queue
--  SquirrelKillRodentAttempt    -> impossible: regular squirrels cannot harm the rodent
--  WinterEndBelowThreshold      -> squirrel: Human
--  SideExitLeave(deer|fox)      -> Human at previousHumanRank
--  KickLanded(human)            -> rank bonus (A2)
--  QuestCompleted / CureCompleted / FetchCompleted -> credits + rank (A2, B§13)
--  EveryoneInfected             -> session reset (B§8)
```

Queue entry rules for tier 2 and tier 3 (whether humans opt in to hospital, police or squirrel, and whether tier 2 is a prerequisite for squirrel) are owner decisions; the schema supports both.

### 3.5 Tunables (`src/shared/Config/Tunables.luau`)

Plain nested values for cheap access; a parallel `TunableMeta` maps each path to `{ unit, min, max, src }` so the dev panel can expose sliders and tests can check ranges. All values in studs and seconds at runtime; `src` cites the spec value it came from.

| Group | Example keys (default, source) |
|---|---|
| `Clock` | `realSecondsPerDay` 72 (about 50 min per 6-week cycle; WD§17.2, WF§13.12), `daysPerWeek` 7, `weeksPerCycle` 6, `winterWeek` 6, `lunarMonthDays` 29.53, `dayCurve` holds for sunrise/sunset/blue hour (WD§14.3) |
| `Population` | `humanBodies` 60, `squirrelBodies` {10, 14}, `deerBodies` 5, `foxBodies` 1, `vigilanteFraction` 0.08 (B§8) |
| `Squirrel` | `walk` 20, `sprint` 42, `stalk` 4.1, `boostMul` 1.6, `gravity` 75, `leapUp` 32, `leapFwd` 41.25, `railBase` 18, `treeMul` 0.6, `shoulderHeight` 1.2 (B§2, SQ§26, RM§20) |
| `Routes` | `autoSwitch` 1.2, `transfer` 4.25, `maxGap` 7.9, `grab` 8.5, `cell` 20 (RM§20) |
| `Combat` | `maxHealth` 100, `kickDamage` 55, `defenderMul` 1.5, `windup` 0.18, `commit` 0.30, `recovery` 0.35, `feintStamina` 25, `zigzagSpeedMul` 0.8, `regenStalk` 2, `regenHollow` 5, `iFrames` 0.6 (SQ§25.3 proposals) |
| `Traffic` | `tickHz` 30, `posesHz` 15, `pad` 0.45 st (0.18 u, TR§8.4), `teleportSkip` 30 st, `hazardVisibleDy` 11.9 st (4.76 u, TR§13) |
| `Infection` | `criticalMass`, `resetAt` 1.0, `squirrelShareCap` 25, `infectedStaffCureMul` 1.5 (HP§13 open) |
| `Foraging` | `hollowCapacity`, `premiumMul` 2, `ownThreshold` 0.70, `stinkFireAt` 0.95, `stinkCost` 30, `survivalThreshold` (B§7, B§12) |
| `AI` | `tierRadii` {160, 600}, `tierHz` {10, 4, 1}, `budgetMs` 4, `spotRadius` 36 (HA§15) |
| `Net` | `moveHz` 20, `rewindMaxMs` 150, `leakyBucket` {capacity, leak} |
| `Avatar` | `maxSat` 0.55, `valRange` {0.39, 0.91}, `furTintCap` 0.3 (A3 "70/30"), `accessoryMaxSize` |

### 3.6 Rig contract (`Anim/RigSpec`)

```lua
export type RigSpec = {
  species: string, root: "HumanoidRootPart" | "Root",
  controller: "Humanoid" | "AnimationController",
  bones: { string },                      -- exact names; Lune placeholder and Blender rig both honour it
  attachments: { string },                -- HeadSocket, MouthSocket, TailTip, CarryR, Seat, ...
  hitbox: { size: Vector3, hipHeight: number },
  clips: { string },                      -- required clip names
  tintRegions: { string },                -- fur/uniform regions for A3 blending
}
```

### 3.7 README recipes (B§14 deliverable)

- **Add a lot type** (for example a barber shop): add a `LotTypes` entry (builder, forage, risk, staff, route templates, map glyph) if the type is new, then add a `TownLots` entry. Run `tools/check.sh`; validators and the bake do the rest.
- **Add a route**: add a `RouteGen` template and reference it from a lot type or a lot's `routes`; the graph regenerates at bake.
- **Add a role**: add a rung and its transitions in `Roles.luau`, a brain in `Brains/`, a controller if it is a new species, and a `RigSpec`. Nothing else encodes the ladder.

---

## 4. Order of operations

### 4.1 Overview

| Wave | Purpose | Owner in Studio | Gate |
|---|---|---|---|
| Step 0 | Decisions and contracts | none (a conversation) | Owner agrees the "before W0" decisions |
| W0 | Foundation: repo, CI with type checking, Open Cloud client, data and golden files | Setup, about 20 min | CI green; Luau Execution "hello" works |
| W1 | Risk spikes S1-S9 inside the real codebase | Spike checklist, about 40 min | **G1: spike review with the owner** before the bulk build |
| W2 | **First Runnable Build: all eight roles playable** | FRB playtest, about 60 min | FRB checklist passes for every role |
| W3 | Breadth and depth: every remaining system | Breadth playtest, about 60 min | Full-system checklist and 2-hour soak |
| W4 | Art lock (art lane runs from W1 onward) | Rig imports if needed; art reviews | No must-replace placeholders left |
| W5 | Live hardening and publish | Live test with friends; final publish | 10+ player live session meets budget |

Waves are internal sequencing of the single pass required by the brief; nothing is shipped publicly before W5, and there is no walkable-town milestone. **One honest tension:** the W1 spike checklist runs on the real graybox town before roles are wired. It is a measuring instrument, not a milestone, and it exists because possession feel, rail validation under latency and the drone's far view cannot be measured headlessly. If the owner prefers, those checks can be folded into the FRB playtest; the cost is that a failed spike would then be discovered after the bulk of W2 is built on top of it.

**Concurrency** (at most 2 subagents): Lane A does gameplay systems; Lane B does data, tools, WorldGen, Blender assets and the client presentation layer. Contracts written in Step 0 (`Types`, `RigSpec`, `Net/Remotes`, `Tunables` skeleton, `Roles` draft) keep the lanes from colliding.

**Every step, every lane:** `tools/check.sh` (StyLua, Selene, Lune unit tests, data validators, Lune bake, `rojo build`, place-tree assertions), then CI (adds strict `luau-lsp analyze`), then on milestones an Open Cloud saved version plus the Luau Execution suite.

### 4.2 Step 0: decisions and contracts

- **Built:** `docs/DECISIONS.md`; contracts: `Types.luau`, `RigSpec`, `Net/Remotes`, `Tunables` skeleton, `Roles` draft text.
- **Owner:** answers the "before W0" decisions in section 7.2 (experience ownership, compass and backdrop sides, squirrel scale, day length, spike checklist yes/no, CI on GitHub Actions and key placement).
- **Exit:** the owner has read the ladder text in `Roles` and agrees it says what B§6 says.

### 4.3 Wave 0: foundation

| Lane | Built |
|---|---|
| A | Private repo `spicy-rodents-roblox`; Rojo project with the properties in 1.2; `tools/bootstrap.sh` and an environment setup script that install pinned rojo 7.7.1, lune 0.11.1, stylua 2.6.0 (`--features luau`), selene 0.31.0 and bpy 5.2.3 (F-A gotchas included; committed `roblox.yml`); GitHub Actions CI with Rokit and `luau-lsp analyze`; `tools/opencloud.luau`: save place version (unpublished), create and poll Luau Execution tasks, upload image/model/animation, poll operations; `tests/cloud` runner skeleton. |
| B | Data import: `lots_*.json` -> `TownLots.luau` with structured params; `roads.json` -> `Roads.luau` (gaps closed); `traffic_lanes.json` -> `Lanes.luau`; `human_cast.json` -> `Cast.luau`; `wildlife.json` -> `Wildlife.luau` (runtime positions baked, WF§15 determinism). Golden data from headless node runs of the unmodified v5.4 JS (the extractors' approach, RM§0, WF preamble): all 1,332 routes' control points and samples; a terrain height grid; 10,000 random `sweptVehicleHit` vectors; Catmull-Rom samples. Lune validators. |

- **Owner in Studio (setup, about 20 minutes, guide `docs/owner/00_setup.md`):** create the experience and its place under the chosen owner (user or group); Game Settings: Max Players 50, Server Fill (if decided), enable Studio access to API services; Creator Dashboard: create the Open Cloud API key with the four scopes restricted to this experience; hand the key over through the environment's secret store (never in chat); send the universe and place IDs.
- **Exit:** CI green on the skeleton (format, lint, strict type check with 0 errors, Lune tests, build); from the container, `opencloud.luau` saves a place version and a Luau Execution task returns `"ok"`; data validators pass with 243 v5.4 lots imported; golden route dump has 1,332 routes and 81,613 index entries (RM§0 verification log); terrain golden matches `TerrainHeight` within 1e-6.
- **If Open Cloud is unreachable from the container** (F-B(d) found `apis.roblox.com` blocked at the time): run the Open Cloud steps from GitHub Actions with the key as a repository secret (owner decision).

### 4.4 Wave 1: risk spikes

Spikes build **real modules** (ActorService, SquirrelMotion, Swept, Scheduler, WorldGen v0) against the real data, with harnesses behind `Flags.LabMode`. Results and measurements go to `docs/spikes/Sn.md`, and every adopted fallback goes to `DECISIONS.md`.

| Spike | What is built | Measurable exit criteria | Fallback if it fails |
|---|---|---|---|
| **S1 Possession handoff** (Humanoid and AnimationController) | ActorService core (possess, release, body modes, driver swap); placeholder R15 human and Lune-built AnimationController squirrel rig with RigSpec names; procedural AnimDriver v0; handoff probe that logs position and animation continuity | (1) 20 handoffs per species at 150 ms simulated lag: position jump at handoff <= 0.5 st (squirrel) and <= 1.0 st (human); (2) control responsive within 250 ms; (3) no T-pose or frozen frame (owner eye plus Animator track check); (4) 500-cycle automated possess/release soak with fake drivers: 0 leaked bodies, 0 errors, network owner always matches driver; (5) leaving mid-stride: AI resumes within 0.2 s, body intact | "Blink handoff" (0.25 s camera dip hides a snap to validated state); animals on server simulation with client prediction (D1 fallback); Server Authority once out of beta |
| **S2 Rail authority** | RouteMath, Registry with all baked routes, Graph, `SquirrelMotion.step`, SquirrelController, MovementValidator, dev-only cheat harness | (1) Lune: every route's samples match the HTML dump within 0.01 u (RM§20); (2) 10-minute scripted honest circuit (trunk, bough, wire, roof, leap, ground, hollow shaft) at 150 ms and 2% loss: 0 corrections; (3) cheat harness (speed x2, 30-stud teleport, 20-stud illegal leap, wall pass, hop to a non-adjacent route): each flagged within 1 s, detection >= 95%, 0 false positives across honest runs; (4) validator <= 0.05 ms per squirrel per tick | Server-authoritative rail with prediction and reconciliation, same step function |
| **S3 Fatal traffic** | `Traffic/Swept`, TrafficService v0 on 3 real lanes, pose ring buffers, VehicleView ghosts, FatalCollision with lag compensation, one drivable patrol car | (1) 10,000 golden vectors: 100% agreement with the JS; (2) Luau Execution scenario suite: 1,000 randomised crossings agree with analytic truth; the 0.51 s sedan jump window reproduces (TR§8.4); (3) Studio 2-client at 150 ms: player car over player squirrel registers in >= 9/10 direct hits and 0/10 clear misses (>= 1.5 st); same for AI car; (4) 15 squirrels x 50 vehicles <= 0.5 ms per tick with circle broad phase | Server-view test with wider pad; input-driven kinematic player cars |
| **S4 AI scale** | AIScheduler tiers and budget, Perception grid, PedestrianBrain v0 on the sidewalk graph, SquirrelBrain v0 on the route graph, deer/fox v0, 47 virtual interest points spread over the town | Studio test server with 60 humans, 14 squirrels, 6 deer, 1 fox, 45 vehicles, 3 real clients: server AI p95 <= 4 ms per frame, whole server frame p95 <= 12 ms, average client receive <= 50 KB/s; Luau Execution microbenchmarks of brain ticks recorded as a regression baseline | Parallel Luau perception; lower tier rates; 45 human bodies |
| **S5 Streaming, WorldGen bake, drone view** | WorldGen v0 graybox bake (Lune) of all 243 lots and roads; runtime terrain from `TerrainHeight`; Persistent backdrop placeholders; Far-Town impostor v0 and map render; DroneController v0 | (1) bake: 100% of lots, 0 validator errors, place builds in < 60 s; (2) server boot including terrain <= 15 s; (3) on a published private server: drone at 300 st over the centre and the corners shows every district (SLIM or impostor) with no holes, owner Mac >= 45 fps; (4) possessing an actor 2,000 st away is streamed and controllable within 2 s; (5) 30-minute drone soak: 0 missing-part errors; (6) record whether Lune-written MeshParts load correctly and whether streamed-out terrain renders far away | Impostor-only far view; MeshPart ground tiles if runtime terrain is too slow or terrain vanishes at distance; runtime clones for building meshes |
| **S6 Asset pipeline** | bpy squirrel rig v0 (from the F-A5 13-bone test, grown to the RigSpec), two clips, FBX per clip and curve JSON, Lune KeyframeSequence builder, Open Cloud uploads, verification task | (1) rig obtained via Open Cloud FBX upload, or one owner import of <= 10 minutes, loads through `InsertService:LoadAsset` in a Luau Execution task with every RigSpec bone and attachment; (2) two clips uploaded headless as Animation assets; `KeyframeSequenceProvider` returns matching pose names; (3) owner sees both clips play correctly (no flipped joints, F-B(c)) in a playtest; (4) a SurfaceAppearance-bearing model loaded at runtime renders its normal map in a live server; (5) a 10-second headless Blender preview render works (for remote art review) | Studio Animation Editor import and Publish per clip; Studio-only temporary IDs during development; procedural animation stays as the runtime fallback |
| **S7 Avatar blend** | AvatarBlendService and BlendRules for human and squirrel | For 20 user IDs (owner, friends, test accounts including bizarre bundles): blend applied <= 1.5 s p95 (stock shown first); revert is exact; hitbox and hip height unchanged (asserted); colours inside palette bounds; accessory load path confirmed (`InsertService` or a hidden dummy with `ApplyDescription`); owner approves 5 examples | Colours-only blend plus recoloured stock accessory; optional colour picker |
| **S8 Type safety** (runs in W0) | CI with `luau-lsp analyze` | 0 strict errors on all `src/` | Owner permits a container source build |
| **S9 Persistence** | Server-lifetime store; session-locked DataStore wrapper | Luau Execution test against test keys passes: locking, retries, version mismatch; Lune tests of the in-memory store | Keep everything server-lifetime |

- **Ordering inside W1:** Lane A runs S1, then S2, then S3; Lane B runs S6 (long Blender lead time), then S5, then S7. S4 starts once S1 and S2 have produced ActorService and SquirrelMotion. S8 completes in W0; S9 is small and runs in Lane A after S3.
- **Owner in Studio (spike checklist, about 40 minutes, `docs/owner/01_spike_checklist.md`):** open the experience from Roblox; Test tab, Clients and Servers, 2 players, Start; set the network lag setting to 150 ms (exact label to verify); follow the numbered list: possess a walking human, possess a running squirrel, release, ride a trunk and a wire, get run over, drive the patrol car, fly the drone over the town; then join the published private server from the Roblox app for the far-view check; rate each step pass/fail. If the headless rig path failed: one rig import (10 steps).
- **Exit and Gate G1:** each spike meets its criteria or its fallback is adopted and recorded. Claude presents a one-page spike report; the owner and Claude decide together whether to commit to W2 as planned.

### 4.5 Wave 2: First Runnable Build (all eight roles playable)

Sub-steps run in this order; each has a headless exit before the owner sees anything.

| Step | Lane A (systems) | Lane B (world, client, assets) | Headless exit |
|---|---|---|---|
| 2a World | Town queries, data colliders, Nav graphs (sidewalks, 40 interior room graphs, hospital, police station) | WorldGen graybox builders for every lot type including the expansion: about 2x restaurants with seating or dumpsters, 13 new lot types, 8 house archetypes, **40 interiors** with doors, rooms, hiding spots; hospital rooms per B§9 (reception, triage, Ward A, Ward B, isolation, pharmacy, staff room, ambulance bay, roof access) inside the 235 x 240 st shell (WD§2.6); police station interior; Quay and Galleria; river, ocean, beach, pier, marina and mountain placeholders; all route templates, 11 hollows (graybox interiors per 3.1), ducts; map image | Validators pass with all counts in 3.1; route graph connectivity report; bake under 60 s |
| 2b Actors and roles | Full cast: 60 humans with personas (jobs, homes, nerve, 8% vigilante flag), 12 squirrels, 1 rodent body, 5 deer, 1 fox, drone; all brains v1 (pedestrian commute, resident, worker, hospital staff, patient, officer, squirrel forager on routes, **AI rodent** for an unheld slot, fox, deer); RoleService, queue, all transitions; DevService | Dev panel (possess any actor, force role, time skip, unlock drone); role HUD shells; AvatarBlend v1; AnimDriver procedural for all species | Luau Execution: every `Roles` transition reachable from a scripted event sequence; 1,000 possess/release cycles clean |
| 2c Squirrel and rodent | Foraging v1 (gardens, feeders, trash, dumpsters, caches, apples, plaza), hollows and meter, 70% claim, theft rule, stink gland; Combat v1 duel (wind-up, commit, recovery, feint, zig-zag, stamina, health, kicks, swings); Infection v1 (per-actor, squirrel share, hidden win, reset) | SquirrelController complete (stalk, pounce, leap, drop, hollow and duct travel), squirrel camera rigs, forage UI | Lune: all combat and foraging rule tests; cloud: infection math suite |
| 2d Town jobs | Traffic v1: all v5.4 lanes with the TR§11 fixes, traffic control data, AI vehicles, yielding including player humans and squirrels, fatal test for every squirrel actor; police v1: foot patrol, baton damage, 2 drivable cars for the top two officers, radar, sightings; QuestService with speeding ticket, parking ticket and petty argument; hospital v1: admissions (walk-in and ambulance), treatment loop, one fetch-task type, staff kill rule; drone v1: flight, feed, spot-and-mark, vigilante call; one shop job for humans; house claim | CarController, DroneController, map with marker layers, radar UI, quest tracker, hospital task UI, notification queue | Cloud: traffic 120 s simulated with 0 deadlocks; quest lifecycle suite; hospital treatment suite |
| 2e Time and sky | SeasonService: days, weeks, winter week (forage multiplier, winter-end survival check) | SkyController with the day curve, moon phase textures generated in Python and uploaded, stars, blinking tower, winter view (bare trees, snow tint) | Lune: Clock, Calendar, Moon tests; the moon index advances once per in-game day |
| 2f Integration | Telemetry budgets; synthetic full population | Owner checklist | Full cloud suite green; synthetic load holds S4 budgets |

**The First Runnable Build contains** (graybox world, placeholder rigs with procedural animation; every role reachable through normal play and through the dev panel):

- **Human:** possess a walking townsperson mid-stride; walk, run, open doors, enter any of the 40 graybox interiors, hide; kick and swing at the rodent (a landed kick raises rank, A2); do one shop job for credits; claim a house; see rank and queue; town map.
- **Hospital staff:** possess a staff body; disinfect an infected patient at a treatment station; complete a medicine fetch task from the pharmacy (wrong item costs time); kill the rodent inside the building and become a squirrel (B§6); performance score.
- **Police:** possess an officer; foot patrol; baton strikes that can kill the rodent; sightings on the map; top two officers get patrol cars (enter, exit, drive, siren and lights) that can run the rodent over; radar with speeds; speeding ticket, parking ticket and petty-argument quests.
- **Drone:** unlocked by the dev panel or by eight officers; full flight and camera feed; spot-and-mark reveals the rodent to officers and calls nearby vigilantes.
- **Regular squirrel:** possess an AI squirrel mid-route; all v5.4 routes, leaps and canopy forks; forage; store nuts in a hollow; claim at 70%; fire the stink gland; rank from nuts and stink.
- **Spicy rodent:** stalk, pounce, bite with wind-up, commit and recovery; feint; zig-zag; health and regeneration; infect humans and squirrels; run over by any vehicle including player cars; killed by police, staff or kicks with the B§6 promotions; hidden win and session reset.
- **Fox:** possess; hunt regular squirrels; cannot harm the rodent; repelled by stink; leaving returns the player to their previous human rank.
- **Deer:** possess; wander; AI deer startle at traffic and a low drone; leaving returns the player to their previous human rank.
- **World:** full day cycle, moon phases tied to the calendar, a winter week every five weeks with survival check at its end.

- **Owner in Studio (FRB playtest, about 60 minutes, `docs/owner/02_frb_playtest.md`):** 3-client local test; for each role, the dev panel's "Play as" button, then a 5-minute scripted checklist; screenshots of anything wrong.
- **Exit:** all eight role checklists pass; 0 script errors in a 30-minute 3-client session; synthetic full population holds the S4 budget.

### 4.6 Wave 3: breadth and depth

| Lane A | Lane B |
|---|---|
| Quests: fender bender (AI drivers step out as actors), stop-sign running (stop-line FSM), burglar (break-in, indoor chase), more hospital fetch items and instruments; station upgrades and unlocks; officers 6-8 with the aggression ladder (HP§11.14); drone unlock by performance; three house defenders (two rolling pins, one broom, x1.5 blows); indoor chases where humans flee and hide and the rodent bursts in (must run and be tested, B§8); remodel points and state; vigilante 8% dynamics; crime scenes, ambulances, wanted posters; ducts, vents and chewing (with the hatch drop fixed, HP verifier #1); sewer; mall and Quay mechanics; apple trees; living events and novelty cast; AI patrol cars; trolley, ice-cream van, heavy vehicles; cats, dogs, rabbits if kept | Birds, nests, butterflies, dragonflies, insects; overflights world-relative (WF§13); audio; interior dressing; winter changes to wildlife; HUD polish; gamepad and touch bindings; art integrations as they land |

- **Owner in Studio (breadth playtest, about 60 minutes):** checklist per new system.
- **Exit:** full-system checklist passes; cloud suite green; 2-hour soak with 4 clients plus synthetic population: no errors, server memory flat, budgets hold.

### 4.7 Wave 4: art lock

The art lane starts in W1 (S6) and delivers in the priority order of section 5. Each landing swaps a template, re-runs RigSpec validation in a Luau Execution task, and gets a preview render plus an in-Studio look by the owner.

- **Owner in Studio:** rig imports only if the headless skinned-rig path failed in S6 (about 10 minutes per rig: Import 3D, Rig Type Custom, Upload, Save to Roblox, paste the asset ID back); art review sessions.
- **Exit:** nothing on the must-replace list remains a placeholder (squirrel, rodent, humans and outfits, fox, deer, patrol car, hollow trees, house kit, hospital interior); budgets still hold with final art; the owner signs off the squirrel, rodent and human looks.

### 4.8 Wave 5: live hardening and publish

- **Built:** SLIM-enabled publish; live MicroProfiler captures; mobile pass; content-maturity questionnaire answers; README (B§14); final balancing via tunables.
- **Owner:** invite 10 or more friends to the private server; play 45 minutes with the tester checklist; fill the maturity questionnaire; final publish (Studio, or Open Cloud since the place holds no SurfaceAppearance).
- **Exit:** in the live session, server frame p95 <= 16 ms, every role played by a real person, no blocking bugs.

### 4.9 Relative size (rough; for discussion only)

W0 small, W1 medium, W2 extra-large (the bulk of the code), W3 large, W4 large but in parallel with W2-W3, W5 medium. The spikes cost roughly a tenth of the build and decide whether the remaining nine tenths run on the primary design or the fallbacks.

---

## 5. Asset plan

Blender work is headless bpy 5.2.3 (F-A5): procedural and base meshes, armatures, skinning, keyframes, batch FBX exports (one clip per FBX plus a rig-only FBX; Unit System None, FBX unit scale, Z forward, Y up, no leaf bones, bake animation on; F-A5 settings table). Hand sculpting and viewport look-dev are not possible here, which is why the semi-realistic hero assets carry the art-quality risk R13.

### 5.1 Priority order and budgets

| # | Asset | LOD0 tris | Bones | Textures | Clips | Placeholder until it lands |
|---|---|---|---|---|---|---|
| 1 | **Squirrel rig** (regular), 1.2 st at the shoulder (B§2) | body <= 8k; fur cards or shells <= 5k as a second skinned MeshPart (F-B(g)) | about 38: Root (no weights), Hips, Spine1-3, Neck, Head, Jaw, Ear L/R x2, Tail1-8, 4 legs x 4 | SurfaceAppearance 1024^2 colour, normal, roughness; fur-card atlas 512^2 with alpha | **B§7 seven:** Run, Climb, WireTraverse, Leap, Pounce (with wind-up, commit and recover markers), BiteDance, Sneak. **Support:** Idle, Trot, ClimbIdle, Land, Feint, HitReact, Knockdown, Forage, Eat, StinkFire, KnotholeEnter | Lune Part rig with RigSpec names, procedural gait (SQ§24 cadences) |
| 2 | **Spicy rodent variant**: same skeleton; zombie-lite mangy body (stitched bald patches, a few ribs), natural fur colours (no green), blood on muzzle and claws, oversized bloodshot eyes, crazed buck-tooth grin | + head variant <= 1.5k | same | own 1024^2 set; emissive mask for eyes | same seven plus StalkIdle, Feint, Death | regular placeholder with red eyes |
| 3 | **Human bodies**, semi-realistic custom R15 (no cages; uniforms do not need layered clothing): 3 builds x 2 presentations, plus an older-adult variant for the two housewife defenders | <= 10k per body | R15 Motor6D | per-role 1024^2 atlas with TintMask accent regions | R15 locomotion set plus about 25 custom: kick, swing, flinch, back away, flee, baton strike, rolling-pin and broom strikes, treat, carry, write ticket, argue, mediate, sit-drive, enter/exit car, pry door, inspect, cower, bitten react, infected shamble, knockdown | Roblox default R15 with role body colours and rigid accessories |
| 4 | **Role outfit kit**: townsperson x 6, police, doctor, nurse, guard, orderly, EMT, cyclist, jogger, mail carrier, shop staff (chef, barber, grocer), burglar, mime | accessories <= 1.5k each | rigid | shared atlas | none | coloured blocks on attachments |
| 5 | **Patrol car** (drivable, light bar, seat) and civilian sedan | <= 6k | wheels as parts | 1024^2 | none (client wheel spin) | box car |
| 6 | **Hollow trees**: H1 spiral ramp, H2 climb shaft with nook, 9 knothole trunks (3 variants), fallen-log tunnel | <= 20k per MeshPart, split into trunk shell, interior, canopy | none | bark 1024^2 or MaterialVariant | none | graybox shafts with the real route geometry |
| 7 | **Fox** | <= 7k + 2k cards | about 36 | 1024^2 | Idle, Walk, Trot, Run, Stalk, Lunge, Repelled, Sniff, Sit | Part rig |
| 8 | **Deer** (doe, buck via antler accessory, fawn by scale) | <= 9k | about 40 | 1024^2 | Idle, Graze, Walk, Trot, Gallop, Startle, Alert, Bound, LieDown | Part rig |
| 9 | **Drone** | <= 3k | none | 512^2 | none (client rotor spin) | box with props |
| 10 | **House kit**: 8 archetypes (bungalow, two-storey, Victorian, ranch, split-level, cottage, apartment block, large older house) as modular pieces with paint, trim, porch, roof and yard variants (B§3) | <= 15k per house | none | tiling MaterialVariants (images uploaded headless) plus MeshPart colour | none | graybox archetype builders |
| 11 | **Interior kit** (about 30 furniture pieces) and hospital/police interior kits (beds, stations, shelves, 12 readable pharmacy items) | <= 1k each | none | atlas 512^2 | none | blocks |
| 12 | **Other vehicles**: ambulance, delivery van, ice-cream van, trolley, dump truck, RV, motorcycle, bicycle | <= 10k | none | 1024^2 | none | boxes with the TR§1 logical dimensions |
| 13 | **Shops and restaurants kit**, Quay kit (about 6 modular pieces, WD§16), Galleria | per lot <= 15k | none | MaterialVariants | none | graybox |
| 14 | **Props**: feeders, trash cans, dumpsters, garden beds, nut caches, hydrants, stop signs, signals, meters, poles (wires as Beams) | <= 1k | none | shared 512^2 atlas | none | primitives |
| 15 | **Backdrop**: mountain, hill and plain bands with baked aerial perspective, tree-line cards, ocean plane, beach, pier, marina boats, radio tower with blinking lights on the measured sunset azimuth (WD§14.4) | far meshes <= 20k each | none | 1024^2, vertex colour | none | terrain hills and a flat ocean |
| 16 | **Ambient**: birds, butterflies, dragonflies, rabbits, cats, dogs | <= 1.5k | small | 256^2 | small loops | client primitives |
| 17 | **Moon phase textures** (30) and skybox | n/a | n/a | 512^2 each, rendered in Python | n/a | engine default moon |

### 5.2 Placeholder strategy

- **Contract first.** `RigSpec` fixes bone names, attachments, hitbox and clip names. Lune generates placeholder rigs that satisfy it, so swapping in real art is a template change, never a code change.
- **Procedural animation as a permanent fallback.** `AnimDriver` drives Motor6D or Bone transforms from the same state machine when a clip is missing, so the FRB plays with zero published clips.
- **Graybox world from the same builders.** Archetype builders produce graybox with correct footprints, doors, rooms, roof and route geometry; the art pass replaces the mesh source while routes, colliders and nav stay put.
- **Must-replace list** (gates W4): squirrel, rodent, human bodies and outfits, fox, deer, patrol car, hollow trees, house kit, hospital interior. Everything else may ship as stylised graybox if time runs short (owner decision).
- **Owner review loop:** headless preview renders (if S6 confirms rendering works) plus an in-Studio look per asset; the owner may decide to source CC-licensed base meshes or commission the hero assets (R13).

---

## 6. Testing

### 6.1 Lune unit tests (container and CI, every commit)

| Suite | What it proves |
|---|---|
| `RouteMath` | Samples equal the HTML dump within 0.01 u for all 1,332 routes; arc-length parameterisation |
| `RouteMotion` / `Junctions` / `Forks` | v5.4 scoring constants (RM verification log items 26-34) as table tests |
| `SquirrelMotion` | Leap apex 2.73 u and airtime 0.853 s (RM log 21); speed caps; transfers; envelope function used by the validator |
| `Swept` | 10,000 golden vectors from the JS function; rotation sub-steps; teleport and stationary rules |
| `TerrainHeight` | Golden grid |
| `Roles` | One test per B§6 sentence (3.4 transitions), slot caps, rank formulas, side exits |
| `Combat`, `Infection`, `Foraging`, `Hollows`, `Stink` | Windows, damage (two kicks kill without recovery, defender one-shot at low health), infection share cap 25, 70% ownership, 95% fire threshold and 30-point cost |
| `Clock`, `Calendar`, `Moon` | Winter every 5 weeks for 1 week; raid week; 29.53-day phases (new, waxing, full, waning) |
| `BlendRules` | Palette clamp; neon only as one accent; regions per species |
| `Packets` | Encode/decode round trips; payload sizes under caps |
| Data validators | Section 3.1 counts and rules; route graph connectivity |
| Place tests | Lune opens the built `.rbxl`: Workspace/Players properties (1.2), lot count equals data, every actor template has `PrimaryPart` and `Atomic`, no SurfaceAppearance in the place (keeps API publishing valid) |

### 6.2 Open Cloud Luau Execution integration tests (real engine, no physics, no auto-running scripts)

- **Flow:** `rojo build` -> save an **unpublished** place version through Open Cloud -> one task per suite group (at most 5 creations per minute and 10 incomplete tasks per place, 5-minute runtime, 4 MB return, F-B(d)) -> a `TestRunner` ModuleScript in `ServerStorage.Tests` returns JSON results -> `run_cloud_tests.luau` fails the run on any failure.
- **Suites:** boot (require every ModuleScript); ActorService possess/release with `PlayerHandle` test doubles (Luau Execution has no Players); Roles event sequences; traffic stepped manually for 120 simulated seconds (0 deadlocks, scripted run-over and jump-over scenarios); AI scheduler step cost at full population (performance regression gate against the S4 baseline); WorldGen engine checks (collisions, `CanQuery`, door hinges); DataStore wrapper on test keys; avatar description fetch and blend for 10 fixed user IDs; RigSpec validation of every runtime-loaded asset ID.
- **Cadence:** every wave sub-step exit, before every owner playtest, and nightly during W2-W3 if a scheduled task is wanted.

### 6.3 Owner playtest checklists (multi-client in Studio)

Each checklist in `docs/owner/` is click-by-click with one action per line, an expected result and a pass/fail box. The style:

1. Open Roblox Studio. Click **Spicy Rodents** under Recent (or File, Open from Roblox).
2. Click the **Test** tab. In **Clients and Servers**, choose **Local Server** and **3 Players**. Click **Start**.
3. Three player windows open. In **Player1**, press **F2**. The dev panel opens.
4. Click **Play as: Spicy Rodent**. Expected: within 2 seconds you control a running squirrel with red eyes.
5. Hold the right mouse button. Expected: the view goes low and close (stalk).
6. ...

| Checklist | When | Length |
|---|---|---|
| `00_setup` | W0 | about 20 min |
| `01_spike_checklist` | W1 | about 40 min, includes one live-server join |
| `02_frb_playtest` | W2 | about 60 min, all 8 roles |
| `03_breadth_playtest` | W3 | about 60 min |
| `04_art_review` | per asset batch | 10-20 min |
| `05_live_test` | W5 | 45 min with 10+ friends |

Automated stand-ins reduce owner load: fake drivers (server-side scripted controllers) and virtual interest points exercise possession, AI tiers and traffic in every Studio session.

---

## 7. Risks, mitigations and owner decisions

### 7.1 Risk register (ordered by threat to the project)

| # | Risk | Likelihood / impact | Spike | Mitigation | Fallback |
|---|---|---|---|---|---|
| R1 | **Possession handoff mid-stride** looks broken (pops, T-pose, lost momentum, animation replication quirks, bodies destroyed on character swap) | Medium / Critical: B§4 is a hard rule | S1 | `PlayerCharacterDestroyBehavior = Disabled`; snapshot with velocity and clip time; matched cross-fade; streaming pre-request; Animator created server-side (F-B(a) pitfall 2) | Blink handoff; server-sim animals; Server Authority |
| R2 | **Client-owned rails are cheatable or the validator rejects honest play** under latency | Medium / High | S2 | Shared pure step; envelope checks; leaky buckets; cheat harness in CI | Server-authoritative rails with prediction |
| R3 | **Fatal traffic unfair under latency**, especially player car vs player rodent | Medium / High | S3 | Exact port with golden vectors; pose ring buffers and rewind; teleport resets; stationary never kills | Server-view test with wider pad; kinematic player cars |
| R4 | **AI scale** blows the server frame budget at 50 players | Medium / High | S4 | Kinematic anchored AI; tiers; time slicing; `BulkMoveTo`; client-only ambient life; ghost vehicles | Parallel Luau; fewer ambient bodies |
| R5 | **Drone's far view** shows holes (SLIM needs static baked geometry; terrain may vanish beyond the streaming radius) | Medium / High: the drone "justifies the backdrop" (B§10) | S5 | Bake static lots; SLIM; Persistent landmarks; drone `ReplicationFocus` | Far-Town impostor (built anyway) |
| R6 | **Skinned custom rigs and animations** fail headless; Studio import has flipped joints; ownership errors | Medium / Medium | S6 | Headless KeyframeSequence upload; RigSpec checks; everything owned by the experience owner (F-B(c) ownership) | Studio import guides; procedural animation |
| R7 | **Avatar data** too thin or restricted for a good 70/30 blend | Medium / Low-Medium | S7 | Body colours plus accessory-type mapping; hidden-dummy accessory loading | Colours-only; player colour picker |
| R8 | **No type checker in the container**: runtime type errors slip through | High / Medium | S8 | Strict mode; CI `luau-lsp`; boot test in the real engine; Lune require-graph test | Container source build if allowed |
| R9 | **Open Cloud not reachable** from the container or rate limits slow CI | Medium / Medium | W0 | Batch suites into few tasks; poll politely | Run Open Cloud steps in GitHub Actions |
| R10 | **Persistence misread**: building cross-server DataStores nobody asked for | Low / Medium | S9 | Server-lifetime per B§6 and B§8 | Per-key switch to DataStore |
| R11 | **Combat duel feels random** under latency (windows of 0.2-0.6 s vs about 150 ms RTT) | Medium / High: "the role everyone wants" | S2, FRB | Server resolution with rewind; client telegraphs; RTT-widened windows; all tunables live in the dev panel | Fixed input-buffer windows |
| R12 | **Content volume** (40 interiors, 8 archetypes, about 2x restaurants, 13 lot types, 11 hollows, expanded hospital) overwhelms the schedule | High / Medium | n/a | Kit-based builders driven by data; interiors from room templates; graybox acceptable for non-hero lots | Owner trims the must-replace list |
| R13 | **Art-quality ceiling** of headless Blender for semi-realistic hero assets (fur that catches light, muscle, a tail that lags; B§7) | High / Medium | S6 render test | Normal and roughness maps plus fur cards (F-B(g)); procedural tail spring; preview renders for owner review | Owner sources CC-licensed base meshes or commissions the squirrel, rodent and humans |
| R14 | **Owner bandwidth**: too many Studio steps for a non-programmer | Medium / Medium | n/a | Place built and saved from git; owner opens from the cloud; short checklists; automated stand-ins | Owner-assisted remote session for any blocked step |
| R15 | **Ephemeral container** loses tools and long setups | High / Low | W0 | Environment setup script installs the pinned toolchain; everything in git | Tool-cache branch with prebuilt binaries |
| R16 | **Experience ownership mismatch** (group vs user) breaks animations | Low / High | S6 | Decide once in Step 0; all uploads under that creator | Re-upload under the right creator |
| R17 | **Content maturity**: blood, horror, zombie theme, v5.4 profanity (WD§16, HA§15) | Medium / Medium | n/a | Remove profane lines; keep blood light; answer the maturity questionnaire accurately | Tone down rodent textures via a variant |
| R18 | **Queue scarcity**: Roblox spins up servers on demand, so the rodent queue may never be "real" (B§5) | Medium / Low | n/a | Server Fill set to maximum so servers fill to 50 | Matchmaking place with reserved servers (large; later) |
| R19 | **Day length**: about 71 s per day makes sunsets 2-3 s long (WD§17.2) | High / Low | n/a | Non-linear day curve that holds sunrise, golden hour and sunset | Longer day and shorter winter cycle |

### 7.2 Owner decisions still needed

**Before Wave 0:**

1. **Spike checklist.** Approve the W1 spike checklist (about 40 minutes in Studio before the bulk build), or fold it into the FRB playtest and accept later discovery of a failed spike.
2. **Experience owner.** Your user account (simpler) or a group (needed only if others will co-own); every asset and animation must be created under the same owner.
3. **Compass and backdrop.** Proposed: +Z is north (matches district names), ocean to the north at the river mouth with the marina, mountains to the south and west, radio tower on the measured sunset azimuth (WD§14.4, WC§17.1).
4. **Squirrel scale.** Follow the brief's 1.2 st shoulder height (about 1.9x the HTML squirrel relative to humans) and re-tune contact radii (SQ§26, RM§21.1). Recommended: yes.
5. **Day length.** Default 72 real seconds per in-game day with a non-linear curve (about 50 minutes per winter cycle, a lunar month in about 35 minutes).
6. **CI and key placement.** Allow GitHub Actions for strict type checking; allow the Open Cloud key as a GitHub secret if the container cannot reach Open Cloud.

**Before Wave 2:**

7. **Queue mechanics.** Do humans opt in to hospital, police or squirrel? Is tier 2 required before squirrel? How is the 7-slot squirrel queue ordered against tier 2?
8. **Infection unit and hidden win.** Per-actor infection with town % (recommended); the critical-mass threshold; whether infecting staff is required or only slows cures; whether anyone sees an infection meter (HP§13.1-3).
9. **Combat.** Remove the v5.4 perfect counter and pounce immunity (B§8 inverts them, SQ§25.2); health numbers; whether the air pounce stays an air-dash (RM verifier #1).
10. **Traffic deaths beyond the rodent.** Can regular squirrels, deer, the fox or humans be run over? Does a player driver get the human-kills-rodent promotion (TR§14.2-3)?
11. **Sightings audience.** Police and drone only, or hospital too; marker lifetime (A1 confirm).
12. **AI patrol cars** keep running for AI officers (A1 confirm).
13. **Which 40 houses** have interiors (WC§17.3; proposed: the 36 existing dwelling lots upgraded to the brief's archetypes plus at least 4 new expansion lots) and which 3 get defenders.
14. **Hollow trees.** Confirm H1-H11 (WF§6.5), spiral ramp in H1 and climb shaft in H2, and the fallen-log tunnel as an extra non-territory shelter.
15. **Remodel points.** B§8 says "each real day of play"; servers rarely live several real days. Proposed: per in-game day played, or per real hour.
16. **HTML extras.** Keep, drop or re-skin: chili hunt, fashion stand, coins, Galleria wishing fountain, cats, rabbits, dogs, idle predator, trampoline, sewer (SQ§27, WF§16).
17. **Child characters.** Keep the five kid cyclists AI-only (not possessable)?
18. **Avatar colour picker.** Allow players with low-signal avatars to choose two accent colours?

**Before Wave 4 or Wave 5:**

19. **Art sourcing.** Headless Blender only, or allow CC-licensed base meshes or a commissioned artist for the squirrel, rodent and humans.
20. **Must-replace list.** Confirm which assets must be final art at launch.
21. **Content maturity.** Target rating for "a little blood" and horror; approve removal of profane lines.
22. **Server Fill** set to maximum to make the rodent queue real.
