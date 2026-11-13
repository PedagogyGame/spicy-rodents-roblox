--!strict
-- Stealth/RafterWatch, the sneak rule of the alley's rafters (BRIEF_ADDENDUM D9): the tables the survey's plan set
-- (one person 12 studs off, the squirrel lit and in front of them): walking is spotted within 1.5 s, creeping is not
-- for 15 s (35 s in the dark), sprinting or landing a leap within 0.5 s; three people spot faster than one; a bowler
-- facing the pins takes at least 2.5 times as long to notice a squirrel on the truss behind them; a squirrel in the
-- vent is never spotted; the meter falls back to 0; "seen" holds while it runs and ends 8 s after it is out of
-- sight; only the rafter routes and the people on the hall floor count. A crowd adds only a little (8 or 18 people:
-- a lit creep still takes 8 s or more, a walk 0.8 to 2 s); after "lost" a creep in view is not spotted again within
-- 10 s; the view cone is 3D (straight overhead is out of view); a can light under the squirrel does not light it;
-- the line of sight is the caller's and required. And the people's lines are short and mild.
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local AlleyRoof = require("@shared/Attractions/AlleyRoof")
local RafterWatch = require("@shared/Stealth/RafterWatch")

local BANNED = { "damn", "hell", "bastard", "crap", "piss", "bloody", "stupid", "idiot", "kill", "die", "dead", "shit" }
local DT = 0.05
-- every person can see the squirrel (the line of sight is the caller's raycast)
local function SEE(_o: RafterWatch.Observer, _s: RafterWatch.Squirrel): boolean
	return true
end

-- the chord at D 7.5 runs 2.4 over the cans at D 8: lit straight over each lane pair, dark between the pairs
local CHORD_D = 7.5
local CHORD_ID = 9123
local LIT_X = AlleyLayout.pairX(5)
local DARK_X = AlleyLayout.pairX(5) + AlleyLayout.PITCH
local EYE = 5.2

type Mode = { speed: number, focus: boolean, sprint: boolean }
local STILL: Mode = { speed = 0, focus = false, sprint = false }
local CREEP: Mode = { speed = 3, focus = true, sprint = false }
local WALK: Mode = { speed = 18, focus = false, sprint = false }
local SPRINT: Mode = { speed = 30.5, focus = false, sprint = true }

local function squirrel(X: number, D: number, mode: Mode, routeId: number?): RafterWatch.Squirrel
	return {
		id = "sq",
		routeId = routeId or CHORD_ID,
		X = X,
		Y = AlleyRoof.CHORD.y1,
		D = D,
		speed = mode.speed,
		focus = mode.focus,
		sprint = mode.sprint,
	}
end

-- a person `dist` studs from the squirrel (eye 5.2 over the floor), on the bowlers' side of it, facing it
local function facing(s: RafterWatch.Squirrel, dist: number, id: string?): RafterWatch.Observer
	local dy = s.Y - EYE
	local back = math.sqrt(dist * dist - dy * dy)
	return { id = id or "p1", X = s.X, Y = EYE, D = s.D - back, faceX = 0, faceD = 1 }
end

-- seconds until "spotted" (nil within `limit`)
local function timeToSpot(
	s: RafterWatch.Squirrel,
	observers: { RafterWatch.Observer },
	limit: number,
	firstTick: ((RafterWatch.Squirrel) -> ())?
): number?
	local state = RafterWatch.new()
	local clock = 0
	while clock < limit do
		local tick = table.clone(s)
		if clock == 0 and firstTick then
			firstTick(tick)
		end
		clock += DT
		for _, e in RafterWatch.step(state, { tick }, observers, nil, DT, SEE) do
			if e.kind == "spotted" then
				return clock
			end
		end
	end
	return nil
end

return function(t)
	t.test("the lamps: the test chord is lit over a pair and dark between pairs", function()
		local o = facing(squirrel(LIT_X, CHORD_D, WALK), 12)
		local lit = RafterWatch.rate(squirrel(LIT_X, CHORD_D, WALK), o)
		local dark = RafterWatch.rate(squirrel(DARK_X, CHORD_D, WALK), facing(squirrel(DARK_X, CHORD_D, WALK), 12))
		t.near(lit, RafterWatch.C.walk, 1e-9)
		t.near(dark, RafterWatch.C.walk * RafterWatch.C.dark, 1e-9)
	end)

	t.test("one person 12 st off, lit, in view: walking is spotted within 1.5 s, sprinting within 0.5 s", function()
		local walk = squirrel(LIT_X, CHORD_D, WALK)
		local tw = timeToSpot(walk, { facing(walk, 12) }, 10)
		t.truthy(tw ~= nil and tw <= 1.5, `walking spotted after {tw} s`)
		t.truthy(tw ~= nil and tw >= 0.8, `but not at once ({tw} s)`)
		local run = squirrel(LIT_X, CHORD_D, SPRINT)
		local ts = timeToSpot(run, { facing(run, 12) }, 10)
		t.truthy(ts ~= nil and ts <= 0.5, `sprinting spotted after {ts} s`)
		print(`      walking spotted after {tw} s, sprinting after {ts} s`)
	end)

	t.test("a leap landing on a beam is spotted within 0.5 s, even if it then keeps still", function()
		local s = squirrel(LIT_X, CHORD_D, STILL)
		local tl = timeToSpot(s, { facing(s, 12) }, 10, function(first)
			first.landed = true
		end)
		t.truthy(tl ~= nil and tl <= 0.5, `the landing spotted after {tl} s`)
		-- the same stillness without the landing is never spotted
		t.eq(timeToSpot(s, { facing(s, 12) }, 30), nil)
	end)

	t.test("creeping: not spotted for 15 s lit, 35 s in the dark (but in the end, lit, it is)", function()
		local lit = squirrel(LIT_X, CHORD_D, CREEP)
		t.eq(timeToSpot(lit, { facing(lit, 12) }, 15), nil, "creeping lit for 15 s")
		local late = timeToSpot(lit, { facing(lit, 12) }, 60)
		t.truthy(late ~= nil and late < 25, `a creep under a lamp in front of someone is seen after {late} s`)
		print(`      creeping under a lamp in front of someone: spotted after {late} s`)
		local dark = squirrel(DARK_X, CHORD_D, CREEP)
		t.eq(timeToSpot(dark, { facing(dark, 12) }, 35), nil, "creeping in the dark for 35 s")
		-- a creep that is not holding stalk (a slow walk) counts as walking
		local slow = squirrel(LIT_X, CHORD_D, { speed = 3, focus = false, sprint = false })
		local ts = timeToSpot(slow, { facing(slow, 12) }, 10)
		t.truthy(ts ~= nil and ts <= 1.5, "moving slowly without stalk held is walking")
	end)

	t.test("three people spot faster than one; far away nobody does", function()
		local s = squirrel(LIT_X, CHORD_D, WALK)
		local one = timeToSpot(s, { facing(s, 12) }, 10) :: number
		local three = timeToSpot(s, { facing(s, 12, "a"), facing(s, 12, "b"), facing(s, 12, "c") }, 10) :: number
		t.truthy(
			three <= 0.8 * one and three >= one / RafterWatch.C.crowdCap - DT,
			`three people {three} s, one {one} s`
		)
		local far = facing(s, 30)
		local tf = timeToSpot(s, { far }, 10) :: number
		t.truthy(tf > one, `30 st away takes longer ({tf} s)`)
		local o = facing(s, 69.9)
		t.truthy(RafterWatch.rate(s, o) < 0.01, "at 70 st nobody notices")
	end)

	t.test("a bowler facing the pins takes at least 2.5x as long to notice a squirrel on the truss behind", function()
		-- the truss at D -10.5 over the approaches, the bowler at the release line (D -4.4) aiming at the pins (+D)
		local s = squirrel(AlleyLayout.laneX(9), AlleyRoof.TRUSS_D[1], WALK, 9121)
		local bowler = { id = "bowler", X = AlleyLayout.laneX(9), Y = EYE, D = -4.4, faceX = 0, faceD = 1 }
		local turned = { id = "turned", X = AlleyLayout.laneX(9), Y = EYE, D = -4.4, faceX = 0, faceD = -1 }
		local away = timeToSpot(s, { bowler }, 30) :: number
		local toward = timeToSpot(s, { turned }, 30) :: number
		t.truthy(away >= 2.5 * toward, `facing away {away} s, facing it {toward} s`)
		print(`      the bowler facing the pins notices after {away} s, turned round after {toward} s`)
	end)

	t.test("in the vent nobody sees it: never spotted while hidden, whatever it does", function()
		local s = squirrel(LIT_X, CHORD_D, SPRINT)
		s.hidden = true
		t.eq(timeToSpot(s, { facing(s, 12) }, 30), nil, "hidden on a chord")
		local inVent = squirrel(AlleyRoof.BOOT.x1, 14, SPRINT, AlleyRoof.VENT)
		inVent.hidden = true
		t.eq(timeToSpot(inVent, { facing(inVent, 8) }, 30), nil, "in the duct")
		-- and only the rafter routes count: a squirrel on the yard's bough over the hall's line is not watched
		local bough = squirrel(LIT_X, CHORD_D, SPRINT, 9105)
		t.eq(timeToSpot(bough, { facing(bough, 12) }, 10), nil, "on the bough")
	end)

	t.test("only people on the hall floor count, and only those who can see it (the caller's line of sight)", function()
		local s = squirrel(LIT_X, CHORD_D, SPRINT)
		-- the guard on the roof platform, the games room, a person on a ladder at the ceiling
		local guard = { id = "guard", X = AlleyRoof.GUARD.x, Y = AlleyRoof.GUARD.eyeY, D = 16.5, faceX = -1, faceD = 0 }
		local games = { id = "games", X = 120, Y = EYE, D = 0, faceX = -1, faceD = 0 }
		local high = { id = "high", X = LIT_X, Y = 11, D = CHORD_D - 6, faceX = 0, faceD = 1 }
		t.eq(timeToSpot(s, { guard, games, high }, 10), nil)
		local state = RafterWatch.new()
		local seen = 0
		for _ = 1, 200 do
			local events = RafterWatch.step(state, { s }, { facing(s, 12) }, nil, DT, function()
				return false
			end)
			seen += #events
		end
		t.eq(seen, 0, "a wall between them")
	end)

	t.test("the meter falls back to 0 once it keeps still (and no person adds to it)", function()
		local state = RafterWatch.new()
		local s = squirrel(LIT_X, CHORD_D, WALK)
		local o = facing(s, 12)
		for _ = 1, math.floor(0.6 / DT) do
			RafterWatch.step(state, { s }, { o }, nil, DT, SEE)
		end
		local m0 = RafterWatch.meter(state, "sq")
		t.truthy(m0 > 0.3 and m0 < 1, `meter {m0} after 0.6 s walking`)
		local still = squirrel(LIT_X, CHORD_D, STILL)
		local seconds = 0
		while (RafterWatch.meter(state, "sq")) > 0 and seconds < 30 do
			RafterWatch.step(state, { still }, { o }, nil, DT, SEE)
			seconds += DT
		end
		t.eq((RafterWatch.meter(state, "sq")), 0)
		t.truthy(seconds <= m0 / RafterWatch.C.decay + 0.1, `back to 0 in {seconds} s`)
	end)

	t.test("spotted: the person and the lane; seen holds while it runs, ends 8 s after it hides in the vent", function()
		local state = RafterWatch.new()
		local s = squirrel(AlleyLayout.laneX(10), CHORD_D, SPRINT)
		local o = facing(s, 12, "bowler on 10")
		local spotted: RafterWatch.Event? = nil
		for _ = 1, 100 do
			for _, e in RafterWatch.step(state, { s }, { o }, nil, DT, SEE) do
				if e.kind == "spotted" then
					spotted = e
				end
			end
		end
		local e = spotted :: RafterWatch.Event
		t.truthy(e ~= nil, "spotted")
		t.eq(e.observer, "bowler on 10")
		t.eq(e.lane, 10)
		-- it keeps running in sight for 20 s: still seen, no second "spotted", no "lost"
		local kinds: { string } = {}
		for _ = 1, math.floor(20 / DT) do
			for _, ev in RafterWatch.step(state, { s }, { o }, nil, DT, SEE) do
				table.insert(kinds, ev.kind)
			end
		end
		t.eq(#kinds, 0, table.concat(kinds, ", "))
		local m, seen = RafterWatch.meter(state, "sq")
		t.eq(m, 1)
		t.eq(seen, true)
		-- into the vent: lost 8 s later
		local hidden = squirrel(AlleyRoof.BOOT.x1, 14, WALK, AlleyRoof.VENT)
		hidden.hidden = true
		local lostAt: number? = nil
		local clock = 0
		for _ = 1, math.floor(12 / DT) do
			clock += DT
			for _, ev in RafterWatch.step(state, { hidden }, { o }, nil, DT, SEE) do
				if ev.kind == "lost" then
					lostAt = clock
				end
			end
		end
		t.truthy(lostAt ~= nil and math.abs((lostAt :: number) - 8) <= 2 * DT, `lost after {lostAt} s`)
		-- creeping in plain sight does not keep it "seen" either
		local st2 = RafterWatch.new()
		for _ = 1, 20 do
			RafterWatch.step(st2, { s }, { o }, nil, DT, SEE)
		end
		local creep = squirrel(AlleyLayout.laneX(10), CHORD_D, CREEP)
		local lost2 = false
		for _ = 1, math.floor(9 / DT) do
			for _, ev in RafterWatch.step(st2, { creep }, { o }, nil, DT, SEE) do
				lost2 = lost2 or ev.kind == "lost"
			end
		end
		t.truthy(lost2, "a squirrel that creeps on is lost after 8 s")
		-- gone from the list while seen: lost at once
		local st3 = RafterWatch.new()
		for _ = 1, 20 do
			RafterWatch.step(st3, { s }, { o }, nil, DT, SEE)
		end
		local gone = RafterWatch.step(st3, {}, { o }, nil, DT, SEE)
		t.eq(#gone, 1)
		t.eq(gone[1].kind, "lost")
	end)

	-- the people on the approaches of lanes 1..n (D -6, eye 5.2), facing the pins unless told otherwise
	local function approaches(n: number, faceD: number?): { RafterWatch.Observer }
		local out = {}
		for i = 1, n do
			table.insert(
				out,
				{ id = `lane {i}`, X = AlleyLayout.laneX(i), Y = EYE, D = -6, faceX = 0, faceD = faceD or 1 }
			)
		end
		return out
	end
	-- seconds until "spotted" at the planned 5 Hz tick (nil within `limit`)
	local TICK = 0.2
	local function spotAt5Hz(s: RafterWatch.Squirrel, observers: { RafterWatch.Observer }, limit: number): number?
		local state = RafterWatch.new()
		local clock = 0
		while clock < limit do
			clock += TICK
			for _, e in RafterWatch.step(state, { s }, observers, nil, TICK, SEE) do
				if e.kind == "spotted" then
					return clock
				end
			end
		end
		return nil
	end

	t.test(
		"a crowd adds only a little: 8 or 18 people, creeping lit still takes 8 s or more, walking 0.8-2 s",
		function()
			local rows = {}
			for _, n in { 1, 4, 8, 12, 18 } do
				local people = approaches(n)
				local creep = spotAt5Hz(squirrel(LIT_X, CHORD_D, CREEP), people, 60)
				local creepDark = spotAt5Hz(squirrel(DARK_X, CHORD_D, CREEP), people, 60)
				local walk = spotAt5Hz(squirrel(LIT_X, CHORD_D, WALK), people, 60) :: number
				local walkDark = spotAt5Hz(squirrel(DARK_X, CHORD_D, WALK), people, 60) :: number
				local function f(x: number?): string
					return if x then string.format("%.1f", x) else "-"
				end
				table.insert(rows, `{n}: creep {f(creep)} / dark {f(creepDark)}, walk {f(walk)} / dark {f(walkDark)}`)
				t.truthy(creep == nil or creep >= 8, `{n} people see a lit creep after {creep} s`)
				t.truthy(creepDark == nil or creepDark >= 20, `{n} people see a dark creep after {creepDark} s`)
				t.truthy(walk >= 0.8 - 1e-6 and (n < 8 or walk <= 2), `{n} people see a lit walk after {walk} s`)
				t.truthy(walkDark >= 1.2, `{n} people see a dark walk after {walkDark} s`)
			end
			print(`      people on the approaches (lanes 1..n), s to spotted: {table.concat(rows, "; ")}`)
			-- behind twelve bowlers who all face the pins (the truss at D -10.5): a creep is safe, a walk takes a while
			local behind = approaches(12)
			local truss = AlleyRoof.TRUSS_D[1]
			local creep = spotAt5Hz(squirrel(LIT_X, truss, CREEP, 9121), behind, 30)
			local walk = spotAt5Hz(squirrel(LIT_X, truss, WALK, 9121), behind, 30) :: number
			t.eq(creep, nil, "creeping behind twelve bowlers")
			t.truthy(walk >= 2, `walking behind twelve bowlers is seen after {walk} s`)
			print(`      behind twelve bowlers: creep {creep or "never in 30"} s, walk {walk} s`)
		end
	)

	t.test("after 'lost', creeping on in view is not spotted again within 10 s; walking or running is", function()
		local s = squirrel(LIT_X, CHORD_D, WALK)
		local o = facing(s, 12)
		local function run(after: Mode): ({ string }, number?)
			local state = RafterWatch.new()
			local log: { string } = {}
			local lostAt: number? = nil
			local clock = 0
			while clock < 40 do
				clock += TICK
				local mode = if clock <= 2 then WALK elseif lostAt == nil then CREEP else after
				for _, e in RafterWatch.step(state, { squirrel(LIT_X, CHORD_D, mode) }, { o }, nil, TICK, SEE) do
					table.insert(log, `{e.kind}@{string.format("%.1f", clock)}`)
					if e.kind == "lost" then
						lostAt = clock
					elseif e.kind == "spotted" and lostAt then
						return log, clock - lostAt
					end
				end
			end
			return log, nil
		end
		local log, again = run(CREEP)
		t.truthy(again == nil or again > 10, `creeping in view after 'lost': {table.concat(log, " ")}`)
		print(`      walk 2 s then creep in view: {table.concat(log, " ")}`)
		local m = RafterWatch.C
		t.truthy(m.lostMeter < 1 and m.calm >= 10)
		local _, walkAgain = run(WALK)
		t.truthy(walkAgain ~= nil and walkAgain <= 1, `walking in view after 'lost' is seen again after {walkAgain} s`)
		local _, sprintAgain = run(SPRINT)
		t.truthy(
			sprintAgain ~= nil and sprintAgain <= 0.5,
			`sprinting after 'lost' is seen again after {sprintAgain} s`
		)
	end)

	t.test("the view cone is 3D: straight overhead counts as behind, 45 degrees up ahead is in view", function()
		local C = RafterWatch.C
		local s = squirrel(LIT_X, CHORD_D, WALK)
		local rise = s.Y - EYE
		-- right under the squirrel, facing on along the chord's line: it is 82 degrees up
		local under = { id = "under", X = LIT_X, Y = EYE, D = CHORD_D - 0.3, faceX = 0, faceD = 1 }
		t.near(RafterWatch.rate(s, under), C.walk * C.behind, 1e-9)
		local underAway = { id = "under", X = LIT_X, Y = EYE, D = CHORD_D - 0.3, faceX = 0, faceD = -1 }
		t.near(RafterWatch.rate(s, underAway), C.walk * C.behind, 1e-9)
		-- 45 degrees up, straight ahead
		local ahead = { id = "ahead", X = LIT_X, Y = EYE, D = CHORD_D - rise, faceX = 0, faceD = 1 }
		t.near(RafterWatch.rate(s, ahead), C.walk, 1e-9)
		-- 18 st away looking at it gives the full rate, and more than the person right under it
		t.truthy(RafterWatch.rate(s, facing(s, 18)) > RafterWatch.rate(s, under))
	end)

	t.test(
		"a can light right under the squirrel (its housing between) does not light it; one beside it does",
		function()
			local C = RafterWatch.C
			local rail = 9134 -- the light rail over lanes 9-10 (pair 5), the cans 0.3 under it at D 8, 12, 20 ...
			local function onRail(D: number): RafterWatch.Squirrel
				local s = squirrel(LIT_X, D, WALK, rail)
				s.Y = AlleyRoof.LIGHT_RAIL.y
				return s
			end
			local over, beside = onRail(12), onRail(10)
			t.near(RafterWatch.rate(over, facing(over, 12)), C.walk * C.dark, 1e-9)
			t.near(RafterWatch.rate(beside, facing(beside, 12)), C.walk, 1e-9)
			-- the chord 2.4 over the cans is still lit by them (their spill on the beams)
			local chord = squirrel(LIT_X, CHORD_D, WALK)
			t.near(RafterWatch.rate(chord, facing(chord, 12)), C.walk, 1e-9)
		end
	)

	t.test("the line of sight is required, and aimPoint aims at the body over the rail", function()
		local s = squirrel(LIT_X, CHORD_D, WALK)
		local ok = pcall(function()
			(RafterWatch.step :: any)(RafterWatch.new(), { s }, { facing(s, 12) }, nil, DT)
		end)
		t.eq(ok, false, "step without canSee is refused")
		local X, Y, D = RafterWatch.aimPoint(s)
		t.eq(X, s.X)
		t.eq(D, s.D)
		t.near(Y - s.Y, 0.85, 1e-9)
	end)

	t.test("laneOver: every lane's middle, nothing over the aisles", function()
		for i = 1, AlleyLayout.LANES do
			t.eq(RafterWatch.laneOver(AlleyLayout.laneX(i)), i)
		end
		t.eq(RafterWatch.laneOver(-24), nil)
		t.eq(RafterWatch.laneOver(98), nil)
	end)

	t.test("the people's lines: short and mild", function()
		t.truthy(#RafterWatch.LINES >= 4)
		for _, line in RafterWatch.LINES do
			t.truthy(#line <= 60 and #line >= 4, line)
			local lower = " " .. string.lower(line) .. " "
			for _, word in BANNED do
				t.truthy(string.find(lower, "%f[%a]" .. word .. "%f[%A]") == nil, `'{word}' in: {line}`)
			end
		end
	end)
end
