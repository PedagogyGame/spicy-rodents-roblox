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
--   has(game) -> bool; LIST = { [game]: { build? } }
-- A builder: build(kit, parent, station, venue) with kit = tools/bake/alley/Kit in the site's frame, parent =
-- the GamesRoom model (the alley) or the venue's site Model, station = the Spec's StationDef, venue = the
-- venue's record from generated/Expansion (nil in the alley).

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

return GameBakes
