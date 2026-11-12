--!strict
-- tools/bake/games/Jenga: the giant Jenga deck's place in the world. NOT BUILT YET: no build, so nothing is baked and the
-- game has no site (its Spec, src/shared/Minigames/Jenga/Spec, lists no station either).
-- It goes on site "f3_steakhouse" (the venue's frame in generated/Expansion), anchor "jenga_table" at local (85, 1.5, 60).
-- To build it: return { build = function(kit, parent, station, venue) ... end }. kit is tools/bake/alley/Kit in
-- the venue's frame (X across, Y above the floor, D into the site; kit:box / at / cyl / ball / wedge / model /
-- gui / label / light), parent is the site's Model (Workspace.Attractions.f3_steakhouse in the game: make one sub-model
-- of your own under it and give every part the server or client must find a unique name), station is the
-- Spec's StationDef and venue the venue's record from generated/Expansion (anchors, footprint, site, ground:
-- how deep a plinth must go). Build the play surface first and enough floor and steps to walk onto it.
-- Interface: { build? } (a stub: none)

return {}
