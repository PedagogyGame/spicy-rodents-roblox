# The air trick, redone, and the grab-and-jump cooldown: what to try (10 minutes)

You asked on 20 November (D18):
- "barrel roll should be when you press as you land, twitch wiggle re-aim 30 degrees in each direction, and 15 degrees closer in or farther out ... per mouse movements, from the moment the button is pushed mid jump";
- then: "it extends the jump, if pressed at the right time ... a maximum of 9% further out, mid-jump, and they could still bring the jump back in and down up to 15% or more ... only one of these maneuvers per jump ... if they have a non-empty meter, it takes 10% from meter";
- "make the marker that shows up with that super subtle and small please, light sky blue perhaps, non-invasive";
- "you can go ahead with grab and jump cooldowns".

All of it is built. Everything below was tested without a screen, on the real movement and the real server checks. Only you can judge how it looks and feels.

## 1. The trick: one button, two moves

| Device | Button | Aiming the jump after a mid-jump press |
|---|---|---|
| Keyboard and mouse | **G** | move the **mouse** (the camera turns with it, as it always does) |
| Gamepad | **R1** (right shoulder) | the **right stick** |
| Phone or tablet | the round **TRICK** button above the jump button (shown while you are in the air) | keep your finger down and **drag from the button**: sideways to turn, up to go further, down to come in |

**Press as you land: a barrel roll.** Press G just before you touch down (in the last 0.15 s of the fall) or right on the landing (within 0.1 s after). The squirrel rolls one full turn around its own length and carries on along the ground at exactly the speed it landed with: the roll keeps your speed, it never adds any. Turning keys do nothing during the roll (0.45 s); a leap ends it.

**Press mid-jump: the twitch-and-wiggle, and from that moment you aim the rest of the jump.** One per jump. From the press until you land:
- **Turn the camera left or right:** the jump turns with it, up to **30 degrees** either way. It keeps its speed.
- **Look up: further out.** At most **9 % further** than the same jump would have gone. How much you get depends on when you pressed: it is best just before the top of the jump (we measured up to about 7.5 % then), less if you press early, and almost nothing if you press just before landing.
- **Look down: closer in and down.** The jump slows across and drops sooner. Pressed before the top of a leap it comes in by **15 % or more** (up to about 40 % pressed right after take-off); from a higher drop it comes in by more studs.
- Full aim is reached with about a 15-degree tilt of the camera up or down (or a 90-pixel drag on a phone). The jump follows the aim smoothly, never with a snap.
- **The meter:** a mid-jump press takes **10 %** of the sprint meter if there is any left. With an empty meter it still works and costs nothing.

**Question for you:** with an empty meter the wiggle and the aim still work for free (we read your words "if they have a non-empty meter, it takes 10%" that way). If you would rather it did nothing on an empty meter, say so: it is a one-line change.

