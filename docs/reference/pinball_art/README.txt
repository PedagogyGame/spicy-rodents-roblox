SPICY RODENT — FINISHED PINBALL ASSETS
Acorn Attack • Spicy Rodent • Space Squirrel

CONTENTS
The archive root contains the 24 requested deliverables: 21 GLB models and
3 backglass PNGs, using the exact filenames from BRIEF_FOR_CHATGPT.md.
CHECK_RESULTS.txt is the unmodified supplied checker's complete final output.
QUALITY_REPORT.txt and asset_manifest.json record the additional audit.
Previews/ contains rendered views of the delivered geometry and artwork.
Source_Project/ contains the 21 editable Blender asset files, the original
artwork, embedded-texture source PNGs, generators and supplied reference inputs.

USING THE MODELS
These visual assets are made for the existing Spicy Rodent pinball game.
Import in METRES (1 Roblox stud = 0.28 m). Preserve object names, separate
objects and pivots; the game uses them to animate and light individual parts.

Playfield asset coordinates:
  origin = the front-left corner of the playfield surface;
  +X = player's right; +Y = up; -Z = up the table away from the player.
  The playfield models are flat. The existing game applies its 6.87549° tilt.

Cabinet coordinates:
  origin = floor beneath the machine's middle; +Z = toward the player.
  The cabinet geometry already contains its required slope.

Shared parts:
  The cabinet, flipper, pop bumper, plunger and gate are supplied once each.
  The game places/recolours these parts per machine, using pinball_data.json.
  Body and Cap remain separate on the bumper. Flipper pivots and all target
  pivots are retained. Glass is alpha blend at 5% opacity; ramp tracks are
  transparent tinted plastic. Other objects are opaque.

ARTWORK
Board textures are embedded inside the GLBs at exactly 486 x 1024 pixels.
Apron title textures are also embedded. The three separate backglass PNGs are
854 x 1024 pixels and reserve the five specified bands for the game's live text.
The supplied reference coordinates determine every painted label and lamp ring.
Original theme illustrations were generated for this pack. Typography and
coordinate-sensitive printing were composed precisely from pinball_data.json.

VALIDATION
The original check_glb.py reports: 24 of 24 files pass.
The independent audit additionally verifies materials, exact image dimensions,
embedded resources, transparency, decorative-object limits, transforms and
sampled reference ramp surfaces. The staged preview renders were inspected
for geometry joins, UV orientation, readability and visible surface artifacts.

To run the supplied checker from this extracted folder:
  python3 -m pip install trimesh scipy networkx pillow
  python3 Source_Project/work/Pinball_ChatGPT_Pack/check_glb.py .

To run the extra audit:
  python3 Source_Project/build/source/audit_assets.py . --pack Source_Project/work/Pinball_ChatGPT_Pack

EDITABLE SOURCES
Open any of the 21 files in Source_Project/build/source/blend/ in Blender.
Textures are packed into the textured .blend files. Per-asset GLBs exclude
cameras, lights and animation. The separate Pinball_Preview_Assembly.blend is
an editable presentation/inspection scene with studio staging; use the 21
individual GLBs at the archive root as the game assets.

The generation scripts retain the Source_Project directory layout so they
can find the original reference data. Blender is required for the geometry
scripts. The hardware generator uses PINBALL_CHECK_PYTHON when supplied,
otherwise python3, for the external trimesh checker.

VISUAL VERIFICATION SCOPE
The preview pictures are Blender renders of the exported assets assembled
using the supplied coordinates. Validation covers the files and those supplied
specifications; runtime Roblox integration remains with the existing game.

BACKUP
Pinball_Finished_Models_BACKUP.zip is a byte-for-byte copy of the main archive.
Both archives were reopened and CRC-tested after writing.
