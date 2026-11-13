--!strict
-- ReplicatedStorage.Shared.Minigames.Pool.Furniture
-- The cue-sport tables as FURNITURE: everything about a table that is not the playing surface itself (that is
-- Tables: bed, cushion noses, jaws, holes, posts). How high the cloth stands, how wide the rails are, where a
-- potted ball rolls home to, how long a cue is, where a player stands to shoot. The bake draws the tables from
-- these numbers, the server sets the balls down by them and the client draws the cue and the camera by them:
-- one source, so what is baked is where the game puts things (checklist C18).
-- A table stands in a SITE's frame (Attractions/AlleyLayout: X across, Y up from the floor, D into the site)
-- with its centre at the station's (x, d) and its long axis along D: the table's x is the site's X and its z
-- the site's D (Tables' header), so a point on the bed is (station.x + x, BED_Y, station.d + z).
-- Parts the server and the clients find by name, under the table's Model (GamesRoom.Pool<index> /
-- GamesRoom.BumperPool): the ball Models "CueBall" (ball 0, eight-ball only) and "Ball<id>", each with its
-- pivot at the ball's centre and no rotation but the site's.
-- Pure data; Lune-tested (tests/unit/pool_furniture.spec.luau).
-- Interface: constants; modelName(game, index?) -> string; ballName(id) -> string; ballColor(table id, id) ->
--   ({ r, g, b }, striped); bed(station, x, z, y?) ->
--   (X, Y, D) (a table point in the site's frame; y is the height above the cloth); world(place, station, x,
--   y, z) -> world x, y, z; fromWorld(place, station, wx, wy, wz) -> (x, y, z); dir(place, dx, dz) -> world
--   (dx, dz); off(table, id, away?) -> (x, y, z) (where a ball that is not on the cloth lies: at home, or out
--   of sight if it is the cue ball or `away`); home(table, id) -> (x, y,
--   z) (where that ball lies once it is down: table frame, y its centre from the cloth); homeGate(table, id,
--   fromX) -> (x, y, z) (where it comes into the tray); tray(slot), cupTray(side, slot) -> (x, y, z) (the
--   trays' slots); outer(table) -> (halfW, halfL) (the furniture's footprint); stand(table, x, z, angle,
--   gap?) -> (x, z) (where a player aiming from (x, z) along `angle` stands: on the ring round the table,
--   behind the ball); sights(table) -> { { x, z } } (the diamonds)

local AlleyLayout = require("../../Attractions/AlleyLayout")
local Tables = require("./Tables")

local Furniture = {}

Furniture.BED_Y = 3.0 -- the cloth, above the floor (a person here stands about 5 studs tall)
Furniture.CLOTH_T = 0.05 -- the cloth and its board
Furniture.SLATE_T = 0.4 -- the bed under it
Furniture.CUSHION_H = 0.215 -- the nose of a cushion above the cloth (0.63 of a ball)
Furniture.CUSHION_BACK = 0.22 -- from the nose back to the wood
Furniture.RAIL_W = 0.56 -- the wooden rail outside the cushion
Furniture.RAIL_H = 0.27 -- the rail's top above the cloth
Furniture.APRON_H = 1.0 -- the body's side, down from the rail's top
Furniture.LEG_W = 0.62
Furniture.WELL_DEPTH = 0.75 -- a pocket's well below the cloth (a ball out of sight is Shot.SINK down)
Furniture.SIGHT_R = 0.055 -- a diamond on the rail

-- the ball return: potted balls line up, in the order they went down, in an open tray under the foot rail
Furniture.TRAY_SLOT = 0.352 -- between ball centres (a ball and a hair)
Furniture.TRAY_Y = -0.62 -- a ball's centre in the tray, from the cloth
Furniture.TRAY_OUT = 0.3 -- the tray's centre line outside the rail
Furniture.TRAY_ROLL = 0.9 -- seconds a potted ball takes from the pocket to its place in the tray

-- the cue (drawn by the clients; the bake stands spares in the rack)
Furniture.CUE_LEN = 4.6
Furniture.CUE_TIP = 0.05 -- diameters
Furniture.CUE_BUTT = 0.12
Furniture.CUE_BACK = 1.5 -- how far a full draw pulls the tip back from the ball
Furniture.CUE_REST = 0.12 -- the tip's distance from the ball when addressing it
Furniture.CUE_PITCH = 0.085 -- radians: the butt is raised a little to clear the rail

