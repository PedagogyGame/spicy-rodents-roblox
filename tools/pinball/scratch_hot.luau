local Layout = require("../../src/shared/Minigames/Pinball/Layout")
local Machine = require("../../src/shared/Minigames/Pinball/Machine")
local Tables = require("../../src/shared/Minigames/Pinball/Tables")

local tbl = Tables.need("pinball_rodent")
local def = tbl.def
local X1 = Layout.FIELD_X1
local target
for _, w in def.walls do
	if #w.pts == 4 and math.abs(w.pts[1] - (X1 - 0.16)) < 1e-9 and math.abs(w.pts[2] - 2.24) < 1e-9 and w.pts[3] == X1 then
		target = w
	end
end
assert(target, "wall not found")
for _, topY in { 2.5, 2.6, 2.7, 2.8, 2.9, 3.0, 3.1 } do
	target.pts[4] = topY;
	(tbl :: any).c = Layout.compile(def)
	local parts = {}
	for _, pull in { 0.08, 0.1, 0.12, 0.14, 0.16, 0.18, 0.2, 0.22 } do
		local m = Machine.new(tbl, 11, 1)
		local out = {}
		local hold = math.floor(pull * def.plunger.pullTicks + 0.5)
		for k = 1, hold + 1 do
			Machine.step(tbl, m, if k <= hold then Machine.BTN.PLUNGE else 0, out)
		end
		local land = "-"
		local prevY = 9
		for _ = 1, 1500 do
			Machine.step(tbl, m, 0, out)
			local b = m.phys.balls[1]
			if b == nil then
				break
			end
			if m.launched and prevY > 0.85 and b.y <= 0.85 then
				land = string.format("%.2f(v%.1f,%.1f)", b.x, b.vx, b.vy)
				break
			end
			prevY = b.y
		end
		table.insert(parts, land)
	end
	print(topY, table.concat(parts, " "))
end
print("right flipper spans", tbl.c.fpx[2] - 0.33 * math.cos(math.rad(30)), tbl.c.fpx[2])
