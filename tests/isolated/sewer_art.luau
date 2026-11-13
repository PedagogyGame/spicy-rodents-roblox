--!strict
-- tests/isolated/sewer_art.luau: cases for tests/unit/sewer_art.spec.luau, run in their own Lune process
-- (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- Client/World/SewerArt on a fake engine over the real bake's art slots (tools/bake/sewers/Build: every slot's
-- ArtModule, ArtPivot, ArtTris, ArtMeshes, ArtCheck, ArtCheckAt copied onto fake models) and a lining part per run,
-- fed a whole run of the real SquirrelMotor through the culvert (tests/lib/SewerStandIn). ReplicatedStorage.SewerArt
-- holds each module as an ideal import would arrive: a Model whose pivot is the module's origin, a part per mesh of
-- the manifest (data/art/sewer_modules.json) at its centre. What the cases show: only the slots round the body are
-- drawn, within the budget, moving along with it; the lining is hidden on this client while the art is in and comes
-- back after; a module not loaded yet, or one that arrives turned or mirrored, leaves the drain in plain parts, with
-- one warning. Nothing here shows how it looks.
-- Interface: return function(t) (the spec shape)
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Data = require("@shared/Data")
local SewerLayout = require("@shared/World/SewerLayout")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local SewerArt = require("@client/World/SewerArt")
local BakedWorld = require("@tests/lib/BakedWorld")
local FakeEngine = require("@tests/lib/FakeEngine")
local SewerStandIn = require("@tests/lib/SewerStandIn")
local Build = require("../../tools/bake/sewers/Build")

local HIP = 0.6

type Mouth = SewerLayout.Mouth

local layout = SewerLayout.default() :: SewerLayout.Layout
local art = serde.decode("json", fs.readFile("data/art/sewer_modules.json"))
local bakedRoot = (Build.build(roblox, layout, art))

-- the culvert end to end with the real motor: every frame's feet
local function runP2(): { { number } }
	local w = SewerStandIn.world(layout):motorWorld(Data.default())
	local a, b = layout.mouth("P2.W") :: Mouth, layout.mouth("P2.E") :: Mouth
	local s = SquirrelMotor.new(a.x, a.y, a.z)
	s.yaw = math.atan2(-a.out.x, -a.out.z)
	local cam = BakedWorld.cameraYawToward(b.x - a.x, b.z - a.z)
	local out, poses = 0, {}
	BakedWorld.drive(w, s, 60 * 40, function(f: number): SquirrelMotor.Input
		return BakedWorld.keys(cam, if f == 1 then { grab = true } else { fw = 1 })
	end, {
		stop = function(st: SquirrelMotor.State, f: number): boolean
			table.insert(poses, { st.x, st.y, st.z })
			if f > 2 and st.routeId == nil then
				out += 1
			end
			return out > 120
		end,
	})
	return poses
end

type Rig = {
	handle: SewerArt.Handle,
	root: any,
	store: any,
	linings: { [string]: { any } },
	warned: { string },
	sewers: any,
}

-- the fake Workspace.Sewers: the bake's slots, a lining part per pipe; the store with each module as imported
local function rig(mirror: string?): Rig
	local sewers = FakeEngine.new("Folder", "Sewers")
	sewers.Parent = workspace
	local linings: { [string]: { any } } = {}
	for _, pipe in bakedRoot:GetChildren() do
		local space = pipe:GetAttribute("Space")
		if type(space) ~= "string" then
			continue
		end
		local fp = FakeEngine.model(pipe.Name, roblox.CFrame.new(0, 0, 0), sewers)
		fp:SetAttribute("Space", space)
		local fart = FakeEngine.new("Folder", "Art")
		fart.Parent = fp
		for _, slot in (pipe:FindFirstChild("Art") :: any):GetChildren() do
			local m = FakeEngine.model(slot.Name, roblox.CFrame.new(0, 0, 0), fart)
			for k, v in slot:GetAttributes() do
				m:SetAttribute(k, v)
			end
		end
		local lining = FakeEngine.model("Lining", roblox.CFrame.new(0, 0, 0), fp)
		linings[space] = {}
		for i = 1, 3 do
			local p = FakeEngine.part(`Wall{i}`, roblox.CFrame.new(0, 0, 0), lining)
			p.LocalTransparencyModifier = 0
			table.insert(linings[space], p)
		end
	end
	local store = FakeEngine.new("Folder", "SewerArt")
	for name, entry in art.modules do
		local model = FakeEngine.model(name, roblox.CFrame.new(0, 0, 0), store)
		for _, mesh in entry.meshes do
			local c = mesh.centre
			local x = if mirror == name then -c[1] else c[1]
			-- a mirrored import also flips along the run (as a turned one would)
			local z = if mirror == name then -c[3] else c[3]
			local part = FakeEngine.new("MeshPart", mesh.name)
			part.CFrame = roblox.CFrame.new(x, c[2], z)
			part.Parent = model
		end
	end
	local body = FakeEngine.model("Squirrel", roblox.CFrame.new(0, 0, 0), workspace)
	local root = FakeEngine.part("Root", roblox.CFrame.new(0, HIP, 0), body)
	body.PrimaryPart = root
	body:SetAttribute("HipHeight", HIP)
	local r = { root = root, store = store, linings = linings, warned = {}, sewers = sewers } :: any
	r.handle = SewerArt.start({
		current = function(): any
			return body
		end,
		layout = layout,
		root = sewers,
		store = store,
	})
	return r :: Rig
