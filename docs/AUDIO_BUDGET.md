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

### Sky lift and the Lookout (branch `feat/skylift`; nothing uploaded, nothing synthesised)
The server makes these as Sound instances with empty ids (`src/server/Rides/SkyLiftService.luau`, table `CUES`):
| Cue | When it fires | Wanted |
|---|---|---|
| `SkyLift.StationBell` | on each gate post, when a cabin's doors open there | a single soft station chime |
| `SkyLift.CounterBell` | on the Lookout's counter, when a lunch is served | a small service bell |
| `SkyLift.TelescopeClick` | on the telescope, when someone looks through it | a coin-viewer click |

Named but not placed yet (no Sound instance exists; the natural trigger is given):
| Cue | Trigger | Wanted |
|---|---|---|
| `SkyLift.CableHum` | looped in the rider's cabin (Client/Rides/SkyLiftView) | a low steady hum of rope and wheels |
| `SkyLift.DoorsOpen` / `SkyLift.DoorsClose` | `SkyLift.doorFrac` rising from 0 / falling to 0 | a pneumatic slide, about 1 s |
| `SkyLift.TowerClunk` | a cabin's grip passing a tower's sheaves | a soft double clunk |
| `SkyLift.WindAtHeight` | looped, louder the higher the cabin | wind round a cabin |
| `Telescope.Click` | Client/Rides/Telescope in and out | the same click as the server's |
| `Lookout.Fireplace`, `Lookout.DiningRoom`, `Lookout.TerraceWind` | looped at the fire, in the dining room, on the terrace | crackle; low murmur and cutlery; wind |

### Paintball (`src/client/Minigames/Games/Paintball.luau`, table `sounds`)
Every cue below is timed and placed already. Until the owner chooses the set, eleven of them play a PLACEHOLDER that ships with every Roblox client (`rbxasset://sounds/...`, nothing uploaded, no licence needed), so the fire, the hits and the dry click can be judged at the playtest; `paintball.step` is empty (no single footstep ships with the client: the body's own stock footsteps are heard meanwhile). A placeholder that does not exist in the client is silent and the Output says it failed to load. Volumes are in `src/client/Minigames/Paintball/Tuning.luau`. Another player's cues are played from where they happened and dulled by each floor between (`World.luau`).

| Cue | When it plays | Volume | Placeholder now | Wanted |
|---|---|---|---|---|
| `paintball.fire` | your ball leaves | `volFire` 0.7 | `paintball.wav` (the classic Paintball Gun gear's pop) | a toy "thup": a light pneumatic pop, not a gunshot |
| `paintball.fire_far` | another player's or a bot's ball leaves, from where they stand | `volFireFar` 0.6 | `paintball.wav` | the same pop, duller and further off |
| `paintball.splat` | a ball bursts on a wall, a floor or a body (yours at once on your screen, others' where they land) | `volSplat` 0.45 | `splat.wav` | a wet splat |
| `paintball.tag` | the server says YOU tagged someone | `volTag` 0.9 | `electronicpingshort.wav` | a bright two-note ding, unmistakable |
| `paintball.tagged` | you were tagged out | `volTagged` 1.0 | `uuhhh.mp3` | a loud low thwack (the loudest thing in the game) |
| `paintball.reload` | your reload starts (R, or by itself after the fifth ball); another's, placed | `volReload` 0.5, `volReloadFar` 0.35 | `switch.wav` | a plastic hopper rattle, about a second and a half |
| `paintball.dry` | a press on an empty or reloading marker (at most one per `drySecs`) | `volDry` 0.5 | `clickfast.wav` | a dry click |
| `paintball.step` | each stride: loud sprinting, soft walking, silent crouched; others' placed | `stepLoud` 0.6, `stepQuiet` 0.22 | none | soft footsteps on a hard floor |
| `paintball.ready` | the reload is done: the magazine is full | `volReady` 0.45 | `button.wav` | a short click-clack |
| `paintball.go` | the briefing is over, the match is live | `volGo` 0.8 | `electronicpingshort.wav` | a horn |
| `paintball.back` | you are back from being tagged out | `volBack` 0.6 | `action_get_up.mp3` | a short rising chime |
| `paintball.over` | full time | `volGo` 0.8 | `victory.wav` | a whistle |

Twelve sounds if each is uploaded; the fire and the far fire, and the reload and the ready, could be one recording each at two volumes.
