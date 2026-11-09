--!strict
-- tools/review/export: flatten the baked rbxm files into build/review/scene.json for tools/review/render.py
-- (visual review renders for a developer who cannot open Studio; nothing here ships or touches the game).
-- Usage (repo root): lune run tools/review/export.luau [--out build/review/scene.json] [--step 4] [--no-terrain]
-- Inputs: build/Town.rbxm and build/EditorGround.rbxm (run tools/bake first) and assets/placeholders/*.rbxm.
--
-- Everything is written in ROBLOX coordinates (studs, Y up, right-handed, -Z forward); render.py converts.
--   parts[]  : { g = group, p = path, s = shape, size = {x,y,z}, pos = {x,y,z},
--                rot = {r00,r01,r02, r10,r11,r12, r20,r21,r22} (row-major, world = pos + rot * local; the columns
--                are the part's RightVector, UpVector and -LookVector), c = {r,g,b} 0-255, t = Transparency,
--                m = Material name }
--     shape: Block | Ball | Cylinder | Wedge | CornerWedge | Box (MeshPart and anything else: its bounding box)
--     Parts with Transparency >= 0.95 are skipped (counted in stats.skippedTransparent).
--   beams[]  : { g, p, a = {x,y,z}, b = {x,y,z}, w = width, c = {r,g,b} }: a Beam between its two Attachments'
--              world points (attachment parent CFrame * attachment CFrame). Zero-length beams are counted, not
--              emitted (stats.beamsDegenerate).
--   models[] : one row per top-level model of Town.Lots / Roads / Props / Lamps and Town.Skyline:
--              { p = path, kind, n = visible parts, min, max (world AABB of visible parts),
--                gap = lowest (part AABB bottom - World/Height.at under the part centre) }. gap > 0 means the
--              model's lowest visible part hovers above the analytic terrain; < 0 that it dips into it.
--   terrain  : World/Height.at sampled at the TerrainBake column centres (4 st) over the playable rectangle,
--              with the WorldTerrain surface material per column and the river water mask, plus a coarse
--              grid over the D32 world clamp (the boot terrain the player stands on; Lune cannot read voxels).
--   lineup   : placement of each placeholder puppet in a row on a ground plane at y = 0 (root at HipHeight or
--              BaseOffset above it, authored facing -Z kept), with labels and the measured foot gap.
local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Height = require("../../src/shared/World/Height")

local out = "build/review/scene.json"
local step = 4
local withTerrain = true
local i = 1
while i <= #process.args do
	local a = process.args[i]
	if a == "--out" then
		out = process.args[i + 1]
		i += 1
	elseif a == "--step" then
		step = tonumber(process.args[i + 1]) or error("--step needs a number")
		i += 1
	elseif a == "--no-terrain" then
		withTerrain = false
	else
		error("unknown argument: " .. a)
	end
	i += 1
end

local t0 = os.clock()

local function generated(name: string): any
	return luau.load(fs.readFile(`generated/{name}.luau`), { debugName = name })()
end
Height.configure(generated("TerrainExtensions"))

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

local function load(path: string): { any }
	if not fs.isFile(path) then
		error(`missing {path}: run tools/bake first (lune run tools/bake/main.luau; tools/bake/editor_ground.luau)`)
	end
	return roblox.deserializeModel(fs.readFile(path))
end

local function shapeOf(p: any): string
	local cls = p.ClassName
	if cls == "Part" then
		return p.Shape.Name -- Block | Ball | Cylinder | Wedge | CornerWedge
	elseif cls == "WedgePart" then
		return "Wedge"
	elseif cls == "CornerWedgePart" then
		return "CornerWedge"
	end
	return "Box" -- MeshPart, TrussPart, unions: the bounding box
end

-- Row-major rotation: R[r][c], columns are XVector, YVector, ZVector.
local function rotOf(cf: any): { number }
	local x, y, z = cf.XVector, cf.YVector, cf.ZVector
	return { r4(x.X), r4(y.X), r4(z.X), r4(x.Y), r4(y.Y), r4(z.Y), r4(x.Z), r4(y.Z), r4(z.Z) }
end

-- World AABB of a part's box: centre +- |R| * size / 2.
local function aabb(p: any): (any, any)
	local cf, s = p.CFrame, p.Size
	local x, y, z = cf.XVector, cf.YVector, cf.ZVector
	local hx = (math.abs(x.X) * s.X + math.abs(y.X) * s.Y + math.abs(z.X) * s.Z) / 2
	local hy = (math.abs(x.Y) * s.X + math.abs(y.Y) * s.Y + math.abs(z.Y) * s.Z) / 2
	local hz = (math.abs(x.Z) * s.X + math.abs(y.Z) * s.Y + math.abs(z.Z) * s.Z) / 2
	local c = cf.Position
	return roblox.Vector3.new(c.X - hx, c.Y - hy, c.Z - hz), roblox.Vector3.new(c.X + hx, c.Y + hy, c.Z + hz)
end

local parts: { any } = {}
local beams: { any } = {}
local models: { any } = {}
local stats = {
	parts = 0,
	skippedTransparent = 0,
	beams = 0,
	beamsDegenerate = 0,
	attachmentsAtPartOrigin = 0, -- Town only
	attachments = 0, -- Town only
	editorGroundPartsAtOrigin = 0,
	shapes = {} :: { [string]: number },
	groups = {} :: { [string]: number },
}

-- `offset` (a Vector3) translates every point (used to stand the puppets in the lineup).
local function emitPart(group: string, p: any, path: string, offset: any?)
	if p.Transparency >= 0.95 then
		stats.skippedTransparent += 1
		return
	end
	local shape = shapeOf(p)
	local pos = p.CFrame.Position
	if offset then
		pos += offset
	end
	table.insert(parts, {
		g = group,
		p = path,
		s = shape,
		size = v3(p.Size),
		pos = v3(pos),
		rot = rotOf(p.CFrame),
		c = rgb(p.Color),
		t = r2(p.Transparency),
		m = p.Material.Name,
	})
	stats.parts += 1
	stats.shapes[shape] = (stats.shapes[shape] or 0) + 1
	stats.groups[group] = (stats.groups[group] or 0) + 1
end

local function attachmentWorld(att: any, offset: any?): any
	local host = att.Parent
	local local_ = att.CFrame.Position
	local w = if host and host:IsA("BasePart") then host.CFrame * local_ else local_
	return if offset then w + offset else w
end

local function emitBeam(group: string, b: any, path: string, offset: any?)
	stats.beams += 1
	local a0, a1 = b.Attachment0, b.Attachment1
	if not a0 or not a1 then
		stats.beamsDegenerate += 1
		return
	end
	local pa, pb = attachmentWorld(a0, offset), attachmentWorld(a1, offset)
	if (pb - pa).Magnitude < 0.01 then
		stats.beamsDegenerate += 1
		return
	end
	local color = { 40, 40, 40 }
	local ok, kp = pcall(function()
		return b.Color.Keypoints[1].Value
	end)
	if ok and kp then
		color = rgb(kp)
	end
	table.insert(beams, {
		g = group,
		p = path,
		a = v3(pa),
		b = v3(pb),
		w = r4((b.Width0 + b.Width1) / 2),
		c = color,
	})
end

local function walk(group: string, root: any, offset: any?)
	local all = root:GetDescendants()
	table.insert(all, 1, root)
	for _, d in all do
		if d:IsA("BasePart") then
			emitPart(group, d, d:GetFullName(), offset)
		elseif d:IsA("Beam") then
			emitBeam(group, d, d:GetFullName(), offset)
		elseif d:IsA("Attachment") and group == "town" then
			stats.attachments += 1
			if d.CFrame.Position.Magnitude < 1e-6 then
				stats.attachmentsAtPartOrigin += 1
			end
		end
	end
end

-- Model rows (kind from the folder and the model's LotType attribute or name prefix).
local function modelRow(m: any, folder: string)
	local lo, hi = nil :: any, nil :: any
	local gap = math.huge
	local n = 0
	for _, d in m:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 0.95 then
			local a, b = aabb(d)
			lo = if lo then lo:Min(a) else a
			hi = if hi then hi:Max(b) else b
			local c = d.CFrame.Position
			gap = math.min(gap, a.Y - Height.at(c.X, c.Z))
			n += 1
		end
	end
	if n == 0 then
		return
	end
	local kind = m:GetAttribute("LotType") or string.match(m.Name, "^(%a+)_") or folder
	table.insert(models, {
		p = m:GetFullName(),
		folder = folder,
		kind = kind,
		n = n,
		min = v3(lo),
		max = v3(hi),
		gap = r2(gap),
	})
end

-- Town (the play build's Workspace.Town)
local town = load("build/Town.rbxm")[1]
walk("town", town)
for _, folder in town:GetChildren() do
	if folder:IsA("Folder") then
		for _, m in folder:GetChildren() do
			modelRow(m, folder.Name)
		end
	elseif folder:IsA("Model") then
		modelRow(folder, folder.Name)
	end
end

-- Editor ground (Studio's EDITOR view only: the server destroys it at boot and writes Terrain instead)
local editorGround = load("build/EditorGround.rbxm")
local egOrigin = 0
for _, root in editorGround do
	walk("editor_ground", root)
	for _, d in root:GetChildren() do
		if d:IsA("BasePart") and d.CFrame.Position.Magnitude < 1e-6 then
			egOrigin += 1
		end
	end
end

-- Placeholder lineup: one row along +X, every puppet facing -Z (authored), ground plane at y = 0.
local LINEUP = {
	"squirrel",
	"rodent",
	"fox",
	"deer_fawn",
	"deer_doe",
	"deer_buck",
	"human_townsperson",
	"human_officer",
	"vehicle_sedan",
	"vehicle_patrol_car",
}
local lineup = { ground = { y = 0 }, items = {} :: { any }, labels = {} :: { any } }
local cursorX = 0
for _, name in LINEUP do
	local file = `assets/placeholders/{name}.rbxm`
	if fs.isFile(file) then
		local model = load(file)[1]
		local hip = model:GetAttribute("HipHeight") or model:GetAttribute("BaseOffset") or 0
		local root = model.PrimaryPart
		local rootPos = if root then root.CFrame.Position else roblox.Vector3.new(0, 0, 0)
		-- visible extent relative to the root
		local lo, hi = nil :: any, nil :: any
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 0.95 then
				local a, b = aabb(d)
				lo = if lo then lo:Min(a) else a
				hi = if hi then hi:Max(b) else b
			end
		end
		local width = hi.X - lo.X
		local gapX = math.max(1.2, 0.35 * width)
		local slotX = cursorX + gapX - (lo.X - rootPos.X)
		local offset = roblox.Vector3.new(slotX - rootPos.X, hip - rootPos.Y, -rootPos.Z)
		walk("lineup", model, offset)
		local footGap = lo.Y + offset.Y -- ground is y = 0
		table.insert(lineup.items, {
			name = name,
			file = file,
			hipHeight = hip,
			root = v3(rootPos + offset),
			min = v3(lo + offset),
			max = v3(hi + offset),
			footGap = r4(footGap),
		})
		table.insert(lineup.labels, {
			text = name,
			pos = { r4(slotX), r4(hi.Y + offset.Y + 0.35 + 0.06 * (hi.Y - lo.Y)), r4(lo.Z + offset.Z) },
			size = r4(math.clamp(0.12 * (hi.X - lo.X + hi.Y - lo.Y), 0.22, 0.9)),
		})
		cursorX = hi.X + offset.X + gapX
	else
		print(`lineup: {file} missing, skipped`)
	end
end
lineup.ground = { y = 0, minX = -4, maxX = r4(cursorX + 4), minZ = -14, maxZ = 14 } :: any

-- Terrain heightfield at the TerrainBake column centres (WorldTerrain.write: grass, mud under the river
-- water, axis roads painted, D32 extension sand). Colours: WorldTerrain MATERIAL_COLORS.
local terrain: any = nil
if withTerrain then
	local ROAD_MATERIAL = { asphalt = "a", concrete = "c", cobble = "k", path = "p" }
	local paint = {}
	for _, r in generated("Roads") do
		local m = ROAD_MATERIAL[r.kind]
		if m and (r.axis == "x" or r.axis == "z") then
			local a, b = math.min(r.start, r["end"]), math.max(r.start, r["end"])
			local hw = r.width / 2
			if r.axis == "x" then
				table.insert(paint, { minX = a, maxX = b, minZ = r.coord - hw, maxZ = r.coord + hw, m = m })
			else
				table.insert(paint, { minX = r.coord - hw, maxX = r.coord + hw, minZ = a, maxZ = b, m = m })
			end
		end
	end
	local spu = Height.STUDS_PER_UNIT
	local P = Height.PLAYABLE_U
	local function grid(x0: number, x1: number, z0: number, z1: number, st: number, fine: boolean): any
		x0, z0 = math.floor(x0 / st) * st, math.floor(z0 / st) * st
		x1, z1 = math.ceil(x1 / st) * st, math.ceil(z1 / st) * st
		local nx, nz = (x1 - x0) // st, (z1 - z0) // st
		local hs = table.create(nx * nz)
		local mats = table.create(nz)
		local water = table.create(nz)
		for k = 0, nz - 1 do
			local z = z0 + (k + 0.5) * st
			local mrow = table.create(nx)
			local wrow = table.create(nx)
			for c = 0, nx - 1 do
				local x = x0 + (c + 0.5) * st
				local h = Height.at(x, z)
				table.insert(hs, r2(h))
				local wet = Height.insideRiverWater(x, z) and h < Height.WATER_Y
				local m = if Height.insideRiverWater(x, z) then "m" else "g"
				if Height.extensionMaterial(x, z) == "Sand" then
					m = "s"
				end
				if fine and not wet then
					for _, r in paint do
						if x >= r.minX and x <= r.maxX and z >= r.minZ and z <= r.maxZ then
							m = r.m
						end
					end
				end
				mrow[c + 1] = m
				wrow[c + 1] = if wet then "1" else "0"
			end
			mats[k + 1] = table.concat(mrow)
			water[k + 1] = table.concat(wrow)
		end
		return {
			x0 = x0,
			z0 = z0,
			step = st,
			nx = nx,
			nz = nz,
			heights = hs,
			materials = table.concat(mats),
			water = table.concat(water),
		}
	end
	local clamp = Height.worldClamp()
	terrain = {
		waterY = Height.WATER_Y,
		colors = {
			g = { 138, 159, 99 },
			m = { 111, 100, 80 },
			s = { 216, 201, 163 },
			a = { 75, 81, 83 },
			c = { 195, 190, 177 },
			k = { 196, 189, 171 },
			p = { 181, 168, 136 },
			w = { 64, 112, 120 },
		},
		fine = grid(P.minX * spu, P.maxX * spu, P.minZ * spu, P.maxZ * spu, step, true),
		coarse = grid(clamp.minX, clamp.maxX, clamp.minZ, clamp.maxZ, 20, false),
	}
end

-- Ground-contact summary per kind: how many models float (> 0.25 st) or sink (< -1 st), worst few.
local byKind: { [string]: { any } } = {}
for _, m in models do
	if m.folder ~= "Roads" and m.folder ~= "Skyline" then
		byKind[m.kind] = byKind[m.kind] or {}
		table.insert(byKind[m.kind], m)
	end
end
local contact = {}
local kinds: { string } = {}
for k in byKind do
	table.insert(kinds, k)
end
table.sort(kinds)
for _, k in kinds do
	local list = byKind[k]
	table.sort(list, function(a, b)
		return a.gap > b.gap
	end)
	local floating, sunk = 0, 0
	for _, m in list do
		if m.gap > 0.25 then
			floating += 1
		elseif m.gap < -1 then
			sunk += 1
		end
	end
	local worst = {}
	for j = 1, math.min(3, #list) do
		table.insert(worst, { p = list[j].p, gap = list[j].gap })
	end
	table.insert(contact, {
		kind = k,
		models = #list,
		floating = floating,
		sunk = sunk,
		maxGap = list[1].gap,
		minGap = list[#list].gap,
		worst = worst,
	})
end

stats.editorGroundPartsAtOrigin = egOrigin
local scene = {
	version = 1,
	units = "studs, Roblox axes (Y up, -Z forward)",
	stats = stats,
	parts = parts,
	beams = beams,
	models = models,
	contact = contact,
	lineup = lineup,
	terrain = terrain,
}
local dir = string.match(out, "^(.*)/[^/]+$")
if dir and not fs.isDir(dir) then
	fs.writeDir(dir)
end
local json = serde.encode("json", scene, false)
fs.writeFile(out, json)

print(
	`export: {stats.parts} parts ({stats.skippedTransparent} transparent skipped), {stats.beams} beams `
		.. `({stats.beamsDegenerate} zero-length), {#models} models -> {out} ({#json // 1024} KiB) in {string.format(
			"%.2f",
			os.clock() - t0
		)} s`
)
if stats.attachments > 0 and stats.attachmentsAtPartOrigin == stats.attachments then
	print(
		`WARNING: all {stats.attachments} Attachments in the baked files sit at their part's origin `
			.. "(Lune drops Attachment.Position writes; set CFrame instead), so every Beam is zero length"
	)
end
if egOrigin > 1 then
	print(
		`WARNING: {egOrigin} EditorGround parts sit at the world origin `
			.. "(Lune drops Part.Position writes; tools/bake/editor_ground.luau should set CFrame)"
	)
end
for _, c in contact do
	if c.floating > 0 or c.sunk > 0 then
		print(
			`contact: {c.kind}: {c.floating}/{c.models} float > 0.25 st (worst {c.maxGap} st {c.worst[1].p}), {c.sunk} sunk > 1 st (min {c.minGap})`
		)
	end
end
for _, it in lineup.items do
	print(`lineup: {it.name} hip {it.hipHeight} -> lowest visible part {it.footGap} st from the ground`)
end
