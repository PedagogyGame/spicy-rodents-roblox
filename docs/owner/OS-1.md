> **CANCELLED 2026-11-09 (owner feedback).** The owner tried Part C: the grey-box test town was confusing without explanation and the drone did not respond (the server writes 7 s+ of hill terrain before creating the drone remotes, with no on-screen "please wait", and F is ignored until then). Decision: the owner does no abstract spike sessions. The possession feel (S2), art-import visuals (S8) and drone far view (S11) are checked in the FIRST RUNNABLE BUILD playtest instead, which must have on-screen instructions and loading feedback for every test. Lesson for every owner-facing build: show what the player is looking at and what to press, show progress while anything loads, and never let input do nothing silently.

# OS-1: one owner session in three parts (about 42 minutes)

For Ben, on a Mac. Three parts, any order once Claude says each is ready: **A** possession test in
Studio (about 20 min), **B** one test-rig import into the Art Inbox (about 12 min), **C** fly the
test drone in the Roblox app (about 10 min, only after Claude has published the test town).
Tick each box as you go and send Claude the filled-in page (or just the numbers and any box you
could not tick). Nothing here can break the game: the test places are throwaways.
Studio menus move between versions; if a label differs slightly, pick the closest one.

## Before the session (Claude does this, not you)

- [ ] Claude saves the possession test place (`build/s2.rbxl`) as the newest version of the **CI**
      place and tells you "OS-1a ready" (today: CI version 12).
- [ ] Claude tells you the name and download link of `squirrel_test_rig.fbx (in the repo at docs/owner/files/, also sent to you in chat)` for Part B.
- [ ] For Part C: Claude asks you first, publishes the test town to the main place, then tells you
      "OS-1c ready" with the experience link.

---

## Part A: possession test (OS-1a, Studio, about 20 minutes)

### Open the test place (3 min)
1. In your web browser go to **create.roblox.com** and sign in.
2. Click **Creations** (top). Click **Spicy Rodent**.
3. In the left menu click **Places**. Click **CI**.
4. Click **Edit in Studio** (top right). Studio opens the CI place. If Studio asks which version, pick
   the newest.
5. Turn on simulated lag: in Studio's top menu click **File -> Studio Settings** (on some Macs:
   **Roblox Studio -> Settings**). Click **Network** on the left. Set **Incoming Replication Lag** to
   **0.15**. Close the settings window.

### Start two test players (1 min)
6. Click the **Test** tab at the top.
7. In the **Clients and Servers** area, set the players box to **2 Players**. Click **Start**.
8. Three windows open: **Server**, **Player1**, **Player2**. Put Player1 and Player2 side by side.
   Each shows a dark panel at the top left titled "S2 possession test".

### The checks (Player1's window unless a step says otherwise) (14 min)
9. Click inside **Player1**. You are already a person walking on the grey square.
   - [ ] **Box 1. Take a walking person.** The camera sits behind a person; the person kept walking
         when you took over: no stiff "T" pose, no freeze, no jump. Press **W** and steer with
         **A/D**: the person obeys straight away.
         Write down from the panel: Handoff gap ____ st   Input -> move ____ ms
10. Click **2. Take a running squirrel** on the panel.
    - [ ] **Box 2. Take a running squirrel.** The camera moves to a small squirrel that keeps
          running; you can steer it with **W/A/S/D** (hold **Shift** to sprint). The squirrel
          does not jump or slide backwards when you take it.
          Write down: Handoff gap ____ st   Request -> control ____ ms   Input -> move ____ ms
    - [ ] **Leg swing (S7 check).** While it runs: the four legs swing forward and back along the
          body (the left legs are red), the tail waves up and down, the spine rocks; nothing swings
          sideways or spins.
11. Repeat steps 9-10 a few times with buttons **1** and **2** (about 10 takeovers each, 3 minutes).
    Note the biggest gap you see: person ____ st, squirrel ____ st.
12. Click **4. Release (back to AI)**.
    - [ ] **Box 3. Release.** The camera lifts to a view of the square; the body you left carries on
          walking or running by itself at once. Panel: AI resumed after release ____ ms.
13. Click **1** (you get a person), then **3. Swap (person <-> squirrel)**, then **3** again.
    - [ ] **Box 4. Swap.** Each click moves you straight from the person to the nearest squirrel and
          back; the one you left carries on by itself.
14. Look at **Player2's window** while you click **1**, **2** and **4** in Player1's window.
    - [ ] **Box 5. The other window.** In Player2's window, the body Player1 takes over keeps moving
          smoothly with its legs moving: no T-pose, no freeze, no snap of more than about a step.
