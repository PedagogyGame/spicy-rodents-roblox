--!strict
-- ServerScriptService.Server.Assets.HeroArt
-- The sculpted, skinned squirrel and Spicy Rodent in place of the part-built puppets (owner 2026-11-10:
-- "this is a central thing, this squirrels appearance ... more attention paid to its face area and better
-- texture"). At boot, before any body is built, each uploaded model in Shared/Actors/HeroAssets is loaded
-- once (InsertService:LoadAsset: the experience owner's own assets), made into a template the rest of the
-- game already understands, and parked under ReplicatedStorage.Assets.Rigs/<name>, which is the first
-- place Actors/BodyFactory.template looks. A model that fails to load or does not pass RigSpec is left
-- out, and that species keeps its puppet.
--
-- What the upload looks like (measured on the CI place): a Model whose PrimaryPart "RootPart" is a
-- 2 x 2 x 1 invisible Part at the FEET holding the 35 Bones, with skinned MeshParts Body, Pattern, Eyes,
-- FurCards (and Blood) each joined to it by a Motor6D and carrying a SurfaceAppearance.
-- What the game expects of a body: PrimaryPart "RootPart" at HipHeight over the feet (the kinematic
-- motors, the hitbox and the camera all work from it), the RigSpec bones, regions and sockets.
-- So prepare(): the imported root is renamed SkinRoot and welded HipHeight below a new small RootPart;
-- the sockets become Attachments under their Bones; the rodent's eyes get a faint red light. The colour
-- maps carry their final colours (the tints are baked in on export), so no SurfaceAppearance has to be
-- changed at runtime.
-- Bones are posed on the client only (Client/Animation/AnimationDriver writes Bone.Transform).
-- Interface: prepare(model, name, entry, lib?) -> Model (errors on a malformed model);
--   install(opts?) -> { installed: { string }, failed: { [string]: string } };
--   opts = { load: ((assetId) -> Instance)?, parent: Instance?, entries: { [string]: Entry }?, lib: Lib? }
--   (lib: the Instance, Vector3, CFrame, Color3 and Enum to build with; the engine's by default, Lune's
--   in the specs)
-- Engine only inside the functions. No side effects on require.

local Import = require("../Import")
local HeroAssets = Import.shared("Actors/HeroAssets") :: typeof(require("../../shared/Actors/HeroAssets"))
local RigSpec = Import.shared("Actors/RigSpec") :: typeof(require("../../shared/Actors/RigSpec"))
-- (a module reached through Import carries its values' types but not its exported type names:
-- this is the same type, taken from a value)
type Entry = typeof(HeroAssets.SPECIES.squirrel)

local HeroArt = {}

HeroArt.ROOT_SIZE = { 0.66, 0.66, 1.4 } -- the puppet's root block (PuppetSpec)
HeroArt.SHOULDER = 0.93 -- studs at the shoulder (the lowered sculpt)

export type Lib = { Instance: any, Vector3: any, CFrame: any, Color3: any, Enum: any }

local function engineLib(): Lib
	return { Instance = Instance, Vector3 = Vector3, CFrame = CFrame, Color3 = Color3, Enum = Enum }
end

local function hex(s: string, Color3: any): any
	local h = string.gsub(s, "#", "")
	local r = tonumber(string.sub(h, 1, 2), 16) or 255
	local g = tonumber(string.sub(h, 3, 4), 16) or 255
	local b = tonumber(string.sub(h, 5, 6), 16) or 255
	return Color3.fromRGB(r, g, b)
end

-- Turns a loaded hero Model into a body template. `name` is the RigSpec species ("squirrel" | "rodent").
function HeroArt.prepare(model: any, name: string, entry: Entry, lib: Lib?): any
	local L = lib or engineLib()
	local Instance, Vector3, CFrame, Color3, Enum = L.Instance, L.Vector3, L.CFrame, L.Color3, L.Enum
	local skin = model.PrimaryPart or model:FindFirstChild("RootPart")
	if skin == nil or not skin:IsA("BasePart") then
		error(`HeroArt: {name} has no root part`)
	end
	local skinRoot: any = skin
	skinRoot.Name = "SkinRoot"
	skinRoot.Transparency = 1
	local hip = entry.hipHeight
	local root = Instance.new("Part")
	root.Name = "RootPart"
	root.Size = Vector3.new(HeroArt.ROOT_SIZE[1], HeroArt.ROOT_SIZE[2], HeroArt.ROOT_SIZE[3])
	root.Transparency = 1
	root.CanCollide = false
	root.CFrame = skinRoot.CFrame * CFrame.new(0, hip, 0)
	local weld = Instance.new("Weld")
	weld.Name = "SkinRootWeld"
	weld.Part0 = root
	weld.Part1 = skinRoot
	weld.C0 = CFrame.new(0, -hip, 0)
	weld.Parent = root
	root.Parent = model
	model.PrimaryPart = root
	-- regions: the SurfaceAppearance's mode and stock tint
	for regionName, region in entry.regions do
		local part = model:FindFirstChild(regionName)
		if part == nil or not part:IsA("BasePart") then
			error(`HeroArt: {name} has no region {regionName}`)
		end
		for _, child in part:GetChildren() do
			if child:IsA("SurfaceAppearance") then
				-- The colour maps are uploaded with their final colours and the mode they need, so there is
				-- normally nothing to do here. A mode or tint that does differ is set if the engine lets a
				-- game script set it (a live server may not: the cloud checks run with more permission).
				local sa: any = child
				local mode = (Enum.AlphaMode :: any)[region.alphaMode]
				if mode and sa.AlphaMode ~= mode then
					pcall(function()
						sa.AlphaMode = mode
					end)
				end
				if region.tint then
					local tint = hex(region.tint, Color3)
					pcall(function()
						sa.Color = tint
					end)
				end
			end
		end
	end
	-- sockets: Attachments under their Bones
	local bones: { [string]: any } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("Bone") then
			bones[d.Name] = d
		end
	end
	for socketName, socket in entry.sockets do
		local bone = bones[socket.bone]
		if bone == nil then
			error(`HeroArt: {name} has no bone {socket.bone} for {socketName}`)
		end
		local a = Instance.new("Attachment")
		a.Name = socketName
		a.Position = Vector3.new(socket.offset[1], socket.offset[2], socket.offset[3])
		a.Parent = bone
	end
	if name == "rodent" then
		-- the Spicy Rodent's eyes glow: a faint red light at the head (nobody else has one)
		local head = model:FindFirstChild("HeadSocket", true)
		if head then
			local light = Instance.new("PointLight")
			light.Name = "EyeGlow"
			light.Color = Color3.fromRGB(255, 40, 20)
			light.Brightness = 0.9
			light.Range = 5
			light.Shadows = false
			light.Parent = head
		end
	end
	model.Name = name
	model:SetAttribute("HipHeight", hip)
	model:SetAttribute("ShoulderHeight", HeroArt.SHOULDER)
	model:SetAttribute("RigSpec", name)
	model:SetAttribute("Hero", true)
	return model
end

export type Options = {
	load: ((assetId: number) -> Instance)?,
	parent: Instance?, -- where Rigs lives (default ReplicatedStorage.Assets, created if missing)
	entries: { [string]: Entry }?,
	lib: Lib?,
}

function HeroArt.install(opts: Options?): { installed: { string }, failed: { [string]: string } }
	local o: Options = opts or {}
	local L = o.lib or engineLib()
	local Instance = L.Instance
	local load: (assetId: number) -> Instance = o.load
		or function(assetId: number): Instance
			return game:GetService("InsertService"):LoadAsset(assetId)
		end
	local parent: any = o.parent
	if parent == nil then
		local rs = game:GetService("ReplicatedStorage")
		local assets = rs:FindFirstChild("Assets")
		if assets == nil then
			local made = Instance.new("Folder")
			made.Name = "Assets"
			made.Parent = rs
			assets = made
		end
		parent = assets
	end
	local rigs: any = parent:FindFirstChild("Rigs")
	if rigs == nil then
		local made = Instance.new("Folder")
		made.Name = "Rigs"
		made.Parent = parent
		rigs = made
	end
	local installed: { string } = {}
	local failed: { [string]: string } = {}
	for name, entry in o.entries or HeroAssets.SPECIES do
		if rigs:FindFirstChild(name) then
			continue -- a rig is already there (a hand-placed one wins)
		end
		local ok, err = pcall(function()
			local asset: any = load(entry.assetId)
			local model = if asset:IsA("Model") and asset.PrimaryPart
				then asset
				else asset:FindFirstChildWhichIsA("Model")
			if model == nil then
				error("the asset holds no Model")
			end
			local template = HeroArt.prepare(model, name, entry, L)
			local report = RigSpec.validate(template, name)
			if not report.ok then
				error(
					`RigSpec: bones {#report.missingBones}, sockets {#report.missingSockets}, regions {#report.missingRegions} missing; root ok {report.primaryPartOk}`
				)
			end
			template.Parent = rigs
		end)
		if ok then
			table.insert(installed, name)
		else
			failed[name] = tostring(err)
		end
	end
	table.sort(installed)
	return { installed = installed, failed = failed }
end

return HeroArt
