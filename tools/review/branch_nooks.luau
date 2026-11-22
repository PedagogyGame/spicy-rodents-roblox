--!strict
-- tools/review/branch_nooks: the D34 branch nooks as a review scene for tools/review/render.py (nothing here ships).
-- The nooks, stashes, hangouts, spurs and knots are Client/World/BranchNookArt over the compiled Shared/World/BranchNooks,
-- exactly the parts a client draws; the trees' Blender bark cannot be drawn offline, so group "bark" is a stand-in
-- (the trunk in round slices at the bark the game takes it to have, BranchNooks.barkRadius; each bough a run of
-- cylinders along its line, as worldgen Builders/Trees draws a bough: its top where the feet run), "ground" a lawn
-- under each tree, and "squirrels" grey-brown stand-ins (a body, a head, a tail) sitting where a squirrel sits: one in
-- a cup, three on a ledge.
-- Usage (repo root): lune run tools/review/branch_nooks.luau [--out build/review]
--   then /root/.cache/spicy-rodents/venv/bin/python -I tools/review/render.py --scene build/review/branch_nooks_scene.json
--     --views build/review/branch_nooks_views.json --out build/review/branch_nooks
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local BranchNookArt = require("../../src/client/World/BranchNookArt")
local BranchNooks = require("../../src/shared/World/BranchNooks")
local Data = require("../../src/shared/Data")
local Height = require("../../src/shared/World/Height")

local out = "build/review"
local i = 1
while i <= #process.args do
	if process.args[i] == "--out" then
		out = process.args[i + 1]
		i += 1
	else
		error("unknown argument: " .. process.args[i])
	end
	i += 1
end

local function r4(n: number): number
	return math.floor(n * 10000 + 0.5) / 10000
end

local d = Data.default()
local reg = d:routes()
local nooks = BranchNooks.new(d:module("BranchNooks") :: any)
local parts = {}

local function emit(group: string, p: any)
	local cf = p.CFrame
	local x, y, z = cf.XVector, cf.YVector, cf.ZVector
	table.insert(parts, {
		g = group,
		p = p:GetFullName(),
		s = if p.Shape == roblox.Enum.PartType.Cylinder
			then "Cylinder"
			elseif p.Shape == roblox.Enum.PartType.Ball then "Ball"
			else "Block",
		size = { r4(p.Size.X), r4(p.Size.Y), r4(p.Size.Z) },
		pos = { r4(cf.Position.X), r4(cf.Position.Y), r4(cf.Position.Z) },
		rot = { r4(x.X), r4(y.X), r4(z.X), r4(x.Y), r4(y.Y), r4(z.Y), r4(x.Z), r4(y.Z), r4(z.Z) },
		c = { math.floor(p.Color.R * 255 + 0.5), math.floor(p.Color.G * 255 + 0.5), math.floor(p.Color.B * 255 + 0.5) },
		t = 0,
		m = p.Material.Name,
	})
end
local function emitAll(group: string, root: any)
	for _, p in root:GetDescendants() do
		if p:IsA("BasePart") then
			emit(group, p)
		end
	end
end

-- a stand-in part straight into the scene
local function cyl(
	group: string,
	name: string,
	a: { number },
	b: { number },
	rad: number,
	color: { number },
	mat: string
)
	local dx, dy, dz = b[1] - a[1], b[2] - a[2], b[3] - a[3]
	local len = math.sqrt(dx * dx + dy * dy + dz * dz)
	if len < 1e-6 then
		return
	end
	local p = roblox.Instance.new("Part")
	p.Name = name
	p.Shape = roblox.Enum.PartType.Cylinder
	p.Size = roblox.Vector3.new(len + rad * 0.5, 2 * rad, 2 * rad)
	local ux, uy, uz = dx / len, dy / len, dz / len
	local ox, oy, oz = 0, 1, 0
	if math.abs(uy) > 0.95 then
		ox, oy, oz = 1, 0, 0
	end
	local zx, zy, zz = uy * oz - uz * oy, uz * ox - ux * oz, ux * oy - uy * ox
	local zl = math.sqrt(zx * zx + zy * zy + zz * zz)
	zx, zy, zz = zx / zl, zy / zl, zz / zl
	local yx, yy, yz = zy * uz - zz * uy, zz * ux - zx * uz, zx * uy - zy * ux
	p.CFrame = roblox.CFrame.fromMatrix(
		roblox.Vector3.new((a[1] + b[1]) / 2, (a[2] + b[2]) / 2, (a[3] + b[3]) / 2),
		roblox.Vector3.new(ux, uy, uz),
		roblox.Vector3.new(yx, yy, yz),
		roblox.Vector3.new(zx, zy, zz)
	)
	p.Color = roblox.Color3.fromRGB(color[1], color[2], color[3])
	p.Material = roblox.Enum.Material[mat]
	emit(group, p)
