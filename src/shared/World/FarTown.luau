--!strict
-- ReplicatedStorage.Shared.World.FarTown
-- The town as it reads from far off (the sky lift's lane 8 and the review of the view from the Lookout: "the town
-- is plain boxes: no roofs, no windows, no trees"). The town bake keeps one massing box per building in its
-- Persistent Skyline (Worldgen/Skyline: the axis-aligned envelope of the lot's solid parts, in the lot's first
-- colour, shown while the lot is streamed out). From those boxes and the lots' own data this plans a richer far
-- house, drawn by the client only (Client/Render/FarTown; nothing new in the town bake):
--   * the body turned with its lot (its "facing": +X/-X/+Z/-Z, or "yaw N deg|rad"), its footprint solved from the
--     axis-aligned envelope;
--   * a roof: a gable of two wedges in a roof colour (houses and the like; ridge along the longer side), or a
--     flat roof's darker cap (shops, quay buildings, the mall);
--   * a window band (one per storey, at most three) round all four faces: dark glass by day; at night `lit`
--     bands glow warm (the client turns them to Neon), about seven houses in ten and nine shops in ten;
-- and one soft crown per tree (generated TreeArt: a trunk and three balls inside the leaves' envelope) for the
-- client to show from far off.
-- Pure: no Instances. Every number is from the inputs and a hash of the lot's id (the same on every screen).
-- Interface: plan(boxes, lots) -> { Piece }; crowns(treeArt) -> { Crown }; yawOf(facing) -> radians?;
--   footprint(sx, sz, yaw) -> w, d; hash(s) -> 0..1; ROOF_COLOURS, GLASS, LIT_COLOURS, GABLE
-- Piece = { lot, name, shape ("Block" | "Wedge"), x, y, z, yaw, tilt (radians about the piece's own Y after yaw:
--   0 or pi, for the second wedge), sx, sy, sz, color, material, band (a window band), lit }

local FarTown = {}

export type Box = {
	lot: string,
	cx: number,
	cy: number,
	cz: number,
	sx: number,
	sy: number,
	sz: number,
	color: { number },
}
export type Piece = {
	lot: string,
	name: string,
	shape: string,
	x: number,
	y: number,
	z: number,
	yaw: number,
	sx: number,
	sy: number,
	sz: number,
	color: { number },
	material: string,
	band: boolean,
	lit: boolean,
	litColor: { number }?,
}
export type Crown = {
	x: number,
	y: number,
	z: number,
	d: number,
	h: number,
	color: { number },
	trunkBase: number,
	trunkTop: number,
	trunkD: number,
	balls: { { any } }, -- { x, y, z, diameter, colour }
}

FarTown.ROOF_COLOURS = table.freeze({
	table.freeze({ 150, 74, 52 }), -- terracotta
	table.freeze({ 84, 88, 96 }), -- slate
	table.freeze({ 108, 66, 50 }), -- dark clay
	table.freeze({ 92, 102, 86 }), -- weathered green
	table.freeze({ 128, 50, 42 }), -- red tile
	table.freeze({ 70, 72, 78 }), -- dark slate
})
FarTown.CAP_COLOUR = table.freeze({ 96, 96, 92 })
FarTown.GLASS = table.freeze({ 46, 56, 68 })
FarTown.LIT_COLOURS = table.freeze({
	table.freeze({ 255, 198, 128 }),
	table.freeze({ 255, 214, 158 }),
	table.freeze({ 246, 184, 112 }),
})
FarTown.CROWN = table.freeze({ 62, 90, 52 })
FarTown.CROWN_DARK = table.freeze({ 48, 72, 44 })
FarTown.BARK = table.freeze({ 86, 70, 56 })
FarTown.STOREY = 9 -- studs a storey (a window band each, at most three)
FarTown.BAND = 1.5 -- a band's height
FarTown.LIT_HOMES = 0.7
FarTown.LIT_SHOPS = 0.9
-- lot types drawn with a pitched roof (the rest get a flat roof's cap)
FarTown.GABLE = table.freeze({
	house = true,
	guesthouse = true,
	estate_mansion = true,
	cottage = true,
	farmhouse = true,
	barn = true,
	chapel = true,
	church = true,
	restaurant_icecream = true,
})

-- FNV-1a of a string, as a fraction 0..1 (exact in doubles).
function FarTown.hash(s: string): number
	local h = 2166136261
	for i = 1, #s do
		h = bit32.bxor(h, string.byte(s, i))
		h = (h * 16777619) % 4294967296
	end
	return h / 4294967296
end

-- The yaw a lot's "facing" names (Roblox yaw: CFrame.Angles(0, yaw, 0)); nil when it names none.
function FarTown.yawOf(facing: any): number?
	if type(facing) ~= "string" then
		return nil
	end
	local axis = string.match(facing, "^([%+%-][XZ])")
	if axis == "+X" or axis == "-X" then
		return math.pi / 2
	elseif axis == "+Z" or axis == "-Z" then
		return 0
	end
	local n, unit = string.match(facing, "^yaw%s+([%-%d%.]+)%s*(%a+)")
	local v = tonumber(n)
	if v == nil then
		return nil
	end
	return if unit == "deg" then math.rad(v) else v
end

-- The building's own width (along its local X) and depth from its axis-aligned envelope sx x sz at `yaw`.
function FarTown.footprint(sx: number, sz: number, yaw: number): (number, number)
	local c, s = math.abs(math.cos(yaw)), math.abs(math.sin(yaw))
	if s < 0.02 then
		return sx, sz
	elseif c < 0.02 then
		return sz, sx
	end
	local den = c * c - s * s
	local w, d
	if math.abs(den) < 0.25 then
		-- near 45 degrees the envelope cannot tell width from depth: a square of the same area
		local side = (sx + sz) / 2 / (c + s)
		w, d = side, side
	else
		w = (sx * c - sz * s) / den
		d = (sz * c - sx * s) / den
	end
	local lo = 0.3 * math.min(sx, sz)
	return math.clamp(w, lo, math.max(sx, sz)), math.clamp(d, lo, math.max(sx, sz))
end

local function pick(list: { { number } }, f: number): { number }
	return list[math.clamp(math.floor(f * #list) + 1, 1, #list)]
end

-- The far house for each massing box whose lot is known (lots: id -> the generated lot record).
function FarTown.plan(boxes: { Box }, lots: { [string]: any }): { Piece }
	local out: { Piece } = {}
	for _, b in boxes do
		local lot = lots[b.lot]
		local yaw = (if lot then FarTown.yawOf(lot.facing) else nil) or 0
		local w, d = FarTown.footprint(b.sx, b.sz, yaw)
		local y0, y1 = b.cy - b.sy / 2, b.cy + b.sy / 2
		local kind = if lot then tostring(lot.type) else ""
		local gable = FarTown.GABLE[kind] == true and b.sy >= 6
		local h1, h2 = FarTown.hash(b.lot), FarTown.hash(b.lot .. "/2")
		local function add(
			name: string,
			shape: string,
			x: number,
			y: number,
			z: number,
			py: number,
			sx: number,
			sy: number,
			sz: number,
			color: { number },
			material: string
		)
			table.insert(out, {
				lot = b.lot,
				name = name,
				shape = shape,
				x = x,
				y = y,
				z = z,
				yaw = py,
				sx = sx,
				sy = sy,
				sz = sz,
				color = color,
				material = material,
				band = false,
				lit = false,
				litColor = nil,
			})
			return out[#out]
		end
		local eaves = y1
		if gable then
			-- the ridge along the longer side: wedges whose slope rises toward their local +Z (the ridge)
			local long, short = math.max(w, d), math.min(w, d)
			local ridgeYaw = if w >= d then yaw else yaw + math.pi / 2
			local rh = math.clamp(0.42 * short, 2, 0.45 * b.sy)
			eaves = y1 - rh
			local roof = pick(FarTown.ROOF_COLOURS :: any, h1)
			local half = short / 2 + 0.5
			for _, side in { -1, 1 } do
				-- the ridge runs along the turned frame's X; a wedge's local -Z edge is its eave and +Z its ridge
				-- edge, so each sits half its depth across the ridge (the frame's Z) and faces back toward it
				local ax, az = math.sin(ridgeYaw), math.cos(ridgeYaw) -- across the ridge (the frame's +Z)
				local ox, oz = side * ax * half / 2, side * az * half / 2
				local py = ridgeYaw + (if side > 0 then math.pi else 0)
				add("Roof", "Wedge", b.cx + ox, eaves + rh / 2, b.cz + oz, py, long + 1, rh, half, roof, "Slate")
			end
		else
			-- a flat roof's cap, darker, a little over the walls
			add("Cap", "Block", b.cx, y1 - 0.3, b.cz, yaw, w + 0.5, 0.6, d + 0.5, FarTown.CAP_COLOUR :: any, "Concrete")
			eaves = y1 - 0.6
		end
		add(
			"Body",
			"Block",
			b.cx,
			(y0 + eaves) / 2 + 0.02,
			b.cz,
			yaw,
			w,
			eaves - y0 + 0.04,
			d,
			b.color,
			"SmoothPlastic"
		)
		-- window bands, one a storey (at most three), round all four faces
		local wall = eaves - y0
		local storeys = math.clamp(math.floor(wall / FarTown.STOREY + 0.35), 1, 3)
		local lit = h2 < (if gable then FarTown.LIT_HOMES else FarTown.LIT_SHOPS)
		local litColor = pick(FarTown.LIT_COLOURS :: any, FarTown.hash(b.lot .. "/3"))
		for k = 1, storeys do
			local yb = y0 + wall * (k - 0.45) / storeys
			local band = add(
				"Band",
				"Block",
				b.cx,
				yb,
				b.cz,
				yaw,
				w + 0.16,
				FarTown.BAND,
				d + 0.16,
				FarTown.GLASS :: any,
				"SmoothPlastic"
			)
			band.band = true
			band.lit = lit
			band.litColor = litColor
		end
	end
	return out
end

-- One soft crown per tree, a little inside its leaves' envelope (TreeArt: pivot + part offsets and sizes,
-- MeshParts whose name starts with "Leaves") so it never pokes through the real tree: a trunk from the pivot up
-- into the crown and three overlapping balls (a big one in the middle, two smaller ones either side and lower,
-- in two greens), so it reads as a tree and not as a ball floating over the grass.
function FarTown.crowns(treeArt: { any }): { Crown }
	local out: { Crown } = {}
	for _, rec in treeArt do
		local x0, x1, y0, y1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge, math.huge, -math.huge
		local pv = rec.pivot
		for _, p in rec.parts or {} do
			if type(p.name) == "string" and string.sub(p.name, 1, 6) == "Leaves" then
				local c = { pv[1] + p.offset[1], pv[2] + p.offset[2], pv[3] + p.offset[3] }
				x0, x1 = math.min(x0, c[1] - p.size[1] / 2), math.max(x1, c[1] + p.size[1] / 2)
				y0, y1 = math.min(y0, c[2] - p.size[2] / 2), math.max(y1, c[2] + p.size[2] / 2)
				z0, z1 = math.min(z0, c[3] - p.size[3] / 2), math.max(z1, c[3] + p.size[3] / 2)
			end
		end
		if x0 < x1 then
			local cx, cz = (x0 + x1) / 2, (z0 + z1) / 2
			local wide = ((x1 - x0) + (z1 - z0)) / 2
			local tall = y1 - y0
			local big = 0.78 * math.min(tall, wide)
			local small = 0.72 * big
			local cy = math.min(y0 + 0.5 * tall, y1 - big / 2) -- in the middle of the leaves, its top under theirs
			local f = FarTown.hash(`{math.floor(cx)}/{math.floor(cz)}`)
			local ax, az = math.cos(f * 2 * math.pi), math.sin(f * 2 * math.pi)
			local spread = 0.22 * wide
			local dark = FarTown.CROWN_DARK :: any
			table.insert(out, {
				x = cx,
				y = cy,
				z = cz,
				d = big,
				h = tall,
				color = FarTown.CROWN :: any,
				trunkBase = pv[2],
				trunkTop = cy,
				trunkD = math.clamp(0.07 * wide, 1.2, 5),
				balls = {
					{ cx, cy, cz, big, FarTown.CROWN :: any },
					{ cx + ax * spread, cy - 0.12 * big, cz + az * spread, small, dark },
					{ cx - ax * spread, cy - 0.08 * big, cz - az * spread, small * 0.9, dark },
				},
			})
		end
	end
	return out
end

return FarTown
