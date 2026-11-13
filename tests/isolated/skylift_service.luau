--!strict
-- tests/isolated/skylift_service.luau: cases for tests/unit/skylift_service.spec.luau, run in their own Lune
-- process (tests/lib/Isolated) because they install fake engine globals (tests/lib/FakeEngine).
-- Server/Rides/SkyLiftService on that fake engine against Shared/Rides/SkyLift's timetable: the engine check's
-- own rider flow (tests/engine/SkyLift: up, down, refusals, five at once, walking away, a player leaving
-- mid-ride, a 200-step soak with nothing left behind), the epoch (written once, kept), the prompts and their
-- E wiring, the gate's board and arm from a baked gate, a player who takes another body mid-ride, the
-- telescope, the counter's lunch (free with its line; the wallet's one charge when a Town gives one), stop(),
-- and the Town built from the game's objects.
-- Interface: return function(t) (the spec shape)
local SkyLift = require("@shared/Rides/SkyLift")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local SkyLiftService = require("@server/Rides/SkyLiftService")
local SkyLiftFlow = require("@tests/engine/SkyLift")
local FakeEngine = require("@tests/lib/FakeEngine")
local roblox = require("@lune/roblox")

local function makeBody(name: string, cf: any): any
	local m = FakeEngine.model(name, cf, nil)
	local root = FakeEngine.part("HumanoidRootPart", cf, m)
	root.Size = roblox.Vector3.new(2, 2, 1)
	m.PrimaryPart = root
	FakeEngine.new("Humanoid", "Humanoid").Parent = m
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

local function world(opts: { [string]: any }?): any
	return SkyLiftFlow.newWorld(SkyLiftService, makeBody, SkyLift, opts)
end

-- A baked gate as tools/bake/skylift/Station lays it out: the pillar (Gate = "board", Station), the arm beside it
-- and the next-cabin board with a TextLabel "Next" on each face.
local function bakedRoot(): any
	local root = FakeEngine.new("Folder", "F4")
	for _, station in SkyLift.STATIONS do
		local st = (SkyLift.stations() :: any)[station]
		local m = FakeEngine.model(`gate_{station}`, roblox.CFrame.new(0, 0, 0), root)
		local interior = FakeEngine.new("Folder", "Interior")
		interior.Parent = m
		local gx = st.board.x + 3 * math.sin(st.boardYaw)
		local gz = st.board.z + 3 * math.cos(st.boardYaw)
		local pillar = FakeEngine.part("BoardGate", roblox.CFrame.new(gx, st.platformY + 2, gz), interior)
		pillar:SetAttribute("Gate", "board")
		pillar:SetAttribute("Station", station)
		-- the arm along the venue's X: hinged at its +X end at the base, at its -X end at the summit (as baked)
		local v = SkyLiftService._venue(st.venue)
		local place = { x = v.position.x, z = v.position.z, floorY = v.floorY, yaw = v.yaw }
		local px, _, pd = AlleyLayout.toLocal(place, gx, st.platformY, gz)
		local side = if station == "base" then 1 else -1
		local ax, ay, az = AlleyLayout.toWorld(place, px - side * 2, 2.7 + st.platformY - v.floorY, pd)
		local arm =
			FakeEngine.part("BoardGateArm", roblox.CFrame.new(ax, ay, az) * roblox.CFrame.Angles(0, v.yaw, 0), interior)
		arm.Size = roblox.Vector3.new(3.4, 0.25, 0.16)
		arm:SetAttribute("HingeX", px - side * 2 + side * 1.7)
		local board = FakeEngine.part("NextCabinBoard", roblox.CFrame.new(gx - 2, st.platformY + 5, gz), interior)
		for _, face in { "Front", "Back" } do
			local gui = FakeEngine.new("SurfaceGui", face)
			gui.Parent = board
			local label = FakeEngine.new("TextLabel", "Next")
			label.Text = "NEXT CABIN"
			label.Parent = gui
		end
	end
	return root
end

