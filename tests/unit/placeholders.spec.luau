--!strict
-- W1 #10 placeholders: every puppet (squirrel, rodent, fox, deer doe/buck/fawn, drone, a block R15 per role
-- palette) and every vehicle kind passes Actors/RigSpec.validate (final bone, socket and region names);
-- vehicles sit exactly at their logical boxes; roots are anchored and limbs are not (HANDOFF rule 4);
-- animals are rounded (Ball / Cylinder) with their soles exactly at HipHeight below the root and
-- nothing lower, decoration never collides or answers queries, the rodent's eyes glow red;
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

	t.test("animal puppets: rounded parts, soles on the ground at HipHeight, decoration never collides", function()
		local cases = {
			PuppetSpec.spec("squirrel"),
			PuppetSpec.spec("rodent"),
			PuppetSpec.spec("fox"),
			PuppetSpec.spec("deer", { variant = "doe" }),
			PuppetSpec.spec("deer", { variant = "buck" }),
			PuppetSpec.spec("deer", { variant = "fawn" }),
		}
		for _, spec in cases do
			t.truthy(#spec.parts <= 42, `{spec.name}: {#spec.parts} parts (budget about 40)`)
			local hip = (spec.attributes :: any).HipHeight
			local model = PartBuilder.instantiate(spec, lib)
			local lowest, rounded, fur = math.huge, 0, 0
			for _, d in model:GetDescendants() do
				if not d:IsA("BasePart") then
					continue
				end
				-- the lowest corner of the part's oriented box (what GetBoundingBox sees)
				local cf, size = d.CFrame, d.Size
				local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
				local low = cf.Position.Y
					- math.abs(r.Y) * size.X / 2
					- math.abs(u.Y) * size.Y / 2
					- math.abs(l.Y) * size.Z / 2
				lowest = math.min(lowest, low)
				if string.sub(d.Name, -4) == "_Toe" then
					t.near(cf.Position.Y - size.Y / 2, -hip, 1e-4, `{spec.name}.{d.Name} sole on the ground`)
				end
				if d ~= model.PrimaryPart then
					t.falsy(d.CanCollide, `{spec.name}.{d.Name} CanCollide`)
					t.falsy(d.CanQuery, `{spec.name}.{d.Name} CanQuery`)
					t.falsy(d.CanTouch, `{spec.name}.{d.Name} CanTouch`)
				end
				if d.Shape == roblox.Enum.PartType.Ball or d.Shape == roblox.Enum.PartType.Cylinder then
					rounded += 1
					if d.Shape == roblox.Enum.PartType.Ball then
						t.near(d.Size.X, d.Size.Y, 1e-4, `{spec.name}.{d.Name} ball is round`)
						t.near(d.Size.X, d.Size.Z, 1e-4, `{spec.name}.{d.Name} ball is round`)
					else
						t.near(d.Size.Y, d.Size.Z, 1e-4, `{spec.name}.{d.Name} cylinder is round`)
					end
				end
				if d:GetAttribute("Region") == "Body" then
					fur += 1
				end
			end
			t.truthy(lowest >= -hip - 1e-3, `{spec.name}: nothing below the soles ({lowest} < {-hip})`)
			t.truthy(rounded >= 20, `{spec.name}: {rounded} rounded parts`)
			t.truthy(fur >= 10, `{spec.name}: {fur} fur parts shade with the Body region`)
		end
		-- the spicy rodent: glowing red eyes, red at the muzzle; the squirrel's eyes stay dark
		local rodent = PartBuilder.instantiate(PuppetSpec.spec("rodent"), lib)
		local eyes = rodent:FindFirstChild("Eyes")
		t.eq(eyes.Material, roblox.Enum.Material.Neon, "rodent eyes glow")
		t.truthy(eyes.Color.R > 0.8 and eyes.Color.G < 0.3, "rodent eyes are red")
		t.truthy(rodent:FindFirstChild("Blood").Color.R > rodent:FindFirstChild("Blood").Color.G * 3)
		local sqEyes = PartBuilder.instantiate(PuppetSpec.spec("squirrel"), lib):FindFirstChild("Eyes")
		t.truthy(sqEyes.Material ~= roblox.Enum.Material.Neon and sqEyes.Color.R < 0.2, "squirrel eyes dark")
	end)

	t.test("believable sizes next to a 6 st person: deer under head height, the fox a third of a person", function()
		local function top(spec: PartBuilder.ModelSpec): number
			local model = PartBuilder.instantiate(spec, lib)
			local hip = (spec.attributes :: any).HipHeight
			local high = -math.huge
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 1 then
					local cf, size = d.CFrame, d.Size
					local r, u, l = cf.RightVector, cf.UpVector, cf.LookVector
					high = math.max(
						high,
						cf.Position.Y
							+ math.abs(r.Y) * size.X / 2
							+ math.abs(u.Y) * size.Y / 2
							+ math.abs(l.Y) * size.Z / 2
					)
				end
			end
			return high + hip -- above the ground
		end
		local doe = PuppetSpec.spec("deer", { variant = "doe" })
		t.near((doe.attributes :: any).ShoulderHeight, 4, 0.25, "doe shoulder")
		t.truthy(top(doe) < 6, `doe stands {top(doe)} st (a person is 6)`)
		t.truthy(top(PuppetSpec.spec("deer", { variant = "buck" })) < 7, "buck with antlers under 7 st")
		local fox = PuppetSpec.spec("fox")
		t.near((fox.attributes :: any).ShoulderHeight, 2, 0.15, "fox shoulder")
		t.truthy(top(fox) < 3.2, `fox stands {top(fox)} st`)
		t.truthy(top(PuppetSpec.spec("human", { role = "townsperson" })) > 5.9, "a person is about 6 st")
	end)

	t.test("people: a face and hair or cap on every placeholder; no shirt reads as bare skin", function()
		for _, role in RolePalettes.ROLES do
			local model = PartBuilder.instantiate(PuppetSpec.human(role, 1, lib), lib)
			for _, name in { "EyeL", "EyeR", "Mouth" } do
				local part = model:FindFirstChild(name)
				t.truthy(part, `{role} has {name}`)
				t.truthy(part.CFrame.Position.Z < -0.55, `{role}.{name} on the face (front, -Z)`)
			end
			t.truthy(model:FindFirstChild("Hair") or model:FindFirstChild("Cap"), `{role} hair or cap`)
			for i = 1, 8 do
				local look = RolePalettes.look(role, i)
				t.falsy(RolePalettes.readsAsSkin(look.shirt, look.skin), `{role} {i} looks shirtless`)
			end
		end
		-- the v5.4 cast's tan and brown shirts are swapped; real colours pass through
		local skin = PartBuilder.hex("#986c51")
		local tan = PartBuilder.hex("#c99c83")
		t.truthy(RolePalettes.readsAsSkin(tan, skin))
		t.falsy(RolePalettes.readsAsSkin(RolePalettes.clothed(tan, skin, 3), skin))
		local blue = PartBuilder.hex("#758ba0")
		t.eq(RolePalettes.clothed(blue, skin, 3), blue)
	end)

	t.test("beacons: the patrol car's bar is bright red and blue Neon, the ambulance's red and white", function()
		for _, kind in { "patrol_car", "ambulance" } do
			local model = PartBuilder.instantiate(VehiclePuppet.spec(kind), lib)
			local a, b = model:FindFirstChild("LightBar"), model:FindFirstChild("LightBarB")
			t.truthy(a and b, `{kind} bar halves`)
			t.eq(a.Material, roblox.Enum.Material.Neon)
			t.eq(b.Material, roblox.Enum.Material.Neon)
			t.truthy(a.Color.R > 0.9 and a.Color.G < 0.3, `{kind} red half`)
			t.eq(a.Transparency, 0)
			if kind == "patrol_car" then
				t.truthy(b.Color.B > 0.9 and b.Color.R < 0.3, "patrol blue half")
			else
				t.truthy(b.Color.R > 0.9 and b.Color.G > 0.9 and b.Color.B > 0.85, "ambulance white half")
			end
		end
		local sedan = PartBuilder.instantiate(VehiclePuppet.spec("sedan"), lib)
		t.eq(sedan:FindFirstChild("LightBar").Transparency, 1, "plain cars show no bar")
		t.eq(sedan:FindFirstChild("LightBarB"), nil)
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
