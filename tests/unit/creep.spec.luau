--!strict
-- tests/unit/creep.spec.luau
-- The Spicy Rodent's twitches (Client/Animation/Creep; owner 2026-11-11: "just crank up that squirrels
-- creepy weirdness, even further"): the head is always cocked and snaps now and then, the jaw chatters
-- in bursts, an ear flicks, the tail whips, the back shudders; all of it small, bounded, deterministic
-- and the same on every client.

local Creep = require("@client/Animation/Creep")

return function(t: any)
	t.test("pose is a pure function of time and seed, and never still", function()
		local a, b = Creep.pose(123.456, 7), Creep.pose(123.456, 7)
		t.deepEq(a, b)
		t.eq(#a.tail, Creep.TAIL_SEGMENTS)
		local other = Creep.pose(123.456, 8)
		t.truthy(other.head.roll ~= a.head.roll or other.head.yaw ~= a.head.yaw, "another body moves differently")
		-- the head is cocked: tilted to one side nearly all the time (a snap, or the swing across to the
		-- other side, can carry it through level for a moment)
		local cocked, samples = 0, 4000
		for i = 1, samples do
			local p = Creep.pose(i * 0.05, 7)
			if math.abs(p.head.roll) > 0.12 then
				cocked += 1
			end
		end
		t.truthy(cocked / samples > 0.9, `cocked {cocked} of {samples} moments`)
	end)

	t.test("every movement happens, often enough to notice and never constantly; all are bounded", function()
		local dt = 1 / 60
		local total = 240 -- seconds
		local n = math.floor(total / dt)
		local snaps, chatter, ears, whips, shudders = 0, 0, 0, 0, 0
		local wasSnap, wasChatter, wasEar, wasWhip, wasShudder = false, false, false, false, false
		local chatterFrames, biggestStep = 0, 0
		local last = Creep.pose(0, 3)
		for i = 1, n do
			local p = Creep.pose(i * dt, 3)
			-- bounds
			t.truthy(
				math.abs(p.head.yaw) <= Creep.SNAP + 0.05
					and math.abs(p.head.roll) <= Creep.TILT + Creep.SNAP * 0.7 + 0.06
			)
			t.truthy(p.jaw >= 0 and p.jaw <= Creep.JAW + 1e-9, "the jaw only opens")
			t.truthy(p.earL >= 0 and p.earR >= 0 and p.earL <= 0.56 and p.earR <= 0.56)
			t.truthy(math.abs(p.spine) <= 0.071 and math.abs(p.chest) <= 0.021)
			local tailMoving = false
			for _, y in p.tail do
				t.truthy(math.abs(y) <= 0.6)
				tailMoving = tailMoving or y ~= 0
			end
			-- count events on their rising edge
			local snap = math.abs(p.head.yaw) > 0.12
			local chat = p.jaw > 0.02
			local ear = p.earL > 0.1 or p.earR > 0.1
			local shud = p.spine ~= 0
			snaps += if snap and not wasSnap then 1 else 0
			ears += if ear and not wasEar then 1 else 0
			whips += if tailMoving and not wasWhip then 1 else 0
			shudders += if shud and not wasShudder then 1 else 0
			if chat then
				chatterFrames += 1
			end
			chatter += if p.jaw > 0 and not wasChatter then 1 else 0
			wasSnap, wasChatter, wasEar, wasWhip, wasShudder = snap, p.jaw > 0, ear, tailMoving, shud
			biggestStep = math.max(biggestStep, math.abs(p.head.yaw - last.head.yaw))
			last = p
		end
		-- a head snap every few seconds, not every frame
		t.truthy(snaps >= total / 6 and snaps <= total / 1.2, `{snaps} head snaps in {total} s`)
		t.truthy(ears >= total / 6, `{ears} ear flicks`)
		t.truthy(whips >= total / 8 and whips <= total / 1.5, `{whips} tail whips`)
		t.truthy(shudders >= total / 20, `{shudders} shudders`)
		t.truthy(
			chatterFrames * dt > total * 0.03 and chatterFrames * dt < total * 0.3,
			`the jaw chatters for {chatterFrames * dt} s`
		)
		t.truthy(chatter >= total / 12, `{chatter} chatter beats`)
		-- a snap is fast (most of 0.5 rad inside a few frames) but never a one-frame teleport
		t.truthy(biggestStep > 0.05 and biggestStep < 0.3, `the fastest head step is {biggestStep} rad in one frame`)
	end)

	t.test("the chatter is a burst of quick bites; the tail's kink runs root to tip", function()
		-- find a chatter and count its beats: about 11 a second
		local dt = 1 / 240
		local beats, inBurst, burstLen, peak = 0, false, 0, false
		for i = 0, 240 * 60 do
			local p = Creep.pose(i * dt, 5)
			if p.jaw > 0 then
				inBurst = true
				burstLen += dt
				local high = p.jaw > Creep.JAW * 0.5
				if high and not peak then
					beats += 1
				end
				peak = high
			elseif inBurst then
				break
			end
		end
		t.truthy(inBurst, "a chatter within a minute")
		t.truthy(burstLen >= 0.3 and burstLen <= 0.75, `a burst of {burstLen} s`)
		t.truthy(beats >= 2 and beats / burstLen > 6 and beats / burstLen < 14, `{beats} bites in {burstLen} s`)
		-- find a whip and check the kink reaches the root before the tip
		local firstAt: { number } = {}
		for i = 0, 240 * 60 do
			local p = Creep.pose(i * dt, 5)
			local any = false
			for seg, y in p.tail do
				if y ~= 0 then
					any = true
					firstAt[seg] = firstAt[seg] or i * dt
				end
			end
			if not any and firstAt[1] and firstAt[Creep.TAIL_SEGMENTS] then
				break
			end
		end
		t.truthy(firstAt[1] ~= nil and firstAt[8] ~= nil, "a whip within a minute")
		t.truthy(firstAt[8] > firstAt[1] + 0.15, "the tip moves after the root")
		for seg = 2, 8 do
			t.truthy(firstAt[seg] >= firstAt[seg - 1], `segment {seg} follows segment {seg - 1}`)
		end
	end)
end
