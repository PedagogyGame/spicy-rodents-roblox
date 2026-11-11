--!strict
-- The client side of the bite-to-hospital sequence, as far as Lune can see it (nothing here renders:
-- the first real look at a bubble, the red eyes or a seated patient is a Play session): the bubble
-- pool's choice of slot, the bubble's size, what each Med value means on screen, how a patient is
-- posed, and where the hospital's cots stand.
local SpeechBubbles = require("@client/UI/SpeechBubbles")
local MedicalView = require("@client/Render/MedicalView")
local AnimationDriver = require("@client/Animation/AnimationDriver")
local SpeechRules = require("@shared/Speech/SpeechRules")
local Lines = require("@shared/Speech/Lines")
local InfectionRules = require("@shared/Infection/InfectionRules")
local HospitalLayout = require("@shared/Infection/HospitalLayout")
local Height = require("@shared/World/Height")
local Data = require("@shared/Data")
local HospitalProps = require("@server/Hospital/HospitalProps")

return function(t)
	t.test("bubble pool: a free slot first, else the one that has been up longest", function()
		local slots: { SpeechBubbles.Slot } = {}
		for i = 1, 4 do
			slots[i] = { expires = 0, since = 0, body = nil }
		end
		t.eq(SpeechBubbles.slotFor(slots, 10), 1)
		slots[1] = { expires = 13.5, since = 10, body = "a" }
		slots[2] = { expires = 14.5, since = 11, body = "b" }
		t.eq(SpeechBubbles.slotFor(slots, 12), 3, "the first free one")
		slots[3] = { expires = 15, since = 11.5, body = "c" }
		slots[4] = { expires = 15.2, since = 11.7, body = "d" }
		t.eq(SpeechBubbles.slotFor(slots, 12), 1, "all in use: the oldest is taken over")
		slots[1] = { expires = 15.5, since = 12, body = "e" }
		t.eq(SpeechBubbles.slotFor(slots, 12.1), 2, "then the next oldest")
		t.eq(SpeechBubbles.slotFor(slots, 14.6), 2, "an expired slot counts as free")
		t.eq(SpeechBubbles.POOL, 8)
	end)

	t.test("bubble size: every line of Speech/Lines fits in at most three rows of a 250 px card", function()
		for _, line in Lines.all() do
			local w, h = SpeechBubbles.sizeFor(line)
			t.truthy(w >= 70 and w <= 250, `"{line}" is {w} px wide`)
			t.truthy(h >= 30 and h <= 80, `"{line}" is {h} px tall`)
			-- the glyphs fit the card: rows times the usable width
			local rows = (h - 12) / 21
			t.truthy(rows * (w - 18) >= #line * 8.6 - 1e-6, `"{line}" does not fit {w} x {h}`)
		end
		local w1 = SpeechBubbles.sizeFor("My ankle!")
		local w2 = SpeechBubbles.sizeFor("Oh my god, it's one of those squirrels again!")
		t.truthy(w1 < w2, "a short line gets a small card")
		local _, h1 = SpeechBubbles.sizeFor("My ankle!")
		local _, h2 = SpeechBubbles.sizeFor("Oh my god, it's one of those squirrels again!")
		t.truthy(h2 > h1, "the owner's line wraps onto a second row")
	end)

	t.test("a bubble is shown for what is left of its 3.5 s; stale and far-future stamps are not shown", function()
		-- the same answer the bubble code asks SpeechRules for, on the clock the server stamps with
		t.eq(SpeechRules.remaining(1000, 1000, 3.5), 3.5)
		t.near(SpeechRules.remaining(1002.5, 1000, 3.5), 1, 1e-9, "streamed in 2.5 s late: one second left")
		t.eq(SpeechRules.remaining(1100, 1000, 3.5), 0, "an old line on a body that just streamed in")
		t.eq(SpeechRules.remaining(1000, 1060, 3.5), 0)
	end)

	t.test("Med on screen: red eyes when symptomatic, hidden in transit, a pose when down or in bed", function()
		t.deepEq(MedicalView.look("symptomatic"), { hidden = false, eyes = true, pose = "stagger", glow = true })
		t.deepEq(MedicalView.look("down"), { hidden = false, eyes = false, pose = "down" })
		t.deepEq(MedicalView.look("carried"), { hidden = false, eyes = false, pose = "walk" })
		t.deepEq(MedicalView.look("transit"), { hidden = true, eyes = false, pose = nil })
		t.deepEq(MedicalView.look("treated"), { hidden = false, eyes = false, pose = "bed" })
		t.deepEq(MedicalView.look(nil), { hidden = false, eyes = false, pose = nil })
		t.deepEq(MedicalView.look(42), { hidden = false, eyes = false, pose = nil }, "junk draws nothing")
		-- every value the rules can publish has a look, and an incubating case publishes none
		local seen: { [string]: boolean } = {}
		for _, state in InfectionRules.STATES do
			for _, arrival in { "walk", "ambulance" } do
				local case: any = { state = state, selfTreat = false, arrival = arrival }
				local tell = InfectionRules.tell(case)
				if tell ~= nil then
					seen[tell] = true
					local look = MedicalView.look(tell)
					t.truthy(
						look.hidden or look.eyes or look.pose ~= nil,
						`{state} publishes "{tell}", which draws nothing`
					)
				end
			end
		end
		t.truthy(seen.symptomatic and seen.down and seen.carried and seen.transit and seen.treated)
		t.eq(
			InfectionRules.tell({ state = "retrieve", selfTreat = false } :: any),
			"carried",
			"a patient who is being moved is on their feet, not sliding along sitting"
		)
		t.eq(InfectionRules.tell({ state = "incubating", selfTreat = false } :: any), nil)
		t.eq(InfectionRules.tell({ state = "bitten", selfTreat = false } :: any), nil)
		t.truthy(MedicalView.EYE.z < 0, "the eyes are on the face (an R15 head looks along -Z)")
	end)

	t.test("patient pose: sitting on the ground when down, up on the cot when treated, untouched otherwise", function()
		local footDrop = 3 -- an R15 root is 3 studs above its soles
		local down = AnimationDriver.medPose("down", footDrop)
		t.eq(down.clip, "sit")
		t.near(down.drop, 3 - AnimationDriver.SIT_SEAT, 1e-9)
		local bed = AnimationDriver.medPose("treated", footDrop)
		t.eq(bed.clip, "sit")
		t.near(down.drop - bed.drop, HospitalLayout.BED.top, 1e-9, "the cot's mattress is that much higher")
		t.truthy(bed.drop >= 0)
		for _, med in { "symptomatic", "carried", "transit", nil :: any, "nonsense" } do
			local p = AnimationDriver.medPose(med, footDrop)
			t.eq(p.clip, nil)
			t.eq(p.drop, 0)
		end
		t.eq(AnimationDriver.medPose("down", 0.5).drop, 0, "a tiny body is never pushed up")
		t.truthy(AnimationDriver.DEFAULT_CLIPS.human.sit ~= nil, "the sit clip the pose needs is in the stock set")
	end)

	t.test("the cots: one per bed, inside the hospital, the mattress top BED.top above the floor", function()
		local data = Data.default()
		local layout = HospitalLayout.fromData(data) :: HospitalLayout.Layout
		local cots = HospitalProps.spec(layout)
		t.eq(#cots, #layout.beds)
		local floorY = Height.at(layout.lot.x, layout.lot.z) + 0.42 * 2.5
		for i, cot in cots do
			local bed = layout.beds[i]
			local top = -math.huge
			local mattress = nil
			for _, p in cot.parts do
				t.truthy(HospitalLayout.contains(layout, p.x, p.z, -2), `cot {i}: {p.name} is outside the hospital`)
				t.truthy(p.y - p.sy / 2 >= floorY - 1e-6, `cot {i}: {p.name} is under the floor`)
				t.truthy(p.sx > 0 and p.sy > 0 and p.sz > 0)
				if p.name == "Mattress" then
					mattress = p
					top = p.y + p.sy / 2
				end
			end
			t.truthy(mattress ~= nil, `cot {i} has no mattress`)
			t.near(top, floorY + HospitalLayout.BED.top, 1e-6, `cot {i}: the mattress top`)
			t.near((mattress :: any).x, bed.x, 1e-6, "the patient sits on the middle of the mattress")
			t.near((mattress :: any).z, bed.z, 1e-6)
			t.eq(#cot.parts, 5)
			-- the patient looks down the length of the cot, away from the pillow: their legs (laid
			-- flat by the client) stay on the mattress
			local face = HospitalLayout.bedFace(layout, bed)
			local fx, fz = face[1] - bed.x, face[2] - bed.z
			local fl = math.sqrt(fx * fx + fz * fz)
			t.near(
				math.abs(fx * math.sin(cot.yaw) + fz * math.cos(cot.yaw)) / fl,
				1,
				1e-6,
				`cot {i}: the patient faces along it`
			)
			for _, p in cot.parts do
				if p.name == "Pillow" then
					t.truthy((p.x - bed.x) * fx + (p.z - bed.z) * fz < 0, `cot {i}: the pillow is behind the patient`)
				end
			end
			-- legs of about 2 studs from the middle of a mattress this long stay on it
			t.truthy(HospitalLayout.BED.length / 2 >= 2.6)
		end
	end)
	t.test("a sitting patient's legs lie flat: the knees and ankles of the chair sit are straightened", function()
		t.truthy(AnimationDriver.medPose("down", 3).flat, "on the ground")
		t.truthy(AnimationDriver.medPose("treated", 3).flat, "on the cot")
		for _, med in { "symptomatic", "carried", "transit", nil :: any, "nonsense" } do
			t.eq(AnimationDriver.medPose(med, 3).flat, false)
		end
		t.deepEq(AnimationDriver.FLAT_JOINTS, { "LeftKnee", "RightKnee", "LeftAnkle", "RightAnkle" })
	end)

	t.test("walk or run: a body at the paces the sequence uses keeps one clip, however its position arrives", function()
		-- the driver's own measurement: the root's position arrives `hz` times a second and is
		-- drawn at 60, so the observed speed is zero on most frames and several times too high on
		-- the others; `pace` smooths it and `gaitClip` picks the clip
		local function switches(speedAt: (t: number) -> number, hz: number, start: string): (number, { string })
			local dt = 1 / 60
			local every = math.floor(60 / hz + 0.5)
			local pace, clip = speedAt(0), start
			local pending, count = 0, 0
			local seen: { string } = {}
			for frame = 1, 60 * 30 do
				local tt = frame * dt
				pending += speedAt(tt) * dt
				local inst = 0
				if frame % every == 0 then
					inst = pending / dt
					pending = 0
				end
				pace = AnimationDriver.pace(pace, inst, dt)
				local want = AnimationDriver.gaitClip(clip, pace, 9)
				if want ~= clip then
					clip = want
					if tt > 2 then
						count += 1
					end
				end
				if tt > 2 and table.find(seen, clip) == nil then
					table.insert(seen, clip)
				end
			end
			return count, seen
		end
		-- hospital.dischargeSpeed, infection.crewSpeed and bystanderSpeed in studs/s, and every
		-- pace near the threshold: the old single threshold at 9 flipped 14 to 40 times a second
		for _, hz in { 60, 30, 20, 15, 10 } do
			for _, v in { 9.0, 8.625, 8.0, 7.5, 9.5, 10.5, 11, 7 } do
				for _, start in { "walk", "run" } do
					local n = switches(function(): number
						return v
					end, hz, start)
					t.truthy(n <= 1, `{v} studs/s seen at {hz} Hz, starting on {start}: {n} clip changes in 28 s`)
				end
			end
		end
		-- someone walking home at 9 studs/s walks; the crew at 8.6 walks; a flee at 19 runs
		for _, hz in { 60, 20, 10 } do
			for _, case in { { 9.0, "walk" }, { 8.625, "walk" }, { 19, "run" }, { 3, "walk" } } do
				local _, seen = switches(function(): number
					return case[1] :: number
				end, hz, "walk")
				t.deepEq(seen, { case[2] }, `{case[1]} studs/s at {hz} Hz`)
			end
		end
		-- a sick person walking in (the uneven pace of Brains/Directive on infection.walkInSpeed)
		-- staggers at a walk: the run clip at the top of every swing made them jog to the hospital
		local Tunables = require("@shared/Config/Tunables")
		local top = Tunables.get("infection.walkInSpeed")
		t.truthy(top <= 9.01, `the walk in peaks at {top} studs/s`)
		for _, hz in { 60, 20, 10 } do
			local _, seen = switches(function(tt: number): number
				return top * (0.55 + 0.45 * math.abs(math.sin(tt * 0.9)))
			end, hz, "walk")
			t.deepEq(seen, { "walk" }, `the walk in at {hz} Hz`)
		end
		-- and the switch is still quick when someone really starts to run (3 -> 19 studs/s)
		local pace, clip, took = 3, "walk", nil :: number?
		for frame = 1, 120 do
			pace = AnimationDriver.pace(pace, 19, 1 / 60)
			clip = AnimationDriver.gaitClip(clip, pace, 9)
			if clip == "run" and took == nil then
				took = frame / 60
			end
		end
		t.truthy(took ~= nil and (took :: number) < 0.3, `running {took} s after the start of a flee`)
		-- the band is part of the interface
		t.eq(AnimationDriver.gaitClip("walk", 10.49, 9), "walk")
		t.eq(AnimationDriver.gaitClip("walk", 10.5, 9), "run")
		t.eq(AnimationDriver.gaitClip("run", 7.5, 9), "run")
		t.eq(AnimationDriver.gaitClip("run", 7.49, 9), "walk")
		t.eq(AnimationDriver.gaitClip(nil, 9, 9), "walk")
		t.eq(AnimationDriver.gaitClip("idle", 9), "walk")
	end)

	t.test("the stagger: someone with the symptoms sways a few degrees; nobody else does", function()
		local worstRoll, worstPitch, crossings, last = 0, 0, 0, 0
		for i = 0, 600 do
			local roll, pitch = AnimationDriver.sway("symptomatic", i / 60, 1.3)
			worstRoll = math.max(worstRoll, math.abs(roll))
			worstPitch = math.max(worstPitch, math.abs(pitch))
			if roll * last < 0 then
				crossings += 1
			end
			last = if roll ~= 0 then roll else last
		end
		t.truthy(worstRoll > math.rad(2.5) and worstRoll < math.rad(5), `sways {math.deg(worstRoll)} degrees`)
		t.truthy(worstPitch > math.rad(1) and worstPitch < math.rad(3))
		t.truthy(crossings >= 12 and crossings <= 40, `{crossings} sways in 10 s (a stagger, not a shiver)`)
		local a = AnimationDriver.sway("symptomatic", 4, 0.2)
		local b = AnimationDriver.sway("symptomatic", 4, 2.9)
		t.truthy(a ~= b, "two people are out of step")
		for _, med in { "down", "carried", "transit", "treated", nil :: any, 7 } do
			local roll, pitch = AnimationDriver.sway(med, 3.3, 1)
			t.eq(roll, 0)
			t.eq(pitch, 0)
		end
		-- and it can be seen from any side: larger eyes, and a faint red glow on the whole body
		t.truthy(MedicalView.EYE.size >= 0.26, "the eyes can be made out across a street")
		t.eq(MedicalView.look("symptomatic").glow, true)
		t.truthy(MedicalView.GLOW.fill > 0.6 and MedicalView.GLOW.fill < 0.95, "faint")
		for _, med in { "down", "carried", "transit", "treated", nil :: any } do
			t.truthy(not MedicalView.look(med).glow)
		end
	end)
end
