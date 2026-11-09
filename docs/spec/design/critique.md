# Adversarial review of `spec/BUILD_PLAN.md`

Date: 2026-11-09. Reviewer lens: requirement coverage, sequencing, feasibility, and v5.4 behaviour that the plan silently drops.

**Inputs read.** `reference/Roblox_Rebuild_Brief.txt` (authoritative), `spec/BRIEF_ADDENDUM.md` (wins over the brief), `spec/roblox_feasibility.md`, `spec/PROJECT_IDS.md`, the eight subsystem specs (summaries, Brief deltas, Porting notes, Open questions and "Added by verifier" sections, plus details where needed), the seven data files in `spec/data/` (all present), and the owner decisions in the task context. The three proposals in `spec/design/` were consulted only to check which of their safeguards the plan did not adopt. **No listed file is missing.**

**Citation style.** "Plan §n" = a section of `BUILD_PLAN.md`; "Dn" = its key decision n; "Sn" = its spike n; "OS-n" = its owner session n; "dec n" = its owner decision n (plan §8); "inv n" = compiler invariant n (plan §3.13); "W n" = wave n.

## Verdict in one screen

The plan is strong on the brief's hardest rules: one actor model with possession as the only handoff (plan §1.5, D1, S2), the ladder in one module (plan §3.7), every role in the first runnable build with click-by-click checks (plan §4.6-4.7), a data-driven town (plan §3.2-3.4, §3.13), and the Open Cloud and Studio split (D12, D15). Most of the brief is covered.

The problems that matter most before the owner commits are these:

1. **Body and slot arithmetic does not add up (S-9).** The plan treats the brief's "35 humans" as 35 townsperson slots plus 5 hospital plus up to 8 police, which gives 48 human-species player slots. Against that it has about 50 human bodies, of which only 28 are civilians, and its fallback trims to 42. At full occupancy the shops, streets and staff would be almost entirely player-held. That breaks brief §4 ("staffed and walked regardless of player count"). The plan also never says what happens when a player joins and the human rung is full.
2. **The CI and Art Inbox places are created too late (S-1).** The owner creates them in OS-1, at the *end* of W0, but W0's spikes S1 and S4-S9 need a place to run Luau Execution against, and S1 names the CI place explicitly.
3. **The art pipeline assumes runtime SurfaceAppearance tinting that nobody has verified (F-1, F-2).** The 70/30 blend relies on runtime TintMask tinting of SurfaceAppearance, and the role outfits rely on per-role SurfaceAppearance texture sets. The feasibility doc says most SurfaceAppearance properties cannot be changed by script and that each MeshPart takes one SurfaceAppearance. No spike tests either path. Getting outfits for about 13 roles onto 6 body types would also add many unbudgeted owner imports.
4. **The drone's whole-town view is tested last (S-5).** The plan rejected risk-first's published-server far-view spike, along with its "does streamed-out terrain render" and `ReplicationFocus` checks. The plan's own scoring criticises risk-first on exactly this point. SLIM is enabled only in W7, yet W6 checks it, and terrain at boot grows with the W6 backdrop, which S6 never measures.
5. **Cross-track dependencies are hidden (S-2, S-3, S-4).** W4 (Track A) needs W3's 40 interiors, defender houses, isolation ward and town-wide traffic control. W2's 8-room hospital greybox is WorldGen work handed to Track A. The harvested-exact routes (D8) carry known v5.4 bugs and conflict with fixing the outer homes so they face the road (inv 2). Template routes arrive only in W3.
6. **v5.4 behaviour is quietly dropped.** This includes the novelty cast (mime and kid cyclists), motorcyclists, living events, crime-scene bystanders, cat swats and dog barks, garden and hedge concealment, river-fall recovery, the trampoline and the hatch ambush. The chili hunt, the fashion stand and the Galleria coins are kept by dec 20, but no wave builds them.

Counts (inventory below): **307 requirements; 277 covered, 28 partial, 2 missing.**

---

## 1. Requirement inventory

Status key: **COVERED** = the plan implements it in a named wave with a check; **PARTIAL** = present but incomplete, deferred to an undecided default, or contradicted elsewhere in the plan; **MISSING** = not in the plan.

### 1.1 Brief preamble and §1 Source of truth

| ID | Requirement | Status | Plan section | Note |
|---|---|---|---|---|
| P-1 | Build the whole game in one pass | COVERED | §4.1 | Step 0 plus W0-W7, nothing public before W7 |
| P-2 | No walkable-town-first milestone | COVERED | §4.1, §4.4, §9.3 | W1 has no owner build; spikes run on a tiny spike place |
| P-3 | Every role test-playable from the first runnable build | COVERED | §4.5-§4.7 | All 8 roles plus a multi-client set; roles are reached through the Lab (drone unlock path only in W4) |
| 1-1 | v5.4 HTML is canonical (SHA-256 pinned) | COVERED | W0 #3, §9.2 graft 24 | harvest checks the SHA |
| 1-2 | Retain the Bellwether Galleria (v5.3) | COVERED | §1.4 WorldGen `Galleria` builder; §3.1 data migration | mall mechanics are partial, see 3-7 |
| 1-3 | Retain apple trees (v5.4) | COVERED | W0 #3 (12 apple trees), W4 #5 | |
| 1-4 | Retain bird nests | COVERED | §3.12 wildlife, W4 #7 | |
| 1-5 | Retain town birds | COVERED | W4 #7 | client-only ambient life |
| 1-6 | Retain silent overflights | COVERED | W4 #7 | made world-relative |
| 1-7 | Retain heavy vehicles | COVERED | §4.6 Bodies | |
| 1-8 | Retain fatal traffic | COVERED | D9, S4 | |
| 1-9 | HTML is the reference for layout, routes, lanes, districts and mechanics | COVERED | D8, §6.3 golden vectors | |
| 1-10 | From-scratch Luau rewrite, not a transpile | COVERED | §0, §6.3 | |
| 1-11 | Restore nut caches | COVERED | W2 #7, §3.12 (cache 4 moved) | |
| 1-12 | Restore deer | COVERED | W2 #8, §4.7 E1-E3 | |
| 1-13 | Restore foxes | COVERED | W2 #8, §4.7 F1-F5 | |
| 1-14 | Restore butterflies | COVERED | W4 #7 | not in the FRB (acceptable) |
| 1-15 | Restore garden insects | COVERED | W4 #7 (dragonflies, insects) | |

### 1.2 Brief §2 Toolchain and repository

