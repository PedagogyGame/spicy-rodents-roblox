--!strict
-- The bite and what follows it, played as a player would see it (owner playtest 2026-11-18: "I really want to make sure
-- that there is an ambulance sequence after the person is bitten by the squirrel, and that all those mechanics work").
-- tests/lib/BiteRig: the real town, the real fleet, the bite-to-hospital sequence and the duel, stepped as Boot/Game
-- steps them; what is checked is what reaches a screen: the bubbles (Say), the poses (Med), the ambulance's poses on
-- the roads, the toasts a player is sent. Four plays:
--   1. a townsperson bitten in the middle of town: the shout, the collapse, the crowd and its lines, the call, the
--      ambulance driving there, the crew loading the patient, the hospital bed, the cure there and nowhere else;
--   2. symptoms later: nothing to see for 40 s or more, then the red eyes, the walk in, the cure;
--   3. the victim is a player's: told on screen what happened and what to do, never moved, cured by walking into
--      the hospital and staying for the treatment;
--   4. two bites seconds apart, and one at the far edge of town: every patient is collected and cured.
-- Every bite here is a player's pounce through the duel (Combat/CombatService), as the game makes it.
local HospitalLayout = require("@shared/Infection/HospitalLayout")
local Lines = require("@shared/Speech/Lines")
local MedicalRoute = require("@shared/Infection/MedicalRoute")
local BiteRig = require("@tests/lib/BiteRig")

local function zero(): number
	return 0
end

return function(t)
	local function timeline(rig: any, id: number, what: string)
		local log = rig.medLog[id] or {}
		print(`      {what}: Med {table.concat(log, " > ")}`)
	end

	-- a player's Spicy Rodent pounces at the person through the duel (Combat/CombatService: the click, the wind-up, the
	-- lunge, the contact in the window); the duel's dice are all 0 here, so a bite that can land does
	local function biteBeside(rig: any, victim: any): boolean
		return rig.lunge(victim.id)
	end

	local function nearestFreeResponderDist(rig: any, x: number, z: number): number
		local best = math.huge
		for _, v in rig.responders() do
			if v.visible and v.phase ~= "idle" then
				best = math.min(best, math.sqrt((v.x - x) ^ 2 + (v.z - z) ^ 2))
			end
		end
		return best
	end

	t.test(
		"1. bitten in the street: the shout, the collapse, the crowd, the call, the ambulance, the crew, the bed, the cure",
		function()
			local rig = BiteRig.new({ duelRand = zero, seed = 11, first = { 0, 0 } })
			rig.infection.tun.crowdChance = 1
			rig.step(20)
			local victim = rig.calmNear(0, 0)
			local id = victim.id
			t.truthy(biteBeside(rig, victim), "the bite starts a case")
			-- the shout, at once
			t.truthy(
				table.find(Lines.GROUPS.bitten, rig.attrs[id].Say) ~= nil,
				`the victim shouts a bitten line ({rig.attrs[id].Say})`
			)
			t.eq(rig.world.brains[id].state, "flee", "and runs")
			t.eq(rig.toasts[#rig.toasts], nil, "nobody holds the victim: no toast for them")
			-- down within a few seconds; the crowd is called over
			t.truthy(
				rig.runUntil(6, function(): boolean
					return rig.attrs[id].Med == "down"
				end),
				"collapses within 6 s"
			)
			local sx, sz = victim.x, victim.z
			local scene = rig.infection.scenes[id]
			t.truthy(scene ~= nil and #scene.bystanders >= 2, "a crowd of two or more is called over")
			-- the call: an ambulance leaves the bay and drives there on the roads
			local outAt: number? = nil
			local closest = math.huge
			local offRoad = 0
			t.truthy(
				rig.runUntil(160, function(): boolean
					local s = rig.infection:stateOf(id)
					return s == "transit" or s == "treated"
				end, function()
					for _, v in rig.responders() do
						if v.phase == "out" and v.visible then
							outAt = outAt or rig.time
							local off = 0
							while off < 60 and not MedicalRoute.onRoad(rig.infection.roads, v.x, v.z, off) do
								off += 1
							end
							offRoad = math.max(offRoad, off)
						end
					end
					closest = math.min(closest, nearestFreeResponderDist(rig, sx, sz))
					local st = rig.infection:stateOf(id)
					if st == "down" or st == "scene" or st == "enroute" then
						t.eq(victim.x, sx, "the patient stays where they fell until the crew comes")
					end
				end),
				`the patient was never loaded (state {rig.infection:stateOf(id)})`
			)
			t.truthy(outAt ~= nil, "an ambulance was seen driving out")
			t.truthy(offRoad <= MedicalRoute.JOIN_GAP, `the ambulance kept to the roads ({offRoad} studs off)`)
			t.truthy(closest < 60, `the ambulance came within {math.floor(closest)} studs of the patient`)
			-- the crowd gathered round and said things; someone asked for an ambulance
			local crowdLines = rig.saidBy("bystander")
			t.truthy(#crowdLines >= 2, `the crowd speaks ({#crowdLines} lines)`)
			local saidCrew = rig.saidBy("crew")
			print(
				`      scene at ({math.floor(sx)}, {math.floor(sz)}): {#scene.bystanders} in the crowd, {#crowdLines} crowd lines, {#saidCrew} crew lines; ambulance out at {math.floor(
					outAt or -1
				)} s, closest {math.floor(closest)} studs`
			)
			-- in a bed, treated, cured inside the hospital
			t.truthy(
				rig.runUntil(220, function(): boolean
					return rig.infection:stateOf(id) == "treated"
				end),
				"in a bed at the hospital"
			)
			t.truthy(victim.infected, "still infected in the bed")
			t.truthy(
				rig.runUntil(40, function(): boolean
					return rig.infection:stateOf(id) == nil
				end),
				"treated and cured"
			)
			t.truthy(not victim.infected, "cured")
			t.truthy(HospitalLayout.contains(rig.infection.layout, victim.x, victim.z), "cured in the hospital")
			local log = rig.medLog[id]
			t.eq(log[1], "down")
			t.truthy(table.find(log, "transit") ~= nil and table.find(log, "treated") ~= nil, "carried off and treated")
			t.eq(log[#log], "-", "and nothing shows afterwards")
			timeline(rig, id, "the street bite")
		end
	)

	t.test("2. symptoms later: nothing to see for 40 s or more, then red eyes, the walk in and the cure", function()
		local rig = BiteRig.new({
			duelRand = zero,
			seed = 5,
			first = { 0.99, 0 },
			tune = function(p: any)
				p.walkInChance = 1
			end,
		})
		rig.step(20)
		local layout = rig.infection.layout
		local victim = rig.calmNear(layout.entrance[1], layout.entrance[2])
		local id = victim.id
		t.truthy(biteBeside(rig, victim))
		local bitAt = rig.time
		t.truthy(rig.runUntil(200, function(): boolean
			return rig.attrs[id].Med == "symptomatic"
		end, function()
			if rig.attrs[id].Med ~= "symptomatic" then
				t.eq(rig.attrs[id].Med, nil, "nothing shows while it incubates")
			end
		end))
		t.truthy(rig.time - bitAt >= 40, `the symptoms came {rig.time - bitAt} s after the bite`)
		t.truthy(
			rig.runUntil(400, function(): boolean
				return rig.infection:stateOf(id) == nil
			end),
			`never cured (state {rig.infection:stateOf(id)})`
		)
		t.truthy(not victim.infected)
		t.truthy(table.find(rig.medLog[id], "treated") ~= nil, "treated in the hospital")
		timeline(rig, id, "the delayed bite")
	end)

	t.test(
		"3. a player's townsperson bitten: told what happened and what to do, never moved, cured by staying in the hospital",
		function()
			local rig = BiteRig.new({ duelRand = zero, seed = 3, first = { 0, 0 } })
			rig.step(20)
			local victim = rig.calmNear(0, 0)
			local id = victim.id
			rig.hold(id)
			t.truthy(biteBeside(rig, victim))
			local mine = {}
			for _, toast in rig.toasts do
				if toast.id == id then
					table.insert(mine, toast)
				end
			end
			t.truthy(#mine >= 1 and type(mine[1].text) == "string", "told on screen at once")
			t.truthy(rig.infection:statusOf(id) ~= nil, "a line stays on screen")
			local x0, z0 = victim.x, victim.z
			rig.step(150, function()
				t.eq(victim.x, x0, "a player's body is never moved")
				t.eq(victim.z, z0)
				t.eq(victim.lift, nil, "never hidden")
			end)
			t.truthy(victim.infected, "nobody recovers in town")
			local reminders = 0
			for _, toast in rig.toasts do
				if toast.id == id then
					reminders += 1
				end
			end
			t.truthy(reminders >= 3, `reminded what to do ({reminders} toasts in 150 s)`)
			-- walks in and stays for the treatment
			local layout = rig.infection.layout
			rig.put(id, layout.reception[1], layout.reception[2])
			t.truthy(
				rig.runUntil(40, function(): boolean
					return rig.infection:stateOf(id) == nil
				end),
				"cured after the treatment"
			)
			t.truthy(not victim.infected)
			print(`      the held victim: {reminders} toasts while away; cured in the hospital`)
		end
	)

	t.test(
		"4. two bites seconds apart, and one at the far edge of town: every patient is collected and cured",
		function()
			local rig = BiteRig.new({ duelRand = zero, seed = 21 })
			rig.step(20)
			local a = rig.calmNear(0, 0)
			rig.dice({ 0, 0 }) -- each of the three collapses at once: three scenes, three calls
			t.truthy(biteBeside(rig, a))
			rig.step(2)
			local b = rig.calmNear(a.x, a.z, { [a.id] = true })
			rig.dice({ 0, 0 })
			t.truthy(biteBeside(rig, b), "a second person bitten two seconds later")
			-- the far one: the townsperson furthest from the hospital
			local layout = rig.infection.layout
			local far, farD = nil, -1
			for _, p in rig.world.actors do
				if
					p.species == "human"
					and p.post == "townsperson"
					and not p.infected
					and rig.combat:temperOf(p.id) == "calm"
				then
					local d = (p.x - layout.entrance[1]) ^ 2 + (p.z - layout.entrance[2]) ^ 2
					if d > farD then
						far, farD = p, d
					end
				end
			end
			rig.dice({ 0, 0 })
			t.truthy(biteBeside(rig, far), "and one at the far edge")
			print(`      the far bite is {math.floor(math.sqrt(farD))} studs from the hospital door`)
			local ids = { a.id, b.id, far.id }
			t.truthy(
				rig.runUntil(900, function(): boolean
					for _, id in ids do
						if rig.infection:stateOf(id) ~= nil then
							return false
						end
					end
					return true
				end),
				"everyone is cured"
			)
			for _, id in ids do
				t.truthy(not rig.world.actorsById[id].infected)
				t.eq((rig.medLog[id] or {})[1], "down", `{id} collapsed where they were bitten`)
				t.truthy(table.find(rig.medLog[id] or {}, "treated") ~= nil, `{id} was treated in the hospital`)
				timeline(rig, id, `patient {id}`)
			end
			local stats = rig.infection:stats()
			t.eq(stats.dispatched, 3, "three ambulance trips")
			print(
				`      {stats.dispatched} ambulance trips, {stats.abandoned} taken in without one, done at {math.floor(
					rig.time
				)} s`
			)
		end
	)
end
