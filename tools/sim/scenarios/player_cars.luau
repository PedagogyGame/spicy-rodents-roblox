--!strict
-- Scenario: the game's 25 vehicles with the players' vehicles where the server parks them at boot
-- (Server/Actors/DeviceService.defaultPlacements: two patrol cars at the police station, carts and bikes
-- by the main street, a pickup and an SUV on the main street), and no player driving one. The parked
-- vehicles are anchored physical models; the fleet only knows what `world` hands it. The meetings
-- detector measures every fleet vehicle that drives into one of them.
local Data = require("@shared/Data")
local DeviceService = require("@server/Actors/DeviceService")
local Height = require("@shared/World/Height")
local Replay = require("../lib/Replay")
local VehicleKinds = require("@shared/Vehicles/VehicleKinds")

local function parked(): { any }
	Height.configure(Data.default():module("TerrainExtensions"))
	local out = {}
	for i, p in DeviceService.defaultPlacements(Data.default()) do
		if p.kind == "drone" or p.kind == "jetski" then
			continue
		end
		local size = VehicleKinds.kind(p.kind).size -- width, height, length (studs)
		-- HTML yaw: atan2(dx, dz) of the heading, the same convention as the fleet's
		table.insert(out, {
			id = `{p.kind}_{i}`,
			kind = p.kind,
			x = p.x,
			z = p.z,
			yaw = p.yaw,
			width = size[1],
			length = size[3],
			speed = 0,
		})
	end
	return out
end

local CARS = parked()

local scenario: Replay.Scenario = {
	name = "player_cars",
	about = "the 25 vehicles with the players' carts, bikes, pickup and SUV parked where the server spawns them",
	seconds = 300,
	ci = 40,
	world = function(_sim: Replay.Sim): any
		return { people = {}, squirrels = {}, cars = CARS }
	end,
	-- until the pickup and the SUV moved off the main street's lanes (and the fleet learned to brake for
	-- player vehicles), the fleet drove through them every lap: 8 times in 120 s
	expect = { none = { "through_player_car" } },
}

return scenario
