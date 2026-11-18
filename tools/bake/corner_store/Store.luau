--!strict
-- tools/bake/corner_store/Store: Pepper's Corner Store (f1_corner_store, brief v2 "Corner store", addendum D2/D14),
-- baked as plain parts in the venue's local frame (tools/bake/alley/Kit: X across the frontage, Y up from the
-- floor, D into the building; the front is at -D). A 1970s feel, not a period piece:
--   Shell     a brick box with a flat roof behind a parapet, plate-glass shop windows either side of the open
--             double doorway, a side door and a service door (each a gap with steps down to the ground), an
--             aluminium canopy over the front, the sign PEPPER'S CORNER STORE on the parapet (its letters glow).
--   Inside    harvest-gold and brown linoleum checks, walnut wood-panel walls over a dark skirting, an acoustic
--             ceiling with fluorescent strip lights.
-- Interface: build(kit, parent, venue, groundAt) -> Model, where groundAt(X, D) is the ground's height below the
--   floor (studs, negative) outside an entrance; constants WALL, IN_X, IN_D, CEIL, TOP, SIGN.
-- No side effects on require. Lune only (@lune/roblox through the Kit).

local Kit = require("../alley/Kit")
local Fixtures = require("./Fixtures")
local ItemRules = require("../../../src/shared/Items/ItemRules")
local EconomyRules = require("../../../src/shared/Economy/EconomyRules")

local Store = {}

Store.WALL = 1.0
Store.IN_X = 23 -- the inside faces of the side walls
Store.IN_D = 21 -- the inside faces of the front and back walls
Store.CEIL = 11 -- the ceiling's underside above the floor
Store.TOP = 15 -- the parapet's top
Store.SIGN = "PEPPER'S CORNER STORE"
Store.STEP = 0.65 -- the most a step rises

local BRICK = { 150, 92, 64 }
local CONCRETE = { 156, 152, 144 }
local ROOF = { 70, 70, 74 }
local CEILING = { 236, 232, 220 }
local LINO = { 214, 170, 76 } -- harvest gold
local LINO_DARK = { 120, 78, 44 } -- brown
local WALNUT = { 112, 74, 46 }
local SKIRT = { 60, 42, 30 }
local ALUMINIUM = { 190, 192, 196 }
local GLASS = { 200, 225, 235 }
local SIGN_BG = { 176, 40, 32 }
local SIGN_FG = { 255, 236, 190 }
local TUBE = { 245, 250, 255 }

local GLASS_OPTS = { transparency = 0.7, shadow = false, reflectance = 0.1 }

-- The openings: each one's span along its wall and its head (Y). Front and service doors' X; the side door's D.
Store.FRONT_DOOR = { -9, -3 }
Store.SIDE_DOOR = { -10, -6 }
Store.SERVICE_DOOR = { -14, -10 }
Store.DOOR_HEAD = 8.5
Store.WINDOWS = { { -21, -11 }, { 1, 21 } } -- the front windows' X spans
Store.SILL, Store.WINDOW_HEAD = 2.5, 8

-- A wall along X (front or back) at depth d0..d1 with gaps { {x0, x1, y0, y1} } (a gap spans y0..y1; the wall
-- fills below and above it).
local function wallX(kit: Kit.Kit, parent: any, name: string, d0: number, d1: number, gaps: { { number } }, y0: number)
	local x0, x1 = -Store.IN_X - Store.WALL, Store.IN_X + Store.WALL
	local cursor = x0
	local n = 0
	local function piece(a: number, b: number, lo: number, hi: number)
		if b - a > 0.01 and hi - lo > 0.01 then
			n += 1
			kit:box(parent, `{name}{n}`, a, b, lo, hi, d0, d1, BRICK, "Brick")
		end
	end
	for _, g in gaps do
		piece(cursor, g[1], y0, Store.TOP)
		piece(g[1], g[2], y0, g[3])
		piece(g[1], g[2], g[4], Store.TOP)
		cursor = g[2]
	end
	piece(cursor, x1, y0, Store.TOP)
end

