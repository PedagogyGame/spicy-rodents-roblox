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
local ArenaModule = require("@shared/Minigames/Paintball/Arena")
local Body = require("@shared/Minigames/Paintball/Body")
local Clock = require("@shared/Minigames/Paintball/Clock")
local Contract = require("@shared/Minigames/Paintball/Contract")
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
		t.truthy(#result.card.awards >= 4)
		for _, row in result.card.rows do
			t.truthy(row.shots > 20, `seat {row.id} fired {row.shots} balls`)
			t.truthy(row.accuracy > 0 and row.accuracy < 0.6)
		end
		-- the one judge refused nothing a bot asked for: its own look, its own eye, never from a spawn
		-- room, never sprinting, never an empty or hurried magazine
		t.eq(s.refused, 0)
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
			local first, later = s.byOrder[1], s.byOrder[3]
			t.truthy(first.rate < later.rate * 0.8, "the first ball is the warning splat")
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
		t.truthy(s.stares <= 2, `{s.stares} times a bot followed somebody through a wall`)
		t.eq(s.doorTrap, 0)
		t.truthy(s.still < 14)
		-- one of its team's bots keeps it company (tests/unit/paintball_bots_team.spec.luau)
		t.truthy(
			s.personCompany > 0.35 and s.personCompany > s.botCompany + 0.1,
			`a bot of its team was near the stand-in {s.personCompany * 100}% of the time, near another bot {s.botCompany * 100}%`
		)
		-- the bots tagged the person only after facing them
		for _, tag in sim.rec.tags do
			if tag.byBot and not tag.idBot then
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
			for _, ball in sim.balls do
				local v = math.sqrt(ball.vx ^ 2 + ball.vy ^ 2 + ball.vz ^ 2)
				t.near(v, speed, 1e-6)
			end
		end
	end)
end
