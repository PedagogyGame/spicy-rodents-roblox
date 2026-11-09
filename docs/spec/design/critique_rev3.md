# Adversarial review of `spec/BUILD_PLAN.md` revision 3 (brief v2 absorbed)

Date: 2026-11-09. Reviewer lens: requirement coverage against brief v2, sequencing, feasibility against `spec/roblox_feasibility.md` and Roblox platform behaviour, contradictions inside the plan, and v5.4 behaviour the plan drops without saying so.

**Inputs read in full.** `reference/Roblox_Rebuild_Brief_v2.md` (authoritative), `spec/BRIEF_ADDENDUM.md` (A1-A3, B1-B3), `spec/BRIEF_V2_DELTA.md`, `spec/BUILD_PLAN.md` revision 3 (every section, including the 536-row traceability tables in §10), `spec/roblox_feasibility.md`, `spec/PROJECT_IDS.md` (as updated today). Consulted where a v5.4 number or behaviour had to be checked: `squirrel_abilities_progression.md` (§5 stalk, §12 Power, §14 currencies, §19 idle predator, §20 end conditions), `wildlife_foraging.md` (§6, §11, §14), `humans_actors.md` (§3, §4.5, §5.5-5.6, §11), `hospital_police_infection.md` (§5.5, §6, §7.5), `traffic.md` (§2, §6), `worldgen_districts_art.md` (§14.2, verifier notes), `routes_movement.md` (§15), `reference/v5_4_function_index.txt`, and the previous review `spec/design/critique.md` for ID continuity. Nothing in `reference/` was modified.

**Citation style.** "Plan §n" = a section of `BUILD_PLAN.md`; "Dn" = its key decision; "Sn" = its W0 spike; "OS-n" = owner session; "dec n" = owner decision (plan §8), "item n" = open item 37-44 there; "inv n" = compiler invariant (plan §3.13); "W n #k" = wave item; "FRB Xn" = an acceptance check in plan §4.7; "V2-n" = a row of the delta's inventory; "brief §n" = brief v2.

**Status key for the inventory.** COVERED = built in a named wave with a named check (a declared deviation that brief v2 §15 accepted by default also counts as COVERED, with the deviation named). PARTIAL = present but incomplete, built on a default that contradicts the brief's text, contradicted elsewhere in the plan, or a platform LIMIT the plan can only approximate. MISSING = not in the plan.

## Verdict in one screen

Revision 3 is thorough: all 229 delta rows have a plan home, the frameworks-before-content rule (rule 13, D28) is the right shape for a scope that doubled, and the FRB is still role-complete (every one of the eight roles has a Lab entry and a thinnest loop in §4.7). The problems below are the ones that would bite before or at G0:

