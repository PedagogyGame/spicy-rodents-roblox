--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Controllers.Quadruped
-- Controller for a held fox or deer (and the squirrel's ground fallback while the rail world is
-- still building): Shared/Movement/QuadrupedMotor driven by InputMap through BodyDriver
-- (BUILD_PLAN §1.4 Controllers, §1.5 step 5, §4.4 #5). The motor resumes at the rendered position
-- with the snapshot's heading and momentum and holds the AI's direction for up to holdSeconds or
-- until the first input, so the stride carries on.
-- Interface: start(body, payload, metrics, ctx) -> stop(); ctx = { world, input, species? }
-- No side effects on require.

local Import = require("../Import")
local QuadrupedMotor =
	Import.shared("Movement/QuadrupedMotor") :: typeof(require("../../shared/Movement/QuadrupedMotor"))
local BodyDriver = require("./BodyDriver")

local Quadruped = {}

function Quadruped.start(
	body: Model,
	payload: { [string]: any },
	metrics: { [string]: any },
	ctx: { [string]: any }
): () -> ()
	local root = body.PrimaryPart
	if root == nil then
		return function() end
	end
	local species = ctx.species or payload.species
	local params = QuadrupedMotor.paramsFor(species)
	local world = ctx.world
	local input = ctx.input
	local pos = root.Position
	local ground = world.groundAt(pos.X, pos.Z, pos.Y)
	params.hip = math.clamp(pos.Y - ground, 0.2, 6)
	local snap = payload.snapshot
	local yaw = (snap.yaw or 0) + math.pi -- Roblox yaw to HTML yaw
	local state = QuadrupedMotor.new(pos.X, pos.Y, pos.Z, yaw)
	state.vx, state.vz = snap.vx or 0, snap.vz or 0
	local holdUntil = os.clock() + (payload.holdSeconds or 0.75)
	local holding = math.abs(state.vx) + math.abs(state.vz) > 0.1
	local motorWorld = { groundAt = world.groundAt, blocked = world.blocked, clamp = world.clamp }
	local inputAt: number? = nil
	return BodyDriver.drive(root, function(dt: number)
		local f = input:sample(BodyDriver.cameraYawHtml())
		local mi = { fw = f.fw, side = f.side, cameraYaw = f.cameraYaw, sprint = f.sprint, jump = f.jump }
		if f.fw ~= 0 or f.side ~= 0 or f.jump then
			holding = false
			if inputAt == nil then
				inputAt = os.clock()
				metrics.inputToMoveMs = metrics.inputToMoveMs or 0
			end
		elseif holding and os.clock() < holdUntil then
			mi.fw, mi.cameraYaw = 1, state.yaw + math.pi
		end
		QuadrupedMotor.step(state, mi, dt, motorWorld, params)
		return Vector3.new(state.x, state.y, state.z), state.yaw, Vector3.new(state.vx, state.vy, state.vz), nil
	end)
end

return Quadruped
