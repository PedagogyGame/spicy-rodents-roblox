--!strict
-- tools/bake/alley/Rooms: everything around the lanes (brief v2 §13a): the concourse (front desk and shoe counter
-- with cubbies, the snack bar with its menu board, tables, house-ball shelves), the games room (two pool
-- tables racked and ready, a bumper pool table, the dartboard on the wall beside the pool tables with its
-- oche, three pinball machines in distinct themes, and in the corner by the ferns Madame Acorna, the
-- fortune-teller cabinet), the back of house behind the pinsetters (workbench, shelves, spare pins, the
-- mechanic's cart, a mop bucket, fluorescent tubes, EMPLOYEES ONLY) and the alley props (three big round
-- dark-blue trash cans beside the tunnel vents, the push broom leaning by the door, crates).
-- Names the server relies on: GamesRoom.Dartboard (Face part "BoardFace"), GamesRoom.Fortune.{Lever, Reel1..3,
-- CardSlot}, GamesRoom.Pool<i>, GamesRoom.Pinball<i>, GamesRoom.BumperPool.
-- Interface: build(kit, root) -> nothing

local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")

local Rooms = {}
local L = AlleyLayout

local WOOD = { 104, 66, 40 }
local WOOD_DARK = { 70, 44, 28 }
local FELT = { 30, 110, 70 }
local BRASS = { 196, 160, 80 }
local BLACK = { 24, 24, 26 }

