--!strict
-- Validator round 16 (the round-15 review's findings; its failing cases are validator_r15rv):
--   packet clocks     a packet of three motor frames whose clock is a float sum (0.05000000000000004 s) is judged as one of
--                     0.05 s: the same verdict (LOW 2: it was a long gap, a hidden rail visit's geometry with no grab search)
--   honest climb      the motor's own E+Space chain up that trunk, every second to every sixth frame (E is an edge: a
--                     person or a key-repeat macro presses it every second frame at most), sent at 60, 20 and 4 packets a
--                     second: clean (the held height is the motor's own leap's, a little under the sent at times)
--   first gather      the grab search's first gather of samples is within the work too (LOW 3): past it, fail safe before
--                     any entry is walked
-- About 5 s: `lune run tests/run.luau validator_r16`.
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local MoveValidator = require("@server/Movement/MoveValidator")
local TestWorld = require("@tests/cheat/TestWorld")

type State = SquirrelMotor.State

local E = SquirrelMotor.envelopeParams

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

	-- a validator fed one actor's packets
	local function rig(vworld: any): ((State) -> any, any)
		local v = MoveValidator.new(vworld)
		local seq = 0
		local function feed(s: State): any
			seq += 1
			return v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(s) }, s.clock + 1)
		end
		return feed, v
	end

	local TRUNK = 604 -- (the town's tallest trunk, 127 st)
	local function trunk(tw: any): (any, number, any, any)
		local reg = tw.registry
		local r = reg:get(TRUNK)
		local lo, hi = reg:pointAt(r, 0), reg:pointAt(r, 1)
		return r, if lo.y < hi.y then 0.02 else 0.98, lo, hi
	end

	-- the motor on the trunk (W and up held; Space on the rail, E and Space every `every` frames in the air), stepped
	-- `frames` frames at 60 a second; `each(s, f)` after every frame
	local function motorClimb(tw: any, every: number, frames: number, each: (State, number) -> ())
		local r, t0 = trunk(tw)
		local p = tw.registry:pointAt(r, t0)
		local s = SquirrelMotor.new(p.x, p.y, p.z)
		s.routeId, s.railT, s.grounded, s.clock, s.yaw = TRUNK, t0, false, 0, 0
		for f = 1, frames do
			local i = SquirrelMotor.idleInput(0)
			i.fw, i.sprint, i.up = 1, true, 1
			i.leap = s.routeId ~= nil or (not s.grounded and f % every == 0)
			i.grab = not s.grounded and s.routeId == nil and f % every == 0
			SquirrelMotor.step(s, i, 1 / 60, tw)
			each(s, f)
		end
	end

	t.test("packet clocks: three frames' float clock sum is judged as a 0.05 s packet", function()
		local tw, vworld = flat()
		local r, t0 = trunk(tw)
		local reg = tw.registry
		local p = reg:pointAt(r, t0 + 0.1)
		local long = 1 / 60 + 1 / 60 + 1 / 60 -- (0.05000000000000000277: the motor's own clock after three frames)
		local sum = 0.1 + 0.05 - 0.1 -- (0.04999999999999999: a hair under)
		local over = 10 + 0.05 - 10 -- (0.05000000000000071: a hair over, as a packet's clocks make)
		assert(over > E.shortDt, "the float sum is over shortDt")
		local shapes = 0
		for _, dy in { 0.5, 1.75, 3, 6 } do
			for _, off in { 0, 2 } do
				for _, vy in { 5, 20, 33 } do
					local prev = SquirrelMotor.new(p.x + off, p.y, p.z)
					prev.grounded, prev.vy, prev.clock = false, 10, 10
					local verdicts = {}
					for _, dt in { E.shortDt, long, sum, over } do
						local nxt = SquirrelMotor.new(p.x + off, p.y + dy, p.z)
						nxt.grounded, nxt.vy, nxt.clock = false, vy, 10 + dt
						local found = SquirrelMotor.envelope(prev, nxt, dt, vworld, false, nil)
						local codes = {}
						for _, v in found do
							table.insert(codes, v.code)
						end
						table.sort(codes)
						table.insert(verdicts, table.concat(codes, ","))
					end
					for k = 2, #verdicts do
						t.eq(verdicts[k], verdicts[1], `rise {dy} st, {off} st off, vy {vy}: packet {k}'s verdict`)
					end
					shapes += 1
				end
			end
		end
		print(`      {shapes} shapes up the trunk: the same verdict at 0.05 s and at its float sums`)
	end)

	t.test("honest climb: the motor's own E+Space chain up the trunk is clean", function()
		local tw, vworld = flat()
		local runs, worstHeld = 0, 0
		for _, every in { 2, 3, 4, 6 } do
			for _, send in { 1, 3, 15 } do
				local feed, v = rig(vworld)
				local dirty = 0
				local held = 0
				local first = true
				motorClimb(tw, every, 240, function(s: State, f: number)
					if first then
						first = false
						feed(SquirrelMotor.clone(s))
					elseif f % send == 0 then
						local res = feed(SquirrelMotor.clone(s))
						dirty += #res.violations
						held = math.max(held, s.y - v._actors.a.last.y)
					end
				end)
				t.eq(dirty, 0, `E+Space every {every} frames, a packet every {send}: violations`)
				worstHeld = math.max(worstHeld, held)
				runs += 1
			end
		end
		print(
			string.format("      %d runs of 4 s: clean, the place held at most %.2f st under the sent", runs, worstHeld)
		)
	end)

	t.test("first gather: the grab search walks no entry past its work", function()
		local tw, vworld = flat()
		local index = vworld.index :: any
		-- (the route sample with the most samples within 20 st: the densest crown)
		local best, at = -1, nil
		for _, r in tw.registry:all() do
			if r.kind == "trunk" then
				local p = tw.registry:pointAt(r, 0.8)
				local m = 0
				index:forEachNear(p.x, p.y, p.z, 20, function(): boolean?
					m += 1
					return nil
				end)
				if m > best then
					best, at = m, p
				end
			end
		end
		assert(at, "a crown")
		-- (the entries the search reads: each cell handed out counts its own reads of x)
		local reads = 0
		local cel = index.cell
		index.cell = function(self: any, ix: number, iy: number, iz: number): any
			local c = cel(self, ix, iy, iz)
			if c == nil then
				return nil
			end
			local xs = setmetatable({}, {
				__index = function(_: any, k: number): number
					reads += 1
					return c.xs[k]
				end,
			})
			return { n = c.n, ids = c.ids, ts = c.ts, xs = xs, ys = c.ys, zs = c.zs }
		end
		local prev = SquirrelMotor.new(at.x + 2, at.y, at.z + 2)
		prev.grounded, prev.vy, prev.vx, prev.clock = false, -60, 30, 10
		local nxt = SquirrelMotor.new(at.x + 6, at.y + 4, at.z + 2)
		nxt.grounded, nxt.vy, nxt.vx, nxt.clock = false, 25, 30, 10 + E.grabSimDt
		local work = E.grabWork
		reads = 0
		SquirrelMotor.envelope(prev, nxt, E.grabSimDt, vworld, false, nil)
		local full = reads
		-- (the work set under what the first gather alone holds)
		local ok, err = pcall(function()
			E.grabWork = math.max(1, math.floor(full / 2))
			reads = 0
			SquirrelMotor.envelope(prev, nxt, E.grabSimDt, vworld, false, nil)
		end)
		local low = reads
		E.grabWork = work
		index.cell = cel
		assert(ok, err)
		print(
			`      the densest crown ({best} samples within 20 st): {full} entries read at the full work, {low} at a work of {math.max(
				1,
				math.floor(full / 2)
			)}`
		)
		t.truthy(full <= work, `{full} entries read, the work {work}`)
		t.eq(low, 0, "past the work before any grab: no entry read")
	end)
end
