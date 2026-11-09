<!-- Captured from the owner's live Claude Doc "Spicy Rodents — Roblox Rebuild Brief" (artifact 4Td73YC8xsjj1zPzH3EwjH, doc rev 28) on 2026-11-09. This supersedes Roblox_Rebuild_Brief.pdf; section 15 answers the build-plan decisions. -->

# Spicy Rodents — Roblox Rebuild Brief

This is the complete brief for the coding and Blender session. Build the whole game in one pass. Do not ship a walkable-town-first milestone; every role below must be test-playable from the first runnable build.

## 1. Source of truth

- Canonical spec: `Spicy_Rodents_v5_4_Living_Town.html`, SHA-256 `fc48b387e51ce3a454898d58d1cb3dda891b22ffad7110cdcd0ade6c777a6227`. It is live at pedagogygame.com and in the GitHub Pages repo.
- v5.4 is a clean superset of v5.2: 46 functions added, none removed. It contains the Bellwether Galleria mall (v5.3) and apple trees, bird nests, town birds, silent overflights, heavy vehicles, and fatal traffic (v5.4).
- The HTML is the reference for layout, climbing routes, traffic lanes, districts, and mechanics. The Roblox build is a from-scratch rewrite in Luau that reproduces and extends it; it does not transpile it.
- Lost in earlier HTML lineage and to be restored here: nut caches, deer, foxes, butterflies, garden insects.

## 2. Toolchain and repository

- Rojo project under git, one repo, Roblox Studio syncing from the filesystem. No zip handoffs.
- Blender for all character and prop assets, exported as FBX with animations, imported via the Studio animation importer.
- Code organized by concern, one module per system, under `ReplicatedStorage/Shared`, `ServerScriptService/Server`, `StarterPlayerScripts/Client`:
  - `WorldGen` — builds the town from data, never from hand-placed parts
  - `Routes` — climbing route registry (trees, poles, wires, rooftops)
  - `Traffic` — lanes, vehicles, yielding, swept collision
  - `Actors` — the single actor model (section 4)
  - `Roles` — hierarchy, queue, promotion ladder
  - `Infection` — bite, spread, cure, win condition
  - `Hospital`, `Police`, `Drone` — job systems
  - `Seasons` — in-game calendar, winter
  - `Foraging` — gardens, feeders, trash, hollows, nut meter
  - `Wildlife` — fox, deer, birds, insects

- The town is a data file: a list of lots, each with a type, footprint, facing, and lot-specific parameters. Adding a barber shop later must be a data entry, not surgery.
- `StreamingEnabled` on. The map is several thousand studs end to end at the chosen scale.
- Scale: HTML units to studs at roughly 2.5. Squirrel stands about 1.2 studs at the shoulder; humans standard R15 height.

## 3. The world

### Districts (from v5.4, all retained)

- Old town core with streets, sidewalks, houses, utility poles and wires, trees
- Hospital (west) — expanded, see section 8
- Police station — expanded, see section 9
- Riverside old town across the river (east): stone arch bridge, cobbled quays, rooftops
- Bellwether Galleria mall (far east): six shops, upper gallery, coin fountain, interior lighting and camera constraints
- Sewer and duct interiors, house interiors

### Neighborhood expansion (new)

The town should read as a real society, not a backdrop. Add, as data-driven lots:

- Restaurants: roughly double the current count. Mix of diner, pizza, taco, Chinese, café, bakery, ice cream, bar and grill, each with outdoor seating or a back-alley dumpster (foraging value).
- Barber shop, music store, hardware store, laundromat, bookshop, pet store, gas station, corner grocery, school with playground, church, park with gazebo, community garden, a small marina on the ocean side.
- Residential variety: at least eight distinct house models (bungalow, two-storey, Victorian, ranch, split-level, cottage, apartment block, large older house), and every individual house gets its own flair through paint, trim, porch, roof, and yard variants so no two read the same. Backyards with gardens, bird feeders, sheds, fences, dog houses.
- Each lot type defines what squirrels can forage there and how risky it is.

