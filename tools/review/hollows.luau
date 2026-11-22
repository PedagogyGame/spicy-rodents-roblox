--!strict
-- tools/review/hollows: the hollow trees' insides and the fallen log as a review scene for tools/review/render.py
-- (nothing here ships). The shell is Server/World/HollowShell over the compiled Shared/World/HollowLayout, exactly
-- the parts the server builds; the trees' Blender bark cannot be drawn offline, so group "bark" is a stand-in of
-- round bark slices at the trunk's visual radius (Builders/Trees), and "ground" a plain lawn under each tree.
-- Usage (repo root): lune run tools/review/hollows.luau [--out build/review]
--   then /root/.cache/spicy-rodents/venv/bin/python -I tools/review/render.py --scene build/review/hollows_scene.json
--     --views build/review/hollows_views.json --out build/review/hollows
-- Writes hollows_scene.json (render.py's format: parts, attractions.lights) and hollows_views.json (views worked
-- out from the layout: from outside at a person's eye, cut away (the bark and the liner on the camera's side left
-- out, the far half kept as the backdrop: groups "bark_cut" and "liner_cut"), and inside at a squirrel's eye).
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local CameraRig = require("../../src/client/Camera/CameraRig")
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

-- each cut-away's camera, level from its hollow's middle (unit): the half of the wall towards it is left out
local cutDir: { [string]: { number } } = {}
for _, h in layout.hollows do
	local hole = h.mouths[1]
	local ol = math.sqrt(hole.out[1] ^ 2 + hole.out[3] ^ 2)
	local ox, oz = hole.out[1] / ol, hole.out[3] / ol
	local dx, dz = ox * 16 - oz * 10, oz * 16 + ox * 10
	local dl = math.sqrt(dx * dx + dz * dz)
	cutDir[h.id] = { dx / dl, dz / dl }
