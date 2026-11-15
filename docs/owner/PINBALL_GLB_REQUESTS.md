# Pinball: the GLB files to make in Blender

There are 24 files in all, 21 GLB models and 3 backglass pictures:
- 10 shared parts, made once and used on all three machines;
- 1 cabinet;
- 13 for the three machines: each has its playfield, guides and backglass picture, plus ACORN ATTACK's plastics, SPICY RODENT's ramp and SPACE SQUIRREL's ramps and pod hoods.

**How to make every file:**
- **Units and axes:** metres, Y up. Roblox counts 1 stud as 0.28 m, and you import with Scale Unit = Meter.
- **Size:** each size below is given in metres, with studs in brackets.
- **Placement:** the blockouts in `docs/owner/pinball_blender/blender/` hold every part at its exact place and footprint. Model over them, and keep each footprint wherever the ball touches.
- **Materials:** plain colours, or one texture per mesh. No layered material sets (SurfaceAppearance).
- **Moving parts:** each must be a separate object with its origin on its pivot, named as listed.
- **Not needed as GLB:** lamp inserts, rollover switches and the balls. The game makes these.

## Shared parts (one each)

| # | File | Contents (object names) | Size | Origin |
|---|---|---|---|---|
| 1 | `Pinball_Flipper.glb` | `Bat`, `Tip` (red), `Pin` | pin to tip-centre 0.0924 (0.33); radius 0.0126 at the pin, 0.0078 at the tip; 0.0196 tall (0.07) | Centre of the pivot pin, 0.0098 (0.035) above the board. It points along +X and is mirrored for the right flipper. It swings from −30° to +38°. |
| 2 | `Pinball_PopBumper.glb` | `Body`, `Cap` (separate; the cap lights up) | body radius 0.0336 (0.12), 0.0448 tall (0.16); cap radius 0.0286, 0.0112 thick, on top. ACORN uses it as made; SPICY RODENT scales it to 0.115 and SPACE SQUIRREL to 0.11. Add a skirt if you like. | Centre of the base |
| 3 | `Pinball_Post_Rubber.glb` | `Post` | radius 0.0062 (0.022), 0.0308 tall (0.11) | Centre of the base |
| 4 | `Pinball_Post_Metal.glb` | `Post` | radius 0.0062 (0.022), 0.0392 tall (0.14) | Centre of the base |
| 5 | `Pinball_DropTarget.glb` | `Target` | about 0.028 wide × 0.0084 thick × 0.0336 tall (0.10 × 0.03 × 0.12). It slides 0.0448 (0.16) down into the board. | Centre of the bottom edge |
| 6 | `Pinball_Standup.glb` | `Target`, `Bracket` | face 0.0084 thick × 0.0336 tall; width to suit (the targets are 0.03 to 0.06 wide) | Centre of the bottom edge of the face |
| 7 | `Pinball_Spinner.glb` | `Flag` (spins), `Bracket` | flag 0.0742 wide (0.265, the lane) × 0.028 tall (0.10); the axis is level across the lane, 0.028 (0.10) up | The flag's origin is on its axis |
| 8 | `Pinball_Gate.glb` | `Flap` (swings), `Bracket` | flap 0.0588 long (0.21) × 0.014 tall (0.05) × 0.0034 thick; the hinge is 0.028 (0.10) up | The flap's origin is on the hinge |
| 9 | `Pinball_Plunger.glb` | `Rod`, `Knob` (red), as one group | rod 0.0098 square, 0.21 long (0.75); knob 0.0308 × 0.0308 × 0.028. It pulls back 0.0896 (0.32). | Front face of the knob |
| 10 | `Pinball_Slingshot.glb` | `Body` (plastic), `Rubber` (separate; it flashes), `Post` ×3 | Triangle about 0.07 × 0.12 × 0.028 tall. Each table's slingshot differs slightly, so match `Slingshot_L_body` in each blockout and mirror it for the right. | Its lower inner corner |

## The cabinet (one, coloured three ways)

