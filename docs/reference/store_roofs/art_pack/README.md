# Spicy Rodent — complete visual art pack / v2

## Open this first

**`GLB/04_Offbeat_Shop_Interior.glb` is the finished updated store interior.** It already contains all nine assembled skateboards, the Night Route jacket and the new café details. Do not add `Shop_Flair_Only.glb` on top of it.

The pack also contains three sewer/tunnel modules. No original game file was altered. This is art, not a new shopping system, clothing system, quest, character controller or lighting configuration.

## What changed in this pass

- **Live Wire** — a charcoal-and-cream skateboard with telephone wires, a curled squirrel-tail silhouette and a small orange lightning accent.
- **Cache Run** — an olive-and-copper skateboard with an acorn, little cache marks and an invented wandering route.
- **Night Route** — a canvas shop-display jacket with a small acorn patch, brass-colored hardware, stitching and a hanger. It is a static prop, **not** a rigged or wearable Roblox outfit.

The two boards sit on a separate upper shelf behind the retail checkout, above the original seven. Each is also supplied independently with its deck, grip, two trucks and four wheels. All nine standalone skateboard meshes are approximately 0.82 × 0.21 m in deck length/width. The original seven files are preserved byte-for-byte.

The café received a framed fictional Old Town study, a small “Please don't feed the regulars” plaque, a ceramic lost-and-found jar with an acorn lid knob, and two cork coasters. The maintenance tunnel received a small “Dry Side / Mind Your Paws” plaque. None of these changes alters the original game's behavior.

## The complete requested interior

A larger retail room, a smaller woodworked café and a simple back office behind a beaded curtain. Separate retail and café counters. Exactly **five café stools**. Windows, bamboo and other plants, handmade posters, Belgium and Jamaica flags, hats, clothes, knickknacks, a vintage register, old boat/truck décor and fictional portrait silhouettes. The original **The Spice Squirrels** poster depicts five female squirrel band members.

The four existing clothing-display names remain Midnight Static, Loose Wire, Dustline and Clear Signal. Their printed names do not identify the requested style genres.

### Menus — all prices remain blank

Drinks: kombucha, green tea, bubble tea, coffee and soft drink.

Food: grilled cheese, ham sandwich, chicken noodle soup, tofu dish, and hamburger & french fries.

## Scene files

| File | Contents |
|---|---|
| `GLB/01_Brick_Sewer_Passage.glb` | Arched brick passage, water channel, walkways, pipes and bridge |
| `GLB/02_Four_Way_Sewer_Junction.glb` | Four arched connections, vaulted center and sump grate |
| `GLB/03_Concrete_Maintenance_Tunnel.glb` | Dry utility passage, pump, pipes, panel and small new wall plaque |
| `GLB/04_Offbeat_Shop_Interior.glb` | Complete three-room v2 shop, café and office |
| `GLB/Skateboards/` | All nine individual assembled boards |
| `GLB/Additions/Night_Route_Jacket.glb` | Independent static jacket display |
| `GLB/Additions/Shop_Flair_Only.glb` | Only the v2 shop additions, placed at the full shop's origin |
| `GLB/Additions/Dry_Side_Marker.glb` | Reusable standalone sewer plaque |
| `GLB/Additions/Specials_Display.glb` | Staged product-view scene for the two boards and jacket |

**Use either the full updated shop OR the additions over a v1 shop—not both.** The additions-only scene retains the shop's coordinate system; it is not centered on a single prop.

## Scale, materials and testing

The files are self-contained GLB 2.0 assets with embedded textures, named meshes, PBR materials and Y-up coordinates. Dimensions are in meters. Preserve the destination game's existing global/Realistic lighting choices; runtime lighting, collision and player-scale review are still needed. Do not put one solid collider around an entire hollow room or tunnel. Water remains static artwork. Prices and purchase behavior are not implemented.

All 17 GLB files in the `GLB/` tree passed the included local structural/geometry tests. Texture buffers, UV ranges, board count and stool count were checked. Representative final GLBs were rendered for inspection. **This is not a Roblox Studio or game-runtime playtest.** The included scene-triangle test ceiling is a local QA setting, not a claim about an engine limit.

## Sources and previews

`Textures/` includes editable artwork and maps. `Previews/` contains current v2 GLB renders; `Previews/Base_Layout/` preserves the first-pass Blender layout renders.

`Source/*_BASE_v1.blend` contains the recovered original Blender authoring scenes, unchanged. Those baseline files do not contain the v2 additions. The final GLBs are the current deliverable and can be imported directly into Blender for editing.

`Source/Import_v2_Into_Blender.py` is an optional helper to generate updated editable `.blend` copies from the final GLBs. It was syntax-checked but not executed in this environment. `Source/Build_Visual_Additions_v2.py` contains the update's mesh and graphic authoring logic. See `Source/SOURCE_STATUS.md` for precise source provenance.

No original game files, economy, wardrobe logic, controls or project lighting were changed.
