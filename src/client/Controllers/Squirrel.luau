--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Controllers.Squirrel
-- Controller for a held squirrel (and the rodent, a squirrel actor with Variant "spicy"). The body is
-- kinematic (owner rule 2026-11-09): every render frame Shared/Movement/SquirrelMotor (the v5.4
-- updatePlayer port: ground glue, rails, leap, drop, grab, fork and junction choice, pounce, trampoline)
-- advances the authoritative point from InputMap, Shared/Movement/SquirrelVisual eases the drawn pose
-- after it (v5.4's render layer: 23/s position easing, ground contact under the drawn point, bark-facing
-- nose-up pose on a trunk, lean into turns), and BodyDriver.driveRender writes that pose as the root's
-- CFrame for the frame being drawn. No Humanoid, no physics settling, no root motion: the animation layer
-- reads the motor's speed and stride rate from KinematicPose and only poses the mesh.
-- The rail world (Movement/RailWorld) builds in the background on the client; until it is ready the same
-- motor runs against an empty rail world (ground, leap, walls), and the routes appear under it the first
-- frame they exist, with no second possession needed.
-- Possession carry-over (BUILD_PLAN 1.5 step 5): the motor starts at the rendered pose with the snapshot's
-- heading and momentum; an AI squirrel suspended on a rail (snapshot.brain.routeId, s, dir) resumes on
-- that rail at the same arc position; the AI's direction is held for up to holdSeconds or until the
-- first input.
-- Recovery: the motor is the only authority on where the body is, so the two things that move it from
-- outside are taken in here. A fall into the river puts it on the nearer quay (v5.4 recoverRiverFall,
-- called after the motor step as in L6767). A teleport by the server (the Reset button, the server's own
-- rescue) shows up as a root that is not where the last frame left it; the motor restarts from there
-- instead of writing the old position back over it.
-- Feedback (owner rule: never ignore input silently): E with nothing to grab, Q on the ground and the
-- motor's hints ("climb closer", "too far to jump across") become short toasts through ctx.toast.
-- Sprint is a burst (SquirrelMotor stamina): ctx.meter draws the meter, and running out says so.
-- Night vision (World/NightVision) is the Spicy Rodent's alone: N toggles it; an ordinary squirrel
-- pressing N is told so.
-- Interface: start(body, payload, metrics, ctx) -> stop(); ctx = { world, input, toast?, meter?, variant? };
--   nightVisionSays(spicy, on) -> string (pure);
--   feedback(frame, events, onRoute) -> string? (pure); hipOf(body, measured) -> studs;
--   movedFromOutside(gap, speed, frameDt) -> boolean (pure); modeOf(onRoute, climb, grounded, trunk?) ->
--   string (pure); launch(events, vy) -> action?, airSeconds? (pure)
-- No side effects on require.

local Import = require("../Import")
local SquirrelMotor = Import.shared("Movement/SquirrelMotor") :: typeof(require("../../shared/Movement/SquirrelMotor"))
local SquirrelVisual =
	Import.shared("Movement/SquirrelVisual") :: typeof(require("../../shared/Movement/SquirrelVisual"))
local RailWorld = Import.shared("Movement/RailWorld") :: typeof(require("../../shared/Movement/RailWorld"))
local Recovery = Import.shared("Movement/Recovery") :: typeof(require("../../shared/Movement/Recovery"))
local Units = Import.shared("Config/Units") :: typeof(require("../../shared/Config/Units"))
local BodyDriver = require("./BodyDriver")
local KinematicPose = require("./KinematicPose")
local NightVision = require("../World/NightVision")

local Squirrel = {}

local HINTS: { [string]: string } = {
	climbCloser = "Climb closer to the fork, then press E",
	noTransfer = "Nothing to grab within reach: get right under a branch or wire",
	nothingNear = "Nothing to grab here: run into a tree, pole or downspout to climb",
	junctionAhead = "Junction ahead: A or D picks the way",
}

-- What to tell the player about this frame's verbs (pure; nil = nothing to say). `frame` is the
-- InputMap sample, `events` the motor's events, `onRoute` whether the body is on a rail now.
function Squirrel.feedback(frame: { [string]: any }, events: { { [string]: any } }, onRoute: boolean): string?
	for _, e in events do
		if e.kind == "hint" and e.reason and HINTS[e.reason] then
			return HINTS[e.reason]
		end
		if e.kind == "winded" then
			return "Out of fumes: sprint comes back in a few seconds"
		end
	end
	local attached = false
	for _, e in events do
		local k = e.kind
		if k == "attach" or k == "transfer" or k == "forkTaken" or k == "branchHop" or k == "junctionChosen" then
			attached = true
		end
	end
	if frame.grab and not attached and not onRoute then
		return "Nothing to grab here: run into a tree, pole or downspout to climb"
	end
	if frame.drop and not onRoute then
		return "Q lets go of a branch: you are already on the ground"
	end
	return nil
end

