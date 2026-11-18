--!strict
-- Shared/World/FarTown: the town as it reads from far off (the review from the Lookout: "plain boxes: no roofs,
-- no windows, no trees"; at night "a black plain"). The lot's facing turns the house; the footprint is solved from
-- the axis-aligned envelope; houses get a gable whose ridge meets the envelope's top, shops a flat roof's cap;
-- window bands a storey; about seven homes in ten lit at night; one crown per Blender tree.
local FarTown = require("@shared/World/FarTown")
local Lots = require("../../generated/Lots")
local TreeArt = require("../../generated/TreeArt")

return function(t)
	t.test("facings: the four axes, yaw in degrees or radians, and nothing for the rest", function()
		t.near(FarTown.yawOf("+X") :: number, math.pi / 2, 1e-9)
		t.near(FarTown.yawOf("-X") :: number, math.pi / 2, 1e-9)
		t.near(FarTown.yawOf("+Z (ascending toward the back)") :: number, 0, 1e-9)
		t.near(FarTown.yawOf("-Z") :: number, 0, 1e-9)
		t.near(FarTown.yawOf("yaw 40.68 deg") :: number, math.rad(40.68), 1e-9)
		t.near(FarTown.yawOf("yaw 1.57 rad") :: number, 1.57, 1e-9)
		t.near(FarTown.yawOf("yaw -0.15 rad") :: number, -0.15, 1e-9)
		t.eq(FarTown.yawOf("n/a"), nil)
		t.eq(FarTown.yawOf("spans X"), nil)
		t.eq(FarTown.yawOf(nil), nil)
	end)

	t.test("the footprint is solved from the envelope of a turned building", function()
		t.deepEq({ FarTown.footprint(20, 10, 0) }, { 20, 10 })
		local w, d = FarTown.footprint(20, 10, math.pi / 2)
		t.deepEq({ w, d }, { 10, 20 })
		for _, deg in { 20, 30, 70, 122.04, 162.72 } do
			local yaw = math.rad(deg)
			local c, s = math.abs(math.cos(yaw)), math.abs(math.sin(yaw))
			local W, D = 24, 12
			local sx, sz = W * c + D * s, W * s + D * c
			local fw, fd = FarTown.footprint(sx, sz, yaw)
			t.near(fw, W, 1e-6, `width at {deg}`)
			t.near(fd, D, 1e-6, `depth at {deg}`)
		end
		-- near 45 degrees: a square of the same envelope, never bigger than it
		local fw, fd = FarTown.footprint(30, 30, math.rad(44))
		t.truthy(fw > 0 and fw <= 30 and fd > 0 and fd <= 30)
	end)

	t.test("a house: two roof wedges whose ridge meets the envelope's top, a body, a band a storey", function()
		local box = { lot = "h1", cx = 100, cy = 12, cz = -50, sx = 30, sy = 16, sz = 20, color = { 200, 190, 170 } }
		local pieces = FarTown.plan({ box }, { h1 = { id = "h1", type = "house", facing = "+Z" } })
		local roofs, bodies, bands = {}, {}, {}
		for _, p in pieces do
			t.eq(p.lot, "h1")
			if p.name == "Roof" then
				table.insert(roofs, p)
			elseif p.name == "Body" then
				table.insert(bodies, p)
			elseif p.name == "Band" then
				table.insert(bands, p)
			end
		end
		t.eq(#roofs, 2)
		t.eq(#bodies, 1)
		t.truthy(#bands >= 1 and #bands <= 3)
		local y0, y1 = box.cy - box.sy / 2, box.cy + box.sy / 2
		local body = bodies[1]
		t.near(body.y - body.sy / 2, y0 + 0.02 - 0.02, 0.05, "the body stands on the envelope's floor")
		for _, r in roofs do
			t.eq(r.shape, "Wedge")
			t.near(r.y + r.sy / 2, y1, 1e-9, "the ridge at the envelope's top")
			t.near(r.y - r.sy / 2, body.y + body.sy / 2 - 0.02, 0.05, "the eaves on the body")
			-- the ridge runs along the longer side (X here); each wedge's high edge (+Z) faces the ridge line
			t.near(r.sx, 31, 1e-9)
			local hz = math.cos(r.yaw)
			local hx = math.sin(r.yaw)
			local towardRidge = (box.cx - r.x) * hx + (box.cz - r.z) * hz
			t.truthy(towardRidge > 0, "the wedge's slope rises toward the ridge")
			-- inside the envelope (plus the overhang)
			t.truthy(math.abs(r.z - box.cz) + r.sz / 2 <= box.sz / 2 + 1.01)
		end
		for _, b in bands do
			t.truthy(b.band and b.y > y0 and b.y < y1)
			t.near(b.sx, body.sx + 0.16, 1e-9)
		end
	end)

	t.test("a shop: a flat roof's cap, its body under it, bands; a turned lot turns every piece", function()
		local box = { lot = "s1", cx = 0, cy = 15, cz = 0, sx = 40, sy = 30, sz = 40, color = { 150, 150, 150 } }
		local pieces = FarTown.plan({ box }, { s1 = { id = "s1", type = "quay_building", facing = "yaw 30 deg" } })
		local names = {}
		for _, p in pieces do
			names[p.name] = (names[p.name] or 0) + 1
			t.near(p.yaw, math.rad(30), 1e-9)
		end
		t.eq(names.Cap, 1)
		t.eq(names.Body, 1)
		t.eq(names.Band, 3, "three storeys of 30 st")
		t.eq(names.Roof, nil)
	end)

	t.test("on the real lots: every facing plans, about seven homes in ten lit; the same on every screen", function()
		local boxes, byId = {}, {}
		for _, lot in Lots :: any do
			if type(lot.x) == "number" and lot.footprint then
				byId[lot.id] = lot
				table.insert(boxes, {
					lot = lot.id,
					cx = lot.x,
					cy = 8,
					cz = lot.z,
					sx = lot.footprint.w * 0.6,
					sy = 16,
					sz = lot.footprint.d * 0.6,
					color = { 180, 170, 160 },
				})
			end
		end
		local a = FarTown.plan(boxes, byId)
		local b = FarTown.plan(boxes, byId)
		t.eq(#a, #b)
		local homes, lit = 0, 0
		local seen: { [string]: boolean } = {}
		for i, p in a do
			t.eq(p.x, b[i].x)
			t.eq(p.lit, b[i].lit)
			t.truthy(p.sx > 0 and p.sy > 0 and p.sz > 0, `{p.lot} {p.name} has a size`)
			if p.band and not seen[p.lot] and FarTown.GABLE[byId[p.lot].type] then
				seen[p.lot] = true
				homes += 1
				if p.lit then
					lit += 1
				end
			end
		end
		t.truthy(homes >= 20, `{homes} homes`)
		t.truthy(lit / homes > 0.5 and lit / homes < 0.9, `{lit} of {homes} homes lit`)
	end)

	t.test("one crown per Blender tree, inside its leaves, above the ground", function()
		local crowns = FarTown.crowns(TreeArt :: any)
		t.eq(#crowns, #(TreeArt :: any))
		for _, c in crowns do
			t.truthy(c.d > 4 and c.d < 200, `crown {c.d} across`)
			t.truthy(c.h > 2, "crown height")
			-- the trunk stands on the tree's pivot and reaches into the big ball; the balls sit inside the leaves
			t.truthy(c.trunkTop > c.trunkBase, "a trunk")
			t.eq(#c.balls, 3)
			for _, b in c.balls do
				t.truthy(b[2] + b[4] / 2 <= c.y + c.d / 2 + 1e-6, "no ball over the big one")
				t.truthy(b[2] - b[4] / 2 > c.trunkBase - 1, "no ball in the ground")
			end
		end
	end)
end
