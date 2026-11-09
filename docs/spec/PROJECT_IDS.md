# Roblox project IDs (owner-confirmed 2026-11-09)

USE THESE, all in the experience **Spicy Rodent** (Universe **10775476638**):

| Place | Place ID | Purpose | Verified |
|---|---|---|---|
| Spicy Rodent (start place) | **106044514609985** | the real game; owner builds are saved here | Open Cloud read + Luau Execution OK (version 4) |
| CI | **118507593202954** | automated test runs (Luau Execution) | Luau Execution OK (version 1) |
| Art Inbox | **126198571623370** | owner's Studio imports of skinned rigs/clips; Claude harvests asset IDs | Luau Execution OK (version 1) |

DO NOT USE: "Spicy Rodents" (Universe 10775476357, Place 71294450489810), an earlier duplicate the owner created.

The Open Cloud API key is stored as a network secret for apis.roblox.com (header x-api-key, injected by the proxy; it is never in files or env vars). Its scopes are assets r/w, universe-places write, and luau-execution-sessions r/w. Luau Execution is verified on all three places.

Places can be listed from inside the game with `AssetService:GetGamePlacesAsync()`; Open Cloud has no list-places endpoint.
