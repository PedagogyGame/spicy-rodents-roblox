--!strict
-- Luau Execution task: do the authored clips move the Bones of a hero body as the game prepares it?
-- (Server/Assets/HeroArt renames the imported root and adds its own; the client then plays the clips
-- through an Animator under an AnimationController.) Builds a hero squirrel through BodyFactory, plays
-- each looping clip, steps the Animator by hand and reports how far a few bones turned from rest.
--   node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/hero_clips.luau --version <v> --place ci

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local server = ServerScriptService:WaitForChild("Server")
local HeroArt = (require :: any)(server.Assets.HeroArt)
local BodyFactory = (require :: any)(server.Actors.BodyFactory)
local HeroAssets = (require :: any)(ReplicatedStorage.Shared.Actors.HeroAssets)

local failures: { string } = {}
local report = HeroArt.install()
local body = BodyFactory.build("squirrel", "normal", 950)
body.Parent = workspace
local controller = body:FindFirstChildOfClass("AnimationController") or Instance.new("AnimationController")
controller.Parent = body
local animator = controller:FindFirstChildOfClass("Animator") or Instance.new("Animator")
animator.Parent = controller

local bones: { [string]: Bone } = {}
for _, d in body:GetDescendants() do
	if d:IsA("Bone") then
		bones[d.Name] = d
	end
end
local watch = { "Spine2", "Tail3", "Tail6", "FrontL_Upper", "BackL_Lower", "Head", "Root" }
local function turned(): { [string]: number }
	local out: { [string]: number } = {}
	for _, name in watch do
		local b = bones[name]
		if b then
			local _, angle = b.Transform:ToAxisAngle()
			out[name] = math.floor((angle + b.Transform.Position.Magnitude) * 1000 + 0.5) / 1000
		end
	end
	return out
end

local clips: { [string]: any } = {}
for _, name in { "Run", "Idle", "Walk", "Climb", "Wire", "Leap", "Stalk" } do
	local clip = HeroAssets.CLIPS.squirrel[name]
	local rec: { [string]: any } = { id = clip.id }
	local anim = Instance.new("Animation")
	anim.AnimationId = clip.id
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	rec.loaded = ok
	if ok then
		local t = track :: AnimationTrack
		-- the clip's content loads in the background: wait for it (Length is 0 until then)
		local waited = 0
		while t.Length <= 0 and waited < 8 do
			waited += task.wait(0.1)
		end
		rec.waited = waited
		t.Looped = clip.loop
		t:Play(0)
		local most = 0
		local stepped, err = pcall(function()
			for _ = 1, 6 do
				(animator :: any):StepAnimations(clip.length / 7)
				for _, v in turned() do
					most = math.max(most, v)
				end
			end
		end)
		rec.stepped = stepped
		rec.stepError = if stepped then nil else tostring(err)
		rec.length = t.Length
		rec.mostTurn = most
		rec.sample = turned()
		t:Stop(0)
		if stepped and most < 0.02 then
			table.insert(failures, `{name}: the clip plays but no watched bone moves`)
		end
	else
		table.insert(failures, `{name}: {track}`)
	end
	clips[name] = rec
end
body:Destroy()
print(`hero_clips: failures={#failures}`)
for _, f in failures do
	print("  FAIL " .. f)
end
return {
	suite = "hero_clips",
	ok = #failures == 0,
	failures = failures,
	install = report,
	clips = clips,
	placeVersion = game.PlaceVersion,
}
