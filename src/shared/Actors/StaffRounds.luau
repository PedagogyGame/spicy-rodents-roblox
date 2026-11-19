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
--   * VENUES: the built expansion venues (generated/Expansion: a venue with `built`) are indoor floors above the
--     ground, and one with a "staff_post" anchor has a member of staff behind its counter (Pepper's Corner
--     Store: the first shop worker, AI/TownAI): venues(expansion) lists them, with the post's short round along
--     the counter (POST_ROUND, local X and D about the post), and floorAt says which floor a point is on. A
--     "venue_staff_post" is a post the venue staffs itself (THE GILDED ACORN's baked bartender): no town worker.
-- Interface: CIRCUIT; POLICE { x, z }; POLICE_EXIT; points(stationX, stationZ, index) -> { {x, z} } (studs);
--   bounds(stationX, stationZ) -> cx, cz, r (a disc that holds the round for every index);
--   POST_ROUND; venues(expansion?) -> { Venue { id, place, hw, hd, floorY, post: { x, z, round } ? } };
--   floorAt(venues, x, z) -> floorY? (inside a built venue's footprint). A staffed post also has its way out
--   (`exit`, world studs, the post first): along behind the counter past its end (POST_CLEAR), to a step inside the
--   venue's first entrance and out to the spot in front of it (World/WalkWay walks the shopkeeper by it).
-- Pure; studs out. No side effects on require.

local AlleyLayout = require("../Attractions/AlleyLayout")

local StaffRounds = {}

local S = 2.5 -- studs per HTML unit (Config/Units; restated so this module needs nothing else)

StaffRounds.CIRCUIT = table.freeze({
	table.freeze({ 0, 0 }),
	table.freeze({ 2.6, -0.65 }),
	table.freeze({ 2.1, -2.8 }),
	table.freeze({ 0, -2.0 }),
})

StaffRounds.POLICE = table.freeze({ x = 6, z = -12 })

-- The way out of the police station from the locker room (World/WalkWay: how its indoor staff leave and come back):
-- studs from the centre of the station's lot, in world axes, the deepest first. Through the gap in the locker room's
-- front wall, round the east end of the front desk, out of the glass entrance to the spot in front of it.
StaffRounds.POLICE_EXIT = table.freeze({
	table.freeze({ 3, -12 }),
	table.freeze({ 0, 1.5 }),
	table.freeze({ 0, 8.5 }),
	table.freeze({ 8, 14.5 }),
	table.freeze({ 8, 27.5 }),
	table.freeze({ 0, 34.5 }),
	table.freeze({ 0, 45 }),
})

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

-- The round behind a counter: the post, then a step or two either way along it (local X, D about the post).
StaffRounds.POST_ROUND = table.freeze({
	table.freeze({ 0, 0 }),
	table.freeze({ 2.5, -0.2 }),
	table.freeze({ 0, 0 }),
	table.freeze({ -2.5, -0.2 }),
})

export type Venue = {
	id: string,
	place: AlleyLayout.Place,
	hw: number,
	hd: number,
	floorY: number,
	-- world studs; round as offsets from (x, z); exit: the way out, the post first, the spot outside last
	post: { x: number, z: number, round: { { number } }, exit: { { number } }? }?,
}

StaffRounds.POST_CLEAR = 5.5 -- studs along the counter from the post to past its end
StaffRounds.DOOR_IN, StaffRounds.DOOR_OUT = 3, 6 -- studs inside and outside an entrance its way passes

function StaffRounds.venues(expansion: any?): { Venue }
	local out: { Venue } = {}
	for _, v in (if expansion and expansion.venues then expansion.venues else {}) :: { any } do
		if v.built == nil or v.place == nil or v.footprint == nil then
			continue
		end
		local venue: Venue = {
			id = v.id,
			place = v.place,
			hw = v.footprint.w / 2,
			hd = v.footprint.d / 2,
			floorY = v.floorY,
		}
		for _, a in v.anchors or {} do
			if a.kind == "staff_post" and venue.post == nil then
				local px, _, pz = AlleyLayout.toWorld(v.place, a.at[1], 0, a.at[3])
				local round = {}
				for _, r in StaffRounds.POST_ROUND do
					local x, _, z = AlleyLayout.toWorld(v.place, a.at[1] + r[1], 0, a.at[3] + r[2])
					table.insert(round, { x - px, z - pz })
				end
				local exit: { { number } }? = nil
				local door = v.entrances and v.entrances[1]
				if door and door.at then
					local ex, ed = door.at[1], door.at[2]
					-- the entrance's wall: the side of the footprint it is nearest to; inward is away from it
					local alongD = math.abs(math.abs(ed) - venue.hd) < math.abs(math.abs(ex) - venue.hw)
					local nx = if alongD then 0 else -math.sign(ex)
					local nd = if alongD then -math.sign(ed) else 0
					local side = math.sign(ex - a.at[1])
					local points = {
						{ a.at[1], a.at[3] },
						{ a.at[1] + side * StaffRounds.POST_CLEAR, a.at[3] },
						{ ex + nx * StaffRounds.DOOR_IN, ed + nd * StaffRounds.DOOR_IN },
						{ ex - nx * StaffRounds.DOOR_OUT, ed - nd * StaffRounds.DOOR_OUT },
					}
					exit = {}
					for _, p in points do
						local x, _, z = AlleyLayout.toWorld(v.place, p[1], 0, p[2])
						table.insert(exit :: { { number } }, { x, z })
					end
				end
				venue.post = { x = px, z = pz, round = round, exit = exit }
			end
		end
		table.insert(out, venue)
	end
	return out
end

function StaffRounds.floorAt(venues: { Venue }, x: number, z: number): number?
	for _, v in venues do
		local lx, _, ld = AlleyLayout.toLocal(v.place, x, 0, z)
		if math.abs(lx) <= v.hw and math.abs(ld) <= v.hd then
			return v.floorY
		end
	end
	return nil
end

return StaffRounds
