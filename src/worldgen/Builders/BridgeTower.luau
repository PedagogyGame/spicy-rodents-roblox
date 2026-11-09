--!strict
-- ServerScriptService.Server.WorldGen.Builders.BridgeTower
-- River bridge tower (v5.4 makeBridgeTower 13698; lot notes): two piers either side of the deck on
-- the bridge deck height (`seat = absolute:15.8`), and the gallery slab spanning them at the tower
-- top (the "River bridge tower gallery" roof route rides on it). The deck between the piers stays
-- open for traffic (the S6 single block closed it).
-- Interface (BUILD_PLAN §1.4): plan(ctx). Pure.

local Spec = require("../Spec")

local BridgeTower = {}

local STONE = { 209, 199, 174 }

function BridgeTower.plan(ctx: Spec.LotCtx)
	local spu = Spec.SPU
	local p = ctx.params
	local h = ctx.kit.heightU * spu
	local pz, pw, pd = (p.pierZU or 10.7) * spu, (p.pierWU or 8) * spu, (p.pierDU or 7.2) * spu
	local gallery = 1.2
	ctx.list:add(ctx.frame, "Gallery", 0, h - gallery / 2, 0, ctx.W, gallery, ctx.D, { color = STONE, role = "Roof" })
	for i, s in { -1, 1 } do
		-- piers stand along the lot's depth axis (world z for these unrotated lots)
		ctx.list:add(
			ctx.frame,
			`Pier{i}`,
			0,
			(h - gallery) / 2,
			s * pz,
			pw,
			h - gallery,
			pd,
			{ color = STONE, role = "Body" }
		)
	end
end

return BridgeTower
