--!strict
-- ServerScriptService.Server.WorldGen.Builders.Greybox
-- Instantiates any BuildPlan (lots, route props, lamps, Skyline): one Model with its parts (the
-- first is the PrimaryPart) and extras (SurfaceGui signs, prompt placeholders, Attachments, Beams).
-- The builder families (Building, House, Interior, Hospital, PoliceStation, Sign, RouteProps) produce
-- the plans; this is the single place they become Instances (Lune bake and engine bake alike).
-- Interface (BUILD_PLAN §1.4): build(plan, factory) -> Model

local Factory = require("../Factory")
local Spec = require("../Spec")

local Greybox = {}

function Greybox.build(plan: Spec.BuildPlan, factory: Factory.Factory): any
	local model = factory.model(plan.id, plan)
	local primary = nil
	local byName: { [string]: any } = {}
	for _, spec in plan.parts do
		local p = factory.part(spec)
		p.Parent = model
		byName[spec.name] = p
		primary = primary or p
	end
	-- Attachments first so Beams can find them
	for pass = 1, 2 do
		local extras: { Spec.ExtraSpec } = plan.extras or {}
		for _, e in extras do
			if (e.kind == "Beam") == (pass == 2) then
				factory.extra(e, byName)
			end
		end
	end
	model.PrimaryPart = primary
	return model
end

return Greybox
