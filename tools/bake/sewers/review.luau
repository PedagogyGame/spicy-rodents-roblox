--!strict
-- tools/bake/sewers/review: one pipe of the storm drains as a review scene for tools/review/render.py (driven by
-- tools/bake/sewers/review.py, which also draws the owner's uploaded modules). Nothing here ships.
-- Usage (repo root, after lune run tools/review/export.luau and lune run tools/bake/sewers.luau):
--   lune run tools/bake/sewers/review.luau --pipe P1 [--base build/review/scene.json]
--     [--out build/review/sewers_P1.json]
-- Writes, in render.py's scene format (Roblox coordinates):
--   parts      the town's parts round the pipe (from the base scene) and the pipe's own (group "sewers"; its
--              Lining as group "lining": in the game the art loader hides the lining once his modules are in, so a
--              view shows either "art" or "lining", the parts fallback a failed load would leave)
--   art        each art slot: the FBX that was uploaded (build/art/sewers/<module>.fbx) and the slot's pivot
--   attractions.lights / texts   every light of the pipe, on (the client turns them on while a squirrel is
--              inside: Enabled is ignored here), and the signs' and the chalk's text
--   terrain    a fine grid round the pipe (half a stud) from Shared/World/Height with the base scene's surface
--              materials, lowered in the attractions' carves as the base scene has them; the base scene's coarse
--              grid beyond
--   holes      the shaft columns (the boot carve opens them to the street): review.py leaves them out of the
--              terrain mesh
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Height = require("../../../src/shared/World/Height")
local SewerLayout = require("../../../src/shared/World/SewerLayout")

local pipeId, base, out = "P1", "build/review/scene.json", nil :: string?
local i = 1
while i <= #process.args do
	local a = process.args[i]
	if a == "--pipe" then
		pipeId = process.args[i + 1]
		i += 1
	elseif a == "--base" then
		base = process.args[i + 1]
		i += 1
	elseif a == "--out" then
		out = process.args[i + 1]
		i += 1
	else
		error("unknown argument: " .. a)
	end
	i += 1
end
local outPath = out or `build/review/sewers_{pipeId}.json`

local layout = SewerLayout.new(require("../../../generated/Sewers") :: any)
local pipe = layout.pipe(pipeId) or error(`no pipe {pipeId}`)
local scene = serde.decode("json", fs.readFile(base))
local root = roblox.deserializeModel(fs.readFile("build/Sewers.rbxm"))[1]
local model = root:FindFirstChild(pipeId)

local function r4(n: number): number
	return math.floor(n * 1e4 + 0.5) / 1e4
end
local function v3(v: any): { number }
	return { r4(v.X), r4(v.Y), r4(v.Z) }
end
local function rgb(c: any): { number }
	return { math.floor(c.R * 255 + 0.5), math.floor(c.G * 255 + 0.5), math.floor(c.B * 255 + 0.5) }
end
local function rotOf(cf: any): { number }
	local x, y, z = cf.XVector, cf.YVector, cf.ZVector
	return { r4(x.X), r4(y.X), r4(z.X), r4(x.Y), r4(y.Y), r4(z.Y), r4(x.Z), r4(y.Z), r4(z.Z) }
end

-- the site: the pipe's mouths and passages, and 40 studs round them
local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
local function grow(x: number, z: number)
	x0, x1, z0, z1 = math.min(x0, x), math.max(x1, x), math.min(z0, z), math.max(z1, z)
end
for _, m in layout.mouthsOf(pipeId) do
	grow(m.x, m.z)
end
for _, pass in pipe.passages do
	for _, p in pass.points do
		grow(p.x, p.z)
	end
end
x0, x1, z0, z1 = x0 - 40, x1 + 40, z0 - 40, z1 + 40

-- the town's parts on the site
local parts = {}
for _, p in scene.parts do
	local q = p.pos
	if q[1] >= x0 and q[1] <= x1 and q[3] >= z0 and q[3] <= z1 then
		table.insert(parts, p)
	end
end

-- the pipe's own parts, lights and text
local lights, texts, art = {}, {}, {}
local function face(part: any, faceName: string): (any, any, any, any, number, number)
	local cf, s = part.CFrame, part.Size
	local X, Y, Z = cf.XVector, cf.YVector, cf.ZVector
	local c = cf.Position
	if faceName == "Front" then
		return c - Z * (s.Z / 2), -Z, -X, Y, s.X, s.Y
	elseif faceName == "Back" then
		return c + Z * (s.Z / 2), Z, X, Y, s.X, s.Y
	elseif faceName == "Right" then
		return c + X * (s.X / 2), X, -Z, Y, s.Z, s.Y
	elseif faceName == "Left" then
		return c - X * (s.X / 2), -X, Z, Y, s.Z, s.Y
	elseif faceName == "Top" then
		return c + Y * (s.Y / 2), Y, X, -Z, s.X, s.Z
	end
	return c - Y * (s.Y / 2), -Y, X, Z, s.X, s.Z
end
local function shapeOf(p: any): string
	if p.ClassName == "Part" then
		return p.Shape.Name
	elseif p.ClassName == "WedgePart" then
		return "Wedge"
	end
	return "Box"
end
local count = 0
for _, d in model:GetDescendants() do
	if d:IsA("BasePart") then
		local inLining = d:FindFirstAncestor("Lining") ~= nil
		if d.Transparency < 0.95 then
			table.insert(parts, {
				g = if inLining then "lining" else "sewers",
				p = d:GetFullName(),
				s = shapeOf(d),
				size = v3(d.Size),
				pos = v3(d.CFrame.Position),
				rot = rotOf(d.CFrame),
				c = rgb(d.Color),
				t = math.floor(d.Transparency * 100 + 0.5) / 100,
				m = d.Material.Name,
			})
			count += 1
		end
		for _, g in d:GetChildren() do
			if g:IsA("SurfaceGui") then
				local c, n, right, up, w, h = face(d, g.Face.Name)
				for _, lab in g:GetChildren() do
					if lab:IsA("TextLabel") and lab.Text ~= "" then
						table.insert(texts, {
							text = lab.Text,
							pos = v3(c + n * 0.006),
							normal = v3(n),
							right = v3(right),
							up = v3(up),
							w = r4(w),
							h = r4(h),
							color = rgb(lab.TextColor3),
						})
					end
				end
			end
		end
	elseif d:IsA("Light") then
		local at = d.Parent
		local cf = if at:IsA("Attachment") then at.Parent.CFrame * at.CFrame else at.CFrame
		local kind = if d:IsA("PointLight") then "point" elseif d:IsA("SpotLight") then "spot" else "area"
		table.insert(lights, {
			kind = kind,
			pos = v3(cf.Position),
			dir = v3(-cf.ZVector),
			right = v3(cf.XVector),
			up = v3(cf.YVector),
			size = { 1, 1 },
			color = rgb(d.Color),
			brightness = d.Brightness,
			range = d.Range,
			angle = if kind == "point" then 0 else d.Angle,
		})
	elseif d:IsA("Model") and d:GetAttribute("ArtModule") ~= nil then
		local cf = d:GetAttribute("ArtPivot")
		table.insert(art, {
			file = `build/art/sewers/{d:GetAttribute("ArtModule")}.fbx`,
			pos = v3(cf.Position),
			rot = rotOf(cf),
			group = "art",
		})
	end
end
-- the attractions' own carves (the alley's forecourt: tools/review/attractions_export) still lower the ground
local otherCarves = if scene.attractions then scene.attractions.carves or {} else {}
scene.parts = parts
scene.beams = {}
scene.art = art
scene.attractions = { lights = lights, texts = texts, carves = {} }

