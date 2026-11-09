--!strict
-- ServerStorage.EngineTests.Backdrop (CI place only; run by tools/cloud/tasks/backdrop_smoke.luau)
-- The backdrop and the day cycle in the real engine (BUILD_PLAN W6 #1; brief v2 §3 Backdrop, §15):
--   * WorldGen/BackdropTerrain after WorldTerrain: timing, and a voxel read-back (sea water over a sandy floor
--     beyond the beach, grass in the band beyond the clamp, the beach sand at the waterline);
--   * Workspace.Backdrop (build/Backdrop.rbxm): Persistent models, parts within 2048 st, anchored, far scenery
--     out of collision and queries, the tower Beacon on the sunset azimuth, fog cards with a SurfaceGui gradient;
--   * Boot/DayClock publishes the clock; Shared/Time/Clock.fromEngine reads the start hour back;
--   * Client/World/Sky.step over a whole day against the real Lighting API (every property it writes exists
--     and takes its value), and the measured sun model: the sun is on the horizon at the sunrise and sunset keys.
-- Luau Execution runs no physics and no RenderStepped, so Sky.start (the moon, beacons, cars) is not exercised.
-- Interface: run() -> Result (JSON-friendly)

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")

local Backdrop = {}

local function probe(x: number, z: number, y0: number, y1: number): { string }
	local gx, gz = math.floor(x / 4) * 4, math.floor(z / 4) * 4
	local mats, occs =
		workspace.Terrain:ReadVoxels(Region3.new(Vector3.new(gx, y0, gz), Vector3.new(gx + 4, y1, gz + 4)), 4)
	local col: { string } = {}
	for j = 1, #mats[1] do
		table.insert(col, `{mats[1][j][1].Name}:{string.format("%.2f", occs[1][j][1])}`)
	end
	return col
end

local function has(col: { string }, material: string): boolean
	for _, c in col do
		if string.sub(c, 1, #material + 1) == material .. ":" then
			return true
		end
	end
	return false
end

function Backdrop.run(): { [string]: any }
	local failures: { string } = {}
	local numbers: { [string]: any } = {}
	local function check(cond: boolean, msg: string)
		if not cond then
			table.insert(failures, msg)
		end
	end
	local server = ServerScriptService:WaitForChild("Server")
	local worldGen = server:WaitForChild("WorldGen")
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local World = shared:WaitForChild("World")
	local BackdropShared = (require :: any)(World:WaitForChild("Backdrop"))
	local Height = (require :: any)(World:WaitForChild("Height"))

	-- terrain -----------------------------------------------------------------------------------------
	local t0 = os.clock()
	local WorldTerrain = (require :: any)(worldGen:WaitForChild("WorldTerrain"))
	WorldTerrain.write(workspace.Terrain)
	numbers.townTerrainSeconds = os.clock() - t0
	local t1 = os.clock()
	local BackdropTerrain = (require :: any)(worldGen:WaitForChild("BackdropTerrain"))
	local st = BackdropTerrain.write(workspace.Terrain)
	numbers.backdropTerrainSeconds = os.clock() - t1
	numbers.backdropTerrain = st
	check(st.rects == 4 and st.voxels > 1e6, `backdrop terrain wrote {st.voxels} voxels in {st.rects} rects`)
	check(numbers.backdropTerrainSeconds < 8, `backdrop terrain took {numbers.backdropTerrainSeconds} s`)
	local sea = probe(-60, 2000, -16, 4)
	local shore = probe(-60, BackdropShared.shoreZ(-60) - 30, -16, 8)
	local c = Height.worldClamp()
	local band = probe(900, c.minZ - 200, -16, 64)
	numbers.probe = { sea = table.concat(sea, " "), shore = table.concat(shore, " "), band = table.concat(band, " ") }
	check(has(sea, "Water") and has(sea, "Sand"), "no sea water over a sandy floor at (-60, 2000)")
	check(has(shore, "Sand"), "no beach sand at the waterline")
	check(has(band, "Grass"), "no grass in the band beyond the clamp")
	check(math.abs(workspace.Terrain.WaterTransparency - 0.3) < 1e-3, "water look not set")

	-- the baked model ------------------------------------------------------------------------------------
	local root = workspace:FindFirstChild("Backdrop")
	check(root ~= nil, "Workspace.Backdrop missing (lune run tools/bake/backdrop.luau before rojo build)")
	if root then
		local parts, models, badModels, oversize, loose, collidingFar, cards = 0, 0, 0, 0, 0, 0, 0
		local beacon: BasePart? = nil
		check((root :: Model).ModelStreamingMode == Enum.ModelStreamingMode.Persistent, "root not Persistent")
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				if d.Size.X > 2048 or d.Size.Y > 2048 or d.Size.Z > 2048 then
					oversize += 1
				end
				if not d.Anchored or d.CanTouch then
					loose += 1
				end
				local group = d.Parent and d.Parent.Parent
				if group and (group.Name == "Ranges" or group.Name == "Backdrop") and d.CanCollide then
					collidingFar += 1
				end
				if d:GetAttribute("Blink") == "obstruction" then
					beacon = d
				end
				if d:FindFirstChildOfClass("SurfaceGui") then
					cards += 1
				end
			elseif d:IsA("Model") then
				models += 1
				if d.ModelStreamingMode ~= Enum.ModelStreamingMode.Persistent then
					badModels += 1
				end
			end
		end
		numbers.backdropParts = parts
		numbers.backdropModels = models
		numbers.fogCards = cards
		check(parts > 2000, `{parts} backdrop parts`)
		check(badModels == 0, `{badModels} backdrop models not Persistent`)
		check(oversize == 0, `{oversize} parts over 2048 st`)
		check(loose == 0, `{loose} parts unanchored or touchable`)
		check(collidingFar == 0, `{collidingFar} far scenery parts collide`)
		check(cards >= 30, `{cards} fog cards`)
		check(beacon ~= nil, "no tower beacon")
		if beacon then
			local T = BackdropShared.TOWER
			local p = beacon.Position
			numbers.beacon = { p.X, p.Y, p.Z }
			check(math.abs(p.X - T.x) < 0.5 and math.abs(p.Z - T.z) < 0.5, "beacon off the tower")
		end
	end

	-- the clock ------------------------------------------------------------------------------------------
	local DayClock = (require :: any)(server:WaitForChild("Boot"):WaitForChild("DayClock"))
	for _, a in { "ClockEpoch", "ClockBase", "ClockRate", "ClockRealSecondsPerDay" } do
		ReplicatedStorage:SetAttribute(a, nil)
	end
	DayClock.publish(ReplicatedStorage)
	local Clock = (require :: any)(shared:WaitForChild("Time"):WaitForChild("Clock"))
	local g = Clock.fromEngine(ReplicatedStorage:GetAttribute("ClockRealSecondsPerDay")):game()
	numbers.clockAtBoot = { day = g.day, hour = g.hour, segment = g.segment, phase = g.phase }
	check(g.day == DayClock.START_DAY, `clock day {g.day}`)
	check(math.abs(g.hour - DayClock.START_HOUR) < 0.2, `clock hour {g.hour}`)

	-- the client sky against the real Lighting ------------------------------------------------------------
	local client = StarterPlayer:WaitForChild("StarterPlayerScripts"):WaitForChild("Client")
	local Sky = (require :: any)(client:WaitForChild("World"):WaitForChild("Sky"))
	local Lighting = game:GetService("Lighting")
	local errors = 0
	local firstError: string? = nil
	for i = 0, 47 do
		local ok, err = pcall(Sky.step, { day = 9, dayFrac = i / 48, hour = i / 2 }, true)
		if not ok then
			errors += 1
			firstError = firstError or tostring(err)
		end
	end
	check(errors == 0, `Sky.step failed {errors} times: {firstError}`)
	local function sunY(hour: number): number
		Sky.step({ day = 9, dayFrac = 0, hour = hour }, true)
		return Lighting:GetSunDirection().Y
	end
	numbers.sunY = { sunrise = sunY(5.83), sunset = sunY(19.08), golden = sunY(16.5), night = sunY(1) }
	check(math.abs(numbers.sunY.sunrise) < 0.02, `sun at the sunrise key {numbers.sunY.sunrise}`)
	check(math.abs(numbers.sunY.sunset) < 0.02, `sun at the sunset key {numbers.sunY.sunset}`)
	check(numbers.sunY.night < -0.3, "night sun above the horizon")
	Sky.step({ day = 9, dayFrac = 0, hour = 1 }, true)
	local sky = Lighting:FindFirstChildOfClass("Sky")
	numbers.night = {
		brightness = Lighting.Brightness,
		stars = sky and sky.StarCount or -1,
		lamps = Lighting:GetAttribute("StreetLamps"),
		atmosphere = (Lighting:FindFirstChildOfClass("Atmosphere") :: Atmosphere).Color:ToHex(),
	}
	check(sky ~= nil and sky.StarCount >= 3000, "few stars at night")
	check(Lighting.Brightness < 0.8, "night too bright")
	-- the engine's own sun direction agrees with the shared model the custom moon uses
	Lighting.ClockTime = 16
	local d = Lighting:GetSunDirection()
	local mx, my, mz = BackdropShared.sunDirection(16, math.asin(d.Z))
	check((Vector3.new(mx, my, mz) - d).Magnitude < 0.01, "sun model differs from GetSunDirection")
	return { ok = #failures == 0, failures = failures, numbers = numbers }
end

return Backdrop
