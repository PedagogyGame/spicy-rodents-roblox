# HANDOFF — read this first in the next session

Owner: PedagogyGame (Ben). Project: Spicy Rodents Roblox rebuild. Written 2026-11-09 at the end of the first build session.

## Where things are
- **Branches:** `planning` (research + plan), `w0-foundation` (all code; includes planning docs). `main` is still the stock Rojo init. Merge `w0-foundation` into `main` once Wave 0 closes.
- **Plan:** `docs/spec/BUILD_PLAN.md` (revision 3 was being finalised by an agent when this session ended; `docs/spec/BRIEF_V2_DELTA.md`, `docs/spec/design/critique_rev3.md` and, if present, `docs/spec/PLAN_REV3_SUMMARY.md` are the inputs). Authoritative brief: `docs/reference/Roblox_Rebuild_Brief_v2.md` + `docs/spec/BRIEF_ADDENDUM.md` (A1-A3, B1-B4).
- **Roblox:** IDs in `docs/spec/PROJECT_IDS.md`. Key scopes verified: assets r/w, luau-execution r/w. universe-places write is refused; workaround B4: place stays at 50, Roles enforces 49. Test artefacts: CI place version 2, Decal 89657770904034.
- **Wave 0 status:** foundation DONE and checked (`docs/reports/w0_check.md`). S1 GO (`docs/spikes/S1.md`). S10 GO (GitHub Actions strict luau-lsp passes). S3 (rail motor + validator) largely done (tasks 7-10 complete), S4 in progress, S5/S9/S12 written (`docs/spikes/`). Pending: S2 possession, S6 bake/terrain, S7 headless animation, S8 models/runtime art, S11 drone far view, plus brief-v2 spikes (physics minigames, first-person vehicles, developer products + DataStore, garb on possessed body, street lighting cost, paintball hit-reg). Then Gate G0 with the owner.
- **Owner sessions still to schedule:** OS-1a (possession checklist in Studio), OS-1b (one test rig import into Art Inbox), OS-1c (drone test on a private server), OS-1d (read the spike report).

## How to resume (container is ephemeral)
1. `bash docs/ENVIRONMENT_SETUP.sh` (≈10 min cold; verified) — or create the dedicated cloud environment with it as the setup script (owner decision 4; the API key must then be re-entered via the secure form).
2. `bash tools/ci.sh` must be green. Cloud loop: `node tools/cloud/cloud.mjs universe`, `save_place build/test.rbxl --place ci`, `run_engine_tests tools/cloud/tasks/boot_smoke.luau --version <v> --place ci`.
3. Check `docs/spikes/*.md` verdicts, finish S4 if `docs/spikes/S4.md` is missing, then run the remaining spikes.

## Standing rules
- Never publish the main place without the owner's explicit go. Never touch the Art Inbox from the container except reads.
- Audio uploads: 40/month working budget, 50 max (B3). Mild rating; rewrite v5.4 swearing (brief v2 §15).
- Commit and push at every task boundary; the owner's website repo is never touched.
