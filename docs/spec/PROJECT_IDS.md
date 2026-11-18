# Roblox project IDs (owner-confirmed 2026-11-09)

USE THESE, all in the experience **Spicy Rodent** (Universe **10775476638**):

| Place | Place ID | Purpose | Verified |
|---|---|---|---|
| Spicy Rodent (start place) | **106044514609985** | the real game; owner builds are saved here | Open Cloud read + Luau Execution OK (version 4) |
| CI | **118507593202954** | automated test runs (Luau Execution) | Luau Execution OK (version 1) |
| Art Inbox | **126198571623370** | owner's Studio imports of skinned rigs/clips; Claude harvests asset IDs | Luau Execution OK (version 1) |

## Purchases

| What | ID | Status |
|---|---|---|
| "Spicy buck" currency product (given by the owner 2026-11-11) | **3730438620** | Recorded only. NOT wired into `src/shared/Economy/Products.luau`: the key cannot read developer products (the API answers "Scope not authorized"), so its Robux price and the Spicy Dollars it sells are not known here. It must not be attached to a tier by guess, because a wrong tier grants the wrong amount for real Robux. Waiting on the owner for: the price in Robux and the amount it should grant. |

DO NOT USE: "Spicy Rodents" (Universe 10775476357, Place 71294450489810), an earlier duplicate the owner created.

The Open Cloud API key is stored as a network secret for apis.roblox.com (header x-api-key, injected by the proxy; it is never in files or env vars). Verified 2026-11-09: assets read/write (place save to CI version 2 and a Decal upload both succeeded) and luau-execution-sessions read/write on all three places. **universe-places write is still refused** ("Scope not authorized" on cloud v2 place PATCH and legacy publish) — needed only to set serverSize/Max players and for the legacy publish route; the owner can set Max players 49 in Creator Hub instead.

Test artefacts in the owner's account: CI place version 2 (unpublished); Decal asset 89657770904034 (16x16 test image, safe to delete).

Places can be listed from inside the game with `AssetService:GetGamePlacesAsync()`; Open Cloud has no list-places endpoint.
