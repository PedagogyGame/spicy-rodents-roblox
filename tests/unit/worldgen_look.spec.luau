--!strict
-- WorldGen look pass (FRB "make it look like the v5.4 town"): Palette reads the lots' v5.4 colours
-- (style hexes, the core/outer/quay tables, plates); buildings carry windows, gable infill wedges, a
-- plinth and cornice or timber; asphalt gets dashed centre paint and sidewalks a street-side curb;
-- every tree has a leafy crown that neither collides nor takes queries; poles carry a crossarm;
-- lamps have an arm and a head over the kerb; the Skyline massing is baked transparent; the Town
-- round-trips through .rbxm with WedgeParts and Ball shapes; the part budget holds.
local roblox = require("@lune/roblox")
local Bake = require("@worldgen/Bake")
local Coplanar = require("@worldgen/Coplanar")
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
				-- the Blender model (generated/TreeArt): three leaf layers and the bark as visual-only meshes
				-- with their PBR maps; the bark cylinders under them are invisible proxies
				local leaves = parts(p, "Leaves")
				if #leaves >= 3 and #parts(p, "Bark") == 1 then
					crowned += 1
				end
				for _, b in p.parts do
					if b.mesh then
						t.truthy(string.find(b.mesh.id, "^rbxassetid://%d+$"), b.name)
						t.truthy(b.mesh.colorMap and b.mesh.normalMap and b.mesh.roughnessMap, b.name)
						t.eq(b.canCollide, false)
						t.eq(b.canQuery, false)
						t.eq(b.yaw, 0)
					else
						t.eq(b.transparency, 1, b.name)
						t.eq(b.role, "Limb", b.name)
					end
				end
				t.eq(p.parts[1].name, "Trunk_1") -- lamps keep clear of parts[1] (Bake)
				t.eq(p.attributes.Mesh, true)
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

	t.test("Town: WedgeParts, balls and tree MeshParts survive the .rbxm round trip; part budget", function()
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
		local wedges, balls, meshes, total = 0, 0, 0, 0
		for _, d in back:GetDescendants() do
			if d:IsA("BasePart") then
				total += 1
				if d.ClassName == "WedgePart" then
					wedges += 1
				elseif d.ClassName == "MeshPart" then
					meshes += 1
					-- the colour map is the part's texture; no SurfaceAppearance is baked (BUILD_PLAN D12)
					-- (Lune reads the texture back under its file name, TextureContent)
					t.truthy(string.find(tostring(d.TextureContent), "rbxassetid://%d+"), d.Name)
					t.eq(d:FindFirstChildOfClass("SurfaceAppearance"), nil)
				elseif d.Shape == roblox.Enum.PartType.Ball then
					balls += 1
				end
			end
		end
		t.truthy(wedges >= 100, `wedges {wedges}`)
		print(`      balls {balls}, tree meshes {meshes}`)
		t.eq(meshes, 392) -- 95 trees: bark + three leaf layers (+ apples on the 12 apple trees)
		t.eq(total, town:GetAttribute("PartCount"))
		print(`      part count {total}`)
		t.truthy(total <= 27000, `part budget: {total}`) -- art pass 2026-11-10: trim and interiors, under 27k
	end)

	-- Two drawn faces on one plane flicker against each other as the camera moves (the owner's "doors
	-- glitch and shimmer in a strobe light way": the leaf's face lay on the wall's own plane). The check
	-- is WorldGen/Coplanar, over every part of every model in the town: doors, signs, window bars, trim,
	-- eaves, roof plates, furniture, floors and wall linings alike.
	t.test("no drawn face in the town lies on the plane of another drawn face (flicker)", function()
		local doors = 0
		for _, p in plans do
			if p.kind == "lot" then
				for _, d in p.parts do
					if (d.role == "Door" or d.role == "Sign") and (d.transparency or 0) < 1 then
						doors += 1
					end
				end
			end
		end
		t.truthy(doors >= 72, `{doors} doors and sign boards checked`)
		local r = Coplanar.run(plans)
		print(`      {r.checked} drawn blocks checked for shared planes`)
		t.truthy(r.checked >= 8000, `{r.checked} blocks checked`)
		t.eq(table.concat(r.clashes, "; ", 1, math.min(#r.clashes, 6)), "", `{#r.clashes} flickering faces`)
	end)

	t.test(
		"Coplanar: finds a face on a wall's plane, ignores hidden backs, grounded bottoms and tiny overlaps",
		function()
			local function box(
				name: string,
				cx: number,
				cy: number,
				cz: number,
				sx: number,
				sy: number,
				sz: number,
				c: number
			): any
				return {
					name = name,
					cx = cx,
					cy = cy,
					cz = cz,
					yaw = 0,
					pitch = 0,
					sx = sx,
					sy = sy,
					sz = sz,
					color = { c, c, c },
					material = "SmoothPlastic",
					canCollide = false,
					transparency = 0,
				}
			end
			local wall = box("Wall", 0, 5, 0, 10, 10, 1, 200)
			-- a door leaf whose outer (-z) face lies on the wall's outer face: the owner's strobe
			local flush = Coplanar.clashes({ wall, box("Door", 0, 4.5, -0.25, 3, 8, 0.5, 90) })
			t.eq(#flush, 1)
			t.eq(flush[1].axis, 3)
			t.eq(flush[1].side, -1)
			-- 0.12 proud: no clash
			t.eq(#Coplanar.clashes({ wall, box("Door", 0, 4.5, -0.37, 3, 8, 0.5, 90) }), 0)
			-- the same colour and material cannot be told apart: no clash
			t.eq(#Coplanar.clashes({ wall, box("Patch", 0, 4, -0.25, 3, 8, 0.5, 200) }), 0)
			-- two boards with their backs on the wall's face are hidden by the wall itself
			local a, b = box("BoardA", 0, 4, -0.6, 4, 4, 0.2, 90), box("BoardB", 1, 4, -0.65, 4, 4, 0.3, 120)
			t.eq(#Coplanar.clashes({ wall, a, b }), 0)
			-- without the wall their backs are in the open, and they clash
			t.eq(#Coplanar.clashes({ a, b }), 1)
			-- bottoms on the ground at the seat are never seen
			local plinth, body = box("Plinth", 0, 0.6, 0, 12, 1.2, 3, 150), box("Body", 0, 5, 0, 10, 10, 1, 200)
			t.eq(#Coplanar.clashes({ plinth, body }, 0), 0)
			t.eq(#Coplanar.clashes({ plinth, body }, -5), 1)
			-- a sliver of shared area (under 0.3 st on a side) is not a clash
			t.eq(#Coplanar.clashes({ wall, box("Bar", 0, 9.9, -0.4, 0.2, 0.2, 0.2, 90) }), 0)
			-- pitched parts are compared in their own frame: an eave strip continuing a roof plate in another
			-- colour on the plate's own top plane clashes where the two overlap
			local plate = box("Plate", 0, 10, 0, 20, 0.4, 12, 100)
			plate.pitch = 0.5
			local strip = box("Strip", 0, 10, 0, 20, 0.4, 2, 240)
			strip.pitch = 0.5
			t.truthy(#Coplanar.clashes({ plate, strip }) >= 1, "pitched overlap")
		end
	)

	-- Owner 2026-11-10: "make sure squirrel cannot run through houses, double check that".
	t.test("every house is solid: bodies, walls, roofs and the foundations under them all collide", function()
		local bodies, walls, foundations, open = 0, 0, 0, {}
		for _, p in plans do
			if p.kind == "lot" then
				for _, part in p.parts do
					local name = part.name
					local massing = name == "Body"
						or name == "Foundation"
						or string.sub(name, 1, 4) == "Wall"
						or string.sub(name, 1, 4) == "Roof"
					if massing and (part.transparency or 0) < 1 then
						if name == "Body" then
							bodies += 1
						elseif name == "Foundation" then
							foundations += 1
						else
							walls += 1
						end
						if part.canCollide ~= true then
							table.insert(open, `{p.id}.{name}`)
						end
					end
				end
			end
		end
		t.truthy(
			bodies >= 70 and walls >= 100 and foundations >= 30,
			`{bodies} bodies, {walls} walls and roofs, {foundations} foundations`
		)
		t.eq(table.concat(open, ", ", 1, math.min(#open, 8)), "", `{#open} parts a body could pass through`)
	end)
end
