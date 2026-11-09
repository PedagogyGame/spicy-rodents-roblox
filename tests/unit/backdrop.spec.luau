--!strict
-- World/Backdrop and tools/bake/backdrop (BUILD_PLAN W6 #1, worldgen_districts_art §14.4): the boot terrain beyond
-- the clamp is continuous with World/Height and hides the land mesh it settles on; the coast reaches the sea at the
-- waterline; the sun model matches the engine's measured GetSunDirection; the tower stands on the sunset azimuth;
-- and the baked rbxm keeps every part <= 2048 st per axis, anchored, untouchable and inside Persistent models.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Height = require("@shared/World/Height")
local Backdrop = require("@shared/World/Backdrop")

return function(t)
	local ext = require("../../generated/TerrainExtensions") :: any
	Height.configure(ext)
	Backdrop.reset()
	local c = Backdrop.clamp()

	t.test("band: continuous with World/Height at the clamp edge, identical inside", function()
		local worst = 0
		for x = c.minX, c.maxX, 97 do
			worst = math.max(worst, math.abs(Backdrop.groundAt(x, c.minZ - 0.5) - Height.at(x, c.minZ)))
		end
		for z = c.minZ, 1200, 97 do
			worst = math.max(worst, math.abs(Backdrop.groundAt(c.minX - 0.5, z) - Height.at(c.minX, z)))
			worst = math.max(worst, math.abs(Backdrop.groundAt(c.maxX + 0.5, z) - Height.at(c.maxX, z)))
		end
		t.truthy(worst < 0.05, `edge step {worst}`)
		for _, p in { { 0, 0 }, { 2000, -1000 }, { -1400, 900 }, { 4000, 1200 }, { 300, 1340 } } do
			t.eq(Backdrop.groundAt(p[1], p[2]), Height.at(p[1], p[2]))
		end
	end)

	t.test("band: the terrain stays above the drawn land mesh (no plastic poking through the grass)", function()
		local m = Backdrop.mesh()
		local worst, n = math.huge, 0
		for _, r in Backdrop.terrainRects() do
			for x = r.minX + 2, r.maxX - 2, 23 do
				for z = r.minZ + 2, r.maxZ - 2, 23 do
					local d = Backdrop.outside(x, z)
					if d > Backdrop.MESH_INSET + 1 then
						-- only where a mesh cell is drawn
						local i, k = 1, 1
						while i < #m.xs - 1 and m.xs[i + 1] <= x do
							i += 1
						end
						while k < #m.zs - 1 and m.zs[k + 1] <= z do
							k += 1
						end
						if m.drawn(i, k) then
							worst = math.min(worst, Backdrop.groundAt(x, z) - Backdrop.meshHeight(x, z))
							n += 1
						end
					end
				end
			end
		end
		print(`      {n} band samples over the mesh; smallest clearance {string.format("%.2f", worst)} st`)
		t.truthy(n > 1000)
		t.truthy(worst >= 0.4, `clearance {worst}`)
	end)

	t.test("coast: the waterline at shoreZ, the shelf under the ocean plane where the plane starts", function()
		for x = c.minX - 300, c.maxX + 300, 211 do
			t.near(Backdrop.groundAt(x, Backdrop.shoreZ(x)), Backdrop.SEA_Y, 1e-6, `waterline at x {x}`)
			t.truthy(Backdrop.groundAt(x, Backdrop.OCEAN_NEAR_Z) < Backdrop.OCEAN_Y, `shelf at x {x}`)
			t.truthy(Backdrop.groundAt(x, Backdrop.shoreZ(x) - 60) > Backdrop.SEA_Y, `beach at x {x}`)
			t.eq(Backdrop.materialAt(x, Backdrop.shoreZ(x) - 20, Backdrop.groundAt(x, Backdrop.shoreZ(x) - 20)), "Sand")
		end
		-- the rewrite starts where the coast blend is zero: the town's beach is untouched there
		for x = -800, 4000, 400 do
			t.eq(Backdrop.groundAt(x, Backdrop.NORTH_FROM_Z), Height.at(x, Backdrop.NORTH_FROM_Z))
		end
	end)

	t.test("sun model: matches the engine's GetSunDirection at latitude 39 (CI v32 probe)", function()
		local probe = {
			{ 6, 0.964, 0, 0.267 },
			{ 9, 0.681, 0.681, 0.267 },
			{ 12, 0, 0.964, 0.267 },
			{ 16, -0.835, 0.482, 0.267 },
			{ 18, -0.964, 0, 0.267 },
			{ 22, -0.482, -0.835, 0.267 },
		}
		for _, p in probe do
			local x, y, z = Backdrop.sunDirection(p[1])
			t.near(x, p[2], 2e-3, `x at {p[1]}`)
			t.near(y, p[3], 2e-3, `y at {p[1]}`)
			t.near(z, p[4], 2e-3, `z at {p[1]}`)
		end
		-- the full moon stands where the sun was 12 hours earlier: rising (+X) as the sun sets
		local mx, my = Backdrop.sunDirection(Backdrop.moonClockTime(18, 0.5))
		t.near(mx, 0.964, 2e-3)
		t.near(my, 0, 2e-3)
		-- the new moon is with the sun; the first quarter is 6 hours behind it
		t.near(Backdrop.moonClockTime(15, 0), 15, 1e-9)
		t.near(Backdrop.moonClockTime(18, 0.25), 12, 1e-9)
	end)

	t.test("tower: on the measured sunset azimuth, beyond the band, on its knoll", function()
		local T = Backdrop.TOWER
		local dx, dz = T.x - Backdrop.CENTRE.x, T.z - Backdrop.CENTRE.z
		local dist = math.sqrt(dx * dx + dz * dz)
		local cosA = (dx * Backdrop.SUNSET.x + dz * Backdrop.SUNSET.z) / dist
		t.truthy(cosA > math.cos(math.rad(0.5)), "on the azimuth")
		t.truthy(dist > 3000 and dist < 4500, `distance {dist}`)
		t.truthy(Backdrop.outside(T.x, T.z) > Backdrop.BAND, "beyond the band")
		t.truthy(Backdrop.meshHeight(T.x, T.z) > 40, "on a knoll")
	end)

	t.test("bake: build/Backdrop.rbxm parts fit Roblox's limits and stream as Persistent", function()
		local out = "build/test_backdrop.rbxm"
		local res = process.exec("lune", { "run", "tools/bake/backdrop.luau", "--out", out, "--report", "build/test_backdrop.json" })
		t.truthy(res.ok, res.stderr)
		local root = roblox.deserializeModel(fs.readFile(out))[1]
		t.eq(root.Name, "Backdrop")
		local parts, bad, models, notPersistent = 0, 0, 0, 0
		local beacon, cards, roadSegs = nil :: any, 0, 0
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				local s = d.Size
				if s.X > 2048 or s.Y > 2048 or s.Z > 2048 or not d.Anchored or d.CanTouch then
					bad += 1
				end
				if d:GetAttribute("Blink") == "obstruction" then
					beacon = d
				end
				if d:FindFirstChildOfClass("SurfaceGui") then
					cards += 1
					t.truthy(d.Transparency >= 1 and not d.CanCollide and not d.CanQuery, "fog card")
				end
				if d.Parent and d.Parent.Name == "Road" then
					roadSegs += 1
				end
			elseif d:IsA("Model") then
				models += 1
				if d.ModelStreamingMode.Name ~= "Persistent" then
					notPersistent += 1
				end
			end
		end
		print(`      {parts} parts, {models} models, {cards} fog cards, {roadSegs} road segments`)
		t.eq(bad, 0, "parts over 2048 st, unanchored or touchable")
		t.eq(notPersistent, 0)
		t.eq(root.ModelStreamingMode.Name, "Persistent")
		t.truthy(parts > 2000 and parts < 4500, `{parts} parts`)
		t.truthy(cards >= 30, "fog cards")
		t.truthy(roadSegs > 50, "road")
		t.truthy(beacon ~= nil, "tower beacon")
		if beacon then
			local T = Backdrop.TOWER
			t.near(beacon.Position.X, T.x, 0.01)
			t.near(beacon.Position.Z, T.z, 0.01)
			t.truthy(beacon.Position.Y > T.height + 30, "beacon at the top")
		end
		fs.removeFile(out)
		fs.removeFile("build/test_backdrop.json")
	end)

	Backdrop.reset()
	Height.configure(nil)
end
