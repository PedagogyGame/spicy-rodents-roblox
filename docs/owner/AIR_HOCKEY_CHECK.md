# Air hockey: what to look at (10 to 15 minutes)

This is your AER / 01, standing in the bowling alley's games room along the back wall, beyond the bumper pool. The simulation is yours, unchanged: it was ported line for line and checked against your own `physics.js` over 58 scripted and seeded cases (12,415 states, every one the same to the last bit), and your C++ checks pass on it. Everything below has been tested without a screen. What a test cannot tell me is how it looks and feels, so this is the list of things only you can judge.

## One thing I found in your simulation
A mallet pushed straight at a puck that rests against a side rail squeezes the puck out through the rail in about fifteen steps, and it never comes back, so the match never ends. It happens in your JavaScript with the same inputs. I did not change your step. Outside it, the table has one rule of its own: a puck that has left the table is put back on the serve spot for the side that conceded last. **Say if you would rather fix it in the simulation itself.**

## How to play
1. Pick **Townsperson** or **Police** (only people can play) and walk into the bowling alley, then through the games room to the back wall.
2. Walk up to either end of the table. The prompt says **Play air hockey: Air hockey (Glacier end)** or **(Ember end)**. Press **E**: that end is yours.
3. You are in the lobby for 8 seconds so a friend can take the other end. **Space** starts at once. If nobody comes, the computer plays the other end: choose **Lounge (easy)**, **Club (medium)** or **Pro (hard)** first.
4. You look down the table from your end, as in your game.
   - **Mouse**: your mallet goes to the point of the table under the pointer.
   - **WASD / arrows / left stick** push it instead. On a phone, **drag a finger anywhere** and the mallet moves as far as the finger does.
   - Move the mallet through the puck to strike it. Hold it still to block. It stays in your half.
   - **Space** (or a click, gamepad **A**, a tap) serves at once while the puck waits.
   - **V** (gamepad **X**) swaps to the view from above and back.
5. First to seven. **Q** leaves at any time. **H** hides the help card.

A second person can press **E** at either end while you play the computer: they take the computer's end at once, mid-match. If they leave, the computer takes it back.

## Please check
| # | What to look at | What you should see |
|---|---|---|
| 1 | The table | It should read at a glance as your table: the pale bed with its centre circle and creases, the dark frame, the goal lit glacier blue at one end and ember orange at the other, the two mallets, the puck, A E R on the bed. It is built from 131 plain parts; your mesh is not uploaded yet. Pictures: `docs/renders/minigames/air_hockey/` |
| 2 | Its size and place | Beside the pool tables it should look the right size (one metre is the same number of studs as on the pool felt). Is there room to stand at each end and to walk past? |
| 3 | Your mallet | **This is the one that matters most.** It must be under your hand with no delay at all, at any frame rate. Nothing about your own mallet waits for the server |
| 4 | The puck against the computer | Smooth, never stuttering, never corrected. On your screen this is your single-player game exactly; the server replays your hand and gets the same match |
| 5 | The puck against a person | In your half it is live. In the far half you see the other player's mallet and the puck a moment late (between one and two tenths of a second on a good connection): their real hand, never a guess. A puck you send away slows a little as it crosses the middle; one coming back is quickened for two or three frames to catch up. **Tell me if either of those bothers you** |
| 6 | The two views | First person from your end by default; **V** gives the view from above with your end at the bottom. The mouse steers in both |
| 7 | The serve | After a goal the puck waits on the side that let it in and is served toward the scorer after 1.25 seconds, or at once on Space |
| 8 | The words | READY WHEN YOU ARE, BEAUTIFUL SHOT, EMBER SCORES, MATCH WON, WELL PLAYED: yours. The score is on the card at the bottom right and on the board on the wall behind the table |
| 9 | The computer | Lounge should be beatable, Club a game, Pro hard. They are your three difficulty numbers |
| 10 | Watching | Stand near the table while two others play (or a second window): you see the same match on the same table, smooth, a moment late |
| 11 | Leaving | Q or walking away (and being bitten at the table, which goes the same way through the shared minigame code): your camera and legs come back at once. The other player carries on against the computer |
| 12 | Typing | Typing in chat during a match must not move the view or serve |

## Known limits
- **No sound yet.** Every sound is a named cue with no asset behind it: strike (louder the harder), rail, post, serve, goal for you, goal against you, a goal at a table you are watching, match won, match lost. Your game makes its tones in code; ours may not at run time, so each needs a short recorded sound.
- **The look is parts, not your mesh.** The 1,500 air jets and the bevels are left out; the GLB is kept in `docs/reference/air_hockey/` for an upload later.
- **On a slow connection against a person**, a fast shot from the far end can be in your half before your screen has been told of it (at 80 ms each way, about one frame in four with the puck in your half; at 150 ms more than one in three). Nothing can show it sooner; what is shown is never wrong, only late. Against the computer this does not arise.
- **The other player's early serve** (their Space during the countdown) is the one thing drawn a moment late and then eased into place.
- Your Tab (switch ends) is not there: you choose your end by the prompt you press. P (pause) and R (reset) are not there either: it is a shared table.
- No server check has been run in the real engine yet (they cannot be run at present); the flow is written and passes on the test rig.
