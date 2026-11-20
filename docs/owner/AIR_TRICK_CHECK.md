# Hopping and the air trick: what to try (10 minutes)

You asked for two things on 20 November (D17):
- "hopping speed, a combination between a and b, slight advantage even if there is empty meter, but not the same";
- "a barrel roll and a twitch and twerk in the air the squirrel can do with an extra button", which also lets you steer where the jump lands.

Both are built. Everything below was tested without a screen, on the real movement and the real server checks. Only you can judge how it looks and feels.

## 1. Hopping on an empty meter

A leap made while the meter is empty now carries further than a walk, but still well short of a leap with meter. It still rises just as high.

Measured on flat open ground, holding W the whole time, over 30 seconds (studs per second):

| How you move | Before | Now |
|---|---|---|
| Walking (no leaps) | 17.9 | 17.9 (unchanged) |
| Hopping as you land, meter **full** (the first 6 s, until it runs out) | 24.1 | 24.1 (unchanged) |
| Leap, walk 1.2 s, leap..., meter **full** (the meter never runs out at this pace) | 20.3 | 20.3 (unchanged) |
| Hopping as you land, meter **empty** | 18.0 (no better than walking) | **20.5 (14 % faster than walking)** |
| Leap, walk 0.6 s, leap..., meter **empty** | 17.9 | **19.4 (8 % faster)** |
| Leap, walk 1.2 s, leap..., meter **empty** | 17.9 | **19.0 (6 % faster)** |

So on an empty meter hopping now gives a small edge (6 to 14 %, depending on how you hop), and hopping with meter is still clearly better (24.1 against 20.5 when you hop as you land). Sprinting is not changed: a full meter is still 4 seconds of sprint at 33 studs per second.

A note on the old figure: the earlier report said leap-then-walk "held 32-34 st/s even on an empty meter". That number came from a measuring mistake (the test squirrel was pushed against the edge of the world, and that push was counted as distance). The real figure was about 18 on an empty meter, which is why it felt the same as walking.

**What to try:** sprint until the meter is empty, then keep hopping with Space while holding W. You should pull a little ahead of a squirrel that only walks, but not as much as when you had meter.

## 2. The air trick

**One button, only in the air** (after a leap, while falling, after a drop from a branch):

| Device | Button |
|---|---|
| Keyboard | **G** |
| Gamepad | **R1** (right shoulder button) |
| Phone or tablet | a round **TRICK** button above the jump button. It only appears while you are in the air and still have a move left. |

- **First press in a jump: a barrel roll.** The squirrel spins one full turn around its own length, in a little under half a second. The back curls and the tail wraps round as it goes.
- **Second press in the same jump: a twitch-and-wiggle.** A quick cartoon shimmy: the hips and the tail swing side to side, and the head and ears give a twitch. It is side to side only, playful and mild.
- **A third press does nothing.** You get both moves again on your next jump.
- **A press during a move does nothing.** Wait for the roll to finish, then press again for the wiggle.
- **It does nothing on the ground or on a branch.** It also does nothing during a pounce.
- **It works with an empty meter too.**

**Steering:** while a move plays, the direction keys (WASD, the stick) turn your jump toward where you are pointing much faster than normal. You can bend a jump round a corner, or bring it back toward the branch you wanted. The trick never makes you faster and never makes you go higher. A jump steered with the trick always lands closer than a straight jump with W held: in our test, a leap steered to the right landed 15 studs to the side with the trick and 10 without.

**Sounds:** the roll plays a soft whoosh and the wiggle a quick light swish. They are two sounds the game already uses (Cloth Whooshes Soft 1 and Swish, Paddle Swish, Soft from the licensed library), so nothing was uploaded. Neither has been heard in the game yet: if one does not fit, it is a one-line swap.

**Other players see it.** The server tells everyone else's screen when your squirrel does a move, so they see the roll and the wiggle too (only within about 120 studs of their camera).

**The controls help** (the M menu, and the line at the bottom of the screen) now lists the G key.

## What to look at

1. Play a **Squirrel**. Leap with **Space** and press **G** at once. Does the roll look like a barrel roll? Is it too fast or too slow? (It is 0.45 s. The wiggle is 0.5 s. Both are one-number changes.)
2. Leap, press **G**, wait for the roll to end, press **G** again for the wiggle. Is the wiggle playful and clearly mild?
3. Leap toward a branch, press **G**, and hold **A** or **D**. Can you steer the landing the way you wanted? Is it too strong or too weak? (The turn rate is one number.)
4. On a phone: the **TRICK** button should appear only while you are in the air. Is it in a good place and easy to reach?
5. On a gamepad: **R1** in the air.
6. With two players: does the other player see your roll and wiggle?
7. Play the **Spicy Rodent** too: it has the same trick.

## Not changed

- Pouncing on an empty meter is still no faster than a walk.
- Leaps off a branch or a wire are still always full leaps, free of the meter.
- The server's movement checks treat the trick as honest: in our tests, players doing a move on every jump, on a good connection and on a bad one with lost packets, were never put back. A cheat that claims to be doing a trick in every message gains no speed.