### Backdrop

The drone role sees the whole town from above, so the backdrop must hold up at altitude, not just from squirrel height.

- One side: mountains falling to rolling hills and plains, with tree line, a distant road, and fog layering.
- Other side: ocean with a beach, pier, marina, and a horizon that reads correctly from 300 studs up.
- Sky with a full day cycle: sunrise and sunset as their own graphic moments, clouds, the silent overflights from v5.4, and a genuinely beautiful night sky with stars, and a moon that runs through real phases tied to the in-game calendar (new, waxing, full, waning over a roughly 29.5-day lunar month), never a permanent full moon. A radio or cell tower in the distance with blinking red lights, placed to silhouette against the sunset.

### Hollow trees

- 12 hollow trees across the town, each a claimable squirrel territory with a nut meter, plus a fallen hollow log as an extra hiding spot.
- Premium tree 1: a spiral ramp running up inside the trunk, chambers at several heights. Premium tree 2: a straight climb-up shaft with a knothole exit and a hideout. Both sit next to the best gardens and bird feeders.
- One escape tree with three apertures and exits.
- The other nine have a single hollow chamber reachable from a knothole.
- Claiming is proximity, not a ritual: no scent-marking animation. A squirrel owns a tree while its meter is at 70% or above and it has visited the tree at least once every three in-game days while at 70%; miss that and the claim lapses.
- Nuts on the map are finite per season. A squirrel carries at most 9 nuts at a time, so every trip back to the hollow is exposure.

## 4. The actor model (hard architectural rule)

There is no distinction in code between a player character and an NPC. There is one kind of actor per species (human, squirrel, fox, deer), and the only question is who is driving it: the AI brain or a player's controller.

- Every human and squirrel in the town is AI-driven by default.
- A player joining takes control of an existing actor mid-stride. A player leaving hands control back and the AI carries on.
- Promotion in the queue is the same handoff: release one body, possess another.
- This single mechanism implements the queue, NPC backfill, role switching, and session reset.
- The town always has more human bodies than the 35 player slots, because the hospital, police station, shops, and streets need to be staffed and walked regardless of player count.

## 5. Server population

- Server cap is 49 player slots, hard: 35 humans (hospital and police slots are inside the 35), 7 regular squirrels, 1 spicy rodent, 5 deer, 1 fox. When it is full it is full; late joiners wait for the next server. No overflow roles, no spectator birds.
- Any slot not held by a player is AI. Squirrel bodies may float between 10 and 14; 7 is the player-slot count, not the body count.
- Baseline NPC staffing that always exists regardless of players: at least 6 NPC police and at least 10 NPC hospital staff, plus ambulance crews on top (crews do not count toward the 10). Player staff make things faster and earn bonuses; the town functions without them.
- Deer and fox are voluntary roles chosen instead of a promotion (section 11). The fox is the Easter egg; deer are openly offered.
- Limited server count so that a real queue exists for the spicy rodent slot.

## 6. Roles and the promotion ladder

State this ladder in one place in code (`Roles`), and nowhere else.

1. Human, lowest level. Walks the town. Earns credits by working. Can be bitten.
2. Hospital staff (5 player slots) and Police (5 player slots, expandable to 8). Hospital ranks slightly above police; privileges are nearly equal.
3. Regular squirrel (7 player slots). Forages, stores nuts, claims a hollow.
4. Spicy rodent (1 slot). The zombie squirrel. The role everyone wants.

Movement between rungs:

