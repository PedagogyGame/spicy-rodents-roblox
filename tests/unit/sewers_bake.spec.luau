--!strict
-- The storm drains' bake (tools/bake/sewers.luau -> build/Sewers.rbxm; tools/bake/sewers/Build, built here in memory
-- by the same call) against the layout it is built from (Shared/World/SewerLayout) and the owner's modules
-- (data/art/sewer_modules.json):
--   the same bytes every time; within the part budget; every light baked off; each pipe streamed whole; the sound
--   cue points named, without sounds, inside their pipes
--   the TerrainCarve folder is the layout's shaft columns, on the 4-stud grid
--   the squirrel's clearance: the body's section (tests/lib/BakedWorld.clearance) along every route meets no part
--   of the bake but the grate it slips through; nothing stands where a launch out of a mouth starts
--   the owner's modules: every slot turned so the route runs a lane his meshes leave clear (the export's exact
--   triangle test, recorded in the manifest), on the module's walkway, inside its 12 studs
--   the mouths: an opening of at least 1.7 x 1.5, the street over it level with the street round it, the top of
--   every carve column covered (the town's road, kerb and sidewalk parts or the mouth's frame: build/Town.rbxm)
--   the real motor through the real bake: E at each street mouth, down, along, up and out on its feet
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Data = require("@shared/Data")
local Enclosure = require("@shared/Routes/Enclosure")
local SewerLayout = require("@shared/World/SewerLayout")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local BakedWorld = require("@tests/lib/BakedWorld")
local Build = require("../../tools/bake/sewers/Build")
local Cues = require("../../tools/bake/sewers/Cues")
local Mouth = require("../../tools/bake/sewers/Mouth")
local Pipe = require("../../tools/bake/sewers/Pipe")

type State = SquirrelMotor.State

local BUDGET = 700 -- parts (the survey's budget, the eight carve columns and the art slots' lining included)

local function isGrate(p: BakedWorld.Part): boolean
	return string.find(p.path, ".Grate.", 1, true) ~= nil
end