end
-- on the far side of hollow `id` from its cut-away camera (or no hollow: false)
local function far(id: string, x: number, z: number): boolean
	local h = layout.hollow(id)
	local d = cutDir[id]
	if h == nil or d == nil then
		return false
	end
	local c = h.cavities[#h.cavities]
	return (x - c.x) * d[1] + (z - c.z) * d[2] < 0
end

local function emit(group: string, p: any)
	local cf = p.CFrame
	local model = p.Parent
	if group == "liner" and model and far(model.Name, cf.Position.X, cf.Position.Z) then
		emit("liner_cut", p) -- (and the whole wall for the views from inside)
	end
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

for _, d in root:GetDescendants() do
	if d:IsA("BasePart") and d.Transparency < 1 then
		-- the cavity's wall (liner rings and roof, the log's boards) on its own: a cut-away view keeps its far half
		local wall = string.match(d.Name, "^liner") ~= nil
			or string.match(d.Name, "^roof") ~= nil
			or string.match(d.Name, "^log%d") ~= nil
		-- (a knothole's dark oval on its own too: the client hides the one a squirrel peeks out of)
		local knot = string.match(d.Name, "^knothole") ~= nil
		emit(if wall then "liner" elseif knot then "knots" else "hollows", d)
		for _, a in d:GetChildren() do
			local al = if a:IsA("Attachment") then a:FindFirstChildOfClass("PointLight") else nil
			if al then
				local wp = d.CFrame * a.CFrame
				local c = al.Color
				table.insert(lights, {
					kind = "point",
					pos = { r4(wp.Position.X), r4(wp.Position.Y), r4(wp.Position.Z) },
					dir = { 0, 1, 0 },
					-- (Blender's lights have no range, and render.py makes a light's power from its range: a hollow's
					-- light goes to the renderer as HollowShell.LIGHT's, which its shorter range and brighter
					-- brightness are meant to look like inside the chamber)
					brightness = HollowShell.LIGHT.brightness,
					range = HollowShell.LIGHT.range,
					color = { c.R * 255, c.G * 255, c.B * 255 },
				})
			end
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
	-- the lawn level with the hole (the ground the squirrel runs in on; a trunk's foot is often a little above it)
	block("ground", h.id .. ".lawn", { h.x, h.mouths[1].y - 0.5, h.z }, { 70, 1, 70 }, { 96, 128, 70 }, "Block")
	if h.trunk then
		local tr = HollowLayout.trunk(reg :: any, h.trunk :: number)
		for k = 0, 12 do
			local h0 = k * 3
			local x, y, z = tr.axisAt(h0 + 1.5)
			local r = tr.bark(h0 + 1.5)
			block("bark", `{h.id}.bark{k}`, { r4(x), r4(y), r4(z) }, { 3, 2 * r, 2 * r }, { 92, 70, 52 }, "Cylinder")
			-- the cut-away's bark: the far half of the slice as 7 of its 14 flats, 0.3 thick
			local w = 2 * r * math.tan(math.pi / 14)
			for f = 0, 13 do
				local a = (f + 0.5) * math.pi / 7
				local sx, sz = math.sin(a), math.cos(a)
				local px, pz = x + sx * (r - 0.15), z + sz * (r - 0.15)
				if far(h.id, px, pz) then
					table.insert(parts, {
						g = "bark_cut",
						p = `{h.id}.bark{k}.flat{f}`,
						s = "Block",
						size = { r4(w), 3, 0.3 },
						pos = { r4(px), r4(y), r4(pz) },
						rot = { r4(sz), 0, r4(sx), 0, 1, 0, r4(-sx), 0, r4(sz) },
						c = { 92, 70, 52 },
						t = 0,
						m = "Wood",
					})
				end
			end
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
local OUTSIDE = { "ground", "bark", "hollows", "knots", "liner", "attractions" }
local CUT = { "ground", "hollows", "knots", "liner_cut", "bark_cut", "attractions" }
local INSIDE = { "ground", "hollows", "knots", "liner", "attractions" }
local PEEK = { "ground", "hollows", "liner", "attractions" }
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
		-- far enough back to take in the whole height (a shaft is 35 studs tall)
		local cav = h.cavities[#h.cavities]
		local mid = (cav.bottom + cav.top) / 2
		local d = cutDir[h.id]
		local back = math.max(18.9, (cav.top - cav.bottom) * 0.95)
		add(
			id .. "_cutaway",
			`{h.id} ({h.variant}) cut away: the bark and the boards on this side left out to show the inside`,
			{ cav.x + d[1] * back, mid + 3, cav.z + d[2] * back },
			{ cav.x, mid, cav.z },
			CUT,
			if h.variant == "spiral" then 75 else 60
		)
		-- and close up, the foot and the top of a tall one (a whole shaft is a thin stripe in a wide picture)
		if cav.top - cav.bottom > 12 then
			for _, part in { { "low", cav.bottom + 5 }, { "top", cav.top - 5 } } do
				local at = part[2] :: number
				add(
					`{id}_cutaway_{part[1]}`,
					`{h.id} ({h.variant}) cut away, close up at its {part[1]}`,
					{ cav.x + d[1] * 11, at + 2, cav.z + d[2] * 11 },
					{ cav.x, at, cav.z },
					CUT,
					70
				)
			end
		end
	end
end
-- inside, at a squirrel's eye: the single chamber from just inside its hole; up the shaft; along the winding climb
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
	local e = r.enclosure :: any
	local up = e.up or e.upAt[1].up
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
	for k, tt in { 0.12, 0.2, 0.55 } do
		local a, b = reg:pointAt(r, tt), reg:pointAt(r, tt + 0.03)
		add(
			`h1_climb_{k}`,
			"H1's winding climb at a squirrel's eye, looking along the way up",
			{ a.x, a.y + 1.0, a.z },
			{ b.x, b.y + 0.8, b.z },
			INSIDE,
			85
		)
	end
	-- looking up the hollow from the low chamber, as the look turned up shows it
	local low = h1.chambers[1]
	local cav = h1.cavities[#h1.cavities]
	add(
		"h1_look_up",
		"H1 from its low chamber, the look turned up the hollow: ledges, knots and the root across, daylight at the holes",
		{ low.x, low.y + 1.0, low.z },
		{ cav.x + (cav.x - low.x) * 0.3, low.y + 14, cav.z + (cav.z - low.z) * 0.3 },
		INSIDE,
		90
	)
end
-- the peeks: out of every hole up a trunk (the hollow look's eye at the hole's face, CameraRig.peekView, a little down)
for _, h in layout.hollows do
	local n = 0
	for _, m in h.mouths do
		if m.opens == "ground" then
			continue
		end
		n += 1
		local ex, ey, ez, vx, vy, vz = CameraRig.peekView(m :: any, 0, -0.35)
		local id = string.lower(h.id)
		add(
			`{id}_peek_{n}`,
			`{h.id}: peeking out of its {m.name} (the branch a hop lands on below)`,
			{ ex, ey, ez },
			{ ex + vx * 4, ey + vy * 4, ez + vz * 4 },
			PEEK,
			85
		)
		-- and that hole and its branch from outside, level with it
		local ol = math.sqrt(m.out[1] ^ 2 + m.out[3] ^ 2)
		local ox, oz = m.out[1] / ol, m.out[3] / ol
		add(
			`{id}_hole_{n}`,
			`{h.id}: its {m.name} and the branch under it, from outside`,
			{ m.x + ox * 9 - oz * 4, m.y + 2.5, m.z + oz * 9 + ox * 4 },
			{ m.x + ox * 2, m.y, m.z + oz * 2 },
			OUTSIDE,
			60
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
