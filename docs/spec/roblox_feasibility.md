# Spicy Rodents: Roblox toolchain and platform feasibility

Date: 2026-11-09. Environment: Linux cloud container (4 cores, 15 GiB RAM, about 28 GB free), no GUI, no Roblox Studio, no Roblox account or credentials used. Nothing was published and no accounts were created.

Scratch work is under `/root/feasibility`:

- `rojo-smoke/` is the Rojo test project, with its tests and lint config.
- `blender/` holds the bpy rig test, its outputs and an FBX inspector.
- `docs_raw/` is a sparse checkout of the official `Roblox/creator-docs` repo.

**Bottom line.** All code-side tooling runs headless here except a Luau type checker:

- Rojo builds `.rbxl`/`.rbxlx`.
- Lune runs unit tests and reads and writes place and model files.
- StyLua and Selene work, each with one non-default step.
- Blender 5.2.3 (the `bpy` wheel) builds, skins, animates, exports and re-imports rigs.

Everything that turns files into Roblox assets needs Studio on the Mac and a Roblox account. That covers mesh import, animation import and publishing, SurfaceAppearance, playtests and the final publish. Open Cloud would automate parts of it, but `apis.roblox.com` is blocked from this container.

How the research was sourced:

- `create.roblox.com` and `devforum.roblox.com` are blocked here (403 at the proxy). `raw.githubusercontent.com` and `git clone` from github.com work.
- I read the official docs straight from the `Roblox/creator-docs` GitHub repo (commit `ccc2b01`, 2026-11-07). Findings with a `creator-docs:` source are high confidence.
- DevForum material came only through web-search snippets and is marked lower confidence.

---

## Part A: Hands-on toolchain

| Tool | Version | How installed | Smoke test | Notes |
|---|---|---|---|---|
| Rojo | 7.7.1 (2026-10-01) | `cargo install rojo --locked` (about 1.5 min) | PASS | Built both `test.rbxl` (3.6 KB) and `test.rbxlx` (6 KB). Tree covered `ReplicatedStorage/Shared`, `ServerScriptService/Server`, `StarterPlayer/StarterPlayerScripts/Client`, two `.luau` modules, a `.server.luau`, a `.client.luau`, a `.model.json` (Model with AnimationController and Animator), an `.rbxmx` (Part with PointLight) and a `.rbxm` KeyframeSequence. `rojo sourcemap` works. Subcommands: `build serve sourcemap syncback upload plugin init fmt-project`. |
| Lune | 0.11.1 | `cargo install lune --locked` (about 3 min) | PASS | 7/7 Luau unit tests passed (`tests/run.luau` requires `src/shared/*.luau` by relative path). `@lune/roblox` opened `test.rbxl` and `test.rbxlx`, walked all 20 instances, and read properties and script `Source`. It also built a KeyframeSequence with Poses, wrote it to `.rbxm`, and read it back. |
| StyLua | 2.6.0 | `cargo install stylua --locked --features luau` | PASS (with the luau feature) | **Gotcha:** plain `cargo install stylua` builds without Luau syntax, so a config with `syntax = "Luau"` fails to parse and directory checks silently do nothing. Rebuilt with `--features luau`. `--check` then flagged the unformatted files, and `stylua src tests` fixed them. npm alternative: `@johnnymorganz/stylua-bin` 2.6.0 ships per-platform binaries on npm, so it needs no GitHub. |
| Selene | 0.31.0 | `cargo install selene --locked` | PASS (after one workaround) | **Gotcha:** `std = "roblox"` generates `roblox.yml` by downloading the Roblox API dump with `ureq`. Selene's build of `ureq` ignores `HTTPS_PROXY` and the proxy CA, so it fails here with "error when getting API dump". Workaround: rebuild Selene with ureq features `proxy-from-env` and `native-certs` (patched copy in `/root/feasibility/src/selene-patched`, binary in `/root/feasibility/selene-patched-bin/bin/selene`), run `generate-roblox-std` once, and stock `selene` then reuses `roblox.yml`. Lint on a sample gave 2 `unused_variable` and 1 `multiple_statements` warning. Recommendation: commit `roblox.yml` or generate it on the Mac. |
| Luau type checker | none available here | none | NOT OBTAINED | Not on crates.io, PyPI or npm as a usable CLI. Details below. |
| Blender Python | bpy 5.2.3 (Blender 5.2.3 LTS) on Python 3.13.18 | venv `/root/feasibility/venv`, `pip install bpy==5.2.3` (403 MB wheel from PyPI) | PASS | Results and FBX settings below. Harmless log noise: Draco and MeshOptimizer libraries are missing, which only affects glTF compression. |

### A4. Luau type checker: what is obtainable

