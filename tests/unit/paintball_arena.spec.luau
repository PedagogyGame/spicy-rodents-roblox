--!strict
-- The paintball arena as data (checklist PB-5; decision D3): WBLW Channel 7 as ArenaData.build() returns it.
-- The contract's own spec (paintball_contract.spec.luau) runs Arena.check on it and pins the bones every lane
-- relies on; this spec is the arena lane's: the fast ball test and walking surface give the reference's
-- answers, the building is the same for both teams, a ball never leaves it, low cover is low cover, the stairs
-- are stairs, the spawn rooms cannot be camped, and what can be seen from where is what was meant.
local Arena = require("@shared/Minigames/Paintball/Arena")
local ArenaData = require("@shared/Minigames/Paintball/ArenaData")
local ArenaDataGreybox = require("@shared/Minigames/Paintball/ArenaDataGreybox")
local ArenaDataPlan = require("@shared/Minigames/Paintball/ArenaDataPlan")
local ArenaGrid = require("@shared/Minigames/Paintball/ArenaGrid")
local Body = require("@shared/Minigames/Paintball/Body")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Hit = require("@shared/Minigames/Paintball/Hit")

local R = Contract.Rules
local H = Arena.FLOOR_HEIGHT
local KIND = Arena.KIND

-- a small generator of its own, so the cases are the same every run
local function random(seed: number): () -> number
	local s = seed
	return function(): number
		s = (s * 1103515245 + 12345) % 2147483648
		return s / 2147483648
	end
end

