--!strict
-- The responder ambulance as the medical sequence drives it (owner 2026-11-10: "there should be an
-- ambulance come"): the three stand parked in view at the kerb of the hospital road (they used to be
-- hidden, and popped into existence on the hospital drive when called), a dispatch pulls out of its bay
-- and stays on the roads all the way, routed by the caller or by the service itself, a held responder
-- waits on scene until it is released, a release on the way turns it round on arrival, and each comes
-- home into its own bay and can be dispatched again. The
-- responder is one of the fleet: it reaches the clients in the fleet's own pose stream (an even 15
-- sends a second, each carrying the server's clock: Traffic/Ghost), with nothing of its own.
local Data = require("@shared/Data")
local Town = require("@shared/World/Town")
local MedicalRoute = require("@shared/Infection/MedicalRoute")
local LaneMath = require("@shared/Traffic/LaneMath")
local AICarMotor = require("@shared/Traffic/AICarMotor")
local Ghost = require("@shared/Traffic/Ghost")
local PoseStream = require("@shared/Traffic/PoseStream")
local Schemas = require("@shared/Net/Schemas")
local Net = require("@shared/Net/Net")
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

	t.test("the responders stand parked at the hospital road's kerb, in view, and all three are free", function()
		local svc = service()
		-- their trips are routed from where the hospital drive meets the hospital road
		t.deepEq(svc:responderHome(), { -890, 707.5 })
		t.eq(svc:responderIdle(), 3)
		local xs = {}
		for _, v in svc.vehicles do
			if v.class == "responder" then
				t.truthy(v.visible, `{v.name} is in view`)
				t.eq(v.phase, "idle")
				-- on the north kerb (the road is 30 st wide about z = 707.5), facing east, on asphalt
				t.near(v.z, 707.5 + 15 - 3.5, 1e-6)
				t.near(v.yaw, math.pi / 2, 1e-9)
				t.truthy(MedicalRoute.onRoad(roads, v.x, v.z, -v.box.width / 2), "its whole width on the road")
				table.insert(xs, v.x)
			end
		end
		t.deepEq(xs, { -924, -962, -1000 }, "34 st back from the junction, then 38 st apart")
		-- and they stay put: nothing moves a parked ambulance
		for _ = 1, 300 do
			svc:step(1 / 30, {})
		end
		for i, v in svc.vehicles do
			if v.class == "responder" then
				t.truthy(v.visible and v.speed == 0)
				t.near(v.z, 719, 1e-6, `{i}`)
			end
		end
	end)

	t.test("a dispatch to a mid-block stop never leaves the roads, routed by the caller or by the service", function()
		local svc = service()
		local home = svc:responderHome() :: { number }
		local stage = MedicalRoute.stage(roads, 100, 250) :: MedicalRoute.Stage
		local trip = MedicalRoute.trip(roads, home, stage) :: { { number } }
		local v = svc:dispatchResponder({ stage.x, stage.z }, { route = trip, hold = true })
		t.truthy(v ~= nil)
		t.eq(v.phase, "out")
		t.truthy(v.visible and not v.teleported, "it was in view at its bay: nothing appears, nothing jumps")
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
		-- the same call with no route given: the service finds the way by road itself (the W1 stand-in
		-- drove the trunk and then an L up through the house blocks, 40 st and more off any road)
		local own = service()
		local w = own:dispatchResponder({ 100, 250 })
		local _, ownWorst = drive(own, w, 200, function(veh: any): boolean
			return veh.phase == "hold"
		end)
		t.eq(w.phase, "hold")
		t.truthy(ownWorst <= MedicalRoute.JOIN_GAP, `{ownWorst} studs off the road at worst`)
		t.truthy(
			math.abs(w.x - stage.x) <= LaneMath.POLY_OFFSET + 0.5
				and math.abs(w.z - stage.z) <= LaneMath.POLY_OFFSET + 0.5,
			"at the point of the roads nearest the call"
		)
	end)

	t.test("held: on scene until released, however long; then home into its bay, in view and free again", function()
		local svc = service()
		local home = svc:responderHome() :: { number }
		local stage = MedicalRoute.stage(roads, -800, 300) :: MedicalRoute.Stage
		local trip = MedicalRoute.trip(roads, home, stage) :: { { number } }
		local bayX, bayZ, bayYaw = svc.byId[15].x, svc.byId[15].z, svc.byId[15].yaw
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
		t.truthy(v.visible, "parked in view")
		t.near(v.x, bayX, 1e-6, "in the bay it left")
		t.near(v.z, bayZ, 1e-6)
		t.near(v.yaw, bayYaw, 1e-6, "facing the way it will leave")
		t.eq(v.speed, 0)
		t.truthy(back > 3 and back < 70, `{back} s home`)
		t.truthy(worst <= MedicalRoute.JOIN_GAP)
		t.eq(svc:responderIdle(), 3)
		-- and it goes out again
		local again = svc:dispatchResponder({ stage.x, stage.z }, { route = trip, hold = true })
		t.eq(again, v, "the first idle responder")
		t.eq(v.phase, "out")
	end)

	t.test(
		"a dispatched ambulance is seen through the fleet's pose stream: stamped sends, in view from its bay and back, an even drive",
		function()
			local svc = service()
			local sent: { buffer } = {}
			local net = Net.new({
				send = function(_player: any, _name: string, payload: any)
					table.insert(sent, payload)
				end,
				players = function(): { any }
					return {}
				end,
			})
			-- the server's frame as Boot/Game runs it (TrafficService.frame: traffic, then one stamped send
			-- every 1/15 s) and the client's side of it as Render/VehicleView does (PoseStream's receiver:
			-- the packet in, then once a frame the instant to draw); the packets arrive with up to 40 ms
			-- of jitter
			local receiver = PoseStream.newReceiver()
			local now, sends, drawAt = 0, 0, 0
			local lag = 0.05
			local function frame(dt: number)
				now += dt
				svc:frame(dt, now, {}, net)
				while #sent > 0 do
					local payload = table.remove(sent, 1) :: buffer
					local stamp = Ghost.takeStamp(Net.decodeStream(Schemas.VehiclePose, payload))
					t.truthy(
						stamp ~= nil and math.abs((stamp :: number) - (now - svc.acc)) < 1e-3,
						"every send carries the server's clock at the tick its state is from"
					)
					sends += 1
					t.truthy(receiver:packet(payload, now + lag + (sends * 7 % 5) * 0.01))
				end
				drawAt = receiver:at(now, dt)
			end
			local buf = receiver.buffer
			for _ = 1, 120 do
				frame(1 / 60)
			end
			local home = svc:responderHome() :: { number }
			local stage = MedicalRoute.stage(roads, 100, 250) :: MedicalRoute.Stage
			local trip = MedicalRoute.trip(roads, home, stage) :: { { number } }
			-- parked: in the stream like every vehicle, and drawn where it stands
			local id = nil
			for _, v in svc.vehicles do
				if v.class == "responder" and id == nil then
					id = v.id
				end
			end
			local bayX, bayZ = svc.byId[id].x, svc.byId[id].z
			local parked = buf:sample(drawAt)[id]
			t.truthy(parked ~= nil, "the parked responder is in the stream")
			t.truthy(parked.visible and parked.stopped, "in view, standing")
			t.truthy(math.sqrt((parked.x - bayX) ^ 2 + (parked.z - bayZ) ^ 2) < 0.1, "at its bay")
			local v = svc:dispatchResponder({ stage.x, stage.z }, { route = trip, hold = true })
			t.eq(v.id, id)
			-- drawn at 60 Hz from the buffer: where the ghost is, frame by frame
			local seen, worstStep, snaps, first = 0, 0, 0, nil :: any
			local last: any = nil
			local function watch()
				local p = buf:sample(drawAt)[id]
				if p and p.visible then
					seen += 1
					first = first or p
					t.truthy(p.beacons, "the beacons are on")
					if p.teleported then
						-- a jump the server flagged would be drawn as a snap: there is none on a trip
						if last and not last.teleported then
							snaps += 1
						end
					elseif last and not last.teleported then
						worstStep = math.max(worstStep, math.sqrt((p.x - last.x) ^ 2 + (p.z - last.z) ^ 2))
					end
					last = p
				else
					last = nil
				end
			end
			local secs = 0
			while secs < 200 and v.phase ~= "hold" do
				frame(1 / 60)
				secs += 1 / 60
				watch()
			end
			t.eq(v.phase, "hold")
			t.truthy(seen > 300, `the ghost was drawn on {seen} frames of the drive`)
			t.truthy(
				math.sqrt((first.x - bayX) ^ 2 + (first.z - bayZ) ^ 2) < 1,
				`it pulls out from where it stood, it does not appear somewhere ({first.x}, {first.z})`
			)
			-- an even drive: no frame moves it further than its top speed allows (no freeze and catch-up)
			local top = 0
			for _, s in v.lane.speeds do
				top = math.max(top, s)
			end
			t.truthy(worstStep <= top / 60 * 1.6 + 0.3, `{worstStep} studs in one frame (top speed {top} studs/s)`)
			-- on scene it stands still, held; released, it drives home and is hidden again
			for _ = 1, 60 do
				frame(1 / 60)
				watch()
			end
			local held = buf:sample(drawAt)[id]
			t.truthy(held.visible and held.stopped, "standing on scene")
			t.truthy(math.sqrt((held.x - v.x) ^ 2 + (held.z - v.z) ^ 2) < 0.5, "exactly where the server has it")
			svc:releaseResponder(v)
			secs = 0
			while secs < 200 and v.phase ~= "idle" do
				frame(1 / 60)
				secs += 1 / 60
				watch()
			end
			for _ = 1, 30 do
				frame(1 / 60)
			end
			t.eq(v.phase, "idle")
			local back = buf:sample(drawAt)[id]
			t.truthy(back.visible and back.stopped, "in view at home")
			t.truthy(math.sqrt((back.x - bayX) ^ 2 + (back.z - bayZ) ^ 2) < 0.1, "back in its bay")
			t.truthy(worstStep <= top / 60 * 1.6 + 0.3, `{worstStep} studs in one frame on the way home`)
			-- turning round at the scene is a U-turn it drives, onto the other side of the road (it used
			-- to flip round on the spot and jump 15 st sideways): nothing on the way out, at the scene or
			-- on the way home is a snap
			t.eq(snaps, 0, "no snap: it drives the turn at the scene")
			-- nothing about a call is a jump any more, so no send carries a flag for it
			local svc2 = service()
			local v2 = svc2:dispatchResponder({ stage.x, stage.z }, { route = trip, hold = true })
			local function flagged(): boolean
				for _, r in svc2:poseRecords() do
					if r.id == v2.id then
						return Ghost.decode(r).teleported
					end
				end
				return false
			end
			t.truthy(not v2.teleported, "pulling out of its bay is not a jump")
			svc2:step(1 / 30, {})
			svc2:step(1 / 30, {})
			t.truthy(not flagged(), "and the next send says so")
			drive(svc2, v2, 200, function(veh: any): boolean
				return veh.phase == "hold"
			end)
			svc2:poseRecords()
			svc2:releaseResponder(v2)
			svc2:step(1 / 30, {})
			t.eq(v2.phase, "turn")
			-- the turn: a half circle of POLY_OFFSET, driven, ending on the return side facing home
			local sx, sz, syaw = v2.x, v2.z, v2.yaw
			local turnSecs, worstTurn = 0, 0
			-- (it waits for a gap in the traffic on the main street before it swings out)
			while v2.phase == "turn" and turnSecs < 90 do
				local px, pz = v2.x, v2.z
				svc2:step(1 / 30, {})
				turnSecs += 1 / 30
				worstTurn = math.max(worstTurn, math.sqrt((v2.x - px) ^ 2 + (v2.z - pz) ^ 2))
				t.truthy(not v2.teleported, "no tick of the turn is a jump")
			end
			t.eq(v2.phase, "back")
			t.truthy(worstTurn < 1, `{worstTurn} studs in one tick of the turn`)
			t.truthy(turnSecs > 2 and turnSecs < 90, `{turnSecs} s to turn round`)
			t.near(math.sqrt((v2.x - sx) ^ 2 + (v2.z - sz) ^ 2), 2 * LaneMath.POLY_OFFSET, 1.5)
			t.near(math.abs(math.atan2(math.sin(v2.yaw - syaw), math.cos(v2.yaw - syaw))), math.pi, 0.05)
			t.truthy(not flagged(), "nothing to flag")
			t.truthy(math.abs(sends - now * 15) <= 2, `{sends} sends in {now} s: an even 15 a second`)
		end
	)

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

	t.test(
		"a person standing in the way is waited for, but not for ever: the responder edges past, reaches its scene and comes home",
		function()
			local home = service():responderHome() :: { number }
			local stage = MedicalRoute.stage(roads, -800, 300) :: MedicalRoute.Stage
			local trip = MedicalRoute.trip(roads, home, stage) :: { { number } }
			-- the same trip with nobody about: how long it takes out and back
			local clear = service()
			local c = clear:dispatchResponder({ stage.x, stage.z }, { route = trip, hold = true })
			local clearOut = drive(clear, c, 200, function(veh: any): boolean
				return veh.phase == "hold"
			end)
			clear:releaseResponder(c)
			local clearBack = drive(clear, c, 200, function(veh: any): boolean
				return veh.phase == "idle"
			end)
			-- a townsperson a player holds, standing in the road just in front of the first responder's
			-- bay (the walk to the hospital door every infected player is sent on passes here): not one
			-- of the hospital's own, so the hard stop applies
			local first = service().byId[15]
			local world = { people = { { kind = "human", x = first.x + 8, y = 0, z = first.z - 1.5, visible = true } } }
			local function run(svc: any, v: any, limit: number, stop: (v: any) -> boolean): number
				local secs = 0
				while secs < limit and not stop(v) do
					svc:step(1 / 30, world)
					secs += 1 / 30
				end
				return secs
			end
			local svc = service()
			local v = svc:dispatchResponder({ stage.x, stage.z }, { route = trip, hold = true })
			local x0, z0 = v.x, v.z
			run(svc, v, AICarMotor.BLOCK_PATIENCE - 0.5, function(): boolean
				return false
			end)
			t.truthy(math.abs(v.x - x0) + math.abs(v.z - z0) < 0.01, "it stops for the person first")
			t.eq(v.speed, 0)
			local out = run(svc, v, 200, function(veh: any): boolean
				return veh.phase == "hold"
			end)
			t.eq(v.phase, "hold", "it reached the scene all the same")
			t.truthy(
				out + AICarMotor.BLOCK_PATIENCE - 0.5 < clearOut + 12,
				`{out} s after the wait; {clearOut} s with nobody in the way`
			)
			-- and home again, past the same person (the trip home ends where it began)
			svc:releaseResponder(v)
			local back = run(svc, v, 200, function(veh: any): boolean
				return veh.phase == "idle"
			end)
			t.eq(v.phase, "idle", "it came home")
			t.truthy(back < clearBack + 12, `{back} s home; {clearBack} s with nobody in the way`)
			t.eq(svc:responderIdle(), 3)
			-- all three at once, as when several people collapse: none is held at the start of its route
			local three = service()
			local out3 = {}
			for _ = 1, 3 do
				table.insert(out3, three:dispatchResponder({ stage.x, stage.z }, { route = trip, hold = true }))
			end
			run(three, out3[1], 200, function(): boolean
				for _, veh in out3 do
					if veh.phase ~= "hold" then
						return false
					end
				end
				return true
			end)
			for _, veh in out3 do
				t.eq(veh.phase, "hold", `{veh.name} reached the scene`)
			end
			-- someone who only crosses in front is still stopped for, and the count runs down again
			local cross = service()
			local w = cross:dispatchResponder({ stage.x, stage.z }, { route = trip, hold = true })
			run(cross, w, 2, function(): boolean
				return false
			end)
			t.eq(w.speed, 0, "stopped while they cross")
			table.clear(world.people)
			run(cross, w, 3, function(): boolean
				return false
			end)
			t.truthy(w.speed > AICarMotor.BLOCK_CRAWL, "then on at its own speed")
			t.eq(w.blocked, 0, "and the wait is forgotten")
		end
	)

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
