--!strict
-- tests/unit/people_art.spec.luau
-- The rounded townspeople (tools/blender/people): Shared/Avatar/PeopleAssets agrees with data/art/people.json;
-- the rig keeps the stock R15's joint names and positions except the elbows and wrists, and every joint's two
-- sides meet at its pivot; the triangle budget; Shared/Avatar/PeopleLooks dresses every role and post; and, on
-- the fake engine, Server/Assets/PeopleArt does nothing without ids, swaps a block R15's fifteen parts for the art
-- (same names, same Humanoid and root, the Motor6Ds and attachments moved and re-pivoted, RigSpec still passes,
-- nothing left pointing at a removed part), welds the extras, hair and hat, dresses the baked lounge staff as
-- statues facing where they faced, and the avatar blend tints only the art's skin.

local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")

local PartBuilder = require("@shared/Avatar/PartBuilder")
local PeopleAssets = require("@shared/Avatar/PeopleAssets")
local PeopleLooks = require("@shared/Avatar/PeopleLooks")
local PuppetSpec = require("@shared/Avatar/PuppetSpec")
local RigSpec = require("@shared/Actors/RigSpec")

local AvatarBlendService = require("@server/Avatar/AvatarBlendService")
local PeopleArt = require("@server/Assets/PeopleArt")

local Instance = roblox.Instance
local R = roblox :: any
local LIB = { Instance = roblox.Instance, Vector3 = R.Vector3, CFrame = R.CFrame, Color3 = R.Color3, Enum = R.Enum }

local function vec(v: { number }): any
	return R.Vector3.new(v[1], v[2], v[3])
end

local function near3(t: any, a: any, b: any, eps: number, msg: string)
	t.truthy((a - b).Magnitude < eps, `{msg}: {a} vs {b}`)
end

-- The six uploads as LoadAsset would hold them: MeshParts named as the files' objects, each with a
-- SurfaceAppearance (marked with the texture set it carries).
local function square(parent: any, name: string, set: string)
	local p = Instance.new("MeshPart")
	p.Name = name
	local sa = Instance.new("SurfaceAppearance")
	sa:SetAttribute("Set", set)
	sa.Parent = p
	p.Parent = parent
end

local function fakeAssets(): { [string]: any }
	local out: { [string]: any } = {}
	for build, key in { slim = "bodySlim", broad = "bodyBroad" } do
		local m = Instance.new("Model")
		local rig = PeopleAssets.BUILDS[build]
		for name, p in rig.parts do
			if name ~= "Head" then
				square(m, name, "body_shirt")
				m[name].Size = vec(p.size)
			end
		end
		for name, e in rig.extras do
			square(m, name, "body_shirt")
			m[name].Size = vec(e.size)
		end
		out[key] = m
	end
	out.head = Instance.new("Model")
	square(out.head, "Head", "head_plain_calm")
	out.headwear = Instance.new("Model")
	for name, w in PeopleAssets.HEADWEAR do
		square(out.headwear, name, "headwear")
		out.headwear[name].Size = vec(w.size)
	end
	out.outfits = Instance.new("Model")
	for outfit in PeopleAssets.OUTFITS do
		square(out.outfits, `Outfit_{outfit}`, `body_{outfit}`)
	end
	out.faces = Instance.new("Model")
	for _, f in PeopleAssets.HEAD.faces do
		for _, e in PeopleAssets.HEAD.expressions do
			square(out.faces, `Face_{f}_{e}`, `head_{f}_{e}`)
		end
	end
	return out
end

-- A stock block R15 (PuppetSpec's, as Actors/BodyFactory's fallback builds it) with the stock extras the engine's
-- CreateHumanoidModelFromDescription adds: the face decal, BodyColors, an OriginalSize value.
local function stockR15(): any
	local model = PartBuilder.instantiate(PuppetSpec.spec("human", { role = "townsperson", index = 2 }), LIB)
	-- the engine's R15 has no block hair or cap (the puppet's eyes and mouth stay: welds onto the head)
	for _, name in { "Hair", "HairBack", "Cap" } do
		local p = model:FindFirstChild(name)
		if p then
			p:Destroy()
		end
	end
	local face = Instance.new("Decal")
	face.Name = "face"
	face.Parent = model.Head
	Instance.new("BodyColors").Parent = model
	local size = Instance.new("Vector3Value")
	size.Name = "OriginalSize"
	size.Value = model.UpperTorso.Size
	size.Parent = model.UpperTorso
	local grip = model.RightHand:FindFirstChild("RightGripAttachment")
	if grip then
		grip.CFrame = R.CFrame.new(grip.CFrame.Position) * R.CFrame.Angles(-math.pi / 2, 0, 0)
	end
	return model
