--!strict
-- tests/unit/liveliness.spec.luau
-- Client/Animation/Liveliness: how a hero squirrel answers its own movement (owner 2026-11-11, of the
-- squirrel seen from behind: "rigid, unalive"). What is pinned: a turn bends the spine into it, counter-turns
-- the pelvis, banks the shoulders more at speed, turns the head first and keeps it level, and leaves the
-- tail behind, root before tip, to spring back past the middle; a stop dips the nose, folds the fore legs
-- under it, throws the tail up, and all of it settles past level; a leap pitches along its flight and its
-- landing squashes the body; a slope pitches it; breathing quickens with a sprint and when winded; the
-- ordinary squirrel flicks and glances when it stands and the Spicy Rodent keeps to its own twitches; and
-- all of it is bounded whatever comes in, the same at any frame rate, back at rest when the body is, and
-- the same every time.

local AnimationDriver = require("@client/Animation/AnimationDriver")
local Creep = require("@client/Animation/Creep")
local Liveliness = require("@client/Animation/Liveliness")

local P = Liveliness.P
local LIMIT = Liveliness.LIMIT
local SPINE = { "Spine1", "Spine2", "Spine3", "Chest" }

type Input = Liveliness.Input

local function input(over: { [string]: any }?): Input
	local i: Input = { speed = 0, yawRate = 0, vy = 0, mode = "ground" }
	if over then
		for k, v in over do
			(i :: any)[k] = v
		end
	end
	return i
end

-- run `seconds` at `hz` frames a second; what(t) is what comes in at the END of the frame that ends at t
local function run(
	st: Liveliness.State,
	from: number,
	seconds: number,
	hz: number,
	what: (t: number) -> Input,
	each: ((t: number, pose: Liveliness.Pose) -> ())?
)
	local n = math.floor(seconds * hz + 0.5)
	for i = 1, n do
		local t = from + i / hz
		local pose = Liveliness.step(st, what(t), 1 / hz)
		if each then
			each(t, pose)
		end
	end
end

local function at(pose: Liveliness.Pose, bone: string, k: number): number
	local r = pose[bone]
	return if r then r[k] or 0 else 0
end

local function sum(pose: Liveliness.Pose, bones: { string }, k: number): number
	local s = 0
	for _, b in bones do
		s += at(pose, b, k)
	end
	return s
end

local TAILS = {}
for i = 1, 8 do
	TAILS[i] = `Tail{i}`
end

-- the limit of each bone the layer may move
local function limitOf(bone: string): { number }?
	if bone == "Root" then
		return LIMIT.root
	elseif bone == "Hips" then
		return LIMIT.hips
	elseif table.find(SPINE, bone) then
		return LIMIT.spine
	elseif bone == "Neck" or bone == "Head" then
		return LIMIT.neck
	elseif bone == "EarL" or bone == "EarR" then
		return LIMIT.ear
	elseif string.sub(bone, 1, 4) == "Tail" then
		return LIMIT.tail
	elseif string.find(bone, "_") then
		return LIMIT.leg
	end
	return nil
end

