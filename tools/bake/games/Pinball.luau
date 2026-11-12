--!strict
-- tools/bake/games/Pinball: pinball's furniture in the bowling alley's games room (brief v2 §13a), built once per
-- station through the bake registry (tools/bake/GameBakes). Three machines in distinct themes (the station's variant: acorn, rodent, space).
-- The game is NOT BUILT YET: this is the set dressing the room had, moved here unchanged so that the game's
-- builder owns it. Rebuild it with uniquely named moving parts (the server and the client find parts by name).
-- Interface: { build(kit, parent, station, venue) }: kit = tools/bake/alley/Kit in the site's frame, parent =
--   the GamesRoom model, station = the Spec's StationDef (index, variant, x, d). Names: GamesRoom.Pinball<index>.

local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")

local Bake = {}
local L = AlleyLayout

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

function Bake.build(kit: any, parent: any, station: any, _venue: any?)
	local at = L.PINBALLS[station.index]
	pinball(kit, parent, station.index, at.x, station.variant)
end

return Bake
