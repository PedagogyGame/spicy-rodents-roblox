# The hollow trees: what to look at (10 minutes)

Your brief (section 3) asks for twelve hollow trees a squirrel can claim, and a fallen hollow log to hide in. Addendum D6 says they run "on the same mechanics" as the ball return. They do: every hollow's inside is an enclosed squirrel run, exactly like the ball return and the storm drains.

Everything below was tested without a screen, on the real squirrel controls and the real server checks. A test cannot tell me how it looks and feels, so this list is the part only you can judge. The pictures are offline renders in `docs/renders/hollows/` (remake them with `lune run tools/review/hollows.luau` and `tools/review/render.py`). The bark in them is a plain stand-in, because the Blender trees cannot be drawn offline. The `_cutaway` pictures cut the bark and the boards away on the camera's side, so you see the inside against the far wall: `h1_cutaway` the whole spiral, `h2_cutaway` and `h12_cutaway` the two climbing trees, each with a `_low` and `_top` close-up, and `log_cutaway` the log.

## Where they are

| Hollow | Tree | Where (studs) | Kind |
|---|---|---|---|
| H1 | HIGHLAND ELM (the giant, north side) | (220, 347.5) | **premium**: a spiral ramp up the inside, three landings, out at the top onto the bark |
| H2 | SYCAMORE (core) | (-92.5, 72.5) | **premium**: a climb up the inside wall, a hideout shelf, a knothole onto a bough part-way, out at the top along another bough |
| H12 | AMERICAN ELM (core) | (80, -92.5) | **escape tree**: three ways out (the ground hole, a knothole onto a bough, the top onto another bough) |
| H3 to H11 | BUR OAK, Pump Elm, OLD WATCH SYCAMORE, SENTINEL OAK, Treehouse Oak, Chilis Sycamore, Estate Oak South 2, Westside 4 shade oak, QUAY WILLOW | spread over the town | one chamber behind a knothole at the foot |
| LOG | the fallen log in the north park | (-47.5, 940) | a short run through, open at both ends; a hiding place, never claimed |

## What to press
1. Play a **Squirrel** (or the Spicy Rodent). Every hollow has a dark knothole at the foot of its trunk. **Run into it**: there is no E to press, as with the ball return's grille, so a squirrel being chased dives straight in.
2. **One-chamber trees:** you run across the floor to the back. The screen says **Hidden in the hollow: nobody can see you in here (S runs back out)**. Press **S** and you come out of the hole on your feet.
3. **H2 and H12:** hold **W**. You cross the floor and climb the inside wall. Part-way up, **E** at the knothole takes you out onto that bough (A or D picks it as you climb). In H2, the other A/D side is the **hideout shelf**; S takes you off it and back down the shaft. At the top, keep holding W and you run out along the top bough.
4. **H1, the spiral:** hold **W** to climb the ramp, whichever way the camera looks; **S** goes back down. The ramp has three flat landings, and at the top you come out of a knothole onto the outside of the trunk, still climbing. In from the hole to out at the top takes about 6 seconds.
5. **The log:** run in at one end and out of the other.
6. Inside, away from a hole, **Space, Q and a click do nothing**: there is no jumping through the bark.

## What being inside does
- **People cannot see you.** Inside a hollow you are out of the town's sight and hearing, as in a drain. People, the fox and the police lose you. At the hole, in the open, you are seen again.
- **The Spicy Rodent cannot bite from inside**, and it **rests** there: it heals at the hollow rate while fed, as in a drain.
- **Claiming** (brief section 3): carrying nuts into a tree raises its meter. The squirrel whose nuts lift it to **70 %** owns the tree, for as long as the meter stays near 70 % and it visits at least once every **three game days**. Nobody can take nuts from someone else's claimed tree, and nobody puts nuts into it either: a squirrel inside someone else's tree keeps what it carries. The meter slowly empties, by 3 % of the tree's capacity per game day. A claimed tree shows a small orange pennant beside its hole, and the tree carries `Meter`, `Owner`, `OwnerName` and `Claimed` for the map and the HUD to show later.
- **Two small rules so a claim is fair.** First, the owner keeps the tree until the meter falls below **60 %**, not 70 %, so a tree claimed at 75 % is not lost to the first day and a half of emptying. Second, to take a tree nobody holds, a squirrel must bring in at least **a tenth of its capacity itself**, so one nut cannot take a lapsed tree and everything stored in it.
- **One tree each** (your D16 #21): a squirrel that holds a tree cannot claim a second. See `OWNERSHIP_CHECK.md`.
- **A claim belongs to the player, not the body.** If you let your squirrel go, your claim stays yours (it lapses if you stay away three game days), and the computer squirrel that takes the body back does not own your tree. Nuts are carried by the body: letting it go, or being knocked out, loses them.
- A squirrel carries **at most nine nuts**.

**Nuts to pick up are now built** (19 November): 49 piles under the acorn oaks, in yards and in the park, and a nut meter on screen; see `docs/owner/NUTS_CHECK.md`. Still not built: taking nuts back out, the winter survival check on the meter, and the squirrel rank's nut count.

## What only you can judge
- **H1 is in the HIGHLAND ELM giant, not the park tree by the Tabasco garden.** The park tree's trunk is 4 studs across and the squirrel is 1.6 wide, so no ramp fits inside it. The giant is 9.4 across. H1's premium garden and bird feeder are listed beside the giant but are not built, the same as H2's. *Default: the giant, as built.*
- **The ground holes are big** (1.9 by 2 studs), because the squirrel's body has to fit through them. Do they look right on the bark?
- **Inside, the walls are plain wooden boards** (rings of planks, a floor and a roof, with one dim warm light per chamber; each light only reaches as far as the bark, so it never lights the lawn outside at night).
- **The log has an invisible stop just inside each end.** A squirrel that walks at the end from the side stays outside; one that runs straight in is taken through as before. The Blender bark is not drawn from inside, so these boards are what you see. Offline, the spiral reads very dark between its landings (`h1_ramp` views). Only the engine can say how dark it really is. Are the boards good enough, or should the insides get art of their own?
- **Moved trees:** H4 is now the Pump Elm and H9 Estate Oak South 2. In the baked town, Estate Oak South 1 stands inside the estate mansion's walls, and both Shop Oaks stand in the sidewalk curbs.
- **The log** is the north park's hollow log from v5.4, now real: about 3.6 studs across and 23 long. The old grey box at that spot is now invisible.
- **How fast should a tree's meter empty?** It loses 3 % of its capacity each game day, and a game day is 12 real minutes. So a full tree that nobody feeds falls below the 60 % keep line after about 13 game days (2 hours 40 minutes), and an owner who claimed at 75 % must bring nuts within 5 game days (1 hour). Is that the pace you want? *Default: 3 % a game day.*

## Costs (for phones)
- **372 plain parts in all**, about 7,000 triangles, no shadows, and 17 dim point lights (no shadows): one on each floor, and one at each landing or store above it. Each light reaches 1.5 to 4.9 studs, no further than the bark round it:
  - H1: 143 parts;
  - H2: 57;
  - H12: 50;
  - each one-chamber tree: 9 to 14;
  - the log: 13 (its boards, its floor and its two invisible end stops);
  - one pennant per claimable tree.
- **The trees themselves are unchanged.** No mesh was re-uploaded.
- **Per frame:** the hiding check is one cylinder test per hollow for each squirrel. The meters update once a second.
