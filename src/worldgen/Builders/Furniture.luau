--!strict
-- ServerScriptService.Server.WorldGen.Builders.Furniture
-- The furniture library of the interiors art pass (owner 2026-11-10: "make ... interiors of houses much
-- nicer"): a small set of well-proportioned, multi-part pieces at human scale (a person stands 5.5 st:
-- seats 1.5, tables 2.5, counters 3, a door 8.75), with cylinders and balls where a round part helps
-- (legs, lamp stems and shades, stools, bowls, pots, knobs). Builders/Furnish chooses and places them.
--
-- A piece is pure data in its own frame: x across its width, y up from the floor, z from its front
-- (-d/2) to its back (+d/2, the side that stands against a wall). The first part is the root: it takes
-- the placed name and the attributes (Kit, Room ...) and, when the piece is `solid`, the collision; every
-- other part is named <name>_<suffix>, never collides and takes no queries, except the few marked solid
-- (the bars of a cell). So a body is stopped by the bulk of a sofa, a bed or a counter and by a table's
-- top, and walks past chairs, lamps, rugs, curtains and pictures.
--
-- Interface:
--   KINDS                                     every kind name
--   TONES                                     colour sets (four homes, hospital, police)
--   piece(kind, tones, opts?) -> Piece        opts: { w = width (counter, rug), seats, variant }
--   emit(list, frame, name, piece, x, z, turns, floorY, attrs?, role?) -> root PartSpec
--        turns: quarter turns; 0 puts the piece's back toward model-local +Z, 1 toward +X, 2 -Z, 3 -X
--   footprint(piece, turns) -> (sizeX, sizeZ) in model-local axes
--   backDir(turns) -> (dx, dz)                the direction the piece's back looks
--   dress(kind, tones, opts?) -> { PartDef }  detail parts around an existing Station or Shelf part
--   emitDress(list, frame, name, parts, x, z, turns, floorY)
-- Pure: no Instances, no state.

local Geometry = require("../Geometry")
local Spec = require("../Spec")

local Furniture = {}

export type Rgb = { number }
export type Tones = {
	wood: Rgb,
	woodDark: Rgb,
	fabric: Rgb,
	fabricDark: Rgb,
	cushion: Rgb,
	rug: Rgb,
	accent: Rgb,
	metal: Rgb,
	white: Rgb,
	stone: Rgb,
	cabinet: Rgb,
	curtain: Rgb,
}
export type PartDef = {
	n: string,
	x: number,
	y: number, -- centre above the floor
	z: number,
	sx: number,
	sy: number,
	sz: number,
	c: Rgb,
	m: string,
	shape: string?,
	roll: number?,
	yaw: number?,
	solid: boolean?, -- collides although it is not the root
	hidden: boolean?, -- an invisible collider
}
export type Piece = {
	kind: string,
	w: number,
	d: number,
	h: number,
	clear: number, -- free floor wanted in front
	solid: boolean, -- the root collides
	mounted: number?, -- hangs on the wall: the height of its lowest edge
	parts: { PartDef },
	attrs: Spec.Attrs?,
}

local HALF_PI = math.pi / 2

local BLACK = { 38, 42, 44 }
local STEEL = { 168, 174, 178 }
local BRASS = { 182, 154, 83 }
local CREAM = { 238, 228, 204 }
local TERRACOTTA = { 176, 112, 84 }
local LEAF = { 96, 130, 78 }
local WATER = { 150, 200, 210 }
local CORK = { 184, 148, 104 }
local PAPER = { 240, 236, 222 }
local RED = { 196, 72, 64 }
local BOOKS = { { 156, 101, 77 }, { 100, 135, 107 }, { 71, 123, 136 }, { 186, 127, 135 }, { 233, 190, 78 } }
local GOODS = { { 188, 128, 93 }, { 234, 219, 189 }, { 100, 135, 107 }, { 209, 215, 206 } }
local ART = { { 118, 147, 119 }, { 99, 140, 160 }, { 214, 168, 120 }, { 150, 120, 150 }, { 224, 204, 150 } }

local function tone(
	wood: string,
	woodDark: string,
	fabric: string,
	fabricDark: string,
	cushion: string,
	rug: string,
	accent: string,
	curtain: string
): Tones
	local function hex(s: string): Rgb
		return {
			tonumber(string.sub(s, 1, 2), 16) :: number,
			tonumber(string.sub(s, 3, 4), 16) :: number,
			tonumber(string.sub(s, 5, 6), 16) :: number,
		}
	end
	return {
		wood = hex(wood),
		woodDark = hex(woodDark),
		fabric = hex(fabric),
		fabricDark = hex(fabricDark),
		cushion = hex(cushion),
		rug = hex(rug),
		accent = hex(accent),
		metal = { 112, 118, 122 },
		white = { 238, 234, 224 },
		stone = { 198, 192, 180 },
		cabinet = { 228, 222, 206 },
		curtain = hex(curtain),
	}
end