end

return function(t: any)
	t.test("PeopleAssets is what data/art/people.json records", function()
		local doc = serde.decode("json", fs.readFile("data/art/people.json"))
		for _, key in PeopleArt.KEYS do
			local a = doc.assets[key]
			t.truthy(a ~= nil, key)
			t.eq(PeopleAssets.ASSETS[key], if a.assetId then tonumber(a.assetId) else 0, `{key} id`)
			if a.assetId then
				t.eq(a.moderation, "Approved", `{key} is approved`)
			end
		end
		for build, b in doc.rig.builds do
			local mine = PeopleAssets.BUILDS[build]
			for name, p in b.parts do
				for i = 1, 3 do
					t.near(mine.parts[name].center[i], p.center[i], 1e-4, `{build}.{name} centre`)
				end
			end
			for name, j in b.joints do
				t.eq(mine.joints[name].part0, j.part0)
				t.eq(mine.joints[name].part1, j.part1)
				for i = 1, 3 do
					t.near(mine.joints[name].c0[i], j.c0[i], 1e-4, `{build}.{name} c0`)
					t.near(mine.joints[name].c1[i], j.c1[i], 1e-4, `{build}.{name} c1`)
				end
			end
			for name, a in b.attachments do
				t.eq(mine.attachments[name].part, a.part, name)
				for i = 1, 3 do
					t.near(mine.attachments[name].position[i], a.position[i], 1e-4, `{build}.{name}`)
				end
			end
			for name, e in b.extras do
				t.eq(mine.extras[name].weldTo, e.weldTo, name)
				t.eq(mine.extras[name].tint, e.tint, name)
			end
		end
		for outfit, o in doc.rig.outfits do
			t.deepEq(PeopleAssets.OUTFITS[outfit].tints, o.tints, outfit)
			t.deepEq(PeopleAssets.OUTFITS[outfit].extras, o.extras, outfit)
		end
		for name, h in doc.rig.headwear do
			t.eq(PeopleAssets.HEADWEAR[name].tint, h.tint, name)
			t.eq(PeopleAssets.HEADWEAR[name].underCap, h.underCap, name)
		end
		for role, r in doc.rig.roles do
			t.deepEq(PeopleAssets.ROLES[role].hair, r.hair, role)
			t.eq(PeopleAssets.ROLES[role].hat, r.hat, role)
		end
	end)

	t.test("the rig is the stock R15's, the elbows and wrists under the shoulder, every joint closed", function()
		local stock: { [string]: { number } } = {
			Root = { 0, -1, 0 },
			Waist = { 0, -0.6, 0 },
			Neck = { 0, 1, 0 },
			LeftShoulder = { -1, 0.763, 0 },
			RightShoulder = { 1, 0.763, 0 },
			LeftElbow = { -1.04, 0.035, 0 },
			RightElbow = { 1.04, 0.035, 0 },
			LeftWrist = { -1.05, -0.75, 0 },
			RightWrist = { 1.05, -0.75, 0 },
			LeftHip = { -0.5, -1, 0 },
			RightHip = { 0.5, -1, 0 },
			LeftKnee = { -0.5, -1.822, 0 },
			RightKnee = { 0.5, -1.822, 0 },
			LeftAnkle = { -0.5, -2.748, 0 },
			RightAnkle = { 0.5, -2.748, 0 },
		}
		for build, rig in PeopleAssets.BUILDS do
			local n = 0
			for _, bone in RigSpec.human.bones do
				local j = rig.joints[bone]
				t.truthy(j ~= nil, `{build} has {bone}`)
				local c0 = if j.part0 == "HumanoidRootPart" then vec({ 0, 0, 0 }) else vec(rig.parts[j.part0].center)
				local c1 = vec(rig.parts[j.part1].center)
				near3(t, c0 + vec(j.c0), vec(stock[bone]), 2e-3, `{build} {bone} from part0`)
				near3(t, c1 + vec(j.c1), vec(stock[bone]), 2e-3, `{build} {bone} from part1`)
				n += 1
			end
			t.eq(n, 15)
			for _, part in RigSpec.human.parts or {} do
				t.truthy(part == "HumanoidRootPart" or rig.parts[part] ~= nil, `{build} has {part}`)
			end
			for _, socket in RigSpec.human.sockets do
				t.truthy(rig.attachments[socket] ~= nil, `{build} has socket {socket}`)
			end
		end
	end)

	t.test("a person costs under 6,000 triangles at worst, inside RigSpec's human budget", function()
		for build, rig in PeopleAssets.BUILDS do
			local body = 0
			for _, p in rig.parts do
				body += p.tris
			end
			t.eq(body, rig.triangles.body, `{build} body`)
			local worst = 0
			for outfit, o in PeopleAssets.OUTFITS do
				local n = body
				for _, e in o.extras do
					n += rig.extras[e].tris
				end
				local hair, hat = 0, 0
				for _, w in PeopleAssets.HEADWEAR do
					if w.kind == "hair" then
						hair = math.max(hair, w.tris)
					else
						hat = math.max(hat, w.tris)
					end
				end
				worst = math.max(worst, n + hair + hat)
				local _ = outfit
			end
			t.truthy(worst < 6000, `{build} worst case {worst}`)
			t.truthy(worst <= RigSpec.human.budget.tris, `{build} inside RigSpec`)
		end
	end)

	t.test("PeopleLooks dresses every role and post from the art, the same on every call", function()
		local roles = {}
		for r in PeopleAssets.ROLES do
			table.insert(roles, r)
		end
		for r in PeopleLooks.ROLES do
			table.insert(roles, r)
		end
		for _, role in roles do
			for i = 1, 12 do
				local d = PeopleLooks.dress(role, i)
				t.truthy(PeopleAssets.BUILDS[d.build] ~= nil, `{role} build`)
				t.truthy(PeopleAssets.OUTFITS[d.outfit] ~= nil, `{role} outfit`)
				t.truthy(table.find(PeopleAssets.HEAD.faces, d.face) ~= nil, `{role} face`)
				if d.hat then
					t.eq(PeopleAssets.HEADWEAR[d.hat].kind, "hat")
					t.truthy(d.hair == nil or PeopleAssets.HEADWEAR[d.hair].underCap, `{role} {i}: hair under the hat`)
				end
				if d.hair then
					t.eq(PeopleAssets.HEADWEAR[d.hair].kind, "hair")
				end
				for _, key in PeopleAssets.OUTFITS[d.outfit].tints do
					local c = PeopleLooks.tint(d, key)
					t.truthy(c.r >= 0 and c.r <= 1 and c.g >= 0 and c.g <= 1 and c.b >= 0 and c.b <= 1, key)
				end
				t.deepEq(PeopleLooks.dress(role, i), d, `{role} {i} is deterministic`)
			end
		end
		t.eq(PeopleLooks.roleOf("police", 1), "officer")
		t.eq(PeopleLooks.roleOf("ambulance_crew", 1), "paramedic")
		t.eq(PeopleLooks.roleOf("shop_worker", 1), "shopkeeper")
		t.eq(PeopleLooks.roleOf("hospital_staff", 1), "doctor")
		t.eq(PeopleLooks.roleOf(nil, 1), "townsperson")
		t.eq(PeopleLooks.dress("paramedic", 4).hat, nil)
		t.eq(PeopleLooks.dress("doorman", 1).build, "broad")
		t.eq(PeopleLooks.dress("doorman", 1).hat, "Hat_cap")
		-- the given colours win (Actors/BodyFactory's cast and palette picks), the role's fixed ones over those
		local skin = { r = 0.3, g = 0.2, b = 0.1 }
		t.deepEq(PeopleLooks.dress("townsperson", 3, { skin = skin }).colours.skin, skin)
		t.deepEq(PeopleLooks.dress("paramedic", 3, { shirt = skin }).colours.shirt, PartBuilder.hex("#e6782a"))
	end)

	t.test("without uploaded ids nothing is loaded and no body is touched", function()
		PeopleArt.reset()
		local loads = 0
		local report = PeopleArt.install({
			load = function(_id: number): any
				loads += 1
				return Instance.new("Model")
			end,
		})
		if PeopleAssets.ASSETS.bodySlim == 0 then
			t.eq(report.ok, false)
			t.eq(loads, 0)
			t.eq(PeopleArt.ready(), false)
		end
		PeopleArt.reset()
		local model = stockR15()
		local head = model.Head
		t.eq(PeopleArt.dress(model, PeopleLooks.dress("townsperson", 1), { lib = LIB }), false)
		t.eq(model.Head, head)
		t.eq(PeopleArt.statue(model, PeopleLooks.dress("townsperson", 1), { lib = LIB }), false)
	end)

	t.test("a load that fails or misses a mesh leaves the stock bodies", function()
		PeopleArt.reset()
		local ids = { bodySlim = 1, bodyBroad = 2, head = 3, headwear = 4, outfits = 5, faces = 6 }
		local assets = fakeAssets()
		local byId = { assets.bodySlim, assets.bodyBroad, assets.head, assets.headwear, assets.outfits, assets.faces }
		local r = PeopleArt.install({
			ids = ids,
			load = function(id: number): any
				if id == 4 then
					error("HTTP 403")
				end
				return byId[id]
			end,
		})
		t.eq(r.ok, false)
		t.truthy(r.failed.headwear ~= nil)
		t.eq(PeopleArt.ready(), false)
		assets.bodyBroad.LeftFoot:Destroy()
		r = PeopleArt.install({
			ids = ids,
			load = function(id: number): any
				return byId[id]
			end,
		})
		t.eq(r.ok, false)
		t.truthy(string.find(r.failed.index, "LeftFoot") ~= nil, r.failed.index)
		t.eq(PeopleArt.ready(), false)
	end)

	t.test("a stock R15 is dressed in the art and keeps the rig the game reads", function()
		local library = PeopleArt.index(fakeAssets())
		local opts = { lib = LIB, library = library }
		for _, case in { { "townsperson", 2 }, { "doctor", 3 }, { "nurse", 1 }, { "officer", 6 }, { "mime", 1 } } do
			local model = stockR15()
			local humanoid = model:FindFirstChildOfClass("Humanoid")
			local root = model.HumanoidRootPart
			local motors0 = 0
			for _, d in model:GetDescendants() do
				if d:IsA("Motor6D") then
					motors0 += 1
				end
			end
			local dress = PeopleLooks.dress(case[1] :: string, case[2] :: number)
			t.eq(PeopleArt.dress(model, dress, opts), true, case[1])
			t.eq(model:FindFirstChildOfClass("Humanoid"), humanoid)
			t.eq(humanoid.HipHeight, 2, "HipHeight: the soles 3 studs under the root's centre")
			t.eq(model.HumanoidRootPart, root)
			t.eq(model:GetAttribute("PeopleArt"), case[1])
			local rig = PeopleAssets.BUILDS[dress.build]
			for name in rig.parts do
				local p = model:FindFirstChild(name)
				t.truthy(p ~= nil and p:IsA("MeshPart") and p:GetAttribute("PeopleArt") == true, `{name} is art`)
				local n = 0
				for _, c in model:GetChildren() do
					if c.Name == name then
						n += 1
					end
				end
				t.eq(n, 1, `one {name}`)
			end
			t.eq(model.Head:FindFirstChild("face"), nil, "the stock face decal goes")
			near3(t, model.Head:GetAttribute("EyeOffset"), vec(PeopleArt.EYE), 1e-4, "where the red eyes go")
			t.eq(model:FindFirstChildOfClass("BodyColors"), nil)
			t.eq(model.UpperTorso.OriginalSize.Value, model.UpperTorso.Size)
			local sa = model.UpperTorso:FindFirstChildOfClass("SurfaceAppearance")
			t.eq(sa:GetAttribute("Set"), `body_{dress.outfit}`, "the outfit's texture")
			t.eq(model.Head:FindFirstChildOfClass("SurfaceAppearance"):GetAttribute("Set"), `head_{dress.face}_calm`)
			-- the joints: all still there, on the new parts, at the art's pivots; nothing points at a removed part
			local motors = 0
			for _, d in model:GetDescendants() do
				if d:IsA("JointInstance") then
					t.truthy(d.Part0 and d.Part0.Parent == model, `{d.Name} part0 in the model`)
					t.truthy(d.Part1 and d.Part1.Parent == model, `{d.Name} part1 in the model`)
					-- at rest both sides of every joint meet
					near3(t, (d.Part0.CFrame * d.C0).Position, (d.Part1.CFrame * d.C1).Position, 1e-3, d.Name)
				end
				if d:IsA("Motor6D") then
					motors += 1
				end
			end
			t.eq(motors, motors0, "no Motor6D lost or added")
			for bone, j in rig.joints do
				local m = model[j.part1]:FindFirstChild(bone)
				t.truthy(m ~= nil and m:IsA("Motor6D"), bone)
				t.eq(m.Part0.Name, j.part0, bone)
				near3(t, m.C0.Position, vec(j.c0), 1e-4, `{bone} C0`)
			end
			-- the attachments: RigSpec's sockets on the art's surface, the grip keeps its turn
			for name, a in rig.attachments do
				local att = model[a.part]:FindFirstChild(name)
				t.truthy(att ~= nil and att:IsA("Attachment"), name)
				near3(t, att.CFrame.Position, vec(a.position), 1e-4, name)
			end
			local grip = model.RightHand.RightGripAttachment
			near3(t, grip.CFrame.UpVector, R.Vector3.new(0, 0, -1), 1e-3, "grip turn")
			t.truthy(RigSpec.validate(model, "human").ok, "RigSpec passes")
			-- extras, hair and hat on welds, out of the way of collisions and queries
			local want = table.clone(PeopleAssets.OUTFITS[dress.outfit].extras)
			if dress.hair then
				table.insert(want, "Hair")
			end
			if dress.hat then
				table.insert(want, "Hat")
			end
			for _, name in want do
				local p = model:FindFirstChild(name)
				t.truthy(p ~= nil, `{case[1]} wears {name}`)
				t.eq(p.CanCollide, false)
				t.eq(p.CanQuery, false)
				t.eq(p.Massless, true)
				local w = p:FindFirstChild("PeopleWeld")
				t.truthy(w ~= nil and w.Part1 == p and w.Part0.Parent == model, `{name} welded`)
			end
			-- the colours: each part in its tint
			local tints = PeopleAssets.OUTFITS[dress.outfit].tints
			for name, key in tints do
				local p = model:FindFirstChild(name)
				if p then
					local c = PeopleLooks.tint(dress, key)
					near3(t, R.Vector3.new(p.Color.R, p.Color.G, p.Color.B), R.Vector3.new(c.r, c.g, c.b), 0.01, name)
					t.eq(p:GetAttribute("PeopleTint"), key)
				end
			end
		end
	end)

	t.test("a body that is not a whole R15 is left alone", function()
		local library = PeopleArt.index(fakeAssets())
		local model = stockR15()
		model.LeftFoot:Destroy()
		local head = model.Head
		t.eq(PeopleArt.dress(model, PeopleLooks.dress("townsperson", 1), { lib = LIB, library = library }), false)
		t.eq(model.Head, head)
		t.eq(model:GetAttribute("PeopleArt"), nil)
	end)

	t.test("the lounge's baked staff stand as rounded people, facing where they faced", function()
		local library = PeopleArt.index(fakeAssets())
		local venue = Instance.new("Model")
		local staff = Instance.new("Model")
		staff.Name = "Staff"
		staff.Parent = venue
		local function figure(name: string, kind: string, tall: number, yaw: number): any
			local m = Instance.new("Model")
			m.Name = name
			m:SetAttribute("Staff", kind)
			local root = Instance.new("Part")
			root.Name = "Root"
			root.Size = R.Vector3.new(2, 5.8 * tall, 1.1)
			root.CFrame = R.CFrame.new(10, 2.9 * tall, 4) * R.CFrame.Angles(0, yaw, 0)
			root.Parent = m
			m.PrimaryPart = root
			for _, part in { "Body", "Leg-1", "Head", "Cap" } do
				local p = Instance.new("Part")
				p.Name = part
				p.Parent = m
			end
			m.Parent = staff
			return m
		end
		local guard = figure("Guard1", "guard", 1.08, 0.7)
		local bartender = figure("Bartender", "bartender", 1.0, 0)
		t.eq(PeopleArt.start(venue, { lib = LIB, library = library }), 2)
		t.eq(PeopleArt.start(venue, { lib = LIB, library = library }), 0, "dressed once")
		for _, case in { { guard, 1.08, "doorman" }, { bartender, 1.0, "bartender" } } do
			local m, s = case[1], case[2]
			t.eq(m:GetAttribute("PeopleArt"), case[3])
			t.eq(m.PrimaryPart.Name, "Root")
			t.eq(m:FindFirstChild("Body"), nil, "the box figure's parts go")
			local root = m.PrimaryPart
			local top, bottom = -math.huge, math.huge
			for _, p in m:GetChildren() do
				if p:IsA("BasePart") and p ~= root then
					t.eq(p.Anchored, true)
					t.eq(p.CanCollide, false)
					local local_ = root.CFrame:PointToObjectSpace(p.CFrame.Position)
					top = math.max(top, local_.Y + p.Size.Y / 2)
					bottom = math.min(bottom, local_.Y - p.Size.Y / 2)
				end
			end
			-- soles on the figure's ground, about 5.5 studs tall at its scale (more with a cap)
			t.near(bottom, -root.Size.Y / 2, 0.15 * s, "soles on the ground")
			t.truthy(top - bottom > 5.2 * s and top - bottom < 6.4 * s, `height {top - bottom}`)
			-- facing the Root's +Z (the bake's -D): the toes are on that side
			local toe = root.CFrame:PointToObjectSpace(m.LeftFoot.CFrame.Position)
			t.truthy(toe.Z > 0.05, `toes forward {toe.Z}`)
		end
		t.truthy(guard:FindFirstChild("Hat") ~= nil, "the doormen wear their caps")
	end)

	t.test(
		"the avatar blend tints only the art's skin, keeps its face and hides its hair under the player's",
		function()
			local library = PeopleArt.index(fakeAssets())
			local model = stockR15()
			local dress = PeopleLooks.dress("nurse", 1)
			t.eq(dress.outfit, "scrubs")
			PeopleArt.dress(model, dress, { lib = LIB, library = library })
			local jacket = stockR15()
			PeopleArt.dress(jacket, PeopleLooks.dress("townsperson", 2), { lib = LIB, library = library })
			t.eq(jacket:GetAttribute("PeopleOutfit"), "jacket")
			local sleeve = jacket.LeftLowerArm.Color
			local service = AvatarBlendService.new({
				color3 = function(r: number, g: number, b: number): any
					return R.Color3.new(r, g, b)
				end,
				newInstance = function(className: string): any
					return Instance.new(className :: any)
				end,
				faceTexture = function(_id: number): string?
					return "rbxassetid://1"
				end,
				accessory = function(_id: number): any
					local acc = Instance.new("Accessory")
					local handle = Instance.new("Part")
					handle.Name = "Handle"
					handle.Parent = acc
					return acc
				end,
			})
			local tone = { r = 0.25, g = 0.15, b = 0.1 }
			local look = { kind = "human", skinTone = tone, face = 42, hair = 7 }
			local function isTone(p: any): boolean
				return math.abs(p.Color.R - tone.r) < 0.01 and math.abs(p.Color.B - tone.b) < 0.01
			end
			service:apply(model, "human", look)
			t.truthy(isTone(model.Head), "head")
			t.truthy(isTone(model.LeftHand), "hand")
			t.truthy(isTone(model.VNeck), "the V of the scrubs")
			t.eq(model.Head:FindFirstChild("FaceDecal"), nil, "no decal over the painted face")
			t.eq(model.Hair.Transparency, 1, "the art's hair under the player's")
			service:revert(model)
			t.eq(model.Hair.Transparency, 0)
			t.falsy(isTone(model.Head), "reverted")
			service:apply(jacket, "human", look)
			t.eq(jacket.LeftLowerArm.Color, sleeve, "a long sleeve stays a sleeve")
			t.truthy(isTone(jacket.LeftHand), "the jacket's hand")
		end
	)
end
