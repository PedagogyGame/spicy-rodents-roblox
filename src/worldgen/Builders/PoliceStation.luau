--!strict
-- ServerScriptService.Server.WorldGen.Builders.PoliceStation
-- PoliceStation builder family (BUILD_PLAN §4.4 #7): the enterable greybox from data/buildings (see
-- Builders/Programme for rooms, doors, stations, shelves and pads).
-- Interface (BUILD_PLAN §1.4): plan(ctx) adds the shell to ctx.list. Pure.

local Programme = require("./Programme")
local Spec = require("../Spec")

local PoliceStation = {}

function PoliceStation.plan(ctx: Spec.LotCtx)
	Programme.build(ctx)
end

return PoliceStation
