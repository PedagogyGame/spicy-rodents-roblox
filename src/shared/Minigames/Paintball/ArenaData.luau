--!strict
-- ReplicatedStorage.Shared.Minigames.Paintball.ArenaData
-- The arena as data (checklist PB-5, decision D3, the ground PB-10 walks on): WBLW Channel 7, the
-- abandoned five-storey TV station. OWNED BY THE ARENA LANE; `build` keeps its name and signature.
--   ArenaDataPlan   the building: every solid box with its kind and its look, the stair ramps, the two
--                   spawn rooms with their curtains, the way out, and what the bake dresses (signs,
--                   lamps, which boxes are monitors). Its header describes the storeys.
--   ArenaGrid       the fast `sweep` and `ground` (the contract reference's answers, number for number).
--   ArenaDataNavBaked   the navigation graph and the cover spots: GENERATED from the plan's boxes by
--                   tools/games/paintball/arena/bake_nav.luau (NavBuild beside it says how). Run that
--                   tool after any change to the plan; a spec fails until the file matches.
--   ArenaDataGreybox   the stand-in this file held before the building existed, kept as it was (the
--                   same `build`), for a test that was written against its exact geometry.
-- build() does that work once and hands back a fresh Arena each call: its lists are copies a caller
-- may change (a spec breaks one rule at a time), over the one grid. A caller that APPENDS a box to
-- `boxes` (a test wall) is answered by the reference scan from then on, so the answers stay true to
-- the list; nobody in the game does.
-- THE BAKE (tools/bake/games/Paintball, the registry's stub this lane fills in) draws plan() through
-- tools/games/paintball/arena/PartList: one sub-model named Arena.MODEL, in it a model per storey,
-- one part per box the same size in the same place, an invisible part per ramp, a see-through part
-- per curtain named Arena.CURTAIN .. team, every `monitor` box's part named Arena.MONITOR, and the
-- lobby annex outside the volume (parts only, no boxes).
-- Interface: build() -> Arena (a fresh table each call; the same every time); plan() -> the
--   ArenaDataPlan.Plan it was built from (shared: read it, never write it); POINTS = named places in
--   the building { x, y (feet), z }, for specs and tools

local Arena = require("./Arena")
local ArenaDataNavBaked = require("./ArenaDataNavBaked")
local ArenaDataPlan = require("./ArenaDataPlan")
local ArenaGrid = require("./ArenaGrid")

local ArenaData = {}

type Built = {
	plan: ArenaDataPlan.Plan,
	sweep: Arena.Sweep,
	ground: Arena.Ground,
	nodes: { Arena.NavNode },
	links: { Arena.NavLink },
	cover: { Arena.Cover },
}

local built: Built? = nil

local function numbers(rows: { string }): { number }
	local out: { number } = {}
	for _, row in rows do
		for word in string.gmatch(row, "%S+") do
			table.insert(out, tonumber(word) :: number)
		end
	end
	return out
end

local NODE_KINDS: { "open" | "cover" | "stair" | "spawn" } = { "open", "cover", "stair", "spawn" }

local function once(): Built
	local b = built
	if b == nil then
		local plan = ArenaDataPlan.build()
		local sweep, ground = ArenaGrid.new(plan.boxes, plan.ramps)
		local nodes: { Arena.NavNode } = {}
		local n = numbers(ArenaDataNavBaked.nodes)
		for k = 1, #n, 6 do
			local id = #nodes + 1
			nodes[id] = {
				id = id,
				x = n[k],
				y = n[k + 1],
				z = n[k + 2],
				floor = n[k + 3],
				kind = NODE_KINDS[n[k + 4]],
				team = n[k + 5],
			}
		end
		local links: { Arena.NavLink } = {}
		local l = numbers(ArenaDataNavBaked.links)
		for k = 1, #l, 3 do
			local p, q = nodes[l[k]], nodes[l[k + 1]]
			local cost = math.sqrt((p.x - q.x) ^ 2 + (p.y - q.y) ^ 2 + (p.z - q.z) ^ 2)
			table.insert(
				links,
				{ a = l[k], b = l[k + 1], cost = cost, kind = if l[k + 2] == 2 then "stair" else "walk" }
			)
		end
		local cover: { Arena.Cover } = {}
		local c = numbers(ArenaDataNavBaked.cover)
		for k = 1, #c, 4 do
			table.insert(cover, { node = c[k], nx = c[k + 1], nz = c[k + 2], low = c[k + 3] == 1 })
		end
		b = { plan = plan, sweep = sweep, ground = ground, nodes = nodes, links = links, cover = cover }
		built = b
	end
	return b :: Built
end

local function copies<T>(list: { T }): { T }
	local out = table.create(#list)
	for i, v in list do
		out[i] = table.clone(v :: any)
	end
	return out
end

function ArenaData.plan(): ArenaDataPlan.Plan
	return once().plan
end

function ArenaData.build(): Arena.Arena
	local b = once()
	local plan = b.plan
	local boxes = table.clone(plan.boxes)
	local ramps = copies(plan.ramps)
	local count = #boxes
	local gridSweep, gridGround = b.sweep, b.ground
	local parts: Arena.Parts = {
		boxes = boxes,
		kinds = table.clone(plan.kinds),
		ramps = ramps,
		spawns = { copies(plan.spawns[1]), copies(plan.spawns[2]) },
		spawnRooms = copies(plan.spawnRooms),
		curtains = { copies(plan.curtains[1]), copies(plan.curtains[2]) },
		exits = copies(plan.exits),
		lobby = table.clone(plan.lobby),
		nodes = copies(b.nodes),
		links = copies(b.links),
		cover = copies(b.cover),
		sweep = function(x0: number, y0: number, z0: number, x1: number, y1: number, z1: number)
			if #boxes ~= count then
				return Arena.sweepBoxes(boxes, x0, y0, z0, x1, y1, z1)
			end
			return gridSweep(x0, y0, z0, x1, y1, z1)
		end,
		ground = function(x: number, y: number, z: number): number?
			if #boxes ~= count then
				return Arena.groundAt(boxes, ramps, x, y, z)
			end
			return gridGround(x, y, z)
		end,
	}
	return Arena.finish(parts)
end

-- Named places (feet points), for the specs that pin what can be seen from where and for the review
-- renders' eye points. F = Arena.FLOOR_HEIGHT.
local F = Arena.FLOOR_HEIGHT
ArenaData.POINTS = table.freeze({
	atrium_floor = { x = 2, y = 0, z = 2 },
	dock_van = { x = 36, y = 0, z = 2 },
	reception = { x = 0, y = 0, z = 44 },
	north_stair_foot = { x = -12.75, y = 0, z = -28 },
	south_stair_foot = { x = 12.75, y = 0, z = 28 },
	newsroom = { x = -45, y = F, z = -24 },
	news_set = { x = 0, y = F, z = -33 },
	gallery_east_1 = { x = 18, y = F, z = 0 },
	gallery_west_1 = { x = -18, y = F, z = 0 },
	gallery_east_2 = { x = 18, y = 2 * F, z = 0 },
	gallery_west_2 = { x = -18, y = 2 * F, z = 0 },
	gallery_north_2 = { x = 0, y = 2 * F, z = -18.3 },
	studio_a = { x = 0, y = 2 * F, z = -40 },
	studio_b = { x = 0, y = 2 * F, z = 40 },
	west_exit_north = { x = -57.5, y = 2 * F, z = -17 },
	west_exit_south = { x = -46.5, y = 2 * F, z = 17 },
	east_exit_south = { x = 57.5, y = 2 * F, z = 17 },
	east_exit_north = { x = 46.5, y = 2 * F, z = -17 },
	master_control = { x = -44, y = 3 * F, z = 0 },
	tape_library = { x = -8, y = 3 * F, z = -48 },
	gallery_east_3 = { x = 18, y = 3 * F, z = 0 },
	gallery_west_4 = { x = -18, y = 4 * F, z = 0 },
	gallery_east_4 = { x = 18, y = 4 * F, z = 0 },
	transmitter_hall = { x = 0, y = 4 * F, z = -48 },
	office = { x = -52, y = 4 * F, z = -10 },
})

return ArenaData
