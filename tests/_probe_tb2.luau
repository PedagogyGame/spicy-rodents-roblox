--!nocheck
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local TestWorld = require("@tests/cheat/TestWorld")
local world = TestWorld.build({ boxes = {} })
-- a person's chain: on the rail `rest` frames, Space; in the air G `after` frames in (nil: never), E `m` frames in
local function slow(id, t0, yaw, rest, m, after, empty, t1, t2)
	local r = world.registry:get(id)
	local p = world.registry:pointAt(r, t0)
	local s = SquirrelMotor.new(p.x, p.y, p.z)
	s.routeId, s.railT, s.grounded, s.clock, s.yaw = id, t0, false, 0, yaw
	if empty then
		s.stamina, s.winded = 0, true
	end
	local x0, z0 = s.x, s.z
	local fx, fz = -math.sin(yaw), -math.cos(yaw)
	local function gone()
		return (s.x - x0) * fx + (s.z - z0) * fz
	end
	local g1, on, air, presses, fell = 0, 0, 0, 0, false
	for f = 1, math.floor(t2 * 60 + 0.5) do
		local i = SquirrelMotor.idleInput(yaw)
		i.fw, i.sprint = 1, true
		if s.routeId ~= nil then
			on += 1
			air = 0
			i.leap = on > rest
		elseif not s.grounded then
			on = 0
			air += 1
			i.trick = after ~= nil and air == after + 1
			i.grab = air >= m
		else
			fell = true
		end
		local _, ev = SquirrelMotor.step(s, i, 1 / 60, world)
		for _, e in ev do
			if e.kind == "trick" then
				presses += 1
			end
		end
		if f == math.floor(t1 * 60 + 0.5) then
			g1 = gone()
		end
	end
	return (gone() - g1) / (t2 - t1), presses, fell
end
local function heading(id, t0)
	local a, b =
		world.registry:pointAt(world.registry:get(id), t0), world.registry:pointAt(world.registry:get(id), t0 + 0.1)
	return math.atan2(-(b.x - a.x), -(b.z - a.z))
end
for _, case in { { "parapet", 1075 }, { "cable", 660 } } do
	local yaw = heading(case[2], 0.02)
	for _, rest in { 16, 24 } do
		for _, m in { 6, 10, 20, 40 } do
			local line = string.format("%-8s rest %d air %2d:", case[1], rest, m)
			for _, after in { false, 0, 2 } do
				for _, empty in { false, true } do
					local v, n, fell = slow(case[2], 0.02, yaw, rest, m, after or nil, empty, 1, 9)
					line ..= string.format(
						" %s%s %.1f (%d%s)",
						if after then "G+" .. after else "none",
						if empty then "e" else "f",
						v,
						n,
						if fell then " fell" else ""
					)
				end
			end
			print(line)
		end
	end
end
