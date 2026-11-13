--!strict
-- tools/compile Expansion (batch 2 town expansion; brief v2 §3, §13a, §15 dec 18; docs/waves/BATCH2_SPEC.md):
-- the compiled layout is sound against the town as the bake sees it (no overlaps with lots, roads, trees, routes or
-- the bowling alley; every door reaches the street network; floors sit on the ground); the brief's counts hold
-- (18+ food businesses with 10 enterable and all 8 kinds, 22 corner-store shelves, 6 pickups + 4 SUVs, the approval
-- labels); world points match the AlleyLayout frame; and the checker really catches a bad layout.
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Backdrop = require("@shared/World/Backdrop")
local Height = require("@shared/World/Height")
local ItemRules = require("@shared/Items/ItemRules")
local Expansion = require("@tests/../tools/compile/lib/Expansion")

return function(t)
	local mod = require("../../generated/Expansion") :: any
	local ext = require("../../generated/TerrainExtensions") :: any
	local index = require("../../generated/Index") :: any
	local wildlife = require("../../generated/Wildlife") :: any
	local routes = {}
	for _, chunk in index.modules.Routes.chunks do
		for _, r in (require)("../../generated/" .. chunk) :: any do
			table.insert(routes, r)
		end
	end
	local world: Expansion.World = {
		lots = require("../../generated/Lots") :: any,
		roads = require("../../generated/Roads") :: any,
		routes = routes,
		trees = wildlife.studs.trees.trees,
		appleTrees = wildlife.studs.apple_trees.appleTrees,
		attractions = (require("../../generated/Attractions") :: any).attractions,
	}
	local function case(name: string, fn: () -> ())
		t.test(name, function()
			Height.configure(ext)
			Backdrop.reset()
			local ok, err = pcall(fn)
			Backdrop.reset()
			Height.configure(nil)
			if not ok then
				error(err, 0)
			end
		end)
	end
	local function venue(id: string): any
		for _, v in mod.venues do
			if v.id == id then
				return v
			end
		end
		error("no venue " .. id)
	end
	local function anchorsOf(v: any, kind: string): { any }
		local out = {}
		for _, a in v.anchors do
			if a.kind == kind then
				table.insert(out, a)
			end
		end
		return out
	end

	case("the compiled layout is sound against the existing town (no problems)", function()
		local problems = Expansion.check(mod, world)
		t.eq(#problems, 0, table.concat(problems, "\n"))
	end)

	case(
		"the ground kept for the alley's backstage: only the venues it names overlap it until the package arrives",
		function()
			-- (the owner's default, venue map question 2: the park gives up its northern edge, and the steakhouse site its
			-- eastern edge, only when the backstage arrives; until then both are drawn whole)
			local alley = world.attractions[1] :: any
			local rs = alley.reserve
			t.eq(table.concat(rs.givesWayOnArrival, " "), "f2_liberty_green f3_steakhouse")
			local ax0, _, az0 = AlleyLayout.toWorld(alley.place, rs.x0, 0, rs.d0)
			local ax1, _, az1 = AlleyLayout.toWorld(alley.place, rs.x1, 0, rs.d1)
			local rx0, rx1, rz0, rz1 = math.min(ax0, ax1), math.max(ax0, ax1), math.min(az0, az1), math.max(az0, az1)
			local named: { [string]: boolean } = {}
			for _, id in rs.givesWayOnArrival do
				named[id] = true
			end
			for _, v in mod.venues do
				local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
				for _, c in Expansion.sitePoly(v) do
					x0, x1 = math.min(x0, c[1]), math.max(x1, c[1])
					z0, z1 = math.min(z0, c[2]), math.max(z1, c[2])
				end
				local over = x0 < rx1 - 0.01 and x1 > rx0 + 0.01 and z0 < rz1 - 0.01 and z1 > rz0 + 0.01
				t.eq(over, named[v.id] == true, `{v.id} {if over then "overlaps" else "is clear of"} the reserve`)
			end
			-- the park as first drawn: z -724..-574, its bandstand inside it
			local green = venue("f2_liberty_green")
			t.eq(green.footprint.d, 150)
			t.eq(green.position.z, -649)
		end
	)

	case("the checker catches overlaps, an unreachable door, a floating floor and a missing pickup", function()
		local bad = table.clone(mod)
		bad.venues = table.clone(mod.venues)
		-- the diner moved onto the boulevard, the café's floor raised 5 st, a door with no path, one pickup gone
		local diner = table.clone(venue("f1_diner"))
		diner.position = { x = diner.position.x, z = 0 }
		local cafe = table.clone(venue("f1_cafe"))
		cafe.floorY += 5
		local barber = table.clone(venue("f1_barber"))
		barber.entrances = { { id = "nowhere", at = { 0, 20 }, width = 4, kind = "door", path = "xpath_missing" } }
		for i, v in bad.venues do
			if v.id == "f1_diner" then
				bad.venues[i] = diner
			elseif v.id == "f1_cafe" then
				bad.venues[i] = cafe
			elseif v.id == "f1_barber" then
				bad.venues[i] = barber
			end
		end
		bad.vehicles = table.clone(mod.vehicles)
		table.remove(bad.vehicles, 1)
		local text = table.concat(Expansion.check(bad, world), "\n")
		t.truthy(string.find(text, "f1_diner overlaps road rd_019_commercial_blvd", 1, true) ~= nil, text)
		t.truthy(string.find(text, "f1_cafe: floorY", 1, true) ~= nil, text)
		t.truthy(string.find(text, "f1_barber/nowhere: unknown path", 1, true) ~= nil, text)
		t.truthy(string.find(text, "5 pickups and 4 SUVs", 1, true) ~= nil, text)
	end)

	case("food: 18+ businesses, 10+ enterable, all 8 kinds (BUILD_PLAN invariant 4)", function()
		local kinds: { [string]: boolean } = {}
		local total, enterable = #mod.foodBaseline, 0
		for _, b in mod.foodBaseline do
			kinds[b.food] = true
		end
		for _, v in mod.venues do
			if v.food and v.status == "new" then
				total += 1
				enterable += 1
				kinds[v.food] = true
				-- outdoor seating or a back-alley dumpster (brief v2 §3)
				t.truthy(#anchorsOf(v, "seat") + #anchorsOf(v, "dumpster") > 0, v.id)
			end
		end
		t.truthy(total >= 18, `food businesses {total}`)
		t.truthy(enterable >= 10, `enterable {enterable}`)
		for _, k in Expansion.FOOD_KINDS do
			t.truthy(kinds[k], k)
		end
	end)

	case("places and attractions carry the brief's interactive anchors (brief v2 §13a)", function()
		-- corner store: one shelf per catalogue item (22), a checkout counter
		local store = venue("f1_corner_store")
		t.eq(#anchorsOf(store, "item_shelf"), #ItemRules.CATALOG)
		t.eq(#ItemRules.CATALOG, 22)
		t.truthy(#anchorsOf(store, "counter") >= 1)
		-- doctor's office: receptionist, two picture books, the bead maze and the tilt labyrinth on the waiting table
		local doctor = venue("f2_doctor")
		t.eq(#anchorsOf(doctor, "picture_book"), 2)
		local games: { [string]: boolean } = {}
		for _, v in mod.venues do
			for _, a in v.anchors do
				if a.game then
					games[a.game] = true
				end
			end
		end
		for _, g in { "racquetball", "volleyball", "giant_jenga", "tilt_labyrinth", "bead_maze" } do
			t.truthy(games[g], g)
		end
		t.truthy(#anchorsOf(venue("f2_museum"), "exhibit") >= 12, "museum exhibits")
		t.truthy(#anchorsOf(venue("f1_antique"), "curio") >= 12, "antique curios")
		t.eq(#anchorsOf(venue("f1_barber"), "barber_chair"), 2)
		t.truthy(#anchorsOf(venue("f3_steakhouse"), "squirrel_block") == 1, "steakhouse glass")
		for _, id in { "f3_lounge_classic", "f3_lounge_scifi" } do
			t.truthy(#anchorsOf(venue(id), "guard_post") >= 1, id)
			t.truthy(#anchorsOf(venue(id), "access") == 1, id)
		end
		t.truthy(#anchorsOf(venue("f3_tv_station"), "arena") == 1)
		local cafeSeats = 0
		for _, a in anchorsOf(venue("f1_cafe"), "seat") do
			if a.reputation then
				cafeSeats += 1
			end
		end
		t.truthy(cafeSeats >= 4, "cafe reputation seats")
	end)

	case(
		"rides: the sky lift runs base to summit above the ground; rides are first person; 6 pickups + 4 SUVs",
		function()
			local rides: { [string]: any } = {}
			for _, r in mod.rides do
				rides[r.id] = r
				t.eq(r.camera, "firstPerson")
			end
			for _, id in { "sky_lift", "parasail", "wind_tunnel", "jetski" } do
				t.truthy(rides[id] ~= nil, id)
			end
			local lift = rides.sky_lift
			local pts = lift.points
			local first, last = pts[1], pts[#pts]
			t.truthy(last[2] - first[2] > 90, "the summit is ~100 st above the base")
			-- bullwheel to bullwheel: the ends are the stations' ride_cable anchors, level with the next point
			-- (the station mouths) at floor + 12
			local base, top = venue("f4_lift_base"), venue("f3_hilltop")
			local function anchor(v: any, id: string): any
				for _, a in v.anchors do
					if a.id == id then
						return a
					end
				end
				error(id)
			end
			for _, pair in { { first, pts[2], base, "cable_out" }, { last, pts[#pts - 1], top, "cable_in" } } do
				local wheel, mouth, v, id = pair[1], pair[2], pair[3], pair[4]
				local a = anchor(v, id)
				t.near(wheel[1], a.world[1], 0.01, id)
				t.near(wheel[3], a.world[3], 0.01, id)
				t.near(wheel[2], v.floorY + 12, 0.01, id)
				t.near(mouth[2], v.floorY + 12, 0.01, id .. " mouth level")
				-- the mouth is on the building's face
				t.truthy(
					Expansion.polyDist(Expansion.footPoly(v), mouth[1], mouth[3]) < 0.05,
					id .. " mouth on the face"
				)
				t.truthy(Expansion.polyDist(Expansion.footPoly(v, 0.5), mouth[1], mouth[3]) > 0.4, id .. " not inside")
			end
			-- inside the summit hall the line runs along the hall's axis (local D), not across it
			local _, _, d0 = AlleyLayout.toLocal(top.place, pts[#pts - 1][1], 0, pts[#pts - 1][3])
			local x1, _, d1 = AlleyLayout.toLocal(top.place, last[1], 0, last[3])
			local x0 = AlleyLayout.toLocal(top.place, pts[#pts - 1][1], 0, pts[#pts - 1][3])
			t.near(x0, -35, 0.01)
			t.near(x1, -35, 0.01)
			t.near(d0, -25, 0.01)
			t.truthy(d1 > d0 + 30, "a straight run into the hall")
			-- nine towers that follow the ground: heads 20..40 above it; the cable clears the ground by 20 outside
			-- 30 st of both buildings (the compiler's rule, re-measured here every 2 st)
			t.eq(#pts - 4, 9, "nine towers")
			for i = 3, #pts - 2 do
				local p = pts[i]
				local above = p[2] - Expansion.ground(p[1], p[3])
				t.truthy(above >= 20 and above <= 40, `tower {i - 2} head {above}`)
			end
			t.eq(Expansion.CABLE_CLEAR, 20)
			local lowest = math.huge
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				local n = math.max(1, math.ceil(math.sqrt((b[1] - a[1]) ^ 2 + (b[3] - a[3]) ^ 2) / 2))
				for k = 0, n do
					local f = k / n
					local x, y, z = a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f, a[3] + (b[3] - a[3]) * f
					if
						Expansion.polyDist(Expansion.footPoly(base), x, z) > 30
						and Expansion.polyDist(Expansion.footPoly(top), x, z) > 30
					then
						lowest = math.min(lowest, y - Expansion.ground(x, z))
					end
				end
			end
			t.truthy(lowest >= 20, `lowest clearance {lowest}`)
			-- and the checker refuses a cable dragged down to 15 st over the plain
			local low = table.clone(mod)
			low.rides = table.clone(mod.rides)
			for i, r in low.rides do
				if r.id == "sky_lift" then
					local r2 = table.clone(r)
					r2.points = table.clone(r.points)
					local p = r2.points[5]
					r2.points[5] = { p[1], Expansion.ground(p[1], p[3]) + 15, p[3] }
					low.rides[i] = r2
				end
			end
			t.truthy(
				string.find(table.concat(Expansion.check(low, world), "\n"), "sky_lift: the cable is", 1, true) ~= nil
			)
			local n = { pickup = 0, suv = 0 }
			for _, v in mod.vehicles do
				n[v.kind] += 1
			end
			t.eq(n.pickup, 6)
			t.eq(n.suv, 4)
		end
	)

	case("world points: entrances and anchors are AlleyLayout.toWorld of their local points", function()
		for _, v in mod.venues do
			for _, a in v.anchors do
				local x, y, z = AlleyLayout.toWorld(v.place, a.at[1], a.at[2], a.at[3])
				t.near(a.world[1], x, 1e-3)
				t.near(a.world[2], y, 1e-3)
				t.near(a.world[3], z, 1e-3)
			end
			for _, e in v.entrances do
				local x, _, z = AlleyLayout.toWorld(v.place, e.at[1], 0, e.at[2])
				t.near(e.world[1], x, 1e-3)
				t.near(e.world[3], z, 1e-3)
			end
			-- the front of the footprint faces (sin yaw, cos yaw)
			local fx, _, fz = AlleyLayout.toWorld(v.place, 0, 0, -v.footprint.d / 2)
			local dx, dz = fx - v.place.x, fz - v.place.z
			local len = math.sqrt(dx * dx + dz * dz)
			t.near(dx / len, math.sin(v.yaw), 1e-6)
			t.near(dz / len, math.cos(v.yaw), 1e-6)
		end
		-- the street strips are Road-shaped: carriageway plus two sidewalks per street
		t.eq(#mod.strips, 3 * #mod.streets)
	end)

	case("approval map: every dec-18 label is on a venue, with 6 new homes", function()
		local labels: { [string]: number } = {}
		for _, v in mod.venues do
			if v.approval then
				labels[v.approval] = (labels[v.approval] or 0) + 1
			end
		end
		for _, l in Expansion.APPROVAL do
			t.truthy(labels[l] ~= nil, l)
		end
		t.eq(labels["6 new homes"], 6)
	end)
end
