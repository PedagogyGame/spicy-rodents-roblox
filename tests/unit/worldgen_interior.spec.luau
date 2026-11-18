--!strict
-- WorldGen interiors (the interiors art pass: Builders/Furniture, Builders/Furnish, InteriorCheck).
-- Library: every piece is human scale, stands on the floor (or hangs on the wall), keeps inside its
-- declared box, has uniform balls and round cylinders, and no two of its faces share a plane.
-- Layout: deterministic; furniture never enters a doorway; a body can always walk from the door to
-- everything; what does not fit is skipped. Town: all six enterable buildings pass InteriorCheck (rooms
-- furnished for their purpose, doorways and paths clear, nothing floating or buried, a light per room),
-- and the check itself catches a table in a doorway, a missing sofa, a floating bed and a dark room.
local roblox = require("@lune/roblox")
local Bake = require("@worldgen/Bake")
local Coplanar = require("@worldgen/Coplanar")
local Factory = require("@worldgen/Factory")
local Furnish = require("@worldgen/Builders/Furnish")
local Furniture = require("@worldgen/Builders/Furniture")
local Geometry = require("@worldgen/Geometry")
local InteriorCheck = require("@worldgen/InteriorCheck")
local Spec = require("@worldgen/Spec")

local ORIGIN = Geometry.frame(0, 0, 0, 0)

