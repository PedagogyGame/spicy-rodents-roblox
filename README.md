# Spicy Rodents on Roblox

The Roblox rebuild of *Spicy Rodents* (the v5.4 "Living Town" HTML game is the mechanics
reference). Everything lives in git; the place is a build artifact. The plan is
`docs/spec/BUILD_PLAN.md`; this README is the brief §14 deliverable: the module layout and how
to add a lot type, a route or a role.

## Layout (Rojo tree, BUILD_PLAN §1.2)

| Disk | Instance | What lives there |
|---|---|---|
| `src/shared/` | `ReplicatedStorage.Shared` | Pure modules: `Config` (Units, Tunables, Flags), `Data`, `Util`, `Net`, `Time`, `World`, `Routes`, `Movement`, `Actors`, `Roles/Ladder`, `Combat`, `Infection`, `Traffic`, `Foraging`, `Avatar`, `Economy`, `Map`, `Quests`. Most run under Lune. |
| `generated/` | `ReplicatedStorage.Shared.Generated` | Compiler output of `tools/compile` (committed; CI fails if stale). `Shared.Data` is the accessor module over it. Optional until the compiler lands. |
| `src/server/` | `ServerScriptService.Server` | `Main.server.luau` (the only Script), `Boot`, `Actors` (ActorService, BodyFactory, Possession, BrainScheduler, Brains), `Movement/MoveValidator`, `Roles`, `Combat`, `Infection`, `Hospital`, `Police`, `Drone`, `Vehicles`, `Sightings`, `Quests`, `Economy`, `Jobs`, `Homes`, `Community`, `Mall`, `Wildlife`, `Rodent`, `Cosmetics`, `Foraging`, `Seasons`, `Avatar`, `Assets`, `Telemetry`, `Persistence`. |
| `src/worldgen/` | `ServerScriptService.Server.WorldGen` | `Bake`, `Factory`, `Plan`, `Kits`, `TerrainBake`, `Builders/*`. ModuleScripts only; run by Lune (bake), by the server as a fallback and by the plugin. |
| `src/client/` | `StarterPlayer.StarterPlayerScripts.Client` | `Main.client.luau` (the only LocalScript), `Possession`, `Controllers`, `Input`, `Camera`, `Animation`, `Render`, `UI`, `World`, `Audio`. |
| `assets/` | `ReplicatedStorage.Assets` | Content, not code (`.rbxm`, `.model.json`). Never a SurfaceAppearance, union or BaseWrap. |
| `tests/engine/` | `ServerStorage.EngineTests` (CI place only) | Suites that run in the real engine through Open Cloud Luau Execution. |

Project files: `default.project.json` (code + data + assets; live-sync capable), `build.project.json`
(adds `build/Town.rbxm` -> `Workspace.Town` when the bake exists), `ci.project.json` (adds
`tests/engine` -> `ServerStorage.EngineTests`). The Workspace, Players and Lighting properties the
plan requires (StreamingEnabled, ModelStreamingBehavior Improved, StreamOutBehavior Opportunistic,
PlayerCharacterDestroyBehavior Disabled, SignalBehavior Deferred, CharacterAutoLoads false,
MaxPlayers 49, Technology Future) are set in all three and asserted by the place test. Note that
the live player cap is the place's `serverSize` in Creator Hub, not the project property.

**Requires.** Modules use relative string requires (`require("./Moon")`, `require("../Util/Rng")`,
`require("@self/Child")` from an `init.luau`), which resolve identically under Lune, luau-lsp and
the Roblox engine (verified in spike S1). Tests may use the `.luaurc` aliases (`@shared/...`).

## Toolchain

Pinned in `rokit.toml` (rojo 7.7.1, lune 0.11.1, stylua 2.6.0 with the Luau feature, selene 0.31.0,
luau-lsp 1.70.1). In the cloud container, `docs/ENVIRONMENT_SETUP.sh` installs the same versions
with cargo, plus the bpy 5.2.3 venv. Lint: `selene.toml` with the committed `roblox.yml`; format:
`stylua.toml`; types: `.luaurc` (strict) and `luau-lsp analyze` in GitHub Actions.

## Everyday commands

```bash
tools/ci.sh                   # stylua --check, selene, Lune unit tests, rojo build (.rbxl/.rbxlx,
                              # default/ci/build projects), Lune place tests, sourcemap (< 2 s)
lune run tests/run.luau       # unit tests only (add words to filter: lune run tests/run.luau moon)
rojo build ci.project.json -o build/test.rbxl
lune run tests/place/check_place.luau build/test.rbxl ci.project.json
node tools/cloud/cloud.mjs help         # Open Cloud: save_place, run_engine_tests, upload_asset ...
```

See `tools/cloud/README.md` for the cloud loop and `docs/spikes/` for spike results.

## How to add things (where the plan puts them)

- **A lot type** (BUILD_PLAN §3.3): add `data/lot_types/<type>.json` (HTML units), run `tools/compile`,
  commit `generated/`. The builders in `src/worldgen/Builders` pick the family from the type's
  `category`; no code change for a new shop.
- **A route** (§3.5, D8): harvested routes come from `tools/harvest` and are never hand-edited;
  corrections go in `data/harvest_patches.json` with a reason. Template routes for rebuilt lots are
  emitted by the lot type's `routes` block and linked by the compiler.
- **A role** (§3.7, rule 2): the ladder is stated once in `src/shared/Roles/Ladder.luau`, numbers
  included (`Ladder.params`). Add the rung there with its slots, score and transitions; services
  execute the Ladder's results and never restate them. A Lune test fails on any ladder literal
  elsewhere in `src/` or `data/`.

## Status

Wave 0 (foundation): skeleton stubs, toolchain, CI, Lune harness and Open Cloud tooling. No
gameplay yet. `CHANGELOG.md` lists every saved place version.
