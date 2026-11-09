# Gate G0: Wave 0 results on one page

For Ben, 9 November 2026. Wave 0's job was to try every risky piece before the main build is stacked on top of it. Details are in `docs/spikes/Sn.md`.

## Passed: 15 tests, no fallback needed

| What we tested | Result |
|---|---|
| Saving builds to your CI place and testing them inside Roblox (S1) | about 3 s each way |
| Squirrel climbing on all 1,332 v5.4 routes, plus anti-cheat (S3) | exact copy of v5.4; cheats caught 100 %, honest players never flagged |
| Cars running squirrels over exactly as v5.4 did (S4) | 10,126 / 10,126 test cases; 0.30 ms per server tick |
| Server load with a full town (S5, and S19 at your new numbers) | 109 bodies + 45 cars cost about 0.5 ms of a 16 ms frame (≈3 %) |
| Whole town built from the data file, plus terrain (S6) | 243 lots and 116 roads in 0.2 s; terrain in about 1 s (7 s with hills) |
| Animations from Blender into Roblox, no Studio needed (S7) | plays with every joint named correctly |
| Reading players' avatars for the 70/30 blend (S9) | works for every avatar tried |
| Type checking on GitHub (S10) | green |
| Blender turntable pictures with no screen (S12) | about 8 minutes per turntable |
| Robux purchases never lost or double-charged; money saved safely (S15, headless part) | 2,000 test purchases with injected crashes: every one credited exactly once |
| Paintball hit detection with lag (S18) | 99.8 % accurate at 150 ms lag; under 0.2 ms per frame |
| Taking over a moving body and giving it back (S2, headless part) | 1,008 take-overs and releases: 0 errors, 0 lost bodies; the 50th arrival politely turned away |

## Needs your eyes: one Studio session, about 42 minutes (`docs/owner/OS-1.md`)

- **A. Possession feel (20 min):** does a walking person or running squirrel feel smooth when you take it over? Plus the squirrel's legs swinging the right way.
- **B. One test import (12 min):** confirms Blender textures and fur colouring survive in Roblox.
- **C. Drone flight (10 min):** is the whole town visible from 300 studs up? **Needs your OK first** for me to publish a throwaway test town to your private Spicy Rodent place. Nobody else can see it.

## Still to test later, in the waves that need them

S13 physics minigames, S14 first person in vehicles, S16 paintball garb on a body, S17 300 street lamps. These need Studio or a live server. The plan runs them when their features are built.

## Decisions needed

1. **Go for Wave 1?** Nothing in Wave 0 failed, and every engine-side number came in far under budget. My recommendation is yes. Session OS-1 can happen while Wave 1 runs. If A shows a problem, the fallback is already designed and only touches the possession module.
2. **OK to publish the drone test town to the private main place?** It's needed for C.
3. **Optional key tweaks (2 min, no rush):**
   - **Asset-delivery read** lets me pull Studio imports back into GitHub automatically.
   - **DataStore read** lets automated tests check saved money.
