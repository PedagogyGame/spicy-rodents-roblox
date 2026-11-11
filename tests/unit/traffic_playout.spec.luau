--!strict
-- The client's playout of the VehiclePoses stream (Traffic/Ghost: the snapshot buffer and the playout
-- clock; Traffic/PoseStream's receiver) against what happens between the server and the picture:
-- packets that overtake each other or arrive twice, a jittery connection, the client's clock stepping, a
-- long server uptime (the stamp is a 32-bit float), a client joining late, a teleport whose flagged send
-- was lost. The unit cases pin each mechanism; the scenarios (tools/sim/scenarios) replay the real fleet
-- through the real codec and must show no glitch at all.
local Ghost = require("@shared/Traffic/Ghost")
local Replay = require("../../tools/sim/lib/Replay")

local function rec(id: number, x: number, speed: number, teleported: boolean?): { [string]: number }
	return Ghost.encode({
		id = id,
		x = x,
		z = 0,
		yaw = math.pi / 2,
		speed = speed,
		visible = true,
		beacons = false,
		teleported = teleported == true,
		stopped = speed < 0.05,
	})
end

return function(t)
	t.test("the buffer keeps snapshots in time order and drops a copy of one it holds", function()
		local g = Ghost.new({ delay = 0 })
		g:push(1, { rec(1, 10, 30) })
		g:push(3, { rec(1, 30, 30) })
		g:push(2, { rec(1, 20, 30) }) -- overtaken on the way
		g:push(3, { rec(1, 99, 30) }) -- a copy of a held stamp
		t.eq(#g.snaps, 3)
		t.eq(g.snaps[1].t, 1)
		t.eq(g.snaps[2].t, 2)
		t.eq(g.snaps[3].t, 3)
		t.near(g:sample(2.5)[1].x, 25, 1e-4, "interpolated between the right pair")
		t.near(g:sample(3)[1].x, 30, 1e-4, "the copy changed nothing")
		-- a late packet older than everything a full buffer holds is dropped
		local h = Ghost.new({ delay = 0, keep = 2 })
		h:push(5, { rec(1, 0, 30) })
		h:push(6, { rec(1, 0, 30) })
		h:push(4, { rec(1, 0, 30) })
		t.eq(#h.snaps, 2)
		t.eq(h.snaps[1].t, 5)
	end)

	t.test("a jump no car could drive is drawn as a snap, never a streak, and never carried on", function()
		local g = Ghost.new({ delay = 0 })
		g:push(0, { rec(1, 0, 30) })
		g:push(1 / 15, { rec(1, 1300, 30) }) -- a wrap whose flagged send was lost
		t.near(g:sample(1 / 30)[1].x, 1300, 1e-3, "snapped, not half way across town")
		t.near(g:sample(1 / 15 + 0.1)[1].x, 1300, 1e-3, "not extrapolated along the jump")
		local h = Ghost.new({ delay = 0 })
		h:push(0, { rec(1, 0, 30) })
		h:push(1 / 15, { rec(1, 2, 30) }) -- an ordinary step
		t.near(h:sample(1 / 30)[1].x, 1, 1e-3)
	end)

	t.test("the stamp is sent modulo STAMP_WRAP and unwrapped: snapshots stay evenly spaced for days", function()
		for _, hours in { 0, 50, 200, 1000 } do
			local clock = Ghost.newClock()
			local base = hours * 3600
			local last: number? = nil
			for i = 0, 200 do
				local server = base + 4090 + i / 15 -- runs through a wrap
				local raw = Ghost.stamp(server).x
				local f32 = buffer.create(4)
				buffer.writef32(f32, 0, raw)
				local s = clock:stamp(buffer.readf32(f32, 0), 1000 + i / 15)
				if last then
					t.near(s - last, 1 / 15, 1e-3, `{hours} h: send {i} spaced as sent`)
				end
				last = s
			end
		end
	end)

	t.test("the playout clock: a clock step is steered out at Ghost.SLEW, never jumped", function()
		for _, step in { -0.25, 0.25 } do
			local clock = Ghost.newClock()
			local prev: number? = nil
			local now = 0
			for f = 1, 60 * 20 do
				local dt = 1 / 60
				local wall = f / 60
				now = wall + (if wall >= 5 then step else 0)
				if f % 4 == 0 then
					clock:stamp(wall - 0.05, now) -- a send every 4 frames, 50 ms away
				end
				local drawn = clock:advance(now, dt) - clock.delay
				if prev and f > 60 then
					local moved = drawn - prev
					t.truthy(
						moved >= dt * (1 - Ghost.CATCH_UP) - 1e-9 and moved <= dt * (1 + Ghost.SLEW) + 1e-9,
						`step {step}: frame {f} moved {moved}`
					)
				end
				prev = drawn
			end
			-- and it has settled again: the instant drawn is Ghost.DELAY behind the newest stamp
			t.near(prev :: number, 20 - 0.05 - Ghost.DELAY, 0.02, `step {step}: settled`)
		end
	end)

	t.test("the playout clock buffers more on a jittery connection, within MAX_DELAY", function()
		local clock = Ghost.newClock()
		for i = 1, 120 do
			local jitter = if i % 5 == 0 then 0.08 else 0.01 * (i % 3)
			clock:stamp(i / 15, i / 15 + 0.06 + jitter)
			clock:advance(i / 15 + 0.06, 1 / 15)
		end
		t.near(clock.delay, Ghost.DELAY + 0.08, 1e-6, "the 95th percentile of the lateness is covered")
		local wild = Ghost.newClock()
		-- every other send 0.6 s late, handed over in the order they arrive (as the remote does)
		local flights = {}
		for i = 1, 120 do
			table.insert(flights, { stamp = i / 15, at = i / 15 + (if i % 2 == 0 then 0.6 else 0) })
		end
		table.sort(flights, function(a, b)
			return a.at < b.at
		end)
		for _, f in flights do
			if f.at > 7 then
				break -- (past here only the late ones are left)
			end
			wild:stamp(f.stamp, f.at)
			wild:advance(f.at, 1 / 15)
		end
		t.eq(wild.delay, Ghost.MAX_DELAY)
	end)

	-- the scenarios: every one must show nothing at all
	for _, name in
		{
			"net_jitter",
			"net_reorder",
			"clock_step_back",
			"clock_step_ahead",
			"long_uptime",
			"late_join",
		}
	do
		t.test(`scenario {name}: no glitch on screen`, function()
			local result = Replay.run({ scenario = name, seconds = 25 })
			local failures = Replay.check(result)
			t.eq(#failures, 0, table.concat(failures, "; "))
			t.eq(result.stats.starvedFrames, 0, "never drawing past the newest snapshot")
		end)
	end
end
