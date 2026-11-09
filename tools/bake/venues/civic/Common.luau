--!strict
-- tools/bake/venues/civic/Common: shared helpers for the F2 civic bake (docs/waves/BATCH2_SPEC.md §2.2): the venue
-- Model (attributes, Atomic streaming, the conventional folders), the Anchors folder, the plinth rule (floor top
-- at floorY, skirt down to ground.min - 2), steps from a door down to the ground, walls with openings, windows,
-- gable roofs, signs, seats and a few props every civic venue uses. All in the venue's local frame through
-- tools/bake/alley/Kit (X across the frontage, Y up from the finished floor, D into the building).
-- Interface: venue(kit, parent, v) -> (model, folders); anchors(kit, folders, v, owners); groundY(v, X, D);
--   plinth(...); steps(...); wallX/wallD(...); window(...); gable(...); sign(...); seat(...); bench(...);
--   lamp(...); tree(...); fence(...); prompt-free (the server adds prompts at boot)

local Height = require("../../../../src/shared/World/Height")
local AlleyLayout = require("../../../../src/shared/Attractions/AlleyLayout")

local Common = {}

export type Folders = {
	model: any,
	shell: any,
	interior: any,
	props: any,
	anchors: any,
	seats: any,
	carve: any,
	interact: any,
}

-- Colours (RGB) the civic quarter shares.
Common.C = {
	brick = { 150, 72, 54 },
	brickDark = { 118, 56, 44 },
	stone = { 214, 206, 188 },
	stoneDark = { 168, 160, 146 },
	trim = { 244, 240, 228 },
	slate = { 74, 80, 92 },
	glass = { 168, 206, 226 },
	glassNight = { 255, 214, 150 },
	wood = { 132, 92, 58 },
	woodDark = { 92, 62, 40 },
	woodLight = { 186, 146, 98 },
	metal = { 52, 56, 60 },
	chrome = { 196, 200, 206 },
	grass = { 98, 140, 70 },
	lawn = { 108, 152, 76 },
	soil = { 92, 66, 44 },
	concrete = { 188, 184, 176 },
	asphalt = { 62, 64, 66 },
	white = { 246, 246, 242 },
	paper = { 250, 246, 232 },
	green = { 52, 110, 64 },
	red = { 178, 46, 42 },
	gold = { 212, 170, 72 },
	black = { 28, 28, 30 },
}

local function ext()
	local ok, e = pcall(require, "../../../../generated/TerrainExtensions")
	return if ok then e else nil
end
local configured = false
function Common.configure()
	if not configured then
		Height.configure(ext())
		configured = true
	end
end

-- Ground height in the venue's local Y (relative to floorY) under a local point.
function Common.groundY(v: any, X: number, D: number): number
	Common.configure()
	local x, _, z = AlleyLayout.toWorld(v.place, X, 0, D)
	return Height.at(x, z) - v.place.floorY
end

function Common.worldGround(x: number, z: number): number
	Common.configure()
	return Height.at(x, z)
end

function Common.venue(kit: any, parent: any, v: any): Folders
	local r = kit.roblox
	local m = kit:model(parent, v.id)
	m:SetAttribute("VenueId", v.id)
	m:SetAttribute("Family", v.family)
	m:SetAttribute("Type", v.type)
	m:SetAttribute("Name", v.name)
	m:SetAttribute("FloorY", v.place.floorY)
	m:SetAttribute("Yaw", v.place.yaw)
	m:SetAttribute("OriginX", v.place.x)
	m:SetAttribute("OriginZ", v.place.z)
	m:SetAttribute("PartBudget", v.partBudget)
	m.ModelStreamingMode = r.Enum.ModelStreamingMode.Atomic
	local f: Folders = {
		model = m,
		shell = kit:folder(m, "Shell"),
		interior = kit:folder(m, "Interior"),
		props = kit:folder(m, "Props"),
		anchors = kit:folder(m, "Anchors"),
		seats = kit:folder(m, "Seats"),
		carve = kit:folder(m, "TerrainCarve"),
		interact = kit:folder(m, "Interact"),
	}
	return f
end

