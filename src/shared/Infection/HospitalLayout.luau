--!strict
-- ReplicatedStorage.Shared.Infection.HospitalLayout
-- Where things happen at the hospital, in world studs, from the data (the `hospital_main` lot and the
-- generated/Buildings hospital programme): the entrance door, the spot in front of it, the reception
-- point inside, the intake (triage) where an ambulance patient waits unseen, and the beds in the two
-- wards with the ward door each bed is reached through. The local frame is the bake's (WorldGen/
-- Builders/Programme: lx across the front, lz toward the front, HTML units; the model's LookVector
-- is the lot's facing through Units' single +pi), so a bed stands where the baked ward is.
-- Interface: fromData(data, beds?) -> Layout?; contains(layout, x, z, pad?) -> boolean;
--   nearEntrance(layout, x, z, r) -> boolean; pathIn(layout, bed) -> { {x, z} }; pathOut(layout, bed)
--   -> { {x, z} }; BED { length, width, top } (studs: the cot the server builds at each bed)
-- Pure; studs. No side effects on require.

export type Bed = { index: number, x: number, z: number, ward: string, door: { number } }

export type Layout = {
	lot: { x: number, z: number, hw: number, hd: number },
	yaw: number, -- HTML yaw of the front
	entrance: { number }, -- the door, on the front wall
	outside: { number }, -- a few studs in front of the door
	reception: { number }, -- inside, between the door and the wards
	intake: { number }, -- triage: where a patient brought by ambulance waits (unseen)
	beds: { Bed },
}

local HospitalLayout = {}

local S = 2.5 -- studs per HTML unit (Config/Units; restated so this module needs nothing else)
local CARDINAL: { [string]: number } = { ["+Z"] = 0, ["-Z"] = math.pi, ["+X"] = math.pi / 2, ["-X"] = -math.pi / 2 }
local OUTSIDE = 8 -- studs in front of the door

-- The cot at each bed: a patient sits up on a mattress whose top is this far above the floor.
HospitalLayout.BED = table.freeze({ length = 7, width = 3.4, top = 1.6 })

local function find(list: { any }, id: string): any?
	for _, item in list do
		if item.id == id then
			return item
		end
	end
	return nil
end

-- fromData(data, beds?): nil when the town has no hospital lot or programme.
function HospitalLayout.fromData(data: any, beds: number?): Layout?
	local lot = data:lot("hospital_main")
	local buildings = data:buildings()
	local b = buildings and buildings.hospital
	if lot == nil or b == nil or lot.footprint == nil then
		return nil
	end
	local yaw = if lot.facing and CARDINAL[lot.facing] ~= nil then CARDINAL[lot.facing] else (lot.yaw or 0)
	local fx, fz = math.sin(yaw), math.cos(yaw) -- the front direction (lz+)
	local rx, rz = -fz, fx -- lx+
	local function world(lx: number, lz: number): { number }
		return { lot.x + (lx * rx + lz * fx) * S, lot.z + (lx * rz + lz * fz) * S }
	end
	local entranceDoor = find(b.doors, "entrance")
	local reception = find(b.rooms, "reception")
	local triage = find(b.rooms, "triage")
	if entranceDoor == nil or reception == nil then
		return nil
	end
	local ex, ez = entranceDoor.at[1], entranceDoor.at[2]
	local function centre(room: any): { number }
		local r = room.rect
		return world((r[1] + r[2]) / 2, (r[3] + r[4]) / 2)
	end
	local layout: Layout = {
		lot = { x = lot.x, z = lot.z, hw = lot.footprint.w / 2, hd = lot.footprint.d / 2 },
		yaw = yaw,
		entrance = world(ex, ez),
		outside = world(ex, ez + OUTSIDE / S),
		reception = centre(reception),
		intake = centre(triage or reception),
		beds = {},
	}
	local wards = {}
	for _, id in { "ward_a", "ward_b" } do
		local room = find(b.rooms, id)
		if room then
			local door = find(b.doors, "rec_" .. id)
			table.insert(
				wards,
				{ room = room, door = if door then world(door.at[1], door.at[2]) else layout.reception }
			)
		end
	end
	local want = beds or 8
	if #wards > 0 then
		local perWard = math.ceil(want / #wards)
		local rows = math.ceil(perWard / 2)
		for _, ward in wards do
			local r = ward.room.rect
			for k = 0, perWard - 1 do
				if #layout.beds >= want then
					break
				end
				local col, row = k % 2, k // 2
				local lx = r[1] + (r[2] - r[1]) * (0.25 + 0.5 * col)
				local lz = r[3] + (r[4] - r[3]) * ((row + 0.5) / rows * 0.7 + 0.1)
				local p = world(lx, lz)
				table.insert(layout.beds, {
					index = #layout.beds + 1,
					x = p[1],
					z = p[2],
					ward = ward.room.id,
					door = ward.door,
				})
			end
		end
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

-- pathIn: door -> reception -> the ward's door -> the bed.
function HospitalLayout.pathIn(layout: Layout, bed: Bed): { { number } }
	return {
		{ layout.entrance[1], layout.entrance[2] },
		{ layout.reception[1], layout.reception[2] },
		{ bed.door[1], bed.door[2] },
		{ bed.x, bed.z },
	}
end

-- pathOut: the bed -> the ward's door -> reception -> the door -> outside.
function HospitalLayout.pathOut(layout: Layout, bed: Bed): { { number } }
	return {
		{ bed.door[1], bed.door[2] },
		{ layout.reception[1], layout.reception[2] },
		{ layout.entrance[1], layout.entrance[2] },
		{ layout.outside[1], layout.outside[2] },
	}
end

return HospitalLayout
