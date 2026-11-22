--!strict
-- tools/bake/corner_store/Fixtures: the corner store's furniture and its 23 shelf places, in the venue's local
-- frame (X across the frontage, Y up from the floor, D into the building; the front door at D -21).
--   Checkout  the counter by the door (walnut front, cream top) with the till, the bell, the gum rack and the
--             camera's impulse rack; the shopkeeper's place behind it; the back bar behind him (bird seed and
--             the kite, the two dear things, out of reach but in sight: their prompts reach over the counter).
--   Aisles    four low beige gondolas (four and a half studs: a person sees over them), each two-sided with
--             walnut end caps; grocery shelving on the east wall and a hardware pegboard on the west.
--   Back      the cold drinks fridge (glass doors) and the ice cream chest freezer on the back wall.
--   Front     the newspaper rack, the umbrella bin and the lawn chair on show in the window.
-- Each of the 23 items (SLOTS, the catalogue's ids) has its place; each one on sale (a price in `prices`: not the dog
-- treats until the town has dogs) is a Model "Item_<id>" with attributes ItemId and Price:
-- "Sample" (the model the server hands a buyer), two more copies under "More", a price tag (its price as
-- Economy/Bank.amount writes it, "50c" or "S$6.00"), and an invisible "Grab" part holding the ProximityPrompt (E,
-- a click or a tap, gamepad X).
-- Interface: build(kit, root, prices, names) -> count of items stocked; SLOTS (id -> { x, y, d, yaw, fixture });
--   COUNTER { x0, x1, d0, d1, top }; STAFF { x, d } (the shopkeeper's post); STAFF_ROUND ({ {x, d} });
--   GONDOLAS ({ centre X }); GONDOLA_D { d0, d1 }; REACH (the prompts' reach); FAR_REACH (over the counter)
-- No side effects on require. Lune only (@lune/roblox through the Kit).

local Bank = require("../../../src/shared/Economy/Bank")
local Kit = require("../alley/Kit")
local Stock = require("./Stock")

local Fixtures = {}

local PI = math.pi
local FACE_W, FACE_E, FACE_FRONT, FACE_BACK = PI / 2, -PI / 2, 0, PI -- yaw: facing local +X, -X, -D, +D

Fixtures.COUNTER = { x0 = -20, x1 = -12, d0 = -15, d1 = -12.5, top = 3.2 }
Fixtures.STAFF = { x = -16, d = -10 }
Fixtures.STAFF_ROUND = { { -16, -10 }, { -13.5, -10.2 }, { -18.5, -10.2 } }
Fixtures.BACKBAR = { x0 = -21, x1 = -12, d0 = -7.5, d1 = -6.5, h = 7 }
Fixtures.GONDOLAS = { -13, -3, 7, 15 }
Fixtures.GONDOLA_D = { d0 = -3, d1 = 15 }
Fixtures.GONDOLA_HALF, Fixtures.GONDOLA_H = 1.3, 4.6
Fixtures.SHELF_Y = { 0.5, 1.9, 3.3 } -- the shelves' tops on a gondola
Fixtures.REACH = 7
Fixtures.FAR_REACH = 11

local G, H = Fixtures.GONDOLAS, Fixtures.GONDOLA_HALF
local MID = Fixtures.SHELF_Y[2]
-- stylua: ignore
Fixtures.SLOTS = {
	-- gondola 1: toys
	frisbee = { x = G[1] - 0.7, y = MID, d = 1, yaw = FACE_E, fixture = "gondola1" },
	football = { x = G[1] - 0.7, y = MID, d = 9, yaw = FACE_E, fixture = "gondola1" },
	bubbles = { x = G[1] + 0.7, y = MID, d = 1, yaw = FACE_W, fixture = "gondola1" },
	chalk = { x = G[1] + 0.7, y = MID, d = 9, yaw = FACE_W, fixture = "gondola1" },
	-- gondola 2: fun and noise
	water_gun = { x = G[2] - 0.7, y = MID, d = 1, yaw = FACE_E, fixture = "gondola2" },
	whoopee_cushion = { x = G[2] - 0.7, y = MID, d = 9, yaw = FACE_E, fixture = "gondola2" },
	harmonica = { x = G[2] + 0.7, y = MID, d = 1, yaw = FACE_W, fixture = "gondola2" },
	bike_horn = { x = G[2] + 0.7, y = MID, d = 9, yaw = FACE_W, fixture = "gondola2" },
	-- gondola 3: snacks and pets
	peanuts = { x = G[3] - 0.7, y = MID, d = 1, yaw = FACE_E, fixture = "gondola3" },
	dog_treats = { x = G[3] - 0.7, y = MID, d = 9, yaw = FACE_E, fixture = "gondola3" },
	flashlight = { x = G[3] + 0.7, y = MID, d = 1, yaw = FACE_W, fixture = "gondola3" },
	radio = { x = G[3] + 0.7, y = MID, d = 9, yaw = FACE_W, fixture = "gondola3" },
	-- gondola 4: odds and ends
	duct_tape = { x = G[4] - 0.7, y = MID, d = 1, yaw = FACE_E, fixture = "gondola4" },
	air_horn = { x = G[4] - 0.7, y = MID, d = 9, yaw = FACE_E, fixture = "gondola4" },
	kick_ball = { x = G[4] + 0.7, y = MID, d = 1, yaw = FACE_W, fixture = "gondola4" }, -- owner D30
	-- the checkout and behind it
	camera = { x = -12.9, y = 3.2, d = -14.2, yaw = FACE_FRONT, fixture = "counter" },
	bird_seed = { x = -18, y = 0.3, d = -7.0, yaw = FACE_FRONT, fixture = "backbar" },
	kite = { x = -14.5, y = 3.6, d = -7.0, yaw = FACE_FRONT, fixture = "backbar" },
	-- the front
	newspaper = { x = 1.5, y = 2.3, d = -19.8, yaw = FACE_BACK, fixture = "news_rack" },
	umbrella = { x = -11.5, y = 0.6, d = -19.9, yaw = FACE_BACK, fixture = "umbrella_bin" },
	lawn_chair = { x = 6.5, y = 0.4, d = -18.6, yaw = FACE_BACK, fixture = "window" },
	-- the back wall
	soda = { x = 8, y = 2.6, d = 19.6, yaw = FACE_FRONT, fixture = "cooler" },
	ice_cream_bar = { x = -4, y = 2.0, d = 19.7, yaw = FACE_FRONT, fixture = "freezer" },
}

local WALNUT = { 112, 74, 46 }
local CREAM = { 240, 228, 196 }
local BEIGE = { 214, 204, 180 }
local STEEL = { 170, 172, 178 }
local DARK = { 40, 40, 44 }
local WHITE = { 246, 246, 242 }
local GLASS = { 200, 225, 235 }
local BRASS = { 200, 160, 70 }
local PEGBOARD = { 196, 160, 110 }

local VISUAL = { collide = false, query = false, shadow = false }
local GLASS_OPTS = { transparency = 0.6, shadow = false, reflectance = 0.1 }

-- the filler stock on every shelf not given to an item: tins and boxes in 1970s packaging colours
-- stylua: ignore
local PACK = {
	{ 214, 120, 40 }, { 180, 60, 40 }, { 230, 190, 60 }, { 120, 140, 60 }, { 70, 110, 150 }, { 200, 170, 130 },
	{ 150, 70, 90 }, { 240, 220, 170 }, { 90, 60, 40 },
}
local packIndex = 0
local function pack(): { number }
	packIndex = packIndex % #PACK + 1
	return PACK[packIndex]
end

-- A row of filler packs along D on a shelf (x0..x1 across, from d0 to d1), skipping the item places' spans.
local function fillRow(
	kit: Kit.Kit,
	parent: any,
	x0: number,
	x1: number,
	y: number,
	d0: number,
	d1: number,
	h: number,
	skip: { { number } }
)
	local d = d0
	local w = 2.2
	while d + w <= d1 + 1e-6 do
		local clear = true
		for _, s in skip do
			if d < s[2] and d + w > s[1] then
				clear = false
			end
		end
		if clear then
			kit:box(parent, "Packs", x0, x1, y, y + h, d + 0.1, d + w - 0.1, pack(), "SmoothPlastic", VISUAL)
		end
		d += w
	end
end

local function gondola(kit: Kit.Kit, parent: any, i: number, c: number)
	local m = kit:model(parent, `Gondola{i}`)
	local g = Fixtures.GONDOLA_D
	local top = Fixtures.GONDOLA_H
	kit:box(m, "Base", c - H, c + H, 0, 0.5, g.d0, g.d1, DARK, "SmoothPlastic")
	kit:box(m, "Spine", c - 0.12, c + 0.12, 0.5, top, g.d0 + 0.2, g.d1 - 0.2, BEIGE, "Metal")
	for k = 2, #Fixtures.SHELF_Y do
		local y = Fixtures.SHELF_Y[k]
		kit:box(m, "ShelfE", c - H, c - 0.12, y - 0.1, y, g.d0 + 0.2, g.d1 - 0.2, BEIGE, "Metal", VISUAL)
		kit:box(m, "ShelfW", c + 0.12, c + H, y - 0.1, y, g.d0 + 0.2, g.d1 - 0.2, BEIGE, "Metal", VISUAL)
	end
	kit:box(m, "Top", c - H, c + H, top - 0.1, top, g.d0, g.d1, BEIGE, "Metal")
	kit:box(m, "CapFront", c - H, c + H, 0, top, g.d0 - 0.2, g.d0, WALNUT, "Wood")
	kit:box(m, "CapBack", c - H, c + H, 0, top, g.d1, g.d1 + 0.2, WALNUT, "Wood")
	-- filler: the bottom and top shelves full, the middle one round the item places
	for _, side in { -1, 1 } do
		local a, b = c + side * 0.2, c + side * (H - 0.15)
		local x0, x1 = math.min(a, b), math.max(a, b)
		local mine: { { number } } = {}
		for _, s in Fixtures.SLOTS do
			if s.fixture == `gondola{i}` and (s.x - c) * side > 0 then
				table.insert(mine, { s.d - 2.2, s.d + 2.2 })
			end
		end
		fillRow(kit, m, x0, x1, 0.5, g.d0 + 0.3, g.d1 - 0.3, 1.0, {})
		fillRow(kit, m, x0, x1, MID, g.d0 + 0.3, g.d1 - 0.3, 0.9, mine)
		fillRow(kit, m, x0, x1, Fixtures.SHELF_Y[3], g.d0 + 0.3, g.d1 - 0.3, 0.8, {})
	end
	return m
end

local function counter(kit: Kit.Kit, parent: any)
	local m = kit:model(parent, "Checkout")
	local c = Fixtures.COUNTER
	kit:box(m, "Front", c.x0, c.x1, 0, c.top - 0.15, c.d0, c.d1, WALNUT, "Wood")
	kit:box(m, "Top", c.x0 - 0.15, c.x1 + 0.15, c.top - 0.15, c.top, c.d0 - 0.2, c.d1 + 0.1, CREAM, "SmoothPlastic")
	kit:box(m, "Kick", c.x0, c.x1, 0, 0.4, c.d0 - 0.05, c.d0, DARK, "SmoothPlastic", VISUAL)
	-- the till: a cash register with its drawer, keys and the sale window
	kit:box(m, "Till", -15.4, -13.8, c.top, c.top + 0.9, -14.1, -12.9, STEEL, "Metal", VISUAL)
	kit:box(m, "TillDrawer", -15.4, -13.8, c.top, c.top + 0.3, -14.25, -14.1, DARK, "Metal", VISUAL)
	local sale =
		kit:box(m, "TillWindow", -15.2, -14.0, c.top + 0.9, c.top + 1.3, -13.8, -13.6, DARK, "SmoothPlastic", VISUAL)
	sale:SetAttribute("Till", true)
	-- the till's prompts, on an invisible part over the counter in front of the till: Pay (E) and Put back (R,
	-- gamepad Y, a short hold)
	local pay = kit:box(
		m,
		"PayPoint",
		-16.2,
		-13.0,
		c.top,
		c.top + 1.6,
		-15.2,
		-13.8,
		{ 255, 255, 255 },
		"SmoothPlastic",
		{
			collide = false,
			query = false,
			shadow = false,
			transparency = 1,
		}
	)
	local r = kit.roblox
	local p = r.Instance.new("ProximityPrompt")
	p.Name = "Pay"
	p.ActionText = "Pay"
	p.ObjectText = "Checkout"
	p.HoldDuration = 0
	p.RequiresLineOfSight = false
	p.MaxActivationDistance = Fixtures.REACH
	p:SetAttribute("Till", "pay")
	p.Parent = pay
	local q = r.Instance.new("ProximityPrompt")
	q.Name = "PutBack"
	q.ActionText = "Put it all back"
	q.ObjectText = "Checkout"
	q.HoldDuration = 0.5
	q.KeyboardKeyCode = r.Enum.KeyCode.R
	q.GamepadKeyCode = r.Enum.KeyCode.ButtonY
	q.RequiresLineOfSight = false
	q.MaxActivationDistance = Fixtures.REACH
	q.UIOffset = r.Vector2.new(0, 72)
	q:SetAttribute("Till", "put_back")
	q.Parent = pay
	-- the bell to ring for service, and the gum rack on the customers' side
	kit:cyl(m, "BellBase", -17.6, c.top + 0.03, -14.3, 0.06, 0.5, "Y", DARK, "Metal", VISUAL)
	kit:ball(m, "Bell", -17.6, c.top + 0.2, -14.3, 0.4, BRASS, "Metal", VISUAL)
	kit:box(m, "GumRack", -19.8, -18.6, 0.4, 2.8, -15.6, -15.0, STEEL, "Metal")
	for k = 0, 3 do
		kit:box(
			m,
			"Gum",
			-19.7,
			-18.7,
			0.6 + k * 0.55,
			0.9 + k * 0.55,
			-15.65,
			-15.55,
			PACK[k + 1],
			"SmoothPlastic",
			VISUAL
		)
	end
	-- the camera's impulse rack on the counter's end
	kit:box(m, "ImpulseRack", -13.4, -12.3, c.top, c.top + 0.08, -14.7, -13.7, STEEL, "Metal", VISUAL)
	-- the back bar behind the shopkeeper
	local b = Fixtures.BACKBAR
	kit:box(m, "BackBar", b.x0, b.x1, 0, 0.3, b.d0, b.d1, DARK, "SmoothPlastic")
	kit:box(m, "BackBarPanel", b.x0, b.x1, 0.3, b.h, b.d1 - 0.2, b.d1, WALNUT, "WoodPlanks")
	for _, y in { 2.4, 4.6 } do
		kit:box(m, "BackBarShelf", b.x0, b.x1, y - 0.1, y, b.d0, b.d1 - 0.2, BEIGE, "Metal", VISUAL)
	end
	for k = 0, 3 do
		local x = b.x0 + 0.6 + k * 2.1
		kit:box(m, "Cartons", x, x + 1.7, 2.4, 3.3, b.d0 + 0.1, b.d1 - 0.3, PACK[k + 5], "SmoothPlastic", VISUAL)
	end
	return m
end

local function walls(kit: Kit.Kit, parent: any)
	local m = kit:model(parent, "WallShelves")
	-- the east wall: grocery shelving, four shelves
	local x0, x1, d0, d1 = -23, -21.4, -2, 16
	kit:box(m, "EastBase", x0, x1, 0, 0.5, d0, d1, DARK, "SmoothPlastic")
	for _, y in { 1.9, 3.3, 4.7, 6.1 } do
		kit:box(m, "EastShelf", x0, x1, y - 0.1, y, d0, d1, BEIGE, "Metal", VISUAL)
	end
	kit:box(m, "EastEnd1", x0, x1, 0, 6.2, d0 - 0.15, d0, BEIGE, "Metal")
	kit:box(m, "EastEnd2", x0, x1, 0, 6.2, d1, d1 + 0.15, BEIGE, "Metal")
	for _, y in { 0.5, 1.9, 3.3, 4.7 } do
		fillRow(kit, m, x0 + 0.1, x1 - 0.1, y, d0 + 0.2, d1 - 0.2, 1.1, {})
	end
	-- the west wall: a hardware pegboard over a low shelf
	local wx0, wx1, wd0, wd1 = 21.6, 23, -2, 18
	kit:box(m, "WestBase", wx0 - 0.6, wx1, 0, 2.4, wd0, wd1, WALNUT, "Wood")
	kit:box(m, "Pegboard", 22.8, 22.9, 2.4, 7.5, wd0, wd1, PEGBOARD, "Fabric", VISUAL)
	local d = wd0 + 0.8
	local k = 0
	while d < wd1 - 1 do
		k += 1
		kit:box(
			m,
			"Hung",
			22.4,
			22.8,
			3.2 + (k % 3) * 1.3,
			4.0 + (k % 3) * 1.3,
			d,
			d + 1.0,
			pack(),
			"SmoothPlastic",
			VISUAL
		)
		d += 1.7
	end
	fillRow(kit, m, wx0 - 0.5, wx1 - 0.1, 2.4, wd0 + 0.2, wd1 - 0.2, 0.8, {})
	return m
end

local function back(kit: Kit.Kit, parent: any)
	local m = kit:model(parent, "Cold")
	-- the cold drinks fridge: a white cabinet, glass doors, a lit sign band over them
	local x0, x1, d0, d1 = 2, 20, 18.6, 21
	kit:box(m, "FridgeBase", x0, x1, 0, 0.8, d0, d1, DARK, "SmoothPlastic")
	kit:box(m, "FridgeSides", x0, x0 + 0.3, 0.8, 8, d0, d1, WHITE, "SmoothPlastic")
	kit:box(m, "FridgeSides", x1 - 0.3, x1, 0.8, 8, d0, d1, WHITE, "SmoothPlastic")
	kit:box(m, "FridgeTop", x0, x1, 7, 8, d0, d1, WHITE, "SmoothPlastic")
	local band =
		kit:box(m, "FridgeSign", x0 + 0.3, x1 - 0.3, 7.15, 7.85, d0 - 0.05, d0, { 30, 90, 170 }, "Neon", VISUAL)
	local gui = kit:gui(band, "Back", 30)
	kit:label(gui, { Text = "ICE COLD DRINKS", TextColor = { 255, 255, 255 }, Font = "FredokaOne" })
	for _, y in { 2.6, 4.4, 6.0 } do
		kit:box(m, "FridgeShelf", x0 + 0.3, x1 - 0.3, y - 0.08, y, d0 + 0.3, d1 - 0.2, STEEL, "Metal", VISUAL)
	end
	for k = 0, 5 do
		local x = x0 + 0.3 + k * 2.9
		kit:box(m, "FridgeDoor", x, x + 2.9, 0.8, 7, d0, d0 + 0.1, GLASS, "Glass", GLASS_OPTS)
		kit:box(m, "FridgeMullion", x, x + 0.12, 0.8, 7, d0 - 0.05, d0 + 0.1, STEEL, "Metal", VISUAL)
	end
	-- rows of bottles behind the glass (one long block each, read as a row through the glass)
	for _, y in { 4.4, 6.0 } do
		for k = 0, 1 do
			local x = x0 + 0.6 + k * 8.6
			kit:box(m, "Bottles", x, x + 8, y, y + 1.1, d0 + 0.5, d1 - 0.4, pack(), "Glass", VISUAL)
		end
	end
	-- the ice cream chest freezer: white, a glass lid, a striped band
	local fx0, fx1, fd0, fd1 = -7, -1, 18.4, 21
	kit:box(m, "Freezer", fx0, fx1, 0, 2.0, fd0, fd1, WHITE, "SmoothPlastic")
	kit:box(m, "FreezerBand", fx0, fx1, 1.2, 1.6, fd0 - 0.05, fd0, { 230, 60, 120 }, "SmoothPlastic", VISUAL)
	kit:box(m, "FreezerLid", fx0 + 0.1, fx1 - 0.1, 2.0, 2.1, fd0 + 0.1, fd1 - 0.1, GLASS, "Glass", GLASS_OPTS)
	return m
end

local function front(kit: Kit.Kit, parent: any)
	local m = kit:model(parent, "Front")
	-- the newspaper rack: a wire rack of three sloped trays
	kit:box(m, "NewsRack", 0, 3, 0, 2.3, -20.6, -19.2, STEEL, "Metal")
	for k = 0, 2 do
		kit:box(m, "Papers", 0.15, 2.85, 0.6 + k * 0.6, 0.75 + k * 0.6, -20.4, -19.4, WHITE, "SmoothPlastic", VISUAL)
	end
	-- the umbrella bin
	kit:cyl(m, "UmbrellaBin", -11.5, 0.6, -19.9, 1.2, 1.1, "Y", { 140, 40, 36 }, "Metal")
	-- the window display: a low plinth with the lawn chair on it
	kit:box(m, "WindowPlinth", 4, 9, 0, 0.4, -20.9, -16.4, { 60, 120, 80 }, "Fabric")
	return m
end

-- One item's place: the Sample, two more copies beside it (one for the big things), its price tag, its prompt.
local function slot(kit: Kit.Kit, parent: any, id: string, s: any, price: number)
	local r = kit.roblox
	local m = kit:model(parent, `Item_{id}`)
	m:SetAttribute("ItemId", id)
	m:SetAttribute("Price", price)
	m:SetAttribute("Fixture", s.fixture)
	local sample = Stock.build(kit, m, id, s.x, s.y, s.d, s.yaw)
	sample.Name = "Sample"
	-- the copies stand along the shelf (across the item's own facing)
	local size = Stock.SIZE[id]
	local big = size[1] > 1.5 or size[2] > 2.5
	local more = kit:model(m, "More")
	local turn = r.CFrame.Angles(0, s.yaw, 0)
	local across = turn * r.Vector3.new(1, 0, 0) -- the item's own X, in the Kit's Roblox-at-yaw-0 frame
	local gap = size[1] + 0.25
	if not big then
		for _, k in { -1, 1 } do
			local c = Stock.build(kit, more, id, s.x + across.X * gap * k, s.y, s.d - across.Z * gap * k, s.yaw)
			c.Name = "Copy"
		end
	end
	-- the price tag on the shelf's edge in front of the sample, its words toward the aisle
	local fwd = turn * r.Vector3.new(0, 0, 1)
	local reachOut = math.max(size[3], size[1] * 0.2) / 2 + 0.15
	local tx, td = s.x + fwd.X * reachOut, s.d - fwd.Z * reachOut
	local tag = kit:at(m, "PriceTag", tx, s.y - 0.12, td, 0.8, 0.3, 0.04, { 255, 250, 230 }, "SmoothPlastic", {
		collide = false,
		query = false,
		shadow = false,
		rot = turn,
	})
	local gui = kit:gui(tag, "Back", 60)
	kit:label(gui, { Text = Bank.amount(price), TextColor = { 200, 30, 30 }, Font = "FredokaOne" })
	-- the prompt's part: an invisible box round the sample, the prompt on it
	local grab = kit:at(
		m,
		"Grab",
		s.x,
		s.y + size[2] / 2,
		s.d,
		math.max(size[1], 0.6),
		math.max(size[2], 0.6),
		math.max(size[3], 0.6),
		{ 255, 255, 255 },
		"SmoothPlastic",
		{
			collide = false,
			query = false,
			shadow = false,
			transparency = 1,
			rot = turn,
		}
	)
	local p = r.Instance.new("ProximityPrompt")
	p.Name = "Take"
	p.ActionText = "Pick up"
	p.ObjectText = `{id}`
	p.HoldDuration = 0
	p.RequiresLineOfSight = false
	p.MaxActivationDistance = if s.fixture == "backbar" then Fixtures.FAR_REACH else Fixtures.REACH
	p:SetAttribute("StoreItem", id)
	p.Parent = grab
	return m
end

function Fixtures.build(kit: Kit.Kit, root: any, prices: { [string]: number }, names: { [string]: string }): number
	local fx = kit:model(root, "Fixtures")
	counter(kit, fx)
	for i, c in Fixtures.GONDOLAS do
		gondola(kit, fx, i, c)
	end
	walls(kit, fx)
	back(kit, fx)
	front(kit, fx)
	local items = kit:model(root, "Items")
	local n = 0
	for _, id in Stock.IDS do
		local s = (Fixtures.SLOTS :: any)[id]
		assert(s, "no shelf place for " .. id)
		if prices[id] == nil then
			continue -- (not on sale: its shelf place stays empty until it is)
		end
		local m = slot(kit, items, id, s, prices[id])
		local prompt = m.Grab.Take
		-- "Water gun, 60c": the wallet's name for it, capitalised, without its article
		local name = names[id] or id
		name = string.gsub(name, "^an? ", "")
		prompt.ObjectText = `{string.upper(string.sub(name, 1, 1))}{string.sub(name, 2)}, {Bank.amount(prices[id])}`
		n += 1
	end
	return n
end

return Fixtures
