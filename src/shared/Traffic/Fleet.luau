--!strict
-- ReplicatedStorage.Shared.Traffic.Fleet
-- The AI fleet manifest: which vehicle runs on which lane, its behaviour class, spawn point and colour
-- (traffic.md §2.2-§2.7, §5.1-§5.12; the lane records' `users`). BUILD_PLAN §4.4 W1 #9.
-- Interface: ENTRIES { Entry }; count(); byClass(class)
--
-- 25 vehicles: 4 moving sedans, 2 RVs, 2 dump trucks, the ice cream van, the trolley, the patrol car,
-- 2 motorcycles, the legacy ambulance, 3 responder ambulances and 2 incident police cars (dispatched,
-- hidden while idle), and 6 living-event sedans. Spawn positions are v5.4's (HTML units along the lane
-- axis, `at`), converted to studs by the fleet builder. Parked placements (traffic.md §2.2 rows 1 and 3)
-- are static world props, not fleet members (W3 parking data).

export type Entry = {
	id: number,
	name: string,
	kind: string, -- Traffic/Boxes kind
	class: string, -- AICarMotor behaviour: sedan | heavy | van | trolley | patrol | motorcycle | legacy_ambulance | responder | incident | event
	lane: string,
	at: number?, -- spawn along the lane axis, HTML units (straight lanes)
	speedKey: string?, -- key into the lane's speed table
	color: string?,
	wait: number?, -- initial wait (s) for appear-on-a-timer classes
	offset: number?, -- event cycle offset (s)
	car: number?, -- incident car index (0 or 1)
	src: string,
}

local Fleet = {}

-- stylua: ignore
Fleet.ENTRIES = {
	{ id = 1, name = "Sedan NB", kind = "sedan", class = "sedan", lane = "res_main_ns_northbound", at = 115, speedKey = "sedan", color = "#6d7f8f", src = "traffic §2.2 row 2, L1564" },
	{ id = 2, name = "Sedan SB", kind = "sedan", class = "sedan", lane = "res_main_ns_southbound", at = -86, speedKey = "sedan", color = "#9a6b55", src = "traffic §2.2 row 2, L1565" },
	{ id = 3, name = "RV SB", kind = "rv", class = "heavy", lane = "res_main_ns_southbound", at = 180, speedKey = "rv", src = "traffic §2.6, L15904" },
	{ id = 4, name = "Dump truck NB", kind = "dump_truck", class = "heavy", lane = "res_west_ns_x-180_northbound", at = -210, speedKey = "dump", src = "traffic §2.6, L15902" },
	{ id = 5, name = "SCOOP MOBILE", kind = "ice_cream_van", class = "van", lane = "icecream_loop", src = "traffic §2.4, §5.3" },
	{ id = 6, name = "Sedan EB", kind = "sedan", class = "sedan", lane = "blvd_eastbound", at = 287, speedKey = "sedan", color = "#5f7a6a", src = "traffic §2.2 row 4" },
	{ id = 7, name = "Dump truck EB", kind = "dump_truck", class = "heavy", lane = "blvd_eastbound", at = 383, speedKey = "dump", src = "traffic §2.6" },
	{ id = 8, name = "Morgan Rider", kind = "motorcycle", class = "motorcycle", lane = "blvd_eastbound", at = 296, speedKey = "motorcycle_0", wait = 19, src = "traffic §2.7, §5.12" },
	{ id = 9, name = "Sedan WB", kind = "sedan", class = "sedan", lane = "blvd_westbound", at = 620, speedKey = "sedan", color = "#8a7f62", src = "traffic §2.2 row 4" },
	{ id = 10, name = "RV WB", kind = "rv", class = "heavy", lane = "blvd_westbound", at = 579, speedKey = "rv", src = "traffic §2.6" },
	{ id = 11, name = "Alex Rider", kind = "motorcycle", class = "motorcycle", lane = "blvd_westbound", at = 650, speedKey = "motorcycle_1", wait = 83, src = "traffic §2.7, §5.12" },
	{ id = 12, name = "Patrol car", kind = "patrol_car", class = "patrol", lane = "patrol_beat", at = 95, speedKey = "patrol_car", src = "traffic §5.7, L7976" },
	{ id = 13, name = "CITY TROLLEY", kind = "trolley", class = "trolley", lane = "trolley_track", at = 283, speedKey = "trolley", src = "traffic §2.5, §5.4" },
	{ id = 14, name = "Ambulance (arterial)", kind = "ambulance", class = "legacy_ambulance", lane = "north_arterial_legacy_ambulance", wait = 18, src = "traffic §5.8" },
	{ id = 15, name = "Responder 1", kind = "ambulance", class = "responder", lane = "responder_ambulance_trunk", color = "#f4f0ea", src = "traffic §5.9" },
	{ id = 16, name = "Responder 2", kind = "ambulance", class = "responder", lane = "responder_ambulance_trunk", color = "#f4f0ea", src = "traffic §5.9" },
	{ id = 17, name = "Responder 3", kind = "ambulance", class = "responder", lane = "responder_ambulance_trunk", color = "#f4f0ea", src = "traffic §5.9" },
	{ id = 18, name = "Incident car 1", kind = "patrol_car", class = "incident", lane = "incident_police_route", car = 0, color = "#e4e8e5", src = "traffic §5.10" },
	{ id = 19, name = "Incident car 2", kind = "patrol_car", class = "incident", lane = "incident_police_route", car = 1, color = "#e4e8e5", src = "traffic §5.10" },
	{ id = 20, name = "Barbecue car 1", kind = "sedan", class = "event", lane = "event_barbecue_cars#1", offset = 0, color = "#7c8e8b", src = "traffic §5.11" },
	{ id = 21, name = "Barbecue car 2", kind = "sedan", class = "event", lane = "event_barbecue_cars#2", offset = 0, color = "#977c65", src = "traffic §5.11" },
	{ id = 22, name = "Barbecue car 3", kind = "sedan", class = "event", lane = "event_barbecue_cars#3", offset = 0, color = "#627789", src = "traffic §5.11" },
	{ id = 23, name = "Softball car 1", kind = "sedan", class = "event", lane = "event_softball_cars#1", offset = 1200, color = "#7c8e8b", src = "traffic §5.11" },
	{ id = 24, name = "Softball car 2", kind = "sedan", class = "event", lane = "event_softball_cars#2", offset = 1200, color = "#977c65", src = "traffic §5.11" },
	{ id = 25, name = "Softball car 3", kind = "sedan", class = "event", lane = "event_softball_cars#3", offset = 1200, color = "#627789", src = "traffic §5.11" },
} :: { Entry }

function Fleet.count(): number
	return #Fleet.ENTRIES
end

function Fleet.byClass(class: string): { Entry }
	local out = {}
	for _, e in Fleet.ENTRIES do
		if e.class == class then
			table.insert(out, e)
		end
	end
	return out
end

return Fleet
