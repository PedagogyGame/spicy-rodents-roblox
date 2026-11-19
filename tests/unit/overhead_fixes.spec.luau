--!strict
-- The overhead watch's review (19 Nov; its findings H1, M1-M4, L1-L7): the cases it found failing, kept as specs, and
-- the specs of the fixes. Each case says what the game should do.
--   1. A rodent that keeps still on a wire after people have pointed it out does not hold them in the duel for good:
--      the officers who spotted it stand in the road under the wire and swing at it, 40 studs up, as long as it stays.
--   2. "Alarmed for the rest of the duel": once the person has let the rodent go (not aware), the alarm is over too.
--   3. An honest ground creep (4.1 studs/s) is not heard because one of the server's 0.1 s duel steps saw the body's
--      move of two (a phone's frame hitch, positions arriving in a bunch): the duel reads its pace off the root's
--      arrivals, and 2 x 4.1 is over duel.quietSpeed.
--   4. A squirrel walking to and fro 10.5 studs up on something that is not a route (a parked truck's roof, a wall
--      top: the motor stands on any colliding top), 5 studs in front of a person, is noticed by someone: the duel
--      leaves anything over duel.overheadY to the overhead watch, and the overhead watch only counts routes.
--   5. Nobody is sent under a squirrel into the road or into the building it is on: the spot they are sent to is open
--      ground off the asphalt with a clear straight way there (M1); an officer's own order comes first (L6).
--   6. A calm person told to hurry on while walking back to the lane hurries on once there (L3).
--   7. The town's chatter is paced as one (L4): the lines of the bite-to-hospital sequence, the drains and the rafters
--      count in the overhead watch's cap by place, every service shares the per-person cooldown and the town window,
--      on one clock.
--   8. The duel's ear (M2): a creep with late or bunched positions reads as a creep; tapping W reads as walking.
local BiteRig = require("@tests/lib/BiteRig")
local CombatRules = require("@shared/Combat/CombatRules")
local Duel = require("@shared/Combat/Duel")
local Colliders = require("@shared/World/Colliders")
local MedicalRoute = require("@shared/Infection/MedicalRoute")
local OverheadService = require("@server/Stealth/OverheadService")
local Pedestrian = require("@server/Actors/Brains/Pedestrian")
local Officer = require("@server/Actors/Brains/Officer")
local Common = require("@server/Actors/Brains/Common")
local SpeechRules = require("@shared/Speech/SpeechRules")
local AreaPace = require("@shared/Speech/AreaPace")
local Pace = require("@shared/Stealth/Pace")
local DuelSim = require("@tests/lib/DuelSim")

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

	t.test(
		"nobody is sent under a squirrel into the road or into the building it is on (wire 163, the roofs)",
		function()
			local rig = BiteRig.new({ seed = 3, overhead = true })
			rig.step(4)
			local world = rig.world
			local svc = rig.overhead
			local colliders, roads = rig.infection.colliders, rig.infection.roads
			local function open(x: number, z: number): boolean
				return Colliders.pointIn(colliders, x, z, world.ctx.groundAt(x, z) + 3, 1) == nil
					and not MedicalRoute.onRoad(roads, x, z)
			end
			-- someone standing on open ground 8 to 30 studs from (x, z)
			local function standBy(x: number, z: number): any
				local a = rig.near(x, z, "police")
				for r = 8, 30, 2 do
					for k = 0, 15 do
						local px, pz = x + math.cos(k * 0.39) * r, z + math.sin(k * 0.39) * r
						if open(px, pz) then
							rig.put(a.id, px, pz)
							return a
						end
					end
				end
				return nil
			end
			local function check(kind: string, x: number, y: number, z: number): (boolean, boolean)
				local a = standBy(x, z)
				if a == nil then
					return false, true
				end
				local s: any = { id = rig.rodent, x = x, y = y, z = z, speed = 0, held = true, kind = kind }
				local ok = true
				for _, mode in { "approach", "back" } do
					local sx, sz = OverheadService.spotFor(svc, a, s, mode)
					if sx and sz then
						ok = ok
							and open(sx, sz)
							and not Colliders.blocked(colliders, a.x, a.z, sx, sz, 1, world.ctx.groundAt(a.x, a.z) + 3)
					end
					if mode == "approach" and sx == nil then
						return false, ok -- (nowhere to wait by it: nobody is sent)
					end
				end
				return true, ok
			end
			local found, bad = 0, 0
			local pts = world.routes.byId(WIRE).points
			for i = 1, #pts, 5 do
				local p = pts[i]
				local had, ok = check("wire", p[1], p[2] + 0.8, p[3])
				if had then
					found += 1
				end
				if not ok then
					bad += 1
				end
			end
			local roofs, roofFound, roofBad = 0, 0, 0
			for id = 1, world.routes.count do
				local r = world.routes.byId(id)
				if r and r.kind == "roof" and roofs < 12 then
					roofs += 1
					local p = r.points[math.max(1, #r.points // 2)]
					local had, ok = check("roof", p[1], p[2] + 0.8, p[3])
					if had then
						roofFound += 1
					end
					if not ok then
						roofBad += 1
					end
				end
			end
			print(
				`      wire 163: a spot to wait at for {found} of its points (none in the road or a building: {bad} bad); roofs: {roofFound} of {roofs} ({roofBad} bad)`
			)
			t.eq(bad, 0, "no spot by the wire is in the road, in a building or across either")
			t.eq(roofBad, 0, "nor by a roof")
			t.truthy(found >= 5, "there is somewhere to wait by the wire")
			-- (a squirrel in the middle of a roof is out of sight from the ground, OverheadService's edgeSlack: nobody waits)
			t.truthy(roofFound >= 1, "and by a roof whose squirrel shows from below")
		end
	)

	t.test("an officer's own order comes first: the overhead watch does not take over a chase or a stakeout", function()
		local rig = BiteRig.new({ seed = 3, overhead = true })
		rig.step(2)
		local world = rig.world
		local cop = rig.near(0, 0, "police")
		local brain: any = world.brains[cop.id]
		local now = world.now
		brain:onEvent({ type = "respond", x = 500, z = 500, untilTime = now + 30 })
		t.falsy(OverheadService.walkTo(rig.overhead, cop.id, 1, 1, 0, 0, 8, 6), "not over a call")
		t.eq(brain.respondX, 500, "the call stands")
		brain.respondUntil = 0
		brain:onEvent({ type = "stakeout", x = 9, z = 9, faceX = 10, faceZ = 10, secs = 20, mouth = "m" })
		t.falsy(OverheadService.walkTo(rig.overhead, cop.id, 1, 1, 0, 0, 8, 6), "nor over a stakeout")
		brain:onEvent({ type = "stakeoutEnd" })
		t.truthy(OverheadService.walkTo(rig.overhead, cop.id, 1, 1, 0, 0, 8, 6), "free, they come and wait")
		t.eq(brain.respondX, 1)
		local _ = Officer
	end)

	t.test("a calm person told to hurry on while walking back to the lane hurries on once there", function()
		local actor = Common.newActor(1, "human", "default", "Pedestrian", 0, 0, 1.5)
		local brain: any = Pedestrian.new(actor, {
			lanes = Pedestrian.defaultLanes(),
			coreLanes = 4,
			speedMin = 3,
			speedMax = 3,
			rng = function(): number
				return 0.3
			end,
		})
		-- stepped back off the lane (it runs along x at z -12.1): walking back to it
		actor.x, actor.z = 40, -22
		brain:onEvent({ type = "overhead", mode = "back", x = 40, z = -14, speed = 5, untilTime = 0.1 })
		local ctx: any = {
			now = 1,
			rng = function(): number
				return 0.3
			end,
			groundAt = function(): number
				return 0
			end,
			threats = {
				query = function(): number
					return 0
				end,
			},
			actorsById = {},
			queryBuffer = {},
		}
		brain:think(0.1, ctx)
		t.eq(brain.state, "rejoin", "walking back to the lane")
		brain:onEvent({ type = "overhead", mode = "hurry", x = 52, z = -12.1, untilTime = 20 })
		t.eq(brain.hurryUntil, 20, "the hurry is taken")
		actor.x, actor.z = brain.lane.fixed == -12.1 and 40 or 40, brain.lane.fixed
		brain:think(0.1, ctx)
		t.eq(brain.state, "walk")
		local u = if brain.lane.axis == "x" then actor.x else actor.z
		local away = if brain.lane.axis == "x" then 52 else -12.1
		t.truthy((brain.goal - u) * (u - away) > 0, `on along the lane away from it (goal {brain.goal}, at {u})`)
		t.truthy(math.abs(brain.goal - u) > 20, "a good way on")
	end)

	t.test("the town's chatter is paced as one: one cooldown, one window, one cap by place, one clock", function()
		local clock = 100
		local town = SpeechRules.new(nil, {
			area = AreaPace.DEFAULTS,
			clock = function(): number
				return clock
			end,
		})
		local yes = function(): number
			return 0
		end
		-- the sequence (its own clock says 7: the town's says 100) says three lines at a scene, never held back by place
		for id = 1, 3 do
			t.truthy(
				SpeechRules.request(town, 7, id, "witness", yes, { x = 0, z = 0, unpaced = true, force = true }),
				"a scene's line"
			)
		end
		t.eq(town.lastByActor[1], 100, "timed on the town's clock")
		t.falsy(SpeechRules.request(town, 100, 9, "overhead", yes, { x = 300, z = 0 }), "the town window is full")
		-- (past the town window, inside the area's) the overhead watch, by the scene: no room there; another street has
		clock = 106
		t.falsy(SpeechRules.request(town, 106, 10, "overhead", yes, { x = 10, z = 5 }), "the scene's lines count")
		t.truthy(SpeechRules.request(town, 106, 11, "overhead", yes, { x = 300, z = 0 }), "another street is its own")
		-- the same person, from another service, inside the cooldown: refused
		clock = 112
		t.falsy(
			SpeechRules.request(town, 112, 11, "rafters", yes, { x = 900, z = 900, unpaced = true }),
			"one cooldown"
		)
		-- an opener needs room for its answer; the answer counts
		clock = 200
		t.truthy(SpeechRules.request(town, 200, 20, "overheadWary", yes, { x = 0, z = 0, need = 2 }))
		t.truthy(SpeechRules.request(town, 200, 21, "overheadReply", yes, { x = 2, z = 0, force = true }))
		t.eq(AreaPace.count(town.area :: any, 200, 0, 0), 2, "the forced answer is counted")
		t.falsy(SpeechRules.request(town, 200, 22, "overhead", yes, { x = 0, z = 3, need = 2 }), "no room for two more")
	end)

	t.test(
		"the overhead watch's lines keep the town's cap by place: 3 within 40 studs in 10 s, whoever says them",
		function()
			local rig = BiteRig.new({
				seed = 6,
				overhead = true,
				overheadRand = function(): number
					return 0 -- (everyone who may speak does)
				end,
			})
			rig.step(1)
			local svc = rig.overhead
			local people = {}
			local skip = {}
			for i = 1, 6 do
				local a = rig.near(0, 0, nil, skip)
				skip[a.id] = true
				people[i] = a
			end
			local function at(i: number, x: number, z: number)
				local a = people[i]
				a.x, a.z = x, z
			end
			-- five people at one corner, one every two seconds (inside the town window's 3 in 5 s each time)
			local said = 0
			for i = 1, 5 do
				at(i, i * 3, 0)
				if OverheadService.say(svc, people[i].id, "overheadLost") then
					said += 1
				end
				at(i, 5000, 5000) -- (out of the way: the cap is where a line was said)
				rig.step(2)
			end
			t.eq(said, AreaPace.DEFAULTS.max, `{said} lines at one corner within its window`)
			-- another corner meanwhile
			at(6, 400, 0)
			t.truthy(OverheadService.say(svc, people[6].id, "overheadLost"), "another corner is its own")
		end
	)

	t.test("the duel's ear: late or bunched positions leave a creep a creep; tapping W is walking (M2)", function()
		local P = CombatRules.params()
		-- a body's track as the server gets it: `pos(t)` where it really is, sampled every `every` s; a sample `isLate`
		-- names still shows the one before (it arrives with the next); read with Pace.stretch at every sample
		local function loudest(
			pos: (number) -> number,
			every: number,
			secs: number,
			isLate: (number) -> boolean
		): number
			local track: { Pace.Point } = {}
			local most = 0
			local k = 0
			local t0 = 0
			while t0 < secs do
				k += 1
				t0 += every
				local x = if isLate(k) and #track > 0 then track[#track].x else pos(t0)
				table.insert(track, { t = t0, x = x, z = 0 })
				local v = Pace.stretch(function(at: number): (number, number)
					return Pace.along(track, at)
				end, t0, track[1].t)
				if v then
					most = math.max(most, v)
				end
			end
			return most
		end
		local creep = function(at: number): number
			return 4.1 * at
		end
		local never = function(_: number): boolean
			return false
		end
		local hitch = function(k: number): boolean
			return k % 10 == 5
		end
		local bunched = function(k: number): boolean
			return k % 7 == 3 or k % 7 == 4 -- (two packets in a row held back, then all three at once)
		end
		local smooth = loudest(creep, 0.1, 10, never)
		local hitched = loudest(creep, 0.1, 10, hitch)
		local packets = loudest(creep, 0.05, 10, bunched)
		-- tapping W: the walk (18) for 0.18 s, still for 0.23 s: 7.9 studs/s on average
		local tap = function(at: number): number
			local n = math.floor(at / 0.41)
			local r = at - n * 0.41
			return n * 18 * 0.18 + 18 * math.min(r, 0.18)
		end
		local tapped = loudest(tap, 0.05, 10, never)
		print(
			string.format(
				"      the ear: a 4.1 st/s creep reads %.1f smooth, %.1f with a hitch a second, %.1f with packets bunched; tapping W (7.9 on average) reads %.1f",
				smooth,
				hitched,
				packets,
				tapped
			)
		)
		t.truthy(hitched <= P.quietSpeed * 0.8, "a hitch leaves a creep well under the creep line")
		t.truthy(packets <= P.quietSpeed * 0.8, "and so do bunched packets")
		t.truthy(tapped > P.quietSpeed + 1, "tapping W is loud")
		-- in the duel: a stalk by tapping W (DuelSim, calm, 100 ms) is heard
		local function row(o: { [string]: any }): any
			local opts: any = { temper = "calm", rodent = "stalker", seed = 11, lag = 0.1 }
			for k, v in o do
				opts[k] = v
			end
			return DuelSim.batch(200, opts)
		end
		local crept, tapW = row({}), row({ tap = { on = 0.18, off = 0.23 } })
		print(
			string.format(
				"      stalked by a creep: %d %% unaware; by tapping W: %d %% unaware",
				math.floor(crept.unawareRate * 100 + 0.5),
				math.floor(tapW.unawareRate * 100 + 0.5)
			)
		)
		t.truthy(crept.unawareRate >= 0.4, "a creep still often bites unaware")
		t.truthy(tapW.unawareRate <= 0.1, "tapping W almost never does")
	end)
end
