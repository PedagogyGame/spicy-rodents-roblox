--!strict
-- ReplicatedStorage.Shared.Infection.HospitalLayout
-- Where things happen at the hospital, in world studs, from the data (the `hospital_main` lot and the
-- generated/Buildings hospital programme): the entrance door, the spot in front of it, the reception
-- point inside, the intake (triage) where an ambulance patient waits unseen, and the beds in the two
-- wards with the ward door each bed is reached through. The local frame is the bake's (WorldGen/
-- Builders/Programme: lx across the front, lz toward the front, HTML units; the model's LookVector
-- is the lot's facing through Units' single +pi), so a bed stands where the baked ward is.
--
-- The hospital is furnished and can be walked into (the interiors work, 2026-11-11), so the places and
-- the ways between them are laid out round what stands in the rooms, and the bake keeps them clear:
--   * reception is the check-in spot in front of the reception desk (the middle of the room is behind
--     the desk: people walked through it); the intake is the spot in front of the triage desk;
--   * LANES join everything: the door to the check-in spot, sideways along the front of the desk to a
--     point in line with each ward door, through that door, down the ward's main aisle, along the aisle
--     at the foot of each row of beds, and from a bed's foot onto the bed. Every walk inside the
--     hospital (`walk`, `pathIn`, `pathOut`) follows lanes, so nobody crosses a desk, a column, another
--     bed or a wall;
--   * POSTS are the rounds the staff walk: up and down the aisle at the foot of each row of beds, and a
--     few steps behind the reception desk (Server/AI/TownAI). They are lanes too.
-- `plan` is all of this in the lot's own frame (HTML units), with nothing but the building record:
-- WorldGen/Builders/Programme reserves the beds, the lanes and the posts from it before any furniture
-- is placed, and tests/unit/hospital_ways.spec checks the baked hospital against it.
-- Interface: plan(building, beds?) -> Plan (lot-local, HTML units); fromData(data, beds?) -> Layout?;
--   contains(layout, x, z, pad?) -> boolean; nearEntrance(layout, x, z, r) -> boolean;
--   walk(layout, x0, z0, x1, z1) -> { {x, z} } (the way along the lanes; the start itself left out);
--   pathIn(layout, bed) -> { {x, z} }; pathOut(layout, bed) -> { {x, z} }; bedFace(layout, bed) ->
--   {x, z} (the point a patient in that bed looks at); BED { length, width, top } (studs: the cot the
--   server builds at each bed); BEDS (how many the bake keeps room for); LANE (half the width kept
--   clear along a lane, studs)
-- Pure; studs. No side effects on require.

export type Bed = { index: number, x: number, z: number, ward: string, door: { number }, foot: { number } }
export type Post = { id: string, room: string, points: { { number } } }

-- The same, before it is placed in the world: lot-local HTML units (lx across the front, lz toward it).
export type Plan = {
	entrance: { number },
	outside: { number },
	reception: { number },
	intake: { number },
	desk: { number }?, -- the reception desk the check-in spot stands in front of
	beds: { Bed },
	lanes: { { number } }, -- { x1, z1, x2, z2 }: node to node
	posts: { Post },
}

export type Layout = {
	lot: { x: number, z: number, hw: number, hd: number },
	yaw: number, -- HTML yaw of the front
	entrance: { number }, -- the door, on the front wall
	outside: { number }, -- a few studs in front of the door
	reception: { number }, -- inside: the check-in spot in front of the reception desk
	intake: { number }, -- triage: where a patient brought by ambulance waits (unseen)
	beds: { Bed },
	lanes: { { number } }, -- { x1, z1, x2, z2 } in world studs
	posts: { Post },
}

local HospitalLayout = {}

local S = 2.5 -- studs per HTML unit (Config/Units; restated so this module needs nothing else)
local CARDINAL: { [string]: number } = { ["+Z"] = 0, ["-Z"] = math.pi, ["+X"] = math.pi / 2, ["-X"] = -math.pi / 2 }
local OUTSIDE = 8 -- studs in front of the door
local CHECK_IN = 6.5 -- studs from a desk's middle to where somebody stands in front of it
local BEHIND = 5 -- and to where its own staff stand behind it
local FOOT = 3 -- studs between the foot of a cot and the middle of the aisle along its row
local SNAP = 1.5 -- a walker this near a lane steps onto it where they are, not at its end

-- The cot at each bed: a patient sits up on a mattress whose top is this far above the floor.
HospitalLayout.BED = table.freeze({ length = 7, width = 3.4, top = 1.6 })
-- How many beds the bake keeps room for (Tunables hospital.beds; the spec holds the two together).
HospitalLayout.BEDS = 8
-- Half the width the bake keeps clear along a lane: a body 1 st in radius and a little air.
HospitalLayout.LANE = 1.6

