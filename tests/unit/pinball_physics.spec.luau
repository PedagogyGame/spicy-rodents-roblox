--!strict
-- Minigames/Pinball/Physics: the one physics core, against known cases (checklist PIN-P3, PIN-P4):
-- the same inputs give the same bits; a copy of the state continues identically (nothing hidden); the ball
-- accelerates down the slope at the table's gravity and arcs across it; energy never grows by itself; rubber
-- is lively and metal dead; a pop bumper and a slingshot ADD a fixed kick; the speed cap holds; at top speed
-- nothing passes through a wall, a post, a flipper or the cabinet on any of the three tables, with one ball or
-- three; a ball left alone always drains or comes to rest; a ramp costs speed and a slow ball rolls back out;
-- the gate at the head of the shooter lane is one-way; a kick-out hole swallows and returns; a spinner spins
-- as fast as the ball went through and runs down; and a step is cheap.
local Layout = require("@shared/Minigames/Pinball/Layout")
local Machine = require("@shared/Minigames/Pinball/Machine")
local Physics = require("@shared/Minigames/Pinball/Physics")
local Tables = require("@shared/Minigames/Pinball/Tables")
local Test = require("../lib/Test")

local EV = Physics.EV
local R = Layout.BALL_R

local function lcg(seed: number): () -> number
	local s = seed
	return function(): number
		s = (s * 69069 + 1) % 4294967296
		return math.floor(s / 65536) / 65536
	end
end

-- every number in a physics state, in a fixed order
local function digest(s: Physics.State): string
	local parts = { tostring(s.tick), tostring(s.rng) }
	for _, b in s.balls do
		table.insert(
			parts,
			string.format("%.17g/%.17g/%.17g/%.17g/%d/%.17g", b.x, b.y, b.vx, b.vy, b.mode, b.s)
		)
	end
	for i = 1, #s.fa do
		table.insert(parts, string.format("%.17g/%.17g", s.fa[i], s.fw[i]))
	end
	for i = 1, #s.drop do
		table.insert(parts, if s.drop[i] then "1" else "0")
	end
	return table.concat(parts, " ")
end

-- a bare table: the cabinet's shell only
local function shell(): Layout.Compiled
	local def = Layout.new("test", "TEST")
	Layout.addShell(def)
	return Layout.compile(def)
end

-- did the ball's centre cross a standing wall between two points?
local function crossed(
	c: Layout.Compiled,
	s: Physics.State,
	x0: number,
	y0: number,
	x1: number,
	y1: number
): number
	for id = 1, c.nSeg do
		local kind = c.sKind[id]
		if kind == Layout.SEG_GATE or (kind == Layout.SEG_DROP and s.drop[c.sRef[id]]) then
			continue
		end
		local ax, ay, dx, dy = c.sx[id], c.sy[id], c.sdx[id], c.sdy[id]
		local s0 = (y0 - ay) * dx - (x0 - ax) * dy
		local s1 = (y1 - ay) * dx - (x1 - ax) * dy
		if (s0 < 0 and s1 > 0) or (s0 > 0 and s1 < 0) then
			local u = s0 / (s0 - s1)
			local px, py = x0 + (x1 - x0) * u, y0 + (y1 - y0) * u
			local along = ((px - ax) * dx + (py - ay) * dy) * c.sInv[id]
			if along > 0.001 and along < 0.999 then
				return id
			end
		end
	end
	return 0
end

-- where a ball is against flipper i as it stands now: along it (0 pivot, 1 tip) and which side of its middle
-- line (+ above)
local function overFlipper(c: Layout.Compiled, s: Physics.State, i: number, b: Physics.Ball): (number, number)
	local a = s.fa[i]
	local dx, dy = c.fmir[i] * math.cos(a), math.sin(a)
	local qx, qy = b.x - c.fpx[i], b.y - c.fpy[i]
	return (qx * dx + qy * dy) / c.flen[i], (qy * dx - qx * dy) * c.fmir[i]
end

