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
local Palette = require("../Palette")
local Spec = require("../Spec")

local Building = {}

local SIGN = { 48, 76, 68 }
Building.SIGN_TEAL = { 51, 95, 103 } -- v5.4 hospital sign #335f67
local PLINTH = { 170, 166, 151 }
local CHIMNEY = { 132, 92, 78 }
local PLATE = 0.4

-- The lot's v5.4 look (Plan sets ctx.palette; direct callers fall back to the lot's own data).
function Building.look(ctx: Spec.LotCtx): Palette.Look
	local pal = ctx.palette
	if pal == nil then
		pal = Palette.forLot(ctx.lot, ctx.kit)
		ctx.palette = pal
	end
	return pal :: Palette.Look
end

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
		local nx, ny = side * math.sin(phi), math.cos(phi) -- outward (upper) normal in (across, up)
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
			color = Building.look(ctx).roof,
			material = Building.look(ctx).roofMaterial,
			role = "Roof",
		})
	end
	Building.gableEnds(ctx, eave, peak, alongLocalX)
end

-- Gable-end infill: two WedgeParts per end in the wall colour, just inside the end walls, so the
-- triangle under the roof plates is closed (v5.4 localRoof gable infill). Visual only.
function Building.gableEnds(ctx: Spec.LotCtx, eave: number, peak: number, alongLocalX: boolean)
	local pal = Building.look(ctx)
	local rise = peak - eave
	if rise <= 0.05 then
		return
	end
	local t = 0.4
	local W, D = ctx.W, ctx.D
	local half = (if alongLocalX then D else W) / 2
	local endAt = (if alongLocalX then W else D) / 2 - t / 2
	local n = 0
	for _, e in { -1, 1 } do
		for _, side in { -1, 1 } do
			n += 1
			-- the wedge rises toward local +Z; side -1 covers the low..centre half toward +, side +1 the other
			local mx, mz, yaw
			local u = side * half / 2
			if alongLocalX then
				mx, mz = e * endAt, u
				yaw = if side < 0 then 0 else math.pi
			else
				mx, mz = u, e * endAt
				yaw = if side < 0 then math.pi / 2 else -math.pi / 2
			end
			ctx.list:add(ctx.frame, `Gable{n}`, mx, eave + rise / 2, mz, t, rise, half, {
				yaw = yaw,
				shape = "Wedge",
				color = pal.wall,
				material = pal.material,
				canCollide = false,
				castShadow = true,
				role = "Wall",
			})
		end
	end
end

-- Window panes on the four faces between `base` and `top` (studs above the seat): a trim panel and a
-- glass pane standing slightly proud of the wall, a grid of floors and bays sized from the face.
-- `avoid` lists door openings per face ("F", "B", "L", "R": { c = centre along the face, w = width }),
-- kept clear on the ground floor. Visual only (no collision).
function Building.windows(
	ctx: Spec.LotCtx,
	base: number,
	top: number,
	avoid: { [string]: { { c: number, w: number } } }?
)
	local pal = Building.look(ctx)
	local W, D = ctx.W, ctx.D
	local height = top - base
	if height < 5 then
		return
	end
	local floors = math.clamp(math.floor(height / 9 + 0.3), 1, 3)
	local floorH = height / floors
	local winH = math.min(4.4, floorH * 0.5)
	local winW = 3.2
	local faces = {
		{ id = "F", len = W, fixed = -D / 2, out = -1, alongX = true },
		{ id = "B", len = W, fixed = D / 2, out = 1, alongX = true },
		{ id = "L", len = D, fixed = -W / 2, out = -1, alongX = false },
		{ id = "R", len = D, fixed = W / 2, out = 1, alongX = false },
	}
	for _, f in faces do
		-- terraced quay rows hide their side walls: front and back only there
		local side = not f.alongX
		if f.len >= 9 and not (side and (pal.timber or f.len < 14)) then
			local bays = math.clamp(math.floor(f.len / 12), 1, 5)
			local gaps: { { c: number, w: number } } = {}
			if avoid and avoid[f.id] then
				gaps = avoid[f.id]
			end
			for fl = 1, floors do
				local y = base + (fl - 0.5) * floorH + 0.3
				for i = 1, bays do
					local c = -f.len / 2 + f.len * (i - 0.5) / bays
					local clear = true
					if fl == 1 then
						for _, g in gaps do
							if math.abs(c - g.c) < g.w / 2 + winW / 2 + 0.6 then
								clear = false
							end
						end
					end
					if clear then
						for k, layer in
							{ { d = 0.08, w = winW + 0.7, h = winH + 0.7 }, { d = 0.16, w = winW, h = winH } }
						do
							local depth = layer.d * 2
							local off = f.fixed + f.out * (layer.d - depth / 2)
							local mx, mz, sx, sz
							if f.alongX then
								mx, mz, sx, sz = c, off, layer.w, depth
							else
								mx, mz, sx, sz = off, c, depth, layer.w
							end
							ctx.list:add(
								ctx.frame,
								`{if k == 1 then "Frame" else "Win"}{f.id}{fl}_{i}`,
								mx,
								y,
								mz,
								sx,
								layer.h,
								sz,
								{
									color = if k == 1 then pal.trim else pal.window,
									material = if k == 1 then "SmoothPlastic" else "Glass",
									canCollide = false,
									castShadow = false,
									role = "Window",
								}
							)
						end
					end
				end
			end
		end
	end
