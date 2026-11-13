--!strict
-- ReplicatedStorage.Shared.Rides.RideSpec
-- The `Ride` contract (BUILD_PLAN §1.4, §3.16; brief v2 §15: rides have no controls and no score; the
-- jet ski is the steerable exception and lives in Vehicles): a def plus a pure path sampler and an exit
-- point. The sky lift's def takes its points from the compiled layout (data/expansion.json rides.sky_lift,
-- the cable's centre line bullwheel to bullwheel); Rides/SkyLift owns its loop, cabins and timetable. Pure.
-- Interface: rides() -> { [id]: Def }; def(ride) -> Def?; check(def) -> (ok, err?); pathAt(def, t) -> (x, y, z);
--            exitPoint(def) -> (x, y, z); duration(def) -> seconds

local Data = require("../Data")

export type Def = {
	ride: string,
	kind: "cable" | "towed_spline" | "float_volume" | "tethered",
	points: { { number } }?, -- polyline control points in studs
	speed: number?, -- studs per second along the path
	controls: boolean, -- always false for a ride
	score: boolean, -- always false for a ride
	camera: string?,
}

local RideSpec = {}

local rides: { [string]: Def }? = nil

function RideSpec.rides(): { [string]: Def }
	if rides == nil then
		local built: { [string]: Def } = {}
		local exp = Data.default():module("Expansion") :: any
		for _, r in exp.rides or {} do
			if r.id == "sky_lift" then
				local pts: { { number } } = {}
				for _, p in r.points do
					table.insert(pts, { p[1], p[2], p[3] })
				end
				local def: Def = {
					ride = r.id,
					kind = "cable",
					points = pts,
					speed = r.speed,
					controls = false,
					score = false,
					camera = r.camera,
				}
				built.sky_lift = table.freeze(def)
			end
		end
		rides = built
	end
	return rides :: { [string]: Def }
end

function RideSpec.def(ride: string): Def?
	return RideSpec.rides()[ride]
end

function RideSpec.check(d: Def): (boolean, string?)
	if d.controls or d.score then
		return false, "a ride has no controls and no score"
	end
	if d.kind == "cable" or d.kind == "towed_spline" then
		if not d.points or #d.points < 2 then
			return false, "path needs two points"
		end
		if not d.speed or d.speed <= 0 then
			return false, "speed"
		end
	end
	return true
end

local function length(d: Def): number
	local pts = d.points :: { { number } }
	local total = 0
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		total += math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
	end
	return total
end

function RideSpec.duration(d: Def): number
	return length(d) / (d.speed :: number)
end

-- Position after t seconds on the ride (clamped to the ends).
function RideSpec.pathAt(d: Def, t: number): (number, number, number)
	local pts = d.points :: { { number } }
	local remaining = math.max(0, t) * (d.speed :: number)
	for i = 2, #pts do
		local a, b = pts[i - 1], pts[i]
		local seg = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
		if remaining <= seg and seg > 0 then
			local f = remaining / seg
			return a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f
		end
		remaining -= seg
	end
	local last = pts[#pts]
	return last[1], last[2], last[3]
end

function RideSpec.exitPoint(d: Def): (number, number, number)
	local last = (d.points :: { { number } })[#(d.points :: { { number } })]
	return last[1], last[2], last[3]
end

return RideSpec
