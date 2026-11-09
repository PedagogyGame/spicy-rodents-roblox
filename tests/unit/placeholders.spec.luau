--!strict
-- W1 #10 placeholders: every puppet (squirrel, rodent, fox, deer doe/buck/fawn, drone, a block R15 per role
-- palette) and every vehicle kind passes Actors/RigSpec.validate (final bone, socket and region names);
-- vehicles sit exactly at their logical boxes; roots are anchored and limbs are not (HANDOFF rule 4);
-- tools/placeholders/build.luau output matches its manifest (deterministic .rbxm).
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local PartBuilder = require("@shared/Avatar/PartBuilder")
local PuppetSpec = require("@shared/Avatar/PuppetSpec")
local RolePalettes = require("@shared/Avatar/RolePalettes")
local RigSpec = require("@shared/Actors/RigSpec")
local VehiclePuppet = require("@shared/Traffic/VehiclePuppet")
local Boxes = require("@shared/Traffic/Boxes")

local lib = {
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
}

return function(t)
	t.test("animal, drone and human puppets pass RigSpec with every final name", function()
		local cases = {
			{ "squirrel", PuppetSpec.spec("squirrel") },
			{ "rodent", PuppetSpec.spec("rodent") },
			{ "fox", PuppetSpec.spec("fox") },
			{ "deer", PuppetSpec.spec("deer", { variant = "doe" }) },
			{ "deer", PuppetSpec.spec("deer", { variant = "buck" }) },
			{ "deer", PuppetSpec.spec("deer", { variant = "fawn" }) },
			{ "drone", PuppetSpec.spec("drone") },
		}
		for _, role in RolePalettes.ROLES do
			table.insert(cases, { "human", PuppetSpec.human(role, 1, lib) })
		end
		for _, c in cases do
			local species, spec = c[1] :: string, c[2] :: PartBuilder.ModelSpec
			local model = PartBuilder.instantiate(spec, lib)
			local report = RigSpec.validate(model, species)
			t.truthy(report.ok, `{spec.name}: {serde.encode("json", report)}`)
			t.truthy(model.PrimaryPart.Anchored, "root anchored")
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d ~= model.PrimaryPart then
					t.falsy(d.Anchored, `{spec.name}.{d.Name} unanchored (rule 4)`)
				end
			end
		end
	end)

	t.test("squirrel stands 1.2 st at the shoulder; deer variants scale; the rodent alone has Blood", function()
		local sq = PuppetSpec.spec("squirrel")
		t.near((sq.attributes :: any).ShoulderHeight, 1.25, 0.06)
		local doe = (PuppetSpec.spec("deer", { variant = "doe" }).attributes :: any).HipHeight
		local fawn = (PuppetSpec.spec("deer", { variant = "fawn" }).attributes :: any).HipHeight
		t.near(fawn / doe, 0.55, 1e-9)
		t.truthy(PartBuilder.names(PuppetSpec.spec("rodent")).parts.Blood)
		t.falsy(PartBuilder.names(sq).parts.Blood)
	end)

	t.test("vehicle puppets: RigSpec.car names, the root IS the logical box, the visible body fills it", function()
		for _, kind in VehiclePuppet.KINDS do
			local spec = VehiclePuppet.spec(kind)
			local model = PartBuilder.instantiate(spec, lib)
			local report = RigSpec.validate(model, "car")
			t.truthy(report.ok, `{kind}: {serde.encode("json", report)}`)
			local box = Boxes.get(kind)
			local root = model.PrimaryPart
			t.near(root.Size.X, box.width, 1e-4)
			t.near(root.Size.Y, box.height, 1e-4)
			t.near(root.Size.Z, box.length, 1e-4)
			-- every visible part stays inside the box (what you see is what kills, D9)
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 1 then
					local p, s = d.CFrame.Position, d.Size
					t.truthy(math.abs(p.X) + s.X / 2 <= box.width / 2 + 0.05, `{kind}.{d.Name} x`)
					t.truthy(math.abs(p.Y) + s.Y / 2 <= box.height / 2 + 0.05, `{kind}.{d.Name} y`)
					t.truthy(math.abs(p.Z) + s.Z / 2 <= box.length / 2 + 0.05, `{kind}.{d.Name} z`)
				end
			end
		end
	end)

	t.test("finishStockR15: a stock R15 without joints or our sockets is completed to RigSpec.human", function()
		local model = PartBuilder.instantiate(PuppetSpec.human("nurse", 2, lib), lib)
		for _, d in model:GetDescendants() do
			if
				d:IsA("Motor6D")
				or (d:IsA("Attachment") and (d.Name == "BadgeAttachment" or d.Name == "PadAttachmentL"))
			then
				d:Destroy()
			end
		end
		t.falsy(RigSpec.validate(model, "human").ok)
		t.eq(PuppetSpec.finishStockR15(model, lib), 2, "two sockets re-added")
		t.truthy(RigSpec.validate(model, "human").ok)
	end)

	t.test("role palettes: stock HumanoidDescriptions carry the uniform colours", function()
		local desc = RolePalettes.description("officer", 1, lib)
		local look = RolePalettes.look("officer", 1)
		t.near(desc.TorsoColor.R, look.shirt.r, 1e-6)
		t.near(desc.LeftLegColor.B, look.pants.b, 1e-6)
		t.near(desc.HeadColor.G, look.skin.g, 1e-6)
		t.eq(RolePalettes.look("doctor", 3).shirt.r, PartBuilder.hex("#e9eee7").r)
	end)

	t.test("assets/placeholders match the manifest (byte-identical rebuilds)", function()
		local manifest = serde.decode("json", fs.readFile("assets/placeholders/manifest.json"))
		t.truthy(#manifest.files >= 26)
		for _, f in manifest.files do
			local bytes = fs.readFile(`assets/placeholders/{f.file}`)
			t.eq(serde.hash("sha256", bytes), f.sha, f.file)
		end
	end)
end
