--!strict
-- The paintball arena's ground for the bots (checklist PB-10, PB-5): everything a body can stand on is reached
-- on foot, the navigation graph the game reads is the one the building gives today, its links can be walked by
-- a body's whole width, and it takes a bot to every room on every storey by a way not much longer than a
-- person's.
local fs = require("@lune/fs")
local Arena = require("@shared/Minigames/Paintball/Arena")
local ArenaData = require("@shared/Minigames/Paintball/ArenaData")
local NavBuild = require("../../tools/games/paintball/arena/NavBuild")
local Reach = require("../../tools/games/paintball/arena/Reach")

local H = Arena.FLOOR_HEIGHT

return function(t)
	local arena = ArenaData.build()
	local nodes, links = arena.nodes, arena.links

	t.test(
		"the baked graph is the one NavBuild makes of the plan today (run bake_nav after changing the plan)",
		function()
			local n, l, c = NavBuild.compute()
			local text = NavBuild.text(n, l, c)
			t.truthy(
				fs.readFile("src/shared/Minigames/Paintball/ArenaDataNavBaked.luau") == text,
				"ArenaDataNavBaked.luau is stale: lune run tools/games/paintball/arena/bake_nav.luau"
			)
			-- and ArenaData reads it back exactly
			t.eq(#nodes, #n)
			t.eq(#links, #l)
			t.eq(#arena.cover, #c)
			t.deepEq(nodes, n)
			t.deepEq(arena.cover, c)
			for i, link in l do
				t.eq(links[i].a, link.a)
				t.eq(links[i].b, link.b)
				t.eq(links[i].kind, link.kind)
				t.near(links[i].cost, link.cost, 1e-9)
			end
			t.truthy(#nodes >= 600 and #nodes <= 1400, `{#nodes} nodes`)
			t.truthy(#links <= 3000, `{#links} links`)
		end
	)

	t.test("everywhere a body can stand is walked to from a spawn room, and has a node near it", function()
		local survey = Reach.survey(arena)
		t.truthy(survey.cells > 40000, `{survey.cells} square studs to stand on`)
		t.eq(#survey.unreached, 0, "no nook, room or ledge of a storey's floor is cut off")
		t.eq(survey.walked, survey.cells)
		for level = 1, Arena.FLOORS do
			t.truthy(survey.perLevel[level] > 7500, `storey {level - 1}: {survey.perLevel[level]} square studs walked`)
		end
		t.eq(#survey.far, 0, `no place is over {Reach.FAR} studs from a node`)
		t.truthy(survey.farthest <= Reach.FAR)
	end)

	t.test("every node is somewhere a body stands; every walk link is clear for a body's whole width", function()
		for _, node in nodes do
			t.eq(arena.ground(node.x, node.y, node.z), node.y, `node {node.id} is on the floor`)
			t.eq(node.floor, math.floor(node.y / H + 0.01), `node {node.id} knows its storey`)
			if node.team == 0 and node.kind ~= "stair" then
				t.truthy(
					NavBuild.standable(arena.sweep, arena.ground, node.x, node.y, node.z) ~= nil,
					`node {node.id} has room`
				)
			end
			-- none within EXIT_CLEAR of the way out (a fight is not drawn into it), nor of its twin
			for _, exit in arena.exits do
				t.falsy(
					Arena.inRoom(exit, node.x, node.y + 0.1, node.z, NavBuild.EXIT_CLEAR)
						or Arena.inRoom(exit, -node.x, node.y + 0.1, -node.z, NavBuild.EXIT_CLEAR),
					`node {node.id} at ({node.x}, {node.y}, {node.z}) is near the way out`
				)
			end
		end
		local stairs, crossing = 0, 0
		local pairs: { [number]: boolean } = {}
		for i, link in links do
			local a, b = nodes[link.a], nodes[link.b]
			local key = math.min(link.a, link.b) * 65536 + math.max(link.a, link.b)
			t.falsy(pairs[key], `link {i} is there twice`)
			pairs[key] = true
			if link.kind == "stair" then
				stairs += 1
				t.truthy(
					a.floor + 1 == b.floor and a.kind == "stair" and b.kind == "stair",
					"a is the foot, b the head"
				)
			elseif a.team ~= 0 or b.team ~= 0 then
				crossing += 1 -- the spawn rooms' chains: by hand, clear along the middle (Arena.check)
			else
				t.truthy(
					NavBuild.walkable(arena.sweep, arena.ground, a.x, a.y, a.z, b.x, b.y, b.z),
					`link {i} from ({a.x}, {a.y}, {a.z}) to ({b.x}, {b.y}, {b.z}) is too tight for a body`
				)
				t.truthy(link.cost <= NavBuild.REACH + 3.01, `link {i} is {link.cost} studs long`)
			end
		end
		t.eq(stairs, 2 * (Arena.FLOORS - 1))
		t.eq(crossing, 16, "two chains of four links in each spawn room")
	end)

	-- every node's twin turned half round, found by place
	local twin: { [number]: number } = {}
	do
		local at: { [string]: number } = {}
		local function key(x: number, y: number, z: number): string
			return string.format("%.4f %.4f %.4f", x + 0, y + 0, z + 0)
		end
		for _, node in nodes do
			at[key(node.x, node.y, node.z)] = node.id
		end
		for _, node in nodes do
			twin[node.id] = at[key(-node.x, node.y, -node.z)]
		end
	end

	t.test(
		"the graph is the same for both teams: every node, link and cover spot has its twin turned half round",
		function()
			for _, node in nodes do
				local other = nodes[twin[node.id]]
				t.truthy(other ~= nil, `node {node.id} at ({node.x}, {node.y}, {node.z}) has no twin`)
				if other then
					t.eq(other.x, -node.x)
					t.eq(other.z, -node.z)
					t.eq(other.y, node.y)
					t.eq(other.floor, node.floor)
					t.eq(other.kind, node.kind)
					t.eq(other.team, if node.team == 0 then 0 else 3 - node.team)
				end
			end
			local have: { [number]: string } = {}
			for _, link in links do
				have[math.min(link.a, link.b) * 65536 + math.max(link.a, link.b)] = link.kind
			end
			for i, link in links do
				local a, b = twin[link.a], twin[link.b]
				t.eq(have[math.min(a, b) * 65536 + math.max(a, b)], link.kind, `link {i} has its twin`)
			end
			local spots: { [string]: boolean } = {}
			for _, c in arena.cover do
				spots[`{c.node} {c.nx} {c.nz} {c.low}`] = true
			end
			for i, c in arena.cover do
				t.truthy(spots[`{twin[c.node]} {-c.nx + 0} {-c.nz + 0} {c.low}`], `cover spot {i} has its twin`)
			end
			-- and so the two halves have the same cover, storey by storey
			local count: { [string]: number } = {}
			for _, c in arena.cover do
				local node = nodes[c.node]
				local k = `{node.floor} {node.x < 0 or (node.x == 0 and node.z < 0)} {c.low}`
				count[k] = (count[k] or 0) + 1
			end
			for level = 0, Arena.FLOORS - 1 do
				for _, low in { true, false } do
					t.eq(count[`{level} true {low}`], count[`{level} false {low}`], `storey {level}, low {low}`)
				end
			end
		end
	)

	t.test("the graph takes a bot everywhere, by ways not much longer than a person's", function()
		local adjacent: { [number]: { { number } } } = {}
		for _, link in links do
			adjacent[link.a] = adjacent[link.a] or {}
			adjacent[link.b] = adjacent[link.b] or {}
			table.insert(adjacent[link.a], { link.b, link.cost })
			table.insert(adjacent[link.b], { link.a, link.cost })
		end
		local function from(start: number): { [number]: number }
			local cost: { [number]: number } = { [start] = 0 }
			local open = { start }
			while #open > 0 do
				local bi = 1
				for k = 2, #open do
					if cost[open[k]] < cost[open[bi]] then
						bi = k
					end
				end
				local at = open[bi]
				open[bi] = open[#open]
				open[#open] = nil
				for _, e in adjacent[at] or {} do
					local c = cost[at] + e[2]
					if cost[e[1]] == nil or c < cost[e[1]] then
						if table.find(open, e[1]) == nil then
							table.insert(open, e[1])
						end
						cost[e[1]] = c
					end
				end
			end
			return cost
		end
		local function nearest(p: { x: number, y: number, z: number }): number
			local best, bd = 0, math.huge
			for _, node in nodes do
				local d = (node.x - p.x) ^ 2 + (node.y - p.y) ^ 2 + (node.z - p.z) ^ 2
				if d < bd then
					best, bd = node.id, d
				end
			end
			return best
		end
		local P = ArenaData.POINTS
		-- from a way out of the west room: every node is reached, and no named place is absurdly far
		local out = nearest(P.west_exit_north)
		local cost = from(out)
		local reached = 0
		for _ in cost do
			reached += 1
		end
		t.eq(reached, #nodes, "one graph")
		-- the stairs are near: the landing of the room's own storey, then two flights either way
		t.truthy(
			cost[nearest(P.north_landing_2)] <= 60,
			`the north landing is {cost[nearest(P.north_landing_2)]} studs away`
		)
		local south = from(nearest(P.west_exit_south))
		t.truthy(south[nearest({ x = 12.75, y = 2 * H, z = 26 })] <= 90, "and the south one from the other door")
		for name, p in P :: { [string]: { x: number, y: number, z: number } } do
			local id = nearest(p)
			local node = nodes[id]
			t.truthy((node.x - p.x) ^ 2 + (node.z - p.z) ^ 2 <= Reach.FAR ^ 2 and node.y == p.y, `a node near {name}`)
			local c = math.min(cost[id], south[id])
			local storeys = math.abs(node.floor - Arena.SPAWN_FLOOR)
			local straight = math.sqrt((node.x - nodes[out].x) ^ 2 + (node.z - nodes[out].z) ^ 2)
			-- a storey costs a flight (25 studs) and the walk to it; the flights switch back, so the place straight
			-- overhead is a walk round the atrium away; everything else is a walk round furniture
			t.truthy(
				c <= 1.6 * straight + storeys * 45 + 110,
				`{name} is {math.floor(c)} studs from the west room by the links`
			)
		end
		-- the same from the east room, by the graph's symmetry: exactly the same walk to every twin
		local east = from(twin[out])
		for id, c in cost do
			t.near(
				east[twin[id]],
				c,
				1e-6,
				`node {id}: {c} from the west room, its twin {east[twin[id]]} from the east`
			)
		end
		-- no node has a single way on unless it is a nook's end; none has so many that a bot dithers
		local degree: { [number]: number } = {}
		for _, link in links do
			degree[link.a] = (degree[link.a] or 0) + 1
			degree[link.b] = (degree[link.b] or 0) + 1
		end
		local most, ends = 0, 0
		for _, node in nodes do
			local d = degree[node.id] or 0
			t.truthy(d >= 1, `node {node.id} has a link`)
			most = math.max(most, d)
			if d == 1 then
				ends += 1
			end
		end
		t.truthy(most <= 14, `the busiest node has {most} links`)
		t.truthy(ends <= #nodes * 0.2, `{ends} dead ends`)
	end)

	t.test("cover spots are beside their cover, spread over every storey, on both teams' sides", function()
		local per: { [number]: number } = {}
		local west, east, low = 0, 0, 0
		for i, c in arena.cover do
			local node = nodes[c.node]
			t.eq(node.kind, "cover")
			per[node.floor] = (per[node.floor] or 0) + 1
			t.truthy(math.abs(c.nx) + math.abs(c.nz) == 1, "the sheltered side is one of the four ways")
			-- the piece is within reach: a ball at shin height stops on it within two and a half studs
			local s = arena.sweep(node.x, node.y + 2, node.z, node.x + c.nx * 2.5, node.y + 2, node.z + c.nz * 2.5)
			t.truthy(s ~= nil and s > 0.3, `cover {i} is beside its piece`)
			if node.x < 0 or (node.x == 0 and node.z < 0) then
				west += 1
			else
				east += 1
			end
			if c.low then
				low += 1
			end
		end
		for level = 0, Arena.FLOORS - 1 do
			t.truthy((per[level] or 0) >= 25, `storey {level} has {per[level]} cover spots`)
			-- none within EXIT_CLEAR of the way out: a bot is not sent to hide where its match ends
			for _, exit in arena.exits do
				for _, c in arena.cover do
					local node = nodes[c.node]
					t.falsy(Arena.inRoom(exit, node.x, node.y + 0.1, node.z, NavBuild.EXIT_CLEAR))
				end
			end
		end
		t.eq(west, east, `{west} spots in the west half, {east} in the east`)
		t.truthy(low >= 0.3 * #arena.cover and low <= 0.8 * #arena.cover, "low and tall cover both")
	end)

	t.test(
		"a tall cover spot hides a standing body from most of a fan of standing shooters, not along one line",
		function()
			local talls, worst = 0, 1
			for i, c in arena.cover do
				if not c.low then
					talls += 1
					local node = nodes[c.node]
					local hidden, of = NavBuild.fan(arena.sweep, arena.ground, node.x, node.y, node.z, c.nx, c.nz)
					t.truthy(of > 0 and hidden >= NavBuild.ARC * of, `tall spot {i} hides a body from {hidden} of {of}`)
					worst = math.min(worst, if of > 0 then hidden / of else 0)
				end
			end
			t.truthy(talls >= 40, `{talls} tall spots`)
			-- and the fan finds a spot that only shelters along a line: beside the end of a pillar, a stud aside
			local a = ArenaData.build()
			local y = 2 * H
			for _, v in { 40, y, 40, 41, y + 10, 41 } do
				table.insert(a.boxes, v) -- a post one stud square in the open
			end
			table.insert(a.kinds, Arena.KIND.pillar)
			local hidden, of = NavBuild.fan(a.sweep, a.ground, 40.5, y, 38.6, 0, 1)
			t.truthy(of >= 15 and hidden < NavBuild.ARC * of, `behind a post: hidden from {hidden} of {of}`)
		end
	)
end
