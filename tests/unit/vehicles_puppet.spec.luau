--!strict
-- Traffic/VehiclePuppet shapes (owner 2026-11-11: "the vehicles are extremely rough"): a shaped kind is a
-- vehicle from at most forty plain parts (wedges for the glass and the bonnet, cylinders and balls for
-- the rounded nose, corners and roof edges), every visible part of every kind stays inside its logical
-- box (what you see is what kills, D9), the RigSpec.car names survive, and each of the ten kinds is
-- recognisably itself. Also PartBuilder's "Wedge" shape.
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local PartBuilder = require("@shared/Avatar/PartBuilder")
local RigSpec = require("@shared/Actors/RigSpec")
local VehiclePuppet = require("@shared/Traffic/VehiclePuppet")
local Boxes = require("@shared/Traffic/Boxes")

-- Every kind is drawn from shaped parts.
local SHAPED = {
	"sedan",
	"patrol_car",
	"ambulance",
	"delivery_van",
	"ice_cream_van",
	"trolley",
	"dump_truck",
	"rv",
	"cart",
	"motorcycle",
}

local lib = {
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
}

-- Half extents of a part's box along the root's axes, turned parts included (centre +- |R| * size / 2).
local function halfExtents(part: any): (number, number, number)
	local cf, s = part.CFrame, part.Size
	local x, y, z = cf.XVector, cf.YVector, cf.ZVector
	return (math.abs(x.X) * s.X + math.abs(y.X) * s.Y + math.abs(z.X) * s.Z) / 2,
		(math.abs(x.Y) * s.X + math.abs(y.Y) * s.Y + math.abs(z.Y) * s.Z) / 2,
		(math.abs(x.Z) * s.X + math.abs(y.Z) * s.Y + math.abs(z.Z) * s.Z) / 2
end

local function byName(spec: PartBuilder.ModelSpec): { [string]: PartBuilder.PartSpec }
	local out = {}
	for _, p in spec.parts do
		out[p.name] = p
	end
	return out
end

local function lum(c: PartBuilder.Rgb): number
	return 0.2126 * c.r + 0.7152 * c.g + 0.0722 * c.b
end

