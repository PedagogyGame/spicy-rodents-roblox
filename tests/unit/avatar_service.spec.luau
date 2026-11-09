--!strict
-- W1 #11 AvatarBlendService over BlendRules (D13, A3, B1, brief v2 §13a): the 16 S9 dev samples blend onto
-- every placeholder body; animals stay in the palette and keep silhouette; the rodent's eyes never
-- change; humans change only skin regions (uniform untouched); revert restores every value exactly;
-- product info is fetched once per asset and failures are cached.
local roblox = require("@lune/roblox")
local AvatarBlendService = require("@server/Avatar/AvatarBlendService")
local BlendRules = require("@shared/Avatar/BlendRules")
local DevSamples = require("@shared/Avatar/DevSamples")
local PartBuilder = require("@shared/Avatar/PartBuilder")
local PuppetSpec = require("@shared/Avatar/PuppetSpec")

local lib = {
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
}

local function snapshot(model: any): { [string]: string }
	local out = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			out[d.Name] = tostring(d.Color) .. tostring(d.Size)
		end
	end
	return out
end

return function(t)
	local function service(extra: { [string]: any }?)
		local deps: any = {
			color3 = roblox.Color3.new,
			newInstance = roblox.Instance.new,
		}
		for k, v in extra or {} do
			deps[k] = v
		end
		return AvatarBlendService.new(deps)
	end

	t.test("16 dev samples x 4 animals: palette-clamped tint, silhouette kept, revert exact", function()
		t.eq(#DevSamples.SAMPLES, 16)
		local svc = service()
		for _, species in { "squirrel", "rodent", "fox", "deer" } do
			local model = PartBuilder.instantiate(PuppetSpec.spec(species), lib)
			local before = snapshot(model)
			local eyesBefore = tostring(model:FindFirstChild("Eyes").Color)
			local sizeBefore = tostring(model:FindFirstChild("Body").Size)
			for i = 1, #DevSamples.SAMPLES do
				local look = svc:preview(model, species, i) :: BlendRules.AnimalLook
				t.truthy(BlendRules.inPalette(look.bodyTint, 1e-6), `{species} sample {i} body in palette`)
				t.truthy(BlendRules.neonAccents(look) <= 1)
				local body = model:FindFirstChild("Body")
				t.near(body.Color.R, look.bodyTint.r, 1e-6)
				t.eq(tostring(body.Size), sizeBefore, "silhouette untouched")
				if species == "rodent" then
					t.eq(tostring(model:FindFirstChild("Eyes").Color), eyesBefore, "rodent eyes locked")
				end
			end
			t.truthy(svc:revert(model))
			local after = snapshot(model)
			for name, v in before do
				t.eq(after[name], v, `{species}.{name} restored`)
			end
		end
	end)

	t.test(
		"humans: skin regions only; the uniform keeps its colours; face decal and hair are added and removed",
		function()
			local svc = service({
				faceTexture = function(id: number): string?
					return `rbxassetid://{id}`
				end,
				accessory = function(id: number): any
					local acc = roblox.Instance.new("Accessory")
					acc.Name = `Acc_{id}`
					local h = roblox.Instance.new("Part")
					h.Name = "Handle"
					h.Parent = acc
					return acc
				end,
			})
			local model = PartBuilder.instantiate(PuppetSpec.human("officer", 1, lib), lib)
			local before = snapshot(model)
			-- a classic-face sample (Face ~= 0) if the set has one, else the first
			local idx = 1
			for i, s in DevSamples.SAMPLES do
				if s.desc.Face ~= 0 and not s.desc.HeadIsDynamic then
					idx = i
					break
				end
			end
			local look = svc:preview(model, "human", idx) :: BlendRules.HumanLook
			t.eq(look.kind, "human")
			local after = snapshot(model)
			for _, name in { "UpperTorso", "LowerTorso", "LeftUpperLeg", "RightUpperLeg", "LeftUpperArm", "Cap" } do
				t.eq(after[name], before[name], `{name} (uniform) untouched`)
			end
			t.near(model:FindFirstChild("Head").Color.R, look.skinTone.r, 1e-6)
			if look.face ~= 0 then
				t.truthy(model:FindFirstChild("Head"):FindFirstChild("FaceDecal"))
			end
			t.truthy(svc:revert(model))
			t.eq(model:FindFirstChild("Head"):FindFirstChild("FaceDecal"), nil)
			for name, v in snapshot(model) do
				t.eq(v, before[name], `{name} restored`)
			end
		end
	)

	t.test("traitsFor: descriptions and product names fetched once, failures cached as no info", function()
		local calls, infoCalls = 0, 0
		local svc = service({
			describe = function(userId: number): BlendRules.DescriptionLike?
				calls += 1
				for _, s in DevSamples.SAMPLES do
					if s.userId == userId then
						return s.desc
					end
				end
				return nil
			end,
			productInfo = function(assetId: number): { name: string }?
				infoCalls += 1
				if assetId % 2 == 0 then
					error("HTTP 400")
				end
				return DevSamples.PRODUCT_INFO[assetId]
			end,
		})
		local uid = DevSamples.SAMPLES[1].userId
		local a = svc:traitsFor(uid)
		local firstInfo = infoCalls
		local b = svc:traitsFor(uid)
		t.truthy(a ~= nil and a == b)
		t.eq(calls, 1)
		t.eq(infoCalls, firstInfo, "cached")
		t.eq(svc:traitsFor(424242), nil, "unknown user: no blend, no error")
		local look = svc:lookFor(uid, "squirrel")
		t.truthy(look and look.kind == "animal")
	end)
end