| ID | Requirement | Status | Plan section | Note |
|---|---|---|---|---|
| 2-1 | Rojo project under git, one repo | COVERED | §1.2 | |
| 2-2 | Studio syncs from the filesystem; no zip handoffs | PARTIAL | D15, §1.2 | Open Cloud saves replace the filesystem sync and the Rojo plugin becomes "optional". This meets the brief's intent (no zips) but is a deviation the owner should approve explicitly |
| 2-3 | Blender for all character and prop assets | COVERED | §5 | |
| 2-4 | Exported as FBX with animations | COVERED | §5.1 | one clip per FBX, as feasibility A5 requires |
| 2-5 | Clips imported through the Studio animation importer | PARTIAL | D11, S7 | deliberately replaced by Lune KeyframeSequence plus Open Cloud upload; the importer is only the fallback. Not listed as a brief deviation |
| 2-6 | One module per system, under Shared / Server / Client | PARTIAL | §1.2, §1.4 | WorldGen sits in `ServerStorage.WorldGen` and art in `ReplicatedStorage.Assets`, outside the three named roots. Harmless, but undeclared |
| 2-7 | WorldGen builds the town from data, never hand-placed parts | COVERED | §1.4 WorldGen, D6 | |
| 2-8 | Routes module (trees, poles, wires, rooftops) | COVERED | §1.4 `Routes/*` | |
| 2-9 | Traffic module (lanes, vehicles, yielding, swept collision) | COVERED | §1.4 `Traffic/*`, `Vehicles/*` | |
| 2-10 | Actors module (single actor model) | COVERED | §1.4, §1.5 | |
| 2-11 | Roles module (hierarchy, queue, promotion ladder) | COVERED | §3.7 | |
| 2-12 | Infection module (bite, spread, cure, win condition) | COVERED | §1.4 `Infection/*`, D17 | |
| 2-13 | Hospital, Police and Drone job systems | COVERED | §1.4 server table | |
| 2-14 | Seasons module (calendar, winter) | COVERED | `Time/*`, `Seasons/SeasonService` | |
| 2-15 | Foraging module (gardens, feeders, trash, hollows, nut meter) | COVERED | `Foraging/*` | |
| 2-16 | Wildlife module (fox, deer, birds, insects) | COVERED | `Wildlife/WildlifeService`, client `World/*` | |
| 2-17 | Town is a data file of lots (type, footprint, facing, params) | COVERED | §3.2 | |
| 2-18 | Adding a barber shop is a data entry | COVERED | §3.3 | |
| 2-19 | StreamingEnabled on | COVERED | §1.2 project properties | |
| 2-20 | Map several thousand studs end to end | COVERED | §4.6 (about 4,350 x 2,520 st) | |
| 2-21 | Scale: 1 HTML unit is about 2.5 studs | COVERED | `Config/Units`, D21 | |
| 2-22 | Squirrel about 1.2 st at the shoulder | COVERED | Tunables `shoulderHeight`, dec 8 | |
| 2-23 | Humans at standard R15 height | COVERED | §5.2, §5.3 | |

### 1.3 Brief §3 The world

| ID | Requirement | Status | Plan section | Note |
|---|---|---|---|---|
| 3-1 | Old town core: streets, sidewalks, houses, poles and wires, trees | COVERED | §4.6 World | |
| 3-2 | Hospital (west), expanded | COVERED | W2 #3, W3 #6 | |
| 3-3 | Police station, expanded | COVERED | §3.12, W3 #7 | |
| 3-4 | Riverside: stone arch bridge, cobbled quays, rooftops | COVERED | WorldGen `Quay`, W5 #7 | river-fall recovery is dropped (Section 4, D-7) |
| 3-5 | Galleria: six shops | COVERED | data migration (`mall_shop` x6) | |
| 3-6 | Galleria: upper gallery | COVERED | data migration (`mezzanine`) | implicit only |
| 3-7 | Galleria: coin fountain | PARTIAL | dec 20 | the fountain is built from data, but no wave implements coin pickup, the wish toss or the mall state machine (D-10) |
| 3-8 | Galleria: interior lighting | COVERED | W6 #4 | |
| 3-9 | Galleria: camera constraints | COVERED | W3 #8, `Camera/CameraRig` | |
| 3-10 | Sewer interiors | COVERED | W3 #8 | |
| 3-11 | Duct interiors | COVERED | W3 #6 | |
| 3-12 | House interiors | COVERED | W2 #9 (4), W3 #3 (40) | |
| 3-13 | Expansion added as data-driven lots | COVERED | §3.3, W3 #2 | |
| 3-14 | Restaurants roughly doubled | COVERED | inv 4 (at least 10) | the baseline is ambiguous: if the Quay taverns and tea rooms and the Galleria café count, 10 is not double |
| 3-15 | Restaurant mix: diner, pizza, taco, Chinese, café, bakery, ice cream, bar and grill | COVERED | inv 4, W3 #2 | |
| 3-16 | Each restaurant has outdoor seating or a back-alley dumpster | COVERED | inv 4 | |
| 3-17 | Barber shop | COVERED | inv 4, §3.3 | |
| 3-18 | Music store | COVERED | inv 4 | |
| 3-19 | Hardware store | COVERED | inv 4 | |
| 3-20 | Laundromat | COVERED | inv 4 | |
| 3-21 | Bookshop | COVERED | inv 4 | |
| 3-22 | Pet store | COVERED | inv 4 | |
| 3-23 | Gas station | COVERED | inv 4, W3 #2 | |
| 3-24 | Corner grocery | COVERED | inv 4 | |
| 3-25 | School with playground | COVERED | inv 4 | |
| 3-26 | Church | COVERED | inv 4 | |
| 3-27 | Park with gazebo | COVERED | inv 4 | exists in v5.4 |
| 3-28 | Community garden | COVERED | inv 4 | Tabasco garden |
| 3-29 | Small marina on the ocean side | COVERED | inv 4, W3 #2, W6 #1 | |
| 3-30 | At least 8 house models (bungalow, two-storey, Victorian, ranch, split-level, cottage, apartment block, large older house) | COVERED | §3.4 | |
| 3-31 | Every house has its own flair; no two read the same | PARTIAL | §3.4 flair rule | distinctness is enforced only within 120 u (at least 4 of 11 axes); the brief says no two, town-wide |
| 3-32 | Backyards with gardens, feeders, sheds, fences, dog houses | PARTIAL | §3.2 `yard` schema | supported by the schema, but no wave deliverable or invariant ensures houses get backyards (v5.4 has them on only 4 lots) |
| 3-33 | Each lot type defines what squirrels can forage there | COVERED | §3.3, inv 4 | |
| 3-34 | Each lot type defines how risky it is | COVERED | §3.3, inv 4 | |
| 3-35 | Backdrop holds up at altitude for the drone | PARTIAL | D5, W6, W7 #6 | not proven on a published server until W6; SLIM only in W7; far terrain under streaming not addressed (S-5) |
| 3-36 | Mountains falling to rolling hills and plains | COVERED | W6 #1 | |
| 3-37 | Tree line | COVERED | W6 #1 | |
| 3-38 | Distant road | COVERED | W6 #1 | |
| 3-39 | Fog layering | MISSING | (none) | the word "fog" never appears in the plan. Feasibility §f says layered fog needs authored silhouette or fog cards, because Atmosphere is one global layer. W6 has only "baked aerial perspective" and the P5 asset list has no fog cards |
| 3-40 | Ocean with a beach | COVERED | W6 #1 | |
| 3-41 | Pier | COVERED | W6 #1 | |
| 3-42 | Marina | COVERED | W6 #1 | |
| 3-43 | Horizon reads correctly from 300 st | COVERED | W6 exit, OS-7 | |
| 3-44 | Sky with a full day cycle | COVERED | D19, W6 #2 | |
| 3-45 | Sunrise and sunset as their own moments | COVERED | D19 day curve | |
| 3-46 | Clouds | COVERED | W6 #4 | |
| 3-47 | Silent overflights in the sky | COVERED | W4 #7 | |
| 3-48 | Beautiful night sky with stars | COVERED | W6 #2 | |
| 3-49 | Moon runs through real phases on the calendar (~29.5 days) | COVERED | W6 #3, `Time/Moon`, §6.2 | |
| 3-50 | Never a permanent full moon | COVERED | W6 exit | |
| 3-51 | Distant radio or cell tower with blinking red lights | COVERED | W6 #1 | |
| 3-52 | Tower silhouetted against the sunset | COVERED | W6 #1, OS-7, dec 25 | |
| 3-53 | 11 hollow trees across the town | COVERED | §3.5, inv 5 | |
| 3-54 | Each one a claimable territory with a nut meter | COVERED | §3.5, W2 #7 | |
| 3-55 | Two premium trees with an interior pathway up the centre of the trunk | COVERED | §5.5, W3 #4 | |
| 3-56 | Premium chambers at several heights | COVERED | §3.5, §5.5 | |
| 3-57 | Premium trees next to the best gardens and feeders | COVERED | inv 5 (within 40 u) | |
| 3-58 | Nine trees with a single chamber reached from a knothole | COVERED | §5.5 | |

### 1.4 Brief §4 Actor model and §5 Population

