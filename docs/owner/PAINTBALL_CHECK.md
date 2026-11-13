# Paintball: what to try at the playtest (20 to 30 minutes)

Paintball is built, joined and reviewed on branch `feat/paintball`. Everything below has been tested without a screen: the server, the client, the bots and the building play whole matches against each other in the test rig, and three reviewers (feel, netcode, and your ten-point bar) tried to break it. **Nobody has played it in Studio or on a device.** Your bar says it is cut if the mechanics are weak, so this is the list of what only you can judge, point by point.

## Before you start

1. **Bake the building.** The station is not in the place file: run `lune run tools/bake/attractions.luau` in the repository, then open Studio as usual (the bake writes `build/Attractions.rbxm`, which the project loads into `Workspace.Attractions`: the station is `f3_tv_station`, the street to it is `Ways`).
2. **Paintball is free for now.** The 20c pass is sold at the desk, but until the wallet lands (`feat/wallet`) the town's charge always says yes, and the pass is forgotten when the server restarts. The lounges do not exist yet, so the pass opens nothing else.
3. **Getting there.** On foot: go to the east end of the estate avenue, where it carries straight on as **Chapel Street**; a green fingerpost on the corner reads "WBLW CHANNEL 7 / PAINTBALL / 1435 studs". Follow Chapel Street east about 1,400 studs; the station is on your left behind a chain-link fence, its walk opposite the door (it takes a few minutes, which is worth doing once: the street, its lamps and the way the station comes into view are new). To skip the walk, press Play, then in the command bar (Server view) run:
   `game.Players:GetPlayers()[1].Character:PivotTo(CFrame.new(2080, 14, -793))`
   That puts you on Chapel Street's sidewalk at the end of the walk, the door straight ahead (north). Walk in.
4. **Buy the pass and join.** Inside the lobby: the **pass desk** on the left (its prompt reads **Buy a pass**, press E), then the **arena door** in the middle of the far wall (press E). Bots fill every empty seat, 4 a side at least. You start in your team's spawn room for a 10-second briefing; first person is locked from the door until you leave.
5. **Your tuning command** (see "Tuning it" below) only works for the place's owner (or anyone in Studio's own play test). A note on screen tells you so when you join.

## What to press

| | Keyboard and mouse | Gamepad | Phone or tablet |
|---|---|---|---|
| Look | mouse | right stick | drag on the right half (also on FIRE) |
| Move | W A S D | left stick | the stock thumbstick |
| Fire | left button: a tap is one ball; **hold it and the marker fires on**, a ball every quarter second | R2 (tap or hold) | FIRE (right; tap or keep the finger on it), or the left FIRE |
| Reload | R (a click during it cancels it and fires) | X | RELOAD |
| Sprint | hold Shift (the marker lowers) | L3 (a toggle; ends on a press, a crouch or letting go of the stick) | hold the stick fully forward for 0.4 s |
| Crouch | hold C or Left Ctrl | B (toggle) | CROUCH (toggle) |
| Jump | Space | A | the stock jump button |
| Scoreboard, Leave, Change sides | hold G | hold View (Y leaves, D-pad up changes sides) | SCORES |

## The ten points, one by one

