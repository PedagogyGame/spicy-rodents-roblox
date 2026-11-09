--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Animation.AnimationDriver
-- D3: animation is local on every client. Each client creates its own Animator on every body it
-- can see (so no track ever replicates), picks the clip from what the body is doing, and keeps the
-- track running across a possession handoff: the same rule animates an AI body, another player's
-- body and one's own, so "mid-stride" is continuous by construction (BUILD_PLAN §1.5 step 5).
-- Humans: Roblox's own default R15 animations (the stock Animate script's idle 507766388, walk
-- 507777826, run 507767714, jump 507765000, fall 507767968; public, owned by Roblox, referenced not
-- uploaded) chosen by speed, the walk/run rate scaled to the speed so feet do not slide.
-- Four-legged bodies (squirrel, Spicy Rodent, fox, deer): the procedural gait (Animation/Gait) on
-- their RigSpec Motor6Ds (leg swing, knee bend, body bob, head nod, tail sway) set every Stepped.
-- Speed is the body's observed speed (smoothed; horizontal for humans, 3D for animals so climbing
-- animates), which works the same for anchored AI bodies moved by the server and for client-owned
-- bodies. For AI bodies the server's `ClipT0` attribute aligns the clip phase across clients when a
-- track starts. No side effects on require.
-- Interface: start(opts) -> Driver; Driver.stop(); DEFAULT_CLIPS

local Gait = require("./Gait")
local Import = require("../Import")
local PossessionState =
	Import.shared("Actors/PossessionState") :: typeof(require("../../shared/Actors/PossessionState"))

export type ClipSet = {
	idle: string?,
	walk: string?,
	run: string?,
	jump: string?,
	fall: string?,
	nominalRun: number?,
	nominalWalk: number?,
}

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

type Joint = { motor: Motor6D, kind: string, leg: string?, index: number? }

type Entry = {
	body: Model,
	root: BasePart,
	animator: Animator?,
	species: string,
	tracks: { [string]: AnimationTrack },
	current: string?,
	lastPos: Vector3,
	speed: number,
	vy: number,
	-- procedural gait (animals)
	gait: Gait.Params?,
	joints: { Joint },
	tailN: number,
	phase: number,
}

local AnimationDriver = {}

-- Roblox's stock R15 animations (public, owned by Roblox: the default Animate script's IDs). The
-- animals use the procedural Gait (the S7 test clip 92005834447457 stays for the clip pipeline only).
AnimationDriver.DEFAULT_CLIPS = {
	human = {
		idle = "rbxassetid://507766388",
		walk = "rbxassetid://507777826",
		run = "rbxassetid://507767714",
		jump = "rbxassetid://507765000",
		fall = "rbxassetid://507767968",
		nominalWalk = 6, -- the stock walk reads right at about 6 st/s
		nominalRun = 16,
	},
} :: { [string]: ClipSet }

-- The Motor6Ds the gait drives, by RigSpec bone name.
local function gaitJoints(model: Model): ({ Joint }, number)
	local joints: { Joint } = {}
	local tailN = 0
	for _, d in model:GetDescendants() do
		if d:IsA("Motor6D") then
			local name = d.Name
			local leg, seg = string.match(name, "^(%a+[LR])_(%a+)$")
			local tail = string.match(name, "^Tail(%d+)$")
			if leg and (seg == "Upper" or seg == "Lower") then
				table.insert(joints, { motor = d, kind = seg :: string, leg = leg } :: Joint)
			elseif tail then
				local i = tonumber(tail) :: number
				tailN = math.max(tailN, i)
				table.insert(joints, { motor = d, kind = "Tail" :: string, index = i } :: Joint)
			elseif name == "Head" or name == "Root" then
				table.insert(joints, { motor = d, kind = name :: string } :: Joint)
			end
		end
	end
	return joints, tailN
end

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
		local animator = e.animator
		if animator == nil then
			return nil
		end
		local ok, loaded = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if not ok then
			warn(`AnimationDriver: cannot load {id}: {loaded}`)
			return nil
		end
		local lt = loaded :: AnimationTrack
		lt.Looped = name ~= "jump"
		lt.Priority = if name == "idle" then Enum.AnimationPriority.Idle else Enum.AnimationPriority.Movement
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
		local sp = model:GetAttribute(PossessionState.ATTR.Species)
		local species = if type(sp) == "string" then sp else "human"
		local gait: Gait.Params? = nil
		local joints: { Joint } = {}
		local tailN = 0
		local animator: Animator? = nil
		if Gait.PROCEDURAL[species] and clips[species] == nil then
			local hip = model:GetAttribute("HipHeight")
			gait = Gait.params(species, if type(hip) == "number" then hip else nil)
			joints, tailN = gaitJoints(model)
		else
			animator = ensureAnimator(model)
			if animator == nil then
				return
			end
		end
		entries[model] = {
			body = model,
			root = root,
			animator = animator,
			species = species,
			tracks = {},
			current = nil,
			lastPos = root.Position,
			speed = 0,
			vy = 0,
			gait = gait,
			joints = joints,
			tailN = tailN,
			phase = (#model.Name * 0.37) % (2 * math.pi),
		}
		count += 1
	end

	local function remove(child: Instance)
		local e = entries[child :: any]
		if e then
			for _, t in e.tracks do
				t:Stop(0)
			end
			for _, j in e.joints do
				j.motor.Transform = CFrame.identity
			end
			entries[child :: any] = nil
			count -= 1
		end
	end

	local function choose(e: Entry): string
		local set: ClipSet = clips[e.species] or {}
		if set.jump and e.vy > 6 then
			return "jump"
		elseif set.fall and e.vy < -10 then
			return "fall"
		end
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
			-- animals measure 3D speed so a climb up a trunk animates like a run
			local inst = (if e.gait then d.Magnitude else Vector3.new(d.X, 0, d.Z).Magnitude) / dt
			local vy = d.Y / dt
			if inst > 200 then
				inst = e.speed -- a teleport or recovery, not motion
				vy = 0
			end
			e.speed += (inst - e.speed) * alpha
			e.vy += (vy - e.vy) * alpha
			if e.gait then
				continue -- posed in Stepped (gaitStep)
			end
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

	-- the procedural gait writes Motor6D.Transform in Stepped (before the joints are solved)
	local clock = 0
	local function gaitStep(_t: number, dt: number)
		clock += dt
		for _, e in entries do
			local p = e.gait
			if p == nil or #e.joints == 0 then
				continue
			end
			e.phase = Gait.advance(e.phase, e.speed, dt, p)
			local pose = Gait.pose(e.phase, e.speed, clock, p, e.tailN)
			for _, j in e.joints do
				local cf = CFrame.identity
				if j.kind == "Upper" then
					cf = CFrame.Angles(pose.legs[j.leg :: string].upper, 0, 0)
				elseif j.kind == "Lower" then
					cf = CFrame.Angles(pose.legs[j.leg :: string].lower, 0, 0)
				elseif j.kind == "Tail" then
					local seg = pose.tail[j.index :: number]
					if seg then
						cf = CFrame.Angles(seg.pitch, seg.yaw, 0)
					end
				elseif j.kind == "Head" then
					cf = CFrame.Angles(pose.head, 0, 0)
				elseif j.kind == "Root" then
					cf = CFrame.new(0, pose.bob, 0) * CFrame.Angles(pose.rock, 0, 0)
				end
				j.motor.Transform = cf
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
		RunService.Stepped:Connect(gaitStep),
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
