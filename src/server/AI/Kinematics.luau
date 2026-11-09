--!strict
-- ServerScriptService.Server.AI.Kinematics
-- The AI motor for anchored, kinematic bodies (BUILD_PLAN §1.3 server frame step 3; §1.5 body
-- modes). W1 folded the S5 spike's integrator into Shared/Movement/HumanAIMotor; this module keeps
-- the spike's name and interface so the S5/S19 scenarios (Scenario, tests/engine/AIScale,
-- BodyBudget) stay runnable unchanged.
-- Interface: step(actor, dt, ctx), railPose(route, s) -> x, y, z. Pure; studs.

local Import = require("../Import")
local HumanAIMotor = Import.shared("Movement/HumanAIMotor") :: typeof(require("../../shared/Movement/HumanAIMotor"))
local Common = require("../Actors/Brains/Common")

local Kinematics = {}

Kinematics.railPose = HumanAIMotor.railPose

function Kinematics.step(actor: Common.Actor, dt: number, ctx: Common.Ctx)
	HumanAIMotor.step(actor :: any, dt, ctx :: any)
end

return Kinematics