Measured on flat open ground, a leap with the aim held full out or full in from the press (percent of the plain leap's distance):

| Pressed (after take-off) | 0.05 s | 0.15 s | 0.25 s | 0.35 s (near the top) | 0.43 s | 0.53 s | 0.63 s | 0.73 s |
|---|---|---|---|---|---|---|---|---|
| Out, W + Shift held | +0.8 % | +4.9 % | +7.5 % | +7.3 % | +7.0 % | +6.5 % | +3.9 % | 0 (the roll instead) |
| In, W + Shift held | -43 % | -34 % | -28 % | -21 % | -17 % | -12 % | -7 % | 0 |

Hopping across open ground with W and Shift, over 6 s from a full meter: 27.1 studs per second with or without the trick (the 10 % cost uses up the gain). From an empty meter, over 30 s: 20.5 without and 22.0 with the trick pressed at the best moment in every jump.

## 1b. What the twitch looks like: nine moves, picked partly at random by your aim

You asked for "a quick spin, twist, summersault, 360 plus weird strange bizarre body-twists ... a variety ... based on the final aim and direction", "all sorts of variations and combinations", "keep side to side wiggle as primary, and add the others in for other situations or angles", and "make which one occurs partially random". So the mid-jump twitch is now one of nine moves:

| Move | What it looks like |
|---|---|
| **Wiggle** (the main one) | the side-to-side shimmy: hips and tail swing, head and ears twitch |
| Spin | a flat spin, tail flung out, ears laid back |
| Somersault | a forward flip, tucked tight |
| Back tuck | a backward flip, back arched |
| Corkscrew | a roll and a spin at once, the body wrung, the tail in a spiral |
| Cartwheel | a sideways turn, spread wide, tail fanned |
| Pretzel | head and hips twisting against each other, twice |
| Starfish | a snap wide open and shut in the middle of the jump |
| Tail whip | the tail cracked round in a double spiral |

Which one you get depends on your aim **and** on chance. Measured over 1,024 jumps for each aim:

| Your aim during the twitch | What you mostly get |
|---|---|
| Small or no aim (ordinary jumps) | the **wiggle** about 87 % of the time; now and then a pretzel (8 %), a starfish or a tail whip |
| Hard left or right | a **spin** about 59 %, the wiggle 26 %, sometimes a tail whip or starfish |
| Full out (looking up) | a **somersault** about 65 %, the wiggle 24 %, sometimes a starfish |
| Full in (looking down) | a **back tuck** about 64 %, the wiggle 25 %, sometimes a starfish |
| Out and to a side | a **corkscrew** about 48 %, the wiggle 23 %, sometimes a spin or a somersault |
| In and to a side | a **cartwheel** about 48 %, the wiggle 24 %, sometimes a spin or a back tuck |

Over ordinary play the wiggle is by far the most common. On top of that, about 4 twitches in 10 lay a second, odd move over the first part-way through (a pretzel, a starfish, a tail whip or a wiggle), so the squirrel rarely does exactly the same thing twice. Turning moves turn twice round (720 degrees) in under half a second. If you move the aim during the twitch, the move blends toward what the new aim would give instead of jumping. Every twitch ends upright and facing the way the jump is going, so the landing (and the landing roll) look normal.

Everyone sees the same move: the "random" pick comes from the moment you pressed the button, which the server passes on to the other players together with your aim. It changes nothing about how far or where you jump.

To change: how often the wiggle comes up, how often a second move is laid over, or any move's shape, are each one number.

## 2. The aim marker

While you are aiming, a small flat disc lies where your jump will come down. Only you see it.

| | Now | To change it, ask for |
|---|---|---|
| Size | 1.2 studs across (about half a squirrel), 0.05 thick | bigger or smaller |
| Colour | light sky blue (red 150, green 205, blue 240) | another colour |
| Opacity | 28 % (72 % see-through) | fainter or stronger |
| Fade | in and out over 0.15 s | slower or quicker |

No text, no glow, no shadow. It disappears as soon as you land.

## 3. The grab-and-jump cooldown

After a leap off a branch or wire, **E does not grab again in the air for 0.065 s** (just under four frames). So E+Space mashed together by a key-repeat macro can chain no faster than about a person's rhythm. A person's own rhythm and every normal climb are not affected.

We started at 0.25 s as you suggested, but that also held back a person's normal chain (E+Space about every sixth frame). Longer than four frames also turned some fast rhythms into a pattern the server's climbing checks wrongly flag, so 0.065 s is the value that slows the macro without touching anyone honest.

Measured with W and Shift held, pressing E and Space together every 2, 3 or 6 frames (studs per second):

| Where | Macro every 2 frames: before / now | Every 3: before / now | A person, every 6: before / now |
|---|---|---|---|
| River bridge parapet | 47.3 / **39.4** | 35.7 / **41.6** | 41.6 / 41.6 |
| Avenue cable | 49.9 / **37.5** | 49.9 / **41.6** | 41.6 / 41.6 |
| Up the tallest trunk | 30.7 / **29.7** | 30.3 / **28.7** | 28.7 / 28.7 |

So mashing now gets about what a person's rhythm gets, no more.

One thing still open: the server's movement checks do not use this cooldown yet. A cheating client (not a macro, a modified game) can still chain at about 47 studs per second along a long rail, as before. Making the server check it is a follow-up for the movement-check work going on now.

## 4. Sounds and other players

- The roll plays a soft whoosh and the wiggle a quick light swish (Cloth Whooshes Soft 1 and Swish, Paddle Swish, Soft, from the licensed library; nothing uploaded). If one does not fit, it is a one-line swap.
- Other players see your roll on landing and your wiggle in the air (within about 120 studs of their camera). They do not see your aim marker.
- The controls help (the M menu, and the line at the bottom of the screen) now says: G mid-jump: wiggle and aim with the mouse; G as you land: roll.

## What to look at

1. Play a **Squirrel**. Leap with **Space**, press **G** near the top of the jump, then move the mouse left and right. Does the jump follow? Is 30 degrees enough, or too much? Press **G** on several jumps with no aim: mostly the wiggle, sometimes something odd. Then push the aim hard to a side, up or down: spins, somersaults, back tucks, corkscrews and cartwheels. Are they fun and clearly mild?
2. Leap, press **G** near the top, and look up. Does the jump carry a little further? Look down instead: does it come in and drop?
3. Is the marker easy to see without getting in the way? (Size, colour and opacity above.)
4. Fall toward the ground and press **G** just as you land. Does the roll look right, and does it keep your speed nicely?
5. On a gamepad: **R1** and the right stick. On a phone: tap **TRICK** mid-jump and drag from it.
6. Run with the meter low and press **G** mid-jump: the meter should drop by a tenth.
7. With two players: does the other player see your roll and wiggle?
8. Chain E and Space along a branch or wire at your own pace: it should feel exactly as before. Mashing them as fast as you can should get you no further.

## The server checks

In our tests, players doing a trick on every jump (aiming every which way, rolling on landings), on a good connection and on a bad one with lost packets, were never put back. A cheat that claims a trick and the full aim in every message gains nothing over an honest player: along the river bridge parapet 46.6 against 46.9 without the claims (20 messages a second) and 47.5 against 46.5 (4 a second); on open ground the claims only slowed it.