Furniture.LAMP_Y = 5.4 -- the lamp's shades above the cloth
Furniture.STAND = 1.5 -- a player stands this far outside the rail

-- bumper pool
Furniture.BUMPER_RAIL_W = 0.5
Furniture.POST_H = 0.3 -- a bumper's top above the cloth
Furniture.POST_RING_H = 0.17 -- its rubber ring: where a ball meets it (a ball's middle)
Furniture.CUP_TRAY_Y = -0.62
Furniture.CUP_TRAY_OUT = 0.3

-- the balls' colours (the bake paints them, the scorecards draw them)
Furniture.CUE_WHITE = { 246, 244, 236 }
Furniture.STRIPE_WHITE = { 244, 242, 232 }
Furniture.POOL_COLORS = {
	{ 244, 196, 32 }, -- 1 and 9: yellow
	{ 30, 74, 190 }, -- 2 and 10: blue
	{ 206, 36, 36 }, -- 3 and 11: red
	{ 104, 50, 150 }, -- 4 and 12: purple
	{ 238, 120, 28 }, -- 5 and 13: orange
	{ 24, 124, 70 }, -- 6 and 14: green
	{ 126, 32, 36 }, -- 7 and 15: maroon
	{ 20, 20, 22 }, -- 8: black
}
Furniture.BUMPER_RED = { 204, 34, 34 }
Furniture.BUMPER_WHITE = { 244, 242, 232 }

export type Station = { x: number, d: number, [string]: any }

-- A ball's colour, and whether it wears a band (eight-ball's 9 to 15: the colour is then the band's, on white).
function Furniture.ballColor(tableId: string, id: number): ({ number }, boolean)
	if tableId == "bumper" then
		return if id <= 5 then Furniture.BUMPER_RED else Furniture.BUMPER_WHITE, false
	elseif id == 0 then
		return Furniture.CUE_WHITE, false
	elseif id <= 8 then
		return Furniture.POOL_COLORS[id], false
	end
	return Furniture.POOL_COLORS[id - 8], true
end

function Furniture.modelName(game: string, index: number?): string
	return if game == "bumper_pool" then "BumperPool" else `Pool{index or 1}`
end

function Furniture.ballName(id: number): string
	return if id == 0 then "CueBall" else `Ball{id}`
end

-- A point of the table (x across, z along, y above the cloth) in the site's frame.
function Furniture.bed(station: Station, x: number, z: number, y: number?): (number, number, number)
	return station.x + x, Furniture.BED_Y + (y or 0), station.d + z
end

-- A table point (y above the cloth) in the world, for a table standing at `station` in the site at `place`.
function Furniture.world(
	place: AlleyLayout.Place,
	station: Station,
	x: number,
	y: number,
	z: number
): (number, number, number)
	return AlleyLayout.toWorld(place, station.x + x, Furniture.BED_Y + y, station.d + z)
end

-- A world point in the table's frame: (x, y above the cloth, z).
function Furniture.fromWorld(
	place: AlleyLayout.Place,
	station: Station,
	wx: number,
	wy: number,
	wz: number
): (number, number, number)
	local X, Y, D = AlleyLayout.toLocal(place, wx, wy, wz)
	return X - station.x, Y - Furniture.BED_Y, D - station.d
end

-- A direction on the table (dx across, dz along) as a world XZ direction.
function Furniture.dir(place: AlleyLayout.Place, dx: number, dz: number): (number, number)
	return AlleyLayout.dirToWorld(place, dx, dz)
end

-- Half the furniture's footprint: the bed, the cushions and the rails.
function Furniture.outer(tb: Tables.Table): (number, number)
	local edge = if tb.id == "bumper" then Furniture.BUMPER_RAIL_W else Furniture.CUSHION_BACK + Furniture.RAIL_W
	return tb.halfW + edge, tb.halfL + edge
end

-- A slot of the eight-ball table's tray (table frame; y is a ball's centre from the cloth): fifteen in a row
-- under the foot rail.
function Furniture.tray(slot: number): (number, number, number)
	local tb = Tables.eightBall()
	local _, hl = Furniture.outer(tb)
	return (slot - 8) * Furniture.TRAY_SLOT, Furniture.TRAY_Y, hl + Furniture.TRAY_OUT
