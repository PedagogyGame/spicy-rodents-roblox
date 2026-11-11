--!strict
-- ServerScriptService.Server.WorldGen.Builders.Facade
-- The exterior art pass (owner 2026-11-10: "make these buildings ... much nicer"): everything that
-- turns a solid box into a building that reads as one, without touching what a body or a route
-- stands on. Windows get a casing, glazing bars and a sill (shop fronts a display pane on a stall
-- riser), doors a surround, a transom, a knob and panels, steps down to the ground and a hood, porch,
-- awning, canopy or portico by building type; gable roofs get eaves, rakes, fascia and barge boards, a
-- ridge cap and gutters; flat roofs a deck, parapet and coping; chimneys a cap and pots; corners get
-- boards, quoins, pilasters or (quay) oak posts, braces and a jetty beam. Colours and materials come
-- from the lot's Palette.Look, so each district keeps its v5.4 character
-- (docs/spec/worldgen_districts_art.md, "Buildings and interiors art pass").
--
-- Rules every part here obeys (tests/unit/worldgen_pins.spec, worldgen_facade.spec, worldgen_look.spec):
--   * decoration never collides and takes no queries (a ground ray from the sky lands on the pavement,
--     not on an awning); the one exception is door steps (role "Step"), which are real ground;
--   * roof plates, bodies, walls and floors are not moved: silhouettes, footprints and every climbing
--     route stay exactly where they were;
--   * no face lies on the plane of another drawn face (stacked trim differs by at least 0.04 st);
--   * names never start with Win, Timber, Cornice, Gable, Chimney, Roof, Wall, Body, Tile, Pad, Seg, Bank
--     or Greybox unless the part is one (tests and Client/World key on those prefixes).
--
-- Interface:
--   style(ctx) -> Style                       the lot's exterior style (pure function of type and id)
--   windowGrid(ctx, base, top, avoid, style, storey?) -> { Win }   where the windows go
--   windows(ctx, grid, style)                 casing, glass, bars, sills, lintels, shutters, flower boxes
--   entrance(ctx, door, style)                surround, transom, knob and panels (door followers), steps, canopy
--   roofSides(ctx, eave, peak, alongLocalX) -> { RoofSide }   the two roof plates (Building.roof draws them)
--   roofTrim(ctx, sides, eave, peak, alongLocalX, style)      eaves, rakes, fascia, barge boards, ridge cap, gutters
--   flatRoof(ctx, top, style, roofDeck)       deck, parapet and coping
--   corners(ctx, eave, style, base)           corner boards, quoins or pilasters
--   timber(ctx, eave)                         quay: back posts, braces and the jetty beam
--   chimneyCap(ctx, x, z, top, size, pots)    cap and pots
--   band(ctx, y, style)                       the fascia band behind a shop sign
--   downspouts(lotPlans, propPlans)           joins every drawn downspout to the gutter above it
--   KNOBS                                     the part-budget knobs
-- Pure (adds PartSpecs to ctx.list).

local Geometry = require("../Geometry")
local Import = require("../Import")
local Palette = require("../Palette")
local Spec = require("../Spec")
local Height = Import.shared("World/Height") :: typeof(require("../../shared/World/Height"))

local Facade = {}

-- Part-budget knobs (the whole town must stay under 27,000 parts: tests/unit/worldgen_look.spec). Turn
-- them in this order if the count runs over: rails, shutters, flowerBoxes, quoinsPerCorner, barge.
Facade.KNOBS = {
	rails = "front", -- sash meeting rails: "all" faces, "front" only, or "none"
	shutters = true, -- two boards beside the front windows of every third timber-clad house
	flowerBoxes = true, -- under the upper front windows of the quay houses
	quoinsPerCorner = 6,
	barge = true, -- barge boards under the gable rakes
	maxBays = 9, -- window bays on a long face (60 st and more)
}

Facade.EMBED = 0.05 -- studs every trim part reaches into the wall behind it
Facade.NECK_REACH = 4.2 -- studs: the longest neck from a downspout to a gutter

export type Style = {
	kind: string, -- cottage | brick | tudor | shopfront | civic | estate | utility
	winW: number,
	winH: number,
	rail: boolean, -- sash meeting rail
	shutters: boolean,
	lintel: boolean, -- a stone head over each window
	courses: boolean, -- continuous sill courses on the upper floors instead of single sills
	corners: string, -- boards | quoins | pilasters | timber | none
	canopy: string, -- porch | hood | awning | flat | portico | none
	columns: number, -- portico columns
	overhang: number, -- eave overhang (studs)
	rake: number, -- gable-end overhang (studs)
	display: boolean, -- shop-front display panes on the ground floor of the front
	displayW: number,
	flowerBoxes: boolean,
	transom: boolean, -- a glazed light over the door
	awning: { number }?,
	glow: boolean, -- windows that light up at night (homes and the quay)
}

export type Win = { face: string, floor: number, i: number, c: number, y: number, w: number, h: number, kind: string }
export type Gap = { c: number, w: number, top: number? } -- a door opening on a face (top above the seat)
export type Face = { id: string, len: number, fixed: number, out: number, alongX: boolean }
export type Door = {
	name: string, -- the leaf part's name (followers are named after it)
	doorId: string,
	face: string,
	c: number, -- centre along the face
	w: number,
	h: number,
	y0: number, -- sill above the seat
	proud: number, -- leaf front face beyond the wall plane (negative: recessed)
	wallTop: number, -- top of the wall above the seat
	surround: boolean?, -- false: the building draws its own (hospital)
	canopy: boolean?, -- true: this is the main entrance
	leaf: boolean?, -- false: no knob and panels
	slide: boolean?, -- the leaf slides into the wall (Builders/Shell): no knob to drag along its face
}
export type RoofSide = {
	name: string,
	side: number,
	mx: number,
	mz: number,
	cy: number,
	yaw: number,
	pitch: number,
	phi: number,
	slope: number,
	length: number,
	half: number,
	nx: number,
	ny: number,
}

local PLATE = 0.4 -- roof plate thickness (Building.roof)
local STEP = { 170, 166, 151 }
local GUTTER = { 92, 96, 98 }
local COPPER = { 113, 134, 121 } -- v5.4 quay copper #718679
local BRASS = { 182, 154, 83 } -- #b69a53
local POT = { 176, 112, 84 }
local CAP = { 150, 144, 132 }
local BLOOM = { { 186, 127, 135 }, { 233, 190, 78 }, { 222, 214, 190 } }
local AWNING_RED = { 168, 72, 60 }
local POLICE_BLUE = { 70, 120, 200 }

