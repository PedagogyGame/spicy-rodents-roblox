--!strict
-- The responder ambulance as the medical sequence drives it (owner 2026-11-10: "there should be an
-- ambulance come"): a routed dispatch stays on the roads all the way (the W1 trunk-plus-L stand-in
-- does not), a held responder waits on scene until it is released, a release on the way turns it
-- round on arrival, and the three responders can be dispatched again after they come home.
local Data = require("@shared/Data")
local Town = require("@shared/World/Town")
local MedicalRoute = require("@shared/Infection/MedicalRoute")
local LaneMath = require("@shared/Traffic/LaneMath")
local TrafficService = require("@server/Traffic/TrafficService")

return function(t)
	local records = require("../../generated/Lanes") :: any
	local roadRecords = require("../../generated/Roads") :: any
	local data = Data.default()
	local town = Town.fromData(data)
	local roads = MedicalRoute.build(town.strips :: any)

	local function service()
		return TrafficService.new({ lanes = records, roads = roadRecords, seed = 3 })
	end

	-- drive until `stop(v)`; returns the seconds taken and the worst distance off asphalt
	local function drive(svc: any, v: any, limit: number, stop: (v: any) -> boolean): (number, number)
		local secs, worst = 0, 0
		while secs < limit and not stop(v) do
			svc:step(1 / 30, {})
			secs += 1 / 30
			if v.visible then
				-- the lane keeps right of the centreline by POLY_OFFSET; the join gaps are documented
				local off = 0
				while off < 60 and not MedicalRoute.onRoad(roads, v.x, v.z, off) do
					off += 1
				end
				worst = math.max(worst, off)
			end
		end
		return secs, worst
	end

	t.test("the responders park on the hospital drive and all three are free at the start", function()
		local svc = service()
		t.deepEq(svc:responderHome(), { -890, 737.5 })
		t.eq(svc:responderIdle(), 3)
	end)

	t.test("a routed dispatch to a mid-block stop never leaves the roads; the stand-in L does", function()
		local svc = service()
		local home = svc:responderHome() :: { number }
		local stage = MedicalRoute.stage(roads, 100, 250) :: MedicalRoute.Stage
		local trip = MedicalRoute.trip(roads, home, stage) :: { { number } }
		local v = svc:dispatchResponder({ stage.x, stage.z }, { route = trip, hold = true })
		t.truthy(v ~= nil)
		t.eq(v.phase, "out")
		t.truthy(v.visible, "it appears on the drive")
		local secs, worst = drive(svc, v, 200, function(veh: any): boolean
			return veh.phase == "hold"
		end)
		t.eq(v.phase, "hold")
		t.truthy(worst <= MedicalRoute.JOIN_GAP, `{worst} studs off the road at worst`)
		t.truthy(
			math.abs(v.x - stage.x) <= LaneMath.POLY_OFFSET + 0.5
				and math.abs(v.z - stage.z) <= LaneMath.POLY_OFFSET + 0.5
		)
		t.truthy(secs > 10 and secs < 90, `{secs} s to drive {MedicalRoute.length(trip)} studs`)
		-- the same stop through the old trunk-plus-L: it drives up through the house blocks
		local old = service()
		local w = old:dispatchResponder({ 100, 250 })
		local _, oldWorst = drive(old, w, 200, function(veh: any): boolean
			return veh.phase == "hold"
		end)
		t.truthy(oldWorst > 40, `the L tail was {oldWorst} studs off the road (the reason for routed trips)`)
	end)

	t.test("held: on scene until released, however long; then home, hidden and free again", function()
		local svc = service()
		local home = svc:responderHome() :: { number }
		local stage = MedicalRoute.stage(roads, -800, 300) :: MedicalRoute.Stage
		local trip = MedicalRoute.trip(roads, home, stage) :: { { number } }
		local v = svc:dispatchResponder({ stage.x, stage.z }, { route = trip, hold = true })
		drive(svc, v, 120, function(veh: any): boolean
			return veh.phase == "hold"
		end)
		t.eq(v.phase, "hold")
		for _ = 1, 30 * 120 do
			svc:step(1 / 30, {})
		end
		t.eq(v.phase, "hold", "still there two minutes later (the plain scene timer is 30 s)")
		t.truthy(v.visible)
		t.eq(svc:responderIdle(), 2)
		svc:releaseResponder(v)
		local back, worst = drive(svc, v, 120, function(veh: any): boolean
			return veh.phase == "idle"
		end)
		t.eq(v.phase, "idle")
		t.truthy(not v.visible, "hidden when parked")
		t.truthy(back > 3 and back < 60, `{back} s home`)
		t.truthy(worst <= MedicalRoute.JOIN_GAP)
		t.eq(svc:responderIdle(), 3)
		-- and it goes out again
		local again = svc:dispatchResponder({ stage.x, stage.z }, { route = trip, hold = true })
		t.eq(again, v, "the first idle responder")
		t.eq(v.phase, "out")
	end)

	t.test("released on the way: it still drives to the scene, turns straight round and comes home", function()
		local svc = service()
		local home = svc:responderHome() :: { number }
		local stage = MedicalRoute.stage(roads, -800, 300) :: MedicalRoute.Stage
		local trip = MedicalRoute.trip(roads, home, stage) :: { { number } }
		local v = svc:dispatchResponder({ stage.x, stage.z }, { route = trip, hold = true })
		for _ = 1, 60 do
			svc:step(1 / 30, {})
		end
		t.eq(v.phase, "out")
		svc:releaseResponder(v)
		local secs = drive(svc, v, 200, function(veh: any): boolean
			return veh.phase == "idle"
		end)
		t.eq(v.phase, "idle")
		t.truthy(secs < 60, `{secs} s: no 30 s wait on scene`)
		t.truthy((svc:stats().events.arrived or 0) == 1 and (svc:stats().events.home or 0) == 1)
	end)

	t.test("unheld dispatches keep the plain scene timer; three at once, a fourth is refused", function()
		local svc = service()
		local home = svc:responderHome() :: { number }
		local stage = MedicalRoute.stage(roads, -800, 300) :: MedicalRoute.Stage
		local trip = MedicalRoute.trip(roads, home, stage) :: { { number } }
		local a = svc:dispatchResponder({ stage.x, stage.z }, { route = trip })
		local b = svc:dispatchResponder({ stage.x, stage.z }, { route = trip, hold = true })
		local c = svc:dispatchResponder({ stage.x, stage.z }, { route = trip, hold = true })
		t.truthy(a and b and c and a ~= b and b ~= c)
		t.eq(svc:dispatchResponder({ stage.x, stage.z }, { route = trip, hold = true }), nil, "all three are out")
		t.eq(svc:responderIdle(), 0)
		local secs = drive(svc, a, 200, function(veh: any): boolean
			return veh.phase == "idle"
		end)
		t.truthy(secs > 30 and secs < 100, `the unheld one waited its 30 s and came home ({secs} s)`)
		t.eq(b.phase, "hold")
		t.eq(c.phase, "hold")
		svc:releaseResponder(b)
		svc:releaseResponder(c)
		drive(svc, c, 200, function(): boolean
			return svc:responderIdle() == 3
		end)
		t.eq(svc:responderIdle(), 3)
		-- releasing a parked or a non-responder vehicle is harmless
		svc:releaseResponder(a)
		svc:releaseResponder(svc.vehicles[1])
		t.eq(svc.vehicles[1].held, nil)
	end)
end
