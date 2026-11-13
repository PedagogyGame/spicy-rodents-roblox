# Sky lift and the Lookout: what to look at (15 to 20 minutes)

The sky lift runs up the hill south-west of town to the Lookout, a restaurant on the crown with a terrace and a telescope. It is a ride: no controls and no score. You get on and it happens. Everything below has been tested without a screen, so what you see is the real check. Wherever something is off, tell me what you pressed and what happened.

## Before the build
The lift and the Lookout are baked separately from the town. Run `lune run tools/bake/skylift.luau` before building the place. The file it writes, `build/Expansion_F4.rbxm`, is not in git. Without it, the server log says `[SkyLift] Workspace.Expansion.F4 missing` and there is no lift to see.

## How to get there
1. Pick **Townsperson** or **Police** from the menu. Only people ride; animals take the trail.
2. Follow the signs. At the town's central crossing a green fingerpost points west to **SKY LIFT / THE LOOKOUT**. Where the cross streets meet the westside street, more fingerposts point south. Where the westside street ends (about x -722, z -610), a tall red **SKY LIFT** sign with a cabin on top marks the start of **Lift Road**. Lift Road has red banners on its lamp posts and a shelter with a map board, and it leads to the **SKY LIFT** station at the foot of the hill (about x -760, z -905). It is a long walk; a car is quicker. Park in the car park and get out with **E** before you go to the gate.
3. A gravel trail with steps and benches also climbs the hill beside the line. You can walk up or down instead of riding.

## What to do
1. Go up the steps, under the red canopy, into the station. At the glass gate a prompt says **Ride the sky lift to the Lookout**. Press **E**.
2. The screen keeps a countdown: **Sky lift: your cabin in N s**. A cabin comes every 25 seconds or so. The board over the gate counts down, and it says **NOW BOARDING** only for the cabin at the door. Stay by the gate: if you walk more than 14 studs away, you give up your place, and the game tells you so.
3. When your cabin is in, the glass doors at the platform edge slide open and you are seated. You can also just walk through the open glass doors into a cabin: that seats you straight away, or tells you the cabin is full and when the next one comes. The view switches to **first person by itself**.
4. **Move the mouse to look around.** No button is needed and you can turn all the way round. The **I** key inverts up and down, as it does on foot. **V** switches to a view of the cabin from outside, and **V** again comes back.
5. Press **E** during the ride. You should read "You are on the sky lift: you get off at the top" (or "at the bottom" on the way down). **Reset** in the menu says the same and moves nothing.
6. Look out of the windows on the way up: fields in strips, hedges, a farm with a red barn and a silo, an orchard, a brook and a pond, and the trail's footbridge.
7. The ride takes about 65 seconds. At the top the doors open and you are standing on the platform with **Welcome to the Lookout**. Your legs and your usual camera come back. If friends rode with you, each of you gets off on a spot of your own.
8. Walk through the hall into the dining room. A host stands by the counter, and now and then townspeople come up on the lift, sit at the tables for a few minutes and ride home. At the counter, **E** orders the hilltop lunch. It is free for now ("On the house today"), and it is put on a table by the window or on the terrace.
9. Go out onto the terrace and press **E** at the telescope. Move the mouse to look, use the wheel to zoom, and press **E** or **Q** to step back. While you look, the game loads the part of town you are looking at, so real houses, trees, cars and people come in.
10. Ride down from the summit gate (**Ride the sky lift down to town**). It ends with **Back in town**.

## Please check
| # | What to look at | What you should see |
|---|---|---|
| 1 | The way there | Fingerposts from the town centre, the tall red sign where Lift Road begins, banners on Lift Road's lamps |
| 2 | The station from Lift Road | The lit SKY LIFT sign over a red canopy, benches, a bike rack and two flags, and the cable going up the hill over nine towers |
| 3 | The cabins | Six red and cream cabins moving smoothly, never jumping, and tipping gently over each tower (never a sudden lurch). They slow through the stations and their doors slide open and shut |
| 4 | The platform | Glass screens along the platform edge, so nobody can fall into the cabins' path; the glass doors open only while a cabin stands there |
| 5 | Boarding | First person straight away, seated on a bench, facing along the cabin. You should not see your own body in the way. Your body should look seated, not running |
| 6 | The free look | Smooth, with no shaking against the cabin walls. Shaking would mean the rider and the cabin are drawn a frame apart: please say so |
| 7 | Out of the windows | Farmland under the line, the hill face, then the town falling away: houses with roofs, windows and trees, even far off |
| 8 | V | The cabin from outside, following it; V again puts you back in your seat |
| 9 | Arrival | Standing on the platform, facing away from the cabin, with your own walking and camera back. Nothing stuck in the seated pose |
| 10 | The Lookout | The hall, the dining room, the counter with its host, the fireside corner and the terrace. Townspeople at some tables. The glass terrace rail sits below the town when you sit |
| 11 | Lunch | A plate, a sandwich and a cup appear on the table named in the message, and are cleared after four minutes |
| 12 | The telescope | A narrow, zoomed view of real streets; you step back with E or Q; your camera returns as it was and the Lookout is there around you |
| 13 | Night | From the terrace and the cabins: lit windows across the town and a warm dot on every street lamp. Lamps along Lift Road, the floodlit red sign, lit cabins, lit station and Lookout windows |
| 14 | The trail | Gravel and steps on the ground, not sunk into the grass and not floating. Benches face the town |

## Known not done
- **Nothing has run in the real engine.** The server checks cannot run until the key's Luau Execution permission is back. These are untested: seating a person on an anchored seat, the seated height (the rider may sit a little high or low on the bench), how riders look to *other* players, and the telescope's streaming of the town.
- **No sound.** The cue points are named in `docs/AUDIO_BUDGET.md`; nothing is uploaded.
- **The lunch is free** until the wallet (`feat/wallet`) lands. Then the one charge is 10 cents, in the counter's handler in `src/server/Rides/SkyLiftService.luau` (`hilltop_lunch` in `src/shared/Economy/EconomyRules.luau`).
- **The town from the top is drawn simply where the game has not loaded it**: houses as plain shapes with a roof and window bands, and trees as round crowns. The telescope loads the real streets it looks at; the terrace and the cabins do not.
- **The hill is a mound on a flat plain**, steeper than "a slight hill". The trail is quicker on foot than the ride.
- **Animals cannot ride** (people only, as planned).
- Up close: the tower wheels sit on top of the cable rather than under it (the cabins' hangers pass straight under the cable, where the wheels would be), the two highest tower footings stand out of the slope on their downhill side, and grass may show through the gravel in places.
- The kitchen and restroom doors at the Lookout are fronts only. The host stands; nobody cooks or serves.
