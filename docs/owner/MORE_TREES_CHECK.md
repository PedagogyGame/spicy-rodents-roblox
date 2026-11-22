# More trees: what to check (D34, D35)

You asked (D34): *"add even more of the tall tree models, even taller before, with a large scattered introduction of
pine trees and other nut trees, making the map have more trees!"* and then (D35): *"make all trees climbable"*.

## What changed

**The map has 442 trees now, and every one of them can be climbed.** Before there were 147: the town's 98 climbable
trees and 49 that had no way up (the 32 conifers on Lookout Hill, the 5 hedgerow oaks and the 12 orchard apples under
the sky lift).

| | Before | After |
|---|---|---|
| Trees on the map | 147 | 442 |
| Climbable trees | 98 | 442 |
| New trees (the "woods") | none | 295 |
| Trees that had no way up | 49 | 0 (each has a trunk to climb now) |

The two maps `docs/renders/trees/cover_before.jpg` and `cover_after.jpg` show every tree from above (north up, east on
the left, like the game's map). The town's own trees are mid green; the new pines are dark blue-green, the new nut trees
olive, the three giants dark green; a red ring marks a tree that has been given its climbing route.

**The new trees, 13 kinds:**

| Kind | How many | Height (studs) | Climbing |
|---|---|---|---|
| KING OAK (giant) | 1 | see below | trunk to 150 studs, ten big limbs from 14 to 138 studs up |
| GREAT ELM (giant) | 1 | see below | trunk to 170 studs, nine limbs rising like a vase |
| OLD BEECH (giant) | 1 | see below | trunk to 148 studs, nine wide spreading limbs, the lowest 12 up |
| WHITE PINE | 54 | about 96 | the trunk to near the top; six branches as ladder rungs, every 12 studs |
| NORWAY SPRUCE | 45 | about 78 | five drooping rungs |
| BALSAM FIR | 18 | about 58 | four short rungs on a narrow spire |
| RED PINE | 40 | about 105 | a tall bare trunk (two dead stubs to rest on), three rungs in the high crown |
| BLACK WALNUT | 20 | about 68 | four main limbs |
| HAZEL (a nut bush) | 20 | about 22 | the main stem and two limbs |
| SWEET CHESTNUT | 18 | about 72 | four main limbs |
| SHAGBARK HICKORY | 12 | about 84 | a tall trunk and four limbs |
| WHITE OAK (acorns) | 48 | about 64 | four wide limbs |
| PIN OAK (acorns) | 17 | about 74 | four limbs |

The three **giants** stand alone, each in open ground: the KING OAK west of the old town, the GREAT ELM south-west
toward Lookout Hill, the OLD BEECH in the north meadow. They are about 1.3 to 1.4 times the HIGHLAND ELM, the tallest tree
until now (175 studs).

**Where the woods grow:** in the town's parks, yards and verges (90 trees, spread out); copses along the west and south
edges of the map (55 each, denser); a pine grove on the ridge between the Quay and the off-road field (22); pines among
Lookout Hill's conifers (12); copses on the off-road back field's hills (14); a row of pines and oaks in the north meadow
behind the beach (14); copses in the south-east (30). Every one keeps clear of roads, sidewalks, driveways and paths,
the lots' buildings, doors, the street lamps and poles, the telephone wires and the sky lift's cable, the kite fields,
the river and the beach, the other trees' crowns and the nut spots. A spec holds every tree to that.

**Nuts:** the game's nuts are one kind (no walnut or acorn items), found at nut spots. Twelve new spots now sit under
twelve of the new nut trees in the town (two walnuts, chestnuts, hickories, hazels, white oaks and pin oaks), so there
are 61 spots (was 49) and 164 nuts when every spot is full (was 128). The trees show their nuts: acorns, green walnut
husks, spiky chestnut burrs, hazelnuts and hickory nuts; the pines carry cones.

## How to climb them

Exactly like the town's trees: run into a trunk and the squirrel climbs it; press A or D to pick a branch as you climb
(the lowest come up first), hold W to go onto it. On a pine, the rungs are short level branches every few studs: climb,
step onto a rung, back onto the trunk, on up. Every new trunk and branch was climbed and run by the real squirrel
controller in a test (344 trunks to the top, 1,349 branches to the tip), and the server's movement check rejected none
of its frames.

## What you see before and after the upload

- **Before the models are uploaded** (now), each new tree is a stand-in: a brown trunk and one or two green balls for the
  crown. The climbing works the same.
- **After the upload** (the lead does it), each kind's model replaces the stand-ins everywhere: one model per kind, turned
  and scaled a little differently at every tree so no two look the same.

## Cost (phones)

- **Parts:** the town bake is unchanged (26,367 of its 27,000). The woods are not in the bake: the server stands them at
  start-up, 3 parts a tree (the bark, the leaves and an invisible trunk that stops you walking through it): 885 parts.
  Each tree streams in and out as a whole.
- **Triangles:** see the table in the next section. The same 13 meshes are used over and over, which the engine draws
  cheaply; far trees are dropped by streaming and simplified by the engine's level of detail.
- **Climbing routes are data, not parts:** 1,693 more routes (3,172 in all, was 1,479). The squirrel's route world builds
  in about 1.4 s instead of 0.8 s (off the start-up path).

## What to look at in Studio (after the upload)

1. Walk to a pine grove (the ridge, or the west edge): do the pines read as pines? Climb one and step out on the rungs.
2. Stand at the foot of a giant (the KING OAK west of the old town): is it tall enough? Climb to its top limb.
3. Look at the leaves from below: they should be green sprays, not grey squares (if grey, tell the lead: it means the
   leaves' see-through setting did not take, and there is a fallback for it).
4. Walk through a town yard with a new walnut or oak: nothing in the way of a door or a path.

## Questions for you (each has a default)

1. **Counts:** 295 new trees. More or fewer? (Default: as is. Each grove's count is one number in `data/woods.json`.)
2. **The alley yard tree** (beside the bowling alley's games room) still cannot be climbed up its trunk: it has a
   squirrel baffle, from your earlier answer (Q11) that the way up is the house roof and its branch. Make its trunk
   climbable too? (Default: keep the baffle; its branch is climbable from the roof.)
3. **The far scenery** (the hedgerows and tree lines beyond the edge of the map, painted backdrop) cannot be reached,
   so it is not climbable. (Default: leave it as backdrop.)
4. **The town's squirrels** (computer-run) climb the new trees but cross roads only from the town's original trees, so
   road crossings stay as careful as you asked in D21. (Default: as is.)
