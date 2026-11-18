--!strict
-- ServerScriptService.Server.Assets.LoungeArt
-- THE GILDED ACORN's hero pieces (tools/blender/lounge_classic: the bar, the four booths, the side and back walls'
-- wainscot, modelled in Blender; publish.py writes Shared/Attractions/LoungeArt). The lounge is baked from plain
-- parts (tools/bake/lounge_classic) and they are its look until the Model is uploaded; when LoungeArt.ASSET_ID
-- names one this swaps the baked look for the meshes, and when it is "" (as committed) it does nothing at all:
--   * each MeshPart (by name: LoungeArt.PIECES) goes to its centre in the venue frame, painted its colour in its
--     Roblox material; visual only (anchored, no collision, touch or queries), under the bake's model in "Art";
--   * the baked parts they stand in for (LoungeArt.REPLACES, under the bake's Interior) are made invisible; the
--     ones that collide keep colliding (the bar, the booths: people and the camera still stop at them).
-- A Model that fails to load, or holds none of the pieces, leaves the baked look as it was (warned once).
-- Interface: install(root, place, data, opts?) -> report { loaded, why?, pieces, unknown, hidden };
--   start(root?, opts?) -> boolean (false: no art to load). opts = { load: ((id) -> Instance)?, spawn: ((f) -> ())? }
-- No side effects on require.

local Import = require("../Import")
local AlleyLayout = Import.shared("Attractions/AlleyLayout") :: typeof(require("../../shared/Attractions/AlleyLayout"))
local Data = Import.shared("Data") :: typeof(require("../../shared/Data"))
local LoungeArtData = Import.shared("Attractions/LoungeArt") :: typeof(require("../../shared/Attractions/LoungeArt"))
local LoungeClassic =
	Import.shared("Attractions/LoungeClassic") :: typeof(require("../../shared/Attractions/LoungeClassic"))

local LoungeArt = {}

export type Opts = {
	load: ((assetId: number) -> Instance)?, -- default InsertService:LoadAsset
	spawn: ((f: () -> ()) -> ())?, -- default task.spawn
}

function LoungeArt.install(root: Instance, place: any, data: any, opts: Opts?): { [string]: any }
	local o: Opts = opts or {}
	local report = { loaded = false, why = nil :: string?, pieces = 0, unknown = 0, hidden = 0 }
	local id = tonumber(data and data.ASSET_ID)
	if id == nil then
		report.why = "no asset id"
		return report
	end
	if root:FindFirstChild("Art") ~= nil then
		report.why = "already installed"
		return report
	end
	local function defaultLoad(assetId: number): Instance
		return game:GetService("InsertService"):LoadAsset(assetId)
	end
	local load: (number) -> Instance = o.load or defaultLoad
	local asset = load(id)
	local holder = asset -- (the pieces are found by name anywhere under it)
	local byName: { [string]: any } = {}
	for _, p in data.PIECES do
		byName[p.name] = p
	end
	local art = Instance.new("Model")
	art.Name = "Art"
	local yaw = CFrame.Angles(0, place.yaw, 0)
	for _, d in holder:GetDescendants() do
		if not d:IsA("BasePart") then
			continue
		end
		local piece = byName[d.Name]
		if piece == nil then
			report.unknown += 1
			continue
		end
		local c = piece.centre
		local x, y, z = AlleyLayout.toWorld(place, c[1], c[2], c[3])
		local part = d :: BasePart
		part.CFrame = CFrame.new(x, y, z) * yaw
		part.Anchored = true
		part.CanCollide = false
		part.CanTouch = false
		part.CanQuery = false
		part.Color = Color3.fromRGB(piece.colour[1], piece.colour[2], piece.colour[3])
		local okM, material = pcall(function(): any
			return (Enum.Material :: any)[piece.robloxMaterial]
		end)
		if okM and material then
			part.Material = material
		end
		report.pieces += 1
	end
	if report.pieces == 0 then
		report.why = "the Model holds none of the pieces"
		return report
	end
	for _, d in holder:GetDescendants() do
		if d:IsA("BasePart") and byName[d.Name] then
			d.Parent = art
		end
	end
	art.Parent = root
	-- the baked look is hidden where the meshes now draw it (collision stays the bake's)
	local interior = root:FindFirstChild("Interior")
	local hide: { [string]: boolean } = {}
	for _, n in data.REPLACES do
		hide[n] = true
	end
	for _, d in (if interior then interior:GetChildren() else {}) :: { Instance } do
		if d:IsA("BasePart") and hide[d.Name] then
			(d :: BasePart).Transparency = 1
			report.hidden += 1
		end
	end
	report.loaded = true
	return report
end

-- Off the boot path: the bake's lounge (Workspace.Expansion.LoungeClassic.f3_lounge_classic) gets its pieces when
-- an id is set. -> false when there is nothing to load (no id, or no bake).
function LoungeArt.start(root: Instance?, opts: Opts?): boolean
	if tonumber(LoungeArtData.ASSET_ID) == nil then
		return false
	end
	local model = root
	if model == nil then
		local ex = workspace:FindFirstChild("Expansion")
		local slot = ex and ex:FindFirstChild("LoungeClassic")
		model = slot and slot:FindFirstChild(LoungeClassic.VENUE)
	end
	if model == nil then
		return false
	end
	local venue: any = nil
	for _, v in (Data.default():module("Expansion") :: any).venues do
		if v.id == LoungeClassic.VENUE then
			venue = v
		end
	end
	if venue == nil then
		return false
	end
	local place = LoungeClassic.placeOf(venue)
	local spawn = (opts and opts.spawn) or function(f: () -> ())
		task.spawn(f)
	end
	spawn(function()
		local ok, report = pcall(LoungeArt.install, model :: Instance, place, LoungeArtData, opts)
		if not ok then
			warn(`[LoungeArt] the lounge's art failed to load: {report}`)
		elseif not report.loaded then
			warn(`[LoungeArt] the lounge's art was not put in: {report.why}`)
		end
	end)
	return true
end

return LoungeArt
