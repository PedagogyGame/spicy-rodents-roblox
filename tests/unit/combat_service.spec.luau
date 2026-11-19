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

	t.test(
		"a quick retry after a miss is a real pounce: the server takes a click when the motor would (review finding 7)",
		function()
			local rig = BiteRig.new({ seed = 3, duelRand = dice(0.99) })
			rig.step(5)
			rig.holdRodent()
			rig.put(rig.rodent, 900, 900)
			local P = rig.combat.P
			local t0 = rig.now()
			t.truthy(rig.combat:rodentAct(rig.rodent, "pounce", t0))
			-- the client lets the motor pounce again pounce.windup + pounce.cooldown after the click (Controllers/Squirrel)
			local again = t0 + P.pounceWindup + P.pounceCooldown
			local ok, why = rig.combat:rodentAct(rig.rodent, "pounce", again - 0.3)
			t.falsy(ok, "not mid-cooldown")
			t.eq(why, "not yet")
			while rig.now() < again - 1e-6 do
				rig.step(0.1)
			end
			t.truthy(rig.combat:rodentAct(rig.rodent, "pounce", rig.now()), "the retry the motor allows is taken")
			t.truthy(rig.combat:stats().missed >= 1, "the first one counted as a miss")
			-- and a refused click is told to the player
			t.truthy(require("@client/UI/DuelWords").news("notyet", false) ~= nil)
		end
	)

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

	t.test("no blow and no noticing through a housing's walls or a building (review finding 4)", function()
		local Cover = require("@shared/Combat/Cover")
		local Colliders = require("@shared/World/Colliders")
		local function firstVigilante(rig: any): any
			local vig = nil
			for id in rig.combat.flags do
				local a = rig.world.actorsById[id]
				if vig == nil or a.id < vig.id then
					vig = a
				end
			end
			return vig
		end
		-- the rodent inside a housing (a Cover box), the vigilante 5 studs outside it: nothing
		do
			local rig = BiteRig.new({ seed = 6, duelRand = dice(0) })
			rig.step(20)
			local v = firstVigilante(rig)
			rig.holdRodent()
			local rx, rz = v.x + math.sin(v.yaw) * 5, v.z + math.cos(v.yaw) * 5
			rig.put(rig.rodent, rx, rz)
			local rod = rig.world.actorsById[rig.rodent]
			local key = Cover.add({
				name = "spec housing",
				place = { x = rx, z = rz, floorY = rod.y - 50, yaw = 0 },
				x0 = -1.5,
				x1 = 1.5,
				y0 = 0,
				y1 = 100,
				d0 = -1.5,
				d1 = 1.5,
			})
			rig.step(4, function()
				rig.put(rig.rodent, rx, rz)
			end)
			Cover.remove(key)
			t.eq(#rig.blows, 0, "no blow through the housing")
			t.eq((rig.attrs[v.id] or {}).Stance, nil, "not squared up at a rodent it cannot see")
		end
		-- a building's wall between them: nothing; the same spot with no wall: kicked
		for _, wall in { true, false } do
			local rig = BiteRig.new({ seed = 6, duelRand = dice(0) })
			rig.step(20)
			local v = firstVigilante(rig)
			rig.holdRodent()
			local fx, fz = math.sin(v.yaw), math.cos(v.yaw)
			local rx, rz = v.x + fx * 6, v.z + fz * 6
			rig.put(rig.rodent, rx, rz)
			local colliders = (rig.infection :: any).colliders
			local box: any = nil
			if wall then
				-- a thin wall across the line between them, 3 studs in front of the person
				local along = math.abs(fx) > math.abs(fz)
				box = {
					id = "spec wall",
					cx = v.x + fx * 3,
					cz = v.z + fz * 3,
					hw = if along then 0.4 else 12,
					hd = if along then 12 else 0.4,
					y0 = v.y - 20,
					eave = v.y + 40,
					peak = v.y + 40,
					ridge = nil,
				}
				Colliders.add(colliders, box)
			end
			rig.step(4, function()
				rig.put(rig.rodent, rx, rz)
			end)
			if wall then
				local i = table.find(colliders.boxes, box)
				if i then
					table.remove(colliders.boxes, i)
				end
				for _, list in colliders.cells do
					local j = table.find(list, box)
					if j then
						table.remove(list, j)
					end
				end
				t.eq(#rig.blows, 0, "no blow through a wall")
				t.eq((rig.attrs[v.id] or {}).Stance, nil, "and it never saw the rodent")
			else
				t.truthy(#rig.blows > 0, "with no wall it kicks")
			end
		end
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
			-- (review finding 8) a kick at nothing, facing away from the rodent, raises no guard
			t.falsy(rig.combat:heldKick(p.id, rig.now() + 0.15, -1, 0), "kicking at nothing")
			t.truthy(rig.combat:heldKick(p.id, rig.now() + 0.15, 1, 0), "kicking at the rodent in front")
			t.truthy(not rig.lunge(p.id, 4), "no bite into the player's kick")
			t.eq(rig.duelNews[#rig.duelNews].payload.phase, "windup")
			rig.step(1)
			t.truthy(rig.lunge(p.id, 4), "without the kick it lands")
		end
	)

	t.test(
		"a player mashing F is not bite-proof, and their kick shares the duel's i-frames (review finding 8)",
		function()
			local rig = BiteRig.new({ seed = 10, duelRand = dice(0) })
			rig.step(20)
			local p = rig.calmNear(-300, 0)
			rig.hold(p.id)
			rig.holdRodent()
			rig.put(rig.rodent, p.x + 9, p.z)
			rig.step(0.5)
			-- F every 0.7 s (the kick's cooldown), facing away: no raised leg, so a bite between kicks lands
			for _ = 1, 3 do
				t.falsy(rig.combat:heldKick(p.id, rig.now(), -1, 0))
				rig.step(0.7)
			end
			t.truthy(rig.lunge(p.id, 4), "a bite on a person kicking at the air")
			-- the i-frames: a blow lands, and a player's kick in the same instant glances off
			local rig2 = BiteRig.new({ seed = 6, duelRand = dice(0) })
			rig2.step(20)
			rig2.holdRodent()
			rig2.put(rig2.rodent, 900, 900)
			rig2.step(0.2)
			t.truthy(rig2.combat:takeBlow(rig2.rodent, rig2.now()), "the first blow lands")
			t.falsy(rig2.combat:takeBlow(rig2.rodent, rig2.now() + 0.05), "a second inside rodent.iFrames does not")
			t.truthy(rig2.combat:takeBlow(rig2.rodent, rig2.now() + rig2.combat.P.iFrames + 0.01), "after them it does")
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
		"after a bite: the zone's hidden boost, a second bite there close to impossible, the nearest police give chase wherever they are and lose it two blocks off",
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
			local P = rig.combat.P
			local officers = 0
			for _, a in rig.world.actors do
				if a.post == "police" and rig.world.brains[a.id].kind == "Officer" then
					officers += 1
				end
			end
			t.eq(chasing, math.min(P.policeSend, officers), "the nearest available officers give chase")
			-- (owner 2026-11-19: no pursuit radius) the nearest, however far
			local nearest, nearestD = nil, math.huge
			for _, a in rig.world.actors do
				if a.post == "police" and rig.world.brains[a.id].kind == "Officer" then
					local d = dist(a, zone)
					if d < nearestD then
						nearest, nearestD = a, d
					end
				end
			end
			t.truthy(rig.combat.chases[(nearest :: any).id] ~= nil, "the nearest officer is one of them")
			print(`      {chasing} of {officers} officers give chase (the nearest {math.floor(nearestD)} studs off)`)
			rig.step(0.3)
			local still = 0
			for _ in rig.combat.chases do
				still += 1
			end
			t.eq(still, chasing, "sent from any distance, still on it")
			-- the officers head for the rodent
			rig.step(1)
			local brain = rig.world.brains[cop.id] :: any
			local rod = rig.world.actorsById[rig.rodent]
			if rig.combat.chases[cop.id] then
				t.truthy(brain.respondUntil > rig.world.now, "ordered after the rodent")
				t.truthy(math.abs(brain.respondX - rod.x) < 40, "toward where it is")
			end
			-- no leash round the bite: far from it, but within two blocks of a chasing officer, the chase goes on
			local lose = P.policeLoseBlocks * P.blockLen
			local id0, chase0 = next(rig.combat.chases)
			t.truthy(id0 ~= nil, "a chase still on")
			local c0 = rig.world.actorsById[id0 :: number]
			local awayX = if c0.x >= zone.x then 1 else -1
			rig.put(rig.rodent, c0.x + awayX * (lose - 150), c0.z)
			t.truthy(dist(rig.world.actorsById[rig.rodent], zone) > lose - 150, "far from the bite")
			rig.step(0.3)
			t.truthy(rig.combat.chases[id0 :: number] == chase0, "within two blocks of the officer: still chased")
			-- more than two blocks from every officer: they lose track of it
			local rod2 = rig.world.actorsById[rig.rodent]
			rig.put(rig.rodent, rod2.x + awayX * 2 * lose, rod2.z)
			rig.step(1)
			for id, c in rig.combat.chases do
				local cop2 = rig.world.actorsById[id]
				t.truthy(
					c.zone ~= zone or not c.acquired or dist(cop2, rig.world.actorsById[rig.rodent]) <= lose,
					`officer {id} still chasing more than two blocks off`
				)
			end
			rig.put(rig.rodent, zone.x + 20, zone.z)
			-- a second bite inside the zone: 0.06 is no longer enough (x alert.bitePenalty)
			local w = rig.calmNear(zone.x, zone.z, { [v.id] = true })
			t.truthy(dist(w, zone) < 100, "a second person inside the zone")
			t.truthy(not rig.lunge(w.id), "the second bite fails")
			t.eq(rig.duelNews[#rig.duelNews].payload.zone, true)
			-- far from it, the same dice land
			local far = rig.calmNear(zone.x + 900, zone.z + 900)
			t.truthy(dist(far, zone) > 120)
			t.truthy(rig.lunge(far.id), "a bite far from the zone lands")
		end
	)
end
