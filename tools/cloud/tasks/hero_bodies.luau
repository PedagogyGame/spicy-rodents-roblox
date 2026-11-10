--!strict
-- Luau Execution task: the sculpted squirrel and Spicy Rodent as game bodies (Server/Assets/HeroArt).
-- Loads both uploads, installs the templates, builds one body of each through Actors/BodyFactory and
-- reports what a player would be handed: the root over the feet, the skin welded under it, the region
-- modes and tints, RigSpec, and where the mesh's lowest point sits against HipHeight.
--   node tools/cloud/cloud.mjs run_engine_tests tools/cloud/tasks/hero_bodies.luau --version <v> --place ci

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")

local server = ServerScriptService:WaitForChild("Server")
local HeroArt = (require :: any)(server.Assets.HeroArt)
local BodyFactory = (require :: any)(server.Actors.BodyFactory)
local RigSpec = (require :: any)(ReplicatedStorage.Shared.Actors.RigSpec)

local failures: { string } = {}
local report = HeroArt.install()
local bodies = {}
for _, case in { { "squirrel", "normal", "squirrel" }, { "squirrel", "spicy", "rodent" } } do
	local name = case[3]
	local rec: { [string]: any } = { template = name }
	if not table.find(report.installed, name) then
		table.insert(failures, `{name} not installed: {report.failed[name]}`)
		table.insert(bodies, rec)
		continue
	end
	local body = BodyFactory.build(case[1], case[2], 900 + #bodies)
	local root = body.PrimaryPart
	rec.hero = body:GetAttribute("Hero")
	rec.rootName = root.Name
	rec.rootAnchored = root.Anchored
	rec.hip = body:GetAttribute("HipHeight")
	local skin = body:FindFirstChild("SkinRoot")
	rec.skinAnchored = skin and skin.Anchored
	rec.skinUnderRoot = skin and (root.Position.Y - skin.Position.Y)
	local lowest, highest = math.huge, -math.huge
	local regions = {}
	for _, d in body:GetChildren() do
		if d:IsA("MeshPart") then
			lowest = math.min(lowest, d.Position.Y - d.Size.Y / 2)
			highest = math.max(highest, d.Position.Y + d.Size.Y / 2)
			local sa: any = d:FindFirstChildOfClass("SurfaceAppearance")
			regions[d.Name] = {
				mode = sa and tostring(sa.AlphaMode),
				color = sa and { sa.Color.R, sa.Color.G, sa.Color.B },
				canCollide = d.CanCollide,
				anchored = d.Anchored,
				skinned = d.HasSkinnedMesh,
			}
		end
	end
	rec.regions = regions
	rec.feetBelowRoot = root.Position.Y - lowest
	rec.topAboveRoot = highest - root.Position.Y
	local v = RigSpec.validate(body, name)
	rec.rigSpecOk = v.ok
	rec.variant = body:GetAttribute("Variant")
	rec.species = body:GetAttribute("Species")
	if rec.hero ~= true then
		table.insert(failures, `{name}: the body is not the hero model`)
	end
	if not v.ok then
		table.insert(failures, `{name}: RigSpec fails`)
	end
	if math.abs(rec.feetBelowRoot - rec.hip) > 0.12 then
		table.insert(failures, `{name}: feet {rec.feetBelowRoot} below the root, HipHeight {rec.hip}`)
	end
	if not rec.rootAnchored or rec.skinAnchored then
		table.insert(failures, `{name}: anchoring root={rec.rootAnchored} skin={rec.skinAnchored}`)
	end
	body:Destroy()
	table.insert(bodies, rec)
end
print(`hero_bodies: installed={table.concat(report.installed, ",")} failures={#failures}`)
for _, f in failures do
	print("  FAIL " .. f)
end
return { suite = "hero_bodies", ok = #failures == 0, failures = failures, install = report, bodies = bodies, placeVersion = game.PlaceVersion }
