--!strict
-- tools/review/backdrop_export: adds the backdrop to the review scene. export.luau calls it just before it writes
-- scene.json; render.py draws the additions through tools/review/backdrop_render.py.
--   parts     build/Backdrop.rbxm (tools/bake/backdrop.luau) as group "backdrop"; a part with a Sphere SpecialMesh
--             is shape "Ellipsoid" (render.py draws a scaled sphere)
--   cards     the fog cards: { pos, rot, size, c, keys = { { position, transparency } } }, keys from the card's
--             UIGradient (0 = top, Rotation 90), drawn as an unlit alpha gradient
--   terrain   terrain.backdrop: World/Backdrop.groundAt over the band beyond the world clamp and the north coast
--             strip (what WorldGen/BackdropTerrain writes at boot), with its sea water mask (step 20 st). The
--             coarse grid's heights from the north coast rewrite on are replaced, so the two agree.
-- Usage: require("./backdrop_export")(scene) from export.luau (no-op with a note when the rbxm is missing).
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")

local Backdrop = require("../../src/shared/World/Backdrop")

local function r4(n: number): number
	return math.floor(n * 1e4 + 0.5) / 1e4
end
local function r2(n: number): number
	return math.floor(n * 100 + 0.5) / 100
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
	if p:FindFirstChildOfClass("SpecialMesh") and p:FindFirstChildOfClass("SpecialMesh").MeshType.Name == "Sphere" then
		return "Ellipsoid"
	end
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

return function(scene: any, path: string?)
	local file = path or "build/Backdrop.rbxm"
	if not fs.isFile(file) then
		print(`backdrop: {file} missing (lune run tools/bake/backdrop.luau); the review shows no backdrop`)
		return
	end
	Backdrop.reset()
	local root = roblox.deserializeModel(fs.readFile(file))[1]
	local parts, cards = 0, {}
	for _, d in root:GetDescendants() do
		if d:IsA("BasePart") then
			local gui = d:FindFirstChildOfClass("SurfaceGui")
			if gui then
				local frame = gui:FindFirstChildOfClass("Frame")
				local grad = frame and frame:FindFirstChildOfClass("UIGradient")
				if frame and grad then
					local keys = {}
					for _, k in grad.Transparency.Keypoints do
						table.insert(keys, { r4(k.Time), r4(k.Value) })
					end
					table.insert(cards, {
						pos = v3(d.CFrame.Position),
						rot = rotOf(d.CFrame),
						size = v3(d.Size),
						c = rgb(frame.BackgroundColor3),
						keys = keys,
						layer = d:GetAttribute("FogLayer") or 0,
					})
				end
			elseif d.Transparency < 0.95 then
				table.insert(scene.parts, {
					g = "backdrop",
					p = d.Parent.Name .. "/" .. d.Name,
					s = shapeOf(d),
					size = v3(d.Size),
					pos = v3(d.CFrame.Position),
					rot = rotOf(d.CFrame),
					c = rgb(d.Color),
					t = r2(d.Transparency),
					m = d.Material.Name,
				})
				parts += 1
			end
		end
	end
	scene.cards = cards

	local terrain = scene.terrain
	if terrain then
		local c = Backdrop.clamp()
		local B, north = Backdrop.BAND, Backdrop.NORTH_FROM_Z
		local st = 20
		local x0, x1 = math.floor((c.minX - B) / st) * st, math.ceil((c.maxX + B) / st) * st
		local z0, z1 = math.floor((c.minZ - B) / st) * st, math.ceil(Backdrop.WATER_TO_Z / st) * st
		local nx, nz = (x1 - x0) // st, (z1 - z0) // st
		local hs = table.create(nx * nz)
		local mats, water = table.create(nz), table.create(nz)
		local codes = { Sand = "s", Grass = "g", Rock = "r" }
		for k = 0, nz - 1 do
			local z = z0 + (k + 0.5) * st
			local mrow, wrow = table.create(nx), table.create(nx)
			for i = 0, nx - 1 do
				local x = x0 + (i + 0.5) * st
				local h = Backdrop.groundAt(x, z)
				table.insert(hs, r2(h))
				mrow[i + 1] = codes[Backdrop.materialAt(x, z, h)] or "g"
				wrow[i + 1] = if z > north and h < Backdrop.SEA_Y then "1" else "0"
			end
			mats[k + 1] = table.concat(mrow)
			water[k + 1] = table.concat(wrow)
		end
		terrain.colors.r = { 128, 124, 112 }
		terrain.backdrop = {
			x0 = x0,
			z0 = z0,
			step = st,
			nx = nx,
			nz = nz,
			heights = hs,
			materials = table.concat(mats),
			water = table.concat(water),
			seaY = Backdrop.SEA_Y,
			clamp = { c.minX, c.maxX, c.minZ, c.maxZ },
			northFrom = north,
		}
		-- the coarse grid (World/Height) north of the coast rewrite: the boot terrain there is Backdrop's
		local g = terrain.coarse
		if g then
			local replaced = 0
			for k = 0, g.nz - 1 do
				local z = g.z0 + (k + 0.5) * g.step
				if z >= north then
					for i = 0, g.nx - 1 do
						local x = g.x0 + (i + 0.5) * g.step
						g.heights[k * g.nx + i + 1] = r2(Backdrop.groundAt(x, z))
						replaced += 1
					end
				end
			end
			terrain.coarseReplacedNorth = replaced
		end
	end
	print(
		`backdrop: {parts} parts, {#cards} fog cards, terrain band {if terrain then "added" else "skipped"} from {file}`
	)
end
