# Spicy Rodent — combined handoff

This combined package contains three independent ZIP files. Extract this outside of Roblox Studio; each nested ZIP can be extracted or imported separately.

**1. Store & Tunnels:** Recovered visual pack v2: finished offbeat store, café, back office, nine assembled skateboards, three sewer/tunnel modules, artwork, previews, and Blender base sources. This is art only. Original code and levels were not touched.

**2. Roof & Rafters:** Newly authored modular GLBs for a 2-meter rafter bay, full finished gable roof, route perches, collider proxies, and gutters/fascia. Includes a local JSON/Luau roof route graph, previews, and local QA checks. Not yet adapted to the live map.

**3. Luau gameplay prototypes:** Optional server-side code for paintball scoring, cable lift, pool-zone flagging, alley NPC patrol, session wallet, roof-route graph lookup, and integration/test notes. Its bootstrap is DISABLED by default. This is not a completed playable game; mechanics, props, models, UI, persistence, remote-action bridges, and in-Studio tests remain.

## Integrity
All three nested ZIP archives passed Python ZIP CRC checks at packaging time. `MANIFEST.json` contains SHA256 checksums for the original nested archives. An archive passing CRC does not confirm that a download link will work on the ChatGPT platform or that a GLB will function properly in the user's Roblox place.

## No background agents
No autonomous run-through or ongoing background execution is active in this chat. The QA scripts are static local checks, not Roblox playtests.
