# The roof vent over the bowling alley: what to look at (15 to 20 minutes)

This is the squirrel's secret way into the bowling alley that you asked for (addendum D9, D10). A squirrel climbs a house next door, jumps to a tree branch, crosses to the alley's roof and slips in through a vent. Inside, it crawls through the steel trusses over the lanes. People bowling below will spot a squirrel that walks about, but not one that creeps. Players who are people can climb metal stairs at the back of the alley and guard the vent from a railed platform. Everything below has been tested without a screen: the squirrel's whole climb runs on the real squirrel controls, and the stairs were checked with a person's size, step and jump. Only you can judge how it looks and feels. Wherever something is off, tell me what you pressed and what happened.

## Before the build
The alley, the house, the tree, the vent and the stairs are all part of the alley's own bake. Run `lune run tools/bake/attractions.luau` before building the place. It writes `build/Attractions.rbxm`, which is not in git.

## Where it is
Go to the bowling alley (about x 1300, z -420). Walk round its east side to the open yard behind the games room wing. There you will find:
- a cream two-storey house with a slate roof and a red front door (about x 1496, z -440);
- a big tree between the house and the alley, with a metal collar round its trunk;
- the metal stairs going up the wing's back wall, three flights (their foot is at about x 1449, z -453);
- the vent: a grey box with louvres on the wing's roof, with a railed platform round it.

## As a squirrel (pick **Squirrel**, or **Spicy Rodent**)
Keys: **W A S D** run, **Shift** sprint, **Space** leap, **E** grab, **Q** drop, **Ctrl** creep.
1. Run at the white drainpipe on the house's street-side corner (north-east, by the porch) and keep **W** held: you climb it, run along the gutter and up onto the ridge.
2. On the ridge, turn toward the tree and run to the end of the ridge. **Jump now to reach the branch** appears at the end: press **Space** (keeping **W** held is fine). You land on the long branch.
3. Keep **W** held along the branch, past the top of the trunk, out over the alley's roof. At its end you read **Q: drop onto the roof**. Press **Q**.
4. Walk to the louvres on the vent box's east face (the side facing the platform). One slat near the bottom is bent: walk into it. You go through the box and along the duct, then come out of a boot onto a steel truss over lane 18.
5. In the trusses: walk along a beam over the lanes. The people bowling below can see you. An eye appears at the bottom of your screen and fills as they get suspicious. Past about a third it says **They're watching: creep (hold Ctrl) or get back in the vent**. Hold **Ctrl** and you creep slowly: that is all but safe. If the eye fills you read **Spotted!**, you glow orange for 6 seconds, and someone below says something like "There's a squirrel in the rafters!". Nothing hurts you. If you are the Spicy Rodent, people in the hall run, the police are sent to the alley's front door, and everyone in the hall reads **The Spicy Rodent is in the rafters over lane N! The police are on their way.**
6. Other things to try: leap from beam to beam; walk the light rails just above the lamps (they are lit, so you are seen sooner); press **Q** over a lane or an approach to drop down; and go back out the same way (the vent works both ways), then down the branch and **Q** into the yard.

## As a guard (pick **Townsperson** or **Police**)
1. Climb the metal stairs at the back of the games room wing. At the top is a railed walkway and platform round the vent box. The rails keep you on it: you cannot walk out over the alley's roof.
2. Stand on the strip in front of the louvres. From there you can see the house's ridge, the jump and the branch.
3. When a squirrel comes to the louvres, press **F** to kick it. A kick reaches a squirrel at the louvres, but not one that is already inside the box.
4. When a squirrel is spotted in the rafters, everyone in the hall and on the platform reads **A squirrel in the rafters over lane N!**
Guarding pays nothing for now (your question Q8's default), and the kick is a guard's only tool (Q7).

## Please check
| # | What to look at | What you should see |
|---|---|---|
| 1 | The yard from the street | The house, the tree and the stairs read as a believable back yard, not a puzzle |
| 2 | The climb | Up the drainpipe, along the gutter and onto the ridge without snagging; the squirrel drawn on the roof, not floating over it |
| 3 | The jump | Easy enough from the end of the ridge. You can also jump from up to about 5 studs short of the end with **W** held, or from further back sprinting |
| 4 | The branch | Running along its top, never through it, and **Q** dropping you onto the roof beside the vent |
| 5 | The bent slat | You can see which slat is bent from the roof and from the platform |
| 6 | Inside | The duct and the boot feel enclosed; you come out onto the beam without a jump or a pop |
| 7 | The hall from below | The raised roof, the steel trusses and the lamps on their rails look like a real bowling alley's ceiling |
| 8 | Sneaking | Creeping with **Ctrl** under the bowlers' eyes is safe; walking about in front of them gets you spotted in a few seconds. **Judge the balance:** one quick dash straight across the hall past a single bowler fills the eye to about two thirds but does not get you spotted |
| 9 | The stairs | Climbing feels normal, with no bumps on the steps or the landings |
| 10 | The platform | You can guard the louvres and see the house's ridge, and you cannot get off onto the roof |
| 11 | The kick | It lands on a squirrel at the louvres and not on one inside |

## Known not done
- **Nothing here has run in the real engine.** Please check especially: walking up the stairs (each flight has an invisible ramp under it for people's feet), the orange glow, the eye at the bottom of the screen, and the callout.
- **The tree is a stand-in** built from simple parts, until the tree work makes a proper one. It has no climbing route: the jump is the only way onto the branch (your question Q11's default).
- Left out on purpose: a 60-second "hall alert" that would make everyone more watchful after a sighting (it would change the sneak balance that has been tuned and checked); reporting sightings anywhere else in the town (that part of the game does not exist yet); a member of staff with a broom (the alley has no staff yet).
- The hints are only **Jump now to reach the branch** and **Q: drop onto the roof**. There is no hint at the drainpipe or at the collar round the trunk.
- No pay for guarding, and no tool for a guard but the kick.
- **No sounds** for the vent or the sightings yet.

## Your roof and rafter kit
- **Used:** the two ridge perch planks with their 16 grips, on the house's ridge (the squirrel runs on their top), and 12 of your gutter brackets under the house's gutters. Your pieces are plain boxes, so they are built as parts directly in the game at 3 studs to the metre, the scale your shop pack uses. Nothing needed uploading.
- **Not used, and why:**
  - The full gable roof (02): it is 34.5 by 45 studs and the house is 24 by 24. The routes and the jump are built round the house, and fitting the roof would mean stretching it by different amounts each way.
  - The rafter bay (01): it is a wooden gable bay, 11.1 m wide and 3.9 m tall. The lane hall has a flat steel roof 127 studs across, so the trusses are steel and built from parts.
  - The eave landings and slope footholds (03): on the house's north slope they would stand across the gutter route.
  - The gutter runs and downpipes (05): they are 15 m long. The house's own gutters and drainpipe are drawn round the squirrel's climb.
  - The collider proxies (04): the house's own roof boards already stop people and animals.
  - The route graph in Specs: it is a local prototype. The squirrel runs on the game's own routes, drawn to match the house, the tree and the vent.
