--!strict
-- ServerScriptService.Server.Actors.BodyFactory
-- Bodies from species, stock look and the best available template (BUILD_PLAN §1.4
-- Actors/BodyFactory, §4.4 #3, §5.2): in order, (1) a placeholder or final rig under
-- ReplicatedStorage.Assets (Rigs/<species>, Placeholders/<species>, or any Model whose `RigSpec`
-- attribute names the species; tools/placeholders writes these with RigSpec's final bone, socket
-- and region names), (2) for humans a stock R15 from a blank HumanoidDescription in the post's
-- palette, (3) the S5 part-built puppet (Server/AI/Puppets). Every body is readied by
-- ActorService.prepareBody (anchored root, Atomic streaming, no server Animator, Dead disabled,
-- replicated ActorId/Species attributes) and stamped with Variant and Post.
-- Interface: build(species, variant, index, post?) -> Model; template(species) -> Model?;
--   applyLook(body, look) (stock colours by species look; the blend is AvatarBlendService's)
-- Engine only inside the functions. No side effects on require.

local ActorService = require("./ActorService")
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

local function stockHuman(index: number, post: string?): Model
	local Players = game:GetService("Players")
	local desc = Instance.new("HumanoidDescription")
	local skin = Color3.fromHSV(0.07, 0.3 + (index % 4) * 0.1, 0.45 + (index % 5) * 0.1)
	local rgb = POST_SHIRTS[post or ""]
	local shirt = if rgb then Color3.fromRGB(rgb[1], rgb[2], rgb[3]) else Color3.fromHSV((index * 0.137) % 1, 0.55, 0.8)
	local pants = Color3.fromHSV((index * 0.291 + 0.5) % 1, 0.4, 0.4)
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
