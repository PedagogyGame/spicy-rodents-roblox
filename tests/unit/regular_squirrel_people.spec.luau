--!strict
-- Owner D21 (2026-11-21): "the regular squirrel should not be ran away from by npcs, unless it jumps right on them or
-- at them". On the town as Boot/Game runs it (tests/lib/BiteRig: the real town AI on the real lanes, the fleet, the
-- bite-to-hospital sequence, the duel, the overhead watch) with Server/Wildlife/TownSquirrels stepped as Boot/Game
-- steps it:
--   * the same walk round a townsperson (standing before them, sprinting by, following, walking up to brush them,
--     over their head on a wire) by an ORDINARY squirrel a player holds and by the Spicy Rodent: for the ordinary one
--     nobody runs, nobody is alert, nothing is reported or said in fear, no duel, no officer called, no crowd, and the
--     person keeps walking their lane; for the Spicy Rodent everything is as it was (the numbers pinned);
--   * the rule (Shared/Wildlife/JumpedAt): on them, at them, and everything that is neither;
--   * jumped at: the start (a step back, the arms up, a yelp), once, bounded, then they carry on; never for the Spicy
--     Rodent's leap (that is the duel's), never for someone another service has in hand;
--   * a glance and a friendly word now and then, under the town's speech pacing;
--   * the cost of a frame.
local BiteRig = require("@tests/lib/BiteRig")
local TownAI = require("@server/AI/TownAI")
local TownSquirrels = require("@server/Wildlife/TownSquirrels")
local JumpedAt = require("@shared/Wildlife/JumpedAt")
local Species = require("@shared/Actors/Species")
local Rng = require("@shared/Util/Rng")

local DT = 0.05

-- the fearful situations: a line of any of these is fear, alarm or a call
local FEAR = {
	spotting = true,
	fleeing = true,
	bitten = true,
	witness = true,
	bystander = true,
	overhead = true,
	overheadWire = true,
	overheadFence = true,
	overheadTree = true,
	overheadRoof = true,
	overheadUneasy = true,
	overheadReply = true,
	overheadWary = true,
	overheadLost = true,
	drain = true,
}

type Tally = {
	fled: number, -- people who ran at any moment, from anything
	alert: number, -- people whose alert was raised
	spotted: number, -- "spotted" reports from the brains, of anything
	fledIt: number, -- people who ran from the held squirrel
	spottedIt: number, -- reports of the held squirrel
	fear: number, -- fearful lines said
	guards: number, -- people the duel took on
	officers: number, -- officers sent somewhere
	crowd: number, -- people gathering
	stages: number, -- people the overhead watch had at a stage
	walked: number, -- how far the person the walk is round got (studs)
	states: { [string]: boolean }, -- every state that person's brain was in
}

-- the town with the service on it, the squirrel `variant` held by a player
local function town(variant: string, seed: number?)
	local rig = BiteRig.new({ overhead = true, dt = DT, seed = seed or 3 })
	local world = rig.world
	local id = rig.rodent
	if variant == "normal" then
		for _, a in world.actors do
			if a.species == "squirrel" and a.variant == "normal" then
				id = a.id
				break
			end
		end
	end
	local sq = world.actorsById[id]
	rig.hold(id)
	local air: { [number]: boolean? } = {}
	local rng = Rng.new(11)
	local svc = TownSquirrels.new({
		world = world,
		speech = rig.speech,
		airborne = function(sid: number): boolean?
			return air[sid]
		end,
		busy = function(pid: number): boolean
			return rig.infection:engaged(pid) or rig.combat:guardOf(pid) ~= nil or rig.overhead:stageOf(pid) ~= "none"
		end,
		setAttr = function(pid: number, name: string, value: any)
			rig.setAttr(pid, name, value)
		end,
		gaze = function(pid: number, x: number?, y: number?, z: number?)
			rig.gazes[pid] = if x then { x, y, z } else nil
		end,
		rand = function(): number
			return rng.next()
		end,
	})
	TownAI.setFocus(world, function()
		return { { x = sq.x, z = sq.z } }
	end)
	local spotted, spottedIt = 0, 0
	TownAI.listen(world, function(ev: any)
		if ev.kind == "spotted" then
			spotted += 1
			if ev.other == id then
				spottedIt += 1
			end
		end
	end)
	local function step(secs: number, each: (() -> ())?)
		for _ = 1, math.max(1, math.floor(secs / DT + 0.5)) do
			rig.step(DT, function()
				svc:step(DT)
				if each then
					each()
				end
			end)
		end
	end
	return {
		rig = rig,
		world = world,
		sq = sq,
		id = id,
		air = air,
		svc = svc,
		step = step,
		spotted = function(): (number, number)
			return spotted, spottedIt
		end,
	}
