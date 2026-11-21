--!strict
-- ReplicatedStorage.Shared.Wildlife.RoadCrossing
-- How the computer's squirrels cross a road (owner D21, 2026-11-21: "make sure those regular squirrels can be run over
-- by cars, if they are not careful"; D15 #6: cars brake for people only, squirrels must dodge). The rule, pure:
--   * WHERE (sites): a tree whose foot stands within C.reach of a road's asphalt, with a clear run to the kerb,
--     straight across and on to the foot of a tree on the other side. The squirrel comes down its trunk, runs to the
--     kerb, stops and looks, dashes kerb to kerb, and runs on to the other tree (Server/Actors/Brains/Squirrel walks it).
--   * LOOKING (look): at the kerb it looks at every car that is moving (the fleet's places and velocities as the
--     server has them): a car whose body will reach the crossing's line before the squirrel is across with C.margin to
--     spare, or that stands on or right by the line, is in the way: it waits for a gap. That is a careful squirrel, and
--     they mostly are.
--   * NOT CAREFUL (dares): a squirrel that has misjudged a fast car (C.fast) races it: it goes at the last moment,
--     when the car is no more than C.late further from the line than the squirrel's own dash to the car's path takes,
--     and so reaches the car's path about when the car does (a little slower than a careful dash, by C.racePace:
--     some scrape through under the car's nose, most do not). Whether it gets across is the fatal sweep's to say
--     (Server/Traffic/SweptCollision), as for a player's squirrel: the car does not brake. A squirrel misjudges a car
--     in one of two ways, each decided once a car: at the kerb, a fast car that keeps it waiting (chance C.misjudge);
--     or up its tree, a fast car coming that it could just beat to the kerb (races: chance C.race, the car's arrival
--     between C.raceLead after its own at the kerb), which brings it down for that car. The town's traffic is thin, so
--     these are few: with a player by every squirrel in town, about one crossing in ten is a race.
-- Interface: C; sites(ends, strips, clear) -> { [routeId]: Site }; need(site) -> seconds; fast(car) -> boolean;
--   arrival(car, site) -> (t, at)? (seconds until the car's body reaches the line, and where along it, studs from the
--   near kerb, its path crosses); look(cars, site) -> (clear, car?, t?, at?) (the soonest car in the way);
--   dares(t, at) -> boolean (the misjudged moment to go); races(t, toKerb) -> boolean (a car worth coming down for)
-- Pure. Studs; a car is { id, x, z, vx, vz, width, length } (velocity in studs/s). No side effects on require.

local Species = require("../Actors/Species")

