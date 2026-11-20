--!strict
-- Validator round-15 review (w0-foundation 37364fc): failing cases, no fix.
--   grab chain 20 Hz   a crafted grab-leap chain along the river bridge's parapet (route 1075) in ordinary 0.05 s packets,
--                      no lag switch: every packet the furthest place along the rail the validator takes with no
--                      violation and no drain of its meter, one fixed shape (on the rail's line, a launch every packet at
--                      5, 15, 25, 33 st/s up in turn). About 50 st/s, the displacement governor's own ceiling, meter full;
--                      the motor's own fastest chain there (E+Space every second frame, a key-repeat macro's rate) runs
--                      47 st/s from its first second on, a person's (every sixth frame) 41. The grab search's band: a
--                      later grab's nearest samples taken within 2r on a line (r: how far the body may be), the leap
--                      from the band's highest with the whole band as its doubt, and r added to the snap again
--   grab chain 4 Hz    the same in 0.25 s packets (the round-15 residual, "44.2 st/s", at its real ceiling)
--   grab climb         the same up the town's tallest trunk (route 604), any launch speed and up to 3 st off its line:
--                      41.6 st/s against the motor's own 30.7 over 2.5 s (a packet a hair over 0.05 s, as float clocks
--                      make, is a long gap: a hidden rail visit's geometry, no grab search, up to the governor's vRail)
-- Each compares the crafted pace with the motor's own on the same route, measured here (along a rail within 3 %, up a
-- trunk within 1 st/s). About 15 s:
-- `lune run tests/run.luau validator_r15rv`.
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

	-- the motor's own grab-leap chain on a route (W and sprint held; on the rail Space, in the air E and Space every
	-- `every` frames): its pace along the heading (or up, `up`) from t1 to t2 seconds in
	local function motorChain(
		tw: any,
		id: number,
		t0: number,
		yaw: number,
		every: number,
		t1: number,
		t2: number,
		up: boolean
	): number
		local r = tw.registry:get(id)
		local p = tw.registry:pointAt(r, t0)
		local s = SquirrelMotor.new(p.x, p.y, p.z)
		s.routeId, s.railT, s.grounded, s.clock, s.yaw = id, t0, false, 0, yaw
		local x0, y0, z0 = s.x, s.y, s.z
		local fx, fz = -math.sin(yaw), -math.cos(yaw)
		local function gone(): number
			return if up then s.y - y0 else (s.x - x0) * fx + (s.z - z0) * fz
		end
		local g1 = 0
		for f = 1, math.floor(t2 * 60 + 0.5) do
			local i = SquirrelMotor.idleInput(yaw)
			i.fw, i.sprint = 1, true
			if up then
				i.up = 1
			end
			i.leap = s.routeId ~= nil or (not s.grounded and f % every == 0)
			i.grab = not s.grounded and s.routeId == nil and f % every == 0
			SquirrelMotor.step(s, i, 1 / 60, tw)
			if f == math.floor(t1 * 60 + 0.5) then
				g1 = gone()
			end
		end
		return (gone() - g1) / (t2 - t1)
	end

	-- the crafted chain: from the motor's own leap off the rail, every `dt` a packet on the rail's line (or up the trunk),
	-- in the air, launching at the next of `vys`, as far along as the validator takes cleanly with the meter undrained
	local function crafted(
		tw: any,
		vworld: any,
		id: number,
		dt: number,
		h: number,
		secs: number,
		place: (s: State, D: number) -> { State },
		free: boolean,
		gone: (s: State) -> number,
		yaw: number,
		t0: number,
		skip: number
	): (number, number, number)
		local feed, try, v = rig(vworld)
		local r = tw.registry:get(id)
		local p = tw.registry:pointAt(r, t0)
		local s = SquirrelMotor.new(p.x, p.y, p.z)
		s.routeId, s.railT, s.grounded, s.clock, s.yaw = id, t0, false, 0, yaw
		feed(s)
		for _ = 1, 10 do
			for _ = 1, 3 do
				SquirrelMotor.step(s, SquirrelMotor.idleInput(yaw), 1 / 60, tw)
			end
			feed(s)
		end
		local i = SquirrelMotor.idleInput(yaw)
		i.fw, i.sprint, i.leap = 1, true, true
		SquirrelMotor.step(s, i, 1 / 60, tw)
		for _ = 1, 2 do
			local j = SquirrelMotor.idleInput(yaw)
			j.fw, j.sprint = 1, true
			SquirrelMotor.step(s, j, 1 / 60, tw)
		end
		assert(#feed(s).violations == 0, "the motor's leap off the rail is clean")
		local vys = { 5, 15, 25, 33 }
		local k, start, stuck = 0, s.clock, 0
		local g0: number? = nil
		local c0 = 0
		local dirty = 0
		while s.clock - start < secs do
			k += 1
			if g0 == nil and s.clock - start >= skip then
				g0, c0 = gone(s), s.clock
			end
			local m0 = v._marks.a.stamina
			local best: State? = nil
			local D = math.max(8, 60 * dt)
			while D >= -2 and best == nil do
				-- (one launch speed in turn; `free`: any of them, and the places `place` offers round the line)
				for _, n in place(s, D) do
					for vi, vy in vys do
						if not free and vi ~= (k - 1) % #vys + 1 then
							continue
						end
						local c = SquirrelMotor.clone(n)
						c.grounded, c.vy, c.clock = false, vy, s.clock + dt
						c.y += h
						local ok, m = try(c)
						if ok and m >= math.min(m0, 1) - 1e-4 then
							best = c
							break
						end
					end
					if best then
						break
					end
				end
				D -= 0.25
			end
			if best == nil then
				stuck += 1
				local n = SquirrelMotor.clone(s)
				n.vy = s.vy - P.gravity * dt
				n.y = s.y + (s.vy + n.vy) / 2 * dt
				n.clock = s.clock + dt
				best = n
			end
			local res = feed(best :: State)
			dirty += #res.violations
			s = SquirrelMotor.clone(v._actors.a.last)
		end
		return (gone(s) - (g0 or 0)) / (s.clock - c0), v._marks.a.stamina, dirty + stuck
	end

	-- along a straight route: the place D studs further along it from where the body is, on its line
	local function alongRoute(
		tw: any,
		id: number,
		t0: number
	): ((State, number) -> { State }, (State) -> number, number)
		local reg = tw.registry
		local r = reg:get(id)
		local a, b = reg:pointAt(r, t0), reg:pointAt(r, 1)
		local l = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
		local ux, uz = (b.x - a.x) / l, (b.z - a.z) / l
		local function gone(s: State): number
			return (s.x - a.x) * ux + (s.z - a.z) * uz
		end
		local function place(s: State, D: number): State
			local p = reg:pointAt(r, math.clamp(t0 + (gone(s) + D) / r.length, 0, 1))
			local n = SquirrelMotor.new(p.x, p.y, p.z)
			n.vx, n.vz, n.yaw = ux * 42, uz * 42, math.atan2(-ux, -uz)
			return { n }
		end
		return place, gone, math.atan2(-ux, -uz)
	end

	for _, case in { { dt = 0.05, h = 0, name = "20 Hz" }, { dt = 0.25, h = -1, name = "4 Hz" } } do
		t.test(
			`grab chain {case.name}: a crafted grab-leap chain along a long rail runs no faster than the motor's own`,
			function()
				local tw, vworld = flat()
				local id, t0 = 1075, 0.02 -- (the river bridge's stone parapet, 530 st straight)
				local place, gone, yaw = alongRoute(tw, id, t0)
				-- (the motor's chain as the validator models it: with no grab-and-jump cooldown, owner D18's motor rule,
				-- which the grab search does not read yet; with it the motor's fastest is a person's 41.6 st/s, so a crafted
				-- chain keeps ~5 st/s over an honest one until the search reads the cooldown)
				local motor = 0
				local cd = P.grabLeapCooldown
				P.grabLeapCooldown = 0
				for _, every in { 2, 3, 4, 6 } do
					motor = math.max(motor, motorChain(tw, id, t0, yaw, every, 1, 9, false))
				end
				P.grabLeapCooldown = cd
				local pace, meter, dirty = crafted(tw, vworld, id, case.dt, case.h, 8, place, false, gone, yaw, t0, 1)
				print(
					string.format(
						"      %s packets: crafted %.1f st/s after the first second, meter %.2f, %d violations; the motor's own fastest chain %.1f st/s",
						case.name,
						pace,
						meter,
						dirty,
						motor
					)
				)
				t.truthy(pace <= motor * 1.03, `crafted {pace} st/s against the motor's {motor}`)
			end
		)
	end

	t.test("grab climb: a crafted grab-leap climb up a trunk climbs no faster than the motor's own", function()
		local tw, vworld = flat()
		local reg = tw.registry
		local id = 604 -- (the town's tallest trunk, 127 st)
		local r = reg:get(id)
		local lo, hi = reg:pointAt(r, 0), reg:pointAt(r, 1)
		local t0 = if lo.y < hi.y then 0.02 else 0.98
		local motor = 0
		local cd = P.grabLeapCooldown
		P.grabLeapCooldown = 0 -- (as the validator models it: no cooldown; see the rail chain above)
		for _, every in { 2, 3, 4, 6 } do
			motor = math.max(motor, motorChain(tw, id, t0, 0, every, 0, 2.5, true))
		end
		P.grabLeapCooldown = cd
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
		local function place(s: State, D: number): { State }
			-- (on the trunk's line, or up to 3 st off it four ways)
			local p = at(s.y + D)
			local out = {}
			for _, rad in { 0, 1, 2, 3 } do
				for ang = 0, 3 do
					table.insert(
						out,
						SquirrelMotor.new(
							p.x + math.cos(ang * math.pi / 2) * rad,
							s.y + D,
							p.z + math.sin(ang * math.pi / 2) * rad
						)
					)
				end
			end
			return out
		end
		local function gone(s: State): number
			return s.y
		end
		-- (packets every 0.05 s: the most the chain climbs a packet is a few studs, so the scan from 8 st covers it; the
		-- trunk is climbed in under 4 s)
		local pace, meter, dirty = crafted(tw, vworld, id, 0.05, 0, 2.5, place, true, gone, 0, t0, 0)
		print(
			string.format(
				"      crafted climb %.1f st/s over 2.5 s from the leap off the trunk, meter %.2f, %d violations; the motor's own fastest over 2.5 s %.1f st/s",
				pace,
				meter,
				dirty,
				motor
			)
		)
		t.truthy(pace <= motor + 1, `crafted climb {pace} st/s against the motor's {motor}`)
	end)
end
