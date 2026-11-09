# W0 independent check (2026-11-09)

Checker: an independent W0 agent, after builders F1 (toolchain, CI, cloud) and F2 (harvest, golden,
compile) finished. Everything below was re-run from a clean shell (`env -i`, `PATH` = cargo bin +
system) in `/home/user/spicy-rodents-roblox` on branch `w0-foundation`, against the plan
(`spec/BUILD_PLAN.md` §1, §3, §4.3, §6) and the specs in `spec/data/*.json`. Nothing was committed;
nothing was published; only the CI place (118507593202954) was touched.

## 1. Verdict in one screen

| Area | Result | Evidence |
|---|---|---|
| `tools/ci.sh` (stylua, selene, Lune tests, compile check, 3 rojo builds, 4 place tests, sourcemap) | **PASS**, 1.6 s | 24/24 unit cases; place tests 391/391/395/391 checks, 0 failures; `generated/` up to date |
| Rojo tree and project properties (§1.2) | **PASS** | all three project files map the plan's roots; every `$properties` value asserted by `tests/place/check_place.luau` on the built `.rbxl`/`.rbxlx`; EngineTests only in `ci.project.json` |
| Skeleton (110 stubs + 3 real pure modules) | **PASS** | every module `--!strict`, headed, requires under Lune and in the real engine (112 ModuleScripts incl. the 2 engine-test modules) |
| `tools/harvest` (pinned v5.4 HTML) | **PASS**, 68 s, byte-identical | SHA-256 verified; fresh run to a scratch dir reproduces all 14 data files byte for byte; only `manifest.json` timestamps/run logs differ |
| `tools/golden` | **PASS**, 0.7 s, byte-identical | 17 verbatim blocks re-verified against `v5_4_game.js`; 10 vector files identical to the committed ones |
| `tools/compile` | **PASS**, 0.9 s | `check`: 12 generated files not stale; `migrate --check`: 22 authored files equal a fresh migration; 5,861 invariants, 0 failures |
| Open Cloud read + Luau Execution | **PASS** (engine half) | `universe` 200 (owner `users/11958930616`); BootSmoke task on CI place v1 (inject mode): COMPLETE, 112 modules required, 0 failures, string requires OK, 3.3 s |
| Open Cloud place save | **BLOCKED by the key** | `save_place build/test.rbxl --place ci`: 403 `PERMISSION_DENIED "User not authenticated"`; `curl` GET `assets/v1/assets/<ci>` gives the same 403 while `cloud/v2` reads are 200. Owner step OS-0b (Assets Read + Write on "Spicy Rodent") still open |
| Secrets / hygiene | **CLEAN** | no `x-api-key` values, tokens or key-like strings in the tree; `.gitignore` covers `build/`, `*.rbxl(x)`, `sourcemap.json`, `node_modules/`, cloud state; no tool writes outside the repo |
| GitHub Actions `ci.yml` | **not executable here**; reviewed | YAML parses; release asset names verified for rojo, lune, stylua, luau-lsp via each repo's release workflow at the pinned tag; selene's could not be verified (cargo fallback present) |

Two things the checker fixed directly (§5) and a short list for the lead (§6).

## 2. Counts verified against the specs

Independent recount (Python over `spec/data/*.json` and `data/harvest/*.json`), not the builders' reports:

