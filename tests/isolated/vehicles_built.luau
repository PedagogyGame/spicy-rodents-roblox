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
--   a parked vehicle casts shadows from its big parts only;
--   the driver sees out (D29: a blank grey screen in the pickup): with CameraRig.seeOut applied as vehicleFirst
--   applies it, no part the driver sees is round the eye, and looking ahead, a little down and to the sides
--   nothing opaque is within a couple of studs.
-- A seated R15 is checked against numbers kept elsewhere: its root over the seat (Client/Animation/AnimationDriver.
-- SIT_SEAT) and its eyes over the seat (Rides/SkyLift.EYE_ABOVE_SEAT).
-- Interface: return function(t) (the spec shape)
local roblox = require("@lune/roblox")
local AnimationDriver = require("@client/Animation/AnimationDriver")
local CameraRig = require("@client/Camera/CameraRig")
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

	t.test("D29: the driver sees out: in first person nothing opaque is round the eye or just ahead of it", function()
		-- the distance along a ray to a part's box, or nil
		local function hit(cf: any, size: any, o: any, d: any): number?
			local lo, ld = cf:PointToObjectSpace(o), cf:VectorToObjectSpace(d)
			local tmin, tmax = 0, math.huge
			for _, axis in { "X", "Y", "Z" } do
				local h, oo, dd = size[axis] / 2, lo[axis], ld[axis]
				if math.abs(dd) < 1e-9 then
					if math.abs(oo) > h then
						return nil
					end
				else
					local a, b = (-h - oo) / dd, (h - oo) / dd
					tmin, tmax = math.max(tmin, math.min(a, b)), math.min(tmax, math.max(a, b))
				end
			end
			return if tmin <= tmax then tmin else nil
		end
		local looks = {}
		for _, yaw in { 0, 0.6, -0.6 } do
			for _, pitch in { 0, -0.25 } do
				table.insert(looks, roblox.CFrame.Angles(0, yaw, 0) * roblox.CFrame.Angles(pitch, 0, 0))
			end
		end
		for _, id in drawnKinds() do
			local m = Placeholder.build(id, id)
			local eye = at(Placeholder.eyeSocket(m))
			local blocked = 0
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") and d.Transparency < 1 then
					local k = CameraRig.seeOut(eye, d.CFrame, d.Size, d.Material == roblox.Enum.Material.Glass) or 0
					local shown = 1 - (d.Transparency + (1 - d.Transparency) * k)
					if shown > 0.5 then
						t.falsy(
							hit(d.CFrame, d.Size, eye, roblox.Vector3.new(0, 0, -1)) == 0,
							`{id}: the eye is in {d.Name}`
						)
						for _, look in looks do
							local dist = hit(d.CFrame, d.Size, eye, look.LookVector)
							if dist and dist < 2 then
								blocked += 1
								print(`  {id}: {d.Name} {string.format("%.2f", dist)} studs ahead`)
							end
						end
					end
				end
			end
			t.eq(blocked, 0, `{id}: opaque parts just ahead of the eye`)
		end
	end)

	t.test("a parked vehicle casts shadows from its big parts only (the body, the roof, the tyres)", function()
		-- the town's fleet (owner D29: the two carts became the ten shared vehicles, Vehicles/SharedRides)
		-- (D30: no ambulance stands parked as a player vehicle: one is drawn only while a doctor has it out)
		local placed =
			{ car = 2, cart = 3, bike = 2, pickup = 1, suv = 1, jetski = 1, moped = 2, escooter = 5, ambulance = 0 }
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

	-- owner D32: "a little bit of glitching when you're turning or just kind of adjusting your steering direction.
	-- There's like a whole flash of a glitch across the whole screen" (the scooter and the moped, first person on entry)
	t.test(
		"D32: steering the leaning rides: the box never in the road, the eye never jumps, the hidden parts stay",
		function()
			local CarMotor = require("@shared/Movement/CarMotor")
			local Units = require("@shared/Config/Units")
			local Vehicle = require("@client/Controllers/Vehicle")
			local CFrame, Vector3 = roblox.CFrame, roblox.Vector3
			local dt = 1 / 60
			-- the steering: straight to speed, then taps and holds both ways (A / D "adjusting the direction")
			local function steerAt(f: number): number
				if f < 90 then
					return 0
				end
				local k = (f - 90) % 150
				local side = if math.floor((f - 90) / 150) % 2 == 0 then 1 else -1
				if k < 8 then
					return side -- a tap
				elseif k < 40 then
					return 0
				elseif k < 100 then
					return -side -- a hold the other way
				end
				return 0
			end
			-- a one-frame wobble of the drawn root's lean (what the physics did to a box pressed into the road): the
			-- camera must not pass it on
			local seed = 12345
			local function wobble(): number
				seed = (seed * 1103515245 + 12345) % 2147483648
				return (seed / 2147483648 - 0.5) * 0.06
			end
			for _, id in { "moped", "escooter", "bike" } do
				local m = Placeholder.build(id, id)
				local eyeRel = CFrame.new(at(Placeholder.eyeSocket(m)))
				local k = VehicleKinds.kind(id)
				local half = k.size[2] / 2
				local s = CarMotor.new(id, 0, half, 0, 0)
				local world = {
					groundAt = function(): number
						return 0
					end,
				}
				-- the parts the camera hides round the eye on entry (CameraRig.seeOut at the eye, upright, parked)
				local drawn = {}
				for _, d in m:GetDescendants() do
					if d:IsA("BasePart") and d.Transparency < 1 then
						table.insert(drawn, d)
					end
				end
				local function nearSet(eye: any, root: any): { [any]: boolean }
					local out = {}
					for _, d in drawn do
						local kk =
							CameraRig.seeOut(eye, root * d.CFrame, d.Size, d.Material == roblox.Enum.Material.Glass)
						if kk == 1 then
							out[d] = true
						end
					end
					return out
				end
				local entry = nearSet(eyeRel.Position, CFrame.new())
				local shown = 0
				local lastNew, lastOld, lastRollNew, lastRollOld = nil, nil, nil, nil
				local jumpNew, jumpOld, rollNew, rollOld = 0, 0, 0, 0
				local swingNew, swingOld, leanMax, lowest, extra = 0, 0, 0, math.huge, 0
				for f = 1, 60 * 10 do
					CarMotor.step(s, { throttle = 1, steer = steerAt(f), handbrake = false }, dt, world)
					local lift = Vehicle.leanLift(id, s.lean)
					local root = Units.yawCFrame(s.yaw, Vector3.new(s.x, s.y, s.z))
						* CFrame.new(0, lift, 0)
						* CFrame.Angles(0, 0, s.lean)
					leanMax = math.max(leanMax, math.abs(s.lean))
					-- the leaned box's lowest corner, over the road (0) it stands on
					for _, cx in { -1, 1 } do
						for _, cy in { -1, 1 } do
							for _, cz in { -1, 1 } do
								local c = root * Vector3.new(cx * k.size[1] / 2, cy * half, cz * k.size[3] / 2)
								lowest = math.min(lowest, c.Y)
							end
						end
					end
					if s.lean ~= 0 then
						-- the least lift: the lowest corner just on the road, not above it
						local lo = math.huge
						for _, cx in { -1, 1 } do
							for _, cy in { -1, 1 } do
								lo = math.min(lo, (root * Vector3.new(cx * k.size[1] / 2, cy * half, 0)).Y)
							end
						end
						extra = math.max(extra, lo)
					end
					local drawnRoot = root * CFrame.Angles(0, 0, wobble())
					shown = CameraRig.rollStep(shown, CameraRig.rollOf(drawnRoot), dt)
					local cam = CameraRig.rideEye(drawnRoot, eyeRel, shown)
					local old = drawnRoot * eyeRel -- the camera before D32: the eye socket as the root carried it
					-- the eye's place in the vehicle's upright frame (its travel and its turn taken out), frame to frame
					local up = CameraRig.upright(drawnRoot)
					local relNew, relOld = up:PointToObjectSpace(cam.Position), up:PointToObjectSpace(old.Position)
					if lastNew then
						jumpNew = math.max(jumpNew, (relNew - lastNew).Magnitude)
						jumpOld = math.max(jumpOld, (relOld - lastOld).Magnitude)
						rollNew = math.max(rollNew, math.abs(CameraRig.rollOf(cam) - lastRollNew))
						rollOld = math.max(rollOld, math.abs(CameraRig.rollOf(old) - lastRollOld))
					end
					lastNew, lastOld = relNew, relOld
					lastRollNew, lastRollOld = CameraRig.rollOf(cam), CameraRig.rollOf(old)
					-- sideways from where it sits upright
					swingNew = math.max(swingNew, math.abs(relNew.X - eyeRel.Position.X))
					swingOld = math.max(swingOld, math.abs(relOld.X - eyeRel.Position.X))
					-- no part the camera did not hide on entry comes round it (nothing is shown and hidden in turn)
					for d in nearSet(cam.Position, drawnRoot) do
						t.truthy(entry[d], `{id}: {d.Name} comes round the eye at frame {f} (not hidden on entry)`)
					end
				end
				print(
					string.format(
						"      %s: lean up to %.2f rad; eye jump a frame %.3f st (rigid %.3f), roll a frame %.2f deg (rigid %.2f), swing %.2f st (rigid %.2f), lowest corner %.4f",
						id,
						leanMax,
						jumpNew,
						jumpOld,
						math.deg(rollNew),
						math.deg(rollOld),
						swingNew,
						swingOld,
						lowest
					)
				)
				t.truthy(leanMax > 0.4, `{id}: the sweep leans it (to {leanMax})`)
				t.truthy(lowest >= -1e-6, `{id}: the leaned box stays out of the road ({lowest})`)
				t.truthy(extra <= 1e-6, `{id}: and is lifted no more than that ({extra})`)
				t.truthy(jumpNew <= 0.05, `{id}: the eye moves at most 0.05 st a frame against the vehicle ({jumpNew})`)
				t.truthy(math.deg(rollNew) <= 1, `{id}: the view turns at most a degree a frame about its axis`)
				t.truthy(swingNew <= 0.4 * swingOld, `{id}: the eye swings well under half as far as the rigid eye did`)
				-- (the old camera, for the record: it carried every wobble and the whole lean)
				t.truthy(math.deg(rollOld) > 3 * math.deg(rollNew), `{id}: the rigid eye's roll a frame was far worse`)
			end
		end
	)

	t.test("D32: third person: the driver is faded before the engine camera can come inside them", function()
		local Vector3 = roblox.Vector3
		for _, id in drawnKinds() do
			local m = Placeholder.build(id, id)
			local lo, hi = Vector3.new(math.huge, math.huge, math.huge), Vector3.new(-math.huge, -math.huge, -math.huge)
			for _, d in m:GetDescendants() do
				if d:IsA("BasePart") then
					local h = d.Size / 2
					for _, sx in { -1, 1 } do
						for _, sy in { -1, 1 } do
							for _, sz in { -1, 1 } do
								local c = d.CFrame * Vector3.new(sx * h.X, sy * h.Y, sz * h.Z)
								lo, hi = lo:Min(c), hi:Max(c)
							end
						end
					end
				end
			end
			local focus = Vector3.new(0, CameraRig.followLift(hi.Y - lo.Y), 0)
			-- the driver (a seated or standing R15) round the seat: a stud each side, feet to the top of the head
			local seat = child(m, "DriverSeat", nil)
			local top = seatTop(seat)
			local stands = VehicleKinds.stands(id)
			local feet = if stands then top.Y else top.Y - Placeholder.SEATED.feetBelow
			local head = top.Y + Placeholder.SEATED.head + 0.5
			local reach = 0
			for _, sx in { -1, 1 } do
				for _, y in { feet, head } do
					for _, sz in { -1, 1 } do
						reach = math.max(reach, (Vector3.new(top.X + sx, y, top.Z + sz * 1.2) - focus).Magnitude)
					end
				end
			end
			local hideAt = CameraRig.riderHide(math.min(reach, CameraRig.RIDER_REACH))
			t.truthy(hideAt < 8, `{id}: the fade starts inside the engine camera's least distance ({hideAt})`)
			if id == "moped" or id == "escooter" or id == "bike" then
				t.truthy(reach <= CameraRig.RIDER_REACH, `{id}: the rider's whole reach is counted ({reach})`)
				t.eq(CameraRig.fadeAt(reach, hideAt), 1, `{id}: gone with the camera at their reach`)
			end
		end
	end)
end