return function(t)
	local data = Bake.data()
	local plans = Bake.plans(data)
	local shells: { any } = {}
	local byId: { [string]: any } = {}
	for _, p in plans do
		if p.kind == "lot" and p.attributes.Enterable == true then
			table.insert(shells, p)
			byId[p.id] = p
		end
	end
	local T = Furniture.TONES.bungalow

	t.test("library: every piece is human scale, sits on the floor or hangs on the wall, inside its own box", function()
		t.truthy(#Furniture.KINDS >= 30, `{#Furniture.KINDS} kinds`)
		for _, kind in Furniture.KINDS do
			for _, variant in { 0, 1 } do
				local p = Furniture.piece(kind, T, { variant = variant })
				t.eq(p.kind, kind)
				t.truthy(p.w >= 1 and p.w <= 18 and p.d >= 0.2 and p.d <= 9 and p.h >= 0.1 and p.h <= 17, `{kind} size`)
				local low, high = math.huge, -math.huge
				for i, d in p.parts do
					local hx, hz = d.sx / 2, d.sz / 2
					if d.shape == "Cylinder" then
						t.near(d.sy, d.sz, 1e-9, `{kind}.{d.n} is a round cylinder`)
						if d.roll then
							hx, hz = d.sy / 2, d.sz / 2 -- upright: its footprint is its diameter
						elseif d.yaw then
							hx, hz = d.sz / 2, d.sx / 2 -- lying along the depth
						end
					elseif d.shape == "Ball" then
						t.truthy(d.sx == d.sy and d.sy == d.sz, `{kind}.{d.n} is a uniform ball`)
					end
					local up = if d.shape == "Cylinder" and d.roll then d.sx / 2 else d.sy / 2
					low, high = math.min(low, d.y - up), math.max(high, d.y + up)
					t.truthy(math.abs(d.x) + hx <= p.w / 2 + 0.06, `{kind}.{d.n} inside the width`)
					t.truthy(math.abs(d.z) + hz <= p.d / 2 + 0.06, `{kind}.{d.n} inside the depth`)
					t.truthy(i == 1 or d.n ~= "", `{kind}: only the root is unnamed`)
				end
				t.truthy(high <= p.h + 0.02, `{kind} is {high} tall, declared {p.h}`)
				if p.mounted then
					t.near(low, p.mounted, 0.02, `{kind} hangs at its declared height`)
					t.truthy(p.mounted >= 2, `{kind} hangs clear of the floor`)
					t.eq(p.solid, false, `{kind}: hung pieces do not collide`)
				elseif kind == "rug" then
					t.near(low, 0.05, 1e-9, "a rug lies on the floor finish")
				else
					t.near(low, 0, 1e-9, `{kind} stands on the floor`)
				end
			end
		end
		-- the scale: a person stands 5.5 st
		t.truthy(Furniture.piece("sofa", T).w <= 8 and Furniture.piece("sofa", T).h <= 3.2, "sofa")
		t.truthy(Furniture.piece("bed", T).d <= 8 and Furniture.piece("bed", T).w <= 7, "bed")
		t.truthy(Furniture.piece("wardrobe", T).h <= 8, "wardrobe under the ceiling")
		t.truthy(Furniture.piece("bookshelf", T).h <= Furnish.CEILING - 2, "a squirrel fits on the shelf top")
	end)

	t.test("library: emitted pieces have one named root, quiet details, and no faces sharing a plane", function()
		for _, kind in Furniture.KINDS do
			for turns = 0, 3 do
				local list = Spec.list()
				local p = Furniture.piece(kind, T)
				local root = Furniture.emit(list, ORIGIN, "Thing", p, 10, -4, turns, 2, { Room = "r" })
				t.eq(root.name, "Thing")
				t.eq(root.attrs.Kit, kind)
				t.eq(root.attrs.Room, "r")
				t.eq(root.canCollide, p.solid, kind)
				local fw, fd = Furniture.footprint(p, turns)
				for i, s in list.parts do
					if i > 1 then
						t.eq(string.sub(s.name, 1, 6), "Thing_", s.name)
						t.eq(s.canQuery, false, `{kind}.{s.name} takes no queries`)
						if s.canCollide then
							t.eq(s.attrs.Part, "Thing", `{kind}.{s.name}: a solid detail names its piece`)
						end
					end
					local x0, x1, y0, _, z0, z1 = Geometry.aabb(s)
					t.truthy(
						x0 >= 10 - fw / 2 - 0.06 and x1 <= 10 + fw / 2 + 0.06,
						`{kind} turn {turns}: {s.name} in x`
					)
					t.truthy(
						z0 >= -4 - fd / 2 - 0.06 and z1 <= -4 + fd / 2 + 0.06,
						`{kind} turn {turns}: {s.name} in z`
					)
					t.truthy(y0 >= 2 - 1e-9, `{kind}: {s.name} under the floor`)
				end
				-- on a floor, as in a room (the floor hides what rests on it)
				local onFloor = table.clone(list.parts)
				table.insert(onFloor, {
					name = "Floor",
					cx = 10,
					cy = 1.5,
					cz = -4,
					yaw = 0,
					pitch = 0,
					sx = 40,
					sy = 1,
					sz = 40,
					color = { 1, 1, 1 },
					material = "Concrete",
					canCollide = true,
					transparency = 0,
				})
				local clashes = Coplanar.clashes(onFloor)
				t.eq(
					#clashes,
					0,
					`{kind} turn {turns}: {if clashes[1] then clashes[1].a .. "/" .. clashes[1].b else ""}`
				)
			end
		end
		-- the back of a piece looks at the wall it stands on
		local bx, bz = Furniture.backDir(0)
		t.eq(bx, 0)
		t.eq(bz, 1)
		local list = Spec.list()
		Furniture.emit(list, ORIGIN, "S", Furniture.piece("sofa", T), 0, 0, 1, 0)
		local back
		for _, s in list.parts do
			if s.name == "S_Back" then
				back = s
			end
		end
		t.truthy(back.cx > 1, "a sofa turned once has its back toward +x")
		-- station and shelf dressing
		for _, kind in { "desk", "console", "board", "shelf" } do
			local parts = Furniture.dress(kind, T, { w = 17.5, seats = 3 })
			t.truthy(#parts >= 4, kind)
			local dl = Spec.list()
			dl:add(
				ORIGIN,
				"Station_x",
				0,
				1.5,
				0,
				if kind == "shelf" then 17.5 else 6,
				if kind == "shelf" then 6.6 else 3,
				if kind == "shelf" then 1.5 else 2.5,
				{}
			)
			if kind == "shelf" then
				dl.parts[1].cy = 3.3
			end
			Furniture.emitDress(dl, ORIGIN, "Station_x", parts, 0, 0, 0, 0)
			t.eq(#Coplanar.clashes(dl.parts), 0, kind .. " dressing")
			for i, s in dl.parts do
				if i > 1 then
					t.eq(s.canCollide, false)
				end
			end
		end
	end)

	local function room(w: number, d: number): any
		return {
			id = "r",
			kind = "living",
			x0 = 0,
			x1 = w,
			z0 = 0,
			z1 = d,
			doors = {},
			windows = {},
			pins = {},
			discs = {},
		}
	end

	t.test("layout: deterministic; pieces stand off the doorways; the room stays walkable", function()
		local function make(): any
			local r = room(24, 20)
			r.doors = { { id = "a", x = 12, z = 0, w = 5, wall = 3 }, { id = "b", x = 24, z = 12, w = 5, wall = 2 } }
			r.windows = { { wall = 1, c = 6, w = 3.6, h = 4.8, y = 5 } }
			return r
		end
		local a = Furnish.layout(make(), Furnish.RECIPES.living, T)
		local b = Furnish.layout(make(), Furnish.RECIPES.living, T)
		t.eq(#a.placed, #b.placed)
		for i, p in a.placed do
			t.eq(p.name, b.placed[i].name)
			t.eq(p.x, b.placed[i].x)
			t.eq(p.z, b.placed[i].z)
			t.eq(p.q, b.placed[i].q)
		end
		t.eq(#a.unreached, 0)
		local kinds: { [string]: any } = {}
		for _, p in a.placed do
			kinds[p.kind] = p
			if p.piece and not p.piece.mounted and p.kind ~= "rug" then
				-- off the doorways: the door's width, 5 st into the room
				t.truthy(not (p.x + p.hx > 9.5 and p.x - p.hx < 14.5 and p.z - p.hz < 5), `{p.name} in doorway a`)
				t.truthy(not (p.z + p.hz > 9.5 and p.z - p.hz < 14.5 and p.x + p.hx > 19), `{p.name} in doorway b`)
				-- inside the room, off the walls
				t.truthy(
					p.x - p.hx >= 0.19 and p.x + p.hx <= 23.81 and p.z - p.hz >= 0.19 and p.z + p.hz <= 19.81,
					p.name
				)
			end
		end
		for _, k in { "sofa", "armchair", "coffee_table", "rug", "tv_stand", "bookshelf", "floor_lamp" } do
			t.truthy(kinds[k], "living room has a " .. k)
		end
		-- the tall bookshelf is not across the window; the sofa's back is to its wall; the TV faces it
		local shelf = kinds.bookshelf
		t.truthy(not (shelf.wall == 1 and math.abs(shelf.along - 6) < 2.2 + 1.8 + 0.9), "bookshelf across the window")
		local sofa, tv = kinds.sofa, kinds.tv_stand
		t.truthy(
			sofa.wall ~= nil and tv.wall ~= nil and (sofa.wall - tv.wall) % 4 == 2,
			"the TV stands on the wall the sofa faces"
		)
		-- no two floor pieces overlap
		for i, p in a.placed do
			for j = i + 1, #a.placed do
				local o = a.placed[j]
				local floorP = p.piece and not p.piece.mounted and p.kind ~= "rug"
				local floorO = o.piece and not o.piece.mounted and o.kind ~= "rug"
				if floorP and floorO then
					local ox = math.min(p.x + p.hx, o.x + o.hx) - math.max(p.x - p.hx, o.x - o.hx)
					local oz = math.min(p.z + p.hz, o.z + o.hz) - math.max(p.z - p.hz, o.z - o.hz)
					t.truthy(not (ox > 0.01 and oz > 0.01), `{p.name} and {o.name} overlap`)
				end
			end
		end
	end)

	t.test(
		"layout: a room that is all doorway gets nothing in the way; a tight room skips what does not fit",
		function()
			-- a 7 st square cell with a door in every wall: every stretch of wall is a doorway
			local r = room(7, 7)
			r.doors = {
				{ id = "n", x = 3.5, z = 7, w = 5, wall = 1 },
				{ id = "e", x = 7, z = 3.5, w = 5, wall = 2 },
				{ id = "s", x = 3.5, z = 0, w = 5, wall = 3 },
				{ id = "w", x = 0, z = 3.5, w = 5, wall = 4 },
			}
			local res = Furnish.layout(r, Furnish.RECIPES.living, T)
			for _, p in res.placed do
				t.truthy(
					p.kind == "rug" or (p.piece and p.piece.mounted),
					`{p.name} stands in a room that is all doorway`
				)
			end
			t.truthy(#res.skipped >= 6, `{#res.skipped} pieces skipped`)
			t.eq(#res.unreached, 0)
			-- a corridor 5 st wide: a sofa along a wall would leave no way past a body, so nothing may close it
			local c = room(5, 30)
			c.doors = { { id = "a", x = 2.5, z = 0, w = 4, wall = 3 }, { id = "b", x = 2.5, z = 30, w = 4, wall = 1 } }
			local cres =
				Furnish.layout(c, { { kind = "dining_set", pref = "centre" }, { kind = "sofa", pref = "A" } }, T)
			for _, p in cres.placed do
				t.truthy(p.kind ~= "dining_set", "a table for four across a 5 st corridor")
			end
			t.eq(#cres.unreached, 0)
			-- a pinned piece on its template spot stays there; in a doorway it is moved out of it
			local pin = room(24, 20)
			pin.doors = { { id = "a", x = 12, z = 0, w = 5, wall = 3 } }
			pin.pins = { { id = "Furniture_bed", kind = "bed", x = 6, z = 17, hide = "under" } }
			local pres = Furnish.layout(pin, {}, T)
			t.near(pres.placed[1].x, 6, 0.26)
			t.near(pres.placed[1].z, 20 - 0.2 - 3.9, 1e-6, "flush to the back wall")
			t.eq(pres.placed[1].hide, "under")
			pin.pins = { { id = "Furniture_bed", kind = "bed", x = 12, z = 2, hide = "under" } }
			local moved = Furnish.layout(pin, {}, T).placed[1]
			t.truthy(moved ~= nil, "the bed is still placed")
			t.truthy(
				not (moved.x + moved.hx > 9.5 and moved.x - moved.hx < 14.5 and moved.z - moved.hz < 5),
				"moved out of the doorway"
			)
		end
	)

	t.test("town: all six enterable buildings pass the interior check", function()
		t.eq(#shells, 6)
		local r = InteriorCheck.run(plans)
		print(`      {r.lots} buildings, {r.rooms} rooms, {r.pieces} pieces, {r.lights} lights`)
		t.eq(table.concat(r.failures, " | ", 1, math.min(#r.failures, 8)), "", `{#r.failures} interior failures`)
		t.eq(r.lots, 6)
		t.eq(r.rooms, 19 + 8 + 4)
		t.truthy(r.pieces >= 280, `{r.pieces} pieces`)
		t.truthy(r.lights >= 19 + 20 + 6, `{r.lights} lights`)
		for _, p in shells do
			t.eq(p.attributes.FurnishUnreached, 0, p.id)
			-- nothing the room is for was left out
			local skipped: string = p.attributes.FurnishSkipped
			for kind, rules in InteriorCheck.REQUIRED do
				for _, rule in rules do
					if rule.kit then
						t.truthy(
							not string.find(skipped, kind .. "." .. rule.kit, 1, true),
							`{p.id} skipped {kind}.{rule.kit}`
						)
					end
				end
			end
		end
	end)

	t.test(
		"town: what is in the rooms (the owner's list), template pieces, per-room floors, lights, curtains",
		function()
			local function kits(p: any, roomId: string): { [string]: number }
				local out: { [string]: number } = {}
				for _, s in p.parts do
					if s.attrs and s.attrs.Kit and s.attrs.Room == roomId then
						out[s.attrs.Kit] = (out[s.attrs.Kit] or 0) + (s.attrs.Seats or s.attrs.Lockers or 1)
					end
				end
				return out
			end
			local function named(p: any, name: string): any
				for _, s in p.parts do
					if s.name == name then
						return s
					end
				end
				return nil
			end
			local materials: { [string]: boolean } = {}
			for _, id in
				{ "core_house_0_victorian", "core_house_1_bungalow", "core_house_2_brick", "core_house_3_blue_cottage" }
			do
				local p = byId[id]
				local living, kitchen, bedroom = kits(p, "living"), kits(p, "kitchen"), kits(p, "bedroom")
				for _, k in { "sofa", "armchair", "coffee_table", "rug", "tv_stand", "bookshelf", "floor_lamp" } do
					t.truthy(living[k], `{id} living room: {k}`)
				end
				for _, k in { "counter_run", "fridge", "dining_set" } do
					t.truthy(kitchen[k], `{id} kitchen: {k}`)
				end
				t.truthy(kitchen.dining_set >= 4, `{id}: chairs at the kitchen table`)
				for _, k in { "bed", "nightstand", "wardrobe", "rug" } do
					t.truthy(bedroom[k], `{id} bedroom: {k}`)
				end
				-- the template's own pieces keep their names, hide types and a hide spot in the room graph
				local sofa, bed = named(p, "Furniture_sofa"), named(p, "Furniture_bed")
				t.eq(sofa.attrs.HideType, "behind", id)
				t.eq(bed.attrs.HideType, "under", id)
				t.eq(sofa.role, "Furniture")
				t.truthy(
					named(p, "Furniture_bed_Pillow1") and named(p, "Furniture_bed_Blanket"),
					`{id}: pillow and blanket`
				)
				t.truthy(named(p, "Furniture_counter_Sink") and named(p, "Furniture_counter_Hob"), `{id}: sink and hob`)
				t.truthy(named(p, "Furniture_wardrobe").attrs.HideType == "inside", id)
				local hides = 0
				for _, e in p.extras do
					if e.kind == "Attachment" and e.attrs and e.attrs.HideType then
						hides += 1
						-- behind the sofa means behind it: off the piece, on the side of its back
						if e.name == "Hide_sofa" then
							local nav = named(p, "Nav")
							local wx, _, wz =
								Geometry.point(Geometry.frame(nav.cx, 0, nav.cz, nav.yaw), e.offset[1], 0, e.offset[3])
							local x0, x1, _, _, z0, z1 = Geometry.aabb(sofa)
							t.truthy(
								wx < x0 or wx > x1 or wz < z0 or wz > z1,
								`{id}: the hide spot is behind the sofa, not in it`
							)
						end
					end
				end
				t.truthy(hides >= 3, `{id} hides {hides}`)
				-- floors, walls, ceiling, lights, curtains
				local curtains, rails, pictures, liners, skirts = 0, 0, 0, 0, 0
				for _, s in p.parts do
					if string.sub(s.name, 1, 7) == "Finish_" then
						materials[s.material] = true
						t.eq(s.canCollide, false, s.name)
						t.eq(s.canQuery, false, s.name) -- a body stands on the structural floor under it
					elseif string.sub(s.name, 1, 8) == "Curtain_" then
						curtains += 1
					elseif string.sub(s.name, 1, 12) == "CurtainRail_" then
						rails += 1
						t.eq(s.shape, "Cylinder")
					elseif s.attrs and s.attrs.Kit == "picture" then
						pictures += 1
					elseif string.sub(s.name, 1, 6) == "Liner_" then
						liners += 1
					elseif string.sub(s.name, 1, 6) == "Skirt_" then
						skirts += 1
					end
				end
				t.truthy(curtains >= 8 and rails * 2 == curtains, `{id}: {curtains} curtains on {rails} rails`)
				t.truthy(pictures >= 4, `{id}: {pictures} pictures`)
				t.truthy(liners >= 20 and skirts >= 16, `{id}: {liners} wall linings, {skirts} skirting boards`)
				-- the living room keeps a curtain rail (the template's squirrel route socket)
				local livingRail = false
				for _, s in p.parts do
					livingRail = livingRail or string.sub(s.name, 1, 19) == "CurtainRail_living_"
				end
				t.truthy(livingRail, `{id}: a curtain rail in the living room`)
				local ceiling = named(p, "Ceiling")
				t.eq(ceiling.role, "Ceiling")
				t.eq(ceiling.canCollide, true)
				local floor = named(p, "Floor")
				t.near(ceiling.cy - ceiling.sy / 2 - (floor.cy + floor.sy / 2), Furnish.CEILING, 1e-6, id)
				t.eq(p.parts[1].name, "Floor")
				-- one lit pendant per room, tagged for the night lighting
				local lights = 0
				for _, e in p.extras do
					if e.kind == "PointLight" then
						lights += 1
						local host = named(p, e.part)
						t.eq(host.attrs.NightLight, true, e.part)
						t.eq(e.shadows == true, false)
						t.truthy(e.range >= 10 and e.range <= 18, `{e.part} range {e.range}`)
					end
				end
				t.eq(lights, p.attributes.RoomLights, id)
			end
			t.truthy(
				materials.WoodPlanks and materials.CeramicTiles and materials.Carpet,
				"wood, tile and carpet floors"
			)
			-- the bungalow's bathroom
			local bath = kits(byId.core_house_1_bungalow, "bath")
			t.truthy(bath.bathtub and bath.toilet and bath.basin and bath.mirror, "bathroom")
			-- hospital
			local h = byId.hospital_main
			t.truthy(kits(h, "reception").waiting_row >= 8, "waiting chairs")
			for _, ward in { "ward_a", "ward_b" } do
				t.truthy(kits(h, ward).ward_bed >= 6, ward .. " beds")
			end
			local curtains, cabinets = 0, 0
			for _, s in h.parts do
				if string.match(s.name, "^Furniture_ward_[ab]_ward_bed%d*_Curtain$") then
					curtains += 1
				elseif s.attrs and s.attrs.Kit == "medicine_cabinet" then
					cabinets += 1
				end
			end
			t.truthy(curtains >= 12, `{curtains} ward curtains`)
			t.truthy(cabinets >= 3, `{cabinets} medicine cabinets`)
			t.truthy(kits(h, "triage").treatment_bay >= 2, "treatment bays")
			t.truthy(
				named(h, "Station_reception_desk_Top") and named(h, "Station_reception_desk_Apron"),
				"reception desk"
			)
			t.truthy(named(h, "Shelf_rx_1_Board1"), "pharmacy shelving")
			-- stations and shelves are exactly where and what they were (the hospital track depends on them)
			local desk = named(h, "Station_reception_desk")
			t.eq(desk.sx, 6)
			t.eq(desk.sy, 3)
			t.eq(desk.sz, 2.5)
			t.eq(desk.role, "Station")
			local slots = 0
			for _, e in h.extras do
				if e.kind == "Attachment" and e.attrs and e.attrs.ItemSlot then
					slots += 1
				end
			end
			t.eq(slots, 36)
			-- police station
			local s = byId.west_police_station
			t.truthy(named(s, "Station_front_desk_Top"), "front desk")
			t.truthy(kits(s, "back_office").cell >= 1, "holding cell")
			t.truthy(kits(s, "back_office").locker_bank >= 6, "lockers")
			t.truthy(kits(s, "briefing").briefing_row >= 8, "briefing chairs")
			local bars = 0
			for _, part in s.parts do
				if string.match(part.name, "^Furniture_back_office_cell_Bar%d+$") then
					bars += 1
					t.eq(part.shape, "Cylinder")
				end
			end
			t.truthy(bars >= 8, `{bars} cell bars`)
			t.eq(named(s, "Furniture_back_office_cell").transparency, 1) -- the collider behind the bars
			t.eq(named(s, "Furniture_back_office_cell").canCollide, true)
		end
	)

	t.test("InteriorCheck has teeth: a table in a doorway, a missing sofa, a floating bed, a dark room", function()
		local base = byId.core_house_2_brick
		local function copy(mutate: (parts: { any }, extras: { any }) -> ()): { string }
			local parts, extras = {}, {}
			for _, s in base.parts do
				table.insert(parts, table.clone(s))
			end
			for _, e in base.extras do
				table.insert(extras, e)
			end
			mutate(parts, extras)
			local p = table.clone(base)
			p.parts, p.extras = parts, extras
			return InteriorCheck.lot(p).failures
		end
		local function find(parts: { any }, name: string): (any, number)
			for i, s in parts do
				if s.name == name then
					return s, i
				end
			end
			error("no part " .. name)
		end
		t.eq(#copy(function() end), 0, "the baked house is clean")
		-- a table pushed into the doorway between the hall and the living room
		local f = copy(function(parts)
			local door = find(parts, "Door_hall_living")
			local sofa = find(parts, "Furniture_sofa")
			local n = Geometry.rotate({ 0, 0, 1 }, door.yaw, 0, 0)
			-- on the living-room side of the leaf
			local side = if (sofa.cx - door.cx) * n[1] + (sofa.cz - door.cz) * n[3] > 0 then 1 else -1
			local table_ = table.clone(sofa)
			table_.name = "Furniture_rogue"
			table_.attrs = { Kit = "coffee_table", Room = "living" }
			table_.cx, table_.cz = door.cx + n[1] * side * 2, door.cz + n[3] * side * 2
			table_.sx, table_.sz = 3, 3
			table.insert(parts, table_)
		end)
		local text = table.concat(f, " | ")
		t.truthy(string.find(text, "Furniture_rogue stands in the doorway of Door_hall_living", 1, true), text)
		t.truthy(string.find(text, "no way", 1, true) or string.find(text, "is blocked", 1, true), text)
		-- the sofa taken away
		f = copy(function(parts)
			local _, i = find(parts, "Furniture_sofa")
			table.remove(parts, i)
		end)
		t.truthy(string.find(table.concat(f, " | "), "living (living): 0 of 1 sofa", 1, true), table.concat(f, " | "))
		-- the bed lifted a stud
		f = copy(function(parts)
			for _, s in parts do
				if s.name == "Furniture_bed" or string.sub(s.name, 1, 14) == "Furniture_bed_" then
					s.cy += 1
				end
			end
		end)
		t.truthy(string.find(table.concat(f, " | "), "Furniture_bed floats 1.00 st", 1, true), table.concat(f, " | "))
		-- and sunk
		f = copy(function(parts)
			for _, s in parts do
				if s.name == "Furniture_bed" or string.sub(s.name, 1, 14) == "Furniture_bed_" then
					s.cy -= 0.5
				end
			end
		end)
		t.truthy(
			string.find(table.concat(f, " | "), "Furniture_bed is buried 0.50 st", 1, true),
			table.concat(f, " | ")
		)
		-- the bedroom's light unplugged
		f = copy(function(_parts, extras)
			for i, e in extras do
				if e.kind == "PointLight" and e.part == "Light_bedroom" then
					table.remove(extras, i)
					break
				end
			end
		end)
		t.truthy(
			string.find(table.concat(f, " | "), "Light_bedroom has no PointLight", 1, true),
			table.concat(f, " | ")
		)
		-- a wardrobe pushed through a wall, and one standing on another piece
		f = copy(function(parts)
			local w = find(parts, "Furniture_wardrobe")
			local bed = find(parts, "Furniture_bed")
			w.cx, w.cz = bed.cx, bed.cz
		end)
		t.truthy(string.find(table.concat(f, " | "), "overlap", 1, true), table.concat(f, " | "))
	end)

	t.test("Town: room lights survive the .rbxm round trip; LightCount; the hospital's panels glow", function()
		local town = Bake.run(
			data,
			Factory.new({
				Instance = roblox.Instance,
				Vector3 = roblox.Vector3,
				CFrame = roblox.CFrame,
				Color3 = roblox.Color3,
				Enum = roblox.Enum,
				UDim2 = roblox.UDim2,
				ColorSequence = roblox.ColorSequence,
			})
		)
		local back = roblox.deserializeModel(roblox.serializeModel({ town }))[1]
		local lights, tagged = 0, 0
		for _, d in back:GetDescendants() do
			if d:IsA("PointLight") then
				lights += 1
				t.eq(d.Enabled, true)
				t.eq(d.Shadows, false)
				t.truthy(d.Range <= 60 and d.Range >= 10, `range {d.Range}`)
				t.eq(d.Parent:GetAttribute("NightLight"), true, d.Parent.Name)
				t.eq(d.Parent.CanCollide, false)
			elseif d:IsA("BasePart") and d:GetAttribute("NightLight") == true then
				tagged += 1
			end
		end
		t.eq(lights, town:GetAttribute("LightCount"))
		t.truthy(lights >= 45, `{lights} room lights`)
		t.truthy(tagged >= lights + 400, `{tagged} parts glow at night (fixtures and home windows)`)
		local hospital = back:FindFirstChild("Lots"):FindFirstChild("hospital_main")
		t.eq(hospital:FindFirstChild("Light_reception_1").Material, roblox.Enum.Material.Neon)
		t.eq(hospital:GetAttribute("NightLights"), hospital:GetAttribute("RoomLights"))
		local house = back:FindFirstChild("Lots"):FindFirstChild("core_house_2_brick")
		t.truthy(house:FindFirstChild("Light_living"):FindFirstChild("Glow"), "the living room light")
		t.truthy(house:FindFirstChild("Furniture_sofa_Back"), "the sofa's back")
		t.eq(house.PrimaryPart.Name, "Floor")
	end)
end