local function checkBounds(t: any, pose: Liveliness.Pose, why: string)
	for bone, r in pose do
		local limit = limitOf(bone)
		t.truthy(limit ~= nil, `{why}: {bone} is not a bone this layer moves`)
		for k = 1, 3 do
			local v = r[k]
			t.truthy(v == v and math.abs(v) <= (limit :: { number })[k] + 1e-9, `{why}: {bone}[{k}] = {v}`)
		end
		if bone == "Root" then
			t.truthy(r[4] == 0 and r[6] == 0, `{why}: the root only moves up and down`)
			t.truthy(r[5] == r[5] and r[5] >= -LIMIT.rootDown and r[5] <= LIMIT.rootUp, `{why}: root offset {r[5]}`)
		else
			t.eq(#r, 3, `{why}: {bone} carries a rotation only`)
		end
		if string.sub(bone, 1, 4) == "Tail" then
			t.truthy(r[1] <= LIMIT.tailDown + 1e-9, `{why}: {bone} pushed down {r[1]}`)
		end
	end
end

-- a quarter turn to the left in 0.3 s, as the motor turns it: the yaw rate rises and falls at 13/s
local function quarterTurn(t: number, from: number): number
	local target = if t >= from and t < from + 0.3 then 5.2 else 0
	local since = t - (if target > 0 then from else from + 0.3)
	if t < from then
		return 0
	elseif target > 0 then
		return 5.2 * (1 - math.exp(-13 * since))
	end
	return 5.2 * (1 - math.exp(-13 * 0.3)) * math.exp(-13 * since)
end

return function(t: any)
	t.test(
		"a turn: the spine bends into it, the pelvis the other way, the shoulders bank, the head stays level",
		function()
			local st = Liveliness.new(3, "rodent")
			local headHalf: number?, bendHalf: number? = nil, nil
			local peak: Liveliness.Pose = {}
			run(st, 0, 0.6, 60, function(_now)
				return input({ speed = 33, yawRate = 4, roll = 0.14 })
			end, function(now, pose)
				-- (their steady values, from the tuning: the head is past half of its own first)
				local headYaw = at(pose, "Neck", 2) + at(pose, "Head", 2)
				local bend = sum(pose, SPINE, 2)
				if
					headHalf == nil
					and headYaw > 0.5 * P.turn.head.max * math.tanh(P.turn.head.gain * 4 / P.turn.head.max)
				then
					headHalf = now
				end
				if
					bendHalf == nil
					and bend > 0.5 * P.turn.bend.max * math.tanh(P.turn.bend.gain * 4 / P.turn.bend.max)
				then
					bendHalf = now
				end
				peak = table.clone(pose)
				for bone, r in pose do
					peak[bone] = table.clone(r)
				end
			end)
			local bend = sum(peak, SPINE, 2)
			t.truthy(bend > 0.25 and bend < 0.5, `the chest turns {bend} rad into a 4 rad/s turn to the left`)
			t.truthy(at(peak, "Hips", 2) < -0.08, "the pelvis counter-turns")
			t.near(at(peak, "Hips", 2), -P.turn.hips * bend, 1e-6)
			for i, name in SPINE do
				t.near(at(peak, name, 2), bend * P.turn.share[i], 1e-6, `{name} takes its share`)
			end
			local headYaw = at(peak, "Neck", 2) + at(peak, "Head", 2)
			t.truthy(headYaw > 0.15 and headYaw < 0.36, `the head turns {headYaw} rad further in`)
			t.truthy(
				headHalf and bendHalf and headHalf < bendHalf,
				`the head goes first ({headHalf} s, the spine {bendHalf} s)`
			)
			local lean = sum(peak, SPINE, 3)
			t.truthy(lean > 0.06 and lean < 0.22, `the shoulders bank {lean} rad into it`)
			-- the head takes back most of the roll the body has (the drawn lean and this bank)
			local headRoll = at(peak, "Neck", 3) + at(peak, "Head", 3)
			t.near(headRoll, -P.turn.keepLevel * (0.14 + lean), 1e-6)
			-- a turn to the right mirrors it
			local other = Liveliness.new(3, "rodent")
			local mirrored: Liveliness.Pose = {}
			run(other, 0, 0.6, 60, function(_now)
				return input({ speed = 33, yawRate = -4, roll = -0.14 })
			end, function(_now, pose)
				mirrored = pose
			end)
			t.near(sum(mirrored, SPINE, 2), -bend, 1e-9)
			t.truthy(mirrored.Root ~= nil)
			t.near(other.tailYaw[5], -st.tailYaw[5], 1e-9, "the tail too (under its ripple, which is the seed's)")
			-- slower, the same turn banks less; standing on end (a trunk) it is not answered at all
			local slow = Liveliness.new(3, "rodent")
			local slowLean = 0
			run(slow, 0, 0.6, 60, function(_now)
				return input({ speed = 6, yawRate = 4 })
			end, function(_now, pose)
				slowLean = sum(pose, SPINE, 3)
			end)
			t.truthy(slowLean > 0.01 and slowLean < 0.7 * lean, `at a creep it banks {slowLean}`)
			local trunk = Liveliness.new(3, "rodent")
			run(trunk, 0, 0.6, 60, function(_now)
				return input({ speed = 10, yawRate = 4, mode = "trunk", pitch = 1.43, roll = 2 })
			end, function(_now, pose)
				t.near(sum(pose, SPINE, 2), 0, 1e-9)
				t.near(at(pose, "Head", 2), 0, 1e-9)
				t.near(at(pose, "Head", 3), 0, 1e-9, "nor is a roll read off a body standing on end")
				t.near(trunk.tailYaw[4], 0, 1e-9)
			end)
		end
	)

	t.test("the tail is left behind in a turn, root before tip, then catches up and swings past the middle", function()
		local st = Liveliness.new(0, "rodent")
		local firstAt: { number } = {}
		local peakAt: { number }, peak: { number } = {}, { 0, 0, 0, 0, 0, 0, 0, 0 }
		local crossedAt: { number } = {}
		local bendPeak, bendPeakAt = 0, 0
		local trail, trailAt = 0, 0
		-- (walking pace: the tail's ripple at speed is not in the way of the reading)
		run(st, 0, 3.5, 120, function(now)
			return input({ speed = 6, yawRate = quarterTurn(now, 0.5) })
		end, function(now, pose)
			local bend = sum(pose, SPINE, 2)
			if bend > bendPeak then
				bendPeak, bendPeakAt = bend, now
			end
			local all = sum(pose, TAILS, 2)
			if all < trail then
				trail, trailAt = all, now
			end
			for i = 1, 8 do
				local y = at(pose, TAILS[i], 2)
				t.truthy(now > 0.5 or math.abs(y) < 1e-6, "still before the turn")
				if firstAt[i] == nil and y < -0.02 then
					firstAt[i] = now
				end
				if y < peak[i] then
					peak[i], peakAt[i] = y, now
				end
				if crossedAt[i] == nil and now > 0.8 and y > 0.004 then
					crossedAt[i] = now
				end
			end
		end)
		for i = 1, 8 do
			t.truthy(firstAt[i] ~= nil, `segment {i} is left behind (to the left of a body turning left: ry < 0)`)
			t.truthy(peak[i] < -0.035 and peak[i] >= -P.tail.yawMax, `segment {i} trails by {peak[i]} rad`)
			if i > 1 then
				t.truthy(firstAt[i] >= firstAt[i - 1], `segment {i} starts after segment {i - 1}`)
				t.truthy(peakAt[i] >= peakAt[i - 1], `segment {i} is furthest out after segment {i - 1}`)
				t.truthy(peak[i] < peak[i - 1], "and further out: the lag grows toward the tip")
			end
			-- it catches up and swings past the middle (the root follows the body closely; from the middle
			-- of the tail on it is a whip)
			t.truthy(i < 3 or crossedAt[i] ~= nil, `segment {i} swings past the middle`)
		end
		t.truthy(firstAt[8] - firstAt[1] > 0.04, `the bend takes {firstAt[8] - firstAt[1]} s to run down the tail`)
		t.truthy(peakAt[8] - peakAt[1] > 0.08, `the tip is furthest out {peakAt[8] - peakAt[1]} s after the root`)
		t.truthy(trail < -0.55 and trail > -1.4, `the whole tail trails by {trail} rad at its most`)
		t.truthy(
			trailAt > bendPeakAt + 0.03,
			`after the spine is at its most bent ({bendPeakAt} s, the tail {trailAt} s)`
		)
		t.truthy(crossedAt[8] > crossedAt[3] + 0.1, "the tip comes back last")
		-- and it is still again
		local last = Liveliness.step(st, input({ speed = 6 }), 1 / 120)
		for i = 1, 8 do
			t.near(at(last, TAILS[i], 2), 0, 0.004, `segment {i} settles`)
		end
	end)

	t.test(
		"a stop: the nose dips and the fore legs fold under it, the tail is thrown up; all settle past level",
		function()
			local st = Liveliness.new(1, "rodent")
			local function speedAt(now: number): number
				-- a sprint let go at 1 s: the motor's speed falls at 17/s (SquirrelMotor speedSmooth) and the
				-- drawn body follows it at 23/s (SquirrelVisual), as the stop take shows
				local since = now - 1
				return if since < 0 then 33 else 33 * (23 * math.exp(-17 * since) - 17 * math.exp(-23 * since)) / 6
			end
			local dipMost, dipAt, rebound = 0, 0, 0
			local liftMost, liftAt, droop = 0, 0, 0
			local sink, foreFold = 0, 0
			local archMost = 0
			run(st, 0, 3, 60, function(now)
				return input({ speed = speedAt(now) })
			end, function(now, pose)
				checkBounds(t, pose, "stop")
				local rx = at(pose, "Root", 1)
				if rx < dipMost then
					dipMost, dipAt = rx, now
				end
				if now > dipAt then
					rebound = math.max(rebound, rx)
				end
				local lift = sum(pose, TAILS, 1) -- (negative lifts)
				if now < 1 then
					t.truthy(math.abs(rx) < 0.01, "level while it runs")
				else
					if lift < liftMost then
						liftMost, liftAt = lift, now
					end
					if now > liftAt then
						droop = math.max(droop, lift)
					end
				end
				sink = math.min(sink, at(pose, "Root", 5))
				-- the fore legs fold while the nose is down: the paws come up toward the body, soles flat
				if rx < -0.06 then
					local upper, lower = at(pose, "FrontL_Upper", 1), at(pose, "FrontL_Lower", 1)
					t.truthy(upper < 0 and lower > 0, `folded at {now} s ({upper}, {lower})`)
					t.near(at(pose, "FrontR_Upper", 1), upper, 1e-12, "both sides alike")
					foreFold = math.max(foreFold, upper / P.fold.fore[1])
					local chest = at(pose, "Hips", 1) + sum(pose, SPINE, 1)
					local folded = at(pose, "FrontL_Upper", 1)
						+ lower
						+ at(pose, "FrontL_Foot", 1)
						+ at(pose, "FrontL_Toe", 1)
					t.near(folded, -(rx + chest), 2e-3, "the sole keeps to the ground the body pitches over")
				end
				archMost = math.max(archMost, at(pose, "Hips", 1) * 2)
				-- the head takes back most of the dip
				if rx < -0.03 then
					t.truthy(at(pose, "Head", 1) > 0.01, "the head goes against the dip")
				end
			end)
			t.truthy(dipMost < -0.09 and dipMost >= -P.brake.dip.down, `the nose dips {dipMost} rad`)
			t.truthy(dipAt > 1.1 and dipAt < 1.5, `at {dipAt} s`)
			t.truthy(rebound > 0.008 and rebound < 0.06, `and comes back past level by {rebound} rad`)
			t.truthy(liftMost < -0.45 and liftMost > -1.2, `the tail is thrown up {liftMost} rad over its length`)
			t.truthy(liftAt > 1.12 and liftAt < 1.6, `at {liftAt} s`)
			t.truthy(droop > 0.005, `and swings back past where it was ({droop})`)
			t.truthy(sink < -0.02 and sink >= P.land.min, `the body sinks {sink} studs`)
			t.truthy(foreFold > 0.05 and foreFold <= P.fold.max + 1e-9, `the fore paws come up {foreFold} studs`)
			t.truthy(archMost > 0.12 and archMost <= P.brake.arch.max, `the back rounds {archMost} rad`)
			-- at rest again
			local last = Liveliness.step(st, input(), 1 / 60)
			t.near(at(last, "Root", 1), 0, 2e-3)
			t.near(at(last, "Root", 5), 0, 1e-3)
			t.near(sum(last, TAILS, 1), 0, 4e-3)
			t.eq(last.FrontL_Upper, nil, "the legs are left to the clip")
			-- a start does the reverse, less: nose up a little, the tail dragged low, never under its limit
			local go = Liveliness.new(1, "rodent")
			local up, low = 0, 0
			run(go, 0, 1, 60, function(now)
				return input({ speed = 18 * (1 - math.exp(-12 * now)) })
			end, function(_now, pose)
				up = math.max(up, at(pose, "Root", 1))
				low = math.max(low, sum(pose, TAILS, 1))
			end)
			t.truthy(up > 0.02 and up <= P.brake.dip.up + 0.02, `a start lifts the nose {up} rad`)
			t.truthy(low > 0.03 and low <= P.tail.startMax * 1.5, `and drags the tail {low} rad low`)
		end
	)

	t.test("a leap: the body pitches along its flight; the landing squashes it and it comes back", function()
		local st = Liveliness.new(2, "rodent")
		-- run, leap at 1 s (up at 32, gravity 75: 0.853 s in the air), land, run on
		local function what(now: number): Input
			if now < 1 then
				return input({ speed = 18 })
			elseif now < 1.853 then
				return input({ speed = 18, pace = 36, vy = 32 - 75 * (now - 1), mode = "air" })
			end
			-- the drawn body eases onto the ground for a moment after the motor lands
			return input({
				speed = 18,
				pace = 18 + 15 * math.exp(-8 * (now - 1.853)),
				vy = -14 * math.exp(-23 * (now - 1.853)),
			})
		end
		local noseUp, noseDown, stretch = 0, 0, 0
		local tailLow, tailHigh = 0, 0
		local sinkMost, sinkAt, bounce = 0, 0, 0
		local roundMost = 0
		run(st, 0, 3.2, 60, what, function(now, pose)
			checkBounds(t, pose, "leap")
			local rx = at(pose, "Root", 1)
			if now > 1 and now < 1.853 then
				noseUp, noseDown = math.max(noseUp, rx), math.min(noseDown, rx)
				stretch = math.min(stretch, at(pose, "Hips", 1) * 2)
				tailLow, tailHigh = math.max(tailLow, sum(pose, TAILS, 1)), math.min(tailHigh, sum(pose, TAILS, 1))
				t.near(at(pose, "Root", 5), 0, 1e-3, "nothing presses it down in the air")
				if now > 1.4 then
					t.eq(pose.FrontL_Upper, nil, "the legs are the clip's in the air")
					t.eq(pose.BackR_Toe, nil)
				end
			elseif now >= 1.853 then
				local ty = at(pose, "Root", 5)
				if ty < sinkMost then
					sinkMost, sinkAt = ty, now
				end
				if now > sinkAt then
					bounce = math.max(bounce, ty)
				end
				roundMost = math.max(roundMost, at(pose, "Hips", 1) * 2)
				-- the drawn body easing down onto the ground is not a slope to pitch along
				t.truthy(math.abs(st.tilt) < 0.02, `tilt {st.tilt} at {now} s`)
				if ty < -0.05 then
					t.truthy(at(pose, "FrontL_Lower", 1) > 0 and at(pose, "BackL_Foot", 1) > 0, "all four legs fold")
				end
			end
		end)
		t.truthy(noseUp > 0.15 and noseUp <= P.flight.max, `nose up {noseUp} rad on the way up`)
		t.truthy(noseDown < -0.15 and noseDown >= -P.flight.max, `nose down {noseDown} rad on the way down`)
		t.truthy(stretch < -0.05, `the back hollows {stretch} rad as it rises`)
		t.truthy(
			tailLow > 0.08 and tailHigh < -0.2,
			`the tail trails the flight: a little low {tailLow}, then high {tailHigh}`
		)
		t.truthy(sinkMost < -0.06 and sinkMost >= P.land.min, `the landing sinks it {sinkMost} studs`)
		t.truthy(sinkAt - 1.853 > 0.04 and sinkAt - 1.853 < 0.2, `{sinkAt - 1.853} s after the motor lands`)
		t.truthy(bounce > 0.003 and bounce <= P.land.max, `and it comes back up past level ({bounce})`)
		t.truthy(roundMost > 0.1, `the back rounds {roundMost} rad`)
		local last = Liveliness.step(st, input({ speed = 18 }), 1 / 60)
		t.near(at(last, "Root", 1), 0, 3e-3)
		t.near(at(last, "Root", 5), 0, 1e-3)
		-- a small hop lands softer than a full leap
		local hop = Liveliness.new(2, "rodent")
		local hopSink = 0
		run(hop, 0, 1.5, 60, function(now)
			if now > 0.5 and now < 0.72 then
				return input({ speed = 18, pace = 26, vy = 8 - 75 * (now - 0.5), mode = "air" })
			end
			return input({ speed = 18 })
		end, function(_now, pose)
			hopSink = math.min(hopSink, at(pose, "Root", 5))
		end)
		t.truthy(hopSink < -0.008 and hopSink > 0.5 * sinkMost, `a hop sinks it {hopSink}`)
		-- told outright, a landing is taken as told
		local told = Liveliness.new(2, "rodent")
		Liveliness.step(told, input(), 1 / 60)
		Liveliness.step(told, input({ landed = 30 }), 1 / 60)
		local toldSink = 0
		run(told, 0, 0.3, 60, function(_now)
			return input()
		end, function(_now, pose)
			toldSink = math.min(toldSink, at(pose, "Root", 5))
		end)
		t.truthy(toldSink < -0.06)
	end)

	t.test("a slope pitches the body with the ground, and the legs are left alone", function()
		for _, angle in { 0.2, -0.3 } do
			local st = Liveliness.new(4, "rodent")
			local last: Liveliness.Pose = {}
			run(st, 0, 1.5, 60, function(_now)
				return input({ speed = 18, pace = 18, vy = 18 * math.tan(angle) })
			end, function(_now, pose)
				last = pose
			end)
			t.near(at(last, "Root", 1), P.tilt.share * angle, 0.01, `on a slope of {angle} rad`)
			t.eq(last.FrontL_Upper, nil, "the ground tilts with it: nothing to fold")
			t.near(sum(last, TAILS, 1), 0, 0.06, "(the tail only ripples)")
		end
		-- on a trunk the climb is not a slope
		local st = Liveliness.new(4, "rodent")
		run(st, 0, 1, 60, function(_now)
			return input({ speed = 10.8, vy = 10.8, mode = "trunk", pitch = 1.43 })
		end, function(_now, pose)
			t.near(at(pose, "Root", 1), 0, 0.02)
		end)
	end)

	t.test("breathing quickens with a sprint and when winded, and comes back", function()
		-- breaths a second over a stretch of standing still, and how deep
		local function breathing(st: Liveliness.State, seconds: number): (number, number)
			local ups, depth = 0, 0
			local before = 0
			run(st, 0, seconds, 120, function(_now)
				return input()
			end, function(_now, pose)
				local b = at(pose, "Spine2", 1)
				if before <= 0 and b > 0 then
					ups += 1
				end
				before = b
				depth = math.max(depth, math.abs(b))
			end)
			return ups / seconds, depth
		end
		local st = Liveliness.new(5)
		local calmHz, calmDepth = breathing(st, 4)
		t.near(calmHz, P.breath.calmHz, 0.3)
		t.truthy(calmDepth > 0.004 and calmDepth < 0.02, `a calm breath lifts the back {calmDepth} rad`)
		-- the chest takes the breath back: the fore paws it carries stay
		local pose = Liveliness.step(st, input(), 1 / 120)
		t.near(sum(pose, SPINE, 1), 0, 1e-9)
		-- four seconds of sprinting
		run(st, 0, 4, 60, function(_now)
			return input({ speed = 33 })
		end)
		t.near(st.effort, 1, 1e-6)
		breathing(st, 1) -- (the stop itself rounds the back for a moment)
		local pantHz, pantDepth = breathing(st, 1.5)
		t.truthy(pantHz > 2 * calmHz, `it pants at {pantHz} Hz (calm: {calmHz})`)
		t.truthy(pantDepth > 2.5 * calmDepth and pantDepth < 0.09, `and deeper ({pantDepth})`)
		breathing(st, P.breath.recover)
		local laterHz = breathing(st, 4)
		t.near(laterHz, calmHz, 0.3, "and gets its breath back")
		-- out of fumes at a walk: out of breath in a second or so
		local winded = Liveliness.new(5)
		run(winded, 0, 1.5, 60, function(_now)
			return input({ speed = 18, winded = true })
		end)
		t.truthy(winded.effort > 0.9, `winded: effort {winded.effort}`)
		-- the Spicy Rodent's resting breath is Creep's: this layer only adds the pant
		local rodent = Liveliness.new(5, "rodent")
		local _, restDepth = breathing(rodent, 2)
		t.near(restDepth, 0, 1e-9)
		run(rodent, 0, 4, 60, function(_now)
			return input({ speed = 33 })
		end)
		breathing(rodent, 1)
		local _, rodentPant = breathing(rodent, 1)
		t.truthy(rodentPant > 0.02)
	end)

	t.test("standing, the ordinary squirrel flicks ears and tail and glances about; the rodent does not", function()
		local st = Liveliness.new(6)
		local total = 240
		local ears, tips, flags, glances = 0, 0, 0, 0
		local wasEar, wasTip, wasFlag, wasGlance = false, false, false, false
		local earL, earR = 0, 0
		local biggest = 0
		local lastYaw = 0
		run(st, 500, total, 60, function(now)
			return input({ time = now })
		end, function(_now, pose)
			checkBounds(t, pose, "idle")
			local ear = pose.EarL ~= nil or pose.EarR ~= nil
			earL += if pose.EarL then 1 else 0
			earR += if pose.EarR then 1 else 0
			local tip = math.abs(at(pose, "Tail8", 2)) > 0.05
			local flag = math.abs(at(pose, "Tail1", 1)) > 0.05
			local yaw = at(pose, "Neck", 2) + at(pose, "Head", 2)
			local glance = math.abs(yaw) > 0.1
			ears += if ear and not wasEar then 1 else 0
			tips += if tip and not wasTip then 1 else 0
			flags += if flag and not wasFlag then 1 else 0
			glances += if glance and not wasGlance then 1 else 0
			wasEar, wasTip, wasFlag, wasGlance = ear, tip, flag, glance
			biggest = math.max(biggest, math.abs(yaw - lastYaw))
			lastYaw = yaw
			t.near(sum(pose, SPINE, 2), 0, 1e-9, "the back does not turn")
		end)
		t.truthy(ears >= total / 8 and ears <= total / 1.5, `{ears} ear flicks in {total} s`)
		t.truthy(earL > 0 and earR > 0, "either ear")
		t.truthy(tips >= total / 10 and tips <= total / 2, `{tips} flicks of the tail tip`)
		t.truthy(flags >= total / 40 and flags <= total / 2, `{flags} beats of tail flagging`)
		t.truthy(glances >= total / 20 and glances <= total / 3, `{glances} glances`)
		t.truthy(biggest > 0.03 and biggest < 0.2, `a glance is quick, never a jump ({biggest} rad in a frame)`)
		-- the same on every client: it is the server's clock that decides
		local a, b = Liveliness.new(6), Liveliness.new(6)
		run(a, 500, 20, 60, function(now)
			return input({ time = now })
		end)
		run(b, 500, 20, 144, function(now)
			return input({ time = now })
		end)
		local pa = Liveliness.step(a, input({ time = 520.4 }), 1 / 60)
		local pb = Liveliness.step(b, input({ time = 520.4 }), 1 / 144)
		t.near(at(pa, "Head", 2), at(pb, "Head", 2), 1e-3)
		t.near(at(pa, "Tail8", 2), at(pb, "Tail8", 2), 1e-3)
		-- on the move there is none of it; the Spicy Rodent has none of it at all (Creep twitches for it)
		for _, case in { { rig = "squirrel", speed = 18 }, { rig = "rodent", speed = 0 } } do
			local other = Liveliness.new(6, case.rig)
			run(other, 500, 1, 60, function(now)
				return input({ time = now, speed = case.speed })
			end)
			run(other, 501, 60, 60, function(now)
				return input({ time = now, speed = case.speed })
			end, function(_now, pose)
				t.eq(pose.EarL, nil, case.rig)
				t.eq(pose.EarR, nil, case.rig)
				t.near(at(pose, "Head", 2), 0, 1e-6, case.rig)
				if case.speed == 0 then
					t.near(sum(pose, TAILS, 2), 0, 1e-6, case.rig)
				end
			end)
		end
		-- stalking it stands quieter: no flagging
		local stalk = Liveliness.new(6)
		run(stalk, 500, 120, 60, function(now)
			return input({ time = now, stalk = true })
		end, function(_now, pose)
			t.truthy(math.abs(at(pose, "Tail1", 1)) < 0.03, "no flagging in a stalk")
		end)
	end)

	t.test("bounded whatever comes in", function()
		local modes = { "ground", "air", "rail", "trunk" }
		local function hash(i: number, salt: number): number
			local x = math.sin(i * 12.9898 + salt * 78.233) * 43758.5453
			return x - math.floor(x)
		end
		for _, rig in { "squirrel", "rodent" } do
			local st = Liveliness.new(7, rig)
			for i = 1, 6000 do
				local wild = input({
					speed = hash(i, 1) * 400 - 50,
					pace = hash(i, 2) * 500,
					yawRate = (hash(i, 3) - 0.5) * 400,
					vy = (hash(i, 4) - 0.5) * 800,
					mode = modes[1 + math.floor(hash(i, 5) * 4)],
					pitch = (hash(i, 6) - 0.5) * 4,
					roll = (hash(i, 7) - 0.5) * 8,
					winded = hash(i, 8) < 0.3,
					coarse = hash(i, 9) < 0.5,
					landed = if hash(i, 10) < 0.1 then hash(i, 11) * 1000 else nil,
					time = i * 0.37,
				})
				local dt = if hash(i, 12) < 0.05 then 3 else 0.001 + hash(i, 13) * 0.05
				checkBounds(t, Liveliness.step(st, wild, dt), `wild {rig} {i}`)
			end
			-- nothing that is not a number gets in, and a frame of no time changes nothing
			local before = st.bend
			Liveliness.step(st, input({ yawRate = 0 / 0 }), 1 / 60)
			Liveliness.step(st, input({ vy = 0 / 0 }), 1 / 60)
			Liveliness.step(st, input({ yawRate = 1 }), 0)
			t.eq(st.bend, before)
			-- and it comes back to rest from anything
			local last: Liveliness.Pose = {}
			run(st, 0, 14, 60, function(_now)
				return input()
			end, function(_now, pose)
				last = pose
			end)
			if rig == "rodent" then
				for bone, r in last do
					for k, v in r do
						t.near(v, 0, 2e-3, `{bone}[{k}] at rest`)
					end
				end
			else
				t.near(at(last, "Root", 1), 0, 2e-3)
				t.near(sum(last, SPINE, 2), 0, 2e-3)
			end
		end
	end)

	t.test("the same at any frame rate", function()
		local RATES: { [string]: { number } } = {
			["30"] = { 1 / 30 },
			["60"] = { 1 / 60 },
			["120"] = { 1 / 120 },
			uneven = { 1 / 40, 1 / 120, 1 / 120, 1 / 40, 1 / 60, 1 / 60 },
		}
		-- a sprint, a quarter turn, a rise and a dip in the ground, a stop: everything that comes in smoothly
		local function smoothly(now: number): Input
			local since = now - 2.4
			local speed = if since < 0 then 33 else 33 * (23 * math.exp(-17 * since) - 17 * math.exp(-23 * since)) / 6
			local hill = if now > 1.2 and now < 2 then 9 * math.sin((now - 1.2) / 0.8 * 2 * math.pi) ^ 3 else 0
			return input({
				speed = speed,
				yawRate = quarterTurn(now, 0.3),
				vy = hill,
				roll = 0.03 * quarterTurn(now, 0.3),
			})
		end
		local checkpoints = { 0.4, 0.6, 0.8, 1.0, 1.4, 1.6, 1.8, 2.0, 2.2, 2.6, 2.8, 3.2 }
		local function trace(dts: { number }): { { number } }
			local st = Liveliness.new(8, "rodent")
			local out = {}
			local now, k, i = 0, 1, 0
			while k <= #checkpoints do
				i += 1
				local dt = dts[(i - 1) % #dts + 1]
				now += dt
				local pose = Liveliness.step(st, smoothly(now), dt)
				if now >= checkpoints[k] - 1e-9 then
					t.near(now, checkpoints[k], 1e-6, "(the rates here all meet at the checkpoints)")
					table.insert(out, {
						sum(pose, SPINE, 2),
						at(pose, "Head", 2),
						sum(pose, SPINE, 3),
						at(pose, "Head", 3),
						sum(pose, TAILS, 2),
						at(pose, "Tail8", 2),
						at(pose, "Root", 1),
						at(pose, "Root", 5),
						sum(pose, TAILS, 1),
						at(pose, "Hips", 1),
						at(pose, "FrontL_Lower", 1),
					})
					k += 1
				end
			end
			return out
		end
		local names =
			{ "bend", "head", "bank", "head roll", "tail yaw", "tip yaw", "pitch", "sink", "tail lift", "arch", "fold" }
		local reference = trace({ 1 / 240 })
		local worst, biggest = 0, 0
		for label, dts in RATES do
			for c, row in trace(dts) do
				for j, v in row do
					local d = math.abs(v - reference[c][j])
					worst = math.max(worst, d)
					biggest = math.max(biggest, math.abs(reference[c][j]))
					-- (a leg's angles are five times the hundredths of a stud its paw is brought up by)
					t.truthy(
						d < (if names[j] == "fold" then 0.006 else 0.002) + 0.02 * math.abs(reference[c][j]),
						`{names[j]} at {checkpoints[c]} s, {label} frames a second: {v} against {reference[c][j]}`
					)
				end
			end
		end
		t.truthy(worst > 0 and biggest > 0.5, `(not literally the same computation: {worst} rad apart at most)`)

		-- a leap and its landing are sharp: a frame is one sample of what comes in, so they are seen within a
		-- frame of when they happened. How far each answer goes does not depend on the frame.
		local function leap(dts: { number }): { number }
			local st = Liveliness.new(8, "rodent")
			local up, down, sink, low, high, round = 0, 0, 0, 0, 0, 0
			local now, i = 0, 0
			while now < 3 do
				i += 1
				local dt = dts[(i - 1) % #dts + 1]
				now += dt
				local air = now > 1.2 + 1e-9 and now < 1.9 + 1e-9
				local pose = Liveliness.step(
					st,
					if air
						then input({ speed = 18, pace = 36, vy = 26 - 75 * (now - 1.2), mode = "air" })
						else input({ speed = 18, pace = 18 }),
					dt
				)
				local rx, lift = at(pose, "Root", 1), sum(pose, TAILS, 1)
				up, down = math.max(up, rx), math.min(down, rx)
				sink = math.min(sink, at(pose, "Root", 5))
				low, high = math.max(low, lift), math.min(high, lift)
				round = math.max(round, at(pose, "Hips", 1))
			end
			return { up, down, sink, low, high, round }
		end
		local leapNames = { "nose up", "nose down", "sink", "tail low", "tail high", "back rounded" }
		local fine = leap({ 1 / 240 })
		t.truthy(fine[1] > 0.15 and fine[2] < -0.15 and fine[3] < -0.06 and fine[5] < -0.2)
		for label, dts in RATES do
			for j, v in leap(dts) do
				t.truthy(
					math.abs(v - fine[j]) < 0.003 + 0.08 * math.abs(fine[j]),
					`{leapNames[j]}, {label} frames a second: {v} against {fine[j]}`
				)
			end
		end
	end)

	t.test(
		"deterministic: the same seed and the same frames give the same pose; another seed another ripple",
		function()
			local function final(seed: number): Liveliness.Pose
				local st = Liveliness.new(seed)
				local last: Liveliness.Pose = {}
				run(st, 100, 3, 60, function(now)
					return input({ speed = 30, yawRate = 3 * math.sin(now * 2), time = now })
				end, function(_now, pose)
					last = pose
				end)
				local copy = {}
				for bone, r in last do
					copy[bone] = table.clone(r)
				end
				return copy
			end
			t.deepEq(final(11), final(11))
			local a, b = final(11), final(12)
			t.near(sum(a, SPINE, 2), sum(b, SPINE, 2), 1e-12, "the answer to the turn is the body's, not the seed's")
			t.truthy(math.abs(at(a, "Tail8", 2) - at(b, "Tail8", 2)) > 1e-4, "the tail's ripple is its own")
		end
	)

	t.test("observe: rates from the root's pose; a teleport has none; a far body gets nothing", function()
		local st = Liveliness.new(9, "rodent")
		local dt = 1 / 60
		local function sample(i: number, over: { [string]: any }?): Liveliness.Sample
			local s: Liveliness.Sample = {
				x = 3 * i * dt,
				y = 10 + 2 * i * dt,
				z = -4 * i * dt,
				pitch = 0.1,
				yaw = 3.1 + 2 * i * dt, -- (through pi: the turn is taken the short way)
				roll = -0.05,
				speed = 18,
				mode = "ground",
				stalk = false,
				winded = false,
				coarse = false,
				time = 1000 + i * dt,
			}
			if over then
				for k, v in over do
					(s :: any)[k] = v
				end
			end
			return s
		end
		local first = Liveliness.observe(st, sample(0), dt)
		t.eq(first.yawRate, 0, "nothing is known of the first frame")
		t.eq(first.pace, 18, "but the speed it is told")
		for i = 1, 40 do
			local got = Liveliness.observe(st, sample(i), dt)
			t.near(got.yawRate, 2, 1e-6)
			t.near(got.vy, 2, 1e-6)
			t.near(got.pace :: number, 5, 1e-6, "over the ground: the level distance")
			t.eq(got.speed, 18)
			t.eq(got.pitch, 0.1)
			t.eq(got.roll, -0.05)
			t.eq(got.time, 1000 + i * dt)
		end
		-- on a trunk the pace is along the trunk
		local climbing = Liveliness.observe(st, sample(41, { mode = "trunk" }), dt)
		t.near(climbing.pace :: number, math.sqrt(29), 1e-6)
		-- put somewhere else: no rate that frame, and the springs start again from rest
		Liveliness.step(st, input({ speed = 33, yawRate = 5 }), 0.2)
		t.truthy(st.bend > 0.1)
		local moved = Liveliness.observe(st, sample(42, { x = 500 }), dt)
		t.eq(moved.yawRate, 0)
		t.eq(moved.vy, 0)
		local pose = Liveliness.step(st, moved, dt)
		t.near(sum(pose, SPINE, 2), 0, 1e-9)
		-- frame is observe then step; far away it is nothing, and what comes back starts from rest
		local near = Liveliness.frame(st, sample(43, { x = 500 + 3 * dt }), dt)
		t.truthy(near ~= nil and near.Root ~= nil)
		for i = 44, 60 do
			Liveliness.frame(st, sample(i, { x = 500 + 3 * (i - 42) * dt }), dt)
		end
		t.truthy(st.bend > 0.02, "turning")
		t.eq(Liveliness.frame(st, sample(61, { far = true }), dt), nil)
		local back = Liveliness.frame(st, sample(400, { x = 0 }), dt) :: Liveliness.Pose
		t.near(sum(back, SPINE, 2), 0, 1e-9)
		t.eq(st.tailYaw[8], 0, "(the tail's springs: its ripple is not one)")
	end)

	t.test("a body the server moves in steps does not shiver", function()
		-- a squirrel the server moves ten times a second: it stands for five frames and jumps on the sixth.
		-- It runs straight at 18 studs/s for 3 s, then turns at 2 rad/s. What the driver tells the layer:
		-- the root as it is each frame, and its own smoothed speed (AnimationDriver's e.speed).
		local st = Liveliness.new(10)
		local dt = 1 / 60
		local x, z, yaw = 0, 0, 0
		local shownX, shownZ, shownYaw = 0, 0, 0
		local lastX, lastZ, told = 0, 0, 18
		local dipSpan, liftSpan, bendStraight = 0, 0, 0
		local bendLow, bendHigh = math.huge, -math.huge
		for i = 1, 360 do
			local now = i * dt
			if now > 3 then
				yaw += 2 * dt
			end
			x -= math.sin(yaw) * 18 * dt
			z -= math.cos(yaw) * 18 * dt
			if i % 6 == 0 then
				shownX, shownZ, shownYaw = x, z, yaw
			end
			local seen = math.sqrt((shownX - lastX) ^ 2 + (shownZ - lastZ) ^ 2) / dt
			lastX, lastZ = shownX, shownZ
			told += (seen - told) * math.min(1, dt / 0.15)
			local pose = Liveliness.frame(st, {
				x = shownX,
				y = 0.9,
				z = shownZ,
				pitch = 0,
				yaw = shownYaw,
				roll = 0,
				speed = told,
				mode = "ground",
				coarse = true,
				time = now,
			}, dt) :: Liveliness.Pose
			checkBounds(t, pose, "stepped")
			local lift = 0
			for k = 1, 8 do
				lift += st.tailPitch[k]
			end
			if now > 1.5 and now <= 3 then
				dipSpan = math.max(dipSpan, math.abs(st.dip))
				liftSpan = math.max(liftSpan, math.abs(lift))
				bendStraight = math.max(bendStraight, math.abs(st.bend))
			elseif now > 4.5 then
				bendLow, bendHigh = math.min(bendLow, st.bend), math.max(bendHigh, st.bend)
			end
		end
		t.truthy(dipSpan < 0.006, `running straight its nose nods {dipSpan} rad at most`)
		t.truthy(liftSpan < 0.03, `its tail bobs {liftSpan} rad over its whole length`)
		t.truthy(bendStraight < 0.004, `its back stays straight ({bendStraight})`)
		t.truthy(bendLow > 0.1, `in the turn the spine bends into it ({bendLow} to {bendHigh} rad)`)
		t.truthy(bendHigh - bendLow < 0.012, `steadily ({bendHigh - bendLow} rad of shiver)`)
	end)

	t.test("the layers add: the squirrel gets this one, the Spicy Rodent this one on its twitches", function()
		local seed = AnimationDriver.creepSeed("squirrel_1")
		local live = Liveliness.new(seed, "rodent")
		run(live, 0, 0.5, 60, function(_now)
			return input({ speed = 33, yawRate = 4, roll = 0.14 })
		end)
		t.eq(next(AnimationDriver.heroLayers("squirrel", 1000, seed)), nil, "nothing without a live state")
		-- the squirrel: exactly the live pose
		local plain = AnimationDriver.heroLayers("squirrel", 1000, seed, live)
		t.deepEq(plain, live.pose)
		-- the rodent: Creep's twitches (the head jerk a little less at a sprint) plus the live pose
		t.near(Liveliness.twitch(live), P.twitch.least, 0.02, "at a sprint")
		t.eq(Liveliness.twitch(Liveliness.new(seed, "rodent")), 1, "standing")
		for _, now in { 1000, 1003.3, 1007.1, 1011.9 } do
			local creep = Creep.pose(now, seed, Liveliness.twitch(live))
			local both = AnimationDriver.heroLayers("rodent", now, seed, live)
			local alone = AnimationDriver.heroLayers("rodent", now, seed)
			t.near(both.Head[2], creep.head.yaw + at(live.pose, "Head", 2), 1e-12)
			t.near(both.Head[3], creep.head.roll + at(live.pose, "Head", 3), 1e-12)
			t.near(both.Spine2[1], creep.chest + at(live.pose, "Spine2", 1), 1e-12)
			t.near(both.Tail3[2], creep.tail[3] + at(live.pose, "Tail3", 2), 1e-12)
			t.near(both.Jaw[1], -creep.jaw, 1e-12, "the jaw is Creep's alone")
			t.near(both.Root[1], at(live.pose, "Root", 1), 1e-12, "the root is this layer's alone")
			t.eq(alone.Root, nil)
			t.near(alone.Head[3], Creep.pose(now, seed).head.roll, 1e-12, "without a live state, Creep as it was")
		end
		-- the live pose itself is not changed by being added
		local keep = table.clone(live.pose.Head)
		AnimationDriver.heroLayers("rodent", 1003.3, seed, live)
		t.deepEq(live.pose.Head, keep)
		-- the shudder is the back's: what Creep rolls the spine by, the chest takes back and the neck
		-- takes up again, so the fore paws (the chest carries them) stay where they stand
		local shudders = 0
		for i = 0, 60 * 120 do
			local now = 1000 + i / 60
			local creep = Creep.pose(now, seed)
			local layers = AnimationDriver.heroLayers("rodent", now, seed)
			if creep.spine ~= 0 then
				shudders += 1
				local chest = layers.Spine1[3] + layers.Spine2[3] + layers.Spine3[3] + layers.Chest[3]
				t.near(chest, 0, 1e-12, "the chest does not roll")
				t.near(layers.Spine3[3], 3 * creep.spine, 1e-12, "the back behind it does, as far as it ever did")
				t.near(layers.Neck[3], 3 * creep.spine, 1e-12, "the head still shakes")
			else
				t.eq(layers.Chest[3], 0)
			end
			t.near(layers.Spine1[1] + layers.Spine2[1] + layers.Chest[1], 0, 1e-12, "nor does the breath pitch it")
			local F = P.fold.foreSpine
			t.near(
				F[1] * layers.Spine1[1] + F[2] * layers.Spine2[1] + F[4] * layers.Chest[1],
				0,
				1e-4,
				"or lift the fore paws"
			)
		end
		t.truthy(shudders > 20)
		-- onto: offsets on the same axes add; the root's offset carries over
		local sumOf = Liveliness.onto(
			{ Head = { 0.1, 0.2, 0.3 } },
			{ Head = { 1, 2, 3 }, Root = { 0.5, 0, 0, 0, -0.1, 0 } }
		)
		t.deepEq(sumOf, { Head = { 1.1, 2.2, 3.3 }, Root = { 0.5, 0, 0, 0, -0.1, 0 } })
		t.deepEq(Liveliness.onto({ Head = { 1, 2, 3 } }, nil), { Head = { 1, 2, 3 } })
	end)
end
