--!strict
-- tools/games/pinball/camera.luau: what the player's camera shows of each machine, measured (no engine): for
-- each view (Shared/Minigames/Pinball/Cabinet.EYES) and screen, where the playfield's corners, the flippers,
-- the plunger and the pop bumpers land in the picture (pixels), and how many pixels a stud of the table's
-- length is near the flippers and at the top (how much the far end is squeezed). The HUD's places
-- (Client/Minigames/Pinball/Controller) were chosen from these numbers; tests/unit/pinball_glue.spec.luau
-- holds them.
-- Run (repo root): lune run tools/games/pinball/camera.luau
local Cabinet = require("../../../src/shared/Minigames/Pinball/Cabinet")
local Layout = require("../../../src/shared/Minigames/Pinball/Layout")
local Tables = require("../../../src/shared/Minigames/Pinball/Tables")

local SCREENS = { { 1920, 1080 }, { 1280, 720 }, { 1024, 768 }, { 844, 390 }, { 1334, 750 } }
for _, which in { "play", "high" } do
	for _, s in SCREENS do
		local w, h = s[1], s[2]
		local v = Cabinet.camera(2, w / h, which)
		local function px(x: number, y: number): (number, number)
			local u, q = Cabinet.project(v, Cabinet.point(2, x, y, 0))
			return math.floor(u * w + 0.5), math.floor(q * h + 0.5)
		end
		local function perStud(y: number): number
			local _, a = px(Layout.WIDTH / 2, y - 0.05)
			local _, b = px(Layout.WIDTH / 2, y + 0.05)
			return (a - b) / 0.1
		end
		local tbl = Tables.need("pinball_rodent")
		local corners = {}
		for _, c in { { 0, 0 }, { Layout.WIDTH, 0 }, { 0, Layout.LENGTH }, { Layout.WIDTH, Layout.LENGTH } } do
			local a, b = px(c[1], c[2])
			table.insert(corners, `({a},{b})`)
		end
		local flippers = {}
		for i = 1, tbl.c.nFlip do
			local a, b = px(tbl.c.fpx[i], tbl.c.fpy[i])
			table.insert(flippers, `({a},{b})`)
		end
		local pa, pb = px(tbl.def.plunger.x, tbl.def.plunger.y)
		local bumpers = {}
		for _, bm in tbl.def.bumpers do
			local a, b = px(bm.x, bm.y)
			table.insert(bumpers, `({a},{b})`)
		end
		print(
			`{which} {w}x{h} fov {string.format("%.1f", v.fov)} eye y {string.format("%.2f", v.eye[2])}:`
				.. ` corners {table.concat(corners, " ")}; flippers {table.concat(flippers, " ")};`
				.. ` plunger ({pa},{pb}); bumpers {table.concat(bumpers, " ")};`
				.. ` px/stud near {string.format("%.0f", perStud(0.6))} top {string.format(
					"%.0f",
					perStud(Layout.LENGTH - 0.6)
				)}`
		)
	end
end
