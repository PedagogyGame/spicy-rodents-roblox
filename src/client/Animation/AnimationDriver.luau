--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Animation.AnimationDriver
-- D3: animation is local on every client. Each client creates its own Animator on every body it
-- can see (so no track ever replicates), picks the clip from what the body is doing, and keeps the
-- track running across a possession handoff: the same rule animates an AI body, another player's
-- body and one's own, so "mid-stride" is continuous by construction (BUILD_PLAN §1.5 step 5).
-- Humans: Roblox's own default R15 animations (the stock Animate script's idle 507766388, walk
-- 507777826, run 507767714, jump 507765000, fall 507767968; public, owned by Roblox, referenced not
-- uploaded; a seated driver plays the stock sit 2506281703) chosen by speed, the walk/run rate
-- scaled to the speed so feet do not slide.
-- Four-legged bodies (squirrel, Spicy Rodent, fox, deer): the procedural gait (Animation/Gait) on
-- their RigSpec Motor6Ds (leg swing, knee bend, body bob, head nod, tail sway) set every Stepped.
-- Speed is the body's observed speed (smoothed; horizontal for humans, 3D for animals so climbing
-- animates), which works the same for anchored AI bodies moved by the server and for client-owned
-- bodies. For AI bodies the server's `ClipT0` attribute aligns the clip phase across clients when a
-- track starts.
-- Visual root (owner playtest 2026-11-09: bodies bounced up and down and stood half in the grass):
-- the visible body hangs off the root through the Motor6D named Root, so its C0 carries a client-only
-- vertical offset and the root itself (the gameplay position the server sees) never moves.
--   * Height smoothing (settle): a critically damped follower with limited velocity feed-forward
--     tracks the rendered root height (read in RenderStepped, after physics), so slopes and climbs
--     are followed without lag while ground-sampling steps, kerbs, jitter and replication steps are
--     eased out; it rises faster than it settles, so feet do not hang in a kerb for long.
--   * Ground contact: AI bodies (anchored roots, placed on World/Height's analytic ground by the
--     server) standing near the terrain are lifted or lowered onto what is really under their feet: a
--     short downward ray from just above the feet, a few times a second, against collidable town parts
--     and the voxel terrain (whose surface can sit up to about a stud above the analytic height).
--     Possessed bodies stand on their own motor's raycast ground or Humanoid, so they get smoothing
--     only (people none); squirrels up trees and on roofs keep their route heights.
--   * Kinematic bodies (Controllers/KinematicPose: the held squirrel) draw their own eased pose, so
--     nothing is layered on it: no height smoothing, no probe; the stride phase advances at the motor's
--     cadence and the swing follows the motor's speed, never the observed displacement. Whatever
--     offset the body carried as an AI decays at v5.4's 23/s, the same rate the controller's drawn point
--     eases onto its own ground, so a possession hands over without a step.
-- Patients (owner 2026-11-10, the bite-to-hospital sequence): the server writes a Med attribute on a
-- bitten body (Server/Infection/InfectionService). An AI body with Med "down" (collapsed at a scene,
-- or being carried to the ambulance) or "treated" (in a hospital bed) plays the stock sit clip and is
-- lowered through the same visual-root offset: sitting on the ground, or on the cot (Infection/
-- HospitalLayout.BED.top above the floor). A body a player holds is never posed. Render/MedicalView
-- draws the rest of the attribute (red eyes, hiding).
-- No side effects on require.
-- Interface: start(opts) -> Driver; Driver.stop(); DEFAULT_CLIPS; newSettle(); settle(state, y, dt) (pure);
--   clipSpeed(speed, nominal?) -> playback speed (pure); medPose(med, footDrop) -> { clip, drop } (pure)

local Gait = require("./Gait")
local KinematicPose = require("../Controllers/KinematicPose")
local Import = require("../Import")
local PossessionState =
	Import.shared("Actors/PossessionState") :: typeof(require("../../shared/Actors/PossessionState"))
local Height = Import.shared("World/Height") :: typeof(require("../../shared/World/Height"))
local HospitalLayout =
	Import.shared("Infection/HospitalLayout") :: typeof(require("../../shared/Infection/HospitalLayout"))

