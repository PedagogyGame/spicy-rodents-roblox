--!strict
-- WorldGen bake tests (spike S6; BUILD_PLAN §6.2 "bake determinism", §6.4 place tests): the Lune
-- bake of generated/ data gives one Model per lot (243) and per road (116), no solid overlap
-- between lot greyboxes, the data's facing, seats on World/Height, LevelOfDetail on every building,
-- a stable BakeHash and an InstanceHash that survives the .rbxm round trip.
local roblox = require("@lune/roblox")
local Bake = require("@worldgen/Bake")
local Factory = require("@worldgen/Factory")
local Plan = require("@worldgen/Plan")
local Kits = require("@worldgen/Kits")
local Height = require("@shared/World/Height")

local lots = require("../../generated/Lots") :: any
local roads = require("../../generated/Roads") :: any
local Index = require("../../generated/Index") :: any

local function factory()
	return Factory.new({
		Instance = roblox.Instance,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		Enum = roblox.Enum,
	})
end

return function(t)
	local data = { lots = lots, roads = roads }
	local plans = Bake.plans(data)

	t.test("one plan per lot and per road; every lot type has a kit", function()
		t.eq(#lots, Index.modules.Lots.count)
		t.eq(#roads, Index.modules.Roads.count)
		local nl, nr = 0, 0
		for _, p in plans do
			if p.kind == "lot" then
				nl += 1
				t.eq(p.attributes.UnknownType, nil, p.id)
			else
				nr += 1
			end
		end
		t.eq(nl, 243)
		t.eq(nr, 116)
	end)

	t.test("BakeHash is deterministic across runs", function()
		t.eq(Bake.hash(Bake.plans(data)), Bake.hash(plans))
	end)

	t.test("no solid overlap between lot greyboxes (3-D, 0.05 st tolerance)", function()
		local solids = {}
		for _, p in plans do
			if p.kind == "lot" and p.attributes.Solid then
				table.insert(solids, p)
			end
		end
		local overlaps = {}
		for i = 1, #solids do
			local a = solids[i].parts[1]
			local ax0, ax1, az0, az1 = Plan.worldBox(a)
			for j = i + 1, #solids do
				local b = solids[j].parts[1]
				local bx0, bx1, bz0, bz1 = Plan.worldBox(b)
				local ox = math.min(ax1, bx1) - math.max(ax0, bx0)
				local oz = math.min(az1, bz1) - math.max(az0, bz0)
				local oy = math.min(a.cy + a.sy / 2, b.cy + b.sy / 2) - math.max(a.cy - a.sy / 2, b.cy - b.sy / 2)
				if ox > 0.05 and oz > 0.05 and oy > 0.05 then
					table.insert(overlaps, `{solids[i].id} x {solids[j].id}`)
				end
			end
		end
		print(`      {#solids} solid lots, {#overlaps} overlaps`)
		t.eq(#overlaps, 0, table.concat(overlaps, "; "))
	end)

	t.test("facing: cardinal lots look along their front; footprints keep their world extents", function()
		local front = { ["+Z"] = { 0, 1 }, ["-Z"] = { 0, -1 }, ["+X"] = { 1, 0 }, ["-X"] = { -1, 0 } }
		local checked = 0
		for i, lot in lots do
			local f = front[lot.facing]
			local s = plans[i].parts[1]
			local x0, x1, z0, z1 = Plan.worldBox(s)
			if lot.footprint and not plans[i].attributes.AttachedTo then
				t.near(x1 - x0, lot.footprint.w, 1e-9, lot.id)
				t.near(z1 - z0, lot.footprint.d, 1e-9, lot.id)
			end
			if f then
				local cf = roblox.CFrame.Angles(0, s.yaw, 0)
				t.near(cf.LookVector.X, f[1], 1e-5, lot.id)
				t.near(cf.LookVector.Z, f[2], 1e-5, lot.id)
				checked += 1
			elseif type(lot.yaw) == "number" then
				-- free yaw: the box stays world-aligned, the front snaps to the nearest quarter turn
				local cf = roblox.CFrame.Angles(0, s.yaw, 0)
				local dot = cf.LookVector.X * math.sin(lot.yaw) + cf.LookVector.Z * math.cos(lot.yaw)
				t.truthy(dot >= math.cos(math.pi / 4) - 1e-6, lot.id)
				t.near(plans[i].attributes.FacingYaw :: number, lot.yaw, 1e-12, lot.id)
				checked += 1
			end
		end
		t.truthy(checked >= 175, `checked {checked}`)
	end)

	t.test("buildings sit on World/Height and carry LevelOfDetail SLIM", function()
		for i, lot in lots do
			local p = plans[i]
			t.near(p.attributes.SeatY :: number, Height.at(lot.x, lot.z), 1e-9, lot.id)
			if p.category == "building" then
				t.eq(p.lod, "SLIM", lot.id)
				local s = p.parts[1]
				t.near(s.cy - s.sy / 2, Height.at(lot.x, lot.z), 1e-9, lot.id)
				t.near(s.sy, Kits.get(lot.type).heightU * 2.5, 1e-9, lot.id)
			end
		end
	end)

	t.test("roads: continuous terrain-following segments", function()
		for _, p in plans do
			if p.kind == "road" then
				for k = 2, #p.parts do
					local a, b = p.parts[k - 1], p.parts[k]
					local ha = a.cy + math.sin(a.pitch) * a.sz / 2
					local hb = b.cy - math.sin(b.pitch) * b.sz / 2
					t.near(ha, hb, 1e-6, p.id)
				end
			end
		end
	end)

	t.test("Town Model: counts, attributes, InstanceHash survives the .rbxm round trip", function()
		local town = Bake.run(data, factory())
		t.eq(#town:FindFirstChild("Lots"):GetChildren(), 243)
		t.eq(#town:FindFirstChild("Roads"):GetChildren(), 116)
		t.eq(town:GetAttribute("BakeHash"), Bake.hash(plans))
		local back = roblox.deserializeModel(roblox.serializeModel({ town }))[1]
		t.eq(Bake.instanceHash(back), town:GetAttribute("InstanceHash"))
		t.eq(back:GetAttribute("BakeHash"), town:GetAttribute("BakeHash"))
		local slim = 0
		for _, m in back:FindFirstChild("Lots"):GetChildren() do
			t.truthy(m.PrimaryPart ~= nil, m.Name)
			t.truthy(m.PrimaryPart.Anchored, m.Name)
			if m.LevelOfDetail == roblox.Enum.ModelLevelOfDetail.SLIM then
				slim += 1
			end
		end
		t.eq(slim, 78 + 15) -- buildings plus their interior children keep the kit's SLIM
	end)
end
