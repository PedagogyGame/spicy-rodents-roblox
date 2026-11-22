# D29 small fixes: what to look at (about 10 minutes)

These are the fixes from your three screenshots: the road, the grey screen in the pickup, the hand on the mallet and the pool room's floor. I also fixed one thing I saw in the screenshots: the keys panel showing through under a game's card. Everything here has been tested without a screen. Please look at each one in the game.

## 1. The road by the brick estate
- **What was wrong.** The street you were standing beside (the west street of the old town, x -450) stopped in the grass 62 studs before the estate avenue. Its lane dashes ran into the grass, and its sidewalk stopped there too. The brick building with the white columns is estate 0's mansion, across the avenue.
- **What I changed.** The street and both of its sidewalks now run on to the avenue and join it. The street on the east side of the old town (x +445) had the same fault, so it is joined too.
- **The same fault elsewhere, also fixed:**
  - The estate connector (the middle street, x 0) used to cross the avenue and stop in the grass on the far side. Its sidewalks were drawn across the avenue. Now it ends at the avenue.
  - Two of the old town's north-south streets stopped about 19 studs short of the north cross road. They now reach it, and so do the west street's sidewalks.
  - Two of the east-west streets stopped about 29 studs short of the westside street. They now reach it, and so do the north street's sidewalks.
  - The westside street stopped 25 studs short of the hospital road. It now reaches it.
  - The north access road lay on top of the east street for about 90 studs, so there were two lines of dashes side by side, and one of its sidewalks was drawn on the road. The westside connector did the same on the south street. Both now start where the other street ends.
  - The four sidewalks at the old town's centre keep their old length. The townspeople's walks and the town's tested scenes are built on them. So at the centre street's north end and the main street's west end, the sidewalk still stops a few studs before the cross road, though the street itself now reaches it.
  - Where a street now meets a cross road, the cross road's sidewalk runs across its mouth, as at every crossroads in the old town.
- **Look at:** walk from the old town's south-west corner down to the estate avenue. The street should run on into the avenue, with no dashes going into the grass. Then do the same at the north and west edges of the old town.
- **Left as they are, for you to decide:**
  - The estate avenue's west end stops about 57 studs short of Lift Road. Joining them needs a change to how the new streets' sidewalks are made, so I left it.
  - Several streets end at the edge of the town: the south and east-west grid streets' east ends, the commercial cross street's north end, the north access road's north end, the hospital road's west end, Liberty Avenue's south end, Chapel Street's east end, Lift Road at the sky lift and Marina Road at the marina car park.
  - At the old town's crossroads, the sidewalks run across the crossing streets. This is how your original town draws them. Cutting them at the street mouths would move the townspeople's walks (see above).

## 2. The grey screen in the pickup truck
- **What was wrong.** In first person, the camera sits at the driver's head. In the pickup, the SUV and the patrol car, that point is inside the solid cab block. The windscreen in front is glass that the game draws solid, so all you saw was the back of the windscreen.
- **What I changed.** When you drive in first person, your own screen hides any part of the vehicle the camera is inside (or touching), and the vehicle's glass becomes see-through. The roof, the bonnet and the dash still show. This works for every vehicle: the pickup, SUV, patrol car, golf cart, bike, jet ski, moped and electric scooter. The drone's camera follows from outside, so it was never affected. Everything goes back when you get out.
- **Look at:** get into the pickup, then the SUV, then (as Police) the patrol car (press **E**). In first person you should see the road ahead over the bonnet. Turn the view with the right mouse button to check the sides.

## 3. A hand on the whack-a-mole mallet
- **What I changed.** When the mallet swings, a right arm holds it: a fist round the foot of the handle with its thumb, a forearm, an elbow and an upper arm to your shoulder. It uses your body's colours: your hand's skin tone, and your sleeves or bare arms as your body has them. If those can't be read, it uses a plain skin tone and a grey-blue sleeve. The fist stays on the handle through the whole swing. When the mallet goes back to its bracket, the hand lets go.
- **People watching** see the player's right arm reach for the mallet, and the body's own right arm is hidden while they do, so nobody has two right arms.
- **Cost:** five small parts per cabinet (three balls and two cylinders), only on screens near it. They don't collide with anything, and they move only when the mallet moves.
- **Other games checked.** Darts shows no dart in your hand before you throw, only the aim marks, so nothing floats. The pool cue and the air hockey striker are drawn on their own, as in most pool and air hockey games. I didn't add hands to those. Say if you want them.
- **Look at:** play a round. The hand should grip the handle from the bottom of the screen as you strike.

## 4. The pool tables' floor
- The rugs under the two pool tables are now a deep purple-navy: border **#201c42**, field **#2a2650**, still fabric. The bumper pool rug was already red, so I left it.
- **Look at:** the games room. The green felt should stand out against the floor.

## 5. The keys panel under a game's card
- **What was wrong.** If the keys panel (**K**) was open when a game's card came up (for example whack-a-mole or pool), the panel showed through underneath the card.
- **What I changed.** While a game's card is up, the keys panel is hidden. It comes back as it was when the card goes (**H**, or leaving the game).
- **Look at:** open the keys with **K**, then start whack-a-mole. Only the game's card should be on the left.
