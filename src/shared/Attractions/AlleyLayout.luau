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
-- THE FLOOR PLAN (eighteen lanes; brief addendum D4, D5) is the second half of this file: the building's outline,
-- the rooms as named rectangles (ZONES), every door and counter opening (OPENINGS), where the games-room tables
-- stand and the clear floor each needs (GAMES), where the staff stand and walk (POSTS, ROUTES), the floors a
-- body can stand on (FLOORS, floorAt), and the owner's backstage (BACKSTAGE: anchor, scale, the volume kept for
-- it, and the interim back module it replaces whole). The bake reads all of it; nothing about the plan is a
-- number in a bake file.
-- THE FLOOR PLAN (eighteen lanes; brief addendum D4, D5) is the second half of this file: the building's outline,
-- the rooms as named rectangles (ZONES), every door and counter opening (OPENINGS), where the games-room tables
-- stand and the clear floor each needs (standing), where the staff stand and walk (POSTS, ROUTES), the floors a
-- body can stand on (FLOORS, floorAt), and the owner's backstage (BACKSTAGE: anchor, scale, the volume kept for
-- it, and the interim back module it replaces whole). The bake reads all of it; nothing about the plan is a
-- number in a bake file.
-- Pure. Interface: constants below; laneX(i), pairX(p), pairOf(lane), sideOf(lane), pinSpots() -> { {x, d} },
--   pinLocal(lane, n) -> (X, D), rackSlot(lane) -> (X, Y, D), release(lane, offset) -> (X, Y, D),
--   toWorld(place, X, Y, D) -> (x, y, z), toLocal(place, x, y, z) -> (X, Y, D), dirToWorld(place, dX, dD) ->
--   (dx, dz), yawOf(place) -> world yaw of local +D, board(): dartboard frame, boardPoint(xmm, ymm) -> (X, Y, D),
--   boardFromLocal(Y, D) -> (xmm, ymm); zone(id) -> Zone; opening(id) -> Opening; post(id) -> Post;
--   machinePost(lane), approachPost(lane) -> Post; route(id) -> { {x, d, y} }; floorAt(X, D) -> Y?;
--   standing() -> { Standing }. The stations (where a player presses E) are listed by each game's Spec
--   (Shared/Minigames/Games.stations).

local AlleyLayout = {}

export type Place = { x: number, z: number, floorY: number, yaw: number }

-- Lanes --------------------------------------------------------------------------------------------------------
AlleyLayout.LANES = 18
AlleyLayout.PAIRS = 9
-- Lane 1's centre. Lanes 1 to 6 stand exactly where the six-lane house had them (it was centred on X 0);
-- lanes 7 to 18 were added to the east, each a PITCH further on.
AlleyLayout.LANE1_X = -15.5
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
-- Inner faces of the outer walls (the walls stand outside these, WALL_T thick). The plan is an L: the hall
-- (lanes, concourse and the front rooms) X0 .. HALL_X1 from the front wall to the rear wall, and the games room
-- as an east wing HALL_X1 .. X1 from the front wall back to GAME_ROOM_D1.
AlleyLayout.X0 = -26 -- west wall (where it always was)
AlleyLayout.X1 = 149 -- east wall: the games room's far wall (the dartboard hangs on it)
AlleyLayout.HALL_X1 = 101 -- the hall's east face: the games-room partition, then the outer wall behind the wing
AlleyLayout.FRONT_D = -68 -- front wall (20 nearer the street than the six-lane house: the front rooms)
AlleyLayout.CONCOURSE_D0 = -48 -- the concourse's front edge (the old front wall line): the front rooms are beyond
AlleyLayout.CEILING_Y = 12
AlleyLayout.ROOF_Y = 13.6
AlleyLayout.LANE_BLOCK_X0 = AlleyLayout.LANE1_X - AlleyLayout.PITCH / 2 -- -18.6: the lane block's west edge
AlleyLayout.LANE_BLOCK_X1 = AlleyLayout.LANE_BLOCK_X0 + AlleyLayout.LANES * AlleyLayout.PITCH -- 93.0
AlleyLayout.LANE_BLOCK_X = -AlleyLayout.LANE_BLOCK_X0 -- (the old half width, 18.6: the block is no longer centred)
AlleyLayout.GAME_ROOM_X0 = AlleyLayout.HALL_X1 -- the games room (pool, bumper pool, darts, pinball, air hockey,
AlleyLayout.GAME_ROOM_D0 = AlleyLayout.FRONT_D -- the fortune teller): the hall face of its partition, and its
AlleyLayout.GAME_ROOM_D1 = 30 -- front and back walls' inner faces
AlleyLayout.PARTITION_T = 0.6
AlleyLayout.SETTEE_D = -21

