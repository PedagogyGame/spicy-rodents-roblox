--!strict
-- Review of feat/overhead-watch (merged onto w0-foundation): failing cases. Each case says what the game should do;
-- the review (scratchpad review_overhead.md) says what it does instead and what would fix it.
--   1. A rodent that keeps still on a wire after people have pointed it out does not hold them in the duel for good:
--      the officers who spotted it stand in the road under the wire and swing at it, 40 studs up, as long as it stays.
--   2. "Alarmed for the rest of the duel": once the person has let the rodent go (not aware), the alarm is over too.
--   3. An honest ground creep (4.1 studs/s) is not heard because one of the server's 0.1 s duel steps saw the body's
--      move of two (a phone's frame hitch, positions arriving in a bunch): the duel reads its pace off the root's
--      arrivals, and 2 x 4.1 is over duel.quietSpeed.
--   4. A squirrel walking to and fro 10.5 studs up on something that is not a route (a parked truck's roof, a wall
--      top: the motor stands on any colliding top), 5 studs in front of a person, is noticed by someone: the duel
--      leaves anything over duel.overheadY to the overhead watch, and the overhead watch only counts routes.
local BiteRig = require("@tests/lib/BiteRig")
local CombatRules = require("@shared/Combat/CombatRules")
local Duel = require("@shared/Combat/Duel")

local WIRE = 163 -- the spec's wire over the busiest crossing (overhead_service.spec)

local function wireWalker(rig: any)
	local world = rig.world
	local pts = world.routes.byId(WIRE).points
	local cum = { 0 }
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		cum[i] = cum[i - 1] + math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
	end
	rig.holdRodent()
	rig.route[rig.rodent] = WIRE
	local rod = world.actorsById[rig.rodent]
	return function(s: number, speed: number)
		local i = 2
		while i < #pts and cum[i] < s do
			i += 1
		end
		local a, b = pts[i - 1], pts[i]
		local k = (s - cum[i - 1]) / math.max(1e-6, cum[i] - cum[i - 1])
		rod.x = a[1] + (b[1] - a[1]) * k
		rod.z = a[3] + (b[3] - a[3]) * k
		rod.y = a[2] + (b[2] - a[2]) * k + rod.hip
		rod.speed = speed
	end,
		cum[#cum]
end

return function(t)
	t.test(
		"a rodent keeping still on a wire does not hold the people who pointed it out in the duel for good",
		function()
			local rig = BiteRig.new({ seed = 1, overhead = true })
			rig.step(20)
			local world = rig.world
			local place, L = wireWalker(rig)
			local rod = world.actorsById[rig.rodent]
			place(L / 2, 0)
			local mx, mz = rod.x, rod.z
			-- two officers and six townspeople on the pavement by the middle of the wire
			local skip = {}
			for i = 1, 8 do
				local a = rig.near(mx, mz, if i <= 2 then "police" else nil, skip)
				if a then
					skip[a.id] = true
					rig.put(a.id, mx + 6 + math.cos(i * 2.4) * 4, mz + math.sin(i * 2.4) * 8)
				end
			end
			-- it walks to and fro over them for 15 s, then keeps still over the middle for 60 s
			local s, dir = L / 2 - 15, 1
			rig.step(15, function()
				s += dir * 18 * rig.dt
				if s > L / 2 + 15 then
					s, dir = L / 2 + 15, -1
				elseif s < L / 2 - 15 then
					s, dir = L / 2 - 15, 1
				end
				place(s, 18)
			end)
			local spotted = 0
			for _, a in world.actors do
				if rig.overhead:spotted(a.id, rig.rodent) then
					spotted += 1
				end
			end
			t.truthy(spotted >= 1, `someone pointed it out ({spotted})`)
			place(L / 2, 0)
			rig.step(40, function()
				place(L / 2, 0)
			end)
			local strikes0 = rig.combat:stats().strikes
			local held = {}
			rig.step(20, function()
				place(L / 2, 0)
				for _, a in world.actors do
					local g = rig.combat:guardOf(a.id)
					if a.species == "human" and g and g.aware then
						held[a.id] = a.post
					end
				end
			end)
			local strikes = rig.combat:stats().strikes - strikes0
			local list = {}
			for id, post in held do
				local a = world.actorsById[id]
				table.insert(list, string.format("%d (%s) at %.0f, %.0f", id, post, a.x, a.z))
			end
			print(
				`      40-60 s after it kept still 40 studs up: {#list} held in the duel ({table.concat(list, "; ")}); {strikes} blows swung at it`
			)
			t.eq(#list, 0, "nobody is still squared up to a rodent 40 studs over their head a minute later")
			t.eq(strikes, 0, "and nobody swings at it")
		end
	)

	t.test("the alarm is for the duel: a person who let the rodent go is not alarmed when it comes back", function()
		local P = CombatRules.params()
		local g = Duel.new(P, 7, "calm", CombatRules.nerve(P, 7, "calm"))
		local zero = function(): number
			return 0.99
		end
		local function view(now: number, dist: number, seen: boolean, sneaking: boolean): Duel.View
			return {
				now = now,
				dt = 0.1,
				dist = dist,
				dy = 0,
				seen = seen,
				tell = nil,
				tellFeint = false,
				committed = false,
				recovering = false,
				zigzag = 0,
				boosted = false,
				sneaking = sneaking,
			}
		end
		-- found creeping up 8 studs behind them: alarmed
		Duel.think(P, g, view(0, 8, true, true), zero)
		t.truthy(g.alarmed, "alarmed (the stalk found out)")
		-- it backs off 50 studs (past engage + FLEE_CLEAR for a calm person; the server keeps the Guard to about 64)
		local now = 0
		while now < 30 do
			now += 0.1
			Duel.think(P, g, view(now, 50, false, false), zero)
		end
		t.falsy(g.aware, "the duel is over: they let it go")
		t.falsy(g.alarmed, "and the alarm with it ('ALARMED for the rest of the duel')")
	end)

	t.test("an honest creep is not heard because one duel step saw two steps' move (a frame hitch)", function()
		local function creep(hitch: boolean): (boolean, number)
			local rig = BiteRig.new({ seed = 44, overhead = true })
			rig.step(16)
			local v = rig.calmNear(-80, 0)
			rig.holdRodent()
			local rod = rig.world.actorsById[rig.rodent]
			local function behind(d: number): (number, number)
				return v.x - math.sin(v.yaw) * d, v.z - math.cos(v.yaw) * d
			end
			rig.dt = 0.1
			local d = 30 -- (out of hearing while it is put there)
			local shown = d
			rod.speed = 4.1
			rig.put(rig.rodent, behind(d))
			rig.step(0.3, function()
				rig.put(rig.rodent, behind(shown))
			end)
			local k = 0
			-- 4.1 studs/s, the ground stalk, from 30 to 12 studs behind (outside duel.threat's alarm, inside its hearing)
			while d > 12 do
				d -= 4.1 * rig.dt
				k += 1
				-- (with the hitch: every tenth step the body's position does not arrive, and the next brings both)
				if not (hitch and k % 10 == 5) then
					shown = d
				end
				rig.step(rig.dt, function()
					rig.put(rig.rodent, behind(shown))
				end)
			end
			local g = rig.combat:guardOf(v.id)
			return g ~= nil and g.aware, v.id
		end
		local smooth = creep(false)
		local hitched, id = creep(true)
		print(
			`      person {id}: a smooth creep noticed {smooth}; the same creep with a 0.1 s hitch a second noticed {hitched}`
		)
		t.falsy(smooth, "a smooth creep from behind is not noticed")
		t.falsy(hitched, "nor the same creep when one of its positions arrives a step late")
	end)

	t.test(
		"a squirrel walking to and fro 10.5 studs up, off any route, 5 studs in front of a person is noticed",
		function()
			local rig = BiteRig.new({ seed = 45, overhead = true })
			rig.step(16)
			local v = rig.calmNear(60, 20)
			rig.holdRodent()
			rig.route[rig.rodent] = false -- (standing on a part's top: no route in its packets)
			local rod = rig.world.actorsById[rig.rodent]
			rod.speed = 18
			rig.dt = 0.1
			local side = 0
			local dir = 1
			local function place()
				local fx, fz = math.sin(v.yaw), math.cos(v.yaw)
				local feet = v.y - v.hip
				rod.x = v.x + fx * 5 + fz * side
				rod.z = v.z + fz * 5 - fx * side
				rod.y = feet + 10.5 + rod.hip
			end
			local noticed = false
			rig.step(6, function()
				side += dir * 18 * rig.dt
				if side > 3 then
					side, dir = 3, -1
				elseif side < -3 then
					side, dir = -3, 1
				end
				place()
				local g = rig.combat:guardOf(v.id)
				if (g and g.aware) or rig.overhead:stageOf(v.id) ~= "none" then
					noticed = true
				end
			end)
			print(`      walking 10.5 studs up, 5 in front of person {v.id} for 6 s: noticed {noticed}`)
			t.truthy(noticed, "the duel or the overhead watch notices it")
		end
	)
end
