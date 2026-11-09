--!strict
-- ServerScriptService.Server.WorldGen.Builders.Hospital
-- Hospital builder family (BUILD_PLAN §4.4 #7): the enterable greybox from data/buildings (see
-- Builders/Programme for rooms, doors, stations, shelves and pads), with ribbon windows, plus a facade
-- that reads as a hospital from the street (review 2026-11-09 "a plain 235 x 240 box"): a roof parapet
-- with a teal cap, the v5.4 "HOSPITAL . EMERGENCY" sign above the roofline over the entrance with a
-- red cross, and an entrance surround (pilasters, lintel, glazed transom) around every front door.
-- Greybox level; all visual (no collision), so rooms, doors, nav and the checks are unchanged.
-- Interface (BUILD_PLAN §1.4): plan(ctx) adds the shell to ctx.list. Pure.

local Building = require("./Building")
local Programme = require("./Programme")
local Spec = require("../Spec")

local Hospital = {}

local RED = { 196, 52, 52 }
local WHITE = { 240, 240, 236 }

function Hospital.facade(ctx: Spec.LotCtx)
	local pal = Building.look(ctx)
	local b = ctx.building :: any
	local spu = Spec.SPU
	local W, D = ctx.W, ctx.D
	local wallH = (b.wallHeightU or ctx.params.eaveU or ctx.kit.heightU) * spu
	local roofTop = wallH + 0.6
	local function add(
		name: string,
		mx: number,
		my: number,
		mz: number,
		sx: number,
		sy: number,
		sz: number,
		color: { number },
		o: Spec.Opts?
	)
		local opts: Spec.Opts = o or {}
		opts.color = color
		opts.material = opts.material or "SmoothPlastic"
		if opts.canCollide == nil then
			opts.canCollide = false
		end
		opts.role = opts.role or "Trim"
		ctx.list:add(ctx.frame, name, mx, my, mz, sx, sy, sz, opts)
	end
	-- roof parapet (2.6 studs over the roof) with a teal cap
	local ph, pt = 2.6, 0.8
	add("ParapetF", 0, roofTop + ph / 2, -D / 2 + pt / 2, W, ph, pt, pal.wall)
	add("ParapetB", 0, roofTop + ph / 2, D / 2 - pt / 2, W, ph, pt, pal.wall)
	add("ParapetL", -W / 2 + pt / 2, roofTop + ph / 2, 0, pt, ph, D - 2 * pt, pal.wall)
	add("ParapetR", W / 2 - pt / 2, roofTop + ph / 2, 0, pt, ph, D - 2 * pt, pal.wall)
	add("CapF", 0, roofTop + ph + 0.2, -D / 2 + pt / 2, W + 0.4, 0.4, pt + 0.4, pal.accent)
	add("CapB", 0, roofTop + ph + 0.2, D / 2 - pt / 2, W + 0.4, 0.4, pt + 0.4, pal.accent)
	add("CapL", -W / 2 + pt / 2, roofTop + ph + 0.2, 0, pt + 0.4, 0.4, D - 2 * pt, pal.accent)
	add("CapR", W / 2 - pt / 2, roofTop + ph + 0.2, 0, pt + 0.4, 0.4, D - 2 * pt, pal.accent)
	-- rooftop plant room (a lighter box set back from the edge)
	add("PlantRoom", W * 0.18, roofTop + 4, D * 0.15, W * 0.3, 8, D * 0.25, { 210, 210, 204 }, { castShadow = true })
	-- front doors: entrance surrounds
	local frontDoors = {}
	for _, d in b.doors do
		local z = -d.at[2] * spu
		if math.abs(z + D / 2) <= 1.5 then
			table.insert(frontDoors, { x = d.at[1] * spu, w = d.width * spu })
		end
	end
	local doorH = b.doorHeightU * spu
	local floorTop = 0.42 * spu
	local mainX = 0
	for i, d in frontDoors do
		local half = d.w / 2 + 2.2
		local top = floorTop + doorH + 4.5
		for k, s in { -1, 1 } do
			add(`EntrancePier{i}_{k}`, d.x + s * (half - 0.8), top / 2, -D / 2 - 0.7, 1.6, top, 1.4, pal.accent)
		end
		add(`EntranceLintel{i}`, d.x, top - 0.7, -D / 2 - 0.8, 2 * half, 1.4, 1.6, pal.accent)
		add(
			`EntranceTransom{i}`,
			d.x,
			floorTop + doorH + 1.6,
			-D / 2 - 0.25,
			d.w + 1.2,
			3.0,
			0.3,
			pal.window,
			{ material = "Glass" }
		)
		if i == 1 then
			mainX = d.x
		end
	end
	-- the v5.4 sign above the roofline over the main entrance, with a red cross beside it
	local text = ctx.params.sign or ctx.kit.signText or "HOSPITAL"
	local signY = roofTop + ph + 4.2
	add(
		"SignPost1",
		mainX - 16,
		roofTop + (ph + 6.6) / 2,
		-D / 2 + 1.2,
		0.8,
		ph + 6.6,
		0.8,
		{ 90, 94, 96 },
		{ material = "Metal" }
	)
	add(
		"SignPost2",
		mainX + 16,
		roofTop + (ph + 6.6) / 2,
		-D / 2 + 1.2,
		0.8,
		ph + 6.6,
		0.8,
		{ 90, 94, 96 },
		{ material = "Metal" }
	)
	ctx.list:add(ctx.frame, "SignBoard", mainX, signY, -D / 2 + 0.6, 44, 6.6, 0.5, {
		color = Building.SIGN_TEAL,
		canCollide = false,
		role = "Sign",
		attrs = { SignText = text .. "  ·  EMERGENCY" },
	})
	ctx.list:extra({
		kind = "SurfaceGui",
		part = "SignBoard",
		name = "Sign",
		text = text .. "  ·  EMERGENCY",
		face = "Front",
	})
	add("CrossBack", mainX + 27, signY, -D / 2 + 0.6, 7.2, 7.2, 0.5, WHITE)
	add("CrossV", mainX + 27, signY, -D / 2 + 0.2, 1.8, 5.6, 0.4, RED, { material = "Neon" })
	add("CrossH", mainX + 27, signY, -D / 2 + 0.15, 5.6, 1.8, 0.4, RED, { material = "Neon" })
end

function Hospital.plan(ctx: Spec.LotCtx)
	Programme.build(ctx)
	if ctx.building and (ctx.building :: any).id == "hospital" then
		Hospital.facade(ctx)
	end
end

return Hospital
