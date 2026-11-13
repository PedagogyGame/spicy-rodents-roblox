--!strict
-- tests/lib/HumanWalk: where a person (a Roblox R15 Humanoid: a body 2 studs wide and 5.2 tall, stepping over what is
-- lower than 0.75, jumping about 7.2) can get to on a baked world (tests/lib/BakedWorld), by a flood fill over a grid
-- of cells in plan, each cell standing at the height of the first surface a person meets under its body. What stops a
-- person is a colliding part whose collision group meets a body's (Default: Shared/World/CollisionGroups; the alley
-- roof's people fence does, its squirrel fence does not); the ground under no part is the terrain (with the bake's
-- carve boxes).
--   HumanWalk.fill(world, start, opts) -> Reach   start: world {x, y, z} (the feet)
--     opts.x0, x1, z0, z1   the world rectangle searched (cells outside it are not entered)
--     opts.cell             the grid (default 0.5)
--     opts.jump             also jump (up to JUMP, one or two cells over, the body clear up, across and down) and fall
--                           any height (default: walk only, stepping up STEP and down at most DROP)
--     opts.stop(x, y, z)    a state the fill reaches but does not go on from (true = stop there)
--   Reach.at(x, z) -> { number }   the feet heights reached in the cell holding (x, z)
--   Reach.states -> { { x, y, z } } every state reached (the cell's centre and its feet)
-- Pure Lune.
local CollisionGroups = require("@shared/World/CollisionGroups")

local HumanWalk = {}

HumanWalk.HALF = 1.0
HumanWalk.STEP = 0.75
HumanWalk.HEAD = 5.2
HumanWalk.DROP = 1.0
HumanWalk.JUMP = 7.2

export type Reach = {
	states: { { number } },
	at: (x: number, z: number) -> { number },
}

export type Options = {
	x0: number,
	x1: number,
	z0: number,
	z1: number,
	cell: number?,
	jump: boolean?,
	stop: ((x: number, y: number, z: number) -> boolean)?,
}

local AXES = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
local JUMPS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 }, { 2, 0 }, { -2, 0 }, { 0, 2 }, { 0, -2 } }

local function personSolid(p: any): boolean
	return p.collide and CollisionGroups.solidToPeople(p.group)
end

-- the first surface a person meets going down from `top` at (x, z), down to `bottom` (else nil): under any part of the
-- body (its centre and four points near its corners), as a Humanoid's box rests on an edge it overhangs
local CORNERS = { { 0, 0 }, { 0.8, 0.8 }, { 0.8, -0.8 }, { -0.8, 0.8 }, { -0.8, -0.8 } }
local function surface(world: any, x: number, z: number, top: number, bottom: number): number?
	local best: number? = nil
	for _, c in CORNERS do
		local px, pz = x + c[1], z + c[2]
		local t = world.raycast(px, top, pz, 0, bottom - top, 0, personSolid)
		local terrain = world.terrainAt(px, pz)
		local y = if t then top + (bottom - top) * t else nil
		if terrain <= top and terrain >= bottom and (y == nil or terrain > y) then
			y = terrain
		end
		if y and (best == nil or y > best) then
			best = y
		end
	end
	return best
end

-- is the body clear standing at (x, z) with its feet at y (and, rising from `from`, all the way up)?
local function clear(world: any, x: number, z: number, y: number, from: number?): boolean
	local lo = (from or y) + HumanWalk.STEP
	local hi = y + HumanWalk.HEAD
	if hi <= lo then
		return true
	end
	local hits = world.overlapBox(
		x,
		(lo + hi) / 2,
		z,
		AXES,
		{ HumanWalk.HALF - 0.02, (hi - lo) / 2, HumanWalk.HALF - 0.02 },
		personSolid
	)
	return #hits == 0
end

-- is the body clear moving level from (ax, az) to (bx, bz) with its feet at y (a box over both)?
local function across(world: any, ax: number, az: number, bx: number, bz: number, y: number): boolean
	local lo, hi = y + HumanWalk.STEP, y + HumanWalk.HEAD
	local h = HumanWalk.HALF - 0.02
	local hits = world.overlapBox(
		(ax + bx) / 2,
		(lo + hi) / 2,
		(az + bz) / 2,
		AXES,
		{ math.abs(bx - ax) / 2 + h, (hi - lo) / 2, math.abs(bz - az) / 2 + h },
		personSolid
	)
	return #hits == 0
end

function HumanWalk.fill(world: any, start: { number }, opts: Options): Reach
	local cell = opts.cell or 0.5
	local nx = math.floor((opts.x1 - opts.x0) / cell)
	local nz = math.floor((opts.z1 - opts.z0) / cell)
	local function centre(i: number, j: number): (number, number)
		return opts.x0 + (i - 0.5) * cell, opts.z0 + (j - 0.5) * cell
	end
	local seen: { [number]: { number } } = {}
	local states: { { number } } = {}
	local queue: { { number } } = {}
	local function key(i: number, j: number): number
		return j * (nx + 2) + i
	end
	local function visit(i: number, j: number, y: number): boolean
		local k = key(i, j)
		local list = seen[k]
		if list == nil then
			list = {}
			seen[k] = list
		end
		for _, h in list do
			if math.abs(h - y) < 0.2 then
				return false
			end
		end
		table.insert(list, y)
		local x, z = centre(i, j)
		table.insert(states, { x, y, z })
		if not (opts.stop and opts.stop(x, y, z)) then
			table.insert(queue, { i, j, y })
		end
		return true
	end
	local si = math.floor((start[1] - opts.x0) / cell) + 1
	local sj = math.floor((start[3] - opts.z0) / cell) + 1
	local sx, sz = centre(si, sj)
	local sy = surface(world, sx, sz, start[2] + HumanWalk.STEP, start[2] - HumanWalk.DROP)
	assert(sy ~= nil, "HumanWalk.fill: no ground under the start")
	visit(si, sj, sy)
	local head = 1
	while head <= #queue do
		local q = queue[head]
		head += 1
		local i, j, y = q[1], q[2], q[3]
		for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local ni, nj = i + d[1], j + d[2]
			if ni >= 1 and ni <= nx and nj >= 1 and nj <= nz then
				local x, z = centre(ni, nj)
				-- walking: the first surface under the step's height, no more than DROP below
				local g = surface(world, x, z, y + HumanWalk.STEP, y - HumanWalk.DROP)
				if g and clear(world, x, z, g) then
					visit(ni, nj, g)
				end
			end
		end
		if opts.jump then
			-- jumping one or two cells over onto something up to JUMP higher, or falling off: up in this cell, across
			-- at the higher of the two heights, down onto the first surface under the jump's top (any height below)
			for _, d in JUMPS do
				local ni, nj = i + d[1], j + d[2]
				if ni >= 1 and ni <= nx and nj >= 1 and nj <= nz then
					local x, z = centre(ni, nj)
					local jg = surface(world, x, z, y + HumanWalk.JUMP, y - 1000)
					if jg then
						local cx, cz = centre(i, j)
						local top = math.max(jg, y)
						local ok = clear(world, cx, cz, top, y)
							and across(world, cx, cz, x, z, top)
							and clear(world, x, z, top, jg)
						if ok then
							visit(ni, nj, jg)
						end
					end
				end
			end
		end
	end
	return {
		states = states,
		at = function(x: number, z: number): { number }
			local i = math.floor((x - opts.x0) / cell) + 1
			local j = math.floor((z - opts.z0) / cell) + 1
			return seen[key(i, j)] or {}
		end,
	}
end

return HumanWalk
