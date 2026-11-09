--!strict
-- Shared/Roles/Ladder, exhaustively (BUILD_PLAN §3.7, §4.4 #4; brief v2 §5, §6, §13a; Addendum B4; D34):
-- the 49 arithmetic, the 50th-arrival turn-away, the idle release, both score formulas and the admin
-- formula, the rank gate, recruitment by seniority, the rodent-death and squirrel-kill rows, every
-- other rule row, and invariant 20 (no other MaxPlayers/maxPlayers assignment in src/ or project files).
local fs = require("@lune/fs")
local Ladder = require("@shared/Roles/Ladder")
local PossessionState = require("@shared/Actors/PossessionState")

type P = Ladder.Player

local GATE = Ladder.params.rankGateDays

local function human(id: any, minutes: number, extra: { [string]: any }?): P
	local s = { activeMinutes = minutes, activeGameDays = GATE, cents = 0, reputation = 0 }
	for k, v in extra or {} do
		(s :: any)[k] = v
	end
	return { id = id, rung = "human", stats = s }
end

local function mk(id: any, rung: string, stats: { [string]: any }?, extra: { [string]: any }?): P
	local p: any = { id = id, rung = rung, stats = stats or { activeGameDays = GATE } }
	for k, v in extra or {} do
		p[k] = v
	end
	return p
end

local function ctxOf(list: { P }, extra: { [string]: any }?): Ladder.Ctx
	local players = {}
	for _, p in list do
		players[p.id] = p
	end
	local c: any = { players = players }
	for k, v in extra or {} do
		c[k] = v
	end
	return c
end

local function rules(ts: { Ladder.Transition }): { string }
	local out = {}
	for _, t in ts do
		table.insert(out, t.rule)
	end
	return out
end

local fired: { [string]: boolean } = {}
local function resolve(event: { [string]: any }, ctx: Ladder.Ctx): { Ladder.Transition }
	local ts = Ladder.resolve(event, ctx)
	for _, t in ts do
		fired[t.rule] = true
	end
	return ts
end

return function(t)
	t.test("the 49 arithmetic: 35 + 7 + 1 + 5 + 1 = maxPlayers; humans include tier 2", function()
		t.eq(Ladder.total(), 49)
		t.eq(Ladder.server.maxPlayers, 49)
		t.eq(Ladder.server.liveServerSize, 50)
		t.eq(Ladder.humanSlots.total, 35)
		t.eq(Ladder.rungs.squirrel.playerSlots + Ladder.rungs.rodent.playerSlots + Ladder.humanSlots.total, 43) -- §13a "35 of the 43"
		local c = ctxOf({ mk(1, "hospital"), mk(2, "hospital"), mk(3, "police") })
		t.eq(Ladder.slots("human", c), 32)
		t.eq(Ladder.slots("hospital", c), 5)
		t.eq(Ladder.slots("police", c), 5)
		t.eq(Ladder.slots("squirrel", c), 7)
		t.eq(Ladder.slots("rodent", c), 1)
		t.eq(Ladder.slots("deer", c), 5)
		t.eq(Ladder.slots("fox", c), 1)
		t.fails(function()
			Ladder.slots("dragon", c)
		end)
		t.eq(Ladder.FULL_MESSAGE, PossessionState.FULL_MESSAGE)
	end)

	t.test("police slots 5 -> 8 by performance (120, 260, 450)", function()
		t.eq(Ladder.policeSlots(0), 5)
		t.eq(Ladder.policeSlots(119), 5)
		t.eq(Ladder.policeSlots(120), 6)
		t.eq(Ladder.policeSlots(260), 7)
		t.eq(Ladder.policeSlots(450), 8)
		t.eq(Ladder.policeSlots(1e9), 8)
	end)

	t.test("admit: 49 admitted, the 50th (and later) turned away", function()
		for n = 0, 48 do
			t.truthy(Ladder.admits(n))
			local ts = resolve({ kind = "admit", player = n + 1 }, ctxOf({}, { admitted = n }))
			t.truthy(ts[1].admit)
		end
		local ts = resolve({ kind = "admit", player = 50 }, ctxOf({}, { admitted = 49 }))
		t.eq(ts[1].kick, Ladder.FULL_MESSAGE)
		t.falsy(ts[1].admit)
		t.falsy(Ladder.admits(50))
	end)

	t.test("join and leave rows", function()
		local ts = resolve({ kind = "join", player = 1 }, ctxOf({}))
		t.deepEq(ts, { { rule = "join", player = 1, to = "human", rank = "lowest" } })
		ts = resolve({ kind = "leave", player = 1 }, ctxOf({ human(1, 5) }))
		t.truthy(ts[1].release)
	end)

	t.test("squirrel score: 90 % nuts held now / cohort max, 10 % stink", function()
		t.near(Ladder.score("squirrel", { nuts = 50, cohortMaxNuts = 100, stinkPct = 40 }), 0.45 + 0.04)
		t.near(Ladder.score("squirrel", { nuts = 0, cohortMaxNuts = 0, stinkPct = 100 }), 0.1)
		t.near(Ladder.score("squirrel", { nuts = 9, cohortMaxNuts = 9, stinkPct = 0 }), 0.9)
	end)

	t.test("human queue score: time 0.25/min + S$ + reputation + entourage 3 + kicks 15 + quests", function()
		local s = {
			activeGameDays = GATE,
			activeMinutes = 40,
			cents = 1250,
			reputation = 7,
			entourage = 2,
			kicks = 1,
			questScore = 4,
		}
		t.near(Ladder.score("human", s), 10 + 12.5 + 7 + 6 + 15 + 4)
		-- money and reputation dominate the slow time term
		t.truthy(Ladder.score("human", { activeGameDays = GATE, cents = 10000 }) > Ladder.score("human", {
			activeGameDays = GATE,
			activeMinutes = 300,
		}))
	end)

	t.test("tier-2 score: performance, quests, time; money never counts", function()
		local a = { adminPerformance = 30, questScore = 5, activeMinutes = 10, cents = 1e6 }
		t.near(Ladder.score("police", a), 30 + 5 + 2)
		t.near(Ladder.score("hospital", a), 37)
	end)

	t.test("rank gate: unranked before 10 in-game days; skipped by offers; ranked at 10", function()
		t.eq(Ladder.score("human", { activeGameDays = GATE - 1, cents = 1e7 }), -math.huge)
		t.truthy(Ladder.score("human", { activeGameDays = GATE }) > -math.huge)
		local c = ctxOf({
			human(1, 0, { activeGameDays = GATE - 0.5, cents = 1e7 }),
			human(2, 1),
		})
		t.deepEq(Ladder.rankOrder("human", c.players), { 2, 1 })
		t.deepEq(Ladder.candidates("topRanked:human", c.players), { 2 })
	end)

	t.test("rank order ties break by seniority then id; queue drop moves a squirrel down", function()
		local c = ctxOf({ human("a", 10), human("b", 10), human("c", 30) })
		-- c: 7.5; a, b: 2.5 each
		t.deepEq(Ladder.rankOrder("human", c.players), { "c", "a", "b" })
		local sq = ctxOf({
			mk(1, "squirrel", { nuts = 90, cohortMaxNuts = 100 }),
			mk(2, "squirrel", { nuts = 80, cohortMaxNuts = 100 }),
			mk(3, "squirrel", { nuts = 70, cohortMaxNuts = 100 }),
			mk(4, "squirrel", { nuts = 60, cohortMaxNuts = 100 }),
		})
		sq.players[1].stats.queueDrop = 2
		t.deepEq(Ladder.rankOrder("squirrel", sq.players), { 2, 3, 1, 4 })
	end)

	t.test("free roam: players who opt out are never offered", function()
		local c = ctxOf({ human(1, 100, nil), human(2, 10) })
		c.players[1].noOffers = true
		t.deepEq(Ladder.candidates("topRanked:human", c.players), { 2 })
	end)

	t.test("recruitment by seniority: top-ranked human first, then by time served", function()
		-- rich newcomer ranks first by score; the rest go by activeMinutes, not score
		local c = ctxOf({
			human("rich", 5, { cents = 100000 }),
			human("veteran", 500),
			human("famous", 50, { reputation = 90 }),
			human("mid", 200),
		})
		t.deepEq(Ladder.rankOrder("human", c.players), { "rich", "veteran", "famous", "mid" })
		t.deepEq(Ladder.candidates("seniority:human", c.players), { "rich", "veteran", "mid" })
		local ts = resolve({ kind = "slot.open", rung = "police" }, c)
		t.eq(ts[1].rule, "slot.open.police")
		t.deepEq(ts[1].offer.candidates, { "rich", "veteran", "mid" })
		t.eq(ts[1].offer.cascade, "seniority")
		local tier = resolve({ kind = "police.performance", previous = 100, performance = 130 }, c)
		t.deepEq(rules(tier), { "police.performance", "police.performance.tier" })
		t.eq(tier[1].value, 6)
		t.deepEq(tier[2].offer.candidates, { "rich", "veteran", "mid" })
		t.eq(#resolve({ kind = "police.performance", previous = 130, performance = 200 }, c), 0)
	end)

	t.test("rodent dies: rodent and infected squirrels to lowest human; infection reset", function()
		local c = ctxOf({
			mk("r", "rodent"),
			mk("s1", "squirrel", nil, { infected = true }),
			mk("s2", "squirrel"),
			human("h", 5),
		})
		local ts = resolve({ kind = "rodent.died" }, c)
		t.deepEq(rules(ts), { "rodent.died", "rodent.died.infected", "rodent.died.infection" })
		t.eq(ts[1].player, "r")
		t.eq(ts[1].to, "human")
		t.eq(ts[1].rank, "lowest")
		t.eq(ts[2].player, "s1")
		t.eq(ts[3].infection, "resetToNewRodent")
		t.eq(ts[3].cure, "instantIfRecentOrEnRoute")
		t.deepEq(Ladder.vacated(ts, c), { "rodent", "squirrel" })
		-- an AI rodent: only the infection rows
		t.deepEq(rules(resolve({ kind = "rodent.died" }, ctxOf({ human("h", 1) }))), { "rodent.died.infection" })
	end)

	t.test("rodent killed by a human: squirrel if a body is free, else hospital over 30 %, else police", function()
		local base = { mk("r", "rodent"), human("k", 20) }
		local ts =
			resolve({ kind = "rodent.killed", by = "human", killer = "k" }, ctxOf(base, { squirrelBodiesFree = 2 }))
		t.eq(ts[1].rule, "rodent.killed")
		t.eq(ts[1].to, "squirrel")
		t.eq(ts[1].rank, "lowestUninfected")
		t.eq(ts[2].rule, "rodent.died")
		ts = resolve(
			{ kind = "rodent.killed", by = "police", killer = "k" },
			ctxOf(base, { squirrelBodiesFree = 0, rodentInfectedShare = 0.31 })
		)
		t.eq(ts[1].to, "hospital")
		ts = resolve(
			{ kind = "rodent.killed", by = "driver", killer = "k" },
			ctxOf(base, { squirrelBodiesFree = 0, rodentInfectedShare = 0.30 })
		)
		t.eq(ts[1].to, "police") -- exactly 30 % is not "more than"
		-- hospital full: falls through to police
		local full = { mk("r", "rodent"), human("k", 20) }
		for i = 1, 5 do
			table.insert(full, mk(`h{i}`, "hospital"))
		end
		ts = resolve(
			{ kind = "rodent.killed", by = "human", killer = "k" },
			ctxOf(full, { squirrelBodiesFree = 0, rodentInfectedShare = 0.5 })
		)
		t.eq(ts[1].to, "police")
		-- police full too: the brief's choice stands, flagged over cap
		for i = 1, 5 do
			table.insert(full, mk(`p{i}`, "police"))
		end
		ts = resolve(
			{ kind = "rodent.killed", by = "human", killer = "k" },
			ctxOf(full, { squirrelBodiesFree = 0, rodentInfectedShare = 0.5 })
		)
		t.eq(ts[1].to, "police")
		t.truthy(ts[1].extraSlot)
	end)

	t.test("rodent killed by hospital staff in the hospital: instant lowest uninfected squirrel, extra slot", function()
		local c = ctxOf({ mk("r", "rodent"), mk("n", "hospital") })
		local ts = resolve({ kind = "rodent.killed", by = "hospital", killer = "n", inHospital = true }, c)
		t.eq(ts[1].rule, "rodent.killed.inHospital")
		t.eq(ts[1].to, "squirrel")
		t.eq(ts[1].rank, "lowestUninfected")
		t.truthy(ts[1].instant and ts[1].extraSlot)
	end)

	t.test("a regular squirrel cannot kill the rodent", function()
		local c = ctxOf({ mk("r", "rodent"), mk("s", "squirrel") })
		t.eq(#resolve({ kind = "rodent.killed", by = "squirrel", killer = "s" }, c), 0)
	end)

	t.test("traffic death of the rodent (AI car): the death rows only", function()
		local c = ctxOf({ mk("r", "rodent") })
		t.deepEq(
			rules(resolve({ kind = "rodent.killed", by = "traffic" }, c)),
			{ "rodent.died", "rodent.died.infection" }
		)
	end)

	t.test("squirrel infected: half the nuts and two places down", function()
		local c = ctxOf({ mk("s", "squirrel", { nuts = 40 }) })
		local ts = resolve({ kind = "squirrel.infected", victim = "s" }, c)
		t.deepEq(ts[1].penalty, { nutsLostPct = 0.5, queueDrop = 2 })
		t.eq(#resolve({ kind = "squirrel.infected", victim = "nobody" }, c), 0)
	end)

	t.test(
		"squirrel killed: infected victim to lowest human; healthy body respawns; hospital outranks police",
		function()
			local c = ctxOf({
				mk("s", "squirrel", nil, { infected = true }),
				mk("cop", "police", { adminPerformance = 999 }),
				mk("nurse", "hospital", { adminPerformance = 1 }),
				human("h", 1000),
			})
			local ts = resolve({ kind = "squirrel.killed", by = "human", victim = "s", infected = true }, c)
			t.deepEq(rules(ts), { "squirrel.killed", "squirrel.killed.slot" })
			t.eq(ts[1].to, "human")
			t.eq(ts[1].rank, "lowest")
			t.eq(ts[2].bodyRespawn, "healthyFromNest")
			t.deepEq(ts[2].offer.candidates, { "nurse", "cop", "h" })
			for _, by in { "police", "hospital", "guard" } do
				t.eq(#resolve({ kind = "squirrel.killed", by = by, victim = "s", infected = true }, c), 2, by)
			end
			t.eq(#resolve({ kind = "squirrel.killed", by = "human", victim = "s", infected = false }, c), 0)
			t.eq(#resolve({ kind = "squirrel.killed", by = "squirrel", victim = "s", infected = true }, c), 0)
			-- an AI infected squirrel: just the respawn and the offer
			t.deepEq(
				rules(resolve({ kind = "squirrel.killed", by = "human", infected = true }, c)),
				{ "squirrel.killed.slot" }
			)
		end
	)

	t.test("winter end below threshold: squirrels back to their remembered human rank", function()
		local c = ctxOf({ mk(2, "squirrel"), mk(1, "squirrel"), human(3, 1) })
		local ts = resolve({ kind = "winter.end.belowThreshold", players = { 2, 1, 3 } }, c)
		t.deepEq(rules(ts), { "winter.end", "winter.end" })
		t.eq(ts[1].player, 1)
		t.eq(ts[1].rank, "rememberedHuman")
	end)

	t.test("slot.open rodent: top uninfected squirrels, immediate, AI re-enters after 20 s", function()
		local c = ctxOf({
			mk(1, "squirrel", { nuts = 90, cohortMaxNuts = 100 }, { infected = true }),
			mk(2, "squirrel", { nuts = 80, cohortMaxNuts = 100 }),
			mk(3, "squirrel", { nuts = 70, cohortMaxNuts = 100 }),
			mk(4, "squirrel", { nuts = 60, cohortMaxNuts = 100 }),
			mk(5, "squirrel", { nuts = 50, cohortMaxNuts = 100 }),
		})
		local o = resolve({ kind = "slot.open", rung = "rodent" }, c)[1].offer :: Ladder.Offer
		t.deepEq(o.candidates, { 2, 3, 4 }) -- cascade of 3
		t.truthy(o.immediate)
		t.eq(o.aiReentry, 20)
		t.eq(o.timeout, 15)
		t.deepEq(o.choices, { "accept", "deer", "fox", "stay" })
		local h = resolve({ kind = "slot.open", rung = "hospital" }, ctxOf({ human(1, 5), human(2, 50) }))
		t.deepEq(h[1].offer.candidates, { 2, 1 })
		local sq =
			resolve({ kind = "slot.open", rung = "squirrel", exclude = { 2 } }, ctxOf({ human(1, 5), human(2, 50) }))
		t.deepEq(sq[1].offer.candidates, { 1 })
		t.eq(#resolve({ kind = "slot.open", rung = "deer" }, c), 0)
	end)

	t.test("idle release (D34) per rung", function()
		local c = ctxOf({
			mk("r", "rodent"),
			mk("s", "squirrel"),
			mk("d", "deer"),
			mk("f", "fox"),
			mk("n", "hospital"),
			mk("p", "police", nil, { subrole = "driver" }),
			human("hd", 10, nil),
			human("plain", 10),
		})
		c.players.hd.subrole = "humanDriver"
		local function afk(id)
			return resolve({ kind = "afk", player = id }, c)
		end
		t.eq(afk("r")[1].rank, "lowest")
		t.eq(afk("s")[1].rank, "rememberedHuman")
		t.eq(afk("d")[1].rank, "remembered")
		t.eq(afk("f")[1].rank, "remembered")
		t.eq(afk("n")[1].rank, "keep")
		local p = afk("p")[1]
		t.eq(p.to, "human")
		t.eq(p.loseSubrole, "driver")
		local hd = afk("hd")[1]
		t.eq(hd.to, "human")
		t.eq(hd.loseSubrole, "humanDriver")
		t.truthy(hd.release)
		t.eq(#afk("plain"), 0) -- an idle townsperson is left alone
		t.eq(#afk("ghost"), 0)
		t.eq(Ladder.params.afkSecs, 780)
		t.eq(Ladder.params.afkWarnSecs, 30)
	end)

	t.test("side exits: deer and fox remember the human rank; full is refused; leaving restores it", function()
		local list = { human("h", 10) }
		local ts = resolve({ kind = "offer.sideExit", player = "h", to = "deer" }, ctxOf(list))
		t.eq(ts[1].to, "deer")
		t.truthy(ts[1].remember)
		table.insert(list, mk("f", "fox"))
		ts = resolve({ kind = "offer.sideExit", player = "h", to = "fox" }, ctxOf(list))
		t.eq(ts[1].refused, "full")
		t.eq(#resolve({ kind = "offer.sideExit", player = "h", to = "dragon" }, ctxOf(list)), 0)
		ts = resolve({ kind = "sideExit.leave", player = "f" }, ctxOf(list))
		t.eq(ts[1].to, "human")
		t.eq(ts[1].rank, "remembered")
		t.eq(#resolve({ kind = "sideExit.leave", player = "h" }, ctxOf(list)), 0)
	end)

	t.test("kicks, work and gigs", function()
		local c = ctxOf({ human("h", 1) })
		local k = resolve({ kind = "kick.landed", player = "h", target = "rodent" }, c)[1]
		t.eq(k.rankDelta, 25)
		t.eq(k.reputation, "kick_landed")
		t.eq(#resolve({ kind = "kick.landed", player = "h", target = "infectedSquirrel" }, c), 1)
		t.eq(#resolve({ kind = "kick.landed", player = "h", target = "squirrel" }, c), 0)
		t.eq(resolve({ kind = "work.completed", player = "h", class = "major", pay = 6 }, c)[1].rankDelta, 10)
		t.eq(resolve({ kind = "work.completed", player = "h", class = "minor", fetchSecs = 12 }, c)[1].rankDelta, 14)
		t.eq(resolve({ kind = "work.completed", player = "h", class = "minor", fetchSecs = 40 }, c)[1].rankDelta, 7)
		t.eq(resolve({ kind = "work.completed", player = "h", class = "minor", fetchSecs = 60 }, c)[1].rankDelta, 4)
		local g = resolve({ kind = "gig.completed", player = "h", gig = "mow", quality = 0.95 }, c)[1]
		t.truthy((g.tip :: number) > 0)
		t.eq(g.reputation, "gig_tip")
	end)

	t.test("drone needs 8 police slots", function()
		t.eq(
			resolve({ kind = "upgrade.bought", id = "drone" }, ctxOf({}, { policePerformance = 449 }))[1].refused,
			"requires policeSlots=8"
		)
		t.eq(
			resolve({ kind = "upgrade.bought", id = "drone" }, ctxOf({}, { policePerformance = 450 }))[1].unlock,
			"drone"
		)
		t.eq(#resolve({ kind = "upgrade.bought", id = "radar" }, ctxOf({})), 0)
	end)

	t.test("traffic: an officer who hits a pedestrian loses the car, is jailed, then lowest human", function()
		local c = ctxOf({ mk("p", "police", nil, { subrole = "driver" }), human("h", 1) })
		local ts = resolve({ kind = "traffic.hitPedestrian", player = "p" }, c)
		t.eq(ts[1].keys, "revoke")
		t.eq(ts[1].jail, 90)
		t.eq(ts[1].to, "human")
		t.eq(ts[1].rank, "lowest")
		t.eq(#resolve({ kind = "traffic.hitPedestrian", player = "h" }, c), 0)
		t.eq(resolve({ kind = "traffic.repeatOffence", player = "h" }, c)[1].jail, 45)
		t.eq(#resolve({ kind = "traffic.repeatOffence", player = "h" }, ctxOf({}, { offroad = true })), 0)
	end)

	t.test("outbreak: critical mass names the winner; the reset keeps the winner and infected squirrels", function()
		local c = ctxOf({
			mk("r", "rodent"),
			mk("si", "squirrel", nil, { infected = true }),
			mk("sh", "squirrel"),
			mk("cop", "police"),
			human("h", 1),
		})
		local cm = resolve({ kind = "infection.criticalMass" }, c)[1]
		t.eq(cm.player, "r")
		t.truthy(cm.winner and cm.cinematic)
		local ts = resolve({ kind = "cinematic.finished", winner = "r" }, c)
		local by = {}
		for _, tr in ts do
			by[tr.player] = tr
		end
		t.eq(by.r.to, "rodent")
		t.eq(by.si.to, "squirrel")
		t.eq(by.sh.to, "human")
		t.eq(by.cop.to, "human")
		t.eq(by.h.rank, "lowest")
		t.eq(#resolve({ kind = "everyoneInfected" }, c), 5)
	end)

	t.test("applyRank policies", function()
		local s =
			{ activeMinutes = 50, kicks = 2, questScore = 9, cents = 300, reputation = 4, nuts = 7, queueDrop = 2 }
		local low = Ladder.applyRank("lowest", s :: any)
		t.eq(low.activeMinutes, 0)
		t.eq(low.kicks, 0)
		t.eq(low.cents, 300) -- money stays the player's
		t.eq(low.reputation, 4)
		t.eq(s.activeMinutes, 50) -- pure
		t.eq(Ladder.applyRank("lowestUninfected", s :: any).nuts, 0)
		t.eq(Ladder.applyRank("remembered", s :: any, { activeMinutes = 99 } :: any).activeMinutes, 99)
		t.deepEq(Ladder.applyRank("keep", s :: any), s)
		t.fails(function()
			Ladder.applyRank("sideways", s :: any)
		end)
	end)

	t.test("key holders: top two by rank (patrol cars; pickups and SUVs)", function()
		local c = ctxOf({
			mk(1, "police", { adminPerformance = 1 }),
			mk(2, "police", { adminPerformance = 9 }),
			mk(3, "police", { adminPerformance = 5 }),
			human(4, 100),
			human(5, 10),
			human(6, 50),
			human(7, 999, { activeGameDays = 0 }),
		})
		t.deepEq(Ladder.keyHolders("driver", c.players), { 2, 3 })
		t.deepEq(Ladder.keyHolders("humanDriver", c.players), { 4, 6 })
	end)

	t.test("unknown events error", function()
		t.fails(function()
			Ladder.resolve({ kind = "dance" }, ctxOf({}))
		end)
	end)

	t.test("coverage: every rule row fired in this spec", function()
		local missing = {}
		for _, row in Ladder.rules do
			if not fired[row.id] then
				table.insert(missing, row.id)
			end
		end
		t.eq(#missing, 0, table.concat(missing, ", "))
	end)

	t.test("invariant 20: the only MaxPlayers/maxPlayers assignments are Ladder.server and the project file", function()
		local hits = {}
		local function scan(dir: string)
			for _, entry in fs.readDir(dir) do
				local path = `{dir}/{entry}`
				if fs.isDir(path) then
					scan(path)
				elseif string.sub(entry, -5) == ".luau" then
					local text = fs.readFile(path)
					for line in string.gmatch(text, "[^\n]+") do
						if string.find(line, "[Mm]ax[Pp]layers%s*=[^=]") and not string.find(line, "^%s*%-%-") then
							table.insert(hits, `{path}: {line}`)
						end
					end
				end
			end
		end
		scan("src")
		for _, h in hits do
			t.truthy(string.find(h, "src/shared/Roles/Ladder.luau", 1, true) ~= nil, h)
		end
		for _, proj in { "default.project.json", "build.project.json", "ci.project.json" } do
			if fs.isFile(proj) then
				for v in string.gmatch(fs.readFile(proj), '"MaxPlayers"%s*:%s*(%d+)') do
					t.eq(tonumber(v), Ladder.server.maxPlayers, proj)
				end
			end
		end
	end)
end
