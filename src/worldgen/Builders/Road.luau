--!strict
-- ServerScriptService.Server.WorldGen.Builders.Road
-- Road strips: a chain of flat anchored parts following the terrain (Plan.road), one Model per road.
-- Markings, curbs and crossings are W1.
-- Interface (BUILD_PLAN §1.4): build(plan, factory) -> Model

local Factory = require("../Factory")
local Plan = require("../Plan")

local Road = {}

function Road.build(plan: Plan.BuildPlan, factory: Factory.Factory): any
	local model = factory.model(plan.id, plan)
	for _, spec in plan.parts do
		factory.part(spec).Parent = model
	end
	return model
end

return Road
