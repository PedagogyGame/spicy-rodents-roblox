# The hollow trees, made gnarly: what to look at (10 minutes)

Your note from playing 1.7 (D32): "those spiral staircase way inside the tree is too uniform, have it be knarly, knotted sometimes, and realistic, allow the squirrel to actually look around and of course be able to smoothly adequately jump out of any hole peeking out of that tree, preferably onto a branch, to then wander out... edit the inside of the hollow trees a bit."

Everything below was tested without a screen, on the real squirrel controls and the real server checks, in the baked town. A test cannot tell me how it looks and feels, so this list is the part only you can judge. The pictures are offline renders in `docs/renders/hollows/` (the bark in them is a plain stand-in; the real trees are the Blender meshes). Remake them with `lune run tools/review/hollows.luau` and `tools/review/render.py`.

## What changed

**The climb inside the HIGHLAND ELM (H1)** is no longer a staircase round a post. It is a run of rough ledges along the inside wall that:
- swings in and out from the wall (by up to about a stud) to get round the **knots** that bulge from the wall;
- gets steeper and shallower as it goes (never steeper than before), with **flat ledges** here and there, three of them the storage chambers;
- **turns back the other way twice**: a gnarled root crosses the middle of the hollow, the squirrel runs across it and carries on round in the other direction (a switchback);
- leans with the tree, as before.

The heartwood post is gone, so you can see up and down the hollow. Climbing from the ground hole to the top takes about 6.5 seconds (it was 5.7).

**The SYCAMORE (H2) and AMERICAN ELM (H12)**: their climbs used to go straight up one side. Now each winds round its wall to the knothole part-way up and back to the top, a different way in each tree, with knots on the walls the climb leaves free.

**The nine one-chamber trees** each have a few knots in their walls. Every tree's wall boards are now each a slightly different shade, so the wall reads as bark rather than a barrel.

**Every tree is different.** The wander, the steepness, the knots and the shades come from a fixed pattern per tree, so the same tree is the same every time and no two trees match.

**Light.** Besides the warm lights in the chambers, a dim cool daylight now comes in at each hole up a trunk.

## Holes and getting out
Each climbing tree now has holes up its trunk, and each one has a branch just outside it:

| Tree | Holes up the trunk | Where Space lands |
|---|---|---|
| H1 HIGHLAND ELM | three knotholes (about 5, 24 and 30 studs up) and the top hole (34) | a short branch under each hole (new) |
| H2 SYCAMORE | a knothole (about 25 up) and the top hole (36) | the knothole: the tree's own bough 1 (a full leap up onto it); the top: a short branch under the hole (new) |
| H12 AMERICAN ELM | a knothole (about 28 up) and the top hole (31) | a short branch under each (new) |

The short branches are new branches of those same trees, drawn as plain bark-coloured parts, not part of the Blender tree meshes.

## What to press
1. Play a **Squirrel** or the **Spicy Rodent**. Run into the dark hole at the foot of H1 (the giant on the north side). Hold **W** to climb, and **S** to go back down.
2. **Look around**: move the mouse (or the right stick) while inside. The view turns right round the squirrel's head, and up and down the hollow. Where the hollow is too narrow to stand behind the squirrel (the shafts), it looks out of the squirrel's own eyes. Anything of the inside that would block the view fades. Let go of the mouse while climbing and the view drifts back behind the squirrel. Turning the view never turns the squirrel: W still climbs.
3. **Peek**: stop at a hole up the trunk. The view moves to the hole and looks out of it (you can still turn it a little). You are in the open there, so people can see you.
4. **Jump out**: at a hole, press **Space**. The squirrel hops out onto the branch just below (on H2's knothole, it leaps up onto the big bough). **E** at a hole also takes you onto the branch. Pressing Space while still climbing past a hole also works.
5. **Wander out**: on the branch, **W** runs out to its end (the screen says "The end of the branch: Space leaps on, Q drops down, S runs back to the trunk"), **S** runs back to the bark, and **E** there goes back in at the hole. From the end of a branch, Space leaps on and Q drops to the ground.
6. Inside, away from a hole, **Space, Q and a click still do nothing**: there is no jumping through the bark.

## What only you can judge
- **Does the climb feel gnarly enough, or too busy?** The amount it swings in and out, how steep it gets, how many knots and roots: all are numbers I can turn up or down per tree.
- **The root crossings.** The squirrel turns quite sharply where it steps onto and off a root (the hollow is only about 5 studs across). Does it read well?
- **The look around.** Is the camera close enough? Too close? Does it drift back behind the squirrel at the right speed?
- **The peek.** The view sits at the hole's outer face. Is that the right place?
- **The new short branches** are plain bark-coloured cylinders sticking out under each hole. Are they good enough, or should the Blender trees grow real branches there (an art job, and a mesh re-upload)?
- **The hop out.** It is a short hop forward and a drop of about a stud onto the branch, about a third of a second. Too small, or about right?
- **H2's knothole** now sits a little higher than the bough under it, so the leap out lands on the bough. The other holes hop down onto their own short branch.

## Not changed
- The one-chamber trees still have just one chamber (your brief: nine single-chamber trees). They only got knots and shaded boards.
- The fallen log is unchanged.
- The rules for being inside (hidden, the rodent's rest, claiming with nuts) are unchanged. The server's movement checks were not edited; they read the new runs the same way as the old ones.

## Costs (for phones)
- **445 plain parts in all** (it was 360), plus one pennant per claimable tree: H1 176 (it was 143), H2 68, H12 64, each one-chamber tree 12 to 17, the log 13. About **12,500 triangles** for all the trees together (it was about 7,000), no shadows. The knots are short cylinders, not balls, which keeps the count down.
- **25 dim point lights, no shadows** (it was 17): the 17 warm ones as before, plus one dim daylight just inside each of the 8 holes up the trunks. Each one reaches no further than the bark round it.
- **8 new short branch routes** (the new branches under the holes).
- **Per frame, only while a squirrel is inside a hollow**: the look-around does one short ray and one small nearby-parts query to fade what is in the way, and a check for a nearby hole. Nothing new runs outside the trees.
