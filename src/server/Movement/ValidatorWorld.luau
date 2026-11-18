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
--   * the floor (`floorBelow`): something under a grounded body's feet within C.FLOOR_DEPTH (the client stands on
--     non-colliding ground plates up to 0.3 st above the colliding surface, and on vehicles drawn a little behind the
--     server's), or the river's water.
-- What the client's motor treats as a wall (Client/World/ClientWorld) and what these rays see must agree in one
-- direction only: a ray may miss a wall the client sees (that lets a cheat through, it never snaps an honest body),
-- it must never stop where the client's body went. So the engine rays look past a tree's invisible bough cylinders
-- (ClientWorld.isBough), the bodies, the vehicles and the terrain (no wall for the client), and run in the squirrel's
-- collision group (Shared/World/CollisionGroups.SQUIRREL_PROBE).
-- The town's cars (owner's playtest 2026-11-18: "I did run right through a car"): they are no parts on the server, and
-- the client's motor now treats the cars it draws as walls and their roofs as ground (Shared/Traffic/Solid). So the
-- rays meet the traffic service's car boxes as well (opts.cars, Server/Traffic/TrafficService.solids): the walls only
-- where a car has stood still long enough for every client to draw it there (a moving car, drawn behind where the
-- server has it, is never a wall: no honest body is snapped for it), the floors wherever a client may still draw one
-- (withCars).
-- Interface: build(rail, opts?) -> World (MoveValidator's world; opts.wall, opts.down: Ray; opts.cars: { walls, floors },
--   Traffic/Solid sets); withCars(wall?, down?, cars) -> (wall?, down?); crosses(wall) ->
--   (x0, z0, x1, z1, yLow, yHigh?, rise?) -> boolean; crossesLong(wall) -> the same, chord by chord, for any
--   length; floor(down) -> (x, y, z) -> boolean; landable(down) ->
--   (x, y, z, depth) -> boolean (a landing a gap between packets can hide); engineRays(exclude) ->
--   (wall: Ray, down: Ray) (workspace raycasts; engine only); isBough(name, parentName) -> boolean; C
-- Ray: (ox, oy, oz, dx, dy, dz) -> boolean, true when the segment origin -> origin + d meets a solid.
-- Pure but for engineRays. No side effects on require.

local Import = require("../Import")
local Height = Import.shared("World/Height") :: typeof(require("../../shared/World/Height"))
local CollisionGroups = Import.shared("World/CollisionGroups") :: typeof(require("../../shared/World/CollisionGroups"))
local Solid = Import.shared("Traffic/Solid") :: typeof(require("../../shared/Traffic/Solid"))

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
})
local C = ValidatorWorld.C

-- A tree's invisible bough cylinders (Tree_<id>.R<route>_<i>): never a wall for the squirrel (ClientWorld.isBough).
function ValidatorWorld.isBough(name: string, parentName: string): boolean
	return string.match(name, "^R%d") ~= nil and string.sub(parentName, 1, 5) == "Tree_"
end