-- One invisible 0.2-stud part per anchor this bake owns, at its world point with its yaw (§2.2).
function Common.anchors(kit: any, f: Folders, v: any, owners: { [string]: boolean })
	for _, a in v.anchors do
		if owners[a.owner] then
			local yaw = math.rad(a.yaw or 0)
			local p = kit:at(f.anchors, a.id, a.at[1], a.at[2], a.at[3], 0.2, 0.2, 0.2, { 255, 255, 255 }, "SmoothPlastic", {
				collide = false,
				query = false,
				shadow = false,
				transparency = 1,
				rot = kit.roblox.CFrame.Angles(0, -yaw, 0),
			})
			p:SetAttribute("Kind", a.kind)
			p:SetAttribute("Owner", a.owner)
			p:SetAttribute("VenueId", v.id)
			for _, k in { "game", "ride", "item", "forage", "gig", "book", "note", "serves" } do
				local val = (a :: any)[k]
				if val ~= nil then
					p:SetAttribute(string.upper(string.sub(k, 1, 1)) .. string.sub(k, 2), val)
				end
			end
			kit.count -= 1 -- anchors are markers, not scenery (not counted against the part budget)
		end
	end
end

-- The plinth rule: foundation from ground.min - 2 up to the floor finish (top at -0.2), the finish to 0.
function Common.plinth(
	kit: any,
	f: Folders,
	v: any,
	x0: number,
	x1: number,
	d0: number,
	d1: number,
	color: { number },
	material: string,
	floorColor: { number },
	floorMat: string
)
	local bottom = v.ground.min - 2 - v.place.floorY
	kit:box(f.shell, "Foundation", x0, x1, bottom, -0.2, d0, d1, color, material)
	kit:box(f.shell, "Floor", x0 + 0.01, x1 - 0.01, -0.2, 0, d0 + 0.01, d1 - 0.01, floorColor, floorMat)
	-- a terrain carve under the whole footprint when the ground comes within 0.3 of the floor
	if v.ground.max > v.place.floorY - 0.6 then
		kit:box(f.carve, "Carve", x0, x1, -6, -0.05, d0, d1, { 255, 0, 0 }, "SmoothPlastic", {
			collide = false,
			query = false,
			transparency = 1,
		})
		kit.count -= 1
	end
end

-- Steps from local height `top` (at the door sill, D = dEdge) outward along `dir` (-1 = toward -D) down to the
-- ground at X across `width`. Returns the D where the bottom step ends.
function Common.steps(
	kit: any,
	parent: any,
	v: any,
	X: number,
	dEdge: number,
	width: number,
	dir: number,
	top: number,
	color: { number },
	material: string,
	opts: { rise: number?, tread: number?, cheeks: { number }? }?
): number
	local o = opts or {}
	local rise = o.rise or 0.75
	local tread = o.tread or 1.4
	-- find the ground where the stairs land (iterate: further out is lower on a slope)
	local g = Common.groundY(v, X, dEdge + dir * 2)
	local n = math.max(1, math.ceil((top - g) / rise))
	for _ = 1, 3 do
		g = Common.groundY(v, X, dEdge + dir * (n * tread + 0.5))
		n = math.max(1, math.ceil((top - g) / rise))
	end
	if top - g < 0.25 then
		return dEdge
	end
	local h = (top - g) / n
	local bottom = math.min(g, Common.groundY(v, X, dEdge)) - 1.5
	for i = 1, n do
		local ytop = top - i * h
		local da = dEdge + dir * (i - 1) * tread
		local db = dEdge + dir * i * tread
		kit:box(parent, `Step{i}`, X - width / 2, X + width / 2, bottom, ytop, math.min(da, db), math.max(da, db), color, material)
	end
	local c = o.cheeks
	if c then
		local dEnd = dEdge + dir * n * tread
		for _, sx in { -1, 1 } do
			kit:box(
				parent,
				"Cheek",
				X + sx * (width / 2) - (if sx > 0 then 0 else 0.6),
				X + sx * (width / 2) + (if sx > 0 then 0.6 else 0),
				bottom,
				top + 0.4,
				math.min(dEdge, dEnd),
				math.max(dEdge, dEnd),
				c,
				material
			)
		end
	end
	return dEdge + dir * n * tread
end

-- A wall in the X-Y plane at D in [d0, d1] (thickness), spanning X with rectangular openings
-- { {x0, x1, y0, y1} }.
function Common.wallX(
	kit: any,
	parent: any,
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	d0: number,
	d1: number,
	holes: { { number } },
	color: { number },
	material: string,
	opts: any?
)
	for i, r in kit:holes(x0, x1, y0, y1, holes) do
		kit:box(parent, `{name}{i}`, r[1], r[2], r[3], r[4], d0, d1, color, material, opts)
	end
