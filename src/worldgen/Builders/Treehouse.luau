--!strict
-- ServerScriptService.Server.WorldGen.Builders.Treehouse
-- Treehouse (v5.4 buildTreehouse 9502; lot notes): floor at base + 13.2 in its oak, three walls with
-- the open front, a roof, and the side deck (4.2 x 3.2 at local x +5.9). The ladder is a route prop
-- (pipe). Interface (BUILD_PLAN §1.4): plan(ctx). Pure.

local Spec = require("../Spec")

local Treehouse = {}

local WOOD = { 140, 104, 70 }

function Treehouse.plan(ctx: Spec.LotCtx)
	local spu = Spec.SPU
	local p = ctx.params
	local W, D = ctx.W, ctx.D
	local floor = (p.floorU or 13.2) * spu
	local wallH = ctx.kit.heightU * spu
	local t = 0.4
	ctx.list:add(ctx.frame, "Floor", 0, floor - 0.2, 0, W, 0.4, D, { color = WOOD, role = "Floor", material = "WoodPlanks" })
	ctx.list:add(ctx.frame, "WallBack", 0, floor + wallH / 2, D / 2 - t / 2, W, wallH, t, { color = WOOD, role = "Wall" })
	ctx.list:add(ctx.frame, "WallLeft", -W / 2 + t / 2, floor + wallH / 2, 0, t, wallH, D - 2 * t, { color = WOOD, role = "Wall" })
	ctx.list:add(ctx.frame, "WallRight", W / 2 - t / 2, floor + wallH / 2, 0, t, wallH, D - 2 * t, { color = WOOD, role = "Wall" })
	ctx.list:add(ctx.frame, "Roof", 0, floor + wallH + 0.2, 0, W + 1, 0.4, D + 1, { color = { 99, 82, 76 }, role = "Roof" })
	local deck = p.deck or { 5.9, 0, 4.2, 3.2 }
	-- v5.4 local x is world x for this unrotated lot; the model's local X is flipped (yaw pi)
	local sx = if math.cos(ctx.frame.yaw) < 0 then -1 else 1
	ctx.list:add(ctx.frame, "Deck", sx * deck[1] * spu, floor - 0.2, -deck[2] * spu, deck[3] * spu, 0.4, deck[4] * spu, {
		color = WOOD,
		role = "Floor",
		material = "WoodPlanks",
	})
end

return Treehouse
