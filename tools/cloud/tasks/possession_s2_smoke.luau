--!strict
-- Luau Execution task (spike S2): smoke of the places/s2 owner test place on a saved CI version,
-- then the 500-cycle Possession soak in the same task (one create against the shared quota).
-- Smoke: S2Harness.build() (scripts do not auto-run here) -> 6 R15 humans + 3 S7 puppets in
-- Workspace.Bodies, prepared as AI bodies (root-only anchoring, no scripts, no server Animator,
-- Atomic, attributes), the remotes exist, 120 AI frames move every body with BulkMoveTo, one
-- possess / swap / release / recover round with a PlayerLike stub through the stub engine, and
-- the place properties D1 needs.
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/possession_s2_smoke.luau --version <v> --place ci
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local ServerStorage = game:GetService("ServerStorage")

local started = os.clock()
local failures: { string } = {}
local function expect(cond: boolean, what: string)
	if not cond then
		table.insert(failures, what)
	end
end

local s2 = ServerScriptService:FindFirstChild("S2") or error("ServerScriptService.S2 missing: not a places/s2 build")
local Harness = (require :: any)(s2:FindFirstChild("S2Harness") :: ModuleScript)
local t0 = os.clock()
local world = Harness.build()
local buildMs = (os.clock() - t0) * 1000

-- bodies
local humans, squirrels, scripts, animators, anchoredLimbs = 0, 0, 0, 0, 0
for _, body in world.folder:GetChildren() do
	if body:IsA("Model") then
		local species = body:GetAttribute("Species")
		if species == "human" then
			humans += 1
			expect(body:FindFirstChildOfClass("Humanoid") ~= nil, `{body.Name}: no Humanoid`)
		elseif species == "squirrel" then
			squirrels += 1
			expect(body:FindFirstChildOfClass("AnimationController") ~= nil, `{body.Name}: no AnimationController`)
			expect(body:FindFirstChild("Head") ~= nil, `{body.Name}: no Head (bubble adornee)`)
			expect(body:FindFirstChildOfClass("Humanoid") == nil, `{body.Name}: squirrel has a Humanoid`)
		end
		expect(body.ModelStreamingMode == Enum.ModelStreamingMode.Atomic, `{body.Name}: not Atomic`)
		expect(body.PrimaryPart ~= nil and body.PrimaryPart.Anchored, `{body.Name}: root not anchored`)
		for _, d in body:GetDescendants() do
			if d:IsA("BaseScript") then
				scripts += 1
			elseif d:IsA("Animator") then
				animators += 1
			elseif d:IsA("BasePart") and d ~= body.PrimaryPart and d.Anchored then
				anchoredLimbs += 1
			end
		end
	end
end
expect(humans == 6, `humans {humans}`)
expect(squirrels == 3, `squirrels {squirrels}`)
expect(scripts == 0, `scripts left in bodies: {scripts}`)
expect(animators == 0, `server Animators left: {animators}`)
expect(anchoredLimbs == 0, `anchored limbs: {anchoredLimbs}`)
local net = ReplicatedStorage:FindFirstChild("PossessionNet")
for _, n in { "Granted", "Released", "Recover", "S2Debug" } do
	expect(net ~= nil and net:FindFirstChild(n) ~= nil, `remote {n} missing`)
end

-- AI frames: every body moves, limbs follow the root
local before: { [string]: Vector3 } = {}
for _, a in world.list do
	before[a.id] = (a.body :: Model):GetPivot().Position
end
local limb = (world.list[1].body :: Model):FindFirstChild("LeftFoot") :: BasePart?
local limbOffset = limb and ((world.list[1].body :: Model):GetPivot():PointToObjectSpace(limb.Position))
local aiT0 = os.clock()
for _ = 1, 120 do
	Harness.stepAI(world, 1 / 60)
end
local aiMs = (os.clock() - aiT0) * 1000 / 120
local minMoved = math.huge
for _, a in world.list do
	local d = ((a.body :: Model):GetPivot().Position - before[a.id]).Magnitude
	minMoved = math.min(minMoved, d)