local function concourse(kit: any, root: any)
	local m = kit:model(root, "Concourse")
	-- front desk / shoe counter along the left wall
	local cx0, cx1 = -21.5, -19.5
	kit:box(m, "Counter", cx0, cx1, 0, 3.6, -44, -28, { 40, 46, 80 }, "SmoothPlastic")
	kit:box(m, "CounterTop", cx0 - 0.2, cx1 + 0.3, 3.6, 3.8, -44.2, -27.8, { 230, 220, 200 }, "Marble")
	kit:box(
		m,
		"CounterStripe",
		cx1,
		cx1 + 0.04,
		2.2,
		2.6,
		-44,
		-28,
		{ 232, 118, 40 },
		"SmoothPlastic",
		{ collide = false }
	)
	kit:box(m, "Register", cx0 + 0.3, cx0 + 1.3, 3.8, 4.6, -31, -29.8, { 40, 40, 44 }, "SmoothPlastic")
	kit:box(
		m,
		"RegisterScreen",
		cx0 + 1.3,
		cx0 + 1.34,
		4.0,
		4.5,
		-30.9,
		-29.9,
		{ 90, 200, 140 },
		"Neon",
		{ collide = false }
	)
	-- shoe cubbies on the wall behind (pairs of two-tone bowling shoes)
	local shoeCols = { { 200, 40, 40 }, { 40, 60, 160 }, { 30, 30, 30 }, { 230, 220, 200 } }
	local k = 0
	for row = 0, 5 do
		for col = 0, 11 do
			local d0 = -44 + col * 1.3
			local y0 = 0.6 + row * 1.0
			kit:box(m, "Cubby", L.X0, L.X0 + 1.4, y0, y0 + 0.08, d0, d0 + 1.3, WOOD_DARK, "Wood", { collide = false })
			k += 1
			if (k * 7) % 5 ~= 0 then
				local c1 = shoeCols[(k % #shoeCols) + 1]
				for s = 0, 1 do
					kit:box(
						m,
						"Shoe",
						L.X0 + 0.2,
						L.X0 + 1.2,
						y0 + 0.08,
						y0 + 0.4,
						d0 + 0.15 + s * 0.52,
						d0 + 0.6 + s * 0.52,
						c1,
						"Fabric",
						{
							collide = false,
						}
					)
				end
			end
		end
	end
	kit:box(m, "CubbyFrame", L.X0, L.X0 + 1.5, 0, 6.8, -44.1, -44, WOOD_DARK, "Wood")
	kit:box(m, "CubbyFrame", L.X0, L.X0 + 1.5, 0, 6.8, -28.4, -28.3, WOOD_DARK, "Wood")
	local shoeSign = kit:box(
		m,
		"ShoeSign",
		L.X0 + 0.1,
		L.X0 + 0.2,
		7.2,
		9.0,
		-42,
		-30,
		{ 26, 30, 60 },
		"SmoothPlastic",
		{ collide = false }
	)
	kit:label(
		kit:gui(shoeSign, "Right", 40),
		{ Text = "SHOES  &  LANES", TextColor = { 255, 214, 92 }, Font = "FredokaOne" }
	)
	local deskSign = kit:box(
		m,
		"DeskSign",
		cx1 + 0.02,
		cx1 + 0.08,
		0.6,
		2.0,
		-40,
		-32,
		{ 26, 30, 60 },
		"SmoothPlastic",
		{ collide = false }
	)
	kit:label(
		kit:gui(deskSign, "Right", 40),
		{ Text = "FREE BOWLING TODAY", TextColor = { 140, 236, 236 }, Font = "GothamBold" }
	)
	-- the snack bar on the right of the entrance
	kit:box(m, "SnackCounter", 12, 23, 0, 3.6, -40.5, -38.5, { 180, 70, 40 }, "SmoothPlastic")
	kit:box(m, "SnackTop", 11.8, 23.2, 3.6, 3.8, -40.7, -38.3, { 230, 220, 200 }, "Marble")
	kit:box(m, "SnackBack", 12, 25.4, 0, 3.4, -47.6, -46.6, { 140, 140, 146 }, "Metal")
	kit:box(m, "Fridge", 23, 25.4, 0, 6.5, -46.6, -44.4, { 200, 204, 210 }, "Metal")
	kit:box(
		m,
		"FridgeGlass",
		22.96,
		23.0,
		0.6,
		6.0,
		-46.2,
		-44.8,
		{ 150, 200, 220 },
		"Glass",
		{ collide = false, transparency = 0.3 }
	)
	kit:box(m, "NachoWarmer", 14, 16, 3.8, 5.0, -40.2, -39.0, { 200, 160, 60 }, "Glass", { transparency = 0.25 })
	kit:box(m, "SodaTower", 18.6, 20, 3.8, 5.6, -46.4, -45.4, { 60, 60, 64 }, "Metal")
	local menu = kit:box(
		m,
		"MenuBoard",
		12.5,
		22.5,
		7.0,
		10.2,
		-47.6,
		-47.5,
		{ 22, 22, 26 },
		"SmoothPlastic",
		{ collide = false }
	)
	local mg = kit:gui(menu, "Front", 30)
	kit:label(mg, { Text = "SNACK BAR", TextColor = { 255, 214, 92 }, Font = "FredokaOne", Size = { 1, 0.32 } })
	kit:label(mg, {
		Text = "NACHOS 5c   SODA 4c   COFFEE 12c   ICE CREAM 5c",
		TextColor = { 240, 240, 240 },
		Font = "GothamBold",
		Size = { 1, 0.3 },
		Pos = { 0, 0.42 },
	})
	kit:label(mg, {
		Text = "no squirrels behind the counter",
		TextColor = { 150, 236, 236 },
		Font = "Gotham",
		Size = { 1, 0.18 },
		Pos = { 0, 0.78 },
	})
	-- tables and chairs in the middle of the concourse
	for i, t in { { -8, -36 }, { 0, -32 }, { 8, -36 }, { -4, -42 }, { 6, -43 } } do
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
	-- house balls on shelves along the left aisle wall
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
			kit:ball(
				m,
				"ShelfBall",
				L.X0 + 0.7,
				y + L.BALL_D / 2,
				-11.5 + b * 1.02,
				L.BALL_D,
				col,
				"SmoothPlastic",
				{ reflectance = 0.12 }
			)
		end
	end
	-- lights over the desk and the snack bar
	local l1 = kit:box(
		m,
		"DeskPendant",
		-21,
		-19.8,
		L.CEILING_Y - 2.4,
		L.CEILING_Y - 2.2,
		-38,
		-34,
		{ 255, 236, 200 },
		"Neon",
		{ collide = false }
	)
	kit:light(l1, "PointLight", { Range = 18, Brightness = 1.2, Color = { 255, 230, 196 } })
	local l2 = kit:box(
		m,
		"SnackPendant",
		16,
		19,
		L.CEILING_Y - 2.4,
		L.CEILING_Y - 2.2,
		-44,
		-42,
		{ 255, 236, 200 },
		"Neon",
		{ collide = false }
	)
	kit:light(l2, "PointLight", { Range = 18, Brightness = 1.2, Color = { 255, 230, 196 } })
	local l3 = kit:box(
		m,
		"ConcourseTroffer",
		-6,
		6,
		L.CEILING_Y - 0.12,
		L.CEILING_Y,
		-38,
		-36,
		{ 250, 248, 238 },
		"Neon",
		{ collide = false }
	)
	kit:light(l3, "PointLight", { Range = 24, Brightness = 0.9, Color = { 255, 244, 226 } })
end

-- A pool table: frame, felt, cushions, pockets, legs; the 15 balls racked and the cue ball spotted.
local POOL_COLS = {
	{ 240, 200, 40 },
	{ 30, 60, 170 },
	{ 200, 30, 30 },
	{ 90, 40, 140 },
	{ 230, 110, 30 },
	{ 30, 120, 60 },
	{ 120, 30, 30 },
	{ 20, 20, 20 },
}
local function poolTable(kit: any, parent: any, name: string, cx: number, cd: number)
	local m = kit:model(parent, name)
	local hl, hw = 5.4, 2.7 -- playing surface half length (D) and half width (X)
	local top = 3.0
	kit:box(m, "Felt", cx - hw, cx + hw, top - 0.3, top, cd - hl, cd + hl, FELT, "Fabric")
	kit:box(m, "Slate", cx - hw - 0.7, cx + hw + 0.7, top - 1.0, top - 0.3, cd - hl - 0.7, cd + hl + 0.7, WOOD, "Wood")
	for side = -1, 1, 2 do
		kit:box(
			m,
			"RailLong",
			cx + side * (hw + 0.35) - 0.35,
			cx + side * (hw + 0.35) + 0.35,
			top - 0.3,
			top + 0.35,
			cd - hl - 0.7,
			cd + hl + 0.7,
			WOOD,
			"Wood"
		)
		kit:box(
			m,
			"CushionLong",
			cx + side * (hw - 0.08) - 0.08,
			cx + side * (hw - 0.08) + 0.08,
			top,
			top + 0.22,
			cd - hl,
			cd + hl,
			{ 26, 96, 60 },
			"Fabric"
		)
		kit:box(
			m,
			"RailShort",
			cx - hw - 0.7,
			cx + hw + 0.7,
			top - 0.3,
			top + 0.35,
			cd + side * (hl + 0.35) - 0.35,
			cd + side * (hl + 0.35) + 0.35,
			WOOD,
			"Wood"
		)
		kit:box(
			m,
			"CushionShort",
			cx - hw,
			cx + hw,
			top,
			top + 0.22,
			cd + side * (hl - 0.08) - 0.08,
			cd + side * (hl - 0.08) + 0.08,
			{ 26, 96, 60 },
			"Fabric"
		)
		for _, pd in { -hl, 0, hl } do
			kit:cyl(
				m,
				"Pocket",
				cx + side * hw,
				top + 0.01,
				cd + pd,
				0.06,
				0.62,
				"Y",
				BLACK,
				"SmoothPlastic",
				{ collide = false }
			)
		end
		for _, ld in { -hl + 0.6, hl - 0.6 } do
			kit:box(
				m,
				"Leg",
				cx + side * (hw + 0.1) - 0.4,
				cx + side * (hw + 0.1) + 0.4,
				0,
				top - 1.0,
				cd + ld - 0.4,
				cd + ld + 0.4,
				WOOD_DARK,
				"Wood"
			)
		end
	end
	for k = 0, 2 do
		kit:cyl(
			m,
			"Diamond",
			cx - hw - 0.35,
			top + 0.36,
			cd - hl / 2 + k * hl / 2,
			0.02,
			0.12,
			"Y",
			{ 236, 236, 220 },
			"SmoothPlastic",
			{ collide = false }
		)
	end
	-- the rack at the foot spot (+D), cue ball at the head spot
	local br = 0.24
	local footD = cd + hl / 2
	local n = 0
	for row = 0, 4 do
		for i = 0, row do
			n += 1
			local bx = cx + (i - row / 2) * br * 2.02
			local bd = footD + row * br * 1.75
			local col = POOL_COLS[((n - 1) % 8) + 1]
			if n == 5 then
				col = BLACK
			end
			kit:ball(m, "PoolBall", bx, top + br, bd, br * 2, col, "SmoothPlastic", { reflectance = 0.1 })
		end
	end
	kit:ball(m, "CueBall", cx, top + br, cd - hl / 2, br * 2, { 245, 245, 240 }, "SmoothPlastic", { reflectance = 0.1 })
	-- a cue lying on the rail
	kit:cyl(m, "Cue", cx + hw + 0.35, top + 0.45, cd, 9.6, 0.1, "D", { 214, 180, 120 }, "Wood", { collide = false })
	-- the lamp over the table (green shades, real light)
	kit:box(m, "LampBar", cx - 0.15, cx + 0.15, 8.2, 8.4, cd - 4, cd + 4, BRASS, "Metal", { collide = false })
	for _, ld in { -3, 0, 3 } do
		kit:box(
			m,
			"Shade",
			cx - 0.8,
			cx + 0.8,
			7.6,
			8.2,
			cd + ld - 0.8,
			cd + ld + 0.8,
			{ 20, 90, 50 },
			"Glass",
			{ collide = false }
		)
		kit:box(
			m,
			"Bulb",
			cx - 0.5,
			cx + 0.5,
			7.55,
			7.62,
			cd + ld - 0.5,
			cd + ld + 0.5,
			{ 255, 236, 190 },
			"Neon",
			{ collide = false }
		)
	end
	local glow = kit:box(
		m,
		"LampLight",
		cx - 0.2,
		cx + 0.2,
		7.5,
		7.55,
		cd - 0.2,
		cd + 0.2,
		{ 255, 236, 190 },
		"Neon",
		{ collide = false }
	)
	kit:light(
		glow,
		"SurfaceLight",
		{ Face = "Bottom", Range = 9, Angle = 90, Brightness = 2.2, Color = { 255, 238, 200 } }
	)
	return m
end

local function dartboard(kit: any, parent: any)
	local b = L.board()
	local m = kit:model(parent, "Dartboard")
	local mm = L.DART_MM
	local fx, by, bd = b.x, b.y, b.d
	-- the board hangs on the games room's right wall facing -X; the thrower faces +X, so the thrower's right is
	-- +D and up is +Y. (x mm right, y mm up) -> local (fx, by + y, bd + x).
	local function boardAt(xmm: number, ymm: number): (number, number)
		return by + ymm * mm, bd + xmm * mm
	end
	kit:box(m, "Cabinet", fx + 0.05, fx + 0.3, by - 1.3, by + 1.3, bd - 1.3, bd + 1.3, WOOD_DARK, "Wood")
	for side = -1, 1, 2 do
		-- the cabinet doors folded open against the wall, chalkboards inside
		local e0, e1 = bd + side * 1.3, bd + side * 2.6
		kit:box(
			m,
			"CabinetDoor",
			fx + 0.05,
			fx + 0.25,
			by - 1.3,
			by + 1.3,
			math.min(e0, e1),
			math.max(e0, e1),
			WOOD,
			"Wood"
		)
		kit:box(
			m,
			"DoorChalk",
			fx + 0.0,
			fx + 0.05,
			by - 1.1,
			by + 1.1,
			math.min(e0, e1) + 0.15,
			math.max(e0, e1) - 0.15,
			{ 30, 40, 34 },
			"Slate",
			{
				collide = false,
			}
		)
	end
	local face = kit:cyl(m, "BoardFace", fx, by, bd, 0.06, b.radius * 2, "X", BLACK, "SmoothPlastic")
	face:SetAttribute("BoardRadius", b.radius)
	local layers = {
		{ 170, { 200, 40, 40 } }, -- double ring
		{ 162, { 236, 222, 186 } }, -- outer singles
		{ 107, { 40, 140, 70 } }, -- treble ring
		{ 99, { 236, 222, 186 } }, -- inner singles
		{ 15.9, { 40, 140, 70 } }, -- outer bull
		{ 6.35, { 200, 40, 40 } }, -- bull
	}
	for i, layer in layers do
		kit:cyl(
			m,
			`Ring{i}`,
			fx - 0.035 - i * 0.004,
			by,
			bd,
			0.004,
			layer[1] * 2 * mm,
			"X",
			layer[2],
			"SmoothPlastic",
			{
				collide = false,
				query = false,
			}
		)
	end
	-- black singles (every other segment) as thin plates laid over the cream singles; a plate's long side runs
	-- out from the bull: rotating about X by -angle points local Y along (up cos a, right sin a)
	for sgm = 0, 19 do
		local ang = math.rad(sgm * 18)
		if sgm % 2 == 1 then
			for _, band in { { 16, 99 }, { 107, 162 } } do
				local r0, r1 = band[1], band[2]
				local mid = (r0 + r1) / 2
				local width = 2 * mid * math.tan(math.rad(9)) * mm
				local py, pd = boardAt(mid * math.sin(ang), mid * math.cos(ang))
				kit:at(m, "Segment", fx - 0.05, py, pd, 0.004, (r1 - r0) * mm, width, BLACK, "SmoothPlastic", {
					collide = false,
					query = false,
					rot = kit.roblox.CFrame.Angles(-ang, 0, 0),
				})
			end
		end
		local wa = math.rad(sgm * 18 + 9)
		local wy, wd = boardAt(85 * math.sin(wa), 85 * math.cos(wa))
		kit:at(m, "Wire", fx - 0.065, wy, wd, 0.006, 170 * mm, 0.008, { 200, 200, 205 }, "Metal", {
			collide = false,
			query = false,
			rot = kit.roblox.CFrame.Angles(-wa, 0, 0),
		})
	end
	local order = { 20, 1, 18, 4, 13, 6, 10, 15, 2, 17, 3, 19, 7, 16, 8, 11, 14, 9, 12, 5 }
	for i, n in order do
		local ang = math.rad((i - 1) * 18)
		local ty, td = boardAt(196 * math.sin(ang), 196 * math.cos(ang))
		local tag = kit:at(m, "Number", fx - 0.07, ty, td, 0.004, 0.14, 0.14, BLACK, "SmoothPlastic", {
			collide = false,
			query = false,
			transparency = 1,
		})
		kit:label(kit:gui(tag, "Left", 200), { Text = tostring(n), TextColor = { 240, 240, 240 }, Font = "GothamBold" })
	end
	-- the oche (throw line) and a mat
	kit:box(
		m,
		"Oche",
		b.ocheX - 0.12,
		b.ocheX + 0.12,
		0,
		0.05,
		bd - 1.5,
		bd + 1.5,
		{ 196, 160, 80 },
		"Metal",
		{ collide = false }
	)
	kit:box(m, "Mat", b.ocheX - 3, fx - 0.4, 0, 0.03, bd - 1.6, bd + 1.6, { 40, 40, 44 }, "Fabric", { collide = false })
	-- the scores chalkboard on the wall beside it (the server writes the scores here)
	local scoreBoard = kit:box(
		m,
		"ScoreBoard",
		fx - 0.05,
		fx + 0.05,
		by - 1.4,
		by + 1.2,
		bd - 6.6,
		bd - 3.0,
		{ 30, 40, 34 },
		"Slate",
		{ collide = false }
	)
	local sg = kit:gui(scoreBoard, "Left", 50)
	sg.Name = "Score"
	kit:label(
		sg,
		{ Text = "DARTS\n501 - CRICKET", TextColor = { 236, 236, 220 }, Font = "PermanentMarker", Size = { 1, 0.6 } }
	)
	kit:label(sg, {
		Text = "walk up and press E",
		TextColor = { 236, 220, 120 },
		Font = "PermanentMarker",
		Size = { 1, 0.3 },
		Pos = { 0, 0.65 },
	})
	local spot = kit:box(
		m,
		"BoardLight",
		fx - 1.4,
		fx - 1.2,
		by + 1.6,
		by + 1.75,
		bd - 0.4,
		bd + 0.4,
		{ 255, 240, 210 },
		"Neon",
		{ collide = false }
	)
	kit:light(spot, "SpotLight", { Face = "Right", Range = 6, Angle = 60, Brightness = 3, Color = { 255, 240, 214 } })
	-- three darts stuck in the board, waiting (the server hides them while a game is on)
	local idle = kit:folder(m, "IdleDarts")
	for k = 0, 2 do
		local iy, idd = boardAt(-30 + k * 25, 60 - k * 20)
		kit:cyl(
			idle,
			"IdleDart",
			fx - 0.3,
			iy,
			idd,
			0.5,
			0.045,
			"X",
			{ 220, 40, 40 },
			"Metal",
			{ collide = false, query = false }
		)
	end
end

local function pinball(kit: any, parent: any, i: number, px: number, theme: string)
	local m = kit:model(parent, `Pinball{i}`)
	local themes: { [string]: any } = {
		acorn = { title = "ACORN ATTACK", body = { 150, 70, 30 }, accent = { 255, 200, 60 }, glow = { 255, 170, 40 } },
		rodent = { title = "SPICY RODENT", body = { 160, 20, 30 }, accent = { 255, 90, 40 }, glow = { 255, 60, 40 } },
		space = {
			title = "SPACE SQUIRREL",
			body = { 30, 30, 90 },
			accent = { 120, 220, 255 },
			glow = { 140, 120, 255 },
		},
	}
	local th = themes[theme]
	local d0 = L.PINBALL_D -- front (where the player stands is -D... the cabinet's front faces +D, into the room)
	local w = 2.7
	-- the body (slanted playfield), legs, the backbox standing up at the back (against the front wall)
	kit:box(m, "Cabinet", px - w / 2, px + w / 2, 2.4, 3.6, d0 - 2.4, d0 + 2.6, th.body, "SmoothPlastic")
	kit:at(m, "Glass", px, 3.75, d0 + 0.1, w - 0.2, 0.05, 5.0, { 160, 200, 220 }, "Glass", {
		transparency = 0.4,
		rot = kit.roblox.CFrame.Angles(0.12, 0, 0),
	})
	kit:at(m, "Playfield", px, 3.6, d0 + 0.1, w - 0.3, 0.04, 4.9, th.accent, "Neon", {
		collide = false,
		rot = kit.roblox.CFrame.Angles(0.12, 0, 0),
	})
	for _, pos in { { -0.6, -1.2 }, { 0.5, -0.6 }, { 0, -1.8 } } do
		kit:cyl(
			m,
			"Bumper",
			px + pos[1],
			3.95 + pos[2] * -0.12,
			d0 + pos[2],
			0.35,
			0.5,
			"Y",
			{ 255, 255, 255 },
			"SmoothPlastic",
			{ collide = false }
		)
	end
	for side = -1, 1, 2 do
		kit:at(m, "Flipper", px + side * 0.45, 3.7, d0 + 2.0, 0.6, 0.12, 0.12, { 240, 240, 240 }, "SmoothPlastic", {
			collide = false,
			rot = kit.roblox.CFrame.Angles(0, side * 0.5, 0),
		})
		kit:box(
			m,
			"Leg",
			px + side * (w / 2 - 0.25) - 0.15,
			px + side * (w / 2 - 0.25) + 0.15,
			0,
			2.4,
			d0 + 2.0,
			d0 + 2.3,
			{ 180, 180, 186 },
			"Metal"
		)
		kit:box(
			m,
			"Leg",
			px + side * (w / 2 - 0.25) - 0.15,
			px + side * (w / 2 - 0.25) + 0.15,
			0,
			2.4,
			d0 - 2.2,
			d0 - 1.9,
			{ 180, 180, 186 },
			"Metal"
		)
	end
	kit:box(m, "Backbox", px - w / 2, px + w / 2, 3.6, 7.4, d0 - 2.6, d0 - 1.8, th.body, "SmoothPlastic")
	local art = kit:box(
		m,
		"Backglass",
		px - w / 2 + 0.15,
		px + w / 2 - 0.15,
		4.0,
		7.2,
		d0 - 1.81,
		d0 - 1.76,
		{ 20, 20, 30 },
		"SmoothPlastic",
		{ collide = false }
	)
	local g = kit:gui(art, "Front", 60)
	kit:label(g, { Text = th.title, TextColor = th.accent, Font = "FredokaOne", Size = { 1, 0.45 }, Pos = { 0, 0.05 } })
	kit:label(g, {
		Text = "OUT OF ORDER\nback soon",
		TextColor = { 255, 255, 255 },
		Font = "GothamBold",
		Size = { 1, 0.35 },
		Pos = { 0, 0.6 },
	})
	kit:box(
		m,
		"BackboxGlow",
		px - w / 2,
		px + w / 2,
		7.25,
		7.4,
		d0 - 1.85,
		d0 - 1.7,
		th.glow,
		"Neon",
		{ collide = false }
	)
	kit:box(
		m,
		"CoinDoor",
		px - 0.4,
		px + 0.4,
		2.6,
		3.3,
		d0 + 2.6,
		d0 + 2.64,
		{ 60, 60, 64 },
		"Metal",
		{ collide = false }
	)
	kit:box(
		m,
		"FreePlay",
		px - 0.35,
		px + 0.35,
		2.95,
		3.15,
		d0 + 2.64,
		d0 + 2.66,
		{ 80, 255, 120 },
		"Neon",
		{ collide = false }
	)
	m:SetAttribute("Theme", theme)
end

local function bumperPool(kit: any, parent: any)
	local m = kit:model(parent, "BumperPool")
	local p = L.BUMPER_POOL
	local cx, cd = p.x, p.d
	local hx, hd = 1.9, 2.8
	local top = 3.0
	kit:box(m, "Felt", cx - hx, cx + hx, top - 0.3, top, cd - hd, cd + hd, { 150, 30, 40 }, "Fabric")
	kit:box(m, "Rail", cx - hx - 0.4, cx + hx + 0.4, top - 1.0, top + 0.3, cd - hd - 0.4, cd - hd, WOOD, "Wood")
	kit:box(m, "Rail", cx - hx - 0.4, cx + hx + 0.4, top - 1.0, top + 0.3, cd + hd, cd + hd + 0.4, WOOD, "Wood")
	kit:box(m, "Rail", cx - hx - 0.4, cx - hx, top - 1.0, top + 0.3, cd - hd, cd + hd, WOOD, "Wood")
	kit:box(m, "Rail", cx + hx, cx + hx + 0.4, top - 1.0, top + 0.3, cd - hd, cd + hd, WOOD, "Wood")
	kit:box(m, "Base", cx - 1.2, cx + 1.2, 0, top - 1.0, cd - 1.8, cd + 1.8, WOOD_DARK, "Wood")
	for _, b in { { 0, -0.8 }, { 0, 0.8 }, { -0.7, 0 }, { 0.7, 0 }, { -0.4, -1.6 }, { 0.4, 1.6 } } do
		kit:cyl(m, "Bumper", cx + b[1], top + 0.15, cd + b[2], 0.3, 0.22, "Y", { 40, 40, 44 }, "Rubber" :: any)
	end
	for side = -1, 1, 2 do
		kit:cyl(
			m,
			"Cup",
			cx,
			top + 0.01,
			cd + side * (hd - 0.5),
			0.05,
			0.4,
			"Y",
			BLACK,
			"SmoothPlastic",
			{ collide = false }
		)
		for k = 0, 4 do
			kit:ball(
				m,
				"Ball",
				cx - 1.0 + k * 0.5,
				top + 0.2,
				cd + side * (hd - 1.2),
				0.4,
				if side < 0 then { 200, 30, 30 } else { 240, 240, 240 },
				"SmoothPlastic"
			)
		end
	end
end

-- Madame Acorna: a fortune-teller booth with a squirrel seer behind glass, three reels, a lever and a card slot.
local function fortune(kit: any, parent: any)
	local m = kit:model(parent, "Fortune")
	local f = L.FORTUNE
	local cx, cd = f.x, f.d
	local purple = { 70, 30, 90 }
	local gold = { 220, 180, 80 }
	-- the cabinet faces into the room: toward (-X, -D) diagonally; build it facing -D and turn it
	local rot = kit.roblox.CFrame.Angles(0, -math.pi / 4, 0)
	local function at(
		name: string,
		ox: number,
		oy: number,
		od: number,
		sx: number,
		sy: number,
		sd: number,
		col: { number },
		mat: string,
		opts: any?
	)
		local o = table.clone(opts or {})
		local c, s = math.cos(math.pi / 4), math.sin(math.pi / 4)
		-- rotate the offset (ox, od) by the same yaw as the part (local frame: +X right, +D away)
		local rx = ox * c + od * s
		local rd = -ox * s + od * c
		o.rot = if o.rot then rot * o.rot else rot
		return kit:at(m, name, cx + rx, oy, cd + rd, sx, sy, sd, col, mat, o)
	end
	at("Base", 0, 1.6, 0, 3.0, 3.2, 2.4, purple, "Wood")
	at("BaseTrim", 0, 3.25, 0, 3.1, 0.15, 2.5, gold, "Metal")
	at("Booth", 0, 5.6, 0.2, 3.0, 4.5, 2.0, purple, "Wood")
	at(
		"BoothGlass",
		0,
		5.6,
		-0.82,
		2.6,
		4.0,
		0.06,
		{ 160, 200, 220 },
		"Glass",
		{ transparency = 0.55, reflectance = 0.2 }
	)
	at("Crown", 0, 8.1, 0.2, 3.3, 0.5, 2.3, gold, "Metal")
	at("Dome", 0, 8.6, 0.2, 2.0, 0.6, 1.4, purple, "Wood")
	local sign = at("Marquee", 0, 9.2, -0.2, 3.0, 0.8, 0.12, { 30, 10, 40 }, "SmoothPlastic", { collide = false })
	kit:label(kit:gui(sign, "Back", 60), { Text = "MADAME ACORNA", TextColor = { 255, 214, 92 }, Font = "Fantasy" })
	-- the seer: a squirrel in a turban with a crystal ball
	at("SeerBody", 0, 4.9, 0.3, 1.0, 1.4, 0.7, { 150, 96, 60 }, "Fabric", { collide = false })
	at("SeerHead", 0, 6.0, 0.25, 0.7, 0.65, 0.65, { 160, 104, 64 }, "Fabric", { collide = false })
	at("Turban", 0, 6.45, 0.25, 0.8, 0.4, 0.75, { 160, 30, 60 }, "Fabric", { collide = false })
	at("Jewel", 0, 6.45, -0.15, 0.12, 0.12, 0.05, { 80, 220, 120 }, "Neon", { collide = false })
	for side = -1, 1, 2 do
		at("Ear", side * 0.22, 6.35, 0.3, 0.14, 0.3, 0.12, { 160, 104, 64 }, "Fabric", { collide = false })
		at("Eye", side * 0.15, 6.05, -0.09, 0.08, 0.08, 0.03, { 255, 220, 120 }, "Neon", { collide = false })
	end
	at(
		"Tail",
		0.5,
		5.5,
		0.8,
		0.35,
		1.6,
		0.35,
		{ 150, 96, 60 },
		"Fabric",
		{ collide = false, rot = kit.roblox.CFrame.Angles(0, 0, -0.4) }
	)
	local orb = at(
		"CrystalBall",
		0,
		4.55,
		-0.35,
		0.6,
		0.6,
		0.6,
		{ 170, 140, 255 },
		"Neon",
		{ collide = false, shape = "Ball", transparency = 0.15 }
	)
	kit:light(orb, "PointLight", { Range = 8, Brightness = 1.6, Color = { 170, 140, 255 } })
	-- the reels window on the base and the three reels (server spins them by attribute)
	at("ReelWindow", 0, 2.6, -1.21, 2.2, 0.8, 0.04, { 20, 16, 24 }, "SmoothPlastic", { collide = false })
	for r = 1, 3 do
		local reel = at(
			`Reel{r}`,
			(r - 2) * 0.7,
			2.6,
			-1.18,
			0.6,
			0.66,
			0.04,
			{ 240, 236, 220 },
			"SmoothPlastic",
			{ collide = false }
		)
		local g = kit:gui(reel, "Back", 120)
		g.Name = "Face"
		kit:label(g, { Text = "?", TextColor = { 90, 30, 110 }, Font = "Fantasy" })
	end
	local slot = at("CardSlot", 0, 1.6, -1.21, 1.0, 0.12, 0.05, { 10, 10, 10 }, "SmoothPlastic", { collide = false })
	local _ = slot
	local plate = at("FreePlate", 0, 1.0, -1.22, 1.8, 0.4, 0.03, gold, "Metal", { collide = false })
	kit:label(kit:gui(plate, "Back", 60), { Text = "FREE - NO COINS", TextColor = { 60, 20, 60 }, Font = "GothamBold" })
	-- the lever on the right side
	local lever = kit:model(m, "Lever")
	at("LeverPivot", 1.6, 2.6, 0, 0.25, 0.4, 0.4, gold, "Metal", { collide = false })
	local arm = at("LeverArm", 1.75, 3.3, 0, 0.12, 1.4, 0.12, gold, "Metal", { collide = false })
	arm.Parent = lever
	local knob = at(
		"LeverKnob",
		1.75,
		4.05,
		0,
		0.36,
		0.36,
		0.36,
		{ 200, 30, 40 },
		"SmoothPlastic",
		{ collide = false, shape = "Ball" }
	)
	knob.Parent = lever
	lever.PrimaryPart = arm
	-- ferns either side of the cabinet
	local function fern(fx: number, fd: number, scale: number)
		kit:cyl(m, "FernPot", fx, 0.8 * scale, fd, 1.6 * scale, 1.5 * scale, "Y", { 160, 90, 60 }, "Brick")
		kit:cyl(
			m,
			"FernSoil",
			fx,
			1.6 * scale + 0.01,
			fd,
			0.04,
			1.35 * scale,
			"Y",
			{ 60, 44, 30 },
			"Ground",
			{ collide = false }
		)
		for k = 0, 9 do
			local a = k * 0.63
			local len = (1.6 + (k % 3) * 0.3) * scale
			local fr = kit.roblox.CFrame.Angles(0, a, 0) * kit.roblox.CFrame.Angles(0.95 + (k % 2) * 0.25, 0, 0)
			kit:at(
				m,
				"Frond",
				fx + math.sin(a) * -0.5 * scale,
				1.6 * scale + 0.55 * scale,
				fd + math.cos(a) * 0.5 * scale,
				0.32 * scale,
				0.04,
				len,
				{ 50 + (k % 3) * 12, 120 + (k % 2) * 20, 50 },
				"Grass",
				{
					collide = false,
					rot = fr,
				}
			)
		end
	end
	fern(cx + 2.4, cd - 0.6, 1.1)
	fern(cx - 1.2, cd + 2.4, 1.0)
	fern(cx + 2.9, cd + 2.6, 0.8)
end

local function gamesRoom(kit: any, root: any)
	local m = kit:model(root, "GamesRoom")
	for i, t in L.POOL_TABLES do
		poolTable(kit, m, `Pool{i}`, t.x, t.d)
	end
	bumperPool(kit, m)
	dartboard(kit, m)
	for i, p in L.PINBALLS do
		pinball(kit, m, i, p.x, p.theme)
	end
	fortune(kit, m)
	-- cue rack, wood panelling, a jukebox-style glow and the room's light
	kit:box(m, "CueRack", L.X1 - 0.3, L.X1, 2, 7, -22, -18, WOOD_DARK, "Wood")
	for k = 0, 5 do
		kit:cyl(
			m,
			"RackedCue",
			L.X1 - 0.45,
			4.6,
			-21.6 + k * 0.7,
			5.6,
			0.1,
			"Y",
			{ 214, 180, 120 },
			"Wood",
			{ collide = false }
		)
	end
	kit:box(
		m,
		"Wainscot",
		L.X1 - 0.08,
		L.X1,
		0,
		3.2,
		L.FRONT_D,
		L.GAME_ROOM_D1,
		WOOD,
		"WoodPlanks",
		{ collide = false }
	)
	kit:box(
		m,
		"WainscotBack",
		L.GAME_ROOM_X0,
		L.X1,
		0,
		3.2,
		L.GAME_ROOM_D1 - 0.08,
		L.GAME_ROOM_D1,
		WOOD,
		"WoodPlanks",
		{ collide = false }
	)
	local sign = kit:box(
		m,
		"GamesSign",
		L.GAME_ROOM_X0 - 0.32,
		L.GAME_ROOM_X0 - 0.3,
		8.6,
		10.2,
		-24,
		-14,
		{ 26, 30, 60 },
		"SmoothPlastic",
		{ collide = false }
	)
	kit:label(kit:gui(sign, "Left", 30), { Text = "GAMES ROOM", TextColor = { 255, 214, 92 }, Font = "FredokaOne" })
	local roomLight = kit:box(
		m,
		"GamesTroffer",
		34,
		48,
		L.CEILING_Y - 0.12,
		L.CEILING_Y,
		6,
		8,
		{ 250, 240, 220 },
		"Neon",
		{ collide = false }
	)
	kit:light(roomLight, "PointLight", { Range = 26, Brightness = 0.9, Color = { 255, 236, 210 } })
	local cornerLight = kit:box(
		m,
		"CornerLamp",
		52,
		53,
		L.CEILING_Y - 2,
		L.CEILING_Y - 1.8,
		22,
		23,
		{ 255, 200, 140 },
		"Neon",
		{ collide = false }
	)
	kit:light(cornerLight, "PointLight", { Range = 14, Brightness = 1.0, Color = { 255, 196, 140 } })
end

local function backOfHouse(kit: any, root: any)
	local m = kit:model(root, "BackOfHouse")
	local d0, d1 = L.MACHINE_D1, L.REAR_WALL_D
	-- a catwalk line painted on the floor, the machine-room sign, fluorescent tubes
	kit:box(
		m,
		"SafetyLine",
		L.X0 + 0.5,
		L.LANE_BLOCK_X,
		0,
		0.004,
		d0 + 1.2,
		d0 + 1.4,
		{ 240, 200, 40 },
		"SmoothPlastic",
		{ collide = false, query = false }
	)
	for k, x in { -16, -4, 8, 20, 36, 48 } do
		local tube = kit:box(
			m,
			"Tube",
			x - 3,
			x + 3,
			L.CEILING_Y - 0.5,
			L.CEILING_Y - 0.35,
			(d0 + d1) / 2 - 0.15,
			(d0 + d1) / 2 + 0.15,
			{ 240, 250, 255 },
			"Neon",
			{
				collide = false,
			}
		)
		if k % 2 == 1 then
			kit:light(tube, "PointLight", { Range = 20, Brightness = 1.0, Color = { 236, 246, 255 } })
		end
	end
	local sign = kit:box(
		m,
		"EmployeesOnly",
		L.X0 + 1,
		L.X0 + 6,
		7.4,
		8.4,
		d0 - 0.66,
		d0 - 0.62,
		{ 200, 30, 30 },
		"SmoothPlastic",
		{ collide = false }
	)
	kit:label(
		kit:gui(sign, "Back", 40),
		{ Text = "EMPLOYEES ONLY", TextColor = { 255, 255, 255 }, Font = "GothamBlack" }
	)
	-- the mechanic's workbench against the rear wall with a vice, tools on a pegboard
	kit:box(m, "Bench", -12, -2, 0, 3.0, d1 - 2.2, d1, { 90, 70, 50 }, "Wood")
	kit:box(m, "BenchTop", -12.1, -1.9, 3.0, 3.2, d1 - 2.3, d1, { 120, 96, 70 }, "Wood")
	kit:box(m, "Pegboard", -12, -2, 3.8, 7.6, d1 - 0.1, d1, { 190, 160, 120 }, "WoodPlanks", { collide = false })
	for k = 0, 6 do
		kit:box(
			m,
			"Tool",
			-11 + k * 1.3,
			-10.7 + k * 1.3,
			4.6 + (k % 2) * 1.2,
			6.2 + (k % 3) * 0.4,
			d1 - 0.22,
			d1 - 0.12,
			{ 60 + k * 20, 60, 70 },
			"Metal",
			{
				collide = false,
			}
		)
	end
	kit:box(m, "Vice", -4.2, -3.2, 3.2, 3.8, d1 - 1.6, d1 - 0.8, { 40, 70, 120 }, "Metal", { collide = false })
	-- spare pins on a shelf, a pin cart and a ball-cleaning machine
	kit:box(m, "Shelf", 4, 14, 0, 0.2, d1 - 1.6, d1, { 120, 120, 124 }, "Metal")
	for level = 0, 2 do
		local y = 1.4 + level * 2.0
		kit:box(m, "ShelfBoard", 4, 14, y - 0.1, y, d1 - 1.6, d1, { 120, 120, 124 }, "Metal")
		for k = 0, 7 do
			kit:cyl(
				m,
				"SparePin",
				4.6 + k * 1.2,
				y + 0.73,
				d1 - 0.8,
				1.45,
				0.42,
				"Y",
				{ 245, 245, 240 },
				"SmoothPlastic",
				{ collide = false }
			)
		end
	end
	for _, sx in { 4, 14 } do
		kit:box(m, "ShelfPost", sx - 0.1, sx + 0.1, 0, 6, d1 - 1.6, d1, { 90, 90, 94 }, "Metal")
	end
	kit:box(m, "PinCart", 18, 21, 0.6, 2.2, d0 + 4, d0 + 6, { 200, 120, 30 }, "Metal")
	for _, w in { { 18.4, d0 + 4.3 }, { 20.6, d0 + 4.3 }, { 18.4, d0 + 5.7 }, { 20.6, d0 + 5.7 } } do
		kit:cyl(m, "CartWheel", w[1], 0.3, w[2], 0.2, 0.6, "X", BLACK, "Rubber" :: any, { collide = false })
	end
	for k = 0, 3 do
		kit:at(m, "CartPin", 18.6 + k * 0.6, 2.5, d0 + 5, 0.42, 1.45, 0.42, { 245, 245, 240 }, "SmoothPlastic", {
			collide = false,
			shape = "Cylinder",
			rot = kit.roblox.CFrame.Angles(0, 0, 1.2),
		})
	end
	kit:box(m, "BallCleaner", 30, 33, 0, 3.6, d1 - 3, d1, { 60, 120, 160 }, "Metal")
	-- storeroom wing: boxes of shoes, paper towels, a mop bucket with its mop
	for k = 0, 5 do
		local bx = 38 + (k % 3) * 2.4
		local by = math.floor(k / 3) * 1.8
		kit:box(m, "Carton", bx, bx + 2.2, by, by + 1.8, d1 - 2.4, d1 - 0.2, { 180, 150, 110 }, "Cardboard" :: any)
	end
	kit:cyl(m, "MopBucket", 30, 0.8, 52, 1.5, 1.7, "Y", { 230, 200, 40 }, "SmoothPlastic")
	kit:cyl(m, "MopHandle", 30.4, 3.2, 52, 4.4, 0.12, "Y", { 170, 130, 80 }, "Wood", {
		collide = false,
		rot = kit.roblox.CFrame.Angles(0.25, 0, 0),
	})
	local deskLamp = kit:box(
		m,
		"StoreTube",
		36,
		48,
		L.CEILING_Y - 0.5,
		L.CEILING_Y - 0.35,
		50,
		50.3,
		{ 240, 250, 255 },
		"Neon",
		{ collide = false }
	)
	kit:light(deskLamp, "PointLight", { Range = 20, Brightness = 0.9, Color = { 236, 246, 255 } })
end

-- The alley: three big round dark-blue trash cans by the vents, the push broom leaning by the door, a couple
-- of crates and an old lane board.
local function alleyProps(kit: any, root: any)
	local m = kit:model(root, "AlleyProps")
	local ay = L.ALLEY_Y
	local d = L.REAR_WALL_D + L.WALL_T + 1.6
	local blue = { 26, 46, 98 }
	local cans = { { -15.6, 0.04 }, { -9.0, -0.06 }, { -3.0, 0.03 } }
	for i, c in cans do
		local cx = c[1]
		local tilt = kit.roblox.CFrame.Angles(c[2], 0, c[2] * 0.6)
		local can = kit:model(m, `TrashCan{i}`)
		kit:cyl(can, "Body", cx, ay + 1.75, d, 3.5, 2.5, "Y", blue, "SmoothPlastic", { rot = tilt })
		for k = 0, 2 do
			kit:cyl(
				can,
				"Rib",
				cx,
				ay + 0.6 + k * 1.15,
				d,
				0.12,
				2.6,
				"Y",
				{ 22, 40, 86 },
				"SmoothPlastic",
				{ collide = false, rot = tilt }
			)
		end
		kit:cyl(can, "Lid", cx + 0.05, ay + 3.6, d, 0.25, 2.75, "Y", { 30, 52, 108 }, "SmoothPlastic", {
			rot = tilt * kit.roblox.CFrame.Angles(0.06 * i, 0, 0),
		})
		kit:box(
			can,
			"Handle",
			cx - 0.5,
			cx + 0.5,
			ay + 3.75,
			ay + 3.95,
			d - 0.12,
			d + 0.12,
			{ 22, 40, 86 },
			"SmoothPlastic",
			{ collide = false }
		)
		can:SetAttribute("Forage", "trash_can")
	end
	-- a bag that did not make it in
	kit:ball(m, "TrashBag", -6.3, ay + 0.6, d + 1.4, 1.3, { 30, 30, 32 }, "SmoothPlastic")
	-- the push broom leaning on the wall by the exit door
	local bx, bd = -18.7, L.REAR_WALL_D + L.WALL_T + 0.35
	local lean = kit.roblox.CFrame.Angles(0.22, 0, 0.05)
	kit:cyl(
		m,
		"BroomHandle",
		bx,
		2.35,
		bd + 0.55,
		4.8,
		0.13,
		"Y",
		{ 176, 130, 76 },
		"Wood",
		{ collide = false, rot = lean }
	)
	kit:at(m, "BroomHead", bx, 0.18, bd + 1.08, 2.2, 0.32, 0.4, { 90, 64, 40 }, "Wood", { collide = false, rot = lean })
	kit:at(m, "Bristles", bx, 0.05, bd + 1.1, 2.15, 0.12, 0.34, BLACK, "Fabric", { collide = false })
	-- crates and an old lane board leaning on the fence
	kit:box(m, "Crate", 30, 33, ay, ay + 2.4, 97, 100, { 160, 120, 70 }, "WoodPlanks")
	kit:box(m, "Crate", 30.4, 32.6, ay + 2.4, ay + 4.2, 97.5, 99.6, { 150, 112, 64 }, "WoodPlanks")
	kit:at(
		m,
		"OldLaneBoard",
		40,
		ay + 3,
		100.4,
		6,
		0.3,
		0.7,
		{ 210, 180, 130 },
		"Wood",
		{ rot = kit.roblox.CFrame.Angles(0.15, 0, 1.2) }
	)
end

function Rooms.build(kit: any, root: any)
	concourse(kit, root)
	gamesRoom(kit, root)
	backOfHouse(kit, root)
	alleyProps(kit, root)
end

return Rooms