- Base rank among humans = time logged in and playing on this server, modified by job credits.
- Squirrel rank = 90% nut count, 10% momentary stink-gland percentage. The highest-ranked squirrel becomes the next spicy rodent when the slot opens.
- When the spicy rodent dies (run over, killed by police or hospital staff, etc.), that player restarts as a lowest-level human.
- A human who kills the spicy rodent is promoted to the lowest-rank uninfected squirrel if a squirrel body is free; otherwise to the police station, or to the hospital if the rodent had infected more than 30% of the town.
- Hospital staff who kill the spicy rodent when it enters the hospital instantly become a lowest-rank uninfected squirrel.
- A regular squirrel cannot kill the spicy rodent; it can only be infected by it.
- A regular squirrel that gets infected loses heavily (points and nuts) and drops in the queue.
- Squirrels that die in winter restart as humans.
- Deer and fox are side exits a player may choose instead of a promotion; leaving them returns the player to human at their previous human rank.

## 7. Squirrel play

### Movement

Port the v5.4 route registry: curves, sampled points, kind (branch, pole, wire, lookout, roof), speed, surface radius, and the per-route `visualOffset`. Climbing is rail-based as in the HTML, with free running on the ground and leaps between rails.

### Animation (Blender)

Seven individually authored clips on a single rig:

1. Run
2. Climb
3. Wire traversal
4. Leap
5. Pounce
6. Bite dance
7. Sneak (stalk)

The squirrel must have weight and presence: fur that catches light, muscle under the skin, a tail that lags the body. This is a modelling and rigging requirement, not a lighting one. Treat the three-stacked-spheres squirrel from the HTML as a placeholder to be replaced entirely.

### Foraging and territory

- Sources: gardens, bird feeders (risky — birds and homeowners), trash cans and restaurant dumpsters, apple trees, the mall plaza.
- Nuts stored in a claimed hollow raise its meter. Above 70%, the squirrel owns the tree and other squirrels cannot take its nuts.
- Premium gardens and feeders near the two big hollow trees can be raided about once per in-game week.

### Stink gland

A slow-filling meter that counts for 10% of rank. It can only be fired at 95% or above, which is hard to reach, and firing it drops the meter by 30 points. The burst repels foxes and humans briefly.

## 8. Spicy rodent play

- Stalk (hold), pounce, bite as in v5.4. Unaware people are easier.
- Biting humans infects them; biting regular squirrels raises town-wide infection rate.
- Fatal traffic from v5.4 ports as a relative swept collision test on the server, not a Touched event. Being run over ends the spicy rodent's run.
- Hidden win path: infecting hospital staff slows cures. No infection meter is ever shown to anyone. When combined infection reaches about half the town plus half the hospital staff and patients, the outbreak triggers and the rodent wins.
- The outbreak is a cinematic, not an end card: every player's camera pulls up and out over the town, time accelerates, squirrels sweep house to house faster and faster, the sky goes overcast and dims; at night it simply fades to black. This sequence needs the lamplit town from section 3 to look right.
- When the spicy rodent dies, the board is not wiped. Infection resets to the new rodent alone (about 0.5%). Regular squirrels keep their hoards; humans keep their points and reputation. Infected squirrels drop to lowest-rank human. Infected humans are cured (instantly if recently bitten or en route to hospital).
- Deer become biteable only once every regular squirrel is infected. A bitten deer turns rabid and charges through town, accelerating the collapse. Before that point the rodent ignores deer.
- Bite aftermath: the vicinity goes on high alert. Humans nearby get a hidden strength boost (not shown on any meter), are far more likely to swing, and NPC police within about two blocks will chase up to five blocks. The ambulance sequence plays out. Biting again near a fresh bite should be close to impossible.
- The rodent therefore needs refuges between bites: hollows, the sewer, poles and trees. Treat them as rodent cover, not just squirrel storage.

### Combat dynamics

The fight between rodent and human is a real duel, not a single pounce. Build these as tunable systems:

- Timing: a pounce has a wind-up, a commit point, and a recovery; biting during the human's reaction window lands, biting into a raised arm or a kick does not.
- Approach: zig-zag movement raises the human's miss chance but costs speed; a straight sprint is fast and readable.
- Feint: a pretend lunge that forces the human to flinch or swing early, opening a real window. Feints cost stamina and, if read correctly, hand the human a free hit.
- Humans respond: flinch, swing, kick, back away, or flee, chosen by awareness and nerve. Vigilantes never flee.
- Every option that shows off should carry a trade-off, so psyching out a human is a skill, not a free win.

