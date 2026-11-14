--!strict
-- The alley roof run on the squirrel's own screen (BRIEF_ADDENDUM D9, lane L6), the pure parts:
--   * the hints on the way in, from the real motor: holding W to the house ridge's west end says "Jump now to reach
--     the branch", holding W to the end of the bough over the games wing's roof says "Q: drop onto the roof"
--     (Client/Controllers/Squirrel.feedback on the motor's own railEnd events); the other ends say nothing, nor
--     does any other route's end;
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

	t.test("routeHint: only the far ends of the ridge and the bough", function()
		t.eq(Squirrel.routeHint(AlleyRoof.RIDGE, 1), "Jump now to reach the branch")
		t.eq(Squirrel.routeHint(AlleyRoof.BOUGH, 1), "Q: drop onto the roof")
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
