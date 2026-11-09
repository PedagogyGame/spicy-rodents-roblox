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
local BAND = { 176, 168, 148 }

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
		-- plinth and string courses at +3.5 / +9 / +14.5 u (v5.4 makeBridgeTower), visual only
		ctx.list:add(ctx.frame, `Plinth{i}`, 0, 1, s * pz, pw + 1.2, 2, pd + 1.2, {
			color = BAND,
			material = "Limestone",
			canCollide = false,
			castShadow = false,
			role = "Trim",
		})
		for k, y in { 3.5, 9, 14.5 } do
			ctx.list:add(ctx.frame, `Course{i}_{k}`, 0, y * spu, s * pz, pw + 0.7, 0.8, pd + 0.7, {
				color = BAND,
				material = "Limestone",
				canCollide = false,
				castShadow = false,
				role = "Trim",
			})
		end
		-- slit windows on the outer face
		for k, x in { -pw / 2 + 2.6, pw / 2 - 2.6 } do
			ctx.list:add(ctx.frame, `Slit{i}_{k}`, x, 11.8 * spu, s * (pz + pd / 2 + 0.05), 1.4, 4.2, 0.3, {
				color = { 70, 86, 92 },
				material = "Glass",
				canCollide = false,
				castShadow = false,
				role = "Window",
			})
		end
		-- a red banner on the outer face
		ctx.list:add(ctx.frame, `Banner{i}`, 0, (h - gallery) * 0.62, s * (pz + pd / 2 + 0.15), 4.5, 11, 0.2, {
			color = { 175, 89, 73 },
			material = "Fabric",
			canCollide = false,
			castShadow = false,
			role = "Trim",
		})
	end
	ctx.list:add(ctx.frame, "GalleryCap", 0, h + 0.3, 0, ctx.W + 1, 0.6, ctx.D + 1, {
		color = BAND,
		material = "Limestone",
		canCollide = false,
		castShadow = false,
		role = "Trim",
	})
end

return BridgeTower