end

-- Bumper pool: where a side's slot-th ball down lies, in the little tray at the end it was shot to (side 1
-- shoots at the foot cup, +z).
function Furniture.cupTray(side: number, slot: number): (number, number, number)
	local tb = Tables.bumper()
	local _, hl = Furniture.outer(tb)
	local sz = if side == 1 then 1 else -1
	return (slot - 3) * Furniture.TRAY_SLOT, Furniture.CUP_TRAY_Y, sz * (hl + Furniture.CUP_TRAY_OUT)
end

-- A ball's HOME: where it lies once it is down. Every ball has its own place, so the trays read like a
-- scoreboard and no ball ever shuffles along when another joins it. Eight-ball: ball n in slot n of the tray
-- under the foot rail (solids on the left, the 8 in the middle, stripes on the right, a gap for every ball
-- still up). Bumper pool: a side's five in the tray at the end they are shot to, the marked ball first.
function Furniture.home(tb: Tables.Table, id: number): (number, number, number)
	if tb.id == "bumper" then
		local side = if id <= 5 then 1 else 2
		return Furniture.cupTray(side, id - (side - 1) * 5)
	end
	return Furniture.tray(math.clamp(id, 1, 15))
end

-- Where a ball that is not on the cloth lies: at home in its tray; the cue ball, and a ball that is `away`
-- (not in this game: bumper pool's other five in practice), out of sight inside the table.
function Furniture.off(tb: Tables.Table, id: number, away: boolean?): (number, number, number)
	if id == 0 or away then
		return 0, -Furniture.WELL_DEPTH - 0.2, 0
	end
	return Furniture.home(tb, id)
end

-- Where a ball rolling home comes into its tray: the end of the tray nearer the pocket it went down, so it
-- is seen to roll along the tray to its place.
function Furniture.homeGate(tb: Tables.Table, id: number, fromX: number): (number, number, number)
	local x, y, z = Furniture.home(tb, id)
	local span = if tb.id == "bumper" then 3 * Furniture.TRAY_SLOT else 8 * Furniture.TRAY_SLOT
	return (if fromX < x then -span else span), y, z
end

-- Where a player who is aiming the ball at (x, z) along `angle` stands: straight behind the ball on the line
-- of the shot, on the ring STAND (or `gap`) outside the rail. The ring hugs the table, so the place is never
-- inside the table, and never farther from it than a step.
function Furniture.stand(tb: Tables.Table, x: number, z: number, angle: number, gap: number?): (number, number)
	local hw, hl = Furniture.outer(tb)
	local g = gap or Furniture.STAND
	hw += g
	hl += g
	-- back along the shot from the ball until the ring is crossed
	local dx, dz = -math.sin(angle), -math.cos(angle)
	local best = math.huge
	if dx > 1e-9 then
		best = math.min(best, (hw - x) / dx)
	elseif dx < -1e-9 then
		best = math.min(best, (-hw - x) / dx)
	end
	if dz > 1e-9 then
		best = math.min(best, (hl - z) / dz)
	elseif dz < -1e-9 then
		best = math.min(best, (-hl - z) / dz)
	end
	if best == math.huge or best < 0 then
		best = 0
	end
	return math.clamp(x + dx * best, -hw, hw), math.clamp(z + dz * best, -hl, hl)
end

-- The diamonds: three between pockets on each half of a long rail and three on each end rail (eighteen),
-- at the quarter points a bank is counted from. Bumper pool's rails carry none.
function Furniture.sights(tb: Tables.Table): { { x: number, z: number } }
	local out: { { x: number, z: number } } = {}
	if tb.id == "bumper" then
		return out
	end
	local mid = Furniture.CUSHION_BACK + Furniture.RAIL_W / 2
	for _, sx in { -1, 1 } do
		for k = 1, 3 do
			for _, sz in { -1, 1 } do
				table.insert(out, { x = sx * (tb.halfW + mid), z = sz * tb.halfL * k / 4 })
			end
		end
	end
	for _, sz in { -1, 1 } do
		for k = -1, 1 do
			table.insert(out, { x = k * tb.halfW / 2, z = sz * (tb.halfL + mid) })
		end
	end
	return out
end

return Furniture
