--!strict
-- tools/review/hollows: the hollow trees' insides and the fallen log as a review scene for tools/review/render.py
-- (nothing here ships). The shell is Server/World/HollowShell over the compiled Shared/World/HollowLayout, exactly
-- the parts the server builds; the trees' Blender bark cannot be drawn offline, so group "bark" is a stand-in of
-- round bark slices at the trunk's visual radius (Builders/Trees), and "ground" a plain lawn under each tree.
-- Usage (repo root): lune run tools/review/hollows.luau [--out build/review]
--   then /root/.cache/spicy-rodents/venv/bin/python -I tools/review/render.py --scene build/review/hollows_scene.json
--     --views build/review/hollows_views.json --out build/review/hollows
-- Writes hollows_scene.json (render.py's format: parts, attractions.lights) and hollows_views.json (views worked
-- out from the layout: from outside at a person's eye, cut away without the bark, and inside at a squirrel's eye).
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local Data = require("../../src/shared/Data")
local HollowLayout = require("../../src/shared/World/HollowLayout")
local HollowShell = require("../../src/server/World/HollowShell")

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

local layout = HollowLayout.default() :: HollowLayout.Layout
local reg = Data.default():routes()
local root = HollowShell.build(roblox, layout)
local parts = {}
local lights = {}

local function emit(group: string, p: any)
	local cf = p.CFrame
	local x, y, z = cf.XVector, cf.YVector, cf.ZVector
	table.insert(parts, {
		g = group,
		p = p:GetFullName(),
		s = if p.Shape == roblox.Enum.PartType.Cylinder then "Cylinder" else "Block",
		size = { r4(p.Size.X), r4(p.Size.Y), r4(p.Size.Z) },
		pos = { r4(cf.Position.X), r4(cf.Position.Y), r4(cf.Position.Z) },
		rot = { r4(x.X), r4(y.X), r4(z.X), r4(x.Y), r4(y.Y), r4(z.Y), r4(x.Z), r4(y.Z), r4(z.Z) },
		c = { math.floor(p.Color.R * 255 + 0.5), math.floor(p.Color.G * 255 + 0.5), math.floor(p.Color.B * 255 + 0.5) },
		t = 0,
		m = p.Material.Name,
	})
end

for _, d in root:GetDescendants() do
	if d:IsA("BasePart") then
		-- the cavity's wall (liner rings and roof) on its own: a cut-away view leaves it out to show what is inside
		local wall = string.match(d.Name, "^liner") ~= nil or string.match(d.Name, "^roof") ~= nil
		emit(if wall then "liner" else "hollows", d)
		local l = d:FindFirstChildOfClass("PointLight")
		if l then
			local c = l.Color
			table.insert(lights, {
				kind = "point",
				pos = { r4(d.CFrame.Position.X), r4(d.CFrame.Position.Y + 1.2), r4(d.CFrame.Position.Z) },
				dir = { 0, 1, 0 },
				brightness = l.Brightness,
				range = l.Range,
				color = { c.R * 255, c.G * 255, c.B * 255 },
			})
		end
	end
end

-- the bark stand-in and a lawn under each tree
local function block(group: string, name: string, pos: { number }, size: { number }, color: { number }, shape: string)
	table.insert(parts, {
		g = group,
		p = name,
		s = shape,
		size = size,
		pos = pos,
		rot = if shape == "Cylinder" then { 0, -1, 0, 1, 0, 0, 0, 0, 1 } else { 1, 0, 0, 0, 1, 0, 0, 0, 1 },
		c = color,
		t = 0,
		m = if shape == "Cylinder" then "Wood" else "Grass",
	})
end
for _, h in layout.hollows do
	block("ground", h.id .. ".lawn", { h.x, h.y - 0.6, h.z }, { 70, 1, 70 }, { 96, 128, 70 }, "Block")
	if h.trunk then
		local tr = HollowLayout.trunk(reg :: any, h.trunk :: number)
		for k = 0, 12 do
			local h0 = k * 3
			local x, y, z = tr.axisAt(h0 + 1.5)
			local r = tr.bark(h0 + 1.5)
			block("bark", `{h.id}.bark{k}`, { r4(x), r4(y), r4(z) }, { 3, 2 * r, 2 * r }, { 92, 70, 52 }, "Cylinder")
		end
	end
end