end

-- A wall in the D-Y plane at X in [x0, x1], spanning D with openings { {d0, d1, y0, y1} }.
function Common.wallD(
	kit: any,
	parent: any,
	name: string,
	d0: number,
	d1: number,
	y0: number,
	y1: number,
	x0: number,
	x1: number,
	holes: { { number } },
	color: { number },
	material: string,
	opts: any?
)
	for i, r in kit:holes(d0, d1, y0, y1, holes) do
		kit:box(parent, `{name}{i}`, x0, x1, r[3], r[4], r[1], r[2], color, material, opts)
	end
end

-- Glazing in an opening: one glass pane plus a sill and a head (and a mullion when wide).
-- axis "X": the opening is in a wall at constant D (centre dC); "D": in a wall at constant X (centre xC).
function Common.window(
	kit: any,
	parent: any,
	axis: string,
	a0: number,
	a1: number,
	y0: number,
	y1: number,
	c: number,
	frame: { number },
	glass: { number }?,
	opts: { mullion: boolean?, lit: boolean?, transparency: number? }?
)
	local o = opts or {}
	local g = glass or Common.C.glass
	local tr = o.transparency or 0.45
	local gopts = { collide = true, query = true, transparency = tr, reflectance = 0.15, shadow = false }
	local function box(name: string, b0: number, b1: number, yy0: number, yy1: number, t: number, col: { number }, mat: string, op: any?)
		if axis == "X" then
			kit:box(parent, name, b0, b1, yy0, yy1, c - t, c + t, col, mat, op)
		else
			kit:box(parent, name, c - t, c + t, yy0, yy1, b0, b1, col, mat, op)
		end
	end
	box("Glass", a0, a1, y0, y1, 0.08, g, "Glass", gopts)
	box("Sill", a0 - 0.3, a1 + 0.3, y0 - 0.25, y0, 0.45, frame, "SmoothPlastic", { shadow = false })
	box("Head", a0 - 0.15, a1 + 0.15, y1, y1 + 0.3, 0.3, frame, "SmoothPlastic", { shadow = false })
	if o.mullion ~= false and a1 - a0 > 3 then
		local m = (a0 + a1) / 2
		box("Mullion", m - 0.12, m + 0.12, y0, y1, 0.16, frame, "SmoothPlastic", { collide = false, shadow = false })
	end
end

