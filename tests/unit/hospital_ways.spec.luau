--!strict
-- The hospital sequence against the furnished hospital (the interiors work, 2026-11-11). Staff, patients
-- and the cots the server stands in the wards are kinematic: nothing stops them at a desk or a bed, so a
-- station or a way that crosses furniture is a person standing in it or walking through it. This spec
-- holds the two sides together on the real town: the places and lanes of Infection/HospitalLayout (what
-- the server walks) against the boxes of everything the bake puts in the hospital's rooms (what
-- WorldGen/Builders/Programme and Furnish build), and the police station's indoor round
-- (Actors/StaffRounds) against the station's rooms.
local Bake = require("@worldgen/Bake")
local Geometry = require("@worldgen/Geometry")
local Data = require("@shared/Data")
local Tunables = require("@shared/Config/Tunables")
local HospitalLayout = require("@shared/Infection/HospitalLayout")
local StaffRounds = require("@shared/Actors/StaffRounds")

local BODY = 1.0 -- studs: the radius of the body that walks the ways (Furnish.BODY, InteriorCheck.BODY)
local HEAD = 6.5 -- studs above the floor: what hangs higher is over a walker's head
local STEP = 0.25 -- studs between the points checked along a way

type Box = { name: string, x0: number, x1: number, z0: number, z1: number }

