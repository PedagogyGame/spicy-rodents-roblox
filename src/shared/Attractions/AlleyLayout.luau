--!strict
-- ReplicatedStorage.Shared.Attractions.AlleyLayout
-- The bowling alley's geometry in one place (brief v2 §13a; BUILD_PLAN §3.17 bowling_alley, W3c #15): the bake
-- (tools/bake/attractions.luau) builds the building from it, the server's lanes (Server/Minigames/BowlingLane)
-- put the pins, the ball and the ball return where the bake drew them, and the tunnel routes in
-- data/attractions.json are checked against it (tests/unit/attractions_alley.spec.luau).
-- Local frame (studs): X across the lanes (+X is the bowler's right), Y up from the finished floor, D down the
-- lane from the foul line (+D toward the pins; the alley and its trash cans are behind the pins at D > 81).
-- The placement (data/attractions.json: origin x, z, floor y, yaw) turns local into world: yaw 0 puts the
-- lanes running toward world -Z with the entrance facing +Z (the boulevard).
-- Scale: real proportions x 3.8 per metre for the lane hardware (a person stands about 5 studs tall), with the
-- lane shortened to 56 studs foul line to head pin so a roll takes about two seconds.
-- Pure. Interface: constants below; laneX(i), pairX(p), pairOf(lane), sideOf(lane), pinSpots() -> { {x, d} },
--   pinLocal(lane, n) -> (X, D), rackSlot(lane) -> (X, Y, D), release(lane, offset) -> (X, Y, D),
--   toWorld(place, X, Y, D) -> (x, y, z), toLocal(place, x, y, z) -> (X, Y, D), dirToWorld(place, dX, dD) ->
--   (dx, dz), yawOf(place) -> world yaw of local +D, board(): dartboard frame, stations() -> { Station }

local AlleyLayout = {}

export type Place = { x: number, z: number, floorY: number, yaw: number }

-- Lanes --------------------------------------------------------------------------------------------------------
AlleyLayout.LANES = 6
AlleyLayout.LANE_W = 4.0 -- the bed (41.5 in)
AlleyLayout.GUTTER_W = 0.9
AlleyLayout.CAP_W = 0.4 -- capping between neighbouring gutters
AlleyLayout.PITCH = AlleyLayout.LANE_W + 2 * AlleyLayout.GUTTER_W + AlleyLayout.CAP_W -- 6.2
AlleyLayout.GUTTER_DEPTH = 0.32

AlleyLayout.APPROACH_D = -15 -- back of the approach
AlleyLayout.FOUL_D = 0
AlleyLayout.ARROWS_D = 14 -- target arrows (15 ft)
AlleyLayout.HEAD_D = 56 -- head pin
AlleyLayout.PIN_SPACING = 1.16 -- 12 in centre to centre
AlleyLayout.ROW_D = AlleyLayout.PIN_SPACING * math.sqrt(3) / 2
AlleyLayout.DECK_START = AlleyLayout.HEAD_D - 1.3
AlleyLayout.DECK_END = AlleyLayout.HEAD_D + 3 * AlleyLayout.ROW_D + 1.25 -- 60.26
AlleyLayout.PIT_END = 65.2
AlleyLayout.PIT_Y = -1.6
AlleyLayout.CUSHION_D = 64.6
AlleyLayout.MACHINE_D0 = 54.2 -- masking unit face
AlleyLayout.MACHINE_D1 = 66.5
AlleyLayout.MASK_BOTTOM = 3.4
AlleyLayout.REAR_WALL_D = 80.8 -- inner face of the rear wall (outer face +0.8)
AlleyLayout.WALL_T = 0.8
AlleyLayout.ALLEY_Y = -3.5 -- the alley's paving, below the floor (the site slopes down to the rear)
AlleyLayout.ALLEY_D1 = 101

-- Under the floor: the ball-return duct under each pair of lanes (the squirrel tunnel).
AlleyLayout.DUCT_W = 1.7
AlleyLayout.DUCT_FLOOR = -3.0 -- top of the duct floor
AlleyLayout.DUCT_CEIL = -0.4 -- underside of the finished floor
AlleyLayout.PIT_DUCT_CEIL = AlleyLayout.PIT_Y - 0.15 -- under the pits the duct is lower
AlleyLayout.SHAFT_D0 = -2.6 -- the riser into the ball-return hood
AlleyLayout.SHAFT_D1 = -0.9

-- Ball and pins (the physics parts).
AlleyLayout.BALL_D = 0.86 -- 8.5 in
AlleyLayout.PIN_H = 1.45 -- 15 in

-- Ball return hood and rack (one per pair, between the two approaches).
AlleyLayout.HOOD_D0 = -0.8
AlleyLayout.HOOD_D1 = -4.2
AlleyLayout.HOOD_W = 2.0
AlleyLayout.HOOD_H = 2.5
AlleyLayout.RACK_D1 = -10.4
AlleyLayout.RACK_Y = 1.5 -- rail tops at the hood end; they fall 0.15 toward the bowler

-- Building -----------------------------------------------------------------------------------------------------
AlleyLayout.X0 = -26
AlleyLayout.X1 = 56
AlleyLayout.FRONT_D = -48
AlleyLayout.CEILING_Y = 12
AlleyLayout.ROOF_Y = 13.6
AlleyLayout.LANE_BLOCK_X = 3 * AlleyLayout.PITCH -- the lanes span -18.6 .. 18.6
AlleyLayout.GAME_ROOM_X0 = 26 -- the games room (pool, bumper pool, darts, pinball, the fortune teller)
AlleyLayout.GAME_ROOM_D1 = 30
AlleyLayout.SETTEE_D = -21

function AlleyLayout.laneX(i: number): number
	return (i - (AlleyLayout.LANES + 1) / 2) * AlleyLayout.PITCH
end

function AlleyLayout.pairOf(lane: number): number
	return (lane + 1) // 2
end

-- -1 for the left lane of its pair, +1 for the right.
function AlleyLayout.sideOf(lane: number): number
	return if lane % 2 == 1 then -1 else 1
end

function AlleyLayout.pairX(p: number): number
	return (AlleyLayout.laneX(2 * p - 1) + AlleyLayout.laneX(2 * p)) / 2
end

-- Pin spots relative to the head pin: x across (bowler's right +), d down-lane. Pin 1 is the head pin; 7 is
-- back left, 10 back right (the standard numbering as the bowler sees it).
function AlleyLayout.pinSpots(): { { number } }
	local s, r = AlleyLayout.PIN_SPACING, AlleyLayout.ROW_D
	return {
		{ 0, 0 },
		{ -s / 2, r },
		{ s / 2, r },
		{ -s, 2 * r },
		{ 0, 2 * r },
		{ s, 2 * r },
		{ -1.5 * s, 3 * r },
		{ -s / 2, 3 * r },
		{ s / 2, 3 * r },
		{ 1.5 * s, 3 * r },
	}
end

function AlleyLayout.pinLocal(lane: number, n: number): (number, number)
	local spot = AlleyLayout.pinSpots()[n]
	return AlleyLayout.laneX(lane) + spot[1], AlleyLayout.HEAD_D + spot[2]
end

-- Where the lane's ball rests on its pair's rack (left lane nearer the hood).
function AlleyLayout.rackSlot(lane: number): (number, number, number)
	local p = AlleyLayout.pairOf(lane)
	local d = if AlleyLayout.sideOf(lane) < 0 then -5.2 else -6.3
	local fall = (d - AlleyLayout.HOOD_D1) / (AlleyLayout.RACK_D1 - AlleyLayout.HOOD_D1) * 0.15
	return AlleyLayout.pairX(p), AlleyLayout.RACK_Y - fall + AlleyLayout.BALL_D / 2, d
end

-- The release point at the foul line: offset -1..1 across the usable bed (the ball's own radius kept in).
function AlleyLayout.release(lane: number, offset: number): (number, number, number)
	local half = AlleyLayout.LANE_W / 2 - AlleyLayout.BALL_D / 2 - 0.05
	return AlleyLayout.laneX(lane) + math.clamp(offset, -1, 1) * half,
		AlleyLayout.BALL_D / 2 + 0.02,
		AlleyLayout.FOUL_D - 0.6
end

-- Placement ----------------------------------------------------------------------------------------------------
-- yaw 0: local +D -> world -Z, local +X -> world +X.
function AlleyLayout.toWorld(place: Place, X: number, Y: number, D: number): (number, number, number)
	local c, s = math.cos(place.yaw), math.sin(place.yaw)
	-- local axis vectors in world: right = (c, 0, -s) ... rotation of (X, 0, -D) about Y by yaw
	local lx, lz = X, -D
	return place.x + lx * c + lz * s, place.floorY + Y, place.z - lx * s + lz * c
end

function AlleyLayout.toLocal(place: Place, x: number, y: number, z: number): (number, number, number)
	local c, s = math.cos(place.yaw), math.sin(place.yaw)
	local dx, dz = x - place.x, z - place.z
	local lx = dx * c - dz * s
	local lz = dx * s + dz * c
	return lx, y - place.floorY, -lz
end

-- A local direction (dX across, dD down-lane) as a world XZ direction.
function AlleyLayout.dirToWorld(place: Place, dX: number, dD: number): (number, number)
	local c, s = math.cos(place.yaw), math.sin(place.yaw)
	local lx, lz = dX, -dD
	return lx * c + lz * s, -lx * s + lz * c
end

-- World yaw (Roblox: CFrame.Angles(0, yaw, 0) looks along (-sin yaw, 0, -cos yaw)) of looking down-lane.
function AlleyLayout.yawOf(place: Place): number
	return place.yaw
end

-- Games room -----------------------------------------------------------------------------------------------------
-- The dartboard hangs on the games room's right wall facing -X; the oche is 9 studs (7 ft 9 in) in front.
AlleyLayout.DART_MM = 0.0038 -- studs per millimetre
function AlleyLayout.board(): { [string]: any }
	local wallX = AlleyLayout.X1 - AlleyLayout.WALL_T / 2
	return {
		x = wallX - 0.25, -- board face
		y = 5.45, -- bull height (5 ft 8 in)
		d = 14,
		normalX = -1, -- faces -X (into the room)
		normalD = 0,
		ocheX = wallX - 0.25 - 9,
		radius = 225 * AlleyLayout.DART_MM,
	}
end

AlleyLayout.POOL_TABLES = { { x = 41, d = -31 }, { x = 41, d = -9 } }
AlleyLayout.BUMPER_POOL = { x = 36, d = 13 }
AlleyLayout.PINBALLS = { { x = 30.5, theme = "acorn" }, { x = 35, theme = "rodent" }, { x = 39.5, theme = "space" } }
AlleyLayout.PINBALL_D = -44.6
AlleyLayout.FORTUNE = { x = 52.3, d = 26.3 }

export type Station = {
	id: string,
	game: string,
	kind: string, -- "lane" | "dartboard" | "fortune" | "pool" | "bumper_pool" | "pinball"
	lane: number?,
	x: number,
	y: number,
	d: number,
	label: string,
}

-- Every place a game is played (the bake puts a prompt part at each; MinigameService finds them by id).
function AlleyLayout.stations(): { Station }
	local out: { Station } = {}
	for lane = 1, AlleyLayout.LANES do
		table.insert(out, {
			id = `bowling_lane_{lane}`,
			game = "bowling",
			kind = "lane",
			lane = lane,
			x = AlleyLayout.laneX(lane),
			y = 3,
			d = -9,
			label = `Lane {lane}`,
		})
	end
	local b = AlleyLayout.board()
	table.insert(out, {
		id = "darts_1",
		game = "darts",
		kind = "dartboard",
		x = b.ocheX + 1.2,
		y = 3,
		d = b.d,
		label = "Dartboard",
	})
	table.insert(out, {
		id = "fortune_1",
		game = "fortune_machine",
		kind = "fortune",
		x = AlleyLayout.FORTUNE.x - 1.6,
		y = 3,
		d = AlleyLayout.FORTUNE.d - 1.6,
		label = "Madame Acorna",
	})
	for i, t in AlleyLayout.POOL_TABLES do
		table.insert(out, {
			id = `pool_{i}`,
			game = "pool",
			kind = "pool",
			x = t.x,
			y = 3,
			d = t.d,
			label = `Pool table {i}`,
		})
	end
	table.insert(out, {
		id = "bumper_pool_1",
		game = "bumper_pool",
		kind = "bumper_pool",
		x = AlleyLayout.BUMPER_POOL.x,
		y = 3,
		d = AlleyLayout.BUMPER_POOL.d,
		label = "Bumper pool",
	})
	for i, p in AlleyLayout.PINBALLS do
		table.insert(out, {
			id = `pinball_{i}`,
			game = `pinball_{p.theme}`,
			kind = "pinball",
			x = p.x,
			y = 3,
			d = AlleyLayout.PINBALL_D + 3,
			label = "Pinball",
		})
	end
	return out
end

return AlleyLayout
