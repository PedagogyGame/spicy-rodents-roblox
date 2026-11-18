# Brief: model the three pinball machines as GLB files

You are making the 3D models for three pinball machines in a Roblox game called "Spicy Rodent". They stand in a bowling alley's games room. The game already plays pinball on them. Its ball physics is exact flat geometry in code, so your models are what players **see**. Anything the ball touches must therefore sit exactly where the game's physics has it, or the ball will look as if it passes through walls.

This pack has all you need:

| File | What it is |
|---|---|
| `BRIEF_FOR_CHATGPT.md` | This brief |
| `pinball_data.json` | Every part of every machine, in metres, taken from the game's code. This is the only source of truth for sizes and places. |
| `reference/*.glb` | A plain blockout of every file you will make, already correct in placement, names, origins and scale. **Start each model from its reference file.** |
| `check_glb.py` | The checker. Run `python3 check_glb.py <your output folder>` and fix every FAIL. Needs `pip install trimesh scipy networkx pillow`. |
| `images/` | Drawings of each playfield from above with every part numbered (`*_plan.png`), the cabinet (`cabinet.png`), the shared parts (`parts.png`) and how the machines look in the game today (`ingame_*.jpg`) |

## What to deliver

24 files: the 21 GLB models below and 3 PNG pictures, all passing `check_glb.py`. Hand them back in one zip, with the checker's output.

## Frame, units and names (strict)

- **Format:** glTF 2.0 binary (`.glb`), **metres**, **Y up**. The game imports in metres and counts 1 Roblox stud as 0.28 m.
- **Playfield files:** the origin is the playfield's **front-left corner on its surface**, where the player stands at the front.
  - +X runs to the player's right.
  - −Z runs up the table, away from the player.
  - Y is height above the playfield surface.
  - Model the playfield **flat**; the game tilts it 6.9°.
- **Cabinet file:** the origin is on the floor under the middle of the machine. +Z is toward the player and Y is up. The tilt is already in the cabinet's numbers.
- **Objects:** every object in a reference file must exist in yours, with exactly the same name and its origin (node position) in the same place, within 1 mm.
  - The game finds parts by these names and moves or lights them about their origins.
  - Do not rename, merge or split them.
  - Any extra decorative object must have a name starting with `Deco_`. Use at most 10 per file, and add detail to the existing objects where you can instead.
- **In Blender:**
  - Import the reference with File › Import › glTF.
  - Blender shows the table running along its +Y axis, which is correct; leave the objects' origins where they are.
  - Export with File › Export › glTF 2.0 › glTF Binary, "+Y Up" on, Apply Modifiers on, and no cameras, lights or animation.
  - Apply scale (Ctrl+A) before export, but **not** location, or the origins move.

## What must not change, and what is yours

- **Fixed: anything the ball touches.** Its outline seen from above must match the reference within 3 mm, and it must be no lower than the reference. The checker measures this. These parts are:
  - the guides and posts;
  - the slingshots;
  - the targets and the spinner;
  - the flipper;
  - the ramps' tracks;
  - the board.
- **Height:** you may make these parts taller and give them detail (bevels, screws, rubber rings, wire guides with brackets). Nothing on the playfield may reach the glass at 0.14 m, except the ramps.
- **Free design, within looser bounds:** the cabinet, the pop bumpers (add skirts), the plunger, the gate, the apron, and decoration on top of the guides.
- **Ramps:** they may get side walls and an entrance flap that meets the playfield. Keep the track's centre line and heights.

## Keep it light (the game runs on phones)

- **Triangle budgets:** stay under each file's budget; the checker enforces them. Each machine shows about 20,000 triangles in all.
  - Flipper: 600
  - Pop bumper: 1,500
  - Plunger: 400
  - Gate: 200
  - Spinner: 300
  - Cabinet: 5,000
  - Board and apron: 300
  - Guides: 6,000
  - Slingshots: 800
  - Targets: 1,200
  - Space's ramps: 5,000; THE WIRE: 3,000
  - Pod hoods: 600
