# Spicy Rodents on Roblox: BUILD PLAN

Status: the single plan the owner and Claude will execute. Nothing is built yet. Date: 2026-11-09. **Revision 3** (same day) absorbs **brief v2** (`reference/Roblox_Rebuild_Brief_v2.md`, the owner's live document, captured today) through `spec/BRIEF_V2_DELTA.md`: the owner's answers to the 36 decisions (§8), the hard 49-slot server, the hollow-tree rules, the spicy-rodent rule additions, the outbreak cinematic, the whole of §13a (human life: economy, reputation, gigs, mischief, vehicles, places and attractions, minigames, rides, paintball), §14 (camera), the §15 extras (traffic law for everyone, street lighting, off-road zone, Power kept) and the art rules. Revision 2 (same day) answered the adversarial review in `spec/design/critique.md`: the human body budget, CI-place timing, outfit and tint feasibility, an early drone far-view spike, cross-track dependencies, v5.4 behaviours kept or dropped explicitly, and the requirement traceability table in section 10. Every revision-2 decision stands unless this revision names the change.

**Backbone:** the roles-first proposal (`spec/design/proposal_roles_first.md`), with grafts from the risk-first and data-pipeline-first proposals. Section 9 has the scoring and the full graft list.

**Inputs (all present):** `reference/Roblox_Rebuild_Brief_v2.md` [brief v2 §n; **authoritative**: it supersedes the PDF and, wherever it speaks, the addendum], `reference/Roblox_Rebuild_Brief.txt` [brief §n, the PDF; still cited where v2 is word-for-word the same], `spec/BRIEF_ADDENDUM.md` [A1-A3 and Addendum B; valid where v2 is silent, with B1 and B2 the owner's two post-v2 answers], `spec/BRIEF_V2_DELTA.md` [delta; the V2-n inventory, conflicts C1-C22 and open questions Q1-Q24 this revision resolves], `spec/roblox_feasibility.md` [feas], `spec/PROJECT_IDS.md`, the eight subsystem specs (cited by file and section), the seven data files in `spec/data/`, and the three proposals [RF], [RK], [DP].

**Fixed facts this plan builds on:**

- Experience "Spicy Rodent": Universe **10775476638**, Place **106044514609985**, private, currently 50 max players; **the owner sets it to 49 on the Creator Hub before the FRB** (brief v2 §5, §15 dec 28; OS-0). The duplicate "Spicy Rodents" experience is never used.
- The owner's account is ID-verified and has Premium (Addendum B2): 100 audio uploads a month, and developer products can be sold.
- Repo **PedagogyGame/spicy-rodents-roblox** (private, Rojo project). The owner's website repo is never touched.
- An Open Cloud key reaches `apis.roblox.com` through the proxy (header injected; never in files). Scopes: assets r/w, universe-places write, luau-execution-sessions r/w. Reads are verified; the owner is correcting the luau-execution scope.
- Studio stays necessary for skinned-rig import, SurfaceAppearance, multi-client playtests and any Studio-only publish step.
- The container is Linux with 4 CPUs, no GUI, and is ephemeral; at most 2 subagents run at once. Everything lives in git.
- Places cannot be created through Open Cloud, and Roblox cannot cap how many servers an experience opens. Both facts shape the plan (Step 0 place creation; decision 26).

---

## 0. The plan in plain words (one screen)

**What we are building.** A new Roblox version of Spicy Rodents, written from scratch. Every person and animal in town is a "body" that either the computer or a player drives. When you join, you take over a body that is already walking; when you leave, the computer takes it back and it keeps walking. Promotions (townsperson to squirrel to spicy rodent) use the same trick. A server holds exactly 49 players (35 humans, 7 squirrels, the spicy rodent, 5 deer, 1 fox); when it is full, Roblox sends the next person to another server. The town always has more people than player places (about 70 walking and working, with at least 6 computer-driven police and 10 hospital staff on duty whatever the players do), so shops, the hospital and the police station are never empty. Being a human is a full game in its own right: Spicy Dollars, gigs, reputation, golf carts and bicycles, mischief, a corner store full of toys that work, a bowling alley, a steakhouse, two lounges, a sky lift, paintball in an abandoned TV station, and more.

**The order (one single build; nothing goes public until the end):**

1. **Agree the plan (now: chat, plus 5 minutes on the website).** You answer the first group of decisions in section 8 and add two empty places ("CI" and "Art Inbox") to your experience on the Roblox website (about 5 minutes). Nothing big is built until you say go.
2. **Wave 0: prove the risky parts.** Claude sets up the project and tests what is most likely to go wrong: taking over a moving body, squirrel climbing feel, cars running over squirrels fairly, server speed with about 90 computer-driven people plus animals and 45 cars, how the whole town looks from the drone, getting Blender art, outfits and animation into Roblox with as little of your time as possible, and the new questions brief v2 raises: physics minigames that feel right online, paintball hit detection, Robux purchases that are never double-charged and survive a server closing, first person inside a moving vehicle, 300 street lamps at once, and paintball garb on a possessed body. You do three short sessions (about 40 minutes in all). Then we look at the results together. **That review is the real "commit" point.**
3. **Wave 1: the skeleton** (nothing for you to play yet). The whole v5.4 town is rebuilt from the data file as grey blocks, with every climbing route, every traffic lane and bodies for every species, all checked automatically; the wallet, reputation, vehicle, minigame and ride frameworks exist as code with tests but no content.
4. **Wave 2: the FIRST RUNNABLE BUILD.** All eight roles playable: townsperson, hospital staff, police (with a drivable car, radar and sightings on the map), drone, squirrel, spicy rodent, fox and deer. The human role is already more than a waiting room: Spicy Dollars and a wage, the corner store with six working items, one gig (lawn mowing), reputation with thumbs up and down, a golf cart and bicycles, first person whenever you like, the taunt button. The rodent has its Power meter. Grey-box town and placeholder characters. You test it with a checklist.
5. **Waves 3 and 4, side by side: fill the town and deepen the play.** First the pieces the new play needs (stop signs everywhere, the 40 enterable homes and their defenders, the full hospital and police station, grey street lamps that really light up), then new restaurants and shops, 8 house styles, the 12 hollow trees, the hill with its sky lift and hilltop restaurant, and the off-road zone beyond the ridge; alongside, the full rodent duel with the new bite-aftermath rules, every police side quest, hospital fetch tasks and upgrades, winter, the mall coins, birds and insects, traffic law for everyone (police included), Robux purchases and saving, the outbreak cinematic, and **paintball in the TV station, built in Wave 4 as the brief says and playtested with you before it is called done** (if it does not shoot right, it is cut; nothing else depends on it).
6. **Waves 3c and 4b, side by side, right after:** the attractions land in waves. The attraction buildings and their interiors (corner store, doctor's office, museum, bowling alley with the ball-return squirrel tunnel, racquetball court, steakhouse, both lounges, the new mall, the antique store), the golf carts, bicycles, pickups and SUVs with their interiors; and the minigames one at a time in a fixed order (bowling first, then darts, pool and bumper pool, the three pinball tables, racquetball, volleyball, giant Jenga, the tilt labyrinth, the kite), the rides (sky lift, parasailing, wind tunnel, the steerable jet ski), all 22 store items, the gigs, mischief, NPC mini-missions, the lounge guards and bartenders, and the paintball garb. Each minigame gets a short "is it ironed out?" check with you.
7. **Wave 5: real art.** The squirrel and the spicy rodent come first, right after the first build. You approve turntable pictures before anything is imported. Rough is fine; the polish goes into the lounges, the paintball arena and the minigames, as you asked. No money is spent on art.
8. **Wave 6: sky and backdrop.** Mountains with layered fog, ocean, sunsets, stars, moon phases, the blinking tower, the final street-lighting pass and the look of the outbreak cinematic.
9. **Wave 7: harden and publish.**

**What you do, and when** (about 10.5-11.5 hours in total, spread out; up to about 2 hours more only if a Wave 0 test fails, mainly the automatic animation path). The rise from revision 2's 7 hours is almost all the paintball playtest you asked for and the per-minigame checks. You never use a terminal, git or Rojo. Claude saves each build into your experience; you open it from the Studio start page and press Test.

| When | What | Time |
|---|---|---|
| Now | Confirm the few decisions still open (section 8, items 37-44); on the website add the "CI" and "Art Inbox" places, set max players to 49, and create the Robux products (Claude gives the exact names and prices) | 20 min chat + 17 min web |
| Now | Studio, once: turn on "Enable Studio Access to API Services" so saving works in playtests | 2 min |
| End of Wave 0 | Studio: try taking over moving bodies | 20 min |
| End of Wave 0 | Studio: import one test squirrel | 10 min |
| End of Wave 0 | Roblox app: fly a test drone over a test town on a live private server | 10 min |
| End of Wave 0 | Read the one-page spike report and say go | 10 min |
| End of Wave 2 | **Play the FIRST RUNNABLE BUILD** with the checklist (can be split over two sittings) | 60-90 min |
| Wave 3 | Approve the town-plan page (now with the steakhouse, hill, TV station, bowling alley, new mall, lounges, corner store, doctor's office, museum, racquetball court and off-road zone) and the squirrel/rodent turntables (web) | 30 min |
| Wave 3 | Studio: import the squirrel and the rodent | 20 min |
| End of Wave 4 | Play build #2 | 60 min |
| End of Wave 4 | **Paintball playtest** with 2-4 windows; you decide whether it stays | 60 min |
| Wave 4b | Minigame checks, about 10-15 minutes each, in two sittings (bowling, darts, pool, pinball, racquetball, volleyball, Jenga, labyrinth) | 90 min |
| Wave 5 | Studio: import fox and deer; then people; then the hollow trees and the lounge kits (three short sittings) | 15 + 15 + 25 min |
| Wave 6 | Look at the sunset tower, the fog, the lamplit town at night, the hill vantage and the drone view | 30 min |
| Wave 7 | Play with friends on a private server, then approve the publish | 60-75 min |

**What the first runnable build lets you test.** A **LAB** button lets you become any role in one click and set up test situations ("spawn the rodent near me"). As a **townsperson** you work a shop job for Spicy Dollars, buy a water gun or a football at the corner store and use it, mow a lawn for a tip, give another player a thumbs up, sit at a cafe and watch your reputation rise, ride a golf cart or a bicycle in first person, press the taunt button, kick the rodent, get bitten and walk to the hospital, and claim a home. As **hospital staff** you cure a patient and fetch the right medicine against a timer. As **police** you see sightings on the map, drive the patrol car with siren, radar a speeder, write tickets and fight the rodent. As the **drone** you fly over the whole town and mark the rodent for officers. As a **squirrel** you climb every v5.4 tree, pole, wire and roof, forage with a nine-nut pocket, fill a hollow, keep visiting it so the claim holds, and fire the stink gland. As the **spicy rodent** you stalk, pounce and bite, watch your Power meter climb from FERAL toward RABID, heal by biting and lose health slowly between bites, and can be kicked or run over. As a **fox** you hunt squirrels; as a **deer** you wander and get startled. With 2 to 4 test windows you can play the roles against each other, and the Lab can fill the server to 49 with fake players so you can see the town stay staffed.

---

## 1. Architecture

### 1.1 Ground rules

1. **One actor model** [brief §4]. One actor kind per species (human, squirrel, fox, deer). The spicy rodent is a squirrel actor with `Variant = "spicy"`. Every actor has a persistent **brain** (AI) and is driven either by that brain or by a player's **controller**. Possession is the only mechanism for joining, leaving, queue promotion, NPC backfill, role switching and session reset.
2. **The ladder is stated once**, in `Shared/Roles/Ladder.luau` [brief §6], **including every number it uses** (slots, score weights, kick reward, offer timeout, the 30 % hospital rule, police slot thresholds, rodent re-entry delay) in its own `Ladder.params` block. Tunables and quest data never hold ladder numbers: quests name a reward class and the Ladder prices it. Services execute its results and never restate slots, scores or transitions. A Lune test scans `src/` and `data/` and fails on any ladder literal outside `Ladder.luau`. The live-tuning panel edits `Ladder.params` through the same attribute mirror as Tunables, so tuning does not create a second copy.
3. **Data is the source of truth** [brief §2]. Lots, lot types, archetypes, interiors, roads, lanes, traffic control, routes, cast, forage, items, quests and map layers are JSON files in HTML units, compiled once into studs. Adding a barber shop is a data entry.
4. **Pure core, thin engine shell.** Rules and motors are pure Luau, tested in Lune. Services are **steppable**: requiring a module never starts a thread; each service has `init(ctx)` and `step(dt, now)`. So the real engine can drive them headlessly through Open Cloud Luau Execution, where scripts do not auto-run [feas B.d].
5. **The server owns outcomes; clients own feel.** Anything that scores, hurts, infects, pays or promotes is decided on the server.
6. **Gameplay never depends on streamed parts.** Routes, colliders, nav graphs, lanes, forage anchors and marker data live in shared data. Server AI runs everywhere, all the time; there is no world pause [hospital_police_infection §12].
7. **The place is a build artifact.** git, then compile, then a Lune bake, then `rojo build`, then an Open Cloud save. Studio-made art reaches the game by asset ID through a manifest. Nothing is authored only in Studio.
8. **Every number is a tunable** with a unit, a range and a spec source (in `Tunables`, or in `Ladder.params` for ladder numbers, rule 2).
9. **The engine never kills a body.** `Humanoid.BreakJointsOnDeath = false`, the Dead state is disabled, and health lives in `CombatService`. Death is a role transition, never a respawn. The Roblox menu's **Reset Character** is routed to `Movement/Recovery` ("unstick me": move to the last safe position) through `StarterGui:SetCore("ResetButtonCallback", bindable)`, for Humanoid and non-Humanoid bodies alike.
10. **Population is data.** How many bodies of each kind exist, which posts they fill, the AI floor each job site keeps (the brief's 6 police and 10 hospital staff are floors that can never be cut) and the parked reserve live in `data/cast/population.json` (§3.12) and are checked by compiler invariant 11. Join and promotion never leave a job site below its floor (§1.5). The server holds 49 players, hard [brief v2 §5]; the plan never serves more.
11. **Two clocks, never merged** [brief v2 §8]. Power fades on real minutes of active play; rodent health drains on in-game days. `Rodent/PowerRules` and `CombatService` each read their own clock and a Lune test per clock pins it.
12. **Persistence only for what is sold or earned across servers** [brief v2 §13a; D26]. The DataStore profile holds the Spicy-Dollar wallet, purchases and the receipt ledger, the wardrobe (paintball garb, fashion-stand outfits) and reputation. Rank, homes, hollows, infection and everything else stay per server as the brief scopes them.
13. **Frameworks before content.** Every attraction is content on one of four frameworks: `Item` (a Tool with a server-validated effect), `Minigame` (join, controls, server-scored result, scoreboard), `Ride` (seat, path or zone, camera, exit) or a staffed `LotType`. A new minigame or ride is a definition file plus one rules module, never a new service (§3.16, D28).

### 1.2 Repository and Rojo tree

```
spicy-rodents-roblox/
  default.project.json     code + generated data + assets (live-sync capable; Rojo plugin optional)
  build.project.json       default + build/Town.rbxm -> Workspace.Town          (owner and live builds)
  ci.project.json          build + tests/engine -> ServerStorage.EngineTests    (CI place only)
  rokit.toml               rojo 7.7.1, lune 0.11.1, stylua 2.6.0 (luau feature), selene 0.31.0, luau-lsp
  selene.toml  roblox.yml (committed)  stylua.toml  .luaurc  .gitattributes (LFS rules)
  .github/workflows/ci.yml stylua --check, selene, luau-lsp analyze (strict), lune tests, compile check, rojo build
  README.md                brief §14: module layout; how to add a lot type, a route, a role
  CHANGELOG.md             one line per saved place version: version -> git sha -> build tag
  data/                    AUTHORED SOURCE (JSON, HTML units), each file validated by data/schema/*.schema.json
    harvest/               machine output of tools/harvest, pinned to the v5.4 SHA-256 (never hand-edited)
    town/                  districts.json (incl. the offroad district, jurisdiction: false), lots/<district>.json,
                           roads.json, traffic_control.json, hollows.json (12 + log), utility.json, trees.json,
                           terrain_extensions.json (hill, ridge, back field: authored height outside the v5.4 rectangle),
                           lighting.json (lamp placement rule, porch and shop-front lights, flicker seeds)
    lot_types/*.json       one file per lot type (house, shop_barber, restaurant_taco, school, marina, ...); the
                           attraction types (shop_corner, clinic, museum, bowling_alley, racquetball, steakhouse,
                           lounge_classic, lounge_scifi, mall_small, restaurant_hilltop, tv_station, shop_antique)
                           carry a `attraction` block (§3.17: minigames, rides, items, seats, camera lock, guards)
    archetypes/houses/*.json   interiors/*.json   buildings/{hospital,police_station}.json
    cast/{cast,population,events}.json  wildlife/  forage/forage_types.json  hospital/items.json
    quests/quest_types.json  (side quests, gigs, NPC posts, mischief responses, player traffic violations)
    upgrades/upgrades.json  outfits/*.json  map/markers.json
    economy/{prices,wages,products}.json   items/items.json (the 22 corner-store items)   reputation/rules.json
    minigames/<game>.json  rides/<ride>.json  paintball/{arena,garb}.json   vehicles/kinds.json (car, cart, bike,
                           pickup, suv, jetski, gondola)  vehicles/placements.json (6 pickups, 4 SUVs, carts, bikes)
    speech/{lines,taunts,fortunes}.json  content/{exhibits,books}.json   persistence/profile.schema.json
    blend/{palette,dev_avatar_samples,item_colours}.json  assets/manifest.json
    harvest_patches.json   corrections to harvested routes, each with a reason and a spec citation (§4.4)
  generated/               compiler output (committed; CI fails if stale) -> ReplicatedStorage.Shared.Data
  src/shared/   -> ReplicatedStorage.Shared               pure modules; most also run under Lune
  src/server/   -> ServerScriptService.Server
  src/worldgen/ -> ServerScriptService.Server.WorldGen     builders (ModuleScripts; never auto-run); run by
                                                           Lune, by the server as a fallback and by the plugin
  src/client/   -> StarterPlayer.StarterPlayerScripts.Client
  src/plugin/   -> build/SpicyTools.rbxm                   Studio plugin: Bake Town, Validate Rig (W7 only)
  assets/       -> ReplicatedStorage.Assets                content, not code: Lune-generated placeholder rigs,
                                                           vehicles, kit templates, KeyframeSequences (.rbxm)
  art_captures/                                            `rojo syncback` output from the Art Inbox (contains
                                                           SurfaceAppearance); in NO project file, git only
  tests/unit/  tests/golden/*.json  tests/engine/          Lune unit, golden vectors, Luau Execution suites
  tools/        harvest/ golden/ compile/ bake/ placeholders/ anims/ textures/ cloud/ validate/ ci.sh
  blender/      <asset>/build.py, <asset>.blend (LFS), export/*.fbx (LFS, brief §14 deliverable),
                clips/*.json, renders/*.png
  docs/         DECISIONS.md (incl. the v5.4 keep/defer/drop table, §4.15), spikes/S*.md,
                owner/*.md (click-by-click), playtest/*.md
  build/        gitignored: Town.rbxm, SpicyRodents.rbxl, reports/
```

**Code roots follow the brief exactly** [brief §2]: all code sits under `ReplicatedStorage.Shared`, `ServerScriptService.Server` (WorldGen included) and `StarterPlayerScripts.Client`. `ReplicatedStorage.Assets` holds content, not code. Studio can live-sync this tree with the Rojo plugin at any time (Claude's own debugging, or the owner if they ever want it); the owner's normal path is the saved place version (D15, deviation 1 in §2.1).

**Project-file properties** (asserted by the place tests, §6.4):

| Where | Setting | Why |
|---|---|---|
| Workspace | `StreamingEnabled = true`, `ModelStreamingBehavior = Improved`, `StreamOutBehavior = Opportunistic`, `StreamingMinRadius = 64`, `StreamingTargetRadius = 1024` | brief §2; [feas B.e] |
| Workspace | `PlayerCharacterDestroyBehavior = Disabled` | otherwise every handoff destroys a body [feas B.a pitfall 1] |
| Workspace | `SignalBehavior = Deferred`, `FallenPartsDestroyHeight` below the sewer floor (-3.4 u) and the river bed | forward-compatible with Server Authority; no lost bodies |
| Players | `CharacterAutoLoads = false` | no engine-spawned avatars; bodies are possessed |
| Lighting | `Technology = Future`, `GeographicLatitude = 39` | [worldgen_districts_art §14.2] |
| Workspace.Town | from `build/Town.rbxm` (the Lune bake) | the town comes from data, baked into the saved place |

### 1.3 Runtime topology

**Server boot** (`Server/Main.server.luau`, the only script that starts loops):

1. `Config`, `Net`, `Clock`; `Tunables` mirrors itself to attributes on `ReplicatedStorage.TunablesLive`.
2. `Data` loads `generated/`; validation failure halts boot with a readable message.
3. `WorldBoot`: check `Workspace.Town` `BakeHash` against `Data.bakeHash` (runtime bake only as a fallback); write Terrain if its `BakeHash` attribute is missing or stale (D6); load runtime art by manifest (D12).
4. Static registries: `Routes` (curves, samples, index, graph), `Colliders`, `Nav`, `Traffic` lane graph.
5. `ActorService.populate()` from `population.json` (§1.5 budget): 69 standing human bodies (84 from W3c, the attraction posts included) plus a parked reserve up to the hard cap S19 proves (target 90); 6 novelty riders and 2 motorcyclists as non-Humanoid AI-only rigs; 10-14 squirrels; 1 rodent body; 6 deer bodies (5 player slots); 1 fox; plus devices (1 drone, 2 drivable patrol cars, golf carts and bicycles, 6 pickups and 4 SUVs parked, jet skis at the marina, the sky-lift gondolas).
5b. `Persistence/Profiles` loads each joining player's profile (wallet, wardrobe, receipts, reputation) with session locking before `RoleService.onJoin` runs; a load failure gives a read-only session (no purchases) rather than a wrong balance (D26).
6. Domain services `init` in dependency order, then the Heartbeat scheduler starts.
7. Only now does `Players.PlayerAdded` reach `RoleService.onJoin`. Players wait on a flyover camera until `WorldReady`.

**Server frame pipeline** (mirrors the HTML's traffic-snapshot order [traffic §8.1]):

1. Drain validated client motor packets into server actor state (`MoveValidator`).
2. `BrainScheduler` runs this frame's brain slices; brains emit intents.
3. AI motors integrate intents; anchored AI bodies move with one `workspace:BulkMoveTo`.
4. `Traffic.step` at 30 Hz: snapshot poses, move vehicles, push to pose ring buffers, broadcast `VehiclePoses`.
5. `SweptCollision`: every squirrel actor against the fleet, previous and current poses.
6. Combat windows and contacts.
7. Minigame and ride steps (`MinigameService.step`, `RideService.step`) and, while a match runs, `Paintball/ArenaService.step` (projectiles at 60 Hz, bot brains inside the `BrainScheduler` budget).
8. 1-5 Hz services: infection, hospital, police, foraging and hollows (claim lapse, season stock), seasons, quests and gigs, sightings, homes, economy (wages per in-game hour), reputation (cafe ticks, companion liking, vote windows), traffic law for player vehicles, the outbreak director when armed.
9. `Telemetry`.

**Client frame:** input to the own-body motor (`PreSimulation`, fixed 1/60 substeps, dt cap 0.08 [routes_movement §20]); camera (`RenderStepped`; the `CameraRig` picks the mode from role, vehicle and zone: human third or first person by toggle, first person on entering any vehicle or the gondola, locked first person inside the paintball arena and both lounges, third person for every animal, the forward-locked squirrel chase, the outbreak pull-out [brief v2 §14, §8]); `AnimationDriver` for every streamed body within range (D3); ghost vehicles; HUD at 5 Hz or on change (wallet, reputation, rank or "unranked", the rodent's Power and health meters); sky from the replicated clock; street lights enabled within a radius of the camera at night with seeded flicker (D30); ambient life as closed-form functions of server time and seed [wildlife_foraging §15]; winter snow applied **locally** on each client (terrain material and overlay swaps near the camera), so no voxel deltas replicate (F-7); client-authority minigame physics for the no-stakes class (D28).

**Ambient life with gameplay effects** stays closed-form but is also **evaluated on the server**: the same seeded functions tell `ForageService` whether birds are at a feeder at time t (feeder bird risk, brief §7), and yard cats and dogs (`Wildlife/YardHazards`) are server-light hazards whose swat and bark are server events the clients animate. What the player sees and what the server resolves therefore always agree.

### 1.4 Module catalogue

Interfaces are the public functions; internals are free to change. "Pure" modules have no engine dependencies and are Lune-tested.

**Shared** (`src/shared` -> `ReplicatedStorage.Shared`)

| Module | Responsibility | Interface |
|---|---|---|
| `Config/Units` (pure) | HTML-unit/stud conversion at the single boundary; facing (authoring faces -Z; one `+pi` from HTML yaw) | `st(u)`, `u(st)`, `yawCFrame(htmlYaw, pos)` |
| `Config/Tunables` + `TunableMeta` (pure) | Every gameplay number with unit, range and source; stud conversion on read; live overrides | `get(path)`, `meta(path)`, `onChanged(path, fn)`, `applyOverrides(map)`, `diff()` |
| `Config/Flags` | Feature flags; dev gating (Studio or the owner's UserId) | `enabled(name)`, `isDev(player)` |
| `Data` (pure) | Read-only accessors over `generated/` | `lots()`, `lot(id)`, `lotType(t)`, `routes()`, `lanes()`, `nav()`, `colliders()`, `forage()`, `hollows()`, `quests()`, `markers()`, `assets()`, `bakeHash` |
| `Util/*` (pure) | `Rng` (mulberry32 port), `Signal`, `Trove`, `Spring`, `SpatialHash`, `Geometry` (AABB/OBB, `segmentBoxEntry`), `Schema`, `BufferCodec`, `Log` | per util |
| `Net/Net`, `Net/Schemas` | The single remote registry (§1.6) | `define`, `fire`, `fireAll`, `fireNear`, `on`, `stream` |
| `Time/Clock`, `DayCurve`, `Calendar`, `Moon` (pure) | Game time from `GetServerTimeNow()` plus an epoch attribute; non-linear day that holds sunrise and sunset; weeks, winter, raid week; lunar phase (reuses the feasibility `Moon.luau`) | `now()`, `game()` -> `{day, hour, week, isWinter, lunarAge, phase}`, `raidWeek(day)` |
| `World/Height` (pure) | Verbatim `baseTerrainHeight`/`terrainHeight` [worldgen_core §3, §16] | `base(x, z)`, `at(x, z)` |
| `World/Ground` (pure) | Ground, roofs and porches as a pure function of position and a reference height (fixes the global-state `getGroundAt` [routes_movement verifier 5]) | `groundAt(x, z, refY)`, `roofAt(x, z, refY)`, `surfaceKind(x, z)` |
| `World/Colliders`, `World/Town` (pure) | Data colliders in a spatial hash; lot and district queries | `blocked(p0, p1, r, refY)`, `query(box)`, `lotAt`, `districtTag`, `pavementDistance` |
| `Routes/Curve`, `Registry`, `SpatialIndex`, `Graph`, `Motion` (pure) | Centripetal Catmull-Rom (alpha 0.5, three.js r160 phantom ends, 200 arc divisions, `max(20, ceil(3L))` samples); registry of harvested plus template routes; 20-st index; precomputed end-links, transfers, forks, islands; `advance`, junction and fork choice, visual pose [routes_movement §1-§14] | `get(id)`, `nearest(pos, maxDist, excl)`, `endLinks`, `transfers`, `forks`, `advance(state, input, dt)`, `visualPose(state)` |
| `Movement/SquirrelMotor`, `QuadrupedMotor`, `HumanAIMotor`, `CarMotor`, `DroneMotor` (pure) | One motor per body type, used by AI on the server and by players on the client: `step(state, input, dt, world) -> state, events`; `serialize`/`deserialize` for mid-stride handoff | `new(params)`, `step`, `serialize`, `deserialize`, `envelope(prev, next, dt)` (validator) |
| `Actors/Species`, `Actors/RigSpec` (pure) | Species definitions (body kind, motor, brains, hitbox, sockets, stock looks); rig contracts (bone, socket and region names, clip names, budgets) | `def(species)`, `RigSpec[species]`, `validate(model)` |
| `Roles/Ladder` (pure) | **The** ladder (§3.7) | `rungs`, `subroles`, `sideExits`, `score(rung, stats)`, `rankOrder`, `slots(rung, state)`, `resolve(event, ctx) -> {Transition}` |
| `Combat/CombatRules` (pure) | Pounce wind-up/commit/recovery, contact, bite chance by awareness, strikes, damage, regen, zig-zag, feint, stamina [squirrel_abilities §6, §25] | `pounceVelocity`, `contact`, `biteChance`, `strikeHits`, `damage`, `regen`, `zigzag(history)`, `feint(ctx)` |
| `Infection/InfectionRules` (pure) | Per-actor infection, town %, squirrel-share maturation (25/7 % per squirrel, cap 25, 1500 s), critical mass, cure-time multiplier [hospital_police_infection §6, §11] | `townPercent`, `squirrelShare`, `criticalMass`, `cureTime` |
| `Traffic/Swept`, `Traffic/LaneMath` (pure) | Exact `sweptVehicleHit`/`segmentBoxEntry` [traffic §8.4]; lane pose, leader/follower, yield corridor, stop-line FSM, the ice-cream spline table | `hit(...)`, `broadPhase(...)`, `pointAt`, `leader`, `seesHazard`, `stopLine` |
| `Foraging/ForageRules` (pure) | Yields, **finite season stock per source** (replenished at season start; brief v2 §3), carry cap **9**, hollow meter, ownership = meter at 70 % **and** a visit within the last `ownVisitDays` (3 in-game days) while at 70 %, else the claim lapses; claiming is proximity (deposit while inside, no ritual, no clip); premium weekly raid, winter multiplier, stink fill and fire | `yield`, `stock`, `meter`, `owner(hollow, now)`, `lapsed`, `stink`, `canFire`, `survives` |
| `Rodent/PowerRules` (pure) | **Power exactly as v5.4** [brief v2 §15 table; squirrel_abilities §12]: +100 bite a person (+150 when high up), +130 an officer, +90 per converted squirrel once each, -19 baton (and the pedestrian kick, v5.4; Q23), -12 yard cat, -15 % rounded up after 10 real minutes of **active play** without a bite, repeating; a bite resets the fade; never below 0; chilis, coins, climbing and missed pounces change nothing; stages FERAL < 600, RABID 600-1,499, SUPER >= 1,500. Golden vectors from `updatePowerAndHeat`. Its clock is real active seconds (rule 11) | `apply(state, event)`, `fade(state, activeDt)`, `stage(power)` |
| `Economy/EconomyRules` (pure) | Spicy Dollars in **cents** (integers); minimum wage 2 cents per in-game hour; prices from `prices.json`; gig pay and tips by quality; developer-product tiers (whole Robux, about 1 R$ = 4 S$); receipt idempotency key; the money term of the human queue score is priced here and read by `Ladder` [brief v2 §13a] | `wage(job, hours)`, `price(itemId)`, `gigPay(gig, quality)`, `grant(productId)`, `receiptKey(receipt)` |
| `Reputation/ReputationRules` (pure) | Two-sided reputation: NPC liking (fun seen nearby: gigs well done, taunts, mischief watched) and player votes, 5 up and 5 down per in-game day, each vote weighted by the voter's own reputation and clamped (brigading tests); cafe sitting tick; rescue, true sighting report, lost pet returned; the gig "very minor ding"; entourage size [brief v2 §13a] | `applyVote(target, voter, dir)`, `tick(event)`, `weight(voterRep)`, `entourage(player)` |
| `Gigs/GigRules` (pure) | The six gigs as quest types with a 0-1 quality score (mow, delivery by bike or cart, sign-spin, car wash, paper route with the porch bonus, steakhouse tables); `>= 0.9` tips, `< 0.4` dings reputation; NPC posts (`npc.post`) priced in coins [brief v2 §13a] | `quality(gig, trace)`, `payout(gig, quality)` |
| `Minigames/MinigameRules/*` (pure) | One rules module per game on the shared `Minigame` contract (join, seats, controls, server-scored result, scoreboard): bowling (angle, power, pin scoring, frames), darts (501 and cricket; aim point, timing meter, wobble), pool and bumper pool (8-ball rules, fouls), pinball (3 themed tables: scoring only; physics is client-side), racquetball, volleyball, giant Jenga (54 blocks, turn order, collapse), tilt labyrinth (**fixed controls**: W/S tilt forward and back, up and down arrows tilt right and left, up arrow is right), kite (wind and line tension), fortune machine (no money in or out). Determinism and physics authority per stakes class (D28) | `def(game)`, `validate(input, state)`, `score(state)`, `result(state)` |
| `Rides/RideSpec` (pure) | Rides have no controls and no score [brief v2 §15]: sky-lift gondola (cable path, cabins), parasailing (towed spline over the beach), wind tunnel (float volume, instructors' balls, paid +10 balls), and the steerable exception, the jet ski (`JetSkiMotor` over a water surface) | `def(ride)`, `pathAt(ride, t)`, `exitPoint` |
| `Paintball/PaintballRules` (pure) | Projectile travel with slight drop, 5-shot magazine with auto and manual reload, hit from a rewound pose, team deathmatch 4v4-8v8 with bot fill, match timer, score; access pass of 5 in-game days for 20 cents which also opens the lounges; garb sets at 1 S$ each, cosmetic only [brief v2 §13a] | `step(proj, dt)`, `hit(proj, poses)`, `magazine`, `score`, `pass(now)` |
| `Vehicles/VehicleKinds` (pure) | `CarMotor` parameter sets for car, cart (slow, open), pickup and SUV; `BikeMotor` (arcade, balance-free); `JetSkiMotor` (water surface, wake); gondola cabins are rides, not vehicles. Who may take what: carts and bikes anyone, pickups and SUVs the top two ranked humans (`Ladder.subroles.humanDriver`), patrol cars the top two officers, jet skis anyone for a rental fee [brief v2 §13a, §15] | `kind(id)`, `mayDrive(player, kind)`, motor params |
| `Camera/CameraPolicy` (pure) | Which camera mode a body, vehicle or zone demands [brief v2 §14]: animals third person; humans free toggle; vehicles and the gondola first person on entry with the toggle kept; paintball and both lounges locked first person; squirrel chase forward-locked; outbreak pull-out | `modeFor(role, vehicle, zone, chase)` |
| `Lighting/LampPlan` (pure) | Compiler-side placement of street lamps per block, porch lights on every house and emissive shop fronts from `lighting.json`; the seeded flicker set; the client-radius enable rule and the Skyline emissive heads for the drone (D30) | `place(town)`, `flickers(seed)`, `withinRadius(cam)` |
| `Items/ItemRules` (pure) | The 22 corner-store items and their effects (water gun squirt and the once-per-player rodent stun of 1.3 s; frisbee and football throws; bubbles; chalk with a 20-letter budget and text filtering; flashlight at night; umbrella; peanuts and bird seed bait; dog treats; newspaper; camera; duct tape; whoopee cushion on a seat; harmonica, bike horn and air horn startles; soda and ice cream; lawn chair as a seat; radio playlist; kite). No lottery or gambling items [brief v2 §13a] | `def(itemId)`, `use(item, ctx) -> effects` |
| `Avatar/BlendRules` (pure) | 70/30 composition; palette clamp (saturation <= 0.55, value 0.39-0.91, one neon accent); bizarre-avatar signature pick; colour sources in priority order: body colours, accessory colours, item-name colour words (`GetProductInfo`), the curated `item_colours.json` table [A3; worldgen_districts_art §15] | `traits(desc, productInfo)`, `compose(species, stock, traits) -> Look`, `isBizarre` |
| `Actors/Population` (pure) | Posts, standing counts, AI floors (normal and hard-cap), reserve and hard cap from `population.json`; picks the body for a join, promotion, paintball bot or attraction post (§1.5) | `pickBody(post, state)` returns a body, a re-post order, a reserve deployment or a wait, `floorsOk(state)` |
| `Combat/VigilanteRules` (pure) | Keeps exactly `round(0.08 x human actors)` vigilante flags at any moment; flags live on AI bodies and move to another AI body within 1 s when a flagged body is possessed [brief §8] | `rebalance(humans, flags) -> flags` |
| `Economy/UpgradeRules` (pure) | The station-upgrade catalogue rules: availability by performance tier, cost in Spicy Dollars from the pooled building fund, effects as tunable multipliers [brief §9, §10, §13] | `available(building, perf)`, `price(id)`, `effect(id)` |
| `Movement/Recovery` (pure) | River-fall recovery to the nearer quay [worldgen_districts_art §16], last-safe-position history, "unstick" for the Reset button, push-off when a parked car carrying a squirrel moves | `safePos(actor)`, `riverRecover(pos)`, `onVehicleMoved(car, riders)` |
| `Map/MapModel`, `Quests/QuestTypes` (pure) | World-to-map projection and marker kinds; quest step validators | `project(x, z)`, `labels()`, `def(type)`, `nextStep(q, evt)` |

**Server** (`src/server` -> `ServerScriptService.Server`)

| Module | Responsibility | Interface |
|---|---|---|
| `Main`, `Boot/WorldBoot` | Boot order and frame pipeline; bake-hash and terrain checks; runtime art load | `ensure()` |
| `Actors/ActorService` | Actor registry and lifecycle; bodies created once, never destroyed | `spawn(species, spec, cf)`, `get(id)`, `query(filter)`, `nearest`, `kill(actor, cause)`, `setBodyMode(actor, "ai"\|"player")`; signals `Possessed`, `Released`, `Died` |
| `Actors/BodyFactory` | Bodies from species, stock look and the best manifest template; `Atomic` streaming, `PrimaryPart`, sockets | `build(species, look)`, `applyLook(body, look)` |
| `Actors/Possession` | **The single handoff mechanism** (§1.5) | `possess(player, actor)`, `release(player, why)`, `swap(player, toActor)`, `controllerOf(actor)` |
| `Actors/BrainScheduler` | Time-sliced brain ticks with distance LOD (D4) and a per-frame budget | `register`, `unregister`, `setFocus(fn)`, `metrics()` |
| `Actors/Brains/*` | `Pedestrian`, `Resident`, `ShopWorker`, `HospitalStaff`, `AmbulanceCrew`, `Patient`, `Officer` (tiers 1-3, §4.9), `PrecinctGuard`, `Driver`, `Burglar`, `Arguer`, `EventGoer`, `Defender`, `Vigilante`, `Bystander` and `Companion` (overlays; a companion likes a player and pals around or follows), `AngryNpc` (mischief reaction: shout, a few steps' chase, report), `Receptionist`, `Bartender`, `LoungeGuard` (kills squirrels that enter), `Instructor` (wind tunnel), `RacquetballOpponent`, `PaintballBot` (FPS brain across five floors), `Pet` (dog or cat: leash-follow, lost-pet wander), `NoveltyRider` (mime, kid cyclists), `Motorcyclist`, `Skater`, `Squirrel` (with `OutbreakSweep` and full-sprint flee on rails when chased), `Rodent`, `Fox`, `Deer` (with `RabidDeer`: charge along sidewalks and lawns, scatter humans; Q5). Each: `new(actor, params)`, `think(dt, ctx) -> Intent`, `suspend() -> snapshot`, `resume(snapshot)`, `onEvent(evt)` | per brain |
| `Actors/Perception`, `Actors/Nav` | Spatial-grid threat queries; ported `spotted` using height above local ground, **including the v5.4 concealment terms** (Tabasco garden, hedges, shrub clusters as data volumes) [wildlife_foraging verifier 1]; sidewalk lane graph, interior room graphs, cached escapes | `spotted(observer, target)`, `nearby(pos, r, filter)`, `path(from, to, opts)`, `roomGraph(lotId)` |
| `Movement/MoveValidator` | Validates client motor packets: per-kind speed caps, legal transfers (gap <= 3.15 u, grab <= 3.4 u), gravity-consistent arcs, wall crossings; leaky buckets; pose history. Log-only until W7 | `accept(actor, packet) -> ok, correction`, `pose(id, t)` |
| `Roles/RoleService`, `Roles/RoleLab` | Executes Ladder transitions: join, leave, queue, offers, side exits, top-two car keys, session reset; dev-only Lab backend | `onJoin`, `onLeave`, `report(event)`, `roleOf`, `stats`, `queue(rung)`, `offer`, `forceRole` (Lab), `resetSession()` |
| `Combat/CombatService` | Server pounce, kick, swing, baton, shove and defender blows; RTT-widened windows; rewind of up to 150 ms; rodent health with the game-clock **drain** (1 hp per in-game day without a bite), **heal on bite** (10 human, 20 squirrel) and slow regen while stalking or in a hollow (re-tuned so the drain and heals matter, D33); **alert zones** after every bite (radius, TTL): hidden kick multiplier, swing-heavy responses, near-impossible second bite, NPC police chase within about two blocks for up to five; infected squirrels have health and are valid strike targets, healthy squirrels are immune (Q6); `rescue` events for reputation; the water-gun stun; death | `requestPounce`, `requestStrike`, `damage`, `healthOf`, `alertZone(pos)`, `inAlert(pos)`; signals `Hit`, `Kick`, `Killed`, `Rescue` |
| `Infection/InfectionService` | Per-actor infection, red-eye tell, walk-in routing, squirrel share, hidden critical mass, outbreak hand-off to the director; **reset on rodent death** (`resetToRodent`: town percent to the new rodent alone, humans cured, instantly if bitten within `recentBiteSecs` or walking to the hospital, admitted patients finish their loop; infected squirrels go to lowest human through the Ladder); deer become biteable only when every regular squirrel body is infected; infected squirrels never recover | `infect`, `cure`, `isInfected`, `townPercent`, `onCriticalMass`, `resetToRodent()`, `deerBiteable()` |
| `Outbreak/OutbreakDirector` | **The outbreak cinematic** [brief v2 §8; D31]: on critical mass, phases on the clock (`Clock.setRate`), every squirrel body infected and in `OutbreakSweep` (door to door, speed rising), lighting state `Outbreak` (overcast ramp by day; fade to black at night), each client's camera pulled up and out from one server timestamp; about 20-30 real seconds, then the Ladder reset (winner keeps the rodent, surviving infected squirrels keep squirrel bodies); the end card survives only as the fallback for a client that cannot play it. Needs the lamplit town (D30) | `arm`, `start(now)`, `phase()`, signal `Finished` |
| `Hospital/HospitalService` | Admissions (walk-in, ambulance), stations, the disinfect loop, fetch tasks, performance metric, upgrades | `admit`, `startDisinfect`, `fetch.offer/pick/deliver`, `performance`, `upgrade` |
| `Police/PoliceService`, `Police/PoliceCoord` | Officers, AI dispatch backfill, precinct guard, tickets, the police performance metric (§4.9), slot expansion 5 to 8 as the Ladder decides, aggression and coordination tiers (pursuer, cut-off, perimeter), "call backup", drone unlock | `officers`, `keyHolders`, `ticket`, `performance`, `slotsUnlocked` (reads `Ladder`), `assignRoles(sighting)`, `droneUnlocked` |
| `Drone/DroneService` | Launch and dock at the station console (the pilot's body stays seated), flight validation, `Player.ReplicationFocus` set to the drone while flying and the drone model `PersistentPerPlayer` for its pilot (F-13), server-resolved spot-and-mark, vigilante summon, deer startle | `launch`, `dock`, `mark(pilot, aim)`, `activeMarks` |
| `Vehicles/TrafficService`, `PlayerVehicles`, `SweptCollision`, `TrafficLaw` | AI fleet on lanes with yielding, traffic control, limits and violations, fender benders, pose ring buffers; **every player-enterable vehicle** (2 patrol cars, golf carts and bicycles for anyone, police carts, 6 pickups and 4 SUVs for the top two ranked humans, jet skis; `VehicleKinds`), enter and exit with the §14 camera switch, keys that change hands only while parked; the fatal test for every squirrel actor with teleport flags, carts in the fleet at low speed, bikes not (Q8); **traffic law for everyone** [brief v2 §15 dec 14]: speeding, stop lines and parking evaluated for player vehicles, AI and player officers ticket players (fine in cents), repeat offenders and pedestrian hits go to a cell, an officer who hits a pedestrian loses the keys and is demoted on release, the pedestrian is knocked down and admitted as an uninfected trauma patient; no jurisdiction in the `offroad` district | `fleet`, `speedOf`, `limitAt`, `violations(vehicle)`; `grantKeys`, `enter`, `exit`, `setSiren`, `kindOf`; `step`, `markTeleported`, signal `RunOver(actor, vehicle, driver?)`, `Knockdown(human, vehicle, driver)`; `ticket`, `jail(player, secs)` |
| `Sightings/SightingService`, `Quests/QuestService` | Markers with TTL and per-role audience from `data/map/markers.json`; radar feed; side quests from simulation sources | `report(kind, pos, conf, src)`, `markersFor(player)`; `offer`, `accept`, `progress(evt)`, `active` |
| `Economy/Wallet`, `Economy/Store`, `Economy/UpgradeService`, `Jobs/JobService`, `Homes/HomeService` | **Spicy-Dollar wallet in cents** (one currency; the brief's "credits" and the old "coins" are Spicy Dollars, Q3), wages per in-game hour, purchases at counters and stands; **`MarketplaceService.ProcessReceipt`** for the developer products with an idempotent receipt ledger in the profile (never double-credited; D26); the station-upgrade catalogue and purchase flow at the upgrade boards (pooled building fund); work sockets on lots and the shared shop-worker rota, with AI staff slower than player staff (`aiStaffSpeedMult`); 40 claimable homes, doors, hide spots, defenders, the indoor escape rule, remodel points | `Wallet.balance/add/spend`; `Store.products`, `Store.processReceipt`, `Store.buy(counter, itemId)`; `Upgrades.offer/contribute/buy/owned`; `jobsAt`, `work`; `claim`, `remodel`, `door`, `hide` |
| `Reputation/ReputationService`, `Social/VoteService`, `Social/TauntService`, `Mischief/MischiefService` | Per-player reputation (server life plus the profile), companion overlays and entourage; votes (5 + 5 per in-game day, weighted, rate-limited, players only by default, Q21); the taunt button (20 curated mild lines from `speech/taunts.json`); the five mischief verbs (TP-ing trees, knock-and-run, egging at night, water balloons, joyriding a police cart) with NPC anger, a `mischief.report` quest source for police and the consequences of Q7 (fine, ding, a cell for repeat offenders) | `rep(player)`, `apply(event)`, `entourage`; `vote(voter, target, dir)`; `taunt(player, i)`; `act(verb, target)`, signal `Mischief` |
| `Gigs/GigService`, `Pets/PetService` | Gigs offered at their lots (mower prop at lawns, restaurants for delivery, storefront sockets for sign-spinning, driveways and the gas station for washing, the morning paper route with porch-hit detection, steakhouse tables), each with a quality trace; NPC-posted mini-missions on the park billboard and the station poster (walk a dog, return a lost pet) paying coins; a few dogs and cats as `Pet` bodies | `offer`, `start`, `report(quality)`; `leash`, `lost`, `returned` |
| `Items/ItemService` | The `Item` framework: Tools in the possessed Humanoid's Backpack, every effect validated on the server, inventory kept per player across possessions and saved in the profile; throwables client-owned while held, throws validated; chalk text through `TextService:FilterStringAsync`; the camera through `CaptureService` on the client (S20) | `give`, `use(player, itemId, args)`, `inventory(player)` |
| `Minigames/MinigameService`, `Rides/RideService` | The `Minigame` framework (join a table or lane, seats, turn order, input validation, server-authoritative or per-turn client-owned physics by stakes class with ownership handed per turn, result and scoreboard, Lab scenarios) and the `Ride` framework (seat, path or zone, camera hand-off, exit; wind-tunnel balls server-owned; the jet ski through `PlayerVehicles`). Content comes from `minigames/*.json` and `rides/*.json` | `join`, `leave`, `input`, `state`, signal `Result`; `board`, `alight` |
| `Paintball/ArenaService` | The in-server instanced paintball match inside the TV station (D29): lobby and teams, 4v4-8v8 with `PaintballBot` bodies re-posted from townspeople above their floors (the D25 pattern), server-simulated projectiles at 60 Hz with client prediction, **1 s pose history per player rewound to the shooter's timestamp**, pooled splat decals cleared at match end, timer, scoreboard, end card, access passes, the garb shop and wardrobe; squirrels cannot enter; exit returns to town with the pass still running (Q9) | `openMatch`, `joinMatch`, `fire(player, shot)`, `reload`, `score`, `buyPass`, `buyGarb`, `equip` |
| `Attractions/*` | Thin services for staffed places that are not minigames or rides: the corner store checkout (`Store.buy` at the counter prompt), the clinic waiting room (books, bead maze, labyrinth as a no-stakes minigame), the museum exhibits from `content/exhibits.json`, the lounges (`LoungeGuard`, bartender with four consumables, access by paintball pass, locked first person), the steakhouse (glass the `SquirrelBlocked` collision group, Humanoid-only doors, bar, volleyball sand, Jenga deck), the bowling alley back of house, the sky-lift stations and hilltop restaurant | per place |
| `Lighting/StreetLighting` | Server-side owner of the lamp list the compiler placed (`LampPlan`) and the seeded flicker set; the client does the rendering (D30) | `lamps()`, `flickerSeed` |
| `Community/EventService`, `Mall/GalleriaService` | Living-community events (barbecue, softball) on their cycle; crime scenes (seated victim, witness alarm, bystanders); argument and break-in sources; outbreak ambience (gas station closes); Galleria coins, wishing-fountain toss and the mall state machine | `schedule`, `crimeScene(bite)`, `onOutbreak`; `coins`, `wish`, `mallState` |
| `Wildlife/YardHazards`, `Rodent/ChiliHunt`, `Cosmetics/FashionStand` | Yard cats' telegraphed swat and dogs' bark that alerts humans; the 8 hidden chili peppers and the chili rush; the sewer fashion stand and wardrobe (server-life) | `swat`, `bark`; `found`, `rushActive`; `buy`, `equip` |
| `Foraging/ForageService`, `HollowService`, `StinkService` | Sources from data with finite season stock, carried nuts (max 9), risk triggers; **12 claimable hollows** (two premium, one escape tree with three knotholes and exits) plus the fallen log, meters, ownership with the 3-day visit rule and claim lapse, theft, rodent rest and cover (hollow interiors and the sewer are `unseen` volumes); stink fill, fire and repel | `forage`, `carried`; `meter`, `owner`, `lastVisit`, `deposit`, `enter`; `fire`, `repelling(pos)` |
| `Wildlife/WildlifeService`, `Seasons/SeasonService` | Species upkeep, threats, startle events, ambient critters; calendar events, winter effects, winter-end survival check | `startle`, `upkeep`; `isWinter`, `onWinterStart/End`, `survivalCheck` |
| `Avatar/AvatarBlendService`, `Assets/AssetService` | Trait fetch and cache (`GetHumanoidDescriptionFromUserId`; `CreateHumanoidModelFromDescription` as the source of the face decal and of **rigid** accessories, since other creators' items cannot come from `LoadAsset`; `MarketplaceService:GetProductInfo` for item-name colour words, cached and rate-limited); apply on possession, revert on release; manifest resolution and runtime `InsertService:LoadAsset` with placeholder fallback, including moderation status (`pending`/`rejected` fall back to the placeholder) | `apply`, `revert`, `preview(actor, sample)`; `template(name)`, `status(name)` |
| `Telemetry`, `Persistence/Profiles` (**W4**, mandatory from the first developer product; D26) | Per-system ms, actor counts by LOD tier, remote bytes, arena ms; the DataStore profile (wallet in cents, receipt ledger, wardrobe, inventory of bought items, reputation, lifetime stats, the once-per-player water-gun flag if Q11 says lifetime) with ProfileStore-style session locking, a Lune-tested serialiser with a version field, and `BindToClose` flush; read-only session on load failure | `scope(name)`, `report()`; `load(player)`, `save(player)`, `locked(player)`, `release(player)` |

**Client** (`src/client` -> `StarterPlayer.StarterPlayerScripts.Client`)

| Module | Responsibility |
|---|---|
| `Main`, `Possession/PossessionClient` | Waits for `Granted`/`Revoked`; picks controller and camera; seeds the mid-stride carry-over |
| `Controllers/Human`, `Squirrel`, `Quadruped`, `Vehicle` (car, cart, bike, pickup, SUV, jet ski), `Drone`, `Paintball` (sprint, crouch, aim, fire, reload) | Each: `start(body, snapshot)`, `stop()`, `packet()`. Humans use the default Humanoid controls plus our verbs; others disable the default controls and drive their pure motor through `AlignPosition`/`AlignOrientation` |
| `Input/InputMap` | Bindings per role (keyboard, gamepad, touch) through ContextActionService; Tab and Esc stay reserved [squirrel_abilities §26]; the tilt labyrinth's fixed bindings (W/S forward and back; up and down arrows right and left, up is right) recorded here and never remapped [brief v2 §13a]; the taunt, vote and first-person-toggle keys |
| `Camera/CameraRig` | Per-mode rigs from `CameraPolicy` [brief v2 §14]: human third person with a free first-person toggle; squirrel per route kind [routes_movement §15]; the rodent's stalk as an over-shoulder third-person stalk by default (v5.4's first-person stalk only if the owner keeps it, Q10); the forward-locked squirrel chase; `Vehicle` first person on entry with a modelled interior and dash, toggle kept; `Gondola` first person; `LockFirstPerson` zones (paintball arena, both lounges); drone feed; the `Outbreak` pull-out on the Skyline layer; spherecast occlusion with a CameraBlocker group |
| `Minigames/*`, `Rides/RideClient`, `Paintball/ArenaClient` | Per-game input and presentation (aim and power UI, scoreboards, the client-side physics of the no-stakes games and the current shooter's owned parts in shared games); ride camera paths; the arena HUD, predicted projectiles, splat rendering, fire and hit audio |
| `World/StreetLights` | Enables real `PointLight`/`SpotLight` pools within a radius of the camera at night (`Shadows = false`), seeded flicker on a few lamps, porch lights, emissive shop fronts; emissive Skyline lamp heads so the lamplit grid reads from 300 st (D30, S17) |
| `Animation/AnimationDriver` | Body state to animation for **every** streamed body within range (D3); clip backend and procedural backend (HTML gait formulas); tail spring and foot IK within about 60 st |
| `Render/VehicleView`, `Render/Interp` | Ghost AI vehicles from the pose stream (about 100 ms behind); interpolation for far AI bodies if the state-stream fallback is used |
| `UI/*` | Role HUDs (wallet, reputation, rank or "unranked" until 10 in-game days, the rodent's Power meter with FERAL / RABID / SUPER beside its health bar), minimap and full map with marker layers, radar, notifications (priority queue; danger telegraphs are never overwritten), prompt styling, promotion offers (including police recruitment by seniority), quest and gig tracker, the billboard and poster UI, hospital task UI, drone feed, the taunt button, thumbs up and down on the player list and target prompt, store and counter UI, the Robux product prompts, wardrobe and garb, minigame scoreboards, the paintball match UI, Role Lab, bug report |
| `World/*`, `Audio` | Sky and lighting from the clock, moon texture by phase, stars, tower blink, clock-tower hands; fog cards tinted per lighting state; client-local winter snow; ambient life; skyline fade; door visuals; interior roof hiding; mall doors and lights from `mallState`; ambience from the licensed audio library (D24) |

**WorldGen** (`src/worldgen` -> `ServerScriptService.Server.WorldGen`; runs in Lune, on the server as fallback and in the plugin)

| Module | Responsibility |
|---|---|
| `Bake` | Entry point: walks districts and lots in a fixed order, calls builders, stamps `BakeHash` |
| `Factory` | Instance-creation shim (wraps `@lune/roblox` under Lune, globals in the engine); CFrames by pure maths |
| `Plan` (pure) | Lots to a deterministic `BuildPlan` (parts, doors, prompts, sockets, colliders, nav, route specs, terrain spans, road strips) |
| `Builders/*` | One family per lot category: House, Storefront, Restaurant, Civic, Hospital, PoliceStation, Estate, Quay, Galleria (also the new small mall and its wind-tunnel cylinder), Park, Marina (jet-ski and parasail stands), Pier, Beach, Sewer; **attraction families** BowlingAlley (lanes, pin decks, ball-return `tunnel` routes under each lane to the rack, arcade corner, back of house), TvStation (five floors, stairwells, central atrium, arena volumes), Lounge (two kits), Steakhouse (glass walls in `SquirrelBlocked`, bar, sand court, deck), Clinic, Museum, CornerStore (checkout counter, 22 shelf sockets), Racquetball, SkyLift (base and hilltop stations, cable, cabins) and HilltopRestaurant; plus Interior, Yard (trampolines, two climbable tree houses with a Humanoid ladder and the squirrel routes to their floors), Hollow (spiral, shaft, knothole, **escape** with three knotholes, log), Tree (drawn around route curves), Pole, Wire (Beams), Fence, Road, Lamps (from `LampPlan`: posts, porch lights, shop-front emissives, Skyline heads), Signage (SurfaceGui text), Backdrop (bands and ocean tiled at <= 2048 st per part, F-8), FogCards, Skyline, OffRoad (ridge trees, back-field terrain, no roads or lots). Every building Model gets `LevelOfDetail` from data at bake time (SLIM-ready from W1) |
| `Kits` | Resolves a logical kit name through the manifest to a MeshPart template, or falls back to the blockout recipe |
| `TerrainBake` (engine only) | `WriteVoxels` in chunks from `World/Height` (verbatim v5.4 inside the v5.4 rectangle) **plus the authored extensions** in `terrain_extensions.json` (the hill with the sky lift, the ridge, the back field, the longer beach; D32); road and garden materials; river and near-ocean water; whether terrain or Blender ground tiles is the primary ground is decided at G0 from S6 and S11 (D6) |

**Tools** (`tools/`, run in the container): `harvest` (headless Chrome on the pinned v5.4 HTML), `golden` (Node and three.js r160 vectors), `compile` (validate, expand, link, emit `generated/` and reports), `bake` (Lune: `generated/` to `build/Town.rbxm`), `placeholders` (Lune puppet rigs and vehicles), `anims` (Blender clip JSON to KeyframeSequence `.rbxm`), `textures` (moon phases, clothing templates, map render, sign atlases), `cloud` (save place version, run engine tests, upload asset, poll operations, harvest IDs, publish), `validate`, `ci.sh`.

### 1.5 The actor model and possession

```
Actor = { id, species, variant, body: Model, brain (persistent), controller: "ai" | Player,
          motorState, health?, infected, traits, homeLot?, castId?, look: { stock, blend? } }
```

**Body modes.** AI-driven bodies are anchored and moved kinematically by the server with `BulkMoveTo`; Humanoids run with `EvaluateStateMachine = false` and unused states disabled. Player-driven bodies are unanchored, client-owned and moved by the client's motor. This mirrors v5.4, where every NPC is kinematic [humans_actors §15], and keeps physics cost to the players' own bodies [feas B.b, B.e].

**Possession** (`Possession.possess(player, actor)`):

1. `player:RequestStreamAroundAsync(body pivot)` with a timeout [feas B.a pitfall 5]. Bodies are `ModelStreamingMode = Atomic` with a `PrimaryPart`.
2. `snapshot = brain:suspend()`: mode, position, velocity, yaw, `routeId`/`s`/`dir` on a rail, goal, current clip and clip time.
3. `setBodyMode(actor, "player")`: unanchor; for Humanoids enable the state machine; set `AssemblyLinearVelocity` from the snapshot so momentum carries.
4. `root:SetNetworkOwner(player)`, then `player.Character = body`.
5. `Possession.Granted` carries the snapshot. The client controller resumes the motor exactly there; humans hold the AI's last move direction for up to 0.75 s or until the first input. The animation does not change hands (D3), so the stride continues.
6. `SweptCollision.markTeleported(actor)` and `MoveValidator.reset(actor)` [traffic verifier 1].
7. `AvatarBlendService.apply(actor, player)` runs asynchronously; the stock look shows first.

**Release** is the reverse: the last validated state goes to `brain:resume`, the body is anchored again, `SetNetworkOwner(nil)`, `player.Character = nil`, the blend is reverted. On `PlayerRemoving`, release happens before anything else.

**Swap** (promotion, side exit, death) is release plus possess in one server step. If the two bodies are far apart, the client plays a short camera fly-to, with streaming requested first.

**Devices.** The drone, the two patrol cars, the golf carts and bicycles, the police carts, the 6 pickups and 4 SUVs, the jet skis and the sky-lift gondolas are devices, not actors. A human driving stays possessed; the body is welded to the driver seat, the client switches to the `Vehicle` controller and to first person (the toggle stays, §14), and the vehicle's root is owned by that player. Patrol-car keys follow the Ladder's "top two officers by rank" and pickup and SUV keys the "top two humans by rank" (`humanDriver`, undocumented in-game: the prompt appears only to key holders), but **keys only change hands while the vehicle is parked**: a driver who drops out of the top two keeps driving until they exit, then the key passes. Carts and bikes need no key; carts are in the fatal fleet at low speed and obey stop lines, bikes are neither (Q8 default). A drone pilot's body stays seated at the station console while the client drives the drone; while flying, `Player.ReplicationFocus` is the drone, and the drone model is `PersistentPerPlayer` for its pilot, so streaming follows the camera, not the seated body (F-13). `Ladder` decides who may operate which device.

**Join.** `RoleService.onJoin` asks the Ladder for the rung (lowest human), asks `Population.pickBody("townsperson")` for an AI human above its post's floor that is walking on a sidewalk (not indoors, not mid-quest), and possesses it.

**The 49-slot server** [brief v2 §5, dec 28]. `Players.MaxPlayers = 49`, set by the owner on the Creator Hub (OS-0), and Roblox itself makes late joiners wait for the next server: **there are no overflow roles and no spectators**. The 49 are 35 humans (hospital and police slots are inside the 35, so "35 of the 43" in §13a reads 35 + 7 squirrels + 1 rodent = 43, and the 5 deer and 1 fox make 49). Every player joins as a human, so whenever squirrel, rodent, deer or fox slots are unheld the human count runs past 35 (up to 49); those **unpromoted humans past the 35 target** are ordinary townspeople served by the same posts and floors. The word "overflow" is retired.

**Human body budget** (`data/cast/population.json`; brief v2 §4-§5: "more human bodies than the 35 player slots ... at least 6 NPC police and at least 10 NPC hospital staff, plus ambulance crews on top"). Bodies are not role-locked: each has a **post**, and a post keeps an **AI floor** that join and promotion never take. The police and hospital floors are the brief's and are never cut; street, shop and attraction floors can be.

| Post | Standing bodies (FRB) | Standing bodies (from W3c) | AI floor (normal) | AI floor (at the hard cap) | Most players |
|---|---|---|---|---|---|
| Townsperson (walkers, residents; 6 begin as infected patients) | 32 | 30 | 8 street walkers | 4 | the rest (up to 49 − tier 2 held) |
| Shop worker (shared rota over open businesses, §4.8; corner-store clerk included) | 6 | 12 | all (players work shop jobs as townspeople) | 4 (FRB) / 8 (W3c) | 0 |
| Hospital staff | 14 | 14 | **10** (brief v2 §5) | **10** | 5 |
| Ambulance crew (its own post; does not count toward the 10) | 3 | 3 | 2 | 2 | 0 |
| Police (incl. precinct guard and the AI patrol-car crew, A1) | 14 | 14 | **6** (brief v2 §5) plus the guard and the car crew | **6** plus guard and crew | 8 |
| Attraction staff (clinic receptionist, 2 bartenders, 2 lounge guards, 2 wind-tunnel instructors, racquetball opponent, bowling and steakhouse staff) | 0 | 11 (re-posted shop or street bodies where possible) | per post in `population.json` (guards 2, bartenders 2, receptionist 1; the rest 0) | same | 0 |
| **Standing human Humanoids** | **69** | **84** | **26 / 37** | **22 / 33** | 35 target, 49 maximum |
| Reserve (built at boot, parked inside buildings, never destroyed) | 8 | 6 | | | |
| **Hard cap** (proven by S19, the re-scoped S5; target) | **90** | **90** | | | |
| Paintball bots (up to 16) and fender-bender drivers | borrowed bodies above their floors (D25, D29), never extra Humanoids | same | | | 0 |
| Novelty riders (mime, 5 kid cyclists) and 2 motorcyclists | 8 non-Humanoid rigs, AI-only (decision 21) | same | | | 0 |

**Worst case the budget must hold** (S19): 49 human players (every slot held by a human before any promotion) + 6 police + guard + 2 car crew + 10 hospital staff + 3 ambulance crew = 71 human Humanoids before a single shop worker, street walker or attraction NPC; with the street, shop and attraction floors about 85-95. The brief's police and hospital floors cannot be cut; the street and shop floors can, and silent posts (instructors, bartenders behind a counter) can become non-Humanoid rigs if S19 misses (D4 fallbacks).

**Supply order** when a human-species body is needed (join, promotion into hospital or police, a paintball bot, an attraction post): (1) an AI body of that post above its floor; (2) **re-post** an AI body above floor from another post: it walks into its building, `BodyFactory.applyLook` changes its outfit out of every player's view, and it walks out in the new post; (3) **deploy a reserve body** through the nearest house or shop door; (4) at the hard cap, drop to the hard-cap floors (the street floor first, then the furthest open businesses close with a "Back soon" sign; the police and hospital floors never move). Unpromoted humans past 35 (the server is full of humans, or players decline promotions, A2) are ordinary townspeople. At the hard cap with the hard-cap floors, 90 − 33 = 57 human players can be served, more than the 49 the server holds, so **a join is never refused inside the 49**. If S19 forces a lower cap (D4), a join that cannot be served waits on the flyover camera with "Finding you a place in town" and is offered any free deer, fox or squirrel slot meanwhile.

**Squirrel float** (brief §5, 10-14 bodies): 14 in autumn, AI squirrels lost at winter's end re-enter from nests one per in-game day until 14; never below 10 (if the count would drop below 10, a body re-enters at once from the nearest nest). Player squirrels count toward the 10-14.

**Rodent death is not a reset** [brief v2 §8]: the board is not wiped. Infection resets to the new rodent alone (`InfectionService.resetToRodent`), regular squirrels keep their hoards, humans keep their points, money and reputation, infected squirrels drop to lowest-rank human and infected humans are cured (instantly if recently bitten or en route to the hospital). The hidden win therefore has to be built inside one rodent tenure.

**Session reset** (after the outbreak cinematic, D31; or everyone infected) re-deals every player through the same possession path, except that the outbreak's winner keeps the rodent and infected squirrels still alive at the win keep a squirrel body in the new session; bodies are cured, not respawned; wallets, wardrobes and reputation persist (D26).

### 1.6 Net layer

Every remote is declared in `Shared/Net/Schemas.luau`, so the whole client-server surface is reviewable in one file. Every inbound payload is type- and range-checked (finite numbers, known enums, existing IDs) and rate-limited by a per-player token bucket. A rejected packet is logged and dropped; it never errors the server. High-rate streams use `buffer` codecs with size tests.

| Remote | Direction | Kind | Rate | Payload |
|---|---|---|---|---|
| `Motor.State` | C->S | unreliable, buffer | 15-20 Hz | seq, client time, mode, routeId (u16), s (u16 quantised), dir, pos, vel (about 40 bytes) |
| `Action` | C->S | reliable | 10/s | verb and args: Pounce, Feint, Strike, Kick, Leap, Interact, Stink, Lunge, Graze, Mark, Siren, EnterVehicle, ExitVehicle, Launch, Dock, Ticket, Treat, Fetch, Choose, Backup, Buy, Contribute, Wish, Equip, UseItem, Throw, Taunt, Report (sighting), Gig (start, step), Mischief (verb), Board, Alight, Sit, Vote |
| `Minigame.Input` | C->S | reliable (unreliable for continuous aim) | 20/s | gameId, seat, verb (aim, power, release, tilt, pull, place, serve, hit), args; validated against the game's state machine |
| `Paintball.Fire`, `Paintball.Move` | C->S | reliable; unreliable | 6/s; 20 Hz | shot origin, direction, client timestamp (rewound on the server); arena pose for the pose history |
| `Offer.Reply`, `Lab.Command` | C->S | reliable | 1/s; 5/s and dev only | offer choice (promotion, side exit, police recruitment); Lab commands |
| `Possession.Granted` / `Revoked` | S->C | reliable | event | actorId, species, role, motor snapshot |
| `Correction`, `ActionResult` | S->C | reliable | <= 2 Hz; event | authoritative state (once enforcement is on); outcome and rewards |
| `Telegraph` | S->C | unreliable | event | actorId, kind, commit time (kick and baton wind-ups) |
| `VehiclePoses` | S->C | unreliable, buffer | 15 Hz (5 Hz far) | interest-filtered: id, x, z, yaw, speed, state bits (about 13 bytes each) |
| `Hud.State`, `Map.Markers`, `Radar`, `Notify` | S->C | reliable / unreliable | <= 5 Hz on change; <= 2 Hz deltas; 5 Hz to drivers; event | private stats (wallet, reputation, rank or unranked, Power, health, pass expiry); markers for this player's audience; nearby speeds and limits; toasts |
| `Minigame.State`, `Paintball.State`, `Splat` | S->C | reliable (unreliable for positions) | on change; 20 Hz to participants; event | table or lane state and scoreboards; match state, projectiles confirmed, hits; splat position and colour for the pooled decals |
| `Outbreak.Start`, `Clock.Rate` | S->C | reliable | event | the server timestamp every client starts the cinematic from; the clock-rate multiplier |

Low-rate public body state rides on **attributes**: `ActorId`, `Species`, `Variant`, `Role`, `Controller` (`ai`/`player`), `MoveState`, `Clip`, `ClipT0`, `Health`, `InfectedTell`, `LookSeed`, `Garb`, `Wet` (water-gun reaction), `Companion`. Rank, money, reputation, the vigilante flag, alert zones, the hidden strength boost and infection internals stay on the server; no meter for infection, alertness or strength is ever shown [brief v2 §8].

### 1.7 Authority map

| Thing | Authority | Notes |
|---|---|---|
| Possessed body movement (human, squirrel, rodent, fox, deer) | client, validated by server | log-only validation until W7; enforcement and corrections after |
| AI bodies | server (kinematic, anchored, `BulkMoveTo`) | LOD tiers (D4) |
| AI vehicles | server simulation at 30 Hz | clients render ghosts from `VehiclePoses` |
| Player vehicles (patrol cars, carts, bikes, pickups, SUVs, jet skis), drone | client-owned device, server samples and validates | speed caps; no jump over 30 st per tick [traffic §13]; traffic law evaluated on the server from the sampled poses |
| Bites, kicks, damage, deaths, infection, cures, nuts, hollows, claims, money, purchases and receipts, reputation and votes, gigs and quality, rank, quests, tickets, fines, cells, sightings, marks, promotions, run-overs, knockdowns, Power | server | every random roll on the server |
| Minigames, no-stakes class (pinball, tilt labyrinth, bead maze, kite) | client physics; server sanity-checks the reported result (bounds, rate) | no Spicy-Dollar stakes anywhere in the brief, so validation stays light (D28) |
| Minigames, shared-table class (bowling, pool, bumper pool, darts, Jenga, volleyball, racquetball) | server-owned parts, or the current shooter's client with ownership handed per turn and the result validated against a replayed simulation where cheating would pay | pattern chosen by S13 per game (D28) |
| Paintball | server projectiles at 60 Hz with client prediction; hits from rewound poses (1 s history) | the only lag-compensated system before W7 (D29) |
| Wind-tunnel balls, Jenga tower at rest, bowling pins | server | watchers see replicated physics |
| Street lights, flicker, camera modes, taunt bubbles, splat rendering | client | from replicated state, seeds and the server clock |
| Animation, camera, HUD, sky and lighting, ambient life, door swing visuals, beacon blink, rotor and wheel spin | client | from replicated state and the server clock |
| Game time | server epoch attribute | clients derive everything from it |

---

## 2. Key decisions

Each decision gives the choice, why, the fallback and how it is verified. Spikes S1-S20 are in W0 (§4.3); D22-D25 and §2.1 were added in revision 2; **D26-D33 are added in revision 3** for brief v2, and D13, D14, D17, D22, D23 and D24 are amended where v2 overrides them (the amendment is marked **rev 3**).

| # | Decision | Why | Fallback | Verified by |
|---|---|---|---|---|
| D1 | **Possession = server sets `player.Character` on a pre-existing body**, with `PlayerCharacterDestroyBehavior = Disabled`, `CharacterAutoLoads = false`, stream-around first, network ownership to the player, brain `suspend`/`resume` snapshots (§1.5) | The brief's hard rule [brief §4]; the API surface is confirmed [feas B.a] | "Blink handoff" (0.25 s camera dip hides a snap to the validated state); then Server Authority for animals once out of beta | S2 + owner check in OS-1a |
| D2 | **Movement: client-owned bodies, shared pure motors, server validation.** Animals, cars and the drone move a non-colliding unanchored root with rigid `AlignPosition`/`AlignOrientation` in `PreSimulation`; humans use default Humanoid controls. Validation logs only until W7, then enforces | Rails need 60 Hz input-coupled motion [routes_movement §20]; one motor codebase for AI and players is the actor-model rule | Server-authoritative rail with client prediction and reconciliation (same `step`); Server Authority (beta) later | S3 (cheat harness, honest traces), OS-1a feel check, FRB checks M1-M2 |
| D3 | **Animation is local on every client**, driven by replicated state (`MoveState`, `Clip`, `ClipT0`) and, for one's own body, by the local motor. Animators are created client-side, so no animation replicates. At handoff nothing changes hands visually, which makes "mid-stride" continuous by construction | Sidesteps the known pitfall that animations only replicate under specific ownership and Animator setups [feas B.a pitfall 2]; zero animation bandwidth for about 70 AI bodies | Standard replication: server-created Animator, owner-played tracks; others play nothing for player bodies | S2 |
| D4 | **AI scheduling:** brains at 10/4/1 Hz by distance to the nearest focus (every player body and the drone camera): Near < 150 st, Mid 150-500 st, Far > 500 st (Far = "commute" along lanes, doors instant). Perception at 5-10 Hz on a spatial grid using height above local ground. Budget < 4 ms per frame average, < 8 ms p99, as a **regression signal** in Luau Execution; the gate is the live MicroProfiler in W7 (F-14) | About 100 Humanoids is where stutter begins [feas B.e]; our worst case (**rev 3**) is about 90 human Humanoids (49 human players plus the brief's 6 police and 10 hospital floors, crews, guards and attraction staff, §1.5) plus 8 non-Humanoid riders, about 22 animals, about 45 vehicles, 2 concurrent fender benders and a 16-body paintball match | Parallel Luau perception in 2-4 `Actor`s; lower Mid/Far rates; a compact state stream instead of moved bodies for Mid/Far; non-Humanoid rigs for silent posts (instructors, bartenders behind a counter); lower the hard cap by cutting street, shop and attraction floors first. **Never** below 49 player bodies plus the brief's police and hospital floors (§1.5) | S19 (re-scoped S5); `SimFull` regression gate from W1; W7 live profile |
| D5 | **Streaming and the drone view:** bodies, buildings, hollows and hospital zones `Atomic`; backdrop and landmarks `Persistent`; a **Skyline** layer (one or two massing parts per building, generated by the bake, `Persistent`) that fades locally where real geometry has streamed in; `LevelOfDetail = SLIM` written by the bake from lot data **from W1 on** (inert in Studio tests, live on published versions); the pilot's `ReplicationFocus` follows the drone (F-13) and the drone requests stream-around along its path | SLIM only works on a saved, published place and static geometry [feas B.e]; Skyline works in every Studio test from the FRB on; the far view is the role that "justifies the backdrop" [brief §10], so it is **tested in W0**, not last | Skyline-only far view if SLIM disappoints; Blender ground tiles if far terrain does not render (D6) | **S11** (W0, published private place); FRB check DR2; W6 published-server check with the real backdrop |
| D6 | **WorldGen: compile, then bake at build time in Lune** into `build/Town.rbxm` inside the saved place (static, diffable, SLIM-ready). Terrain is written at server boot from `World/Height` when its hash is stale (Lune cannot write voxels). **Which ground is primary is decided at G0**: Terrain, or Lane-2 Blender ground tiles from the same height function (SLIM-friendly, no boot cost), using S6 (boot time with the town *and* the near-hill backdrop bands) and S11 (does streamed-out terrain render from 300 st) | "From data, never hand-placed" [brief §2] and SLIM both hold; the place stays a build artifact; every Studio Test, CI task and live server pays the terrain write (F-7) | Terrain: (a) write the chunks around players first, holding them on the flyover; (b) ground as Lane-2 MeshPart tiles (<= 2048 st each, F-8); (c) Studio "Bake Terrain" before the final publish. Bake: unsupported classes emit stubs the runtime completes | S6 (WriteVoxels timing with backdrop bands, BakeParity); S11 |
| D7 | **Data: JSON plus JSON Schema in HTML units**, compiled once to studs into committed `generated/` Luau (CI fails if stale). The Ladder and Tunables are Luau (the brief wants the ladder "in code") with unit tags. Spec IDs and line references carry over | Every number stays checkable against the spec; Lune, Python (bpy) and Node all read JSON; one unit boundary | Buffer or base64 encoding if large modules misbehave; smaller chunks | S6 (largest chunk require time) |
| D8 | **Routes: harvest all 1,332 v5.4 routes exactly** (control points, kind, radius, visualOffset, generator, lotId) from a headless run of the pinned HTML; name regexes become explicit `surface`, `surfaceNormal` and `autoGrab`. Rebuilt lots drop their harvested routes by `lotId` and emit **template** routes; **linkers** re-run the HTML bridge rules deterministically | Brief §1: the HTML is the reference for climbing routes; new lots must be data | `routes_catalog.json` formulas reimplemented (loses RNG-exact details) | Lune: samples within 0.01 u; regression counts (1,332 routes, 81,613 samples, 95 fork trunks, 770 forks, 149 islands, largest island 563) |
| D9 | **Traffic:** AI vehicles simulated by the server at 30 Hz on a per-lane leader/follower model; clients render **ghost vehicles** from `VehiclePoses`; the fatal test is the exact `sweptVehicleHit` port for every squirrel actor every tick, never `Touched`; stationary vehicles never kill; every scripted reposition (and every possession) resets the previous pose; 1 s pose ring buffers for lag compensation (enabled in W7). Handedness, the trolley deadlock and the patrol-car lane defect are fixed, not ported [traffic §11] | Brief §8; [traffic §13]; a streamed-out server car can never be "invisible yet lethal" | Anchored server vehicle models moved with `BulkMoveTo`; client near-miss flag confirmed by the server | S4; FRB checks P8, R6, M5 |
| D10 | **Player patrol cars:** a kinematic arcade `CarMotor` (the same model as AI cars) on the client, shapecasts against world geometry, OBB checks against the fleet; officer welded into the seat; siren and lights as attributes; park anywhere. AI cars treat player cars as fleet members and yield to them [A1] | Deterministic, no physics tuning, same geometry feeds the swept test | `VehicleSeat` constraint chassis with client ownership | FRB checks P4, P5, P7, P8 |
| D11 | **Animation clips:** Blender exports per-bone transforms per frame to JSON; Lune builds `KeyframeSequence` `.rbxm` (verified possible [feas A]); Open Cloud uploads them as Animations. Studio playtests can play git-tracked clips with `AnimationClipProvider:RegisterAnimationClip` before upload. Humans use Roblox's stock R15 locomotion; placeholders use the procedural backend. Gameplay windows come from Tunables, never from clip timing; clips carry `Commit`/`Recover` markers for sync only. **A declared deviation** from the brief's "imported via the Studio animation importer" (§2.1 deviation 2): the FBX with animations is still exported and committed, and the importer stays the fallback | Keeps the owner out of the clip pipeline; the docs warn that files edited outside Studio "might not upload or function" [feas B.d] | Owner imports each clip FBX in the Animation Editor and publishes (about 1-2 min per clip) in the Art Inbox place; this time is budgeted per session in §6.6 | S7 |
| D12 | **Art delivery in four lanes** (§5.1) through `data/assets/manifest.json`. Rigid kits and props go through Open Cloud Model uploads and are baked into the place; skinned rigs and anything with SurfaceAppearance are imported once by the owner into the **Art Inbox** place and loaded at runtime by ID (`InsertService:LoadAsset`, allowed for assets owned by the experience owner). So the saved place never contains SurfaceAppearance and stays publishable through Open Cloud. Every upload is **moderated**: the manifest records `pending`, `approved` or `rejected`, a pending or rejected ID falls back to the placeholder, and blood lives in its own small texture so a rejection never blocks the whole rodent (F-9) | The API publisher does not update SurfaceAppearance, unions or BaseWrap [feas B.d]; the owner's Studio time stays small | If Lune-written MeshParts misbehave, kits also load at runtime and the plugin's "Bake Town" writes them into the place before a Studio publish; if Lane-2 kits carry no PBR maps, `MaterialVariant` with uploaded maps gives kits and greybox PBR without Studio (S8f) | S8 |
| D13 | **Avatar blend (70/30)** [A3]: traits from `GetHumanoidDescriptionFromUserId` (body colours, accessories, face, scales, clothing IDs) plus colour words from item names via `GetProductInfo` (cached) and a curated item-to-colour table; no clothing pixels. **Humans** (**rev 3**, brief v2 §13a: "the body keeps its own build and clothes (about 70%) and takes the player's face, hair and skin tone (about 30%). Do this with appearance properties scripts can set, not tinting") keep body type, uniform and silhouette and take **skin tone** (nearest of 8 tones, as the body-part colour, the same scriptable property Roblox's own `BodyColors` sets; Q1 confirms), **one hair or head accessory** and **the face** (a classic face decal copied from `CreateHumanoidModelFromDescription` onto the custom head's `FaceDecal`; a dynamic head maps to the nearest of 6 stock expressions). The addendum's two accent colours (trim, tie, scarf, shoes) are **dropped for humans** by v2; outfits are the role's, untinted. **Animals** keep species mesh and markings and take a capped fur tint (30 %), pattern colours (tail tip, stripes) from shirt and pants colours (from item names or the curated table; layered-clothing shirts and jackets count as shirts), eye colour (the rodent's eyes stay bloodshot red) and one **rigid** accessory shrunk and hand-welded to `HeadSocket` (WrapLayer accessories are skipped). Bizarre avatars keep one signature feature; nothing may change silhouette, hitbox, hip height or route offsets | Brief v2 §13a for humans; Addendum B1 keeps the A3 animal blend; hitboxes drive gameplay; other creators' items reach us only through `CreateHumanoidModelFromDescription` (F-4) | Stock look with a seeded variant if traits fail; body and accessory colours only if `GetProductInfo` is rate-limited; 6-8 pre-authored fur variants if runtime fur tint fails S8(c2); a fixed set of 8 skin textures if the owner answers Q1 "no part colours" | S9; S8(c2); Lab samples (classic, neon, giant, non-human bundle, dynamic head, layered clothing) because Studio test players have negative UserIds |
| D14 | **Persistence per server for gameplay** (rank, hollows, homes, remodels, infection, the rodent queue), as the brief scopes them [brief §6, §8]. **rev 3:** what is bought or earned across servers persists through the DataStore profile of D26 (wallet, purchases and receipts, wardrobe and garb, reputation, lifetime stats); the FRB still needs no DataStore (the wallet is server-life until W4 #11) | Brief v2 sells Spicy Dollars for Robux and garb "kept permanently", so saving is no longer optional (dec 27 reversed by §13a) | Profile unavailable: read-only session (no Robux purchases offered), gameplay unaffected | S15; `Persistence` suite (§6.5) |
| D15 | **Delivery to the owner:** each owner build is `rojo build build.project.json` saved as a new version of the main place through Open Cloud; the owner opens it from the Studio start page and presses Test. CI saves go to a separate **CI place** in the same experience (created by the owner in Step 0), so tests never disturb the owner's build. Every engine-test task runs against the **exact version ID** its save returned (`/versions/{v}`), and all cloud calls from both tracks pass through one on-disk lock and token bucket (5 task creates per minute per key owner), so two tracks never test each other's build (S-13). Team Create stays **off** on the main and CI places, so no collaborative autosave can overwrite an API-saved version (F-11). The owner never runs a terminal. Rojo live-sync remains available, so this is a declared deviation in form only (§2.1 deviation 1) | "The owner is not a programmer" | Single place: Claude re-saves the current owner build after every CI run; or a `.rbxl` attached to a GitHub release | S1 |
| D16 | **Type safety and CI:** `--!strict` everywhere; Selene; Lune tests; `luau-lsp analyze` in **GitHub Actions** (which can download the release binary the container cannot [feas A4]); `BootSmoke` requires every module in the real engine | No type checker in the container | Owner allows a container source build of luau-lsp | S10 |
| D17 | **Infection:** per-actor infection, town % = infected human bodies / all human bodies; HTML numbers as defaults. **Critical mass is the rodent's win**: the player holding the rodent at that moment is recorded as the session's winner (an AI rodent can never win, decision 17). **rev 3** (brief v2 §8, §15 dec 11): the ending is **the outbreak cinematic, not an end card** (D31): every player's camera pulls up and out over the town, time accelerates, squirrels sweep house to house faster and faster, the sky goes overcast and dims (at night it fades to black), about 20-30 real seconds, then the session resets; the end card survives only as the fallback for a client that cannot play the cinematic. The winner keeps the rodent slot into the new session and gets a cosmetic mark (glowing scar) for that run (Q12); infected squirrels alive at the win keep squirrel bodies; everyone else is re-dealt through possession at the lowest human rank. **Rodent death** resets infection to the new rodent alone without wiping hoards, points or reputation (§1.5). No one sees an infection meter (Lab only) | Reconciles "critical mass wins" with "session resets" [brief v2 §8; hospital_police_infection §13]; the owner answered dec 11 explicitly | Thresholds are tunables; end card as the client fallback | Decision 11 (decided); `OutbreakCinematic` suite; OS-5 scenario |
| D18 | **Interactions:** ProximityPrompts (custom style) for doors, stations, shelves, forage, knotholes, car doors, consoles and ticket targets; the server re-validates role, distance and state. Continuous verbs (pounce, strike, stalk) use ContextActionService. Long channels (vent chewing) are server-timed, not `HoldDuration` | Keyboard, gamepad and touch for free | n/a | FRB checks |
| D19 | **Clock:** 72 real seconds per in-game day by default, with a non-linear day curve that holds sunrise, golden hours, sunset and blue hour; 7-day weeks; winter is week 6 of each 6-week cycle (about 50 real minutes); lunar month 29.53 days | Brief §12 target; a linear 72 s day would give 2-3 s sunsets [worldgen_districts_art §17.2] | One constant | Owner decision 10 |
| D20 | **Combat under latency:** telegraphs and lunges play instantly on the client; the server resolves with up to 150 ms rewind and windows widened by half the RTT; a rejected result arrives as a correction, never a rubber-banded lunge [squirrel_abilities §26] | The duel is "the role everyone wants" | Fixed input-buffer windows; looser tunables | FRB R3-R5; W4 duel tuning |
| D21 | **Units and facing:** runtime code sees studs only; all authored models face Roblox `LookVector` (-Z), which Humanoids require; `Units.yawCFrame` adds pi to HTML yaw in exactly one place. "North" follows owner decision 7 | The specs say models face +Z in the HTML; one documented conversion beats per-asset fixes | n/a | S8 arrow check |
| D22 | **Outfits and how humans take the player's look** (F-1, F-2; **rev 3** per brief v2 §13a "appearance properties scripts can set, not tinting"): human role outfits are **per-part colour textures** on the custom R15 bodies (`MeshPart.TextureID`, which scripts can set, uploaded headlessly as images), authored on **one shared UV layout** across the 6 bodies, **plain colour, with no tint zones for accents**. The player's 30 % arrives through settable appearance properties only: **skin tone** as the body-part colour of the skin parts (head, hands, bare arms, shown through transparent skin texels; Q1), **the face** as a decal, **hair** as an accessory; clothes stay the role's. Human bodies carry no SurfaceAppearance (detail baked into the colour map). Squirrel, rodent, fox and deer keep SurfaceAppearance (PBR fur) and the **A3 fur tint**, which Addendum B1 keeps for animals, on `SurfaceAppearance.Color` (TintMask) **only if S8(c2) proves runtime writes on a `LoadAsset` rig**; each separately tinted animal zone (`Body`, `Pattern`, `Eyes`) is its own MeshPart, because a SurfaceAppearance has one Color. Paintball garb and fashion-stand hats are rigid accessory sets through the D13 accessory path (S16) | One SurfaceAppearance per MeshPart, most of its properties not scriptable [feas g]; 13 outfit roles x 6 bodies as Studio imports would swamp the owner; v2 forbids tinting humans, which removes the accent zones and simplifies the texture work | (a) one pre-made SurfaceAppearance per outfit on the shared UVs, imported once in the Art Inbox (about 13 imports, about 25 min, OS-6b) and cloned at runtime; (b) R15-standard UVs with classic Shirt/Pants images; skin from 8 fixed textures if Q1 says no part colours; animal fallback: 6-8 pre-authored fur variants; garb as accessories plus texture swap if layered clothing fails S16 | S8(c2), S8(e) (skin texels only), S16; decision 29 (accepted, amended) |
| D23 | **Population under the hard 49-slot cap** (**rev 3**, brief v2 §5): `Players.MaxPlayers = 49`, no overflow roles, no spectators, late joiners wait for the next server; the brief's 35 human slots include hospital and police; posts, AI floors (police >= 6, hospital >= 10, ambulance crews extra, never cut), re-posting, a parked reserve and a hard cap of about 90 human Humanoids that S19 proves; squirrel bodies float 10-14; 6 deer bodies for 5 deer slots (Q22) | Brief v2 §5 arithmetic (35 + 7 + 1 + 5 + 1 = 49); the hospital and the station stay staffed at full occupancy by the brief's own floors (S-9) | Lower hard cap by cutting street, shop and attraction floors, then a "finding you a place" wait (D4) | S19 at the worst case; `Population` unit tests; `LadderE2E` fill to 49; `Cap49` suite; decision 28 (decided) |
| D24 | **Audio** comes first from Roblox's licensed audio library (sirens, ambience, birds, crowd, fountain, the in-game radio, 1920s-feel jazz for lounge one, paintball fire and hit sounds); Open Cloud audio uploads (**100 per month**: the account is ID-verified, Addendum B2) are kept for signature sounds (rodent screech, bite, stink puff, chili rush, drone rotor, the paintball marker) and, if runtime layering of library pads does not read as "seamless", one procedurally generated ambient loop for lounge two | The cap no longer blocks W6 | Owner uploads in Studio if the cap is hit | decision 30 (decided) |
| D25 | **Fender-bender drivers, paintball bots and attraction staff are borrowed bodies** (F-6; **rev 3** extends it): AI vehicles carry no driver bodies; when an incident spawns, two AI townsperson bodies above their floor are placed beside the two cars while no player is looking (`markTeleported`), and walk off again when the report is filed; paintball bots and most attraction staff are townsperson bodies above their floors re-posted into the venue. No extra Humanoids | S19's budget; feas B.e | Driver and bot models as non-Humanoid rigs | S19 with 2 concurrent incidents and a 16-body match |
| D26 | **Spicy Dollars, developer products and the DataStore profile** [brief v2 §13a]: one currency, the Spicy Dollar, kept in integer cents; the PDF's "credits" and dec 20's "coins" are Spicy Dollars (Q3); wages at 2 cents per in-game hour; goods priced in `prices.json`; **Robux buys Spicy Dollars through developer products** created by the owner on the Creator Hub (whole Robux amounts; default tiers 25, 100 and 400 R$ for 100, 400 and 1,600 S$, Q19), granted in `MarketplaceService.ProcessReceipt` with an **idempotent receipt ledger** keyed by `PurchaseId`; the whole wallet, the ledger, the wardrobe (paintball garb, fashion-stand outfits), the item inventory and reputation live in a **DataStore profile** with session locking, loaded before the first possession and flushed on leave and `BindToClose`. Money counts toward the **human queue only**, never toward hospital or police rank (C6). Lives in W4 #11, before any product is live; the FRB wallet is server-life | Anything bought with Robux must survive a server closing or it is a chargeback and a policy problem; the brief makes saving mandatory (dec 27 reversed) | ProfileStore-style community module if the hand-rolled lock misbehaves; products created but inactive until the profile is proven; read-only session on load failure | S15; `Economy` and `Persistence` suites; a Lune economy simulation shown at G1 (Q4) |
| D27 | **Player vehicles are kinds of one `PlayerVehicles` device family** [brief v2 §13a, §15]: `CarMotor` parameter sets for patrol car, golf cart, pickup and SUV; `BikeMotor` (arcade, balance-free); `JetSkiMotor` over a defined water surface; the gondola is a `Ride`. Carts and bicycles for anyone (also the police carts that can be joyridden); pickups (6) and SUVs (4) for **the top two ranked humans** through `Ladder.subroles.humanDriver` (hand-over when parked; undocumented in-game); patrol cars for the top two officers (A1); jet skis rented for Spicy Dollars. Every player-enterable vehicle gets a **modelled interior and dashboard** and switches to first person on entry (§14); carts are in the fatal fleet at low speed, bikes are not (Q8) | Brief v2 adds six vehicle kinds and first person; one family keeps the swept test, the traffic law and the camera rule in one place | `VehicleSeat` chassis for a kind whose kinematic feel fails S14; pickups and SUVs parked-only if the human-driver hand-over proves confusing | S14; FRB checks H14, P4; `Traffic` suite with player kinds |
| D28 | **`Item`, `Minigame` and `Ride` frameworks, with physics authority by stakes** [brief v2 §13a, §15]: an item is a Tool with a server-validated effect; a ride has no controls and no score (sky lift, parasailing, wind tunnel; the jet ski is the steerable exception); a minigame has controls and a result (bowling, pinball, pool, bumper pool, darts, racquetball, paintball, tilt labyrinth, giant Jenga, volleyball) and **only minigames get the ironing-out treatment**: a common harness, Lab scenarios, headless determinism tests and one 10-15 minute owner check each. Physics authority: no-stakes single-player games run on the client and report a sanity-checked result; shared-table games run server-owned or on the current shooter's client with ownership handed per turn and a replayed check where cheating would pay; the wind tunnel's balls are server-owned. S13 picks the pattern per game | The plan had avoided physics; v2 wants ten physics games; stakes are scoreboards only, so authority can be chosen for feel | Client-only physics everywhere with sanity checks; shared tables turn-based with server replay | S13; `Minigames` suite; OS-5c checks |
| D29 | **Paintball as an instanced match inside the town server** [brief v2 §13a]: the TV-station lot holds its own match state (lobby, teams, timer, scoreboard, end card), bots from borrowed bodies (D25), server-simulated projectiles with travel and drop, a five-shot magazine, **server-side hit detection with lag compensation** (1 s pose history rewound to the shooter's timestamp, pulled from W7 into W4 for the arena only), pooled splats, sprint and crouch, locked first person, squirrels excluded; access passes and the garb shop run on the town wallet; a player may leave a match early and walk back into town (Q9). **Gate G-PB:** built in W4 and playtested with the owner (OS-5b) before it is called done; if the mechanics are weak it is cut, and nothing else depends on it | The brief's own rules (one actor model, passes on the game clock, garb worn back into town) assume continuity with the town; a separate place would need persistence at both ends | A separate place through `TeleportService` with reserved servers if S18 shows the arena cannot share the server | S18; `Paintball` suite; OS-5b (G-PB) |
| D30 | **Street lighting everywhere as data** [brief v2 §15]: the compiler places lamps per block, porch lights on every house and emissive shop fronts (`LampPlan`, `lighting.json`); clients enable real `PointLight`/`SpotLight` pools (`Shadows = false`) within a radius at night with seeded flicker on a few; emissive heads on the Skyline layer so the lamplit grid reads from 300 st for the drone and the cinematic. Greybox lamps with real lights land in **W3a** so the W4 cinematic can be judged; the final pass is W6 #4 | The drone and the outbreak cinematic depend on it; lamps stream out at drone altitude, so the far view must come from emissives | Smaller radius, fewer real lights per block, Neon-only beyond 100 st | S17; OS-7 night check |
| D31 | **The outbreak cinematic** (details in D17 and `Outbreak/OutbreakDirector`): server-driven phases on the clock, squirrels in `OutbreakSweep`, an `Outbreak` lighting state, one camera tween per client from the server's start time on the Skyline layer without streaming requests; end card only as the client fallback | Brief v2 §8, §15 dec 11 | End card for everyone if the director fails in the engine suite | `OutbreakCinematic` suite; OS-5 Lab scenario |
| D32 | **The world footprint grows beyond the v5.4 rectangle** [brief v2 §13a, §15]: `World/Height` keeps the verbatim v5.4 function inside the rectangle and adds authored extensions from `terrain_extensions.json` outside it: the hill with the sky lift and hilltop restaurant (a second vantage), the ridge with real trees, the back field with hills and the beach that runs past the public area into the **off-road** district (no roads, lanes or lots; `jurisdiction: false`: no tickets, no arrests, the drone can see it); the near backdrop band moves outward; the world clamp and the town-plan page grow by the 12 v2 sites | The verbatim port stays verbatim where it applies; everything new is declared data | Hill and back field as Blender ground tiles if the terrain write misses S6 on the larger footprint | S6 and S11 re-run on the extended footprint; OS-3; OS-7 hill vantage |
| D33 | **Rodent health and Power are two clocks** [brief v2 §8]: health 100, kick 55, defenders x1.5 (dec 12 accepted), **drain 1 hp per in-game day without a bite**, **heal 10 on a human bite and 20 on a squirrel bite**, slow regen while stalking or in a hollow re-tuned so the drain and the heals are the main recovery paths (defaults 0.25 hp/s stalking, 1 hp/s in a hollow, so a kick takes about a minute in cover); the alert-zone strength boost is a hidden kick multiplier (default 1.25, always below 1.82 so one kick never kills). **Power** (v5.4 table) fades on real active minutes and is the rodent's visible status meter; health is survival. Neither clock reads the other | The owner's dec 12 answer adds the drain and heals; the plan's old regen would have made them irrelevant (C5) | All five numbers are Tunables, re-tuned in the FRB | `CombatRules` and `PowerRules` unit tests, one per clock; FRB R7-R9 |

### 2.1 Declared deviations from the brief (accepted by the owner by default in brief v2 §15: "where a default is not named here, accept it"; decision 31)

| # | Brief says | Plan does | Why | If the owner says no |
|---|---|---|---|---|
| 1 | "Roblox Studio syncing from the filesystem" [brief §2] | Each owner build reaches Studio as a saved place version (Open Cloud); Rojo live-sync stays available but is not the owner's path | The owner never needs a terminal or the plugin running; still no zip handoffs | The owner runs `rojo serve` through a one-click helper Claude prepares, and Claude stops saving owner builds |
| 2 | Clips "imported via the Studio animation importer" [brief §2] | Clips go Blender -> JSON -> Lune KeyframeSequence -> Open Cloud Animation (D11); FBX with animations is still exported and committed; the importer is the fallback | Saves the owner about 70 clip imports (1.5-2.5 hours) | The owner imports every clip in the Animation Editor (budgeted in §6.6) |
| 3 | "Each real day of play earns remodel points" [brief §8] | One point per real hour played on the server (decision 22) | Servers rarely live a whole real day, so a daily point would almost never arrive | Points per real day of cumulative play on that server |
| 4 | "Limited server count so that a real queue exists" [brief §5] | Server fill "Maximum" (decision 26); Roblox cannot cap the number of servers | Platform limit | A lobby place with reserved servers through TeleportService (much later; not planned) |
| 5 | Avatar face onto every human [A3] | Classic faces transfer; a dynamic head maps to the nearest stock expression (D13) | Dynamic heads cannot be moved onto custom heads | Stock face for dynamic-head avatars |
| 6 | Human outfits as PBR art [owner art direction, implied] | Human outfits are colour-texture only (D22) | Headless and scriptable; PBR outfits would mean about 13 Studio imports | Fallback (a) of D22 (about 25 owner minutes) |
| 7 (conditional) | "Rodent, regular squirrel, deer and fox stay in standard third person" [brief v2 §14] | The rodent's stalk becomes an over-shoulder third-person stalk (default). **Only if** the owner answers Q10 "keep v5.4's first-person stalk" does that become deviation 7 | v5.4's stalk is first person (hold right mouse); the owner may want it kept as the one exception | Nothing: the default already follows §14 |

Brief v2 itself adds no deviation: rev 3 builds everything it asks for. Three of its numbers are flagged as **time-scale questions, not deviations** (Q2): hollow visits every 3 in-game days (3.6 real minutes), 5-day passes (6 real minutes) and 5 + 5 votes per in-game day (every 72 s) are built as written, as Tunables, and re-tuned in the FRB if the owner meant a longer day.

---

## 3. Data schemas

### 3.1 Conventions

- Positions in data are HTML units (`x`, `z`, optional `y`); `y` is absolute only where the spec gives it absolutely, otherwise `dy` above `Ground.groundAt`. The compiler converts to studs (x 2.5) once.
- Facing is `+X`, `-X`, `+Z`, `-Z` or `yaw` in HTML radians. Footprints are `{w, d}` in world axes after rotation [worldgen_core §1].
- Durations on the game clock are strings (`"day"`, `"week"`, `"3h"`); real seconds are numbers.
- Every ported record carries `src` (spec citation or v5.4 line), so provenance survives.
- `tools/compile` migrates `spec/data/*` once (243 lots, 116 roads, 25 lanes, 87 cast, wildlife); new content is added by hand after that.
- Money is always integer **Spicy cents** (`"price": 12` is 12 cents; 100 cents = 1 S$). Robux amounts are whole numbers [brief v2 §13a].

### 3.2 Lot (`data/town/lots/<district>.json`)

```jsonc
{
  "id": "core_house_0_victorian",          // stable; spec ids preserved (routes, cast and saves refer to it)
  "district": "old_town_core",             // -> districts.json (bounds, HUD tag, map label)
  "type": "house",                         // -> data/lot_types/house.json
  "archetype": "victorian",                // -> data/archetypes/houses/victorian.json (houses only)
  "x": -56, "z": -53,                      // lot centre, HTML units
  "facing": "+Z",                          // world axis the front faces; or "yaw": radians
  "footprint": { "w": 18.04, "d": 15.58 },
  "seat": "graded_pad",                    // graded_pad | terrain_centre | absolute:<y>
  "params": { "storeys": 2, "porch": "wrap", "chimney": true },   // validated by the lot type's paramSchema
  "flair": { "seed": 1034, "lock": { "wall": "#ded7b7", "trim": "#f5ecd5", "roof": "#63524c" } },
  "yard": { "items": ["garden", "feeder", "shed", "doghouse"], "fences": ["F1", "F2"] },   // default from the
                                           // archetype's yard set by flair.seed when omitted (invariant 12)
  "home": { "interior": "victorian_a", "claimable": true, "hideSpots": 3, "backExit": true,
            "defender": null,               // or { "kind": "rolling_pin", "look": "older_woman_a" }
            "residents": ["donna", "frank", "mrs_abbott"] },
  "forage": { "inherit": true, "add": [ { "kind": "bird_feeder", "at": [-45, 68], "premiumFor": "H2" } ] },
  "risk": { "homeowner": 0.5, "dog": "chained", "cat": "cat_0" },
  "jobs": { "inherit": true },
  "traffic": { "parking": "curb_front", "hydrants": [], "driveway": { "side": "-X", "len": 26 } },
  "routes": { "source": "harvest" },       // harvest | template | none
  "streaming": "Atomic", "lod": "SLIM", "tags": ["map_label"],
  "src": "v5.4 L1034 buildHouse(0); lots_core.json"
}
```

### 3.3 Lot type (`data/lot_types/<type>.json`): a barber shop is data

Builder families are Luau; lot types are JSON records that parameterise them and may `extend` another type.

```jsonc
{
  "type": "shop_barber",
  "extends": "storefront_small",           // inherits builder, kit, routes, traffic and map defaults
  "builder": "Storefront",                 // src/worldgen/Builders/Storefront.luau
  "kit": "kit.storefront.small",           // manifest key; blockout recipe until the kit lands
  "defaults": { "footprint": { "w": 14, "d": 18 }, "storeys": 1, "palette": "brick_warm",
                "awning": "stripe_red_white", "prop": "barber_pole" },
  "paramSchema": { "sign": { "type": "string", "maxLen": 18, "required": true },
                   "chairs": { "type": "int", "min": 1, "max": 3, "default": 2 } },
  "interior": { "template": "barber", "public": true, "openHours": [8, 18] },
  "jobs": [ { "socket": "chair_*", "job": "barber_cut", "credits": 3, "cycleS": 20, "role": "human" },
            { "socket": "register", "job": "cashier", "credits": 1, "cycleS": 12, "role": "human" } ],
  "staff": { "ai": [1, 2] },
  "forage": [ { "kind": "trash_can", "socket": "rear_bin", "yield": [1, 2], "cooldown": "day", "risk": { "humans": 0.15 } } ],
  "risk": { "base": 0.15 },
  "routes": ["roof_ridge_or_parapet", "downspout_front_right", "gutter_to_roof", "awning_edge"],
  "traffic": { "curb": "parallel_parking_front", "hydrantChance": 0.3 },
  "map": { "icon": "scissors", "label": "$params.sign" },
  "streaming": "Atomic", "lod": "SLIM", "skyline": "box"
}
```

The lot entry the brief asks for is then one line:

```jsonc
{ "id": "east_barber_01", "district": "east_commercial", "type": "shop_barber", "x": 560, "z": -128,
  "facing": "+Z", "footprint": { "w": 14, "d": 18 }, "params": { "sign": "CLIP JOINT", "chairs": 2 } }
```

From those two records the compiler and bake derive: the shell seated on terrain (kit meshes once they exist), awning and pole prop, the SurfaceGui sign, a furnished interior with door sockets linked into the pedestrian nav graph, two job sockets, AI staff, a rear trash-can forage source with risk, roof/downspout/awning routes passed through the linkers, colliders, curb parking with a red curb by any hydrant, a map icon and label, Skyline massing and the streaming and LOD flags. A new **type** such as `shop_music` is one more lot-type file reusing `Storefront`.

**Attraction lot types** (brief v2 §13a; rev 3) add one optional block, `attraction`, read by the `Minigame`, `Ride`, `Item` and camera frameworks (schema in §3.17): which minigame tables and lanes the interior holds, which rides start here, which items are sold at which counter, seat sockets that raise reputation, `cameraLock: "firstPerson"`, `squirrelBlocked` collision for glass, guards and their posts, access by pass, and the gigs the lot offers. A bowling alley is a lot type whose interior template declares six lanes, three pinball sockets, two pool tables, a bumper pool table, a dartboard, the fortune machine, the back-of-house props and the ball-return `tunnel` routes.

### 3.4 House archetypes, flair and interiors

- **Archetype** (`data/archetypes/houses/<name>.json`): footprint ranges, levels, roof kinds and pitch, doors with in/out waypoints, sockets (mailbox, service drop), route templates, interior templates and **flair axes** (palette, trim, roof colour, porch, roof kind, chimney, dormers, shutters, window box, door colour, yard). The same file drives the Luau blockout builder and `blender/kit_from_archetype.py`, so doors, eaves and ridges line up in both. Eight archetypes: bungalow, two-storey, Victorian, ranch, split-level, cottage, apartment block, large older house [brief §3].
- **Flair rule** ("no two read the same", brief §3): `flair.seed` picks one value per axis, `flair.lock` pins any axis; **town-wide, no two houses share the same archetype-plus-flair signature** (all 11 axes) and any two houses of the same archetype differ on at least 3 axes; any two houses within 120 u (one street view) differ on at least 4 axes. The compiler re-seeds a clashing house deterministically and reports it. With 8 archetypes and 11 axes the space is far larger than the town's house count. Palettes come from the v5.4 colours [worldgen_core §6.1; worldgen_districts_art §11].
- **Backyards** (brief §3): every detached house archetype declares a backyard set (garden, bird feeder, shed, fence run, dog house, flowering bushes, washing line); each house lot gets at least 2 items by `flair.seed` unless its `yard` lists them; apartment blocks get a shared yard. Town-wide minimums keep foraging alive: at least 12 gardens, 10 feeders, 8 sheds and 6 dog houses (invariant 12). Yard items are forage sources and risks from `forage_types.json` and `YardHazards`.
- **Interior template** (`data/interiors/<name>.json`): rooms (fractional rects), doors between rooms and to outside (each with `lockable`), furniture slots with a kit category and a hide type (`behind`, `under`, `inside`), squirrel routes (counter tops, shelf tops, curtain rails), `defenderSpawn`, `burglarEntry`, `remodelSlots`. Nav waypoints (room centres, door midpoints, hide spots) are generated. Interiors sit inside the real shell; nobody teleports [worldgen_core §16]. The schema and the `Interior` builder exist from **W1** (the 4 FRB houses use them); W3 adds the other 36.
- **Indoor escape rule** (humans_actors Q4; decision 35 default): a fleeing human who gets through a lockable door ahead of the rodent may hold it shut (3 s, then the rodent can shoulder it open, a tunable); a human who reaches a hide spot while the rodent has no line of sight for 2 s is hidden, and the rodent must search (1.5 s per hide spot checked); a found human falls back to the normal duel (flinch, kick, flee); a human who reaches the back exit escapes outside; in a defender house the defender bursts out when the rodent crosses the threshold. Each step is a tunable, and `RodentLoop` runs an indoor chase to each outcome.

### 3.5 Routes and hollows

**RouteSpec** (compiled runtime record; harvested, template or linker origin):

```jsonc
{ "id": "r_00412", "name": "BUR OAK bough 3",     // name is for debugging only; behaviour never reads it
  "kind": "trunk|branch|bridge|lookout|roof|wire|fence|trampoline|hollow|ramp|tunnel|duct",
  "surface": "tree|pole|pipe|ladder|bark_inner|log|stone|cable|shingle|duct",
  "points": [[-34, 0.4, -33], [-34, 9.2, -33]],   // control points, HTML units in data
  "surfaceRadius": 1.18, "surfaceNormal": null, "visualOffset": null,
  "speedMult": 1.0,                               // v5.4 ignores route.speed; kept as a field (D8 note)
  "flags": { "autoGrab": true, "interior": false, "winterBare": false, "isolated": false },
  "lotId": "core_tree_bur_oak", "origin": "harvest|template|linker", "generator": "makeTree.trunk@L2240",
  "nodes": [ { "t": 0.35, "kind": "chamber|knothole|vent|nook", "id": "H2c1", "capacity": 40 } ] }
```

**Hollow** (`data/town/hollows.json`, **12 claimable territories** (2 premium, 1 escape tree, 9 single-chamber) plus the fallen log as a non-claimable shelter; brief v2 §3, decision 19 decided). **Claiming is proximity, not a ritual:** a deposit while inside the chamber counts; there is no scent-marking clip. Each hollow record carries the owner's `lastVisitDay`; `ForageRules.owner` holds a claim while the meter is at 70 % **and** the owner has visited within `forage.ownVisitDays` (3 in-game days); miss that and the claim lapses (the meter stays). Nuts are **finite per season**: every source has a `seasonStock` replenished at season start (§3.17 forage), and invariant 15 checks the season's total stock against the hollows' needs.

```jsonc
{ "id": "H1", "tier": "premium", "variant": "spiral", "tree": "park_outer_95", "x": 90, "z": 358,
  "girth": 2.0,                                   // premium trees are rebuilt at giant girth [wildlife_foraging §6.5]
  "asset": "hero.hollow.spiral",                  // Lane 3; blockout ring plus rails until it lands
  "chambers": [ { "id": "low", "h": 0.25, "cap": 40 }, { "id": "mid", "h": 0.55, "cap": 60 },
                { "id": "crown", "h": 0.85, "cap": 20, "lookout": true } ],
  "knotholes": [ { "h": 0.05, "bearing": 200, "chamber": "low" }, { "h": 0.88, "bearing": 30, "chamber": "crown", "exitTo": "bough:2" } ],
  "interiorRoute": { "kind": "ramp", "from": "low", "to": "crown" },
  "meter": { "capacity": 240, "ownAt": 0.70 }, "claimable": true,
  "premiumForage": ["tabasco_garden_bed_1", "feeder_premium_H1"] }
```

The escape tree (brief v2 §3, "one escape tree with three apertures and exits") is `H12`: `variant: "escape"`, one chamber, three `knotholes`, each with an `exitTo` on a different bough or the ground, asset `hero.hollow.escape` (knothole-class budget). The fallen log (`variant: "log"`, `claimable: false`) is a ground-level `tunnel` route with two exits and a mid nook, as before.

### 3.6 Roads, lanes and traffic control

- `town/districts.json`: bounds, HUD tag, map label and, new, `jurisdiction` (default `true`; the `offroad` district sets `false`, so violations, tickets, arrests and AI dispatch ignore it while the drone still sees it [brief v2 §15]) and `terrain: "v54" | "extension"`.
- `town/roads.json`: the v5.4 schema `{id, axis, coord, start, end, width, kind}` plus `class`, `speedLimit` (u/s) and a `connects` list per end; the gaps in [worldgen_core §4.3] are closed in W3. The off-road district has no roads; its drivable surface is terrain.
- Lanes (compiled from `traffic_lanes.json` and roads): `{id, road, path, dir, speedLimit, users, wrap, stops}`, one handedness (owner decision 9), opposing lanes excluded from same-lane tests (deadlock guard [traffic §6.1]).
- `town/traffic_control.json` (new; required by A2):

```jsonc
{ "junctions": [ { "id": "j_core_0_0", "at": [0, 0], "control": "stop4|signal|yield|none",
                   "stopLines": [ { "lane": "res_main_ns_nb", "s": 245.2 } ],
                   "phases": [ { "green": ["res_main_ns_nb", "res_main_ns_sb"], "secs": 18 } ] } ],
  "speedLimits": [ { "lane": "*residential*", "u_per_s": 9.0 } ],
  "parking": [ { "id": "p_core_0", "lane": "res_main_ns_nb", "s0": 120, "s1": 128,
                 "legal": true, "flags": ["hydrant", "red_curb", "driveway", "time_limit"], "limitHours": 2 } ],
  "hydrants": [[312, 23], [387, -22]],
  "violationRates": { "speeding": 0.06, "rollingStop": 0.08, "illegalPark": 0.05, "fenderBender_per_hour": 0.5 },
  "playerLaw": { "appliesTo": ["car", "cart", "pickup", "suv"], "speedingTolerance": 1.15,
                 "fines": { "speeding": 300, "rollingStop": 200, "illegalPark": 150 },
                 "cell": { "repeatOffences": 3, "hitPedestrianSecs": 90, "repeatSecs": 45 },
                 "pedestrianHit": { "knockdown": true, "ambulance": true, "admitAs": "trauma_uninfected" } } }
```

`playerLaw` (brief v2 §15 dec 14, "everyone obeys traffic law in town, police included") is evaluated by `TrafficLaw` for every player-driven kind listed: AI officers and player officers can ticket (a fine in Spicy cents and a police quest), repeat offenders sit in a cell, and an officer who hits a pedestrian loses the keys, sits in a cell and is demoted to lowest rank on release (Ladder rule); the pedestrian is knocked down, collected by an ambulance and admitted as an uninfected trauma patient. AI vehicles keep yielding to people. Bicycles are outside the law (Q8).

### 3.7 Roles ladder (`src/shared/Roles/Ladder.luau`, the only place it is stated)

```lua
--!strict
-- THE ladder. Brief v2 §4-§6, §8, §10, §11, §13, §13a, §15; Addendum A1-A2. No other module restates slots,
-- scores, transitions or the numbers they use (a Lune test fails on any ladder literal elsewhere).
local Ladder = {}

Ladder.server = { maxPlayers = 49 }               -- brief v2 §5: hard; set by the owner on the Creator Hub (OS-0);
                                                   -- invariant 20 checks the project file against this number
Ladder.humanSlots = { total = 35 }                -- brief v2 §5: 35 human-species player slots INCLUDING hospital and
                                                   -- police (decision 28, decided). Players beyond 35 are humans only
                                                   -- while squirrel, rodent, deer or fox slots are unheld (§1.5).
Ladder.rungs = {
	human    = { tier = 1, species = "human", playerSlots = "humanSlots - tier2Held", label = "Townsperson" },
	hospital = { tier = 2, species = "human", playerSlots = 5, prestige = 2.1, label = "Hospital staff" }, -- slightly above police
	police   = { tier = 2, species = "human", playerSlots = { start = 5, max = 8 }, prestige = 2.0, label = "Police" },
	squirrel = { tier = 3, species = "squirrel", playerSlots = 7 },           -- bodies float 10-14: population.json
	rodent   = { tier = 4, species = "squirrel", variant = "spicy", playerSlots = 1, aiWhenUnheld = true },
}
Ladder.subroles = {   -- devices and privileges inside a rung
	driver      = { parent = "police", slots = 2, pick = "topTwoByRank", handOver = "whenParked" },  -- A1
	drone       = { parent = "police", slots = 1, unlock = "upgrade:drone" },                       -- brief §10: "the next upgrade" at 8
	humanDriver = { parent = "human", slots = 2, pick = "topTwoByRank", handOver = "whenParked",
	                vehicles = { "pickup", "suv" }, undocumented = true },                           -- brief v2 §15: top two humans
}
Ladder.sideExits = {  -- chosen instead of a promotion; leaving returns to human at the remembered rank
	deer = { species = "deer", playerSlots = 5 },                  -- brief v2 §5: 5 deer (decision 16 amended)
	fox  = { species = "fox", playerSlots = 1, hidden = true },     -- Easter egg
}
-- 35 + 7 + 1 + 5 + 1 = 49 = maxPlayers (brief v2 §5). "35 of the 43" in §13a = 35 + 7 + 1.

-- Every number the ladder uses. The live-tuning panel mirrors this block; nothing else stores these.
Ladder.params = {
	-- human QUEUE score (brief v2 §13a: "queue rank = money plus reputation"; §6: time served; A2: kicks, quests)
	w = { time = 1.0, money = 0.02, reputation = 0.6, entourage = 3.0, kick = 15, quest = 1.0 },   -- money in Spicy Dollars
	rankGateDays = 10,                                               -- in-game days of play before a human is ranked at all (§13a)
	-- tier-2 (hospital, police) rank: performance only; money never buys a place there (§13a)
	wAdmin = { performance = 1.0, quest = 1.0, time = 0.2 },
	kickEvent = 25,                                                  -- rank points per landed kick on the rodent OR an infected squirrel (A2, §13a)
	rankClass = { minor = 4, standard = 6, major = 10 },             -- quests name a class; the ladder prices it
	rankBySpeed = { { 15, 10 }, { 30, 6 }, { 45, 3 } },              -- hospital fetch (A2)
	offerTimeout = 15, offerCascade = 3, offerRetry = 60,            -- s; candidates per opening; s between cycles
	recruitCascade = "seniority",                                    -- §13a: police recruitment passes by time served, not score
	killerHospitalIf = 0.30,                                         -- share of the town THIS rodent infected (brief §6)
	rodentReentry = 20,                                              -- s before the rodent body re-enters (AI or player)
	squirrelInfected = { nutsLostPct = 0.5, queueDrop = 2 },         -- decision 15 (accepted); applies while infected
	infectedSquirrelHealth = 100, infectedSquirrelKick = 55,         -- §13a: humans can kill infected squirrels (two kicks)
	policeSlots = { [6] = 120, [7] = 260, [8] = 450 },               -- police performance needed per extra slot (§4.9)
	jail = { hitPedestrianSecs = 90, repeatOffenceSecs = 45 },       -- §15 dec 14: cell time (real seconds)
}

-- Scores. Inputs come from RoleService.stats, Wallet and Reputation.
function Ladder.score(rung: string, s): number
	if rung == "squirrel" then
		-- brief §6: 90 % nut count, 10 % momentary stink-gland %.
		-- "Nut count" = nuts the squirrel holds NOW: stored in hollows it owns or claims + carried. Not lifetime.
		return 0.9 * (s.nuts / math.max(1, s.cohortMaxNuts)) + 0.1 * (s.stinkPct / 100)
	end
	if rung == "hospital" or rung == "police" then
		-- §13a: rank "inside that administration" by performance; money is never a term here
		local a = Ladder.params.wAdmin
		return s.adminPerformance * a.performance + s.questScore * a.quest + s.activeMinutes * a.time
	end
	-- the human queue: time served + money + reputation (+ entourage, kicks, quests); unranked before rankGateDays
	if s.activeGameDays < Ladder.params.rankGateDays then
		return -math.huge -- "unranked": shown as such, skipped by offers
	end
	local w = Ladder.params.w
	return s.activeMinutes * w.time + s.spicyDollars * w.money + s.reputation * w.reputation
		+ s.entourage * w.entourage + s.kicks * w.kick + s.questScore * w.quest
end

-- Transitions: one row per brief rule. resolve() is pure and returns { {player, toRung, rankPolicy, body?} }.
Ladder.rules = {
	{ on = "join", to = "human", rank = "lowest" },                                                   -- §4, §6; §1.5 (49 hard)
	{ on = "leave", release = true },                                                                  -- §4
	{ on = "rodent.died", who = "rodent", to = "human", rank = "lowest" },                            -- §6
	{ on = "rodent.died", who = "infectedSquirrels", to = "human", rank = "lowest" },                 -- v2 §8: infected squirrels drop
	{ on = "rodent.died", infection = "resetToNewRodent", cureHumans = "instantIfRecentOrEnRoute" },   -- v2 §8: board not wiped
	{ on = "rodent.killed", by = "human|police|driver", who = "killer",
	  to = { "squirrel:lowestUninfectedIfBodyFree", "hospital:ifRodentInfectedShareAbove(killerHospitalIf)", "police" } }, -- §6; v2 §15 (driver)
	{ on = "rodent.killed", by = "hospital", where = "inHospital", who = "killer",
	  to = "squirrel", rank = "lowestUninfected", instant = true, extraSlot = true },                  -- §6, §9; decision 15
	{ on = "squirrel.infected", who = "victim", penalty = "squirrelInfected" },                       -- §6; decision 15
	{ on = "squirrel.killed", by = "human|police|hospital|guard", who = "victim", to = "human", rank = "lowest" }, -- v2 §13a (Q6 for guards)
	{ on = "squirrel.killed", bodyRespawns = "healthyFromNest",
	  slotTo = "topRanked:hospitalThenPoliceThenHuman", offer = true },                                -- v2 §13a: hospital outranks police
	{ on = "winter.end.belowThreshold", who = "squirrel", to = "human", rank = "rememberedHuman" },   -- §12; decision 15
	-- Rodent slot (S-10): the offer goes out AT ONCE to the top squirrel; the rodent body re-enters at a sewer
	-- grate after rodentReentry. Accepted before then: the player possesses the body as it re-enters (countdown
	-- shown). Accepted later: the player swaps into the AI rodent mid-stride. Declined or timed out: the next
	-- squirrel, up to offerCascade candidates; then the AI keeps it and offers retry every offerRetry seconds.
	{ on = "slot.open", rung = "rodent", take = "topRanked:squirrel", offer = "immediate",
	  ai = "reenterAfter(rodentReentry)", cascade = "offerCascade" },                                  -- §6
	{ on = "slot.open", rung = "squirrel", take = "topRanked:hospitalThenPoliceThenHuman", offer = true }, -- decision 15, v2 §13a
	{ on = "slot.open", rung = "hospital", take = "topRanked:human", offer = true },
	{ on = "slot.open", rung = "police", take = "topRanked:human", offer = true, cascade = "recruitCascade" }, -- v2 §13a recruitment
	{ on = "police.performance.tier", offer = "police", to = "topRanked:human", cascade = "recruitCascade" }, -- v2 §13a
	{ on = "offer.sideExit", to = "deer|fox", remember = "humanRank" },                               -- §5, §11
	{ on = "sideExit.leave", to = "human", rank = "remembered" },                                     -- §6
	{ on = "kick.landed", target = "rodent|infectedSquirrel", who = "kicker", rankDelta = "kickEvent", reputation = "kick_landed" }, -- A2, v2 §13a
	{ on = "work.completed", who = "worker", pay = "fromJobOrGig", rankDelta = "rankClass" },         -- A2, §13, §13a
	{ on = "gig.completed", who = "worker", pay = "byQuality", reputation = "byQuality" },            -- v2 §13a: tip or ding
	{ on = "police.performance", unlock = "policeSlots" },                                            -- §10: 6, 7, 8
	{ on = "upgrade.bought", id = "drone", requires = "policeSlots=8", unlock = "drone" },             -- §10, §13
	{ on = "traffic.hitPedestrian", by = "police", keys = "revoke", jail = "hitPedestrianSecs",
	  then_ = { to = "human", rank = "lowest" } },                                                     -- v2 §15 dec 14
	{ on = "traffic.repeatOffence", by = "any", jail = "repeatOffenceSecs" },                          -- v2 §15 dec 14; not in offroad
	{ on = "infection.criticalMass", who = "rodentPlayer", winner = true, cinematic = true },           -- §8 (D17, D31)
	{ on = "cinematic.finished|everyoneInfected", all = true, to = "human", rank = "lowest", reset = true,
	  except = { "winnerKeepsRodent", "infectedSquirrelsAliveKeepSquirrel" } },                        -- §8 (D17); v2 §13a
}

function Ladder.resolve(event, ctx) --> { Transition }
	-- table-driven; one unit test per row (tests/unit/Ladder.spec.luau)
end
return Ladder
```

**Offers.** When a slot opens, the top-ranked eligible player sees **Accept / Deer instead / Fox instead / Stay as I am** with a `params.offerTimeout` timeout. **Police recruitment** (brief v2 §13a) is the same offer, sent when police performance crosses a tier to the top-ranked regular human and, if declined, passed on **by seniority** (time served), not by score. Unranked players (fewer than `rankGateDays` in-game days of play) see "unranked" on the HUD and are skipped by offers. A player can switch on "don't offer me promotions" (free roam, A2); such players are skipped, and staying human past the 35 target simply leaves them ordinary townspeople (§1.5). The Role Lab's `forceRole` reads the same rung table and logs when it exceeds a cap; the Lab never edits the ladder.

### 3.8 Tunables (`src/shared/Config/Tunables.luau`)

One nested table; each leaf carries `v`, `unit` and `src`. `Tunables.get` returns studs for length units. In Studio and for dev UserIds every leaf is mirrored to an attribute on `ReplicatedStorage.TunablesLive`; changing it during a playtest takes effect immediately, and the Lab's **Export tuning** button prints a diff for Claude to commit.

```lua
return {
	clock = { realSecondsPerDay = { v = 72, unit = "s", src = "brief v2 §15 dec 10 (decided)" },
	          weeksPerCycle = { v = 6 }, winterWeek = { v = 6 }, lunarMonthDays = { v = 29.53 },
	          dayCurve = { v = { night = 0.20, sunrise = 0.10, goldenAm = 0.12, day = 0.30, goldenPm = 0.12, sunset = 0.10, blue = 0.06 } } },
	squirrel = { walk = { v = 8.0, unit = "u/s", src = "routes §8.1" }, sprint = { v = 16.8, unit = "u/s" },
	             stalk = { v = 1.65, unit = "u/s" }, gravity = { v = 30, unit = "u/s2" },
	             leapFwd = { v = 16.5, unit = "u/s" }, leapUp = { v = 12.8, unit = "u/s" },
	             grabRadius = { v = 3.4, unit = "u" }, maxTransferGap = { v = 3.15, unit = "u" },
	             autoSwitch = { v = 0.48, unit = "u" }, explicitTransfer = { v = 1.7, unit = "u" },
	             shoulderHeight = { v = 1.2, unit = "st", src = "brief §2; decision 8" },
	             chaseLockRange = { v = 30, unit = "u", src = "brief v2 §8: forward-locked camera while chasing a squirrel" } },
	pounce = { cooldown = { v = 0.7, unit = "s" }, window = { v = 0.78, unit = "s" },
	           windup = { v = 0.12, unit = "s", src = "brief §8 (new)" }, recovery = { v = 0.35, unit = "s" },
	           contactHuman = { v = 1.38, unit = "u" }, chanceUnaware = { v = 0.955 }, chanceAware = { v = 0.035 } },
	rodent = { maxHealth = { v = 100 }, kick = { v = 55 }, baton = { v = 50 }, shove = { v = 40 }, defenderMult = { v = 1.5 },
	           -- brief v2 §8, §15 dec 12 (decided): drain and heals are the main recovery paths; regen lowered (D33)
	           drainPerDay = { v = 1, unit = "hp/game day", src = "brief v2 §8" },
	           healOnBite = { v = { human = 10, squirrel = 20 }, unit = "hp", src = "brief v2 §8" },
	           regenStalk = { v = 0.25, unit = "hp/s", src = "D33" }, regenHollow = { v = 1, unit = "hp/s", src = "D33" },
	           iFrames = { v = 0.6, unit = "s" },
	           fallDamage = { v = 0, src = "routes Q7; v5.4 has none" }, biteDanceEvery = { v = 10, src = "squirrel_abilities §10" },
	           chiliRushSecs = { v = 12, unit = "s" }, chiliRushSpeed = { v = 1.25 },
	           waterGunStunSecs = { v = 1.3, unit = "s", src = "brief v2 §13a; once per player (Q11)" } },
	alert = { -- brief v2 §8: bite aftermath
	          radiusU = { v = 40, unit = "u" }, ttl = { v = 90, unit = "s" },
	          kickMult = { v = 1.25, src = "hidden strength boost; must stay below 1.82 (D33)" },
	          swingBias = { v = 2.0, src = "response weights toward swing/kick" },
	          bitePenalty = { v = 0.05, src = "second bite near a fresh one is close to impossible" },
	          policeChaseBlocks = { v = 2 }, policeLeashBlocks = { v = 5 }, blockLenU = { v = "measured from roads.json", src = "Q16" } },
	power = { -- brief v2 §15 table, verbatim v5.4 (squirrel_abilities §12); real ACTIVE seconds, never the game clock (rule 11)
	          bitePerson = { v = 100 }, bitePersonHigh = { v = 150 }, highAboveGroundU = { v = 1.6, src = "v5.4 uses absolute Y > 4; Q23" },
	          biteOfficer = { v = 130 }, convertSquirrel = { v = 90 }, batonHit = { v = -19 }, pedestrianKick = { v = -19, src = "v5.4 same function; Q23" },
	          catHit = { v = -12 }, fadeAfterActiveMin = { v = 10 }, fadePct = { v = 0.15, src = "rounded up; repeats" },
	          stages = { v = { feral = 0, rabid = 600, super = 1500 } }, hudMax = { v = 1500 } },
	human = { spotRange = { v = 14.5, unit = "u" }, kickReach = { v = 2.65, unit = "u" }, kickWindup = { v = 0.58, unit = "s" },
	          vigilanteShare = { v = 0.08, src = "brief §8" }, crouchHeightMult = { v = 0.6, src = "paintball crouch" },
	          reportRange = { v = 25, unit = "u", src = "true sighting report (v2 §13a)" } },
	infection = { squirrelSharePer = { v = 25 / 7 }, squirrelShareCap = { v = 25 }, matureSecs = { v = 1500 },
	              criticalTown = { v = 50 }, criticalStaffFrac = { v = 0.5 }, criticalPatientFrac = { v = 0.5 },
	              infectedStaffCureMult = { v = 1.5 }, recentBiteSecs = { v = 60, src = "cured instantly on rodent death if bitten within (v2 §8)" },
	              newRodentPct = { v = 0.5, unit = "%", src = "v2 §8: infection resets to the new rodent alone" } },
	outbreak = { cinematicSecs = { v = 25, unit = "s", src = "D31" }, clockRateMult = { v = 40 }, sweepSpeedRamp = { v = { 1.0, 3.0 } },
	             overcastRampS = { v = 8 }, nightFadeS = { v = 6 } },
	hospital = { disinfectSteps = { v = { 1.2, 0.8, 1.2 }, unit = "s" }, fetchTimeout = { v = 45, unit = "s" }, wrongItemPenalty = { v = 10, unit = "s" },
	             aiStaffSpeedMult = { v = 0.7, src = "v2 §5: player staff are faster" } },
	police = { batonWindup = { v = 0.5, unit = "s" }, carMaxSpeed = { v = 16, unit = "u/s" }, radarRange = { v = 48, unit = "u" } },
	drone = { maxAlt = { v = 160, unit = "u" }, speed = { v = 24, unit = "u/s" }, markHold = { v = 0.6, unit = "s" },
	          markRange = { v = 100, unit = "u" }, markSecs = { v = 12, unit = "s" }, markCooldown = { v = 20, unit = "s" },
	          vigilanteRadius = { v = 60, unit = "u" }, deerStartleAlt = { v = 24, unit = "u" } },
	traffic = { tickHz = { v = 30 }, posesHz = { v = 15 }, sweptPad = { v = 0.18, unit = "u" }, yawStep = { v = 0.05, unit = "rad" },
	            teleportSkip = { v = 12, unit = "u" }, sedanBox = { v = { 2.35, 4.45, 2.04 }, unit = "u" },
	            cartMaxSpeed = { v = 7, unit = "u/s" }, bikeMaxSpeed = { v = 9, unit = "u/s" }, jetSkiMaxSpeed = { v = 20, unit = "u/s" },
	            speedingTolerance = { v = 1.15, src = "player law (v2 §15)" } },
	forage = { carryMax = { v = 9, src = "brief v2 §3" }, hollowCapacity = { v = 120 }, premiumMult = { v = 2 }, ownThreshold = { v = 0.70 },
	           ownVisitDays = { v = 3, unit = "game days", src = "brief v2 §3: visit every three in-game days or the claim lapses (Q2)" },
	           seasonStockMargin = { v = 1.5, src = "invariant 15" },
	           stinkFillPerMin = { v = 1.2 }, stinkFireMin = { v = 95 }, stinkCost = { v = 30 },
	           stinkRepelRadius = { v = 8, unit = "u" }, stinkRepelSecs = { v = 4, unit = "s" } },
	economy = { minWageCentsPerHour = { v = 2, src = "brief v2 §13a" }, robuxToCents = { v = 400, src = "about 1 R$ = 4 S$" },
	            paintballPassCents = { v = 20 }, paintballPassDays = { v = 5, unit = "game days", src = "Q2" }, garbSetCents = { v = 100 } },
	reputation = { votesPerDay = { v = { up = 5, down = 5 }, unit = "per game day", src = "v2 §13a (Q2)" }, voteWeightClamp = { v = { 0.25, 1.5 } },
	               cafeTickPerHour = { v = 1 }, rankGateDays = { v = "Ladder.params", src = "ladder number; not here" } },
	paintball = { projectileSpeed = { v = 90, unit = "st/s" }, drop = { v = 9.8 }, magazine = { v = 5 }, lagHistorySecs = { v = 1.0 },
	              matchSecs = { v = 480 }, teamSize = { v = { 4, 8 } }, sprintMult = { v = 1.4 } },
	minigames = { inputDelayBudgetMs = { v = 120, src = "S13 pass bar" }, jengaBlocks = { v = 54 }, dartsWobble = { v = 0.04 },
	              labyrinthTiltDegPerS = { v = 25 } },
	lighting = { enableRadius = { v = 180, unit = "st" }, flickerFraction = { v = 0.07 }, maxRealLights = { v = 300, src = "S17" } },
	interior = { doorHold = { v = 3, unit = "s" }, hideNoSight = { v = 2, unit = "s" }, searchPerSpot = { v = 1.5, unit = "s" } },   -- decision 35 (accepted)
	recovery = { safeHistory = { v = 3, unit = "s" }, riverToQuay = { v = true, src = "worldgen_districts_art §16" } },
	policeCoord = { tier2Pair = { v = true }, cutoffLookahead = { v = 30, unit = "u" }, perimeterPoints = { v = 3 } },
	-- Ladder numbers (score weights, kick reward, offer timeout, 30 % rule, re-entry delay, police slots, rank gate, jail) live in Ladder.params.
	ai = { thinkHz = { v = { near = 10, mid = 4, far = 1 } }, lodNear = { v = 150, unit = "st" }, lodMid = { v = 500, unit = "st" }, budgetMs = { v = 4 },
	       arenaBudgetMs = { v = 1.5, src = "S18" } },
	avatar = { maxSat = { v = 0.55 }, valRange = { v = { 0.39, 0.91 } }, furTintCap = { v = 0.30, src = "animals only (Addendum B1)" }, skinTones = { v = 8 } },
}
```

### 3.9 Quests and jobs

**Jobs** live on lot types (`jobs: [{socket, job, centsPerHour, cycleS, role}]`, §3.3; pay is in Spicy cents per in-game hour, minimum 2, brief v2 §13a). **Quests** are data in `data/quests/quest_types.json`; `QuestService` spawns them from simulation events, offers them to eligible roles, tracks steps with `QuestTypes.nextStep`, and pays Spicy Dollars and rank through `Ladder` (`work.completed`). No quest is mandatory [A2]. **Gigs** (rev 3) are quest types with a `gig` block: a 0-1 quality trace, a tip at `>= 0.9` and a reputation ding below `0.4`; **NPC posts** (`source: "npc.post"`) appear on the park billboard and the station poster and pay coins; **mischief responses** (`source: "mischief.report"`) are police quests spawned by the Mischief service; **player violations** (`source: "traffic.player.*"`) are the same ticket quests with a player as the target.

```jsonc
[
  { "type": "parking_ticket", "roles": ["police"], "source": "traffic.illegalPark",
    "spawn": { "perGameHour": 1.5, "maxConcurrent": 3 },
    "steps": [ { "verb": "goto", "target": "$vehicle", "within": 6 },
               { "verb": "ticket", "target": "$vehicle", "prompt": "Write ticket", "hold": 2.0 } ],
    "ttl": "2h", "reward": { "credits": 15, "rankClass": "minor" }, "fail": { "on": ["ttl", "vehicleLeft"] },
    "marker": { "layer": "quest", "icon": "ticket" } },
  { "type": "speeding_ticket", "roles": ["police:driver"], "source": "radar.overLimit",
    "steps": [ { "verb": "follow", "target": "$vehicle", "within": 20 }, { "verb": "siren", "target": "$vehicle", "pullOver": true },
               { "verb": "ticket", "target": "$vehicle", "prompt": "Issue ticket", "hold": 2.0 } ],
    "ttl": "1h", "reward": { "credits": 25, "rankClass": "standard" } },
  { "type": "petty_argument", "roles": ["police"], "source": "community.pairArgument",
    "steps": [ { "verb": "goto", "target": "$pair", "within": 5 },
               { "verb": "choose", "options": ["calm_a", "calm_b", "separate"], "correct": "$pair.mood" } ],
    "reward": { "credits": 12, "rankClass": "minor" } },
  { "type": "hospital_fetch", "roles": ["hospital"], "source": "hospital.request",
    "spawn": { "perGameHour": 4, "maxConcurrent": 2 },
    "steps": [ { "verb": "pick", "target": "$item", "from": "pharmacy|supply" }, { "verb": "deliver", "target": "$bay", "within": 4 } ],
    "timer": 45, "wrongItem": { "timePenalty": 10, "score": -5 },
    "reward": { "credits": 20, "rankClass": "bySpeed" } }
]
```

The full catalogue adds `stop_sign_ticket` (`traffic.rollingStop`), `fender_bender` (inspect both cars, talk to both drivers, file), `burglar` (`community.breakIn`; catch before escape), `disinfect` (`hospital.admit`), shop work, the **gigs** `gig_mow` (house lots with lawns; the mower prop; quick), `gig_delivery` (pick up at a restaurant, deliver to a home within a timer, by bike or cart), `gig_sign` (a rhythm-and-hold verb at a storefront socket), `gig_wash` (driveways and the gas station), `gig_paper` (a morning route of houses, a throw verb, server porch-hit detection with the porch bonus) and `gig_serve` (steakhouse table sockets), the **NPC posts** `walk_dog` and `lost_pet` (pets from `PetService`), `mischief_response` (police: find the culprit, fine or warn; Q7) and the player-target ticket quests. Hospital items are `data/hospital/items.json`: `{id, name, kind: medicine|instrument, color, icon, shelf, requestWeight}` (about 8 medicines and 6 instruments). Quest rewards name a `rankClass`; the points come from `Ladder.params` (§1.1 rule 2).

```jsonc
{ "type": "gig_mow", "roles": ["human"], "source": "lot.lawn", "spawn": { "perGameHour": 6, "maxConcurrent": 8 },
  "steps": [ { "verb": "take", "target": "$mower" }, { "verb": "mow", "target": "$lawn", "coverage": true } ],
  "gig": { "quality": "coverage*timeFactor", "pay": 40, "tipAt": 0.9, "tip": 20, "dingBelow": 0.4, "ding": "minor" },
  "ttl": "3h", "reward": { "rankClass": "minor" } }
```

**Performance metrics** (both rolling over the last 2 in-game days, recomputed at 1 Hz, visible on each building's board):

- **Hospital performance** = speed of disinfection [brief §9]: the median admit-to-cure time against a par of 3 in-game hours, scaled 0-100, plus 2 points per correct fetch and minus 3 per wrong item. Tiers at 40 / 65 / 85 unlock station upgrades for purchase and raise staff rank through `work.completed`.
- **Police performance** [brief §10]: 30 per rodent kill by an officer, 10 per baton hit, 5 per sighting reached within 60 s, the quest points of every completed police quest (tickets, arguments, fender benders, burglars caught), minus 10 per burglar who escapes and minus 5 per bite within 30 u of an idle officer. `Ladder.params.policeSlots` turns it into officer slots 6, 7 and 8 (performance only, as the brief says), and the same three thresholds are the police upgrade tiers 1-3; slots never close again during the server's life.

**Station upgrades** (`data/upgrades/upgrades.json`; brief §9, §10, §13; A2 "credits buy upgrades"; costs now in Spicy cents, D26). Each building has an **upgrade board** (hospital staff room, police briefing room). Upgrades become *available* at a performance tier and are *bought* with Spicy Dollars: any player in that building's role may contribute to a pooled building fund, and the purchase applies to the whole building for the server's life (D14). Money never buys a place in the hospital or police ranks themselves (brief v2 §13a).

```jsonc
[ { "id": "h_fast_station", "building": "hospital", "tier": 1, "cost": 300, "effect": { "disinfectStepMult": 0.85 } },
  { "id": "h_second_bed", "building": "hospital", "tier": 2, "cost": 600, "effect": { "bedsPerStation": 2 } },
  { "id": "h_sanitiser", "building": "hospital", "tier": 2, "cost": 500, "effect": { "infectedStaffCureMult": 1.25 } },
  { "id": "h_shelf_labels", "building": "hospital", "tier": 1, "cost": 250, "effect": { "fetchHighlight": true } },
  { "id": "h_ambulance_radio", "building": "hospital", "tier": 3, "cost": 900, "effect": { "ambulanceDispatchMult": 0.7 } },
  { "id": "p_radar_range", "building": "police", "tier": 1, "cost": 300, "effect": { "radarRangeMult": 1.5 } },
  { "id": "p_ticket_book", "building": "police", "tier": 1, "cost": 250, "effect": { "ticketHoldMult": 0.6 } },
  { "id": "p_posters", "building": "police", "tier": 2, "cost": 500, "effect": { "posterSightings": true } },
  { "id": "drone", "building": "police", "requires": "policeSlots=8", "cost": 1200, "effect": { "unlock": "drone" } } ]
```

### 3.10 Map markers and sightings

Layers and their audiences are data, not code:

```jsonc
// data/map/markers.json
{ "sighting":  { "audience": ["police", "drone"], "ttl": 60, "fade": "linear", "rateLimitPerSourceSecs": 10, "icon": "eye" },
  "bite":      { "audience": ["police", "drone", "hospital"], "ttl": 90, "icon": "tooth" },
  "droneMark": { "audience": ["police", "drone"], "ttl": 12, "precise": true, "outline": true },
  "quest":     { "audience": "$assignee" },
  "job":       { "audience": ["human"], "static": true },
  "home":      { "audience": "$owner" },
  "hollow":    { "audience": ["squirrel", "rodent"], "showOwner": ["squirrel"] },   // the rodent sees hollows to rest in, not owners
  "patient":   { "audience": ["hospital"] },
  "car":       { "audience": ["police"] },
  "gig":       { "audience": ["human"], "static": true },                 // lawns, restaurants, storefronts, the paper route
  "post":      { "audience": ["human"], "static": true },                 // the park billboard and the station poster
  "mischief":  { "audience": ["police"], "ttl": 120, "icon": "egg" },
  "violation": { "audience": ["police"], "ttl": 90, "icon": "car" } }   // player vehicles over the limit or through a stop
```

Runtime marker record (server to client deltas, studs):
`{ id, layer, x, z, t0, ttl, conf (0-1), src: "ai_spot|witness|bite|drone|poster|bark", railHint: "ground|wire|roof|tree"?, label? }`.
Sources: every `spotted` transition (with the concealment terms), bite resolution, witness alarm at crime scenes, a yard dog's bark, poster recognition (one per human per 10 s) [humans_actors §14 item 12], drone marks, and (rev 3) a human player's **Report** verb: true if the rodent is within `reportRange`, which feeds the sighting layer and raises reputation; a false report costs a little reputation [brief v2 §13a]. Police and the drone see everything; hospital staff see bite locations only; markers fade after about a minute (dec 13 decided). The full-screen map image is rendered from the compiled data by `tools/textures` and uploaded headlessly; markers are drawn over it.

### 3.11 Asset manifest (`data/assets/manifest.json`)

```jsonc
"rig.squirrel": {
  "lane": 3, "status": "puppet",                 // puppet | blockout | v1 | final
  "moderation": null,                            // pending | approved | rejected (F-9); not approved -> fallback
  "fallback": "puppet.squirrel",                 // Lune-built placeholder in assets/
  "modelAssetId": null, "packageId": null, "version": null,
  "contract": "RigSpec.squirrel",                // bones, sockets, regions, clip names, budgets
  "budget": { "tris": 13000, "bones": 36, "maps": 1024 },
  "source": { "blend": "blender/squirrel/squirrel.blend", "fbx": "blender/squirrel/export/squirrel_rig.fbx", "sha": "..." },
  "clips": { "Run": null, "Climb": null, "Wire": null, "Leap": null, "Pounce": null, "BiteDance": null, "Sneak": null }
}
```

`AssetService.template(name)` always returns the best available **approved** version (final, then v1, then blockout, then puppet); a pending or rejected upload never renders blank. Puppets share the final bounding box, sockets, region names and clip names, so gameplay never changes when art lands. A dev toggle tints remaining placeholders magenta.

### 3.12 Other data files

| File | Record shape |
|---|---|
| `cast/*.json` | `{id, name, role, homeLot?, personality: wary\|panic\|brave\|bluster, nerve 0-1, look: {body, skinTone, outfit, accessory}, schedule?, possessable, src}` from `human_cast.json` (87) [humans_actors §1-§3] |
| `forage/forage_types.json` | `{kind, yield: [min, max], cooldown, carry, winterMult, risk: {trigger, radius, effect}}` [wildlife_foraging §14] |
| `wildlife/*.json` | the spec file re-keyed: hollows, nut caches (cache 4 moved), deer herd, fox spawn, 95 trees, 12 apple trees, 24 nests, birds, 30 insects |
| `buildings/hospital.json` | room programme (reception, triage, Ward A, Ward B, isolation, pharmacy, staff room, supply, ambulance bay, roof hatch), 10 stations, shelves with item slots, the 7-node duct as a `duct` route with the hatch over an aisle [hospital_police_infection verifier 1] |
| `buildings/police_station.json` | lobby, briefing (quest board), lockers, dispatch/radar room, 2 cells, drone console and roof pad, garage (2 player cars, 2 AI cruisers), upgrade board |
| `blend/*.json` | palette clamps; Studio test avatar samples as HumanoidDescription data; `item_colours.json`, a curated table from common catalogue item names and IDs to colours (the A3 fallback when `GetProductInfo` gives nothing) |
| `cast/population.json` | posts, standing bodies, AI floors (normal and at the hard cap; police >= 6, hospital >= 10, ambulance crews, guards, bartenders), reserve, hard cap, squirrel float 10-14, deer bodies 6 (§1.5) |
| `economy/prices.json`, `wages.json`, `products.json` | §3.14: item and consumable prices in cents; job wages in cents per in-game hour; developer products with Roblox IDs and Spicy-Dollar grants |
| `items/items.json` | §3.14: the 22 corner-store items, prices and effects |
| `reputation/rules.json` | §3.15: event deltas, vote weights, cafe tick, entourage term |
| `minigames/<game>.json`, `rides/<ride>.json`, `paintball/*.json` | §3.16: definitions on the frameworks |
| `vehicles/kinds.json`, `vehicles/placements.json` | §3.18: motor parameters and interiors per kind; where the 6 pickups, 4 SUVs, carts and bikes stand |
| `town/lighting.json` | §3.19: lamp rule per block, porch and shop-front lights, flicker fraction, client radius |
| `persistence/profile.schema.json` | §3.20: the DataStore profile |
| `town/terrain_extensions.json` | D32: authored height patches outside the v5.4 rectangle (hill, ridge, back field, long beach) |
| `speech/taunts.json`, `speech/fortunes.json`, `content/exhibits.json`, `content/books.json` | the 20 taunt lines and the rewritten v5.4 lines (mild, dec 24), the fortune machine's lines, museum exhibits and the clinic's two picture books (procedurally written and drawn; Q15) |
| `cast/events.json` | living-community events (barbecue at (-66,-84), softball at (66,356), 2,400 s cycle) [humans_actors §9.3]; argument pairs; break-in candidates |
| `upgrades/upgrades.json` | the station-upgrade catalogue (§3.9) |
| `outfits/*.json` | per role: texture set per body type on the shared UVs, accent zones, props (D22) |
| `town/concealment.json` | garden, hedge and shrub concealment volumes with their `spotted` multipliers [wildlife_foraging verifier 1] |
| `town/secrets.json` | the 8 hidden chili peppers, the fashion stand, the wishing fountain and Galleria coin spawns [squirrel_abilities §12-§15; worldgen_districts_art §4.6] |
| `harvest_patches.json` | each harvested route that is corrected, dropped or temporarily locked, with the reason and spec citation (§4.4) |

### 3.13 Compiler invariants (CI fails on any)

1. Every lot validates against its type's `paramSchema`; IDs unique; no footprint overlap except declared children; inside the world clamp.
2. Every lot front faces a road unless it declares a reason (fixes the outer-home inversion [worldgen_core §18.2]). Until W3b #8 rebuilds them with template routes, the 20 outer homes declare `reason: "harvest_lock"` and keep their v5.4 orientation, so their harvested routes still sit on their greybox (§4.4 patch list); from W3 that reason is rejected.
3. Exactly **40** claimable homes with interiors; exactly **3** defenders (two older housewives of different appearance with rolling pins, one man with a broom).
4. **Restaurants roughly doubled:** the v5.4 baseline is the 9 food businesses with signs (4 core food lots [worldgen_core §15], 4 Quay food facades: The Old Anchor, Copper Kettle, The Tea Room, Willow Bakery; the Galleria's Copper Cup Café), so at least **18** food businesses town-wide, at least **10** of them enterable restaurant lots, covering all **8** kinds, each restaurant with seating or a dumpster socket; all 13 named new lot types present (barber, music, hardware, laundromat, bookshop, pet store, gas station, corner grocery, school with playground, church, park with gazebo, community garden, marina); every lot type has a forage table and a risk value [brief §3].
5. Exactly **12** claimable hollows (2 premium, 1 escape with three knotholes and exits, 9 single-chamber) plus the non-claimable log; each premium hollow has a premium garden and a premium feeder within 40 u [brief v2 §3, §7].
6. Every pole at least 0.95 u from pavement [worldgen_core §16]; no route shorter than 0.04 u, with a non-finite point or fewer than 2 points [routes_movement §1.1].
7. Route connectivity: largest island at least 563 routes; every hollow, the hospital roof and every new roof reach the main network or are listed as intended leap-only islands.
8. Car lane graph strongly connected; every lot with parking or a driveway connects to a lane; deadlock guard on opposing lanes.
9. Nav graph connected: every interior, hide spot, back exit, job socket and hospital or police room reachable.
10. Per-district budgets (instances, triangles from manifest budgets, SurfaceGui count) and the flair-distinctness rule, **town-wide** (§3.4).
11. **Population** (§1.5): standing bodies >= 35 + the normal AI floors; police floor >= 6 and hospital floor >= 10 with ambulance crews on a separate post (brief v2 §5); hard cap − hard-cap floors >= 49; standing + reserve <= hard cap; every job site with staff has a post and a floor; squirrel float 10-14; deer bodies >= 5.
12. **Backyards:** every detached house has at least 2 backyard items; town-wide at least 12 gardens, 10 feeders, 8 sheds and 6 dog houses (§3.4).
13. **Ladder literals:** no slot count, score weight, rank reward or ladder threshold appears outside `Ladder.luau` (a scan of `src/` and `data/`).
14. **No captures in the build:** no project file maps `art_captures/`; the place test also rejects SurfaceAppearance (§6.4).
15. **Finite nuts** (brief v2 §3): the season's total `seasonStock` over every source is at least 1.5 x the sum of every hollow's 70 % threshold, and the winter multiplier leaves at least the survival threshold reachable for 10 squirrels.
16. **Attractions present** (brief v2 §13a): corner store (22 shelf items, checkout counter), doctor's office (receptionist, books, bead maze, labyrinth), museum, bowling alley (6 lanes with `tunnel` routes to the rack, 3 pinball, 2 pool, 1 bumper pool, dartboard, fortune machine, back of house), racquetball court, steakhouse (glass in `SquirrelBlocked`, volleyball net, Jenga table), jet-ski and parasail stands, the sky lift with a hilltop restaurant, the TV station (5 floors, stairwells, atrium), both lounges, the small mall with the wind tunnel, the antique store; 2 tree houses with Humanoid ladders and squirrel routes to the floor; at least 3 trampolines; the park billboard and the station poster.
17. **Vehicles placed** (brief v2 §15): exactly 6 pickups and 4 SUVs parked in town, at least 4 golf carts (2 at the park, 2 at the station) and 6 bicycles; every player-enterable kind has an interior template with a dashboard socket (`DashSocket`) and a camera eye socket.
18. **Lighting** (brief v2 §15): at least one lamp per block side on every road in town, a porch light on every house, an emissive front on every open business; the flicker set is 5-10 % of lamps; every lamp has a Skyline emissive head.
19. **Jurisdiction**: every lot and lane lies in a district with `jurisdiction: true`; the `offroad` district has no lots, lanes or stop lines, and its terrain is reachable from the town by at least two drivable slopes.
20. **Ladder arithmetic**: 35 + 7 + 1 + 5 + 1 = 49 = `Players.MaxPlayers` in the project file; `humanSlots.total = 35`; no "50" anywhere in `src/` or `data/`.

### 3.14 Economy, prices and items (`data/economy/*.json`, `data/items/items.json`; brief v2 §13a)

```jsonc
// economy/wages.json: Spicy cents per in-game hour; the minimum is the brief's 2
{ "minimum": 2, "jobs": { "cashier": 2, "barber_cut": 4, "restock": 3, "hospital_shift": 6, "police_shift": 6 },
  "aiStaffSpeedMult": 0.7 }                         // AI staff are slower; player staff are faster and earn bonuses
// economy/prices.json: cents
{ "coffee": 12, "nachos": 5, "hot_cocoa": 10, "green_tea": 8, "snow_cone": 6, "jetski_rental": 50,
  "paintball_pass": 20,                              // five in-game days of arena and lounge access
  "paintball_garb_set": 100,                         // one Spicy Dollar per set, kept permanently
  "wind_tunnel_balls": 15 }                          // adds 10 balls for whoever is in the tunnel
// economy/products.json: developer products the owner creates on the Creator Hub (Q19); IDs wired by Claude
[ { "productId": null, "robux": 25, "cents": 10000, "label": "100 Spicy Dollars" },
  { "productId": null, "robux": 100, "cents": 40000, "label": "400 Spicy Dollars" },
  { "productId": null, "robux": 400, "cents": 160000, "label": "1,600 Spicy Dollars" } ]
// items/items.json: the corner store's 22 shelf items, each functional (prices from the brief, in cents)
[ { "id": "water_gun", "price": 6, "effect": "squirt", "npcReaction": "wet", "easterEgg": { "rodentStunSecs": 1.3, "oncePer": "player" } },
  { "id": "frisbee", "price": 5, "effect": "throw", "physics": "client_owned_while_held" },
  { "id": "football", "price": 6, "effect": "throw" }, { "id": "bubbles", "price": 3, "effect": "vfx" },
  { "id": "chalk", "price": 2, "effect": "write", "letters": 20, "filter": "TextService" },
  { "id": "flashlight", "price": 6, "effect": "spotlight", "nightOnly": true }, { "id": "umbrella", "price": 5, "effect": "cosmetic" },
  { "id": "peanuts", "price": 4, "effect": "bait", "lures": "one_squirrel" }, { "id": "bird_seed", "price": 40, "effect": "bait", "lures": "squirrels_and_birds" },
  { "id": "dog_treats", "price": 4, "effect": "calm_dog" }, { "id": "newspaper", "price": 2, "effect": "read_and_throw" },
  { "id": "camera", "price": 6, "effect": "screenshot", "api": "CaptureService" }, { "id": "duct_tape", "price": 4, "effect": "patch_bandage" },
  { "id": "whoopee_cushion", "price": 15, "effect": "seat_trap" }, { "id": "harmonica", "price": 5, "effect": "sound" },
  { "id": "air_horn", "price": 5, "effect": "startle", "radius": 12 }, { "id": "soda", "price": 4, "effect": "stamina" },
  { "id": "ice_cream_bar", "price": 5, "effect": "stamina" }, { "id": "lawn_chair", "price": 6, "effect": "place_seat" },
  { "id": "radio", "price": 8, "effect": "playlist", "source": "library" }, { "id": "bike_horn", "price": 3, "effect": "sound" },
  { "id": "kite", "price": 60, "effect": "ride", "ride": "kite", "zones": ["park", "beach"] } ]
// header: "No lottery or gambling items. Prices are the brief's; everything is cheap except bird seed and the kite."
```

The effects marked undefined by the brief (duct tape, umbrella, soda, ice cream, newspaper, peanuts versus seed) carry the Q13 defaults and are one-line data changes. Receipts: `{ purchaseId, productId, playerId, cents, grantedAt }`, appended to the profile's ledger inside `ProcessReceipt` before `PurchaseGranted` is returned; a repeated `PurchaseId` returns `PurchaseGranted` without crediting again.

### 3.15 Reputation (`data/reputation/rules.json`; brief v2 §13a)

```jsonc
{ "range": [-100, 100], "start": 0,
  "events": { "gig_tip": 2, "gig_bad": -1, "rescue": 6, "true_report": 3, "false_report": -1, "lost_pet_returned": 5,
              "cafe_seat_per_game_hour": 1, "mischief_seen_by_npc": -1, "kick_landed": 4 },
  "votes": { "perGameDay": { "up": 5, "down": 5 }, "targets": "players",            // Q21: players only by default
             "base": 2, "weight": "clamp(0.25 + voterRep / 100, 0.25, 1.5)", "sameTargetCooldown": "day" },
  "npcLiking": { "funRadius": 20, "likeThreshold": 3, "followDistance": 6, "dropOffAfter": "2h", "maxCompanions": 4 },
  "humanScore": { "wReputation": 0.6, "wEntourage": 3.0 } }                           // read by Ladder.params, not restated
```

Reputation is two-sided: NPC liking (companions who pal around or follow; a bigger entourage raises rank) and player votes weighted by the voter's own reputation to blunt brigading. It persists in the profile (D26) unless the owner answers Q-rep "per server" (§8 item 41).

### 3.16 Minigame, ride and paintball definitions (`data/minigames/*.json`, `data/rides/*.json`, `data/paintball/*.json`)

```jsonc
// minigames/bowling.json: content on the Minigame framework; rules in Minigames/MinigameRules/Bowling.luau
{ "game": "bowling", "class": "shared_table", "authority": "$S13",   // server | shooter_client_per_turn (chosen by S13)
  "seats": 4, "turns": true, "controls": { "angle": "mouse_x", "power": "hold_release" },
  "physics": { "pins": 10, "ball": { "mass": 6, "radius": 0.9 }, "ballReturn": "rack_tunnel" },
  "scoring": "ten_frames", "scoreboard": "overhead", "lab": ["strike", "split", "gutter"], "ironOut": true }
{ "game": "darts", "class": "shared_table", "authority": "server_deterministic",
  "controls": { "aim": "mouse_point", "power": "timing_meter", "wobble": 0.04 }, "modes": ["501", "cricket"], "ironOut": true }
{ "game": "pinball_a", "class": "no_stakes", "authority": "client", "theme": "riverside", "flippers": 2, "sanity": { "maxScorePerSec": 5000 }, "ironOut": true }
{ "game": "tilt_labyrinth", "class": "no_stakes", "authority": "client",
  "controls": { "forward": "W", "back": "S", "right": "Up", "left": "Down" }, "fixedControls": true, "ironOut": true }
{ "game": "giant_jenga", "class": "shared_table", "blocks": 54, "controls": { "pull": "drag", "place": "drop" }, "ironOut": true }
{ "game": "fortune_machine", "class": "no_stakes", "authority": "server", "money": "none", "lines": "speech/fortunes.json",
  "styling": "fortune_teller_cabinet" }                                 // Q20: never fruit reels
// rides/sky_lift.json: no controls, no score; camera first person on boarding
{ "ride": "sky_lift", "kind": "cable", "from": "lot:skylift_base", "to": "lot:restaurant_hilltop", "cabins": 6, "speed": 6, "camera": "firstPerson" }
{ "ride": "parasail", "kind": "towed_spline", "zone": "beach", "durationS": 90, "camera": "firstPerson" }
{ "ride": "wind_tunnel", "kind": "float_volume", "lot": "mall_small", "instructors": 2, "balls": { "base": 6, "paidAdd": 10 } }
{ "ride": "kite", "kind": "tethered", "zones": ["park", "beach"], "input": { "pull": "mouse", "wind": "server_seeded" } }
// paintball/arena.json
{ "lot": "tv_station", "floors": 5, "atrium": true, "teams": 2, "size": { "min": 4, "max": 8 }, "botsFill": true,
  "matchSecs": 480, "projectile": { "speed": 90, "drop": 9.8, "ttl": 1.5 }, "magazine": 5, "reload": { "auto": true, "key": "R" },
  "lagComp": { "historySecs": 1.0 }, "splats": { "pool": 400 }, "camera": "lockedFirstPerson", "squirrels": "excluded",
  "pass": { "cents": 20, "gameDays": 5, "alsoUnlocks": ["lounge_classic", "lounge_scifi"] },
  "garb": { "sets": 3, "pieces": ["mask", "chest_rig", "pads"], "colourways": ["green", "blue", "red", "yellow"], "cents": 100, "gameplayEffect": "none" } }
```

The ten minigames in ironing-out order (owner check after each, OS-5c): bowling, darts, pool, bumper pool, pinball x3, racquetball, volleyball, giant Jenga, tilt labyrinth; the kite follows as a ride with a little input. Rides have no ironing-out slot by the owner's rule.

### 3.17 Attraction lot types (`data/lot_types/<type>.json`, the `attraction` block)

```jsonc
{ "type": "bowling_alley", "extends": "civic_large", "builder": "BowlingAlley", "kit": "kit.bowling",
  "interior": { "template": "bowling", "public": true, "openHours": [10, 24] },
  "attraction": { "minigames": ["bowling", "pinball_a", "pinball_b", "pinball_c", "pool", "pool", "bumper_pool", "darts", "fortune_machine"],
                  "seats": ["bench_*"], "staff": [ { "post": "bowling_desk", "ai": 1 } ],
                  "backOfHouse": { "doors": "push_bar_to_alley", "props": ["blue_trash_can_x3", "push_broom"] } },
  "routes": ["rack_tunnel_lane_*", "roof_parapet"],                        // the ball-return tunnel is a real squirrel route
  "forage": [ { "kind": "trash_can", "socket": "alley_bin_*", "yield": [1, 3], "cooldown": "day" } ],
  "polish": "high" }                                                       // dec 23: minigames get the polish
{ "type": "lounge_classic", "attraction": { "access": "paintball_pass", "cameraLock": "firstPerson", "guards": 2,
  "staff": [ { "post": "bartender", "ai": 1, "serves": ["hot_cocoa", "coffee", "green_tea", "snow_cone"] } ],
  "squirrels": "killed_by_guards", "music": "library:jazz_1920s" }, "polish": "high" }
{ "type": "steakhouse", "attraction": { "squirrelBlocked": ["glass_*"], "doors": "humanoid_only", "bar": "outdoor",
  "minigames": ["volleyball", "giant_jenga"], "gigs": ["gig_serve"], "seats": ["table_*"] } }
{ "type": "shop_corner", "attraction": { "layout": "1970s_corner_store", "counter": "checkout", "shelves": "items/items.json" } }
{ "type": "tv_station", "attraction": { "paintball": "paintball/arena.json", "cameraLock": "firstPerson", "squirrels": "excluded" }, "polish": "high" }
{ "type": "clinic", "attraction": { "staff": [ { "post": "receptionist", "ai": 1 } ], "table": ["book_animals", "book_early_america", "bead_maze"], "minigames": ["tilt_labyrinth"] } }
{ "type": "museum", "attraction": { "exhibits": "content/exhibits.json" } }
{ "type": "mall_small", "builder": "Galleria", "attraction": { "rides": ["wind_tunnel"], "shops": 4 } }
{ "type": "restaurant_hilltop", "attraction": { "rides": ["sky_lift"], "vantage": true, "seats": ["table_*"] } }
```

Every attraction interior is built to the first-person bar (§5.6) because humans can go first person anywhere and the lounges and arena are locked to it.

### 3.18 Vehicles (`data/vehicles/kinds.json`, `placements.json`; brief v2 §13a, §15)

```jsonc
{ "kinds": {
    "car":    { "motor": "CarMotor", "params": "patrol", "box": [2.35, 4.45, 2.04], "who": "police:driver", "fleet": true, "law": true, "interior": "kit.interior.patrol" },
    "cart":   { "motor": "CarMotor", "params": "cart", "box": [1.6, 2.6, 1.9], "maxSpeed": 7, "who": "anyone", "fleet": true, "law": "stopLines", "interior": "kit.interior.cart" },
    "bike":   { "motor": "BikeMotor", "box": [0.6, 1.8, 1.2], "maxSpeed": 9, "who": "anyone", "fleet": false, "law": false, "interior": null },
    "pickup": { "motor": "CarMotor", "params": "pickup", "box": [2.5, 5.6, 2.3], "who": "human:driver", "fleet": true, "law": true, "offroad": true, "interior": "kit.interior.pickup" },
    "suv":    { "motor": "CarMotor", "params": "suv", "box": [2.4, 5.0, 2.2], "who": "human:driver", "fleet": true, "law": true, "offroad": true, "interior": "kit.interior.suv" },
    "jetski": { "motor": "JetSkiMotor", "surface": "water:marina", "who": "rental", "fleet": false, "law": false, "interior": "kit.interior.jetski" } },
  "camera": { "onEnter": "firstPerson", "toggle": true },               // brief v2 §14
  "undocumented": ["pickup", "suv"] }                                   // prompts only for key holders; no tutorial text
// placements.json: 6 pickups and 4 SUVs parked in town; carts and bikes at the park, the station and the marina
[ { "kind": "pickup", "at": [312, -40], "yaw": 0 }, "...", { "kind": "cart", "at": [88, 350], "owner": "park" }, { "kind": "cart", "at": [-410, 30], "owner": "police" } ]
```

### 3.19 Street lighting (`data/town/lighting.json`; brief v2 §15)

```jsonc
{ "lamps": { "perBlockSide": 1, "spacingMaxU": 60, "height": 5.5, "warmth": [0.95, 0.75, 0.45], "range": 18, "brightness": 1.2 },
  "porch": { "everyHouse": true, "range": 8 }, "shopFront": { "emissive": true, "openOnly": true },
  "flicker": { "fraction": 0.07, "seed": 7 },
  "client": { "enableRadius": 180, "shadows": false, "nightOnly": true }, "skyline": { "emissiveHeads": true } }
```

### 3.20 Persistence profile (`data/persistence/profile.schema.json`; D26)

```jsonc
{ "version": 1, "userId": 0,
  "wallet": { "cents": 0 },
  "receipts": [ { "purchaseId": "...", "productId": 0, "cents": 0, "at": 0 } ],   // idempotency ledger (capped, oldest trimmed)
  "wardrobe": { "garb": ["green_set_a"], "hats": ["sewer_fedora"], "equipped": { "garb": null, "hat": null } },
  "inventory": { "items": { "water_gun": 1 } },
  "reputation": 0, "waterGunStunUsed": false,                                      // Q11: lifetime only if the owner says so
  "stats": { "activeMinutes": 0, "kicks": 0, "bites": 0, "matches": 0 },
  "session": { "lockedBy": null, "lockedAt": 0 } }                                 // ProfileStore-style session lock
```

Rank, homes, hollows, infection, the rodent queue and remodels are **not** in the profile (brief §6, §8; D14).

---

## 4. Order of operations (inside the single pass)

### 4.1 Shape

- **One build pass, Step 0 plus eight waves (W0-W7), with the attraction pair W3c and W4b added between W4 and W5 (rev 3).** Nothing ships publicly before W7. There is **no walkable-town milestone**: W1 has no owner build, and the first thing the owner plays is the FRB at the end of W2, with all eight roles [brief preamble]. Attractions are not roles: most of brief v2 §13a lands after the FRB in two waves, with nine small anchors in the FRB so the human role is "a full game, not a waiting room" (§4.5). Paintball is the exception the brief places itself: built in W4, playtested with the owner (G-PB), cut if weak.
- **Spikes run on a tiny spike place, not on the town**, so W0 cannot become a walkable-town milestone in disguise.
- **Two tracks, matching the two-subagent limit and the 4-CPU container.** Track A: gameplay code (actors, roles, combat, services, controllers) and, **from W2 on, the HUD and UI and traffic gameplay** (violations, pull-over, fender benders), which moves load off Track B; in W4b the minigame, ride and item frameworks, economy, reputation, gigs, mischief and paintball garb. Track B: data, tools, WorldGen, routes, traffic core (lanes, motor, swept test), foraging, wildlife, seasons, client world presentation; in W3c the attraction lots and interiors, vehicle kits with interiors, street lighting and the off-road district. Contracts written in Step 0 (`Types`, `RigSpec`, `Net/Schemas`, the Tunables skeleton, the Ladder draft, and now the `Item`, `Minigame`, `Ride`, `VehicleKinds` and profile contracts) keep the tracks from colliding; the lead integrates.
- **Art has fixed slots, not "continuous" good intentions.** From W1 to W4, **one Track B task slot in every three is an art task** (authoring in bpy, validation, turntables); W5 is mostly art. Blender exports, renders and long test runs run in the background (at most 2 CPU-heavy jobs at once, so CI keeps a core). The squirrel and rodent fit in W1-W2's art slots; humans, fox and deer in W3-W4's.
- **Cloud concurrency.** Both tracks share the CI place and the key's 5-per-minute task budget, so every Open Cloud call goes through `tools/cloud`'s on-disk lock and token bucket, and every engine-test task names the version ID its save returned (S-13).
- **Ephemeral container.** Work is pushed to `spicy-rodents-roblox` at every task boundary; builds are reproducible from git; an environment setup script preinstalls the pinned toolchain (owner decision 4).
- **Preconditions owned by the owner and already in progress:** pushing to GitHub needs the Claude GitHub App connection; S1 needs the luau-execution scope. W0 code starts when push works; Lune-only work can proceed while the scope is fixed. When the App connection is finished, Claude checks that it may push `.github/workflows/*` (the App's "workflows" permission); if not, the owner pastes one file through GitHub's web editor once (F-10, decision 3).
- **Regression rule.** From the FRB on, every owner build must still pass the FRB role checklists (self-checked headlessly first) before new checks are added.
- **Gates with the owner:** **G0** after W0 (spike report; the real commitment point, now also choosing the physics-authority pattern, S13, whether paintball shares the server, S18, and the hard cap at the new floors, S19), **G1** after the FRB (which depth first; the Lune economy curve is shown here, Q4), **G2** turntable approval before each hero asset is imported, **G-PB** the paintball playtest at the end of W4 (OS-5b: the brief's "playtest with Ben before calling it done"; a weak arena is cut, and nothing else depends on it), and an **ironing-out check per minigame** in W4b (OS-5c).
- **Owner builds:** #1 FRB (end W2), #2 (end W3/W4, with the paintball playtest), #2b (end W3c/W4b: attractions and minigames), #3 art and presentation (end W6), release candidate (W7).

**Cross-track dependencies** (a consumer task does not start until its producer's sub-step exit is green; the lead checks this list at every task boundary):

| Consumer (track, wave) | Needs (track, wave) | Why |
|---|---|---|
| Hospital core: stations, fetch shelves (A, W2 #3) | `buildings/hospital.json` v0 and the Hospital builder with all 8 rooms (B, W1 #7) | the v5.4 data has one ward and no isolation ward, pharmacy or staff room [hospital_police_infection §11.1] |
| Police core: car pads, drone console (A, W2 #4-#5) | `buildings/police_station.json` v0 and the PoliceStation builder (B, W1 #7) | the v5.4 station cannot be entered |
| FRB homes, H5, H8 (A/B, W2 #9) | interior schema, `Interior` builder, room graphs, server-owned doors, 4 interior templates (B, W1 #7) | v5.4 interiors are dead code [worldgen_core §18.1] |
| Combat, police, drone (A, W2) | `Swept`, `SweptCollision`, lanes (B, W1 #9); `Perception` (A, W1 #3) | run-overs, sightings |
| Burglar (A, W4 #2) | 40 claimable interiors (B, **W3a** #2) | burglars break into houses |
| Indoor chases, defenders (A, W4 #1) | defender houses and interiors (B, **W3a** #2) | brief §8 |
| Stop-sign tickets town-wide (A, W4 #2) | traffic control everywhere (B, **W3a** #1) | A2 |
| Isolation flow, hatch ambush, ambulances (A, W4 #3) | full hospital, duct, bay (B, **W3a** #3) | brief §9 |
| Upgrade boards, precinct guard (A, W4 #2-#3b) | full hospital staff room and station (B, **W3a** #3-#4) | brief §9-§10 |
| Mall coins, wish, fashion stand (B, W4 #9) | Galleria builder (B, W1 #7); sewer and secrets file (B, W3b #9) | worldgen_districts_art §4.6 |
| Human outfits (B art, W3-W4) | outfit path chosen at G0 (S8e, D22) | F-2 |
| Every hero import (owner, OS-4 on) | G2 turntables, which need S12 renders (W0) | S-7 |
| Outbreak cinematic (A, W4 #13) | greybox street lighting with real lights (B, **W3a** #5); `Clock.setRate`, the `Outbreak` lighting state (A/B, W4) | brief v2 §8: "needs the lamplit town" |
| Paintball core (A, W4 #10) | TV-station greybox with 5 floors, stairwells and atrium (B, **W3c** #1, pulled forward into W3a's tail so W4 can start); S18's authority and venue choice at G0; pose history from `MoveValidator` (A, W1 #6) | brief v2 §13a; D29 |
| Economy live: products, `ProcessReceipt`, the profile (A, W4 #11) | S15 at G0; the owner's developer products and the Studio API-services toggle (OS-0) | D26 |
| Traffic law for everyone (A, W4 #12) | traffic control everywhere (B, W3a #1); player vehicle kinds (A, W1 #5); cells (B, W3a #4) | brief v2 §15 dec 14 |
| Every minigame (A, W4b) | its table, lane or court in an attraction interior (B, **W3c**); the authority pattern from S13 | D28 |
| Rides: sky lift, parasail, wind tunnel, jet ski (A, W4b #4) | the hill terrain extension, cable and stations (B, **W3b** #11); beach and marina stands (B, W3b #5); the small mall (B, W3c); S14 for first person on the gondola | D32, D27 |
| Items beyond the FRB's six (A, W4b #3) | the corner store interior with 22 shelf sockets (B, W3c #1; the FRB uses a 6-socket greybox counter from W2) | brief v2 §13a |
| Gigs: delivery, paper route, serving (A, W4b #5) | bicycles and carts (A, W2 #12); restaurants (B, W3b #5); porches (B, W3b #6); the steakhouse (B, W3c) | brief v2 §13a |
| Pickups and SUVs for the top two humans (A, W4b) | the vehicle kits with interiors and the off-road district (B, W3b #10, W3c #3) | brief v2 §15 |
| Lounges with guards and bartenders (A, W4b #8) | lounge interiors (B, W3c #1); the paintball pass (A, W4 #10) | brief v2 §13a |

### 4.2 Step 0: agree the plan (chat, plus about 17 minutes on the website and 2 in Studio)

- **Deliverables:** `docs/DECISIONS.md` with the owner's answers, the brief deviations (§2.1) and the **v5.4 behaviours keep/defer/drop table** (§4.15); the contracts drafted (no game code).
- **Owner (OS-0):** decisions 1-36 are answered by brief v2 §15 (explicitly or by its "accept the default" rule; §8 records each); the owner confirms the few new ones (§8 items 37-44) or lets their defaults stand. On the Roblox website (Creator Hub), adds two places named "CI" and "Art Inbox" to "Spicy Rodent", checks that Team Create is off on the main place, **sets Max Players to 49** and **creates the three developer products** Claude names (about 17 minutes in all; click-by-click in §6.6); in Studio, once, turns on **Game Settings -> Security -> Enable Studio Access to API Services** (2 minutes) so playtests can read the DataStore. Places and developer products cannot be created through Open Cloud, and the W0 spikes need the CI place and one live product.
- **Claude, right after OS-0:** a Luau Execution call against each new place confirms that the existing key reaches them (if the key is scoped to named places rather than the universe, the owner adds the two places to the key: one more web step, about 2 minutes). Until then, W0 spikes save and test unpublished versions of the main place, which nobody plays yet.
- **Exit:** the owner says go for W0. W0 is small and reversible.

### 4.3 W0: foundation and proof spikes (size M in revision 2; L with the brief v2 spikes S13-S20)

**Deliverables**

1. **Repo and toolchain:** Rojo tree (§1.2), `rokit.toml`, StyLua with the Luau feature, Selene with committed `roblox.yml`, Git LFS rules, Lune harness, `tools/ci.sh` (format, lint, unit, compile check, `rojo build`), GitHub Actions workflow with strict `luau-lsp analyze`, and the environment setup script (cargo: rojo, lune, stylua, patched selene; bpy 5.2.3 venv; node harvest dependencies).
2. **Open Cloud tooling** (Lune `@lune/net`): `cloud/save_place` (unpublished version to the CI place or the main place; returns the version ID), `cloud/run_engine_tests` (create against `/versions/{v}`, poll, parse JSON and logs), a shared on-disk lock and token bucket for every call, `cloud/upload_asset` (Image, Model, Animation; poll the operation), `cloud/harvest_ids` (Luau Execution reads a place version and returns IDs), `cloud/publish`. Rate-limit aware: Luau Execution 5 creates per minute, 10 incomplete per place, 5-minute runtime; Assets 120 per minute. A first call reads the universe owner, so every upload uses the same creator (user or group) as the experience [feas B.c ownership].
3. **Reference capture:** `tools/harvest` runs the pinned v5.4 HTML (SHA-256 checked) in headless Chrome with the [routes_movement §0] instrumentation and emits all 1,332 routes, forks, 95 trees, 24 nests, 12 apple trees and 110 utility supports. `tools/golden` emits golden vectors by calling the original functions in Node with three.js r160: `baseTerrainHeight`, `terrainHeight`, Catmull-Rom `getPointAt`/`getSpacedPoints`, `RouteMotion.advance`, `sweptVehicleHit`/`segmentBoxEntry` (10,000 random plus hand cases), `pounceVelocity`, the `spotted` predicate.
4. **Data import and compiler v0:** JSON Schemas; migration of `spec/data/*`; `tools/compile` validates and emits `generated/` plus count reports.
5. **Contracts:** `Types`, `RigSpec` (all species), `Net/Schemas`, the Tunables tree, `Ladder` with unit tests for every rule row (the 49 arithmetic, the human-queue and administration scores, the rodent-death and squirrel-kill rows), and the rev 3 contracts: `VehicleKinds`, `Item`, `Minigame`, `Ride`, `CameraPolicy`, the profile schema and `PowerRules` with its golden vectors from `updatePowerAndHeat`.
6. **Spike place and spikes S1-S20** (tables below), each recorded in `docs/spikes/Sn.md` as go or fallback with numbers. S5, S6 and S11 are re-scoped by brief v2 (S19 replaces S5's worst case; S6 and S11 run on the extended footprint, D32).

| Spike | Question | Pass looks like | If it fails |
|---|---|---|---|
| **S1 Cloud loop** | Save a version to the CI place (created in Step 0) and run a Luau Execution task **pinned to that version ID** that requires our modules and returns JSON; two saves in a row from two shells through the cloud lock | report back in under 2 minutes, end to end from the container; each task reports the version it ran; the lock serialises the two saves | GitHub Actions runner with the key as a repository secret; engine tests only in owner playtests |
| **S2 Possession** | Possess a walking anchored R15 and a running AnimationController squirrel mid-stride; release on leave; swap; client-local animation (D3); camera on a non-Humanoid; the Roblox menu's Reset routed to Recovery; bubble chat on a non-Humanoid `Head`; 2 clients | 20 handoffs per species at 150 ms simulated lag: position jump <= 0.5 st (squirrel), <= 1.0 st (human); control responsive within 250 ms; no T-pose or frozen frame; 500 automated possess/release cycles with fake drivers: 0 leaked bodies, 0 errors, network owner always matches driver; on leave the AI resumes within 0.2 s; Reset never kills or respawns a body; a chat bubble shows over the squirrel; **owner ticks 6 boxes** | D1 and D3 fallbacks; decided at G0 |
| **S3 Rail motor and validator** | `Curve`, `Registry` (harvested routes), `Graph`, `SquirrelMotor`, `MoveValidator` | samples within 0.01 u of the harvest for all 1,332 routes; 10 simulated minutes of honest circuits (trunk, bough, wire, roof, leap, ground) with 150 ms jitter and 2 % loss: 0 violations; cheat harness (speed x2, 30-st teleport, illegal 20-st leap, wall pass, non-adjacent hop): each flagged within 1 s, >= 95 % detection, 0 false positives; validator <= 0.05 ms per squirrel per tick | server-authoritative rail with prediction (same `step`) |
| **S4 Fatal traffic** | `Swept`, `LaneMath`, `SweptCollision`, ghost vehicles on 3 real lanes | 100 % agreement with the 10,000 JS vectors; Luau Execution: 1,000 randomised crossings agree with analytic truth and the 0.51 s sedan jump window reproduces [traffic §8.4]; 15 squirrels x 50 vehicles <= 0.5 ms per tick | server-view test with a wider pad; anchored server vehicles |
| **S5 AI scale** (re-scoped as **S19**, below) | `BrainScheduler`, `Perception`, minimal brains, `BulkMoveTo`, `Population` | the S19 worst case (about 90 human Humanoids at brief v2's floors): AI <= 4 ms per frame average (a regression baseline, F-14); `BulkMoveTo` of 150 anchored rigs <= 1 ms; in OS-1a, the Telemetry overlay shows client receive under about 50 KB/s | D4 fallbacks (lower hard cap by cutting street, shop and attraction floors; never the police and hospital floors) |
| **S6 Bake, data and terrain** | Lune bake of all 243 lots and 116 roads; BakeParity; `WriteVoxels` over the whole map, **the authored extensions (hill, ridge, back field, long beach; D32)** and the near-hill backdrop bands (Terrain 0.5-2 km out [worldgen_districts_art §14.4]); the same ground as Blender MeshPart tiles (<= 2048 st each) for comparison; require time of the largest data chunk | bake plus `rojo build` < 60 s; runtime bake hash equals the Lune bake; terrain write < 25 s for town, extensions and near bands (recorded separately); largest chunk requires in < 100 ms | D6 terrain fallbacks (a)-(c), with (b) tiles promoted to primary at G0 if terrain misses (the hill and back field first); D7 encoding fallback |
| **S7 Headless animation** | Blender clip -> JSON -> Lune KeyframeSequence -> Open Cloud Animation -> `KeyframeSequenceProvider:GetKeyframeSequenceAsync` in Luau Execution | the clip loads with the expected pose names; in OS-1a it plays without flipped joints | owner Animation Editor imports (D11) |
| **S8 Models and runtime art** | (a) a textured rigid FBX through Open Cloud Model: does a Lune-written MeshPart with its MeshId/TextureID render and collide, and does the upload carry normal and roughness maps? (b) one owner-imported skinned test rig with SurfaceAppearance (TintMask on the body MeshPart, a separate `Pattern` MeshPart), converted to a Package in the Art Inbox: can Claude read its ID through Luau Execution, and does `LoadAsset` at runtime keep the normal map? **(c2)** on that loaded rig, does a server or client script write to `SurfaceAppearance.Color` change the tint, per MeshPart? (c) the facing arrow; (d) can the key download the Art Inbox version for `rojo syncback`? **(e)** outfit path: on a custom R15 test body, does a script-set `MeshPart.TextureID` with transparent tint regions show `MeshPart.Color` there, at runtime, on a `LoadAsset` body; and does an Open Cloud `.rbxm` Model upload that contains a SurfaceAppearance keep it? **(f)** a `MaterialVariant` with uploaded maps applied to greybox parts | (a) renders with Box or Hull collision, maps recorded; (b) ID harvested without copy-paste and the rig renders with its maps; (c2) the tint changes visibly per zone; (c) the arrow faces `LookVector`; (d), (e) and (f) recorded either way | (a) kits load at runtime and the plugin bakes them before a Studio publish; no maps -> (f) MaterialVariant for kits; (b) the owner pastes the ID from the Save dialog; (c2) fails -> 6-8 pre-authored fur variants; (d) the owner uploads the saved `.rbxl` through GitHub's web "Upload files" once per art batch; (e) picks D22's primary or fallback (a)/(b) at G0 |
| **S9 Avatar APIs** | `GetHumanoidDescriptionFromUserId` and `CreateHumanoidModelFromDescription` in Luau Execution for 10 public UserIds (including bizarre bundles, a dynamic head, layered clothing); `MarketplaceService:GetProductInfo` on their shirt, pants and accessory IDs (rate and colour words); copy the classic face decal onto a custom head; hand-weld one rigid accessory to a squirrel `HeadSocket`; 60 descriptions for timing | traits returned; colour words found for most items (rate recorded); face and accessory transfer work; compose works on every species; 60 models < 3 s | verify in the FRB instead; body and accessory colours plus the curated table; stock face |
| **S10 Type checking** | GitHub Actions `luau-lsp analyze` with the Roblox definitions and the sourcemap | 0 strict errors on the skeleton | container source build if the owner allows it |
| **S11 Drone far view** (published) | A small test town published through Open Cloud to the **main place** (private, and nothing else lives there in W0; the start place is the one the Roblox app's Play button joins): Skyline parts for a 4 x 3 km block layout **plus a test hill and an off-road strip beyond a ridge (the extended footprint, D32)**, terrain out to the near bands, one tiled backdrop band, SLIM on static test buildings, **emissive lamp heads on the Skyline layer at night (S17)**, a test drone with `ReplicationFocus` and `PersistentPerPlayer`; the owner flies it from the Roblox app | from 300 st over the centre and each corner: no missing town blocks, far terrain visible (or not: recorded), SLIM visible after transcoding, no horizon seam, the lamplit grid reads at night, the drone keeps streaming around itself 1.5 km from the pilot's body and sees the off-road strip; the owner ticks 5 boxes | Skyline-only far view; Blender ground tiles as primary ground (D6); decided at G0 |
| **S12 Headless renders** | One 36-frame turntable of the test squirrel at 512 px with Cycles (CPU) and EEVEE (if it starts without a GPU) in the container | minutes per frame recorded; a turntable page the owner can open | Cycles at lower samples; a Workbench preview; G2 from still renders only |

**Spikes added by brief v2 (rev 3; delta §3.4):**

| Spike | Question | Pass looks like | If it fails |
|---|---|---|---|
| **S13 Physics minigame authority and feel** | Pool, pinball and Jenga as small test rigs: server-owned parts versus per-turn client ownership versus client-only with a reported result; feel at 100-150 ms simulated latency; determinism of a replayed shot | the chosen pattern per stakes class (D28) with input-to-motion delay under 120 ms for the shooter and no visible rubber-banding for watchers; a Jenga tower of 54 blocks stays stable for 60 s on the server; a replayed pool shot lands within 0.1 st | client-only physics for everything with a sanity-checked result; shared tables become turn-based with server replay |
| **S14 First person inside a kinematic vehicle** | Camera at the driver's eye inside a client-moved `AlignPosition` chassis at 60 Hz, with a placeholder interior and dash; enter and exit transitions; the gondola on a cable | no clipping through the interior, no judder on the owner's Mac, the HUD readable inside the dash, the toggle back to third person works; the gondola cabin holds up at eye level while moving | `VehicleSeat` chassis for player vehicles (D10 fallback); the gondola as a ride with a fixed exterior camera |
| **S15 Developer products, `ProcessReceipt` and the DataStore** | In Studio (API services on): a test developer product bought through `ProcessReceipt`, writing an idempotent receipt and a wallet balance to a DataStore; in Luau Execution: read and write the same keys; session locking; an Open Cloud DataStore read for CI verification | a repeated receipt is not double-credited; the balance survives a Studio stop and start; Luau Execution reads it; the Open Cloud read matches; two simulated servers cannot hold one profile at once | a ProfileStore-style community module if the hand-rolled lock misbehaves; products created but inactive until the loop is proven |
| **S16 Garb and clothing on a possessed body** | On a custom R15 test body loaded with `LoadAsset`: rigid accessory sets welded at runtime, a layered-clothing (WrapLayer) item, a texture swap; apply on possess, remove on release; 100 possess and release cycles | rigid sets and texture swaps work and leak nothing; WrapLayer recorded either way; garb survives a possession swap | garb as rigid accessories plus texture swap only (the brief's own fallback) |
| **S17 Street lighting at scale** | 300 `PointLight`/`SpotLight` lamps (`Shadows = false`) with 20 flickering, porch lights on 60 houses, emissive shop fronts; Future and ShadowMap; a client-radius enable rule; emissive heads on the Skyline layer seen from 300 st (inside S11's test town) | 60 fps on the owner's Mac and 30 fps on a mid phone in Studio's device emulator with the radius rule; the lamplit grid reads from the drone | smaller radius, fewer real lights per block, Neon-only beyond 100 st |
| **S18 Paintball hit detection with lag compensation, in the town server** | A greybox three-floor box with 16 simulated players: server projectile simulation at 60 Hz, 1 s pose history per player rewound to the shooter's timestamp, 10 bots with a navigation brain; measured inside a `SimFull`-style task with the full town population | hits agree with the shooter's view at 150 ms for 95 % of shots in the harness; the arena adds under 1.5 ms per frame to the server at 16 players and 10 bots | a separate place through `TeleportService` with reserved servers (D29 fallback) |
| **S19 Body budget at the new floors** (the re-scoped S5) | S5's worst case rebuilt: 49 human players, 6 police + guard + 2 car crew, 10 hospital staff, 3 ambulance crew, shop and street floors, attraction staff, 16 paintball bots from re-posted bodies, 14 squirrels, 6 deer, 1 fox, 45 vehicles, 2 fender benders | AI under 4 ms per frame average with about 90 Humanoids; `BulkMoveTo` of 150 anchored rigs under 1 ms; the hard cap recorded by measurement | D4 fallbacks; non-Humanoid rigs for silent posts; street, shop and attraction floors cut first, never the brief's police and hospital floors |
| **S20 (small; folded into W2)** | `CaptureService` screenshot from a Tool; `TextService:FilterStringAsync` for chalk text | both work in a Studio test | the camera becomes a photo-pose emote; chalk uses a fixed glyph set |

S8(c2) stays for the animal fur tint (Addendum B1); S8(e) now only needs the skin texels (D22).

**Owner, three short sessions** (click-by-click in §6.6; any order once Claude says each is ready): **OS-1a** (Studio, about 20 minutes): the S2 possession checklist with 2 test windows, a ride along one trunk and one wire, being run over by a test car, the facing arrow, the test clip (S7). **OS-1b** (Studio, about 10 minutes): one test-rig import into the Art Inbox. **OS-1c** (Roblox app, about 10 minutes): fly the S11 test drone on a live private server.

**Exit criteria:** CI green on the skeleton (both the container and GitHub Actions); every spike has a recorded result and a chosen path; the harvest reproduces v5.4 (1,332 routes, 81,613 samples, 95 fork trunks); all 243 lots import and validate; `PowerRules` matches its golden vectors. **Gate G0:** Claude publishes a one-page spike report; the owner reads it (about 10 minutes, OS-1d) and confirms the build goes ahead on the primary design or the named fallbacks, including six choices the spikes settle: the primary ground (terrain or tiles, D6), the outfit path (D22), the animal tint path, **the physics-authority pattern per minigame class (S13, D28), whether paintball shares the town server (S18, D29) and the human hard cap at the new floors (S19, D23)**. This is the significant commitment point.

### 4.4 W1: the spine, role-shaped (size L; headless; no owner build)

Every spine piece is exercised by at least one role's motor or brain in headless tests.

**Track A**

1. `Config`, `Net`, `Clock`, `Util`; `Data` over `generated/`.
2. `World/Height`, `World/Ground` (golden-tested), `Colliders`, `Town`.
3. `Actors`: `Species`, `RigSpec`, `BodyFactory`, `ActorService`, `Possession`, `Population` (posts, floors, re-post, reserve), `BrainScheduler` with LOD, `Perception` (with the concealment terms, golden-tested against `spotted`), `Nav`, and **minimal brains for every species**: pedestrians walk lanes, staff walk hospital circuits, officers patrol, squirrels run routes and ground, the rodent wanders and stalks, the fox roams, deer graze.
4. `Roles/Ladder` (complete, exhaustive tests: the 49 arithmetic, the two score formulas, the rank gate, recruitment by seniority, the rodent-death and squirrel-kill rows), `RoleService` (join, leave, `forceRole`), Role Lab ("Become X").
5. **All motors and controllers with cameras** (human, squirrel, quadruped, drone, and `Vehicles/PlayerVehicles` with the `VehicleKinds` parameter sets: car, cart, bike, pickup, SUV, jet ski; placeholder interiors with a dash and eye socket), including the trampoline bounce on `trampoline` routes [worldgen_core verifier 4], the `CameraPolicy` modes (human toggle, vehicle first person, zone locks, animal third person, chase lock), and `AnimationDriver` (stock R15 locomotion for humans, procedural backend for animals); `Movement/Recovery` (river-fall to the nearer quay, last safe position, Reset routing).
6. `MoveValidator` (log-only, with the 1 s pose history the arena will rewind) and `Telemetry`.
6b. **Rev 3 frameworks as code with tests but no content:** `Rodent/PowerRules` (golden-tested), `Economy/EconomyRules` and `Wallet` (server-life until W4), `Reputation/ReputationRules` and the vote window, `Gigs/GigRules`, the `Item`, `Minigame` and `Ride` contracts with one stub each, `Persistence/Profiles` as a module with a Lune-tested serialiser and an in-memory store (the DataStore binding lands in W4 #11), `Outbreak/OutbreakDirector` as a steppable state machine with the end-card fallback.

**Track B**

7. `tools/compile` complete for the v5.4 data; `WorldGen`: `Plan`, `Factory`, **greybox builders for every lot type present in the imported data** (real doors, roofs, colliders, prompts, Skyline parts, SurfaceGui signs, Beam wires, trees drawn around their route curves, `LevelOfDetail` from data); Lune bake to `Town.rbxm`; `TerrainBake` at boot. Explicitly included because W2 consumes them (S-3, S-11):
   - **`buildings/hospital.json` v0** and the Hospital builder: all 8 brief rooms as greybox (reception, triage, Ward A, Ward B, isolation, pharmacy, staff room, ambulance bay), 4 stations, pharmacy shelves with item slots, room-name volumes;
   - **`buildings/police_station.json` v0** and the PoliceStation builder: enterable lobby, briefing room, drone console, 2 player-car pads and the AI cruiser pad;
   - **the interior template schema, the `Interior` builder, room graphs and server-owned doors**, with 4 interior templates for the FRB houses;
   - **`data/harvest_patches.json`** (S-2): every harvested route that the rebuild changes, with a reason. Known entries: the 20 outer homes keep their v5.4 orientation and roofs under `harvest_lock` (invariant 2) so their harvested routes still match the greybox; outer-home downspouts that double-count terrain are re-seated [routes_movement verifier 3]; the flat outer-home roof landing is kept flat in greybox until W3 templates replace it [routes_movement verifier 4]; the ridge-length quirk is reproduced, not fixed, until W3 [worldgen_core verifier 5]. Anything else that fails the route-on-geometry check must be added here with a reason or fixed.
   - **`population.json` at brief v2's numbers** (49 slots; 35 + 7 + 1 + 5 + 1; police floor 6, hospital floor 10, ambulance crews, 6 deer bodies; invariants 11 and 20) and **`hollows.json` with H12** (the escape tree) and the log.
   - **`World/Height` extensions** from `terrain_extensions.json` (the hill, ridge, back field and long beach as declared patches outside the verbatim rectangle; D32), the `offroad` district with `jurisdiction: false`, and `LampPlan` placing greybox lamp posts (no lights yet) and Skyline heads.
8. Routes: `Curve`, `Registry` (harvest), `SpatialIndex`, `Graph`, `Motion`.
9. Traffic: lanes with handedness unified, AI `CarMotor` and `LaneMath`, yielding (humans and squirrels included, relative visibility height), stop control at the existing sign sites, `Swept`, `SweptCollision`, teleport flags, ghost vehicles; placeholder vehicles at the true logical boxes.
10. `tools/placeholders`: R15 humans from stock HumanoidDescriptions in role colour palettes [hospital_police_infection §5.1, §8.2]; squirrel, fox, deer, drone and car puppets built from parts with the **final bone, socket and region names**.
11. `Map/MapModel`, the minimap and the rendered map image; `Avatar/BlendRules` and `AvatarBlendService` with the dev samples.
12. **Art slots** (one Track B slot in three): squirrel and rodent base mesh and rig v0 in bpy, turntable renders, budget validation.

**Exit criteria (all headless)**

- Lune: all unit and golden tests green.
- Luau Execution `BootSmoke` (every module requires), `DataIntegrity`, `WorldBuild` (lot count equals data; no solid overlap; every door reachable from a sidewalk; every route sample within `surfaceRadius + 0.3 u` of geometry or terrain, except entries in `harvest_patches.json`, each of which must carry a reason; Skyline for every building; the hospital's 8 rooms and the station console exist), `BakeParity`, `Actors` (spawn every species; possess and release through a `PlayerLike` stub; death keeps species counts; `Population` floors hold through 200 scripted joins, promotions and leaves).
- **`SimFull`:** 5 simulated minutes at 60 Hz at the full standing population (69 humans, 8 riders, 10 squirrels, the rodent, a fox, 6 deer, about 20 vehicles) in **one** Luau Execution task (5-minute wall limit; if a run nears it, the measured window shrinks to 3 simulated minutes rather than splitting, because a second task cannot resume the first one's state, S-12): every actor moves; no NaN; nobody outside the world clamp; no vehicle stuck more than 60 s unless parked; AI under 4 ms per frame on average (a regression signal, F-14).
- **`SimLong`:** 40 simulated minutes at 1/15 s steps with a quarter of the population, in one task: liveness only (no leaks, no stuck actors, no drift in counts), plus one accelerated winter start and end.

### 4.5 W2: role loops -> FIRST RUNNABLE BUILD (size L; owner build #1)

**Track A**

1. **Combat:** pounce with wind-up, commit and recovery; v5.4 contact and bite chance by awareness; kick, baton and shove with telegraphs; rodent health with **the game-clock drain, the bite heals and the lowered regen (D33)**, death and replacement in the Ladder's order (offer to the top squirrel at once, body re-enters after `Ladder.params.rodentReentry`, S-10); the bite dance on every 10th bite [squirrel_abilities §10]; no fall damage (v5.4); **the Power meter** on the rodent HUD from `PowerRules` (FERAL / RABID / SUPER; the fade on real active minutes); the rodent ignores deer until every squirrel is infected (gate only; the rabid deer is W4).
2. **Infection:** per-actor infection and the red-eye tell; infected AI walk to the hospital; squirrel share; a per-rodent tally of who it infected (for the 30 % rule); **reset to the new rodent on rodent death** (humans cured, instantly if recently bitten or en route; infected squirrels to lowest human; hoards, money and reputation kept); hidden critical mass and the winner record logged (visible in the Lab); the outbreak cinematic comes in W4.
3. **Hospital core** (on the W1 Hospital builder's 8 greybox rooms): stations with the 3-step disinfect loop; fetch tasks with 6 items on pharmacy shelves; staff shove; infected staff x1.5; a performance number.
4. **Police core:** baton; sightings on the map; top-two car keys; `PlayerVehicles` with the patrol-car kind (enter, exit, drive, siren and lights, park anywhere; first person on entry with the toggle kept, §14); radar; `QuestService` with **parking ticket** and **speeding ticket**.
5. **Drone core:** launch and dock at the station console; flight with `ReplicationFocus`; feed HUD; spot-and-mark; vigilante summon (`VigilanteRules` keeps 8 % of all human actors flagged, flags on AI bodies only, re-assigned within 1 s of a possession; approach only); deer startle source. Unlocked from the Lab; the real unlock path is W4.
6. Every Ladder rule wired through `RoleService`, with `OfferUI`; `Population` join, re-post and reserve deployment at the brief's floors (10 AI hospital staff and 6 AI police visible at full occupancy), so a join is never refused inside the 49 (§1.5); the squirrel-slot order hospital, then police, then humans; the killed-squirrel recycle rule where humans can already kick (infected squirrels have health from here). Slot expansion 5 to 8 and police recruitment by seniority exist in the Ladder and are reachable from the Lab.
   - **6b. Moved from Track B (rebalance):** role HUDs (wallet, reputation, rank or "unranked", Power), notifications, the full Role Lab (§4.7 commands), bug report, the Reset button routed to Recovery.
   - **6c. The nine human-life anchors (brief v2 §13a; delta §3.3)**, each proving a framework the attractions reuse: (1) the **Spicy-Dollar wallet** in cents with a HUD and pay from the shop job at the minimum wage (server-life; no Robux yet); (2) **the corner store greybox with six of the 22 items working** (water gun with the rodent stun, football throw, air horn, flashlight, lawn chair, soda), proving `Item` (Tools on a possessed Humanoid, server validation, inventory across possessions); (3) **one gig with the quality rule** (lawn mowing), proving tips and the reputation ding; (4) **reputation core**: the per-player value, 5 + 5 votes per in-game day with weighting, a cafe seat that raises it, its term in the human queue score and the 10-day gate shown as "unranked"; (5) **one golf cart and bicycles** at the park, anyone may ride, first person on entry with a placeholder dash (S14), proving `PlayerVehicles` beyond the patrol car; (6) **the human first-person toggle** everywhere; (7) **the taunt button** with 20 lines (the mild-rating rewrite of the v5.4 lines happens here too, dec 24); (8) **the Power meter** (item 1); (9) **the 49 / 35+7+1+5+1 population with the brief's NPC floors** (M9 becomes "fill to 49").

**Track B**

7. **Foraging core:** sources from data (v4.1 caches, trash cans, garden plots, feeders) with **finite season stock**; carrying (**max 9**); **12 hollows**, each with a knothole and a single-chamber placeholder interior (H12 with three knotholes); meter, 70 % ownership **and the 3-day visit rule with claim lapse**; claiming by deposit, no ritual; stink gland; river-fall recovery for squirrels (Recovery, W1).
8. **Wildlife verbs:** fox lunge against squirrels (rodent immune, stink repels); deer graze, bolt and leap; AI startle from vehicles and the drone.
9. **Jobs and homes:** a restock job at 3 shops paying Spicy cents per in-game hour; the corner store's greybox counter and 6 shelf sockets; a cafe with `Seat` sockets; the park's cart and bike stands; claim at the 4 core houses, whose greybox interiors come from the W1 `Interior` builder (doors, rooms, hide spots).
10. **Seasons basic:** clock and calendar HUD; day and night from the HTML presets plus night; winter toggle (forage x0.3, cold grade); winter-end survival check.
11. `docs/playtest/FRB.md` and the checklist page; art slots continue (squirrel and rodent v1 for G2).

**Owner: OS-2**, the FRB playtest (60-90 minutes; can be split as roles 1-4 and roles 5-8 plus multi-client).

**Exit criteria**

- Headless first: `SimFull` with gameplay assertions (the AI rodent lands at least one bite; the hospital cures at least one patient; at least one sighting; at least one parking violation spawns; radar speeds are non-zero; swept hits only on roads; the vigilante share stays at 8 % through possessions; at least two AI squirrels hold a claim through a visit cycle; Power rises on a bite and fades after 10 active minutes without one; health drains by the clock); `LadderE2E` (scripted joins, kills, winter end and leaves through `RoleService`, plus the rodent re-entry versus offer cases, rodent death resetting infection, a killed infected squirrel recycling its player and promoting the top hospital player, an unranked player skipped by offers, and a **49-player fill** that keeps every post at its floor with 10 AI hospital staff and 6 AI police) green; `Economy` (wages per in-game hour, a purchase at the counter, a gig tip and ding) and `Cap49` (the 50th join is refused by MaxPlayers, not by us) green.
- The owner's eight role checklists and the multi-client checklist pass (§4.7). Failures are logged with repro steps and fixed first in W3/W4.
- **Gate G1:** the owner picks which depth comes first (knobs, §4.13).

### 4.6 What the FIRST RUNNABLE BUILD contains (tag `frb-1`)

| Area | Contents |
|---|---|
| World | The whole v5.4 footprint as data-driven greybox: 243 lots, 116 roads, terrain over the playable rectangle (about 4,350 x 2,520 st) **plus the declared extensions as bare terrain (the hill, the ridge, the back field; nothing built on them yet)**; the complete v5.4 climbing network (1,332 routes) on real greybox trees, poles, wires and roofs; 4 enterable houses; the hospital greybox with all 8 brief rooms; the police station with car pads and the drone console; **12 hollows** (knothole plus placeholder chamber; H12 with three knotholes); a greybox corner-store counter with 6 shelf sockets; a cafe with seats; the park's cart and bike stands; greybox lamp posts (unlit); Skyline for the drone; default sky, day/night cycle, calendar |
| Bodies | 69 standing AI humans by post (32 townspeople of whom 6 start as infected patients, 6 shop workers, 14 hospital staff with a floor of 10, 3 ambulance crew, 14 police with a floor of 6 plus the guard and car crew) plus 8 reserve bodies, hard cap per S19 (§1.5); 10 squirrels; 1 spicy rodent; 1 fox; 6 deer bodies (5 slots); 2 player-drivable patrol cars; 1 golf cart and 4 bicycles; about 20 AI vehicles (AI patrol car, ice-cream van, trolley, heavy vehicles); 1 drone. Every possessable body is possessable mid-stride; every unheld slot is AI. Novelty riders and motorcyclists arrive in W4 |
| Systems | possession on join and leave, with posts and floors under the hard 49 cap; the full Ladder with offers, side exits, the two score formulas, the rank gate, recruitment by seniority, rodent-death reset and the squirrel-kill recycle; Role Lab; Reset routed to Recovery; river-fall recovery; concealment in spotting; combat core with drain, bite heals and Power; per-actor infection; hospital disinfect and fetch; police baton, car, radar, parking and speeding quests; drone flight with spot-and-mark; foraging with finite stock and carry 9, hollows with the visit rule, stink gland; fox and deer verbs; shop job paid in Spicy cents, the wallet, 6 store items, one gig, reputation and votes, a golf cart and bicycles in first person, the human first-person toggle, the taunt button, home claim; server swept run-over for every squirrel actor; sightings and the map; the 70/30 blend on placeholders (humans: face, hair, skin tone; animals: fur tint); live Tunables |
| Art | placeholders only: R15 humans in role palettes; part-built animals with procedural gaits; part-built cars and drone; R15 stock locomotion |

**Explicitly not in the FRB** (and where it lands): traffic control everywhere, 40 interiors, defenders, full hospital and station, greybox street lighting with real lights (W3a); expansion lots, 8 house archetypes, backyards, premium hollow interiors, sewer and ducts, the hill with the sky lift and hilltop restaurant, the off-road district with its trees (W3b); the attraction lots and interiors, vehicle kits with interiors, pickups and SUVs, pets (W3c); feint and zig-zag, the indoor escape rule, alert zones and the rabid deer, burglar, argument, fender bender, stop-sign running, ambulances, police performance and 5 to 8 progression, upgrades, remodels, full forage risks, yard cats and dogs, full winter, ambient life, novelty cast, community events and crime scenes, mall coins, chili hunt, fashion stand, speech, **paintball (W4 #10, per the brief), Robux products and the DataStore profile (W4 #11), traffic law for players (W4 #12), the outbreak cinematic (W4 #13)**; every minigame and ride, the other 16 items, the other gigs and NPC posts, mischief, companions, the lounges' guards and bartenders, paintball garb (W4b); authored art (W5, starting right after the FRB); backdrop, fog layering, moon phases, audio, the final street-lighting pass (W6); enforcement, vehicle lag compensation, lifetime stats, mobile, the SLIM check on the release build (W7; SLIM flags are baked from W1).

### 4.7 FRB acceptance checks, per role

**Setup, once per session.** Open Studio, open "Spicy Rodent" from the start page, **Test** tab, choose 1 player (or 2-4 for the multi-client checks), **Start**. A **LAB** button appears at the top left. Each role starts with **LAB -> Become \<role\>**, which bypasses the ladder for testing; the ladder itself is tested by R5, S5, P3, F5, E3, M2-M7 and M9. Each line is action -> expected result. These checks are delivered as a shareable checklist page.

| Role | Thinnest complete loop | Deepened in |
|---|---|---|
| Townsperson | walk -> shop job -> Spicy Dollars -> buy and use a store item; mow a lawn for a tip; vote and sit at a cafe -> reputation; ride a cart in first person; taunt; kick the rodent; get bitten -> walk to hospital; claim a home | W3a (40 homes), W4 (remodels, swing, back away, flee, vigilantes, indoor escape, events, mall coins, traffic law, Robux), W4b (the other 16 items, gigs, posts, mischief, companions, minigames, rides, lounges, garb) |
| Hospital staff | infected patient arrives -> disinfect -> pay and performance; fetch the right item fast; kill the rodent inside -> become a squirrel | W3a (full building, ducts), W4 (ambulances, performance tiers, upgrades, catalogue, hatch ambush) |
| Police | sighting on the map -> on foot or by car -> baton the rodent; radar a speeder -> pull over -> ticket; parking ticket | W4 (argument, fender bender, stop sign, burglar, performance, 5 to 8, coordination tiers, upgrades) |
| Drone | launch -> fly the town -> find the rodent -> mark it -> officers see it, vigilantes converge | W0 S11 (far view proven), W6 (backdrop, fog, night), W7 (SLIM on the release build) |
| Squirrel | run and climb the full network -> forage -> store in a knothole -> meter -> own the tree; stink repels; rank = 90/10; infected -> penalty | W3b (premium hollows, backyards), W4 (bird, cat and dog risks, raids, winter) |
| Spicy rodent | stalk -> pounce (wind-up, commit, recovery) -> bite -> infection spreads and Power rises; health heals on a bite and drains by the clock; kicks hurt; run over or killed -> townsperson, infection resets to the new rodent | W4 (feint, zig-zag, alert zones, defenders, indoor chases, rabid deer, chili rush, the outbreak cinematic) |
| Fox | roam -> lunge at squirrels on the ground -> they drop nuts; rodent immune; stink repels; leave -> previous human rank | W5 art |
| Deer | wander, graze, bolt, leap; AI deer startle from cars and the drone; the rodent ignores you; leave -> previous human rank | W4 (biteable once every squirrel is infected; rabid charge), W5 art |

**Townsperson (H)**
- H1. Join (no Lab) -> you are already walking on a sidewalk; you did not drop from the sky. HUD: "TOWNSPERSON - Rank n of m".
- H2. WASD, Shift, Space -> walk, run, jump; the camera follows.
- H3. M opens the map -> your arrow moves; district names show; a JOB marker sits on the corner shops.
- H4. At the job, E at each of the 3 glowing shelves -> the wallet on the HUD ticks up in Spicy cents at the end of each in-game hour worked; your rank reads "unranked" until the Lab skips you to 10 in-game days, then improves within 10 s.
- H5. E at a door marked AVAILABLE -> "This is your home"; a house icon appears on the map.
- H6. LAB -> "Spawn rodent near me". As it closes in, a kick telegraph shows; click -> kick. On a hit: "KICK! +rank" and the rodent's health bar drops.
- H7. Let it bite you -> "INFECTED"; another window sees your eyes glow red; a marker points to the hospital; walk in and get cured.
- H8. Nearby AI townspeople flee; some run into one of the 4 houses and the door closes behind them.
- H9. Esc -> Reset Character -> you are moved to a safe spot nearby; you do not die or change role.
- H10. At the corner store, E at the counter -> buy a water gun (6 cents) and a football (6) -> they appear in your Backpack; squirt an AI townsperson -> they react ("wet" shake); squirt the rodent -> it freezes 1.3 s once, never again for you; throw the football -> it flies and lands; buy and blow the air horn -> nearby squirrels flee; the flashlight only lights at night; the lawn chair places a seat you can sit on; soda refills your sprint.
- H11. E at a lawn with a mower marker -> "Mow the lawn" -> cover the lawn -> pay in cents plus "Tip!" if you covered it well; mow half and quit -> a small reputation ding on the HUD.
- H12. Open the player list -> thumbs up Player 2 -> their reputation (visible to them) rises a little; try a sixth thumbs up in the same in-game day -> "No votes left today".
- H13. Sit at the cafe (E on a chair) -> reputation ticks up each in-game hour.
- H14. E at the golf cart in the park -> you sit in it and the camera is in first person behind a placeholder dash; W/S/A/D drive, slowly; V toggles third person; E exits; the bicycle works the same and is faster.
- H15. V (first-person toggle) anywhere on foot -> first person; walk into a house -> the interior holds up at eye level; V again -> third person.
- H16. T -> a one-liner appears over your head and the taunt cycles; no line is profane.
- H17. Rank panel: "unranked (n of 10 in-game days)" until the gate passes; the Lab's "Skip me to day 10" makes the rank appear.

**Hospital staff (S)**
- S1. LAB -> Become Hospital Staff -> you are at reception; HUD: "HOSPITAL".
- S2. Visit reception, triage, Ward A, Ward B, isolation, pharmacy, staff room, ambulance bay -> each name shows as you enter.
- S3. LAB -> "Send infected patient" -> a red-eyed patient walks to a bed; E at the station -> 3 steps (hold E; press E on green; hold E) -> "CURED"; the wallet ticks up at the hour; eyes return to normal; the performance number changes.
- S4. A toast: "Bay 3 needs SALINE (blue)" with a 45 s timer; take the blue bin from the pharmacy, E at Bay 3 -> "Correct". Repeat with the wrong bin -> "Wrong item -10 s".
- S5. LAB -> "Spawn rodent in hospital" -> shove it until it dies -> you instantly become a squirrel.
- S6. LAB -> "Infect me" -> the disinfect steps take visibly longer (x1.5).

**Police (P)**
- P1. LAB -> Become Police -> you are an officer at the station.
- P2. LAB -> "Spawn rodent" near townspeople -> within seconds a sighting marker appears on your map and fades after about a minute.
- P3. Reach the rodent; click -> baton wind-up, then strike. Two hits kill it -> you are promoted (to squirrel if a body is free).
- P4. As the only officer you hold car keys. E at the cruiser -> you sit in it; W/S/A/D drive; H toggles siren and lights (another window sees and hears them); E exits; the car stays where you left it.
- P5. While driving, the radar panel lists the car ahead with its speed and the limit; a speeder shows red.
- P6. A parking-violation marker appears (or LAB -> "Spawn parking violation") -> walk to the car at the hydrant -> E "Write ticket" -> Spicy cents and rank.
- P7. Follow a red radar target and press H behind it -> it pulls over -> E at its window -> ticket, Spicy cents and rank.
- P8. LAB -> "Spawn rodent on road", then drive over it -> "RUN OVER", and you get the kill credit.

**Drone (DR)**
- DR1. LAB -> Become Drone -> the camera lifts from the console; HUD "DRONE FEED" with altitude, heading and zoom.
- DR2. WASD, E/Q up and down, mouse look, wheel zoom; ceiling 400 st. From altitude the whole town is visible; distant blocks are simple shapes.
- DR3. Hold the mouse on the rodent about 0.6 s -> "MARKED". An officer window sees an outline and a map marker for 12 s; nearby AI vigilantes run toward it.
- DR4. Fly low over the deer -> they bolt.
- DR5. F -> the drone flies home and docks; you are back in your officer body at the console.

**Squirrel (Q)**
- Q1. LAB -> Become Squirrel -> you take over a running AI squirrel without it stopping.
- Q2. Run, sprint, Space leap; walk into a trunk to climb; A/D picks a branch at forks; walk a wire between poles; Q drops you off.
- Q3. E at a trash can or garden bed (map markers) -> "+3 nuts (carried)".
- Q4. Climb to a knothole, E -> inside view; E "Store" -> the meter rises; at 70 % or more -> "This tree is yours".
- Q5. LAB -> "Fill stink 95 %" -> R -> a puff; a nearby human and the fox recoil; the meter drops by 30.
- Q6. The HUD shows your squirrel rank (90 % nuts, 10 % stink) and your place in the rodent queue.
- Q7. LAB -> "Spawn fox" -> it hunts you on the ground; climbing makes you safe.
- Q8. LAB -> "Rodent bites me" -> "INFECTED: lost nuts, dropped in queue".
- Q9. Jump into the river from the bridge -> you reappear on the nearer quay.
- Q10. Forage past nine nuts -> "Pockets full (9)"; the HUD counts 9/9.
- Q11. Own a tree (Q4), then LAB -> "Advance clock 4 days" without visiting -> "Your claim on this tree lapsed"; visit and deposit -> owned again.
- Q12. Climb the escape tree (H12) -> three knotholes; leave by each -> you come out on a different bough or the ground.
- Q13. LAB -> "Spawn human kicker" while you are infected -> two kicks and you are a townsperson at the bottom of the queue; a healthy squirrel body climbs out of a nest and Player 2 (hospital staff) is offered it.

**Spicy rodent (R)**
- R1. LAB -> Become Spicy Rodent -> zombie-squirrel placeholder with red eyes; all squirrel movement works.
- R2. Hold the right mouse button -> first-person stalk, slow and quiet, with an aim arc.
- R3. Click -> short crouch (wind-up), lunge, brief stagger (recovery). Hit an unaware townsperson from behind -> "BITE"; their eyes turn red and they flee; a police window gets a sighting.
- R4. Pounce at someone already looking at you -> usually "Batted away".
- R5. LAB -> "Make a vigilante kick me" twice quickly -> after the second kick you die and become a townsperson at the lowest rank; the top squirrel is offered the rodent at once, and a rodent climbs out of a sewer grate about 20 s later (an AI one if nobody accepted).
- R6. Stand on a road as a car comes -> "RUN OVER" -> you become a townsperson.
- R7. Rest inside a knothole, or stalk -> the health bar refills slowly (about a minute for a kick's worth in a hollow).
- R8. The HUD shows a second meter, POWER, labelled FERAL; bite a townsperson -> +100 and the bar moves; LAB -> "Advance active time 10 min" -> Power drops 15 %; LAB -> "Set Power 600" -> the label reads RABID; 1,500 -> SUPER.
- R9. LAB -> "Advance clock 5 days" without biting -> health is down about 5; bite a human -> +10 health; bite a squirrel -> +20.
- R10. Stalk a deer -> no pounce prompt ("Not yet"); LAB -> "Infect every squirrel" -> the deer becomes a target.
- R11. Die with the town at 20 % infected -> the new rodent (AI or Player 2) starts with the town at about 0.5 %; a red-eyed AI townsperson on the way to the hospital is cured; an infected squirrel you had bitten is now a townsperson.

**Fox (F)**
- F1. LAB -> Become Fox -> WASD, Shift run, Space jump.
- F2. Click to lunge at a squirrel on the ground -> it is knocked back and drops nuts.
- F3. Lunge at the rodent -> nothing happens ("Not that one").
- F4. A squirrel's stink makes you recoil for about 4 s.
- F5. LAB -> "Leave side role" -> you are a townsperson at your previous rank.

**Deer (E)**
- E1. LAB -> Become Deer -> walk, Shift bolt, Space leap, G graze.
- E2. LAB -> "Spawn car near deer" -> the AI deer bolt; fly the drone low over them -> they bolt again.
- E3. Leave -> you return to your previous human rank.
- E4. LAB -> "Spawn rodent near me" -> it ignores you; nothing you do makes it bite (until W4's gate opens).

**Multi-client (M)** (Test with 3 players)
- M1. Watch a walking townsperson in Player 1's window while Player 2 joins -> Player 2 takes over a walking body mid-stride; nobody pops in.
- M2. Close Player 2's window -> that body keeps walking as AI.
- M3. Player 1 rodent, Player 2 police -> Player 2 sees sightings when AI spot Player 1; baton against pounce; death transitions apply to both.
- M4. Player 3 drone marks Player 1 -> Player 2 sees the outline.
- M5. Player 2 drives over Player 1 -> run-over death with credit to Player 2.
- M6. LAB -> "Blend sample: Neon" on Player 1's squirrel -> stock squirrel with a neon tail tip only; "Giant bundle" -> silhouette unchanged.
- M7. Player 1 is the top squirrel; LAB -> "Kill rodent" -> Player 1 sees the offer -> Accept -> Player 1's squirrel walks on as AI and Player 1 is the rodent.
- M8. LAB -> "Skip to winter end" -> squirrels below the survival threshold become humans.
- M9. LAB -> "Fill town to 49 players" (fake drivers) -> Player 3 leaves and rejoins -> still gets a walking body; the hospital shows at least 10 AI staff, the station at least 6 AI police, and the shops still show workers; a 50th fake join is refused by Roblox, not by the game.
- M10. Player 1 (rodent) dies while Player 2 is an infected squirrel -> Player 2 becomes a lowest-rank townsperson and keeps their money and reputation; Player 3 (townsperson) keeps their home.
- M11. Player 2 kicks Player 1 (an infected squirrel) twice -> Player 1 recycles to the bottom of the human queue; Player 3 (hospital staff) is offered the squirrel slot before any police player.

### 4.8 W3: town completeness through data (size XL; Track B; alongside W4), then W3c: attraction lots, interiors, vehicle kits and lighting (Track B; alongside W4b)

**Before building:** Claude publishes a **town-plan page** (proposed placements, the 40 interior houses, the 3 defender houses, restaurant and shop sites, the 12 hollow sites, and, per brief v2 §15 dec 18, **the steakhouse, the hill with the sky lift and hilltop restaurant, the TV station, the bowling alley, the new mall, both lounges, the corner store, doctor's office, museum, racquetball court, and the off-road zone below the ridge**, on the extended footprint); the owner approves it on the web (decision 18, decided; OS-3, about 30 minutes).

W3 is split so that everything W4 consumes comes first (S-4). **W3a** must exit before the W4 items that need it start (§4.1 dependency table); W4 items that need nothing from W3 (duel tuning, feint, zig-zag, petty argument, parking variants, foraging risks, ambient life, winter) start at once.

**W3a: what W4 needs (first)**

1. Roads connected [worldgen_core §4.3]; traffic control everywhere: all-way stops on the grid, signals on the boulevard, hydrants, red curbs, legal and illegal parking [traffic §12]; motorcycles and novelty riders as road users with logical boxes (§4.15).
2. Houses, part 1: **40 interiors** with nav graphs, hide spots, lockable doors, back exits and server-owned doors (the W1 `Interior` builder and schema); claimable homes with remodel slots; the 3 defender houses.
3. Hospital, full: Ward A and Ward B, isolation with airlock, pharmacy with 12 item kinds, staff room with the upgrade board, supply, covered ambulance bay, roof hatch into the 7-node duct (`duct` routes, vents, server-timed chewing), with the hatch moved over an aisle.
4. Police station interior: spawn, lockers, briefing board and upgrade board, dispatch/radar room, cells (now also used by traffic law, W4 #12), precinct-guard post, drone console and roof pad, garage with the police carts.
5. **Street lighting, greybox with real lights** (D30, brief v2 §15): lamps per block from `LampPlan` on placeholder posts, porch lights on every house, emissive shop fronts, the client radius rule and seeded flicker, Skyline emissive heads; so the W4 cinematic can be judged on a lamplit town. The final look is W6 #4.
6. **TV-station greybox** (five floors, stairwells, central atrium, arena volumes; D29), so W4 #10 can start; the rest of the attraction lots are W3c.

**W3b: town completeness (then)**

5. Expansion lots [brief §3]: restaurants doubled to at least 18 food businesses (invariant 4: diner, pizza, taco, Chinese, café, bakery, ice cream, bar and grill), each restaurant with seating or a dumpster; barber (the owner's specifics, Q14), music, hardware, laundromat, bookshop, pet store (with the pets' home, W3c), corner grocery; school with playground, church, marina (with the jet-ski and parasail stands), pier, **the beach extended past the public area**; Quay facades promoted to enterable restaurants and shops (The Old Anchor, Copper Kettle, The Tea Room, Willow Bakery, Quayside Books); the two gas stations typed. Shop workers become a **shared rota** of 12 bodies assigned by `JobService` to the open businesses nearest to players; a business without a worker shows "Back soon" and still offers player jobs (§1.5). Cafes get `Seat` sockets (reputation).
6. Houses, part 2: 8 archetypes with per-lot flair (town-wide distinctness) and **backyards** (gardens, feeders, sheds, fences, dog houses, flowering bushes, **trampolines at 3-4 sites, two climbable tree houses with Humanoid ladders**) on every house (invariants 10, 12 and 16); porches get the paper-route target.
7. Hollow trees: H1 spiral-ramp premium, H2 shaft premium, **H12 the escape tree with three knotholes and exits**, 9 knothole chambers, and the fallen-log tunnel (§5.5).
8. Routes: lot-type templates for every lot (ridges, downspouts, gutters, fences, awnings, interiors, hollows), checked against the harvest wherever a lot is unchanged; linkers; the hospital roof route. The 20 outer homes are rebuilt to face the road with template routes, and every `harvest_lock` entry in `harvest_patches.json` is retired.
9. Sewer (retained per brief §3) and Galleria camera constraints [worldgen_districts_art §16]; the secrets file (chili peppers, fashion stand, fountain, coin spawns).
10. Lane-2 kits begin replacing greybox as they pass budget checks (house kits from the archetype JSON, trees from route curves, storefronts).
11. **The hill, the sky lift and the hilltop restaurant** (brief v2 §13a, D32): the terrain extension, a `SkyLift` base station in town and a hilltop station, the cable and six cabins as a `Ride` path, `restaurant_hilltop` with its vantage over the town; the second far-view check (OS-7).
12. **The off-road district** (brief v2 §15, D32): beyond the ridge with real trees, the back field with hills, the long beach; no roads, lanes, lots or stop lines; `jurisdiction: false`; two drivable slopes from town; the 6 pickups and 4 SUVs parked in town from `placements.json` (drivable in W4b once the human-driver subrole is live).

**W3c: attractions, interiors, vehicle kits and lighting (Track B; alongside W4b, after W3b and W4; rev 3)**

13. **Attraction lots and interiors** (brief v2 §13a; §3.17; invariant 16): the corner store with its 1970s-style layout, checkout counter and 22 shelf sockets; the doctor's office (reception counter, waiting-room table with two picture books, the bead maze and the tilt labyrinth); the museum with readable exhibits from `content/exhibits.json`; the **bowling alley** (six lanes, pin decks, overhead lights, scoreboards, the **ball-return tunnel under each lane as a real `tunnel` route from the alley bins to the rack**, the arcade corner with three pinball sockets, two pool tables, the bumper pool table, the dartboard, the fortune machine by the ferns, and the back of house with steel push-bar doors to an alley, big round dark-blue trash cans as forage sockets and a push broom); the racquetball court; the steakhouse (outdoor bar, glass walls in `SquirrelBlocked`, Humanoid-only doors, sand court with a beach ball and volleyball net, the deck table for giant Jenga); both lounges' shells (interiors in W5 kits); the small mall on the Galleria builder with the glass wind-tunnel cylinder; the antique store with browsable curios; the TV station's interior detail over W3a's greybox.
14. **Vehicle kits with interiors and dashboards** (brief v2 §14; §5.3 P3): patrol car, golf cart, pickup, SUV, jet ski and gondola cabin interiors as greybox with a `DashSocket` and eye socket (art in W5); carts and bikes placed at the park, the station and the marina.
15. **Pets**: a few dogs and cats as `Pet` bodies at the pet store and in yards for the NPC posts.
16. Lane-2 kits continue; the lounge and arena lighting detail slots begin (dec 23 polish).

**Owner:** web review of the town plan (about 30 minutes, start of W3). The playtest is shared with W4 (build #2) and W4b (build #2b).

**Exit criteria:** W3a: `WorldBuild` passes for all 40 interiors (an AI human paths from the door to every hide spot and the back exit), the hospital and station rooms, town-wide stop lines, and the lamp count per block (invariant 18); W3b: all compiler invariants (§3.13) green with no `harvest_lock` left; no orphan downspouts; the route connectivity report is at or above v5.4; the 12 hollows and the off-road slopes pass; W3c: invariant 16 and 17 green; a squirrel paths the full length of every ball-return tunnel and pops out at the rack; every attraction interior passes the eye-level check (no see-through walls or floating props within 2 st of any seat, lane or counter, raycast test).

### 4.9 W4: systems depth (size XL; Track A, with the Track B items marked; alongside W3), then W4b: attractions and minigames (Track A; alongside W3c)

1. **Duel, full** [brief v2 §8; squirrel_abilities §25]: tuned wind-up, commit and recovery; feint with stamina; zig-zag detection (lateral reversals per second give a miss bonus and a speed penalty); human responses (flinch, swing, kick, back away, flee) chosen by awareness and nerve; vigilantes never flee; *(after W3a)* indoor pounce, bite and kick; defenders with rolling pins and a broom at x1.5; indoor chases that actually run, with the indoor escape rule (§3.4, decision 35); crime scenes after a bite (the victim sits, witnesses raise the alarm as a sighting, up to 4 bystanders gather until police or EMT arrive) [humans_actors §7.2-7.4]; the hidden chili hunt (8 peppers) and the rodent-only chili rush (decision 20); **rev 3:** **alert zones** after every bite (hidden kick multiplier, swing-heavy responses, a near-impossible second bite, NPC police within about two blocks chasing up to five), the **rabid deer** once every squirrel is infected (charge through town, scatter humans; mechanics per Q5), the **squirrel chase** with the forward-locked camera and AI squirrels fleeing at full sprint on rails, **human strikes on infected squirrels** with the kill, respawn, hospital-first promotion and recycle rules, `rescue` events, and the rodent's cover (hollow interiors and the sewer as `unseen` volumes).
2. **Police:** *(after W3a)* burglar (a `Burglar` brain using interiors); petty argument (3-choice mediation); fender bender with **borrowed driver bodies** (D25); stop-sign running town-wide and the full pull-over; parking variants; AI dispatch backfill; the precinct guard and station reinforcements that keep the rodent out of the station [hospital_police_infection §8.4-§8.5]; **police performance** (§3.9) unlocking officers 6, 7 and 8; **later officers more aggressive and better coordinated** (`PoliceCoord`): tier 1 (officers 1-5) chase on a sighting; tier 2 (6-7) pair up as pursuer and cut-off, the cut-off heading for the junction ahead of the rodent on the route and lane graphs; tier 3 (8) sets a 3-point perimeter around the last sighting and shares sightings by radio; player officers from tier 2 get a "Call backup" verb that assigns AI officers as cut-off; the drone unlock as an upgrade bought at 8 officers; wanted posters as a sighting source.
3. **Hospital:** *(after W3a)* ambulances and responder flow into the bay [hospital_police_infection §7]; performance (§3.9) raising staff rank; the full fetch catalogue; isolation flow; the overhead-hatch ambush with its 2.5 s attack window [humans_actors verifier 6; hospital_police_infection §4.6].
   - **3b. Upgrades:** the catalogue in `upgrades.json`, the two upgrade boards, pooled credit contributions and purchases, effects wired as tunable multipliers (brief §9, §10, §13; A2).
4. **Homes:** remodel points (cadence per decision 22) and remodel options.
5. **Foraging, full** (Track B): gardens, feeders with **bird risk resolved on the server** from the same seeded bird function the clients draw (birds at the feeder: a peck scares the squirrel off and it drops 1 nut) and homeowner risk; trash, dumpsters, apples, acorns, the mall plaza; premium weekly raids; theft rules; **yard cats' telegraphed swat and dogs' bark that alerts nearby humans** (`YardHazards`, server-side); the AI rodent's behaviour when unheld (decision 17).
6. **Winter, full** (Track B): snow applied **client-locally** (terrain material and overlay swaps near each camera; nothing replicated, F-7), bare trees (leaf models hidden in one batch), survival rule, squirrel float, wildlife changes.
7. **Ambient life** (Track B): birds and nests, butterflies, dragonflies, insects, turtles, rabbits, a world-relative overflight.
   - **7b. Street cast** (Track A): the novelty riders (Marcel the mime on a unicycle and 5 kid cyclists, AI-only, with their own spotting and escape rules [humans_actors §8]), 2 motorcyclists (in the fatal fleet; a bite crashes the rider, v5.4), skaters on sidewalks; the 8 Quay walkers are ordinary townsperson actors.
8. **Speech and flavour:** BillboardGui bubbles with curated lines (**the v5.4 swearing rewritten to keep the venom and lose the vocabulary, "skating the line like a lawyer"; brief v2 §15 dec 24**), per-actor speech timers that always tick [humans_actors verifier 3]; living-community events (barbecue, softball) from `events.json` on their 2,400 s cycle, which also seed petty arguments; outbreak ambience with the gas station closing; **the end card is now only the client fallback behind #13**.
9. **Mall and sewer** (Track B): Galleria coin pickup (coins become **Spicy cents** for humans and nut crumbs for squirrels, decision 20 as answered), the wishing-fountain toss (spend a coin for a small random boon), the mall state machine (doors and lights animated on clients from `mallState`); the sewer fashion stand (buy with Spicy cents or nut crumbs, equip; **wardrobe saved in the profile, D26**; a worn hat replaces the A3 accessory).
10. **Paintball core** (brief v2 §13a; D29; rev 3): on W3a's TV-station greybox, the in-server instanced match: lobby and teams, 4v4-8v8 with `PaintballBot` bodies borrowed from townspeople above their floors, a generic marker that **shoots right** (server-simulated projectile with travel and slight drop, client prediction, 5-shot magazine with auto reload and R), **server-side hit detection with lag compensation** (1 s pose history rewound to the shooter's timestamp), pooled paint splats on walls and players, sprint and crouch that feel right, five floors with stairwells and the atrium, match timer, scoreboard and end card, distinct fire and hit audio, locked first person, squirrels excluded; the 20-cent access pass for five in-game days (also opening the lounges); **Gate G-PB** at OS-5b. The garb shop is W4b.
11. **Economy live** (D26): the developer products the owner created, `MarketplaceService.ProcessReceipt` with the idempotent receipt ledger, the **DataStore profile** (wallet, receipts, wardrobe, inventory, reputation) with session locking, `BindToClose` flush and the read-only fallback; prices from `prices.json`; the Lune economy simulation shown at G1 becomes the tuning baseline (Q4); the human-queue money term goes live.
12. **Traffic law for everyone** (brief v2 §15 dec 14; `TrafficLaw`): violations on player vehicles (speeding, stop lines, parking), AI and player officers ticketing players (fines in cents; the ticket quests gain player targets), cells in the station for repeat offenders and pedestrian hits, the Ladder's officer demotion with key revocation, **non-fatal pedestrian hits** by player vehicles (knockdown, ambulance, admitted as an uninfected trauma patient; Q17 for player pedestrians), AI vehicles still yielding to people, the off-road district exempt.
13. **The outbreak cinematic** (brief v2 §8, §15 dec 11; D31): `OutbreakDirector` phases on `Clock.setRate`, every squirrel body infected and sweeping house to house with rising speed, the `Outbreak` lighting state (overcast and dim by day, fade to black at night) on W3a's lamplit town, each client's camera pulling up and out from the server's timestamp on the Skyline layer, then the Ladder reset (winner keeps the rodent; surviving infected squirrels keep squirrel bodies); the end card as the fallback.

**Owner: OS-5**, build #2 playtest (about 60 minutes): the FRB regression set plus scenario checklists per new system (indoor chase to each escape outcome, defender, each police quest, coordinated police tiers, upgrades, ambulance, hatch ambush, winter end, mall coins, an alert zone after a bite, the rabid deer, a Robux test purchase in Studio, a speeding fine and a cell, the outbreak cinematic through the Lab). **OS-5b, the paintball playtest (about 60 minutes, 2-4 windows): the brief's "playtest with Ben before calling it done" (G-PB).** The owner's verdict is recorded in `docs/DECISIONS.md`: keep, fix a named list, or cut.

**Exit criteria:** per-system engine simulations green (`RodentLoop` including indoor chases to each outcome, crime scenes, alert zones, the rabid deer and the squirrel-kill rules; `Traffic` 120 s with 0 deadlocks, stop-sign compliance equal to the tunable, and player-vehicle violations ticketed; quest lifecycles; hospital treatment; `PoliceCoord`: over 50 scripted rodent escapes, tier-3 AI officers catch the rodent at least 1.5 times as often as tier 1; `Upgrades` purchase and effect; `Paintball` hit-registration harness at 150 ms; `Economy` receipt idempotency; `Persistence` save, lock and restore; `OutbreakCinematic` trigger and phases; `SimFull` re-run with fender benders, events, the street cast and a 16-body match inside the budget); build #2 checks pass; G-PB recorded.

**W4b: minigames, rides, items, gigs, reputation, mischief (Track A; alongside W3c; rev 3)**

Each minigame lands in this order, headless tests first, then an "ironed out" acceptance check (below) and a 10-15 minute owner check (OS-5c); the owner's rule is that only minigames get this treatment, so rides have none.

1. **The `Minigame` framework and bowling** (the harness: join, seats, turns, input validation, authority by S13, result, scoreboard, Lab scenarios): angle and power, the ball, physics pins, scoring over ten frames, the ball returning up the rack, overhead lights and working scoreboards; the alley is "no scrimping", so bowling is first in the polish order.
2. **Darts** (501 and cricket; mouse aim point, timing meter, slight wobble), **pool and bumper pool** (cue aim, power, 8-ball rules, bumpers), **the three pinball tables** (distinct themes, flipper physics on the client), **racquetball** (against an NPC opponent body or a player), **volleyball** at the steakhouse sand, **giant Jenga** (54 blocks, pull and place), **the tilt labyrinth** with its fixed controls, the **bead maze** (a toy, not a game), **the fortune machine** (lever, spinning fortune cards, a fortune or a taunt, no money ever; styled per Q20).
3. **The other 16 items** on the `Item` framework (frisbee, bubbles, chalk with filtered text and the 20-letter budget, umbrella, peanuts and bird seed as bait that AI squirrels approach and seeded birds flock to, dog treats, newspaper, the disposable camera through `CaptureService`, duct tape, whoopee cushion, harmonica, bike horn, ice cream bar, radio with the library playlist, **the kite as a ride-class flying sequence in the park and on the beach**); the Q13 defaults for the undefined effects.
4. **The `Ride` framework**: the sky-lift gondola on W3b's cable with first person on boarding, parasailing over the beach, the wind tunnel in the small mall (float on `LinearVelocity`, two silly instructors throwing server-owned giant balls, other players paying to add 10), and the steerable exception, the **jet ski** (`JetSkiMotor` over the marina water, rented for Spicy Dollars, first person).
5. **Gigs and NPC posts**: delivery by bike or cart, sign-spinning, car washing, the morning paper route with the porch bonus, serving tables at the steakhouse (each with the quality rule); the park billboard and station poster with NPC mini-missions (walk Mrs. Harrison's dog, return a lost pet) paying coins.
6. **Mischief** (TP-ing trees, knock-and-run, egging at night, water balloons, joyriding a police cart) with NPC anger, the police `mischief_response` quest and the Q7 consequences; supplies sold at the corner grocery by default.
7. **Reputation, full**: companions (NPCs who like you pal around or follow; entourage raises rank), rescue and true-report events, lost pets; votes with the brigading weight tests.
8. **Lounges live**: `LoungeGuard` bodies that kill any squirrel that enters (Q6 for a player squirrel), the 1940s-style bartender serving hot cocoa, coffee, green tea and snow cones, licensed 1920s-feel jazz in lounge one, the procedural ambient loop in lounge two, access by the paintball pass, locked first person.
9. **Paintball garb and the wardrobe**: three Blender outfit sets (mask, chest rig, pads) in four colourways (green, blue, red, yellow) with insignia and patches as rigid accessory sets (S16), one Spicy Dollar per set, kept permanently in the profile, wearable back into town if the possession system allows (it does, through the D13 accessory path) and otherwise removed on leaving the arena; no gameplay effect.
10. **Pickups and SUVs** for the top two ranked humans (`humanDriver`, hand-over when parked, prompts only for key holders, undocumented), drivable into the off-road district.

**"Ironed out" acceptance check, per minigame** (the exit for each item above): a headless determinism test (the same inputs give the same result twice), a physics-stability test (no part leaves its table or lane in 10 simulated minutes of random play; Jenga stands 60 s), input-to-motion under 120 ms for the active player at 150 ms simulated latency (S13's bar), the scoreboard matching the rules module on 50 scripted games, and the owner's check ticked in OS-5c ("feels right", "controls do what the brief says", "I would play it again").

**Owner: OS-5c**, the minigame checks (about 90 minutes over two sittings, 10-15 minutes each: bowling, darts, pool and bumper pool, pinball, racquetball, volleyball, Jenga, the labyrinth), plus a 20-minute walk through the attractions on **build #2b** (store items, a gig of each kind, a ride of each kind, a lounge, the wind tunnel, the hilltop by gondola).

**Exit criteria:** `Minigames` suite green for every game (determinism, stability, replay agreement where the server replays); every minigame's owner check ticked or its fix list recorded; `Rides` suite (board, path, exit, camera mode) green; every one of the 22 items has an engine test of its effect; `Economy` with gigs, posts, purchases and the arena shop; `Reputation` brigading cases; `SimFull` with companions, pets and a running match inside the budget.

### 4.10 W5: art landing (size L in revision 2, XL with the attraction kits; art has fixed Track B slots from W1, §4.1)

Art lands as each asset passes its gate, in the §5.3 priority order. W5 is where the must-replace list closes.

1. Squirrel and rodent (default: imported right after the FRB, OS-4).
2. Human bodies (6 types on one shared UV layout), the role outfits by the path chosen at G0 (D22: colour-texture sets uploaded headlessly by default), hair, props and verb clips; the face slot on every head.
3. Fox and deer.
4. Vehicles and the drone, **with interiors and dashboards** for every player-enterable kind (patrol car, golf cart, pickup, SUV, jet ski, gondola cabin; brief v2 §14).
5. Trees and the hollow interiors (premium, escape, knothole, log).
6. House, interior, civic, commercial, hospital and police kits.
7. Quay and Galleria kits; street furniture, **lamp posts, porch lights and shop-front signs with emissives**.
8. **Attraction kits** (rev 3; rough is fine, dec 23): corner store (1970s-style shelving, checkout), clinic, museum, bowling alley (lanes, pin deck, rack, arcade cabinets, back-of-house props), racquetball, steakhouse (bar, glass, deck, net), small mall and wind tunnel, hilltop restaurant and gondola, antique store, TV-station interior; the **22 store items** as props; **minigame props** (balls, cues, darts, 54 Jenga blocks, pinball tables, the fortune cabinet); **paintball garb**, 3 sets x 3 pieces x 4 colourways with insignia; the **two lounge interiors** (leather and woodwork, fancy counters; lava lamps, dense plants and sci-fi fittings).
9. **The polish pass where people pay or play** (brief v2 §15 dec 23): extra lighting detail in both lounges and the paintball arena; each minigame's table, lane or court ironed out visually after its owner check.

**Owner:** G2 turntable approvals on the web (10 minutes per batch); **OS-4** (squirrel and rodent, about 20 minutes, during W3); **OS-6a** (fox and deer, about 15 minutes), **OS-6b** (6 human bodies, about 15 minutes; plus about 25 minutes of outfit imports only if D22 fell back to (a)), **OS-6c** (the 2 premium hollow trees, the escape tree and the two lounge kits if they carry SurfaceAppearance, about 25 minutes). If S7 failed, each session also carries its rig's clip imports (budgeted in §6.6).

**Exit criteria:** the engine `Assets` suite is green (every ID loads; every ID is moderation-approved or falls back visibly in the report; bone and socket names and triangle budgets hold; every clip loads, which also catches ownership errors); zero placeholders remain on the must-replace list (squirrel, rodent, humans and outfits, fox, deer, patrol car and the five other vehicle interiors, hollow trees, house kit, hospital interior, the bowling alley, both lounges, the arena); budgets still hold with final art; the G2 bar of §5.6 ("rough is fine; contours, textures, colours, shading and shadows, and the basic movement set") met on every hero asset; no money spent and no outside artist.

### 4.11 W6: world presentation (size L)

1. Backdrop [worldgen_districts_art §14.4]: three bands of hills and mountains with baked aerial perspective, a tree line and a distant road with impostor cars; **fog layering** [brief §3]: alpha-gradient fog cards between and in front of the mountain bands and in the valleys (tiled planes or Beams, colour and opacity set per lighting state on the client), in front of a tuned `Atmosphere`, because Atmosphere is one global layer [feas f]; the ocean to the horizon (Terrain water near the coast, tiled planes beyond), beach, pier and marina; the radio tower on the measured sunset azimuth with blinking obstruction lights; every band, ocean and ground mesh tiled at <= 2048 st per part and <= 20k triangles per tile (F-8); all `Persistent`.
2. Lighting state machine from the clock: sunrise and sunset as their own moments, golden hours, blue hour, night with stars [worldgen_districts_art §14.3].
3. Moon phases: `MoonTextureId` swap per phase (16 textures rendered headlessly and uploaded), custom client moon as the fallback [feas B.f].
4. Clouds, winter grade, audio and ambience from the licensed library (D24), signage pass, interior lighting, the clock-tower hands; **the street-lighting final pass** (brief v2 §15, D30): warm pools on every block, the flickering few, porch lights, glowing shop fronts, tuned against S17's budget; **the outbreak cinematic's final look** on the lamplit town.
5. A published private-server check of the drone far view with the real backdrop (Skyline and SLIM, which the bake has set since W1; S11 already proved the method), with `ReplicationFocus` on the drone, by night as well as day, and **from the hilltop restaurant** (the second vantage).
6. **Detail by distance** (dec 23): high on the ridge and anything near town (the off-road zone is playable, so it gets real trees and terrain); the far distance is painted scenery (the bands).

**Owner: OS-7** (about 30 minutes): LAB -> "Set time 18:40" -> is the tower silhouetted from the ground and from the drone? Drone at 300 st over the centre and each corner -> no holes, no horizon seam; do the mountains show soft layers of fog between the ridges, morning and evening? LAB -> "Set time 22:00" -> does the town read as lamplit from the drone and from the hilltop? LAB -> "Trigger outbreak" -> does the cinematic look right at night and by day?

**Exit criteria:** no horizon seam at 300 st with the default FOV; at least two visible fog layers between the mountain bands at sunrise and sunset; the moon index advances once per in-game day through new, waxing, full and waning; the drone (max altitude 400 st) collides with the 315-st radio tower in an engine test; at night every block shows at least one lit lamp pool within the client radius and the Skyline heads read from 300 st; owner build #3.

### 4.12 W7: scale, hardening and publish (size L)

1. Movement validation enforced; swept-collision lag compensation for vehicles (pose rewind to client timestamps; the arena has had it since W4); combat rewind tuned.
2. Performance pass at 49 players: an 8-client Studio test plus a live private-server session, **with a paintball match running inside a full server and every minigame table occupied**; MicroProfiler captures.
3. Mobile and gamepad bindings (minigame controls included; the labyrinth keeps its keyboard bindings and gains a tilt-stick equivalent).
4. Lifetime stats in the profile (the profile itself has been live since W4 #11, D26); a DataStore budget check at 49 players.
5. README (brief §14: module layout; how to add a lot type, a route, a role) and tidied Blender deliverables (sources plus exported FBX for the squirrel with seven clips, human variants, fox, deer and key props).
6. Verify SLIM on the release build (the bake has written `LevelOfDetail` since W1); `EnableSLIMAvatars`; the SpicyTools plugin only if S8 or S6 forced a Studio bake.
7. Game settings: confirm max players is **49** (the owner set it in OS-0), server fill (decision 26), the maturity questionnaire answered for "mild" with the rewritten lines (decision 24), the developer products active with the right IDs, and that no simulated-gambling imagery is in the fortune machine (Q20).
8. Publish: through Open Cloud when the place holds no SurfaceAppearance or Studio-only instances; otherwise from Studio.

**Owner: OS-8** (60-75 minutes): a private-server session with 10 or more friends using the tester checklist; the maturity questionnaire; approve the publish (or click Publish if a Studio publish is needed); set the experience public when ready.

**Exit criteria:** tagged release candidate; every regression checklist green; budgets met **in the live MicroProfiler capture**, which is the real gate (headless `SimFull` numbers are only a regression signal, F-14): server AI under 4 ms per frame with a match running; server frame p95 under 16 ms in the live session; no client under 30 fps on the owner's Mac at 8 clients, lamps lit; every role played by a real person in the live session with no blocking bugs, including at least one Roblox-avatar 70/30 blend per species seen by a second player, one real Robux purchase that survives a server restart, and a 49th join that works while a 50th waits.

### 4.13 Knobs the owner can turn on the order

1. **Hero art earlier (default ON).** Squirrel and rodent are imported right after the FRB, so playtests feel like the game sooner. Costs about one Track B cycle; nothing on Track A.
2. **W3 and W4 interleave, with W3a first (default).** W3a (traffic control, interiors and defenders, hospital, station) exits before the W4 items that need it (§4.1 table); everything else runs side by side. Alternative: finish all of W3 before W4 starts (slower, simpler to follow).
3. **Backdrop before art.** Swap W6 and W5 if the drone role is the showcase to demo first.
4. **Hardening earlier.** Pull W7 enforcement into W4 if public tests are planned before release.
5. ~~Commissioned hero squirrel.~~ Withdrawn: brief v2 §15 dec 23 says no money is ever spent on art and no outside artist. The rig contract is still frozen in W0, so the owner could reverse this later with a manifest edit.
6. **Human life sooner (rev 3).** If the human role must feel "full" before W4b, W4b's first three items (bowling, the other items, the gigs) can be pulled into W4 at the cost of pushing W4's police coordination tiers and upgrades into W4b. Default off: the FRB anchors already make the human role more than a waiting room.
7. **Paintball later.** The brief places paintball in W4; if G0's S18 result is marginal, it can move to W4b with the lounges' access pass stubbed. Default off.

### 4.14 Relative size (for the order discussion; not calendar promises)

| Step | Size | Owner time | Extra owner time only if a W0 fallback is taken |
|---|---|---|---|
| Step 0 | S | 20 min chat, 17 min web (places, Team Create check, Max Players 49, three developer products), 2 min Studio (API services) | +2 min if the key must list the new places |
| W0 | M -> **L** (eight more spikes, S13-S20) | 20 + 10 min Studio, 10 min Roblox app, 10 min report | none |
| W1 | L | none | |
| W2 (FRB) | L | 60-90 min | |
| W3 + W4 | XL + XL, in parallel (W3a first); W4 is larger than in revision 2 (paintball, economy live, traffic law, the cinematic) | 30 min web (town plan with 12 more sites), 20 min Studio (OS-4), 60 min playtest, **60 min paintball playtest (OS-5b)** | S7 failed: +30 min clip imports in OS-4 (about 20 squirrel and rodent clips) |
| **W3c + W4b** (rev 3) | **XL + XL**, in parallel (the attractions: 13 lot types with interiors, 6 vehicle kits, lighting; 10 minigames, 4 rides, 22 items, gigs, posts, mischief, reputation, garb, lounges) | **90 min minigame checks (OS-5c) + 20 min attractions walk (build #2b)** | |
| W5 | L -> **XL** (the kit count roughly doubles: attraction interiors, 6 vehicle interiors, garb, lounge kits, minigame props, lamps; rough is fine) | 15 + 15 + 25 min Studio, 4 x 10 min web | S7 failed: +45 min (about 30 human clips) in OS-6b, +30 min (about 21 fox and deer clips) in OS-6a; D22 fallback (a): +25 min outfit imports in OS-6b |
| W6 | L | 30 min | |
| W7 | L | 60-75 min | |
| **Total** | **roughly double revision 2** (2 XL + 3 L + 3 M of new work against the PDF brief's L + XL gameplay layer; delta §3.1) | **about 10.5-11.5 hours** | **up to about 2.2 hours more** |

**Honest reading of the size (delta §3.1).** The §13a places-and-attractions list alone is about 1.5-2x the PDF brief's whole gameplay layer (W2 plus W4); with the §8 rule additions, vehicles and traffic law for everyone, the v2 delta is about 2-2.5x the PDF's gameplay work, and the whole project roughly **doubles**. None of this is a calendar promise; it is the order of magnitude the owner should hold in mind when reading "build the whole game in one pass". The two new waves run in parallel on the two tracks like W3 and W4, so the shape of the plan does not change, only its length.

### 4.15 v5.4 behaviours: keep, defer or drop (also in `docs/DECISIONS.md` from Step 0)

The specs document v5.4 behaviour that the brief does not name. Nothing is dropped by omission: every row is kept with a wave and a check, deferred to a named owner decision, or dropped with a reason. The owner can flip any row at Step 0 or G1 (decision 33).

| # | v5.4 behaviour (spec) | Call | Wave | Check |
|---|---|---|---|---|
| D-1 | Novelty street cast: Marcel the mime on a unicycle and 5 kid cyclists, with their own spotting and escape rules (humans_actors §8) | **Keep**, AI-only and never possessable (decision 21); non-Humanoid rider rigs; `NoveltyRider` brain | W4 #7b | `Traffic` sim includes them; OS-5 scenario "the mime flees the rodent" |
| D-2 | Motorcyclists (2) and skaters as road and sidewalk users; motorcycles outside the fatal fleet (traffic §2.7, §5.12; defect 5, Q9) | **Keep**; motorcycles **join the fatal fleet** with a 0.8 x 2.2 u box (default; v5.4 omits them); a bite crashes the rider as in v5.4; skaters on sidewalks | W3a #1, W4 #7b | swept golden cases for the motorcycle box; `Traffic` sim |
| D-3 | Living-community events: barbecue (-66,-84), softball (66,356), 2,400 s cycle (humans_actors §9.3, Q7) | **Keep**, from `events.json`; they also seed petty arguments | W4 #8 | `SimLong` asserts each event fires and AI attend |
| D-4 | Crime scenes: seated victims, witness alarm, bystanders (humans_actors §7.2-7.4) | **Keep** | W4 #1 | `RodentLoop`: a bite produces a seated victim, a witness sighting and up to 4 bystanders |
| D-5 | Yard cats' telegraphed swat, yard dogs' bark that alerts humans (humans_actors §12; squirrel_abilities verifier 2); turtles | **Keep** cats and dogs as **server-side** yard hazards (`YardHazards`); turtles and rabbits as client ambient life | W4 #5, #7 | engine test: a swat drops 1 nut; a bark raises nearby humans' alert; OS-5 scenario |
| D-6 | Garden and hedge concealment from human spotting (wildlife verifier 1) | **Keep** in `Perception.spotted` from `concealment.json` | W1 #3 (in the FRB) | golden `spotted` cases with concealment |
| D-7 | River-fall recovery to the nearer quay; swimming (worldgen_districts_art §16, Q9) | **Keep** squirrel recovery and add "last safe position" for every body; humans, deer and the fox do not swim (they wade out at the nearer bank; decision 34) | W1 #5, W2 #7 | FRB check Q9; unit tests |
| D-8 | Hidden chili hunt (8 peppers) and chili rush (squirrel_abilities §12-§13) | **Keep** as a rodent-only power-up (decision 20) | W4 #1 | `RodentLoop`: picking up a pepper starts a 12 s rush |
| D-9 | Sewer fashion stand, wardrobe (squirrel_abilities §15) | **Keep** as a cosmetic (decision 20, decided): Spicy cents or nut crumbs; wardrobe saved in the profile (D26) | W4 #9 | engine test: buy, equip, the hat replaces the A3 accessory; the hat survives a server restart |
| D-10 | Galleria coin pickup, wishing-fountain toss, mall state machine (worldgen_districts_art §4.6-§4.7, §16) | **Keep** (coins become Spicy cents for humans and nut crumbs for squirrels; decision 20 as answered) | W4 #9 | engine test: pickup pays cents; OS-5 scenario |
| D-11 | Trampoline bounce (worldgen_core verifier 4) | **Keep** in `SquirrelMotor` | W1 #5 (in the FRB) | unit test: bounce apex matches the v5.4 golden |
| D-12 | Hospital overhead-hatch ambush, 2.5 s attack window (humans_actors verifier 6; hospital_police §4.6) | **Keep**, with the hatch over an aisle | W4 #3 | OS-5 scenario; engine test of the window |
| D-13 | Incident police, station reinforcements, precinct guards (hospital_police §8.4-§8.5) | **Keep** (the police AI floor includes the guard) | W4 #2 | `RodentLoop`: the rodent entering the station draws the guard |
| D-14 | Bite dance every 10th bite (squirrel_abilities §10, Q9) | **Keep** every 10th bite (tunable) | W2 #1 | `CombatRules` unit test |
| D-15 | NPC voices by speech synthesis (humans_actors §11) | **Defer** (decision 34): bubbles only until W6, then text-to-speech if Roblox's audio API offers it to this experience | W6 #4 (if kept) | n/a until decided |
| D-16 | 8 Quay ambient walkers (worldgen_districts_art §15) | **Keep as ordinary townsperson actors** (brief §4: every human is an actor) | W1 (cast) | `DataIntegrity` cast count |
| D-17 | v4.1 extras: crowd accessories (`makeTownPeopleMoreDistinct`), flowering bushes (humans_actors verifier 2; wildlife §11.7) | **Keep**: accessories through cast looks and hair/props; flowering bushes as backyard items | W1 #10 (placeholders), W3b #6, W5 | invariant 12; visual check in OS-5 |
| D-18 | Gas-station panic closure; clock-tower hands; legacy decorative ambulance loop (worldgen_core Q7; districts_art Q11; hospital_police Q17) | **Keep** closure as outbreak ambience; **keep** the clock-tower hands; **drop** the legacy loop (real ambulances replace it) | W4 #8, W6 #4, W4 #3 | OS-5 / OS-7 scenarios |
| D-19 | Squirrel on a moving car roof (routes Q6, traffic Q13) | **Default**: no riding; a squirrel on a parked car's roof is set down beside the car when it moves (`Recovery.onVehicleMoved`); stationary cars never kill (decision 34) | W2 | unit test; player cars included |
| D-20 | Rodent fall damage (routes Q7) | **Drop** (none, as in v5.4); a tunable kept at 0 (decision 34) | W2 | n/a |
| D-21 | **Power** meter and the heat/fade loop (squirrel_abilities §12, `updatePowerAndHeat`) | **Keep exactly as v5.4** (brief v2 §15 dec 20 reverses revision 2's "drop"): the table's rewards and penalties, the 10-active-minute fade of 15 % rounded up, FERAL / RABID / SUPER on the HUD; **Gold stays dropped**; the fade clock counts active play, never the game clock (rule 11); the pedestrian-kick -19 and the absolute-Y quirk follow Q23 | W1 #6b (`PowerRules`), W2 #1 (HUD) | golden vectors from `updatePowerAndHeat`; FRB R8 |

---

## 5. Asset plan (Blender)

### 5.1 Pipeline and lanes

```
blender/<asset>/build.py (bpy 5.2.3, headless) -> <asset>.blend (LFS)
  -> blender/validate.py: tris <= budget and <= 20k per mesh; <= 4 influences per vertex; Root at origin with
     no weights; frozen transforms; bone, socket and region names == RigSpec; clips keyed from frame 0;
     scene named after the clip
  -> exports: <asset>_rig.fbx (no animation) + <asset>_<Clip>.fbx (one clip per file) + clips/<Clip>.json
     (bone TRS per frame) + *.sockets.json / *.routes.json (named empties and curves)
  -> review: turntable and clip contact-sheet renders (Cycles on CPU, or EEVEE if it starts headless; timing
     proven by S12) -> gate G2 (owner, web)
  -> Roblox (by lane, below) -> manifest IDs -> runtime: BodyFactory / Kits pick the best available version
```

**FBX settings** [feas A5]: Unit System None; FBX Unit Scale; Z forward and Y up (models face -Z, D21); Leaf Bones off; Bake Animation on for clips only; NLA, All Actions and Force Start/End off; Simplify 0; Embed Textures on with Path Mode Copy; one animation track per file.

| Lane | Path | Owner in Studio? | Used for |
|---|---|---|---|
| 1. Code geometry | Parts, wedges, Terrain, Beams and SurfaceGui text built by WorldGen from data | no | the whole FRB; signs; wires; Skyline massing |
| 2. Cloud mesh | bpy -> FBX -> Open Cloud Model upload -> IDs harvested by Luau Execution -> kit templates in `assets/` -> baked into the place; PBR through `MaterialVariant` with uploaded maps if the FBX upload carries colour only (S8a, S8f) | no | building kits, props, furniture, vehicles **with interiors and dashboards**, trees, backdrop bands and fog cards (tiled <= 2048 st), pier and marina, terrain tiles, **attraction kits, minigame props, the 22 store items, lamp posts, paintball garb pieces (rigid accessories), the gondola** |
| 3. Studio import | owner: Import 3D into the **Art Inbox** place (Rig Type Custom or R15) -> Convert to Package -> Save; Claude harvests the ID; the server loads it at runtime with `LoadAsset` | yes, about 3 minutes per asset | skinned rigs (squirrel, rodent, fox, deer, human bodies) and any PBR hero (premium and escape hollow trees, the two lounge interiors if they carry SurfaceAppearance, patrol car if it uses SurfaceAppearance) |
| 4. Data-only appearance | HumanoidDescription recipes and generated 2D clothing images (placeholders); then **per-part outfit colour textures** for the 6 custom bodies on one shared UV layout, uploaded as images through Open Cloud and set at runtime with `MeshPart.TextureID`; skin texels transparent so the body-part colour shows (D22; no accent tint zones, brief v2 §13a) | no | placeholder humans; every role outfit on every body type |

### 5.2 Contracts and placeholders

Every rig and kit has a contract in `RigSpec` or the kit registry: bone and joint names, socket attachments, region MeshParts for the blend, root and pivot, facing -Z, the logical hitbox and the clip names. Gameplay reads only the contract, so placeholders and art are interchangeable.

| Body | Contract essentials |
|---|---|
| Squirrel / rodent | `Root` (non-deform, origin); Hips, Spine1-3, Chest, Neck, Head, Jaw, EarL/R, Tail1-8, four legs x (Upper, Lower, Foot, Toe). Regions, **each its own skinned MeshPart because each SurfaceAppearance has one Color** (D22, F-1): `Body` (fur tint), `Pattern` (tail tip, stripes), `Eyes`, `FurCards`; the rodent's blood is a separate small texture on `Blood` (F-9). A rigid part named `Head` for bubble chat. Sockets `HeadSocket`, `MouthSocket` (carried nuts and fetch items), `TailTip`, `ChestCenter`. Hitbox radius 0.32 u, re-tuned for the 1.2-st shoulder |
| Human | Standard R15 parts on **one shared UV layout across the 6 bodies**; outfit = one colour texture per part (Lane 4), plain colour, no accent zones (brief v2 §13a); skin = `Head`, hands and bare-arm texels transparent over the body-part colour; `FaceDecal` on the head; plus `RightGripAttachment`/`LeftGripAttachment`, `BadgeAttachment`, `HairAttachment` and the garb attachments (`MaskAttachment`, `ChestRigAttachment`, `PadAttachmentL/R`); a crouch pose for paintball |
| Fox / deer | as squirrel, with Tail1-6 (fox); Tail1-2, Neck1-3 and an optional `Antlers` part (deer); fawn = `Model:ScaleTo(0.55)` |
| Vehicles | body plus 4 wheel parts; `DriverSeat`, `LightBar`, `Headlights`, `TailLights`; logical box per [traffic §1] (sedan 2.35 x 4.45 x 2.04 u); **every player-enterable kind** (patrol car, golf cart, pickup, SUV, jet ski; the gondola cabin as a ride) has a modelled **interior and dashboard** with `DashSocket` (HUD inside the dash), `EyeSocket` (first-person camera, S14) and no see-through seams at eye level [brief v2 §14] |
| Paintball garb | three rigid accessory sets (mask, chest rig, pads) welded to the human garb attachments, each in four colourways with its own insignia and patches; no hitbox change; applied and removed through the D13 accessory path (S16) |
| Minigame props | bowling ball and 10 pins, cue and 16 balls, bumper-pool set, 3 darts and board, 54 Jenga blocks, volleyball and net, racquetball and racquets, 3 pinball cabinets, the fortune cabinet, the labyrinth board; each with its collision shape declared (sphere, box) because the physics games read it |
| Drone | body, `Rotor1`-`Rotor4`, `Camera` attachment |
| Building kits | pivot at lot centre on the ground; door hinge attachments; `RoofLanding` parts; Skyline part |

**Placeholders** are generated by `tools/placeholders`: R15 humans from stock descriptions in role palettes (officer navy and cap, hospital teal and white); animals as ellipsoid-part puppets whose Motor6Ds carry the final bone names, animated by the procedural backend (already more readable than the HTML's stacked spheres); vehicles built to the logical box; buildings as greybox lot types in flair colours. The procedural backend stays as a permanent fallback when a clip is missing.

### 5.3 Priority order and budgets

LOD0 triangles per MeshPart; Roblox caps a mesh at 20k [feas B.c]. Textures: 1024 px maximum per map for characters, 256-512 px for small props [feas B.g].

| P | Asset | Tris | Bones | Textures | Notes |
|---|---|---|---|---|---|
| P0 | **Squirrel** | body <= 8k + fur cards/shells <= 5k (second skinned MeshPart) + eyes | ~36 | body Color/Normal/Roughness 1024 (TintMask for A3); cards 512 alpha cutout | 7 stock furs [wildlife_foraging §2]; tail lag = 8 tail bones plus a client spring chain |
| P0 | **Spicy rodent** | own body <= 8k + sparse mange cards <= 3k | same skeleton | own 1024 set; emissive mask for the eyes | shares every squirrel clip; art direction §5.6 |
| P1 | **Human bodies x 6** (female slim, female full, male slim, male broad, older female, older male) | <= 10k each (head <= 3k) | R15 | shared UV layout; per-part colour textures 1024 (detail and AO baked in); skin = 8 tones via `MeshPart.Color` | "several adult body types"; the two older housewives of different appearance [brief §8] |
| P1 | **Role outfits x 13** (townsperson x 3 variants, police, nurse, doctor, guard, orderly, EMT, cyclist, jogger, mail carrier, shop staff, defenders, burglar) | n/a (textures) | n/a | one set per outfit on the shared UVs (6 bodies share it), 2 accent zones | Lane 4, headless; about 13 sets x 15 parts as 1024 images, uploaded through Open Cloud (well within 120 per minute) |
| P1 | **Hair x 8, role props ~20** | hair <= 2k; props 0.2-1.5k | rigid | 256-512 | cap, badge, belt, baton, ticket book, radar gun; stethoscope, clipboard; guard cap; EMT vest; mail bag; chef hat; barber smock; cyclist helmet; jogger band; rolling pin; broom; burglar beanie, sack, flashlight; 12 fetch items |
| P2 | **Fox** | <= 6k + cards <= 2k | ~34 | 1024 | stock #b8663c / #e4d6bc / #302c29 |
| P2 | **Deer** (doe; buck with antler accessory; fawn by scale) | <= 8k + antlers <= 1.5k | ~40 | 1024 + fawn spots variant | doe #ad845e, buck #946f4e, fawn #b99a70 |
| P3 | **Patrol car / sedan** (AI colour variants) **with interior and dashboard** | <= 6k + 4 wheels + interior <= 4k | rigid | shared 1024 trim + 512 liveries + 1024 interior | light-bar parts for the beacon blink; first person inside (S14) |
| P3 | **Player vehicles with interiors** (brief v2 §13a, §14): golf cart, pickup, SUV, jet ski; the sky-lift **gondola cabin** | cart 4k, pickup 8k, SUV 8k, jet ski 4k, cabin 5k, each plus an interior <= 4k | rigid | shared trim 1024 + one interior sheet 1024 | 6 pickups and 4 SUVs placed; the cabin holds up at eye level while moving |
| P3 | ambulance, ice-cream van, trolley, dump truck, RV, motorcycle, bicycle; **drone** | 8k, 8k, 10k, 10k, 10k, 4k, 2k; drone <= 3k | rigid | shared trim; drone 512 | logical boxes per [traffic §1]; rotors and wheels spin on the client; the bicycle is now rideable (a saddle socket) |
| P3 | **Trees** (oak, elm, sycamore, maple, willow, apple) | trunk + boughs <= 8k; canopy cards <= 8k (separate MeshPart, hidden in winter) | rigid | bark 1024, shared leaf atlas 1024 | meshes generated around each tree's route curves, so bark and rails always match; acorns and apples merged per tree |
| P3 | **Hollow trees**: H1 spiral, H2 shaft, **H12 escape (three knotholes and exits)**, 3 knothole variants, fallen log | premium shell <= 15k + interior <= 10k; escape <= 8k; knothole <= 6k; log <= 4k | rigid | bark 1024 + interior 1024 | §5.5; sockets and interior routes exported back into data |
| P3 | **Paintball garb**: 3 sets x (mask, chest rig, pads) x 4 colourways (green, blue, red, yellow) with insignia and patches | <= 1.5k per piece | rigid accessories | one 1024 sheet per set, recoloured per colourway | cosmetics only; rough is fine, the marker "can be generic and even silly-looking" |
| P4 | **Attraction interiors** (brief v2 §13a): corner store (1970s-style shelving, checkout, 22 item props), clinic (counter, table, two books, bead maze, labyrinth board), museum cases, **bowling alley** (lanes, pin decks, rack, scoreboards, overhead lights, arcade cabinets, the fortune cabinet, back-of-house doors, blue cans, broom), racquetball court, steakhouse (bar, glass, deck, sand, net), small mall and wind-tunnel cylinder, hilltop restaurant, antique curios, TV-station interior | <= 15k per building shell + fit-out 0.2-2k per piece | rigid | shared trims; 512 per prop | the ball-return tunnel is rendered "with great care" as a hero interior piece; **polish slots** for the bowling alley and every minigame table |
| P4 | **Lounge interiors x 2**: classic (leather, woodwork, fancy counters, bar) and sci-fi (lava lamps, dense plants, surreal fittings) | <= 20k each + props | rigid; Lane 3 if PBR | 1024 sheets | the "polish where people pay" slot (dec 23): extra lighting detail; locked first person, so eye-level detail matters |
| P4 | **Minigame props**: balls, pins, cues, darts, 54 Jenga blocks, 3 themed pinball tables, volleyball and net, racquets, the labyrinth | 0.1-3k each | rigid | 512 | collision shapes declared; the themed tables each get their own playfield art |
| P4 | **House kits x 8 archetypes** + furniture kit (~40-60 pieces) | <= 15k per assembled house; furniture 0.2-2k | rigid | shared 1024-2048 trim sheet + siding, brick, shingle tileables | generated from the archetype JSON; flair = module swaps plus recolours |
| P4 | storefront and restaurant kit; school, church, gas station; hospital and police fit-out; Quay kit (6 modules); Galleria shell | <= 15k per building | rigid | shared trims | recoloured per lot |
| P4 | street furniture: hydrant, stop sign, signal, **street lamp (post, head with an emissive face, flicker variant), porch lamp, shop-front sign with emissive**, pole, bench, bin, dumpster, feeder, garden bed, mailbox, fences, hedges, trampoline, tree-house kit, billboard, wanted poster | 0.2-2k | rigid | shared 1024 | wires are Beams, not meshes; lamps are placed by the compiler (D30) |
| P5 | backdrop: 3 mountain and hill bands, **fog cards** (layered, alpha gradient), tree-line cards, beach, ocean planes, pier, marina boats, radio tower, overflight airliner | <= 20k per tile, each tile <= 2048 st; tower <= 8k; plane <= 3k | rigid | aerial perspective baked in; fog cards 512 alpha gradients | `Persistent` |
| P5 | images: 16 moon phases (512), map render (2048), clothing templates, UI icons, sign atlases | n/a | n/a | n/a | Open Cloud image upload |

**Load check at peak:** about 15 squirrels x 13k plus up to 90 humans x 10k is roughly 1.1M triangles if all were visible at once; streaming and distance keep the visible set much smaller. Verified on low-end devices in W7; a squirrel LOD1 (about 4k, no cards) beyond 60 st is added if needed. **Art budget rule (brief v2 §15 dec 23):** no money is ever spent on art and no outside artist; everything is made procedurally in Blender by the coding session and approved by turntable; rough is fine; polish goes where people pay or play (both lounges, the paintball arena, every minigame); detail is high on the ridge and near town; the far distance is painted scenery.

### 5.4 Clips per rig

| Rig | Required | Utility (also authored) |
|---|---|---|
| Squirrel / rodent | The brief's seven [brief §7]: **Run** (ground; also roof, fence and branch at 0.7 cadence), **Climb** (trunk), **Wire traversal**, **Leap**, **Pounce** (with `Commit` and `Recover` markers), **Bite dance**, **Sneak**. State mapping per [routes_movement §19] | Idle, ClimbIdle, Land, Hit, Death, Forage, Deposit, Stink (squirrel), Chew, KnotholeEnter; Feint, StalkIdle, RunOverDeath (rodent) |
| Human (R15, shared by all 6 bodies) | Roblox stock locomotion | Kick (markers), Swing, Baton, Shove, Flinch, BackAway, Cower, PanicFlee, Disinfect, Pick, Carry, Deliver, WriteTicket, Talk, Argue A/B, Calm, RollingPin, Broom, DriveSit, EnterCar, ExitCar, Console, Restock, HideCrouch, SickIdle, BurglarSneak, KnockedDown; **rev 3:** Taunt, Vote (thumb), Mow, SpinSign, Wash, ThrowPaper, Serve, Bowl, Cue, Dart, JengaPull, Serve/Spike (volleyball), Racquet, PaintballAim, PaintballCrouch, Reload, Float (wind tunnel), RideSit, Squirt, Throw, BlowHorn, Sit (lawn chair and cafe), Egg, Knock, Companion walk |
| Fox | Idle, Walk, Trot, Run, Lunge | Stalk, Recoil, Sniff, Sit, Jump, Hit |
| Deer | Idle, Graze, Walk, Trot, Bolt | Startle, Leap, Alert, LookAround, LieDown |

### 5.5 Hollow trees: brief v2's 12 and the owner's variants, reconciled

Brief v2 §3 wants **12** claimable hollow territories: 2 premium (a spiral ramp with chambers at several heights; a straight climb-up shaft with a knothole exit and a hideout), **one escape tree with three apertures and exits**, and nine with a single chamber reachable from a knothole, plus the fallen hollow log as an extra hiding spot. Decision 19 is decided ("12 not 11"). The owner's three variants (shaft, spiral, log) are all present.

| Hollow | Site [wildlife_foraging §6.5] | Variant | How it satisfies both |
|---|---|---|---|
| H1 premium | park outer tree (90, 358), beside the Tabasco community garden and the premium feeder | **Spiral ramp** up the trunk centre; chambers at about 25 %, 55 % and 85 % height; base entrance and crown knothole | the brief's interior pathway with chambers; rebuilt at giant girth (r about 2 u, about 5 st) so the ramp fits |
| H2 premium | core SYCAMORE (-37, 29), garden plot and premium feeder nearby | **Vertical shaft** climbed on the inside with the Climb clip; side chambers; knothole exits at mid-height and crown; a **hideout nook** at the top | the owner's "climb up inside a hollow shaft with knothole exit and hideout nook", at premium scale |
| H3-H11 | bur oak, 3 giant trees, treehouse oak, Chili's sycamore, estate oak, Westside oak, Quay willow | **Knothole + single chamber**, a miniature of the shaft (short climb-up nook) | the brief's 9 single-chamber hollows |
| **H12 escape** (rev 3) | a core-grid oak chosen on the town-plan page, on a route island with at least three boughs | **Escape tree**: one chamber, **three knotholes**, each exiting to a different bough or the ground | brief v2 §3 "one escape tree with three apertures and exits"; a rodent refuge with three ways out |
| Log (shelter, not counted) | the v5.4 hollow log at (-19, 376) [wildlife_foraging §6.4] | **Fallen-log tunnel**: a ground-level `tunnel` route with two exits and a mid nook | "plus a fallen hollow log as an extra hiding spot": not claimable, so the count of 12 stays exact; rodent regen, a hide from the fox and a shortcut |

Chambers anchor the nut store; the meter, the 70 % ownership rule and the 3-day visit rule are per tree; claiming is proximity, with no scent-marking animation. The rodent regenerates inside any hollow and may rest in owned hollows (it cannot take nuts); hollows, the sewer, poles and trees are rodent cover, not just squirrel storage [brief v2 §8]. In the FRB all 12 are knothole plus a placeholder chamber (H12 with three knotholes); W3b adds the premium and escape greybox interiors and the log; W5 adds the art.

### 5.6 Art direction and the review loop

- **Overall:** semi-realistic, on the warm, hazy, low-saturation golden-hour suburb of v5.4 (median saturation 0.30; strong colour only on signs and toys) [worldgen_districts_art §14.1].
- **Spicy rodent (owner direction):** zombie-lite (mangy fur, stitched bald patches, a few ribs showing); **natural fur colours, no green**; a little blood on the muzzle and claws; a touch of horror; "cute but unhinged" with slightly oversized bloodshot eyes and a crazed buck-tooth grin. Blood amount follows decision 24; the red eyes survive the avatar blend.
- **Regular squirrels:** natural greys, reds and browns from the 7 HTML furs. Weight and presence come from a sculpted silhouette, a groom normal map, varied roughness, fur cards and a tail that lags the body; there is no fur shader [feas B.g; brief §7].
- **Humans:** every role outfit (townsperson variants, police, nurse, doctor, guard, orderly, EMT, cyclist, jogger, mail carrier, shop staff, bartender, lounge guard, instructor, the defenders, the burglar in neutral dark clothes) on all six body types, delivered as headless colour-texture sets on one shared UV layout (D22); police, doctors and nurses visibly distinct [brief v2 §13a]; stereotypes avoided.
- **The G2 pass bar (brief v2 §15 dec 23):** "rough is fine; what must be covered is contours, textures, colours, shading and shadows, and the basic movement set." G2 judges exactly those five things plus the clip set; nothing else blocks an import. **The polish list:** extra lighting detail in both lounges and the paintball arena, and every minigame's table, lane or court ironed out; the far distance is painted scenery; the ridge and anything near town get real detail.
- **First-person bar (brief v2 §14):** interiors, vehicles and the gondola must hold up at eye level: no see-through seams, no floating props within reach, readable dashboards; checked by raycast in `WorldBuild` and by the owner in first person during OS-5 and OS-5c.
- **Fur that catches light and muscle under the skin** [brief §7] are planned concretely: the body silhouette is built from anatomical volumes (skin modifier and metaballs over the skeleton, shoulder, haunch and neck masses), remeshed, then displaced with baked groom and muscle-definition normal maps; roughness varies by fur length; fur cards on a second skinned MeshPart; weights painted for volume preservation at the shoulders and haunches; the tail's lag comes from 8 bones plus a client spring. G2 judges the result on turntables and a clip contact sheet; if it misses, decision 23.
- **Honest limit and the loop.** Headless Blender cannot hand-sculpt or judge look-dev in a viewport [feas]. Claude builds procedurally (skin modifiers, metaballs and remeshing with displacement; textures and masks baked from procedural shaders; fur cards from particle hair; clips keyed from parametric gaits refined against reference timing). Every asset ships turntables and a clip contact sheet for G2. **There is no artist fallback** (brief v2 §15 dec 23: no money, no outside artist): if an asset misses the bar at G2, Claude iterates procedurally and, failing that, ships rough; the owner has accepted "rough is fine" as the bar.

### 5.7 How assets reach Roblox and git

| Item | Into Roblox | Into git |
|---|---|---|
| Blender sources | n/a | `blender/<asset>/*.blend` and `build.py` (LFS for `.blend`) |
| Exported FBX (brief §14 deliverable) | Lane 2: Claude uploads through Open Cloud; Lane 3: the owner imports in the Art Inbox | `blender/<asset>/export/*.fbx` (LFS) |
| Clips | KeyframeSequences built by Lune, uploaded by Claude as Animations (S7); fallback: owner Animation Editor import and publish | `clips/*.json` and `assets/anim/*.rbxm` (small, not LFS) |
| Images (moon, map, clothing, signs) | Claude uploads through Open Cloud | generator scripts in `tools/textures`; outputs regenerated |
| Asset IDs | n/a | `data/assets/manifest.json` (harvested by Luau Execution where possible) |
| Studio-made instances (imported rigs with SurfaceAppearance) | loaded at runtime by ID | captured into `art_captures/*.rbxm` (outside `assets/` and in no project file, so it never enters a build; invariant 14) with **`rojo syncback`** (rules limited to `Workspace.Inbox`) from the Art Inbox place file: downloaded headlessly if S8(d) passes, otherwise uploaded by the owner through GitHub's web "Upload files" once per batch |

**Moderation rule:** every upload is moderated; `tools/cloud` polls each asset's status into the manifest (`pending`, `approved`, `rejected`), the runtime never shows a pending or rejected ID (placeholder instead), and owner builds list any non-approved asset in their release note (F-9).

**Ownership rule:** the experience, every model, every animation and every image share one creator (the experience owner, user or group). Claude reads the creator in W0 and uploads under it; the owner's Save dialogs use the same creator. The engine `Assets` suite catches mismatches ("Failed to load animation") [feas Blocker 7].

**Studio-edit rule:** the owner never saves edits into the main place or the CI place, and Team Create stays off on both (F-11); all Studio-made content goes into the Art Inbox. Claude's saves therefore never overwrite owner work.

---

## 6. Testing and verification

### 6.1 Static checks (every change)

`stylua --check` (built with `--features luau`); `selene` with the committed `roblox.yml`; `luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=sourcemap.json src/` in GitHub Actions (strict, 0 errors); `rojo sourcemap` regenerated by CI.

### 6.2 Lune unit tests (`tests/unit`, in the container on every change)

| Area | Asserted |
|---|---|
| Units, Tunables, Schema, Net | every tunable has a unit and a source; no NaN; schema round trips; malformed packets rejected; buffer codecs round trip and stay under payload caps |
| Data validators | the §3.13 invariants that do not need the compiler graph; unique IDs; cast homes exist; forage and hollow anchors on walkable ground; lanes on roads |
| `World/Height`, `World/Ground` | golden vectors (tolerance 1e-6); `groundAt` pure in `(x, z, refY)` |
| `Routes/*` | golden `getPointAt`/`getSpacedPoints` for 200 random routes (0.01 u); harvest regression counts; `advance` golden; auto-switch at <= 0.48 u; junction choice; serialize -> deserialize resumes identically (the mid-stride property) |
| Motors | leap apex 2.73 u continuous (about 0.1 lower at 60 Hz, as expected [routes_movement verifier 10]); speed caps, turn rates, ground snap; determinism under fixed dt |
| `Traffic/Swept`, `LaneMath` | 10,000 JS vectors plus hand cases (jump over a sedan, under a trolley, 180-degree flip, start inside); broad phase never rejects a true hit; no trolley-versus-westbound deadlock; stop-line FSM |
| `MoveValidator` | honest traces: 0 violations; cheat harness: >= 95 % flagged within 1 s |
| `Ladder` | one test per rule row; properties: a player is always in exactly one rung; caps never exceeded outside the Lab (humans past 35 only while other slots are unheld; never more than 49 players); side exits restore the remembered rank; killer promotion order (driver included); the 30 % rule uses this rodent's own tally; rodent offer versus re-entry timing (S-10); keys change hands only when parked (patrol cars and the human drivers' pickups and SUVs); the outbreak winner keeps the rodent and surviving infected squirrels keep squirrel bodies; **rev 3:** the human queue score is time + money + reputation + entourage + kicks + quests and the administration score ignores money; unranked below 10 in-game days; recruitment cascades by seniority; rodent death drops infected squirrels and resets infection; a killed infected squirrel recycles its player and promotes hospital before police; the officer who hits a pedestrian loses keys, sits in a cell and lands at lowest rank; **no ladder literal anywhere else in `src/` or `data/`** |
| `Population`, `VigilanteRules` | floors never broken by 1,000 random joins, leaves and promotions up to **49** players; police >= 6 and hospital >= 10 AI at every step; supply order (above-floor, re-post, reserve, hard-cap floors; police and hospital floors never cut); 16 paintball bots borrowed and returned without breaking a floor; the vigilante share is `round(0.08 x humans)` after every change, flags only on AI bodies |
| `PowerRules` (golden from `updatePowerAndHeat`) | +100 / +150 / +130 / +90 once per squirrel / -19 / -12; the 15 % fade rounded up after 10 **active** minutes, repeating; a bite resets the fade; never below 0; chilis, coins, climbing and missed pounces leave it unchanged; stage labels at 600 and 1,500; **the fade never advances on game-clock time alone** (two clocks, rule 11) |
| `EconomyRules`, `ReputationRules`, `GigRules` | integer cents everywhere; wages per in-game hour at the minimum and above; prices from data; product tiers are whole Robux; `receiptKey` idempotent on repeated receipts; vote caps 5 + 5 per in-game day, weights clamped, a brigade of 20 zero-reputation voters moves a target less than 3 honest votes; cafe tick; gig quality to tip (>= 0.9) and ding (< 0.4); entourage term |
| `ForageRules` (rev 3 rows) | carry cap 9; a claim at 70 % lapses after 3 in-game days without a visit and holds with one; season stock depletes and refills at season start; invariant 15 arithmetic |
| `MinigameRules/*`, `PaintballRules`, `VehicleKinds`, `CameraPolicy` | each game's state machine rejects out-of-turn and out-of-range input; bowling frames, darts 501 and cricket, 8-ball fouls, Jenga turn order, labyrinth bindings fixed; the magazine (5, auto and manual reload), projectile drop, a rewound hit at 150 ms; who may drive what; the camera mode for every role, vehicle and zone combination |
| `Profiles` serialiser | round trip of every profile field; version migration; a corrupt blob yields a read-only session, never a default wallet |
| `UpgradeRules`, `Recovery` | availability by tier, pooled purchase, effects applied once; river fall lands on the nearer quay; last safe position is on walkable ground; a car moving from under a squirrel sets it down beside the car |
| `CombatRules` | pounce velocity golden; wind-up, commit, recovery; bite chance by awareness; two kicks inside the regen window kill; defender x1.5 one-shots at low health; "biting into a raised arm or kick fails"; **rev 3:** the drain removes 1 hp per in-game day and never on real time alone (two clocks); bites heal 10 and 20; the alert-zone kick multiplier stays below the one-kick-kill line; the second-bite penalty inside a fresh zone; infected squirrels take two kicks, healthy ones none; the water-gun stun fires once per player |
| `InfectionRules`, `ForageRules`, `Calendar`, `Moon` | squirrel share (25/7, cap 25, gates); critical mass; cure multiplier; yields and cooldowns on the game clock; 70 % ownership; stink fire at >= 95 % costs 30; winter week 6 of 6; survival threshold; phase index at days 0, 7.4, 14.8, 22.1 |
| `BlendRules` | saturation <= 0.55 and value 0.39-0.91; at most one neon accent; rodent eyes unchanged; bizarre detection on the sample set; hitbox untouched |
| `QuestTypes` | step validators; reward computation |

### 6.3 Golden vectors from the original game

`tools/golden` runs functions lifted from `reference/v5_4_game.js` in Node with the inlined three.js r160 on fixed and random inputs and writes `tests/golden/*.json`. The Luau port must match. This is the strongest guarantee that "the HTML is the reference for mechanics" [brief §1] survives the rewrite, and it extends cheaply to any other pure function.

### 6.4 Compile, bake and place tests (Lune, every build)

- The §3.13 invariants; generated output not stale; reports diffed against spec counts.
- Bake determinism: two runs give the same `BakeHash`; per-district instance and triangle budgets.
- Place tests on the built `.rbxl`: project-file properties (§1.2); every body template has a `PrimaryPart` and `Atomic` mode; every lot Model has its sockets and the SLIM flag where configured; **no SurfaceAppearance, union or BaseWrap in the place** (keeps Open Cloud publishing valid); nothing from `art_captures/`; `EngineTests` absent from owner and live builds; every building Model carries the `LevelOfDetail` its data asks for.

### 6.5 Open Cloud Luau Execution suites (`tests/engine`, real engine, headless)

**Runner:** `rojo build ci.project.json` -> save an unpublished version of the **CI place** (through the shared cloud lock) -> 2-3 tasks per run ("fast", "sim", optional "assets"), each pinned to the saved version ID -> poll -> parse the JSON return and logs -> fail on any failure. Limits: 5 creates per minute, 10 incomplete per place, 5 minutes per task, 4 MB return, 450 KB logs; physics does not run and scripts do not auto-run, which suits steppable, kinematic services. Results go to `build/reports/*.json` and the commit message. **An owner build is only saved from a green run.**

| Suite | Task | Proves |
|---|---|---|
| `BootSmoke` | fast | every ModuleScript requires (the type-checker stand-in); the remote table builds; project properties are as set |
| `DataIntegrity` | fast | generated data decodes; counts match the reports |
| `WorldBuild` + `BakeParity` | fast | Plan -> Instantiate in the engine: counts, doors, prompts, colliders; interior nav reachability; route samples on geometry (raycast within `surfaceRadius + 0.3 u`); Skyline; streaming modes; runtime bake hash equals the Lune bake |
| `Terrain` | fast | `TerrainBake` on 3 districts; `ReadVoxels` matches `Height.at` within 1 voxel; timing recorded |
| `Actors` | fast | spawn every species; possess and release through `PlayerLike` stubs (anchoring, ownership bookkeeping, attributes, look applied and reverted); death and replacement keep species counts |
| `Assets` | assets | every non-zero manifest ID loads (`LoadAsset`, `GetKeyframeSequenceAsync`); moderation status recorded and non-approved IDs fall back; rig contracts hold (bones, sockets, separate tint-zone MeshParts, triangle budgets) |
| `Avatar` | fast | trait fetch for fixed public UserIds; `GetProductInfo` colour words with the cache; face decal and rigid accessory transfer; compose on every species |
| `SimFull` | sim | 5 simulated minutes at the full standing population, 60 Hz, fixed seed, one task (no hand-off between tasks, S-12). Liveness (every actor moves; no stuck vehicle over 60 s unless parked; no NaN; nobody outside the clamp). Gameplay (an AI rodent bite; a cure; a sighting; a quest spawned; swept hits only on roads; floors held). Budget (AI < 4 ms per frame average, < 8 ms p99, from `os.clock`) as a **regression signal**; the live MicroProfiler in W7 is the gate (F-14) |
| `SimLong` | sim | 40 simulated minutes at 1/15 s with a quarter population, one task: liveness, counts stable, events fire, one accelerated winter |
| `LadderE2E`, `RodentLoop`, `Traffic`, `Quests`, `PoliceCoord`, `Upgrades` | sim | scripted event streams through `RoleService` with stub players, including a **49-player fill** that keeps 10 AI hospital staff and 6 AI police; bite -> admit -> cure; rodent death resetting infection; indoor chases to each escape outcome; crime scenes and alert zones; the rabid deer; squirrel kills and recycles; 120 s traffic with 0 deadlocks, stop-sign compliance and **player-vehicle violations ticketed, a pedestrian hit admitted, an officer demoted**; quest and gig lifecycles; tier-3 versus tier-1 police catch rates; upgrade purchase and effect |
| `Cap49` | fast | the project file says `MaxPlayers = 49`; `Ladder.server.maxPlayers` agrees; 49 stub players all get walking bodies; the population floors hold; no code path refuses a join below 49 |
| `Minigames` | sim | for every game: determinism (same inputs, same result, twice), physics stability (no part leaves its table or lane in 10 simulated minutes; a 54-block Jenga tower stands 60 s), scoreboard equals the rules module over 50 scripted games, out-of-turn input rejected, and (shared-table class) the server replay agrees with the shooter's reported outcome within tolerance |
| `Paintball` | sim | the S18 harness inside the full population: 16 stub players and 10 bots, 200 shots at 150 ms simulated latency, 95 % hit agreement with the shooter's view; magazine and reload; splat pool never exceeds its cap; the arena adds under 1.5 ms per frame; a player leaving mid-match returns to town with the pass intact |
| `Economy` | fast | wages accrue per in-game hour; counter purchases debit cents; **`ProcessReceipt` is idempotent** (the same `PurchaseId` three times credits once and returns `PurchaseGranted` each time); a receipt during a profile lock is retried, not lost; the product table matches the owner's Creator Hub IDs |
| `Persistence` | fast | load, mutate, save, reload across two simulated servers with the session lock contested; `BindToClose` flush; version migration; a corrupt blob gives a read-only session; Open Cloud DataStore read matches the in-engine write |
| `OutbreakCinematic` | sim | critical mass arms the director; phases run on `Clock.setRate`; every squirrel body enters `OutbreakSweep`; the lighting state is `Outbreak`; the reset fires after `cinematicSecs` with the winner keeping the rodent and surviving infected squirrels keeping squirrel bodies; a client that reports no cinematic support gets the end card |
| `Rides`, `Items`, `Lighting` | fast | board, path, exit and camera mode for each ride; each of the 22 items' server effect; the lamp count per block, porch lights on every house, the flicker fraction, the Skyline heads present |

**Cadence:** every wave sub-step exit, before every owner build, and (optionally) nightly through W3-W4 as a scheduled task. Every task is pinned to the version ID its save returned, and all calls share the cloud lock (S-13).

### 6.6 Owner sessions and playtest scripts (click by click, few)

**Format of every checklist:** one action per line, an expected result and a pass/fail box; delivered as a shareable checklist page plus `docs/playtest/<build>.md`. Each build re-runs the FRB set as regression after a 15-minute **smoke** pass. Studio labels are re-verified in each checklist at the time, because Studio menus move.

| Session | When | Length | Steps |
|---|---|---|---|
| **OS-0** | Step 0 | 20 min chat + 17 min web + 2 min Studio | confirm the open items in section 8 (37-44) or let the defaults stand; skim section 0. Then on the Roblox website: (1) **create.roblox.com** -> **Creations** -> "Spicy Rodent" -> **Places** -> **Create a place** -> name it "CI"; repeat for "Art Inbox" (or in Studio: **View -> Asset Manager -> Places** -> right-click -> **Add New Place**, then rename). (2) "Spicy Rodent" -> **Configure** -> **Places** -> the start place -> **Max Players** -> **49** -> Save. (3) "Spicy Rodent" -> **Monetization** -> **Developer Products** -> **Create**: three products with the names and Robux prices Claude gives ("100 Spicy Dollars" 25 R$, "400 Spicy Dollars" 100 R$, "1,600 Spicy Dollars" 400 R$; Q19); Claude reads the IDs. (4) Open Studio once -> open "Spicy Rodent" -> **File -> Collaborate**: if it says Team Create is on, ask Claude before changing anything (it should be off); then **Home -> Game Settings -> Security -> Enable Studio Access to API Services -> On -> Save**. Tell Claude "places done". (Labels are re-checked by Claude on the day, because the website moves.) |
| **OS-1a** | end of W0 | about 20 min | Studio start page -> "Spicy Rodent" -> **Test** -> 2 players -> **Start** -> follow the 6-box possession checklist on screen (take over a walking person, a running squirrel, release, swap, look at the other window), ride a trunk and a wire, get run over by the test car, look at the arrow, watch the test clip, press Esc -> Reset once. Close Studio without saving |
| **OS-1b** | end of W0 | about 10 min | Open "Art Inbox" -> **File -> Import 3D** -> `squirrel_test_rig.fbx` (Claude names the file and where it is) -> Rig Type **Custom** -> **Import** -> right-click the model -> **Convert to Package** (creator = the experience owner) -> **File -> Save**. Tell Claude "done" |
| **OS-1c** | end of W0 | about 10 min | Roblox app or website -> "Spicy Rodent" -> **Play** (a private test town) -> press **F** to fly the test drone -> go up to 300 studs (the HUD shows it) -> look at the centre and the four corners -> tick the 4 boxes on screen |
| **OS-1d** | after OS-1a-c | 10 min, web | read the one-page spike report; say go (G0) |
| **OS-2** | end of W2 | 60-90 min | FRB checklist (§4.7): roles 1-4, then roles 5-8 and the multi-client set (Test -> 3 players) |
| **OS-3** | start of W3 | 30 min, web | approve the town-plan page (the 40 homes, defenders, restaurants and shops, the 12 hollows, and brief v2's 12 sites: steakhouse, hill with sky lift and hilltop restaurant, TV station, bowling alley, new mall, both lounges, corner store, doctor's office, museum, racquetball court, off-road zone) and the squirrel/rodent turntables (G2) |
| **OS-4** | W3 | about 20 min (+30 min if S7 failed) | Art Inbox: import the squirrel and the rodent as in OS-1b (2 rigs); Save. **If S7 failed**, for each of about 20 clips: **Avatar** tab -> **Animation Editor** -> select the rig -> "..." -> **Import** -> **From FBX Animation** -> pick the file Claude names -> "..." -> **Publish to Roblox** (creator = the experience owner); about 1.5 min each |
| **OS-5** | end of W4 | about 60 min | build #2: smoke, FRB regression, new scenario checks (alert zone, rabid deer, a Robux test purchase in Studio, a speeding fine and a cell, the outbreak cinematic through the Lab) |
| **OS-5b** | end of W4 | about 60 min | **Paintball playtest (G-PB)**: Test -> 4 players -> LAB -> "Open paintball match" -> two windows per team plus bots; the checklist asks about travel and drop, the five-shot magazine and reload, hits landing where you aimed, splats staying, sprint and crouch, the five floors and atrium, the timer, scoreboard and end card, fire and hit sounds. The last box is the verdict: keep / fix this list / cut. The verdict goes into `docs/DECISIONS.md` |
| **OS-5c** | end of W4b | about 90 min over two sittings, plus 20 min | build #2b: one 10-15 minute check per minigame in the ironing-out order (bowling, darts, pool and bumper pool, pinball, racquetball, volleyball, Jenga, the labyrinth with its fixed controls), each with three boxes ("feels right", "controls do what the brief says", "I would play it again"); then a 20-minute walk through the attractions (buy and use items, one gig of each kind, the sky lift to the hilltop, parasailing, the wind tunnel, a jet ski, a lounge in first person, the kite) |
| **OS-6a** | W5 | about 15 min (+30 min if S7 failed) | Art Inbox: import the fox and the deer (Rig Type **Custom**); Save. If S7 failed: their about 21 clips as in OS-4 |
| **OS-6b** | W5 | about 15 min (+45 min if S7 failed; +25 min if D22 fell back to (a)) | Art Inbox: import the 6 human bodies (Rig Type **R15**); Save. If S7 failed: about 30 human clips as in OS-4. If D22 fell back to (a): import the outfit pack Claude names (one SurfaceAppearance per outfit) and Save |
| **OS-6c** | W5 | about 25 min | Art Inbox: import the 2 premium hollow trees, the escape tree and the two lounge interiors if they carry SurfaceAppearance; Save |
| **OS-7** | W6 | 30 min | LAB -> "Set time 18:40": tower silhouette from the ground and the drone; fog layers; drone corners at 300 st; LAB -> "Set time 22:00": the lamplit town from the drone and from the hilltop restaurant (ride the gondola up); LAB -> "Trigger outbreak": the cinematic by night and by day |
| **OS-8** | W7 | 60-75 min | private-server session with friends from the Roblox app; tester checklist; maturity questionnaire; approve the publish; set public when ready |

**Bug capture:** LAB -> **Report** copies role, position, recent log lines, the tunables diff and the place version as text for the owner to paste to Claude.
**Feel tuning:** during any playtest, the Server window's Explorer -> `ReplicatedStorage -> TunablesLive` -> change an attribute in Properties; afterwards LAB -> **Export tuning** and paste the text to Claude.
**Studio test avatars** have negative UserIds, so the real 70/30 blend is checked with the Lab's sample avatars until the live session in W7.

### 6.7 Definition of done (per change)

`stylua --check` -> `selene` -> Lune unit and golden tests -> compile (invariants, not stale) -> bake -> `rojo build` -> place tests -> (engine-relevant changes) CI-place save and the engine suites -> commit and push. GitHub Actions adds strict `luau-lsp analyze`. An owner build is cut only when all are green and the wave's checklist has been self-checked by the headless suites.

---

## 7. Risks and mitigations

| # | Risk | Likelihood / impact | Mitigation | Trigger and fallback |
|---|---|---|---|---|
| 1 | **Mid-stride possession** misbehaves (lost control after setting `Character`, pops, T-pose, bodies destroyed, camera on non-Humanoids) [feas B.a, medium-high confidence] | M / Critical (hard brief rule) | S2 first, on a spike place; `PlayerCharacterDestroyBehavior = Disabled`; snapshots with velocity and clip time; client-local animation (D3); stream-around; bodies never die in the engine | S2 fails -> blink handoff; Server Authority for animals when out of beta; decided at G0 |
| 2 | **Client-owned movement** feels floaty, is cheatable, or the server sees stale positions so bites and run-overs feel unfair | M / H | shared pure motors; cheat harness and honest traces in CI; validation log-only until W7; teleport flags; RTT-widened windows; pose rewind in W7 | FRB complaints -> pull W7 lag compensation forward; server-authoritative rail with prediction |
| 3 | **Server CPU and bandwidth** at about 90 human Humanoids (49 players plus brief v2's floors and attraction staff), 8 riders, about 22 animals, about 45 vehicles, a 16-body paintball match and 49 players | **M-H / H** (the floors rose from 5 to 16 and the attractions add posts) | kinematic anchored AI; `EvaluateStateMachine` off; LOD tiers with the drone as focus; ghost vehicles; client-only ambient life; borrowed bodies for drivers, bots and staff (D25); no animation replication; `SimFull` regression signal from W1; S19 at the worst case | budget miss -> Parallel Luau perception; state-stream rendering for Mid/Far; non-Humanoid rigs for silent posts; cut street, shop and attraction floors first and the brief's police and hospital floors never; the live MicroProfiler in W7 decides |
| 4 | **Semi-realistic hero art from headless procedural Blender** misses the bar (fur, muscle, tail lag, faces) | H / **M** (the owner has lowered the bar: "rough is fine") | contracts and placeholders mean gameplay never waits for art; G2 turntables judged against the five-point bar of §5.6; budgets enforced by script; hero art pulled forward; polish budget spent only on lounges, arena and minigames | G2 fails -> iterate procedurally, then ship rough; **no artist and no money, by the owner's decision 23** (the revision-2 fallback is withdrawn) |
| 5 | **Asset pipeline unknowns:** headless clips (S7), Lune-written MeshParts, runtime SurfaceAppearance tint (S8b, S8c2), the outfit path (S8e), PBR on Lane-2 kits (S8a, S8f), ID harvesting, ownership mismatch | M / M | spikes in W0; one creator for everything; the engine `Assets` suite; D22 avoids SurfaceAppearance on humans | S7 fails -> owner clip imports (budgeted per session, §6.6); S8c2 fails -> pre-authored fur variants; S8e fails -> D22 fallback (a) or (b); runtime kit swap plus plugin bake before a Studio publish |
| 6 | **Breadth versus depth:** eight roles in the FRB could each be shallow or buggy | M / M | explicit thinnest loops and owner-runnable checks; Role Lab; depth by wave with G1 priorities; the regression rule | FRB failures fixed first in W3/W4 |
| 7 | **Open Cloud availability and limits:** the luau-execution scope is still being corrected; 5 task creates per minute; 10 incomplete per place | M / M | Lune-only work proceeds meanwhile; batched suites (2-3 tasks per run); polite polling; a separate CI place | scope delayed -> engine tests run in owner playtests until fixed; GitHub Actions runner with the key as a secret |
| 8 | **GitHub push not yet available** (App connection being finished) while the container is ephemeral | M / H (lost work) | W0 code starts only once push works; push at every task boundary | n/a |
| 9 | **Data-driven town versus SLIM, boot time and the drone view** | M / M | Lune bake into the saved place; Skyline from the FRB; terrain hash check; S6 timing | terrain fallbacks (D6); Skyline-only far view |
| 10 | **No Luau type checker in the container** [feas A4] | H / L-M | `--!strict`; GitHub Actions `luau-lsp`; `BootSmoke` in the engine; broad unit tests | container source build if allowed |
| 11 | **Content and policy:** blood and horror, the v5.4 swearing, possessable children, burglar portrayal, player-written chalk text, a "slot machine", Robux products | M / M | mild rating with the lines **rewritten** to keep the venom and lose the vocabulary (dec 24); kids and the mime AI-only; neutral burglar; blood as a flagged decal set; chalk through `TextService` filtering; the fortune machine styled as a fortune-teller cabinet with no money in or out (Q20); products as plain currency packs; no lottery or gambling items | questionnaire result -> tone the rodent texture variant down by flag; fortune cards instead of reels |
| 12 | **Ephemeral container and large binaries:** tool setup about 10 minutes per fresh container; Git LFS quota | H / L | environment setup script; LFS only for `.blend`, FBX and source textures; `git lfs pull --include` per task | LFS data pack (decision 5) or exports regenerated by script |
| 13 | **Tuning drift from scale:** the brief's 1.2-st squirrel is about 1.6-2x larger relative to humans than the HTML's, so radii, offsets and cameras change [routes_movement §20] | H / M | everything a tunable with source; owner live tuning; contact radii tested against the new mesh | decision 8 |
| 14 | **Day length:** 72 s days make linear sunsets last seconds | H / L | non-linear day curve | decision 10 |
| 15 | **Studio test players have negative UserIds**, so the real blend is untested until live | H / L | Lab sample avatars; S9 in Luau Execution; W7 live session | n/a |
| 16 | **Queue scarcity:** Roblox opens servers on demand, so the rodent queue may never be "real" [brief §5] | M / L | server fill to the maximum (decision 26); the queue is per server; the owner is told plainly that Roblox cannot cap the server count (§2.1 deviation 4) | matchmaking with reserved servers (TeleportService), much later |
| 17 | **Owner bandwidth:** too many Studio steps for a non-programmer | M / M | place built and saved from git; open from the start page; Studio sessions split so none is longer than about 20 minutes plus budgeted fallbacks (§6.6); automated stand-ins (fake drivers, synthetic population) | any blocked step becomes a guided, screen-by-screen session |
| 18 | **CI saves overwrite owner work** (including Team Create autosave) | L / M | the owner never saves into the main or CI places; Team Create off on both (F-11); Studio content only in the Art Inbox | `rojo syncback` capture |
| 19 | **Moderation** holds or rejects uploads (blood and horror on the rodent most likely) | M / M | manifest `pending`/`approved`/`rejected`; placeholders never blank; blood in its own small texture (F-9) | a rejected texture ships without blood; decision 24 tones it down |
| 20 | **Audio upload cap** (10 per month, 100 if ID-verified) | H / L | the licensed audio library first; at most 10 signature uploads (D24) | owner uploads in Studio; decision 30 |
| 21 | **GitHub App cannot push workflow files** | M / L | checked when the App connection is finished (F-10) | the owner pastes `ci.yml` once in GitHub's web editor; until then strict type checks run only in `BootSmoke` |
| 22 | **Body budget at full occupancy** (every one of 49 players a human before promotions, on top of the brief's floors) | M / H | posts, floors, re-posting, a parked reserve, a hard cap that serves 57 humans (§1.5, D23); `LadderE2E` 49-player fill; `Cap49`; FRB check M9 | lower cap -> "finding you a place" wait plus side-exit offers |
| 23 | **The drone's far view** fails on a published server (streamed-out terrain, SLIM timing, focus), now also at night (lamps) and over the extended footprint | M / H (the brief's showcase role) | S11 in W0 on a published private place with the hill, the off-road strip and emissive lamp heads; `ReplicationFocus`; Skyline from the FRB; SLIM flags from W1 | ground tiles as primary (D6); Skyline-only far view; Neon heads only |
| 24 | **Data loss or double-crediting in the DataStore profile** (rev 3; the project's first real persistence risk): a Robux purchase lost on a server crash, a receipt credited twice, a session lock stuck | M / H (money and policy) | S15 before any product is live; the receipt ledger inside `ProcessReceipt`; ProfileStore-style session locking; `BindToClose` flush; a Lune-tested serialiser with versions; read-only session on failure; `Persistence` and `Economy` suites; an Open Cloud DataStore read in CI | a community ProfileStore module; products switched off until fixed; manual grants by the owner through the Creator Hub for any disputed receipt |
| 25 | **Physics minigames feel wrong online** (rubber-banding, pins that jitter, a Jenga tower that collapses on its own) | M-H / M (ten games; the owner's rule is "ironed out") | S13 chooses authority per stakes class; the `Minigames` suite (determinism, stability, replay); one owner check per game (OS-5c) with a fix list | client-only physics with sanity checks; shared tables turn-based with server replay; a game that cannot be ironed out ships as a toy without a scoreboard, by the owner's call |
| 26 | **Paintball is cut** at G-PB ("Ben will not keep a weak version") after an L-XL of work | M / M (scoped by the brief) | mechanics before looks (generic marker, greybox arena); S18 proves hit registration in W0; the owner plays it in W4 with a named fix list before the verdict; the lounges' access pass does not depend on the arena staying | the TV station stays as a climbable shell; garb becomes fashion-stand cosmetics; the pass unlocks only the lounges |
| 27 | **Light count and mobile performance** with lamps on every block, porch lights, shop fronts, flashlights and lounge lighting | M / M | S17 at 300 lights on Future and ShadowMap; the client radius rule; `Shadows = false`; emissive heads for distance; `Lighting` suite counts | smaller radius; fewer real lights per block; Neon-only beyond 100 st |
| 28 | **Time-scale cadences** written in in-game days against a 72-second day (3-day hollow visits, 5-day passes, daily votes, a 10-day rank gate) feel frantic or trivial | H / L | every cadence a Tunable on the game clock; Q2 put to the owner; re-tuned in the FRB | the owner names a longer day or a per-rule multiplier; one constant each |
| 29 | **Scope roughly doubles** (delta §3.1) while the container, the two tracks and the owner's time stay the same | H / M | the two new waves run on the existing tracks; frameworks before content (rule 13); content as data; knobs 6 and 7; the honest size table in §4.14 | the owner reorders or trims W4b content at G1 or after OS-5c; nothing in W4b blocks the roles or the release |

---

## 8. Owner decisions: answered by brief v2, and the few still open

**Status after brief v2 §15 (rev 3).** The owner answered the 36 decisions on 8 Nov: 13 explicitly (10, 11, 12, 13, 14, 18, 19, 20, 23, 24, 28, plus the rides-versus-minigames rule and fog in W6), the rest by the rule "where a default is not named here, accept it (drive on the right, north is +Z, squirrel 1.2 studs at the shoulder, type checking in CI)". Four accepted defaults are overridden indirectly by v2's own text and are marked **amended**: 15 (hospital strictly outranks police for an open squirrel slot; the killed-squirrel recycle), 16 (5 deer; deer biteable late), 27 (saving is now mandatory for purchases) and 29 (no tinting for humans). Decision 30 was answered in Addendum B2. Each decision below keeps its original text for the record, followed by **DECIDED** and the owner's wording where there is one, or **accepted by default**. The genuinely open items are **37-44** at the end; every one has a default the build proceeds on, so nothing stalls. Already decided and not repeated here: the repo, the Open Cloud key, the experience and its IDs, the art direction, the wish for all three hollow variants, and holding this order-of-operations discussion before committing.

**Step 0 (before W0)**

1. **Wave order and knobs.** Default: as in §4, with hero squirrel and rodent art imported right after the FRB (knob 1 on). **Accepted by default** (rev 3 adds W3c/W4b and knobs 6-7 on top; knob 5 withdrawn by dec 23).
2. **Two extra places** ("CI" and "Art Inbox") inside the existing experience. Default: yes, added **in Step 0** (OS-0, about 5 minutes on the website), because places cannot be created through Open Cloud and the W0 spikes need the CI place. Claude then confirms with one call that the existing key reaches them; if the key is scoped to named places, the owner adds the two (about 2 minutes). Team Create stays off on the main and CI places. Fallback: one place, with Claude re-saving the owner build after each test run. **Accepted by default.**
3. **GitHub Actions for type checking** (`luau-lsp`) on the private repo. Default: yes (free-tier minutes are enough). If the Claude GitHub App lacks the "workflows" permission, the owner either grants it or pastes `ci.yml` once through GitHub's web editor (Claude provides the text). **Accepted by default** ("type checking in CI" is named in §15).
4. **Cloud environment setup script** so each new session starts with the tools installed. Default: yes (one approval prompt). **Accepted by default.**
5. **Git LFS** for `.blend` files, FBX exports and source textures (a paid data pack may be needed later). Default: yes. **Accepted by default.**
6. **Spike sessions before the big build** (OS-1a-c, about 40 minutes in three sittings). Default: yes, rather than discovering a failed spike after the FRB is built on top of it. **Accepted by default**; rev 3 adds spikes S13-S20 to the same three sittings.

*Added in revision 2 (also Step 0):*

28. **Human player slots and full servers.** Revision 2 default: the brief's 35 human slots **include** the 5 hospital and 5-8 police slots. **DECIDED** (brief v2 §15: "28, player slots: server caps at 49 (section 5). No late-joiner overflow"; §5: "35 humans (hospital and police slots are inside the 35), 7 regular squirrels, 1 spicy rodent, 5 deer, 1 fox. When it is full it is full; late joiners wait for the next server. No overflow roles, no spectator birds"). Effect: `MaxPlayers = 49` (owner, OS-0); the overflow design of revision 2 is retired and the posts-and-floors mechanism keeps serving humans past 35 inside the 49 (§1.5, D23); standing bodies rise to the brief's floors (6 police, 10 hospital, crews extra).

**Before W1 (shape of the world)**

7. **Compass and backdrop.** Default: north = +Z (matches the district names); ocean to the north at the Willow River mouth with the marina near (850, 480); mountains, hills and plains south and west; the tower 1.5-3 km out on the measured sunset azimuth [worldgen_districts_art §14.4]. **DECIDED** by name in §15 ("north is +Z"); rev 3 adds the hill with the sky lift, the ridge and the off-road zone to the footprint (D32).
8. **Squirrel size.** Default: the brief's 1.2 studs at the shoulder, with radii re-tuned in playtests. **DECIDED** by name in §15 ("squirrel 1.2 studs at the shoulder").
9. **Traffic handedness.** Default: drive on the right everywhere [traffic §14 Q1]. **DECIDED** by name in §15 ("drive on the right").

**Before W2 (rules the FRB plays by)**

10. **Day length.** Default: 72 real seconds per in-game day with held sunrise, golden hours and sunset (winter about every 50 minutes; lunar month about 35 minutes). **DECIDED** ("10, day length: accept 72 real seconds per in-game day with sunrise and sunset held longer, winter about every 50 minutes. One tunable constant"). See open item 38 for the cadences v2 writes in in-game days.
11. **Infection and the hidden win.** Default: per-person infection; critical mass (50 % of the town plus half the staff plus half the patients) silently starts an outbreak and **is the rodent's win**; the winner keeps the rodent slot into the new session with a cosmetic scar; nobody sees an infection meter (D17). **DECIDED, amended** ("11, hidden win: accept the half-town trigger, but the ending is the outbreak cinematic in section 8, not an end card"). The end card is now only the client fallback (D31); rodent death resets infection to the new rodent without wiping the board (§1.5).
12. **Duel rules and health.** Default: drop the HTML's "perfect counter" and pounce immunity (a lunge that meets a committed kick is hit); 100 health; kick 55, baton 50, staff shove 40, defenders x1.5; 0.6 s grace after a hit; keep the mid-air pounce with a server cooldown. **DECIDED, amended** ("12, rodent health: accept 100 / 55 / 1.5x, plus the drain and bite-heal rules in section 8": health drains 1 % per in-game day without a bite; biting a human restores 10 %, a squirrel 20 %; slow regen while sneaking or in a hollow; "Power fades on real minutes; health drains on in-game days ... Do not merge them"). Regen defaults lowered to 0.25 and 1 hp/s so the drain and heals matter (D33).
13. **Who sees sightings.** Default: police and the drone see all; hospital staff see bite sightings only; the rodent sees none; markers fade after about a minute. **DECIDED** ("13, map sightings: accept. Police and drone see everything; hospital staff see bite locations only; markers fade after about a minute").
14. **Traffic deaths and patrol cars.** Default: every squirrel can be run over; the rodent's run ends; a regular squirrel drops its carried nuts and restarts at its hollow (no rank change); AI vehicles yield to people, deer and the fox; a player driver gets the kill credit; AI patrol cars keep running while players drive; car keys change hands only while parked. **DECIDED, with additions** ("14, driving and traffic: accept, with additions. Everyone obeys traffic law in town, police included. An officer who hits a pedestrian loses the car, sits in a cell, and is demoted to lowest rank on release; the pedestrian wakes up in a hospital bed as an uninfected patient. A player driver who runs over the rodent gets the kill credit and the section 6 promotion"). Built as `TrafficLaw` in W4 #12; "people protected by yielding" now holds for AI vehicles only; player vehicles can knock pedestrians down (non-fatal).
15. **Promotion paths and penalties.** Default: offers show Accept / Deer / Fox / Stay with a 15 s timeout and a "don't offer me promotions" switch; staff who kill the rodent inside the hospital get a temporary 8th squirrel slot if all 7 are full; a squirrel that dies in winter returns at its previous human rank; an infected squirrel loses half its nuts and drops two queue places. **Accepted by default, amended by §13a:** an open squirrel slot goes to the top-ranked **hospital** player first ("hospital outranks police"), then police, then humans; a killed infected squirrel's player "recycles to the bottom of the human queue"; police recruitment offers pass "to the next by seniority".
16. **Fox and deer.** Default: a fox lunge knocks a squirrel back and spills its carried nuts but never kills; the rodent cannot bite the fox. **Accepted by default, amended by §5 and §8:** **5 deer** slots (6 bodies, item 43); "deer become biteable only once every regular squirrel is infected. A bitten deer turns rabid and charges through town ... Before that point the rodent ignores deer" (mechanics of the charge: item 40).
17. **AI rodent when no player holds the slot.** Default: on, with gentler aggression, and it can never trigger the hidden win by itself. **Accepted by default.**

**Before W3 (town content)**

18. **Town plan.** Default (shown on a town-plan page for approval): 40 interior homes = 34 existing dwellings plus 6 in a new south-east block; restaurants and shops on the east "grass lots" and the Westside frontage; Quay bakery, café, pub and bookshop promoted to enterable lots; school and church in the south-east block; marina, pier and beach on the coast; defenders in core house 0 (housewife A), Westside house 2 (housewife B) and outer home 12 (broom man). **DECIDED, with additions** ("18, town layout: accept the 34 + 6 homes with a south-east school and church block, and the marina, pier and beach. The approval map must also show the steakhouse, the hill with sky lift and hilltop restaurant, the TV station, the bowling alley, the new mall, both lounges, the corner store, doctor's office, museum, racquetball court, and the off-road zone below"). OS-3 grows accordingly; the footprint extends (D32).
19. **Hollow mapping.** Default: H1 spiral ramp (premium), H2 vertical shaft with knothole exit and hideout nook (premium), H3-H11 knothole single chambers, and the fallen-log tunnel as an extra non-claimable shelter. **DECIDED** ("19, hollow trees: 12 not 11; see section 3"): the twelfth is the escape tree H12 with three knotholes and exits; the log stays an extra shelter; claiming is proximity with no ritual; the 70 % plus 3-day visit rule; finite nuts per season; carry 9.
20. **HTML extras.** Revision 2 default: drop Power and Gold; coins become credits and nut crumbs; chili hunt and rush rodent-only; sewer and fashion stand cosmetic; cats and dogs keep their gameplay. **DECIDED, reversed on Power** ("20, old web-game extras: keep Power exactly as v5.4 implements it (table below), drop Gold, coins become Spicy Dollars, chili rush becomes a rodent-only power-up, sewer and fashion stand stay with outfits as cosmetics, cats and dogs stay"). `Rodent/PowerRules` with the table (§4.15 D-21); squirrels still get nut crumbs for mall coins (v2 is silent; default kept).
21. **Children and special cast.** Default: the kid cyclists and the mime stay AI-only and are never possessable; the burglar wears neutral dark clothes. **Accepted by default.**
22. **Remodel points cadence.** The brief says per real day of play, but servers rarely live that long. Default: one point per real hour played on that server. This is a declared deviation (§2.1 deviation 3). **Accepted by default.**

**Before W5 to W7**

23. **Art sourcing.** Revision 2 default: Claude's procedural Blender work with turntable approval; if the squirrel, rodent or human heads miss the bar, licensed base meshes or an artist. **DECIDED, fallback removed** ("23, art: no money is ever spent on art and no outside artist. Everything is made procedurally in Blender by the coding session and approved by turntable. Rough is fine; what must be covered is contours, textures, colours, shading and shadows, and the basic movement set. Polish goes where people pay or play: extra lighting detail in both lounges and the paintball arena, and every minigame ironed out carefully. Detail is high on the ridge and anything near town; the far distance is painted scenery"). §5.6 carries this as the G2 bar; risk 4 and knob 5 updated; traceability rows 7-6 and 7-7 become COVERED by acceptance.
24. **Maturity target.** Default: "Mild" (a little blood on muzzle and claws, a horror tone), with the questionnaire answered to match. **DECIDED, amended** ("24, content rating: accept mild. Rewrite the v5.4 swearing lines to keep the venom and lose the vocabulary; skate the line like a lawyer"): lines are rewritten, not removed (W4 #8, W2 anchor 7).
25. **Moon and tower.** Default: moon by texture swap per phase; a new backdrop tower on the sunset azimuth; tall towers block the drone. **Accepted by default.**
26. **Server fill.** Default: "Maximum", so servers fill to **49** before new ones open and the rodent queue is real. Plainly: Roblox does not let an experience cap how many servers it runs, so the brief's "limited server count" can only be approximated this way (§2.1 deviation 4); a lobby with reserved servers is possible much later but is not planned. **Accepted by default.**
27. **Saving across servers.** Revision 2 default: none for gameplay. **Accepted by default but reversed by §13a for money and cosmetics:** Robux buys Spicy Dollars and garb is "kept permanently", so a DataStore profile is mandatory from W4 #11 (D26) for the wallet, receipts, wardrobe, inventory and reputation; rank, homes and hollows stay per server. Owner steps: the Studio API-services toggle and the developer products (OS-0). Whether reputation persists across servers is item 41.

*Added in revision 2:*

29. **Outfits and how humans look** (settled at G0 by S8e). Revision 2 default: colour-texture outfit sets on one shared UV layout with skin, trim and shoe colours from the avatar as tint zones. **Accepted by default, amended by §13a** ("the body keeps its own build and clothes (about 70%) and takes the player's face, hair and skin tone (about 30%). Do this with appearance properties scripts can set, not tinting"): no accent tint zones; face as a decal, hair as an accessory, skin tone as the body-part colour (item 37 confirms that reading). D22 updated; traceability A3-6 dropped.
30. **Audio sources** (before W6). Default: Roblox's licensed audio library for sirens, ambience and effects; uploaded signature sounds within the cap (D24). **DECIDED** (Addendum B2: the account is ID-verified with Premium, so 100 uploads a month); Premium changes nothing for uploads.
31. **Brief deviations** (Step 0 or G0). Default: approve the six declared deviations in §2.1 (owner builds as saved versions with Rojo live-sync still available; headless clips with the importer as fallback; remodel points per real hour; server fill instead of a server cap; dynamic-head faces mapped to a stock expression; colour-texture outfits). **Accepted by default** (all six). A seventh exists only if item 39 keeps the first-person stalk.
32. **Hospital and police progression** (before W4). Default: the performance metrics, the 6/7/8 officer thresholds and the upgrade catalogue in §3.9; upgrades bought from a pooled building fund; the drone as the upgrade bought at 8 officers; later officers coordinate as pursuer, cut-off and perimeter (§4.9). **Accepted by default**; §13a adds that duty is optional and never costs rank, raises rank inside that administration, and that police recruitment offers go to the top-ranked human and cascade by seniority.
33. **v5.4 behaviours** (Step 0, revisitable at G1). Default: the keep/defer/drop calls in §4.15. **Accepted by default**, with D-21 (Power) added as Keep by dec 20.
34. **Small physical rules** (before W2). Defaults: humans, deer and the fox do not swim (they wade out at the nearer bank; squirrels go to the nearer quay as in v5.4); squirrels do not ride moving cars and are set down beside a car that starts moving; no fall damage for the rodent (as in v5.4); NPC voices deferred (speech bubbles only), revisited in W6 if Roblox's text-to-speech is available to this experience. **Accepted by default.**
35. **Indoor chase outcome** (before W4). Default: the escape rule in §3.4 (hold a door for 3 s, hide out of sight for 2 s and force a search, or reach the back exit; defenders burst out in their houses). **Accepted by default.**
36. **Avatar blend sources** (before W2). Default: colours from body colours, accessory colours, item-name colour words (`GetProductInfo`) and a curated item-to-colour table; classic faces copied onto the role head; dynamic heads mapped to the nearest of 6 stock expressions; only rigid accessories transfer to animals (layered clothing is skipped) (D13). **Accepted by default, amended by Addendum B1:** animals keep the A3 30 % blend (fur tint and markings capped, one rigid head accessory); humans take face, hair and skin tone through settable appearance properties, no tinting.

**Also decided in brief v2 §15 without a revision-2 number:** rides versus minigames ("parasailing, the sky lift and the wind tunnel are rides: no controls, no score ... Jet ski is the exception (you steer). Minigames have controls and a result: bowling, pinball, pool, bumper pool, darts, racquetball, paintball, the tilt labyrinth, giant Jenga, volleyball. Only minigames get the ironing-out treatment"; D28); **layered distant fog goes into Wave 6** with the backdrop (W6 #1, unchanged); **street lighting** ("lamps on every block with warm pools of light and a few that flicker, porch lights, glowing shop fronts. The drone pilot and the outbreak cinematic both depend on this"; D30); **the off-road zone** ("beyond a ridge with real trees, a beach that runs out past the public area into a back field with hills. No tickets and no arrests there; police have no jurisdiction, though the drone can see it. The top two ranked humans can drive any pickup or SUV in town (place 6 pickups and 4 SUVs). This is undocumented in-game; players discover it. Otherwise only police drive"; D27, D32).

**Still open after brief v2 (rev 3; each with the default the build proceeds on; delta §4):**

37. **Human skin tone as a body-part colour** (before W1 art). v2 forbids "tinting" for humans; the only way to set skin tone on a custom body is the part colour (the same property Roblox's own BodyColors uses). Default: part colour, nearest of 8 tones. Alternative: a fixed set of 8 skin textures.
38. **Time-scale cadences** (before the FRB). At 72 s per in-game day, v2's rules read: hollow visits every 3.6 real minutes, 6-minute paintball and lounge passes, 5 + 5 votes every 72 s, a 12-minute ranking gate, a health drain of 1 hp per 72 s. Keep as written, or were these meant against a longer day? Default: as written, all Tunables, re-tuned in the FRB.
39. **Rodent stalk camera** (before W2). v5.4's stalk is first person (hold right mouse); §14 says the rodent stays in third person. Default: an over-shoulder third-person stalk. Alternative: keep the first-person stalk as the one exception (deviation 7).
40. **Animal rules v2 leaves open** (before W4): what the rabid deer's charge does (default: knockdowns and panic, no infection; a player-held deer keeps control and the charge is suggested, not forced); whether humans may kick healthy squirrels at all and what happens to a healthy player squirrel a lounge guard "annihilates" (default: healthy squirrels are immune to human strikes; a guard kill uses the same recycle rule); whether the water-gun stun is once per server life or once ever (default: per server life).
41. **Persistence scope** (before W4 #11). Default: the DataStore profile holds the Spicy-Dollar wallet, purchases and receipts, the garb and fashion-stand wardrobe, the item inventory and **reputation**; everything else is per server. Question: should reputation persist across servers (default yes, since v2 ties it to votes other players cast), and should lifetime stats?
42. **Paintball hosting** (at G0). Default: an instanced arena inside the same server with its own match state, borrowed-body bots and rodent exclusion (D29); fallback a separate place through `TeleportService` with reserved servers if S18 says the arena cannot share the server. Also: may a player quit a match early and walk back into town (default yes, pass still running)?
43. **Economy and population numbers** (before W4 #11). Developer-product tiers as whole Robux (default 25, 100, 400 R$ for 100, 400, 1,600 S$; the owner creates them in OS-0); one currency (the PDF's "credits" are Spicy Dollars; money counts toward the human queue only); a Lune earn-and-spend curve shown at G1 before prices are final; 6 deer bodies for 5 slots so the side exit is always available; a "block" for police chases measured from `roads.json`; the Power table's two verbatim gaps (the pedestrian kick also costs -19 in v5.4; the +150 bonus uses absolute world Y > 4; default: port the kick row too and measure height above local ground).
44. **Content and consequence details** (before W4b): mischief consequences and where TP, eggs and balloons are sold (default: fine plus reputation ding, a cell for repeat offenders; sold at the corner grocery); whether carts and bikes count as "driving" and whether a cart can earn the kill credit (default: anyone may ride; carts in the fatal fleet at low speed and obeying stop signs; bikes neither); votes on NPCs (default: players only); items with undefined effects (duct tape, umbrella, soda, ice cream, newspaper, peanuts versus seed; defaults in §3.14); the barber shop's and antique store's specifics (default: a two-chair shop with a pole, bench and radio; browsable curios with one-line descriptions); procedurally generated picture books and exhibits under "no money on art" (default: yes, text-forward with vector illustrations); the fortune machine styled as a fortune-teller cabinet with cards, never fruit reels; voting-abuse limits beyond the weight (default: one vote per target per in-game day, votes only after the 10-day gate); whether a human player hit by a player vehicle is also knocked down and hospitalised (default yes) and whether people stay immune to AI vehicles (default yes).

**Deferred or owner-gated requirements, in one place** (everything else in the traceability table is planned in a wave):

| Requirement | Why it waits | Recommended default | Decision |
|---|---|---|---|
| Fur that catches light, muscle under the skin (brief §7) | headless procedural Blender cannot judge look-dev; the plan's method is in §5.6 | procedural; "rough is fine" accepted, no artist fallback | 23 (decided) |
| Limited server count (brief §5) | platform limit | server fill "Maximum" at 49 | 26 (accepted) |
| Remodel points per real day (brief §8) | servers rarely live a day | per real hour | 22, 31 (accepted) |
| Studio sync from the filesystem; clips through the Studio importer (brief §2) | owner time | saved place versions; headless clips; both originals stay available as fallbacks | 31 (accepted) |
| Avatar face for dynamic heads (A3) | cannot transfer onto custom heads | nearest stock expression | 36 (accepted) |
| PBR human outfits (art direction) | SurfaceAppearance needs Studio imports | colour-texture outfits, untinted | 29 (accepted, amended) |
| NPC voices (v5.4 D-15) | no confirmed runtime speech synthesis | bubbles only | 34 (accepted) |
| Paintball staying in the game (brief v2 §13a) | the owner's own cut rule | built in W4, judged at G-PB | 42, OS-5b |
| Reputation across servers (brief v2 §13a) | v2 is silent | persists in the profile | 41 |
| Cadences in in-game days (brief v2 §3, §13a) | written against a 72-second day | as written, Tunables | 38 |

---

## 9. Scoring of the proposals and the grafts

### 9.1 Scores (1-10)

| Proposal | (a) every role in the first runnable build | (b) retires the scariest risks early | (c) data-driven, content-scalable town | (d) realistic for the toolchain and the owner's Studio time | Total |
|---|---|---|---|---|---|
| **Roles-first** [RF] | **10**: explicit thinnest loop per role, owner-runnable acceptance checks for all 8 roles plus multi-client, a Role Lab that sets up every scenario | 7: W0 spikes cover possession, cloud loop, terrain, headless animation and models, avatar APIs and move cost, but with soft exit criteria; no rail-validator or latency spike; the far view is mitigated rather than tested | 8: lots as JSON, a LotType contract, a pure Plan instantiated in Lune, the engine and a plugin, harvested routes plus generators; but lot types are Luau modules and the expansion waits until W3 | **8**: few owner steps, place as an Open Cloud artifact, runtime art by ID, live tunables; schedules experience creation that is already done | **33** |
| **Risk-first** [RK] | 8: all eight roles in the FRB, but the FRB is very heavy (all 40 interiors and the expansion) and its checks are less explicit; the pre-FRB spike checklist runs on the greybox town, close to a walkable-town milestone | **10**: nine spikes with numeric exit criteria (handoff jump, soak, cheat harness, golden agreement, AI p95, far view on a published server, runtime SurfaceAppearance, avatar blend on 20 users) and a gate before the bulk build | 7: lots as Luau data with structured params, Factory builders, an always-built impostor; less tool-friendly for Blender and Node | 6: more early owner Studio time (setup, a 40-minute spike session with a live-server join, art reviews); a very large single FRB step; VehicleSeat physics cars need tuning | 31 |
| **Data-pipeline-first** [DP] | 8: an FRB checklist covers all roles in 4 windows, but abbreviated; the FRB also carries the entire town and 40 interiors, so it arrives later | 6: spikes are mostly pipeline (uploads, terrain, chunk size, plugin); no AI-scale, rail-validation or latency spike before the FRB | **10**: JSON with schemas, lot types with `extends`, archetype JSON shared by Luau and Blender, interior templates, exact compiler invariants, harvest pinned by SHA, sockets and routes exported back from Blender, a lane-aware asset manifest | 6: seven owner sessions including two 45-minute import nights with manual texture dragging; two separate experiences (new owner setup); a large tool surface (Node harvest, Lune compiler, Python textures, plugin) before anything plays | 30 |

**Backbone: roles-first.** It scores highest on the brief's hardest process rule (a) and on (d), and its spine is compatible with the two strongest ideas of the others: risk-first's measurable spike gate (b) and data-pipeline-first's compiler and data model (c).

### 9.2 Grafts

**From risk-first**

1. Numeric spike exit criteria (handoff jump at 150 ms lag, 500-cycle possess/release soak with fake drivers, golden agreement, AI budgets) and a spike-report gate (G0) before the bulk build (§4.3).
2. Brain `suspend()`/`resume()` snapshots carrying clip and clip time; momentum carried through `AssemblyLinearVelocity`; the "blink handoff" fallback (§1.5, D1).
3. The engine never kills a body (`BreakJointsOnDeath = false`, Dead state disabled); death is a role transition (§1.1 rule 9).
4. Client-rendered ghost AI vehicles from a buffered pose stream, plus server pose ring buffers for lag compensation (D9).
5. `buffer`-encoded `Motor.State` and `VehiclePoses` with payload-size tests (§1.6).
6. A rail-validator cheat harness with 0 false positives over honest traces, run in CI (S3, §6.2).
7. Strict `luau-lsp analyze` in GitHub Actions, which can fetch the binary the container cannot (D16).
8. Lune place tests on the built `.rbxl`, including "no SurfaceAppearance in the place" (§6.4).
9. RTT-widened combat windows with up to 150 ms server rewind (D20).
10. An environment setup script for the ephemeral container (§4.1).
11. The map image rendered from the same data as the far-town impostor (§3.10).
12. Session reset re-deals every player through the possession path (§1.5).
13. The remodel-points cadence surfaced as an owner decision (decision 22).

**From data-pipeline-first**

14. Authored data as JSON plus JSON Schema in HTML units, compiled once to studs into committed `generated/` Luau that CI checks for staleness (D7, §1.2).
15. Lot types as JSON with `extends` over Luau builder families, so even a new shop type is data (§3.3).
16. House archetype JSON shared by the Luau blockout builder and the Blender kit generator, with flair axes and a distinctness invariant (§3.4).
17. Interior templates as data with generated nav, hide spots, defender spawn, burglar entry and remodel slots (§3.4).
18. Exact compiler invariants (40 interiors, 3 defenders, 12 hollows (11 before brief v2) with premium forage within 40 u, at least 10 restaurants of 8 kinds, all 13 new lot types and now the attractions, connectivity, strongly connected traffic, deadlock guard) (§3.13).
19. Steppable services (`init`/`step`, no threads on require) so Luau Execution can drive real modules (§1.1 rule 4).
20. The asset manifest with lanes and statuses and "best available" template resolution, plus the magenta placeholder toggle (§3.11, §5.1).
21. Sockets and route curves exported from Blender back into data so art and rails cannot drift (§5.1).
22. Lane 4: human looks from HumanoidDescription recipes and generated clothing images until custom bodies land (§5.1).
23. Signs as SurfaceGui text from data and wires as Beams (no uploads) (§1.4 WorldGen).
24. The harvest pinned to the canonical HTML's SHA-256, output committed with it (§4.3).
25. BakeParity: the engine-side bake hashes equal to the Lune bake (§6.5).
26. Owner imports only into an Inbox, with IDs harvested by Claude through Luau Execution instead of copy-paste (§5.7).
27. The top-two driver subrole and the AI-rodent backfill rule stated in the Ladder (§3.7).
28. The restaurant, shop and interior placement plan as the default for the town-plan page (decision 18).

**New in this plan**

29. Client-local animation for every body from replicated state, which makes the handoff animation-continuous and removes the animation-replication pitfall (D3, spike S2).
30. Already-done owner items removed; CI and Art Inbox as places inside the existing experience instead of new experiences (decision 2).
31. Exported FBX committed (a brief §14 deliverable), not treated as disposable build output (§5.7).
32. A headless terrain fallback: Blender ground tiles from the same height function (D6).
33. Owner playtests split into a 15-minute smoke plus the full checklist, and the FRB playtest splittable over two sittings (§6.6).
34. W0 code tied to the two owner items still in progress (GitHub push, luau-execution scope) (§4.1).

**Adopted in revision 2 (after the review)**

35. Risk-first's published-server far-view spike, with far terrain and `ReplicationFocus` (S11), which revision 1 had dropped.
36. Risk-first's runtime SurfaceAppearance check, extended to tint writes and the outfit path (S8c2, S8e), and its headless preview render (S12).
37. New: the population as posts, AI floors, re-posting and a reserve, so job sites stay staffed at full occupancy (§1.5, D23).

**Adopted in revision 3 (brief v2, through the delta)**

38. The hard 49-slot server with the brief's own NPC floors, and the retirement of the overflow design (§1.5, D23, S19).
39. Frameworks before content: `Item`, `Minigame` and `Ride` as contracts in W0, stubs in W1, anchors in the FRB and content in W4b, with physics authority chosen per stakes class by a spike (rule 13, D28, S13).
40. Paintball as an instanced match inside the town server with borrowed-body bots and lag compensation pulled forward for the arena only, judged by the owner at G-PB (D29, S18).
41. A mandatory DataStore profile with an idempotent receipt ledger, proven in W0 before any Robux product is live (D26, S15).
42. One `PlayerVehicles` family for every drivable kind, with first person on entry and modelled interiors (D27, S14).
43. Street lighting placed by the compiler, rendered by the client within a radius, and read from the drone through Skyline emissives (D30, S17).
44. The outbreak cinematic as a server-driven director with the end card demoted to a client fallback (D31).
45. The extended footprint as authored terrain patches outside the verbatim v5.4 height function (D32).
46. Two clocks for Power and health, pinned by tests (rule 11, D33).
47. A new parallel wave pair (W3c, W4b) for the attractions, so the brief's role-first FRB rule survives a scope that roughly doubles (§4.1, §4.14).

### 9.3 Not adopted, and why

- Risk-first's spike checklist on the greybox town before roles exist: too close to a walkable-town milestone. Spikes here run on a tiny spike place.
- Putting all 40 interiors and the whole expansion into the FRB (risk-first, data-pipeline-first): it delays the first time the owner plays all eight roles. Content lands in W3, through data, in parallel with W4.
- Two separate experiences for test and live (data-pipeline-first): the owner already created one; places inside it do the same job.
- VehicleSeat physics patrol cars (risk-first, data-pipeline-first) as the primary: a kinematic `CarMotor` shared with AI cars is deterministic and feeds the swept test directly; VehicleSeat stays as the fallback.
- Two 45-minute import nights with manual texture dragging (data-pipeline-first): imports are batched smaller, and the importer's own PBR handling is tried first (S8).

---

## 10. Requirement traceability

Every requirement in the review's inventory (`spec/design/critique.md` §1: the brief, Addendum A1-A3, the owner's art direction and standing decisions; same IDs) is traced to where this plan builds and checks it, and **§10.4 adds every brief v2 requirement (V2-1 to V2-229, the IDs of `spec/BRIEF_V2_DELTA.md`)**. Section references are to this plan; "W n #k" is item k of wave n (W3c and W4b included); "inv n" is compiler invariant n (§3.13); "dec n" is owner decision n (§8) and "item n" one of the open items 37-44 there; "S1-S20" are the W0 spikes (§4.3); "FRB X n" are the first-runnable-build acceptance checks (§4.7; hospital-staff checks are "FRB S1-S6"); "D-n" rows are v5.4 behaviours (§4.15); "C n" is a conflict in the delta's §2, answered in §10.5.

**Status key**

| Status | Meaning |
|---|---|
| COVERED | Built in the named wave and checked by a named test, invariant or owner check |
| COVERED* | Built on a default that one of the open items 37-44 (§8) confirms; work proceeds on the default (item named in the note) |
| DEVIATION | Meets the brief's intent another way; declared in §2.1; accepted by the owner by default in brief v2 §15 (decision 31) |
| GATED | Built, but kept only if the owner's own gate passes: in revision 3 only paintball (G-PB, the brief's cut rule) |
| LIMIT | Cannot be met as written on Roblox; the closest approximation is built and the owner is told plainly |
| DEFERRED / DROPPED | waits for a named owner decision with a default / not built because a later owner document removed it (the reason named) |

**Totals.** Rows 10.1 (307, the PDF brief, the addendum and the standing decisions): 302 COVERED, 3 DEVIATION (all accepted by the owner by default), 1 LIMIT, 1 DROPPED (A3-6, by brief v2); **0 COVERED\*, 0 GATED, 0 PARTIAL, 0 MISSING** (revision 2 had 294 COVERED, 7 COVERED*, 2 GATED; revision 1 had 277 covered, 28 partial and 2 missing). Rows 10.4 (229, brief v2): 199 COVERED, 29 COVERED*, 1 GATED; the COVERED* rows build on a default that one of the open items 37-44 confirms, and the one GATED row is paintball's own cut rule. Grand total **536 requirements**, none unplaced.

### 10.1 Requirements

| ID | Requirement | Plan section / wave | Status | Note |
|---|---|---|---|---|
| P-1 | Build the whole game in one pass | §4.1 | COVERED |  |
| P-2 | No walkable-town-first milestone | §4.1, §4.4, §9.3 | COVERED |  |
| P-3 | Every role test-playable from the first runnable build | §4.5-§4.7 | COVERED | roles reached through the Lab in the FRB; the drone's real unlock path in W4 #2-#3b |
| 1-1 | v5.4 HTML is canonical (SHA-256 pinned) | W0 #3, §9.2 graft 24 | COVERED |  |
| 1-2 | Retain the Bellwether Galleria (v5.3) | §1.4 WorldGen `Galleria` builder; §3.1 data migration | COVERED | mall mechanics now built in W4 #9 |
| 1-3 | Retain apple trees (v5.4) | W0 #3 (12 apple trees), W4 #5 | COVERED |  |
| 1-4 | Retain bird nests | §3.12 wildlife, W4 #7 | COVERED |  |
| 1-5 | Retain town birds | W4 #7 | COVERED |  |
| 1-6 | Retain silent overflights | W4 #7 | COVERED |  |
| 1-7 | Retain heavy vehicles | §4.6 Bodies | COVERED |  |
| 1-8 | Retain fatal traffic | D9, S4 | COVERED |  |
| 1-9 | HTML is the reference for layout, routes, lanes, districts and mechanics | D8, §6.3 golden vectors | COVERED |  |
| 1-10 | From-scratch Luau rewrite, not a transpile | §0, §6.3 | COVERED |  |
| 1-11 | Restore nut caches | W2 #7, §3.12 (cache 4 moved) | COVERED |  |
| 1-12 | Restore deer | W2 #8, §4.7 E1-E3 | COVERED |  |
| 1-13 | Restore foxes | W2 #8, §4.7 F1-F5 | COVERED |  |
| 1-14 | Restore butterflies | W4 #7 | COVERED |  |
| 1-15 | Restore garden insects | W4 #7 (dragonflies, insects) | COVERED |  |
| 2-1 | Rojo project under git, one repo | §1.2 | COVERED |  |
| 2-2 | Studio syncs from the filesystem; no zip handoffs | §1.2, D15, §2.1 #1 | DEVIATION | saved place versions; Rojo live-sync still available; dec 31 accepted by default (brief v2 §15) |
| 2-3 | Blender for all character and prop assets | §5 | COVERED |  |
| 2-4 | Exported as FBX with animations | §5.1 | COVERED |  |
| 2-5 | Clips imported through the Studio animation importer | D11, S7, §2.1 #2, §6.6 fallback budget | DEVIATION | headless KeyframeSequences; FBX with animations still exported; importer is the budgeted fallback; dec 31 accepted by default |
| 2-6 | One module per system, under Shared / Server / Client | §1.2 (WorldGen under `ServerScriptService.Server`) | COVERED | all code under the three named roots; `ReplicatedStorage.Assets` is content |
| 2-7 | WorldGen builds the town from data, never hand-placed parts | §1.4 WorldGen, D6 | COVERED |  |
| 2-8 | Routes module (trees, poles, wires, rooftops) | §1.4 `Routes/*` | COVERED |  |
| 2-9 | Traffic module (lanes, vehicles, yielding, swept collision) | §1.4 `Traffic/*`, `Vehicles/*` | COVERED |  |
| 2-10 | Actors module (single actor model) | §1.4, §1.5 | COVERED |  |
| 2-11 | Roles module (hierarchy, queue, promotion ladder) | §3.7 | COVERED |  |
| 2-12 | Infection module (bite, spread, cure, win condition) | §1.4 `Infection/*`, D17 | COVERED |  |
| 2-13 | Hospital, Police and Drone job systems | §1.4 server table | COVERED |  |
| 2-14 | Seasons module (calendar, winter) | `Time/*`, `Seasons/SeasonService` | COVERED |  |
| 2-15 | Foraging module (gardens, feeders, trash, hollows, nut meter) | `Foraging/*` | COVERED |  |
| 2-16 | Wildlife module (fox, deer, birds, insects) | `Wildlife/WildlifeService`, client `World/*` | COVERED |  |
| 2-17 | Town is a data file of lots (type, footprint, facing, params) | §3.2 | COVERED |  |
| 2-18 | Adding a barber shop is a data entry | §3.3 | COVERED |  |
| 2-19 | StreamingEnabled on | §1.2 project properties | COVERED |  |
| 2-20 | Map several thousand studs end to end | §4.6 (about 4,350 x 2,520 st plus the D32 extensions) | COVERED | the hill, ridge, back field and long beach extend it (brief v2 §13a, §15) |
| 2-21 | Scale: 1 HTML unit is about 2.5 studs | `Config/Units`, D21 | COVERED |  |
| 2-22 | Squirrel about 1.2 st at the shoulder | Tunables `shoulderHeight`, dec 8 | COVERED |  |
| 2-23 | Humans at standard R15 height | §5.2, §5.3 | COVERED |  |
| 3-1 | Old town core: streets, sidewalks, houses, poles and wires, trees | §4.6 World | COVERED |  |
| 3-2 | Hospital (west), expanded | W1 #7, W2 #3, W3a #3 | COVERED |  |
| 3-3 | Police station, expanded | §3.12, W3a #4 | COVERED |  |
| 3-4 | Riverside: stone arch bridge, cobbled quays, rooftops | WorldGen `Quay`, W5 #7; Recovery W1 #5, W2 #7 | COVERED | river-fall recovery kept (§4.15 D-7) |
| 3-5 | Galleria: six shops | data migration (`mall_shop` x6) | COVERED |  |
| 3-6 | Galleria: upper gallery | data migration (`mezzanine`) | COVERED |  |
| 3-7 | Galleria: coin fountain | W4 #9 `GalleriaService`, §4.15 D-10 | COVERED | coin pickup, wish toss, mall state machine; engine test and OS-5 scenario |
| 3-8 | Galleria: interior lighting | W6 #4 | COVERED |  |
| 3-9 | Galleria: camera constraints | W3b #9, `Camera/CameraRig` | COVERED |  |
| 3-10 | Sewer interiors | W3b #9 | COVERED |  |
| 3-11 | Duct interiors | W3a #3 | COVERED |  |
| 3-12 | House interiors | W2 #9 (4), W3a #2, W3b #6 (40) | COVERED |  |
| 3-13 | Expansion added as data-driven lots | §3.3, W3b #5 | COVERED |  |
| 3-14 | Restaurants roughly doubled | inv 4, W3b #5 | COVERED | baseline defined: 9 food businesses in v5.4, so >= 18 town-wide |
| 3-15 | Restaurant mix: diner, pizza, taco, Chinese, café, bakery, ice cream, bar and grill | inv 4, W3b #5 | COVERED |  |
| 3-16 | Each restaurant has outdoor seating or a back-alley dumpster | inv 4 | COVERED |  |
| 3-17 | Barber shop | inv 4, §3.3 | COVERED |  |
| 3-18 | Music store | inv 4 | COVERED |  |
| 3-19 | Hardware store | inv 4 | COVERED |  |
| 3-20 | Laundromat | inv 4 | COVERED |  |
| 3-21 | Bookshop | inv 4 | COVERED |  |
| 3-22 | Pet store | inv 4 | COVERED |  |
| 3-23 | Gas station | inv 4, W3b #5 | COVERED |  |
| 3-24 | Corner grocery | inv 4 | COVERED |  |
| 3-25 | School with playground | inv 4 | COVERED |  |
| 3-26 | Church | inv 4 | COVERED |  |
| 3-27 | Park with gazebo | inv 4 | COVERED |  |
| 3-28 | Community garden | inv 4 | COVERED |  |
| 3-29 | Small marina on the ocean side | inv 4, W3b #5, W6 #1 | COVERED |  |
| 3-30 | At least 8 house models (bungalow, two-storey, Victorian, ranch, split-level, cottage, apartment block, large older house) | §3.4 | COVERED |  |
| 3-31 | Every house has its own flair; no two read the same | §3.4 flair rule, inv 10, W3b #6 | COVERED | town-wide unique signatures plus local and same-archetype distance |
| 3-32 | Backyards with gardens, feeders, sheds, fences, dog houses | §3.4 backyards, inv 12, W3b #6 | COVERED | >= 2 items per house; town-wide minimums |
| 3-33 | Each lot type defines what squirrels can forage there | §3.3, inv 4 | COVERED |  |
| 3-34 | Each lot type defines how risky it is | §3.3, inv 4 | COVERED |  |
| 3-35 | Backdrop holds up at altitude for the drone | D5, S11 (W0), W6 #5, OS-1c, OS-7 | COVERED | published far-view spike in W0; SLIM baked from W1; `ReplicationFocus` |
| 3-36 | Mountains falling to rolling hills and plains | W6 #1 | COVERED |  |
| 3-37 | Tree line | W6 #1 | COVERED |  |
| 3-38 | Distant road | W6 #1 | COVERED |  |
| 3-39 | Fog layering | W6 #1, §5.3 P5, OS-7, W6 exit | COVERED | layered fog cards in front of a tuned Atmosphere |
| 3-40 | Ocean with a beach | W6 #1 | COVERED |  |
| 3-41 | Pier | W6 #1 | COVERED |  |
| 3-42 | Marina | W6 #1 | COVERED |  |
| 3-43 | Horizon reads correctly from 300 st | W6 exit, OS-7 | COVERED |  |
| 3-44 | Sky with a full day cycle | D19, W6 #2 | COVERED |  |
| 3-45 | Sunrise and sunset as their own moments | D19 day curve | COVERED |  |
| 3-46 | Clouds | W6 #4 | COVERED |  |
| 3-47 | Silent overflights in the sky | W4 #7 | COVERED |  |
| 3-48 | Beautiful night sky with stars | W6 #2 | COVERED |  |
| 3-49 | Moon runs through real phases on the calendar (~29.5 days) | W6 #3, `Time/Moon`, §6.2 | COVERED |  |
| 3-50 | Never a permanent full moon | W6 exit | COVERED |  |
| 3-51 | Distant radio or cell tower with blinking red lights | W6 #1 | COVERED |  |
| 3-52 | Tower silhouetted against the sunset | W6 #1, OS-7, dec 25 | COVERED |  |
| 3-53 | ~~11~~ **12** hollow trees across the town (brief v2 §3 supersedes the PDF's 11) | §3.5, §5.5, inv 5 | COVERED | superseded by V2-1; dec 19 decided |
| 3-54 | Each one a claimable territory with a nut meter | §3.5, W2 #7 | COVERED |  |
| 3-55 | Two premium trees with an interior pathway up the centre of the trunk | §5.5, W3b #7 | COVERED |  |
| 3-56 | Premium chambers at several heights | §3.5, §5.5 | COVERED |  |
| 3-57 | Premium trees next to the best gardens and feeders | inv 5 (within 40 u) | COVERED |  |
| 3-58 | Nine trees with a single chamber reached from a knothole | §5.5 | COVERED | plus the escape tree H12 (V2-6) |
| 4-1 | No code distinction between player character and NPC | §1.1 rule 1 | COVERED |  |
| 4-2 | One actor kind per species (human, squirrel, fox, deer) | §1.1, `Actors/Species` | COVERED |  |
| 4-3 | The only question is AI brain or player controller | §1.5 | COVERED |  |
| 4-4 | Every human and squirrel is AI-driven by default | §1.5 Join | COVERED |  |
| 4-5 | A joining player takes over an existing actor mid-stride | D1, S2, M1 | COVERED |  |
| 4-6 | A leaving player hands control back; the AI carries on | §1.5 Release, M2 | COVERED |  |
| 4-7 | Promotion is the same handoff | §1.5 Swap | COVERED |  |
| 4-8 | One mechanism implements the queue, backfill, role switching and session reset | §1.1 rule 1, §1.5 | COVERED |  |
| 4-9 | More human bodies than the 35 player slots; staff and streets kept staffed regardless of player count | §1.5 budget, D23, inv 11, S19, FRB M9 | COVERED | 69-84 standing bodies; the brief's floors (6 police, 10 hospital, crews extra); reserve to the S19 cap; humans past 35 served inside the 49; dec 28 decided |
| 5-1 | Max players ~~50~~ **49** (brief v2 §5 supersedes the PDF) | OS-0, inv 20, `Cap49`, W7 #7 | COVERED | the owner sets 49 in Step 0; W7 #7 confirms it |
| 5-2 | 35 humans, 7 squirrels, 1 spicy rodent | §1.5, §3.7 `humanSlots` | COVERED | 35 includes hospital and police: 35 + 7 + 1 + 5 + 1 = 49 of 49; dec 28 decided |
| 5-3 | Any slot not held by a player is AI | §1.5, §4.6 | COVERED |  |
| 5-4 | Squirrel population floats 10-14 | §1.5 squirrel float, inv 11 | COVERED | seasonal float 10-14 defined |
| 5-5 | Deer: ~~several~~ **5** voluntary slots (brief v2 §5) | §3.7 `sideExits.deer = 5`, dec 16 amended | COVERED | 6 deer bodies so the side exit is always available (item 43) |
| 5-6 | Fox: one slot, Easter egg | §3.7 (`hidden = true`) | COVERED |  |
| 5-7 | Limited server count so a real queue exists | dec 26, §2.1 #4, risk 16 | LIMIT | Roblox cannot cap servers; server fill "Maximum" at 49 approximates it; owner told plainly; accepted by default |
| 6-1 | The ladder is stated in one place (`Roles`) and nowhere else | §1.1 rule 2, §3.7 `Ladder.params`, inv 13 | COVERED | every ladder number inside `Ladder.luau`; quests name a rank class; literal scan in CI |
| 6-2 | Human: walks, earns credits by working, can be bitten | §4.7 H1-H7 | COVERED |  |
| 6-3 | Hospital staff: 5 player slots | §3.7 | COVERED |  |
| 6-4 | Police: 5 slots, expandable to 8 | §3.7, W4 #2 | COVERED |  |
| 6-5 | Hospital ranks slightly above police; privileges nearly equal | §3.7 `prestige` | COVERED |  |
| 6-6 | Regular squirrel: 7 slots; forages, stores nuts, claims a hollow | §3.7, W2 #7 | COVERED |  |
| 6-7 | Spicy rodent: 1 slot | §3.7 | COVERED |  |
| 6-8 | Human base rank = time playing on this server, modified by job credits | `Ladder.score`, `Ladder.params.w` | COVERED | reconciled with brief v2 §13a (C6): the human queue = time served + Spicy Dollars + reputation (+ entourage, kicks, quests); money counts toward the queue only; unranked before 10 in-game days |
| 6-9 | Squirrel rank = 90 % nuts + 10 % momentary stink % | `Ladder.score` | COVERED | "nut count" defined: stored in owned or claimed hollows plus carried, now |
| 6-10 | The highest-ranked squirrel becomes the next spicy rodent when the slot opens | §3.7 rodent-slot row, W2 #1, `LadderE2E`, R5 | COVERED | offer first, re-entry after 20 s, cascade (S-10 fixed) |
| 6-11 | When the rodent dies, its player restarts as a lowest-level human | §3.7, R5, R6 | COVERED |  |
| 6-12 | A human who kills the rodent goes to squirrel if a body is free, else police, or hospital if the rodent infected over 30 % | §3.7 | COVERED | uses the share of the town this rodent infected; a player driver who runs it over counts (brief v2 §15) |
| 6-13 | Hospital staff who kill the rodent inside the hospital instantly become a squirrel | §3.7, FRB S5 check, dec 15 | COVERED |  |
| 6-14 | A regular squirrel cannot kill the rodent | by design (no squirrel attack verb) | COVERED |  |
| 6-15 | An infected regular squirrel loses heavily and drops in the queue | §3.7, Q8 | COVERED | and, per brief v2 §8 and §13a, drops to lowest human when the rodent dies, can be killed by humans, and never recovers |
| 6-16 | Squirrels that die in winter restart as humans | §3.7, M8 | COVERED |  |
| 6-17 | Deer and fox are side exits; leaving returns to the previous human rank | §3.7, F5, E3 | COVERED |  |
| 7-1 | Port the route registry: curves, samples, kind, speed, surface radius, visualOffset | D8, §3.5 | COVERED |  |
| 7-2 | Rail-based climbing | `Routes/Motion`, S3 | COVERED |  |
| 7-3 | Free running on the ground | `SquirrelMotor` | COVERED |  |
| 7-4 | Leaps between rails | S3, Q2 | COVERED |  |
| 7-5 | Seven clips on a single rig (Run, Climb, Wire, Leap, Pounce, Bite dance, Sneak) | §5.4 | COVERED |  |
| 7-6 | Fur that catches light | §5.6, §5.3 P0, S12, G2 | COVERED | method stated; judged at G2 against the owner's bar "rough is fine; contours, textures, colours, shading and shadows" (dec 23 decided); no artist fallback |
| 7-7 | Muscle under the skin | §5.6, S12, G2 | COVERED | same as 7-6 |
| 7-8 | Tail lags the body | §5.3 (8 tail bones plus spring) | COVERED |  |
| 7-9 | Weight and presence are a modelling and rigging requirement, not lighting | §5.6 | COVERED |  |
| 7-10 | Replace the stacked-spheres placeholder entirely | W5 must-replace list | COVERED |  |
| 7-11 | Forage source: gardens | W2 #7, W4 #5 | COVERED |  |
| 7-12 | Forage source: bird feeders, risky because of birds and homeowners | §1.3, W4 #5 | COVERED | bird presence evaluated on the server from the clients' seeded function |
| 7-13 | Trash cans and restaurant dumpsters | W2 #7, W4 #5 | COVERED |  |
| 7-14 | Apple trees | W4 #5 | COVERED |  |
| 7-15 | Mall plaza | W4 #5 | COVERED |  |
| 7-16 | Nuts stored in a claimed hollow raise its meter | Q4 | COVERED |  |
| 7-17 | Above 70 % the squirrel owns the tree; others cannot take its nuts | `ForageRules`, W4 #5 theft rules | COVERED |  |
| 7-18 | Premium gardens and feeders raided about once per in-game week | W4 #5, `Calendar.raidWeek` | COVERED |  |
| 7-19 | Stink gland: slow-filling meter, 10 % of rank | Tunables `stinkFillPerMin` | COVERED |  |
| 7-20 | Fires only at 95 % or more | Q5 | COVERED |  |
| 7-21 | Firing drops the meter by 30 | Q5 | COVERED |  |
| 7-22 | Burst briefly repels foxes and humans | Q5, F4 | COVERED |  |
| 8-1 | Stalk (hold), pounce, bite as in v5.4 | R2-R3 | COVERED |  |
| 8-2 | Unaware people are easier | `CombatRules.biteChance` | COVERED |  |
| 8-3 | Biting humans infects them | W2 #2 | COVERED |  |
| 8-4 | Biting regular squirrels raises town-wide infection | `InfectionRules.squirrelShare` | COVERED |  |
| 8-5 | Fatal traffic as a server-side swept test, not Touched | D9 | COVERED |  |
| 8-6 | Being run over ends the rodent's run | R6 | COVERED |  |
| 8-7 | Hidden win path: infecting hospital staff slows cures | Tunables `infectedStaffCureMult` | COVERED |  |
| 8-8 | Critical mass of infection wins the session for the rodent | D17, D31, §3.7 rules, W2 #2, W4 #13 | COVERED | critical mass = the rodent player's win; the ending is the outbreak cinematic (brief v2 §8); dec 11 decided |
| 8-9 | Do not surface the hidden win in the UI | D17 | COVERED | the cinematic shows the outbreak, never a meter or a message naming the win |
| 8-10 | Session resets when everyone is infected | §1.5, §3.7 | COVERED | re-worded per C3: the reset follows the cinematic (or everyone infected); rodent death is not a reset (brief v2 §8) |
| 8-11 | The duel is built as tunable systems | `CombatRules`, Tunables | COVERED |  |
| 8-12 | Pounce has a wind-up, commit point and recovery | W2 #1, R3 | COVERED |  |
| 8-13 | Biting during the reaction window lands; biting into a raised arm or kick does not | dec 12, §6.2 | COVERED |  |
| 8-14 | Zig-zag raises miss chance but costs speed | W4 #1 | COVERED |  |
| 8-15 | A straight sprint is fast and readable | W4 #1 | COVERED |  |
| 8-16 | A feint forces an early flinch or swing | W4 #1 | COVERED |  |
| 8-17 | Feints cost stamina; read correctly, they hand the human a free hit | W4 #1 | COVERED |  |
| 8-18 | Humans flinch, swing, kick, back away or flee by awareness and nerve | W4 #1 | COVERED |  |
| 8-19 | Vigilantes never flee | W4 #1 | COVERED |  |
| 8-20 | Every show-off option carries a trade-off | W4 #1 | COVERED |  |
| 8-21 | 8 % of all human actors are vigilantes at any moment | `VigilanteRules`, W2 #5, §6.2, `SimFull` | COVERED | 8 % of all human actors kept through possessions |
| 8-22 | Vigilantes move to kick on sighting | W2 #5, W4 #1 | COVERED |  |
| 8-23 | Vigilantes answer the drone's call | DR3 | COVERED |  |
| 8-24 | Rodent health meter | W2 #1 | COVERED |  |
| 8-25 | A kick does not kill; about two kicks without recovery do | Tunables, R5 | COVERED | 100 / 55 / 1.5x confirmed by dec 12; plus the drain of 1 % per in-game day (V2-49) |
| 8-26 | Health regenerates while sneaking or resting in a hollow | R7, D33 | COVERED | regen lowered so the drain and the bite heals (10 human, 20 squirrel) are the main recovery (brief v2 §8) |
| 8-27 | Three defender houses burst out when the rodent chases someone inside | inv 3, W3a #2, W3b #6, W4 #1 | COVERED |  |
| 8-28 | Two older housewives of different appearance with rolling pins; one man with a broom | inv 3, §5.3 P1 | COVERED |  |
| 8-29 | Defender blows hit 50 % harder; one blow at low health kills | Tunables `defenderMult`, §6.2 | COVERED |  |
| 8-30 | 40 houses with full interiors the rodent can burst into | W3a #2, W3b #6, inv 3 | COVERED |  |
| 8-31 | Humans run inside and hide; escape or bite depends on the chase | §3.4 escape rule, W4 #1, `RodentLoop` | COVERED | door hold, hide and search, back exit; dec 35 accepted by default |
| 8-32 | Interiors must actually run and be tested, not stubbed | W3 exit, OS-5 | COVERED |  |
| 8-33 | The 40 houses are claimable homes | `HomeService`, W3a #2, W3b #6 | COVERED |  |
| 8-34 | Each real day of play earns remodel points | W4 #4, §2.1 #3 | DEVIATION | per real hour; dec 22 and 31 accepted by default |
| 8-35 | Remodels persist for the life of the server | D14 | COVERED |  |
| 9-1 | Reception | W1 #7, W2 #3, FRB S2 | COVERED |  |
| 9-2 | Triage | W1 #7, W2 #3 | COVERED |  |
| 9-3 | Two wards | W1 #7, W2 #3, W3a #3 | COVERED |  |
| 9-4 | Isolation ward | W1 #7, W2 #3, W3a #3 | COVERED |  |
| 9-5 | Pharmacy | W1 #7, W2 #3 | COVERED |  |
| 9-6 | Staff room | W1 #7, W2 #3 | COVERED |  |
| 9-7 | Ambulance bay | W3a #3 | COVERED |  |
| 9-8 | Roof access as a squirrel route | W3b #8, W3a #3 | COVERED |  |
| 9-9 | Infected humans are delivered or walk in | W2 #2 (walk-in), W4 #3 (ambulance) | COVERED |  |
| 9-10 | Staff disinfect through a short interaction loop at stations | FRB S3 | COVERED |  |
| 9-11 | Hospital performance = speed of disinfection | `HospitalService.performance` | COVERED |  |
| 9-12 | Good performance raises staff rank | W4 #3 | COVERED |  |
| 9-13 | Good performance unlocks station upgrades | §3.9 upgrades, W4 #3b, `Upgrades` suite | COVERED | catalogue, tiers, board, pooled purchase, effects |
| 9-14 | Staff can kill the rodent inside the building | FRB S5 | COVERED |  |
| 9-15 | Infected staff cure slower | FRB S6 | COVERED |  |
| 10-1 | Five officer player slots at start | §3.7 | COVERED |  |
| 10-2 | Officers pursue and can kill the rodent | P3 | COVERED |  |
| 10-3 | Good performance unlocks officers one at a time up to 8 | §3.9 police performance, `Ladder.params.policeSlots`, W4 #2 | COVERED | metric and thresholds defined |
| 10-4 | Later officers are more aggressive and better coordinated | W4 #2 `PoliceCoord`, `PoliceCoord` suite | COVERED | pursuer, cut-off, perimeter tiers; "Call backup" |
| 10-5 | At 8 officers the next upgrade unlocks a drone for one pilot | §3.7 `drone`, W4 #2 | COVERED |  |
| 10-6 | Full flight controls | DR2 | COVERED |  |
| 10-7 | Camera feed | DR1 | COVERED |  |
| 10-8 | Spot-and-mark reveals the rodent to officers for a short window | DR3 | COVERED |  |
| 10-9 | The mark calls nearby vigilantes to the spot | DR3 | COVERED |  |
| 10-10 | The drone as good as it can be (justifies the backdrop) | S11, D5, `DroneService`, W6 #5 | COVERED | far view tested in W0; `ReplicationFocus`; `PersistentPerPlayer` |
| 11-1 | Fox: one player slot, Easter egg | §3.7 | COVERED |  |
| 11-2 | Fox hunts regular squirrels | W2 #8 | COVERED |  |
| 11-3 | Fox cannot harm the rodent | F3 | COVERED |  |
| 11-4 | Fox is repelled by the stink gland | F4 | COVERED |  |
| 11-5 | Deer: several slots; peaceful; wanders | E1 | COVERED |  |
| 11-6 | Deer startled by traffic | E2 | COVERED | Lab "Spawn car near deer" makes E2 testable |
| 11-7 | Deer startled by the drone | DR4 | COVERED |  |
| 11-8 | AI-only birds and nests | W4 #7 | COVERED |  |
| 11-9 | AI-only butterflies | W4 #7 | COVERED |  |
| 11-10 | AI-only garden insects | W4 #7 | COVERED |  |
| 11-11 | AI deer and foxes when no player holds them | §4.6 Bodies | COVERED |  |
| 12-1 | In-game calendar | `Time/Calendar`, W2 #10 | COVERED |  |
| 12-2 | A week is the raid cycle | `raidWeek` | COVERED |  |
| 12-3 | Time scale is one tunable constant with a sensible default | D19, Tunables `realSecondsPerDay` | COVERED |  |
| 12-4 | Winter cycle about every 50 real minutes | D19 | COVERED |  |
| 12-5 | Visible day and night | W2 #10, W6 #2 | COVERED |  |
| 12-6 | Every five weeks, winter arrives and lasts one week | D19 (week 6 of 6) | COVERED |  |
| 12-7 | Snow | W4 #6 | COVERED | snow applied client-locally (no voxel replication) |
| 12-8 | Bare trees | W4 #6 | COVERED |  |
| 12-9 | Dimmer light | W2 #10, W6 #4 | COVERED |  |
| 12-10 | Reduced foraging | W2 #10 | COVERED |  |
| 12-11 | At winter's end, squirrels below the threshold die and restart as humans | W2 #10, M8 | COVERED |  |
| 13-1 | Humans earn credits from hospital, police and shop jobs | §3.3 jobs, §3.9, D26 | COVERED | "credits" are Spicy Dollars (one currency, C6): wages in cents per in-game hour |
| 13-2 | Credits raise queue rank | `Ladder.score` | COVERED | the money term of the human queue only; never hospital or police rank (brief v2 §13a) |
| 13-3 | Credits buy the §9 and §10 station upgrades | §3.9 upgrades, W4 #3b | COVERED | Spicy Dollars buy upgrades from a pooled building fund |
| 14-1 | Runnable place with every role test-playable | §4.6-§4.7 | COVERED |  |
| 14-2 | Blender sources and FBX for the squirrel (rigged, seven clips) | §5.7, W7 #5 | COVERED |  |
| 14-3 | Blender sources and FBX for the human variants | §5.7 | COVERED |  |
| 14-4 | Fox assets | §5.3 P2 | COVERED |  |
| 14-5 | Deer assets | §5.3 P2 | COVERED |  |
| 14-6 | Key props | §5.3 P1, P4 | COVERED |  |
| 14-7 | Town data file with every lot, including the full expansion | §1.2 `data/town`, W3 | COVERED |  |
| 14-8 | README: module layout; how to add a lot type, a route, a role | §1.2, W7 #5 | COVERED |  |
| A1-1 | The two highest-ranked police players each get a drivable car | §3.7 `driver`, P4 | COVERED | keys change hands only while the car is parked |
| A1-2 | Enter and exit the car | P4 | COVERED |  |
| A1-3 | Drive: throttle, brake, steer | D10, P4 | COVERED |  |
| A1-4 | Siren and lights toggle | P4 | COVERED |  |
| A1-5 | Park anywhere | P4 | COVERED |  |
| A1-6 | Other officers on foot; AI patrol cars keep running | dec 14 | COVERED | the population keeps 2 AI police bodies for the AI patrol car; "only police drive" now has brief v2's exceptions (carts and bikes for anyone, pickups and SUVs for the top two humans, jet skis; C8, D27) |
| A1-7 | Player cars in the server swept collision; can run over the rodent | P8, M5 | COVERED |  |
| A1-8 | Player cars take part in the traffic sim's yielding | D10 | COVERED |  |
| A1-9 | Town map: minimap plus full-screen map with marker layers | §3.10, H3 | COVERED |  |
| A1-10 | Sighting marker when a human spots the rodent or a bite happens; fades | §3.10, P2 | COVERED |  |
| A1-11 | Who sees sightings (to confirm) | dec 13, `markers.json` | COVERED |  |
| A1-12 | Drone mark gives a precise, short-lived marker | `droneMark` layer | COVERED |  |
| A1-13 | Radar shows nearby speeders and moving vehicles; speeds feed tickets | P5, P7 | COVERED |  |
| A2-1 | Rank rises from a successful kick by any human | §3.7 `kick.landed`, H6 | COVERED |  |
| A2-2 | Police work = fighting crime | P3 | COVERED |  |
| A2-3 | Settle a petty argument | §3.9, W4 #2 | COVERED |  |
| A2-4 | Write up a fender bender | W4 #2, D25 | COVERED | borrowed driver bodies; S5 includes 2 incidents |
| A2-5 | Parking ticket (hydrant, red curb, driveway, overtime) | §3.6, §3.9 | COVERED |  |
| A2-6 | Speeding ticket (radar, pull over with lights and siren, issue) | §3.9, P7 | COVERED |  |
| A2-7 | Stop signs, with AI drivers who sometimes roll through | §3.6, W3a #1, W4 #2 | COVERED |  |
| A2-8 | Stop a burglar before they escape | W4 #2 after W3a #2 | COVERED | explicit cross-track dependency (§4.1) |
| A2-9 | Hospital fetch: right medicine or instrument, under time pressure; a wrong item costs time and score | §3.9, FRB S4 | COVERED |  |
| A2-10 | Disinfecting counts as hospital work | §3.9 `disinfect` | COVERED |  |
| A2-11 | Play runs live across in-game days | §3.9 spawn per game hour | COVERED |  |
| A2-12 | Pursue rank or roam freely; no quest is mandatory | §3.7 Offers ("don't offer me promotions") | COVERED |  |
| A2-13 | Credits keep working (earn, raise rank, buy upgrades) | §3.9 upgrades, W4 #3b, D26 | COVERED | same as 13-3; the currency is the Spicy Dollar |
| A3-1 | 70/30 blend for every possessed actor, animals included | D13, `AvatarBlendService` | COVERED | runtime paths now spiked (S8c2, S8e, S9) |
| A3-2 | Humans keep body type, uniform and silhouette | D13 | COVERED |  |
| A3-3 | Humans take the avatar's skin tone | D13, D22, S8e | COVERED | skin tone as `MeshPart.Color` on skin parts |
| A3-4 | Humans take hair or one signature head accessory | D13 | COVERED |  |
| A3-5 | Humans take the avatar's face | D13, S9, §2.1 #5 | COVERED | classic face decal copied onto the head; dynamic heads map to a stock expression; dec 36 accepted; confirmed by brief v2 §13a ("face, hair and skin tone") |
| A3-6 | Avatar colours as accents (trim, tie, scarf, shoes) | D13, D22 (rev 3) | DROPPED | brief v2 §13a limits the human blend to face, hair and skin tone and forbids tinting; the accent zones are removed (C7) |
| A3-7 | Animals keep the species model and stock markings | D13 | COVERED |  |
| A3-8 | Animals take the dominant colours tinted into the fur (capped) | D13, D22, S8c2 | COVERED | confirmed by Addendum B1 (animals keep the A3 blend); runtime `SurfaceAppearance.Color` proven in W0, else pre-authored fur variants |
| A3-9 | Patterns coloured from the avatar's shirt and pants colours | D13, S9, `item_colours.json` | COVERED | `GetProductInfo` colour words plus a curated table; layered clothing counted; dec 36 accepted; Addendum B1 |
| A3-10 | Eye colour from the avatar | D13 | COVERED | Addendum B1 |
| A3-11 | One avatar accessory shrunk onto the head socket | D13, S9 | COVERED | rigid accessories from `CreateHumanoidModelFromDescription`, hand-welded to `HeadSocket`; Addendum B1 |
| A3-12 | Bizarre avatars: clamp saturation and brightness | `BlendRules`, §6.2 | COVERED |  |
| A3-13 | Bizarre avatars: one signature feature | D13, M6 | COVERED |  |
| A3-14 | Drop anything that breaks silhouette or hitboxes | D13, M6 | COVERED |  |
| A3-15 | Read the avatar server-side with `GetHumanoidDescriptionFromUserId` | D13, S9 | COVERED |  |
| A3-16 | No clothing pixels; derive colours from body colours, accessory metadata or a curated mapping | D13 | COVERED |  |
| A3-17 | Reversible: 100 % stock when the player leaves | §1.5 Release | COVERED |  |
| AD-1 | Semi-realistic overall | §5.6 | COVERED |  |
| AD-2 | Spicy rodent zombie-lite: mangy, stitched bald patches, a few ribs | §5.6, §5.3 P0 | COVERED |  |
| AD-3 | Natural fur colours, no green | §5.6 | COVERED |  |
| AD-4 | A little blood on muzzle and claws | §5.6, dec 24 | COVERED | blood in its own texture; moderation status handled (F-9) |
| AD-5 | A touch of horror | §5.6 | COVERED |  |
| AD-6 | "Cute but unhinged": oversized bloodshot eyes, crazed buck-tooth grin | §5.6 | COVERED |  |
| AD-7 | Humans: every role outfit (townsperson, police, nurse, doctor, guard, orderly, cyclist, jogger, mail carrier, EMT, ...) | D22, §5.3 P1, W5 #2 | COVERED | about 13 outfits as headless colour-texture sets on shared UVs, untinted; dec 29 accepted and amended by brief v2 §13a |
| AD-8 | Several adult body types | §5.3 P1 (6) | COVERED |  |
| AD-9 | All three hollow variants: shaft with knothole exit and hideout nook; spiral ramp; fallen-log tunnel | §5.5 | COVERED |  |
| AD-10 | Reconciled with the brief's 11 (2 premium, 9 knothole) | §5.5, dec 19 | COVERED |  |
| OD-1 | New private repo; the website repo is never touched | Fixed facts | COVERED |  |
| OD-2 | Open Cloud for uploads, saves and Luau Execution; Studio for rig import, SurfaceAppearance, multi-client tests and final publish | D12, D15, §5.1 | COVERED |  |
| OD-3 | Already-done owner items are not scheduled again | §8 preamble | COVERED | W7 #7 re-listing removed |
| OD-4 | Owner Studio steps click-by-click and few | §6.6, §4.14 | COVERED | sessions split (OS-1a-d, OS-6a-c); fallback minutes budgeted |
| OD-5 | Discuss order of operations before a significant commitment | Step 0, G0, §4.13 knobs | COVERED |  |
| OD-6 | Ephemeral container; everything in git | §4.1 | COVERED |  |
| OD-7 | At most 2 subagents at once, 4 CPUs | §4.1 | COVERED | UI and traffic gameplay moved to Track A; art has fixed Track B slots |

### 10.2 v5.4 behaviours outside the brief's list (from §4.15)

| ID | Behaviour | Call | Plan section / wave | Status |
|---|---|---|---|---|
| D-1 | Novelty cast (mime, 5 kid cyclists) | keep, AI-only | W4 #7b, `NoveltyRider` | COVERED |
| D-2 | Motorcyclists, skaters; motorcycles in the fatal fleet | keep (motorcycles join the fleet) | W3a #1, W4 #7b | COVERED (dec 33 accepted) |
| D-3 | Barbecue and softball events | keep | W4 #8, `EventService` | COVERED |
| D-4 | Crime scenes: seated victim, witness alarm, bystanders | keep | W4 #1 | COVERED |
| D-5 | Yard cat swat, dog bark; turtles | keep (server-side hazards; turtles ambient) | W4 #5, #7, `YardHazards` | COVERED |
| D-6 | Garden and hedge concealment | keep | W1 #3 (in the FRB) | COVERED |
| D-7 | River-fall recovery; swimming | keep recovery; nobody else swims | W1 #5, W2 #7 | COVERED (dec 34 accepted) |
| D-8 | Chili hunt and chili rush | keep | W4 #1 | COVERED |
| D-9 | Sewer fashion stand | keep as cosmetic; priced in Spicy cents; wardrobe saved in the profile | W4 #9 | COVERED (dec 20 decided) |
| D-10 | Galleria coins, wish toss, mall state machine | keep; coins become Spicy Dollars for humans | W4 #9 | COVERED (dec 20 decided) |
| D-11 | Trampoline bounce | keep | W1 #5 (in the FRB) | COVERED |
| D-12 | Hospital hatch ambush (2.5 s window) | keep | W4 #3 | COVERED |
| D-13 | Incident police, reinforcements, precinct guard | keep | W4 #2 | COVERED |
| D-14 | Bite dance every 10th bite | keep | W2 #1 | COVERED |
| D-15 | NPC voices | defer | W6 #4 if kept | DEFERRED (dec 34) |
| D-16 | 8 Quay walkers | keep as ordinary actors | W1 cast | COVERED |
| D-17 | Crowd accessories, flowering bushes | keep | W1 #10, W3b #6, W5 | COVERED |
| D-18 | Gas-station closure, clock-tower hands, legacy ambulance loop | keep, keep, drop | W4 #8, W6 #4, W4 #3 | COVERED / DROPPED (replaced by real ambulances) |
| D-19 | Squirrel on a moving car roof | no riding; set down beside the car | W2 (`Recovery`) | COVERED (dec 34 accepted) |
| D-20 | Rodent fall damage | none, as in v5.4 | W2 (tunable at 0) | COVERED (dec 34 accepted) |
| D-21 | **Power** meter and fade (squirrel_abilities §12) | **keep exactly as v5.4** (dec 20 decided reverses revision 2); Gold stays dropped | W1 #6b `PowerRules`, W2 #1 HUD | COVERED |

### 10.3 Review findings and where revision 2 answers them

| Finding (critique) | Answer in this plan |
|---|---|
| S-1 CI and Art Inbox places created after the spikes that need them | §4.2 Step 0 (OS-0 creates them; key scope confirmed), dec 2 |
| S-2 harvested routes versus quirk fixes | §4.4 W1 #7 `harvest_patches.json`; inv 2 `harvest_lock` until W3b #8 |
| S-3 hospital and station greybox handed to the gameplay track | W1 #7 (`buildings/*.json` v0 and builders); §4.1 dependency table |
| S-4 hidden cross-track dependencies | §4.1 dependency table; W3 split into W3a (first) and W3b; knob 2 |
| S-5 drone far view tested last | S11 (W0, published); D5 (SLIM from W1, `ReplicationFocus`); S6 with backdrop terrain |
| S-6 owner Studio time unbudgeted | §6.6 sessions split (OS-1a-d, OS-6a-c); §4.14 fallback minutes; §0 totals |
| S-7 G2 depends on untested headless renders | S12 (W0) |
| S-8 Track B overloaded; no art lane | §4.1 rebalance (UI and traffic gameplay to Track A) and fixed art slots |
| S-9 body and slot arithmetic; overflow undefined | §1.5 budget, D23, inv 11, dec 28 (decided: 49, hard), S19 at the hard cap, FRB M9 |
| S-10 AI rodent refill versus the offer | §3.7 rodent-slot row; `LadderE2E`; FRB R5 |
| S-11 FRB interiors depend on pieces W1 did not list | W1 #7 (schema, `Interior` builder, room graphs, doors, 4 templates) |
| S-12 Sim10 cannot be split across tasks | `SimFull` (5 sim-min, one task) and `SimLong` (§4.4, §6.5) |
| S-13 two tracks share one CI place | D15 version pinning and the shared cloud lock; S1 |
| F-1 runtime SurfaceAppearance tint; one Color per MeshPart | S8(c2); D22 (separate tint-zone MeshParts); §5.2 |
| F-2 no route for human outfits | D22 (colour-texture outfits on shared UVs), S8(e), dec 29, §5.3 P1 |
| F-3 face and shirt/pants colours | D13, S9 (`GetProductInfo`, face transfer), `item_colours.json`, dec 36 |
| F-4 accessory path onto animals | D13 (rigid only, via `CreateHumanoidModelFromDescription`, hand-welded), S9 |
| F-5 audio upload cap | D24, dec 30, risk 20 |
| F-6 fender-bender drivers break the budget | D25, S5 |
| F-7 runtime terrain costs; winter snow replication | D6 (primary ground decided at G0), S6, S11; client-local snow (§1.3, W4 #6) |
| F-8 2048-stud part cap | WorldGen Backdrop builder, W6 #1, §5.3 P5 (tiles) |
| F-9 moderation | D12, §3.11 `moderation`, §5.7 moderation rule, risk 19 |
| F-10 GitHub App and workflow files | §4.1 preconditions, dec 3, risk 21 |
| F-11 Team Create overwrites | D15, OS-0, §5.7 Studio-edit rule, risk 18 |
| F-12 Reset button; bubble chat on non-Humanoids | §1.1 rule 9, `Recovery`, §5.2 `Head` part, S2, FRB H9 |
| F-13 drone streaming focus | §1.5 Devices, `DroneService`, D5, S11 |
| F-14 Luau Execution timings are not live timings | D4, §6.5 `SimFull`, W7 exit (live MicroProfiler is the gate) |
| F-15 Lane-2 kits may lack PBR maps | S8(a), S8(f), D12, §5.1 Lane 2 |
| F-16 syncback captures inside the build | §1.2 `art_captures/`, inv 14, §5.7, §6.4 |
| §5 notes: tower inside the drone envelope; rodent sees hollows; keys mid-drive; nut count; deer startle testability; moderation in `Assets` | W6 exit (tower collision test); §3.10 `hollow` audience; §1.5 Devices; §3.7 `Ladder.score`; FRB E2; §6.5 `Assets` |

### 10.4 Brief v2 requirements (V2-1 to V2-229, from `spec/BRIEF_V2_DELTA.md` §1) and where revision 3 builds them

The requirement text is the delta's quotation of brief v2, shortened where long; the delta carries the full sentence and the "smallest plan change" each row started from.

| ID | Brief v2 says | Plan section / wave | Status | Note |
|---|---|---|---|---|
| V2-1 | 12 hollow trees across the town, each a claimable squirrel territory with a nut meter (PDF: 11) | §3.5, §5.5, inv 5, W2 #7, W3b #7 | COVERED | 12 claimable; dec 19 decided; supersedes row 3-53 |
| V2-2 | plus a fallen hollow log as an extra hiding spot | §5.5 log row, W3b #7 | COVERED | the log stays a non-claimable shelter |
| V2-3 | Premium tree 1: a spiral ramp running up inside the trunk, chambers at several heights | §5.5 H1, W3b #7 | COVERED |  |
| V2-4 | Premium tree 2: a straight climb-up shaft with a knothole exit and a hideout | §5.5 H2, W3b #7 | COVERED |  |
| V2-5 | Both sit next to the best gardens and bird feeders | inv 5 (premium forage within 40 u) | COVERED |  |
| V2-6 | One escape tree with three apertures and exits | §3.5 H12, §5.5, W3b #7, §5.3 P3, FRB Q12 | COVERED |  |
| V2-7 | The other nine have a single hollow chamber reachable from a knothole | §5.5 H3-H11 | COVERED |  |
| V2-8 | Claiming is proximity, not a ritual: no scent-marking animation | §3.5 (deposit while inside, no clip), FRB Q4 | COVERED |  |
| V2-9 | A squirrel owns a tree while its meter is at 70% or above and it has visited the tree at least once every three... | `ForageRules.owner`, Tunables `forage.ownVisitDays`, W2 #7, FRB Q11 | COVERED* | item 38 (3 in-game days = 3.6 real minutes) |
| V2-10 | Nuts on the map are finite per season | `ForageRules.stock`, `seasonStock`, inv 15, W2 #7, W4 #5 | COVERED |  |
| V2-11 | A squirrel carries at most 9 nuts at a time | Tunables `forage.carryMax = 9`, FRB Q10 | COVERED |  |
| V2-12 | Server cap is 49 player slots, hard | §1.5, D23, inv 20, `Cap49`, OS-0 (Max Players 49) | COVERED |  |
| V2-13 | 35 humans (hospital and police slots are inside the 35) | §1.5, §3.7 `humanSlots`, dec 28 decided | COVERED |  |
| V2-14 | 7 regular squirrels, 1 spicy rodent | §3.7 | COVERED |  |
| V2-15 | 5 deer (PDF: several; plan default 4) | §3.7 `sideExits.deer = 5`, §1.5 (6 bodies), dec 16 amended | COVERED |  |
| V2-16 | 1 fox | §3.7 | COVERED |  |
| V2-17 | When it is full it is full; late joiners wait for the next server. No overflow roles, no spectator birds | §1.5 (no overflow roles; MaxPlayers makes late joiners wait), D23, FRB M9, `Cap49` | COVERED |  |
| V2-18 | Any slot not held by a player is AI | §1.5, §4.6 | COVERED |  |
| V2-19 | Squirrel bodies may float between 10 and 14 | §1.5 squirrel float, inv 11 | COVERED |  |
| V2-20 | at least 6 NPC police and at least 10 NPC hospital staff, plus ambulance crews on top (crews do not count toward... | §1.5 budget table (police 6, hospital 10, ambulance-crew post), inv 11, S19, FRB M9 | COVERED |  |
| V2-21 | Player staff make things faster and earn bonuses; the town functions without them | Tunables `hospital.aiStaffSpeedMult`, `Wallet`, W4 #3 | COVERED |  |
| V2-22 | The fox is the Easter egg; deer are openly offered | §3.7 (`fox.hidden`), Offers | COVERED |  |
| V2-23 | No infection meter is ever shown to anyone | D17 (Lab only), §1.6 attributes | COVERED |  |
| V2-24 | When combined infection reaches about half the town plus half the hospital staff and patients, the outbreak... | D17, dec 11 decided, Tunables `infection.critical*` | COVERED |  |
| V2-25 | The outbreak is a cinematic, not an end card | D31, `OutbreakDirector`, W4 #13, `OutbreakCinematic` suite, OS-5 | COVERED |  |
| V2-26 | every player's camera pulls up and out over the town | D31 (camera on the Skyline layer, one tween per client), W4 #13 | COVERED |  |
| V2-27 | time accelerates | `Clock.setRate`, Tunables `outbreak.clockRateMult`, W4 #13 | COVERED |  |
| V2-28 | squirrels sweep house to house faster and faster | `Brains/Squirrel` `OutbreakSweep`, W4 #13 | COVERED |  |
| V2-29 | the sky goes overcast and dims; at night it simply fades to black | `Outbreak` lighting state, W4 #13, W6 #4 | COVERED |  |
| V2-30 | This sequence needs the lamplit town from section 3 to look right | W3a #5 (greybox lamps with real lights), D30, W6 #4 | COVERED |  |
| V2-31 | When the spicy rodent dies, the board is not wiped | §1.5 'Rodent death is not a reset', D17 | COVERED |  |
| V2-32 | Infection resets to the new rodent alone (about 0.5%) | `InfectionService.resetToRodent`, W2 #2, FRB R11, `LadderE2E` | COVERED |  |
| V2-33 | Regular squirrels keep their hoards | `HollowService`, §1.5 | COVERED |  |
| V2-34 | humans keep their points and reputation | §1.5, `Wallet`, `ReputationService`, FRB M10 | COVERED |  |
| V2-35 | Infected squirrels drop to lowest-rank human (on rodent death) | §3.7 rule `rodent.died who = infectedSquirrels`, FRB M10 | COVERED |  |
| V2-36 | Infected humans are cured (instantly if recently bitten or en route to hospital) | `InfectionService` (`recentBiteSecs`), W2 #2, FRB R11 | COVERED |  |
| V2-37 | Deer become biteable only once every regular squirrel is infected | `InfectionService.deerBiteable`, W2 #1 gate, W4 #1, FRB R10, E4 | COVERED |  |
| V2-38 | A bitten deer turns rabid and charges through town, accelerating the collapse | `RabidDeer` brain state, W4 #1 | COVERED* | item 40 (what the charge does) |
| V2-39 | Before that point the rodent ignores deer | W2 #1, FRB E4 | COVERED |  |
| V2-40 | Bite aftermath: the vicinity goes on high alert | `CombatService.alertZone`, Tunables `alert.*`, W4 #1 | COVERED |  |
| V2-41 | Humans nearby get a hidden strength boost (not shown on any meter) | Tunables `alert.kickMult` (hidden, below 1.82), D33, W4 #1 | COVERED |  |
| V2-42 | are far more likely to swing | Tunables `alert.swingBias`, W4 #1 | COVERED |  |
| V2-43 | NPC police within about two blocks will chase up to five blocks | Tunables `alert.policeChaseBlocks`, `policeLeashBlocks`, W4 #1-#2 | COVERED* | item 43 (a block measured from `roads.json`) |
| V2-44 | The ambulance sequence plays out | W4 #3 ambulances | COVERED |  |
| V2-45 | Biting again near a fresh bite should be close to impossible | Tunables `alert.bitePenalty`, W4 #1 | COVERED |  |
| V2-46 | The rodent therefore needs refuges between bites: hollows, the sewer, poles and trees. Treat them as rodent cover,... | `concealment.json` unseen volumes, `HollowService` rodent rest, W3b #9, W4 #1, §5.5 | COVERED |  |
| V2-47 | Rodent health 100. A kick does 55, so two kicks without recovery kill | Tunables `rodent.*`, dec 12 decided | COVERED |  |
| V2-48 | The three house defenders hit 1.5x (about 82), which kills only if health is already below full. Accepted as-is | Tunables `rodent.defenderMult` | COVERED |  |
| V2-49 | Health drains 1% per in-game day without a bite | Tunables `rodent.drainPerDay`, D33, W2 #1, FRB R9 | COVERED |  |
| V2-50 | Biting a human restores 10%; biting a regular squirrel restores 20% | Tunables `rodent.healOnBite`, W2 #1, FRB R9 | COVERED |  |
| V2-51 | Health also regenerates slowly while sneaking or resting in a hollow | Tunables `regenStalk`, `regenHollow` (lowered, D33), FRB R7 | COVERED |  |
| V2-52 | Power fades on real minutes; health drains on in-game days. These are two separate clocks by design. Do not merge them | §1.1 rule 11, D33, `PowerRules`, §6.2 two-clock tests | COVERED |  |
| V2-53 | regular squirrels match the rodent's speed and agility | `SquirrelMotor` shared; `Brains/Squirrel` full-sprint flee on rails, W4 #1 | COVERED |  |
| V2-54 | a chase is long and exposed, the camera is locked forward | `CameraRig` chase lock, Tunables `squirrel.chaseLockRange`, W4 #1 | COVERED |  |
| V2-55 | a vigilante or patrol car can take you from the blind side | `VigilanteRules`, `SweptCollision` (emergent) | COVERED |  |
| V2-56 | The 20% heal is the reward for that risk | Tunables `rodent.healOnBite.squirrel = 20` | COVERED |  |
| V2-57 | Humans are 35 of the 43 player slots | §1.5 (the 43/49 reading), §3.7 | COVERED |  |
| V2-58 | the human life must be a full game, not a waiting room | W2 #6c anchors, FRB H10-H17, W3c, W4b | COVERED |  |
| V2-59 | Everyone has total free range | A2-12, §3.7 Offers | COVERED |  |
| V2-60 | Hospital and police duty is optional: skipping it never costs rank | §3.7 (no penalty rows), dec 32 | COVERED |  |
| V2-61 | doing it raises rank inside that administration | `Ladder.score` administration formula (`wAdmin`) | COVERED |  |
| V2-62 | Everyone gains some rank for time served | `Ladder.params.w.time` | COVERED |  |
| V2-63 | Police, doctors and nurses get distinct outfits | §5.3 P1 outfits, §5.6 | COVERED |  |
| V2-64 | the body keeps its own build and clothes (about 70%) and takes the player's face, hair and skin tone (about 30%) | D13 (rev 3), D22 | COVERED |  |
| V2-65 | Do this with appearance properties scripts can set, not tinting | D22 (part colour, face decal, hair accessory), S8(e) | COVERED* | item 37 (skin as part colour) |
| V2-66 | Several golf carts and bicycles (player-usable) | D27 `VehicleKinds` cart and bike, W2 #6c anchor 5, W3c #14, FRB H14 | COVERED |  |
| V2-67 | trampolines (plural; v5.4 has one) | W3b #6 (3-4 trampoline sites), inv 16, §4.15 D-11 | COVERED |  |
| V2-68 | two climbable tree houses (risky: squirrels reach them) | W3b #6 (2 tree houses, Humanoid ladder plus squirrel routes), inv 16 | COVERED |  |
| V2-69 | Mischief: TP-ing trees, knock-and-run, egging at night, water balloons, joyriding a police cart | `MischiefService`, W4b #6 | COVERED* | item 44 (consequences and supplies) |
| V2-70 | Mischief angers NPCs and gives police something to respond to | `AngryNpc` overlay, `mischief_response` quest, W4b #6 | COVERED |  |
| V2-71 | A taunt button that cycles about 20 one-liners | `TauntService`, `speech/taunts.json`, W2 #6c anchor 7, FRB H16 | COVERED |  |
| V2-72 | Gigs (earn Spicy Dollars): lawn mowing (quick) | `gig_mow`, §3.9, W2 #6c anchor 3, FRB H11 | COVERED |  |
| V2-73 | restaurant delivery by bike or cart | `gig_delivery`, §3.9, W4b #5 | COVERED |  |
| V2-74 | sign-spinning | `gig_sign`, §3.9, W4b #5 | COVERED |  |
| V2-75 | car washing | `gig_wash`, §3.9, W4b #5 | COVERED |  |
| V2-76 | a morning newspaper bike route (bonus for hitting the porch) | `gig_paper` (porch-hit detection, porch bonus), §3.9, W4b #5 | COVERED |  |
| V2-77 | serving tables at the steakhouse | `gig_serve`, §3.9, §3.17 steakhouse, W4b #5 | COVERED |  |
| V2-78 | One rule for all gigs: an extra-good job earns a tip; a bad job gives a very minor reputation ding | `GigRules` quality rule, §3.9, W2 #6c, FRB H11 | COVERED |  |
| V2-79 | NPC-posted mini-missions appear on a wanted poster or billboard (walk Mrs. Harrison's dog, return a lost pet) and... | `npc.post` source, billboard and poster UI, `PetService`, W4b #5 | COVERED |  |
| V2-80 | Reputation. Two-sided | `ReputationRules`, §3.15, W2 #6c anchor 4, W4b #7 | COVERED |  |
| V2-81 | NPCs can like you for being fun and will pal around or follow you | `Companion` overlay, §3.15 `npcLiking`, W4b #7 | COVERED |  |
| V2-82 | a bigger entourage raises rank | `Ladder.params.w.entourage` | COVERED |  |
| V2-83 | Players give thumbs up or down to anyone, five of each per in-game day | `VoteService`, §3.15 votes, FRB H12 | COVERED* | item 38 (5 + 5 per 72-second day) |
| V2-84 | a vote against another player affects their reputation | `ReputationRules.applyVote` | COVERED |  |
| V2-85 | Weight votes by the voter's own reputation to blunt brigading | §3.15 weight clamp, §6.2 brigading tests | COVERED |  |
| V2-86 | Sitting at a cafe raises reputation | `Seat` sockets on cafes, §3.15 cafe tick, W3b #5, FRB H13 | COVERED |  |
| V2-87 | Reputation also rises for rescuing someone the rodent is chasing | `CombatService` `Rescue` signal, §3.15, W4 #1 | COVERED |  |
| V2-88 | true sighting reports | Report verb, §3.10, §3.15 | COVERED |  |
| V2-89 | returning lost pets | W4b #5 (lost pet), `PetService` | COVERED |  |
| V2-90 | Big boost for landing a kick on the rodent or any infected squirrel | §3.7 `kick.landed` target rodent or infected squirrel, W4 #1 | COVERED |  |
| V2-91 | Killing an infected non-leader squirrel kills it | `Ladder.params.infectedSquirrelHealth`, `squirrel.killed` rows, W2 #6, FRB Q13 | COVERED* | item 40 (healthy squirrels immune by default) |
| V2-92 | a healthy squirrel respawns and the top-ranked hospital player (hospital outranks police) is promoted into that slot | §3.7 `slot.open squirrel take = hospitalThenPoliceThenHuman`, FRB M11 | COVERED |  |
| V2-93 | The killed player recycles to the bottom of the human queue | §3.7 `squirrel.killed victim -> human lowest`, FRB M11 | COVERED |  |
| V2-94 | Infected squirrels never recover | `InfectionService` (no cure path for squirrels) | COVERED |  |
| V2-95 | one still alive when the rodent wins restarts the next match as a regular squirrel | §3.7 reset row `infectedSquirrelsAliveKeepSquirrel`, D17 | COVERED |  |
| V2-96 | Police recruitment: when police perform well, a promotion offer is messaged to the top-ranked regular human;... | §3.7 recruitment rows, `recruitCascade = seniority`, Offers | COVERED |  |
| V2-97 | Currency is Spicy Dollars | D26, `Economy/Wallet` (cents), §3.14 | COVERED |  |
| V2-98 | Robux buys them through developer products (about 1 Robux to 4 Spicy Dollars; Robux amounts must be whole numbers) | D26, `Economy/Store.processReceipt`, `products.json`, S15, W4 #11, OS-0 | COVERED* | item 43 (whole-Robux tiers) |
| V2-99 | Minimum wage is 2 spicy pennies per in-game hour | §3.9 jobs `centsPerHour`, `wages.json`, Lune economy curve at G1 | COVERED* | item 43 (numbers) |
| V2-100 | goods are cheap (coffee 12 cents, nachos 5 cents) | `prices.json`, §3.14 | COVERED |  |
| V2-101 | Money's main use is buying your place in the human queue only, never into police or hospital | `Ladder.score` (money in the human queue only; `wAdmin` ignores it) | COVERED |  |
| V2-102 | Queue rank = money plus reputation | `Ladder.params.w` (time, money, reputation, entourage) | COVERED |  |
| V2-103 | a player needs at least 10 in-game days of play before being ranked at all | `Ladder.params.rankGateDays = 10`, FRB H17 | COVERED* | item 38 (10 days = 12 real minutes) |
| V2-104 | Places and attractions (all fully interactive, not set dressing) | §1.1 rule 13, §3.16-§3.17, D28, W3c, W4b | COVERED |  |
| V2-105 | Detailed stores: antique store | `shop_antique` lot type, W3c #13 | COVERED* | item 44 (specifics) |
| V2-106 | pet store (detailed) | pet store interior with pets, W3b #5, W3c #15 | COVERED |  |
| V2-107 | a very specific barber shop | W3b #5 | COVERED* | item 44 (the owner's specifics) |
| V2-108 | an intricate police station | W3a #4, W5 #6 fit-out | COVERED |  |
| V2-109 | Corner store: a 1970s-style layout (not literally period), a working checkout counter | `shop_corner` lot type, §3.17, W2 #9 greybox counter, W3c #13 | COVERED |  |
| V2-110 | about 22 pick-up-able shelf items, every one functional, all cheap except bird seed and the kite | `Item` framework, §3.14 `items.json`, W2 #6c anchor 2 (6 items), W4b #3 (16), D26 inventory | COVERED |  |
| V2-111 | water gun 6 (squirts people, they react; Easter egg: the first time a given player's squirt hits the rodent it... | `items.json` water_gun, Tunables `waterGunStunSecs`, FRB H10 | COVERED* | item 40 (once per server or forever) |
| V2-112 | frisbee 5, football 6 | `items.json` frisbee and football (throwables), FRB H10, W4b #3 | COVERED |  |
| V2-113 | bubbles 3 | `items.json` bubbles, W4b #3 | COVERED |  |
| V2-114 | sidewalk chalk 2 (each stick writes about 20 letters on pavement) | `items.json` chalk, `TextService` filter, S20, W4b #3 | COVERED |  |
| V2-115 | flashlight 6 (works at night) | `items.json` flashlight, FRB H10, S17 budget | COVERED |  |
| V2-116 | umbrella 5 | `items.json` umbrella (cosmetic) | COVERED* | item 44 |
| V2-117 | peanuts 4 and bird seed 40 (baits squirrels and birds) | `items.json` peanuts and bird_seed bait, W4b #3 | COVERED* | item 44 (peanuts versus seed) |
| V2-118 | dog treats 4 | `items.json` dog_treats, `PetService` | COVERED |  |
| V2-119 | newspaper 2 | `items.json` newspaper, `gig_paper` | COVERED* | item 44 |
| V2-120 | disposable camera 6 (takes screenshots) | `items.json` camera, `CaptureService`, S20 | COVERED |  |
| V2-121 | duct tape 4 | `items.json` duct_tape | COVERED* | item 44 (effect undefined) |
| V2-122 | whoopee cushion 15 (moderate, to limit how many are about) | `items.json` whoopee_cushion, `Seat` sockets | COVERED |  |
| V2-123 | harmonica 5, bike horn 3, air horn 5 (startles NPCs and squirrels) | `items.json` harmonica, bike_horn, air_horn, FRB H10 | COVERED |  |
| V2-124 | soda 4, ice cream bar 5 | `items.json` soda, ice_cream_bar (stamina), FRB H10 | COVERED* | item 44 |
| V2-125 | lawn chair 6 (sit anywhere) | `items.json` lawn_chair, FRB H10 | COVERED |  |
| V2-126 | radio 8 (plays the stock library) | `items.json` radio, D24 library | COVERED |  |
| V2-127 | kite 60 (a full flying sequence in the park and on the beach) | `rides/kite.json`, W4b #3-#4 | COVERED |  |
| V2-128 | No lottery or gambling items | §3.14 header; risk 11 | COVERED |  |
| V2-129 | Doctor's office: receptionist at the counter | `clinic` lot type, §3.17, W3c #13, §1.5 attraction staff | COVERED |  |
| V2-130 | two openable picture books (animals; early America) | `content/books.json`, W3c #13 | COVERED* | item 44 (generated content) |
| V2-131 | a wire bead maze | W3c #13 (bead maze), W4b #2 | COVERED |  |
| V2-132 | a playable tilt marble labyrinth. Controls are deliberate, do not change: W/S tilt forward and back; up and down... | `tilt_labyrinth` with fixed controls, `InputMap`, §3.16, W4b #2 | COVERED |  |
| V2-133 | Museum with readable exhibits | `museum` lot type, `content/exhibits.json`, W3c #13 | COVERED* | item 44 (generated content) |
| V2-134 | Bowling alley with fully playable lanes: choose your angle and power, bowl, physics pins, the ball returns up the... | `bowling` minigame, §3.16, W4b #1, S13, OS-5c | COVERED |  |
| V2-135 | The ball-return tunnel is a real squirrel route: a squirrel can run the length of it under the lane and pop out at... | `bowling_alley` `rack_tunnel_lane_*` routes, W3c #13 exit check, §5.3 P4 hero piece | COVERED |  |
| V2-136 | three pinball machines (distinct themes, real flipper physics) | pinball x3 (client physics), §3.16, W4b #2 | COVERED |  |
| V2-137 | two pool tables | `pool` minigame, W4b #2 | COVERED |  |
| V2-138 | a bumper pool table | bumper-pool variant, W4b #2 | COVERED |  |
| V2-139 | a working dartboard beside the pool tables (mouse sets the aim point, a timing meter sets power, slight wobble so... | `darts` 501 and cricket, §3.16, W4b #2 | COVERED |  |
| V2-140 | a free-play fortune-teller slot machine: pull the lever, reels spin, it dispenses a fortune or a taunt. No money... | `fortune_machine` (no money in or out), §3.16, W4b #2 | COVERED* | item 44 (fortune-teller styling) |
| V2-141 | Realistic back of house: steel push-bar exit doors to an alley with big round dark-blue used trash cans and a push... | §3.17 `backOfHouse` props and forage sockets, W3c #13 | COVERED |  |
| V2-142 | No scrimping (bowling) | W4b order (bowling first), W5 #9 polish | COVERED |  |
| V2-143 | Racquetball court, playable against NPCs or players, with real ball physics | `racquetball` minigame, `RacquetballOpponent` brain, W3c #13, W4b #2 | COVERED |  |
| V2-144 | Elaborate steakhouse: outdoor bar, glass walls squirrels can see through but not enter (a human refuge) | `steakhouse` lot type (`SquirrelBlocked`, Humanoid-only doors), W3c #13 | COVERED |  |
| V2-145 | sand with a beach ball and a working volleyball net | `volleyball` minigame, W3c #13, W4b #2 | COVERED |  |
| V2-146 | a playable four-foot giant Jenga on a deck table | `giant_jenga`, §3.16, W4b #2 | COVERED |  |
| V2-147 | Ocean side: jet ski rental | `JetSkiMotor`, D27, W3b #5 marina stands, W4b #4 | COVERED |  |
| V2-148 | parasailing | `rides/parasail.json`, W4b #4 | COVERED |  |
| V2-149 | A sky lift up a slight hill to a hilltop restaurant (second vantage over the town) | D32, W3b #11 (hill, `SkyLift`, `restaurant_hilltop`), W4b #4, OS-7 | COVERED |  |
| V2-150 | Paintball arena inside a big abandoned five-storey TV station | `tv_station` lot type, W3a #6 greybox, W3c #13 | COVERED |  |
| V2-151 | runs as its own match, rodent-free | D29 (in-server instanced match), `ArenaService`, S18 | COVERED* | item 42 (venue) |
| V2-152 | 20 spicy cents buys five in-game days of access, which also unlocks five days in the lounges | `PaintballRules.pass`, `prices.json`, W4 #10 | COVERED* | item 38 (5 days = 6 real minutes) |
| V2-153 | Priority is mechanics, not looks: the marker can be generic and even silly-looking, but it must shoot right | §5.3 P3 garb note, W4 #10 (greybox arena, generic marker) | COVERED |  |
| V2-154 | projectile with travel and slight drop | `arena.json` projectile, W4 #10, S18 | COVERED |  |
| V2-155 | a five-shot magazine that auto-reloads when empty or reloads on a button press | `arena.json` magazine, W4 #10 | COVERED |  |
| V2-156 | server-side hit detection with lag compensation | D29 lag compensation, `MoveValidator` pose history, S18, `Paintball` suite | COVERED |  |
| V2-157 | paint splats that stay on walls and players | `arena.json` splat pool, W4 #10 | COVERED |  |
| V2-158 | a five-floor layout with stairwells and a central atrium for verticality | W3a #6, W3c #13 | COVERED |  |
| V2-159 | team deathmatch 4v4 to 8v8 with NPC bots filling empty slots | D25 and D29 borrowed bots, `PaintballBot`, S19 | COVERED |  |
| V2-160 | a match timer, scoreboard and end card | W4 #10 | COVERED |  |
| V2-161 | distinct audio for fire and hits | D24 library, W4 #10 | COVERED |  |
| V2-162 | sprint and crouch that feel right | `Controllers/Paintball`, Tunables `human.crouchHeightMult`, W4 #10 | COVERED |  |
| V2-163 | If the mechanics are not good it gets cut; Ben will not keep a weak version | G-PB (§4.1), OS-5b, risk 26 | GATED | the owner's verdict after the W4 playtest: keep, fix or cut |
| V2-164 | Build it in Wave 4 and playtest with Ben before calling it done | W4 #10, OS-5b | COVERED |  |
| V2-165 | players can buy upgraded paintball garb at one Spicy Dollar per set, kept permanently | `prices.json` garb, profile wardrobe (D26), W4b #9 | COVERED |  |
| V2-166 | a few Blender-made outfit sets (mask, chest rig, pads), each in four colourways, green, blue, red and yellow, and... | §5.3 P3 garb sets, S16, W4b #9 | COVERED |  |
| V2-167 | Players can take the garb off or keep wearing it around town for the rest of the session if that works with the... | D13 accessory path, S16, W4b #9 | COVERED |  |
| V2-168 | Check that custom clothing meshes can be applied to a possessed human body in Roblox; if full outfits are not... | S16 | COVERED |  |
| V2-169 | Lounge one: squirrel-proof, very tough NPC guards who annihilate any squirrel that tries | `LoungeGuard` brain, §3.17 `lounge_classic`, W4b #8 | COVERED* | item 40 (a healthy player squirrel killed by a guard) |
| V2-170 | Elaborate Blender interior, leather and woodwork, fancy counters | §5.3 P4 lounge kits, W5 #8-#9 | COVERED |  |
| V2-171 | a classy 1940s-style bartender serving hot cocoa, coffee, green tea and snow cones | `Bartender` brain, `prices.json` consumables, W4b #8 | COVERED |  |
| V2-172 | Stock licensed jazz from Roblox's music library, 1920s feel | D24 library jazz, W4b #8 | COVERED |  |
| V2-173 | Lounge two: futuristic and surreal, sci-fi and space, lava lamps, dense plants | §5.3 P4 sci-fi lounge kit, W5 #8 | COVERED |  |
| V2-174 | a seamless procedurally generated ambient loop | D24 (layered library pads or one upload), W4b #8 | COVERED |  |
| V2-175 | New small shopping mall with the showpiece: an indoor skydiving wind tunnel | `mall_small` lot type (Galleria builder), `rides/wind_tunnel.json`, W3c #13, W4b #4 | COVERED |  |
| V2-176 | You float in a glass cylinder while silly instructors throw giant balls that bounce off you | `Instructor` brains, server-owned balls (§1.7), W4b #4 | COVERED |  |
| V2-177 | other players can pay Spicy Dollars to add 10 balls | `prices.json` wind_tunnel_balls, W4b #4 | COVERED |  |
| V2-178 | Rodent, regular squirrel, deer and fox stay in standard third person | `CameraPolicy` (animals third person) | COVERED* | item 39 (the rodent's stalk camera) |
| V2-179 | Humans can toggle first person at any time | `CameraRig` human toggle, W2 #6c anchor 6, FRB H15 | COVERED |  |
| V2-180 | Interiors, vehicles and the gondola must hold up at eye level | §5.6 first-person bar, §5.2 vehicle contracts, W3c exit check | COVERED |  |
| V2-181 | Boarding the sky-lift gondola or getting into any vehicle switches to first person automatically; the toggle remains | `CameraPolicy` vehicle and gondola first person, S14, FRB H14 | COVERED |  |
| V2-182 | Vehicles need modelled interiors and dashboards | §5.2, §5.3 P3 (6 interiors), W3c #14, W5 #4 | COVERED |  |
| V2-183 | Paintball and both lounge interiors are locked to first person | `LockFirstPerson` zones, §3.17 `cameraLock`, W4 #10, W4b #8 | COVERED |  |
| V2-184 | Where a default is not named here, accept it (drive on the right, north is +Z, squirrel 1.2 studs at the shoulder,... | §8 (every default recorded), `docs/DECISIONS.md` | COVERED |  |
| V2-185 | 10, day length: accept 72 real seconds per in-game day with sunrise and sunset held longer, winter about every 50... | D19, dec 10 decided | COVERED |  |
| V2-186 | 11, hidden win: accept the half-town trigger, but the ending is the outbreak cinematic in section 8, not an end card | D17, D31, dec 11 decided | COVERED |  |
| V2-187 | 12, rodent health: accept 100 / 55 / 1.5x, plus the drain and bite-heal rules in section 8 | D33, dec 12 decided | COVERED |  |
| V2-188 | 13, map sightings: accept. Police and drone see everything; hospital staff see bite locations only; markers fade... | dec 13 decided, `markers.json` | COVERED |  |
| V2-189 | 14, driving and traffic: accept, with additions. Everyone obeys traffic law in town, police included | `TrafficLaw`, §3.6 `playerLaw`, W4 #12, dec 14 decided | COVERED |  |
| V2-190 | An officer who hits a pedestrian loses the car, sits in a cell, and is demoted to lowest rank on release | §3.7 `traffic.hitPedestrian` rule, W3a #4 cells, W4 #12 | COVERED |  |
| V2-191 | the pedestrian wakes up in a hospital bed as an uninfected patient | `SweptCollision` `Knockdown`, `HospitalService.admit` trauma, W4 #12 | COVERED* | item 44 (player pedestrians) |
| V2-192 | A player driver who runs over the rodent gets the kill credit and the section 6 promotion | §3.7 `rodent.killed by = driver`, FRB P8, M5 | COVERED |  |
| V2-193 | 18, town layout: accept the 34 + 6 homes with a south-east school and church block, and the marina, pier and beach | dec 18 decided, OS-3 | COVERED |  |
| V2-194 | The approval map must also show the steakhouse, the hill with sky lift and hilltop restaurant, the TV station, the... | OS-3 town-plan page with the 12 sites, D32, W3 'before building' | COVERED |  |
| V2-195 | 19, hollow trees: 12 not 11; see section 3 | dec 19 decided; V2-1, V2-6 | COVERED |  |
| V2-196 | 20, old web-game extras: keep Power exactly as v5.4 implements it (table below) | `Rodent/PowerRules`, §4.15 D-21, W1 #6b, W2 #1, FRB R8 | COVERED |  |
| V2-197 | drop Gold | dec 20 decided (Gold dropped) | COVERED |  |
| V2-198 | coins become Spicy Dollars | W4 #9 (coins to Spicy cents), dec 20 decided | COVERED |  |
| V2-199 | chili rush becomes a rodent-only power-up | W4 #1 chili rush, §4.15 D-8 | COVERED |  |
| V2-200 | sewer and fashion stand stay with outfits as cosmetics | W4 #9 fashion stand (cents; wardrobe in the profile), §4.15 D-9 | COVERED |  |
| V2-201 | cats and dogs stay | W4 #5 `YardHazards`, §4.15 D-5 | COVERED |  |
| V2-202 | 23, art: no money is ever spent on art and no outside artist | §5.6 (no artist fallback), risk 4, knob 5 withdrawn, dec 23 decided | COVERED |  |
| V2-203 | Everything is made procedurally in Blender by the coding session and approved by turntable | §5.1, §5.6, G2 | COVERED |  |
| V2-204 | Rough is fine; what must be covered is contours, textures, colours, shading and shadows, and the basic movement set | §5.6 G2 pass bar | COVERED |  |
| V2-205 | Polish goes where people pay or play: extra lighting detail in both lounges and the paintball arena, and every... | W5 #9 polish pass, §5.3 polish slots, W4b ironing-out checks | COVERED |  |
| V2-206 | Detail is high on the ridge and anything near town; the far distance is painted scenery | W6 #6 detail by distance, D32 (the ridge is playable), W6 #1 bands | COVERED |  |
| V2-207 | 24, content rating: accept mild. Rewrite the v5.4 swearing lines to keep the venom and lose the vocabulary; skate... | W4 #8 rewritten lines, W2 anchor 7, dec 24 decided, risk 11 | COVERED |  |
| V2-208 | 28, player slots: server caps at 49 (section 5). No late-joiner overflow | dec 28 decided, §1.5, D23 | COVERED |  |
| V2-209 | Rides versus minigames: parasailing, the sky lift and the wind tunnel are rides: no controls, no score, you get on... | `Ride` framework, §3.16, D28, W4b #4 | COVERED |  |
| V2-210 | Minigames have controls and a result: bowling, pinball, pool, bumper pool, darts, racquetball, paintball, the tilt... | `Minigame` framework, §3.16, D28, W4b, OS-5c | COVERED |  |
| V2-211 | Layered distant fog goes into Wave 6 with the backdrop | W6 #1 | COVERED |  |
| V2-212 | Street lighting: lamps on every block with warm pools of light and a few that flicker, porch lights, glowing shop... | D30, `LampPlan`, §3.19, inv 18, W3a #5, W6 #4, S17 | COVERED |  |
| V2-213 | The drone pilot and the outbreak cinematic both depend on this | D30 Skyline emissive heads, S11 and S17, W4 #13 | COVERED |  |
| V2-214 | Off-road zone: beyond a ridge with real trees, a beach that runs out past the public area into a back field with hills | D32, `offroad` district, `terrain_extensions.json`, W3b #12, S6 and S11 re-run | COVERED |  |
| V2-215 | No tickets and no arrests there; police have no jurisdiction, though the drone can see it | `districts.json` `jurisdiction`, §3.6, inv 19, W4 #12 | COVERED |  |
| V2-216 | The top two ranked humans can drive any pickup or SUV in town (place 6 pickups and 4 SUVs) | `Ladder.subroles.humanDriver`, D27, `placements.json`, inv 17, W3b #12, W4b #10 | COVERED |  |
| V2-217 | This is undocumented in-game; players discover it | §1.5 Devices (prompts only for key holders), `kinds.json` `undocumented` | COVERED |  |
| V2-218 | Otherwise only police drive | D27 (carts and bikes are not 'driving') | COVERED* | item 44 |
| V2-219 | Open: whether Ben's Roblox account is ID-verified (gates audio uploads at 100 a month versus 10). Ben has Roblox... | Addendum B2, D24 (100 a month), dec 30 decided | COVERED |  |
| V2-220 | Power table: Bite a person +100 | Tunables `power.bitePerson`, `PowerRules` golden | COVERED |  |
| V2-221 | Power table: Bite a person while world Y is above 4 units +150 instead | Tunables `power.bitePersonHigh`, `highAboveGroundU` | COVERED* | item 43 (absolute Y quirk) |
| V2-222 | Power table: Bite a police officer +130 | Tunables `power.biteOfficer` | COVERED |  |
| V2-223 | Power table: Bite and convert an uninfected squirrel +90, once per squirrel | Tunables `power.convertSquirrel` (once per squirrel) | COVERED |  |
| V2-224 | Power table: Hit by a police baton -19 | Tunables `power.batonHit`, `pedestrianKick` | COVERED* | item 43 (v5.4 also charges the pedestrian kick) |
| V2-225 | Power table: Hit by a yard cat -12 | Tunables `power.catHit`, W4 #5 | COVERED |  |
| V2-226 | Power table: 10 real minutes of active play without a successful bite: lose 15% of current Power, rounded up;... | Tunables `power.fadeAfterActiveMin`, `fadePct`, active-play clock, §6.2 | COVERED |  |
| V2-227 | A successful bite resets the fade timer. Power never drops below zero. Chilis, coins, climbing and missed pounces... | `PowerRules` (bite resets the fade; floor 0; no other sources) | COVERED |  |
| V2-228 | Stages shown on the HUD: FERAL below 600, RABID 600 to 1,499, SUPER at 1,500 or more | rodent HUD, Tunables `power.stages`, FRB R8 | COVERED |  |
| V2-229 | Keep it as the rodent's visible status meter; it is reputation, health is survival | `UI/*` two meters, D33 | COVERED |  |

### 10.5 The delta's conflicts (C1-C22) and where revision 3 resolves them

| Conflict | Resolution in this plan |
|---|---|
| C1 the 49-slot hard cap versus the overflow design | §1.5 (MaxPlayers 49; the posts-and-floors mechanism kept for humans past 35; "overflow" retired), D23, inv 20, `Cap49`, FRB M9 |
| C2 NPC staffing floors and staffed attractions versus the body budget | §1.5 budget table (police 6, hospital 10, crews, attraction posts), D25 borrowed bodies for bots and staff, S19, D4 fallbacks (silent posts as non-Humanoid rigs; street and shop floors cut first) |
| C3 the outbreak cinematic versus the end card | D17 (rev 3), D31, `OutbreakDirector`, W4 #13, W3a #5 lamps first, `OutbreakCinematic` suite |
| C4 infection reset on rodent death versus per-actor persistence | §1.5 "Rodent death is not a reset", `InfectionService.resetToRodent`, §3.7 rows, W2 #2, FRB R11, M10 |
| C5 health drain versus regeneration | D33 (regen 0.25 and 1 hp/s; drain and heals as the main recovery; alert kick multiplier below 1.82), Tunables `rodent.*`, FRB R7-R9 |
| C6 the human rank formula and the currency | one currency (D26); `Ladder.score` split into the human queue (time + money + reputation + entourage + kicks + quests, gated at 10 days) and the administration score (performance only); item 43 for the numbers |
| C7 "appearance properties, not tinting" versus D22 and D13 | D13 and D22 (rev 3): skin as part colour, face decal, hair accessory, no accent zones; animals keep the A3 blend (Addendum B1); A3-6 DROPPED; item 37 |
| C8 "otherwise only police drive" versus carts, bikes, pickups and SUVs | D27 `VehicleKinds`, `Ladder.subroles.humanDriver`, §3.18, item 44 (carts and bikes are not "driving") |
| C9 humans killing infected squirrels; guards killing squirrels | §3.7 `squirrel.killed` rows, `Ladder.params.infectedSquirrelHealth`, hospital-first promotion, W4 #1, W4b #8 guards, item 40 |
| C10 Robux products and permanent wardrobes versus "no cross-server saving" | D14 (rev 3), D26, `Persistence/Profiles` in W4 #11, S15, `Economy` and `Persistence` suites, OS-0 (products, API services), item 41 |
| C11 the world footprint | D32 `terrain_extensions.json`, W3b #11-#12, S6 and S11 re-run, OS-3 with the 12 sites, OS-7 hill vantage |
| C12 paintball in the server versus a separate place | D29 (in-server instanced match; TeleportService as the fallback), S18, W4 #10, G-PB at OS-5b, item 42 |
| C13 first-person requirements versus box-and-ghost vehicles and the v5.4 stalk | `CameraPolicy`, D27 interiors, S14, §5.2 vehicle contracts, §5.6 first-person bar, item 39 (stalk) |
| C14 everyone obeys traffic law, pedestrians can be hit | `TrafficLaw`, §3.6 `playerLaw`, §3.7 jail and demotion rows, `SweptCollision` `Knockdown`, W4 #12, item 44 (player pedestrians) |
| C15 Power kept versus "drop Power" | `Rodent/PowerRules`, §4.15 D-21, Tunables `power.*`, rule 11, W1 #6b, W2 #1, FRB R8, item 43 (two verbatim gaps) |
| C16 street lighting everywhere versus the lighting mapping and budgets | D30, `LampPlan`, §3.19, inv 18, W3a #5 greybox, W6 #4 final, S17, Skyline emissive heads |
| C17 physics minigames versus a plan that avoided physics | D28 authority by stakes class, §1.7 rows, S13, `Minigames` suite, W4b ironing-out checks |
| C18 twelve hollows versus eleven | §3.5 H12 escape variant, §5.5, inv 5, dec 19 decided |
| C19 finite nuts versus cooldown regeneration | `ForageRules.stock`, `seasonStock`, inv 15, `SimLong` ownership assertion |
| C20 in-game-day cadences against a 72-second day | every cadence a Tunable on the game clock (`forage.ownVisitDays`, `economy.paintballPassDays`, `reputation.votesPerDay`, `Ladder.params.rankGateDays`, `rodent.drainPerDay`); item 38; risk 28 |
| C21 "no money, no artist" versus the GATED rows and risk 4 | §5.6 G2 bar and no artist fallback, risk 4, knob 5 withdrawn, rows 7-6 and 7-7 COVERED |
| C22 rides versus minigames and the ironing-out owner time | D28, §3.16 (`ironOut` flags), W4b acceptance check, OS-5c (about 90 minutes), §4.14 owner time |
