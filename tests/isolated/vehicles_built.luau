--!strict
-- tests/isolated/vehicles_built.luau: cases for tests/unit/vehicles_built.spec.luau, run in their own Lune process
-- (tests/lib/Isolated) because they put engine globals in place (getfenv) for Shared/Vehicles/Placeholder.build.
-- The player's vehicles as Server/Actors/DeviceService builds them (Placeholder.build, not only .look), on Lune's
-- instances (review of feat/bikes-art, findings 1, 2, 4 and 8):
--   the first-person camera (Camera/CameraRig vehicleFirst takes the FIRST EyeSocket in the model) sees from the
--   driver's head: one EyeSocket and one DriverSeat socket, straight over the Seat at a seated R15's eyes;
--   the driver the server seats on the hidden DriverSeat (Seat:Sit) sits on the drawn saddle, bench or seat, behind
--   the drawn steering wheel, on the left of a car (drive on the right), its feet near the pedals or on the floor,
--   its head under a closed car's roof and the golf cart's (raised) canopy;
--   the RootPart (the VehicleKinds box) is the only solid, queryable, massed part; every drawn part and the Seat
--   collide with nothing, weigh nothing and are not anchored; the Seat is unseen on a drawn vehicle;
--   a parked vehicle casts shadows from its big parts only.
-- A seated R15 is checked against numbers kept elsewhere: its root over the seat (Client/Animation/AnimationDriver.
-- SIT_SEAT) and its eyes over the seat (Rides/SkyLift.EYE_ABOVE_SEAT).
-- Interface: return function(t) (the spec shape)
local roblox = require("@lune/roblox")
local AnimationDriver = require("@client/Animation/AnimationDriver")
local Placeholder = require("@shared/Vehicles/Placeholder")
local SkyLift = require("@shared/Rides/SkyLift")
local VehicleKinds = require("@shared/Vehicles/VehicleKinds")

-- the engine globals Placeholder.build looks up (this process only)
do
	local dm = roblox.Instance.new("DataModel")
	-- selene: allow(deprecated)
	local env = getfenv(0) :: any
	env.Instance, env.Vector3, env.CFrame, env.Color3, env.Enum =
		roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
	env.game, env.workspace = dm, dm:GetService("Workspace")
end

-- an attachment's position in its model's frame (Lune keeps Position and CFrame apart: whichever was set)
local function at(a: any): any
	local ok, pos = pcall(function()
		return a.Position
	end)
	local cf = if ok and pos then roblox.CFrame.new(pos) else a.CFrame
	return (a.Parent.CFrame * cf).Position
end

local function drawnKinds(): { string }
	local out = {}
	for _, id in VehicleKinds.list() do
		if Placeholder.look(id) then
			table.insert(out, id)
		end
	end
	return out
end

local function child(m: any, name: string, seat: any): any
	for _, d in m:GetChildren() do
		if d:IsA("BasePart") and d.Name == name and d ~= seat then
			return d
		end
	end
	return nil
end

-- the Seat's top centre in the model's frame
local function seatTop(seat: any): any
	return seat.CFrame.Position + roblox.Vector3.new(0, seat.Size.Y / 2, 0)
end