end
local function ball(group: string, name: string, c: { number }, dia: number, color: { number }, mat: string)
	local p = roblox.Instance.new("Part")
	p.Name = name
	p.Shape = roblox.Enum.PartType.Ball
	p.Size = roblox.Vector3.new(dia, dia, dia)
	p.CFrame = roblox.CFrame.new(c[1], c[2], c[3])
	p.Color = roblox.Color3.fromRGB(color[1], color[2], color[3])
	p.Material = roblox.Enum.Material[mat]
	emit(group, p)
end
local function block(group: string, name: string, c: { number }, size: { number }, color: { number }, mat: string)
	local p = roblox.Instance.new("Part")
	p.Name = name
	p.Size = roblox.Vector3.new(size[1], size[2], size[3])
	p.CFrame = roblox.CFrame.new(c[1], c[2], c[3])
	p.Color = roblox.Color3.fromRGB(color[1], color[2], color[3])
	p.Material = roblox.Enum.Material[mat]
	emit(group, p)
end

-- a sitting squirrel stand-in at feet (x, y, z) facing (fx, fz): body, head, tail (grey-brown; nothing green)
local FUR, TAIL = { 128, 112, 100 }, { 150, 132, 116 }
local function squirrel(name: string, x: number, y: number, z: number, fx: number, fz: number)
	ball("squirrels", name .. ".body", { x, y + 0.42, z }, 0.84, FUR, "Fabric")
	ball("squirrels", name .. ".head", { x + fx * 0.28, y + 0.95, z + fz * 0.28 }, 0.5, FUR, "Fabric")
	cyl(
		"squirrels",
		name .. ".tail",
		{ x - fx * 0.35, y + 0.3, z - fz * 0.35 },
		{ x - fx * 0.55, y + 1.25, z - fz * 0.55 },
		0.22,
		TAIL,
		"Fabric"
	)
end

-- the trees: the first with a nook, a hangout and two spurs, a big one, and an apple
local picks: { number } = {}
do
	local kinds: { [number]: { [string]: number } } = {}
	for _, p in nooks.places do
		local k = kinds[p.trunk] or {}
		kinds[p.trunk] = k
		k[p.kind] = (k[p.kind] or 0) + 1
	end
	local function name(trunk: number): string
		return (reg:get(trunk) :: any).name
	end
	local function pick(test: (number, string, { [string]: number }) -> boolean)
		local ids = {}
		for trunk in kinds do
			table.insert(ids, trunk)
		end
		table.sort(ids)
		for _, trunk in ids do
			if not table.find(picks, trunk) and test(trunk, name(trunk), kinds[trunk]) then
				table.insert(picks, trunk)
				return
			end
		end
	end
	pick(function(_t, n, k)
		return string.find(string.lower(n), "street", 1, true) ~= nil and (k.hangout or 0) >= 1 and (k.spur or 0) >= 2
	end)
	pick(function(_t, n, k)
		return string.find(n, "Estate", 1, true) ~= nil and (k.hangout or 0) >= 1
	end)
	pick(function(_t, n, _k)
		return string.find(n, "APPLE", 1, true) ~= nil
	end)
end

