--!strict
-- tests/isolated/sewers_play.luau: the case for tests/unit/sewers_play.spec.luau, run in its own Lune process
-- (tests/lib/Isolated) because it installs fake engine globals (tests/lib/FakeEngine).
-- The storm drains end to end, the three sewer lanes joined as Boot/Game and Client/Main join them: the Spicy Rodent
-- stands on P1's north-west grate in front of a policeman and four people, presses E, runs W through the crossing's
-- chamber and climbs out at the south-east verge. One frame drives everything:
--   the real SquirrelMotor on the real sewer bake (tools/bake/sewers/Build, in memory, through tests/lib/BakedWorld)
--   the server: the real town AI (AI/TownAI) with World/SewerService started as Boot/Game starts it (the carve on
--     a recording terrain, after the terrain write); the held rodent's root fed to the AI every frame
--   the client: World/SewerAmbience started as Client/Main starts it, the held body posed from the motor, the
--     render step run; Workspace.Sewers is a fake-engine copy of the real bake's lights (each light at its
--     attachment's world point, with the bake's Space attributes and pipe models), so S3's lamp lookup is held to
--     what S1 really bakes
-- What it shows: "E or W: down the drain" on the grate before E; in with E, through the chamber, out on its feet at the
-- far corner; the crossroads' baked lights on while inside and every light back as baked after; "W: climb out" at
-- the top of the far shaft; the people who saw it go say so, the officer watches the NW grate for sewer.stakeoutSecs
-- and says "It went down the drain!", nobody spots the rodent while it is under the street, and the officer never
-- goes toward the corner it came out of (the police lose sight of it at the drain).
-- Interface: return function(t) (the spec shape)
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local serde = require("@lune/serde")
local Data = require("@shared/Data")
local SewerLayout = require("@shared/World/SewerLayout")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local Tunables = require("@shared/Config/Tunables")
local Common = require("@server/Actors/Brains/Common")
local TownAI = require("@server/AI/TownAI")
local SewerService = require("@server/World/SewerService")
local SewerAmbience = require("@client/World/SewerAmbience")
local BakedWorld = require("@tests/lib/BakedWorld")
local FakeEngine = require("@tests/lib/FakeEngine")
local Build = require("../../tools/bake/sewers/Build")

local DT = 1 / 60
local HIP = 0.6 -- the client body's hip over the feet (as tests/isolated/sewer_ambience)

type Mouth = SewerLayout.Mouth

-- Workspace.Sewers on the fake engine: every light of the real bake, at its world point, under a model named after
-- its pipe, the holder carrying the bake's Space attribute; returns the lights by space and as baked
local function mirrorLights(bakeRoot: any): (any, { [string]: { any } }, { [any]: { enabled: boolean, shadows: any } })
	local root = FakeEngine.new("Model", "Sewers")
	root.Parent = workspace
	local bySpace: { [string]: { any } } = {}
	local baked: { [any]: { enabled: boolean, shadows: any } } = {}
	local models: { [string]: any } = {}
	for _, d in bakeRoot:GetDescendants() do
		if d:IsA("PointLight") or d:IsA("SpotLight") or d:IsA("SurfaceLight") then
			local holder = d.Parent
			local cf = if holder:IsA("Attachment") then holder.Parent.CFrame * holder.CFrame else holder.CFrame
			-- the pipe model this light is under (Workspace.Sewers.<P>)
			local node = holder
			while node.Parent and node.Parent ~= bakeRoot do
				node = node.Parent
			end
			local model = models[node.Name]
			if model == nil then
				model = FakeEngine.model(node.Name, roblox.CFrame.new(0, 0, 0), root)
				models[node.Name] = model
			end
			local space = holder:GetAttribute("Space")
			local part = FakeEngine.part(holder.Name, roblox.CFrame.new(cf.Position), model)
			part:SetAttribute("Space", space)
			local light = FakeEngine.new(d.ClassName, d.Name)
			light.Enabled = d.Enabled
			local okS, shadows = pcall(function()
				return (d :: any).Shadows
			end)
			if okS and not d:IsA("SurfaceLight") then
				light.Shadows = shadows
			end
			light.Parent = part
			bySpace[space] = bySpace[space] or {}
			table.insert(bySpace[space], light)
			baked[light] = { enabled = light.Enabled, shadows = light.Shadows }
		end
	end
	return root, bySpace, baked
end

local function lit(list: { any }?): number
	local n = 0
	for _, l in list or {} do
		if l.Enabled then
			n += 1
		end
	end
	return n
end

