local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local AlleyRoof = require("@shared/Attractions/AlleyRoof")
local RafterSense = require("@shared/Stealth/RafterSense")
local RafterWatch = require("@shared/Stealth/RafterWatch")
local BakedWorld = require("@tests/lib/BakedWorld")
local process = require("@lune/process")
local aimUp = tonumber(process.args[1]) or 0.85
local slack = tonumber(process.args[2]) or 1.2
local baked, place = BakedWorld.bakeAlley()
local two = process.args[3] == "two"
local function canSee1(o, s, up)
	local ex, ey, ez = AlleyLayout.toWorld(place, o.X, o.Y, o.D)
	local wx, wy, wz = AlleyLayout.toWorld(place, s.X, s.Y + up, s.D)
	local dx, dy, dz = wx - ex, wy - ey, wz - ez
	local hit = baked.raycast(ex, ey, ez, dx, dy, dz, function(q)
		return q.query
	end)
	return hit == nil or (1 - hit) * math.sqrt(dx * dx + dy * dy + dz * dz) <= slack
end
local function canSee(o, s)
	if two then
		return canSee1(o, s, 0.85) or canSee1(o, s, 1.6)
	end
	return canSee1(o, s, aimUp)
end
local settee = {}
for _, x in { -10, 10, 30, 50, 70, 90 } do
	table.insert(settee, { id = "s" .. x, X = x, Y = 5.0, D = -21, faceX = 0, faceD = 1 })
end
local bowlers = {}
for lane = 1, 18 do
	table.insert(bowlers, { id = "b" .. lane, X = AlleyLayout.laneX(lane), Y = 5.2, D = -6, faceX = 0, faceD = 1 })
end
local function run(D, speed, lanes)
	local obs = {}
	for _, l in lanes do
		table.insert(obs, bowlers[l])
	end
	local sense, watch = RafterSense.new(), RafterWatch.new()
	local X, peak, spotted = 96, 0, nil
	local clock, TICK = 0, 0.2
	local seenTicks, ticks = 0, 0
	while X > -25 do
		local s = RafterSense.sense(sense, "sq", X, AlleyRoof.CHORD.y1, D, TICK)
		if s then
			ticks += 1
			local any = false
			for _, o in obs do
				if canSee(o, s) then
					any = true
				end
			end
			if any then
				seenTicks += 1
			end
			for _, e in RafterWatch.step(watch, { s }, obs, nil, TICK, canSee) do
				if e.kind == "spotted" and not spotted then
					spotted = clock
				end
			end
			peak = math.max(peak, (RafterWatch.meter(watch, "sq")))
		end
		X -= speed * TICK
		clock += TICK
	end
	return peak, spotted, seenTicks / math.max(1, ticks)
end
local saved = bowlers
local all = {}
for l = 1, 18 do
	table.insert(all, l)
end
for _, D in AlleyRoof.TRUSS_D do
	if D > 53 then
		continue
	end
	for _, sp in { { "creep", 3 }, { "walk", 18 }, { "sprint", 30.5 } } do
		local p1, s1, f1 = run(D, sp[2], all)
		local p2, s2, f2 = run(D, sp[2], { 17 })
		if process.args[4] == "settee" then
			bowlers = settee
			p2, s2, f2 = run(D, sp[2], { 1, 2, 3, 4, 5, 6 })
			bowlers = saved
		end
		print(
			string.format(
				"D %5.1f %-6s all18: peak %.2f spotted %s inview %.2f | lane17: peak %.2f spotted %s inview %.2f",
				D,
				sp[1],
				p1,
				tostring(s1),
				f1,
				p2,
				tostring(s2),
				f2
			)
		)
	end
end
