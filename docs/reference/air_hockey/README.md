# AER / 01

An original first-person air hockey game built with Blender and Unreal Engine 5.8.4.

## Play

**Portable:** open `AER_Play.html` in a current desktop browser. It contains the complete game code, renderer, geometry, and sound synthesis in one file. It works offline, without a server or downloads. WebGL 2 is required. Click **Take your position** to play. Three AI difficulty levels are available on the title screen.

**Unreal on this Mac:** run `Unreal/Play_AER.command`, or open `Unreal/AerHockey.uproject` and press Play. Press **Space** to begin the first serve. The native level and material are included. The Mac editor module was compiled against Unreal 5.8.4 on Apple Silicon. On another machine, let Unreal rebuild the module using a compatible C++ toolchain.

This delivery includes an editable Unreal source project. It is not a separately cooked standalone Unreal application. The HTML file is the immediately playable, portable game.

## Controls

| Control | Action |
| --- | --- |
| Mouse | Move your mallet across your half of the table |
| Space | Start / serve |
| Tab | Switch between Glacier and Ember first-person positions |
| V | Toggle first-person and overhead views |
| P / Escape | Pause / resume |
| R | Reset the match |
| M | Toggle sound in the portable game |
| WASD / arrows | Additional mallet controls in the portable game |
| Touch and drag | Move the mallet in the portable game |

The AI takes the opposite end. This is a single-player game, with either end selectable. First to seven wins. Goals reset the puck and serve toward the opponent from the conceding side. Mallets stay on their own halves. Move the mallet through the puck to strike it; holding the mallet still also blocks shots.

## Files

| File | Purpose |
| --- | --- |
| `AER_AirHockey.glb` | Self-contained glTF 2.0 model, materials, and two player cameras |
| `SourceArt/AER_AirHockey.blend` | Editable Blender scene, studio lighting, and render camera |
| `SourceArt/build_arena.py` | Reproducible procedural Blender modeling and export source |
| `AER_Play.html` | Complete, dependency-free playable game and source in one HTML file |
| `Portable/` | Readable renderer template, JavaScript physics, and HTML assembly script |
| `Unreal/AerHockey.uproject` | Native Unreal Engine project |
| `Unreal/Source/AerHockey/` | C++ game mode, arena, player pawn, camera, HUD, audio, physics |
| `Unreal/Content/AirHockey/` | Native Unreal level and parametric surface material |
| `Unreal/Content/Data/Arena.json` | Evaluated Blender geometry used by both game runtimes |
| `Tests/physics_tests.cpp` | Engine-independent C++ simulation checks |
| `AER_Hero.png` | Blender product render |
| `AER_Portable.jpg` | Portable game title-screen preview |
| `AER_Unreal.png` | Native Unreal first-person screenshot |
| `AER_Unreal_Overhead.png` | Native Unreal overhead screenshot |

The GLB has four named game pivots: `Table_Static`, `Mallet_Glacier`, `Mallet_Ember`, and `Puck_Dynamic`. The table is modeled in metres, Z up. The playable bed is at Z = 0.90 m; its interior is 1.24 × 2.34 m. Each goal is 0.44 m wide. Puck radius is 0.032 m; mallet radius is 0.064 m. The studio floor and lights are in the Blender source, outside the exported game-asset collection.

## Physics and implementation

The native game uses an engine-independent C++ simulation at 240 fixed steps per second. It resolves continuous swept-circle contacts against moving mallets and rounded goal posts, analytic rail contacts, restitution, speed limits, light air drag, and full-puck goal crossings. It does not depend on triangle-mesh collisions or Chaos rigid-body settings. The portable JavaScript simulation implements the same dimensions and rules.

Unreal renders the Blender geometry with ProceduralMeshComponent and a parametric material. Runtime positions convert metres to centimetres and reflect Blender X to Unreal X so printed graphics and mouse controls remain correctly oriented. Direct studio lights, ambient cubemap lighting, and screen-space reflections support these dynamic procedural meshes. No Lumen distance-field data is required.

## Rebuild

Use Unreal Engine **5.8** and Xcode on macOS, or Visual Studio with C++ tools on Windows. Build the **AerHockeyEditor / Development** target. The material and map are already supplied; if regenerating them, execute `Unreal/Tools/setup_arena.py` through Unreal's Python script command.

On this Mac, `Unreal/Build_AER.command` builds the project and regenerates the native map/material if either is missing. Set `UNREAL_ENGINE_ROOT` if your engine is installed somewhere else.

Rebuild the HTML after editing its source or geometry:

```sh
python3 Portable/build_portable.py
```

Regenerate the Blender model, GLB, shared runtime geometry, and product render:

```sh
blender --background --factory-startup --python SourceArt/build_arena.py
python3 Portable/build_portable.py
```

Run the portable C++ physics checks from this folder:

```sh
clang++ -std=c++17 -O2 Tests/physics_tests.cpp -o /tmp/aer_physics_tests
/tmp/aer_physics_tests
```

For a distributable Unreal application, use Unreal's Package Project workflow for the intended platform. The included `Data` directory is configured for staging, and the arena map/material are configured for cooking.

All model geometry, graphics, gameplay code, and synthesized sound were created for this delivery. No downloaded models, textures, music, or web libraries are required. The Unreal project uses standard engine components and an engine ambient cubemap.