end
expect(minMoved > 5, `a body did not move (min {minMoved} st in 2 s)`)
local limbErr = 0
if limb and limbOffset then
	limbErr = ((world.list[1].body :: Model):GetPivot():PointToObjectSpace(limb.Position) - limbOffset).Magnitude
	expect(limbErr < 1e-3, `LeftFoot did not follow the root ({limbErr} st)`)
end

-- one possession round with a stub player
local engine = world.possession.engine
local owners: { [Instance]: any } = {}
engine.streamAround = function() end
engine.setOwner = function(root: any, player: any?)
	if player == nil then
		root:SetNetworkOwner(nil)
	elseif not root:CanSetNetworkOwnership() then
		error("CanSetNetworkOwnership false")
	end
	owners[root] = player
end
engine.setCharacter = function(player: any, model: any?)
	player.Character = model
end
local granted = 0
world.possession.deps.onGranted = function()
	granted += 1
end
world.possession.deps.onReleased = function() end
local stub = { UserId = -1, Name = "Stub1", Character = nil }
local r1 = world.roles:onJoin(stub)
expect(r1 == "possessed", `join -> {r1}`)
local h = world.possession:actorOf(stub)
expect(h ~= nil and h.species == "human", "join did not give a human")
local sq = Harness.nearestFree(world, "squirrel", stub)
local okSwap = world.possession:swap(stub, sq)
expect(okSwap == true, "swap to squirrel failed")
expect(stub.Character == sq.body, "Character is not the squirrel")
expect(not ((sq.body :: Model).PrimaryPart :: BasePart).Anchored, "possessed squirrel root still anchored")
expect(h.mode == "ai" and ((h.body :: Model).PrimaryPart :: BasePart).Anchored, "old human not back in AI")
expect(world.possession:recover(stub), "recover failed")
world.roles:onLeave(stub)
expect(stub.Character == nil and sq.mode == "ai", "leave did not release")
Harness.stepAI(world, 1 / 60)
expect(world.lastResumeMs ~= nil, "AI did not resume on the next frame")
local ok, errs = world.possession:check()
expect(ok, "invariants: " .. table.concat(errs, "; "))
expect(granted == 2, `granted {granted}`)

-- place properties D1 needs
local props: { [string]: any } = {}
for _, spec in
	{
		{ Players, "CharacterAutoLoads" },
		{ workspace, "PlayerCharacterDestroyBehavior" },
		{ workspace, "StreamingEnabled" },
		{ workspace, "SignalBehavior" },
	}
do
	local inst, name = spec[1] :: Instance, spec[2] :: string
	local okRead, v = pcall(function()
		return (inst :: any)[name]
	end)
	props[name] = if okRead then tostring(v) else "unreadable"
end
expect(props.CharacterAutoLoads == "false", "CharacterAutoLoads is not false")

world.folder:ClearAllChildren()
local smoke = {
	ok = #failures == 0,
	failures = failures,
	buildMs = buildMs,
	aiFrameMs = aiMs,
	minMovedStuds = minMoved,
	limbFollowErr = limbErr,
	properties = props,
	possessMaxMs = world.possession.stats.maxPossessMs,
}
print(`S2 smoke: ok={smoke.ok} failures={#failures} build={math.floor(buildMs)} ms`)
for _, f in failures do
	print("  FAIL " .. f)
end

-- the soak, on the same version (uses ServerStorage.S2Templates' puppet)
local tests = ServerStorage:FindFirstChild("EngineTests") or error("ServerStorage.EngineTests missing")
local Suite = (require :: any)(tests:FindFirstChild("Possession") :: ModuleScript)
local soak = Suite.run({ cycles = 500 })
local s = soak.soak
print(
	`Possession soak: ok={soak.ok} possessed={s.possessed} released={s.released} swaps={s.swaps} leaves={s.leaves} recovers={s.recovers} errors={#s.errors} invariants={#s.invariantFailures} leaked={s.leakedBodies} resumeMax={s.resumeMaxSeconds}`
)
for _, e in s.errors do
	print("  ERR " .. e)
end
for _, e in s.invariantFailures do
	print("  INV " .. e)
end
return {
	suite = "S2",
	ok = smoke.ok and soak.ok,
	smoke = smoke,
	soak = soak,
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