local function look(ctx: Spec.LotCtx): Palette.Look
	local pal = ctx.palette
	if pal == nil then
		pal = Palette.forLot(ctx.lot, ctx.kit)
		ctx.palette = pal
	end
	return pal :: Palette.Look
end

local function shade(c: { number }, k: number): { number }
	return {
		math.clamp(math.floor(c[1] * k + 0.5), 0, 255),
		math.clamp(math.floor(c[2] * k + 0.5), 0, 255),
		math.clamp(math.floor(c[3] * k + 0.5), 0, 255),
	}
end
Facade.shade = shade

function Facade.faces(ctx: Spec.LotCtx): { [string]: Face }
	local W, D = ctx.W, ctx.D
	return {
		F = { id = "F", len = W, fixed = -D / 2, out = -1, alongX = true },
		B = { id = "B", len = W, fixed = D / 2, out = 1, alongX = true },
		L = { id = "L", len = D, fixed = -W / 2, out = -1, alongX = false },
		R = { id = "R", len = D, fixed = W / 2, out = 1, alongX = false },
	}
end
local FACE_ORDER = { "F", "B", "L", "R" }

-- A visual-only part: never collides, takes no queries, casts no shadow unless asked.
local function deco(
	ctx: Spec.LotCtx,
	name: string,
	mx: number,
	my: number,
	mz: number,
	sx: number,
	sy: number,
	sz: number,
	color: { number },
	material: string?,
	o: Spec.Opts?
): Spec.PartSpec
	local opts: Spec.Opts = o or {}
	opts.color = color
	opts.material = material or "SmoothPlastic"
	opts.canCollide = false
	opts.canQuery = false
	if opts.castShadow == nil then
		opts.castShadow = false
	end
	opts.role = opts.role or "Trim"
	return ctx.list:add(ctx.frame, name, mx, my, mz, sx, sy, sz, opts)
end

-- A board on face `f`: centred `c` along the face and `y` above the seat, `w` wide, `h` tall, standing
-- `proud` of the wall plane (and EMBED into it).
local function board(
	ctx: Spec.LotCtx,
	f: Face,
	name: string,
	c: number,
	y: number,
	w: number,
	h: number,
	proud: number,
	color: { number },
	material: string?,
	o: Spec.Opts?,
	embed: number?
): Spec.PartSpec
	local t = proud + (embed or Facade.EMBED)
	local off = f.fixed + f.out * (proud - t / 2)
	if f.alongX then
		return deco(ctx, name, c, y, off, w, h, t, color, material, o)
	end
	return deco(ctx, name, off, y, c, t, h, w, color, material, o)
end

-- Model-local (mx, mz) of a point `c` along face `f` and `dist` studs out from its wall plane.
local function outPoint(f: Face, c: number, dist: number): (number, number)
	if f.alongX then
		return c, f.fixed + f.out * dist
	end
	return f.fixed + f.out * dist, c
end

-- Terrain height (above the seat) under a model-local point.
local function ground(ctx: Spec.LotCtx, mx: number, mz: number): number
	local wx, _, wz = Geometry.point(ctx.frame, mx, 0, mz)
	return Height.at(wx, wz) - ctx.seat
end

-- The highest the ground stands (above the seat) in front of a door: across the door's width, from the
-- wall to 3 st out. A sill lower than this is partly under the grass (WorldGen/DoorSill checks it).
function Facade.doorGround(ctx: Spec.LotCtx, face: string, c: number, w: number): number
	local f = Facade.faces(ctx)[face]
	local top = -math.huge
	for _, a in { -0.5, 0, 0.5 } do
		for _, dist in { 0, 1.5, 3 } do
			local mx, mz = outPoint(f, c + a * w, dist)
			top = math.max(top, ground(ctx, mx, mz))
		end
	end
	return top
end

function Facade.style(ctx: Spec.LotCtx): Style
	local t: string = ctx.lot.type or ""
	local id: string = ctx.lot.id or ""
	local pal = look(ctx)
	local i = Palette.index(id)
	local s: Style = {
		kind = "utility",
		winW = 3.2,
		winH = 4.4,
		rail = false,
		shutters = false,
		lintel = false,
		courses = false,
		corners = "none",
		canopy = "none",
		columns = 0,
		overhang = 1.625, -- v5.4 roof overhang 0.65 u
		rake = 1.2,
		display = false,
		displayW = 9,
		flowerBoxes = false,
		transom = false,
		awning = nil,
		glow = false,
	}
	if t == "quay_building" then
		s.kind, s.corners, s.winW, s.winH = "tudor", "timber", 3.6, 5.0
		s.display, s.displayW, s.flowerBoxes, s.glow = true, 8, true, true
		s.rake = 1.625 -- the 30 "gutter to ridge" routes run 1.62 st outside the gable wall: on this rake
		if i % 3 == 0 then
			-- worldgen_districts_art §3.4: an awning only when index % 3 == 0
			s.canopy = "awning"
			s.awning = if i % 2 == 1 then Palette.hex("#80987a") else Palette.hex("#b26d52")
		end
	elseif t == "house" or t == "guesthouse" then
		s.glow, s.transom = true, true
		if pal.material == "Brick" then
			s.kind, s.lintel, s.corners, s.winW, s.winH = "brick", true, "quoins", 3.0, 4.8
		else
			s.kind, s.rail, s.corners, s.winW, s.winH = "cottage", true, "boards", 3.6, 4.8
			s.shutters = i % 3 == 0
		end
		-- worldgen_core §5.1 (house 0), §6.1 (outer homes: porch 0.63 W on 2 posts); every other
		-- older Westside house too; the rest get a hood on brackets
		local porch = id == "core_house_0_victorian"
			or string.find(id, "outer_home_", 1, true) ~= nil
			or (string.find(id, "west_old_house_", 1, true) ~= nil and i % 2 == 0)
		s.canopy = if porch then "porch" else "hood"
	elseif t == "estate_mansion" then
		s.kind, s.lintel, s.courses, s.corners, s.canopy = "estate", true, true, "quoins", "portico"
		s.columns, s.winW, s.winH, s.transom, s.glow = 4, 4.4, 6.4, true, true
	elseif t == "mall" then
		s.kind, s.display, s.displayW, s.courses, s.corners, s.canopy = "shopfront", true, 12, true, "pilasters", "flat"
		s.winW, s.winH = 5.0, 8.0
	elseif t == "restaurant" then
		s.kind, s.display, s.canopy, s.awning = "shopfront", true, "awning", AWNING_RED
		s.winW, s.winH = 3.6, 4.8
	elseif t == "shop" then
		s.kind, s.display, s.canopy, s.awning = "shopfront", true, "awning", pal.accent
	elseif t == "restaurant_icecream" then
		s.kind, s.display, s.canopy, s.awning = "shopfront", true, "awning", pal.roof
	elseif t == "gas_station" then
		s.kind, s.display, s.canopy = "shopfront", true, "flat"
	elseif t == "hospital" or t == "police_station" then
		s.kind, s.corners, s.winW, s.winH = "civic", "pilasters", 3.4, 5.0
		if t == "police_station" then
			s.lintel, s.courses, s.canopy = true, true, "flat"
		end
	elseif t == "chapel_crypt" then
		s.corners, s.canopy, s.columns = "pilasters", "portico", 2
	elseif t == "shelter_house" then
		s.corners, s.canopy = "boards", "hood"
	end
	return s
