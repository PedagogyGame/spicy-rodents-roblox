# Branch nooks: what to check (D34)

You asked: *"make sure there are little nooks in the branches, and that the user experience feels like they are a
squirrel, a little shift from running over the nodules, but still smooth movement feel and play, the points where the
branches are can have stash places off to the side and a little place to hangout, cozy! improve and add branching"*

## What changed

Every climbable tree in town (all 98 of them, the hollow trees and the planted ones included) now has these. They are
worked out from each tree's own branches, so any new tree added later gets them too.

- **Nodules.** Small knots sit along the top of every branch (about one every 5 to 8 studs; 4,324 in all). When your
  squirrel runs over one, its body gives a tiny bob and sway that is gone in 0.15 seconds. The camera follows the body,
  so you feel it a little too. Your speed does not change and you never stop or trip. A jump pressed at that moment is
  still a jump. Only your own screen draws this: the server and the movement checks never see it.
- **Nooks** (2 on each tree, 3 on the big ones; 220 in all). A little cupped hollow in the crook where a branch leaves
  the trunk. It has a dark floor, bark walls round the back and a soft low lip across the front that you step over.
  - To go in: run up a branch. Near the nook the hint **"E  step into the nook"** shows. Press **E** (no jump needed).
  - To leave: **S** backs out to the branch, then **E** puts you back on the branch.
- **Stashes** (one beside every nook). A knot-hole in the bark next to the cup. Standing in the cup, **"E  stash"**
  shows.
  - **E** with nuts in your paws puts them all in. Each knot-hole holds 12 nuts for you.
  - **E** with empty paws takes them back out, up to the 9 you can carry.
  - Every player has their own nuts in every knot-hole. Nobody can take yours.
  - Acorns show in the hole on your screen while you have nuts in it.
  - They are kept as long as the server runs (like the hollow trees' meters); they are not saved when you leave.
- **Hangouts** (on the trees with a wide gap between branches; 84 in all). A flat mossy ledge in the crook round the
  trunk, with two twigs and a tuft of leaves. There is room for three squirrels.
  - To get on: run up the branch and press **E** at **"E  step onto the ledge"**.
  - To sit: stop on the ledge (or in a nook's cup) and press **R** (a gamepad's **Y**; on a touch screen, the **SIT**
    button). The squirrel sits up on its haunches facing out of the tree.
  - To get up, use the same ways as getting up from a lounge seat: **R** again, **Space**, a step with W A S D or the
    stick, or the **STAND** button.
- **More branching** (2 short side branches on each tree, 3 on the big ones; 220 in all). Each one leaves the middle
  of a long branch, rises a little and ends in a twig and a tuft of leaves.
  - To take one: on the branch, press **A** or **D** to pick it, then **E**. Just **E** works where it starts.
  - Each one is another place to run to, and to leap from.

## Checked by the tests

- The real squirrel movement was driven along every one of the 524 new paths (nooks, ledges and side branches) with
  the server's movement check on every frame. Each run went in from its branch with E (no jump), out to its end, back,
  and onto the branch again. There were 0 rejected frames and no falling through. The largest move in one frame was
  0.18 studs.
- Every new path stays:
  - outside the bark;
  - at least 6 studs over the ground;
  - out of the buildings;
  - 2 studs or more from every other path;
  - no steeper than the old branches.
- A stash works only from inside its cup. Standing on the branch or climbing the trunk past it does nothing.

## What it costs (phones)

- **The town's parts: unchanged** (26,367 of 27,000). None of this is baked into the town.
- Your screen draws the nooks only on the trees near the camera, up to 150 studs away. That is at most 60 small parts
  a tree (2 to 3 trees at a time is typical). It also draws the knots of the one tree you are at, at most 60.
- None of these parts is solid, none casts a shadow, and nothing new runs every frame on the server.
- Each frame on your own screen there is one small sum for the knots.

## Please check in Studio

1. Climb a street tree (WESTSIDE STREET ELM 0 is a good one), run out along a branch, and feel the knots. Is the bob
   too little, too much, or right?
2. On the same tree, step into a nook with E. Sit with R, then get up with Space and with W. Does it feel cozy, and
   does getting up always work?
3. Pick some nuts up on the ground and run them to a nook. Press E to stash them, then press E again to take them
   back. Do the acorns show in the knot-hole?
4. On the ESTATE SYCAMORE SOUTH tree, find a hangout ledge. Can you and two friends sit on it together?
5. Take a side branch with A/D and E. Does it make the tree more fun to run around?
6. Do the nooks look attached to the tree with the real tree models? The pictures in docs/renders/branches use
   plain stand-in bark. Tell us if a nook or ledge floats or sinks into the bark on a particular tree.

## The pictures

`docs/renders/branches/` (stand-in bark, the nooks exactly as drawn in the game; grey-brown squirrel stand-ins):
`t1_*` WESTSIDE STREET ELM 0, `t2_*` ESTATE SYCAMORE SOUTH, `t3_*` APPLE 1. For each tree:

- `_tree`: the whole tree;
- `_nook`: a squirrel in a cup with acorns in the stash beside it;
- `_hangout`: three squirrels on a ledge (not on APPLE 1: its branches are too close together for one);
- `_spur`: a side branch;
- `_knots`: a squirrel's view down a branch over its knots.
