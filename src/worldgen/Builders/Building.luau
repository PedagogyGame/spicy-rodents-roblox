--!strict
-- ServerScriptService.Server.WorldGen.Builders.Building
-- Greybox building family (BUILD_PLAN §4.4 #7): a solid body to the eave, a gable (two pitched roof
-- plates along the ridge) or a flat roof, a front door leaf with a ProximityPrompt placeholder and a
-- SurfaceGui sign on the front. Heights come from the lot's params (seeded from the v5.4 harvest:
-- eaveU, peakU, roof, ridge) or the lot type (heightU). Also exports the roof and sign helpers the
-- House and Interior families reuse.
-- Interface (BUILD_PLAN §1.4): plan(ctx); roof(ctx, eave, peak, kind, ridgeLocalX); sign(ctx, text, y)
-- Pure (adds PartSpecs/ExtraSpecs to ctx.list).

local Geometry = require("../Geometry")
local Spec = require("../Spec")

local Building = {}

local ROOF = { 99, 82, 76 }
local DOOR = { 120, 86, 60 }
local SIGN = { 48, 76, 68 }
local PLATE = 0.4

-- Eave and peak in studs above the seat, the roof kind and whether the ridge runs along local X.
function Building.heights(ctx: Spec.LotCtx): (number, number, string, boolean)
	local p, kit = ctx.params, ctx.kit
	local spu = Spec.SPU
	local kind = p.roof or kit.roof or "flat"
	local eave, peak
	if p.eaveU then
		eave = p.eaveU * spu
		peak = (p.peakU or p.eaveU) * spu
	elseif kind == "gable" then
		eave = kit.heightU * 0.65 * spu
		peak = kit.heightU * spu
	else
		eave = kit.heightU * spu
		peak = eave
	end
	if kind == "flat" then
		-- a flat roof lands at the ridge height (outer homes: routes_movement verifier 4, harvest_lock)
		eave = math.max(eave, peak)
		peak = eave
	end
	-- ridge axis is given in world axes; the model's local X is world X for even quarter turns
	local ridge = p.ridge or "x"
	local localXIsWorldX = math.abs(math.cos(ctx.frame.yaw)) > 0.5
	local alongLocalX = (ridge == "x") == localXIsWorldX
	return eave, peak, kind, alongLocalX
end

-- Two pitched plates from the eave line to the ridge (top faces meet at the peak).
function Building.roof(ctx: Spec.LotCtx, eave: number, peak: number, alongLocalX: boolean)
	local W, D = ctx.W, ctx.D
	local span = if alongLocalX then D else W -- horizontal run from eave to eave
	local length = if alongLocalX then W else D -- along the ridge
	local rise = peak - eave
	local half = span / 2
	local slope = math.sqrt(half * half + rise * rise)
	local phi = math.atan2(rise, half)
	for side = -1, 1, 2 do
		-- plate centre on the slope line (offset half a plate thickness up the normal)
		local u = side * half / 2 -- across-ridge coordinate of the plate centre
		local nx, ny = -side * math.sin(phi), math.cos(phi) -- outward normal in (across, up)
		local cu, cy = u + nx * PLATE / 2, eave + rise / 2 + ny * PLATE / 2
		local mx, mz, yaw = 0, cu, 0
		if not alongLocalX then
			mx, mz, yaw = cu, 0, math.pi / 2
		end
		-- choose the pitch sign so that the plate's inner (+Z local) end is the high end: evaluate it
		local pitch = phi
		local tip = Geometry.rotate({ 0, 0, slope / 2 }, yaw, pitch, 0)
		local tipAcross = if alongLocalX then tip[3] else tip[1]
		local tipHigher = tip[2] > 0
		if (tipAcross * u < 0) ~= tipHigher then
			pitch = -phi
		end
		ctx.list:add(ctx.frame, if side < 0 then "RoofA" else "RoofB", mx, cy, mz, length, PLATE, slope, {
			yaw = yaw,
			pitch = pitch,
			color = ROOF,
			role = "Roof",
		})
	end
end

-- A non-solid sign board on the front face with a SurfaceGui.
function Building.sign(ctx: Spec.LotCtx, text: string, y: number, width: number?)
	local w = math.min(width or ctx.W * 0.6, 24)
	ctx.list:add(ctx.frame, "SignBoard", 0, y, -ctx.D / 2 - 0.15, w, 2.2, 0.3, {
		color = SIGN,
		canCollide = false,
		role = "Sign",
		attrs = { SignText = text },
	})
	ctx.list:extra({ kind = "SurfaceGui", part = "SignBoard", name = "Sign", text = text, face = "Front" })
end

-- Front door leaf set into the front face (the body behind it is solid until W3 interiors).
function Building.door(ctx: Spec.LotCtx, width: number, height: number)
	ctx.list:add(ctx.frame, "Door", 0, height / 2, -ctx.D / 2 + 0.15, width, height, 0.3, {
		color = DOOR,
		role = "Door",
		attrs = { DoorId = ctx.lot.id .. ":front", ServerOwned = true, Lockable = true, Open = false, Locked = false },
	})
	ctx.list:extra({ kind = "Prompt", part = "Door", name = "Prompt", action = "Open", offset = { 0, 0, -0.3 }, attrs = { Placeholder = true } })
	ctx.attributes.DoorOutside = true
end

function Building.plan(ctx: Spec.LotCtx)
	local eave, peak, kind, alongX = Building.heights(ctx)
	ctx.list:add(ctx.frame, "Body", 0, eave / 2, 0, ctx.W, eave, ctx.D, {
		color = ctx.kit.color,
		material = ctx.kit.material,
		role = "Body",
	})
	if kind == "gable" and peak > eave + 0.05 then
		Building.roof(ctx, eave, peak, alongX)
	end
	if ctx.kit.door then
		Building.door(ctx, math.min(3 * Spec.SPU, ctx.W * 0.5), math.min(3.5 * Spec.SPU, eave * 0.8))
	end
	local text = ctx.params.sign or ctx.kit.signText
	if text then
		Building.sign(ctx, text, math.min(eave - 1.4, 4.4 * Spec.SPU))
	end
	ctx.attributes.EaveY = eave
	ctx.attributes.PeakY = peak
	ctx.attributes.Roof = kind
end

return Building
