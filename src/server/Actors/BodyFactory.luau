--!strict
-- ServerScriptService.Server.Actors.BodyFactory
-- Bodies from species, stock look and the best available template (BUILD_PLAN §1.4
-- Actors/BodyFactory, §4.4 #3, §5.2): in order, (1) a placeholder or final rig under
-- ReplicatedStorage.Assets (Rigs/<species>, Placeholders/<species>, or any Model whose `RigSpec`
-- attribute names the species; tools/placeholders writes these with RigSpec's final bone, socket
-- and region names), (2) for humans a stock R15 from a blank HumanoidDescription in the post's
-- palette (townspeople wear their cast member's v5.4 shirt and skin, data/authored/cast; posts wear the
-- RolePalettes uniform; pants from the v5.4 pants list), (3) for animals the RigSpec placeholder puppet
-- built from Shared/Avatar/PuppetSpec (head, ears, eyes, four-segment legs, tail arc: the Motor6Ds the
-- client gait drives), (4) the S5 part-built puppet (Server/AI/Puppets) if that fails. Every body is readied by
-- ActorService.prepareBody (anchored root, Atomic streaming, no server Animator, Dead disabled,
-- replicated ActorId/Species attributes) and stamped with Variant and Post.
-- Interface: build(species, variant, index, post?) -> Model; template(species) -> Model?;
--   applyLook(body, look) (stock colours by species look; the blend is AvatarBlendService's)
-- Engine only inside the functions. No side effects on require.

local ActorService = require("./ActorService")
local Import = require("../Import")
local Puppets = require("../AI/Puppets")

local BodyFactory = {}

-- role palettes for stock humans [hospital_police_infection §5.1, §8.2]: shirt hue per post
local POST_SHIRTS: { [string]: { number } } = {
	hospital_staff = { 120, 190, 200 },
	ambulance_crew = { 230, 120, 40 },
	police = { 35, 50, 110 },
}

function BodyFactory.template(species: string): Model?
	local ReplicatedStorage = game:GetService("ReplicatedStorage")
	local assets = ReplicatedStorage:FindFirstChild("Assets")
	if not assets then
		return nil
	end
	for _, folderName in { "Rigs", "Placeholders" } do
		local folder = assets:FindFirstChild(folderName)
		local m = folder and folder:FindFirstChild(species)
		if m and m:IsA("Model") then
			return m
		end
	end
	for _, d in assets:GetDescendants() do
		if d:IsA("Model") and d:GetAttribute("RigSpec") == species then
			return d
		end
	end
	return nil
end

-- The cast's v5.4 looks ({ shirt, skin } as Color3), read once from Shared.Generated.Cast.
local castCache: { { shirt: Color3?, skin: Color3? } }? = nil
local function castLooks(): { { shirt: Color3?, skin: Color3? } }
	if castCache then
		return castCache
	end
	local out: { { shirt: Color3?, skin: Color3? } } = {}
	pcall(function()
		for _, c in Import.shared("Generated/Cast") :: { any } do
			local look = c.look or {}
			local shirt = string.match(tostring(look.outfit or ""), "shirt%s*#(%x%x%x%x%x%x)")
			local skin = string.match(tostring(look.skinTone or ""), "#?(%x%x%x%x%x%x)")
			if shirt or skin then
				table.insert(out, {
					shirt = if shirt then Color3.fromHex(shirt) else nil,
					skin = if skin then Color3.fromHex(skin) else nil,
				})
			end
		end
	end)
	castCache = out
	return out
end

-- Post -> RolePalettes uniform role (the street posts dress as townspeople from the cast).
local function roleFor(post: string?, index: number): string?
	if post == "police" then
		return "officer"
	elseif post == "hospital_staff" then
		return ({ "nurse", "doctor", "orderly", "nurse", "guard" })[index % 5 + 1]
	end
	return nil
end

local function stockHuman(index: number, post: string?): Model
	local Players = game:GetService("Players")
	local desc = Instance.new("HumanoidDescription")
	local RolePalettes = Import.shared("Avatar/RolePalettes")
	local fallback = RolePalettes.look("townsperson", index + 1)
	local skin = Color3.new(fallback.skin.r, fallback.skin.g, fallback.skin.b)
	local shirt = Color3.new(fallback.shirt.r, fallback.shirt.g, fallback.shirt.b)
	local pants = Color3.new(fallback.pants.r, fallback.pants.g, fallback.pants.b)
	local role = roleFor(post, index)
	local rgb = POST_SHIRTS[post or ""]
	if role then
		local look = RolePalettes.look(role, index + 1)
		shirt = Color3.new(look.shirt.r, look.shirt.g, look.shirt.b)
		pants = Color3.new(look.pants.r, look.pants.g, look.pants.b)
	elseif rgb then
		shirt = Color3.fromRGB(rgb[1], rgb[2], rgb[3])
	else
		local cast = castLooks()
		local c = cast[(index % math.max(#cast, 1)) + 1]
		if c then
			shirt = c.shirt or shirt
			skin = c.skin or skin
		end
	end
	desc.HeadColor = skin
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	desc.TorsoColor = shirt
	desc.LeftLegColor = pants
	desc.RightLegColor = pants
	return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
end

function BodyFactory.build(species: string, variant: string, index: number, post: string?): Model
	local templateSpecies = if species == "squirrel" and variant == "spicy" then "rodent" else species
	local model: Model
	local t = BodyFactory.template(templateSpecies) or BodyFactory.template(species)
	if t then
		model = t:Clone()
	elseif species == "human" and variant ~= "rider" then
		local ok, result = pcall(stockHuman, index, post)
		if ok then
			model = result
		else
			model = Puppets.build(species, variant, index, workspace).model
		end
	elseif species == "squirrel" or species == "fox" or species == "deer" then
		local ok, result = pcall(function(): Model
			local PuppetSpec = Import.shared("Avatar/PuppetSpec")
			local PartBuilder = Import.shared("Avatar/PartBuilder")
			local v: string = variant
			local spec = if species == "squirrel" and v == "spicy"
				then PuppetSpec.spec("rodent")
				elseif species == "deer" then PuppetSpec.spec("deer", { variant = v })
				else PuppetSpec.spec(species)
			return PartBuilder.instantiate(spec, PartBuilder.engineLib())
		end)
		model = if ok then result else Puppets.build(species, variant, index, workspace).model
	else
		model = Puppets.build(species, variant, index, workspace).model
	end
	local id = `{species}_{index}`
	ActorService.prepareBody(model, id, species)
	model:SetAttribute("Variant", variant)
	if post then
		model:SetAttribute("Post", post)
	end
	return model
end

-- applyLook(body, look): the species stock look (fur / skin base colour on the body parts).
function BodyFactory.applyLook(body: Model, look: any)
	local c = Color3.new(look.body.r, look.body.g, look.body.b)
	for _, d in body:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 and d.Name ~= "HumanoidRootPart" then
			d.Color = c
		end
	end
end

return BodyFactory
