--!strict
-- ReplicatedStorage.Shared.Rides.RideSpec
-- The `Ride` contract (BUILD_PLAN §1.4, §3.16; brief v2 §15: rides have no controls and no score; the
-- jet ski is the steerable exception and lives in Vehicles): a def plus a pure path sampler and an exit
-- point. W1 ships the contract and ONE stub ride (the sky lift as a straight cable between two points;
-- W3c/W4b take its ends from lot data). Pure.
-- Interface: RIDES; def(ride) -> Def?; check(def) -> (ok, err?); pathAt(def, t) -> (x, y, z); exitPoint(def) -> (x, y, z);
--            duration(def) -> seconds

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

RideSpec.RIDES = {
	-- stub ends until lot data: base near the park, top on the hill (studs)
	sky_lift = {
		ride = "sky_lift",
		kind = "cable",
		points = { { 0, 10, 0 }, { 0, 160, 600 } },
		speed = 6 * 2.5,
		controls = false,
		score = false,
		camera = "firstPerson",
	},
} :: { [string]: Def }

function RideSpec.def(ride: string): Def?
	return RideSpec.RIDES[ride]
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
