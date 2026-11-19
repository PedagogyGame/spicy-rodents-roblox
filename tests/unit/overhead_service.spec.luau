--!strict
-- Server/Stealth/OverheadService on the town as Boot/Game runs it (tests/lib/BiteRig with the overhead watch: the real
-- town AI, its 80 people on the real lanes, the real wires, the duel asking who has spotted the rodent overhead). Owner
-- playtest 2026-11-19: "awareness and discussion and chatter, if i (spicy rodent) am prowling and stalking from above on
-- a powerline or branch etc."
--   * the headless sim (seed 2, with three townspeople talking on the corner under the wire: since the lanes were cut
--     where buildings stand on them, who happens to walk under it differs, so the test puts the people it counts on
--     there): the player's rodent walks a powerline 42 studs over the busiest crossing for a minute: it draws
--     looks, pointing and chatter (two-person exchanges among it), and its own eye fills; creeping along the same wire
--     for a minute, lingering over whoever passes under it (as a stalking player does), it draws uneasy glances and
--     murmurs ("Did you hear something?") and is pointed out rarely (the numbers are printed);
--   * the stages on the bodies: a head turns up (Gaze) before an arm points (Gesture);
--   * the chatter caps: no one says two lines within the per-person cooldown (but an answer, which is forced), no more
--     than AreaPace's lines in an area's window, no line twice running, and every answer follows a line from someone
--     near it a moment before;
--   * the duel: a person who pointed the rodent out overhead meets it aware when it comes down; a rodent that creeps up
--     behind someone bites them unaware; one that runs straight at them is noticed first;
--   * the cost: a tick with 60 people round the rodent, under budget.
local BiteRig = require("@tests/lib/BiteRig")
local OverheadService = require("@server/Stealth/OverheadService")
local SpeechRules = require("@shared/Speech/SpeechRules")
local AreaPace = require("@shared/Speech/AreaPace")
local Lines = require("@shared/Speech/Lines")

local WIRE = 163 -- an east-side utility wire over the town's busiest crossing (x 41, z -41 to 41; 42 studs up)
-- the group on the corner by the wire's foot (rigWithLog), and where they stand facing
local GROUP = { { 33, -36 }, { 36, -33 }, { 33, -30 } }
local GROUP_AT = { 35, -34 }
local SECS = 60
local OVERHEAD = {
	overhead = true,
	overheadWire = true,
	overheadFence = true,
	overheadTree = true,
	overheadRoof = true,
	overheadUneasy = true,
	overheadReply = true,
	overheadWary = true,
	overheadLost = true,
}
-- the openers (an answer follows one of these)
local OPENERS = {
	overhead = true,
	overheadWire = true,
	overheadFence = true,
	overheadTree = true,
	overheadRoof = true,
	overheadWary = true,
}

type Log = { t: number, id: number, what: string, value: any, x: number?, z: number? }

