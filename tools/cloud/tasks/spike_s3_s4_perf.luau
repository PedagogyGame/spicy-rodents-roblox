--!strict
-- Luau Execution task (spikes S3 + S4): engine timing of the per-tick server costs on a saved version.
-- S4: SweptCollision.step with 15 squirrel actors x 50 moving vehicles for 600 ticks at 30 Hz.
-- S3: MoveValidator is measured in Lune (0.007 ms per squirrel per tick); here we only confirm the
-- module loads in the engine.
local SSS = game:GetService("ServerScriptService")
local server = SSS:WaitForChild("Server")
local SweptCollision = (require :: any)(server:WaitForChild("Traffic"):WaitForChild("SweptCollision"))
local _MoveValidator = (require :: any)(server:WaitForChild("Movement"):WaitForChild("MoveValidator"))

local rng = Random.new(4105)
local kinds = { "sedan", "delivery_van", "ice_cream_van", "trolley", "dump_truck", "rv" }
local sc = SweptCollision.new()
local vehicles, actors = {}, {}
for i = 1, 50 do
	local yaw = rng:NextNumber(-math.pi, math.pi)
	local x, z = rng:NextNumber(-150, 150), rng:NextNumber(-150, 150)
	vehicles[i] = {
		id = i,
		kind = kinds[(i % #kinds) + 1],
		x = x,
		y = 0.1,
		z = z,
		yaw = yaw,
		prevX = x,
		prevY = 0.1,
		prevZ = z,
		prevYaw = yaw,
		visible = true,
		prevVisible = true,
		speed = rng:NextNumber(10, 25),
	}
end
for i = 1, 15 do
	local x, z = rng:NextNumber(-150, 150), rng:NextNumber(-150, 150)
	actors[i] =
		{ id = i, x = x, y = 0.45, z = z, prevX = x, prevY = 0.45, prevZ = z, ang = rng:NextNumber(-math.pi, math.pi) }
end
local dt = 1 / 30
local total, maxT, hits = 0, 0, 0
for _ = 1, 600 do
	for _, v in vehicles do
		v.prevX, v.prevY, v.prevZ, v.prevYaw = v.x, v.y, v.z, v.yaw
		v.x += math.sin(v.yaw) * v.speed * dt
		v.z += math.cos(v.yaw) * v.speed * dt
		if math.abs(v.x) > 160 or math.abs(v.z) > 160 then
			v.yaw += math.pi
		end
	end
	for _, a in actors do
		a.prevX, a.prevY, a.prevZ = a.x, a.y, a.z
		a.ang += rng:NextNumber(-0.3, 0.3)
		a.x = math.clamp(a.x + math.sin(a.ang) * 40 * dt, -160, 160)
		a.z = math.clamp(a.z + math.cos(a.ang) * 40 * dt, -160, 160)
	end
	local t0 = os.clock()
	local h = sc:step(actors, vehicles, dt)
	local t = (os.clock() - t0) * 1000
	total += t
	maxT = math.max(maxT, t)
	hits += #h
end
local result =
	{ suite = "S3S4Perf", ok = (total / 600) <= 0.5, sweptMsAvg = total / 600, sweptMsMax = maxT, hits = hits }
print(
	`S4 engine: SweptCollision 15x50 avg {string.format("%.4f", result.sweptMsAvg)} ms, max {string.format("%.4f", maxT)} ms, hits {hits}`
)
return result
