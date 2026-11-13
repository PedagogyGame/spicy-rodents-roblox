--!strict
-- tests/isolated/skylift_ride.luau: the case for tests/unit/skylift_ride.spec.luau, run in its own Lune process
-- (tests/lib/Isolated) because it installs fake engine globals (tests/lib/FakeEngine).
-- The sky lift joined (the plan's lane 6 proof): the real server service (Server/Rides/SkyLiftService, on the stub
-- Town of tests/engine/SkyLift) and the real client view (Client/Rides/SkyLiftView, drawing six cabins from a
-- CabinTemplate built here to the bake's interface) share one fake engine and one clock. A person presses the
-- base gate, is booked, boards (the grant asks for the gondola in first person; Client/Camera/CameraPolicy and
-- PossessionClient.rideTarget put the camera on that seat's EyeSocket in the view's own cabin), rides up with the
-- body drawn on the view's seat, toggles to the outside view and back (V), is told what E does mid-ride, alights
-- on the summit platform with the words and the legs back (Ride attribute gone, root unanchored, the view leaves
-- the body alone), then rides down the same way.
-- Interface: return function(t) (the spec shape)
local SkyLift = require("@shared/Rides/SkyLift")
local SkyLiftService = require("@server/Rides/SkyLiftService")
local SkyLiftView = require("@client/Rides/SkyLiftView")
local CameraPolicy = require("@client/Camera/CameraPolicy")
local PossessionClient = require("@client/Possession/PossessionClient")
local SkyLiftFlow = require("@tests/engine/SkyLift")
local FakeEngine = require("@tests/lib/FakeEngine")
local roblox = require("@lune/roblox")

local CF = roblox.CFrame
local V3 = roblox.Vector3
local DT = 1 / 30

FakeEngine.classes({ parts = { "Seat" } })
FakeEngine.events({ "PromptTriggered" })

local function part(name: string, cf: any, size: any, parent: any, class: string?): any
	local p = FakeEngine.new(class or "Part", name)
	rawset(p, "CFrame", cf)
	rawset(p, "Size", size)
	p.Anchored = true
	p.Parent = parent
	return p
end

-- A CabinTemplate to the bake's interface (tools/bake/skylift/Cabin's header), its origin at `at`.
local function makeTemplate(parent: any, at: any): any
	local m = FakeEngine.model("CabinTemplate", at, nil)
	m:SetAttribute("Template", true)
	local origin = part("Origin", at, V3.new(0.2, 0.2, 0.2), m)
	m.PrimaryPart = origin
	part("Floor", at * CF.new(0, -0.25, 0), V3.new(6, 0.5, 8), m)
	part("Roof", at * CF.new(0, 6.8, 0), V3.new(6, 0.7, 7.8), m)
	local light = part("Light", at * CF.new(0, 6.47, 0), V3.new(1, 0.06, 2.4), m)
	local lamp = FakeEngine.new("PointLight", "PointLight")
	lamp.Enabled = false
	lamp.Parent = light
	local doors = FakeEngine.new("Folder", "Doors")
	doors.Parent = m
	for _, d in { { "DoorFore", -0.75, -1.5 }, { "DoorAft", 0.75, 1.5 } } do
		local leaf = FakeEngine.model(d[1] :: string, at, doors)
		leaf:SetAttribute("SlideZ", d[3])
		part("Glass", at * CF.new(2.92, 3.8, d[2] :: number), V3.new(0.08, 4.8, 1.5), leaf)
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
		local eye = FakeEngine.new("Attachment", "EyeSocket")
		eye.CFrame = CF.new(0, 0.16 + SkyLift.EYE_ABOVE_SEAT, 0)
		eye.Parent = s
	end
	m.Parent = parent
	return m
end

local function lastOf(p: any, kind: string): any
	for i = #p.events, 1, -1 do
		if p.events[i].kind == kind then
			return p.events[i]
		end
	end
	return nil
end

