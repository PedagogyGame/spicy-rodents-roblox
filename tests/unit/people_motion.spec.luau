--!strict
-- Owner D27 (2026-11-21): "smoothen up the movement of the townsperson and human characters ... waddles, jolts left
-- right, rocks, does not walk or run in a straight smooth line ... a smooth dynamic forward motion, torso led".
-- The numbers, on the real brain helpers and motor (tests/lib/MotionProbe) and the client's drawing
-- (Client/Animation/PeopleMotion):
--   * the server's path: a straight stretch is straight at a steady pace; a step round a post on a lane is a shallow
--     diagonal, eased (it was a sideways slide of up to 18 studs/s started within one frame); a turn at a corner is
--     eased in and out (its rate jumped 4 rad/s within one frame); the legs of the way are walked as before;
--   * the drawing between the poses a client is sent (20 and 10 a second, late by up to 10 ms): no standing still and
--     jumping, a straight line, a continuous turn, the clip's pace steady;
--   * the torso: the clip's roll and yaw of the hips and chest cut to a small counter-swing, a forward lean that
--     grows with the pace, the chest turning into a turn first; a patient with the symptoms still staggers.
local MotionProbe = require("@tests/lib/MotionProbe")
local HumanAIMotor = require("@shared/Movement/HumanAIMotor")
local Common = require("@server/Actors/Brains/Common")
local PeopleMotion = require("@client/Animation/PeopleMotion")
local AnimationDriver = require("@client/Animation/AnimationDriver")

local DT = 1 / 60
local WALK, RUN = MotionProbe.WALK, MotionProbe.RUN

local function delta(a: number, b: number): number
	return (b - a + math.pi) % (2 * math.pi) - math.pi
end

-- how far (x, z) is from the way (0, 0) -> (0, 30) -> q
local function offWay(x: number, z: number, qx: number, qz: number): number
	local function seg(ax: number, az: number, bx: number, bz: number): number
		local ex, ez = bx - ax, bz - az
		local t = math.clamp(((x - ax) * ex + (z - az) * ez) / (ex * ex + ez * ez), 0, 1)
		return math.sqrt((x - ax - ex * t) ^ 2 + (z - az - ez * t) ^ 2)
	end
	return math.min(seg(0, 0, 0, 30), seg(0, 30, qx, qz))
end

type Drawn = {
	stepRipple: number, -- (the fastest frame - the slowest) / the mean pace, over the steady stretch
	still: number, -- frames of it the body did not move
	jump: number, -- studs: the longest move in one frame
	side: number, -- studs off the line, at most (a straight walk along +X)
	lag: number, -- studs behind the newest pose, at most
	clipRipple: number, -- (max - min) / mean of the pace the clip is played at
	yawStep: number, -- rad: the biggest change of the drawn facing in one frame
	yawReversals: number,
	offWay: number, -- studs off the way, at most (a corner)
	past: number, -- studs the drawn body went past where its root came to rest
}

