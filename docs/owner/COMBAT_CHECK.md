# The fight and the bite's aftermath: what to look at (15 minutes)

Your words (playtest, 18 November): "I really want to make sure that there is an ambulance sequence after the person is bitten by the squirrel, and that all those mechanics work, like the people that are extra aggressive and extra successful in landing blows against you, and extra resistant of being bitten. Still possible, but harder."

Everything below was tested without a screen: the real town, the real traffic, the real ambulance sequence and the real squirrel controls, driven by scripts. A test cannot tell me how it looks and feels, so this is the list of things only you can judge.

## What changed for the player
- **No more biting by bumping into people.** The rodent bites only with a pounce: **click**, a short wind-up (about a tenth of a second, which everyone sees as a crouch), the lunge, and the bite lands if the rodent reaches the person during the lunge and the moment is right.
- **The moment matters.** A bite lands on someone who has not seen you, someone flinching, someone who has just swung or kicked and missed, or someone running away (harder: most shake it off). It does not land on a raised arm, and never on a raised leg or a kick.
- **F is the feint** (for the Spicy Rodent; F is still the kick for a person). It looks exactly like a pounce's wind-up but no lunge follows. It can make a person flinch or swing early, which opens them up. If they see through it, they hit you. Three feints empty the meter; it refills in about 12 seconds.
- **Zig-zagging** (A and D while running at someone) makes their blows miss more often, but it is slower.
- **People now fight back on their own.** Before, only players could kick. Now a person the rodent comes at may flinch, swing, kick, back away or run, depending on who they are.

## Three kinds of people
Every townsperson is one of three, fixed for that person (the same in every server):

| | How common | What they do |
|---|---|---|
| **Calm** | about 64 % | mostly run; slow to react; rarely hit back |
| **Wary** | about 28 % | stand their ground more, swing and kick more |
| **Tough (the vigilantes)** | 8 %, as the brief says | never run; walk straight at the rodent the moment they see it; notice it sooner; strike sooner, more often and more surely; always have a guard up, so a bite lands only in the short moment after they strike; read half of all feints |

Officers fight like vigilantes, with a baton.

**The vigilante's tell:** when a vigilante faces the rodent they square up with both fists raised in front of them. Nobody else stands like that. Other people show a raised forearm (guard), a drawn-back leg (a kick coming) or both arms over the face (a flinch).

## After a bite
- The area round the bite (about 100 studs) is on **high alert for 90 seconds**:
  - everybody there strikes harder (the hidden boost: a kick does 69 instead of 55, still never one-kick-kills);
  - everybody is twice as ready to swing and kick;
  - a second bite there is **close to impossible** (one twentieth of the usual chance).
- **Police within about two blocks** (880 studs, the town's road spacing) **chase** the rodent. They give up if it gets more than five blocks (2,200 studs) from the bite, if it goes down a drain or into a hollow tree, or after the 90 seconds.
- **The ambulance sequence plays out as before.** The play-through spec checks the shout, the collapse, the crowd and its lines, the ambulance driving there on the roads, the crew loading the patient, the hospital bed and the cure, which happens only at the hospital. It also checks the delayed symptoms, a player's own townsperson being bitten, two bites seconds apart, and a bite 2,151 studs from the hospital.

## The numbers (the duel simulation: 400 duels each, the person already aware of the rodent 30 studs away)

| Rodent | against | wins |
|---|---|---|
| skilled (timing, zig-zag, feints, reading the tell) | a calm person | 92 % |
| skilled | a wary person | 89 % |
| skilled | **a vigilante** | **35 %** |
| straight sprint and pounce, no tricks | a calm person | 76 % |
| straight sprint | **a vigilante** | **10 %** |
| skilled, right after a bite nearby | calm / wary / vigilante | 18 % / 9 % / 1 % |

Against a vigilante, a skilled rodent takes almost two blows per fight on average (two blows knock it out).

## What to try (Studio, Play, or two test windows)
1. **Spicy Rodent.** Walk into a townsperson. Nothing happens (no more bites by contact).
2. **Click** next to a townsperson who has not seen you. You crouch for a moment, lunge and bite: the shout, then the collapse or the walk-off with symptoms later, and the ambulance.
3. Find someone squaring up with both fists raised: that is a **vigilante**. They walk at you. Pounce straight at them and you are almost always kicked, two kicks and you are out. Now try this instead: stay just out of reach, **zig-zag**, wait for the kick, step back out of it, and pounce the moment it misses. Or **F** to feint and pounce when they swing at nothing.
4. Bite someone, then try to bite someone else nearby straight away. You are batted away again and again ("Everyone here is on alert after that bite: get clear first"), and the people round you fight harder. Police start running toward you.
5. **Two windows:** one player as a townsperson, the other as the rodent. The townsperson's **F** kick timed into the lunge stops the bite (a raised leg). Otherwise the bite lands.
6. Watch a person's stance change as the rodent comes close: fists up (a vigilante), a forearm up, a leg drawn back before a kick, arms over the face in a flinch.

## Sounds
The duel's five sounds have their names and places (a hiss at the wind-up, a whoosh at a strike, a soft thump and squeak when a blow lands, a slap and yelp when a bite is batted away, a "Hey!" when a vigilante squares up). They are silent until we pick them from Roblox's licensed library (`docs/AUDIO_BUDGET.md`).

## Questions for you (each has a default already built in)
1. **Is the vigilante hard enough, or too hard?** Default: a skilled rodent wins about a third of the time and an unskilled one about a tenth. The numbers are all in `Tunables duel.*`.
2. **Should calm people be harder?** Default: a skilled rodent wins about nine times in ten (the brief: "unaware people are easier"). If you want them tougher, the main dial is how often a running person shakes the bite off (`duel.biteRunner`).
3. **Is the vigilante's tell too obvious?** Default: both fists up whenever they face the rodent. The brief keeps the vigilante flag hidden, but you asked for them to be readable.
4. **Police chase range:** the brief's "two blocks" on this town is 880 studs, which covers most of the middle of town. Default: kept as the brief says.
5. **Feint on F:** the rodent's F was unused (it showed "only people can kick"). Default: F feints, and on a gamepad X (the person's kick button) feints for the rodent too.
