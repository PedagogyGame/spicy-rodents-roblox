local process = require("@lune/process")
local Bot = require("../../src/shared/Minigames/Pinball/Bot")
local Machine = require("../../src/shared/Minigames/Pinball/Machine")
local Tables = require("../../src/shared/Minigames/Pinball/Tables")

local GAMES = tonumber(process.args[1]) or 5
local only = process.args[2]
for _, id in Tables.IDS do
	if only and not string.find(id, only, 1, true) then
		continue
	end
	local tbl = Tables.need(id)
	local spots: { [string]: number } = {}
	for level = 1, 3 do
		for seed = 1, GAMES do
			local m = Machine.new(tbl, seed, 1)
			local bot = Bot.new(level, seed * 977)
			local out = {}
			local n = 0
			while m.phase ~= Machine.PHASE.OVER and n < 240 * 60 * 30 do
				local pre = {}
				if m.quiet == Machine.SEARCH_TICKS - 1 then
					for _, b in m.phys.balls do
						if b.mode == 0 then
							table.insert(pre, string.format("%.2f,%.2f%s", b.x, b.y, if b.asleep then "" else "~"))
						end
					end
				end
				Machine.step(tbl, m, Bot.step(bot, tbl, m), out)
				n += 1
				for i = 1, #out, 3 do
					if out[i] == Machine.CUE.SEARCH then
						for _, p in pre do
							spots[p] = (spots[p] or 0) + 1
						end
					end
				end
				table.clear(out)
			end
		end
	end
	local list = {}
	for k, v in spots do
		table.insert(list, { k = k, v = v })
	end
	table.sort(list, function(a, b)
		return a.v > b.v
	end)
	local parts = {}
	for i = 1, math.min(25, #list) do
		table.insert(parts, `{list[i].k} x{list[i].v}`)
	end
	print(id, "ball search spots:", table.concat(parts, "  "))
end