15. Back in **Player1**, take a squirrel (button **2**). Press **/** to chat, type **hello**, press
    **Return**.
    - [ ] **Box 6a. Bubble.** A speech bubble with "hello" appears over the squirrel's head.
          If not: click **Bubble fallback: off** (it turns "on") and type hello again.
          The bubble showed: default ____ / only with the fallback ____ / never ____
16. Press **Esc**. Click **Reset Character**, then **Reset**.
    - [ ] **Box 6b. Reset.** You stay in the same squirrel (it may hop up a little); nothing dies,
          falls apart or reappears somewhere else. Panel: Resets routed = 1.
17. Close **Player2's** window (the red close button on that window).
    - [ ] **Leave.** In Player1's window, the body Player2 had starts walking again by itself within
          a moment.

### Finish (2 min)
18. In the main Studio window click **Stop** (Test tab).
19. Set **File -> Studio Settings -> Network -> Incoming Replication Lag** back to **0**.
20. Close Studio. When it asks to save, click **Don't Save**.

---

## Part B: one test-rig import (OS-1b, Studio, about 12 minutes)

1. Download `squirrel_test_rig.fbx (in the repo at docs/owner/files/, also sent to you in chat)` from the link Claude gave you into your **Downloads** folder.
2. In the browser: **create.roblox.com -> Creations -> Spicy Rodent -> Places -> Art Inbox ->
   Edit in Studio**.
3. In Studio: **File -> Import 3D**. Pick `squirrel_test_rig.fbx (in the repo at docs/owner/files/, also sent to you in chat)` in Downloads. Click **Open**.
4. In the import window, find **Rig Type** (under the rig settings) and choose **Custom**. Click
   **Import**. The squirrel appears in the 3D view and in the **Explorer** under Workspace.
   - [ ] The squirrel imported (one model in Workspace).
5. In the **Explorer**, right-click the squirrel model -> **Convert to Package...** -> keep the name ->
   owner: **you** (the experience owner) -> **Submit**.
6. **File -> Save to Roblox**. Wait for "saved".
   - [ ] Saved. Write down the model's name in the Explorer: ________

S8 picture checks (these are looked at, then thrown away):

7. **View -> Toolbox**. In the Toolbox click **Inventory** -> **My Models**. Click
   **"spicy-rodents pipeline test: S8a (safe to delete)"**: a log appears in the 3D view.
8. In the **Explorer**, expand the log and click **HollowLog**, expand it, click
   **SurfaceAppearance**. In **Properties**, look at **ColorMap**, **NormalMap**, **RoughnessMap**.
   - [ ] All three have a value (an `rbxassetid://` number), not empty.
   - [ ] Zoom in on the log: the bark shows ridges (not a flat painted look).
9. In the **Explorer**, expand your squirrel model, click the part named **Body**, expand it, click its
   **SurfaceAppearance**. In **Properties**, set **AlphaMode** to **TintMask** if it is not already.
10. **Test -> Play**. Then **View -> Command Bar**. Click into the command bar at the bottom, paste
    this line, put your squirrel's name (step 6) where it says NAME, press **Return**:
    `workspace.NAME.Body.SurfaceAppearance.Color = Color3.fromRGB(255, 120, 40)`
    - [ ] Only the main fur (Body) turns orange; the pattern (belly/markings) does not change.
11. **Test -> Stop**. Close Studio and click **Don't Save** (the import was saved in step 6; the log and
    the colour test should not be).

---

## Part C: fly the test drone (OS-1c, Roblox app, about 10 minutes)

**Changed 2026-11-09:** Claude's safety settings do not allow it to publish to your live place, so Part C runs **in Studio** instead of the Roblox app. The drone test town is saved as **CI place version 13**.

Studio route (use this):
1. create.roblox.com -> Creations -> Spicy Rodent -> Places -> **CI** -> **Edit in Studio** (newest version = the drone town).
2. **Test** tab -> **Play**. Then follow steps 2-5 below. Studio cannot show SLIM far-building shapes, so mark box 3 "n/a in Studio".
3. When done: Stop, close with **Don't Save**, and tell Claude "C done". Claude then re-saves the possession place for Part A.

(Optional, for the full check: in Studio with the drone town open, File -> Publish to Roblox As -> Spicy Rodent -> the **Spicy Rodent** place -> Overwrite. Then use the Roblox-app steps below. It is your private place, so only you can join. Publish your real game over it later.)

Roblox-app route (only if you published it yourself):

1. Open the link Claude gave you (the Spicy Rodent experience page) and click the green **Play**
   button. The Roblox app opens the test town. You stand on a small pad; wait about 10 seconds
   while the ground builds.
2. Press **F**: the camera jumps to a small drone above you; the box at the top left shows heights
   and distances. Fly: **W/A/S/D** (the way the camera faces), **Space** up, **Q** down, hold
   **Shift** to go fast. Drag with the right mouse button to look around.
3. Hold **Space** until "Height above ground" reads about **300**.
   - [ ] **Box 1. Centre.** Over the centre ("Centre: ... <- here"), look all round: the whole town
         is there as blocks and roads, with no missing blocks or holes.
4. Fly to each corner (the box shows the distance; "<- here" when you are there), keep about 300 up,
   and look outwards and back at the town.
   - [ ] **Box 2. Corners.** At NW, NE, SW and SE the town is complete and the hills beyond it are
         visible. Far hills: visible ____ / missing ____. No straight seam or cliff on the horizon.
   - [ ] **Box 3. Far buildings.** From a corner, buildings across the town still show as shapes
         (not vanishing or popping in only when close).
5. Press **N** (night). Wait a few seconds.
   - [ ] **Box 4. Night grid.** From 300 up, a grid of small lights traces the streets.
         Press **N** again for day.
6. Fly to **Off-road strip** (behind the ridge to the north) with **Shift + W**. When it says
   "<- here", check "Distance from your body" is more than 1,500.
   - [ ] **Box 5. Far from the body.** Tall orange posts stand on a brown strip around you, and the
         ground under the drone is there (not empty). Distance from your body: ______ st
7. Press **Esc -> Leave**.

---

## What to send Claude

The ticked boxes, the numbers you wrote down, and anything that looked wrong (a screenshot with
**Cmd + Shift + 4** helps). About 20 + 12 + 10 = 42 minutes in all.
