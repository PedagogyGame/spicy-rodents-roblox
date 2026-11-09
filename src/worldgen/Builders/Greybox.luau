--!strict
-- ServerScriptService.Server.WorldGen.Builders.Greybox
-- W0/W1 greybox family for every lot type: one block (or plate, slab, prop, marker) per lot with
-- the right footprint, facing, height, collision and LevelOfDetail (spike S6). The per-category
-- families (House, Storefront, ...) replace the block inside the same Model in W1.
-- Interface (BUILD_PLAN §1.4): build(plan, factory) -> Model

local Factory = require("../Factory")
local Plan = require("../Plan")

local Greybox = {}

function Greybox.build(plan: Plan.BuildPlan, factory: Factory.Factory): any
	local model = factory.model(plan.id, plan)
	local primary = nil
	for _, spec in plan.parts do
		local p = factory.part(spec)
		p.Parent = model
		primary = primary or p
	end
	model.PrimaryPart = primary
	return model
end

return Greybox