-- the terrain: a fine local grid, the shaft columns carved
local st = 0.5
local baseGrid = scene.terrain.fine
local function baseCell(g: any, x: number, z: number): number
	local c = math.clamp(math.floor((x - g.x0) / g.step), 0, g.nx - 1)
	local k = math.clamp(math.floor((z - g.z0) / g.step), 0, g.nz - 1)
	return k * g.nx + c + 1
end
local gx0, gz0 = math.floor(x0 / 4) * 4, math.floor(z0 / 4) * 4
local nx, nz = math.ceil((x1 - gx0) / st), math.ceil((z1 - gz0) / st)
local hs, mats, water = table.create(nx * nz), table.create(nz), table.create(nz)
local columns = {}
for _, b in layout.carveBoxes() do
	if b.kind == "shaft" and b.pipe == pipeId then
		table.insert(columns, b)
	end
end
for k = 0, nz - 1 do
	local z = gz0 + (k + 0.5) * st
	local mrow, wrow = table.create(nx), table.create(nx)
	for c = 0, nx - 1 do
		local x = gx0 + (c + 0.5) * st
		local h = Height.at(x, z)
		for _, b in otherCarves do
			if x > b.x0 and x < b.x1 and z > b.z0 and z < b.z1 then
				h = math.min(h, b.y0)
			end
		end
		table.insert(hs, math.floor(h * 100 + 0.5) / 100)
		local bc = baseCell(baseGrid, x, z)
		mrow[c + 1] = string.sub(baseGrid.materials, bc, bc)
		wrow[c + 1] = string.sub(baseGrid.water, bc, bc)
	end
	mats[k + 1] = table.concat(mrow)
	water[k + 1] = table.concat(wrow)
end
scene.terrain.fine = {
	x0 = gx0,
	z0 = gz0,
	step = st,
	nx = nx,
	nz = nz,
	heights = hs,
	materials = table.concat(mats),
	water = table.concat(water),
}
-- the shaft columns are holes in the ground: render's terrain mesh leaves them out (review.py), so no sheet of
-- terrain hangs down through the pipes as a heightfield lowered there would
local holes = {}
for _, b in columns do
	table.insert(holes, { b.x0, b.x1, b.z0, b.z1 })
end
scene.holes = holes
scene.lineup = nil
fs.writeFile(outPath, serde.encode("json", scene))
print(
	`sewers review: {pipeId}: {#parts} parts ({count} the pipe's), {#lights} lights, {#texts} texts, {#art} art slots, terrain {nx} x {nz} -> {outPath}`
)