| ID | Requirement | Status | Plan section | Note |
|---|---|---|---|---|
| 4-1 | No code distinction between player character and NPC | COVERED | §1.1 rule 1 | |
| 4-2 | One actor kind per species (human, squirrel, fox, deer) | COVERED | §1.1, `Actors/Species` | rodent = squirrel with `Variant = "spicy"` |
| 4-3 | The only question is AI brain or player controller | COVERED | §1.5 | |
| 4-4 | Every human and squirrel is AI-driven by default | COVERED | §1.5 Join | |
| 4-5 | A joining player takes over an existing actor mid-stride | COVERED | D1, S2, M1 | |
| 4-6 | A leaving player hands control back; the AI carries on | COVERED | §1.5 Release, M2 | |
| 4-7 | Promotion is the same handoff | COVERED | §1.5 Swap | |
| 4-8 | One mechanism implements the queue, backfill, role switching and session reset | COVERED | §1.1 rule 1, §1.5 | |
| 4-9 | More human bodies than the 35 player slots; staff and streets kept staffed regardless of player count | PARTIAL | §1.5, §3.7, §4.6 | about 50 bodies (fallback 42) against 48 human-species player slots; only 28 civilian bodies for 35 townsperson slots; overflow join undefined (S-9) |
| 5-1 | Max players 50 | COVERED | already set; W7 #7 | W7 #7 re-lists a setting the owner already made |
| 5-2 | Target 35 humans, 7 squirrels, 1 spicy rodent | PARTIAL | §3.7 | the Ladder makes 35 the *townsperson* count and adds 5 + 8 tier-2 slots. Brief arithmetic (35 + 7 + 1 = 43, leaving room for deer and fox inside 50) is lost: the plan's slots total 61 |
| 5-3 | Any slot not held by a player is AI | COVERED | §1.5, §4.6 | |
| 5-4 | Squirrel population floats 10-14 | COVERED | §3.7 `bodies` | what makes it "float" is not stated (minor) |
| 5-5 | Deer: several voluntary slots | COVERED | §3.7 `sideExits`, dec 16 (4) | |
| 5-6 | Fox: one slot, Easter egg | COVERED | §3.7 (`hidden = true`) | |
| 5-7 | Limited server count so a real queue exists | PARTIAL | dec 26, risk 16 | Roblox cannot cap the server count; "server fill: Maximum" is the right mitigation, but the requirement cannot be met as written. Say so to the owner |

### 1.5 Brief §6 Roles and the promotion ladder

| ID | Requirement | Status | Plan section | Note |
|---|---|---|---|---|
| 6-1 | The ladder is stated in one place (`Roles`) and nowhere else | PARTIAL | §3.7, §3.8, §3.9 | ladder numbers also live in Tunables (`roles.w`, `kickEvent`, `offerTimeout`, `infection.killerHospitalIf`, `rodent.respawnDelay`) and in quest JSON (`reward.rank`); `PoliceService.unlockSlot` executes it. That is defensible, but it is the drift the brief forbids. Keep ladder parameters in `Ladder.luau` or declare Tunables as the Ladder's single parameter block |
| 6-2 | Human: walks, earns credits by working, can be bitten | COVERED | §4.7 H1-H7 | |
| 6-3 | Hospital staff: 5 player slots | COVERED | §3.7 | |
| 6-4 | Police: 5 slots, expandable to 8 | COVERED | §3.7, W4 #2 | |
| 6-5 | Hospital ranks slightly above police; privileges nearly equal | COVERED | §3.7 `prestige` | |
| 6-6 | Regular squirrel: 7 slots; forages, stores nuts, claims a hollow | COVERED | §3.7, W2 #7 | |
| 6-7 | Spicy rodent: 1 slot | COVERED | §3.7 | |
| 6-8 | Human base rank = time playing on this server, modified by job credits | COVERED | `Ladder.score` | |
| 6-9 | Squirrel rank = 90 % nuts + 10 % momentary stink % | COVERED | `Ladder.score` | "nuts" (stored, carried or lifetime) is undefined (minor) |
| 6-10 | The highest-ranked squirrel becomes the next spicy rodent when the slot opens | COVERED | §3.7 `slot.open`, M7 | order against the 20 s AI-rodent refill not defined (S-10) |
| 6-11 | When the rodent dies, its player restarts as a lowest-level human | COVERED | §3.7, R5, R6 | |
| 6-12 | A human who kills the rodent goes to squirrel if a body is free, else police, or hospital if the rodent infected over 30 % | COVERED | §3.7 | uses town %, not "infected by this rodent" (minor) |
| 6-13 | Hospital staff who kill the rodent inside the hospital instantly become a squirrel | COVERED | §3.7, S5 check, dec 15 | |
| 6-14 | A regular squirrel cannot kill the rodent | COVERED | by design (no squirrel attack verb) | |
| 6-15 | An infected regular squirrel loses heavily and drops in the queue | COVERED | §3.7, Q8 | |
| 6-16 | Squirrels that die in winter restart as humans | COVERED | §3.7, M8 | |
| 6-17 | Deer and fox are side exits; leaving returns to the previous human rank | COVERED | §3.7, F5, E3 | |

### 1.6 Brief §7 Squirrel play

| ID | Requirement | Status | Plan section | Note |
|---|---|---|---|---|
| 7-1 | Port the route registry: curves, samples, kind, speed, surface radius, visualOffset | COVERED | D8, §3.5 | |
| 7-2 | Rail-based climbing | COVERED | `Routes/Motion`, S3 | |
| 7-3 | Free running on the ground | COVERED | `SquirrelMotor` | |
| 7-4 | Leaps between rails | COVERED | S3, Q2 | |
| 7-5 | Seven clips on a single rig (Run, Climb, Wire, Leap, Pounce, Bite dance, Sneak) | COVERED | §5.4 | |
| 7-6 | Fur that catches light | PARTIAL | §5.3, §5.6 | the groom normal map and fur cards are right, but headless procedural Blender cannot sculpt or judge look-dev (feasibility); depends on G2 and dec 23 |
| 7-7 | Muscle under the skin | PARTIAL | §5.6 | same limit as 7-6 |
| 7-8 | Tail lags the body | COVERED | §5.3 (8 tail bones plus spring) | |
| 7-9 | Weight and presence are a modelling and rigging requirement, not lighting | COVERED | §5.6 | |
| 7-10 | Replace the stacked-spheres placeholder entirely | COVERED | W5 must-replace list | |
| 7-11 | Forage source: gardens | COVERED | W2 #7, W4 #5 | |
| 7-12 | Forage source: bird feeders, risky because of birds and homeowners | PARTIAL | W4 #5 | birds are client-only closed-form visuals (§1.3), so the "bird risk" needs a server-side model; not specified |
| 7-13 | Trash cans and restaurant dumpsters | COVERED | W2 #7, W4 #5 | |
| 7-14 | Apple trees | COVERED | W4 #5 | |
| 7-15 | Mall plaza | COVERED | W4 #5 | |
| 7-16 | Nuts stored in a claimed hollow raise its meter | COVERED | Q4 | |
| 7-17 | Above 70 % the squirrel owns the tree; others cannot take its nuts | COVERED | `ForageRules`, W4 #5 theft rules | |
| 7-18 | Premium gardens and feeders raided about once per in-game week | COVERED | W4 #5, `Calendar.raidWeek` | |
| 7-19 | Stink gland: slow-filling meter, 10 % of rank | COVERED | Tunables `stinkFillPerMin` | |
| 7-20 | Fires only at 95 % or more | COVERED | Q5 | |
| 7-21 | Firing drops the meter by 30 | COVERED | Q5 | |
| 7-22 | Burst briefly repels foxes and humans | COVERED | Q5, F4 | |

### 1.7 Brief §8 Spicy rodent play