return function(t)
	local plans = Bake.plans(Bake.data())
	local data = Data.default()
	local layout = HospitalLayout.fromData(data, Tunables.get("hospital.beds")) :: HospitalLayout.Layout

	local function planOf(id: string): any
		for _, p in plans do
			if p.kind == "lot" and p.id == id then
				return p
			end
		end
		error(`no baked lot {id}`)
	end

	-- Everything a walker would walk into in a baked building: each piece of furniture as one box round
	-- all its parts (a ward bed with its curtain rail, a desk with its chair), the stations and shelves,
	-- and the walls. Rugs and whatever hangs over head height are left out; door leaves never collide
	-- and swing clear (worldgen_enter.spec).
	local function solids(p: any): ({ Box }, { Box }, { Box })
		local floorTop = 0
		for _, s in p.parts do
			if s.name == "Floor" then
				floorTop = s.cy + s.sy / 2
			end
		end
		local furniture: { Box } = {}
		local walls: { Box } = {}
		local rooms: { Box } = {}
		for _, r in p.parts do
			local a: any = r.attrs or {}
			if a.Kit or r.role == "Station" or r.role == "Shelf" then
				local x0, x1, y0, y1, z0, z1 = Geometry.aabb(r)
				local prefix = r.name .. "_"
				for _, s in p.parts do
					if string.sub(s.name, 1, #prefix) == prefix then
						local a0, a1, b0, b1, c0, c1 = Geometry.aabb(s)
						x0, x1 = math.min(x0, a0), math.max(x1, a1)
						y0, y1 = math.min(y0, b0), math.max(y1, b1)
						z0, z1 = math.min(z0, c0), math.max(z1, c1)
					end
				end
				if y1 - floorTop > 0.35 and y0 - floorTop < HEAD then
					table.insert(furniture, { name = r.name, x0 = x0, x1 = x1, z0 = z0, z1 = z1 })
				end
			elseif r.role == "Wall" and r.canCollide then
				local x0, x1, y0, _, z0, z1 = Geometry.aabb(r)
				-- (the piece of wall over a doorway is above a walker's head)
				if y0 - floorTop < HEAD - 1.5 then
					table.insert(walls, { name = r.name, x0 = x0, x1 = x1, z0 = z0, z1 = z1 })
				end
			elseif r.role == "Room" and a.Exterior ~= true then
				local x0, x1, _, _, z0, z1 = Geometry.aabb(r)
				table.insert(rooms, { name = a.RoomId, x0 = x0, x1 = x1, z0 = z0, z1 = z1 })
			end
		end
		return furniture, walls, rooms
	end

	-- the nearest box to a point within `r` (flat distance), or nil
	local function near(boxes: { Box }, x: number, z: number, r: number): string?
		for _, b in boxes do
			local dx = math.max(b.x0 - x, 0, x - b.x1)
			local dz = math.max(b.z0 - z, 0, z - b.z1)
			if dx * dx + dz * dz < r * r then
				return b.name
			end
		end
		return nil
	end
	-- what a body walking a straight leg would touch
	local function legHit(boxes: { Box }, a: { number }, b: { number }, r: number): string?
		local len = math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		local n = math.max(1, math.ceil(len / STEP))
		for i = 0, n do
			local f = i / n
			local hit = near(boxes, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, r)
			if hit then
				return hit
			end
		end
		return nil
	end

	local hospital = planOf("hospital_main")
	local furniture, walls, rooms = solids(hospital)

	local function roomAt(x: number, z: number): string?
		for _, r in rooms do
			if x > r.x0 and x < r.x1 and z > r.z0 and z < r.z1 then
				return r.name
			end
		end
		return nil
	end
	-- a way, leg by leg: nothing of the furniture within a body's radius, no wall within half of one
	-- (a doorway is a body and a half wide at the least)
	local function wayClear(points: { { number } }, what: string): number
		local len = 0
		for i = 2, #points do
			local a, b = points[i - 1], points[i]
			local hit = legHit(furniture, a, b, BODY - 0.05)
			t.eq(hit, nil, `{what}: leg {i - 1} ({a[1]}, {a[2]}) -> ({b[1]}, {b[2]}) crosses {hit}`)
			local wall = legHit(walls, a, b, BODY / 2)
			t.eq(wall, nil, `{what}: leg {i - 1} ({a[1]}, {a[2]}) -> ({b[1]}, {b[2]}) crosses the wall {wall}`)
			len += math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2)
		end
		return len
	end

	t.test("the bake and the server agree on the beds; the hospital is furnished round the layout", function()
		t.eq(HospitalLayout.BEDS, Tunables.get("hospital.beds"), "the bake keeps room for the beds the server uses")
		t.eq(#layout.beds, HospitalLayout.BEDS)
		t.truthy(#furniture > 60, `{#furniture} pieces in the hospital`)
		t.truthy(#walls > 20 and #rooms >= 8, `{#walls} walls, {#rooms} rooms`)
		t.truthy(#layout.lanes > 20, `{#layout.lanes} lanes`)
		t.truthy(#layout.posts >= 3, `{#layout.posts} posts`)
		print(`      {#furniture} pieces, {#walls} walls, {#layout.lanes} lanes, {#layout.posts} posts`)
	end)

	t.test("stations: the check-in spot, the intake and every bed stand clear of the furniture", function()
		t.eq(roomAt(layout.reception[1], layout.reception[2]), "reception")
		t.eq(roomAt(layout.intake[1], layout.intake[2]), "triage")
		for _, spot in { { "reception", layout.reception }, { "intake", layout.intake } } do
			local name, p = spot[1] :: string, spot[2] :: { number }
			t.eq(near(furniture, p[1], p[2], BODY + 0.5), nil, `{name}: furniture where people stand`)
			t.eq(near(walls, p[1], p[2], BODY + 0.5), nil, `{name}: a wall where people stand`)
		end
		-- the check-in spot is at the desk, not across the room from it
		local desk: Box? = nil
		for _, b in furniture do
			if b.name == "Station_reception_desk" then
				desk = b
			end
		end
		t.truthy(desk ~= nil, "the reception desk is baked")
		if desk then
			local dx = math.max(desk.x0 - layout.reception[1], 0, layout.reception[1] - desk.x1)
			local dz = math.max(desk.z0 - layout.reception[2], 0, layout.reception[2] - desk.z1)
			t.truthy(dx < 0.5 and dz > BODY and dz < 8, `the check-in spot is {dz} st from the desk`)
			-- on the door's side of the desk
			t.truthy(
				math.abs(layout.entrance[2] - layout.reception[2])
					< math.abs(layout.entrance[2] - (desk.z0 + desk.z1) / 2),
				"people check in on the door's side of the desk"
			)
		end
		-- the cot the server stands at each bed (Hospital/HospitalProps: along the hospital's depth)
		local bed = HospitalLayout.BED
		local fx, fz = math.abs(math.sin(layout.yaw)), math.abs(math.cos(layout.yaw))
		local hx = (bed.width * fz + bed.length * fx) / 2
		local hz = (bed.width * fx + bed.length * fz) / 2
		for i, b in layout.beds do
			t.eq(roomAt(b.x, b.z), b.ward, `bed {i} is in its ward`)
			for _, f in furniture do
				local over = math.min(f.x1, b.x + hx) - math.max(f.x0, b.x - hx) > 0.05
					and math.min(f.z1, b.z + hz) - math.max(f.z0, b.z - hz) > 0.05
				t.truthy(not over, `the cot at bed {i} stands in {f.name}`)
			end
			t.eq(roomAt(b.foot[1], b.foot[2]), b.ward, `bed {i}: the foot of the bed is in the ward`)
			t.eq(near(furniture, b.foot[1], b.foot[2], BODY), nil, `bed {i}: furniture at the foot of the bed`)
		end
	end)

	t.test("lanes and posts: nothing stands in a lane or on a staff round, and no lane crosses a wall", function()
		local total = 0
		for i, l in layout.lanes do
			total += wayClear({ { l[1], l[2] }, { l[3], l[4] } }, `lane {i}`)
		end
		for _, post in layout.posts do
			t.truthy(#post.points >= 2, `{post.id}: a round has somewhere to go`)
			local round = table.clone(post.points)
			table.insert(round, post.points[1]) -- and back to the start
			wayClear(round, `post {post.id}`)
			for _, p in post.points do
				t.eq(roomAt(p[1], p[2]), post.room, `post {post.id} is in {post.room}`)
			end
		end
		print(`      {string.format("%.0f", total)} st of lanes`)
		-- the check has teeth: a chair set down in the middle of a lane is found, and so is a leg
		-- that cuts through the front wall beside the door
		local l = layout.lanes[#layout.lanes]
		local mx, mz = (l[1] + l[3]) / 2, (l[2] + l[4]) / 2
		local chair: { Box } = { { name = "chair", x0 = mx - 0.8, x1 = mx + 0.8, z0 = mz - 0.8, z1 = mz + 0.8 } }
		t.eq(legHit(chair, { l[1], l[2] }, { l[3], l[4] }, BODY), "chair")
		local o, e = layout.outside, layout.entrance
		t.truthy(
			legHit(walls, { o[1] + 12, o[2] }, { e[1] + 12, e[2] + (e[2] - o[2]) }, BODY / 2) ~= nil,
			"a wall is a wall"
		)
	end)

	t.test("walks: door to bed, bed to door, staff to their posts and back, all along clear floor", function()
		local walks = 0
		for i, bed in layout.beds do
			local inn = HospitalLayout.pathIn(layout, bed)
			t.deepEq(inn[1], layout.entrance)
			t.deepEq(inn[#inn], { bed.x, bed.z })
			wayClear(inn, `in to bed {i}`)
			local out = HospitalLayout.pathOut(layout, bed)
			t.deepEq(out[#out], layout.outside)
			table.insert(out, 1, { bed.x, bed.z })
			wayClear(out, `out from bed {i}`)
			-- a patient who is already inside (the check-in spot, the intake) walks to the bed
			for _, from in { layout.reception, layout.intake } do
				local way = HospitalLayout.walk(layout, from[1], from[2], bed.x, bed.z)
				table.insert(way, 1, { from[1], from[2] })
				wayClear(way, `to bed {i} from ({from[1]}, {from[2]})`)
			end
			-- the hospital's own people: from a bed back to their post, and from the door to it
			for _, post in layout.posts do
				local p = post.points[1]
				local back = HospitalLayout.walk(layout, bed.x, bed.z, p[1], p[2])
				table.insert(back, 1, { bed.x, bed.z })
				wayClear(back, `bed {i} to post {post.id}`)
				walks += 1
			end
			walks += 4
		end
		for _, post in layout.posts do
			for k, p in post.points do
				local way = HospitalLayout.walk(layout, layout.entrance[1], layout.entrance[2], p[1], p[2])
				table.insert(way, 1, layout.entrance)
				wayClear(way, `door to post {post.id} point {k}`)
				local toDesk = HospitalLayout.walk(layout, p[1], p[2], layout.reception[1], layout.reception[2])
				table.insert(toDesk, 1, p)
				wayClear(toDesk, `post {post.id} point {k} to the check-in spot`)
				walks += 2
			end
		end
		-- a walk between two points of one lane is the straight leg; a walk to where one stands is empty
		local l = layout.lanes[1]
		t.eq(#HospitalLayout.walk(layout, l[1], l[2], l[3], l[4]), 1)
		t.eq(#HospitalLayout.walk(layout, l[1], l[2], l[1], l[2]), 0)
		print(`      {walks} walks checked`)
	end)

	t.test("police station: the indoor staff's round is in the locker room, clear of what stands there", function()
		local station = planOf("west_police_station")
		local pieces, stationWalls, stationRooms = solids(station)
		t.truthy(#pieces > 20, `{#pieces} pieces in the station`)
		local lot = data:lot("west_police_station")
		local sx, sz = lot.x + StaffRounds.POLICE.x, lot.z + StaffRounds.POLICE.z
		local cx, cz, r = StaffRounds.bounds(sx, sz)
		for index = 1, 4 do
			local round = StaffRounds.points(sx, sz, index)
			table.insert(round, round[1])
			for i = 2, #round do
				local a, b = round[i - 1], round[i]
				t.truthy((a[1] - cx) ^ 2 + (a[2] - cz) ^ 2 <= r * r + 1e-6, "bounds holds the round")
				local hit = legHit(pieces, a, b, BODY - 0.05)
				t.eq(hit, nil, `staff {index}: leg {i - 1} crosses {hit}`)
				local wall = legHit(stationWalls, a, b, BODY / 2)
				t.eq(wall, nil, `staff {index}: leg {i - 1} crosses the wall {wall}`)
				local inRoom = false
				for _, room in stationRooms do
					if a[1] > room.x0 and a[1] < room.x1 and a[2] > room.z0 and a[2] < room.z1 then
						inRoom = true
					end
				end
				t.truthy(inRoom, `staff {index}: point {i - 1} is in no room`)
			end
		end
	end)
end