local views = {}
local function add(name: string, desc: string, pos: { number }, look: { number }, fov: number?)
	table.insert(views, {
		name = name,
		desc = desc,
		pos = { r4(pos[1]), r4(pos[2]), r4(pos[3]) },
		look = { r4(look[1]), r4(look[2]), r4(look[3]) },
		fov = fov or 60,
		groups = { "ground", "bark", "nooks", "squirrels" },
	})
end

local report = {}
for k, trunkId in picks do
	local trunk = reg:get(trunkId) :: any
	local foot = reg:foot(trunk)
	local tag = `t{k}`
	-- the lawn, the trunk, the boughs (stand-ins)
	local g = Height.at(foot.x, foot.z)
	block("ground", tag .. ".lawn", { foot.x, g - 0.5, foot.z }, { 90, 1, 90 }, { 96, 128, 70 }, "Grass")
	local bark = BranchNookArt.COLORS.barks[(trunkId % 4) + 1]
	local samples = reg:samples(trunk)
	for j = 1, #samples - 1, 2 do
		local a, b = samples[j], samples[math.min(j + 2, #samples)]
		local tt = (j - 1) / (#samples - 1)
		cyl(
			"bark",
			`{tag}.trunk{j}`,
			{ a.x, a.y, a.z },
			{ b.x, b.y, b.z },
			BranchNooks.barkRadius(trunk, tt) - 0.05,
			bark,
			"Wood"
		)
	end
	local boughs = {}
	for _, rec in d:forks() do
		if rec.trunk == trunkId then
			for _, f in rec.forks do
				table.insert(boughs, reg:get(f.branch))
			end
		end
	end
	for _, b in boughs do
		local s = reg:samples(b)
		for j = 1, #s - 1, 2 do
			local a, e = s[j], s[math.min(j + 2, #s)]
			local u = (j - 1) / (#s - 1)
			cyl(
				"bark",
				`{tag}.bough{b.id}_{j}`,
				{ a.x, a.y, a.z },
				{ e.x, e.y, e.z },
				1.19 + (0.75 - 1.19) * u,
				bark,
				"Wood"
			)
		end
	end
	-- the nooks, stashes, hangouts and spurs, and this tree's knots, as a client draws them
	local model, rep = BranchNookArt.build(roblox :: any, nooks, reg, trunkId)
	emitAll("nooks", model)
	local spurs = {}
	for _, p in nooks.tree(trunkId) do
		if p.kind == "spur" then
			table.insert(spurs, reg:get(p.route))
		end
	end
	local knots = roblox.Instance.new("Folder")
	local all = table.clone(boughs)
	for _, s in spurs do
		table.insert(all, s)
	end
	local nk = BranchNookArt.nodules(roblox :: any, reg, all, trunkId, knots, 60)
	emitAll("nooks", knots)
	table.insert(
		report,
		`{trunk.name}: {rep.parts} parts ({rep.nooks} nooks, {rep.hangouts} hangouts, {rep.spurs} spurs), {nk} knots`
	)
	-- squirrels: one in the first cup (with its stash full of acorns), three on the first ledge
	local firstNook, firstLedge, firstSpur = nil, nil, nil
	for _, p in nooks.tree(trunkId) do
		if p.kind == "nook" and firstNook == nil then
			firstNook = p
		elseif p.kind == "hangout" and firstLedge == nil then
			firstLedge = p
		elseif p.kind == "spur" and firstSpur == nil then
			firstSpur = p
		end
	end
	local lift = BranchNooks.C.lift
	if firstNook then
		local p = firstNook :: any
		local acorns = roblox.Instance.new("Folder")
		BranchNookArt.acorns(roblox :: any, p, 3, acorns)
		emitAll("nooks", acorns)
		squirrel(`{tag}.inNook`, p.at[1], p.at[2] + lift, p.at[3], p.out[1], p.out[2])
		local fx, fy, fz = p.at[1], p.at[2] + lift, p.at[3]
		add(
			`{tag}_nook`,
			`{trunk.name}: a nook in the crook of a bough, a squirrel sat in its cup, the knot-hole stash beside it (acorns: this player's nuts)`,
			{ fx + p.out[1] * 5 - p.out[2] * 2, fy + 2.6, fz + p.out[2] * 5 + p.out[1] * 2 },
			{ fx, fy + 0.4, fz },
			55
		)
	end
	if firstLedge then
		local p = firstLedge :: any
		local r = reg:get(p.route) :: any
		for n, tt in BranchNookArt.C.hangoutAt do
			local e = reg:pointAt(r, tt)
			squirrel(`{tag}.ledge{n}`, e.x, e.y + lift, e.z, p.out[1], p.out[2])
		end
		local m = reg:pointAt(r, 0.68)
		add(
			`{tag}_hangout`,
			`{trunk.name}: a hangout at a wide fork, a mossy crook with three squirrels sat on it`,
			{ m.x + p.out[1] * 7.5, m.y + lift + 3.4, m.z + p.out[2] * 7.5 },
			{ m.x, m.y + lift + 0.3, m.z },
			55
		)
	end
	if firstSpur then
		local p = firstSpur :: any
		local r = reg:get(p.route) :: any
		local m = reg:pointAt(r, 0.5)
		local b = reg:get(p.parent) :: any
		local q = reg:pointAt(b, p.parentT)
		local e = reg:pointAt(r, 1)
		local sx, sz = e.x - q.x, e.z - q.z
		local sl = math.max(math.sqrt(sx * sx + sz * sz), 1e-3)
		add(
			`{tag}_spur`,
			`{trunk.name}: a spur off the middle of a long bough (another place to go), twig and leaves at its tip`,
			{ m.x + sx / sl * 6 - sz / sl * 5, m.y + 4.5, m.z + sz / sl * 6 + sx / sl * 5 },
			{ q.x, q.y + 1, q.z },
			60
		)
	end
	-- the whole tree from a person's height, aimed at its nooks, and a squirrel's eye down a bough over its knots
	local midY, n = 0, 0
	for _, p in nooks.tree(trunkId) do
		midY += p.at[2]
		n += 1
	end
	midY = if n > 0 then midY / n else foot.y + 12
	add(
		`{tag}_tree`,
		`{trunk.name}: the tree with its nooks, hangout and spurs (stand-in bark)`,
		{ foot.x + 30, midY + 4, foot.z + 22 },
		{ foot.x, midY, foot.z },
		60
	)
	local longest = nil
	for _, b in boughs do
		if longest == nil or b.length > longest.length then
			longest = b
		end
	end
	if longest then
		local L = longest.length
		local first = BranchNooks.nodules(longest)[1] or L * 0.4
		local a = reg:pointAt(longest, math.clamp((first - 3) / L, 0.3, 0.9))
		local e = reg:pointAt(longest, math.clamp((first + 8) / L, 0.35, 1))
		add(
			`{tag}_knots`,
			`{trunk.name}: a squirrel's eye down its longest bough: the knots in the run path (each a little settle)`,
			{ a.x, a.y + lift + 1.3, a.z },
			{ e.x, e.y + lift + 0.2, e.z },
			70
		)
	end
end

if not fs.isDir(out) then
	fs.writeDir(out)
end
fs.writeFile(
	out .. "/branch_nooks_scene.json",
	serde.encode("json", { parts = parts, attractions = { lights = {}, texts = {} } })
)
fs.writeFile(
	out .. "/branch_nooks_views.json",
	serde.encode("json", {
		about = "THE BRANCH NOOKS review views (tools/review/branch_nooks.luau writes them from the compiled places).",
		defaults = { res = "960x540", samples = 16, groups = { "ground", "bark", "nooks", "squirrels" } },
		sun = {
			dir = { 0.7, 0.55, -0.45 },
			strength = 3.6,
			color = { 1.0, 0.86, 0.68 },
			angleDeg = 1.5,
			skyStrength = 1.0,
		},
		views = views,
	}, true)
)
for _, line in report do
	print("  " .. line)
end
print(`branch nooks review: {#parts} parts, {#views} views -> {out}/branch_nooks_scene.json, branch_nooks_views.json`)
