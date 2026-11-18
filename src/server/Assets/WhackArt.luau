--!strict
-- ServerScriptService.Server.Assets.WhackArt
-- The whack-a-mole cabinet's meshes from the owner's Blender file (tools/blender/whack_a_mole: export.py makes
-- about 12,000 triangles in 42 pieces, publish.py uploads them and writes Shared/Minigames/WhackAMole/Art). The
-- cabinet itself is baked from plain parts (tools/bake/games/WhackAMole) under the names the game moves and
-- writes on; when Art names an uploaded Model this swaps the baked look for his meshes under the same names, and
-- when it names none (assetId "", as now) it does nothing at all:
--   * each MeshPart goes where Art says (its centre in the cabinet frame, Layout.toSite, set down on the site's
--     place; MeshParts arrive unrotated in the site frame), painted Layout.COLORS[material] (a mole's fur its own,
--     the mallet's timber its handle colour) in its Roblox material; visual only (anchored, no collision, touch
--     or queries);
--   * a mole's pieces go into its Mole model and the mallet's into the Mallet, so the clients' PivotTo of those
--     models carries them (each model's PrimaryPart stays the baked one: the pivot the clients use);
--   * the baked parts they replace are made invisible and the ones nothing needs any more are removed (fewer
--     parts to replicate): a mole or the mallet keeps only its pivot (its PrimaryPart), the shell only the parts
--     that collide or carry lettering. The cabinet's collision stays the bake's, and so does every SurfaceGui
--     (WHACK A MOLE, the windows' live SCORE and TIME, FREE PLAY, the hole numbers: the meshes carry no
--     lettering); each part that carries lettering is brought NUDGE studs toward the viewer, off the mesh face
--     it would otherwise share (his coin door, the glass, the leather deck) and flicker against.
-- Started by the station's own server half (Server/Minigames/Games/WhackAMole) once its cabinet is found: the
-- load runs off the caller's path, and a Model that fails to load leaves the baked cabinet as it was (warned).
-- Interface: install(model, place, data, opts?) -> report { loaded, why?, pieces, unknown, hidden, removed,
--   nudged }; start(model, place, opts?) -> boolean (false: no art to load); colour(piece) -> { r, g, b }; NUDGE
-- No side effects on require.

local Import = require("../Import")
local AlleyLayout = Import.shared("Attractions/AlleyLayout") :: typeof(require("../../shared/Attractions/AlleyLayout"))
local Layout =
	Import.shared("Minigames/WhackAMole/Layout") :: typeof(require("../../shared/Minigames/WhackAMole/Layout"))

local WhackArt = {}

WhackArt.SITE = "bowling_alley" -- the venue whose games room holds the cabinet
WhackArt.NUDGE = 0.03 -- studs a part carrying lettering is brought toward the viewer over the meshes

export type Env = { CFrame: any, Color3: any, Enum: any }
export type Opts = {
	load: ((assetId: number) -> Instance)?, -- default InsertService:LoadAsset
	data: any?, -- default Shared/Minigames/WhackAMole/Art
	env: Env?, -- default the engine's CFrame, Color3 and Enum (Lune specs pass @lune/roblox)
	spawn: ((f: () -> ()) -> ())?, -- default task.spawn
	warn: ((text: string) -> ())?,
}

local function engineEnv(): Env
	return { CFrame = CFrame, Color3 = Color3, Enum = Enum }
end

local function artData(): any
	return Import.shared("Minigames/WhackAMole/Art") :: any
end

-- the colour a piece is painted (Layout.COLORS by its material; a mole's fur is that mole's own)
function WhackArt.colour(piece: any): { number }
	local name = piece.material
	if name == "fur" then
		name = Layout.MOLE.fur[piece.mole or 1] or "cocoa"
	elseif name == "wood" and piece.group == "mallet" then
		name = "handle"
	end
	return Layout.COLORS[name] or Layout.COLORS.cream
end

function WhackArt.install(model: Instance, place: any, data: any, opts: Opts?): { [string]: any }
	local o: Opts = opts or {}
	local e = o.env or engineEnv()
	local report =
		{ loaded = false, why = nil :: string?, pieces = 0, unknown = 0, hidden = 0, removed = 0, nudged = 0 }
	local id = tonumber(data and data.assetId)
	if id == nil then
		report.why = "no asset id"
		return report
	end
	if model:GetAttribute("Art") ~= nil then
		report.why = "already installed"
		return report
	end
	local function defaultLoad(assetId: number): Instance
		return game:GetService("InsertService"):LoadAsset(assetId)
	end
	local load: (number) -> Instance = o.load or defaultLoad
	local asset = load(id)
	local holder = asset:IsA("Model") and asset:FindFirstChildWhichIsA("Model") or asset
	local N = Layout.NAMES
	local shell = model:FindFirstChild("Shell")
	local yaw = e.CFrame.Angles(0, place.yaw, 0)
	local into: { [string]: Instance } = {}
	for _, d in holder:GetDescendants() do
		if not d:IsA("BasePart") then
			continue
		end
		local piece = data.pieces[d.Name]
		if piece == nil then
			report.unknown += 1
			continue
		end
		local c = piece.centre
		local X, Y, D = Layout.toSite(c[1], c[2], c[3])
		local x, y, z = AlleyLayout.toWorld(place, X, Y, D)
		d.CFrame = e.CFrame.new(x, y, z) * yaw
		d.Anchored = true
		d.CanCollide = false
		d.CanTouch = false
		d.CanQuery = false
		local rgb = WhackArt.colour(piece)
		d.Color = e.Color3.fromRGB(rgb[1], rgb[2], rgb[3])
		local okM, material = pcall(function(): any
			return (e.Enum.Material :: any)[piece.robloxMaterial]
		end)
		if okM and material then
			d.Material = material
		end
		local parent: Instance? = if piece.group == "mole"
			then model:FindFirstChild(`{N.mole}{piece.mole}`)
			elseif piece.group == "mallet" then model:FindFirstChild(N.mallet)
			else shell
		into[d.Name] = parent or model
		report.pieces += 1
	end
	if report.pieces == 0 then
		report.why = "the Model holds none of the pieces"
		return report
	end
	-- the baked look is hidden where the meshes now draw it (collision and lettering stay the bake's)
	local function hide(root: Instance?)
		if root == nil then
			return
		end
		for _, d in root:GetDescendants() do
			if d:IsA("BasePart") and d.Transparency < 1 then
				d.Transparency = 1
				d.CastShadow = false
				report.hidden += 1
			end
		end
	end
	hide(shell)
	hide(model:FindFirstChild(N.mallet))
	for i = 1, 5 do
		hide(model:FindFirstChild(`{N.mole}{i}`))
	end
	for _, name in { N.score, N.time } do
		local window = model:FindFirstChild(name)
		if window and window:IsA("BasePart") then
			window.Transparency = 1
			report.hidden += 1
		end
	end
	-- the hidden parts nothing needs any more go: all of a mole or the mallet but its pivot, and of the shell
	-- whatever neither collides nor carries lettering (before the meshes move in)
	local function prune(root: Instance?, pivot: Instance?)
		if root == nil then
			return
		end
		for _, d in root:GetDescendants() do
			if
				d:IsA("BasePart")
				and d.Transparency >= 1
				and d ~= pivot
				and (pivot ~= nil or not d.CanCollide)
				and d:FindFirstChildWhichIsA("SurfaceGui") == nil
			then
				d:Destroy()
				report.removed += 1
			end
		end
	end
	prune(shell, nil)
	for _, name in { N.mallet, `{N.mole}1`, `{N.mole}2`, `{N.mole}3`, `{N.mole}4`, `{N.mole}5` } do
		local m = model:FindFirstChild(name)
		if m and m:IsA("Model") then
			prune(m, m.PrimaryPart)
		end
	end
	-- the lettering off the meshes' faces: each part with a SurfaceGui comes NUDGE toward where its face looks
	local nudged: { [Instance]: boolean } = {}
	for _, gui in model:GetDescendants() do
		local part = gui.Parent
		if gui:IsA("SurfaceGui") and part and part:IsA("BasePart") and not nudged[part] then
			nudged[part] = true
			local cf = part.CFrame
			local face = (gui.Face :: any).Name
			local out = if face == "Front"
				then -cf.LookVector
				elseif face == "Back" then cf.LookVector
				elseif face == "Top" then cf.UpVector
				elseif face == "Bottom" then -cf.UpVector
				elseif face == "Right" then cf.RightVector
				else -cf.RightVector
			part.CFrame = cf + out * WhackArt.NUDGE
			report.nudged += 1
		end
	end
	for _, d in holder:GetDescendants() do
		local parent = into[d.Name]
		if parent and d:IsA("BasePart") then
			d.Parent = parent
		end
	end
	model:SetAttribute("Art", tostring(id))
	report.loaded = true
	return report
end

-- The station's one call: nothing when Art names no Model; else the load off the caller's path.
function WhackArt.start(model: Instance, place: any, opts: Opts?): boolean
	local o: Opts = opts or {}
	local okD, data = pcall(function(): any
		return o.data or artData()
	end)
	if not okD or data == nil or tonumber(data.assetId) == nil then
		return false
	end
	local spawn = o.spawn or function(f: () -> ())
		task.spawn(f)
	end
	local complain = o.warn or function(text: string)
		warn(text)
	end
	spawn(function()
		local ok, report = pcall(WhackArt.install, model, place, data, o)
		if not ok then
			complain(`[SpicyRodents] whack-a-mole art failed: {report} (the baked cabinet stands)`)
		elseif not report.loaded and report.why ~= "already installed" then
			complain(`[SpicyRodents] whack-a-mole art: {report.why} (the baked cabinet stands)`)
		end
	end)
	return true
end

-- Boot's one call (Server/Boot/Game, like PinballArt): the cabinet in each bowling alley's games room
-- (Workspace.Attractions.<alley>.GamesRoom.WhackAMole). heartbeat = false (a headless boot) loads nothing.
function WhackArt.startIn(root: Instance?, opts: (Opts & { heartbeat: boolean? })?): number
	local o: any = opts or {}
	if root == nil or o.heartbeat == false then
		return 0
	end
	local n = 0
	for _, site in root:GetChildren() do
		if site:GetAttribute("Site") ~= WhackArt.SITE then
			continue
		end
		local room = site:FindFirstChild("GamesRoom")
		local model = room and room:FindFirstChild(Layout.NAMES.model)
		if model and WhackArt.start(model, { yaw = site:GetAttribute("Yaw") or 0 }, o) then
			n += 1
		end
	end
	return n
end

return WhackArt