| What | Spec / plan | Harvest or compile | Checker recount |
|---|---|---|---|
| Routes | 1,332 (§4.3 exit) | 1,332 | 1,332 (`routes.json`), ids 0..1331 |
| Spatial-index samples | 81,613 (§4.3 exit) | 81,613 | 81,613 (sum of `sampleCount`; `route_samples.json` points); `max(20, ceil(3L)) + 1` holds for all 1,332 |
| Fork trunks | 95 | 95 | 95 (`forks.json` trunks) |
| Trees (incl. apple) | 95 | 95 | 95 (`trees.json`; `wildlife.json v54.trees.list` 95) |
| Nests / apple trees | 24 / 12 | 24 / 12 | 24 / 12 (both files; wildlife spec 24 / 12) |
| Utility supports | 110 | 110 | 110 (97 residential + 6 estate + 7 westside) |
| Route kinds | 8 | 8 | roof 99, trunk 265, bridge 78, fence 12, trampoline 1, wire 150, branch 715, lookout 12 |
| Largest island / islands | 563 / 149 (§3.13 inv. 7) | 563 / 149 | from the harvest `graph.json` (derived by the tool) |
| Lots | 243 (§3.1) | 243 in 11 districts | 90 (`lots_core.json`) + 153 (`lots_districts.json`) = 243 |
| Roads / lanes / cast | 116 / 25 / 87 | 116 / 25 / 87 | 116 / 25 / 87 |
| Route catalogue | 60 generators summing to 1,332 | 60 / 1,332 | 60 rows; `count_estimate` sum 1,332; per-line counts equal the harvest call sites (60/60) |
| Nut caches / deer / insects / hollow proposals | 10 / 5 / 30 / 11 | same | 10 / 5 / 30 / 2 premium + 9 knothole = 11 |
| Reference HTML SHA-256 | `fc48b387...7227` | pinned in `manifest.json`, `Index.luau`, route chunks | `sha256sum` agrees |
| Unit conversion | x 2.5 (§3.1) | | `galleria_building` x 1102 u -> 2755 st, footprint w 78 -> 195; shortest-decimal rule holds |

## 3. What was run, exactly

```bash
# gate (1.6 s)
env -i HOME=/root PATH=/root/.cargo/bin:/usr/bin:/bin bash tools/ci.sh
# harvest to a scratch dir, then byte-compare with data/harvest (68 s)
node tools/harvest/src/harvest.js --out <scratch>/harvest_out --report <scratch>/harvest_report.md --cache <scratch>/harvest_cache
# golden to a scratch dir, then byte-compare with tests/golden (0.7 s; node_modules already present)
node tools/golden/src/golden.js --out <scratch>/golden_out --report <scratch>/golden_report.md
# compiler
lune run tools/compile/main.luau check            # 0.9 s
lune run tools/compile/main.luau migrate --check  # 22 files match
# cloud loop, once, CI place only
node tools/cloud/cloud.mjs universe                                   # 200
node tools/cloud/cloud.mjs save_place build/test.rbxl --place ci      # 403 (key)
node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/boot_smoke.luau \
     --version 1 --inject ci.project.json --inject-exclude generated  # COMPLETE, PASS
```

Other checks: `stylua --check` and `selene` on `tools/compile` and `generated/` (clean); `git status
--ignored` (only `build/`, `sourcemap.json`, `tools/golden/node_modules/`, `tools/harvest/.cache/`
ignored); grep for key-like strings (only SHA-256 block hashes and Roblox enum names matched); a
search of every tool for writes into `/home/user/spicy-rodents` (none: harvest writes to `--out`
and `--cache`, golden to `--out`, compile to `data/authored`, `generated/`, `build/`).

## 4. Findings in detail

### 4.1 Toolchain, CI, skeleton (F1)

- The Rojo tree matches §1.2 (`src/shared` -> `ReplicatedStorage.Shared` with optional
  `Generated`, `src/server` -> `ServerScriptService.Server` + `WorldGen`, `src/client` ->
  `StarterPlayerScripts.Client`, `assets/` -> `ReplicatedStorage.Assets`, `tests/engine` ->
  `ServerStorage.EngineTests` only in `ci.project.json`, optional `build/Town.rbxm` in build and ci).
  Project properties are exactly the §1.2 table (plus `SoundService.RespectFilteringEnabled`).
- The place test walks the project JSON against the built file (classes, every `$properties`
  value incl. enums by name, every file -> instance, no SurfaceAppearance/PartOperation/BaseWrap,
  EngineTests presence). It now also covers the 12 `generated/` modules (391 checks, up from the
  366 F1 reported before `generated/` landed).
- Lune harness: discovery under `tests/` and `src/`, filter words, non-zero exit; the assertion lib
  is small and typed. 24 cases pass. The skeleton spec requires every module under Lune.
- Real modules: `Config/Units` (2.5 st/u, one `+pi`), `Time/Moon` (phase maths), `Time/Calendar`
  (string `require("./Moon")`, winter week 6 of 6). Everything else is a headed stub with
  `__skeleton = true`; W0 deliverable 5 (Types, RigSpec, Net/Schemas, Tunables tree, Ladder with
  tests) is a separate task and not claimed by F1.
