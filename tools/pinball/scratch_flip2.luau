local Machine = require("../../src/shared/Minigames/Pinball/Machine")
local Physics = require("../../src/shared/Minigames/Pinball/Physics")
local Tables = require("../../src/shared/Minigames/Pinball/Tables")
local tbl = Tables.need("pinball_acorn")
local c = tbl.c
local P = Physics :: any

local function clone(s: Physics.State): Physics.State
	local m = Machine.new(tbl, 1, 1)
	m.phys = s
	return Machine.clone(m).phys
end

local function shotTable(label: string)
	local s0 = Physics.new(c, 1)
	local ev = {}
	Physics.addBall(s0, 0.25, 1.3, 0, 0)
	local settled = false
	for _ = 1, 240 * 8 do
		Physics.step(c, s0, true, false, ev)
		if s0.balls[1].asleep then
			settled = true
			break
		end
	end
	local row = {}
	local rest = c.frest[1]
	for d = 40, 260, 8 do
		local s = clone(s0)
		local b = s.balls[1]
		for _ = 1, d do
			Physics.step(c, s, false, false, ev)
		end
		local along = ((b.x - c.fpx[1]) * math.cos(rest) + (b.y - c.fpy[1]) * math.sin(rest)) / c.flen[1]
		local vx, vy = 0, 0
		local got = false
		for _ = 1, 240 do
			Physics.step(c, s, true, false, ev)
			if not got and b.y > 1.0 and b.vy > 0 then
				vx, vy = b.vx, b.vy
				got = true
				break
			end
			if b.mode ~= 0 then
				break
			end
		end
		if got and along > 0.05 and along < 1.03 then
			table.insert(row, string.format("%.2f:%+.0f/%.0f", along, math.deg(math.atan2(vx, vy)), math.sqrt(vx * vx + vy * vy)))
		end
	end
	print(label, settled and "" or "(NO CRADLE)")
	print("   " .. table.concat(row, " "))
end

for _, up in { 28, 34, 38 } do
	c.fup[1] = math.rad(up)
	c.fup[2] = math.rad(up)
	for _, mu in { 0.15, 0.2, 0.3 } do
		P.FLIP_MU = mu
		shotTable(`up {up} mu {mu}`)
	end
end