| ID | Requirement | Status | Plan section | Note |
|---|---|---|---|---|
| 8-1 | Stalk (hold), pounce, bite as in v5.4 | COVERED | R2-R3 | |
| 8-2 | Unaware people are easier | COVERED | `CombatRules.biteChance` | |
| 8-3 | Biting humans infects them | COVERED | W2 #2 | |
| 8-4 | Biting regular squirrels raises town-wide infection | COVERED | `InfectionRules.squirrelShare` | |
| 8-5 | Fatal traffic as a server-side swept test, not Touched | COVERED | D9 | |
| 8-6 | Being run over ends the rodent's run | COVERED | R6 | |
| 8-7 | Hidden win path: infecting hospital staff slows cures | COVERED | Tunables `infectedStaffCureMult` | |
| 8-8 | Critical mass of infection wins the session for the rodent | PARTIAL | D17, dec 11 | critical mass silently starts an "outbreak"; what the rodent player *wins* (reward, credit, end of session) is undefined |
| 8-9 | Do not surface the hidden win in the UI | COVERED | D17 | |
| 8-10 | Session resets when everyone is infected | COVERED | §1.5, §3.7 | |
| 8-11 | The duel is built as tunable systems | COVERED | `CombatRules`, Tunables | |
| 8-12 | Pounce has a wind-up, commit point and recovery | COVERED | W2 #1, R3 | |
| 8-13 | Biting during the reaction window lands; biting into a raised arm or kick does not | COVERED | dec 12, §6.2 | |
| 8-14 | Zig-zag raises miss chance but costs speed | COVERED | W4 #1 | |
| 8-15 | A straight sprint is fast and readable | COVERED | W4 #1 | |
| 8-16 | A feint forces an early flinch or swing | COVERED | W4 #1 | |
| 8-17 | Feints cost stamina; read correctly, they hand the human a free hit | COVERED | W4 #1 | |
| 8-18 | Humans flinch, swing, kick, back away or flee by awareness and nerve | COVERED | W4 #1 | |
| 8-19 | Vigilantes never flee | COVERED | W4 #1 | |
| 8-20 | Every show-off option carries a trade-off | COVERED | W4 #1 | |
| 8-21 | 8 % of all human actors are vigilantes at any moment | PARTIAL | W2 #5, Tunables | the flag sits on AI humans, with no rule that keeps 8 % as players possess and release bodies |
| 8-22 | Vigilantes move to kick on sighting | COVERED | W2 #5, W4 #1 | |
| 8-23 | Vigilantes answer the drone's call | COVERED | DR3 | |
| 8-24 | Rodent health meter | COVERED | W2 #1 | |
| 8-25 | A kick does not kill; about two kicks without recovery do | COVERED | Tunables, R5 | |
| 8-26 | Health regenerates while sneaking or resting in a hollow | COVERED | R7 | |
| 8-27 | Three defender houses burst out when the rodent chases someone inside | COVERED | inv 3, W3 #3, W4 #1 | |
| 8-28 | Two older housewives of different appearance with rolling pins; one man with a broom | COVERED | inv 3, §5.3 P1 | |
| 8-29 | Defender blows hit 50 % harder; one blow at low health kills | COVERED | Tunables `defenderMult`, §6.2 | |
| 8-30 | 40 houses with full interiors the rodent can burst into | COVERED | W3 #3, inv 3 | |
| 8-31 | Humans run inside and hide; escape or bite depends on the chase | COVERED | W3 #3, W4 #1 | the escape rule (locks, timers, back exit) is not decided (humans_actors Q4) |
| 8-32 | Interiors must actually run and be tested, not stubbed | COVERED | W3 exit, OS-5 | |
| 8-33 | The 40 houses are claimable homes | COVERED | `HomeService`, W3 #3 | |
| 8-34 | Each real day of play earns remodel points | PARTIAL | dec 22 | the default changes this to per real hour (well argued, but it deviates from the brief) |
| 8-35 | Remodels persist for the life of the server | COVERED | D14 | |

### 1.8 Brief §9 Hospital, §10 Police, §11 Wildlife

| ID | Requirement | Status | Plan section | Note |
|---|---|---|---|---|
| 9-1 | Reception | COVERED | W2 #3, S2 | |
| 9-2 | Triage | COVERED | W2 #3 | |
| 9-3 | Two wards | COVERED | W2 #3, W3 #6 | |
| 9-4 | Isolation ward | COVERED | W2 #3, W3 #6 | |
| 9-5 | Pharmacy | COVERED | W2 #3 | |
| 9-6 | Staff room | COVERED | W2 #3 | |
| 9-7 | Ambulance bay | COVERED | W3 #6 | |
| 9-8 | Roof access as a squirrel route | COVERED | W3 #5-#6 | |
| 9-9 | Infected humans are delivered or walk in | COVERED | W2 #2 (walk-in), W4 #3 (ambulance) | |
| 9-10 | Staff disinfect through a short interaction loop at stations | COVERED | S3 | |
| 9-11 | Hospital performance = speed of disinfection | COVERED | `HospitalService.performance` | |
| 9-12 | Good performance raises staff rank | COVERED | W4 #3 | |
| 9-13 | Good performance unlocks station upgrades | PARTIAL | W4 #3 | no upgrade catalogue, data file or effect is defined anywhere |
| 9-14 | Staff can kill the rodent inside the building | COVERED | S5 | |
| 9-15 | Infected staff cure slower | COVERED | S6 | |
| 10-1 | Five officer player slots at start | COVERED | §3.7 | |
| 10-2 | Officers pursue and can kill the rodent | COVERED | P3 | |
| 10-3 | Good performance unlocks officers one at a time up to 8 | PARTIAL | W4 #2 | the police performance metric is never defined |
| 10-4 | Later officers are more aggressive and better coordinated | PARTIAL | W4 #2 | there are aggression tiers, but "coordinated" (pursuit roles, cut-offs) is not designed |
| 10-5 | At 8 officers the next upgrade unlocks a drone for one pilot | COVERED | §3.7 `drone`, W4 #2 | |
| 10-6 | Full flight controls | COVERED | DR2 | |
| 10-7 | Camera feed | COVERED | DR1 | |
| 10-8 | Spot-and-mark reveals the rodent to officers for a short window | COVERED | DR3 | |
| 10-9 | The mark calls nearby vigilantes to the spot | COVERED | DR3 | |
| 10-10 | The drone as good as it can be (justifies the backdrop) | PARTIAL | W6 #5, W7 #6 | no early far-view spike; `ReplicationFocus` not used; SLIM late (S-5, F-13) |
| 11-1 | Fox: one player slot, Easter egg | COVERED | §3.7 | |
| 11-2 | Fox hunts regular squirrels | COVERED | W2 #8 | |
| 11-3 | Fox cannot harm the rodent | COVERED | F3 | |
| 11-4 | Fox is repelled by the stink gland | COVERED | F4 | |
| 11-5 | Deer: several slots; peaceful; wanders | COVERED | E1 | |
| 11-6 | Deer startled by traffic | COVERED | E2 | the check may be hard to trigger if no lane passes the north-park herd |
| 11-7 | Deer startled by the drone | COVERED | DR4 | |
| 11-8 | AI-only birds and nests | COVERED | W4 #7 | |
| 11-9 | AI-only butterflies | COVERED | W4 #7 | |
| 11-10 | AI-only garden insects | COVERED | W4 #7 | |
| 11-11 | AI deer and foxes when no player holds them | COVERED | §4.6 Bodies | |

### 1.9 Brief §12 Seasons, §13 Credits, §14 Deliverables

