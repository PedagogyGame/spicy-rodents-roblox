--!strict
-- W1 §4.4 #5: CameraPolicy modes (brief v2 §14), InputMap's pure parts and the controller choice.
local CameraPolicy = require("@client/Camera/CameraPolicy")
local InputMap = require("@client/Input/InputMap")
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
end