end

-- Continuous ribbon windows (hospital, review 2026-11-09 "a plain box"): one glass band per floor on
-- every face, broken around the ground-floor door openings in `avoid`, with an accent floor line under
-- each band. Visual only.
function Building.bands(ctx: Spec.LotCtx, base: number, top: number, avoid: { [string]: { { c: number, w: number } } }?)
	local pal = Building.look(ctx)
	local W, D = ctx.W, ctx.D
	local height = top - base
	if height < 5 then
		return
	end
	local floors = math.clamp(math.floor(height / 10 + 0.3), 1, 4)
	local floorH = height / floors
	local bandH = math.min(4.2, floorH * 0.42)
	local faces = {
		{ id = "F", len = W, fixed = -D / 2, out = -1, alongX = true },
		{ id = "B", len = W, fixed = D / 2, out = 1, alongX = true },
		{ id = "L", len = D, fixed = -W / 2, out = -1, alongX = false },
		{ id = "R", len = D, fixed = W / 2, out = 1, alongX = false },
	}
	local function piece(
		name: string,
		f: any,
		a: number,
		b: number,
		y: number,
		h: number,
		depth: number,
		color: { number },
		material: string
	)
		if b - a < 1 then
			return
		end
		local off = f.fixed + f.out * depth / 2
		local mx, mz, sx, sz
		if f.alongX then
			mx, mz, sx, sz = (a + b) / 2, off, b - a, depth
		else
			mx, mz, sx, sz = off, (a + b) / 2, depth, b - a
		end
		ctx.list:add(ctx.frame, name, mx, y, mz, sx, h, sz, {
			color = color,
			material = material,
			canCollide = false,
			castShadow = false,
			role = "Window",
		})
	end
	for _, f in faces do
		local margin = math.min(6, f.len * 0.08)
		for fl = 1, floors do
			local y = base + (fl - 0.5) * floorH + 0.4
			local spans = { { -f.len / 2 + margin, f.len / 2 - margin } }
			if fl == 1 and avoid and avoid[f.id] then
				for _, g in avoid[f.id] do
					local nextSpans = {}
					for _, sp in spans do
						local g0, g1 = g.c - g.w / 2 - 2.5, g.c + g.w / 2 + 2.5
						if g1 <= sp[1] or g0 >= sp[2] then
							table.insert(nextSpans, sp)
						else
							table.insert(nextSpans, { sp[1], g0 })
							table.insert(nextSpans, { g1, sp[2] })
						end
					end
					spans = nextSpans
				end
			end
			for k, sp in spans do
				piece(`Win{f.id}{fl}_{k}`, f, sp[1], sp[2], y, bandH, 0.36, pal.window, "Glass")
				piece(
					`Sill{f.id}{fl}_{k}`,
					f,
					sp[1] - 0.3,
					sp[2] + 0.3,
					y - bandH / 2 - 0.3,
					0.6,
					0.5,
					pal.trim,
					"SmoothPlastic"
				)
			end
			if fl > 1 then
				piece(
					`FloorLine{f.id}{fl}`,
					f,
					-f.len / 2,
					f.len / 2,
					base + (fl - 1) * floorH,
					0.9,
					0.24,
					pal.accent,
					"SmoothPlastic"
				)
			end
		end
	end
end