-- Muted and earthy like the town (worldgen_districts_art §11): one set per home, so no two houses match.
Furniture.TONES = {
	victorian = tone("82634b", "5b4239", "8a5a52", "6e4742", "d8c6a1", "9c654d", "405b51", "b9a17e"),
	bungalow = tone("b08961", "806147", "7d9a7a", "64876b", "eadbbd", "a3835b", "597e77", "d7b399"),
	brick = tone("9a7352", "6e5144", "5b7186", "486d88", "dfd6ba", "745547", "bb8e71", "c9bda7"),
	cottage = tone("c4a57c", "a3835b", "8fa7b3", "6f8c9a", "f4e8cf", "aebbc4", "b26d52", "f2ecdf"),
	hospital = tone("d9d4c6", "a5ada9", "6ca99e", "628e9d", "e5eee9", "b9c4ba", "628e9d", "cfe0d6"),
	police = tone("8a7458", "5e5044", "4e6a7a", "344852", "c9cfd2", "5d6b65", "344852", "8a989e"),
} :: { [string]: Tones }

type Builder = {
	parts: { PartDef },
	box: (
		n: string,
		x: number,
		y0: number,
		z: number,
		sx: number,
		sy: number,
		sz: number,
		c: Rgb,
		m: string?
	) -> PartDef,
	cyl: (n: string, x: number, y0: number, z: number, dia: number, h: number, c: Rgb, m: string?) -> PartDef,
	rodX: (n: string, x: number, y: number, z: number, len: number, dia: number, c: Rgb, m: string?) -> PartDef,
	rodZ: (n: string, x: number, y: number, z: number, len: number, dia: number, c: Rgb, m: string?) -> PartDef,
	ball: (n: string, x: number, y0: number, z: number, dia: number, c: Rgb, m: string?) -> PartDef,
}

-- Part helpers: y0 is the part's bottom above the floor.
local function builder(): Builder
	local parts: { PartDef } = {}
	local function push(p: PartDef): PartDef
		table.insert(parts, p)
		return p
	end
	return {
		parts = parts,
		box = function(n, x, y0, z, sx, sy, sz, c, m)
			return push({
				n = n,
				x = x,
				y = y0 + sy / 2,
				z = z,
				sx = sx,
				sy = sy,
				sz = sz,
				c = c,
				m = m or "SmoothPlastic",
			})
		end,
		-- an upright cylinder (legs, stems, shades, bowls, pots)
		cyl = function(n, x, y0, z, dia, h, c, m)
			return push({
				n = n,
				x = x,
				y = y0 + h / 2,
				z = z,
				sx = h,
				sy = dia,
				sz = dia,
				c = c,
				m = m or "SmoothPlastic",
				shape = "Cylinder",
				roll = HALF_PI,
			})
		end,
		-- a lying cylinder along the piece's width
		rodX = function(n, x, y, z, len, dia, c, m)
			return push({
				n = n,
				x = x,
				y = y,
				z = z,
				sx = len,
				sy = dia,
				sz = dia,
				c = c,
				m = m or "Metal",
				shape = "Cylinder",
			})
		end,
		-- a lying cylinder along the piece's depth
		rodZ = function(n, x, y, z, len, dia, c, m)
			return push({
				n = n,
				x = x,
				y = y,
				z = z,
				sx = len,
				sy = dia,
				sz = dia,
				c = c,
				m = m or "Metal",
				shape = "Cylinder",
				yaw = HALF_PI,
			})
		end,
		ball = function(n, x, y0, z, dia, c, m)
			return push({
				n = n,
				x = x,
				y = y0 + dia / 2,
				z = z,
				sx = dia,
				sy = dia,
				sz = dia,
				c = c,
				m = m or "SmoothPlastic",
				shape = "Ball",
			})
		end,
	}
end

local function shade(c: Rgb, k: number): Rgb
	return {
		math.clamp(math.floor(c[1] * k + 0.5), 0, 255),
		math.clamp(math.floor(c[2] * k + 0.5), 0, 255),
		math.clamp(math.floor(c[3] * k + 0.5), 0, 255),
	}
end

-- A chair: seat on an inset base, and a back on the side `face` (-1: back toward -z, +1: toward +z;
-- "x" variants turn it to face along the width). Three parts.
local function chair(b: Builder, tag: string, x: number, z: number, face: number, alongX: boolean, T: Tones)
	b.box("Chair" .. tag .. "Base", x, 0, z, 1.2, 1.25, 1.2, T.woodDark, "Wood")
	b.box("Chair" .. tag .. "Seat", x, 1.25, z, 1.6, 0.25, 1.6, T.fabric, "Fabric")
	if alongX then
		b.box("Chair" .. tag .. "Back", x + face * 0.69, 1.5, z, 0.2, 1.9, 1.5, T.wood, "Wood")
	else
		b.box("Chair" .. tag .. "Back", x, 1.5, z + face * 0.69, 1.5, 1.9, 0.2, T.wood, "Wood")
	end
end

type Opts = { w: number?, seats: number?, variant: number? }

local MAKERS: { [string]: (T: Tones, o: Opts) -> Piece } = {}

local function piece(kind: string, w: number, d: number, h: number, clear: number, solid: boolean, b: Builder): Piece
	return { kind = kind, w = w, d = d, h = h, clear = clear, solid = solid, parts = b.parts }
end

