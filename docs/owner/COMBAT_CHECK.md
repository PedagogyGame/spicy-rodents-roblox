# The fight and the bite's aftermath: what to look at (15 minutes)

Your words (playtest, 18 November): "I really want to make sure that there is an ambulance sequence after the person is bitten by the squirrel, and that all those mechanics work, like the people that are extra aggressive and extra successful in landing blows against you, and extra resistant of being bitten. Still possible, but harder." Then, after playing again: "none on the scene attacked me initially, i would like more of that". And your decisions of 19 November on the police range and the vigilante's tell (below).

Everything below was tested without a screen: the real town, the real traffic, the real ambulance sequence and the real squirrel controls, driven by scripts. A test cannot tell me how it looks and feels, so this is the list of things only you can judge.

## What changed for the player
- **No more biting by bumping into people.** The rodent bites only with a pounce: **click**, a short wind-up (about a tenth of a second, which everyone sees as a crouch), the lunge, and the bite lands if the rodent reaches the person during the lunge and the moment is right.
- **The moment matters.** A bite lands on someone who has not seen you, someone flinching, someone who has just swung or kicked and missed, or someone running away (harder: most shake it off). It does not land on a raised arm, and never on a raised leg or a kick.
- **F is the feint** (for the Spicy Rodent; F is still the kick for a person). It looks exactly like a pounce's wind-up but no lunge follows. It can make a person flinch or swing early, which opens them up. If they see through it, they hit you. Three feints empty the meter; it refills in about 12 seconds.
- **Zig-zagging** (A and D while running at someone) makes their blows miss more often, but it is slower.
- **People now fight back on their own.** Before, only players could kick. Now a person the rodent comes at may flinch, swing, kick, back away or run, depending on who they are.
- **The scene fights back.** When the rodent bites someone, the people who see it (within about 35 studs, not behind a wall or a building) turn on it at once: vigilantes and most wary people square up and come at it, kicking the moment it is in reach; most calm people back off shouting, some run, and some lash out (more so in the bite's alert). The same happens when the rodent pounces into a group of three or more, or a bite is batted away by one of a group. Running at once still gets the rodent away (and so do climbing, a hollow tree and the sewer).
- **A quick second pounce counts.** If you miss, you can pounce again as soon as the squirrel can (under a second later), and that pounce can bite. If a click ever comes too soon for the server (a bunched-up connection), you are told "Too soon".

## Three kinds of people
Every townsperson is one of three, fixed for that person (the same in every server):

| | How common | What they do |
|---|---|---|
| **Calm** | about 64 % | mostly run; slow to react; rarely hit back |
| **Wary** | about 28 % | stand their ground more, swing and kick more |
| **Tough (the vigilantes)** | 8 %, as the brief says | never run; walk straight at the rodent the moment they see it; notice it sooner; strike sooner, more often and more surely; always have a guard up, so a bite lands only in the moment after they strike (longest after a kick at thin air); read half of all feints |

Officers fight like vigilantes, with a baton.

**The vigilante's tell (your decision, 19 November: "Keep them hidden until provoked, with the exception that a few become visible once you reach a 40% bitten rate"):** a vigilante looks like anyone else (a raised forearm) until it is provoked: it strikes at the rodent, the rodent pounces or feints at it, or it turns on the rodent after a bite. From then on it squares up with both fists raised. Once 40 % of the town's people have a bite on them, the three vigilantes nearest the rodent show their fists whatever they are doing; when cures bring it under 40 % again, they are hidden again. Other people show a raised forearm (guard), a drawn-back leg (a kick coming) or both arms over the face (a flinch).

## After a bite
- The area round the bite (about 100 studs) is on **high alert for 90 seconds**:
  - everybody there strikes harder (the hidden boost: a kick does 69 instead of 55, still never one-kick-kills);
  - everybody is twice as ready to swing and kick;
  - a second bite there is **close to impossible** (one twentieth of the usual chance).
- **The police (your decision, 19 November: "Do not limit their pursuit radius; instead, require a distance of two average blocks for them to lose track of you")**: the two nearest free officers, wherever they are, **chase** the rodent. An officer loses track of it only when it is more than two blocks (880 studs, the town's road spacing) from that officer, or when it goes down a drain or into a hollow tree. There is no limit round the bite and no time limit (an officer sent from further away follows the radio until it gets within two blocks, and gives up with the alert if it never does). The sewer stakeout is as before.
- **The ambulance sequence plays out as before.** The play-through spec checks the shout, the collapse, the crowd and its lines, the ambulance driving there on the roads, the crew loading the patient, the hospital bed and the cure, which happens only at the hospital. It also checks the delayed symptoms, a player's own townsperson being bitten, two bites seconds apart, and a bite 2,151 studs from the hospital.

## The numbers (the duel simulation: 400 duels each, the person already aware of the rodent 30 studs away)

The simulation plays the duel as the server does (ten times a second), with the squirrel's pounce going where its body faces, and with a real connection: the rodent's player sees a person a round trip late. Phones on mobile data are typically 100 to 150 ms; the targets hold there.

| Rodent | against | 0 ms | 100 ms | 150 ms |
|---|---|---|---|---|
| skilled (timing, zig-zag, feints, reading the tell) | **a vigilante** | 41 % | **38 %** | **32 %** |
| straight sprint and pounce, no tricks | **a vigilante** | 8 % | 10 % | 12 % |
| skilled | a wary person | 80 % | 75 % | 64 % |
| skilled | a calm person | 86 % | 87 % | 75 % |
| straight sprint | a calm person | 88 % | 86 % | 88 % |
| skilled, right after a bite nearby | calm / wary / vigilante | | 8 % / 4 % / 3 % | |
| **stalked from behind** (creeps up, pounces from 9 studs) | calm / wary | 89 / 82 % | 86 / 76 % | 86 / 72 % |
| **dropped from above** (creeps along a wire or bough, drops behind them, pounces) | calm / wary | 89 / 81 % | 81 / 78 % | 82 / 72 % |

**Stalking (added 19 November, after the overhead watch):** people now notice the rodent the way the town sees it: in front of them, or heard when it moves faster than a creep (about 21 studs), or felt when it brushes them (4 studs). A rodent creeping or keeping still behind someone is no longer noticed just for being within 17 studs. Still possible, but harder: someone may hear the hiss of the wind-up and turn at the last moment (a calm person 35 %, a wary one 45 %, a vigilante 55 %: `duel.tellHeard`), and someone who finds the rodent sneaking up close, or shakes off a bite they never saw coming, cries out, turns on it and stays on edge for the rest of the fight (swings and hits as near a fresh bite, arm always up). So in those two rows **about half the fights end in a bite on someone who never saw it coming** (unaware: 53 to 56 % of calm people, 42 to 45 % of wary ones), and the stalk wins about as often as an open fight (calm 81 to 86 %, wary 72 to 78 % on a phone's link) but faster and with fewer blows taken. A rodent that runs straight in is noticed every time (0 % unaware). The first five rows are unchanged.

**After the overhead watch's review (19 November):** the "creep" is the pace the rodent keeps up by its own checked movement (a phone's hiccup no longer makes a creep heard, and tapping W is heard: a stalk by tapping W bites someone unaware 0 % of the time, a real creep about 60 %); the alarm ends when the person lets the rodent go; and nobody squares up to, swings at or walks under a rodent out of reach up a wire or a wall (they let it go after 4 seconds, or at once once it is more than 10 studs over them, and take it up again when it comes down).

Against a vigilante, a skilled rodent takes almost two blows per fight on average (two blows knock it out). A runner no longer reaches "a door": a person runs about six seconds, as the town's people do, and stays on guard if the rodent is still on them.

After a street bite (16 bites on the real town): typically two people are on the scene and one of them comes at the rodent (from none to two); every vigilante and wary person on the scene attacked, the calm ones backed off. A rodent that ran straight away was never hit on the way; one that stayed was kicked.

## What to try (Studio, Play, or two test windows)
1. **Spicy Rodent.** Walk into a townsperson. Nothing happens (no more bites by contact).
2. **Click** next to a townsperson who has not seen you. You crouch for a moment, lunge and bite: the shout, then the collapse or the walk-off with symptoms later, and the ambulance.
3. A **vigilante** looks like anyone until you provoke it: someone who walks straight at you is a good guess. Once it strikes (or you pounce or feint at it) it squares up with both fists raised. Pounce straight at them and you are almost always kicked, two kicks and you are out. Now try this instead: stay just out of reach, **zig-zag**, wait for the kick, step back out of it, and pounce the moment it misses. Or **F** to feint and pounce when they swing at nothing.
4. Bite someone on a busy street. The people round you turn on you at once (fists up, coming at you; others backing off and shouting). Run, and you get away. Try to bite someone else nearby straight away: you are batted away again and again ("Everyone here is on alert after that bite: get clear first"). The two nearest police officers come for you; get more than two blocks from them, or down a drain, to lose them.
5. **Two windows:** one player as a townsperson, the other as the rodent. The townsperson's **F** kick at the rodent, timed into the lunge, stops the bite (a raised leg). A kick at thin air does not, and the bite lands.
6. Watch a person's stance change as the rodent comes close: a forearm up, a leg drawn back before a kick, arms over the face in a flinch, fists up once a vigilante (or anyone who turned on you) means it. Bite four in ten of the town and three vigilantes near you show their fists.

## Sounds
The duel's six sounds have their names and places (a hiss at the wind-up, a whoosh at a strike, a soft thump and squeak when a blow lands, a slap and yelp when a bite is batted away, a "Hey!" when someone squares up, a short shout when someone backs off). They are silent until we pick them from Roblox's licensed library (`docs/AUDIO_BUDGET.md`).

## Questions for you (each has a default already built in)
1. **Is the vigilante hard enough, or too hard?** Default: on a phone's connection a skilled rodent wins about a third of the time and an unskilled one about a tenth. The numbers are all in `Tunables duel.*`.
2. **Should calm people be harder?** Default: a skilled rodent wins about eight times in ten. The main dials are the bite into someone's reaction (`duel.biteOpen`) and how often a running person shakes it off (`duel.biteRunner`).
3. **Is the scene's response strong enough?** Default: wary people and vigilantes on the scene always come at you; calm ones mostly back off (`duel.rally`, `duel.sceneRadius`).
4. **Feint on F:** the rodent's F was unused (it showed "only people can kick"). Default: F feints, and on a gamepad X (the person's kick button) feints for the rodent too.