-- A gable roof. ridge "X": the ridge runs along X over [x0, x1] and the slopes fall toward d0 and d1;
-- ridge "D": along D over [d0, d1], slopes toward x0 and x1. Eaves at local y0, ridge at y0 + rise.
-- Gable-end triangles are filled with the wall colour (wedges), the slabs overhang by `over`.
function Common.gable(
	kit: any,
	parent: any,
	ridge: string,
	x0: number,
	x1: number,
	d0: number,
	d1: number,
	y0: number,
	rise: number,
	roofColor: { number },
	roofMat: string,
	wallColor: { number },
	wallMat: string,
	over: number?,
	thick: number?
)
	local CFrame = kit.roblox.CFrame
	local ov = over or 1.2
	local th = thick or 0.6
	if ridge == "X" then
		local half = (d1 - d0) / 2
		local dm = (d0 + d1) / 2
		local slope = math.sqrt(half * half + rise * rise)
		local ang = math.atan2(rise, half)
		-- slab centres: halfway down each slope, lifted by half the thickness along the normal
		local len = slope + ov
		for _, s in { -1, 1 } do
			local cdOff = (len / 2 - ov) * math.cos(ang)
			local cy = y0 + rise - (len / 2 - ov) * math.sin(ang) - (len / 2) * 0 + th / 2 * math.cos(ang)
			-- centre measured from the ridge down the slope
			local along = len / 2 - (ov - ov) -- from the ridge
			local cd = dm + s * (along * math.cos(ang) - ov * math.cos(ang) + ov * math.cos(ang))
			cy = y0 + rise - along * math.sin(ang) + th / 2 * math.cos(ang)
			cd = dm + s * along * math.cos(ang) - s * th / 2 * math.sin(ang) * 0
			local _ = cdOff
			kit:at(parent, "RoofSlab", (x0 + x1) / 2, cy, cd, x1 - x0 + 2 * ov * 0.6, th, len, roofColor, roofMat, {
				rot = CFrame.Angles(if s < 0 then ang else -ang, 0, 0),
			})
		end
		-- ridge cap
		kit:at(parent, "Ridge", (x0 + x1) / 2, y0 + rise + th * 0.7, dm, x1 - x0 + 2 * ov * 0.6, 0.35, 0.7, roofColor, roofMat, { shadow = false })
		-- gable triangles at both X ends
		for _, xe in { x0, x1 } do
			kit:wedge(parent, "Gable", xe + (if xe == x0 then 0.3 else -0.3), y0 + rise / 2, dm - half / 2, 0.6, rise, half, wallColor, wallMat, {
				rot = CFrame.Angles(0, math.pi, 0),
			})
			kit:wedge(parent, "Gable", xe + (if xe == x0 then 0.3 else -0.3), y0 + rise / 2, dm + half / 2, 0.6, rise, half, wallColor, wallMat)
		end
	else
		local half = (x1 - x0) / 2
		local xm = (x0 + x1) / 2
		local slope = math.sqrt(half * half + rise * rise)
		local ang = math.atan2(rise, half)
		local len = slope + ov
		for _, s in { -1, 1 } do
			local along = len / 2
			local cy = y0 + rise - along * math.sin(ang) + th / 2 * math.cos(ang)
			local cx = xm + s * along * math.cos(ang)
			kit:at(parent, "RoofSlab", cx, cy, (d0 + d1) / 2, len, th, d1 - d0 + 2 * ov * 0.6, roofColor, roofMat, {
				rot = CFrame.Angles(0, 0, if s < 0 then -ang else ang),
			})
		end
		kit:at(parent, "Ridge", xm, y0 + rise + th * 0.7, (d0 + d1) / 2, 0.7, 0.35, d1 - d0 + 2 * ov * 0.6, roofColor, roofMat, { shadow = false })
		for _, de in { d0, d1 } do
			local dd = de + (if de == d0 then 0.3 else -0.3)
			kit:wedge(parent, "Gable", xm - half / 2, y0 + rise / 2, dd, 0.6, rise, half, wallColor, wallMat, {
				rot = CFrame.Angles(0, -math.pi / 2, 0),
			})
			kit:wedge(parent, "Gable", xm + half / 2, y0 + rise / 2, dd, 0.6, rise, half, wallColor, wallMat, {
				rot = CFrame.Angles(0, math.pi / 2, 0),
			})
		end
	end
end

-- A sign board with text on its front (-D unless face given). Returns the board.
function Common.sign(
	kit: any,
	parent: any,
	text: string,
	cx: number,
	cy: number,
	cd: number,
	w: number,
	h: number,
	board: { number },
	ink: { number },
	opts: { face: string?, font: string?, depth: number?, material: string?, lit: boolean?, rot: any?, pps: number? }?
): any
	local o = opts or {}
	local depth = o.depth or 0.3
	local p = kit:at(parent, "Sign", cx, cy, cd, w, h, depth, board, o.material or "SmoothPlastic", {
		shadow = false,
		rot = o.rot,
	})
	local gui = kit:gui(p, o.face or "Front", o.pps or 40)
	kit:label(gui, {
		Text = text,
		TextColor = ink,
		Font = o.font or "Garamond",
		Size = { 0.94, 0.86 },
		Pos = { 0.03, 0.07 },
	})
	if o.lit then
		kit:light(p, "SurfaceLight", {
			Face = o.face or "Front",
			Brightness = 0.6,
			Range = 6,
			Angle = 70,
			Color = { 255, 230, 190 },
		})
	end
	return p
end

-- A sit-able Seat part (the server adds the "Sit" prompt at boot). yaw in degrees: 0 faces +D.
function Common.seat(kit: any, f: Folders, name: string, X: number, Y: number, D: number, w: number, d: number, yawDeg: number, color: { number }, material: string): any
	local s = kit:at(f.seats, name, X, Y, D, w, 0.4, d, color, material, {
		class = "Seat",
		rot = kit.roblox.CFrame.Angles(0, math.rad(180 - yawDeg), 0),
		shadow = false,
	})
	s.Disabled = false
	s:SetAttribute("Seat", name)
	return s
end

