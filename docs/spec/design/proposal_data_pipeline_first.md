# Spicy Rodents on Roblox: build proposal, "data and content pipeline first"

Status: proposal for the owner's order-of-operations discussion. No game code has been written.
Date: 2026-11-09.

Sources, all under `/home/user/spicy-rodents`:

- `reference/Roblox_Rebuild_Brief.txt` (the brief)
- `spec/BRIEF_ADDENDUM.md` (the addendum, which wins on conflicts)
- `spec/roblox_feasibility.md`
- the eight subsystem specs: `spec/worldgen_core.md`, `spec/worldgen_districts_art.md`, `spec/routes_movement.md`, `spec/traffic.md`, `spec/squirrel_abilities_progression.md`, `spec/humans_actors.md`, `spec/hospital_police_infection.md`, `spec/wildlife_foraging.md`
- the seven data files in `spec/data/`

Every listed file was present and was read. Citations use the form `file §section`.

---

## 0. The pitch

The town, its climbing routes, traffic lanes, jobs, forage sources, interiors and art slots all come out of a compiler that reads data. Geometry is just a view of that data.

The plan builds the pipeline first:

```
v5.4 HTML -> harvest -> JSON -> Lune compile -> generated Luau data -> bake -> place -> Open Cloud -> tests
```

The first runnable build then comes off that pipeline. It contains:

- the whole town from data, including the full neighbourhood expansion and all 40 house interiors, as blockout geometry;
- all 1,332 v5.4 climbing routes, harvested exactly;
- every one of the 8 roles (human, hospital staff, police, drone, regular squirrel, spicy rodent, fox, deer), playable on "puppet" rigs that need no Studio import.

After that, art drops in by editing the asset manifest, with no code changes.

**Three rules hold the whole plan together.**

1. **Data is the single source of truth.**
   - It is JSON in HTML units, so every number can be checked against the spec line by line.
   - It is compiled to studs exactly once.
   - Nothing in the world is placed by hand in Studio (brief §2).
2. **Visual follows data.**
   - The Luau blockout builders and the Blender kit generators read the same lot, archetype and route JSON.
   - Hand-authored hero assets (squirrel, premium hollow trees) export their sockets and route curves back into data as named empties and curves.
   - So the rails a squirrel climbs and the bark it is drawn on cannot drift apart.
3. **The saved place is always rebuildable from git.**
   - Anything Open Cloud place saving cannot carry is kept out of the saved place: SurfaceAppearance, unions, BaseWrap and EditableMesh (`roblox_feasibility.md` §B.d).
   - Those assets are loaded at runtime from model assets the owner publishes, listed in the manifest.
   - So Claude can save every build headlessly and the owner never touches git or a terminal.

---

## 1. Architecture

### 1.1 Repository and Rojo tree

The repo is the new private GitHub repo `spicy-rodents-roblox`. Large binaries go in Git LFS (owner decision O13).

```
spicy-rodents-roblox/
  default.project.json        game place (rojo build -> build/SpicyRodents.rbxl)
  plugin.project.json         SpicyTools Studio plugin (-> build/SpicyTools.rbxm)
  rokit.toml                  pinned tools for the Mac (rojo 7.7.1, lune 0.11.1, stylua 2.6.0, selene 0.31.0, luau-lsp)
  selene.toml  stylua.toml  roblox.yml (committed; feasibility §A Selene gotcha)
  ci.sh                       one entry point: fmt -> lint -> unit -> harvest-check -> compile -> bake -> build -> cloud
  reference/                  pinned v5.4 HTML + SHA-256 (fc48b387...6227), used only by tools/harvest
  data/                       AUTHORED SOURCE DATA (JSON, HTML units)
    schema/                   JSON Schemas for every file below
    harvest/                  machine output of tools/harvest (never hand-edited)
    town/lots/*.json          one file per district (core, outer, east, estates, north, westside, hospital, quay, galleria, southeast, coast)
    town/roads.json  town/intersections.json  town/utility.json  town/trees.json  town/hollows.json  town/dressing.json
    lot_types/*.json          one file per lot type (house_bungalow, shop_barber, restaurant_pizza, school, marina, ...)
    archetypes/houses/*.json  8+ house archetypes (dimensions, sockets, route templates, flair axes)
    interiors/*.json          interior templates (rooms, doors, furniture slots, hide spots, nav)
    buildings/hospital.json  buildings/police_station.json   (room programs)
    traffic/vehicles.json  traffic/fleet.json  traffic/drivers.json
    cast/roles.json  cast/outfits.json  cast/bodytypes.json  cast/named.json
    wildlife/*.json           fox, deer, birds, insects, nests, apple trees (from spec/data/wildlife.json)
    quests/*.json             police, hospital and shop job definitions
    backdrop/backdrop.json    bands, ocean, tower, overflight
    assets/manifest.json      logical asset name -> {lane, status, ids, budgets, sockets file}
  generated/                  COMPILER OUTPUT, committed; CI fails if stale
    data/*.luau               compact runtime data (studs), chunked <= ~1 MB per module
    reports/*.md              counts, connectivity, budgets, diff vs v5.4
  src/
    shared/   -> ReplicatedStorage.Shared       (pure modules; most also run under Lune)
    server/   -> ServerScriptService.Server
    client/   -> StarterPlayer.StarterPlayerScripts.Client
    worldgen/ -> ServerStorage.WorldGen          (builders; run by Lune, by the Studio plugin and by the server)
    plugin/   -> SpicyTools plugin source
  assets/     -> ReplicatedStorage.Assets         (generated .rbxm/.model.json: puppet rigs, KeyframeSequences, kit templates)
  art/                        Blender sources (.blend, LFS) + bpy scripts; FBX are build artefacts, not committed
  tools/
    harvest/   node + headless Chrome (google-chrome is installed here; a scratch run already dumped 1,332 routes and 95 fork trunks)
    compile/   lune: validate + expand + link + emit generated/
    bake/      lune: generated data -> build/world/*.rbxm via src/worldgen
    blender/   bpy 5.2.3: rig/clip export, kit generators, tree-from-routes, sockets export, budget checks
    textures/  python: moon phases, clothing templates, map render, sign atlases
    cloud/     lune + curl: Open Cloud upload, place save, Luau Execution runner, ID harvest
  tests/
    unit/      lune specs (pure modules)
    cloud/     Luau Execution suites (real engine, headless)
    playtest/  owner checklists (markdown, click-by-click)
  docs/README.md   module layout + "how to add a lot type, a route, a role" (brief §14)
```

`default.project.json` essentials, all settable from the project file per feasibility §B.a and §B.h:

| Path | Setting |
|---|---|
| `ReplicatedStorage.Shared` | `$path src/shared`, with child `Data` -> `generated/data` |
| `ReplicatedStorage.Assets` | `$path assets` |
| `ServerStorage.WorldGen` | `$path src/worldgen` |
| `ServerScriptService.Server` | `$path src/server` |
| `StarterPlayer.StarterPlayerScripts.Client` | `$path src/client` |
| `Workspace.World` | `$path build/world`, produced by bake; absent means a runtime bake (D1) |
| `Workspace` properties | `StreamingEnabled=true`, `ModelStreamingBehavior=Improved`, `StreamOutBehavior=Opportunistic`, `PlayerCharacterDestroyBehavior=Disabled`, `SignalBehavior=Deferred` (forward-compatible with Server Authority), `FallenPartsDestroyHeight=-60` (below the sewer floor at -3.4 u = -8.5 st) |
| `Players` | `CharacterAutoLoads=false` |
| `Lighting` | `Technology=Future` |

### 1.2 Boot sequence (server)

`Main.server.luau` is the only file that starts loops. Every service exposes `init(ctx)` and `step(dt, now)`, so Luau Execution tests can drive services without auto-running scripts (feasibility §B.d says Server and Local scripts do not run there).

1. `Data` loads generated modules. `Tunables` mirrors itself to Attributes.
2. `WorldGen.ensureWorld()` checks `Workspace.World:GetAttribute("BakeHash")` against `Data.bakeHash`. If it is missing or stale, the builders run at runtime (fallback, D1). `WorldGen.buildTerrain()` always runs, writing voxels from the analytic height (D1).
3. `Assets.preload()`: `InsertService:LoadAsset` for every manifest entry in the runtime-loaded lane. Missing assets fall back to the puppet or blockout template.
4. Static registries: `Routes.Registry`, `Routes.Graph`, `World.Colliders`, `AI.Nav`, `Traffic.Graph`.
5. `Actors.populate()` spawns the AI bodies: about 50 humans, 12 squirrels, 1 rodent, 4 deer and 1 fox, plus the device actors (drone and patrol cars).
6. Services `init` in dependency order, then the Heartbeat scheduler starts.
7. Only now does `Players.PlayerAdded` possess bodies (RoleService).

### 1.3 Module catalogue

"L" means the module is pure and also runs under Lune (unit-testable in the container).

#### `src/shared` -> ReplicatedStorage.Shared

| Module | Responsibility | Public interface | Data it owns |
|---|---|---|---|
| `Config/Units` (L) | HTML-unit/stud conversion; facing to yaw; lot transforms | `st(u)`, `u(st)`, `yawFromFacing(f)`, `lotCFrame(lot)` | `STUDS_PER_UNIT = 2.5` (brief §2) |
| `Config/Tunables` (L) | Every gameplay number, with unit, range and spec source. Mirrored to Attributes on `ReplicatedStorage.TunablesLive` so the owner can tweak values live in Studio's Properties panel during a playtest | `get(path)`, `onChanged(path, fn)`, `snapshot()`, `applyOverrides(tbl)` | Tunables table (§3.10) |
| `Clock` (L) | In-game time, derived from `workspace:GetServerTimeNow()` plus two replicated attributes | `now()`, `day()`, `dayFraction()`, `phase()`, `week()`, `isWinter()`, `moonAge()`, `moonLit()` | epoch, `secondsPerDay`, non-linear day curve (districts_art §14.3) |
| `Net` | Single declaration of every remote: typed payload checks, per-player rate limits, reliable / unreliable-batched | `Net.Event.<Name>:Fire/Connect`, `Net.Func.<Name>:Invoke`, `Net.Stream.<Name>:Push/Subscribe` | `Net/Schema` table |
| `Data` (L) | Read-only accessors over the generated data; decodes chunked JSON once | `lots()`, `lot(id)`, `lotType(t)`, `routes()`, `trafficGraph()`, `nav()`, `colliders()`, `forage()`, `hollows()`, `map()`, `cast()`, `wildlife()`, `assets()`, `bakeHash` | `generated/data/*` |
| `World/Height` (L) | Analytic terrain, river, bridge deck and ground at a reference height. Fixes the global-y quirk (routes §Added by verifier 5) | `terrain(x,z)`, `ground(x,z,refY)`, `riverCenter(z)`, `deckAt(x,z)` | worldgen_core §3 formulas, verbatim |
| `World/Colliders` (L) | Data colliders (AABB, OBB, circle, segment) in a spatial hash, for server AI, the squirrel controller and validation | `query(box)`, `blocked(p0, p1, r, refY)`, `roofAt(x, z, refY)` | compiled collider sets |
| `Math/{CatmullRom, ArcLength, SpatialHash, OBB, Swept}` (L) | Centripetal Catmull-Rom with three.js r160 end extrapolation; arc-length tables; the `sweptVehicleHit` port | `CatmullRom.new(pts)`, `:pointAt(t)`, `:tangentAt(t)`, `Swept.hit(P0,P1,V0,V1,psi0,psi1,W,L,H)` | none |
| `Routes/Registry` (L) | Route registry: curves, samples at `max(20, ceil(3L))`, 20-stud spatial index (routes §1) | `get(id)`, `pointAt(id,t)`, `tangentAt(id,t)`, `advance(t,dir,fw,dt,speed,len)`, `nearest(pos, maxDist, excl)`, `byLot(lotId)` | none (built from `Data.routes`) |
| `Routes/Graph` (L) | Precompiled end-links, forks, transfers and hollow/knothole nodes | `endLinks(id, atStart)`, `forks(trunkId)`, `transfers(id,t)`, `junctionCandidates(id,t,pos)`, `knotholes(hollowId)` | none |
| `Routes/Kinds` (L) | Per-kind behaviour: speed multiplier, visual offset, camera distance, clip | `Kinds[kind]` | trunk, branch, bridge, lookout, roof, wire, fence, trampoline, plus new hollow, ramp, tunnel, duct, chamber |
| `Actors/Species` (L) | Species definitions and actor attribute names and states | `Species[s]`, `Attr.*`, `State.*` | human, squirrel, fox, deer; plus `device` (drone, car seat) |
| `Roles/Ladder` (L) | **The** promotion ladder (brief §6). Nothing else states it | `rungs`, `sideExits`, `rankHuman(stats)`, `rankSquirrel(stats)`, `transition(event, ctx)`, `slotsFor(state)` | rungs, slots, rank weights, transition table (§3.9) |
| `Combat/Rules` (L) | Duel phases and outcome functions (brief §8 combat dynamics) | `phases`, `resolve(attack, defend)`, `damage(src, ctx)`, `zigzag(history)`, `feint(ctx)` | none (numbers live in Tunables) |
| `Infection/Rules` (L) | Town %, squirrel maturation, cure-time multiplier, hidden-win test | `townPct(s)`, `cureTime(base, nInfectedStaff)`, `critical(s)` | none |
| `Seasons/Calendar` (L) | Weeks, the winter cycle and moon age (the feasibility `Moon.luau` is reused) | `calendar(day)`, `moon(day)` | none |
| `Foraging/Rules` (L) | Yield, cooldown, risk inputs, hollow meter, stink gland | `yield(src, now)`, `meter(h)`, `owner(h)`, `stinkReady(pct)` | none |
| `Avatar/Blend` (L) | 70/30 blend maths: colour extraction, clamp to town palette, signature-feature choice | `traits(desc)`, `humanRecipe(stock, traits)`, `animalTints(stock, traits)` | clamp targets: saturation <= 0.55, value 0.39-0.91 (districts_art §11, §15) |
| `Map/Projection` (L) | World/map transforms, marker kinds | `toMap(v)`, `Marker.*` | none |
| `Quests/Defs` (L) | Typed views of `data/quests/*.json` | `Defs[id]` | none |
| `UI/Theme` | Palette, fonts, sizes | `Theme.*` | UI palette (districts_art §11) |

