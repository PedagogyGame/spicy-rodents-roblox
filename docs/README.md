# Spicy Rodents: planning docs

This branch holds the research and planning for the Roblox rebuild. It contains no game code yet.

- `reference/`: the source material.
  - The owner's brief: `Roblox_Rebuild_Brief.pdf`, plus a `.txt` copy.
  - The canonical v5.4 HTML game: `Spicy_Rodents_v5_4_Living_Town.html`, SHA-256 fc48b387…6227, verified against the brief.
  - Older versions v0.5, v4.1 and v5.2, for features lost after v4.1.
  - Pretty-printed `v5_4_game.js` and `v4_1_game.js`. All spec line numbers refer to these files.
  - A function index and a section map.
- `spec/`: a verified porting spec of v5.4, one document per subsystem. Each was fact-checked by a second agent; see the "Verification log" at the end of each file.
  - `BRIEF_ADDENDUM.md`: the owner's additions. These win over the brief.
  - `PROJECT_IDS.md`: the Roblox experience to use.
  - `roblox_feasibility.md`: toolchain and platform findings.
  - `data/*.json`: lots, roads, routes catalogue, traffic lanes, human cast and wildlife, all in HTML units. 1 unit = 2.5 studs.
  - `design/`: independent build proposals and the critique.
  - `BUILD_PLAN.md`: the merged plan, once written.
