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
-- Interface: start(body, payload, metrics, ctx) -> stop(); ctx = { world, input }
-- No side effects on require.

local Import = require("../Import")
local SquirrelMotor =
	Import.shared("Movement/SquirrelMotor") :: typeof(require("../../shared/Movement/SquirrelMotor"))
local BodyDriver = require("./BodyDriver")
local Quadruped = require("./Quadruped")

local Squirrel = {}

function Squirrel.start(body: Model, payload: { [string]: any }, metrics: { [string]: any }, ctx: { [string]: any }): () -> ()
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
	local hip = math.clamp(pos.Y - ground, 0.1, 3)
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
		local _, events = SquirrelMotor.step(state, mi, dt, motorWorld :: any)
		for _, e in events do
			metrics.lastEvent = e.kind
		end
		local v = SquirrelMotor.visualPose(state, motorWorld :: any)
		local p = Vector3.new(v.x, v.y + hip, v.z)
		local vel = if dt > 0 then (p - last) / dt else Vector3.zero
		last = p
		return p, state.yaw, vel, nil
	end)
end

return Squirrel
