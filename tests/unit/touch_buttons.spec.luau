--!strict
-- Owner D40: the touch screen's buttons (Client/UI/TouchButtons): which show for each body and place, that every
-- key a keyboard player has outside the minigames has a touch path, and that the slots keep clear of the other buttons.
local InputMap = require("@client/Input/InputMap")
local TouchButtons = require("@client/UI/TouchButtons")

local function set(list: { string }): { [string]: boolean }
	local s = {}
	for _, v in list do
		s[v] = true
	end
	return s
end

return function(t)
	t.test("each body and place shows its buttons, within the limits", function()
		local function both(ctx: TouchButtons.Context): { [string]: boolean }
			local a, g = TouchButtons.shows(ctx)
			t.truthy(#a <= TouchButtons.MAX_ACTIONS and #g <= TouchButtons.MAX_TOGGLES, `{#a} actions {#g} toggles`)
			local s = set(a)
			for _, v in g do
				s[v] = true
			end
			return s
		end
		local rodent = both({ role = "rodent", night = true })
		for _, id in { "leap", "bite", "grab", "drop", "feint", "run", "sneak", "night" } do
			t.truthy(rodent[id], id)
		end
		local sq = both({ role = "squirrel", night = true })
		t.truthy(sq.leap and sq.grab and sq.drop and sq.run and sq.sneak, "squirrel")
		t.truthy(not sq.bite and not sq.feint and not sq.night, "squirrel has no rodent buttons")
		local person = both({ role = "human", viewAllowed = true, nearVehicle = true })
		t.truthy(person.kick and person.enter and person.run and person.view, "person")
		t.truthy(not person.leap, "a person jumps with Roblox's own button")
		t.truthy(not both({ role = "human" }).enter, "IN only by a vehicle")
		local car = both({ role = "human", device = "vehicle", viewAllowed = true })
		t.truthy(car.brake and car.view and not car.kick, "driving")
		local drone = both({ role = "human", device = "drone" })
		t.truthy(drone.up and drone.down and drone.run, "drone")
		t.truthy(both({ role = "human", telescope = true }).back, "telescope")
		t.eq(next(both({ role = "human", seated = true })), nil)
		t.eq(next(both({ role = "rodent", minigame = true })), nil)
		t.eq(next(both({})), nil)
		local ctx = TouchButtons.contextOf({ species = "squirrel", variant = "spicy" }, false, false)
		t.eq(ctx.role, "rodent")
		t.truthy(TouchButtons.contextOf({}, false, true).minigame, "in a minigame")
	end)

	t.test("every keyboard verb outside the minigames has a touch path", function()
		-- the bar's keys, plus what already has one elsewhere (the reason in the comment)
		local elsewhere = {
			jump = true, -- a person: Roblox's jump button (animals: LEAP)
			chooseLeft = true, -- A/D at a fork: the thumbstick sideways (its move vector)
			chooseRight = true,
			trick = true, -- UI/AirTrickButton
			interact = true, -- IN here; GET OFF / LAND / RIDE in UI/RideHint
			handbrake = true, -- BRAKE (Space held)
		}
		local keys: { [string]: boolean } = {}
		for _, b in TouchButtons.BUTTONS do
			if b.key then
				keys[b.key] = true
			end
		end
		for verb, names in InputMap.BINDINGS :: { [string]: { string } } do
			local covered = elsewhere[verb] == true
			for _, n in names do
				covered = covered or keys[n] == true
			end
			t.truthy(covered, verb)
		end
	end)

	t.test("the slots keep clear of each other and of the other buttons", function()
		local function hit(a: { number }, b: { number }): boolean
			return a[1] < b[2] and b[1] < a[2] and a[3] < b[4] and b[3] < a[4]
		end
		local all = {}
		for _, r in TouchButtons.ACTION_SLOTS do
			table.insert(all, r)
		end
		for _, r in TouchButtons.TOGGLE_SLOTS do
			table.insert(all, r)
		end
		for i, r in all do
			for name, other in TouchButtons.AVOID do
				t.truthy(not hit(r, other), `slot {i} over {name}`)
			end
			for j = i + 1, #all do
				t.truthy(not hit(r, all[j]), `slots {i} and {j}`)
			end
			t.truthy(r[2] <= 400 and r[4] <= 310, `slot {i} out of the thumbstick and on a 375-high phone`)
		end
		-- LEAP takes the phone's jump spot: only for bodies with no Humanoid (no stock button)
		for _, role in { "human" } do
			local a = TouchButtons.shows({ role = role })
			t.truthy(table.find(a, "leap") == nil, role)
		end
	end)

	t.test("a tap presses the key for every listener and a hold keeps it down", function()
		local got = {}
		local off = InputMap.onKey(function(n)
			table.insert(got, n)
		end)
		InputMap.tap("E")
		off()
		InputMap.tap("F")
		t.eq(table.concat(got, ","), "E")
		InputMap.hold("LeftShift", true)
		t.truthy(InputMap.keyHeld("LeftShift"), "held")
		InputMap.hold("LeftShift", false)
		t.truthy(not InputMap.keyHeld("LeftShift"), "let go")
		t.eq(InputMap.stickPick(0, 0.8, true), 1)
		t.eq(InputMap.stickPick(0.8, 0.9, true), 0)
		t.eq(InputMap.stickPick(0, -0.7, true), -1)
		t.eq(InputMap.stickPick(0, 0.8, false), 0)
	end)
end
