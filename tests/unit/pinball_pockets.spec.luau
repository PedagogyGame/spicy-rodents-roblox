--!strict
-- Minigames/Pinball: nowhere to get stuck (checklist PIN-P3 "never sticks or jitters in a corner"), and what
-- that takes of the physics and of the three layouts:
--   * a ball comes to rest only where it is held from both sides (a cradle, a corner, the plunger's tip): rolling
--     resistance cannot hold it on a slope or balanced on a post, however gentle the slope;
--   * with the flippers down there is no such place on any of the three tables: from every spot a ball can
--     reach it rolls on and drains, and none is batted round a loop for ever (Survey);
--   * the inlane guide runs onto the flipper's face in one line: a ball fed down the inlane stays on the rubber
--     all the way to the tip, slow or fast (it never hops the flipper, never stops where guide and hub meet);
--   * a post on the end of a wall sits flush (Layout.endPost);
--   * coils vary by a seeded tenth (the machine's own launch, the bumpers, the slingshots), so the same loop is
--     never played twice the same way, and the same seed still gives the same game.
local Layout = require("@shared/Minigames/Pinball/Layout")
local Machine = require("@shared/Minigames/Pinball/Machine")
local Physics = require("@shared/Minigames/Pinball/Physics")
local Survey = require("@shared/Minigames/Pinball/Survey")
local Tables = require("@shared/Minigames/Pinball/Tables")
local Test = require("../lib/Test")

local R = Layout.BALL_R
local CUE = Machine.CUE

-- a bare cabinet with whatever the test stands in it
local function bare(build: (def: Layout.TableDef) -> ()): Layout.Compiled
	local def = Layout.new("test", "TEST")
	Layout.addShell(def)
	build(def)
	return Layout.compile(def)
end

local function settle(c: Layout.Compiled, s: Physics.State, seconds: number)
	local ev: { number } = {}
	for _ = 1, math.floor(seconds * Physics.HZ) do
		Physics.step(c, s, false, false, ev)
		table.clear(ev)
	end
end

return function(t: Test.T)
	t.test("PIN-P4: rolling resistance cannot hold a ball on a slope, however gentle: it rolls off and away", function()
		-- a long wall that falls one stud in sixty across the table (under one degree)
		local c = bare(function(def)
			Layout.wall(def, "wood", { 0.4, 2.02, 1.6, 2.0 })
		end)
		local s = Physics.new(c, 1)
		local i = Physics.addBall(s, 0.6, 2.02 + R + 0.001, 0, 0)
		local b = s.balls[i]
		settle(c, s, 3)
		t.truthy(b.x > 0.62, `it has started down the wall ({b.x})`)
		t.falsy(b.asleep, "a ball leaning on one thing is not at rest")
		settle(c, s, 30)
		t.truthy(b.y < 1.5, `and rolled off its end ({b.x}, {b.y})`)
	end)

	t.test("PIN-P3: a ball set on the crown of a post rolls off it; it never goes to sleep up there", function()
		local c = bare(function(def)
			Layout.post(def, 1.1, 2.0, 0.03)
		end)
		for _, off in { 0.0005, -0.0005, 0.004, -0.004 } do
			local s = Physics.new(c, 1)
			local i = Physics.addBall(s, 1.1 + off, 2.0 + 0.03 + R + 0.0005, 0, 0)
			local b = s.balls[i]
			settle(c, s, 6)
			t.falsy(b.asleep, `set down {off} off the crown: not asleep`)
			t.truthy(b.y < 1.9, `set down {off} off the crown: it fell off ({b.y})`)
			t.eq(b.x > 1.1, off > 0, "to the side it leaned")
		end
	end)

	t.test("PIN-P3: held from both sides a ball does come to rest, and stays: a valley, a level floor", function()
		local valley = bare(function(def)
			Layout.wall(def, "wood", { 0.8, 2.2, 1.1, 2.0, 1.4, 2.2 })
		end)
		local s = Physics.new(valley, 1)
		local b = s.balls[Physics.addBall(s, 0.9, 2.4, 0, 0)]
		settle(valley, s, 12)
		t.truthy(b.asleep, "asleep in the valley")
		t.near(b.x, 1.1, 0.01)
		local x, y = b.x, b.y
		settle(valley, s, 5)
		t.eq(b.x, x, "and does not creep")
		t.eq(b.y, y)
		-- the plunger's tip is a level floor: one thing under the ball, and it is enough
		local tbl = Tables.need("pinball_acorn")
		local m = Machine.new(tbl, 1, 1)
		local out: { number } = {}
		for _ = 1, 240 do
			Machine.step(tbl, m, 0, out)
		end
		t.truthy(m.phys.balls[1].asleep, "the ball on the plunger is at rest")
	end)

	t.test(
		"PIN-P3: no dead spots: on every table a ball let go anywhere it can reach, flippers down, rolls on and drains",
		function()
			for _, id in Tables.IDS do
				local tbl = Tables.need(id)
				local report = Survey.rests(tbl, 3)
				t.truthy(report.spots > 3000, `{id}: {report.spots} spots can be reached`)
				t.truthy(report.tried > 1000, `{id}: {report.tried} of them tried`)
				local where = ""
				if #report.rest > 0 then
					where = string.format(" (first at %.2f, %.2f)", report.rest[1], report.rest[2])
				end
				t.eq(#report.rest // 2, 0, `{id}: places a ball came to rest by itself{where}`)
				if #report.moving > 0 then
					where = string.format(" (first from %.2f, %.2f)", report.moving[1], report.moving[2])
				end
				t.eq(#report.moving // 2, 0, `{id}: balls still going round after {Survey.SECONDS} s{where}`)
				t.eq(report.drained, report.tried)
				t.truthy(report.slowest < 30, `{id}: the slowest took {report.slowest} s to drain`)
			end
		end
	)

	t.test("the survey reaches the whole playfield and nothing behind it; a known pocket is found", function()
		local tbl = Tables.need("pinball_acorn")
		local spots = Survey.reachable(tbl)
		local top, lane, low = false, false, false
		for i = 1, #spots, 2 do
			local x, y = spots[i], spots[i + 1]
			top = top or y > 4.4
			lane = lane or (x > Layout.FIELD_X1 and y < 1)
			low = low or y < 0.6
			-- behind the A-C-O-R-N bank is closed
			t.falsy(x < 0.12 and y > 2.3 and y < 2.8, `a spot behind the bank: {x}, {y}`)
		end
		t.truthy(top and lane and low, "the top lanes, the shooter lane and the flippers are all reached")
		-- a valley across the middle of a bare cabinet is a dead spot, and drop() says so
		local def = Layout.new("pocket", "POCKET")
		Layout.addShell(def)
		Layout.addBottom(def, { gap = 0.18, outlane = 0.16, inlane = 0.17, pivotY = 0.62 })
		Layout.wall(def, "wood", { 0.8, 2.2, 1.1, 2.0, 1.4, 2.2 })
		local pocket: Machine.Table = {
			id = def.id,
			title = def.title,
			def = def,
			ix = Layout.index(def),
			c = Layout.compile(def),
			sheet = tbl.sheet,
		}
		local what, x = Survey.drop(pocket, 0.9, 2.4, 0, 20)
		t.eq(what, "rest")
		t.near(x, 1.1, 0.01)
		t.truthy(#Survey.rests(pocket, 4, 20).rest > 0, "and the survey of that table finds it")
		t.eq((Survey.drop(pocket, 0.3, 2.4, 0, 20)), "drained", "beside the valley a ball drains")
	end)

	t.test(
		"PIN-P2: the inlane guide runs onto the flipper's face: a ball fed down the inlane stays on the rubber to the tip",
		function()
			for _, id in Tables.IDS do
				local tbl = Tables.need(id)
				local c = tbl.c
				for i = 1, 2 do
					local lane = tbl.def.sensors[if i == 1 then tbl.ix.sensor.inlane_l else tbl.ix.sensor.inlane_r]
					-- let go at the top of the inlane (slow), and thrown down it (as a ramp's wire drops it)
					for _, vy in { 0, -1.5 } do
						local s = Physics.new(c, 1)
						local ev: { number } = {}
						local b = s.balls[Physics.addBall(s, (lane.x1 + lane.x2) / 2, lane.y1 + 0.2, 0, vy)]
						-- the flipper's face at rest: along its axis, and off its surface
						local a = c.frest[i]
						local dx, dy = c.fmir[i] * math.cos(a), math.sin(a)
						local nx, ny = -dy, dx
						if ny < 0 then
							nx, ny = -nx, -ny
						end
						local worst, furthest, slowest = 0, 0, math.huge
						for _ = 1, 240 * 8 do
							Physics.step(c, s, false, false, ev)
							if b.mode ~= Physics.FREE then
								break
							end
							local qx, qy = b.x - c.fpx[i], b.y - c.fpy[i]
							local along = (qx * dx + qy * dy) / c.flen[i]
							if along > 0 and along < 1 then
								local surface = c.frb[i] + (c.frt[i] - c.frb[i]) * along
								local gap = qx * nx + qy * ny - R - surface
								worst = math.max(worst, gap)
								furthest = math.max(furthest, along)
								slowest = math.min(slowest, math.sqrt(b.vx * b.vx + b.vy * b.vy))
							end
						end
						local what = `{id} flipper {i}, let go at {vy}`
						t.eq(b.mode, Physics.GONE, `{what}: it rolled off the tip and drained`)
						t.truthy(furthest > 0.95, `{what}: it rolled the whole flipper ({furthest})`)
						-- (thrown down the lane it lands on the guide with a bounce, which has died to a hair by
						-- the time it is on the flipper; let go, it never leaves the rubber at all)
						t.truthy(
							worst < (if vy == 0 then 0.012 else 0.02),
							`{what}: it never left the rubber by more than a hair ({worst})`
						)
						t.truthy(slowest > 0.3, `{what}: it never stopped on the way ({slowest})`)
					end
				end
			end
		end
	)

	t.test(
		"Layout.endPost: the post sits back from the wall's end, its crown flush with the wall's upper face",
		function()
			local def = Layout.new("test", "TEST")
			-- a wall that falls to the right, and one that falls to the left
			for _, w in { { 0.5, 2.3, 1.0, 2.0 }, { 1.9, 2.3, 1.4, 2.0 } } do
				local before = #def.posts
				Layout.endPost(def, w[3], w[4], w[1], w[2], 0.022)
				t.eq(#def.posts, before + 1)
				local p = def.posts[#def.posts]
				t.eq(p.r, 0.022)
				local dx, dy = w[3] - w[1], w[4] - w[2]
				local l = math.sqrt(dx * dx + dy * dy)
				local nx, ny = -dy / l, dx / l
				if ny < 0 then
					nx, ny = -nx, -ny
				end
				-- the post's centre is one radius under the wall's line, straight under the wall's end
				t.near((p.x - w[3]) * nx + (p.y - w[4]) * ny, -0.022, 1e-9, "one radius below the face")
				t.near((p.x - w[3]) * dx + (p.y - w[4]) * dy, 0, 1e-9, "under the end")
			end
			-- and so a ball that dribbles down the wall with no speed rolls over the post and on (a post standing
			-- ON the end of the same wall would hold it)
			local function dribble(flush: boolean): boolean
				local c = bare(function(d)
					Layout.wall(d, "wood", { 0.5, 2.3, 1.0, 2.0 })
					if flush then
						Layout.endPost(d, 1.0, 2.0, 0.5, 2.3)
					else
						Layout.post(d, 1.0, 2.0)
					end
				end)
				-- set down with no speed on the wall, 0.06 studs up it from its end (just where a post standing on
				-- the end would meet the ball)
				local l = math.sqrt(0.34)
				local nx, ny = 0.3 / l, 0.5 / l
				local ux, uy = -0.5 / l, 0.3 / l
				local s = Physics.new(c, 1)
				local b = s.balls[Physics.addBall(
					s,
					1.0 + ux * 0.06 + nx * (R + 0.001),
					2.0 + uy * 0.06 + ny * (R + 0.001),
					0,
					0
				)]
				settle(c, s, 10)
				return b.y < 1.8
			end
			t.truthy(dribble(true), "flush: the ball rolls on")
			t.falsy(
				dribble(false),
				"a post on the wall's end is a notch (which is why no table has one on a gentle wall)"
			)
		end
	)

	t.test(
		"the machine's own launch is never twice the same strength, and always the same for the same seed",
		function()
			local tbl = Tables.need("pinball_rodent")
			local function launches(seed: number): { number }
				local m = Machine.new(tbl, seed, 1)
				local out: { number } = {}
				local got: { number } = {}
				-- abandon the ball: the machine launches it itself; then lose it inside the ball save, three times
				Machine.forfeit(tbl, m, out)
				for _ = 1, 4 do
					table.clear(out)
					for _ = 1, 2400 do
						Machine.step(tbl, m, 0, out)
						local found = false
						for i = 1, #out, 3 do
							if out[i] == CUE.PLUNGE and out[i + 1] == 0 then
								table.insert(got, out[i + 2])
								found = true
							end
						end
						table.clear(out)
						if found then
							break
						end
					end
					-- a new machine each time would repeat itself; the same machine goes on down its seeded stream
					m.queue += 1
					for _, b in m.phys.balls do
						b.x, b.y, b.vx, b.vy = Layout.XC, 0.3, 0, -2
						b.asleep = false
					end
				end
				return got
			end
			local a, b, other = launches(5), launches(5), launches(6)
			t.truthy(#a >= 3, `{#a} launches by the machine`)
			t.deepEq(a, b, "the same seed, the same launches")
			local p = tbl.def.plunger
			local distinct: { [number]: boolean } = {}
			for _, pull in a do
				t.truthy(
					pull >= p.autoPull - Machine.AUTO_SPREAD - 1e-9 and pull <= p.autoPull + Machine.AUTO_SPREAD + 1e-9
				)
				t.truthy(pull >= 0 and pull <= 1)
				distinct[pull] = true
			end
			local n = 0
			for _ in distinct do
				n += 1
			end
			t.eq(n, #a, "no two alike")
			t.truthy(a[1] ~= other[1], "another seed, another launch")
		end
	)

	t.test("bumpers and slingshots kick within a tenth of their strength, seeded: never a fixed loop", function()
		local tbl = Tables.need("pinball_acorn")
		local c = tbl.c
		local bump = tbl.def.bumpers[1]
		local function pops(seed: number): { number }
			local s = Physics.new(c, seed)
			local ev: { number } = {}
			local got: { number } = {}
			for _ = 1, 6 do
				for i = #s.balls, 1, -1 do
					s.balls[i] = nil
				end
				local b = s.balls[Physics.addBall(s, bump.x, bump.y + bump.r + R + 0.01, 0, -3)]
				for _ = 1, 4 do
					Physics.step(c, s, false, false, ev)
				end
				table.insert(got, b.vy)
			end
			return got
		end
		local a = pops(9)
		t.deepEq(a, pops(9), "the same seed, the same kicks")
		local lo, hi = math.huge, 0
		for _, v in a do
			lo, hi = math.min(lo, v), math.max(hi, v)
			-- (the ball arrives at 3 studs/s: its rebound off the body, and the ring's kick on top)
			local kick = v - Physics.BUMPER_E * 3
			t.truthy(math.abs(kick - Physics.BUMPER_KICK) <= Physics.BUMPER_KICK * Physics.KICK_JITTER + 0.1, `{v}`)
		end
		t.truthy(hi - lo > 0.1, `six pops are not six copies ({lo} to {hi})`)
		t.truthy(Physics.KICK_JITTER > 0 and Physics.KICK_JITTER <= 0.15)
	end)
end
