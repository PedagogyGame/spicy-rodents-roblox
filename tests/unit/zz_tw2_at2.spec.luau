--!strict
local AirTrick = require("@shared/Movement/AirTrick")
return function(t)
	t.test("dbg2", function()
		for f = 27, 31 do
			local ang = math.pi * f / 60
			local b = AirTrick.blend(-math.cos(ang), math.sin(ang), 117)
			local s = string.format("f%d side %.3f: ", f, -math.cos(ang))
			for _, m in AirTrick.MOVES do
				s ..= string.format("%s=%.3f ", m, b[m])
			end
			local r = AirTrick.twitch(f / 60, -math.cos(ang), math.sin(ang), 117).Root or {}
			print(s, r[1], r[2], r[3])
		end
	end)
end
