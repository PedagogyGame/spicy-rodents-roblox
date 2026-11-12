--!strict
-- tools/bake/games/Paintball: the paintball arena's place in the world. NOT BUILT YET: no build, so nothing is baked,
-- the TV station has no site Model and the game has no station in the world.
-- OWNED BY THE ARENA LANE of the paintball contract (src/shared/Minigames/Paintball/Contract; the building as data is
-- ArenaData beside it, and its header says what this bake makes from that data).
-- It goes on site "f3_tv_station" (the venue's frame in generated/Expansion). To build it: return
-- { build = function(kit, parent, station, venue) ... end }. kit is tools/bake/alley/Kit in the venue's frame (X
-- across, Y above the floor, D into the site; kit:box / at / cyl / ball / wedge / model / gui / label / light):
-- Arena.toSite turns a point of the arena frame into it (the arena_origin anchor is at local (0, 0, 15), and the
-- arena's z runs against D). parent is the site's Model (Workspace.Attractions.f3_tv_station in the game), station
-- the Spec's StationDef and venue the venue's record from generated/Expansion (anchors, footprint, site, ground:
-- how deep the plinth must go; partBudget 3,500).
-- build is called once for each of paintball's two stations: build everything for the arena's own
-- (station.id == Contract.STATION) and nothing for the pass desk's prompt (station.joins ~= nil).
-- What the rest of paintball finds by name: ONE sub-model named Arena.MODEL ("PaintballArena") under parent (the
-- server's Table is inert on a site without it), and in it every monitor as a part named Arena.MONITOR
-- ("Monitor": one in the lobby, old sets about the floors) for the server to put the score on.
-- Interface: { build? } (a stub: none)

return {}
