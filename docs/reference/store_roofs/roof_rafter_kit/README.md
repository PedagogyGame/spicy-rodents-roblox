# Spicy Rodent — modular roof + rafter assets, v1

## What is delivered

Five new **GLB 2.0** files, a geometry reference image, an isolated roof-route graph and a Luau data-only ModuleScript. No original project files, game logic, lighting, or place file were modified. This is an independent candidate asset kit for the future Roblox/Claude build, NOT a tested Roblox implementation.

| Asset | Intent |
|---|---|
| `01_Exposed_Rafter_Bay_2m.glb` | 2-metre timber frame bay: paired rafters, ridge board, collar ties, rafter ties and eave framing |
| `02_Full_Gable_Roof_14m.glb` | Finished 14-m roof shell: roof decking, shingle rows, fascia, gutter, ridge cap, chimney and exposed rafter tails |
| `03_Ridge_Eave_Route_Perches.glb` | Squirrel-scale ridge grip, eave perch and sloped-roof footholds; aligned with the full roof |
| `04_Roof_Collider_Proxies.glb` | Proxy collider geometry for roof slopes and perches, to configure separately in Roblox Studio |
| `05_Gutter_Fascia_Details.glb` | Separate gutter/fascia bracket/downpipe detail kit |

## Coordinates and scale

- **Y-up**, meters in source GLBs.
- Full roof: ~10-m building span plus eaves, 14-m run plus 0.45-m end overhang. Eave Y ≈ 4.15m; ridge Y = 7.45m.
- Roof is centered at (0,0,0) at ground datum and intentionally has **no walls**; align to existing house geometry.
- A 2-m rafter bay can be repeated along the Z axis. Some structural elements in the finished roof are decorative, not engineered real-world structure.
- Perches and colliders align to full-roof local coordinates; attach as children under a shared root so transforms remain consistent.

## Studio / Claude integration

1. Keep current v5.4 route registry and project files untouched until a separate integration review.
2. Import finished roof and perches in the same local coordinate system. Scale units **once** for the destination game.
3. If using colliders, disable visible rendering of collider proxies and configure Collidable deliberately. **Do not** use one box collider around a hollow roof or building.
4. `Specs/roof_route_graph.json` / `Specs/RoofRouteData.luau` contain **local prototype** roof nodes. Merge/transform them; never assume they refer to route IDs in the original v5.4 town.
5. `ExternalHooks` are intentionally unresolved until actual nearby rooftops, wires and safe landing destinations are known.
6. Validate squirrel-to-roof jumps, roof-plane movement, ridge/eave traversal, transfers to adjacent routes, and fall recovery in Studio.
7. Do **not** overpaint or alter global/Realistic lighting settings when importing this art.

## Testing and limitations

This kit passed local GLB reload and mesh integrity checks, plus local path graph node/link checks. No Roblox Studio or user-game runtime testing was possible; scripts are data-only. Roof art uses geometry and colored vertex material rather than production PBR textures. This is a prototype/asset pack, not a finished integrated roofing system.

Other requested tracks (paintball, sky lift, pool, alley, wallet and run-through gameplay agents) are **not claimed complete or running**. The `STATUS.json` file records their state without inventing progress.
