--!strict
-- tools/bake/GameBakes: the bake registry of minigames: ONE LINE PER GAME that has furniture of its own (its line
-- in src/shared/Minigames/Games says what the game is). tools/bake/attractions.luau builds every game's stations
-- through it: the bowling alley's games room calls build() for each station that stands in it, and for a station
-- on an expansion venue (generated/Expansion: "f3_racquet_club", "f3_steakhouse", "f2_doctor", "f3_tv_station")
-- the bake makes that venue's site Model (Workspace.Attractions.<venue id>, carrying Site / OriginX / OriginZ /
-- FloorY / Yaw so the server finds it) the first time a game builds there, and hands it to the game's build().
-- A game with no build bakes nothing: its venue gets no Model, so the server gives it no station.
-- (Bowling's lanes, the dartboard and Madame Acorna are part of the alley itself: tools/bake/alley.)
-- Interface: build(game, kit, parent, station, venue?) -> bool (false: the game has no builder);
--   has(game) -> bool; LIST = { [game]: { build? } }; siteModel(roblox, name, id, place) -> Model (with the
--   attributes the server reads); venueSites(roblox, folder, stations, places, venues, list?) -> { sites = count,
--   built = { station id }, parts } (the venue half of tools/bake/attractions; `list` replaces LIST in a spec)
-- A builder: build(kit, parent, station, venue) with kit = tools/bake/alley/Kit in the site's frame, parent =
-- the GamesRoom model (the alley) or the venue's site Model, station = the Spec's StationDef, venue = the
-- venue's record from generated/Expansion (nil in the alley).

local Kit = require("./alley/Kit")

local GameBakes = {}

type Entry = { build: ((kit: any, parent: any, station: any, venue: any?) -> ())? }

GameBakes.LIST = {
	pool = require("./games/Pool"),
	bumper_pool = require("./games/BumperPool"),
	pinball = require("./games/Pinball"),
	racquetball = require("./games/Racquetball"),
	volleyball = require("./games/Volleyball"),
	giant_jenga = require("./games/Jenga"),
	tilt_labyrinth = require("./games/Labyrinth"),
	paintball = require("./games/Paintball"),
	air_hockey = require("./games/AirHockey"),
} :: { [string]: Entry }

function GameBakes.has(game: string): boolean
	local entry = GameBakes.LIST[game]
	return entry ~= nil and entry.build ~= nil
end

function GameBakes.build(game: string, kit: any, parent: any, station: any, venue: any?): boolean
	local entry = GameBakes.LIST[game]
	local build = entry and entry.build
	if build == nil then
		return false
	end
	build(kit, parent, station, venue)
	return true
end

-- A site's Model: everything under it is in the site's own frame, and the server reads where that is from here.
function GameBakes.siteModel(roblox: any, name: string, id: string, place: Kit.Place): any
	local root = roblox.Instance.new("Model")
	root.Name = name
	root:SetAttribute("AttractionId", id)
	root:SetAttribute("Site", id)
	root:SetAttribute("OriginX", place.x)
	root:SetAttribute("OriginZ", place.z)
	root:SetAttribute("FloorY", place.floorY)
	root:SetAttribute("Yaw", place.yaw)
	return root
end

-- The minigames' places on the expansion venues: for every station on a venue whose game has a builder, that
-- venue's site Model (made the first time a game builds there, named after the venue) and the game's build().
function GameBakes.venueSites(
	roblox: any,
	folder: any,
	stations: { any },
	places: { [string]: Kit.Place },
	venues: { [string]: any },
	list: { [string]: Entry }?
): { sites: number, built: { string }, parts: number }
	local entries = list or GameBakes.LIST
	local sites: { [string]: { kit: any, root: any } } = {}
	local out = { sites = 0, built = {} :: { string }, parts = 0 }
	for _, st in stations do
		local venue = venues[st.site]
		local entry = entries[st.game]
		local build = entry and entry.build
		if venue == nil or build == nil then
			continue
		end
		local site = sites[st.site]
		if site == nil then
			local place = places[st.site]
			site = { kit = Kit.new(roblox, place), root = GameBakes.siteModel(roblox, st.site, st.site, place) }
			site.root.Parent = folder
			sites[st.site] = site
			out.sites += 1
		end
		build(site.kit, site.root, st, venue)
		table.insert(out.built, st.id)
	end
	for _, site in sites do
		out.parts += site.kit.count
	end
	return out
end

return GameBakes
