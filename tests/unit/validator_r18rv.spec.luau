--!strict
-- Adversarial review, round 18 (the validator and the motor at 7144137: the air trick D17/D18, round 17, the rail pace
-- D19): failing cases, no fix.
--   trick floor       MoveValidator._stamina: while a wiggle's re-aim is out at all (aimReach > 0 with any reach earned),
--                     the air's steering floor is a SPRINT's times the out scale for the walk-steered step too
--                     (walkLo = sprintLo = max(walkLo, P.sprint) x trickOut). The motor scales what it steers toward
--                     (its moveSpeed: a walk when winded or with Shift up); the server hands a winded body a sprint's
--                     steering in every flight for a claimed wiggle with a hair of reach, which costs an empty meter
--                     nothing. A stream that hops on landing and claims that every flight holds about 30 st/s for ever
--                     on an empty meter; the motor's own best from empty is 22 (trick hopping; a held sprint 22.1).
--   rail chain        the crafted grab-leap chain along a long rail (round 15's greedy, any launch speed a packet) in
--                     0.1 s and 0.25 s packets runs about 42 and 40 st/s, the pace of the motor BEFORE D19; the motor's
--                     own best along that rail is now 29.7 (Space held; E+Space 28.0). In 0.05 s packets it is held to
--                     33.7. validator_r15rv compares with a chain the motor cannot make (the cooldown switched off).
-- The bar in each: the motor's own best there x 1.15 (the owner's accepted residual, D19).
-- About 60 s: `lune run tests/run.luau validator_r18rv`.
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local MoveValidator = require("@server/Movement/MoveValidator")
local TestWorld = require("@tests/cheat/TestWorld")
local Units = require("@shared/Config/Units")

type State = SquirrelMotor.State