end

local function at(r: Rig, x: number, y: number, z: number)
	r.root.CFrame = roblox.CFrame.new(x, y + HIP, z)
	r.handle.step(SewerArt.C.every)
end

local function copies(): { any }
	local f = workspace:FindFirstChild("SewerArtLocal")
	return if f then f:GetChildren() else {}
end

return function(t)
	local poses = runP2()

	t.test("the culvert end to end: only the modules round the body, within the budget, moving along", function()
		FakeEngine.with(function()
			local r = rig()
			local C = SewerArt.C
			local most, inside, hiddenFrames = 0, 0, 0
			local seen: { [string]: boolean } = {}
			for k, p in poses do
				-- half way: drain 1 streams out (the slot list is renumbered on the next rescan, the copies are not)
				if k == math.floor(#poses / 2) then
					r.sewers:FindFirstChild("P1"):Destroy()
				end
				at(r, p[1], p[2], p[3])
				local list = copies()
				local here: { [string]: boolean } = {}
				for _, c in list do
					local key = tostring(c:GetPivot().Position)
					t.truthy(not here[key], "one copy per slot")
					here[key] = true
				end
				most = math.max(most, #list)
				local tris, meshes = 0, 0
				for _, c in list do
					local q = c:GetPivot().Position
					local d = math.sqrt((q.X - p[1]) ^ 2 + (q.Y - p[2]) ^ 2 + (q.Z - p[3]) ^ 2)
					t.truthy(d <= C.radius + 1e-6, `a module {d} studs from the body`)
					seen[tostring(q)] = true
					local entry = art.modules[c.Name]
					tris += entry.tris
					meshes += #entry.meshes
				end
				t.truthy(tris <= C.budgetTris and meshes <= C.budgetMeshes, `{tris} triangles, {meshes} meshes`)
				if layout.contains(p[1], p[2], p[3]) == "sewer.culvert" then
					inside += 1
					if r.handle.hidden() then
						hiddenFrames += 1
						for _, part in r.linings["sewer.culvert"] do
							t.eq(part.LocalTransparencyModifier, 1, "the lining hidden here")
						end
					end
				end
				for _, space in { "sewer.crossroads", "sewer.bowllane" } do
					for _, part in r.linings[space] do
						t.eq(part.LocalTransparencyModifier, 0, `{space}'s lining untouched`)
					end
				end
			end
			local slotsInP2 = #(bakedRoot:FindFirstChild("P2") :: any):FindFirstChild("Art"):GetChildren()
			local n = 0
			for _ in seen do
				n += 1
			end
			print(`      the culvert: at most {most} modules at once; {n} of its {slotsInP2} slots drawn along the run`)
			t.truthy(most >= 3 and most <= C.maxSlots, `{most} at once`)
			t.truthy(n >= slotsInP2 - 2, "the window moved the whole way")
			t.truthy(hiddenFrames >= inside * 0.95, `the lining hidden while inside ({hiddenFrames} of {inside})`)
			-- out on the quay a while: nothing left, the lining back
			local last = poses[#poses]
			for _ = 1, 8 do
				at(r, last[1] + 6, last[2], last[3])
			end
			t.eq(#copies(), 0, "no module left drawn")
			for _, part in r.linings["sewer.culvert"] do
				t.eq(part.LocalTransparencyModifier, 0, "the lining back")
			end
			r.handle.stop()
			t.eq(workspace:FindFirstChild("SewerArtLocal"), nil)
		end)
	end)

	t.test("a module turned or mirrored on import: that drain stays in plain parts, one warning", function()
		FakeEngine.with(function()
			local r = rig("dry")
			local warnings = 0
			-- selene: allow(deprecated)
			local env = getfenv(0) :: any
			local realWarn = env.warn
			env.warn = function(_text: string)
				warnings += 1
			end
			for i = 1, #poses, 20 do
				local p = poses[i]
				at(r, p[1], p[2], p[3])
				t.eq(#copies(), 0, "nothing drawn")
				for _, part in r.linings["sewer.culvert"] do
					t.eq(part.LocalTransparencyModifier, 0, "the lining stays")
				end
			end
			env.warn = realWarn
			t.truthy(r.handle.bad().dry, "the dry module is known bad")
			t.eq(warnings, 1, "one warning")
			r.handle.stop()
		end)
	end)

	t.test("before the modules arrive (or if they never do): the lining, nothing drawn", function()
		FakeEngine.with(function()
			local r = rig()
			r.store:FindFirstChild("dryPlain"):Destroy()
			local p = poses[math.floor(#poses / 2)]
			at(r, p[1], p[2], p[3])
			t.eq(#copies(), 0)
			t.eq(r.handle.hidden(), false)
			r.handle.stop()
		end)
	end)
end
