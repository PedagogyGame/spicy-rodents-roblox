# The storm drains: what to look at (10 minutes)

Your words (addendum D8): "a few underground pipes that the squirrel can run through, like a short cut or two through a system under the city, just basic sewers". There are three. A squirrel or the Spicy Rodent goes down a grate with **E**, runs the pipe, and climbs out somewhere else. People, the fox and the deer cannot go down. The police lose the rodent at the grate.

Everything below has been tested without a screen: the real squirrel controls were driven through the real pipes, and the town's people and police were run against it. What a test cannot tell me is how it looks and feels, so this is the list of things only you can judge.

## Before you build
The pipes are their own bake, like the bowling alley. Run `lune run tools/bake/sewers.luau` before `rojo build`. Without it, the game starts with no drains, prints a warning, and leaves the ground whole.

## Where the drains are
| Drain | Way in or out | Where | Face this way to go down |
|---|---|---|---|
| **1. The crossroads** (under the Main Street / Centre Street crossing, 4 arms) | north-west corner grate | at the kerb on the corner, (-24.6, 24.6) | south |
| | north-east corner grate | (24.6, 24.6) | west |
| | south-east corner grate | (24.6, -24.6) | west |
| | south-west corner grate | (-24.6, -24.6) | north |
| **2. The old river culvert** (under the river, quay to quay) | west quay access cover | (1960.7, 462), on the quay walk | east |
| | east quay access cover | (2335.4, 462) | west |
| **3. Bowl Lane** (bowling alley's doors to Main Street) | bowling alley lawn grate | (1306, -339.4), in front of the alley | north |
| | Main Street north verge grate | (1350, 37.4) | south |

The words on screen tell you when you are on a grate but facing the wrong way.

## What to press
1. Pick **Squirrel** or **Spicy Rodent**. Run to a grate and stand on it. When you face the right way, the screen says **E: down the drain**.
2. Press **E**. The squirrel goes down the ladder shaft.
3. Hold **W**. The squirrel runs the way the camera looks, as on a branch. In drain 1's chamber, **W** goes straight on, and **A** or **D** turns into a side arm.
4. At the top of the far shaft the screen says **W: climb out**. Keep holding W and you come out on your feet, still running.
5. Try **Space**, **Q** or a click in the middle of a pipe. Nothing happens, and the screen says **No room to jump down here: run on to a grate (W at the top climbs out)**.

Times with W held: drain 1, corner to corner, about 5 seconds (the way round on the pavements is 113 studs, across two roads). Drain 2, about 25 seconds (round by the bridge is 1,430 studs). Drain 3, about 22 seconds (across Bowl Lane, the boulevard and the trolley rails is 379 studs).

## Please check
| # | What to look at | What you should see |
|---|---|---|
| 1 | Each grate from the pavement | An iron grate in a frame, level with the street. Drain 2's ways in are solid iron covers on the quay. The pictures are in `docs/renders/sewers/` (`*_street.jpg`) |
| 2 | Going down | Into the shaft, past the iron rungs, and onto the walkway at the foot of the ladder |
| 3 | Inside | A darker, cooler picture; the drain's own lamps light up (shadows from the two nearest only); an echo on the sound; the name at the top, e.g. **UNDERGROUND · STORM DRAIN 1 CROSSROADS**. When you come out, all of it goes back, and the game's lighting is never changed |
| 4 | Drain 1's chamber | Where the four arms meet (a rough copy of your junction in plain parts for now), light from the manhole lid, and the fashion stand beside the crossing (only a stand to look at for now). With your junction loaded (not yet, see below): your four arches, vaulted centre and sump grate, as in `p1_chamber.jpg` |
| 5 | Drain 2 | A long dry tunnel under the river (a rough copy in plain parts for now). With your modules loaded: your concrete maintenance tunnel, and your "Dry Side / Mind Your Paws" plaque at the foot of each ladder (`p2_1_run33.jpg`) |
| 6 | Drain 3 | A brick pipe with a water channel beside the walkway (a rough copy in plain parts for now), and light falling through a small grate in the boulevard. With your modules loaded: your brick passage (`p3_1_run33.jpg`) |
| 7 | The police | As the Spicy Rodent, go down a grate while a policeman is looking at you. He walks to that grate, stands over it facing it, says **"It went down the drain!"** and goes back to his beat about 15 seconds later. He never goes to the other end. One or two people who saw it may say something too ("Where did it go?"). An ordinary squirrel gets remarks, but no policeman |
| 8 | Hidden | While you are in a pipe, nobody sees or hears you, and the fox does not hunt you. You are seen again as soon as you are out |
| 9 | The alligator | Stand still in a pipe for 12 and a half minutes: a hiss and the line "A low hiss and a ripple in the sewer water…". It is never seen |

## Known not done
- **Your meshes are not in the game yet.** The six models are uploaded and approved, and the bake marks where each one goes. But the code that loads them into place when the server starts is not written, so the game shows plain brick-coloured walls. Your modules only show in the renders made from them (for example `docs/renders/sewers/p1_chamber.jpg`, against `p1_1_run50_parts.jpg`). This needs the server check permission back too, to see that they arrive upright.
- **Walking onto a grate can still take you down.** You asked for E only. The run-through mechanic has no "E only" way in yet. Today a squirrel running straight at a grate from its ladder side, within about 60 degrees, goes in. Across it, or from the other three sides, it does not. The screen only promises E.
- **The pipes run at street pace, not 1.25 times.** The 1.25 is stored on every pipe, but the squirrel's movement does not read it yet. Every pipe still beats its way over the top.
- **The rodent does not heal in a pipe.** The game has no healing over time yet. The drain's rate (the hollow tree rate, only while fed) is written and waiting for it.
- **A dead rodent does not come back out of a drain.** The rule (a drain at least 100 studs away with nobody near) is written, but the role ladder that would use it is not running in the game yet.
- **Policemen only react to what they saw themselves.** There is no chase yet, so nobody chases the rodent to a grate.
- **No sound.** Every sound is a named cue with no recording behind it (drips, the trickle, the river's hum, the rungs, footsteps' echo, the grate, the alligator's hiss), listed in `docs/AUDIO_BUDGET.md`. Cars and the trolley overhead are named but never played.
- **Computer squirrels never use the pipes.**
- **The fashion stand is a stand to look at.** Buying from it is not built.
- **Drain 3's south grate** sits by the bowling alley's front, which the eighteen-lane alley is rebuilding. A strip of the shaft's brick shows from the forecourt (`p3s_street.jpg`) until that lands.
- **Nothing here has been seen in the engine.** The checks that run inside Roblox are written (`tests/engine/Sewers.luau`: the ground cut away along every pipe, the street left whole over it, your modules imported upright). They cannot run until the key's Luau Execution permission is restored.
