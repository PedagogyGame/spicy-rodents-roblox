--!strict
-- tools/bake/alley/Concourse: what the shell leaves in the public floor of the eighteen-lane alley until the
-- rooms are dressed (brief addendum D5): a plain counter in every serving opening of Shared/Attractions/
-- AlleyLayout.OPENINGS (kind "counter": it stops COUNTER_GAP short of the opening's far end, where the staff walk
-- through; kind "window": the full width), a sign over every opening saying what is behind it, the snack tables
-- and their stools in two rows clear of the walk along the concourse, two benches by the shoe returns, and the
-- house balls on their shelves along the west aisle wall.
-- The front rooms themselves (the bowling ball shop, the shoe rental, the gift shop, the snack bar, the lockers)
-- are finished and EMPTY: whoever dresses a room replaces its counter here (models "Counter_<opening id>") and
-- adds the rest inside the room's rectangle (AlleyLayout.zone).
-- Interface: build(kit, root) -> nothing

local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")

local Concourse = {}
local L = AlleyLayout
local WOOD_DARK = { 70, 44, 28 }
local NAVY = { 40, 46, 80 }
local TOP = { 230, 220, 200 }
local T = L.PARTITION_T

-- the words over an opening, read from the side people come from
local SIGNS: { [string]: string } = {
	ball_shop_door = "BOWLING BALL SHOP",
	shoe_desk = "SHOE RENTAL  -  LANES",
	shoe_returns = "SHOE RETURNS",
	gift_shop_door = "GIFT SHOP",
	gift_lobby_door = "GIFT SHOP",
	snack_counter = "SNACK BAR",
	lockers = "LOCKERS",
}

local function counters(kit: any, m: any)
	for _, o in L.OPENINGS do
		if o.kind == "counter" or o.kind == "window" then
			local c = kit:model(m, `Counter_{o.id}`)
			c:SetAttribute("Opening", o.id)
			local a, b = o.a, if o.kind == "counter" then o.b - L.COUNTER_GAP else o.b
			-- the wall an opening is in stands on the low side of its line (AlleyLayout: at - T .. at) when it runs
			-- across the building, and centred on it when it runs down the building
			if o.axis == "x" then
				local mid = o.at - T / 2
				kit:box(c, "Base", a, b, 0, 3.6, mid - 0.9, mid + 0.9, NAVY, "SmoothPlastic")
				kit:box(c, "Top", a - 0.1, b + 0.1, 3.6, 3.8, mid - 1.1, mid + 1.1, TOP, "Marble")
				kit:box(c, "Stripe", a, b, 2.2, 2.6, mid + 0.9, mid + 0.94, { 232, 118, 40 }, "SmoothPlastic", {
					collide = false,
				})
			else
				local mid = o.at
				kit:box(c, "Base", mid - 0.9, mid + 0.9, 0, 3.6, a, b, NAVY, "SmoothPlastic")
				kit:box(c, "Top", mid - 1.1, mid + 1.1, 3.6, 3.8, a - 0.1, b + 0.1, TOP, "Marble")
				kit:box(c, "Stripe", mid + 0.9, mid + 0.94, 2.2, 2.6, a, b, { 232, 118, 40 }, "SmoothPlastic", {
					collide = false,
				})
			end
		end
	end
end

