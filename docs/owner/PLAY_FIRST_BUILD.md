# Play the first build (9 November 2026)

File: `docs/owner/files/SpicyRodents_play.rbxl` (about 1.3 MB). You publish it once from Studio, then you play it from the Roblox website or app like any other game. Play on a computer with a keyboard and mouse: phones and tablets are not supported in this build.

## 5 steps
1. **Publish it (Studio, once).** Open `SpicyRodents_play.rbxl` with File > Open from File. Choose File > Publish to Roblox As…, then pick the existing Spicy Rodents experience and its start place. Close Studio. If the experience is private, you can still play it yourself.
2. **Join from the website or the app.** Open the experience page and press the green Play button. A dark-green screen says SPICY RODENTS and has an orange bar. The line under the bar names each step: the sky, then the ground, river and hills, then the cars, then the 102 people and animals, then "Preparing the climbing routes on this computer". The first player in a new server waits about 5 to 20 seconds. Later players get in almost at once.
3. **Pick who to play.** A menu asks "Who do you want to be?" and shows five big buttons: **Spicy Rodent, Squirrel, Townsperson, Police, Police drone**. Click one. A line at the top says what you became, for example "You are the SPICY RODENT. Bite people!", and the camera moves to your body.
4. **Play.** The dark panel at the bottom left always lists the keys for what you are doing right now. Every key answers on screen, even when it cannot do anything there. For example, F as a squirrel says "Only people can kick".
   - **Spicy Rodent and Squirrel**
     - WASD runs (the camera sets the direction) and Shift sprints.
     - Run into a tree, pole or downspout and keep holding W to climb.
     - A or D chooses the way at a fork, Space leaps, Q drops and E grabs. If there is nothing to grab, the screen tells you.
     - The rodent pounces with a left click and **bites anyone it touches**. The person shouts (a speech bubble over their head) and runs away, and your bite count and Power go up (top centre). What happens to them next is in "After a bite" below.
     - Cars kill you: you see **RUN OVER!** and the menu comes back after 3 seconds.
   - **Townsperson:** WASD walks, Shift sprints and Space jumps. **F kicks**: the rodent has 100 health and a kick does 55, so two kicks knock it out. The top line says whether you hit or missed.
   - **Police:** you start beside the patrol car. Walk up and press **E**: the view moves to the driver's seat. W is gas, S brakes and reverses, A and D steer, and Space is the handbrake. V switches between the inside and outside views. E gets you out.
   - **Police drone:** it takes off by itself about a second after you pick it. WASD flies, Space goes up, Q or Ctrl goes down, Shift boosts, and E lands. You are back on foot next to the drone.
5. **Switch or stop.** The orange **Menu (M)** button at the bottom right, or the M key, brings the menu back at any time. If you get stuck in a wall or the river, press Esc and then Reset Character: this moves you to a safe spot and never kills you. To stop, press Esc and then Leave.

## After a bite (new on 10 November 2026)
- **The bitten person is infected and runs.** One of two things follows:
  - **About half the time they collapse** a short way off, within 4 seconds, and sit on the ground. A few seconds later an **ambulance** leaves the hospital (far west of town) and drives along the roads to the nearest road point. **Sometimes 2 to 4 people from nearby walk over, stand round the patient and say something** (where at least two people are near enough; one onlooker alone does not come). A paramedic steps out of the ambulance and walks to the patient, round any building in the way, the patient is walked back to the ambulance beside the paramedic, and it drives back to the hospital. For someone a long way from the road the paramedic runs.
  - **The rest of the time they get away looking fine.** 40 to 120 seconds later their **eyes turn red** and they stagger. They then either **walk to the hospital themselves** or collapse and get an ambulance as above. Someone who is not on a pavement (the police yard, a shop floor) walks straight across the open ground, round the buildings.
- **The hospital is the only cure.** Nobody gets better on their own, and knocking the rodent out cures nobody. In the hospital a patient sits up on a cot in one of the two wards for 30 seconds, then walks out cured and goes home on foot: townspeople to where they were bitten, staff and officers to their post.
- **If the rodent bites you** while you are a townsperson or an officer, the top line says so and tells you what to do: **walk in through the hospital's front doors and stay inside for 30 seconds.** The top line says it again every 40 seconds, and a red line under your role at the top of the screen says INFECTED and where to go for as long as it is true. If you leave early the top line tells you to go back. When you are cured it says CURED. You are never frozen or moved.
- **If you are the rodent**, the top line tells you when someone you bit has collapsed, shows symptoms or was cured.
- **People talk.** Some of the people who spot the Spicy Rodent say a line in a speech bubble, for example "Oh my god, it's one of those squirrels again!". Not everyone speaks at once, and you see a bubble only from about 30 metres or closer.
- Nothing to press for any of this: bite someone and follow them.

## What you should see
- No screen is ever blank or silent. While something loads, a line says what is loading.
- If something fails, the line turns red or says "press F9". F9 opens the Developer Console. Open its Server tab, take a screenshot of the red lines and send it to me.
- Shift is always sprint. If you have turned Shift Lock on in your Roblox settings, this game switches it off.
- Typing in the chat never moves you or triggers a key.

## Not working yet (please tell me what you notice)
- **The bite-to-hospital sequence has never been seen on a screen.** Its rules are tested without one. Please look at: the speech bubbles, the red eyes, a collapsed person sitting on the ground (they may hover or sink a little), the patient disappearing when loaded, and the patients sitting on the cots in the hospital wards. There is **no siren**: the ambulance is silent apart from its flashing lights.
- **Two shop workers beyond the river** have no road and no way on foot to the hospital. If they are bitten the ambulance stops at the nearest road and they are taken in without the paramedic's walk (they disappear where they sit), and when cured they reappear at their shop.
- **In a rush of bites** (more than three people on the ground at once) someone can wait a few minutes for one of the three ambulances. Anyone still waiting after two and a half minutes with no ambulance on its way is taken in without one.
- **Cars are see-through to you.** AI cars are drawn on your computer only. Your patrol car drives through them, and they only hurt squirrels and the rodent.
- **Nobody has played this live yet.** Everything has been tested on the server without a screen. If something feels wrong, tell me what you pressed and what happened.
- **The day stays fixed** at a sunny afternoon. The day/night clock comes in the next wave.
- **The town is grey boxes.** Real art comes later.
- **One Spicy Rodent per server.** If a second player picks it, they are told someone else already is.
