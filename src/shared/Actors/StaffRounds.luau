--!strict
-- ReplicatedStorage.Shared.Actors.StaffRounds
-- The short round a member of staff walks about a post, and where the indoor posts are (the interiors
-- work, 2026-11-11). Staff are kinematic: nothing stops them at a wall or a desk, so a round that
-- crosses furniture is a person walking through it. The buildings are furnished and can be walked
-- into now, so the bake keeps the floor under every indoor round clear, and both sides read the round
-- from here:
--   * CIRCUIT is the v5.4 staff circuit (hospital_police_infection §5.3: station -> +(dir 2.6, -0.65)
--     -> +(dir 2.1, -2.8) -> +(0, -2.0), HTML units; dir alternates with the staff member's index).
--     Server/Actors/Brains/Staff walks it; the hospital's staff walk the ward rounds of
--     Infection/HospitalLayout instead.
--   * POLICE is where the station's indoor staff (the guard and the car crew) have theirs: studs from
--     the centre of the station's lot, in world axes. It is in the locker room at the back.
-- Interface: CIRCUIT; POLICE { x, z }; points(stationX, stationZ, index) -> { {x, z} } (studs);
--   bounds(stationX, stationZ) -> cx, cz, r (a disc that holds the round for every index)
-- Pure; studs out. No side effects on require.

local StaffRounds = {}

local S = 2.5 -- studs per HTML unit (Config/Units; restated so this module needs nothing else)

StaffRounds.CIRCUIT = table.freeze({
	table.freeze({ 0, 0 }),
	table.freeze({ 2.6, -0.65 }),
	table.freeze({ 2.1, -2.8 }),
	table.freeze({ 0, -2.0 }),
})

StaffRounds.POLICE = table.freeze({ x = 6, z = -12 })

-- The round of staff member `index` about a station: the circuit, mirrored for every other member.
function StaffRounds.points(stationX: number, stationZ: number, index: number): { { number } }
	local dir = if index % 2 == 1 then 1 else -1
	local out = {}
	for _, p in StaffRounds.CIRCUIT do
		table.insert(out, { stationX + dir * p[1] * S, stationZ + p[2] * S })
	end
	return out
end

-- A disc that holds both mirror images of the round about a station.
function StaffRounds.bounds(stationX: number, stationZ: number): (number, number, number)
	local z0, z1, half = math.huge, -math.huge, 0
	for _, p in StaffRounds.CIRCUIT do
		z0, z1 = math.min(z0, p[2] * S), math.max(z1, p[2] * S)
		half = math.max(half, math.abs(p[1]) * S)
	end
	local cz = (z0 + z1) / 2
	local r = 0
	for _, p in StaffRounds.CIRCUIT do
		r = math.max(r, math.sqrt((p[1] * S) ^ 2 + (p[2] * S - cz) ^ 2))
	end
	return stationX, stationZ + cz, math.max(r, half)
end

return StaffRounds
