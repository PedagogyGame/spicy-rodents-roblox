# Audio budget

Roblox has no runtime sound synthesis: every sound is a library asset or an upload, and uploads are limited to 40 to 50 a month (BRIEF_ADDENDUM B3; HANDOFF §3 rule 6). This file keeps the tally and the list of sounds that are waiting.

## Uploads
| Month | Uploaded | Notes |
|---|---|---|
| 2026-11 | not tallied here yet | Bowling (branch `feat/bowling-complete`) uploaded nothing. Whoever uploads audio next starts the count on this row. |

## Cues waiting for a sound
These already fire at the right moments in the game and are silent. Fill the asset id in the named table and the sound plays.

### Bowling (`src/client/Minigames/MinigameSounds.luau`, table `CUES`)
| Cue | When it fires | Wanted |
|---|---|---|
| `release` | the ball leaves the hand | a soft thud on wood |
| `roll` | just after the release, volume from the power | a ball rumbling down a lane, about 2 s, should stop at the pins or the pit |
| `gutter` | the ball drops into the channel | a hollow clunk and a duller rumble |
| `pin` | each clatter of pins (pins hit within 0.04 s count as one) | one to three pins knocking; played several times in a strike |
| `pit` | the ball drops off the back of the deck | a thump on carpet |
| `strike` | the STRIKE banner | a short bright sting |
| `spare` | the SPARE banner | a shorter, smaller sting |
| `sweep` | not fired yet (the pinsetter is drawn by the server) | a machine clank and whirr, about 2.5 s |

Eight sounds if each is uploaded; fewer if library sounds fit.

### Air hockey (`src/client/Minigames/Games/AirHockey.luau`, table `sounds`)
| Cue | When it fires | Wanted |
|---|---|---|
| `air_hockey.strike` | a mallet meets the puck, when the contact is seen; volume from how hard | a sharp plastic clack |
| `air_hockey.rail` | the puck comes off a side or end rail; volume from how hard | a shorter, duller knock |
| `air_hockey.post` | the puck comes off a goal post | a small metal tick |
| `air_hockey.serve` | each time the puck is let go (the countdown running out, or a press) | a soft puff of air |
| `air_hockey.goal_for` | you scored | the puck dropping into the goal, then a short bright sting |
| `air_hockey.goal_against` | they scored | the same drop, then a lower sting |
| `air_hockey.goal` | a goal at a table you are watching | the drop alone |
| `air_hockey.win` | the match is yours | a short win sting |
| `air_hockey.lose` | the match is theirs | a short falling sting |

Nine sounds if each is uploaded. The owner's own game makes these as tones in code (`docs/reference/air_hockey/`); the strike, rail and post could be one recording at three pitches.

### Sewers (`src/client/World/SewerAmbience.luau`, table `CUES`)
The storm drains (BRIEF_ADDENDUM D8). Mild: water, echoes and drips, nothing dirty. While the squirrel is inside, the client also sets `SoundService.AmbientReverb` to `SewerPipe` and puts it back on the way out, so most of these can be dry library sounds.
| Cue | When it fires | Wanted |
|---|---|---|
| `sewer.grateIn` | the squirrel goes down a grate or quay cover | a light iron rattle and a soft drop |
| `sewer.grateOut` | it comes up out of one (or the body changes while inside) | the same rattle, shorter |
| `sewer.rung` | every stud climbed or descended in a shaft | a small claw tick on iron |
| `sewer.footEcho` | every 2.75 studs run along a passage | a soft patter with a short echo |
| `sewer.drip` | at random every 2 to 6 s while inside, at the nearest drip point | one clear water drip |
| `sewer.trickle` | a loop while inside a brick drain (P1, P3) | running water in a narrow channel |
| `sewer.riverHum` | a loop while inside the dry culvert under the river (P2) | a low, muffled rush from above |
| `sewer.streetMurmur` | a loop while within 8 studs (level) of a mouth, from below | muffled traffic and voices through a grate |
| `sewer.hiss` | the squirrel has stood still underground until the idle warning (D34; v5.4's small alligator), with the line "A low hiss and a ripple in the sewer water…" | a low hiss and a small splash, never seen |
| `sewer.carOverhead` | not fired yet (needs the traffic poses over a pipe) | a car passing over a manhole lid, a dull double thump |
| `sewer.trolleyOverhead` | not fired yet (as above, the trolley over P3) | a heavier rumble and a rail clack |

Eleven sounds if each is uploaded. The loops (trickle, riverHum, streetMurmur) and the drip are the ones that make the place; the rest could share two or three recordings.
