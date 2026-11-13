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