1. **The population arithmetic does not close (CT-1).** §1.5's floor totals (26/37 normal, 22/33 at the hard cap) do not equal the sum of their own rows (the shop floor and the guard-and-crew bodies are left out; the attraction row says 5 but the total uses 11). With the rows' own floors, the hard cap of 90 serves 90 − 44 = **46** human players, not the 57 the text claims, so invariant 11 ("hard cap − hard-cap floors ≥ 49") fails on the plan's own numbers and the brief's "staffed regardless of player count" cannot hold at a 49-player fill without cutting street, shop and attraction floors. FRB check M9 ("the shops still show workers" at 49) is unsatisfiable with the FRB's 69 + 8 bodies.
2. **The rodent health model contradicts itself (CT-2).** D33 claims the regen was "re-tuned so the drain and the heals are the main recovery paths", but `regenStalk = 0.25 hp/s` is 18 hp per 72-second in-game day against a drain of 1 hp per day, and `regenHollow = 1 hp/s` is 72 hp per day. The brief's drain can never matter.
3. **Physics spikes and physics suites have no place to run (SQ-1, FE-1).** Luau Execution runs no physics [feas B.d], the container has no Studio, and OS-1a-c (40 minutes) list none of S13 (pool, pinball, Jenga feel and stability), S14 (judder on the owner's Mac), S15 (a Studio test purchase) or S17 (fps on the Mac and a phone). The `Minigames` suite's "no part leaves its table in 10 simulated minutes; Jenga stands 60 s" is listed as a Luau Execution task and cannot be one.
4. **Physics replay and determinism are assumed where Roblox does not provide them (FE-2, FE-3).** "A replayed pool shot lands within 0.1 st" and "the server replay agrees with the shooter's reported outcome" presume deterministic rigid-body physics across machines; Roblox's solver is not deterministic for chaotic contacts (a break, a pin scatter). Per-turn ownership of the ball with server-owned pins also splits one collision across two simulators.
5. **The paintball venue is decided at G0 on headless numbers (SQ-4).** S18 measures stub players and custom projectile code; it cannot measure 16 unanchored Humanoids replicating at 60 Hz. The first real measurement is W7 #2, and the fallback (a separate place through TeleportService) is the one change that breaks the actor model at both ends.
6. **The FRB rodent check is stale and there is no AFK rule (CT-3, VD-1).** FRB R2 still reads "hold the right mouse button -> first-person stalk" while §14, `CameraRig` and item 39 default to an over-shoulder third-person stalk. v5.4's idle-predator game over (its only AFK mechanic) is dropped without a row, and nothing releases an idle player's body to the AI, so an AFK player can hold the rodent slot, "the role everyone wants", indefinitely.
7. **Owner time is understated and bunched (SQ-3, CT-7).** §0 says "5 minutes on the website" for Step 0 where its own table says 17; the §0 table omits the four G2 approvals (40 min) and OS-5c's extra 20 min that §4.14 and §6.6 count; W0's physics and lighting spikes need another 40-60 minutes of Studio; OS-5 (60 min) is asked to cover the FRB regression set plus about fourteen new systems, when the FRB alone was 60-90 minutes; and about 3.8 of the 10.5 hours land in the W4-W4b window.
8. **Two owner documents are not honoured (RQ-1, CT-9, CT-8).** Addendum B3's audio budget (40 uploads a month, 50 if needed, a running `docs/AUDIO_BUDGET.md` tally) is absent; D24 and risk 20 still cite 100 and "at most 10". Decision 27's accepted default (no cross-server saving) is reversed by D26 without a §2.1 deviation row. OS-0 still schedules creating the CI and Art Inbox places that `PROJECT_IDS.md` shows already exist and verified.

**Inventory counts** (section 1 below): **290 requirements; 268 COVERED, 20 PARTIAL, 2 MISSING.** The two MISSING items are Addendum B3 (the audio upload budget and tally) and Addendum B4 (the 49 cap enforced by the ladder, which post-dates revision 3). The PARTIALs are listed in §2.5.

---

## 1. Requirement inventory (brief v2, bullet by bullet)

### 1.1 Preamble and §1 Source of truth

| ID | Requirement (brief v2) | Status | Plan section | Note |
|---|---|---|---|---|
| P-1 | Build the whole game in one pass | COVERED | §4.1 | Step 0 plus W0-W7 with W3c/W4b inserted |
| P-2 | Do not ship a walkable-town-first milestone | COVERED | §4.1, §4.4 | W1 has no owner build; spikes on a spike place |
| P-3 | Every role test-playable from the first runnable build | COVERED | §4.5-§4.7 | All eight roles reach the FRB through the Lab; see CT-3 for the stale rodent check |
| 1-1 | Canonical spec is v5.4 HTML, SHA-256 pinned | COVERED | W0 #3 | harvest checks the hash |
| 1-2 | v5.4 superset retained: Galleria, apple trees, nests, birds, overflights, heavy vehicles, fatal traffic | COVERED | §1.4 `Galleria`, W4 #5, W4 #7, §4.6, D9 | |
| 1-3 | The HTML is the reference for layout, routes, lanes, districts, mechanics | COVERED | D8, §6.3 golden vectors | |
| 1-4 | From-scratch Luau rewrite, not a transpile | COVERED | §0, §6.3 | |
| 1-5 | Restore nut caches | COVERED | W2 #7, §3.12 | v4.1's +5 Power and coin values per cache are not ported (delta V2-227 note); acceptable under the Power table's "verbatim" |
| 1-6 | Restore deer, foxes, butterflies, garden insects | COVERED | W2 #8, W4 #7 | |

### 1.2 §2 Toolchain and repository

| ID | Requirement | Status | Plan section | Note |
|---|---|---|---|---|
| 2-1 | Rojo project under git, one repo, Studio syncing from the filesystem, no zip handoffs | COVERED | §1.2, D15, §2.1 #1 | declared deviation 1 (saved place versions; live-sync available), accepted by default |
| 2-2 | Blender for all character **and prop** assets | PARTIAL | §5.1 Lane 1, §1.4 WorldGen `Wire (Beams)`, `Signage (SurfaceGui text)`, Skyline massing, Terrain | Wires as Beams, signs as SurfaceGui text, Skyline massing as Parts and the ground as Terrain stay permanently non-Blender; sensible, but an undeclared deviation (RQ-2) |
| 2-3 | FBX with animations, imported via the Studio animation importer | COVERED | D11, S7, §2.1 #2 | declared deviation 2 with the importer as the budgeted fallback |
| 2-4 | Code by concern, one module per system, under Shared / Server / Client | COVERED | §1.2 | |
| 2-5 | `WorldGen` from data, never hand-placed | COVERED | §1.4 WorldGen, D6 | |
| 2-6 | `Routes` registry (trees, poles, wires, rooftops) | COVERED | §1.4 `Routes/*` | |
| 2-7 | `Traffic` (lanes, vehicles, yielding, swept collision) | COVERED | §1.4 `Traffic/*`, `Vehicles/*` | |
| 2-8 | `Actors` single actor model | COVERED | §1.4, §1.5 | |
| 2-9 | `Roles` (hierarchy, queue, ladder) | COVERED | §3.7 | |
| 2-10 | `Infection` (bite, spread, cure, win) | COVERED | §1.4 `Infection/*`, D17 | |
| 2-11 | `Hospital`, `Police`, `Drone` job systems | COVERED | §1.4 server table | |
| 2-12 | `Seasons` (calendar, winter) | COVERED | `Time/*`, `Seasons/SeasonService` | |
| 2-13 | `Foraging` (gardens, feeders, trash, hollows, nut meter) | COVERED | `Foraging/*` | |
| 2-14 | `Wildlife` (fox, deer, birds, insects) | COVERED | `Wildlife/*`, client `World/*` | |
| 2-15 | The town is a data file of lots; adding a barber shop is a data entry | COVERED | §3.2, §3.3 | |
| 2-16 | StreamingEnabled on; map several thousand studs | COVERED | §1.2, §4.6, D32 | |
| 2-17 | Scale about 2.5 st per HTML unit; squirrel 1.2 st; humans R15 | COVERED | `Config/Units`, Tunables `shoulderHeight`, §5.2 | |

### 1.3 §3 The world

| ID | Requirement | Status | Plan section | Note |
|---|---|---|---|---|
| 3-1 | Old town core: streets, sidewalks, houses, poles and wires, trees | COVERED | §4.6 World | |
| 3-2 | Hospital (west), expanded | COVERED | W1 #7, W2 #3, W3a #3 | |
| 3-3 | Police station, expanded | COVERED | §3.12, W3a #4 | |
| 3-4 | Riverside: stone arch bridge, cobbled quays, rooftops | COVERED | WorldGen `Quay`, W5 #7 | |
| 3-5 | Galleria: six shops, upper gallery, coin fountain, interior lighting, camera constraints | COVERED | data migration, W4 #9, W6 #4, W3b #9 | |
| 3-6 | Sewer and duct interiors, house interiors | COVERED | W3b #9, W3a #3, W2 #9 / W3a #2 | |
| 3-7 | Restaurants roughly doubled; the eight kinds; each with outdoor seating or a dumpster | COVERED | inv 4, W3b #5 | baseline 9 -> at least 18 |
| 3-8 | Barber, music, hardware, laundromat, bookshop, pet store, gas station, corner grocery, school with playground, church, park with gazebo, community garden, small marina | COVERED | inv 4, W3b #5 | |
| 3-9 | At least eight house models; every house its own flair; backyards with gardens, feeders, sheds, fences, dog houses | COVERED | §3.4, inv 10, inv 12, W3b #6 | |
| 3-10 | Each lot type defines forage and risk | COVERED | §3.3, inv 4 | |
| 3-11 | Backdrop holds up at altitude for the drone | COVERED | D5, S11, W6 #5, OS-7 | |
| 3-12 | Mountains to hills and plains, tree line, distant road, fog layering | COVERED | W6 #1, §5.3 P5 | |
| 3-13 | Ocean with beach, pier, marina; horizon correct from 300 st | COVERED | W6 #1, W6 exit | |
| 3-14 | Full day cycle; sunrise and sunset as moments; clouds; overflights; stars; moon phases on a 29.5-day lunar month, never permanently full | COVERED | D19, W6 #2-#4, `Time/Moon`, W6 exit | |
| 3-15 | Distant radio or cell tower, blinking red lights, silhouetted against the sunset | COVERED | W6 #1, OS-7 | |
| 3-16 | 12 hollow trees, each claimable with a nut meter, plus a fallen hollow log | COVERED | §3.5, §5.5, inv 5 | |
| 3-17 | Premium 1 spiral ramp with chambers; premium 2 straight shaft with knothole exit and hideout; both by the best gardens and feeders | COVERED | §5.5 H1, H2; inv 5 (40 u) | |
| 3-18 | One escape tree with three apertures and exits | COVERED | §3.5 H12, §5.5, FRB Q12 | |
| 3-19 | The other nine: single chamber from a knothole | COVERED | §5.5 H3-H11 | |
| 3-20 | Claiming is proximity, no scent-marking; own while meter ≥ 70 % and visited every three in-game days, else the claim lapses | COVERED | `ForageRules.owner`, Tunables `forage.ownVisitDays`, FRB Q11 | 3 days = 3.6 real minutes at 72 s/day (item 38); built as written |
| 3-21 | Nuts finite per season | COVERED | `seasonStock`, inv 15, `SimLong` | |
| 3-22 | A squirrel carries at most 9 nuts | COVERED | Tunables `forage.carryMax = 9`, FRB Q10 | |

### 1.4 §4 The actor model

| ID | Requirement | Status | Plan section | Note |
|---|---|---|---|---|
| 4-1 | One actor kind per species; the only question is AI brain or player controller | COVERED | §1.1 rule 1, §1.5 | |
| 4-2 | Every human and squirrel AI-driven by default | COVERED | §1.5 Join | |
| 4-3 | Joining takes an existing actor mid-stride; leaving hands it back | COVERED | D1, S2, FRB M1-M2 | |
| 4-4 | Promotion is the same handoff | COVERED | §1.5 Swap | |
| 4-5 | One mechanism implements queue, backfill, role switching and session reset | COVERED | §1.1 rule 1, §1.5 | |
| 4-6 | More human bodies than the 35 slots; hospital, station, shops and streets staffed regardless of player count | PARTIAL | §1.5 budget, D23, inv 11, S19 | the floor totals do not add up and the hard cap cannot serve 49 humans with every floor kept (CT-1) |

### 1.5 §5 Server population

| ID | Requirement | Status | Plan section | Note |
|---|---|---|---|---|
| 5-1 | 49 hard: 35 humans (hospital and police inside), 7 squirrels, 1 rodent, 5 deer, 1 fox; when full it is full; no overflow, no spectators | COVERED | §1.5, §3.7, D23, inv 20, `Cap49`, OS-0 | |
| 5-2 | Any slot not held is AI; squirrel bodies float 10-14 | COVERED | §1.5, inv 11 | |
| 5-3 | At least 6 NPC police and 10 NPC hospital staff, crews on top; player staff faster with bonuses; town functions without them | PARTIAL | §1.5 table, inv 11, Tunables `aiStaffSpeedMult`, S19 | floors named, but the arithmetic that proves they survive a 49-player fill is wrong (CT-1) |
| 5-4 | Deer and fox voluntary instead of a promotion; fox hidden Easter egg | COVERED | §3.7 `sideExits`, Offers | |
| 5-5 | Limited server count so a real queue exists | PARTIAL | dec 26, §2.1 #4, risk 16 | platform LIMIT; server fill "Maximum" approximates it; the owner is told |

### 1.6 §6 Roles and the promotion ladder

| ID | Requirement | Status | Plan section | Note |
|---|---|---|---|---|
| 6-1 | The ladder stated in one place (`Roles`) and nowhere else | COVERED | §1.1 rule 2, §3.7, inv 13 | but §3.15 restates the score weights in data (CT-4) |
| 6-2 | Human: lowest rung; walks, earns by working, can be bitten | COVERED | FRB H1-H7 | |
| 6-3 | Hospital staff 5 slots; police 5 expandable to 8; hospital slightly above police | COVERED | §3.7 `prestige`, `policeSlots` | |
| 6-4 | Regular squirrel 7 slots: forages, stores, claims | COVERED | §3.7, W2 #7 | |
| 6-5 | Spicy rodent 1 slot | COVERED | §3.7 | |
| 6-6 | Human base rank = time logged on this server, modified by job credits | COVERED | `Ladder.score` (C6 reconciliation) | weights make money negligible (CT-5) |
| 6-7 | Squirrel rank 90 % nuts, 10 % stink; top squirrel becomes the next rodent | COVERED | `Ladder.score`, rodent-slot row, FRB R5, M7 | |
| 6-8 | Rodent dies -> its player restarts as lowest human | COVERED | §3.7, FRB R5, R6 | |
| 6-9 | Human killer -> lowest uninfected squirrel if a body is free, else police, or hospital if > 30 % infected | COVERED | §3.7 `rodent.killed` row | |
| 6-10 | Hospital staff who kill it inside the hospital instantly become a squirrel | PARTIAL | §3.7 (`extraSlot = true`), dec 15, FRB S5 | the temporary 8th squirrel player slot contradicts brief §5's hard "7 regular squirrels" (CT-6) |
| 6-11 | A regular squirrel cannot kill the rodent, only be infected | COVERED | no squirrel attack verb | |
| 6-12 | An infected squirrel loses heavily and drops in the queue | COVERED | `Ladder.params.squirrelInfected`, FRB Q8 | |
| 6-13 | Squirrels that die in winter restart as humans | COVERED | §3.7 winter row, FRB M8 | |
| 6-14 | Deer and fox are side exits; leaving returns the previous human rank | COVERED | §3.7, FRB F5, E3 | |

### 1.7 §7 Squirrel play

| ID | Requirement | Status | Plan section | Note |
|---|---|---|---|---|
| 7-1 | Port the v5.4 route registry (curves, samples, kind, speed, surface radius, visualOffset) | COVERED | D8, §3.5 | |
| 7-2 | Rail climbing, free running on the ground, leaps between rails | COVERED | `Routes/Motion`, `SquirrelMotor`, S3 | |
| 7-3 | Seven clips on one rig: Run, Climb, Wire, Leap, Pounce, Bite dance, Sneak | COVERED | §5.4 | |
| 7-4 | Weight and presence (fur, muscle, tail lag); stacked-spheres placeholder replaced entirely | COVERED | §5.6, §5.3 P0, G2 bar, W5 must-replace list | no artist fallback (dec 23); "rough is fine" is the bar |
| 7-5 | Forage sources: gardens, feeders (risky), trash cans and dumpsters, apple trees, mall plaza | COVERED | W2 #7, W4 #5 | |
| 7-6 | Nuts in a claimed hollow raise its meter; above 70 % others cannot take them | COVERED | `ForageRules`, W4 #5 theft rules, FRB Q4 | |
| 7-7 | Premium gardens and feeders raidable about once per in-game week | COVERED | `Calendar.raidWeek`, W4 #5 | |
| 7-8 | Stink gland: slow meter, 10 % of rank, fires only ≥ 95 %, −30, repels foxes and humans briefly | COVERED | Tunables `forage.stink*`, FRB Q5, F4 | |

### 1.8 §8 Spicy rodent play

| ID | Requirement | Status | Plan section | Note |
|---|---|---|---|---|
| 8-1 | Stalk (hold), pounce, bite as in v5.4; unaware people are easier | PARTIAL | FRB R2-R4, `CameraRig`, item 39 | v5.4's stalk is first person; the plan defaults to over-shoulder (§14) but FRB R2 still describes first person (CT-3); the v5.4 aim arc and the stalk noise rule are not re-specified for the new camera (VD-9, VD-10) |
| 8-2 | Biting humans infects them; biting squirrels raises town-wide infection | COVERED | W2 #2, `InfectionRules.squirrelShare` | |
| 8-3 | Fatal traffic as a server-side relative swept test, not Touched; being run over ends the run | COVERED | D9, S4, FRB R6 | |
| 8-4 | Hidden win: infecting staff slows cures; no meter ever shown; about half the town plus half staff and patients triggers the outbreak | COVERED | D17, Tunables `infection.critical*`, `infectedStaffCureMult` | |
| 8-5 | The outbreak is a cinematic: camera pulls up and out, time accelerates, squirrels sweep house to house, overcast and dims, night fades to black; needs the lamplit town | COVERED | D31, `OutbreakDirector`, W4 #13, W3a #5 lamps, `OutbreakCinematic` suite | |
| 8-6 | Rodent death: board not wiped; infection resets to the new rodent (~0.5 %); squirrels keep hoards; humans keep points and reputation; infected squirrels -> lowest human; infected humans cured (instantly if recent or en route) | COVERED | §1.5, `InfectionService.resetToRodent`, §3.7 rows, FRB R11, M10 | |
| 8-7 | Deer biteable only once every squirrel is infected; a bitten deer turns rabid and charges, accelerating the collapse; before that the rodent ignores deer | PARTIAL | `deerBiteable`, `RabidDeer`, W4 #1, FRB R10, E4 | what the charge does mechanically is open (item 40); "accelerating the collapse" has no mechanism in the default (knockdowns and panic only) |
| 8-8 | Bite aftermath: high alert; hidden strength boost; more swings; NPC police within ~2 blocks chase up to 5; ambulance plays out; a second bite nearby is close to impossible | COVERED | `CombatService.alertZone`, Tunables `alert.*`, W4 #1-#3 | "block" measured from `roads.json` (item 43) |
| 8-9 | Refuges between bites: hollows, sewer, poles, trees as rodent cover | COVERED | `concealment.json` unseen volumes, `HollowService` rest, W3b #9, W4 #1 | |
| 8-10 | Pounce has wind-up, commit and recovery; biting in the reaction window lands, into a raised arm or kick does not | COVERED | W2 #1, dec 12, §6.2 `CombatRules` | |
| 8-11 | Zig-zag raises miss chance but costs speed; straight sprint is fast and readable | COVERED | W4 #1 | |
| 8-12 | Feint forces an early flinch or swing; costs stamina; read correctly it hands a free hit | COVERED | W4 #1, `CombatRules.feint` | |
| 8-13 | Humans flinch, swing, kick, back away or flee by awareness and nerve; vigilantes never flee | COVERED | W4 #1 | civilian swing is new (v5.4 had none) and is planned |
| 8-14 | Every show-off option carries a trade-off | COVERED | W4 #1 | |
| 8-15 | 8 % of all human actors are vigilantes; they move to kick on sighting and answer the drone's call | COVERED | `VigilanteRules`, W2 #5, FRB DR3, `SimFull` | |
| 8-16 | Health 100; kick 55 (two kicks kill); defenders 1.5x (~82) | COVERED | Tunables `rodent.*`, dec 12 | |
| 8-17 | Health drains 1 % per in-game day without a bite; a human bite restores 10 %, a squirrel bite 20 %; slow regen while sneaking or in a hollow | PARTIAL | Tunables `rodent.drainPerDay`, `healOnBite`, `regenStalk`, `regenHollow`, D33, FRB R7, R9 | the regen defaults are 18x and 72x the drain per in-game day, so the drain never matters (CT-2) |
| 8-18 | Power fades on real minutes; health drains on in-game days; two clocks, never merged | COVERED | §1.1 rule 11, D33, §6.2 two-clock tests | |
| 8-19 | Three defender houses: two older housewives of different appearance with rolling pins, one man with a broom | COVERED | inv 3, §5.3 P1, W3a #2, W4 #1 | |
| 8-20 | Squirrel chases carry tunnel vision: squirrels match the rodent; long exposed chase; camera locked forward; blind-side risk; the 20 % heal is the reward | COVERED | `CameraRig` chase lock, Tunables `squirrel.chaseLockRange`, `Brains/Squirrel` flee, W4 #1 | |
| 8-21 | 40 houses with full interiors the rodent can burst into; humans hide; escape or bite depends on the chase; must run and be tested | COVERED | W3a #2, W3b #6, §3.4 escape rule, `RodentLoop`, OS-5 | |
| 8-22 | The 40 houses are claimable homes; each real day earns remodel points; remodels persist for the server's life | COVERED | `HomeService`, W4 #4, D14, §2.1 #3 | declared deviation 3 (points per real hour), accepted by default |

### 1.9 §9 Hospital, §10 Police, §11 Wildlife, §12 Seasons, §13 Credits

| ID | Requirement | Status | Plan section | Note |
|---|---|---|---|---|
| 9-1 | Rooms: reception, triage, two wards, isolation, pharmacy, staff room, ambulance bay, roof access as a squirrel route | COVERED | W1 #7, W3a #3, W3b #8 | |
| 9-2 | Infected delivered or walk in; staff disinfect through a short loop at stations | COVERED | W2 #2-#3, W4 #3, FRB S3 | |
| 9-3 | Performance = speed of disinfection; raises staff rank; unlocks station upgrades | COVERED | §3.9 metrics and upgrades, W4 #3-#3b | |
| 9-4 | Staff can kill the rodent inside the building | COVERED | FRB S5 | |
| 9-5 | Infected staff cure slower | COVERED | Tunables `infectedStaffCureMult`, FRB S6 | |
| 10-1 | Five officer slots; officers pursue and can kill the rodent | COVERED | §3.7, FRB P3 | |
| 10-2 | Good performance unlocks officers one at a time to eight; later officers more aggressive and coordinated | COVERED | §3.9 police performance, `PoliceCoord` tiers, W4 #2 | |
| 10-3 | At eight officers the next upgrade unlocks a drone: full flight, camera feed, spot-and-mark that reveals the rodent and calls vigilantes; "as good as it can be" | COVERED | §3.7 `drone`, §3.9 upgrade, `DroneService`, S11, FRB DR1-DR5 | |
| 11-1 | Fox: one slot, Easter egg, hunts squirrels, cannot harm the rodent, repelled by stink | COVERED | §3.7, W2 #8, FRB F1-F5 | |
| 11-2 | Deer: several slots, peaceful, startled by traffic and the drone | COVERED | W2 #8, FRB E1-E3, DR4 | |
| 11-3 | AI-only birds, nests, butterflies, insects; AI deer and foxes when unheld | COVERED | W4 #7, §4.6 | |
| 12-1 | In-game calendar; week = raid cycle; one tunable constant; ~50 real minutes per winter cycle; visible day and night | COVERED | D19, Tunables `clock.*`, W2 #10 | |
| 12-2 | Every five weeks winter for one week: snow, bare trees, dimmer light, reduced foraging | COVERED | D19 (week 6 of 6), W4 #6, W2 #10 | |
| 12-3 | At winter's end squirrels below the threshold die and restart as humans, opening slots | COVERED | W2 #10, §3.7 winter row, FRB M8 | |
| 13-1 | Humans earn credits by working: hospital, police, shop jobs | COVERED | §3.3 jobs, §3.9, D26 | one currency (C6) |
| 13-2 | Credits raise queue rank and buy the §9/§10 upgrades | COVERED | `Ladder.score`, §3.9 upgrades, W4 #3b | the money weight makes the rank effect token (CT-5) |

### 1.10 §13a Human life

| ID | Requirement | Status | Plan section | Note |
|---|---|---|---|---|
| 13a-1 | Humans are 35 of the 43 player slots; the human life is a full game, not a waiting room | COVERED | §1.5 (43 = 35 + 7 + 1), W2 #6c anchors, W3c, W4b | the brief's 43 and 49 disagree; the plan picks the only sensible reading silently (note in §2.3) |
| 13a-2 | Total free range; duty optional, never costs rank; doing it raises rank inside that administration; rank for time served | COVERED | §3.7 Offers, `Ladder.score` (`wAdmin`), `w.time` | |
| 13a-3 | Police, doctors and nurses get distinct outfits | COVERED | §5.3 P1, §5.6 | |
| 13a-4 | Avatar blend: body keeps build and clothes (~70 %), takes face, hair and skin tone (~30 %) | COVERED | D13 (rev 3), D22 | |
| 13a-5 | Do this with appearance properties scripts can set, not tinting | PARTIAL | D22, S8(e), item 37 | the skin path (`MeshPart.Color` through transparent texels) is the same transparent-texel tint technique D22 removed for accents; the plan itself asks the owner (item 37) but builds textures on it from the W3-W4 art slots (FE-6) |
| 13a-6 | Several golf carts and bicycles | COVERED | D27, W2 #6c (5), W3c #14, inv 17, FRB H14 | |
| 13a-7 | Trampolines | COVERED | W3b #6, inv 16, §4.15 D-11 | |
| 13a-8 | Two climbable tree houses (risky: squirrels reach them) | COVERED | W3b #6, inv 16 | |
| 13a-9 | Mischief: TP-ing trees, knock-and-run, egging at night, water balloons, joyriding a police cart | COVERED | `MischiefService`, W4b #6 | consequences and supplies are item 44 defaults |
| 13a-10 | Mischief angers NPCs and gives police something to respond to | COVERED | `AngryNpc`, `mischief_response` quest, W4b #6 | |
| 13a-11 | Taunt button cycling about 20 one-liners | COVERED | `TauntService`, `speech/taunts.json`, W2 #6c (7), FRB H16 | |
| 13a-12 | Gig: lawn mowing (quick) | COVERED | `gig_mow`, W2 #6c (3), FRB H11 | |
| 13a-13 | Gig: restaurant delivery by bike or cart | COVERED | `gig_delivery`, W4b #5 | |
| 13a-14 | Gig: sign-spinning | COVERED | `gig_sign`, W4b #5 | |
| 13a-15 | Gig: car washing | COVERED | `gig_wash`, W4b #5 | |
| 13a-16 | Gig: morning newspaper bike route, bonus for hitting the porch | COVERED | `gig_paper`, W4b #5 | |
| 13a-17 | Gig: serving tables at the steakhouse | COVERED | `gig_serve`, §3.17, W4b #5 | |
| 13a-18 | One rule for all gigs: extra-good earns a tip; bad gives a very minor reputation ding | COVERED | `GigRules`, §3.9 | |
| 13a-19 | NPC-posted mini-missions on a poster or billboard (walk Mrs. Harrison's dog, return a lost pet) paying coins | COVERED | `npc.post`, billboard and poster UI, `PetService`, W4b #5 | |
| 13a-20 | Reputation is two-sided; NPCs like you and pal around or follow; a bigger entourage raises rank | COVERED | `ReputationRules`, `Companion` overlay, `Ladder.params.w.entourage`, W4b #7 | |
| 13a-21 | Thumbs up or down to **anyone**, five of each per in-game day; a vote against affects reputation | PARTIAL | `VoteService`, §3.15 (`targets: players`), FRB H12 | "anyone" narrowed to players only by default (Q21); 5 + 5 per 72-second day is item 38 |
| 13a-22 | Weight votes by the voter's reputation to blunt brigading | COVERED | §3.15 weight clamp, §6.2 brigading test | |
| 13a-23 | Sitting at a cafe raises reputation | COVERED | `Seat` sockets, §3.15, FRB H13 | |
| 13a-24 | Reputation rises for rescues, true sighting reports, returning lost pets | COVERED | `Rescue` signal, Report verb, `PetService`, §3.15 | |
| 13a-25 | Big boost for a kick on the rodent or any infected squirrel | COVERED | §3.7 `kick.landed`, W4 #1 | |
| 13a-26 | Killing an infected non-leader squirrel kills it; a healthy one respawns; top-ranked hospital player promoted; killed player to the bottom of the human queue | COVERED | §3.7 `squirrel.killed` rows, FRB Q13, M11 | healthy squirrels immune by default (item 40) |
| 13a-27 | Infected squirrels never recover; one alive at the win restarts the next match as a regular squirrel | COVERED | `InfectionService`, §3.7 reset row, D17 | |
| 13a-28 | Police recruitment offer to the top-ranked human; declined, it passes by seniority | COVERED | §3.7 recruitment rows, `recruitCascade` | |
| 13a-29 | Currency Spicy Dollars; Robux buys them through developer products (~1:4; whole Robux) | COVERED | D26, `Economy/Store`, `products.json`, S15, W4 #11, OS-0 | tiers are item 43 |
| 13a-30 | Minimum wage 2 pennies per in-game hour; coffee 12, nachos 5 | COVERED | `wages.json`, `prices.json` | |
| 13a-31 | Money's main use is buying your place in the human queue, never police or hospital | PARTIAL | `Ladder.score`, `Ladder.params.w.money = 0.02` | money never enters tier-2 scores (right), but at 0.02 per S$ against 1.0 per active minute a 25 R$ purchase is worth two minutes of play (CT-5) |
| 13a-32 | Queue rank = money plus reputation; at least 10 in-game days before being ranked | COVERED | `Ladder.params.w`, `rankGateDays`, FRB H17 | 10 days = 12 real minutes (item 38) |
| 13a-33 | Places and attractions all fully interactive, not set dressing | COVERED | rule 13, D28, §3.16-§3.17, W3c, W4b | |
| 13a-34 | Detailed antique store | COVERED | `shop_antique`, W3c #13 | browsable curios by default (item 44) |
| 13a-35 | Detailed pet store | COVERED | W3b #5, W3c #15 | |
| 13a-36 | A very specific barber shop | PARTIAL | W3b #5, item 44 | nobody holds the owner's specifics; the plan builds a two-chair default |
| 13a-37 | An intricate police station | COVERED | W3a #4, W5 #6 | |
| 13a-38 | Corner store: 1970s-style layout (not literally period), working checkout counter | COVERED | `shop_corner`, §3.17, W2 #9 greybox, W3c #13 | |
| 13a-39 | About 22 pick-up-able shelf items, every one functional, all cheap except bird seed and the kite | COVERED | `Item` framework, `items.json` (22 ids, prices match the brief), W2 #6c (2), W4b #3 | |
| 13a-40 | water gun 6: squirts people, they react; first squirt on the rodent stuns it 1.3 s, once per player | COVERED | `items.json`, Tunables `waterGunStunSecs`, FRB H10 | once per server or forever is item 40 |
| 13a-41 | frisbee 5 | COVERED | `items.json` throwable | |
| 13a-42 | football 6 | COVERED | `items.json`, FRB H10 | |
| 13a-43 | bubbles 3 | COVERED | `items.json` vfx | |
| 13a-44 | sidewalk chalk 2, about 20 letters per stick | COVERED | `items.json`, `TextService` filter, S20 | |
| 13a-45 | flashlight 6, works at night | COVERED | `items.json`, FRB H10 | one more light per player (S17) |
| 13a-46 | umbrella 5 | COVERED | `items.json` cosmetic | no function in the brief; cosmetic default (item 44) |
| 13a-47 | peanuts 4 | COVERED | `items.json` bait | peanuts versus seed is item 44 |
| 13a-48 | bird seed 40, baits squirrels and birds | COVERED | `items.json` bait, W4b #3 | |
| 13a-49 | dog treats 4 | COVERED | `items.json`, `PetService` | |
| 13a-50 | newspaper 2 | COVERED | `items.json`, `gig_paper` | |
| 13a-51 | disposable camera 6, takes screenshots | COVERED | `items.json`, `CaptureService`, S20 | |
| 13a-52 | duct tape 4 | COVERED | `items.json` | effect undefined by the brief; default patches a bandage (item 44) |
| 13a-53 | whoopee cushion 15 (moderate, to limit how many are about) | COVERED | `items.json` seat trap | |
| 13a-54 | harmonica 5 | COVERED | `items.json` sound | |
| 13a-55 | air horn 5, startles NPCs and squirrels | COVERED | `items.json` startle, FRB H10 | |
| 13a-56 | soda 4 | COVERED | `items.json` stamina, FRB H10 | depends on a human sprint-stamina system the plan never defines (RQ-14) |
| 13a-57 | ice cream bar 5 | COVERED | `items.json` stamina | same note |
| 13a-58 | lawn chair 6, sit anywhere | COVERED | `items.json` place_seat, FRB H10 | |
| 13a-59 | radio 8, plays the stock library | COVERED | `items.json` playlist, D24 | |
| 13a-60 | bike horn 3 | COVERED | `items.json` sound | |
| 13a-61 | kite 60, a full flying sequence in the park and on the beach | COVERED | `rides/kite.json`, W4b #3-#4 | a ride with a little input; the brief lists it in neither category |
| 13a-62 | No lottery or gambling items | COVERED | §3.14 header, risk 11 | |
| 13a-63 | Doctor's office: receptionist at the counter | COVERED | `clinic`, §3.17, W3c #13 | |
| 13a-64 | Two openable picture books (animals; early America) | COVERED | `content/books.json`, W3c #13 | procedurally written and drawn (item 44) |
| 13a-65 | A wire bead maze | COVERED | W3c #13, W4b #2 | |
| 13a-66 | Playable tilt labyrinth; controls fixed: W/S forward and back, up and down arrows right and left, up is right | COVERED | `tilt_labyrinth` `fixedControls`, `InputMap`, W4b #2 | |
| 13a-67 | Museum with readable exhibits | COVERED | `museum`, `content/exhibits.json`, W3c #13 | |
| 13a-68 | Bowling: angle and power, bowl, physics pins, ball returns up the rack, overhead lights, working scoreboards | COVERED | `bowling` minigame, §3.16, W4b #1, S13, OS-5c | authority and test venue issues in FE-1 to FE-3 |
| 13a-69 | Ball-return tunnel is a real squirrel route under the lane to the rack; playable and rendered with great care | COVERED | `rack_tunnel_lane_*` routes, W3c exit check, §5.3 P4 hero piece | |
| 13a-70 | Three pinball machines, distinct themes, real flipper physics | COVERED | pinball x3 client physics, W4b #2 | |
| 13a-71 | Two pool tables | COVERED | `pool`, W4b #2 | |
| 13a-72 | A bumper pool table | COVERED | bumper variant, W4b #2 | |
| 13a-73 | Dartboard: mouse aim point, timing meter, slight wobble; 501 and cricket | COVERED | `darts` server-deterministic, W4b #2 | |
| 13a-74 | Free-play fortune-teller slot machine: pull the lever, **reels spin**, fortune or taunt; no money in or out | PARTIAL | `fortune_machine`, Q20, item 44 | the plan replaces spinning reels with fortune cards for policy reasons; right call, but it is a change to the brief's text pending the owner |
| 13a-75 | Back of house: steel push-bar doors to an alley, big round dark-blue used cans, a push broom | COVERED | §3.17 `backOfHouse`, W3c #13 | |
| 13a-76 | No scrimping on the bowling alley | COVERED | W4b order, W5 #9 polish | |
| 13a-77 | Racquetball court vs NPCs or players, real ball physics | COVERED | `racquetball`, `RacquetballOpponent`, W3c #13, W4b #2 | |
| 13a-78 | Steakhouse: outdoor bar; glass walls squirrels see through but cannot enter (a human refuge) | COVERED | `steakhouse` (`SquirrelBlocked`, Humanoid-only doors), W3c #13 | |
| 13a-79 | Sand with a beach ball and a working volleyball net | COVERED | `volleyball`, W3c #13, W4b #2 | |
| 13a-80 | Playable four-foot giant Jenga on a deck table | COVERED | `giant_jenga`, W4b #2 | stability test venue in FE-1 |
| 13a-81 | Jet ski rental | COVERED | `JetSkiMotor`, D27, W3b #5, W4b #4 | |
| 13a-82 | Parasailing | COVERED | `rides/parasail.json`, W4b #4 | |
| 13a-83 | Sky lift up a slight hill to a hilltop restaurant (second vantage) | COVERED | D32, W3b #11, W4b #4, OS-7 | |
| 13a-84 | Paintball arena inside a big abandoned five-storey TV station | COVERED | `tv_station`, W3a #6, W3c #13 | |
| 13a-85 | Runs as its own match, rodent-free | COVERED | D29 in-server instance, `ArenaService`, S18 | venue default (item 42); see SQ-4 |
| 13a-86 | 20 cents buys five in-game days of access, which also unlocks five days in the lounges | COVERED | `PaintballRules.pass`, `prices.json`, W4 #10 | 5 days = 6 real minutes (item 38) |
| 13a-87 | Mechanics over looks; generic marker that shoots right | COVERED | W4 #10, §5.3 P3 | |
| 13a-88 | Projectile with travel and slight drop | COVERED | `arena.json`, W4 #10, S18 | |
| 13a-89 | Five-shot magazine, auto-reload when empty or on a button | COVERED | `arena.json` magazine | |
| 13a-90 | Server-side hit detection with lag compensation | COVERED | D29, pose history, S18, `Paintball` suite | |
| 13a-91 | Paint splats that stay on walls and players | COVERED | `arena.json` splat pool | |
| 13a-92 | Five-floor layout with stairwells and a central atrium | COVERED | W3a #6, W3c #13 | |
| 13a-93 | Team deathmatch 4v4 to 8v8 with NPC bots filling | COVERED | D25, D29, `PaintballBot`, S19 | |
| 13a-94 | Match timer, scoreboard, end card | COVERED | W4 #10 | |
| 13a-95 | Distinct audio for fire and hits | COVERED | D24, W4 #10 | |
| 13a-96 | Sprint and crouch that feel right | COVERED | `Controllers/Paintball`, Tunables `crouchHeightMult` | |
| 13a-97 | If the mechanics are not good it gets cut | COVERED | G-PB, OS-5b, risk 26 | the plan's one GATED row |
| 13a-98 | Build it in Wave 4 and playtest with Ben before calling it done | COVERED | W4 #10, OS-5b | |
| 13a-99 | Upgraded paintball garb at one Spicy Dollar per set, kept permanently | COVERED | `prices.json`, profile wardrobe (D26), W4b #9 | |
| 13a-100 | A few Blender outfit sets (mask, chest rig, pads), four colourways, insignia and patches, cosmetic only | COVERED | §5.3 P3 garb, S16, W4b #9 | |
| 13a-101 | Wear it around town if possession allows, else auto-remove on leaving; stays in the wardrobe | COVERED | D13 accessory path, S16, W4b #9 | |
| 13a-102 | Check custom clothing meshes on a possessed body; fallback accessories plus texture swap | COVERED | S16 | |
| 13a-103 | Lounge one: squirrel-proof; very tough guards annihilate any squirrel | COVERED | `LoungeGuard`, §3.17 `lounge_classic`, W4b #8 | player-squirrel outcome is item 40 |
| 13a-104 | Elaborate Blender interior: leather, woodwork, fancy counters | COVERED | §5.3 P4, W5 #8-#9 | shells only until W5 (SQ-9) |
| 13a-105 | Classy 1940s-style bartender serving hot cocoa, coffee, green tea, snow cones | COVERED | `Bartender`, `prices.json`, W4b #8 | |
| 13a-106 | Licensed jazz from Roblox's library, 1920s feel | COVERED | D24, W4b #8 | |
| 13a-107 | Lounge two: futuristic, surreal, sci-fi and space, lava lamps, dense plants | COVERED | §5.3 P4, W5 #8 | |
| 13a-108 | A seamless procedurally generated ambient loop | PARTIAL | D24, W4b #8 | Roblox has no runtime synthesis; the plan's "layered library pads or one upload" is the only path, and the upload must count against B3's budget (FE-7, RQ-1) |
| 13a-109 | New small mall with an indoor skydiving wind tunnel as the showpiece | COVERED | `mall_small`, `rides/wind_tunnel.json`, W3c #13, W4b #4 | |
| 13a-110 | Float in a glass cylinder while silly instructors throw giant balls that bounce off you | COVERED | `Instructor` brains, server-owned balls, W4b #4 | |
| 13a-111 | Other players pay Spicy Dollars to add 10 balls | COVERED | `prices.json` wind_tunnel_balls | |

### 1.11 §14 Camera and first person

| ID | Requirement | Status | Plan section | Note |
|---|---|---|---|---|
| 14-1 | Rodent, squirrel, deer and fox stay in standard third person | PARTIAL | `CameraPolicy`, item 39, FRB R2 | the plan's default follows §14 but FRB R2 still specifies v5.4's first-person stalk (CT-3) |
| 14-2 | Humans can toggle first person at any time | COVERED | `CameraRig` human toggle, W2 #6c (6), FRB H15 | |
| 14-3 | Interiors, vehicles and the gondola hold up at eye level | COVERED | §5.6 first-person bar, §5.2 vehicle contracts, W3c exit raycast check | |
| 14-4 | Boarding the gondola or any vehicle switches to first person automatically; the toggle remains | COVERED | `CameraPolicy`, S14, FRB H14 | |
| 14-5 | Vehicles need modelled interiors and dashboards | COVERED | §5.2, §5.3 P3 (six interiors), W3c #14, W5 #4 | |
| 14-6 | Paintball and both lounges locked to first person | COVERED | `LockFirstPerson` zones, §3.17 `cameraLock`, W4 #10, W4b #8 | |

### 1.12 §15 Decisions from the build-plan review (one row per decision line) and the Power table

| ID | Requirement | Status | Plan section | Note |
|---|---|---|---|---|
| 15-0 | Where a default is not named, accept it (drive on the right, north +Z, squirrel 1.2 st, type checking in CI) | COVERED | §8 (every default recorded), `docs/DECISIONS.md` | the plan reverses accepted default 27 without a deviation row (CT-9) |
| 15-1 | Dec 10: 72 s per in-game day with sunrise and sunset held; winter about every 50 minutes; one constant | COVERED | D19, Tunables `clock.*` | |
| 15-2 | Dec 11: half-town trigger; ending is the outbreak cinematic, not an end card | COVERED | D17, D31, W4 #13 | |
| 15-3 | Dec 12: 100 / 55 / 1.5x plus the §8 drain and bite-heal rules | COVERED | D33, Tunables `rodent.*` | the defaults' contradiction is counted once at 8-17 (CT-2) |
| 15-4 | Dec 13: police and drone see everything; hospital bite locations only; markers fade after about a minute | COVERED | `markers.json` | |
| 15-5 | Dec 14: everyone obeys traffic law in town, police included | COVERED | `TrafficLaw`, §3.6 `playerLaw`, W4 #12 | |
| 15-6 | An officer who hits a pedestrian loses the car, sits in a cell, is demoted to lowest rank on release | COVERED | §3.7 `traffic.hitPedestrian`, W3a #4 cells, W4 #12 | |
| 15-7 | The pedestrian wakes up in a hospital bed as an uninfected patient | COVERED | `SweptCollision` `Knockdown`, `HospitalService.admit` trauma, W4 #12 | player pedestrians are item 44 |
| 15-8 | A player driver who runs over the rodent gets the kill credit and the §6 promotion | COVERED | §3.7 `by = driver`, FRB P8, M5 | |
| 15-9 | Dec 18: 34 + 6 homes with a south-east school and church block; marina, pier, beach | COVERED | dec 18, OS-3 | |
| 15-10 | The approval map also shows the steakhouse, hill with sky lift and hilltop restaurant, TV station, bowling alley, new mall, both lounges, corner store, doctor's office, museum, racquetball court, off-road zone | COVERED | OS-3 town-plan page, D32 | |
| 15-11 | Dec 19: 12 hollows, not 11 | COVERED | §3.5, §5.5, inv 5 | |
| 15-12 | Dec 20: keep Power **exactly** as v5.4 implements it | PARTIAL | `Rodent/PowerRules`, §4.15 D-21, FRB R8, `UI/*` | the rules port is exact (golden vectors), but v5.4's visible Power UI also shows the "NEXT POWER FADE mm:ss" countdown, which the HUD list omits (VD-2); the per-bite coin income that accompanied Power is dropped (VD-3) |
| 15-13 | Drop Gold | COVERED | dec 20 | |
| 15-14 | Coins become Spicy Dollars | PARTIAL | W4 #9 (Galleria pickups pay cents), D26 | only the Galleria pickups are converted; v5.4's +10 coins per successful bite and the 150-coin fashion-stand unlock vanish without a row (VD-3) |
| 15-15 | Chili rush becomes a rodent-only power-up | PARTIAL | W4 #1, §4.15 D-8, Tunables `chiliRushSecs = 12`, `chiliRushSpeed = 1.25` | the brief asked for a scope change, not a retune; v5.4 is +30 s per pepper (cap 90 s), x1.6 speed (not while stalking), pounce x1.12, leap 18.5; the plan's 12 s and x1.25 carry no source (VD-4) |
| 15-16 | Sewer and fashion stand stay, outfits as cosmetics | COVERED | W4 #9, §4.15 D-9, D26 wardrobe | |
| 15-17 | Cats and dogs stay | COVERED | W4 #5 `YardHazards`, §4.15 D-5 | |
| 15-18 | Dec 23: no money on art, no outside artist | COVERED | §5.6, risk 4, knob 5 withdrawn | |
| 15-19 | Everything procedural in Blender by the coding session, approved by turntable | COVERED | §5.1, §5.6, G2, S12 | |
| 15-20 | Rough is fine; contours, textures, colours, shading and shadows, basic movement set | COVERED | §5.6 G2 bar | |
| 15-21 | Polish where people pay or play: lounges, arena lighting; every minigame ironed out | COVERED | W5 #9, §5.3 polish slots, W4b checks | |
| 15-22 | Detail high on the ridge and near town; far distance painted | COVERED | W6 #6, D32, W6 #1 | |
| 15-23 | Dec 24: mild; rewrite the swearing to keep the venom and lose the vocabulary | COVERED | W4 #8, W2 #6c (7), risk 11 | |
| 15-24 | Dec 28: server caps at 49; no late-joiner overflow | COVERED | §1.5, D23 | superseded in mechanism by Addendum B4 (AD-6) |
| 15-25 | Rides versus minigames: parasail, sky lift, wind tunnel are rides (no controls, no score); jet ski is the steerable exception | COVERED | `Ride` framework, §3.16, D28, W4b #4 | |
| 15-26 | Minigames have controls and a result (the ten named); only minigames get ironing out | COVERED | `Minigame` framework, §3.16 `ironOut`, W4b, OS-5c | |
| 15-27 | Layered distant fog goes into Wave 6 | COVERED | W6 #1 | |
| 15-28 | Street lighting: lamps on every block with warm pools, a few flicker, porch lights, glowing shop fronts; the drone and the cinematic depend on it | COVERED | D30, `LampPlan`, §3.19, inv 18, W3a #5, W6 #4, S17 | the S17 phone pass bar is not a measurement (FE-4) |
| 15-29 | Off-road zone beyond a ridge with real trees, beach past the public area, back field with hills; no tickets, no arrests; the drone can see it | COVERED | D32, `offroad` district, inv 19, W3b #12, W4 #12 | |
| 15-30 | The top two ranked humans can drive any pickup or SUV; place 6 pickups and 4 SUVs | COVERED | `Ladder.subroles.humanDriver`, D27, `placements.json`, inv 17, W4b #10 | |
| 15-31 | Undocumented in-game; players discover it | COVERED | §1.5 Devices, `kinds.json` `undocumented` | |
| 15-32 | Otherwise only police drive | PARTIAL | D27, item 44 | carts and bicycles for anyone and jet skis for rent are read as "not driving"; a plausible reading, but it is the plan's, not the owner's |
| 15-33 | Open: ID-verified account (audio cap) | COVERED | Addendum B2, D24 | |
| PT-1 | Bite a person: +100 | COVERED | Tunables `power.bitePerson`, golden | |
| PT-2 | Bite a person while world Y is above 4 units: +150 instead | PARTIAL | Tunables `power.highAboveGroundU = 1.6`, item 43 | the plan replaces the table's absolute world Y with height above local ground; defensible on the new terrain, but it is not "verbatim" and waits on item 43 |
| PT-3 | Bite a police officer: +130 | COVERED | Tunables `power.biteOfficer` | |
| PT-4 | Bite and convert an uninfected squirrel: +90, once per squirrel | COVERED | Tunables `power.convertSquirrel` | |
| PT-5 | Hit by a police baton: −19 | COVERED | Tunables `power.batonHit` | the pedestrian kick's −19 (same v5.4 function) is item 43 |
| PT-6 | Hit by a yard cat: −12 | COVERED | Tunables `power.catHit`, W4 #5 | |
| PT-7 | 10 real minutes of active play without a bite: lose 15 % rounded up; repeats | COVERED | `PowerRules.fade`, Tunables `fadeAfterActiveMin`, `fadePct`, §6.2 | active-play clock |
| PT-8 | A bite resets the fade; never below zero; chilis, coins, climbing, missed pounces do not change it | COVERED | `PowerRules`, §6.2 | |
| PT-9 | HUD stages FERAL < 600, RABID 600-1,499, SUPER ≥ 1,500 | COVERED | Tunables `power.stages`, FRB R8 | |
| PT-10 | Keep it as the rodent's visible status meter; it is reputation, health is survival | COVERED | `UI/*` two meters, D33 | fade countdown missing (VD-2) |

### 1.13 §16 Deliverables and the addendum items still in force

| ID | Requirement | Status | Plan section | Note |
|---|---|---|---|---|
| 16-1 | A runnable place with every role test-playable (human, hospital, police, drone, squirrel, rodent, fox, deer) | COVERED | §4.6-§4.7 | |
| 16-2 | Blender sources and FBX: squirrel (rigged, seven clips), human variants, fox, deer, key props | COVERED | §5.7, W7 #5 | |
| 16-3 | The town data file with every lot, including the full restaurant and shop expansion | COVERED | `data/town`, W3 | |
| 16-4 | A short README: module layout; how to add a lot type, a route, a role | COVERED | §1.2, W7 #5 | |
| AD-1 | Addendum A1 (top two officers drive; radar and sightings on the map) | COVERED | §3.7 `driver`, §3.10, FRB P4-P7 | |
| AD-2 | Addendum A2 (rank through kicks, police side quests, hospital fetch; no quest mandatory) | COVERED | §3.9, FRB H6, P6-P7, S4 | |
| AD-3 | Addendum A3 animal blend as confirmed by B1 (capped fur tint, pattern colours, eye colour, one rigid head accessory) | COVERED | D13, D22, S8(c2), S9 | |
| AD-4 | Addendum B2 (ID-verified, Premium) | COVERED | D24, dec 30 | |
| AD-5 | Addendum B3 audio budget: at most 40 uploads a month (50 if genuinely needed); library and in-engine sound first; a running tally in `docs/AUDIO_BUDGET.md`; batch uploads; never an unreviewed take | MISSING | D24 says 100 a month; risk 20 says "10 per month, 100 if ID-verified ... at most 10 signature uploads" | no tally file, no budget number, no batching rule anywhere in the plan (RQ-1) |
| AD-6 | Addendum B4: the place stays at Roblox's 50; the Roles ladder enforces 49 by kicking the 50th arrival before any body is assigned; Creator Hub 49 later only as a safety net | MISSING | §1.5 ("Roblox itself makes late joiners wait"), inv 20 (`MaxPlayers = 49` in the project file), `Cap49` ("the 50th join is refused by MaxPlayers, not by us", "no code path refuses a join below 49"), OS-0 | revision 3 predates B4; the plan's design is the opposite of B4 on every one of these points (CT-17, FE-8) |

### 1.14 Inventory totals

Counted from the tables above: **290 rows: 268 COVERED, 20 PARTIAL, 2 MISSING.** (The counts are recomputed mechanically in §4.)

---

## 2. Findings

### 2.1 Sequencing (SQ)

**SQ-1. Four W0 spikes need a Studio seat the plan does not budget.** Luau Execution runs no physics and no clients [feas B.d], and the container has no Studio. S13 (pool, pinball and Jenga feel at 100-150 ms; "a Jenga tower of 54 blocks stays stable for 60 s on the server"), S14 ("no judder on the owner's Mac"), S15 ("in Studio (API services on): a test developer product bought through ProcessReceipt") and S17 ("60 fps on the owner's Mac and 30 fps on a mid phone") can only be run by a person in Studio. OS-1a (20 min), OS-1b (10) and OS-1c (10) list none of them. Either W0 owner time rises by about 40-60 minutes (one more Studio sitting with a click-by-click script per spike), or these spikes are re-scoped to what a live private server plus the owner's Roblox app can show, or they move to G1 and are no longer G0 inputs. As written, G0 is asked to "choose the physics-authority pattern (S13)" from a spike nobody can run.

**SQ-2. W4b's first items depend on W3c's first items with no ordering between the tracks.** §4.1's table says every minigame (A, W4b) needs "its table, lane or court in an attraction interior (B, W3c)", and W4b #1 is bowling while W3c #13 is one undivided item containing the bowling alley, the clinic, the museum, the racquetball court, the steakhouse, the lounges, the small mall, the antique store and the TV-station detail. W3 was split into W3a/W3b precisely to avoid this; W3c is not split. Recommendation: order W3c by the W4b ironing-out order (bowling alley first, corner store with 22 sockets second, steakhouse and racquetball third, lounges and mall last), state the exits, or give W4b #1 a greybox lane set in the tail of W4 so Track A never idles.

**SQ-3. Owner sessions are understated and bunched.** (a) OS-5 (60 min) is asked to cover a 15-minute smoke, the whole FRB regression set (which alone was 60-90 min at OS-2) and scenario checks for about fourteen new systems (indoor chase to each outcome, defender, each police quest, coordination tiers, upgrades, ambulance, hatch ambush, winter end, mall coins, alert zone, rabid deer, a Robux test purchase, a speeding fine and a cell, the cinematic). That is 2-3 hours of clicking, not one. (b) OS-5 and OS-5b (60 + 60) fall in the same window at the end of W4, followed by OS-5c (90 + 20) at the end of W4b: about 3.8 of the 10.5 planned hours land between the end of W4 and the end of W4b. (c) §0's table omits the four G2 web approvals (4 x 10 min, §4.14) and OS-5c's "+20 min attractions walk" (§6.6). (d) §0 item 1 says "chat, plus 5 minutes on the website" where §4.2 and the §0 table say 17 minutes plus 2 in Studio. (e) Add SQ-1's Studio spikes. A consistent total is about 11.5-12.5 hours before any fallback, not 10.5-11.5, with a 2-hour block at the end of W4 that a non-programmer should be warned about or that should be split over three sittings.

**SQ-4. The paintball venue (D29) is decided at G0 from numbers that cannot be measured headless.** S18's "16 simulated players ... measured inside a SimFull-style task" measures the server-side projectile loop, the pose-history rewind and bot brains, all of which are the plan's own kinematic code. It cannot measure what actually decides whether an FPS can share a 49-player town server: the replication of 16 unanchored, client-owned Humanoids at full rate, 16 clients receiving `Paintball.State` at 20 Hz while the town streams around them, and physics on the arena's unanchored bodies. The first real measurement is W7 #2 ("a paintball match running inside a full server"). If that fails, the fallback is a separate place through TeleportService, which the plan itself describes as breaking the actor model at both ends and needing persistence round-trips. Recommendation: at OS-5b (already 2-4 windows), run the match on a published private server with the Lab filling the town to 49 fake drivers and record the server MicroProfiler; make the venue decision at G-PB, not G0, and keep S18 as the hit-registration proof only.

**SQ-5. W3a is a single-track gate for most of W4.** W3a now carries six large deliverables on Track B alone (traffic control everywhere, 40 interiors with nav and doors, the full hospital with ducts, the station interior with cells, greybox street lighting with real lights, the TV-station greybox), and eight W4 items wait on it (burglar, indoor chases and defenders, stop-sign tickets, isolation and ambulances, upgrade boards, the cinematic, paintball, traffic law). The W4 items that need nothing from W3a (duel tuning, feint, zig-zag, petty argument, parking variants, foraging risks, ambient life, winter) are mostly Track B items themselves (#5-#7), so Track A's unblocked W4 set is small. Recommendation: two W3a exits (W3a-1: traffic control, cells, lamps, TV greybox; W3a-2: interiors and hospital), with W4 #12, #10 and #13 keyed to the first.

**SQ-6. Step 0 schedules work that is already done, and its fixed facts are stale.** OS-0 still tells the owner to create the "CI" and "Art Inbox" places; `spec/PROJECT_IDS.md` (updated today) lists both with IDs and "Luau Execution OK". The plan's fixed facts say "the owner is correcting the luau-execution scope" (now verified) and list "universe-places write" as held (now refused). A non-programmer following OS-0 click by click will stall on step (1). The web time for OS-0 drops to about 12 minutes (Max Players, three developer products), and W7 #8's "publish through Open Cloud" must name the Assets-API route (`assetType: Place`, `published: true`), since the legacy `universe-places` route is the one that is refused.

**SQ-7. FRB check M9 cannot pass with the FRB's bodies.** §1.5's FRB column has 69 standing bodies plus 8 reserve. At "fill town to 49 players", 49 of the 77 bodies are player-held, leaving 28 AI bodies for floors that sum to 32-35 (8 street + 6 shop + 10 hospital + 2 ambulance + 6 police + guard and car crew). M9's "the shops still show workers" and "the hospital shows at least 10 AI staff, the station at least 6 AI police" cannot all be true; the plan's own rule (cut the street and shop floors first) means the shops go dark. Either M9 drops the shop clause or the FRB standing count rises to about 85.

**SQ-8. The lounges are "live" in W4b with empty shells.** W3c #13 builds "both lounges' shells (interiors in W5 kits)", W4b #8 puts guards, the bartender and locked first person in them, and OS-5c asks the owner to walk "a lounge in first person" at build #2b. The brief's lounge is its interior; a locked-first-person walk through a shell is not a check of anything the brief asked for. Move the lounge walk to OS-7 or label it a shell check.

**SQ-9. The FRB (W2) is sized "L" while carrying nine new anchors plus eight rule changes.** W2 now adds the wallet and wages, the `Item` framework with six working items including physics throwables, a gig with quality tracing, reputation with weighted votes and a cafe tick, carts and bicycles with first person (S14-dependent), the toggle, taunts, the Power meter and the 49-population, on top of the revision-2 FRB and the rodent-death, drain, heal, carry-9, visit-rule, deer-gate, squirrel-kill and hospital-first changes. §4.14 keeps W2 at "L" while W3+W4 and W3c+W4b grew to XL+XL. Either W2 is XL or the anchors are the first things the owner trims at G0 (knob 6 is the wrong direction: it pulls more in).

**SQ-10. Cross-reference errors in the dependency table a lead will act on.** §4.1 cites "W3c #1" for the corner store and the lounges (W3c items are numbered 13-16), "W2 #12" for bicycles and carts (W2 has no #12; it is #6c (5)), and §4.8 numbers W3b from 5 after W3a's 1-6, so "W3a #5" (lamps) and "W3b #5" (expansion lots) collide; "W3a #6" is the TV station but the table says it is "W3c #1, pulled forward into W3a's tail". Harmless on a careful read, dangerous as a checklist "the lead checks at every task boundary".

### 2.2 Feasibility (FE)

**FE-1. Physics-dependent suites are listed as Luau Execution tasks.** §6.5 puts `Minigames` ("physics stability: no part leaves its table or lane in 10 simulated minutes; a 54-block Jenga tower stands 60 s") in the "sim" task, and the W4b "ironed out" exit requires the same. Luau Execution does not step physics [feas B.d, high confidence]; nothing unanchored moves. The `Rides` suite's "camera mode" is a client property with no client in a headless task. These tests must run in Studio (owner time) or on a live private server driven by the Lab, and the plan's "an owner build is only saved from a green run" cannot include them as written. Paintball is unaffected (its projectiles are the plan's own 60 Hz kinematic code).

**FE-2. Replay-based validation assumes deterministic physics.** S13's pass bar "a replayed pool shot lands within 0.1 st" and the `Minigames` suite's "the server replay agrees with the shooter's reported outcome within tolerance" assume that re-running the same cue input on the server reproduces the client's result. Roblox's rigid-body solver is not deterministic across machines (or across runs with different frame timing), and pool breaks and pin scatters are chaotic: a 1 mm difference at the first contact becomes a different rack. The plan's own fallback ("shared tables become turn-based with server replay") has the same flaw. Recommendation: pick one authority per table and never replay. For bowling, pool, bumper pool and Jenga, simulate on the server (the ball or cue ball may be predicted on the shooter's client for feel, then snapped) and accept 100-150 ms of input latency, or give the shooter's client ownership of **every** part on the table for the turn (ball and pins, all 16 balls, the whole tower) and bounds-check the result. "Where cheating would pay" is nowhere, as the plan says (no stakes), so dropping replay costs nothing.

**FE-3. Per-turn ownership of the ball alone splits one collision across two simulators.** D28/§1.7 says "the current shooter's client with ownership handed per turn", and §1.7 lists "bowling pins" as server-owned. Network ownership is per assembly; if the shooter owns the ball and the server owns the pins, the shooter's client computes the ball's bounce off pins whose motion it only receives from the server, and the server knocks the pins over when the replicated ball arrives, so the two sides disagree and both see jitter. S13 must test the "all table parts to the shooter for the turn, back to the server at rest" variant explicitly; the plan's text does not name it.

**FE-4. Studio's device emulator does not measure frame rate.** S17's pass bar is "30 fps on a mid phone in Studio's device emulator". The emulator changes resolution, DPI, safe areas and input, not GPU or CPU performance, and the Mac keeps rendering at its own speed. It also cannot show the quality-level downgrades a real phone applies (Future lighting falls back to ShadowMap/Voxel on low quality levels, which changes how 300 `PointLight`s look and cost). The mobile lighting budget has to be measured on a device (W7 #3 is the only place a device appears). Rewrite S17's pass as "60 fps on the Mac at quality 10 and at quality 3-4 (ShadowMap/Voxel), with the lamp look still reading at the low level", and defer the phone number to W7.

**FE-5. `ProcessReceipt` is almost right; two semantics are missing.** (a) The design never names `Enum.ProductPurchaseDecision.NotProcessedYet`. It must be returned whenever the profile is locked, loading or unavailable, so Roblox retries (including on the player's next join); the `Economy` suite's "a receipt during a profile lock is retried, not lost" implies it but D26 and `Economy/Store` should state it. (b) "appended to the profile's ledger inside ProcessReceipt before PurchaseGranted is returned" is only durable if the ledger write itself is an immediate `UpdateAsync`, not the profile's periodic autosave; otherwise a server crash between the return and the next autosave is a granted-but-lost purchase. (c) CI DataStore writes from Luau Execution (S15, `Persistence`) hit the live universe's stores, because the CI place shares the universe; test keys need their own scope or key prefix and a cleanup, or a test player ID range. (d) The DataStore request budget at 49 players (60 + 10 x players per minute per request type) is ample for 30-second autosaves; say so once so nobody adds per-action saves.

**FE-6. "Appearance properties scripts can set, not tinting" is being satisfied with a tint technique.** D22's skin path is `MeshPart.Color` showing through transparent texels of the outfit texture, the same mechanism D22 removed for the accents because the owner said "not tinting". `MeshPart.Color` is indeed the property Roblox's own `BodyColors` drives, so the plan's reading may be right, but the plan commits the shared UV layout and every outfit texture to transparent skin texels from the W3-W4 art slots while item 37 is still open. If the owner says "no", the fallback is eight skin textures per body type per outfit (the texture count multiplies by eight). Ask item 37 at G0, not before W1 art, and show one rendered example of the part-colour skin so the owner answers on evidence. Two smaller points: "nearest of 8 tones" quantises the player's skin, which the owner may read as not their colour; and a transparent-texel skin on a `LoadAsset` body needs S8(e) to pass, which is correctly in W0.

**FE-7. Roblox has no runtime audio synthesis.** Addendum B3 asks for "procedurally generated or in-engine synthesised sound (lounge two's ambient loop, UI blips)". The Audio API offers players, emitters, faders, filters, echo, reverb, chorus, flanger, distortion, pitch shift, compressor and analyser, but no oscillator or sample generator; nothing can synthesise a tone from code. D24's "runtime layering of library pads, else one uploaded loop" is the correct answer, and UI blips must come from the library or from uploads too. The plan should say this once, count the uploads against B3's 40 (RQ-1), and stop risk 20 from saying "at most 10 signature uploads" as if that were the budget.

**FE-8. The 49 cap after Addendum B4.** B4 says the place stays at Roblox's 50 and the ladder kicks the 50th arrival before any body is assigned. Two platform facts matter. (a) `Players.MaxPlayers` in the place file is used by Studio tests only; the live value comes from the Creator Hub place settings, so inv 20 and `Cap49`'s "the project file says MaxPlayers = 49" prove nothing about live servers. (b) If the live value stays 50, matchmaking will keep routing the 50th player into a server that has one free slot, and that player is kicked on arrival (after loading the place), then routed again; "server fill: Maximum" makes this worse because a 49-player server looks like the best fill target. The polite kick is a safety net, not a mechanism. The plan must either keep OS-0's one-minute Creator Hub change as a hard precondition of the FRB (the owner can do it; PROJECT_IDS says so) and add the B4 kick as the net, or accept the kick-loop and say so. `Cap49` must flip from "no code path refuses a join below 49" to "the 50th arrival is kicked before any body is assigned and never counts toward population", and the W7 exit's "a 49th join that works while a 50th waits" is not what Roblox does.

**FE-9. Street lighting: the risk is the lighting technology, not the light count.** Non-shadow `PointLight`s within a 180-st radius (say 40-80 at night including every porch light) are cheap on desktop; the flicker on 7 % of lamps is a few dozen property writes a frame. The real variables are Future lighting on mid-range phones (auto-downgraded, see FE-4) and the Skyline emissive heads as `Persistent` parts: several hundred lamps, a porch light per house and a shop front per business is roughly 500-700 Persistent Neon parts, which is fine for memory but is replicated to every client at join; keep them as single parts, not Models. SLIM impostors would not carry emissive glow, so the plan's choice of Neon heads rather than SLIM for the drone's lamplit view is correct.

**FE-10. First person on custom R15 bodies and in welded vehicles.** The default camera's first-person mode (zoom to the head, local transparency on the character's parts) depends on a Humanoid with standard part names, which the plan's custom bodies keep; so §14's toggle is free as D27 says. Inside a kinematic vehicle the body is **welded** to the seat rather than seated, so `CameraSubject` stays the Humanoid (a `VehicleSeat` would switch the subject to the seat); the camera popper will try to pop in front of interior geometry unless the interior is in a `CameraBlocker`-excluded collision group. S14 covers this; it should name the collision-group rule as a pass condition.

**FE-11. Invariant 20's literal scan is unenforceable.** "no '50' anywhere in `src/` or `data/`" would fail on `infection.criticalTown = 50`, `rodent.baton = 50`, `fetchTimeout = 45`'s neighbours (`150` ms rewind, `500` st LOD, `1500` Power), `matchSecs = 480` and every coordinate. Replace it with a scan for `MaxPlayers` and `maxPlayers` assignments only.

**FE-12. Luau Execution task budget.** `SimFull` at the W3c population plus a 16-body match plus fender benders inside one five-minute task is plausible only if the measured window shrinks (the plan allows 3 simulated minutes); say which numbers are produced at which window so a shrunk run is not read as a regression. Minor.

### 2.3 Contradictions inside the plan (CT)

**CT-1. §1.5's floor totals do not equal their rows, and the "57 humans served" claim is wrong.** Rows (FRB / from W3c): street 8/8 (hard cap 4/4), shop "all" = 6/12 (hard cap 4/8), hospital 10/10, ambulance crew 2/2, police 6/6 "plus the guard and the car crew" (3 bodies), attraction 0/5 (the row says guards 2, bartenders 2, receptionist 1, the rest 0). Sum, normal: 35 / 46 (the table says 26 / 37); hard cap: 29 / 38 (the table says 22 / 33). The stated totals omit the shop floor and the guard-and-crew bodies entirely and count 11 attraction bodies where the row says 5. The text then computes "90 − 33 = 57 human players can be served, more than the 49 the server holds, so a join is never refused inside the 49". With the rows' own hard-cap floors it is 90 − 44 = 46 < 49, so invariant 11 ("hard cap − hard-cap floors ≥ 49") fails on the plan's own data, and brief §4's "staffed and walked regardless of player count" does not hold at a 49-player fill unless street, shop and attraction floors are cut (which the plan permits but never says happens at fill). The worst case paragraph ("71 before a single shop worker ... about 85-95") is consistent with a needed hard cap of about 95, not 90. Fix: recompute the table, state the hard cap as "49 + every floor kept at fill" (about 93-96 at the W3c posts), or state which floors go dark at fill and reflect that in M9 and in brief row 4-6.

**CT-2. D33's regen defaults make the brief's drain meaningless.** `rodent.drainPerDay = 1 hp` per 72-second in-game day. `regenStalk = 0.25 hp/s` is 18 hp per day while sneaking; `regenHollow = 1 hp/s` is 72 hp per day while resting. D33 states the opposite: "re-tuned so the drain and the heals are the main recovery paths". With these numbers a rodent that sneaks for four seconds a day never drains, and the bite heals (10 and 20) are a rounding error against a minute in a hollow. The brief wants a rodent that must bite to stay alive. Options that honour both brief sentences: regen only while the rodent has bitten within the last N in-game days (drain and regen mutually exclusive), regen capped at a few hp per in-game day, or regen values two orders smaller (0.005 hp/s stalking, 0.02 hp/s in a hollow, so a kick's worth takes real time). FRB R7 ("about a minute for a kick's worth in a hollow") and R9 ("5 days without biting -> health down about 5") cannot both be true unless the rodent stands outside hollows and never sneaks for those five days.

**CT-3. FRB R2 contradicts §14, `CameraRig` and item 39.** R2: "Hold the right mouse button -> first-person stalk, slow and quiet, with an aim arc." `CameraRig`: "the rodent's stalk as an over-shoulder third-person stalk by default". If the owner never answers item 39, the FRB ships the default and the checklist tells him to expect first person. Rewrite R2 to the default and add the aim guide to it (VD-9).

**CT-4. Rule 2 / invariant 13 versus §3.15.** Rule 2 forbids any ladder number outside `Ladder.luau` and inv 13 scans `data/` for them; §3.15's `reputation/rules.json` carries `"humanScore": { "wReputation": 0.6, "wEntourage": 3.0 }`, the same two weights as `Ladder.params.w`, with the comment "read by Ladder.params, not restated". It is restated, and the scan would fail. Likewise `wages.json` carries `aiStaffSpeedMult: 0.7` next to Tunables `hospital.aiStaffSpeedMult`. Remove the copies.

**CT-5. The human-queue weights contradict the brief's statement about money.** Brief §13a: "Money's main use is buying your place in the human queue" and "Queue rank = money plus reputation". `Ladder.params.w = { time = 1.0, money = 0.02, reputation = 0.6, entourage = 3.0, kick = 15, quest = 1.0 }` with money in Spicy Dollars and time in active minutes: a 25 R$ purchase (100 S$) is worth 2 points, i.e. two minutes of standing in the street; the whole reputation range (−100..100) is worth at most 60 points; after one hour of play, time (60) outweighs any purchase a sane player would make, and one kick (15) outweighs 750 S$. These are tunables, but they are the defaults the FRB and the G1 economy curve will be judged on, and they say money barely matters, which is not what the owner wrote. Either reweight (money and reputation dominant, time a tie-breaker, as §13a reads) or put the question to the owner with the curve.

**CT-6. Decision 15's temporary eighth squirrel slot versus brief §5's hard "7 regular squirrels".** `extraSlot = true` on the hospital-kill row lets an eighth player hold a squirrel body when all seven slots are full. The total stays at 49, but "7 regular squirrels, hard" is a stated composition. Either drop `extraSlot` (the killer waits for the next opening with priority) or list it as a deviation.

**CT-7. Owner-time accounting disagrees with itself.** See SQ-3: §0 item 1 (5 min web) versus §0's table and §4.2 (17 min web + 2 min Studio); §0's table versus §4.14 and §6.6 (G2 approvals, the +20 min walk); the §0 total "about 10.5-11.5 hours" versus the sum of the plan's own sessions once the omissions are added (about 10.6 hours before SQ-1's Studio spikes).

**CT-8. OS-0 versus PROJECT_IDS.md.** The CI and Art Inbox places exist (IDs and "Luau Execution OK" recorded today), yet OS-0 schedules creating them and dec 2 still says "added in Step 0". The fixed facts list a key scope (universe-places write) that is refused and a problem (luau-execution scope) that is solved.

**CT-9. Decision 27 is reversed without a deviation row.** §15 accepts every unnamed default, and dec 27's revision-2 default was "no saving across servers". D26 reverses it ("dec 27 reversed") on the strength of §13a's Robux products and "kept permanently" garb. The inference is sound (an unsaved Robux purchase is a chargeback), but a reversed accepted default belongs in §2.1 as a declared deviation the owner sees, with the scope spelled out (wallet, receipts, wardrobe, **item inventory**, **reputation**, lifetime stats, possibly the water-gun flag). Item 41 asks only about reputation; the inventory and stats are added silently (§1.1 rule 12 lists neither; §3.20 has both).

**CT-10. §1.1 rule 12 versus §3.20.** Rule 12: the profile holds the wallet, purchases and receipts, the wardrobe and reputation. §3.20 adds `inventory`, `waterGunStunUsed` and `stats`. Make one list.

**CT-11. Invariant 20's "no 50 anywhere" is unenforceable** (FE-11).

**CT-12. FRB M9 versus the FRB population column** (SQ-7).

**CT-13. Numbering and cross-references in §4.1 and §4.8** (SQ-10).

**CT-14. §4.6 World says "greybox lamp posts (unlit)" in the FRB while W2's exit and §0 item 4 do not mention lamps at all; fine, but §0 item 5 then says "grey street lamps that really light up" arrive in W3/W4, and D30 says W3a; consistent. No action.** (Listed so the reviewer's pass over §0 is complete.)

**CT-15. D22 says "no tint zones" and "skin texels transparent so the body-part colour shows" in the same row** (FE-6). The second is a tint zone by another name; the plan should say so plainly and own the reading.

**CT-16. The brief's own 43 versus 49.** §13a says "Humans are 35 of the 43 player slots" and §5 says 49. The plan reads 43 as 35 + 7 + 1 and says so in §1.5 and §3.7. That is the only arithmetic that works, so it is the right call; but it is an owner-text inconsistency the plan resolves silently, and it belongs in §8 as a one-line confirmation next to item 43 rather than only in a code comment.

**CT-17. Addendum B4 versus §1.5, inv 20, `Cap49`, OS-0 and the W7 exit** (FE-8). Every one of those says the opposite of B4 ("Roblox itself makes late joiners wait", "the 50th join is refused by MaxPlayers, not by us", "no code path refuses a join below 49", "a 49th join that works while a 50th waits").

### 2.4 v5.4 behaviours the plan drops or changes without a row (VD)

§4.15 promises "nothing is dropped by omission". These are omitted.

**VD-1. The idle predator (squirrel_abilities §19) and, with it, any AFK rule.** v5.4 ends a run after 780 s without movement ("caught by an eagle / cat / snake / alligator / hospital guard" by place). It is not in §4.15, and the plan has no idle or AFK handling anywhere (no match for AFK, idle or inactivity outside the Power fade). On a 49-player server with a single rodent slot that "everyone wants", an AFK rodent (or AFK squirrel, deer or fox) holds the slot until they disconnect. The actor model makes the fix nearly free: after N minutes without input, release the body to its brain and drop the player to human at lowest rank (or to the flyover). Port the predator flavour text if the owner likes it; the rule is the point.

**VD-2. The Power HUD's fade countdown.** v5.4's top panel shows "NEXT POWER FADE mm:ss" (`refreshPowerUI`, squirrel_abilities §21.1). The brief says "keep Power exactly as v5.4 implements it" and "keep it as the rodent's visible status meter". §1.4 `UI/*` lists the Power meter and the three labels only. Add the countdown (it also makes the active-play clock visible to the owner in the FRB).

**VD-3. Squirrel Coins per bite and the fashion-stand unlock gate.** v5.4 pays +10 coins per successful bite (human, officer or squirrel) and unlocks the sewer fashion stand at 150 lifetime coins (squirrel_abilities §14-§15). Dec 20 says "coins become Spicy Dollars"; the plan converts the Galleria pickups and reprices the stand in cents or nut crumbs, but the per-bite income and the 150-coin gate disappear with no row. A rodent or squirrel player now has no stated income except nut crumbs; the stand's unlock condition is unstated.

**VD-4. The chili rush is retuned, not just rescoped.** v5.4: +30 s per pepper, capped at 90 s, speed x1.6 on ground and rail (not while stalking), pounce x1.12, leap 18.5 instead of 16.5, gait x1.14, eye emissive 1.65 (squirrel_abilities §12). Plan: `chiliRushSecs = 12`, `chiliRushSpeed = 1.25`, no stacking, no pounce or leap terms, and no `src`. The owner asked only that the rush be rodent-only. Port the numbers and cite them.

**VD-5. Hospital occupants' 14-second immunity after a bite** (`nextBite = 14`, hospital_police §5.5). Superseded in spirit by the alert zones, but not listed as replaced.

**VD-6. The decaying infection score** (0.66 per minute, hospital_police §6.3) is replaced by per-actor infection (dec 11). Correct, but it should be a Drop row with the reason.

**VD-7. HUD layout presets, pause, the graphics panel, the voice toggle and the "How to play" panel.** Pause cannot exist on a server and the graphics panel is Roblox's own, which is fine, but v5.4's hints and help text are the only control reference the game has, and the plan's control set (squirrel rails, forks, stalk, pounce, feint, stink, vehicles, drone, items, taunt, vote, minigames with fixed labyrinth keys) is far larger. No wave builds a controls or help screen; W7 #3 only maps bindings. Add a help panel per role to W2's HUD work.

**VD-8. The perfect counter and pounce immunity** are dropped by dec 12 and documented; listed for completeness.

**VD-9. The stalk aim guide** (the simulated pounce arc with a landing ring, `updateAimPath`) exists only in the stale FRB R2 line. With the over-shoulder default it must be re-specified (where the arc is drawn from, whether it survives in third person). Not in §4.15 or Tunables.

**VD-10. The stalk noise rule and the trunk exclusion.** v5.4: humans detect noise only above 2.5 u/s while stalking versus 4.7 otherwise, so a stalker is silent; stalk is never allowed on trunks (squirrel_abilities §5). `Perception.spotted` is golden-tested, which may carry the noise thresholds implicitly, but the plan never names them and the trunk exclusion is not stated.

**VD-11. The +150 elevated-bite rule's absolute Y > 4** is changed to height above ground (item 43). Flagged, not silent; listed because the table says "verbatim".

**VD-12. Motorcycle rider bites always succeed** (contact 2.0, dy up to 3.2; traffic §5.12). The plan keeps the crash and the fatal-fleet box but not the guaranteed-success contact numbers.

**VD-13. The single upper-gallery gold coin** (Gold dropped): becomes a brass coin or vanishes; unstated. Trivial.

**VD-14. The legacy decorative ambulance** is dropped with a row (D-18). Correct.

### 2.5 Requirements left PARTIAL or MISSING, with the smallest fix (RQ)

| # | Requirement | Status | Smallest fix |
|---|---|---|---|
| RQ-1 | Addendum B3 audio budget (AD-5) | MISSING | D24: budget 40 uploads a month (50 if needed), tally in `docs/AUDIO_BUDGET.md` from W0, batch by month, library and layered pads first; risk 20 corrected; list the planned uploads (rodent hiss and bite, chili rush, stink gland, outbreak music, paintball fire and hit, lounge-two loop, drone rotor) and their count |
| RQ-2 | Addendum B4 cap enforcement (AD-6) | MISSING | §1.5 and `Cap49` rewritten per FE-8; Creator Hub 49 stays a hard FRB precondition; the kick path added to `RoleService.onJoin` as the net |
| RQ-3 | Blender for all prop assets (2-2) | PARTIAL | one line in §2.1: wires as Beams, signs as SurfaceGui text, Skyline massing as Parts and the ground as Terrain are permanent non-Blender geometry |
| RQ-4 | Staffing regardless of player count (4-6, 5-3) | PARTIAL | CT-1 |
| RQ-5 | Limited server count (5-5) | PARTIAL | platform LIMIT; nothing to fix beyond saying it (done) |
| RQ-6 | Hospital kill -> squirrel with an 8th slot (6-10) | PARTIAL | CT-6 |
| RQ-7 | Stalk as in v5.4; animals third person (8-1, 14-1) | PARTIAL | CT-3, VD-9, VD-10; ask item 39 at G0 |
| RQ-8 | Rabid deer (8-7) | PARTIAL | item 40; give "accelerating the collapse" a mechanism (a rabid deer's charge infects or knocks down, and knocked-down humans are easier bites) or say the deer is visual only |
| RQ-9 | Drain, heals, regen (8-17) | PARTIAL | CT-2 |
| RQ-10 | Appearance properties, not tinting (13a-5) | PARTIAL | FE-6; ask item 37 at G0 with a render |
| RQ-11 | Votes to anyone (13a-21) | PARTIAL | item 44 lists Q21; if NPCs may be voted on, `ReputationRules` needs an NPC-side value, which the `Companion` liking already is |
| RQ-12 | Money buys the human queue (13a-31) | PARTIAL | CT-5 |
| RQ-13 | A very specific barber shop (13a-36) | PARTIAL | ask the owner for the specifics before W3b, or build the default and label it |
| RQ-14 | Fortune machine reels (13a-74) | PARTIAL | item 44 (Q20) as written; fine once the owner answers |
| RQ-15 | Procedurally generated ambient loop (13a-108) | PARTIAL | FE-7 |
| RQ-16 | Power kept exactly (15-12, PT-2) | PARTIAL | VD-2, VD-3, item 43 |
| RQ-17 | Coins become Spicy Dollars (15-14) | PARTIAL | VD-3 |
| RQ-18 | Chili rush rodent-only (15-15) | PARTIAL | VD-4 |
| RQ-19 | Otherwise only police drive (15-32) | PARTIAL | item 44 (Q8) as written |
| RQ-20 | Human sprint stamina (implied by soda and ice cream, 13a-56, 13a-57) | not a brief line; a gap | `Controllers/Human` has sprint but no stamina; define a human stamina tunable or make the consumables do something else |

### 2.6 Does the FRB still make every role test-playable?

Yes. Each of the eight roles keeps a Lab entry and a thinnest loop in §4.7, and the multi-client set covers the role interactions the brief cares about (M1-M11). Three caveats: the rodent's R2 describes the wrong camera (CT-3); M9 cannot pass as written (SQ-7); and the FRB's size is understated (SQ-9), which is the realistic threat to "first runnable" rather than any missing role.

### 2.7 Owner time, recomputed from the plan's own sessions

| Window | Plan §0 table | Plan §4.14 / §6.6 | This review |
|---|---|---|---|
| Step 0 | 20 chat + 17 web + 2 Studio | same | 20 + 12 web (places exist) + 2 |
| W0 | 20 + 10 + 10 + 10 | same | + 40-60 Studio for S13, S14, S15, S17 (SQ-1) |
| W2 | 60-90 | same | same |
| W3 | 30 web + 20 Studio | + 4 x 10 G2 approvals across W3-W5 | same as §4.14 |
| End W4 | 60 + 60 | same | OS-5 realistically 120-180 (SQ-3); OS-5b 60 |
| W4b | 90 | 90 + 20 | 110 |
| W5 | 15 + 15 + 25 | same | same |
| W6 | 30 | same | same |
| W7 | 60-75 | same | same |
| **Total** | about 9.6 h (sum of the table) | about 10.6 h | **about 12-13 h** before fallbacks; 2 h in one window at the end of W4 |

---

## 3. What revision 4 should change (in priority order)

1. Recompute §1.5's floor table; set the hard cap to "49 players + every floor kept at fill" or state which floors go dark at fill; fix invariant 11's expectation, M9 and brief row 4-6 (CT-1, SQ-7).
2. Make the drain matter: regen and drain mutually exclusive, or regen two orders smaller; fix FRB R7/R9 to match (CT-2).
3. Give the physics spikes and suites a venue: one more W0 Studio sitting (S13, S14, S15, S17 scripts), the `Minigames` stability tests moved to a Lab-driven private-server run, and S17's phone number deferred to a device in W7 (SQ-1, FE-1, FE-4).
4. Drop replay validation; pick server-owned or whole-table-to-shooter authority per game in S13 (FE-2, FE-3).
5. Decide the paintball venue at G-PB from a published private-server profile, not at G0 (SQ-4).
6. Absorb Addendum B3 and B4 (RQ-1, RQ-2, FE-8, CT-17) and correct OS-0 and the fixed facts against PROJECT_IDS.md (CT-8).
7. Add an AFK release rule and the Power fade countdown; port the chili rush numbers and the per-bite coin income or write their Drop rows (VD-1 to VD-4).
8. Fix FRB R2, the §3.15 weight copies, invariant 20, rule 12 versus §3.20, the §4.1 cross-references and the §4.8 numbering (CT-3, CT-4, CT-10, CT-11, CT-13).
9. Reweight or question the human-queue formula so money and reputation mean what the owner wrote (CT-5); list the dec 27 reversal and the eighth squirrel slot as deviations (CT-9, CT-6).
10. Split W3c by the W4b order and W3a into two exits; size W2 honestly; restate owner time at about 12-13 hours with the end-of-W4 block split into three sittings (SQ-2, SQ-5, SQ-9, SQ-3).

## 4. Mechanical count of the inventory

The counts in the verdict and §1.14 are produced by counting status cells in the tables of section 1 (`| COVERED |`, `| PARTIAL |`, `| MISSING |`), excluding the RQ table in §2.5.