local function find(list: { any }, id: string): any?
	for _, item in list do
		if item.id == id then
			return item
		end
	end
	return nil
end

-- plan(building, beds?): the places, lanes and posts in the lot's own frame, or nil without an entrance
-- door and a reception room.
function HospitalLayout.plan(b: any, beds: number?): Plan?
	local entranceDoor = find(b.doors, "entrance")
	local reception = find(b.rooms, "reception")
	local triage = find(b.rooms, "triage")
	if entranceDoor == nil or reception == nil then
		return nil
	end
	local lanes: { { number } } = {}
	local function lane(a: { number }, c: { number })
		if math.abs(a[1] - c[1]) + math.abs(a[2] - c[2]) > 1e-6 then
			table.insert(lanes, { a[1], a[2], c[1], c[2] })
		end
	end
	local function centre(room: any): { number }
		local r = room.rect
		return { (r[1] + r[2]) / 2, (r[3] + r[4]) / 2 }
	end
	-- a desk faces the front of the building (Builders/Furnish turns it to the nearest door; for the
	-- reception and triage desks that is the front): people stand on its front side
	local function station(room: string, kind: string): any?
		for _, s in b.stations or {} do
			if s.room == room and s.kind == kind then
				return s
			end
		end
		return nil
	end
	local ex, ez = entranceDoor.at[1], entranceDoor.at[2]
	local entrance = { ex, ez }
	local outside = { ex, ez + OUTSIDE / S }
	local desk = station("reception", "admit")
	local checkIn = if desk then { desk.at[1], desk.at[2] + CHECK_IN / S } else centre(reception)
	local triageDesk = if triage then station("triage", "triage") else nil
	local intake = if triageDesk
		then { triageDesk.at[1], triageDesk.at[2] + CHECK_IN / S }
		elseif triage then centre(triage)
		else checkIn
	lane(outside, entrance)
	-- the door and the check-in spot are in line in the data; a corner keeps the lane square if not
	if math.abs(ex - checkIn[1]) > 1e-6 then
		lane(entrance, { ex, checkIn[2] })
		lane({ ex, checkIn[2] }, checkIn)
	else
		lane(entrance, checkIn)
	end

	local posts: { Post } = {}
	local out: { Bed } = {}
	local wards = {}
	for _, id in { "ward_a", "ward_b" } do
		local room = find(b.rooms, id)
		local door = find(b.doors, "rec_" .. id)
		if room and door then
			table.insert(wards, { room = room, door = { door.at[1], door.at[2] } })
		end
	end
	local want = beds or HospitalLayout.BEDS
	local perWard = if #wards > 0 then math.ceil(want / #wards) else 0
	local rows = math.ceil(perWard / 2)
	for w, ward in wards do
		local r = ward.room.rect
		local dx, dz = ward.door[1], ward.door[2]
		-- sideways from the check-in spot to a point in line with the ward door, then through the door.
		-- On the way the first ward's lane passes the corner the desk's own staff turn at.
		local side = { dx, checkIn[2] }
		lane(checkIn, side)
		local from = side
		if desk and w == 1 then
			local turn = { dx, desk.at[2] - BEHIND / S }
			local dir = if dx < desk.at[1] then -1 else 1
			local near = { desk.at[1] + dir * 1.5 / S, turn[2] }
			local far = { desk.at[1] - dir * 1.5 / S, turn[2] }
			lane(side, turn)
			lane(turn, near)
			lane(near, far)
			table.insert(posts, { id = "reception_desk", room = "reception", points = { near, far } })
			from = turn
		end
		lane(from, ward.door)
		-- the beds: two columns, `rows` rows, the pillow toward the back wall
		local mine: { { lx: number, lz: number, row: number } } = {}
		for k = 0, perWard - 1 do
			if #out + #mine >= want then
				break
			end
			local col, row = k % 2, k // 2
			table.insert(mine, {
				lx = r[1] + (r[2] - r[1]) * (0.25 + 0.5 * col),
				lz = r[3] + (r[4] - r[3]) * ((row + 0.5) / rows * 0.7 + 0.1),
				row = row,
			})
		end
		-- the main aisle runs in from the door; each row has its aisle at the foot of its beds (the
		-- front side, where the patients look), nearest row first
		local rowIds: { number } = {}
		local aisle: { [number]: number } = {}
		for _, m in mine do
			if aisle[m.row] == nil then
				aisle[m.row] = m.lz + (HospitalLayout.BED.length / 2 + FOOT) / S
				table.insert(rowIds, m.row)
			end
		end
		table.sort(rowIds, function(a, c)
			return math.abs(aisle[a] - dz) < math.abs(aisle[c] - dz)
		end)
		local at = ward.door
		for _, row in rowIds do
			local junction = { dx, aisle[row] }
			lane(at, junction)
			at = junction
			-- along the row, away from the main aisle on each side of it
			local feet: { { number } } = {}
			for _, m in mine do
				if m.row == row then
					table.insert(feet, { m.lx, aisle[row] })
				end
			end
			table.sort(feet, function(a, c)
				return math.abs(a[1] - dx) < math.abs(c[1] - dx)
			end)
			local last: { [number]: { number } } = { [-1] = junction, [1] = junction }
			local round: { { number } } = { junction }
			for _, f in feet do
				local sideOf = if f[1] < dx then -1 else 1
				lane(last[sideOf], f)
				last[sideOf] = f
				table.insert(round, f)
			end
			-- the staff's round of this row: out along the feet of its beds and back
			for i = #feet - 1, 1, -1 do
				table.insert(round, feet[i])
			end
			table.insert(posts, { id = `{ward.room.id}_row{row + 1}`, room = ward.room.id, points = round })
		end
		for _, m in mine do
			local foot = { m.lx, aisle[m.row] }
			lane(foot, { m.lx, m.lz })
			table.insert(
				out,
				{ index = #out + 1, x = m.lx, z = m.lz, ward = ward.room.id, door = ward.door, foot = foot }
			)
		end
	end
	return {
		entrance = entrance,
		outside = outside,
		reception = checkIn,
		intake = intake,
		desk = if desk then { desk.at[1], desk.at[2] } else nil,
		beds = out,
		lanes = lanes,
		posts = posts,
	}
end

-- fromData(data, beds?): nil when the town has no hospital lot or programme.
function HospitalLayout.fromData(data: any, beds: number?): Layout?
	local lot = data:lot("hospital_main")
	local buildings = data:buildings()
	local b = buildings and buildings.hospital
	if lot == nil or b == nil or lot.footprint == nil then
		return nil
	end
	local plan = HospitalLayout.plan(b, beds)
	if plan == nil then
		return nil
	end
	local yaw = if lot.facing and CARDINAL[lot.facing] ~= nil then CARDINAL[lot.facing] else (lot.yaw or 0)
	local fx, fz = math.sin(yaw), math.cos(yaw) -- the front direction (lz+)
	local rx, rz = -fz, fx -- lx+
	local function world(p: { number }): { number }
		return { lot.x + (p[1] * rx + p[2] * fx) * S, lot.z + (p[1] * rz + p[2] * fz) * S }
	end
	local layout: Layout = {
		lot = { x = lot.x, z = lot.z, hw = lot.footprint.w / 2, hd = lot.footprint.d / 2 },
		yaw = yaw,
		entrance = world(plan.entrance),
		outside = world(plan.outside),
		reception = world(plan.reception),
		intake = world(plan.intake),
		beds = {},
		lanes = {},
		posts = {},
	}
	for _, bed in plan.beds do
		local p = world({ bed.x, bed.z })
		table.insert(layout.beds, {
			index = bed.index,
			x = p[1],
			z = p[2],
			ward = bed.ward,
			door = world(bed.door),
			foot = world(bed.foot),
		})
	end
	for _, l in plan.lanes do
		local a, c = world({ l[1], l[2] }), world({ l[3], l[4] })
		table.insert(layout.lanes, { a[1], a[2], c[1], c[2] })
	end
	for _, post in plan.posts do
		local points = {}
		for _, p in post.points do
			table.insert(points, world(p))
		end
		table.insert(layout.posts, { id = post.id, room = post.room, points = points })
	end
	return layout
end

-- contains: inside the hospital's footprint (pad grows it).
function HospitalLayout.contains(layout: Layout, x: number, z: number, pad: number?): boolean
	local p = pad or 0
	return math.abs(x - layout.lot.x) <= layout.lot.hw + p and math.abs(z - layout.lot.z) <= layout.lot.hd + p
end

function HospitalLayout.nearEntrance(layout: Layout, x: number, z: number, r: number): boolean
	local dx, dz = x - layout.entrance[1], z - layout.entrance[2]
	return dx * dx + dz * dz <= r * r
end

-- bedFace: the point a patient sitting up in the bed looks at: along the cot, away from its pillow.
-- The cots lie along the hospital's depth with the pillow toward the back wall (Server/Hospital/
-- HospitalProps), so that is toward the front. A patient's legs lie out in front of them: facing the
-- ward door instead, they lay across the cot's corner and through its frame.
function HospitalLayout.bedFace(layout: Layout, bed: Bed): { number }
	local reach = 4 * HospitalLayout.BED.length
	return { bed.x + math.sin(layout.yaw) * reach, bed.z + math.cos(layout.yaw) * reach }