- **Materials:** one material per object. Plain base colours everywhere, using the colours in `pinball_data.json` → `machines.<name>.colours`.
  - Only three things get a picture texture: the `Board` (the playfield art), the `Apron` (the title) and the backglass PNGs.
  - Textures may be at most 1024 × 1024.
  - No normal, roughness or occlusion maps.
- **No transparency** except the `Glass` and the ramp tracks. Use alpha blend, with the glass about 95% clear.
- **Do not model:** collision shapes, the balls, the lamp inserts, the rollover switches, lights or anything under the board. The game makes or handles all of these.

## The files

### Shared parts (one each, used on all three machines)

| File | Objects | Notes |
|---|---|---|
| `Pinball_Flipper.glb` | `Bat`, `Tip`, `Pin` | Origin on the pivot pin, half-way up the flipper. It points along +X; the game mirrors it for the right flipper and swings it. Classic shape: a tapered white rubber bat with a red tip and a dark pin. Sizes: `shared.Flipper`. |
| `Pinball_PopBumper.glb` | `Body`, `Cap` | Origin at the centre of the base. The game lights the cap, so it stays separate. Made at radius 0.0336; the game scales it per machine. Add a classic skirt and ring. |
| `Pinball_Plunger.glb` | `Rod`, `Knob` | The knob is at the origin and the rod runs up the table (−Z). The game slides the whole plunger back toward the player. |
| `Pinball_Gate.glb` | `Flap` | Origin on the hinge at the top of the flap. A thin wire gate. |

### The cabinet (one model; the game colours it per machine)

| File | Objects | Notes |
|---|---|---|
| `Pinball_Cabinet.glb` | `Body`, `SideWall_L`, `SideWall_R`, `FrontWall`, `BackWall`, `LockdownBar`, `Glass`, `FlipperButton_L`, `FlipperButton_R`, `CoinDoor`, `Leg_FL`, `Leg_FR`, `Leg_BL`, `Leg_BR`, `Backbox`, `Backglass`, `LightStrip` | A classic pinball cabinet. Exact corners: `cabinet.parts_as_8_corners`.<br>• The back legs are longer; that is the slope.<br>• The `Backglass` is a flat front face; the game writes the score on it.<br>• The coin door shows FREE PLAY, with no coin slot artwork.<br>• Leave the body, trim and legs as plain separate colours so each machine can recolour them. |

### Each machine (prefix `Acorn_`, `Rodent_`, `Space_`)

| File | Objects | Notes |
|---|---|---|
| `<M>_Playfield.glb` | `Board`, `Apron` | The board carries the playfield art as one texture (see below). The apron carries the machine's title. |
| `<M>_Guides.glb` | `Guides_Wood`, `Guides_Metal`, `Guides_Plastic` (Rodent and Space only), `Guides_Rubber` (Acorn only), `Posts_Metal`, `Posts_Rubber` | Everything that never moves, merged by material, which draws faster:<br>• `Guides_Wood`: wooden side rails and arch;<br>• `Guides_Metal`: chrome wire guides;<br>• `Guides_Plastic`: coloured plastic guides;<br>• `Guides_Rubber`: rubber bands;<br>• `Posts_Metal` and `Posts_Rubber`: posts with rubber rings.<br>The walls' centre lines, thicknesses and heights are in `machines.<name>.walls`; the posts are in `.posts`. |
| `<M>_Slingshots.glb` | `SlingBody1`, `Sling1`, `SlingBody2`, `Sling2` | A plastic triangle body, plus the white kicking rubber on its inner face. The rubber stays separate because it flashes. |
| `<M>_Targets.glb` | Acorn: `Drop1`–`Drop5`, `Standup6`, `Standup7`<br>Rodent: `Standup1`–`Standup5`<br>Space: `Standup1`–`Standup4` | Origin at the middle of each target's bottom edge.<br>• Drop targets sink straight down into the board when hit.<br>• Standups are fixed faces; add a small bracket behind each.<br>• Colour: `colours.target`. |
| `Acorn_Spinner.glb` | `Spinner1` | A flat chrome flag; its origin is on its spin axis, which runs level across the lane. Add a wire bracket as `Deco_`. |
| `Rodent_Wire.glb` | `Ramp_wire` | "THE WIRE": a long clear-orange ramp. Path: `machines.rodent.ramps`. |
| `Space_Ramps.glb` | `Ramp_ramp_l`, `Ramp_ramp_r` | Two ice-blue clear ramps. Paths: `machines.space.ramps`. |
| `Space_PodHoods.glb` | `PodHood1`, `PodHood2` | **New part, with no reference.**<br>• One low hood on the upper half of the rim of each lock-pod hole: `machines.space.holes`, ids `pod_1` and `pod_2`.<br>• It stands 0 to 6 mm high, so a ball coming down the table rolls over it, and one going up drops into the hole.<br>• A chrome or blue-plastic lip. |