return function(t)
	t.test("every player kind is drawn (a kind with no look would keep the greybox and its old interior)", function()
		t.eq(#drawnKinds(), #VehicleKinds.list())
	end)

	t.test(
		"one EyeSocket and one DriverSeat socket per player vehicle, over the Seat at a seated driver's eyes",
		function()
			for _, id in drawnKinds() do
				local m = Placeholder.build(id, id)
				local eyes, sockets = 0, 0
				for _, d in m:GetDescendants() do
					if d:IsA("Attachment") and d.Name == "EyeSocket" then
						eyes += 1
					elseif d:IsA("Attachment") and d.Name == "DriverSeat" then
						sockets += 1
					end
				end
				t.eq(eyes, 1, `{id}: EyeSockets`)
				t.eq(sockets, 1, `{id}: DriverSeat sockets`)
				local seat = m:FindFirstChild("DriverSeat") :: any
				t.truthy(seat and seat:IsA("Seat"), `{id}: the DriverSeat the server sits the driver on`)
				-- the camera's eye (the first EyeSocket, as CameraRig and Placeholder.eyeSocket take it)
				local eye = at(Placeholder.eyeSocket(m))
				local top = seatTop(seat)
				t.near(eye.X, top.X, 0.05, `{id}: the eye is over the Seat across`)
				t.near(eye.Z, top.Z, 0.05, `{id}: the eye is over the Seat along`)
				t.near(eye.Y - top.Y, SkyLift.EYE_ABOVE_SEAT, 0.05, `{id}: the eye at a seated R15's eyes`)
				local socket = nil
				for _, d in m:GetDescendants() do
					if d:IsA("Attachment") and d.Name == "DriverSeat" then
						socket = d
					end
				end
				t.truthy((at(socket) - seat.CFrame.Position).Magnitude < 0.05, `{id}: the seat socket is the Seat's`)
			end
		end
	)

	t.test("the hidden Seat the driver is put on lies on the saddle or seat the vehicle draws", function()
		local pairs_ = {
			{ "bike", "Saddle" },
			{ "cart", "Seat" },
			{ "jetski", "Seat" },
			{ "moped", "Seat" },
			{ "escooter", "Board" },
		}
		for _, pair in pairs_ do
			local id, drawnName = pair[1], pair[2]
			local m = Placeholder.build(id, id)
			local seat = m:FindFirstChild("DriverSeat") :: any
			local drawn = child(m, drawnName, seat)
			t.truthy(drawn, `{id} draws its {drawnName}`)
			local s, d = seat.CFrame.Position, drawn.CFrame.Position
			-- (a standing rider's Seat is a standing body's height over the board: Placeholder.SEATED.stand)
			local lift = if VehicleKinds.stands(id) then Placeholder.SEATED.stand else 0
			local sTop, dTop = s.Y + seat.Size.Y / 2, d.Y + drawn.Size.Y / 2 + lift
			t.near(sTop, dTop, 0.02, `{id}: the sitter's seat top {sTop} vs the drawn {drawnName}'s {dTop}`)
			t.truthy(
				math.abs(s.X - d.X) <= drawn.Size.X / 2,
				`{id}: the sitter at x {s.X} is over the drawn {drawnName} (x {d.X} +- {drawn.Size.X / 2})`
			)
			t.truthy(
				math.abs(s.Z - d.Z) <= drawn.Size.Z / 2,
				`{id}: the sitter at z {s.Z} is over the drawn {drawnName} (z {d.Z} +- {drawn.Size.Z / 2})`
			)
		end
		-- the cart's driver sits behind its drawn steering wheel
		local cart = Placeholder.build("cart", "cart")
		local seat = cart:FindFirstChild("DriverSeat") :: any
		local wheel = child(cart, "Steering", seat)
		t.near(seat.CFrame.Position.X, wheel.CFrame.Position.X, 0.01, "the cart's driver is behind the wheel")
		t.truthy(seat.CFrame.Position.Z > wheel.CFrame.Position.Z, "and behind it, not in front")
	end)

	t.test(
		"a seated R15 fits: hips on the seat, feet at the pedals or on the floor, head under a closed roof",
		function()
			local S = Placeholder.SEATED
			-- the module's seated figure agrees with the numbers the client and the sky lift keep
			t.eq(S.root, AnimationDriver.SIT_SEAT, "the root over the seat (AnimationDriver.SIT_SEAT)")
			t.eq(S.eye, SkyLift.EYE_ABOVE_SEAT, "the eyes over the seat (SkyLift.EYE_ABOVE_SEAT)")
			for _, id in drawnKinds() do
				local k = VehicleKinds.kind(id)
				local m = Placeholder.build(id, id)
				local seat = m:FindFirstChild("DriverSeat") :: any
				local top = seatTop(seat)
				local ground = -k.size[2] / 2
				local feet = top + roblox.Vector3.new(0, -S.feetBelow, -S.feetAhead)
				t.truthy(feet.Y >= ground, `{id}: the feet ({feet.Y}) above the ground ({ground})`)
				if VehicleKinds.stands(id) then
					-- (owner D29) the electric scooter's rider stands: the soles on the board, the eyes a standing R15's
					local board = child(m, "Board", seat)
					local boardTop = board.CFrame.Position.Y + board.Size.Y / 2
					t.near(top.Y - S.stand, boardTop, 1e-3, `{id}: the soles on the board`)
					t.near(S.stand + S.root, 3.0, 1e-6, "a standing R15's root over its soles")
				elseif not k.interior.open then
					-- drive on the right (owner decision 9): the driver on the left, the side DeviceService lets them out on
					t.truthy(top.X < -0.5, `{id}: the driver on the left (x {top.X})`)
					local roof = child(m, "Roof", seat)
					local under = roof.CFrame.Position.Y - roof.Size.Y / 2
					t.truthy(
						top.Y + S.head <= under + 1e-3,
						`{id}: the head ({top.Y + S.head}) under the roof ({under})`
					)
					t.truthy(
						math.abs(top.Z - roof.CFrame.Position.Z) <= roof.Size.Z / 2,
						`{id}: the driver under the roof along`
					)
				elseif id == "bike" then
					-- the feet near a pedal end (the cranks' two ends, seen from the side: a foot is out on its pedal's side),
					-- and clear of the front wheel
					local cranks = child(m, "Cranks", seat)
					local half = cranks.CFrame.XVector * (cranks.Size.X / 2)
					local function side(p: any): number
						return math.sqrt((feet.Y - p.Y) ^ 2 + (feet.Z - p.Z) ^ 2)
					end
					local near = math.min(side(cranks.CFrame.Position - half), side(cranks.CFrame.Position + half))
					t.truthy(near <= 0.6, `bike: the feet {near} from a pedal`)
					local wheel = child(m, "WheelF", seat)
					local axle = wheel.CFrame.Position
					local r = wheel.Size.Y / 2
					local off = math.sqrt((feet.Y - axle.Y) ^ 2 + (feet.Z - axle.Z) ^ 2)
					t.truthy(off >= r, `bike: the feet ({off} from the axle) clear the front wheel (radius {r})`)
				else
					-- on the cart's floor (the tub's top), the jet ski's deck or the moped's floorboard, within half a
					-- stud (the moped's 0.6: its seat stands a little higher over the board, as a scooter's does)
					local name = if id == "cart" then "Body" elseif id == "moped" then "Floor" else "Deck"
					local floor = child(m, name, seat)
					local floorTop = floor.CFrame.Position.Y + floor.Size.Y / 2
					local within = if id == "moped" then 0.6 else 0.5
					t.truthy(
						math.abs(feet.Y - floorTop) <= within,
						`{id}: the feet ({feet.Y}) on the floor ({floorTop})`
					)
				end
			end
		end
	)

	t.test("the golf cart: a seated head clears the canopy's underside, inside the taller box", function()
		-- owner check sheet BIKES_CHECK: the head (5.72 up) came 1.2 through the old 4.75 box's canopy (underside 4.5)
		local S = Placeholder.SEATED
		local k = VehicleKinds.kind("cart")
		local m = Placeholder.build("cart", "cart")
		local seat = m:FindFirstChild("DriverSeat") :: any
		local top = seatTop(seat)
		local canopy = child(m, "Canopy", seat)
		t.truthy(canopy, "the cart draws its canopy")
		local under = canopy.CFrame.Position.Y - canopy.Size.Y / 2
		local head = top.Y + S.head
		local clear = under - head
		t.truthy(clear >= 0.2 and clear <= 0.35, `the head ({head}) under the canopy ({under}) by {clear}`)
		t.truthy(
			math.abs(top.Z - canopy.CFrame.Position.Z) <= canopy.Size.Z / 2
				and math.abs(top.X - canopy.CFrame.Position.X) <= canopy.Size.X / 2,
			"the driver sits under the canopy"
		)
		t.near(canopy.CFrame.Position.Y + canopy.Size.Y / 2, k.size[2] / 2, 1e-3, "the canopy is the top of the box")
		for _, name in { "PostFL", "PostFR", "PostBL", "PostBR" } do
			local post = child(m, name, seat)
			t.near(post.CFrame.Position.Y + post.Size.Y / 2, under, 1e-3, `{name} carries the raised canopy`)
		end
	end)

	t.test(
		"as built: the box is the one solid, queryable, massed part; the drawing and the Seat hit nothing, weigh nothing",
		function()
			for _, id in VehicleKinds.list() do
				local m = Placeholder.build(id, id)
				local root = m.PrimaryPart :: any
				t.eq(root.Name, "RootPart", id)
				local k = VehicleKinds.kind(id)
				t.near(root.Size.X, k.size[1], 1e-4, `{id}: the root is the VehicleKinds box`)
				t.near(root.Size.Y, k.size[2], 1e-4)
				t.near(root.Size.Z, k.size[3], 1e-4)
				t.truthy(root.CanCollide and root.CanQuery, `{id}: the box collides and takes queries`)
				t.falsy(root.Massless or root.Anchored, `{id}: the box carries the mass, unanchored`)
				t.eq(root.Transparency, 1, `{id}: the box is unseen`)
				local seat = m:FindFirstChild("DriverSeat") :: any
				local drawn = Placeholder.look(id) ~= nil
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") and d ~= root then
						local tag = `{id}.{d.Name}`
						t.falsy(d.CanCollide, `{tag} collides with nothing`)
						t.truthy(d.Massless, `{tag} weighs nothing`)
						t.falsy(d.Anchored, `{tag} is not anchored`)
						if d ~= seat then
							t.falsy(d.CanQuery, `{tag} takes no queries`)
						end
					end
				end
				if drawn then
					t.eq(seat.Transparency, 1, `{id}: the Seat is unseen (the drawing shows the seat)`)
					t.falsy(seat.CastShadow, `{id}: and casts no shadow`)
				end
			end
		end
	)

	t.test("a parked vehicle casts shadows from its big parts only (the body, the roof, the tyres)", function()
		-- the town's fleet (owner D29: the two carts became the ten shared vehicles, Vehicles/SharedRides)
		local placed = { car = 2, cart = 3, bike = 2, pickup = 1, suv = 1, jetski = 1, moped = 2, escooter = 5 }
		local total = 0
		for _, id in drawnKinds() do
			local m = Placeholder.build(id, id)
			local casters, tyres = 0, 0
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 1 and d.CastShadow then
					casters += 1
					if string.match(d.Name, "^Wheel%u%u?$") then
						tyres += 1
					end
				end
			end
			t.truthy(casters <= 8, `{id}: {casters} parts cast shadows`)
			t.eq(tyres, VehicleKinds.kind(id).wheels, `{id}: every tyre casts`)
			total += casters * (placed[id] or 1)
		end
		-- (at most 60 before D29's ten shared vehicles: a third cart, two mopeds (cowl, seat, tyres) and five scooters
		-- (board, tyres) bring it to 84)
		t.truthy(total <= 90, `the parked fleet: {total} shadow casters (240 before the bikes pass)`)
	end)
end