return function(t)
	t.test(
		"the engine check's own rider flow passes here (up, down, refusals, five, walk away, leaver, soak)",
		function()
			FakeEngine.with(function()
				local result = SkyLiftFlow.play(SkyLiftService, makeBody, SkyLift)
				if not result.ok then
					error(table.concat(result.failures, "\n"))
				end
				local n = result.numbers
				t.eq(n.up.seatError < 0.05, true)
				t.eq(math.abs(n.up.ride - SkyLift.rideTime("base")) <= 2, true)
				t.eq(math.abs(n.down.ride - SkyLift.rideTime("summit")) <= 2, true)
				t.eq(n.soak.granted > 20, true)
			end)
		end
	)

	t.test("the epoch is written once and an existing one is kept", function()
		FakeEngine.with(function()
			local rs = FakeEngine.new("Folder", "ReplicatedStorage")
			t.eq(SkyLiftService.publishEpoch(rs, 50), 50)
			t.eq(rs:GetAttribute(SkyLift.EPOCH_ATTRIBUTE), 50)
			t.eq(SkyLiftService.publishEpoch(rs, 90), 50)
			local w = world()
			-- (newWorld writes 1000 first: the service keeps it)
			t.eq(w.rs:GetAttribute(SkyLift.EPOCH_ATTRIBUTE), 1000)
			t.eq(w.svc:time(), 0)
		end)
	end)

	t.test("prompts: two gates, the telescope and the counter, E with Door = true, and E at a gate books", function()
		FakeEngine.with(function()
			local w = world({ prompts = true })
			local kinds: { [string]: any } = {}
			for _, d in w.parent:GetDescendants() do
				if d.ClassName == "ProximityPrompt" then
					kinds[d:GetAttribute("SkyLift")] = d
					t.eq(d:GetAttribute("Door"), true)
					t.eq(d.KeyboardKeyCode, roblox.Enum.KeyCode.E)
					t.eq(d.HoldDuration, 0)
				end
			end
			t.eq(kinds.gate_base.ActionText, "Ride the sky lift to the Lookout")
			t.eq(kinds.gate_summit.ActionText, "Ride the sky lift down to town")
			t.eq(kinds.telescope ~= nil, true)
			t.eq(kinds.counter.ObjectText, SkyLiftService.WORDS.counterFree)
			local p = SkyLiftFlow.player(w, "Ann", "human", SkyLiftFlow.atGate(w, "base"))
			kinds.gate_base.Triggered.fire(p)
			t.eq(w.svc:busy(p), "waiting")
			t.eq(string.find(lastOf(p, "notice").text, "Next cabin in", 1, true) ~= nil, true)
			t.eq(type(p.attrs.SkyLiftBoardAt), "number")
			-- a prompt whose handler throws is contained (a bad player stub)
			kinds.counter.Triggered.fire(nil)
			-- the telescope post stands on the telescope anchor, at the eyepiece's height
			local place = w.svc.lookout
			-- (CFrames are single precision: a thousandth of a stud out here)
			local tp = w.svc.telescopePost.Position
			local lx, ly, ld = AlleyLayout.toLocal(place, tp.X, tp.Y, tp.Z)
			t.near(lx, 15, 1e-3)
			t.near(ld, -44, 1e-3)
			t.near(ly, 4.4, 1e-3)
			w.svc:stop()
			t.eq(w.svc:busy(p), nil)
		end)
	end)

	t.test(
		"a baked gate: the prompt stands on it, the board counts down, the arm lifts while doors are open",
		function()
			FakeEngine.with(function()
				local root = bakedRoot()
				local w = world({ root = root, start = 0 })
				for _, station in SkyLift.STATIONS do
					local gate = w.svc.gates[station]
					local pillar
					for _, d in root:GetDescendants() do
						if d.Name == "BoardGate" and d:GetAttribute("Station") == station then
							pillar = d
						end
					end
					t.truthy((gate.at - pillar.Position).Magnitude < 1, `{station}: the prompt is not on the gate`)
					t.eq(#gate.labels, 2)
					t.eq(gate.armSide, if station == "base" then 1 else -1)
				end
				local homes = {}
				for _, station in SkyLift.STATIONS do
					homes[station] = w.svc.gates[station].arm.CFrame
				end
				local saw: { [string]: { [string]: boolean } } = { base = {}, summit = {} }
				local maxLift = 0
				for _ = 1, math.ceil(SkyLift.period() / 0.1) + 5 do
					SkyLiftFlow.step(w, 0.1)
					for _, station in SkyLift.STATIONS do
						local gate = w.svc.gates[station]
						local s = saw[station]
						local text = gate.labels[1].Text
						t.eq(gate.labels[2].Text, text)
						if string.match(text, "^NEXT CABIN %d+ s$") then
							s.count = true
						elseif text == "NOW BOARDING" then
							s.boarding = true
						end
						local half = gate.armSide * gate.arm.Size.X / 2
						local home = homes[station]
						local free = gate.arm.CFrame * roblox.Vector3.new(-half, 0, 0)
						local free0 = home * roblox.Vector3.new(-half, 0, 0)
						local up = free.Y - free0.Y
						maxLift = math.max(maxLift, up)
						if up > 2.5 then
							s.lifted = true
						elseif s.lifted and up < 0.01 then
							s.lowered = true
						end
						t.truthy(up > -1e-3, `{station}: the arm's free end went down`)
						-- the hinge end never moves
						local hinge = gate.arm.CFrame * roblox.Vector3.new(half, 0, 0)
						local hinge0 = home * roblox.Vector3.new(half, 0, 0)
						t.truthy((hinge - hinge0).Magnitude < 1e-3, `{station}: the hinge end moved`)
					end
				end
				for _, station in SkyLift.STATIONS do
					local s = saw[station]
					t.truthy(s.count and s.boarding, `{station}: the board never counted down and said boarding`)
					t.truthy(s.lifted and s.lowered, `{station}: the arm never lifted and came down`)
				end
				t.truthy(maxLift < 3.4 + 1e-3)
			end)
		end
	)

	t.test("taking another body mid-ride: the screen leaves the ride, the old body is held to the far end", function()
		FakeEngine.with(function()
			local w = world({ start = 5 })
			local p = SkyLiftFlow.player(w, "Swapper", "human", SkyLiftFlow.atGate(w, "summit"))
			w.svc:press(p, "summit")
			local b = w.svc.waiters[p]
			while w.svc:time() < b.boardAt + 10 do
				SkyLiftFlow.step(w, 0.1)
			end
			t.eq(w.svc:busy(p), "riding")
			local old = p.body
			p.body = makeBody("Swapper2", SkyLiftFlow.atGate(w, "summit"))
			SkyLiftFlow.step(w, 0.1)
			t.eq(w.svc:busy(p), nil)
			t.eq(lastOf(p, "deviceReleased").value, "ride_left")
			t.eq(p.attrs.OnRide, nil)
			t.eq(w.holds[old] ~= nil, true)
			-- the new body may ride at once (from the summit again)
			local ok = w.svc:press(p, "summit")
			t.eq(ok, true)
			while w.svc:time() < b.arriveAt + 1 do
				SkyLiftFlow.step(w, 0.1)
			end
			t.eq(w.holds[old].freed ~= nil, true)
			t.eq(old:GetAttribute("Ride"), nil)
			-- nobody was told "Back in town" for the old body
			for _, e in p.events do
				t.eq(e.text == SkyLiftService.WORDS.downArrive, false)
			end
		end)
	end)

	t.test("the telescope: people get the view toward the town; animals are refused with words", function()
		FakeEngine.with(function()
			local w = world()
			local place = w.svc.lookout
			local p =
				SkyLiftFlow.player(w, "Looker", "human", roblox.CFrame.new(AlleyLayout.toWorld(place, 15, 3, -42)))
			t.eq((w.svc:telescope(p)), true)
			local e = lastOf(p, "telescope")
			t.eq(e ~= nil, true)
			t.eq(e.fov, SkyLiftService.TELESCOPE_FOV)
			-- the eye is at the eyepiece, the look runs out of the venue's front (toward the town) and a little down
			local ex, ey, ez = e.eye[1], e.eye[2], e.eye[3]
			local lx, ly, lz = e.look[1], e.look[2], e.look[3]
			local dx, dz = lx - ex, lz - ez
			local tx, tz = 0 - ex, 0 - ez -- the town origin
			local cos = (dx * tx + dz * tz) / (math.sqrt(dx * dx + dz * dz) * math.sqrt(tx * tx + tz * tz))
			t.eq(cos > 0.9, true)
			t.eq(ly < ey, true)
			t.near(ey, place.floorY + 4.86, 1e-6)
			local sq = SkyLiftFlow.player(w, "Sq", "squirrel", roblox.CFrame.new(ex, ey, ez))
			local ok, why = w.svc:telescope(sq)
			t.eq(ok, false)
			t.eq(why, SkyLiftService.WORDS.telescopeAnimal)
			t.eq(lastOf(sq, "refused").text, why)
			t.eq(lastOf(sq, "telescope"), nil)
		end)
	end)

	t.test(
		"the counter: lunch on the house, on a table top, one each, every place used, cleared after a while",
		function()
			FakeEngine.with(function()
				local w = world()
				local place = w.svc.lookout
				local ok, text = w.svc:counter(SkyLiftFlow.player(w, "Diner1", "human", roblox.CFrame.new(0, 0, 0)))
				t.eq(ok, true)
				t.eq(string.find(text :: string, "On the house today", 1, true) ~= nil, true)
				local first = w.svc.lunches[1]
				-- the plate sits on the table top, within the table's 2.1-stud radius
				local plate = first.model:FindFirstChild("Plate")
				local px, py, pd = AlleyLayout.toLocal(place, plate.Position.X, plate.Position.Y, plate.Position.Z)
				local a
				for _, tb in w.svc.tables do
					if tb.id == first.table then
						a = tb
					end
				end
				t.eq(first.table, "table_1")
				t.eq(math.sqrt((px - a.x) ^ 2 + (pd - a.d) ^ 2) < 2.1 - 0.55, true)
				t.near(py, SkyLiftService.TABLE_TOP + 0.04, 1e-3)
				for _, part in first.model:GetChildren() do
					t.eq(part.Anchored, true)
					t.eq(part.CanCollide, false)
				end
				-- once each
				local again, why = w.svc:counter(first.player)
				t.eq(again, false)
				t.eq(string.find(why :: string, "already", 1, true) ~= nil, true)
				-- 8 tables x 4 places: the 33rd diner is told every table is taken
				for i = 2, 32 do
					local okI = w.svc:counter(SkyLiftFlow.player(w, `Diner{i}`, "human", roblox.CFrame.new(0, 0, 0)))
					t.eq(okI, true)
				end
				local spots: { [string]: boolean } = {}
				for _, l in w.svc.lunches do
					local key = `{l.table}/{l.spot}`
					t.eq(spots[key], nil)
					spots[key] = true
				end
				local full, fullWhy =
					w.svc:counter(SkyLiftFlow.player(w, "Diner33", "human", roblox.CFrame.new(0, 0, 0)))
				t.eq(full, false)
				t.eq(fullWhy, SkyLiftService.WORDS.lunchNoRoom)
				-- animals are refused with words
				local sq = SkyLiftFlow.player(w, "Sq", "squirrel", roblox.CFrame.new(0, 0, 0))
				local okS, whyS = w.svc:counter(sq)
				t.eq(okS, false)
				t.eq(whyS, SkyLiftService.WORDS.counterAnimal)
				-- a player who leaves takes their lunch away; the rest clear after LUNCH_SECS
				w.svc:gone(first.player)
				t.eq(#w.svc.lunches, 31)
				SkyLiftFlow.step(w, SkyLiftService.LUNCH_SECS + 1, 1)
				t.eq(#w.svc.lunches, 0)
				t.eq(#w.svc.lunchFolder:GetChildren(), 0)
			end)
		end
	)

	t.test("the counter with a wallet: the one charge, 10 cents as hilltop_lunch; no money, no lunch", function()
		FakeEngine.with(function()
			local charged: { any } = {}
			local w0 = world()
			local town = SkyLiftFlow.stubTown(w0)
			local broke: { [any]: boolean } = {}
			town.charge = function(player: any, cents: number, why: string): (boolean, string?)
				if broke[player] then
					return false, "Not enough money"
				end
				table.insert(charged, { player, cents, why })
				return true, nil
			end
			local w = world({ town = town, prompts = true })
			local rich = SkyLiftFlow.player(w0, "Rich", "human", roblox.CFrame.new(0, 0, 0))
			local poor = SkyLiftFlow.player(w0, "Poor", "human", roblox.CFrame.new(0, 0, 0))
			broke[poor] = true
			local ok, text = w.svc:counter(rich)
			t.eq(ok, true)
			t.eq(string.find(text :: string, "10 cents", 1, true) ~= nil, true)
			t.eq(#charged, 1)
			t.eq(charged[1][2], SkyLiftService.LUNCH_CENTS)
			t.eq(charged[1][3], "hilltop_lunch")
			local okP, whyP = w.svc:counter(poor)
			t.eq(okP, false)
			t.eq(whyP, "Not enough money")
			t.eq(#w.svc.lunches, 1)
			t.eq(w.svc.counterPrompt.ObjectText, SkyLiftService.WORDS.counterPaid)
		end)
	end)

	t.test("stop: waiters let go, riders put on their far platform, nobody left in the air", function()
		FakeEngine.with(function()
			local w = world({ start = 2, prompts = true })
			local rider = SkyLiftFlow.player(w, "Rider", "human", SkyLiftFlow.atGate(w, "base"))
			w.svc:press(rider, "base")
			local b = w.svc.waiters[rider]
			while w.svc:time() < b.boardAt + 15 do
				SkyLiftFlow.step(w, 0.1)
			end
			local waiter = SkyLiftFlow.player(w, "Waiter", "human", SkyLiftFlow.atGate(w, "base"))
			w.svc:press(waiter, "base")
			t.eq(w.svc:busy(rider), "riding")
			t.eq(w.svc:busy(waiter), "waiting")
			w.svc:stop()
			local c = w.svc:counts()
			t.eq(c.waiting + c.riding + c.held + c.booked + c.seated, 0)
			local st = SkyLift.stations().summit
			local pos = rider.body:GetPivot().Position
			t.near(pos.Y, st.platformY + 3, 1e-3)
			t.eq(rider.body.PrimaryPart.Anchored, false)
			t.eq(lastOf(rider, "deviceReleased").value, "ride_end")
			-- stepping after stop does nothing
			SkyLiftFlow.step(w, 1)
		end)
	end)

	t.test("gameTown: canRide refuses animals, drivers, players in a game and patients, with words", function()
		FakeEngine.with(function()
			local bodies: { [any]: any } = {}
			local function actor(species: string): any
				local body = makeBody("B", roblox.CFrame.new(0, 0, 0))
				return { species = species, body = body }
			end
			local actors: { [any]: any } = {}
			local fired: { any } = {}
			local inGame: { [any]: boolean } = {}
			local town = SkyLiftService.gameTown({
				possession = {
					actorOf = function(_self: any, player: any): any
						return actors[player]
					end,
					controllerOf = function(_self: any, _actor: any): any
						return "ai"
					end,
				},
				runtime = { world = {}, byTownId = {} },
				devices = { fleet = { vehicles = {}, byDriver = {} } },
				fire = function(player: any, payload: any)
					table.insert(fired, { player, payload })
				end,
				attractions = function(): any
					return {
						minigames = {
							stationOf = function(_self: any, player: any): string?
								return if inGame[player] then "bowling_lane_1" else nil
							end,
						},
					}
				end,
			})
			local person = { UserId = 1, events = {} }
			local squirrel = { UserId = 2, events = {} }
			local player3 = { UserId = 3, events = {} }
			local patient = { UserId = 4, events = {} }
			local nobody = { UserId = 5, events = {} }
			actors[person] = actor("human")
			actors[squirrel] = actor("squirrel")
			actors[player3] = actor("human")
			actors[patient] = actor("human")
			actors[patient].body:SetAttribute("Med", "symptoms")
			inGame[player3] = true
			local _ = bodies
			t.eq((town.canRide(person)), true)
			local ok, why = town.canRide(squirrel)
			t.eq(ok, false)
			t.eq(why, SkyLiftService.WORDS.animal)
			local ok3, why3 = town.canRide(player3)
			t.eq(ok3, false)
			t.eq(why3, "Leave your game first")
			local ok4 = town.canRide(patient)
			t.eq(ok4, false)
			local ok5, why5 = town.canRide(nobody)
			t.eq(ok5, false)
			t.eq(why5, SkyLiftService.WORDS.noBody)
			t.eq(town.speciesOf(squirrel), "squirrel")
			t.eq(town.bodyOf(person), actors[person].body)
			town.notify(person, "hello")
			town.refuse(person, "no")
			t.eq(fired[1][2].kind, "notice")
			t.eq(fired[2][2].kind, "refused")
			-- a PlayerLike stub gets the device events in its own list
			town.grant(person, { device = "ride" })
			town.release(person, "ride_end")
			t.eq(person.events[1].kind, "deviceGranted")
			t.eq(person.events[2].value, "ride_end")
			t.eq(town.charge, nil)
			-- a body the runtime does not know cannot be held
			t.eq(town.hold(actors[person].body), nil)
			-- a body it knows: its brain is suspended while held, it is drawn where the service says, and it is
			-- given back to its brain standing on the floor it is freed on
			local held = makeBody("Held", roblox.CFrame.new(0, 50, 0))
			local registered, unregistered = 0, 0
			local resumed: any = nil
			local brain = {
				suspend = function(_self: any): any
					return {}
				end,
				resume = function(_self: any, snap: any)
					resumed = snap
				end,
			}
			local a = { x = 0, y = 0, z = 0, yaw = 0, hip = 2, speed = 4, intent = { mode = "walk" } }
			local heldActor = { species = "human", body = held, possessable = true }
			local town2 = SkyLiftService.gameTown({
				possession = {
					actorOf = function(_self: any, _player: any): any
						return nil
					end,
					controllerOf = function(_self: any, _actor: any): any
						return "ai"
					end,
				},
				runtime = {
					world = {
						possessed = {},
						now = 0,
						brains = { [7] = brain },
						actorsById = { [7] = a },
						scheduler = {
							register = function()
								registered += 1
							end,
							unregister = function()
								unregistered += 1
							end,
						},
					},
					byTownId = { [7] = heldActor },
				},
				fire = function() end,
			})
			local h = town2.hold(held)
			t.truthy(h ~= nil)
			t.eq(heldActor.possessable, false)
			t.eq(unregistered, 1)
			h.place(10, 40, 20, 0.5)
			-- (no bounding box on the fake engine: the stand offset is 3) pivot = a.y - hip + offset
			t.near(a.y - a.hip + 3, 40, 1e-9)
			t.eq(a.x, 10)
			t.near(a.yaw + math.pi, 0.5, 1e-9)
			h.free(11, 116, 21, 1)
			t.eq(heldActor.possessable, true)
			t.eq(registered, 1)
			t.truthy(resumed ~= nil)
			t.near(a.y, 116 + a.hip, 1e-9)
			t.eq(a.x, 11)
		end)
	end)
	t.test(
		"a full cabin gets out on four spots of its own, one per seat, facing away from the cabin (review)",
		function()
			-- the review found all four riders of a cabin put on one spot at arrival (and the base's in its wall)
			FakeEngine.with(function()
				for _, station in SkyLift.STATIONS do
					local other = if station == "base" then "summit" else "base"
					local w = world({ start = 0 })
					local riders = {}
					for k = 1, SkyLift.SEATS do
						local p = SkyLiftFlow.player(w, `Rider{k}`, "human", SkyLiftFlow.atGate(w, station))
						local ok = w.svc:press(p, station)
						t.eq(ok, true)
						table.insert(riders, p)
					end
					local first = w.svc.waiters[riders[1]]
					for _, p in riders do
						t.eq(w.svc.waiters[p].cabin, first.cabin, "four to a cabin")
					end
					local arriveAt = first.arriveAt
					while w.svc:time() < arriveAt + 0.5 do
						SkyLiftFlow.step(w, 0.1)
					end
					local spots = {}
					for _, p in riders do
						t.eq(w.svc:busy(p), nil)
						local seat = lastOf(p, "deviceGranted").value.seat
						local x, y, z, yaw = SkyLift.alightSpot(other, seat)
						local cf = p.body:GetPivot()
						t.near(cf.Position.X, x, 1e-3, `{station} seat {seat} x`)
						t.near(cf.Position.Z, z, 1e-3, `{station} seat {seat} z`)
						t.near(cf.Position.Y, y + 3, 1e-3, `{station} seat {seat} stands on the platform`)
						local look = cf.LookVector
						t.near(look.X, -math.sin(yaw), 1e-3)
						t.near(look.Z, -math.cos(yaw), 1e-3)
						table.insert(spots, cf.Position)
					end
					for a = 1, #spots do
						for b = a + 1, #spots do
							local d = (spots[a] - spots[b]).Magnitude
							t.truthy(d >= 1.2, `{station}: riders {a} and {b} put {d} apart`)
						end
					end
				end
			end)
		end
	)

	t.test("stepping into the opening while a cabin stands there seats you at once; a full one says so", function()
		-- the review: a child walks into the open cabin instead of pressing E. Standing at the opening (in front of
		-- the shut screen) is enough: when the cabin comes and the leaves slide open, you are seated, no E
		FakeEngine.with(function()
			for _, station in SkyLift.STATIONS do
				local st = (SkyLift.stations() :: any)[station]
				local w = world({ start = 0 })
				local at = roblox.CFrame.new(st.board.x, st.platformY + 3, st.board.z)
				local p = SkyLiftFlow.player(w, "Kid", "human", at)
				t.truthy(SkyLiftService.inOpening(station, at.Position))
				-- the first window: from OPEN_LEAD before a board time
				local b = SkyLiftService.window(station, w.svc:time())
				while w.svc:time() < b - SkyLiftService.OPEN_LEAD - 0.3 do
					SkyLiftFlow.step(w, 0.1)
				end
				t.eq(w.svc:busy(p), nil, `{station}: seated before the leaves opened`)
				SkyLiftFlow.step(w, 0.5)
				t.eq(w.svc:busy(p), "riding", `{station}: standing in the open doorway did not seat the kid`)
				local g = lastOf(p, "deviceGranted")
				t.truthy(g ~= nil and g.value.device == "ride", `{station}: no grant`)
				t.truthy(w.svc:time() < b, `{station}: seated only at the board time`)
				-- the cabin it went into is the one at the door
				local _, _, _, _, phase, open = SkyLift.cabin(g.value.cabin, w.svc:time())
				t.truthy(open and phase == station, `{station}: seated into a cabin with its doors shut`)

				-- a full cabin: four booked already, the fifth steps in and is told, then rides the next
				local w2 = world({ start = 0 })
				local b2 = SkyLiftService.window(station, w2.svc:time())
				local four = {}
				for k = 1, SkyLift.SEATS do
					local q = SkyLiftFlow.player(w2, `Early{k}`, "human", SkyLiftFlow.atGate(w2, station))
					w2.svc:press(q, station)
					table.insert(four, q)
				end
				t.eq(math.abs(w2.svc.waiters[four[1]].boardAt - b2) < 0.05, true)
				local fifth = SkyLiftFlow.player(w2, "Fifth", "human", at)
				while w2.svc:time() < b2 do
					SkyLiftFlow.step(w2, 0.1)
				end
				t.eq(w2.svc:busy(fifth), "waiting", `{station}: the fifth was not put on the next cabin`)
				local n = lastOf(fifth, "notice")
				t.truthy(n ~= nil and string.find(n.text, "That cabin is full", 1, true) ~= nil, `{station}: no words`)
				-- told once for this cabin, not every step
				local told = 0
				for _, e in fifth.events do
					if e.kind == "notice" and string.find(e.text, "That cabin is full", 1, true) then
						told += 1
					end
				end
				t.eq(told, 1)
				for _, q in four do
					t.eq(w2.svc:busy(q), "riding")
				end
			end
		end)
	end)

	t.test(
		"a late friend joins the cabin in front of them while its doors are still open (grace to the doors)",
		function()
			-- the review: pressing E two seconds after the board time, with the doors open and a friend sitting in
			-- the cabin, booked the next one 25.6 s later
			FakeEngine.with(function()
				for _, station in SkyLift.STATIONS do
					local st = (SkyLift.stations() :: any)[station]
					local w = world({ start = 0 })
					local _, b = SkyLift.nextDeparture(station, 0)
					local friend = SkyLiftFlow.player(w, "Friend", "human", SkyLiftFlow.atGate(w, station))
					w.svc:press(friend, station)
					while w.svc:time() < b + 2 do
						SkyLiftFlow.step(w, 0.1)
					end
					t.eq(w.svc:busy(friend), "riding")
					local late = SkyLiftFlow.player(w, "Late", "human", SkyLiftFlow.atGate(w, station))
					local ok, text = w.svc:press(late, station)
					t.eq(ok, true)
					t.eq(text, SkyLiftService.WORDS.now)
					SkyLiftFlow.step(w, 0.1)
					t.eq(w.svc:busy(late), "riding", `{station}: the late friend was not seated`)
					t.eq(
						lastOf(late, "deviceGranted").value.cabin,
						lastOf(friend, "deviceGranted").value.cabin,
						`{station}: not in the friend's cabin`
					)
					-- after the doors close it is the next cabin
					local close = b + (st.doorsCloseSigma - st.boardSigma) % SkyLift.period()
					while w.svc:time() < close + 0.2 do
						SkyLiftFlow.step(w, 0.1)
					end
					local later = SkyLiftFlow.player(w, "Later", "human", SkyLiftFlow.atGate(w, station))
					local ok2, text2 = w.svc:press(later, station)
					t.eq(ok2, true)
					t.truthy(string.find(text2 or "", "Next cabin in", 1, true) ~= nil, `{station}: {text2}`)
				end
			end)
		end
	)

	t.test(
		"the board says NOW BOARDING only for the cabin at the door, counts down otherwise, and says FULL",
		function()
			FakeEngine.with(function()
				for _, station in SkyLift.STATIONS do
					local w = world({ start = 0 })
					local P = SkyLift.period() / SkyLift.CABINS
					for k = 0, math.ceil(2 * P / 0.25) do
						local tq = k * 0.25
						local text = SkyLiftService.boardText(w.svc, station, tq)
						local _, nb = SkyLift.nextDeparture(station, tq)
						local b = SkyLiftService.window(station, tq)
						if text == "NOW BOARDING" then
							t.truthy(
								tq >= b - SkyLiftService.BOARDING_SHOW,
								`{station}: boarding shown {b - tq} s early`
							)
						else
							t.eq(text, `NEXT CABIN {math.max(0, math.ceil(nb - tq))} s`)
						end
					end
					-- a full next cabin
					local _, nb = SkyLift.nextDeparture(station, 0)
					local tq = nb - SkyLiftService.BOARDING_SHOW - 3
					if tq > 0 then
						w.clock = 1000 + tq
						for k = 1, SkyLift.SEATS do
							local q = SkyLiftFlow.player(w, `Q{k}`, "human", SkyLiftFlow.atGate(w, station))
							w.svc:press(q, station)
						end
						t.eq(SkyLiftService.boardText(w.svc, station, tq), "NEXT CABIN FULL")
					end
				end
			end)
		end
	)

	t.test("the platform screen's leaves slide open only while a cabin stands at the opening, then shut", function()
		FakeEngine.with(function()
			local root = bakedRoot()
			for _, station in SkyLift.STATIONS do
				local st = (SkyLift.stations() :: any)[station]
				for i, dir in { -1, 1 } do
					local leaf = FakeEngine.part(
						`ScreenDoor{i}`,
						roblox.CFrame.new(st.board.x + dir, st.platformY + 3.5, st.board.z),
						root
					)
					leaf:SetAttribute("ScreenDoor", station)
					leaf:SetAttribute("Slide", roblox.Vector3.new(dir * 1.9, 0, 0))
				end
			end
			local w = world({ root = root, start = 0 })
			for _, station in SkyLift.STATIONS do
				t.eq(#w.svc.gates[station].leaves, 2)
			end
			local sawOpen, sawShut = { base = false, summit = false }, { base = false, summit = false }
			for _ = 1, math.ceil(SkyLift.period() / 0.1) do
				SkyLiftFlow.step(w, 0.1)
				for _, station in SkyLift.STATIONS do
					local gate = w.svc.gates[station]
					local leaf = gate.leaves[1]
					local moved = (leaf.part.CFrame.Position - leaf.home.Position).Magnitude
					if moved > 1e-3 then
						-- never open (even a little) unless a cabin stands in this station with its doors open
						local any = false
						for c = 1, SkyLift.CABINS do
							local _, _, _, _, phase, doors = SkyLift.cabin(c, w.svc:time())
							any = any or (doors and phase == station)
						end
						t.truthy(any, `{station}: the leaves open with no open cabin in the station`)
						if moved > 1.8 then
							sawOpen[station] = true
						end
					elseif moved < 1e-6 then
						sawShut[station] = true
					end
				end
			end
			for _, station in SkyLift.STATIONS do
				t.truthy(sawOpen[station] and sawShut[station], `{station}: the leaves never opened and shut`)
			end
		end)
	end)
end
