--!strict
-- StarterPlayerScripts.Client.World.BranchNookView
-- The branch nooks drawn on the trees near the camera (owner D34; where: Shared/World/BranchNooks; how:
-- Client/World/BranchNookArt). Every client draws the same thing from the same data, so every player sees every nook;
-- none of it is in the baked town (the town's 27,000-part budget is untouched) and at most a few trees' worth exists
-- at once:
--   * a tree's nooks, stashes, hangouts and spurs (BranchNookArt.build) while its trunk is within C.show studs (level)
--     of the camera, gone past C.hide; one tree built per look (C.every s), so a run into the park never builds
--     a dozen in one frame;
--   * the nodules (knots on the run paths) of the one tree whose trunk is nearest the camera within C.knots studs, at
--     most C.knotMax of them;
--   * this player's own nuts in their stashes (the attribute NutStashes the server writes: Foraging/BranchStash) as
--     acorns in the knot-holes of the trees drawn.
-- Parts: none solid, none queried or touched, no shadows. Under Workspace.BranchNooks (this client's).
-- Interface: start() -> stop(); C
-- No side effects on require.

local Import = require("../Import")
local BranchNooks = Import.shared("World/BranchNooks") :: typeof(require("../../shared/World/BranchNooks"))
local Data = Import.shared("Data") :: typeof(require("../../shared/Data"))
local BranchNookArt = require("./BranchNookArt")
local BranchNookClient = require("./BranchNookClient")

local BranchNookView = {}

BranchNookView.C = table.freeze({
	show = 150, -- studs (level, camera to trunk foot)
	hide = 180,
	knots = 45,
	knotMax = 60,
	every = 0.4, -- seconds between looks
})
local C = BranchNookView.C

function BranchNookView.start(): () -> ()
	local data = Data.default()
	local nooks = BranchNooks.new(data:module("BranchNooks") :: any)
	local reg = data:routes()
	local engine = { Instance = Instance, CFrame = CFrame, Vector3 = Vector3, Color3 = Color3, Enum = Enum }
	-- the trees: trunk foot, and the routes its knots run on (its boughs and spurs)
	local trees: { { trunk: number, x: number, z: number, routes: { any } } } = {}
	local byTrunk: { [number]: { any } } = {}
	for _, rec in data:forks() do
		local list = {}
		for _, f in rec.forks do
			local b = reg:get(f.branch)
			if b then
				table.insert(list, b)
			end
		end
		byTrunk[rec.trunk] = list
	end
	local seen: { [number]: boolean } = {}
	for _, p in nooks.places do
		if not seen[p.trunk] then
			seen[p.trunk] = true
			local trunk = reg:get(p.trunk)
			if trunk then
				local foot = reg:foot(trunk)
				local routes = byTrunk[p.trunk] or {}
				for _, q in nooks.tree(p.trunk) do
					if q.kind == "spur" then
						local r = reg:get(q.route)
						if r then
							table.insert(routes, r)
						end
					end
				end
				table.insert(trees, { trunk = p.trunk, x = foot.x, z = foot.z, routes = routes })
			end
		end
	end
	local folder = Instance.new("Folder")
	folder.Name = "BranchNooks"
	folder.Parent = workspace
	local built: { [number]: Model? } = {}
	local acorns: { [number]: Folder } = {}
	local knotTree: number? = nil
	local knotFolder: Folder? = nil
	local running = true

	local function drawAcorns(trunk: number)
		local old = acorns[trunk]
		if old then
			old:Destroy()
			acorns[trunk] = nil
		end
		local model: Model? = built[trunk]
		if model == nil then
			return
		end
		local counts = BranchNookClient.parseCounts(game:GetService("Players").LocalPlayer:GetAttribute("NutStashes"))
		local f = Instance.new("Folder")
		f.Name = "Acorns"
		local any = false
		for _, p in nooks.tree(trunk) do
			local n = counts[p.route]
			if n and n > 0 then
				BranchNookArt.acorns(engine, p, n, f)
				any = true
			end
		end
		if any then
			f.Parent = model
			acorns[trunk] = f
		else
			f:Destroy()
		end
	end

	local changed = game:GetService("Players").LocalPlayer:GetAttributeChangedSignal("NutStashes"):Connect(function()
		for trunk in built do
			drawAcorns(trunk)
		end
	end)

	task.spawn(function()
		while running do
			local cam = workspace.CurrentCamera
			if cam then
				local at = cam.CFrame.Position
				local nearest, nd = nil, math.huge
				local builtOne = false
				for _, tr in trees do
					local d = math.sqrt((tr.x - at.X) ^ 2 + (tr.z - at.Z) ^ 2)
					if d < nd then
						nearest, nd = tr, d
					end
					local m = built[tr.trunk]
					if m and d > C.hide then
						m:Destroy()
						built[tr.trunk] = nil
						acorns[tr.trunk] = nil
					elseif m == nil and d < C.show and not builtOne then
						local okB, model = pcall(function()
							return (BranchNookArt.build(engine, nooks, reg, tr.trunk))
						end)
						if okB and model then
							model.Parent = folder
							built[tr.trunk] = model
							drawAcorns(tr.trunk)
						end
						builtOne = true
					end
				end
				-- the knots of the tree the camera is at
				local want = if nearest and nd < C.knots then nearest.trunk else nil
				if want ~= knotTree then
					if knotFolder then
						knotFolder:Destroy()
						knotFolder = nil
					end
					knotTree = want
					if want and nearest then
						local kf = Instance.new("Folder")
						kf.Name = `Knots_{want}`
						pcall(BranchNookArt.nodules, engine, reg, nearest.routes, want, kf, C.knotMax)
						kf.Parent = folder
						knotFolder = kf
					end
				end
			end
			task.wait(C.every)
		end
	end)

	return function()
		running = false
		changed:Disconnect()
		folder:Destroy()
	end
end

return BranchNookView
