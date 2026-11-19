--!strict
-- Review of feat/bikes-art (failing cases; nothing here is a fix). The player's vehicles as Server/Actors/DeviceService
-- builds them (Vehicles/Placeholder.build, not only .look): the first-person camera (Camera/CameraRig vehicleFirst takes
-- the FIRST EyeSocket in the model) must stay where the driver's head is, and the driver the server seats on the hidden
-- DriverSeat (Seat:Sit) must sit on the saddle or seat the vehicle now draws.
--   1 a shaped vehicle carries two EyeSockets and two DriverSeat attachments (VehiclePuppet's spec sockets AND the
--     interior's); the first found is VehiclePuppet's, on the other side of the car from the Seat (car: x -1.29 against
--     the Seat's +1.18, 0.4 higher), so the camera moved 2.5 studs off the driver's head.
--   2 the Seat is where VehicleKinds' interior puts it, not on the drawn saddle or bench: the bike's rider sits 0.65 below
--     the saddle and 0.8 ahead of it (on the top tube, legs out through the front wheel), the cart's 1.4 ahead of the
--     bench, the jet ski's 1.8 ahead of its seat and off its side.
-- Lune instances stand in for the engine's (the engine globals are set for Placeholder.build, then put back).
local roblox = require("@lune/roblox")
local Placeholder = require("@shared/Vehicles/Placeholder")
local VehicleKinds = require("@shared/Vehicles/VehicleKinds")

local NAMES = { "Instance", "Vector3", "CFrame", "Color3", "Enum", "game", "workspace" }

local function withEngine<T>(fn: () -> T): T
	local env = getfenv(0) :: any
	local saved = {}
	for _, n in NAMES do
		saved[n] = env[n]
	end
	local dm = roblox.Instance.new("DataModel")
	env.Instance, env.Vector3, env.CFrame, env.Color3, env.Enum =
		roblox.Instance, roblox.Vector3, roblox.CFrame, roblox.Color3, roblox.Enum
	env.game, env.workspace = dm, dm:GetService("Workspace")
	local ok, out = pcall(fn)
	for _, n in NAMES do
		env[n] = saved[n]
	end
	if not ok then
		error(out, 0)
	end
	return out
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

return function(t)
	t.test(
		"review bikes: one EyeSocket per player vehicle, where the driver's head is (the camera takes the first)",
		function()
			withEngine(function()
				for _, id in drawnKinds() do
					local m = Placeholder.build(id, id)
					local eyes, seats = 0, 0
					for _, d in m:GetDescendants() do
						if d:IsA("Attachment") and d.Name == "EyeSocket" then
							eyes += 1
						elseif d:IsA("Attachment") and d.Name == "DriverSeat" then
							seats += 1
						end
					end
					t.eq(eyes, 1, `{id}: EyeSockets`)
					t.eq(seats, 1, `{id}: DriverSeat sockets`)
					-- the interior's eye (VehicleKinds, HTML axes flipped as Placeholder flips them), over the Seat's side
					local e = VehicleKinds.kind(id).interior.eye
					local first = m:FindFirstChild("EyeSocket", true)
					local p = at(first)
					t.near(
						p.X,
						-e[1],
						0.05,
						`{id}: the camera's eye across (the Seat is at x {-VehicleKinds.kind(id).interior.seat[1]})`
					)
					t.near(p.Y, e[2], 0.05, `{id}: the camera's eye height`)
				end
				return nil
			end)
		end
	)

	t.test("review bikes: the hidden Seat the driver is put on lies on the saddle or seat the vehicle draws", function()
		withEngine(function()
			for _, pair in { { "bike", "Saddle" }, { "cart", "Seat" }, { "jetski", "Seat" } } do
				local id, drawnName = pair[1], pair[2]
				local m = Placeholder.build(id, id)
				local seat = m:FindFirstChild("DriverSeat") :: any
				local drawn: any = nil
				for _, d in m:GetChildren() do
					if d:IsA("BasePart") and d.Name == drawnName and d ~= seat then
						drawn = d
					end
				end
				t.truthy(drawn, `{id} draws its {drawnName}`)
				local s, d = seat.CFrame.Position, drawn.CFrame.Position
				local sTop, dTop = s.Y + seat.Size.Y / 2, d.Y + drawn.Size.Y / 2
				t.near(sTop, dTop, 0.25, `{id}: the sitter's seat top {sTop} vs the drawn {drawnName}'s {dTop}`)
				t.truthy(
					math.abs(s.X - d.X) <= drawn.Size.X / 2,
					`{id}: the sitter at x {s.X} is over the drawn {drawnName} (x {d.X} +- {drawn.Size.X / 2})`
				)
				t.truthy(
					math.abs(s.Z - d.Z) <= drawn.Size.Z / 2,
					`{id}: the sitter at z {s.Z} is over the drawn {drawnName} (z {d.Z} +- {drawn.Size.Z / 2})`
				)
			end
			return nil
		end)
	end)
end
