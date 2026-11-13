--!strict
-- ServerStorage.EngineTests.Sewers (CI place only). Written for the day Open Cloud Luau Execution works for the key
-- again (lost 2026-11-11): nothing runs it yet. Its task script would be tools/cloud/tasks/sewers_smoke.luau, the
-- same shape as backdrop_smoke.luau (require this module, run(), print and return the result).
-- The storm drains in the real engine (BRIEF_ADDENDUM D8; Shared/World/SewerLayout, the bake build/Sewers.rbxm as
-- Workspace.Sewers, Server/World/SewerService), the things only the engine can say:
--   * the carve: WorldGen/WorldTerrain writes the town's terrain, then SewerService.start carves as Boot/Game does;
--     read back, the terrain is air along every passage of every pipe (at the body's middle over each route point,
--     every stud), and solid one voxel over every passage carve's top wherever the ground stands that high (the
--     street keeps its skin over the pipes); the shaft columns are open from the bottom of the shaft to the street
--   * Workspace.Sewers as published: each pipe a Model streamed whole (Atomic), every light baked off, the part
--     budget, every Lining part colliding, the art slots there
--   * the owner's modules (data/art/sewer_modules.json): each ArtAsset loads (InsertService), is one Model whose
--     meshes stand upright and centred on the pivot as the export assumed (the bounding box, in the pivot's frame,
--     against the union of the manifest's mesh boxes): what S1 could not see without the engine
--   * the service in the engine: the cover is on the town AI's world, and it stops cleanly
-- Interface: run() -> Result { ok, failures, numbers } (JSON-friendly); samples(layout) -> { {pipe, x, y, z} } (pure:
--   the points the carve is read at; tests/unit/sewers_play holds them inside the layout's pipes and ART_BOX to the
--   manifest); BUDGET; STEP; BODY_MID; ART_BOX; ART_TOL. Engine calls only inside run.

local Sewers = {}

Sewers.BUDGET = 700 -- parts in Workspace.Sewers (tests/unit/sewers_bake)
Sewers.STEP = 1 -- studs between samples along a passage
Sewers.BODY_MID = 0.85 -- studs over the walkway: the middle of the squirrel's 1.7-stud body
Sewers.BEND = 1 -- studs either side of a passage's bend left out of the samples
Sewers.ART_TOL = 0.15 -- studs: an imported module's box may differ this much from the manifest's
-- Each module's box in its own frame (X across, Y up, Z along; the pivot is the module origin): the union of the mesh
-- boxes in data/art/sewer_modules.json (modules.<key>.meshes, centre +- size / 2), which is not in the place. If the
-- manifest is exported again, take these from it again.
Sewers.ART_BOX = {
	brick = { size = { 6.64, 6.5, 12 }, centre = { 0, 2.27, 0 } },
	brickPlain = { size = { 6.64, 6.5, 12 }, centre = { 0, 2.27, 0 } },
	junction = { size = { 12, 6.54, 12 }, centre = { 0, 2.25, 0 } },
	dry = { size = { 6.64, 5.96, 12 }, centre = { 0, 2.54, 0 } },
	dryPlain = { size = { 6.64, 5.96, 12 }, centre = { 0, 2.54, 0 } },
	marker = { size = { 0.64, 0.36, 0.01 }, centre = { 0, 0.18, 0 } },
} :: { [string]: { size: { number }, centre: { number } } }

-- the terrain's material and occupancy at one point (the 4-stud voxel holding it)
local function voxel(x: number, y: number, z: number): (string, number)
	local gx, gy, gz = math.floor(x / 4) * 4, math.floor(y / 4) * 4, math.floor(z / 4) * 4
	local mats, occs =
		workspace.Terrain:ReadVoxels(Region3.new(Vector3.new(gx, gy, gz), Vector3.new(gx + 4, gy + 4, gz + 4)), 4)
	return mats[1][1][1].Name, occs[1][1][1]
end

-- samples(layout): every Sewers.STEP studs along every passage of every pipe, the route line (the passage axis moved
-- `offset` toward the walkway: SewerLayout's left is (dz, -dx), `side` +1 when the walkway is on the left) raised
-- to the middle of the body
function Sewers.samples(layout: any): { { pipe: string, x: number, y: number, z: number } }
	local out = {}
	for _, pipe in layout.pipes do
		for _, pass in pipe.passages do
			local pts = pass.points
			for i = 1, #pts - 1 do
				local a, b = pts[i], pts[i + 1]
				local dx, dz = b.x - a.x, b.z - a.z
				local len = math.sqrt(dx * dx + dz * dz)
				if len > 1e-6 then
					local lx, lz = dz / len, -dx / len
					local n = math.max(1, math.floor(len / Sewers.STEP))
					for k = 0, n - 1 do
						local u = k / n
						-- (at a bend the route is mitred and curved, not this straight offset: a stud either side is left out)
						local nearBend = (i > 1 and u * len < Sewers.BEND)
							or (i + 1 < #pts and (1 - u) * len < Sewers.BEND)
						if not nearBend then
							table.insert(out, {
								pipe = pipe.id,
								x = a.x + dx * u + lx * pass.side * pass.offset,
								y = a.y + (b.y - a.y) * u + Sewers.BODY_MID,
								z = a.z + dz * u + lz * pass.side * pass.offset,
							})
						end
					end
				end
			end
		end
	end
	return out
end

function Sewers.run(): { [string]: any }
	local InsertService = game:GetService("InsertService")
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local ServerScriptService = game:GetService("ServerScriptService")
	local failures: { string } = {}
	local numbers: { [string]: any } = {}
	local function check(cond: boolean, msg: string)
		if not cond then
			table.insert(failures, msg)
		end
	end
	local shared = ReplicatedStorage:WaitForChild("Shared")
	local server = ServerScriptService:WaitForChild("Server")
	local SewerLayout = (require :: any)(shared:WaitForChild("World"):WaitForChild("SewerLayout"))
	local Height = (require :: any)(shared:WaitForChild("World"):WaitForChild("Height"))
	local layout = SewerLayout.default()
	check(layout ~= nil, "no sewer layout (generated/Sewers.luau not compiled into the place)")
	if layout == nil then
		return { ok = false, failures = failures, numbers = numbers }
	end

	-- the carve, as Boot/Game: the terrain first, then the service --------------------------------------------
	local t0 = os.clock()
	local WorldTerrain = (require :: any)(server:WaitForChild("WorldGen"):WaitForChild("WorldTerrain"))
	WorldTerrain.write(workspace.Terrain)
	numbers.terrainSeconds = os.clock() - t0
	local Data = (require :: any)(shared:WaitForChild("Data"))
	local TownAI = (require :: any)(server:WaitForChild("AI"):WaitForChild("TownAI"))
	local SewerService = (require :: any)(server:WaitForChild("World"):WaitForChild("SewerService"))
	local world = TownAI.build({ data = Data.default(), seed = 1, humans = 4, squirrels = 1, deer = 0, fox = 0 })
	local t1 = os.clock()
	local svc = SewerService.start({ world = world, layout = layout })
	numbers.carveSeconds = os.clock() - t1
	numbers.carved = svc.carved
	check(svc.carved == #layout.carveBoxes(), `carved {svc.carved} of {#layout.carveBoxes()} boxes`)
	check(world.cover ~= nil, "the cover is not on the town AI")

	-- air along every passage, at the body's middle over the route line
	local samples, solid = 0, 0
	local firstSolid: string? = nil
	for _, q in Sewers.samples(layout) do
		local mat, occ = voxel(q.x, q.y, q.z)
		samples += 1
		if mat ~= "Air" and occ > 0 then
			solid += 1
			firstSolid = firstSolid or `{q.pipe} ({q.x}, {q.y}, {q.z}): {mat} {occ}`
		end
	end
	numbers.passageSamples = samples
	check(samples > 500, `only {samples} passage samples`)
	check(solid == 0, `{solid} passage samples in terrain, first {firstSolid}`)

	-- the street keeps its skin: solid one voxel over each passage carve's top where the ground stands that high
	local skins, holes = 0, 0
	local firstHole: string? = nil
	for _, box in layout.carveBoxes() do
		if box.kind == "passage" then
			local cx, cz = (box.x0 + box.x1) / 2, (box.z0 + box.z1) / 2
			if Height.at(cx, cz) >= box.y1 + 4 then
				local mat, occ = voxel(cx, box.y1 + 2, cz)
				skins += 1
				if mat == "Air" or occ <= 0 then
					holes += 1
					firstHole = firstHole or `({cx}, {box.y1 + 2}, {cz})`
				end
			end
		end
	end
	numbers.crownVoxels = skins
	check(skins > 0, "no passage carve under standing ground to test")
	check(holes == 0, `{holes} passage carves open to the sky, first at {firstHole}`)

	-- the shafts: open from the shaft's bottom to the street
	local shut = 0
	for _, m in layout.mouths do
		local s = m.shaft
		local y = s.bottom + 1
		while y < s.top - 1 do
			local mat, occ = voxel(s.cx, y, s.cz)
			if mat ~= "Air" and occ > 0 then
				shut += 1
				table.insert(failures, `{m.id}: the shaft is filled at y {y} ({mat})`)
				break
			end
			y += 2
		end
	end
	numbers.shutShafts = shut

	-- Workspace.Sewers as published ------------------------------------------------------------------------
	local root = workspace:FindFirstChild("Sewers")
	check(root ~= nil, "Workspace.Sewers missing (lune run tools/bake/sewers.luau before rojo build)")
	local slots: { { asset: string, module: string, name: string } } = {}
	if root then
		local parts, lit, looseLining = 0, 0, 0
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") then
				parts += 1
				if d:FindFirstAncestor("Lining") and not d.CanCollide then
					looseLining += 1
				end
			elseif d:IsA("Light") and d.Enabled then
				lit += 1
			elseif d:IsA("Model") and d.Parent and d.Parent.Name == "Art" then
				local asset = d:GetAttribute("ArtAsset")
				if type(asset) == "string" and asset ~= "" then
					table.insert(
						slots,
						{ asset = asset, module = tostring(d:GetAttribute("ArtModule")), name = d.Name }
					)
				end
			end
		end
		numbers.parts = parts
		numbers.artSlots = #slots
		check(parts > 0 and parts <= Sewers.BUDGET, `{parts} parts (budget {Sewers.BUDGET})`)
		check(lit == 0, `{lit} lights baked on`)
		check(looseLining == 0, `{looseLining} Lining parts without collision`)
		for _, p in layout.pipes do
			local model = root:FindFirstChild(p.id)
			check(model ~= nil and model:IsA("Model"), `Workspace.Sewers.{p.id} missing`)
			if model and model:IsA("Model") then
				check(model.ModelStreamingMode == Enum.ModelStreamingMode.Atomic, `{p.id} is not streamed whole`)
			end
		end
		check(#slots > 0, "no art slots")
	end

	-- the owner's modules, imported ----------------------------------------------------------------------------
	local loaded: { [string]: boolean } = {}
	for _, slot in slots do
		if loaded[slot.asset] == nil then
			local ok, res = pcall(function()
				return InsertService:LoadAsset(tonumber(slot.asset) :: number)
			end)
			loaded[slot.asset] = ok
			check(ok, `{slot.module} ({slot.asset}) did not load: {res}`)
			local model = if ok then (res :: Instance):GetChildren()[1] else nil
			check(not ok or (model ~= nil and model:IsA("Model")), `{slot.module}: the asset is not one Model`)
			if model and model:IsA("Model") then
				local cf, size = model:GetBoundingBox()
				local centre = model:GetPivot():PointToObjectSpace(cf.Position)
				numbers[`art_{slot.module}`] =
					{ size = { size.X, size.Y, size.Z }, centre = { centre.X, centre.Y, centre.Z } }
				local want = Sewers.ART_BOX[slot.module]
				if want then
					local wantSize = Vector3.new(want.size[1], want.size[2], want.size[3])
					local wantCentre = Vector3.new(want.centre[1], want.centre[2], want.centre[3])
					check(
						(wantSize - size).Magnitude < Sewers.ART_TOL,
						`{slot.module}: imported box {size} vs the manifest's {wantSize} (turned on import?)`
					)
					check(
						(wantCentre - centre).Magnitude < Sewers.ART_TOL,
						`{slot.module}: centre {centre} vs the manifest's {wantCentre} (pivot not at the module origin?)`
					)
				end
			end
		end
	end

	svc:stop()
	check(world.cover == nil, "the cover stayed on after stop")
	return { ok = #failures == 0, failures = failures, numbers = numbers }
end

return Sewers