-- The walk as a client draws it at 60 frames a second from the poses it is sent: as sent (`follow` false: the body
-- at the newest pose, the clip's pace the driver's old smoothing of the seen speed), or following
-- (Animation/PeopleMotion.follow).
local function draw(poses: { MotionProbe.Pose }, follow: boolean, qx: number?, qz: number?): Drawn
	local st = PeopleMotion.newFollow()
	local out: Drawn = {
		stepRipple = 0,
		still = 0,
		jump = 0,
		side = 0,
		lag = 0,
		clipRipple = 0,
		yawStep = 0,
		yawReversals = 0,
		offWay = 0,
		past = 0,
	}
	local final, before = poses[#poses], poses[#poses]
	for k = #poses, 1, -1 do
		if Common.dist2d(poses[k].x, poses[k].z, final.x, final.z) > 2 then
			before = poses[k]
			break
		end
	end
	local far = math.max(1e-6, Common.dist2d(before.x, before.z, final.x, final.z))
	local ux, uz = (final.x - before.x) / far, (final.z - before.z) / far
	local i = 1
	local t0, t1 = poses[1].t, poses[#poses].t
	local px, pz, pyaw = poses[1].x, poses[1].z, poses[1].yaw + math.pi
	local seen, turn = 0, 0
	local lo, hi, sum, n = math.huge, 0, 0, 0
	local clipLo, clipHi, clipSum = math.huge, 0, 0
	local rx0, rz0 = px, pz
	for f = 1, math.floor((t1 - t0) / DT) do
		local t = t0 + f * DT
		while i < #poses and poses[i + 1].t <= t do
			i += 1
		end
		local root = poses[i]
		local x, z, yaw = root.x, root.z, root.yaw + math.pi
		local clip
		if follow then
			local dx, dz, dyaw = PeopleMotion.follow(st, x, z, yaw, DT)
			x, z, yaw = x + dx, z + dz, yaw + dyaw
			clip = st.speed
		else
			-- (AnimationDriver's step before D27: the seen speed smoothed over 0.15 s)
			local inst = math.sqrt((root.x - rx0) ^ 2 + (root.z - rz0) ^ 2) / DT
			seen += (inst - seen) * math.min(1, DT / 0.15)
			clip = seen
		end
		rx0, rz0 = root.x, root.z
		local step = math.sqrt((x - px) ^ 2 + (z - pz) ^ 2)
		local dyaw = delta(pyaw, yaw)
		out.jump = math.max(out.jump, step)
		out.yawStep = math.max(out.yawStep, math.abs(dyaw))
		if math.abs(dyaw) > 1e-4 then
			local s = if dyaw > 0 then 1 else -1
			if turn ~= 0 and s ~= turn then
				out.yawReversals += 1
			end
			turn = s
		end
		out.lag = math.max(out.lag, math.sqrt((x - root.x) ^ 2 + (z - root.z) ^ 2))
		if qx and qz then
			out.offWay = math.max(out.offWay, offWay(x, z, qx, qz))
		end
		out.past = math.max(out.past, (x - final.x) * ux + (z - final.z) * uz)
		-- the steady stretch: after the start, before the end
		if t > t0 + 2 and t < t1 - 2 then
			n += 1
			sum += step / DT
			lo, hi = math.min(lo, step / DT), math.max(hi, step / DT)
			clipLo, clipHi, clipSum = math.min(clipLo, clip), math.max(clipHi, clip), clipSum + clip
			out.side = math.max(out.side, math.abs(z - poses[1].z))
			if step < 1e-6 then
				out.still += 1
			end
		end
		px, pz, pyaw = x, z, yaw
	end
	out.stepRipple = (hi - lo) / (sum / n)
	out.clipRipple = (clipHi - clipLo) / (clipSum / n)
	return out
end

return function(t)
	t.test("the server's path: a straight stretch is straight, at a steady pace, facing ahead", function()
		for _, speed in { WALK, RUN } do
			local m = MotionProbe.measure(MotionProbe.lane(speed, nil), "x")
			t.truthy(m.sideMax < 1e-9, `off the line {m.sideMax}`)
			t.eq(m.yawReversals, 0)
			t.truthy(m.crabPeak < 1e-6, `facing {m.crabPeak} off the way`)
			t.near(m.speedMean, speed, 0.01)
			t.truthy(m.speedLow > speed * 0.99, `slowest frame {m.speedLow}`)
		end
	end)

	t.test("the server's path: a step round a post on a lane is a shallow eased diagonal, never a slide", function()
		for _, case in { { WALK, 1.5 }, { WALK, 2.4 }, { RUN, 1.5 }, { RUN, 2.4 } } do
			local speed, off = case[1], case[2]
			local samples = MotionProbe.lane(speed, off)
			local m = MotionProbe.measure(samples, "x")
			print(
				string.format(
					"      %4.1f st/s round a post %.1f aside: sideways %.2f st/s at most, changing %.2f st/s a frame at most (before: %.1f and %.1f); facing %.1f deg off the way at most (before: %.0f)",
					speed,
					off,
					m.sidePeak,
					m.sideSnap,
					8 * off * (1 - math.exp(-8 * DT)) / (8 * DT),
					8 * off * (1 - math.exp(-8 * DT)) / (8 * DT),
					math.deg(m.crabPeak),
					math.deg(math.atan2(8 * off, speed))
				)
			)
			-- no steeper than the motor's slope, started and ended gently
			t.truthy(m.sidePeak <= HumanAIMotor.LANE_SLOPE * speed + 1e-6, `sideways {m.sidePeak}`)
			t.truthy(m.sideSnap <= HumanAIMotor.LANE_ACCEL * speed * DT + 1e-6, `sideways change {m.sideSnap}`)
			t.truthy(math.deg(m.crabPeak) < 12, `facing {math.deg(m.crabPeak)} deg off the way`)
			-- the pace over the ground is the person's own all the way
			t.near(m.speedMean, speed, 0.01)
			t.truthy(m.stepSnap < speed * 0.1 + 0.05, `velocity change {m.stepSnap}`)
			-- aside in time: the whole step by the post, and back on the line after it
			local post = 30 + speed * 2
			for _, s in samples do
				if math.abs(s.x - post) < 1 then
					t.truthy(math.abs(s.z - off) < 0.1, `{s.z} aside at the post (wanted {off})`)
				end
			end
			t.near(samples[#samples].z, 0, 0.02)
		end
	end)

	t.test("the server's path: a turn at a corner is eased in and out, with no snap and no swing back", function()
		for _, speed in { WALK, RUN } do
			for _, degrees in { 45, 90, 150 } do
				local a = math.rad(degrees)
				local qx, qz = math.sin(a) * 30, 30 + math.cos(a) * 30
				local samples = MotionProbe.corner(speed, degrees)
				local m = MotionProbe.measure(samples)
				if degrees == 90 then
					print(
						string.format(
							"      %4.1f st/s round a 90 degree corner: yaw rate %.2f rad/s at most, changing %.2f rad/s a frame at most (before: 4.00 and 4.00)",
							speed,
							m.yawRatePeak,
							m.yawSnap
						)
					)
				end
				t.truthy(m.yawRatePeak <= 4 + 1e-6, `yaw rate {m.yawRatePeak}`)
				t.truthy(m.yawSnap <= HumanAIMotor.TURN_ACCEL * 4 * DT + 1e-6, `yaw rate change {m.yawSnap}`)
				t.eq(m.yawReversals, 0)
				-- the legs of the way are walked as before (World/WalkWay keeps them off the walls)
				local off = 0
				for _, s in samples do
					off = math.max(off, offWay(s.x, s.z, qx, qz))
				end
				t.truthy(off <= Common.LEG_REACH, `{off} studs off the way`)
				-- there, and facing the way it came (the last leg starts LEG_REACH short of the corner)
				local last = samples[#samples]
				t.truthy(Common.dist2d(last.x, last.z, qx, qz) < 1.5, "arrived")
				local from = last
				for k = #samples, 1, -1 do
					if Common.dist2d(samples[k].x, samples[k].z, last.x, last.z) > 5 then
						from = samples[k]
						break
					end
				end
				t.near(delta(last.yaw, math.atan2(last.x - from.x, last.z - from.z)), 0, 0.01)
			end
		end
	end)

	t.test("easeTurn: never past the heading, never faster than the cap, from any start", function()
		for _, cap in { 4, 10 } do
			for _, start in { -3, -1.5, -0.2, 0.01, 0.9, 2.2, 3.1 } do
				for _, rate0 in { 0, cap, -cap } do
					local yaw, rate = start, rate0
					local passed = false
					for _ = 1, 240 do
						local was = delta(yaw, 0)
						local wasRate = rate
						yaw, rate = HumanAIMotor.easeTurn(yaw, rate, 0, cap, DT)
						t.truthy(math.abs(rate) <= cap + 1e-9, `rate {rate}`)
						t.truthy(math.abs(rate - wasRate) <= HumanAIMotor.TURN_ACCEL * cap * DT + 1e-9 or rate == 0)
						-- (a body already turning the other way is slowed first: it may pass once, on its old swing)
						if was * delta(yaw, 0) < 0 and wasRate * was > 0 then
							passed = true
						end
					end
					t.falsy(passed, `passed the heading from {start} at {rate0}`)
					t.near(delta(yaw, 0), 0, 1e-3)
				end
			end
		end
	end)

	t.test("wildlife and bare actors keep the v5.4 steps (the lane lock, the plain turn clamp)", function()
		local ctx = {
			groundAt = function()
				return 0
			end,
			bounds = { minX = -100, maxX = 100, minZ = -100, maxZ = 100 },
		}
		local a = Common.newActor(1, "deer", "x", "Deer", 0, 2, 2.5)
		a.intent.mode = "walk"
		a.intent.tx, a.intent.tz, a.intent.speed = 50, 0, 3
		a.intent.laneAxis, a.intent.laneCoord = "x", 0
		HumanAIMotor.step(a :: any, DT, ctx :: any)
		t.near(a.yaw, 4 * DT, 1e-9) -- (the clamp: 4 rad/s from the first frame)
		t.truthy(a.z < 2 * math.exp(-8 * DT) + 1e-3, `lane lock {a.z}`)
		t.eq((a :: any).side, nil)
		t.eq((a :: any).yawRate, nil)
	end)

	t.test("the drawing: between the poses a client is sent the body moves evenly, in a straight line", function()
		for _, speed in { WALK, RUN } do
			for _, hz in { 20, 10 } do
				local poses = MotionProbe.stream(MotionProbe.lane(speed, nil), hz, 0.01, MotionProbe.rng(7))
				local before, after = draw(poses, false), draw(poses, true)
				print(
					string.format(
						"      %4.1f st/s, %2d poses a second: frame-to-frame pace ripple %3.0f %% -> %4.1f %%; frames stood still %d -> %d; longest move in a frame %.2f -> %.2f studs; the clip's pace ripple %4.1f %% -> %4.2f %%; behind the newest pose %.2f studs at most",
						speed,
						hz,
						before.stepRipple * 100,
						after.stepRipple * 100,
						before.still,
						after.still,
						before.jump,
						after.jump,
						before.clipRipple * 100,
						after.clipRipple * 100,
						after.lag
					)
				)
				-- as sent: the body stands for frames and then jumps a whole step
				t.truthy(before.still > 100, `{before.still} frames still`)
				t.truthy(before.stepRipple > 2, `ripple {before.stepRipple}`)
				-- following: every frame moves, at very nearly the same pace, on the line
				t.eq(after.still, 0)
				t.truthy(after.stepRipple < (if hz == 20 then 0.15 else 0.25), `ripple {after.stepRipple}`)
				t.truthy(after.jump < speed * DT * 1.2, `a move of {after.jump} in a frame`)
				t.truthy(after.side < 1e-6, `off the line {after.side}`)
				-- about one pose behind its root, never past where it stops
				t.truthy(after.lag < speed * (1 / hz + 0.1) + 0.1, `{after.lag} behind`)
				t.truthy(after.past <= 1e-6, `{after.past} past its root's last place`)
				-- and the clip keeps very nearly one pace
				t.truthy(after.clipRipple < before.clipRipple / 2, `clip {before.clipRipple} -> {after.clipRipple}`)
			end
		end
	end)

	t.test("the drawing: a corner is turned continuously and rounded only a little", function()
		for _, speed in { WALK, RUN } do
			local poses = MotionProbe.stream(MotionProbe.corner(speed, 90), 20, 0.01, MotionProbe.rng(11))
			local before, after = draw(poses, false, 30, 30), draw(poses, true, 30, 30)
			print(
				string.format(
					"      %4.1f st/s round a 90 degree corner, 20 poses a second: the facing's biggest change in a frame %.1f -> %.1f deg; longest move in a frame %.2f -> %.2f studs; off the way %.2f studs at most; past the stop %.2f studs",
					speed,
					math.deg(before.yawStep),
					math.deg(after.yawStep),
					before.jump,
					after.jump,
					after.offWay,
					after.past
				)
			)
			t.truthy(after.past < 0.05 + speed * 0.01, `{after.past} studs past where it stopped`)
			t.truthy(after.yawStep < before.yawStep / 2.5, `yaw step {before.yawStep} -> {after.yawStep}`)
			t.truthy(math.deg(after.yawStep) < 4.5, `yaw step {math.deg(after.yawStep)} deg`)
			t.eq(after.yawReversals, 0)
			t.truthy(after.jump < speed * DT * 1.3, `a move of {after.jump} in a frame`)
			t.truthy(after.offWay < Common.LEG_REACH + speed * 0.06, `{after.offWay} off the way`)
		end
	end)

	t.test("the drawing: a body put somewhere else is drawn there at once, and never strays from its root", function()
		local st = PeopleMotion.newFollow()
		for i = 1, 120 do
			PeopleMotion.follow(st, i * 0.3, 0, 0, DT)
		end
		local dx, dz, dyaw = PeopleMotion.follow(st, 500, 40, 1, DT)
		t.eq(dx, 0)
		t.eq(dz, 0)
		t.eq(dyaw, 0)
		t.eq(st.speed, 0)
		-- a root dragged faster than anything walks: the drawn body is kept within MAX_LAG
		for i = 1, 120 do
			local ox, oz = PeopleMotion.follow(st, 500 + i * 5, 40, 1, DT)
			t.truthy(math.sqrt(ox * ox + oz * oz) <= PeopleMotion.MAX_LAG + 1e-9)
		end
		-- and one frame of a second long does not blow up
		local lx, lz = PeopleMotion.follow(st, 1101, 40, 1, 1)
		t.truthy(lx == lx and lz == lz and math.abs(lx) <= PeopleMotion.MAX_LAG + 1e-9)
	end)

	t.test(
		"the torso: the clip's roll, yaw and sideways shift cut to a small counter-swing, the bob kept small",
		function()
			-- a stride of a waddle: the hips rolling 8 degrees and turning 10 either way, shifting 0.2 studs, bobbing 0.25
			local rollPeak, yawPeak, shiftPeak, bobPeak, pitchPeak = 0, 0, 0, 0, 0
			for i = 0, 59 do
				local ph = i / 60 * 2 * math.pi
				local rx, ry, rz, px, py = PeopleMotion.steady(
					math.rad(-6) + math.rad(2) * math.sin(2 * ph),
					math.rad(10) * math.sin(ph),
					math.rad(8) * math.sin(ph),
					0.2 * math.sin(ph),
					0.25 * math.sin(2 * ph),
					1
				)
				rollPeak, yawPeak = math.max(rollPeak, math.abs(rz)), math.max(yawPeak, math.abs(ry))
				shiftPeak, bobPeak = math.max(shiftPeak, math.abs(px)), math.max(bobPeak, math.abs(py))
				pitchPeak = math.max(pitchPeak, math.abs(rx))
			end
			print(
				string.format(
					"      a clip's hips rolling 8 deg, turning 10 deg, shifting 0.20 studs, bobbing 0.25: drawn %.1f deg, %.1f deg, %.2f studs, %.3f studs",
					math.deg(rollPeak),
					math.deg(yawPeak),
					shiftPeak,
					bobPeak
				)
			)
			t.near(math.deg(rollPeak), 8 * PeopleMotion.KEEP, 1e-6)
			t.near(math.deg(yawPeak), 10 * PeopleMotion.KEEP, 1e-6)
			t.near(shiftPeak, 0.2 * PeopleMotion.KEEP, 1e-9)
			t.near(bobPeak, 0.25 * PeopleMotion.BOB_KEEP, 1e-3)
			t.near(math.deg(pitchPeak), 8, 0.02) -- (the clip's own pitch is the clip's)
			t.truthy(math.deg(rollPeak) < 3 and math.deg(yawPeak) < 4, "a few degrees at most")
			t.truthy(PeopleMotion.KEEP > 0.2 and PeopleMotion.KEEP < 0.5, "a small counter-swing stays")
			-- off (standing, sitting, far away): the clip as it is
			local rx, ry, rz, px, py = PeopleMotion.steady(0.1, 0.2, 0.3, 0.4, 0.5, 0)
			t.deepEq({ rx, ry, rz, px, py }, { 0.1, 0.2, 0.3, 0.4, 0.5 })
		end
	)

	t.test("the torso: a forward lean that grows with the pace; the chest turns into a turn first", function()
		t.eq(PeopleMotion.lean(0), 0)
		local walk, flee, sprint = PeopleMotion.lean(WALK), PeopleMotion.lean(RUN), PeopleMotion.lean(28)
		print(
			string.format(
				"      forward lean: %.1f deg at %.0f st/s, %.1f at 17 (a held person's walk), %.1f at %.0f, %.1f at 28 (a sprint)",
				math.deg(walk),
				WALK,
				math.deg(PeopleMotion.lean(17)),
				math.deg(flee),
				RUN,
				math.deg(sprint)
			)
		)
		t.truthy(math.deg(walk) > 1.5 and math.deg(walk) < 4, `walk {math.deg(walk)}`)
		t.truthy(flee > walk and sprint > flee)
		t.near(math.deg(sprint), 7, 1e-6)
		t.near(PeopleMotion.lean(60), sprint, 1e-9)
		local was = 0
		for v = 0, 30, 0.25 do
			local l = PeopleMotion.lean(v)
			t.truthy(l >= was and l - was < math.rad(0.5), `lean steps at {v}`)
			was = l
		end
		-- facing -Z (yaw 0), going off to the left (-X): the chest turns left (+), eased, at most TWIST_MAX
		local tw, step = 0, 0
		for _ = 1, 90 do
			local nx = PeopleMotion.twist(tw, 0, -3, -0.5, DT)
			step = math.max(step, math.abs(nx - tw))
			tw = nx
		end
		t.near(tw, PeopleMotion.TWIST_MAX, 0.01)
		t.truthy(step < math.rad(3.5), `chest turn {math.deg(step)} deg in a frame`)
		-- going straight: none; to the right: the other way; a small angle: half of it
		t.near(PeopleMotion.twist(0, 0, 0, -3, 10), 0, 1e-9)
		t.truthy(PeopleMotion.twist(0, 0, 3, -0.5, 10) < -0.4)
		t.near(PeopleMotion.twist(0, 0, -math.sin(0.4) * 3, -math.cos(0.4) * 3, 10), 0.2, 1e-3)
		-- standing, or walking backwards (a held person): not a turn, on either side of straight back
		t.near(PeopleMotion.twist(0, 0, -0.2, 0, 10), 0, 1e-9)
		t.near(PeopleMotion.twist(0, 0, 0, 3, 10), 0, 1e-9)
		t.near(PeopleMotion.twist(0, 0, 0.01, 3, 10), 0, 1e-9)
		t.near(PeopleMotion.twist(0, 0, -0.01, 3, 10), 0, 1e-9)
		t.near(PeopleMotion.twist(0, 0, -1.5, 3, 10), 0, 1e-9)
	end)

	t.test("a patient with the symptoms still staggers; nobody else does", function()
		local peak = 0
		for i = 0, 600 do
			local roll, pitch = AnimationDriver.sway("symptomatic", i / 60, 1.3)
			peak = math.max(peak, math.abs(roll))
			t.truthy(math.abs(pitch) <= 0.03 + 1e-9)
		end
		t.truthy(math.deg(peak) > 3 and math.deg(peak) < 4.5, `stagger {math.deg(peak)} deg`)
		for _, med in { nil, "carried", "down", "treated" } :: { any } do
			local roll, pitch = AnimationDriver.sway(med, 1.7, 1.3)
			t.eq(roll, 0)
			t.eq(pitch, 0)
		end
	end)
end
