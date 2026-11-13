--!strict
-- tools/games/paintball/bots/Greybox.luau: the match-and-bots lane's own test building. It is the
-- stand-in arena the paintball contract shipped in Shared/Minigames/Paintball/ArenaData before the
-- arena lane's real building replaced it, kept here word for word so that the bots' close-up specs
-- (tests/unit/paintball_bots.spec.luau) and their pinned matches stand on ground that does not move
-- when the real building is re-planned: the S18 greybox (five floors 14 studs apart, a 30 x 30
-- atrium, four pillars a floor) made honest enough to pass Arena.check:
--   * rails on the east and west sides of the atrium;
--   * two switchback stairs inside the atrium's north and south edges: each storey's flight (14 step
--     boxes under a walking ramp) ends on a landing where the next storey's flight begins. Their
--     sides are open: a body may drop off them;
--   * two walled spawn rooms on the middle storey, against the west wall (team 1) and the east wall
--     (team 2), each with a door at either end behind a baffle wall, a curtain box in each doorway and
--     eight spawn points that no node outside can see;
--   * a 5 x 5 grid of navigation nodes a floor (24 studs apart), the stairs' nodes, the rooms' ways
--     out, and cover spots beside the pillars and behind the rails.
-- It is wide open (long sight lines, little cover): a harder place for a bot to look sensible in
-- than the real building, which is why the bands the specs pin here are not the real building's
-- (tests/unit/paintball_bots_building.spec.luau plays whole matches on ArenaData.build() itself).
-- NOTHING IN THE GAME READS THIS FILE: the game's arena is ArenaData.build().
-- Interface: build() -> Arena (a fresh table each call; pure, the same every time)

local Arena = require("@shared/Minigames/Paintball/Arena")

local Greybox = {}

