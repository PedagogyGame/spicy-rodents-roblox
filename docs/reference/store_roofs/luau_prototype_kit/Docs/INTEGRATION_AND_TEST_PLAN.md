# Spicy Rodent — isolated Luau feature prototypes / v1

## What this is and is not

These are independent **server-side Luau prototypes** for the requested feature names: paintball, sky lift, pool, alley, wallet, and roof-route lookup. They are **not a playable combined game** and were **not installed into or tested in the user's Roblox place**. They deliberately do not replace the existing movement, route registry, lighting, or economy.

The original Spicy Rodents v5.4 browser build is a reference, not a target that has been edited here. The future underground facility concept remains a separate note; no tunnel concept was merged into the original game.

## Folder placement

Copy `SpicyFeatures/` to `ServerScriptService` in a **copy** of your Roblox Studio experience. The disabled manual bootstrap illustrates wiring. Do not enable it wholesale; uncomment only services actually placed and tested. The roof-route ModuleScript is bundled here for convenience and corresponds to the separate roof-rafter art kit.

## Modules

| Module | Implemented in prototype | Not implemented |
|---|---|---|
| WalletService | Session balance, credit/spend, duplicate-transaction guard, server-held state | DataStore persistence, UI, storefront checkout |
| PaintballService | Arena membership, server-checked equipped marker, raycast, firing cooldown, nonlethal score | Round timer, teams, visual paintballs, hit decals, remote bridge, rewards |
| SkyLiftService | Single rider A→B anchored cabin movement, return route, distance checks | Multi-user carriage, cable physics, cabin model, emergency animation |
| PoolZoneService | Server-side pool occupancy attribute `SpicyInPool` | Water physics, dive animations, pool art, lifeguard NPCs |
| AlleyPatrolService | Sequential NPC Humanoid waypoint patrol | Alley geometry, pathfinding around moving obstacles, NPC dialogue |
| RoofRouteService | Local-node nearest lookup, direct-edge checks, world-transform mapping | Live player movement, merge with 1,332 existing v5.4 routes, route transitions |

## Gameplay acceptance targets / remaining work

### Paintball
- Players must join only from within the arena.
- All shooting validation occurs on the server; clients must never award their own hits.
- Outside-arena shots, rapid-fire attempts, shots without an equipped marker, and unregistered participants are rejected.
- Scores count only valid hits on other participating players. No health damage.
- Add actual marker, arena, teams/FFA choice, effects, UI, round start/end before claiming completion.

### Sky lift
- Platform/cabin and two anchored stations are set at real map coordinates.
- Reject boarding if the player is more than 9 studs away or cabin is occupied.
- Validate arrival without physics trapping, falls, stuck avatars or overlapping riders.
- Cabin uses `CFrame` motion with an anchored rider root as a prototype; retest on actual squirrel rig and movement controller. Never use this module unchanged on a complex moving character without testing.

### Pool
- Zone metadata correctly detects entry/exit with server-side checks.
- Use actual Roblox Terrain Water for swimming; the zone flag is NOT a substitute.
- Test underwater camera, entering/exiting, climbing from water, drowning/recovery rules only when separately approved.

### Alley
- NPCs traverse at least two ordered waypoints without attacking the player.
- Verify doorways, parked traffic and street furniture do not trap NPCs.
- Existing NPC behaviors remain in charge outside this isolated patrol.

### Wallet
- Transactions originate only in the server; duplicate keys cannot double-award.
- Negative/noninteger/NaN amounts, overspend and balance overflow fail.
- Decide persistence/backups and reconcile with original store/wardrobe before enabling.
- **No client payment action or purchases** have been wired in this pack.

### Roof route
- Preserve original v5.4 climb-route registry and generation IDs; never overwrite by matching local prototype IDs.
- Import perches and colliders alongside finished roof at same transform.
- Test landing, slope walking, ridge crossing, transfer to wires/adjacent roof and safe fall recovery.
- Resolve all `ExternalHooks` manually against actual map geometry.

### Run-through / QA
A fully automated gameplay agent is NOT running. `QA/verify_kit.py` statically checks this deliverable. Studio playthroughs still need to cover: spawning, roof routes, streets, shop entry, paintball, sky lift, pool, alley NPC patrol, wallet awards/spend, transitions back to normal exploration, and repeated exit/re-entry. Record failures and screenshot/video evidence before promoting modules into production.

## Non-regression requirements
- Do not alter original build, broad map, existing lighting mode, camera, roof/branch/wire traversal, NPC AI or global controls simply by importing.
- New code starts disabled and requires explicit integration into a Studio copy.
- Treat server authority for credits, scoring and permissions as mandatory.
- Do not interpret prototype module existence as a completed feature or a currently running external agent.
