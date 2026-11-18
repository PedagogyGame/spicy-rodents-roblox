--!strict
-- The alley roof run on the squirrel's own screen (BRIEF_ADDENDUM D9, lane L6), the pure parts:
--   * the hints on the way in, from the real motor: holding W to the house ridge's west end says "Jump now to reach
--     the branch", holding W to the end of the bough over the games wing's roof says "Q: drop onto the roof"
--     (Client/Controllers/Squirrel.feedback on the motor's own railEnd events); at the gutter's top with the view
--     turned away from the tree (where the motor stops: the ridge leaves at a right angle) "Turn toward the tree",
--     and turning on runs along the ridge; out of the vent's boot onto the first truss, the rafters' keys; the other
--     ends say nothing, nor does any other route's end;
--   * the sneak meter's look (Client/UI/SneakMeter.look): hidden off the rafters, a calm amber eye, "They're
--     watching: creep (hold Ctrl) or get back in the vent" past WATCH (kept until it falls under CALM), and
--     "Spotted!" over a full red eye.
local AlleyRoof = require("@shared/Attractions/AlleyRoof")
local Curve = require("@shared/Routes/Curve")
local Registry = require("@shared/Routes/Registry")
local SpatialIndex = require("@shared/Routes/SpatialIndex")
local Graph = require("@shared/Routes/Graph")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local Squirrel = require("@client/Controllers/Squirrel")
local SneakMeter = require("@client/UI/SneakMeter")

local PLACE = { x = 1300, z = -420, floorY = 16.5, yaw = 0 }

return function(t)
	local registry = Registry.fromRecords(AlleyRoof.records(PLACE) :: any)
	local index = SpatialIndex.build(registry)
	local world = {
		registry = registry,
		index = index,
		graph = Graph.build(registry, index, nil),
		trampolines = {},
		groundAt = function(_x: number, _z: number, _y: number): number
			return -100 -- (nothing to land on: the squirrel stays on the route)
		end,
		blocked = function(): boolean
			return false
		end,
	}
	local function pt(id: number, u: number): Curve.Vec3
		return registry:pointAt(registry:get(id) :: Registry.Route, u)
	end

	-- hold W along route `id` from `u0` toward its end, the camera behind looking at the end; what the squirrel is
	-- told each frame (Squirrel.feedback with the frame's events), and where it stopped
	local function holdW(id: number, u0: number, seconds: number): ({ string }, SquirrelMotor.State)
		local p = pt(id, u0)
		local state = SquirrelMotor.new(p.x, p.y, p.z)
		state.routeId, state.railT, state.railDir, state.grounded = id, u0, 1, false
		local said: { string } = {}
		local goal = pt(id, 1)
		for _ = 1, math.ceil(seconds * 60) do
			local input = SquirrelMotor.idleInput(0)
			input.fw = 1
			input.cameraYaw = math.atan2(-(goal.x - state.x), -(goal.z - state.z))
			local wasOn = state.routeId ~= nil
			local _, events = SquirrelMotor.step(state, input, 1 / 60, world :: any)
			local say = Squirrel.feedback(input :: any, events :: any, wasOn, state.railT)
			if say and said[#said] ~= say then
				table.insert(said, say)
			end
		end
		return said, state
	end

	-- hold W on route `id` from `u0` for `seconds` with the camera at `yaw(state)` (world yaw); what was said, the
	-- routes ridden, and the state
	local function holdWYaw(
		id: number,
		u0: number,
		seconds: number,
		yaw: (SquirrelMotor.State) -> number
	): ({ string }, { number }, SquirrelMotor.State)
		local p = pt(id, u0)
		local state = SquirrelMotor.new(p.x, p.y, p.z)
		state.routeId, state.railT, state.railDir, state.grounded = id, u0, 1, false
		local said: { string } = {}
		local rode = { id }
		for _ = 1, math.ceil(seconds * 60) do
			local input = SquirrelMotor.idleInput(yaw(state))
			input.fw = 1
			local wasOn = state.routeId ~= nil
			local _, events = SquirrelMotor.step(state, input, 1 / 60, world :: any)
			local say = Squirrel.feedback(input :: any, events :: any, wasOn, state.railT)
			if say and said[#said] ~= say then
				table.insert(said, say)
			end
			if state.routeId and rode[#rode] ~= state.routeId then
				table.insert(rode, state.routeId)
			end
		end
		return said, rode, state
	end
	-- the world yaw whose camera looks along the alley's local (dX, dD) (place yaw 0: x = X, z = -D)
	local function yawLocal(dX: number, dD: number): number
		return math.atan2(-dX, dD)
	end

	t.test(
		"the gutter's top with the view turned from the tree: 'Turn toward the tree', then on along the ridge",
		function()
			-- looking up the slope and a little east (the camera of someone who climbed from the north-east)
			local away = yawLocal(0.5, 1)
			local said, rode, state = holdWYaw(AlleyRoof.GUTTER, 0.9, 1.5, function()
				return away
			end)
			t.eq(state.routeId, AlleyRoof.GUTTER, `stopped at the gutter's top (rode {table.concat(rode, " ")})`)
			t.near(state.railT, 1, 1e-6)
			t.eq(table.concat(said, " | "), "Turn toward the tree: the ridge runs that way")
			-- turning the view toward the tree (west) runs on along the ridge, and nothing more is said on the way
			local said2, rode2 = holdWYaw(AlleyRoof.GUTTER, 0.9, 1.5, function(st: SquirrelMotor.State): number
				return if st.routeId == AlleyRoof.GUTTER and st.railT < 0.999 then away else yawLocal(-1, 0)
			end)
			t.eq(table.concat(rode2, " "), "9102 9103", "on along the ridge once the view is turned")
			-- (said once, at the stop; then the ridge's own end: "Jump now")
			t.eq(
				table.concat(said2, " | "),
				"Turn toward the tree: the ridge runs that way | Jump now to reach the branch"
			)
			-- looking up the slope, straight or turned toward the tree, it never stops
			for _, dir in { { 0, 1 }, { -0.5, 1 }, { -1, 1 } } do
				local said3, rode3 = holdWYaw(AlleyRoof.GUTTER, 0.9, 1, function()
					return yawLocal(dir[1], dir[2])
				end)
				t.eq(table.concat(rode3, " "), "9102 9103", `looking ({dir[1]}, {dir[2]})`)
				t.eq(#said3, 0)
			end
		end
	)

	t.test("out of the vent's boot onto the first truss: the rafters' keys, once", function()
		local said, rode = holdWYaw(AlleyRoof.VENT, 0.97, 1, function()
			return yawLocal(-1, 0)
		end)
		t.eq(table.concat(rode, " "), "9107 9120")
		t.eq(table.concat(said, " | "), Squirrel.RAFTERS_HINT)
		t.eq(
			Squirrel.feedback({ fw = 1 }, { { kind = "autoSwitch", routeId = 9120, fromRouteId = 9139 } }, true, 0),
			nil
		)
	end)

	t.test("the motor at the ridge's west end: 'Jump now to reach the branch'", function()
		local said, state = holdW(AlleyRoof.RIDGE, 0.8, 2)
		t.eq(state.routeId, AlleyRoof.RIDGE, "W stops the squirrel at the end")
		t.near(state.railT, 1, 1e-6)
		t.eq(table.concat(said, " | "), "Jump now to reach the branch")
	end)

	t.test("the motor at the end of the bough over the wing roof: 'Q: drop onto the roof'", function()
		local said, state = holdW(AlleyRoof.BOUGH, 0.85, 2)
		t.eq(state.routeId, AlleyRoof.BOUGH)
		t.near(state.railT, 1, 1e-6)
		t.eq(table.concat(said, " | "), "Q: drop onto the roof")
	end)

	t.test("routeHint: only the far ends of the way in (downspout, gutter, ridge, bough)", function()
		t.eq(Squirrel.routeHint(AlleyRoof.RIDGE, 1), "Jump now to reach the branch")
		t.eq(Squirrel.routeHint(AlleyRoof.BOUGH, 1), "Q: drop onto the roof")
		t.eq(Squirrel.routeHint(AlleyRoof.GUTTER, 1), "Turn toward the tree: the ridge runs that way")
		t.eq(Squirrel.routeHint(AlleyRoof.DOWNSPOUT, 1), "Face the roof and hold W to climb on")
		t.eq(Squirrel.routeHint(AlleyRoof.GUTTER, 0), nil)
		t.eq(Squirrel.routeHint(AlleyRoof.RIDGE, 0), nil, "the ridge's east end leads on to the gutter")
		t.eq(Squirrel.routeHint(AlleyRoof.BOUGH, 0), nil, "the bough's house end")
		t.eq(Squirrel.routeHint(9120, 1), nil)
		t.eq(Squirrel.routeHint(nil, 1), nil)
		-- a railEnd anywhere else says nothing new; the motor's own hints still come first
		local idle = { fw = 1, grab = false, drop = false }
		t.eq(Squirrel.feedback(idle, { { kind = "railEnd", routeId = 9120 } }, true, 1), nil)
		t.eq(
			Squirrel.feedback(
				idle,
				{ { kind = "hint", reason = "noRoom" }, { kind = "railEnd", routeId = 9103 } },
				true,
				1
			),
			"No room to jump in here: run on to an opening"
		)
		t.eq(Squirrel.feedback(idle, { { kind = "railEnd", routeId = 9103 } }, true), nil, "no t: nothing")
	end)

	t.test("SneakMeter.look: hidden, calm, watched (with its words held until it calms), spotted", function()
		local hidden = SneakMeter.look(nil, nil)
		t.eq(hidden.visible, false)
		local calm = SneakMeter.look(0.1, false)
		t.eq(calm.state, "calm")
		t.near(calm.fill, 0.1, 1e-9)
		t.eq(calm.words, nil)
		t.eq(calm.shout, nil)
		local watched = SneakMeter.look(0.4, false)
		t.eq(watched.state, "watched")
		t.eq(watched.words, "They're watching: creep (hold Ctrl) or get back in the vent")
		t.eq(SneakMeter.look(0.3, false, true).state, "watched", "held between CALM and WATCH")
		t.eq(SneakMeter.look(0.3, false, false).state, "calm", "not yet watched")
		t.eq(SneakMeter.look(0.2, false, true).state, "calm", "back under CALM")
		local spotted = SneakMeter.look(1, true)
		t.eq(spotted.state, "spotted")
		t.eq(spotted.shout, "Spotted!")
		t.eq(spotted.words, "They're watching: creep (hold Ctrl) or get back in the vent")
		t.eq(spotted.fill, 1)
		-- the eye reddens as it fills
		t.truthy(SneakMeter.look(0.9, false).color[2] < watched.color[2], "redder when fuller")
		for _, look in { calm, watched, spotted } do
			for _, c in look.color do
				t.truthy(c >= 0 and c <= 255 and c == math.floor(c))
			end
		end
	end)
end
