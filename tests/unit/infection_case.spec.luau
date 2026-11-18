--!strict
-- Infection/InfectionRules: one bitten person's story on a scripted clock and scripted dice (owner
-- 2026-11-10). Every path is driven to its end: collapse at once, symptoms later then a walk-in or a
-- collapse, the walk-in that is too slow, no route, no ambulance, a full hospital, a bite on the
-- hospital's grounds, and a person a player holds (told what to do, told again every 40 s, a status
-- for the line that stays on screen; a player who ends up holding a patient gets the person back on
-- their feet and the ambulance is sent away). The rules that must never break are checked on 2,000
-- seeded runs: everyone ends cured, nobody is cured anywhere but the hospital, and nothing shows
-- before the symptoms do.
local InfectionRules = require("@shared/Infection/InfectionRules")
local Rng = require("@shared/Util/Rng")

type Case = InfectionRules.Case
type Inputs = InfectionRules.Inputs

local P: InfectionRules.Params = {
	immediateChance = 0.45,
	collapseAfterSecs = { 1.5, 4 },
	incubateSecs = { 40, 120 },
	symptomSecs = { 8, 20 },
	walkInChance = 0.5,
	walkInSpeed = 11,
	walkInMaxDist = 2750,
	dispatchDelaySecs = { 4, 10 },
	assessSecs = { 2.1, 5 },
	loadSecs = 3,
	ambulanceTimeoutSecs = 150,
	transitMaxSecs = 200,
	groanSecs = { 12, 21 },
	treatSecs = 30,
	crewMaxSecs = 55,
	remindSecs = 40,
}

-- dice that return the scripted values in order, then 0.5 for ever
local function dice(values: { number }): () -> number
	local i = 0
	return function(): number
		i += 1
		return values[i] or 0.5
	end
end

local function kinds(effects: { InfectionRules.Effect }): string
	local out = {}
	for _, e in effects do
		table.insert(
			out,
			if e.kind == "say" then `say:{e.situation}` elseif e.kind == "toast" then `toast:{e.key}` else e.kind
		)
	end
	return table.concat(out, ",")
end

local function has(effects: { InfectionRules.Effect }, kind: string): boolean
	for _, e in effects do
		if e.kind == kind then
			return true
		end
	end
	return false
end

local AI: Inputs = { controller = "ai" }

