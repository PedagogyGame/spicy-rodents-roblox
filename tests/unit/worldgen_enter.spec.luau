--!strict
-- Getting in (the interiors work, 2026-11-11): every exterior door stands on its threshold at ground
-- level or on steps a walking body can take (WorldGen/DoorSill); the buildings people walk into stand
-- on level sites (World/Height.SITES) that match the lot data; a body walks from the ground in front
-- of each building's door into every one of its rooms and out at the back (WorldGen/EnterCheck), and
-- the check catches a solid leaf, a wall with no opening, a tall threshold, a low lintel, furniture in
-- a doorway and ground coming up through the floor; every doorway's leaf is an auto door that never
-- collides, swings clear of the furniture or slides into the wall beside it.
local roblox = require("@lune/roblox")
local Bake = require("@worldgen/Bake")
local DoorSill = require("@worldgen/DoorSill")
local EnterCheck = require("@worldgen/EnterCheck")
local Geometry = require("@worldgen/Geometry")
local Shell = require("@worldgen/Builders/Shell")
local DoorMotion = require("@shared/World/DoorMotion")
local Height = require("@shared/World/Height")

return function(t)
	local data = Bake.data()
	local plans = Bake.plans(data)
	local lots: { [string]: any } = {}
	for _, l in data.lots do
		lots[l.id] = l
	end
	local byId: { [string]: any } = {}
	local shells: { any } = {}
	for _, p in plans do
		byId[p.id] = p
		if p.kind == "lot" and p.attributes.Enterable == true then
			table.insert(shells, p)
		end
	end
	local function find(parts: { any }, name: string): any
		for _, s in parts do
			if s.name == name then
				return s
			end
		end
		error("no part " .. name)
	end
	-- a copy of a baked plan with its parts changed
	local function altered(id: string, mutate: (parts: { any }) -> ()): any
		local base = byId[id]
		local parts = {}
		for _, s in base.parts do
			table.insert(parts, table.clone(s))
		end
		mutate(parts)
		local p = table.clone(base)
		p.parts = parts
		return p
	end
	-- a solid block where a part is: across the doorway of a leaf, `y0` to `y1` above its sill
	local function across(parts: { any }, leafName: string, name: string, y0: number, y1: number, thick: number)
		local leaf = find(parts, leafName)
		local block = table.clone(leaf)
		local sill = leaf.cy - leaf.sy / 2
		block.name, block.role, block.attrs = name, "Wall", nil
		block.canCollide = true
		block.cy, block.sy, block.sz = sill + (y0 + y1) / 2, y1 - y0, thick
		table.insert(parts, block)
	end

	-- a one-building plan with a front door at z = -10 whose sill is `sill` above y = 0
	local function building(sill: number, steps: { { number } }?): any
		local parts: { any } = {
			{ name = "Body", cx = 0, cy = 6, cz = 0, yaw = math.pi, pitch = 0, sx = 20, sy = 12, sz = 20 },
			{
				name = "Door",
				cx = 0,
				cy = sill + 4,
				cz = -10.12,
				yaw = math.pi,
				pitch = 0,
				sx = 6,
				sy = 8,
				sz = 0.5,
				role = "Door",
				attrs = { DoorId = "b:front" },
			},
		}
		-- steps: { top, near edge, far edge } out from the wall
		for k, st in steps or {} do
			table.insert(parts, {
				name = `Door_Step{k}`,
				cx = 0,
				cy = (st[1] - 1) / 2,
				cz = -10 - (st[2] + st[3]) / 2,
				yaw = math.pi,
				pitch = 0,
				sx = 8,
				sy = st[1] + 1,
				sz = st[3] - st[2],
				role = "Step",
				canCollide = true,
			})
		end
		for _, s in parts do
			s.canCollide = if s.canCollide == nil then true else s.canCollide
			s.color, s.material, s.transparency = { 1, 1, 1 }, "Concrete", 0
		end
		return { kind = "lot", id = "b", category = "building", attributes = {}, parts = parts }
	end
	local function flat(y: number): (number, number) -> number
		return function(_x: number, _z: number): number
			return y
		end
	end

	t.test("DoorSill: a level sill passes; a buried door, a door in the air and a tall step are caught", function()
		local r = DoorSill.run({ building(0) }, flat(0))
		t.eq(r.doors, 1)
		t.eq(r.level, 1)
		t.eq(#r.failures, 0, table.concat(r.failures, "; "))
		-- within a threshold's height either way
		t.eq(#DoorSill.run({ building(0.3) }, flat(0)).failures, 0)
		t.eq(#DoorSill.run({ building(0) }, flat(0.3)).failures, 0)
		-- under the grass
		local buried = DoorSill.run({ building(0) }, flat(1.4))
		t.eq(#buried.failures, 1)
		t.truthy(string.find(buried.failures[1], "b/Door: 1.4 st under the ground", 1, true), buried.failures[1])
		-- only one side of the door under the slope is enough
		local slope = DoorSill.run({ building(0) }, function(x: number, _z: number): number
			return if x > 2 then 1 else 0
		end)
		t.eq(#slope.failures, 1)
		-- in the air with nothing to climb
		local air = DoorSill.run({ building(2) }, flat(0))
		t.truthy(string.find(air.failures[1], "above the ground with no steps", 1, true), air.failures[1])
		-- three steps of 0.7 down from a sill 2.1 up
		local stairs =
			DoorSill.run({ building(2.1, { { 2.1, 0, 1.4 }, { 1.4, 1.4, 2.8 }, { 0.7, 2.8, 4.2 } }) }, flat(0))
		t.eq(#stairs.failures, 0, table.concat(stairs.failures, "; "))
		t.eq(stairs.stepped, 1)
		-- a rise no body takes
		local tall = DoorSill.run({ building(2.1, { { 2.1, 0, 1.4 }, { 1.0, 1.4, 2.8 } }) }, flat(0))
		t.truthy(string.find(table.concat(tall.failures, "; "), "step 2 rises 1.10", 1, true), tall.failures[1])
		-- the top step below the sill, and stairs that stop short of the ground
		local low = DoorSill.run({ building(2.1, { { 1.8, 0, 1.4 }, { 1.1, 1.4, 2.8 }, { 0.4, 2.8, 4.2 } }) }, flat(0))
		t.truthy(string.find(table.concat(low.failures, "; "), "top step", 1, true), low.failures[1])
		local short = DoorSill.run({ building(2.1, { { 2.1, 0, 1.4 }, { 1.4, 1.4, 2.8 } }) }, flat(0))
		t.truthy(string.find(table.concat(short.failures, "; "), "bottom step stands 1.40", 1, true), short.failures[1])
	end)

	t.test("town: all 83 exterior doors stand on a threshold at ground level or on steps down to it", function()
		local r = DoorSill.run(plans, Height.at)
		print(`      {r.doors} exterior doors: {r.level} on a level threshold, {r.stepped} on steps`)
		t.eq(r.doors, 83)
		t.eq(table.concat(r.failures, "; "), "")
		t.eq(r.level + r.stepped, r.doors)
		-- the doors that stood under the ground before: the sill is at the ground now, the leaf whole
		local raised = 0
		for _, p in plans do
			if p.kind == "lot" then
				for _, s in p.parts do
					if s.name == "Door" and s.role == "Door" then
						local sill = s.cy - s.sy / 2 - (p.attributes.SeatY :: number)
						t.truthy(sill >= -1e-9, `{p.id}: the sill is under the seat`)
						if sill > 0.01 then
							raised += 1
							t.truthy(s.sy >= 6.5, `{p.id}: a raised door {s.sy} st tall`)
							t.truthy(
								sill + s.sy <= (p.attributes.EaveY :: number) - 0.5,
								`{p.id}: the raised door reaches the eave`
							)
						end
					end
				end
			end
		end
		t.truthy(raised >= 13, `{raised} doors raised to the ground on their uphill side`)
		-- without the level site the hospital's staff exit is under the grass again (the check has teeth
		-- on the real town)
		local natural = DoorSill.run(plans, Height.natural)
		t.truthy(
			string.find(table.concat(natural.failures, "; "), "hospital_main/Door_staff_exit", 1, true),
			"the staff exit on the natural ground"
		)
	end)

	t.test("sites: every building people walk into stands on level ground, and the list matches the lots", function()
		local M = Height.SITE_MARGIN
		local sites: { [string]: any } = {}
		for _, s in Height.SITES do
			sites[s.id] = s
			local lot = lots[s.id]
			t.truthy(lot, `{s.id} is not a lot`)
			t.eq(s.x, lot.x, s.id)
			t.eq(s.z, lot.z, s.id)
			t.eq(s.w, lot.footprint.w, s.id)
			t.eq(s.d, lot.footprint.d, s.id)
		end
		local enterable = 0
		for _, p in plans do
			if p.kind == "lot" and p.attributes.Enterable == true then
				enterable += 1
				local lot = lots[p.id]
				local seat = p.attributes.SeatY :: number
				local w, d = lot.footprint.w, lot.footprint.d
				local rises = false
				for i = 0, 24 do
					for j = 0, 24 do
						local x = lot.x - w / 2 - M + (w + 2 * M) * i / 24
						local z = lot.z - d / 2 - M + (d + 2 * M) * j / 24
						t.truthy(
							Height.at(x, z) <= seat + 0.05,
							`{p.id}: the ground stands above the seat at ({x}, {z})`
						)
						rises = rises or Height.natural(x, z) > seat + 0.05
					end
				end
				t.eq(sites[p.id] ~= nil, rises, `{p.id}: a site exactly where the natural ground rises above the seat`)
			end
		end
		t.eq(enterable, 6)
	end)

	t.test("EnterCheck: a body walks from every building's door into each of its rooms and out at the back", function()
		local r = EnterCheck.run(plans, Height.at)
		print(`      {r.lots} buildings, {r.doors} exterior doors, {r.rooms} rooms, {r.cells} cells walked`)
		t.eq(table.concat(r.failures, "; "), "")
		t.eq(r.lots, 6)
		t.eq(r.rooms, 31)
		t.eq(r.doors, 11, "two for each house and the hospital, one for the station")
		-- the body is the game's own: the step a walking body takes and its width (Client/World/ClientWorld)
		local ClientWorld = require("@client/World/ClientWorld")
		t.eq(EnterCheck.STEP, ClientWorld.STEP)
		t.eq(EnterCheck.HALF, ClientWorld.BODY_HALF)
		t.truthy(
			EnterCheck.TOP >= 5.5 and EnterCheck.TOP > ClientWorld.BODY_TOP,
			"a person's height: a squirrel fits too"
		)
	end)

	t.test(
		"EnterCheck has teeth: a solid leaf, a wall with no opening, a tall threshold, a low lintel, furniture in a doorway, ground through the floor",
		function()
			local id = "core_house_1_bungalow"
			local function fails(mutate: (parts: { any }) -> (), heightAt: ((number, number) -> number)?): string
				return table.concat(EnterCheck.lot(altered(id, mutate), heightAt or Height.at).failures, " | ")
			end
			local function has(text: string, what: string): boolean
				return string.find(text, what, 1, true) ~= nil
			end
			t.eq(fails(function() end), "", "the baked house is clean")
			-- the leaves solid, as they were baked before: nobody gets in
			local text = fails(function(parts)
				for _, s in parts do
					if s.role == "Door" then
						s.canCollide = true
					end
				end
			end)
			for _, room in { "living", "kitchen", "bedroom", "bath", "den" } do
				t.truthy(has(text, "no way from Door_front into the room " .. room), text)
			end
			t.truthy(has(text, "out at Door_back"), text)
			-- only the back door solid: every room is reached, but nobody comes out at the back
			text = fails(function(parts)
				find(parts, "Door_back").canCollide = true
			end)
			t.eq(text, "no way through the building from Door_front out at Door_back")
			-- a wall with no opening where the front door is
			text = fails(function(parts)
				across(parts, "Door_front", "Wall_rogue", 0, 8.75, 0.6)
			end)
			t.truthy(has(text, "into the room living") and has(text, "into the room den"), text)
			-- a threshold taller than a step shuts the bathroom; one a body steps over does not
			text = fails(function(parts)
				across(parts, "Door_living_bath", "Kerb_rogue", 0, 1.0, 0.4)
			end)
			t.eq(text, "no way from Door_front into the room bath")
			t.eq(
				fails(function(parts)
					across(parts, "Door_living_bath", "Kerb_low", 0, 0.7, 0.4)
				end),
				""
			)
			-- a lintel lower than a person
			text = fails(function(parts)
				across(parts, "Door_living_bath", "Beam_rogue", 4.5, 5.2, 0.4)
			end)
			t.eq(text, "no way from Door_front into the room bath")
			-- a cabinet pushed into the doorway
			text = fails(function(parts)
				local door = find(parts, "Door_living_bath")
				local block = table.clone(door)
				block.name, block.role, block.attrs, block.canCollide = "Furniture_rogue", "Furniture", nil, true
				block.sx, block.sy, block.sz = 3.4, 3, 3.4
				block.cy = door.cy - door.sy / 2 + 1.5
				table.insert(parts, block)
			end)
			t.eq(text, "no way from Door_front into the room bath")
			-- the ground coming up through the floor of half the house
			local lot = lots[id]
			local floor = find(byId[id].parts, "Floor")
			text = fails(function() end, function(x: number, z: number): number
				return if x > lot.x then floor.cy + floor.sy / 2 + 0.2 else Height.at(x, z)
			end)
			t.truthy(has(text, "the ground comes up through the floor"), text)
			-- the hospital on the natural ground: the grass indoors that the level site took away
			local natural = table.concat(EnterCheck.lot(byId.hospital_main, Height.natural).failures, " | ")
			t.truthy(has(natural, "the ground comes up through the floor"), natural)
		end
	)

	t.test(
		"doors: every doorway's leaf is an auto door that never collides; wide ones slide into the wall, the rest swing clear of the furniture",
		function()
			local C = roblox.CFrame
			local doors, slides, swings = 0, 0, 0
			for _, p in shells do
				local walls: { { number } } = {}
				local cores: { { name: string, box: { number } } } = {}
				for _, s in p.parts do
					local x0, x1, y0, y1, z0, z1 = Geometry.aabb(s)
					if s.role == "Wall" and s.canCollide then
						table.insert(walls, { x0, x1, y0, y1, z0, z1 })
					elseif (s.role == "Furniture" or s.role == "Station" or s.role == "Shelf") and s.canCollide then
						table.insert(cores, { name = s.name, box = { x0, x1, y0, y1, z0, z1 } })
					end
				end
				local function inWall(x: number, y: number, z: number): boolean
					for _, w in walls do
						if
							x > w[1] + 0.01
							and x < w[2] - 0.01
							and y > w[3]
							and y < w[4]
							and z > w[5] + 0.01
							and z < w[6] - 0.01
						then
							return true
						end
					end
					return false
				end
				local n = 0
				for _, s in p.parts do
					local a = s.attrs
					if s.role == "Door" and a then
						n += 1
						doors += 1
						local tag = `{p.id}.{s.name}`
						t.eq(s.canCollide, false, `{tag} collides: nobody could walk in`)
						t.eq(a.Auto, true, tag)
						t.eq(a.Locked, false, tag)
						local closed = C.new(s.cx, s.cy, s.cz) * C.Angles(0, s.yaw, 0)
						local size = { X = s.sx, Y = s.sy, Z = s.sz }
						local sill = s.cy - s.sy / 2
						if a.Motion == "slide" then
							slides += 1
							t.truthy(s.sx > Shell.SLIDE_MIN, tag)
							t.near(a.SlideRun, s.sx, 1e-9, `{tag}: it clears the whole doorway`)
							t.truthy(a.SlideSign == 1 or a.SlideSign == -1, tag)
							local open = DoorMotion.pose(closed, size, "slide", a.SlideSign, a.SlideRun, 1, C)
							-- open, the whole leaf stands inside the wall beside the doorway: both faces,
							-- at both ends and the middle (so it shows nowhere and shares no face)
							for _, f in { -0.5, 0, 0.5 } do
								for _, side in { -1, 1 } do
									local pt = (open * C.new(f * (s.sx - 0.1), 0, side * s.sz / 2)).Position
									t.truthy(inWall(pt.X, pt.Y, pt.Z), `{tag}: the open leaf shows outside the wall`)
								end
							end
						else
							swings += 1
							t.eq(a.Motion, "swing", tag)
							t.truthy(s.sx <= Shell.SLIDE_MIN, `{tag}: a {s.sx} st leaf swings`)
							-- either way it swings, the leaf sweeps over no furniture
							for _, sign in { 1, -1 } do
								for _, alpha in { 0.2, 0.4, 0.6, 0.8, 1 } do
									local cf = DoorMotion.pose(closed, size, "swing", sign, 0, alpha, C)
									for _, f in { -0.45, -0.25, 0, 0.25, 0.48 } do
										local pt = (cf * C.new(f * s.sx, 0, 0)).Position
										for _, c in cores do
											local b = c.box
											local hit = pt.X > b[1] - 0.1
												and pt.X < b[2] + 0.1
												and pt.Z > b[5] - 0.1
												and pt.Z < b[6] + 0.1
												and b[4] > sill + 0.2
											t.truthy(not hit, `{tag} swings through {c.name}`)
										end
									end
								end
							end
						end
					end
				end
				t.eq(p.attributes.AutoDoors, n, p.id)
			end
			print(`      {doors} doorways: {slides} leaves slide into the wall, {swings} swing`)
			t.eq(doors, 37)
			t.eq(slides, 14, "the hospital's ten and the station's four")
			t.eq(swings, 23, "the house doors")
			-- a plain building's front door is on a solid body: it stays a wall, shut
			local shop = find(byId.east_corner_shops.parts, "Door")
			t.eq(shop.canCollide, true)
			t.eq(shop.attrs.Auto, nil)
		end
	)
end