end

-- Where a walker joins or leaves the lanes: the ends of the nearest lane, each with the distance to
-- it. Standing on the lane (within SNAP) either end will do, and the lane's index is returned; off the
-- lanes (a room they do not reach) it is the nearer end, in a straight line.
local function hop(layout: Layout, x: number, z: number): ({ { number } }, number?)
	local best, bestD = 0, math.huge
	for i, l in layout.lanes do
		local ax, az, bx, bz = l[1], l[2], l[3], l[4]
		local abx, abz = bx - ax, bz - az
		local t = math.clamp(((x - ax) * abx + (z - az) * abz) / (abx * abx + abz * abz), 0, 1)
		local d = math.sqrt((x - ax - abx * t) ^ 2 + (z - az - abz * t) ^ 2)
		if d < bestD then
			best, bestD = i, d
		end
	end
	local l = layout.lanes[best]
	if l == nil then
		return {}, nil
	end
	local ends = {
		{ l[1], l[2], math.sqrt((x - l[1]) ^ 2 + (z - l[2]) ^ 2) },
		{ l[3], l[4], math.sqrt((x - l[3]) ^ 2 + (z - l[4]) ^ 2) },
	}
	if bestD <= SNAP then
		return ends, best
	end
	return { if ends[1][3] <= ends[2][3] then ends[1] else ends[2] }, nil