### Vigilantes

8% of all human actors on the map at any moment have a vigilante streak. On sighting the spicy rodent they move to kick it rather than evade, and they answer the drone's call.

### Health and house defenders

- Rodent health 100. A kick does 55, so two kicks without recovery kill. The three house defenders hit 1.5x (about 82), which kills only if health is already below full. Accepted as-is.
- Health drains 1% per in-game day without a bite. Biting a human restores 10%; biting a regular squirrel restores 20%. Health also regenerates slowly while sneaking or resting in a hollow.
- Power (section 15) fades on real minutes; health drains on in-game days. These are two separate clocks by design. Do not merge them.
- Three houses have a defender who bursts out when the rodent chases someone inside: two older housewives (different demographic appearances) with rolling pins, one man with a broom.
- Squirrel chases carry tunnel vision: regular squirrels match the rodent's speed and agility, so a chase is long and exposed, the camera is locked forward, and a vigilante or patrol car can take you from the blind side. The 20% heal is the reward for that risk.

### House interiors

- 40 houses have full interiors the rodent can burst into. Humans can run inside and hide; whether they escape or get bitten depends on the chase. This must actually run and be tested, not be stubbed.
- These 40 houses are also the homes a human player can claim (35 player slots, so there is slack). Each real day of play earns remodel points; remodels persist for the life of that server instance.

## 9. Hospital

Needs far more elaboration than the HTML. Build it as a real building: reception, triage, two wards, an isolation ward, pharmacy, staff room, ambulance bay, roof access (a squirrel route).

- Infected humans are delivered or walk in. Staff disinfect them through a short interaction loop at treatment stations.
- Hospital performance = speed of disinfection. Good performance raises staff rank and unlocks station upgrades.
- Staff can kill the spicy rodent if it enters the building (section 6 reward).
- Infected staff cure slower, feeding the hidden win path.

## 10. Police

- Five officer player slots at start. Officers pursue and can kill the spicy rodent.
- Good performance unlocks additional officers one at a time up to eight total; later officers are more aggressive and better coordinated.
- At eight officers, the next upgrade unlocks a drone: one player flies it. Full flight controls, camera feed, a spot-and-mark ability that reveals the spicy rodent to officers for a short window and calls nearby vigilante neighbors to the spot. Make this as good as it can be; it is the role that justifies the backdrop.

## 11. Wildlife and voluntary roles

- Fox: one player slot, Easter egg. Hunts regular squirrels; cannot harm the spicy rodent. Repelled by the stink gland.
- Deer: several player slots. Peaceful, wanders, can be startled by traffic and the drone. Purely for players who want it.
- AI-only: birds and nests (from v5.4), butterflies, garden insects, and restored deer and foxes when no player holds them.

## 12. Seasons

- In-game calendar. A week is the raid cycle for premium gardens. Time scale is one tunable constant (real seconds per in-game day); pick a sensible default and tune it in playtest. Rough targets mentioned: a winter cycle every 50 real minutes or so, with visible day and night.
- Every five in-game weeks, winter arrives and lasts one week: snow, bare trees, dimmer light, reduced foraging.
- At winter's end, squirrels whose hollow meter is below the survival threshold die and restart as humans, opening squirrel slots.

## 13. Credits and upgrades

- Humans earn credits by working: hospital, police, and shop jobs.
- Credits raise rank in the queue toward the squirrel and spicy rodent slots and buy the station upgrades in sections 9 and 10.

## 13a. Human life (addendum)

Humans are 35 of the 43 player slots, so the human life must be a full game, not a waiting room. Everyone has total free range. Hospital and police duty is optional: skipping it never costs rank; doing it raises rank inside that administration. Everyone gains some rank for time served. Police, doctors and nurses get distinct outfits.

### Avatar blend

