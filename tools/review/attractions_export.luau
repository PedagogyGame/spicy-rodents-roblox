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
-- Usage: require("./attractions_export")(scene) from export.luau (a no-op with a note when the rbxm is missing).
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

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

return function(scene: any, path: string?)
	local file = path or "build/Attractions.rbxm"
	if not fs.isFile(file) then
		print(`attractions: {file} missing (lune run tools/bake/attractions.luau); the review shows no attractions`)
		return
	end
	local root = roblox.deserializeModel(fs.readFile(file))[1]
	local lights, texts, carves = {}, {}, {}
	local count, skipped = 0, 0
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
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
				if child:IsA("PointLight") or child:IsA("SpotLight") or child:IsA("SurfaceLight") then
					local kind = if child:IsA("PointLight") then "point" elseif child:IsA("SpotLight") then "spot" else "area"
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
	scene.attractions = { lights = lights, texts = texts, carves = carves }
	scene.stats.groups.attractions = count
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
		`attractions: {count} parts ({skipped} transparent skipped), {#lights} lights, {#texts} texts, {#carves} carve boxes ({lowered} terrain columns lowered)`
	)
end