local P = SquirrelMotor.params
-- (the owner's accepted residual over the motor's own best, D19)
local RESIDUAL = 1.15

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
	-- (flat ground at y 0, no walls: the TestWorld's own routes, the town's)
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

	-- trick floor ------------------------------------------------------------------------------------------------------
	t.test(
		"trick floor: a wiggle claimed with a hair of reach every flight buys an empty meter no sprint's steering",
		function()
			local tw, vworld = flat()
			-- the motor's own best from an empty meter on open ground, 30 s at 60 fps, W and Shift held: a held sprint, hops
			-- on landing, hops with the wiggle full out at its best moment
			local function honest(leap: boolean, trickAt: number?): number
				local s = SquirrelMotor.new(Units.st(-560), tw.groundHeight, Units.st(-545))
				s.stamina, s.winded = 0, true
				local z0, inAir = s.z, 0
				for _ = 1, 30 * 60 do
					local i = SquirrelMotor.idleInput(math.pi)
					i.fw, i.sprint = 1, true
					if s.grounded then
						inAir = 0
						i.leap = leap
					else
						inAir += 1
						i.trick = inAir == trickAt
						i.aimReach = 1
					end
					SquirrelMotor.step(s, i, 1 / 60, tw)
				end
				return (s.z - z0) / 30
			end
			local motor =
				math.max(honest(false, nil), honest(true, nil), honest(true, 12), honest(true, 15), honest(true, 20))
			-- the crafted stream: each packet's height, vertical speed and footing are the motor's own (hops on landing, a
			-- packet every three frames); across, as far as the validator takes with no violation; `claim`: every airborne
			-- packet says a wiggle is on (fresh on the flight's first), its re-aim 0.02 out
			local function crafted(claim: boolean, secs: number): (number, number)
				local feed, try, v = rig(vworld)
				local m = SquirrelMotor.new(-1400, tw.groundHeight, -1360)
				m.clock, m.stamina, m.winded = 0, 0, true
				local z = m.z
				feed(m)
				v._marks.a.stamina, v._marks.a.winded = 0, true
				local dt = 0.05
				local prev: State = SquirrelMotor.clone(m)
				local dirty = 0
				local n = math.floor(secs / dt)
				for _ = 1, n do
					for _ = 1, 3 do
						local i = SquirrelMotor.idleInput(math.pi)
						i.fw, i.sprint, i.leap = 1, true, m.grounded
						SquirrelMotor.step(m, i, 1 / 60, tw)
					end
					local c = SquirrelMotor.clone(m)
					c.x, c.vx = -1400, 0
					c.trickKind, c.trickTime, c.aimYaw, c.aimReach = 0, 0, 0, 0
					if claim and not c.grounded then
						local on = prev.trickKind == 2 and not prev.grounded
						c.trickKind = 2
						c.trickTime = if on then math.max(0, prev.trickTime - dt) else P.trickWiggle
						c.aimReach = 0.02
					end
					local best: State? = nil
					local D = 3.5
					while D >= 0 and best == nil do
						local cc = SquirrelMotor.clone(c)
						cc.z, cc.vz = z + D, D / dt
						if try(cc) then
							best = cc
						end
						D -= 0.05
					end
					if best == nil then
						best = SquirrelMotor.clone(c)
						best.z, best.vz = z, 0
					end
					dirty += #feed(best).violations
					z = best.z
					prev = best
				end
				return (z + 1360) / (n * dt), dirty
			end
			local plain, d0 = crafted(false, 20)
			local claimed, d1 = crafted(true, 20)
			print(
				string.format(
					"      empty meter, open ground, 20 s: the motor's own best %.1f st/s; crafted with no claim %.1f (%d violations), claiming a wiggle 0.02 out every flight %.1f (%d violations)",
					motor,
					plain,
					d0,
					claimed,
					d1
				)
			)
			t.eq(d1, 0, "(the claimed stream is clean)")
			t.truthy(
				claimed <= motor * RESIDUAL,
				`claimed {claimed} st/s on an empty meter against the motor's {motor}`
			)
		end
	)

	-- rail chain -------------------------------------------------------------------------------------------------------
	-- the motor's own pace along a route from t1 to t2 s (W and sprint held; on the rail Space; in the air Space, or
	-- E and Space every `every` frames)
	local function motorChain(
		tw: any,
		id: number,
		t0: number,
		yaw: number,
		every: number?,
		t1: number,
		t2: number
	): number
		local r = tw.registry:get(id)
		local p = tw.registry:pointAt(r, t0)
		local s = SquirrelMotor.new(p.x, p.y, p.z)
		s.routeId, s.railT, s.grounded, s.clock, s.yaw = id, t0, false, 0, yaw
		local x0, z0 = s.x, s.z
		local fx, fz = -math.sin(yaw), -math.cos(yaw)
		local g1 = 0
		for f = 1, math.floor(t2 * 60 + 0.5) do
			local i = SquirrelMotor.idleInput(yaw)
			i.fw, i.sprint = 1, true
			if every then
				i.leap = s.routeId ~= nil or (not s.grounded and f % every == 0)
				i.grab = not s.grounded and s.routeId == nil and f % every == 0
			else
				i.leap = true
			end
			SquirrelMotor.step(s, i, 1 / 60, tw)
			if f == math.floor(t1 * 60 + 0.5) then
				g1 = (s.x - x0) * fx + (s.z - z0) * fz
			end
		end
		return ((s.x - x0) * fx + (s.z - z0) * fz - g1) / (t2 - t1)
	end
	-- the crafted chain (validator_r15rv's, any launch speed a packet): from the motor's own leap off the rail, every
	-- `dt` a packet on the rail's line `h` st off it, in the air, launching at one of four speeds up, as far along as the
	-- validator takes cleanly with the meter undrained. Returns its pace after the first second, the meter, violations
	local function craftedChain(
		tw: any,
		vworld: any,
		id: number,
		t0: number,
		dt: number,
		h: number
	): (number, number, number)
		local reg = tw.registry
		local r = reg:get(id)
		local a, b = reg:pointAt(r, t0), reg:pointAt(r, 1)
		local l = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
		local ux, uz = (b.x - a.x) / l, (b.z - a.z) / l
		local yaw = math.atan2(-ux, -uz)
		local function gone(s: State): number
			return (s.x - a.x) * ux + (s.z - a.z) * uz
		end
		local feed, try, v = rig(vworld)
		local s = SquirrelMotor.new(a.x, a.y, a.z)
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
		local start = s.clock
		local g0: number? = nil
		local c0, dirty = 0, 0
		while s.clock - start < 8 do
			if g0 == nil and s.clock - start >= 1 then
				g0, c0 = gone(s), s.clock
			end
			local m0 = v._marks.a.stamina
			local best: State? = nil
			local D = math.max(8, 60 * dt)
			while D >= -2 and best == nil do
				local p = reg:pointAt(r, math.clamp(t0 + (gone(s) + D) / r.length, 0, 1))
				for _, vy in { 5, 15, 25, 33 } do
					local c = SquirrelMotor.new(p.x, p.y + h, p.z)
					c.vx, c.vz, c.yaw = ux * 42, uz * 42, yaw
					c.grounded, c.vy, c.clock = false, vy, s.clock + dt
					local ok, m = try(c)
					if ok and m >= math.min(m0, 1) - 1e-4 then
						best = c
						break
					end
				end
				D -= 0.25
			end
			if best == nil then
				local n = SquirrelMotor.clone(s)
				n.vy = s.vy - P.gravity * dt
				n.y = s.y + (s.vy + n.vy) / 2 * dt
				n.clock = s.clock + dt
				best = n
			end
			dirty += #feed(best :: State).violations
			s = SquirrelMotor.clone(v._actors.a.last)
		end
		return (gone(s) - (g0 or 0)) / (s.clock - c0), v._marks.a.stamina, dirty
	end

	for _, case in { { dt = 0.1, h = 0, name = "10 Hz" }, { dt = 0.25, h = -1, name = "4 Hz" } } do
		t.test(
			`rail chain {case.name}: a crafted grab-leap chain along a long rail runs no faster than the motor's own chain there (D19)`,
			function()
				local tw, vworld = flat()
				local id, t0 = 1075, 0.02 -- (the river bridge's stone parapet, 530 st straight)
				local reg = tw.registry
				local r = reg:get(id)
				local a, b = reg:pointAt(r, t0), reg:pointAt(r, 1)
				local yaw = math.atan2(-(b.x - a.x), -(b.z - a.z))
				-- (the motor's own best along it: Space held, or E and Space every 2, 3, 4 or 6 frames, cooldown and all)
				local motor = motorChain(tw, id, t0, yaw, nil, 1, 9)
				for _, every in { 2, 3, 4, 6 } do
					motor = math.max(motor, motorChain(tw, id, t0, yaw, every, 1, 9))
				end
				local pace, meter, dirty = craftedChain(tw, vworld, id, t0, case.dt, case.h)
				print(
					string.format(
						"      %s packets along the parapet: crafted %.1f st/s after the first second, meter %.2f, %d violations; the motor's own best chain there %.1f st/s",
						case.name,
						pace,
						meter,
						dirty,
						motor
					)
				)
				t.truthy(pace <= motor * RESIDUAL, `crafted {pace} st/s against the motor's {motor}`)
			end
		)
	end
end
