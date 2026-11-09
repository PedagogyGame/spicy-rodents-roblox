--!strict
-- ServerScriptService.Server.WorldGen.Builders.House
-- House builder family (greybox in W1; BUILD_PLAN §3.4, §4.4 #7): a house with an interior template
-- (the 4 FRB homes, `home.interior`) is an enterable shell (Builders/Interior); every other house is
-- the Building massing with its harvested eave/peak, roof kind and ridge (outer homes keep the flat
-- v5.4 landing under harvest_lock, data/harvest_patches.json).
-- Interface (BUILD_PLAN §1.4): plan(ctx). Pure.

local Building = require("./Building")
local Interior = require("./Interior")
local Spec = require("../Spec")

local House = {}

function House.plan(ctx: Spec.LotCtx)
	if ctx.interior then
		Interior.build(ctx)
	else
		Building.plan(ctx)
	end
end

return House
