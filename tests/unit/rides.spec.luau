--!strict
-- The bikes, novelty rides and their riders (owner playtest 2026-11-19: "i saw bikes and things that were basic colors,
-- like earlier builds"): Shared/Vehicles/RidePuppet's eight street riders are the v5.4 cast on their rides (the mime on
-- his unicycle, five kids on bicycles in helmets, two motorcyclists on scooters), drawn round like the townspeople from
-- PeopleLooks' colours and in the cast's own shirts, within a mobile part budget, collision-free but for the old
-- 1 x 1 x 1 root at the old height; in town (Server/AI/TownAI) the mime and the kids take the lanes, each in its own
-- slot, and Morgan and Alex ride the traffic's two motorcycles (Traffic/Ghost), one of each person at once; a street
-- rider is AI-only, never handed to a player (Actors/ActorsRuntime.pickFree; decision 21); the player's vehicles
-- (Vehicles/Placeholder.look) are shaped in the traffic's style INSIDE their VehicleKinds boxes (the box stays the
-- collider); and the yard props the town bakes (worldgen Builders/Props) are drawn, not boxes.
-- (As built on engine stand-ins: tests/unit/vehicles_built.spec.luau, tests/unit/riders_built.spec.luau.)
local roblox = require("@lune/roblox")
local fs = require("@lune/fs")
local serde = require("@lune/serde")
local PartBuilder = require("@shared/Avatar/PartBuilder")
local RidePuppet = require("@shared/Vehicles/RidePuppet")
local Placeholder = require("@shared/Vehicles/Placeholder")
local VehicleKinds = require("@shared/Vehicles/VehicleKinds")
local VehiclePuppet = require("@shared/Traffic/VehiclePuppet")
local Ghost = require("@shared/Traffic/Ghost")
local Fleet = require("@shared/Traffic/Fleet")
local RolePalettes = require("@shared/Avatar/RolePalettes")
local Data = require("@shared/Data")
local Bake = require("@worldgen/Bake")
local TownAI = require("@server/AI/TownAI")
local ActorsRuntime = require("@server/Actors/ActorsRuntime")

local lib = {
	Instance = roblox.Instance,
	Vector3 = roblox.Vector3,
	CFrame = roblox.CFrame,
	Color3 = roblox.Color3,
	Enum = roblox.Enum,
}

local function halfExtents(part: any): (number, number, number)
	local cf, s = part.CFrame, part.Size
	local x, y, z = cf.XVector, cf.YVector, cf.ZVector
	return (math.abs(x.X) * s.X + math.abs(y.X) * s.Y + math.abs(z.X) * s.Z) / 2,
		(math.abs(x.Y) * s.X + math.abs(y.Y) * s.Y + math.abs(z.Y) * s.Z) / 2,
		(math.abs(x.Z) * s.X + math.abs(y.Z) * s.Y + math.abs(z.Z) * s.Z) / 2
end

-- the visible parts' extent in the root's frame
local function extent(model: any): (any, any)
	local lo = { x = math.huge, y = math.huge, z = math.huge }
	local hi = { x = -math.huge, y = -math.huge, z = -math.huge }
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d.Transparency < 1 then
			local p = model.PrimaryPart.CFrame:PointToObjectSpace(d.CFrame.Position)
			local hx, hy, hz = halfExtents(d)
			lo.x, lo.y, lo.z = math.min(lo.x, p.X - hx), math.min(lo.y, p.Y - hy), math.min(lo.z, p.Z - hz)
			hi.x, hi.y, hi.z = math.max(hi.x, p.X + hx), math.max(hi.y, p.Y + hy), math.max(hi.z, p.Z + hz)
		end
	end
	return lo, hi
end

local function byName(spec: PartBuilder.ModelSpec): { [string]: PartBuilder.PartSpec }
	local out = {}
	for _, p in spec.parts do
		out[p.name] = p
	end
	return out
end

local function same(a: PartBuilder.Rgb, b: PartBuilder.Rgb): boolean
	return math.abs(a.r - b.r) < 1e-6 and math.abs(a.g - b.g) < 1e-6 and math.abs(a.b - b.b) < 1e-6
end