1. **Projectile with travel and slight drop.** Fire across the atrium at a far wall: you should see the ball fly (about 0.3 s over 45 studs) and dip a little (about a stud over 45, two over 70). **Changed at the review:** the ball was 90 studs/s and could not hit a person walking across your view without a lead of up to five body widths; it is now 150, with the drop doubled so the arc still shows. Try a moving bot at 20 and at 40 studs. If it is too easy or too hard, change it (Tuning, below): try 120, 150 and 180.
2. **Five-shot magazine.** Five pips on the HUD. Fire five: the reload starts by itself (1.6 s, a rattle). Press R with balls left, then click: the click cancels the reload and fires (changed at the review: it used to be a dry click for 1.6 s). Hold the button down: five balls, the reload, and on.
3. **Server hits with lag compensation.** What you hit on your screen should be what the server counts (a hit marker X and a ding come only on the server's word). Studio has a network simulator (File, Studio Settings, Network: Incoming Replication Lag): try 0.1 and 0.15 s. At a 300 ms round trip about 9 shots in 10 agree; `/pb rewind 0.3` makes that 19 in 20, at the price of being tagged a little later after ducking.
4. **Splats stay.** Walls, floors and players keep their paint for the whole match (the oldest of 400 on the building go first). By minute six the atrium should be a two-colour mess.
5. **Five floors, stairwells, a central atrium.** Walk every stair up and down, walking, sprinting and crouched. **Watch for the screen saying your position was put back** (a correction): it must never happen to an honest walk. Look down the atrium from each gallery; crouch behind a low wall in a room and check a bot cannot tag you over it. At the atrium rails a crouched head still shows, by a hair, to someone across the atrium.
6. **Team deathmatch, 4v4 to 8v8, bots fill.** With one person you get 4 a side. Leave and rejoin; ask a friend to join: a bot gives up its seat.
7. **Timer, scoreboard, end card.** The clock is top middle (your floor is under it now). Hold G for the board. At full time the WBLW sports bulletin with silly awards; the next match starts by itself. `/pb` does not shorten a match: to see the end card sooner, ask me for a shorter match.
8. **Distinct audio for fire and hits.** **Placeholder sounds now play** (the classic Paintball Gun's pop, a splat, a ding when YOU tag someone, a thwack when you are tagged, a dry click). They are Roblox's own built-in sounds, chosen so you can judge the timing; choose the real ones (below). If any is silent, Studio's Output says it failed to load.
9. **Sprint and crouch that feel right.** Sprint: faster, the view widens, the marker lowers and cannot fire until 0.15 s after you stop; a click ends the sprint. Crouch: half speed, eye lower, silent footsteps. On a phone, check the sprint does not start on its own when you just run.
10. **If it is weak it gets cut.** Your call. If you cut it, nothing else in the town depends on it.

Also: first person is locked inside (brief 14); the call-outs from bots name a floor and now say where it is from you ("They are on 3! (one up)").

## Tuning it (owner only)

Type in chat while you are in the match (after pressing E at the arena door):

| Command | What it changes | Range |
|---|---|---|
| `/pb` | shows every number as it is now | |
| `/pb ballSpeed 150` | ball speed, studs a second | 80 to 200 |
| `/pb ballDrop 19.6` | how fast the ball drops | 0 to 40 |
| `/pb fireInterval 0.25` | seconds between balls | 0.15 to 1 |
| `/pb reloadSecs 1.6` | reload time | 0.5 to 4 |
| `/pb sprintMult 1.4` | sprint speed over walking | 1 to 1.6 |
| `/pb crouchSecs 0.2` | time to crouch and stand | 0.05 to 0.5 |
| `/pb respawnSecs 4` | time out when tagged | 1 to 10 |
| `/pb protectSecs 2` | protection after a respawn | 0 to 5 |
| `/pb rewind 0.3` | furthest back a ball is judged (lag compensation) | 0.1 to 0.4 |
| `/pb botSkill -0.2` | bots easier (below 0) or harder (above 0) | -0.5 to 0.5 |

The command knows you by the place's owner (`game.CreatorId`): if the game belongs to a group rather than to your own account, `/pb` works only in Studio's play test; tell me and I will add your user id. Anyone else who tries it is told "Only the place's owner can tune paintball."

The answer appears on screen and in the feed, for example "Ball speed: 150 -> 120, from the next match". **Every change takes effect at the next match** (so no two screens disagree during one); `rewind` and `botSkill` too. Write down the numbers you like and tell me: I will make them the defaults.

## Sounds to choose

Twelve cues, all timed and placed (other players' are heard from where they happen and dulled by each floor between). Placeholders for eleven, nothing for footsteps (the body's own stock footsteps play meanwhile). The full table with volumes is in `docs/AUDIO_BUDGET.md` under Paintball.

| Cue | When | Wanted |
|---|---|---|
| `paintball.fire` | your ball leaves | a toy "thup", not a gunshot |
| `paintball.fire_far` | anyone else's ball leaves | the same, duller and further |
| `paintball.splat` | a ball bursts on a wall, floor or person | a wet splat |
| `paintball.tag` | you tagged someone | a bright two-note ding |
| `paintball.tagged` | you were tagged | a loud low thwack |
| `paintball.reload` | a reload starts | a plastic hopper rattle |
| `paintball.dry` | a press on an empty marker | a dry click |
| `paintball.step` | footsteps (loud sprinting, soft walking, silent crouched) | soft steps on a hard floor |
| `paintball.ready` | the reload is done | a click-clack |
| `paintball.go` | the match goes live | a horn |
| `paintball.back` | you are back after being tagged | a short rising chime |
| `paintball.over` | full time | a whistle |

## Known not to be done

- **Nothing has run in Studio or on a device.** The written engine checks (`tools/cloud/tasks/paintball_flow.luau`, `paintball_walk.luau`, `tools/games/paintball/*/engine_check.luau`, `arena/frame_check.luau`) wait for the key's Luau Execution permission. So the frame cost (under 1.5 ms beside the town), the stairs under a real body, and the movement tolerances are unmeasured. The five-minute check is point 5 above: walk every stair, watch for a correction.
- **The way there and the outside are done; inside is not quite.** Chapel Street now runs from the estate avenue to the station (fingerpost, lamps, a forecourt), and the front has rotted (boards gone and hanging, the sign's L fallen, rust, a fence with a panel down, weeds, a dead news van): pictures `pb_18`, `pb_25` and `pb_26` in `docs/renders/paintball/`. Inside reads as a dead TV station, but there is no rubble or fallen ceiling. No picture of a match in play exists (every render is the empty building).
- **The pass** is free and not saved (above); the lounges it should open do not exist.
- **Not built:** garb and the lobby's garb shop (PB-13), a wall monitor showing the live match (the lobby screens show the score and clock only), paint fading on a player who leaves (D7), gamepad aim slow-down, hiding chat bubbles over hidden opponents.
- **Bots:** a scripted fair player beats the average bot about 3 times in 5 (the target), but single matches swing from 44 % to 82 %, and that player is a stand-in, not a person. `/pb botSkill` is the knob.
- **Anti-cheat leftovers:** a modified client that never sends the move belonging to its click can still fire a ball sideways to where it looks, but its puppet is then shown turned to the shot. The engine's ping (`GetNetworkPing`) is trusted as the round trip; if Roblox measures it as half, the lag allowance at 300 ms is a little tighter.