end

-- Does this window glow at night? A stable 60 % of the panes of a home (Client/Render/TownLights).
local function glows(ctx: Spec.LotCtx, w: Win): boolean
	local n = Palette.index(ctx.lot.id or "") * 3 + w.floor * 7 + w.i * 5 + string.byte(w.face)
	return n % 10 < 6
end

-- Where the windows go between `base` and `top` (studs above the seat): floors of bays on each face,
-- clear of the door openings in `avoid` on the ground floor. Shop fronts get a tall ground storey whose
-- front carries display panes in the spans between the doors.
function Facade.windowGrid(
	ctx: Spec.LotCtx,
	base: number,
	top: number,
	avoid: { [string]: { Gap } }?,
	style: Style,
	storey: number?
): { Win }
	local out: { Win } = {}
	local pal = look(ctx)
	local height = top - base
	if height < 5 then
		return out
	end
	local SHOP = 13.2 -- the shop storey: display panes, the awning and the sign band
	local floors = math.clamp(math.floor(height / 9 + 0.3), 1, 3)
	local floorH = height / floors
	local upperBase, upperFloors = base, floors
	if style.display and storey then
		-- half-timbered: the upper storey starts on the mid timber band and its jetty beam, so no
		-- window is ever crossed by a band
		upperBase = storey + 0.7
		local rest = top - upperBase
		upperFloors = if rest >= 14 then 2 elseif rest >= 5 then 1 else 0
		floors = 1 + upperFloors
		floorH = if upperFloors > 0 then rest / upperFloors else height
	elseif style.display then
		local rest = height - SHOP
		upperFloors = if rest >= 6.5 then math.clamp(math.floor(rest / 9 + 0.3), 1, 3) else 0
		upperBase = base + SHOP
		floors = 1 + upperFloors
		floorH = if upperFloors > 0 then rest / upperFloors else height
	end
	local faces = Facade.faces(ctx)
	for _, fid in FACE_ORDER do
		local f = faces[fid]
		-- terraced quay rows hide their side walls: front and back only there
		local side = not f.alongX
		if f.len >= 9 and not (side and (pal.timber or f.len < 14)) then
			local bays = math.clamp(math.floor(f.len / 12), 1, 5)
			if f.len >= 60 then
				bays = math.clamp(math.floor(f.len / 15), 5, Facade.KNOBS.maxBays)
			end
			local gaps: { Gap } = if avoid and avoid[f.id] then avoid[f.id] else {}
			for fl = 1, floors do
				local y, winH
				if style.display then
					if fl == 1 then
						winH = math.min(style.winH, 5.2)
						y = base + math.min(6.2, height * 0.5)
					else
						winH = math.min(style.winH, floorH * 0.55)
						y = upperBase + (fl - 1.5) * floorH + (if storey then 0 else 0.3)
					end
				else
					winH = math.min(style.winH, floorH * 0.5)
					y = base + (fl - 0.5) * floorH + 0.3
					if fl == 1 and (style.kind == "cottage" or style.kind == "brick" or style.kind == "utility") then
						-- a home's ground-floor windows sit at eye height however tall the storey is
						y = math.min(y, base + 5.6)
					end
				end
				if fl == 1 and style.display and f.id == "F" then
					local spans: { { number } } = { { -f.len / 2 + 1.6, f.len / 2 - 1.6 } }
					for _, g in gaps do
						local nextSpans = {}
						local g0, g1 = g.c - g.w / 2 - 1.8, g.c + g.w / 2 + 1.8
						for _, sp in spans do
							if g1 <= sp[1] or g0 >= sp[2] then
								table.insert(nextSpans, sp)
							else
								table.insert(nextSpans, { sp[1], g0 })
								table.insert(nextSpans, { g1, sp[2] })
							end
						end
						spans = nextSpans
					end
					local h = math.min(6.4, height - 3.4)
					local k = 0
					for _, sp in spans do
						local len = sp[2] - sp[1]
						if len >= 4.5 and h >= 3 then
							local n = math.max(1, math.floor(len / (style.displayW + 3) + 0.5))
							local cell = len / n
							local w = math.min(cell - 1.4, style.displayW)
							for j = 1, n do
								k += 1
								local pane: Win = {
									face = f.id,
									floor = 1,
									i = k,
									c = sp[1] + (j - 0.5) * cell,
									y = base + 1.7 + h / 2,
									w = w,
									h = h,
									kind = "display",
								}
								table.insert(out, pane)
							end
						end
					end
				else
					for i = 1, bays do
						local c = -f.len / 2 + f.len * (i - 0.5) / bays
						local clear = true
						for _, g in gaps do
							-- 1.5 st clear of the opening: room for the door's jamb and head; and on the
							-- floor above, no window where the door's transom and hood stand
							local over = fl > 1 and g.top ~= nil and y - winH / 2 - 0.6 < g.top + 4.2
							if (fl == 1 or over) and math.abs(c - g.c) < g.w / 2 + style.winW / 2 + 1.5 then
								clear = false
							end
						end
						if clear then
							table.insert(out, {
								face = f.id,
								floor = fl,
								i = i,
								c = c,
								y = y,
								w = style.winW,
								h = winH,
								kind = "sash",
							})
						end
					end
				end
			end
		end
	end
	return out
end

