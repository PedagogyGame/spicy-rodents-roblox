--!strict
-- tests/isolated/sewer_ambience.luau: cases for tests/unit/sewer_ambience.spec.luau, run in their own Lune process
-- (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- Client/World/SewerAmbience on a fake engine, fed whole runs of the real SquirrelMotor through the pipes' stand-in
-- (tests/lib/SewerStandIn): each frame the motor's point and facing become the held body's root, and the render step
-- runs. A fake bake (Workspace.Sewers: a model per space, a lamp part with a PointLight at every lamp anchor, a beam
-- under every light grate, a flowing water texture) stands where lane S1's will be. Lighting carries the D7 preset
-- (Shared/World/LightingPreset.apply). What the cases show: the words on screen at the right moments; the inside look
-- comes in and goes; exactly that space's lights are on while inside and every light is back as baked after; the
-- reverb is set and put back; Lighting is never touched; the cues fire in the right places and never outside; the
-- alligator; a body handed over mid-pipe; stop() leaves nothing behind. Nothing here shows how it looks or sounds.
-- Interface: return function(t) (the spec shape)
local roblox = require("@lune/roblox")
local Data = require("@shared/Data")
local LightingPreset = require("@shared/World/LightingPreset")
local SewerLayout = require("@shared/World/SewerLayout")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local SewerAmbience = require("@client/World/SewerAmbience")
local SquirrelController = require("@client/Controllers/Squirrel")
local BakedWorld = require("@tests/lib/BakedWorld")
local FakeEngine = require("@tests/lib/FakeEngine")
local SewerStandIn = require("@tests/lib/SewerStandIn")

local HIP = 0.6

type Mouth = SewerLayout.Mouth
type Pose = { x: number, y: number, z: number, yaw: number, routeId: number? }

local layout = SewerLayout.default() :: SewerLayout.Layout
local world: any = nil
local function motorWorld(): any
	if world == nil then
		world = SewerStandIn.world(layout):motorWorld(Data.default())
	end
	return world
end

-- A run of the real motor: standing on mouth `fromId` facing in, E, then W held with the view toward `toId` until it
-- has been out on the street `after` frames. Every frame's point and facing.
local runs: { [string]: { Pose } } = {}
local function run(fromId: string, toId: string, after: number?): { Pose }
	local key = `{fromId}>{toId}>{after or 0}`
	if runs[key] then
		return runs[key]
	end
	local w = motorWorld()
	local a, b = layout.mouth(fromId) :: Mouth, layout.mouth(toId) :: Mouth
	local s = SquirrelMotor.new(a.x, a.y, a.z)
	s.yaw = math.atan2(-a.out.x, -a.out.z)
	local cam = BakedWorld.cameraYawToward(b.x - a.x, b.z - a.z)
	local poses: { Pose } = {}
	-- a second on the grate first (nothing pressed), so the prompt is seen before E
	for _ = 1, 60 do
		table.insert(poses, { x = s.x, y = s.y, z = s.z, yaw = s.yaw })
	end
	local out = 0
	BakedWorld.drive(w, s, 60 * 40, function(f: number): SquirrelMotor.Input
		return BakedWorld.keys(cam, if f == 1 then { grab = true } else { fw = 1 })
	end, {
		stop = function(st: SquirrelMotor.State, f: number): boolean
			table.insert(poses, { x = st.x, y = st.y, z = st.z, yaw = st.yaw, routeId = st.routeId })
			if f > 2 and st.routeId == nil then
				out += 1
			end
			return out > (after or 60)
		end,
	})
	runs[key] = poses
	return poses
end

type Rig = {
	handle: SewerAmbience.Handle,
	body: any,
	root: any,
	species: string,
	toasts: { string },
	lighting: any,
	sound: any,
	sewers: any,
	lights: { [string]: { any } }, -- by space
	water: any,
	gui: any,
}

-- the fake bake: a model per space; a lamp part with a PointLight (off, as baked) at every lamp anchor and a
-- SpotLight under every light grate; P1's first lamp baked with shadows on (it must come back so); a water texture
local function bake(r: Rig)
	local sewers = FakeEngine.new("Folder", "Sewers")
	sewers.Parent = workspace
	r.sewers = sewers
	local models: { [string]: any } = {}
	for _, p in layout.pipes do
		local m = FakeEngine.model(p.id, roblox.CFrame.new(0, 0, 0), sewers)
		m:SetAttribute("Space", p.space)
		models[p.space] = m
		r.lights[p.space] = {}
	end
	for i, a in layout.anchors do
		if a.kind == "lamp" or a.kind == "lightGrate" then
			local part = FakeEngine.part(`Lamp{i}`, roblox.CFrame.new(a.x, a.y, a.z), models[a.space])
			local light = FakeEngine.new(if a.kind == "lamp" then "PointLight" else "SpotLight", "Light")
			light.Enabled = false
			light.Shadows = #r.lights[a.space] == 0 and a.space == "sewer.crossroads"
			light.Parent = part
			table.insert(r.lights[a.space], light)
		end
	end
	local channel = FakeEngine.part("Water", roblox.CFrame.new(0, -10.9, 0), models["sewer.crossroads"])
	local tex = FakeEngine.new("Texture", "Ripple")
	tex.StudsPerTileU = 8
	tex.OffsetStudsU = 0
	tex:SetAttribute("Flow", 1.5)
	tex.Parent = channel
	r.water = tex
	-- a lamp of the town outside the bake: never touched
	local street = FakeEngine.part("StreetLamp", roblox.CFrame.new(0, 10, 0), workspace)
	local streetLight = FakeEngine.new("PointLight", "Light")
	streetLight.Enabled = true
	streetLight.Shadows = true
	streetLight.Parent = street
end

local function rig(species: string?): Rig
	local r: Rig = {
		handle = nil :: any,
		body = nil,
		root = nil,
		species = species or "squirrel",
		toasts = {},
		lighting = (game :: any):GetService("Lighting"),
		sound = (game :: any):GetService("SoundService"),
		sewers = nil,
		lights = {},
		water = nil,
		gui = nil,
	}
	LightingPreset.apply(r.lighting)
	r.sound.AmbientReverb = roblox.Enum.ReverbType.NoReverb
	bake(r)
	local body = FakeEngine.model("Squirrel", roblox.CFrame.new(0, 0, 0), workspace)
	local root = FakeEngine.part("Root", roblox.CFrame.new(0, HIP, 0), body)
	body.PrimaryPart = root
	body:SetAttribute("HipHeight", HIP)
	body:SetAttribute("Species", r.species)
	r.body, r.root = body, root
	r.handle = SewerAmbience.start({
		current = function(): any
			return r.body
		end,
		state = function(): { [string]: any }
			return { species = r.species }
		end,
		toast = function(text: string)
			table.insert(r.toasts, text)
		end,
		layout = layout,
		seed = 7,
	})
	r.gui = (game :: any):GetService("Players").LocalPlayer:FindFirstChild("PlayerGui"):FindFirstChild("SewerHud")
	return r
end

local function pose(r: Rig, p: Pose)
	-- the root as Controllers/Squirrel writes it: the motor's yaw turned to Roblox's, the hip over the feet
	r.root.CFrame = roblox.CFrame.new(p.x, p.y + HIP, p.z) * roblox.CFrame.Angles(0, p.yaw + math.pi, 0)
	FakeEngine.renderStep(1 / 60)
end

local function lit(list: { any }): number
	local n = 0
	for _, l in list do
		if l.Enabled then
			n += 1
		end
	end
	return n
end

local function shadowed(list: { any }): number
	local n = 0
	for _, l in list do
		if l.Shadows then
			n += 1
		end
	end
	return n
end

-- every property of an instance and its children (a fake instance's plain fields), to compare before and after
local function snapshot(inst: any): { [string]: string }
	local out: { [string]: string } = {}
	local function walk(node: any, path: string)
		for k, v in node do
			if type(k) == "string" and string.sub(k, 1, 1) ~= "_" then
				out[path .. "." .. k] = tostring(v)
			end
		end
		for name, v in rawget(node, "_attrs") do
			out[path .. "@" .. name] = tostring(v)
		end
		for _, c in node:GetChildren() do
			walk(c, path .. "/" .. c.Name)
		end
	end
	walk(inst, inst.Name)
	return out
end

local function sameSnapshot(t: any, a: { [string]: string }, b: { [string]: string }, what: string)
	for k, v in a do
		t.eq(b[k], v, `{what}: {k}`)
	end
	for k, v in b do
		t.eq(a[k], v, `{what}: {k} appeared`)
	end
end

return function(t)
	t.test("P1 corner to corner: the prompt, the look, the lights, the reverb, the cues, and all put back", function()
		FakeEngine.with(function()
			local r = rig()
			local h = r.handle
			local poses = run("P1.NW", "P1.SE", 60)
			local said: { [string]: number } = {}
			local placeSeen, maxLevel = nil, 0
			local insideFrames, crossroadsLit, otherLit, maxShadows = 0, 0, 0, 0
			local cameraGrade: any = nil
			for _, p in poses do
				pose(r, p)
				local prompt = h.prompt()
				if prompt then
					said[prompt] = (said[prompt] or 0) + 1
				end
				maxLevel = math.max(maxLevel, h.level())
				if h.space() then
					insideFrames += 1
					placeSeen = h.place()
					crossroadsLit = math.max(crossroadsLit, lit(r.lights["sewer.crossroads"]))
					otherLit = math.max(otherLit, lit(r.lights["sewer.culvert"]) + lit(r.lights["sewer.bowllane"]))
					local pointLights = {}
					for _, l in r.lights["sewer.crossroads"] do
						if l.ClassName == "PointLight" then
							table.insert(pointLights, l)
						end
					end
					maxShadows = math.max(maxShadows, shadowed(pointLights))
					t.eq(r.sound.AmbientReverb, roblox.Enum.ReverbType.SewerPipe, "the pipe's reverb inside")
					cameraGrade = workspace.CurrentCamera:FindFirstChild("SewerGrade")
				end
			end
			t.truthy((said["E: down the drain"] or 0) >= 30, "standing on the grate facing in: E: down the drain")
			t.truthy((said["W: climb out"] or 0) >= 10, "the top of the far shaft: W: climb out")
			t.truthy(insideFrames > 200, `inside for {insideFrames} frames`)
			t.eq(placeSeen, "UNDERGROUND · STORM DRAIN 1 CROSSROADS")
			t.eq(crossroadsLit, #r.lights["sewer.crossroads"], "every light of the crossroads on inside")
			t.eq(otherLit, 0, "no other drain's lights")
			t.eq(maxShadows, 2, "shadows on the two nearest lamps only")
			t.truthy(maxLevel > 0.9, "the inside look came in")
			t.truthy(cameraGrade ~= nil and cameraGrade.Enabled, "the grade is on the camera")
			local placeLabel = r.gui:FindFirstChild("Place")
			-- out on the street: a second on (the linger and the ease-out pass)
			for _ = 1, 120 do
				pose(r, poses[#poses])
			end
			t.eq(h.space(), nil)
			t.eq(h.level(), 0, "the look has gone")
			t.eq(r.sound.AmbientReverb, roblox.Enum.ReverbType.NoReverb, "the reverb put back")
			t.eq(lit(r.lights["sewer.crossroads"]), 0, "the lamps off again")
			t.truthy(r.lights["sewer.crossroads"][1].Shadows, "a lamp baked with shadows has them again")
			t.eq(shadowed(r.lights["sewer.crossroads"]), 1, "and only that one")
			t.truthy(not cameraGrade.Enabled, "the grade is off")
			t.truthy(not workspace.CurrentCamera:FindFirstChild("SewerFocus").Enabled, "the focus is off")
			t.truthy(not placeLabel.Visible, "the place name is gone")
			local c = h.counts()
			t.eq(c["sewer.grateIn"], 1)
			t.eq(c["sewer.grateOut"], 1)
			t.truthy((c["sewer.rung"] or 0) >= 15, `rungs down and up two shafts: {c["sewer.rung"]}`)
			t.truthy((c["sewer.footEcho"] or 0) >= 20, `footfalls along two 35-stud arms: {c["sewer.footEcho"]}`)
			t.truthy((c["sewer.drip"] or 0) >= 1, "a drip")
			t.eq(c["sewer.trickle"], 1, "the channel's trickle, once")
			t.eq(c["sewer.riverHum"], nil, "no river under the crossroads")
			t.eq(c["sewer.streetMurmur"], 2, "the street heard at each end")
			t.eq(c["sewer.hiss"], nil)
			for cue, on in h.loops() do
				t.truthy(not on, `{cue} stopped`)
			end
			t.truthy(r.water.OffsetStudsU > 0, "the water flowed")
			for _, l in r.sewers:GetDescendants() do
				if l.ClassName == "SpotLight" then
					t.truthy(not l.Enabled, "the grate beams off again")
				end
			end
			h.stop()
		end)
	end)

	t.test("Lighting is never touched (the D7 preset holds), and nothing is parented to it", function()
		FakeEngine.with(function()
			local r = rig()
			local before = snapshot(r.lighting)
			local poses = run("P2.W", "P2.E", 90)
			local sawInside = false
			for _, p in poses do
				pose(r, p)
				sawInside = sawInside or r.handle.space() == "sewer.culvert"
			end
			t.truthy(sawInside)
			sameSnapshot(t, before, snapshot(r.lighting), "Lighting")
			r.handle.stop()
			sameSnapshot(t, before, snapshot(r.lighting), "Lighting after stop")
		end)
	end)

	t.test("the culvert: its own lamps, the river's hum, no trickle; the street lamp never touched", function()
		FakeEngine.with(function()
			local r = rig()
			local street = workspace:FindFirstChild("StreetLamp"):FindFirstChild("Light")
			local most = 0
			for _, p in run("P2.E", "P2.W") do
				pose(r, p)
				if r.handle.space() then
					t.eq(lit(r.lights["sewer.crossroads"]) + lit(r.lights["sewer.bowllane"]), 0)
					most = math.max(most, lit(r.lights["sewer.culvert"]))
					t.eq(r.handle.place(), "UNDERGROUND · OLD RIVER CULVERT 1911")
				end
				t.truthy(street.Enabled and street.Shadows, "the town's lamp")
			end
			t.eq(most, #r.lights["sewer.culvert"])
			local c = r.handle.counts()
			t.eq(c["sewer.riverHum"], 1)
			t.eq(c["sewer.trickle"], nil)
			t.truthy((c["sewer.rung"] or 0) >= 50, `two 35-stud shafts: {c["sewer.rung"]} rungs`)
			r.handle.stop()
		end)
	end)

	t.test("outside, nothing fires: running over the pipes and round the grates on the street", function()
		FakeEngine.with(function()
			local r = rig()
			-- across P1's crossing and along P3's line at street level, then circling a grate
			for i = 0, 600 do
				local f = i / 600
				pose(r, { x = -40 + 80 * f, y = 0, z = -30 + 60 * f, yaw = 0.7 })
			end
			for i = 0, 360 do
				local a = i * math.pi / 90
				pose(r, { x = 24.65 + 2.2 * math.sin(a), y = 0, z = -24.65 + 2.2 * math.cos(a), yaw = a })
			end
			t.eq(next(r.handle.counts()), nil, "no cue")
			t.eq(r.handle.level(), 0, "no look")
			t.eq(lit(r.lights["sewer.crossroads"]), 0, "no lamp")
			t.eq(r.sound.AmbientReverb, roblox.Enum.ReverbType.NoReverb)
			t.eq(workspace.CurrentCamera:FindFirstChild("SewerGrade"), nil, "no effect made")
			r.handle.stop()
		end)
	end)

	t.test("a person on a grate is told nothing, and a person's body is never 'inside'", function()
		FakeEngine.with(function()
			local r = rig("human")
			local m = layout.mouth("P1.NW") :: Mouth
			for _ = 1, 30 do
				pose(r, { x = m.x, y = m.y, z = m.z, yaw = math.atan2(-m.out.x, -m.out.z) })
			end
			t.eq(r.handle.prompt(), nil)
			t.eq(r.gui:FindFirstChild("Prompt").Visible, false)
			pose(r, { x = 0, y = -10.6, z = 0, yaw = 0 })
			t.eq(r.handle.space(), nil)
			r.handle.stop()
		end)
	end)

	t.test("the prompt on screen follows the body: E on the grate, gone off it", function()
		FakeEngine.with(function()
			local r = rig()
			local m = layout.mouth("P3.S") :: Mouth
			local prompt = r.gui:FindFirstChild("Prompt")
			pose(r, { x = m.x, y = m.y, z = m.z, yaw = math.atan2(-m.out.x, -m.out.z) })
			t.eq(prompt.Text, "E: down the drain")
			t.truthy(prompt.Visible)
			pose(r, { x = m.x, y = m.y, z = m.z, yaw = math.atan2(m.out.x, m.out.z) })
			t.truthy(string.find(prompt.Text, "then E: down the drain", 1, true) ~= nil, prompt.Text)
			pose(r, { x = m.x + 20, y = m.y, z = m.z, yaw = 0 })
			t.eq(prompt.Visible, false)
			r.handle.stop()
		end)
	end)

	t.test("the controller's refusals pass through the filter: a drain's words inside, unchanged outside", function()
		FakeEngine.with(function()
			local r = rig()
			local noRoom = SquirrelController.feedback({}, { { kind = "hint", reason = "noRoom" } }, true) :: string
			t.eq(r.handle.filter(noRoom), noRoom, "outside")
			pose(r, { x = 0, y = -10.6, z = 3, yaw = 0 })
			t.truthy(r.handle.space() ~= nil, "in the chamber")
			local said = r.handle.filter(noRoom)
			t.truthy(said ~= noRoom and string.find(said, "down here", 1, true) ~= nil, said)
			r.handle.stop()
		end)
	end)

	t.test("the small alligator: still underground until the idle warning, one hiss and its line", function()
		FakeEngine.with(function()
			local r = rig()
			local seconds = SewerAmbience.C.hissAfter
			local p = { x = 0, y = -10.6, z = 3, yaw = 0 }
			-- 30 frames a second of game time is enough to judge "still"
			for _ = 1, math.ceil(seconds * 30) + 30 do
				r.root.CFrame = roblox.CFrame.new(p.x, p.y + HIP, p.z)
				FakeEngine.renderStep(1 / 30)
			end
			t.eq(r.handle.counts()["sewer.hiss"], 1, "one hiss")
			t.eq(r.toasts[#r.toasts], SewerAmbience.HISS_LINE)
			-- moving resets it, and it comes again after another wait
			pose(r, { x = 0, y = -10.6, z = 6, yaw = 0 })
			for _ = 1, math.ceil(seconds * 30) - 60 do
				r.root.CFrame = roblox.CFrame.new(0, -10.6 + HIP, 6)
				FakeEngine.renderStep(1 / 30)
			end
			t.eq(r.handle.counts()["sewer.hiss"], 1, "not before the wait is over again")
			r.handle.stop()
		end)
	end)

	t.test("handed over mid-pipe (released, or another body): everything goes back at once", function()
		FakeEngine.with(function()
			local r = rig()
			local poses = run("P3.S", "P3.N")
			local mid = 0
			for i, p in poses do
				pose(r, p)
				if r.handle.space() and i > #poses / 2 then
					mid = i
					break
				end
			end
			t.truthy(mid > 0, "got half way")
			t.truthy(lit(r.lights["sewer.bowllane"]) > 0)
			r.body = nil
			FakeEngine.renderStep(1 / 60)
			t.eq(r.handle.space(), nil)
			t.eq(lit(r.lights["sewer.bowllane"]), 0)
			t.eq(r.sound.AmbientReverb, roblox.Enum.ReverbType.NoReverb)
			t.eq(r.handle.prompt(), nil)
			for _ = 1, 120 do
				FakeEngine.renderStep(1 / 60)
			end
			t.eq(r.handle.level(), 0)
			r.handle.stop()
		end)
	end)

	t.test("stop() inside: the lights, the reverb, the effects and the words all go", function()
		FakeEngine.with(function()
			local r = rig()
			pose(r, { x = 0, y = -10.6, z = 3, yaw = 0 })
			t.truthy(r.handle.space() ~= nil)
			r.handle.stop()
			t.eq(lit(r.lights["sewer.crossroads"]), 0)
			t.eq(r.sound.AmbientReverb, roblox.Enum.ReverbType.NoReverb)
			t.eq(workspace.CurrentCamera:FindFirstChild("SewerGrade"), nil)
			t.eq(workspace.CurrentCamera:FindFirstChild("SewerFocus"), nil)
			t.eq(
				(game :: any):GetService("Players").LocalPlayer:FindFirstChild("PlayerGui"):FindFirstChild("SewerHud"),
				nil
			)
			local n = FakeEngine.renderStep
			n(1 / 60) -- nothing is bound any more
			t.eq(r.handle.space(), nil)
		end)
	end)
end
