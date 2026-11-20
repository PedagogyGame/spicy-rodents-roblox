--!strict
-- Validator round 13 (the round-12 review's findings; the failing cases are validator_r12rv): the mechanics those cases
-- do not reach on their own.
--   hidden launch     a gap from a bough that ends in a fresh flight beside it: a leap off the bough (free, its flight
--                     free); the same far from any rail, rising: a leap off the ground, charged leapCost, not free
--   winded reading    a hidden leap with the meter short of leapCost and the end no faster than a winded leap: the meter
--                     to empty at most (the motor's floor), its carry a winded one's; at full speed: leapCost in full
--   snap and hand-off a reset (a snap) ends a free flight; forget() parks winded and the speed kept, takeOver restores
--   rail hops         a "rail" column's hops past ValidatorWorld.C.HOPS spend the actor's ray pool (needs build/Town.rbxm)
-- About 2 s: `lune run tests/run.luau validator_r13`.
local fs = require("@lune/fs")
local Data = require("@shared/Data")
local Height = require("@shared/World/Height")
local BakedWorld = require("@tests/lib/BakedWorld")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local MoveValidator = require("@server/Movement/MoveValidator")
local TestWorld = require("@tests/cheat/TestWorld")

type State = SquirrelMotor.State

local P = SquirrelMotor.params
local E = SquirrelMotor.envelopeParams

return function(t)
	-- (open, flat ground at y 0 everywhere, no walls; v5.4's routes stand where the generated chunks put them)
	local function flat(): any
		local function wall(): boolean
			return false
		end
		local function down(_ox: number, oy: number, _oz: number, _dx: number, dy: number, _dz: number): boolean
			return oy >= 0 and math.min(oy, oy + dy) <= 0
		end
		return ValidatorWorld.build(TestWorld.build({}), { wall = wall, down = down })
	end

	-- a validator and a feed of packets for actor "a" (the server's time is the client's plus 1)
	local function rig(): (any, (State) -> any)
		local v = MoveValidator.new(flat())
		local seq = 0
		return v,
			function(s: State): any
				seq += 1
				return v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(s) }, s.clock + 1)
			end
	end

	-- the lowest bough within a cell of (x, z): its route, parameter and point
	local function bough(vworld: any, x: number, z: number): (number, number, any)
		local best, id, tt = math.huge, nil, 0
		vworld.index:forEachNear(
			x,
			0,
			z,
			5,
			function(rid: number, rt: number, sx: number, sy: number, sz: number): boolean?
				local d = (sx - x) ^ 2 + (sz - z) ^ 2
				if d < best and sy < 10 then
					best, id, tt = d, rid, rt
				end
				return nil
			end
		)
		assert(id, "a bough near the start")
		return id :: number, tt, vworld.registry:pointAt(vworld.registry:get(id :: number), tt)
	end

	-- a gap of `gap` s ending `age` s into a leap from (x, y, z) along x at the leap's speed
	local function leapEnd(x: number, y: number, z: number, clock: number, age: number, speed: number): State
		local s = SquirrelMotor.new(x + speed * age, y + P.leapUp * age - 0.5 * P.gravity * age * age, z)
		s.grounded, s.vx, s.vy = false, speed, P.leapUp - P.gravity * age
		s.clock = clock
		return s
	end

	t.test("hidden launch: a gap from a bough ending in a fresh flight beside it is a free leap off it", function()
		local v, feed = rig()
		local id, tt, pt = bough(v.world, 0, -200)
		local clock = 0
		for _ = 1, 10 do
			clock += 0.05
			local s = SquirrelMotor.new(pt.x, pt.y, pt.z)
			s.routeId, s.railT, s.grounded, s.clock = id, tt, false, clock
			feed(s)
		end
		local m = v._marks.a
		local before = m.stamina
		feed(leapEnd(pt.x, pt.y, pt.z, clock + 0.7, 0.2, P.leapForward))
		print(`      off the bough: free {m.speedRail}, meter {before} -> {m.stamina}`)
		t.eq(m.speedRail, true, "free off the bough")
		t.truthy(m.stamina >= before - 1e-9, "no charge")
	end)

	t.test("hidden launch: the same from the ground far from any rail is a leap off the ground, charged", function()
		local v, feed = rig()
		local clock = 0
		local x, z = 5000, 5000
		for _ = 1, 10 do
			clock += 0.05
			local s = SquirrelMotor.new(x, 0, z)
			s.clock = clock
			feed(s)
		end
		local m = v._marks.a
		local before = m.stamina
		feed(leapEnd(x, 0, z, clock + 0.7, 0.2, P.leapForward))
		print(`      off the ground: free {m.speedRail}, meter {before} -> {m.stamina}`)
		t.eq(m.speedRail, nil, "not free")
		t.truthy(math.abs(m.stamina - (before - P.leapCost)) < 1e-6, "leapCost charged")
	end)

	t.test(
		"winded reading: a hidden leap short of leapCost at a winded leap's speed takes the meter to empty",
		function()
			for _, full in { false, true } do
				local v, feed = rig()
				local clock = 0
				local x, z = 5000, 5000
				for _ = 1, 10 do
					clock += 0.05
					local s = SquirrelMotor.new(x, 0, z)
					s.clock = clock
					feed(s)
				end
				local m = v._marks.a
				m.stamina = 0.05
				local speed = if full then P.leapForward else P.leapForwardWinded
				feed(leapEnd(x, 0, z, clock + 0.7, 0.2, speed))
				print(`      {if full then "full" else "winded"} speed: meter 0.05 -> {m.stamina}, winded {m.winded}`)
				if full then
					t.truthy(math.abs(m.stamina - (0.05 - P.leapCost)) < 1e-6, "a full leap pays leapCost")
				else
					t.truthy(math.abs(m.stamina) < 1e-6, "a winded leap takes the meter to empty, no further")
						t.truthy(m.speedU <= P.leapForwardWinded * E.launchTol + 1e-6, "carries at a winded leap's speed")
				end
			end
		end
	)

	t.test("snap and hand-off: a reset ends a free flight; forget parks winded and the speed kept", function()
		local v, feed = rig()
		local s = SquirrelMotor.new(5000, 0, 5000)
		s.clock = 0.05
		feed(s)
		local m = v._marks.a
		m.speedRail, m.speedArcAt, m.speedArcY, m.speedArcVy = true, 0, 0, P.leapUp
		v:reset("a", SquirrelMotor.serialize(s), 2)
		t.eq(m.speedRail, nil, "a snap ends the free flight")
		t.eq(m.speedArcAt, nil, "and its arc")
		m.gov = m.gov or {}
		m.winded, m.speedU, m.speedS = true, 7, 8
		v:forget("a")
		v:takeOver("a", 5000, 0, 5000, 3)
		local back = v._marks.a
		t.eq(back.winded, true, "winded carried")
		t.eq(back.speedU, 7, "speed kept carried")
		t.eq(back.speedS, 8, "moveSpeed kept carried")
		t.eq(back.speedRail, nil, "never a free flight")
	end)

	t.test("rail hops: a column's hops past HOPS spend the actor's ray pool (needs build/Town.rbxm)", function()
		if not fs.isFile("build/Town.rbxm") then
			print("      (no build/Town.rbxm: bake first)")
			return
		end
		Height.configure(Data.default():module("TerrainExtensions"))
		local baked: any = BakedWorld.load("build/Town.rbxm")
		local bw = baked:motorWorld(Data.default())
		local _, _, cover = BakedWorld.validatorRays(baked)
		local function parentOf(p: any): string
			return string.match(p.path, "([^%.]+)%.[^%.]+$") or ""
		end
		local function prop(p: any): boolean
			return p.squirrelSolid and not ValidatorWorld.stops("rail", p.name, parentOf(p))
		end
		local deep, spent, closed = 0, 0, 0
		for _, r in bw.registry:all() do
			if deep >= 12 then
				break
			end
			local n = math.clamp(math.floor((r.length or 50) / 2), 2, 400)
			for k = 0, n do
				local p = bw.registry:pointAt(r, k / n)
				-- (the props the column down 40 st passes)
				local props, from, bottom = 0, p.y, p.y - 40
				while props < 64 do
					local t2 = baked.raycast(p.x, from, p.z, 0, bottom - from, 0, prop)
					if not t2 then
						break
					end
					props += 1
					from += (bottom - from) * t2 - 0.05
				end
				if props > ValidatorWorld.C.HOPS + 1 then
					deep += 1
					local pool = { left = 1000 }
					local open = cover(p.x, p.y, p.z, 0, -40, 0, "rail", pool)
					spent += 1000 - pool.left
					local empty = { left = 0 }
					if cover(p.x, p.y, p.z, 0, -40, 0, "rail", empty) then
						closed += 1
					end
					t.truthy(1000 - pool.left > 0 or open, "hops past HOPS taken from the pool")
					if deep >= 12 then
						break
					end
				end
			end
		end
		print(
			`      {deep} columns past {ValidatorWorld.C.HOPS + 1} props: {spent} rays from the pool, {closed} closed on an empty one`
		)
		t.truthy(deep >= 5, "such columns found")
		t.truthy(spent > 0, "the pool spent")
		t.eq(closed, deep, "an empty pool fails each column closed")
	end)
end
