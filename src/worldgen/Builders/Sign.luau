--!strict
-- ServerScriptService.Server.WorldGen.Builders.Sign
-- Free-standing sign family (BUILD_PLAN §4.4 #7; v5.4 riverSign/flatSign: a post and a board): a
-- solid post, a non-solid board and a SurfaceGui on its front with the lot's `params.sign` text.
-- Interface (BUILD_PLAN §1.4): plan(ctx). Pure.

local Spec = require("../Spec")

local Sign = {}

function Sign.plan(ctx: Spec.LotCtx)
	local spu = Spec.SPU
	local h = ctx.kit.heightU * spu
	ctx.list:add(ctx.frame, "Post", 0, h / 2, 0, 0.6, h, 0.6, { color = { 110, 90, 70 }, role = "Post" })
	local text = ctx.params.sign or ctx.kit.signText or "SIGN"
	local w = math.clamp(math.max(ctx.W, ctx.D), 4, 8 * spu)
	ctx.list:add(ctx.frame, "SignBoard", 0, h - 1.2, -0.45, w, 1.3 * spu, 0.3, {
		color = { 48, 76, 68 },
		canCollide = false,
		role = "Sign",
		attrs = { SignText = text },
	})
	ctx.list:extra({ kind = "SurfaceGui", part = "SignBoard", name = "Sign", text = text, face = "Front" })
end

return Sign
