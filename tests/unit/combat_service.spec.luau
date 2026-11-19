--!strict
-- Server/Combat/CombatService on the town as Boot/Game runs it (tests/lib/BiteRig: the real town AI, fleet and
-- bite-to-hospital sequence): the bite at the right moment instead of on contact, the people's side of the duel on the
-- real brains (a vigilante squares up and closes in; a calm person runs), blows that cost the rodent health, a player's
-- townsperson left to their own kicks, feints, the vigilante share through possessions, and the bite's aftermath
-- (the alert zone's hidden boost and near-impossible second bite, the police within two blocks giving chase and
-- stopping past five).
local BiteRig = require("@tests/lib/BiteRig")

local function dice(v: number): () -> number
	return function(): number
		return v
	end
end

return function(t)
	local function dist(a: any, b: any): number
		return math.sqrt((a.x - b.x) ^ 2 + (a.z - b.z) ^ 2)
	end

	t.test("no bite on contact: touching a person bites nobody; a pounce that touches nobody is a miss", function()
		local rig = BiteRig.new({ seed = 2, duelRand = dice(0) })
		rig.step(20)
		local v = rig.calmNear(0, 0)
		rig.holdRodent()
		rig.step(2, function()
			rig.put(rig.rodent, v.x + 1, v.z)
		end)
		t.eq(rig.combat:stats().bites, 0, "standing on someone is no bite")
		t.truthy(not v.infected)
		-- a pounce at nobody
		rig.put(rig.rodent, 600, 600)
		t.truthy(rig.combat:rodentAct(rig.rodent, "pounce", rig.now()))
		t.eq(rig.attrs[rig.rodent].PounceAt, rig.now(), "the wind-up everyone sees")
		local ok, why = rig.combat:rodentAct(rig.rodent, "pounce", rig.now())
		t.falsy(ok, "one pounce at a time")
		t.eq(why, "not yet")
		rig.step(1.4)
		t.eq(rig.duelNews[#rig.duelNews].what, "missed")
		-- and a real pounce at the person lands
		t.truthy(rig.lunge(v.id), "a pounce into a calm person")
		t.truthy(v.infected, "the bite-to-hospital sequence has them")
	end)

	t.test("a click with no pounce in the motor bites nobody; the motor's pounce with the click does", function()
		local rig = BiteRig.new({ seed = 4, duelRand = dice(0), motorCheck = true })
		rig.step(20)
		local v = rig.calmNear(0, 0)
		rig.holdRodent()
		rig.put(rig.rodent, v.x + 6, v.z)
		t.truthy(rig.combat:rodentAct(rig.rodent, "pounce", rig.now()))
		rig.motor[rig.rodent] = { age = 0 }
		rig.step(1.2, function()
			rig.put(rig.rodent, v.x + 0.5, v.z)
		end)
		t.eq(rig.combat:stats().bites, 0, "the motor never pounced")
		t.truthy(rig.combat:stats().noMotor > 0)
		rig.step(1)
		t.truthy(rig.lunge(v.id), "with the motor's pounce")
	end)

	t.test("the click and the lunge are one pounce: a lunge held back, or a motor gone quiet, bites nobody", function()
		-- (review finding 1: the click, then the body waits out of reach, then a fresh motor pounce in contact)
		local rig = BiteRig.new({ seed = 4, duelRand = dice(0), motorCheck = true })
		rig.step(20)
		local v = rig.calmNear(0, 0)
		rig.holdRodent()
		rig.dt = 0.1
		local P = rig.combat.P
		for _, late in { 0.5, 0.8 } do
			rig.step(2)
			rig.put(rig.rodent, v.x + 8, v.z)
			t.truthy(rig.combat:rodentAct(rig.rodent, "pounce", rig.now()))
			local t0 = rig.time
			rig.motor[rig.rodent] = { age = 0 }
			rig.step(late, function()
				rig.put(rig.rodent, v.x + 8, v.z)
			end)
			-- the motor launches now, `late` seconds after the click (an honest one launches pounce.windup after it)
			local launch = rig.time
			rig.step(0.3, function()
				rig.put(rig.rodent, v.x + 1, v.z)
				rig.motor[rig.rodent] = { age = 0, launchAgo = rig.time - launch }
			end)
			t.eq(rig.combat:stats().bites, 0, `a lunge {late} s after the click ({rig.time - t0} s)`)
		end
		-- the motor's packets stopped a while ago: its last pounce is no proof of this one
		rig.step(2)
		rig.put(rig.rodent, v.x + 8, v.z)
		t.truthy(rig.combat:rodentAct(rig.rodent, "pounce", rig.now()))
		local t1 = rig.time
		rig.step(0.3, function()
			rig.put(rig.rodent, v.x + 1, v.z)
			rig.motor[rig.rodent] = { age = P.motorFresh + 0.1, launchAgo = rig.time - t1 - P.pounceWindup }
		end)
		t.eq(rig.combat:stats().bites, 0, "a stale motor")
		-- and the same pounce launched on time lands (on someone who has not just been chased about)
		rig.put(rig.rodent, v.x + 400, v.z)
		rig.step(10)
		t.truthy(rig.lunge(v.id), "a lunge when the click said")
	end)

	t.test("a vigilante: squares up on sighting, closes in, kicks; into the raised leg no bite lands", function()
		local rig = BiteRig.new({ seed = 6, duelRand = dice(0) })
		rig.step(20)
		local vig = nil
		for id in rig.combat.flags do
			local a = rig.world.actorsById[id]
			if vig == nil or a.id < vig.id then
				vig = a
			end
		end
		t.truthy(vig ~= nil, "the town has vigilantes")
		local v = vig :: any
		t.eq(rig.combat:temperOf(v.id), "tough")
		-- the rodent 25 studs in front of them
		rig.holdRodent()
		local fx, fz = math.sin(v.yaw), math.cos(v.yaw)
		rig.put(rig.rodent, v.x + fx * 25, v.z + fz * 25)
		local rod = rig.world.actorsById[rig.rodent]
		local d0 = dist(v, rod)
		rig.step(0.6)
		t.eq(rig.attrs[v.id].Stance, "squared", "the vigilante's stance: the visible tell")
		t.truthy(dist(v, rod) < d0 - 3, `closing in ({d0} -> {dist(v, rod)})`)
		-- it reaches striking range and kicks (the dice say yes): a blow on the rodent
		t.truthy(
			rig.runUntil(4, function(): boolean
				return #rig.blows > 0
			end),
			"a blow lands"
		)
		local blow = rig.blows[1]
		t.eq(blow.by, v.id)
		t.truthy(blow.amount == 55 or blow.amount == 35, `a kick or a swing ({blow.amount})`)
		t.eq(rig.health[rig.rodent], 100 - blow.amount)
		-- a pounce into the next wind-up is batted away
		local g = rig.combat:guardOf(v.id) :: any
		t.truthy(
			rig.runUntil(3, function(): boolean
				return g.phase == "windup"
			end),
			"winding up again"
		)
		t.truthy(not rig.lunge(v.id, 3), "no bite into a raised leg")
		local news = rig.duelNews[#rig.duelNews]
		t.truthy(news.what == "batted" or #rig.blows > 1, "batted away, or kicked first")
		t.truthy(not v.infected)
		print(`      the vigilante landed {#rig.blows} blows; rodent health {rig.health[rig.rodent]}`)
	end)

	t.test("vigilantes are 8 % of the humans, on AI townspeople; a player taking one moves the flag", function()
		local rig = BiteRig.new({ seed = 8 })
		rig.step(2)
		local humans = 0
		for _, a in rig.world.actors do
			if a.species == "human" then
				humans += 1
			end
		end
		local function flags(): { number }
			local out = {}
			for id in rig.combat.flags do
				table.insert(out, id)
			end
			return out
		end
		local before = flags()
		t.eq(#before, math.floor(humans * 0.08 + 0.5), `round(8 % of {humans})`)
		for _, id in before do
			t.eq(rig.world.actorsById[id].post, "townsperson")
		end
		rig.hold(before[1])
		rig.step(1.2)
		local after = flags()
		t.eq(#after, #before, "still the same number")
		t.falsy(rig.combat:isVigilante(before[1]), "not on a player's body")
		t.eq(rig.combat:temperOf(before[1]) ~= "tough", true)
	end)

	t.test(
		"a calm person who sees the rodent close runs; a player's townsperson is never ordered and kicks for themselves",
		function()
			local rig = BiteRig.new({ seed = 10, duelRand = dice(0) })
			rig.step(20)
			local v = rig.calmNear(0, 0)
			rig.holdRodent()
			rig.put(rig.rodent, v.x + math.sin(v.yaw) * 12, v.z + math.cos(v.yaw) * 12)
			rig.step(0.6)
			t.eq(rig.world.brains[v.id].state, "flee", "the dice say run")
			-- (review finding 6) a runner stays a runner however far behind the rodent falls, for the brain's whole flight
			rig.put(rig.rodent, v.x + 70, v.z)
			rig.step(1)
			local g = rig.combat:guardOf(v.id)
			t.truthy(g ~= nil and g.phase == "flee", "still running, 70 studs off: a bite at the heels is a runner's")
			t.eq(require("@shared/Combat/Duel").bitePhase(g, rig.now()), "runner")
			-- a player's person: no orders, no stance; a kick is a raised leg
			local p = rig.calmNear(-300, 0, { [v.id] = true })
			rig.hold(p.id)
			rig.put(rig.rodent, p.x + 10, p.z)
			rig.step(1)
			t.eq(rig.combat:guardOf(p.id), nil, "no duel for a player's body")
			t.eq((rig.attrs[p.id] or {}).Stance, nil)
			rig.step(1)
			rig.combat:heldKick(p.id, rig.now() + 0.15)
			t.truthy(not rig.lunge(p.id, 4), "no bite into the player's kick")
			t.eq(rig.duelNews[#rig.duelNews].payload.phase, "windup")
			rig.step(1)
			t.truthy(rig.lunge(p.id, 4), "without the kick it lands")
		end
	)

	t.test("feints: a tell with no pounce; three from a full meter, then winded until it refills", function()
		local rig = BiteRig.new({ seed = 12, duelRand = dice(0.5) })
		rig.step(5)
		rig.holdRodent()
		rig.put(rig.rodent, 600, 600)
		for i = 1, 3 do
			t.truthy(rig.combat:rodentAct(rig.rodent, "feint", rig.now()), `feint {i}`)
			t.eq(rig.attrs[rig.rodent].PounceAt, rig.now(), "looks just like a pounce")
			local ok = rig.combat:rodentAct(rig.rodent, "pounce", rig.now())
			t.falsy(ok, "no pounce straight after a feint")
			rig.step(0.5)
		end
		local ok, why = rig.combat:rodentAct(rig.rodent, "feint", rig.now())
		t.falsy(ok)
		t.eq(why, "winded")
		rig.step(3)
		t.truthy(rig.combat:rodentAct(rig.rodent, "feint", rig.now()), "refilled")
	end)

	t.test(
		"after a bite: the zone's hidden boost, a second bite there close to impossible, the police within two blocks give chase and stop past five",
		function()
			local rig = BiteRig.new({ seed = 14, duelRand = dice(0.06) })
			rig.step(20)
			-- bitten near the police beat, so that officers are within two blocks
			local officer = nil
			for _, a in rig.world.actors do
				if a.post == "police" and rig.world.brains[a.id].kind == "Officer" then
					officer = officer or a
				end
			end
			local cop = officer :: any
			local v = rig.calmNear(cop.x, cop.z)
			t.truthy(rig.lunge(v.id), "the first bite (0.06 against an unaware or running person)")
			t.eq(#rig.combat:zones(), 1, "a zone at the bite")
			local zone = rig.combat:zones()[1]
			t.truthy(rig.combat:inAlert(v.x, v.z, rig.now()))
			t.eq(rig.combat:boost(zone.x, zone.z, rig.now()), 1.25, "the hidden strength boost (alert.kickMult)")
			t.eq(rig.combat:boost(zone.x + 500, zone.z, rig.now()), 1)
			local chasing = 0
			for _ in rig.combat.chases do
				chasing += 1
			end
			t.truthy(chasing >= 1, "officers give chase")
			print(`      {chasing} officers within two blocks give chase`)
			-- the officers head for the rodent
			rig.step(1)
			local brain = rig.world.brains[cop.id] :: any
			local rod = rig.world.actorsById[rig.rodent]
			if rig.combat.chases[cop.id] then
				t.truthy(brain.respondUntil > rig.world.now, "ordered after the rodent")
				t.truthy(math.abs(brain.respondX - rod.x) < 40, "toward where it is")
			end
			-- a second bite inside the zone: 0.06 is no longer enough (x alert.bitePenalty)
			local w = rig.calmNear(zone.x, zone.z, { [v.id] = true })
			t.truthy(dist(w, zone) < 100, "a second person inside the zone")
			t.truthy(not rig.lunge(w.id), "the second bite fails")
			t.eq(rig.duelNews[#rig.duelNews].payload.zone, true)
			-- far from it, the same dice land
			local far = rig.calmNear(zone.x + 900, zone.z + 900)
			t.truthy(dist(far, zone) > 120)
			t.truthy(rig.lunge(far.id), "a bite far from the zone lands")
			-- the rodent runs beyond five blocks: the chase is called off
			rig.put(rig.rodent, zone.x + 5 * 440 + 100, zone.z)
			rig.step(1)
			for id, c in rig.combat.chases do
				t.truthy(c.zone ~= zone, `officer {id} still chasing past the leash`)
			end
		end
	)
end
