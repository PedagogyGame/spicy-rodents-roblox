--!strict
-- WorldGen pins for the buildings and interiors art pass: decoration may be added freely, but it must
-- leave everything a body or a route stands on exactly where it was. These tests freeze, with their own
-- serialisation (independent of Bake.serialize, whose format may grow):
--   * the Skyline and street lamps, the route props (trees, poles, wires, pipes, fences) and the roads;
--   * the collidable massing of every lot (bodies, walls, roofs, floors, foundations; not furniture,
--     stations, shelves, ceilings or door steps, which are new interior and entrance pieces);
--   * the first part of every lot plan (its PrimaryPart and the reference of DoorReach and Skyline);
-- and they hold the rules that keep the engine bake identical to the Lune bake and the server's ground
-- rays honest: balls are uniform, cylinders round, and anything that overhangs a building without
-- colliding takes no queries.
-- A legitimate change to roads, props, lamps or massing by another track will fail here: re-pin the
-- value on purpose, in the same commit, and say why.
local Bake = require("@worldgen/Bake")
local Geometry = require("@worldgen/Geometry")

local function line(id: string, s: any): string
	return string.format(
		"%s/%s|%.3f|%.3f|%.3f|%.3f|%.3f|%.3f|%.4f|%.4f",
		id,
		s.name,
		s.cx,
		s.cy,
		s.cz,
		s.sx,
		s.sy,
		s.sz,
		s.yaw,
		s.pitch
	)
end

local function look(s: any): string
	return string.format(
		"|%.4f|%d,%d,%d|%s|%s|%.2f|%s",
		s.roll or 0,
		s.color[1],
		s.color[2],
		s.color[3],
		s.material,
		tostring(s.canCollide),
		s.transparency,
		s.shape or ""
	)
end

-- interior and entrance pieces the art pass adds on purpose
local NEW_ROLES = { Furniture = true, Station = true, Shelf = true, Ceiling = true, Step = true }

return function(t)
	local data = Bake.data()
	local plans = Bake.plans(data)

	t.test("pin: the Skyline, street lamps, route props and roads are untouched by decoration", function()
		local sky: { string } = {}
		local props: { string } = {}
		local lamps = 0
		for _, p in plans do
			if p.kind == "skyline" or p.kind == "lamps" then
				for _, s in p.parts do
					table.insert(sky, line(p.id, s) .. look(s))
				end
				if p.kind == "lamps" then
					lamps += #p.parts
				end
			elseif p.kind == "props" or p.kind == "road" then
				for _, s in p.parts do
					table.insert(props, line(p.id, s) .. look(s))
				end
			end
		end
		t.eq(lamps, 390)
		t.eq(Bake.fnv(table.concat(sky, "\n")), "44a6ca98126b416a", "Skyline or lamps moved: re-pin only on purpose")
		t.eq(Bake.fnv(table.concat(props, "\n")), "6f18bcf82f1f304e", "props or roads moved: re-pin only on purpose")
	end)

	t.test("pin: the collidable massing of every lot and its first part are exactly as before", function()
		local lines: { string } = {}
		local firsts: { string } = {}
		for _, p in plans do
			if p.kind == "lot" then
				table.insert(firsts, p.id .. ":" .. p.parts[1].name)
				for _, s in p.parts do
					if s.canCollide and not NEW_ROLES[s.role or ""] then
						table.insert(lines, line(p.id, s))
					end
				end
			end
		end
		t.eq(#lines, 854, "collidable massing parts")
		t.eq(Bake.fnv(table.concat(lines, "\n")), "3e2b604320333bd5", "massing moved: re-pin only on purpose")
		t.eq(Bake.fnv(table.concat(firsts, "\n")), "89066c7454a584aa", "a lot's first part changed")
	end)

	t.test("engine parity: every Ball is uniform and every Cylinder is round", function()
		local bad: { string } = {}
		local balls, cylinders = 0, 0
		for _, p in plans do
			for _, s in p.parts do
				if s.shape == "Ball" then
					balls += 1
					if math.abs(s.sx - s.sy) > 1e-9 or math.abs(s.sy - s.sz) > 1e-9 then
						table.insert(bad, `{p.id}.{s.name}`)
					end
				elseif s.shape == "Cylinder" then
					cylinders += 1
					if math.abs(s.sy - s.sz) > 1e-9 then
						table.insert(bad, `{p.id}.{s.name}`)
					end
				end
			end
		end
		t.truthy(balls >= 100 and cylinders >= 1000, `{balls} balls, {cylinders} cylinders`)
		t.eq(table.concat(bad, ", ", 1, math.min(#bad, 8)), "", `{#bad} shapes the engine would resize`)
	end)

	-- The server seats bodies and vehicles with a ray from the sky that stops at any part taking queries
	-- (Boot/Game groundY, Actors/DeviceService): an awning or an eave over a sidewalk must not catch it.
	t.test("overhangs: decoration standing out from a building without colliding takes no queries", function()
		local bad: { string } = {}
		local checked = 0
		for _, p in plans do
			if p.kind == "lot" and p.category == "building" then
				local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
				for _, s in p.parts do
					if s.canCollide and s.role ~= "Step" then
						local a0, a1, _, _, c0, c1 = Geometry.aabb(s)
						x0, x1, z0, z1 = math.min(x0, a0), math.max(x1, a1), math.min(z0, c0), math.max(z1, c1)
					end
				end
				for _, s in p.parts do
					if not s.canCollide and s.transparency < 1 and s.role ~= "Pad" then
						local a0, a1, _, _, c0, c1 = Geometry.aabb(s)
						local out = math.max(x0 - a0, a1 - x1, z0 - c0, c1 - z1)
						if out > 0.5 then
							checked += 1
							if s.canQuery ~= false then
								table.insert(bad, `{p.id}.{s.name}`)
							end
						end
					end
				end
			end
		end
		print(`      {checked} overhanging decoration parts`)
		t.eq(table.concat(bad, ", ", 1, math.min(#bad, 8)), "", `{#bad} overhangs a ground ray would land on`)
	end)
end
