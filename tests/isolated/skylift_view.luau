--!strict
-- tests/isolated/skylift_view.luau: cases for tests/unit/skylift_view.spec.luau, run in their own Lune process
-- (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- Client/Rides/SkyLiftView and Client/Rides/Telescope on the fake engine (the sky-lift plan's lane-5 proof):
-- six cabins cloned from a CabinTemplate built here to the bake's interface (tools/bake/skylift/Cabin's header:
-- Origin, Seats/Seat1..4 with EyeSocket, Doors/DoorFore and DoorAft with SlideZ, Light with a PointLight,
-- NumberFront / NumberBack), placed every frame from the shared clock. Each cabin's seat is the server's seat
-- (Shared/Rides/SkyLift.seat) at the same clock within 0.05; no cabin moves more than the line's speed times
-- the frame (with the smoothing's SLEW) through both stations with a jittery server clock; each seat's eye is
-- inside its cabin and at least 4.5 above the floor; doors, riders, night lights, the turning wheels; stop().
-- The telescope: in by its prompt, the view and its limits, out by E, Q, walking off; the words.
-- Interface: return function(t) (the spec shape)
local SkyLift = require("@shared/Rides/SkyLift")
local AnimationDriver = require("@client/Animation/AnimationDriver")
local SkyLiftView = require("@client/Rides/SkyLiftView")
local SkyLiftService = require("@server/Rides/SkyLiftService")
local Telescope = require("@client/Rides/Telescope")
local FakeEngine = require("@tests/lib/FakeEngine")
local roblox = require("@lune/roblox")

local CF = roblox.CFrame
local V3 = roblox.Vector3
local Key = roblox.Enum.KeyCode
local Kind = roblox.Enum.UserInputType
local EPOCH = 5000
local DT = 1 / 60

FakeEngine.classes({ parts = { "Seat" } })
FakeEngine.events({ "PromptTriggered" })

type Rig = { now: number, moves: number, f4: any, tpl: any? }

-- the fake workspace's engine calls the view uses
local function engineCalls(rig: Rig)
	local ws = FakeEngine.workspace()
	rawset(ws, "BulkMoveTo", function(_self: any, parts: { any }, cframes: { any }, _mode: any)
		assert(#parts == #cframes, "BulkMoveTo: as many frames as parts")
		rig.moves += 1
		for i, p in parts do
			rawset(p, "CFrame", cframes[i])
		end
	end)
	rawset(ws, "GetServerTimeNow", function(_self: any): number
		return rig.now
	end)
	game:GetService("ReplicatedStorage"):SetAttribute(SkyLift.EPOCH_ATTRIBUTE, EPOCH)
end

local function part(name: string, cf: any, size: any, parent: any, class: string?): any
	local p = FakeEngine.new(class or "Part", name)
	rawset(p, "CFrame", cf)
	rawset(p, "Size", size)
	p.Anchored = true
	p.Parent = parent
	return p
end

-- A CabinTemplate to the bake's interface, its origin at `at` (yaw 0), as tools/bake/skylift/Cabin lays it out.
local function makeTemplate(parent: any, at: any): any
	local m = FakeEngine.model("CabinTemplate", at, nil)
	m:SetAttribute("Template", true)
	local origin = part("Origin", at, V3.new(0.2, 0.2, 0.2), m)
	m.PrimaryPart = origin
	local function box(p: any, name: string, x: number, y: number, z: number, sx: number, sy: number, sz: number)
		return part(name, at * CF.new(x, y, z), V3.new(sx, sy, sz), p)
	end
	box(m, "Floor", 0, -0.25, 0, 6, 0.5, 8)
	box(m, "LowLeft", -2.92, 0.7, 0, 0.15, 1.4, 7.7)
	box(m, "Roof", 0, 6.8, 0, 6, 0.7, 7.8)
	box(m, "Grip", 0, SkyLift.HANG, 0, 1.1, 1.1, 1.1)
	local light = box(m, "Light", 0, 6.47, 0, 1, 0.06, 2.4)
	light.Material = roblox.Enum.Material.Neon
	local lamp = FakeEngine.new("PointLight", "PointLight")
	lamp.Enabled = false
	lamp.Parent = light
	for _, n in { { "NumberFront", -3.96 }, { "NumberBack", 3.96 } } do
		local plate = box(m, n[1] :: string, 0, 7, n[2] :: number, 1.4, 0.6, 0.08)
		local gui = FakeEngine.new("SurfaceGui", "Front")
		gui.Parent = plate
		local label = FakeEngine.new("TextLabel", "Number")
		label.Text = "1"
		label.Parent = gui
	end
	local doors = FakeEngine.new("Folder", "Doors")
	doors.Parent = m
	for _, d in { { "DoorFore", -0.75, -1.5 }, { "DoorAft", 0.75, 1.5 } } do
		local leaf = FakeEngine.model(d[1] :: string, at, doors)
		leaf:SetAttribute("SlideZ", d[3])
		box(leaf, "Glass", 2.92, 3.8, d[2] :: number, 0.08, 4.8, 1.5)
		box(leaf, "Kick", 2.93, 0.72, d[2] :: number, 0.14, 1.35, 1.5)
	end
	local seats = FakeEngine.new("Folder", "Seats")
	seats.Parent = m
	for k = 1, SkyLift.SEATS do
		local L = SkyLift.SEAT_LOCAL[k]
		local s = part(
			`Seat{k}`,
			at * CF.new(L[1], L[2] - 0.16, L[3]) * CF.Angles(0, L[4], 0),
			V3.new(2.5, 0.32, 1.2),
			seats,
			"Seat"
		)
		s:SetAttribute("Seat", k)
		local eye = FakeEngine.new("Attachment", "EyeSocket")
		eye.CFrame = CF.new(0, 0.16 + SkyLift.EYE_ABOVE_SEAT, 0)
		eye.Parent = s
	end
	m.Parent = parent
	return m
end

local function newRig(): Rig
	local rig: Rig = { now = EPOCH, moves = 0, f4 = nil, tpl = nil }
	engineCalls(rig)
	local exp = FakeEngine.new("Folder", "Expansion")
	exp.Parent = FakeEngine.workspace()
	local f4 = FakeEngine.new("Folder", "F4")
	f4.Parent = exp
	rig.f4 = f4
	local wheel = SkyLift.stations().base.wheel
	rig.tpl = makeTemplate(f4, CF.new(wheel.x, wheel.y - 60, wheel.z))
	return rig
end

local function cabins(): { any }
	local folder = FakeEngine.workspace():FindFirstChild(SkyLiftView.FOLDER)
	return if folder then folder:GetChildren() else {}
end

local function cabinNamed(i: number): any
	local folder = FakeEngine.workspace():FindFirstChild(SkyLiftView.FOLDER)
	return folder and folder:FindFirstChild(`Cabin{i}`)
end

local function descendant(root: any, name: string): any
	for _, d in root:GetDescendants() do
		if d.Name == name then
			return d
		end
	end
	return nil
end

-- the frame of cabin i at the view's clock: a world point into the cabin's own frame
local function toCabin(i: number, t: number, p: any): any
	local x, y, z, yaw = SkyLift.cabin(i, t)
	return (CF.new(x, y, z) * CF.Angles(0, yaw, 0)):PointToObjectSpace(p)
end

-- run frames until the view's clock reaches about t (snapping there first)
local function goTo(rig: Rig, t: number)
	rig.now = EPOCH + t
	FakeEngine.renderStep(DT)
end

local function telescopeModel(parent: any): (any, any)
	-- the bake's telescope (tools/bake/lookout): lens toward the town (here -Z), eyepiece behind, tilted 6 degrees
	local m = FakeEngine.model("Telescope", CF.new(100, 116, 200), parent)
	-- (as the bake places them: the parts tipped, their centres on the venue's grid: lens 0.18 under the eyepiece)
	local tilt = CF.Angles(math.rad(-6), 0, 0)
	part("Head", CF.new(100, 120.75, 200) * tilt, V3.new(1.5, 0.95, 1.6), m)
	for _, dx in { -0.36, 0.36 } do
		part("Lens", CF.new(100 + dx, 120.68, 199.15) * tilt, V3.new(0.5, 0.5, 0.2), m)
		part("Eyepiece", CF.new(100 + dx, 120.86, 200.9) * tilt, V3.new(0.32, 0.32, 0.3), m)
	end
	local column = part("Column", CF.new(100, 117.9, 200), V3.new(0.45, 3.6, 0.45), m)
	local prompt = FakeEngine.new("ProximityPrompt", "TelescopePrompt")
	prompt.Enabled = true
	prompt:SetAttribute("Door", true)
	prompt.Parent = column
	return m, prompt
end

local function person(name: string, at: any, parent: any): any
	local body = FakeEngine.model(name, at, parent)
	local root = part("HumanoidRootPart", at, V3.new(2, 2, 1), body)
	body.PrimaryPart = root
	return body
end

return function(t)
	t.test("six cabins from the template, numbered 1 to 6; none and no error before the template arrives", function()
		FakeEngine.with(function()
			local rig = newRig()
			local tpl = rig.tpl
			tpl.Parent = nil -- not streamed in yet
			local stop = SkyLiftView.start()
			t.eq(FakeEngine.bound(), 1, "one render step bound")
			for _ = 1, 30 do
				FakeEngine.renderStep(DT)
			end
			t.eq(#cabins(), 0, "no cabins without a template")
			tpl.Parent = rig.f4
			for _ = 1, 70 do
				FakeEngine.renderStep(DT)
			end
			t.eq(#cabins(), SkyLift.CABINS, "six cabins once it is there")
			for i = 1, SkyLift.CABINS do
				local c = cabinNamed(i)
				t.truthy(c, `cabin {i}`)
				t.eq(c:GetAttribute("Cabin"), i)
				t.eq(c:GetAttribute("Template"), nil, "a clone is not a template")
				local labels = 0
				for _, d in c:GetDescendants() do
					if d.Name == "Number" then
						t.eq(d.Text, tostring(i), "number plate")
						labels += 1
					end
				end
				t.eq(labels, 2, "both number plates")
				t.truthy(SkyLiftView.cabinModel(i) == c)
			end
			t.eq(#tpl:GetChildren() > 0, true, "the template itself is left alone")
			stop()
			t.eq(FakeEngine.bound(), 0, "stop unbinds")
			t.eq(FakeEngine.workspace():FindFirstChild(SkyLiftView.FOLDER), nil, "stop removes the cabins")
		end)
	end)

	t.test("every seat of every cabin is the server's seat at the same clock, within 0.05, at 300 times", function()
		FakeEngine.with(function()
			local rig = newRig()
			local stop = SkyLiftView.start()
			FakeEngine.renderStep(DT)
			t.eq(#cabins(), SkyLift.CABINS)
			local P = SkyLift.period()
			local worst, worstYaw = 0, 0
			for j = 0, 299 do
				goTo(rig, -400 + j * (P * 7.37 / 300)) -- every gap over SNAP: the clock takes the server's
				local tc = SkyLiftView.clock() :: number
				t.near(tc, -400 + j * (P * 7.37 / 300), 1e-6, "clock")
				for i = 1, SkyLift.CABINS do
					local holder = SkyLiftView.seatModel(i, 1)
					t.truthy(holder, "seat model")
					for k = 1, SkyLift.SEATS do
						local seat = SkyLiftView.seatModel(i, k).PrimaryPart
						local top = seat.CFrame * CF.new(0, 0.16, 0)
						local x, y, z, yaw = SkyLift.seat(i, k, tc)
						worst = math.max(worst, (top.Position - V3.new(x, y, z)).Magnitude)
						local look = seat.CFrame.LookVector
						local want = V3.new(-math.sin(yaw), 0, -math.cos(yaw))
						worstYaw = math.max(worstYaw, (look - want).Magnitude)
					end
				end
			end
			t.truthy(worst <= 0.05, `seat off by {worst}`)
			t.truthy(worstYaw <= 0.01, `seat facing off by {worstYaw}`)
			stop()
		end)
	end)

	t.test(
		"each seat's eye is inside its cabin and at least 4.5 above the floor; the seat model holds that eye only",
		function()
			FakeEngine.with(function()
				local rig = newRig()
				local stop = SkyLiftView.start()
				for j = 0, 40 do
					goTo(rig, j * 13.7)
					local tc = SkyLiftView.clock() :: number
					for i = 1, SkyLift.CABINS do
						for k = 1, SkyLift.SEATS do
							local holder = SkyLiftView.seatModel(i, k)
							local eyes = 0
							local eye: any = nil
							for _, d in holder:GetDescendants() do
								if d.Name == "EyeSocket" then
									eyes += 1
									eye = d
								end
							end
							t.eq(eyes, 1, "one EyeSocket in the seat model")
							local w = (eye.Parent.CFrame * eye.CFrame).Position
							local l = toCabin(i, tc, w)
							t.truthy(math.abs(l.X) <= SkyLift.CABIN_WIDTH / 2, `eye x {l.X}`)
							t.truthy(math.abs(l.Z) <= SkyLift.CABIN_LENGTH / 2, `eye z {l.Z}`)
							t.truthy(l.Y >= 4.5 - 1e-4, `eye only {l.Y} over the floor`)
							t.truthy(l.Y <= SkyLift.CABIN_HEIGHT - SkyLift.CABIN_BELOW, "eye under the roof")
							local cf = SkyLiftView.eye(i, k) :: any
							t.truthy((cf.Position - w).Magnitude < 0.05, "eye() agrees with the socket")
						end
					end
				end
				stop()
			end)
		end
	)

	t.test(
		"no cabin moves more than the line's speed x dt between frames, a whole lap, with a jittery server clock",
		function()
			FakeEngine.with(function()
				local rig = newRig()
				local stop = SkyLiftView.start()
				local seed = 7
				local function wobble(): number -- 0..1, a small LCG (no Random on the fake engine)
					seed = (seed * 1103515245 + 12345) % 2147483648
					return seed / 2147483648
				end
				local trueT = 3.3
				rig.now = EPOCH + trueT
				FakeEngine.renderStep(DT)
				local last: { any } = {}
				for i = 1, SkyLift.CABINS do
					last[i] = SkyLiftView.cabinModel(i):FindFirstChild("Origin").Position
				end
				local limit = SkyLift.LINE_SPEED * DT * (1 + SkyLiftView.SLEW) * 1.0005 + 1e-4
				local worst, drift = 0, 0
				local stations = { base = 0, summit = 0 }
				local frames = math.ceil(SkyLift.period() / DT) + 60
				for _ = 1, frames do
					trueT += DT
					rig.now = EPOCH + trueT + (wobble() - 0.5) * 0.06 -- the estimate wobbles 30 ms
					FakeEngine.renderStep(DT)
					local tc = SkyLiftView.clock() :: number
					drift = math.max(drift, math.abs(tc - trueT))
					for i = 1, SkyLift.CABINS do
						local p = SkyLiftView.cabinModel(i):FindFirstChild("Origin").Position
						worst = math.max(worst, (p - last[i]).Magnitude)
						last[i] = p
						local _, _, _, _, phase = SkyLift.cabin(i, tc)
						if phase == "base" or phase == "summit" then
							stations[phase] += 1
						end
					end
				end
				t.truthy(worst <= limit, `a cabin moved {worst} in a frame (limit {limit})`)
				t.truthy(drift < 0.1, `the smoothed clock strayed {drift} s`)
				t.truthy(stations.base > 0 and stations.summit > 0, "the lap went through both stations")
				stop()
			end)
		end
	)

	t.test("doors: shut on the line, slid open by SlideZ in a station, between while opening", function()
		FakeEngine.with(function()
			local rig = newRig()
			local stop = SkyLiftView.start()
			local P = SkyLift.period()
			local seen = { shut = false, open = false, half = false }
			for j = 0, 600 do
				local tt = j * P / 600
				goTo(rig, tt + 10 * j) -- far apart: each frame snaps
				local tc = SkyLiftView.clock() :: number
				local f = SkyLift.doorFrac(1, tc)
				local cab = SkyLiftView.cabinModel(1)
				local fore = descendant(descendant(cab, "DoorFore"), "Glass")
				local aft = descendant(descendant(cab, "DoorAft"), "Glass")
				local lf, la = toCabin(1, tc, fore.Position), toCabin(1, tc, aft.Position)
				t.near(lf.Z, -0.75 - 1.5 * f, 1e-3, "fore leaf")
				t.near(la.Z, 0.75 + 1.5 * f, 1e-3, "aft leaf")
				t.near(lf.X, 2.92, 1e-3, "the leaf stays in the side")
				if f == 0 then
					seen.shut = true
				elseif f == 1 then
					seen.open = true
				else
					seen.half = true
				end
			end
			t.truthy(seen.shut and seen.open and seen.half, "shut, open and opening all seen")
			stop()
		end)
	end)

	t.test("riders sit on their seats in the cabin's own frame; bodies without a ride are not moved", function()
		FakeEngine.with(function()
			local rig = newRig()
			local bodies = FakeEngine.new("Folder", "Bodies")
			bodies.Parent = FakeEngine.workspace()
			local rider = person("Rider", CF.new(0, 50, 0), bodies)
			rider:SetAttribute("Ride", "3/2")
			local walker = person("Walker", CF.new(10, 5, 10), bodies)
			local wrong = person("Wrong", CF.new(20, 5, 20), bodies)
			wrong:SetAttribute("Ride", "9/9")
			local stop = SkyLiftView.start()
			for j = 0, 50 do
				goTo(rig, 7 + j * 11.3)
				local tc = SkyLiftView.clock() :: number
				local x, y, z, yaw = SkyLiftView.rootAt(3, 2, tc)
				local root = rider.PrimaryPart.CFrame
				t.truthy((root.Position - V3.new(x, y, z)).Magnitude < 1e-4, "rider on seat 2 of cabin 3")
				t.truthy((root.LookVector - V3.new(-math.sin(yaw), 0, -math.cos(yaw))).Magnitude < 1e-4, "facing")
				-- the root is SIT_ROOT over the local seat part's top, in the same frame
				local seat = SkyLiftView.seatModel(3, 2).PrimaryPart
				local top = (seat.CFrame * CF.new(0, 0.16, 0)).Position
				t.truthy(
					(root.Position - top - V3.new(0, SkyLiftView.SIT_ROOT, 0)).Magnitude < 1e-3,
					"on the drawn seat"
				)
			end
			t.eq(walker.PrimaryPart.CFrame.Position, V3.new(10, 5, 10), "a walker is not moved")
			t.eq(wrong.PrimaryPart.CFrame.Position, V3.new(20, 5, 20), "a bad Ride value is not used")
			-- off the ride: left where the server puts it
			rider:SetAttribute("Ride", nil)
			rawset(rider.PrimaryPart, "CFrame", CF.new(1, 2, 3))
			for _ = 1, 20 do
				FakeEngine.renderStep(DT)
			end
			t.eq(rider.PrimaryPart.CFrame.Position, V3.new(1, 2, 3), "a body off the ride is not moved")
			stop()
		end)
	end)

	t.test("cabin lights: the baked look without a day cycle; lit at night, off by day, with hysteresis", function()
		FakeEngine.with(function()
			newRig()
			local Lighting = game:GetService("Lighting")
			local stop = SkyLiftView.start()
			for _ = 1, 40 do
				FakeEngine.renderStep(DT)
			end
			local function lamps(): (number, number)
				local on, neon = 0, 0
				for i = 1, SkyLift.CABINS do
					local light = SkyLiftView.cabinModel(i):FindFirstChild("Light")
					if light:FindFirstChildOfClass("PointLight").Enabled then
						on += 1
					end
					if light.Material == roblox.Enum.Material.Neon then
						neon += 1
					end
				end
				return on, neon
			end
			local on, neon = lamps()
			t.eq(on, 0, "no day cycle: lamps as baked (off)")
			t.eq(neon, SkyLift.CABINS, "no day cycle: the panel as baked")
			Lighting:SetAttribute("StreetLamps", 0.9)
			for _ = 1, 40 do
				FakeEngine.renderStep(DT)
			end
			on, neon = lamps()
			t.eq(on, SkyLift.CABINS, "night: every cabin lit")
			t.eq(neon, SkyLift.CABINS, "night: the panels glow")
			Lighting:SetAttribute("StreetLamps", 0.3) -- inside the hysteresis band: stays night
			for _ = 1, 40 do
				FakeEngine.renderStep(DT)
			end
			t.eq((lamps()), SkyLift.CABINS, "dusk does not flicker")
			Lighting:SetAttribute("StreetLamps", 0)
			for _ = 1, 40 do
				FakeEngine.renderStep(DT)
			end
			on, neon = lamps()
			t.eq(on, 0, "day: lamps off")
			t.eq(neon, 0, "day: the panels unlit")
			stop()
		end)
	end)

	t.test("the bullwheel, its hub and the sheaves turn with the rope, the right way round, without moving", function()
		FakeEngine.with(function()
			local rig = newRig()
			local st = SkyLift.stations()
			local wheel = st.base.wheel
			local baseM = FakeEngine.model("f4_lift_base", CF.new(wheel.x, wheel.y, wheel.z), rig.f4)
			-- a cylinder's axis is its local X: stood up, X -> world Y
			local upright = CF.Angles(0, 0, math.pi / 2)
			local bw =
				part("Bullwheel", CF.new(wheel.x, wheel.y + 1.25, wheel.z) * upright, V3.new(0.6, 10.8, 10.8), baseM)
			local top = st.summit.wheel
			local topM = FakeEngine.model("f4_lift_summit", CF.new(top.x, top.y, top.z), rig.f4)
			local tw = part("Bullwheel", CF.new(top.x, top.y + 1.25, top.z) * upright, V3.new(0.6, 10.8, 10.8), topM)
			local tower = SkyLift.towers()[3]
			local towerM = FakeEngine.model("f4_lift_tower_3", CF.new(tower.x, tower.y, tower.z), rig.f4)
			local sheaves = {}
			for _, p in { tower.up, tower.down } do
				-- axle across the line: RightVector perpendicular to the line in plan
				table.insert(
					sheaves,
					part(
						"Sheave",
						CF.new(p.x, p.y + 1.2, p.z) * CF.Angles(0, tower.yaw, 0),
						V3.new(0.32, 1.2, 1.2),
						towerM
					)
				)
			end
			local other = part("Crossarm", CF.new(tower.x, tower.y + 2, tower.z), V3.new(13, 0.8, 0.8), towerM)
			local bases = { bw.CFrame, tw.CFrame, sheaves[1].CFrame, sheaves[2].CFrame }
			local cam = FakeEngine.workspace().CurrentCamera
			local stop = SkyLiftView.start()

			-- the velocity of a point of the wheel, by a small step of the clock
			-- (the material point of the wheel that is at `world` at clock `at`)
			local function pointVelocity(p: any, world: any, at: number): any
				rawset(cam, "CFrame", CF.new(world))
				goTo(rig, at + 100) -- two jumps over SNAP: the clock is exactly `at`
				goTo(rig, at)
				local localP = p.CFrame:PointToObjectSpace(world)
				local a = (p.CFrame * localP)
				local ta = SkyLiftView.clock() :: number
				rig.now = EPOCH + at + 0.004
				FakeEngine.renderStep(0.004)
				local b = (p.CFrame * localP)
				return (b - a) / ((SkyLiftView.clock() :: number) - ta)
			end
			-- the bullwheel: the rope leaves it on the departing strand, past the board point
			for _, pair in { { bw, st.base }, { tw, st.summit } } do
				local w, s = pair[1], pair[2]
				local gx, _, gz, yaw = SkyLift.at(s.boardS)
				local rx, rz = gx - s.wheel.x, gz - s.wheel.z
				-- the rope point on the wheel's rim beside the strand: radius STRAND across the line
				local r = V3.new(rx, 0, rz)
				local along = V3.new(-math.sin(yaw), 0, -math.cos(yaw))
				local across = r - along * r:Dot(along)
				local rim = V3.new(s.wheel.x, w.Position.Y, s.wheel.z) + across.Unit * SkyLift.STRAND
				local v = pointVelocity(w, rim, 20)
				t.truthy(
					(v - along * SkyLift.LINE_SPEED).Magnitude < 0.6,
					`{s.id} bullwheel rim moves with the rope ({v} vs {along * SkyLift.LINE_SPEED}; r {r})`
				)
			end
			for idx, sh in sheaves do
				local bottom = sh.Position - V3.new(0, 0.6, 0)
				local s = if idx == 1 then "up" else "down"
				local v = pointVelocity(sh, bottom, 40)
				-- the rope's own direction under it, from the loop
				local p = if idx == 1 then tower.up else tower.down
				local bestS, best = 0, math.huge
				for q = 0, 3600 do
					local sq = SkyLift.loop().length * q / 3600
					local x, _, z = SkyLift.at(sq)
					local d = (x - p.x) ^ 2 + (z - p.z) ^ 2
					if d < best then
						best, bestS = d, sq
					end
				end
				local _, _, _, ry = SkyLift.at(bestS)
				local rope = V3.new(-math.sin(ry), 0, -math.cos(ry)) * SkyLift.LINE_SPEED
				t.truthy((V3.new(v.X, 0, v.Z) - rope).Magnitude < 1.2, `{s} sheave rolls on the rope ({v} vs {rope})`)
				t.truthy((sh.Position - bases[2 + idx].Position).Magnitude < 1e-6, "a sheave stays on its axle")
			end
			t.truthy((bw.Position - bases[1].Position).Magnitude < 1e-6, "the bullwheel stays put")
			t.eq(other.CFrame.Position, V3.new(tower.x, tower.y + 2, tower.z), "other parts are not turned")
			-- out of range: not turned
			rawset(cam, "CFrame", CF.new(tower.x + 5000, 0, tower.z))
			local before = sheaves[1].CFrame
			goTo(rig, 77)
			t.truthy(sheaves[1].CFrame == before, "a far sheave is left alone")
			-- streamed out, then stop: the wheels go back to their baked poses
			towerM.Parent = nil
			rawset(cam, "CFrame", CF.new(wheel.x, wheel.y, wheel.z))
			for _ = 1, 70 do
				FakeEngine.renderStep(DT)
			end
			stop()
			t.truthy(bw.CFrame == bases[1], "stop puts the bullwheel back")
		end)
	end)

	t.test("words: where the cabin is going and the seconds to the platform, both ways", function()
		FakeEngine.with(function()
			for _, from in { "base", "summit" } do
				local c, boardAt, arriveAt = SkyLift.nextDeparture(from, 1234.5)
				local title, hint, secs, dest = SkyLiftView.hudFor(c, boardAt + 0.01)
				t.eq(dest, if from == "base" then "summit" else "base", `from {from}`)
				t.eq(secs, math.ceil(arriveAt - boardAt - 0.01), "seconds to the platform")
				t.truthy(string.find(title, if from == "base" then "Lookout" else "town", 1, true), title)
				t.truthy(string.find(hint, "V: outside view", 1, true), hint)
				t.truthy(string.find(hint, `{secs} s`, 1, true), hint)
				local _, near = SkyLiftView.hudFor(c, arriveAt - 0.5)
				t.truthy(string.find(near, "step out", 1, true), near)
			end
			t.eq(SkyLiftView.BOARD_LINE, "Riding the sky lift. Move the mouse to look around. V: outside view.")
		end)
	end)

	t.test("pure: the Ride attribute, the root over the seat, the smoothed clock", function()
		FakeEngine.with(function()
			t.deepEq({ SkyLiftView.parseRide("3/2") }, { 3, 2 })
			t.deepEq({ SkyLiftView.parseRide("6/4") }, { 6, 4 })
			for _, bad in { "7/1", "1/5", "0/1", "x", "3-2", 32, true } do
				t.eq((SkyLiftView.parseRide(bad)), nil, tostring(bad))
			end
			local x, y, z, yaw = SkyLift.seat(2, 3, 50)
			local rx, ry, rz, ryaw = SkyLiftView.rootAt(2, 3, 50)
			t.deepEq({ rx, ry - SkyLiftView.SIT_ROOT, rz, ryaw }, { x, y, z, yaw })
			t.eq(SkyLiftView.SIT_ROOT, AnimationDriver.SIT_SEAT, "the root over the seat is the sit clip's")
			-- (review) the server places a rider's root at the same height the client draws it
			t.eq(SkyLiftService.ROOT_ABOVE_SEAT, SkyLiftView.SIT_ROOT, "the server's seated root is the client's")
			-- (review) a rider sits by its Ride attribute alone: Seat:Sit on an anchored root is unverified, and
			-- without it the clip followed the root's 15 st/s and ran
			t.eq(AnimationDriver.seated(nil, "3/2"), true)
			t.eq(AnimationDriver.seated({}, nil), true)
			t.eq(AnimationDriver.seated(nil, nil), false)
			t.eq(SkyLiftView.advance(nil, DT, 12), 12, "first frame takes the server's")
			t.near(SkyLiftView.advance(10, 0.1, 10.1), 10.1, 1e-9, "in step")
			t.near(SkyLiftView.advance(10, 0.1, 10.5), 10.1 + 0.1 * SkyLiftView.SLEW, 1e-9, "slewed forward")
			t.near(SkyLiftView.advance(10, 0.1, 9.9), 10.1 - 0.1 * SkyLiftView.SLEW, 1e-9, "slewed back")
			t.eq(SkyLiftView.advance(10, 0.1, 40), 40, "a big jump is taken")
			t.near(SkyLiftView.spinAngle(1, 5, 1), 3, 1e-9)
			t.near(SkyLiftView.spinAngle(1, 5, -1), 2 * math.pi - 3, 1e-9)
		end)
	end)

	t.test("telescope: its prompt takes the camera to the lens, looking where it points, at 15 degrees", function()
		FakeEngine.with(function()
			local ws = FakeEngine.workspace()
			local scope, prompt = telescopeModel(ws)
			local me = game:GetService("Players").LocalPlayer
			local body = person("Me", CF.new(100, 119, 202), ws)
			rawset(me, "Character", body)
			local said: { any } = {}
			local changes: { boolean } = {}
			local stop = Telescope.start({
				hud = function(a: string?, b: string?)
					table.insert(said, { a, b })
				end,
				onChange = function(on: boolean)
					table.insert(changes, on)
				end,
			})
			local cam = ws.CurrentCamera
			rawset(cam, "CameraType", roblox.Enum.CameraType.Custom)
			-- a prompt that is not a telescope's, and another player's trigger: nothing
			local other = FakeEngine.new("ProximityPrompt", "Counter")
			other.Parent = ws
			local PPS = game:GetService("ProximityPromptService")
			PPS.PromptTriggered.fire(other, me)
			PPS.PromptTriggered.fire(prompt, FakeEngine.new("Player", "Someone"))
			t.falsy(Telescope.active(), "not for another prompt or another player")
			PPS.PromptTriggered.fire(prompt, me)
			t.truthy(Telescope.active(), "in")
			t.eq(prompt.Enabled, false, "its prompt is off while looking")
			t.deepEq(said[1], { Telescope.TITLE, Telescope.HINT }, "the words")
			t.deepEq(changes, { true })
			-- the E that opened it does not close it
			FakeEngine.input("began", { KeyCode = Key.E })
			t.truthy(Telescope.active(), "the opening press is not a closing one")
			FakeEngine.renderStep(DT)
			t.eq(cam.CameraType, roblox.Enum.CameraType.Scriptable)
			t.eq(cam.FieldOfView, Telescope.FOV)
			local look = cam.CFrame.LookVector
			t.truthy(look.Z < -0.95, `looks the way the telescope points ({look})`)
			t.near(look.Y, -math.sin(math.rad(6)), 0.02, "tipped down with it")
			t.truthy(
				(cam.CFrame.Position - V3.new(100, 120.6, 199)).Magnitude < 0.6,
				`at the lens ({cam.CFrame.Position})`
			)
			t.eq(game:GetService("UserInputService").MouseBehavior, roblox.Enum.MouseBehavior.LockCenter)
			FakeEngine.input("ended", { KeyCode = Key.E })
			FakeEngine.input("began", { KeyCode = Key.E })
			t.falsy(Telescope.active(), "E steps back")
			t.eq(cam.CameraType, roblox.Enum.CameraType.Custom, "camera type given back")
			t.eq(cam.FieldOfView, 70, "field of view given back")
			t.eq(prompt.Enabled, true, "prompt back on")
			t.deepEq(said[2], { nil, nil }, "the words cleared")
			t.deepEq(changes, { true, false })
			t.eq(game:GetService("UserInputService").MouseBehavior, roblox.Enum.MouseBehavior.Default)
			t.truthy(scope.Parent == ws)
			stop()
		end)
	end)

	t.test("telescope: the mouse pans within its limits, the wheel zooms, Q and walking off step back", function()
		FakeEngine.with(function()
			local ws = FakeEngine.workspace()
			local scope, prompt = telescopeModel(ws)
			local me = game:GetService("Players").LocalPlayer
			local body = person("Me", CF.new(100, 119, 202), ws)
			rawset(me, "Character", body)
			local stop = Telescope.start()
			local cam = ws.CurrentCamera
			local PPS = game:GetService("ProximityPromptService")
			PPS.PromptTriggered.fire(prompt, me)
			FakeEngine.renderStep(DT)
			local start = cam.CFrame.LookVector
			FakeEngine.input("changed", { UserInputType = Kind.MouseMovement, Delta = V3.new(200, 0, 0) })
			FakeEngine.renderStep(DT)
			local turned = cam.CFrame.LookVector
			t.truthy(start:Cross(turned).Y < 0, "mouse right turns right")
			local expect = 200 * Telescope.SENS * Telescope.FOV / 70
			t.near(math.acos(math.clamp(start:Dot(turned), -1, 1)), expect, 0.01, "slower when narrow")
			for _ = 1, 50 do
				FakeEngine.input("changed", { UserInputType = Kind.MouseMovement, Delta = V3.new(3000, -3000, 0) })
				FakeEngine.renderStep(DT)
			end
			local l = cam.CFrame.LookVector
			local yaw = math.atan2(-l.X, -l.Z)
			t.near(math.abs(yaw), Telescope.YAW_LIMIT, 0.02, "yaw held at its limit")
			t.near(math.asin(l.Y), Telescope.PITCH_MAX, 0.02, "pitch held at its limit")
			FakeEngine.input("changed", { UserInputType = Kind.MouseWheel, Position = V3.new(0, 0, 1) })
			FakeEngine.renderStep(DT)
			t.near(cam.FieldOfView, Telescope.FOV / Telescope.ZOOM_STEP, 1e-6, "wheel up zooms in")
			for _ = 1, 30 do
				FakeEngine.input("changed", { UserInputType = Kind.MouseWheel, Position = V3.new(0, 0, 1) })
			end
			FakeEngine.renderStep(DT)
			t.eq(cam.FieldOfView, Telescope.MIN_FOV, "no narrower than MIN_FOV")
			for _ = 1, 30 do
				FakeEngine.input("changed", { UserInputType = Kind.MouseWheel, Position = V3.new(0, 0, -1) })
			end
			FakeEngine.renderStep(DT)
			t.eq(cam.FieldOfView, Telescope.MAX_FOV, "no wider than MAX_FOV")
			FakeEngine.input("began", { KeyCode = Key.Q })
			t.falsy(Telescope.active(), "Q steps back")
			-- in again, then walk off
			PPS.PromptTriggered.fire(prompt, me)
			FakeEngine.renderStep(DT)
			t.truthy(Telescope.active())
			rawset(body.PrimaryPart, "CFrame", CF.new(100, 119, 200 + Telescope.LEAVE_DIST + 2))
			FakeEngine.renderStep(DT)
			t.falsy(Telescope.active(), "walking off steps back")
			-- in again, then the telescope streams out
			rawset(body.PrimaryPart, "CFrame", CF.new(100, 119, 202))
			PPS.PromptTriggered.fire(prompt, me)
			FakeEngine.renderStep(DT)
			scope.Parent = nil
			FakeEngine.renderStep(DT)
			t.falsy(Telescope.active(), "the telescope gone: out")
			t.eq(FakeEngine.bound(), 0, "nothing left bound")
			stop()
		end)
	end)

	t.test("telescope pure: look and zoom", function()
		FakeEngine.with(function()
			local y, p = Telescope.look(0, 0, 100, 50, 70, false)
			t.near(y, -100 * Telescope.SENS, 1e-9)
			t.near(p, -50 * Telescope.SENS, 1e-9)
			local _, pi = Telescope.look(0, 0, 0, 50, 70, true)
			t.near(pi, 50 * Telescope.SENS, 1e-9, "inverted")
			t.eq(Telescope.zoom(15, 100), Telescope.MIN_FOV)
			t.eq(Telescope.zoom(15, -100), Telescope.MAX_FOV)
			t.near(Telescope.zoom(15, -1), 15 * Telescope.ZOOM_STEP, 1e-9)
		end)
	end)
	t.test(
		"the wait for a booked cabin counts down on the HUD and clears when seated (review: nothing on screen)",
		function()
			FakeEngine.with(function()
				t.deepEq({ SkyLiftView.waitWords(nil, 10) }, { nil, nil })
				local title, hint = SkyLiftView.waitWords(30, 17.6)
				t.eq(title, "Sky lift: your cabin in 13 s")
				t.truthy(hint ~= nil and string.find(hint, "gate", 1, true) ~= nil)
				t.eq((SkyLiftView.waitWords(30, 30.2)), "Sky lift: your cabin is here")
				local player = game:GetService("Players").LocalPlayer
				local heartbeat = game:GetService("RunService").Heartbeat
				local clock = 100
				local lines: { any } = {}
				local stop = SkyLiftView.watchWait(function(a: string?, b: string?)
					table.insert(lines, { a, b })
				end, function(): number
					return clock
				end)
				heartbeat.fire(0.1)
				t.eq(#lines, 0, "nothing shown without a booking")
				player:SetAttribute("SkyLiftBoardAt", 112)
				for _ = 1, 30 do
					clock += 0.1
					heartbeat.fire(0.1)
				end
				t.truthy(#lines >= 3, `the countdown was shown {#lines} times in 3 s`)
				t.eq(lines[1][1], "Sky lift: your cabin in 12 s")
				local last = tonumber(string.match(lines[#lines][1], "in (%d+) s"))
				t.truthy(last == 9 or last == 10, `after 3 s it said {lines[#lines][1]}`)
				player:SetAttribute("SkyLiftBoardAt", nil)
				heartbeat.fire(0.1)
				t.deepEq(lines[#lines], { nil, nil }, "the usual HUD back once the booking is gone")
				local n = #lines
				heartbeat.fire(0.1)
				t.eq(#lines, n, "and only once")
				stop()
			end)
		end
	)
end