end

-- a walker (no rider) on a long straight stretch, the same in every town of a seed
local function walker(world: any): any
	local best, bestD = nil, math.huge
	for _, a in world.actors do
		local brain = world.brains[a.id]
		if
			a.species == "human"
			and a.post == "townsperson"
			and brain.kind == "Pedestrian"
			and not brain.params.cyclist
		then
			local d = a.x * a.x + a.z * a.z
			if d < bestD then
				best, bestD = a, d
			end
		end
	end
	return best
end

-- the squirrel put somewhere on the ground (or `up` studs over it), at a pace
local function place(T: any, x: number, z: number, speed: number, up: number?)
	local sq = T.sq
	sq.x, sq.z = x, z
	sq.y = T.world.ctx.groundAt(x, z) + sq.hip + (up or 0)
	sq.speed = speed
end

-- The walk round a person: before them, sprinting by, following, up to brush them, over their head. Returns the tally.
local function walkRound(T: any): Tally
	local world, rig, sq = T.world, T.rig, T.sq
	local p = walker(world)
	local brain = world.brains[p.id]
	local tally: Tally = {
		fled = 0,
		alert = 0,
		spotted = 0,
		fledIt = 0,
		spottedIt = 0,
		fear = 0,
		guards = 0,
		officers = 0,
		crowd = 0,
		stages = 0,
		walked = 0,
		states = {},
	}
	local fled: { [number]: boolean } = {}
	local fledIt: { [number]: boolean } = {}
	local alert: { [number]: boolean } = {}
	local guards: { [number]: boolean } = {}
	local officers: { [number]: boolean } = {}
	local crowd: { [number]: boolean } = {}
	local stages: { [number]: boolean } = {}
	local lastX, lastZ = p.x, p.z
	local function watch()
		for _, a in world.actors do
			if a.species == "human" then
				local b = world.brains[a.id] :: any
				if b.state == "flee" then
					fled[a.id] = true
					if b.threat == sq then
						fledIt[a.id] = true
					end
				end
				if b.state == "gather" then
					crowd[a.id] = true
				end
				if a.alert > 0 then
					alert[a.id] = true
				end
				if rig.combat:guardOf(a.id) ~= nil then
					guards[a.id] = true
				end
				if b.kind == "Officer" and ((b.respondUntil or 0) > world.now or b.stakeout ~= nil) then
					officers[a.id] = true
				end
				if rig.overhead:stageOf(a.id) ~= "none" then
					stages[a.id] = true
				end
			end
		end
		tally.states[brain.state] = true
		tally.walked += math.sqrt((p.x - lastX) ^ 2 + (p.z - lastZ) ^ 2)
		lastX, lastZ = p.x, p.z
	end
	local function ahead(d: number, side: number?): (number, number)
		local fx, fz = math.sin(p.yaw), math.cos(p.yaw)
		local s = side or 0
		return p.x + fx * d - fz * s, p.z + fz * d + fx * s
	end
	T.step(1, watch) -- (the town settles)
	-- 1. standing before them, in plain view
	local x, z = ahead(8)
	T.step(4, function()
		place(T, x, z, 0)
		watch()
	end)
	-- 2. sprinting by, three studs to their side, from 40 studs ahead to 40 behind
	local d = 40
	T.step(80 / 33, function()
		d -= 33 * DT
		local sx, sz = ahead(d, 3)
		place(T, sx, sz, 33)
		watch()
	end)
	-- 3. following six studs behind them
	T.step(6, function()
		local sx, sz = ahead(-6)
		place(T, sx, sz, 18)
		watch()
	end)
	-- 4. walking up to them from the front until it brushes them, and staying there
	d = 20
	T.step(5, function()
		d = math.max(1.5, d - 18 * DT)
		local sx, sz = ahead(d)
		place(T, sx, sz, if d > 1.5 then 18 else 0)
		watch()
	end)
	-- 5. over their head on a wire, keeping up with them
	local wire = nil
	for _, r in world.routes.routes do
		if r.kind == "wire" then
			wire = r.id
			break
		end
	end
	rig.route[T.id] = wire
	T.step(8, function()
		place(T, p.x, p.z, 18, 25)
		watch()
	end)
	rig.route[T.id] = nil
	-- ... and gone: the town a little longer
	place(T, p.x + 400, p.z + 400, 0)
	T.step(3, watch)
	local function count(set: { [number]: boolean }): number
		local n = 0
		for _ in set do
			n += 1
		end
		return n
	end
	tally.fled, tally.alert, tally.guards = count(fled), count(alert), count(guards)
	tally.officers, tally.crowd, tally.stages = count(officers), count(crowd), count(stages)
	tally.fledIt = count(fledIt)
	tally.spotted, tally.spottedIt = T.spotted()
	for _, s in rig.said do
		if s.situation and FEAR[s.situation] then
			tally.fear += 1
		end
	end
	return tally
