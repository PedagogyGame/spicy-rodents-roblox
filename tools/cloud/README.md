# tools/cloud: Open Cloud tooling

Save place versions, run Luau Execution suites, upload assets and (one day) publish, from the
cloud container or any machine whose egress proxy injects the owner's API key for
`apis.roblox.com` (BUILD_PLAN §4.3 item 2, D15, §6.5). **No key is handled here.** Nothing in this
tree reads, stores or sends an `x-api-key` header; the proxy adds it. Outside the container the
calls fail with 401 by design.

## Why Node, not Lune

The plan preferred Lune's `@lune/net`. Measured 2026-11-09: Lune 0.11.1 ignores `HTTPS_PROXY`,
and since the proxy also does DNS the request dies with "failed to lookup address information".
Node 22.23's built-in `fetch` follows `HTTPS_PROXY` when `NODE_USE_ENV_PROXY=1` is set (the CLI
sets it on itself) and trusts the proxy CA through `NODE_EXTRA_CA_CERTS`, so the tooling is
dependency-free Node (no `npm install`). `curl` works too and was used to cross-check.

## Commands

```bash
node tools/cloud/cloud.mjs help
node tools/cloud/cloud.mjs universe [--places]            # universe + owner (creator for uploads); a 200 proves the key path
node tools/cloud/cloud.mjs save_place build/test.rbxl --place ci [--legacy] [--out build/save.json]
node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/boot_smoke.luau --version <v> [--place ci] [--out build/r.json]
node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/boot_smoke.luau --version 1 --inject ci.project.json
node tools/cloud/cloud.mjs upload_asset path/to.png --type Image --name "name" [--description ...]
node tools/cloud/cloud.mjs harvest_ids [--place art_inbox] [--run --version <v>]      # W0 stub
node tools/cloud/cloud.mjs publish build/owner.rbxl --place main --i-really-mean-it   # never in CI
node tools/cloud/cloud.mjs operation operations/<id> [--wait]
node tools/cloud/cloud.mjs status                          # token buckets + local task registry
node tools/cloud/cloud.mjs lock_test --hold-ms 2000        # offline lock check (run from two shells)
```

