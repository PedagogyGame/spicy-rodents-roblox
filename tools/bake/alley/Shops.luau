--!strict
-- tools/bake/alley/Shops: the front rooms' fittings (brief addendum D5: "a bowling ball shop and gift shop, and
-- bowling shoe rental detailed"), plain parts in the alley's style, each inside its room's rectangle
-- (Shared/Attractions/AlleyLayout.zone), against a wall, and off every staff post and walking route (the alley's walk
-- test, tests/unit/attractions_alley_bake, walks them all; the employees' loops, Shared/Attractions/AlleyStaff, are
-- held clear by tests/unit/alley_staff):
--   BallShop     the wall of balls (three tiers on the west wall), the glass display case with the till where the
--                clerk stands, the drilling bench with its drill press on the front wall, the bag rack on the east
--                wall, the PRO SHOP board;
--   ShoeRental   the cubbies by size on the west wall (six columns, sizes 6 to 13 across, pairs in most), the spray
--                bench where returned pairs are sprayed, the till, pairs and a spray can on the desk;
--   GiftShop     the souvenir shelves on the east wall (plush acorns, little pins, mugs, folded shirts), the cash
--                desk on the front wall, a display table behind each shopfront window (a big plush pin and two
--                trophies; three bowling-ball money boxes), the SOUVENIRS board;
--   SnackBar     the grill and fryer on the front wall with a hood, the fridge on the east wall, the till on the
--                counter (the front desk's work stops: AlleyStaff "front_desk").
-- Nothing here is sold (the owner's call: the goods are for the look; a till is a till). Budget: BUDGET parts.
-- Interface: build(kit, root) -> nothing; BUDGET

local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")

local Shops = {}

Shops.BUDGET = 200

local L = AlleyLayout
local WOOD = { 120, 82, 50 }
local WOOD_DARK = { 70, 44, 28 }
local NAVY = { 40, 46, 80 }
local STEEL = { 150, 154, 160 }
local DARK = { 46, 48, 52 }
local TOP = { 230, 220, 200 }
local GLASS = { 200, 225, 235 }
local SIGN_BG = { 26, 30, 60 }
local GOLD = { 255, 214, 92 }
-- bowling-ball colours (swirls read as solid colours at this size)
local BALLS = {
	{ 180, 30, 40 },
	{ 30, 60, 160 },
	{ 110, 40, 140 },
	{ 20, 130, 140 },
	{ 230, 120, 30 },
	{ 30, 30, 34 },
	{ 220, 90, 150 },
	{ 200, 180, 40 },
}
-- bowling shoes: two-tone pairs (a pair is one block at this size)
local SHOES = { { 150, 40, 40 }, { 40, 70, 150 }, { 90, 60, 40 }, { 60, 60, 66 } }

local NOCOL = { collide = false }

local function board(
	kit: any,
	m: any,
	name: string,
	x0: number,
	x1: number,
	y0: number,
	y1: number,
	d0: number,
	d1: number,
	face: string,
	text: string
)
	local b = kit:box(m, name, x0, x1, y0, y1, d0, d1, SIGN_BG, "SmoothPlastic", NOCOL)
	kit:label(kit:gui(b, face, 30), { Text = text, TextColor = GOLD, Font = "FredokaOne" })
	return b
end

local function till(kit: any, m: any, x: number, y: number, d: number)
	kit:box(m, "Till", x - 0.45, x + 0.45, y, y + 0.45, d - 0.35, d + 0.35, DARK, "SmoothPlastic", NOCOL)
	kit:box(
		m,
		"TillScreen",
		x - 0.35,
		x + 0.35,
		y + 0.45,
		y + 0.95,
		d - 0.05,
		d + 0.05,
		{ 60, 90, 110 },
		"Glass",
		NOCOL
	)
end

-- THE BOWLING BALL SHOP ------------------------------------------------------------------------------------------
local function ballShop(kit: any, root: any)
	local z = L.zone("ball_shop")
	local m = kit:model(root, "BallShop")
	-- the wall of balls: three tiers on the west wall
	local x0, x1 = z.x0, z.x0 + 1.4
	local d0, d1 = -65, -51
	for _, d in { d0, (d0 + d1) / 2, d1 } do
		kit:box(m, "RackPost", x0, x1, 0, 4.6, d - 0.1, d + 0.1, WOOD_DARK, "Wood")
	end
	for tier, y in { 0.6, 2.0, 3.4 } do
		kit:box(m, "RackShelf", x0, x1, y - 0.15, y, d0 + 0.1, d1 - 0.1, WOOD, "Wood")
		kit:box(m, "RackLip", x1 - 0.1, x1, y, y + 0.2, d0 + 0.1, d1 - 0.1, WOOD_DARK, "Wood", NOCOL)
		local n = 12
		for k = 0, n - 1 do
			local col = BALLS[((k + tier * 3) % #BALLS) + 1]
			kit:ball(
				m,
				"Ball",
				(x0 + x1) / 2,
				y + L.BALL_D / 2,
				d0 + 0.65 + k * (d1 - d0 - 1.3) / (n - 1),
				L.BALL_D,
				col,
				"SmoothPlastic",
				{
					reflectance = 0.15,
				}
			)
		end
	end
	board(kit, m, "RackSign", z.x0 + 0.05, z.x0 + 0.15, 5.2, 6.4, -63, -53, "Right", "PRO BALLS")
	-- the glass display case and the till (the clerk stands behind it at the ball_counter post)
	do
		local cx0, cx1, cd0, cd1 = -10, -4, -50.9, -49.8
		kit:box(m, "CaseBase", cx0, cx1, 0, 2.4, cd0, cd1, WOOD, "Wood")
		kit:box(m, "CaseGlass", cx0, cx1, 2.4, 3.6, cd0, cd1, GLASS, "Glass", { transparency = 0.6 })
		kit:box(m, "CaseTop", cx0 - 0.05, cx1 + 0.05, 3.6, 3.72, cd0 - 0.05, cd1 + 0.05, TOP, "Marble")
		for k = 0, 2 do
			kit:ball(
				m,
				"CaseBall",
				cx0 + 1.2 + k * 1.8,
				2.4 + L.BALL_D / 2,
				(cd0 + cd1) / 2,
				L.BALL_D,
				BALLS[k + 2],
				"SmoothPlastic",
				{
					reflectance = 0.25,
					collide = false,
				}
			)
		end
		till(kit, m, cx1 - 0.8, 3.72, (cd0 + cd1) / 2)
	end
	-- the drilling bench on the front wall: a bench, a drill press, a ball in its cup
	do
		local bx0, bx1, bd0, bd1 = -23.5, -16.5, z.d0, z.d0 + 1.4
		kit:box(m, "Bench", bx0, bx1, 0, 3.0, bd0, bd1, STEEL, "DiamondPlate")
		kit:box(m, "BenchTop", bx0, bx1, 3.0, 3.15, bd0, bd1 + 0.05, WOOD_DARK, "Wood")
		local px, pd = -18.5, bd0 + 0.6
		kit:cyl(m, "DrillColumn", px, 4.8, pd, 3.3, 0.3, "Y", DARK, "Metal")
		kit:box(
			m,
			"DrillHead",
			px - 0.4,
			px + 0.4,
			5.6,
			6.4,
			pd - 0.3,
			pd + 0.6,
			{ 200, 60, 40 },
			"SmoothPlastic",
			NOCOL
		)
		kit:cyl(m, "DrillChuck", px, 5.2, pd + 0.35, 0.8, 0.18, "Y", STEEL, "Metal", NOCOL)
		kit:cyl(m, "BallCup", px, 3.3, pd + 0.35, 0.3, 0.7, "Y", DARK, "Metal", NOCOL)
		kit:ball(m, "DrillBall", px, 3.45 + L.BALL_D / 2, pd + 0.35, L.BALL_D, BALLS[3], "SmoothPlastic", NOCOL)
		board(kit, m, "ProShopSign", -23, -17, 7.2, 8.4, z.d0 + 0.05, z.d0 + 0.15, "Front", "PRO SHOP")
	end
	-- the bag rack on the east wall
	do
		local rx0, rx1, rd0, rd1 = z.x1 - 1.6, z.x1, -66, -58
		kit:box(m, "BagRack", rx1 - 0.15, rx1, 0, 4.4, rd0, rd1, WOOD_DARK, "Wood")
		for _, y in { 1.2, 2.9 } do
			kit:box(m, "BagShelf", rx0, rx1, y - 0.12, y, rd0, rd1, WOOD, "Wood")
		end
		for k = 0, 3 do
			local y = if k < 2 then 1.2 else 2.9
			local d = rd0 + 1.2 + (k % 2) * 4.2
			kit:box(
				m,
				"Bag",
				rx0 + 0.2,
				rx1 - 0.25,
				y,
				y + 1.1,
				d,
				d + 2.4,
				BALLS[(k * 2) % #BALLS + 1],
				"Fabric",
				NOCOL
			)
		end
	end
end

-- THE SHOE RENTAL -------------------------------------------------------------------------------------------------
local SIZES = { "6-7", "8", "9", "10", "11", "12-13" }

local function shoeRental(kit: any, root: any)
	local z = L.zone("shoe_rental")
	local m = kit:model(root, "ShoeRental")
	-- the cubbies by size on the west wall: six columns (one size each), six rows
	local x0, x1 = z.x0, z.x0 + 1.5
	local d0, d1 = z.d0 + 0.4, -58.6
	local y1 = 6.6
	kit:box(m, "CubbyBack", x0, x0 + 0.1, 0, y1, d0, d1, WOOD_DARK, "Wood")
	for _, d in { d0, d1 } do
		kit:box(m, "CubbySide", x0, x1, 0, y1, d - 0.08, d + 0.08, WOOD, "Wood")
	end
	kit:box(m, "CubbyTop", x0, x1, y1 - 0.12, y1, d0, d1, WOOD, "Wood")
	local cols, rows = #SIZES, 6
	local colW = (d1 - d0) / cols
	for k = 1, cols - 1 do
		local d = d0 + k * colW
		kit:box(m, "CubbyDivider", x0 + 0.1, x1, 0.1, y1 - 0.12, d - 0.05, d + 0.05, WOOD, "Wood", NOCOL)
	end
	local rowH = (y1 - 0.12) / rows
	for r = 1, rows - 1 do
		local y = r * rowH
		kit:box(m, "CubbyShelf", x0 + 0.1, x1, y - 0.06, y, d0, d1, WOOD, "Wood")
	end
	-- pairs in most cubbies (every column has some out on the desk)
	for c = 0, cols - 1 do
		for r = 0, rows - 1 do
			if (c * 7 + r * 3) % 5 ~= 0 then
				local dm = d0 + (c + 0.5) * colW
				local y = r * rowH + 0.02
				local col = SHOES[((c + r) % #SHOES) + 1]
				kit:box(m, "Pair", x0 + 0.25, x1 - 0.15, y, y + 0.42, dm - 0.5, dm + 0.5, col, "Leather", NOCOL)
			end
		end
	end
	-- the sizes across the top, read from the room
	local labels = kit:box(m, "SizeStrip", x1, x1 + 0.06, y1 + 0.1, y1 + 0.8, d0, d1, SIGN_BG, "SmoothPlastic", NOCOL)
	local gui = kit:gui(labels, "Right", 30)
	for c, s in SIZES do
		kit:label(gui, {
			Text = s,
			TextColor = GOLD,
			Font = "FredokaOne",
			Size = { 1 / cols, 1 },
			-- (read from the room, facing -X, +D is to the right)
			Pos = { (c - 1) / cols, 0 },
		})
	end
	-- the spray bench: a cabinet, two cans, a pair being sprayed
	do
		local bd0, bd1 = -57.6, -53.4
		kit:box(m, "SprayBench", x0, x0 + 2.0, 0, 3.0, bd0, bd1, NAVY, "SmoothPlastic")
		kit:box(m, "SprayTop", x0, x0 + 2.05, 3.0, 3.12, bd0, bd1, TOP, "Marble")
		for k, d in { bd0 + 0.6, bd0 + 1.3 } do
			kit:cyl(m, "SprayCan", x0 + 0.5, 3.12 + 0.45, d, 0.9, 0.36, "Y", { 230, 230, 236 }, "Metal", NOCOL)
			kit:cyl(
				m,
				"SprayCap",
				x0 + 0.5,
				3.12 + 1.0,
				d,
				0.2,
				0.26,
				"Y",
				if k == 1 then { 40, 110, 200 } else { 200, 60, 60 },
				"SmoothPlastic",
				NOCOL
			)
		end
		kit:box(m, "SprayPair", x0 + 0.6, x0 + 1.6, 3.12, 3.55, bd1 - 1.8, bd1 - 0.6, SHOES[2], "Leather", NOCOL)
	end
	-- on the desk (the plain counter of Concourse in the shoe_desk opening): the till, two pairs, a spray can
	do
		local o = L.opening("shoe_desk")
		local top = 3.8
		till(kit, m, o.at - 0.3, top, o.a + 1.2)
		for k = 0, 1 do
			local d = o.a + 3 + k * 1.4
			kit:box(
				m,
				"DeskPair",
				o.at - 0.6,
				o.at + 0.4,
				top,
				top + 0.42,
				d - 0.5,
				d + 0.5,
				SHOES[k + 1],
				"Leather",
				NOCOL
			)
		end
		kit:cyl(m, "DeskSpray", o.at - 0.4, top + 0.45, o.b - 4.2, 0.9, 0.36, "Y", { 230, 230, 236 }, "Metal", NOCOL)
	end
end

-- THE GIFT SHOP ---------------------------------------------------------------------------------------------------
local function giftShop(kit: any, root: any)
	local z = L.zone("gift_shop")
	local m = kit:model(root, "GiftShop")
	-- the souvenir shelves on the east wall
	local x0, x1 = z.x1 - 1.7, z.x1
	local d0, d1 = -66, -50
	kit:box(m, "ShelfBack", x1 - 0.1, x1, 0, 6.2, d0, d1, WOOD_DARK, "Wood")
	for _, d in { d0, d1 } do
		kit:box(m, "ShelfSide", x0, x1, 0, 6.2, d - 0.08, d + 0.08, WOOD, "Wood")
	end
	local shelves = { 0.9, 2.2, 3.5, 4.8 }
	for _, y in shelves do
		kit:box(m, "Shelf", x0, x1, y - 0.12, y, d0 + 0.08, d1 - 0.08, WOOD, "Wood")
	end
	local xm = (x0 + x1) / 2 - 0.1
	-- plush acorns
	for k = 0, 5 do
		local d = d0 + 1.4 + k * 2.6
		kit:ball(m, "PlushAcorn", xm, shelves[1] + 0.4, d, 0.8, { 150, 100, 55 }, "Fabric", NOCOL)
	end
	-- little souvenir pins
	for k = 0, 7 do
		local d = d0 + 1 + k * 2
		kit:cyl(m, "MiniPin", xm, shelves[2] + 0.5, d, 1.0, 0.36, "Y", { 246, 246, 240 }, "SmoothPlastic", NOCOL)
	end
	-- mugs
	for k = 0, 5 do
		local d = d0 + 1.4 + k * 2.6
		kit:cyl(m, "Mug", xm, shelves[3] + 0.3, d, 0.6, 0.55, "Y", BALLS[(k % 4) + 1], "SmoothPlastic", NOCOL)
	end
	-- folded shirts
	for k = 0, 4 do
		local d = d0 + 1.2 + k * 3.2
		kit:box(
			m,
			"Shirt",
			x0 + 0.3,
			x1 - 0.3,
			shelves[4],
			shelves[4] + 0.25,
			d,
			d + 1.6,
			BALLS[(k + 3) % #BALLS + 1],
			"Fabric",
			NOCOL
		)
	end
	board(kit, m, "SouvenirSign", x1 - 0.15, x1 - 0.05, 6.6, 7.8, -63, -53, "Left", "SOUVENIRS")
	-- the cash desk on the front wall
	do
		local cx0, cx1, cd0, cd1 = 41, 51, z.d0, z.d0 + 1.6
		kit:box(m, "Desk", cx0, cx1, 0, 3.6, cd0, cd1, NAVY, "SmoothPlastic")
		kit:box(m, "DeskTop", cx0 - 0.05, cx1 + 0.05, 3.6, 3.75, cd0, cd1 + 0.1, TOP, "Marble")
		till(kit, m, 46, 3.75, cd0 + 0.8)
		for k = 0, 1 do
			local x = 48.5 + k * 1.2
			kit:box(
				m,
				"GiftBag",
				x - 0.4,
				x + 0.4,
				3.75,
				4.85,
				cd0 + 0.4,
				cd0 + 1.0,
				BALLS[k * 3 + 1],
				"SmoothPlastic",
				NOCOL
			)
		end
	end
	-- a display table behind each shopfront window
	local tx0, tx1 = z.x0 + 0.6, z.x0 + 3.2
	do
		local td0, td1 = -66.5, -62.2
		kit:box(m, "WindowTable", tx0, tx1, 0, 2.6, td0, td1, WOOD, "Wood")
		local px, pd = (tx0 + tx1) / 2, td0 + 1.2
		kit:cyl(m, "PlushPinBody", px, 2.6 + 1.0, pd, 2.0, 1.1, "Y", { 246, 246, 240 }, "Fabric", NOCOL)
		kit:ball(m, "PlushPinHead", px, 2.6 + 2.3, pd, 0.8, { 246, 246, 240 }, "Fabric", NOCOL)
		kit:cyl(m, "PlushPinStripe", px, 2.6 + 1.85, pd, 0.2, 0.75, "Y", { 200, 30, 40 }, "Fabric", NOCOL)
		for k = 0, 1 do
			local d = td1 - 0.9 - k * 1.3
			kit:cyl(m, "TrophyBase", px, 2.6 + 0.15, d, 0.3, 0.6, "Y", WOOD_DARK, "Wood", NOCOL)
			kit:cyl(m, "TrophyCup", px, 2.6 + 0.75, d, 0.9, 0.45, "Y", { 220, 180, 70 }, "Metal", NOCOL)
		end
	end
	do
		local td0, td1 = -52.6, -49.6
		kit:box(m, "WindowTable", tx0, tx1, 0, 2.6, td0, td1, WOOD, "Wood")
		for k = 0, 2 do
			kit:ball(
				m,
				"MoneyBox",
				(tx0 + tx1) / 2,
				2.6 + 0.4,
				td0 + 0.6 + k * 0.9,
				0.8,
				BALLS[k + 5],
				"SmoothPlastic",
				NOCOL
			)
		end
	end
end

-- THE SNACK BAR'S KITCHEN -----------------------------------------------------------------------------------------
local function snackBar(kit: any, root: any)
	local z = L.zone("snack_bar")
	local m = kit:model(root, "SnackKitchen")
	local gx0, gx1, gd0, gd1 = 66, 75, z.d0, z.d0 + 1.6
	kit:box(m, "Cooker", gx0, gx1, 0, 3.2, gd0, gd1, STEEL, "DiamondPlate")
	kit:box(m, "Griddle", gx0 + 0.3, gx0 + 5, 3.2, 3.35, gd0 + 0.2, gd1 - 0.2, DARK, "Metal", NOCOL)
	kit:box(m, "Fryer", gx0 + 5.6, gx1 - 0.4, 3.2, 3.9, gd0 + 0.2, gd1 - 0.2, STEEL, "Metal", NOCOL)
	kit:box(m, "Hood", gx0 - 0.2, gx1 + 0.2, 7.4, 8.6, gd0, gd1 + 0.6, STEEL, "Metal", NOCOL)
	local fx0, fx1, fd0, fd1 = z.x1 - 1.0, z.x1, -64, -60
	kit:box(m, "Fridge", fx0, fx1, 0, 6.5, fd0, fd1, { 230, 232, 236 }, "SmoothPlastic")
	kit:box(m, "FridgeDoor", fx0 - 0.06, fx0, 0.4, 6.2, fd0 + 0.2, fd1 - 0.2, GLASS, "Glass", {
		transparency = 0.4,
		collide = false,
	})
	local o = L.opening("snack_counter")
	till(kit, m, o.a + 2, 3.8, o.at - L.PARTITION_T / 2)
end

function Shops.build(kit: any, root: any)
	local before = kit.count
	ballShop(kit, root)
	shoeRental(kit, root)
	giftShop(kit, root)
	snackBar(kit, root)
	root:SetAttribute("ShopParts", kit.count - before)
end

return Shops
