--!strict
-- The paintball bots (Server/Minigames/Paintball/Bots, BotBrain, BotNav; checklist PB-6, PB-10), pinned
-- two ways. Close up: one bot, a hand-built match and a scripted person, for what a bot sees, hears,
-- waits for and refuses to do. And whole matches played headless (tools/games/paintball/bots/Sim: the
-- real Session, Rules and Bots, with the lane's own ball loop): 4 v 4 and 8 v 8 of bots alone, bots
-- against a scripted target, and a match with the stand-in fair player; each with a fixed seed, each
-- run once and shared by the cases that read it.
-- EVERYTHING HERE STANDS ON THE LANE'S OWN TEST BUILDING (tools/games/paintball/bots/Greybox: the
-- contract's stand-in arena, kept), so a case may name a spot by its coordinates and a band may be
-- narrow: none of it moves when the real building is re-planned. The same bots on the game's own
-- building (ArenaData.build()) are held to looser, building-blind bands in
-- tests/unit/paintball_bots_building.spec.luau.
-- (The numbers pinned here are bands round what the bots do today. When the bots are retuned, run
-- tools/games/paintball/bots/match.luau and calibrate.luau with `greybox`, look, and move the bands
-- on purpose.)
local Ballistics = require("@shared/Paintball/Ballistics")
local ArenaModule = require("@shared/Minigames/Paintball/Arena")
local Body = require("@shared/Minigames/Paintball/Body")
local Clock = require("@shared/Minigames/Paintball/Clock")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Hit = require("@shared/Minigames/Paintball/Hit")
local Rules = require("@shared/Minigames/Paintball/Rules")
local Wire = require("@shared/Minigames/Paintball/Wire")
local BotBrain = require("@server/Minigames/Paintball/BotBrain")
local BotNav = require("@server/Minigames/Paintball/BotNav")
local Bots = require("@server/Minigames/Paintball/Bots")
local Greybox = require("../../tools/games/paintball/bots/Greybox")
local Report = require("../../tools/games/paintball/bots/Report")
local Sim = require("../../tools/games/paintball/bots/Sim")

local R = Contract.Rules
local F = Contract.FEEL
local BOT = Contract.BOT
local BIT = Wire.BIT
local DT = 1 / Clock.TICK_HZ

local arena = Greybox.build()
local nav = BotNav.build(arena)

-- matches are played once and shared
local played: { [string]: any } = {}
local function match(key: string, make: () -> Sim.Sim): (Sim.Sim, Report.Summary)
	local had = played[key]
	if had == nil then
		local sim = Sim.run(make())
		had = { sim = sim, summary = Report.summary(sim) }
		played[key] = had
	end
	return had.sim, had.summary
end
local function four(): (Sim.Sim, Report.Summary)
	return match("4v4", function()
		return Sim.new({ arena = arena, seed = 11, perSide = 4 })
	end)
end
local function eight(): (Sim.Sim, Report.Summary)
	return match("8v8", function()
		return Sim.new({ arena = arena, seed = 12, perSide = 8 })
	end)
end

-- A hand-built match for close-up cases: seat 1 a person (team 1) the case moves by hand, seat 2 a bot
-- (team 2), live, protection over, the bot standing at node `at` and looking along `yaw`.
type Close = {
	state: Rules.State,
	bots: Bots.Bots,
	poses: { [number]: Contract.Pose },
	now: number,
	brain: BotBrain.Brain,
	fired: { Bots.Command },
	said: { Bots.Command },
}
local function closeUp(at: number, yaw: number, seed: number?): Close
	local state = Rules.init(2, 5)
	Rules.sync(state, 100)
	local now = 100 + R.briefingSecs + F.protectSecs + 1
	Rules.sync(state, now - 5)
	Rules.step(state, 0)
	Rules.sync(state, now)
	Rules.step(state, 0)
	Rules.drain(state)
	assert(state.phase == "live", "live")
	local bots = Bots.new(arena, { seed = seed or 3 })
	local node = arena.nodes[at]
	local poses: { [number]: Contract.Pose } = {
		{ x = 0, y = 0, z = 0, yaw = 0, pitch = 0, crouch = 0, bits = 0 },
		{ x = node.x, y = node.y, z = node.z, yaw = yaw, pitch = 0, crouch = 0, bits = 0 },
	}
	Bots.sync(bots, state, { [2] = 0.5 }, poses, now)
	-- (the person left their spawn room a while ago: no truce is owed them, THE TRUCES in BotBrain)
	bots.squad.leftAt[1] = state.slots[1].spawnAt + 0.5
	local brain = (bots.brains :: { [number]: BotBrain.Brain })[2]
	brain.goAt = math.huge -- it stands where it was put until the case says otherwise
	brain.scanAt, brain.scanYaw, brain.scanPitch = math.huge, yaw, 0 -- and looks where it looks
	return { state = state, bots = bots, poses = poses, now = now, brain = brain, fired = {}, said = {} }
end
local function stepClose(c: Close, seconds: number, heard: { Bots.Heard }?)
	local first = heard
	local n = math.floor(seconds / DT + 0.5)
	for _ = 1, n do
		c.now += DT
		Rules.sync(c.state, c.now)
		for _, cmd in Bots.step(c.bots, c.state, c.poses, first or {}, c.now, DT) do
			if cmd.kind == "fire" then
				table.insert(c.fired, cmd)
				Rules.fire(c.state, cmd.id, c.now)
			elseif cmd.kind == "reload" then
				Rules.reload(c.state, cmd.id, c.now)
			else
				table.insert(c.said, cmd)
			end
		end
		first = nil
		Rules.step(c.state, DT)
	end
end
-- the yaw that looks from one point at another
local function yawTo(x0: number, z0: number, x1: number, z1: number): number
	return math.atan2(-(x1 - x0), -(z1 - z0))
end
local function angleOff(c: Close, x: number, z: number): number
	local want = yawTo(c.brain.x, c.brain.z, x, z)
	return math.abs((want - c.poses[2].yaw + math.pi) % (2 * math.pi) - math.pi)
end
-- a node on the open ground floor, well away from pillars and stairs
local function groundNode(x: number, z: number): number
	for i, node in arena.nodes do
		if node.floor == 0 and node.x == x and node.z == z then
			return i
		end
	end
	error(`no ground node at {x}, {z}`)
end

return function(t)
	t.test("the test building's quick ball test and ground are the reference's, box for box", function()
		local seed = 7
		local function u(): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end
		local function snap(v: number): number
			return math.floor(v * 2 + 0.5) / 2
		end
		local wrong, hits = 0, 0
		for i = 1, 20000 do
			local x0, y0, z0 = u() * 140 - 70, u() * 77 - 2, u() * 140 - 70
			local len = if i % 2 == 0 then u() * 6 else u() * 150
			local dx, dy, dz = u() - 0.5, (u() - 0.5) * (if i % 3 == 0 then 0.05 else 1), u() - 0.5
			local m = math.sqrt(dx * dx + dy * dy + dz * dz)
			local x1, y1, z1 = x0 + dx / m * len, y0 + dy / m * len, z0 + dz / m * len
			if i % 4 < 2 then
				-- on the half-stud lattice the building is drawn on, and along the axes (as clearPath asks)
				x0, y0, z0, x1, y1, z1 = snap(x0), snap(y0), snap(z0), snap(x1), snap(y1), snap(z1)
				if i % 4 == 0 then
					z1, y1 = z0, y0
				end
			end
			local a, ax, ay, az, ai = arena.sweep(x0, y0, z0, x1, y1, z1)
			local b, bx, by, bz, bi = ArenaModule.sweepBoxes(arena.boxes, x0, y0, z0, x1, y1, z1)
			hits += if a ~= nil then 1 else 0
			if a ~= b or (a ~= nil and (ax ~= bx or ay ~= by or az ~= bz or ai ~= bi)) then
				wrong += 1
			end
			local gx, gy, gz = snap(u() * 124 - 62), u() * 73 - 1, snap(u() * 124 - 62)
			if arena.ground(gx, gy, gz) ~= ArenaModule.groundAt(arena.boxes, arena.ramps, gx, gy, gz) then
				wrong += 1
			end
		end
		t.eq(wrong, 0)
		t.truthy(hits > 5000, `{hits} of the segments struck something`)
	end)

	t.test("what a bot knows of the building: doors, keep-off ground, a way out of the spawn room, peeks", function()
		t.eq(nav.count, #arena.nodes)
		for team = 1, 2 do
			t.truthy(#nav.doors[team] >= 2, "two ways out")
			for _, id in nav.doors[team] do
				local node = arena.nodes[id]
				t.eq(node.team, 0, "a door node is outside the room")
				t.truthy(nav.keepOff[3 - team][id], "the other team keeps off it")
				t.falsy(nav.keepOff[team][id], "its own team does not")
				t.truthy(BotNav.atDoor(nav, team, node.x, node.y, node.z))
				t.falsy(BotNav.atDoor(nav, 3 - team, node.x, node.y, node.z))
			end
			-- every spawn point has a node of its room it can walk straight to
			for index, sp in arena.spawns[team] do
				local entry = arena.nodes[nav.entry[team][index]]
				t.eq(entry.team, team)
				local c = ArenaModule.CHEST
				t.eq(arena.sweep(sp.x, sp.y + c, sp.z, entry.x, entry.y + c, entry.z), nil)
			end
			local room = arena.spawnRooms[team]
			t.eq(BotNav.roomOf(nav, (room.minX + room.maxX) / 2, room.minY, (room.minZ + room.maxZ) / 2), team)
		end
		t.eq(BotNav.roomOf(nav, 0, 0, 0), 0)
		-- nobody chooses to stand in a room, on a door, or (the other team) near one
		for f = 1, arena.floors do
			t.truthy(#nav.goals[f] > 10, `storey {f} has places to go`)
			for _, id in nav.goals[f] do
				t.eq(arena.nodes[id].team, 0)
				t.eq(nav.door[id], 0)
			end
		end
		-- a peek is a short step on the same floor with nothing in the way
		local peeks = 0
		for id, list in nav.peeks do
			local node = arena.nodes[id]
			for _, peek in list do
				peeks += 1
				t.near(math.sqrt((peek.x - node.x) ^ 2 + (peek.z - node.z) ^ 2), BotNav.PEEK, 1e-6)
				t.near(arena.ground(peek.x, node.y + 0.5, peek.z) :: number, node.y, 0.05)
				local e = ArenaModule.EYE
				t.eq(arena.sweep(node.x, node.y + e, node.z, peek.x, node.y + e, peek.z), nil)
			end
		end
		t.truthy(peeks > 40, `{peeks} peeks`)
	end)

	t.test(
		"routes: out of its own room and never back, never through the other team's, by a stair of its own taste",
		function()
			local hub = { 0, 0 }
			for i, node in arena.nodes do
				if node.team ~= 0 and hub[node.team] == 0 then
					hub[node.team] = i
				end
			end
			local far = groundNode(48, 48)
			local function checked(path: { number }, team: number, stairsUsed: { [number]: boolean }?)
				local left = false
				for k, id in path do
					local node = arena.nodes[id]
					t.truthy(node.team ~= 3 - team, "never in the other team's room")
					t.truthy(nav.door[id] ~= 3 - team, "nor on its doors")
					if node.team == 0 then
						left = true
					else
						t.falsy(left, "once out of its own room it does not go back in")
					end
					-- every step is a link of the graph
					if k > 1 then
						local linked = false
						local list = nav.adjacent[path[k - 1]]
						for j = 1, #list, 3 do
							if list[j] == id then
								linked = true
								if nav.stair[list[j + 1]] and stairsUsed ~= nil then
									stairsUsed[list[j + 1]] = true
								end
							end
						end
						t.truthy(linked, "a step along a link")
					end
				end
			end
			for seed = 1, 8 do
				local taste = BotNav.taste(nav, seed)
				for team = 1, 2 do
					local path = BotNav.route(nav, hub[team], nil, 0, far, team, taste) :: { number }
					t.truthy(path ~= nil and #path > 3)
					t.eq(path[1], hub[team])
					t.eq(path[#path], far)
					checked(path, team, nil)
				end
			end
			-- the same trip by 24 bots, two storeys down and across the building, about as far by the north
			-- stairs as by the south: their tastes send some each way
			local stairsUsed: { [number]: boolean } = {}
			local from = BotNav.nearest(nav, 24, 28, 24, 1)
			local to = groundNode(-24, -24)
			for seed = 1, 24 do
				local path = BotNav.route(nav, from, nil, 0, to, 1, BotNav.taste(nav, seed)) :: { number }
				checked(path, 1, stairsUsed)
			end
			local used = 0
			for _ in stairsUsed do
				used += 1
			end
			t.eq(used, 4, "both flights of both storeys")
			-- from outside, a route across the building does not cut through the bot's own room
			local taste = BotNav.taste(nav, 1)
			local a = BotNav.nearest(nav, -48, 28, -24, 1)
			local b = BotNav.nearest(nav, -48, 28, 24, 1)
			for _, id in BotNav.route(nav, a, nil, 0, b, 1, taste) :: { number } do
				t.eq(arena.nodes[id].team, 0)
			end
			-- and there is no way INTO the other team's room at all
			t.eq(BotNav.route(nav, a, nil, 0, hub[2], 1, taste), nil)
			-- the search keeps its working tables between searches: whatever came before (a search that
			-- found nothing, one to somewhere else), the same question has the same answer
			local once = BotNav.route(nav, a, nil, 0, b, 1, taste)
			BotNav.route(nav, b, nil, 0, hub[1], 1, taste)
			BotNav.route(nav, a, nil, 0, hub[2], 1, taste)
			t.deepEq(BotNav.route(nav, a, nil, 0, b, 1, taste), once)
			t.eq(BotNav.route(nav, a, nil, 0, nav.count + 1, 1, taste), nil, "no such place")
			-- and starting from either end of a link: the cheaper start is taken
			local list = nav.adjacent[a]
			local beside = list[1]
			local viaBeside = BotNav.route(nav, a, beside, 1000, b, 1, taste) :: { number }
			t.eq(viaBeside[1], a, "a costly other end is not where it starts")
		end
	)

	t.test(
		"the list of brains: one a bot's seat, none for a person's; no pose, no bot; out or not live, it stands",
		function()
			local state = Rules.init(4, 1)
			Rules.sync(state, 50)
			local bots = Bots.new(arena, { seed = 1 })
			local poses: { [number]: Contract.Pose } = {}
			t.deepEq(Bots.step(bots, state, poses, {}, 50, DT), {}, "nobody synced")
			Bots.sync(bots, state, { [2] = 0.5, [3] = 0.4, [4] = 0.6 }, poses, 50)
			local brains = bots.brains :: { [number]: BotBrain.Brain }
			t.eq(brains[1], nil)
			t.truthy(brains[2] ~= nil and brains[3] ~= nil and brains[4] ~= nil)
			t.falsy(brains[2].placed)
			t.deepEq(Bots.step(bots, state, poses, {}, 50.02, DT), {})
			t.eq(poses[2], nil, "a bot nobody has placed writes no pose")
			-- placed in the briefing: it stands on its spawn point until the match is live
			local sp = arena.spawns[2][1]
			poses[2] = { x = sp.x, y = sp.y, z = sp.z, yaw = sp.yaw, pitch = 0, crouch = 0, bits = 0 }
			Bots.place(bots, 2, poses[2], 50.02)
			t.truthy(brains[2].placed)
			local now = 50.02
			for _ = 1, 120 do
				now += DT
				Rules.sync(state, now)
				t.deepEq(Bots.step(bots, state, poses, {}, now, DT), {})
				Rules.step(state, DT)
			end
			t.deepEq({ poses[2].x, poses[2].z, poses[2].bits }, { sp.x, sp.z, 0 })
			-- live: it walks out of the room, by links, and is out of it within a few seconds
			now = 50 + R.briefingSecs
			local left: number? = nil
			for _ = 1, 8 * Clock.TICK_HZ do
				now += DT
				Rules.sync(state, now)
				Bots.step(bots, state, poses, {}, now, DT)
				Rules.step(state, DT)
				if left == nil and BotNav.roomOf(nav, poses[2].x, poses[2].y, poses[2].z) == 0 then
					left = now - (50 + R.briefingSecs)
				end
			end
			t.truthy(left ~= nil and left < 5, `out of the room in {left} s`)
			-- tagged out: it stands where it stood, says so once, and writes nothing more
			t.truthy(Rules.tag(state, 1, 2, now))
			local x, z = poses[2].x, poses[2].z
			local words = 0
			for _ = 1, 60 do
				now += DT
				Rules.sync(state, now)
				for _, cmd in Bots.step(bots, state, poses, {}, now, DT) do
					t.eq(cmd.kind, "say")
					t.eq(cmd.line, "out")
					t.truthy((Contract.LINES :: any)[cmd.line] ~= nil)
					words += 1
				end
			end
			t.eq(words, 1)
			t.deepEq({ poses[2].x, poses[2].z }, { x, z })
			-- a person takes seat 3, seat 4 changes sides: the one brain goes, the other starts afresh
			local four4 = brains[4]
			t.truthy(Rules.assign(state, 4, 1))
			Bots.sync(bots, state, { [2] = 0.5, [4] = 0.6 }, poses, now)
			t.eq(brains[3], nil)
			t.truthy(brains[4] ~= nil and brains[4] ~= four4, "a new brain for the new side")
			t.eq(brains[4].team, 1)
			-- a new match is a new State: nothing of the old one is kept
			local next = Rules.init(2, 2)
			Rules.sync(next, now)
			Bots.sync(bots, next, { [2] = 0.5 }, {}, now)
			t.eq(brains[4], nil)
			t.falsy((bots.brains :: any)[2].placed)
		end
	)

	t.test(
		"sight: only inside the cone, only along a clear line, and nothing is done about it before the reaction time",
		function()
			local at = groundNode(0, -24)
			-- the person stands 30 studs in front of the bot, in the open: seen, then fired on
			local c = closeUp(at, 0)
			local bx, bz = c.brain.x, c.brain.z
			c.poses[1].x, c.poses[1].y, c.poses[1].z = bx, 0, bz - 30
			local t0 = c.now
			stepClose(c, 0.2)
			local contact = c.brain.con[1]
			t.truthy(contact ~= nil and contact.first > t0, "seen at the first sight check")
			t.truthy(contact.react >= BOT.reactMin and contact.react <= BOT.reactMax)
			t.eq(c.brain.target, nil, "seen is not yet noticed")
			t.eq(#c.fired, 0)
			stepClose(c, 1.5)
			t.eq(c.brain.target, 1)
			t.truthy(#c.fired >= 1, "and then it fires")
			-- a ball goes along the bot's own look, from its own eye, at the match's speed
			local cmd = c.fired[#c.fired]
			local speed = math.sqrt((cmd.vx :: number) ^ 2 + (cmd.vy :: number) ^ 2 + (cmd.vz :: number) ^ 2)
			t.near(speed, c.state.feel.ballSpeed, 1e-6)
			-- behind it: never seen, however long
			local behind = closeUp(at, 0)
			behind.poses[1].x, behind.poses[1].z = bx, bz + 30
			stepClose(behind, 3)
			t.eq(behind.brain.con[1], nil)
			t.eq(#behind.fired, 0)
			-- at the edge: 55 degrees off is seen, 65 is not
			for _, case in { { 55, true }, { 65, false } } do
				local edge = closeUp(at, 0)
				local a = math.rad(case[1] :: number)
				edge.poses[1].x, edge.poses[1].z = bx + math.sin(a) * 25, bz - math.cos(a) * 25
				edge.brain.scanAt = math.huge -- it keeps looking where it looks
				stepClose(edge, 0.25)
				local seen = edge.brain.con[1] ~= nil and edge.brain.con[1].seen > 0
				t.eq(seen, case[2], `{case[1]} degrees`)
			end
			-- a pillar in the way: looked for, not seen
			local pillar = closeUp(BotNav.nearest(nav, 35, 0, -20, 2), 0)
			pillar.poses[1].x, pillar.poses[1].z = 35, -50
			pillar.brain.x, pillar.brain.z = 35, -20
			pillar.brain.yaw = yawTo(35, -20, 35, -50)
			pillar.brain.scanAt = math.huge
			stepClose(pillar, 1)
			t.truthy(pillar.brain.con[1] ~= nil, "a sight check was spent on it")
			t.eq(pillar.brain.con[1].seen, -math.huge, "and found a pillar")
			t.eq(#pillar.fired, 0)
			-- in its own spawn room: nobody looks in, nobody shoots in
			local sp = arena.spawns[1][1]
			local room = closeUp(at, 0)
			room.poses[1].x, room.poses[1].y, room.poses[1].z = sp.x, sp.y, sp.z
			room.brain.x, room.brain.y, room.brain.z = sp.x + 3, sp.y, sp.z
			stepClose(room, 1)
			t.eq(room.brain.con[1], nil)
		end
	)

	t.test(
		"a head over a rail is somebody in plain view: seen, aimed at where they show, and tagged; crouched, they are hidden",
		function()
			-- the person stands upright behind the atrium's west rail on the middle storey; the bot behind
			-- the east rail, on the same storey and on the one above, looking across
			local y = 2 * arena.floorHeight
			local px, pz = -17, 0
			for _, storey in { 2, 3 } do
				local at = BotNav.nearest(nav, 17.5, storey * arena.floorHeight, 0, 2)
				local node = arena.nodes[at]
				local ex, ey, ez = Body.eyePoint(node.x, node.y, node.z, 0)
				-- the premise: the rail hides their chest from here and not their head
				t.truthy(arena.sweep(ex, ey, ez, px, y + ArenaModule.CHEST, pz) ~= nil, "the chest is behind the rail")
				t.eq((arena.sweep(ex, ey, ez, px, y + Body.STAND_TOP - Body.RADIUS, pz)), nil, "the head is over it")
				local c = closeUp(at, yawTo(node.x, node.z, px, pz), 3 + storey)
				c.poses[1].x, c.poses[1].y, c.poses[1].z = px, y, pz
				stepClose(c, 6)
				t.eq(c.brain.target, 1, `seen from storey {storey + 1}`)
				t.truthy(c.brain.con[1].high, "by the head")
				t.truthy(#c.fired >= 5, `{#c.fired} balls`)
				-- its balls go over the rail, and some land: each one flown by the rules a ball is flown by
				local landed, onRail = 0, 0
				local feel = c.state.feel
				for _, cmd in c.fired do
					local ox, oy, oz = cmd.ox :: number, cmd.oy :: number, cmd.oz :: number
					local vx, vy, vz = cmd.vx :: number, cmd.vy :: number, cmd.vz :: number
					local age = 0
					while age < R.ballTtl do
						local ax, ay, az = Ballistics.position(ox, oy, oz, vx, vy, vz, feel.ballDrop, age)
						local bx, by, bz = Ballistics.position(ox, oy, oz, vx, vy, vz, feel.ballDrop, age + DT)
						local wall = arena.sweep(ax, ay, az, bx, by, bz)
						local s = Hit.body(arena.sweep, ax, ay, az, bx, by, bz, px, y, pz, 0)
						if s ~= nil and (wall == nil or s < wall) then
							landed += 1
							break
						elseif wall ~= nil then
							local hx, hy = ax + (bx - ax) * wall, ay + (by - ay) * wall
							if hx < -ArenaModule.ATRIUM + 0.1 and hx > -ArenaModule.ATRIUM - 0.6 and hy < y + 3.5 then
								onRail += 1
							end
							break
						end
						age += DT
					end
				end
				t.truthy(landed >= 1, `{landed} of {#c.fired} balls landed on what showed`)
				t.truthy(onRail < #c.fired * 0.6, `{onRail} of {#c.fired} balls spent on the rail`)
			end
			-- crouched behind the rail they are wholly hidden: looked for, never seen, never fired at
			local at = BotNav.nearest(nav, 17.5, y, 0, 2)
			local node = arena.nodes[at]
			local hidden = closeUp(at, yawTo(node.x, node.z, px, pz))
			hidden.poses[1].x, hidden.poses[1].y, hidden.poses[1].z, hidden.poses[1].crouch = px, y, pz, 1
			stepClose(hidden, 4)
			t.truthy(hidden.brain.con[1] ~= nil, "sight checks were spent on them")
			t.eq(hidden.brain.con[1].seen, -math.huge, "and found the rail, at the chest and at the head")
			t.eq(hidden.brain.target, nil)
			t.eq(#hidden.fired, 0)
			-- and standing in the open, it is the middle of them a bot aims at
			local open = closeUp(groundNode(0, -24), 0)
			open.poses[1].x, open.poses[1].y, open.poses[1].z = open.brain.x, 0, open.brain.z - 30
			stepClose(open, 1.5)
			t.eq(open.brain.target, 1)
			t.falsy(open.brain.con[1].high)
		end
	)

	t.test(
		"the first ball waits for the sighting to be 0.25 s old and the look to be on it; sprinting, it waits longer",
		function()
			local at = groundNode(0, -24)
			for seed = 1, 12 do
				local c = closeUp(at, math.rad(40), seed)
				local bx, bz = c.brain.x, c.brain.z
				c.poses[1].x, c.poses[1].z = bx, bz - 28
				local born: number? = nil
				local from = c.now
				for _ = 1, 3 * Clock.TICK_HZ do
					stepClose(c, DT)
					if #c.fired > 0 then
						born = c.now
						break
					end
				end
				local first = c.brain.con[1].first
				t.truthy(born ~= nil, `seed {seed} fired`)
				t.truthy((born :: number) - first >= BOT.reactMin - 1e-6, "not before the reaction time")
				t.truthy((born :: number) - from < 2, "and not long after")
				-- along its look: the service's check (BOT.aimSlack) would pass it
				local cmd = c.fired[1]
				local lx, ly, lz = Body.look(c.poses[2].yaw, c.poses[2].pitch)
				local speed = c.state.feel.ballSpeed
				local cos = ((cmd.vx :: number) * lx + (cmd.vy :: number) * ly + (cmd.vz :: number) * lz) / speed
				t.truthy(cos >= math.cos(BOT.aimSlack), "the ball is where the puppet points")
				-- and the look had been turning towards the person, at no more than BOT.turn
				t.truthy(angleOff(c, bx, bz - 28) < math.rad(25), "it turned to face before it fired")
			end
			-- the sprint bit, or the 0.15 s after it: no ball
			local c = closeUp(at, 0)
			c.poses[1].x, c.poses[1].z = c.brain.x, c.brain.z - 28
			stepClose(c, 1.2)
			local n = #c.fired
			t.truthy(n >= 1)
			c.brain.sprintAt = c.now + 0.4 -- (as if it sprints for the next 0.4 s)
			stepClose(c, 0.4 + Body.SPRINT_FIRE_DELAY)
			t.eq(#c.fired, n, "nothing while sprinting or within the delay after")
			stepClose(c, 1.5)
			t.truthy(#c.fired > n, "then it fires again")
			-- a protected target is watched, not fired on
			local safe = closeUp(at, 0)
			safe.poses[1].x, safe.poses[1].z = safe.brain.x, safe.brain.z - 28
			safe.state.slots[1].safeUntil = safe.now + 1.5
			stepClose(safe, 1.4)
			t.eq(safe.brain.target, 1)
			t.eq(#safe.fired, 0)
			stepClose(safe, 1.5)
			t.truthy(#safe.fired >= 1)
		end
	)

	t.test(
		"the truces are narrow: first strides and a quiet doorstep only, and over when somebody comes close or squares up",
		function()
			local TRUCE = BotBrain.TRUCE
			local at = groundNode(0, -24)
			-- a person who has just stepped out of their spawn room (as far as the bots can tell) and stands
			-- `dist` studs in front of the bot, looking at it or away; nothing changes but what the case says
			local function fresh(seed: number, dist: number, looking: boolean): Close
				local c = closeUp(at, 0, seed)
				local sp = arena.spawns[1][1]
				c.poses[1].x, c.poses[1].y, c.poses[1].z = sp.x, sp.y, sp.z
				stepClose(c, DT)
				c.bots.squad.leftAt[1] = nil -- (as after a placement: its next step out is its first)
				local bx, bz = c.brain.x, c.brain.z
				c.poses[1].x, c.poses[1].y, c.poses[1].z = bx, 0, bz - dist
				c.poses[1].yaw = if looking
					then yawTo(bx, bz - dist, bx, bz)
					else yawTo(bx, bz - dist, bx, bz) + math.pi
				return c
			end
			local function firstBall(c: Close, within: number): number?
				local from = c.now
				for _ = 1, math.floor(within / DT + 0.5) do
					stepClose(c, DT)
					if #c.fired > 0 then
						return c.now - from
					end
				end
				return nil
			end
			for seed = 1, 8 do
				-- first strides, 25 studs off, looking away: not its target (no stare), no ball for OUT_TRUCE ...
				local c = fresh(seed, 25, false)
				stepClose(c, TRUCE.out - 0.05)
				t.eq(#c.fired, 0, `seed {seed}: a ball in somebody's first strides out`)
				t.eq(c.brain.target, nil, `seed {seed}: it does not stand with its marker on them`)
				t.truthy(c.brain.con[1] ~= nil and c.now - c.brain.con[1].seen < 0.4, "though it has seen them")
				-- ... and then it is a fight like any other: the sighting has long sunk in
				local late = firstBall(c, 2)
				t.truthy(late ~= nil and late < 1.3, `seed {seed}: the first ball {late} s after the truce`)
				-- looking at the bot: squared up to it, no truce
				local square = fresh(seed, 25, true)
				local squared = firstBall(square, TRUCE.out)
				t.truthy(squared ~= nil and squared < 1.3, `seed {seed}: squared up, the first ball after {squared} s`)
				-- walking straight up to it, looking away: no truce once inside TRUCE.near
				local walk = fresh(seed, 32, false)
				local inside: number? = nil
				local fired: number? = nil
				for _ = 1, 3 * Clock.TICK_HZ do
					local p = walk.poses[1]
					if walk.brain.z - p.z > 6 then
						p.z += Body.WALK * DT
					end
					if inside == nil and walk.brain.z - p.z < TRUCE.near then
						inside = walk.now
					end
					stepClose(walk, DT)
					if #walk.fired > 0 then
						fired = walk.now
						break
					end
				end
				t.truthy(inside ~= nil and fired ~= nil, `seed {seed}: walked up and was fired on`)
				t.truthy((fired :: number) >= (inside :: number), "not before it came close")
				t.truthy(
					(fired :: number) - (inside :: number) < 0.8,
					`seed {seed}: {(fired :: number) - (inside :: number)} s after it came close`
				)
			end
			-- the doorstep: quiet on it, 21 studs from a bot, looking away: no ball for as long as it stays
			-- quiet; squared up to the bot, a fight
			local door = nav.nodes[nav.doors[1][1]]
			local post = BotNav.nearest(nav, door.x + 18, door.y, door.z - 18, 2)
			local node = arena.nodes[post]
			local px, pz = door.x + 3.5, door.z - 3
			t.truthy(BotNav.atDoor(nav, 1, px, door.y, pz), "the premise: on its own doorstep")
			local flat = math.sqrt((node.x - px) ^ 2 + (node.z - pz) ^ 2)
			t.truthy(flat > TRUCE.near + 2 and flat < 26, `the premise: {flat} studs from the bot`)
			t.eq(arena.sweep(node.x, node.y + 4.5, node.z, px, door.y + ArenaModule.CHEST, pz), nil, "in plain view")
			for _, looking in { false, true } do
				local c = closeUp(post, yawTo(node.x, node.z, px, pz))
				c.poses[1].x, c.poses[1].y, c.poses[1].z = px, door.y, pz
				c.poses[1].yaw = yawTo(px, pz, node.x, node.z) + (if looking then 0 else math.pi)
				local first = firstBall(c, 6)
				if looking then
					t.truthy(first ~= nil and first < 1.3, `squared up on the doorstep: the first ball after {first} s`)
				else
					t.eq(first, nil, "nobody quiet on their doorstep is fired on")
					t.eq(c.brain.target, nil, "nor stared at")
				end
			end
			-- the stand-in person keeps none of it
			t.eq((Sim.FAIR :: any).courtesy, false)
			t.eq((BotBrain.DEFAULT :: any).courtesy, true)
		end
	)

	t.test("the first ball at a new target is the widest (the warning splat); the later ones close in", function()
		-- a person standing still 28 studs off, forty bots in turn: how far each ball's line passes from
		-- the person's centre line, sideways, by which ball of the sighting it is
		local at = groundNode(0, -24)
		local sum = { 0, 0, 0 }
		local count = { 0, 0, 0 }
		for seed = 1, 40 do
			local c = closeUp(at, math.rad(10), seed)
			local bx, bz = c.brain.x, c.brain.z
			local px, pz = bx + 3, bz - 28
			c.poses[1].x, c.poses[1].z = px, pz
			stepClose(c, 3)
			local want = yawTo(bx, bz, px, pz)
			for i, cmd in c.fired do
				local got = yawTo(0, 0, cmd.vx :: number, cmd.vz :: number)
				local off = math.abs((got - want + math.pi) % (2 * math.pi) - math.pi)
				local k = math.min(i, 3)
				sum[k] += off * off
				count[k] += 1
			end
		end
		t.eq(count[1], 40, "every bot fired")
		t.truthy(count[3] >= 40, `{count[3]} third and later balls`)
		local rms = {}
		for k = 1, 3 do
			rms[k] = math.sqrt(sum[k] / count[k])
		end
		t.truthy(rms[1] > rms[3] * 1.4, `first ball {math.deg(rms[1])} deg off, later {math.deg(rms[3])} deg`)
		t.truthy(rms[2] > rms[3] * 0.9 and rms[2] < rms[1], "the second between")
		-- and none is a turret: even the later balls are off by something at this range
		t.truthy(math.deg(rms[3]) > 0.5, `later balls {math.deg(rms[3])} deg off`)
	end)

	t.test("it turns no faster than BOT.turn, respects the magazine like anybody, and fires in bursts", function()
		local at = groundNode(0, -24)
		local c = closeUp(at, 0)
		-- the person walks a circle round the bot, and half way through is suddenly 50 degrees further on
		local bx, bz = c.brain.x, c.brain.z
		local angle = 0
		local lastYaw, lastPitch = c.poses[2].yaw, c.poses[2].pitch
		local worst = 0
		local times: { number } = {}
		for i = 1, 14 * Clock.TICK_HZ do
			angle += 0.4 * DT
			if i == 7 * Clock.TICK_HZ then
				angle += math.rad(50)
			end
			c.poses[1].x, c.poses[1].z = bx + math.sin(angle) * 28, bz - math.cos(angle) * 28
			local before = #c.fired
			stepClose(c, DT)
			if #c.fired > before then
				table.insert(times, c.now)
			end
			local turned = math.abs((c.poses[2].yaw - lastYaw + math.pi) % (2 * math.pi) - math.pi)
			worst = math.max(worst, turned / DT, math.abs(c.poses[2].pitch - lastPitch) / DT)
			lastYaw, lastPitch = c.poses[2].yaw, c.poses[2].pitch
		end
		t.truthy(worst <= BOT.turn + 1e-6, `turned at {worst} rad/s`)
		t.truthy(worst > BOT.turn * 0.5, "and it does turn briskly")
		t.truthy(#times >= 8, `{#times} balls`)
		local pauses = 0
		for i = 2, #times do
			local gap = times[i] - times[i - 1]
			t.truthy(gap >= F.fireInterval - 1e-6, "never inside the fire interval")
			if gap > F.fireInterval + 0.1 then
				pauses += 1
			end
		end
		t.truthy(pauses >= 2, "bursts, with pauses between")
		for i = 6, #times do
			t.truthy(times[i] - times[i - 5] >= F.reloadSecs, "a sixth ball only after a reload")
		end
		local slot = c.state.slots[2]
		t.eq(slot.shots, #times, "every ball it asked for was one the match allowed")
	end)

	t.test(
		"in the open with somebody to fight it does not stand to be shot: it jinks across their line and back",
		function()
			local at = groundNode(0, -24)
			for seed = 1, 6 do
				local c = closeUp(at, 0, seed)
				local bx, bz = c.brain.x, c.brain.z
				c.poses[1].x, c.poses[1].z = bx, bz - 28 -- the person: dead ahead, along -z
				c.brain.mode = "hold" -- at a post in the open (no cover at this node)
				c.brain.holdUntil = math.huge
				t.truthy(nav.coverAt[at] == nil, "the node is open floor")
				local left, right, turns, lastSide = 0, 0, 0, 0
				local lastX = bx
				for _ = 1, 6 * Clock.TICK_HZ do
					stepClose(c, DT)
					if c.brain.mode ~= "hold" then
						break -- (empty in the open, it goes for cover or another spot: not this case's business)
					end
					local off = c.brain.x - bx
					left, right = math.min(left, off), math.max(right, off)
					local going = c.brain.x - lastX
					local side = if going > 1e-6 then 1 elseif going < -1e-6 then -1 else 0
					if side ~= 0 and lastSide == 0 then
						turns += 1 -- it sets off from rest: a step out, or a step back
					end
					lastSide, lastX = side, c.brain.x
					-- a couple of strides either side of where it stood, on the floor it stood on, at a walk
					t.truthy(math.abs(off) <= 3 and math.abs(c.brain.z - bz) <= 0.5, `seed {seed}: {off} off its post`)
					t.near(c.brain.y, 0, 1e-6)
					t.truthy(math.abs(going) <= Body.speed(0, false, c.state.feel) * DT + 1e-6, "no faster than a walk")
					t.falsy(Wire.has(c.poses[2].bits, BIT.sprint))
				end
				t.truthy(right - left >= 2.5, `seed {seed}: it moved {right - left} studs across the line`)
				t.truthy(turns >= 3, `seed {seed}: out, back and out again at the least ({turns} steps)`)
				t.truthy(#c.fired >= 3, `seed {seed}: and it fired as it went ({#c.fired} balls)`)
				t.eq(c.brain.target, 1)
			end
			-- with nobody to fight it stands at its post: a jink is for a fight
			local idle = closeUp(at, 0)
			idle.poses[1].x, idle.poses[1].z = idle.brain.x, idle.brain.z + 28 -- behind it
			idle.brain.mode = "hold"
			idle.brain.holdUntil = math.huge
			local x0, z0 = idle.brain.x, idle.brain.z
			idle.brain.scanAt = math.huge
			stepClose(idle, 1)
			t.eq(idle.brain.target, nil)
			t.deepEq({ idle.brain.x, idle.brain.z }, { x0, z0 })
		end
	)

	t.test(
		"somebody in view too far off to fire at: it does not stand and look at them, it moves up and then fires",
		function()
			-- the longest clear line between two places a bot may stand on one storey: well over its range
			local reach = BotBrain.DEFAULT.range * F.ballSpeed
			local from, to, longest = 0, 0, 0
			for i, a in arena.nodes do
				if a.team ~= 0 or nav.door[i] ~= 0 or nav.keepOff[2][i] then
					continue
				end
				for j, b in arena.nodes do
					local d = math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
					if
						j > i
						and b.team == 0
						and a.y == b.y
						and d > longest
						and arena.sweep(a.x, a.y + ArenaModule.EYE, a.z, b.x, b.y + ArenaModule.CHEST, b.z) == nil
						and arena.sweep(b.x, b.y + ArenaModule.EYE, b.z, a.x, a.y + ArenaModule.CHEST, a.z) == nil
					then
						from, to, longest = i, j, d
					end
				end
			end
			t.truthy(longest > reach + 12, `the longest line is {longest} studs, the range {reach}`)
			local there = arena.nodes[to]
			for seed = 1, 6 do
				local c = closeUp(from, yawTo(arena.nodes[from].x, arena.nodes[from].z, there.x, there.z), seed)
				c.poses[1].x, c.poses[1].y, c.poses[1].z = there.x, there.y, there.z
				c.brain.mode = "hold"
				c.brain.holdUntil = math.huge -- it would stand at this post for ever, if nobody came
				local function off(): number
					return math.sqrt((c.brain.x - there.x) ^ 2 + (c.brain.y - there.y) ^ 2 + (c.brain.z - there.z) ^ 2)
				end
				local noticed, left, firstBall = nil :: number?, nil :: number?, nil :: number?
				local t0 = c.now
				for _ = 1, 12 * Clock.TICK_HZ do
					local balls = #c.fired
					stepClose(c, DT)
					if noticed == nil and c.brain.target == 1 then
						noticed = c.now
					end
					if left == nil and c.brain.mode == "travel" then
						left = c.now
					end
					if #c.fired > balls then
						firstBall = firstBall or c.now
						t.truthy(off() <= reach + 0.5, `seed {seed}: a ball from {off()} studs`)
					end
				end
				t.truthy(noticed ~= nil and (noticed :: number) - t0 < 1, `seed {seed}: it sees them`)
				-- a moment to take it in, then it is on its way: never ten seconds of looking
				t.truthy(
					left ~= nil and (left :: number) - (noticed :: number) < 3.5,
					`seed {seed}: it set off {if left ~= nil then left - (noticed :: number) else -1} s after it saw them`
				)
				t.truthy(firstBall ~= nil, `seed {seed}: and once it can reach them it fires`)
				t.truthy(off() < reach, `seed {seed}: it ended {off()} studs off`)
				t.truthy(off() > 12, "but not on top of them")
			end
			-- over whole matches: a little of their time with a target, and never for long
			for _, whole in { { four() }, { eight() } } do
				local s = whole[2] :: Report.Summary
				t.truthy(s.stareShare < 0.12, `{s.stareShare * 100}% of their time with a target`)
				t.truthy(s.stareLongest < 12, `{s.stareLongest} s at the longest`)
			end
		end
	)

	t.test(
		"at a post it looks where there is something to see: not at a wall, not into the pillar it peeks round",
		function()
			-- every sixth place a bot may stand on the upper storeys (the person is on the ground: nobody to see)
			local posts, walls, tried = 0, 0, 0
			local worst, worstAt = 0, 0
			for floor = 2, arena.floors do
				local list = nav.goals[floor]
				for k = 1, #list, 6 do
					local at = list[k]
					local c = closeUp(at, 0, 7 + k)
					local home = arena.spawns[1][1] -- (the person: in their spawn room, where nobody looks)
					c.poses[1].x, c.poses[1].y, c.poses[1].z = home.x, home.y, home.z
					c.brain.mode = "hold"
					c.brain.holdUntil = math.huge
					c.brain.scanAt = c.now -- it looks about as it likes
					tried += 1
					local mine, blocked = 0, 0
					for _ = 1, 12 * Clock.TICK_HZ do
						stepClose(c, DT)
						local pose = c.poses[2]
						if pose.crouch > 0.3 then
							continue -- down behind low cover it is hiding, not looking
						end
						mine += 1
						local ex, ey, ez = Body.eyePoint(pose.x, pose.y, pose.z, pose.crouch)
						local lx, ly, lz = Body.look(pose.yaw, pose.pitch)
						if arena.sweep(ex, ey, ez, ex + lx * 5, ey + ly * 5, ez + lz * 5) ~= nil then
							blocked += 1
						end
					end
					t.eq(c.brain.target, nil)
					posts += mine
					walls += blocked
					if mine > 0 and blocked / mine > worst then
						worst, worstAt = blocked / mine, at
					end
				end
			end
			t.truthy(tried >= 25, `{tried} posts tried`)
			-- (what is left is the look swinging past a pillar on its way from one view to the next)
			t.truthy(walls / posts < 0.04, `{walls / posts} of the time its look ended within 5 studs`)
			t.truthy(worst < 0.2, `at node {worstAt}, {worst} of the time`)
			-- a peek sees: from every peek point a standing eye has a clear view the way the cover faces
			local peeks = 0
			for id, cover in nav.coverAt do
				local node = nav.nodes[id]
				for _, peek in nav.peeks[id] do
					peeks += 1
					local y = node.y + ArenaModule.EYE
					t.eq(
						(arena.sweep(peek.x, y, peek.z, peek.x + cover.nx * 12, y, peek.z + cover.nz * 12)),
						nil,
						`the peek at node {id} sees past its cover`
					)
				end
			end
			t.truthy(peeks >= 40, `{peeks} peeks`)
			-- what a node sees: twelve directions, measured once, kept
			local views = BotNav.views(nav, groundNode(0, -24))
			t.eq(#views, BotNav.VIEWS)
			t.truthy(BotNav.views(nav, groundNode(0, -24)) == views, "kept")
			for _, far in views do
				t.truthy(far > 0 and far <= BotNav.VIEW_FAR)
			end
		end
	)

	t.test(
		"the legs are a person's: the sim holds every step a brain takes to the rules a person's pose is held to",
		function()
			-- seat 1 a scripted person, seat 2 a bot (team 2); no brain runs: the case moves the bot by hand
			local sim = Sim.new({ arena = arena, seed = 5, perSide = 4, dummies = 1, frozen = true })
			Sim.run(sim, sim.start + R.briefingSecs + F.protectSecs + 0.5)
			t.eq(sim.state.phase, "live")
			local team = sim.state.slots[2].team
			local pose = sim.poses[2]
			local walk = Body.speed(0, false, sim.state.feel) * sim.dt
			local sprint = Body.speed(0, true, sim.state.feel) * sim.dt
			-- one step from (x0, 0, z0) to (x1, y1, z1): what the legs' check says of it
			local function step(
				x0: number,
				z0: number,
				x1: number,
				y1: number,
				z1: number,
				bits: number?,
				crouch: number?
			): string?
				pose.x, pose.y, pose.z, pose.crouch, pose.bits = x0, 0, z0, crouch or 0, 0
				sim.legsAt[2] = nil
				table.clear(sim.rec.legs)
				Sim.legs(sim, sim.botWho, true)
				t.eq(next(sim.rec.legs), nil, "standing on open floor is no offence")
				pose.x, pose.y, pose.z, pose.bits = x1, y1, z1, bits or 0
				Sim.legs(sim, sim.botWho, true)
				local why = next(sim.rec.legs)
				return why
			end
			t.eq(step(10, 40, 10 + walk, 0, 40), nil, "a walking step")
			t.eq(step(10, 40, 10 + walk * 1.02, 0, 40), "bot:distance", "a hair over a walking step: no tolerance")
			t.eq(step(10, 40, 10 + sprint, 0, 40, BIT.sprint), nil, "a sprinting step, with the bit shown")
			t.eq(step(10, 40, 10 + sprint, 0, 40), "bot:distance", "the same step without the bit")
			local crouched = Body.speed(1, false, sim.state.feel) * sim.dt
			t.truthy(crouched < walk * 0.8)
			t.eq(step(10, 40, 10 + crouched, 0, 40, BIT.crouch, 1), nil, "a crouched step")
			t.eq(step(10, 40, 10 + walk, 0, 40, BIT.crouch, 1), "bot:distance", "crouched, at a walk")
			t.eq(step(10, 40, 10, 1, 40), "bot:height", "off the floor")
			t.eq(step(10, 40, arena.half + 1, 0, 40), "bot:inside", "out of the building")
			local other = arena.spawns[3 - team][1]
			t.eq(step(10, 40, other.x, other.y, other.z), "bot:room", "the other team's spawn room")
			-- through a box: from a cover spot, straight through what shelters it, to the floor beyond
			local through = 0
			for _, cover in arena.cover do
				local node = arena.nodes[cover.node]
				if node.floor ~= 0 then
					continue
				end
				for d = 1, 8, 0.25 do
					local x, z = node.x + cover.nx * d, node.z + cover.nz * d
					local chest = node.y + ArenaModule.CHEST
					if
						arena.ground(x, node.y + 0.6, z) == node.y
						and arena.sweep(x, chest, z, x, chest + 0.01, z) == nil
						and not ArenaModule.clearPath(arena.sweep, node.x, node.z, x, z, chest)
					then
						t.eq(step(node.x, node.z, x, 0, z), "bot:walls", `through the cover at node {cover.node}`)
						through += 1
						break
					end
				end
			end
			t.truthy(through >= 3, `{through} covers tried`)
			-- out, it stands: any step is an offence
			sim.state.slots[2].out = true
			t.eq(step(10, 40, 10 + walk, 0, 40), "bot:distance", "tagged out, it does not walk")
		end
	)

	t.test(
		"hearing: a ball that goes by, a splat beside it, a team-mate tagged in view; not a ball that stopped short",
		function()
			local at = groundNode(0, -24)
			local function shotPast(): (Close, Bots.Heard)
				-- the person is 40 studs behind the bot and fires a ball that passes 3 studs to its side
				local c = closeUp(at, 0)
				local bx, bz = c.brain.x, c.brain.z
				c.poses[1].x, c.poses[1].z = bx + 3, bz + 40
				return c, { kind = "born", id = 1, x = bx + 3, y = 4.5, z = bz + 40, vx = 0, vy = 0, vz = -90 }
			end
			local c, born = shotPast()
			stepClose(c, DT, { born })
			t.eq(#c.brain.whizz, 1)
			t.eq(c.brain.alertAt, nil, "the ball has not got here yet")
			stepClose(c, 0.5)
			t.truthy(c.brain.alertAt ~= nil or c.brain.alarm > 0, "it heard it go by")
			stepClose(c, 0.5)
			t.truthy(c.brain.alarm > 0)
			local heardAt = c.now - 1 + 40 / 90
			t.truthy(c.brain.alarm - heardAt >= BOT.reactMin - 2 * DT, "it knew after its reaction time, not before")
			t.truthy(c.brain.alarm - heardAt <= BOT.reactMax + 2 * DT)
			stepClose(c, 1)
			t.truthy(angleOff(c, c.poses[1].x, c.poses[1].z) < math.rad(60), "and turned towards where it came from")
			t.truthy(c.brain.con[1] ~= nil and c.brain.con[1].seen > 0, "which is how it comes to see who fired")
			-- the same ball, stopped on something 20 studs short: it never went by
			local short, born2 = shotPast()
			stepClose(short, DT, { born2 })
			t.eq(#short.brain.whizz, 1)
			stepClose(short, DT, { { kind = "ended", id = 1, x = short.brain.x + 3, y = 4, z = short.brain.z + 20 } })
			t.eq(#short.brain.whizz, 0)
			stepClose(short, 1.5)
			t.eq(short.brain.alarm, -math.huge)
			-- a ball that passes 10 studs off is not heard (BOT.hear is 6)
			local wide = closeUp(at, 0)
			stepClose(wide, DT, {
				{
					kind = "born",
					id = 1,
					x = wide.brain.x + 10,
					y = 4.5,
					z = wide.brain.z + 40,
					vx = 0,
					vy = 0,
					vz = -90,
				},
			})
			t.eq(#wide.brain.whizz, 0)
			-- a splat beside it
			local splat = closeUp(at, 0)
			stepClose(splat, DT, {
				{
					kind = "born",
					id = 1,
					x = splat.brain.x + 30,
					y = 4.5,
					z = splat.brain.z + 30,
					vx = -60,
					vy = 0,
					vz = -60,
				},
			})
			stepClose(splat, DT, { { kind = "ended", id = 1, x = splat.brain.x + 2, y = 3, z = splat.brain.z + 2 } })
			t.truthy(splat.brain.alertAt ~= nil)
			-- its own side's ball tells it nothing
			local own = closeUp(at, 0)
			own.state.slots[1].team = 2
			stepClose(own, DT, {
				{
					kind = "born",
					id = 1,
					x = own.brain.x + 3,
					y = 4.5,
					z = own.brain.z + 40,
					vx = 0,
					vy = 0,
					vz = -90,
				},
			})
			t.eq(#own.brain.whizz, 0)
		end
	)

	t.test(
		"a splat beside it: it hears where THAT ball came from, though an older one of the same shooter's still flies",
		function()
			local at = groundNode(0, -24)
			local c = closeUp(at, 0)
			local bx, by, bz = c.brain.x, c.brain.y + 2.7, c.brain.z
			c.poses[1].x, c.poses[1].z = 30, -60 -- (the shooter, out of the bot's sight cone or not: it is heard)
			-- ball one: a long one, fired first, away over the far side of the floor
			local s = F.ballSpeed
			stepClose(c, DT, { { kind = "born", id = 1, x = 30, y = 4.5, z = -60, vx = s, vy = 0, vz = 0 } })
			-- ball two, a moment later from somewhere else, ends against something three studs short of the bot
			local ox, oz = bx - 20, bz
			stepClose(c, 0.1, { { kind = "born", id = 1, x = ox, y = by, z = oz, vx = s, vy = 0, vz = 0 } })
			local ex = bx - 3
			local t0 = c.now
			stepClose(c, DT, { { kind = "ended", id = 1, x = ex, y = by, z = bz } })
			t.truthy(c.brain.alertAt ~= nil and c.brain.alertAt > t0, "it heard the splat")
			t.near(c.brain.alertX, ox, 1e-6, "and took it to come from where the second ball was fired")
			t.near(c.brain.alertZ, oz, 1e-6)
			-- the first ball is still in flight, as far as the bots know: it ends later, far off
			local list = c.bots.flights[1]
			t.eq(#list, 1)
			t.near(list[1].x, 30, 1e-6)
		end
	)

	t.test("it does not follow somebody it cannot see: behind a pillar, the look stays where they went in", function()
		-- the bot stands south of a ground-floor pillar; the person walks east to west across its view,
		-- 30 studs off, and passes behind the pillar on the way
		local c = closeUp(BotNav.nearest(nav, 35, 0, -12, 2), 0)
		c.brain.x, c.brain.z = 35, -12
		c.poses[2].x, c.poses[2].z = 35, -12
		c.brain.yaw = yawTo(35, -12, 50, -45)
		c.brain.scanAt = math.huge
		local px = 55
		c.poses[1].x, c.poses[1].y, c.poses[1].z = px, 0, -45
		local hiddenFor, followed = 0, 0
		local wasSeen = false
		for _ = 1, 8 * Clock.TICK_HZ do
			px -= 5 * DT
			c.poses[1].x = px
			stepClose(c, DT)
			local eye = ArenaModule.EYE
			local clear = arena.sweep(35, eye, -12, px, ArenaModule.CHEST, -45) == nil
			if clear and c.brain.target == 1 then
				wasSeen = true
			end
			if wasSeen and not clear then
				hiddenFor += DT
				-- half a second after it went behind: is the look still within 3 degrees of where it IS?
				if hiddenFor > 0.6 and angleOff(c, px, -45) < math.rad(3) then
					followed += DT
				end
			end
		end
		t.truthy(wasSeen, "it was tracking the person before the pillar")
		t.truthy(hiddenFor > 1, `hidden for {hiddenFor} s`)
		t.truthy(followed < 0.2, `it followed for {followed} s`)
	end)

	t.test("4 v 4 of bots, a whole match: it finishes, both teams score, every click obeys the rules", function()
		local sim, s = four()
		t.truthy(s.finished)
		t.near(s.seconds, R.briefingSecs + R.matchSecs, 2 * DT)
		t.eq(sim.session.phase, "done")
		t.truthy(s.scores[1] >= 20 and s.scores[2] >= 20, `{s.scores[1]} - {s.scores[2]}`)
		t.truthy(s.tags >= 60 and s.tags <= 260, `{s.tags} tags`)
		t.eq(s.scores[1] + s.scores[2], s.tags)
		local result = Rules.result(sim.state) :: Contract.Result
		t.eq(#result.card.rows, 8)
		t.truthy(#result.card.awards >= 5)
		-- the bulletin's awards go round: one a player, and never Top Tagger with Saving It For Later
		local holder: { [number]: string } = {}
		for _, a in result.card.awards do
			t.eq(holder[a.id], nil, `seat {a.id}: {holder[a.id]} and {a.title}`)
			holder[a.id] = a.title
		end
		for _, row in result.card.rows do
			t.truthy(row.shots > 20, `seat {row.id} fired {row.shots} balls`)
			t.truthy(row.accuracy > 0 and row.accuracy < 0.6)
		end
		-- the one judge refused nothing a bot asked for: its own look, its own eye, never from a spawn
		-- room, never sprinting, never an empty or hurried magazine
		t.eq(s.refused, 0)
		t.eq(s.legs, 0, "every step a brain took is one a person could have taken")
		t.eq(s.tooSoon, 0)
		-- the magazine, from the record: never six balls without a reload's wait
		local byShooter: { [number]: { number } } = {}
		for _, shot in sim.rec.shots do
			byShooter[shot.by] = byShooter[shot.by] or {}
			table.insert(byShooter[shot.by], shot.t)
		end
		local gaps, pauses = 0, 0
		for _, times in byShooter do
			for i = 2, #times do
				gaps += 1
				local gap = times[i] - times[i - 1]
				t.truthy(gap >= F.fireInterval - 1e-9)
				if gap > F.fireInterval + 0.1 and gap < 1.5 then
					pauses += 1
				end
			end
			for i = 6, #times do
				t.truthy(times[i] - times[i - 5] >= F.reloadSecs + 4 * F.fireInterval - 1e-9)
			end
		end
		t.truthy(pauses / gaps > 0.12, "bursts and pauses, not a hose")
		-- the same seed plays the same match; another seed another
		local again = Report.summary(Sim.run(Sim.new({ arena = arena, seed = 11, perSide = 4 })))
		t.deepEq(again.scores, s.scores)
		t.eq(again.shots, s.shots)
		local other = Report.summary(Sim.run(Sim.new({ arena = arena, seed = 13, perSide = 4 }), 1000 + 120))
		t.truthy(other.shots > 0)
	end)

	t.test("4 v 4: nobody is stuck, nobody camps a spawn room, nobody is trapped at theirs", function()
		local _, s = four()
		-- (the stuck watch sends a bot off after nine seconds in one place; the rest is the walk away)
		t.truthy(s.still < 14, `the longest stand-still was {s.still} s (seat {s.stillSlot})`)
		t.truthy(s.roomSlowest < 6, `the slowest out of a spawn room took {s.roomSlowest} s`)
		t.truthy(s.roomMean < 3)
		t.truthy(s.camping < 3, `{s.camping} bot-seconds watching the other team's door`)
		t.eq(s.doorTrap, 0, "no bot fires a ball at a quiet player on their own doorstep")
		t.eq(s.outTrap, 0, "nor at somebody in their first seconds out who has not fired")
		t.truthy(s.earlyTags <= math.max(2, 0.03 * s.tags), `{s.earlyTags} tags on somebody just out`)
		-- and no truce, nor anything else, leaves a bot standing with somebody in plain view close by and
		-- not firing: the time to notice, turn, settle and be seen to face them, and no more
		t.truthy(s.held < 1.5, `a bot held its fire {s.held} s on somebody in plain view (seat {s.heldSlot})`)
		t.truthy(
			s.doorStray <= math.max(3, 0.04 * s.tags),
			`{s.doorStray} quiet players walked off their doorstep into a ball meant for somebody else`
		)
		t.truthy(s.lives > 60)
	end)

	t.test("4 v 4: all five storeys, both stairs of each, cover, crouching and sprinting", function()
		local _, s = four()
		for f, share in s.floorShare do
			t.truthy(share >= 0.03, `storey {f} has {share * 100}% of the bots' time`)
		end
		t.truthy(s.floorShare[ArenaModule.SPAWN_FLOOR + 1] < 0.7, "they do not all stay where they spawn")
		for f, uses in s.stairPairs do
			t.eq(#uses, 2)
			for _, n in uses do
				t.truthy(n >= 3, `a flight between storeys {f} and {f + 1} was used {n} times`)
			end
		end
		t.truthy(s.stairBusiest <= 0.8, `one flight had {s.stairBusiest * 100}% of its storey's traffic`)
		t.truthy(s.coverShare > 0.15 and s.coverShare < 0.6, `{s.coverShare * 100}% of the time at cover`)
		t.truthy(s.crouchShare > 0.005, "somebody crouched behind a rail")
		t.truthy(s.sprintShare > 0.05 and s.sprintShare < 0.5)
		-- at a post they look where there is something to see (what is left is a look at where a noise
		-- came from or somebody vanished, and the look swinging past a pillar on its way)
		t.truthy(s.noseShare < 0.22, `at a post their look ended on a wall {s.noseShare * 100}% of the time`)
	end)

	t.test(
		"4 v 4: they miss believably: more at range, at a moving target, with the first ball; and they face whom they tag",
		function()
			local sim, s = four()
			t.truthy(s.accuracy > 0.05 and s.accuracy < 0.3, `{s.accuracy * 100}% of balls tagged their target`)
			local near, mid, far, out = s.byRange[1], s.byRange[2], s.byRange[3], s.byRange[4]
			t.truthy(near.shots >= 20 and mid.shots >= 100 and far.shots >= 100)
			t.truthy(near.rate > mid.rate and mid.rate > far.rate, "the hit rate falls with range")
			t.truthy(far.rate >= out.rate * 0.8)
			t.truthy(near.rate > 0.25, "close up a bot is dangerous")
			local standing, walking = s.bySpeed[1], s.bySpeed[2]
			t.truthy(standing.rate > walking.rate * 1.2, "a moving target is harder")
			-- the warning splat: over a whole match a hit rate by ball is skewed (a third ball at somebody is
			-- only fired when the first two missed, so later balls go at the hard targets; close up the
			-- first ball tags MORE often than the third), so it is read here where the error decides, at
			-- 40 studs and over; it is measured ball by ball, close up, in "the first ball at a new target
			-- is the widest"
			-- (Report's byOrder is of those balls)
			local firstFar, laterFar = s.byOrder[1], s.byOrder[3]
			t.truthy(firstFar.shots >= 100 and laterFar.shots >= 100)
			t.truthy(
				firstFar.rate < 0.6 * laterFar.rate,
				`the first ball is the warning splat: {firstFar.rate * 100}% tagged, later {laterFar.rate * 100}%`
			)
			t.truthy(
				s.faced >= s.facedOf * 0.97,
				`{s.faced} of {s.facedOf} tags from a bot that had been facing its victim`
			)
			-- and every ball, tag or not, was fired at somebody the bot had had in view for BOT.faced
			local aimed, facing = 0, 0
			for _, shot in sim.rec.shots do
				if shot.target ~= nil then
					aimed += 1
					if shot.faced then
						facing += 1
					end
				end
			end
			t.eq(aimed, #sim.rec.shots, "no ball is fired at nobody")
			t.truthy(facing >= aimed * 0.99, `{facing} of {aimed}`)
			-- they talk, and not all the time
			local says = sim.rec.says
			t.truthy(
				(says.floor or 0) > 5 and (says.reloading or 0) > 5 and (says.tagged or 0) > 2 and (says.out or 0) > 2
			)
			local total = 0
			for line, n in says do
				t.truthy((Contract.LINES :: any)[line] ~= nil, line)
				total += n
			end
			t.truthy(total < R.matchSecs / 2, `{total} call-outs in a match`)
		end
	)

	t.test("8 v 8 of bots, a whole match: sixteen play it to the end inside the cost and the sight budget", function()
		local sim, s = eight()
		t.truthy(s.finished)
		t.eq(s.botCount, 16)
		t.truthy(s.scores[1] >= 40 and s.scores[2] >= 40, `{s.scores[1]} - {s.scores[2]}`)
		t.eq(#(Rules.result(sim.state) :: Contract.Result).card.rows, 16)
		t.eq(s.refused, 0)
		t.eq(s.legs, 0, "every step a brain took is one a person could have taken")
		t.eq(s.tooSoon, 0)
		t.truthy(s.still < 14, `the longest stand-still was {s.still} s (seat {s.stillSlot})`)
		t.truthy(s.roomSlowest < 6)
		t.truthy(s.camping < 4)
		t.eq(s.doorTrap, 0, "no bot fires a ball at a quiet player on their own doorstep")
		for f, share in s.floorShare do
			t.truthy(share >= 0.03, `storey {f}`)
		end
		t.truthy(s.stairBusiest <= 0.8)
		t.truthy(s.faced >= s.facedOf * 0.97)
		-- PB-15: the bots' share is 0.5 ms a tick at 15 bots; sixteen come in far under it here (the
		-- bound is loose because other work shares this machine)
		t.truthy(s.botMs < Contract.COST.botsMs, `{s.botMs} ms a tick`)
		-- sight checks: no bot more than BOT.sightHz a second, no tick more than its share
		t.truthy(s.sweepsSecond <= s.sweepsCap, `{s.sweepsSecond} sight checks in a second, cap {s.sweepsCap}`)
		t.truthy(s.sweepsTick <= math.ceil(16 * BOT.sightHz * DT), `{s.sweepsTick} in one tick`)
		t.truthy(s.sweepsSecond > s.sweepsCap * 0.5, "and they do look")
	end)

	t.test(
		"against a scripted target: standing still is how to get tagged; walking is harder, sprinting harder still",
		function()
			local function beat(mode: string): (number, number)
				local speed = if mode == "still" then 0 elseif mode == "walk" then Body.WALK else Body.SPRINT
				local shots, hits = 0, 0
				for seed = 1, 4 do
					local dir = 1
					local sim = Sim.new({
						arena = arena,
						seed = 20 + seed,
						perSide = 4,
						dummies = 1,
						script = function(world: any, id: number, pose: Contract.Pose, _now: number, dt: number)
							if pose.y < 27 or pose.z < 30 then
								Sim.teleport(world, id, 0, 28, 40, 0) -- out of the spawn room, onto its beat
							end
							pose.x += dir * speed * dt
							if pose.x > 22 then
								dir = -1
							elseif pose.x < -22 then
								dir = 1
							end
							pose.bits = if mode == "sprint" then BIT.sprint else 0
						end,
					})
					Sim.run(sim, sim.start + 200)
					for _, shot in sim.rec.shots do
						if shot.target == 1 then
							shots += 1
							if shot.tagged then
								hits += 1
							end
							t.truthy(shot.faced, "fired at the scripted person only after facing it")
						end
					end
					t.eq(sim.state.slots[1].shots, 0, "the scripted person never fires")
				end
				return shots, hits
			end
			local stillShots, stillHits = beat("still")
			local walkShots, walkHits = beat("walk")
			local runShots, runHits = beat("sprint")
			t.truthy(stillShots > 200 and walkShots > 200 and runShots > 200)
			local still, walk, run = stillHits / stillShots, walkHits / walkShots, runHits / runShots
			-- (over eight matches each: about one ball in five, one in ten, one in sixteen; four
			-- matches each here, and the bands leave room for their luck)
			t.truthy(still > 0.12 and still < 0.5, `standing: {still * 100}%`)
			t.truthy(walk < still * 0.8, `walking: {walk * 100}% against {still * 100}%`)
			t.truthy(run < walk * 1.1, `sprinting: {run * 100}% against {walk * 100}%`)
			t.truthy(run < still * 0.6, `sprinting: {run * 100}% against {still * 100}% standing`)
			t.truthy(run > 0.01, "but nobody is safe")
		end
	)

	t.test(
		"a bot and a person are judged by one rule: the same click in the same place gets the same answer",
		function()
			-- seat 1 is a scripted person (team 1), seat 2 a bot (team 2); no brain runs: the case moves both
			local sim = Sim.new({ arena = arena, seed = 5, perSide = 4, dummies = 1, frozen = true })
			Sim.run(sim, sim.start + R.briefingSecs + F.protectSecs + 0.5)
			t.eq(sim.state.phase, "live")
			t.truthy(sim.botWho[2] ~= nil and sim.dummyWho[1])
			local speed = sim.state.feel.ballSpeed
			local function put(id: number, x: number, y: number, z: number, yaw: number, bits: number?)
				Sim.teleport(sim, id, x, y, z, yaw)
				sim.poses[id].crouch, sim.poses[id].bits = 0, bits or 0
				sim.sprintAt[id] = nil
			end
			local function click(id: number, off: number?): (boolean, string?)
				local pose = sim.poses[id]
				local ex, ey, ez = Body.eyePoint(pose.x, pose.y, pose.z, pose.crouch)
				local lx, ly, lz = Body.look(pose.yaw + (off or 0), pose.pitch)
				return Sim.judge(sim, id, ex, ey, ez, lx * speed, ly * speed, lz * speed)
			end
			local function both(label: string, prepare: (id: number) -> (), expect: { any }, off: number?)
				for _, id in { 1, 2 } do
					prepare(id)
					t.deepEq({ click(id, off) }, expect, `{label}, seat {id}`)
				end
			end
			-- from inside a spawn room (its own): refused
			both("in the spawn room", function(id: number)
				local sp = arena.spawns[sim.state.slots[id].team][1]
				put(id, sp.x, sp.y, sp.z, sp.yaw)
			end, { false, "safe" })
			-- in the open: a direction that is not the pose's own look is refused; the look itself is a ball
			local function open(id: number)
				put(id, if id == 1 then -10 else 10, 0, 40, if id == 1 then -math.pi / 2 else math.pi / 2)
			end
			both("off its look", open, { false, "look" }, BOT.aimSlack * 1.5)
			both("sprinting", function(id: number)
				open(id)
				sim.poses[id].bits = BIT.sprint
			end, { false, "sprint" })
			both("just stopped sprinting", function(id: number)
				open(id)
				sim.sprintAt[id] = sim.now - 0.05
			end, { false, "sprint" })
			both("the marker is up again", function(id: number)
				open(id)
				sim.sprintAt[id] = sim.now - Body.SPRINT_FIRE_DELAY
			end, { true, nil })
			both("too soon after", open, { false, "fast" })
			-- the magazine runs out for both after the same five, and both are told the same
			for _, id in { 1, 2 } do
				local n = 1
				while n < R.magazine do
					Sim.run(sim, sim.now + F.fireInterval)
					open(id)
					t.deepEq({ click(id) }, { true, nil } :: { any })
					n += 1
				end
				Sim.run(sim, sim.now + F.fireInterval)
				open(id)
				t.deepEq({ click(id) }, { false, "empty" } :: { any }, `seat {id} is reloading`)
			end
			Sim.run(sim, sim.now + F.reloadSecs)
			-- face to face, 20 studs apart: each one's ball tags the other, after the same flight
			local flights = {}
			for _, pair in { { 1, 2 }, { 2, 1 } } do
				local by, id = pair[1], pair[2]
				open(1)
				open(2)
				Sim.run(sim, sim.now + 0.3) -- (the history must have both where they stand)
				local pose = sim.poses[by]
				local ex, ey, ez = Body.eyePoint(pose.x, pose.y, pose.z, 0)
				local lx, ly, lz = Body.look(pose.yaw, 0)
				local tags = #sim.rec.tags
				t.truthy(Sim.shoot(sim, by, ex, ey, ez, lx * speed, ly * speed, lz * speed))
				local born = sim.now
				Sim.run(sim, sim.now + 0.5)
				t.eq(#sim.rec.tags, tags + 1, `seat {by}'s ball tagged`)
				local tag = sim.rec.tags[#sim.rec.tags]
				t.deepEq({ tag.by, tag.id }, { by, id })
				table.insert(flights, tag.t - born)
				t.truthy(sim.state.slots[id].out)
				Sim.run(sim, sim.now + F.respawnSecs + F.protectSecs + 0.2)
			end
			t.near(flights[1], flights[2], 1e-9, "the same flight either way")
			-- protected, both are passed through; in its own room, both are passed through
			for _, pair in { { 1, 2 }, { 2, 1 } } do
				local by, id = pair[1], pair[2]
				open(1)
				open(2)
				Sim.run(sim, sim.now + 0.3)
				sim.state.slots[id].safeUntil = sim.now + 1
				local pose = sim.poses[by]
				local ex, ey, ez = Body.eyePoint(pose.x, pose.y, pose.z, 0)
				local lx, ly, lz = Body.look(pose.yaw, 0)
				local tags = #sim.rec.tags
				t.truthy(Sim.shoot(sim, by, ex, ey, ez, lx * speed, ly * speed, lz * speed))
				Sim.run(sim, sim.now + 1.2)
				t.eq(#sim.rec.tags, tags, `seat {id} was protected`)
			end
			t.eq(sim.rec.firedTooSoon, 0)
		end
	)

	t.test("with the stand-in fair player: a match the bots neither walk over nor are walked over in", function()
		local sim, s = match("fair", function()
			return Sim.new({ arena = arena, seed = 31, perSide = 4, people = 1, skill = 0.5, audit = true })
		end)
		t.truthy(s.finished)
		t.eq(s.botCount, 7)
		t.truthy(s.personTags + s.personOuts >= 15, `{s.personTags} : {s.personOuts}`)
		-- about three in five over many matches (calibrate.luau prints the figure); one match is a
		-- wide band round it
		t.truthy(s.personWin > 0.35 and s.personWin < 0.85, `the stand-in won {s.personWin * 100}% of its exchanges`)
		t.eq(s.refused, 0, "the stand-in's clicks pass the same judge")
		t.eq(s.legs, 0, "every step a brain took is one a person could have taken")
		t.truthy(s.stares <= 2, `{s.stares} times a bot followed somebody through a wall`)
		t.eq(s.doorTrap, 0)
		t.eq(s.outTrap, 0)
		t.truthy(s.held < 1.5, `a bot held its fire {s.held} s on somebody in plain view (seat {s.heldSlot})`)
		t.truthy(s.still < 14)
		-- one of its team's bots keeps it company (tests/unit/paintball_bots_team.spec.luau)
		t.truthy(
			s.personCompany > 0.35 and s.personCompany > s.botCompany + 0.1,
			`a bot of its team was near the stand-in {s.personCompany * 100}% of the time, near another bot {s.botCompany * 100}%`
		)
		-- the bots tagged the person only after facing them (a ball meant for somebody else that the person
		-- walked into is nobody's aim)
		for _, tag in sim.rec.tags do
			if tag.byBot and not tag.idBot and not tag.stray then
				t.truthy(tag.faced, "a bot that tags a person has been seen to turn on them")
			end
		end
	end)

	t.test("a faster ball is still a match: the feel is the match's own, at 120 and 150 studs a second", function()
		for _, speed in { 120, 150 } do
			local sim =
				Sim.new({ arena = arena, seed = 40 + speed, perSide = 4, feel = Contract.feel({ ballSpeed = speed }) })
			Sim.run(sim, sim.start + 150)
			local s = Report.summary(sim)
			t.eq(sim.state.feel.ballSpeed, speed)
			t.truthy(s.tags > 10, `{s.tags} tags in 140 s at {speed}`)
			t.eq(s.refused, 0)
			t.eq(s.legs, 0, "every step a brain took is one a person could have taken")
			for _, ball in sim.balls do
				local v = math.sqrt(ball.vx ^ 2 + ball.vy ^ 2 + ball.vz ^ 2)
				t.near(v, speed, 1e-6)
			end
		end
	end)
end
