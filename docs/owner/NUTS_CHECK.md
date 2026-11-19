# Nuts and the nut meter: what to try (10 minutes)

You asked for nut foraging and a nut meter next (D16 #22). Squirrels now find nuts around the town, carry up to nine, and run them into a hollow tree to fill its meter. A small meter on screen shows what you carry and how full your tree is.

Everything below was tested without a screen, on the real town and the real server rules. Only you can judge how it looks and feels.

## Where the nuts are

There are 49 spots. Each one is a little pile of acorns on the grass, and each nut grows back on the game clock.

| Kind | Where | Nuts in a pile | One grows back every |
|---|---|---|---|
| Under nut trees (18 spots) | three round each acorn oak that has open grass under it: the BUR OAK in the core (next to hollow H3), Villa Oak South, and the four Westside shade oaks | 3 | 4 minutes (a third of a game day) |
| Yards (17) | where the old gardens, bird feeders and compost bins were | 2 | 6 minutes |
| The park (11) | the old nut caches and the Tabasco garden | 2 | 4 minutes |
| Big piles (3) | beside the two premium hollows: H1's garden and feeder, H2's feeder | 6 | the whole pile again in about a game week (85 minutes) |

When every pile is full there are 128 nuts in the town. A pile that nobody touches stays full. It does not save nuts up.

Four acorn oaks have no pile. Both Shop Oaks stand in the sidewalk. Estate Oak South 1 is inside the mansion's walls. The Treehouse Oak's ground is under its treehouse.

## What to press

1. Play a **Squirrel**. The meter appears at the top of the screen, beside your health bar. It shows an acorn and **0/9**, and the line **Find nuts: oaks, yards, the park**. On a phone, the meter sits in the top-left corner.
2. Go to the **BUR OAK**, the big oak in the core with hollow H3 at its foot. You will see three little piles of acorns on the grass round the trunk.
3. **Run over a pile.** There is no key to press, just as with a hollow's hole. Your squirrel dips its head and you hear a small tick. The meter flashes **+1** and counts up, one nut every half second until the pile is gone.
   - A squirrel standing on a fence or a branch over the pile does not pick it up.
4. At **9/9** the count turns amber and you are told **Your paws are full (9 nuts): run them into a hollow tree**.
5. **Run into H3's knothole** at the foot of the oak. The meter shows **H3** with a bar and the line **Nobody's: fill to 70% to claim**. Your nuts go in and it flashes **stored 9**.
   - H3 holds 120 nuts. To claim it you need 84 nuts (70 %), and at least 12 of them must be your own.
   - Once it is yours, the meter always shows your tree and how full it is, with a tick on the bar at 70 %.
   - Inside another squirrel's tree, the bar is grey and the line says **Not yours: you keep your nuts**.
6. **Let your squirrel go, or get knocked out.** Any nuts it was carrying are lost. Nuts already stored stay in the tree.

## What the computer's squirrels do

They forage lightly. A computer squirrel whose run passes close to a pile stops for about three seconds and eats one nut, with the same head dip.

They never carry nuts away, so they never fill or claim a hollow. You compete with them for nuts, never for trees.

Their runs are mostly up in the trees and along fences, so this does not happen often. Over six minutes, about four nuts were eaten across the whole town.

## The Spicy Rodent and nuts: nothing

The rodent cannot pick nuts up, and the meter does not show while you play it. It already has its own needs:
- it claims no tree;
- it heals by resting in a hollow or a drain while it is fed;
- it is fed by biting.

If nuts healed it, a pile of acorns could stand in for the chase. *Default: nuts do nothing for the rodent.*

## Fair play (for the record)

- **The server decides every pick-up.** It does not take the squirrel's position from the player's computer. It uses where the server's own movement check last accepted the squirrel.
  - A cheat that moves the squirrel's body onto a pile, without the server accepting the move, picks nothing up.
  - A squirrel that has just been snapped back picks nothing up until it moves cleanly again.
- **Storing nuts in a tree works the same way.**
- **Picking up is limited** to one nut every half second, nine at most.

## What only you can judge

- **The pace.** Should piles grow back faster or slower, and should squirrels carry more than nine? *Default: as in the table above; nine.*
- **Picking up by running over a pile, with no key.** *Default: as built.* Phones need no extra button this way.
- **The look of a pile.** Each acorn is a small brown ball under a darker cap, about a third of the squirrel's width. Are they easy enough to spot on the grass? Should piles have a marker on a map later?
- **The tick.** The tick you hear is a stand-in, the store's flashlight click played a little higher. A better nut sound can replace it in one line.

## Not built yet

- Taking nuts back out of your tree.
- Winter. The brief says less foraging and a survival check, but the game has no winter yet.
- Nuts in the squirrel's rank.
- A map layer that shows the piles.

## Costs (for phones)

- **Acorns:** 128 acorns of two plain parts each, so 256 parts. They have no shadow, no collision, no textures and no meshes. The game streams them in, so a phone only draws the few piles near the player.
- **The server:**
  - it checks the players' squirrels ten times a second, against the 49 piles;
  - it checks the computer's squirrels every four seconds;
  - it regrows the piles once a second.
  - The worst step measured was **0.07 ms**, with 14 squirrels.
- **The meter:** one small screen panel. It changes only when the server changes a number, and does no work in between.
- **The network:** a few values on the player when a nut is picked up or stored, and one number on the pile.