function Greybox.build(): Arena.Arena
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
	local function room(x0: number, y0: number, z0: number, x1: number, y1: number, z1: number): Arena.Room
		return {
			minX = math.min(x0, x1),
			minY = math.min(y0, y1),
			minZ = math.min(z0, z1),
			maxX = math.max(x0, x1),
			maxY = math.max(y0, y1),
			maxZ = math.max(z0, z1),
		}
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

	-- The stairs: on each of the north (side -1) and south (side 1) edges of the atrium, two strips 4
	-- studs wide side by side. Even storeys climb in the outer strip, odd storeys in the inner one, each
	-- the other way along x, so a flight ends on the landing (across both strips) the next begins on.
	local RUN, STEPS, STRIP = 21, 14, 4
	local END = (RUN / 2 + atrium) / 2 -- the middle of a landing, along x
	local ramps: { Arena.Ramp } = {}
	local flights: { { f: number, side: number, dir: number, z: number } } = {}
	for f = 0, floors - 2 do
		local y0, y1 = f * h, (f + 1) * h
		local inner = if f % 2 == 0 then 0 else STRIP
		for _, side in { -1, 1 } do
			local dir = (if f % 2 == 0 then 1 else -1) * -side -- the way it rises along x
			local za, zb = side * (atrium - inner), side * (atrium - inner - STRIP)
			local z0, z1 = math.min(za, zb), math.max(za, zb)
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
			-- the landing at the head, across both strips: the foot of the next storey's flight too
			box(KIND.slab, dir * RUN / 2, y1 - 1, side * (atrium - 2 * STRIP), dir * atrium, y1, side * atrium)
			table.insert(flights, { f = f, side = side, dir = dir, z = (za + zb) / 2 })
		end
	end

	local parts: Arena.Parts = {
		boxes = boxes,
		kinds = kinds,
		ramps = ramps,
		spawns = {},
		spawnRooms = {},
		curtains = {},
		exits = {},
		lobby = { x = -14, y = 0, z = 72, yaw = 0 },
		nodes = {},
		links = {},
		cover = {},
	}

	-- The spawn rooms, on the middle storey: team 1's against the west wall, team 2's the same room
	-- turned half round against the east wall (s = 1, -1). Written for team 1: air from x -60 to -44,
	-- z -12 to 12; a door in the north wall at its west end and one in the south wall at its east end;
	-- inside each door a baffle wall, so that whoever looks in sees a wall and whoever walks in turns
	-- along a corridor and comes into the room at the far end of the baffle.
	local roomY = Arena.SPAWN_FLOOR * h
	local wallTop = roomY + h - 1
	local doorTop = roomY + Arena.HEADROOM
	for team = 1, 2 do
		local s = if team == 1 then 1 else -1
		box(KIND.wall, s * -44, roomY, s * -13, s * -43, wallTop, s * 13) -- the wall towards the atrium
		box(KIND.wall, s * -55, roomY, s * -13, s * -44, wallTop, s * -12) -- north wall (door: x -60..-55)
		box(KIND.wall, s * -60, roomY, s * 12, s * -49, wallTop, s * 13) -- south wall (door: x -49..-44)
		box(KIND.wall, s * -60, roomY, s * -7, s * -48, wallTop, s * -6) -- the baffle inside the north door
		box(KIND.wall, s * -55, roomY, s * 6, s * -44, wallTop, s * 7) -- the baffle inside the south door
		parts.spawnRooms[team] = room(s * -60, roomY, s * -12, s * -44, doorTop, s * 12)
		parts.curtains[team] = {
			room(s * -60, roomY, s * -13, s * -55, doorTop, s * -12),
			room(s * -49, roomY, s * 12, s * -44, doorTop, s * 13),
		}
		local list: { Arena.Spawn } = {}
		for _, z in { -2.5, 2.5 } do
			-- each row looks towards the gap at the end of the baffle on its side
			local gx, gz = if z < 0 then -46 else -57.5, if z < 0 then -6.5 else 6.5
			for _, x in { -57, -53, -49.5, -46 } do
				local dx, dz = s * (gx - x), s * (gz - z)
				table.insert(list, { x = s * x, y = roomY, z = s * z, yaw = math.atan2(-dx, -dz) })
			end
		end
		parts.spawns[team] = list
	end

	-- navigation: a grid a floor, then the stairs, the rooms' ways out, and cover beside the pillars
	-- and behind the rails
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
	local grid: { [number]: { number } } = {} -- the grid nodes of a floor that are in no spawn room
	local hubs: { [number]: number } = {} -- by team: the grid node inside its spawn room
	local function nearest(floor: number, x: number, z: number): number
		local best, bestD = 0, math.huge
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
				if nodes[id].team == 0 then
					table.insert(grid[f], id)
				else
					hubs[nodes[id].team] = id
				end
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
	-- the stairs: a node at the foot and at the head of every flight, a node on the floor beside each
	-- landing, and a step across the landing from the head of one flight to the foot of the next
	local beside: { [string]: number } = {} -- "floor:side" -> the node on the floor beside that landing
	local heads: { [string]: number } = {}
	for _, fl in flights do
		local f, side, dir = fl.f, fl.side, fl.dir
		local foot = node(-dir * END, f * h, fl.z, f, "stair")
		local head = node(dir * END, (f + 1) * h, fl.z, f + 1, "stair")
		link(foot, head, "stair")
		heads[`{f + 1}:{side}`] = head
		local below = heads[`{f}:{side}`]
		if below then
			link(below, foot, "walk")
		else
			local onFloor = node(-dir * END, f * h, side * (atrium + 3), f, "open")
			link(onFloor, foot, "walk")
			link(onFloor, nearest(f, -dir * END, side * STEP), "walk")
		end
		local onFloor = node(dir * END, (f + 1) * h, side * (atrium + 3), f + 1, "open")
		beside[`{f + 1}:{side}`] = onFloor
		link(onFloor, head, "walk")
		link(onFloor, nearest(f + 1, dir * END, side * STEP), "walk")
	end
	-- the rooms' ways out: from the grid node inside, round each baffle, along the corridor, out of the door
	for team = 1, 2 do
		local s = if team == 1 then 1 else -1
		local hub = hubs[team]
		local function chain(points: { { number } }): number
			local last = hub
			for _, p in points do
				local id = node(s * p[1], roomY, s * p[2], Arena.SPAWN_FLOOR, "open")
				link(last, id, "walk")
				last = id
			end
			return last
		end
		local northOut = chain({ { -46, -6.5 }, { -46, -9.5 }, { -57.5, -9.5 }, { -57.5, -17 } })
		local southOut = chain({ { -57.5, 6.5 }, { -57.5, 9.5 }, { -46.5, 9.5 }, { -46.5, 17 } })
		-- the north door (for team 2, turned round: the south one) comes out on the stairs' side
		link(northOut, beside[`{Arena.SPAWN_FLOOR}:{-s}`], "walk")
		link(northOut, nearest(Arena.SPAWN_FLOOR, s * -48, s * -24), "walk")
		link(southOut, nearest(Arena.SPAWN_FLOOR, s * -48, s * 24), "walk")
	end
	for f = 0, floors - 1 do
		for _, c in pillars do
			for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
				-- the spot is 4.5 studs from the pillar's middle, sheltered from fire coming the other way
				local id = node(c[1] + d[1] * 4.5, f * h, c[2] + d[2] * 4.5, f, "cover")
				link(id, nearest(f, c[1] + d[1] * 12, c[2] + d[2] * 12), "walk")
				table.insert(parts.cover, { node = id, nx = -d[1], nz = -d[2], low = false })
			end
		end
		if f >= 1 then
			for _, side in { -1, 1 } do
				local id = node(side * (atrium + 2.5), f * h, 0, f, "cover")
				link(id, nearest(f, side * STEP, 0), "walk")
				table.insert(parts.cover, { node = id, nx = -side, nz = 0, low = true })
			end
		end
	end
	return Arena.finish(parts)
end

return Greybox
