# The hollow trees, made gnarly: what to look at (10 minutes)

## Update for your D33 note (inside H1): read this part first

Your note, with the screenshot from inside the HIGHLAND ELM: "the hollow log shows up as this, from within, I would like for the view to be more verticle within the tree trunk with the option to run out on those branches, try to fix this up, and while you do so, patch stuff together with more textured gnarliness inside the hollow part, but also grainularity, strike these physics balances."

What was wrong in your picture: the inside wall was a few wide flat boards with big gaps, and from inside a tree the game does not draw the tree's own bark, so through every gap you saw the lawn, the sky and the town. The camera also faded boards near it, which opened more gaps. The two black discs were the dark knothole marks painted on the outside of the bark, seen from behind. The ledges were plain planks.

What is there now:
- **A closed wall.** The inside of every hollow tree is lined all the way round with narrow upright staves, from the floor to the roof: about 20 round in the HIGHLAND ELM, 10 to 14 in the narrow shafts and the small one-chamber trees, 21 or 22 in the two wide ones (H5 and H6). They overlap a little, so no gap opens from any angle, and where a trunk bends they are cut into shorter pieces so they follow it. The only openings are the real holes: the hole at the ground, and the holes up the trunk you can jump out of.
- **The holes up the trunk** are lined back to the bark with dark wood (a sill, a top and two sides), so each reads as a dark recess in the wall with daylight in it, not a disc. The black knothole marks on the outside of the bark are hidden on your screen while you are inside the tree (other players outside still see them).
- **Grain.** The staves, the floor and the roof wear the tree's own bark texture on their inside faces (the same bark picture the tree wears outside), each stave at its own offset and shade, with a few dark streaks. Everything inside is the Wood material, so the ledges, roots and knots have wood grain too.
- **Gnarl.** The ledges of H1's climb are now round shelves, like bracket fungus growing out of the wall, overlapping up the climb, instead of planks. The bigger knots have a raised middle, so they read as rounded bulges, and every knot now grows out of the wall instead of standing off it. The roots across the hollow are as before.
- **The view is vertical.** Inside a climbing tree the camera now sits close behind and a little below the squirrel and looks up the trunk (about 34 degrees up, and a little more over the squirrel's head), so you see the climb above you and the daylight at the holes, with the squirrel low in the picture (all told it looks about 55 degrees up). The mouse and the right stick still look around from there; let go while climbing and it drifts back to looking up. It never fades the wall, so it never shows the town through it. In the one-chamber trees the view stays nearly level (their roof is just over the squirrel's head).
- **Getting out onto the branches.** Nothing about the holes or branches changed. When you reach a hole up the trunk, a short message says **"Space: out onto the branch"** (at the top hole: "Space: out onto the branch · W: on out of the top"). E at the hole still takes the branch too.
- **Physics: unchanged.** The climbs, ledges, roots, holes and branches are the same paths as before, to the hundredth of a stud (checked by comparing the compiled paths). Everything inside the tree is still for looks only; the squirrel runs on its paths as before. All the tests that run the real squirrel controls up every climb and out of every hole still pass with no rejected moves.

### What to look at (5 minutes)
1. Run into the hole at the foot of **H1**. Does the wall look closed and round? Do you see any lawn or sky except through the holes?
2. Hold **W**. Does looking up the trunk feel right? Too steep, or not steep enough? (The angle and how far behind the squirrel the camera sits are two numbers I can change.)
3. Do the round shelves read as growths or fungus? Do the knots look rounded enough?
4. Does the bark texture on the inside walls look right, too busy, or too dark? (I could not see it: the offline pictures below show plain colours.)
5. Stop at a hole: you should see the message, then the view looks out of the hole. Press **Space**.
6. Try **H2** and **H12** (the narrow shafts) and a one-chamber tree.

### The pictures
Offline renders from the player's camera, before and after, are in `docs/renders/hollows/`: `before_*.png` and `after_*.png` (H1 low, middle, high, passing a hole, peeking out; H2; H12; H3). They show plain colours (no bark texture), a grey box stands in for the squirrel, and a dim fill light stands in for the game's ambient light. Before: wide gaps with lawn and sky, plank ledges, the camera looking sideways. After: closed walls, the shelves climbing up the trunk above the squirrel, daylight in the lined holes.

### Cost (for phones)
- **596 plain parts** for all the hollows (it was 445): the town's 26,367 and these make 26,963, under the 27,000 budget (a test checks this). H1 is 218 parts, H2 87, H12 81, a one-chamber tree 18 to 31.
- About **21,500 triangles** for all the hollows together (it was about 12,500; counting a cylinder as about 66): the round shelves and knots are cylinders. Only the tree you are in is close enough to matter.
- **333 bark textures** (one on each stave, floor and roof); they use 4 bark pictures the trees already load.
- Lights unchanged (25, no shadows); the daylight at each hole is a little brighter.
- Per frame, only while you are inside a tree: the same as before, plus a check for a nearby hole for the message.

---

*Below: the D32 notes (1.8). Where they differ from the update above, the update is current: the climbing view now rests looking up the trunk, and the costs are the ones above.*


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