function AlleyLayout.laneX(i: number): number
	return AlleyLayout.LANE1_X + (i - 1) * AlleyLayout.PITCH
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
-- The games room is the east wing: GAME_ROOM_X0 + PARTITION_T .. X1 across, GAME_ROOM_D0 .. GAME_ROOM_D1 deep
-- (47.4 x 98, twice the six-lane house's 30 x 78). The pool tables stand in a column on the east side with the
-- dartboard on the east wall just beyond them, as they always did; the pinball machines stand along the front
-- wall; the fortune teller keeps the back corner by the ferns; bumper pool and air hockey have the west side.
-- The dartboard hangs on the games room's right wall facing -X; the oche is 9 studs (7 ft 9 in) in front.
AlleyLayout.DART_MM = 0.0038 -- studs per millimetre
function AlleyLayout.board(): { [string]: any }
	local wallX = AlleyLayout.X1 - AlleyLayout.WALL_T / 2
	return {
		x = wallX - 0.25, -- board face
		y = 5.45, -- bull height (5 ft 8 in)
		d = 8,
		normalX = -1, -- faces -X (into the room)
		normalD = 0,
		ocheX = wallX - 0.25 - 9,
		radius = 225 * AlleyLayout.DART_MM,
	}
end

-- boardPoint(xmm, ymm): local (X, Y, D) of a point on the board face, millimetres from the bull with +x to
-- the thrower's right and +y up. The thrower faces local +X (yaw 0: world +X), whose right is world +Z, which
-- is local -D: so +x runs toward -D.
function AlleyLayout.boardPoint(xmm: number, ymm: number): (number, number, number)
	local b = AlleyLayout.board()
	return b.x, b.y + ymm * AlleyLayout.DART_MM, b.d - xmm * AlleyLayout.DART_MM
end

-- boardFromLocal(Y, D): the board millimetres of a local point on the face (the inverse of boardPoint).
function AlleyLayout.boardFromLocal(Y: number, D: number): (number, number)
	local b = AlleyLayout.board()
	return (b.d - D) / AlleyLayout.DART_MM, (Y - b.y) / AlleyLayout.DART_MM
end

-- Table centres. A pool table's long side runs down the room (along D); a pinball machine's back is against the
-- front wall and its player stands on the +D side; the fortune cabinet faces the room diagonally.
AlleyLayout.POOL_TABLES = { { x = 134, d = -40 }, { x = 134, d = -14 } }
AlleyLayout.BUMPER_POOL = { x = 113, d = -16 }
AlleyLayout.PINBALLS = { { x = 107, theme = "acorn" }, { x = 111.5, theme = "rodent" }, { x = 116, theme = "space" } }
AlleyLayout.PINBALL_D = AlleyLayout.GAME_ROOM_D0 + 3.4 -- the cabinet's middle: its back is 1 from the front wall
AlleyLayout.FORTUNE = { x = AlleyLayout.X1 - 3.7, d = AlleyLayout.GAME_ROOM_D1 - 3.7 }
-- The air hockey table (about 6.2 across by 11.5 long; the owner's AER / 01, brief addendum D3): the middle of
-- its bed. yaw is the turn of the table's long axis from local +X about the vertical: 0 lays it across the room,
-- one player at its west end (toward the lanes) and one at its east end, each with 4 studs of floor.
AlleyLayout.AIR_HOCKEY = { x = 116, d = 20, yaw = 0 }
AlleyLayout.AIR_HOCKEY_SIZE = { across = 6.2, along = 11.5 }

-- (Where each game is played is its own Spec's business: Shared/Minigames/Games.stations.)

export type Rect = { x0: number, x1: number, d0: number, d1: number }
export type Standing = { id: string, x0: number, x1: number, d0: number, d1: number }

-- The floor each games-room table needs for itself and the people playing it (the table plus where they
-- stand, walk round it and draw a cue back). No two overlap and none reaches a wall or a doorway
-- (tests/unit/attractions_alley.spec.luau); whoever dresses the room keeps these clear.
function AlleyLayout.standing(): { Standing }
	local out: { Standing } = {}
	local function add(id: string, x0: number, x1: number, d0: number, d1: number)
		table.insert(out, { id = id, x0 = x0, x1 = x1, d0 = d0, d1 = d1 })
	end
	for i, t in AlleyLayout.POOL_TABLES do
		-- the table is 6.8 x 12.2 over its rails; a cue needs 5 behind every rail
		add(`pool_{i}`, t.x - 8.4, t.x + 8.4, t.d - 11.1, t.d + 11.1)
	end
	local bp = AlleyLayout.BUMPER_POOL
	add("bumper_pool", bp.x - 6.3, bp.x + 6.3, bp.d - 7.2, bp.d + 7.2)
	local pb = AlleyLayout.PINBALLS
	add("pinball", pb[1].x - 1.6, pb[#pb].x + 1.6, AlleyLayout.GAME_ROOM_D0, AlleyLayout.PINBALL_D + 5.6)
	local b = AlleyLayout.board()
	add("darts", b.ocheX - 3.6, b.x, b.d - 1.8, b.d + 1.8)
	local f = AlleyLayout.FORTUNE
	add("fortune", f.x - 4.3, AlleyLayout.X1, f.d - 4.3, AlleyLayout.GAME_ROOM_D1)
	local ah, size = AlleyLayout.AIR_HOCKEY, AlleyLayout.AIR_HOCKEY_SIZE
	local alongX = math.abs(math.cos(ah.yaw)) > 0.5
	local hx = if alongX then size.along / 2 + 4 else size.across / 2 + 1.2
	local hd = if alongX then size.across / 2 + 1.2 else size.along / 2 + 4
	add("air_hockey", ah.x - hx, ah.x + hx, ah.d - hd, ah.d + hd)
	return out
end

-- THE FLOOR PLAN ----------------------------------------------------------------------------------------------------
-- Rooms. Every rectangle is the room's clear floor between wall faces, in the local frame, at floor level
-- unless `y` says otherwise. `open` rooms have no wall toward the concourse.
--   the front rooms (FRONT_D .. CONCOURSE_D0, west to east): the bowling ball shop, the shoe rental (the control
--     desk, at the lobby's left hand), the lobby with the main doors, the gift shop, the snack bar, and the
--     lockers alcove beside the games room;
--   the hall: the concourse (CONCOURSE_D0 .. -24) across all eighteen lanes, the settees, the approaches, the
--     lanes and an aisle down each side;
--   the games room (the east wing); the back corridor behind the pinsetters; the rear alley outside.
export type Zone = {
	id: string,
	label: string,
	x0: number,
	x1: number,
	d0: number,
	d1: number,
	y: number?,
	open: boolean?,
	outside: boolean?,
}

local T = AlleyLayout.PARTITION_T
local FD, CD = AlleyLayout.FRONT_D, AlleyLayout.CONCOURSE_D0
-- the front rooms' cross walls stand on these lines (each wall T thick, centred)
AlleyLayout.FRONT_WALLS_X = { 2, 14, 30, 54, 88 }
AlleyLayout.ENTRANCE = { x0 = 18, x1 = 26 } -- the main doors in the front wall (on the Alley Walk's line)

AlleyLayout.ZONES = {
	{ id = "ball_shop", label = "BOWLING BALL SHOP", x0 = AlleyLayout.X0, x1 = 2 - T / 2, d0 = FD, d1 = CD - T },
	{ id = "shoe_rental", label = "SHOE RENTAL", x0 = 2 + T / 2, x1 = 14 - T / 2, d0 = FD, d1 = CD - T },
	{ id = "lobby", label = "LOBBY", x0 = 14 + T / 2, x1 = 30 - T / 2, d0 = FD, d1 = CD, open = true },
	{ id = "gift_shop", label = "GIFT SHOP", x0 = 30 + T / 2, x1 = 54 - T / 2, d0 = FD, d1 = CD - T },
	{ id = "snack_bar", label = "SNACK BAR", x0 = 54 + T / 2, x1 = 88 - T / 2, d0 = FD, d1 = CD - T },
	{ id = "lockers", label = "LOCKERS", x0 = 88 + T / 2, x1 = AlleyLayout.HALL_X1, d0 = FD, d1 = CD, open = true },
	{ id = "concourse", label = "CONCOURSE", x0 = AlleyLayout.X0, x1 = AlleyLayout.HALL_X1, d0 = CD, d1 = -24 },
	{
		id = "settees",
		label = "SETTEES",
		x0 = AlleyLayout.LANE_BLOCK_X0,
		x1 = AlleyLayout.LANE_BLOCK_X1,
		d0 = -24,
		d1 = AlleyLayout.APPROACH_D,
	},
	{
		id = "approaches",
		label = "APPROACHES",
		x0 = AlleyLayout.LANE_BLOCK_X0,
		x1 = AlleyLayout.LANE_BLOCK_X1,
		d0 = AlleyLayout.APPROACH_D,
		d1 = AlleyLayout.FOUL_D,
	},
	{
		id = "lanes",
		label = "LANES 1 - 18",
		x0 = AlleyLayout.LANE_BLOCK_X0,
		x1 = AlleyLayout.LANE_BLOCK_X1,
		d0 = AlleyLayout.FOUL_D,
		d1 = AlleyLayout.MACHINE_D1,
	},
	{
		id = "left_aisle",
		label = "AISLE",
		x0 = AlleyLayout.X0,
		x1 = AlleyLayout.LANE_BLOCK_X0 - 0.4,
		d0 = -24,
		d1 = AlleyLayout.MACHINE_D1 - T,
	},
	{
		id = "right_aisle",
		label = "AISLE",
		x0 = AlleyLayout.LANE_BLOCK_X1 + 0.4,
		x1 = AlleyLayout.HALL_X1,
		d0 = -24,
		d1 = AlleyLayout.MACHINE_D1 - T,
	},
	{
		id = "games_room",
		label = "GAMES ROOM",
		x0 = AlleyLayout.GAME_ROOM_X0 + T,
		x1 = AlleyLayout.X1,
		d0 = AlleyLayout.GAME_ROOM_D0,
		d1 = AlleyLayout.GAME_ROOM_D1,
	},
	{
		id = "back_corridor",
		label = "BACK CORRIDOR (interim)",
		x0 = AlleyLayout.X0,
		x1 = AlleyLayout.HALL_X1,
		d0 = AlleyLayout.MACHINE_D1,
		d1 = AlleyLayout.REAR_WALL_D,
	},
	{
		id = "rear_alley",
		label = "REAR ALLEY",
		x0 = AlleyLayout.X0 - AlleyLayout.WALL_T - 2,
		x1 = AlleyLayout.HALL_X1 + AlleyLayout.WALL_T + 14,
		d0 = AlleyLayout.REAR_WALL_D + AlleyLayout.WALL_T,
		d1 = AlleyLayout.ALLEY_D1,
		y = AlleyLayout.ALLEY_Y,
		outside = true,
	},
	{
		id = "forecourt",
		label = "FORECOURT",
		x0 = 9,
		x1 = 35,
		d0 = FD - 14,
		d1 = FD - AlleyLayout.WALL_T,
		outside = true,
	},
} :: { Zone }

function AlleyLayout.zone(id: string): Zone
	for _, z in AlleyLayout.ZONES do
		if z.id == id then
			return z
		end
	end
	error(`AlleyLayout: no zone {id}`)
end

-- Openings: every way through a wall. `axis` "x": the wall runs across the building on the line D = at and the
-- opening spans X a .. b; `axis` "d": the wall runs down the building on the line X = at and the opening spans
-- D a .. b. `head` is the height of the opening's top. kind: "door" (a doorway), "arch" (a wide cased opening),
-- "counter" (a serving opening: its counter is the room's furniture and leaves COUNTER_GAP clear at one end for
-- the staff), "open" (no wall at all, a beam overhead), "exit" (the steel push-bar doors).
export type Opening = {
	id: string,
	axis: string,
	at: number,
	a: number,
	b: number,
	head: number,
	kind: string,
	between: { string },
}
AlleyLayout.OPENINGS = {
	{
		id = "entrance",
		axis = "x",
		at = FD,
		a = AlleyLayout.ENTRANCE.x0,
		b = AlleyLayout.ENTRANCE.x1,
		head = 7.2,
		kind = "door",
		between = { "forecourt", "lobby" },
	},
	{
		id = "lobby",
		axis = "x",
		at = CD,
		a = 14 + T / 2,
		b = 30 - T / 2,
		head = 9,
		kind = "open",
		between = { "lobby", "concourse" },
	},
	{
		id = "ball_shop_door",
		axis = "x",
		at = CD,
		a = -16,
		b = -10,
		head = 7.2,
		kind = "door",
		between = { "ball_shop", "concourse" },
	},
	{
		id = "shoe_desk",
		axis = "d",
		at = 14,
		a = -64,
		b = -50,
		head = 8.4,
		kind = "counter",
		between = { "shoe_rental", "lobby" },
	},
	{
		id = "shoe_returns",
		axis = "x",
		at = CD,
		a = 5,
		b = 11,
		head = 8.4,
		kind = "counter",
		between = { "shoe_rental", "concourse" },
	},
	{
		id = "gift_shop_door",
		axis = "x",
		at = CD,
		a = 38,
		b = 46,
		head = 7.2,
		kind = "door",
		between = { "gift_shop", "concourse" },
	},
	{
		id = "snack_counter",
		axis = "x",
		at = CD,
		a = 58,
		b = 84,
		head = 8.4,
		kind = "counter",
		between = { "snack_bar", "concourse" },
	},
	{
		id = "lockers",
		axis = "x",
		at = CD,
		a = 88 + T / 2,
		b = AlleyLayout.HALL_X1,
		head = 9,
		kind = "open",
		between = { "lockers", "concourse" },
	},
	{
		id = "games_arch",
		axis = "d",
		at = AlleyLayout.GAME_ROOM_X0,
		a = -46,
		b = -32,
		head = 8.4,
		kind = "arch",
		between = { "concourse", "games_room" },
	},
	{
		id = "games_side",
		axis = "d",
		at = AlleyLayout.GAME_ROOM_X0,
		a = -6,
		b = 4,
		head = 8.4,
		kind = "arch",
		between = { "right_aisle", "games_room" },
	},
	{
		id = "machine_door_west",
		axis = "x",
		at = AlleyLayout.MACHINE_D1,
		a = -24.2,
		b = -20.8,
		head = 7.2,
		kind = "door",
		between = { "left_aisle", "back_corridor" },
	},
	{
		id = "machine_door_east",
		axis = "x",
		at = AlleyLayout.MACHINE_D1,
		a = 95.3,
		b = 98.7,
		head = 7.2,
		kind = "door",
		between = { "right_aisle", "back_corridor" },
	},
	{
		id = "exit_doors",
		axis = "x",
		at = AlleyLayout.REAR_WALL_D,
		a = -24.7,
		b = -20.3,
		head = 7.4,
		kind = "exit",
		between = { "back_corridor", "rear_alley" },
	},
} :: { Opening }
AlleyLayout.COUNTER_GAP = 3 -- a serving counter stops this far short of its opening's east (or +D) end

function AlleyLayout.opening(id: string): Opening
	for _, o in AlleyLayout.OPENINGS do
		if o.id == id then
			return o
		end
	end
	error(`AlleyLayout: no opening {id}`)
end

-- The rear exit's stoop and its steps down to the alley (the alley is ALLEY_Y below the floor); the entrance
-- landing (at floor level) and the ramp down from it to the walk from the street (y0 at its street end).
AlleyLayout.STOOP = { x0 = -27.4, x1 = -17.6, depth = 3.4, steps = 6, tread = 0.72 }
AlleyLayout.LANDING = { x0 = 13, x1 = 31, d0 = FD - 7 }
AlleyLayout.RAMP = { x0 = 16, x1 = 28, d0 = FD - 14, y0 = -0.6 }

-- Floors: where a body that takes its height from data (the computer-driven people) stands. `y` is the top of the
-- floor; a ramp runs from y at d0 to y1 at d1. Later rectangles win where two overlap.
export type Floor = { id: string, x0: number, x1: number, d0: number, d1: number, y: number, y1: number? }
do
	local st = AlleyLayout.STOOP
	local sd0 = AlleyLayout.REAR_WALL_D + AlleyLayout.WALL_T
	local alley = AlleyLayout.zone("rear_alley")
	local land, ramp = AlleyLayout.LANDING, AlleyLayout.RAMP
	AlleyLayout.FLOORS = {
		{ id = "rear_alley", x0 = alley.x0, x1 = alley.x1, d0 = alley.d0, d1 = alley.d1, y = AlleyLayout.ALLEY_Y },
		{
			id = "hall",
			x0 = AlleyLayout.X0,
			x1 = AlleyLayout.HALL_X1 + T,
			d0 = FD - AlleyLayout.WALL_T,
			d1 = AlleyLayout.REAR_WALL_D + AlleyLayout.WALL_T,
			y = 0,
		},
		{
			id = "games_room",
			x0 = AlleyLayout.HALL_X1,
			x1 = AlleyLayout.X1,
			d0 = AlleyLayout.GAME_ROOM_D0,
			d1 = AlleyLayout.GAME_ROOM_D1,
			y = 0,
		},
		{ id = "stoop", x0 = st.x0, x1 = st.x1, d0 = sd0, d1 = sd0 + st.depth, y = 0 },
		{
			id = "stoop_steps",
			x0 = st.x0,
			x1 = st.x1,
			d0 = sd0 + st.depth,
			d1 = sd0 + st.depth + st.steps * st.tread,
			y = 0,
			y1 = AlleyLayout.ALLEY_Y,
		},
		{ id = "landing", x0 = land.x0, x1 = land.x1, d0 = land.d0, d1 = FD - AlleyLayout.WALL_T, y = 0 },
		{ id = "ramp", x0 = ramp.x0, x1 = ramp.x1, d0 = ramp.d0, d1 = land.d0, y = ramp.y0, y1 = 0 },
	} :: { Floor }
end

-- The height of the floor under a local point (Y above the finished floor), or nil off every floor.
function AlleyLayout.floorAt(X: number, D: number): number?
	local found: number? = nil
	for _, f in AlleyLayout.FLOORS do
		if X >= f.x0 and X <= f.x1 and D >= f.d0 and D <= f.d1 then
			if f.y1 then
				found = f.y + (f.y1 - f.y) * (D - f.d0) / (f.d1 - f.d0)
			else
				found = f.y
			end
		end
	end
	return found
end

-- Staff posts: named places for an employee to be (the employees themselves are Server/Attractions' work).
-- `face` is the direction they look, as a local (dX, dD). Every post is on a floor, in its zone and clear of the
-- games' standing room (tests/unit/attractions_alley.spec.luau), and the bake's walk test stands a body on each.
export type Post = { id: string, x: number, d: number, zone: string, face: { number }?, what: string }
AlleyLayout.POSTS = {
	{ id = "shoe_desk", x = 10.5, d = -57, zone = "shoe_rental", face = { 1, 0 }, what = "behind the shoe desk" },
	{ id = "shoe_shelves", x = 5, d = -62, zone = "shoe_rental", face = { -1, 0 }, what = "the shoe cubbies" },
	{ id = "shoe_returns", x = 8, d = -51, zone = "shoe_rental", face = { 0, 1 }, what = "the returns window" },
	{ id = "ball_counter", x = -8, d = -53, zone = "ball_shop", face = { 0, 1 }, what = "the ball shop's counter" },
	{ id = "ball_wall", x = -23, d = -58, zone = "ball_shop", face = { -1, 0 }, what = "the wall of balls" },
	{ id = "ball_drill", x = -20, d = -65, zone = "ball_shop", face = { 0, -1 }, what = "the drilling bench" },
	{ id = "gift_counter", x = 34, d = -62, zone = "gift_shop", face = { 1, 0 }, what = "the gift shop's counter" },
	{ id = "gift_shelves", x = 50, d = -58, zone = "gift_shop", face = { 1, 0 }, what = "the souvenir shelves" },
	{ id = "snack_till", x = 62, d = -51.5, zone = "snack_bar", face = { 0, 1 }, what = "the snack bar's till" },
	{ id = "snack_grill", x = 70, d = -65, zone = "snack_bar", face = { 0, -1 }, what = "the grill and fryer" },
	{ id = "snack_fridge", x = 85, d = -62, zone = "snack_bar", face = { 1, 0 }, what = "the fridge" },
	{
		id = "snack_pass",
		x = 82.5,
		d = -50,
		zone = "snack_bar",
		face = { 0, 1 },
		what = "the gap at the counter's end",
	},
	{ id = "door_mat", x = 22, d = -64, zone = "lobby", face = { 0, -1 }, what = "inside the main doors" },
	{ id = "greeter", x = 22, d = -52, zone = "lobby", face = { 0, -1 }, what = "where a newcomer is met" },
	{ id = "lockers", x = 94, d = -60, zone = "lockers", face = { 0, -1 }, what = "the lockers" },
	{ id = "concourse_west", x = -12, d = -36, zone = "concourse", what = "the concourse's west end" },
	{ id = "concourse_mid", x = 37, d = -36, zone = "concourse", what = "the middle of the concourse" },
	{ id = "concourse_east", x = 86, d = -36, zone = "concourse", what = "the concourse's east end" },
	{ id = "tables", x = 70, d = -36, zone = "concourse", what = "the snack tables" },
	{ id = "left_aisle", x = -22.5, d = 20, zone = "left_aisle", what = "half way down the west aisle" },
	{ id = "right_aisle", x = 97, d = 20, zone = "right_aisle", what = "half way down the east aisle" },
	{ id = "games_arch", x = 106, d = -39, zone = "games_room", what = "just inside the games room" },
	{ id = "games_floor", x = 122, d = -26, zone = "games_room", what = "the middle of the games room" },
	{ id = "games_front", x = 136, d = -60, zone = "games_room", what = "the games room's front corner" },
	{ id = "games_back", x = 132, d = 22, zone = "games_room", what = "the games room's back" },
	{ id = "bench", x = -7, d = 77, zone = "back_corridor", face = { 0, 1 }, what = "the mechanic's bench" },
	{ id = "pin_shelf", x = 9, d = 77, zone = "back_corridor", face = { 0, 1 }, what = "the spare pins" },
	{ id = "corridor_west", x = -22.5, d = 72, zone = "back_corridor", what = "inside the west machine-room door" },
	{ id = "corridor_east", x = 97, d = 72, zone = "back_corridor", what = "inside the east machine-room door" },
	{
		id = "exit_inside",
		x = -22.5,
		d = 78.5,
		zone = "back_corridor",
		face = { 0, 1 },
		what = "at the push-bar doors",
	},
	{ id = "stoop", x = -22.5, d = 83.4, zone = "rear_alley", what = "the stoop outside the exit" },
	{ id = "alley_foot", x = -22.5, d = 91.5, zone = "rear_alley", what = "the foot of the stoop steps" },
	{ id = "cans", x = -12, d = 87, zone = "rear_alley", face = { 0, -1 }, what = "the big blue trash cans" },
} :: { Post }

function AlleyLayout.post(id: string): Post
	for _, p in AlleyLayout.POSTS do
		if p.id == id then
			return p
		end
	end
	error(`AlleyLayout: no post {id}`)
end

-- Behind a lane's pinsetter, in the back corridor (the mechanic tends a machine from here).
function AlleyLayout.machinePost(lane: number): Post
	return {
		id = `machine_{lane}`,
		x = AlleyLayout.laneX(lane),
		d = AlleyLayout.MACHINE_D1 + 3,
		zone = "back_corridor",
		face = { 0, -1 },
		what = `behind lane {lane}'s pinsetter`,
	}
end

-- At the back of a lane's approach (dust-mopping, calling a bowler).
function AlleyLayout.approachPost(lane: number): Post
	return {
		id = `approach_{lane}`,
		x = AlleyLayout.laneX(lane),
		d = AlleyLayout.APPROACH_D + 2,
		zone = "approaches",
		face = { 0, 1 },
		what = `the back of lane {lane}'s approach`,
	}
end

-- Walking routes: named lines of waypoints (x, d) a body can walk in straight legs without meeting a wall or a
-- piece of the building (the bake's walk test walks every leg). They cross at the posts, so a longer errand is a
-- chain of them.
AlleyLayout.ROUTES = {
	-- in at the main doors and through to the middle of the concourse
	welcome = { { 22, -72 }, { 22, -64 }, { 22, -52 }, { 22, -36 }, { 37, -36 } },
	-- the length of the concourse, behind the settees
	concourse = { { -22.5, -36 }, { -12, -36 }, { 22, -36 }, { 37, -36 }, { 70, -36 }, { 86, -36 }, { 97, -36 } },
	-- the shoe desk: the cubbies, the desk, the returns window
	shoe_desk = { { 5, -62 }, { 10.5, -57 }, { 8, -51 } },
	-- the ball shop, from its door
	ball_shop = { { -12, -36 }, { -13, -44 }, { -13, -53 }, { -8, -53 }, { -23, -58 }, { -20, -65 } },
	-- the gift shop, from its door
	gift_shop = { { 37, -36 }, { 42, -44 }, { 42, -55 }, { 34, -62 }, { 50, -58 } },
	-- the snack bar: from the concourse through the gap at the counter's end to the grill, the till and the fridge
	snack_bar = { { 86, -36 }, { 82.5, -44 }, { 82.5, -50 }, { 82.5, -58 }, { 70, -65 }, { 62, -51.5 }, { 85, -62 } },
	-- the west aisle from the concourse to the machine-room door, and the east aisle
	west_aisle = { { -22.5, -36 }, { -22.5, 20 }, { -22.5, 62 }, { -22.5, 72 } },
	east_aisle = { { 97, -36 }, { 97, 20 }, { 97, 62 }, { 97, 72 } },
	-- behind the eighteen machines, door to door
	machines = { { -22.5, 72 }, { -15.5, 69.5 }, { 89.9, 69.5 }, { 97, 72 } },
	-- the bin run: the back corridor, out through the push-bar doors, down the stoop steps to the cans
	bins = { { -22.5, 72 }, { -22.5, 78.5 }, { -22.5, 83.4 }, { -22.5, 91.5 }, { -12, 91.5 }, { -12, 87 } },
	-- the mechanic's bench and the spare pins
	bench = { { -22.5, 72 }, { -15.5, 74 }, { -7, 77 }, { 9, 77 } },
	-- the games room: in at the arch, round the tables, out at the side opening into the east aisle
	games_room = {
		{ 97, -39 },
		{ 106, -39 },
		{ 122, -26 },
		{ 122, -56 },
		{ 136, -60 },
		{ 122, -56 },
		{ 122, 2 },
		{ 132, 12 },
		{ 132, 22 },
		{ 122, 2 },
		{ 106, -1 },
		{ 97, -1 },
	},
	-- the lockers alcove
	lockers = { { 86, -36 }, { 94, -44 }, { 94, -60 } },
} :: { [string]: { { number } } }

-- A route's waypoints with the floor height under each: { x, d, y }.
function AlleyLayout.route(id: string): { { number } }
	local r = AlleyLayout.ROUTES[id]
	if r == nil then
		error(`AlleyLayout: no route {id}`)
	end
	local out = {}
	for _, p in r do
		table.insert(out, { p[1], p[2], AlleyLayout.floorAt(p[1], p[2]) or 0 })
	end
	return out
end

-- THE BACKSTAGE (brief addendum D4; docs/reference/bowling_backstage) ------------------------------------------------
-- The owner's authored service area goes behind the lanes. Its package (meshes, collision pieces and
-- Data/layout.json) HAS NOT ARRIVED: these numbers are from its handoff document and are what the site keeps
-- free for it.
--   anchor: "ServiceFrontCenter", the floor point at the middle of the eighteen lane tails. In the package's
--     frame +X points to lane 18 (our +X), +Y up, +Z toward the customer lanes (our -D); the backstage extends
--     toward -Z (our +D: the pins and beyond). Until layout.json gives the head-pin spots, the service front is
--     taken to be the masking units' face (MACHINE_D0); the final registration puts its eighteen head-pin base
--     spots on pinLocal(lane, 1).
--   scale: the package is authored at a 5.714286-stud lane pitch; ours is PITCH, so it is scaled by PITCH over
--     that (1.085), uniformly, about the anchor.
--   size: "about 189.3 x 125 studs" as authored (an irregular footprint: rooms and the workshop reach back and
--     to one side), so about 205.4 x 135.6 at our scale; the storage lofts are 3.63 m (12.96 authored studs,
--     14.07 of ours) above the floor, higher than the hall's 12-stud ceiling: the backstage brings its own roof.
--   reserve: the box the site keeps clear for it: the full width centred on the anchor (the true outline may sit
--     to either side), from the service front back by the full depth, up to a roof over the lofts.
--   interimFrom: until it arrives, everything behind the pinsetters (D > interimFrom: the back corridor, the rear
--     wall, the exit doors, the stoop, the rear alley and its fence) and the stand-in pinsetter machines are the
--     bake's "BackModule" (and "Doors"): one model the backstage replaces whole. The lanes' own playing parts
--     (beds, decks, pits, pins, sweeps, kickbacks, masking units), the nine tunnels and the hall stay.
do
	local authoredPitch = 5.714286
	local scale = AlleyLayout.PITCH / authoredPitch
	local anchorX = (AlleyLayout.laneX(1) + AlleyLayout.laneX(AlleyLayout.LANES)) / 2
	local anchorD = AlleyLayout.MACHINE_D0
	local w, d = 189.3 * scale, 125 * scale
	local loft = 3.63 / 0.28 * scale
	AlleyLayout.BACKSTAGE = {
		anchorName = "ServiceFrontCenter",
		anchor = { x = anchorX, y = 0, d = anchorD },
		authoredPitch = authoredPitch,
		scale = scale,
		size = { x = w, d = d },
		loftY = loft,
		reserve = { x0 = anchorX - w / 2, x1 = anchorX + w / 2, d0 = anchorD, d1 = anchorD + d, y1 = loft + 14 },
		interimFrom = AlleyLayout.MACHINE_D1,
		bays = AlleyLayout.LANES,
		returns = AlleyLayout.PAIRS,
	}
end

return AlleyLayout
