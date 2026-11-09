--!strict
-- Tree art harvest: InsertService:LoadAsset on the uploaded tree Models (data/art/trees.json) and a
-- dump of every MeshPart's properties (mesh, size, offset from the Model pivot, SurfaceAppearance
-- maps) so the bake can write the same MeshParts straight into build/Town.rbxm.
-- The TREES table is filled in by tools/blender/trees/harvest_meshes.py (batches of 24):
--   python3 -I tools/blender/trees/harvest_meshes.py --version <ciVersion>
-- which writes data/art/tree_meshes.json.

local TREES: { { index: number, assetId: number } } = {} -- @@TREES@@

local InsertService = game:GetService("InsertService")

local function r4(x: number): number
	return math.round(x * 10000) / 10000
end
local function vec(v: Vector3): { number }
	return { r4(v.X), r4(v.Y), r4(v.Z) }
end

local result: { [string]: any } = { suite = "tree_harvest", trees = {} }
local ok = true

for _, spec in TREES do
	local entry: { [string]: any } = { index = spec.index, assetId = spec.assetId }
	local good, model = pcall(function()
		return InsertService:LoadAsset(spec.assetId)
	end)
	if not good then
		entry.error = tostring(model)
		ok = false
		table.insert(result.trees, entry)
		continue
	end
	local tree: Instance = model
	local kids = model:GetChildren()
	if #kids == 1 and kids[1]:IsA("Model") then
		tree = kids[1]
	end
	entry.name = tree.Name
	local pivot = if tree:IsA("Model") then (tree :: Model):GetPivot() else CFrame.new()
	local parts = {}
	local others: { [string]: number } = {}
	for _, d in tree:GetDescendants() do
		if d:IsA("MeshPart") then
			local rel = pivot:ToObjectSpace(d.CFrame)
			local rx, ry, rz = rel:ToOrientation()
			local p: { [string]: any } = {
				name = d.Name,
				meshId = d.MeshId,
				textureId = d.TextureID,
				size = vec(d.Size),
				meshSize = vec(d.MeshSize),
				offset = vec(rel.Position),
				rot = { r4(rx), r4(ry), r4(rz) },
				color = { math.round(d.Color.R * 255), math.round(d.Color.G * 255), math.round(d.Color.B * 255) },
				material = d.Material.Name,
				transparency = d.Transparency,
				doubleSided = d.DoubleSided,
				renderFidelity = d.RenderFidelity.Name,
				collisionFidelity = d.CollisionFidelity.Name,
			}
			local sa = d:FindFirstChildOfClass("SurfaceAppearance")
			if sa then
				-- the string map properties are plugin-only; the Content properties are readable
				local function uri(prop: string): string
					local read, v = pcall(function()
						return ((sa :: any)[prop] :: any).Uri
					end)
					return if read then tostring(v) else "ERR " .. tostring(v)
				end
				p.surface = {
					colorMap = uri("ColorMapContent"),
					normalMap = uri("NormalMapContent"),
					roughnessMap = uri("RoughnessMapContent"),
					metalnessMap = uri("MetalnessMapContent"),
					alphaMode = sa.AlphaMode.Name,
					color = { math.round(sa.Color.R * 255), math.round(sa.Color.G * 255), math.round(sa.Color.B * 255) },
				}
			end
			table.insert(parts, p)
		else
			others[d.ClassName] = (others[d.ClassName] or 0) + 1
		end
	end
	table.sort(parts, function(a, b)
		return a.name < b.name
	end)
	entry.parts = parts
	entry.others = others
	table.insert(result.trees, entry)
	model:Destroy()
end

result.ok = ok
return result
