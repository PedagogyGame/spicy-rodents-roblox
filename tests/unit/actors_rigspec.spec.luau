--!strict
-- Shared/Actors/RigSpec and Species (BUILD_PLAN §4.3 item 5 contracts, §5.2): the final names are
-- present and unique per rig, validate() accepts a conforming @lune/roblox model and reports what is
-- missing on a broken one, species definitions carry studs through Config/Units.
local roblox = require("@lune/roblox")
local RigSpec = require("@shared/Actors/RigSpec")
local Species = require("@shared/Actors/Species")
local Units = require("@shared/Config/Units")

local Instance = roblox.Instance

local function buildConforming(speciesId: string): any
	local c = RigSpec.get(speciesId)
	local model = Instance.new("Model")
	model.Name = speciesId
	local root = Instance.new("Part")
	root.Name = c.primaryPart
	root.Parent = model
	for _, name in c.parts or {} do
		if name ~= c.primaryPart then
			local p = Instance.new("Part")
			p.Name = name
			p.Parent = model
		end
	end
	for _, name in c.regions do
		if not model:FindFirstChild(name) then
			local p = Instance.new("MeshPart")
			p.Name = name
			p.Parent = model
		end
	end
	for _, name in c.sockets do
		local a = Instance.new("Attachment")
		a.Name = name
		a.Parent = root
	end
	for _, name in c.bones do
		local m = Instance.new("Motor6D")
		m.Name = name
		m.Parent = root
	end
	return model
end

return function(t)
	t.test("seven contracts, each with unique bone, socket and region names", function()
		t.eq(#RigSpec.species(), 7)
		for _, id in RigSpec.species() do
			local c = RigSpec.get(id)
			t.eq(c.id, id)
			for _, list in { c.bones, c.sockets, c.regions, c.parts or {} } do
				local seen = {}
				for _, name in list do
					t.falsy(seen[name], `{id}: duplicate {name}`)
					seen[name] = true
				end
			end
		end
	end)

	t.test("squirrel: Root, Spine1-3, Tail1-8, four legs x four segments, the four sockets, the regions", function()
		local c = RigSpec.squirrel
		t.eq(#c.bones, 35)
		t.truthy(table.find(c.bones, "Root"))
		t.truthy(table.find(c.bones, "Tail8"))
		t.falsy(table.find(c.bones, "Tail9"))
		t.truthy(table.find(c.bones, "FrontL_Upper"))
		t.truthy(table.find(c.bones, "BackR_Toe"))
		t.deepEq(c.sockets, { "HeadSocket", "MouthSocket", "TailTip", "ChestCenter" })
		t.deepEq(c.regions, { "Body", "Pattern", "Eyes", "FurCards" })
		t.eq(c.primaryPart, "RootPart")
		t.eq(c.bubbleHead, "Head")
	end)

	t.test("rodent shares the squirrel skeleton and adds the Blood region; fox has Tail1-6; deer Neck1-3", function()
		t.eq(RigSpec.rodent.bones, RigSpec.squirrel.bones)
		t.truthy(table.find(RigSpec.rodent.regions, "Blood"))
		t.truthy(table.find(RigSpec.fox.bones, "Tail6"))
		t.falsy(table.find(RigSpec.fox.bones, "Tail7"))
		t.truthy(table.find(RigSpec.deer.bones, "Neck3"))
		t.truthy(table.find(RigSpec.deer.bones, "Tail2"))
		t.falsy(table.find(RigSpec.deer.bones, "Tail3"))
		t.near((RigSpec.deer.scaleVariants :: any).fawn, 0.55)
	end)

	t.test("human is standard R15 with our attachments and the skin regions; car and drone list their parts", function()
		local h = RigSpec.human
		t.eq(#(h.parts :: { string }), 16)
		t.truthy(table.find(h.parts :: { string }, "HumanoidRootPart"))
		t.truthy(table.find(h.bones, "LeftAnkle"))
		t.truthy(table.find(h.sockets, "HairAttachment"))
		t.truthy(table.find(h.sockets, "MaskAttachment"))
		t.truthy(table.find(h.regions, "Head"))
		t.truthy(table.find(RigSpec.car.sockets, "EyeSocket"))
		t.truthy(table.find(RigSpec.car.parts :: { string }, "WheelBR"))
		t.truthy(table.find(RigSpec.drone.parts :: { string }, "Rotor4"))
		t.near((RigSpec.car.hitbox.size :: { number })[1], Units.st(2.35))
	end)

	t.test("validate accepts a conforming model for every contract", function()
		for _, id in RigSpec.species() do
			local model = buildConforming(id)
			local report = RigSpec.validate(model, id)
			t.truthy(
				report.ok,
				`{id}: bones {#report.missingBones} sockets {#report.missingSockets} regions {#report.missingRegions} parts {#report.missingParts} primary {tostring(
					report.primaryPartOk
				)}`
			)
		end
	end)

	t.test("validate reports exactly what is missing", function()
		local model = buildConforming("squirrel")
		local root = model:FindFirstChild("RootPart")
		root:FindFirstChild("Tail8"):Destroy()
		root:FindFirstChild("HeadSocket"):Destroy()
		model:FindFirstChild("Pattern"):Destroy()
		local report = RigSpec.validate(model, "squirrel")
		t.falsy(report.ok)
		t.deepEq(report.missingBones, { "Tail8" })
		t.deepEq(report.missingSockets, { "HeadSocket" })
		t.deepEq(report.missingRegions, { "Pattern" })
		t.truthy(report.primaryPartOk)
	end)

	t.test("validate reads the species from the Species attribute or the model name", function()
		local model = buildConforming("fox")
		model.Name = "whatever"
		model:SetAttribute("Species", "fox")
		t.truthy(RigSpec.validate(model).ok)
		t.fails(function()
			RigSpec.validate(buildConforming("deer"), "dragon")
		end, "no contract")
	end)

	t.test("species: four actor species, studs via Units, 7 squirrel furs plus the rodent", function()
		t.deepEq(Species.list(), { "human", "squirrel", "fox", "deer" })
		local sq = Species.def("squirrel")
		t.near(sq.speeds.walk, Units.st(7.2))
		t.near(sq.speeds.sprint, Units.st(13.2))
		t.near((sq.speeds.rail :: any).walk, Units.st(7.2))
		t.near((sq.speeds.rail :: any).woodMultiplier, 0.6)
		t.near(sq.hitbox.radius, Units.st(0.32))
		t.eq(#sq.stockLooks, 8)
		t.eq(Species.stockLook("squirrel", 9).name, "fur0", "wraps")
		t.eq(Species.rodentLook().name, "spicy")
		t.truthy(Species.rodentLook().eyesLocked)
		t.near(Species.def("fox").speeds.sprint, Units.st(8.8))
		t.near(Species.def("deer").leash :: number, Units.st(95))
		t.near(Species.def("human").speeds.flee :: number, Units.st(7.6))
		t.fails(function()
			Species.def("dragon")
		end, "unknown species")
	end)
end