end

-- walk(layout, x0, z0, x1, z1): the way from one point of the hospital to another along the lanes: the
-- points to walk to, in order, ending at (x1, z1); the start itself is left out. Points that are not on
-- a lane are joined to the nearest one in a straight line (the bake keeps nothing clear for that).
function HospitalLayout.walk(layout: Layout, x0: number, z0: number, x1: number, z1: number): { { number } }
	-- nodes: the lane ends (shared ends are one node)
	local nodes: { { number } } = {}
	local index: { [string]: number } = {}
	local links: { { { number } } } = {}
	local function node(x: number, z: number): number
		local key = string.format("%.2f,%.2f", x, z)
		local i = index[key]
		if i == nil then
			table.insert(nodes, { x, z })
			i = #nodes
			index[key] = i
			links[i] = {}
		end
		return i
	end
	for _, l in layout.lanes do
		local a, c = node(l[1], l[2]), node(l[3], l[4])
		local len = math.sqrt((l[3] - l[1]) ^ 2 + (l[4] - l[2]) ^ 2)
		table.insert(links[a], { c, len })
		table.insert(links[c], { a, len })
	end
	local out: { { number } } = {}
	local function push(x: number, z: number)
		local last = out[#out]
		local lx, lz = if last then last[1] else x0, if last then last[2] else z0
		if math.abs(lx - x) + math.abs(lz - z) > 0.05 then
			table.insert(out, { x, z })
		end
	end
	local starts, startLane = hop(layout, x0, z0)
	local goals, goalLane = hop(layout, x1, z1)
	-- no lanes at all, or both on the same stretch of lane: straight there
	if #starts == 0 or #goals == 0 or (startLane ~= nil and startLane == goalLane) then
		push(x1, z1)
		return out
	end
	-- Dijkstra over a few dozen nodes
	local dist: { number } = table.create(#nodes, math.huge)
	local prev: { number } = table.create(#nodes, 0)
	local done: { boolean } = table.create(#nodes, false)
	for _, s in starts do
		dist[node(s[1], s[2])] = s[3]
	end
	for _ = 1, #nodes do
		local u, best = 0, math.huge
		for i = 1, #nodes do
			if not done[i] and dist[i] < best then
				u, best = i, dist[i]
			end
		end
		if u == 0 then
			break
		end
		done[u] = true
		for _, e in links[u] do
			if best + e[2] < dist[e[1]] then
				dist[e[1]] = best + e[2]
				prev[e[1]] = u
			end
		end
	end
	local goal, total = 0, math.huge
	for _, g in goals do
		local i = node(g[1], g[2])
		if dist[i] + g[3] < total then
			goal, total = i, dist[i] + g[3]
		end
	end
	if goal == 0 or total == math.huge then
		push(x1, z1)
		return out
	end
	local chain: { number } = {}
	local at = goal
	while at ~= 0 do
		table.insert(chain, 1, at)
		at = prev[at]
	end
	for _, i in chain do
		push(nodes[i][1], nodes[i][2])
	end
	push(x1, z1)
	return out
end

-- pathIn: the door, the check-in spot, the ward's door, the aisles and the bed.
function HospitalLayout.pathIn(layout: Layout, bed: Bed): { { number } }
	local points = { { layout.entrance[1], layout.entrance[2] } }
	for _, p in HospitalLayout.walk(layout, layout.entrance[1], layout.entrance[2], bed.x, bed.z) do
		table.insert(points, p)
	end
	return points
end

-- pathOut: from the bed along the aisles, out at the ward's door, past the desk, the door, outside.
function HospitalLayout.pathOut(layout: Layout, bed: Bed): { { number } }
	return HospitalLayout.walk(layout, bed.x, bed.z, layout.outside[1], layout.outside[2])
end

return HospitalLayout