-- Steps from a landing at the floor down to the ground outside an opening: `along` is the opening's span, the
-- steps run away from the wall (sign `out` along X or D).
local function steps(
	kit: Kit.Kit,
	parent: any,
	name: string,
	axis: string,
	edge: number,
	out: number,
	span: { number },
	drop: number,
	base: number
)
	local n = math.max(1, math.ceil(-drop / Store.STEP))
	local rise = -drop / n
	local depth = 1.0
	-- the landing (1.5 deep) at the floor's height, then n - 1 steps; the last one is the ground
	local function slab(i: number, lo: number, hi: number, top: number)
		local a, b = edge + out * lo, edge + out * hi
		local s0, s1 = span[1] - 0.6, span[2] + 0.6
		if axis == "D" then
			kit:box(parent, `{name}{i}`, s0, s1, base, top, math.min(a, b), math.max(a, b), CONCRETE, "Concrete")
		else
			kit:box(parent, `{name}{i}`, math.min(a, b), math.max(a, b), base, top, s0, s1, CONCRETE, "Concrete")
		end
	end
	slab(0, 0, 1.5, 0)
	for i = 1, n - 1 do
		slab(i, 1.5 + (i - 1) * depth, 1.5 + i * depth, -i * rise)
	end
end

function Store.build(kit: Kit.Kit, parent: any, venue: any, groundAt: (number, number) -> number): any
	local root = kit:model(parent, venue.id)
	root.ModelStreamingMode = kit.roblox.Enum.ModelStreamingMode.Atomic
	root.LevelOfDetail = kit.roblox.Enum.ModelLevelOfDetail.SLIM
	root:SetAttribute("Venue", venue.id)
	local start = kit.count

	local W, IX, ID = Store.WALL, Store.IN_X, Store.IN_D
	local OX, OD = IX + W, ID + W
	local base = venue.ground.min - venue.floorY - 1.0
	local floorTop = -0.4 -- the slab under the linoleum

	-- shell
	local shell = kit:model(root, "Shell")
	kit:box(shell, "Plinth", -OX - 0.3, OX + 0.3, base, floorTop, -OD - 0.3, OD + 0.3, CONCRETE, "Concrete")
	kit:box(shell, "Linoleum", -IX, IX, floorTop, 0, -ID, ID, LINO, "SmoothPlastic")
	-- the front wall: piers, sills and headers round the two windows and the doorway
	local fd = Store.FRONT_DOOR
	local wins = Store.WINDOWS
	wallX(kit, shell, "Front", -OD, -ID, {
		{ wins[1][1], wins[1][2], Store.SILL, Store.WINDOW_HEAD },
		{ fd[1], fd[2], floorTop, Store.DOOR_HEAD },
		{ wins[2][1], wins[2][2], Store.SILL, Store.WINDOW_HEAD },
	}, floorTop)
	for i, w in wins do
		kit:box(
			shell,
			`Window{i}`,
			w[1],
			w[2],
			Store.SILL,
			Store.WINDOW_HEAD,
			-OD + 0.4,
			-OD + 0.6,
			GLASS,
			"Glass",
			GLASS_OPTS
		)
	end
	local sd = Store.SERVICE_DOOR
	wallX(kit, shell, "Back", ID, OD, { { sd[1], sd[2], floorTop, Store.DOOR_HEAD } }, floorTop)
	-- the side walls: the east one (-X) whole, the west one (+X) round the side door
	kit:box(shell, "SideEast", -OX, -IX, floorTop, Store.TOP, -ID, ID, BRICK, "Brick")
	local sdd = Store.SIDE_DOOR
	kit:box(shell, "SideWest1", IX, OX, floorTop, Store.TOP, -ID, sdd[1], BRICK, "Brick")
	kit:box(shell, "SideWest2", IX, OX, Store.DOOR_HEAD, Store.TOP, sdd[1], sdd[2], BRICK, "Brick")
	kit:box(shell, "SideWest3", IX, OX, floorTop, Store.TOP, sdd[2], ID, BRICK, "Brick")
	-- ceiling and the flat roof behind the parapet
	kit:box(shell, "Ceiling", -IX, IX, Store.CEIL, Store.CEIL + 0.4, -ID, ID, CEILING, "SmoothPlastic")
	kit:box(shell, "Roof", -IX, IX, Store.TOP - 2.4, Store.TOP - 1.8, -ID, ID, ROOF, "Slate")
	-- the canopy over the front windows and the doorway
	kit:box(shell, "Canopy", -OX + 1, OX - 1, 9.0, 9.35, -OD - 3.2, -OD, ALUMINIUM, "Metal", { shadow = true })
	-- the sign on the parapet, over the canopy
	local board = kit:box(shell, "SignBoard", -19, 19, 10.2, 14.4, -OD - 0.25, -OD, SIGN_BG, "SmoothPlastic")
	local gui = kit:gui(board, "Back", 30)
	kit:label(
		gui,
		{ Text = Store.SIGN, TextColor = SIGN_FG, Font = "FredokaOne", Size = { 0.96, 0.8 }, Pos = { 0.02, 0.1 } }
	)

	-- the inside: wood-panel walls over a dark skirting (thin linings on the brick)
	local inside = kit:model(root, "Interior")
	local LIN = 0.15
	local function lining(name: string, x0: number, x1: number, d0: number, d1: number)
		kit:box(
			inside,
			name,
			x0,
			x1,
			0.6,
			Store.CEIL,
			d0,
			d1,
			WALNUT,
			"WoodPlanks",
			{ collide = false, query = false, shadow = false }
		)
		kit:box(
			inside,
			name .. "Skirt",
			x0,
			x1,
			0,
			0.6,
			d0,
			d1,
			SKIRT,
			"Wood",
			{ collide = false, query = false, shadow = false }
		)
	end
	lining("PanelEast", -IX, -IX + LIN, -ID + 0.5, ID)
	lining("PanelWestFront", IX - LIN, IX, -ID + 0.5, sdd[1])
	lining("PanelWestBack", IX - LIN, IX, sdd[2], ID)
	lining("PanelBackEast", -IX, sd[1], ID - LIN, ID)
	lining("PanelBackWest", sd[2], IX, ID - LIN, ID)
	-- the linoleum's brown checks, 4 studs square, laid on the gold (collide off: a skin over the floor)
	local T = 4
	for i = 0, math.floor(2 * IX / T) - 1 do
		for j = 0, math.floor(2 * ID / T) - 1 do
			if (i + j) % 2 == 0 then
				local x0, d0 = -IX + 1 + i * T, -ID + 1 + j * T
				kit:box(inside, "Check", x0, x0 + T, 0, 0.02, d0, d0 + T, LINO_DARK, "SmoothPlastic", {
					collide = false,
					query = false,
					shadow = false,
				})
			end
		end
	end

	-- fluorescent strip lights: six tubes in two rows, three of them lit (the engine pays per light)
	local lamps = kit:model(root, "Lamps")
	for row, x in { -9, 9 } do
		for k, d in { -12, 0, 12 } do
			local tube = kit:box(
				lamps,
				`Tube{row}{k}`,
				x - 0.35,
				x + 0.35,
				Store.CEIL - 0.25,
				Store.CEIL,
				d - 5,
				d + 5,
				TUBE,
				"Neon",
				{
					collide = false,
					query = false,
					shadow = false,
				}
			)
			if (row + k) % 2 == 0 or k == 2 then
				kit:light(
					tube,
					"PointLight",
					{ Color = { 240, 246, 255 }, Brightness = 1.1, Range = 22, Shadows = false }
				)
			end
		end
	end

	-- entrances: a landing and steps down to the ground outside each opening
	local ent = kit:model(root, "Entrances")
	steps(kit, ent, "FrontStep", "D", -OD, -1, fd, groundAt((fd[1] + fd[2]) / 2, -OD - 3), base)
	steps(kit, ent, "SideStep", "X", OX, 1, sdd, groundAt(OX + 3, (sdd[1] + sdd[2]) / 2), base)
	steps(kit, ent, "ServiceStep", "D", OD, 1, sd, groundAt((sd[1] + sd[2]) / 2, OD + 3), base)
	-- door thresholds level with the floor in each wall gap
	kit:box(ent, "FrontThreshold", fd[1], fd[2], base, 0, -OD, -ID, CONCRETE, "Concrete")
	kit:box(ent, "SideThreshold", IX, OX, base, 0, sdd[1], sdd[2], CONCRETE, "Concrete")
	kit:box(ent, "ServiceThreshold", sd[1], sd[2], base, 0, ID, OD, CONCRETE, "Concrete")

	-- the furniture and the 22 items on their shelves
	local prices: { [string]: number } = {}
	for _, def in ItemRules.CATALOG do
		prices[def.id] = def.price
	end
	local items = Fixtures.build(kit, root, prices, EconomyRules.NAMES :: any)
	root:SetAttribute("Items", items)

	local hidden = { collide = false, query = false, transparency = 1, shadow = false }
	-- the store's inside as one box: a shopper whose body leaves it puts back what they have not paid for
	-- (Server/Items/CornerStore reads it)
	kit:box(root, "Zone", -IX, IX, -0.5, Store.CEIL, -ID, ID, { 255, 255, 0 }, "SmoothPlastic", hidden)

	-- the inside of the shell, carved to air at boot (no terrain pokes through the floor)
	local carve = kit:folder(root, "TerrainCarve")
	kit:box(carve, "Inside", -IX, IX, -0.4, Store.CEIL, -ID, ID, { 255, 0, 0 }, "SmoothPlastic", hidden)

	root:SetAttribute("Parts", kit.count - start)
	return root
end

return Store