local function hasEye(model: any): boolean
	for _, d in model:GetDescendants() do
		if d.Name == "EyeSocket" then
			return true
		end
	end
	return false
end

return function(t)
	t.test("board, ride up, toggle the view, alight, ride down: the real service against the real view", function()
		FakeEngine.with(function()
			local ws = FakeEngine.workspace()
			local rs = game:GetService("ReplicatedStorage")
			local clock = { now = 0 }
			rawset(ws, "BulkMoveTo", function(_self: any, parts: { any }, cframes: { any }, _mode: any)
				for i, p in parts do
					rawset(p, "CFrame", cframes[i])
				end
			end)
			rawset(ws, "GetServerTimeNow", function(_self: any): number
				return clock.now
			end)
			local bodies = FakeEngine.new("Folder", "Bodies")
			bodies.Parent = ws
			local exp = FakeEngine.new("Folder", "Expansion")
			exp.Parent = ws
			local f4 = FakeEngine.new("Folder", "F4")
			f4.Parent = exp
			local wheel = SkyLift.stations().base.wheel
			makeTemplate(f4, CF.new(wheel.x, wheel.y - 40, wheel.z))

			local function makeBody(name: string, cf: any): any
				local m = FakeEngine.model(name, cf, bodies)
				local root = FakeEngine.part("HumanoidRootPart", cf, m)
				root.Size = V3.new(2, 2, 1)
				m.PrimaryPart = root
				FakeEngine.new("Humanoid", "Humanoid").Parent = m
				return m
			end
			-- the server: the stub Town of the engine check, the epoch on the real ReplicatedStorage
			local w = SkyLiftFlow.newWorld(SkyLiftService, makeBody, SkyLift, { start = 3, rs = rs, root = f4 })
			clock.now = w.clock
			-- the client: the view on the same server clock, bound to the render step
			local stopView = SkyLiftView.start()
			local function tick(seconds: number)
				for _ = 1, math.max(1, math.ceil(seconds / DT - 1e-9)) do
					w.clock += DT
					clock.now = w.clock
					w.svc:step(DT)
					FakeEngine.renderStep(DT)
				end
			end
			tick(1.5) -- the template is found, six cabins drawn
			t.eq(#ws:FindFirstChild(SkyLiftView.FOLDER):GetChildren(), SkyLift.CABINS, "six cabins on this screen")

			local p = SkyLiftFlow.player(w, "Ann", "human", SkyLiftFlow.atGate(w, "base"))
			for _, leg in { { "base", "summit" }, { "summit", "base" } } do
				local from, to = leg[1], leg[2]
				-- the gate
				local ok, why = w.svc:press(p, from)
				t.eq(ok, true, `{from}: the gate booked a person ({why})`)
				local booked = w.svc.waiters[p]
				t.truthy(booked, `{from}: waiting`)
				local cabin, seat = booked.cabin, booked.seat
				-- (pressed while the last cabin's doors are still open, the booking is that cabin: "step in")
				local told = lastOf(p, "notice").text
				t.truthy(
					string.find(told, "Next cabin in", 1, true) or told == SkyLiftService.WORDS.now,
					`{from}: told when ({told})`
				)
				repeat
					tick(0.1)
				until w.svc:time() >= booked.boardAt + 0.1
				-- boarding: the grant the client acts on
				local g = lastOf(p, "deviceGranted")
				t.truthy(g, `{from}: granted`)
				local info = g.value
				t.eq(info.device, "ride")
				t.eq(info.kind, "gondola")
				t.eq(info.to, to)
				t.eq(p.body:GetAttribute("Ride"), `{cabin}/{seat}`)
				-- first person on boarding: the policy for a person in the gondola, the seat's eye in the view's cabin
				local first = CameraPolicy.modeFor({ species = "human", vehicle = "gondola", firstPersonToggle = true })
				t.eq(first.mode, "vehicleFirst")
				t.eq(first.toggleAllowed, true, "V stays")
				local seatModel = PossessionClient.rideTarget(first.mode, cabin, seat, SkyLiftView)
				t.truthy(seatModel, `{from}: a seat model for the camera`)
				t.eq(hasEye(seatModel), true, "the seat model holds its EyeSocket")
				-- riding: the body is drawn on the view's seat, and the seat is where the server seats it
				local worst, worstServer = 0, 0
				for _ = 1, 6 do
					tick(5)
					local now = SkyLiftView.clock() :: number
					if w.svc:time() < booked.arriveAt - 1 then
						local x, y, z = SkyLiftView.rootAt(cabin, seat, now)
						local root = p.body.PrimaryPart.Position
						worst = math.max(worst, (root - V3.new(x, y, z)).Magnitude)
						local sx, sy, sz = SkyLift.seat(cabin, seat, w.svc:time())
						local seatPart = w.svc.seats[cabin][seat]
						local seatPos = seatPart.Position + V3.new(0, seatPart.Size.Y / 2, 0) -- its top
						worstServer = math.max(worstServer, (seatPos - V3.new(sx, sy, sz)).Magnitude)
						-- the eye is inside the view's own cabin
						local eye = SkyLiftView.eye(cabin, seat) :: any
						local cab = SkyLiftView.cabinModel(cabin) :: any
						local rel = (cab.PrimaryPart or cab:FindFirstChild("Origin")).CFrame:PointToObjectSpace(
							eye.Position
						)
						t.eq(
							math.abs(rel.X) < 3 and math.abs(rel.Z) < 4 and rel.Y > 4.49 and rel.Y < 6.5,
							true,
							`eye at {rel} in its cabin`
						)
						t.eq(w.svc:busy(p), "riding")
					end
				end
				t.eq(worst < 0.05, true, `{from}: rider {worst} studs off the view's seat`)
				t.eq(worstServer < 0.05, true, `{from}: server seat {worstServer} studs off the timetable`)
				-- V: the cabin from outside, and back
				local third =
					CameraPolicy.modeFor({ species = "human", vehicle = "gondola", firstPersonToggle = false })
				t.eq(third.mode, "vehicleThird")
				t.eq(PossessionClient.rideTarget(third.mode, cabin, seat, SkyLiftView), SkyLiftView.cabinModel(cabin))
				t.eq(PossessionClient.rideTarget(first.mode, cabin, seat, SkyLiftView), seatModel)
				-- E mid-ride: words, and the service will not book a rider again
				t.truthy(string.find(PossessionClient.rideWords(to), if to == "summit" then "top" else "bottom"))
				t.eq((w.svc:press(p, from)), false)
				-- alighting
				while w.svc:time() < booked.arriveAt + 0.5 do
					tick(0.1)
				end
				t.eq(lastOf(p, "deviceReleased").value, "ride_end")
				t.eq(PossessionClient.reasonText("ride_end"), nil, "no refusal words on arrival")
				local words = if to == "summit" then SkyLiftService.WORDS.upArrive else SkyLiftService.WORDS.downArrive
				t.eq(lastOf(p, "notice").text, words)
				t.eq(p.body:GetAttribute("Ride"), nil)
				t.eq(p.body.PrimaryPart.Anchored, false, "the legs are the player's again")
				local st = SkyLift.stations()[to]
				local pos = p.body:GetPivot().Position
				t.near(pos.Y, st.platformY + 3, 0.1)
				local before = pos
				tick(1) -- the view leaves a body without a Ride attribute where it stands
				t.eq((p.body:GetPivot().Position - before).Magnitude < 1e-3, true)
				t.eq(w.svc:busy(p), nil)
				-- walk to the gate for the ride back
				p.body:PivotTo(SkyLiftFlow.atGate(w, to))
			end
			local c = w.svc:counts()
			t.eq(c.waiting + c.riding + c.held + c.booked + c.seated, 0, "nothing left behind")
			stopView()
			w.svc:stop()
		end)
	end)
end
