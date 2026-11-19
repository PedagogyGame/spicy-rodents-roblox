--!strict
-- Stealth/OverheadWatch: people in town notice a squirrel stalking above them (owner playtest 2026-11-19). One person,
-- the squirrel 12 studs up on a wire: walking 20 studs in front of them it is spotted in about two seconds, sprinting in under
-- one, creeping not for 15 s; creeping straight over them from behind is never spotted; walking close over them is
-- heard and spotted, the same walk 30 studs off to the side, out of view, is not; the leaves (a branch) slow it to
-- less than half. The stages come in order (glance, look, spot), all of them in order when a landing jumps the meter;
-- "wary" follows the spot while it is in sight, "lost" once it is out of sight long enough, and a creep is not spotted
-- again at once; a glance that empties ends ("away"). The two-person exchange: the one told looks up at once and
-- answers once, a moment later. The squirrel's own eye is the highest meter on it.
local OverheadWatch = require("@shared/Stealth/OverheadWatch")

local DT = 0.2
local UP = 12 -- the wire over the person's eye
local C = OverheadWatch.C

type Mode = { speed: number, sprint: boolean? }
local STILL: Mode = { speed = 0 }
local CREEP: Mode = { speed = 3 }
local WALK: Mode = { speed = 18 }
local SPRINT: Mode = { speed = 30.5, sprint = true }

local function squirrel(x: number, z: number, mode: Mode, canopy: boolean?): OverheadWatch.Squirrel
	return { id = "rodent", x = x, y = UP, z = z, speed = mode.speed, sprint = mode.sprint, canopy = canopy }
end

-- a person at the origin, eye at 0, facing +z
local PERSON: OverheadWatch.Observer = { id = "p", x = 0, y = 0, z = 0, faceX = 0, faceZ = 1 }

local function seenOf(s: OverheadWatch.Squirrel, o: OverheadWatch.Observer): OverheadWatch.Seen?
	local r, imp, e = OverheadWatch.rate(s, o)
	if e <= 0 then
		return nil
	end
	return { squirrel = s.id, rate = r, impulse = imp, exposure = e, creep = s.speed <= C.stalkSpeed }
end

-- seconds until this person spots it (nil within `limit`), and the events on the way
local function timeToSpot(s: OverheadWatch.Squirrel, limit: number): (number?, { OverheadWatch.Event })
	local state = OverheadWatch.new()
	local all = {}
	local now = 0
	while now < limit do
		now += DT
		local seen = {}
		seen[PERSON.id] = seenOf(s, PERSON)
		for _, e in OverheadWatch.step(state, now, DT, seen) do
			table.insert(all, e)
			if e.kind == "spot" then
				return now, all
			end
		end
	end
	return nil, all
end

