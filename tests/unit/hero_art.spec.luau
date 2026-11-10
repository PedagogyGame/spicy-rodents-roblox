--!strict
-- tests/unit/hero_art.spec.luau
-- The sculpted squirrel and Spicy Rodent in place of the puppets: Shared/Actors/HeroAssets agrees with
-- data/art/heroes.json; Server/Assets/HeroArt turns an uploaded model (as measured on the CI place: the
-- root part at the feet holding the Bones, skinned region MeshParts on Motor6Ds with a
-- SurfaceAppearance) into a body template that passes RigSpec with the root at HipHeight, the stock
-- tints and the sockets; a failed or malformed load installs nothing for that animal; the client gait
-- finds the same joints by name on a puppet (Motor6Ds) and on a hero (Bones).

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local HeroAssets = require("@shared/Actors/HeroAssets")
local RigSpec = require("@shared/Actors/RigSpec")
local PuppetSpec = require("@shared/Avatar/PuppetSpec")
local PartBuilder = require("@shared/Avatar/PartBuilder")
local AnimationDriver = require("@client/Animation/AnimationDriver")

local HeroArt = require("@server/Assets/HeroArt")

local Instance = roblox.Instance
local LIB = {
	Instance = roblox.Instance,
	Vector3 = (roblox :: any).Vector3,
	CFrame = (roblox :: any).CFrame,
	Color3 = (roblox :: any).Color3,
	Enum = (roblox :: any).Enum,
}

-- An upload as LoadAsset returns it: a wrapper Model holding the hero Model.
local function upload(name: string, drop: string?): any
	local contract = RigSpec.get(name)
	local wrapper = Instance.new("Model")
	local model = Instance.new("Model")
	model.Name = "Spicy Rodents hero " .. name
	local root = Instance.new("Part")
	root.Name = "RootPart"
	root.Size = (roblox :: any).Vector3.new(2, 2, 1)
	root.Parent = model
	model.PrimaryPart = root
	local bones: { [string]: any } = {}
	for _, boneName in contract.bones do
		if boneName ~= drop then
			local b = Instance.new("Bone")
			b.Name = boneName
			b.Parent = root
			bones[boneName] = b
		end
	end
	for _, regionName in contract.regions do
		if regionName ~= drop then
			local part = Instance.new("MeshPart")
			part.Name = regionName
			part.Parent = model
			local sa = Instance.new("SurfaceAppearance")
			sa.Parent = part
			local m = Instance.new("Motor6D")
			m.Name = regionName .. "Motor6D"
			m.Part0 = root
			m.Part1 = part
			m.Parent = part
		end
	end
	model.Parent = wrapper
	return wrapper
end

