--!strict
-- The storm drains as data (BRIEF_ADDENDUM D8; Shared/World/SewerLayout over data/sewers.json, compiled to
-- generated/Sewers.luau and appended to the Registry by Shared/Data): the numbers every other lane builds on.
--   the routes keep to their pipe and above the recovery floor; the art pack's numbers are the section's
--   the carve: on the voxel grid, over every shell with its margin, under at least `cover` of ground, clear of the
--   baked town (build/Town.rbxm) except the slabs that already cover a shaft's hole; every mouth on the ground with
--   nothing standing in its opening
--   the junction, the fashion stand, the anchors; contains / nearestMouth / reentryMouth / surfaceWalk
--   lengths, the short cut by distance, ids clear of every other route
-- The runs through the pipes on the real motor are in sewers_runthrough.spec.
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local Data = require("@shared/Data")
local Enclosure = require("@shared/Routes/Enclosure")
local Height = require("@shared/World/Height")
local Recovery = require("@shared/Movement/Recovery")
local SewerLayout = require("@shared/World/SewerLayout")
local Tunables = require("@shared/Config/Tunables")
local BakedWorld = require("@tests/lib/BakedWorld")

local function floor4(v: number): number
	return math.floor(v / 4) * 4
end

return function(t)
	local data = Data.default()
	local layout = SewerLayout.default() :: SewerLayout.Layout
	local reg = data:routes()
	local doc = serde.decode("json", fs.readFile("data/sewers.json"))

	t.test("compiled: three pipes, eight street mouths, six routes on the enclosed-run contract", function()
		t.truthy(layout ~= nil, "generated/Sewers.luau is compiled and Shared/Data has it")
		t.eq(#layout.pipes, 3)
		t.eq(#layout.mouths, 8)
		local ids = {}
		for _, r in layout.routes do
			table.insert(ids, r.id)
			local route = reg:get(r.id)
			t.truthy(route ~= nil, `route {r.id} is in the Registry`)
			local rt = route :: any
			t.eq(rt.kind, Enclosure.KIND)
			t.eq(rt.origin, "sewer")
			t.eq(rt.flags.treeTravel, false, "full rail pace in a pipe, never the tree factor")
			t.eq(rt.speedMult, Tunables.raw("sewer.speedMult"), "the pipe pace is the one tunable")
			t.eq(Enclosure.zone(rt), layout.spaceOf(r.id))
			t.eq(#Enclosure.validate(r.enclosure, r.kind), 0)
		end
		table.sort(ids)
		t.deepEq(ids, { 9301, 9302, 9303, 9304, 9311, 9321 })
		t.eq(layout.spaceOf(9311), "sewer.culvert")
		t.eq(layout.spaceOf(9002), nil, "the ball return is not a sewer")
		-- built the same twice (the compiler is idempotent; tools/compile check holds generated/ to it)
		local a = SewerLayout.build(doc, { pace = Tunables.raw("sewer.speedMult") })
		local b = SewerLayout.build(doc, { pace = Tunables.raw("sewer.speedMult") })
		t.deepEq(a, b)
		t.eq(#a.carves, #layout.carves)
		t.eq(#a.anchors, #layout.anchors)
	end)

	t.test("ids 9300-9399, clear of the harvest, the alley (9001-9018) and the hollow trees (9100-9229)", function()
		for _, r in layout.routes do
			t.truthy(r.id >= 9300 and r.id <= 9399, tostring(r.id))
		end
		local counts: { [number]: number } = {}
		for _, r in reg:all() do
			counts[r.id] = (counts[r.id] or 0) + 1
			if r.origin ~= "sewer" then
				t.truthy(r.id < 9300 or r.id > 9399, `route {r.id} ({r.origin}) in the sewer range`)
			end
		end
		for id, n in counts do
			t.eq(n, 1, `route id {id} once`)
		end
	end)

	t.test("the section is the owner's art at one stud a metre (art pack metadata)", function()
		local base = "docs/reference/store_roofs/art_pack/Metadata/"
		local brick = serde.decode("json", fs.readFile(base .. "01_Brick_Sewer_Passage.json"))
		local junction = serde.decode("json", fs.readFile(base .. "02_Four_Way_Sewer_Junction.json"))
		local dry = serde.decode("json", fs.readFile(base .. "03_Concrete_Maintenance_Tunnel.json"))
		local k = layout.data.art.studsPerMetre
		local function box(meta: any, name: string): any
			for _, b in meta.collision_boxes do
				if b.name == name then
					return b
				end
			end
			error("no collision box " .. name)
		end
		local s = layout.data.sections.brick
		local wall = box(brick, "Walls_Right")
		t.near(s.innerHalf, (wall.center_m[1] - wall.size_m[1] / 2) * k, 1e-3, "inner wall face")
		t.near(s.outerHalf, (wall.center_m[1] + wall.size_m[1] / 2) * k, 1e-3, "outer wall face")
		local walk = box(brick, "Floor_Right")
		t.near(s.walkway[1], (walk.center_m[1] - walk.size_m[1] / 2) * k, 1e-3)
		t.near(s.walkway[2], (walk.center_m[1] + walk.size_m[1] / 2) * k, 1e-3)
		local bed = box(brick, "Floor_Channel_Bed")
		t.near(s.below, -(bed.center_m[2] - bed.size_m[2] / 2) * k, 1e-3, "the channel bed's underside")
		t.near(s.spring, brick.connectors[1].spring_height_m * k, 1e-3)
		t.truthy(s.crown > brick.connectors[1].crown_height_m * k, "the vault's outer top over its inner crown")
		-- the route on the walkway, the body on it and inside the junction's piers
		local body = Enclosure.BODY.width / 2
		t.truthy(s.routeOffset - body >= s.walkway[1] - 0.1 and s.routeOffset + body <= s.walkway[2])
		local pier = box(junction, "Piers_Junction")
		t.truthy(s.routeOffset + body <= (math.abs(pier.center_m[1]) - pier.size_m[1] / 2) * k, "clear of the piers")
		t.near(layout.data.chambers and layout.chambers[1].half or 0, junction.footprint_m[1] / 2 * k, 1e-3)
		local d = layout.data.sections.dry
		local floor = box(dry, "Floor_Dry")
		t.near(d.below, -(floor.center_m[2] - floor.size_m[2] / 2) * k, 1e-3)
		local plinth = box(dry, "Pump_Plinth")
		t.truthy(d.routeOffset + body <= (plinth.center_m[1] - plinth.size_m[1] / 2) * k, "clear of the pump")
		-- the enclosure gives the body its walkway and the shaft's depth from the rungs
		for _, r in layout.routes do
			t.truthy(r.enclosure.width >= Enclosure.BODY.width and r.enclosure.height >= Enclosure.BODY.height)
		end
	end)

	t.test("every route sample is inside its own pipe and above the recovery floor", function()
		for _, r in layout.routes do
			local route = reg:get(r.id) :: any
			local space = layout.spaceOf(r.id)
			local lowest = math.huge
			for i = 0, 400 do
				local p = reg:pointAt(route, i / 400)
				lowest = math.min(lowest, p.y)
				local where = layout.contains(p.x, p.y, p.z)
				local m = layout.nearestMouth(p.x, p.z, 2.5)
				local atStreet = m ~= nil and p.y > (m :: any).y - SewerLayout.C.streetSkin - 1e-6
				t.truthy(where == space or atStreet, `route {r.id} t {i / 400}: ({p.x}, {p.y}, {p.z}) in {where}`)
			end
			t.truthy(lowest > Recovery.FLOOR_Y + 2, `route {r.id} lowest {lowest}`)
		end
	end)

	t.test("the carve: on the grid, around every shell with its margin, under the ground's cover", function()
		local carve = layout.data.carve
		local boxes = layout.carveBoxes()
		local function inAny(x: number, y: number, z: number): boolean
			for _, b in boxes do
				if x >= b.x0 and x <= b.x1 and y >= b.y0 and y <= b.y1 and z >= b.z0 and z <= b.z1 then
					return true
				end
			end
			return false
		end
		for _, b in boxes do
			for _, v in { b.x0, b.x1, b.y0, b.y1, b.z0, b.z1 } do
				t.eq(v % carve.voxel, 0, "on the voxel grid")
			end
			t.truthy(b.y0 >= carve.slabBottom, "not under the terrain slab")
			if b.kind ~= "shaft" then
				-- at least `cover` studs of ground over it everywhere, and the surface voxel untouched
				local x = b.x0 + 0.5
				while x < b.x1 do
					local z = b.z0 + 0.5
					while z < b.z1 do
						local g = Height.at(x, z)
						t.truthy(
							b.y1 <= floor4(g - carve.cover),
							`{b.pipe} {b.kind} top {b.y1} under ground {g} at ({x}, {z})`
						)
						z += 1
					end
					x += 1
				end
			end
		end
		-- the outer shell plus the margin, along every passage (its corners and its mid-line, above and below)
		for _, p in layout.pipes do
			local s = layout.data.sections[p.section]
			for _, pass in p.passages do
				for i = 1, #pass.points - 1 do
					local a, b = pass.points[i], pass.points[i + 1]
					local len = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
					local dx, dz = (b.x - a.x) / len, (b.z - a.z) / len
					local n = math.ceil(len)
					for k = 0, n do
						local f = k / n
						local wy = a.y + (b.y - a.y) * f
						for _, l in { -1, 0, 1 } do
							local lat = l * (s.outerHalf + carve.margin)
							local x, z = a.x + dx * len * f + dz * lat, a.z + dz * len * f - dx * lat
							-- (nothing to clear under the terrain slab's bottom)
							local low = math.max(wy - s.below - carve.margin, carve.slabBottom)
							for _, y in { low, wy + s.crown + carve.margin } do
								t.truthy(inAny(x, y, z), `{p.id} passage shell + margin at ({x}, {y}, {z})`)
							end
						end
					end
				end
			end
		end
		-- each shaft's column reaches the street and goes down into its passage's carve
		for _, m in layout.mouths do
			local c = m.column
			t.truthy(c.y1 >= m.y and c.y1 - m.y < carve.voxel, `{m.id} column opens at the street`)
			t.truthy(c.y0 <= m.shaft.bottom - carve.margin, `{m.id} column reaches the passage`)
			local half = m.shaft.inside / 2 + m.shaft.wall
			t.truthy(c.x0 <= m.shaft.cx - half and c.x1 >= m.shaft.cx + half)
			t.truthy(c.z0 <= m.shaft.cz - half and c.z1 >= m.shaft.cz + half)
		end
	end)

	t.test("every mouth: on the ground, its opening inside its shaft, the body down through it", function()
		local body = Enclosure.BODY.width / 2
		for _, m in layout.mouths do
			t.truthy(math.abs(m.y - Height.at(m.x, m.z)) <= 0.3, `{m.id} on the ground ({m.y} / {Height.at(m.x, m.z)})`)
			local s = m.shaft
			local o = m.opening
			t.truthy(
				o.x0 >= s.cx - s.inside / 2 - 1e-6
					and o.x1 <= s.cx + s.inside / 2 + 1e-6
					and o.z0 >= s.cz - s.inside / 2 - 1e-6
					and o.z1 <= s.cz + s.inside / 2 + 1e-6,
				`{m.id} opening inside the shaft`
			)
			-- across the rungs the body's width, away from them its depth: both fit the opening (a 1.7 x 1.5 hole at least)
			local across = if s.rungs.x ~= 0 then o.z1 - o.z0 else o.x1 - o.x0
			local deep = if s.rungs.x ~= 0 then o.x1 - o.x0 else o.z1 - o.z0
			t.truthy(across >= 1.7 and deep >= 1.5, `{m.id} opening {across} x {deep}`)
			local ax = if s.rungs.x ~= 0 then m.z else m.x
			local a0 = if s.rungs.x ~= 0 then o.z0 else o.x0
			local a1 = if s.rungs.x ~= 0 then o.z1 else o.x1
			t.truthy(ax - body >= a0 - 1e-6 and ax + body <= a1 + 1e-6, `{m.id}: the body's width inside the opening`)
			local back = Enclosure.BODY.height
			local px = m.x - s.rungs.x * back
			local pz = m.z - s.rungs.z * back
			t.truthy(
				px >= o.x0 - 1e-6 and px <= o.x1 + 1e-6 and pz >= o.z0 - 1e-6 and pz <= o.z1 + 1e-6,
				`{m.id}: its back too`
			)
			t.eq(m.out.x, s.rungs.x)
			t.eq(m.out.z, s.rungs.z)
			local route = reg:get(m.route) :: any
			local q = reg:pointAt(route, m.t)
			t.near(q.x, m.x, 1e-3, `{m.id} is route {m.route}'s end`)
			t.near(q.y, m.y, 1e-3)
			t.near(q.z, m.z, 1e-3)
		end
	end)

	t.test("the baked town: nothing in a carve but the slabs over a shaft's hole; nothing over an opening", function()
		t.truthy(fs.isFile("build/Town.rbxm"), "build/Town.rbxm (lune run tools/bake/main.luau)")
		local town = BakedWorld.load("build/Town.rbxm")
		local function counts(p: BakedWorld.Part): boolean
			return p.collide or p.visible
		end
		local AXES = { { 1, 0, 0 }, { 0, 1, 0 }, { 0, 0, 1 } }
		local slabs: { [string]: boolean } = {}
		for _, b in layout.carveBoxes() do
			-- the street level over a shaft's column (its mouth's): slabs lying on the street there cover the hole
			local street: number? = nil
			for _, m in layout.mouths do
				local c = m.column
				if b.kind == "shaft" and c.x0 < b.x1 and c.x1 > b.x0 and c.z0 < b.z1 and c.z1 > b.z0 then
					street = m.y
				end
			end
			local function within(y0: number, y1: number): { BakedWorld.Part }
				return town.overlapBox(
					(b.x0 + b.x1) / 2,
					(y0 + y1) / 2,
					(b.z0 + b.z1) / 2,
					AXES,
					{ (b.x1 - b.x0) / 2 - 0.01, (y1 - y0) / 2 - 0.01, (b.z1 - b.z0) / 2 - 0.01 },
					counts
				)
			end
			-- nothing reaches into a carve; over a shaft, nothing more than half a stud under the street
			local low = if street then within(b.y0, street - 0.5) else within(b.y0, b.y1)
			for _, p in low do
				t.truthy(false, `{b.pipe} {b.kind} carve: {p.path} (y {p.y0}..{p.y1})`)
			end
			if street then
				for _, p in within(street - 0.5, b.y1) do
					slabs[p.path] = true
				end
			end
		end
		local names = {}
		for n in slabs do
			table.insert(names, n)
		end
		table.sort(names)
		print("      slabs over the shafts' holes: " .. table.concat(names, ", "))
		for _, m in layout.mouths do
			local o = m.opening
			local over = town.overlapBox(
				(o.x0 + o.x1) / 2,
				m.y + 1.5,
				(o.z0 + o.z1) / 2,
				AXES,
				{ (o.x1 - o.x0) / 2, 1.4, (o.z1 - o.z0) / 2 },
				function(p)
					return p.collide
				end
			)
			local list = {}
			for _, p in over do
				table.insert(list, p.path)
			end
			t.eq(#over, 0, `{m.id}: over the opening: {table.concat(list, ", ")}`)
			t.near(town.groundAt(m.x, m.z, m.y + 1), m.y, 0.3, `{m.id}: the street at the mouth`)
		end
	end)

	t.test("P1's junction: the arms meet at the crossing on the module's floor, the fashion stand beside it", function()
		local ch = layout.chambers[1]
		t.eq(ch.pipe, "P1")
		t.eq(#ch.ports, 4)
		local u, v = ch.ports[1].outward, ch.ports[2].outward
		t.near(u.x * v.x + u.z * v.z, 0, 1e-3, "the arms at right angles: the module's four arches")
		local function frame(x: number, z: number): (number, number)
			local px, pz = x - ch.x, z - ch.z
			return px * u.x + pz * u.z, px * v.x + pz * v.z
		end
		local cu, cv = frame(ch.crossing.x, ch.crossing.z)
		local body = Enclosure.BODY.width / 2
		t.truthy(math.abs(cu) + body <= 3 and math.abs(cv) + body <= 3, "the crossing on the central floor")
		-- every arm's samples inside the chamber keep the body off the piers (2.78, 0.4 square)
		for _, port in ch.ports do
			local route = reg:get(port.route) :: any
			for i = 0, 200 do
				local p = reg:pointAt(route, i / 200)
				local pu, pv = frame(p.x, p.z)
				if math.abs(pu) <= ch.half and math.abs(pv) <= ch.half then
					for _, su in { -1, 1 } do
						for _, sv in { -1, 1 } do
							local du = math.max(math.abs(pu - su * 2.78) - 0.2, 0)
							local dv = math.max(math.abs(pv - sv * 2.78) - 0.2, 0)
							t.truthy(math.max(du, dv) >= body, `arm {port.route} at ({pu}, {pv}) by a pier`)
						end
					end
				end
			end
		end
		local stand
		for _, a in layout.anchors do
			if a.kind == "fashionStand" then
				stand = a
			end
		end
		t.truthy(stand ~= nil, "the fashion stand's anchor")
		local su, sv = frame(stand.x, stand.z)
		t.truthy(math.abs(su) + 0.6 <= 2.58 and math.abs(sv) + 0.6 <= 2.58, "a 1.2 stand inside the piers")
		t.truthy(math.abs(su) - 0.6 >= 1.2 or math.abs(sv) - 0.6 >= 1.2, "off the sump grate")
		for _, port in ch.ports do
			local route = reg:get(port.route) :: any
			for i = 0, 200 do
				local p = reg:pointAt(route, i / 200)
				t.truthy(
					math.sqrt((p.x - stand.x) ^ 2 + (p.z - stand.z) ^ 2) >= body + 0.6,
					"the stand clear of the runs"
				)
			end
		end
		t.near(
			stand.facing.x * (ch.crossing.x - stand.x) + stand.facing.z * (ch.crossing.z - stand.z),
			math.sqrt((ch.crossing.x - stand.x) ^ 2 + (ch.crossing.z - stand.z) ^ 2),
			1e-3,
			"facing the crossing"
		)
		t.eq(stand.y, ch.y)
		-- the crossing joins all four arms: straight on by the end link, the side arms by forks
		for _, port in ch.ports do
			local route = reg:get(port.route) :: any
			local e = route.enclosure :: Enclosure.Spec
			t.truthy(e.atEnd ~= nil, `arm {port.route} runs straight on`)
			t.eq(#e.forks, 2, `arm {port.route} turns either way`)
			local q = reg:pointAt(route, 1)
			t.near(q.x, ch.crossing.x, 1e-3)
			t.near(q.z, ch.crossing.z, 1e-3)
		end
	end)

	t.test(
		"anchors: a lamp per art module on the wall away from the walkway, a sign at each shaft, the light grates",
		function()
			local kinds: { [string]: number } = {}
			for _, a in layout.anchors do
				kinds[a.kind] = (kinds[a.kind] or 0) + 1
				local space = layout.contains(a.x, a.y + 0.5, a.z)
				if a.kind ~= "lightGrate" then
					t.eq(space, a.space, `{a.kind} at ({a.x}, {a.y}, {a.z}) inside its pipe`)
				end
			end
			t.eq(kinds.sign, 8, "one stencil at each shaft foot")
			t.eq(kinds.lightGrate, 2, "P1's lid over the chamber, P3's grate in the boulevard")
			t.eq(kinds.fashionStand, 1)
			t.truthy((kinds.lamp or 0) >= 40, tostring(kinds.lamp))
			for _, a in layout.anchors do
				if a.kind == "lightGrate" then
					t.eq(layout.contains(a.x, a.y + 2, a.z), a.space, "a light grate's beam falls into its pipe")
				end
			end
		end
	)

	t.test("contains, nearestMouth, reentryMouth, surfaceWalk", function()
		t.eq(layout.contains(0, -9, 0), "sewer.crossroads", "under the crossing")
		t.eq(layout.contains(0, 0.5, 0), nil, "on the crossing")
		t.eq(layout.contains(2148, -12, 462), "sewer.culvert", "under the river")
		t.eq(layout.contains(2148, 0, 462), nil, "in the river")
		local m = layout.mouth("P1.NW") :: SewerLayout.Mouth
		t.eq(layout.contains(m.x, m.y, m.z), nil, "standing on the grate")
		t.eq(layout.contains(m.x, m.y - 1, m.z), "sewer.crossroads", "a stud down the shaft")
		local near, d = layout.nearestMouth(-20, 20)
		t.eq((near :: any).id, "P1.NW")
		t.truthy(d < 7)
		t.eq((layout.nearestMouth(500, 500, 50)), nil)
		-- re-entry: far from the death, nobody near, nearest the centre
		local r1 = layout.reentryMouth(-20, 20, {}) :: SewerLayout.Mouth
		t.truthy(math.sqrt((r1.x + 20) ^ 2 + (r1.z - 20) ^ 2) >= SewerLayout.C.reentryMin, r1.id)
		local r2 = layout.reentryMouth(2000, 400, {}) :: SewerLayout.Mouth
		t.eq(r2.pipe, "P1", "a death on the quay comes back at the crossroads")
		local crowd = {}
		for _, q in layout.mouthsOf("P1") do
			table.insert(crowd, { q.x + 3, q.z })
		end
		local r3 = layout.reentryMouth(2000, 400, crowd) :: SewerLayout.Mouth
		t.truthy(r3.pipe ~= "P1", "people at every crossroads grate: another drain")
		for _, q in crowd do
			t.truthy(math.sqrt((q[1] - r3.x) ^ 2 + (q[2] - r3.z) ^ 2) >= SewerLayout.C.reentryClear)
		end
		t.truthy(layout.reentryMouth(0, 0, nil) ~= nil, "always somewhere")
		local w = layout.surfaceWalk("P1.SE", "P1.NW") :: SewerLayout.SurfaceWay
		t.eq(w.points[1].x, 24.65)
		t.near(w.length, 112.96, 0.05)
	end)

	t.test("lengths, and the short cut by distance where the river forces the way round", function()
		local function len(id: number): number
			return (reg:get(id) :: any).length
		end
		local p1 = len(9301) + len(9303)
		local p2 = len(9311)
		local p3 = len(9321)
		t.near(p1, 91.0, 1, "P1 corner to corner")
		t.near(p2, 443.9, 1, "P2 quay to quay")
		t.near(p3, 402.8, 1, "P3 lawn to verge")
		t.near(len(9302) + len(9304), p1, 1e-3, "both P1 diagonals")
		local s1 = (layout.surfaceWalk("P1.NW", "P1.SE") :: any).length
		local s2 = (layout.surfaceWalk("P2.W", "P2.E") :: any).length
		local s3 = (layout.surfaceWalk("P3.S", "P3.N") :: any).length
		t.near(s2, 1429.7, 1)
		t.truthy(p2 < 0.35 * s2, `P2 {p2} against {s2} over the bridge`)
		t.truthy(p1 < s1, `P1 {p1} against the safe way {s1}`)
		-- P3 is longer than walking straight across (its time is in sewers_runthrough: it needs the pipe pace)
		t.truthy(p3 > s3 and p3 < s3 * Tunables.raw("sewer.speedMult"), `P3 {p3} against {s3}`)
	end)
end
