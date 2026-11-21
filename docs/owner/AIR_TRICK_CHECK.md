# The air trick, its burst, and the grab-and-jump cooldown: what to try (10 minutes)

**New on 21 November (D20): the mid-jump press is now also a burst.** You asked: "I kinda wanted the g button push and the action to also result in a little burst of instantaneous movement in the direction the camera and squirrel were then turned at that second"; "i want the squirrel to at that second, twist and contort, stretch and turn in that instant and reposition the jump"; "like a cat or rabbit, guinea pig ... flexible and spasmatic ... almost seems to redirect or convert movement in another direction"; "it should feel slightly like a dash, and give you that new direction and further distance, but no extra elevation at all". That is section 1a below; the rest of this sheet is updated to match.

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

**Press mid-jump: the twist and the burst (section 1a), and from that moment you aim the rest of the jump.** One per jump. After the burst, from the press until you land:
- **Turn the camera left or right:** the jump turns with it, up to **30 degrees** more either way. It keeps its speed.
- **Look up: further out.** At most **9 % further** on top of the burst, and the burst and "further out" together never add more than about a fifth to the jump (table in section 1a). It is best pressed just before the top of the jump, less if you press early, and almost nothing just before landing.
- **Look down: closer in and down.** The jump slows across and drops sooner. Pressed before the top of a leap it comes in by **15 % or more** of the jump (up to about 40 % pressed right after take-off), measured against the same press with no aim; from a higher drop it comes in by more studs.
- Full aim is reached with about a 15-degree tilt of the camera up or down (or a 90-pixel drag on a phone). The jump follows the aim smoothly, never with a snap.
- **The meter:** a mid-jump press takes **10 %** of the sprint meter if there is any left. With an empty meter it still works and costs nothing.

**Question for you:** with an empty meter the wiggle and the aim still work for free (we read your words "if they have a non-empty meter, it takes 10%" that way). If you would rather it did nothing on an empty meter, say so: it is a one-line change.

Measured on flat open ground, a sprint leap with the aim held full out or full in from the press. Each number is the change against the same press with the aim left alone (so the burst is in both), as a percent of the plain leap's distance:

| Pressed (after take-off) | 0.05 s | 0.15 s | 0.25 s | 0.35 s (near the top) | 0.43 s | 0.53 s | 0.63 s | 0.73 s |
|---|---|---|---|---|---|---|---|---|
| Out, W + Shift held | +0.8 % | +5.0 % | +5.7 % | +5.4 % | +5.2 % | +4.9 % | +4.4 % | 0 (the roll instead) |
| In, W + Shift held | -43 % | -35 % | -28 % | -22 % | -17 % | -12 % | -8 % | 0 |

"Out" is a little less than before (it was up to 7.5 %): the burst now takes part of the room, so that the whole trick stays at about a fifth of a jump.

Hopping across open ground with W and Shift and the trick pressed at the best moment in every jump: over 6 s from a full meter 29.7 studs per second (27.1 without the trick); from an empty meter, over 30 s, 24.3 (20.5 without). So the trick is now worth about a tenth to a fifth on your pace across open ground.

## 1a. The burst: the press throws the jump onto a new line (new, D20)

It is tuned to look like a cat's or a rabbit's mid-air twist: a sudden, springy flex of the whole body that turns the momentum the jump already has and gives it a little extra push. It is not a second jump.

At the instant you press G mid-jump, three things happen together:

1. **The jump turns to where you are heading.** That is where the camera looks (with W held, or no key). If you are holding A, S or D instead, it is the way that key steers, so the burst never fights your steering. The jump's line turns to it at once, by up to **60 degrees**; past that it turns 60 degrees and your steering does the rest.
2. **A pop of speed along that line: 25 % more speed, fading back to normal over 0.3 s.**
3. **The squirrel is thrown 2.5 studs along that line** (about its own length) over the first 0.12 s, most of it in the first three frames. It is spread over those frames, never a one-frame jump of position.

No lift at all: the height of the jump and the moment you land are exactly what they were. We checked this frame by frame against the same jump without the press.

**How far it carries.** The burst alone, pressed at any moment of the jump, with nothing else touched:

| Jump (flat ground) | Plain distance | The burst alone | The burst and "further out" together, at most |
|---|---|---|---|
| Sprint leap (W + Shift) | 29.9 studs | +3.6 to +3.8 studs (12 to 13 %) | +5.5 studs (18.5 %) |
| Running leap (W) | 20.5 studs | +3.2 to +3.6 studs (15 to 18 %) | +4.4 studs (21 %) |
| Standing leap (no key) | 22.2 studs | +3.1 to +3.7 studs (14 to 17 %) | +4.7 studs (21 %) |
| Winded leap (empty meter, W) | 17.4 studs | +2.1 to +2.2 studs (12 to 13 %) | +3.3 studs (19 %) |

The burst is the same number of studs whatever you do with the aim afterwards. On the shorter jumps the same burst is a bigger share of the jump, which is why those rows read higher.

**Out of breath (the meter empty): two thirds of it** (1.7 studs and 17 % more speed).

**Once per jump, and it cannot be spammed.** Two limits keep quick hops from stacking bursts:
- on the short chained hops along a branch or a wire (grab, jump, grab, jump), the press still does the wiggle and the aim, but gives no burst;
- there is never more than one burst every half second.

Ordinary jumps are not affected: a leap lasts 0.85 s, so every jump has its burst. Measured along the river bridge parapet and the avenue cable, chaining grab-and-jump with G pressed in every hop is no faster than without G (parapet 24.6 to 26.7 against 25.6 to 28.0 studs per second; cable 25.0 to 29.1 against 27.3 to 29.1).

**What you see.** The squirrel's own body does the throwing: in the first tenth of a second the head and chest snap toward the new line, the hips are left behind and then whip round past it like a rabbit kicking out, the tail lashes the other way and the body banks into the turn. At the same time it stretches long along the new line (front paws reaching, hind legs trailing, ears flat) and holds that stretch for a beat while the extra speed lasts. It springs: in, a little past, and back. Pressed straight ahead there is no twist, only the stretch and the snap forward. The twitch that follows (section 1b) is picked by the turn as well: a throw to one side makes a spin or a tail whip more likely, a throw back toward the camera a back tuck.

**The three numbers you can ask to change:**

| | Now | Ask for |
|---|---|---|
| How far the pop throws the squirrel | 2.5 studs | further or less |
| How much extra speed | 25 % | more or less |
| How long the extra speed lasts | 0.3 s | longer or shorter |

Also one number each: the most the jump turns at the press (60 degrees), how much a winded squirrel gets (two thirds), and the half-second limit.

**The camera** is not pushed or shaken. The squirrel moves ahead of it for a moment and the camera catches up as it always does, which already reads as a dash.

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

While you are aiming, a small flat disc lies where your jump will come down. Only you see it. It shows the new landing spot from the very frame of the press, burst included.

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

Measured with W and Shift held, pressing E and Space together every 2, 3 or 6 frames (studs per second). The last
number in each cell is with your D19 change (chained leaps carry less, see `RAIL_PACE_CHECK.md`):

| Where | Macro every 2 frames: before / cooldown / D19 | Every 3 | A person, every 6 |
|---|---|---|---|
| River bridge parapet | 47.3 / 39.4 / **28.0** | 35.7 / 41.6 / **28.0** | 41.6 / 41.6 / **28.0** |
| Avenue cable | 49.9 / 37.5 / **25.0** | 49.9 / 41.6 / **28.2** | 41.6 / 41.6 / **28.2** |
| Up the tallest trunk | 30.7 / 29.7 / **27.0** | 30.3 / 28.7 / **25.0** | 28.7 / 28.7 / **25.0** |

So mashing gets about what a person's rhythm gets, no more (up a trunk a fast rhythm is 2 studs per second quicker;
both are inside the climb's band).

The server now checks chained leaps too (see `RAIL_PACE_CHECK.md`): a modified game sending a crafted chain along a long
rail gets about 35-38 studs per second, against the game's own 28-33.

## 4. Sounds and other players