Exit codes: 0 pass, 1 failure (HTTP error, task FAILED, or the task's JSON has `ok == false`),
2 usage, 3 refused by a safety rule (main place without `--allow-main-place`, publish without
`--i-really-mean-it`, Art Inbox writes, the duplicate experience's IDs).

### Safety rules (hard-coded in `lib/config.mjs` and the commands)

- Default target is the **CI place** (118507593202954). The main place needs
  `--allow-main-place`; the Art Inbox is never written; universe 10775476357 / place
  71294450489810 (the duplicate experience) are refused everywhere.
- `save_place` always saves an **unpublished** version (`published: false` on the Assets API, or
  `versionType=Saved` with `--legacy`). Only `publish` can publish, and only with the flag.
- Every engine-test task is **pinned to a version** (`/versions/{v}`); `--version` is mandatory.

### Shared lock and token buckets

State lives in `${SPICY_CLOUD_STATE_DIR:-~/.cache/spicy-rodents/cloud}`:
`locks/cloud-write.lock` (a `mkdir` lock with the owner pid; stale after 15 min or a dead pid) is
held across a whole save, task create or upload, so two shells serialise (S-13).
`buckets.json` holds sliding windows: `luau_create` 5/min, `assets` 120/min (uploads and Assets-API
saves), `legacy_publish` 30/min, `reads` 240/min (polls). A full window makes the caller sleep,
with a message, instead of hitting 429. `tasks.json` remembers created tasks so the "10 incomplete
per place" rule can be honoured before a create (incomplete ones are refreshed first).

### Save-free engine tests (`--inject`)

Verified in S1: a Luau Execution task may `Instance.new("ModuleScript")`, set `Source` and
`require` it. `--inject <project.json>` prepends a bootstrap that rebuilds the project's code tree
(Folders, ModuleScripts, Scripts, LocalScripts from `$path` directories; content files such as
`.model.json`/`.rbxm` are skipped) inside the task's DataModel and applies `$properties` with pcall
(read-only ones such as `Players.MaxPlayers` are recorded under `InjectedPropertyFailures`), then
runs the task script. It marks `ServerStorage.EngineTests` with the attribute `Injected = true`
so suites can soften property checks. Script size counts against the 4 MB task limit (the W0
tree is 76 KB). This is the path to use until a real save works, and it stays useful for quick
loops because it needs no upload.

## Measured timings (2026-11-09, from the container; CI place version 1)

| Step | Result | Time |
|---|---|---|
| `universe` (GET universe, derive creator) | 200, owner `users/11958930616` | 0.85 s |
| `save_place` (Assets API PATCH, published=false) | **403 PERMISSION_DENIED "User not authenticated"** | 0.25 s to the refusal |
| `save_place --legacy` (universes/v1, versionType=Saved) | **403 "Scope not authorized."** | 0.2 s |
| GET `assets/v1/assets/{placeId}` (read) on all three places | 403 "User not authenticated" | 0.3 s |
| `run_engine_tests tasks/ping.luau --version 1` | COMPLETE, JSON returned, 1 log line | create 0.43 s, done 2.8 s, total 3.1 s |
| two shells, `ping` at once | both PASS; 2nd waited 1.13 s for the write lock; bucket 2/5 | 3.5 s and 4.8 s |
| `lock_test` from two shells (hold 2000 ms / 500 ms) | B acquired 1810 ms after requesting, right after A released | n/a |
| inject experiment (set `Source`, require) | `canSetSource=true canRequire=true answer=42` | 3.3 s |
| `run_engine_tests tasks/boot_smoke.luau --version 1 --inject ci.project.json` (76 KB script, 174 instances) | COMPLETE: 112 ModuleScripts required, 0 failures, string requires OK | create 0.9-2.3 s, total 3.5-3.6 s |

Scriptable from a task: `Workspace.StreamingEnabled`, `StreamOutBehavior`, `Players.CharacterAutoLoads`,
`Players.MaxPlayers` (read-only). Not readable from any script: `ModelStreamingBehavior`,
`PlayerCharacterDestroyBehavior`, `SignalBehavior`, `Lighting.Technology`; the Lune place test
(`tests/place/check_place.luau`) is authoritative for those.

## Blocked: the key cannot save place versions (owner action)

Reads on `cloud/v2` (universe, places, users) and Luau Execution work, so the key reaches Roblox
through the proxy. But every Assets API call, reads included, returns 403 "User not authenticated",
and the legacy publish endpoint returns "Scope not authorized". So the key currently lacks:

1. **assets** (Read and Write) on the experience "Spicy Rodent" (Creator Hub -> Open Cloud ->
   API Keys -> the key -> Access Permissions -> Assets -> add the experience with Read + Write).
   This also unblocks `upload_asset` (Image/Model/Animation), which could not be tested.
2. **universe-places:write** (legacy "Universe Places" write) if the `--legacy` route is wanted.

PROJECT_IDS.md lists both as granted; the live key says otherwise (perhaps granted on the duplicate
"Spicy Rodents" experience). After the owner fixes it, re-run:

```bash
rojo build ci.project.json -o build/test.rbxl
node tools/cloud/cloud.mjs save_place build/test.rbxl --place ci --out build/save.json
node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/boot_smoke.luau --version "$(jq -r .versionNumber build/save.json)" --out build/bootsmoke.json
```

Expected per the plan: save + task in well under 2 minutes (the task alone is ~3.5 s).

## Files

- `cloud.mjs`: entry; re-executes with `NODE_USE_ENV_PROXY=1`; dispatches `commands/*.mjs`.
- `lib/config.mjs`: IDs, forbidden IDs, buckets, state dir. `lib/lock.mjs`: lock, buckets, task
  registry, logs. `lib/http.mjs`: fetch with retries (429/5xx), multipart helper, error hints.
  `lib/openCloud.mjs`: the API calls. `lib/inject.mjs`: project tree -> task bootstrap.
- `tasks/*.luau`: task scripts (`ping.luau`, `boot_smoke.luau`); formatted and linted with the rest.
- Logs of every save/task/upload append to `saves.log`, `tasks.log`, `assets.log` in the state dir.
