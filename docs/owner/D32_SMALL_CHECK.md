# D32 small fixes: what to check

You played 1.7 and asked for three small things. Here is what changed and how to check each one in Studio or in a test server.

## 1. The scooter and the moped: no more flash when you steer

**What was wrong.** These two lean into a turn. While they leaned, the bottom corner of the vehicle's invisible box was pushed a little way into the road every frame. The physics pushed it back out and tipped it upright, and then the next frame pushed it in again. The first-person camera was fixed to the rider's eyes, high above that box, so it shook and tilted with every frame of it. Each tap of A or D also tilted the whole view by up to 28 degrees and swung your eyes about 1.7 studs sideways. That is the flash across the screen.

**What I changed.**
- While a vehicle leans, it is lifted just enough that its box never goes into the road. The lift is at most 0.15 studs, so you will not notice it.
- In first person the view now leans only a little (30 % of the vehicle's lean). It eases into the lean, so a quick tap of A or D no longer jerks the screen.
- In third person (V), if a wall behind you pulls the camera in close, your rider fades out. The camera no longer ends up inside your own body.
- The bicycle uses the same code, so it gets the same fix.

**Please check:**
1. Get on a scooter (E). You start in first person. Ride fast and tap A and D quickly. Then hold A, then hold D. Weave around.
   - The screen should never flash or jump.
   - The view should tilt gently into each turn.
2. Do the same on a moped.
3. Press V for the view from behind. Ride with your back close to a wall or a hedge.
   - Your rider should fade out.
   - The screen should never fill with the inside of the rider.
4. Try the bicycle once too.

## 2. The 1940s lounge (The Gilded Acorn): you can always get up

**What was wrong.** The lounge seats are fixed in place. On a fixed seat, the normal jump does not reliably free you. Pressing R again was worse: it sat you on the next stool along. So you could end up stuck.

**What I changed.**
- The server now gets you up and stands you in a clear spot next to your seat:
  - behind a bar stool, club chair or armchair;
  - at the open end of a booth.
- Any of these stands you up:
  - **R** again;
  - **Space**;
  - a step with W, A, S or D;
  - the gamepad's **A** or **Y**.
- When you sit down, a short message tells you how to get up.
- A **STAND** button appears while you are seated. On a phone or tablet, tap it.
- Getting up never drops you straight back into a seat. A computer test checks that every one of the 33 seats lets you out onto floor you can walk to the door from.

**Other seats I checked:**
- **The lawn chair:** it had the same problem, so it uses the same fix. You stand up in front of it.
- **Cars, carts, bikes, the golf cart's passenger seat, the police drone:** you get out with E (the gamepad's Y). A phone or tablet has no E key. Until now it only had a GET OFF button on the shared scooters, mopeds and golf carts. That button now shows in every vehicle and in the passenger seat. On the drone it says LAND.
- **The sky lift:** unchanged. The cabin always takes you to the platform.
- **The Lookout's dining chairs and the games room:** nobody can sit on them, so there is nothing to get stuck in.

**Please check:**
1. In the lounge, sit on a bar stool with R. Press R again.
   - You should stand behind the stool.
   - You should **not** move onto the next stool.
2. Sit again and press Space. Then sit again and take a step with W.
3. Try a booth, a club chair and an armchair by the fire.
   - Each time you should stand somewhere clear and be able to walk to the door.
4. With a gamepad, sit and press Y, then sit and press A.
5. On a phone (or Studio's device emulator), sit and tap STAND.
6. Put down a lawn chair (you sit in it automatically), then press Space.
7. On a phone, drive a police car or a pickup.
   - You should see GET OFF and it should work.
   - On the drone you should see LAND.

## 3. The "CORNER SHOPS" building is now "ELM ROW OFFICES"

This is the two-storey building near the alley's AIR HOCKEY - DARTS sign and The Gilded Acorn. Its sign now reads **ELM ROW OFFICES**. That is a quiet, ordinary name, and it does not suggest a shop that isn't there. Pepper's Corner Store stays the only real shop.

I changed the name everywhere the game keeps it. Nothing else in the game, including speech, errands, the map and the tests, used the old name. The baked town has the new sign.

**Please check:** walk past the building at night. The sign should read ELM ROW OFFICES.

## What these changes cost on phones

- **Camera:**
  - While riding in first person, a few extra sums each frame. Less work than before overall, because the hidden rider's parts are now only written when they change.
  - In the view from behind, one distance check per frame.
- **Seats:**
  - One small button, hidden unless you are seated.
  - One key listener.
  - On the server, one message per stand-up, at most a few a second per player.
- **The sign:** no new parts, no new triangles.
