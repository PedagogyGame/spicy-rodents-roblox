# Whack-a-mole: what to look at (about 10 minutes)

This is your whack-a-mole from the 18 November delivery, the tenth game. It stands in the bowling alley's games room, against the front wall, just to the right of the three pinball machines. The rules are your browser game's. Everything below has been tested without a screen. What a test cannot tell me is how it looks and feels, so this is the list of things only you can judge.

## What it is
- **Your rules, from `Play_Whack_A_Mole.html`:**
  - five holes and a 45-second round;
  - +10 for a hit, -2 for a miss, and the score never goes below zero;
  - a mole that is already hit and dropping scores nothing either way;
  - the first mole comes at 0.3 seconds;
  - after that, a new mole is tried every 0.76 seconds, getting down to 0.34 by the end, plus up to 0.19 seconds at random;
  - a mole stays up 1.55 seconds, getting down to 0.95 by the end, plus up to 0.22 seconds at random;
  - one mole at a time for the first 35% of the round, then two at a time;
  - a mole never comes up in the same hole twice in a row;
  - a mole rises in 0.17 seconds and drops in 0.21;
  - a hit counts once the mole is 22% of the way up, until just before it starts to drop.
- **Your Blender play script is a little different.** It has one mole at a time, rises in 0.13 seconds and drops in 0.14. I used the browser version, because it is the one you described as the game.
- **What I added:** a three-second count-in (**READY 3, 2, 1, GO!**), so the first mole does not come while the camera is still moving.
- **The server keeps score.** Your screen sends only which hole you struck and when. The server judges the hole as it was at that moment, so a player on a slow line still scores what they saw.
- **Free play.** No coins, ever. Your coin slot and coin return are now a **FREE PLAY** plate.
- **Watching.** Anyone within 40 studs sees the same moles, mallet and score as the player.
- **Best scores.** The cabinet keeps a board of the best five rounds for as long as the server runs, with each player's name. It starts with five house scores to beat: MIDNIGHT 400, COCOA 300, TAUPE 220, CHARCOAL 150 and LITTLE NOSE 80. Your own best is kept too.

## How to play
1. Pick **Townsperson** or **Police** (only people can play), walk into the bowling alley and go through to the games room. The cabinet is on the front wall, beside the pinball machines.
2. Press **E** at the cabinet (**Play: Whack-a-Mole (free play)**). The camera moves over the deck, and the count-in starts.
3. To strike:
   - **Mouse:** click a mole.
   - **Touch:** tap a mole.
   - **Keys:** 1, 2, 3 are the back row from the left, and 4, 5 are the front row. The numbers are painted beside the holes, as on your deck.
   - **Gamepad:** the D-pad's left, up and right are the back row, and LB and RB are the front row.
4. **Q** (gamepad **B**, or the Leave button) leaves. At the end, **Play again** (Space, or gamepad A) starts the next round.

## Please check
| # | What to look at | What you should see |
|---|---|---|
| 1 | The cabinet | Your red and gold cabinet, green deck, five holes with brass lips, the WHACK A MOLE sign with SCORE and TIME windows, the bulbs, the mallet in its bracket and FREE PLAY on the front. It is built from plain parts for now (149 parts). The game version of your mesh is ready but not uploaded (see below). Pictures: `docs/renders/minigames/whack_a_mole/bake_*.png` |
| 2 | Its place | Beside the pinball row, about the same height as the pinball machines (7.7 studs). Is there room to stand, and room for friends to watch from either side? The plan is `00_plan_games_room.png` in the same folder. |
| 3 | The camera | From just behind your head, looking down at the deck, with both windows in view. All five holes should be on screen on a wide monitor and on a phone. |
| 4 | The moles | They should pop up quickly, wait, then drop. When you hit one, it should drop at once, with no wait for the server. A mole that the server says you missed comes back up (this should be rare). |
| 5 | The mallet | On every strike it swings from the bracket to the hole and down, waits over that hole for a second, then goes back to the bracket. |
| 6 | The windows | SCORE counts up as you hit and TIME counts down from 45. The line under them says READY, GO!, NICE! +10, MISS -2, TIME!, and FREE PLAY - PRESS E when nobody is playing. Watchers see the same. |
| 7 | The pace | Does it feel like your browser game, getting faster and busier towards the end? |
| 8 | Leaving | Walk away from the cabinet, or press Q, in the middle of a round. The round ends, and your camera and walking come back. |
| 9 | Sound | Nothing yet: the sounds are named but no audio has been chosen. They are pop, swing, bonk, thud, count, go, hurry and over (`whack_a_mole.<name>`). |

## Your model: what was made from it
Your GLB is 232,092 triangles in 246 pieces, about 15 times the cost of one pinball machine. The game version is made from your `.blend` by `tools/blender/whack_a_mole/export.py`. It comes to **12,168 triangles in 42 pieces**:

| Part | Triangles | How |
|---|---|---|
| The cabinet | 6,622 | Merged into one mesh per material (wood, ebony, brass, gold, leather, the dark hole interiors, the bulbs). Your large panels keep their rounded edges; thin trims are plain boxes; the hole lips and bulbs are simplified. |
| Five moles | 4,800 (960 each) | Each mole is six pieces (fur, muzzle and paws, nose, eyes, eye sparkle, teeth and claws), so it can move on its own. |
| The mallet | 746 | Its own model, pivoting at the bottom of the handle as in your file. |
| Left out | 127,660 | Your lettering. The game writes WHACK, A MOLE, MIDNIGHT, THE MIDNIGHT ARCADE, the hole numbers and the live numbers as text, which costs nothing and stays sharp. |
| Left out | 1,072 | The coin slot, coin return and their label, and the hidden floor inside the cabinet. |

The pictures put your model and the game version side by side, from your Preview's angle, from the player's view and close on the moles: `art_*.jpg`. The look survived. The moles' heads are a little less round up close, and your fine wood grain is in the `.blend` only (it was not in your GLB either).

**Not uploaded yet.** The upload step is written and ready. Until it runs, the game shows the plain-part cabinet. Once it runs, the loader puts your meshes over the cabinet with nothing else to change.

## Known limits
- **Nothing has run in the real engine yet.** The engine check is written (`tools/cloud/tasks/whack_a_mole_flow.luau`) but has not been run.
- **The mouse and touch aim** works from the shapes of the moles' heads and bodies as they stand on your screen. It is a little more generous than the drawn mole, so a click near the edge still counts. Clicking a hole's mouth with no mole in it is a miss, as on your deck.
- **Idle players.** A player who strikes nothing for 20 seconds is taken off.
- **Best scores are not saved.** The board and your best last only as long as the server runs, as on the pinball machines.
