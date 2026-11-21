--!nocheck
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local Units = require("@shared/Config/Units")
local TestWorld = require("@tests/cheat/TestWorld")
local P = SquirrelMotor.params
local world = TestWorld.build({ boxes = {} })
local function keys(o)
	local i = SquirrelMotor.idleInput(math.pi)
	for k, v in o or {} do
		i[k] = v
	end
	return i
end
-- a leap after `pre` frames of `hold`; the trick pressed `at` frames after takeoff (nil: none), the aim held `reach`
local function jump(pre, hold, winded, at, reach, cam)
	local s = SquirrelMotor.new(Units.st(-560), world.groundHeight, Units.st(-545))
	if winded then
		s.stamina = 0
		s.winded = true
	end
	for _ = 1, pre do
		SquirrelMotor.step(s, keys(hold), 1 / 60, world)
	end
	local x0, z0 = s.x, s.z
	local h = table.clone(hold)
	h.leap = true
	SquirrelMotor.step(s, keys(h), 1 / 60, world)
	local n = 1
	local peak, pressed = 0, false
	local maxStep = 0
	while not s.grounded do
		local k = table.clone(hold)
		if at and n == at then
			k.trick = true
			pressed = true
			if cam then
				k.cameraYaw = cam
			end
		elseif cam and pressed then
			k.cameraYaw = cam
		end
		if pressed and s.trickKind == 2 then
			k.aimReach = reach
		end
		local ox, oz = s.x, s.z
		SquirrelMotor.step(s, keys(k), 1 / 60, world)
		if pressed then
			maxStep = math.max(maxStep, math.sqrt((s.x - ox) ^ 2 + (s.z - oz) ^ 2) * 60)
		end
		peak = math.max(peak, math.sqrt(s.vx ^ 2 + s.vz ^ 2))
		n += 1
	end
	return math.sqrt((s.x - x0) ^ 2 + (s.z - z0) ^ 2), n, maxStep, s.x - x0, s.z - z0
end
local kinds = {
	{ "standing", 0, {}, false },
	{ "standing W", 0, { fw = 1 }, false },
	{ "running W", 60, { fw = 1 }, false },
	{ "sprint", 60, { fw = 1, sprint = true }, false },
	{ "winded W", 60, { fw = 1 }, true },
}
for _, k in kinds do
	local plain, frames = jump(k[2], k[3], k[4])
	local line = string.format("%-11s plain %5.2f st (%d fr) |", k[1], plain, frames)
	local best, bestAll = 0, 0
	for _, at in { 3, 9, 15, 21, 26, 32, 38 } do
		local b, _, peak = jump(k[2], k[3], k[4], at, 0)
		local o = jump(k[2], k[3], k[4], at, 1)
		line ..= string.format(" %2d: +%.2f (%4.1f%%) / +%.2f (%4.1f%%) pk %.0f |", at, b - plain, (b / plain - 1) * 100, o - plain, (o / plain - 1) * 100, peak)
		best = math.max(best, b / plain - 1)
		bestAll = math.max(bestAll, o / plain - 1)
	end
	print(line)
	local worst = 0
	for at = 2, frames - 10 do
		worst = math.max(worst, jump(k[2], k[3], k[4], at, 1) / plain - 1)
	end
	print(string.format("   best burst %.1f%%, best burst+out %.1f%% (every press %.1f%%)", best * 100, bestAll * 100, worst * 100))
end
-- a turn: sprint leap, camera swung 45 deg and 120 deg at the press
for _, deg in { 0, 30, 60, 90, 120, 180 } do
	local d, _, _, dx, dz = jump(60, { fw = 1, sprint = true }, false, 20, 0, math.pi + math.rad(deg))
	print(string.format("turn %3d: landed %.1f st away, bearing %.1f deg", deg, d, math.deg(math.atan2(dx, dz))))
end
