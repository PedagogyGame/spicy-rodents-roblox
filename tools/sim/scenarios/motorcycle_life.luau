--!strict
-- Scenario: one motorcycle's whole life, twice (traffic.md §5.12), with something in its way each time.
-- Morgan Rider appears on the eastbound boulevard 2 s in, behind Sedan EB (slowed to 12 st/s so the
-- rider catches it); a person stands in the eastbound lane from 15 s to 19 s, in the rider's path; the
-- rider rides to the end of its lane and hides. Its wait is then cut to 3 s so the second appearance
-- (the same spawn, the same sedan further on) is seen too.
-- Measured on the base tree (all fixed since: AICarMotor's rider follows the vehicle ahead, eases its
-- speed, and stands parked at the kerb between rides instead of popping in and out):
--   * it pops into view at full speed mid-boulevard (x = 740 st, about 1,090 st inside the town) and pops
--     out at x = 1,641 st, also mid-town (AICarMotor stepClass.motorcycle: appear at spawnS with
--     `v.speed = v.cruise`; the despawn at `lane.length - 3 u` just hides it)
--   * it rides straight through the sedan ahead (it yields to no vehicle; §5.12 port), and the sedan,
--     which does see the rider once it is ahead, brakes hard behind it
--   * for the person it goes from full speed to 0 in one tick and back to full speed in one tick
--     (`v.speed = 0` / `v.speed = v.cruise`, no ramp)
local Fleet = require("@shared/Traffic/Fleet")
local Height = require("@shared/World/Height")
local LaneMath = require("@shared/Traffic/LaneMath")
local Replay = require("../lib/Replay")

local RIDER, SEDAN = 8, 6
local PERSON = { x = 1150, z = 14, from = 15, to = 19 }

local entries = {}
for _, e in Fleet.ENTRIES do
	if e.id == RIDER or e.id == SEDAN then
		table.insert(entries, e)
	end
end

local scenario: Replay.Scenario = {
	name = "motorcycle_life",
	about = "a motorcycle appears behind a slow sedan, rides through it, stops dead for a person, hides, and does it again",
	seconds = 90,
	ci = 90,
	entries = entries,
	setup = function(sim: Replay.Sim)
		local rider = sim.traffic.byId[RIDER]
		rider.timer = 2
		local sedan = sim.traffic.byId[SEDAN]
		sedan.s = LaneMath.arcOf(sedan.lane, 800, 14, 1)
		sedan.cruise = 12
		sedan.speed = 12
	end,
	frame = function(sim: Replay.Sim)
		local rider = sim.traffic.byId[RIDER]
		if rider.n == 1 and rider.phase == "idle" and not sim.state.second then
			sim.state.second = true
			rider.timer = 3
		end
	end,
	world = function(sim: Replay.Sim): any
		local people = {}
		if sim.wall >= PERSON.from and sim.wall < PERSON.to then
			table.insert(people, {
				x = PERSON.x,
				y = Height.at(PERSON.x, PERSON.z),
				z = PERSON.z,
				kind = "human",
			})
		end
		return { people = people, squirrels = {} }
	end,
	expect = {
		-- (not teleport_unflagged: Sedan EB wraps at 74.5 s and that wrap can lose its flag, sedan_wrap's
		-- business, not the rider's)
		none = {
			"sim_jump_unflagged",
			"reverse_travel",
			"sideways_slide",
			"yaw_jump",
			"sink",
			"float",
			"box_overlap",
			"accel_spike",
			"appear",
			"disappear",
		},
	},
}

return scenario