return function(t)
	local arena = ArenaData.build()
	local plan = ArenaData.plan()
	local boxes, kinds = arena.boxes, arena.kinds
	local n = #kinds
	local P = ArenaData.POINTS

	local function box(i: number): (number, number, number, number, number, number)
		local k = (i - 1) * 6
		return boxes[k + 1], boxes[k + 2], boxes[k + 3], boxes[k + 4], boxes[k + 5], boxes[k + 6]
	end
	-- is the line between two points clear, each raised by its own height above the feet?
	local function sees(
		a: { x: number, y: number, z: number },
		ah: number,
		b: { x: number, y: number, z: number },
		bh: number
	): boolean
		return arena.sweep(a.x, a.y + ah, a.z, b.x, b.y + bh, b.z) == nil
	end

	t.test("the building: Arena.check passes, five storeys of it, the same every call, built quickly", function()
		local ok, problems = Arena.check(arena, R.teamMax)
		t.truthy(ok, table.concat(problems, "; "))
		t.eq(#boxes, n * 6)
		t.eq(#plan.looks, n)
		t.truthy(n > 1000 and n < 2000, `{n} boxes`)
		local again = ArenaData.build()
		t.deepEq(again.boxes, arena.boxes)
		t.deepEq(again.kinds, arena.kinds)
		t.deepEq(again.nodes, arena.nodes)
		t.deepEq(again.links, arena.links)
		t.deepEq(again.spawns, arena.spawns)
		t.truthy(again.nodes ~= arena.nodes and again.nodes[1] ~= arena.nodes[1], "a fresh copy each call")
		-- a later build is a copy over the one grid: under 10 ms even on a slow machine
		local t0 = os.clock()
		for _ = 1, 5 do
			ArenaData.build()
		end
		t.truthy((os.clock() - t0) / 5 < 0.02, "a build after the first is a copy")
		-- every storey has its floor, its rails, its low cover and its tall pieces
		local low, rails, tall = {}, {}, {}
		for i = 1, n do
			local _, y0, _, _, y1, _ = box(i)
			local level = math.floor(y0 / H + 0.01)
			if kinds[i] == KIND.cover then
				low[level] = (low[level] or 0) + 1
			elseif kinds[i] == KIND.rail then
				rails[level] = (rails[level] or 0) + 1
			elseif
				(kinds[i] == KIND.prop or kinds[i] == KIND.pillar)
				and y0 - level * H < 1.01
				and y1 - y0 >= Arena.HEADROOM
			then
				tall[level] = (tall[level] or 0) + 1
			end
		end
		for level = 0, Arena.FLOORS - 1 do
			t.truthy((low[level] or 0) >= 12, `storey {level} has {low[level]} low pieces`)
			t.truthy((low[level] or 0) + (tall[level] or 0) >= 25, `storey {level}: about 25 pieces of cover`)
			if level >= 1 then
				t.truthy((rails[level] or 0) >= 4, `storey {level} has rails on all four sides of the atrium`)
			end
		end
		-- every look is a name the bake knows, and the stand-in is still there for whoever needs its geometry
		for i = 1, n do
			t.truthy(ArenaDataPlan.LOOKS[plan.looks[i]] ~= nil, `box {i} has a look`)
		end
		local okGrey = Arena.check(ArenaDataGreybox.build(), R.teamMax)
		t.truthy(okGrey, "the greybox stand-in still passes the check")
	end)

	t.test("the grid's ball test gives the reference's answer on thousands of segments (PB-5)", function()
		local rnd = random(20261113)
		local checked, hits = 0, 0
		local function same(x0: number, y0: number, z0: number, x1: number, y1: number, z1: number)
			local s, nx, ny, nz, index = arena.sweep(x0, y0, z0, x1, y1, z1)
			local rs, rx, ry, rz, rindex = Arena.sweepBoxes(boxes, x0, y0, z0, x1, y1, z1)
			if s ~= rs or nx ~= rx or ny ~= ry or nz ~= rz or index ~= rindex then
				t.eq(
					{ s :: any, nx, ny, nz, index },
					{ rs :: any, rx, ry, rz, rindex },
					`segment ({x0}, {y0}, {z0}) to ({x1}, {y1}, {z1})`
				)
			end
			checked += 1
			if s ~= nil then
				hits += 1
			end
		end
		local function point(): (number, number, number)
			return rnd() * 126 - 63, rnd() * 74 - 2, rnd() * 126 - 63
		end
		-- anywhere to anywhere, in and round the volume
		for _ = 1, 1500 do
			local x0, y0, z0 = point()
			local x1, y1, z1 = point()
			same(x0, y0, z0, x1, y1, z1)
		end
		-- a ball's step: a stud or two, mostly level, from a point in the air
		for _ = 1, 3000 do
			local x0, y0, z0 = point()
			local yaw, pitch, len = rnd() * 2 * math.pi, (rnd() - 0.5) * 0.8, 0.3 + rnd() * 3.2
			local dx, dy, dz = Body.look(yaw, pitch)
			same(x0, y0, z0, x0 + dx * len, y0 + dy * len, z0 + dz * len)
		end
		-- a look: level, at eye height on a storey, tens of studs long
		for _ = 1, 1500 do
			local level = math.floor(rnd() * 5)
			local x0, z0 = rnd() * 118 - 59, rnd() * 118 - 59
			local x1, z1 = rnd() * 118 - 59, rnd() * 118 - 59
			same(x0, level * H + Arena.EYE, z0, x1, level * H + Arena.CHEST, z1)
		end
		-- along the axes on whole and half studs: along faces, edges and the grid's own planes
		for _ = 1, 1500 do
			local x0, y0, z0 =
				math.floor(rnd() * 240 - 120) / 2, math.floor(rnd() * 144) / 2, math.floor(rnd() * 240 - 120) / 2
			local axis, len = math.floor(rnd() * 3), math.floor(rnd() * 80 - 40) / 2
			same(
				x0,
				y0,
				z0,
				x0 + (if axis == 0 then len else 0),
				y0 + (if axis == 1 then len else 0),
				z0 + (if axis == 2 then len else 0)
			)
		end
		-- along the faces of the boxes themselves, corner to corner and edge to edge
		for _ = 1, 1000 do
			local i = 1 + math.floor(rnd() * n)
			local x0, y0, z0, x1, y1, z1 = box(i)
			local pick = math.floor(rnd() * 4)
			if pick == 0 then
				same(x0, y0, z0, x1, y1, z1)
			elseif pick == 1 then
				same(x0, y1, z0 - 3, x0, y1, z1 + 3)
			elseif pick == 2 then
				same(x0 - 2, y0, z1, x1 + 2, y0, z1)
			else
				same(x1, y0 - 1, z1, x1, y1 + 1, z1)
			end
		end
		-- points (a segment of no length), in the open and inside things
		for _ = 1, 1000 do
			local x0, y0, z0 = point()
			same(x0, y0, z0, x0, y0, z0)
		end
		-- from the lobby and from far outside, towards the building
		for _ = 1, 500 do
			local x1, y1, z1 = point()
			same(rnd() * 200 - 100, rnd() * 20, 60 + rnd() * 60, x1, y1, z1)
			same(rnd() * 400 - 200, rnd() * 200 - 50, rnd() * 400 - 200, x1, y1, z1)
		end
		t.truthy(checked >= 10000, `{checked} segments`)
		t.truthy(hits > 3000 and hits < checked - 2000, `{hits} of them hit something: both answers are well tried`)
	end)

	t.test("the grid's walking surface gives the reference's answer on thousands of points", function()
		local rnd = random(771)
		local found = 0
		local function same(x: number, y: number, z: number)
			local g, r = arena.ground(x, y, z), Arena.groundAt(boxes, arena.ramps, x, y, z)
			if g ~= r then
				t.eq(g, r, `ground at ({x}, {y}, {z})`)
			end
			if g ~= nil then
				found += 1
			end
		end
		for _ = 1, 6000 do
			same(rnd() * 130 - 65, rnd() * 76 - 3, rnd() * 130 - 65)
		end
		for _ = 1, 3000 do
			same(
				math.floor(rnd() * 248 - 124) / 2,
				math.floor(rnd() * 5) * H + rnd() * 2,
				math.floor(rnd() * 248 - 124) / 2
			)
		end
		-- on the stairs, where a ramp and its steps and the floors below all lie under a point
		for _, r in arena.ramps do
			for _ = 1, 300 do
				local x = r.minX - 1 + rnd() * (r.maxX - r.minX + 2)
				local z = r.minZ - 1 + rnd() * (r.maxZ - r.minZ + 2)
				same(x, r.y0 + rnd() * (r.y1 - r.y0 + 2) - 1, z)
			end
		end
		t.truthy(found > 8000)
		local _, _, stats = ArenaGrid.new(plan.boxes, plan.ramps)
		t.truthy(stats.cells > 10000 and stats.entries / n < 60, "the grid is fine and its lists are short")
	end)

	t.test("a box appended to an arena's list is a wall from then on (the reference answers)", function()
		local a = ArenaData.build()
		local y = 2 * H
		t.eq((a.sweep(40, y + 3, 33, 40, y + 3, 49)), nil, "open floor in the south-east room")
		t.eq(a.ground(40, y + 1, 40), y)
		for _, v in { 38, y, 39, 42, y + 5, 41 } do
			table.insert(a.boxes, v)
		end
		table.insert(a.kinds, KIND.wall)
		local s, _, _, nz, index = a.sweep(40, y + 3, 33, 40, y + 3, 49)
		t.near(s :: number, 0.375, 1e-9)
		t.eq(nz, -1)
		t.eq(index, #a.kinds)
		t.eq(a.ground(40, y + 4, 40), y + 5)
		t.eq((arena.sweep(40, y + 3, 33, 40, y + 3, 49)), nil, "and no other arena has it")
	end)

	t.test("the west team's building is the east team's, turned half round", function()
		local function key(x0: number, y0: number, z0: number, x1: number, y1: number, z1: number): string
			return string.format("%.3f %.3f %.3f %.3f %.3f %.3f", x0, y0, z0, x1, y1, z1)
		end
		local have: { [string]: number } = {}
		for i = 1, n do
			local k = key(box(i))
			have[k] = (have[k] or 0) + 1
		end
		-- (the south wall of the ground floor is cut for the gate and the lobby's windows, the north one is
		-- whole: the same solid, so the outer walls are compared by what a ball meets instead)
		local missing = 0
		for i = 1, n do
			local x0, y0, z0, x1, y1, z1 = box(i)
			local outer = math.max(math.abs(x0), math.abs(x1), math.abs(z0), math.abs(z1)) > Arena.HALF
			if not outer and have[key(-x1, y0, -z1, -x0, y1, -z0)] == nil then
				missing += 1
				t.truthy(missing > 3, `box {i} has no twin: {key(x0, y0, z0, x1, y1, z1)}`)
			end
		end
		t.eq(missing, 0)
		local rnd = random(5)
		for _ = 1, 3000 do
			local x0, y0, z0 = rnd() * 120 - 60, rnd() * 70, rnd() * 120 - 60
			local x1, y1, z1 = rnd() * 124 - 62, rnd() * 72 - 1, rnd() * 124 - 62
			local s, nx, ny, nz = arena.sweep(x0, y0, z0, x1, y1, z1)
			local ts, tx, ty, tz = arena.sweep(-x0, y0, -z0, -x1, y1, -z1)
			if s == nil or ts == nil then
				t.eq(s, ts)
			else
				t.near(s, ts, 1e-9)
				t.deepEq({ nx, ny, nz }, { -tx, ty, -tz })
			end
		end
		-- the rooms, the spawn points and the stairs too
		for i, sp in arena.spawns[1] do
			local twin = arena.spawns[2][i]
			t.near(twin.x, -sp.x, 1e-9)
			t.near(twin.z, -sp.z, 1e-9)
			t.eq(twin.y, sp.y)
		end
		for i = 1, #arena.ramps, 2 do
			local a, b = arena.ramps[i], arena.ramps[i + 1]
			t.deepEq(
				{ b.minX, b.maxX, b.minZ, b.maxZ, b.y0, b.y1, b.dir },
				{ -a.maxX, -a.minX, -a.maxZ, -a.minZ, a.y0, a.y1, -a.dir }
			)
		end
	end)

	t.test("the volume is sealed: a ball never leaves it, by the gate, the windows, the shutter or the roof", function()
		local rnd = random(99)
		local tried = 0
		while tried < 4000 do
			local x, y, z = rnd() * 118 - 59, 0.5 + rnd() * 69, rnd() * 118 - 59
			if arena.sweep(x, y, z, x, y, z) == nil then
				tried += 1
				local yaw, pitch = rnd() * 2 * math.pi, (rnd() - 0.5) * 3
				local dx, dy, dz = Body.look(yaw, pitch)
				local s = arena.sweep(x, y, z, x + dx * 400, y + dy * 400, z + dz * 400)
				t.truthy(s ~= nil, `a ball from ({x}, {y}, {z}) flies out of the building`)
			end
		end
		-- the lobby looks in through glass, which is a wall to a ball; the gate is shut
		local s, _, _, nz, index = arena.sweep(28, 5, 50, 28, 5, 70)
		t.near(s :: number, 0.5, 1e-9)
		t.eq(nz, -1)
		t.eq(ArenaDataPlan.LOOKS[plan.looks[index]], "glass")
		local _, _, _, _, gate = arena.sweep(0, 3, 50, 0, 3, 70)
		t.eq(ArenaDataPlan.LOOKS[plan.looks[gate]], "gate")
		local _, _, _, _, shutter = arena.sweep(57, 4, -25, 70, 4, -25)
		t.eq(ArenaDataPlan.LOOKS[plan.looks[shutter]], "shutter")
		-- the way out is a room inside, behind the gate, and the lobby point is outside on the lobby's floor
		t.eq(#arena.exits, 1)
		local exit = arena.exits[1]
		t.truthy(exit.maxZ <= Arena.HALF and exit.minZ > 50 and exit.minY == 0)
		t.truthy(Arena.inRoom(exit, Arena.GATE.x, 1, Arena.HALF - 1), "it is the alcove behind the gate")
		t.falsy(Arena.inVolume(arena.lobby.x, arena.lobby.y + 1, arena.lobby.z))
		t.truthy(arena.lobby.z > Arena.HALF + 2 and arena.lobby.z < 90)
	end)

	t.test(
		"PB-5, PB-9: low cover is rail height on what it stands on; nothing is the wrong height to stand by",
		function()
			for i = 1, n do
				local x0, y0, z0, x1, y1, z1 = box(i)
				local kind = kinds[i]
				if kind == KIND.cover or kind == KIND.rail then
					t.near(y1 - y0, Arena.RAIL_HEIGHT, 1e-9, `low piece {i} is rail height`)
					-- it stands on a floor or a riser: the walking surface beside it is its foot
					local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
					local foot = arena.ground(cx, y0, cz)
					t.eq(foot, y0, `low piece {i} stands on the walking surface`)
				end
			end
			-- beside every cover spot of the graph: a level ball at a crouched eye is stopped, at a standing eye
			-- it flies over low cover and is stopped by tall cover
			local lows, talls = 0, 0
			for i, c in arena.cover do
				local node = arena.nodes[c.node]
				local x1, z1 = node.x + c.nx * 3.6, node.z + c.nz * 3.6
				local crouched = arena.sweep(node.x, node.y + Body.CROUCH_EYE, node.z, x1, node.y + Body.CROUCH_EYE, z1)
				local standing = arena.sweep(node.x, node.y + Body.STAND_EYE, node.z, x1, node.y + Body.STAND_EYE, z1)
				t.truthy(crouched ~= nil, `cover {i}: a crouched body there is behind something`)
				if c.low then
					lows += 1
					t.eq(standing, nil, `cover {i} is low: a standing eye sees over it`)
					-- and a crouched body there is not tagged by a level ball from the far side, a standing one is
					local fx, fz = node.x + c.nx * 8, node.z + c.nz * 8
					local y = node.y + Arena.RAIL_HEIGHT + 0.3
					if arena.sweep(fx, y, fz, node.x, y, node.z) == nil then
						t.eq((Hit.body(arena.sweep, fx, y, fz, node.x, y, node.z, node.x, node.y, node.z, 1)), nil)
						t.truthy(Hit.body(arena.sweep, fx, y, fz, node.x, y, node.z, node.x, node.y, node.z, 0) ~= nil)
					end
				else
					talls += 1
					t.truthy(standing ~= nil, `cover {i} is tall: it hides a standing body`)
				end
			end
			t.truthy(lows >= 60 and talls >= 40, `{lows} low spots and {talls} tall ones`)
		end
	)

	t.test("the stairs are stairs: two flights a storey, steps under every ramp, headroom all the way", function()
		t.eq(#arena.ramps, 2 * (Arena.FLOORS - 1))
		local steps = 0
		for i = 1, n do
			if kinds[i] == KIND.step then
				steps += 1
				local x0, _, z0, x1, y1, z1 = box(i)
				-- under exactly one ramp, and never above its surface
				local under = 0
				for _, r in arena.ramps do
					local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
					local h = Arena.rampHeight(r, cx, cz)
					if h ~= nil and y1 <= r.y1 + 1e-9 and y1 >= r.y0 - 1e-9 then
						under += 1
						for _, x in { x0, x1 } do
							local at = Arena.rampHeight(r, x, cz) :: number
							t.truthy(y1 <= at + 1e-9, `step {i} rises above its ramp`)
						end
						t.truthy(h - y1 <= 0.5 + 1e-9, `step {i} is no more than half a stud under the ramp`)
					end
				end
				t.eq(under, 1, `step {i} lies under one ramp`)
			end
		end
		t.truthy(steps >= 200)
		for i, r in arena.ramps do
			t.eq(r.y1 - r.y0, H)
			t.eq(r.axis, "x")
			local run = r.maxX - r.minX
			t.truthy(run >= 18 and run <= 24, "a flight is neither a ladder nor a ramp")
			local zc = (r.minZ + r.maxZ) / 2
			-- walked from the foot to the head a quarter stud at a time: the floor rises smoothly, the head
			-- has room, and a ball flying down the flight's middle meets nothing
			local last = r.y0
			local from, to = if r.dir > 0 then r.minX - 2 else r.maxX + 2, if r.dir > 0 then r.maxX + 2 else r.minX - 2
			for k = 0, 100 do
				local x = from + (to - from) * k / 100
				local g = arena.ground(x, last, zc) :: number
				t.truthy(g ~= nil and g >= last - 1e-9 and g - last <= 0.35, `ramp {i} at x = {x}`)
				t.eq((arena.sweep(x, g + 0.1, zc, x, g + Arena.HEADROOM, zc)), nil, `headroom on ramp {i} at x = {x}`)
				last = g
			end
			t.near(last, r.y1, 1e-9)
			-- the landing at its head is a floor, with the next flight's foot beside it
			t.eq(arena.ground(to, r.y1, zc), r.y1)
		end
		-- climbing one core from the ground to the top storey: four flights, three turns on a landing
		local feet: { [number]: Arena.NavNode } = {}
		local heads: { [number]: Arena.NavNode } = {}
		for _, l in arena.links do
			local a, b = arena.nodes[l.a], arena.nodes[l.b]
			if l.kind == "stair" and a.z < 0 then
				feet[a.floor], heads[b.floor] = a, b
			end
		end
		for f = 1, Arena.FLOORS - 2 do
			local gap = math.sqrt((feet[f].x - heads[f].x) ^ 2 + (feet[f].z - heads[f].z) ^ 2)
			t.truthy(gap <= 4.01, `the north core's turn on storey {f} is {gap} studs`)
		end
	end)

	t.test("the spawn rooms cannot be camped (decision 18)", function()
		local mid = Arena.SPAWN_FLOOR * H
		for team = 1, 2 do
			local room = arena.spawnRooms[team]
			local other = arena.spawns[3 - team]
			t.eq(#arena.spawns[team], R.teamMax)
			-- no spawn point sees an enemy spawn point, eye to eye or eye to chest
			for _, sp in arena.spawns[team] do
				for _, foe in other do
					t.falsy(sees(sp, Arena.EYE, foe, Arena.EYE))
					t.falsy(sees(sp, Arena.EYE, foe, Arena.CHEST))
				end
			end
			-- nobody outside sees anybody inside the room proper: from every node of the graph outside it,
			-- at a standing and at a crouched eye, to the head, chest and shins of a body on every spawn point
			local outs: { Arena.NavNode } = {}
			for _, l in arena.links do
				local a, b = arena.nodes[l.a], arena.nodes[l.b]
				if a.team == team and b.team == 0 then
					table.insert(outs, b)
				end
				t.falsy(b.team == team and a.team == 0, "a way out is written from the inside to the outside")
			end
			t.eq(#outs, 2, `team {team}'s room has one link across each of its two doorways`)
			for _, node in arena.nodes do
				if node.team ~= team then
					for _, sp in arena.spawns[team] do
						for _, eye in { Body.STAND_EYE, Body.CROUCH_EYE } do
							for _, h in { 0.5, Arena.CHEST, Body.STAND_TOP - 0.2 } do
								t.falsy(sees(node, eye, sp, h), `node {node.id} sees into team {team}'s room`)
							end
						end
					end
				end
			end
			-- the two ways out are far apart, on opposite sides of the room, and nobody sees both of them
			local a, b = outs[1], outs[2]
			t.truthy(math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2) >= Arena.EXIT_APART)
			t.truthy((a.z - room.minZ) * (b.z - room.minZ) < 0 or (a.z < room.minZ) ~= (b.z < room.minZ))
			t.falsy(sees(a, Arena.EYE, b, Arena.EYE))
			local both = 0
			for _, node in arena.nodes do
				if node.team == 0 and node.id ~= a.id and node.id ~= b.id then
					if sees(node, Arena.EYE, a, Arena.CHEST) and sees(node, Arena.EYE, b, Arena.CHEST) then
						both += 1
					end
				end
			end
			t.eq(both, 0, `{both} nodes watch both of team {team}'s doors at once`)
			-- each way out has more than one way on from it, and cover within a few strides
			for _, out in outs do
				local ways = 0
				for _, l in arena.links do
					if
						(l.a == out.id and arena.nodes[l.b].team == 0) or (l.b == out.id and arena.nodes[l.a].team == 0)
					then
						ways += 1
					end
				end
				t.truthy(ways >= 2, `the way out at ({out.x}, {out.z}) leads on {ways} ways`)
				local near = math.huge
				for _, c in arena.cover do
					local node = arena.nodes[c.node]
					if node.floor == Arena.SPAWN_FLOOR then
						near = math.min(near, math.sqrt((node.x - out.x) ^ 2 + (node.z - out.z) ^ 2))
					end
				end
				t.truthy(near <= 16, `cover {near} studs from the way out at ({out.x}, {out.z})`)
			end
			-- the curtains fill the doorways: thin, door height, and the wall is solid either side of each
			for _, c in arena.curtains[team] do
				t.eq(c.minY, mid)
				t.eq(c.maxY, mid + Arena.HEADROOM)
				local alongX = (c.maxX - c.minX) > (c.maxZ - c.minZ)
				t.truthy(alongX and c.maxZ - c.minZ == 1 and c.maxX - c.minX == 5)
				local z = (c.minZ + c.maxZ) / 2
				t.truthy(
					arena.sweep(c.minX - 0.5, mid + 3, z, c.minX - 0.5, mid + 3, z) ~= nil or c.minX <= -Arena.HALF
				)
				t.truthy(arena.sweep(c.maxX + 0.5, mid + 3, z, c.maxX + 0.5, mid + 3, z) ~= nil or c.maxX >= Arena.HALF)
				t.truthy(
					arena.sweep(c.minX + 2.5, mid + Arena.HEADROOM + 2, z, c.minX + 2.5, mid + 12, z) ~= nil,
					"a lintel over it"
				)
			end
		end
	end)

	t.test("what is seen from where: the atrium joins the storeys, the walls part the rooms", function()
		local stand, crouch = Body.STAND_EYE, Body.CROUCH_EYE
		-- (from, its height, to, its height, open?)
		local function line(from: string, fh: number, to: string, th: number, open: boolean)
			local a, b = (P :: any)[from], (P :: any)[to]
			t.truthy(a ~= nil and b ~= nil, `{from} and {to} are named places`)
			t.eq(sees(a, fh, b, th), open, `{from} to {to}`)
			t.eq(sees(b, th, a, fh), open, `{to} to {from}`)
		end
		-- every named place is somewhere a body stands
		for name, p in P :: { [string]: { x: number, y: number, z: number } } do
			t.eq(arena.ground(p.x, p.y, p.z), p.y, `{name} is on the floor`)
			t.eq((arena.sweep(p.x, p.y + 0.2, p.z, p.x, p.y + Arena.HEADROOM, p.z)), nil, `{name} is in the open`)
		end
		-- across the atrium on a storey: standing bodies see each other, crouched ones do not
		line("gallery_east_2", stand, "gallery_west_2", stand, true)
		line("gallery_east_2", crouch, "gallery_west_2", crouch, false)
		line("gallery_east_2", stand, "gallery_west_2", crouch, false)
		line("gallery_east_1", stand, "gallery_west_1", stand, true)
		line("gallery_north_2", stand, "gallery_south_2", stand, true)
		-- between storeys: from the rail you see the far gallery one storey down, and its heads see you
		line("rail_east_4", stand, "gallery_west_3", stand, true)
		line("rail_east_2", stand, "gallery_west_1", stand, true)
		line("rail_east_1", stand, "atrium_floor_west", Arena.CHEST, true)
		-- but not two storeys down (your own rail is in the way), and not the floor at your feet
		line("rail_east_4", stand, "gallery_west_2", 0.5, false)
		line("rail_east_1", stand, "atrium_floor_east", Arena.CHEST, false)
		-- step back from the rail and the storey below is gone
		line("gallery_east_4", stand, "gallery_west_3", 0.5, false)
		-- the atrium floor sees up the whole height of it, and the glass roof is over it
		t.truthy(sees(P.atrium_floor, 1, { x = P.atrium_floor.x, y = Arena.HEIGHT - 0.5, z = P.atrium_floor.z }, 0))
		line("atrium_floor", stand, "gallery_west_4", stand, false)
		-- rooms are rooms
		line("studio_a", stand, "studio_b", stand, false)
		line("studio_a", stand, "gallery_north_2", stand, false)
		line("west_exit_north", stand, "west_exit_south", stand, false)
		line("west_exit_north", stand, "east_exit_south", stand, false)
		line("west_exit_south", stand, "gallery_east_2", stand, false)
		line("newsroom", stand, "news_set", stand, false)
		line("office", stand, "gallery_west_4", stand, false)
		line("tape_library", stand, "master_control", stand, false)
		line("reception", stand, "atrium_floor", stand, false)
		-- master control looks out over the concourse and the atrium through its windows, standing only
		line("master_control_window", stand, "gallery_east_3", stand, true)
		line("master_control_window", crouch, "gallery_east_3", stand, false)
		line("master_control", stand, "gallery_east_3", stand, false)
		-- a stair core: shut off from the gallery on the first floor, open over a parapet on the second
		line("north_landing_1", stand, "gallery_north_1", stand, false)
		line("north_landing_2", stand, "gallery_north_2", stand, true)
		line("north_landing_2", crouch, "gallery_north_2", crouch, false)
		-- inside a core you see the flight you are about to climb, and the ground hall sees the first flight
		t.truthy(sees(P.north_landing_2, stand, { x = 0, y = 2.5 * H, z = -28 }, stand))
		line("north_stair_foot", stand, "atrium_floor", stand, true)
		-- the long look down the ground floor's aisle, from the atrium to the dock's east wall
		line("atrium_floor_aisle", 2, "dock_wall_east", 2, true)
		-- the lobby's windows look onto the atrium's floor past the south core (glass stops a ball, not the eye)
		local glass = { x = 28, y = 0, z = Arena.HALF - 0.1 }
		t.truthy(
			sees(glass, stand, P.atrium_floor_east, stand),
			"from inside the lobby's east window to the atrium floor"
		)
		t.truthy(sees({ x = -28, y = 0, z = Arena.HALF - 0.1 }, stand, { x = -13, y = 0, z = 7 }, stand))
	end)
end