return function(t)
	t.test("in front of them: walking is spotted in about 2 s, sprinting in under 1, creeping not for 15 s", function()
		local walk = timeToSpot(squirrel(0, 20, WALK), 30)
		local sprint = timeToSpot(squirrel(0, 20, SPRINT), 30)
		local creep = timeToSpot(squirrel(0, 20, CREEP), 60)
		print(`      walk {walk} s, sprint {sprint} s, creep {creep} s`)
		t.truthy(walk and walk >= 1.2 and walk <= 3, `walk {walk}`)
		t.truthy(sprint and sprint <= 1, `sprint {sprint}`)
		t.truthy(creep == nil or creep >= 15, `creep {creep}`)
		t.eq(timeToSpot(squirrel(0, 20, STILL), 60), nil, "keeping still: never")
	end)

	t.test("stalking from behind: a creep straight over them or behind them is never spotted", function()
		t.eq(timeToSpot(squirrel(0, -2, CREEP), 120), nil, "creeping right overhead")
		t.eq(timeToSpot(squirrel(0, -10, CREEP), 120), nil, "creeping behind")
		local r = OverheadWatch.rate(squirrel(0, -2, CREEP), PERSON)
		t.truthy(r < C.quiet, `under the quiet line: {r}`)
	end)

	t.test(
		"close overhead is heard: a walk over them is spotted; the same walk 30 studs off to the side is not (in 10 s)",
		function()
			local over = timeToSpot(squirrel(2, -3, WALK), 20)
			local side = timeToSpot(squirrel(30, 0, WALK), 10)
			print(`      over them {over} s, 30 studs to the side {side}`)
			t.truthy(over and over <= 4, `over: {over}`)
			t.eq(side, nil, "off to the side, out of view")
			-- straight over them, and 20 studs off to the side
			local rOver = OverheadWatch.rate(squirrel(2, -3, WALK), PERSON)
			local rSide = OverheadWatch.rate(squirrel(20, 0, WALK), PERSON)
			t.truthy(rOver > rSide * 3, `close over them builds faster than off to the side: {rOver} against {rSide}`)
		end
	)

	t.test("the leaves: a walk on a branch takes more than twice as long", function()
		local open = timeToSpot(squirrel(0, 20, WALK), 30) :: number
		local leafy = timeToSpot(squirrel(0, 20, WALK, true), 30)
		t.truthy(leafy == nil or leafy >= open * 2.5, `open {open}, branch {leafy}`)
	end)

	t.test("the stages come in order; a landing that jumps the meter gives each, in order, at once", function()
		local _, events = timeToSpot(squirrel(0, 20, WALK), 30)
		local kinds = {}
		for _, e in events do
			table.insert(kinds, e.kind)
		end
		t.deepEq(kinds, { "glance", "look", "spot" })
		-- a sprint landing right in front of them
		local state = OverheadWatch.new()
		local s = squirrel(0, 6, SPRINT)
		s.landed = true
		local seen = {}
		seen[PERSON.id] = seenOf(s, PERSON)
		local _, impulse = OverheadWatch.rate(s, PERSON)
		t.truthy(impulse >= 0.3, `a landing adds {impulse}`)
		state.tracks[PERSON.id] = nil
		local ev = OverheadWatch.step(state, 0.2, DT, seen)
		seen[PERSON.id] = seenOf(s, PERSON)
		local ev2 = OverheadWatch.step(state, 0.4, DT, seen)
		local got = {}
		for _, e in ev do
			table.insert(got, e.kind)
		end
		for _, e in ev2 do
			table.insert(got, e.kind)
		end
		t.deepEq({ got[1], got[2], got[3] }, { "glance", "look", "spot" })
	end)

	t.test(
		"wary while it is in sight after the spot; lost once out of sight; a creep is not spotted again at once",
		function()
			local state = OverheadWatch.new()
			local s = squirrel(0, 10, WALK)
			local now = 0
			local kinds: { [string]: number } = {}
			local function tick(seen: OverheadWatch.Seen?)
				now += DT
				local m = {}
				m[PERSON.id] = seen
				for _, e in OverheadWatch.step(state, now, DT, m) do
					kinds[e.kind] = kinds[e.kind] or now
				end
			end
			while kinds.spot == nil and now < 10 do
				tick(seenOf(s, PERSON))
			end
			for _ = 1, 20 do
				tick(seenOf(s, PERSON))
			end
			t.truthy(kinds.wary and kinds.wary - kinds.spot >= C.waryAfter - DT, "wary a while after the spot")
			t.truthy(OverheadWatch.spotted(state, PERSON.id, "rodent"))
			local m, seen = OverheadWatch.meterOf(state, "rodent")
			t.eq(m, 1)
			t.truthy(seen)
			-- gone (out of everyone's sight)
			local gone = now
			while kinds.lost == nil and now < gone + 20 do
				tick(nil)
			end
			t.truthy(kinds.lost and kinds.lost - gone >= C.forget - DT and kinds.lost - gone <= C.forget + DT, "lost")
			t.falsy(OverheadWatch.spotted(state, PERSON.id, "rodent"))
			-- creeping in front of them again, right away: nothing builds
			local c = squirrel(0, 10, CREEP)
			local m0 = OverheadWatch.meterOf(state, "rodent")
			for _ = 1, 20 do
				tick(seenOf(c, PERSON))
			end
			t.truthy(OverheadWatch.meterOf(state, "rodent") <= m0, "a creep adds nothing just after it was lost")
		end
	)

	t.test("a glance that empties ends ('away'); a person with nothing left is dropped", function()
		local state = OverheadWatch.new()
		local s = squirrel(0, 10, WALK)
		local now = 0
		local got = {}
		local m = {}
		m[PERSON.id] = seenOf(s, PERSON)
		while OverheadWatch.stageOf(state, PERSON.id) ~= "glance" do
			now += DT
			OverheadWatch.step(state, now, DT, m)
		end
		for _ = 1, 100 do
			now += DT
			for _, e in OverheadWatch.step(state, now, DT, {}) do
				table.insert(got, e.kind)
			end
		end
		t.deepEq(got, { "away" })
		t.eq(state.tracks[PERSON.id], nil)
	end)

	t.test("the exchange: the one told looks up at once and answers once, a moment later", function()
		local state = OverheadWatch.new()
		t.truthy(OverheadWatch.tell(state, 10, "p", "q", "rodent"))
		t.eq(OverheadWatch.stageOf(state, "q"), "look")
		t.falsy(OverheadWatch.tell(state, 10.1, "r", "q", "rodent"), "already answering someone")
		local replies = {}
		local now = 10
		for _ = 1, 30 do
			now += DT
			for _, e in OverheadWatch.step(state, now, DT, {}) do
				if e.kind == "reply" then
					table.insert(replies, { at = now, other = e.other, person = e.person })
				end
			end
		end
		t.eq(#replies, 1)
		t.eq(replies[1].other, "p")
		t.eq(replies[1].person, "q")
		t.near(replies[1].at - 10, C.replyDelay, DT + 1e-6)
	end)
end
