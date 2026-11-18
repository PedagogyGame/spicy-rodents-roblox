# Bowling: what to look at (10 to 15 minutes)

Bowling is the first minigame taken to completion. Everything below has been tested without a screen. What a test cannot tell me is how it looks and feels, so this is the list of things only you can judge. Tell me what you pressed and what happened wherever something is off.

## One decision I need from you
Your brief says "physics pins". I did not use Roblox physics for the pins. The server works out each throw itself the moment you let go (where the ball goes, which pins fall) and every screen then draws that same throw. The pins still tip over, slide, bounce off the side walls and drop into the pit.

Why: Roblox physics gives slightly different results on different computers and does not run at all in my test setup. With physics pins the score could differ from what you saw, and I could never have tested a throw.

**Please say yes or no to this.** If you want real physics pins, only one part of the code changes.

## How to play
1. Pick **Townsperson** or **Police** from the menu (only people can bowl) and walk into the bowling alley.
2. Walk up to a lane. A prompt says **Bowl: Lane 3 - open**. Press **E**.
3. You are in the lobby for 8 seconds so friends can join. **Space** starts at once. **Add a computer** gives you an opponent (press it up to three times: Bowlbot is average, Gutter Gus is weak, Strike Sally is good).
4. On your turn:
   - **A / D** step left and right along the line.
   - **Mouse** (or **Left / Right** arrows) turns your aim. A dotted line on the lane shows where the ball will go, two thirds of the way down.
   - **Z / X** or the **mouse wheel** add hook. The ball bends late; the dots turn orange where the bend begins.
   - **Hold Space** (or the mouse button): the power meter runs up and down. **Let go in the green band** and the ball goes exactly where you aimed. Full power is fast but wild.
5. **Q** leaves at any time. **H** hides the help card.

Aim just to the right (or left) of the front pin: that is the pocket, and it is where strikes come from. Dead centre often leaves a split.

## Please check
| # | What to look at | What you should see |
|---|---|---|
| 1 | The prompt at a lane | "Bowl" and the lane's name; "Join" while a lobby is open; "In use" during a game |
| 2 | Aiming | The camera behind your person, the dotted line following your keys and mouse, the hook pips under the meter, a status line naming the keys |
| 3 | The throw | The ball rolls at a believable speed, a hook bends on the far half, a wide ball drops into the gutter and stays there |
| 4 | The pins | A pocket hit usually clears them; a centre hit leaves pins; fallen pins tip the way they were pushed and slide. Does it look right, or too tidy? |
| 5 | The camera | It rides behind the ball, cuts once to a low view of the pins just before the ball arrives, holds, then returns to you. It must give your own camera back every time, also after Q in mid-throw |
| 6 | Smoothness | The ball and pins should move smoothly. Tell me if you see stutter, or pins jumping when the sweep bar starts |
| 7 | The pinsetter | The bar comes down, standing pins lift and are set back (or ten new ones come down), the ball comes home to the rack. About four seconds |
| 8 | Scoring | The sheet at the bottom right and the monitor over the lane: X for a strike, / for a spare, - for a miss, running totals. The tenth frame gives a third ball after a strike or spare |
| 9 | The turn clock | Top of the screen, 60 seconds. Under 15 it warns "Bowl within N seconds or your turn is skipped". Let it run out once: the frame is skipped and says so. Twice in a row takes you off the lane |
| 10 | A computer opponent | It takes its turns by itself about two seconds after the lane is ready, and its score looks like its skill |
| 11 | The end | A card with places, scores, strikes, spares, misses, **Play again** and **Leave**, and "The lane resets in N s" |
| 12 | A squirrel on the lane | Play as a squirrel in a second window (or ask a friend) and run onto a lane during a game. The ball knocks it into the gutter. The bowlers read "A squirrel ran onto the lane: the ball knocked it into the gutter. The throw counts." The squirrel reads "A bowling ball knocked you off the lane!" |
| 13 | Typing | Typing in chat during your turn must not move you or throw the ball |

## Known limits
- **No sound yet.** The moments for the sounds exist (roll, pins, gutter, strike), but nothing has been uploaded.
- **Your person does not swing an arm.** They slide to the line and the ball leaves the hand.
- **Phones and tablets:** there are touch buttons for everything, but I have not seen the layout on a small screen.
- **First-person view:** if you bowl in first person, the mouse still aims, but I could not check that view.