MAKERS.sofa = function(T, _o)
	local b = builder()
	b.box("", 0, 0, 0, 7.6, 1.45, 3.2, T.fabric, "Fabric")
	b.box("Back", 0, 1.45, 1.22, 7.5, 1.55, 0.7, T.fabricDark, "Fabric")
	for k, s in { -1, 1 } do
		b.box(`Arm{k}`, s * 3.42, 1.45, -0.02, 0.75, 0.8, 3.1, T.fabricDark, "Fabric")
		b.box(`Cushion{k}`, s * 1.5, 1.45, -0.35, 2.9, 0.4, 2.3, T.cushion, "Fabric")
	end
	return piece("sofa", 7.6, 3.2, 3.0, 2.2, true, b)
end

MAKERS.armchair = function(T, _o)
	local b = builder()
	b.box("", 0, 0, 0, 3.6, 1.45, 3.2, T.fabricDark, "Fabric")
	b.box("Back", 0, 1.45, 1.22, 3.5, 1.55, 0.7, T.fabric, "Fabric")
	for k, s in { -1, 1 } do
		b.box(`Arm{k}`, s * 1.45, 1.45, -0.02, 0.65, 0.8, 3.1, T.fabric, "Fabric")
	end
	b.box("Cushion", 0, 1.45, -0.35, 2.2, 0.4, 2.3, T.cushion, "Fabric")
	return piece("armchair", 3.6, 3.2, 3.0, 2.0, true, b)
end

MAKERS.coffee_table = function(T, _o)
	local b = builder()
	b.box("", 0, 1.2, 0, 4.2, 0.25, 2.2, T.wood, "Wood")
	local k = 0
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			k += 1
			b.cyl(`Leg{k}`, sx * 1.8, 0, sz * 0.8, 0.28, 1.2, T.woodDark, "Wood")
		end
	end
	return piece("coffee_table", 4.2, 2.2, 1.45, 0, true, b)
end

MAKERS.rug = function(T, o)
	local b = builder()
	local w = o.w or 9
	local d = math.max(4, w * 0.66)
	b.box("", 0, 0.05, 0, w, 0.06, d, T.rug, "Carpet")
	b.box("Field", 0, 0.11, 0, w - 1.2, 0.03, d - 1.2, shade(T.rug, 1.18), "Carpet")
	return piece("rug", w, d, 0.15, 0, false, b)
end

MAKERS.tv_stand = function(T, _o)
	local b = builder()
	b.box("", 0, 0, 0, 6.2, 1.9, 1.7, T.wood, "Wood")
	for k, s in { -1, 1 } do
		b.box(`Door{k}`, s * 1.5, 0.25, -0.86, 2.6, 1.4, 0.08, T.woodDark, "Wood")
	end
	b.box("Neck", 0, 1.9, 0.2, 1.2, 0.3, 0.6, BLACK, "Metal")
	b.box("Screen", 0, 2.2, 0.25, 5.2, 3.0, 0.22, BLACK, "Glass")
	return piece("tv_stand", 6.2, 1.7, 5.2, 2.5, true, b)
end

MAKERS.sideboard = function(T, _o)
	local b = builder()
	b.box("", 0, 0, 0, 6.2, 2.6, 1.7, T.wood, "Wood")
	for k = 1, 3 do
		b.box(`Door{k}`, (k - 2) * 2.0, 0.3, -0.86, 1.8, 2.0, 0.08, T.woodDark, "Wood")
	end
	b.cyl("Vase", -1.8, 2.6, 0, 0.7, 1.3, T.accent)
	b.ball("Bloom", -1.8, 3.7, 0, 1.1, LEAF, "LeafyGrass")
	return piece("sideboard", 6.2, 1.7, 4.8, 1.5, true, b)
end

