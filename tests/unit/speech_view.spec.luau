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
		t.deepEq(MedicalView.look("symptomatic"), { hidden = false, eyes = true, pose = "stagger" })
		t.deepEq(MedicalView.look("down"), { hidden = false, eyes = false, pose = "down" })
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
		t.truthy(seen.symptomatic and seen.down and seen.transit and seen.treated)
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
		for _, med in { "symptomatic", "transit", nil :: any, "nonsense" } do
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
		end
	end)
end