| # | File | Contents (object names) | Size | Origin |
|---|---|---|---|---|
| 11 | `Pinball_Cabinet.glb` | `Body`, `SideWall_L`, `SideWall_R`, `FrontWall`, `BackWall`, `LockdownBar`, `Glass`, `Leg` ×4, `CoinDoor`, `FlipperButton_L`, `FlipperButton_R`, `Backbox`, `Backglass`, `LightStrip` | Overall 0.756 wide × 2.156 tall × about 1.48 deep (2.7 × 7.7 × 5.3). Body and glass tilt 6.9° toward the player. Glass 0.14 (0.5) above the playfield. Front legs 0.689 (2.46) and back legs 0.846 (3.02), all 0.0616 square. Backbox 0.756 × 0.91 × 0.168 (2.7 × 3.25 × 0.6), its foot 1.246 (4.45) off the floor. Coin door 0.196 × 0.154. | The floor, under the middle of the machine. Match `cabinet_body_blockout.obj`. |

Make the backglass a flat front face: the game writes the score on it. Use one material slot each for the body, the trim and the light strip, so the three machines can take their own colours:
- ACORN ATTACK: walnut and brass;
- SPICY RODENT: black and red;
- SPACE SQUIRREL: blue and silver.

## Per machine (four files each)

The origin of every file below is the playfield's front-left corner, on its surface, the same as the blockout. Model these flat; the game tilts them.

**ACORN ATTACK** (blockout `acorn_playfield_blockout.obj`)

| # | File | Contents |
|---|---|---|
| 12 | `Acorn_Playfield.glb` | `Board`, 0.672 × 1.417 × 0.0168 (2.4 × 5.06 × 0.06), with the painted art as its texture, and `Apron`, 0.42 × 0.106, with the title |
| 13 | `Acorn_Guides.glb` | Every static wall at its blockout footprint:<br>• the wooden side rails and arch;<br>• the shooter lane wall;<br>• the wire guides of the three top lanes;<br>• the inlane and outlane guides and dividers;<br>• the curved rail guides;<br>• the spinner lane guide;<br>• the A-C-O-R-N bank's wooden wall and rubber;<br>• the OAK targets' wedge backs;<br>• the rebound rubber at the arch. |
| 14 | `Acorn_Plastics.glb` | Decorative plastics above the ball, between 0.056 and 0.126 (0.2 to 0.45) above the board. These are free design. |
| 15 | `Acorn_Backglass.png` | Art for the backglass, 0.689 × 0.826 (2.46 × 2.95), in portrait: an autumn sun over an oak. Keep the middle band plain, where the score shows. |

**SPICY RODENT** (blockout `rodent_playfield_blockout.obj`)

| # | File | Contents |
|---|---|---|
| 16 | `Rodent_Playfield.glb` | `Board` and `Apron` as above, with its own art |
| 17 | `Rodent_Guides.glb` | Every static wall at its blockout footprint:<br>• the rails and arch;<br>• the shooter lane wall;<br>• the inlane and outlane guides;<br>• the hot lane guide;<br>• the S-P-I-C-Y targets' backs, including the pointed back of I;<br>• THE BITE's metal horseshoe (radius 0.0462, 0.165), with its hole, at the blockout's `Hole_bite`. |
| 18 | `Rodent_Wire.glb` | THE WIRE ramp, following `Ramp_wire` in the blockout:<br>• the track is 0.0518 (0.185) wide and rises to 0.084 (0.3);<br>• side walls and an entrance flap are yours to add;<br>• keep the track's centre line and heights. |
| 19 | `Rodent_Backglass.png` | A heat glow rising, same size as above |

**SPACE SQUIRREL** (blockout `space_playfield_blockout.obj`)

| # | File | Contents |
|---|---|---|
| 20 | `Space_Playfield.glb` | `Board` and `Apron` as above, with its own art |
| 21 | `Space_Guides.glb` | Every static wall at its blockout footprint:<br>• the rails and arch;<br>• the shooter lane wall;<br>• the orbit's curved inner guide, with the docking gap;<br>• the ramp-mouth bodies;<br>• the inlane and outlane guides;<br>• the curved rail guides. |
| 22 | `Space_Ramps.glb` | `RampL` and `RampR`, following `Ramp_ramp_l` and `Ramp_ramp_r`: track 0.0518 wide, rising to 0.084 |
| 23 | `Space_PodHoods.glb` | Two hoods, a new part that the game does not have yet:<br>• one over each lock-pod hole (`Hole_pod_1`, `Hole_pod_2`, radius 0.041);<br>• each hood covers the side toward the top of the table, so a ball going up drops in and one coming down rides over;<br>• each is no taller than 0.035. |
| 24 | `Space_Backglass.png` | A ringed planet, same size as above |
