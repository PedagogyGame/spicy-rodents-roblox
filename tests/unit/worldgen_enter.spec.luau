--!strict
-- Getting in (the interiors work, 2026-11-11): every exterior door stands on its threshold at ground
-- level or on steps a walking body can take (WorldGen/DoorSill), and the buildings people walk into
-- stand on level sites (World/Height.SITES) that match the lot data.
local Bake = require("@worldgen/Bake")
local DoorSill = require("@worldgen/DoorSill")
local Height = require("@shared/World/Height")

return function(t)
	local data = Bake.data()
	local plans = Bake.plans(data)
	local lots: { [string]: any } = {}
	for _, l in data.lots do
		lots[l.id] = l
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
end
