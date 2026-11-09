--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Controllers.Squirrel
-- Controller for a held squirrel (and the rodent, a squirrel actor with Variant "spicy"):
-- Shared/Movement/SquirrelMotor (the v5.4 updatePlayer port: ground, rails, leap, drop, grab, fork
-- and junction choice, pounce; plus the trampoline bounce) driven by InputMap through BodyDriver
-- (BUILD_PLAN §1.4 Controllers, D2, §4.4 #5; the S2 ground-only controller is replaced behind the
-- same start/stop). The rail world (Movement/RailWorld) builds in the background on the client;
-- until it is ready the body runs on the ground with QuadrupedMotor's squirrel parameters.
-- Possession carry-over (§1.5 step 5): the motor starts at the rendered pose with the snapshot's
-- heading and momentum; an AI squirrel suspended on a rail (snapshot.brain.routeId, s, dir) resumes
-- on that rail at the same arc position; the AI's direction is held for up to holdSeconds or until
-- the first input.
-- Feedback (owner rule: never ignore input silently): E with nothing to grab, Q on the ground and the
-- motor's hints ("climb closer", "too far to jump across") become short toasts through ctx.toast.
-- Interface: start(body, payload, metrics, ctx) -> stop(); ctx = { world, input, toast? };
--   feedback(frame, events, onRoute) -> string? (pure); hipOf(body, measured) -> studs
-- No side effects on require.

local Import = require("../Import")
local SquirrelMotor = Import.shared("Movement/SquirrelMotor") :: typeof(require("../../shared/Movement/SquirrelMotor"))
local BodyDriver = require("./BodyDriver")
local Quadruped = require("./Quadruped")

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

-- The root's height above the soles: the body's HipHeight attribute, else the measured gap (clamped).
function Squirrel.hipOf(body: Model, measured: number): number
	local hip = body:GetAttribute("HipHeight")
	if type(hip) == "number" and hip > 0 then
		return hip
	end
	return math.clamp(measured, 0.1, 3)
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
	local rail = world.rail()
	if rail == nil then
		-- rail world still building: ground only until the next possession
		metrics.squirrelGroundOnly = true
		return Quadruped.start(body, payload, metrics, { world = world, input = ctx.input, species = "squirrel" })
	end
	local input = ctx.input
	local pos = root.Position
	local ground = world.groundAt(pos.X, pos.Z, pos.Y)
	-- the root's height above the soles is the body's own HipHeight (PuppetSpec), not the gap to the
	-- ground at the handoff: the AI stood on World/Height's analytic ground, which can sit up to a stud
	-- under the voxel surface the motor's raycast finds (the old measure buried the squirrel), and a
	-- squirrel taken on a trunk is nowhere near the ground
	local hip = Squirrel.hipOf(body, pos.Y - ground)
	local snap = payload.snapshot
	local state = SquirrelMotor.new(pos.X, ground, pos.Z)
	state.yaw = (snap.yaw or 0) + math.pi
	state.vx, state.vz = snap.vx or 0, snap.vz or 0
	local b = snap.brain
	if b and b.routeId and b.routeId ~= 0 then
		local route = rail.registry:get(b.routeId)
		if route and route.length > 0 then
			state.routeId = b.routeId
			state.railT = math.clamp((b.s or 0) / route.length, 0, 1)
			state.railDir = if (b.dir or 1) >= 0 then 1 else -1
			state.grounded = false
		end
	end
	local motorWorld = {
		registry = rail.registry,
		index = rail.index,
		graph = rail.graph,
		trampolines = rail.trampolines,
		groundAt = world.groundAt,
		blocked = world.blocked,
		clamp = world.clamp,
	}
	local holdUntil = os.clock() + (payload.holdSeconds or 0.75)
	local holding = state.routeId ~= nil or math.abs(state.vx) + math.abs(state.vz) > 0.1
	local last = Vector3.new(pos.X, pos.Y, pos.Z)
	local lastSaid, lastText = -math.huge, ""
	return BodyDriver.drive(root, function(dt: number)
		local f = input:sample(BodyDriver.cameraYawHtml())
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
		local say = if ctx.toast then Squirrel.feedback(f :: any, events :: any, wasOnRoute) else nil
		local t = os.clock()
		if say and t - lastSaid > 1.5 and (say ~= lastText or t - lastSaid > 8) then
			lastSaid, lastText = t, say
			ctx.toast(say, 2.5)
		end
		local v = SquirrelMotor.visualPose(state, motorWorld :: any)
		local p = Vector3.new(v.x, v.y + hip, v.z)
		local vel = if dt > 0 then (p - last) / dt else Vector3.zero
		last = p
		return p, state.yaw, vel, nil
	end)
end

return Squirrel
