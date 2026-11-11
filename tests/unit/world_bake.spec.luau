--!strict
-- WorldGen bake tests (spike S6, W1 #7; BUILD_PLAN §6.2 "bake determinism", §6.4 place tests): the
-- Lune bake of generated/ data gives one Model per lot (243) and per road (116) plus route props,
-- lamps and the Skyline; the data's facing; seats on World/Height (or the harvested absolute seat);
-- LevelOfDetail from data; the builder families (gables at the harvested eave/peak, doors with prompt
-- placeholders, SurfaceGui signs, Beam wires, trees around their route curves, the Hospital and
-- PoliceStation programmes, the 4 FRB interiors with server-owned doors); a stable BakeHash and an
-- InstanceHash that survives the .rbxm round trip.
local roblox = require("@lune/roblox")
local Bake = require("@worldgen/Bake")
local Factory = require("@worldgen/Factory")
local Plan = require("@worldgen/Plan")
local Geometry = require("@worldgen/Geometry")
local Kits = require("@worldgen/Kits")
local Height = require("@shared/World/Height")

local Index = require("../../generated/Index") :: any
local LotTypes = require("../../generated/LotTypes") :: any

local function factory()
	return Factory.new({
		Instance = roblox.Instance,
		Vector3 = roblox.Vector3,
		CFrame = roblox.CFrame,
		Color3 = roblox.Color3,
		Enum = roblox.Enum,
		UDim2 = roblox.UDim2,
		ColorSequence = roblox.ColorSequence,
	})
end

local function part(p: any, name: string): any
	for _, s in p.parts do
		if s.name == name then
			return s
		end
	end
	return nil
end

return function(t)
	local data = Bake.data()
	local lots, roads = data.lots, data.roads
	local plans = Bake.plans(data)
	local byId: { [string]: any } = {}
	for _, p in plans do
		if p.kind == "lot" then
			byId[p.id] = p
		end
	end

	t.test("one plan per lot and per road; every lot type has a kit from data", function()
		t.eq(#lots, Index.modules.Lots.count)
		t.eq(#roads, Index.modules.Roads.count)
		local n = { lot = 0, road = 0, props = 0, lamps = 0, skyline = 0 }
		for _, p in plans do
			n[p.kind] += 1
			if p.kind == "lot" then
				t.eq(p.attributes.UnknownType, nil, p.id)
			end
		end
		t.eq(n.lot, 243)
		t.eq(n.road, 116)
		t.eq(n.skyline, 1)
		t.truthy(n.props >= 400, `props {n.props}`)
		t.truthy(n.lamps >= 15, `lamp models {n.lamps}`) -- one model per street with lamps
		for _, lot in lots do
			t.truthy(Kits.known(lot.type), lot.type)
			t.eq(Kits.get(lot.type).lod, LotTypes.types[lot.type].lod, lot.type)
		end
	end)

	t.test("BakeHash is deterministic across runs", function()
		t.eq(Bake.hash(Bake.plans(data)), Bake.hash(plans))
	end)

	t.test("facing: cardinal lots look along their front; footprints keep their world extents", function()
		local front = { ["+Z"] = { 0, 1 }, ["-Z"] = { 0, -1 }, ["+X"] = { 1, 0 }, ["-X"] = { -1, 0 } }
		local checked = 0
		for _, lot in lots do
			local p = byId[lot.id]
			local s = p.parts[1]
			local fam = p.attributes.Builder
			if
				(fam == "Block" or fam == "Building" or fam == "House")
				and lot.footprint
				and not p.attributes.AttachedTo
			then
				local x0, x1, z0, z1 = Plan.worldBox(s)
				t.near(x1 - x0, lot.footprint.w, 1e-9, lot.id)
				t.near(z1 - z0, lot.footprint.d, 1e-9, lot.id)
			end
			local f = front[lot.facing]
			if f then
				local cf = roblox.CFrame.Angles(0, s.yaw, 0)
				t.near(cf.LookVector.X, f[1], 1e-5, lot.id)
				t.near(cf.LookVector.Z, f[2], 1e-5, lot.id)
				checked += 1
			end
		end
		t.truthy(checked >= 115, `checked {checked}`)
	end)

	t.test("seats: World/Height or the harvested absolute seat; buildings carry their data LevelOfDetail", function()
		for _, lot in lots do
			local p = byId[lot.id]
			local abs = lot.seat and string.match(lot.seat, "^absolute:(.+)$")
			local want = if abs then tonumber(abs) * 2.5 else Height.at(lot.x, lot.z)
			t.near(p.attributes.SeatY :: number, want, 1e-9, lot.id)
			if p.category == "building" then
				t.eq(p.lod, "SLIM", lot.id)
			end
		end
	end)

	t.test("houses: harvested eave and peak, gable plates meet at the ridge; outer homes have gables", function()
		local core = byId.core_house_1_bungalow
		t.eq(core.attributes.Interior, "frb_bungalow")
		t.near(core.attributes.EaveY :: number, 6.068 * 2.5, 1e-9)
		t.near(core.attributes.PeakY :: number, 8.528 * 2.5, 1e-9)
		local a, b = part(core, "RoofA"), part(core, "RoofB")
		t.truthy(a and b, "two roof plates")
		-- the plates' upper faces rise toward the ridge: their centres sit halfway up the slope
		local seat = core.attributes.SeatY :: number
		t.near(a.cy - seat, (6.068 + 8.528) / 2 * 2.5, 0.25)
		t.truthy(math.abs(a.pitch) > 0.1, "pitched")
		-- outer homes (review 2026-11-09): the v5.4 gable to the harvested peak, body to the eave
		local outer = byId.outer_home_05
		t.eq(outer.attributes.Roof, "gable")
		local body = part(outer, "Body")
		local outerLot
		for _, l in lots do
			if l.id == "outer_home_05" then
				outerLot = l
			end
		end
		t.near(body.sy, outerLot.params.eaveU * 2.5, 1e-6)
		t.near(outer.attributes.PeakY :: number, outerLot.params.peakU * 2.5, 1e-6)
		t.truthy(part(outer, "RoofA") and part(outer, "RoofB"), "outer home roof plates")
	end)

	t.test(
		"doors, prompts and signs: every building with a door has a prompt placeholder; quay names on SurfaceGuis",
		function()
			local doors, signs = 0, 0
			for _, p in plans do
				if p.kind == "lot" then
					for _, e in p.extras or {} do
						if e.kind == "Prompt" then
							doors += 1
						elseif e.kind == "SurfaceGui" then
							signs += 1
							t.truthy(e.text and #e.text > 0, p.id)
						end
					end
				end
			end
			t.truthy(doors >= 80, `prompts {doors}`)
			t.truthy(signs >= 40, `signs {signs}`)
			local anchor = byId.quay_bldg_w_00
			local found = false
			for _, e in anchor.extras do
				found = found or (e.kind == "SurfaceGui" and e.text == "THE OLD ANCHOR")
			end
			t.truthy(found, "THE OLD ANCHOR sign")
		end
	)

	t.test("hospital: 8 brief rooms as volumes, 4 stations, 36 pharmacy item slots, enterable", function()
		local h = byId.hospital_main
		t.eq(h.attributes.Builder, "Hospital")
		t.eq(h.attributes.Enterable, true)
		for _, id in
			{ "reception", "triage", "ward_a", "ward_b", "isolation", "pharmacy", "staff_room", "ambulance_bay" }
		do
			local v = part(h, "Room_" .. id)
			t.truthy(v, id)
			t.eq(v.canCollide, false, id)
			t.eq(v.canQuery, true, id)
		end
		local stations, slots = 0, 0
		for _, s in h.parts do
			if s.role == "Station" then
				stations += 1
			end
		end
		for _, e in h.extras do
			if e.kind == "Attachment" and e.attrs and e.attrs.ItemSlot then
				slots += 1
			end
		end
		t.eq(stations, 4)
		t.eq(slots, 36)
		t.eq(part(h, "Door_entrance").attrs.ServerOwned, true)
		t.eq(part(h, "Nav").attrs.NavUnreached, 0)
	end)

	t.test("police station: lobby, briefing, drone console, 2 player-car pads and the AI cruiser pad", function()
		local s = byId.west_police_station
		t.eq(s.attributes.Builder, "PoliceStation")
		t.truthy(part(s, "Room_lobby"))
		t.truthy(part(s, "Room_briefing"))
		t.eq(part(s, "Station_drone_console").attrs.Station, "drone_console")
		local player, ai = 0, 0
		for _, p in s.parts do
			if p.role == "Pad" then
				if p.attrs.PadKind == "player_car" then
					player += 1
				else
					ai += 1
				end
			end
		end
		t.eq(player, 2)
		t.eq(ai, 1)
	end)

	t.test(
		"FRB interiors: 4 houses with rooms, server-owned lockable doors, hide spots and a connected room graph",
		function()
			local n = 0
			for _, p in plans do
				if p.kind == "lot" and p.attributes.Interior then
					n += 1
					t.eq(part(p, "Nav").attrs.NavUnreached, 0, p.id)
					local front, back, hides = part(p, "Door_front"), part(p, "Door_back"), 0
					t.truthy(front and front.attrs.ServerOwned and front.attrs.Lockable, p.id)
					t.truthy(back, p.id)
					for _, e in p.extras do
						if e.kind == "Attachment" and e.attrs and e.attrs.HideType then
							hides += 1
						end
					end
					t.truthy(hides >= 3, `{p.id} hides {hides}`)
				end
			end
			t.eq(n, 4)
		end
	)

	t.test("route props: trees around their curves, poles, Beam wires, pipes and fences, LOD from data", function()
		local kinds: { [string]: number } = {}
		local beams = 0
		for _, p in plans do
			if p.kind == "props" then
				kinds[p.category] = (kinds[p.category] or 0) + 1
				t.eq(p.lod, Kits.routeProps[p.category].lod, p.id)
				for _, e in p.extras or {} do
					if e.kind == "Beam" then
						beams += 1
					end
				end
			end
		end
		t.eq(kinds.tree, 95) -- one model per harvested tree trunk (trees.json: 95)
		t.eq(kinds.pole, 110) -- the 97 grid poles plus 7 Westside and 6 estate-avenue telephone poles
		t.eq(kinds.wire, 150)
		t.truthy((kinds.pipe or 0) >= 60, `pipes {kinds.pipe}`)
		t.truthy((kinds.fence or 0) >= 12, `fences {kinds.fence}`)
		t.truthy(beams >= 150, `beams {beams}`)
	end)

	t.test(
		"lamps: one row per street, 25 st clear of lamps and poles, vertical posts, a 5-10 % flicker set, Skyline heads",
		function()
			local posts, flicker = 0, 0
			local sky
			local at: { any } = {}
			local poles: { any } = {}
			for _, p in plans do
				if p.kind == "lamps" then
					for _, s in p.parts do
						if string.sub(s.name, 1, 5) == "Post_" then
							posts += 1
							table.insert(at, s)
							if s.attrs.Flicker then
								flicker += 1
							end
							-- vertical: a cylinder whose axis (local X) is turned straight up
							t.near(s.roll, math.pi / 2, 1e-9, s.name)
							t.eq(s.pitch, 0, s.name)
							t.truthy(s.sx >= 14 and s.sx <= 17, `{s.name} height {s.sx}`)
						end
					end
				elseif p.kind == "skyline" then
					sky = p
				elseif p.kind == "props" and p.category == "pole" then
					table.insert(poles, p.parts[1])
				end
			end
			t.truthy(posts >= 100 and posts <= 200, `posts {posts}`)
			for i, a in at do
				for j = i + 1, #at do
					local b = at[j]
					t.truthy(math.sqrt((a.cx - b.cx) ^ 2 + (a.cz - b.cz) ^ 2) >= 25, `{a.name} near {b.name}`)
				end
				for _, b in poles do
					t.truthy(math.sqrt((a.cx - b.cx) ^ 2 + (a.cz - b.cz) ^ 2) >= 25, `{a.name} near a pole`)
				end
				-- never on a sidewalk, footpath or street strip (the bridge's own lamps stand on its deck)
				for _, rp in plans do
					local ownBridge = string.find(rp.id, "bridge", 1, true) ~= nil
						and string.find(a.name, rp.id, 1, true) ~= nil
					if rp.kind == "road" and not ownBridge then
						for _, seg in rp.parts do
							if seg.role ~= "Paint" then
								t.truthy(not Geometry.containsXZ(seg, a.cx, a.cz, 0), `{a.name} on {rp.id}`)
							end
						end
					end
				end
			end
			local f = flicker / posts
			t.truthy(f >= 0.05 and f <= 0.1, `flicker {f}`)
			t.eq(sky.attributes.LampHeads, posts)
			t.eq(sky.streaming, "Persistent")
			for _, s in sky.parts do
				t.eq(s.canCollide, false, s.name)
			end
		end
	)

	t.test("Town Model: counts, attributes, InstanceHash survives the .rbxm round trip", function()
		local town = Bake.run(data, factory())
		t.eq(#town:FindFirstChild("Lots"):GetChildren(), 243)
		t.eq(#town:FindFirstChild("Roads"):GetChildren(), 116)
		t.truthy(town:FindFirstChild("Skyline") ~= nil, "Skyline")
		t.eq(town:GetAttribute("BakeHash"), Bake.hash(plans))
		local back = roblox.deserializeModel(roblox.serializeModel({ town }))[1]
		t.eq(Bake.instanceHash(back), town:GetAttribute("InstanceHash"))
		t.eq(back:GetAttribute("BakeHash"), town:GetAttribute("BakeHash"))
		t.truthy(Bake.maxGeometryDelta(Bake.geometry(town), Bake.geometry(back)) <= 1e-4, "geometry round trip")
		local slim = 0
		for _, m in back:FindFirstChild("Lots"):GetChildren() do
			t.truthy(m.PrimaryPart ~= nil, m.Name)
			t.truthy(m.PrimaryPart.Anchored, m.Name)
			if m.LevelOfDetail == roblox.Enum.ModelLevelOfDetail.SLIM then
				slim += 1
			end
		end
		t.eq(slim, 78 + 15) -- buildings plus their interior children keep the type's SLIM
		local sign = back:FindFirstChild("Lots"):FindFirstChild("quay_bldg_w_00"):FindFirstChild("SignBoard")
		t.eq(sign:FindFirstChild("Sign"):FindFirstChild("Text").Text, "THE OLD ANCHOR")
		local wire = back:FindFirstChild("Props"):FindFirstChildWhichIsA("Model")
		t.truthy(wire ~= nil)
	end)

	-- The v5.4 hospital zones (lobby, triage, ward bays...) are child lots inside the enterable shell.
	-- As see-through boxes up to 235 st long they stood through every room and its furniture.
	t.test("hospital zones inside the enterable shell are invisible markers; mall shops are unchanged", function()
		local hidden, ghosts = 0, 0
		for _, p in plans do
			if p.kind == "lot" and p.attributes.ParentLot ~= nil then
				local s = p.parts[1]
				if p.attributes.ParentLot == "hospital_main" then
					hidden += 1
					t.eq(s.transparency, 1, p.id)
					t.eq(s.canQuery, false, p.id)
					t.eq(s.canCollide, false, p.id)
				else
					ghosts += 1
					t.eq(s.transparency, 0.7, p.id)
				end
			end
		end
		t.truthy(hidden >= 8, `{hidden} hospital zones`)
		t.truthy(ghosts >= 6, `{ghosts} other child lots`)
	end)

	t.test("PointLight extras: built lit with their range and colour, hashed, kept by the .rbxm", function()
		local Greybox = require("@worldgen/Builders/Greybox")
		local Spec = require("@worldgen/Spec")
		local function plan(range: number): any
			local list = Spec.list()
			list:add(Geometry.frame(0, 0, 0, 0), "Shade", 0, 10, 0, 1, 1, 1, { canCollide = false, canQuery = false })
			list:extra({
				kind = "PointLight",
				part = "Shade",
				name = "Glow",
				range = range,
				brightness = 0.9,
				color = { 255, 218, 152 },
			})
			return {
				kind = "lot",
				id = "lamp_test",
				category = "prop",
				lod = "Disabled",
				streaming = "Default",
				attributes = {},
				parts = list.parts,
				extras = list.extras,
			}
		end
		local model = Greybox.build(plan(14), factory())
		local back = roblox.deserializeModel(roblox.serializeModel({ model }))[1]
		local light = back:FindFirstChild("Shade"):FindFirstChild("Glow")
		t.eq(light.ClassName, "PointLight")
		t.near(light.Range, 14, 1e-6)
		t.near(light.Brightness, 0.9, 1e-6)
		t.eq(light.Enabled, true)
		t.eq(light.Shadows, false)
		t.near(light.Color.G * 255, 218, 0.51)
		t.eq(back:FindFirstChild("Shade").CanQuery, false)
		-- the plan hash sees the light's parameters and the part's canQuery; so does the instance hash
		t.truthy(Bake.hash({ plan(14) }) ~= Bake.hash({ plan(18) }), "range is hashed")
		local wrap = roblox.Instance.new("Model")
		wrap.Name = "Town"
		model.Parent = wrap
		local lines = table.concat(Bake.instanceLines(wrap), "\n")
		t.truthy(string.find(lines, "Glow|PointLight|14.0/0.90/true", 1, true), lines)
		-- a range past the engine's 60 st limit is clamped by Factory, the same in both runtimes
		local far = Greybox.build(plan(90), factory())
		t.near(far:FindFirstChild("Shade"):FindFirstChild("Glow").Range, 60, 1e-6)
	end)
end