-- crosses(wall)(x0, z0, x1, z1, yLow, yHigh?, rise?): did the straight move from (x0, z0) to (x1, z1) go through a
-- wall? yLow / yHigh: the lower and higher feet of the two ends; rise: how far above yHigh the body could have been in
-- between (a leap's arc).
function ValidatorWorld.crosses(wall: Ray): (number, number, number, number, number, number?, number?) -> boolean
	return function(
		x0: number,
		z0: number,
		x1: number,
		z1: number,
		yLow: number,
		yHigh: number?,
		rise: number?
	): boolean
		local dx, dz = x1 - x0, z1 - z0
		local len = math.sqrt(dx * dx + dz * dz)
		if len < C.MIN_CHORD or len > C.MAX_CHORD then
			return false
		end
		local px, pz = -dz / len * C.SIDE, dx / len * C.SIDE
		local low = yLow + C.CORE
		local high = (yHigh or yLow) + (rise or 0) + C.TOP
		for _, side in { 0, 1, -1 } do
			local ox, oz = x0 + px * side, z0 + pz * side
			if not wall(ox, low, oz, dx, 0, dz) or not wall(ox, high, oz, dx, 0, dz) then
				return false
			end
		end
		return true
	end
end

-- crossesLong(wall)(x0, z0, x1, z1, yLow, yHigh?, rise?): the straight line of a gap too long for crosses, judged
-- chord by chord (each at most C.MAX_CHORD, each by the six rays): did any chord go through a wall? (An honest body may
-- have gone round a corner in the gap: the caller weighs it as such.) A line longer than C.MAX_CHORDS chords is judged
-- by that many chords spread evenly along it: the cost is bounded (a line that long, 64 studs, is over a second at the
-- fastest, judged on its reach first).
function ValidatorWorld.crossesLong(wall: Ray): (number, number, number, number, number, number?, number?) -> boolean
	local one = ValidatorWorld.crosses(wall)
	return function(
		x0: number,
		z0: number,
		x1: number,
		z1: number,
		yLow: number,
		yHigh: number?,
		rise: number?
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
		for i = 1, n do
			local a = (i - 1) * spread
			local b = a + step
			if
				one(x0 + (x1 - x0) * a, z0 + (z1 - z0) * a, x0 + (x1 - x0) * b, z0 + (z1 - z0) * b, yLow, yHigh, rise)
			then
				return true
			end
		end
		return false
	end
end

-- floor(down)(x, y, z): is there something to stand on under feet at y (or the river's water)?
function ValidatorWorld.floor(down: Ray): (number, number, number) -> boolean
	return function(x: number, y: number, z: number): boolean
		if Height.insideRiverWater(x, z) and y <= Height.WATER_Y + C.FLOOR_DEPTH then
			return true
		end
		return down(x, y + C.RAY_ABOVE, z, 0, -(C.RAY_ABOVE + C.FLOOR_DEPTH), 0)
	end
end

-- landable(down)(x, y, z, depth): is there ground within `depth` under feet at y (a landing the gap can hide)?
function ValidatorWorld.landable(down: Ray): (number, number, number, number) -> boolean
	return function(x: number, y: number, z: number, depth: number): boolean
		return down(x, y + 0.1, z, 0, -(depth + 0.1), 0)
	end
end

-- The car boxes the rays meet (Traffic/Solid sets; exported types do not cross Import)
export type Cars = { walls: any, floors: any }

export type Options = { wall: Ray?, down: Ray?, cars: Cars? }

-- withCars(wall?, down?, cars): the two rays, each also stopped by the cars' boxes (the walls set for `wall`, the
-- floors set for `down`); a ray the world has none of is the cars' alone. The boxes are read at each ray (the sets are
-- refilled every traffic tick).
function ValidatorWorld.withCars(wall: Ray?, down: Ray?, cars: Cars): (Ray, Ray)
	local walls, floors = cars.walls, cars.floors
	local function over(set: any, ray: Ray?): Ray
		return function(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number): boolean
			if set.n > 0 and Solid.ray(set, ox, oy, oz, dx, dy, dz) then
				return true
			end
			return ray ~= nil and ray(ox, oy, oz, dx, dy, dz)
		end
	end
	return over(walls, wall), over(floors, down)
end

-- build(rail, opts?): MoveValidator's world over a rail world (Movement/RailWorld: registry, index, graph,
-- trampolines). A fresh table, so Motion's caches on it are the validator's own.
function ValidatorWorld.build(rail: any, opts: Options?): any
	local o: Options = opts or {}
	local wall, down = o.wall, o.down
	if o.cars then
		wall, down = ValidatorWorld.withCars(wall, down, o.cars)
	end
	return {
		registry = rail.registry,
		index = rail.index,
		graph = rail.graph,
		trampolines = rail.trampolines,
		groundAt = function(_x: number, _z: number, refY: number): number
			return refY
		end,
		crosses = if wall then ValidatorWorld.crosses(wall) else nil,
		crossesLong = if wall then ValidatorWorld.crossesLong(wall) else nil,
		floorBelow = if down then ValidatorWorld.floor(down) else nil,
		landable = if down then ValidatorWorld.landable(down) else nil,
	}
end

-- engineRays(exclude): the two rays on the live server. `wall`: colliding parts in the squirrel's group, past the
-- bough cylinders, not the terrain, nor anything under `exclude` (the bodies, the vehicles). `down`: the same, with the
-- terrain, the water and the vehicles counted as floor.
function ValidatorWorld.engineRays(exclude: { Instance }): (Ray, Ray)
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
	local function cast(p: RaycastParams): Ray
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
				if not ValidatorWorld.isBough(part.Name, if parent then parent.Name else "") then
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
	return cast(wallParams), cast(floorParams)
end

return ValidatorWorld