### Pictures

- **Playfield art:** one texture on each `Board`, **486 × 1024** pixels. The top of the image is the back of the table.
  - The board runs from x 0 to 0.672 and from z +0.0448 (the front edge) to z −1.372 (the back).
  - Paint each machine's words where `machines.<name>.painted_words` puts them: centres and sizes in metres, in the playfield frame.
  - Leave a round, slightly lighter insert ring at each lamp centre in `.lamps`, at the given radius. The game draws the lit lamp on top.
  - Show the lanes' arrows as you see fit.
  - The background colour is `colours.field`.
- **Backglass art:** `<M>_Backglass.png`, **854 × 1024**, for the backbox face, 0.689 m wide × 0.826 m tall. The game writes its own text over five bands (`cabinet.backglass_text_bands_from_top`, as fractions of the height), so keep those bands dark and calm. The emblem for each:
  - Acorn: an autumn sun over an oak;
  - Rodent: a heat glow rising;
  - Space: a ringed planet.

## The three machines

- **ACORN ATTACK:** a gentle 1960s electro-mechanical table.
  - Walnut cabinet, brass trim, tan playfield, amber plastics, rust-red bumpers.
  - Story: a squirrel fills its hoard with acorns before winter.
  - Painted words include THE HOARD, the letters A C O R N, OAK, SPIN, and FILL THE HOARD BEFORE WINTER.
- **SPICY RODENT:** a fast, modern table.
  - Near-black cabinet, red trim, deep red playfield, orange plastics, yellow bumpers.
  - Story: a rodent gets hotter and hotter: CALM, FERAL, RABID, SUPER.
  - Words include THE WIRE, THE BITE, HOT LANE, CLIMB TO SUPER and the letters S P I C Y.
  - THE BITE is a kick-out hole inside a metal horseshoe; it is part of `Guides_Metal`.
- **SPACE SQUIRREL:** a flowing space table.
  - Deep blue cabinet, silver trim, navy playfield, ice-blue plastics, violet bumpers, green targets.
  - Story: fuel the rocket (F U E L), lock two balls, countdown, LIFTOFF.
  - Words include ORBIT, RAMP, LOCK, COMBO, JACKPOT and COUNTDOWN TO MULTIBALL.

## Content rules for the art (strict)

- The game is rated mild, so there is no gambling imagery: no coins, money, dollar signs, dice, cards, "INSERT COIN" or betting. No swearing, no gore.
- No red cross on white (it is a protected emblem).
- The rodent character is never green.
- Original art only: no real brands, logos or existing pinball machines' artwork.

## Order of work

1. Copy the `reference/` folder and work on each file there.
2. Shape each file, keeping names, origins and outlines.
3. Run `python3 check_glb.py <folder>` after each file, and fix every FAIL before moving on.
4. Make the pod hoods and the PNGs last.
5. Return all 24 files in one zip with the final checker output, which should say `24 of 24 files pass`.
