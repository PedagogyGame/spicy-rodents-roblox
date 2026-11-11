--!strict
-- ReplicatedStorage.Shared.Paintball.ArenaData
-- The arena as data (checklist PB-5). OWNED BY THE ARENA LANE; `build` keeps its name and signature.
-- TODAY THIS IS A STAND-IN, so that the match, the bots, the server and the client can run against a
-- real, valid arena from the first minute: the S18 greybox (Server/Paintball/Layout: five floors 14
-- studs apart, a 30 x 30 atrium, four pillars a floor) made honest enough to pass Arena.check: rails
-- on the east and west sides of the atrium, two straight stair flights a storey inside the atrium's
-- north and south edges (step boxes under a walking ramp, a landing at each end), two spawn rooms
-- in opposite corners of the ground floor, a 5 x 5 grid of navigation nodes a floor plus stair and
-- cover nodes. It has no rooms, no real cover, and nothing in it is baked.
-- THE ARENA LANE REPLACES THE BODY OF build() with the real building (lobby and loading dock,
-- newsroom, studios, control rooms, offices; about 25 cover pieces a floor; two real stairwells a
-- storey; spawn rooms with two ways out) and hands back grid-backed `sweep` and `ground` that give
-- the reference's answers (Arena.sweepBoxes, Arena.groundAt). The bake (tools/bake/paintball.luau)
-- makes its parts FROM this data, one part per box and one invisible ramp part per ramp, so the
-- building and the collision data cannot differ.
-- Interface: build() -> Arena (a fresh table each call; pure, the same every time)

local Arena = require("./Arena")

local ArenaData = {}

