--!strict
-- tools/bake/alley/GamesRoom: the games room (the "activity room"; brief v2 §13a, addendum D5), the east wing of
-- the eighteen-lane house: two pool tables racked and ready, a bumper pool table, the dartboard on the wall
-- beside the pool tables with its oche, three pinball machines in distinct themes along the front wall, the air
-- hockey table, and in the back corner by the ferns Madame Acorna, the fortune-teller cabinet. Where each stands
-- is Shared/Attractions/AlleyLayout's (POOL_TABLES, BUMPER_POOL, PINBALLS, PINBALL_D, AIR_HOCKEY, FORTUNE,
-- board()), and so is the clear floor each keeps (standing()): the room's own dressing here stays on the walls
-- and the ceiling.
-- The pool tables, the bumper pool table, the pinball machines and whatever a later game stands in the room are
-- their games' own furniture, built through the bake registry (tools/bake/GameBakes), one build per station.
-- Names the server relies on: GamesRoom.Dartboard (Face part "BoardFace"), GamesRoom.Fortune.{Lever, Reel1..3,
-- CardSlot}, GamesRoom.Pool<i>, GamesRoom.Pinball<i>, GamesRoom.BumperPool.
-- Interface: build(kit, root) -> nothing

local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")
local Games = require("../../../src/shared/Minigames/Games")
local GameBakes = require("../GameBakes")

local GamesRoom = {}
local L = AlleyLayout
-- games whose place in the games room's build order is fixed below (the lanes are Lanes.luau's)
local ROOM_ORDER: { [string]: boolean } =
	{ bowling = true, darts = true, fortune_machine = true, pool = true, bumper_pool = true, pinball = true }

local WOOD = { 104, 66, 40 }
local WOOD_DARK = { 70, 44, 28 }
local BLACK = { 24, 24, 26 }