return function(t: Test.T)
	t.test("the tick is 1/240 s (PIN: fixed tick of 240 Hz or finer) and a sub-step moves under a third of a radius", function()
		t.eq(Physics.HZ, 240)
		t.eq(Physics.DT, 1 / 240)
		t.truthy(Physics.SUB_TRAVEL <= R / 3)
		-- at top speed, with a flipper at full swing, the sub-steps in hand are enough
		local worst = Physics.MAX_SPEED * Physics.DT + Physics.FLIP_W_MAX * Physics.DT * 0.45
		t.truthy(worst / Physics.SUB_TRAVEL <= Physics.MAX_SUBSTEPS, "sub-steps cover the worst case")
	end)

	t.test("determinism: the same seed and the same buttons give the same bits, on every table", function()
		for _, id in Tables.IDS do
			local tbl = Tables.need(id)
			local function run(): string
				local s = Physics.new(tbl.c, 99)
				local rnd = lcg(7)
				local ev: { number } = {}
				Physics.addBall(s, 1.0, 3.0, 2.2, 6.1)
				Physics.addBall(s, 0.6, 2.4, -3.0, 4.0)
				for i = 1, 2400 do
					local left = rnd() < 0.3
					local right = rnd() < 0.3
					Physics.step(tbl.c, s, left, right, ev)
					if i % 400 == 0 then
						Physics.removeGone(s)
						Physics.addBall(s, 0.5 + rnd(), 2.5 + rnd(), rnd() * 8 - 4, rnd() * 8)
					end
				end
				return digest(s) .. " " .. tostring(#ev)
			end
			t.eq(run(), run(), id)
		end
	end)

	t.test("no hidden state: a copy of the state continues exactly as the original does", function()
		local tbl = Tables.need("pinball_space")
		local s = Physics.new(tbl.c, 5)
		local ev: { number } = {}
		Physics.addBall(s, 1.1, 3.2, 3, 5)
		for i = 1, 500 do
			Physics.step(tbl.c, s, i % 90 < 30, i % 70 < 20, ev)
		end
		local m = Machine.new(tbl, 5, 1)
		m.phys = s
		local twin = Machine.clone(m).phys
		-- step something else in between: scratch buffers must not matter
		local other = Physics.new(tbl.c, 1)
		Physics.addBall(other, 0.5, 2.0, 1, 1)
		for i = 1, 500 do
			Physics.step(tbl.c, s, i % 50 < 10, i % 60 < 30, ev)
			Physics.step(tbl.c, other, true, false, ev)
		end
		for i = 1, 500 do
			Physics.step(tbl.c, twin, i % 50 < 10, i % 60 < 30, ev)
		end
		t.eq(digest(s), digest(twin))
	end)

	t.test("PIN-P4: the ball rolls down the slope at the table's gravity and arcs across the table", function()
		local c = shell()
		local s = Physics.new(c, 1)
		local ev: { number } = {}
		local i = Physics.addBall(s, 0.5, 4.0, 1.0, 0)
		local b = s.balls[i]
		for _ = 1, 120 do
			Physics.step(c, s, false, false, ev)
		end
		-- half a second: y falls by g t^2 / 2 (less a little rolling resistance), x runs on
		t.near(4.0 - b.y, c.gravity * 0.25 / 2, 0.03, "distance fallen")
		t.near(b.vy, -c.gravity * 0.5, 0.12, "speed down the table")
		t.truthy(b.x > 0.95 and b.x < 1.0, "it kept going across")
		-- and thrown up the table it slows, stops and comes back: an arc
		local s2 = Physics.new(c, 1)
		local j = Physics.addBall(s2, 0.5, 1.0, 0.8, 4.0)
		local top = 0
		for _ = 1, 480 do
			Physics.step(c, s2, false, false, ev)
			top = math.max(top, s2.balls[j].y)
		end
		t.near(top - 1.0, 16 / (2 * c.gravity), 0.12, "height of the arc")
	end)

	t.test("energy never grows by itself (dead table: nothing kicks), on every table", function()
		for _, id in Tables.IDS do
			local tbl = Tables.need(id)
			local rnd = lcg(11)
			for _ = 1, 12 do
				local s = Physics.new(tbl.c, 3)
				s.dead = true
				local ev: { number } = {}
				-- thrown from the open middle of the table
				local i = Physics.addBall(s, Layout.XC - 0.2 + rnd() * 0.4, 1.6 + rnd() * 0.4, rnd() * 20 - 10, rnd() * 20 - 4)
				local b = s.balls[i]
				local start = Physics.energy(tbl.c, b)
				local high = start
				for _ = 1, 1200 do
					Physics.step(tbl.c, s, false, false, ev)
					if b.mode == Physics.FREE then
						high = math.max(high, Physics.energy(tbl.c, b))
					elseif b.mode ~= Physics.RAIL then
						break
					end
				end
				-- pushing a ball out of a surface it has sunk a hair into is the only gain there is
				t.truthy(high <= start + 0.02, `{id}: energy rose from {start} to {high}`)
			end
		end
	end)

	t.test("PIN-P4: rubber is bouncy, metal and wood are dead", function()
		local function bounce(mat: string): number
			local def = Layout.new("test", "TEST")
			Layout.addShell(def)
			Layout.wall(def, mat, { 0.4, 2.0, 1.8, 2.0 })
			local c = Layout.compile(def)
			local s = Physics.new(c, 1)
			local ev: { number } = {}
			local i = Physics.addBall(s, 1.1, 2.0 + R + 0.02, 0, -6)
			local b = s.balls[i]
			for _ = 1, 4 do
				Physics.step(c, s, false, false, ev)
			end
			return b.vy
		end
		local rubber, metal, wood = bounce("rubber"), bounce("metal"), bounce("wood")
		t.near(rubber / 6, Layout.MATERIALS.rubber.e, 0.03)
		t.near(metal / 6, Layout.MATERIALS.metal.e, 0.03)
		t.truthy(rubber > 1.5 * wood and wood > metal, "rubber > wood > metal")
		t.truthy(Layout.MATERIALS.rubber.e >= 0.65 and Layout.MATERIALS.metal.e <= 0.4)
	end)

	t.test("PIN-P4: a pop bumper throws the ball out at its own fixed speed, however softly it was touched", function()
		local function pop(speed: number, dead: boolean): (number, number)
			local def = Layout.new("test", "TEST")
			Layout.addShell(def)
			table.insert(def.bumpers, { id = "b", x = 1.1, y = 2.5, r = 0.12 })
			local c = Layout.compile(def)
			local s = Physics.new(c, 1)
			s.dead = dead
			local ev: { number } = {}
			local i = Physics.addBall(s, 1.1, 2.5 + 0.12 + R + 0.01, 0, -speed)
			for _ = 1, 3 do
				Physics.step(c, s, false, false, ev)
			end
			local fired = 0
			for k = 1, #ev, 4 do
				if ev[k] == EV.BUMPER and ev[k + 2] == 1 then
					fired += 1
				end
			end
			return s.balls[i].vy, fired
		end
		local soft, f1 = pop(1.0, false)
		local hard, f2 = pop(9.0, false)
		t.eq(f1, 1)
		t.eq(f2, 1)
		t.near(soft, Physics.BUMPER_KICK, 0.1, "a soft touch")
		t.near(hard, Physics.BUMPER_KICK, 0.1, "a hard hit")
		t.truthy(soft > 1.0 * 3, "energy was added")
		-- tilted, the bumper is a rubber post and adds nothing
		local dead, f3 = pop(4.0, true)
		t.eq(f3, 0)
		t.truthy(dead < 4.0 * 0.6, "a dead bumper only bounces")
	end)

	t.test("PIN-P4: a slingshot adds its kick to the bounce; a touch near its ends or too soft does not fire", function()
		local tbl = Tables.need("pinball_acorn")
		local sl = tbl.def.slings[1]
		local dx, dy = sl.x2 - sl.x1, sl.y2 - sl.y1
		local len = math.sqrt(dx * dx + dy * dy)
		-- the face looks toward the middle of the table
		local nx, ny = -dy / len, dx / len
		if nx < 0 then
			nx, ny = -nx, -ny
		end
		local function hit(at: number, speed: number): (number, number)
			local s = Physics.new(tbl.c, 1)
			local ev: { number } = {}
			local px, py = sl.x1 + dx * at + nx * (R + 0.01), sl.y1 + dy * at + ny * (R + 0.01)
			local i = Physics.addBall(s, px, py, -nx * speed, -ny * speed)
			Physics.step(tbl.c, s, false, false, ev)
			Physics.step(tbl.c, s, false, false, ev)
			local fired = 0
			for k = 1, #ev, 4 do
				if ev[k] == EV.SLING then
					fired += 1
				end
			end
			local b = s.balls[i]
			return b.vx * nx + b.vy * ny, fired
		end
		local out, fired = hit(0.5, 2.0)
		t.eq(fired, 1)
		t.near(out, Physics.SLING_KICK + 2.0 * Layout.MATERIALS.rubber.e, 0.25)
		local _, softFired = hit(0.5, 0.4)
		t.eq(softFired, 0, "too soft a touch")
		local _, endFired = hit(0.04, 2.0)
		t.eq(endFired, 0, "at the very end of the rubber")
	end)

	t.test("PIN-P4: the speed cap holds whatever kicks the ball", function()
		local tbl = Tables.need("pinball_rodent")
		local s = Physics.new(tbl.c, 1)
		local ev: { number } = {}
		local rnd = lcg(3)
		Physics.addBall(s, 0.5, 3.6, 28, 9)
		local top = 0
		for i = 1, 3000 do
			Physics.step(tbl.c, s, rnd() < 0.5, rnd() < 0.5, ev)
			for _, b in s.balls do
				if b.mode == Physics.FREE then
					top = math.max(top, math.sqrt(b.vx * b.vx + b.vy * b.vy))
				end
			end
			if i % 300 == 0 then
				Physics.removeGone(s)
				Physics.addBall(s, 0.4 + rnd(), 3.0, rnd() * 60 - 30, rnd() * 60 - 30)
			end
		end
		t.truthy(top <= Physics.MAX_SPEED + 1e-9, `top speed {top}`)
		t.truthy(top > Physics.MAX_SPEED * 0.9, "the cap was reached")
	end)

	t.test("PIN-P3: at top speed nothing passes through a wall, a post or the cabinet, with one ball or three", function()
		for _, id in Tables.IDS do
			local tbl = Tables.need(id)
			local c = tbl.c
			local rnd = lcg(2024)
			local s = Physics.new(c, 17)
			local ev: { number } = {}
			local px: { number }, py: { number } = {}, {}
			local function throw()
				-- from the open middle of the table, as hard as a ball can go, any way
				local a = rnd() * 2 * math.pi
				Physics.addBall(
					s,
					Layout.XC - 0.1 + rnd() * 0.2,
					1.7 + rnd() * 0.3,
					math.cos(a) * Physics.MAX_SPEED,
					math.sin(a) * Physics.MAX_SPEED
				)
			end
			for _ = 1, 3 do
				throw()
			end
			local worst = 0
			for i = 1, 9600 do
				for k, b in s.balls do
					px[k], py[k] = b.x, b.y
				end
				local n = #s.balls
				local modes: { number } = {}
				for k, b in s.balls do
					modes[k] = b.mode
				end
				table.clear(ev)
				Physics.step(c, s, rnd() < 0.4, rnd() < 0.4, ev)
				for k = 1, n do
					local b = s.balls[k]
					if modes[k] == Physics.FREE and b.mode == Physics.FREE then
						local hit = crossed(c, s, px[k], py[k], b.x, b.y)
						t.eq(hit, 0, `{id}: tick {i}: the ball went through wall {hit} at {b.x}, {b.y}`)
						-- inside the cabinet, and not inside a post or a bumper
						t.truthy(b.x > R - 0.002 and b.x < Layout.WIDTH - R + 0.002, `{id}: x {b.x}`)
						t.truthy(b.y < Layout.LENGTH - R + 0.002, `{id}: y {b.y}`)
						for q = 1, c.nCir do
							local dx, dy = b.x - c.cx[q], b.y - c.cy[q]
							local deep = c.cr[q] + R - math.sqrt(dx * dx + dy * dy)
							worst = math.max(worst, deep)
						end
					end
				end
				if i % 160 == 0 then
					-- fresh balls at top speed, and whatever is still about is thrown again
					Physics.removeGone(s)
					for _, b in s.balls do
						if b.mode == Physics.FREE then
							local a = rnd() * 2 * math.pi
							b.vx, b.vy = math.cos(a) * Physics.MAX_SPEED, math.sin(a) * Physics.MAX_SPEED
							b.asleep = false
						end
					end
					while #s.balls < 3 do
						throw()
					end
				end
			end
			t.truthy(worst < R * 0.5, `{id}: deepest a ball got into a post: {worst}`)
		end
	end)

	t.test("PIN-P3: the ball never passes through a flipper, at rest, held or swinging, from above at any speed", function()
		local tbl = Tables.need("pinball_acorn")
		local c = tbl.c
		local rnd = lcg(5)
		local through, shots = 0, 0
		for trial = 1, 400 do
			local s = Physics.new(c, trial)
			local ev: { number } = {}
			local side = if trial % 2 == 0 then 1 else 2
			local along = 0.1 + rnd() * 0.85
			local tx = c.fpx[side] + c.fmir[side] * along * c.flen[side] * 0.87
			local speed = 3 + rnd() * (Physics.MAX_SPEED - 3)
			local i = Physics.addBall(s, tx + (rnd() - 0.5) * 0.3, c.fpy[side] + 0.9, 0, 0)
			local b = s.balls[i]
			-- aimed at a point on the flipper
			local ax, ay = tx - b.x, (c.fpy[side] - 0.05) - b.y
			local d = math.sqrt(ax * ax + ay * ay)
			b.vx, b.vy = ax / d * speed, ay / d * speed
			local mode = trial % 3 -- 0 at rest, 1 held up, 2 flipped as the ball arrives
			local flipAt = math.floor(0.75 / speed * 240) - math.floor(rnd() * 8)
			if mode == 1 then
				for _ = 1, 60 do
					Physics.step(c, s, true, true, ev)
				end
				b.x, b.y = tx + (rnd() - 0.5) * 0.3, c.fpy[side] + 0.9
				b.vx, b.vy = ax / d * speed, ay / d * speed
			end
			for k = 1, 90 do
				local press = mode == 1 or (mode == 2 and k >= flipAt)
				local along0, side0 = overFlipper(c, s, side, b)
				Physics.step(c, s, press, press, ev)
				if b.mode ~= Physics.FREE then
					break
				end
				-- on the other side of the flipper's middle line than a tick ago, while over its length both
				-- times, is through it
				local along1, side1 = overFlipper(c, s, side, b)
				if
					side0 * side1 < 0
					and along0 > 0.03
					and along0 < 0.97
					and along1 > 0.03
					and along1 < 0.97
				then
					through += 1
					break
				end
			end
			shots += 1
		end
		t.eq(through, 0, "balls that went through a flipper")
		t.eq(shots, 400)
	end)

	t.test("a rest state is reached: a ball left alone on a dead table drains or comes to rest, every time", function()
		for _, id in Tables.IDS do
			local tbl = Tables.need(id)
			local rnd = lcg(31)
			local unsettled = 0
			for _ = 1, 40 do
				local s = Physics.new(tbl.c, 1)
				s.dead = true
				local ev: { number } = {}
				local i = Physics.addBall(s, Layout.XC - 0.2 + rnd() * 0.4, 1.6 + rnd() * 0.4, rnd() * 16 - 8, rnd() * 14 - 2)
				local b = s.balls[i]
				local done = false
				for _ = 1, 240 * 40 do
					Physics.step(tbl.c, s, false, false, ev)
					if b.mode == Physics.GONE or b.asleep then
						done = true
						break
					end
				end
				if not done then
					unsettled += 1
				end
			end
			t.eq(unsettled, 0, `{id}: balls still moving after 40 s`)
		end
	end)

	t.test("PIN-P3: a ball in a corner comes to rest and stays put (no jitter)", function()
		-- the foot of the shooter lane is a corner: the plunger's rubber and the lane's walls
		local tbl = Tables.need("pinball_acorn")
		local s = Physics.new(tbl.c, 1)
		local ev: { number } = {}
		local i = Physics.addBall(s, Layout.LANE_X + 0.01, 1.2, 0.3, 0)
		local b = s.balls[i]
		for _ = 1, 240 * 6 do
			Physics.step(tbl.c, s, false, false, ev)
		end
		t.truthy(b.asleep, "asleep on the plunger")
		local x, y = b.x, b.y
		for _ = 1, 480 do
			Physics.step(tbl.c, s, false, false, ev)
		end
		t.eq(b.x, x)
		t.eq(b.y, y)
		t.eq(b.vx, 0)
		t.eq(b.vy, 0)
		t.near(y, tbl.def.plunger.y, 0.002, "resting on the plunger")
	end)

	t.test("the gate at the head of the shooter lane is one-way: out, never back in", function()
		local tbl = Tables.need("pinball_acorn")
		local c = tbl.c
		-- out: a launched ball leaves the lane
		local s = Physics.new(c, 1)
		local ev: { number } = {}
		local p = tbl.def.plunger
		local i = Physics.addBall(s, p.x, p.y, 0, p.vMax)
		local b = s.balls[i]
		local left = false
		for _ = 1, 480 do
			Physics.step(c, s, false, false, ev)
			if b.x < Layout.FIELD_X1 then
				left = true
				break
			end
		end
		t.truthy(left, "the ball left the lane")
		-- back: a ball dropped onto the gate from the arch rolls off it into the playfield
		local s2 = Physics.new(c, 1)
		s2.dead = true
		local j = Physics.addBall(s2, Layout.LANE_X, 4.0, 0, -2)
		local b2 = s2.balls[j]
		local lowest = 9
		for _ = 1, 720 do
			Physics.step(c, s2, false, false, ev)
			if b2.x > Layout.FIELD_X1 then
				lowest = math.min(lowest, b2.y)
			end
			if b2.mode ~= Physics.FREE then
				break
			end
		end
		t.truthy(lowest > 3.4, `it stayed above the gate while over the lane ({lowest})`)
		t.truthy(b2.x < Layout.FIELD_X1 or b2.mode ~= Physics.FREE, "and ended up on the playfield")
	end)

	t.test("a ramp costs speed: a fast ball rides it to the end, a slow one rolls back out of the mouth", function()
		local tbl = Tables.need("pinball_rodent")
		local c = tbl.c
		local rail = c.rails[1]
		local function shoot(speed: number): (boolean, number, number)
			local s = Physics.new(c, 1)
			s.dead = true
			local ev: { number } = {}
			local tx, ty = rail.tx[1], rail.ty[1]
			local i = Physics.addBall(s, rail.x[1] - tx * 0.12, rail.y[1] - ty * 0.12, tx * speed, ty * speed)
			local b = s.balls[i]
			local slowest = speed
			local highest = 0
			for _ = 1, 240 * 8 do
				table.clear(ev)
				Physics.step(c, s, false, false, ev)
				if b.mode == Physics.RAIL then
					slowest = math.min(slowest, b.v)
					highest = math.max(highest, b.z)
				end
				for k = 1, #ev, 4 do
					if ev[k] == EV.RAIL_OUT then
						return ev[k + 2] == 1, slowest, highest
					end
				end
			end
			return false, slowest, highest
		end
		local made, slowest, highest = shoot(9)
		t.truthy(made, "a hard shot makes the ramp")
		t.truthy(slowest < 9 * 0.8, `the climb cost speed ({slowest})`)
		t.truthy(highest > 0.25, "it went up off the playfield")
		local weak = shoot(2.2)
		t.falsy(weak, "a weak shot rolls back")
	end)

	t.test("a kick-out hole swallows a ball slow enough, holds it, throws it back out and takes no second ball", function()
		local tbl = Tables.need("pinball_rodent")
		local c = tbl.c
		local sc = tbl.def.saucers[1]
		local s = Physics.new(c, 4)
		local ev: { number } = {}
		local i = Physics.addBall(s, sc.x - 0.02, sc.y - 0.12, 0.3, 2.0)
		local b = s.balls[i]
		local held, out = 0, 0
		for tick = 1, 240 * 4 do
			table.clear(ev)
			Physics.step(c, s, false, false, ev)
			for k = 1, #ev, 4 do
				if ev[k] == EV.SAUCER then
					held = tick
					-- a second ball arriving while the hole is full is not taken
					Physics.addBall(s, sc.x, sc.y - 0.1, 0, 1.0)
				elseif ev[k] == EV.EJECT then
					out = tick
				end
			end
			if out > 0 then
				break
			end
		end
		t.truthy(held > 0, "swallowed")
		t.near(out - held, sc.holdTicks, 1, "held for its time")
		t.eq(b.mode, Physics.FREE)
		t.truthy(b.vy < -2, "thrown down the table")
		t.eq(s.balls[2].mode, Physics.FREE, "the second ball stayed out")
		-- too fast, the ball skips over the hole
		local s2 = Physics.new(c, 4)
		local j = Physics.addBall(s2, sc.x - 0.3, sc.y, sc.maxSpeed * 1.5, 0)
		for _ = 1, 20 do
			Physics.step(c, s2, false, false, ev)
		end
		t.neq(s2.balls[j].mode, Physics.HELD)
	end)

	t.test("a spinner spins as fast as the ball went through it, counts its turns and runs down", function()
		local tbl = Tables.need("pinball_acorn")
		local c = tbl.c
		local sp = tbl.def.sensors[tbl.ix.sensor.spinner]
		local function turns(speed: number): number
			local s = Physics.new(c, 1)
			s.dead = true
			local ev: { number } = {}
			Physics.addBall(s, (sp.x1 + sp.x2) / 2, sp.y1 - 0.15, 0, speed)
			local n = 0
			for _ = 1, 240 * 8 do
				table.clear(ev)
				Physics.step(c, s, false, false, ev)
				for k = 1, #ev, 4 do
					if ev[k] == EV.SPIN then
						n += 1
					end
				end
			end
			t.eq(s.spinW[c.spinners[1]], 0, "it has stopped")
			return n
		end
		local slow, fast = turns(3), turns(9)
		t.truthy(slow >= 1, `a slow ball turns it ({slow})`)
		t.truthy(fast > slow * 2, `a fast ball turns it many times ({fast} against {slow})`)
		t.truthy(fast <= 40, "but not for ever")
	end)

	t.test("two balls click off each other and neither is left inside the other", function()
		local c = shell()
		local s = Physics.new(c, 1)
		local ev: { number } = {}
		local i = Physics.addBall(s, 0.8, 2.5, 3, 0)
		local j = Physics.addBall(s, 1.4, 2.5, -3, 0)
		local clicked = false
		for _ = 1, 60 do
			table.clear(ev)
			Physics.step(c, s, false, false, ev)
			for k = 1, #ev, 4 do
				if ev[k] == EV.BALLS then
					clicked = true
				end
			end
			local a, b = s.balls[i], s.balls[j]
			local d = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
			t.truthy(d > 2 * R - 0.005, "apart")
		end
		t.truthy(clicked)
		t.truthy(s.balls[i].vx < 0 and s.balls[j].vx > 0, "they traded their speed")
	end)

	t.test("performance: a step with a ball in play costs a few microseconds", function()
		local tbl = Tables.need("pinball_space")
		local s = Physics.new(tbl.c, 1)
		local ev: { number } = {}
		local rnd = lcg(1)
		local started = os.clock()
		local steps = 0
		for round = 1, 20 do
			Physics.removeGone(s)
			if #s.balls < 3 then
				Physics.addBall(s, 0.5 + rnd(), 2.2 + rnd() * 2, rnd() * 10 - 5, rnd() * 10 - 5)
			end
			for i = 1, 1200 do
				Physics.step(tbl.c, s, (i + round) % 100 < 30, i % 130 < 40, ev)
				steps += 1
			end
			table.clear(ev)
		end
		local micros = (os.clock() - started) / steps * 1e6
		-- 240 steps a second at this cost is well under one per cent of a frame's budget
		t.truthy(micros < 60, `{micros} microseconds a step`)
	end)
end