-- views
local views = {}
local function add(name: string, desc: string, pos: { number }, look: { number }, groups: { string }, fov: number?)
	table.insert(views, {
		name = name,
		desc = desc,
		pos = { r4(pos[1]), r4(pos[2]), r4(pos[3]) },
		look = { r4(look[1]), r4(look[2]), r4(look[3]) },
		fov = fov or 60,
		groups = groups,
	})
end
local OUTSIDE = { "ground", "bark", "hollows", "liner", "attractions" }
local CUT = { "ground", "hollows", "attractions" }
local INSIDE = { "ground", "hollows", "liner", "attractions" }
for _, h in layout.hollows do
	local hole = h.mouths[1]
	local ol = math.sqrt(hole.out[1] ^ 2 + hole.out[3] ^ 2)
	local ox, oz = hole.out[1] / ol, hole.out[3] / ol
	local id = string.lower(h.id)
	if h.trunk then
		add(
			id .. "_outside",
			`{h.id} ({h.tree}, {h.variant}) from outside at a person's eye, the ground hole facing`,
			{ hole.x + ox * 12, hole.y + 4.5, hole.z + oz * 12 },
			{ hole.x, hole.y + 1.5, hole.z },
			OUTSIDE
		)
	end
	if h.variant ~= "knothole" then
		local cav = h.cavities[#h.cavities]
		local mid = (cav.bottom + cav.top) / 2
		add(
			id .. "_cutaway",
			`{h.id} ({h.variant}) cut away: the bark left out to show the inside`,
			{ cav.x + ox * 16 - oz * 10, mid + 6, cav.z + oz * 16 + ox * 10 },
			{ cav.x, mid, cav.z },
			CUT,
			if h.variant == "spiral" then 75 else 60
		)
	end
end
-- inside, at a squirrel's eye: the single chamber from just inside its hole; up the shaft; along the spiral
local h3 = layout.hollow("H3") :: HollowLayout.Hollow
do
	local r = reg:get(h3.routes[1]) :: any
	local a, b = reg:pointAt(r, 0.45), reg:pointAt(r, 1)
	add(
		"h3_inside",
		"H3's chamber from just inside the hole, a squirrel's eye",
		{ a.x, a.y + 1.1, a.z },
		{ b.x, b.y + 0.8, b.z },
		INSIDE,
		80
	)
end
local h2 = layout.hollow("H2") :: HollowLayout.Hollow
do
	local r = reg:get(h2.routes[2]) :: any
	local a, b = reg:pointAt(r, 0.05), reg:pointAt(r, 0.6)
	local up = (r.enclosure :: any).up
	add(
		"h2_shaft_up",
		"H2's shaft from its foot, looking up the wall a squirrel climbs (the hideout shelf and the knotholes above)",
		{ a.x + up.x * 1.1, a.y + 0.3, a.z + up.z * 1.1 },
		{ b.x, b.y, b.z },
		INSIDE,
		85
	)
end
local h1 = layout.hollow("H1") :: HollowLayout.Hollow
do
	local r = reg:get(h1.routes[2]) :: any
	for k, tt in { 0.18, 0.55 } do
		local a, b = reg:pointAt(r, tt), reg:pointAt(r, tt + 0.03)
		add(
			`h1_ramp_{k}`,
			"H1's spiral ramp at a squirrel's eye, looking along the way up",
			{ a.x, a.y + 1.0, a.z },
			{ b.x, b.y + 0.8, b.z },
			INSIDE,
			85
		)
	end
end
local log = layout.hollow("LOG") :: HollowLayout.Hollow
do
	local m = log.mouths[1]
	add(
		"log_inside",
		"the fallen log from one end, a squirrel's eye",
		{ m.x - m.out[1] * 0.5, m.y + 0.9, m.z - m.out[3] * 0.5 },
		{ log.x, log.y + 0.9, log.z },
		INSIDE,
		75
	)
end

if not fs.isDir(out) then
	fs.writeDir(out)
end
fs.writeFile(
	out .. "/hollows_scene.json",
	serde.encode("json", { parts = parts, attractions = { lights = lights, texts = {} } })
)
fs.writeFile(
	out .. "/hollows_views.json",
	serde.encode("json", {
		about = "THE HOLLOW TREES review views (tools/review/hollows.luau writes them from the layout).",
		defaults = { res = "800x450", samples = 16, groups = OUTSIDE },
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
print(
	`hollows review: {#parts} parts, {#lights} lights, {#views} views -> {out}/hollows_scene.json, hollows_views.json`
)