function ArenaData.build(): Arena.Arena
	local KIND = Arena.KIND
	local half, h, floors, atrium = Arena.HALF, Arena.FLOOR_HEIGHT, Arena.FLOORS, Arena.ATRIUM
	local boxes: { number } = {}
	local kinds: { number } = {}
	local function box(kind: number, x0: number, y0: number, z0: number, x1: number, y1: number, z1: number)
		table.insert(boxes, math.min(x0, x1))
		table.insert(boxes, math.min(y0, y1))
		table.insert(boxes, math.min(z0, z1))
		table.insert(boxes, math.max(x0, x1))
		table.insert(boxes, math.max(y0, y1))
		table.insert(boxes, math.max(z0, z1))
		table.insert(kinds, kind)
	end
	local top = floors * h
	box(KIND.slab, -half, -1, -half, half, 0, half) -- the ground floor
	for f = 1, floors - 1 do
		local y = f * h
		box(KIND.slab, -half, y - 1, -half, half, y, -atrium)
		box(KIND.slab, -half, y - 1, atrium, half, y, half)
		box(KIND.slab, -half, y - 1, -atrium, -atrium, y, atrium)
		box(KIND.slab, atrium, y - 1, -atrium, half, y, atrium)
		-- rails on the two sides of the atrium the stairs do not use
		box(KIND.rail, -atrium - 0.5, y, -atrium, -atrium, y + Arena.RAIL_HEIGHT, atrium)
		box(KIND.rail, atrium, y, -atrium, atrium + 0.5, y + Arena.RAIL_HEIGHT, atrium)
	end
	box(KIND.slab, -half, top, -half, half, top + 1, half) -- the roof
	box(KIND.wall, -half - 1, -1, -half, -half, top + 1, half)
	box(KIND.wall, half, -1, -half, half + 1, top + 1, half)
	box(KIND.wall, -half, -1, -half - 1, half, top + 1, -half)
	box(KIND.wall, -half, -1, half, half, top + 1, half + 1)
	local pillars = { { -35, -35 }, { 35, -35 }, { 35, 35 }, { -35, 35 } }
	for f = 0, floors - 1 do
		for _, c in pillars do
			box(KIND.pillar, c[1] - 2, f * h, c[2] - 2, c[1] + 2, f * h + h - 1, c[2] + 2)
		end
	end

	-- two stair flights a storey, inside the atrium: the north one rises towards +x, the south one
	-- towards -x; each is 14 steps under a ramp, with a landing level with the floor at each end
	local RUN, STEPS = 21, 14
	local ramps: { Arena.Ramp } = {}
	local stairEnds: { { number } } = {} -- { floor, lowX, highX, z }
	for f = 0, floors - 2 do
		local y0, y1 = f * h, (f + 1) * h
		for _, side in { -1, 1 } do
			local dir = -side -- north (z < 0) rises towards +x
			local zIn, zOut = side * (atrium - 4), side * atrium
			local z0, z1 = math.min(zIn, zOut), math.max(zIn, zOut)
			table.insert(ramps, {
				minX = -RUN / 2,
				minZ = z0,
				maxX = RUN / 2,
				maxZ = z1,
				y0 = y0,
				y1 = y1,
				axis = "x",
				dir = dir,
			})
			local run = RUN / STEPS
			for k = 0, STEPS - 1 do
				-- step k from the low end: its top is the ramp's height where the step begins
				local xa = -dir * RUN / 2 + dir * run * k
				box(KIND.step, xa, y0 + k * (h / STEPS) - 1, z0, xa + dir * run, y0 + k * (h / STEPS), z1)
			end
			local lowX, highX = -dir * (RUN / 2), dir * (RUN / 2)
			if f > 0 then
				box(KIND.slab, lowX, y0 - 1, z0, -dir * atrium, y0, z1) -- the landing at the foot
			end
			box(KIND.slab, highX, y1 - 1, z0, dir * atrium, y1, z1) -- the landing at the head
			table.insert(stairEnds, { f, (lowX - dir * atrium) / 2, (highX + dir * atrium) / 2, side * (atrium - 2) })
		end
	end

	local parts: Arena.Parts = {
		boxes = boxes,
		kinds = kinds,
		ramps = ramps,
		spawns = {},
		spawnRooms = {},
		exits = {},
		lobby = { x = -14, y = 0, z = 72, yaw = 0 },
		nodes = {},
		links = {},
		cover = {},
	}

	-- spawn rooms: opposite corners of the ground floor, eight points each, facing the middle
	for team = 1, 2 do
		local sign = if team == 1 then -1 else 1
		parts.spawnRooms[team] = {
			minX = math.min(sign * 59, sign * 45),
			minY = 0,
			minZ = math.min(sign * 59, sign * 31),
			maxX = math.max(sign * 59, sign * 45),
			maxY = Arena.HEADROOM,
			maxZ = math.max(sign * 59, sign * 31),
		}
		local list: { Arena.Spawn } = {}
		for _, x in { 55, 49 } do
			for _, z in { 55, 49, 43, 37 } do
				table.insert(
					list,
					{ x = sign * x, y = 0, z = sign * z, yaw = if team == 1 then -math.pi * 0.75 else math.pi * 0.25 }
				)
			end
		end
		parts.spawns[team] = list
	end

	-- navigation: a grid a floor, then the stairs, then cover beside the pillars and behind the rails
	local nodes, links = parts.nodes, parts.links
	local function node(
		x: number,
		y: number,
		z: number,
		floor: number,
		kind: "open" | "cover" | "stair" | "spawn"
	): number
		local team = 0
		for t = 1, 2 do
			if Arena.inRoom(parts.spawnRooms[t], x, y + 0.1, z) then
				team = t
			end
		end
		local id = #nodes + 1
		nodes[id] =
			{ id = id, x = x, y = y, z = z, floor = floor, kind = if team ~= 0 then "spawn" else kind, team = team }
		return id
	end
	local function link(a: number, b: number, kind: "walk" | "stair")
		local na, nb = nodes[a], nodes[b]
		local cost = math.sqrt((na.x - nb.x) ^ 2 + (na.y - nb.y) ^ 2 + (na.z - nb.z) ^ 2)
		table.insert(links, { a = a, b = b, cost = cost, kind = kind })
	end
	local function clear(a: number, b: number): boolean
		local na, nb = nodes[a], nodes[b]
		local c = Arena.CHEST
		return (Arena.sweepBoxes(boxes, na.x, na.y + c, na.z, nb.x, nb.y + c, nb.z)) == nil
	end
	local grid: { [number]: { number } } = {}
	local function nearest(floor: number, x: number, z: number): number?
		local best: number?, bestD = nil, math.huge
		for _, id in grid[floor] do
			local d = (nodes[id].x - x) ^ 2 + (nodes[id].z - z) ^ 2
			if d < bestD then
				best, bestD = id, d
			end
		end
		return best
	end
	local STEP = 24
	for f = 0, floors - 1 do
		local at: { [string]: number } = {}
		grid[f] = {}
		for ix = -2, 2 do
			for iz = -2, 2 do
				if f >= 1 and ix == 0 and iz == 0 then
					continue -- the atrium
				end
				local id = node(ix * STEP, f * h, iz * STEP, f, "open")
				at[`{ix},{iz}`] = id
				table.insert(grid[f], id)
				local west, north = at[`{ix - 1},{iz}`], at[`{ix},{iz - 1}`]
				if west and clear(west, id) then
					link(west, id, "walk")
				end
				if north and clear(north, id) then
					link(north, id, "walk")
				end
			end
		end
	end
	for _, e in stairEnds do
		local f, lowX, highX, z = e[1], e[2], e[3], e[4]
		local foot = node(lowX, f * h, z, f, "stair")
		local head = node(highX, (f + 1) * h, z, f + 1, "stair")
		link(foot, head, "stair")
		link(foot, nearest(f, lowX, z * 1.6) :: number, "walk")
		link(head, nearest(f + 1, highX, z * 1.6) :: number, "walk")
	end
	for f = 0, floors - 1 do
		for _, c in pillars do
			for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				-- the spot is 4.5 studs from the pillar's middle, sheltered from fire coming the other way
				local id = node(c[1] + d[1] * 4.5, f * h, c[2] + d[2] * 4.5, f, "cover")
				link(id, nearest(f, c[1] + d[1] * 12, c[2] + d[2] * 12) :: number, "walk")
				table.insert(parts.cover, { node = id, nx = -d[1], nz = -d[2], low = false })
			end
		end
		if f >= 1 then
			for _, side in { -1, 1 } do
				local id = node(side * (atrium + 2.5), f * h, 0, f, "cover")
				link(id, nearest(f, side * STEP, 0) :: number, "walk")
				table.insert(parts.cover, { node = id, nx = -side, nz = 0, low = true })
			end
		end
	end
	return Arena.finish(parts)
end

return ArenaData
