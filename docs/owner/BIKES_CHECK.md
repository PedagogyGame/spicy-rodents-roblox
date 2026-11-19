# Bikes, novelty rides and the old greybox props: what to look at (10 minutes)

You said after the 19 November playtest: "i saw bikes and things that were basic colors, like earlier builds". I looked for everything in town that was still drawn the early way, using offline renders. Then I redrew the worst of it in the same style as the new cars. Nothing has been uploaded: all of it is built from plain Roblox parts.

The pictures are in `docs/renders/bikes/`:
- `before_lineup.jpg` and `before_street.jpg` show how things looked;
- `after_riders.jpg`, `after_lineup.jpg` and `after_street.jpg` show how they look now.

You can make them again with `tools/review/rides.sh`.

## What was still basic-looking, and what changed

| What | Where | Before | Now |
|---|---|---|---|
| **The eight street riders**: Marcel the Mime, the five kids, the two motorcyclists | riding the lanes all over town | 6 same-coloured blocks each (a box body, a box head, two flat discs) | The cast on proper rides. Marcel juggles on a tall unicycle in his beret, stripes and red scarf. Ellie, Theo, Jules, Avery and Riley ride kids' bicycles in their own frame and helmet colours (two have baskets). Morgan and Alex ride motor scooters in open helmets. Each rider has a round head with eyes, hair, round hands and bent legs on the pedals, coloured like the townspeople. 34 to 41 parts each. |
| **Your vehicles**: 2 bikes, 2 golf carts, 2 patrol cars, the pickup, the SUV, the jet ski | the town centre, the police station, the cross street, the river | plain coloured boxes on black discs | The patrol cars and carts now look like the traffic ones. The pickup, SUV and jet ski are new, in the same style. The bike is a proper bicycle. 11 to 40 parts each. |
| **The traffic's two motorcycles** | the boulevard | ridden by nobody | Morgan and Alex ride them. |
| **Kids' bikes (3), wheelbarrows (2), hose reels (2)** | yards | a blue, a red and a green box | a kid's bike on its stand with a basket; a red wheelbarrow with its wheel and handles; a hose reel |
| **The ride-on mower** | behind house 3 in the old town | a yellow box | a yellow ride-on mower: bonnet, seat, steering wheel, big back wheels |
| **The park shed** | north gardens | a box with no roof | the same walls with a slate roof, a door, a window and a fascia board |

## Why the riders are not the new rounded townspeople models

The rounded townspeople art is put onto a full Roblox body (an R15) when the game starts. The riders have no such body: each one is built as a single piece with its ride. I chose to draw them in the same look rather than give them a full body, for three reasons:
- the walking animations have no riding pose, so a full body would sit on the bike stiffly;
- a full body on every rider would cost a character and animation work on every phone;
- the parts drawing can be tested and rendered here.

Nothing else about the riders changed. They are still never patients. The only thing that can be touched or hit on a rider is the same small invisible box as before, at the same height.

## Cost (phones)

- **Riders:** 34 to 41 parts each, about 310 for all eight. Before it was 7 each. Only the body, the head and the tyres cast shadows. Each rider still moves as one welded piece.
- **Traffic motorcycles:** 21 more parts on each of the two.
- **Your vehicles:** 15 to 42 parts each, against 6 to 11 before.
- **Town bake:** 105 more parts. It is now 26,834, under the 27,000 budget.

## Collisions

**Nothing changed.**
- Each vehicle's invisible collision box is exactly the size it was.
- A rider's only solid part is the old small box.
- The yard props never blocked anyone, and still don't. Their old boxes are still there, but invisible, and a squirrel can no longer stand on top of them.
- The shed's walls are the same solid box. Its new slate roof lies flush on top and is not solid itself, so whoever climbs onto the shed stands on the walls' top, sunk 0.3 studs into the slates.

## For you to look at in Studio
1. Watch a kid ride past and the mime come down the main street. Do they read well at street distance?
2. Look at the parked bike, the carts, the patrol car and the pickup in the town centre and on the cross street.
3. Look at the jet ski on the river. Its bottom sits at the water line, as the old box did.
4. Watch a traffic motorcycle with its rider on the boulevard.

## Still basic-looking: left for you to decide
- **The trolley stops (3)** on the east boulevard are solid 24 x 7.5-stud blocks. Making them look like shelters means making them open, which changes their collisions. **Default if you say nothing:** they stay as they are.
- **The drone** at the police station is still a dark box with four flat plates. A rounder drone already exists among the stand-in models and could replace it.
- **The hollow stump** in the north park is a plain box. The hollow-tree work owns it.
- **The galleria coin fountain** is a 40-stud flat slab. It needs a design, and the name should lose "coin" (no gambling imagery).
- **Rain barrels, compost bins, garden gnomes and lawn flamingos** are simple shapes already: cylinders, or a ball on a stick. They are cheap to improve later.
- **The shrub clusters** are single green balls. They are left for the planting work.
