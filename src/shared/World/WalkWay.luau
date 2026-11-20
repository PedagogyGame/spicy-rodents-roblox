--!strict
-- ReplicatedStorage.Shared.World.WalkWay
-- The one way on foot for every computer-run body in town (the owner's playtest, 19 November: "one of the
-- characters ran through a wall"). The town's people are anchored and kinematic: Movement/HumanAIMotor walks a body
-- in a straight line to whatever its brain or a service names, and nothing in the engine stops it at a wall. So
-- every leg that is not already known to be clear (a lane, a round the bake keeps clear) is asked for here, and
-- this never hands back a way through a wall: when it knows none it says so (nil) and the caller does something
-- else (stays, takes another lane, an ambulance, out of sight).
--   * The obstacles are the building boxes of World/Colliders (every solid lot, the built venues, the bowling
--     alley) and, for walkers only, what else stands on the ground: the fence and parapet lines (the harvested
--     fence routes, drawn as panels by WorldGen/Builders/RouteProps), the venues baked by their own bakes that
--     Colliders leaves out (the TV station's arena, the sky lift's base, the Lookout), the raised decks (the
--     park's footbridge), the bowling alley's raised rear alley and its yard's house, the farmland under the sky
--     lift (Rides/SkyLiftCountry: hedges, walls, the farm), the sky lift's tower footings (Rides/SkyLift.towers),
--     Lookout Hill's rocks, benches and handrails (Rides/LookoutHill.obstacles: the bake's layout, the same numbers;
--     its trail is walked on, AI/TownAI's ground), the river's embankment walls (both banks, past the river's
--     ends), the plinth a clock tower stands on (WorldGen/Builders/Fixtures: PLINTH_OUT past its footprint) and the
--     benches on the bowling alley's front lawn
--     (Attractions/AlleyLayout.STREET_BENCHES); any of them at least LOW tall (a fountain's rim is a wall to a
--     walker). The river is closed ground (World/FootPath). tests/unit/wall_walk.spec holds every baked wall a
--     walker's waist meets to lying inside one of these boxes (tests/lib/WallAudit.uncovered).
--   * A building people work in has its own ways inside and a door (`rooms`): the bowling alley (Attractions/
--     AlleyWalk, out by its main doors), the hospital (Infection/HospitalLayout's lanes, out by its entrance), the
--     police station (the locker room's way out past the front desk: Actors/StaffRounds.POLICE_EXIT) and a built
--     venue whose counter is staffed (the post's way round the counter to its front door: StaffRounds.venues).
--     A walk into or out of one goes by its door; a walk inside one keeps to its ways.
--   * Any other box is solid: a point inside one has no way (find gives nil) and `putBack` names the nearest spot
--     outside it, where a body a player left in there is let go to the computer (TownAI.resume).
--   * The river bridge (the Quay's stone bridge, World/Height.RIVER: its ramps and deck, which the ground closes) is
--     a building with a door at each end (BRIDGE): on it a walker keeps to the walk line BRIDGE.walkZ, clear of the
--     traffic, the tower piers and the lamps; off it, a FootPath link joins the two doors, so the far bank is a way
--     over the bridge (AI/TownAI gives its ground the deck's height there).
--   * Outside, World/FootPath finds the way round the boxes (the boxes grown by a walker's half width), over the
--     whole of the town AI's bounds (opts.bounds), with its connected areas labelled at build: a way between two
--     areas no bridge joins (a fenced yard, the Lookout's top) is no way at once, without a search.
-- Interface: new(opts) -> Way; find(way, x0, z0, x1, z1, opts?) -> ({ {x, z} }?, length) (the points after the
--   start, the goal last); clear(way, x0, z0, x1, z1) -> boolean (a straight walk passes nothing); solidAt(way,
--   x, z, margin?) -> Box? (a box with no ways inside that holds the point, MARGIN inside its walls unless
--   `margin` says); roomAt(way, x, z) -> Room?; putBack(way, x, z)
--   -> (x, z, nx, nz) (where a body left at (x, z) can walk from, and the way out of the wall it was moved past);
--   splitLane(way, lane) -> { Lane } (the pieces of a straight lane that miss every obstacle); addFences(colliders,
--   data) -> n; bounds() -> the town AI's bounds (studs); posts(data) -> { {x, z, r} } (the telephone poles and tree
--   trunks: props, not walls); dodges(posts, lane) -> { {u, off} }? (those standing on a lane: where, and the step
--   aside that clears each); LOW, MARGIN, KEEP, LANE_MIN, DECK_MAX, BAKED_VENUES,
--   VENUE_YARD, RAMP_RUN, PORCH, BRIDGE
-- Pure; studs. No side effects on require.

local Colliders = require("./Colliders")
local FootPath = require("./FootPath")
local Ground = require("./Ground")
local Height = require("./Height")
local AlleyLayout = require("../Attractions/AlleyLayout")
local AlleyRoof = require("../Attractions/AlleyRoof")
local AlleyStaff = require("../Attractions/AlleyStaff")
local AlleyWalk = require("../Attractions/AlleyWalk")
local HospitalLayout = require("../Infection/HospitalLayout")
local StaffRounds = require("../Actors/StaffRounds")
local SkyLiftCountry = require("../Rides/SkyLiftCountry")
local SkyLift = require("../Rides/SkyLift")
local LookoutHill = require("../Rides/LookoutHill")

export type Room = {
	id: string,
	inside: (x: number, z: number) -> boolean,
	-- the way between two points inside (the start left out, the goal last)
	within: (x0: number, z0: number, x1: number, z1: number) -> { { number } },
	door: { number }, -- the spot in front of its door, outside: every walk in or out goes by it
	-- more than one door (the bridge: one at each end): a walk out goes by the one nearer where it is going, a walk
	-- in by the one nearer where it comes from
	doors: { { number } }?,
	-- where a body left at (x, z) inside is let go to the computer: a point its ways join without crossing what
	-- stands in the room (nil: anywhere inside joins them)
	settle: ((x: number, z: number) -> (number, number))?,
}

export type Way = {
	colliders: Colliders.Colliders,
	foot: FootPath.Finder,
	rooms: { Room },
	roomOf: { [string]: Room }, -- box id -> its room
}

-- (dodges: the posts standing on it, each { u along the lane, the step aside from its line }: dodges())
export type Lane = {
	axis: "x" | "z",
	fixed: number,
	min: number,
	max: number,
	inward: number?,
	dodges: { { number } }?,
}

local WalkWay = {}

WalkWay.LOW = 1.5 -- studs: anything this tall stops a walker (lower is stepped over)
WalkWay.MARGIN = 0.2 -- studs a point must be inside a box's walls to be in it
WalkWay.KEEP = 2.5 -- studs from a building's own ways (a lane, a round) a body may be let go and join them straight
WalkWay.LANE_MIN = 6 -- studs: a piece of lane shorter than this is not walked
WalkWay.DECK_MAX = 4 -- studs: a slab lot (a footbridge's deck) this tall or less is a wall to a walker; higher: a canopy
-- the venues baked by their own bakes that World/Colliders does not hold (it is also the squirrels' world, and the
-- TV station's arena is walked into for paintball): solid to walkers
WalkWay.BAKED_VENUES = table.freeze({ "f3_tv_station", "f4_lift_base", "f3_hilltop" })
-- studs a baked venue's box reaches past its footprint: the TV station's yard (its plinth, steps and the paintball
-- arena's yard fence stand up to 16 studs out)
WalkWay.VENUE_YARD = table.freeze({ f3_tv_station = 18 })

-- The Quay's stone bridge (World/Height.RIVER, studs): its ramps and deck run x0..x1 (|z| under half); the walk
-- line keeps walkZ, between the road's traffic and the tower piers, parapets and lamps (the piers stand from
-- |z| 17.8, a downspout at 17.1, the lamps at 16.1); its doors are `out` past each ramp's foot, on the walk line.
WalkWay.BRIDGE = table.freeze({
	id = "quay_stone_bridge",
	x0 = Height.RIVER.rampStart * Height.STUDS_PER_UNIT,
	x1 = Height.RIVER.rampEnd * Height.STUDS_PER_UNIT,
	half = 7.8 * Height.STUDS_PER_UNIT,
	walkZ = 12,
	out = 8,
})

-- studs a clock tower's plinth stands past its footprint (WorldGen/Builders/Fixtures: W + 4 across)
WalkWay.PLINTH_OUT = 2
-- the river's embankment walls (the Quay's: 1.3 units thick along each bank, Height.RIVER.halfWidth from the
-- channel's centre line, from the bed to the coping over the bank): boxed every EMBANK_STEP studs along z,
-- EMBANK_HALF studs each side of the line (the wall, its coping and the meander across a box)
WalkWay.EMBANK_STEP = 12
WalkWay.EMBANK_HALF = 3.5
-- studs each way round a sky lift tower's footing (tools/bake/skylift/Towers: 6.4 square, turned with the line)
WalkWay.FOOTING = 4.6

local FENCE_HALF = 0.5 -- studs: half a panel's thickness and a little more
local FENCE_PIECE = 3 -- studs: a slanted fence is boxed in pieces this long

-- The fence and parapet lines (the harvested routes of kind "fence": WorldGen/Builders/RouteProps draws a panel
-- down to the ground under each piece): a thin box per piece, from the ground to the rail. Returns how many.
function WalkWay.addFences(c: Colliders.Colliders, data: any): number
	local ok, registry = pcall(function()
		return data:routes()
	end)
	if not ok or registry == nil then
		return 0
	end
	local n = 0
	for _, r in registry:all() do
		if r.kind ~= "fence" then
			continue
		end
		local pts = r.points
		for k = 1, #pts - 1 do
			local a, b = pts[k], pts[k + 1]
			local dx, dz = b.x - a.x, b.z - a.z
			local len = math.sqrt(dx * dx + dz * dz)
			local pieces = math.max(1, math.ceil(len / FENCE_PIECE))
			for i = 0, pieces - 1 do
				local t0, t1 = i / pieces, (i + 1) / pieces
				local x0, z0 = a.x + dx * t0, a.z + dz * t0
				local x1, z1 = a.x + dx * t1, a.z + dz * t1
				local top = math.max(a.y, b.y)
				local y0 = math.min(Height.at(x0, z0), Height.at(x1, z1))
				n += 1
				Colliders.add(c, {
					id = `fence_{r.id}`,
					cx = (x0 + x1) / 2,
					cz = (z0 + z1) / 2,
					hw = math.abs(x1 - x0) / 2 + FENCE_HALF,
					hd = math.abs(z1 - z0) / 2 + FENCE_HALF,
					y0 = y0,
					eave = math.max(top, y0 + WalkWay.LOW),
					peak = math.max(top, y0 + WalkWay.LOW),
					ridge = nil,
				})
			end
		end
	end
	return n
end

-- The raised decks (lots of category "slab" whose deck stands LOW to DECK_MAX above the ground: the park's
-- footbridge): the computer's ground does not know a deck, so a walker would walk into its edge at the waist. Higher
-- slabs are canopies walked under (the fuel canopy, a porte-cochere); lower ones are stepped onto (a dock).
local function addDecks(c: Colliders.Colliders, data: any): number
	local lt = data:module("LotTypes") :: any
	local types = if lt and lt.types then lt.types else {}
	local n = 0
	for _, lot in data:lots() do
		local t = types[lot.type]
		local fp = lot.footprint
		local h = if t and t.heightU then t.heightU * Height.STUDS_PER_UNIT else 0
		if t and fp and t.category == "slab" and h >= WalkWay.LOW and h <= WalkWay.DECK_MAX then
			local y0 = Height.at(lot.x, lot.z)
			Colliders.add(c, {
				id = lot.id,
				cx = lot.x,
				cz = lot.z,
				hw = fp.w / 2,
				hd = fp.d / 2,
				y0 = y0,
				eave = y0 + h,
				peak = y0 + h,
				ridge = nil,
			})
			n += 1
		end
	end
	return n
end

-- The bowling alley's rear alley (AlleyLayout zone "rear_alley": raised paving behind the hall, a kerb and a fence,
-- with a ramp down at each end, RAMP_RUN long): outside the building's box, and higher than the computer's ground.
WalkWay.RAMP_RUN = 20 -- studs past each end of the rear alley's paving its ramps reach
-- a box in the alley's frame (X0..X1, D0..D1) as a world box
local function addAlleyBox(c: Colliders.Colliders, alley: any, id: string, r: { number }, y0: number, top: number)
	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, corner in { { r[1], r[3] }, { r[2], r[3] }, { r[1], r[4] }, { r[2], r[4] } } do
		local x, _, z = AlleyLayout.toWorld(alley, corner[1], 0, corner[2])
		minX, maxX = math.min(minX, x), math.max(maxX, x)
		minZ, maxZ = math.min(minZ, z), math.max(maxZ, z)
	end
	Colliders.add(c, {
		id = id,
		cx = (minX + maxX) / 2,
		cz = (minZ + maxZ) / 2,
		hw = (maxX - minX) / 2,
		hd = (maxZ - minZ) / 2,
		y0 = y0,
		eave = top,
		peak = top,
		ridge = nil,
	})
end

-- The bowling alley's neighbours in its own bake, outside its box: the guard's stair up the games wing, the rear alley (AlleyLayout zone "rear_alley":
-- raised paving behind the hall, a kerb and a fence, a ramp down at each end, RAMP_RUN long) and the yard's house
-- (AlleyRoof.HOUSE, its porch PORCH out), both higher than the computer's ground or solid.
WalkWay.RAMP_RUN = 20
WalkWay.PORCH = 4
local function addAlleyNeighbours(c: Colliders.Colliders, alley: any)
	local zone = AlleyLayout.zone("rear_alley")
	local y = alley.floorY + (zone.y or 0)
	local run = WalkWay.RAMP_RUN
	addAlleyBox(c, alley, "bowling_alley_rear", { zone.x0 - run, zone.x1 + run, zone.d0, zone.d1 }, y - 4, y + 4)
	-- the guard's stair against the games wing's back wall (AlleyRoof.STAIR: its flights and the ramp past its foot)
	local st = AlleyRoof.STAIR
	local foot = alley.floorY + st.footY
	addAlleyBox(c, alley, "bowling_alley_stair", { 101.8, st.footX + 4, st.d0 - 0.5, st.d1 + 0.5 }, foot, foot + 22)
	-- the benches on the front lawn (their backs are at a walker's waist)
	local bd = AlleyLayout.STREET_BENCH_D
	for _, b in AlleyLayout.STREET_BENCHES do
		local wx, _, wz = AlleyLayout.toWorld(alley, (b[1] + b[2]) / 2, 0, (bd[1] + bd[2]) / 2)
		local g = Height.at(wx, wz)
		addAlleyBox(c, alley, "bowling_alley_bench", { b[1] - 0.3, b[2] + 0.3, bd[1] - 0.3, bd[2] + 0.3 }, g, g + 3.5)
	end
	local h = AlleyRoof.HOUSE
	local p = WalkWay.PORCH
	local floor = alley.floorY + h.floorY
	addAlleyBox(
		c,
		alley,
		"bowling_alley_yard_house",
		{ h.x0 - p, h.x1 + p, h.d0 - p, h.d1 + p },
		floor,
		alley.floorY + h.ridgeY
	)
end

-- The farmland under the sky lift's line (Rides/SkyLiftCountry: its hedges, walls, paddock, farm and hut): a line
-- in pieces like a fence, a building as the box round its footprint however it is turned.
local function addCountry(c: Colliders.Colliders): number
	local ok, lines, blocks = pcall(SkyLiftCountry.obstacles)
	if not ok then
		return 0
	end
	local n = 0
	local function box(id: string, x0: number, z0: number, x1: number, z1: number, half: number)
		local y0 = math.min(Height.at(x0, z0), Height.at(x1, z1))
		n += 1
		Colliders.add(c, {
			id = id,
			cx = (x0 + x1) / 2,
			cz = (z0 + z1) / 2,
			hw = math.abs(x1 - x0) / 2 + half,
			hd = math.abs(z1 - z0) / 2 + half,
			y0 = y0,
			eave = y0 + 2 * WalkWay.LOW,
			peak = y0 + 2 * WalkWay.LOW,
			ridge = nil,
		})
	end
	for _, l in lines do
		local ax, az = SkyLiftCountry.at(l.u0, l.v0)
		local bx, bz = SkyLiftCountry.at(l.u1, l.v1)
		local len = math.sqrt((bx - ax) ^ 2 + (bz - az) ^ 2)
		local pieces = math.max(1, math.ceil(len / FENCE_PIECE))
		for i = 0, pieces - 1 do
			local t0, t1 = i / pieces, (i + 1) / pieces
			box(
				"lift_country",
				ax + (bx - ax) * t0,
				az + (bz - az) * t0,
				ax + (bx - ax) * t1,
				az + (bz - az) * t1,
				l.w / 2 + 0.2
			)
		end
	end
	for _, b in blocks do
		local x, z = SkyLiftCountry.at(b.u, b.v)
		box("lift_country", x, z, x, z, math.max(b.w, b.d) / 2 * math.sqrt(2))
	end
	local sh = SkyLiftCountry.SHELTER
	box("lift_shelter", sh.x, sh.z, sh.x, sh.z, sh.half)
	return n
end

-- The river's embankment walls (Height.RIVER: the channel's centre line wanders 9 units each way; the walls stand
-- halfWidth from it on both banks and reach a little past the river's two ends, where the bank steps down)
local function addEmbankments(c: Colliders.Colliders): number
	local R, S = Height.RIVER, Height.STUDS_PER_UNIT
	local z0, z1 = (R.zMin - 1) * S, (R.zMax + 1) * S
	local n = 0
	local steps = math.ceil((z1 - z0) / WalkWay.EMBANK_STEP)
	for i = 0, steps - 1 do
		local za, zb = z0 + (z1 - z0) * i / steps, z0 + (z1 - z0) * (i + 1) / steps
		for _, side in { -1, 1 } do
			local xa = (Height.riverCenterU(za / S) + side * R.halfWidth) * S
			local xb = (Height.riverCenterU(zb / S) + side * R.halfWidth) * S
			Colliders.add(c, {
				id = "river_embankment",
				cx = (xa + xb) / 2,
				cz = (za + zb) / 2,
				hw = math.abs(xb - xa) / 2 + WalkWay.EMBANK_HALF,
				hd = (zb - za) / 2,
				y0 = R.bedY * S,
				eave = R.bankY * S + 0.6,
				peak = R.bankY * S + 0.6,
				ridge = nil,
			})
			n += 1
		end
	end
	return n
end

-- the plinth under each clock tower (a landmark tower named for its clock), PLINTH_OUT past its footprint
local function addPlinths(c: Colliders.Colliders, data: any): number
	local n = 0
	for _, lot in data:lots() do
		local fp = lot.footprint
		if lot.type == "landmark_tower" and fp and string.find(lot.id, "clock", 1, true) then
			local y0 = Height.at(lot.x, lot.z)
			Colliders.add(c, {
				id = `{lot.id}_plinth`,
				cx = lot.x,
				cz = lot.z,
				hw = fp.w / 2 + WalkWay.PLINTH_OUT,
				hd = fp.d / 2 + WalkWay.PLINTH_OUT,
				y0 = y0,
				eave = y0 + 6,
				peak = y0 + 6,
				ridge = nil,
			})
			n += 1
		end
	end
	return n
end

-- the sky lift's tower footings
local function addFootings(c: Colliders.Colliders): number
	local ok, towers = pcall(SkyLift.towers)
	if not ok then
		return 0
	end
	local half = WalkWay.FOOTING
	for _, t in towers do
		local y0 = Height.at(t.x, t.z)
		Colliders.add(c, {
			id = "lift_footing",
			cx = t.x,
			cz = t.z,
			hw = half,
			hd = half,
			y0 = y0 - 2,
			eave = y0 + 4,
			peak = y0 + 4,
			ridge = nil,
		})
	end
	return #towers
end

-- Lookout Hill's rocks, benches and handrails (Rides/LookoutHill.obstacles)
local function addLookoutHill(c: Colliders.Colliders): number
	local ok, blocks = pcall(LookoutHill.obstacles)
	if not ok then
		return 0
	end
	for _, b in blocks do
		Colliders.add(c, {
			id = b.id,
			cx = (b.x0 + b.x1) / 2,
			cz = (b.z0 + b.z1) / 2,
			hw = (b.x1 - b.x0) / 2,
			hd = (b.z1 - b.z0) / 2,
			y0 = b.y0,
			eave = b.top,
			peak = b.top,
			ridge = nil,
		})
	end
	return #blocks
end

-- the venues in BAKED_VENUES, as Colliders.addBuiltVenues boxes them
local function addBakedVenues(c: Colliders.Colliders, data: any): number
	local ex = data:module("Expansion") :: any
	local n = 0
	for _, v in (if ex and ex.venues then ex.venues else {}) :: { any } do
		local poly = v.footPoly
		if table.find(WalkWay.BAKED_VENUES, v.id) == nil or poly == nil or #poly < 3 then
			continue
		end
		local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
		for _, p in poly do
			minX, maxX = math.min(minX, p[1]), math.max(maxX, p[1])
			minZ, maxZ = math.min(minZ, p[2]), math.max(maxZ, p[2])
		end
		local y0 = if v.ground then v.ground.min else v.floorY
		local yard = WalkWay.VENUE_YARD[v.id] or 0
		Colliders.add(c, {
			id = v.id,
			cx = (minX + maxX) / 2,
			cz = (minZ + maxZ) / 2,
			hw = (maxX - minX) / 2 + yard,
			hd = (maxZ - minZ) / 2 + yard,
			y0 = y0,
			eave = math.max(v.floorY + (v.height or 10), y0 + WalkWay.LOW),
			peak = math.max(v.floorY + (v.height or 10), y0 + WalkWay.LOW),
			ridge = nil,
		})
		n += 1
	end
	return n
end

-- the nearest point to (x, z) on a set of legs { x1, z1, x2, z2 }, and how far it is
local function nearestOnLegs(legs: { { number } }, x: number, z: number): (number, number, number)
	local best, bx, bz = math.huge, x, z
	for _, l in legs do
		local ex, ez = l[3] - l[1], l[4] - l[2]
		local l2 = ex * ex + ez * ez
		local t = if l2 > 0 then math.clamp(((x - l[1]) * ex + (z - l[2]) * ez) / l2, 0, 1) else 0
		local px, pz = l[1] + ex * t, l[2] + ez * t
		local d = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
		if d < best then
			best, bx, bz = d, px, pz
		end
	end
	return bx, bz, best
end

-- settle onto a set of legs: kept within KEEP of them, else moved onto the nearest
local function settleOn(legs: { { number } }): (number, number) -> (number, number)
	return function(x: number, z: number): (number, number)
		local px, pz, d = nearestOnLegs(legs, x, z)
		if d <= WalkWay.KEEP then
			return x, z
		end
		return px, pz
	end
end

-- the way along a chain of points (the deepest first, the door's outside spot last) between two points inside
local function chainWithin(chain: { { number } }): (number, number, number, number) -> { { number } }
	local function nearest(x: number, z: number): number
		local best, bestD = 1, math.huge
		for i, p in chain do
			local d = (p[1] - x) ^ 2 + (p[2] - z) ^ 2
			if d < bestD then
				best, bestD = i, d
			end
		end
		return best
	end
	return function(x0: number, z0: number, x1: number, z1: number): { { number } }
		local i0, i1 = nearest(x0, z0), nearest(x1, z1)
		local out: { { number } } = {}
		local step = if i1 >= i0 then 1 else -1
		for i = i0, i1, step do
			table.insert(out, { chain[i][1], chain[i][2] })
		end
		table.insert(out, { x1, z1 })
		return out
	end
end

-- a building whose only way is a chain (its post's way out) and the rounds worked at its end (`rounds`: closed
-- loops of points)
local function boxRoom(id: string, box: Colliders.Box, chain: { { number } }, rounds: { { { number } } }?): Room
	local legs: { { number } } = {}
	for i = 1, #chain - 1 do
		table.insert(legs, { chain[i][1], chain[i][2], chain[i + 1][1], chain[i + 1][2] })
	end
	local list: { { { number } } } = rounds or {}
	for _, round in list do
		for i, p in round do
			local q = round[i % #round + 1]
			table.insert(legs, { p[1], p[2], q[1], q[2] })
		end
	end
	return {
		id = id,
		inside = function(x: number, z: number): boolean
			return math.abs(x - box.cx) < box.hw and math.abs(z - box.cz) < box.hd
		end,
		within = chainWithin(chain),
		door = chain[#chain],
		settle = settleOn(legs),
	}
end

export type Opts = {
	data: any, -- Shared/Data
	colliders: Colliders.Colliders?, -- the building boxes (default Colliders.fromData(data))
	hospital: HospitalLayout.Layout?, -- default HospitalLayout.fromData(data)
	-- where the path-finder has ground (studs; default bounds(): the town AI's, where a player can leave a body)
	bounds: { minX: number, maxX: number, minZ: number, maxZ: number }?,
}

-- bounds(): the town AI's bounds (AI/TownAI's ctx.bounds: World/Height.worldClamp read as units), studs
function WalkWay.bounds(): { minX: number, maxX: number, minZ: number, maxZ: number }
	local c = Height.worldClamp()
	local s = Height.STUDS_PER_UNIT
	return { minX = c.minX * s, maxX = c.maxX * s, minZ = c.minZ * s, maxZ = c.maxZ * s }
end

-- the bridge as a building with a door at each end: on it, onto the walk line, along it, and off it to the goal
local function bridgeRoom(): Room
	local B = WalkWay.BRIDGE
	local west, east = { B.x0 - B.out, B.walkZ }, { B.x1 + B.out, B.walkZ }
	return {
		id = B.id,
		inside = function(x: number, z: number): boolean
			return x > B.x0 and x < B.x1 and math.abs(z) < B.half
		end,
		within = function(x0: number, z0: number, x1: number, z1: number): { { number } }
			local out: { { number } } = {}
			local function add(x: number, z: number)
				local last = out[#out]
				if last == nil or math.abs(last[1] - x) + math.abs(last[2] - z) > 0.5 then
					table.insert(out, { x, z })
				end
			end
			if math.abs(z0 - B.walkZ) > 0.5 then
				add(math.clamp(x0, west[1], east[1]), B.walkZ)
			end
			add(math.clamp(x1, west[1], east[1]), B.walkZ)
			add(x1, z1)
			return out
		end,
		door = west,
		doors = { west, east },
	}
end

-- the door of `room` nearest (x, z)
local function doorOf(room: Room, x: number, z: number): { number }
	local doors = room.doors
	if doors == nil then
		return room.door
	end
	local best, bestD = room.door, math.huge
	for _, d in doors do
		local dd = (d[1] - x) ^ 2 + (d[2] - z) ^ 2
		if dd < bestD then
			best, bestD = d, dd
		end
	end
	return best
end

function WalkWay.new(opts: Opts): Way
	local data = opts.data
	local c = opts.colliders or Colliders.fromData(data)
	WalkWay.addFences(c, data)
	addDecks(c, data)
	addBakedVenues(c, data)
	addCountry(c)
	addEmbankments(c)
	addPlinths(c, data)
	addFootings(c)
	addLookoutHill(c)
	local alleyPlace = AlleyStaff.placeOf(data)
	if alleyPlace then
		addAlleyNeighbours(c, alleyPlace)
	end
	local river = Height.RIVER
	local S = Height.STUDS_PER_UNIT
	local B = WalkWay.BRIDGE
	local foot = FootPath.new({
		colliders = c,
		bounds = opts.bounds or WalkWay.bounds(),
		minHeight = WalkWay.LOW,
		areas = true,
		-- nobody walks through the river; over it only by the bridge's walk line (the link, door to door)
		links = { { B.x0 - B.out, B.walkZ, B.x1 + B.out, B.walkZ } },
		isBlocked = function(x: number, z: number): boolean
			return Ground.surfaceKind(x, z) ~= "terrain"
		end,
		blockedBox = {
			minX = river.startX * S,
			maxX = river.endX * S,
			minZ = river.zMin * S,
			maxZ = river.zMax * S,
		},
	})
	local way: Way = { colliders = c, foot = foot, rooms = {}, roomOf = {} }
	local function add(room: Room)
		table.insert(way.rooms, room)
		way.roomOf[room.id] = room
	end
	add(bridgeRoom())
	local alley = AlleyStaff.placeOf(data)
	if alley then
		local ox, oz = AlleyWalk.outside(alley)
		add({
			id = "bowling_alley",
			inside = function(x: number, z: number): boolean
				return AlleyStaff.inside(alley, x, z)
			end,
			within = function(x0: number, z0: number, x1: number, z1: number): { { number } }
				return AlleyWalk.way(alley, x0, z0, x1, z1)
			end,
			door = { ox, oz },
		})
	end
	local layout = opts.hospital or HospitalLayout.fromData(data)
	if layout then
		local entrance, outside = layout.entrance, layout.outside
		add({
			id = "hospital_main",
			inside = function(x: number, z: number): boolean
				return HospitalLayout.contains(layout, x, z)
			end,
			within = function(x0: number, z0: number, x1: number, z1: number): { { number } }
				-- (the spot outside the door is the door's own lane on to the entrance)
				local function inner(x: number, z: number): (number, number)
					if HospitalLayout.contains(layout, x, z) then
						return x, z
					end
					return entrance[1], entrance[2]
				end
				local ax, az = inner(x0, z0)
				local bx, bz = inner(x1, z1)
				local out: { { number } } = {}
				if ax ~= x0 or az ~= z0 then
					table.insert(out, { ax, az })
				end
				for _, p in HospitalLayout.walk(layout, ax, az, bx, bz) do
					table.insert(out, p)
				end
				if bx ~= x1 or bz ~= z1 then
					table.insert(out, { x1, z1 })
				end
				return out
			end,
			door = { outside[1], outside[2] },
			settle = settleOn(layout.lanes),
		})
	end
	-- the police station: the locker room's way out (StaffRounds.POLICE_EXIT, from the lot's centre)
	local station = data:lot("west_police_station")
	if station then
		for _, b in c.boxes do
			if b.id == station.id then
				local chain = {}
				for _, p in StaffRounds.POLICE_EXIT do
					table.insert(chain, { station.x + p[1], station.z + p[2] })
				end
				-- the locker room's rounds (both mirror images: Brains/Staff walks StaffRounds.points)
				local sx, sz = station.x + StaffRounds.POLICE.x, station.z + StaffRounds.POLICE.z
				add(boxRoom(station.id, b, chain, { StaffRounds.points(sx, sz, 1), StaffRounds.points(sx, sz, 2) }))
				break
			end
		end
	end
	-- the built venues with a counter staffed by a town worker: the post's way round the counter and out
	for _, v in StaffRounds.venues(data:module("Expansion")) do
		local post = v.post
		if post and post.exit then
			for _, b in c.boxes do
				if b.id == v.id then
					local round = {}
					for _, r in post.round do
						table.insert(round, { post.x + r[1], post.z + r[2] })
					end
					add(boxRoom(v.id, b, post.exit, { round }))
					break
				end
			end
		end
	end
	return way
end

-- the box with no ways inside that holds (x, z) (inside its walls by `margin`, default MARGIN), if any
function WalkWay.solidAt(way: Way, x: number, z: number, margin: number?): Colliders.Box?
	local m = margin or WalkWay.MARGIN
	for _, b in Colliders.query(way.colliders, x, z, x, z) do
		if
			way.roomOf[b.id] == nil
			and b.eave - b.y0 >= WalkWay.LOW
			and math.abs(x - b.cx) < b.hw - m
			and math.abs(z - b.cz) < b.hd - m
		then
			return b
		end
	end
	return nil
end

-- the building with ways inside that holds (x, z), if any
function WalkWay.roomAt(way: Way, x: number, z: number): Room?
	for _, room in way.rooms do
		if room.inside(x, z) then
			return room
		end
	end
	return nil
end

-- is (x, z) inside any box a walker cannot pass (by any margin; a building with ways' box too)?
local function inWalls(way: Way, x: number, z: number): boolean
	for _, b in Colliders.query(way.colliders, x, z, x, z) do
		if b.eave - b.y0 >= WalkWay.LOW and math.abs(x - b.cx) < b.hw and math.abs(z - b.cz) < b.hd then
			return true
		end
	end
	return false
end

local function push(points: { { number } }, x: number, z: number)
	local last = points[#points]
	if last and math.abs(last[1] - x) + math.abs(last[2] - z) < 0.5 then
		return
	end
	table.insert(points, { x, z })
end

-- clear: can a body walk straight from one point to the other? Not into or out of a building (that goes by its
-- door), not across any box or closed ground.
function WalkWay.clear(way: Way, x0: number, z0: number, x1: number, z1: number): boolean
	if WalkWay.roomAt(way, x0, z0) or WalkWay.roomAt(way, x1, z1) then
		return false
	end
	-- (an end inside a wall at all, however little, is in the box: never a straight line through the rest of it; a
	-- building with ways too, outside its ways: its front wall's base, say)
	if inWalls(way, x0, z0) or inWalls(way, x1, z1) then
		return false
	end
	-- (an end within a walker's half width of a wall may cross that margin, never the wall)
	local skip = FootPath.boxesAt(way.foot, x0, z0)
	local atGoal = FootPath.boxesAt(way.foot, x1, z1)
	if atGoal then
		local set = skip or {}
		for b in atGoal do
			set[b] = true
		end
		skip = set
	end
	return FootPath.clear(way.foot, x0, z0, x1, z1, skip)
end

-- find: the way on foot from (x0, z0) to (x1, z1) (see the header), or nil. A goal inside a solid box is taken
-- to the nearest spot outside it (putBack): the way ends there. With opts.partial, a search out of budget gives the
-- way as far as it got (the third result true): the walker walks it and asks again from its end.
function WalkWay.find(
	way: Way,
	x0: number,
	z0: number,
	x1: number,
	z1: number,
	opts: FootPath.FindOpts?
): ({ { number } }?, number, boolean?)
	-- a goal inside a solid box (a spot by a fence that falls in its panel's box) is the nearest spot outside it
	if WalkWay.roomAt(way, x1, z1) == nil and WalkWay.solidAt(way, x1, z1) then
		x1, z1 = WalkWay.putBack(way, x1, z1)
	end
	local r0, r1 = WalkWay.roomAt(way, x0, z0), WalkWay.roomAt(way, x1, z1)
	if r0 and r0 == r1 then
		local inside = r0.within(x0, z0, x1, z1)
		return inside, FootPath.length(x0, z0, inside)
	end
	local points: { { number } } = {}
	local sx, sz = x0, z0
	if r0 then
		local door = doorOf(r0, x1, z1)
		for _, p in r0.within(x0, z0, door[1], door[2]) do
			push(points, p[1], p[2])
		end
		sx, sz = door[1], door[2]
	end
	local ex, ez = x1, z1
	if r1 then
		local door = doorOf(r1, sx, sz)
		ex, ez = door[1], door[2]
	end
	if WalkWay.solidAt(way, sx, sz) or WalkWay.solidAt(way, ex, ez) then
		return nil, 0
	end
	local o: FootPath.FindOpts? = opts
	local pre = FootPath.length(x0, z0, points)
	if opts and opts.maxLength then
		o = { maxNodes = opts.maxNodes, maxLength = opts.maxLength - pre, partial = opts.partial }
	end
	local mid, _, partial = FootPath.find(way.foot, sx, sz, ex, ez, o)
	if mid == nil then
		return nil, 0
	end
	for _, p in mid do
		push(points, p[1], p[2])
	end
	if partial then
		-- (out of budget: the way as far as it got; the walker asks again from its end)
		return points, FootPath.length(x0, z0, points), true
	end
	if r1 then
		for _, p in r1.within(ex, ez, x1, z1) do
			push(points, p[1], p[2])
		end
	end
	if #points == 0 then
		points = { { x1, z1 } }
	end
	local len = FootPath.length(x0, z0, points)
	if opts and opts.maxLength and len > opts.maxLength then
		return nil, 0
	end
	return points, len
end

-- putBack: where a body a player left at (x, z) is let go to the computer. Anywhere it can walk from, it stays;
-- inside a box that has no ways inside (a solid lot: a house shell, a shop), it is the nearest spot outside that
-- box's walls (a walker's half width and a little more out), on open ground; inside a building with ways, more than
-- KEEP from them (behind the corner store's till, in the police station's lobby), the nearest point on them. The
-- third and fourth results are the way out of the wall it was moved past (0, 0 when it stays).
function WalkWay.putBack(way: Way, x: number, z: number): (number, number, number, number)
	local room = WalkWay.roomAt(way, x, z)
	if room then
		if room.settle then
			local sx, sz = room.settle(x, z)
			return sx, sz, 0, 0
		end
		return x, z, 0, 0
	end
	local b = WalkWay.solidAt(way, x, z, 0)
	if b == nil then
		return x, z, 0, 0
	end
	local out = FootPath.RADIUS + 1.5
	local best, bx, bz, nx, nz = math.huge, x, z, 0, 0
	local tries = {
		{ b.cx - b.hw - out, z, -1, 0 },
		{ b.cx + b.hw + out, z, 1, 0 },
		{ x, b.cz - b.hd - out, 0, -1 },
		{ x, b.cz + b.hd + out, 0, 1 },
		{ b.cx - b.hw - out, b.cz - b.hd - out, -1, 0 },
		{ b.cx + b.hw + out, b.cz - b.hd - out, 1, 0 },
		{ b.cx - b.hw - out, b.cz + b.hd + out, -1, 0 },
		{ b.cx + b.hw + out, b.cz + b.hd + out, 1, 0 },
	}
	for _, p in tries do
		local d = (p[1] - x) ^ 2 + (p[2] - z) ^ 2
		if
			d < best
			and WalkWay.solidAt(way, p[1], p[2]) == nil
			and WalkWay.roomAt(way, p[1], p[2]) == nil
			and FootPath.boxesAt(way.foot, p[1], p[2]) == nil
		then
			best, bx, bz, nx, nz = d, p[1], p[2], p[3], p[4]
		end
	end
	return bx, bz, nx, nz
end

-- posts(data): the telephone poles and the trees' trunks (the harvested routes of kind "trunk": a pole or a tree
-- stands on each one's foot), { x, z, radius }. Props a walker steps round, not walls: a lane is never cut for one.
WalkWay.POST_RADIUS = 1.25 -- studs: a trunk route's surface radius when it names none
function WalkWay.posts(data: any): { { number } }
	local ok, registry = pcall(function()
		return data:routes()
	end)
	local out: { { number } } = {}
	if not ok or registry == nil then
		return out
	end
	for _, r in registry:all() do
		local pts = r.points
		if r.kind == "trunk" and pts and #pts >= 2 then
			local a, b = pts[1], pts[2]
			local foot = if b.y < a.y then b else a
			-- (upright at its foot: a trunk, not a fallen log or a slanted limb)
			if math.abs(b.y - a.y) > 2 * math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2) then
				table.insert(out, { foot.x, foot.z, math.max(r.surfaceRadius or 0, WalkWay.POST_RADIUS) })
			end
		end
	end
	return out
end

WalkWay.DODGE_CLEAR = 1.2 -- studs between a post's side and a walker's centre line stepping round it
WalkWay.DODGE_MIN = 1.5 -- studs: the least step aside

-- dodges(posts, lane): the posts standing on a lane (nearer its line than radius + DODGE_CLEAR), in order along it:
-- { u, off }, off the step aside (to the side away from the post) that clears it. nil when none.
function WalkWay.dodges(posts: { { number } }, lane: Lane): { { number } }?
	local out: { { number } } = {}
	for _, p in posts do
		local u, c = if lane.axis == "x" then p[1] else p[2], if lane.axis == "x" then p[2] else p[1]
		local d = c - lane.fixed
		local need = p[3] + WalkWay.DODGE_CLEAR
		if math.abs(d) < need and u >= lane.min - need and u <= lane.max + need then
			local side = if d > 0 then -1 else 1
			table.insert(out, { u, side * math.max(WalkWay.DODGE_MIN, need - math.abs(d)) })
		end
	end
	if #out == 0 then
		return nil
	end
	table.sort(out, function(a: { number }, b: { number }): boolean
		return a[1] < b[1]
	end)
	return out
end

-- splitLane: the pieces of a straight lane (Server/Actors/Nav lanes, Brains/Pedestrian) that miss every obstacle
-- (each box grown by a walker's half width): a sidewalk that runs into a building's front, a trolley stop's shelter
-- standing on it, or a fence across it is walked up to, never through. Pieces shorter than LANE_MIN are dropped.
function WalkWay.splitLane(way: Way, lane: Lane): { Lane }
	local r = FootPath.RADIUS
	local cuts: { { number } } = {}
	local minX, maxX, minZ, maxZ
	if lane.axis == "x" then
		minX, maxX, minZ, maxZ = lane.min, lane.max, lane.fixed, lane.fixed
	else
		minX, maxX, minZ, maxZ = lane.fixed, lane.fixed, lane.min, lane.max
	end
	for _, b in Colliders.query(way.colliders, minX - r, minZ - r, maxX + r, maxZ + r) do
		if b.eave - b.y0 < WalkWay.LOW then
			continue
		end
		if lane.axis == "x" then
			if math.abs(lane.fixed - b.cz) < b.hd + r then
				table.insert(cuts, { b.cx - b.hw - r, b.cx + b.hw + r })
			end
		elseif math.abs(lane.fixed - b.cx) < b.hw + r then
			table.insert(cuts, { b.cz - b.hd - r, b.cz + b.hd + r })
		end
	end
	table.sort(cuts, function(a, b)
		return a[1] < b[1]
	end)
	local out: { Lane } = {}
	local from = lane.min
	local function piece(a: number, b: number)
		if b - a >= WalkWay.LANE_MIN then
			table.insert(
				out,
				{ axis = lane.axis, fixed = lane.fixed, min = a, max = b, inward = lane.inward, dodges = nil }
			)
		end
	end
	for _, cut in cuts do
		if cut[1] > from then
			piece(from, math.min(cut[1], lane.max))
		end
		from = math.max(from, cut[2])
		if from >= lane.max then
			break
		end
	end
	if from < lane.max then
		piece(from, lane.max)
	end
	return out
end

return WalkWay