- Toolchain config is as the plan says: `rokit.toml` pins, `stylua.toml` Luau syntax, `selene.toml`
  with a committed 775 KB `roblox.yml`, `.luaurc` strict with aliases, `.gitattributes` LFS rules
  for blend/fbx/glb/gltf and source PNGs. `docs/ENVIRONMENT_SETUP.sh` is idempotent and contains no
  secrets.
- `.github/workflows/ci.yml`: parses; mirrors `tools/ci.sh` then runs strict `luau-lsp analyze`
  with `globalTypes.d.luau` from the 1.70.1 tag. Asset names checked against the pinned tags'
  release workflows: `rojo-7.7.1-linux-x86_64.zip`, `lune-0.11.1-linux-x86_64.zip`,
  `stylua-linux-x86_64.zip`, `luau-lsp-linux-x86_64.zip` are right. Selene's release workflow is
  not at `.github/workflows/release.yml` on tag 0.31.0 (its `build.yml` only uploads CI artifacts
  named `selene-linux`), so `selene-0.31.0-linux.zip` is unverified; the step falls back to
  `cargo install`, which costs minutes but works. S10 (0 strict errors) is unproven until the
  branch is pushed.

### 4.2 Open Cloud (F1)

- Safety rules hold in code: CI place is the default and the only default write target; `main`
  needs `--allow-main-place`; the Art Inbox is never written; the duplicate experience's IDs are
  refused everywhere; `save_place` cannot publish; every task is pinned to `--version`; no code
  path reads or sets `x-api-key`. The on-disk lock and token buckets live under
  `~/.cache/spicy-rodents/cloud` (gitignored paths; nothing in the repo).
- The save is blocked by the key, confirmed independently with `curl` (reads on `assets/v1`
  also 403; `cloud/v2` reads 200). This is the owner's OS-0b step, as F1 wrote.
- **New fact found by this check:** the Luau Execution **script** cap is **1 MiB**, not the 4 MB the
  plan (§6.5) and the feasibility doc state. With `generated/` in the tree the inject bootstrap grew
  from 76 KB to 1.47 MB and the API refused it (`400 INVALID_ARGUMENT "Script too large: was 1502344
  bytes, limit is 1048576 bytes"`). Fixed in the tool (§5). Consequence: inject mode cannot carry the
  compiled data, so `DataIntegrity`, `WorldBuild` and the sim suites need real saved versions, which
  makes OS-0b more urgent than "optional".

### 4.3 Harvest, golden, compile (F2)

- Harvest: deterministic (canonical hash `b0db2d6f2efb037b` on all three runs, html and pretty
  variants), pinned, refuses other hashes, blocks every external request; the instrumented copy
  lives in the tool's `.cache/`, never in `reference/`. All 44 count comparisons match, the 60
  call sites match the catalogue, the derived graph reproduces 149 islands / 563 largest / 40
  singletons / 0 branch-tip links. Chili peppers are correctly flagged non-deterministic.
- Golden: `original.js` is generated from cited line ranges and re-verified by SHA-256 at run
  time; vectors are seeded with the game's own `rng`. One detail for the Luau port: the npm
  three@0.160.1 cross-check reports **2 sample-count mismatches** against the harvest (ceil(3L)
  at an integer boundary flips on a 1e-14 length difference). The Luau `Registry` should take
  `sampleCount` from the harvest record, not recompute it.
- Compile: schema validation (draft-07 subset), unique ids, cross-references, counts, stud
  conversion on the shortest decimal, StyLua over the output, Lune require of every module with
  timings (largest chunk 12.6 ms). Warnings worth carrying into W1: 8 lanes reference no road id
  (yard glides, verges, templated routes); duplicate cast names `Avery` and `Sam` (ids
  disambiguated). Invariant 1 (paramSchema) and route-to-lot assignment are W1 by design.
