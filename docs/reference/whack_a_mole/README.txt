WHACK-A-MOLE
Editable Blender cabinet, demonstration animation, and optional play modes

FILES

Whack_A_Mole.blend
    Editable Blender project with the cabinet, five separate animated moles,
    mallet, lighting, camera, and an eight-second demonstration.

Whack_A_Mole.glb
    Exported 3D game asset. This is not a finished Roblox game or a Roblox
    gameplay script; gameplay must be implemented in the destination engine.

Play_Whack_A_Mole.html
    Standalone browser game that can be opened locally and played offline.

Preview.png
    Still image of the cabinet.

source/build_whack_a_mole.py
    Blender Python source used to build the project. Edit this source to change
    how the model and demonstration are generated.

source/play_whack_a_mole.py
    Optional interactive Blender play script, also provided as editable text
    inside the Blender project.

VIEW THE BLENDER DEMONSTRATION

1. Extract the files, then open Whack_A_Mole.blend in Blender.
2. Click the Play button in the Timeline to watch the eight-second animation.
3. Click Pause to stop, or move the Timeline playhead to inspect a frame.

The Timeline animation is a demonstration. It does not respond to hits until
the optional interactive play script is run.

PLAY INSIDE BLENDER (OPTIONAL)

1. Open the Scripting workspace.
2. In the Text Editor, select play_whack_a_mole.py. If it is not selected or
   visible, open source/play_whack_a_mole.py using the Text Editor's Open command.
3. Click Run Script in the Text Editor.
4. Move the pointer over a 3D Viewport, press N, open the Arcade tab, and click
   Start 45-second round. Alternatively, press F3 and run Play Whack a Mole,
   or use the 3D Viewport's View > Play Whack a Mole menu item.
5. Press 1 through 5 to strike the five mole positions. Press Esc to stop.

The embedded script does NOT auto-run when you open the project. Running the
script enables the interactive command; starting that command begins play.

PLAY IN A BROWSER

1. Open Play_Whack_A_Mole.html in a web browser.
2. Use the on-page start control to begin a 45-second round.
3. Click or tap raised moles, or use keys 1-5: +10 points per hit and -2 points
   per miss, with a zero floor. Escape pauses. Sound is off until enabled.

This browser version is separate from the Blender Timeline demonstration and
does not require Blender or an internet connection.

EDIT THE ASSET

Use Whack_A_Mole.blend to change the cabinet, materials, mole objects, mallet,
lighting, camera, or animation. Use Whack_A_Mole.glb when importing the asset
into another compatible 3D application or game project. The Python build
source uses Blender's Python environment rather than ordinary system Python.

COMPATIBILITY AND EXPORT

Created and checked with Blender 4.3.2. The GLB contains the five independently
named mole roots and one combined demonstration animation. Its materials use
portable base colors and metallic/roughness settings; Blender's very fine
procedural wood bump is retained in the .blend rather than baked into the GLB.
The studio floor, lights, and camera are excluded from the GLB.
