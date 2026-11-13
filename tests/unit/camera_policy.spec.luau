--!strict
-- W1 §4.4 #5: CameraPolicy modes (brief v2 §14), InputMap's pure parts and the controller choice.
local CameraPolicy = require("@client/Camera/CameraPolicy")
local InputMap = require("@client/Input/InputMap")
local CameraRig = require("@client/Camera/CameraRig")
local PossessionClient = require("@client/Possession/PossessionClient")

return function(t)
	t.test("CameraPolicy: animals third person, humans toggle, vehicles first person, locks and overrides", function()
		local m = CameraPolicy.modeFor
		t.eq(m({}).mode, "overview")
		t.eq(m({ species = "human" }).mode, "humanThird")
		t.eq(m({ species = "human", firstPersonToggle = true }).mode, "humanFirst")
		t.truthy(m({ species = "human" }).toggleAllowed)
		for _, sp in { "squirrel", "rodent", "fox", "deer" } do
			local d = m({ species = sp, firstPersonToggle = true })
			t.eq(d.mode, "animalThird", sp)
			t.truthy(not d.firstPerson and not d.toggleAllowed, `{sp}: no first person`)
		end
		t.eq(m({ species = "squirrel", chase = true }).mode, "chaseLock")
		t.eq(m({ species = "fox", chase = true }).mode, "animalThird", "chase lock is the squirrel's")
		local v = m({ species = "human", vehicle = "car", firstPersonToggle = true })
		t.truthy(v.mode == "vehicleFirst" and v.firstPerson and v.toggleAllowed)
		t.eq(m({ species = "human", vehicle = "car", firstPersonToggle = false }).mode, "vehicleThird")
		t.eq(m({ species = "human", vehicle = "gondola", firstPersonToggle = true }).mode, "vehicleFirst")
		local lock = m({ species = "human", zone = "lockFirstPerson", firstPersonToggle = false })
		t.truthy(lock.mode == "lockFirst" and lock.firstPerson and not lock.toggleAllowed)
		t.eq(m({ species = "human", drone = true }).mode, "drone")
		t.eq(m({ species = "squirrel", outbreak = true }).mode, "outbreak")
		for _, mode in CameraPolicy.MODES do
			t.truthy(type(mode) == "string")
		end
	end)

	t.test("InputMap: move vector mapping, reserved keys, fixed labyrinth, hints for every controller", function()
		local fw, side = InputMap.fromMoveVector(0, -1)
		t.eq(fw, 1)
		t.eq(side, 0)
		fw, side = InputMap.fromMoveVector(1, 0.1)
		t.eq(fw, 0, "dead zone")
		t.eq(side, 1)
		for _, names in InputMap.BINDINGS do
			for _, n in names do
				t.truthy(n ~= "Tab" and n ~= "Escape", `reserved key bound: {n}`)
			end
		end
		t.eq(InputMap.LABYRINTH.right, "Up", "Up is right (brief v2 §13a)")
		for _, role in { "human", "squirrel", "quadruped", "vehicle", "drone" } do
			t.truthy(#InputMap.HINTS(role) > 10, role)
		end
	end)

	t.test("controllerFor: humans, squirrels and the rodent, quadrupeds", function()
		t.eq(PossessionClient.controllerFor("human"), "human")
		t.eq(PossessionClient.controllerFor("squirrel", "normal"), "squirrel")
		t.eq(PossessionClient.controllerFor("squirrel", "spicy"), "squirrel")
		t.eq(PossessionClient.controllerFor("fox"), "quadruped")
		t.eq(PossessionClient.controllerFor("deer"), "quadruped")
	end)

	t.test("the gondola's free look (review: no test): yaw wraps, pitch clamps, I inverts, any start", function()
		local P = CameraRig.CABIN_PITCH
		local tau = 2 * math.pi
		-- the mouse right turns the view right (yaw down), all the way round and wrapped into [0, 2 pi)
		local yaw, pitch = 0.1, 0
		for _ = 1, 40 do
			yaw, pitch = CameraRig.cabinLook(yaw, pitch, 0.2, 0, false)
			t.truthy(yaw >= 0 and yaw < tau, `yaw {yaw} not wrapped`)
		end
		t.near(yaw, (0.1 - 8) % tau, 1e-9, "forty turns of 0.2")
		t.eq(pitch, 0)
		-- up and down: the mouse down looks down, clamped at the limits either way
		local _, down = CameraRig.cabinLook(0, 0, 0, 0.3, false)
		t.near(down, -0.3, 1e-9)
		local _, low = CameraRig.cabinLook(0, P.min + 0.1, 0, 5, false)
		t.eq(low, P.min)
		local _, high = CameraRig.cabinLook(0, P.max - 0.1, 0, -5, false)
		t.eq(high, P.max)
		-- I: inverted, the same mouse looks up
		local _, up = CameraRig.cabinLook(0, 0, 0, 0.3, true)
		t.near(up, 0.3, 1e-9)
		t.truthy(P.min < 0 and P.max > 0, "the limits straddle level")
	end)

	t.test("Reset in a cabin says where you get off and moves nothing; on foot it moves you (review)", function()
		t.eq(PossessionClient.resetWords(true, "ride", "summit"), PossessionClient.rideWords("summit"))
		t.eq(PossessionClient.resetWords(true, "ride", "base"), PossessionClient.rideWords("base"))
		t.truthy(string.find(PossessionClient.rideWords("base"), "bottom", 1, true) ~= nil)
		t.truthy(string.find(PossessionClient.rideWords("summit"), "top", 1, true) ~= nil)
		t.eq(PossessionClient.resetWords(true, nil, nil), nil, "on foot Reset moves the body")
		t.eq(PossessionClient.resetWords(true, "vehicle", nil), nil, "a car is not a ride")
		t.truthy(PossessionClient.resetWords(false, nil, nil) ~= nil, "no body: words, not a silent press")
	end)
end
