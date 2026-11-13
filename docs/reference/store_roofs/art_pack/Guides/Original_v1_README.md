# Spicy Rodent — tunnels, independent shop, café and skateboards

Original Blender art assets prepared from the November 13, 2026 design conversation. The requested delivery is a visual asset pack; it does not modify the existing Spicy Rodent game.

## Start here

- **GLB/** contains the three tunnel modules and complete three-room shop interior.
- **GLB/Skateboards/** contains seven separately reusable, fully assembled boards.
- **Source/** contains the editable Blender scenes and authoring scripts.
- **Previews/** contains rendered images of the models.
- **Textures/** contains original editable material maps, graphics and menus. The GLBs also embed their used textures.
- **Guides/** contains concise instructions for Claude and Roblox Studio.
- **Metadata/** contains dimensions, connector positions and verification results.

The shop has a larger retail room, a smaller café and a separate back office. Its personality comes from collected furnishings, handmade graphics, plants, antiques and mismatched materials. The two sales counters have distinct functions and positions. The café has five stools. Seven assembled skateboards are displayed behind the retail checkout and supplied separately as GLBs.

## Requested visual details

The retail area includes clothes, hats and knickknacks. The four original clothing-display names are **Midnight Static**, **Loose Wire**, **Dustline** and **Clear Signal**. The printed labels avoid naming the requested style genres.

Wall and ceiling decorations include Belgian and Jamaican flags, generic handmade posters and **The Spice Squirrels**, an original poster with five female squirrel pop-band members. Plants include bamboo. The café includes a vintage register, woodwork, old boat and truck décor, and fictional portrait silhouettes. A beaded curtain marks the entrance to the simple office. Several windows admit light.

The small **Rooftop Social Club** graphic and **chili-and-acorn** checkout emblem borrow visual personality from the original game's squirrel-scale, mischievous world. Those are art details. They do not change its controls, economy, wardrobe or other behavior.

## Café menu

Prices are intentionally left blank.

| Drinks | Food |
|---|---|
| Kombucha | Grilled cheese |
| Green tea | Ham sandwich |
| Bubble tea | Chicken noodle soup |
| Coffee | Tofu dish |
| Soft drink | Hamburger & french fries |

## Skateboard collection

| Board | Graphic |
|---|---|
| Lunar Moth | Moon and moth |
| Static Weekend | Old television, static and lightning |
| Ochre Run | Desert mountains and sun |
| Concrete Fern | Botanical stems and leaves |
| Tidal Check | Checker pattern and flowing waves |
| Ghost Fish | Friendly ghost fish and water lines |
| Violet Comet | Violet sky and comet |

Each standalone skateboard is approximately **0.82 m long, 0.21 m wide and 0.139 m high**, with a shaped deck, grip, two trucks and four wheels. These are display/game-prop meshes; riding physics and purchase behavior belong to the game.

## Tunnel modules

1. **Brick sewer passage:** a 12 m length with a barrel vault, twin raised walkways, a central water channel, rusty service lines, a red valve and a footbridge.
2. **Four-way sewer junction:** a 12 × 12 m layout with four arched exits, a vaulted center and a metal grate over the sump.
3. **Concrete maintenance tunnel:** a 12 m dry passage with a pump, electrical cabinet, cable trays, pipes, drain and a decorative closed service panel. Small muddy paw tracks sit beside the drain.

The common nominal interior width is 6 m; trim reduces the narrowest clear opening to about 5.6 m. Clear crown height is 5.2 m. Each module uses a floor-level center origin and named connection markers. Structural exterior dimensions and below-floor depth are recorded in the metadata. The ends are open for placement as modules; the previews show those open ends.

## Materials, scale and rendering

All new models use **meters**, with Blender Z-up and exported GLB Y-up. Do not infer the original HTML game's unit scale from these measurements. Keep the new asset scale explicit when importing into the current project.

The GLBs are self-contained glTF 2.0 binaries with embedded images and named meshes. They use ordinary PBR materials and do not need Draco or KTX2 decoding. Roofs, water, glass, architecture and display pieces remain separable where useful. Source files and textures allow further art changes.

Rendered previews use Blender lights. Engine lighting, reflections, shadows, transparent glass and navigation still need to be checked in the destination scene. This package has not been playtested in the user's Roblox Studio place or current Claude build. Keep the existing global and Realistic lighting choices when reviewing it.

Tunnel collision boxes and connection markers are reference data. They are not automatically installed into any game. A whole hollow room should not receive one solid bounding-box collider. The water is a static art surface. The maintenance access panel is a closed decorative panel.

## Reproduction

The source scripts state their required runtime and commands in their headers. Blender files can be edited normally without rerunning scripts. Rebuilding overwrites the generated assets in this extracted folder, so keep an edited copy first when making custom changes.

All geometry and texture graphics in this pack were authored for this request. The Spice Squirrels poster uses original image-generated artwork; its full-resolution source and prompt are preserved in `Textures/Shop/Artwork_Originals/`.