- The roll plays a soft whoosh and the wiggle a quick light swish (Cloth Whooshes Soft 1 and Swish, Paddle Swish, Soft, from the licensed library; nothing uploaded). If one does not fit, it is a one-line swap.
- Other players see your roll on landing and your wiggle in the air (within about 120 studs of their camera). They do not see your aim marker.
- The controls help (the M menu, and the line at the bottom of the screen) now says: G mid-jump: a burst the way you face, then aim with the mouse; G as you land: roll.

## What to look at

0. **The burst (new).** Play a **Squirrel**, run with **W**, leap with **Space** and press **G** mid-jump. Does the squirrel pop forward and land clearly further, with no extra height? Does it feel "slightly like a dash"? Then leap, swing the camera to one side and press **G**: does the jump snap onto the new direction, and does the body look as if it threw itself there? Is the pop too much, too little, too long?
1. Leap with **Space**, press **G** near the top of the jump, then move the mouse left and right. Does the jump follow? Is 30 degrees enough, or too much? Press **G** on several jumps with no aim: mostly the wiggle, sometimes something odd. Then push the aim hard to a side, up or down: spins, somersaults, back tucks, corkscrews and cartwheels. Are they fun and clearly mild?
2. Leap, press **G** near the top, and look up. Does the jump carry a little further? Look down instead: does it come in and drop?
3. Is the marker easy to see without getting in the way? (Size, colour and opacity above.)
4. Fall toward the ground and press **G** just as you land. Does the roll look right, and does it keep your speed nicely?
5. On a gamepad: **R1** and the right stick. On a phone: tap **TRICK** mid-jump and drag from it.
6. Run with the meter low and press **G** mid-jump: the meter should drop by a tenth.
7. With two players: does the other player see your roll and wiggle?
8. Chain E and Space along a branch or wire at your own pace: it should feel exactly as before. Mashing them as fast as you can should get you no further, and neither should adding G to the chain.

## The server checks

The server's movement checks are switched off in the live game for now (since version 54; they only log). They are kept correct for when they come back.

In our tests, players doing a trick on every jump (bursting with the camera swung any way, aiming every which way, rolling on landings), on a good connection and on a bad one with lost packets, were never flagged for the trick (8 runs of each kind, about 7,400 presses each). The server counts the burst itself: one per jump and no more than one every half second. A message stream that takes the burst without claiming it, takes twice the burst, or takes a second burst in the same jump or inside the half second is flagged. A cheat that claims a trick in every message along the river bridge parapet gets 33.3 studs per second against 33.4 without the claims (20 messages a second) and 38.8 against 37.8 (4 a second); on open ground the claims only slowed it.

## 1.1: the G press, stronger and simpler (21 November)

What the owner asked: "a bit more, a little bit further propellant by the g button push ... the squirrel re-directs, within 30 degrees left or right, or if the s button is being held, drops the jump back a little bit, or if the w button is being held, gives you that ... forward burst".

- **Direction:** the jump turns toward where the camera is facing, at most 30 degrees left or right of the jump's own line. Turn the camera with the mouse mid-jump, then press G.
- **W held:** the full burst: about 6 to 9 studs farther (a sprint leap of 30 studs lands about 7 to 8 studs farther).
- **No key held:** a smaller burst, about 4 to 6 studs farther.
- **S held:** no burst; the jump is pulled back and lands shorter.
- **No extra height** in any case. Once per jump. On an empty meter, about two thirds.

The numbers you can ask to change: how strong the burst is (W), how much of it you get with no key (now 70 %), how far S pulls the jump back (now 30 % of its speed), and the 30 degrees.

## 1.2: a bigger lunge (21 November)

The G press's burst is a step bigger. Holding W, a sprint leap of 30 studs now lands about 8 to 9 studs farther (1.1: about 7); with no key held, about 5 to 6 studs farther. Direction (toward the camera, 30 degrees either side), S pulling the jump back, and no extra height are unchanged.

## 1.4: more forward, and real side lunges (21 November)

- **Forward (W held):** a little more again: a sprint leap of 30 studs lands about 9 to 10 studs farther.
- **Turning:** the jump now turns toward the camera by up to 55 degrees either side (it was 30).
- **Side lunge (A or D held when you press G):** the jump is thrown 45 degrees to that side of where the camera faces, about a fifth stronger than the forward burst. Try jump, hold D, press G.
- **S held** still pulls the jump back; no extra height in any case; once per jump.
