--!strict
-- tools/games/paintball/arena/Reach: where a body can walk in an arena, found by walking it (checklist PB-5,
-- PB-10). Every square stud of the building where a body can stand is a cell; from team 1's first spawn point
-- the walk spreads to a neighbouring cell when the floor there is within Arena.STEP_UP of the floor here (up
-- or down: no drops, no jumps) and nothing solid stands between the two at chest height. It climbs the stairs
-- because a ramp rises less than that a stud. What it gives back says whether the building has a room nobody
-- can walk into, and whether the navigation graph has a node near everywhere a body can be.
-- Pure. Interface: survey(arena) -> Survey { cells (standable, on a storey's floor), walked (of those, reached
--   on foot), unreached = { { x, y, z } } (standable and never reached), far = { { x, y, z, d } } (reached, outside
--   the stair cores, and further than FAR studs from every node of its storey), farthest (the largest such
--   distance met), perLevel = { walked cells by storey } }
local Arena = require("../../../../src/shared/Minigames/Paintball/Arena")
local NavBuild = require("./NavBuild")

local Reach = {}

Reach.FAR = 14 -- studs: no place a body can stand is further than this from a node of its storey

export type Survey = {
	cells: number,
	walked: number,
	unreached: { { number } },
	far: { { number } },
	farthest: number,
	perLevel: { number },
}

function Reach.survey(arena: Arena.Arena): Survey
	local sweep, ground = arena.sweep, arena.ground
	local H = Arena.FLOOR_HEIGHT
	local half = Arena.HALF
	local size = 2 * half
	-- a cell is (ix, iz) and the floor's height in half studs: a flight and the floor under it are two cells
	local function key(ix: number, iz: number, g: number): number
		return (math.floor(g * 2 + 0.5) * size + ix) * size + iz
	end
	local function centre(i: number): number
		return i - half + 0.5
	end
	local start = arena.spawns[1][1]
	local sx, sz = math.floor(start.x + half), math.floor(start.z + half)
	local visited: { [number]: boolean } = { [key(sx, sz, start.y)] = true }
	local queue: { number } = { sx, sz, start.y }
	local head = 1
	while head <= #queue do
		local ix, iz, g = queue[head], queue[head + 1], queue[head + 2]
		head += 3
		local x, z = centre(ix), centre(iz)
		for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
			local jx, jz = ix + d[1], iz + d[2]
			if jx < 0 or jx >= size or jz < 0 or jz >= size then
				continue
			end
			local nx, nz = centre(jx), centre(jz)
			local e = ground(nx, g, nz)
			if e == nil or math.abs(e - g) > Arena.STEP_UP then
				continue
			end
			local k = key(jx, jz, e)
			if visited[k] then
				continue
			end
			local c = Arena.CHEST
			if sweep(x, g + c, z, nx, e + c, nz) ~= nil then
				continue
			end
			if NavBuild.standable(sweep, ground, nx, e, nz) == nil then
				continue
			end
			visited[k] = true
			table.insert(queue, jx)
			table.insert(queue, jz)
			table.insert(queue, e)
		end
	end
	-- every cell of every storey's own floor
	local out: Survey = { cells = 0, walked = 0, unreached = {}, far = {}, farthest = 0, perLevel = {} }
	local byFloor: { [number]: { Arena.NavNode } } = {}
	for _, node in arena.nodes do
		byFloor[node.floor] = byFloor[node.floor] or {}
		table.insert(byFloor[node.floor], node)
	end
	for level = 0, Arena.FLOORS - 1 do
		local walked = 0
		for ix = 0, size - 1 do
			for iz = 0, size - 1 do
				local x, z = centre(ix), centre(iz)
				local g = NavBuild.standable(sweep, ground, x, level * H, z)
				if g == nil or g > level * H + Arena.STEP_UP or ground(x, g, z) ~= g then
					continue
				end
				out.cells += 1
				if not visited[key(ix, iz, g)] then
					table.insert(out.unreached, { x, g, z })
					continue
				end
				walked += 1
				local inCore = math.abs(x) < Arena.ATRIUM + 1 and math.abs(z) > 21 and math.abs(z) < 31
				local best = math.huge
				for _, node in byFloor[level] or {} do
					best = math.min(best, (node.x - x) ^ 2 + (node.z - z) ^ 2)
				end
				best = math.sqrt(best)
				if not inCore then
					out.farthest = math.max(out.farthest, best)
					if best > Reach.FAR then
						table.insert(out.far, { x, g, z, best })
					end
				end
			end
		end
		out.walked += walked
		out.perLevel[level + 1] = walked
	end
	return out
end

return Reach