| ID | Requirement | Status | Plan section | Note |
|---|---|---|---|---|
| 12-1 | In-game calendar | COVERED | `Time/Calendar`, W2 #10 | |
| 12-2 | A week is the raid cycle | COVERED | `raidWeek` | |
| 12-3 | Time scale is one tunable constant with a sensible default | COVERED | D19, Tunables `realSecondsPerDay` | |
| 12-4 | Winter cycle about every 50 real minutes | COVERED | D19 | |
| 12-5 | Visible day and night | COVERED | W2 #10, W6 #2 | |
| 12-6 | Every five weeks, winter arrives and lasts one week | COVERED | D19 (week 6 of 6) | |
| 12-7 | Snow | COVERED | W4 #6 | performance caution (F-7) |
| 12-8 | Bare trees | COVERED | W4 #6 | |
| 12-9 | Dimmer light | COVERED | W2 #10, W6 #4 | |
| 12-10 | Reduced foraging | COVERED | W2 #10 | |
| 12-11 | At winter's end, squirrels below the threshold die and restart as humans | COVERED | W2 #10, M8 | |
| 13-1 | Humans earn credits from hospital, police and shop jobs | COVERED | §3.3 jobs, §3.9 | |
| 13-2 | Credits raise queue rank | COVERED | `Ladder.score` | |
| 13-3 | Credits buy the §9 and §10 station upgrades | PARTIAL | `Credits.spend` | no purchase flow and no catalogue; police slots unlock by performance, not purchase |
| 14-1 | Runnable place with every role test-playable | COVERED | §4.6-§4.7 | |
| 14-2 | Blender sources and FBX for the squirrel (rigged, seven clips) | COVERED | §5.7, W7 #5 | |
| 14-3 | Blender sources and FBX for the human variants | COVERED | §5.7 | |
| 14-4 | Fox assets | COVERED | §5.3 P2 | |
| 14-5 | Deer assets | COVERED | §5.3 P2 | |
| 14-6 | Key props | COVERED | §5.3 P1, P4 | |
| 14-7 | Town data file with every lot, including the full expansion | COVERED | §1.2 `data/town`, W3 | |
| 14-8 | README: module layout; how to add a lot type, a route, a role | COVERED | §1.2, W7 #5 | |

### 1.10 Addendum A1-A3

| ID | Requirement | Status | Plan section | Note |
|---|---|---|---|---|
| A1-1 | The two highest-ranked police players each get a drivable car | COVERED | §3.7 `driver`, P4 | what happens to a car mid-drive when the top two change is not specified (minor) |
| A1-2 | Enter and exit the car | COVERED | P4 | |
| A1-3 | Drive: throttle, brake, steer | COVERED | D10, P4 | |
| A1-4 | Siren and lights toggle | COVERED | P4 | |
| A1-5 | Park anywhere | COVERED | P4 | |
| A1-6 | Other officers on foot; AI patrol cars keep running | COVERED | dec 14 | at 8 player officers no AI officer bodies remain (S-9) |
| A1-7 | Player cars in the server swept collision; can run over the rodent | COVERED | P8, M5 | |
| A1-8 | Player cars take part in the traffic sim's yielding | COVERED | D10 | |
| A1-9 | Town map: minimap plus full-screen map with marker layers | COVERED | §3.10, H3 | |
| A1-10 | Sighting marker when a human spots the rodent or a bite happens; fades | COVERED | §3.10, P2 | |
| A1-11 | Who sees sightings (to confirm) | COVERED | dec 13, `markers.json` | |
| A1-12 | Drone mark gives a precise, short-lived marker | COVERED | `droneMark` layer | |
| A1-13 | Radar shows nearby speeders and moving vehicles; speeds feed tickets | COVERED | P5, P7 | |
| A2-1 | Rank rises from a successful kick by any human | COVERED | §3.7 `kick.landed`, H6 | |
| A2-2 | Police work = fighting crime | COVERED | P3 | |
| A2-3 | Settle a petty argument | COVERED | §3.9, W4 #2 | |
| A2-4 | Write up a fender bender | COVERED | W4 #2 | performance cost of driver bodies (F-6) |
| A2-5 | Parking ticket (hydrant, red curb, driveway, overtime) | COVERED | §3.6, §3.9 | |
| A2-6 | Speeding ticket (radar, pull over with lights and siren, issue) | COVERED | §3.9, P7 | |
| A2-7 | Stop signs, with AI drivers who sometimes roll through | COVERED | §3.6, W3 #1, W4 #2 | |
| A2-8 | Stop a burglar before they escape | COVERED | W4 #2 | depends on W3 interiors (S-4) |
| A2-9 | Hospital fetch: right medicine or instrument, under time pressure; a wrong item costs time and score | COVERED | §3.9, S4 | |
| A2-10 | Disinfecting counts as hospital work | COVERED | §3.9 `disinfect` | |
| A2-11 | Play runs live across in-game days | COVERED | §3.9 spawn per game hour | |
| A2-12 | Pursue rank or roam freely; no quest is mandatory | COVERED | §3.7 Offers ("don't offer me promotions") | |
| A2-13 | Credits keep working (earn, raise rank, buy upgrades) | PARTIAL | §3.7 | "buy upgrades" undefined (same gap as 13-3) |
| A3-1 | 70/30 blend for every possessed actor, animals included | COVERED | D13, `AvatarBlendService` | |
| A3-2 | Humans keep body type, uniform and silhouette | COVERED | D13 | |
| A3-3 | Humans take the avatar's skin tone | COVERED | D13 | skin TintMask on the same MeshPart as clothing is a feasibility problem (F-1) |
| A3-4 | Humans take hair or one signature head accessory | COVERED | D13 | |
| A3-5 | Humans take the avatar's face | MISSING | D13 | D13 reads "face" as a trait, but the human take-list omits it. Classic face decals or dynamic heads have no path onto the six custom heads |
| A3-6 | Avatar colours as accents (trim, tie, scarf, shoes) | PARTIAL | D13, §5.2 | only one accent colour on one TintMask zone; one SurfaceAppearance (one Color) per MeshPart |
| A3-7 | Animals keep the species model and stock markings | COVERED | D13 | |
| A3-8 | Animals take the dominant colours tinted into the fur (capped) | COVERED | D13 (30 % cap) | runtime tint path unverified (F-1) |
| A3-9 | Patterns coloured from the avatar's shirt and pants colours | PARTIAL | D13 | classic Shirt/Pants assets carry no colour; "colour words from item names" needs `MarketplaceService:GetProductInfo`, which S9 does not test; layered clothing ignored (F-3) |
| A3-10 | Eye colour from the avatar | COVERED | D13 | rodent eyes stay red |
| A3-11 | One avatar accessory shrunk onto the head socket | COVERED | D13 | the acquisition path is not spelled out (F-4) |
| A3-12 | Bizarre avatars: clamp saturation and brightness | COVERED | `BlendRules`, §6.2 | |
| A3-13 | Bizarre avatars: one signature feature | COVERED | D13, M6 | |
| A3-14 | Drop anything that breaks silhouette or hitboxes | COVERED | D13, M6 | |
| A3-15 | Read the avatar server-side with `GetHumanoidDescriptionFromUserId` | COVERED | D13, S9 | |
| A3-16 | No clothing pixels; derive colours from body colours, accessory metadata or a curated mapping | COVERED | D13 | |
| A3-17 | Reversible: 100 % stock when the player leaves | COVERED | §1.5 Release | |

### 1.11 Owner art direction and standing decisions (task context)

