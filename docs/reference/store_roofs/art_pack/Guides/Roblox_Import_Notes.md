# Roblox Studio — visual asset import notes

These notes cover importing and reviewing the art pack. They do not replace the project's existing lighting setup or implement gameplay. The exports have not been imported or playtested in the user's Roblox Studio place.

## Import settings

Studio's Importer supports `.glb` files.[^importer] Import one scene at a time from `GLB/`, or an individual board from `GLB/Skateboards/`. The full v2 shop already includes the two new special boards and the jacket. Do not overlay `Shop_Flair_Only.glb` on that updated scene.

| Setting | Use for these assets |
|---|---|
| Scale Unit | **Meter** — the source geometry is modeled in meters; do not treat those numbers as studs.[^units] |
| Orientation | The GLB is already Y-up. Inspect the import preview before applying any extra rotation. |
| Merge Meshes | **Off**, preserving the separate interior surfaces and prop parts.[^importer] |
| Anchored | Keep static architecture and display props anchored. |
| Materials | Retain the separate mesh/material assignments and the supplied texture maps. |

## SurfaceAppearance maps

The authored meshes use a single UV layout with UV coordinates in the 0–1 range. Keep those UVs during any re-export. Review the imported material splits; some source objects, such as skateboard decks, contain multiple material primitives. Preserve the separate material-bearing surfaces.[^textures]

| Supplied image | SurfaceAppearance property |
|---|---|
| `*_basecolor.jpg`, or a named poster/flag/menu image | `ColorMap` |
| `*_normal.png` | `NormalMap` |
| `*_roughness.png` | `RoughnessMap` |
| `*_metallic.png` | `MetalnessMap` |

The normal maps use OpenGL tangent-space orientation, as Roblox expects.[^pbr] Separate grayscale roughness and metallic maps are included where those PBR materials are used. The `*_orm.png` files are packed glTF maps; do not assign the complete RGB ORM image as a grayscale roughness or metalness map. Occlusion images are supplied for other renderers and editing; SurfaceAppearance does not expose the same separate occlusion-map slot.

## Review with the existing lighting

Keep the user's global and **Realistic** lighting settings. Add or tune local fixtures within that established scene as needed to judge the imported materials. Emissive-looking lamp meshes and Blender render lights do not establish the complete Roblox lighting setup.

For enclosed interiors, Roblox's Realistic lighting tutorial recommends surrounding the space with opaque Part backing at least **1 stud thick** to limit unwanted outdoor light leakage.[^interior] Place any required backing outside the visible shell and preserve the entrances. A thin visible surface alone may not provide sufficient enclosure.

For collision, preserve the hollow passage. A single Box or convex Hull covering a whole tunnel would fill the space characters need to occupy. Use the supplied metadata as a starting reference for separate floors and walls; the engine's collision and navigation setup still requires review. Decorative pipes, posters, clothes, small antiques, and foliage do not each need an elaborate collider.

The canal water is a static visual mesh; café stools, menus, clothing, and boards are art assets. Importing them does not itself create seating, shopping, animation, or water behavior. Café prices intentionally remain blank.

## Official references

[^importer]: Roblox Creator Hub, [Importer](https://create.roblox.com/docs/studio/importer).
[^units]: Roblox Creator Hub, [MeshScaleUnit](https://create.roblox.com/docs/reference/engine/enums/MeshScaleUnit).
[^textures]: Roblox Creator Hub, [Texture specifications](https://create.roblox.com/docs/art/modeling/texture-specifications).
[^pbr]: Roblox Creator Hub, [SurfaceAppearance](https://create.roblox.com/docs/reference/engine/classes/SurfaceAppearance) and [PBR textures](https://create.roblox.com/docs/art/modeling/surface-appearance).
[^interior]: Roblox Creator Hub, [Enhance indoor environments with realistic lighting](https://create.roblox.com/docs/tutorials/use-case-tutorials/lighting/enhance-indoor-environments).


## v2 source status

Current geometry is in the final GLBs. Packaged `*_BASE_v1.blend` files are historical authoring scenes; use `Source/Import_v2_Into_Blender.py` or directly import the GLBs to edit the updated version. The jacket is an unrigged display prop, not wearable avatar clothing.
