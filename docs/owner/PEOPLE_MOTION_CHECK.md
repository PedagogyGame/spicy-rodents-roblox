# How people move: what changed and what to look at (5 minutes)

You asked on 21 November (D27): "please try to smoothen up the movement of the townsperson and human characters movement, i like their form, but the movement, waddles, jolts left right, rocks, does not walk or run in a straight smooth line or smoothly, so just tidy the basic movement up, bring it into a smooth dynamic forward motion, torso led".

How people look is untouched: the same bodies, proportions and clothes, the same walk and run animations underneath. Only how they move changed. None of it could be seen here: it was built and measured without a screen, so the numbers below are measurements and the look is yours to judge.

## What was wrong (measured before the change)

| What you saw | What it was | Size before |
|---|---|---|
| A townsperson moving in tiny stops and jumps | The game sends your screen each townsperson's place only 10 to 20 times a second, and the body was drawn exactly where the last message put it: still for two or three frames, then a jump | Out of every three frames the body stood still for two; the pace from frame to frame swung by 300 to 700 % |
| Legs speeding up and slowing down | The walk animation was timed from that stop-and-jump movement | The animation's pace swung by 41 to 75 % |
| A jolt to the left or right | A person stepping round a lamp post or a tree on the pavement was slid sideways while still facing straight ahead | Sideways at 11 to 18 studs a second (a stroll is 3), started within one frame |
| A snap at a turn | The turn started and stopped at full rate within one frame | The turning rate jumped by 4 radians a second in one frame |
| Waddle and rock | The stock walk and run animations swing the hips and chest from side to side | Not measurable here (the animation files are Roblox's and could not be opened from this machine) |

## What it does now

1. **A townsperson is drawn walking, not jumping.** The body on your screen now walks after the place the game sends, at a steady pace, in a straight line. It never overshoots and comes back. Frame-to-frame pace now varies by 12 to 16 % (it was 300 to 700 %), and the body never stands still in mid-walk.
2. **The legs keep time with the ground.** The walk and run animations are timed from that steady drawn movement.
3. **Stepping round a post is a gentle diagonal.** The person starts the step aside about two and a half seconds before the post, walks it at their usual pace, turned slightly the way they are going, and comes back onto the pavement's line the same way.
4. **Turns are eased.** A turn builds up over about a tenth of a second and settles gently, with no snap and no swing back. On your screen the facing also turns smoothly between the game's messages.
5. **Torso-led.** For every person walking or running, townspeople and the person a player controls:
   - the side-to-side roll and twist of the hips and chest from the animation are cut to about a third (a small natural counter-swing stays); the sideways shift of the hips likewise; the up-and-down bob is kept at 70 %;
   - the chest leans forward a little, more with speed: about 2.5 degrees at a stroll, 5 at a player's walk, 7 at a sprint;
   - going into a turn, the chest turns first toward where the person is heading (up to 25 degrees), and the feet follow.
6. **Someone who is ill still staggers.** The sway of a person with the infection's symptoms is unchanged. Nobody else sways.

## What to look at

1. **Stand on a pavement and watch townspeople stroll past, side on and head on.** They should glide forward evenly, upright with a slight forward lean, the shoulders nearly level, no rocking from side to side, no small stops.
2. **Watch one from behind as it walks away.** The hips should stay close to level. A small sway is intended; a clear waddle is not.
3. **As the Spicy Rodent, scare someone and watch them run.** A straight, even run with more forward lean. Where they turn around or round a corner, the chest should turn first and the body follow without a snap.
4. **Find a lamp post or tree standing on a pavement and watch someone pass it.** A gentle curve round it and back, facing the way they go. There are only four such posts on the pavements, so this one is rare.
5. **Become a person and walk, then hold Shift to sprint, and turn sharply.** The same steadier torso and forward lean; your own speeds and controls are exactly as before.
6. **Find someone with the symptoms (red eyes, before they collapse).** They should still stagger.

## Things you may want changed (each is one number)

- **Too stiff?** If people now look like they glide with a rigid torso, the share of the animation's hip and chest swing that is kept (35 %) can go up; if there is still a waddle, it can go down.
- **Lean.** If the forward lean reads as too much on top of the run animation's own lean, or too little, the two angles (2 and 7 degrees) can change.
- **The chest turning into a turn** (25 degrees at most) can be made stronger, weaker or switched off.
- **Bob.** The up-and-down bob is at 70 % of the animation's; it can go lower for a flatter glide.

## What was not changed, and two things left as they were on purpose

- People's speeds, where they go, how they react to the rodent, and everything about squirrels and vehicles.
- **Turning right around.** A person who reverses direction on the pavement still starts walking the new way at once while the body takes most of a second to turn round. The turn is now eased and the chest leads it, but for that moment the feet still slide a little. Making them stop, turn and then walk would cost a fleeing person about half a second at the start of every run, which changes how easy people are to catch, so it was left for you to decide.
- **A person stops as abruptly as before** when they reach where they were going. The body on your screen walks up to that spot and stops; it no longer jumps to it.

One side effect to know about: the body you see is now about one message behind where the game has it (about a quarter of a stud at a stroll, about 2 studs for someone running flat out, up to about 3 when the messages come slowly). Before, it was between zero and one message behind, in jumps.