- **crates.io:** `luau-analyze` 0.0.1 is a third-party in-process type-checker library and `luau-analyzer-sys` 0.1.1 is a set of bindings. Neither is a ready CLI, and both would need a wrapper written around them. `luau-cli` 0.739.0 (luau-rs) is an interpreter and compiler, not an analyzer.
- **PyPI:** nothing. The `luau` package there is an unrelated script helper.
- **npm:** `luau-lsp` 1.0.0 is a 3 KB third-party wrapper (`@unrealworks/rkkit-core`) that downloads the GitHub release binary, which is blocked here. No `luau-analyze` package exists.
- **From source:** `git clone https://github.com/JohnnyMorganz/luau-lsp` (main at 1.70.1+, Luau submodule from 2026-10-09) succeeded. The repo bundles current Roblox type definitions (`scripts/globalTypes.d.luau`). Building it with CMake and Ninja (cmake 3.28, g++ 13, ninja are all present) was **denied by this session's permission policy** because the source came from outside the registries. I did not try to work around that.
- **Recommendation:** run `luau-lsp analyze --definitions=globalTypes.d.luau --sourcemap=sourcemap.json src/` on the Mac (installed with Rokit) and in CI. Alternatively, explicitly allow a source build in this container.

### A5. Blender rig, animation and export test (`/root/feasibility/blender/rig_export_test.py`)

What the script built:

- A 13-bone squirrel armature: `Root` (non-deform, at the origin), Hips, Spine, Chest, Neck, Head, Tail1 to Tail3, and four legs.
- A 2,096-triangle mesh skinned by distance weights, with at most 2 influences per vertex and no weights on Root.
- Two actions: **Run** (frames 1 to 20) and **Leap** (frames 1 to 30).

It wrote these exports to `/root/feasibility/blender/out/`:

| File | Content | Re-import into a fresh scene |
|---|---|---|
| `squirrel_all_actions.fbx` | rig and mesh, all actions as separate takes | 1 armature, 13 bones, 1 skinned mesh (2,096 tris), scale 1.0, **2 actions**: Run 1 to 20, Leap 1 to 30, 139 curves each. Takes are re-based to start at time 0. |
| `squirrel_Run.fbx`, `squirrel_Leap.fbx` | rig and mesh with one clip each | 13 bones, 1 action each. The take is named after the **scene**, so the script renames the scene to the clip name. The take keeps absolute frame numbers (`LocalStart` = 1). |
| `squirrel_rig_only.fbx` | rig and mesh, no animation | 13 bones, skinned, 0 actions |
| `squirrel.glb` | glTF binary with all actions | 13 bones, 2 actions (Run 1 to 20, Leap 1 to 30). The 2nd mesh is Blender's glTF bone-display icosphere. |

