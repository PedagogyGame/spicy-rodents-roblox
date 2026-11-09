# Spicy Rodents on Roblox: the plan after brief v2, on one page

For Ben. 9 November 2026. The full plan is `spec/BUILD_PLAN.md` (now revision 4: revision 3 took in brief v2, and revision 4 fixes what a review of revision 3 found and adds your answers on audio and the 49 cap). Nothing here needs a terminal.

## What brief v2 added

- **A hard 49-player server** (35 humans, 7 squirrels, the rodent, 5 deer, 1 fox), no overflow, and at least 6 computer police and 10 computer hospital staff on duty at all times. Because our key cannot change the server size, the place stays at Roblox's 50 and the game itself politely turns the 50th person away before they get a body (your answer B4).
- **Hollow trees:** 12 plus a fallen log and the three-exit escape tree; claim by being there, keep the claim by visiting every 3 in-game days at 70 %; nuts run out each season; carry 9.
- **Rodent rules:** the outbreak cinematic instead of an end card; the board is not wiped when the rodent dies; deer only after every squirrel is infected; the bite aftermath; health drains 1 a day and bites heal; squirrel chases with a locked camera.
- **Human life as a full game:** Spicy Dollars (Robux packs), wages, gigs, reputation and votes, mischief, taunts, carts, bikes, trampolines, tree houses, and about 20 fully working places (corner store with 22 items, doctor's office, museum, bowling alley with the squirrel ball-return tunnel, racquetball, steakhouse, jet ski, parasailing, sky lift, paintball in the TV station, two lounges, the new mall with the wind tunnel).
- **Camera:** first person for humans on demand, automatic in vehicles and the gondola, locked in paintball and the lounges.
- **Extras:** traffic law for everyone (police included), street lamps everywhere, layered fog, the off-road zone, Power kept exactly, mild rating, no money on art.

## How the order of work changed

Same shape: prove the risky parts (Wave 0), build the skeleton (W1), the **first runnable build** with all eight roles (W2), then town and systems side by side (W3 and W4), then **two new waves for the attractions (W3c and W4b)**, then art (W5), sky (W6), publish (W7). New in revision 4:

- The attraction buildings now arrive **in the order the minigames need them**: bowling alley first, then the corner store and doctor's office, then the steakhouse and racquetball court, then the rest.
- The town work W4 depends on comes out in two batches (stop signs, police station, lamps, TV station first; then the 40 homes and the hospital), so systems work is not held up.
- **Paintball's "can it share the town server?" is decided at your paintball playtest**, from a live measurement, not guessed in Wave 0.
- Anything that needs real physics, cameras or frame rates is tested in Studio by you or on a private server with a window left open, never assumed from the automatic tests (which cannot run physics).
- The first build is bigger than before; if it runs long, the lawn-mowing gig, the cart and bikes and four store items move to just after it rather than delaying it.

## Wave 0: where the tests stand

**Passed (7):** saving builds to your CI place (S1), squirrel climbing on all 1,332 routes (S3), cars running over squirrels exactly as v5.4 does (S4), 90 computer people for a tiny share of server time (S5), reading Roblox avatars (S9), the type checker (S10), Blender pictures without a screen (S12). Your CI and Art Inbox places already exist; you have nothing to create.
**Still to run:** taking over moving bodies (S2), terrain (S6), animations without Studio (S7), art reaching Roblox (S8), the drone's far view (S11), and the brief v2 tests: **physics minigames** (S13), **first person in vehicles** (S14), **Robux purchases that are never lost or double-charged** (S15), **paintball garb on a body** (S16), **300 street lamps** (S17), **paintball hit detection** (S18), **the body count at a full server** (S19), the store camera and chalk (S20).

## What the first runnable build contains

All eight roles through a LAB button (townsperson, hospital staff, police with a drivable car and radar, drone, squirrel, spicy rodent, fox, deer) on a grey-box copy of the whole v5.4 town. Humans get a wage in Spicy Dollars, six working store items, lawn mowing, thumbs up and down, a golf cart and bicycles, first person and taunts. The rodent gets Power with its fade countdown, the health drain and bite heals. Squirrels get the 12 hollows, nine-nut pockets and the visit rule. A help panel (H) in every role, and an idle rule so nobody can sit on the rodent slot. The Lab can fill the server with 49 fake players to show the town stays staffed.

## Your time (about 12-13 hours over the whole build; no sitting over about 90 minutes)

| When | What | Time |
|---|---|---|
| Now | Answer or accept the questions below; create 3 Robux products on the website; one Studio setting | 20 min chat, 10 min web, 2 min Studio |
| End of Wave 0 | Four Studio or app sittings (bodies, one import, the drone, the physics/vehicle/purchase/lamp tests), then read the report and say go | 20 + 10 + 10 + 40 + 15 min |
| End of Wave 2 | Play the first runnable build | 60-90 min, two sittings |
| Waves 3-5 | Town-plan page and turntables (web); import squirrel and rodent | 30 + 40 + 20 min |
| End of Wave 4 | Build #2 in two sittings on different days; paintball playtest on a third | 2 x 60 + 60 min |
| A few builds | Leave a private-server window open while the game tests its own physics | about 5 min, 4 times |
| Wave 4b | Minigame checks, then a walk through the attractions | 90 + 20 min |
| Wave 5 | Three short import sittings | 15 + 15 + 25 min |
| Wave 6 | Sunset, fog, lamplit town, both lounges | 40 min |
| Wave 7 | Play with friends, set Max Players to 49, approve the publish | 60-75 min |

Up to about 2 hours more only if the automatic animation route fails.

## Open questions (each has a recommended default; silence means the default)

1. **Skin tone** (plan item 37): show the player's skin colour on a townsperson's skin areas through the body-part colour (the property Roblox's own body colours use). *Default: yes; you see one rendered example at the end of Wave 0 before anything is made.*
2. **Time scale** (38): with 72-second days, hollow visits come every 3.6 minutes, passes last 6 minutes, votes refresh every 72 s and ranking starts after 12 minutes. *Default: keep as written and tune in the first build.*
3. **Rodent stalk camera** (39): *Default: over-the-shoulder third person (brief §14), keeping v5.4's aim arc; alternative: keep v5.4's first-person stalk.*
4. **Rabid deer** (40): *Default: its charge knocks people down, and knocked-down people are easy bites; the deer itself never infects. Healthy squirrels cannot be kicked; the water-gun stun is once per player per server.*
5. **What is saved between servers** (41): *Default: wallet, purchases, wardrobe, items, reputation and lifetime stats; nothing else.*
6. **Paintball hosting** (42): *Default: inside the town server, decided at your playtest; players may leave a match early.*
7. **Robux packs** (43): *Default: 25, 100 and 400 Robux for 100, 400 and 1,600 Spicy Dollars.*
8. **Content details** (44): *Defaults: mischief costs a fine and a little reputation, a cell for repeat offenders; carts and bikes are not "driving"; votes go to players only; the fortune machine's reels spin with fortune symbols (never fruit or sevens). Please tell us the specifics of the barber shop before Wave 3; otherwise a two-chair shop with a pole, bench and radio.*
9. **"35 of the 43"** (45): *Default: 43 means 35 humans + 7 squirrels + the rodent, with 5 deer and the fox making 49.*
10. **What ranks a human in the queue** (46): *Default: Spicy Dollars and reputation count most (1 point each), time played a little (15 points an hour); you see the curve after the first build.*
11. **The hospital killer when all 7 squirrel places are taken** (47): *Default: a temporary 8th squirrel place until one frees (the server never passes 49).*
12. **Max Players 49 on the website** (48): *Default: leave it at 50 while private; you change it to 49 (one minute) just before going public.*
13. **Idle players** (49): *Default: after 13 minutes with no input in a scarce role, a 30-second warning, then back to townsperson.*
14. **Human sprint stamina** (50): *Default: 10 seconds of sprint; soda and ice cream give unlimited sprint for a while.*
15. **Rodent and squirrel earnings** (51): *Default: 10 Spicy cents per successful bite; the sewer fashion stand opens after 150 cents earned as an animal.*
