local Bot = require("../../src/shared/Minigames/Pinball/Bot")
local Machine = require("../../src/shared/Minigames/Pinball/Machine")
local Tables = require("../../src/shared/Minigames/Pinball/Tables")

local tbl = Tables.need("pinball_acorn")
local m = Machine.new(tbl, 1, 1)
local bot = Bot.new(3, 5)
local out = {}
local b = m.phys.balls[1]
b.x, b.y, b.vx, b.vy = tbl.c.fpx[1] + 0.15, 1.6, 0, 0
m.launched = true
for tick = 1, 1500 do
	local buttons = Bot.step(bot, tbl, m)
	Machine.step(tbl, m, buttons, out)
	if tick % 20 == 0 or (tick > 80 and tick < 140) then
		local bb = m.phys.balls[1]
		if bb == nil then
			print(tick, "no ball; phase", m.phase)
			break
		end
		print(string.format("%4d  ball %.3f,%.3f v %.2f,%.2f asleep %s  buttons %d  mode %d/%d timer %d still %d aim %.2f  fa %.2f", tick, bb.x, bb.y, bb.vx, bb.vy, tostring(bb.asleep), buttons, bot.mode[1], bot.mode[2], bot.timer[1], bot.still[1], bot.aim[1], m.phys.fa[1]))
	end
end
print("score", m.scores[1])
