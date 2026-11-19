# Bikes, novelty rides and the old greybox props: what to look at (10 minutes)

You said after the 19 November playtest: "i saw bikes and things that were basic colors, like earlier builds". I looked for everything in town that was still drawn the early way, using offline renders. Then I redrew the worst of it in the same style as the new cars. Nothing has been uploaded: all of it is built from plain Roblox parts.

The pictures are in `docs/renders/bikes/`:
- `before_lineup.jpg` and `before_street.jpg` show how things looked;
- `after_riders.jpg`, `after_lineup.jpg` and `after_street.jpg` show how they look now;
- `after_seated.jpg` shows where a player sits on the bike, the golf cart and the jet ski. The figure is a stand-in: a blocky Roblox body (R15) in its sit pose.

You can make them again with `tools/review/rides.sh`.

## What was still basic-looking, and what changed

| What | Where | Before | Now |
|---|---|---|---|
| **The six street riders**: Marcel the Mime and the five kids | riding the lanes all over town | 6 same-coloured blocks each (a box body, a box head, two flat discs) | The cast on proper rides. Marcel juggles on a tall unicycle in his beret, stripes and red scarf. Ellie, Theo, Jules, Avery and Riley ride kids' bicycles in their own frame, helmet and shirt colours (two have baskets). Each rider has a round head with eyes, hair, round hands and bent legs on the pedals, coloured like the townspeople. 38 to 41 parts each. |
| **Your vehicles**: 2 bikes, 2 golf carts, 2 patrol cars, the pickup, the SUV, the jet ski | the town centre, the police station, the cross street, the river | plain coloured boxes on black discs | The patrol cars and carts now look like the traffic ones. The pickup, SUV and jet ski are new, in the same style. The bike is a proper bicycle. 11 to 40 parts each. |
| **The traffic's two motorcycles** | the boulevard | ridden by nobody | Morgan and Alex ride them, in open helmets and their own jackets. Before, two scooter riders dressed as Morgan and Alex also rode the lanes, so each of them was in town twice. Now there is one of each. |
| **Kids' bikes (3), wheelbarrows (2), hose reels (2)** | yards | a blue, a red and a green box | a kid's bike on its stand with a basket; a red wheelbarrow with its wheel and handles; a hose reel |
| **The ride-on mower** | behind house 3 in the old town | a yellow box | a yellow ride-on mower: bonnet, seat, steering wheel, big back wheels |
| **The park shed** | north gardens | a box with no roof | the same walls with a slate roof, a door, a window and a fascia board |

## Shirts

Every rider wears the shirt or jacket the cast gives them. Ellie's orange shirt, Riley's khaki shirt and Morgan's brown-grey jacket are close to skin colours. On those three the shoulders, just under the chin, are a darker shade of the same colour, so the face does not run into the body. You can see it in `after_riders.jpg` (riders 2, 6 and 7).

## Where you sit when you drive

The game sits you on a hidden seat in each vehicle. That seat used to be where the old box vehicles had it, so on the new bike, cart and jet ski you would have sat beside or below the seat that is drawn. Now:

- **Bike:** you sit on the saddle (2.05 studs up). Your feet are near the pedals.
- **Golf cart:** you sit on the bench, behind the steering wheel, with your back to the seat back. Your feet are on the floor.
- **Jet ski:** you sit on the seat, near the handlebars. Your feet sink about 0.3 studs below the deck, into the hull.
- **Patrol car, pickup and SUV:** you sit on the left, because we drive on the right. The game also lets you out on the left. The seat is low enough that your head is under the roof. Before, a seated player's head came up through the roof: by about 0.9 studs in the car, 0.4 in the pickup and 0.3 in the SUV.
- **First-person view:** in first person you now see from your own head. Before, in the car, cart, pickup, SUV and jet ski, the view came from the empty seat on the other side.

Nobody has checked these in the game yet. They are worked out from a standard Roblox body's sit pose.

### A size call for you, and the cart fixed

