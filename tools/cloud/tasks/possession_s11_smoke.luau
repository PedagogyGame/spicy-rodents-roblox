--!strict
-- Luau Execution task (spike S11 preparation; named possession_* because it ships with builder
-- A's S2 batch): smoke of the places/s11 drone far-view place on a saved CI version. Scripts do
-- not auto-run here, so it calls S11World directly: the terrain write (town + near bands + ridge,
-- off-road strip and test hill), the off-road markers, the census of what the place carries
-- (243 lots, SLIM on building lots, Skyline massing and lamp heads Persistent) and a pilotless
-- drone (PersistentPerPlayer). Voxel columns are read back at the hill top, the ridge crest and
-- the strip. What only OS-1c can show: what the client renders from 300 st after publishing.
-- Sent by: node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/possession_s11_smoke.luau --version <v> --place ci --timeout 300s
local ServerScriptService = game:GetService("ServerScriptService")

local started = os.clock()
local s11 = ServerScriptService:FindFirstChild("S11")
	or error("ServerScriptService.S11 missing: not a places/s11 build")
local S11World = (require :: any)(s11:FindFirstChild("S11World") :: ModuleScript)
local failures: { string } = {}
local function expect(cond: boolean, what: string)
	if not cond then
		table.insert(failures, what)
	end
end

local census = S11World.census()
expect(census.lots == 243, `lots {census.lots}`)
expect(census.buildings > 0 and census.slimBuildings == census.buildings, "a building lot is not SLIM")
expect(census.skyline == 104, `skyline boxes {census.skyline}`)
expect(census.lampHeads > 0, "no lamp heads")
expect(census.skylineMode == "Persistent" and census.lampMode == "Persistent", "layers not Persistent")

local terrain = S11World.writeTerrain()
local markers = S11World.buildOffroad()
expect(markers == 6, `markers {markers}`)

local function topOf(x: number, z: number): (number?, string?)
	local region = Region3.new(Vector3.new(x - 2, -64, z - 2), Vector3.new(x + 2, 512, z + 2)):ExpandToGrid(4)
	local mats, occs = workspace.Terrain:ReadVoxels(region, 4)
	local size = mats.Size
	for y = size.Y, 1, -1 do
		local m = mats[1][y][1]
		if m ~= Enum.Material.Air and m ~= Enum.Material.Water then
			return region.CFrame.Y - region.Size.Y / 2 + (y - 1) * 4 + occs[1][y][1] * 4, m.Name
		end
	end
	return nil, nil
end
local probes: { [string]: any } = {}
for _, t in S11World.TARGETS do
	local y, m = topOf(t.x, t.z)
	probes[t.name] = { x = t.x, z = t.z, top = y, material = m, expected = S11World.outsideHeight(t.x, t.z) }
end
local hill = probes["Test hill"]
expect(hill.top ~= nil and hill.top > 200, `hill top {hill.top}`)
local strip = probes["Off-road strip"]
expect(strip.material == "Ground", `strip material {strip.material}`)
local station = Vector3.new(700, 0, -100)
local stripDist = Vector3.new(strip.x - station.X, 0, strip.z - station.Z).Magnitude
expect(stripDist >= 1500, `strip only {stripDist} st from the console`)

local drone = S11World.makeDrone(nil)
expect(drone.ModelStreamingMode == Enum.ModelStreamingMode.PersistentPerPlayer, "drone not PersistentPerPlayer")
expect(drone.PrimaryPart ~= nil and not drone.PrimaryPart.Anchored, "drone root anchored")
local canOwn = drone.PrimaryPart and drone.PrimaryPart:CanSetNetworkOwnership()
expect(canOwn == true, "drone root cannot take a network owner")
drone:Destroy()

print(
	`S11 smoke: ok={#failures == 0} terrain={math.floor(terrain.totalSeconds * 100) / 100} s voxels={terrain.totalVoxels} lots={census.lots} slim={census.slim} skyline={census.skyline} lamps={census.lampHeads}`
)
for _, f in failures do
	print("  FAIL " .. f)
end
return {
	suite = "S11Smoke",
	ok = #failures == 0,
	failures = failures,
	census = census,
	terrain = terrain,
	probes = probes,
	stripDistanceFromConsole = stripDist,
	placeVersion = game.PlaceVersion,
	elapsedSeconds = os.clock() - started,
}