return function(t)
	local data = Data.default()
	local layout = SewerLayout.default() :: SewerLayout.Layout
	local art = serde.decode("json", fs.readFile("data/art/sewer_modules.json"))
	local root, report = Build.build(roblox, layout, art)
	local baked = BakedWorld.fromModel(root)
	local w = baked:motorWorld(data)
	local reg = w.registry

	t.test("the same bytes every time; within the budget; every light off; each pipe streamed whole", function()
		local again = Build.build(roblox, layout, art)
		t.truthy(roblox.serializeModel({ root }) == roblox.serializeModel({ again }), "the bake is deterministic")
		print(`      {report.parts} parts, {report.slots} art slots, {report.lamps} lamps`)
		t.truthy(report.parts <= BUDGET, `{report.parts} parts (budget {BUDGET})`)
		local lights = 0
		for _, d in root:GetDescendants() do
			if d:IsA("Light") then
				lights += 1
				t.eq(d.Enabled, false, `{d:GetFullName()} is baked off`)
				local holder = d.Parent
				t.truthy(holder:GetAttribute("Space") ~= nil, `{d:GetFullName()}: its space is named`)
			end
		end
		t.truthy(lights >= report.lamps)
		local lampAnchors = 0
		for _, a in layout.anchors do
			if a.kind == "lamp" then
				lampAnchors += 1
			end
		end
		t.eq(report.lamps, lampAnchors, "a light at every lamp anchor")
		for _, pipe in layout.pipes do
			local m = root:FindFirstChild(pipe.id)
			t.truthy(m ~= nil and m:IsA("Model"), pipe.id)
			t.eq(m.ModelStreamingMode, roblox.Enum.ModelStreamingMode.Atomic)
			t.eq(m:GetAttribute("Space"), pipe.space)
			for _, name in { "Shell", "Lining", "Art", "Mouths", "Dressing" } do
				t.truthy(m:FindFirstChild(name) ~= nil, `{pipe.id}.{name}`)
			end
		end
	end)

	t.test("sound cue points: named, empty until audio exists, each inside its pipe (or at its mouth)", function()
		local known: { [string]: boolean } = {}
		for _, n in Cues.NAMES do
			known[n] = true
		end
		local seen: { [string]: number } = {}
		local n = 0
		for _, d in root:GetDescendants() do
			if d:IsA("Attachment") and d:GetAttribute("Cue") ~= nil then
				n += 1
				local name = d:GetAttribute("Cue")
				t.truthy(known[name], `{name} is a cue`)
				t.eq(d:GetAttribute("SoundId"), "", `{name}: no sound yet`)
				seen[name] = (seen[name] or 0) + 1
				local p = (d.Parent.CFrame * d.CFrame).Position
				local space = d:GetAttribute("Space")
				if name ~= "sewer.grateIn" and name ~= "sewer.grateOut" and name ~= "sewer.streetMurmur" then
					t.eq(layout.contains(p.X, p.Y, p.Z), space, `{name} at {p} is inside {space}`)
				else
					local m = layout.nearestMouth(p.X, p.Z, 0.5)
					t.truthy(m ~= nil and m.space == space, `{name} at a mouth of {space}`)
				end
			end
		end
		t.eq(n, report.cues)
		for _, name in Cues.NAMES do
			t.truthy((seen[name] or 0) > 0, `a {name} point`)
		end
	end)

	t.test("TerrainCarve: the layout's shaft columns, on the 4-stud grid", function()
		local folder = root:FindFirstChild("TerrainCarve")
		local want = {}
		for _, b in layout.carveBoxes() do
			if b.kind == "shaft" then
				table.insert(want, b)
			end
		end
		t.eq(#baked.carves, #want)
		for _, c in baked.carves do
			local found = false
			for _, b in want do
				if
					math.abs(c.x0 - b.x0) < 1e-3
					and math.abs(c.x1 - b.x1) < 1e-3
					and math.abs(c.z0 - b.z0) < 1e-3
					and math.abs(c.z1 - b.z1) < 1e-3
					and math.abs(c.y0 - b.y0) < 1e-3
				then
					found = true
				end
			end
			t.truthy(found, `carve {c.x0},{c.z0}`)
			for _, v in { c.x0, c.x1, c.z0, c.z1, c.y0 } do
				t.near(v / 4, math.floor(v / 4 + 0.5), 1e-3, "on the grid")
			end
		end
		for _, d in folder:GetChildren() do
			t.eq(d.Transparency, 1)
			t.eq(d.CanCollide, false)
		end
	end)

	t.test(
		"the squirrel's clearance: along every route the body meets nothing but the grate it slips through",
		function()
			for _, r in layout.routes do
				local route = reg:get(r.id) :: any
				local hit = {}
				for _, b in
					BakedWorld.clearance(baked, reg, route, {
						filter = function(p)
							return (p.collide or p.visible) and not isGrate(p)
						end,
					})
				do
					table.insert(hit, `{b.path} t {string.format("%.3f..%.3f", b.t0, b.t1)}`)
				end
				t.eq(#hit, 0, `route {r.id}: {table.concat(hit, "; ")}`)
				for _, mb in
					BakedWorld.mouthClearance(baked, reg, route, function(p)
						return p.collide and not isGrate(p)
					end)
				do
					local names = {}
					for _, p in mb.parts do
						table.insert(names, p.path)
					end
					t.eq(#mb.parts, 0, `route {r.id} {mb.mouth}: a launch out starts in {table.concat(names, ", ")}`)
				end
			end
		end
	)

	t.test("the owner's modules: each slot runs the route in a lane his meshes leave clear, on his walkway", function()
		local slots = 0
		for _, pipe in layout.pipes do
			for _, s in (root:FindFirstChild(pipe.id) :: any).Art:GetChildren() do
				slots += 1
				local variant = s:GetAttribute("ArtModule")
				local entry = art.modules[variant]
				t.truthy(entry ~= nil, `{pipe.id}.{s.Name}: module {variant}`)
				t.truthy(
					entry.assetId ~= nil and tostring(s:GetAttribute("ArtAsset")) == tostring(entry.assetId),
					"its id"
				)
				local pivot = s:GetAttribute("ArtPivot")
				t.truthy(pivot ~= nil, "a pivot")
				if variant == "marker" then
					continue
				end
				-- the route samples inside the module's 12 studs, in the module's frame
				local inside = 0
				for _, id in pipe.routes do
					local route = reg:get(id) :: any
					for k = 0, 600 do
						local p = reg:pointAt(route, k / 600)
						local q = pivot:PointToObjectSpace(roblox.Vector3.new(p.x, p.y, p.z))
						if math.abs(q.Z) <= 6 and math.abs(q.X) <= 6 and math.abs(q.Y) < 1.0 then
							inside += 1
							t.truthy(math.abs(q.Y) < 0.1, `{pipe.id}.{s.Name}: on the walkway ({q.Y})`)
							-- which lane the body is in, and that his meshes leave it clear
							local lane = nil
							for name, l in entry.lanes do
								local lo, hi = l.box[1], l.box[2]
								local cx, cz = (lo[1] + hi[1]) / 2, (lo[3] + hi[3]) / 2
								local alongZ = (hi[3] - lo[3]) > (hi[1] - lo[1])
								local off = if alongZ then math.abs(q.X - cx) else math.abs(q.Z - cz)
								if off < 0.06 then
									lane = { name, l }
								end
							end
							if variant == "junction" and math.abs(q.X) < 2.45 and math.abs(q.Z) < 2.45 then
								-- in the middle of the junction the body turns from one lane to the other
								if lane == nil then
									continue
								end
							end
							t.truthy(
								lane ~= nil,
								`{pipe.id}.{s.Name} ({variant}): the route at x {q.X} z {q.Z} runs no lane`
							)
							if lane then
								t.truthy(lane[2].clear, `{pipe.id}.{s.Name}: lane {lane[1]} is clear of his meshes`)
							end
						end
					end
				end
				t.truthy(inside > 10, `{pipe.id}.{s.Name}: the route runs through it ({inside})`)
			end
		end
		t.eq(slots, report.slots)
	end)

	t.test("the mouths: the opening, the street over it, every carve column's top covered", function()
		t.truthy(fs.isFile("build/Town.rbxm"), "build/Town.rbxm (lune run tools/bake/main.luau)")
		local town = BakedWorld.load("build/Town.rbxm")
		for _, m in layout.mouths do
			local o = m.opening
			local short, long = math.min(o.x1 - o.x0, o.z1 - o.z0), math.max(o.x1 - o.x0, o.z1 - o.z0)
			t.truthy(short >= Enclosure.BODY.height - 0.25 and long >= Enclosure.BODY.width, `{m.id}: {long} x {short}`)
			local top = Mouth.plane(m)
			t.near(baked.groundAt(m.x, m.z, m.y + 1), top, 0.02, `{m.id}: the squirrel stands on the grate`)
			t.truthy(math.abs(top - m.y) <= 0.15, `{m.id}: level with the street ({top} vs {m.y})`)
			-- every point of the column's top: something to stand on or look at, at the street
			local c = m.column
			local open = 0
			local x = c.x0 + 0.1
			while x < c.x1 do
				local z = c.z0 + 0.1
				while z < c.z1 do
					-- (the grate fills the opening: its edge, to float precision, counts as the grate's)
					local e = 0.02
					local inHole = x > o.x0 - e and x < o.x1 + e and z > o.z0 - e and z < o.z1 + e
					if not inHole then
						local function covers(world: BakedWorld.World): boolean
							local tt = world.raycast(x, m.y + 2, z, 0, -2.8, 0, function(p)
								return p.visible
							end)
							return tt ~= nil
						end
						if not covers(baked) and not covers(town) then
							open += 1
						end
					end
					z += 0.25
				end
				x += 0.25
			end
			t.eq(open, 0, `{m.id}: {open} points of the carved column's top show the hole`)
		end
		-- the light grate on the boulevard lies on the road
		local road = Pipe.ROAD_TOP.P3
		for _, a in layout.anchors do
			if a.kind == "lightGrate" and a.pipe == "P3" then
				t.near(town.groundAt(a.x, a.z, 20), road, 0.03, "the boulevard at P3's light grate")
			end
		end
	end)

	t.test("the real motor through the real bake: E at each street mouth, out on its feet at the other", function()
		local runs = {
			{ "P1.NW", "P1.SE" },
			{ "P1.SE", "P1.NW" },
			{ "P1.NE", "P1.SW" },
			{ "P1.SW", "P1.NE" },
			{ "P2.W", "P2.E" },
			{ "P2.E", "P2.W" },
			{ "P3.S", "P3.N" },
			{ "P3.N", "P3.S" },
		}
		for _, run in runs do
			local a, b = layout.mouth(run[1]) :: SewerLayout.Mouth, layout.mouth(run[2]) :: SewerLayout.Mouth
			local s = SquirrelMotor.new(a.x, baked.groundAt(a.x, a.z, a.y + 1), a.z)
			s.yaw = math.atan2(-a.out.x, -a.out.z)
			local cam = BakedWorld.cameraYawToward(b.x - a.x, b.z - a.z)
			local trace = BakedWorld.drive(w, s, 60 * 40, function(f: number): SquirrelMotor.Input
				return BakedWorld.keys(cam, if f == 1 then { grab = true } else { fw = 1 })
			end, {
				validator = true,
				stop = function(st: State, f: number)
					return f > 2 and st.routeId == nil
				end,
			})
			t.eq(BakedWorld.count(trace, "enter"), 1, `{run[1]}: E goes in`)
			t.eq(BakedWorld.count(trace, "emerge"), 1, `{run[1]} -> {run[2]}: out`)
			t.eq(trace.violations, 0, `{run[1]}: the server accepts every frame`)
			t.truthy(s.grounded and s.routeId == nil, `{run[2]}: on its feet`)
			t.truthy(math.sqrt((s.x - b.x) ^ 2 + (s.z - b.z) ^ 2) < 1.0, `{run[2]}: at the mouth`)
			-- and on along the street (a quay's cover stands 0.14 over the quay: one small step up)
			local on = BakedWorld.drive(w, s, 30, function(): SquirrelMotor.Input
				return BakedWorld.keys(cam, { fw = 1 })
			end, { validator = true })
			t.eq(next(on.routes), nil, `{run[2]}: not pulled back in`)
			t.eq(on.violations, 0)
			t.truthy(s.grounded and math.abs(s.y - baked.groundAt(s.x, s.z, s.y + 1)) < 0.05, `{run[2]}: on the street`)
			print(string.format("      %s -> %s: %.2f s", run[1], run[2], trace.seconds))
		end
	end)
end