- Layout deviations, both declared by F2 and both harmless today: authored data is under
  `data/authored/{town,cast,routes,wildlife}` where §1.2 says `data/town`, `data/cast`,
  `data/wildlife`; golden vectors are in `tests/golden/` where §6.3 says `tests/golden/`. Decide
  once (move, or amend §1.2/§6.3); the only references are `tools/compile/main.luau`, the
  `$schema` links and `tools/golden` defaults.

### 4.4 Paths, hygiene, environment

- Every builder file is inside the repo; the committed-candidate set is the one in the two
  reports plus `docs/reports/*.md`. `README.md` and `CHANGELOG.md` at the root were in F1's list.
- Ignored artefacts present and correctly ignored: `build/`, `sourcemap.json`,
  `tools/golden/node_modules/` (33 MB), `tools/harvest/.cache/` (2.9 MB).
- Four files under `/home/user/spicy-rodents` changed during the build window
  (`spec/BUILD_PLAN.md` 06:32, `spec/BRIEF_ADDENDUM.md` 06:32, `spec/BRIEF_V2_DELTA.md` 06:09,
  `reference/Roblox_Rebuild_Brief_v2.md` 05:41). No builder tool writes there and the timing
  matches the lead's own "BUILD_PLAN rev 3" work; flagged only so the lead can confirm.
- Caches stayed under `/root/.cache` (npm 10 MB, cloud state 24 KB). Disk use of the repo: 68 MB
  including `.git` and `node_modules`; committed JSON data is 6.6 MB (harvest) + 11 MB (golden).

## 5. Fixes applied by the checker

1. **`tools/cloud/lib/inject.mjs`, `tools/cloud/commands/run_engine_tests.mjs`:** new
   `--inject-exclude <dir,...>` (project-relative `$path` directories left out of the injected
   tree, reported under `injected.excluded`), and the size guard lowered from 4 MB to the real
   1 MiB with a message that names the flag. Re-tested live: the BootSmoke task completed (174
   instances, 76 KB, 112 modules, `placeVersion = 1`).
2. **`tools/ci.sh`:** added the plan's missing "compile check" step
   (`lune run tools/compile/main.luau check`, 0.9 s) after the unit tests, so a stale `generated/`
   fails the gate; `tools/compile` added to the stylua/selene directories (it was already clean);
   `mkdir -p build` moved before the check (it writes `build/compile-check/`). Both `tools/ci.sh`
   and `tools/ci.sh --no-build` pass.
3. Docs: `tools/cloud/README.md` (1 MiB limit, the flag, two measured rows), `docs/spikes/S1.md`
   (checker re-run and the limit correction), `README.md` (everyday commands mention the compile
   step and `compile`).

## 6. For the lead

1. **Owner action OS-0b** (Assets Read + Write for "Spicy Rodent", optionally Universe Places
   Write): blocks `save_place`, `upload_asset`, `publish`, hence S1's save half, S7, S8a/f, S11,
   and every data-dependent engine suite (inject mode cannot carry `generated/`). First CI version
   for `CHANGELOG.md` waits on it.
2. **Correct the limits text:** BUILD_PLAN §6.5 and roblox_feasibility B.d say "script up to
   4 MB"; the live API caps the script at 1 MiB (4 MB is the return value). Already corrected in
   the tool docs and S1.
3. **Decide the data layout** (`data/authored/*` vs §1.2; `tests/golden/` vs `tests/golden/`)
   before W1 code starts depending on the paths.
4. `Players.MaxPlayers = 49` is in the place file but the live cap is the place's `serverSize`
   (50 on all three places): set it in Creator Hub or via `PATCH cloud/v2 .../places/{p}` (F1's note;
   confirmed by the place read: `"serverSize": 50`).
5. Push the branch once to prove S10 (`luau-lsp analyze` strict) and the selene download name;
   if `selene-0.31.0-linux.zip` is wrong the cargo fallback still passes, only slower.
6. Carry forward: the 2 golden sample-count edge cases (use harvest `sampleCount`), the 8 road-less
   lanes and the duplicate cast names, and consider LFS for `data/harvest/*.json` and
   `tests/golden/*.json` if repo size matters (17 MB today).
7. Not part of these two builds, still open in W0: deliverable 5 (contracts: Types, RigSpec,
   Net/Schemas, Tunables tree, Ladder with per-row tests) and spikes S2-S12.