- **The bike is a small adult bike.** It is drawn at 0.88 of a full bicycle so that it fits its collision box, which is 1.25 wide, 3 high and 4.5 long:

  | | Now (0.88) | Full size |
  |---|---|---|
  | Wheels | 1.62 across | 1.84 across |
  | Saddle | 2.05 up | 2.33 up |
  | Handlebars | 2.13 up, 1.14 wide | 2.48 up, 1.3 wide |
  | Wheelbase | 2.73 | 3.1 |

  A seated player is about 5.6 studs tall on it, so it looks small under an adult. A full-size bike needs a box of about 1.3 wide, 3 high and 5.0 long. That changes what the bike collides with, and the box its steering and speed work in. **Default if you say nothing:** the box and the 0.88 bike stay as they are.

- **The golf cart's roof: fixed: roof raised, box 6.25 (about 6.0).** Before, a seated player's head (5.72 studs up: the bench top is 2.12) poked about 1.2 studs through the roof, whose underside was at 4.5 in a 4.75-tall box. Now:
  - your cart's collision box is 6.25 tall (still 3.75 wide and 6.5 long), and its posts, windshield and roof go up with it;
  - the underside of the roof is at 6.0, so a seated head clears it by about 0.3 studs (see `after_seated.jpg`). A box of exactly 6.0 would have left only 0.03;
  - the tub, the bench and the golf bags have not moved, so you sit where you did;
  - the traffic's carts are not changed: they keep their 4.75 box and their lower roof;
  - the two parked carts still stand clear: nothing is built over their spots.

## Why the riders are not the new rounded townspeople models

The rounded townspeople art is put onto a full Roblox body (an R15) when the game starts. The riders have no such body: each one is built as a single piece with its ride. I chose to draw them in the same look rather than give them a full body, for three reasons:
- the walking animations have no riding pose, so a full body would sit on the bike stiffly;
- a full body on every rider would cost a character and animation work on every phone;
- the parts drawing can be tested and rendered here.

Nothing else about the riders changed. They are still never patients. The only thing that can be touched or hit on a rider is the same small invisible box as before, at the same height.

**A player can no longer be given a rider.** Before, choosing Townsperson next to a rider could hand you that rider, whose body then fell through the ground. Riders are run by the game only (decision 21), so you always get a townsperson.

## Cost (phones)

- **Riders:** 38 to 41 parts each. That is about 240 for the six on the lanes; before it was 7 each.
  - Dropping the two scooter riders saved about 70 parts and two AI walkers.
  - Only the body, the head and the tyres cast shadows, 3 or 4 parts per rider.
  - Each rider still moves as one welded piece.
- **Traffic motorcycles:** 21 more parts on each of the two. Their riders cast shadows from 2 parts each.
- **Your vehicles:** 15 to 42 parts each, against 6 to 11 before. Only the big parts cast shadows: the body, the cabin and roof, the cart's canopy, the pickup's bed, the jet ski's hull and seat, and the tyres. That is 2 to 8 parts per vehicle, 53 across the parked fleet. The first version had 240.
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
5. Get on the bike, a cart and the jet ski, and get into a patrol car:
   - Do you sit on the seat?
   - Does the first-person view come from your own head?
   - In the car and the golf cart, does your head stay under the roof?

## Still basic-looking: left for you to decide
- **The trolley stops (3)** on the east boulevard are solid 24 x 7.5-stud blocks. Making them look like shelters means making them open, which changes their collisions. **Default if you say nothing:** they stay as they are.
- **The drone** at the police station is still a dark box with four flat plates. A rounder drone already exists among the stand-in models and could replace it.
- **The hollow stump** in the north park is a plain box. The hollow-tree work owns it.
- **The galleria coin fountain** is a 40-stud flat slab. It needs a design, and the name should lose "coin" (no gambling imagery).
- **Rain barrels, compost bins, garden gnomes and lawn flamingos** are simple shapes already: cylinders, or a ball on a stick. They are cheap to improve later.
- **The shrub clusters** are single green balls. They are left for the planting work.
