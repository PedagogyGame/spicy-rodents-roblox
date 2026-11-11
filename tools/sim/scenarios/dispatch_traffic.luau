--!strict
-- Scenario: ambulances and police answering calls through the town's traffic. The dispatch scenario sends
-- the responders and incident cars out alone; here the whole fleet runs, a responder is sent every 60 s
-- (to houses east and west of the main street, so its last legs cross the main street's lanes and the
-- west street) and the incident pair every 90 s to a scene on the main street. A person stands on the
-- responder trunk for a while, as a crowd would round a casualty. Overlaps with fleet traffic, people
-- driven through, player cars driven through.
local Fleet = require("@shared/Traffic/Fleet")
local Height = require("@shared/World/Height")
local Replay = require("../lib/Replay")

-- responder destinations and incident scenes, HTML units {x, z}
local HOUSES = { { -40, 60 }, { 60, -120 }, { -210, 150 } }
local SCENES = { { 100, -80 }, { 0, 40 } }

local scenario: Replay.Scenario = {
	name = "dispatch_traffic",
	about = "the whole fleet with a responder sent every 60 s and the incident pair every 90 s",
	seconds = 600,
	ci = 60,
	entries = Fleet.ENTRIES,
	sceneSecs = 10,
	frame = function(sim: Replay.Sim)
		local st = sim.state
		st.nextResponder = st.nextResponder or 2
		st.nextIncident = st.nextIncident or 4
		st.r = st.r or 0
		st.i = st.i or 0
		if sim.wall >= st.nextResponder then
			st.nextResponder += 60
			st.r += 1
			local h = HOUSES[(st.r - 1) % #HOUSES + 1]
			sim.traffic:dispatchResponder({ sim.st(h[1]), sim.st(h[2]) })
		end
		if sim.wall >= st.nextIncident then
			st.nextIncident += 90
			st.i += 1
			local s = SCENES[(st.i - 1) % #SCENES + 1]
			sim.traffic:dispatchIncident({ sim.st(s[1]), sim.st(s[2]) })
		end
	end,
	world = function(sim: Replay.Sim): any
		local people = {}
		-- a bystander on the responder trunk's east-west leg, 20 s of every 60 s
		if (sim.wall - 10) % 60 < 20 and sim.wall >= 10 then
			local x, z = -650, 745
			table.insert(people, { id = "bystander", x = x, y = Height.at(x, z), z = z, kind = "human" })
		end
		return { people = people, squirrels = {} }
	end,
}

return scenario
