--!strict
-- The small pieces of the overhead watch (owner playtest 2026-11-19): Speech/AreaPace (the chatter cap by place),
-- Combat/Duel.notices (the duel's noticing is the town's perception: seen in the view cone, heard faster than a creep,
-- felt when it brushes them, never the pounce itself, overhead only when pointed out), the Pedestrian's "overhead"
-- orders (never into a duel's order or a flight), the client's pieces (the eye's words in town, the pointing arm, the
-- head's angles), and the new line groups' sizes.
local AreaPace = require("@shared/Speech/AreaPace")
local Lines = require("@shared/Speech/Lines")
local CombatRules = require("@shared/Combat/CombatRules")
local Duel = require("@shared/Combat/Duel")
local Pedestrian = require("@server/Actors/Brains/Pedestrian")
local Common = require("@server/Actors/Brains/Common")
local SneakMeter = require("@client/UI/SneakMeter")
local StanceView = require("@client/Render/StanceView")
local GazeView = require("@client/Render/GazeView")

return function(t)
	t.test("AreaPace: at most `max` lines in an area's window; an opener needs room for its answer", function()
		local a = AreaPace.new({ radius = 40, window = 10, max = 3 })
		t.truthy(AreaPace.allow(a, 0, 0, 0, 2))
		AreaPace.note(a, 0, 0, 0)
		AreaPace.note(a, 1, 10, 0)
		t.falsy(AreaPace.allow(a, 2, 5, 5, 2), "no room for a line and its answer")
		t.truthy(AreaPace.allow(a, 2, 5, 5), "room for one")
		t.truthy(AreaPace.allow(a, 2, 200, 0, 2), "another street is its own")
		AreaPace.note(a, 2, 5, 5)
		t.falsy(AreaPace.allow(a, 3, 0, 0))
		t.truthy(AreaPace.allow(a, 10.5, 0, 0), "the window slides")
		t.eq(AreaPace.count(a, 12.5, 0, 0), 0)
	end)

	t.test(
		"the overhead line groups: 6 to 10 lines each (4 for a place); a line names a place only in its group",
		function()
			for _, g in { "overhead", "overheadUneasy", "overheadReply", "overheadWary", "overheadLost" } do
				local n = #Lines.of(g)
				t.truthy(n >= 6 and n <= 10, `{g}: {n} lines`)
			end
			-- (review L5: "Up in the tree!" about a squirrel on a wire; "creeping" about one walking)
			local places = {
				overheadWire = { "wire", "power line" },
				overheadFence = { "fence" },
				overheadTree = { "tree", "branch" },
				overheadRoof = { "roof" },
			}
			for g, words in places do
				t.truthy(#Lines.of(g) >= 4, `{g}: {#Lines.of(g)} lines`)
				for _, line in Lines.of(g) do
					local named = false
					for _, w in words do
						named = named or string.find(string.lower(line), w, 1, true) ~= nil
					end
					t.truthy(named, `"{line}" names its place ({g})`)
				end
			end
			for _, g in { "overhead", "overheadUneasy", "overheadReply", "overheadWary", "overheadLost" } do
				for _, line in Lines.of(g) do
					local l = string.lower(line)
					for _, w in { "wire", "power line", "fence", "tree", "branch", "roof", "creep" } do
						-- (whole words: "street" is no tree)
						t.falsy(
							string.find(l, "%f[%a]" .. w, 1),
							`"{line}" ({g}) says nothing of where it is or how it moves`
						)
					end
				end
			end
			local OverheadService = require("@server/Stealth/OverheadService")
			for kind, g in OverheadService.SURFACE do
				t.truthy(places[g] ~= nil, `{kind} -> {g}`)
			end
		end
	)

	t.test("Duel.notices: the town's perception (view cone, a noise faster than a creep, a brush, overhead)", function()
		local P = CombatRules.params()
		local g = Duel.new(P, 1, "calm", 0.25)
		local function n(s: Duel.Sight): boolean
			return Duel.notices(P, g, s)
		end
		t.truthy(n({ dist = 30, inView = true, speed = 0 }), "seen in view within the spot range")
		t.falsy(n({ dist = 40, inView = true, speed = 0 }), "not beyond it")
		t.falsy(n({ dist = 10, inView = false, speed = 4 }), "a creep behind at 10 studs is not noticed")
		t.falsy(n({ dist = 16, inView = false, speed = 0 }), "nor a still one at 16 (the old rule's 17)")
		t.truthy(n({ dist = 20, inView = false, speed = 18 }), "a walk behind at 20 is heard")
		t.falsy(n({ dist = 8, inView = false, speed = 31, lunging = true }), "the pounce itself is not")
		t.truthy(n({ dist = 3, inView = false, speed = 0 }), "a brush is felt")
		t.falsy(n({ dist = 3, inView = false, speed = 0, lunging = true }), "but not a lunge's last stride")
		t.falsy(n({ dist = 5, dy = 25, inView = true, speed = 18 }), "overhead is not the duel's to see")
		t.falsy(
			n({ dist = 5, dy = 25, inView = false, speed = 0, spottedOverhead = true }),
			"not even pointed out, while it is still up there (out of reach: the watch's)"
		)
		t.truthy(
			n({ dist = 9, dy = 0, inView = false, speed = 0, spottedOverhead = true }),
			"pointed out, it is met aware once it comes down"
		)
		local tough = Duel.new(P, 2, "tough", 1)
		t.truthy(Duel.notices(P, tough, { dist = 26, inView = false, speed = 18 }), "a vigilante hears further")
	end)

	t.test("Pedestrian: the overhead watch's orders, never into a duel's order or a flight", function()
		local rng = function(): number
			return 0.3
		end
		local actor = Common.newActor(1, "human", "default", "Pedestrian", 0, 0, 1.5)
		local brain: any = Pedestrian.new(
			actor,
			{ lanes = Pedestrian.defaultLanes(), coreLanes = 4, speedMin = 3, speedMax = 3, rng = rng }
		)
		brain:onEvent({ type = "overhead", mode = "stand", x = 5, z = 5, untilTime = 10 })
		t.eq(brain.state, "duel")
		t.eq(brain.duelSource, "overhead")
		brain:onEvent({ type = "duel", mode = "approach", x = 1, z = 1, speed = 6, untilTime = 10 })
		t.eq(brain.duelSource, "duel", "the duel's order cuts into it")
		brain:onEvent({ type = "overhead", mode = "back", x = 5, z = 5, speed = 5, untilTime = 10 })
		t.eq(brain.duel.mode, "approach", "and is not cut into")
		brain:onEvent({ type = "duel", mode = "end" })
		brain:onEvent({ type = "overhead", mode = "hurry", x = 5, z = 5, untilTime = 20 })
		t.eq(brain.hurryUntil, 20, "hurrying on")
		brain:onEvent({ type = "witness", threat = actor, alert = 8 })
		if brain.state == "flee" then
			brain:onEvent({ type = "overhead", mode = "stand", x = 5, z = 5, untilTime = 30 })
			t.eq(brain.state, "flee", "a flight is not stopped to look up")
		end
	end)

	t.test("the client: the eye's words in town, the pointing arm under a stance, the head's angles", function()
		local m, seen, where = SneakMeter.pick(nil, nil, 0.5, false)
		t.eq(m, 0.5)
		t.eq(where, "overhead")
		t.falsy(seen)
		local look = SneakMeter.look(m, seen, false, where)
		t.eq(look.words, SneakMeter.WORDS.overhead)
		local _, _, w2 = SneakMeter.pick(0.2, true, 0.9, false)
		t.eq(w2, "rafters", "a spotted eye wins")
		local _, _, w3 = SneakMeter.pick(0.2, false, 0.9, false)
		t.eq(w3, "overhead", "else the fuller")
		t.eq(SneakMeter.look(0.5, false).words, SneakMeter.WORDS.watching, "the rafters keep their words")
		t.eq(StanceView.effective(nil, "point"), "point")
		t.eq(StanceView.effective("guard", "point"), "guard", "a stance wins over a gesture")
		t.truthy(StanceView.turns("point").RightShoulder ~= nil)
		for name in StanceView.turns("point") do
			t.truthy(table.find(StanceView.JOINTS, name) ~= nil, name)
		end
		local p, y = GazeView.angles(0, 10, -10)
		t.near(p, math.rad(45), 1e-6, "up at 45 degrees ahead")
		t.near(y, 0, 1e-6)
		local p2, y2 = GazeView.angles(-10, 40, 0)
		t.near(p2, GazeView.PITCH_MAX, 1e-6, "no further back than a neck goes")
		t.near(y2, GazeView.YAW_MAX, 1e-6, "nor round")
	end)
end
