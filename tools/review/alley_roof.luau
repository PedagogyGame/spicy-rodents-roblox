--!strict
-- tools/review/alley_roof: adds the roof run's yard (tools/bake/alley/Yard: the house and the tree, which are not in
-- build/Attractions.rbxm yet) to a review scene exported by tools/review/export.luau, with two review-only extras:
-- the roof run's routes drawn as thin bright rods (group "routes": yellow the way up, orange the leap's flight with no
-- key held, cyan the vent and the rafters, which have no building yet) and a few squirrels (the placeholder puppet)
-- standing where the motor puts one (group "squirrels"). Views pick the groups (tools/review/views_alley_roof.json).
-- Usage (repo root), after the bakes (tools/bake/main.luau, editor_ground.luau, attractions.luau, backdrop.luau):
--   lune run tools/review/export.luau --out build/review_roof/scene.json
--   lune run tools/review/alley_roof.luau [--scene build/review_roof/scene.json] [--placeholders assets/placeholders]
--   <bpy python> -I tools/review/render.py --scene build/review_roof/scene.json \
--       --views tools/review/views_alley_roof.json --out build/review_roof --threads 2
-- Committed pictures: docs/renders/alley_roof/.
local fs = require("@lune/fs")
local process = require("@lune/process")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local AlleyLayout = require("../../src/shared/Attractions/AlleyLayout")
local AlleyRoof = require("../../src/shared/Attractions/AlleyRoof")
local Curve = require("../../src/shared/Routes/Curve")
local SquirrelMotor = require("../../src/shared/Movement/SquirrelMotor")
local Kit = require("../bake/alley/Kit")
local Yard = require("../bake/alley/Yard")

local scenePath = "build/review_roof/scene.json"
local placeholders = "assets/placeholders"
local i = 1
while i <= #process.args do
	local a = process.args[i]
	if a == "--scene" then
		scenePath = process.args[i + 1]
		i += 1
	elseif a == "--placeholders" then
		placeholders = process.args[i + 1]
		i += 1
	else
		error("unknown argument: " .. a)
	end
	i += 1
end

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
	if p.ClassName == "Part" then
		return p.Shape.Name
	elseif p.ClassName == "WedgePart" then
		return "Wedge"
	end
	return "Box"
end

local scene = serde.decode("json", fs.readFile(scenePath))
scene.stats.groups = scene.stats.groups or {}
-- run twice on one scene: the first run's additions are replaced, not doubled
do
	local kept = {}
	for _, p in scene.parts do
		if string.sub(p.p, 1, 15) ~= "AlleyRoofReview" then
			table.insert(kept, p)
		end
	end
	scene.parts = kept
end
local added: { [string]: number } = {}
local function emit(group: string, p: any, cf: any?)
	if p.Transparency >= 0.95 then
		return
	end
	local c = cf or p.CFrame
	table.insert(scene.parts, {
		g = group,
		p = p:GetFullName(),
		s = shapeOf(p),
		size = v3(p.Size),
		pos = v3(c.Position),
		rot = rotOf(c),
		c = rgb(p.Color),
		t = math.floor(p.Transparency * 100 + 0.5) / 100,
		m = p.Material.Name,
	})
	added[group] = (added[group] or 0) + 1
	scene.stats.groups[group] = (scene.stats.groups[group] or 0) + 1
end

local doc = serde.decode("json", fs.readFile("data/attractions.json"))
local alley = doc.attractions[1]
local place: AlleyLayout.Place =
	{ x = alley.place.x, z = alley.place.z, floorY = alley.place.floorY, yaw = alley.place.yaw }
local kit = Kit.new(roblox, place)
local holder = roblox.Instance.new("Model")
holder.Name = "AlleyRoofReview"
local yard = Yard.build(kit, holder)
for _, d in yard:GetDescendants() do
	if d:IsA("BasePart") then
		emit("attractions", d)
	end
end