| ID | Requirement | Status | Plan section | Note |
|---|---|---|---|---|
| AD-1 | Semi-realistic overall | COVERED | §5.6 | risk 4 acknowledged |
| AD-2 | Spicy rodent zombie-lite: mangy, stitched bald patches, a few ribs | COVERED | §5.6, §5.3 P0 | |
| AD-3 | Natural fur colours, no green | COVERED | §5.6 | |
| AD-4 | A little blood on muzzle and claws | COVERED | §5.6, dec 24 | upload moderation risk (F-9) |
| AD-5 | A touch of horror | COVERED | §5.6 | |
| AD-6 | "Cute but unhinged": oversized bloodshot eyes, crazed buck-tooth grin | COVERED | §5.6 | |
| AD-7 | Humans: every role outfit (townsperson, police, nurse, doctor, guard, orderly, cyclist, jogger, mail carrier, EMT, ...) | PARTIAL | §5.6, §5.3 P1 | listed, but the delivery path for about 13 outfits on 6 bodies is unplanned and unbudgeted (F-2) |
| AD-8 | Several adult body types | COVERED | §5.3 P1 (6) | |
| AD-9 | All three hollow variants: shaft with knothole exit and hideout nook; spiral ramp; fallen-log tunnel | COVERED | §5.5 | |
| AD-10 | Reconciled with the brief's 11 (2 premium, 9 knothole) | COVERED | §5.5, dec 19 | |
| OD-1 | New private repo; the website repo is never touched | COVERED | Fixed facts | |
| OD-2 | Open Cloud for uploads, saves and Luau Execution; Studio for rig import, SurfaceAppearance, multi-client tests and final publish | COVERED | D12, D15, §5.1 | |
| OD-3 | Already-done owner items are not scheduled again | COVERED | §8 preamble | W7 #7 re-lists "max players 50" (cosmetic) |
| OD-4 | Owner Studio steps click-by-click and few | PARTIAL | §6.6 | the S7-failure branch and the outfit imports add unbudgeted Studio time; OS-1 bundles four tasks (S-6) |
| OD-5 | Discuss order of operations before a significant commitment | COVERED | Step 0, G0, §4.13 knobs | |
| OD-6 | Ephemeral container; everything in git | COVERED | §4.1 | |
| OD-7 | At most 2 subagents at once, 4 CPUs | PARTIAL | §4.1 two tracks | Track B is overloaded and the "continuous" art track has no lane (S-8) |

Counts: **307 requirements; 277 COVERED, 28 PARTIAL, 2 MISSING** (3-39 fog layering, A3-5 avatar face).

---

## 2. Sequencing problems

**S-1. The CI and Art Inbox places are created after the W0 spikes that need them.** The owner adds "CI" and "Art Inbox" in OS-1 step 1, which runs at the *end* of W0 (plan §4.3, §6.6, dec 2). But S1 is defined as "save a version to the CI place and run a Luau Execution task". S4, S5, S6, S7, S8(a) and S9 all run in Luau Execution earlier in W0. Places cannot be created through Open Cloud. Fix: move "add two places" into Step 0 / OS-0 (about 3 minutes on the web), or state that W0 spikes target the main place. Also confirm that the existing API key's place and experience scope covers the new places (the plan asserts "the existing key covers them"). If it does not, editing the key is another owner step.

**S-2. Harvested-exact routes conflict with the quirk fixes.** D8 harvests all 1,332 routes exactly. Yet inv 2 (every lot front faces a road, fixing the outer-home inversion [worldgen_core §18.2]) and the known route bugs [routes_movement verifier 3-4: outer-home downspouts double-count terrain; flat outer-home roof landing against a gabled mesh; worldgen_core verifier 5: ridge-length quirk] mean the 20 outer homes' harvested routes cannot match rebuilt greybox geometry. Lot-type template routes arrive only in W3 #5. W1's exit ("every route sample within `surfaceRadius + 0.3 u` of geometry") either fails or passes trivially where geometry is drawn around the routes. Fix: add a W1 "harvest patch list" (which harvested routes are corrected and how). For the outer homes, either let them declare a reason under inv 2 until W3, or pull their templates into W1.

**S-3. W2's hospital greybox and station console are WorldGen work given to the gameplay track.** W2 Track A #3 builds "greybox rooms from the brief layout (all 8 rooms)". The imported v5.4 data has one ward and no isolation ward, pharmacy or staff room (hospital_police §11.1). `buildings/hospital.json` (plan §3.12) is not authored in any wave before W2. W2 #5 needs a station console and W2 #4 car pads, but the v5.4 station cannot be entered. This is data and builder work (Track B) with no owner. Fix: put `buildings/hospital.json` and `police_station.json` v0 into W1 Track B #7.

