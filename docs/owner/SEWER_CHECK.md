# The storm drains: what to look at (10 minutes)

Your words (addendum D8): "a few underground pipes that the squirrel can run through, like a short cut or two through a system under the city, just basic sewers". There are three. A squirrel or the Spicy Rodent goes down a grate, runs the pipe, and climbs out somewhere else. People, the fox and the deer cannot go down. The police lose the rodent at the grate.

Everything below has been tested without a screen. The real squirrel controls were driven through the real pipes, and the town's people and police were run against it. A test cannot tell me how it looks and feels, so this is the list of things only you can judge. Two of your defaults are not met yet: walking onto a grate also takes you down, and drain 3 is not quicker than going over the top. Both are explained under **Known not done**.

## Before you build
The pipes are their own bake, like the bowling alley. Run `lune run tools/bake/sewers.luau` before `rojo build`. Without the bake the game prints a warning, leaves the ground whole and hides nobody. But the routes are still there, so a squirrel pressing E at an unmarked corner would go down into the ground. Always bake before you publish.

## Where the drains are
The game's map has east on the left of the x axis, so the drains are named by what stands beside them, not by the compass. "Walk in facing" is the way to face to go down. The words on screen use it too.

| Drain | Way in or out | Where | Walk in facing |
|---|---|---|---|
| **1. The crossroads** (under the Main Street / Centre Street crossing, 4 arms) | corner grate by the brick house | on the grass at the corner, (-24.6, 24.6) | Main Street |
| | corner grate by the blue cottage | (24.6, 24.6) | Centre Street |
| | corner grate by the bungalow | (24.6, -24.6) | Centre Street |
| | corner grate by the Victorian house | (-24.6, -24.6) | Main Street |
| **2. The old river culvert** (under the river, quay to quay) | town-side quay access cover | (1960.7, 462), on the quay walk | the river |
| | far-side quay access cover | (2335.4, 462) | the river |
| **3. Bowl Lane** (bowling alley's doors to Main Street) | bowling alley lawn grate | (1306, -335.4), on the lawn in front of the alley | Bowl Lane |
| | Main Street north verge grate | (1350, 37.4) | the boulevard |

## What to press
1. Pick **Squirrel** or **Spicy Rodent**. Run to a grate and stand on it. Facing the right way, the screen says **E or W: down the drain**. Facing another way, it tells you which way to turn, for example **Turn left to face Main Street: walking in or E goes down the drain**.
2. Press **E** (or keep walking in). The squirrel goes down the ladder shaft.
3. Hold **W**. The squirrel runs the way the camera looks, as on a branch.
4. In drain 1, as you run at the crossing the screen says **The crossing: A or D there turns into a side arm**. Then, in the last 6 studs, it says **A / D now: a side arm (W: straight on)**. Press A or D then; a press made earlier is not kept. Once past the crossing it tells you which way you went and where you will come out, for example **Straight on: out at the corner grate by the bungalow**.
5. At the top of the far shaft the screen says **W: climb out**. Keep holding W and you come out on your feet, still running. For a second after that the screen says nothing about going back down.
6. Try **Space**, **Q** or a click in the middle of a pipe. Nothing happens, and the screen says **No room to jump down here: run on to a grate (W at the top climbs out)**.

## Is it quicker?
Measured with W held, on the real squirrel controls, against the way over the top:

| Drain | In the pipe (walk / sprint) | Over the top (walk / sprint) | Quicker? |
|---|---|---|---|
| 1, corner to corner | 5.1 s / 3.0 s | 6.3 s / 3.5 s round the pavements | yes, a little. A straight dash across the junction through the traffic (about 3.9 s walking) is quicker still |
| 2, quay to quay | 24.7 s / 19.0 s | 79.4 s / 62.1 s round by the bridge | yes, by far |
| 3, lawn to verge | 22.2 s / 17.0 s | 20.9 s / 15.2 s straight across | **no**: the pipe is longer than the straight line because of its two ladder shafts. With the 1.25 times pipe pace it would take 17.8 s / 13.6 s and win |

## Please check
| # | What to look at | What you should see |
|---|---|---|
| 1 | Each grate from the pavement | An iron grate in a frame, level with the street. Drain 2's ways in are solid iron covers on the quay. Drain 3's lawn grate sits in a concrete surround on the lawn, clear of the alley's forecourt. The pictures are in `docs/renders/sewers/` (`*_street.jpg`) |
| 2 | Going down | Into the shaft, past the iron rungs, and onto the walkway at the foot of the ladder |
| 3 | Inside | Your modules round you: the brick passage in drains 1 and 3, your four-way junction under the crossing, your dry maintenance tunnel and its "Dry Side / Mind Your Paws" plaque in drain 2. They are drawn for about 48 studs around the squirrel and follow it as it runs. Also a darker, cooler picture, the drain's own lamps near you, an echo on the sound, and the name at the top, e.g. **UNDERGROUND · STORM DRAIN 1 CROSSROADS**. When you come out, all of it goes back, and the game's lighting is never changed. The pictures: `p1_chamber.jpg`, `p2_1_run33.jpg`, `p3_1_run33.jpg` and the other views without `_parts` |
| 4 | If your modules do not show | The drain is drawn in plain brick-coloured parts instead (the `_parts` pictures), and F9 shows a line starting `[SewerArt]` or `sewer module`. Please send me that line |
| 5 | Drain 1's chamber | Your junction, light from the manhole lid, and the fashion stand beside the crossing (only a stand to look at for now) |
| 6 | The police | As the Spicy Rodent, go down a grate while a policeman is looking at you. He walks to that grate, stands about 6 studs from it facing it, says **"It went down the drain!"** and goes back to his beat about 15 seconds later. He never goes to the other end. If you come back up where he can see you, he stops watching and comes after you. Diving in and out of the same grate does not keep him there: a grate is watched once every 15 seconds. One or two people who saw it may say something too ("Where did it go?"). An ordinary squirrel gets remarks, but no policeman |
| 7 | Hidden | While you are down a drain, nobody sees or hears you and the fox does not hunt you. You cannot bite from there either, even from the top of the ladder right under someone's feet. You are seen again as soon as you are out |
| 8 | Healing | As the Spicy Rodent, after biting someone (within one game day, 12 minutes), rest in a drain: your health creeps back up at the hollow tree rate, about 5 points a minute. If you have not bitten anyone in that time, it does not |
| 9 | The alligator (optional, slow) | Stand still in a pipe for 12 and a half minutes: the line "A low hiss and a ripple in the sewer water…". There is no sound yet and nothing to see. Skip this one unless you have the time |

## Known not done
- **Walking onto a grate takes you down too.** You asked for E only. The run-through mechanic has no "E only" way in, and I may not change the movement code, so it is waiting on the movement lane. Today a squirrel on a grate that walks into the opening goes down, and so does one that turns toward it. The words on screen say exactly that. A squirrel running across a grate, or out of it from the ladder side, does not go down.
- **Drain 3 is not a short cut yet.** The pipes run at street pace. The 1.25 times pace is stored, but the movement code does not read it yet (the same movement lane). Drains 1 and 2 already beat the way over the top; drain 3 will once the pace is read.
- **The crossing's A / D works only in the last 6 studs.** The screen says when. A wider window, or keeping a press made earlier, is a change to the movement code.
- **Your modules have not been seen in Roblox yet.** They are loaded when the server starts and drawn near the squirrel. I have checked the placement only in Blender and in tests without the engine. If Roblox imports one turned or mirrored, the game notices and shows plain parts for that drain, so it never looks broken. The engine check is written (`tests/engine/Sewers.luau`, task `tools/cloud/tasks/sewers_smoke.luau`). It cannot run until the key's Luau Execution permission is restored.
- **A dead rodent does not come back out of a drain.** The rule (a drain at least 100 studs away with nobody near) is written, but the role ladder that would use it is not running in the game yet. The same goes for the alligator's warning before an idle body is let go.
- **Policemen only react to what they saw themselves.** There is no chase yet, so nobody follows the rodent to a grate.
- **No sound.** Every sound is a named cue with no recording behind it (drips, the trickle, the river's hum, the rungs, the footsteps' echo, the grate, the alligator's hiss), listed in `docs/AUDIO_BUDGET.md`. Cars and the trolley overhead are named but never played.
- **Computer squirrels never use the pipes.**
- **The fashion stand is a stand to look at.** Buying from it is not built.
- **From the bowling alley's doors to the lawn grate is a small jump.** The alley's forecourt is cut 1.5 studs below the lawn. The grate now sits 4 studs into the lawn, so no brick shows and you climb out onto grass. Steps up from the forecourt belong to the alley's own work.
- **Nothing here has been seen in the engine or in Studio.**
