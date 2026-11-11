local process = require("@lune/process")
local Bot = require("../../src/shared/Minigames/Pinball/Bot")
local Machine = require("../../src/shared/Minigames/Pinball/Machine")
local Tables = require("../../src/shared/Minigames/Pinball/Tables")

local id = process.args[1] or "pinball_acorn"
local level = tonumber(process.args[2]) or 3
local GAMES = tonumber(process.args[3]) or 20
local tbl = Tables.need(id)
local CUE = Machine.CUE

local kinds: { [string]: number } = {}
local trapsStarted, trapsSettled, aimed = 0, 0, 0
local drains = 0
local xs = {}
for seed = 1, GAMES do
	local m = Machine.new(tbl, seed, 1)
	local bot = Bot.new(level, seed * 977 + level)
	local out = {}
	local n = 0
	local lastFlipperHit, lastFlip = -9999, -9999
	local prevMode = { 0, 0 }
	local hist = {}
	while m.phase ~= Machine.PHASE.OVER and n < 240 * 60 * 60 do
		local b = m.phys.balls[1]
		if b then
			table.insert(hist, { b.x, b.y, b.vx, b.vy })
			if #hist > 240 then
				table.remove(hist, 1)
			end
		end
		Machine.step(tbl, m, Bot.step(bot, tbl, m), out)
		n += 1
		for i = 1, 2 do
			if bot.mode[i] == 4 and prevMode[i] ~= 4 then
				trapsStarted += 1
			end
			if prevMode[i] == 4 and bot.mode[i] == 0 then
				trapsSettled += 1
			end
			prevMode[i] = bot.mode[i]
		end
		for k = 1, #out, 3 do
			local cue = out[k]
			if cue == CUE.FLIPPER_HIT then
				lastFlipperHit = n
			elseif cue == CUE.FLIP_UP then
				lastFlip = n
			elseif cue == CUE.DRAIN then
				drains += 1
				local x = out[k + 2]
				local where = if x < tbl.def.flippers[1].x then "outlane L" elseif x > tbl.def.flippers[2].x then "outlane R" else "centre"
				local how
				if where ~= "centre" then
					how = where
				elseif n - lastFlip > 240 and n - lastFlipperHit > 240 then
					how = "centre, untouched and no flip in the last second"
				elseif n - lastFlip > 240 then
					how = "centre, touched a resting flipper, no flip"
				elseif n - lastFlipperHit > 120 then
					how = "centre, flipped but missed"
				else
					how = "centre, after a flipper hit"
				end
				kinds[how] = (kinds[how] or 0) + 1
				if where == "centre" and #xs < 12 then
					-- where was it and how fast, when it crossed y = 1.0 on the way down
					for h = #hist, 1, -1 do
						if hist[h][2] > 1.0 then
							table.insert(xs, string.format("(%.2f v %.1f,%.1f; mode %d/%d)", hist[h][1], hist[h][3], hist[h][4], bot.mode[1], bot.mode[2]))
							break
						end
					end
				end
			end
		end
		table.clear(out)
	end
end
print(id, Bot.NAMES[level], "drains", drains, "traps started", trapsStarted, "settled", trapsSettled)
for k, v in kinds do
	print(string.format("   %-55s %4.0f%%", k, v / drains * 100))
end
print("   centre drains crossed y=1.0 at: " .. table.concat(xs, " "))
