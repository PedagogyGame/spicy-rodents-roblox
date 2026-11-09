--!strict
-- ServerScriptService.Server.Avatar.AvatarBlendService
-- Trait fetch and cache; apply on possession, revert on release (BUILD_PLAN §1.4, D13; Addendum A3, B1;
-- brief v2 §13a; spike S9 carry-forward).
-- Interface: new(deps?) -> Service; :traitsFor(userId) -> Traits?; :lookFor(userId, species, stock?) -> Look?;
--            :apply(model, species, look) -> number (ops); :revert(model) -> boolean;
--            :preview(model, species, sampleIndex) -> Look (Role Lab dev samples); ops(model, species, look);
--            STOCK (species stock looks); engineDeps() (Players / MarketplaceService fetchers).
--
-- description -> BlendRules.traits (GetProductInfo names, cached; failures cached as "no info", S9 finding 5;
-- the curated colour table) -> BlendRules.compose -> concrete operations on the body:
--   humans  (brief v2 §13a): skin tone on the RigSpec.human skin regions (Head, hands, lower arms), the face
--           decal (FaceDecal on Head) when the avatar has a classic face, the hair accessory; the uniform,
--           build and hitbox never change.
--   animals (A3, B1): the capped 30 % fur tint on Body and FurCards, pattern colour on Pattern, the tail tip
--           (the part holding the TailTip socket), derived eyes on Eyes (the rodent's never change: stock
--           eyesLocked), the one softened neon accent on the ears, and ONE rigid accessory on HeadSocket at
--           x0.45. A part with a SurfaceAppearance gets SurfaceAppearance.Color (S8: writable at runtime),
--           otherwise Part.Color, so puppets and skinned rigs blend the same way.
-- Every original value is recorded per model, so `revert` restores the body exactly on release.
-- Engine calls live in `engineDeps` and inside deps; requiring is side-effect free; Lune tests pass fakes.

local Import = require("../Import")
local BlendRules = Import.shared("Avatar/BlendRules") :: typeof(require("../../shared/Avatar/BlendRules"))
local DevSamples = Import.shared("Avatar/DevSamples") :: typeof(require("../../shared/Avatar/DevSamples"))
local PartBuilder = Import.shared("Avatar/PartBuilder") :: typeof(require("../../shared/Avatar/PartBuilder"))

-- Exported types do not cross Import (W1 Track A note): BlendRules' types are restated loosely here.
type Rgb = { r: number, g: number, b: number }
type DescriptionLike = any
type ProductInfo = { [number]: { name: string } }
type ColourTable = { [number]: Rgb }
type Traits = any
type StockLook = { body: Rgb, pattern: Rgb, eyes: Rgb, eyesLocked: boolean }
type Look = any
type HumanLook = any
type AnimalLook = any

export type Deps = {
	describe: ((userId: number) -> DescriptionLike?)?,
	productInfo: ((assetId: number) -> { name: string }?)?,
	colourTable: ColourTable?,
	accessory: ((assetId: number) -> Instance?)?, -- an Accessory with a Handle (engine: from the avatar model)
	faceTexture: ((faceId: number) -> string?)?, -- classic face asset -> decal texture (S9: LoadAsset)
	color3: ((r: number, g: number, b: number) -> any)?, -- Color3.new (engine or @lune/roblox)
	newInstance: ((className: string) -> Instance)?,
	cframe: any?, -- the CFrame library (accessory weld)
}

export type Op = { inst: Instance, prop: string, value: Rgb }

local AvatarBlendService = {}
AvatarBlendService.__index = AvatarBlendService

AvatarBlendService.ACCESSORY_SCALE = 0.45 -- HeadSocket shrink (S9 carry-forward)

-- Stock looks per animal species (the placeholder palette, Avatar/PuppetSpec; art replaces them in W5).
local hex = PartBuilder.hex
AvatarBlendService.STOCK = {
	squirrel = { body = hex("#b78453"), pattern = hex("#e6d3b3"), eyes = hex("#1d1a17"), eyesLocked = false },
	rodent = { body = hex("#83544d"), pattern = hex("#c9a38c"), eyes = hex("#b0242a"), eyesLocked = true },
	fox = { body = hex("#b8663c"), pattern = hex("#efe6da"), eyes = hex("#2a1d12"), eyesLocked = false },
	deer = { body = hex("#ad845e"), pattern = hex("#eadfcc"), eyes = hex("#1a1512"), eyesLocked = false },
} :: { [string]: StockLook }

local HUMAN_SKIN = { "Head", "LeftHand", "RightHand", "LeftLowerArm", "RightLowerArm" } -- RigSpec.human.regions