Raw FBX header (read with Blender's bundled parser): FBX 7400, UpAxis Y, FrontAxis Z (sign −1), UnitScaleFactor 100, 30 fps.

**FBX export settings for Roblox skinned custom rigs with animation.** Sources: creator-docs `art/modeling/export-requirements.md`, `art/blender.md`, `avatar/character-bodies/export.md`, `art/modeling/specifications.md`.

| Blender FBX option (`bpy.ops.export_scene.fbx`) | Value | Source and confidence |
|---|---|---|
| Scene Units, Unit System | **None**, so 1 BU = 1 stud | art/blender.md (high) |
| Path Mode / Embed Textures | **Copy** / **on** | export-requirements.md (high) |
| Apply Scalings (`apply_scale_options`) | **FBX Unit Scale** (`FBX_SCALE_UNITS`), other scales at 1.0 | export-requirements.md, art/blender.md (high). Fallbacks: export Scale 0.01, or scene Unit Scale 0.01. |
| Forward / Up (`axis_forward`, `axis_up`) | **Z Forward**, **Y Up** | art/blender.md export section (high that the docs say this). A model facing Blender −Y should then face Roblox LookVector (−Z); verify once in Studio with an arrow prop (medium). |
| Apply Transform (`bake_space_transform`) | **off**; apply rotation and scale in Blender first | Docs don't mention it. Rig spec says bones must be frozen (rotation 0, scale 1) and the root at 0,0,0 (high on the spec, inference on the option). |
| Add Leaf Bones | **off** | export-requirements.md, character-bodies/export.md (high) |
| Bake Animation | **on** only when exporting animation | export-requirements.md (high) |
| NLA Strips / All Actions / Force Start-End Keying | **all off**; set the timeline Start and End to the clip; Simplify **0.0** | character-bodies/export.md (high) |
| Clips per file | **one animation track per FBX** | specifications.md: "Only a single animation track can be exported with a mesh or model… create separate exports for each animation" (high). An "all actions as takes" FBX is fine for Blender round trips but is **not** what Studio expects. |
| Rig rules | max **4 influences per vertex**; no influence on Root; root bone at origin; **20,000 triangles per mesh** | specifications.md (high) |
| Bone count | no documented per-mesh cap found; Importer drops zero-influence bones unless "Keep Zero Influence Bones" is on | studio/importer.md (high); bone cap unknown (low) |

Practical recommendations from the test:

- Key every clip from frame 0, or set the timeline start to the first key, so the take doesn't begin with an empty frame.
- Name the scene after the clip, or give each clip its own `.blend` scene.
- Batch-export one FBX per clip from a script: rig only, then `Run`, `Climb`, `Wire`, `Leap`, `Pounce`, `BiteDance`, `Sneak`.

---

## Part B: Platform research

### a. Possessing a pre-existing NPC body mid-stride (and handing it back)

**Finding: feasible.** `Player.Character` is writable from the server (write security None, per creator-docs `Player.yaml`). The pattern:

- Spawn no avatars: `Players.CharacterAutoLoads = false`; never call `LoadCharacterAsync`, since `LoadCharacter` is deprecated in favour of it.
- To possess, the server sets `player.Character = actorModel`.
- To release, the server clears it (`player.Character = nil`) and resumes the AI brain.

Pitfalls (doc-sourced unless marked):

1. **`Workspace.PlayerCharacterDestroyBehavior`**. When Enabled, the engine calls `Destroy()` on a player's *old character when it is replaced* and on the Player when they leave. That would delete actor bodies on every handoff. Set it to **Disabled**; I verified Rojo can set it in `default.project.json`. On `PlayerRemoving`, release the body before cleanup. (creator-docs `Workspace.yaml`; high)
2. **Network ownership.** `BasePart:SetNetworkOwner(player)` applies to the whole connected assembly. Give the possessed root part to the player and hand it back with `SetNetworkOwner(nil)`. DevForum reports that animations only replicate when the client owns the assembly and the `Animator` was created server-side. (DevForum; medium)
3. **Animate script.** The default `Animate` LocalScript arrives only with engine-spawned characters. A possessed NPC has none, so each species needs its own animation driver used by both AI and player control. That fits the brief's one-actor-model rule anyway. (DevForum; medium-high)
4. **Camera.** The default camera follows the Humanoid on `CharacterAdded`. For non-Humanoid bodies (squirrel, fox, deer), a LocalScript must set `Camera.CameraSubject` to a part. (DevForum; medium)
5. **StreamingEnabled.** The client may not have the target body streamed in. Call `player:RequestStreamAroundAsync(pos)` before the swap. Make actor models `ModelStreamingMode = Atomic` so a body never arrives half-streamed. Set `PrimaryPart`, which is the streaming focus. (creator-docs `workspace/streaming/index.md`; high)
6. **Respawn and death.** With `CharacterAutoLoads = false` nothing respawns automatically. Death becomes "possess another body", per the brief's ladder.
7. **Server Authority (beta).** `Workspace.AuthorityMode = Server` keeps characters server-owned with client prediction and rollback. It is still in beta ("will be released soon"). (creator-docs `projects/server-authority/index.md`; high)

**Confidence: medium-high.** The API surface is confirmed. The mid-stride feel, including animation continuity and replication of client-played tracks, needs a Studio prototype in week 1.

### b. Custom non-humanoid rigs and rail or kinematic movement

**Humans.** Use **Humanoid (R15)**. It gives the default controls, clothing through `HumanoidDescription`, and SLIM avatar stand-ins.

**Squirrel, fox and deer.** Use **AnimationController + Animator** and a **custom controller**. The docs say rigs without a Humanoid must use an AnimationController with a child Animator (creator-docs `animation/using.md`).

Movement options:

1. **Client-owned kinematic.** Do this first. The player owns the root assembly, and the client moves it along the rail by arc length `s` and route id, using AlignPosition/AlignOrientation or direct `CFrame`. Physics replication carries it to the server. The server validates:
   - rail adjacency and leap reachability against the shared `Routes` registry;
   - speed per route `kind`;
   - leaky-bucket tolerance. The docs recommend leaky-bucket accumulators for client-movement validation (`scripting/security/network-ownership.md`).

   Send discrete events such as leap, pounce and bite over RemoteEvents, timestamped with `workspace:GetServerTimeNow()`.
2. **Server Authority (beta).** Put the shared movement code in `RunService:BindToSimulation()` in a ModuleScript run on both sides. Inputs go through the Input Action System, and state lives in attributes (the first 64 per instance, strings of at most 50 chars). `Animator:LoadAnimation`, `AnimationTrack:Play/Stop/AdjustSpeed/TimePosition` have simulation access and roll back with the simulation. This is the cleanest anti-cheat model, but it is beta: it requires StreamingEnabled, NextGenerationReplication, deferred signals and fixed simulation, and Tools are not fully supported. (creator-docs `projects/server-authority/index.md`; high on the docs, medium on its readiness for this project)
3. Also available: `ControllerManager` (GroundController, ClimbController, AirController) is a physics character controller that doesn't need a Humanoid. The Character Controller Library (`@rbx/AvatarAbilities`, attribute and ability based, beta) is used by Roblox's "Boneheads" sample under Server Authority. (creator-docs; high that they exist, low-medium that they fit rails)

AI-driven actors with no player can be **anchored** and moved by the server with `workspace:BulkMoveTo`, which avoids physics cost. On possession, unanchor the body and give ownership to the player; on release, reverse it. Anchored parts moved by a client do not replicate. (General engine behaviour; medium-high)

**Confidence: medium-high** for option 1 and Humanoid/AnimationController selection; **medium** for Server Authority.

### c. Importing skinned custom rigs with animations

- **Limits.** 20,000 triangles per mesh, 4 bone influences per vertex, frozen bones, root at the origin, no root influences. I found no documented bone-count cap; DevForum says none. The 37 extra optional bones apply to *advanced R15* avatars only. (creator-docs `art/modeling/specifications.md`; high)
- **Importer.** File > Import (FBX, glTF/GLB or OBJ). For rigged files, set Rig Type to **Custom**. Settings include World Forward/Up, Scale Unit (Studs), "Keep Zero Influence Bones" and "Upload to Roblox" (off for iteration). A glTF import nests one Model per primitive, unlike FBX. (creator-docs `studio/importer.md`; high)
- **Animations.**
  - A rig FBX may carry **one** animation track.
  - Each clip is brought in through the **Animation Editor: … > Import > From File / From FBX Animation** onto the imported rig.
  - Saving creates a `KeyframeSequence` (or `CurveAnimation`) under ServerStorage (`RBX_ANIMSAVES`), referenced from the rig's `AnimSaves`.
  - Before use in a game, each clip must be published with **Publish to Roblox**. Pick the **group as Creator** if the experience is group-owned.

  (creator-docs `animation/editor.md`, `avatar/emotes/import.md`; high) Community reports: custom Blender rigs sometimes import with flipped (−180°) joint transforms or blank keyframes. (DevForum; low-medium)
- **Ownership.** Animation assets must be owned by the experience owner (same user or same group), or "Failed to load animation" errors follow. Group-owned animations are known to fail for some Team Create members in Studio while working live. Asset Privacy settings do **not** govern Animations. (DevForum and creator-docs `projects/assets/privacy.md`; medium-high)
- **Studio-only playback without uploading: yes.**
  - `KeyframeSequenceProvider:RegisterKeyframeSequence()` (and `RegisterActiveKeyframeSequence`) returns a temporary ID for `Animation.AnimationId` that "cannot be used outside of Studio". This service is now **deprecated**; its replacement is `AnimationClipProvider:RegisterAnimationClip()`, which also takes CurveAnimation.
  - KeyframeSequences can live in git as `.rbxm`. I verified that Rojo syncs one into `ReplicatedStorage/Animations` and Lune can generate one. A Studio playtest can therefore play git-tracked clips before they are published.
  - Live servers need published IDs.

  (creator-docs `KeyframeSequenceProvider.yaml`, `AnimationClipProvider.yaml`; high)

### d. Open Cloud

**Assets API** (`POST/PATCH apis.roblox.com/assets/v1/assets`, beta, 20 MB per file):

| Asset type | Formats | Limits |
|---|---|---|
| **Model** | `.fbx`, `.gltf`, `.glb`, `.rbxm`, `.rbxmx` | Becomes a Model of MeshParts, uploaded as a *package*. Only `.fbx` content can be updated in place. |
| **Animation** | `.rbxm`/`.rbxmx` only, holding a KeyframeSequence | "files edited outside of Studio might not upload or function". |
| **Decal/Image** | png, jpeg, bmp, tga | under 8000 px; no updates |
| **Audio** | mp3, ogg, wav, flac | 7 min; 100 per month ID-verified, 10 otherwise |
| **Video** | mp4, mov | |
| **Mesh** | only from the Asset Delivery API | |

- **Scopes:** API key with **assets** permission (Read and Write for the target experience); OAuth scopes `asset:read` and `asset:write`. Rate limit 120 per minute.
- A Blender clip could reach Roblox **without Studio** this way: Blender exports bone curves, Lune builds a KeyframeSequence `.rbxm`, and Open Cloud uploads it as an Animation. This is unverified and carries the docs' warning above.

(creator-docs `cloud/guides/usage-assets.md`, `reference/cloud/openapi.json`; high)

**Luau Execution API** (`/cloud/v2/universes/{u}/places/{p}[/versions/{v}]/luau-execution-session-tasks`, stable). It runs a script against a specific place version, headless:

- Physics does **not** run, and Server and Local scripts do **not** auto-run. The script can read and modify the DataModel (changes are not persisted), `require` ModuleScripts, and reach cloud APIs such as DataStores.
- Script up to 4 MB, runtime up to 5 min, return values up to 4 MB as JSON. Logs up to 450 KB. Binary input up to 100 MiB. At most 10 incomplete tasks per place.
- Create: 5 per minute per key owner.
- Scope `universe.place.luau-execution-session:write`; get and logs also accept `:read`.

It suits **CI unit and integration tests of ModuleScripts in the real engine**: Roles ladder, Infection math, Seasons, Routes, the Traffic swept-collision maths, and WorldGen output checks such as lot counts and overlaps. It does not suit physics or multiplayer tests. (openapi.json schema text; high)

**Place publishing**, two routes:

- Current docs route: Assets API `PATCH /assets/v1/assets/{placeId}` with `assetType: "Place"` and `published: true`, an `.rbxl` or `.rbxlx` body, polled through `operations/{id}`. Omitting `published` saves an unpublished version, which is handy as a CI target for the Luau Execution API.
- Legacy route: `POST /universes/v1/{universeId}/places/{placeId}/versions` (scope `universe-places:write`, beta, 30 per minute).
- **Limitation:** publishing through the API "doesn't update" EditableImage, EditableMesh, **PartOperation (unions)**, **SurfaceAppearance** or **BaseWrap** instances; publish from Studio after changing those. `rojo upload` exists as a wrapper.

(creator-docs `cloud/guides/usage-place-publishing.md`; high)

**Network note:** `apis.roblox.com` is blocked from this container, so none of this can run here even with a key.

### e. Performance and AI budgets

- **No official NPC-count figure.** Community reports converge on **about 100 full Humanoids** as where replication and physics stutter begins. Common fixes:
  - disable unused `HumanoidStateType`s;
  - stop NPC-to-NPC collisions with collision groups;
  - avoid `Humanoid:MoveTo` for crowds;
  - keep Humanoid-free bodies for animals;
  - let the server own state while clients render, interpolate and play animations.

  (DevForum via search; medium) The docs confirm the guidance: disable unneeded Humanoid states, don't use Humanoids for static NPCs, and avoid frequently respawning Humanoid or skinned models. (creator-docs `performance-optimization/improve.md`; high)
- **This brief's load** is roughly 45 to 60 human bodies (35 slots plus staff and street walkers), 10 to 14 squirrels, a few deer, 1 to 2 foxes, plus AI-only birds and insects. Keep Humanoids for humans only, at most about 60. Run animals as AnimationController rigs. Make birds, butterflies and insects **client-only visuals** driven by a seed and the server clock, never server instances.
- **AI tick budget** (recommended; not an official number):
  - Server Heartbeat is 60 Hz. Tick brains at 4 to 10 Hz, staggered across frames.
  - Run LOD by distance to the nearest player. Far actors get coarse "commute" updates and anchored `BulkMoveTo`; near ones get full perception.
  - Aim for under about 4 ms per frame of total AI on the server and profile with the MicroProfiler.
- **Parallel Luau.** Scripts under an `Actor` only run in parallel after `task.desynchronize()` or `ConnectParallel`. Scripts in the same Actor run serially. `require` is not allowed in the parallel phase, and instance writes need `task.synchronize()`. Use a **few Actors that each own a slice of brains**, not one per NPC: compute perception and decisions in parallel, then write CFrames and attributes in the serial phase. Community reports of Parallel Luau gains are mixed. (creator-docs `scripting/multithreading.md`; high; DevForum; medium)
- **Streaming modes.** `Atomic` suits actor bodies, so a rig streams as a unit. `Persistent` is for "very rare circumstances", not NPC crowds. `PersistentPerPlayer` can keep a player's own body, or the drone, always present. Recommended Workspace settings:
  - `ModelStreamingBehavior = Improved`
  - `StreamOutBehavior = Opportunistic`
  - `StreamingMinRadius` 64, `StreamingTargetRadius` 1024 (defaults)
  - `PredictiveStreamingMode` is available
  - Client physics, including Server Authority prediction, only runs in streamed areas.

  (creator-docs `workspace/streaming/index.md`; high)
- **Drone view (important).** Distant models are invisible once streamed out unless `Model.LevelOfDetail = SLIM` (or the legacy StreamingMesh). SLIM is generated by cloud transcoding of the *saved, published* place and works best on static geometry that "don't change at/during runtime". `Workspace.EnableSLIMAvatars` renders distant R15 avatars as animated stand-ins. **So the brief's "WorldGen builds the town from data" should run at edit or build time**, baking the data into the saved place through a Studio plugin or command, with the data file still the source of truth. Runtime generation would rule out SLIM for the drone's whole-town view. (creator-docs `workspace/streaming/slim.md`, `Model.yaml`; high on SLIM's requirements, medium on the conclusion)

### f. Day/night, sky and moon phases

- **Time and sun.** `Lighting.ClockTime` and `TimeOfDay` drive the sun and moon. `GeographicLatitude` moves their paths, taking Earth's tilt into account. `GetSunDirection()` and `GetMoonDirection()` are available. (creator-docs; high)
- **Sky.** `MoonTextureId`/`MoonTextureContent` (default `rbxasset://sky/moon.jpg`); `MoonAngularSize` (default 11°, clamped 0 to 60); `SunAngularSize` (default 21°); `StarCount` (needs `CelestialBodiesShown`); `CelestialBodiesShown`; `SkyboxOrientation`, which can rotate the skybox for slow star drift. (creator-docs `Sky.yaml`; high)
- **Native phases: no.** `Lighting:GetMoonPhase()` "There is no way to change the moon's phase so this will always return 0.75". (creator-docs `Lighting.yaml`; high) Two options:
  1. **Swap `MoonTextureId` per phase**: 8 to 30 pre-rendered phase textures, chosen from the in-game day mod 29.53. This is simple and uses the engine's moon path and glow. A DevForum report says a script-side swap showed a blank moon. Pre-upload the textures, keep them referenced (preload), and test on the client. (DevForum; medium)
  2. **Custom moon**: a client-side billboard or mesh placed at `camera.Position + GetMoonDirection() * far`, with the moon size set to 0. It allows correct terminator orientation relative to the sun and earthshine.

  Use option 1 first and fall back to option 2. The phase maths is already unit-tested in `rojo-smoke/src/shared/Moon.luau`.
- **Clouds and fog.** `Terrain.Clouds` (Cover, Density, Color; renders only when parented to Terrain) and `Lighting.Atmosphere` (Density, Offset, Haze, Glare, Color, Decay) are single global layers. The brief's "fog layering" on mountains therefore needs authored **layered silhouette meshes or cards** (alpha SurfaceAppearance) in front of a tuned Atmosphere. (creator-docs `environment/*.md`; high)
- The blinking tower and silhouette work through Neon parts or PointLights toggled on the client.

### g. SurfaceAppearance and squirrel fur

- **What PBR supports.** SurfaceAppearance has five maps: Color (albedo with alpha), Normal (OpenGL tangent space), Roughness, Metalness and Emissive mask. Alpha modes are Overlay, Transparency, TintMask and Opaque (Opaque is beta).
  - **One SurfaceAppearance per MeshPart.**
  - Most properties are **not script-modifiable** at runtime.
  - The API place publisher doesn't update SurfaceAppearance.

  (creator-docs `art/modeling/surface-appearance.md`, `SurfaceAppearance.yaml`, `usage-place-publishing.md`; high)
- **Texture sizes.** Up to **4096×4096** is supported, and the engine streams lower mips first. Guidance is 256² for a 2×2×2-stud object, which covers a 1.2-stud squirrel, and up to 1024² per map. (creator-docs `art/modeling/texture-specifications.md`; high)
- **Fur that "catches light".** There is no fur shader, anisotropic specular, sheen or subsurface scattering. Realistic options:
  - a well-sculpted body with a strong groom **normal map** and varied **roughness** (grazing-angle highlight);
  - plus a second skinned MeshPart of **fur cards or 2 to 3 shells** using `AlphaMode.Transparency` with `MeshPart.Transparency = 0` (hard-edged cutout, proper depth);
  - tail cards on the tail bones so the lag reads.

  Budget roughly 5 to 8k tris body and 3 to 6k cards per squirrel, at 1024² or less per map, times 10 to 14 squirrels. Test on mobile. (DevForum; medium)

### h. Rojo version, plugin and layout

- **Version.** Rojo **7.7.1** (2026-10-01) is current; 7.7.0 shipped 2026-07-01.
  - Since 7.7.0-rc.1 the server and plugin talk over **WebSockets** instead of long polling. **The Studio plugin must match the CLI.** Install it with `rojo plugin install` on the Mac after each CLI upgrade rather than trusting the Marketplace copy, which lagged during the RC.
  - `serve` now validates Host and Origin headers.
  - **`rojo syncback`** exists. It converts a place file back into project files and is configured by `syncbackRules`. Use it to capture Studio-imported meshes and SurfaceAppearances as `.rbxm` into git.

  (Rojo CHANGELOG via raw GitHub; high)
- **Layout.** Matches the brief, verified by build:

```
default.project.json
src/
  shared/   -> ReplicatedStorage.Shared   (Roles, Routes, Actors, Seasons, Infection rules, Town data, Moon)
  server/   -> ServerScriptService.Server (WorldGen bake, Traffic, Hospital, Police, Drone, Wildlife brains)
  client/   -> StarterPlayer.StarterPlayerScripts.Client (controllers, camera, sky/moon, ambient fauna)
assets/     -> *.rbxm / *.model.json (rigs with mesh IDs, KeyframeSequences, SurfaceAppearance packages)
tests/      -> Lune unit tests (pure modules) + Luau-Execution test runner modules
```

  Workspace properties confirmed settable from the project file include `StreamingEnabled`, `PlayerCharacterDestroyBehavior`, `ModelStreamingBehavior`, `StreamOutBehavior` and `AuthorityMode`. Rojo rejects properties on the wrong class at build time; for example, `CharacterAutoLoads` belongs on `Players`.

---

## What I can do from this container

- Write and refactor all Luau, organized one module per system under the Rojo layout. Build `.rbxl`/`.rbxlx` with Rojo 7.7.1 and generate `sourcemap.json`.
- Unit-test pure modules under Lune: Roles ladder, route sampling, infection maths, seasons and calendar, moon phase, combat timing windows, the swept-collision maths.
- Use Lune's `@lune/roblox` to:
  - inspect and modify built places;
  - assert on generated instance trees;
  - generate `.rbxm`/`.rbxmx`, including KeyframeSequences;
  - validate the town data file, its lots and its routes.
- Format with StyLua (`--features luau`) and lint with Selene (`std = "roblox"`, using a generated `roblox.yml`).
- Author Blender content headless with bpy 5.2.3:
  - procedural or base meshes, armatures, skinning, keyframed actions;
  - batch FBX exports with the Roblox settings (one clip per file plus a rig-only file);
  - glTF exports, re-import validation, and checks on triangle and influence counts.
  - Not possible: hand sculpting, look-dev or viewport judgment. Rendering previews may be possible with Cycles or EEVEE headless, but I didn't test that.
- Read the official Roblox docs from the `Roblox/creator-docs` GitHub repo, which stay current.

## What needs the user's Mac, Studio or Roblox account

- Roblox Studio itself: the Rojo plugin (`rojo plugin install`, matching 7.7.1) with `rojo serve` sync, playtests (multi-client Test), MicroProfiler and network simulator.
- The **3D Importer** for every mesh and rig. MeshParts get asset IDs only by uploading under the account or group.
- **Animation Editor import of each FBX clip** onto the rig, then **Publish to Roblox under the experience owner** (user or group). Alternatively, Open Cloud Animation upload of `.rbxm` from a machine that can reach `apis.roblox.com`.
- SurfaceAppearance setup and any union or WrapLayer work, then **publishing the place from Studio**, because the API publisher doesn't update these.
- Creating the experience and places, setting max players to 50, choosing the group, Team Create, and API keys if Open Cloud CI is wanted. Keys stay with the user.
- SLIM generation, which needs a saved and published place.
- Installing a Luau type checker (luau-lsp through Rokit) unless a source build is allowed here.
- Mobile and low-end device testing.

## Blockers

1. **No Luau type checker in the container.** None is on any registry; GitHub release downloads are blocked (403); and a source build of luau-lsp was denied by this session's permission policy. Lint and format work, but strict type checking doesn't.
2. **`apis.roblox.com`, `create.roblox.com` and `devforum.roblox.com` are blocked (403)**, and `download.blender.org` too. Open Cloud uploads, publishing and Luau Execution tests cannot run from here even with a key. Docs come only from the GitHub mirror.
3. **GitHub release assets are blocked** (`github.com/.../releases` returns 403). Tools must come from crates.io, npm or PyPI. `git clone` works.
4. **Selene's Roblox std generation ignores the proxy.** It needs the patched build or a committed `roblox.yml`; there is a workaround.
5. **Asset IDs need the account.** Every mesh, animation and texture ID must be created by the user or group before the place can show real art. Placeholder primitives and Studio-registered KeyframeSequences can stand in until then.
6. **Design tension (not a tool blocker).** Runtime WorldGen versus SLIM, which needs static saved geometry for the drone view. Resolve it by baking WorldGen at edit or build time from the data file.
7. **Animation ownership.** If the experience is group-owned, every animation must be published under that group. This is a known source of "Failed to load animation" errors.

## Recommended pipeline

1. **Repo (git, Rojo 7.7.1).** `default.project.json` maps `src/shared`, `src/server` and `src/client` as above. Add `assets/` for `.rbxm` rigs, KeyframeSequences and SurfaceAppearance packages captured with `rojo syncback`, and `data/town.lots.luau` as the single source of truth. Workspace properties go in the project: `StreamingEnabled`, `ModelStreamingBehavior=Improved`, `StreamOutBehavior=Opportunistic`, `PlayerCharacterDestroyBehavior=Disabled`, and `Players.CharacterAutoLoads=false`. Pin tools with `rokit.toml` on the Mac (rojo, lune, stylua, selene, luau-lsp).
2. **Code loop (container or Mac).**
   - Write Luau.
   - `stylua --check`, then `selene`, then `lune run tests` (pure modules), then `rojo build -o build/place.rbxl`.
   - On the Mac, add `luau-lsp analyze` using the sourcemap.
   - CI from a runner that can reach Open Cloud: save an *unpublished* place version through the Assets API, then run a Luau Execution task that requires the test modules (Roles, Infection, Seasons, WorldGen bake validation) and fails on any error.
3. **Art loop (Blender, then Studio).**
   - One `.blend` per species: squirrel, fox, deer, and human variants on R15.
   - Script exports: `X_rig.fbx` with no animation, plus one `X_<Clip>.fbx` per clip (Run, Climb, Wire, Leap, Pounce, BiteDance, Sneak).
   - Export settings: Unit System None, FBX Unit Scale, Z Forward, Y Up, Leaf Bones off, Bake Animation on, NLA and All Actions off, clip keyed from frame 0, scene named after the clip.
   - Respect the rules: under 20k tris per mesh, 4 influences per vertex, root at the origin with no weights.
   - In Studio, import the rig (Rig Type Custom), then Animation Editor > Import FBX clip, then Publish under the experience owner.
   - Studio-only iteration can use `AnimationClipProvider:RegisterAnimationClip` on git-tracked KeyframeSequences.
   - Run `rojo syncback` to pull the configured model (mesh IDs plus SurfaceAppearance) back into `assets/`.
4. **Runtime architecture.**
   - Humans: R15 Humanoid. Animals: AnimationController and Animator with a custom rail and kinematic controller.
   - One `Actors` module possesses bodies with `player.Character = body` and gives the player network ownership of the root. It releases bodies back to the AI.
   - AI brains tick at 4 to 10 Hz with distance LOD in a few parallel Actors, and far bodies stay anchored and are moved with `BulkMoveTo`.
   - Bodies use `ModelStreamingMode=Atomic`. Birds and insects are client-only.
   - Start with client-owned movement plus server validation. Evaluate Server Authority (beta) for the spicy-rodent duel once it is out of beta.
5. **World.**
   - Bake WorldGen from `town.lots` into the saved place through a Studio command or plugin. Re-bake whenever the data changes.
   - Set `LevelOfDetail=SLIM` on buildings and backdrop, and enable `EnableSLIMAvatars`, so the drone sees the whole town.
   - Sky: `ClockTime` cycle, `GeographicLatitude`, per-phase `MoonTextureId` swap with a custom billboard fallback, Atmosphere plus authored fog-layer cards.
6. **Publish** from Studio, which is required while SurfaceAppearance or unions exist. Open Cloud publishing can handle code-only updates later, if the user creates an API key.

### Sources

- Official Roblox docs, from GitHub `Roblox/creator-docs` @ `ccc2b01` (paths under `content/en-us/`):
  - `studio/importer.md`
  - `art/modeling/specifications.md`, `art/modeling/export-requirements.md`, `art/blender.md`, `art/modeling/surface-appearance.md`, `art/modeling/texture-specifications.md`
  - `avatar/character-bodies/export.md`, `avatar/emotes/import.md`
  - `animation/editor.md`, `animation/using.md`
  - `projects/assets/privacy.md`, `projects/server-authority/index.md`
  - `cloud/guides/usage-assets.md`, `cloud/guides/usage-place-publishing.md`, `reference/cloud/openapi.json`
  - `scripting/multithreading.md`, `scripting/security/network-ownership.md`
  - `workspace/streaming/index.md`, `workspace/streaming/slim.md`
  - `performance-optimization/improve.md`
  - `environment/{skybox,lighting,clouds,atmosphere}.md`
  - `reference/engine/classes/{Player,Players,Workspace,BasePart,Sky,Lighting,Model,SurfaceAppearance,KeyframeSequenceProvider,AnimationClipProvider,ControllerManager}.yaml`
- Rojo CHANGELOG: https://raw.githubusercontent.com/rojo-rbx/rojo/master/CHANGELOG.md
- DevForum (search snippets only; lower confidence):
  - [Unable to control character after setting player.Character](https://devforum.roblox.com/t/unable-to-control-character-after-setting-playercharacter/1411987)
  - [Animations not replicating after character set manually](https://devforum.roblox.com/t/animations-not-replicating-to-the-server-after-player-character-is-set-manually/421979)
  - [Why can my humanoid only play animations when I call SetNetworkOwner](https://devforum.roblox.com/t/why-can-my-humanoid-only-play-animations-when-i-call-setnetworkownerplayer/1689759)
  - [Humanoid Optimisation and 500 NPCs](https://devforum.roblox.com/t/humanoid-optimisation-and-500-npcs/312738)
  - [Humanoid or AnimationController for 100+ units](https://devforum.roblox.com/t/which-is-better-for-100-unit-games-humanoid-or-custom-meshes-with-animationcontroller/3774505)
  - [Moon Cycle System](https://devforum.roblox.com/t/moon-cycle-system-v11/1566416)
  - [Control over moon phase](https://devforum.roblox.com/t/control-over-moon-phase/126511)
  - [I can't change the texture of the moon](https://devforum.roblox.com/t/i-cant-change-the-texture-of-the-moon/1832271)
  - [How to import fur in Studio](https://devforum.roblox.com/t/how-to-import-fur-in-studio/2574354)
  - [Fur/Custom Shaders](https://devforum.roblox.com/t/furcustom-shaders/2784658)
  - [Group-made animations do not load for Team Create members](https://devforum.roblox.com/t/permissions-bug-group-made-animations-do-not-load-for-team-create-members-in-studio/1338224)
  - [Blender rigs import with -180 degree Motor6D transform](https://devforum.roblox.com/t/animations-from-blender-rigs-import-into-roblox-with-180-degree-motor6d-transform/4020911)
  - [Parallel Luau NPC approaches](https://devforum.roblox.com/t/parallel-luau-npc-approaches/1919849)
  - [Max limit of bones for custom characters](https://devforum.roblox.com/t/max-limit-of-bones-for-custom-characters/1290031)
  - [Rojo 7.7.0-rc.1 release notes](https://newreleases.io/project/github/rojo-rbx/rojo/release/v7.7.0-rc.1)