-- the routes as rods (review only)
local guides = kit:model(holder, "Routes")
local YELLOW, ORANGE, CYAN = { 255, 214, 40 }, { 255, 120, 30 }, { 60, 220, 255 }
local function polyline(name: string, pts: { any }, color: { number }, d: number)
	for k = 1, #pts - 1 do
		local a, b = pts[k], pts[k + 1]
		kit:rod(guides, `{name}_{k}`, a[1], a[2], a[3], b[1], b[2], b[3], d, color, "Neon")
	end
end
for _, r in AlleyRoof.routes() do
	local c = Curve.fromArrays(r.points)
	local n = math.max(2, math.ceil(c:getLength() / 1.5))
	local pts = {}
	for k = 0, n do
		local p = c:getPointAt(k / n)
		table.insert(pts, { p.x, p.y, p.z })
	end
	local inside = r.kind == "tunnel" or AlleyRoof.isRafter(r.id)
	polyline(`R{r.id}`, pts, if inside then CYAN else YELLOW, if inside then 0.18 else 0.22)
end
-- the leap's flight off the ridge's west end with no key held (the motor's numbers, drawn ballistic with air drag)
do
	local P = SquirrelMotor.params
	local e = AlleyRoof.route(9103).points[2]
	local X, Y, D = e[1], e[2], e[3]
	local vx, vy = -P.leapForward, P.leapUp
	local pts = { { X, Y, D } }
	for _ = 1, 30 do
		local dt = 1 / 60
		vx *= math.exp(-dt * P.dragAir)
		vy -= P.gravity * dt
		X += vx * dt
		Y += vy * dt
		table.insert(pts, { X, Y, D })
	end
	polyline("Leap", pts, ORANGE, 0.2)
end
for _, d in guides:GetDescendants() do
	if d:IsA("BasePart") then
		emit("routes", d)
	end
end

-- squirrels where the motor puts one: { local feet point, local heading (dX, dD) }
local file = `{placeholders}/squirrel.rbxm`
if fs.isFile(file) then
	local model = roblox.deserializeModel(fs.readFile(file))[1]
	local hip = model:GetAttribute("HipHeight") or 0
	local rootPart = model.PrimaryPart
	local rootCF = if rootPart then rootPart.CFrame else roblox.CFrame.new()
	local function bough(id: number, t: number): ({ number }, { number })
		local c = Curve.fromArrays(AlleyRoof.route(id).points)
		local p = c:getPointAt(t)
		local tg = c:getTangentAt(t)
		return { p.x, p.y + 1.25, p.z }, { tg.x, tg.z }
	end
	local ridgeEnd = AlleyRoof.route(9103).points[2]
	local onBough, boughDir = bough(9105, 0.62)
	local crossing = AlleyRoof.route(9106).points
	local roofEnd = crossing[#crossing]
	local spot = {
		{ { ridgeEnd[1] + 0.6, ridgeEnd[2], ridgeEnd[3] }, { -1, 0 } }, -- at the ridge's end, about to leap
		{ onBough, { -boughDir[1], -boughDir[2] } }, -- on the house bough, heading down to the fork
		{ { roofEnd[1] - 1, AlleyRoof.WING_ROOF.y, roofEnd[3] }, { -1, -0.1 } }, -- dropped onto the wing roof
	}
	for k, s in spot do
		local f, h = s[1], s[2]
		local x, y, z = AlleyLayout.toWorld(place, f[1], f[2] + hip, f[3])
		local dx, dz = AlleyLayout.dirToWorld(place, h[1], h[2])
		local pos = roblox.Vector3.new(x, y, z)
		local target = roblox.CFrame.lookAt(pos, pos + roblox.Vector3.new(dx, 0, dz))
		for _, d in model:GetDescendants() do
			if d:IsA("BasePart") then
				emit("squirrels", d, target * rootCF:Inverse() * d.CFrame)
			end
		end
		local _ = k
	end
else
	print(`alley_roof: {file} missing: no squirrels in the pictures`)
end

fs.writeFile(scenePath, serde.encode("json", scene))
local parts = {}
for g, n in added do
	table.insert(parts, `{g} {n}`)
end
table.sort(parts)
print(`alley_roof: added {table.concat(parts, ", ")} -> {scenePath}`)
