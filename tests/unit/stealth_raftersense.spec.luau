--!strict
-- Stealth/RafterSense (BRIEF_ADDENDUM D9, lane L5): what the server reads from a squirrel's body over the alley's
-- lanes. The feet on a chord, a light rail, a brace or in the vent are located on that route at the right t; a
-- creep along chord 9120 reads as creeping (3 st/s) and a walk as walking; a leap between chords keeps the beam it
-- left and the landing is flagged once; out of the vent's boot onto the chord is not a landing; deep in the vent the
-- squirrel is hidden and at the louvre it is not; off the rafters (down on a lane, out on the roof) the watch ends;
-- and with the real RafterWatch a creep along the chord in front of a bowler is not spotted for 15 s while a walk is
-- within 1.5 s (the service's own tick, 5 Hz).
-- Combat/Cover with Combat/PlayRules: a box stops a kick and a bite from one side of it to the other, and does
-- nothing once removed.
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local AlleyRoof = require("@shared/Attractions/AlleyRoof")
local Curve = require("@shared/Routes/Curve")
local RafterSense = require("@shared/Stealth/RafterSense")
local RafterWatch = require("@shared/Stealth/RafterWatch")
local Cover = require("@shared/Combat/Cover")
local PlayRules = require("@shared/Combat/PlayRules")

local TICK = 0.2

-- the local point at arc-length t of a roof route
local function at(id: number, t: number): (number, number, number)
	local p = Curve.fromArrays(AlleyRoof.route(id).points):getPointAt(t)
	return p.x, p.y, p.z
end

return function(t)
	t.test("locate: chords, light rails, braces and the vent duct, at the right t; nothing off them", function()
		for _, id in RafterSense.ROUTES do
			for _, u in { 0.1, 0.5, 0.9 } do
				local X, Y, D = at(id, u)
				local got, gotT = RafterSense.locate(X, Y, D)
				-- (where two routes cross, either is right: check the point lies on what was found)
				t.truthy(got ~= nil, `route {id} at {u}`)
				local gx, gy, gz = at(got :: number, gotT)
				t.truthy(math.abs(gx - X) + math.abs(gy - Y) + math.abs(gz - D) < 0.5, `route {id} at {u} -> {got}`)
				if got == id then
					t.near(gotT, u, 0.01, `t on {id}`)
				end
			end
		end
		t.eq(#RafterSense.ROUTES, 20, "8 chords, 9 light rails, 2 braces and the vent")
		-- a stud to the side, two studs below, on the lane floor, out on the wing roof
		local X, Y, D = at(9120, 0.5)
		t.eq(RafterSense.locate(X, Y, D + 1.5), nil, "beside the chord")
		-- (between two lane pairs, where no light rail runs under the chord)
		local between = AlleyLayout.pairX(5) + AlleyLayout.PITCH
		t.eq(RafterSense.locate(between, Y - 2, D), nil, "under the chord")
		t.eq(RafterSense.locate(X, 0, D), nil, "on the lane")
		t.eq(RafterSense.locate(130, AlleyRoof.WING_ROOF.y, 0), nil, "on the wing roof")
		-- where the boot meets chord 9120 the chord wins
		t.eq(RafterSense.locate(AlleyRoof.BOOT.x0, AlleyRoof.CHORD.y1, 16.5), 9120)
	end)

	t.test("sense: creep and walk speeds, a leap between chords keeps its beam and lands once", function()
		local st = RafterSense.new()
		local X, Y, D = at(9120, 0.5)
		local first = RafterSense.sense(st, "sq", X, Y, D, TICK) :: RafterWatch.Squirrel
		t.eq(first.routeId, 9120)
		t.eq(first.speed, 0)
		t.truthy(first.focus and not first.landed and not first.hidden)
		local creep = RafterSense.sense(st, "sq", X - 3 * TICK, Y, D, TICK) :: RafterWatch.Squirrel
		t.near(creep.speed, 3, 1e-6)
		t.truthy(creep.focus, "3 st/s is a creep")
		local walk = RafterSense.sense(st, "sq", X - 3 * TICK - 18 * TICK, Y, D, TICK) :: RafterWatch.Squirrel
		t.near(walk.speed, 18, 1e-6)
		t.truthy(not walk.focus, "18 st/s is a walk")
		-- a leap from 9120 (D 16.5) toward 9124 (D 25.5): in the air it still counts on 9120
		local x = X - 4
		local air = RafterSense.sense(st, "sq", x, Y + 4, 21, TICK) :: RafterWatch.Squirrel
		t.eq(air.routeId, 9120, "in the air it counts on the beam it left")
		t.truthy(not air.landed)
		local land = RafterSense.sense(st, "sq", x, AlleyRoof.CHORD.y1, 25.5, TICK) :: RafterWatch.Squirrel
		t.eq(land.routeId, 9124)
		t.truthy(land.landed, "the first tick on a beam after the air is a landing")
		local after = RafterSense.sense(st, "sq", x - 0.5, AlleyRoof.CHORD.y1, 25.5, TICK) :: RafterWatch.Squirrel
		t.truthy(not after.landed, "once")
		-- down on a lane: gone
		t.eq(RafterSense.sense(st, "sq", x, 0, 25.5, TICK), nil)
		t.eq(st.tracks.sq, nil)
		-- a body that appears in the air of the roof space with no beam behind it is not watched
		t.eq(RafterSense.sense(st, "new", x, 16, 25.5, TICK), nil)
	end)

	t.test("sense: in the vent hidden away from its mouths; out of the boot onto the chord is no landing", function()
		local st = RafterSense.new()
		local mouth = RafterSense.sense(st, "sq", AlleyRoof.MOUTH.x, AlleyRoof.MOUTH.y, AlleyRoof.MOUTH.d, TICK)
		t.truthy(mouth ~= nil and mouth.routeId == AlleyRoof.VENT and not mouth.hidden, "at the louvre: in sight")
		for _, u in { 0.2, 0.5, 0.8 } do
			local X, Y, D = at(AlleyRoof.VENT, u)
			local s = RafterSense.sense(st, "sq", X, Y, D, TICK) :: RafterWatch.Squirrel
			t.truthy(s.hidden and s.routeId == AlleyRoof.VENT, `hidden at {u}`)
		end
		local X, Y, D = at(9120, 0.02)
		local out = RafterSense.sense(st, "sq", X, Y, D, TICK) :: RafterWatch.Squirrel
		t.eq(out.routeId, 9120)
		t.truthy(not out.landed and not out.hidden)
	end)

	t.test(
		"with RafterWatch at 5 Hz: a creep in front of a bowler is not spotted for 15 s, a walk and a sprint are",
		function()
			-- a bowler on lane 17's approach facing the pins, the squirrel on chord 9120 (D 16.5) ahead of them
			local bowler: RafterWatch.Observer =
				{ id = "b", X = AlleyLayout.laneX(17), Y = 5.2, D = -6, faceX = 0, faceD = 1 }
			-- the squirrel goes to and fro along the chord over lanes 15 to 18, in front of the bowler
			local function run(speed: number, seconds: number): number?
				local sense, watch = RafterSense.new(), RafterWatch.new()
				local X0, X1 = AlleyLayout.laneX(15), AlleyLayout.laneX(18)
				local X, dir = X1, -1
				local clock = 0
				while clock < seconds do
					local s = RafterSense.sense(sense, "sq", X, AlleyRoof.CHORD.y1, 16.5, TICK)
					for _, e in
						RafterWatch.step(watch, { s :: any }, { bowler }, nil, TICK, function()
							return true
						end)
					do
						if e.kind == "spotted" then
							return clock
						end
					end
					X += dir * speed * TICK
					if X < X0 or X > X1 then
						X = math.clamp(X, X0, X1)
						dir = -dir
					end
					clock += TICK
				end
				return nil
			end
			-- (the chord at D 16.5 runs between the lamps, dark: one bowler sees a walk in about 3.5 s, not the lit 1.25)
			t.eq(run(3, 15), nil, "creeping")
			local walked = run(18, 6)
			t.truthy(walked ~= nil and walked <= 4.5, `walking: {walked}`)
			local sprinted = run(30.5, 2)
			t.truthy(sprinted ~= nil and sprinted <= 1.5, `sprinting: {sprinted}`)
		end
	)

	t.test("Cover: a box stops a kick and a bite through its walls, and nothing once removed", function()
		Cover.clear()
		local place = { x = 1300, z = -420, floorY = 16.5, yaw = 0 }
		local key =
			Cover.add({ name = "unit", place = place, x0 = 104, x1 = 116, y0 = 13.6, y1 = 19, d0 = 11, d1 = 22 })
		local function w(X: number, Y: number, D: number): { id: string, x: number, y: number, z: number }
			local x, y, z = AlleyLayout.toWorld(place, X, Y, D)
			return { id = "?", x = x, y = y, z = z }
		end
		local guard = w(118.5, 16.7, 16.5)
		guard.id = "guard"
		local inside = w(113, 14.3, 16.5)
		inside.id = "inside"
		local mouth = w(117, 14.3, 16.5)
		mouth.id = "mouth"
		local look = { x = -1, z = 0 } -- facing the louvre (local -X is world -X at yaw 0)
		t.eq(PlayRules.kickTarget(guard, look, { inside }), nil, "through the housing")
		t.eq(PlayRules.kickTarget(guard, look, { inside, mouth }), "mouth", "at the louvre")
		t.eq(#PlayRules.biteVictims(inside, { guard }, 0, {}), 0, "no bite out through the wall")
		t.truthy(Cover.between(guard.x, guard.y, guard.z, inside.x, inside.y, inside.z))
		t.truthy(not Cover.between(guard.x, guard.y, guard.z, mouth.x, mouth.y, mouth.z))
		-- a turned frame: inside() follows the place's yaw
		local turned = { x = 10, z = -20, floorY = 3, yaw = math.pi / 2 }
		local box = { name = "turned", place = turned, x0 = -1, x1 = 1, y0 = 0, y1 = 2, d0 = 4, d1 = 6 }
		local ix, iy, iz = AlleyLayout.toWorld(turned, 0.5, 1, 5.5)
		local ox, oy, oz = AlleyLayout.toWorld(turned, 0.5, 1, 7)
		t.truthy(Cover.inside(box, ix, iy, iz), "inside, turned")
		t.truthy(not Cover.inside(box, ox, oy, oz), "outside, turned")
		t.truthy(not Cover.inside(box, ix, iy + 2.5, iz), "above")
		Cover.remove(key)
		t.eq(#Cover.list(), 0)
		t.eq(PlayRules.kickTarget(guard, look, { inside }), "inside", "no cover: the old reach")
	end)
end