-- A park bench (slatted seat and back on cast-iron ends), facing yawDeg (0 = facing +D). Returns its Seat.
function Common.bench(kit: any, f: Folders, name: string, X: number, Y: number, D: number, yawDeg: number, len: number?): any
	local CFrame = kit.roblox.CFrame
	local L = len or 5
	local rot = CFrame.Angles(0, math.rad(-yawDeg), 0)
	local function at(lx: number, ly: number, ld: number): (number, number, number)
		-- rotate a bench-local offset (lx across, ld forward) by the bench yaw
		local c, s = math.cos(math.rad(yawDeg)), math.sin(math.rad(yawDeg))
		return X + lx * c + ld * s, Y + ly, D - lx * s + ld * c
	end
	local x, y, d = at(0, 1.55, 0)
	local seat = Common.seat(kit, f, name, x, y, d, L, 1.4, yawDeg, Common.C.woodLight, "Wood")
	x, y, d = at(0, 2.6, -0.75)
	kit:at(f.props, "BenchBack", x, y, d, L, 1.1, 0.2, Common.C.woodLight, "Wood", { rot = rot * CFrame.Angles(-0.2, 0, 0) })
	for _, sx in { -1, 1 } do
		x, y, d = at(sx * (L / 2 - 0.3), 1.35, -0.1)
		kit:at(f.props, "BenchEnd", x, y, d, 0.25, 2.7, 1.5, Common.C.metal, "Metal", { rot = rot, shadow = false })
	end
	return seat
end

-- A lamp standard (post, lantern with a PointLight).
function Common.lamp(kit: any, parent: any, X: number, Y: number, D: number, h: number?, color: { number }?)
	local H = h or 11
	local col = color or Common.C.metal
	kit:cyl(parent, "LampBase", X, Y + 0.5, D, 1, 1.1, "Y", col, "Metal", { shadow = false })
	kit:cyl(parent, "LampPost", X, Y + H / 2, D, H, 0.35, "Y", col, "Metal", { shadow = false })
	local head = kit:at(parent, "LampHead", X, Y + H + 0.6, D, 1.1, 1.3, 1.1, { 255, 236, 190 }, "Neon", {
		collide = false,
		query = false,
		shadow = false,
		transparency = 0.15,
	})
	kit:at(parent, "LampCap", X, Y + H + 1.4, D, 1.5, 0.3, 1.5, col, "Metal", { collide = false, shadow = false })
	kit:light(head, "PointLight", { Brightness = 1.2, Range = 22, Color = { 255, 214, 160 }, Shadows = false })
	head:SetAttribute("NightLight", true)
end

-- A simple deciduous tree (trunk, three canopy balls).
function Common.tree(kit: any, parent: any, X: number, Y: number, D: number, scale: number?, leaf: { number }?)
	local s = scale or 1
	local lc = leaf or { 92, 132, 70 }
	kit:cyl(parent, "Trunk", X, Y + 4 * s, D, 8 * s, 1.1 * s, "Y", Common.C.woodDark, "Wood")
	kit:ball(parent, "Canopy", X, Y + 9 * s, D, 7.5 * s, lc, "Grass", { collide = false, query = false })
	kit:ball(parent, "Canopy", X + 2 * s, Y + 7.6 * s, D + 1.2 * s, 5.4 * s, { lc[1] + 10, lc[2] + 12, lc[3] + 6 }, "Grass", {
		collide = false,
		query = false,
	})
	kit:ball(parent, "Canopy", X - 1.8 * s, Y + 7.8 * s, D - 1.4 * s, 5 * s, { lc[1] - 8, lc[2] - 6, lc[3] - 4 }, "Grass", {
		collide = false,
		query = false,
	})
end

