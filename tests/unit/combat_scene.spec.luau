--!strict
-- The scene fights back (owner, second playtest 2026-11-18: "none on the scene attacked me initially, i would like more
-- of that"), on the rig (tests/lib/BiteRig: the real town, its people and the duel stepped as Boot/Game steps them).
-- A street bite: everyone in sight of it within duel.sceneRadius turns on the rodent at once: vigilantes and most wary
-- people square up and go for it, most calm people back off shouting, some lash out (more readily in the bite's
-- boost). Nobody behind a building joins in. A rodent that runs at once gets away; one that stays is set upon. The same
-- when it sets on a group. Over 16 street bites the spec prints how many on the scene attack (median and range).
local BiteRig = require("@tests/lib/BiteRig")

local CASES = 16

-- every bite that can land lands (the spec is about what follows it); the rest of the duel keeps its seeded dice
local function landIt(): number
	return 0
end

local function median(list: { number }): number
	local s = table.clone(list)
	table.sort(s)
	local n = #s
	if n == 0 then
		return 0
	end
	return if n % 2 == 1 then s[(n + 1) // 2] else (s[n // 2] + s[n // 2 + 1]) / 2
end

-- a calm townsperson with at least `others` people (not themselves) within the scene's radius
local function streetVictim(rig: any, others: number): any
	local P = rig.combat.P
	local skip: { [number]: boolean } = {}
	for _ = 1, 40 do
		local v = rig.calmNear(0, 0, skip)
		if v == nil then
			return nil
		end
		local n = 0
		for _, a in rig.world.actors do
			if
				a.species == "human"
				and a.id ~= v.id
				and (a.x - v.x) ^ 2 + (a.z - v.z) ^ 2 <= P.sceneRadius * P.sceneRadius
			then
				n += 1
			end
		end
		if n >= others then
			return v
		end
		skip[v.id] = true
	end
	return nil
end

return function(t)
	local attackers: { number } = {}
	local onScene: { number } = {}
	local byTemper: { [string]: { attack: number, other: number } } = {
		calm = { attack = 0, other = 0 },
		wary = { attack = 0, other = 0 },
		tough = { attack = 0, other = 0 },
	}
	local escapes, ranAway = 0, 0
	local stayedBlows = 0

	t.test("a street bite: the people in sight of it turn on the rodent at once", function()
		for case = 1, CASES do
			local rig = BiteRig.new({ seed = 300 + case, biteRand = landIt })
			rig.step(20 + case)
			local v = streetVictim(rig, 2)
			if v == nil then
				continue
			end
			local before = rig.combat:stats()
			local bitten = false
			for _ = 1, 6 do
				if rig.lunge(v.id, 6) then
					bitten = true
					break
				end
				rig.step(0.5)
			end
			if not bitten then
				continue
			end
			local after = rig.combat:stats()
			table.insert(attackers, after.rallyAttack - before.rallyAttack)
			table.insert(onScene, after.rallied - before.rallied)
			for id, g in rig.combat.guards do
				local at = rig.combat.rallied[id]
				if at ~= nil and at >= rig.now() - 1 then
					local row = byTemper[g.temper]
					if g.rallyUntil > 0 then
						row.attack += 1
					else
						row.other += 1
					end
				end
			end
			-- half the rodents run at once (straight away from the victim at a sprint); the others stay put
			local rod = rig.world.actorsById[rig.rodent]
			local blows = #rig.blows
			if case % 2 == 0 then
				ranAway += 1
				local dx, dz = rod.x - v.x, rod.z - v.z
				local d = math.max(1e-6, math.sqrt(dx * dx + dz * dz))
				local ux, uz = dx / d, dz / d
				local h0 = rig.health[rig.rodent] or 100
				rig.step(2.5, function()
					rig.put(rig.rodent, rod.x + ux * 33 * rig.dt, rod.z + uz * 33 * rig.dt)
				end)
				print(`      case {case}: ran with {h0} health, {#rig.blows - blows} blows on the way`)
				if #rig.blows - blows <= 1 then
					escapes += 1
				end
			else
				local x, z = rod.x, rod.z
				rig.step(4, function()
					rig.put(rig.rodent, x, z)
				end)
				stayedBlows += #rig.blows - blows
			end
		end
		local total, most = 0, 0
		for _, n in attackers do
			total += n
			most = math.max(most, n)
		end
		local least = math.huge
		for _, n in attackers do
			least = math.min(least, n)
		end
		print(
			`      {#attackers} street bites: on the scene {median(onScene)} (median), attacking {median(attackers)} (median), {least}-{most} (range), {total} in all`
		)
		for temper, row in byTemper do
			print(`      {temper}: {row.attack} attacked, {row.other} backed off or ran`)
		end
		print(
			`      ran at once: {escapes}/{ranAway} got away on their feet; stayed: {stayedBlows} blows on them in 4 s`
		)
		t.truthy(#attackers >= CASES * 0.6, `enough street bites landed ({#attackers})`)
		t.truthy(median(attackers) >= 1, "a typical street bite has someone go for the rodent")
		t.truthy(most >= 2, "a busy street has several")
		t.truthy(byTemper.wary.attack >= byTemper.wary.other, "most wary people attack")
		t.eq(byTemper.tough.other, 0, "vigilantes always do")
		t.truthy(byTemper.calm.other > byTemper.calm.attack, "most calm people back off or run")
		t.truthy(escapes >= ranAway - 1, "a rodent that runs at once gets away")
		t.truthy(stayedBlows > 0, "one that stays is set upon")
	end)

	t.test("nobody behind a building joins in; a pounce into a group turns the group on it", function()
		local Colliders = require("@shared/World/Colliders")
		local rig = BiteRig.new({ seed = 77, biteRand = landIt })
		rig.step(20)
		local v = streetVictim(rig, 1)
		t.truthy(v ~= nil)
		-- a wall boxing the victim in on three sides and the top: nobody outside it sees the bite
		local colliders = (rig.infection :: any).colliders
		local boxes = {}
		for _, b in
			{
				{ dx = 6, dz = 0, hw = 0.4, hd = 6 },
				{ dx = -6, dz = 0, hw = 0.4, hd = 6 },
				{ dx = 0, dz = 6, hw = 6, hd = 0.4 },
				{ dx = 0, dz = -6, hw = 6, hd = 0.4 },
			}
		do
			local box: any = {
				id = "spec wall",
				cx = v.x + b.dx,
				cz = v.z + b.dz,
				hw = b.hw,
				hd = b.hd,
				y0 = v.y - 20,
				eave = v.y + 40,
				peak = v.y + 40,
				ridge = nil,
			}
			Colliders.add(colliders, box)
			table.insert(boxes, box)
		end
		local before = rig.combat:stats().rallied
		local bitten = false
		for _ = 1, 6 do
			-- (the rodent inside the walls with them: from 3 studs)
			if rig.lunge(v.id, 3) then
				bitten = true
				break
			end
			rig.step(0.5)
		end
		local after = rig.combat:stats().rallied
		for _, box in boxes do
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
		end
		t.truthy(bitten, "the bite inside the walls")
		t.eq(after - before, 0, "nobody outside the walls turned on the rodent")
		-- a group of four: the rodent's pounce starts among them and they turn on it together
		local rig2 = BiteRig.new({ seed = 78 })
		rig2.step(20)
		local P = rig2.combat.P
		local g = rig2.calmNear(0, 0)
		local skip: { [number]: boolean } = { [g.id] = true }
		local group = { g }
		for i = 1, 3 do
			local o = rig2.near(g.x, g.z, nil, skip)
			skip[o.id] = true
			rig2.hold(o.id) -- (held still for the test, then let go to the AI)
			rig2.put(o.id, g.x + math.cos(i * 2) * 6, g.z + math.sin(i * 2) * 6)
			rig2.let(o.id)
			table.insert(group, o)
		end
		rig2.holdRodent()
		rig2.put(rig2.rodent, g.x + 3, g.z)
		local r0 = rig2.combat:stats().rallied
		t.truthy(rig2.combat:rodentAct(rig2.rodent, "pounce", rig2.now()))
		rig2.step(0.2)
		local n = rig2.combat:stats().rallied - r0
		t.truthy(n >= P.groupMin, `the group turned on it ({n})`)
	end)
end
