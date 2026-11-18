# THE GILDED ACORN, the 1940s lounge: what to look at (10 to 15 minutes)

This is the old-fashioned lounge from your brief ("Lounge one"). It has leather and woodwork, a long polished bar, a bartender in a white jacket, jazz, and two tough guards at the door who let no squirrel in. Only this lounge is built: the futuristic one is not, as you asked on 18 November. Everything below has been tested without a screen, so what you see is the real check. Wherever something is off, tell me what you pressed and what happened.

## Before the build
The lounge is baked separately from the town. Run `lune run tools/bake/lounge_classic.luau` before building the place. It writes `build/Expansion_LoungeClassic.rbxm`, which is not in git. Without it, the server log says `[Lounge] Workspace.Expansion.LoungeClassic has no bake` and there is no lounge to see.

## How to get there
The lounge is in the leisure quarter, about 200 studs east of the bowling alley, at about x 1487, z -334 (the door). Bowl Lane, the street planned in front of it, is not built yet, so for now the lounge stands on grass. Its front is black marble with gold lines, and **THE GILDED ACORN** is written over the canopy. A brass acorn sits on the roof.

## What to do
1. **As a person without a pass.** Pick **Townsperson**. Walk between the velvet ropes, past the two guards and up the four steps. At the door, press **E** (**Go in**). You should read "Members only. A pass is 20c for five in-game days of paintball and both lounges." The door stays shut.
2. **Buy the pass.** Press **E** at the black podium on the right of the door (**Buy a pass**). With 20c or more you pay 20c and go straight in. With less, you read "You need 20c; you have …c." and nothing is taken. This is the same pass the paintball desk sells, so one pass opens both.
3. **Inside.** You stand just inside the door, facing the room, and the camera is **locked to first person**. **V** does nothing here. The jazz would start softly, but it is silent for now (see "Uploads" below).
4. **Look around.** You should see the long bar with seven leather stools and a brass foot rail, the bartender behind it, and the back bar with its mirror, cups, a coffee urn, a cocoa pot, a teapot and a snow-cone machine. There are four leather booths along the walls with a lamp on each table, and club chairs round four small tables on the rug. The stage at the back left has a grand piano, a microphone and a 1940s radio. The fireplace on the right has two armchairs. Overhead are two chandeliers.
5. **Order a drink.** Walk up to the bar. Along it, **E** offers **Hot cocoa (10c)**, **Coffee (12c)**, **Green tea (8c)** and **Snow cone (6c)**: the nearest one shows. You pay and the drink is in your hand. You lift it to your mouth four times, five seconds apart, and then read "All gone." You can hold only one drink at a time.
6. **Leave.** At the door inside, **E** (**Leave**). You are back on the landing facing the street, and your usual camera returns. A drink you were still holding is gone.
7. **As a squirrel.** Pick a squirrel and run at the door. As soon as you are on the forecourt, the steps or the landing, the nearest guard steps in and you are knocked out: "THE GUARDS! The lounge's guards do not let squirrels in." You go back to the menu, as with any knock-out. Computer squirrels that wander there are sent back where they live. Then try other ways in: the walls, the windows, the roof. There is no way in.

## Please check
| # | What to look at | What you should see |
|---|---|---|
| 1 | The front, by day and at night | Black marble and gold, four amber windows, the lit canopy, the sign readable from the street, two glowing lanterns either side of the entry |
| 2 | The guards | Two broad men in claret coats and peaked caps either side of the ropes. A guard steps toward a squirrel and back (no blood, nothing shown but the step) |
| 3 | The door without a pass | "Members only." and the pass's price, and the door does not open |
| 4 | Buying the pass at the podium | 20c taken once, straight in. The same pass opens paintball |
| 5 | First person inside | Locked the whole time you are inside; your normal camera back the moment you leave |
| 6 | The light | Warm and low: pendants over the bar, booth lamps, sconces, the fire, the chandeliers. Tell me if it is too dark for you on a phone |
| 7 | The bartender | Turns to face you for a moment when you order |
| 8 | The drink | A white cup (or a paper cone with red ice) in your right hand, lifted to your face four times, then gone |
| 9 | A squirrel at the door | Knocked out on the forecourt, the steps or the landing, every time |
| 10 | Nothing alcoholic | No bottles, taps or cocktail glasses anywhere; the menu says HOT COCOA · COFFEE · GREEN TEA · SNOW CONES |

## What it costs (phones)
- **Parts:** 480 (the bake's own cap is 800; the plan allowed 1,300).
- **Lights:** 22. Only 3 cast shadows: the middle pendant over the bar, the back chandelier and the spot on the piano.
- **The Blender pieces** (bar, booths, wall panelling): 15,448 triangles in 14 meshes, once uploaded. That is about one pinball machine.
- **Work each frame:** the server checks the door and the guards five times a second. It checks only squirrels within 60 studs.

## Uploads (the lead does these; nothing has been uploaded)
- **The Blender pieces:** `python3 -I tools/blender/lounge_classic/publish.py` uploads one Model. Until then, the bar, the booths and the panelling are the plain-part versions.
- **The jazz:** four tracks picked from Roblox's own licensed music library, so nothing is uploaded. Their ids go in `src/shared/Attractions/LoungeClassic.luau` (`JAZZ`). The wanted feel is listed in `docs/AUDIO_BUDGET.md`: 1920s hot jazz, stride piano, a slow ballad and light swing.
- **Four sound cues,** also from the library: the guard's swat, the door, the bar's bell and a pour.

## Questions for you (each already has a default built in)
1. **Drinks cost money; they are not free with the pass.** They cost 6c to 12c, the prices already set for the lounges, so they are cheap. A pass that also paid for drinks would make it a better deal. Say if you want them free with the pass.
2. **A drink has no effect.** People in this game have no stamina, so a drink is only for the look. A small effect, such as a short walking-speed boost, could be added. Say if you want one.
3. **What "annihilate" means here.** It is the game's own knock-out: the player goes back to the menu and picks a new body, as after being run over. The guards do this to any squirrel on the forecourt, the steps or the landing, not only one pressing the door. Computer squirrels are sent home the same way.
4. **The guards and the bartender are built from parts**, like the game's placeholder people. Proper people models would come with the people art (`art/people`, parked).
5. **The front is a forecourt to Bowl Lane's planned sidewalk.** When Bowl Lane is built, its sidewalk meets the forecourt.

## Not done yet
- Nothing has run in the engine yet: the cloud check `tools/cloud/tasks/lounge_smoke.luau` is written but not run. It needs the key's Luau Execution permission.
- Not yet checked on a screen: the drink in the hand (a cup welded to the body's root, not to the hand) and the guard's step.
- Nobody sits on the stools or in the booths yet.