local function signs(kit: any, m: any)
	for _, o in L.OPENINGS do
		local text = SIGNS[o.id]
		if text then
			local mid = (o.a + o.b) / 2
			local half = math.min((o.b - o.a) / 2, 5.5)
			local y0, y1 = o.head + 0.25, math.min(o.head + 1.75, L.CEILING_Y - 0.3)
			local board, face
			if o.axis == "x" then
				board = kit:box(
					m,
					`Sign_{o.id}`,
					mid - half,
					mid + half,
					y0,
					y1,
					o.at + 0.02,
					o.at + 0.08,
					{ 26, 30, 60 },
					"SmoothPlastic",
					{
						collide = false,
					}
				)
				face = "Front" -- toward the lanes
			else
				-- on the lobby's side of the wall
				local lz = L.zone("lobby")
				local plus = (lz.x0 + lz.x1) / 2 > o.at
				local x0 = if plus then o.at + T / 2 + 0.02 else o.at - T / 2 - 0.08
				board = kit:box(
					m,
					`Sign_{o.id}`,
					x0,
					x0 + 0.06,
					y0,
					y1,
					mid - half,
					mid + half,
					{ 26, 30, 60 },
					"SmoothPlastic",
					{
						collide = false,
					}
				)
				face = if plus then "Right" else "Left" -- into the lobby
			end
			kit:label(kit:gui(board, face, 30), { Text = text, TextColor = { 255, 214, 92 }, Font = "FredokaOne" })
		end
	end
end

local function tables(kit: any, m: any)
	-- two rows in front of the snack bar, either side of the walk along the concourse (AlleyLayout.ROUTES.concourse)
	local spots = { { 60, -41.5 }, { 68, -41.5 }, { 76, -41.5 }, { 64, -30.5 }, { 72, -30.5 }, { 80, -30.5 } }
	for i, t in spots do
		local tx, td = t[1], t[2]
		kit:cyl(m, `TableTop{i}`, tx, 2.5, td, 0.12, 2.4, "Y", { 230, 120, 40 }, "SmoothPlastic")
		kit:cyl(m, "TablePost", tx, 1.25, td, 2.4, 0.25, "Y", { 60, 60, 64 }, "Metal")
		kit:cyl(m, "TableFoot", tx, 0.05, td, 0.1, 1.2, "Y", { 60, 60, 64 }, "Metal")
		for a = 0, 2 do
			local ang = a * 2.1 + i
			local sx, sd = tx + math.cos(ang) * 1.9, td + math.sin(ang) * 1.9
			kit:cyl(m, "Stool", sx, 1.6, sd, 0.25, 1.1, "Y", { 36, 150, 150 }, "Fabric")
			kit:cyl(m, "StoolPost", sx, 0.8, sd, 1.5, 0.18, "Y", { 60, 60, 64 }, "Metal")
		end
	end
	-- benches for changing shoes, by the returns window
	for _, bx in { -1, 7 } do
		kit:box(m, "ShoeBench", bx, bx + 6, 1.3, 1.6, -43.4, -41.8, { 222, 104, 40 }, "Fabric")
		for _, lx in { bx + 0.5, bx + 5.5 } do
			kit:box(m, "ShoeBenchLeg", lx - 0.15, lx + 0.15, 0, 1.3, -43.2, -42.0, { 60, 60, 64 }, "Metal")
		end
	end
end

local function houseBalls(kit: any, m: any)
	local cols = {
		{ 200, 40, 40 },
		{ 40, 80, 190 },
		{ 40, 150, 80 },
		{ 230, 196, 40 },
		{ 140, 50, 160 },
		{ 20, 20, 24 },
		{ 230, 120, 40 },
	}
	for shelf = 0, 2 do
		local y = 0.9 + shelf * 1.4
		kit:box(m, "BallShelf", L.X0, L.X0 + 1.4, y - 0.1, y, -12, 12, WOOD_DARK, "Wood")
		for b = 0, 22 do
			local col = cols[((b + shelf * 3) % #cols) + 1]
			kit:ball(m, "ShelfBall", L.X0 + 0.7, y + L.BALL_D / 2, -11.5 + b * 1.02, L.BALL_D, col, "SmoothPlastic", {
				reflectance = 0.12,
			})
		end
	end
end

function Concourse.build(kit: any, root: any)
	local m = kit:model(root, "Concourse")
	counters(kit, m)
	signs(kit, m)
	tables(kit, m)
	houseBalls(kit, m)
end

return Concourse