export type Service = typeof(setmetatable(
	{} :: {
		deps: Deps,
		_traits: { [number]: Traits },
		_info: { [number]: { name: string } | false },
		_applied: { [Instance]: { ops: { { inst: Instance, prop: string, old: any } }, added: { Instance } } },
	},
	AvatarBlendService
))

function AvatarBlendService.new(deps: Deps?): Service
	return setmetatable({
		deps = deps or {},
		_traits = {},
		_info = {},
		_applied = {},
	}, AvatarBlendService)
end

-- Product info through the cache: a failed fetch is remembered as "no info" (S9 finding 5).
local function infoFor(self: Service, desc: DescriptionLike): ProductInfo
	local out: ProductInfo = {}
	local fetch = self.deps.productInfo
	local ids = { desc.Shirt, desc.Pants, desc.GraphicTShirt }
	for _, a in desc.accessories do
		table.insert(ids, a.assetId)
	end
	for _, id in ids do
		if id and id ~= 0 then
			local cached: { name: string } | false | nil = self._info[id]
			if cached == nil and fetch then
				local ok, info = pcall(fetch, id)
				local value: { name: string } | false = if ok and info then info else false
				self._info[id] = value
				cached = value
			end
			if cached then
				out[id] = cached :: { name: string }
			end
		end
	end
	return out
end

function AvatarBlendService.traitsFor(self: Service, userId: number): Traits?
	local cached = self._traits[userId]
	if cached then
		return cached
	end
	local describe = self.deps.describe
	if not describe then
		return nil
	end
	local ok, desc = pcall(describe, userId)
	if not ok or desc == nil then
		return nil
	end
	local traits = BlendRules.traits(desc, infoFor(self, desc), self.deps.colourTable)
	self._traits[userId] = traits
	return traits
end

function AvatarBlendService.lookFor(self: Service, userId: number, species: string, stock: StockLook?): Look?
	local traits = self:traitsFor(userId)
	if not traits then
		return nil
	end
	local s = stock or AvatarBlendService.STOCK[species] or AvatarBlendService.STOCK.squirrel
	return BlendRules.compose(species, s, traits)
end

-- The colour target of a region: its SurfaceAppearance when it has one, else the part.
local function colourTarget(part: Instance): (Instance, string)
	local sa = part:FindFirstChildWhichIsA("SurfaceAppearance")
	if sa then
		return sa, "Color"
	end
	return part, "Color"
end

-- ops(model, species, look): the colour operations a look implies on this body (pure over the tree).
function AvatarBlendService.ops(model: Instance, species: string, look: Look): { Op }
	local out: { Op } = {}
	local function add(name: string, value: Rgb)
		local part = model:FindFirstChild(name, true)
		if part and part:IsA("BasePart") then
			local inst, prop = colourTarget(part)
			table.insert(out, { inst = inst, prop = prop, value = value })
		end
	end
	if look.kind == "human" then
		local h = look :: HumanLook
		for _, name in HUMAN_SKIN do
			add(name, h.skinTone)
		end
		return out
	end
	local a = look :: AnimalLook
	add("Body", a.bodyTint)
	add("FurCards", a.bodyTint)
	add("Pattern", a.patternColour)
	add("Eyes", a.eyeColour)
	local tip = model:FindFirstChild("TailTip", true)
	if tip and tip.Parent and tip.Parent:IsA("BasePart") then
		local inst, prop = colourTarget(tip.Parent)
		table.insert(out, { inst = inst, prop = prop, value = a.tailTip })
	end
	if a.accent then
		add("EarL", a.accent)
		add("EarR", a.accent)
	end
	local _ = species
	return out
end

local function color3(self: Service, c: Rgb): any
	local make = self.deps.color3
	if make then
		return make(c.r, c.g, c.b)
	end
	return Color3.new(c.r, c.g, c.b)
end