-- Facade dressing: a stone plinth, a cornice strip under a flat roof, Tudor timber bands (quay) and
-- a chimney (houses with one in v5.4). Visual only (no collision), so physics and the checks are
-- unchanged.
function Building.dress(ctx: Spec.LotCtx, eave: number, peak: number, flat: boolean, plinth: boolean?)
	local pal = Building.look(ctx)
	local W, D = ctx.W, ctx.D
	local function add(
		name: string,
		mx: number,
		my: number,
		mz: number,
		sx: number,
		sy: number,
		sz: number,
		color: { number },
		material: string?
	)
		ctx.list:add(ctx.frame, name, mx, my, mz, sx, sy, sz, {
			color = color,
			material = material or "SmoothPlastic",
			canCollide = false,
			castShadow = false,
			role = "Trim",
		})
	end
	if plinth ~= false then
		add("Plinth", 0, 0.6, 0, W + 0.4, 1.2, D + 0.4, PLINTH, "Concrete")
	end
	if flat then
		local c = if ctx.lot.type == "mall" or ctx.lot.type == "hospital" then pal.accent else pal.trim
		add("CorniceF", 0, eave - 0.4, -D / 2 - 0.15, W + 0.6, 0.8, 0.3, c)
		add("CorniceB", 0, eave - 0.4, D / 2 + 0.15, W + 0.6, 0.8, 0.3, c)
		add("CorniceL", -W / 2 - 0.15, eave - 0.4, 0, 0.3, 0.8, D, c)
		add("CorniceR", W / 2 + 0.15, eave - 0.4, 0, 0.3, 0.8, D, c)
	end
	if pal.timber then
		for i, y in { 2.25, eave * 0.51, eave - 0.5 } do
			add(`TimberF{i}`, 0, y, -D / 2 - 0.1, W + 0.1, 0.4, 0.2, Palette.OAK, "Wood")
			add(`TimberB{i}`, 0, y, D / 2 + 0.1, W + 0.1, 0.4, 0.2, Palette.OAK, "Wood")
		end
		for i, x in { -W / 2, -W / 6, W / 6, W / 2 } do
			add(`PostF{i}`, x, eave / 2, -D / 2 - 0.1, 0.45, eave, 0.2, Palette.OAK, "Wood")
		end
	end
	if pal.chimney and peak > eave + 0.5 then
		local h = peak - eave * 0.8 + 2.5
		add("Chimney", -0.28 * W, eave * 0.8 + h / 2, 0.2 * D, 2.2, h, 2.2, CHIMNEY, "Brick")
	end
end

-- A non-solid sign board on the front face with a SurfaceGui.
function Building.sign(ctx: Spec.LotCtx, text: string, y: number, width: number?)
	local w = math.min(width or ctx.W * 0.6, 24)
	local pal = Building.look(ctx)
	ctx.list:add(ctx.frame, "SignBoard", 0, y, -ctx.D / 2 - 0.15, w, 2.2, 0.3, {
		color = if pal.timber then pal.accent else SIGN,
		canCollide = false,
		role = "Sign",
		attrs = { SignText = text },
	})
	ctx.list:extra({ kind = "SurfaceGui", part = "SignBoard", name = "Sign", text = text, face = "Front" })
end

-- Front door leaf set into the front face (the body behind it is solid until W3 interiors).
function Building.door(ctx: Spec.LotCtx, width: number, height: number)
	ctx.list:add(ctx.frame, "Door", 0, height / 2, -ctx.D / 2 + 0.15, width, height, 0.3, {
		color = Building.look(ctx).door,
		material = "Wood",
		role = "Door",
		attrs = { DoorId = ctx.lot.id .. ":front", ServerOwned = true, Lockable = true, Open = false, Locked = false },
	})
	ctx.list:extra({
		kind = "Prompt",
		part = "Door",
		name = "Prompt",
		action = "Open",
		offset = { 0, 0, -0.3 },
		attrs = { Placeholder = true },
	})
	ctx.attributes.DoorOutside = true
end

function Building.plan(ctx: Spec.LotCtx)
	local eave, peak, kind, alongX = Building.heights(ctx)
	local pal = Building.look(ctx)
	ctx.list:add(ctx.frame, "Body", 0, eave / 2, 0, ctx.W, eave, ctx.D, {
		color = pal.wall,
		material = pal.material,
		role = "Body",
	})
	local gable = kind == "gable" and peak > eave + 0.05
	if gable then
		Building.roof(ctx, eave, peak, alongX)
	end
	local doorW = math.min(3 * Spec.SPU, ctx.W * 0.5)
	if ctx.kit.door then
		Building.door(ctx, doorW, math.min(3.5 * Spec.SPU, eave * 0.8))
	end
	Building.windows(ctx, 0.6, eave - 0.6, { F = if ctx.kit.door then { { c = 0, w = doorW } } else {} })
	Building.dress(ctx, eave, peak, not gable)
	local text = ctx.params.sign or ctx.kit.signText
	if text then
		Building.sign(ctx, text, math.min(eave - 1.4, 4.4 * Spec.SPU))
	end
	ctx.attributes.EaveY = eave
	ctx.attributes.PeakY = peak
	ctx.attributes.Roof = kind
end

return Building
