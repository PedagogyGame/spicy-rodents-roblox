--!strict
-- tests/lib/SewerStandIn: a plain stand-in of the storm drains (Shared/World/SewerLayout) as parts, for the specs that
-- drive the real SquirrelMotor through the pipes on tests/lib/BakedWorld before the bake (lane S1) exists. Built only
-- from the layout, at its numbers: each passage a floor (its top at the walkway), two side walls to the spring of the
-- vault and a roof at the vault's inner crown, the end walls behind the shafts; P1's chamber a floor, a roof and the
-- four solid corners of the junction module; each shaft four walls from the vault's outer top up to the street; each
-- mouth a cover part over its carve column at street level ("MouthCover": the squirrel stands on it; the route goes
-- down through it, as the drawn squirrel slips through the grate's bars, so the clearance sweep looks past it). The
-- shaft columns are a TerrainCarve folder (BakedWorld lowers the terrain inside them); the passage carves are not
-- (they are under the ground and leave the street as it is). Nothing here is the bake: no art, no lamps, no water.
-- Interface: model(layout) -> Model; world(layout) -> BakedWorld.World
local roblox = require("@lune/roblox")
local BakedWorld = require("@tests/lib/BakedWorld")

local SewerStandIn = {}

local Vector3 = roblox.Vector3
local CFrame = roblox.CFrame

local WALL = 0.32
local FLOOR = 0.44
local ROOF = 0.32

local function part(parent: any, name: string, cf: any, size: any)
	local p = roblox.Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = true
	p.Size = size
	p.CFrame = cf
	p.Parent = parent
	return p
end

-- a box along the segment a -> b (studs), `width` across, `height` up from `lift` over the segment's line, its frame
-- turned with the segment (a sloping run tilts it)
local function along(
	parent: any,
	name: string,
	a: any,
	b: any,
	lateral: number,
	lift: number,
	width: number,
	height: number,
	extra: number
)
	local va, vb = Vector3.new(a.x, a.y, a.z), Vector3.new(b.x, b.y, b.z)
	local len = (vb - va).Magnitude
	if len < 1e-6 then
		return
	end
	local cf = CFrame.lookAt((va + vb) / 2, vb)
	local centre = cf * Vector3.new(lateral, lift + height / 2, 0)
	part(
		parent,
		name,
		CFrame.lookAt(centre, centre + cf.LookVector, cf.UpVector),
		Vector3.new(width, height, len + extra)
	)
end

function SewerStandIn.model(layout: any): any
	local root = roblox.Instance.new("Model")
	root.Name = "Sewers"
	local carve = roblox.Instance.new("Model")
	carve.Name = "TerrainCarve"
	carve.Parent = root
	local data = layout.data
	for _, pipe in layout.pipes do
		local model = roblox.Instance.new("Model")
		model.Name = pipe.id
		model.Parent = root
		local s = data.sections[pipe.section]
		local inner = s.innerHalf
		for _, pass in pipe.passages do
			local pts = pass.points
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				-- the floor's top at the walkway, the walls from under it to the spring line plus the vault, the roof
				along(model, "Floor", a, b, 0, -FLOOR, 2 * inner + 2 * WALL, FLOOR, 0.6)
				along(model, "Wall", a, b, inner + WALL / 2, -FLOOR, WALL, s.crown - ROOF + FLOOR, 0.6)
				along(model, "Wall", a, b, -inner - WALL / 2, -FLOOR, WALL, s.crown - ROOF + FLOOR, 0.6)
			end
			-- the roof, open over the shaft at the passage's start (and its end, when it ends at a mouth)
			local first, last = pts[1], pts[#pts]
			local open = 4.0 + 2.0
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				local la = math.sqrt((a.x - first.x) ^ 2 + (a.z - first.z) ^ 2)
				local lb = math.sqrt((b.x - first.x) ^ 2 + (b.z - first.z) ^ 2)
				if lb <= open then
					continue
				end
				local function at(p: any, q: any, f: number): any
					return { x = p.x + (q.x - p.x) * f, y = p.y + (q.y - p.y) * f, z = p.z + (q.z - p.z) * f }
				end
				local seg = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
				local ra = if la < open then at(a, b, (open - la) / seg) else a
				local rb = b
				if pipe.chamber == nil then
					local ea = math.sqrt((a.x - last.x) ^ 2 + (a.z - last.z) ^ 2)
					local eb = math.sqrt((b.x - last.x) ^ 2 + (b.z - last.z) ^ 2)
					if ea <= open then
						continue
					end
					if eb < open then
						rb = at(a, b, (ea - open) / seg)
					end
				end
				along(model, "Roof", ra, rb, 0, s.crown - ROOF, 2 * inner + 2 * WALL, ROOF, 0)
			end
			-- the end walls behind the shafts
			local function endWall(p: any, q: any)
				local dx, dz = q.x - p.x, q.z - p.z
				local l = math.sqrt(dx * dx + dz * dz)
				local back = { x = p.x - dx / l * WALL, y = p.y, z = p.z - dz / l * WALL }
				along(model, "EndWall", back, p, 0, -FLOOR, 2 * inner + 2 * WALL, s.crown + FLOOR, 0)
			end
			endWall(pts[1], pts[2])
			if pipe.chamber == nil then
				endWall(pts[#pts], pts[#pts - 1])
			end
		end
		for _, ch in layout.chambers do
			if ch.pipe ~= pipe.id then
				continue
			end
			local u = ch.ports[1].outward
			local yaw = math.atan2(u.x, u.z)
			local base = CFrame.new(ch.x, ch.y, ch.z) * CFrame.Angles(0, yaw, 0)
			local h = ch.half
			part(model, "ChamberFloor", base * CFrame.new(0, -FLOOR / 2, 0), Vector3.new(2 * h, FLOOR, 2 * h))
			part(model, "ChamberRoof", base * CFrame.new(0, s.crown - ROOF / 2, 0), Vector3.new(2 * h, ROOF, 2 * h))
			-- the module's solid corners between its four arches (the arms are `inner` wide either side of an axis)
			local c = (h + inner) / 2
			for _, sx in { -1, 1 } do
				for _, sz in { -1, 1 } do
					part(
						model,
						"ChamberCorner",
						base * CFrame.new(sx * c, (s.crown - ROOF) / 2, sz * c),
						Vector3.new(h - inner, s.crown - ROOF, h - inner)
					)
				end
			end
		end
	end
	for _, m in layout.mouths do
		local sh = m.shaft
		local half = sh.inside / 2
		local y0 = sh.bottom + data.sections[(layout.pipe(m.pipe) :: any).section].crown
		local y1 = m.y - 0.3
		local hgt = y1 - y0
		local mid = (y0 + y1) / 2
		local t = sh.wall
		part(root, "ShaftWall", CFrame.new(sh.cx + half + t / 2, mid, sh.cz), Vector3.new(t, hgt, sh.inside + 2 * t))
		part(root, "ShaftWall", CFrame.new(sh.cx - half - t / 2, mid, sh.cz), Vector3.new(t, hgt, sh.inside + 2 * t))
		part(root, "ShaftWall", CFrame.new(sh.cx, mid, sh.cz + half + t / 2), Vector3.new(sh.inside, hgt, t))
		part(root, "ShaftWall", CFrame.new(sh.cx, mid, sh.cz - half - t / 2), Vector3.new(sh.inside, hgt, t))
		local col = m.column
		part(
			root,
			"MouthCover",
			CFrame.new((col.x0 + col.x1) / 2, m.y - 0.06, (col.z0 + col.z1) / 2),
			Vector3.new(col.x1 - col.x0, 0.12, col.z1 - col.z0)
		)
		part(
			carve,
			"Shaft",
			CFrame.new((col.x0 + col.x1) / 2, (col.y0 + col.y1) / 2, (col.z0 + col.z1) / 2),
			Vector3.new(col.x1 - col.x0, col.y1 - col.y0, col.z1 - col.z0)
		)
	end
	return root
end

function SewerStandIn.world(layout: any): BakedWorld.World
	return BakedWorld.fromModel(SewerStandIn.model(layout))
end

return SewerStandIn