-- apply(model, species, look): colour ops plus face and accessory; reverts any earlier blend first.
function AvatarBlendService.apply(self: Service, model: Instance, species: string, look: Look): number
	self:revert(model)
	local record = { ops = {}, added = {} }
	for _, op in AvatarBlendService.ops(model, species, look) do
		table.insert(record.ops, { inst = op.inst, prop = op.prop, old = (op.inst :: any)[op.prop] });
		(op.inst :: any)[op.prop] = color3(self, op.value)
	end
	local newInstance: (className: string) -> Instance = self.deps.newInstance
		or function(className: string): Instance
			return Instance.new(className :: any)
		end
	if look.kind == "human" then
		local h = look :: HumanLook
		local head = model:FindFirstChild("Head")
		if head and h.face ~= 0 and self.deps.faceTexture then
			local texture = self.deps.faceTexture(h.face)
			if texture then
				local decal = head:FindFirstChild("FaceDecal")
				if decal then
					table.insert(record.ops, { inst = decal, prop = "Texture", old = (decal :: any).Texture });
					(decal :: any).Texture = texture
				else
					local d = newInstance("Decal")
					d.Name = "FaceDecal"
					(d :: any).Texture = texture
					d.Parent = head
					table.insert(record.added, d)
				end
			end
		end
		local hair = h.hair or h.headAccessory
		if hair and self.deps.accessory then
			local acc = self.deps.accessory(hair)
			if acc then
				acc.Parent = model
				table.insert(record.added, acc)
			end
		end
	else
		local a = look :: AnimalLook
		local socket = model:FindFirstChild("HeadSocket", true)
		if a.accessory and self.deps.accessory and socket and socket.Parent then
			local acc = self.deps.accessory(a.accessory)
			local handle = acc and acc:FindFirstChild("Handle")
			if acc and handle and handle:IsA("BasePart") then
				handle.Size = handle.Size * AvatarBlendService.ACCESSORY_SCALE
				handle.Anchored = false
				handle.CanCollide = false
				handle.Massless = true
				local weld = newInstance("Weld")
				weld.Name = "AccessoryWeld"
				(weld :: any).Part0 = socket.Parent;
				(weld :: any).Part1 = handle;
				(weld :: any).C0 = (socket :: any).CFrame
				weld.Parent = handle
				acc.Parent = model
				table.insert(record.added, acc)
			end
		end
	end
	model:SetAttribute("Blended", true)
	self._applied[model] = record
	return #record.ops + #record.added
end

-- revert(model): restore every recorded value and remove what apply added (release, D13).
function AvatarBlendService.revert(self: Service, model: Instance): boolean
	local record = self._applied[model]
	if not record then
		return false
	end
	for i = #record.ops, 1, -1 do
		local op = record.ops[i];
		(op.inst :: any)[op.prop] = op.old
	end
	for _, inst in record.added do
		inst:Destroy()
	end
	self._applied[model] = nil
	model:SetAttribute("Blended", nil)
	return true
end

-- preview(model, species, sampleIndex): Role Lab's blend preview on a dev sample (DevSamples, D13).
function AvatarBlendService.preview(self: Service, model: Instance, species: string, sampleIndex: number): Look
	local sample = DevSamples.SAMPLES[((sampleIndex - 1) % #DevSamples.SAMPLES) + 1]
	local traits = BlendRules.traits(sample.desc, DevSamples.PRODUCT_INFO, self.deps.colourTable)
	local look =
		BlendRules.compose(species, AvatarBlendService.STOCK[species] or AvatarBlendService.STOCK.squirrel, traits)
	self:apply(model, species, look)
	return look
end

-- Engine fetchers (call inside the engine only): descriptions and product names, both through pcall.
function AvatarBlendService.engineDeps(): Deps
	local Players = game:GetService("Players")
	local Marketplace = game:GetService("MarketplaceService")
	local function rgb(c: Color3): Rgb
		return { r = c.R, g = c.G, b = c.B }
	end
	return {
		describe = function(userId: number): DescriptionLike?
			local desc = Players:GetHumanoidDescriptionFromUserId(userId)
			local accessories = {}
			for _, a in desc:GetAccessories(true) do
				table.insert(accessories, {
					assetId = a.AssetId,
					accessoryType = a.AccessoryType.Name,
					isLayered = a.IsLayered,
					order = a.Order,
				})
			end
			return {
				HeadColor = rgb(desc.HeadColor),
				TorsoColor = rgb(desc.TorsoColor),
				LeftArmColor = rgb(desc.LeftArmColor),
				RightArmColor = rgb(desc.RightArmColor),
				LeftLegColor = rgb(desc.LeftLegColor),
				RightLegColor = rgb(desc.RightLegColor),
				Face = desc.Face,
				Head = desc.Head,
				Shirt = desc.Shirt,
				Pants = desc.Pants,
				GraphicTShirt = desc.GraphicTShirt,
				HeightScale = desc.HeightScale,
				WidthScale = desc.WidthScale,
				HeadScale = desc.HeadScale,
				DepthScale = desc.DepthScale,
				BodyTypeScale = desc.BodyTypeScale,
				ProportionScale = desc.ProportionScale,
				accessories = accessories,
			}
		end,
		productInfo = function(assetId: number): { name: string }?
			local info = Marketplace:GetProductInfo(assetId, Enum.InfoType.Asset)
			return if info and info.Name then { name = info.Name } else nil
		end,
	}
end

return AvatarBlendService
