--!strict
-- Owner D30: "i would like for the golf carts to be able to seat two". The golf cart (Shared/Vehicles/VehicleKinds
-- seats 2) carries a passenger beside its driver: Shared/Vehicles/PlayerVehicles' bookkeeping (board, alight, aboard),
-- E at a cart someone drives with its other seat free (Server/Actors/DeviceService.pick), the passenger's keys and the
-- prompt (Client/Input/InputMap, Client/UI/RideHint), and a passenger is never in a vehicle's way, cannot kick and cannot
-- take a new body (Boot/Game, the sky lift: PlayerVehicles.aboard). The built cart's seat is tests/isolated/
-- cart_two_seats.luau. The bump and knock rules are unchanged (tests/unit/shared_rides.spec).
local Isolated = require("@tests/lib/Isolated")
local PlayerVehicles = require("@shared/Vehicles/PlayerVehicles")
local VehicleKinds = require("@shared/Vehicles/VehicleKinds")
local Placeholder = require("@shared/Vehicles/Placeholder")
local DeviceService = require("@server/Actors/DeviceService")
local InputMap = require("@client/Input/InputMap")
local RideHint = require("@client/UI/RideHint")
local fs = require("@lune/fs")

return function(t)
	Isolated.register(t, "tests/isolated/cart_two_seats")

	t.test("the golf cart seats two, every other kind one; the seat beside mirrors the driver's", function()
		t.eq(VehicleKinds.seats("cart"), 2)
		for _, id in VehicleKinds.list() do
			if id ~= "cart" then
				t.eq(VehicleKinds.seats(id), 1, id)
				t.eq(Placeholder.passenger(id), nil, id)
			end
		end
		t.eq(VehicleKinds.seats("nope"), 1)
		local driver = Placeholder.cockpit("cart") :: any
		local beside = Placeholder.passenger("cart") :: any
		t.eq(beside.seat[1], -driver.seat[1])
		t.eq(beside.seat[2], driver.seat[2])
		t.eq(beside.seat[3], driver.seat[3])
	end)

	t.test(
		"bookkeeping: beside a driver only, one passenger, never both seats, off again, the driver may leave",
		function()
			local f = PlayerVehicles.new()
			PlayerVehicles.add(f, "cart_1", "cart", 0, 0, 0)
			PlayerVehicles.add(f, "moped_1", "moped", 10, 0, 0)
			t.deepEq({ PlayerVehicles.board(f, "cart_1", 2) }, { false, "nobody driving" })
			t.truthy((PlayerVehicles.enter(f, "cart_1", 1, { human = true })))
			t.deepEq({ PlayerVehicles.board(f, "cart_1", 1) }, { false, "already driving" })
			t.deepEq({ PlayerVehicles.board(f, "cart_1", 2) }, { true, nil })
			t.deepEq({ PlayerVehicles.board(f, "cart_1", 3) }, { false, "seat taken" })
			t.deepEq({ PlayerVehicles.board(f, "cart_9", 3) }, { false, "no such vehicle" })
			t.truthy((PlayerVehicles.enter(f, "moped_1", 3, { human = true })))
			t.deepEq({ PlayerVehicles.board(f, "moped_1", 4) }, { false, "one seat" })
			t.deepEq({ PlayerVehicles.enter(f, "moped_1", 2, { human = true }) }, { false, "occupied" })
			t.eq(PlayerVehicles.aboard(f, 1), "cart_1")
			t.eq(PlayerVehicles.aboard(f, 2), "cart_1")
			t.eq(PlayerVehicles.passengerOf(f, 2), "cart_1")
			t.eq(PlayerVehicles.vehicleOf(f, 2), nil, "a passenger drives nothing")
			t.truthy((PlayerVehicles.check(f)))
			-- the driver gets out: the passenger stays aboard; nobody drives until someone takes the wheel
			t.eq(PlayerVehicles.exit(f, 1), "cart_1")
			t.eq(PlayerVehicles.aboard(f, 2), "cart_1")
			local p2 = PlayerVehicles.enter(f, "cart_1", 2, { human = true })
			t.falsy(p2, "the passenger gets off before driving")
			t.truthy((PlayerVehicles.enter(f, "cart_1", 5, { human = true })), "someone else may drive them about")
			t.truthy((PlayerVehicles.check(f)))
			t.eq(PlayerVehicles.alight(f, 2), "cart_1")
			t.eq(PlayerVehicles.alight(f, 2), nil)
			t.eq(PlayerVehicles.aboard(f, 2), nil)
			t.eq((PlayerVehicles.get(f, "cart_1") :: any).passenger, nil)
			t.truthy((PlayerVehicles.check(f)))
			-- a fleet made by hand without the passengers' map still answers
			local bare = { vehicles = {}, order = {}, byDriver = {} } :: any
			t.eq(PlayerVehicles.aboard(bare, 1), nil)
			t.truthy((PlayerVehicles.check(bare)))
		end
	)

	t.test("E: the nearest in reach that can be driven, or sat in beside its driver; nothing out of reach", function()
		t.deepEq({ DeviceService.pick({}) }, { nil, false })
		local opts = {
			{ id = "car_1", d = 9, free = true, seat = false },
			{ id = "cart_1", d = 4, free = false, seat = true },
			{ id = "moped_1", d = 2, free = false, seat = false },
		}
		t.deepEq({ DeviceService.pick(opts) }, { "cart_1", true }, "beside the cart's driver")
		opts[2].seat = false
		t.deepEq({ DeviceService.pick(opts) }, { "car_1", false }, "its seat taken: the free car")
		t.deepEq(
			{ DeviceService.pick({ { id = "cart_2", d = DeviceService.REACH + 1, free = false, seat = true } }) },
			{ nil, false }
		)
	end)

	t.test("the passenger's keys and the prompt by a driven cart with its seat free", function()
		t.truthy(string.find(InputMap.HINTS("passenger"), "E get off", 1, true))
		t.eq(RideHint.words("cart", false, false, true), "E  sit beside the driver")
		t.eq(RideHint.words("cart", false, true, true), "Y  sit beside the driver")
		t.eq(RideHint.words("cart", true, false, true), "SIT")
		t.eq(RideHint.words("cart", false, false), "E  ride the golf cart", "unchanged for a free one")
		local rides = {
			{ x = 0, z = 5, free = false, beside = true },
			{ x = 0, z = 8, free = true },
			{ x = 0, z = 1, free = false },
		}
		t.eq(RideHint.pick(0, 0, rides), 1, "the nearest with a seat: the cart's beside its driver")
		rides[1].beside = false
		t.eq(RideHint.pick(0, 0, rides), 2)
	end)

	t.test("a passenger is aboard everywhere a driver is: no kick, no new body, never in a vehicle's way", function()
		local game = fs.readFile("src/server/Boot/Game.luau")
		local lift = fs.readFile("src/server/Rides/SkyLiftService.luau")
		t.falsy(string.find(game, "PlayerVehicles.vehicleOf(", 1, true), "Boot/Game asks aboard everywhere")
		t.falsy(string.find(lift, "PlayerVehicles.vehicleOf(", 1, true), "the sky lift too")
		local _, n = string.gsub(game, "PlayerVehicles%.aboard%(", "")
		t.eq(n, 3, "the kick, a new body, the shared vehicles' way")
		local client = fs.readFile("src/client/Possession/PossessionClient.luau")
		t.truthy(string.find(client, 'info.device == "passenger"', 1, true), "the client sits, never drives")
	end)
end
