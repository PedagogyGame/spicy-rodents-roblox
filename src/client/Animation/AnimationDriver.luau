--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Animation.AnimationDriver
-- D3: animation is local on every client. Each client creates its own Animator on every body it
-- can see (so no track ever replicates), picks the clip from what the body is doing, and keeps the
-- track running across a possession handoff: the same rule animates an AI body, another player's
-- body and one's own, so "mid-stride" is continuous by construction (BUILD_PLAN §1.5 step 5).
-- W0 minimal (spike S2): the human R15 (idle / walk / run) and the squirrel puppet (one run clip,
-- rate scaled by speed, held on its current frame when stopped). Speed is the body's observed
-- horizontal speed (smoothed), which works the same for anchored AI bodies moved by the server
-- and for client-owned bodies. For AI bodies the server's `ClipT0` attribute aligns the clip phase
-- across clients when a track starts. W1 adds per-species clip sets from the manifest.
-- No side effects on require.
-- Interface: start(opts) -> Driver; Driver.stop(); DEFAULT_CLIPS

local Import = require("../Import")
local PossessionState =
	Import.shared("Actors/PossessionState") :: typeof(require("../../shared/Actors/PossessionState"))

export type ClipSet = { idle: string?, walk: string?, run: string?, nominalRun: number?, nominalWalk: number? }

export type Opts = {
	container: Instance, -- the folder whose child Models are bodies
	clips: { [string]: ClipSet }?, -- by Species attribute
	walkAbove: number?, -- studs/s (default 0.4)
	runAbove: number?, -- studs/s (default 9)
}

export type Driver = {
	stop: () -> (),
	bodies: () -> number,
}

type Entry = {
	body: Model,
	root: BasePart,
	animator: Animator,
	species: string,
	tracks: { [string]: AnimationTrack },
	current: string?,
	lastPos: Vector3,
	speed: number,
}

local AnimationDriver = {}

-- Roblox's stock R15 animations (public, owned by Roblox) and the S7 test clip (owner-owned upload).
AnimationDriver.DEFAULT_CLIPS = {
	human = {
		idle = "rbxassetid://507766388",
		walk = "rbxassetid://507777826",
		run = "rbxassetid://507767714",
		nominalWalk = 6, -- the stock walk reads right at about 6 st/s
		nominalRun = 16,
	},
	squirrel = {
		run = "rbxassetid://92005834447457", -- S7 squirrel Run, 0.667 s loop
		nominalRun = 20, -- 8 u/s ground walk (Species)
	},
} :: { [string]: ClipSet }

local function ensureAnimator(body: Model): Animator?
	local host: Instance? = body:FindFirstChildOfClass("Humanoid")
	if host == nil then
		host = body:FindFirstChildOfClass("AnimationController")
		if host == nil then
			local ac = Instance.new("AnimationController")
			ac.Parent = body
			host = ac
		end
	end
	local hostInst = host :: Instance
	local existing = hostInst:FindFirstChildOfClass("Animator")
	if existing then
		return existing
	end
	local animator = Instance.new("Animator")
	animator.Parent = hostInst -- created on this client: never replicates (D3)
	return animator
end

function AnimationDriver.start(opts: Opts): Driver
	local RunService = game:GetService("RunService")
	local clips = opts.clips or AnimationDriver.DEFAULT_CLIPS
	local walkAbove = opts.walkAbove or 0.4
	local runAbove = opts.runAbove or 9
	local entries: { [Model]: Entry } = {}
	local count = 0

	local function track(e: Entry, name: string): AnimationTrack?
		local t = e.tracks[name]
		if t then
			return t
		end
		local set = clips[e.species]
		local id = set and (set :: any)[name]
		if type(id) ~= "string" then
			return nil
		end
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, loaded = pcall(function()
			return e.animator:LoadAnimation(anim)
		end)
		if not ok then
			warn(`AnimationDriver: cannot load {id}: {loaded}`)
			return nil
		end
		local lt = loaded :: AnimationTrack
		lt.Looped = true
		lt.Priority = Enum.AnimationPriority.Movement
		e.tracks[name] = lt
		return lt
	end

	local function add(child: Instance)
		if not child:IsA("Model") or entries[child] then
			return
		end
		local model = child :: Model
		local root = model.PrimaryPart
		if root == nil then
			return
		end
		local animator = ensureAnimator(model)
		if animator == nil then
			return
		end
		local species = model:GetAttribute(PossessionState.ATTR.Species)
		entries[model] = {
			body = model,
			root = root,
			animator = animator,
			species = if type(species) == "string" then species else "human",
			tracks = {},
			current = nil,
			lastPos = root.Position,
			speed = 0,
		}
		count += 1
	end

	local function remove(child: Instance)
		local e = entries[child :: any]
		if e then
			for _, t in e.tracks do
				t:Stop(0)
			end
			entries[child :: any] = nil
			count -= 1
		end
	end

	local function choose(e: Entry): string
		local set: ClipSet = clips[e.species] or {}
		if e.speed < walkAbove then
			return if set.idle then "idle" elseif set.run then "hold" else "none"
		end
		if set.walk and e.speed < runAbove then
			return "walk"
		end
		return if set.run then "run" else "walk"
	end

	local function step(dt: number)
		if dt <= 0 then
			return
		end
		local alpha = math.min(1, dt / 0.15)
		for _, e in entries do
			local pos = e.root.Position
			local d = pos - e.lastPos
			e.lastPos = pos
			local inst = Vector3.new(d.X, 0, d.Z).Magnitude / dt
			if inst > 200 then
				inst = e.speed -- a teleport or recovery, not motion
			end
			e.speed += (inst - e.speed) * alpha
			local want = choose(e)
			local set: ClipSet = clips[e.species] or {}
			if want == "hold" then
				-- squirrel puppet stopped: freeze the run clip where it is (no snap to the rest pose)
				local t = e.tracks.run
				if t and t.IsPlaying then
					t:AdjustSpeed(0)
				end
				e.current = "hold"
				continue
			end
			if want ~= e.current then
				local nextTrack = if want ~= "none" then track(e, want) else nil
				for name, t in e.tracks do
					if name ~= want and t.IsPlaying then
						t:Stop(0.2)
					end
				end
				if nextTrack and not nextTrack.IsPlaying then
					nextTrack:Play(0.2)
					local t0 = e.body:GetAttribute(PossessionState.ATTR.ClipT0)
					if type(t0) == "number" and nextTrack.Length > 0 then
						nextTrack.TimePosition = (workspace:GetServerTimeNow() - t0) % nextTrack.Length
					end
				end
				e.current = want
			end
			local cur = e.current and e.tracks[e.current]
			if cur then
				local nominal = if e.current == "run"
					then set.nominalRun
					elseif e.current == "walk" then set.nominalWalk
					else nil
				cur:AdjustSpeed(if nominal then math.clamp(e.speed / nominal, 0.3, 2.5) else 1)
			end
		end
	end

	for _, child in opts.container:GetChildren() do
		add(child)
	end
	local conns = {
		opts.container.ChildAdded:Connect(add),
		opts.container.ChildRemoved:Connect(remove),
		RunService.RenderStepped:Connect(step),
	}

	return {
		stop = function()
			for _, c in conns do
				c:Disconnect()
			end
			for model in entries do
				remove(model)
			end
		end,
		bodies = function(): number
			return count
		end,
	}
end

return AnimationDriver
