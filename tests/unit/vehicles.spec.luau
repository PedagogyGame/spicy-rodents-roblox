--!strict
-- W1 §4.4 #5 / §1.5 Devices: VehicleKinds parameter sets and access rules (brief v2 §13a, §15),
-- PlayerVehicles seats and keys (keys only change hands while parked, §1.5).
local VehicleKinds = require("@shared/Vehicles/VehicleKinds")
local PlayerVehicles = require("@shared/Vehicles/PlayerVehicles")

return function(t)
	t.test("VehicleKinds: the nine kinds, interiors with an eye socket, fleet membership", function()
		local ids = VehicleKinds.list()
		t.eq(table.concat(ids, ","), "car,cart,bike,pickup,suv,jetski,moped,escooter,ambulance")
		for _, id in ids do
			local k = VehicleKinds.kind(id)
			t.truthy(k.maxSpeed > 0 and k.wheelbase > 0 and #k.size == 3, id)
			t.eq(#k.interior.eye, 3, `{id} eye socket`)
			t.truthy(k.interior.eye[2] > k.interior.seat[2], `{id} eye above the seat`)
		end
		t.near(VehicleKinds.kind("car").size[3], 4.45 * 2.5, 1e-9, "sedan logical box (traffic §1)")
		t.truthy(
			VehicleKinds.isFleet("car") and not VehicleKinds.isFleet("bike"),
			"Q8: the patrol car in the fleet, bikes not"
		)
		-- owner D29: a shared vehicle's bump never kills (Server/Vehicles/RideBumps): no shared kind is in the fatal fleet
		for _, id in { "cart", "moped", "escooter" } do
			t.truthy(VehicleKinds.isShared(id) and not VehicleKinds.isFleet(id), `{id}: shared, not in the fatal fleet`)
		end
		t.truthy(VehicleKinds.kind("cart").maxSpeed < VehicleKinds.kind("car").maxSpeed, "carts are slow")
	end)

	t.test("VehicleKinds: the shared three (owner D29): who rides, the police, the feel", function()
		local shared = {}
		for _, id in VehicleKinds.list() do
			if VehicleKinds.isShared(id) then
				table.insert(shared, id)
			end
			-- no police trouble for the shared ones, the old rules for the rest
			t.eq(VehicleKinds.policeIgnore(id), VehicleKinds.isShared(id), `{id}: police ignore only the shared`)
		end
		t.eq(table.concat(shared, ","), "cart,moped,escooter")
		for _, id in shared do
			t.truthy((VehicleKinds.mayDrive(id, { human = true })), `{id}: any person, no key, no rental`)
			t.truthy(not (VehicleKinds.mayDrive(id, { human = false })), `{id}: never a squirrel or the rodent`)
		end
		-- the scooter about a brisk run (a person sprints at 28) and quick to turn, the cart in between, the moped quickest
		local sc, cart, moped = VehicleKinds.kind("escooter"), VehicleKinds.kind("cart"), VehicleKinds.kind("moped")
		t.truthy(sc.maxSpeed >= 18 and sc.maxSpeed <= 26, `escooter {sc.maxSpeed} st/s`)
		t.truthy(sc.maxSpeed < cart.maxSpeed and cart.maxSpeed < moped.maxSpeed, "escooter < cart < moped")
		t.truthy(sc.maxSteer > cart.maxSteer and sc.steerRate > moped.steerRate, "the scooter turns quickest")
		t.truthy(VehicleKinds.stands("escooter") and not VehicleKinds.stands("moped"), "the scooter's rider stands")
	end)

	t.test("VehicleKinds.mayDrive: anyone, key holders, officers with keys, rentals; people only", function()
		t.truthy((VehicleKinds.mayDrive("cart", {})), "carts: anyone")
		t.truthy((VehicleKinds.mayDrive("bike", {})), "bikes: anyone")
		t.truthy(not (VehicleKinds.mayDrive("pickup", {})), "pickup needs the key")
		t.truthy((VehicleKinds.mayDrive("suv", { keyHolder = true })), "suv with the key")
		t.truthy(not (VehicleKinds.mayDrive("car", { keyHolder = true })), "patrol car: police only")
		t.truthy((VehicleKinds.mayDrive("car", { keyHolder = true, officer = true })), "officer with the key")
		t.truthy(not (VehicleKinds.mayDrive("jetski", {})), "jet ski: rent first")
		t.truthy((VehicleKinds.mayDrive("jetski", { paidRental = true })))
		t.truthy(not (VehicleKinds.mayDrive("cart", { human = false })), "squirrels do not drive")
		-- D30: the ambulance is a doctor's alone
		t.deepEq(
			{ VehicleKinds.mayDrive("ambulance", { human = true, keyHolder = true, officer = true }) },
			{ false, "doctors only" }
		)
		t.truthy((VehicleKinds.mayDrive("ambulance", { human = true, doctor = true })))
		t.truthy(
			not (VehicleKinds.mayDrive("ambulance", { human = false, doctor = true })),
			"a doctor in a person's body"
		)
	end)

	t.test("PlayerVehicles: enter, occupied, one seat per driver, exit, invariants", function()
		local f = PlayerVehicles.new()
		PlayerVehicles.add(f, "c1", "cart", 0, 0, 0)
		PlayerVehicles.add(f, "c2", "cart", 10, 0, 0)
		t.truthy((PlayerVehicles.enter(f, "c1", 1, { human = true })))
		local ok, why = PlayerVehicles.enter(f, "c1", 2, { human = true })
		t.truthy(not ok and why == "occupied")
		ok, why = PlayerVehicles.enter(f, "c2", 1, { human = true })
		t.truthy(not ok and why == "already driving")
		t.eq(PlayerVehicles.vehicleOf(f, 1), "c1")
		t.eq(PlayerVehicles.exit(f, 1), "c1")
		t.eq(PlayerVehicles.vehicleOf(f, 1), nil)
		t.truthy((PlayerVehicles.check(f)))
	end)

	t.test(
		"keys: the top two get the pickups and SUVs; a key moves only once the vehicle is parked and empty",
		function()
			local f = PlayerVehicles.new()
			PlayerVehicles.add(f, "p1", "pickup", 0, 0, 0)
			PlayerVehicles.add(f, "s1", "suv", 0, 0, 0)
			PlayerVehicles.add(f, "car1", "car", 0, 0, 0)
			PlayerVehicles.grantKeys(f, "humanDriver", { 10, 20 })
			t.eq(PlayerVehicles.keyHolder(f, "p1"), 10)
			t.eq(PlayerVehicles.keyHolder(f, "s1"), 20)
			t.eq(PlayerVehicles.keyHolder(f, "car1"), nil, "patrol cars are the police group")
			t.truthy((PlayerVehicles.enter(f, "p1", 10, { human = true })))
			PlayerVehicles.setMotion(f, "p1", 20)
			-- 10 drops out of the top two while driving: keeps driving, key pending
			PlayerVehicles.grantKeys(f, "humanDriver", { 20, 30 })
			t.eq(PlayerVehicles.keyHolder(f, "p1"), 10, "still driving: the key stays")
			t.eq(PlayerVehicles.keyHolder(f, "s1"), 20, "holder keeps their own vehicle")
			PlayerVehicles.setMotion(f, "p1", 0)
			t.eq(PlayerVehicles.keyHolder(f, "p1"), 10, "parked but occupied: still theirs")
			PlayerVehicles.exit(f, 10)
			t.eq(PlayerVehicles.keyHolder(f, "p1"), 30, "parked and empty: the key passes")
			t.truthy(not (PlayerVehicles.enter(f, "p1", 10, { human = true })), "old holder refused")
			t.truthy((PlayerVehicles.enter(f, "p1", 30, { human = true })))
			PlayerVehicles.grantKeys(f, "police", { 7 })
			t.eq(PlayerVehicles.keyHolder(f, "car1"), 7)
			t.truthy(not (PlayerVehicles.enter(f, "car1", 7, { human = true })), "not an officer")
			t.truthy((PlayerVehicles.enter(f, "car1", 7, { human = true, officer = true })))
			t.truthy((PlayerVehicles.check(f)))
		end
	)
end
