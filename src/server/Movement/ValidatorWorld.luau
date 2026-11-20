--!strict
-- ServerScriptService.Server.Movement.ValidatorWorld
-- The world the live server's MoveValidator judges squirrel packets against (spike S3; Boot/Game.movement):
--   * the rails: the same Registry, SpatialIndex, Graph and trampoline sites every rail user shares
--     (Shared/Movement/RailWorld over Shared/Data: the harvest's routes, the bowling alley's ball returns and roof
--     route, the storm drains, the hollow trees and the fallen log, each with its enclosure record);
--   * walls (`crosses`, the envelope's wall-pass test) from rays through the baked town on the server: a move is
--     through a wall only when every one of six rays along it is stopped: at the body's lowest core height and above
--     the highest point it could have reached (a leap over a fence is not a wall), each along the centre line and
--     C.SIDE to either side (a corner the honest body rounded, a thin pole, a window it went through are not); and
--     only for a move of at most C.MAX_CHORD studs (a longer gap could have gone round a corner);
--   * the floor (`floorBelow`): something under a grounded body's feet within C.FLOOR_DEPTH (vehicles drawn a little
--     behind the server's), or the river's water; the colliding parts, the terrain and the town's non-colliding ground
--     plates the client's motor stands on as drawn (Shared/World/GroundPlate: up to 3.3 st over the terrain, measured).
-- What the client's motor treats as a wall (Client/World/ClientWorld) and what these rays see must agree in one
-- direction only: a ray may miss a wall the client sees (that lets a cheat through, it never snaps an honest body),
-- it must never stop where the client's body went. So the engine's wall ray looks past a tree's invisible bough
-- cylinders (ClientWorld.isBough), the bodies, the vehicles and the terrain (no wall for the client), and runs in the
-- squirrel's collision group (Shared/World/CollisionGroups.SQUIRREL_PROBE). For floors the direction is the other one:
-- the server's floor ray must meet every floor the client stands on, and the client's ground (ClientWorld.groundAt) is
-- the first colliding part under the feet, a bough cylinder included (a drop, Q, off a branch stands the body on its
-- bough's cylinder; validator round 6: the floor ray looked past them and snapped 515 of 766 drops). So the floor ray
-- counts the bough cylinders as floor, and only the cover check (a roof over a wall's far end) looks past them, as the
-- wall ray does: a bough over a garden wall is no roof. One rule decides what each ray stops at (stops), and the
-- specs' rays over the baked parts use it too (tests/lib/BakedWorld.validatorRays), so they see what the server sees.
-- The town's cars (owner's playtest 2026-11-18: "I did run right through a car"): they are no parts on the server, and
-- the client's motor now treats the cars it draws as walls and their roofs as ground (Shared/Traffic/Solid). So the
-- rays meet the traffic service's car boxes as well (opts.cars, Server/Traffic/TrafficService.solids): the walls only
-- where a car has stood still long enough for every client to draw it there (a moving car, drawn behind where the
-- server has it, is never a wall: no honest body is snapped for it), the floors wherever a client may still draw one
-- (withCars).
-- Interface: build(rail, opts?) -> World (MoveValidator's world; opts.wall, opts.down, opts.cover: Ray (cover: the down
--   ray the roof check casts, default `down`); opts.cars: { walls, floors },
--   Traffic/Solid sets); withCars(wall?, down?, cars) -> (wall?, down?); crosses(wall, down?) ->
--   (x0, z0, x1, z1, yLow, yHigh?, rise?, endY?) -> boolean (a rise only as high as the far end is open above:
--   cover(down) -> (x, z, footY, top) -> number?); crossesLong(wall, down?) -> the same, chord by chord, for any
--   length; around(wall, down?) -> the same args -> boolean (a way round a corner is clear: two legs via a corner);
--   floor(down, depth?, above?) -> (x, y, z) -> boolean (the world's floorBelow); floorNear(down) (C.FLOOR_NEAR under,
--   C.SLAB_ON over the feet);
--   stops(kind, name, parentName) -> boolean (the one rule: does a ray of `kind` "wall" | "floor" | "cover" stop at a
--   colliding part of that name under that parent);
--   the world's carFloor (x, y, z) -> boolean (a car's roof within C.CAR_SLACK under the feet, with opts.cars);
--   maxChord (the world's: C.MAX_CHORD); floorUnder(down) -> (x, y, z, depth) -> number? (the first floor's height under
--   feet at y); railReach(wall, cover) -> (x0, y0, z0, x1, y1, z1) -> boolean (a rail a body there could get onto: a
--   release's re-seat); slab(cover) -> (x0, y0, z0, x1, y1, z1, standY?) -> boolean (a move through a floor, a roof or a ceiling);
--   landable(down) ->
--   (x, y, z, depth) -> boolean (a landing a gap between packets can hide); engineRays(exclude) ->
--   (wall: Ray, down: Ray, cover: Ray) (workspace raycasts; engine only); isBough(name, parentName) -> boolean; C
-- Ray: (ox, oy, oz, dx, dy, dz) -> boolean, true when the segment origin -> origin + d meets a solid.
-- Pure but for engineRays. No side effects on require.

local Import = require("../Import")
local Height = Import.shared("World/Height") :: typeof(require("../../shared/World/Height"))
local CollisionGroups = Import.shared("World/CollisionGroups") :: typeof(require("../../shared/World/CollisionGroups"))
local Solid = Import.shared("Traffic/Solid") :: typeof(require("../../shared/Traffic/Solid"))
local GroundPlate = Import.shared("World/GroundPlate") :: typeof(require("../../shared/World/GroundPlate"))

local ValidatorWorld = {}

export type Ray = (ox: number, oy: number, oz: number, dx: number, dy: number, dz: number) -> boolean

ValidatorWorld.C = table.freeze({
	-- the body's core height over the feet (ClientWorld.STEP + PROBE_RADIUS: the narrow probe's centre)
	CORE = 0.75 + 0.35,
	-- the top of the body's box over the feet (ClientWorld.BODY_TOP), less a little
	TOP = 1.6,
	-- the side rays, either side of the centre line (inside ClientWorld.BODY_HALF 1.0)
	SIDE = 0.6,
	-- the longest move judged for walls (a 90-degree corner rounded at the body's half-width cuts a chord of about 4)
	MAX_CHORD = 4,
	-- the shortest (shorter is no move at all)
	MIN_CHORD = 0.05,
	-- the most chords a long line is judged by (crossesLong): a longer line is sampled by this many, evenly spread, so
	-- one judgement costs at most MAX_CHORDS * 6 rays whatever the line's length
	MAX_CHORDS = 16,
	-- the floor ray: from this far over the feet to FLOOR_DEPTH under them
	RAY_ABOVE = 1.5,
	FLOOR_DEPTH = 3.5,
	-- a grounded body that rose since the last packet stands on a floor this near under its feet (floorNear: the
	-- client's ground plates are up to 0.3 over the colliding surface): it rose because the floor did (the round-3
	-- review: a standing body crept up a posSlack a packet to FLOOR_DEPTH over the floor)
	FLOOR_NEAR = 0.6,
	-- studs: a grounded body this near over a car's roof the server has, with no floor within FLOOR_NEAR, is weighed a
	-- third a packet (the roof its client draws, a little behind or off the server's on a slope or a bump), not a whole
	-- flag (carFloor)
	CAR_SLACK = 1.5,
	-- the down rays that bisect the cover over the far end of a wall a leap's rise cleared (cover): its height to an
	-- eighth of the rise
	COVER_RAYS = 3,
	-- the most walls of one long line asked for the cover over their far ends (crossesLong; validator round 6: one per
	-- line let a second wall cleared over its top into a roofed house go unasked). A line within the chord bound meets
	-- two or three; a further one cleared over its top is a crossing. Cost: (COVER_RAYS + 1 + 3) rays each
	COVER_WALLS = 3,
	-- the slab test (slab; validator round 8): a top this near over the end's feet is the floor it stands on (the client's
	-- numbers against the server's ray, and a ground plate the server's plate ray counts and the client's ground does not:
	-- 0.28 st over the terrain on the quay's market square; FLOOR_NEAR, the floor check's own) ...
	SLAB_ON = 0.6,
	-- ... a move this far across is the vertical part judged in full; a longer one only its last SLAB_REACH studs across
	-- (an honest fall may have come in beside an overhang's edge: the wall test's own chord, MAX_CHORD)
	SLAB_REACH = 4,
	-- ... and a move rising less than this is no vertical move (no ray; validator round 9: every fall is judged)
	SLAB_DY = 0.05,
	-- around (validator round 9): the longest line a way round a corner is looked for on (studs). A longer line through a
	-- wall stays a gap's third (a lag spike that rounded a corner), never the held place (MovementService, invariant E).
	-- Its cost: each leg at most ceil(AROUND_MAX * 0.71 / MAX_CHORD) = 2 chords, 4 corners: at most 16 chords (96 wall
	-- rays) and C.COVER_WALLS covers per second leg
	AROUND_MAX = 8,
	-- ... and the longest line the held place is asked to reach a clean packet by after a doubtful one (studs: aroundFar,
	-- MoveValidator.reachable; a lag spike's gap round a corner, half a second at a sprint). Asked at most every
	-- MovementService.C.REACH_EVERY while a doubt stands; a longer line through a wall is no way (snapped back)
	AROUND_FAR = 16,
	-- studs: how near a rail a body must get to take it (railReach; Routes/Motion.C.airGrab, 3.4 st)
	RAIL_GRAB = 3.4,
	-- floorUnder's bisection: the most rays, and the height it stops at
	FLOOR_RAYS = 14,
	FLOOR_STEP = 0.05,
})
local C = ValidatorWorld.C

-- A tree's invisible bough cylinders (Tree_<id>.R<route>_<i>): never a wall for the squirrel (ClientWorld.isBough).
function ValidatorWorld.isBough(name: string, parentName: string): boolean
	return string.match(name, "^R%d") ~= nil and string.sub(parentName, 1, 5) == "Tree_"
end

-- stops(kind, name, parentName): does a ray of `kind` stop at a colliding part (in the squirrel's collision group) of
-- this name under a parent of this name? "floor": every one (the client's ground stands on a bough's cylinder); "wall"
-- and "cover": not a tree's bough cylinders (no wall for the client's motor; a bough over a wall is no roof).
function ValidatorWorld.stops(kind: string, name: string, parentName: string): boolean
	if kind == "floor" then
		return true
	end
	return not ValidatorWorld.isBough(name, parentName)
end

-- cover(down)(x, z, footY, top) -> number?: is (x, z) under a roof between a body's top standing there (footY + C.TOP)
-- and `top`? nil when open; else the highest height found open over it (C.COVER_RAYS down rays bisect it). Down rays
-- only (each from a height to footY + C.TOP: something whose top lies between); in the engine the cover ray, which looks
-- past a tree's bough cylinders (stops "cover"), and a trampoline's bed lies under the feet, never between.
function ValidatorWorld.cover(down: Ray): (number, number, number, number) -> number?
	return function(x: number, z: number, footY: number, top: number): number?
		local base = footY + C.TOP
		if top <= base or not down(x, top, z, 0, base - top, 0) then
			return nil
		end
		local lo, hi = base, top
		for _ = 1, C.COVER_RAYS do
			local mid = (lo + hi) / 2
			if down(x, mid, z, 0, base - mid, 0) then
				hi = mid
			else
				lo = mid
			end
		end
		return lo
	end
end

-- chordTest(wall, down?)(x0, z0, x1, z1, yLow, yHigh?, rise?, endY?, useCover) -> (crossed, coverSpent, unasked): one
-- chord of at most C.MAX_CHORD by the six rays (crosses), the cover over its far end asked only when `useCover`
-- (C.COVER_RAYS + 1 down rays and three more wall rays: 13 rays at most); `unasked`: cleared over its top where a cover
-- could have been asked but `useCover` was off
local function chordTest(
	wall: Ray,
	down: Ray?
): (
	number,
	number,
	number,
	number,
	number,
	number?,
	number?,
	number?,
	boolean
) -> (boolean, boolean, boolean)
	local covered = if down then ValidatorWorld.cover(down) else nil
	return function(
		x0: number,
		z0: number,
		x1: number,
		z1: number,
		yLow: number,
		yHigh: number?,
		rise: number?,
		endY: number?,
		useCover: boolean
	): (boolean, boolean, boolean)
		local dx, dz = x1 - x0, z1 - z0
		local len = math.sqrt(dx * dx + dz * dz)
		if len < C.MIN_CHORD or len > C.MAX_CHORD then
			return false, false, false
		end
		local px, pz = -dz / len * C.SIDE, dx / len * C.SIDE
		local low = yLow + C.CORE
		local high = (yHigh or yLow) + C.TOP + math.max(rise or 0, 0)
		local roofable = useCover and covered ~= nil and endY ~= nil
		local over = false -- a high ray passed over it
		for _, side in { 0, 1, -1 } do
			local ox, oz = x0 + px * side, z0 + pz * side
			if not wall(ox, low, oz, dx, 0, dz) then
				return false, false, false
			end
			if not over and not wall(ox, high, oz, dx, 0, dz) then
				over = true
			end
		end
		if not over then
			return true, false, false
		end
		if not roofable then
			-- (cleared over its top; `unasked`: a cover could have been asked, but the caller has none left)
			return false, false, covered ~= nil and endY ~= nil and not useCover
		end
		-- (cleared over the top: only as high as the far end is open above, the body coming down under its cover)
		local open = (covered :: any)(x1, z1, endY :: number, high)
		if open == nil then
			return false, true, false
		end
		local capped = math.max(low, open)
		for _, side in { 0, 1, -1 } do
			if not wall(x0 + px * side, capped, z0 + pz * side, dx, 0, dz) then
				return false, true, false
			end
		end
		return true, true, false
	end
end

-- crosses(wall, down?)(x0, z0, x1, z1, yLow, yHigh?, rise?, endY?): did the straight move from (x0, z0) to (x1, z1) go
-- through a wall? yLow / yHigh: the lower and higher feet of the two ends; rise: how far above yHigh the body could have
-- been in between (a leap's arc); endY: the feet at (x1, z1), where the body came down. A wall cleared over its top
-- (every low ray stopped, a high ray over it: by the arc's rise or the higher end's own height) is cleared only as high
-- as the far end is open above (the round-4 review: a leap's rise cleared a 14-stud house wall into the house under its
-- roof): with `down` and `endY`, the high rays again no higher than the cover over the far end (cover).
function ValidatorWorld.crosses(
	wall: Ray,
	down: Ray?
): (number, number, number, number, number, number?, number?, number?) -> boolean
	local one = chordTest(wall, down)
	return function(
		x0: number,
		z0: number,
		x1: number,
		z1: number,
		yLow: number,
		yHigh: number?,
		rise: number?,
		endY: number?
	): boolean
		return (one(x0, z0, x1, z1, yLow, yHigh, rise, endY, true))
	end
end

-- crossesLong(wall, down?)(x0, z0, x1, z1, yLow, yHigh?, rise?, endY?): the straight line of a gap too long for
-- crosses, judged chord by chord (each at most C.MAX_CHORD, each by the six rays; the cover over each chord's far end
-- cleared over its top, at the feet the line has there, for C.COVER_WALLS walls at most, a further one cleared over its
-- top being a crossing): did any chord go through a wall? (An honest body may have gone round a corner in the gap: the caller weighs it as such.)
-- A line longer than C.MAX_CHORDS chords is judged by that many chords spread evenly along it: the cost is bounded (a
-- line that long, 64 studs, is over a second at the fastest, judged on its reach first).
function ValidatorWorld.crossesLong(
	wall: Ray,
	down: Ray?
): (number, number, number, number, number, number?, number?, number?) -> boolean
	local one = chordTest(wall, down)
	return function(
		x0: number,
		z0: number,
		x1: number,
		z1: number,
		yLow: number,
		yHigh: number?,
		rise: number?,
		endY: number?
	): boolean
		local len = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
		if len < C.MIN_CHORD then
			return false
		end
		local n = math.ceil(len / C.MAX_CHORD)
		local step = 1 / n
		if n > C.MAX_CHORDS then
			-- (each chord C.MAX_CHORD long, their starts spread evenly)
			step = C.MAX_CHORD / len
			n = C.MAX_CHORDS
		end
		local spread = if n > 1 then (1 - step) / (n - 1) else 0
		-- (the feet at the start: the end that is not endY)
		local startY = if endY then yLow + (yHigh or yLow) - endY else nil
		local coversLeft = C.COVER_WALLS
		for i = 1, n do
			local a = (i - 1) * spread
			local b = a + step
			local y = if endY and startY then startY + (endY - startY) * b else nil
			local crossed, spent, unasked = one(
				x0 + (x1 - x0) * a,
				z0 + (z1 - z0) * a,
				x0 + (x1 - x0) * b,
				z0 + (z1 - z0) * b,
				yLow,
				yHigh,
				rise,
				y,
				coversLeft > 0
			)
			if crossed then
				return true
			end
			if spent then
				coversLeft -= 1
			elseif unasked then
				-- (a further wall cleared only over its top, with no cover left to ask: a crossing)
				return true
			end
		end
		return false
	end
end

-- around(wall, down?)(x0, z0, x1, z1, yLow, yHigh?, rise?, endY?) -> boolean: a long line through a wall (crossesLong)
-- has a way round a corner: two legs via a corner, each judged as crossesLong judges a line, one such way clear
-- (validator round 9, the round-8 review's MEDIUM: one long packet through a wall was weighed a third, as a corner
-- rounded unseen, and kept). The corners tried: the two L-shaped paths (via (x1, z0) and via (x0, z1)) and the two
-- right-angle corners in the line's own frame (its middle, half its length to either side: a corner of a building
-- that is not square to the axes). An honest gap that cut a corner has one of them clear; a line into a closed room has
-- none. The first leg is asked for no cover (its corner's height is unknown: the lenient way), the second as the line.
-- A line longer than C.AROUND_MAX is not asked (true: a gap's third, as before; invariant E keeps it from the held
-- place). Cost: only for a line already through a wall; at most 8 legs of at most 2 chords
function ValidatorWorld.around(
	wall: Ray,
	down: Ray?,
	maxLen: number?
): (number, number, number, number, number, number?, number?, number?) -> boolean
	local long = ValidatorWorld.crossesLong(wall, down)
	local most = maxLen or C.AROUND_MAX
	return function(
		x0: number,
		z0: number,
		x1: number,
		z1: number,
		yLow: number,
		yHigh: number?,
		rise: number?,
		endY: number?
	): boolean
		if (x1 - x0) ^ 2 + (z1 - z0) ^ 2 > most * most then
			return true -- (too long to tell: weighed as a gap's, never held)
		end
		local mx, mz = (x0 + x1) / 2, (z0 + z1) / 2
		local hx, hz = (x1 - x0) / 2, (z1 - z0) / 2
		for _, c in { { x1, z0 }, { x0, z1 }, { mx - hz, mz + hx }, { mx + hz, mz - hx } } do
			local cx, cz = c[1], c[2]
			if
				not long(x0, z0, cx, cz, yLow, yHigh, rise, nil)
				and not long(cx, cz, x1, z1, yLow, yHigh, rise, endY)
			then
				return true
			end
		end
		return false
	end
end

-- railReach(wall, cover)(x0, y0, z0, x1, y1, z1) -> boolean: could a body standing at (x0, y0, z0) (feet) get onto a
-- rail at (x1, y1, z1)? (Validator round 9, the round-8 review's LOW: a body let go on the street was re-seated in the
-- storm drain under it.) No wall on the way to within a rail's grab of it (C.RAIL_GRAB: the body stands at a trunk's
-- bark, not in it; crossesLong), and no floor, roof or ceiling between the heights: for a rail lower, a cover ray down
-- the far column from SLAB_ON over the feet to SLAB_ON over the rail (the street over a drain); for one higher than the
-- body's top, up the near column (a ceiling over a body let go indoors). Cost: a line's chords and one ray
function ValidatorWorld.railReach(wall: Ray, cover: Ray): (number, number, number, number, number, number) -> boolean
	local long = ValidatorWorld.crossesLong(wall, cover)
	return function(x0: number, y0: number, z0: number, x1: number, y1: number, z1: number): boolean
		local dx, dz = x1 - x0, z1 - z0
		local d = math.sqrt(dx * dx + dz * dz)
		local k = if d > C.RAIL_GRAB then (d - C.RAIL_GRAB) / d else 0
		local ex, ez = x0 + dx * k, z0 + dz * k
		if k > 0 and long(x0, z0, ex, ez, math.min(y0, y1), math.max(y0, y1), 0, y1) then
			return false
		end
		if y1 < y0 then
			return not cover(ex, y0 + C.SLAB_ON, ez, 0, y1 - y0, 0)
		elseif y1 > y0 + C.TOP then
			return not cover(x0, y0 + C.TOP, z0, 0, y1 - y0 - C.TOP, 0)
		end
		return true
	end
end

-- floor(down, depth?, above?)(x, y, z): is there something to stand on under feet at y (or the river's water), within
-- `depth` under them (default C.FLOOR_DEPTH), the ray from `above` over them (default C.RAY_ABOVE)?
function ValidatorWorld.floor(down: Ray, depth: number?, above: number?): (number, number, number) -> boolean
	local d = depth or C.FLOOR_DEPTH
	local a = above or C.RAY_ABOVE
	return function(x: number, y: number, z: number): boolean
		if Height.insideRiverWater(x, z) and y <= Height.WATER_Y + d then
			return true
		end
		return down(x, y + a, z, 0, -(a + d), 0)
	end
end

-- floorNear(down)(x, y, z): the top a grounded body stands on: within C.FLOOR_NEAR under its feet and C.SLAB_ON over
-- them (validator round 9, the round-8 review's MEDIUM: from RAY_ABOVE, 1.5 over the feet, a grounded claim sank under a
-- roof's top by steps the slab test skipped and still "stood" on it). The honest motor's feet are AT the top its ground
-- ray found (it stands on anything within 1.5 over them after every substep); SLAB_ON is the slab test's own band (a
-- ground plate the server counts and the client does not, 0.28 over the terrain). A body sunk deeper into a part has
-- the ray start inside it, which meets nothing: no floor
function ValidatorWorld.floorNear(down: Ray): (number, number, number) -> boolean
	return ValidatorWorld.floor(down, C.FLOOR_NEAR, C.SLAB_ON)
end

-- landable(down)(x, y, z, depth): is there ground within `depth` under feet at y (a landing the gap can hide)?
function ValidatorWorld.landable(down: Ray): (number, number, number, number) -> boolean
	return function(x: number, y: number, z: number, depth: number): boolean
		return down(x, y + 0.1, z, 0, -(depth + 0.1), 0)
	end
end

-- floorUnder(down)(x, y, z, depth) -> number?: the height of the first floor under feet at y within `depth` (nil: none),
-- to C.FLOOR_STEP by bisection over the down ray (at most C.FLOOR_RAYS rays: a Reset's target, rate-limited)
function ValidatorWorld.floorUnder(down: Ray): (number, number, number, number) -> number?
	return function(x: number, y: number, z: number, depth: number): number?
		local top = y + 0.1
		if not down(x, top, z, 0, -(depth + 0.1), 0) then
			return nil
		end
		local lo, hi = 0, depth + 0.1 -- (no floor within lo under top; one within hi)
		for _ = 1, C.FLOOR_RAYS do
			if hi - lo <= C.FLOOR_STEP then
				break
			end
			local mid = (lo + hi) / 2
			if down(x, top, z, 0, -mid, 0) then
				hi = mid
			else
				lo = mid
			end
		end
		return top - hi
	end
end

-- slab(ray)(x0, y0, z0, x1, y1, z1) -> boolean: did a move go through a floor, a roof or a ceiling? (validator round 8,
-- the round-7 review's MEDIUM: a fall straight down through a roof into the sealed storey under it was judged by no
-- rule: the wall rays are horizontal.) The client's motor stands on the first top its ground ray (from 1.5 over the
-- feet, RAY_ABOVE) meets, after every substep, rising (it steps up onto it) or falling (it lands): so where an honest
-- body ends, no top lies between its feet and RAY_ABOVE over them, and a fall's vertical part crossed none. One cover
-- ray (past a tree's bough cylinders: nothing to hide in; never a car: those are drawn behind) at the end's column,
-- from RAY_ABOVE over the feet, raised by the fall's drop over its last SLAB_REACH studs across, down to SLAB_ON over
-- them; a hit is a top the body went through or stands inside. Nothing in the river's water (the client's recovery).
-- A fall slanting further than SLAB_REACH across in one move (a slow link: 2 packets a second at 10 st/s) is judged
-- in full only at the height the body last stood (`standY`): a second ray, there, at the end's column (the roof it
-- stood on reaches over where it ends: it sank through it; an honest body comes in under a top lower than its floor)
-- Validator round 9 (the round-8 review's MEDIUM: a grounded claim sank under a roof's top by steps under SLAB_DY, then
-- fell from rest by steps under it, and every ray after started inside the roof, which meets nothing): every fall is
-- judged whatever its drop (SLAB_DY now gates rises only), and a fall the down ray found nothing for casts one ray up,
-- at the end's column from SLAB_ON over the end's feet to SLAB_ON over the start's: it meets a slab's underside the down
-- ray started inside (the body's own box swept that column; an honest one has nothing there). A grounded claim stands
-- within SLAB_ON under a top at most (floorNear), so the down ray starts over the top it stood on
function ValidatorWorld.slab(ray: Ray): (number, number, number, number, number, number, number?) -> boolean
	return function(x0: number, y0: number, z0: number, x1: number, y1: number, z1: number, standY: number?): boolean
		local fell = y1 < y0
		if (not fell and y1 - y0 < C.SLAB_DY) or Height.insideRiverWater(x1, z1) then
			return false
		end
		local across = math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
		local drop = math.max(0, y0 - y1)
		local part = if across <= C.SLAB_REACH then drop else drop * C.SLAB_REACH / across
		local top = y1 + C.RAY_ABOVE + part
		if ray(x1, top, z1, 0, y1 + C.SLAB_ON - top, 0) then
			return true
		end
		if standY and across > C.SLAB_REACH and standY - C.SLAB_ON > top then
			local from = standY + C.SLAB_ON
			if ray(x1, from, z1, 0, math.max(top, standY - C.SLAB_ON) - from, 0) then
				return true
			end
		end
		-- (the up ray: a slab whose top the down ray started under)
		return fell and ray(x1, y1 + C.SLAB_ON, z1, 0, drop, 0)
	end
end

-- The car boxes the rays meet (Traffic/Solid sets; exported types do not cross Import)
export type Cars = { walls: any, floors: any }

export type Options = { wall: Ray?, down: Ray?, cover: Ray?, cars: Cars? }

-- withCars(wall?, down?, cars, cover?): the rays, each also stopped by the cars' boxes (the walls set for `wall`, the
-- floors set for `down` and `cover`: a car's roof over a wall's far end is a roof); a ray the world has none of is the
-- cars' alone. The boxes are read at each ray (the sets are refilled every traffic tick).
function ValidatorWorld.withCars(wall: Ray?, down: Ray?, cars: Cars, cover: Ray?): (Ray, Ray, Ray)
	local walls, floors = cars.walls, cars.floors
	local function over(set: any, ray: Ray?): Ray
		return function(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number): boolean
			if set.n > 0 and Solid.ray(set, ox, oy, oz, dx, dy, dz) then
				return true
			end
			return ray ~= nil and ray(ox, oy, oz, dx, dy, dz)
		end
	end
	return over(walls, wall), over(floors, down), over(floors, cover or down)
end

-- build(rail, opts?): MoveValidator's world over a rail world (Movement/RailWorld: registry, index, graph,
-- trampolines). A fresh table, so Motion's caches on it are the validator's own.
function ValidatorWorld.build(rail: any, opts: Options?): any
	local o: Options = opts or {}
	local wall, down, cover = o.wall, o.down, o.cover or o.down
	local slabRay = cover -- (before the cars: a car is drawn behind the server's box)
	if o.cars then
		wall, down, cover = ValidatorWorld.withCars(wall, down, o.cars, cover)
	end
	return {
		registry = rail.registry,
		index = rail.index,
		graph = rail.graph,
		trampolines = rail.trampolines,
		groundAt = function(_x: number, _z: number, refY: number): number
			return refY
		end,
		crosses = if wall then ValidatorWorld.crosses(wall, cover) else nil,
		crossesLong = if wall then ValidatorWorld.crossesLong(wall, cover) else nil,
		around = if wall then ValidatorWorld.around(wall, cover) else nil,
		aroundFar = if wall then ValidatorWorld.around(wall, cover, C.AROUND_FAR) else nil,
		aroundFarMax = C.AROUND_FAR,
		floorBelow = if down then ValidatorWorld.floor(down) else nil,
		floorNear = if down then ValidatorWorld.floorNear(down) else nil,
		-- a car's roof within C.CAR_SLACK under the feet (the climb and float flags weigh a third there)
		carFloor = if o.cars
			then function(x: number, y: number, z: number): boolean
				local floors = (o.cars :: Cars).floors
				return floors.n > 0 and Solid.ray(floors, x, y + C.RAY_ABOVE, z, 0, -(C.RAY_ABOVE + C.CAR_SLACK), 0)
			end
			else nil,
		landable = if down then ValidatorWorld.landable(down) else nil,
		floorUnder = if down then ValidatorWorld.floorUnder(down) else nil,
		slab = if slabRay then ValidatorWorld.slab(slabRay) else nil,
		railReach = if wall and slabRay then ValidatorWorld.railReach(wall, slabRay) else nil,
		maxChord = C.MAX_CHORD, -- (the longest line `crosses` judges; a longer one is crossesLong's)
	}
end

-- engineRays(exclude): the three rays on the live server. `wall`: colliding parts in the squirrel's group, past the
-- bough cylinders, not the terrain, nor anything under `exclude` (the bodies, the vehicles). `down`: colliding parts
-- in the squirrel's group, the bough cylinders included, the terrain, the water, the vehicles and the town's ground
-- plates (Shared/World/GroundPlate) counted as floor. `cover`: `down` past the bough cylinders (stops: one rule each).
function ValidatorWorld.engineRays(exclude: { Instance }): (Ray, Ray, Ray)
	local function params(list: { Instance }): RaycastParams
		local p = RaycastParams.new()
		p.FilterType = Enum.RaycastFilterType.Exclude
		p.FilterDescendantsInstances = list
		p.RespectCanCollide = true
		pcall(function()
			p.CollisionGroup = CollisionGroups.SQUIRREL_PROBE
		end)
		return p
	end
	local wallList = table.clone(exclude)
	table.insert(wallList, workspace.Terrain)
	local wallParams = params(wallList)
	local floorList: { Instance } = {}
	for _, i in exclude do
		if i.Name ~= "Vehicles" then
			table.insert(floorList, i)
		end
	end
	local floorParams = params(floorList)
	floorParams.IgnoreWater = false
	local function cast(p: RaycastParams, kind: string): Ray
		return function(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number): boolean
			local origin = Vector3.new(ox, oy, oz)
			local left = Vector3.new(dx, dy, dz)
			for _ = 1, 4 do
				local hit = workspace:Raycast(origin, left, p)
				if hit == nil then
					return false
				end
				local part = hit.Instance
				local parent = part.Parent
				if ValidatorWorld.stops(kind, part.Name, if parent then parent.Name else "") then
					return true
				end
				-- through the bough and on along the rest of the segment
				local unit = left.Unit
				local gone = (hit.Position - origin).Magnitude + 0.02
				left = unit * math.max(0, left.Magnitude - gone)
				origin = hit.Position + unit * 0.02
				if left.Magnitude < 1e-3 then
					return false
				end
			end
			return false
		end
	end
	-- the town's ground plates (Shared/World/GroundPlate: non-colliding, laid over the terrain), which the client's motor
	-- stands on as drawn (Client/World/ClientWorld.groundAt): a floor too, or a body on a tennis court's tiles, up to
	-- 1.5 studs over the terrain, would be a climb (validator round 5: tests/unit/validator_floors.spec.luau)
	local plateParams = RaycastParams.new()
	plateParams.FilterType = Enum.RaycastFilterType.Include
	plateParams.RespectCanCollide = false
	local folders: { Instance } = {}
	local function plateFolders(): boolean
		if #folders == 0 then
			local town = workspace:FindFirstChild("Town")
			for _, n in GroundPlate.FOLDERS do
				local f = town and town:FindFirstChild(n)
				if f then
					table.insert(folders, f)
				end
			end
			plateParams.FilterDescendantsInstances = folders
		end
		return #folders > 0
	end
	local function plate(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number): boolean
		if not plateFolders() then
			return false
		end
		local origin = Vector3.new(ox, oy, oz)
		local left = Vector3.new(dx, dy, dz)
		for _ = 1, 4 do
			local hit = workspace:Raycast(origin, left, plateParams)
			if hit == nil then
				return false
			end
			local part = hit.Instance :: BasePart
			if not part.CanCollide and GroundPlate.like(part.Name, part.Size.Y, part.Transparency) then
				return true
			end
			local unit = left.Unit
			local gone = (hit.Position - origin).Magnitude + 0.02
			left = unit * math.max(0, left.Magnitude - gone)
			origin = hit.Position + unit * 0.02
			if left.Magnitude < 1e-3 then
				return false
			end
		end
		return false
	end
	local solidDown, solidCover = cast(floorParams, "floor"), cast(floorParams, "cover")
	local function down(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number): boolean
		return solidDown(ox, oy, oz, dx, dy, dz) or plate(ox, oy, oz, dx, dy, dz)
	end
	local function cover(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number): boolean
		return solidCover(ox, oy, oz, dx, dy, dz) or plate(ox, oy, oz, dx, dy, dz)
	end
	return cast(wallParams, "wall"), down, cover
end

return ValidatorWorld