return function(t)
	t.test("defaults come from Tunables; the old instant-cure window is off", function()
		local d = InfectionRules.defaults()
		t.eq(d.immediateChance, 0.45)
		t.deepEq(d.incubateSecs, { 40, 120 })
		t.eq(d.walkInSpeed, 9, "3.6 u/s in studs")
		t.eq(d.treatSecs, 30)
		t.eq(d.remindSecs, 40)
		t.eq(#InfectionRules.STATES, 15)
		t.eq(InfectionRules.townPercent(17, 68), 25)
		t.eq(InfectionRules.townPercent(0, 0), 0)
	end)

	t.test(
		"immediate: bitten -> down -> scene -> ambulance -> crew -> carried -> transit -> bed -> released",
		function()
			local rand = dice({ 0.1, 0 }) -- the collapse path, after the shortest run
			local case, fx = InfectionRules.newCase(7, 100, AI, rand, P)
			t.eq(kinds(fx), "flee,say:bitten")
			t.eq(case.state, "bitten")
			t.truthy(case.infected and case.immediate)
			t.eq(InfectionRules.tell(case), nil, "nothing shows while they run")
			t.truthy(InfectionRules.possessable(case))
			t.eq(kinds(InfectionRules.advance(case, 101.4, AI, rand, P)), "")
			rand = dice({ 0, 0 }) -- dispatch delay 4 s, first groan after 12 s
			t.eq(kinds(InfectionRules.advance(case, 101.5, AI, rand, P)), "collapse")
			t.eq(case.state, "down")
			t.eq(InfectionRules.tell(case), "down")
			t.truthy(not InfectionRules.possessable(case) and not InfectionRules.biteable(case))
			t.truthy(InfectionRules.atScene(case))
			t.eq(kinds(InfectionRules.advance(case, 105.4, AI, rand, P)), "")
			t.eq(kinds(InfectionRules.advance(case, 105.5, AI, rand, P)), "call")
			t.eq(case.state, "scene")
			t.eq(case.deadline, 255.5)
			t.eq(kinds(InfectionRules.advance(case, 106, { controller = "ai", ambulance = "queued" }, rand, P)), "")
			t.eq(kinds(InfectionRules.advance(case, 107, { controller = "ai", ambulance = "assigned" }, rand, P)), "")
			t.eq(case.state, "enroute")
			-- the patient groans while waiting (first at 113.5)
			t.eq(
				kinds(InfectionRules.advance(case, 114, { controller = "ai", ambulance = "assigned" }, rand, P)),
				"say:patient"
			)
			local arrived: Inputs = { controller = "ai", ambulance = "arrived", crewSecs = 10 }
			t.eq(kinds(InfectionRules.advance(case, 150, arrived, rand, P)), "crewOut,say:patient")
			t.eq(case.state, "approach")
			rand = dice({ 0 }) -- assess 2.1 s
			t.eq(kinds(InfectionRules.advance(case, 160, arrived, rand, P)), "say:crew")
			t.eq(case.state, "assess")
			rand = dice({ 0.99, 0.99, 0.99 }) -- groans far apart from here on
			InfectionRules.advance(case, 162.1, arrived, rand, P)
			t.eq(case.state, "loading")
			t.eq(kinds(InfectionRules.advance(case, 165.1, arrived, rand, P)), "carry")
			t.eq(case.state, "retrieve")
			t.eq(InfectionRules.tell(case), "carried", "walked to the ambulance, still in view")
			t.eq(kinds(InfectionRules.advance(case, 175.1, arrived, rand, P)), "load")
			t.eq(case.state, "transit")
			t.eq(InfectionRules.tell(case), "transit")
			t.truthy(not InfectionRules.atScene(case))
			local back: Inputs = { controller = "ai", ambulance = "returning" }
			t.eq(kinds(InfectionRules.advance(case, 200, back, rand, P)), "")
			local home: Inputs = { controller = "ai", ambulance = "home", hospital = "none" }
			local arrive = InfectionRules.advance(case, 230, home, rand, P)
			t.eq(kinds(arrive), "arrive")
			t.eq(arrive[1].by, "ambulance")
			t.eq(case.state, "admitted")
			t.eq(InfectionRules.tell(case), "transit", "still out of sight until a bed is free")
			t.eq(kinds(InfectionRules.advance(case, 231, { controller = "ai", hospital = "queued" }, rand, P)), "")
			t.eq(kinds(InfectionRules.advance(case, 240, { controller = "ai", hospital = "bed" }, rand, P)), "bed")
			t.eq(case.state, "treated")
			t.eq(InfectionRules.tell(case), "treated")
			t.truthy(case.infected, "still infected in the bed")
			t.eq(kinds(InfectionRules.advance(case, 260, { controller = "ai", hospital = "bed" }, rand, P)), "")
			local out = InfectionRules.advance(case, 270, { controller = "ai", hospital = "done" }, rand, P)
			t.eq(kinds(out), "cure,discharge,say:cured")
			t.eq(case.state, "released")
			t.truthy(not case.infected and InfectionRules.closed(case))
			t.eq(InfectionRules.tell(case), nil)
			t.eq(kinds(InfectionRules.advance(case, 999, AI, rand, P)), "", "released is the end")
		end
	)

	t.test("no crew: the ambulance arrives, the patient is assessed and loaded where they sit", function()
		local rand = dice({ 0.1, 0, 0, 0 })
		local case = InfectionRules.newCase(1, 0, AI, rand, P)
		InfectionRules.advance(case, 1.5, AI, rand, P)
		InfectionRules.advance(case, 5.5, AI, rand, P)
		local arrived: Inputs = { controller = "ai", ambulance = "arrived", crewSecs = 0 }
		rand = dice({ 0, 0.99, 0.99 })
		t.eq(kinds(InfectionRules.advance(case, 40, arrived, rand, P)), "say:patient")
		t.eq(case.state, "assess")
		InfectionRules.advance(case, 42.1, arrived, rand, P)
		t.eq(case.state, "loading")
		t.eq(kinds(InfectionRules.advance(case, 45.1, arrived, rand, P)), "load")
		t.eq(case.state, "transit")
		-- a crew time beyond the cap is clamped (v5.4 walkTime <= 55)
		local far = InfectionRules.newCase(2, 0, AI, dice({ 0.1, 0, 0, 0.99 }), P)
		InfectionRules.advance(far, 1.5, AI, dice({ 0, 0.99 }), P)
		InfectionRules.advance(far, 5.5, AI, dice({}), P)
		InfectionRules.advance(far, 6, { controller = "ai", ambulance = "arrived", crewSecs = 400 }, dice({}), P)
		t.eq(far.crewSecs, 55)
	end)

	t.test("delayed: looks fine for 40 s or more, then the tell, then walks in and is treated", function()
		local rand = dice({ 0.9, 0 }) -- not immediate; the shortest incubation
		local case, fx = InfectionRules.newCase(3, 0, AI, rand, P)
		t.eq(kinds(fx), "flee,say:bitten")
		t.eq(case.state, "incubating")
		for now = 1, 39 do
			t.eq(kinds(InfectionRules.advance(case, now, AI, rand, P)), "")
			t.eq(InfectionRules.tell(case), nil, "nothing a client can read while incubating")
			t.truthy(case.infected and InfectionRules.possessable(case) and InfectionRules.biteable(case))
		end
		rand = dice({ 0 }) -- symptoms for 8 s
		t.eq(kinds(InfectionRules.advance(case, 40, AI, rand, P)), "say:symptoms")
		t.eq(case.state, "symptomatic")
		t.eq(case.symptomsAt, 40)
		t.eq(InfectionRules.tell(case), "symptomatic")
		local route: Inputs = { controller = "ai", routeLen = 550 }
		t.eq(kinds(InfectionRules.advance(case, 47.9, route, rand, P)), "")
		rand = dice({ 0.1 }) -- the dice say walk
		t.eq(kinds(InfectionRules.advance(case, 48, route, rand, P)), "walkIn,say:symptoms")
		t.eq(case.state, "walkin")
		t.near(case.untilT, 48 + 550 / 11 * 1.35 + 20, 1e-9, "time to walk it, with slack")
		t.eq(InfectionRules.tell(case), "symptomatic")
		t.eq(kinds(InfectionRules.advance(case, 80, route, rand, P)), "")
		local door: Inputs =
			{ controller = "ai", routeLen = 5, atEntrance = true, nearHospital = true, hospital = "none" }
		local arrive = InfectionRules.advance(case, 100, door, rand, P)
		t.eq(kinds(arrive), "arrive")
		t.eq(arrive[1].by, "walk")
		t.eq(InfectionRules.tell(case), "symptomatic", "a walk-in waits in reception, in view")
		door.hospital = "bed"
		t.eq(kinds(InfectionRules.advance(case, 101, door, rand, P)), "bed")
		door.hospital = "done"
		t.eq(kinds(InfectionRules.advance(case, 131, door, rand, P)), "cure,discharge,say:cured")
		t.truthy(not case.infected)
	end)

	t.test("delayed: the dice, no route or too long a walk end in a collapse and an ambulance", function()
		local function toSymptoms(): Case
			local case = InfectionRules.newCase(4, 0, AI, dice({ 0.9, 0 }), P)
			InfectionRules.advance(case, 40, AI, dice({ 0 }), P)
			t.eq(case.state, "symptomatic")
			return case
		end
		local a = toSymptoms()
		t.eq(
			kinds(InfectionRules.advance(a, 48, { controller = "ai", routeLen = 550 }, dice({ 0.9, 0, 0 }), P)),
			"collapse"
		)
		t.eq(a.state, "down")
		local b = toSymptoms()
		local noRoute = dice({ 0, 0 }) -- would have said "walk" had it been asked
		t.eq(kinds(InfectionRules.advance(b, 48, AI, noRoute, P)), "collapse", "no route: no dice")
		local c = toSymptoms()
		t.eq(
			kinds(InfectionRules.advance(c, 48, { controller = "ai", routeLen = 2751 }, dice({ 0, 0 }), P)),
			"collapse"
		)
		-- the same far walk is taken from the hospital's own grounds (staff bitten at work)
		local d = toSymptoms()
		local near: Inputs = { controller = "ai", routeLen = 2751, nearHospital = true }
		t.eq(kinds(InfectionRules.advance(d, 48, near, dice({ 0.99 }), P)), "walkIn,say:symptoms")
	end)

	t.test("a walk-in that does not reach the door in time collapses where it stands", function()
		local case = InfectionRules.newCase(5, 0, AI, dice({ 0.9, 0 }), P)
		InfectionRules.advance(case, 40, AI, dice({ 0 }), P)
		local route: Inputs = { controller = "ai", routeLen = 1100 }
		InfectionRules.advance(case, 48, route, dice({ 0.1 }), P)
		t.eq(case.state, "walkin")
		local giveUp = 48 + 1100 / 11 * 1.35 + 20
		t.eq(kinds(InfectionRules.advance(case, giveUp - 0.1, route, dice({}), P)), "")
		t.eq(kinds(InfectionRules.advance(case, giveUp, route, dice({}), P)), "collapse")
		t.eq(case.state, "down")
		t.truthy(case.infected)
	end)

	t.test("no ambulance in time: the patient is taken in anyway, and still has to be treated", function()
		local case = InfectionRules.newCase(6, 0, AI, dice({ 0.1, 0 }), P)
		InfectionRules.advance(case, 1.5, AI, dice({ 0, 0.99 }), P)
		t.eq(kinds(InfectionRules.advance(case, 5.5, AI, dice({}), P)), "call")
		local waiting: Inputs = { controller = "ai", ambulance = "queued" }
		for now = 6, 155, 1 do
			local fx = InfectionRules.advance(case, now, waiting, dice({ 0.99 }), P)
			t.truthy(not has(fx, "abandon") and not has(fx, "cure"), `at {now}: {kinds(fx)}`)
			t.eq(case.state, "scene")
		end
		t.eq(kinds(InfectionRules.advance(case, 155.5, waiting, dice({}), P)), "abandon")
		t.eq(case.state, "transit")
		t.truthy(case.infected)
		-- the glue drops the ambulance request on "abandon"; with none the patient is admitted
		local fx =
			InfectionRules.advance(case, 156, { controller = "ai", ambulance = "none", hospital = "none" }, dice({}), P)
		t.eq(kinds(fx), "arrive")
		t.eq(case.state, "admitted")
		-- the same holds when an ambulance was assigned but is stuck on the way. Its clock starts when
		-- it is assigned: a patient who waited two minutes for a free ambulance is not given up on
		-- thirty seconds after one finally sets off
		local stuck = InfectionRules.newCase(8, 0, AI, dice({ 0.1, 0 }), P)
		InfectionRules.advance(stuck, 1.5, AI, dice({ 0, 0.99 }), P)
		InfectionRules.advance(stuck, 5.5, AI, dice({}), P)
		local coming: Inputs = { controller = "ai", ambulance = "assigned" }
		InfectionRules.advance(stuck, 125, { controller = "ai", ambulance = "queued" }, dice({ 0.99 }), P)
		t.eq(stuck.state, "scene")
		InfectionRules.advance(stuck, 126, coming, dice({ 0.99 }), P)
		t.eq(stuck.state, "enroute")
		for now = 127, 275 do
			local tick = InfectionRules.advance(stuck, now, coming, dice({ 0.99 }), P)
			t.truthy(not has(tick, "abandon"), `given up on at {now} with the ambulance on its way`)
		end
		t.eq(stuck.state, "enroute")
		t.eq(kinds(InfectionRules.advance(stuck, 276, coming, dice({ 0.99 }), P)), "abandon")
		-- and a return trip that never ends cannot hold a patient for ever
		local held: Inputs = { controller = "ai", ambulance = "returning", hospital = "none" }
		t.eq(kinds(InfectionRules.advance(stuck, 475.9, held, dice({}), P)), "")
		t.eq(kinds(InfectionRules.advance(stuck, 476, held, dice({}), P)), "arrive")
	end)

	t.test("a full hospital: the patient waits, infected, until a bed is free", function()
		local case = InfectionRules.newCase(9, 0, AI, dice({ 0.9, 0 }), P)
		InfectionRules.advance(case, 40, AI, dice({ 0 }), P)
		InfectionRules.advance(case, 48, { controller = "ai", routeLen = 100 }, dice({ 0.1 }), P)
		local door: Inputs = { controller = "ai", atEntrance = true, hospital = "queued" }
		InfectionRules.advance(case, 60, door, dice({}), P)
		t.eq(case.state, "admitted")
		for now = 61, 600, 7 do
			t.eq(kinds(InfectionRules.advance(case, now, door, dice({}), P)), "")
			t.truthy(case.infected and case.state == "admitted")
		end
		door.hospital = "bed"
		t.eq(kinds(InfectionRules.advance(case, 601, door, dice({}), P)), "bed")
	end)

	t.test("bitten on the hospital's grounds: never a collapse at once, always a walk in", function()
		local near: Inputs = { controller = "ai", nearHospital = true, routeLen = 60 }
		local rand = dice({ 0 }) -- would be "immediate" (0 < 0.45) if the path were diced
		local case = InfectionRules.newCase(10, 0, near, rand, P)
		t.eq(case.state, "incubating")
		t.truthy(not case.immediate)
		t.eq(case.untilT, 40, "the one draw went to the incubation time")
		InfectionRules.advance(case, 40, near, dice({ 0 }), P)
		t.eq(kinds(InfectionRules.advance(case, 48, near, dice({ 0.99 }), P)), "walkIn,say:symptoms")
	end)

	t.test("a person a player holds: told what happened, never collapses, cured by standing in the hospital", function()
		local me: Inputs = { controller = "player" }
		local rand = dice({ 0 })
		local case, fx = InfectionRules.newCase(11, 0, me, rand, P)
		t.eq(kinds(fx), "flee,say:bitten,toast:bitten")
		t.eq(case.state, "incubating")
		t.truthy(not case.immediate)
		t.eq(InfectionRules.status(case), "infected", "the status line says so from the bite on")
		t.eq(kinds(InfectionRules.advance(case, 39, me, dice({}), P)), "")
		t.eq(kinds(InfectionRules.advance(case, 40, me, dice({}), P)), "say:symptoms,toast:symptoms")
		t.eq(InfectionRules.status(case), "symptoms")
		-- symptoms for as long as the player stays away: 20 minutes and no collapse, no hiding; the
		-- only thing that happens is the reminder, every 40 s (one toast is easily missed)
		local reminders, lastAt = 0, 40
		for now = 41, 1240 do
			local e = InfectionRules.advance(case, now, me, dice({ 0 }), P)
			if kinds(e) == "toast:symptoms" then
				reminders += 1
				t.eq(now - lastAt, 40, `reminded at {now}`)
				lastAt = now
			else
				t.eq(kinds(e), "", `at {now}`)
			end
			t.eq(case.state, "symptomatic")
			t.truthy(case.infected and InfectionRules.possessable(case))
		end
		t.eq(reminders, 30, "told again every 40 s for 20 minutes")
		local inside: Inputs = { controller = "player", atEntrance = true, nearHospital = true }
		t.eq(kinds(InfectionRules.advance(case, 1300, inside, dice({}), P)), "toast:treating")
		t.eq(case.state, "treated")
		t.eq(InfectionRules.status(case), "treating")
		t.eq(InfectionRules.tell(case), "symptomatic", "a held body is never posed or hidden")
		t.truthy(InfectionRules.possessable(case) and not InfectionRules.biteable(case))
		-- no reminder while the treatment runs
		t.eq(kinds(InfectionRules.advance(case, 1309, inside, dice({}), P)), "")
		-- walking out early starts it over
		t.eq(kinds(InfectionRules.advance(case, 1310, me, dice({}), P)), "toast:leftEarly")
		t.eq(case.state, "symptomatic")
		t.truthy(case.infected)
		t.eq(kinds(InfectionRules.advance(case, 1320, inside, dice({}), P)), "toast:treating")
		t.eq(kinds(InfectionRules.advance(case, 1349.9, inside, dice({}), P)), "")
		t.truthy(case.infected)
		t.eq(kinds(InfectionRules.advance(case, 1350, inside, dice({}), P)), "cure,toast:cured")
		t.truthy(not case.infected and case.state == "released")
		t.eq(InfectionRules.status(case), nil, "nothing more to say")
		-- before the symptoms the reminder says "infected" (and where to go), every 40 s as well
		local quiet = InfectionRules.newCase(14, 0, me, dice({ 0.99 }), P) -- incubates for 119.2 s
		t.eq(kinds(InfectionRules.advance(quiet, 39.9, me, dice({}), P)), "")
		t.eq(kinds(InfectionRules.advance(quiet, 40, me, dice({}), P)), "toast:infected")
		t.eq(kinds(InfectionRules.advance(quiet, 79, me, dice({}), P)), "")
		t.eq(kinds(InfectionRules.advance(quiet, 80, me, dice({}), P)), "toast:infected")
		t.eq(InfectionRules.tell(quiet), nil, "and still nothing a client can read")
		-- an AI case never reminds anybody
		local ai = InfectionRules.newCase(15, 0, AI, dice({ 0.99, 0.99 }), P)
		for now = 1, 119 do
			t.eq(kinds(InfectionRules.advance(ai, now, AI, dice({}), P)), "")
		end
		t.eq(InfectionRules.status(ai), "infected", "(the server only shows a status to a player)")
		-- going to the hospital before the symptoms show works too
		local early = InfectionRules.newCase(12, 0, me, dice({ 0.5 }), P)
		t.eq(kinds(InfectionRules.advance(early, 5, inside, dice({}), P)), "toast:treating")
		t.eq(kinds(InfectionRules.advance(early, 35, inside, dice({}), P)), "cure,toast:cured")
	end)

	t.test("hand-overs: a player takes or lets go of an infected body at any point", function()
		-- taken in the seconds before the collapse: incubates instead (a held person never collapses)
		local a = InfectionRules.newCase(13, 0, AI, dice({ 0.1, 0.99 }), P)
		t.eq(a.state, "bitten")
		local me: Inputs = { controller = "player" }
		t.eq(kinds(InfectionRules.advance(a, 2, me, dice({ 0 }), P)), "toast:bitten")
		t.eq(a.state, "incubating")
		t.eq(a.untilT, 40, "counted from the bite")
		-- let go mid-incubation: the AI carries on to the symptoms and beyond
		t.eq(kinds(InfectionRules.advance(a, 20, AI, dice({}), P)), "")
		-- taken again while nothing shows: the player is told the body is infected (it is theirs now)
		t.eq(kinds(InfectionRules.advance(a, 25, me, dice({}), P)), "toast:infected")
		t.eq(InfectionRules.tell(a), nil)
		t.eq(kinds(InfectionRules.advance(a, 30, AI, dice({}), P)), "")
		t.eq(kinds(InfectionRules.advance(a, 40, AI, dice({ 0 }), P)), "say:symptoms")
		t.eq(a.untilT, 48)
		-- taken while symptomatic: told what to do; no timer runs while held
		t.eq(kinds(InfectionRules.advance(a, 45, me, dice({}), P)), "toast:symptoms")
		t.eq(kinds(InfectionRules.advance(a, 84, me, dice({}), P)), "")
		t.eq(kinds(InfectionRules.advance(a, 85, me, dice({}), P)), "toast:symptoms", "the reminder")
		t.eq(kinds(InfectionRules.advance(a, 500, me, dice({}), P)), "toast:symptoms")
		t.eq(kinds(InfectionRules.advance(a, 500.2, me, dice({}), P)), "")
		t.eq(a.state, "symptomatic")
		-- let go while symptomatic: a fresh symptom timer, then the usual end
		t.eq(kinds(InfectionRules.advance(a, 501, AI, dice({ 0 }), P)), "")
		t.eq(a.untilT, 509)
		t.eq(
			kinds(InfectionRules.advance(a, 509, { controller = "ai", routeLen = 300 }, dice({ 0.1 }), P)),
			"walkIn,say:symptoms"
		)
		-- taken mid walk-in: the route is dropped, the player walks the rest
		t.eq(kinds(InfectionRules.advance(a, 520, me, dice({}), P)), "resume,toast:symptoms")
		t.eq(a.state, "symptomatic")
		-- let go inside the hospital mid-treatment: the AI finishes the walk in and gets a bed
		local inside: Inputs = { controller = "player", atEntrance = true, nearHospital = true }
		InfectionRules.advance(a, 600, inside, dice({}), P)
		t.eq(a.state, "treated")
		local left: Inputs =
			{ controller = "ai", atEntrance = true, nearHospital = true, routeLen = 4, hospital = "none" }
		local fx = InfectionRules.advance(a, 610, left, dice({}), P)
		t.eq(kinds(fx), "walkIn,say:symptoms,arrive")
		t.eq(a.state, "admitted")
		t.truthy(a.infected and not a.selfTreat)
	end)

	t.test(
		"a player holding a patient: back on their feet, the ambulance sent away, the hospital still the cure",
		function()
			local me: Inputs = { controller = "player" }
			-- every state in which somebody else is doing something for the patient
			local function patientIn(state: string): Case
				local case = InfectionRules.newCase(21, 0, AI, dice({ 0.1, 0 }), P) -- the collapse path
				local facts: Inputs = { controller = "ai", ambulance = "none", hospital = "none" }
				local now = 0
				for _ = 1, 4000 do
					if case.state == state then
						return case
					end
					now += 0.2
					if case.state == "scene" then
						facts.ambulance = "assigned"
					elseif case.state == "enroute" and state ~= "enroute" then
						facts.ambulance, facts.crewSecs = "arrived", 10
					elseif case.state == "transit" and state ~= "transit" then
						facts.ambulance = "home"
					elseif case.state == "admitted" and state ~= "admitted" then
						facts.hospital = "bed"
					end
					InfectionRules.advance(case, now, facts, dice({}), P)
				end
				error(`never reached {state} (stuck in {case.state})`)
			end
			for _, state in
				{
					"down",
					"scene",
					"enroute",
					"approach",
					"assess",
					"loading",
					"retrieve",
					"transit",
					"admitted",
					"treated",
				}
			do
				local case = patientIn(state)
				t.truthy(InfectionRules.isPatient(case), state)
				t.truthy(not InfectionRules.possessable(case), `{state}: never offered to a player`)
				local now = case.since + 1
				local fx = InfectionRules.advance(case, now, me, dice({}), P)
				t.eq(kinds(fx), "standDown,toast:symptoms", `taken in {state}`)
				t.eq(case.state, "symptomatic", `taken in {state}`)
				t.truthy(case.infected, "standing up is not a cure")
				t.eq(case.untilT, math.huge, "no clock runs while a player holds the body")
				t.eq(InfectionRules.tell(case), "symptomatic", "red eyes, never hidden, never posed")
				t.truthy(InfectionRules.possessable(case) and not InfectionRules.isPatient(case))
				t.eq(InfectionRules.status(case), "symptoms")
				-- nothing happens to them for as long as they stay away, but for the reminders
				for k = 1, 300 do
					local e = kinds(InfectionRules.advance(case, now + k, me, dice({ 0 }), P))
					t.truthy(e == "" or e == "toast:symptoms", `{state}: {e}`)
				end
				t.eq(case.state, "symptomatic")
				-- the cure is the hospital, as for any held person
				local inside: Inputs = { controller = "player", atEntrance = true, nearHospital = true }
				t.eq(kinds(InfectionRules.advance(case, now + 400, inside, dice({}), P)), "toast:treating")
				t.eq(kinds(InfectionRules.advance(case, now + 430, inside, dice({}), P)), "cure,toast:cured")
				t.truthy(not case.infected)
			end
			-- taken while already inside the hospital (a patient in a bed): treated where they stand
			local bed = patientIn("treated")
			local inside: Inputs = { controller = "player", atEntrance = true, nearHospital = true }
			t.eq(
				kinds(InfectionRules.advance(bed, bed.since + 1, inside, dice({}), P)),
				"standDown,toast:symptoms,toast:treating"
			)
			t.truthy(bed.selfTreat and bed.infected)
			-- standUp for a body that was out of the world: when the AI has it back, the usual end follows
			local gone = patientIn("enroute")
			InfectionRules.standUp(gone, 500)
			t.eq(gone.state, "symptomatic")
			t.eq(gone.untilT, math.huge, "the case waits")
			t.truthy(gone.infected)
			t.eq(kinds(InfectionRules.advance(gone, 900, AI, dice({ 0 }), P)), "", "back: the symptom clock starts")
			t.eq(gone.untilT, 908)
			local fx = InfectionRules.advance(gone, 908, { controller = "ai", routeLen = 300 }, dice({ 0.1 }), P)
			t.eq(kinds(fx), "walkIn,say:symptoms")
		end
	)

	t.test("a second bite on an infected person: they run and shout again, the case does not change", function()
		local case = InfectionRules.newCase(14, 0, AI, dice({ 0.9, 0.5 }), P)
		local before = case.untilT
		t.eq(kinds(InfectionRules.rebite(case, 10)), "flee,say:bitten")
		t.eq(case.state, "incubating")
		t.eq(case.untilT, before)
		local down = InfectionRules.newCase(15, 0, AI, dice({ 0.1, 0 }), P)
		t.truthy(not InfectionRules.biteable(down), "just bitten")
		InfectionRules.advance(down, 2, AI, dice({ 0, 0 }), P)
		t.eq(#InfectionRules.rebite(down, 3), 0, "nobody bites a patient on the ground")
		-- a player holding the bitten body is told about the second bite too (and where the cure is)
		local me: Inputs = { controller = "player" }
		local held = InfectionRules.newCase(16, 0, me, dice({ 0.5 }), P)
		t.eq(kinds(InfectionRules.rebite(held, 10)), "flee,say:bitten,toast:bittenAgain")
		t.eq(kinds(InfectionRules.rebite(case, 10, "player")), "flee,say:bitten,toast:bittenAgain", "taken just now")
		t.eq(kinds(InfectionRules.rebite(held, 10, "ai")), "flee,say:bitten", "let go just now")
		t.eq(held.state, "incubating")
	end)

	t.test("2,000 seeded runs: everyone ends cured, only by the hospital; nothing shows before the symptoms", function()
		local ORDER: { [string]: number } = {}
		for i, s in InfectionRules.STATES do
			ORDER[s] = i
		end
		local paths: { [string]: number } = { immediate = 0, walk = 0, collapse = 0, abandoned = 0 }
		local longest = 0
		for seed = 1, 2000 do
			local rng = Rng.new(seed * 7919)
			local nearHospital = rng.next() < 0.1
			local routeLen: number? = if rng.next() < 0.75 then rng.range(20, 3200) else nil
			local walkSecs = rng.range(10, 400) -- how long this walker really takes
			local ambulanceComes = rng.next() < 0.8
			local assignAfter, driveSecs = rng.range(0, 60), rng.range(20, 70)
			local queueSecs = rng.range(0, 90)
			local inputs: Inputs = { controller = "ai", nearHospital = nearHospital, routeLen = routeLen }
			local case = InfectionRules.newCase(seed, 0, inputs, rng.next, P)
			if case.immediate then
				paths.immediate += 1
			end
			local calledAt: number? = nil
			local loadedAt: number? = nil
			local walkAt: number? = nil
			local admittedAt: number? = nil
			local bedAt: number? = nil
			local cures = 0
			local now = 0
			local last = case.state
			while now < 1500 and not InfectionRules.closed(case) do
				now += 0.5
				-- the world's facts, as the glue would report them
				if case.state == "walkin" then
					inputs.atEntrance = walkAt ~= nil and now - walkAt >= walkSecs
				else
					inputs.atEntrance = false
				end
				if calledAt == nil then
					inputs.ambulance = "none"
				elseif loadedAt then
					inputs.ambulance = if now - loadedAt >= driveSecs then "home" else "returning"
				elseif not ambulanceComes or now - calledAt < assignAfter then
					inputs.ambulance = "queued"
				elseif now - calledAt < assignAfter + driveSecs then
					inputs.ambulance = "assigned"
				else
					inputs.ambulance = "arrived"
					inputs.crewSecs = (seed % 5) * 6
				end
				if admittedAt == nil then
					inputs.hospital = "none"
				elseif now - admittedAt < queueSecs then
					inputs.hospital = "queued"
				elseif bedAt == nil or now - bedAt < P.treatSecs then
					inputs.hospital = "bed"
				else
					inputs.hospital = "done"
				end
				local before = case.state
				local fx = InfectionRules.advance(case, now, inputs, rng.next, P)
				for _, e in fx do
					if e.kind == "call" then
						calledAt = now
					elseif e.kind == "load" then
						loadedAt = now
					elseif e.kind == "abandon" then
						calledAt = nil -- the request is dropped
						paths.abandoned += 1
					elseif e.kind == "walkIn" then
						walkAt = now
						paths.walk += 1
					elseif e.kind == "collapse" then
						paths.collapse += 1
					elseif e.kind == "arrive" then
						admittedAt = now
					elseif e.kind == "bed" then
						bedAt = now
					elseif e.kind == "cure" then
						cures += 1
						t.eq(before, "treated", `seed {seed}: cured from {before}`)
						t.eq(inputs.hospital, "done", `seed {seed}: cured before the treatment ended`)
					end
				end
				-- the rules that never break
				if not InfectionRules.closed(case) then
					t.truthy(case.infected, `seed {seed}: not infected in {case.state}`)
				end
				if case.state == "incubating" or case.state == "bitten" then
					t.eq(InfectionRules.tell(case), nil, `seed {seed}: a tell while {case.state}`)
				end
				t.truthy(
					ORDER[case.state] >= ORDER[last] or case.state == "down",
					`seed {seed}: {last} -> {case.state}`
				)
				last = case.state
			end
			t.truthy(InfectionRules.closed(case), `seed {seed}: stuck in {case.state} after {now} s`)
			t.eq(cures, 1, `seed {seed}: {cures} cures`)
			t.truthy(not case.infected)
			t.truthy(bedAt ~= nil and now - (bedAt :: number) >= P.treatSecs - 0.5, `seed {seed}: treated too briefly`)
			if not case.immediate then
				t.truthy((case.symptomsAt :: number) >= 40 - 1e-9, `seed {seed}: symptoms at {case.symptomsAt}`)
			end
			longest = math.max(longest, now)
		end
		t.truthy(paths.immediate > 600 and paths.immediate < 1100, `immediate {paths.immediate}`)
		t.truthy(paths.walk > 150, `walk-ins {paths.walk}`)
		t.truthy(paths.collapse > paths.immediate, "delayed cases collapse too")
		t.truthy(paths.abandoned > 100, `timeouts {paths.abandoned}`)
		print(
			`      2,000 cases: {paths.immediate} collapsed at once, {paths.walk} walked in, {paths.collapse} collapses, {paths.abandoned} without an ambulance; longest {longest} s`
		)
	end)

	t.test(
		"1,500 seeded runs with a player taking and letting go of the body at any moment: never carried, never cured outside, never stuck",
		function()
			-- what is only ever done to a body the AI has: a step that does any of it while a player
			-- holds the body is a broken rule
			local AI_ONLY: { [string]: boolean } = {
				collapse = true,
				call = true,
				crewOut = true,
				carry = true,
				load = true,
				abandon = true,
				walkIn = true,
				arrive = true,
				bed = true,
				discharge = true,
			}
			local taken, stoodDown, selfCured, bedCured = 0, 0, 0, 0
			for seed = 1, 1500 do
				local rng = Rng.new(seed * 104729)
				local routeLen: number? = if rng.next() < 0.7 then rng.range(20, 3000) else nil
				local walkSecs, driveSecs, queueSecs = rng.range(10, 300), rng.range(15, 60), rng.range(0, 40)
				local inputs: Inputs = { controller = "ai", nearHospital = false, routeLen = routeLen }
				local case = InfectionRules.newCase(seed, 0, inputs, rng.next, P)
				-- the world round the case, as the glue keeps it (all of it reset by "standDown")
				local calledAt: number?, loadedAt: number?, walkAt: number?, admittedAt: number?, bedAt: number? =
					nil, nil, nil, nil, nil
				local held, heldUntil, inside, insideSince = false, 0, false, 0
				local cures, now = 0, 0
				while now < 2400 and not InfectionRules.closed(case) do
					now += 0.5
					-- hand-overs: until 700 s a player may take the body at any moment (whatever state
					-- it is in: the race the server guards against) and keeps it for a while, sometimes
					-- walking it into the hospital; after that the AI has it for good
					if held and now >= heldUntil then
						held, inside = false, false
					elseif not held and now < 700 and rng.next() < 0.004 then
						held, heldUntil = true, now + rng.range(1, 200)
						inside = false
						taken += 1
					end
					if held and not inside and rng.next() < 0.01 then
						inside, insideSince = true, now
					elseif held and inside and rng.next() < 0.01 then
						inside = false
					end
					inputs.controller = if held then "player" else "ai"
					if held then
						inputs.atEntrance = inside
					elseif case.state == "walkin" then
						inputs.atEntrance = walkAt ~= nil and now - walkAt >= walkSecs
					else
						inputs.atEntrance = false
					end
					if calledAt == nil then
						inputs.ambulance = "none"
					elseif loadedAt then
						inputs.ambulance = if now - loadedAt >= driveSecs then "home" else "returning"
					elseif now - calledAt < driveSecs then
						inputs.ambulance = "assigned"
					else
						inputs.ambulance = "arrived"
						inputs.crewSecs = (seed % 4) * 8
					end
					if admittedAt == nil then
						inputs.hospital = "none"
					elseif now - admittedAt < queueSecs then
						inputs.hospital = "queued"
					elseif bedAt == nil or now - bedAt < P.treatSecs then
						inputs.hospital = "bed"
					else
						inputs.hospital = "done"
					end
					local before, wasSelf = case.state, case.selfTreat
					local fx = InfectionRules.advance(case, now, inputs, rng.next, P)
					for _, e in fx do
						if held then
							t.truthy(
								not AI_ONLY[e.kind],
								`seed {seed}: "{e.kind}" done to a body a player holds ({before})`
							)
						end
						if e.kind == "standDown" then
							stoodDown += 1
							t.truthy(held, `seed {seed}: stood down with no player`)
							calledAt, loadedAt, walkAt, admittedAt, bedAt = nil, nil, nil, nil, nil
						elseif e.kind == "call" then
							calledAt, loadedAt = now, nil
						elseif e.kind == "load" then
							loadedAt = now
						elseif e.kind == "abandon" then
							calledAt = nil
						elseif e.kind == "walkIn" then
							walkAt = now
						elseif e.kind == "resume" then
							walkAt = nil
						elseif e.kind == "arrive" then
							admittedAt, bedAt = now, nil
						elseif e.kind == "bed" then
							bedAt = now
						elseif e.kind == "cure" then
							cures += 1
							t.eq(before, "treated", `seed {seed}: cured from {before}`)
							if wasSelf then
								selfCured += 1
								t.truthy(held and inside, `seed {seed}: a held person cured outside the hospital`)
								t.truthy(
									now - insideSince >= P.treatSecs - 0.5,
									`seed {seed}: cured after {now - insideSince} s inside`
								)
							else
								bedCured += 1
								t.eq(inputs.hospital, "done", `seed {seed}: cured before the treatment ended`)
							end
						end
					end
					if not InfectionRules.closed(case) then
						t.truthy(case.infected, `seed {seed}: not infected in {case.state}`)
					end
					if held then
						t.truthy(
							not InfectionRules.isPatient(case),
							`seed {seed}: a player holds a patient ({case.state})`
						)
						local tell = InfectionRules.tell(case)
						t.truthy(tell == nil or tell == "symptomatic", `seed {seed}: a held body shows "{tell}"`)
					end
				end
				t.truthy(InfectionRules.closed(case), `seed {seed}: stuck in {case.state} after {now} s`)
				t.eq(cures, 1, `seed {seed}: {cures} cures`)
			end
			print(
				`      1,500 cases, {taken} hand-overs: {stoodDown} patients put back on their feet, {selfCured} cured standing in the hospital, {bedCured} in a bed`
			)
			t.truthy(taken > 2000 and stoodDown > 100, "the hand-overs hit patients often enough to mean something")
			t.truthy(selfCured > 100 and bedCured > 100, "both cures happen")
			t.eq(selfCured + bedCured, 1500)
		end
	)
	t.test(
		"nobody sits down in the road: a collapse that is due waits for the kerb, six seconds at most, and the dice are thrown once",
		function()
			local Q = table.clone(P)
			Q.roadHoldSecs = 6
			local road: Inputs = { controller = "ai", onRoad = true }
			-- bitten, running across a street when the collapse falls due (at 1.5 s)
			local rand = dice({ 0.1, 0 })
			local case = InfectionRules.newCase(1, 0, AI, rand, Q)
			t.eq(kinds(InfectionRules.advance(case, 1.5, road, rand, Q)), "")
			t.eq(case.state, "bitten", "still running")
			t.eq(kinds(InfectionRules.advance(case, 3, road, rand, Q)), "")
			t.eq(kinds(InfectionRules.advance(case, 3.2, AI, rand, Q)), "collapse", "off the road: now")
			-- someone who never gets off it collapses there after the hold (the ambulance then stops short)
			rand = dice({ 0.1, 0 })
			case = InfectionRules.newCase(2, 0, AI, rand, Q)
			t.eq(kinds(InfectionRules.advance(case, 7.4, road, rand, Q)), "")
			t.eq(kinds(InfectionRules.advance(case, 7.5, road, rand, Q)), "collapse")
			-- symptomatic: the walk-in dice are thrown once; only the fall waits
			rand = dice({ 0.9, 0, 0 })
			case = InfectionRules.newCase(3, 0, AI, rand, Q)
			InfectionRules.advance(case, 40, AI, rand, Q)
			t.eq(case.state, "symptomatic")
			t.eq(case.untilT, 48)
			local draws = 0
			local function no(): number
				draws += 1
				return 0.99
			end
			local onRoad: Inputs = { controller = "ai", routeLen = 500, onRoad = true }
			t.eq(kinds(InfectionRules.advance(case, 48, onRoad, no, Q)), "")
			t.truthy(case.falling, "the dice said collapse")
			t.eq(draws, 1)
			t.eq(InfectionRules.tell(case), "symptomatic", "the red eyes stay while they get off the road")
			t.eq(kinds(InfectionRules.advance(case, 50, onRoad, no, Q)), "")
			t.eq(draws, 1, "not thrown again while they wait")
			t.eq(kinds(InfectionRules.advance(case, 51, { controller = "ai", routeLen = 500 }, no, Q)), "collapse")
			t.eq(case.state, "down")
			t.truthy(not case.falling)
			-- a player who takes the body in that moment: no fall, and the AI decides afresh later
			rand = dice({ 0.9, 0, 0 })
			case = InfectionRules.newCase(4, 0, AI, rand, Q)
			InfectionRules.advance(case, 40, AI, rand, Q)
			InfectionRules.advance(case, 48, onRoad, no, Q)
			t.truthy(case.falling)
			InfectionRules.advance(case, 49, { controller = "player", onRoad = true }, no, Q)
			t.eq(case.state, "symptomatic")
			t.truthy(not case.falling)
			-- a walk-in that overruns on a crossing takes the last steps to the kerb
			rand = dice({ 0.9, 0, 0, 0 })
			case = InfectionRules.newCase(5, 0, AI, rand, Q)
			InfectionRules.advance(case, 40, AI, rand, Q)
			InfectionRules.advance(case, 48, { controller = "ai", routeLen = 500 }, rand, Q)
			t.eq(case.state, "walkin")
			local late = case.untilT
			t.eq(kinds(InfectionRules.advance(case, late + 1, road, rand, Q)), "")
			t.eq(kinds(InfectionRules.advance(case, late + 2, AI, rand, Q)), "collapse")
			-- with no hold set (the old params) nothing waits
			rand = dice({ 0.1, 0 })
			case = InfectionRules.newCase(6, 0, AI, rand, P)
			t.eq(kinds(InfectionRules.advance(case, 1.5, road, rand, P)), "collapse")
			t.eq(InfectionRules.defaults().roadHoldSecs, 6)
		end
	)
end