-- What pressing N says: `spicy` whether this body is the Spicy Rodent, `on` the state after the press.
function Squirrel.nightVisionSays(spicy: boolean, on: boolean): string
	if not spicy then
		return "Only the Spicy Rodent has night vision"
	end
	return if on then "Night vision on (N turns it off)" else "Night vision off"
end

-- The root's height above the soles: the body's HipHeight attribute, else the measured gap (clamped).
function Squirrel.hipOf(body: Model, measured: number): number
	local hip = body:GetAttribute("HipHeight")
	if type(hip) == "number" and hip > 0 then
		return hip
	end
	return math.clamp(measured, 0.1, 3)
end

-- Whether a root found `gap` studs from where the last frame wrote it was moved by someone else. Physics
-- carries the body at the written velocity between frames (twice that is allowed for an uneven frame);
-- beyond that and a little slack it is a teleport.
Squirrel.OUTSIDE_SLACK = 2
function Squirrel.movedFromOutside(gap: number, speed: number, frameDt: number): boolean
	return gap > Squirrel.OUTSIDE_SLACK + speed * math.max(frameDt, 0) * 2
end

-- What the held body is doing, for a rig that plays clips (KinematicPose.mode): on a rail it is on a
-- "trunk" from the moment it takes one (`trunk`: SquirrelVisual's; the nose comes up over the next half
-- second, and it should not trot a wire meanwhile) and while more than half of the climb pose still shows
-- after it leaves one (SquirrelVisual's `climb`), else running a "rail"; off one it is on the "ground" or
-- in the "air". Pure: the offline motion preview (tools/review/motion) asks the same question.
function Squirrel.modeOf(onRoute: boolean, climb: number, grounded: boolean, trunk: boolean?): string
	if onRoute then
		return if trunk or climb > 0.5 then "trunk" else "rail"
	end
	return if grounded then "ground" else "air"
end

-- How this frame's motor events sent the body into the air, for a rig that plays clips
-- (KinematicPose.action, airSeconds): "leap" or "pounce", and the seconds until gravity brings it back
-- down to the height it left (`vy`: its vertical speed after the launch, studs/s). nil: nothing did.
function Squirrel.launch(events: { { [string]: any } }, vy: number): (string?, number?)
	for _, e in events do
		if e.kind == "leap" or e.kind == "pounce" then
			return e.kind, 2 * math.max(vy, 0) / SquirrelMotor.params.gravity
		end
	end
	return nil, nil
end

function Squirrel.start(
	body: Model,
	payload: { [string]: any },
	metrics: { [string]: any },
	ctx: { [string]: any }
): () -> ()
	local root = body.PrimaryPart
	if root == nil then
		return function() end
	end
	local world = ctx.world
	local input = ctx.input
	local rw = world.rail()
	local railLive = rw ~= nil
	local first = rw or RailWorld.empty()
	local motorWorld = {
		registry = first.registry,
		index = first.index,
		graph = first.graph,
		trampolines = first.trampolines,
		groundAt = world.groundAt,
		blocked = world.blocked,
		blockedCore = world.blockedCore,
		blockedHalf = world.blockedHalf,
		clamp = world.clamp,
	}
	local pos = root.Position
	local ground = world.groundAt(pos.X, pos.Z, pos.Y)
	-- the root's height above the soles is the body's own HipHeight (PuppetSpec), not the gap to the
	-- ground at the handoff: a squirrel taken on a trunk or in the air is nowhere near the ground
	local hip = Squirrel.hipOf(body, pos.Y - ground)
	local feet = pos.Y - hip
	local snap = payload.snapshot or {}
	local state = SquirrelMotor.new(pos.X, ground, pos.Z)
	state.yaw = (snap.yaw or 0) + math.pi
	state.vx, state.vz = snap.vx or 0, snap.vz or 0
	local b = snap.brain
	if railLive and b and b.routeId and b.routeId ~= 0 then
		local route = motorWorld.registry:get(b.routeId)
		if route and route.length > 0 then
			state.routeId = b.routeId
			state.railT = math.clamp((b.s or 0) / route.length, 0, 1)
			state.railDir = if (b.dir or 1) >= 0 then 1 else -1
			state.grounded = false
		end
	end
	if state.routeId == nil and feet - ground > SquirrelMotor.params.glueMin then
		-- taken in the air (or off a rail that is not built yet): fall from where the body is drawn
		state.y = feet
		state.grounded = false
	end
	-- the drawn pose starts exactly where the body is drawn now and eases onto the motor from there
	local visual = SquirrelVisual.new()
	visual.x, visual.y, visual.z = pos.X, feet, pos.Z
	visual.live = true
	visual.yaw = state.yaw
	local kin: KinematicPose.Pose = { moveSpeed = 0, cadence = 0, climb = 0 }
	KinematicPose.set(body, kin)

	local holdUntil = os.clock() + (payload.holdSeconds or 0.75)
	local holding = state.routeId ~= nil or math.abs(state.vx) + math.abs(state.vz) > 0.1
	local last, lastSpeed = pos, 0
	local lastSaid, lastText = -math.huge, ""
	local shownStamina, shownWinded = -1, false
	local spicy = (ctx.variant or payload.variant or body:GetAttribute("Variant")) == "spicy"
	local vision: NightVision.Handle? = nil
	local stopDrive = BodyDriver.driveRender(root, function(frameDt: number)
		local dt = math.min(frameDt, 0.08)
		if not railLive and state.routeId == nil then
			local built = world.rail()
			if built then
				motorWorld.registry, motorWorld.index = built.registry, built.index
				motorWorld.graph, motorWorld.trampolines = built.graph, built.trampolines
				-- Motion caches the trunk feet of the registry it first saw on the world table
				local cache: any = motorWorld
				cache._trunkFeet = nil
				railLive = true
			end
		end
		local at = root.Position
		if Squirrel.movedFromOutside((at - last).Magnitude, lastSpeed, frameDt) then
			-- moved by the server: restart the motor where the body now is, and cut the drawn point to it
			local g = world.groundAt(at.X, at.Z, at.Y)
			local soles = at.Y - hip
			local air = soles - g > SquirrelMotor.params.glueMin
			SquirrelMotor.place(state, at.X, if air then soles else g, at.Z, not air)
			visual.live = false
			holding = false
		end
		local f = input:sample(BodyDriver.cameraYawHtml())
		if f.nightVision then
			local nowOn = false
			if spicy then
				local h = vision or NightVision.start()
				vision = h
				nowOn = h.toggle()
			end
			if ctx.toast then
				ctx.toast(Squirrel.nightVisionSays(spicy, nowOn), 2)
			end
		end
		local mi = {
			fw = f.fw,
			side = f.side,
			sprint = f.sprint,
			focus = f.focus,
			cameraYaw = f.cameraYaw,
			cameraPitch = 0.12,
			leap = f.leap,
			drop = f.drop,
			grab = f.grab,
			choose = if state.routeId then f.choose else 0,
			pounce = f.pounce,
		}
		local any = f.fw ~= 0 or f.side ~= 0 or f.leap or f.drop or f.grab or f.pounce
		if any then
			holding = false
		elseif holding and os.clock() < holdUntil then
			-- keep the AI's stride: forward along the current heading (camera behind the body)
			mi.fw = 1
			mi.cameraYaw = state.yaw + math.pi
		end
		local wasOnRoute = state.routeId ~= nil
		local _, events = SquirrelMotor.step(state, mi, dt, motorWorld :: any)
		for _, e in events do
			metrics.lastEvent = e.kind
		end
		if state.routeId == nil then
			local rx, ry, rz = Recovery.riverFall(state.x, state.y, state.z)
			if rx and ry and rz then
				SquirrelMotor.place(state, rx, ry, rz, true)
				metrics.lastEvent = "riverRecover"
			end
		end
		local say = if ctx.toast then Squirrel.feedback(f :: any, events :: any, wasOnRoute) else nil
		local t = os.clock()
		if say and t - lastSaid > 1.5 and (say ~= lastText or t - lastSaid > 8) then
			lastSaid, lastText = t, say
			ctx.toast(say, 2.5)
		end
		if ctx.meter and (math.abs(state.stamina - shownStamina) > 0.004 or state.winded ~= shownWinded) then
			shownStamina, shownWinded = state.stamina, state.winded
			ctx.meter(state.stamina, state.winded)
		end
		-- the bowling alley's ball-return tunnel (and its vent): the camera rides low behind (CameraPolicy zone)
		local zone = nil
		if state.routeId then
			local r = motorWorld.registry:get(state.routeId)
			if r and r.origin == "attraction" then
				zone = "tunnel"
			end
		end
		if body:GetAttribute("CameraZone") ~= zone then
			body:SetAttribute("CameraZone", zone)
		end
		-- what is drawn: the eased pose, about the feet point (yaw, then nose-up pitch and lean, then the hip)
		local snapped = SquirrelVisual.frame(visual, state, motorWorld :: any, dt, world.groundAt)
		kin.moveSpeed, kin.cadence, kin.climb = visual.moveSpeed, visual.cadence, visual.climb
		kin.mode = Squirrel.modeOf(state.routeId ~= nil, visual.climb, state.grounded, visual.trunk)
		kin.stalk = state.focus
		kin.winded = state.winded
		local action, airSeconds = Squirrel.launch(events :: any, state.vy)
		if action or kin.mode ~= "air" then
			kin.action, kin.airSeconds = action, airSeconds
		end
		local cf = Units.yawCFrame(visual.yaw or state.yaw, Vector3.new(visual.x, visual.y, visual.z))
			* CFrame.Angles(visual.pitch, 0, -visual.lean)
			* CFrame.new(0, hip, 0)
		local p = cf.Position
		local vel = if snapped or dt <= 0 then Vector3.zero else (p - last) / dt
		last, lastSpeed = p, vel.Magnitude
		return cf, vel
	end)
	return function()
		stopDrive()
		KinematicPose.clear(body)
		if ctx.meter then
			ctx.meter(nil)
		end
		if vision then
			vision.stop() -- the next body, and the menu, see the town as everyone else does
		end
	end
end

return Squirrel