export type ClipSet = {
	idle: string?,
	walk: string?,
	run: string?,
	jump: string?,
	fall: string?,
	sit: string?,
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
	humanoid: Humanoid?, -- seated in a car (SeatPart set): the sit clip, not a run at car speed
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
	-- visual root: the Root Motor6D's C0, or the root-side Attachment of a Root AnimationConstraint
	rootJoint: Motor6D?,
	rootAttach: Attachment?,
	baseC0: CFrame,
	footDrop: number, -- studs from the root down to the soles at rest
	settle: Settle,
	fix: number, -- studs, the ground-contact correction now (eased)
	fixTarget: number,
	nextProbe: number,
	anchored: boolean,
	applied: number,
	kin: boolean, -- a kinematic controller drew this body last frame
	med: any, -- the body's Med attribute (a patient's pose)
	medConn: RBXScriptConnection?,
	drop: number, -- studs the pose lowers the body by, now (eased)
}

-- The visual-height follower's state (AnimationDriver.newSettle): the visual height and velocity, and
-- rings of the last root heights (with their times) and short-baseline velocities.
export type Settle = {
	y: number,
	v: number,
	live: boolean,
	clock: number,
	hy: { number },
	ht: { number },
	head: number,
	vel: { number },
	vi: number,
}

local AnimationDriver = {}

-- Visual root tuning (studs, seconds, rad/s).
AnimationDriver.RISE = 30 -- omega while the visual body is below the root (catch up fast)
AnimationDriver.FALL = 12 -- omega while it is above (settle smoothly)
AnimationDriver.MAX_LAG = 0.6 -- the visual body never strays further than this from the root
AnimationDriver.SNAP = 6 -- a jump bigger than this in one frame is a teleport: no easing
AnimationDriver.PROBE_EVERY = 0.25
AnimationDriver.PROBE_RANGE = 320 -- only bodies this close to the camera are probed
AnimationDriver.PROBE_UP = 1.6 -- the ray starts this far above the soles (starts inside a hedge: ignored)
AnimationDriver.FIX_MIN = -0.75
AnimationDriver.FIX_MAX = 1.4
AnimationDriver.CLEARANCE = 0.04 -- soles rest this much above the surface found
AnimationDriver.NEAR_GROUND = 2 -- only soles this close to the terrain are probed (not squirrels up trees)
AnimationDriver.KIN_RATE = 23 -- 1/s: a kinematic body sheds its carried offset at v5.4's visual easing rate
AnimationDriver.SIT_SEAT = 1.35 -- studs from an R15 root down to what the sit clip sits on
AnimationDriver.POSE_RATE = 6 -- 1/s: how fast a patient sinks into (or rises out of) the pose

local SHORT, BASE, MEDIAN_N = 3, 12, 7 -- frames: short and long velocity baselines; median window
local scratch: { number } = table.create(MEDIAN_N, 0)

function AnimationDriver.newSettle(): Settle
	return {
		y = 0,
		v = 0,
		live = false,
		clock = 0,
		hy = table.create(BASE + 1, 0),
		ht = table.create(BASE + 1, 0),
		head = 1,
		vel = table.create(MEDIAN_N, 0),
		vi = 1,
	}
end

