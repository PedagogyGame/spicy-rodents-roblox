--!strict
-- WorldGen look pass (FRB "make it look like the v5.4 town"): Palette reads the lots' v5.4 colours
-- (style hexes, the core/outer/quay tables, plates); buildings carry windows, gable infill wedges, a
-- plinth and cornice or timber; asphalt gets dashed centre paint and sidewalks a street-side curb;
-- every tree has a leafy crown that neither collides nor takes queries; poles carry a crossarm;
-- lamps have an arm and a head over the kerb; the Skyline massing is baked transparent; the Town
-- round-trips through .rbxm with WedgeParts and Ball shapes; the part budget holds.
local roblox = require("@lune/roblox")
local Bake = require("@worldgen/Bake")
local Factory = require("@worldgen/Factory")
local Palette = require("@worldgen/Palette")
local Kits = require("@worldgen/Kits")

return function(t)
	local data = Bake.data()
	local plans = Bake.plans(data)
	local byId: { [string]: any } = {}
	for _, p in plans do
		byId[p.id] = p
	end
	local function parts(p: any, prefix: string): { any }
		local out = {}
		for _, s in p.parts do
			if string.sub(s.name, 1, #prefix) == prefix then
				table.insert(out, s)
			end
		end
		return out
	end
	local function rgb(h: string): string
		local c = Palette.hex(h)
		return `{c[1]},{c[2]},{c[3]}`
	end
	local function str(c: { number }): string
		return `{c[1]},{c[2]},{c[3]}`
	end

	t.test("Palette: style hexes, the v5.4 house/quay tables and plates", function()
		local lots: { [string]: any } = {}
		for _, l in data.lots do
			lots[l.id] = l
		end
		local mansion = Palette.forLot(lots.estate_0_mansion, Kits.get("estate_mansion"))
		t.eq(str(mansion.wall), rgb("#ad7964"))
		t.eq(str(mansion.roof), rgb("#514846"))
		t.eq(mansion.material, "Brick")
		local core = Palette.forLot(lots.core_house_2_brick, Kits.get("house"))
		t.eq(str(core.wall), rgb("#bb8e71"))
		t.eq(str(core.roof), rgb("#615653"))
		local outer = Palette.forLot(lots.outer_home_07, Kits.get("house"))
		t.eq(str(outer.wall), rgb("#b7c5c1")) -- v5.4 wall[i % 6] with i = 7
		t.eq(str(outer.wall), str(Palette.forLot(lots.outer_home_07, nil).wall))
		local q = Palette.forLot(lots.quay_bldg_w_00, Kits.get("quay_building"))
		t.truthy(q.timber, "quay half-timber")
		t.eq(str(Palette.forLot(lots.galleria_building, Kits.get("mall")).wall), rgb("#ded2ba"))
		t.eq(str(Palette.forLot(lots.hospital_main, Kits.get("hospital")).wall), rgb("#e6e5db"))
		local c, m = Palette.plate("lawn", nil)
		t.eq(m, "Grass")
		t.eq(str(c), rgb("#819762"))
		local _, wm, wt = Palette.plate("estate_pool", "deck #d9c6b0")
		t.eq(wm, "Glass")
		t.truthy(wt > 0, "water is see-through")
	end)

	t.test("buildings: wall colour, windows, gable wedges, cornice, timber, chimney", function()
		local mansion = byId.estate_0_mansion
		t.eq(str(parts(mansion, "Body")[1].color), rgb("#ad7964"))
		t.truthy(#parts(mansion, "Win") >= 8, "mansion windows")
		t.eq(#parts(mansion, "Cornice"), 4)
		for _, w in parts(mansion, "Win") do
			t.eq(w.canCollide, false, w.name)
		end
		local house = byId.outer_home_02
		local wedges = parts(house, "Gable")
		if house.attributes.Roof == "gable" then
			t.eq(#wedges, 4)
			t.eq(wedges[1].shape, "Wedge")
		end
		local quay = byId.quay_bldg_w_00
		t.truthy(#parts(quay, "Timber") == 6, "timber bands")
		t.truthy(#parts(quay, "Gable") == 4, "quay gables")
		local frb = byId.core_house_0_victorian
		t.truthy(#parts(frb, "Win") >= 2, "FRB shell windows")
		t.eq(#parts(frb, "Chimney"), 1)
		t.truthy(#parts(byId.hospital_main, "Win") >= 4, "hospital windows")
	end)

	t.test("roads: dark asphalt with centre dashes, sidewalk curbs on the street side", function()
		local street = byId.rd_001_grid_ns_x0
		t.eq(str(street.parts[1].color), str(Palette.ROAD.asphalt))
		t.truthy(#parts(street, "Dash") >= 20, "dashes")
		local walk = byId["rd_002_sidewalk_x-12.1"]
		local curbs = parts(walk, "Curb")
		t.truthy(#curbs >= 5, "curbs")
		for _, c in curbs do
			-- the street (x = 0) is to the +x side of the x = -12.1 u sidewalk
			t.truthy(c.cx > walk.parts[1].cx, `{c.name} at {c.cx}`)
			t.eq(c.canCollide, false)
		end
	end)

	t.test("trees: a leafy crown around every trunk, poles with crossarms, lamp arms over the kerb", function()
		local trees, crowned, poles, arms = 0, 0, 0, 0
		for _, p in plans do
			if p.kind == "props" and p.category == "tree" then
				trees += 1
				local leaves = parts(p, "Leaves")
				if #leaves >= 2 then
					crowned += 1
				end
				for _, b in leaves do
					t.eq(b.shape, "Ball")
					t.eq(b.canCollide, false)
					t.eq(b.canQuery, false)
					t.eq(b.sx, b.sz)
				end
			elseif p.kind == "props" and p.category == "pole" then
				poles += 1
				arms += #parts(p, "Crossarm")
			end
		end
		t.eq(crowned, trees)
		t.eq(arms, poles)
		local sky = byId.Skyline
		local heads, armParts = 0, 0
		for _, s in sky.parts do
			if string.sub(s.name, 1, 5) == "Head_" then
				heads += 1
			elseif string.sub(s.name, 1, 4) == "Arm_" then
				armParts += 1
			elseif s.attrs and s.attrs.Lot then
				t.eq(s.transparency, 1, s.name)
			end
		end
		t.eq(armParts, heads)
	end)

	t.test("Town: WedgeParts and balls survive the .rbxm round trip; part budget", function()
		local town = Bake.run(
			data,
			Factory.new({
				Instance = roblox.Instance,
				Vector3 = roblox.Vector3,
				CFrame = roblox.CFrame,
				Color3 = roblox.Color3,
				Enum = roblox.Enum,
				UDim2 = roblox.UDim2,
				ColorSequence = roblox.ColorSequence,
			})
		)
		local back = roblox.deserializeModel(roblox.serializeModel({ town }))[1]
		t.eq(Bake.instanceHash(back), town:GetAttribute("InstanceHash"))
		local wedges, balls, total = 0, 0, 0
		for _, d in back:GetDescendants() do
			if d:IsA("BasePart") then
				total += 1
				if d.ClassName == "WedgePart" then
					wedges += 1
				elseif d.Shape == roblox.Enum.PartType.Ball then
					balls += 1
				end
			end
		end
		t.truthy(wedges >= 100, `wedges {wedges}`)
		t.truthy(balls >= 500, `balls {balls}`)
		t.eq(total, town:GetAttribute("PartCount"))
		t.truthy(total <= 30000, `part budget: {total}`) -- review 2026-11-09: full tree crowns, under ~30k
	end)
end
