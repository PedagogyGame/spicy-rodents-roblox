--!strict
-- The owner's finished pinball models on the baked machines (Server/Assets/PinballArt), on stand-in Models built
-- from generated/PinballArt (what the uploads hold: every mesh by name and size, placed anywhere), and the
-- manifest against the pack ChatGPT made them to (docs/owner/pinball_blender/chatgpt_pack/pinball_data.json):
--   * every part the client moves is still there, by its name, and each mesh lands within 1 mm of the baked part
--     it replaces (drop and standup targets about their bottom edge, the spinner on its axis and turning about
--     it, the bumper caps, the plunger's knob and rod, the flipper meshes about their Hub, the board);
--   * the baked parts the meshes replace are gone, the colliders stay unseen, the live text stays;
--   * a second run changes nothing; with no asset ids nothing changes and it is said once; a Model missing a
--     mesh leaves the machine as baked.
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Cabinet = require("@shared/Minigames/Pinball/Cabinet")
local Games = require("@shared/Minigames/Games")
local Tables = require("@shared/Minigames/Pinball/Tables")
local PinballArtData = require("../../generated/PinballArt")
local Bake = require("../../tools/bake/games/Pinball")
local GameBakes = require("../../tools/bake/GameBakes")
local Kit = require("../../tools/bake/alley/Kit")
local PinballArt = require("@server/Assets/PinballArt")

local Instance = roblox.Instance
local CFrame = roblox.CFrame
local Vector3 = roblox.Vector3
local ENV =
	{ CFrame = roblox.CFrame, Color3 = roblox.Color3, Enum = roblox.Enum, Instance = Instance, Vector3 = Vector3 }
local PLACE: AlleyLayout.Place = { x = 40, z = -90, floorY = 12, yaw = 0.6 }
local MM = 0.001 / 0.28 -- a millimetre in studs
local DATA = serde.decode("json", fs.readFile("docs/owner/pinball_blender/chatgpt_pack/pinball_data.json"))

-- the alley's site with the three machines, baked as tools/bake/attractions.luau bakes them
local function baked(): (any, { [number]: any })
	local root = Instance.new("Folder")
	root.Name = "Attractions"
	local site = GameBakes.siteModel(roblox, "BellwetherBowl", "bowling_alley", PLACE)
	site.Parent = root
	local room = Instance.new("Model")
	room.Name = "GamesRoom"
	room.Parent = site
	local kit = Kit.new(roblox, PLACE)
	local machines = {}
	for _, st in Games.stations({ bowling_alley = PLACE }) do
		if st.game == "pinball" then
			Bake.build(kit, room, st, nil)
			machines[st.index :: number] = room:FindFirstChild(Cabinet.model(st.index :: number))
		end
	end
	return root, machines
end

-- the data with every Model "uploaded"
local function uploaded(): any
	local d = table.clone(PinballArtData :: any)
	d.assets = {}
	for i, tag in PinballArt.TAGS do
		d.assets[tag] = { id = 1000 + i, moderation = "Approved" }
	end
	return d
end

-- a stand-in for InsertService:LoadAsset: the Model's MeshParts by name and size, somewhere off to the side
-- drop: a mesh the Model leaves out; bare: a textured mesh that came without its picture
local function loader(data: any, drop: string?, bare: string?): ((number) -> any, { number })
	local calls = {}
	return function(id: number): any
		table.insert(calls, id)
		local tag = PinballArt.TAGS[id - 1000]
		local holder = Instance.new("Model")
		local m = Instance.new("Model")
		m.Name = tag
		m.Parent = holder
		for _, rec in data.models[tag].meshes do
			if `{tag}.{rec.name}` ~= drop then
				local p = Instance.new("MeshPart")
				p.Name = rec.name
				p.Size = Vector3.new(rec.size[1], rec.size[2], rec.size[3])
				p.CFrame = CFrame.new(500 + rec.at[1], 7 + rec.at[2], rec.at[3])
				if rec.textured and `{tag}.{rec.name}` ~= bare then
					-- the importer brings a textured mesh's picture along (a Lune MeshPart has no TextureID)
					Instance.new("SurfaceAppearance").Parent = p
				end
				p.Parent = m
			end
		end
		return holder
	end,
		calls
end

local function count(model: any): number
	local n = 0
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			n += 1
		end
	end
	return n
end

local function pfOf(index: number): any
	local X, Y, D = Cabinet.origin(index)
	local x, y, z = AlleyLayout.toWorld(PLACE, X, Y, D)
	return CFrame.new(x, y, z)
		* CFrame.Angles(0, PLACE.yaw, 0)
		* CFrame.Angles(0, math.pi, 0)
		* CFrame.Angles(Cabinet.TILT, 0, 0)
end

local function near(a: any, b: any, what: string, tol: number?)
	local d = (a - b).Magnitude
	assert(d <= (tol or MM), `{what}: {string.format("%.2f", d * 280)} mm off`)
end

return function(t)
	local root, machines = baked()
	-- the baked parts' frames, before the loader runs
	local before: { [number]: { [string]: any } } = {}
	local parts0: { [number]: number } = {}
	for index, m in machines do
		local b = {}
		for _, d in m:GetDescendants() do
			if d:IsA("BasePart") and b[d.Name] == nil then
				b[d.Name] = d.CFrame
			end
		end
		before[index] = b
		parts0[index] = count(m)
	end
	local data = uploaded()
	local load, calls = loader(data)
	local report = PinballArt.run(root, { load = load, data = data, env = ENV })

	t.test("each Model is loaded once for the three machines, and every machine takes its art", function()
		t.eq(#calls, #PinballArt.TAGS)
		t.eq(report.machines, 3)
		for i, r in report.reports do
			t.eq(r.failed, nil, `machine {i}`)
			print(
				`  machine {i}: {r.meshes} meshes in, {r.removed} baked parts out, {r.hidden} kept unseen; parts {parts0[i]} -> {count(
					machines[i]
				)}`
			)
		end
	end)

	t.test("every part the client moves is still there, by the name it looks for", function()
		local N = Cabinet.NAMES
		for index, m in machines do
			local tbl = Tables.need(m:GetAttribute("Table"))
			local def = tbl.def
			t.truthy(m:GetAttribute("ArtLoaded"))
			for i = 1, Cabinet.BALLS do
				t.truthy(m:FindFirstChild(`{N.ball}{i}`), `ball {i}`)
			end
			for i = 1, #def.flippers do
				local f = m:FindFirstChild(`{N.flipper}{i}`)
				t.truthy(f and f.PrimaryPart and f.PrimaryPart.Name == "Hub", `flipper {i} of {index}`)
				for _, name in { "Bat", "Tip", "Pin" } do
					t.truthy(f:FindFirstChild(name) and f:FindFirstChild(name):IsA("MeshPart"), `flipper {i} {name}`)
				end
			end
			for i, target in def.targets do
				local name = if target.kind == "drop" then `{N.drop}{i}` else `Standup{i}`
				local p = m:FindFirstChild(name)
				t.truthy(p and p:IsA("MeshPart"), `{name} of {index}`)
			end
			for k = 1, #tbl.c.spinners do
				t.truthy(m:FindFirstChild(`{N.spinner}{k}`):IsA("MeshPart"), `spinner {k}`)
			end
			for i = 1, #def.lamps do
				t.truthy(m:FindFirstChild(`{N.lamp}{i}`), `lamp {i}`)
			end
			for i = 1, #def.bumpers do
				t.truthy(m:FindFirstChild(`{N.bumper}{i}`):IsA("MeshPart"), `bumper cap {i}`)
			end
			for i = 1, #def.slings do
				t.truthy(m:FindFirstChild(`{N.sling}{i}`):IsA("MeshPart"), `sling {i}`)
			end
			local plunger = m:FindFirstChild(N.plunger)
			t.truthy(plunger.PrimaryPart and plunger.PrimaryPart.Name == "Rod" and plunger.PrimaryPart:IsA("MeshPart"))
			t.truthy(plunger:FindFirstChild("Knob"):IsA("MeshPart"))
			t.truthy(m:FindFirstChild("Glass"):IsA("MeshPart"))
			local glass = m:FindFirstChild(N.backglass)
			t.eq(glass.Transparency, 1)
			t.eq(glass:FindFirstChild("Art"), nil)
			for _, name in { "Title", "Score", "Info", "Say", "Best" } do
				t.truthy(glass:FindFirstChild("Display"):FindFirstChild(name), name)
			end
		end
	end)

	t.test("the baked parts the meshes replace are gone; the colliders stay, unseen; all of it visual only", function()
		for index, m in machines do
			for _, d in m:GetChildren() do
				if d:IsA("BasePart") and d.ClassName == "Part" then
					for _, p in PinballArt.REPLACED do
						t.falsy(string.find(d.Name, p), `{d.Name} left on machine {index}`)
					end
				end
			end
			for name in PinballArt.HIDDEN do
				local p = m:FindFirstChild(name)
				t.truthy(p and p.Transparency == 1, `{name} of {index}`)
			end
			t.truthy(m:FindFirstChild("Playfield").CanCollide, "the playfield still holds a body up")
			t.eq(m:FindFirstChild("Playfield"):FindFirstChild("Art"), nil)
			for _, d in m:GetDescendants() do
				if d:IsA("MeshPart") then
					t.truthy(d.Anchored and not d.CanCollide and not d.CanQuery and not d.CanTouch, d.Name)
				end
			end
		end
	end)

	t.test("each mesh lands within 1 mm of the baked part it replaces", function()
		for index, m in machines do
			local tbl = Tables.need(m:GetAttribute("Table"))
			local def, c = tbl.def, tbl.c
			local b = before[index]
			local pf = pfOf(index)
			-- targets: their pivot on the middle of their bottom edge (the bake's bar: 0.12 tall), standing up
			for i, target in def.targets do
				local name = if target.kind == "drop" then `Drop{i}` else `Standup{i}`
				local p = m:FindFirstChild(name)
				near((p.CFrame * p.PivotOffset).Position, (b[name] * CFrame.new(0, -0.06, 0)).Position, name)
				t.truthy(p.CFrame.UpVector:Dot(b[name].UpVector) > 0.9999, `{name} upright`)
			end
			-- the spinner: on its axis, turning about the axis the bake's part does
			for k = 1, #c.spinners do
				local p = m:FindFirstChild(`Spinner{k}`)
				near(p.CFrame.Position, b[`Spinner{k}`].Position, `Spinner{k}`)
				t.truthy(math.abs(p.CFrame.RightVector:Dot(b[`Spinner{k}`].RightVector)) > 0.9999, "spin axis")
			end
			-- the bumper caps, each at its bumper, as wide as the bake's
			for i, bumper in def.bumpers do
				local p = m:FindFirstChild(`BumperCap{i}`)
				near(p.CFrame.Position, b[`BumperCap{i}`].Position, `BumperCap{i}`)
				local want = pf * CFrame.new(bumper.x, 0.18, -bumper.y)
				near(p.CFrame.Position, want.Position, `BumperCap{i} on its bumper`)
				t.truthy(math.abs(p.Size.X - bumper.r * 0.85 * 2) < 0.03, `BumperCap{i} width {p.Size.X}`)
			end
			-- the plunger's knob and rod (the client draws the Model back along its PrimaryPart's Z)
			local plunger = m:FindFirstChild("Plunger")
			near(plunger:FindFirstChild("Knob").CFrame.Position, b.Knob.Position, "Knob")
			near(plunger:FindFirstChild("Rod").CFrame.Position, b.Rod.Position, "Rod")
			t.truthy(
				plunger.PrimaryPart.CFrame.LookVector:Dot(b.Rod.LookVector) > 0.9999,
				"the rod lies along the table"
			)
			-- the flipper meshes about their Hub (the pin on the pivot, the bat along the bake's)
			for i = 1, c.nFlip do
				local f = m:FindFirstChild(`Flipper{i}`)
				near(f:FindFirstChild("Pin").CFrame.Position, f.PrimaryPart.CFrame.Position, `Flipper{i} pin`, 2 * MM)
				local bat = f.PrimaryPart.CFrame:PointToObjectSpace(f:FindFirstChild("Bat").CFrame.Position)
				t.truthy(bat.X > 0.1 and math.abs(bat.Z) < MM, `Flipper{i} bat along the hub's X`)
			end
			-- the board where the baked playfield is, the backglass picture right behind the live text
			near(
				m:FindFirstChild(PinballArt.GROUP):FindFirstChild("Board").CFrame.Position,
				b.Playfield.Position,
				"Board"
			)
			local art = m:FindFirstChild(PinballArt.GROUP):FindFirstChild("BackglassArt")
			local glass = m:FindFirstChild("Backglass")
			local rel = glass.CFrame:PointToObjectSpace(art.CFrame.Position)
			t.truthy(math.abs(rel.X) < MM and math.abs(rel.Y) < MM, `backglass art off centre {rel}`)
			local front = -glass.Size.Z / 2 -- (the face the Display is on, toward the player: the part's -Z)
			t.truthy(rel.Z > front and rel.Z < front + 0.02, `backglass art {rel.Z} not just behind {front}`)
		end
	end)

	t.test("the cabinet, the bumpers and the light strip take the machine's colours", function()
		for _, m in machines do
			local th = Bake.THEMES[m:GetAttribute("Theme")]
			local group = m:FindFirstChild(PinballArt.GROUP)
			local function rgb(p: any): string
				return `{math.floor(p.Color.R * 255 + 0.5)},{math.floor(p.Color.G * 255 + 0.5)},{math.floor(
					p.Color.B * 255 + 0.5
				)}`
			end
			local function want(c: { number }): string
				return table.concat(c, ",")
			end
			t.eq(rgb(group:FindFirstChild("SideWall_L")), want(th.body))
			t.eq(rgb(group:FindFirstChild("LightStrip")), want(th.glow))
			t.eq(group:FindFirstChild("LightStrip").Material, roblox.Enum.Material.Neon)
			t.eq(rgb(group:FindFirstChild("Bumper")), want(th.bumper))
			t.eq(rgb(m:FindFirstChild("BumperCap1")), want(th.cap))
			t.truthy(group:FindFirstChild("SideWall_L").CastShadow)
			t.falsy(group:FindFirstChild("Guides_Metal").CastShadow)
		end
	end)

	t.test("a second run changes nothing", function()
		local n = {}
		for i, m in machines do
			n[i] = count(m)
		end
		local again = PinballArt.run(root, { load = load, data = data, env = ENV })
		for i, m in machines do
			t.eq(count(m), n[i])
			t.eq(again.reports[i].meshes, 0)
		end
	end)

	t.test("with no asset ids nothing changes, and it is said once", function()
		local root2, machines2 = baked()
		local said, spawned = {}, 0
		-- the game's data with every id taken out (as before the upload)
		local bare: any = table.clone(PinballArtData :: any)
		bare.assets = {}
		for tag, a in (PinballArtData :: any).assets do
			local b = table.clone(a)
			b.id = nil
			bare.assets[tag] = b
		end
		local r = PinballArt.start(root2, {
			data = bare,
			print = function(msg: string)
				table.insert(said, msg)
			end,
			spawn = function(_f: () -> ())
				spawned += 1
			end,
		})
		t.eq(r.ready, false)
		t.eq(r.machines, 3)
		t.eq(#said, 1)
		t.truthy(string.find(said[1], "not uploaded yet", 1, true), said[1])
		t.eq(spawned, 0)
		for i, m in machines2 do
			t.eq(count(m), parts0[i])
			t.falsy(m:GetAttribute("ArtLoaded"))
		end
	end)

	t.test("the game's own data has every Model uploaded and approved: the art goes on at boot, once", function()
		for _, tag in PinballArt.TAGS do
			local a = (PinballArtData :: any).assets[tag]
			t.truthy(type(a.id) == "number" and a.id > 0, `{tag} has an asset id`)
			t.eq(a.moderation, "Approved", tag)
		end
		local root5 = baked()
		local spawned = 0
		local r = PinballArt.start(root5, {
			data = PinballArtData,
			print = function(_msg: string) end,
			spawn = function(_f: () -> ())
				spawned += 1
			end,
		})
		t.eq(r.ready, true)
		t.eq(spawned, 1)
	end)

	t.test("a Model missing a mesh leaves every machine as baked", function()
		local root3, machines3 = baked()
		local load3 = loader(data, "acorn.Drop3")
		local r = PinballArt.run(root3, { load = load3, data = data, env = ENV })
		for i, m in machines3 do
			local v = m:GetAttribute("Theme")
			if v == "acorn" then
				t.truthy(r.reports[i].failed and string.find(r.reports[i].failed, "Drop3", 1, true))
				t.eq(count(m), parts0[i])
				t.falsy(m:GetAttribute("ArtLoaded"))
			else
				t.eq(r.reports[i].failed, nil)
			end
		end
	end)

	t.test("a Board that came without its picture leaves the painted board as baked (review)", function()
		local root4, machines4 = baked()
		local r = PinballArt.run(root4, { load = loader(data, nil, "rodent.Board"), data = data, env = ENV })
		for i, m in machines4 do
			t.eq(r.reports[i].failed, nil)
			local painted = m:FindFirstChild("Playfield")
			local group = m:FindFirstChild(PinballArt.GROUP)
			if m:GetAttribute("Theme") == "rodent" then
				t.truthy(painted.Transparency < 1, "the baked board still shows")
				t.truthy(painted:FindFirstChild("Art") ~= nil, "its painted words stay")
				t.eq(group:FindFirstChild("Board"), nil)
			else
				t.eq(painted.Transparency, 1)
				t.truthy(group:FindFirstChild("Board") ~= nil)
			end
		end
	end)

	t.test("the ramps' entrance flaps sit a hair above the board, never on its face (review: flicker)", function()
		for index, m in machines do
			local pf = pfOf(index)
			local n = 0
			for _, d in m:FindFirstChild(PinballArt.GROUP):GetChildren() do
				if d:IsA("BasePart") and d.Name == "Deco_EntranceFlaps" then
					local bottom = pf:PointToObjectSpace(d.CFrame.Position).Y - d.Size.Y / 2
					t.truthy(bottom > 0.0005, `{d.Name} of {index}: bottom {bottom}`)
					n += 1
				end
			end
			if m:GetAttribute("Theme") ~= "acorn" then
				t.truthy(n > 0, `machine {index} has its entrance flaps`)
			end
		end
	end)

	t.test("the manifest matches the pack the models were made to (pinball_data.json)", function()
		local S = 0.28
		local art: any = PinballArtData
		local function rec(tag: string, name: string): any
			for _, r in art.models[tag].meshes do
				if r.name == name then
					return r
				end
			end
			error(`{tag} has no {name}`)
		end
		local function pivotOf(r: any): { number }
			return r.pivot or r.at
		end
		for variant, md in DATA.machines do
			for _, g in md.targets do
				local p = pivotOf(rec(variant, g.name))
				local x, z = (g.a[1] + g.b[1]) / 2, (g.a[2] + g.b[2]) / 2
				t.truthy(
					math.abs(p[1] * S - x) < 0.001 and math.abs(p[3] * S - z) < 0.001 and math.abs(p[2]) < 1e-6,
					g.name
				)
			end
			for _, s in md.spinners do
				local p = pivotOf(rec(variant, s.name))
				t.truthy(
					math.abs(p[1] * S - (s.a[1] + s.b[1]) / 2) < 0.001 and math.abs(p[2] * S - s.axis_height) < 0.001
				)
			end
			for _, s in md.slingshots do
				rec(variant, s.body_name)
				rec(variant, s.rubber_name)
			end
			local board = rec(variant, "Board")
			t.truthy(math.abs(board.size[1] * S - (md.board.x1 - md.board.x0)) < 0.001, "board width")
			t.truthy(math.abs(board.size[3] * S - (md.board.z_front - md.board.z_back)) < 0.001, "board length")
		end
		for name in DATA.cabinet.parts_as_8_corners do
			if name ~= "Backglass" then
				rec("cabinet", name)
			end
		end
		local sh = DATA.shared
		t.truthy(math.abs(art.bumperRadius * S - sh.PopBumper.made_at_radius) < 1e-4)
		t.truthy(math.abs(art.gateHinge * S - sh.Gate.flap_top) < 1e-4)
		t.truthy(math.abs(rec("gate", "Flap").size[1] * S - sh.Gate.flap_length) < 0.001, "gate flap length")
		t.truthy(math.abs(rec("plunger", "Rod").size[3] * S - sh.Plunger.rod_length) < 0.001, "plunger rod length")
		t.truthy(math.abs(rec("plunger", "Knob").size[1] * S - sh.Plunger.knob_size[1]) < 0.001, "knob size")
	end)
end
