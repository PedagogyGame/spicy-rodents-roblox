--!strict
-- The paintball bots AS TEAM-MATES (Server/Minigames/Paintball/Bots, BotBrain; checklist PB-10): what a
-- bot does for a person on its own side. One bot of a small team (two of a big one) keeps a person
-- company: its posts are a short run from where they are, it follows them to another storey, and it is
-- back beside them after either has been tagged out. And a team's bots are told what a person's play
-- shows anybody: where their paint landed, and where one of their own went down.
-- On the lane's own test building (tools/games/paintball/bots/Greybox), like paintball_bots.spec.luau.
local Clock = require("@shared/Minigames/Paintball/Clock")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Rules = require("@shared/Minigames/Paintball/Rules")
local BotBrain = require("@server/Minigames/Paintball/BotBrain")
local BotNav = require("@server/Minigames/Paintball/BotNav")
local Bots = require("@server/Minigames/Paintball/Bots")
local Greybox = require("../../tools/games/paintball/bots/Greybox")
local Report = require("../../tools/games/paintball/bots/Report")
local Sim = require("../../tools/games/paintball/bots/Sim")

local R = Contract.Rules
local F = Contract.FEEL
local DT = 1 / Clock.TICK_HZ
local NEAR = 35 -- studs: a team-mate this near on the same storey is company (the Sim's own measure)

local arena = Greybox.build()
local nav = BotNav.build(arena)

-- a place for a person to stand on a storey: the `pick`th cover spot that is nobody's doorstep
local function post(floor: number, pick: number): { x: number, y: number, z: number }
	local n = 0
	for _, id in nav.goals[floor + 1] do
		if nav.coverAt[id] ~= nil and not nav.keepOff[1][id] and not nav.keepOff[2][id] then
			n += 1
			if n == pick then
				return nav.nodes[id]
			end
		end
	end
	error(`storey {floor + 1} has no such post`)
end

-- A hand-built live match of three: seat 1 a person (team 1), seat 2 a bot of the other team, seat 3 a
-- bot of the person's.
local function three(): (Rules.State, Bots.Bots, { [number]: Contract.Pose }, number)
	local state = Rules.init(3, 5)
	Rules.sync(state, 100)
	local now = 100 + R.briefingSecs + F.protectSecs + 1
	Rules.sync(state, now - 5)
	Rules.step(state, 0)
	Rules.sync(state, now)
	Rules.step(state, 0)
	Rules.drain(state)
	assert(state.phase == "live" and state.slots[3].team == 1 and state.slots[2].team == 2, "the three")
	local bots = Bots.new(arena, { seed = 3 })
	local a, b, c = post(2, 1), post(2, 2), post(2, 3)
	local poses: { [number]: Contract.Pose } = {
		{ x = a.x, y = a.y, z = a.z, yaw = 0, pitch = 0, crouch = 0, bits = 0 },
		{ x = b.x, y = b.y, z = b.z, yaw = 0, pitch = 0, crouch = 0, bits = 0 },
		{ x = c.x, y = c.y, z = c.z, yaw = 0, pitch = 0, crouch = 0, bits = 0 },
	}
	Bots.sync(bots, state, { [2] = 0.5, [3] = 0.5 }, poses, now)
	return state, bots, poses, now
end

return function(t)
	t.test("a person's paint tells their team where the fight is; a bot's own tells nobody anything new", function()
		local state, bots, poses, now = three()
		local squad = bots.squad
		-- (the other team's bot is out for these few ticks, so that nobody SEES anybody: what the team
		-- knows below, it was told)
		t.truthy(Rules.tag(state, 3, 2, now))
		Bots.step(bots, state, poses, {}, now + DT, DT)
		t.eq(squad.people[1], 1, "seat 1 is a person of team 1, as far as the bots can tell")
		t.eq(squad.people[2], nil)
		t.eq(squad.people[3], nil)
		t.eq(squad.heat[1][5], -math.huge)
		-- the person fires up at the fifth storey and the ball lands there
		local up = 4 * arena.floorHeight
		now += 2 * DT
		Bots.step(bots, state, poses, {
			{ kind = "born", id = 1, x = poses[1].x, y = poses[1].y + 5, z = poses[1].z, vx = 0, vy = 60, vz = 60 },
		}, now, DT)
		now += DT
		Bots.step(bots, state, poses, { { kind = "ended", id = 1, x = 10, y = up + 3, z = 20 } }, now, DT)
		t.eq(squad.heat[1][5], now, "their team takes the fifth storey to be where somebody is")
		t.eq(squad.spot[1].at, now)
		t.near(squad.spot[1].x, 10, 1e-9)
		t.near(squad.spot[1].y, up, 1e-9)
		t.eq(squad.heat[2][5], -math.huge, "the other team is told nothing by it")
		-- a bot's ball: its team knew what it saw when it aimed
		now += DT
		Bots.step(bots, state, poses, {
			{ kind = "born", id = 3, x = poses[3].x, y = poses[3].y + 5, z = poses[3].z, vx = 0, vy = -60, vz = 60 },
		}, now, DT)
		now += DT
		local before = squad.spot[1].at
		Bots.step(bots, state, poses, { { kind = "ended", id = 3, x = -10, y = 3, z = -20 } }, now, DT)
		t.eq(squad.spot[1].at, before)
		t.eq(squad.heat[1][1], -math.huge)
	end)

	t.test("a team-mate tagged out is a place the team knows of, when it knows nothing newer", function()
		local state, bots, poses, now = three()
		local squad = bots.squad
		now += DT
		Bots.step(bots, state, poses, {}, now, DT)
		-- the person is tagged on the ground floor by the other team's bot
		t.truthy(Rules.tag(state, 2, 1, now))
		now += DT
		Bots.step(bots, state, poses, { { kind = "tag", id = 1, by = 2, x = 30, y = 4, z = -12 } }, now, DT)
		t.eq(squad.spot[1].at, now)
		t.near(squad.spot[1].x, 30, 1e-9)
		t.eq(squad.heat[1][1], now)
		t.eq(squad.spot[2].at, -math.huge, "the tagger's team learns nothing from it")
	end)

	t.test(
		"company: one bot of a small team stays within a short run of a person, on whatever storey they go to",
		function()
			local total, with = 0, 0
			for seed = 51, 52 do
				local where = post(4, 3) -- the fifth storey, two flights from the spawn rooms
				local sim = Sim.new({
					arena = arena,
					seed = seed,
					perSide = 4,
					dummies = 1,
					script = function(world: any, id: number, pose: Contract.Pose, _now: number, _dt: number)
						-- the scripted person stands at its post; a respawn walks it straight back
						if BotNav.roomOf(nav, pose.x, pose.y, pose.z) ~= 0 or math.abs(pose.y - where.y) > 1 then
							Sim.teleport(world, id, where.x, where.y, where.z, 0)
						end
					end,
				})
				local me = sim.state.slots[1]
				local live = sim.start + R.briefingSecs
				local function watch(from: number, to: number)
					while sim.now < to do
						Sim.tick(sim)
						local escorts = 0
						for bot, who in sim.bots.squad.escort do
							t.eq(who, 1, "only the person is kept company")
							t.eq(sim.state.slots[bot].team, me.team, "and only by their own side")
							escorts += 1
						end
						t.truthy(escorts <= 1, "one of a team of three bots, no more")
						local pose = sim.poses[1]
						if sim.now < from or me.out or pose == nil then
							continue
						end
						total += 1
						for id, mate in sim.state.slots do
							local p = sim.poses[id]
							if
								id ~= 1
								and p ~= nil
								and mate.team == me.team
								and not mate.out
								and math.abs(p.y - pose.y) < 5
								and (p.x - pose.x) ^ 2 + (p.z - pose.z) ^ 2 < NEAR * NEAR
							then
								with += 1
								break
							end
						end
					end
				end
				-- time to get there, then 45 s watched; the same again on the ground floor
				watch(live + 25, live + 70)
				where = post(0, 5)
				watch(live + 95, live + 140)
				-- nobody's company is a reason to break the rules
				local s = Report.summary(sim)
				t.eq(s.refused, 0)
				t.eq(s.legs, 0, "every step a brain took is one a person could have taken")
				t.eq(s.doorTrap, 0)
				t.truthy(s.still < 14, `the longest stand-still was {s.still} s (seat {s.stillSlot})`)
			end
			-- (a bot that is alone up there is tagged out now and then and has two flights to climb
			-- back: about half the time over many matches, against a tenth for a team that does not care)
			t.truthy(with / total > 0.4, `a team-mate was near {with / total * 100}% of the time`)
		end
	)

	t.test("company costs nothing when there is nobody to keep it with, and ends when the person leaves", function()
		local sim = Sim.new({ arena = arena, seed = 53, perSide = 4, dummies = 1 })
		Sim.run(sim, sim.start + R.briefingSecs + 30)
		local had = 0
		for _ in sim.bots.squad.escort do
			had += 1
		end
		t.truthy(had <= 1)
		-- the person leaves and a bot takes the seat: nobody keeps a bot company
		Rules.gone(sim.state, 1)
		Rules.join(sim.state, 1)
		sim.botWho[1] = 0.5
		sim.dummyWho[1] = nil
		Bots.sync(sim.bots, sim.state, sim.botWho, sim.seenByBots, sim.now)
		Sim.run(sim, sim.now + 30)
		t.eq(next(sim.bots.squad.people), nil, "eight bots and no people")
		t.eq(next(sim.bots.squad.escort), nil)
		t.truthy((sim.bots.brains :: { [number]: BotBrain.Brain })[1] ~= nil)
	end)

	t.test("8 v 8 with a person: two bots of a big team may keep them company; the match is still a match", function()
		local sim = Sim.run(Sim.new({ arena = arena, seed = 54, perSide = 8, people = 1 }), 1000 + 200)
		local s = Report.summary(sim)
		local escorts = 0
		for _, who in sim.bots.squad.escort do
			t.eq(who, 1)
			escorts += 1
		end
		t.truthy(escorts <= 2)
		t.truthy(s.personCompany > 0.5, `a bot of its team was near the stand-in {s.personCompany * 100}% of the time`)
		t.truthy(s.scores[1] > 30 and s.scores[2] > 30, `{s.scores[1]} - {s.scores[2]}`)
		t.eq(s.refused, 0)
		t.eq(s.legs, 0, "every step a brain took is one a person could have taken")
	end)
end