When a player possesses a human body, the body keeps its own build and clothes (about 70%) and takes the player's face, hair and skin tone (about 30%). Do this with appearance properties scripts can set, not tinting.

### Getting around and goofing off

- Several golf carts and bicycles, trampolines, two climbable tree houses (risky: squirrels reach them).
- Mischief: TP-ing trees, knock-and-run, egging at night, water balloons, joyriding a police cart. Mischief angers NPCs and gives police something to respond to.
- A taunt button that cycles about 20 one-liners ("what's up, loser?", "hey, Dinkleberry").

### Gigs (earn Spicy Dollars)

Lawn mowing (quick), restaurant delivery by bike or cart, sign-spinning, car washing, a morning newspaper bike route (bonus for hitting the porch), serving tables at the steakhouse. One rule for all gigs: an extra-good job earns a tip; a bad job gives a very minor reputation ding. NPC-posted mini-missions appear on a wanted poster or billboard (walk Mrs. Harrison's dog, return a lost pet) and pay coins.

### Reputation

Two-sided. NPCs can like you for being fun and will pal around or follow you; a bigger entourage raises rank. Players give thumbs up or down to anyone, five of each per in-game day; a vote against another player affects their reputation. Weight votes by the voter's own reputation to blunt brigading. Sitting at a cafe raises reputation. Reputation also rises for rescuing someone the rodent is chasing, true sighting reports, and returning lost pets.

### Scoring against squirrels

Big boost for landing a kick on the rodent or any infected squirrel. Killing an infected non-leader squirrel kills it; a healthy squirrel respawns and the top-ranked hospital player (hospital outranks police) is promoted into that slot. The killed player recycles to the bottom of the human queue. Infected squirrels never recover; one still alive when the rodent wins restarts the next match as a regular squirrel. Police recruitment: when police perform well, a promotion offer is messaged to the top-ranked regular human; declined, it passes to the next by seniority.

### Economy

Currency is Spicy Dollars. Robux buys them through developer products (about 1 Robux to 4 Spicy Dollars; Robux amounts must be whole numbers). Minimum wage is 2 spicy pennies per in-game hour; goods are cheap (coffee 12 cents, nachos 5 cents). Money's main use is buying your place in the human queue only, never into police or hospital. Queue rank = money plus reputation, and a player needs at least 10 in-game days of play before being ranked at all.

### Places and attractions (all fully interactive, not set dressing)

- Detailed stores: antique store, pet store, a very specific barber shop; an intricate police station. Corner store: a 1970s-style layout (not literally period), a working checkout counter, and about 22 pick-up-able shelf items, every one functional, all cheap except bird seed and the kite. Prices in spicy cents: water gun 6 (squirts people, they react; Easter egg: the first time a given player's squirt hits the rodent it stuns it 1.3 seconds, once per player), frisbee 5, football 6, bubbles 3, sidewalk chalk 2 (each stick writes about 20 letters on pavement), flashlight 6 (works at night), umbrella 5, peanuts 4, bird seed 40 (baits squirrels and birds), dog treats 4, newspaper 2, disposable camera 6 (takes screenshots), duct tape 4, whoopee cushion 15 (moderate, to limit how many are about), harmonica 5, air horn 5 (startles NPCs and squirrels), soda 4, ice cream bar 5, lawn chair 6 (sit anywhere), radio 8 (plays the stock library), bike horn 3, kite 60 (a full flying sequence in the park and on the beach). No lottery or gambling items.
- Doctor's office: receptionist at the counter; on the waiting-room table two openable picture books (animals; early America), a wire bead maze, and a playable tilt marble labyrinth. Controls are deliberate, do not change: W/S tilt forward and back; up and down arrows tilt right and left, up arrow is right.
- Museum with readable exhibits.
- Bowling alley with fully playable lanes: choose your angle and power, bowl, physics pins, the ball returns up the rack, overhead lights and working scoreboards. The ball-return tunnel is a real squirrel route: a squirrel can run the length of it under the lane and pop out at the rack to get you. That route must be playable and rendered with great care, since it's a signature moment; plus three pinball machines (distinct themes, real flipper physics), two pool tables, a bumper pool table, a working dartboard beside the pool tables (mouse sets the aim point, a timing meter sets power, slight wobble so it is a skill rather than a click; scores 501 and cricket), and in a corner by some ferns a free-play fortune-teller slot machine: pull the lever, reels spin, it dispenses a fortune or a taunt. No money in or out, ever (Roblox forbids simulated gambling). Realistic back of house: steel push-bar exit doors to an alley with big round dark-blue used trash cans and a push broom leaning by the door. No scrimping.
- Racquetball court, playable against NPCs or players, with real ball physics.
- Elaborate steakhouse: outdoor bar, glass walls squirrels can see through but not enter (a human refuge), sand with a beach ball and a working volleyball net, a playable four-foot giant Jenga on a deck table.
- Ocean side: jet ski rental, parasailing.
- A sky lift up a slight hill to a hilltop restaurant (second vantage over the town).
- Paintball arena inside a big abandoned five-storey TV station; runs as its own match, rodent-free. 20 spicy cents buys five in-game days of access, which also unlocks five days in the lounges. Priority is mechanics, not looks: the marker can be generic and even silly-looking, but it must shoot right. Minimum bar: projectile with travel and slight drop, a five-shot magazine that auto-reloads when empty or reloads on a button press, server-side hit detection with lag compensation, paint splats that stay on walls and players, a five-floor layout with stairwells and a central atrium for verticality, team deathmatch 4v4 to 8v8 with NPC bots filling empty slots, a match timer, scoreboard and end card, distinct audio for fire and hits, and sprint and crouch that feel right. If the mechanics are not good it gets cut; Ben will not keep a weak version. Build it in Wave 4 and playtest with Ben before calling it done. Once inside, players can buy upgraded paintball garb at one Spicy Dollar per set, kept permanently: a few Blender-made outfit sets (mask, chest rig, pads), each in four colourways, green, blue, red and yellow, and carrying its own insignia and patches, so sets read as distinct squads worn as cosmetics with no gameplay advantage. Players can take the garb off or keep wearing it around town for the rest of the session if that works with the possession system; if not, it comes off automatically when they leave the arena. Either way it stays in their wardrobe. Check that custom clothing meshes can be applied to a possessed human body in Roblox; if full outfits are not feasible, do it with accessories and a texture swap.
- Lounge one: squirrel-proof, very tough NPC guards who annihilate any squirrel that tries. Elaborate Blender interior, leather and woodwork, fancy counters, a classy 1940s-style bartender serving hot cocoa, coffee, green tea and snow cones. Stock licensed jazz from Roblox's music library, 1920s feel.
- Lounge two: the opposite direction, futuristic and surreal, sci-fi and space, lava lamps, dense plants, a seamless procedurally generated ambient loop.
- New small shopping mall with the showpiece: an indoor skydiving wind tunnel. You float in a glass cylinder while silly instructors throw giant balls that bounce off you; other players can pay Spicy Dollars to add 10 balls.

## 14. Camera and first person

- Rodent, regular squirrel, deer and fox stay in standard third person.
- Humans can toggle first person at any time. Interiors, vehicles and the gondola must hold up at eye level.
- Boarding the sky-lift gondola or getting into any vehicle switches to first person automatically; the toggle remains. Vehicles need modelled interiors and dashboards.
- Paintball and both lounge interiors are locked to first person.

## 15. Decisions from the build-plan review (8 Nov)

These answer the coding session's 36 decisions. Where a default is not named here, accept it (drive on the right, north is +Z, squirrel 1.2 studs at the shoulder, type checking in CI).

- 10, day length: accept 72 real seconds per in-game day with sunrise and sunset held longer, winter about every 50 minutes. One tunable constant.
- 11, hidden win: accept the half-town trigger, but the ending is the outbreak cinematic in section 8, not an end card.
- 12, rodent health: accept 100 / 55 / 1.5x, plus the drain and bite-heal rules in section 8.
- 13, map sightings: accept. Police and drone see everything; hospital staff see bite locations only; markers fade after about a minute.
- 14, driving and traffic: accept, with additions. Everyone obeys traffic law in town, police included. An officer who hits a pedestrian loses the car, sits in a cell, and is demoted to lowest rank on release; the pedestrian wakes up in a hospital bed as an uninfected patient. A player driver who runs over the rodent gets the kill credit and the section 6 promotion.
- 18, town layout: accept the 34 + 6 homes with a south-east school and church block, and the marina, pier and beach. The approval map must also show the steakhouse, the hill with sky lift and hilltop restaurant, the TV station, the bowling alley, the new mall, both lounges, the corner store, doctor's office, museum, racquetball court, and the off-road zone below.
- 19, hollow trees: 12 not 11; see section 3.
- 20, old web-game extras: keep Power exactly as v5.4 implements it (table below), drop Gold, coins become Spicy Dollars, chili rush becomes a rodent-only power-up, sewer and fashion stand stay with outfits as cosmetics, cats and dogs stay.
- 23, art: no money is ever spent on art and no outside artist. Everything is made procedurally in Blender by the coding session and approved by turntable. Rough is fine; what must be covered is contours, textures, colours, shading and shadows, and the basic movement set. Polish goes where people pay or play: extra lighting detail in both lounges and the paintball arena, and every minigame ironed out carefully. Detail is high on the ridge and anything near town; the far distance is painted scenery.
- 24, content rating: accept mild. Rewrite the v5.4 swearing lines to keep the venom and lose the vocabulary; skate the line like a lawyer.
- 28, player slots: server caps at 49 (section 5). No late-joiner overflow.
- Rides versus minigames: parasailing, the sky lift and the wind tunnel are rides: no controls, no score, you get on and it happens. Jet ski is the exception (you steer). Minigames have controls and a result: bowling, pinball, pool, bumper pool, darts, racquetball, paintball, the tilt labyrinth, giant Jenga, volleyball. Only minigames get the ironing-out treatment.
- Layered distant fog goes into Wave 6 with the backdrop.
- Street lighting: lamps on every block with warm pools of light and a few that flicker, porch lights, glowing shop fronts. The drone pilot and the outbreak cinematic both depend on this.
- Off-road zone: beyond a ridge with real trees, a beach that runs out past the public area into a back field with hills. No tickets and no arrests there; police have no jurisdiction, though the drone can see it. The top two ranked humans can drive any pickup or SUV in town (place 6 pickups and 4 SUVs). This is undocumented in-game; players discover it. Otherwise only police drive.
- Open: whether Ben's Roblox account is ID-verified (gates audio uploads at 100 a month versus 10). Ben has Roblox Premium.

### Power, verbatim from v5.4

| Event | Power change |
|---|---|
| Bite a person | +100 |
| Bite a person while world Y is above 4 units | +150 instead |
| Bite a police officer | +130 |
| Bite and convert an uninfected squirrel | +90, once per squirrel |
| Hit by a police baton | -19 |
| Hit by a yard cat | -12 |
| 10 real minutes of active play without a successful bite | lose 15% of current Power, rounded up; repeats every 10 minutes |

A successful bite resets the fade timer. Power never drops below zero. Chilis, coins, climbing and missed pounces do not change it. Stages shown on the HUD: FERAL below 600, RABID 600 to 1,499, SUPER at 1,500 or more. Keep it as the rodent's visible status meter; it is reputation, health is survival.

## 16. Deliverables

- A runnable Roblox place with every role above test-playable: human, hospital staff, police, drone, regular squirrel, spicy rodent, fox, deer.
- Blender source files and exported FBX for the squirrel (rigged, seven clips), human variants, fox, deer, and key props.
- The town data file with every lot, including the full restaurant and shop expansion.
- A short README describing the module layout and how to add a lot type, a route, or a role.