#### `src/server` -> ServerScriptService.Server

| Module | Responsibility | Public interface | Data it owns |
|---|---|---|---|
| `Main.server` | Boot order (§1.2) and the scheduler loop | none | none |
| `WorldGen/Runtime` | Bake-hash check; runtime bake fallback; terrain voxels | `ensureWorld()`, `buildTerrain()` | `Workspace.World` |
| `Assets/Service` | Manifest resolution; runtime `LoadAsset` of hero models; template cache; fallback to puppet or blockout | `preload()`, `template(name)`, `status(name)` | ServerStorage template cache |
| `Actors/Registry` | One actor model per species; bodies are created once and never destroyed | `spawn(species, cf, opts)`, `get(id)`, `each(filter)`, `setBrain(id, brain)`, signals `Possessed`, `Released`, `Died` | actor table, body Models |
| `Actors/Possession` | Mid-stride handoff (feasibility §B.a pattern) | `possess(player, actorId)`, `release(player)`, `swap(player, toId)` | ownership map |
| `Actors/Validation` | Leaky-bucket checks per species (speed per route kind, legal transfers, no wall crossing) | `accept(actorId, packet) -> ok, correction` | per-actor buckets |
| `AI/Scheduler` | Brain tick tiers by distance to the nearest player (near 10 Hz, mid 4 Hz, far 1 Hz "commute"), round-robin within a frame budget | `register(actorId, brain)`, `setTier(...)`, `stats()` | tier queues |
| `AI/Brains/*` | Pedestrian, Resident, Worker, HospitalStaff, Patient, Officer, Medic, Driver, Arguer, Burglar, Vigilante (an overlay flag), Defender, Squirrel, Rodent, Fox, Deer | `brain.new(actor)`, `:tick(dt, ctx)` | brain state |
| `AI/Perception` | Spatial-grid threat queries; spotting rules ported from humans §5.3 with height above ground | `spotted(observer, target)`, `nearby(pos, r, filter)` | grid |
| `AI/Nav` | Waypoint graph: sidewalks, crosswalks, lot doors, interiors, hospital and police rooms; A* with a cache | `path(from, to, opts)`, `nearestNode(pos)` | `Data.nav` |
| `Roles/Service` | Applies the Ladder: queue, slot accounting, promotions, side exits, dev picker | `request(player, roleId)`, `onEvent(evt)`, `queue()`, `rankOf(player)` | per-server rank stats |
| `Combat/Service` | Server resolution of pounce, bite, kick, baton and blows; health; death | `pounceStart(actor, pkt)`, `kick(actor)`, `blow(actor, kind)`, `health(actorId)` | health, windows, cooldowns |
| `Infection/Service` | Per-actor infection, town %, maturation, hidden win, session reset | `infect(actorId, src)`, `cure(actorId, by)`, `townPct()` | infection state |
| `Hospital/Service` | Admissions, stations, disinfect loop, fetch tasks, performance metric, upgrades, in-building staff kills | `admit(actorId)`, `stationUse(player, stationId)`, `fetchTask(player)`, `perf()` | wards, stations, item shelves |
| `Police/Service` | Officer slots (5 -> 8), AI dispatch backfill, baton, tickets, drone unlock, top-two car assignment | `officers()`, `assignCars()`, `issueTicket(player, target, kind)`, `unlock(level)` | police state |
| `Drone/Service` | Drone device actor, pilot binding (the pilot's human body is seated at the station console), spot-and-mark, vigilante call | `launch(player)`, `land(player)`, `mark(player, pos)` | drone state, mark cooldowns |
| `Traffic/Service` | Lane simulation on the compiled graph: stop control, signals, parking, violations, fender benders | `step(dt)`, `vehicles()`, `speedOf(id)`, `spawnEvent(kind)` | vehicle states |
| `Traffic/Collision` | Server swept test every tick, with a 1 s pose ring buffer for lag compensation (traffic §13) | `step(dt)`, `teleported(entityId)` | ring buffers |
| `Vehicles/PlayerCars` | Patrol cars for the top two officers: enter, exit, drive, siren and lights; ownership; validation | `enter(player, carId)`, `exit(player)`, `toggleSiren(player)` | car seats |
| `Sightings/Service` | Marker store with TTL and per-role visibility; radar feed | `report(kind, pos, conf, src)`, `markersFor(player)` | markers |
| `Quests/Service` | Generic job and quest engine plus providers (police side quests, hospital fetch, shop jobs) | `offer(player)`, `accept(player, q)`, `progress(q, evt)`, `complete(q)` | live quests |
| `Economy/Credits` | Credits and upgrade purchases (brief §13) | `grant(player, n, why)`, `spend(player, n, item)` | balances |
| `Homes/Service` | 40 claimable homes; remodel points per real day; remodel state for the server's lifetime (brief §8) | `claim(player, lotId)`, `remodel(player, slot, option)` | home state |
| `Interiors/Service` | Door hold/open/passable states (worldgen_core §13), hiding spots, defender triggers, burglar entries | `door(lotId, doorId)`, `hide(actorId, spotId)`, `chaseInside(lotId)` | door and spot state |
| `Seasons/Service` | Owns the clock epoch; winter transitions; winter-end survival check | `setTimeScale(s)`, `onWinterEnd(fn)` | epoch |
| `Foraging/Service` | Forage sources, cooldowns, nuts, hollow meters and ownership, premium weekly raids, stink gland | `take(actorId, srcId)`, `store(actorId, hollowId, n)`, `stink(actorId)` | forage and hollow state |
| `Wildlife/Service` | Server-side animals not driven by Actors (rabbits, cats and dogs if kept); seed broadcast for client fauna | `seed()`, `step(dt)` | ambient state |
| `Avatar/Service` | Fetches `HumanoidDescription`, applies the blend on possess, reverts on release | `apply(actorId, userId)`, `revert(actorId)` | blend cache |
| `Persistence/Profiles` | DataStore profile per UserId: wardrobe, settings, lifetime stats | `load(player)`, `save(player)` | profile cache |
| `Admin/Dev` | Dev role picker (Studio or the owner's allowlist only), debug commands, test hooks | `enabled(player)` | none |
| `Telemetry` | Frame budget, AI ms, actor counts, net bytes | `sample()` | counters |

#### `src/client` -> StarterPlayerScripts.Client

| Module | Responsibility | Public interface |
|---|---|---|
| `Main.client` | Wires controllers to the possessed species | none |
| `Controllers/Squirrel` | Rail plus ground kinematic controller (routes §5-§13), leap, pounce input, knothole and hollow entry | `start(actor)`, `stop()` |
| `Controllers/Human` | Humanoid controls plus kick, swing, interact, work-spot actions | `start(actor)`, `stop()` |
| `Controllers/Animal` | Fox and deer kinematic ground controller | `start(actor)`, `stop()` |
| `Controllers/Drone` | Full flight, camera feed, mark | `start(device)`, `stop()` |
| `Controllers/Car` | VehicleSeat input, siren and lights, radar gun | `start(car)`, `stop()` |
| `Camera/Rigs` | Per-mode rigs: squirrel trunk/branch/wire (routes §15), human, drone, car; spherecast occlusion | `set(mode, subject)` |
| `Animation/Driver` | Per-species state-to-track map (same table for AI and players), tail spring chain, foot IK near the camera | `bind(actor)`, `setState(s)` |
| `Render/Interp` | Interpolates AI actor and vehicle streams, about 100 ms behind | `subscribe(stream)` |
| `World/Local` | Interior roof hiding, door visuals, interior prop distance hiding, `RequestStreamAroundAsync` helpers, drone massing-model toggle | none |
| `Sky/Lighting` | Day cycle from Clock, moon texture swap, stars, tower blink, overflight | none |
| `Ambient/Fauna` | Birds, insects and nest life, client-only from a seed and the server clock (wildlife §15) | none |
| `UI/*` | Role HUDs, minimap and full map, radar, notification priority queue, quest panel, queue and rank panel, dev picker, station mini-game, ticket book, drone feed, remodel UI, settings | `UI.open(name, args)` |
| `Input/Bindings` | ContextActionService maps for keyboard, mouse, gamepad and touch (squirrel §26 conflicts) | `bind(set)` |
| `Audio`, `Speech/Bubbles` | Sound assets; BillboardGui bubbles (humans §11) | `play(id, at)`, `say(actorId, line)` |

#### `src/worldgen` -> ServerStorage.WorldGen

This code runs in three hosts: the Lune bake, the Studio plugin and the server.

| Module | Responsibility | Public interface |
|---|---|---|
| `Bake` | Entry point: walks districts and lots in a fixed order and calls builders; stamps `BakeHash` | `Bake.run(data, factory, opts) -> rootModel` |
| `Factory` | Instance creation shim. Under Lune it wraps `@lune/roblox`; in Roblox it uses globals. CFrames are computed by pure maths (Lune has no `PivotTo`) | `part(spec)`, `wedge(spec)`, `mesh(kitName, cf, size, color)`, `model(name, opts)`, `surfaceText(...)`, `beam(...)` |
| `Kits` | Resolves a logical kit name through the manifest to a MeshPart template, or falls back to a blockout recipe | `resolve(name) -> template or recipe` |
| `Builders/Lot` | Dispatches a lot to its type's builder; applies flair; emits sockets as Attachments | `build(lot, ctx)` |
| `Builders/{House, Storefront, Restaurant, Civic, Hospital, PoliceStation, Estate, Quay, Galleria, Park, Cemetery, Marina, Pier, Beach, Sewer}` | One builder family per lot category, parameterised by lot-type JSON | `build(lot, type, ctx)` |
| `Builders/{Interior, Hollow, Tree, Pole, Wire, Fence, Road, Signage, Dressing, Backdrop, Massing}` | Interiors from templates; trees and wires drawn from route curves; roads; text signs as SurfaceGui; drone massing model | `build(...)` |
| `Builders/Terrain` (Roblox only) | `WriteVoxels` from `World/Height` in chunks | `write(region)` |

#### `src/plugin` -> SpicyTools Studio plugin

It has four buttons and nothing else:

- **Rebake Town** runs `WorldGen.Bake` in edit mode.
- **Validate Rig** checks the rig contract.
- **Publish Hero Asset** calls `AssetService:CreateAssetAsync`, then writes the id to `ServerStorage.SpicyManifest`. This must be verified in spike S6.
- **Checklist** shows the current session's steps.

The plugin source also ships as a Script in the test place, so the owner installs it with right-click > **Save as Local Plugin**.

#### `tools`

| Tool | Does |
|---|---|
| `tools/harvest` | Loads a copy of the pinned v5.4 HTML in headless Chrome, with `addRoute`, `makeTree`, `rebuildCanopyForks` and the nest/bird/apple setup instrumented, and dumps JSON: route control points, kind, radius, visualOffset, generator and stack; forks; trees; nests; apples; utility supports. Runs only when the reference changes; output goes to `data/harvest/` with its SHA. Proven feasible: routes §0, and a scratch dump of 1,332 routes and 95 fork trunks exists in this session. |
| `tools/compile` | Lune: schema validation, invariant checks (§3.12), lot-type expansion, flair seeding, route templating and linkers, traffic graph, nav graph, colliders, forage, map vector data, reports. Writes `generated/`. |
| `tools/bake` | Lune: `generated/` -> `build/world/<district>.rbxm` via `src/worldgen`; writes `BakeHash`. |
| `tools/blender` | `export_rig.py` (one FBX per clip plus rig-only, with the settings in feasibility §A5); `clips_to_json.py` (bone curves -> JSON -> Lune KeyframeSequence); `kit_from_archetype.py`; `tree_from_routes.py`; `export_sockets.py` (named empties and curves -> `*.sockets.json`, `*.routes.json`); `check_budget.py` |
| `tools/textures` | Moon phases (16 at 512 px), classic clothing templates (585x559) from `cast/outfits.json`, map render, sign and trim atlases |
| `tools/cloud` | `upload.luau` (Assets API: Image/Decal, Model, Animation); `save_place.luau` (unpublished version to the TEST place); `exec.luau` (Luau Execution: one task runs the whole suite; returns JSON); `harvest_ids.luau` (Luau Execution reads the latest saved place or loads uploaded models and returns MeshIds, TextureIDs and plugin-written manifest attributes) |

### 1.4 Cross-cutting conventions

- **Units.** Source data uses HTML units (u). `tools/compile` multiplies by 2.5 exactly once. Runtime code sees only studs. Source of the rule: brief §2; worldgen_core §1.
- **Yaw.** HTML `rotation.y = θ` is Roblox `CFrame.Angles(0, θ, 0)`, with the model front on local +Z (worldgen_core §1; traffic §0).
  - Kits are authored facing Blender +Y so that they land facing +Z. Verify with an arrow prop in spike S3, because the docs' default maps Blender -Y to LookVector.
  - Never use `CFrame.lookAt` for vehicle facing (traffic §0).
- **Actor attributes.** Every body is a Model with these attributes: `ActorId`, `Species`, `Role`, `DriverUserId` (0 means AI), `State`, `Health`, `Infected`, `Vigilante`.
  - Clients and UI read only attributes and streams, never server tables.
- **Steppable services.** No module starts threads when it is required. This is what makes Luau Execution integration tests possible.
- **Gameplay never depends on streamed instances.** Routes, colliders, nav, doors, forage anchors and markers are all data (routes §20; hospital §12; wildlife §15).

---

## 2. Key technical decisions

Each decision is listed with its rationale, its fallback and the spike that proves it. The spikes S1-S8 run in Wave 0 (§5).

### D1. WorldGen: bake at build time, rebake in Studio, runtime only as fallback

- **Choice.**
  - `tools/bake` (Lune) runs the shared `src/worldgen` builders over the generated data and writes `build/world/*.rbxm`. `rojo build` puts them under `Workspace.World`.
  - The same builders run from the plugin's **Rebake Town** button and, if `BakeHash` is missing or stale, at server start.
  - **Terrain is the exception.** Lune cannot write voxels, so the server writes terrain at boot from the analytic `World/Height` (heights stay under about 24 st). The Roblox build covers the whole playable rectangle, fixing the mesh gaps in worldgen_core §2.
- **Rationale.** Brief §2 says the world is built "from data, never from hand-placed parts". SLIM needs static geometry in a saved, published place (feasibility §B.e and Blocker 6). Lune can create instances and write `.rbxm` (feasibility §A, Lune row).
  - A build-time bake makes the world diffable, testable in CI (counts, overlaps, budgets) and identical in every host.
  - A Luau Execution test asserts that the runtime bake's tree hash equals the Lune bake's hash.
- **Fallback.**
  - If boot-time terrain is too slow (spike S4 measures `WriteVoxels` over 4,350 x 2,520 st in Luau Execution), the owner bakes terrain once with the plugin. It is then kept as a `TerrainRegion` asset (`Terrain:CopyRegion`) that the server pastes at boot.
  - If the Lune bake hits an unsupported class or property, that builder emits a "deferred" stub that the runtime bake completes.

### D2. Data format: JSON source in HTML units, compiled to chunked Luau

- **Choice.**
  - Authored files are JSON with JSON Schemas. Lune, Python (bpy) and Node all read them natively.
  - The compiler emits `generated/data/*.luau` modules. Each returns a compact JSON string, decoded once by `Data`: `HttpService:JSONDecode` in the engine, `serde` under Lune. Modules are chunked by district to stay under about 1 MB.
  - The Ladder and Tunables are Luau, because the brief wants the ladder stated "in code" (§6).
- **Rationale.**
  - Spec ids and line numbers carry straight over: the 90 + 153 lots, 116 roads and 25 lanes keep their ids.
  - Tool-friendly and schema-checkable.
  - One conversion point for units.
- **Fallback.** If very large string constants misbehave (spike S5 times requiring the largest chunk), switch the encoding to `buffer` base64 or split further.

### D3. Streaming, SLIM and the drone view

- **Choice.**
  - Each lot bakes to one Model with `ModelStreamingMode=Atomic`, so the shell, its doors and its route visuals arrive together. Interior props sit in a child Model that the client hides by distance.
  - District block Models (about 300 x 300 st) get `LevelOfDetail=SLIM`.
  - Persistent: backdrop bands, radio and cell towers, clock tower, bridge towers, Galleria shell (districts_art §16).
  - Actors are Atomic with `PrimaryPart` set; the possessed body is `PersistentPerPlayer`.
  - `RequestStreamAroundAsync` is called before possession, teleports, sewer or hospital transitions, and along the drone path.
- **Rationale.** feasibility §B.e (streaming modes; SLIM) and §B.a.5 (possession pitfalls).
- **Fallback, which is data-driven so it works even if SLIM disappoints.** The bake also emits a **massing model**:
  - one low-poly block per building, coloured by roof colour, plus road ribbons: about 2,000 parts, Persistent;
  - the client shows it only when the camera is above about 150 st, or beyond the streaming radius.
  - The drone always sees the whole town. Verified in the release wave once a published place exists.

### D4. Climbing routes: harvested exactly, then templated for anything rebuilt

- **Choice.**
  - **Harvest** all 1,332 v5.4 routes: control points, kind, surfaceRadius, visualOffset, generator and an inferred `lotId`. They go into `data/harvest/routes.json`. This reproduces the HTML's RNG- and creation-order-dependent network exactly (routes §3, §20).
  - Name-regex behaviour becomes explicit attributes: `surface` (tree, pole, pipe or ladder), `surfaceNormal` and `autoGrab` (routes §4, §19).
  - **Templates.** Every lot type, archetype and hero asset carries route templates in lot-local space: ridge, gutter, downspout, parapet, fence top, sign top, awning edge, interior counter and shelf tops.
    - When a lot is rebuilt (20 outer homes, the hospital, every new lot), the compiler drops that lot's harvested routes by `lotId` and emits its template routes instead.
  - **Linkers** re-run the HTML's bridge rules deterministically, sorted by id rather than by creation order. These are the living bridge to the nearest wire sample (<49 u), the rooftop crossing (<64 u), the canopy-to-wire bridge (<39 u) and gutter-to-roof (<24 u) (routes §3).
  - A report diffs connectivity against v5.4: 149 islands, largest 563.
- **Rationale.** Brief §1: the HTML is the reference for climbing routes. Brief §3: adding a lot is a data entry.
- **Fallback.** If harvest instrumentation breaks, `spec/data/routes_catalog.json` gives every generator formula for a code re-implementation, at the cost of RNG-dependent details.

### D5. Four asset lanes, and hero assets loaded at runtime

| Lane | Path | Studio? | Used for |
|---|---|---|---|
| 1. Code geometry | Parts, Wedges, Terrain, Beams, SurfaceGui text, built by worldgen | no | the whole first runnable build; signs (all text is data); wires; massing |
| 2. Cloud mesh | bpy (headless) -> FBX -> Open Cloud Assets API "Model" -> `harvest_ids` -> MeshId/TextureID -> `assets/kits/*.rbxm` (Lune) -> baked into the place | no | building kits, props, furniture, vehicles, trees, backdrop, pier and marina |
| 3. Studio import | The owner imports the FBX in the 3D Importer (Rig Type Custom), adds SurfaceAppearance, then clicks **Publish Hero Asset** (or "Save to Roblox"). The id goes into the manifest, and the server loads it at runtime with `InsertService:LoadAsset` (allowed for assets owned by the experience owner) | yes, few clicks | skinned rigs (squirrel, rodent, fox, deer), PBR heroes (premium hollow trees, patrol car interior) |
| 4. Data-only appearance | `HumanoidDescription` recipes plus uploaded 2D clothing images; `Players:CreateHumanoidModelFromDescription` on the server | no | all humans (R15) and their outfits |

- **Rationale.**
  - It keeps SurfaceAppearance and BaseWrap out of the saved place, so API saves and publishes stay faithful (feasibility §B.d).
  - It lets Claude ship the place headlessly. Puppet rigs and blockouts mean art never blocks gameplay.
- **Fallbacks.**
  - If Lane 2 id extraction fails (spike S3), the owner runs one capture: File > Save to File, then Claude runs `rojo syncback` in the container (Rojo 7.7.1 syncback, feasibility §B.h).
  - If runtime `LoadAsset` is unsuitable, the hero templates live in a Studio-owned folder and that release is published from Studio.

### D6. Movement authority

- **Choice.**
  - Possessed bodies are client-owned. The client runs the controller at 60 Hz:
    - squirrel: rail and ground kinematic controller, gravity 75 st/s²;
    - humans: Humanoid;
    - fox and deer: kinematic;
    - drone: a client-owned device;
    - patrol car: VehicleSeat.
  - The server validates with leaky buckets: speed caps per route kind x1.6 boost, transfer gap <= 7.9 st, grab radius <= 8.5 st, gravity-consistent arcs, data-collider wall checks (routes §20).
  - Route riders replicate as `(routeId, t, dir)`.
  - AI bodies are anchored and moved by the server with `BulkMoveTo`. Possession unanchors the body and hands network ownership to the player; release reverses it (feasibility §B.b).
- **Rationale.** Rails need input-coupled 60 Hz motion. Server Authority is still beta.
- **Fallback.** Server Authority (`AuthorityMode=Server`, already compatible because of Deferred signals and StreamingEnabled) for the rodent duel only, once it is out of beta. The pounce protocol has server rewind of about 150 ms in the meantime (squirrel §26).

### D7. AI scheduling and level of detail

- **Choice.**
  - One scheduler with three tiers by distance to the nearest player:
    - near (< 150 st): 10 Hz with full perception;
    - mid: 4 Hz;
    - far: 1 Hz "commute" along the nav graph with anchored warps.
  - Total budget is 4 ms per frame, round-robin, staggered phases.
  - Perception uses a 40-st grid.
  - Humans use `Humanoid:Move()` toward graph waypoints, not per-frame `MoveTo`. `PathfindingService` is used only for interiors and escapes, cached per house (humans §15).
  - Parallel Luau (2-3 Actors that each own a slice of brains) is added only if profiling demands it (feasibility §B.e).
  - Body budget: about 50 humans, at most about 60 Humanoids in total; 12 squirrels; 1 rodent; 4 deer; 1 fox. Birds and insects are client-only.
- **Fallback.** Reduce AI humans toward 40 and widen the far tier.

### D8. Traffic collision and vehicles

- **Choice.**
  - AI vehicles are server-kinematic on the compiled lane graph at 30 Hz. Poses go out in a batched unreliable stream; clients render them.
  - The fatal test is the HTML's `sweptVehicleHit` (traffic §8.4), unchanged, run server-side for every squirrel actor every tick:
    - circle broad-phase;
    - the `travel > 30 st` and teleport-flag skips;
    - a 1 s ring buffer to rewind to the client timestamp.
  - Player patrol cars are physics VehicleSeats with client ownership, sampled by the server each tick (speed cap, anti-teleport) and included in the same fleet list.
  - Fixed relative to the HTML: handedness (keep right), the trolley deadlock (opposing lanes excluded) and the teleport sweep bug (traffic §6.1, §Added by verifier 1).
- **Fallback.** If client-owned car physics desyncs, use a server-authoritative arcade car (throttle and steer inputs over a remote).

### D9. Animation pipeline

- **Choice.**
  - Clips are authored in Blender, on the puppet armature first and the hero armature later, with the same bone names.
  - `clips_to_json.py` dumps per-frame local bone transforms. Lune writes a `KeyframeSequence` `.rbxm` with Pose names equal to the Motor6D or Bone names.
  - In **Studio playtests** they play through `AnimationClipProvider:RegisterAnimationClip` from git, with no upload (feasibility §B.c).
  - For **live** servers they upload through the Open Cloud Animation API (spike S2; the docs warn "files edited outside of Studio might not upload").
  - FBX per clip is still exported for the Studio Animation Editor fallback.
- **Fallback.** The owner imports each FBX clip in the Animation Editor and publishes it: about 1 minute per clip. Or SpicyTools batch-publishes the KeyframeSequences, if `CreateAssetAsync` supports Animation (spike S6).

### D10. Avatar blend, 70% stock and 30% player (addendum A3)

- **Humans.**
  - The server reads `GetHumanoidDescriptionFromUserId`.
  - The recipe keeps the role's uniform, body type and silhouette. From the avatar it takes skin tone, face, one hair or head accessory, and accent colours clamped to the palette (trim, tie, scarf, shoes).
  - It is applied with `Humanoid:ApplyDescription` and reverted to the stock description on release.
- **Animals.**
  - Rigs are split into skinned MeshParts: Body (SurfaceAppearance AlphaMode Overlay, with pattern regions cut as alpha holes so `MeshPart.Color` shows through), FurCards (TintMask), Eyes.
  - The blend sets `MeshPart.Color` (scriptable) from avatar shirt, pants and body colours, with a capped blend.
  - The FurCards tint uses `SurfaceAppearance.Color` if scripts can write it; verify in S8. Otherwise it uses the variant fallback below.
  - One avatar accessory is taken from a temporary `CreateHumanoidModelFromDescription` model. It is resized and welded to `HatSocket`.
  - The rodent's red eyes are never overridden (squirrel §25.11).
- **Puppet rigs** use the same region names, so the blend works from the first runnable build.
- **Fallback.** A palette-quantised variant set: 12 fur tints and 6 pattern kits, chosen by nearest colour. Clothing pixels are never read (addendum A3).

### D11. Persistence

- **Choice.**
  - Rank, credits, nuts, homes and remodels are **per server instance**, in memory only, as the brief scopes them (§6 "time … on this server"; §8 remodels "for the life of that server instance").
  - A DataStore profile per UserId keeps cross-session items: settings, wardrobe if kept (squirrel §26) and lifetime stats.
- **Fallback.** If DataStores fail, the session runs profile-less and shows a toast.

### D12. Delivery to the owner: Open Cloud place versions, two universes

- **Choice.**
  - Two experiences under the same owner:
    - **TEST**: CI saves, Luau Execution, owner playtests.
    - **LIVE**: releases only.
  - `ci.sh` saves an unpublished version of TEST on every green build. The owner simply opens TEST in Studio (File > Open from Roblox). There is no Rojo, git or terminal on the owner's Mac. `rojo serve` stays optional.
- **Rationale.** "The owner is not a programmer: Studio steps must be click-by-click and few."
- **Constraint.** The owner must not edit Rojo-managed trees in TEST. Anything the owner imports goes in `ServerStorage.Inbox` (unmanaged) and is captured by `harvest_ids` before the next save overwrites the version.

### D13. Network layer

`Net/Schema` declares every remote with payload types and rate limits.

- Reliable: discrete events (pounce, bite, kick, ticket, mark, interact).
- Unreliable, batched at 10-20 Hz: AI actor poses, vehicle poses and route-rider tuples.
- Timestamps use `workspace:GetServerTimeNow()`.
- One `Net` module per side. Nothing else creates RemoteEvents.

### D14. Clock and day length

- **Choice.**
  - The server owns `epoch` and `secondsPerDay` as attributes. Each client derives all lighting itself and nothing streams per frame (districts_art §16).
  - The default follows brief §12: one winter cycle (5 weeks + 1 winter week = 42 days) about every 50 real minutes, which is about 71 s per day.
  - A non-linear day curve holds sunrise, golden hour, sunset and blue hour longer (districts_art §17.2).
  - The moon uses a per-phase `MoonTextureId` swap with 16 phases, with a custom billboard as the fallback (feasibility §B.f).
- **Owner decision O7.**

---

## 3. Data schemas

### 3.1 Pipeline stages and what each produces

```
reference/v5_4.html --(tools/harvest, rare)--> data/harvest/{routes,forks,trees,nests,apples,supports}.json
spec/data/*.json    --(one-time migration)---> data/town/**, data/traffic/**, data/cast/**, data/wildlife/**
data/** (authored)  --(tools/compile)--------> generated/data/*.luau + generated/reports/*.md
generated/data      --(tools/bake)-----------> build/world/*.rbxm          (+ BakeHash)
art/** (bpy)        --(tools/blender)--------> build/fbx/*.fbx, *.sockets.json, *.routes.json, clips/*.json
build/fbx           --(tools/cloud upload)---> asset ids -> data/assets/manifest.json -> assets/kits/*.rbxm
clips/*.json        --(lune)-----------------> assets/anim/*.rbxm (KeyframeSequence) --(cloud)--> animation ids
src + generated + assets + build/world --(rojo build)--> build/SpicyRodents.rbxl --(cloud save)--> TEST version
TEST version        --(cloud exec)-----------> tests/cloud results (JSON)
```

### 3.2 Lot (one entry in `data/town/lots/<district>.json`)

This extends the extractors' schema (`id, district, type, x, z, facing, footprint, style, has_interior, notes, src_line`; worldgen_core §1). Existing ids and fields are kept. Everything new goes under `params`, `flair`, `forage`, `home` and `overrides`.

```jsonc
{
  "id": "core_house_0_victorian",          // stable; spec ids preserved
  "district": "old_town_core",
  "type": "house_victorian",               // -> data/lot_types/house_victorian.json
  "x": -56, "z": -53,                      // HTML units, lot centre
  "facing": "+Z",                          // front direction; or "yaw": radians (overrides facing)
  "footprint": { "w": 18.04, "d": 15.58 }, // world-axis extents (already rotated), u
  "seat": "terrain_centre",                // terrain_centre | graded_pad | absolute:<y>
  "params": {                              // validated against the lot type's param schema
    "storeys": 2, "porch": "wrap", "chimney": true, "deck": "covered",
    "driveway": { "side": "-X", "len": 26 }, "mailbox": true
  },
  "flair": { "seed": 1034, "lock": { "wall": "#ded7b7", "trim": "#f5ecd5", "roof": "#63524c" } },
  "yard": { "theme": "porch_bbq", "fences": ["F1", "F2"], "items": ["bbq", "bbq", "drum", "picnic_x4", "bins"] },
  "forage": { "inherit": true, "add": [ { "kind": "garden_bed", "at": [-36, 52], "premiumFor": "H2" } ] },
  "home": { "interior": "victorian_a", "claimable": true, "defender": null, "residents": ["Donna", "Frank", "Mrs. Abbott"] },
  "routes": { "dropHarvested": false },    // true when the lot is rebuilt from an archetype template
  "streaming": "Atomic", "lod": "SLIM",
  "provenance": { "spec": "lots_core.json", "src_line": 1034 },
  "notes": "free text; never read by code"
}
```

### 3.3 Lot type: how a barber shop becomes one data entry

The lot type `data/lot_types/shop_barber.json` is written once. It composes existing builders, so no code changes are needed.

```jsonc
{
  "type": "shop_barber",
  "extends": "storefront_small",            // inherits builder, kit, routes, traffic, map defaults
  "category": "commercial",
  "builder": "Storefront",                  // src/worldgen/Builders/Storefront.luau
  "kit": "kit.storefront.small",            // manifest key; blockout recipe until the kit lands
  "defaults": { "footprint": { "w": 14, "d": 18 }, "storeys": 1, "palette": "brick_warm", "awning": "stripe_red_white", "pole": "barber_pole" },
  "paramSchema": { "sign": { "type": "string", "maxLen": 18, "required": true }, "chairs": { "type": "int", "min": 1, "max": 3, "default": 2 } },
  "interior": { "template": "barber", "public": true, "openHours": [8, 18] },
  "jobs": [
    { "socket": "chair_*",  "job": "barber_cut", "credits": 3, "cycleS": 20, "role": "human" },
    { "socket": "register", "job": "cashier",    "credits": 1, "cycleS": 12, "role": "human" }
  ],
  "staff": { "ai": [1, 2] },
  "forage": [ { "kind": "trash_can", "socket": "rear_bin", "yield": [1, 2], "cooldownH": 24, "risk": { "humans": 0.15 } } ],
  "risk": { "base": 0.15 },
  "routes": ["roof_ridge_or_parapet", "downspout_front_right", "gutter_to_roof", "awning_edge"],
  "traffic": { "curb": "parallel_parking_front", "hydrantChance": 0.3 },
  "map": { "icon": "scissors", "label": "$params.sign" },
  "streaming": "Atomic", "lod": "SLIM"
}
```

The lot entry is the "data entry" the brief asks for:

```jsonc
{ "id": "east_barber_01", "district": "east_commercial", "type": "shop_barber",
  "x": 560, "z": -128, "facing": "+Z", "footprint": { "w": 14, "d": 18 },
  "params": { "sign": "CLIP JOINT", "chairs": 2 } }
```

From those two records, the compiler derives:

- A blockout shell, or kit meshes once they exist, seated on terrain.
- An awning and a barber pole prop.
- A sign as SurfaceGui text, so no upload is needed.
- A furnished interior from template `barber`, with door sockets linked into the pedestrian nav graph.
- Two job sockets, which Quests and Economy use for credits.
- AI staff assigned from the human pool.
- A rear trash-can forage source with yield, cooldown and risk.
- Roof, downspout and awning routes, run through the linkers so a nearby tree can bridge onto the roof.
- Colliders.
- Curb parking spaces in front, with a red curb if a hydrant is placed.
- A map icon and label.
- Massing and SLIM settings.

Adding a new **type**, such as `shop_music`, is one more lot-type file that reuses `Storefront` with a different interior template.

### 3.4 House archetype and per-house flair (`data/archetypes/houses/*.json`)

There are eight archetypes, the brief §3 minimum: bungalow, two-storey, Victorian, ranch, split-level, cottage, apartment block, large older house. Mansion and guesthouse are optional extras for the estates.

The archetype JSON is read by both `Builders/House` (blockout) and `tools/blender/kit_from_archetype.py` (kit mesh). Doors, eaves and ridges therefore line up exactly in both.

```jsonc
{
  "archetype": "split_level",
  "footprint": { "w": [12, 16], "d": [10, 14] },               // u, ranges the lot may pick within
  "levels": [ { "floorY": 0, "eave": 3.4, "rect": [0, 0, 0.55, 1] }, { "floorY": 1.6, "eave": 5.4, "rect": [0.55, 0, 0.45, 1] } ],
  "roof": { "kinds": ["gable", "hip"], "pitch": [0.45, 0.7] },
  "doors": [ { "id": "front", "face": "+Z", "at": 0.3, "w": 1.05, "h": 1.4, "waypoints": { "out": 1.25, "in": 2.15 } }, { "id": "back", "face": "-Z", "at": 0.7 } ],
  "windows": { "perFaceMin": 2 },
  "sockets": { "mailbox": [0.35, 0, 0.5, "out:6.5"], "serviceDrop": [-0.4, "eave", 0.5] },
  "routeTemplates": ["ridge", "gutter_to_roof", "downspout_corner", "porch_rail"],
  "interiors": ["split_level_a", "split_level_b"],
  "flairAxes": {
    "palette":   ["sage", "cream", "teal_grey", "brick", "butter", "slate", "clay"],
    "trim":      ["white", "cream", "dark_oak", "forest"],
    "roofColor": ["#5e5d5d", "#71625c", "#5d6b65", "#755a50", "#63524c"],
    "porch":     ["none", "stoop", "half", "full", "wrap"],
    "roofKind":  ["gable", "hip"],
    "chimney":   [false, true],
    "dormers":   [0, 1, 2],
    "shutters":  [false, true],
    "windowBox": [false, true],
    "door":      ["#4b6d61", "#6e5144", "#3d5e78", "#a3835b", "#597e77", "#5b4239"],
    "yard":      ["garden", "feeder", "shed", "doghouse", "pool", "trampoline", "veg_patch", "swing"]
  }
}
```

**Flair rule.**

- `flair.seed` (default: hash of the lot id) picks one value per axis. `flair.lock` pins any axis.
- The validator requires every pair of houses within 120 u of each other to differ on at least 4 of the 11 axes, so "no two read the same" (brief §3).
- The palettes are drawn from the existing v5.4 colours (worldgen_core §6.1 wall, roof and door lists; districts_art §11 statistics), so the town keeps its muted golden-hour look (districts_art §14.1).

### 3.5 Interior template (`data/interiors/*.json`)

```jsonc
{
  "template": "victorian_a",
  "fitsArchetypes": ["house_victorian", "large_older"],
  "rooms": [ { "id": "hall", "rect": [0.42, 0.0, 0.16, 0.45] }, { "id": "living", "rect": [0, 0, 0.42, 0.55] },
             { "id": "kitchen", "rect": [0, 0.55, 0.5, 0.45] }, { "id": "bed1", "rect": [0.58, 0.55, 0.42, 0.45] } ],
  "doors": [ ["hall", "living"], ["hall", "kitchen"], ["hall", "bed1"], ["kitchen", "outside:back"] ],
  "furniture": [ { "slot": "sofa", "room": "living", "at": [0.2, 0.25], "cat": "sofa", "hide": "behind" },
                 { "slot": "bed", "room": "bed1", "cat": "bed_double", "hide": "under" },
                 { "slot": "wardrobe", "room": "bed1", "cat": "wardrobe", "hide": "inside" } ],
  "squirrelRoutes": [ "counter_top:kitchen", "shelf_top:living", "curtain_rail:bed1" ],
  "defenderSpawn": "kitchen",            // used only if the lot sets home.defender
  "burglarEntry": "window:bed1",
  "remodelSlots": ["wall_paint", "floor", "sofa", "bed", "rug", "lamp", "art"]
}
```

`Builders/Interior` lays out partitions, door gaps and furniture from the `cat`-to-kit lookup, and seeds variants from the lot's flair.

Nav waypoints are generated automatically: room centres, door midpoints and hide spots. Hide spots are data: humans "run inside and hide" (brief §8; humans §14.7).

The interior lives inside the real shell, with no teleport. That replaces both the dead v2.1 code and the Westside transit (worldgen_core §5.4, §13).

### 3.6 Routes, hollows and the utility network

Harvested route (`data/harvest/routes.json`; the compiler adds the attributes):

```jsonc
{ "hid": 220, "name": "outer 12 tree trunk", "kind": "trunk", "ctrl": [[x, y, z], ...],   // u, world
  "surfaceRadius": 0.81, "visualOffset": null, "speed": 1, "generator": "makeOuterTree@2240",
  "lotId": null, "treeId": "outer_12",
  "surface": "tree", "surfaceNormal": null, "autoGrab": true }        // replaces regexes in routes §4
```

Template route, in local lot space, with heights given relative to archetype levels rather than absolute (this fixes routes §Added by verifier 3 and 4):

```jsonc
{ "template": "downspout_corner", "kind": "trunk", "surface": "pipe", "surfaceRadius": 0.14, "autoGrab": false,
  "ctrl": [["corner:+X+Z", "ground+0.1"], ["corner:+X+Z", "eave-0.15"]], "surfaceNormal": "face:+Z" }
```

Compiled runtime route: `{id, kind, surface, ctrl (studs), radius, vOffset, speed, normal, autoGrab, origin = harvest | template | linker, lotId}`. Runtime samples and the spatial index are rebuilt from `ctrl` on both server and client in milliseconds (routes §20).

**Hollow tree** (`data/town/hollows.json`): 11 entries, sited per wildlife §6.5 (H1-H11).

```jsonc
{ "id": "H1", "variant": "shaft", "premium": true, "tree": "park_outer_95", "x": 90, "z": 358,
  "asset": "hero.hollow.shaft",                 // Lane 3; blockout hollow ring until it lands
  "chambers": [ { "id": "root", "h": 0.6, "cap": 40 }, { "id": "pantry", "h": 6.5, "cap": 60 }, { "id": "nook", "h": 12.0, "cap": 20, "lookout": true } ],
  "knotholes": [ { "h": 1.2, "bearing": 200, "chamber": "root" }, { "h": 12.4, "bearing": 30, "chamber": "nook", "exitTo": "bough:2" } ],
  "interiorRoute": { "kind": "hollow", "from": "root", "to": "nook" },
  "meter": { "capacity": 120, "ownAt": 0.70 },
  "premiumForage": ["tabasco_garden_bed_1", "feeder_premium_H1"] }
```

**Reconciling the owner's three variants with the brief's 11 hollows (11 = 2 premium + 9 single chamber).**

| Brief slot | Variant | Where (wildlife §6.5) | How it plays |
|---|---|---|---|
| Premium 1 | **Shaft climb** | H1, park outer 95 (90, 358), modelled at giant girth (r about 2 u; wildlife §6.5) | Vertical `hollow` rail up the centre of the trunk; chambers at 3 heights; knothole exits; a hideout nook at the top |
| Premium 2 | **Spiral ramp** | H2, core SYCAMORE (-37, 29) | `ramp` helix route that you walk rather than climb; 3 chambers off the ramp |
| Single (7) | Knothole chamber | H3-H8, H10 (standing trees) | Knothole -> one chamber (E to enter) |
| Single (2) | **Hollow fallen-log tunnel** | H9 becomes a fallen hollow oak lying beside Estate Oak South 1 (118, -356). H11 becomes a fallen willow on the quay bank beside the QUAY WILLOW (1094, 192). Both keep their district and their forage (wildlife §6.5) | `tunnel` route through the log; the chamber at its middle; entries at both ends |

This keeps the brief's count, the premium rule and the district spread, and gives the owner all three interior types. The existing v5.4 park log shelter at (-19, 376) (wildlife §6.4) also gets a `tunnel` route, but as a non-territory hiding spot.

The alternative is to keep H9 and H11 standing and make the logs extra, non-territory shelters (owner decision O4).

**Utility network** (`data/town/utility.json`):

- Pole lines are lists of pole points, harvested: 110 supports (worldgen_core §11).
- Spans are generated between consecutive poles with the sag rule `min(0.84, 0.26 + 0.004·span)` (routes §2).
- Service drops go to every house lot with `serviceDrop: true`. The HTML gave drops to only 4 houses (worldgen_core §11, a creation-order quirk). Adding drops is a design choice, flagged in the reports.
- A compile-time assertion requires every pole to be at least 0.95 u from pavement (worldgen_core §16).

### 3.7 Traffic from data

| File | Content | Source |
|---|---|---|
| `town/roads.json` | 116 entries (harvested), plus `class` (residential, arterial, boulevard, estate, access), `speedLimit` (u/s) and `lanes` | roads.json; worldgen_core §4 |
| `town/roads_fix.json` | Connectors for the gaps: x=-180 and x=0 to z=283; x=347 to z=283 and south to the new south-east block; x=±180 to the estate avenue; Westside street to the hospital road | worldgen_core §4.3, §17.5 |
| `town/intersections.json` | Node id -> control: `allStop`, `twoStop:<axis>`, `signal{phases, timings}` or `none`. Defaults: grid junctions are all-way stops; boulevard x x=347 becomes a 4-way signal using the 4 existing signal props | traffic §4, §14.7 |
| compiled curbs | Each road edge minus intersections, crosswalks and driveways. Hydrants are spaced along curbs (the 4 HTML hydrants are kept). Red curb within 3 u of hydrants and 8 u of stop lines. Parallel spaces are 6.5 u. The commercial bay-line lots (z = ±139, x 410-635; restaurant bays x 438-508) become lot parking | worldgen_core §4.4 |
| `traffic/vehicles.json` | Logical boxes and speeds per type, from traffic §1-§2 (sedan 2.35 x 4.45 x 2.04 or the true mesh, O11) | traffic §1 |
| `traffic/fleet.json` | Spawns and paths: residential and boulevard movers, ice-cream spline (baked arc table), trolley schedule, heavies, ambulances, AI patrol beats, event glides | traffic_lanes.json (25) |
| `traffic/drivers.json` | Violation profiles: speeder rate, rolling-stop rate, illegal-park rate, fender-bender rate per in-game hour | addendum A2 |

**What the compiler emits for traffic.**

- A planar lane graph with keep-right offsets:
  - residential ±5.4 u as in the HTML;
  - the boulevard mirrored to keep right (traffic §3, §14.1).
- Turn connectors.
- Conflict pairs for yielding.
- Stop lines and stop-sign props placed by rule.
- Speed limits per edge.
- Parking spaces with `{legal, timeLimitMin, kind}`.

These feed four consumers:

- Police tickets (radar speed against the edge limit; stop-line crossing without a stop event; illegal or overtime parking).
- Fender-bender events, at low speed at junctions and lots.
- The map.
- Deer startle zones.

### 3.8 Forage value and risk per lot type (defaults; lots may override)

All yields, cooldowns and risk numbers are tunables (wildlife §14 proposals).

| Lot type family | Sources (socket) | Yield / cooldown | Risk (who reacts) |
|---|---|---|---|
| House (backyard theme) | garden bed, feeder, compost, pet bowl, bins | bed 2-4 / day; feeder 2 / day; bowl 1 / 12 h | homeowner (resident brain), dog or cat if present, birds at feeders |
| Premium yard next to H1 or H2 | premium bed, premium feeder | 8-12, **once per in-game week** (brief §7) | homeowner 2x, dog |
| Restaurant (8 kinds) | dumpster (rear) or patio crumbs | dumpster 4-6 / 12 h; patio 1-2 / 2 h while open | staff (worker brain), diners |
| Shop / civic | trash can | v4.1 rule: 35% chance, once per can per day (wildlife §11.3) | passers-by |
| Park, gardens | community beds, Tabasco garden | beds 2-3 / day | dogs, park walkers |
| Orchard (12 apple trees) | fallen and hanging apples | weekly regrowth; none in winter | low |
| Acorn oaks (10) | canopy acorns | 1 per gather; daily pool | height-safe |
| Mall plaza | crumbs, café spill | 1-2 / h | crowd |
| Nut caches (10 restored, cache 4 moved; wildlife §15) | cache | 3 / 5 / 7 (v4.1 values), daily respawn | low |

### 3.9 The roles ladder (`src/shared/Roles/Ladder.luau`, the only place it is stated)

```lua
-- THE promotion ladder (brief §6, addendum A2). RoleService is its only consumer.
return {
  rungs = {
    { id = "human",    level = 1, species = "human",    slots = 35 },
    { id = "police",   level = 2, species = "human",    slots = { start = 5, max = 8 }, unlock = "officer_n" },
    { id = "hospital", level = 2, species = "human",    slots = 5, outranks = "police" },     -- "slightly above"
    { id = "squirrel", level = 3, species = "squirrel", slots = 7, bodies = { min = 10, max = 14 } },
    { id = "rodent",   level = 4, species = "squirrel", slots = 1, infected = true },
  },
  subroles  = { drone = { parent = "police", slots = 1, unlock = "officers_8_plus_upgrade" },
                driver = { parent = "police", slots = 2, pick = "top_two_by_rank" } },   -- addendum A1
  sideExits = { deer = { species = "deer", slots = 4 }, fox = { species = "fox", slots = 1, easterEgg = true } },
  rank = {
    human = { perMinutePlayed = 1.0, perCredit = 0.5, perKick = 25, perQuest = 10 },        -- addendum A2 inputs
    squirrel = { nutWeight = 0.90, stinkWeight = 0.10 },                                    -- brief §6
  },
  transitions = {   -- event -> rule; evaluated by Ladder.transition(event, ctx)
    rodent_died           = { to = "human", rank = "lowest" },
    human_killed_rodent   = { first = { "squirrel:lowest_uninfected_if_free" },
                              orElse = { when = "town_infected_gt_0.30", to = "hospital" }, default = "police" },
    hospital_killed_rodent_inside = { to = "squirrel", rank = "lowest_uninfected" },
    squirrel_infected     = { penalty = { nutsLostPct = 0.5, rankDrop = 2 } },              -- numbers: owner O16
    squirrel_winter_death = { to = "human" },
    side_exit_leave       = { to = "human", rank = "previous_human" },
    rodent_slot_open      = { pick = "highest_squirrel" },
  },
}
```

A unit test asserts two things:

- Every role change in the codebase goes through `Ladder.transition`, because `Roles/Service` is the only caller of `Actors.swap` for role changes.
- No other module defines rank weights.

### 3.10 Tunables (`src/shared/Config/Tunables.luau`)

Values are in studs and seconds, scaled from the specs at 2.5. Each entry carries its source so tuning stays traceable.

```lua
return {
  squirrel = {
    walk      = { v = 20,    unit = "st/s",  src = "routes §8.1 (8 u/s)" },
    sprint    = { v = 42,    unit = "st/s",  src = "16.8 u/s" },
    gravity   = { v = 75,    unit = "st/s2", src = "30 u/s2" },
    leap      = { v = { fwd = 41.25, up = 32 }, unit = "st/s", src = "routes §20" },
    transferMax = { v = 7.9, unit = "st", src = "3.15 u" },
    grabRadius  = { v = 8.5, unit = "st", src = "3.4 u" },
    shoulderHeight = { v = 1.2, unit = "st", src = "brief §2 (O2)" },
  },
  combat = {
    maxHealth = { v = 100 }, kickDamage = { v = 55 }, defenderMult = { v = 1.5, src = "brief §8" },
    regenStalk = { v = 2, unit = "hp/s" }, regenHollow = { v = 5, unit = "hp/s" }, iFrames = { v = 0.6, unit = "s" },
    -- window 0.78 and cooldown 0.7 are v5.4 values (squirrel §6); windup, commit and recovery are new proposals (brief §8)
    pounce = { windup = { v = 0.18 }, commit = { v = 0.10 }, window = { v = 0.78 }, recovery = { v = 0.45 }, cooldown = { v = 0.7 } },
    kickReach = { v = 6.6, unit = "st", src = "2.65 u" }, spotRadius = { v = 36, unit = "st", src = "14.5 u" },
    vigilantePct = { v = 0.08, src = "brief §8" },
  },
  clock    = { secondsPerDay = { v = 71.4, src = "brief §12 (O7)" }, weeksPerCycle = { v = 6 }, winterWeeks = { v = 1 }, lunarDays = { v = 29.53 } },
  forage   = { ownAt = { v = 0.70, src = "brief §7" }, stinkFireAt = { v = 0.95 }, stinkCost = { v = 30 } },
  traffic  = { tickHz = { v = 30 }, teleportSkip = { v = 30, unit = "st" }, sedanCruise = { v = { 16.25, 23.75 }, unit = "st/s" } },
  ai       = { budgetMs = { v = 4 }, nearHz = { v = 10 }, midHz = { v = 4 }, farHz = { v = 1 }, nearRadius = { v = 150, unit = "st" } },
}
```

### 3.11 Asset manifest (`data/assets/manifest.json`)

```jsonc
"rig.squirrel": {
  "lane": 3, "status": "puppet",                       // puppet | blockout | v1 | final
  "fallback": "puppet.squirrel",                       // Lane-1 recipe built by Lune (assets/rigs/puppet_squirrel.rbxm)
  "modelAssetId": null, "version": null,
  "contract": "art/squirrel/rig_contract.json",       // bone names, sockets, region MeshParts
  "budget": { "tris": 14000, "bones": 34, "maps": "1024" },
  "clips": { "Run": null, "Climb": null, "Wire": null, "Leap": null, "PounceWindup": null, "PounceCommit": null,
             "PounceRecover": null, "BiteDance": null, "Sneak": null, "Idle": null, "Land": null, "Forage": null,
             "StinkBurst": null, "Hit": null, "Death": null, "Rest": null, "Knothole": null }
}
```

`Assets/Service.template(name)` always returns the best available version (final, then v1, then blockout, then puppet). Promoting an asset is a manifest edit. The puppet and blockout versions share the final asset's bounding box, sockets and region names, so gameplay never changes when art lands.

### 3.12 Invariants enforced by `tools/compile` (CI fails on any of them)

1. Every lot validates against its type's `paramSchema`. Ids are unique. No footprint overlaps except declared children, such as the gas canopy.
2. Every lot front faces a road unless it declares `facing.reason`. This fixes the outer-home inversion (worldgen_core §6.1, §17.2).
3. Exactly 40 lots have `home.claimable` with an interior. Exactly 3 have a defender: two older housewives with rolling pins and one man with a broom, of different demographics (brief §8).
4. Restaurant lots are at least 10, covering all 8 named kinds. Each has seating or a dumpster socket. All 13 named new lot types exist: barber, music, hardware, laundromat, bookshop, pet store, gas station, grocery, school with playground, church, park with gazebo, community garden, marina. Each lot type has a forage table and a risk value.
5. Exactly 11 hollows, 2 of them premium, and each premium hollow has at least 1 premium garden and 1 premium feeder within 40 u.
6. Every pole is at least 0.95 u from pavement. No route is shorter than 0.04 u, has a non-finite point or has fewer than 2 points (routes §1.1).
7. Route connectivity: the largest island is at least 563 routes, matching v5.4 or better. Every hollow, the hospital roof and every new roof reaches the main network or is listed as an intended leap-only island (routes §21.10).
8. The traffic graph is strongly connected for car lanes. Every lot with parking or a driveway connects to a lane. No opposing-lane pair is closer than the sum of vehicle half-widths plus 0.2 u (deadlock guard, traffic §6.1).
9. The nav graph is connected. Every interior, hide spot, job socket and hospital or police room is reachable.
10. Budgets per district for instance count, triangles from manifest budgets and SurfaceGui count, plus the flair-distinctness rule (§3.4).

### 3.13 Content volume the data must hold (brief §3, §8, §9, §10)

| Content | v5.4 today | Target in data | Where it comes from |
|---|---|---|---|
| Dwellings | 36: 24 `houses[]`, 7 Westside, 2 mansions, 2 estate guesthouses, 1 guest cottage (worldgen_core §13) | 42+ lots | existing 36, plus 6 in a new south-east block |
| Homes with full interiors, claimable | 4 enterable (Westside garages); 4 dead walk-ins (worldgen_core §13) | **40** | 4 core, 20 outer homes rebuilt as archetypes on their lots with doors facing the road, 7 Westside, 2 estate guesthouses, 1 guest cottage, 6 new. Mansions get an exterior plus foyer only (O3) |
| House archetypes | 4 core styles, 1 parametric outer, 1 Westside, 2 mansions | **8**: bungalow, two-storey, Victorian, ranch, split-level, cottage, apartment block, large older house | core 0 Victorian, core 1 bungalow, core 2 two-storey, core 3 cottage; outer homes become ranch, split-level, cottage, bungalow and two-storey; Westside becomes large older house; new block adds an apartment block, Victorian, split-level and two-storey |
| Interior templates | 0 working | 16 (2 per archetype), seeded furnishing variants giving 40 distinct interiors | `data/interiors/*` |
| Restaurants | 4 food lots in core scope (Chili's, corner shops, 2 ice-cream; worldgen_core §15) plus Quay facades named as eateries | **10 lots, 8 kinds**, each with patio or dumpster | keep Chili's (bar & grill), corner shops -> diner, 2 ice-cream (fixed: grounded and solid). New: pizza and taco on the east "grass lots" (bay lines z = ±139, x 410-635), Chinese on the Westside frontage. Promote Quay facades: WILLOW BAKERY -> bakery, COPPER KETTLE -> café, THE OLD ANCHOR -> pub (districts_art §15). The Galleria COPPER CUP CAFE stays as an 11th |
| New lot types | none | barber, music store, hardware, laundromat, bookshop (promote QUAYSIDE BOOKS), pet store, corner grocery, school with playground, church, marina, apartment block, pier, beach; gas station (2 existing, typed), park with gazebo and community garden (existing, typed). That is about 15 new types plus the 8 restaurant kinds | east grass lots: music, pet store, laundromat, barber. Westside frontage: hardware, grocery. South-east block: school, church. Coast: marina, pier, beach |
| Hospital | 94 x 96 shell; open ward, triage, reception; no isolation, pharmacy or staff room; teleport entry (hospital §11) | room program in `buildings/hospital.json` | front third unchanged. Middle: Ward A (bays 1-4) and Ward B (bays 5-8) behind a real wall. Back third (local z 25-48): isolation (2 rooms plus airlock), pharmacy (12 item kinds on slotted shelves for fetch tasks), staff room, supply, observation. Annex: covered ambulance bay with stretcher route. Roof: downspout and gutter routes plus a roof hatch into the ported 7-node duct (`duct` route kind), with the hatch moved over an aisle (hospital §Added by verifier 1). 10 treatment stations |
| Police station | 46 x 31 shell, never enterable (hospital §8.1) | about 60 x 44 plus garage annex | lobby and front desk, briefing room (quest board), lockers (outfit swap), dispatch and radar room, 2 holding cells (burglars), drone console with stair to a roof pad, garage (2 player patrol cars plus 2 AI cruisers), upgrade board; guarded against the rodent only |
| Hollow trees | 1 decorative stump (wildlife §6.4) | 11 (§3.6) | `town/hollows.json` |
| Forage sources | none interactive (wildlife §10) | every lot type, plus restored v4.1 caches, gardens, feeders and trash (wildlife §11) | §3.8 |
| Backdrop | fog edge only (districts_art §14.4) | ocean north with river-mouth marina near (850, 480); mountains, hills and plains south and west; 3 depth bands; distant road; radio tower on the measured sunset azimuth with blinking lights | `backdrop/backdrop.json`; orientation is O1 |

---

## 4. Order of operations (inside the single build pass)

**Shape.** Waves 0-5. Waves run internally with Claude-verifiable exit criteria. Two subagent streams run in parallel:

- **Stream A:** world, data and content.
- **Stream B:** actors and gameplay.

The owner is pulled in only for a small number of short, click-by-click Studio sessions (Appendix A).

The **first build the owner plays (end of Wave 1) already contains every role**. There is no walkable-town-first milestone (brief, opening paragraph). It still ships the whole town as data on blockout geometry. That is the point of the data-first order: content volume is not a late phase, because the full town exists as data from Wave 1, and later waves only swap in better views of it.

### Wave 0: pipeline, contracts and spikes (nothing playable yet)

| Step | Stream | Builds | Exit criterion |
|---|---|---|---|
| 0.1 | A | Repo and `ci.sh`; the toolchain installed by an environment setup script (cargo: rojo 7.7.1, lune 0.11.1, stylua with `--features luau`, the patched selene; bpy 5.2.3 venv; node harvest deps), because the container is ephemeral | `ci.sh` runs fmt, lint and unit on a clean container in under about 15 minutes |
| 0.2 | A | `tools/harvest` against the pinned HTML (SHA check) | 1,332 routes; 95 fork trunks and 770 forks; 81,613 index samples; 95 trees; 24 nests; 12 apples; 110 supports, all matching routes §0 and the verification logs |
| 0.3 | A | Schemas; one-time migration of `spec/data/*` into `data/`; `tools/compile` v0 (validate and emit); reports | 90 + 153 lots, 116 roads, 25 lanes and 87 cast entries validate; reports diff cleanly against spec counts |
| 0.4 | B | `Units`, `World/Height` (verbatim port), `Math/*`, `Routes/Registry` and `Graph`, `Swept` | Lune: route samples within 0.01 u of the harvest; fork and junction picks match the harvest; swept golden cases from traffic §8.4 |
| 0.5 | A | `src/worldgen` Factory plus 6 generic builders: box building, gable house, road ribbon, pole, wire-from-route, tree-from-routes placeholder; `tools/bake` | `build/world/*.rbxm` holds every v5.4 lot as blockout; `rojo build` succeeds; bake report |
| 0.6 | A | `tools/cloud`: save an unpublished TEST version; one Luau Execution task runs RequireAll, DataIntegrity and BakeParity | green JSON result in CI |
| 0.7 | B | Puppet rigs (squirrel, fox, deer: Parts plus Motor6D with region names, built by Lune from `art/*/rig_contract.json`); bpy procedural clips (7 brief clips plus extras); `clips_to_json`, then Lune KeyframeSequences | rigs load; clips play through `RegisterAnimationClip` in Studio (Session 1) |
| 0.8 | A+B | **Spikes S1-S8**, below | each spike records go or fallback in `docs/decisions.md` |

| Spike | Question | Where | Fallback if it fails |
|---|---|---|---|
| S1 | Possessing a Humanoid body and an AnimationController body mid-stride under StreamingEnabled: ownership, animation replication, camera (feasibility §B.a) | owner, Session 1 (2 clients) | Server Authority beta for animals; or respawn-style possession with a blend-in |
| S2 | Lune-built KeyframeSequence -> Open Cloud Animation upload -> loads and plays on a server | headless | Studio Animation Editor import (D9) |
| S3 | bpy static FBX -> Open Cloud Model -> MeshId harvested with Luau Execution `InsertService:LoadAsset` -> Lune MeshPart renders; arrow-facing test | headless, plus the owner glances at the arrow | the owner saves the place to file and Claude runs `rojo syncback` (D5) |
| S4 | Time for `Terrain:WriteVoxels` over 4,350 x 2,520 st plus backdrop near-hills | headless | Studio-baked TerrainRegion pasted at boot (D1) |
| S5 | `require` time and memory of the largest generated data chunk | headless | buffer encoding; smaller chunks (D2) |
| S6 | SpicyTools `AssetService:CreateAssetAsync` for Model (and Animation?) from a plugin | owner, Session 1 | right-click > Save to Roblox, then type the id into the plugin field |
| S7 | 60 x `CreateHumanoidModelFromDescription` plus `ApplyDescription`: server time and memory | headless | fewer unique descriptions; cloned templates |
| S8 | Extract one accessory from a real avatar description and fit it to an animal `HatSocket` | headless | curated accessory set (D10 fallback) |

**Owner, Session 1 (about 40 minutes):**

- create the TEST and LIVE experiences and settings;
- create the API key and enter it through the secure credential form, never in chat;
- pass Claude the universe and place ids;
- open TEST; save the plugin locally;
- run the S1 and S6 checklists.

**Wave 0 exit:** `ci.sh` is green end to end, including the cloud stage. The harvest reproduces v5.4. All 8 spikes are decided.

### Wave 1: the first runnable build (every role playable, the whole town as data)

Stream A builds out the world. Stream B builds the actors and every role. The step order inside each stream follows its dependencies. Stream B's B1 needs only Wave 0. B5 needs A4 (lanes) and A2 (nav). B6 needs A3 (hollow routes).

| Step | Stream | Builds | Exit criterion (Claude-verifiable) |
|---|---|---|---|
| A1 | A | Full town data: all v5.4 lots retyped, plus every expansion lot (§3.13). Blockout builders per family: House (8 parametric archetypes with flair), Storefront, Restaurant (with patio or dumpster), Civic, Hospital program, Police program, Estate, Quay (index-driven, districts_art §3.4), Galleria, Park, Cemetery, Garden, Marina, Pier, Beach, Sewer | invariants 1, 2 and 4 pass; bake report counts |
| A2 | A | 16 interior templates (primitive furniture, doors, hide spots, nav); 40 homes; 3 defenders | invariants 3 and 9 |
| A3 | A | Routes: harvested minus rebuilt lots, plus templates (houses, shops, hospital roof, duct and hatch, police roof, 11 hollows), plus linkers | invariant 7; connectivity report |
| A4 | A | Traffic data: road fixes, intersections and controls, curbs, hydrants, parking, lane graph, fleet | invariant 8 |
| A5 | A | Runtime terrain; backdrop blockout (ocean plane and shore water, hill and mountain silhouettes set Persistent, blinking tower); massing model; sky, day curve, 16 moon textures (`tools/textures`, Open Cloud images) | BakeParity green; images in the manifest |
| A6 | A | Forage and hollow data: sources per lot type, premium sets, 10 caches, 12 apple trees, 10 acorn pools; map vector data and district labels (districts_art §1) | forage and map invariants |
| B1 | B | `Actors` registry, possession, validation, AI scheduler; populate about 50 humans (role outfits as HumanoidDescriptions in stock colours), 12 squirrels, 1 rodent, 4 deer, 1 fox (puppets); `Animation/Driver` | Luau Execution: populate under 3 s; scheduler at or under 4 ms for 70 brains (synthetic) |
| B2 | B | Controllers and cameras for squirrel (rail and ground port of routes §5-§15), human, fox, deer, drone, car; keyboard, mouse and basic gamepad | Lune: controller step functions against golden traces from the HTML formulas |
| B3 | B | `Roles/Ladder` and `Roles/Service`; queue and rank UI; **dev role picker**; join possesses a random AI body, leave releases it | Ladder unit tests: every transition in brief §6 |
| B4 | B | Rodent core: stalk; pounce with wind-up, commit and recovery; bite; kick and baton; health and death through the Ladder. Infection: per actor, town %, squirrel bites, hidden win, session reset | Combat and Infection unit tests; a Luau Execution scenario test |
| B5 | B | Hospital v1: ambulance and walk-in admissions, disinfect loop at stations, fetch task v1, staff kills inside. Police v1: patrol on foot, baton, tickets (parking, speeding by radar, stop sign), argument v1, burglar v1, top-two car assignment (enter, exit, drive, siren). Drone v1: flight, feed, mark, which drops markers and calls vigilantes (dev unlock). Sightings and map | Quest and Sightings scenario tests (Luau Execution, steppable) |
| B6 | B | Traffic simulation and server swept collision; AI patrol and ambulances on the lane graph. Squirrel loop: forage, store, meter and ownership, stink gland. Seasons: week, winter flag, forage reduction, winter-end check. Fox hunts squirrels (ignores the rodent, repelled by stink). Deer wander and are startled by cars and the drone | traffic golden tests; season calendar tests |
| B7 | B | Avatar blend v1 (human recipe; animal tints on puppet regions); HUD per role; notification priority queue; Telemetry overlay | blend unit tests; S8 data |
| C1 | A+B | Integration: merge, full cloud suite, save TEST version, write the Session 2 checklist | everything green |

**What the first runnable build contains (so that every role is test-playable).**

| Area | Contents |
|---|---|
| World | Terrain over the whole playable rectangle. All roads, with gaps fixed. **Every** lot from data: v5.4 districts plus the full expansion, as parametric blockouts with flair colours. 40 enterable homes with blockout interiors, working doors and hide spots. The hospital with all brief rooms. The police station with interior and garage. 11 hollow trees with working interiors (shaft, spiral, knothole, log). Quay, Galleria and sewer. Backdrop blockout with ocean and mountains. Day cycle with a phased moon and blinking tower. Massing view for the drone. SurfaceGui signs |
| Routes | All 1,332 harvested routes plus template routes. Trees, poles and wires drawn from their route curves, so rails and visuals match |
| Bodies | About 50 R15 humans in stock role colours (Roblox default R15 animations plus procedural custom clips). 12 squirrels, 1 rodent, 4 deer and 1 fox on puppet rigs with the full clip set. Part-built drone and vehicles with true logical dimensions |
| Human | Walks the town (possessed mid-stride on join); works a shop job socket for credits; kicks (rank from a successful kick, addendum A2); hides in houses; claims a home (remodel UI stubbed to paint and furniture swaps) |
| Hospital staff | Station disinfect loop; fetch the right item from the pharmacy against a timer; kills the rodent inside the building and is promoted to squirrel |
| Police | Baton; sightings map and minimap; ticket a parked car, a speeder (radar) or a stop-sign runner; settle an argument; catch a burglar. **Top two** officers get patrol cars: enter, exit, drive, siren and lights; the car can run over the rodent |
| Drone | Unlocked by a dev toggle (the real unlock is Wave 4); full flight; camera feed; spot-and-mark reveals the rodent to officers for a short window and calls vigilantes |
| Regular squirrel | Rails, leaps, forks and wires; forage sources; carry and store nuts in a hollow; meter and ownership at 70%; stink gland at 95% or more; can be infected; winter-end check |
| Spicy rodent | Stalk, pounce (3 phases), bite (infects humans; squirrel bites raise the town rate); health; kicked, beaten or run over ends the run (the player becomes the lowest human); hidden win |
| Fox | Hunts regular squirrels; a valid target must be within 2.5 u of the ground, so trees are safe (wildlife §13.9); cannot harm the rodent; repelled by stink |
| Deer | Wanders; startled by traffic and the drone |
| Ladder | Queue, promotions and side exits per brief §6. Dev picker for testers |

**Owner, Session 2: first-runnable-build playtest** (about 75 minutes; 4 clients in Studio; checklist in §6.5).

**Wave 1 exit:**

- Every role's checklist passes its core steps, or every failure is logged with repro steps.
- No blocker bugs.
- The Telemetry overlay shows server frame time under 16 ms and AI time under 4 ms during the 4-client test.

### Wave 2: content to spec, through Lane 2 cloud meshes (no owner work beyond one review)

| Step | Stream | Builds | Exit criterion |
|---|---|---|---|
| 2.1 | A | `kit_from_archetype.py`: 8 house kits with flair parts. Storefront, restaurant and civic kits. Uploaded through Open Cloud; manifest set to v1 | all lots resolve to kits; invariant 10 budgets |
| 2.2 | A | `tree_from_routes.py`: 95 existing trees plus new ones; apple trees; leaves split out for winter. Route-driven fences and poles | trees within budget; zero route/visual mismatch (sampled distance check) |
| 2.3 | B | Furniture kit (about 60 pieces); 40 interiors furnished; remodel catalogue; hospital and police fit-out with item shelves | interior budgets; nav still connected |
| 2.4 | B | Vehicles (10 types plus the drone); street furniture; Quay modular kit; marina, pier and beach; backdrop meshes (3 mountain layers, tree-line cards, towers) | Persistent and SLIM flags set; drone-altitude screenshots taken in Session 3 |
| 2.5 | A | Seeded dressing (hedges, flowers, shrubs, litter: worldgen_core §16); bunting; lamps (Neon, with PointLights client-toggled at dusk); signage pass; art-direction pass against districts_art §14.2; winter grade (snow terrain material swap, bare-tree leaf hide) | lighting keyframes match the §14.3 table |

**Owner, Session 3: content review** (about 45 minutes): drone flyover at 300 st, 6 interiors, sunrise, sunset, night, moon.

**Wave 2 exit:** budgets pass, and the owner has signed off on the look direction, with notes captured as data or tunable changes.

### Wave 3: hero art (Lane 3) and human looks

| Step | Builds | Owner |
|---|---|---|
| 3.1 | Squirrel hero rig (same bone names as the puppet's main chain; fur cards; regions), clips re-authored on the hero armature | **Session 4, import night 1** (about 45 minutes): squirrel and rodent |
| 3.2 | Spicy rodent mesh and texture variant (zombie-lite: mangy, stitched bald patches, a few ribs, natural fur colours, a little blood on muzzle and claws, oversized bloodshot eyes, crazed buck-tooth grin) plus extra clips | same session |
| 3.3 | Fox; deer (doe, buck, fawn); 2 premium hollow trees with interiors (sockets and routes exported back into data) | **Session 5, import night 2** (about 45 minutes) |
| 3.4 | Human looks: about 50 classic clothing templates (Lane 4); role props and fetch items (Lane 2); 6 adult body types via HumanoidDescription scales on the bases chosen in O9; defenders' looks | none (catalog picks in O9) |

**Wave 3 exit:**

- Manifest entries are final.
- Rig-contract validation passes.
- The cloud test `AssetsLoad` loads every id (this catches ownership errors, feasibility §B.c).
- The blend works on hero rigs.

### Wave 4: depth and tuning (systems to full brief)

| Step | Builds |
|---|---|
| 4.1 | Combat in full: feints, zig-zag, stamina; human responses (flinch, swing, kick, back away, flee) chosen by awareness and nerve; vigilantes at 8%, re-rolled per in-game day (O16); defender burst-outs; indoor chases (squirrel §25.2; humans §14.3-§14.7) |
| 4.2 | Police in full: slots expand 5 -> 8 by performance, with later officers more aggressive (hospital §11.14 baselines); drone unlock upgrade; fender benders with drivers who step out; burglar AI using interior nav; argument mediation UI |
| 4.3 | Hospital in full: performance metric (admission-to-cure time), station upgrades, infected staff cure slower, fetch variety, isolation flow |
| 4.4 | Economy: credits, upgrades, homes and remodel points per real day; seasons (premium weekly raids, winter survival threshold); wildlife extras (O15); audio and speech bubbles; mobile and gamepad bindings |
| 4.5 | Performance: Parallel Luau perception only if profiling demands it; replication budgets; headless 70-brain benchmark |

**Owner, Session 6:** full playtest with friends on a private TEST server or Team Test (about 60 minutes).

**Wave 4 exit:** the tuning checklist is closed; server at or above 55 Hz with the session's player count; AI at or under 4 ms.

### Wave 5: release

| Step | Builds |
|---|---|
| 5.1 | Publish LIVE through Open Cloud. The saved place holds no SurfaceAppearance, unions or BaseWrap, because those live in runtime-loaded models (D5). Fallback: publish from Studio |
| 5.2 | Max players 50; SLIM check at drone altitude (massing fallback ready); maturity questionnaire (O10); DataStores live |

**Owner, Session 7:** release checklist (about 30 minutes).

### Order alternatives for the owner to weigh

1. **As proposed:** pipeline, then a first runnable build on blockouts holding the full data, then content kits, hero art, depth and release.
2. **Hero squirrel in parallel from Wave 0.** If the owner wants a commissioned or hand-sculpted squirrel, start it during Wave 0. The rig contract (bone names, sockets, regions) is frozen in Wave 0, so nothing else moves.
3. **Depth before kits** (swap Waves 2 and 4) if the Session 2 playtest shows gameplay is the bigger risk. Content kits only touch `art/` and the manifest, so they can slide without blocking anything.

---

## 5. Asset plan

### 5.1 Conventions every asset follows

- **Rig contract** (`art/<species>/rig_contract.json`). It fixes:
  - bone names and hierarchy; Root at the origin with no weights; at most 4 influences per vertex; at most 20k triangles per mesh (feasibility §A5, §B.c);
  - region MeshParts (`Body`, `FurCards`, `Eyes`, `Pattern`) for the avatar blend (D10);
  - sockets (`HatSocket`, `MouthSocket` for carried nuts and fetch items, `TailTip`, `PawL`, `PawR`);
  - forward +Z; squirrel shoulder height 1.2 st (brief §2, O2).

  The puppet rig carries the same names. The plugin's **Validate Rig** button and `check_budget.py` enforce the contract.
- **Export.** Use the feasibility §A5 settings:
  - Unit System None; FBX Unit Scale;
  - Z Forward / Y Up (with the +Z authoring rule verified in S3);
  - Leaf Bones off; Simplify 0;
  - one clip per FBX, keyed from frame 0, scene named after the clip, plus a rig-only FBX;
  - for Lane 2, one static mesh per FBX.
- **Sockets and routes travel with the art.** Named empties (`socket:door_front`, `socket:job:register`, `socket:forage:rear_bin`, `socket:hide:under_bed`) and curves (`route:trunk:pipe:downspout_fr`) export to `*.sockets.json` and `*.routes.json`, which `tools/compile` consumes.
- **Textures.**
  - Shared trim sheets and atlases wherever possible.
  - Hero maps at 1024 px; props at 512 or 256 px (feasibility §B.g: about 256 px suits a 2 x 2 x 2-stud object).
  - Lane 2 uses `TextureID` plus `Color`. PBR (SurfaceAppearance) is used only on Lane 3 heroes.
- **Generated, not hand-made, where possible.** Lane 2 assets come from bpy scripts. The script is the source; FBX files are build artefacts, recorded by hash in the manifest. Only hand-authored `.blend` files go to LFS.

### 5.2 Prioritised asset list with budgets

Priority follows gameplay criticality, then screen coverage. Triangle counts are LOD0.

| Pri | Asset | Lane | Tris | Bones | Textures | Clips / contents | Placeholder until it lands |
|---|---|---|---|---|---|---|---|
| 1 | **Regular squirrel** (hero) | 3 | body 6-8k, fur cards/shells 3-6k (separate MeshPart), eyes 0.2k; total 14k or less | about 32: Root, Hips, Spine1-3, Neck, Head, Jaw, Ear L/R, Tail1-6, 4 per foreleg, 4 per hind leg | body Color/Normal/Roughness 1024; cards atlas 512 (alpha cutout) | Brief 7: Run, Climb, WireTraverse, Leap, Pounce (Windup, Commit, Recover), BiteDance, Sneak. Plus Idle, Walk, ClimbIdle, WireIdle, Land, Forage, Store, StinkBurst, Hit, Death, Rest, Knothole, RiverScramble. Tail spring chain at runtime (squirrel §24) | Puppet (Lune Parts plus Motor6D), procedural clips |
| 2 | **Spicy rodent** | 3 | body variant 9k or less, mange cards 4k or less | same skeleton | own 1024 set; emissive mask for the eyes | all of priority 1, plus Feint, ZigzagLean (additive), KickedHit, RunOverDeath. Art: zombie-lite, natural fur (no green), a little blood on muzzle and claws, oversized bloodshot eyes, buck-tooth grin | priority 1 puppet, mangy palette, red emissive eyes |
| 3 | **Humans** | 4 (data), optional 3 | R15 catalog bodies, or custom semi-realistic R15 at 10k or less plus a dynamic head at 4k or less (O9) | R15 | classic shirt and pants 585x559: about 20 roles x 2-3 colourways, about 50 images, generated by `tools/textures` | Roblox default R15 set, plus custom: Kick (3 phases), Swing, Flinch, BackAway, PanicFlee, BatonSwing, RollingPin, BroomSwipe, work loops (cut, cashier, cook, type, mop), Disinfect, Carry, WriteTicket, Argue x2, Mediate, DriveSit, PilotConsole, Cower, BurglarSneak, KnockedDown, InfectedShamble | default body in stock role colours |
| 3a | Role outfits (data) | 4 | none | none | as above | Townsperson x6, police officer, police sergeant (drivers), doctor, nurse, guard, orderly, EMT, cyclist, jogger, mail carrier, barber, shop clerk, cook, waiter, gas attendant, hardware clerk, teacher, pastor, burglar, 2 older housewife defenders (different demographics), broom man; mime and kids per O10 | stock colours |
| 4 | Role props and fetch items | 2 | 0.2-1.5k each | none | shared 256 atlas | baton, ticket book, radar gun, clipboard, police cap, stethoscope, rolling pin, broom, mail bag, helmet, burglar sack and beanie, extinguisher; 12 fetch items (6 colour-coded medicines, thermometer, syringe, bandage, scalpel, blood-pressure cuff, splint) | coloured Parts with SurfaceGui labels |
| 5 | Patrol car (drivable) | 2 | 8k or less, cabin included; light-bar meshes separate (Neon) | none | 512 | 4 doors (cosmetic), seat sockets, siren and light sockets | Part car at the true logical box |
| 6 | House kits (8 archetypes plus flair parts) | 2 | 10k or less per assembled exterior | none | shared 2048 trim sheet plus 1024 tiling siding, brick and shingle | generated from archetype JSON | parametric blockout (same JSON) |
| 7 | Trees (route-driven, about 100) plus apple trees (12) | 2 | 3-6k tubes plus 2-4k leaf cards (separate MeshPart, hidden in winter); giants 12k or less; apple 4k or less, fruit separate | none | bark 1024 tiling; leaf atlas 1024 | built **around the harvested route curves** | Part tubes along the curves |
| 8 | Premium hollow trees x2 (shaft, spiral) | 3 (PBR) or 2 | 20k or less per mesh; trunk shell, interior and canopy as separate meshes | none | bark 1024 plus interior 1024 | sockets: chambers, knotholes, nook; routes: hollow and ramp | hollow ring of Parts plus rails |
| 9 | Storefront, restaurant and civic kits (school, church) | 2 | 8k or less per building; civic 15k or less (split) | none | shared trim sheet | patio, dumpster, awning and sign-board sockets | blockout |
| 10 | Fox | 3 | 9k or less | about 30 (tail 5) | 1024 | Idle, Walk, Trot, Run, Stalk, Lunge, Warn, Flee, Sit, Sniff, Hit, Repelled | puppet |
| 11 | Deer (doe base; buck antlers as an accessory; fawn by scale and a spots map) | 3 | 9k plus 1.5k antlers | about 32 | 1024 plus a fawn variant | Idle, Graze, Walk, Trot, Gallop, Startle, Alert, LieDown, Hit | puppet |
| 12 | Furniture kit (about 60 pieces) | 2 | 1.5k or less each | none | shared 2048 atlas | hide-spot sockets | primitives |
| 13 | Hospital and police fit-out | 2 | 2k or less each | none | shared atlas | beds, carts, stations, isolation doors, pharmacy shelves with item slots, lockers, cells, radar console, drone console, roof pad | primitives |
| 14 | Other vehicles: sedan, ambulance, trolley, ice-cream van, dump truck, RV, motorcycle, bicycle; drone | 2 | sedan 4k; others 6-7k; motorcycle 2.5k; bicycle 1.5k; drone 3k (rotors separate) | none | 512 | logical boxes from traffic §1 | Part vehicles |
| 15 | Street furniture and utility | 2 | pole 0.6k, streetlight 0.8k, signal 0.8k, stop sign 0.2k, hydrant 0.4k, bench 0.6k, bin 0.3k, dumpster 0.8k, mailbox 0.2k, feeder 0.3k, shed 1.5k, doghouse 0.8k, fence 0.3k per 3.3 u | none | shared 1024 atlas | placed by rule from data | primitives |
| 16 | Quay modular kit (6 pieces), bridge, clock tower | 2 | 3k or less per module; bridge 15k or less (split) | none | Quay palette atlas | recoloured per lot (districts_art §16) | blockout |
| 17 | Backdrop: 3 mountain layers, mid-hill tree-line cards, radio tower (lattice), cell tower, pier, marina docks, 3 boats, beach props | 2 | mountains 20k or less per mesh (several meshes, vertex-colour aerial perspective); radio tower 6k; pier 8k; boats 3k | none | 1024 | Persistent; tower beacon 0.5 Hz plus steady side lights (districts_art §14.4) | wedge silhouettes |
| 18 | Images | 2 | none | none | moon phases 16 x 512; map render 2048; sign and trim atlases | from `tools/textures` | procedural or vector |
| 19 | Audio | Open Cloud audio, or Roblox Creator Store sounds | none | none | none | upload quota is 10 per month, or 100 if ID-verified (feasibility §B.d); prefer library sounds | silent |

### 5.3 Placeholder strategy

- **Every logical asset has a working placeholder from Wave 1.**
  - Puppet rigs and blockouts are built by Lune or worldgen from the same contract and archetype JSON. They have the final bounding box, sockets, region names and clip names.
  - So swapping in art changes only `manifest.status` and ids. Gameplay, hitboxes and routes never move. This is addendum A3's "drop anything that breaks silhouette or hitboxes", applied to our own art.
- Clips are authored once on the puppet armature, which shares the hero's main-chain bone names. They are re-timed or re-authored on the hero armature in Wave 3; clip names and the state-to-clip table stay the same.
- A dev toggle tints placeholders magenta, so the owner can see at a glance what is still placeholder.
- **Quality bar.** Claude can script competent procedural meshes, rigs and clips headlessly with bpy, but cannot hand-sculpt or judge look-dev (feasibility §"What I can do"). The semi-realistic target for the squirrel, rodent, fox, deer and custom human bodies may need an artist pass. That is owner decision O9. The pipeline and the rig contract make an external artist's drop a single manifest edit.

---

## 6. Testing

### 6.1 Static checks (every CI run)

- `stylua --check` (built with `--features luau`).
- `selene`, using the committed `roblox.yml`.
- On the Mac only: `luau-lsp analyze` with the sourcemap. There is no Luau type checker in the container (feasibility Blocker 1). A local source build of luau-lsp would fix that if the owner permits it (O14).

### 6.2 Lune unit tests (`tests/unit`, pure modules, golden data from the specs and the harvest)

| Module | What is asserted |
|---|---|
| `Routes/*` | Sample points equal the harvest within 0.01 u. Fork lists equal the 95 harvested trunks. Junction picks, end-links at 0.48 u and transfers at 1.7 u behave as in routes §3 and §11. `RouteMotion.advance` clamps |
| `Math/Swept` | Every worked case in traffic §8.4; teleport skip; stationary skip |
| `World/Height` | Flat core exactly 0 for Chebyshev distance up to 104; sampled maxima (worldgen_core §3); river and deck ramps |
| `Roles/Ladder` | Every brief §6 transition, including edge cases: no free squirrel body; more than 30% infection goes to hospital; hospital kill inside goes to squirrel; side-exit return keeps the previous human rank. Rank formulas; slots 5 -> 8 |
| `Combat/Rules` | Phase windows; "bite into a raised arm fails"; two kicks without recovery kill; defender x1.5 kills at low health; zig-zag and feint trade-offs |
| `Infection/Rules`, `Seasons/Calendar` | Town %, maturation, cure multiplier, hidden win; weeks, winter, moon phase (the feasibility `Moon.luau` tests are reused) |
| `Foraging/Rules` | Cooldowns, premium weekly raid, ownership at 70%, stink at 95% or more costing 30 |
| `Avatar/Blend` | Palette clamp; "bizarre" handling (neon becomes a single accent); rodent eyes stay red |
| `Net/Schema` | Payload validators reject malformed packets; rate limits |

### 6.3 Compile and bake tests

- The §3.12 invariants.
- Bake determinism: two runs give the same `BakeHash`.
- Per-district instance and triangle budgets.
- Every lot Model has `PrimaryPart`, Atomic mode, the SLIM flag where configured, and its sockets.
- Every route used by a hollow, a hospital route or a new roof is reachable (invariant 7).

### 6.4 Open Cloud Luau Execution integration tests (`tests/cloud`, real engine, headless)

**Limits** (feasibility §B.d):

- 5 task creations per minute; 10 incomplete tasks per place;
- 5 minutes of runtime;
- 4 MB of return data;
- no physics; scripts do not auto-run.

So **one task runs the whole suite** against the just-saved TEST version and returns JSON. A heavier nightly task runs the benchmarks. Services are steppable (§1.4), so tests call `init` and `step` directly with simulated time.

| Suite | Asserts |
|---|---|
| T1 RequireAll | Every module requires cleanly in the engine (catches API misuse Lune cannot see) |
| T2 DataIntegrity | Generated data decodes; counts match the reports |
| T3 BakeParity | A runtime bake inside the engine hashes the same as the Lune bake |
| T4 Terrain | `WriteVoxels` time for the full map (S4) and spot heights against `World/Height` |
| T5 RoutesInEngine | Registry and index build time; `nearest()` against Lune results |
| T6 Roles | Scenario scripts with fake players (actor ids) through the full ladder |
| T7 RodentLoop | Spawn actors, step Combat, Infection and Hospital through bite, admit and cure; hidden-win threshold |
| T8 Traffic | Step the lane simulation for 120 simulated seconds: no deadlock, stop-sign compliance rate equals the tunable, swept kills on scripted crossings |
| T9 AssetsLoad | `InsertService:LoadAsset` of every manifest model id; KeyframeSequence fetch for every animation id (ownership check) |
| T10 AvatarBlend | Real `HumanoidDescription`s from a fixed list of user ids yield valid recipes and tints |
| T11 Profiles | DataStore round trip in the TEST universe |
| T12 Bench (nightly) | 70 brains x 60 s simulated: ms per tick by tier; `CreateHumanoidModelFromDescription` x60 |

### 6.5 Owner playtest checklists (multi-client in Studio)

- Each checklist is a short markdown file in `tests/playtest/`, also shown in the plugin's **Checklist** pane.
- Every step is one action plus one expected result.
- The owner marks pass or fail and adds a one-line note or screenshot.
- The Telemetry overlay (toggle with F8) shows numbers the owner can read out: server frame ms, AI ms, actor counts, current role.

**Session 2 (first runnable build) checklist, abbreviated.** Studio: **Test** tab > **Clients and Servers** > Clients **4** > **Start**. Windows are labelled Player1-4.

| # | Window | Action | Expected |
|---|---|---|---|
| 1 | all | wait for the load screen to finish | each player is already walking as a townsperson; no one spawned from the sky |
| 2 | P1 | Dev picker (F7) > **Spicy Rodent** | P1 becomes the rodent; the old body walks on, AI-driven |
| 3 | P2 | Dev picker > **Police** | P2 is an officer; the minimap appears |
| 4 | P1 | hold right mouse near a townsperson, then left click | wind-up, lunge, bite; the victim shows bitten; P2's map shows a sighting marker |
| 5 | P2 | press E at the garage car (top-two driver) | P2 enters the car; W/S/A/D drive; H toggles the siren; F exits |
| 6 | P2 | drive over P1 | P1's run ends; P1 becomes the lowest human; P2 sees a promotion toast |
| 7 | P3 | Dev picker > **Hospital** | P3 at reception; an infected patient arrives |
| 8 | P3 | at a station, hold E, then follow the 3-step prompt | the patient is cured; town infection drops |
| 9 | P3 | accept a fetch task, bring the right bottle | timer stops; credits are added |
| 10 | P4 | Dev picker > **Squirrel**; climb a tree; take a wire across the street | rail movement and leaps work; the camera follows |
| 11 | P4 | take from a garden, then store in hollow H2 (spiral) | the nut meter rises; at 70% or more, "You own this tree" |
| 12 | P4 | Dev picker > **Fox**; chase an AI squirrel on the ground | lunge works; a squirrel up a tree is safe |
| 13 | P2 | Dev picker > **Drone** (dev unlock); fly to 300 studs; mark the rodent | the whole town is visible; a mark appears for police; vigilantes move to it |
| 14 | P4 | Dev picker > **Deer**; stand near the road as a car passes | the deer startles and flees |
| 15 | P1 | Dev picker > **Squirrel**; fill the stink gland with the dev fill; fire it near the fox | the fox is repelled |
| 16 | any | Dev panel > "Skip to winter end" | snow; squirrels below the threshold become humans |
| 17 | P2 | leave the game (close the window) | P2's body continues, AI-driven |

Later checklists cover:

- Session 3: content review (drone flyover route, 6 named interiors, lighting phases).
- Sessions 4-5: import nights. Each step is an exact menu path; each asset ends with **Validate Rig** reporting green.
- Session 6: the full loop with friends.
- Session 7: release.

---

## 7. Risks, mitigations and owner decisions

### 7.1 Top risks

| # | Risk | Likelihood / impact | Mitigation | Fallback |
|---|---|---|---|---|
| R1 | Mid-stride possession feels wrong: animation replication, ownership, camera (feasibility §B.a, medium-high confidence only) | M / H | S1 in Wave 0; each species has its own animation driver; the Animator is created on the server; `RequestStreamAroundAsync` before the swap | Server Authority beta for animals; a short blend-in |
| R2 | Open Cloud Animation upload rejects Lune-built KeyframeSequences ("edited outside of Studio") | M / M | S2; Studio-only `RegisterAnimationClip` covers every Studio playtest | owner imports clips in the Animation Editor (about 1 minute per clip) or plugin batch publish (S6) |
| R3 | Lane 2 id harvesting (MeshId from uploaded Model packages) fails, or Luau Execution cannot call `InsertService` | M / M | S3 | owner saves the place to file; Claude runs `rojo syncback` |
| R4 | Server performance: about 60 Humanoids, 14 squirrels, about 45 vehicles and 50 players | M / H | anchored `BulkMoveTo` AI, tiered scheduler at 4 ms, unreliable batched streams, client-only fauna, Telemetry from Wave 1, nightly bench (T12) | fewer AI humans (to 40); a wider far tier; Parallel Luau |
| R5 | Drone view: SLIM only appears after publishing; distant parts stream out | M / H | district-level SLIM; Persistent backdrop and landmarks | the massing model (D3), which works regardless |
| R6 | Content volume: 40 interiors, 8 archetypes, about 25 lot types, about 100 trees | H / M | parametric generation from data; seeded flair; shared kits; the bake reports what is placeholder | ship with v1 procedural kits; prioritise interiors by visitation |
| R7 | Semi-realistic quality ceiling of procedural bpy art | H / M | rig contract plus manifest lets an artist's asset drop in with no code change | commissioned hero assets (O9) |
| R8 | The harvest depends on the exact v5.4 HTML (instrumentation drift) | L / M | pinned SHA-256; harvest output committed; `routes_catalog.json` as the formula fallback | re-implement generators from the catalog |
| R9 | Terrain write at boot is too slow | L / M | S4 | Studio-baked TerrainRegion |
| R10 | Large generated data modules hit engine limits | L / M | S5; chunking by district | buffer encoding |
| R11 | Ephemeral container: tool install takes about 10 minutes per new session; binaries are lost | H / L | environment setup script; everything in git; LFS only for hand-authored binaries | none needed |
| R12 | No Luau type checker in the container | H / L | Selene, unit tests, the cloud RequireAll suite | `luau-lsp` on the Mac, or permission to build it from source here |
| R13 | Animation and asset ownership mismatch (group vs user) gives "Failed to load animation" (feasibility §B.c) | M / H | decide ownership up front (O8); the API key's owner equals the experience owner; T9 AssetsLoad | re-upload under the right owner |
| R14 | Open Cloud limits: Luau Execution creates 5 per minute; Assets API 120 per minute | M / L | one batched suite task per CI run; upload queue with backoff | nightly heavy runs |
| R15 | Rojo-managed trees overwritten by API saves while the owner has local edits | M / M | the owner's imports go only to `ServerStorage.Inbox`; `harvest_ids` runs before every save; the checklist says "close Studio before Claude saves" | `rojo syncback` capture |
| R16 | Content maturity: "a little blood", horror tone, possessable children | M / M | moderate blood (decals on muzzle and claws only); profanity removed (districts_art §16); kids AI-only by default | owner chooses the maturity label (O10) |
| R17 | "Limited server count so a real queue exists" (brief §5): Roblox does not let an experience cap its number of servers | H / M | max players 50 plus "fill servers fully" settings; the queue is per server | matchmaking with reserved servers (TeleportService) later |

### 7.2 Owner decisions still needed (each has a recommended default so work can proceed)

| # | Decision | Recommended default | Source |
|---|---|---|---|
| O1 | Compass and backdrop sides | north = +Z (matching district names); ocean to the north at the river mouth with the marina near (850, 480); mountains, hills and plains south and west; tower on the measured sunset azimuth | worldgen_core §17.1; districts_art §14.4, §17.1 |
| O2 | Squirrel scale | brief: 1.2 st at the shoulder (about 1.6-2x the HTML relative size); re-tune offsets, radii and cameras in Tunables | routes §21.1; squirrel §27.14 |
| O3 | Which 40 homes; the 3 defender houses; outer-home doors | §3.13 split (34 existing plus 6 new); defenders in core house 0 (housewife A), Westside house 2 (housewife B) and outer home 12 (broom man); doors face the road | worldgen_core §17.2-§17.4; humans §16.3 |
| O4 | Hollow mapping | §3.6: H1 shaft, H2 spiral, 7 knothole trees, and H9 and H11 as fallen-log tunnels on their original sites, counted inside the 11; the v5.4 park log stays an extra shelter | wildlife §6.5, §16.11; owner's three variants |
| O5 | Restaurant and shop placement; which Quay facades get interiors | §3.13 (promote bakery, café, pub and books) | districts_art §17.5 |
| O6 | Traffic handedness and control plan | keep right everywhere; all-way stops on the grid; signals at boulevard x=347; AI drivers decorative, with a pooled actor stepping out for events | traffic §14.1, §14.6, §14.7 |
| O7 | Day length and moon method | 71.4 s per day (brief) with a non-linear curve holding sunrise and sunset; `MoonTextureId` swap first | districts_art §17.2, §17.3 |
| O8 | Asset ownership | user-owned (simplest); a group only if collaborators are coming | feasibility §B.c |
| O9 | Art bar | procedural bpy v1 for everything; commission or sculpt hero squirrel and rodent (optionally fox and deer); human bodies from 2-4 free Roblox bundles plus scale-based body types, with custom semi-realistic R15 bodies later | brief §7; owner art direction |
| O10 | Maturity and cast | "Mild" label; profanity removed; mime kept; kid cyclists AI-only (not possessable) | humans §16.6, §16.10 |
| O11 | Vehicle logical box | true mesh dimensions; parked cars never lethal | traffic §14.4, §14.14 |
| O12 | Sightings and infection visibility | sightings for police, drone and hospital; infection meter hidden from everyone (hidden win) | hospital §13.3, §13.10 |
| O13 | Git LFS for `.blend` files | yes; generated FBX files are not committed | none |
| O14 | Allow a luau-lsp source build in the container | yes (adds a strict type check to CI) | feasibility §A4 |
| O15 | HTML extras: chili rush, fashion stand, Galleria coins, cats, rabbits, dogs, idle predator | keep cats, dogs and rabbits as ambient; Galleria coins become forage crumbs; drop the idle predator (an AFK rodent hands its body to the AI); chili rush and fashion stand deferred to Wave 4 | squirrel §27; wildlife §16.1 |
| O16 | Penalty and economy numbers | infected squirrel loses 50% of nuts and drops 2 queue places; vigilantes re-rolled per in-game day | brief §6; humans §16.2 |
| O17 | AI rodent when no player holds the slot | on, with gentle aggression (so the town always has a threat), never triggering the hidden win alone | brief §5 |

---

## Appendix A: owner Studio sessions (click-by-click, few)

| Session | When | Length | What the owner clicks |
|---|---|---|---|
| 1 Setup and spikes | Wave 0 | about 40 min | (1) Creator Hub > Creations > **Create Experience** twice: "Spicy Rodents" and "Spicy Rodents TEST". (2) For each: set the place's max players to 50 (the exact menu path is printed in the Session 1 checklist, verified at the time); Studio > Game Settings > Avatar: **R15**; Security: **Enable Studio Access to API Services**. (3) Enter the API key in the secure form Claude opens (never in chat). (4) Copy the universe and place ids from the Creator Hub URL into chat. (5) Studio > File > Open from Roblox > TEST. (6) In Explorer: ServerStorage > SpicyToolsPlugin > right-click > **Save as Local Plugin**. (7) Run checklist S1: Test > Clients and Servers > 2 > Start, then the steps in the pane. (8) Run checklist S6: select `ServerStorage.Inbox.TestCube` > SpicyTools > **Publish Hero Asset**. (9) File > **Save to Roblox**. |
| 2 First-runnable-build playtest | end of Wave 1 | about 75 min | File > Open from Roblox > TEST; Test > Clients and Servers > 4 > Start; follow §6.5; close Studio when done |
| 3 Content review | end of Wave 2 | about 45 min | open TEST; Play solo; Dev picker > Drone; fly the marked tour; F7 > lighting phase buttons; open 6 listed houses |
| 4 Import night 1 | Wave 3 | about 45 min | per asset (squirrel, rodent): File > **Import 3D** > choose `art/<asset>/<asset>_rig.fbx` > Rig Type **Custom** > Upload off > Import > drag the result into `ServerStorage.Inbox` > drag `Color/Normal/Roughness` PNGs into the SurfaceAppearance fields (named in the checklist) > SpicyTools > **Validate Rig** (green) > **Publish Hero Asset** > File > Save to Roblox. Claude then harvests the ids. Animation Editor steps only if S2 or S6 fell back |
| 5 Import night 2 | Wave 3 | about 45 min | same as Session 4, for fox, deer and the 2 premium hollow trees |
| 6 Full playtest | end of Wave 4 | about 60 min | start a TEST private server from the Creator Hub and invite friends; or Team Test; run the loop checklist |
| 7 Release | Wave 5 | about 30 min | review LIVE after Claude's publish; complete the maturity questionnaire; set the experience Public |
