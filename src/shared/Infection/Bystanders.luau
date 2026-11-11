--!strict
-- ReplicatedStorage.Shared.Infection.Bystanders
-- The crowd at a scene (owner 2026-11-10: "a crowd gather sometimes"; humans_actors §7.4
-- gatherAtCrime): which nearby townspeople come and where each one stands. v5.4 kept a pool of seven
-- hidden extras and popped them in around the victim; here real townspeople who are close by walk
-- over, so a crowd only forms where people actually are.
--   select: with chance crowdChance a crowd forms, of 2 to 4 people (the dice): returns that size
--     and EVERY eligible person within the radius, nearest first. The size is how many are wanted,
--     not how many are asked: someone who cannot walk over is replaced by the next nearest.
--   spots: the v5.4 ring, angle (i + 0.33) 2 pi / n at `ring` studs from the victim; a spot the
--     caller's `isFree` rejects (inside a building, on the road where the ambulance stops) is tried
--     again a little round the ring and nearer or further; spots keep MIN_APART from each other.
--     A victim on a pavement has the road on one side: the ring places that fall on it are made up
--     from anywhere else round the victim that is free (a sweep of the whole circle), so a crowd of
--     n finds n places whenever there are n to find.
--   assign: people in order (nearest first) each take the nearest free spot they can walk to
--     (`wayTo` returns the walk, or nil: kinematic people do not collide, so a blocked line would be
--     a walk through a house) until `want` are placed. Fewer than `min`: nobody comes (one onlooker
--     is not a crowd).
-- Interface: select(scene, candidates, rand, params) -> ({ id }, want); spots(scene, n, isFree,
--   ring) -> { {x, z} }; assign(people, spots, wayTo, want?, min?) -> { { id, x, z, path } };
--   MIN_APART; SPOT_TRIES; SAY_FIRST, SAY_EACH
-- Pure; studs. No side effects on require.

export type Candidate = { id: any, x: number, z: number, eligible: boolean }
export type Params = { chance: number, min: number, max: number, radius: number }
export type Place = { id: any, x: number, z: number, path: { { number } }? }

local Bystanders = {}

Bystanders.MIN_APART = 4 -- studs between two bystanders
Bystanders.SPOT_TRIES = 2 -- a person tries their nearest free spots, this many at most
-- humans_actors §7.4: bystander i speaks once, 2.2 + 0.85 i seconds after being called over
Bystanders.SAY_FIRST = 2.2
Bystanders.SAY_EACH = 0.85

local ANGLE_TRIES = { 0, 0.4, -0.4, 0.8, -0.8, 1.2, -1.2 } -- radians round the ring
local RADIUS_TRIES = { 1, 0.75, 1.3, 1.6 }
local SWEEP = 16 -- directions tried all the way round for the places the ring could not give

-- select: everyone who could come over (eligible, within the radius), nearest first, and how many
-- are wanted (0: no crowd this time). Draws: one for "does a crowd form", one for its size.
function Bystanders.select(
	scene: { x: number, z: number },
	candidates: { Candidate },
	rand: () -> number,
	params: Params
): ({ any }, number)
	if rand() >= params.chance then
		return {}, 0
	end
	local want = params.min + math.floor(rand() * (params.max - params.min + 1))
	want = math.clamp(want, params.min, params.max)
	local near: { { id: any, d: number } } = {}
	for _, c in candidates do
		if c.eligible then
			local d = math.sqrt((c.x - scene.x) ^ 2 + (c.z - scene.z) ^ 2)
			if d <= params.radius then
				table.insert(near, { id = c.id, d = d })
			end
		end
	end
	table.sort(near, function(a, b)
		if a.d ~= b.d then
			return a.d < b.d
		end
		return tostring(a.id) < tostring(b.id)
	end)
	local out = {}
	for i, n in near do
		out[i] = n.id
	end
	return out, want
end

-- spots: up to n standing spots round the victim. `isFree(x, z)` rejects a spot.
function Bystanders.spots(
	scene: { x: number, z: number },
	n: number,
	isFree: (x: number, z: number) -> boolean,
	ring: number
): { { number } }
	local out: { { number } } = {}
	local function take(a: number, rk: number): boolean
		local x, z = scene.x + math.cos(a) * ring * rk, scene.z + math.sin(a) * ring * rk
		if not isFree(x, z) then
			return false
		end
		for _, other in out do
			if (other[1] - x) ^ 2 + (other[2] - z) ^ 2 < Bystanders.MIN_APART ^ 2 then
				return false
			end
		end
		table.insert(out, { x, z })
		return true
	end
	for i = 0, n - 1 do
		local base = (i + 0.33) * 2 * math.pi / math.max(1, n)
		local found = false
		for _, rk in RADIUS_TRIES do
			for _, da in ANGLE_TRIES do
				if take(base + da, rk) then
					found = true
					break
				end
			end
			if found then
				break
			end
		end
	end
	-- the places the ring could not give: anywhere round the victim that is free
	for _, rk in RADIUS_TRIES do
		for k = 0, SWEEP - 1 do
			if #out >= n then
				return out
			end
			take((k + 0.5) * 2 * math.pi / SWEEP, rk)
		end
	end
	return out
end

-- assign: people in the given order (nearest to the scene first) each take the nearest remaining
-- spot they can walk to, until `want` are placed (default: as many as there are spots). `wayTo`
-- returns the waypoints of the walk (the spot last) or nil; it is asked for a person's SPOT_TRIES
-- nearest free spots only, so a street full of people who cannot come costs little. With fewer than
-- `min` placed, nobody is.
function Bystanders.assign(
	people: { Place },
	spots: { { number } },
	wayTo: (person: Place, x: number, z: number) -> { { number } }?,
	want: number?,
	min: number?
): { Place }
	local taken: { [number]: boolean } = {}
	local out: { Place } = {}
	local limit = math.min(want or #spots, #spots)
	for _, p in people do
		if #out >= limit then
			break
		end
		local order: { { i: number, d: number } } = {}
		for i, s in spots do
			if not taken[i] then
				table.insert(order, { i = i, d = (s[1] - p.x) ^ 2 + (s[2] - p.z) ^ 2 })
			end
		end
		table.sort(order, function(a, b)
			if a.d ~= b.d then
				return a.d < b.d
			end
			return a.i < b.i
		end)
		for k = 1, math.min(#order, Bystanders.SPOT_TRIES) do
			local i = order[k].i
			local path = wayTo(p, spots[i][1], spots[i][2])
			if path then
				taken[i] = true
				table.insert(out, { id = p.id, x = spots[i][1], z = spots[i][2], path = path })
				break
			end
		end
	end
	if #out < (min or 1) then
		return {}
	end
	return out
end

return Bystanders
