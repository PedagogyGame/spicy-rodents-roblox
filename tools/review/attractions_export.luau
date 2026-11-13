--!strict
-- tools/review/attractions_export: adds the attraction buildings to the review scene (export.luau calls it just
-- before it writes scene.json; render.py draws the additions through tools/review/attractions_render.py).
--   parts       build/Attractions.rbxm (tools/bake/attractions.luau) as group "attractions"
--   attractions.lights  every PointLight / SpotLight / SurfaceLight: { kind, pos, dir, size, color, brightness,
--               range, angle } (Roblox axes; dir = the light's face normal for spot and surface lights)
--   attractions.texts   every SurfaceGui TextLabel with text: { text, pos, right, up, w, h, color } so the
--               signs and scoreboards read in the renders (Blender's own font; position and size only)
--   terrain     the TerrainCarve boxes (Server/Attractions/AttractionService carves them to air at boot) are
--               applied to the fine and coarse heightfields: columns inside a box (grown by one step) are lowered
--               to the box's floor, as the boot terrain is after the carve
--   expansions  every build/Expansion_F*.rbxm (tools/bake/skylift.luau writes F4: the sky lift and the Lookout)
--               the same way, merged into the same group, lights, texts and carves. A cabin template (a Model
--               with Template = true, parked under the station floor) is not drawn: CABINS posed copies of it
--               stand on the line at lift time SKYLIFT_T (env, default 40 s), doors as Shared/Rides/SkyLift has
--               them then. The fine terrain grid is grown (same step, same values where it was) to take in the
--               bake's extent, so the hill under the lift is drawn at the town's resolution.
-- Usage: require("./attractions_export")(scene) from export.luau (a no-op with a note when nothing is baked);
--   require("./attractions_export")(scene, path) adds that one file.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local Height = require("../../src/shared/World/Height")
local SkyLift = require("../../src/shared/Rides/SkyLift")

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
local function shapeOf(p: any): string
	local cls = p.ClassName
	if cls == "Part" then
		return p.Shape.Name
	elseif cls == "WedgePart" then
		return "Wedge"
	elseif cls == "CornerWedgePart" then
		return "CornerWedge"
	end
	return "Box"
end

-- A part face as (centre, outward normal, right, up, width, height) in world space. Right/up are how a
-- SurfaceGui on that face reads to someone looking at it.
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

-- Is `d` inside a template model (a cabin parked under the floor for clients to clone)?
local function inTemplate(d: any): boolean
	local node = d.Parent
	while node ~= nil do
		if node:IsA("Model") and node:GetAttribute("Template") == true then
			return true
		end
		node = node.Parent
	end
	return false
end

-- CABINS copies of a cabin template on the line at lift time t (each part kept relative to the template's Origin;
-- door leaves slid by SlideZ x doorFrac), in a Folder "Cabins" under `parent`.
local function poseCabins(tpl: any, parent: any, t: number): number
	local origin = (tpl.PrimaryPart or tpl:FindFirstChild("Origin")).CFrame
	local inv = origin:Inverse()
	local folder = roblox.Instance.new("Folder")
	folder.Name = "Cabins"
	for i = 1, SkyLift.CABINS do
		local x, y, z, yaw = SkyLift.cabin(i, t)
		local frac = SkyLift.doorFrac(i, t)
		local at = roblox.CFrame.new(x, y, z) * roblox.CFrame.Angles(0, yaw, 0)
		local c = tpl:Clone()
		c.Name = `Cabin{i}`
		c:SetAttribute("Template", nil)
		for _, p in c:GetDescendants() do
			if p:IsA("BasePart") then
				local rel = inv * p.CFrame
				local leaf = p.Parent and p.Parent:GetAttribute("SlideZ")
				if type(leaf) == "number" then
					rel = roblox.CFrame.new(0, 0, leaf * frac) * rel
				end
				p.CFrame = at * rel
			end
		end
		c.Parent = folder
	end
	folder.Parent = parent
	return SkyLift.CABINS
end

-- Grow the fine heightfield (same origin grid and step; old cells kept) to take in [x0, x1] x [z0, z1].
local function growFine(g: any, x0: number, x1: number, z0: number, z1: number): boolean
	local st = g.step
	local ox0, oz0 = g.x0, g.z0
	local ox1, oz1 = ox0 + g.nx * st, oz0 + g.nz * st
	local nx0 = math.min(ox0, ox0 - math.ceil((ox0 - x0) / st) * st)
	local nz0 = math.min(oz0, oz0 - math.ceil((oz0 - z0) / st) * st)
	local nx1 = math.max(ox1, ox1 + math.ceil((x1 - ox1) / st) * st)
	local nz1 = math.max(oz1, oz1 + math.ceil((z1 - oz1) / st) * st)
	if nx0 == ox0 and nz0 == oz0 and nx1 == ox1 and nz1 == oz1 then
		return false
	end
	local nx, nz = (nx1 - nx0) // st, (nz1 - nz0) // st
	local dc, dk = (ox0 - nx0) // st, (oz0 - nz0) // st
	local hs = table.create(nx * nz)
	local mats, water = table.create(nz), table.create(nz)
	for k = 0, nz - 1 do
		local ok = k - dk
		local inRow = ok >= 0 and ok < g.nz
		local z = nz0 + (k + 0.5) * st
		local mrow, wrow = table.create(nx), table.create(nx)
		for c = 0, nx - 1 do
			local oc = c - dc
			if inRow and oc >= 0 and oc < g.nx then
				local i = ok * g.nx + oc + 1
				table.insert(hs, g.heights[i])
				table.insert(mrow, string.sub(g.materials, i, i))
				table.insert(wrow, string.sub(g.water, i, i))
			else
				local x = nx0 + (c + 0.5) * st
				table.insert(hs, math.floor(Height.at(x, z) * 100 + 0.5) / 100)
				table.insert(mrow, if Height.extensionMaterial(x, z) == "Sand" then "s" else "g")
				table.insert(wrow, "0")
			end
		end
		mats[k + 1] = table.concat(mrow)
		water[k + 1] = table.concat(wrow)
	end
	g.x0, g.z0, g.nx, g.nz = nx0, nz0, nx, nz
	g.heights = hs
	g.materials = table.concat(mats)
	g.water = table.concat(water)
	return true
end

local function addFile(scene: any, file: string)
	local root = roblox.deserializeModel(fs.readFile(file))[1]
	local into = scene.attractions or { lights = {}, texts = {}, carves = {} }
	scene.attractions = into
	local lights, texts, carves = into.lights, into.texts, into.carves
	local count, skipped, posed = 0, 0, 0
	local lo, hi = { math.huge, math.huge }, { -math.huge, -math.huge }
	local liftT = tonumber(process.env.SKYLIFT_T) or 40
	for _, d in root:GetChildren() do
		if d:IsA("Model") and d:GetAttribute("Template") == true and d:FindFirstChild("Seats") then
			posed += poseCabins(d, root, liftT)
		end
	end
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") and inTemplate(d) then
			skipped += 1
		elseif d:IsA("BasePart") then
			if file ~= "build/Attractions.rbxm" then
				local q = d.CFrame.Position
				lo[1], lo[2] = math.min(lo[1], q.X), math.min(lo[2], q.Z)
				hi[1], hi[2] = math.max(hi[1], q.X), math.max(hi[2], q.Z)
			end
			local inCarve = d.Parent and d.Parent.Name == "TerrainCarve"
			if inCarve then
				local cf, s = d.CFrame, d.Size
				local p = cf.Position
				-- carve boxes are axis-aligned in the world when the building's yaw is a multiple of 90 degrees;
				-- take the world AABB either way
				local X, Y, Z = cf.XVector, cf.YVector, cf.ZVector
				local hx = (math.abs(X.X) * s.X + math.abs(Y.X) * s.Y + math.abs(Z.X) * s.Z) / 2
				local hy = (math.abs(X.Y) * s.X + math.abs(Y.Y) * s.Y + math.abs(Z.Y) * s.Z) / 2
				local hz = (math.abs(X.Z) * s.X + math.abs(Y.Z) * s.Y + math.abs(Z.Z) * s.Z) / 2
				table.insert(carves, { x0 = p.X - hx, x1 = p.X + hx, y0 = p.Y - hy, z0 = p.Z - hz, z1 = p.Z + hz })
			elseif d.Transparency >= 0.95 then
				skipped += 1
			else
				table.insert(scene.parts, {
					g = "attractions",
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
			for _, child in d:GetChildren() do
				if
					(child:IsA("PointLight") or child:IsA("SpotLight") or child:IsA("SurfaceLight"))
					and child.Enabled ~= false -- baked off (a cabin by day): the game switches it on
				then
					local kind = if child:IsA("PointLight")
						then "point"
						elseif child:IsA("SpotLight") then "spot"
						else "area"
					local fname = if kind == "point" then "Front" else child.Face.Name
					local c, n, right, up, w, h = face(d, fname)
					table.insert(lights, {
						kind = kind,
						pos = v3(if kind == "point" then d.CFrame.Position else c),
						dir = v3(n),
						right = v3(right),
						up = v3(up),
						size = { r4(w), r4(h) },
						color = rgb(child.Color),
						brightness = child.Brightness,
						range = child.Range,
						angle = if kind == "point" then 0 else child.Angle,
					})
				elseif child:IsA("SurfaceGui") then
					local c, n, right, up, w, h = face(d, child.Face.Name)
					for _, lab in child:GetChildren() do
						if lab:IsA("TextLabel") and lab.Text ~= "" and lab.TextTransparency < 0.9 then
							local px, py = lab.Position.X.Scale, lab.Position.Y.Scale
							local sx, sy = lab.Size.X.Scale, lab.Size.Y.Scale
							local cx, cy = px + sx / 2, py + sy / 2
							local centre = c + n * 0.006 + right * ((cx - 0.5) * w) + up * ((0.5 - cy) * h)
							table.insert(texts, {
								text = lab.Text,
								pos = v3(centre),
								normal = v3(n),
								right = v3(right),
								up = v3(up),
								w = r4(sx * w),
								h = r4(sy * h),
								color = rgb(lab.TextColor3),
								bg = if lab.BackgroundTransparency < 0.5 then rgb(lab.BackgroundColor3) else nil,
							})
						end
					end
				end
			end
		end
	end
	scene.stats.groups.attractions = (scene.stats.groups.attractions or 0) + count
	-- an expansion beyond the town's fine grid: grow the grid over it (the hill under the sky lift)
	local grown = false
	if scene.terrain and scene.terrain.fine and lo[1] < hi[1] then
		grown = growFine(scene.terrain.fine, lo[1] - 40, hi[1] + 40, lo[2] - 40, hi[2] + 40)
	end
	-- lower the boot terrain inside the carve boxes (as AttractionService does at boot)
	local lowered = 0
	local function apply(g: any)
		if g == nil then
			return
		end
		local st = g.step
		for k = 0, g.nz - 1 do
			local z = g.z0 + (k + 0.5) * st
			for c = 0, g.nx - 1 do
				local x = g.x0 + (c + 0.5) * st
				for _, b in carves do
					if x >= b.x0 - st and x <= b.x1 + st and z >= b.z0 - st and z <= b.z1 + st then
						local i = k * g.nx + c + 1
						if g.heights[i] > b.y0 then
							g.heights[i] = math.floor(b.y0 * 100) / 100
							lowered += 1
						end
					end
				end
			end
		end
	end
	if scene.terrain then
		apply(scene.terrain.fine)
		apply(scene.terrain.coarse)
	end
	print(
		`attractions: {file}: {count} parts ({skipped} transparent or template skipped), {posed} cabins posed at t {liftT}, {#lights} lights, {#texts} texts, {#carves} carve boxes ({lowered} terrain columns lowered){if grown
			then ", fine terrain grown"
			else ""}`
	)
end

return function(scene: any, path: string?)
	if path then
		if fs.isFile(path) then
			addFile(scene, path)
		else
			print(`attractions: {path} missing`)
		end
		return
	end
	local files = {}
	if fs.isFile("build/Attractions.rbxm") then
		table.insert(files, "build/Attractions.rbxm")
	else
		print("attractions: build/Attractions.rbxm missing (lune run tools/bake/attractions.luau)")
	end
	if fs.isDir("build") then
		local found = {}
		for _, name in fs.readDir("build") do
			if string.match(name, "^Expansion_F%d+%.rbxm$") then
				table.insert(found, `build/{name}`)
			end
		end
		table.sort(found)
		for _, f in found do
			table.insert(files, f)
		end
	end
	if #files == 0 then
		print("attractions: nothing baked; the review shows no attractions")
	end
	for _, f in files do
		addFile(scene, f)
	end
end
