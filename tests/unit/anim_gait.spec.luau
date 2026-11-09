--!strict
-- Procedural gait (Client/Animation/Gait): squirrels bound (front pair together, back pair opposite),
-- fox and deer trot (diagonal pairs together); the swing grows with speed and is still at rest; the
-- phase advances one cycle per stride; the tail sways at rest and while running; climbing speed
-- (3D) animates the same as ground speed. The bob is smooth (no cusps) and small, the head cancels the
-- rock, a hovering speed never pops the pose, and AnimationDriver.settle (the visual root height)
-- follows slopes without lag while easing steps and jitter. Also Client/Render/TownView's
-- nearest-lamp selection and Squirrel.hipOf.
local Gait = require("@client/Animation/Gait")
local AnimationDriver = require("@client/Animation/AnimationDriver")
local Squirrel = require("@client/Controllers/Squirrel")
local TownView = require("@client/Render/TownView")

return function(t)
	t.test("bound vs trot: which legs move together", function()
		local sq = Gait.params("squirrel", 0.9)
		local pose = Gait.pose(math.pi / 2, 16, 0, sq, 3)
		t.truthy(sq.bound)
		t.near(pose.legs.FrontL.upper, pose.legs.FrontR.upper, 0.1)
		t.truthy(pose.legs.FrontL.upper * pose.legs.BackL.upper < 0, "back pair opposite the front")
		local fox = Gait.params("fox", 2.05)
		local fp = Gait.pose(math.pi / 2, 18, 0, fox, 2)
		t.near(fp.legs.FrontL.upper, fp.legs.BackR.upper, 1e-9)
		t.near(fp.legs.FrontL.upper, -fp.legs.FrontR.upper, 1e-9)
	end)

	t.test("swing grows with speed; still legs at rest but the tail sways", function()
		local p = Gait.params("deer", 4.4)
		local rest = Gait.pose(1, 0, 3.7, p, 1)
		for _, leg in rest.legs do
			t.eq(leg.upper, 0)
		end
		t.truthy(math.abs(rest.tail[1].yaw) > 0, "idle tail sway")
		local walk = Gait.pose(math.pi / 2, 4, 0, p, 1)
		local run = Gait.pose(math.pi / 2, 22, 0, p, 1)
		t.truthy(math.abs(run.legs.FrontL.upper) > math.abs(walk.legs.FrontL.upper), "faster swings wider")
		t.truthy(math.abs(run.legs.FrontL.upper) <= p.swing + 1e-9, "bounded")
	end)

	t.test("phase: one cycle per stride, wraps", function()
		local p = Gait.params("squirrel", 0.9)
		local ph = 0
		local steps = 100
		for _ = 1, steps do
			ph = Gait.advance(ph, p.stride, 1 / steps, p) -- one stride in one second
		end
		t.truthy(ph < 1e-6 or math.abs(ph - 2 * math.pi) < 1e-6, `phase {ph}`)
		t.eq(Gait.advance(1, 0, 1, p), 1)
		t.truthy(Gait.PROCEDURAL.squirrel and Gait.PROCEDURAL.deer and Gait.PROCEDURAL.fox)
		t.eq(Gait.PROCEDURAL.human, nil)
	end)

	t.test("bob: smooth and small, never below rest; the head holds its line; no pop near zero speed", function()
		for _, species in { "squirrel", "fox", "deer" } do
			local hip = if species == "squirrel" then 0.9 elseif species == "fox" then 2.05 else 3.8
			local p = Gait.params(species, hip)
			local n = 720
			local prev: number? = nil
			local prevSlope: number? = nil
			local maxBob = 0
			for i = 0, n do
				local phase = 2 * math.pi * i / n
				local pose = Gait.pose(phase, p.runSpeed, 0, p, 3)
				maxBob = math.max(maxBob, pose.bob)
				t.truthy(pose.bob >= -1e-9, `{species} bob below rest`)
				t.near(pose.head, -pose.rock, 0.035, `{species} head follows the rock`)
				if prev then
					local slope = (pose.bob - prev) * n
					if prevSlope then
						-- a cusp (abs(sin)) flips the slope's sign in one step (about 9000 x bob here); a
						-- raised cosine bends at most 4 pi^2 x 2 x bob (about 80 x bob) per step
						t.truthy(math.abs(slope - prevSlope) * n < p.bob * 300, `{species} bob has a cusp at {i}`)
					end
					prevSlope = slope
				end
				prev = pose.bob
			end
			t.truthy(maxBob <= hip * 0.06 + 1e-9, `{species} bob {maxBob} studs is small`)
			-- speed hovering around the old 0.3 threshold changes the pose only a little
			local a = Gait.pose(1.2, 0.29, 5, p, 3)
			local b = Gait.pose(1.2, 0.31, 5, p, 3)
			t.truthy(math.abs(a.legs.FrontL.upper - b.legs.FrontL.upper) < 0.02, `{species} legs pop`)
			t.truthy(math.abs(a.bob - b.bob) < 0.01, `{species} bob pops`)
			t.truthy(math.abs(a.tail[1].yaw - b.tail[1].yaw) < 0.03, `{species} tail pops`)
		end
		t.eq(Gait.moving(0), 0)
		t.eq(Gait.moving(5), 1)
		t.truthy(Gait.params("squirrel", 0.9).tailLift > 0, "a running squirrel streams its tail back")
		t.truthy(Gait.params("deer", 3.8).tailLift < 0, "a running deer flags its tail up")
	end)

	t.test("settle: slopes without lag, steps eased (rising fast), jitter damped, teleports snap", function()
		local dt = 1 / 60
		local fresh = AnimationDriver.newSettle
		-- a steady climb at 5 st/s: the visual height converges onto the root
		local st = fresh()
		local off = 0
		for i = 0, 120 do
			off = AnimationDriver.settle(st, 10 + 5 * i * dt, dt)
		end
		t.truthy(math.abs(off) < 0.02, `slope lag {off}`)
		-- a 0.5 st kerb: below the root at first, never more than MAX_LAG, gone in a quarter second
		st = fresh()
		AnimationDriver.settle(st, 0, dt)
		local first = AnimationDriver.settle(st, 0.5, dt)
		t.truthy(first < -0.3 and first >= -AnimationDriver.MAX_LAG, `kerb first frame {first}`)
		for _ = 1, 15 do
			off = AnimationDriver.settle(st, 0.5, dt)
		end
		t.truthy(math.abs(off) < 0.05, `kerb after 0.25 s {off}`)
		-- a step down eases more slowly (the body stays above the ground on the way)
		st = fresh()
		AnimationDriver.settle(st, 0.5, dt)
		local down = AnimationDriver.settle(st, 0, dt)
		t.truthy(down > 0.3, `step down first frame {down}`)
		local lowest = down
		for _ = 1, 60 do
			lowest = math.min(lowest, AnimationDriver.settle(st, 0, dt))
		end
		t.truthy(lowest > -0.01, `a step down never dips below the ground ({lowest})`)
		-- a kerb never overshoots above the new level
		st = fresh()
		AnimationDriver.settle(st, 0, dt)
		local highest = -math.huge
		for _ = 1, 60 do
			highest = math.max(highest, AnimationDriver.settle(st, 0.5, dt))
		end
		t.truthy(highest < 0.01, `kerb overshoot {highest}`)
		-- +/-0.08 st jitter at several frame periods: the visual body moves a fraction of it
		for _, half in { 1, 2, 3, 4 } do
			st = fresh()
			local lo, hi = math.huge, -math.huge
			for i = 0, 600 do
				local y = 0.08 * (if (i // half) % 2 == 0 then 1 else -1)
				AnimationDriver.settle(st, y, dt)
				if i > 120 then
					lo, hi = math.min(lo, st.y), math.max(hi, st.y)
				end
			end
			t.truthy(hi - lo < 0.16 * 0.2, `jitter every {half} frames: {hi - lo} of 0.16`)
		end
		-- a climb at 18 st/s seen as network updates every third frame: followed, barely lagging
		st = fresh()
		for i = 0, 240 do
			off = AnimationDriver.settle(st, 18 * (i - i % 3) * dt, dt)
		end
		t.truthy(math.abs(off) < 0.25, `staircase climb lag {off}`)
		-- a teleport snaps
		st = fresh()
		AnimationDriver.settle(st, 0, dt)
		t.eq(AnimationDriver.settle(st, 40, dt), 0)
	end)

	t.test("Squirrel.hipOf: the body's HipHeight, else the measured gap", function()
		local attrs: { [string]: any } = { HipHeight = 0.9 }
		local body: any = {
			GetAttribute = function(_self: any, k: string): any
				return attrs[k]
			end,
		}
		t.eq(Squirrel.hipOf(body, 0.1), 0.9)
		attrs.HipHeight = nil
		t.eq(Squirrel.hipOf(body, 0.5), 0.5)
		t.eq(Squirrel.hipOf(body, 9), 3)
	end)

	t.test("TownView.nearest: nearest first, within the radius, at most max", function()
		local pts = { { 0, 0 }, { 10, 0 }, { 5, 0 }, { 500, 0 } }
		local pick = TownView.nearest(pts, 6, 0, 2, 100)
		t.eq(#pick, 2)
		t.eq(pick[1], 3)
		t.eq(pick[2], 2)
		t.eq(#TownView.nearest(pts, 0, 0, 10, 100), 3)
	end)
end
