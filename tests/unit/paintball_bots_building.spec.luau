--!strict
-- The paintball bots IN THE GAME'S OWN BUILDING (Shared/Minigames/Paintball/ArenaData.build(), whatever
-- the arena lane has made of it; checklist PB-6, PB-10, PB-15): whole matches played headless
-- (tools/games/paintball/bots/Sim: the real Session, Rules and Bots, the lane's own ball loop), 4 v 4
-- and 8 v 8 of bots alone and a match with the stand-in fair player, each with a fixed seed, each run
-- once and shared by the cases that read it.
-- THIS SPEC KNOWS NOTHING OF THE BUILDING BUT ITS DATA: no case names a coordinate, a node or a stair.
-- Its bands are wide on purpose: they are what must be true of the bots in ANY arena that passes
-- Arena.check (they finish the match, both sides score, nobody is stuck, trapped or camped on, every
-- storey and at least two flights between each pair are used, the bots miss more at range and at a
-- moving target, they face whom they tag, they stay inside their cost), so that a re-planned building
-- fails this only if the bots really cannot play in it. The narrow bands and the close-up cases are in
-- tests/unit/paintball_bots.spec.luau, on the lane's own test building.
-- (To look at a match here: lune run tools/games/paintball/bots/match.luau <seed> <a side>.)
local ArenaModule = require("@shared/Minigames/Paintball/Arena")
local ArenaData = require("@shared/Minigames/Paintball/ArenaData")
local Clock = require("@shared/Minigames/Paintball/Clock")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Rules = require("@shared/Minigames/Paintball/Rules")
local BotBrain = require("@server/Minigames/Paintball/BotBrain")
local BotCheck = require("@server/Minigames/Paintball/BotCheck")
local BotNav = require("@server/Minigames/Paintball/BotNav")
local Report = require("../../tools/games/paintball/bots/Report")
local Sim = require("../../tools/games/paintball/bots/Sim")

local R = Contract.Rules
local F = Contract.FEEL
local BOT = Contract.BOT
local DT = 1 / Clock.TICK_HZ

local arena = ArenaData.build()
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

-- what is true of the bots in a whole match of any size
local function sound(t: any, sim: Sim.Sim, s: Report.Summary, seats: number)
	t.truthy(s.finished, "the match ran to its end")
	t.near(s.seconds, R.briefingSecs + R.matchSecs, 2 * DT)
	t.eq(sim.session.phase, "done")
	t.eq(s.scores[1] + s.scores[2], s.tags)
	local result = Rules.result(sim.state) :: Contract.Result
	t.eq(#result.card.rows, seats)
	t.truthy(#result.card.awards >= 5)
	-- the bulletin's awards go round: one a player, and never Top Tagger with Saving It For Later
	local holder: { [number]: string } = {}
	for _, a in result.card.awards do
		t.eq(holder[a.id], nil, `seat {a.id}: {holder[a.id]} and {a.title}`)
		holder[a.id] = a.title
	end
	-- the one judge refused nothing a bot asked for: its own look, its own eye, never from a spawn
	-- room, never sprinting, never an empty or hurried magazine
	t.eq(s.refused, 0, "no command of a bot's was refused")
	t.eq(s.legs, 0, "every step a brain took is one a person could have taken")
	t.eq(s.tooSoon, 0)
	-- nobody stuck, nobody kept in or camped on
	t.truthy(s.still < 16, `the longest stand-still was {s.still} s (seat {s.stillSlot})`)
	t.truthy(s.roomSlowest < 6, `the slowest out of a spawn room took {s.roomSlowest} s`)
	t.truthy(s.roomMean < 3, `out of the spawn room in {s.roomMean} s on average`)
	t.truthy(s.camping < 4, `{s.camping} bot-seconds watching the other team's door`)
	t.eq(s.doorTrap, 0, "no bot fires a ball at a quiet player on their own doorstep")
	t.eq(s.outTrap, 0, "nor at somebody in their first seconds out who has not fired")
	-- (no truce, nor anything else, leaves a bot standing with somebody in plain view close by and not
	-- firing: the time to notice, turn, settle and face them, and no more; in the melee of sixteen a
	-- bot's ten sight checks a second go round more opponents, and a sighting takes longer to start)
	local heldMost = if seats >= 16 then 2 else 1.5
	t.truthy(s.held < heldMost, `a bot held its fire {s.held} s on somebody in plain view (seat {s.heldSlot})`)
	t.truthy(
		s.doorStray <= math.max(3, 0.04 * s.tags),
		`{s.doorStray} quiet players walked off their doorstep into a ball meant for somebody else`
	)
	-- the whole building
	for f, share in s.floorShare do
		t.truthy(share >= 0.03, `storey {f} has {share * 100}% of the bots' time`)
	end
	t.truthy(s.floorShare[ArenaModule.SPAWN_FLOOR + 1] < 0.7, "they do not all stay where they spawn")
	for f, uses in s.stairPairs do
		local busy = 0
		for _, n in uses do
			if n >= 3 then
				busy += 1
			end
		end
		t.truthy(busy >= 2, `between storeys {f} and {f + 1} only {busy} flights were used`)
	end
	t.truthy(s.stairBusiest <= 0.85, `one flight had {s.stairBusiest * 100}% of its storey's traffic`)
	-- they face whom they tag
	t.truthy(s.faced >= s.facedOf * 0.97, `{s.faced} of {s.facedOf} tags from a bot that had been facing its victim`)
	-- and they miss believably: more at range, and with the first ball at somebody (read where the
	-- error decides: see Report's byOrder)
	t.truthy(s.byRange[1].rate > s.byRange[3].rate * 2, "the hit rate falls with range")
	local first, later = s.byOrder[1], s.byOrder[3]
	if first.shots >= 50 and later.shots >= 50 then
		t.truthy(
			first.rate < later.rate,
			`the first ball is the warning splat: {first.rate * 100}% tagged, later {later.rate * 100}%`
		)
	end
end

return function(t)
	t.test("the building is one a bot can read: doors, a way out for every spawn point, places to go", function()
		local ok, problems = ArenaModule.check(arena, R.teamMax)
		t.truthy(ok, table.concat(problems, "; "))
		t.eq(nav.count, #arena.nodes)
		for team = 1, 2 do
			t.truthy(#nav.doors[team] >= 2, "two ways out")
			for _, id in nav.doors[team] do
				t.eq(arena.nodes[id].team, 0, "a door node is outside the room")
				t.truthy(nav.keepOff[3 - team][id], "the other team keeps off it")
			end
			t.truthy(#arena.spawns[team] >= R.teamMax)
			for index, sp in arena.spawns[team] do
				local entry = arena.nodes[nav.entry[team][index]]
				t.truthy(entry ~= nil, `spawn point {index} of team {team} has a node to walk to`)
				t.eq(entry.team, team)
				local c = ArenaModule.CHEST
				t.eq(arena.sweep(sp.x, sp.y + c, sp.z, entry.x, entry.y + c, entry.z), nil)
				-- and from there a way out to every storey, never through the other team's room
				local taste = BotNav.taste(nav, index)
				for f = 1, arena.floors do
					local goals = nav.goals[f]
					local to = goals[(index * 7) % #goals + 1]
					local path = BotNav.route(nav, entry.id, nil, 0, to, team, taste)
					t.truthy(path ~= nil, `team {team} can walk from spawn point {index} to storey {f}`)
					for _, id in path :: { number } do
						t.truthy(arena.nodes[id].team ~= 3 - team)
					end
				end
			end
		end
		local cover = 0
		for _ in nav.coverAt do
			cover += 1
		end
		t.truthy(cover >= 20, `{cover} cover spots`)
		for f = 1, arena.floors do
			t.truthy(#nav.goals[f] > 10, `storey {f} has places to go`)
		end
		-- however wide the building's pillars and wall ends are, a peek is a step that SEES: from each
		-- one a standing eye has a clear view the way its cover faces, and it is a step a body can take
		local peeks, high = 0, 0
		for id, c in nav.coverAt do
			local node = nav.nodes[id]
			if not c.low then
				high += 1
			end
			for _, peek in nav.peeks[id] do
				peeks += 1
				local y = node.y + ArenaModule.EYE
				t.eq(
					(arena.sweep(peek.x, y, peek.z, peek.x + c.nx * 12, y, peek.z + c.nz * 12)),
					nil,
					`peek at node {id}`
				)
				t.truthy(ArenaModule.clearPath(arena.sweep, node.x, node.z, peek.x, peek.z, node.y + ArenaModule.CHEST))
				t.near(arena.ground(peek.x, node.y + 0.5, peek.z) :: number, node.y, 0.05)
				t.truthy((peek.x - node.x) ^ 2 + (peek.z - node.z) ^ 2 <= 5.01 ^ 2, "a step, not a walk")
			end
		end
		t.truthy(peeks >= high * 0.5, `{peeks} peeks for {high} high cover spots`)
	end)

	t.test("4 v 4 of bots, a whole match: it finishes, both teams score, nobody is stuck or trapped", function()
		local sim, s = four()
		sound(t, sim, s, 8)
		t.truthy(s.scores[1] >= 10 and s.scores[2] >= 10, `{s.scores[1]} - {s.scores[2]}`)
		t.truthy(s.tags >= 40 and s.tags <= 300, `{s.tags} tags`)
		t.truthy(s.lives > 40)
		for _, row in (Rules.result(sim.state) :: Contract.Result).card.rows do
			t.truthy(row.shots >= 10, `seat {row.id} fired {row.shots} balls`)
			t.truthy(row.accuracy < 0.7)
		end
		-- the same seed plays the same match
		local again = Report.summary(Sim.run(Sim.new({ arena = arena, seed = 11, perSide = 4 })))
		t.deepEq(again.scores, s.scores)
		t.eq(again.shots, s.shots)
	end)

	t.test("4 v 4: they miss believably, in bursts, from cover, on the run; and say so", function()
		local sim, s = four()
		t.truthy(s.accuracy > 0.04 and s.accuracy < 0.4, `{s.accuracy * 100}% of balls tagged their target`)
		-- the hit rate falls with range: under 20 studs against over 40
		local near, mid, far, out = s.byRange[1], s.byRange[2], s.byRange[3], s.byRange[4]
		local farShots, farTags = far.shots + out.shots, far.tags + out.tags
		t.truthy(near.shots >= 20 and farShots >= 20, `{near.shots} near, {farShots} far`)
		t.truthy(near.rate > mid.rate, `near {near.rate}, mid {mid.rate}`)
		t.truthy(mid.rate > farTags / farShots * 0.9, `mid {mid.rate}, far {farTags / farShots}`)
		t.truthy(near.rate > 0.25 and near.rate < 0.75, "close up a bot is dangerous, and not certain")
		-- a moving target is harder
		local standing, walking = s.bySpeed[1], s.bySpeed[2]
		t.truthy(standing.shots >= 40 and walking.shots >= 40)
		t.truthy(standing.rate > walking.rate * 1.2, `standing {standing.rate}, walking {walking.rate}`)
		-- every ball was fired at somebody the bot had had in view for BOT.faced
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
		t.truthy(facing >= aimed * 0.98, `{facing} of {aimed}`)
		-- the magazine, from the record: never inside the fire interval, never six without a reload's
		-- wait; and bursts with pauses, not a hose
		local byShooter: { [number]: { number } } = {}
		for _, shot in sim.rec.shots do
			byShooter[shot.by] = byShooter[shot.by] or {}
			table.insert(byShooter[shot.by], shot.t)
		end
		local runs, hosed = 0, 0
		for _, times in byShooter do
			local run = 1
			for i = 2, #times do
				local gap = times[i] - times[i - 1]
				t.truthy(gap >= F.fireInterval - 1e-9)
				if gap <= F.fireInterval + 0.1 then
					run += 1
				else
					runs += 1
					if run > BotBrain.DEFAULT.burstMax then
						hosed += 1
					end
					run = 1
				end
			end
			for i = 6, #times do
				t.truthy(times[i] - times[i - 5] >= F.reloadSecs + 4 * F.fireInterval - 1e-9)
			end
		end
		t.truthy(runs > 30)
		t.truthy(hosed <= runs * 0.15, `{hosed} of {runs} bursts ran on past {BotBrain.DEFAULT.burstMax} balls`)
		-- cover, the crouch, the sprint
		t.truthy(s.coverShare > 0.1 and s.coverShare < 0.7, `{s.coverShare * 100}% of the time at cover`)
		t.truthy(s.crouchShare > 0.003, "somebody crouched behind low cover")
		t.truthy(s.sprintShare > 0.05 and s.sprintShare < 0.6, `{s.sprintShare * 100}% sprinting`)
		-- at a post they look where there is something to see (what is left is a look at where a noise
		-- came from or somebody vanished, and the look swinging past a pillar on its way)
		t.truthy(s.noseShare < 0.25, `at a post their look ended on a wall {s.noseShare * 100}% of the time`)
		-- somebody in view too far off to fire at is somebody to move up on, not to stand and look at
		t.truthy(
			s.stareShare < 0.15,
			`they stood and looked at somebody out of range {s.stareShare * 100}% of the time`
		)
		t.truthy(s.stareLongest < 14, `{s.stareLongest} s at the longest`)
		-- they talk, and not all the time
		local says = sim.rec.says
		t.truthy((says.floor or 0) > 3 and (says.tagged or 0) > 1 and (says.out or 0) > 1)
		local total = 0
		for line, n in says do
			t.truthy((Contract.LINES :: any)[line] ~= nil, line)
			total += n
		end
		t.truthy(total < R.matchSecs / 2, `{total} call-outs in a match`)
	end)

	t.test("8 v 8 of bots, a whole match: sixteen play it to the end inside the cost and the sight budget", function()
		local sim, s = eight()
		sound(t, sim, s, 16)
		t.eq(s.botCount, 16)
		t.truthy(s.scores[1] >= 25 and s.scores[2] >= 25, `{s.scores[1]} - {s.scores[2]}`)
		-- PB-15: the bots' share is 0.5 ms a tick at 15 bots (the bound is loose here because other work
		-- shares this machine; BotCheck measures it in the engine)
		t.truthy(s.botMs < Contract.COST.botsMs, `{s.botMs} ms a tick`)
		-- sight checks: no bot more than BOT.sightHz a second, no tick more than its share
		t.truthy(s.sweepsSecond <= s.sweepsCap, `{s.sweepsSecond} sight checks in a second, cap {s.sweepsCap}`)
		t.truthy(s.sweepsTick <= math.ceil(16 * BOT.sightHz * DT), `{s.sweepsTick} in one tick`)
		t.truthy(s.sweepsSecond > s.sweepsCap * 0.5, "and they do look")
	end)

	t.test("with the stand-in fair player: a match the bots neither walk over nor are walked over in", function()
		local sim, s = match("fair", function()
			return Sim.new({ arena = arena, seed = 31, perSide = 4, people = 1, skill = 0.5, audit = true })
		end)
		t.truthy(s.finished)
		t.eq(s.botCount, 7)
		t.truthy(s.personTags + s.personOuts >= 12, `{s.personTags} : {s.personOuts}`)
		-- about three in five over many matches (calibrate.luau prints the figure); one match is a
		-- wide band round it
		t.truthy(s.personWin > 0.35 and s.personWin < 0.9, `the stand-in won {s.personWin * 100}% of its exchanges`)
		t.eq(s.refused, 0, "the stand-in's clicks pass the same judge")
		t.eq(s.legs, 0, "every step a brain took is one a person could have taken")
		t.truthy(s.stares <= 2, `{s.stares} times a bot followed somebody through a wall`)
		t.eq(s.doorTrap, 0)
		t.eq(s.outTrap, 0)
		t.truthy(s.still < 20)
		-- the bots tagged the person only after facing them (a ball meant for somebody else that the person
		-- walked into is nobody's aim)
		for _, tag in sim.rec.tags do
			if tag.byBot and not tag.idBot and not tag.stray then
				t.truthy(tag.faced, "a bot that tags a person has been seen to turn on them")
			end
		end
	end)

	t.test(
		"the server check (BotCheck) runs here as it will there: fifteen bots, no rule broken, inside the budget",
		function()
			local result = BotCheck.run({ seconds = 60, seed = 3 })
			t.deepEq(result.failures, {})
			t.truthy(result.ok)
			local n = result.numbers
			t.eq(n.bots, Contract.COST.atBots)
			t.eq(n.ticks, 60 * Clock.TICK_HZ)
			t.truthy(n.shots > 40 and n.tags > 5, `{n.shots} balls, {n.tags} tags`)
			t.eq(n.refused, 0)
			t.eq(n.legs, 0, "every step a brain took is one a person could have taken")
			t.eq(n.neverLeft, 0)
			t.truthy(n.botsMs < n.budgetMs)
		end
	)
end