-- settle(state, y, dt): one frame of the visual-height follower towards the rendered root height y;
-- returns the offset (visual - root) to apply. Pure (Lune-tested; tuned against simulated slopes,
-- kerbs, drops, ground-sampling jitter, the squirrel motor's downhill hop seen through BodyDriver's
-- one-frame extrapolation, and network-update staircases). A critically damped spring (faster while
-- the body is below the root) with velocity feed-forward, so slopes and trunk climbs are followed
-- without lag; the feed-forward is minmod(median of 3-frame velocities, 12-frame velocity): a
-- one-frame step or a back-and-forth jitter feeds nothing forward, so it is eased, not overshot.
function AnimationDriver.settle(st: Settle, y: number, dt: number): number
	local ring = BASE + 1
	if not st.live or dt <= 0 or math.abs(y - st.y) > AnimationDriver.SNAP then
		st.y, st.v, st.live = y, 0, true
		for i = 1, ring do
			st.hy[i], st.ht[i] = y, st.clock
		end
		for i = 1, MEDIAN_N do
			st.vel[i] = 0
		end
		return 0
	end
	st.clock += dt
	st.head = st.head % ring + 1
	st.hy[st.head], st.ht[st.head] = y, st.clock
	local s = (st.head - 1 - SHORT) % ring + 1
	local b = (st.head - 1 - BASE) % ring + 1
	local ds, db = st.clock - st.ht[s], st.clock - st.ht[b]
	st.vi = st.vi % MEDIAN_N + 1
	st.vel[st.vi] = if ds > 0 then (y - st.hy[s]) / ds else 0
	table.move(st.vel, 1, MEDIAN_N, 1, scratch)
	table.sort(scratch)
	local short = scratch[(MEDIAN_N + 1) // 2]
	local long = if db > 0 then (y - st.hy[b]) / db else 0
	local rv = if short * long > 0 then (if math.abs(short) < math.abs(long) then short else long) else 0
	-- the target moves at rv through the frame; semi-implicit substeps (stable for any frame time)
	local w = if st.y < y then AnimationDriver.RISE else AnimationDriver.FALL
	local span = math.min(dt, 0.1)
	local n = math.clamp(math.ceil(span * 480), 1, 48)
	local h = span / n
	local yv, v = st.y, st.v
	for j = 1, n do
		local target = y - rv * (span - j * h)
		v += (w * w * (target - yv) + 2 * w * (rv - v)) * h
		yv += v * h
	end
	local off = math.clamp(yv - y, -AnimationDriver.MAX_LAG, AnimationDriver.MAX_LAG)
	st.y, st.v = y + off, v
	return off
end

-- Roblox's stock R15 animations (public, owned by Roblox: the default Animate script's IDs). The
-- animals use the procedural Gait (the S7 test clip 92005834447457 stays for the clip pipeline only).
-- start() falls back to this table, so it must exist: without it every body's add() and the whole
-- per-frame step throw (tests/unit/anim_gait.spec.luau pins it).
AnimationDriver.DEFAULT_CLIPS = {
	human = {
		idle = "rbxassetid://507766388",
		walk = "rbxassetid://507777826",
		run = "rbxassetid://507767714",
		jump = "rbxassetid://507765000",
		fall = "rbxassetid://507767968",
		sit = "rbxassetid://2506281703", -- the stock R15 Animate sit
		-- The stock R15 walk and run are authored for Roblox's default 16 st/s: Roblox's own Animate
		-- script plays them at speed / 16. This said 6 for the walk, so a townsperson strolling at 2 to
		-- 4 st/s cycled their legs nearly three times too fast (owner 2026-11-10: "people wandering
		-- around who seem to sort of always be running in place").
		nominalWalk = 16,
		nominalRun = 16,
	},
} :: { [string]: ClipSet }

-- Playback speed of a walk or run clip authored for `nominal` st/s on a body moving at `speed`: the
-- feet keep pace with the ground. The floor is low (a slow stroll is a slow cycle, never legs that
-- run under a body that barely moves); other clips play at their own speed.
-- medPose(med, footDrop): how an AI body with this Med attribute is posed: the clip to play (nil =
-- the usual choice by speed) and how far the visible body is lowered (studs). `footDrop` is the
-- body's root height above its soles. A collapsed person sits on the ground; a patient in a bed sits
-- up on the cot; anything else (symptomatic, in transit, healthy) keeps its usual animation.
function AnimationDriver.medPose(med: any, footDrop: number): { clip: string?, drop: number }
	if med == "down" then
		return { clip = "sit", drop = math.max(0, footDrop - AnimationDriver.SIT_SEAT) }
	elseif med == "treated" then
		return { clip = "sit", drop = math.max(0, footDrop - AnimationDriver.SIT_SEAT - HospitalLayout.BED.top) }
	end
	return { clip = nil, drop = 0 }
end

function AnimationDriver.clipSpeed(speed: number, nominal: number?): number
	if nominal == nil or nominal <= 0 then
		return 1
	end
	return math.clamp(speed / nominal, 0.1, 2.5)
end

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

-- The joint named Root that hangs the visible body off the root part (animals: RootPart -> Pelvis;
-- R15: HumanoidRootPart -> LowerTorso): a Motor6D, or on stock R15s built with the avatar joint
-- upgrade an AnimationConstraint, whose root-side Attachment is moved instead of C0.
local function rootJointOf(model: Model, root: BasePart): (Motor6D?, Attachment?)
	for _, d in model:GetDescendants() do
		if d.Name ~= "Root" then
			continue
		end
		if d:IsA("Motor6D") and d.Part0 == root then
			return d, nil
		elseif d:IsA("AnimationConstraint") then
			for _, a in { d.Attachment0, d.Attachment1 } do
				if a and a.Parent == root then
					return nil, a
				end
			end
		end
	end
	return nil, nil
end

-- Studs from the root's centre down to the soles: the puppet's HipHeight attribute (the root's
-- height above the ground), else the model's bounding box at rest.
local function footDropOf(model: Model, root: BasePart): number
	local hip = model:GetAttribute("HipHeight")
	if type(hip) == "number" and model:FindFirstChildOfClass("Humanoid") == nil then
		return hip
	end
	local cf, size = model:GetBoundingBox()
	return root.Position.Y - (cf.Position.Y - size.Y / 2)
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
		local rootJoint, rootAttach = rootJointOf(model, root)
		local medConn = model:GetAttributeChangedSignal("Med"):Connect(function()
			local e = entries[model]
			if e then
				e.med = model:GetAttribute("Med")
			end
		end)
		entries[model] = {
			body = model,
			root = root,
			animator = animator,
			humanoid = model:FindFirstChildOfClass("Humanoid"),
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
			rootJoint = rootJoint,
			rootAttach = rootAttach,
			baseC0 = if rootJoint then rootJoint.C0 elseif rootAttach then rootAttach.CFrame else CFrame.identity,
			footDrop = footDropOf(model, root),
			settle = AnimationDriver.newSettle(),
			fix = 0,
			fixTarget = 0,
			nextProbe = os.clock() + ((#model.Name * 0.173) % 1) * AnimationDriver.PROBE_EVERY,
			anchored = root.Anchored,
			applied = 0,
			kin = false,
			med = model:GetAttribute("Med"),
			medConn = medConn,
			drop = 0,
		}
		count += 1
	end

	local function remove(child: Instance)
		local e = entries[child :: any]
		if e then
			if e.medConn then
				e.medConn:Disconnect()
			end
			for _, t in e.tracks do
				t:Stop(0)
			end
			for _, j in e.joints do
				j.motor.Transform = CFrame.identity
			end
			if e.applied ~= 0 then
				local rj, ra = e.rootJoint, e.rootAttach
				if rj then
					rj.C0 = e.baseC0
				elseif ra then
					ra.CFrame = e.baseC0
				end
			end
			entries[child :: any] = nil
			count -= 1
		end
	end

	local function choose(e: Entry): string
		local set: ClipSet = clips[e.species] or {}
		local hum = e.humanoid
		if set.sit and hum and hum.SeatPart ~= nil then
			return "sit"
		end
		-- a patient (AI bodies only: a held body keeps its own animation)
		if e.med ~= nil and e.root.Anchored then
			local clip = AnimationDriver.medPose(e.med, e.footDrop).clip
			if clip and (set :: any)[clip] then
				return clip
			end
		end
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

	-- ground probe: collidable parts and terrain, never bodies, the camera's own parts or water
	local probe = RaycastParams.new()
	probe.FilterType = Enum.RaycastFilterType.Exclude
	probe.RespectCanCollide = true
	probe.IgnoreWater = true
	probe.FilterDescendantsInstances = { opts.container, workspace.CurrentCamera }
	local DOWN = Vector3.new(0, -(AnimationDriver.PROBE_UP - AnimationDriver.FIX_MIN + 0.5), 0)

	-- the visible body's vertical offset from its root (world up, whatever the root's attitude)
	local function applyOffset(e: Entry, off: number)
		if math.abs(off - e.applied) > 0.002 or (off == 0 and e.applied ~= 0) then
			e.applied = off
			local shifted = CFrame.new(e.root.CFrame:VectorToObjectSpace(Vector3.new(0, off, 0))) * e.baseC0
			local rj, ra = e.rootJoint, e.rootAttach
			if rj then
				rj.C0 = shifted
			elseif ra then
				ra.CFrame = shifted
			end
		end
	end

	-- the visual root of one body this frame (after physics: root.Position is what renders)
	local function visualRoot(e: Entry, pos: Vector3, dt: number, now: number, camPos: Vector3)
		local rj, ra = e.rootJoint, e.rootAttach
		if (rj == nil or rj.Parent == nil) and (ra == nil or ra.Parent == nil) then
			return
		end
		local anchored = e.root.Anchored
		if KinematicPose.get(e.body) then
			if not e.kin then
				e.kin = true
				e.fix, e.fixTarget = e.applied, 0
				e.settle.live = false
			end
			e.anchored = anchored
			e.fix *= math.exp(-dt * AnimationDriver.KIN_RATE)
			if math.abs(e.fix) < 0.001 then
				e.fix = 0
			end
			applyOffset(e, e.fix)
			return
		elseif e.kin then
			-- the controller let go: the smoothing starts again from the height drawn now
			e.kin = false
			e.settle.live = false
			e.fix, e.fixTarget = 0, 0
		end
		if anchored ~= e.anchored then
			-- possession or release: carry the ground correction into the smoothed height so the
			-- body does not jump when the root takes over (or gives up) the real ground
			e.anchored = anchored
			e.settle.y += e.fix
			e.fix, e.fixTarget = 0, 0
		end
		local off = 0
		if e.humanoid and not anchored then
			e.settle.live = false -- a possessed person stands on its Humanoid
		else
			off = AnimationDriver.settle(e.settle, pos.Y, dt)
		end
		if anchored then
			if now >= e.nextProbe then
				e.nextProbe = now + AnimationDriver.PROBE_EVERY
				local target = 0
				local sole = pos.Y - e.footDrop
				if
					(pos - camPos).Magnitude < AnimationDriver.PROBE_RANGE
					and math.abs(sole - Height.at(pos.X, pos.Z)) < AnimationDriver.NEAR_GROUND
				then
					local hit =
						workspace:Raycast(Vector3.new(pos.X, sole + AnimationDriver.PROBE_UP, pos.Z), DOWN, probe)
					if hit and hit.Normal.Y > 0.6 then
						local lift = hit.Position.Y + AnimationDriver.CLEARANCE - sole
						if lift >= AnimationDriver.FIX_MIN and lift <= AnimationDriver.FIX_MAX then
							target = lift
						end
					end
				end
				e.fixTarget = target
			end
		else
			e.fixTarget = 0
		end
		e.fix += (e.fixTarget - e.fix) * (1 - math.exp(-dt * 8))
		off += e.fix
		-- a patient's pose lowers the visible body (sitting on the ground, or up on the cot)
		local wantDrop = if anchored and e.med ~= nil then AnimationDriver.medPose(e.med, e.footDrop).drop else 0
		if wantDrop ~= e.drop then
			e.drop += (wantDrop - e.drop) * (1 - math.exp(-dt * AnimationDriver.POSE_RATE))
			if math.abs(wantDrop - e.drop) < 0.005 then
				e.drop = wantDrop
			end
		end
		off -= e.drop
		applyOffset(e, off)
	end

	local function step(dt: number)
		if dt <= 0 then
			return
		end
		local alpha = math.min(1, dt / 0.15)
		local now = os.clock()
		local camera = workspace.CurrentCamera
		local camPos = if camera then camera.CFrame.Position else Vector3.zero
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
			local kin = KinematicPose.get(e.body)
			if kin then
				-- the motor's own speed: what the body is seen to do never feeds the animation
				e.speed, e.vy = kin.moveSpeed, 0
			else
				e.speed += (inst - e.speed) * alpha
				e.vy += (vy - e.vy) * alpha
			end
			visualRoot(e, pos, dt, now, camPos)
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
				cur:AdjustSpeed(AnimationDriver.clipSpeed(e.speed, nominal))
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
			local kin = KinematicPose.get(e.body)
			if kin then
				e.phase = (e.phase + kin.cadence * dt) % (2 * math.pi)
			else
				e.phase = Gait.advance(e.phase, e.speed, dt, p)
			end
			local pose = Gait.pose(e.phase, e.speed, clock, p, e.tailN, if kin then kin.climb else 0)
			for _, j in e.joints do
				local cf = CFrame.identity
				local leg = if j.leg then pose.legs[j.leg] else nil
				if j.kind == "Upper" and leg then
					cf = CFrame.Angles(leg.upper, 0, 0)
				elseif j.kind == "Lower" and leg then
					cf = CFrame.Angles(leg.lower, 0, 0)
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