return function(t)
	t.test("down the drain at P1's NW grate, through the chamber, up at the SE verge; the police lose it", function()
		FakeEngine.with(function()
			local data = Data.default()
			local layout = SewerLayout.default() :: SewerLayout.Layout
			local art = serde.decode("json", fs.readFile("data/art/sewer_modules.json"))
			local bakeRoot = Build.build(roblox, layout, art)
			local motorWorld = BakedWorld.fromModel(bakeRoot):motorWorld(data)
			local nw = layout.mouth("P1.NW") :: Mouth
			local se = layout.mouth("P1.SE") :: Mouth
			local chamber = layout.chambers[1]

			-- the server, as Boot/Game: the terrain is written, then the drains start (the carve, the cover)
			local terrainCalls: { string } = {}
			local terrain = FakeEngine.new("Terrain", "Terrain")
			rawset(terrain, "WriteVoxels", function()
				table.insert(terrainCalls, "write")
			end)
			rawset(terrain, "FillBlock", function(_self: any, _cf: any, _size: any, material: any)
				t.eq(material, Enum.Material.Air, "the carve fills with air")
				table.insert(terrainCalls, "fill")
			end)
			rawset(workspace, "Terrain", terrain)
			terrain:WriteVoxels()
			local town = TownAI.build({ data = data, seed = 1, humans = 90, squirrels = 3, deer = 0, fox = 0 })
			TownAI.setFocus(town, function()
				return { { x = nw.x, z = nw.z } }
			end)
			local attrs: { [number]: { [string]: any } } = {}
			local svc = SewerService.start({
				world = town,
				layout = layout,
				rand = function()
					return 0.25
				end,
				setAttr = function(id: number, name: string, value: any)
					attrs[id] = attrs[id] or {}
					attrs[id][name] = value
				end,
			})
			t.eq(terrainCalls[1], "write", "the terrain write first")
			t.eq(#terrainCalls, 1 + #layout.carveBoxes(), "then one carve per box")
			local events: { TownAI.Event } = {}
			TownAI.listen(town, function(ev: TownAI.Event)
				table.insert(events, ev)
			end)

			-- the rodent is the player's (out of the AI); a policeman 12 studs west of the grate and four people
			-- by it, all looking at it
			local rodent: any, officer: any = nil, nil
			local walkers = {}
			for _, a in town.actors do
				local kind = if town.brains[a.id] then town.brains[a.id].kind else ""
				if a.variant == "spicy" then
					rodent = a
				elseif kind == "Officer" and officer == nil then
					officer = a
				elseif kind == "Pedestrian" and a.post ~= "rider" and #walkers < 4 then
					table.insert(walkers, a)
				end
			end
			t.truthy(rodent ~= nil and officer ~= nil and #walkers == 4, "the rodent, an officer and four people")
			local function put(a: any, x: number, z: number)
				TownAI.suspend(town, a.id)
				TownAI.resume(town, a.id, x, town.ctx.groundAt(x, z) + a.hip, z, Common.yawOf(nw.x - x, nw.z - z))
			end
			put(officer, nw.x - 12, nw.z + 2)
			for i, w in walkers do
				put(w, nw.x + 4 + i, nw.z + 3)
			end
			TownAI.suspend(town, rodent.id)

			-- the client, as Client/Main: the ambience over the held body
			local _, lights, baked = mirrorLights(bakeRoot)
			t.truthy(#(lights["sewer.crossroads"] or {}) > 0, "the bake's crossroads lights carry their space")
			local sound = (game :: any):GetService("SoundService")
			sound.AmbientReverb = roblox.Enum.ReverbType.NoReverb
			local body = FakeEngine.model("SpicyRodent", roblox.CFrame.new(0, 0, 0), workspace)
			local root = FakeEngine.part("Root", roblox.CFrame.new(0, HIP, 0), body)
			body.PrimaryPart = root
			body:SetAttribute("HipHeight", HIP)
			body:SetAttribute("Species", "rodent")
			body:SetAttribute("Variant", "spicy")
			local handle = SewerAmbience.start({
				current = function(): any
					return body
				end,
				state = function(): { [string]: any }
					return { species = "rodent" }
				end,
				layout = layout,
				seed = 7,
			})

			-- one frame of the whole game: the client's body and render step, the server's AI with the held root
			local said: { [string]: number } = {}
			local spotsUnder, insideFrames, crossroadsLit, otherLit = 0, 0, 0, 0
			local nearestChamber = math.huge
			local s = SquirrelMotor.new(nw.x, motorWorld.groundAt(nw.x, nw.z, nw.y + 1), nw.z)
			s.yaw = math.atan2(-nw.out.x, -nw.out.z)
			local function frame()
				root.CFrame = roblox.CFrame.new(s.x, s.y + HIP, s.z) * roblox.CFrame.Angles(0, s.yaw + math.pi, 0)
				FakeEngine.renderStep(DT)
				local prompt = handle.prompt()
				if prompt then
					said[prompt] = (said[prompt] or 0) + 1
				end
				if handle.space() then
					insideFrames += 1
					crossroadsLit = math.max(crossroadsLit, lit(lights["sewer.crossroads"]))
					otherLit = math.max(otherLit, lit(lights["sewer.culvert"]) + lit(lights["sewer.bowllane"]))
				end
				rodent.x, rodent.y, rodent.z, rodent.speed = s.x, s.y + rodent.hip, s.z, 0
				local before = #events
				TownAI.stepFrame(town, DT)
				for i = before + 1, #events do
					local ev = events[i]
					if ev.kind == "spotted" and ev.other == rodent.id and svc:underground(rodent.id) then
						spotsUnder += 1
					end
				end
				if svc:underground(rodent.id) then
					nearestChamber = math.min(
						nearestChamber,
						math.sqrt((s.x - chamber.crossing.x) ^ 2 + (s.z - chamber.crossing.z) ^ 2)
					)
				end
			end

			-- a second on the grate, nothing pressed: the prompt, and the people see it there
			for _ = 1, 60 do
				frame()
			end
			t.truthy((said[SewerAmbience.PROMPT.down] or 0) >= 30, "on the grate facing in: E or W: down the drain")
			t.eq(svc:underground(rodent.id), nil, "on the grate it is still in the street")
			-- E, then W held with the view toward the far corner, until it has stood out on the street 30 frames
			local cam = BakedWorld.cameraYawToward(se.x - nw.x, se.z - nw.z)
			local outFrames = 0
			local outAt: { number }? = nil
			local trace = BakedWorld.drive(motorWorld, s, 60 * 20, function(f: number): SquirrelMotor.Input
				return BakedWorld.keys(cam, if f == 1 then { grab = true } else { fw = 1 })
			end, {
				validator = true,
				stop = function(st: SquirrelMotor.State, f: number): boolean
					frame()
					if f > 2 and st.routeId == nil then
						outFrames += 1
						outAt = outAt or { st.x, st.z }
					end
					return outFrames > 30
				end,
			})
			t.eq(BakedWorld.count(trace, "enter"), 1, "E goes in")
			t.eq(BakedWorld.count(trace, "emerge"), 1, "and out once")
			t.eq(trace.violations, 0, "the server accepts every frame")
			t.truthy(nearestChamber < 2, `through the chamber ({nearestChamber} st from the crossing)`)
			t.truthy(s.grounded and s.routeId == nil, "on its feet, running on along the street")
			local o = outAt or { math.huge, math.huge }
			t.truthy(math.sqrt((o[1] - se.x) ^ 2 + (o[2] - se.z) ^ 2) < 1, "out at the south-east grate")
			t.eq(svc:underground(rodent.id), nil, "back in the open")
			t.truthy((said["W: climb out"] or 0) >= 5, "the top of the far shaft: W: climb out")
			t.truthy(insideFrames > 200, `inside for {insideFrames} frames`)
			t.truthy(
				crossroadsLit >= 3 and crossroadsLit <= SewerAmbience.C.maxLit,
				`the crossroads lights round the body on inside ({crossroadsLit} of {#lights["sewer.crossroads"]})`
			)
			t.eq(otherLit, 0, "no other drain's lights")
			t.eq(spotsUnder, 0, "nobody spotted it under the street")
			-- the linger runs out: every light as baked, the reverb back
			for _ = 1, 60 do
				frame()
			end
			for light, was in baked do
				t.eq(light.Enabled, was.enabled, "the light as baked")
				t.eq(light.Shadows, was.shadows, "the shadows as baked")
			end
			t.eq(sound.AmbientReverb, roblox.Enum.ReverbType.NoReverb, "the reverb back")

			-- the server's account: who saw it go, the officer sent to the NW grate
			local report = svc:lost()[1]
			t.truthy(report ~= nil, "a report of the rodent going down")
			t.eq(report.mouth, "P1.NW")
			t.truthy(table.find(report.witnesses, officer.id) ~= nil, "the officer saw it go")
			t.deepEq(report.officers, { officer.id })
			-- the officer watches the grate it went down for the stakeout, says so, and never goes after it
			local secs = Tunables.get("sewer.stakeoutSecs")
			local saidAt: number? = nil
			local nearestSe, nearestNw = math.huge, math.huge
			local t0 = town.now
			while town.now - t0 < secs + 8 do
				frame()
				if saidAt == nil and (attrs[officer.id] or {}).Say == "It went down the drain!" then
					saidAt = town.now
				end
				nearestSe = math.min(nearestSe, math.sqrt((officer.x - se.x) ^ 2 + (officer.z - se.z) ^ 2))
				nearestNw = math.min(nearestNw, math.sqrt((officer.x - nw.x) ^ 2 + (officer.z - nw.z) ^ 2))
			end
			print(
				string.format(
					"      run %.2f s; officer: nearest the NW grate %.1f st, the SE corner %.1f st",
					trace.seconds,
					nearestNw,
					nearestSe
				)
			)
			t.truthy(saidAt ~= nil, "the officer: It went down the drain!")
			t.truthy(nearestNw < SewerService.C.standOff + 1, "the officer stood over the NW grate")
			t.truthy(nearestSe > 40, "and never went toward the corner it came out of")
			handle.stop()
			svc:stop()
		end)
	end)
end
