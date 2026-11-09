--!strict
-- tools/anim/KeyframeBuilder (BUILD_PLAN D11, spike S7): a spicy-clip/1 table becomes a
-- KeyframeSequence with RigSpec-named Poses nested like the bone tree, CFrames survive an .rbxm
-- round trip, markers land on their keyframes, invalid clips are refused with every problem listed,
-- and the committed S7 test clip only poses squirrel bones.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local KeyframeBuilder = require("../../tools/anim/KeyframeBuilder")
local RigSpec = require("@shared/Actors/RigSpec")

local IDENTITY = { 0, 0, 0, 1, 0, 0, 0, 1, 0, 0, 0, 1 }

local function rotX(a: number, y: number): { number }
	local c, s = math.cos(a), math.sin(a)
	return { 0, y, 0, 1, 0, 0, 0, c, -s, 0, s, c }
end

local function clip(): KeyframeBuilder.Clip
	return {
		format = "spicy-clip/1",
		rig = "squirrel",
		clip = "Test",
		fps = 30,
		loop = true,
		priority = "Movement",
		rootPart = "RootPart",
		bones = {
			{ name = "Root" },
			{ name = "Hips", parent = "Root" },
			{ name = "Tail1", parent = "Hips" },
			{ name = "FrontL_Upper", parent = "Hips" },
		},
		keyframes = {
			{ time = 0, poses = { Root = IDENTITY, Hips = IDENTITY, Tail1 = rotX(0.25, 0), FrontL_Upper = IDENTITY } },
			{ time = 0.1, poses = { Root = IDENTITY, Hips = rotX(0.1, 0.05), Tail1 = rotX(0.5, 0) } },
			{
				time = 0.2,
				poses = { Root = IDENTITY, Hips = IDENTITY, Tail1 = rotX(0.25, 0), FrontL_Upper = IDENTITY },
			},
		},
		markers = { { time = 0.1, name = "Commit", value = "stride" } },
	}
end

local function keyframesOf(seq: any): { any }
	local list = {}
	for _, c in seq:GetChildren() do
		if c.ClassName == "Keyframe" then
			table.insert(list, c)
		end
	end
	table.sort(list, function(a: any, b: any)
		return a.Time < b.Time
	end)
	return list
end

return function(t)
	t.test("builds the Keyframe/Pose tree with the root part and nested bones", function()
		local seq = KeyframeBuilder.build(clip())
		t.eq(seq.ClassName, "KeyframeSequence")
		t.eq(seq.Name, "Test")
		t.truthy(seq.Loop, "loop")
		t.eq(seq.Priority, roblox.Enum.AnimationPriority.Movement, "priority")
		local s = KeyframeBuilder.summarize(seq)
		t.eq(s.keyframes, 3)
		t.near(s.duration, 0.2, 1e-6)
		t.deepEq(s.poseNames, { "RootPart", "Root", "Hips", "Tail1", "FrontL_Upper" })
		local kf = keyframesOf(seq)[1]
		local hips = kf:FindFirstChild("RootPart"):FindFirstChild("Root"):FindFirstChild("Hips")
		t.truthy(hips and hips:FindFirstChild("Tail1"), "Tail1 nests under Hips")
	end)

	t.test("pose CFrames, weights and easing survive an .rbxm round trip", function()
		local bytes = roblox.serializeModel({ KeyframeBuilder.build(clip()) })
		local seq = roblox.deserializeModel(bytes)[1]
		local kf2 = keyframesOf(seq)[2]
		local hips = kf2:FindFirstChild("Hips", true)
		local rx = hips.CFrame:ToOrientation()
		t.near(rx, 0.1, 1e-4, "Hips rotation (measured error about 5e-6 rad after the round trip)")
		t.near(hips.CFrame.Position.Y, 0.05, 1e-4, "Hips offset (measured error about 3e-6 studs)")
		t.eq(hips.Weight, 1)
		t.eq(hips.EasingStyle, roblox.Enum.PoseEasingStyle.Linear)
		-- A bone without a pose in a keyframe stays in the tree with weight 0 (no influence).
		local front = kf2:FindFirstChild("FrontL_Upper", true)
		t.eq(front.Weight, 0)
	end)

	t.test("markers sit on the keyframe with the same time", function()
		local kf = keyframesOf(KeyframeBuilder.build(clip()))
		local marker = kf[2]:FindFirstChildOfClass("KeyframeMarker")
		t.truthy(marker, "marker on keyframe 2")
		t.eq(marker.Name, "Commit")
		t.eq(marker.Value, "stride")
		t.falsy(kf[1]:FindFirstChildOfClass("KeyframeMarker"), "no marker on keyframe 1")
	end)

	t.test("invalid clips are refused with every problem listed", function()
		local bad = clip()
		bad.format = "other"
		table.insert(bad.bones, { name = "Ghost", parent = "Nowhere" })
		bad.keyframes[2].poses.Unknown = IDENTITY
		bad.keyframes[3].poses.Hips = { 1, 2, 3 }
		bad.keyframes[3].time = 0.05
		bad.markers = { { time = 0.15, name = "Recover" } }
		local problems = KeyframeBuilder.validate(bad)
		t.eq(#problems, 6, table.concat(problems, "; "))
		t.fails(function()
			KeyframeBuilder.build(bad)
		end, "invalid clip")
		t.eq(#KeyframeBuilder.validate(clip()), 0)
	end)

	t.test("the committed S7 clip poses only squirrel bones (RigSpec names)", function()
		local path = "assets/test/squirrel_Run_s7.rbxm"
		if not fs.isFile(path) then
			return
		end
		local seq = roblox.deserializeModel(fs.readFile(path))[1]
		local s = KeyframeBuilder.summarize(seq)
		t.eq(s.keyframes, 21)
		t.near(s.duration, 20 / 30, 1e-5)
		local bones: { [string]: boolean } = {}
		for _, b in RigSpec.squirrel.bones do
			bones[b] = true
		end
		t.eq(s.poseNames[1], RigSpec.squirrel.primaryPart, "root pose is the primary part")
		for i = 2, #s.poseNames do
			t.truthy(bones[s.poseNames[i]], `{s.poseNames[i]} is a RigSpec squirrel bone`)
		end
		t.deepEq(s.markers, { "Commit", "Recover" })
	end)
end