local function dartboard(kit: any, parent: any)
	local b = L.board()
	local m = kit:model(parent, "Dartboard")
	local mm = L.DART_MM
	local fx, by, bd = b.x, b.y, b.d
	-- the board hangs on the games room's right wall facing -X; the thrower faces +X, so the thrower's right is
	-- -D and up is +Y (AlleyLayout.boardPoint).
	local function boardAt(xmm: number, ymm: number): (number, number)
		local _, Y, D = L.boardPoint(xmm, ymm)
		return Y, D
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
	-- out from the bull: rotating about X by +angle points local Y along (up cos a, -D sin a) = (up, right)
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
					rot = kit.roblox.CFrame.Angles(ang, 0, 0),
				})
			end
		end
		local wa = math.rad(sgm * 18 + 9)
		local wy, wd = boardAt(85 * math.sin(wa), 85 * math.cos(wa))
		kit:at(m, "Wire", fx - 0.065, wy, wd, 0.006, 170 * mm, 0.008, { 200, 200, 205 }, "Metal", {
			collide = false,
			query = false,
			rot = kit.roblox.CFrame.Angles(wa, 0, 0),
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
	-- the booth is hollow (the seer sits inside behind the glass): back, sides, floor and top
	at("BoothBack", 0, 5.6, 1.15, 3.0, 4.5, 0.1, purple, "Wood")
	at("BoothSideL", -1.45, 5.6, 0.2, 0.1, 4.5, 2.0, purple, "Wood")
	at("BoothSideR", 1.45, 5.6, 0.2, 0.1, 4.5, 2.0, purple, "Wood")
	at("BoothFloor", 0, 3.4, 0.2, 3.0, 0.1, 2.0, { 50, 20, 30 }, "Fabric")
	at("BoothTop", 0, 7.8, 0.2, 3.0, 0.1, 2.0, purple, "Wood")
	at(
		"BoothGlass",
		0,
		5.6,
		-0.82,
		2.6,
		4.0,
		0.06,
		{ 190, 214, 228 },
		"SmoothPlastic",
		{ transparency = 0.9, reflectance = 0.05, shadow = false }
	)
	at("Velvet", 0, 5.6, 1.12, 2.7, 4.2, 0.08, { 120, 20, 40 }, "Fabric", { collide = false })
	local boothLamp = at("BoothLamp", 0, 7.65, 0.2, 2.4, 0.08, 1.4, { 255, 220, 150 }, "Neon", { collide = false })
	kit:light(boothLamp, "PointLight", { Range = 7, Brightness = 1.6, Color = { 255, 214, 160 } })
	at("ReelTrim", 0, 3.05, -1.22, 2.4, 0.06, 0.03, { 255, 200, 80 }, "Neon", { collide = false })
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
			-1.26,
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
	-- each game's furniture is its own (tools/bake/GameBakes): one build per station, in the room's old order
	local stations = Games.stations({ bowling_alley = kit.place })
	local function furnish(game: string)
		for _, st in stations do
			if st.game == game and st.site == "bowling_alley" then
				GameBakes.build(game, kit, m, st, nil)
			end
		end
	end
	furnish("pool")
	furnish("bumper_pool")
	dartboard(kit, m)
	furnish("pinball")
	fortune(kit, m)
	-- (and whatever a later game stands in this room)
	for _, st in stations do
		if st.site == "bowling_alley" and not ROOM_ORDER[st.game] then
			GameBakes.build(st.game, kit, m, st, nil)
		end
	end
	-- the room's own dressing: a cue rack on the east wall between the two pool tables, wood wainscot and
	-- knotty-pine panelling (a 70s rec room) on the east and back walls and on the solid stretches of the
	-- partition, a sign over each opening on the hall side, and the room's lights
	local x1, gd0, gd1 = L.X1, L.GAME_ROOM_D0, L.GAME_ROOM_D1
	local px = L.GAME_ROOM_X0 + L.PARTITION_T -- the partition's room face
	local pt = L.POOL_TABLES
	local rackD = (pt[1].d + pt[#pt].d) / 2
	kit:box(m, "CueRack", x1 - 0.3, x1, 2, 7, rackD - 2, rackD + 2, WOOD_DARK, "Wood")
	for k = 0, 5 do
		kit:cyl(
			m,
			"RackedCue",
			x1 - 0.45,
			4.6,
			rackD - 1.6 + k * 0.7,
			5.6,
			0.1,
			"Y",
			{ 214, 180, 120 },
			"Wood",
			{ collide = false }
		)
	end
	local PINE = { 186, 152, 106 }
	local soft = { collide = false }
	kit:box(m, "Wainscot", x1 - 0.08, x1, 0, 3.2, gd0, gd1, WOOD, "WoodPlanks", soft)
	kit:box(m, "PinePanel", x1 - 0.06, x1, 3.2, L.CEILING_Y, gd0, gd1, PINE, "WoodPlanks", soft)
	kit:box(m, "ChairRail", x1 - 0.12, x1, 3.1, 3.35, gd0, gd1, WOOD_DARK, "Wood", soft)
	kit:box(m, "WainscotBack", px, x1, 0, 3.2, gd1 - 0.08, gd1, WOOD, "WoodPlanks", soft)
	kit:box(m, "PinePanelBack", px, x1, 3.2, L.CEILING_Y, gd1 - 0.06, gd1, PINE, "WoodPlanks", soft)
	kit:box(m, "ChairRailBack", px, x1, 3.1, 3.35, gd1 - 0.12, gd1, WOOD_DARK, "Wood", soft)
	-- the partition: panelled between the openings
	local cuts = {}
	for _, o in L.OPENINGS do
		if o.axis == "d" and o.at == L.GAME_ROOM_X0 then
			table.insert(cuts, { o.a, o.b })
		end
	end
	table.sort(cuts, function(p, q)
		return p[1] < q[1]
	end)
	local from = gd0
	table.insert(cuts, { gd1, gd1 })
	for _, cut in cuts do
		if cut[1] > from + 0.01 then
			kit:box(m, "WainscotWest", px, px + 0.08, 0, 3.2, from, cut[1], WOOD, "WoodPlanks", soft)
			kit:box(m, "PinePanelWest", px, px + 0.06, 3.2, L.CEILING_Y, from, cut[1], PINE, "WoodPlanks", soft)
			kit:box(m, "ChairRailWest", px, px + 0.12, 3.1, 3.35, from, cut[1], WOOD_DARK, "Wood", soft)
		end
		from = cut[2]
	end
	-- "GAMES ROOM" over each opening, on the hall side
	for _, id in { "games_arch", "games_side" } do
		local o = L.opening(id)
		local mid = (o.a + o.b) / 2
		local sign = kit:box(
			m,
			"GamesSign",
			L.GAME_ROOM_X0 - 0.06,
			L.GAME_ROOM_X0 - 0.02,
			o.head + 0.3,
			o.head + 1.9,
			mid - 5,
			mid + 5,
			{ 26, 30, 60 },
			"SmoothPlastic",
			soft
		)
		kit:label(kit:gui(sign, "Left", 30), { Text = "GAMES ROOM", TextColor = { 255, 214, 92 }, Font = "FredokaOne" })
	end
	-- lights: a grid of warm troffers over the floor (none casts shadows: the pool tables bring their own lamps)
	-- and a low amber lamp in the fortune teller's corner
	local wide = x1 - px
	for _, d in { gd0 + 12, gd0 + 38, gd0 + 64, gd1 - 10 } do
		for _, fx in { 0.26, 0.74 } do
			local cx = px + wide * fx
			local troffer = kit:box(
				m,
				"GamesTroffer",
				cx - 3,
				cx + 3,
				L.CEILING_Y - 0.14,
				L.CEILING_Y - 0.04,
				d - 1,
				d + 1,
				{ 250, 240, 220 },
				"Neon",
				{ collide = false, shadow = false }
			)
			kit:light(
				troffer,
				"PointLight",
				{ Range = 26, Brightness = 1.0, Color = { 255, 236, 210 }, Shadows = false }
			)
		end
	end
	local f = L.FORTUNE
	local cornerLight = kit:box(
		m,
		"CornerLamp",
		f.x - 3.5,
		f.x - 2.5,
		L.CEILING_Y - 2,
		L.CEILING_Y - 1.8,
		f.d - 3.5,
		f.d - 2.5,
		{ 255, 200, 140 },
		"Neon",
		soft
	)
	kit:light(cornerLight, "PointLight", { Range = 16, Brightness = 1.4, Color = { 255, 196, 140 }, Shadows = false })
end

function GamesRoom.build(kit: any, root: any)
	gamesRoom(kit, root)
end

return GamesRoom
