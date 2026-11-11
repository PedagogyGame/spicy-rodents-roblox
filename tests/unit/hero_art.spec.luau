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

	-- Owner 2026-11-10: "I don't like the way the squirrel runs ... from the back, it looks rigid, unalive".
	t.test(
		"a hero squirrel plays its authored clips: the right one for what it is doing, in step with its stride",
		function()
			local doc = serde.decode("json", fs.readFile("data/art/heroes.json"))
			local clips = HeroAssets.CLIPS.squirrel
			for name, src in doc.species.squirrel.clips do
				t.eq(clips[name].id, "rbxassetid://" .. src.assetId, name)
				t.near(clips[name].length, src.duration, 1e-3, name)
				t.eq(clips[name].loop, src.loop, name)
			end
			for _, name in { "Idle", "Walk", "Run", "Climb", "Wire", "Leap", "Stalk" } do
				t.truthy(clips[name] ~= nil, `the rig has {name}`)
			end
			local pick, rate, H = AnimationDriver.heroClip, AnimationDriver.heroRate, AnimationDriver.HERO
			-- on the ground: standing, ambling, the bounding run, creeping
			t.eq(pick("ground", 0, false), "Idle")
			t.eq(pick("ground", 4, false), "Walk")
			t.eq(pick("ground", 18, false), "Run")
			t.eq(pick("ground", 33, false), "Run")
			t.eq(pick("ground", 4, true), "Stalk")
			t.eq(pick("ground", 0.1, true), "Stalk", "a stalk that stops holds its creep")
			t.eq(rate("Stalk", 0.1, nil, clips.Stalk.length), 0, "frozen")
			t.truthy(rate("Stalk", 4, nil, clips.Stalk.length) > 0)
			-- a run that is braking keeps to its run until it stands; one that only slows goes to a walk
			t.eq(pick("ground", 4, false, nil, "Run", true), "Run")
			t.eq(pick("ground", 4, false, nil, "Run", false), "Walk")
			t.eq(pick("ground", 4, false, nil, "Idle", true), "Walk")
			t.eq(pick("ground", 0.1, false, nil, "Run", true), "Idle")
			-- on a trunk it climbs (and hangs there when still); on a wire or bough it runs the wire clip
			t.eq(pick("trunk", 10, false), "Climb")
			t.eq(pick("trunk", 0, false), "Climb")
			t.eq(pick("rail", 20, false), "Wire")
			t.eq(pick("rail", 0, false), "Idle")
			t.eq(pick("rail", 0, true), "Idle")
			-- in the air: the leap, however it got there, but for a pounce
			t.eq(pick("air", 30, false), "Leap")
			t.eq(pick("air", 30, false, "leap"), "Leap")
			t.eq(pick("air", 30, false, "pounce"), "Pounce")
			t.truthy(clips.Pounce ~= nil)
			-- the run keeps step with the motor's stride: one bound per cadence cycle, never a blur
			local run = clips.Run.length
			t.near(rate("Run", 18, 2 * math.pi * 3, run), 3 * run, 1e-9, "three bounds a second")
			t.eq(rate("Run", 33, 2 * math.pi * 12, run), H.maxRate, "capped")
			t.near(rate("Run", 11, nil, run), 11 / H.stride.Run * run, 1e-9, "from speed when no motor says")
			t.truthy(
				rate("Walk", 4, nil, clips.Walk.length) > rate("Walk", 2, nil, clips.Walk.length),
				"faster legs at a faster walk"
			)
			t.eq(rate("Walk", 0.01, nil, clips.Walk.length), H.minRate)
			-- the clips are authored to these strides (tools/blender/heroes/clips_squirrel.py: a planted paw
			-- goes back under the body at exactly this much a cycle), so they change together or paws slide
			for name, studs in { Run = 5.5, Walk = 2.4, Climb = 3.6, Wire = 6.9, Stalk = 2.2 } do
				t.eq(H.stride[name], studs, `{name} stride`)
			end
			-- along a wire: two small bounds over 6.9 studs, in step at any speed up to the rail's 18 studs/s
			-- (with 4.5 the paws slid a third of every stride below that)
			t.near(rate("Wire", 9, nil, clips.Wire.length), 9 / 6.9 * clips.Wire.length, 1e-9, "a slow wire")
			t.near(rate("Wire", 17.9, nil, clips.Wire.length), 17.9 / 6.9 * clips.Wire.length, 1e-9)
			t.eq(rate("Wire", 18, nil, clips.Wire.length), H.maxRate, "the rail's walk is the clip's fastest")
			-- hanging still on a trunk holds the pose; idle and the leap play at their own speed
			t.eq(rate("Climb", 0, nil, clips.Climb.length), 0)
			t.truthy(rate("Climb", 10, nil, clips.Climb.length) > 0.5)
			t.eq(rate("Idle", 0, nil, clips.Idle.length), 1)
			t.eq(rate("Leap", 40, nil, clips.Leap.length), 1)
			-- a launched leap goes from its take-off to its landing in the time the body is in the air
			for name, air in H.air do
				t.truthy(air.launch < air.fall and air.fall < air.land and air.land < clips[name].length, name)
				t.near(rate(name, 18, nil, clips[name].length, 0.5), (air.land - air.launch) / 0.5, 1e-9, name)
				t.eq(rate(name, 18, nil, clips[name].length, 0.01), H.maxRate, "never a blur")
				t.eq(rate(name, 18, nil, clips[name].length, 60), H.minRate)
				t.eq(rate(name, 18, nil, clips[name].length, 0), 1)
			end
			t.eq(clips.Leap.loop, false)
			t.eq(clips.Run.loop, true)
		end
	)
end
