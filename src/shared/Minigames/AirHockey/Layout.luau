--!strict
-- ReplicatedStorage.Shared.Minigames.AirHockey.Layout
-- Where the air hockey table stands and how the owner's table (docs/reference/air_hockey/build_arena.py: metres,
-- X across, Y along, Z up, the playing bed at Z = 0.90) becomes studs in the bowling alley's games room. ONE
-- SOURCE: the bake (tools/bake/games/AirHockey) builds the table through these functions, the server puts the
-- puck and the mallets to rest with them, and the client draws and aims with them, so what is drawn is what
-- is simulated (tests/unit/air_hockey_layout.spec.luau).
-- Scale: the pool tables beside it have a 10.8 stud felt for a 2.54 m bed, so one metre is 10.8 / 2.54 studs,
-- across the table, along it and for everything above the bed. Below the bed the cabinet is shortened so that
-- the bed stands at BED_Y above the floor, a hand's height for the people of this town (the pool felt is at 3.0).
-- The table lies along the room's back wall: the model's +Y (Glacier's end at -Y, Ember's at +Y) runs along the
-- alley's local +X, and the model's +X along local -D (a turn about the vertical: the printed bed is not
-- mirrored). Glacier's player stands at the west end with their back to the lanes' side wall, Ember's at the east.
-- Pure. Interface: constants; height(z) -> Y; toLocal(x, y, z?) -> (X, Y, D); fromLocal(X, D) -> (x, y);
--   toWorld(place, x, y, z?) -> (wx, wy, wz); fromWorld(place, wx, wz) -> (x, y); camera(side, overhead) ->
--   { eye = {x, y, z}, target = {x, y, z}, fov }; stance(side) -> (X, D) where that end's player stands;
--   footprint() -> { x0, x1, d0, d1 } (the cabinet); standing(side) -> { x0, x1, d0, d1 }; srgb(linear) -> 0..255;
--   onTable(place, wx, wy, wz) -> (x, y)? (a point of the world that is on the table: where, in the model's
--   metres); aisle(place, y) -> (wx, wy, wz) (the floor beside the table on the room's side, level with y);
--   stations(sites) -> { StationDef }; sideOfStation(id) -> side?

local AlleyLayout = require("../../Attractions/AlleyLayout")
local GameSpec = require("../GameSpec")
local Sim = require("./Sim")

local Layout = {}

Layout.SITE = "bowling_alley"
Layout.SCALE = 10.8 / 2.54 -- studs per metre (the pool tables' own scale)
Layout.BED_Z = 0.90 -- the playing surface in the model, metres
Layout.BED_Y = 3.1 -- and in the room, studs above the floor
Layout.CENTRE = { x = 36.5, d = 25.8 } -- the middle of the bed in the alley's frame
-- the cabinet's reach from the middle of the bed, metres (side rails and cooling fins; end rails and puck return)
Layout.HALF_WIDTH = 0.75
Layout.HALF_LENGTH = 1.345
Layout.STAND_GAP = 0.25 -- a player stands this far (metres) behind their end...
Layout.STAND_DEPTH = 0.62 -- ...in a box this deep and as wide as the table
Layout.PROMPT_Y = 3.4

-- names in the bake (GamesRoom.AirHockey.<name>): what the server and the clients look for
Layout.MODEL = "AirHockey"
Layout.PUCK = "Puck"
Layout.MALLETS = { [0] = "MalletGlacier", [1] = "MalletEmber" }
Layout.SCORE = "ScoreBoard" -- a part with a SurfaceGui on each long face, each with a TextLabel "Score"
-- each end's own score, lit in the bed in the corner across from its team number (a plate with a SurfaceGui on
-- top holding a TextLabel "Score"): model metres, the Ember end's at +y, each read from its own end
Layout.SCORE_PRINTS = { [0] = "ScoreGlacier", [1] = "ScoreEmber" }
Layout.SCORE_PRINT = { x = 0.44, y = 1.02, w = 0.2, h = 0.075 }
Layout.SIDE_NAMES = { [0] = "Glacier", [1] = "Ember" }
-- The moving pieces are small Models (the puck; a mallet's base, crown, stem and cap), each with its pivot on
-- its own axis. The bake stands them at home (the puck on the centre spot, the mallets where a match starts
-- them) and whoever moves one slides its pivot across the bed to toWorld(x, y), height and turn unchanged.
Layout.HOME_PUCK = { 0, 0 }
Layout.HOME_MALLET = { [0] = { 0, -0.8 }, [1] = { 0, 0.8 } }

Layout.STATION = "air_hockey_1" -- the Glacier end's prompt (the table's own station)
Layout.STATION_EMBER = "air_hockey_1_ember" -- the Ember end's prompt: a second way in to the same table

-- Model height (metres above his floor) to studs above ours.
function Layout.height(z: number): number
	if z <= Layout.BED_Z then
		return z * (Layout.BED_Y / Layout.BED_Z)
	end
	return Layout.BED_Y + (z - Layout.BED_Z) * Layout.SCALE
end

-- A point of the model in the alley's local frame. z defaults to the bed.
function Layout.toLocal(x: number, y: number, z: number?): (number, number, number)
	return Layout.CENTRE.x + y * Layout.SCALE, Layout.height(z or Layout.BED_Z), Layout.CENTRE.d - x * Layout.SCALE
end

function Layout.fromLocal(X: number, D: number): (number, number)
	return (Layout.CENTRE.d - D) / Layout.SCALE, (X - Layout.CENTRE.x) / Layout.SCALE
end

function Layout.toWorld(place: GameSpec.Place, x: number, y: number, z: number?): (number, number, number)
	local X, Y, D = Layout.toLocal(x, y, z)
	return AlleyLayout.toWorld(place, X, Y, D)
end

function Layout.fromWorld(place: GameSpec.Place, wx: number, wz: number): (number, number)
	local X, _, D = AlleyLayout.toLocal(place, wx, 0, wz)
	return Layout.fromLocal(X, D)
end

-- The two views, in the model's metres: his first-person position at your end (the eye a little behind and well
-- above the end rail, looking just past the middle; 64 degrees) and the view from above with your end at the
-- bottom of the screen (lower and wider than his, to stay under the room's ceiling).
function Layout.camera(side: number, overhead: boolean): { eye: { number }, target: { number }, fov: number }
	local s = if side ~= 0 then 1 else -1
	if overhead then
		local up = (AlleyLayout.CEILING_Y - 0.7 - Layout.BED_Y) / Layout.SCALE
		return { eye = { 0, s * 0.02, Layout.BED_Z + up }, target = { 0, 0, Layout.BED_Z }, fov = 76 }
	end
	return { eye = { 0, s * 1.82, 1.70 }, target = { 0, -s * 0.18, Layout.BED_Z }, fov = 64 }
end

-- The cabinet's rectangle on the floor, local studs.
function Layout.footprint(): { x0: number, x1: number, d0: number, d1: number }
	local c, k = Layout.CENTRE, Layout.SCALE
	return {
		x0 = c.x - Layout.HALF_LENGTH * k,
		x1 = c.x + Layout.HALF_LENGTH * k,
		d0 = c.d - Layout.HALF_WIDTH * k,
		d1 = c.d + Layout.HALF_WIDTH * k,
	}
end

-- Where an end's player stands (the middle of their standing room), local X and D.
function Layout.stance(side: number): (number, number)
	local s = if side ~= 0 then 1 else -1
	local y = s * (Layout.HALF_LENGTH + Layout.STAND_GAP + Layout.STAND_DEPTH / 2)
	local X, _, D = Layout.toLocal(0, y)
	return X, D
end

-- The floor an end's player needs, local studs.
function Layout.standing(side: number): { x0: number, x1: number, d0: number, d1: number }
	local s = if side ~= 0 then 1 else -1
	local k = Layout.SCALE
	local near = Layout.CENTRE.x + s * (Layout.HALF_LENGTH + Layout.STAND_GAP) * k
	local far = near + s * Layout.STAND_DEPTH * k
	return {
		x0 = math.min(near, far),
		x1 = math.max(near, far),
		d0 = Layout.CENTRE.d - Layout.HALF_WIDTH * k,
		d1 = Layout.CENTRE.d + Layout.HALF_WIDTH * k,
	}
end

-- A point of the world that is ON the table (over the cabinet, from just under the bed to head height): where it
-- is in the model's metres. nil, nil for anything else: the floor under the table and the floor beside it are
-- not the table.
Layout.ON_TABLE = { below = 0.6, above = 5 } -- studs under and over the bed that still count
function Layout.onTable(place: GameSpec.Place, wx: number, wy: number, wz: number): (number?, number?)
	local X, Y, D = AlleyLayout.toLocal(place, wx, wy, wz)
	local x, y = Layout.fromLocal(X, D)
	if
		math.abs(x) > Layout.HALF_WIDTH
		or math.abs(y) > Layout.HALF_LENGTH
		or Y < Layout.BED_Y - Layout.ON_TABLE.below
		or Y > Layout.BED_Y + Layout.ON_TABLE.above
	then
		return nil, nil
	end
	return x, y
end

-- The floor beside the table on the room's side (the other side is the wall), level with the model's y: where
-- something knocked off the table lands.
Layout.AISLE = 1.5 -- studs out from the cabinet
function Layout.aisle(place: GameSpec.Place, y: number): (number, number, number)
	local X = Layout.CENTRE.x + math.clamp(y, -Layout.HALF_LENGTH, Layout.HALF_LENGTH) * Layout.SCALE
	return AlleyLayout.toWorld(place, X, 0.4, Layout.footprint().d0 - Layout.AISLE)
end

-- One of his material colours (linear RGB, 0..1) as an sRGB byte.
function Layout.srgb(linear: number): number
	local c = math.clamp(linear, 0, 1)
	local v = if c <= 0.0031308 then 12.92 * c else 1.055 * c ^ (1 / 2.4) - 0.055
	return math.floor(v * 255 + 0.5)
end

function Layout.sideOfStation(id: string): number?
	if id == Layout.STATION then
		return 0
	elseif id == Layout.STATION_EMBER then
		return 1
	end
	return nil
end

-- A prompt at each end, a step behind the end rail: the Glacier end's is the table's station, the Ember end's
-- joins it.
function Layout.stations(sites: { [string]: GameSpec.Place }): { GameSpec.StationDef }
	if sites[Layout.SITE] == nil then
		return {}
	end
	local out: { GameSpec.StationDef } = {}
	for side = 0, 1 do
		local X, D = Layout.stance(side)
		table.insert(out, {
			id = if side == 0 then Layout.STATION else Layout.STATION_EMBER,
			game = "air_hockey",
			label = `Air hockey ({Layout.SIDE_NAMES[side]} end)`,
			site = Layout.SITE,
			x = X,
			y = Layout.PROMPT_Y,
			d = D,
			index = 1,
			reach = 30,
			joins = if side == 0 then nil else Layout.STATION,
		})
	end
	return out
end

-- (the model's own numbers, for the bake and the specs)
Layout.RINK = { halfWidth = Sim.HALF_WIDTH, halfLength = Sim.HALF_LENGTH, goal = Sim.GOAL }

return Layout