MAKERS.bookshelf = function(T, o)
	local b = builder()
	b.box("", 0, 0, 0, 4.4, 7.2, 1.3, T.woodDark, "Wood")
	local v = o.variant or 0
	for k = 1, 4 do
		b.box(`Books{k}`, 0, 0.45 + (k - 1) * 1.7, -0.36, 3.9, 1.25, 0.7, BOOKS[(k + v) % #BOOKS + 1])
	end
	return piece("bookshelf", 4.4, 1.3, 7.2, 1.8, true, b)
end

MAKERS.floor_lamp = function(T, _o)
	local b = builder()
	b.cyl("", 0, 0, 0, 1.1, 0.15, T.metal, "Metal")
	b.cyl("Stem", 0, 0.15, 0, 0.16, 4.9, T.metal, "Metal")
	b.cyl("Shade", 0, 5.05, 0, 1.5, 1.2, CREAM, "Fabric")
	return piece("floor_lamp", 1.5, 1.5, 6.25, 0, false, b)
end

MAKERS.plant = function(_T, o)
	local b = builder()
	b.cyl("", 0, 0, 0, 1.3, 1.2, TERRACOTTA)
	if (o.variant or 0) % 2 == 1 then
		b.cyl("Trunk", 0, 1.2, 0, 0.2, 1.6, { 101, 83, 66 }, "Wood")
		b.ball("Leaves", 0, 2.5, 0, 2.4, LEAF, "LeafyGrass")
		return piece("plant", 2.4, 2.4, 4.9, 0, false, b)
	end
	b.ball("Leaves", 0, 1.0, 0, 2.2, LEAF, "LeafyGrass")
	return piece("plant", 2.2, 2.2, 3.2, 0, false, b)
end

MAKERS.picture = function(T, o)
	local b = builder()
	local v = o.variant or 0
	local w, h = 3.2, 2.4
	if v % 3 == 1 then
		w, h = 2.2, 2.8
	end
	b.box("", 0, 5.0, 0.04, w, h, 0.12, T.woodDark, "Wood")
	b.box("Canvas", 0, 5.2, -0.01, w - 0.4, h - 0.4, 0.1, ART[v % #ART + 1])
	local p = piece("picture", w, 0.2, 5.0 + h, 0, false, b)
	p.mounted = 5.0
	return p
end

MAKERS.counter_run = function(T, o)
	local b = builder()
	local w = o.w or 10
	b.box("", 0, 0, 0.05, w, 2.8, 2.0, T.cabinet, "Wood")
	b.box("Top", 0, 2.8, 0, w + 0.1, 0.22, 2.2, T.stone, "Granite")
	b.box("Fronts", 0, 0.35, -0.98, w - 0.3, 2.2, 0.06, shade(T.cabinet, 0.9), "Wood")
	b.box("Sink", -w / 4, 3.02, -0.1, 2.2, 0.06, 1.4, STEEL, "Metal")
	b.cyl("Tap", -w / 4, 3.02, 0.72, 0.2, 0.8, STEEL, "Metal")
	b.box("Hob", w / 4, 3.02, -0.1, 2.4, 0.05, 1.6, BLACK, "Glass")
	local h = 3.9
	if (o.variant or 0) ~= 1 then
		-- wall cupboards over the run (left off where the run stands under a window)
		b.box("Uppers", 0, 5.7, 0.5, w, 2.5, 1.1, T.cabinet, "Wood")
		h = 8.2
	end
	local p = piece("counter_run", w, 2.2, h, 2.4, true, b)
	p.attrs = { Sink = true, Hob = true } :: Spec.Attrs
	return p
end

MAKERS.fridge = function(T, _o)
	local b = builder()
	b.box("", 0, 0, 0.15, 2.6, 6.4, 2.4, T.white, "Metal")
	b.box("Seam", 0, 4.2, -1.06, 2.5, 0.08, 0.04, T.metal, "Metal")
	b.cyl("Handle", 0.95, 1.2, -1.15, 0.14, 2.6, STEEL, "Metal")
	return piece("fridge", 2.6, 2.7, 6.4, 2.2, true, b)
end

MAKERS.dining_set = function(T, o)
	local b = builder()
	local seats = o.seats or 4
	b.box("", 0, 2.25, 0, 6.4, 0.28, 3.6, T.wood, "Wood")
	for k, s in { -1, 1 } do
		b.box(`Trestle{k}`, s * 2.4, 0, 0, 0.5, 2.25, 2.6, T.woodDark, "Wood")
	end
	local n = 0
	for _, sz in { -1, 1 } do
		for _, sx in { -1, 1 } do
			n += 1
			chair(b, tostring(n), sx * 1.5, sz * 2.75, sz, false, T)
		end
	end
	local w = 6.4
	if seats >= 6 then
		for _, sx in { -1, 1 } do
			n += 1
			chair(b, tostring(n), sx * 4.15, 0, sx, true, T)
		end
		w = 10.2
	end
	local p = piece("dining_set", w, 7.3, 3.4, 0.6, true, b)
	p.attrs = { Seats = n } :: Spec.Attrs
	return p
end

MAKERS.bed = function(T, o)
	local b = builder()
	local single = (o.variant or 0) == 1
	local w = if single then 4.2 else 6.6
	b.box("", 0, 0, -0.2, w - 0.1, 1.0, 7.4, T.wood, "Wood")
	b.box("Headboard", 0, 0, 3.7, w, 3.6, 0.4, T.woodDark, "Wood")
	b.box("Mattress", 0, 1.0, -0.2, w - 0.4, 0.7, 7.0, T.white, "Fabric")
	b.box("Blanket", 0, 1.0, -1.3, w - 0.26, 0.78, 4.9, T.fabric, "Fabric")
	if single then
		b.box("Pillow1", 0, 1.7, 2.5, 2.6, 0.45, 1.5, T.cushion, "Fabric")
	else
		for k, s in { -1, 1 } do
			b.box(`Pillow{k}`, s * 1.6, 1.7, 2.5, 2.6, 0.45, 1.5, T.cushion, "Fabric")
		end
	end
	return piece("bed", w, 7.8, 3.6, 1.6, true, b)
end

MAKERS.nightstand = function(T, _o)
	local b = builder()
	b.box("", 0, 0, 0, 1.9, 2.0, 1.7, T.wood, "Wood")
	b.box("Drawer", 0, 1.1, -0.86, 1.6, 0.6, 0.06, T.woodDark, "Wood")
	b.cyl("LampStem", 0, 2.0, 0.2, 0.14, 0.7, T.metal, "Metal")
	b.cyl("LampShade", 0, 2.7, 0.2, 0.9, 0.7, CREAM, "Fabric")
	return piece("nightstand", 1.9, 1.7, 3.4, 0.8, true, b)
end

MAKERS.wardrobe = function(T, _o)
	local b = builder()
	b.box("", 0, 0, 0.15, 4.6, 7.4, 2.1, T.woodDark, "Wood")
	for k, s in { -1, 1 } do
		b.box(`Door{k}`, s * 1.12, 0.5, -0.92, 2.1, 6.5, 0.06, T.wood, "Wood")
		b.ball(`Knob{k}`, s * 0.25, 3.6, -1.05, 0.26, BRASS, "Metal")
	end
	return piece("wardrobe", 4.6, 2.4, 7.4, 2.2, true, b)
end

MAKERS.bathtub = function(T, _o)
	local b = builder()
	b.box("", 0, 0, 0, 6.2, 2.0, 2.9, T.white)
	b.box("Water", 0, 1.98, 0, 5.5, 0.05, 2.2, WATER, "Glass")
	b.cyl("Tap", -2.7, 2.0, 1.05, 0.2, 0.7, STEEL, "Metal")
	return piece("bathtub", 6.2, 2.9, 2.7, 1.6, true, b)
end

MAKERS.toilet = function(T, _o)
	local b = builder()
	b.box("", 0, 0, 0.9, 1.8, 3.2, 0.8, T.white)
	b.cyl("Bowl", 0, 0, -0.35, 1.6, 1.45, T.white)
	b.cyl("Lid", 0, 1.45, -0.35, 1.66, 0.14, shade(T.white, 0.9))
	return piece("toilet", 1.8, 2.6, 3.2, 1.6, true, b)
end

MAKERS.basin = function(T, _o)
	local b = builder()
	b.box("", 0, 0, 0.35, 0.9, 2.7, 0.9, T.white)
	b.box("Bowl", 0, 2.7, 0.1, 2.2, 0.5, 1.5, T.white)
	b.cyl("Tap", 0, 3.2, 0.6, 0.18, 0.6, STEEL, "Metal")
	return piece("basin", 2.2, 1.7, 3.8, 1.6, true, b)
end

MAKERS.mirror = function(T, _o)
	local b = builder()
	b.box("", 0, 4.2, 0.04, 2.4, 3.0, 0.12, T.woodDark, "Wood")
	b.box("Glass", 0, 4.4, -0.01, 2.0, 2.6, 0.1, { 178, 204, 210 }, "Glass")
	local p = piece("mirror", 2.4, 0.2, 7.2, 0, false, b)
	p.mounted = 4.2
	return p
end

MAKERS.coat_hooks = function(T, _o)
	local b = builder()
	b.box("", 0, 5.4, 0.23, 4.2, 0.5, 0.14, T.woodDark, "Wood")
	b.box("Coat1", -1.2, 2.5, 0.0, 1.1, 3.1, 0.45, T.fabricDark, "Fabric")
	b.box("Coat2", 0.9, 2.9, 0.0, 1.0, 2.7, 0.45, T.accent, "Fabric")
	local p = piece("coat_hooks", 4.2, 0.6, 5.9, 0.6, false, b)
	p.mounted = 2.5
	return p
end

MAKERS.shoe_bench = function(T, _o)
	local b = builder()
	b.box("", -0.45, 0, 0, 2.7, 1.3, 1.2, T.wood, "Wood")
	b.box("Cushion", -0.45, 1.3, 0, 2.5, 0.22, 1.1, T.fabric, "Fabric")
	b.box("Boots", 1.4, 0, 0.05, 0.7, 1.0, 0.9, { 74, 58, 46 }, "Leather")
	return piece("shoe_bench", 3.6, 1.2, 1.52, 0.6, true, b)
end

MAKERS.desk = function(T, _o)
	local b = builder()
	b.box("", 0, 2.3, 1.1, 5.2, 0.25, 2.5, T.wood, "Wood")
	b.box("Drawers", -1.7, 0, 1.1, 1.5, 2.3, 2.3, T.woodDark, "Wood")
	b.box("Leg", 2.4, 0, 1.1, 0.3, 2.3, 2.3, T.woodDark, "Wood")
	b.cyl("MonitorNeck", 0.6, 2.55, 1.75, 0.3, 0.5, BLACK, "Metal")
	b.box("Monitor", 0.6, 3.0, 1.75, 2.4, 1.5, 0.15, BLACK, "Glass")
	chair(b, "", 0.3, -1.3, -1, false, T)
	return piece("desk", 5.2, 4.7, 4.5, 0.4, true, b)
end

MAKERS.pantry_shelf = function(T, o)
	local b = builder()
	local metal = (o.variant or 0) >= 10
	b.box("", 0, 0, 0, 3.4, 6.6, 1.4, if metal then STEEL else T.wood, if metal then "Metal" else "Wood")
	local v = o.variant or 0
	for k = 1, 3 do
		b.box(`Goods{k}`, 0, 0.6 + (k - 1) * 2.0, -0.4, 3.0, 1.3, 0.7, GOODS[(k + v) % #GOODS + 1])
	end
	return piece("pantry_shelf", 3.4, 1.4, 6.6, 1.8, true, b)
end

-- Hospital and station seating: a beam on two legs with moulded seats.
MAKERS.waiting_row = function(T, o)
	local b = builder()
	local seats = o.seats or 4
	local w = seats * 2.1 + 0.2
	b.box("", 0, 0.9, 0.1, w, 0.25, 0.5, T.metal, "Metal")
	for k, s in { -1, 1 } do
		b.box(`Leg{k}`, s * (w / 2 - 0.7), 0, 0.1, 0.3, 0.9, 1.6, T.metal, "Metal")
	end
	for k = 1, seats do
		local x = (k - (seats + 1) / 2) * 2.1
		b.box(`Seat{k}`, x, 1.15, -0.1, 1.9, 0.3, 1.9, T.fabric)
		b.box(`Back{k}`, x, 1.45, 0.85, 1.9, 1.5, 0.25, T.fabric)
	end
	local p = piece("waiting_row", w, 2.2, 3.0, 2.0, false, b)
	p.attrs = { Seats = seats } :: Spec.Attrs
	return p
end

-- A ward bed on its end boards, with a bedside cabinet and a curtain on a rail.
MAKERS.ward_bed = function(T, _o)
	local b = builder()
	local bx = -1.1
	b.box("", bx, 1.3, 0.05, 3.6, 0.35, 7.3, T.metal, "Metal")
	b.box("Head", bx, 0, 3.85, 3.8, 3.4, 0.3, T.white)
	b.box("Foot", bx, 0, -3.75, 3.8, 2.4, 0.3, T.white)
	b.box("Mattress", bx, 1.65, 0.05, 3.4, 0.5, 7.0, T.white, "Fabric")
	b.box("Blanket", bx, 1.65, -1.2, 3.5, 0.58, 4.4, T.fabric, "Fabric")
	b.box("Pillow", bx, 2.15, 2.7, 2.4, 0.4, 1.3, T.cushion, "Fabric")
	b.box("Cabinet", 2.1, 0, 3.1, 1.6, 2.2, 1.6, T.white)
	b.rodZ("Rail", 2.95, 8.0, 0, 8.0, 0.16, T.metal)
	b.box("Curtain", 2.95, 2.0, 2.0, 0.12, 5.95, 3.9, T.curtain, "Fabric")
	local p = piece("ward_bed", 6.0, 8.2, 8.1, 2.4, true, b)
	p.attrs = { Curtain = true } :: Spec.Attrs
	return p
end

-- A treatment bay: an examination couch, a stool, an instrument trolley and a curtain.
MAKERS.treatment_bay = function(T, _o)
	local b = builder()
	b.box("", -1.4, 1.9, 0.6, 2.8, 0.3, 6.4, T.metal, "Metal")
	for k, s in { -1, 1 } do
		b.box(`End{k}`, -1.4, 0, 0.6 + s * 2.9, 2.4, 1.9, 0.3, T.white)
	end
	b.box("Pad", -1.4, 2.2, 0.6, 2.6, 0.35, 6.2, T.fabric, "Fabric")
	b.cyl("StoolStem", 1.6, 0, -1.6, 0.3, 1.5, T.metal, "Metal")
	b.cyl("Stool", 1.6, 1.5, -1.6, 1.3, 0.3, T.fabricDark)
	b.box("Trolley", 2.2, 0, 2.4, 1.6, 2.6, 1.2, STEEL, "Metal")
	b.box("Tray", 2.2, 2.6, 2.4, 1.8, 0.12, 1.4, T.white)
	b.rodZ("Rail", -3.55, 8.0, 0.2, 7.4, 0.16, T.metal)
	b.box("Curtain", -3.55, 2.0, 2.0, 0.12, 5.95, 3.6, T.curtain, "Fabric")
	return piece("treatment_bay", 7.4, 7.8, 8.1, 2.0, true, b)
end

MAKERS.medicine_cabinet = function(T, _o)
	local b = builder()
	b.box("", 0, 4.2, 0, 3.8, 3.2, 1.0, T.white)
	for k, s in { -1, 1 } do
		b.box(`Door{k}`, s * 0.93, 4.4, -0.5, 1.7, 2.8, 0.08, T.accent, "Glass")
	end
	b.box("CrossV", 0, 7.5, 0.0, 0.3, 0.9, 0.3, RED)
	b.box("CrossH", 0, 7.8, 0.0, 0.9, 0.3, 0.34, RED)
	local p = piece("medicine_cabinet", 3.8, 1.0, 8.4, 1.2, false, b)
	p.mounted = 4.2
	return p
end

MAKERS.iv_stand = function(T, _o)
	local b = builder()
	b.cyl("", 0, 0, 0, 1.2, 0.15, T.metal, "Metal")
	b.cyl("Pole", 0, 0.15, 0, 0.14, 6.0, STEEL, "Metal")
	b.box("Bag", 0.3, 4.9, 0, 0.5, 1.0, 0.3, { 214, 232, 236 }, "Glass")
	return piece("iv_stand", 1.2, 1.2, 6.15, 0, false, b)
end

MAKERS.locker_bank = function(T, o)
	local b = builder()
	local n = o.seats or 4
	local w = n * 1.6 + 0.2
	b.box("", 0, 0, 0, w, 7.2, 1.7, T.fabricDark, "Metal")
	for k = 1, n do
		b.box(`Door{k}`, (k - (n + 1) / 2) * 1.6, 0.4, -0.86, 1.4, 6.5, 0.06, T.fabric, "Metal")
	end
	local p = piece("locker_bank", w, 1.7, 7.2, 2.4, true, b)
	p.attrs = { Lockers = n } :: Spec.Attrs
	return p
end

-- A row of plain chairs (briefing room): seat block and back, side by side.
MAKERS.briefing_row = function(T, o)
	local b = builder()
	local seats = o.seats or 4
	local w = seats * 2.0
	for k = 1, seats do
		local x = (k - (seats + 1) / 2) * 2.0
		b.box(if k == 1 then "" else `Seat{k}`, x, 0, -0.1, 1.6, 1.45, 1.6, T.fabric, "Fabric")
		b.box(`Back{k}`, x, 1.45, 0.6, 1.5, 1.8, 0.22, T.fabricDark, "Fabric")
	end
	local p = piece("briefing_row", w, 1.8, 3.25, 1.8, false, b)
	p.attrs = { Seats = seats } :: Spec.Attrs
	return p
end

-- A holding cell against a wall: barred front and sides, a bunk inside. The bars are drawn as
-- cylinders; three invisible panels stop a body exactly where the bars stand.
MAKERS.cell = function(T, _o)
	local b = builder()
	local w, d, h = 10.4, 7.0, 8.2
	local iron = { 54, 75, 81 } -- v5.4 iron #364b51
	local front = b.box("", 0, 0, -3.35, w, h, 0.3, iron)
	front.hidden = true
	for k, s in { -1, 1 } do
		local side = b.box(`Side{k}`, s * (w / 2 - 0.15), 0, 0.15, 0.3, h, d - 0.3, iron)
		side.hidden, side.solid = true, true
		b.box(`SideTop{k}`, s * (w / 2 - 0.15), h - 0.25, 0.2, 0.28, 0.25, d - 0.5, iron, "Metal")
		for i = 1, 4 do
			b.cyl(`SideBar{k}_{i}`, s * (w / 2 - 0.15), 0, -3.35 + i * 1.4, 0.22, h - 0.25, iron, "Metal")
		end
	end
	b.box("FrontTop", 0, h - 0.25, -3.35, w, 0.25, 0.28, iron, "Metal")
	b.box("FrontSill", 0, 0, -3.35, w, 0.25, 0.28, iron, "Metal")
	for i = 0, 7 do
		b.cyl(`Bar{i + 1}`, -w / 2 + 0.3 + i * (w - 0.6) / 7, 0.25, -3.35, 0.22, h - 0.5, iron, "Metal")
	end
	b.box("Bunk", -2.3, 1.4, 2.2, 5.0, 0.3, 2.4, T.metal, "Metal")
	b.box("BunkLeg", -2.3, 0, 2.2, 4.4, 1.4, 0.3, T.metal, "Metal")
	b.box("BunkPad", -2.3, 1.7, 2.2, 4.8, 0.35, 2.2, T.cushion, "Fabric")
	local p = piece("cell", w, d, h, 2.5, true, b)
	p.attrs = { Cell = true } :: Spec.Attrs
	return p
end

MAKERS.notice_board = function(T, o)
	local b = builder()
	b.box("", 0, 4.0, 0.04, 5.0, 3.2, 0.12, T.woodDark, "Wood")
	b.box("Cork", 0, 4.2, -0.01, 4.6, 2.8, 0.1, CORK)
	local v = o.variant or 0
	b.box("Paper1", -1.2, 5.0, -0.06, 1.2, 1.5, 0.05, PAPER)
	b.box("Paper2", 0.9, 4.6, -0.06, 1.4, 1.0, 0.05, if v % 2 == 0 then { 233, 190, 78 } else { 186, 127, 135 })
	local p = piece("notice_board", 5.0, 0.2, 7.2, 0.8, false, b)
	p.mounted = 4.0
	return p
end

-- A structural column for the big rooms (opts.w = its height to the ceiling).
MAKERS.column = function(T, o)
	local b = builder()
	local h = o.w or 16
	b.box("", 0, 0, 0, 2.2, h, 2.2, T.white, "Concrete")
	b.box("Base", 0, 0, 0, 2.6, 1.2, 2.6, T.accent)
	return piece("column", 2.6, 2.6, h, 0, true, b)
end

local KINDS: { string } = {}
for k in MAKERS do
	table.insert(KINDS, k)
end
table.sort(KINDS)
Furniture.KINDS = KINDS

function Furniture.piece(kind: string, tones: Tones, opts: Opts?): Piece
	local make = MAKERS[kind] or error("Furniture.piece: unknown kind " .. kind)
	return make(tones, opts or {})
end

-- Detail parts around an existing Station (6 x 3 x 2.5 st, standing on the floor) or Shelf part, in
-- that part's frame (x across, z toward its back), y above the floor:
--   desk    a counter top on two wings with a fronted apron and a monitor (reception, triage, pharmacy)
--   console a desk top with three monitors and a keyboard (ward station, drone console)
--   board   a pin board standing on the cabinet (quest board)
--   shelf   end panels, three shelf boards on the slot side and a top (opts.w = length, opts.seats = levels)
function Furniture.dress(kind: string, T: Tones, opts: Opts?): { PartDef }
	local b = builder()
	local o: Opts = opts or {}
	if kind == "desk" then
		b.box("Top", 0, 3.0, 0, 9.0, 0.25, 3.3, T.wood, "Wood")
		b.box("Apron", 0, 0, -1.45, 9.0, 3.0, 0.3, T.accent)
		for k, s in { -1, 1 } do
			b.box(`Wing{k}`, s * 3.75, 0, 0.1, 1.5, 3.0, 2.6, T.white)
		end
		b.cyl("MonitorNeck", 1.5, 3.25, 0.5, 0.3, 0.4, BLACK, "Metal")
		b.box("Monitor", 1.5, 3.6, 0.5, 1.9, 1.3, 0.15, BLACK, "Glass")
	elseif kind == "console" then
		b.box("Top", 0, 3.0, 0, 8.0, 0.25, 3.3, T.metal, "Metal")
		b.box("Riser", 0, 3.25, 0.9, 7.0, 0.5, 0.8, T.woodDark)
		for k = 1, 3 do
			b.box(`Monitor{k}`, (k - 2) * 2.3, 3.75, 0.9, 2.0, 1.4, 0.15, BLACK, "Glass")
		end
		b.box("Keys", 0, 3.25, -0.6, 2.4, 0.08, 0.8, BLACK)
	elseif kind == "board" then
		b.box("Frame", 0, 3.0, 0.9, 7.0, 4.6, 0.3, T.woodDark, "Wood")
		b.box("Cork", 0, 3.3, 0.72, 6.4, 4.0, 0.12, CORK)
		b.box("Paper1", -1.9, 5.2, 0.63, 1.4, 1.6, 0.06, PAPER)
		b.box("Paper2", 0.2, 4.2, 0.63, 1.6, 1.2, 0.06, { 233, 190, 78 })
		b.box("Paper3", 2.0, 5.4, 0.63, 1.2, 1.4, 0.06, { 186, 127, 135 })
	elseif kind == "shelf" then
		local len, levels = o.w or 17.5, o.seats or 3
		local h = 2.2 * levels
		for k, s in { -1, 1 } do
			b.box(`End{k}`, s * (len / 2 + 0.1), 0, -0.55, 0.2, h + 0.2, 2.8, T.white, "Metal")
		end
		for lv = 1, levels do
			b.box(`Board{lv}`, 0, (lv - 1) * 2.2 + 1.0, -1.4, len, 0.12, 1.2, STEEL, "Metal")
		end
		b.box("Cap", 0, h, -0.55, len + 0.5, 0.2, 2.9, T.accent)
	else
		error("Furniture.dress: unknown kind " .. kind)
	end
	return b.parts
end

-- The direction a placed piece's back looks, in model-local (x, z).
function Furniture.backDir(turns: number): (number, number)
	local q = turns % 4
	if q == 0 then
		return 0, 1
	elseif q == 1 then
		return 1, 0
	elseif q == 2 then
		return 0, -1
	end
	return -1, 0
end

function Furniture.footprint(p: Piece, turns: number): (number, number)
	if turns % 2 == 0 then
		return p.w, p.d
	end
	return p.d, p.w
end

local function place(
	list: Spec.PartList,
	frame: Geometry.Frame,
	name: string,
	def: PartDef,
	x: number,
	z: number,
	turns: number,
	floorY: number,
	opts: Spec.Opts
): Spec.PartSpec
	local a = (turns % 4) * HALF_PI
	local c, s = math.cos(a), math.sin(a)
	-- Ry(a): the same convention as Geometry.rotate and Factory
	local rx, rz = def.x * c + def.z * s, -def.x * s + def.z * c
	opts.color = def.c
	opts.material = def.m
	opts.shape = def.shape
	opts.yaw = a + (def.yaw or 0)
	opts.roll = def.roll
	if def.hidden then
		opts.transparency = 1
	end
	return list:add(frame, name, x + rx, floorY + def.y, z + rz, def.sx, def.sy, def.sz, opts)
end

local NO_ATTRS: Spec.Attrs = table.freeze({})

-- Adds a piece to `list` at model-local (x, z) on the floor at floorY (above the seat). The root part
-- is named `name` and carries Kit plus `attrs`; details are <name>_<suffix>.
function Furniture.emit(
	list: Spec.PartList,
	frame: Geometry.Frame,
	name: string,
	p: Piece,
	x: number,
	z: number,
	turns: number,
	floorY: number,
	attrs: Spec.Attrs?
): Spec.PartSpec
	local root: Spec.PartSpec? = nil
	for i, def in p.parts do
		if i == 1 then
			local a: Spec.Attrs = { Kit = p.kind }
			for _, more in { p.attrs or NO_ATTRS, attrs or NO_ATTRS } do
				for k, v in more do
					a[k] = v
				end
			end
			if p.mounted then
				a.WallMounted = true
			end
			root = place(list, frame, name, def, x, z, turns, floorY, {
				canCollide = p.solid,
				canQuery = if p.solid then nil else false,
				castShadow = false,
				role = if p.solid then "Furniture" else "Decor",
				attrs = a,
			})
		else
			place(list, frame, name .. "_" .. def.n, def, x, z, turns, floorY, {
				canCollide = def.solid == true,
				canQuery = false,
				castShadow = false,
				role = if def.solid then "Furniture" else "Decor",
				attrs = if def.solid then { Part = name } :: Spec.Attrs else nil,
			})
		end
	end
	return root :: Spec.PartSpec
end

-- Adds dressing parts around an existing part `name` (a Station or a Shelf) centred at (x, z).
function Furniture.emitDress(
	list: Spec.PartList,
	frame: Geometry.Frame,
	name: string,
	parts: { PartDef },
	x: number,
	z: number,
	turns: number,
	floorY: number
)
	for _, def in parts do
		place(list, frame, name .. "_" .. def.n, def, x, z, turns, floorY, {
			canCollide = false,
			canQuery = false,
			castShadow = false,
			role = "Decor",
		})
	end
end

return Furniture