**S-4. "W3 and W4 interleave" hides hard dependencies.** These W4 Track A items need W3 Track B outputs:
- the burglar needs claimable interiors (W3 #3);
- indoor chases and the three defenders need the defender houses (W3 #3);
- town-wide stop-sign running needs traffic control everywhere (W3 #1);
- the isolation flow needs the isolation ward (W3 #6).

The plan offers "W3 first" only as a knob (§4.13 #2). Fix: list the cross-track dependencies explicitly and order the W3 sub-steps that feed W4 first (traffic control, interiors and defenders, hospital) before the expansion lots.

**S-5. The drone's far view, the role that "justifies the backdrop", is retired last.** The plan's §9.1 scores risk-first down because "the far view is mitigated rather than tested", then adopts no far-view spike. Risk-first's S5 (published-server drone at 300 st, "whether streamed-out terrain renders far away", drone `ReplicationFocus`) was dropped. Consequences:
- the first real test is W6 #5;
- W6 #5 checks "SLIM where generated", but `LevelOfDetail = SLIM` is only set in W7 #6;
- S6 measures terrain writes only for the 4,350 x 2,520 st town, while W6 adds near hills as Terrain 0.5-2 km out and ocean water 6-10 km out [worldgen_districts_art §14.4], which could multiply boot-time voxel writes.

Fix: add a small W0/W1 far-view spike on a published private place (Skyline parts plus terrain at 300 st plus `ReplicationFocus`), and re-measure terrain boot time with the backdrop bands.

**S-6. Owner Studio work can bunch up unbudgeted.**
- If S7 (headless clips) fails, every clip needs an Animation Editor import and publish at 1-2 minutes each. That is about 20 squirrel and rodent clips, about 30 human clips, about 11 fox and about 10 deer (plan §5.4), roughly 70 clips or 1.5-2.5 hours. Only OS-6 mentions the fallback; OS-4 (squirrel and rodent) does not, and the "6 to 7 hours" total in §0 excludes it.
- Role outfits for about 13 roles (F-2) are not in any session.
- OS-1 bundles four unrelated tasks for a non-programmer: creating places, the possession checklist with two windows, art import, and Convert to Package with the correct creator.
- OS-6 holds fox, deer, 6 bodies and 2 premium hollows in one 40-minute session.

Fix: budget the S7-failure branch per session, and split OS-6.

**S-7. The G2 turntable gate depends on headless renders that are untested.** The feasibility doc says "rendering previews may be possible with Cycles or EEVEE headless, but I didn't test that". EEVEE generally needs a GPU context. Cycles on 4 CPUs competes with CI and Lune runs. G2 gates every hero import (OS-3 at the start of W3). Fix: add a W0 render spike (one 36-frame turntable at 512 px; record minutes per frame).

**S-8. Track B is overloaded, and the art track has no lane.** Track B carries the compiler, WorldGen, routes, traffic, placeholders, map and blend (W1); foraging, wildlife, jobs, seasons and UI (W2); W3 (XL); W6 presentation; *and* the art track "running continuously from W1". With at most 2 subagents, art (risk 4, H/H) competes with the XL town build. "Blender exports go to the background" covers CPU, not authoring attention. Fix: rebalance (move traffic or UI to Track A after W1) or give art fixed slots between waves.

**S-9. Body roster and slot arithmetic do not add up, and the plan never says what happens on overflow.**
- The Ladder gives the human rung 35 slots *plus* hospital 5 *plus* police 5-8, so up to 48 human-species player slots, and 61 slots in total against 50 max players.
- The FRB roster has 50 human bodies: 22 townspeople, 6 shop workers, 8 staff, 6 patients and 8 officers. That is only 28 civilian bodies for 35 townsperson slots, and patients are AI-only (hospital_police §11.1 item 9).
- The D4 fallback trims to 42 "(still above 35)", which is below 48.
- At full occupancy shops, streets and AI officers disappear, contradicting brief §4.
- Nothing defines what happens when a player joins while the human rung is full (possible whenever players decline promotions, A2 free roam).

Fix: decide whether tier-2 slots are inside the brief's 35 (the brief's 35 + 7 + 1 = 43 arithmetic implies yes). Write a full-occupancy body budget per role with an AI floor per job site. Define overflow (re-outfit with `BodyFactory.applyLook`, or spawn extra bodies up to a cap), then re-run S5 at that count.

**S-10. AI rodent refill against the promotion offer.** R5 says "a new AI rodent appears about 20 s later", and M7 shows the offer to the top squirrel. The order (offer first and AI only on decline or timeout, or AI immediately with a swap on accept) is not defined. The 15 s offer timeout and the 20 s respawn delay interact. Fix: one Ladder row plus one LadderE2E case.

**S-11. FRB interiors depend on pieces W1 does not list.** The 4 FRB houses (W2 #9, H5, H8) need interior templates, the `Interior` builder, room graphs and server-owned doors. W1 #7 lists builders "for every lot type present in the imported data", and the v5.4 interiors are dead code (worldgen_core §18.1). Add the interior template schema and builder to W1 explicitly.

**S-12. Sim10 cannot simply be split into two tasks.** Luau Execution has a 5-minute cap and "changes are not persisted". 10 simulated minutes at 60 Hz (36,000 frames) with full AI likely needs more than 5 minutes. The plan says "split into two tasks if needed", but the second task cannot resume the first one's state unless it is serialised through the 4 MB return value and the binary input. Design the hand-off, or shorten the run to 5 simulated minutes at full population plus a separate long low-population run.

**S-13. Two tracks share one CI place.** Concurrent saves from Track A and Track B can make a Luau Execution task test the wrong version. `cloud/run_engine_tests` must pin the version ID returned by the save (the API supports `/versions/{v}`), and the 5-creates-per-minute budget is shared per key owner.

---

## 3. Feasibility problems (against `spec/roblox_feasibility.md` and the platform)

**F-1. Runtime tinting of SurfaceAppearance is unverified, and one Color per MeshPart rules out multiple tint zones.**
- D13 and §5.3 rely on TintMask for the 70/30 fur tint, human skin tone and accent colours, and the fallback only triggers if tinting "looks wrong".
- Feasibility §g says "One SurfaceAppearance per MeshPart" and "Most properties are not script-modifiable at runtime".
- No spike writes `SurfaceAppearance.Color` at runtime on a rig loaded with `LoadAsset`. S8(b) checks normal maps; S9 checks traits.
- "TintMask zones for skin and accent" on one MeshPart is impossible because a SurfaceAppearance has one Color. Each tint zone must be its own MeshPart, a split the rig contract (§5.2) must state. The other route is a `MeshPart.TextureID` plus `Color` path for tinted zones.
- Fix: add both to S8.

**F-2. The plan has no workable route for human role outfits.**
- "Outfit texture sets per role with accent zones" on 6 custom bodies means SurfaceAppearance maps that cannot be assigned by script. The feasibility doc never shows that an Open Cloud Model upload creates SurfaceAppearance.
- Each outfit set therefore becomes a Lane 3 Studio import, about 13 roles (§5.6), possibly per body, and none of it is budgeted in OS-6.
- Lane 4 (classic Shirt/Pants) only works on standard R15 UVs.
- Fix: decide early between (a) a shared UV layout across the 6 bodies, one pre-made SurfaceAppearance per outfit cloned at runtime, about 13 imports; (b) non-PBR `TextureID` outfits uploaded through Open Cloud; or (c) R15-standard UVs with classic clothing. Then budget it.

**F-3. The avatar face and shirt/pants colours have no feasible source as written.**
- A3 asks for the avatar's face, and pattern colours "from the avatar's shirt/pants colours".
- HumanoidDescription gives Shirt/Pants asset IDs with no colour, and reading clothing pixels is restricted (A3, D13).
- "Colour words from item names" needs `MarketplaceService:GetProductInfo` per asset, which is rate-limited and missing from S9. Layered-clothing jackets and shirts are accessories, not Shirt/Pants.
- Faces (decals or dynamic heads) do not transfer onto the custom heads.
- Fix: S9 should include `GetProductInfo` on the samples. The plan should state the fallback (body colours plus accessory colours plus a curated item-to-colour table) and record the face as a declined trait or a decal-on-head path, approved by the owner.

**F-4. Getting the accessory onto an animal has a specific path the plan leaves unstated.**
- Other users' catalogue or UGC accessories cannot come from `InsertService:LoadAsset`, which only loads assets owned by the creator or by Roblox. They come from `Players:CreateHumanoidModelFromDescription` (S9 tests it).
- Layered accessories (WrapLayer) cannot be shrunk onto a squirrel.
- On a non-Humanoid the accessory must be welded by hand. State the path and the "rigid accessories only" filter.

**F-5. Audio uploads are capped.** Feasibility §d: Open Cloud Audio uploads are capped at 10 per month (100 if ID-verified). W6 #4 "audio and ambience", the sirens, the radio, the fountain and the per-actor sounds name no source. Fix: plan to use Roblox's licensed audio library first, uploads only for a few signature sounds, and ask the owner whether the account is ID-verified.

**F-6. Fender-bender drivers as human bodies break the S5 budget.** W4 #2 makes AI drivers "human bodies that step out". S5's synthetic population is 60 humans and 45 vehicles *without* drivers, and feasibility §e puts stutter at about 100 Humanoids. Fix: borrow a nearby pedestrian body for the incident (possession-style swap into the car), and re-run S5 with the incident load.

**F-7. Terrain written at runtime has costs the plan does not count.**
- Lune cannot write voxels, so every server boot (each Studio Test, CI task and live server) writes terrain. S6 allows 20 s for the town only (see S-5 for the backdrop).
- Streamed-out terrain at drone altitude is not addressed (feasibility §e covers only models and SLIM).
- Winter "snow terrain swapped in chunks" (W4 #6), if done on the server with `ReplaceMaterial` over about 11 M st², replicates voxel deltas to every client. Client-local snow (terrain material change or overlay applied per client) avoids that.
- Fix: decide early whether D6 fallback (b), ground MeshPart tiles, should be the primary ground for both the drone view and boot time.

**F-8. Parts are capped at 2048 studs per axis (platform fact; verify).** The backdrop bands 5-10 km out at "≤ 20k tris per band" (§5.3 P5), and a large ocean or ground mesh, must be tiled into several MeshParts. The 20k-triangle-per-mesh cap then applies per tile. Ocean "6-10 km" should be Terrain water or tiled planes. Not stated.

**F-9. Uploads go through moderation.** Every Open Cloud image, model or animation is moderated. IDs can sit pending (rendering blank) or be rejected, and the rodent's blood textures and horror tone are the likeliest to be flagged. The `Assets` suite and owner builds can see blank assets. The plan's manifest status should include `pending` and `rejected`, with the placeholder fallback, and blood should live in a separate small texture (it already plans a "flagged decal set", which helps).

**F-10. The Claude GitHub App may lack permission to push workflow files (verify).** Pushing `.github/workflows/ci.yml` needs the GitHub App's "workflows" permission. Without it D16 (strict `luau-lsp` in Actions) cannot be installed by Claude, and that becomes an owner step. Check this when the App connection is finished.

**F-11. Team Create could overwrite Claude's saves (verify).** If Team Create is enabled on the main place, the collaborative session's saves can overwrite versions saved through the API. "The owner never saves into the main place" does not cover Team Create autosave. Keep Team Create off for the main and CI places, and say so in OS-1.

**F-12. The Roblox menu's Reset button is unhandled.** With the Humanoid `Dead` state disabled and bodies that are possessed rather than spawned, the Roblox menu's "Reset Character" must be disabled or routed to a role transition (`StarterGui:SetCore("ResetButtonCallback", ...)`). Non-Humanoid bodies need the same treatment, and bubble chat needs an adornee on non-Humanoid heads.

**F-13. Drone streaming focus.** The pilot's character stays at the console 1-2 km away. Without `Player.ReplicationFocus` set to the drone, streaming follows the character, and client ownership of a far-away drone part is fragile. `RequestStreamAroundAsync` alone (D5) is not enough. Risk-first had this; the plan dropped it.

**F-14. Luau Execution timings are not live-server timings.** The `Sim10` budget gate ("AI < 4 ms per frame") measures a headless, physics-free, replication-free engine. Treat it as a regression signal and keep the W7 live MicroProfiler numbers as the gate.

**F-15. Lane 2 kits may not carry PBR maps (suggestion).** The feasibility doc does not show that an Open Cloud FBX upload brings normal or roughness maps, so Lane 2 buildings may be colour-texture only. That falls short of the semi-realistic target. `MaterialVariant` (MaterialService) with uploaded maps is a Studio-free PBR path for kits and greybox; add it to S8.

**F-16. `rojo syncback` captures must stay out of the build.** Art Inbox captures in `assets/captured/*.rbxm` contain SurfaceAppearance. Because `assets/` maps to `ReplicatedStorage.Assets`, they would enter the place and break the "no SurfaceAppearance in the place" rule and the Open Cloud publish. Exclude `captured/` from every project file. The place test would catch this, but late.

Items already handled correctly (no finding):
- one animation per FBX (§5.1);
- the 20k-tri cap (§5.3);
- SLIM needing baked static geometry (D5, D6);
- no clothing pixels (D13);
- Open Cloud rate limits (W0 #2);
- the API publisher not updating SurfaceAppearance (D12, §6.4);
- `PlayerCharacterDestroyBehavior` (§1.2);
- no Luau type checker in the container (D16).

---

## 4. v5.4 behaviour the specs document and the plan silently drops

None of these is called out as dropped. Several are kept by an owner-decision default but never scheduled in any wave.

| # | v5.4 behaviour (spec) | Plan status |
|---|---|---|
| D-1 | Novelty street cast: Marcel the mime on a unicycle and 5 kid cyclists, with their own spotting and escape rules (humans_actors §8; squirrel_abilities verifier 3) | dec 21 refers to them, but there is no `NoveltyRider` brain (§1.4 brain list) and no wave builds them |
| D-2 | Motorcyclists (2), skaters and novelty riders as road users (traffic §2.7-2.8, §5.12-5.13); whether motorcycles join the fatal fleet (traffic defect 5, Q9) | not in the brain list or the FRB fleet; only a motorcycle *asset* (§5.3 P3) |
| D-3 | Living-community events: barbecue (-66,-84) and softball (66,356), on a 2,400 s cycle (humans_actors §9.3, Q7) | absent |
| D-4 | Crime scenes: seated victims, witness alarm, emergency bystanders gathering (humans_actors §7.2-7.4) | only "witness alarm" survives, as a sighting source (§3.10); scene staging and bystanders are not scheduled |
| D-5 | Yard cats' telegraphed swat and yard dogs' bark that alerts humans (humans_actors §12; squirrel_abilities verifier 2); turtles | demoted to "ambient life" (W4 #7, dec 20), which the plan runs client-side (§1.3), so their gameplay vanishes; turtles never mentioned |
| D-6 | Garden and hedge concealment from human spotting (Tabasco garden, hedges; wildlife verifier 1) | not mentioned; `Perception.spotted` is "ported" but the concealment terms are not listed |
| D-7 | River-fall recovery (squirrel moved to the nearer quay) and swimming rules (worldgen_districts_art §16 Water, Q9); "recover to last safe position" | only `FallenPartsDestroyHeight` is lowered; no recovery or safe-position service |
| D-8 | Hidden chili hunt (8 peppers) and chili rush (squirrel_abilities §12-§13) | dec 20 keeps it as a rodent power-up; no wave schedules it |
| D-9 | Sewer fashion stand: buy and equip, wardrobe (squirrel_abilities §15) | dec 20 keeps it as a cosmetic; no wave schedules it; the currency after coins and wardrobe persistence (against D14 "no DataStore") are undefined |
| D-10 | Galleria coin pickup, wishing-fountain toss, mall state machine (client-animated doors, lights) (worldgen_districts_art §4.6-§4.7, §16) | dec 20 remaps coins to credits and nut crumbs; no wave implements it |
| D-11 | Trampoline bounce (worldgen_core verifier 4) | route kind kept (§3.5); bounce mechanic not scheduled |
| D-12 | Hospital overhead-hatch ambush with a 2.5 s attack window (humans_actors verifier 6; hospital_police §4.6) | hatch moved over an aisle (W3 #6); the ambush window is not mentioned |
| D-13 | Incident police, station reinforcements and precinct guards that keep the rodent out of the station (hospital_police §8.4-§8.5) | only "AI dispatch backfill" (W4 #2); station security not listed |
| D-14 | Bite dance trigger (every 10th bite) (squirrel_abilities §10, Q9) | clip authored (§5.4); trigger rule undecided |
| D-15 | NPC voices (speech synthesis per voice type and personality) (humans_actors §11) | bubbles only (W4 #8); no decision recorded |
| D-16 | 8 Quay ambient walkers (brief §4 says every human is an actor; districts_art §15) | not addressed (keep as actors, replace, or remove) |
| D-17 | v4.1 lost extras outside the brief's list: crowd accessories (`makeTownPeopleMoreDistinct`, humans_actors verifier 2) and flowering bushes (wildlife §11.7) | silently not restored |
| D-18 | Gas-station panic closure, clock-tower hands, legacy decorative ambulance loop (worldgen_core Q7; districts_art Q11; hospital_police Q17) | undecided (minor) |
| D-19 | Squirrel carried or pushed by a moving car roof (routes Q6, traffic Q13), more pressing now that players drive cars | undecided |
| D-20 | Rodent fall damage (routes Q7) | undecided |

Fix for the whole section: add a "v5.4 behaviours: keep, defer or drop" table to `docs/DECISIONS.md` in Step 0. Give every "keep" a wave and a check, so nothing is lost by omission.

---

## 5. Smaller consistency notes

- §0 says the squirrel and rodent are imported in "Wave 3", §4.10 says "right after the FRB (OS-4)", and §6.6 puts OS-4 "during W3". These are consistent, but the S7-failure clip work is missing from OS-4 (S-6).
- `Tunables.drone.maxAlt = 160 u` (400 st) puts the 315-st radio tower inside the flight envelope. dec 25 says "tall towers block the drone", but there is no collision test for it.
- `markers.json` gives `hollow` an audience of "squirrel" with `showOwner`. The rodent rests in owned hollows (§5.5), but whether the rodent sees hollows on its map is unspecified.
- A1-1: "top two by rank" can change mid-drive; define whether keys transfer only when the car is parked.
- 6-9 and 7-16: define "nut count" for rank (stored in hollow, carried, or lifetime).
- E2 (deer startled by cars) may be untestable if no lane passes the north-park herd; add a Lab "spawn car near deer" command.
- The `Assets` suite's ownership check is good. Add moderation status (F-9).

---

## 6. Recommended changes before G0, in priority order

1. Rewrite the slot and body budget (S-9) and get the owner's ruling on whether hospital and police slots are inside the 35.
2. Move the CI and Art Inbox place creation into Step 0, and confirm the key covers them (S-1).
3. Add to W0: S8(c2) runtime `SurfaceAppearance.Color` write plus a per-zone MeshPart split; an outfit-path decision (F-1, F-2); S9 `GetProductInfo` plus the accessory path (F-3, F-4); a headless render spike (S-7); and a published far-view spike with `ReplicationFocus` and far terrain (S-5, F-13).
4. Write the W1 harvest patch list and the cross-track dependency list (S-2, S-3, S-4, S-11).
5. Budget the owner's Studio time for the S7-failure branch and the outfits; split OS-1 and OS-6 (S-6).
6. Add fog layering to W6 and to the P5 asset list (3-39), and define the face trait (A3-5).
7. Add the "keep, defer or drop" table for the v5.4 behaviours in Section 4, and define the upgrade catalogue and purchase flow (9-13, 13-3), the police performance metric (10-3) and the rodent's "win" outcome (8-8).
