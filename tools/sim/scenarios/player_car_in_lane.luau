--!strict
-- Scenario: a player driving among the fleet (addendum A1: police players drive patrol cars, anyone may
-- take a cart, pickup or SUV). One player's car pulls into the main street's northbound lane and stands
-- there for 20 s of every 60 s (stopped to get out, to watch, to block the road), then drives off; another
-- crawls along the boulevard's eastbound lane at 8 st/s, slower than every AI vehicle on it, and loops.
-- The fleet must queue behind them and pull away once they are gone, never drive through them.
local Replay = require("../lib/Replay")
local VehicleKinds = require("@shared/Vehicles/VehicleKinds")

local PICKUP = VehicleKinds.kind("pickup").size -- width, height, length
local CAR = VehicleKinds.kind("car").size

local scenario: Replay.Scenario = {
	name = "player_car_in_lane",
	about = "a player's pickup standing in the main street's northbound lane 20 s a minute, a patrol car crawling along the boulevard",
	seconds = 300,
	ci = 60,
	world = function(sim: Replay.Sim): any
		local cars = {}
		local t = sim.wall
		-- the pickup: in the lane at z = 200 (facing north) for 20 s from t = 10 + 60 k
		local u = (t - 10) % 60
		if t >= 10 and u < 20 then
			table.insert(cars, {
				id = "pickup",
				x = -13.5,
				z = 200,
				yaw = 0,
				width = PICKUP[1],
				length = PICKUP[3],
				speed = 0,
			})
		end
		-- the crawling patrol car: east along z = 14 from x = 720 to 1620 at 8 st/s, again and again
		if t >= 5 then
			local x = 720 + ((t - 5) * 8) % 900
			table.insert(cars, {
				id = "patrol",
				x = x,
				z = 14,
				yaw = math.pi / 2,
				width = CAR[1],
				length = CAR[3],
				speed = 8,
			})
		end
		return { people = {}, squirrels = {}, cars = cars }
	end,
	expect = { none = { "through_player_car" } },
}

return scenario