-- the rodent held by a player on the wire at `speed` studs/s for `secs`: back and forth along it, or (`prowl`) as a
-- stalking player does, along it to over the nearest townsperson within PROWL studs of it, lingering over them
local PROWL = 40
local function onWire(rig: any, speed: number, secs: number, each: (() -> ())?, prowl: boolean?)
	local world = rig.world
	local r = world.routes.byId(WIRE)
	local pts = r.points
	local cum = { 0 }
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		cum[i] = cum[i - 1] + math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
	end
	local L = cum[#cum]
	rig.holdRodent()
	rig.route[rig.rodent] = WIRE
	local rod = world.actorsById[rig.rodent]
	local s, dir = 0, 1
	local function place()
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
	end
	place()
	rig.step(secs, function()
		local goal: number? = nil
		if prowl then
			local bestD = PROWL
			for _, a in world.actors do
				if a.species == "human" and a.post == "townsperson" and not rig.players[a.id] then
					for i = 1, #pts do
						local d = math.sqrt((pts[i][1] - a.x) ^ 2 + (pts[i][3] - a.z) ^ 2)
						if d < bestD then
							bestD, goal = d, cum[i]
						end
					end
				end
			end
		end
		if goal then
			s += math.clamp(goal - s, -speed * rig.dt, speed * rig.dt)
		else
			s += dir * speed * rig.dt
			if s > L then
				s, dir = L, -1
			elseif s < 0 then
				s, dir = 0, 1
			end
		end
		place()
		if each then
			each()
		end
	end)
end

-- a rig with the overhead watch, its heads and arms logged
local function rigWithLog(seed: number): (any, { Log })
	local rig = BiteRig.new({ seed = seed, overhead = true })
	local log: { Log } = {}
	local svc = rig.overhead
	local gaze, setAttr = svc.opts.gaze, svc.opts.setAttr
	svc.opts.gaze = function(id: number, x: number?, y: number?, z: number?)
		table.insert(log, { t = rig.time, id = id, what = "Gaze", value = x })
		gaze(id, x, y, z)
	end
	svc.opts.setAttr = function(id: number, name: string, value: any)
		local a = rig.world.actorsById[id]
		table.insert(log, { t = rig.time, id = id, what = name, value = value, x = a and a.x, z = a and a.z })
		setAttr(id, name, value)
	end
	rig.step(20)
	-- three townspeople talking on the corner under the wire (who happens to walk by depends on where the lanes run:
	-- the test puts a few people it can count on there)
	local used: { [number]: boolean } = {}
	for _, q in GROUP do
		local a = rig.calmNear(q[1], q[2], used)
		if a then
			used[a.id] = true
			rig.hold(a.id)
			rig.put(a.id, q[1], q[2])
			rig.let(a.id)
			local brain = rig.world.brains[a.id] :: any
			brain:onEvent({ type = "gather", x = GROUP_AT[1], z = GROUP_AT[2], untilTime = rig.world.now + 200 })
		end
	end
	return rig, log
end

-- the most lines inside AreaPace's radius and window at any opener (a line that is not a forced answer), counting it:
-- every line where and when it was said (Say entries of a Log with positions)
local function worstArea(log: { Log }): (number, number)
	local P = AreaPace.DEFAULTS
	local lines: { Log } = {}
	for _, e in log do
		if e.what == "Say" and e.x and e.z then
			table.insert(lines, e)
		end
	end
	local worst = 0
	for _, s in lines do
		if table.find(Lines.GROUPS.overheadReply, s.value) then
			continue -- (forced: it was made room for by its opener)
		end
		local before = 0
		for _, o in lines do
			if
				o ~= s
				and o.t <= s.t
				and s.t - o.t < P.window
				and ((o.x :: number) - (s.x :: number)) ^ 2 + ((o.z :: number) - (s.z :: number)) ^ 2 <= P.radius * P.radius
			then
				before += 1
			end
		end
		worst = math.max(worst, before + 1)
	end
	return worst, #lines
end

local function count(t: { [any]: any }): number
	local n = 0
	for _ in t do
		n += 1
	end
	return n
end

return function(t)
	local walk: any, walkLog: { Log } = nil, {}
	local walkSpotters: { [number]: boolean } = {}

	t.test(
		"a rodent walking a powerline over a busy street draws looks and chatter; prowling at a creep, uneasy glances and murmurs, rarely pointed out",
		function()
			local rows = {}
			for _, mode in { { name = "walk", speed = 18 }, { name = "creep", speed = 3, prowl = true } } do
				local rig, log = rigWithLog(2)
				local eye = 0
				local spotters: { [number]: boolean } = {}
				onWire(rig, mode.speed, SECS, function()
					local e = rig.eye[rig.rodent]
					if e then
						eye = math.max(eye, e.meter)
					end
					for id, tr in rig.overhead.watch.tracks do
						if tr.stage == 4 then
							spotters[id] = true
						end
					end
				end, mode.prowl)
				local st = rig.overhead:stats()
				local lines = 0
				for _, said in rig.said do
					if OVERHEAD[said.situation or ""] then
						lines += 1
					end
				end
				rows[mode.name] = { st = st, eye = eye, spotters = count(spotters), lines = lines }
				print(
					string.format(
						"      %s along the wire for %d s: %d glances, %d stop and look, %d point it out (%d people), %d exchanges, %d wary, %d lost; %d lines, %d of them uneasy murmurs (%d held back by the caps); the rodent's eye up to %.2f; a busy tick %.3f ms on average, %.3f at worst; Gaze %.1f writes a second",
						mode.name,
						SECS,
						st.glances,
						st.looks,
						st.spots,
						count(spotters),
						st.exchanges,
						st.wary,
						st.lost,
						lines,
						st.uneasy,
						st.refused,
						eye,
						st.busyMs / math.max(1, st.busyTicks),
						st.peakMs,
						st.gazeWrites / SECS
					)
				)
				if mode.name == "walk" then
					walk, walkLog, walkSpotters = rig, log, spotters
				end
			end
			local w, c = rows.walk, rows.creep
			t.truthy(w.st.glances >= 8, `walking draws looks: {w.st.glances}`)
			t.truthy(w.spotters >= 3, `walking is pointed out: {w.spotters} people`)
			t.truthy(w.lines >= 4, `and talked about: {w.lines} lines`)
			t.truthy(w.st.exchanges >= 1, "with a two-person exchange")
			t.truthy(w.eye >= 0.99, "the walking rodent's eye fills")
			-- creeping (prowling over people): uneasy glances and murmurs, rarely pointed out
			t.truthy(c.st.glances >= 2 and c.st.glances <= 12, `creeping draws uneasy glances: {c.st.glances}`)
			t.truthy(c.st.uneasy >= 1, `and murmurs: {c.st.uneasy}`)
			t.truthy(c.spotters <= 1, `creeping is pointed out rarely: {c.spotters} people`)
			t.truthy(c.eye >= 0.3, `the creeping rodent's eye rises: {c.eye}`)
			t.truthy(w.st.spots >= 3 * math.max(1, c.st.spots), "creeping is clearly the better stealth")
		end
	)

	t.test("the stages on the bodies: a head turns up before an arm points; the arm comes down again", function()
		t.truthy(walk ~= nil, "the walk ran")
		local firstGaze: { [number]: number } = {}
		local points = 0
		for _, e in walkLog do
			if e.what == "Gaze" and e.value ~= nil and firstGaze[e.id] == nil then
				firstGaze[e.id] = e.t
			elseif e.what == "Gesture" and e.value == "point" then
				points += 1
				t.truthy(firstGaze[e.id] ~= nil and firstGaze[e.id] <= e.t, `person {e.id} pointed before looking up`)
			end
		end
		t.truthy(points >= 3, `{points} people pointed`)
		local up: { [number]: boolean } = {}
		for _, e in walkLog do
			if e.what == "Gesture" then
				up[e.id] = e.value ~= nil
			end
		end
		for id, isUp in up do
			t.falsy(isUp and walk.overhead.gestures[id] == nil, `person {id}'s arm stays up untimed`)
		end
	end)

	t.test(
		"the chatter caps: per person, per area, no repeats; every answer follows someone near a moment before",
		function()
			local said = {}
			for _, s in walk.said do
				if OVERHEAD[s.situation or ""] then
					table.insert(said, s)
				end
			end
			t.truthy(#said >= 4)
			local cooldown = SpeechRules.defaults().actorCooldown
			local lastBy: { [number]: number } = {}
			local actors = walk.world.actorsById
			for i, s in said do
				-- (an answer is forced: it waits only SpeechRules' one-second floor)
				local gap = if s.situation == "overheadReply" then 1 else cooldown
				if lastBy[s.id] then
					t.truthy(s.t - lastBy[s.id] >= gap - 1e-6, `person {s.id} spoke twice within {gap} s`)
				end
				lastBy[s.id] = s.t
				if i > 1 then
					t.neq(s.line, said[i - 1].line, "the same line twice running")
				end
				-- the area cap
				local a = actors[s.id]
				local near = 0
				for _, o in said do
					local b = actors[o.id]
					if
						o.t <= s.t
						and s.t - o.t < AreaPace.DEFAULTS.window
						and (a.x - b.x) ^ 2 + (a.z - b.z) ^ 2 <= (AreaPace.DEFAULTS.radius + 20) ^ 2
					then
						near += 1
					end
				end
				t.truthy(near <= AreaPace.DEFAULTS.max + 1, `{near} lines round {s.id} within the window`)
				-- (strictly, where each was said: an opener found room for itself, and its answer, under the cap)
				if s.situation == "overheadReply" then
					local opener = false
					for _, o in said do
						if o.id ~= s.id and OPENERS[o.situation or ""] and s.t - o.t > 0 and s.t - o.t <= 3 then
							opener = true
						end
					end
					t.truthy(opener, "an answer follows a line from someone a moment before")
				end
			end
		end
	)

	t.test("the area cap, where each line was said: no opener over AreaPace's max in its radius and window", function()
		-- (review L7: a cap of 30 passed the test above; this one counts every line where and when it was said)
		local P = AreaPace.DEFAULTS
		local worst, n = worstArea(walkLog)
		t.truthy(n >= 4, `{n} lines`)
		print(
			`      the area cap on the street: at most {worst} lines within {P.radius} studs in {P.window} s by an opener`
		)
		t.truthy(worst <= P.max, `{worst} lines in one area's window (cap {P.max})`)
	end)

	t.test("the duel: whoever pointed it out overhead meets it aware when it comes down", function()
		local spotter: number? = nil
		-- (someone the duel runs for: a townsperson or an officer, not a cyclist)
		local function fights(id: number): boolean
			local post = walk.world.actorsById[id].post
			return post == "townsperson" or post == "police"
		end
		for id in walkSpotters do
			if fights(id) and walk.overhead:spotted(id, walk.rodent) and walk.combat:temperOf(id) == "calm" then
				spotter = id
				break
			end
		end
		if spotter == nil then
			-- (point it out by hand: the duel reads the same call)
			for id in walkSpotters do
				if fights(id) then
					spotter = id
					break
				end
			end
		end
		t.truthy(spotter ~= nil, "someone spotted it")
		local p = walk.world.actorsById[spotter :: number]
		walk.overhead.opts.motorOf = function(): any
			return { routeId = nil }
		end
		-- down behind them, quite still (the ground's own perception would not see it there)
		local bx, bz = p.x - math.sin(p.yaw) * 9, p.z - math.cos(p.yaw) * 9
		walk.put(walk.rodent, bx, bz)
		local spottedNow = walk.overhead:spotted(spotter, walk.rodent)
		walk.step(0.4, function()
			walk.put(walk.rodent, bx, bz)
		end)
		local g = walk.combat:guardOf(spotter :: number)
		if spottedNow then
			t.truthy(g ~= nil and g.aware, "the one who pointed it out is aware of it")
		end
	end)

	t.test("the duel: a creep up behind someone bites them unaware; a run straight at them is noticed first", function()
		local stalked, ran = 0, 0
		local cases = 10
		for case = 1, cases do
			-- every bite that is not on someone unaware fails (0.9 is above every other phase's chance)
			local rig = BiteRig.new({
				seed = 40 + case,
				overhead = true,
				biteRand = function(): number
					return 0.9
				end,
			})
			rig.step(15 + case)
			local v = rig.calmNear(case * 60 - 200, 0)
			rig.holdRodent()
			-- 30 studs behind them, creeping in (4 studs/s: the ground stalk) to 8 studs, then the pounce
			local function behind(d: number): (number, number)
				return v.x - math.sin(v.yaw) * d, v.z - math.cos(v.yaw) * d
			end
			local d = 30
			local x, z = behind(d)
			local rod = rig.world.actorsById[rig.rodent]
			rig.put(rig.rodent, x, z)
			rod.speed = 4
			rig.dt = 0.1
			rig.step(0.3, function()
				local px, pz = behind(d)
				rig.put(rig.rodent, px, pz, v.yaw)
			end)
			while d > 8 do
				d -= 4 * rig.dt
				rig.step(rig.dt, function()
					local px, pz = behind(d)
					rig.put(rig.rodent, px, pz, v.yaw)
				end)
			end
			local g = rig.combat:guardOf(v.id)
			local unaware = g == nil or not g.aware
			local bit = unaware and rig.lunge(v.id, 8)
			if bit then
				stalked += 1
			end
			-- the same person, the rodent running at them from 20 studs behind
			local rig2 = BiteRig.new({ seed = 40 + case, overhead = true })
			rig2.step(15 + case)
			local v2 = rig2.world.actorsById[v.id]
			rig2.holdRodent()
			rig2.dt = 0.1
			rig2.world.actorsById[rig2.rodent].speed = 18
			local d2 = 20
			while d2 > 8 do
				d2 -= 18 * rig2.dt
				rig2.step(rig2.dt, function()
					rig2.put(rig2.rodent, v2.x - math.sin(v2.yaw) * d2, v2.z - math.cos(v2.yaw) * d2, v2.yaw)
				end)
			end
			local g2 = rig2.combat:guardOf(v.id)
			if g2 ~= nil and g2.aware then
				ran += 1
			end
		end
		print(
			`      {stalked}/{cases} creeps from behind bit unaware; {ran}/{cases} runs from behind were noticed first`
		)
		-- (some hear the wind-up and turn at the last moment: duel.tellHeard, a calm person's 0.35; 4 in 10 here)
		t.truthy(stalked >= cases * 0.3, "a creep from behind often bites unaware")
		t.truthy(ran >= cases - 1, "a run from behind is heard")
	end)

	t.test("the cost: a tick with 60 people crowded round the rodent on the wire", function()
		-- (everyone who may speak does: the caps alone hold the chatter back)
		local rig = BiteRig.new({
			seed = 5,
			overhead = true,
			overheadRand = function(): number
				return 0
			end,
		})
		rig.step(10)
		local crowd = {}
		for _, a in rig.world.actors do
			if a.species == "human" and #crowd < 60 then
				table.insert(crowd, a)
			end
		end
		t.truthy(#crowd >= 60, `{#crowd} people`)
		-- every Gaze write (an attribute that replicates to every player), by person
		local writes: { [number]: number } = {}
		local log: { Log } = {}
		local setAttr = rig.overhead.opts.setAttr
		rig.overhead.opts.setAttr = function(id: number, name: string, value: any)
			local a = rig.world.actorsById[id]
			table.insert(log, { t = rig.time, id = id, what = name, value = value, x = a and a.x, z = a and a.z })
			setAttr(id, name, value)
		end
		local inner = rig.overhead.opts.gaze
		rig.overhead.opts.gaze = function(id: number, x: number?, y: number?, z: number?)
			writes[id] = (writes[id] or 0) + 1
			inner(id, x, y, z)
		end
		local before = rig.overhead:stats()
		onWire(rig, 18, 20, function()
			local rod = rig.world.actorsById[rig.rodent]
			for i, a in crowd do
				local ang = i * 2.399
				local rr = 4 + (i % 12) * 2.5
				a.x, a.z = rod.x + math.cos(ang) * rr, rod.z + math.sin(ang) * rr
			end
		end)
		local st = rig.overhead:stats()
		local ticks = st.busyTicks - before.busyTicks
		local mean = (st.busyMs - before.busyMs) / math.max(1, ticks)
		print(
			string.format(
				"      %d ticks with 60 people round it: %.3f ms a tick on average, %.3f at worst (5 ticks a second: %.2f ms of server time a second); %d pairs rated",
				ticks,
				mean,
				st.peakMs,
				mean * 5,
				st.rated - before.rated
			)
		)
		t.truthy(ticks >= 90, "it ticked")
		t.truthy(mean < 1.0, `a tick costs {mean} ms on average`)
		-- the network: Gaze is rewritten only when the squirrel has moved a few degrees, at most twice a second a person
		local total, most, gazers = 0, 0, 0
		for _, n in writes do
			total += n
			most = math.max(most, n)
			gazers += 1
		end
		local secs = 20
		print(
			string.format(
				"      Gaze: %d writes in %d s by %d people (%.1f a second; the most from one person %.2f a second)",
				total,
				secs,
				gazers,
				total / secs,
				most / secs
			)
		)
		t.eq(st.gazeWrites - before.gazeWrites, total, "the stats count every write")
		t.truthy(most / secs <= 2.1, `no one's head is rewritten more than twice a second ({most / secs})`)
		t.truthy(total / secs <= 2.1 * math.max(1, gazers), "nor the crowd's")
		t.truthy(total / secs <= 90, `the crowd's Gaze writes stay under 90 a second ({total / secs}; was 186)`)
		-- the area cap in a crowd (review L7: a cap of 30 passed the old test): every line where it was said
		local worst, n = worstArea(log)
		print(`      the area cap in the crowd: {n} lines, at most {worst} within one area's window by an opener`)
		t.truthy(n >= 3, "the crowd talks")
		t.truthy(worst <= AreaPace.DEFAULTS.max, `{worst} lines in one area's window (cap {AreaPace.DEFAULTS.max})`)
		local _ = OverheadService
	end)
end