-- every part but the root joined to it exactly once, names unique
local function joinedOnce(t: any, spec: PartBuilder.ModelSpec, label: string)
	local names, jointed = {}, {}
	for _, p in spec.parts do
		t.eq(names[p.name], nil, `{label}: one part called {p.name}`)
		names[p.name] = true
	end
	for _, j in spec.joints do
		t.eq(j.part0, spec.primary, `{label}: {j.name} hangs on the root`)
		t.eq(jointed[j.part1], nil, `{label}: {j.part1} is joined once`)
		jointed[j.part1] = true
	end
	for _, p in spec.parts do
		t.truthy(p.name == spec.primary or jointed[p.name], `{label}: {p.name} is joined to the root`)
	end
end

return function(t)
	t.test("the eight street riders are the cast on their rides, in town order", function()
		local rides = {}
		for slot = 1, 8 do
			local spec = RidePuppet.rider(slot)
			rides[slot] = spec.attributes and spec.attributes.RideKind
		end
		t.eq(
			serde.encode("json", rides),
			serde.encode("json", {
				"unicycle",
				"bicycle",
				"bicycle",
				"bicycle",
				"bicycle",
				"bicycle",
				"scooter",
				"scooter",
			})
		)
		-- each rider's colours are its cast member's (data/authored/cast/cast.json)
		local cast = serde.decode("json", fs.readFile("data/authored/cast/cast.json"))
		local list = if cast[1] then cast else (cast.cast or cast.members)
		local byId = {}
		for _, m in list do
			byId[m.id] = serde.encode("json", m)
		end
		for _, r in RidePuppet.RIDERS do
			local row = byId[r.src]
			t.truthy(row, `{r.name}: cast member {r.src}`)
			for _, c in { r.skin, r.shirt, r.frame, r.helmet } do
				if
					c
					and not (r.ride == "unicycle" and c == r.frame)
					and not (r.ride == "scooter" and c == r.helmet)
				then
					t.truthy(string.find(row, c, 1, true), `{r.name}: {c} is the cast's`)
				end
			end
		end
	end)

	t.test(
		"a rider: the old root at the old height, joined parts, nothing else to hit, a mobile part budget",
		function()
			for slot = 1, 9 do
				local spec = RidePuppet.rider(slot)
				local model = PartBuilder.instantiate(spec, lib)
				local root = model.PrimaryPart
				t.eq(root.Name, "HumanoidRootPart")
				t.eq(root.Transparency, 1)
				t.near(root.Size.X, 1, 1e-9)
				t.near(root.Size.Y, 1, 1e-9)
				t.truthy(root.CanQuery and root.Anchored)
				joinedOnce(t, spec, `rider {slot}`)
				t.truthy(#spec.parts <= 44, `rider {slot}: {#spec.parts} parts`)
				t.truthy(#spec.parts >= 30, `rider {slot}: {#spec.parts} parts is a shaped rider, not six blocks`)
				local shadows = 0
				for _, d in model:GetDescendants() do
					if d:IsA("BasePart") and d ~= root then
						t.falsy(d.CanCollide or d.CanQuery or d.CanTouch, `rider {slot}: {d.Name} touches nothing`)
						t.falsy(d.Anchored, `rider {slot}: {d.Name} hangs on the root`)
						shadows += if d.CastShadow then 1 else 0
					end
				end
				t.truthy(shadows >= 3 and shadows <= 6, `rider {slot}: {shadows} parts cast shadows`)
				-- the tyres stand on the ground ROOT_HEIGHT under the root; a person's height on top
				local lo, hi = extent(model)
				t.near(lo.y, -RidePuppet.ROOT_HEIGHT, 0.02, `rider {slot} stands on the ground`)
				t.truthy(hi.y - lo.y > 4.2 and hi.y - lo.y < 7.4, `rider {slot} is {hi.y - lo.y} studs tall`)
				t.truthy(hi.x - lo.x < 2.2, `rider {slot} is {hi.x - lo.x} wide`)
				local names = PartBuilder.names(spec)
				t.truthy(names.joints.WheelF, `rider {slot}: the front tyre turns on WheelF`)
			end
		end
	)

	t.test(
		"riders are dressed as the townspeople: a head with eyes, hair, round hands, the role's hat or a helmet",
		function()
			for slot = 1, 8 do
				local p = byName(RidePuppet.rider(slot))
				for _, name in { "Head", "EyeL", "EyeR", "HandL", "HandR", "Hair", "Torso", "ShoeL", "ShoeR" } do
					t.truthy(p[name], `rider {slot} has {name}`)
				end
				t.eq(p.Head.shape, "Ball")
				t.eq(p.HandL.shape, "Ball")
				-- the eyes sit on the face, in front of the hair
				t.truthy(p.EyeL.pos[3] < p.Hair.pos[3] - 0.4, `rider {slot}: the eyes are in front`)
				local r = RidePuppet.RIDERS[slot]
				if r.role == "mime" then
					t.truthy(p.Beret and p.Stripe1 and p.Scarf and p.Ball4, "the mime: beret, stripes, scarf, juggling")
					t.truthy(p.HandL.color.r > 0.9 and p.HandL.color.b > 0.9, "the mime's white gloves")
				else
					t.truthy(p.Helmet and p.Visor, `rider {slot} wears a helmet`)
					t.truthy(
						same(p.Helmet.color, PartBuilder.hex(r.helmet :: string)),
						`rider {slot}: the cast's helmet`
					)
					t.truthy(same(p.HandL.color, p.Head.color), `rider {slot}: bare hands`)
				end
			end
			-- the kids are small, on small bikes
			local kid, adult = byName(RidePuppet.rider(2)), byName(RidePuppet.rider(7))
			t.truthy(kid.Head.size[1] < adult.Head.size[1] * 0.8, "a kid's head is smaller")
			t.truthy(
				byName(RidePuppet.rider(2)).Basket ~= nil and byName(RidePuppet.rider(3)).Basket == nil,
				"some baskets"
			)
		end
	)

	t.test("the bicycle: spoked wheels, a frame in the paint, a saddle, bars; anchors where the rider sits", function()
		local k = RidePuppet.newKit(0)
		local a = RidePuppet.drawBicycle(k, { scale = 1, frame = "#405979" })
		local p: { [string]: any } = {}
		for _, part in k.parts do
			p[part.name] = part
		end
		for _, name in
			{
				"WheelF",
				"WheelB",
				"WheelFSpokes1",
				"WheelBHub",
				"SeatTube",
				"TopTube",
				"DownTube",
				"Fork",
				"Bars",
				"Saddle",
			}
		do
			t.truthy(p[name], `the bicycle has {name}`)
		end
		t.near(p.WheelF.pos[2] - p.WheelF.size[2] / 2, 0, 1e-9, "the tyres touch the ground")
		t.truthy(p.WheelF.pos[3] < p.WheelB.pos[3], "the front wheel faces -Z")
		t.truthy(same(p.TopTube.color, PartBuilder.hex("#405979")), "the frame is the paint")
		t.truthy(#k.parts == 21, `{#k.parts} parts`)
		t.truthy(a.seat[2] > 2 and #a.hands == 2 and #a.feet == 2, "the rider's anchors")
		t.truthy(a.feet[1][2] ~= a.feet[2][2], "the pedals stand at different heights")
	end)

	t.test("the player's vehicles are shaped inside their VehicleKinds boxes, which stay the colliders", function()
		for _, id in VehicleKinds.list() do
			local kind = VehicleKinds.kind(id)
			local spec = Placeholder.look(id)
			t.truthy(spec, `{kind.id} is drawn`)
			local s = spec :: PartBuilder.ModelSpec
			t.truthy(#s.parts <= 42, `{kind.id}: {#s.parts} parts`)
			t.truthy(#s.parts >= 12, `{kind.id}: {#s.parts} parts is shaped`)
			joinedOnce(t, s, kind.id)
			local model = PartBuilder.instantiate(s, lib)
			local root = model.PrimaryPart
			t.near(root.Size.X, kind.size[1], 1e-4, `{kind.id}: the box is the VehicleKinds box`)
			t.near(root.Size.Y, kind.size[2], 1e-4)
			t.near(root.Size.Z, kind.size[3], 1e-4)
			local lo, hi = extent(model)
			local w, h, l = kind.size[1] / 2 + 0.05, kind.size[2] / 2 + 0.05, kind.size[3] / 2 + 0.05
			t.truthy(lo.x >= -w and hi.x <= w, `{kind.id}: inside its box across ({lo.x}, {hi.x})`)
			t.truthy(lo.y >= -h and hi.y <= h, `{kind.id}: inside its box up ({lo.y}, {hi.y})`)
			t.truthy(lo.z >= -l and hi.z <= l, `{kind.id}: inside its box along ({lo.z}, {hi.z})`)
			t.near(lo.y, -kind.size[2] / 2, 0.06, `{kind.id} stands on the floor of its box`)
			t.truthy(hi.z - lo.z > kind.size[3] * 0.85, `{kind.id} fills its box's length`)
		end
		-- the patrol car keeps its white and the bar; the others wear their VehicleKinds colour
		local car = byName(Placeholder.look("car") :: any)
		t.truthy(car.LightBar and car.LightBarB and car.LightBarB.material == "Neon", "the patrol car's bar")
		local bike = byName(Placeholder.look("bike") :: any)
		local c = VehicleKinds.kind("bike").color
		t.near(bike.TopTube.color.r, c[1], 0.003, "the bike's frame is its colour")
		-- the player-only kinds need a box (no traffic kind is drawn by accident)
		t.falsy(pcall(VehiclePuppet.spec, "pickup"), "a pickup has no traffic box")
		t.truthy(table.find(VehiclePuppet.KINDS, "pickup") == nil, "and is not a traffic kind")
	end)

	t.test(
		"the town's yard props are drawn over their old boxes, which stay unseen and never block anyone; the shed roofed",
		function()
			local plans = Bake.plans(Bake.data())
			local seen: { [string]: number } = {}
			for _, p in plans do
				local kind = string.match(p.id or "", "^detail_%d+_(.+)$")
					or (if p.id == "core_mower" then "mower" elseif p.id == "north_park_shed" then "shed" else nil)
				local wants = ({
					kids_bike = "BikeWheelF",
					wheelbarrow = "Tray",
					garden_hose_reel = "Hose",
					mower = "Bonnet",
					shed = "Door",
				})[kind or ""]
				if wants then
					seen[kind :: string] = (seen[kind :: string] or 0) + 1
					local names, drawn = {}, 0
					for _, part in p.parts do
						names[part.name] = part
						if part.name ~= "Greybox" and part.name ~= "Foundation" then
							drawn += 1
							t.falsy(part.canCollide, `{p.id}.{part.name} blocks nobody`)
						end
					end
					t.truthy(names[wants], `{p.id} has its {wants}`)
					local body = names.Greybox
					if kind == "shed" then
						t.truthy(
							body.canCollide and (body.transparency or 0) == 0,
							"the shed's walls are still the solid box"
						)
						t.truthy(names.Slates, "under a roof of slates")
						-- an overhang takes no queries: rays (and a body's ground probe) land on the walls' top
						t.eq(names.Slates.canQuery, false, "the slates take no queries")
						t.falsy(names.Slates.canCollide, "nor collide")
					else
						t.eq(body.transparency, 1, `{p.id}: the old box is unseen`)
						t.falsy(body.canCollide or body.canQuery, `{p.id}: the old box blocks nothing`)
						t.truthy(drawn >= 6 and drawn <= 22, `{p.id}: {drawn} drawn parts`)
					end
				end
			end
			t.eq(seen.kids_bike, 3)
			t.eq(seen.wheelbarrow, 2)
			t.eq(seen.garden_hose_reel, 2)
			t.eq(seen.mower, 1)
			t.eq(seen.shed, 1)
		end
	)

	t.test(
		"the traffic's motorcycles carry Morgan and Alex; without a rider the motorcycle is drawn as before",
		function()
			local bare = VehiclePuppet.spec("motorcycle")
			for _, slot in { 7, 8 } do
				local spec = VehiclePuppet.spec("motorcycle", { rider = slot })
				local p = byName(spec)
				t.truthy(p.RiderHead and p.RiderHelmet and p.RiderHandL and p.RiderShoeR, `slot {slot}: a rider`)
				t.truthy(same(p.RiderHelmet.color, PartBuilder.hex(RidePuppet.RIDERS[slot].helmet :: string)))
				t.truthy(#spec.parts - #bare.parts <= 22, `{#spec.parts - #bare.parts} rider parts`)
				joinedOnce(t, spec, `motorcycle {slot}`)
				-- the motorcycle itself is untouched: every part of the bare one, where it was
				for _, q in bare.parts do
					t.eq(serde.encode("json", p[q.name]), serde.encode("json", q), `{q.name} unchanged`)
				end
				-- the rider sits on the seat, hands at the bar
				t.near(p.RiderHandL.pos[2], p.Bars.pos[2], 0.01, "hands on the bar")
				t.truthy(p.RiderPelvis.pos[2] > p.Seat.pos[2], "on the seat")
			end
		end
	)
	t.test("the riders wear the cast's shirts; a shirt that reads as skin is darker at the shoulders", function()
		for slot, r in RidePuppet.RIDERS do
			local p = byName(RidePuppet.rider(slot))
			local shirt = PartBuilder.hex(r.shirt)
			t.truthy(same(p.Torso.color, shirt), `{r.name}: the cast's shirt {r.shirt}`)
			t.truthy(same(p.ArmL.color, shirt), `{r.name}: in its sleeves`)
			local skinLike = r.role ~= "mime" and RolePalettes.readsAsSkin(shirt, PartBuilder.hex(r.skin))
			if skinLike then
				t.truthy(p.Shoulders.color.r < shirt.r * 0.8, `{r.name}: the shoulders darker under the chin`)
			else
				t.truthy(same(p.Shoulders.color, shirt), `{r.name}: the shoulders in the shirt`)
			end
		end
		-- Ellie's orange, Riley's khaki and Morgan's brown-grey jacket are the ones that read as skin (the owner sheet
		-- says so)
		local skinLike = {}
		for _, r in RidePuppet.RIDERS do
			if r.role ~= "mime" and RolePalettes.readsAsSkin(PartBuilder.hex(r.shirt), PartBuilder.hex(r.skin)) then
				table.insert(skinLike, r.name)
			end
		end
		t.eq(table.concat(skinLike, ", "), "Ellie, Riley, Morgan Rider")
	end)

	t.test(
		"in town the mime and the five kids ride the lanes, each in its own slot; Morgan and Alex ride the motorcycles",
		function()
			local world = TownAI.build({ data = Data.default(), seed = 5 })
			local slots = {}
			for _, a in world.actors do
				if a.post == "rider" then
					t.truthy(a.ride ~= nil, `rider {a.id} has a slot`)
					t.eq(slots[a.ride], nil, `slot {a.ride} rides once`)
					slots[a.ride] = true
				end
			end
			for slot = 1, 6 do
				t.truthy(slots[slot], `{RidePuppet.RIDERS[slot].name} rides in town`)
			end
			t.falsy(slots[7] or slots[8], "Morgan and Alex are not on the lanes too")
			-- the traffic's motorcycles: each carries its own named rider, once
			local onBikes = {}
			for _, e in Fleet.ENTRIES do
				if e.kind == "motorcycle" then
					local slot = Ghost.riderSlot(e.id, e.kind) :: number
					t.eq(RidePuppet.RIDERS[slot].name, e.name, `fleet {e.id} carries {e.name}`)
					t.eq(onBikes[slot], nil, `{e.name} rides one motorcycle`)
					onBikes[slot] = true
					local p = byName(Ghost.spec(e.id, { kind = e.kind }))
					t.truthy(p.RiderHead and p.RiderHelmet, `fleet {e.id}: the model render builds has its rider`)
					t.truthy(same(p.RiderHelmet.color, PartBuilder.hex(RidePuppet.RIDERS[slot].helmet :: string)))
				end
			end
			t.truthy(onBikes[7] and onBikes[8], "Morgan and Alex are on the motorcycles")
			t.eq(Ghost.riderSlot(1, "sedan"), nil, "a car has no rider drawn")
			t.eq(#Ghost.spec(1, { kind = "sedan" }).parts, #VehiclePuppet.spec("sedan").parts, "and is drawn as before")
		end
	)

	t.test("a street rider is never handed to a player (AI-only, decision 21), however near the player is", function()
		local world = TownAI.build({ data = Data.default(), seed = 5 })
		local all = function(_a: any): boolean
			return true
		end
		local riders = 0
		for _, a in world.actors do
			if a.post == "rider" then
				riders += 1
				-- a Townsperson pick right beside the rider gets a townsperson
				local near = { X = a.x, Z = a.z } :: any
				local got = ActorsRuntime.pickFree(world.actors, all, "human", nil, near)
				t.truthy(got and got.post == "townsperson", `beside rider {a.id}: a {got and got.post}`)
			end
		end
		t.truthy(riders >= 6, `{riders} riders in town`)
		-- with only riders free, nobody is handed over (the fallback of any post skips them too)
		local onlyRiders = function(a: any): boolean
			return a.post == "rider"
		end
		t.eq(ActorsRuntime.pickFree(world.actors, onlyRiders, "human", nil, nil), nil, "no rider as a last resort")
		t.truthy(ActorsRuntime.AI_ONLY.rider, "riders are AI-only")
		-- the fallback still hands over a free person of another post
		local onlyPolice = function(a: any): boolean
			return a.post == "police"
		end
		local cop = ActorsRuntime.pickFree(world.actors, onlyPolice, "human", nil, nil)
		t.truthy(cop and cop.post == "police", "a free officer when no townsperson is free")
	end)
end
