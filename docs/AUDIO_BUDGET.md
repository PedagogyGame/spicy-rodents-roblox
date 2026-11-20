# Audio budget

Roblox has no runtime sound synthesis: every sound is a library asset or an upload, and uploads are limited (BRIEF_ADDENDUM B3: this game works within 40 a month, at most 50, and keeps at least 50 of the owner's 100 for his other games; HANDOFF §3 rule 6). The owner's rule since D16 (#36, #50): **no cue is left silent**; the most fitting reasonable sound for each, with uploads only where the licensed library has nothing, and a custom upload for the dog's bark.

Where the sounds come from, in order:
1. **Roblox's licensed library**: ProSoundEffects (creator 7462895450) for effects and APMOfficial (creator 7462718749) for music and stings, found through the Creator Store's read-only toolbox search.
2. **Roblox's own sounds** (creator Roblox): its pinball set ("Audio/Roblox_Pinball_..."), its interface set, its player footsteps, and the classic sounds every client ships (`rbxasset://sounds/...`).
3. **The game's own uploads**, made offline (never at run time) where nothing above fits. Each is a candidate under `assets/audio/candidates/` until the lead has heard it, approved it and uploaded it.

Every id below was picked by its library title, description and length; **none has been heard in the game yet**. Each is one line to swap in the table named. `tests/unit/audio_cues.spec.luau` fails if any cue in the game has no sound (other than an upload slot waiting for the lead), if an id chosen is missing from this file, or if the uploads planned exceed 12.

## Uploads
| Month | Uploaded | Notes |
|---|---|---|
| 2026-11 | 0 so far; **2 planned** | `dog_bark` and `bowling_roll` below. Nothing else needs an upload. |

The upload slots (`src/shared/Audio/Uploads.luau`: the game reads the id from there; empty until uploaded, and the cue is silent until then):

| Slot | Cue | Candidate | Length | How it was made | Licence |
|---|---|---|---|---|---|
| `dog_bark` | `Dogs.Bark` (the yard dogs; owner #36: a custom bark) | `assets/audio/candidates/dog_bark.ogg` | 0.78 s | synthesised offline: two short voiced barks, harmonics through three open-mouth formants (650, 1250, 2600 Hz), a breath at each onset, pitch 380 -> 560 -> 300 Hz; friendly, no growl | the game's own (made from code here; no recording or third-party audio) |
| `bowling_roll` | `roll` (bowling: the ball down the lane) | `assets/audio/candidates/bowling_roll.ogg` | 2.6 s | synthesised offline: low brown noise with the lane's wooden resonances (85, 140 Hz), the ball's turn as a 4-4.6 Hz pulse, faint surface grit, duller and quieter as it goes, faded | the game's own |

Why these two: the licensed library has no dog bark short enough (only 50-70 s farm ambiences with barking in them) and no ball rolling down a lane (only billiards, basketballs and carts); the owner asked for the bark as an upload.

The lead's steps:
1. `python3 -I tools/audio/make_candidates.py --preview build/audio` remakes both from fixed seeds (numpy, scipy, ffmpeg) and writes WAVs and spectrograms to listen to and look at.
2. Listen. To change one, edit its recipe in `make_candidates.py` and remake it.
3. `python3 -I tools/audio/publish.py --skip-upload` checks the candidates (mono Vorbis, short, the length the manifest says, a slot in `Uploads.luau` for each).
4. Upload by hand (Creator Hub; `tools/cloud` deliberately does not upload audio), then `python3 -I tools/audio/publish.py --record dog_bark=<assetId> --moderation Approved --approve`, which writes the id into the manifest and `Uploads.luau`. Add the upload to the tally above.

## Every cue and its sound

### Corner store (`src/server/Items/ItemWorld.luau` `SOUNDS`; the till in `src/server/Items/CornerStore.luau`)
Each cue is a Sound named after it, played at the person using the item (or at the cushion).

| Cue | When it fires | Sound (id) |
|---|---|---|
| `CornerStore.Till` | a sale at the till | Cash Register 2 (9113728049) |
| `Items.WaterGun` | a squirt | Squirt Bottle (9125995935) |
| `Items.Harmonica` | the harmonica is played | Harmonica Stings D, APM (1846183142) |
| `Items.BikeHorn` | the bike horn | Horn Blow Long Bursts 7 (9114822511) |
| `Items.AirHorn` | the air horn (it also startles anyone within 12 studs) | Diesel Truck Air Horn 1 (9114075665) |
| `Items.Bubbles` | blowing bubbles | Small Bubbles Float Up Pop 5 (9112872239) |
| `Items.CameraClick` | a disposable-camera shot | Camera Shutter 1 (9113678227) |
| `Items.TapeRip` | a strip of duct tape | Denim Or Canvas Tears 8 (9114886755) |
| `Items.Whoopee` | someone steps on the whoopee cushion | Airy Deflate 13 (9114372701) |
| `Items.SodaFizz` | a soda is had | Drinking Cu Gulping 1: drinking from a soda can (9114171849). The library has no can opening; this is the nearest. |
| `Items.Wrapper` | the ice cream bar | Crunchy Cellophane 6 (9117409740) |
| `Items.PaperRustle` | the newspaper is read | Open And Turn Pages 2 (9118835414) |
| `Items.ChairUnfold` | the lawn chair is set down | Folding Chairs 18 (9114514975) |
| `Items.Click` | the flashlight on or off | Flashlight Switch 13 (9114481274) |
| `Items.UmbrellaOpen` | the umbrella opens or closes | Heavy Cloth Flap 6 (9114884567) |
| `Items.Throw` | a frisbee or a football thrown | Whoosh Thick Quick 2 (9120742716) |
| `Items.Chalk` | chalk writing | Chalkboard 9 (9113781594) |
| `Items.Scatter` | peanuts or bird seed put down | Pebbles On Wood 14: a handful dropped lightly (9117274542) |
| `Items.Crunch` | a dog treat given | Celery Break 6 (9113734636) |
| `Items.KiteWind` | the kite goes up | Flag Flap 3 (9114461211) |

The radio's playlist (the same table; APM, chosen 18 November): `Radio.Oldies1` Sunny Side Up, Alan Hawkshaw (1837066444); `Radio.Oldies2` Songbird, Brian Bennett (1837066718); `Radio.SoftRock` Out Of Sight, David Hamer (1847299654); `Radio.Country` Way Out West, Richard Warren Gilks (1840347412); `Radio.Jazz` Coffee Break, Manfred Paulsen (1845444990); `Radio.Weather` A Million Stars, a 15-second sting (9042143607).

### THE GILDED ACORN, the 1940s lounge
The jazz (`src/shared/Attractions/LoungeClassic.luau` `JAZZ`, APM, heard inside only): `Lounge.Jazz1` Charleston Time, Harry Gold (104391003816309); `Lounge.Jazz2` Strolling Along, Paul Lenart (1847365925); `Lounge.Jazz3` White Gardenia, Harry Gold (112961391906009); `Lounge.Jazz4` Dixie Doodle, Harry Gold (112031221369583).

The effects (`src/server/Attractions/LoungeService.luau` `SOUND_IDS`):
| Cue | When it fires | Sound (id) |
|---|---|---|
| `Lounge.GuardSwat` | a guard knocks out a squirrel at the door | Cloth Whooshes Soft 1 (9113842150) |
| `Lounge.Door` | the door's prompt, in or out | Half Glass Door 1 (9114745537) |
| `Lounge.CounterBell` | a drink is ordered at the bar | Desk Bell Counter Service (9125485591) |
| `Lounge.Pour` | the drink is handed over | Pour Tea From Pot Into Cup 3 (9117865590) |

### Bowling (`src/client/Minigames/Games/Bowling.luau` `sounds`; the cue points in `Shared/Minigames/Bowling/RollScript.cues`)
| Cue | When it fires | Sound (id) |
|---|---|---|
| `release` | the ball leaves the hand | Wood Beam Impact Resonant Clunk (9126236431) |
| `roll` | just after the release, volume from the power | **upload slot `bowling_roll`** (silent until uploaded) |
| `gutter` | the ball drops into the channel | Punch Wood Box 2: a hollow wooden knock (9117973595) |
| `pin` | each clatter of pins | Wood Down Shaft Clanking 5 (9120840234) |
| `pit` | the ball drops off the back of the deck | Body Pat Muted 1 (9113531800) |
| `strike` | the STRIKE banner | Through the Roof, APM sting (1840076509) |
| `spare` | the SPARE banner | The Little Things, APM hit (1848287311) |
| `sweep` | the pinsetter's bar comes down (now fired: the throw's end + `RollScript.SWEEP_AT`, which is the server's SETTLE + PAUSE; played after the playback lets go) | Pump Cycle Machine: mechanical clunks, an air burst, 2.9 s (9125792061) |

### Air hockey (`src/client/Minigames/Games/AirHockey.luau` `sounds`)
| Cue | When it fires | Sound (id) |
|---|---|---|
| `air_hockey.strike` | a mallet meets the puck (volume: how hard) | Knock Slap Plastic 15 (9116202343) |
| `air_hockey.rail` | the puck off a rail | Knock Slap Plastic 1 (9116201137) |
| `air_hockey.post` | the puck off a goal post | Metal Lid Small 2 (9116741491) |
| `air_hockey.serve` | each time the puck is let go | Bellows 19: a soft puff of air (9113418957) |
| `air_hockey.goal_for` | you scored | Through the Roof, APM sting (1840076509) |
| `air_hockey.goal_against` | they scored | Feet Do Not Fail Me, APM sting (1839996306) |
| `air_hockey.goal` | a goal at a table you are watching | Tennis Ball Can Drop Into Plastic Container: a puck-sized drop into plastic (9126097643) |
| `air_hockey.win` | the match is yours | J Funk, APM sting (1839982934) |
| `air_hockey.lose` | the match is theirs | Muck and Brass, APM sting (1837719710) |

### Paintball (`src/client/Minigames/Games/Paintball.luau` `sounds`; volumes in `Shared/Minigames/Paintball/Tuning`)
| Cue | When it plays | Sound |
|---|---|---|
| `paintball.fire`, `paintball.fire_far` | a ball leaves (yours; another's, placed) | `rbxasset://sounds/paintball.wav` (the classic Paintball Gun gear's pop, ships with every client) |
| `paintball.splat` | a ball bursts | `rbxasset://sounds/splat.wav` |
| `paintball.tag` | the server says YOU tagged someone | `rbxasset://sounds/electronicpingshort.wav` |
| `paintball.tagged` | you were tagged out | Thwack Sharp 1 (9120032247) |
| `paintball.reload` | a reload starts | Plastic Rattle (9125746771) |
| `paintball.dry` | a press on an empty marker | `rbxasset://sounds/clickfast.wav` |
| `paintball.step` | each stride: loud sprinting, soft walking, silent crouched | Roblox's own PlayerStep_Dirt_03, a single player footstep (129087653644939). The licensed library has no single human footstep. |
| `paintball.ready` | the reload is done | `rbxasset://sounds/button.wav` |
| `paintball.go` | the match is live | `rbxasset://sounds/electronicpingshort.wav` |
| `paintball.back` | back from being tagged out | `rbxasset://sounds/action_get_up.mp3` |
| `paintball.over` | full time | Referee Whistle 2 (9118113825) |

The `rbxasset://sounds/...` ones are the client's own files; check in Studio that each loads (a missing one is silent and the Output says so).

### Pool and bumper pool (`src/client/Minigames/Pool/Sounds.luau`: one set, `pool.<cue>` and `bumper_pool.<cue>`)
| Cue | When it fires | Sound (id) |
|---|---|---|
| `chalk` | a turn begins: the cue is chalked | Coral Scrape: small pieces rubbed together, thin, gritty (9125460155) |
| `strike` | the tip meets the ball (volume by power) | Billiards Ball Hits Rolls With Cue Stick 3 (9113441098) |
| `click` | ball on ball | Billiard Balls Ball Hits Rolls 13 (9113440232) |
| `crack` | the break (eight-ball) | Billiards Break Rack Up Ball Hits 6 (9113441694) |
| `cushion` | a ball off a cushion | Billiards Ball Bounces Off Of Bumpers 8 (9113440925) |
| `jaw` | a ball rattling in a pocket's jaws (eight-ball) | Billiards Shoot Balls Into Pockets 2 (9113442163) |
| `post` | a ball off a rubber bumper (bumper pool) | Billiards Ball Bounces Off Of Bumpers 7 (9113440927) |
| `rim` | a ball lipping out or skipping a cup | Billiards Balls Rolling On Table 3: soft plunky hits (9113441345) |
| `drop` | a ball dropping into a pocket or cup | Billiards Shoot Balls Into Pockets 1 (9113442190) |
| `home` | a potted ball arriving in the tray | Roblox Pinball Rolling Metal Tracks Loop 01 (16480554578) |

### Pinball (`src/client/Minigames/Pinball/Cabinet.luau` `IDS`; the same on the three machines, `pinball.<variant>.<cue>`)
All from Roblox's own pinball set (Audio/Roblox_Pinball_...):

| Cue | Sound (id) | Cue | Sound (id) |
|---|---|---|---|
| `flip_up` | Flipper Up 01 (16480564862) | `flip_down` | Flipper Down 01 (16480567211) |
| `flipper_hit` | Bumper Weighted Click 01 (16480567946) | `wall` | Bumper Soft Click 02 (16480568611) |
| `post` | Bumper Soft Click 01 (16480568821) | `bumper` | Bumper Full 01 (16480574637) |
| `sling` | Bumper Mecanical Air 02 (16480569302) | `standup` | Bumper Weighted Click 03 (16480567747) |
| `drop` | Modern Machine Mechanics 01 (16480555593) | `rollover` | Tiny Button Press 01 (16480550292) |
| `spin` | Small Button Press 05 (16480553171) | `saucer` | Giant Button Press 01 (16480560857) |
| `eject` | Bumper Mecanical Air 03 (16480569639) | `ramp_in` | Ball Plastic Slide 01 (16480576404) |
| `ramp_out` | Ball Plastic Slide 04 (16480576087) | `balls_click` | Small Metal Click 01 (16480551554) |
| `drain` | Modern Machine Mechanics 03 (16480555243) | `plunge` | Joystick Buzz Release 01 (16480558943) |
| `save` | 8Bit Riser 01 (16480578169) | `bonus_tick` | 8Bit Blip 01 (16480580213) |
| `tilt_warn` | Giant Button Press 02 (16480560696) | `tilt` | Modern Machine Mechanics 02 (16480555445) |
| `ball_start` | Startup Mechanical 01 (16480551414) | `ball_end` | Big Metal Tally 02 (16480575731) |
| `extra_ball` | 8Bit Riser 02 (16480578036) | `game_over` | Endgame Tally 01 (16480567382) |
| `say` | 8Bit Blip 05 (16480579431) | `nudge` | Joystick Slam 01 (16480557599) |
| `search` | Gameplay Actions 01 (16480563821) | `reset_drops` | Startup Mechanical 02 (16480551277) |
| `jingle` | 8Bit Riser 04 (16480577565) | `gate` | Tiny Button Press 02 (16480550090) |
| `reel` | Big Metal Tally 03 (16480575322) | | |

### Whack-a-mole (`src/client/Minigames/WhackAMole/Cabinet.luau` `IDS`)
| Cue | When it fires | Sound (id) |
|---|---|---|
| `whack_a_mole.pop` | a mole comes up | Pop Airy 16 (9117834439) |
| `whack_a_mole.swing` | the mallet swings | Swish, Paddle Swish, Soft (9119702970) |
| `whack_a_mole.bonk` | a hit | Comic Boinks 2 (9113854411) |
| `whack_a_mole.thud` | a miss on the deck | Punch Wood Box 1 (9117973587) |
| `whack_a_mole.count` | each second of the count-in | Roblox Pinball 8Bit Blip 02 (16480580064) |
| `whack_a_mole.go` | GO | Roblox Pinball 8Bit Riser 01 (16480578169) |
| `whack_a_mole.hurry` | each of the last five seconds | Roblox Pinball 8Bit Blip 09 (16480578434) |
| `whack_a_mole.over` | TIME | Roblox UI Tonal Stinger (15675043410) |

### Sewers (`src/client/World/SewerAmbience.luau` `CUES` and `VOLUME`; the server's hiss in `src/server/World/SewerService.luau`)
The storm drains (BRIEF_ADDENDUM D8). Mild: water, echoes and drips. While the squirrel is inside, the client sets `SoundService.AmbientReverb` to `SewerPipe`, so the sounds themselves are dry; the per-stride and per-stud cues play quietly.

| Cue | When it fires | Volume | Sound (id) |
|---|---|---|---|
| `sewer.grateIn` | the squirrel goes down a grate or quay cover | 0.6 | Cast Iron Fireplace Grate: drop on its side and shift (9125426401) |
| `sewer.grateOut` | it comes up out of one | 0.5 | the same, shorter (9125426396) |
| `sewer.rung` | every stud climbed or descended in a shaft | 0.2 | Metal Rungs 1: a ladder climb (9116801858) |
| `sewer.footEcho` | every 2.75 studs run along a passage | 0.25 | Spider Footsteps 4: soft fast taps, a small patter (9119455498) |
| `sewer.drip` | at random every 2 to 6 s inside | 0.5 | Water Drip: a distant single drop, reverberant (9126176614) |
| `sewer.trickle` | a loop in a brick drain (P1, P3) | 0.35 | River Water 1: an aqueduct inside a tunnel (9118187543) |
| `sewer.riverHum` | a loop in the dry culvert under the river (P2) | 0.5 | Storm Drain Presence 1: a 3' pipe, slowed, wind-like (9119643864) |
| `sewer.streetMurmur` | a loop within 8 studs of a mouth | 0.25 | City Ambience 1: traffic, an occasional car over a metal plate (9112758242) |
| `sewer.hiss` | still underground until the idle warning (the small alligator, never seen) | 0.7 | Snake Hiss 1: airy hisses (9119302862) |
| `sewer.carOverhead` | a town car this client draws (the traffic ghosts) comes over the pipe the squirrel is in: within 5 studs of the pipe's line and 30 of the squirrel, as it arrives (not while one stands there); at most once in 5 s a pipe. The cars cross drain 1 (the north-south main road, the ice cream van's loop) and drain 3 (the boulevard, the patrol beat); nothing drives over the culvert | 0.6 | Metal Plate Impact, Manhole Hit (9116750726) |
| `sewer.trolleyOverhead` | the same for the trolley (its track crosses drain 3 on the boulevard); at most once in 15 s | 0.5 | Electric Trolley 2: a pass by (9114257912) |

### Sky lift and the Lookout (`src/shared/Rides/SkyLiftSounds.luau`: ids, volumes, reach)
The server plays the first three from its posts (`src/server/Rides/SkyLiftService.luau`) and keeps the Lookout's three loops on posts of their own; the client (`src/client/Rides/SkyLiftView.luau`) hangs the cabin's own on each local cabin (heard only round it) and plays them for cabins within 150 studs of the camera; `src/client/Rides/Telescope.luau` clicks on the way out.

| Cue | When it fires | Sound (id) |
|---|---|---|
| `SkyLift.StationBell` | on each gate post, when a cabin's doors open there | Amtrak Superliner 1: a call-to-conductor chime (9113118168) |
| `SkyLift.CounterBell` | on the Lookout's counter, when a lunch is served | Desk Bell Counter Service (9125485591) |
| `SkyLift.TelescopeClick` | on the telescope, when someone looks through it | Airstream Door Latch 5: a lever click and snap (9113076465) |
| `Telescope.Click` | the looker's own screen, on the way out | the same (9113076465) |
| `SkyLift.CableHum` | looped on every cabin | Elevator Room 2: motors running, a steady hum (9112777363) |
| `SkyLift.DoorsOpen` / `SkyLift.DoorsClose` | a cabin's `doorFrac` leaving 0 / back to 0 | Air Chuff Hydraulic Pneumatic Air Burst 2 / 4 (9113059828 / 9113059926) |
| `SkyLift.TowerClunk` | a cabin's grip reaching a tower (within `TOWER_NEAR` of its centre in plan) | Pulley Rotating Movement 3: wheels turning, soft clicks (9117951840) |
| `SkyLift.WindAtHeight` | looped on every cabin, louder the higher it is over the slope (none under 15 studs, full at 120) | Barstow Wind 3: light, blustery, a low howl (9113287001) |
| `Lookout.Fireplace` | looped at the fire | Fireplace, constant burning flame (9112780193) |
| `Lookout.DiningRoom` | looped in the dining room | Dining Jesuits 1: plates, cutlery, a murmur (9112769536) |
| `Lookout.TerraceWind` | looped on the terrace | Desert Wind: whistley, light gusts (9114057104) |

### The duel (`src/server/Combat/CombatService.luau` `SOUNDS`)
Mild: no crunch, no pain sounds. Played at the body.

| Cue | When it fires | Sound (id) |
|---|---|---|
| `Duel.Windup` | the rodent's pounce wind-up, or a feint | Creature Vocal, Spider Hiss Exhale 1: a short hiss (9113990336) |
| `Duel.Strike` | a person's kick, swing or baton comes down | Whoosh Heavy Punches 3: arm swings (9120729007) |
| `Duel.Blow` | the blow lands on the rodent | Squeaky Toy 2: a toy hit and squeak (9119536562) |
| `Duel.Batted` | a bite batted away | Baseball Fist Slap Into Glove (9125376871) |
| `Duel.Squareup` | someone squares up to the rodent | Video Game Effects 18: a fight yell (9120416894) |
| `Duel.Shout` | someone on the scene of a bite backs off | Male Vocal Gasps Exclamations 3 (9116457156) |

The library's human voices are few; the two vocal picks are the riskiest in this file (a word, or a pained sound, would have to go). If either does not fit when heard, the next candidates are the other takes of the same sets (Video Game Effects 1-27, 9120415730 to 9120417879; Male Vocal Gasps Exclamations 1-5).

### The yard dogs (`src/server/Wildlife/YardHazards.luau` `SOUNDS`)
| Cue | When it fires | Sound |
|---|---|---|
| `Dogs.Bark` | a yard dog barks at a squirrel in its yard (at most every 8 seconds a dog) | **upload slot `dog_bark`** (the game's own; silent until uploaded) |

### Nuts (`src/client/UI/NutMeter.luau` `PICK_SOUND`)
| Cue | When it fires | Sound (id) |
|---|---|---|
| `Nuts.Pick` | the player's own squirrel picks a nut up (heard by that player only; volume 0.35, played a little higher) | Wood Drop, Impacts On Concrete, Small Pieces: a small wooden tick and bounce (9120863989). It replaces the stand-in, the store's flashlight click (9114481274). |

### The air trick (`src/shared/Movement/AirTrick.luau` `SOUNDS`; played by `src/client/Animation/AnimationDriver.luau`)
Owner D17: one sound per move, played once at the squirrel by every client that sees it (within 120 studs), a little higher than recorded. Both are ids the game already uses elsewhere; nothing uploaded.

| Cue | When it fires | Sound (id) |
|---|---|---|
| `AirTrick.Roll` | a squirrel's barrel roll in the air | Cloth Whooshes Soft 1: a soft whoosh going past (9113842150) |
| `AirTrick.Wiggle` | a squirrel's twitch-and-wiggle in the air | Swish, Paddle Swish, Soft (9119702970) |

## To hear first in Studio
All of the above were chosen without being heard. The ones most likely to need a swap: the duel's two voices; `Items.SodaFizz` (a gulp, not a can opening); `sewer.footEcho` and `sewer.rung` at their volumes; `SkyLift.CableHum` (a building's lift motor, not a rope); and the two upload candidates.