return function(t: any)
	t.test("HeroAssets is what data/art/heroes.json records", function()
		local doc = serde.decode("json", fs.readFile("data/art/heroes.json"))
		for name, entry in HeroAssets.SPECIES do
			local src = doc.species[name]
			t.truthy(src ~= nil, name)
			t.eq(entry.assetId, tonumber(src.model.assetId), `{name} asset id`)
			t.eq(src.model.moderation, "Approved", `{name} is approved`)
			t.eq(src.bonesMatchRigSpec, true)
			t.near(entry.hipHeight, src.hipHeight, 1e-9)
			for regionName, region in src.regions do
				t.eq(entry.regions[regionName].alphaMode, region.alphaMode, `{name}.{regionName} mode`)
				t.eq(entry.regions[regionName].tint, region.tint, `{name}.{regionName} tint`)
			end
			for socketName, socket in src.sockets do
				t.eq(entry.sockets[socketName].bone, socket.bone)
				for i = 1, 3 do
					t.near(entry.sockets[socketName].offset[i], socket.offset[i], 1e-9, `{name}.{socketName}`)
				end
			end
		end
		t.truthy(HeroAssets.SPECIES.squirrel ~= nil and HeroAssets.SPECIES.rodent ~= nil)
		t.truthy(HeroAssets.SPECIES.squirrel.assetId ~= HeroAssets.SPECIES.rodent.assetId)
	end)

	t.test("prepare: the root at HipHeight over the feet, RigSpec passes, tints and sockets are set", function()
		for _, name in { "squirrel", "rodent" } do
			local entry = HeroAssets.SPECIES[name]
			local wrapper = upload(name)
			local model = wrapper:FindFirstChildWhichIsA("Model")
			local feet = model.PrimaryPart
			local out = HeroArt.prepare(model, name, entry, LIB)
			t.eq(out.Name, name)
			local root = out.PrimaryPart
			t.eq(root.Name, "RootPart")
			t.truthy(root ~= feet, "a new root")
			t.eq(feet.Name, "SkinRoot")
			t.near(root.CFrame.Position.Y - feet.CFrame.Position.Y, 0.9, 1e-4, "the root rides 0.9 st over the feet")
			t.eq(out:GetAttribute("HipHeight"), 0.9)
			t.eq(out:GetAttribute("Hero"), true)
			local weld = root:FindFirstChild("SkinRootWeld")
			t.truthy(weld ~= nil and weld.Part0 == root and weld.Part1 == feet, "the skin hangs from the root")
			t.near(weld.C0.Position.Y, -0.9, 1e-4)
			local report = RigSpec.validate(out, name)
			t.truthy(report.ok, serde.encode("json", report))
			for regionName, region in entry.regions do
				local sa = out:FindFirstChild(regionName):FindFirstChildOfClass("SurfaceAppearance")
				t.eq(sa.AlphaMode.Name, region.alphaMode, `{name}.{regionName}`)
				if region.tint then
					local c = sa.Color
					t.truthy(c.R < 0.999 or c.G < 0.999, `{name}.{regionName} is tinted`)
				end
			end
			for socketName, socket in entry.sockets do
				local a = out:FindFirstChild(socketName, true)
				t.eq(a.ClassName, "Attachment")
				t.eq(a.Parent.Name, socket.bone)
				t.near(a.Position.Y, socket.offset[2], 1e-4)
			end
			-- only the Spicy Rodent's eyes glow
			t.eq(out:FindFirstChild("EyeGlow", true) ~= nil, name == "rodent", `{name} eye glow`)
		end
	end)

	t.test("install: templates land under Rigs; a failed or malformed load installs nothing for that animal", function()
		local parent = Instance.new("Folder")
		local report = HeroArt.install({
			parent = parent,
			lib = LIB,
			load = function(assetId: number): any
				if assetId == HeroAssets.SPECIES.squirrel.assetId then
					return upload("squirrel")
				end
				error("HTTP 403 (not owned)")
			end,
		})
		t.deepEq(report.installed, { "squirrel" })
		t.truthy(string.find(report.failed.rodent, "403", 1, true) ~= nil, report.failed.rodent)
		local rigs = parent:FindFirstChild("Rigs")
		t.truthy(rigs:FindFirstChild("squirrel") ~= nil)
		t.eq(rigs:FindFirstChild("rodent"), nil, "the rodent keeps its puppet")
		-- a model missing a bone, a region or its root is refused whole
		for _, drop in { "Tail5", "Pattern" } do
			local p2 = Instance.new("Folder")
			local r2 = HeroArt.install({
				parent = p2,
				lib = LIB,
				entries = { squirrel = HeroAssets.SPECIES.squirrel },
				load = function(_assetId: number): any
					return upload("squirrel", drop)
				end,
			})
			t.eq(#r2.installed, 0, `missing {drop}`)
			t.truthy(r2.failed.squirrel ~= nil)
			t.eq(p2:FindFirstChild("Rigs"):FindFirstChild("squirrel"), nil)
		end
		local p3 = Instance.new("Folder")
		local r3 = HeroArt.install({
			parent = p3,
			lib = LIB,
			entries = { squirrel = HeroAssets.SPECIES.squirrel },
			load = function(_assetId: number): any
				return Instance.new("Model")
			end,
		})
		t.truthy(string.find(r3.failed.squirrel, "no Model", 1, true) ~= nil, r3.failed.squirrel)
		-- a rig already in place is left alone
		local again = HeroArt.install({
			parent = parent,
			lib = LIB,
			load = function(_assetId: number): any
				error("must not load: squirrel is installed")
			end,
			entries = { squirrel = HeroAssets.SPECIES.squirrel },
		})
		t.eq(#again.installed, 0)
		t.eq(next(again.failed), nil)
	end)

	t.test("the gait finds the same joints on a puppet (Motor6Ds) and on a hero (Bones)", function()
		local puppet = PartBuilder.instantiate(PuppetSpec.spec("squirrel"), LIB)
		local hero = HeroArt.prepare(
			upload("squirrel"):FindFirstChildWhichIsA("Model"),
			"squirrel",
			HeroAssets.SPECIES.squirrel,
			LIB
		)
		local function names(model: any): ({ [string]: string }, number)
			local joints, tailN = AnimationDriver.gaitJoints(model)
			local out: { [string]: string } = {}
			for _, j in joints do
				out[j.motor.Name] = j.motor.ClassName
			end
			return out, tailN
		end
		local pj, pt = names(puppet)
		local hj, ht = names(hero)
		t.eq(pt, 8)
		t.eq(ht, 8)
		local n = 0
		for name, class in pj do
			n += 1
			t.eq(class, "Motor6D")
			t.eq(hj[name], "Bone", `the hero has {name}`)
		end
		for name in hj do
			t.truthy(pj[name] ~= nil, `the puppet has {name}`)
		end
		t.truthy(n >= 18, `{n} gait joints`)
		t.eq(hj.BodyMotor6D, nil, "a region's own joint is not a gait joint")
	end)
end
