--!strict
local AirTrick = require("@shared/Movement/AirTrick")
return function(t)
	t.test("dbg", function()
		local function rot(r: { number }?): { number }
			local a, b, c = if r then r[1] or 0 else 0, if r then r[2] or 0 else 0, if r then r[3] or 0 else 0
			local ca, sa, cb, sb, cc, sc = math.cos(a), math.sin(a), math.cos(b), math.sin(b), math.cos(c), math.sin(c)
			return { cb * cc, -cb * sc, sb, ca * sc + sa * sb * cc, ca * cc - sa * sb * sc, -sa * cb, sa * sc - ca * sb * cc, sa * cc + ca * sb * sc, ca * cb }
		end
		local function apart(m: { number }, n: { number }): number
			local tr = 0
			for i = 1, 9 do
				tr += m[i] * n[i]
			end
			return math.acos(math.clamp((tr - 1) / 2, -1, 1))
		end
		local worst, at = 0, ""
		for seed = 0, 1023, 3 do
			local prev: any = nil
			for f = 1, 479 do
				local p = f / 480
				local ang = math.pi * p
				local pose = AirTrick.twitch(p, -math.cos(ang), math.sin(ang), seed)
				if prev then
					local d = apart(rot(pose.Root), rot(prev.Root))
					if d > worst then
						worst = d
						local r0, r1 = prev.Root or {}, pose.Root or {}
						at = string.format("seed %d f %d: %.3f,%.3f,%.3f -> %.3f,%.3f,%.3f", seed, f, r0[1] or 0, r0[2] or 0, r0[3] or 0, r1[1] or 0, r1[2] or 0, r1[3] or 0)
					end
				end
				prev = pose
			end
		end
		print(worst, at)
	end)
end
