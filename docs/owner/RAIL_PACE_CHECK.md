# Chains along rails and climbs up trunks at a balanced pace: what to try (5 minutes)

Your words (D19, 20 November): "make these closer to the average on the ground, or even slightly slower", then "its ok if it is a little bit faster ... just bring it to a balanced, fun, game physics".

## What changed

A leap off a branch, wire, cable, parapet or trunk that comes **straight after another one** (you landed on the rail from a leap off a rail and jumped again within a quarter of a second) now carries a bit less: about **70 %** as far forward and **88 %** as high. That is what makes long E+Space or Space-held chains, and E+Space trunk climbs, come down to a pace a little above running on the ground.

Not changed:
- **The first leap is a full one.** Standing on a branch, or pausing on it for a quarter of a second, and then leaping carries exactly as before, so every gap between branches, wires and roofs is still crossable.
- Running along a rail, walking or sprinting on the ground, hopping, the pounce and the air trick.

## Before and after (studs per second, W and Shift held, measured in the game's own physics)

| Way of travelling | River bridge parapet: before / now | Avenue cable: before / now | Up the tallest trunk: before / now |
|---|---|---|---|
| Space held (leap, land, leap) | 41.4 / **29.7** | 41.4 / **29.8** | - |
| E+Space about every sixth frame (a person) | 41.6 / **28.0** | 41.6 / **28.2** | 28.7 / **25.0** |
| E+Space every fourth frame | 39.4 / **28.0** | 37.5 / **25.0** | 29.7 / **26.7** |
| E+Space every other frame (a macro) | 39.4 / **28.0** | 37.5 / **25.0** | 29.7 / **27.0** |
| Just running along it (sprint) | 24.7 / 24.7 | 24.9 / 24.9 | 18.3 / 18.3 |
| For comparison, on the ground | walk 17.9, held sprint about 22.5, hopping 20-24 | | |

So chains along a rail are now about 25-30 studs per second (the target was 26-32), trunk climbs about 25-27 (target 24-28), and mashing gets no more than a person's rhythm (up a trunk a very fast rhythm is about 2 studs per second quicker; both are inside the band).

## What to try

1. **A chain along the river bridge parapet or a long cable**: hold W and Shift, press E and Space together in a rhythm, or just hold Space. It should feel brisk, a little quicker than sprinting on the ground, not a rocket. The first jump off still feels as strong as before.
2. **Branch to branch in a tree**: jump from one branch to the next one you could reach before. It should still make it. If you land and jump again at once, that second jump is a little shorter; pause a moment on the branch and it is a full one again.
3. **Climb the tallest tree with E+Space**: about 5 seconds to the top of a 127-stud trunk (it was about 4.4).

If the chains now feel too slow or too fast, it is one number each: how much a chained leap carries forward (0.69), how much it rises (0.88), and how long a pause restores a full leap (0.25 s).

## The server's checks

The server now knows about chained leaps too, so a modified game cannot claim the old speeds: a crafted chain along a long rail is held to about 33-38 studs per second, and a crafted trunk climb to the server's climbing limit (about 30 studs per second over a long climb, a little more over the first few seconds). Players who play normally are not flagged more than before (the honest test runs flag fewer climbs than before).
