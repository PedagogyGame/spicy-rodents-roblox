--!strict
-- Validator round-16 review (w0-foundation 49b73c7): failing cases, no fix.
--   honest climb, rail to air   the motor's own E+Space climb (W and up held, E and Space every sixth frame), sent at 20
--                               packets a second: a packet that leaves a bough and grabs again inside it, its clock a float
--                               sum a hair over 0.05 s, is now a short gap (E.dtEps), and leaving a rail in a short gap has
--                               no hidden grab: "teleport" (was the long gap's rail visit half of the time). Trunk 1203
--   honest climb, a grab's snap the motor's grab of a sample 5.8 st over the body and 1.7 st across: the grab search's snap
--                               onto it is now N's distance across (hd + m), but the motor takes any sample of the band,
--                               within the 3-D nearest distance of where the body may be: "launch", "teleport". Trunk 170
--   honest climb, 10 Hz         a 0.1 s packet whose grab the search does not explain, no longer the long gap's rail visit
--                               (longVisit): "launch". Trunk 135
--   honest chain, in phase      pre-existing (37364fc, live in version 50): the motor's grab-leap chain along a rail sent in
--                               phase with its grabs (E+Space every sixth frame, a packet every sixth frame) shows no
--                               launch (the same vertical speed each packet), so the sprint judge never gets the grab
--                               search's explanation and holds the leaps' 41 st/s to the air's step: "speed"
--   grab climb 10 Hz            a crafted climb up the town's tallest trunk in 0.1 s packets, 5.5 st off its line (outside
--                               the bark rule): the grab search explains 6.75 st a packet, the governor's vertical bound
--                               (vRail and its one-off) is what holds it: 41 st/s over 2.5 s against the motor's 30.7.
--                               OPEN (LOW 2, pre-existing, live in version 50): validator round 17 left it to the governor
--                               (its vRail, 33.95 st/s, is the motor's own E+Space chain on a vertical trunk, and the
--                               honest chain up a leaning one snaps 0.4-0.6 st up a grab, 48 st/s for a while: a
--                               per-packet rise bound or no one-off for a chain snapped honest climbs); the case pins it
--                               there (the governor's rate and one-off + 1 st/s) and prints the motor's own
-- The honest cases assert a clean climb; the crafted one the governor's bound (above). About 10 s:
-- `lune run tests/run.luau validator_r16rv`.
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local MoveValidator = require("@server/Movement/MoveValidator")
local TestWorld = require("@tests/cheat/TestWorld")

type State = SquirrelMotor.State

local P = SquirrelMotor.params

-- (a copy of the validator's state for one actor, its tables shared as they are: a candidate packet tried and undone)
local function deep(v: any, memo: { [any]: any }): any
	if type(v) ~= "table" then
		return v
	end
	if memo[v] then
		return memo[v]
	end
	local c = {}
	memo[v] = c
	for k, x in v do
		c[deep(k, memo)] = deep(x, memo)
	end
	return setmetatable(c, getmetatable(v))
end

return function(t)
	local function flat(): (any, any)
		local tw = TestWorld.build({ boxes = {} })
		local function wall(): boolean
			return false
		end
		local function down(_ox: number, oy: number, _oz: number, _dx: number, dy: number, _dz: number): boolean
			return oy >= 0 and math.min(oy, oy + dy) <= 0
		end
		return tw, ValidatorWorld.build(tw, { wall = wall, down = down })
	end

	-- a validator fed one actor's packets, and a try that undoes itself: (clean, meter after)
	local function rig(vworld: any): ((State) -> any, (State) -> (boolean, number), any)
		local v = MoveValidator.new(vworld)
		local seq = 0
		local function feed(s: State): any
			seq += 1
			return v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(s) }, s.clock + 1)
		end
		local function try(s: State): (boolean, number)
			local a, m = v._actors.a, v._marks.a
			local memo = {}
			v._actors.a, v._marks.a = deep(a, memo), deep(m, memo)
			local seq0 = seq
			local r = feed(s)
			local meter = v._marks.a.stamina
			v._actors.a, v._marks.a = a, m
			seq = seq0
			return #r.violations == 0, meter
		end
		return feed, try, v
	end

	-- the motor on a trunk from its foot (W, sprint and up held; Space on a rail, E and Space every `every` frames in the
	-- air), facing `yaw`, for 2.5 s, a packet every `per` frames from the first: the violations, "code: detail"
	local function honestClimb(tw: any, vworld: any, id: number, yaw: number, every: number, per: number): { string }
		local reg = tw.registry
		local r = reg:get(id)
		local a, b = reg:pointAt(r, 0), reg:pointAt(r, 1)
		local t0 = if a.y < b.y then 0.03 else 0.97
		local p = reg:pointAt(r, t0)
		local s = SquirrelMotor.new(p.x, p.y, p.z)
		s.routeId, s.railT, s.grounded, s.clock, s.yaw = id, t0, false, 0, yaw
		local feed = rig(vworld)
		feed(SquirrelMotor.clone(s))
		local out = {}
		for f = 1, 150 do
			local i = SquirrelMotor.idleInput(yaw)
			i.fw, i.sprint, i.up = 1, true, 1
			i.leap = s.routeId ~= nil or (not s.grounded and f % every == 0)
			i.grab = s.routeId == nil and not s.grounded and f % every == 0
			SquirrelMotor.step(s, i, 1 / 60, tw)
			if f % per == 0 then
				for _, x in feed(SquirrelMotor.clone(s)).violations do
					table.insert(out, `frame {f}: {x.code}: {x.detail}`)
				end
			end
		end
		return out
	end

	local function honestCase(name: string, id: number, yaw: number, every: number, per: number)
		t.test(name, function()
			local tw, vworld = flat()
			local found = honestClimb(tw, vworld, id, yaw, every, per)
			for k, x in found do
				if k <= 3 then
					print(`      trunk {id}, yaw {yaw}, E+Space every {every} frames, a packet every {per}: {x}`)
				end
			end
			t.eq(#found, 0, `trunk {id}: violations of the motor's own climb`)
		end)
	end

	honestCase(
		"honest climb, rail to air: a 3-frame packet that leaves a bough and grabs again is clean",
		1203,
		0,
		6,
		3
	)
	honestCase(
		"honest climb, a grab's snap: the motor's grab of a sample over and across the body is clean",
		170,
		math.pi,
		6,
		3
	)
	honestCase("honest climb, 10 Hz: a 0.1 s packet with the motor's own grab is clean", 135, 0, 10, 6)
	honestCase("honest chain, in phase: a grab-leap chain sent in phase with its grabs is clean", 21, math.pi / 2, 6, 6)

	-- the motor's own grab-leap chain up a trunk (W, sprint, up held; on the rail Space, in the air E and Space every
	-- `every` frames): how far up it climbs from t1 to t2 seconds in, a second
	local function motorClimb(tw: any, id: number, t0: number, every: number, t1: number, t2: number): number
		local r = tw.registry:get(id)
		local p = tw.registry:pointAt(r, t0)
		local s = SquirrelMotor.new(p.x, p.y, p.z)
		s.routeId, s.railT, s.grounded, s.clock, s.yaw = id, t0, false, 0, 0
		local y0 = s.y
		local g1 = 0
		for f = 1, math.floor(t2 * 60 + 0.5) do
			local i = SquirrelMotor.idleInput(0)
			i.fw, i.sprint, i.up = 1, true, 1
			i.leap = s.routeId ~= nil or (not s.grounded and f % every == 0)
			i.grab = not s.grounded and s.routeId == nil and f % every == 0
			SquirrelMotor.step(s, i, 1 / 60, tw)
			if f == math.floor(t1 * 60 + 0.5) then
				g1 = s.y - y0
			end
		end
		return (s.y - y0 - g1) / (t2 - t1)
	end

	t.test(
		"grab climb 10 Hz: a crafted climb up a trunk in 0.1 s packets climbs no faster than the governor holds (LOW 2 open)",
		function()
			local tw, vworld = flat()
			local reg = tw.registry
			local id = 604 -- (the town's tallest trunk, 127 st)
			local r = reg:get(id)
			local lo, hi = reg:pointAt(r, 0), reg:pointAt(r, 1)
			local t0 = if lo.y < hi.y then 0.02 else 0.98
			local motor = 0
			for _, every in { 2, 3, 4, 6 } do
				motor = math.max(motor, motorClimb(tw, id, t0, every, 0, 2.5))
			end
			-- (the trunk's point at height y)
			local function at(y: number): any
				local a, b = 0, 1
				local rising = hi.y > lo.y
				for _ = 1, 30 do
					local mid = (a + b) / 2
					if (reg:pointAt(r, mid).y < y) == rising then
						a = mid
					else
						b = mid
					end
				end
				return reg:pointAt(r, (a + b) / 2)
			end
			local feed, try, v = rig(vworld)
			local s = SquirrelMotor.new(reg:pointAt(r, t0).x, reg:pointAt(r, t0).y, reg:pointAt(r, t0).z)
			s.routeId, s.railT, s.grounded, s.clock, s.yaw = id, t0, false, 0, 0
			feed(s)
			for _ = 1, 10 do
				for _ = 1, 3 do
					SquirrelMotor.step(s, SquirrelMotor.idleInput(0), 1 / 60, tw)
				end
				feed(s)
			end
			local i = SquirrelMotor.idleInput(0)
			i.fw, i.sprint, i.leap = 1, true, true
			SquirrelMotor.step(s, i, 1 / 60, tw)
			for _ = 1, 2 do
				local j = SquirrelMotor.idleInput(0)
				j.fw, j.sprint = 1, true
				SquirrelMotor.step(s, j, 1 / 60, tw)
			end
			assert(#feed(s).violations == 0, "the motor's leap off the trunk is clean")
			-- every 0.1 s the highest place the validator takes cleanly with its meter undrained: up the trunk's line by D, on
			-- it, 2 st or 5.5 st off it eight ways (outside the bark the grab rule keeps a leap from), launching at 5 to 33 st/s
			local dt = 0.1
			local start, y0 = s.clock, s.y
			local dirty = 0
			while s.clock - start < 2.5 - 1e-9 do
				local m0 = v._marks.a.stamina
				local best: State? = nil
				local bestD = -math.huge
				for _, rad in { 0, 2, 5.5 } do
					for ang = 0, (if rad == 0 then 0 else 7) do
						for _, vy in { 5, 15, 25, 33 } do
							local D = 8
							while D > bestD and D >= -1 do
								local p = at(s.y + D)
								local n = SquirrelMotor.new(
									p.x + math.cos(ang * math.pi / 4) * rad,
									s.y + D,
									p.z + math.sin(ang * math.pi / 4) * rad
								)
								n.grounded, n.vy, n.clock = false, vy, s.clock + dt
								local ok, m = try(n)
								if ok and m >= math.min(m0, 1) - 1e-4 then
									bestD, best = D, n
									break
								end
								D -= 0.25
							end
						end
					end
				end
				if best == nil then
					local n = SquirrelMotor.clone(s)
					n.vy = s.vy - P.gravity * dt
					n.y = s.y + (s.vy + n.vy) / 2 * dt
					n.clock = s.clock + dt
					best = n
					dirty += 1
				end
				dirty += #feed(best :: State).violations
				s = SquirrelMotor.clone(v._actors.a.last)
			end
			local pace = (s.y - y0) / (s.clock - start)
			print(
				string.format(
					"      crafted climb %.1f st/s over %.1f s in 0.1 s packets, meter %.2f, %d violations; the motor's own fastest over 2.5 s %.1f st/s",
					pace,
					s.clock - start,
					v._marks.a.stamina,
					dirty,
					motor
				)
			)
			local B = v:governorBounds(false)
			local held = (B.vRail * (s.clock - start) + B.dv) / (s.clock - start)
			t.truthy(pace <= held + 1, `crafted climb {pace} st/s against the governor's {held} (the motor's {motor})`)
		end
	)
end