end

-- the Spicy Rodent's walk (walkRound) before owner D21's change, measured on 26c47c8 with this very script
local SPICY = { fledIt = 5, spottedIt = 5, fear = 6, guards = 3, stages = 5 }

return function(t)
	t.test("who is feared: the Spicy Rodent and the infected; an ordinary squirrel is not", function()
		t.falsy(Species.feared({ species = "squirrel", variant = "normal" }))
		t.falsy(Species.feared({ species = "squirrel", variant = "normal", infected = false }))
		t.truthy(Species.feared({ species = "squirrel", variant = "spicy" }))
		t.truthy(Species.feared({ species = "squirrel", variant = "normal", infected = true }))
		t.truthy(Species.feared({ species = "rodent", variant = "normal" }))
		t.falsy(Species.feared({ species = "human", variant = "townsperson", infected = true }), "only squirrels")
		t.falsy(Species.feared({ species = "fox", variant = "fox" }))
	end)

	t.test(
		"an ordinary squirrel before them, sprinting by, following, brushing them, overhead: nobody runs, backs away or calls anyone",
		function()
			local T = town("normal")
			local tally = walkRound(T)
			print(
				`      ordinary: fled {tally.fled}, alert {tally.alert}, reports {tally.spotted}, fearful lines {tally.fear}, duel {tally.guards}, officers {tally.officers}, crowd {tally.crowd}, overhead stages {tally.stages}; the person walked {math.floor(
					tally.walked
				)} studs`
			)
			t.eq(tally.fled, 0, "nobody runs")
			t.eq(tally.alert, 0, "nobody is alert")
			t.eq(tally.spotted, 0, "nothing is reported")
			t.eq(tally.fear, 0, "no fearful line, no alarm, no call")
			t.eq(tally.guards, 0, "no duel")
			t.eq(tally.officers, 0, "no officer sent")
			t.eq(tally.crowd, 0, "no crowd")
			t.eq(tally.stages, 0, "the overhead watch leaves it be")
			t.deepEq(tally.states, { walk = true }, "the person only ever walks their lane")
			t.truthy(tally.walked > 40, `and keeps walking ({tally.walked} studs in 30 s)`)
			t.eq(T.svc:stats().starts, 0, "and nobody starts: it never jumped")
			for _, s in T.rig.said do
				t.eq(s.situation, "squirrelNear", `the only words are friendly ones ({s.line})`)
			end
		end
	)

	t.test("the Spicy Rodent on the same walk: everything as it was", function()
		local T = town("spicy")
		local tally = walkRound(T)
		print(
			`      spicy: fled from it {tally.fledIt} (from anything {tally.fled}), reports of it {tally.spottedIt}, fearful lines {tally.fear}, duel {tally.guards}, officers {tally.officers}, crowd {tally.crowd}, overhead stages {tally.stages}`
		)
		-- (the numbers of this walk before owner D21's change, measured on 26c47c8 with this very script)
		t.eq(tally.fledIt, SPICY.fledIt, "people who ran from it")
		t.eq(tally.spottedIt, SPICY.spottedIt, "reports of it")
		t.eq(tally.fear, SPICY.fear)
		t.eq(tally.guards, SPICY.guards)
		t.eq(tally.stages, SPICY.stages)
		t.truthy(
			tally.fledIt >= 1 and tally.fear >= 1 and tally.guards >= 1,
			"people run from it, say so and square up"
		)
		-- (before the change one more person ran in this town: from one of the computer's ordinary squirrels)
		t.eq(tally.fled, tally.fledIt, "and from nothing else")
		t.eq(T.svc:stats().starts, 0, "TownSquirrels has nothing to do with the rodent")
		t.eq(T.svc:stats().glances, 0)
	end)

	t.test("the rule: on them, at them, and what is neither (Shared/Wildlife/JumpedAt)", function()
		local C = JumpedAt.C
		t.near(C.on, 1.125 + 0.8 + 0.5, 1e-9, "on: the two bodies' radii and half a stud")
		t.near(C.short, 1.125 + 0.8 + 3.5, 1e-9, "short: the radii and 3.5 studs")
		-- a person at the origin, feet at 0; a leap launched 12 studs west of them
		local function flight(x: number, y: number, z: number, lx: number?, ly: number?, lz: number?)
			local f = JumpedAt.launch(lx or -12, ly or 0, lz or 0)
			JumpedAt.advance(f, x, y, z)
			return f
		end
		-- ON them
		t.truthy(JumpedAt.passes(flight(-3, 3, 0), -0.5, 1, 0, 0, 0, 0), "comes down onto them")
		t.truthy(JumpedAt.passes(flight(-4, 4, 1), 4, 4, 1, 0, 0, 0), "flies past their ear, a stud to the side")
		t.truthy(JumpedAt.passes(flight(0.5, 12, 0), 0.5, 5, 0, 0, 0, 0), "drops onto their head from a branch")
		t.falsy(JumpedAt.passes(flight(0.5, 20, 0), 0.5, 12, 0, 0, 0, 0), "... still well over their head")
		t.falsy(JumpedAt.passes(flight(-4, 2, 3), 4, 2, 3, 0, 0, 0), "goes by three studs to the side")
		t.falsy(JumpedAt.passes(flight(-4, 20, 0), 4, 20, 0, 0, 0, 0), "crosses over their head, wire to wire")
		t.falsy(JumpedAt.passes(flight(1, 0, 0), 1, 3, 0, 0, 0, 0), "hops on the spot at their feet")
		t.falsy(JumpedAt.passes(flight(1, 0, 0), 6, 3, 0, 0, 0, 0), "leaps away from beside them")
		-- AT them: the landing
		t.truthy(JumpedAt.lands(flight(-6, 3, 0), -4, 0, 0, 0, 0, 0), "lands four studs short, straight at them")
		t.falsy(JumpedAt.lands(flight(-8, 3, 0), -6, 0, 0, 0, 0, 0), "lands six studs short")
		t.falsy(JumpedAt.lands(flight(-6, 3, 2), -4, 0, 3, 0, 0, 0), "lands near, but its line passes four studs aside")
		t.falsy(JumpedAt.lands(flight(-5, 1, 0, -5, 0, 0), -4, 0, 0, 0, 0, 0), "a one-stud hop beside them")
		t.falsy(JumpedAt.lands(flight(2, 9, 0), 4, 0, 0, 0, 0, 0), "comes down beyond them (it went over)")
		t.falsy(JumpedAt.lands(flight(-6, 14, 0), -4, 12, 0, 0, 0, 0), "lands on a roof edge over them")
		-- the caps
		local book = JumpedAt.newBook()
		t.truthy(JumpedAt.allow(book, "p1", "s", 0))
		t.falsy(JumpedAt.allow(book, "p1", "s", 5), "the same person: not within 20 s")
		t.falsy(JumpedAt.allow(book, "p1", "other", 19.9), "whichever squirrel")
		t.truthy(JumpedAt.allow(book, "p2", "s", 1))
		t.truthy(JumpedAt.allow(book, "p3", "s", 2))
		t.falsy(JumpedAt.allow(book, "p4", "s", 3), "a squirrel makes three people start in 10 s, no more")
		t.truthy(JumpedAt.allow(book, "p4", "other", 3), "another squirrel is another matter")
		t.truthy(JumpedAt.allow(book, "p5", "s", 10.5), "... once the first has slid out of the window")
		t.truthy(JumpedAt.allow(book, "p1", "s", 20.5), "and the first person again after 20 s")
	end)

	t.test("the leap is the server's: a motor packet's word (TownSquirrels.airborne)", function()
		t.eq(TownSquirrels.airborne({ grounded = true, routeId = -1 }, 0.05), false, "on its feet")
		t.eq(TownSquirrels.airborne({ grounded = false, routeId = 12 }, 0.05), false, "on a rail")
		t.eq(TownSquirrels.airborne({ grounded = false, routeId = -1 }, 0.05), true, "off its feet and off every rail")
		t.eq(TownSquirrels.airborne({ grounded = false, routeId = -1 }, 0.6), nil, "a stale packet says nothing")
		t.eq(TownSquirrels.airborne(nil, nil), nil, "no packet yet")
	end)

	-- A leap of the held squirrel from (x0, z0) to (x1, z1) in `secs`, `top` studs high in the middle, `up` studs over
	-- the ground throughout: the server's places at the packets' pace, in the air until it lands.
	local function leap(
		T: any,
		x0: number,
		z0: number,
		x1: number,
		z1: number,
		secs: number?,
		top: number?,
		up: number?
	)
		local n = math.max(2, math.floor((secs or 0.5) / DT + 0.5))
		place(T, x0, z0, 0, up)
		T.air[T.id] = false
		T.step(DT)
		for i = 1, n - 1 do
			local u = i / n
			T.air[T.id] = true
			place(T, x0 + (x1 - x0) * u, z0 + (z1 - z0) * u, 30, (up or 0) + 4 * (top or 5) * u * (1 - u))
			T.step(DT)
		end
		T.air[T.id] = false
		place(T, x1, z1, 0, up)
		T.step(DT)
	end
	local function ahead(p: any, d: number, side: number?): (number, number)
		local fx, fz = math.sin(p.yaw), math.cos(p.yaw)
		local s = side or 0
		return p.x + fx * d - fz * s, p.z + fz * d + fx * s
	end
	local function saidBy(rig: any, pid: number, situation: string): number
		local n = 0
		for _, s in rig.said do
			if s.id == pid and s.situation == situation then
				n += 1
			end
		end
		return n
	end

	t.test("jumped right on: a step back, the arms up, a yelp, then on their way; once in 20 s", function()
		local T = town("normal")
		local world, rig = T.world, T.rig
		local p = walker(world)
		local brain = world.brains[p.id]
		T.step(1)
		local lane = brain.lane
		local x0, z0 = ahead(p, 12)
		-- (how far along their way they are, every frame: the steps back show as a retreat)
		local px, pz, fx, fz = p.x, p.z, math.sin(p.yaw), math.cos(p.yaw)
		local far, back = 0, 0
		local function track()
			local along = (p.x - px) * fx + (p.z - pz) * fz
			far = math.max(far, along)
			back = math.max(back, far - along)
		end
		leap(T, x0, z0, p.x, p.z)
		track()
		t.eq(T.svc:stats().starts, 1, "they start")
		t.eq(T.svc:stats().leaps, 1)
		t.eq(rig.attrs[p.id].Gesture, "flinch", "the arms come up")
		t.eq(saidBy(rig, p.id, "jumpedAt"), 1, "a yelp")
		t.eq(brain.state, "duel")
		t.eq(brain.duelSource, "startle", "the quick steps away")
		t.eq(p.alert, 0, "no alert")
		-- the steps away from it: a few studs, no more
		T.step(0.7, track)
		t.truthy(back > 1.5 and back < 5, `a couple of quick steps back ({back} studs)`)
		T.step(0.3)
		t.eq(rig.attrs[p.id].Gesture, nil, "the arms are down again within a second")
		-- then they carry on: back on their lane, walking, as if nothing happened
		local walking = false
		local fled = false
		for _ = 1, 160 do
			T.step(DT)
			fled = fled or brain.state == "flee"
			if brain.state == "walk" then
				walking = true
				break
			end
		end
		t.truthy(walking, "walking again within 8 s")
		t.falsy(fled, "never a flight")
		t.eq(brain.lane, lane, "on the lane they were on")
		t.eq(T.spotted(), 0, "nothing reported")
		t.eq(p.alert, 0)
		for _, s in rig.said do
			t.truthy(s.situation == "jumpedAt" or s.situation == "squirrelNear", `no fearful word ({s.line})`)
		end
		for _, a in world.actors do
			if a.species == "human" then
				local b = world.brains[a.id] :: any
				t.truthy(b.state ~= "flee" and b.state ~= "gather", "nobody else minds")
				t.eq(rig.combat:guardOf(a.id), nil, "no duel")
			end
		end
		-- again two seconds later: nothing (one start a person in 20 s)
		x0, z0 = ahead(p, 12)
		leap(T, x0, z0, p.x, p.z)
		t.eq(T.svc:stats().starts, 1, "not again so soon")
		t.eq(brain.state, "walk")
		t.eq(saidBy(rig, p.id, "jumpedAt"), 1)
		-- ... and after the 20 s, again
		T.step(21)
		x0, z0 = ahead(p, 12)
		leap(T, x0, z0, p.x, p.z)
		t.eq(T.svc:stats().starts, 2, "after 20 s they start again")
	end)

	t.test(
		"at them or not: a landing short and aimed is; a leap past, a leap overhead and a run into them are not",
		function()
			local T = town("normal")
			local world = T.world
			local p = walker(world)
			T.step(1)
			-- past them, four studs to the side
			local x0, z0 = ahead(p, 12, 4)
			local x1, z1 = ahead(p, -8, 4)
			leap(T, x0, z0, x1, z1)
			t.eq(T.svc:stats().starts, 0, "a leap past them, four studs to the side")
			-- over their head, wire to wire
			x0, z0 = ahead(p, 12)
			x1, z1 = ahead(p, -12)
			leap(T, x0, z0, x1, z1, 0.6, 3, 25)
			t.eq(T.svc:stats().starts, 0, "a leap 25 studs over their head")
			-- running into them, never off its feet
			x0, z0 = ahead(p, 12)
			for i = 1, 10 do
				local u = i / 10
				place(T, x0 + (p.x - x0) * u, z0 + (p.z - z0) * u, 33)
				T.step(DT)
			end
			t.eq(T.svc:stats().starts, 0, "a sprint straight into them")
			t.eq(T.svc:stats().leaps, 2, "(two leaps were followed)")
			-- landing short of them, aimed at them
			place(T, p.x + 300, p.z, 0)
			T.step(0.5)
			x0, z0 = ahead(p, 14)
			x1, z1 = ahead(p, 4.5)
			leap(T, x0, z0, x1, z1, 0.4)
			t.eq(T.svc:stats().starts, 1, "a leap that lands about four studs before their feet")
			t.eq(world.brains[p.id].duelSource, "startle")
		end
	)

	t.test("bounded: a squirrel bouncing from person to person leaves three starts in ten seconds", function()
		local T = town("normal")
		local world = T.world
		T.step(1)
		local people = {}
		for _, a in world.actors do
			local b = world.brains[a.id] :: any
			if a.species == "human" and b.kind == "Pedestrian" and not b.params.cyclist and #people < 6 then
				table.insert(people, a)
			end
		end
		t.eq(#people, 6)
		local t0 = world.now
		for _, p in people do
			local x0, z0 = ahead(p, 10)
			leap(T, x0, z0, p.x, p.z, 0.4)
		end
		t.truthy(world.now - t0 < 10, "(inside ten seconds)")
		t.eq(T.svc:stats().starts, 3, "three people started, the rest did not")
		t.eq(T.svc:stats().leaps, 6)
		local fled = 0
		for _, a in world.actors do
			if a.species == "human" and (world.brains[a.id] :: any).state == "flee" then
				fled += 1
			end
		end
		t.eq(fled, 0, "and nobody ran")
		t.eq(T.spotted(), 0)
	end)

	t.test(
		"riders ride on, staff pause, someone in other hands is left alone; the rodent's leap is not this",
		function()
			local T = town("normal")
			local world, rig = T.world, T.rig
			T.step(1)
			local rider, staff = nil, nil
			for _, a in world.actors do
				local b = world.brains[a.id] :: any
				if a.species == "human" and b.kind == "Pedestrian" and b.params.cyclist and rider == nil then
					rider = a
				elseif a.species == "human" and b.kind == "Staff" and a.post == "shop_worker" and staff == nil then
					staff = a
				end
			end
			t.truthy(rider ~= nil and staff ~= nil)
			local rb = world.brains[rider.id] :: any
			local x0, z0 = ahead(rider, 10)
			leap(T, x0, z0, rider.x, rider.z, 0.4)
			t.eq(T.svc:stats().starts, 1)
			t.eq(rig.attrs[rider.id].Gesture, "flinch")
			t.eq(saidBy(rig, rider.id, "jumpedAt"), 1, "the rider yelps")
			t.eq(rb.state, "walk", "and rides on")
			local sb = world.brains[staff.id] :: any
			x0, z0 = ahead(staff, 8)
			leap(T, x0, z0, staff.x, staff.z, 0.4)
			t.eq(T.svc:stats().starts, 2)
			t.truthy(sb.pause > 0, "a member of staff stops a moment")
			-- someone in other hands (here: a patient of the bite-to-hospital sequence)
			local p = walker(world)
			rig.infection:bite(p.id, rig.rodent, "rodentPlayer")
			T.step(0.2)
			x0, z0 = ahead(p, 10)
			leap(T, x0, z0, p.x, p.z, 0.4)
			t.eq(T.svc:stats().starts, 2, "a bitten person has other things on their mind")
			t.eq(saidBy(rig, p.id, "jumpedAt"), 0)
			-- the Spicy Rodent leaping on someone: the duel's business, never a start
			local S = town("spicy")
			S.step(1)
			local q = walker(S.world)
			x0, z0 = ahead(q, 10)
			leap(S, x0, z0, q.x, q.z, 0.4)
			t.eq(S.svc:stats().starts, 0)
			t.eq(S.svc:stats().leaps, 0, "its leaps are not even followed")
			t.eq(saidBy(S.rig, q.id, "jumpedAt"), 0)
			-- ... nor an infected squirrel's
			local I = town("normal")
			I.sq.infected = true
			I.step(1)
			q = walker(I.world)
			x0, z0 = ahead(q, 10)
			leap(I, x0, z0, q.x, q.z, 0.4)
			t.eq(I.svc:stats().starts, 0, "an infected squirrel is feared, not started at")
		end
	)

	t.test("a glance and a friendly word now and then, and they keep walking; stop() takes everything back", function()
		local T = town("normal")
		local world, rig = T.world, T.rig
		local p = walker(world)
		local brain = world.brains[p.id]
		T.step(1)
		local gazed, longest, run = 0, 0, 0
		local states: { [string]: boolean } = {}
		T.step(120, function()
			local x, z = ahead(p, 6)
			place(T, x, z, 6)
			if rig.gazes[p.id] then
				run += DT
				longest = math.max(longest, run)
			else
				if run > 0 then
					gazed += 1
				end
				run = 0
			end
			states[brain.state] = true
		end)
		local st = T.svc:stats()
		print(
			`      two minutes with a squirrel six studs ahead: {gazed} glances by that person, {st.words} words in town`
		)
		t.truthy(gazed >= 2 and gazed <= 12, `a glance now and then ({gazed} in two minutes)`)
		t.truthy(longest <= 1.5 + 2 * DT, `each a moment ({longest} s)`)
		local words = saidBy(rig, p.id, "squirrelNear")
		t.truthy(words <= 3, `a word at most every 45 s ({words})`)
		t.truthy(st.words >= 1, "someone said something friendly")
		t.deepEq(states, { walk = true }, "walking all the while")
		t.eq(p.alert, 0)
		for _, s in rig.said do
			t.eq(s.situation, "squirrelNear", s.line)
		end
		-- the gaze is at the squirrel
		local g = nil
		T.step(60, function()
			local x, z = ahead(p, 6)
			place(T, x, z, 6)
			g = g or rig.gazes[p.id]
		end)
		t.truthy(g ~= nil)
		t.truthy(math.abs(g[2] - (T.sq.y - T.sq.hip + TownSquirrels.C.eye)) < 3, "at the squirrel's height")
		-- stop: nothing left on any body
		local x0, z0 = ahead(p, 10)
		leap(T, x0, z0, p.x, p.z, 0.4)
		T.svc:stop()
		for id, attrs in rig.attrs do
			t.eq(attrs.Gesture, nil, `Gesture left on {id}`)
		end
		for id in rig.gazes do
			if (rig.overhead:stageOf(id)) == "none" then
				t.eq(rig.gazes[id], nil)
			end
		end
	end)

	t.test(
		"cost: nothing to speak of without a leap; a leap through a street is a few hundredths of a millisecond",
		function()
			local T = town("normal")
			local world = T.world
			local p = walker(world)
			T.step(1)
			place(T, p.x + 30, p.z, 0)
			T.air[T.id] = false
			local n = 2000
			local t0 = os.clock()
			for _ = 1, n do
				T.svc:step(1 / 60)
			end
			local idle = (os.clock() - t0) * 1000 / n
			T.air[T.id] = true
			t0 = os.clock()
			for i = 1, n do
				place(T, p.x + 30 - i * 0.01, p.z, 30, 3)
				T.svc:step(1 / 60)
			end
			local inAir = (os.clock() - t0) * 1000 / n
			print(
				`      TownSquirrels.step: {idle} ms a frame on the ground, {inAir} ms in a leap ({#world.actors} actors)`
			)
			t.truthy(idle < 0.05, `idle {idle} ms`)
			t.truthy(inAir < 0.2, `in a leap {inAir} ms`)
		end
	)
end
