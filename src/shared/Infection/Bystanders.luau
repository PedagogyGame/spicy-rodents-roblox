--!strict
-- ReplicatedStorage.Shared.Infection.Bystanders
-- The crowd at a scene (owner 2026-11-10: "a crowd gather sometimes"; humans_actors §7.4
-- gatherAtCrime): which nearby townspeople come and where each one stands. v5.4 kept a pool of seven
-- hidden extras and popped them in around the victim; here real townspeople who are close by walk
-- over, so a crowd only forms where people actually are.
--   select: with chance crowdChance, 2 to 4 (the dice) of the nearest eligible people within the
--     radius, nearest first; fewer when the street is nearly empty, none when it is.
--   spots: the v5.4 ring, angle (i + 0.33) 2 pi / n at `ring` studs from the victim; a spot the
--     caller's `isFree` rejects (inside a building, on the road where the ambulance stops) is tried
--     again a little round the ring and nearer or further; spots keep MIN_APART from each other.
--   assign: each person takes the nearest free spot they can walk to in a straight line (`canWalk`:
--     kinematic people do not collide, so a blocked line would be a walk through a house); a person
--     with no such spot stays out of it.
-- Interface: select(scene, candidates, rand, params) -> { id }; spots(scene, n, isFree, ring) ->
--   { {x, z} }; assign(people, spots, canWalk) -> { { id, x, z } }; MIN_APART; SAY_FIRST, SAY_EACH
-- Pure; studs. No side effects on require.

export type Candidate = { id: any, x: number, z: number, eligible: boolean }
export type Params = { chance: number, min: number, max: number, radius: number }
export type Place = { id: any, x: number, z: number }

local Bystanders = {}

Bystanders.MIN_APART = 4 -- studs between two bystanders
-- humans_actors §7.4: bystander i speaks once, 2.2 + 0.85 i seconds after being called over
Bystanders.SAY_FIRST = 2.2
Bystanders.SAY_EACH = 0.85

local ANGLE_TRIES = { 0, 0.4, -0.4, 0.8, -0.8, 1.2, -1.2 } -- radians round the ring
local RADIUS_TRIES = { 1, 0.75, 1.3, 1.6 }

-- select: the ids of the people who come over, nearest first. Draws: one for "does a crowd form",
-- one for its size.
function Bystanders.select(
	scene: { x: number, z: number },
	candidates: { Candidate },
	rand: () -> number,
	params: Params
): { any }
	if rand() >= params.chance then
		return {}
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
	for i = 1, math.min(want, #near) do
		out[i] = near[i].id
	end
	return out
end

-- spots: up to n standing spots round the victim. `isFree(x, z)` rejects a spot.
function Bystanders.spots(
	scene: { x: number, z: number },
	n: number,
	isFree: (x: number, z: number) -> boolean,
	ring: number
): { { number } }
	local out: { { number } } = {}
	for i = 0, n - 1 do
		local base = (i + 0.33) * 2 * math.pi / math.max(1, n)
		local found: { number }? = nil
		for _, rk in RADIUS_TRIES do
			for _, da in ANGLE_TRIES do
				local a = base + da
				local x, z = scene.x + math.cos(a) * ring * rk, scene.z + math.sin(a) * ring * rk
				local ok = isFree(x, z)
				if ok then
					for _, other in out do
						if (other[1] - x) ^ 2 + (other[2] - z) ^ 2 < Bystanders.MIN_APART ^ 2 then
							ok = false
							break
						end
					end
				end
				if ok then
					found = { x, z }
					break
				end
			end
			if found then
				break
			end
		end
		if found then
			table.insert(out, found)
		end
	end
	return out
end

-- assign: people in the given order (nearest to the scene first) each take the nearest remaining
-- spot they can walk to.
function Bystanders.assign(
	people: { Place },
	spots: { { number } },
	canWalk: (person: Place, x: number, z: number) -> boolean
): { Place }
	local taken: { [number]: boolean } = {}
	local out: { Place } = {}
	for _, p in people do
		local best, bestD = nil, math.huge
		for i, s in spots do
			if not taken[i] then
				local d = (s[1] - p.x) ^ 2 + (s[2] - p.z) ^ 2
				if d < bestD and canWalk(p, s[1], s[2]) then
					best, bestD = i, d
				end
			end
		end
		if best then
			taken[best] = true
			table.insert(out, { id = p.id, x = spots[best][1], z = spots[best][2] })
		end
	end
	return out
end

return Bystanders
