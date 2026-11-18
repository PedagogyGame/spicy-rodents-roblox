--!strict
-- tools/bake/sewers/Mouth: what a street mouth looks like from the pavement and what the squirrel stands on.
--   frame    an iron frame at street level over the part of the shaft's carve column (Mouth.column) the baked
--            town leaves open (Mouth.FRAMES: the corner squares of grass at the crossing, the verge; else the whole
--            column, on a quay a little more: the quay's paving slab does not collide), with the opening
--            (Mouth.opening) in it; on open ground a concrete apron round it (Mouth.APRONS). Collides: the street goes
--            on over it. On a slope it lies in the ground's plane.
--   Grate    a Model the route passes through as the drawn squirrel slips between the bars (the clearance sweep
--            looks past it; tests/unit/sewers_bake.spec.luau): "MouthCover", an invisible plate over the opening at
--            the frame's top (the squirrel stands on it to press E), the visible bars (a kerb grate in a verge or a
--            lawn) or a cast-iron access cover (on a quay: the town's paving slab is drawn across the hole, so a
--            see-through grate would show paving), and on a quay the cover's underside under the slab; a SpotLight
--            under the opening ("GrateLight", disabled) for the client to light the shaft from above
-- Interface: build(kit, parent, mouth, space) -> { model, top, under } (top: the street surface over the mouth;
--   under: the underside the shaft's walls rise to); Mouth.FRAMES; Mouth.plane(mouth) -> (top, gx, gz)

local Height = require("../../../src/shared/World/Height")
local Kit = require("./Kit")

local Mouth = {}

-- the street around each mouth that the baked town (build/Town.rbxm) does not cover, x0, x1, z0, z1: measured from
-- the town's road, kerb and sidewalk parts (the corner squares of grass are 22.5..26.12; the verge 32.49..39.37),
-- reaching 0.1 under the road and sidewalk tops round them so no sliver of the hole shows (sewers_bake.spec holds
-- every column's top covered)
Mouth.FRAMES = {
	["P1.NW"] = { -26.22, -22.4, 22.4, 26.22 },
	["P1.NE"] = { 22.4, 26.22, 22.4, 26.22 },
	["P1.SE"] = { 22.4, 26.22, -26.22, -22.4 },
	["P1.SW"] = { -26.22, -22.4, -26.22, -22.4 },
	["P3.N"] = { 1348, 1352, 32.39, 39.47 },
}
-- on open ground the iron frame fills the carve column and a concrete apron runs round it (the lawn and the verge:
-- smooth terrain dips at the edge of a carved column, and the apron hides the dip), x0, x1, z0, z1
Mouth.APRON = 0.8 -- studs round the column
-- how deep an apron's concrete goes under the street: a skirt to the carved voxel's floor and past it, so where the
-- lawn dips at a carved column's edge (or slopes away from a level frame) concrete shows, never the shaft's brick
Mouth.APRON_DEPTH = 1.5
Mouth.APRONS = {
	-- the lawn, wholly: 4 studs clear of the alley's forecourt carve (tools/bake/attractions: down to 14.9 from z -340.2)
	["P3.S"] = { 1303.2, 1308.8, -336.2, -331.2 },
	["P3.N"] = { 1347.2, 1352.8, 32.39, 39.47 }, -- along the verge only: the boulevard and the kerb bound it
}
Mouth.OVERHANG = 0.3 -- studs past a carve column's edge where a quay's cover frame lies on the paving slab
Mouth.THICK = 0.3
Mouth.QUAY_SLAB_TOP = 0.1 -- the quay's paving slab stands this far over the ground (Lots.quay_district_ground)

local IRON = { 46, 48, 50 }
local RIM = { 70, 72, 74 }

-- the street surface over the mouth: its height at the mouth point and its slope (the ground's, at the mouth)
function Mouth.plane(m: any): (number, number, number)
	if m.kind == "cover" then
		return m.y + Mouth.QUAY_SLAB_TOP + 0.04, 0, 0
	end
	local e = 1.0
	local gx = (Height.at(m.x + e, m.z) - Height.at(m.x - e, m.z)) / (2 * e)
	local gz = (Height.at(m.x, m.z + e) - Height.at(m.x, m.z - e)) / (2 * e)
	return m.y + 0.02, gx, gz
end

local function rectsMinus(r: { number }, hole: { number }): { { number } }
	local out = {}
	local x0, x1, z0, z1 = r[1], r[2], r[3], r[4]
	local hx0, hx1 = math.max(hole[1], x0), math.min(hole[2], x1)
	local hz0, hz1 = math.max(hole[3], z0), math.min(hole[4], z1)
	local function add(a: number, b: number, c: number, d: number)
		if b - a > 0.04 and d - c > 0.04 then
			table.insert(out, { a, b, c, d })
		end
	end
	add(x0, x1, z0, hz0)
	add(x0, x1, hz1, z1)
	-- the side strips overlap the end strips a hair, so no float seam shows between them
	add(x0, hx0, hz0 - 0.01, hz1 + 0.01)
	add(hx1, x1, hz0 - 0.01, hz1 + 0.01)
	return out
end

function Mouth.build(kit: Kit.Kit, parent: any, m: any, space: string): { model: any, top: number, under: number }
	local r = kit.roblox
	local V, CF = r.Vector3, r.CFrame
	local model = kit:model(parent, m.id, { Mouth = m.id, Space = space, Kind = m.kind })
	local top, gx, gz = Mouth.plane(m)
	-- the plane's frame: origin on the street over the mouth point, y its normal, x and z square to world x and z
	local ny = V.new(-gx, 1, -gz).Unit
	local zx = V.new(0, 0, 1) - ny * ny.Z
	local zz = zx.Unit
	local xx = ny:Cross(zz)
	local plane = CF.fromMatrix(V.new(m.x, top, m.z), xx, ny, zz)
	local function local2(x: number, z: number): (number, number)
		return x - m.x, z - m.z
	end
	local col = m.column
	local rect = Mouth.FRAMES[m.id]
	if rect == nil then
		local over = if m.kind == "cover" then Mouth.OVERHANG else 0
		rect = { col.x0 - over, col.x1 + over, col.z0 - over, col.z1 + over }
	end
	local apron = Mouth.APRONS[m.id]
	if apron == true then
		local e = Mouth.APRON
		apron = { col.x0 - e, col.x1 + e, col.z0 - e, col.z1 + e }
	end
	if apron then
		for _, q in rectsMinus(apron, rect) do
			local a, b = local2(q[1], q[3])
			local c, d = local2(q[2], q[4])
			kit:box(model, "Apron", plane, a, c, -Mouth.APRON_DEPTH, -0.01, b, d, { 150, 146, 138 }, "Concrete")
		end
	end
	local o = m.opening
	local hole = { o.x0, o.x1, o.z0, o.z1 }
	for _, q in rectsMinus(rect, hole) do
		local a, b = local2(q[1], q[3])
		local c, d = local2(q[2], q[4])
		kit:box(model, "Frame", plane, a, c, -Mouth.THICK, 0, b, d, IRON, "CorrodedMetal")
	end
	local ax, az = local2(o.x0, o.z0)
	local bx, bz = local2(o.x1, o.z1)

	local grate = kit:model(model, "Grate")
	local cover = kit:box(
		grate,
		"MouthCover",
		plane,
		ax,
		bx,
		-0.1,
		0,
		az,
		bz,
		IRON,
		"CorrodedMetal",
		{ transparency = 1, shadow = false }
	)
	local w, d = bx - ax, bz - az
	if m.kind == "cover" then
		-- a cast-iron access cover lying in the frame, with raised ribs and a lifting slot
		kit:box(
			grate,
			"CoverPlate",
			plane,
			ax + 0.03,
			bx - 0.03,
			-0.05,
			0.0,
			az + 0.03,
			bz - 0.03,
			IRON,
			"DiamondPlate",
			{ visual = true }
		)
		for k = 1, 3 do
			local x = ax + w * k / 4
			kit:box(
				grate,
				"CoverRib",
				plane,
				x - 0.05,
				x + 0.05,
				0,
				0.025,
				az + 0.15,
				bz - 0.15,
				RIM,
				"CorrodedMetal",
				{ visual = true }
			)
		end
		kit:box(
			grate,
			"LiftSlot",
			plane,
			-0.25,
			0.25,
			0,
			0.012,
			bz - 0.45,
			bz - 0.33,
			{ 14, 14, 16 },
			"SmoothPlastic",
			{ visual = true }
		)
		-- its underside, under the quay's slab, with two pick holes of daylight
		local under = m.y - 0.1
		local ucf = CF.new(m.x, under - 0.05, m.z)
		local cx, cz = (o.x0 + o.x1) / 2 - m.x, (o.z0 + o.z1) / 2 - m.z
		kit:at(
			grate,
			"CoverUnderside",
			ucf * CF.new(cx, 0, cz),
			{ w - 0.06, 0.1, d - 0.06 },
			IRON,
			"CorrodedMetal",
			{ visual = true }
		)
		for _, s in { -1, 1 } do
			kit:at(
				grate,
				"PickHole",
				ucf * CF.new(cx + s * w * 0.3, -0.051, cz),
				{ 0.12, 0.01, 0.12 },
				{ 255, 244, 214 },
				"Neon",
				{ visual = true, shadow = false }
			)
		end
	else
		-- kerb grate bars across the shorter side, two flat bearers under them
		local alongX = w >= d
		local n = math.max(3, math.floor((if alongX then w else d) / 0.45))
		for k = 1, n - 1 do
			local f = k / n
			if alongX then
				local x = ax + w * f
				kit:box(
					grate,
					"GrateBar",
					plane,
					x - 0.06,
					x + 0.06,
					-0.14,
					0,
					az,
					bz,
					IRON,
					"CorrodedMetal",
					{ visual = true }
				)
			else
				local z = az + d * f
				kit:box(
					grate,
					"GrateBar",
					plane,
					ax,
					bx,
					-0.14,
					0,
					z - 0.06,
					z + 0.06,
					IRON,
					"CorrodedMetal",
					{ visual = true }
				)
			end
		end
		for _, f in { 0.3, 0.7 } do
			if alongX then
				local z = az + d * f
				kit:box(
					grate,
					"GrateBearer",
					plane,
					ax,
					bx,
					-0.24,
					-0.14,
					z - 0.05,
					z + 0.05,
					IRON,
					"CorrodedMetal",
					{ visual = true }
				)
			else
				local x = ax + w * f
				kit:box(
					grate,
					"GrateBearer",
					plane,
					x - 0.05,
					x + 0.05,
					-0.24,
					-0.14,
					az,
					bz,
					IRON,
					"CorrodedMetal",
					{ visual = true }
				)
			end
		end
	end
	-- daylight down the shaft (the client lights it while the space is in use)
	local at = kit:attach(
		cover,
		"GrateLight",
		plane * CF.new((ax + bx) / 2, -0.3, (az + bz) / 2) * CF.Angles(-math.pi / 2, 0, 0)
	)
	at:SetAttribute("Space", space)
	at:SetAttribute("Kind", "grateLight")
	kit:light(at, "SpotLight", {
		Brightness = 1.4,
		Range = 16,
		Angle = 60,
		Face = r.Enum.NormalId.Front,
		Color = r.Color3.fromRGB(236, 240, 246),
		Shadows = false,
	})
	local under = if m.kind == "cover" then m.y - 0.2 else top - Mouth.THICK
	return { model = model, top = top, under = under }
end

return Mouth
