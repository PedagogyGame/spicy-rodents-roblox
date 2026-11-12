--!strict
-- tools/bake/games/Pool: pool's furniture in the bowling alley's games room (brief v2 §13a), built once per
-- station through the bake registry (tools/bake/GameBakes). Two tables, racked and ready, each with its lamp.
-- The game is NOT BUILT YET: this is the set dressing the room had, moved here unchanged so that the game's
-- builder owns it. Rebuild it with uniquely named moving parts (the server and the client find parts by name).
-- Interface: { build(kit, parent, station, venue) }: kit = tools/bake/alley/Kit in the site's frame, parent =
--   the GamesRoom model, station = the Spec's StationDef (index, variant, x, d). Names: GamesRoom.Pool<index>.

local Bake = {}

local WOOD = { 104, 66, 40 }
local WOOD_DARK = { 70, 44, 28 }
local FELT = { 30, 110, 70 }
local BRASS = { 196, 160, 80 }
local BLACK = { 24, 24, 26 }

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
	kit:light(glow, "PointLight", { Range = 13, Brightness = 0.9, Color = { 255, 236, 200 }, Shadows = false })
	return m
end

function Bake.build(kit: any, parent: any, station: any, _venue: any?)
	poolTable(kit, parent, `Pool{station.index}`, station.x, station.d)
end

return Bake
