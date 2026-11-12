--!strict
-- tools/bake/games/BumperPool: bumper pool's furniture in the bowling alley's games room (brief v2 §13a), built once per
-- station through the bake registry (tools/bake/GameBakes). One small table with its bumpers, two cups and ten balls.
-- The game is NOT BUILT YET: this is the set dressing the room had, moved here unchanged so that the game's
-- builder owns it. Rebuild it with uniquely named moving parts (the server and the client find parts by name).
-- Interface: { build(kit, parent, station, venue) }: kit = tools/bake/alley/Kit in the site's frame, parent =
--   the GamesRoom model, station = the Spec's StationDef (index, variant, x, d). Names: GamesRoom.BumperPool.

local AlleyLayout = require("../../../src/shared/Attractions/AlleyLayout")

local Bake = {}
local L = AlleyLayout

local WOOD = { 104, 66, 40 }
local WOOD_DARK = { 70, 44, 28 }
local BLACK = { 24, 24, 26 }

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

function Bake.build(kit: any, parent: any, _station: any, _venue: any?)
	bumperPool(kit, parent)
end

return Bake
