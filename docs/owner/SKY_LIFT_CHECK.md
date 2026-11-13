# Sky lift and the Lookout: what to look at (10 to 15 minutes)

The sky lift runs up the hill south-west of town to the Lookout, a restaurant on the crown with a terrace and a telescope. It is a ride: no controls and no score. You get on and it happens. Everything below has been tested without a screen, so what you see is the real check. Wherever something is off, tell me what you pressed and what happened.

## Before the build
The lift and the Lookout are baked separately from the town. Run `lune run tools/bake/skylift.luau` before building the place. The file it writes, `build/Expansion_F4.rbxm`, is not in git. Without it, the server log says `[SkyLift] Workspace.Expansion.F4 missing` and there is no lift to see.

## How to get there
1. Pick **Townsperson** or **Police** from the menu. Only people ride; animals take the trail.
2. Go to the west end of town. Where the westside street ends (about x -722, z -610), **Lift Road** runs south past the car park to the **SKY LIFT** station at the foot of the hill (about x -760, z -905). It is a long walk; a car is quicker. Park in the car park and get out with **E** before you go to the gate.
3. A gravel trail with steps and benches also climbs the hill beside the line. You can walk up or down instead of riding.

## What to do
1. Go up the steps into the station. At the glass gate a prompt says **Ride the sky lift to the Lookout**. Press **E**.
2. The screen says **Next cabin in N s**. A cabin comes every 25 seconds or so, and the board over the gate counts down. Stay by the gate: if you walk more than 14 studs away, you give up your place, and the game tells you so.
3. When the cabin is in and its doors are open, the gate arm lifts and you are seated. The view switches to **first person by itself**.
4. **Move the mouse to look around.** No button is needed and you can turn all the way round. The **I** key inverts up and down, as it does on foot. **V** switches to a view of the cabin from outside, and **V** again comes back.
5. Press **E** during the ride. You should read "You are on the sky lift: you get off at the top" (or "at the bottom" on the way down).
6. The ride takes about 65 seconds. At the top the doors open and you are standing on the platform with **Welcome to the Lookout**. Your legs and your usual camera come back.
7. Walk through the hall into the dining room. At the counter, **E** orders the hilltop lunch. It is free for now ("On the house today"), and it is put on a table by the window or on the terrace.
8. Go out onto the terrace and press **E** at the telescope. Move the mouse to look, use the wheel to zoom, and press **E** or **Q** to step back.
9. Ride down from the summit gate (**Ride the sky lift down to town**). It ends with **Back in town**.

## Please check
| # | What to look at | What you should see |
|---|---|---|
| 1 | The station from Lift Road | The lit SKY LIFT sign, steps up to the platform, the cable going up the hill over nine towers |
| 2 | The cabins | Six red and cream cabins moving smoothly, never jumping. They slow through the stations and their doors slide open and shut |
| 3 | Boarding | First person straight away, seated on a bench, facing along the cabin. You should not see your own body in the way |
| 4 | The free look | Smooth, with no shaking against the cabin walls. Shaking would mean the rider and the cabin are drawn a frame apart: please say so |
| 5 | Out of the windows | The plain, the hill face and the town falling away. Tell me how the town reads from up there: it is far away, and may be thin |
| 6 | V | The cabin from outside, following it; V again puts you back in your seat |
| 7 | Arrival | Standing on the platform, facing away from the cabin, with your own walking and camera back. Nothing stuck in the seated pose |
| 8 | The Lookout | The hall, the dining room, the counter, the fireside corner and the terrace. The rooms should look furnished and lit, and the terrace rail should sit below your eye when you sit |
| 9 | Lunch | A plate, a sandwich and a cup appear on the table named in the message, and are cleared after four minutes |
| 10 | The telescope | A narrow, zoomed view toward the town; you step back with E or Q; your camera returns as it was |
| 11 | Night | Lamps along Lift Road, lit cabins, lit station and Lookout windows |
| 12 | The trail | Gravel and steps on the ground, not sunk into the grass and not floating. Benches face the town |

## Known not done
- **Nothing has run in the real engine.** The server checks cannot run until the key's Luau Execution permission is back. These are untested: seating a person on an anchored seat, the seated height (the rider may sit a little high or low on the bench), and how riders look to *other* players.
- **No sound.** The cue points are named in `docs/AUDIO_BUDGET.md`; nothing is uploaded.
- **The lunch is free** until the wallet (`feat/wallet`) lands. Then the one charge is 10 cents, in the counter's handler in `src/server/Rides/SkyLiftService.luau` (`hilltop_lunch` in `src/shared/Economy/EconomyRules.luau`).
- **The view of town is far away.** The nearest houses are about 950 studs from the terrace. With streaming they may show as simple shapes with no trees, cars or people. The far-view work (lit windows of the Lookout from town, streaming the street the telescope looks at) is not built.
- **The hill is a mound on a flat plain**, steeper than "a slight hill". The trail is quicker on foot than the ride.
- **People the game was steering**, if you swap bodies mid-ride, are taken to the far platform and then try to walk back to where they belong, which is a long way.
- Up close: the tower wheels ride slightly above the cable, the two highest tower footings stand proud of the slope, and grass may show through the gravel in places.
- The kitchen and restroom doors at the Lookout are fronts only. There are no staff.
