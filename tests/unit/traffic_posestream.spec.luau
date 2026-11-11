--!strict
-- Traffic/PoseStream, TrafficService.frame and Ghost.view / rootCFrame: the logic that used to sit inside
-- Server/Boot/Game's step and Client/Render/VehicleView's handlers, pinned to what those did, so the game
-- and the headless replay (tools/sim) run one implementation (focus 2: car glitches by measurement).
local fs = require("@lune/fs")
local roblox = require("@lune/roblox")
local Ghost = require("@shared/Traffic/Ghost")
local PoseStream = require("@shared/Traffic/PoseStream")
local Fleet = require("@shared/Traffic/Fleet")
local Boxes = require("@shared/Traffic/Boxes")
local Schemas = require("@shared/Net/Schemas")
local Net = require("@shared/Net/Net")
local Rng = require("@shared/Util/Rng")
local TrafficService = require("@server/Traffic/TrafficService")

return function(t)
	local records = require("../../generated/Lanes") :: any
	local roads = require("../../generated/Roads") :: any

	local function loopback(): (any, { buffer })
		local sent: { buffer } = {}
		local net = Net.new({
			send = function(_player: any, name: string, payload: any)
				assert(name == PoseStream.REMOTE, "only the pose stream is sent")
				table.insert(sent, payload)
			end,
			players = function(): { any }
				return {}
			end,
		})
		return net, sent
	end

	t.test("the sender sends on exactly the frames the old inline accumulator did, stamped with the clock", function()
		-- the reference: Server/Boot/Game's step as it was before the logic moved (2026-11-10)
		local rng = Rng.new(11)
		local sender = PoseStream.newSender()
		local source = {
			poseRecords = function(_self: any): { { [string]: number } }
				return { { id = 1, x = 0, z = 0, yaw = 0, speed = 0, bits = 0 } }
			end,
		}
		local poseAcc, now, sends = 0, 0, 0
		for i = 1, 5000 do
			-- frames from 4 ms to 30 ms, a hitch clamped to MAX_FRAME_DT now and then
			local dt = if i % 400 == 0 then PoseStream.MAX_FRAME_DT else rng.range(0.004, 0.03)
			now += dt
			local expected = false
			poseAcc += dt
			if poseAcc >= 1 / 15 then
				poseAcc = math.min(poseAcc - 1 / 15, 1 / 15)
				expected = true
			end
			local out = sender:frame(dt, now, source)
			t.eq(out ~= nil, expected, `frame {i}`)
			if out then
				sends += 1
				t.eq(#out, 2, "the pose records plus the stamp")
				t.eq(out[2].id, Ghost.STAMP_ID)
				t.eq(out[2].x, now, "the stamp is the server clock after the frame")
			end
		end
		t.eq(sender.sends, sends)
		t.near(sends / now, PoseStream.HZ, 0.2, "an even 15 sends a second")
		t.eq(PoseStream.MAX_FRAME_DT, 0.1, "Game clamps each Heartbeat dt to 0.1 s")
		-- a steady 60 Hz server: every send is 4 frames after the last one
		local steady = PoseStream.newSender()
		local last, gaps = 0, {}
		for i = 1, 600 do
			if steady:frame(1 / 60, i / 60, source) then
				gaps[i - last] = (gaps[i - last] or 0) + 1
				last = i
			end
		end
		t.eq(steady.sends, 150)
		t.eq(gaps[4], 150, "sends are 4 frames apart at a steady 60 Hz")
	end)

	t.test("TrafficService.frame is step plus the stamped send through Net, and sends nothing without a net", function()
		local a = TrafficService.new({ lanes = records, roads = roads, seed = 7 })
		local b = TrafficService.new({ lanes = records, roads = roads, seed = 7 })
		local net, sent = loopback()
		local now = 0
		local reference = PoseStream.newSender()
		for i = 1, 240 do
			local dt = 1 / 60
			now += dt
			local before = #sent
			a:frame(dt, now, {}, net)
			-- the reference: the old Game step, written out
			b:step(dt, {})
			-- (a send carries every jump since the last one, then forgets them: TrafficService.jumped)
			local expected = reference:frame(dt, now, b)
			t.eq(#sent - before, if expected then 1 else 0, `frame {i}`)
			if expected then
				local wire = Net.decodeStream(Schemas.VehiclePose, sent[#sent])
				t.eq(#wire, Fleet.count() + 1, "25 vehicles and the stamp")
				t.eq(buffer.len(sent[#sent]), 13 * (Fleet.count() + 1))
				t.eq(wire[#wire].id, Ghost.STAMP_ID)
				t.near(
					wire[#wire].x,
					now - a.acc,
					1e-5,
					"the stamp is the caller's clock less the tick not yet run (f32 on the wire)"
				)
				for j = 1, Fleet.count() do
					t.eq(wire[j].id, expected[j].id)
					t.near(wire[j].x, expected[j].x, 1e-3)
					t.near(wire[j].z, expected[j].z, 1e-3)
					t.eq(wire[j].yaw, expected[j].yaw)
					t.eq(wire[j].bits, expected[j].bits)
				end
			end
		end
		t.eq(#sent, 60, "15 sends a second")
		t.eq(a.vehicles[1].z, b.vehicles[1].z, "frame steps the fleet exactly as step does")
		local quiet = TrafficService.new({ lanes = records, roads = roads, seed = 7 })
		for _ = 1, 60 do
			quiet:frame(1 / 60, 0, {}, nil)
		end
		t.eq(quiet.sender.sends, 0, "no net, no send")
		t.truthy(quiet:stats().ticks >= 29, "the fleet still steps")
	end)

	t.test("kinds() lists this service's own entries (a scenario with one custom vehicle)", function()
		local svc = TrafficService.new({
			lanes = records,
			roads = roads,
			entries = {
				{
					id = 3,
					name = "Lone van",
					kind = "ice_cream_van",
					class = "van",
					lane = "icecream_loop",
					src = "spec",
				},
			} :: any,
		})
		local kinds = svc:kinds()
		t.eq(kinds[3].kind, "ice_cream_van", "not the fleet manifest's id 3 (an RV)")
		t.eq(kinds[1], nil)
		local all = TrafficService.new({ lanes = records, roads = roads }):kinds()
		for _, e in Fleet.ENTRIES do
			t.eq(all[e.id].kind, e.kind)
			t.eq(all[e.id].color, e.color)
		end
	end)

	t.test("the receiver: decode, unwrap the stamp, keep the snapshots on the server's timeline", function()
		local svc = TrafficService.new({ lanes = records, roads = roads, seed = 3 })
		local net, sent = loopback()
		local receiver = PoseStream.newReceiver()
		-- the reference: the same steps by hand
		local buf, clock = Ghost.new(), Ghost.newClock()
		local now = 0
		local jitter = { 0.031, 0.002, 0.044, 0.0, 0.019 }
		for i = 1, 120 do
			now += 1 / 60
			svc:frame(1 / 60, now, {}, net)
			if #sent > 0 then
				local b = table.remove(sent, 1) :: buffer
				local arrival = 1000 + now + 0.06 + jitter[i % #jitter + 1]
				t.truthy(receiver:packet(b, arrival))
				local wire = Net.decodeStream(Schemas.VehiclePose, b)
				local stamp = Ghost.takeStamp(wire)
				buf:push(clock:stamp(stamp :: number, arrival), wire)
			end
		end
		t.eq(#receiver.buffer.snaps, #buf.snaps)
		t.truthy(#buf.snaps >= 12)
		for i, snap in buf.snaps do
			t.eq(receiver.buffer.snaps[i].t, snap.t, "the same time")
			t.eq(receiver.buffer.snaps[i].poses[Ghost.STAMP_ID], nil, "the stamp is not a vehicle")
			t.deepEq(receiver.buffer.snaps[i].poses, snap.poses)
			if i > 1 then
				t.near(snap.t - buf.snaps[i - 1].t, 1 / 15, 1e-4, "spaced as the server sent them")
			end
		end
		t.near(buf.snaps[#buf.snaps].t, now - svc.acc, 1e-3, "at the server's clock, the tick the state is from")
		t.eq(receiver:packet("not a buffer", 5), false, "anything but a buffer is dropped")
		t.eq(receiver:packet(nil, 5), false)
		t.eq(#receiver.buffer.snaps, #buf.snaps)
		-- the time to draw at: the newest snapshot's floor plus the delay, once a frame
		local at = receiver:at(1000 + now + 0.06, 1 / 60)
		local delay = receiver.buffer.delay
		t.truthy(delay >= Ghost.DELAY and delay <= Ghost.DELAY + 0.045, `the delay {delay} covers the 44 ms of jitter`)
		t.near(receiver.clock.delay, delay)
		t.truthy(at - delay < buf.snaps[#buf.snaps].t, "drawn behind the newest snapshot")
		-- a send without a stamp is timed by its arrival
		local plain = PoseStream.newReceiver()
		plain:receive({ { id = 4, x = 1, z = 2, yaw = 0, speed = 0, bits = 1 } }, 77.5)
		t.eq(plain.buffer.snaps[1].t, 77.5)
		t.eq(plain.buffer.delay, Ghost.DELAY)
	end)

	t.test("Ghost.view visits every known vehicle with sample() and seen(); hidden ones park below", function()
		local kinds = { [1] = { kind = "sedan" }, [2] = { kind = "trolley" }, [3] = { kind = "rv" } }
		local function hill(x: number, _z: number): number
			return 5 + x * 0.1
		end
		local function rec(id: number, x: number, visible: boolean): { [string]: number }
			return Ghost.encode({
				id = id,
				x = x,
				z = 3,
				yaw = math.pi / 2,
				speed = 10,
				visible = visible,
				beacons = false,
				teleported = false,
				stopped = false,
			})
		end
		local buf = Ghost.new({ delay = 0 })
		buf:push(0, { rec(1, 0, true), rec(2, 50, true), rec(3, 9, false), rec(99, 0, true) })
		buf:push(1, { rec(1, 10, true), rec(2, 60, true), rec(3, 9, false), rec(99, 5, true) })
		local seen: { [number]: { number } } = {}
		local n = Ghost.view(buf, 0.5, kinds, hill, function(id, p, k, x, y, z, yaw, pitch)
			seen[id] = { x, y, z, yaw, pitch }
			t.eq(k, kinds[id])
			t.eq(p.id, id)
			local sx, sy, sz, syaw, spitch = Ghost.seen(p, k.kind, hill)
			t.deepEq({ x, y, z, yaw, pitch }, { sx, sy, sz, syaw, spitch })
		end)
		t.eq(n, 3, "id 99 has no kind: it is not drawn")
		t.eq(seen[99], nil)
		t.near(seen[1][1], 5, 1e-9, "interpolated half way")
		t.near(
			seen[1][2],
			5 + 0.5 + Boxes.get("sedan").height / 2,
			1e-6,
			"on the ground under its axles, half its height up"
		)
		t.near(seen[1][5], math.atan(0.1), 1e-6, "pitched up the hill")
		t.near(seen[2][2], 5 + 5.5 + Boxes.get("trolley").height / 2, 1e-6)
		t.eq(seen[3][2], Ghost.HIDDEN_Y, "a hidden vehicle parks far below")
		t.eq(seen[3][5], 0)
	end)

	t.test("rootCFrame: the nose points along the HTML yaw and lifts with a positive pitch", function()
		local lib = { CFrame = roblox.CFrame, Vector3 = roblox.Vector3 }
		for _, case in
			{
				{ yaw = 0, pitch = 0 },
				{ yaw = math.pi / 2, pitch = 0.2 },
				{ yaw = -2.2, pitch = -0.35 },
				{ yaw = math.pi, pitch = 0.5 },
			}
		do
			local cf = Ghost.rootCFrame(lib, 10, 20, 30, case.yaw, case.pitch, true)
			t.near(cf.Position.X, 10, 1e-5)
			t.near(cf.Position.Y, 20, 1e-5)
			t.near(cf.Position.Z, 30, 1e-5)
			-- authored rigs face -Z (LookVector); HTML yaw faces (sin yaw, cos yaw)
			t.near(cf.LookVector.X, math.sin(case.yaw) * math.cos(case.pitch), 1e-5)
			t.near(cf.LookVector.Y, math.sin(case.pitch), 1e-5, "nose up for a positive pitch")
			t.near(cf.LookVector.Z, math.cos(case.yaw) * math.cos(case.pitch), 1e-5)
			t.near(cf.RightVector.Y, 0, 1e-5, "never rolled")
			local hidden = Ghost.rootCFrame(lib, 10, Ghost.HIDDEN_Y, 30, case.yaw, case.pitch, false)
			t.near(hidden.LookVector.Y, 0, 1e-6, "a hidden vehicle is level")
			t.near(hidden.Position.Y, Ghost.HIDDEN_Y, 1e-3)
		end
	end)

	t.test("the game, the client and the replay all go through the shared entry points", function()
		local game = fs.readFile("src/server/Boot/Game.luau")
		t.truthy(
			string.find(game, "traffic:frame(dt, now, trafficWorld() :: any, net)", 1, true),
			"Game steps through frame"
		)
		t.truthy(
			string.find(game, "step(math.min(dt, PoseStream.MAX_FRAME_DT))", 1, true),
			"Game clamps with the shared constant"
		)
		for _, inline in { "Ghost.stamp(", "poseAcc", "poseRecords(", 'net:stream(nil, "VehiclePoses"' } do
			t.falsy(string.find(game, inline, 1, true), `Game no longer inlines {inline}`)
		end
		local view = fs.readFile("src/client/Render/VehicleView.luau")
		t.truthy(string.find(view, "PoseStream.newReceiver()", 1, true))
		t.truthy(string.find(view, "receiver:packet(b, workspace:GetServerTimeNow())", 1, true))
		t.truthy(string.find(view, "local at = receiver:at(workspace:GetServerTimeNow(), dt)", 1, true))
		t.truthy(string.find(view, "Ghost.render(receiver.buffer, at, folder, kinds, ground, models)", 1, true))
		-- the ghosts stand on the drawn roads, and the headless replay seats them on the same ground
		local ground = "RoadSurface.ground(RoadSurface.new(Data.default():roads()), Height.at)"
		t.truthy(string.find(view, ground, 1, true), "VehicleView seats the ghosts on World/RoadSurface")
		local replay = fs.readFile("tools/sim/lib/Replay.luau")
		t.truthy(
			string.find(replay, "RoadSurface.ground(RoadSurface.new(data:roads()), Height.at)", 1, true),
			"the replay seats them the same way"
		)
		for _, inline in { "takeStamp", "newClock", "decodeStream", "Ghost.new(", "CFrame.", "Vector3." } do
			t.falsy(string.find(view, inline, 1, true), `VehicleView no longer inlines {inline}`)
		end
		local ghost = fs.readFile("src/shared/Traffic/Ghost.luau")
		local render = string.sub(ghost, (string.find(ghost, "function Ghost.render(", 1, true)) :: number)
		t.truthy(string.find(render, "Ghost.view(buffer, now, kinds, heightAt,", 1, true), "render draws from view")
		t.truthy(string.find(render, "Ghost.rootCFrame(lib, x, y, z, yaw, pitch, p.visible, roll)", 1, true))
		t.falsy(string.find(render, "buffer:sample", 1, true), "render does not sample on its own")
	end)
end
