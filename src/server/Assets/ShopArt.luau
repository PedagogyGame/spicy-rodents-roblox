--!strict
-- ServerScriptService.Server.Assets.ShopArt
-- The owner's Neighbourhood Shop (brief addendum D12): its baked shell (Workspace.Expansion.NeighbourhoodShop,
-- tools/bake/neighbourhood_shop.luau) holds the walls, colliders, camera occluders, lamps and steps; his
-- interior and his gable roof are uploaded Models (data/art/neighbourhood_shop.json -> Shared/Generated/ShopArt)
-- that this module loads into the shell at boot. The venue model names them (attributes ArtShop, ArtRoof) and
-- gives the frame (ArtPivot, a CFrame: the centre of the shop floor, facing the street).
--   carve(venue)      the shell's TerrainCarve boxes to air (the ground is half a stud under the floor at the back)
--   prepare(model)    makes every part visual only (anchored; no collision, touch or queries: the shell's
--                     colliders from his metadata do that), paints a MeshPart the importer left without a
--                     SurfaceAppearance or texture (an untextured one with its material's colour, a textured one
--                     with its map's mean colour), makes his glass see-through and his lamp shades glow (Neon:
--                     the engine draws no emissive material from a file)
--   place(model)      pivots the Model onto ArtPivot and puts any part whose centre is off by more than SNAP back
--                     where his file has it (MeshParts arrive unrotated: the export applied every transform)
--   boxes(model)      every mesh his file has as a plain box (12 triangles, untextured: 45 in the shop, all 90 in
--                     the roof) is drawn as an ordinary Part of the same size, place, turn and colour, so the
--                     engine batches them (it draws each distinct mesh on its own)
--   install(venue)    all of the above for both Models
--   run(root)         every venue under `root` with ArtShop; a Model that fails to load leaves a walkable shell
--   start(root, opts) the boot's one call (Boot/Game): carves, then runs off the boot path, and warns when
--                     generated/ShopArt names a shop that has no baked venue (its bake was not run)
-- Art only: nothing here sells, seats or dresses anyone (the pack's own rule).
-- Interface: venues(root) -> { Model }; carve(venue, opts?) -> n; prepare(model, data, env?) -> report;
--   place(model, pivot, data, env?) -> snapped; boxes(model, pivot, data, env?) -> n; install(venue, opts?) ->
--   report; run(root, opts?) -> report; start(root?, opts?) -> { venues, missing? }; missing(root?, data) -> string?
-- No side effects on require.

local Import = require("../Import")

local ShopArt = {}

ShopArt.SNAP = 0.5 -- studs: a part further than this from its place in his file is moved there
ShopArt.GLASS_TRANSPARENCY = 0.7

export type Env = { CFrame: any, Color3: any, Enum: any, Instance: any, Vector3: any }
export type Opts = {
	load: ((assetId: number) -> Instance)?, -- default InsertService:LoadAsset
	data: any?, -- default Shared/Generated/ShopArt
	env: Env?, -- default the engine's CFrame, Color3, Enum, Instance and Vector3 (Lune specs pass @lune/roblox)
	fill: ((cframe: any, size: any) -> ())?, -- default Terrain:FillBlock(cframe, size, Air)
}

local function engineEnv(): Env
	return { CFrame = CFrame, Color3 = Color3, Enum = Enum, Instance = Instance, Vector3 = Vector3 }
end

local function generated(): any
	return Import.shared("Generated/ShopArt") :: any
end

-- Every venue model under `root` that names an uploaded shop.
function ShopArt.venues(root: Instance): { Model }
	local out: { Model } = {}
	for _, d in root:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("ArtShop") ~= nil then
			table.insert(out, d)
		end
	end
	return out
end

function ShopArt.carve(venue: Instance, opts: Opts?): number
	local o: Opts = opts or {}
	local fill = o.fill
		or function(cframe: any, size: any)
			workspace.Terrain:FillBlock(cframe, size, Enum.Material.Air)
		end
	local folder = venue:FindFirstChild("TerrainCarve")
	local n = 0
	if folder then
		for _, p in folder:GetChildren() do
			if p:IsA("BasePart") then
				fill(p.CFrame, p.Size)
				n += 1
			end
		end
	end
	return n
end

-- name -> the mesh's record (colour, glass, at) from the generated data, shop and roof together
local function byName(data: any): { [string]: any }
	local out: { [string]: any } = {}
	for _, list in { data.shop, data.roofParts } do
		for _, rec in list do
			out[rec.name] = rec
		end
	end
	return out
end

function ShopArt.prepare(
	model: Instance,
	data: any,
	env: Env?
): { parts: number, painted: number, glass: number, glowing: number }
	local e = env or engineEnv()
	local recs = byName(data)
	local parts, painted, glass, glowing = 0, 0, 0, 0
	local function rgb(c: { number }): any
		return e.Color3.fromRGB(c[1], c[2], c[3])
	end
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			parts += 1
			d.Anchored = true
			d.CanCollide = false
			d.CanTouch = false
			d.CanQuery = false
			local rec = recs[d.Name]
			if rec and rec.glass then
				local appearance = d:FindFirstChildOfClass("SurfaceAppearance")
				if appearance then
					appearance:Destroy()
				end
				d.Material = e.Enum.Material.Glass
				d.Transparency = ShopArt.GLASS_TRANSPARENCY
				d.CastShadow = false
				d.Color = rgb(rec.colour)
				glass += 1
			elseif rec and rec.emissive then
				-- his lamp shades' diffusers: the glTF emissive material arrives as a plain colour
				d.Material = e.Enum.Material.Neon
				d.Color = rgb(rec.colour)
				d.CastShadow = false
				glowing += 1
			elseif rec and d:IsA("MeshPart") and d:FindFirstChildOfClass("SurfaceAppearance") == nil then
				-- (a MeshPart made in Lune has no TextureID to read: treat it as none)
				local okT, texture = pcall(function(): any
					return (d :: any).TextureID
				end)
				if not okT or texture == nil or texture == "" then
					d.Color = rgb(if rec.textured and rec.fallback then rec.fallback else rec.colour)
					d.Material = e.Enum.Material.SmoothPlastic
					painted += 1
				end
			end
		end
	end
	return { parts = parts, painted = painted, glass = glass, glowing = glowing }
end

-- Pivots the Model onto the shop's frame, then moves any part that is not where his file has it.
function ShopArt.place(model: Model, pivot: any, data: any, env: Env?): number
	local e = env or engineEnv()
	local recs = byName(data)
	-- the imported Model's pivot is the FBX origin (the tree models measured so, data/art/trees.json); a part
	-- that is not where his file puts it is moved there (Lune's Instances have no PivotTo: every part moves)
	pcall(function()
		model:PivotTo(pivot)
	end)
	local snapped = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			local rec = recs[d.Name]
			if rec and rec.at then
				local want = pivot * e.CFrame.new(rec.at[1], rec.at[2], rec.at[3])
				if (d.CFrame.Position - want.Position).Magnitude > ShopArt.SNAP then
					d.CFrame = want
					snapped += 1
				end
			end
		end
	end
	return snapped
end

-- His plain boxes as Parts: same size, place, turn and colour; visual only, like the rest of his art.
function ShopArt.boxes(model: Instance, pivot: any, data: any, env: Env?): number
	local e = env or engineEnv()
	local recs = byName(data)
	local n = 0
	for _, d in model:GetDescendants() do
		local rec = if d:IsA("MeshPart") then recs[d.Name] else nil
		if rec and rec.box and not rec.glass and not rec.emissive and not rec.textured then
			local at = e.Vector3.new(rec.at[1], rec.at[2], rec.at[3])
			local frame = if rec.right
				then e.CFrame.fromMatrix(
					at,
					e.Vector3.new(rec.right[1], rec.right[2], rec.right[3]),
					e.Vector3.new(rec.up[1], rec.up[2], rec.up[3])
				)
				else e.CFrame.new(rec.at[1], rec.at[2], rec.at[3])
			local p = e.Instance.new("Part")
			p.Name = d.Name
			p.Size = e.Vector3.new(rec.box[1], rec.box[2], rec.box[3])
			p.CFrame = pivot * frame
			p.Anchored = true
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = false
			p.CastShadow = (d :: BasePart).CastShadow
			p.Material = e.Enum.Material.SmoothPlastic
			p.Color = e.Color3.fromRGB(rec.colour[1], rec.colour[2], rec.colour[3])
			p.TopSurface = e.Enum.SurfaceType.Smooth
			p.BottomSurface = e.Enum.SurfaceType.Smooth
			p.Parent = d.Parent
			d:Destroy()
			n += 1
		end
	end
	return n
end

local function modelOf(asset: Instance): Model?
	if asset:IsA("Model") and #asset:GetChildren() == 1 and asset:GetChildren()[1]:IsA("Model") then
		return asset:GetChildren()[1] :: Model
	end
	if asset:IsA("Model") then
		return asset :: Model
	end
	return nil
end

export type Report = {
	loaded: { string },
	failed: { string },
	parts: number,
	painted: number,
	glass: number,
	glowing: number,
	boxes: number,
	snapped: number,
}

function ShopArt.install(venue: Model, opts: Opts?): Report
	local o: Opts = opts or {}
	local data = o.data or generated()
	local load: (assetId: number) -> Instance = o.load
		or function(assetId: number): Instance
			return game:GetService("InsertService"):LoadAsset(assetId)
		end
	local pivot = venue:GetAttribute("ArtPivot")
	local report: Report =
		{ loaded = {}, failed = {}, parts = 0, painted = 0, glass = 0, glowing = 0, boxes = 0, snapped = 0 }
	for _, which in { "Shop", "Roof" } do
		local id = tonumber(venue:GetAttribute(`Art{which}`))
		local name = `Art{which}`
		if id == nil or pivot == nil or venue:FindFirstChild(name) then
			continue
		end
		local ok, asset = pcall(function(): Instance
			return load(id :: number)
		end)
		local model = if ok and asset then modelOf(asset) else nil
		if model == nil then
			table.insert(report.failed, `{which} {id}: {if ok then "no Model in the asset" else tostring(asset)}`)
			continue
		end
		local m = model :: Model
		local r = ShopArt.prepare(m, data, o.env)
		report.snapped += ShopArt.place(m, pivot, data, o.env)
		report.boxes += ShopArt.boxes(m, pivot, data, o.env)
		report.parts += r.parts
		report.painted += r.painted
		report.glass += r.glass
		report.glowing += r.glowing
		m.Name = name
		m.Parent = venue
		if asset ~= m then
			(asset :: Instance):Destroy()
		end
		table.insert(report.loaded, which)
	end
	venue:SetAttribute("ArtLoaded", table.concat(report.loaded, ","))
	return report
end

-- Every shop under `root` (Workspace.Expansion). Yields while the Models load: call it from a task.
function ShopArt.run(root: Instance, opts: Opts?): { venues: number, reports: { Report } }
	local reports: { Report } = {}
	local list = ShopArt.venues(root)
	for _, venue in list do
		table.insert(reports, ShopArt.install(venue, opts))
	end
	return { venues = #list, reports = reports }
end

-- The shops generated/ShopArt names that have no baked venue under `root`: a message, or nil when all are there.
function ShopArt.missing(root: Instance?, data: any): string?
	if data == nil or data.venue == nil then
		return nil
	end
	local list: { Model } = if root then ShopArt.venues(root) else {}
	for _, v in list do
		if v:GetAttribute("Venue") == data.venue then
			return nil
		end
	end
	return `{data.venue} is in generated/ShopArt but Workspace.Expansion has no baked shop for it: run `
		.. "lune run tools/bake/neighbourhood_shop.luau before building the place"
end

export type StartOpts = Opts & {
	terrain: boolean?, -- carve the terrain inside each shop (default true)
	heartbeat: boolean?, -- load the Models off the boot path (default true; false in the headless rig)
	spawn: ((() -> ()) -> ())?, -- default task.spawn
	print: ((string) -> ())?,
	warn: ((string) -> ())?,
}

-- The boot's one call (Boot/Game, after the town is ready): carve now, load his Models off the boot path.
function ShopArt.start(root: Instance?, opts: StartOpts?): { venues: number, missing: string? }
	local o: StartOpts = opts or {}
	local say: (string) -> () = o.print or function(m: string)
		print(m)
	end
	local complain: (string) -> () = o.warn or function(m: string)
		warn(m)
	end
	local okD, data = pcall(function(): any
		return o.data or generated()
	end)
	local shops: { Model } = if root then ShopArt.venues(root) else {}
	local missing = ShopArt.missing(root, if okD then data else nil)
	if missing then
		complain(`[SpicyRodents] shop art: {missing}`)
	end
	if o.terrain ~= false then
		for _, shop in shops do
			pcall(ShopArt.carve, shop, o)
		end
	end
	if #shops > 0 and o.heartbeat ~= false then
		local spawn = o.spawn or function(f: () -> ())
			task.spawn(f)
		end
		spawn(function()
			local okS, report = pcall(ShopArt.run, root :: Instance, o)
			if okS then
				for i, r in report.reports do
					say(
						`[SpicyRodents] shop art {i}: loaded {table.concat(r.loaded, ", ")}; {r.parts} parts, {r.boxes} drawn as plain parts, {r.painted} painted, {r.glass} glass, {r.glowing} glowing, {r.snapped} moved into place`
					)
					for _, f in r.failed do
						complain(`[SpicyRodents] shop art: {f} (the shell stands without it)`)
					end
				end
			else
				complain(`[SpicyRodents] shop art failed: {report}`)
			end
		end)
	end
	return { venues = #shops, missing = missing }
end

return ShopArt