-- The windows of `grid`: casing board, glass, glazing bars, sill or sill course, lintel, shutters,
-- flower boxes; display panes on a stall riser with a transom bar.
function Facade.windows(ctx: Spec.LotCtx, grid: { Win }, style: Style)
	local pal = look(ctx)
	local faces = Facade.faces(ctx)
	local knobs = Facade.KNOBS
	local idx = Palette.index(ctx.lot.id or "")
	local lit = 0
	local courses: { [string]: { y: number, face: string, floor: number } } = {}
	local courseOrder: { string } = {}
	for _, w in grid do
		local f = faces[w.face]
		local id = `{w.face}{w.floor}_{w.i}`
		local win: Spec.Opts = { role = "Window" }
		local glass: Spec.Opts = { role = "Window" }
		if style.glow and w.kind == "sash" and glows(ctx, w) then
			glass.attrs = { NightLight = true } :: Spec.Attrs
			lit += 1
		end
		if w.kind == "display" then
			board(ctx, f, "Frame" .. id, w.c, w.y, w.w + 0.8, w.h + 0.8, 0.12, pal.trim, nil, win)
			board(ctx, f, "Win" .. id, w.c, w.y, w.w, w.h, 0.18, pal.window, "Glass", glass, 0.02)
			local low = w.y - w.h / 2 - 0.4
			if low - 1.2 > 0.2 then
				-- the stall riser, from the plinth top to the pane
				board(ctx, f, "Stall" .. id, w.c, (low + 1.2) / 2, w.w + 0.8, low - 1.2, 0.28, pal.accent)
			end
			board(ctx, f, "Transom" .. id, w.c, w.y + w.h * 0.27, w.w, 0.22, 0.32, pal.trim)
			if w.w > 5 then
				board(ctx, f, "Mull" .. id, w.c, w.y, 0.2, w.h, 0.26, pal.trim)
			end
		else
			board(ctx, f, "Frame" .. id, w.c, w.y, w.w + 0.7, w.h + 0.7, 0.12, pal.trim, nil, win)
			board(ctx, f, "Win" .. id, w.c, w.y, w.w, w.h, 0.18, pal.window, "Glass", glass, 0.02)
			board(ctx, f, "Mull" .. id, w.c, w.y, 0.18, w.h, 0.3, pal.trim)
			if style.rail and (knobs.rails == "all" or (knobs.rails == "front" and w.face == "F")) then
				board(ctx, f, "Rail" .. id, w.c, w.y, w.w, 0.18, 0.24, pal.trim)
			end
			if style.courses and w.floor > 1 then
				local key = `{w.face}{w.floor}`
				if not courses[key] then
					courses[key] = { y = w.y - (w.h + 0.7) / 2 - 0.15, face = w.face, floor = w.floor }
					table.insert(courseOrder, key)
				end
			else
				board(ctx, f, "Sill" .. id, w.c, w.y - (w.h + 0.7) / 2 - 0.05, w.w + 1.3, 0.3, 0.5, pal.trim)
			end
			if style.lintel then
				board(ctx, f, "Head" .. id, w.c, w.y + (w.h + 0.7) / 2 + 0.12, w.w + 1.3, 0.55, 0.3, pal.trim)
			end
			if style.shutters and knobs.shutters and w.face == "F" then
				for k, s in { -1, 1 } do
					board(
						ctx,
						f,
						`Shutter{id}{if k == 1 then "a" else "b"}`,
						w.c + s * (w.w / 2 + 0.35 + 0.65),
						w.y,
						1.2,
						w.h + 0.5,
						0.16,
						pal.door
					)
				end
			end
			if style.flowerBoxes and knobs.flowerBoxes and w.face == "F" and w.floor == 2 then
				local by = w.y - (w.h + 0.7) / 2 - 0.6
				board(ctx, f, "FlowerBox" .. id, w.c, by, w.w + 0.6, 0.7, 0.95, Palette.OAK, "Wood")
				local t = 0.75
				local off = f.fixed + f.out * (0.5 + t / 2 - 0.3)
				local bloom = BLOOM[(idx + w.i) % #BLOOM + 1]
				if f.alongX then
					deco(ctx, "Blooms" .. id, w.c, by + 0.55, off, w.w + 0.2, 0.5, t, bloom, "LeafyGrass")
				else
					deco(ctx, "Blooms" .. id, off, by + 0.55, w.c, t, 0.5, w.w + 0.2, bloom, "LeafyGrass")
				end
			end
		end
	end
	for _, key in courseOrder do
		local c = courses[key]
		local f = faces[c.face]
		-- front and back run past the corners; the sides fit between them
		board(ctx, f, "Course" .. key, 0, c.y, if f.alongX then f.len + 0.5 else f.len, 0.36, 0.34, pal.trim)
	end
	if lit > 0 then
		Spec.bump(ctx.attributes, "NightLights", lit)
	end
end

-- A door's dressing: jambs and a head (with a glazed transom where the wall above allows), a knob and
-- two panels that swing with the leaf (attribute DoorOf, Doors.followers), steps down to the ground
-- where the sill stands above it, and on the main entrance the style's hood, porch, awning, flat canopy
-- or portico.
function Facade.entrance(ctx: Spec.LotCtx, d: Door, style: Style)
	local pal = look(ctx)
	local f = Facade.faces(ctx)[d.face]
	local top = d.y0 + d.h
	local P = math.max(0.25, d.proud + 0.1)
	local headTop = top
	if d.surround ~= false then
		local transom = style.transom and d.wallTop - top > 3.4
		local headY = top + (if transom then 1.8 else 0) + 0.3
		headTop = headY + 0.3
		for k, s in { -1, 1 } do
			board(
				ctx,
				f,
				`{d.name}_Jamb{k}`,
				d.c + s * (d.w / 2 + 0.3),
				(d.y0 + headY - 0.3) / 2,
				0.6,
				headY - 0.3 - d.y0,
				P,
				pal.trim
			)
		end
		board(ctx, f, d.name .. "_Head", d.c, headY, d.w + 2.0, 0.6, P + 0.08, pal.trim)
		if transom then
			board(ctx, f, d.name .. "_Light", d.c, top + 0.95, d.w, 1.3, 0.14, pal.window, "Glass", { role = "Window" })
			board(ctx, f, d.name .. "_Bar", d.c, top + 0.14, d.w, 0.28, P - 0.06, pal.trim)
		end
	end

	-- followers: they turn with the leaf when the server opens it
	if d.leaf ~= false then
		local follow: Spec.Attrs = { DoorOf = d.doorId }
		local hand = if f.alongX then 1 else -1 -- the leaf's free edge is its local +X
		if not d.slide then
			local kx, kz = outPoint(f, d.c + hand * (d.w / 2 - 0.7), d.proud + 0.1)
			deco(ctx, d.name .. "_Knob", kx, d.y0 + math.min(3.5, d.h * 0.42), kz, 0.44, 0.44, 0.44, BRASS, "Metal", {
				shape = "Ball",
				attrs = follow,
			})
		end
		local t = 0.1
		local px, pz = outPoint(f, d.c, d.proud + 0.06 - t / 2)
		local function panel(
			name: string,
			c: number,
			y: number,
			w: number,
			h: number,
			color: { number },
			material: string?
		)
			local ax, az = outPoint(f, c, d.proud + 0.06 - t / 2)
			if f.alongX then
				deco(ctx, name, ax, y, pz, w, h, t, color, material, { attrs = table.clone(follow) })
			else
				deco(ctx, name, px, y, az, t, h, w, color, material, { attrs = table.clone(follow) })
			end
		end
		if d.w > 10 then
			-- a wide entrance reads as a pair of glazed doors: a centre stile and two lights
			panel(d.name .. "_Stile", d.c, d.y0 + d.h / 2, 0.5, d.h - 0.3, pal.trim)
			for k, s in { -1, 1 } do
				panel(
					`{d.name}_Pane{k}`,
					d.c + s * d.w / 4,
					d.y0 + d.h * 0.58,
					d.w / 2 - 1.6,
					d.h * 0.6,
					pal.window,
					"Glass"
				)
			end
		else
			local inset = shade(pal.door, 0.82)
			panel(d.name .. "_PanelA", d.c, d.y0 + d.h * 0.27, d.w - 1.6, d.h * 0.34, inset, "Wood")
			panel(d.name .. "_PanelB", d.c, d.y0 + d.h * 0.72, d.w - 1.6, d.h * 0.36, inset, "Wood")
		end
	end

	-- steps down to the ground (collidable: they are the way in), or a flat threshold on level ground
	local RUN = 1.4
	local gx, gz = outPoint(f, d.c, 3)
	local g = ground(ctx, gx, gz)
	local drop = d.y0 - g
	local sw = d.w + (if d.surround == false then 6.0 else 2.4)
	if drop > 0.3 and drop <= 4.5 then
		local n = math.ceil(drop / 0.7)
		local rise = drop / n
		for k = 1, n do
			local topY = d.y0 - (k - 1) * rise
			-- (a building that draws its own entrance piers gets a deeper landing, past them)
			local land = if d.surround == false then 1.0 else 0
			local d0, d1 = if k == 1 then -0.04 else (k - 1) * RUN + land, k * RUN + land
			local ax, az = outPoint(f, d.c, d0)
			local bx, bz = outPoint(f, d.c, d1)
			local low = math.min(g, ground(ctx, ax, az), ground(ctx, bx, bz)) - 0.4
			local cx, cz = outPoint(f, d.c, (d0 + d1) / 2)
			local opts: Spec.Opts = { color = STEP, material = "Concrete", role = "Step", castShadow = false }
			local h = topY - low
			if f.alongX then
				ctx.list:add(ctx.frame, `{d.name}_Step{k}`, cx, low + h / 2, cz, sw, h, d1 - d0, opts)
			else
				ctx.list:add(ctx.frame, `{d.name}_Step{k}`, cx, low + h / 2, cz, d1 - d0, h, sw, opts)
			end
		end
		Spec.bump(ctx.attributes, "Steps", n)
	elseif drop >= -0.3 and drop <= 0.3 then
		local cx, cz = outPoint(f, d.c, 0.55)
		local y = math.max(d.y0, g) + 0.02
		if f.alongX then
			deco(ctx, d.name .. "_Threshold", cx, y, cz, d.w + 1.0, 0.2, 1.1, STEP, "Concrete")
		else
			deco(ctx, d.name .. "_Threshold", cx, y, cz, 1.1, 0.2, d.w + 1.0, STEP, "Concrete")
		end
	end

	if d.canopy ~= true or f.id ~= "F" then
		return
	end
	-- the main entrance's canopy (front face: outward is model-local -Z)
	local z0 = f.fixed
	local kind = style.canopy
	if kind == "hood" then
		local y = headTop + 0.55
		deco(ctx, "Hood", d.c, y, z0 - 1.37, d.w + 3.2, 0.3, 2.8, pal.roof, pal.roofMaterial, { castShadow = true })
		for k, s in { -1, 1 } do
			deco(ctx, `HoodBracket{k}`, d.c + s * (d.w / 2 + 1.0), y - 0.75, z0 - 1.05, 0.3, 1.2, 2.0, pal.trim)
		end
	elseif kind == "porch" then
		local pw = math.min(0.63 * ctx.W, math.max(d.w + 8, 14))
		local depth = 5.6
		local y = headTop + 1.1
		deco(
			ctx,
			"PorchRoof",
			d.c,
			y,
			z0 - depth / 2 + 0.1,
			pw,
			0.4,
			depth,
			pal.roof,
			pal.roofMaterial,
			{ pitch = -0.14, castShadow = true }
		)
		local beamY = y - 0.14 * (depth / 2 - 0.3) - 0.5
		deco(ctx, "PorchBeam", d.c, beamY, z0 - depth + 0.45, pw - 0.4, 0.5, 0.36, pal.trim)
		for k, s in { -1, 1 } do
			local px = d.c + s * (pw / 2 - 0.6)
			local pz = z0 - depth + 0.45
			local low = ground(ctx, px, pz) - 0.3
			deco(ctx, `PorchPost{k}`, px, (low + beamY - 0.25) / 2, pz, 0.5, beamY - 0.25 - low, 0.5, pal.trim)
		end
	elseif kind == "awning" and style.awning and d.wallTop >= 16 then
		-- (a low shop has no room for one between its door and its sign)
		local low = ctx.W < 28
		local y = top + (if low then 0.1 else 0.35)
		local h = if low then 0.9 else 1.4
		local aw = if ctx.W > 60 then math.max(d.w + 14, ctx.W * 0.36) else ctx.W - 2.4
		deco(ctx, "Awning", d.c, y + h / 2, z0 - 1.7 + 0.03, aw, h, 3.4, style.awning, "Fabric", {
			shape = "Wedge",
			castShadow = true,
		})
		deco(ctx, "Valance", d.c, y - 0.22, z0 - 3.4 + 0.09, aw, 0.5, 0.12, pal.trim, "Fabric")
	elseif kind == "flat" then
		local y = headTop + 0.7
		local cw = d.w + 6
		deco(ctx, "Canopy", d.c, y, z0 - 2.3 + 0.05, cw, 0.45, 4.6, pal.accent, "Metal", { castShadow = true })
		for k, s in { -1, 1 } do
			local px, pz = d.c + s * (cw / 2 - 0.5), z0 - 4.2
			local low = ground(ctx, px, pz) - 0.3
			deco(ctx, `CanopyPost{k}`, px, (low + y - 0.2) / 2, pz, 0.4, y - 0.2 - low, 0.4, GUTTER, "Metal")
		end
		if ctx.lot.type == "police_station" then
			for k, s in { -1, 1 } do
				board(
					ctx,
					f,
					`BlueLamp{k}`,
					d.c + s * (d.w / 2 + 1.9),
					d.y0 + d.h - 1.6,
					0.7,
					1.4,
					0.6,
					POLICE_BLUE,
					"Neon"
				)
			end
		end
	elseif kind == "portico" and style.columns > 0 then
		local depth = 6.0
		local topY = math.min(d.wallTop - 1.5, headTop + 5.5)
		local half = d.w / 2 + 2.2 + (style.columns / 2 - 1) * 5
		local n = style.columns
		for k = 1, n do
			local t = if n > 1 then (k - 1) / (n - 1) else 0.5
			local px = d.c - half + 2 * half * t
			local pz = z0 - depth + 1.2
			local low = ground(ctx, px, pz) - 0.3
			local h = topY - 0.6 - low
			deco(ctx, `Column{k}`, px, low + h / 2, pz, h, 1.6, 1.6, pal.trim, "Concrete", {
				shape = "Cylinder",
				roll = math.pi / 2,
			})
		end
		deco(ctx, "PorticoSlab", d.c, topY, z0 - depth / 2 + 0.05, 2 * half + 3, 1.2, depth, pal.trim, "Concrete", {
			castShadow = true,
		})
		if n >= 4 then
			-- a low pediment over the slab: two wedges rising to the centre
			local ph, hw = 2.6, half + 1.5
			for k, s in { -1, 1 } do
				deco(
					ctx,
					`Pediment{k}`,
					d.c + s * hw / 2,
					topY + 0.6 + ph / 2,
					z0 - depth / 2 + 0.05,
					depth - 0.6,
					ph,
					hw,
					pal.trim,
					"Concrete",
					{
						shape = "Wedge",
						yaw = if s < 0 then math.pi / 2 else -math.pi / 2,
					}
				)
			end
		end
	end
end

-- The two roof plates of a gable (top faces meet at the peak): Building.roof draws exactly these, and
-- roofTrim continues them. `side` -1 is plate A, +1 plate B (across the ridge).
function Facade.roofSides(ctx: Spec.LotCtx, eave: number, peak: number, alongLocalX: boolean): { RoofSide }
	local W, D = ctx.W, ctx.D
	local span = if alongLocalX then D else W -- horizontal run from eave to eave
	local length = if alongLocalX then W else D -- along the ridge
	local rise = peak - eave
	local half = span / 2
	local slope = math.sqrt(half * half + rise * rise)
	local phi = math.atan2(rise, half)
	local out: { RoofSide } = {}
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
		table.insert(out, {
			name = if side < 0 then "RoofA" else "RoofB",
			side = side,
			mx = mx,
			mz = mz,
			cy = cy,
			yaw = yaw,
			pitch = pitch,
			phi = phi,
			slope = slope,
			length = length,
			half = half,
			nx = nx,
			ny = ny,
		})
	end
	return out
end

-- Eaves, rakes, fascia and barge boards, a ridge cap and gutters around the two plates. The plates
-- themselves are untouched: the strips continue their planes outward in the plates' own colour.
function Facade.roofTrim(
	ctx: Spec.LotCtx,
	sides: { RoofSide },
	eave: number,
	peak: number,
	alongLocalX: boolean,
	style: Style
)
	local pal = look(ctx)
	local oh, g = style.overhang, style.rake
	local rise = peak - eave
	if rise <= 0.05 then
		return
	end
	local gutter = if pal.timber then COPPER else GUTTER
	-- (along the ridge, across it) -> model-local (mx, mz)
	local function at(along: number, across: number): (number, number)
		if alongLocalX then
			return along, across
		end
		return across, along
	end
	for _, s in sides do
		local tag = if s.side < 0 then "A" else "B"
		local cosP, sinP, tanP = math.cos(s.phi), math.sin(s.phi), math.tan(s.phi)
		local e = oh / cosP -- slope length of the eave overhang
		local roofOpts = function(): Spec.Opts
			return { yaw = s.yaw, pitch = s.pitch, castShadow = true, role = "Trim" }
		end
		-- the eave strip: from the plate's low edge down and out
		local ea, ey =
			s.side * s.half + s.nx * PLATE / 2 + s.side * cosP * e / 2, eave + s.ny * PLATE / 2 - sinP * e / 2
		local mx, mz = at(0, ea)
		deco(ctx, "Eave" .. tag, mx, ey, mz, s.length, PLATE, e, pal.roof, pal.roofMaterial, roofOpts())
		-- the rakes: the whole slope, eave overhang included, past each gable end
		local ra = s.side * s.half / 2 + s.nx * PLATE / 2 + s.side * cosP * e / 2
		local ry = eave + rise / 2 + s.ny * PLATE / 2 - sinP * e / 2
		for k, endSign in { -1, 1 } do
			local along = endSign * (s.length / 2 + g / 2)
			mx, mz = at(along, ra)
			deco(ctx, `Rake{tag}{k}`, mx, ry, mz, g, PLATE, s.slope + e, pal.roof, pal.roofMaterial, roofOpts())
			if Facade.KNOBS.barge then
				-- the barge board hangs under the rake's outer edge
				local bAlong = endSign * (s.length / 2 + g - 0.16)
				mx, mz = at(bAlong, ra - s.nx * 0.5)
				deco(
					ctx,
					`Barge{tag}{k}`,
					mx,
					ry - s.ny * 0.5,
					mz,
					0.22,
					0.8,
					s.slope + e - 0.1,
					pal.trim,
					nil,
					{ yaw = s.yaw, pitch = s.pitch }
				)
			end
		end
		-- fascia under the eave's lip, and the gutter on it
		local lipY = eave - oh * tanP
		local full = s.length + 2 * g
		local fa = s.side * (s.half + oh - 0.14)
		mx, mz = at(0, fa)
		if alongLocalX then
			deco(ctx, "Fascia" .. tag, mx, lipY - 0.3, mz, full - 0.5, 0.8, 0.2, pal.trim)
		else
			deco(ctx, "Fascia" .. tag, mx, lipY - 0.3, mz, 0.2, 0.8, full - 0.5, pal.trim)
		end
		mx, mz = at(0, s.side * (s.half + oh + 0.22))
		deco(ctx, "Gutter" .. tag, mx, lipY - 0.2, mz, full, 0.5, 0.5, gutter, "Metal", {
			shape = "Cylinder",
			yaw = if alongLocalX then 0 else math.pi / 2,
			role = "Gutter",
		})
	end
	local full = sides[1].length + 2 * g
	local cap = shade(pal.roof, 0.82)
	if alongLocalX then
		deco(ctx, "RidgeCap", 0, peak + 0.1, 0, full, 0.3, 0.9, cap, pal.roofMaterial)
	else
		deco(ctx, "RidgeCap", 0, peak + 0.1, 0, 0.9, 0.3, full, cap, pal.roofMaterial)
	end
	ctx.attributes.Eaves = oh
end

-- A flat roof: a deck in the roof's colour over the body's top (`roofDeck`), a low parapet in the wall
-- material and a coping on it.
function Facade.flatRoof(ctx: Spec.LotCtx, top: number, style: Style, roofDeck: boolean)
	local pal = look(ctx)
	local W, D = ctx.W, ctx.D
	local pt, ph = 0.5, 1.2
	if roofDeck then
		deco(ctx, "Deck", 0, top + 0.06, 0, W - 2 * pt, 0.12, D - 2 * pt, pal.roof, pal.roofMaterial)
	end
	local y = top + ph / 2
	deco(ctx, "ParapetF", 0, y, -D / 2 + pt / 2, W, ph, pt, pal.wall, pal.material)
	deco(ctx, "ParapetB", 0, y, D / 2 - pt / 2, W, ph, pt, pal.wall, pal.material)
	deco(ctx, "ParapetL", -W / 2 + pt / 2, y, 0, pt, ph, D - 2 * pt, pal.wall, pal.material)
	deco(ctx, "ParapetR", W / 2 - pt / 2, y, 0, pt, ph, D - 2 * pt, pal.wall, pal.material)
	local cy = top + ph + 0.125
	local c = if style.kind == "shopfront" then pal.accent else pal.trim
	deco(ctx, "CopingF", 0, cy, -D / 2 + pt / 2 - 0.02, W + 0.4, 0.25, pt + 0.36, c)
	deco(ctx, "CopingB", 0, cy, D / 2 - pt / 2 + 0.02, W + 0.4, 0.25, pt + 0.36, c)
	deco(ctx, "CopingL", -W / 2 + pt / 2 - 0.02, cy, 0, pt + 0.36, 0.25, D - 2 * pt - 0.4, c)
	deco(ctx, "CopingR", W / 2 - pt / 2 + 0.02, cy, 0, pt + 0.36, 0.25, D - 2 * pt - 0.4, c)
end

-- Corner dressing from `base` (the plinth top, or the floor) to the eave: boards on timber-clad houses,
-- alternating quoins on brick and stone, pilasters with a cap on civic and commercial blocks.
function Facade.corners(ctx: Spec.LotCtx, eave: number, style: Style, base: number)
	local pal = look(ctx)
	local W, D = ctx.W, ctx.D
	local h = eave - base
	if h < 3 then
		return
	end
	local n = 0
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			n += 1
			if style.corners == "boards" then
				deco(ctx, `CornerBoard{n}`, sx * (W / 2 - 0.1), base + h / 2, sz * (D / 2 - 0.1), 0.5, h, 0.5, pal.trim)
			elseif style.corners == "pilasters" then
				deco(ctx, `Pilaster{n}`, sx * (W / 2 - 0.4), base + h / 2, sz * (D / 2 - 0.4), 1.4, h, 1.4, pal.trim)
			elseif style.corners == "quoins" then
				local count = math.clamp(math.floor(h / 2.6), 3, Facade.KNOBS.quoinsPerCorner)
				local pitch = h / count
				for k = 1, count do
					local a, b = 1.7, 1.0
					if k % 2 == 0 then
						a, b = b, a
					end
					deco(
						ctx,
						`Quoin{n}_{k}`,
						sx * (W / 2 + 0.14 - a / 2),
						base + (k - 0.5) * pitch,
						sz * (D / 2 + 0.14 - b / 2),
						a,
						pitch * 0.62,
						b,
						pal.trim,
						"Concrete"
					)
				end
			end
		end
	end
end

-- Quay half-timber beyond the bands and front posts Building.dress keeps: four back posts, two diagonal
-- braces on each long side, and a jetty beam under the upper storey (v5.4: a jettied upper storey; the
-- massing stays one box, so the jetty is a beam on the mid band).
function Facade.timber(ctx: Spec.LotCtx, eave: number)
	local W, D = ctx.W, ctx.D
	local OAK = Palette.OAK
	for i, x in { -W / 2, -W / 6, W / 6, W / 2 } do
		deco(ctx, `PostB{i}`, x, (eave + 1.2) / 2, D / 2 + 0.09, 0.45, eave - 1.2, 0.38, OAK, "Wood")
	end
	local mid = eave * 0.51
	-- braces: from the corner post at the mid band up to the top band, leaning inward (upper storey)
	-- (short and steep, inside the corner panel: clear of the outer window column at W / 3)
	local run, rise = math.max(W / 6 - 2.7, 2), math.min(eave - 1.4 - mid, 8)
	local len = math.sqrt(run * run + rise * rise)
	local ang = math.atan2(rise, run)
	local n = 0
	for _, face in { -1, 1 } do
		for _, s in { -1, 1 } do
			n += 1
			-- roll turns the brace about the face's normal; on the back face the same lean mirrors
			deco(
				ctx,
				`Brace{n}`,
				s * (W / 2 - 0.3 - run / 2),
				mid + 0.7 + rise / 2,
				face * (D / 2 + 0.06),
				len,
				0.36,
				0.22,
				OAK,
				"Wood",
				{ roll = -s * ang }
			)
		end
	end
	-- the bressummer of the upper storey, on the mid band
	deco(ctx, "Jetty", 0, mid + 0.45, -D / 2 - 0.2, W + 0.5, 0.5, 0.5, OAK, "Wood")
end

-- A cap wider than the stack and its pots.
function Facade.chimneyCap(ctx: Spec.LotCtx, x: number, z: number, top: number, size: number, pots: number)
	deco(ctx, "StackCap", x, top + 0.18, z, size + 0.7, 0.36, size + 0.7, CAP, "Concrete")
	for k = 1, pots do
		local off = if pots == 1 then 0 else (k - 1.5) * 1.0
		deco(ctx, `StackPot{k}`, x + off, top + 0.36 + 0.5, z, 1.0, 0.7, 0.7, POT, "Concrete", {
			shape = "Cylinder",
			roll = math.pi / 2,
		})
	end
end

-- The fascia band a shop sign sits on, across the front at height `y`.
function Facade.band(ctx: Spec.LotCtx, y: number, style: Style)
	local pal = look(ctx)
	local f = Facade.faces(ctx).F
	local h = if ctx.W < 28 then 2.6 else 3.0
	local color = if pal.timber then Palette.OAK else pal.accent
	board(
		ctx,
		f,
		"Band",
		0,
		y,
		ctx.W - (if pal.timber then 0.6 else 0.2),
		h,
		0.36,
		color,
		if pal.timber then "Wood" else nil
	)
	if style.kind == "shopfront" then
		board(ctx, f, "BandCap", 0, y + h / 2 + 0.14, ctx.W + 0.3, 0.28, 0.46, pal.trim)
	end
end

-- Joins every drawn downspout (route props of category "pipe" with a Shoe) to the gutter of the gabled
-- lot it stands by: where the pipe's shaft does not already pass through the gutter, a short neck runs
-- from the shaft to the nearest point of the gutter (some harvested pipes rise past the eave). Added to the lot's plan (visual only), so nothing a
-- route, a lamp or the Skyline depends on changes. Returns the number of downspouts joined.
function Facade.downspouts(lotPlans: { Spec.BuildPlan }, propPlans: { Spec.BuildPlan }): number
	type GutterLine = { plan: Spec.BuildPlan, a: { number }, b: { number }, color: { number } }
	local gutters: { GutterLine } = {}
	for _, p in lotPlans do
		for _, s in p.parts do
			if s.role == "Gutter" then
				local ax = Geometry.rotate({ s.sx / 2, 0, 0 }, s.yaw, s.pitch, s.roll or 0)
				table.insert(gutters, {
					plan = p,
					a = { s.cx - ax[1], s.cy - ax[2], s.cz - ax[3] },
					b = { s.cx + ax[1], s.cy + ax[2], s.cz + ax[3] },
					color = s.color,
				})
			end
		end
	end
	-- the point of segment a-b nearest p
	local function nearest(a: { number }, b: { number }, p: { number }): { number }
		local abx, aby, abz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
		local len2 = abx * abx + aby * aby + abz * abz
		local t = if len2 > 0
			then math.clamp(((p[1] - a[1]) * abx + (p[2] - a[2]) * aby + (p[3] - a[3]) * abz) / len2, 0, 1)
			else 0
		return { a[1] + abx * t, a[2] + aby * t, a[3] + abz * t }
	end
	local joined = 0
	for _, pp in propPlans do
		local shoe = false
		local top: { number }? = nil
		local low: { number }? = nil
		if pp.category == "pipe" then
			for _, s in pp.parts do
				if s.name == "Shoe" then
					shoe = true
				elseif string.sub(s.name, 1, 4) == "Pipe" and s.name ~= "PipeFoot" then
					local ax = Geometry.rotate({ s.sx / 2, 0, 0 }, s.yaw, s.pitch, s.roll or 0)
					for _, e in { -1, 1 } do
						local q = { s.cx + e * ax[1], s.cy + e * ax[2], s.cz + e * ax[3] }
						if top == nil or q[2] > top[2] then
							top = q
						end
						if low == nil or q[2] < low[2] then
							low = q
						end
					end
				end
			end
		end
		if shoe and top and low then
			-- the closest approach of the pipe's shaft to any gutter (the gutter sampled every 0.25 st)
			local best: GutterLine? = nil
			local bestD = Facade.NECK_REACH
			local onGutter, onPipe = top, top
			for _, gl in gutters do
				if Geometry.segmentDistance(gl.a, gl.b, top) < 40 then
					local len = math.sqrt((gl.b[1] - gl.a[1]) ^ 2 + (gl.b[2] - gl.a[2]) ^ 2 + (gl.b[3] - gl.a[3]) ^ 2)
					local n = math.max(1, math.ceil(len / 0.25))
					for i = 0, n do
						local f = i / n
						local q = {
							gl.a[1] + (gl.b[1] - gl.a[1]) * f,
							gl.a[2] + (gl.b[2] - gl.a[2]) * f,
							gl.a[3] + (gl.b[3] - gl.a[3]) * f,
						}
						local d = Geometry.segmentDistance(low, top, q)
						if d < bestD then
							best, bestD, onGutter, onPipe = gl, d, q, nearest(low, top, q)
						end
					end
				end
			end
			if best then
				joined += 1
				-- beside the shaft the pipe already runs through the gutter; otherwise a neck joins them
				if bestD > 0.5 then
					local dvec = { onGutter[1] - onPipe[1], onGutter[2] - onPipe[2], onGutter[3] - onPipe[3] }
					local yaw, roll = Geometry.axisAngles(dvec)
					table.insert(best.plan.parts, {
						name = "GutterNeck_" .. tostring(pp.attributes.Route),
						cx = (onPipe[1] + onGutter[1]) / 2,
						cy = (onPipe[2] + onGutter[2]) / 2,
						cz = (onPipe[3] + onGutter[3]) / 2,
						yaw = yaw,
						pitch = 0,
						roll = roll,
						sx = bestD + 0.3,
						sy = 0.4,
						sz = 0.4,
						color = best.color,
						material = "Metal",
						canCollide = false,
						canQuery = false,
						castShadow = false,
						transparency = 0,
						shape = "Cylinder",
						role = "Gutter",
						attrs = { Route = pp.attributes.Route :: number } :: Spec.Attrs,
					})
				end
			end
		end
	end
	return joined
end

return Facade