-- A ground-level end of a route (a tree's foot): the route, the arc length of that end along it, and where it is.
export type End = { route: number, s: number, x: number, z: number }

export type Strip = { kind: string, axis: string, coord: number, min: number, max: number, half: number }

export type Site = {
	route: number, -- the tree it sets out from
	s: number, -- its foot on that route (arc length)
	ax: number, -- the foot
	az: number,
	kx: number, -- the kerb on its side: where it stops and looks
	kz: number,
	fx: number, -- the far kerb, straight across
	fz: number,
	to: number, -- the tree on the other side
	toS: number, -- its foot
	bx: number,
	bz: number,
	width: number, -- kerb to kerb (studs)
	length: number, -- the whole run, foot to foot
}

export type Car = { id: any, x: number, z: number, vx: number, vz: number, width: number, length: number }

local RoadCrossing = {}

local speeds = Species.def("squirrel").speeds

RoadCrossing.C = table.freeze({
	reach = 70, -- studs from a tree's foot to the kerb, at most
	kerb = 1.5, -- studs outside the asphalt's edge it stops and looks
	ends = 5, -- studs from a road's ends no crossing is made within
	pace = speeds.sprint, -- studs/s kerb to kerb (33)
	approach = speeds.walk, -- studs/s to the kerb and from the far one (18)
	margin = 0.8, -- seconds to spare a careful squirrel wants once it is across
	pad = 1.2, -- studs either side of a car's body that still count as its path
	still = 1, -- studs/s: slower than this a car is standing
	near = 10, -- studs: a standing car this near the line is in the way (it may pull off)
	lookSecs = { 0.8, 3 }, -- it looks both ways this long before it goes
	patience = 9, -- seconds at the kerb with no gap: back up its tree
	fast = 15, -- studs/s: a fast car (the one a squirrel misjudges)
	misjudge = 0.5, -- the chance it takes a fast car that keeps it waiting for a slower one
	late = 0.25, -- seconds: a misjudging squirrel goes when the car is this much further off than its own dash, or less
	racePace = { 0.85, 1 }, -- ... and runs at this share of the pace (some are quicker than others: some make it)
	race = 0.2, -- the chance a squirrel up its tree comes down to race a fast car that is coming
	raceLead = { 0.6, 4 }, -- ... one that will reach the line this long after the squirrel reaches the kerb
	raceRest = 20, -- seconds before the same squirrel makes its mind up about the same car again
	every = { 25, 80 }, -- seconds between one squirrel's thoughts of crossing
	atOnce = 3, -- squirrels on their way across at once, town-wide
})

local C = RoadCrossing.C

-- sites(ends, strips, clear): for each route with a foot by a road, its best crossing (the shortest run). `clear(x0, z0,
-- x1, z1)`: a straight run passes no wall or fence (World/WalkWay.clear). A foot standing on a strip (a trunk in the
-- pavement) is no start.
function RoadCrossing.sites(
	ends: { End },
	strips: { Strip },
	clear: (x0: number, z0: number, x1: number, z1: number) -> boolean
): { [number]: Site }
	local out: { [number]: Site } = {}
	for _, a in ends do
		for _, s in strips do
			if s.kind ~= "asphalt" then
				continue
			end
			local alongZ = s.axis == "z"
			local along = if alongZ then a.z else a.x
			local off = (if alongZ then a.x else a.z) - s.coord
			local gap = math.abs(off) - s.half
			if gap < C.kerb + 0.5 or gap > C.reach or along < s.min + C.ends or along > s.max - C.ends then
				continue
			end
			local side = if off > 0 then 1 else -1
			local kc, fc = s.coord + side * (s.half + C.kerb), s.coord - side * (s.half + C.kerb)
			local kx, kz, fx, fz
			if alongZ then
				kx, kz, fx, fz = kc, along, fc, along
			else
				kx, kz, fx, fz = along, kc, along, fc
			end
			if not clear(a.x, a.z, kx, kz) or not clear(kx, kz, fx, fz) then
				continue
			end
			local best: End?, bestD = nil, C.reach
			for _, b in ends do
				if b.route ~= a.route then
					local d = math.sqrt((b.x - fx) ^ 2 + (b.z - fz) ^ 2)
					local across = (if alongZ then b.x else b.z) - s.coord
					if d < bestD and across * side < -(s.half + C.kerb + 0.5) and clear(fx, fz, b.x, b.z) then
						best, bestD = b, d
					end
				end
			end
			if best then
				local width = 2 * (s.half + C.kerb)
				local length = math.sqrt((a.x - kx) ^ 2 + (a.z - kz) ^ 2) + width + bestD
				local had = out[a.route]
				if had == nil or length < had.length then
					out[a.route] = {
						route = a.route,
						s = a.s,
						ax = a.x,
						az = a.z,
						kx = kx,
						kz = kz,
						fx = fx,
						fz = fz,
						to = best.route,
						toS = best.s,
						bx = best.x,
						bz = best.z,
						width = width,
						length = length,
					}
				end
			end
		end
	end
	return out
end

-- need(site): how long the line must stay clear for a careful squirrel: the dash and the margin
function RoadCrossing.need(site: Site): number
	return site.width / C.pace + C.margin
end

-- arrival(car, site): seconds until the car's body (C.pad wider either side) reaches the crossing's line, and where
-- along the line (studs from the near kerb) its path crosses; nil when it never does on its present heading (going
-- away, already past, or passing clear of both kerbs). 0: on the line now. A standing car is in the way (0) only
-- within C.near of the line.
function RoadCrossing.arrival(car: Car, site: Site): (number?, number?)
	local kx, kz = site.kx - car.x, site.kz - car.z
	local fx, fz = site.fx - car.x, site.fz - car.z
	local speed = math.sqrt(car.vx * car.vx + car.vz * car.vz)
	if speed < C.still then
		-- how far the car's middle is from the line (a segment)
		local dx, dz = fx - kx, fz - kz
		local l2 = dx * dx + dz * dz
		local u = if l2 > 1e-9 then math.clamp(-(kx * dx + kz * dz) / l2, 0, 1) else 0
		local px, pz = kx + dx * u, kz + dz * u
		if math.sqrt(px * px + pz * pz) <= car.length / 2 + C.near then
			return 0, u * site.width
		end
		return nil, nil
	end
	local ux, uz = car.vx / speed, car.vz / speed
	-- the two kerbs in the car's frame: ahead of it (a) and to its right (r)
	local ka, kr = kx * ux + kz * uz, kx * uz - kz * ux
	local fa, fr = fx * ux + fz * uz, fx * uz - fz * ux
	local half = car.width / 2 + C.pad
	-- the part of the line inside the car's path: q in [q0, q1] along it (kerb 0, far kerb 1)
	local q0, q1 = 0, 1
	local dr = fr - kr
	if math.abs(dr) < 1e-9 then
		if math.abs(kr) > half then
			return nil, nil
		end
	else
		local qa, qb = (-half - kr) / dr, (half - kr) / dr
		q0, q1 = math.max(0, math.min(qa, qb)), math.min(1, math.max(qa, qb))
		if q0 > q1 then
			return nil, nil
		end
	end
	local a0, a1 = ka + (fa - ka) * q0, ka + (fa - ka) * q1
	local nearest, furthest = math.min(a0, a1), math.max(a0, a1)
	if furthest < -car.length / 2 then
		return nil, nil -- (behind its tail: it has passed)
	end
	local qc = if math.abs(dr) < 1e-9 then (q0 + q1) / 2 else math.clamp(-kr / dr, 0, 1)
	return math.max(0, nearest - car.length / 2) / speed, qc * site.width
end

-- look(cars, site): is the line clear for a careful squirrel? When not, the car that will be there soonest, in how
-- many seconds, and where along the line.
function RoadCrossing.look(cars: { Car }, site: Site): (boolean, Car?, number?, number?)
	local need = RoadCrossing.need(site)
	local worst: Car?, worstT: number?, worstAt: number? = nil, nil, nil
	for _, car in cars do
		local t, at = RoadCrossing.arrival(car, site)
		if t ~= nil and t < need and (worstT == nil or t < worstT) then
			worst, worstT, worstAt = car, t, at
		end
	end
	return worst == nil, worst, worstT, worstAt
end

-- fast(car): the kind of car a squirrel misjudges
function RoadCrossing.fast(car: Car): boolean
	return car.vx * car.vx + car.vz * car.vz >= C.fast * C.fast
end

-- dares(t, at): a misjudging squirrel's moment: the car is `t` seconds from the line and its path `at` studs along
-- it; it goes once the car is no more than C.late further off than its own dash to that path takes
function RoadCrossing.dares(t: number, at: number): boolean
	return t > 0 and t <= at / C.pace + C.late
end

-- races(t, toKerb): is a car `t` seconds from the line one a squirrel `toKerb` seconds from the kerb could come down
-- for: there before it, but not by long
function RoadCrossing.races(t: number, toKerb: number): boolean
	return t >= toKerb + C.raceLead[1] and t <= toKerb + C.raceLead[2]
end

return RoadCrossing
