# HANDOFF — read this first in any new session

Owner: PedagogyGame (Ben). Project: Spicy Rodents Roblox rebuild. Last updated 2026-11-09.

## 1. Where things are
- **Branches.**
  - `w0-foundation` holds all code and docs. Work continues here.
  - `planning` is a research snapshot.
  - `main` is still the stock Rojo init. Merge `w0-foundation` at Gate G0.
- **Authority order.** `docs/reference/Roblox_Rebuild_Brief_v2.md` (owner's live doc, rev 28), then `docs/spec/BRIEF_ADDENDUM.md` (A1-A3, B1-B4), then `docs/spec/BUILD_PLAN.md` revision 3 (when the critique fixes have been applied the header says so), then the v5.4 subsystem specs in `docs/spec/*.md`.
- **Plan inputs.**
  - `docs/spec/BRIEF_V2_DELTA.md`: 229 items and 22 conflicts (C1-C22).
  - `docs/spec/design/critique_rev3.md`: 290 requirements (268 covered / 20 partial / 2 missing), 10 sequencing and 12 feasibility findings.
- **Roblox.**
  - IDs are in `docs/spec/PROJECT_IDS.md`.
  - The key can read and write assets (save place versions, upload) and run Luau Execution.
  - It cannot write universe-places. Workaround B4: the place stays at 50 and Roles kicks the 50th player.
  - Test artefacts: CI place versions 2-3 and Decal 89657770904034.

## 2. Wave 0 status (spike reports in `docs/spikes/`)
| Spike | Verdict | Key numbers / carry-forward |
|---|---|---|
| S1 cloud loop | GO | save to CI ~3 s; Luau Execution ~3 s; script cap **1 MiB** (not 4 MB); `--inject --inject-exclude generated` for code-only suites |
| S3 rail motor + validator | GO | 1,332 routes exact; 0 honest violations / 105k packets; 100 % cheat detection; 0.007 ms per squirrel per tick |
| S4 fatal traffic | GO | 10,126/10,126 golden; engine 0.30 ms/tick for 15×50; Lune JSON is not ulp-exact → `tests/lib/PreciseJson` |
| S5 AI scale | GO | 0.12 ms/frame for the full worst case (budget 4 ms); body mode = anchored root + Motor6D limbs, BulkMoveTo roots only |
| S9 avatar APIs | GO | descriptions 16/16; classic face via LoadAsset decal; dynamic heads need a stock-expression map; product-name colour words only 42 % → curated `item_colours.json` |
| S10 type check | GO | GitHub Actions strict luau-lsp green |
| S12 renders | GO | Cycles CPU 64 spp + denoise: 13.5 s/frame at 512 px on 2 threads (~8 min per turntable) |
| S2, S6, S7, S8, S11, S13-S20 | open | see BUILD_PLAN §4.3 (rev 3 adds S13-S20 for brief v2) |

## 3. Engineering rules learned (apply everywhere)
1. **Requires.** Within a root use relative string requires ("./X", "../Y"). Across roots (server/client/worldgen → shared) use the root's `Import.luau`:
   `local Swept = Import.shared("Traffic/Swept") :: typeof(require("../../shared/Traffic/Swept"))`
   Value from the engine or Lune, type from disk. Verified: all 138 modules require in the engine (BootSmoke, CI v3).
2. **Golden tests that need bit-exactness** decode with `tests/lib/PreciseJson.luau`.
3. **Routes.** Take `sampleCount` from the harvest record; never recompute ceil(3L).
4. **AI bodies.** One anchored root plus Motor6D limbs, moved with `workspace:BulkMoveTo` on roots only. All-parts anchoring costs about 1.4 ms per 130 rigs.
5. **Engine checks.** `Players.MaxPlayers` in the file is overridden live by the place's serverSize. Several streaming/lighting properties are NotScriptable and are verified by the Lune place test, not in the engine.
6. **Audio.** There is no runtime synthesis in Roblox. Use library sounds plus Audio API effects; budget 40/50 uploads per month (B3). Keep the tally in `docs/AUDIO_BUDGET.md`.
7. **Luau Execution** runs no physics, has no players and auto-runs no scripts. Physics feel, camera and fps checks need the owner's Studio (critique SQ-1, FE-1).
8. **Commit and push at every task boundary.** The container is ephemeral.

## 4. Next steps, in order
1. If `BUILD_PLAN.md`'s header does not yet say the rev-3 critique was applied, apply `critique_rev3.md`. Its gaps include B3/B4 absent from the plan, floor arithmetic, regen vs drain, queue weights, ProcessReceipt NotProcessedYet, no runtime audio synthesis, and the already-created CI and Art Inbox places.
2. Run the remaining spikes. Headless first: S6 bake/terrain, S7 headless animation upload, S8 model upload/runtime art, S15 receipts+DataStore logic, S18 paintball hit-reg, S19 body budget. Then those needing the owner: S2 possession (OS-1a), S11 drone far view (OS-1c), S13/S14/S16/S17.
3. Write the one-page G0 spike report for the owner. Merge to `main` on go.
4. Wave 1 per BUILD_PLAN §4.4.

## 5. How to resume (ephemeral container)
1. `bash docs/ENVIRONMENT_SETUP.sh` (~10 min cold, verified), then `bash tools/ci.sh` must be green.
2. Cloud loop:
   - `node tools/cloud/cloud.mjs universe`
   - `node tools/cloud/cloud.mjs save_place build/test.rbxl --place ci`
   - `node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/boot_smoke.luau --version <v> --place ci`
3. Reference material outside the repo (`/home/user/spicy-rodents/`) is mirrored in `docs/spec` and `docs/reference`. Agents' prompts may name the outside paths: copy `docs/` back there, or point them at `docs/`.

## 6. Standing rules
- Never publish the main place without the owner's explicit go. Only read the Art Inbox from the container.
- Mild rating: rewrite v5.4 swearing (brief v2 §15). No gambling: the fortune machine takes no money.
- Never touch the owner's website repo.
