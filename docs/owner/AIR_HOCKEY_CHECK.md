# Air hockey: what to look at (10 to 15 minutes)

This is your AER / 01, standing in the bowling alley's games room along the back wall, beyond the bumper pool. The simulation is yours: it was ported line for line and checked against your own `physics.js` over 58 scripted and seeded cases (12,415 states, every one the same to the last bit), and your C++ checks pass on it. Everything below has been tested without a screen. What a test cannot tell me is how it looks and feels, so this is the list of things only you can judge.

## What changed since the first version
Two reviewers played it on the test rig, one for whether it plays right and one for how it feels in the hand. What they found, and what is done about it:
- **The puck pinched against a rail.** Your step lets it out through the rail (see 1 below). It is now held in and the rally goes on, and the player reads **PINCHED. PLAY ON.**
- **Against a person the puck skipped and crawled**, even with no delay on the line. The far end is now a quarter less late (58 thousandths of a second with no delay, was 74), and a far mallet that charges the puck is planned for, so the puck no longer stops dead. Figures are under Known limits.
- **On a phone the HUD covered half the table.** A phone now opens from above, the help card is put away when the match starts (a HELP button brings it back), the status line only shows while the puck waits, the scorecard is a strip in the top corner, and the words (a goal's, PINCHED) are said beside the bed. Nothing lies over the bed on an 844 by 390 or a 667 by 375 screen.
- The rest: the winner hears the winner's sound and the serve is heard every time the puck is let go; you are stood on the mat at your end and your arm reaches for your mallet on everyone else's screen; a stick and Shift with the keys move the mallet at full speed; after V the mallet stays under a still pointer; a goal is said once; your score is lit in the bed at your end; a lost piece of the log mends itself without words; typing in chat moves nothing; a second press of Space, Play again or Q is not refused; a player on a line too slow for a live match is told so.

## Three things for you to decide

### 1. Your rails let the puck out, so the table now holds it in
In your step, a mallet that presses the puck against a rail squeezes it out through the rail, and it never comes back. It happens in your JavaScript with the same inputs. It is not rare: in an ordinary match it happened one to four times, and with the plainest mouse hand (the pointer put on the puck) about seven times a match at every level. The computer's own mallet did it too.

I did not change your step. After each of your steps, outside it, the table has one rule of its own. Exactly:
- if the puck's centre has ended up past a rail's face (a side rail, an end rail beside the goal, a wall of the goal slot or a post), it is put back on that face and its speed across the face is turned inward (times your rail restitution, 0.95);
- if a mallet is still on top of it there (that is how it got out), it is slid along the rail to that mallet's edge, the nearer way, and given the speed it would have off that mallet (your mallet restitution, 0.94);
- it is counted as a contact, so the rail or the strike is heard, and the player reads **PINCHED. PLAY ON.** for a moment (not again within three seconds);
- nothing else: a step that ends on the table is still your step to the last bit, and the old answer (the puck put back on the serve spot) is kept only as a net under this, which nothing has reached.

Measured with that pointer hand, 12 matches a level: the rails held 7.0, 6.6 and 6.8 times a match against Lounge, Club and Pro, the puck popped 6 to 9 cm along the rail (16 cm at most, in one step), and no puck left the table. **Look at a pinch** (push the puck into a side rail and hold it there): it should read as the puck squirting out from under the mallet.

**Say if you would rather fix the rail test in the simulation itself**, and how.

### 2. Your three opponents, measured
They are your three difficulty numbers, unchanged. Played to seven against three simple hands (the same result every time, recorded in `tests/unit/air_hockey_opponents.spec.luau`):

| Hand | Lounge | Club | Pro |
|---|---|---|---|
| A mallet that never moves | wins 7-6 | loses 0-7 | loses 0-7 |
| A goalkeeper under the puck who never strikes | wins 7-0 | wins 7-2 | loses 1-7 |
| The pointer put on the puck (12 matches) | wins 8, goals 74-57 | wins 2, goals 51-76 | wins 2, goals 33-79 |

So Lounge loses to a player who does nothing, because it puts the puck in its own goal, and a goalkeeper who never hits the puck beats Club. Your own `physics.js` gives the same still-mallet result. **Is that what you want from Lounge and Club?** I have not touched the numbers.

### 3. The keys are slower than the mouse
Your keyboard speed is 1.8 metres a second. The mouse, a finger and a stick held fully over move the mallet at its full 3.5. The same hand won 19 of 20 matches against Club at the mouse's speed and 7 of 20 at the keys' speed (11 and 3 against Pro). I kept your 1.8 and added one thing: **hold Shift** and the keys move the mallet at 3.5. **Say if the keys should simply be faster.**

## How to play
1. Pick **Townsperson** or **Police** (only people can play) and walk into the bowling alley, then through the games room to the back wall.
2. Walk up to either end of the table. The prompt says **Play air hockey: Air hockey (Glacier end)** or **(Ember end)**. Press **E**: that end is yours, and you are stood on the mat behind it.
3. You are in the lobby for 8 seconds so a friend can take the other end. **Space** starts at once. If nobody comes, the computer plays the other end: choose **Lounge (easy)**, **Club (medium)** or **Pro (hard)** first.
4. You look down the table from your end, as in your game.
   - **Mouse**: your mallet goes to the point of the table under the pointer.
   - **WASD / arrows** push it (Shift: full speed). The **left stick** pushes it, gently near the middle and at full speed held over. On a phone, **drag a finger anywhere** and the mallet moves as far as the finger does.
   - Move the mallet through the puck to strike it. Hold it still to block. It stays in your half.
   - **Space** (or a click, gamepad **A**, a tap, the SERVE button) serves while the puck waits.
   - **V** (gamepad **X**, the VIEW button) swaps to the view from above and back.
5. First to seven. **Q** (gamepad **B**) leaves at any time. **H** (gamepad **Y**, the HELP button) hides and shows the help card.

A second person can press **E** at either end while you play the computer: they take the computer's end at once, mid-match. If they leave, the computer takes it back.

## Please check
| # | What to look at | What you should see |
|---|---|---|
| 1 | The table | It should read at a glance as your table: the pale bed with its centre circle and creases, the dark frame, the goal lit glacier blue at one end and ember orange at the other, the two mallets, the puck, A E R on the bed. It is built from plain parts; your mesh is not uploaded yet. Pictures: `docs/renders/minigames/air_hockey/` |
| 2 | Its size and place | Beside the pool tables it should look the right size (one metre is the same number of studs as on the pool felt). Is there room to stand at each end and to walk past? |
| 3 | Your mallet | **This is the one that matters most.** It must be under your hand with no delay at all, at any frame rate. Nothing about your own mallet waits for the server |
| 4 | The puck against the computer | Smooth, never stuttering, never corrected. On your screen this is your single-player game exactly; the server replays your hand and gets the same match |
| 5 | The puck against a person | Your own half is live: where your mallet meets the puck, the puck you see is the real one. The far end is shown a moment late (the other player's real hand and the real puck, never a guess). A shot you send away is drawn a little slower all the way down. A shot coming back hurries across the far half to be real again by the time it reaches you. On a good connection you should hardly see either; a hard shot sent back from the centre line still hurries visibly. **Tell me if either bothers you** |
| 6 | The two views | First person from your end by default; **V** gives the view from above with your end at the bottom. The mouse steers in both, and after V the mallet is still under the pointer |
| 7 | The serve | After a goal the puck waits on the side that let it in and is served toward the scorer after 1.25 seconds, or at once on Space. Against a person a press lets the puck go 0.4 seconds later, so both screens know before it moves |
| 8 | The words and the score | READY WHEN YOU ARE, BEAUTIFUL SHOT, EMBER SCORES, MATCH WON, WELL PLAYED: yours, each said once. The score is on the card, on the board on the wall for the room, and lit in the bed in a corner of your own end, across from the 01 or 02 (your goals first). **That last one is mine, not yours: say if you want it gone** |
| 9 | The computer | See the table above |
| 10 | Watching | Stand near the table while two others play (or a second window): you see the same match on the same table, smooth, a moment late, and you hear it. Each person playing stands on the mat at their end, leans toward the table and holds their right arm out toward their mallet as it moves. The table is long for an arm, so the hand is on the mallet only when it is close to their end. **I could not look at this one: say if the arm looks wrong** (it is one switch, `Reach.ON`). Your own arm is left alone on your own screen |
| 11 | Leaving | Q or walking away, or being bitten at the table: your camera and legs come back at once. The other player carries on against the computer |
| 12 | Typing | Typing in chat during a match must not move the mallet, the view or serve |
| 13 | A phone | The game opens from above on a small screen, the help card is put away when the match starts (HELP brings it back), and nothing of the HUD lies over the bed: a goal's words and PINCHED are in the top left corner beside it |
| 14 | A squirrel on the table | Jump on the table as a squirrel while two people play: when the puck or a mallet reaches you, you are put on the floor beside it and both sides read a line. The match is not touched |

## Known limits
- **No sound yet.** Every sound is a named cue with no asset behind it: strike (louder the harder), rail, post, serve (each time the puck is let go), goal for you, goal against you, a goal at a table you are watching, match won, match lost. Your game makes its tones in code; ours may not at run time, so each needs a short recorded sound.
- **The look is parts, not your mesh.** The 1,500 air jets and the bevels are left out; the GLB is kept in `docs/reference/air_hockey/` for an upload later.
- **Against a person, the line's delay has to show somewhere.** The far end is one round trip and a twentieth of a second behind (the other hand's log goes twenty times a second, the most the game's input channel carries; a faster allowance would cut it further). Measured on a made-up line with two hard-hitting hands, 60 seconds, each way 0 / 40 / 80 thousandths of a second (each player's screen):
  - the far end is drawn 58 / 107 / 206 thousandths late (it was 74 / 124 / 223);
  - the puck is late at your own strikes by 1 / 2 to 4 / 55 to 60 thousandths on average;
  - the drawn puck moves at more than twice the table's top speed on about 1 frame in 800 / 1 to 3 in 100 / 3 to 4 in 100 (with no delay it was up to 1 in 200), and never at more than four times its own speed;
  - a moving puck is drawn under 60 % of its speed on 3 / 10 to 12 / 24 to 33 in a hundred of the frames (with no delay it was 6 to 7), and with no delay it never stands still (it did on about 5 frames a minute).

  A hard shot sent back from near the centre line still has to catch up in half a metre, and at 80 and above a hard shot from the far end is in your half before your screen is told of it. Nothing honest can show it sooner. At 150 each way the puck is about a quarter of a second late at your strikes. Against the computer none of this arises.
- **Above about 350 thousandths of a second each way** a match between two people stops waiting for the slow player's hand, and that player is told so in words.
- A player whose own line is slow by up to 0.4 seconds is waited for, so someone who slows their line on purpose sees that much further ahead. The table does not try to catch this.
- Your Tab (switch ends) is not there: you choose your end by the prompt you press. P (pause) and R (reset) are not there either: it is a shared table.
- No server check has been run in the real engine yet (they cannot be run at present); the flow is written and passes on the test rig.