-- A picket fence along a straight local line, following the ground (posts every `step`), with gaps
-- { {a0, a1} } measured along the run from its start.
function Common.fence(
	kit: any,
	parent: any,
	v: any,
	ax: number,
	ad: number,
	bx: number,
	bd: number,
	h: number,
	color: { number },
	gaps: { { number } }?,
	style: string?
)
	local CFrame = kit.roblox.CFrame
	local dx, dd = bx - ax, bd - ad
	local L = math.sqrt(dx * dx + dd * dd)
	local step = 8
	local n = math.max(1, math.ceil(L / step))
	local yaw = math.atan2(dd, dx) -- local rotation about Y so the rail runs from a to b
	local function inGap(t0: number, t1: number): boolean
		for _, g in gaps or {} do
			if t1 > g[1] and t0 < g[2] then
				return true
			end
		end
		return false
	end
	for i = 0, n do
		local t = i / n
		local x, d = ax + dx * t, ad + dd * t
		local g = Common.groundY(v, x, d)
		if not inGap(t * L - 0.5, t * L + 0.5) then
			kit:at(parent, "FencePost", x, g + h / 2 - 0.2, d, 0.5, h + 0.4, 0.5, color, "Wood", { shadow = false })
		end
		if i < n then
			local t1 = (i + 1) / n
			local x1, d1 = ax + dx * t1, ad + dd * t1
			local g1 = Common.groundY(v, x1, d1)
			if not inGap(t * L, t1 * L) then
				local seg = L / n
				local pitch = math.atan2(g1 - g, seg)
				local mx, md = (x + x1) / 2, (d + d1) / 2
				local gm = (g + g1) / 2
				local rot = CFrame.Angles(0, -yaw, 0) * CFrame.Angles(0, 0, pitch)
				if style == "rail" then
					for _, ry in { h * 0.45, h * 0.85 } do
						kit:at(parent, "FenceRail", mx, gm + ry, md, seg, 0.25, 0.25, color, "Wood", { rot = rot, shadow = false })
					end
				else
					-- pickets as one slatted board (a striped look from a single part each side is enough at 8 st)
					kit:at(parent, "FenceRail", mx, gm + h * 0.75, md, seg, 0.25, 0.2, color, "Wood", { rot = rot, shadow = false })
					kit:at(parent, "Pickets", mx, gm + h * 0.45, md, seg - 0.4, h * 0.8, 0.12, color, "WoodPlanks", {
						rot = rot,
						shadow = false,
					})
				end
			end
		end
	end
end

-- A ground-following flat path from (ax, ad) to (bx, bd) in the venue frame, `w` wide, segments <= 12 st.
function Common.path(kit: any, parent: any, v: any, ax: number, ad: number, bx: number, bd: number, w: number, color: { number }, material: string, lift: number?)
	local CFrame = kit.roblox.CFrame
	local dx, dd = bx - ax, bd - ad
	local L = math.sqrt(dx * dx + dd * dd)
	if L < 0.05 then
		return
	end
	local n = math.max(1, math.ceil(L / 12))
	local yaw = math.atan2(dd, dx)
	local up = lift or 0.12
	for i = 1, n do
		local t0, t1 = (i - 1) / n, i / n
		local x0, d0 = ax + dx * t0, ad + dd * t0
		local x1, d1 = ax + dx * t1, ad + dd * t1
		local g0 = math.max(Common.groundY(v, x0, d0), Common.groundY(v, (x0 + x1) / 2, (d0 + d1) / 2) - 0.3)
		local g1 = Common.groundY(v, x1, d1)
		local seg = L / n
		local pitch = math.atan2(g1 - g0, seg)
		kit:at(
			parent,
			"Path",
			(x0 + x1) / 2,
			(g0 + g1) / 2 + up - 0.3,
			(d0 + d1) / 2,
			seg + 0.6,
			0.6,
			w,
			color,
			material,
			{ rot = CFrame.Angles(0, -yaw, 0) * CFrame.Angles(0, 0, pitch), shadow = false }
		)
	end
end

-- A flower bed: soil kerb plus a few coloured blooms.
function Common.flowerBed(kit: any, parent: any, v: any, X: number, D: number, w: number, d: number, colors: { { number } })
	local g = Common.groundY(v, X, D)
	kit:box(parent, "BedEdge", X - w / 2, X + w / 2, g - 0.6, g + 0.45, D - d / 2, D + d / 2, Common.C.stoneDark, "Brick", { shadow = false })
	kit:box(parent, "BedSoil", X - w / 2 + 0.3, X + w / 2 - 0.3, g + 0.45, g + 0.6, D - d / 2 + 0.3, D + d / 2 - 0.3, Common.C.soil, "Ground", {
		shadow = false,
	})
	local n = math.max(2, math.floor(w / 2.2))
	for i = 1, n do
		local c = colors[(i - 1) % #colors + 1]
		local xx = X - w / 2 + (i - 0.5) * w / n
		kit:ball(parent, "Bloom", xx, g + 1.1, D + (if i % 2 == 0 then -d / 6 else d / 6), 1.1, c, "SmoothPlastic", {
			collide = false,
			query = false,
			shadow = false,
		})
	end
end

return Common