return function(t)
	t.test("PartBuilder: a Wedge is a WedgePart whose slope climbs toward local +Z", function()
		local grey = PartBuilder.hex("#808080")
		local model = PartBuilder.instantiate({
			name = "WedgeCheck",
			species = "car",
			primary = "RootPart",
			parts = {
				{ name = "RootPart", size = { 1, 1, 1 }, pos = { 0, 0, 0 }, color = grey },
				{ name = "Screen", size = { 4, 2, 3 }, pos = { 0, 1, -2 }, color = grey, shape = "Wedge" },
				{ name = "Back", size = { 4, 2, 3 }, pos = { 0, 1, 2 }, yaw = math.pi, color = grey, shape = "Wedge" },
				{ name = "Wheel", size = { 1, 2, 2 }, pos = { 3, 0, 0 }, color = grey, shape = "Cylinder" },
				{ name = "Box", size = { 1, 1, 1 }, pos = { 0, 3, 0 }, color = grey },
			},
			joints = { { name = "ScreenWeld", kind = "Weld", part0 = "RootPart", part1 = "Screen" } },
			attachments = {},
		}, lib)
		local screen, back = model:FindFirstChild("Screen"), model:FindFirstChild("Back")
		t.eq(screen.ClassName, "WedgePart")
		t.eq(back.ClassName, "WedgePart")
		t.eq(model:FindFirstChild("Wheel").ClassName, "Part")
		t.eq(model:FindFirstChild("Wheel").Shape, roblox.Enum.PartType.Cylinder)
		t.eq(model:FindFirstChild("Box").Shape, roblox.Enum.PartType.Block)
		t.near(screen.Size.Z, 3, 1e-6)
		-- a WedgePart is whole on its +Z face and thin at -Z: unturned, the high side is toward the rig's
		-- tail (+Z), as a windscreen's is; yaw = pi puts the high side toward the nose, a rear window
		t.near(screen.CFrame.ZVector.Z, 1, 1e-6)
		t.near(back.CFrame.ZVector.Z, -1, 1e-6)
		t.falsy(screen.Anchored)
		t.falsy(screen.CanCollide)
		t.eq(screen:FindFirstChild("ScreenWeld").ClassName, "Weld")
	end)

	t.test("every visible part of every kind lies inside its RootPart box (within 0.05 st)", function()
		for _, kind in VehiclePuppet.KINDS do
			local model = PartBuilder.instantiate(VehiclePuppet.spec(kind), lib)
			local box = Boxes.get(kind)
			local root = model.PrimaryPart
			t.eq(root.Name, "RootPart")
			t.eq(root.Transparency, 1, `{kind}: the root is not drawn`)
			t.near(root.Size.X, box.width, 1e-4)
			t.near(root.Size.Y, box.height, 1e-4)
			t.near(root.Size.Z, box.length, 1e-4)
			local seen = 0
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d ~= root and d.Transparency < 1 then
					seen += 1
					local p = root.CFrame:PointToObjectSpace(d.CFrame.Position)
					local hx, hy, hz = halfExtents(d)
					t.truthy(math.abs(p.X) + hx <= box.width / 2 + 0.05, `{kind}.{d.Name} x {math.abs(p.X) + hx}`)
					t.truthy(math.abs(p.Y) + hy <= box.height / 2 + 0.05, `{kind}.{d.Name} y {math.abs(p.Y) + hy}`)
					t.truthy(math.abs(p.Z) + hz <= box.length / 2 + 0.05, `{kind}.{d.Name} z {math.abs(p.Z) + hz}`)
				end
			end
			t.truthy(seen >= 8, `{kind}: {seen} visible parts`)
		end
	end)

	t.test("every shaped kind: RigSpec.car names, at most 40 parts, and it fills its box", function()
		for _, kind in SHAPED do
			local spec = VehiclePuppet.spec(kind)
			t.truthy(#spec.parts <= 40, `{kind}: {#spec.parts} parts`)
			t.truthy(#spec.parts >= 20, `{kind}: {#spec.parts} parts is a shaped vehicle, not ten blocks`)
			local model = PartBuilder.instantiate(spec, lib)
			local report = RigSpec.validate(model, "car")
			t.truthy(report.ok, `{kind}: {serde.encode("json", report)}`)
			local names = PartBuilder.names(spec)
			for _, name in RigSpec.car.parts :: { string } do
				t.truthy(names.parts[name], `{kind} has {name}`)
			end
			for _, socket in RigSpec.car.sockets do
				t.truthy(names.attachments[socket], `{kind} has {socket}`)
			end
			for _, wheel in { "WheelFL", "WheelFR", "WheelBL", "WheelBR" } do
				t.truthy(names.joints[wheel], `{kind}: {wheel} turns on a Motor6D of its own name`)
			end
			-- one part, one name; every part but the root hangs on the root by exactly one joint
			local count, jointed = 0, {}
			for _ in names.parts do
				count += 1
			end
			t.eq(count, #spec.parts, `{kind}: part names are unique`)
			for _, j in spec.joints do
				t.eq(j.part0, "RootPart")
				t.eq(jointed[j.part1], nil, `{kind}: {j.part1} is joined once`)
				jointed[j.part1] = true
			end
			for _, p in spec.parts do
				t.truthy(p.name == "RootPart" or jointed[p.name], `{kind}: {p.name} is joined to the root`)
			end
			-- the drawn car reaches every face of the box that kills (0.06 st), the roof to within 0.16
			local box = Boxes.get(kind)
			local hi = { x = -math.huge, y = -math.huge, z = -math.huge }
			local lo = { x = math.huge, y = math.huge, z = math.huge }
			for _, d in model:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 1 then
					local p = d.CFrame.Position
					local hx, hy, hz = halfExtents(d)
					hi.x, hi.y, hi.z = math.max(hi.x, p.X + hx), math.max(hi.y, p.Y + hy), math.max(hi.z, p.Z + hz)
					lo.x, lo.y, lo.z = math.min(lo.x, p.X - hx), math.min(lo.y, p.Y - hy), math.min(lo.z, p.Z - hz)
				end
			end
			t.truthy(hi.x >= box.width / 2 - 0.06 and lo.x <= -box.width / 2 + 0.06, `{kind} is as wide as its box`)
			t.truthy(hi.z >= box.length / 2 - 0.06 and lo.z <= -box.length / 2 + 0.06, `{kind} is as long`)
			t.truthy(lo.y <= -box.height / 2 + 0.06, `{kind} stands on the ground`)
			t.truthy(hi.y >= box.height / 2 - 0.16, `{kind} is as tall ({hi.y})`)
		end
	end)

	t.test(
		"the sedan is car-shaped: raked glass, a narrower cabin, proud wheels in dark arches, lamps in pairs",
		function()
			local paint = "#9a6b55" -- a fleet colour (Traffic/Fleet, "Sedan SB")
			local spec = VehiclePuppet.spec("sedan", { color = paint })
			local p = byName(spec)
			local box = Boxes.get("sedan")
			local want = PartBuilder.hex(paint)
			-- paint comes from the fleet entry; trim, glass and tyres keep their own colours
			for _, name in { "Body", "Nose", "Bonnet", "Deck", "Tail", "Cabin", "Roof", "Mirrors" } do
				t.near(p[name].color.r, want.r, 1e-9, `{name} is painted`)
				t.near(p[name].color.b, want.b, 1e-9, `{name} is painted`)
			end
			local grey = byName(VehiclePuppet.spec("sedan"))
			for _, name in { "Windscreen", "SideGlass", "WheelFL", "BumperF", "Seam1", "ArchF", "Grille", "Plate" } do
				t.eq(p[name].color.r, grey[name].color.r, `{name} keeps its own colour`)
			end
			-- raked glass: the windscreen climbs toward the tail, the rear window toward the nose; both
			-- darker than any fleet paint
			t.eq(p.Windscreen.shape, "Wedge")
			t.eq(p.Windscreen.yaw, nil)
			t.eq(p.RearWindow.shape, "Wedge")
			t.near(p.RearWindow.yaw :: number, math.pi, 1e-9)
			t.eq(p.Bonnet.shape, "Wedge")
			t.truthy(p.Windscreen.pos[3] < p.Cabin.pos[3] and p.Cabin.pos[3] < p.RearWindow.pos[3], "nose to tail")
			t.truthy(lum(p.Windscreen.color) < 0.2 and lum(p.SideGlass.color) < 0.2, "dark glass")
			t.truthy(p.Windscreen.size[3] / p.Windscreen.size[2] > 0.7, "the windscreen is raked, not upright")
			-- three boxes: a bonnet longer than the boot, the cabin narrower than the body, a crown on the roof
			t.truthy(p.Cabin.size[1] < p.Body.size[1] - 0.6, "a shoulder each side of the cabin")
			t.truthy(p.Roof.size[1] < p.Cabin.size[1] and p.Roof.pos[2] > p.Cabin.pos[2], "the roof is crowned")
			local bonnet = p.Bonnet.size[3]
			local boot = box.length / 2 - (p.RearWindow.pos[3] + p.RearWindow.size[3] / 2)
			t.truthy(bonnet > boot * 1.5 and boot > 1, `bonnet {bonnet} st, boot {boot} st`)
			-- rounded ends: two upright corner cylinders per end, a ball where the nose's two rounds meet
			for _, name in { "CornerFL", "CornerFR", "CornerBL", "CornerBR", "NoseEdge" } do
				t.eq(p[name].shape, "Cylinder", name)
			end
			t.eq(p.FenderL.shape, "Ball")
			t.eq(p.FenderR.shape, "Ball")
			-- wheels: round, on the ground, a little proud of the body, each under a dark arch that is wider
			-- than the body and larger than the tyre
			local bodyHalf = p.Body.size[1] / 2
			for _, name in { "WheelFL", "WheelFR", "WheelBL", "WheelBR" } do
				local w = p[name]
				t.eq(w.shape, "Cylinder")
				t.near(w.pos[2] - w.size[2] / 2, -box.height / 2, 1e-6, `{name} stands on the ground`)
				local outer = math.abs(w.pos[1]) + w.size[1] / 2
				t.truthy(outer > bodyHalf + 0.05 and outer < bodyHalf + 0.2, `{name} is {outer - bodyHalf} st proud`)
				local arch = if string.sub(name, 6, 6) == "F" then p.ArchF else p.ArchB
				t.near(arch.pos[3], w.pos[3], 1e-6)
				t.truthy(arch.size[2] > w.size[2] + 0.2, "the arch clears the tyre")
				t.truthy(
					arch.size[1] / 2 > bodyHalf and arch.size[1] / 2 < outer,
					"the arch lies between body and tyre face"
				)
				t.truthy(lum(arch.color) < lum(w.color), "the arch is the darkest thing on the flank")
			end
			t.truthy(p.WheelFL.pos[1] < 0 and p.WheelFR.pos[1] > 0, "L is local -X (the driver's side)")
			t.truthy(p.WheelFL.pos[3] < 0 and p.WheelBL.pos[3] > 0, "F is toward -Z")
			-- lamps: a lit strip at each end whose middle is covered, so a pair shows from one named part
			t.eq(p.Headlights.material, "Neon")
			t.eq(p.TailLights.material, "Neon")
			t.truthy(p.Headlights.pos[3] < 0 and p.TailLights.pos[3] > 0)
			t.truthy(p.Grille.size[1] < p.Headlights.size[1] - 1.5, "a lamp each side of the grille")
			t.truthy(
				p.Grille.pos[3] - p.Grille.size[3] / 2 < p.Headlights.pos[3] - p.Headlights.size[3] / 2,
				"grille in front"
			)
			t.truthy(p.BootPanel.size[1] < p.TailLights.size[1] - 1.5, "a lamp each side of the boot panel")
			t.truthy(p.BootPanel.pos[3] + p.BootPanel.size[3] / 2 > p.TailLights.pos[3] + p.TailLights.size[3] / 2)
			-- bumpers reach the box ends; mirrors reach its sides; door seams are thin and dark
			t.near(p.BumperF.pos[3] - p.BumperF.size[3] / 2, -box.length / 2, 1e-6)
			t.near(p.BumperB.pos[3] + p.BumperB.size[3] / 2, box.length / 2, 1e-6)
			t.near(p.Mirrors.size[1], box.width, 1e-6)
			for _, name in { "Seam1", "Seam2" } do
				t.truthy(p[name].size[3] < 0.1 and lum(p[name].color) < 0.1, `{name} is a thin dark strip`)
				t.truthy(p[name].size[1] > p.Body.size[1], `{name} shows on both flanks`)
			end
		end
	)

	t.test("the patrol car is the sedan's body in white under a red and blue bar on the roof", function()
		local sedan, patrol = VehiclePuppet.spec("sedan"), VehiclePuppet.spec("patrol_car")
		t.eq(#patrol.parts, #sedan.parts + 1, "one more part: the second half of the bar")
		local s, p = byName(sedan), byName(patrol)
		for name, part in s do
			local other = p[name]
			t.truthy(other ~= nil, `patrol car has {name}`)
			for i = 1, 3 do
				t.eq(other.size[i], part.size[i], `{name} size`)
				t.eq(other.pos[i], part.pos[i], `{name} pos`)
			end
		end
		t.truthy(lum(p.Body.color) > 0.75, "white paint")
		t.eq(s.LightBar.transparency, 1, "a plain sedan shows no bar")
		t.eq(s.LightBarB, nil)
		for _, name in { "LightBar", "LightBarB" } do
			t.eq(p[name].material, "Neon")
			t.near(p[name].pos[3], p.Roof.pos[3], 1e-6, `{name} is over the middle of the roof`)
			t.truthy(
				p[name].pos[2] - p[name].size[2] / 2 >= p.Cabin.pos[2] + p.Cabin.size[2] / 2 - 1e-6,
				`{name} is on the roof`
			)
		end
		t.truthy(p.LightBar.pos[1] < 0 and p.LightBarB.pos[1] > 0, "red on the driver's side")
	end)

	t.test(
		"the ambulance: a low white van with a red stripe, a green cross on each flank and a red and white bar",
		function()
			local spec = VehiclePuppet.spec("ambulance")
			local p = byName(spec)
			t.truthy(lum(p.Hull.color) > 0.8, "white")
			for _, name in { "Stripe", "CrossV", "CrossH" } do
				local c = p[name].color
				if name == "Stripe" then
					t.truthy(c.r > 0.7 and c.g < 0.35 and c.b < 0.35, "the stripe is red")
				else
					-- never a red cross on white: that emblem is protected
					t.truthy(c.g > c.r + 0.2 and c.g > c.b, `{name} is green`)
				end
				t.truthy(p[name].size[1] > p.Hull.size[1], `{name} shows on both flanks`)
			end
			t.truthy(
				p.CrossV.size[2] > p.CrossV.size[3] and p.CrossH.size[3] > p.CrossH.size[2],
				"an upright and a bar"
			)
			t.near(p.CrossV.pos[3], p.CrossH.pos[3], 1e-6)
			t.eq(p.Windscreen.shape, "Wedge")
			t.eq(p.Bonnet.shape, "Wedge")
			t.truthy(p.Hull.pos[3] > p.Windscreen.pos[3], "the box body is behind the cab")
			t.eq(p.LightBar.material, "Neon")
			t.eq(p.LightBarB.material, "Neon")
			t.truthy(p.LightBarB.color.r > 0.9 and p.LightBarB.color.g > 0.9, "the second half is white")
			-- a fleet colour repaints the body and leaves the markings
			local tinted = byName(VehiclePuppet.spec("ambulance", { color = "#f4f0ea" }))
			t.near(tinted.Hull.color.r, PartBuilder.hex("#f4f0ea").r, 1e-9)
			t.eq(tinted.Stripe.color.r, p.Stripe.color.r)
		end
	)

	t.test("the delivery van: a tall panel van, a brown band and parcel panel on the load space, rear doors", function()
		local p = byName(VehiclePuppet.spec("delivery_van"))
		local box = Boxes.get("delivery_van")
		t.near(p.Roof.pos[2] + p.Roof.size[2] / 2, box.height / 2, 1e-6, "the roof is the top of the box")
		t.truthy(p.Hull.size[2] > p.Hull.size[1], "taller than wide")
		t.eq(p.Windscreen.shape, "Wedge")
		t.truthy(p.Windscreen.pos[2] + p.Windscreen.size[2] / 2 < p.Hull.pos[2] + p.Hull.size[2] / 2 - 1, "a high roof")
		for _, name in { "RoofEdgeL", "RoofEdgeR" } do
			t.eq(p[name].shape, "Cylinder", `{name} rounds the roof`)
			t.near(p[name].yaw :: number, math.pi / 2, 1e-9, `{name} lies along the van`)
		end
		for _, name in { "Band", "Parcel" } do
			local c = p[name].color
			t.truthy(c.r > c.g * 1.4 and c.g > c.b * 1.5, `{name} is brown`)
			t.truthy(p[name].size[1] > p.Hull.size[1], `{name} shows on both flanks`)
			t.truthy(p[name].pos[3] > p.SideGlass.pos[3], `{name} is behind the cab`)
		end
		t.truthy(p.RearDoors.pos[3] > 0 and p.DoorSplit.size[1] < 0.2 and p.RearGlass.material == "Glass")
		t.near(p.Mirrors.size[1], box.width, 1e-6, "the mirrors reach the box")
		t.eq(p.LightBar.transparency, 1)
	end)

	t.test(
		"the ice cream van: a serving hatch, counter and awning on the kerb side, a wafer and a scoop on the roof",
		function()
			local p = byName(VehiclePuppet.spec("ice_cream_van"))
			local box = Boxes.get("ice_cream_van")
			local function pink(c: PartBuilder.Rgb): boolean
				return c.r > 0.8 and c.r > c.g * 1.3 and c.b > c.g
			end
			-- the hatch is on local +X only (the kerb side: we drive on the right), behind the cab
			for _, name in { "Hatch", "Counter", "Awning" } do
				t.truthy(p[name].pos[1] > 0 and p[name].pos[1] - p[name].size[1] / 2 > 0, `{name} is on the kerb side`)
				t.truthy(p[name].pos[3] > p.SideGlass.pos[3], `{name} is behind the cab`)
			end
			t.truthy(lum(p.Hatch.color) < 0.25, "the hatch is a dark opening")
			t.truthy(
				p.Counter.pos[2] < p.Hatch.pos[2] and p.Awning.pos[2] > p.Hatch.pos[2],
				"counter below, awning above"
			)
			t.near(p.Counter.pos[1] + p.Counter.size[1] / 2, box.width / 2, 1e-6, "the counter reaches the box")
			-- the awning is a wedge turned to fall away from the van
			t.eq(p.Awning.shape, "Wedge")
			t.near(p.Awning.yaw :: number, -math.pi / 2, 1e-9)
			t.truthy(pink(p.Awning.color) and pink(p.Skirt.color) and pink(p.Scoop.color), "pink trim")
			-- the cone: a wafer cylinder standing on the roof with a ball on it, up to the top of the box
			t.eq(p.Cone.shape, "Cylinder")
			t.near(p.Cone.roll :: number, math.pi / 2, 1e-9, "the wafer stands upright")
			t.eq(p.Scoop.shape, "Ball")
			t.near(
				p.Cone.pos[2] - p.Cone.size[1] / 2,
				p.Roof.pos[2] + p.Roof.size[2] / 2,
				1e-6,
				"the wafer stands on the roof"
			)
			t.truthy(
				p.Scoop.pos[2] > p.Cone.pos[2] and p.Scoop.size[1] > p.Cone.size[2],
				"the scoop sits on and overhangs it"
			)
			t.truthy(
				p.Scoop.pos[2] + p.Scoop.size[2] / 2 > box.height / 2 - 0.1,
				"the scoop reaches the top of the box"
			)
			t.truthy(p.Scoop.pos[3] < p.Hatch.pos[3], "over the cab")
			-- the skirt lies between the wheel arches, not across them
			t.truthy(p.Skirt.pos[3] - p.Skirt.size[3] / 2 > p.ArchF.pos[3] + p.ArchF.size[2] / 2)
			t.truthy(p.Skirt.pos[3] + p.Skirt.size[3] / 2 < p.ArchB.pos[3] - p.ArchB.size[2] / 2)
		end
	)

	t.test("the trolley: a streetcar with rounded ends, a cream window band, a monitor roof and its pole", function()
		local p = byName(VehiclePuppet.spec("trolley"))
		local box = Boxes.get("trolley")
		-- painted below, cream above, one strip of glass through the car with four pillars across it
		t.truthy(p.Body.color.r > p.Body.color.g * 2, "the lower body is the trolley red")
		t.truthy(lum(p.Cabin.color) > 0.7, "the window band is cream")
		t.truthy(p.Cabin.pos[2] > p.Body.pos[2])
		t.eq(p.SideGlass.material, "Glass")
		t.truthy(p.SideGlass.size[3] > box.length * 0.75 and p.SideGlass.size[1] > p.Cabin.size[1])
		for i = 1, 4 do
			local pillar = p[`Pillar{i}`]
			t.truthy(pillar.size[1] > p.SideGlass.size[1], `Pillar{i} stands proud of the glass`)
			t.truthy(math.abs(pillar.pos[3]) < p.SideGlass.size[3] / 2, `Pillar{i} crosses the glass`)
		end
		-- rounded ends: an upright cylinder at each corner, a stud or more in radius
		for _, name in { "CornerFL", "CornerFR", "CornerBL", "CornerBR" } do
			t.eq(p[name].shape, "Cylinder")
			t.near(p[name].roll :: number, math.pi / 2, 1e-9)
			t.truthy(p[name].size[2] >= 2, `{name} is a generous round`)
		end
		t.truthy(p.Windscreen.pos[3] < 0 and p.RearWindow.pos[3] > 0, "glass at both ends")
		-- one round headlamp, a lit destination board over the windscreen, a door on the kerb side
		t.eq(p.Headlights.shape, "Cylinder")
		t.eq(p.Headlights.material, "Neon")
		t.eq(p.Board.material, "Neon")
		t.truthy(p.Board.pos[2] > p.Windscreen.pos[2] and p.Board.pos[3] < 0)
		t.truthy(p.Door.pos[1] - p.Door.size[1] / 2 > 0 and p.Door.pos[3] < 0, "the door is at the front on local +X")
		-- the roof: a lid with rounded edges, the monitor on it, the pole trailing up to the top of the box
		t.truthy(p.Monitor.pos[2] > p.Roof.pos[2] and p.Monitor.size[1] < p.Roof.size[1])
		t.truthy((p.Pole.pitch :: number) < 0, "the pole rises toward the tail")
		t.truthy(p.Pole.size[3] > 4 and p.Pole.size[1] < 0.2, "a thin pole")
		local rise = p.Pole.size[3] / 2 * math.sin(-(p.Pole.pitch :: number)) + p.Pole.size[2] / 2
		t.truthy(p.Pole.pos[2] + rise <= box.height / 2 and p.Pole.pos[2] + rise > box.height / 2 - 0.1)
	end)

	t.test(
		"the dump truck: a bonneted cab, an open tipper with a shield over the cab, two rear axles, a stack",
		function()
			local p = byName(VehiclePuppet.spec("dump_truck"))
			local box = Boxes.get("dump_truck")
			t.eq(p.Bonnet.shape, "Wedge")
			t.eq(p.Windscreen.shape, "Wedge")
			t.truthy(p.Cabin.pos[3] < 0 and p.Bed.pos[3] > 0, "cab in front, tipper behind")
			-- the tipper: floor, two sides, headboard and tailgate around a load; the shield is the top of
			-- the box and reaches forward over the cab roof
			t.truthy(p.BedL.pos[1] < 0 and p.BedR.pos[1] > 0 and p.BedL.size[1] < 0.6, "thin side walls")
			t.truthy(p.Headboard.pos[3] < p.Load.pos[3] and p.Tailgate.pos[3] > p.Load.pos[3])
			t.truthy(p.Load.size[1] < p.Bed.size[1] - 0.5, "the load lies between the sides")
			t.truthy(p.Load.pos[2] + p.Load.size[2] / 2 > p.BedL.pos[2] + p.BedL.size[2] / 2, "heaped over the rim")
			t.near(p.Shield.pos[2] + p.Shield.size[2] / 2, box.height / 2, 1e-6)
			t.truthy(p.Shield.pos[3] - p.Shield.size[3] / 2 < p.Cabin.pos[3] + p.Cabin.size[3] / 2 - 1, "over the cab")
			t.truthy(p.Shield.pos[2] - p.Shield.size[2] / 2 > p.Cabin.pos[2] + p.Cabin.size[2] / 2, "clear of its roof")
			for _, name in { "Rib1", "Rib2" } do
				t.truthy(p[name].size[1] > p.Bed.size[1], `{name} shows on both flanks`)
			end
			-- big wheels; an arch on the cab only; the second rear axle is one roller with its own hubs
			t.truthy(p.WheelFL.size[2] >= 3, "big wheels")
			t.truthy(p.ArchF ~= nil and p.ArchB == nil, "the rear wheels stand bare under the tipper")
			t.eq(p.Tandem.shape, "Cylinder")
			t.near(p.Tandem.size[2], p.WheelBL.size[2], 1e-9)
			t.truthy(p.Tandem.pos[3] > p.WheelBL.pos[3] + p.WheelBL.size[2] / 2, "behind the first rear axle")
			t.truthy(p.HubsT.size[1] > p.Tandem.size[1], "its hub caps show")
			t.eq(p.Stack.shape, "Cylinder")
			t.truthy(p.Stack.pos[1] < 0 and p.Stack.size[1] > 4, "a tall exhaust on the driver's side")
			t.truthy(
				p.TailLights.pos[3] + p.TailLights.size[3] / 2 > box.length / 2 - 1e-6,
				"the lamp strip is the tail"
			)
		end
	)

	t.test(
		"the RV: a long motorhome with saloon windows, a stripe, a kerb-side door and awning, an air conditioner",
		function()
			local p = byName(VehiclePuppet.spec("rv"))
			local box = Boxes.get("rv")
			t.truthy(p.Hull.size[3] > box.length * 0.75, "one long hull behind the cab")
			for _, name in { "WindowA", "WindowB" } do
				t.eq(p[name].material, "Glass")
				t.truthy(p[name].size[1] > p.Hull.size[1], `{name} shows on both flanks`)
				t.truthy(p[name].pos[3] > p.SideGlass.pos[3], `{name} is behind the cab`)
			end
			t.truthy(p.WindowB.pos[3] - p.WindowB.size[3] / 2 > p.WindowA.pos[3] + p.WindowA.size[3] / 2, "two windows")
			-- the door stands between the windows on the kerb side only
			t.truthy(p.Door.pos[1] - p.Door.size[1] / 2 > 0, "the door is on local +X")
			t.truthy(p.Door.pos[3] > p.WindowA.pos[3] and p.Door.pos[3] < p.WindowB.pos[3])
			t.truthy(p.Door.size[2] > 6, "a door a person walks through")
			t.truthy(
				p.Stripe.size[3] > box.length * 0.7 and p.Stripe.size[1] > p.Hull.size[1],
				"a stripe down both flanks"
			)
			-- the air conditioner is the top of the box; the awning is a roll along the kerb-side roof edge
			t.near(p.AirCon.pos[2] + p.AirCon.size[2] / 2, box.height / 2, 1e-6)
			t.near(p.AirCon.pos[2] - p.AirCon.size[2] / 2, p.Roof.pos[2] + p.Roof.size[2] / 2, 1e-6, "on the roof")
			t.eq(p.Awning.shape, "Cylinder")
			t.near(p.Awning.yaw :: number, math.pi / 2, 1e-9)
			t.truthy(p.Awning.pos[1] > 0 and p.Awning.pos[1] + p.Awning.size[2] / 2 <= box.width / 2 + 1e-6)
			t.eq(p.RearPanel.color.r, p.Hull.color.r, "a plain back")
		end
	)

	t.test("the golf cart: an open tub, a bench, two bags on the deck, a canopy on four posts", function()
		local p = byName(VehiclePuppet.spec("cart"))
		local box = Boxes.get("cart")
		t.near(p.Canopy.pos[2] + p.Canopy.size[2] / 2, box.height / 2, 1e-6, "the canopy is the top of the box")
		for _, name in { "PostFL", "PostFR", "PostBL", "PostBR" } do
			local post = p[name]
			t.truthy(post.size[1] < 0.2 and post.size[3] < 0.2 and post.size[2] > 2, `{name} is a thin post`)
			t.near(
				post.pos[2] + post.size[2] / 2,
				p.Canopy.pos[2] - p.Canopy.size[2] / 2,
				1e-6,
				`{name} carries the canopy`
			)
		end
		t.truthy(p.PostFL.pos[1] < 0 and p.PostFR.pos[1] > 0 and p.PostFL.pos[3] < p.PostBL.pos[3])
		-- open: nothing but posts and a clear windshield between the tub and the canopy
		t.truthy((p.Windshield.transparency :: number) >= 0.4, "the windshield is clear")
		t.eq(p.Cowl.shape, "Wedge")
		t.truthy(p.Seat.pos[2] < p.SeatBack.pos[2] and p.SeatBack.pos[3] > p.Seat.pos[3], "a bench with a back")
		t.truthy(p.Seat.pos[2] + p.Seat.size[2] / 2 < p.Canopy.pos[2] - 2, "headroom over the bench")
		for _, name in { "Bag1", "Bag2" } do
			t.eq(p[name].shape, "Cylinder")
			t.near(p[name].roll :: number, math.pi / 2, 1e-9, `{name} stands upright`)
			t.truthy(p[name].pos[3] > p.SeatBack.pos[3], `{name} is behind the seat`)
		end
		t.truthy(p.Bag1.color.g > p.Bag1.color.r and p.Bag2.color.r > p.Bag2.color.g, "a green bag and a red one")
		t.truthy(p.Steering.pos[1] < 0, "the wheel is on the driver's side")
		t.truthy(p.WheelFL.size[2] < 1.5, "small wheels")
	end)

	t.test(
		"the motorcycle: two wheels in line under four wheel names, raked forks, a tank, bars and a screen",
		function()
			local paint = "#7a2f2a"
			local p = byName(VehiclePuppet.spec("motorcycle", { color = paint }))
			local box = Boxes.get("motorcycle")
			-- each wheel is two half-width tyres side by side on the centre line
			for _, pair in { { "WheelFL", "WheelFR" }, { "WheelBL", "WheelBR" } } do
				local l, r = p[pair[1]], p[pair[2]]
				t.near(l.pos[3], r.pos[3], 1e-9)
				t.near(l.pos[1] + l.size[1] / 2, 0, 1e-9, `{pair[1]} ends on the centre line`)
				t.near(r.pos[1] - r.size[1] / 2, 0, 1e-9, `{pair[2]} starts on it`)
				t.truthy(l.size[1] + r.size[1] < 0.6, "one narrow tyre")
			end
			t.truthy(p.WheelFL.pos[3] < 0 and p.WheelBL.pos[3] > 0)
			t.eq(VehiclePuppet.track("motorcycle"), nil, "a two-wheeler has no track")
			-- the tank takes the paint; the engine and the trim do not
			local want = PartBuilder.hex(paint)
			t.near(p.Tank.color.r, want.r, 1e-9)
			t.eq(p.Tank.shape, "Cylinder")
			t.truthy(p.Body.color.r ~= want.r, "the engine keeps its metal")
			t.truthy(
				p.Tank.pos[2] > p.Body.pos[2] and p.Seat.pos[3] > p.Tank.pos[3],
				"tank over the engine, seat behind"
			)
			-- forks raked back from the front axle to the bars; bars as wide as the box; a clear screen to its top
			for _, name in { "ForkL", "ForkR" } do
				t.truthy((p[name].pitch :: number) > 0.2, `{name} is raked`)
				t.truthy(p[name].pos[3] < 0 and p[name].size[2] > 1.5)
			end
			t.near(p.Bars.size[1], box.width, 1e-6)
			t.truthy(p.Bars.pos[2] > p.Tank.pos[2])
			t.truthy((p.Screen.transparency :: number) >= 0.4)
			t.near(p.Screen.pos[2] + p.Screen.size[2] / 2, box.height / 2, 1e-6)
			t.eq(p.Headlights.material, "Neon")
			t.truthy(p.Headlights.pos[3] < p.Tank.pos[3] and p.TailLights.pos[3] > p.Seat.pos[3])
			local sockets = VehiclePuppet.spec("motorcycle").attachments
			t.eq(sockets[1].pos[1], 0, "the rider sits on the centre line")
		end
	)

	t.test("all ten kinds are shaped: none is the ten-block placeholder", function()
		t.eq(#VehiclePuppet.KINDS, 10)
		t.eq(#SHAPED, 10)
		local shaped = {}
		for _, kind in SHAPED do
			shaped[kind] = true
		end
		for _, kind in VehiclePuppet.KINDS do
			t.truthy(shaped[kind], `{kind} is in the shaped list`)
			local spec = VehiclePuppet.spec(kind)
			local rounded = 0
			for _, part in spec.parts do
				if part.shape == "Ball" or (part.shape == "Cylinder" and string.sub(part.name, 1, 5) ~= "Wheel") then
					rounded += 1
				end
			end
			t.truthy(rounded >= 4, `{kind}: {rounded} rounded parts besides its wheels`)
			-- the block placeholder's see-through cabin is gone: glass is dark and solid, or a clear screen
			local cabin = byName(spec).Cabin
			t.truthy(cabin == nil or (cabin.transparency or 0) == 0, `{kind}: no see-through block cabin`)
		end
	end)
end
