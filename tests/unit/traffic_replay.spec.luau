--!strict
-- tools/sim: the headless traffic replay and its glitch detectors (focus 2: car glitches by measurement).
--   * the regression: every scenario with a `ci` length is replayed on an ideal network and its `expect`
--     (what must hold) and `known` (glitches it shows today, which the instrument must keep seeing) checked
--   * the instrument itself: the replay is exact and repeatable, the network and pacing models do what
--     their settings say, and every detector fires on the glitch it names and stays quiet on clean motion
local serde = require("@lune/serde")
local Ghost = require("@shared/Traffic/Ghost")
local Boxes = require("@shared/Traffic/Boxes")
local Colliders = require("@shared/World/Colliders")
local Town = require("@shared/World/Town")
local Detect = require("../../tools/sim/lib/Detect")
local NetModel = require("../../tools/sim/lib/NetModel")
local Replay = require("../../tools/sim/lib/Replay")
local Report = require("../../tools/sim/lib/Report")

return function(t)
	local detectors: { [string]: Detect.Def } = {}
	for _, def in Detect.load() do
		detectors[def.name] = def
	end

	-- A detector on the bench: vehicle 1 follows `truth(clock)` at 30 ticks a second; 60 frames a second
	-- draw it Ghost.DELAY behind, exactly where it truly was, after `seen(t, sample)` has had its say.
	type Drive = {
		seconds: number?,
		truth: ((clock: number) -> { [string]: any })?,
		seen: ((time: number, sample: { [string]: any }) -> ())?,
		bench: { [string]: any }?,
		others: { [number]: (clock: number) -> { [string]: any } }?,
		seenOthers: { [number]: (time: number, sample: { [string]: any }) -> () }?,
	}
	local function cruise(clock: number): { [string]: any }
		return { x = 0, z = 20 * clock, yaw = 0, speed = 20 }
	end
	local function drive(def: Detect.Def, o: Drive): ({ Detect.Incident }, { [string]: number })
		local bench = Detect.bench(def, o.bench)
		local truthOf = { [1] = o.truth or cruise }
		for id, fn in o.others or {} do
			truthOf[id] = fn
		end
		local tick, nextTick = 1 / 30, 1 / 30
		local n = 0
		while n / 60 <= (o.seconds or 2) do
			local time = n / 60
			while nextTick <= time + 1e-9 do
				local list = {}
				for id, fn in truthOf do
					local s = fn(nextTick)
					s.id = id
					table.insert(list, s)
				end
				bench:tick(nextTick, list)
				nextTick += tick
			end
			local ref = time - Ghost.DELAY
			if ref > 3 * tick then
				local frame = {}
				for id in truthOf do
					local r = bench.truth:at(id, ref)
					local sample = { x = r.x, z = r.z, yaw = r.yaw, speed = r.speed, vis = r.visible }
					local alter = if id == 1 then o.seen else (o.seenOthers or {})[id]
					if alter then
						alter(time, sample)
					end
					frame[id] = sample
				end
				bench:frame(time, frame, ref)
			end
			n += 1
		end
		return bench:finish()
	end
	local function total(counts: { [string]: number }): number
		local n = 0
		for _, c in counts do
			n += c
		end
		return n
	end

	-- the regression ---------------------------------------------------------------------------------
	for _, name in Replay.scenarios() do
		local sc = Replay.scenario(name)
		if sc.ci then
			t.test(
				`scenario {name} ({sc.ci} s, ideal network): what must hold holds, known glitches still show`,
				function()
					local result = Replay.run({ scenario = name, seconds = sc.ci })
					local kinds = {}
					for kind, n in result.counts do
						table.insert(kinds, `{kind} {n}`)
					end
					table.sort(kinds)
					print(`      {name}: {if #kinds > 0 then table.concat(kinds, ", ") else "no incidents"}`)
					local failures = Replay.check(result)
					t.eq(#failures, 0, table.concat(failures, "; "))
					t.eq(result.stats.lost, 0)
					t.near(result.stats.sends / result.stats.serverClock, 15, 0.1, "15 sends a second")
					t.near(result.stats.ticks / result.stats.serverClock, 30, 0.1, "30 ticks a second")
				end
			)
		end
	end

	-- the replay ---------------------------------------------------------------------------------------
	t.test(
		"on an ideal network the drawn pose is the true pose of the instant being drawn, Ghost.DELAY behind",
		function()
			local result = Replay.run({ scenario = "fleet", seconds = 15, keepFrames = true })
			local frames = result.frames :: { Detect.Frame }
			t.eq(#frames, 15 * 60, "60 client frames a second")
			-- the RV and the dump truck on the straight residential lanes (ids 3 and 4), the ice cream van on
			-- its loop (5) and the trolley between stations (13)
			local straight, curved, worstLag, checked = 0, 0, 0, 0
			for _, frame in frames do
				if frame.t < 1 then
					continue
				end
				t.eq(#frame.ids, 25, "every vehicle has a pose in every frame")
				t.near(frame.ref :: number, frame.now - Ghost.DELAY - (frame.offset :: number), 1e-9)
				for _, id in { 3, 4, 5, 13 } do
					local s = frame.v[id]
					t.truthy(s.rok and s.vis and s.rvis)
					local off = math.sqrt((s.x - s.rx) ^ 2 + (s.z - s.rz) ^ 2)
					if id == 3 or id == 4 then
						straight = math.max(straight, off)
					else
						curved = math.max(curved, off)
					end
					-- behind the server's pose of this very instant by the delay's worth of driving
					local lag = math.sqrt((s.x - s.tx) ^ 2 + (s.z - s.tz) ^ 2)
					worstLag = math.max(worstLag, lag - s.tspeed * 0.17 - 1.5)
					t.truthy(s.y > 0 and s.y < 60 and math.abs(s.pitch) <= 0.5, "seated on the terrain")
					checked += 1
				end
				-- the hidden vehicles park below the map
				t.eq(frame.v[15].vis, false)
				t.eq(frame.v[15].y, Ghost.HIDDEN_Y)
			end
			t.truthy(checked > 3000)
			t.truthy(
				straight < 0.02,
				`on a straight lane the drawn pose is the truth being drawn (off by {straight} st)`
			)
			t.truthy(curved < 1, `on a curve or into a stop it is within a stud (off by {curved} st)`)
			t.truthy(worstLag <= 0, `the lag is the delay's worth of driving (excess {worstLag} st)`)
			t.eq(result.stats.starvedFrames, 0)
			t.near(result.stats.lagMs.p50, Ghost.DELAY * 1000, 15, "the median lag is the render delay")
		end
	)

	t.test("a replay repeats exactly; a constant latency adds lag and nothing else; loss makes stutter", function()
		local a = Replay.run({ scenario = "stops", seconds = 15, net = "typical", seed = 5 })
		local b = Replay.run({ scenario = "stops", seconds = 15, net = "typical", seed = 5 })
		t.deepEq(a.counts, b.counts)
		t.eq(#a.incidents, #b.incidents)
		for i, inc in a.incidents do
			t.eq(inc.t, b.incidents[i].t)
			t.eq(inc.kind, b.incidents[i].kind)
			t.eq(inc.magnitude, b.incidents[i].magnitude)
		end
		t.eq(a.stats.lost, b.stats.lost)
		local other = Replay.run({ scenario = "stops", seconds = 15, net = "typical", seed = 6 })
		t.truthy(other.stats.lagStuds.mean ~= a.stats.lagStuds.mean, "another seed is another network")
		-- 200 ms away with no jitter and no loss: the same incidents as no latency at all
		local near = Replay.run({ scenario = "stops", seconds = 15 })
		local far = Replay.run({ scenario = "stops", seconds = 15, netSet = { latency = 0.2 } })
		t.deepEq(far.counts, near.counts, "a constant latency is not a glitch")
		t.near(far.stats.lagMs.p50 - near.stats.lagMs.p50, 200, 20, "it is 200 ms more lag")
		-- one packet in five lost: starved frames, and the stutter detector sees them
		local lossy = Replay.run({ scenario = "stops", seconds = 15, netSet = { loss = 0.2 }, seed = 2 })
		t.truthy(lossy.stats.lost > 20 and lossy.stats.starvedFrames > 0)
		t.truthy((lossy.counts.speed_stutter or 0) > 0, "loss shows up as speed_stutter")
		t.eq(near.counts.speed_stutter, nil)
	end)

	t.test(
		"settings: profiles by name or field, the scenario's defaults, thresholds, a chosen detector, the trace",
		function()
			local s = Replay.settings({ scenario = "sedan_wrap", net = "typical", netSet = { loss = 0.5 }, fps = 30 })
			t.eq(s.netName, "typical")
			t.eq(s.net.latency, 0.06)
			t.eq(s.net.jitter, 0.02)
			t.eq(s.net.loss, 0.5)
			t.eq(NetModel.NET.typical.loss, 0.01, "the named profile is not edited")
			t.eq(s.client.hz, 30)
			t.eq(s.seconds, 12, "the scenario's own length")
			t.eq(s.trafficSeed, 7, "the game's fleet seed")
			t.fails(function()
				Replay.settings({ scenario = "no_such_scenario" })
			end, "no scenario")
			t.fails(function()
				Replay.settings({ net = "no_such_profile" })
			end, "no net profile")
			local result = Replay.run({
				scenario = "sedan_wrap",
				detectors = { "jumps" },
				thresholds = { ["jumps.teleport"] = 100000 },
				trace = { from = 2, to = 4, vehicles = { 1 } },
			})
			t.eq(#result.detectors, 1)
			t.eq(result.counts.teleport_unflagged, nil, "the threshold override applies")
			t.truthy((result.counts.position_jump or 0) > 0, "the streak is now a hop")
			local rows = result.trace :: { { [string]: any } }
			t.eq(#rows, 2 * 60, "one row per frame for the one vehicle")
			t.eq(rows[1].id, 1)
			local csv = Report.csv(rows)
			t.truthy(string.find(csv, "frame,t,dt,packets,snaps,starved,offset,id,vis,x,y,z,yaw,pitch", 1, true))
		end
	)

	t.test("the report: summary, JSON and the worst list", function()
		local result = Replay.run({ scenario = "motorcycles" })
		local text = Report.summary(result, 5, "lune run tools/sim/traffic_replay.luau --scenario motorcycles")
		t.truthy(string.find(text, "appear", 1, true))
		t.truthy(string.find(text, "#8 Morgan Rider", 1, true))
		t.truthy(
			string.find(
				text,
				"trace it: lune run tools/sim/traffic_replay.luau --scenario motorcycles --trace",
				1,
				true
			)
		)
		local worst = Report.worst(result, 10)
		t.truthy(#worst >= 3)
		for i = 2, #worst do
			t.truthy(worst[i - 1].severity >= worst[i].severity, "most severe first")
		end
		local back = serde.decode("json", serde.encode("json", Report.json(result, "cmd")))
		t.eq(back.scenario.name, "motorcycles")
		t.eq(back.counts.appear, 2)
		t.eq(#back.incidents, #result.incidents)
		local first = back.incidents[1]
		for _, field in { "kind", "t", "vehicle", "magnitude", "limit", "unit", "severity", "name" } do
			t.truthy(first[field] ~= nil, `an incident carries {field}`)
		end
		local thresholds = 0
		for _, d in back.detectors do
			for _, item in d.thresholds do
				t.truthy(#item.why > 20, `{d.name}.{item.key} states its reason`)
				thresholds += 1
			end
		end
		t.truthy(thresholds >= 25)
	end)

	-- the models -------------------------------------------------------------------------------------
	t.test(
		"network model: ideal passes everything at once; typical is 60 ms + 20 ms and 1 %; bursts, reordering",
		function()
			local ideal = NetModel.network(NetModel.NET.ideal, 1)
			for i = 1, 100 do
				local out = ideal:send(i / 15)
				t.eq(#out, 1)
				t.eq(out[1], i / 15)
			end
			local net = NetModel.network(NetModel.NET.typical, 3)
			local n, sum, least, most = 0, 0, math.huge, 0
			for i = 1, 30000 do
				for _, at in net:send(i / 15) do
					local delay = at - i / 15
					n += 1
					sum += delay
					least, most = math.min(least, delay), math.max(most, delay)
				end
			end
			t.near(net.stats.lost / 30000, 0.01, 0.003, "1 % lost")
			t.eq(n + net.stats.lost, 30000)
			t.near(sum / n, 0.06 + 0.02, 0.002, "60 ms plus jitter with a 20 ms mean")
			t.truthy(least >= 0.06 and most <= 0.06 + 5 * 0.02 + 1e-9, "the jitter is one-sided and capped at 5 x")
			-- the same seed is the same network
			local a, b = NetModel.network(NetModel.NET.wifi, 9), NetModel.network(NetModel.NET.wifi, 9)
			for i = 1, 2000 do
				t.deepEq(a:send(i / 15), b:send(i / 15))
			end
			t.truthy(a.stats.bursts >= 3 and a.stats.burstLost > 0, "wifi has loss bursts")
			t.truthy(a.stats.reordered > 0)
			local dup = table.clone(NetModel.NET.ideal)
			dup.duplicate = 1
			t.eq(#NetModel.network(dup, 1):send(1), 2, "a duplicated packet arrives twice")
		end
	)

	t.test("pacers: steady is exact; live wanders, spikes and stalls around its rate", function()
		local steady = NetModel.pacer(NetModel.SERVER.steady, 1)
		for _ = 1, 100 do
			t.eq(steady:next(), 1 / 60)
		end
		local live = NetModel.pacer(NetModel.SERVER.live, 4)
		local sum, n = 0, 60 * 600
		for _ = 1, n do
			sum += live:next()
		end
		t.truthy(live.stats.spikes > 50 and live.stats.stalls >= 3)
		t.truthy(live.stats.longest > 0.12 and live.stats.longest < 0.5)
		t.near(sum / n, 1 / 60, 0.001, "about 60 frames a second")
		local same = NetModel.pacer(NetModel.SERVER.live, 4)
		local again = NetModel.pacer(NetModel.SERVER.live, 4)
		for _ = 1, 500 do
			t.eq(same:next(), again:next())
		end
	end)

	-- the detectors, each on the bench -----------------------------------------------------------------
	t.test("every detector is quiet on a car that is drawn exactly where it was", function()
		for name, def in detectors do
			local incidents, counts = drive(def, {})
			t.eq(#incidents, 0, `{name} on clean motion: {serde.encode("json", counts)}`)
		end
	end)

	t.test("jumps: a hop, an unflagged teleport, a flagged teleport, and where each comes from", function()
		local def = detectors.jumps
		local incidents = drive(def, {
			seen = function(time, s)
				if time >= 1 then
					s.z += 5
				end
			end,
		})
		t.eq(#incidents, 1)
		t.eq(incidents[1].kind, "position_jump")
		t.near(incidents[1].magnitude, 5 + 20 / 60, 0.01, "the step of that frame")
		t.near(incidents[1].limit, 2.5 * 20 / 60 + 0.5, 0.01)
		t.eq(incidents[1].origin, "stream", "the truth drove smoothly")
		t.near(incidents[1].t, 1, 0.02)
		local streak = drive(def, {
			seen = function(time, s)
				if time >= 1 then
					s.z += 300
				end
			end,
		})
		t.eq(streak[1].kind, "teleport_unflagged")
		local snap = drive(def, {
			seen = function(time, s)
				if time >= 1 then
					s.z += 300
					s.snap = time < 1 + 1 / 60
				end
			end,
		})
		t.eq(#snap, 1)
		t.eq(snap[1].kind, "teleport_flagged")
		t.eq(snap[1].magnitude, 1, "a flagged teleport is one pop")
		t.near((snap[1].detail :: any).distance, 300 + 20 / 60, 0.01)
		-- the truth itself wraps (flagged) and the client draws it faithfully: origin sim
		local wrapped = drive(def, {
			truth = function(clock)
				local s = cruise(clock)
				if clock >= 1 then
					s.z -= 500
					s.teleported = clock < 1 + 1 / 30
				end
				return s
			end,
		})
		t.eq(#wrapped, 1)
		t.eq(wrapped[1].kind, "teleport_unflagged", "the bench draws the truth without the snap flag")
		t.eq(wrapped[1].origin, "sim")
		t.eq((wrapped[1].detail :: any).truth, "flagged teleport")
		-- a hitch is not a jump: one 0.25 s frame moves 5 st at 20 st/s
		local bench = Detect.bench(def)
		for i = 1, 60 do
			bench:tick(i / 30, { { id = 1, x = 0, z = 20 * i / 30, yaw = 0, speed = 20 } })
		end
		bench:frame(1.0, { [1] = { x = 0, z = 20, speed = 20 } }, 1.0)
		bench:frame(1.25, { [1] = { x = 0, z = 25, speed = 20 } }, 1.25)
		t.eq(#bench:finish(), 0)
	end)

	t.test("stutter: a wobbling speed, a freeze, and a dead stop that is the server's own", function()
		local def = detectors.stutter
		local wobble = drive(def, {
			seen = function(time, s)
				if time >= 1 and time < 1.5 then
					s.z += 0.3 * math.sin(2 * math.pi * 7.5 * time)
				end
			end,
		})
		t.truthy(#wobble >= 1)
		for _, inc in wobble do
			t.truthy(inc.kind == "speed_stutter" or inc.kind == "accel_spike")
			t.eq(inc.origin, "stream")
		end
		local held: number? = nil
		local frozen = drive(def, {
			seen = function(time, s)
				if time >= 1 and time < 1.1 then
					held = held or s.z
					s.z = held :: number
				end
			end,
		})
		local sawFrozen = false
		for _, inc in frozen do
			sawFrozen = sawFrozen or (inc.kind == "speed_stutter" and (inc.detail :: any).direction == "frozen")
		end
		t.truthy(sawFrozen, "a frozen car is a speed_stutter with direction frozen")
		local stop = drive(def, {
			truth = function(clock)
				return { x = 0, z = 20 * math.min(clock, 1), yaw = 0, speed = if clock < 1 then 20 else 0 }
			end,
		})
		t.truthy(#stop >= 1)
		for _, inc in stop do
			t.eq(inc.kind, "accel_spike", "a real dead stop is no speed_stutter: the car did have those speeds")
			t.eq(inc.origin, "sim")
		end
	end)

	t.test("turns: a heading snap, a sideways slide, driving backwards (not the trolley, not parking)", function()
		local def = detectors.turns
		local snap = drive(def, {
			seen = function(time, s)
				if time >= 1 then
					s.yaw += 0.25
				end
			end,
		})
		t.eq(snap[1].kind, "yaw_jump")
		t.near(snap[1].magnitude, 0.25, 1e-6)
		t.eq(snap[1].origin, "stream")
		local _, crab = drive(def, {
			seen = function(_time, s)
				s.yaw = math.pi / 2
			end,
		})
		t.truthy((crab.sideways_slide or 0) >= 1)
		t.eq(crab.reverse_travel, nil)
		local backwards = function(clock: number): { [string]: any }
			return { x = 0, z = 20 * clock, yaw = math.pi, speed = 20 }
		end
		local reversed, counts = drive(def, { truth = backwards })
		t.eq(counts.reverse_travel, 1, "one long incident")
		t.eq(reversed[1].origin, "sim", "the server's own heading")
		t.truthy(reversed[1].duration > 1)
		local _, trolley = drive(def, {
			truth = backwards,
			bench = { vehicles = { [1] = { name = "Trolley", kind = "trolley", class = "trolley" } } },
		})
		t.eq(trolley.reverse_travel, nil, "the trolley runs both ways")
		local _, parking = drive(def, {
			seconds = 6,
			truth = function(clock)
				return { x = 0, z = 0.7 * clock, yaw = math.pi, speed = 0.7 }
			end,
		})
		t.eq(parking.reverse_travel, nil, "backing into a space is not driving backwards")
	end)

	t.test(
		"ground: Ghost.seat's own pose is clean on a slope; sunk, floating, popping, twitching, tilted, unrolled",
		function()
			local def = detectors.ground
			local function slope(_x: number, z: number): number
				return 3 + 0.25 * z
			end
			-- the game's own seating on a 14 degree slope, uphill and downhill: nothing to report
			for _, heading in { 0, math.pi } do
				local seated = function(_time: number, s: { [string]: any })
					local pose: any = { x = s.x, z = s.z, yaw = heading, visible = true }
					local _, y, _, _, pitch = Ghost.seen(pose, "sedan", slope)
					s.y, s.pitch, s.yaw = y, pitch, heading
				end
				local incidents, counts = drive(def, { bench = { heightAt = slope }, seen = seated })
				t.eq(#incidents, 0, `Ghost.seat heading {heading} on a slope: {serde.encode("json", counts)}`)
			end
			local half = Boxes.get("sedan").height / 2
			local function with(change: (time: number, s: { [string]: any }) -> ()): { [string]: number }
				local _, counts = drive(def, {
					seen = function(time, s)
						s.y = half
						change(time, s)
					end,
				})
				return counts
			end
			local sunk = with(function(_time, s)
				s.y -= 1.5
			end)
			t.eq(sunk.sink, 1)
			t.eq(total(sunk), 1)
			local floating = with(function(_time, s)
				s.y += 1.5
			end)
			t.eq(floating.float, 1)
			t.eq(total(floating), 1)
			local pop = with(function(time, s)
				if time >= 1 then
					s.y += 0.5
				end
			end)
			t.eq(pop.height_jump, 1)
			local twitch = with(function(time, s)
				if time >= 1 then
					s.pitch = 0.2
				end
			end)
			t.eq(twitch.pitch_jump, 1)
			t.eq(twitch.tilt_mismatch, 1, "and from then on the car is tilted on flat ground")
			local _, crossfall = drive(def, {
				bench = {
					heightAt = function(x: number, _z: number): number
						return 0.2 * x
					end,
				},
			})
			t.eq(crossfall.roll_missing, 1)
		end
	)

	t.test("rubber: a car drawn ahead of where it was, by how much and which way", function()
		local incidents = drive(detectors.rubber, {
			seen = function(time, s)
				if time >= 1 and time < 1.3 then
					s.z += 4
					s.x += 1
				end
			end,
		})
		t.eq(#incidents, 1)
		t.eq(incidents[1].kind, "rubber_band")
		t.near(incidents[1].magnitude, math.sqrt(17), 1e-6)
		t.near(incidents[1].limit, 1.5 + 20 / 30, 1e-6)
		t.near((incidents[1].detail :: any).along, 4, 1e-6, "drawn 4 st ahead")
		t.near(math.abs((incidents[1].detail :: any).across), 1, 1e-6)
		t.near(incidents[1].duration, 0.3, 0.02)
	end)

	t.test("overlap: one car through another, on the server or only on screen", function()
		local def = detectors.overlap
		local two = {
			vehicles = {
				[1] = { name = "A", kind = "sedan", class = "sedan" },
				[2] = { name = "B", kind = "rv", class = "heavy" },
			},
		}
		local function parked(_clock: number): { [string]: any }
			return { x = 0, z = 24, yaw = math.pi / 2, speed = 0 }
		end
		local through = drive(def, { bench = two, others = { [2] = parked } })
		t.eq(#through, 1, "one incident for the pair")
		t.eq(through[1].kind, "box_overlap")
		t.eq(through[1].origin, "sim", "the true poses overlap too")
		t.eq((through[1].detail :: any).other, 2)
		t.truthy(through[1].magnitude > 3, "right through the middle")
		-- lanes apart on the server; only the drawn car is shifted into the other
		local beside = function(_clock: number): { [string]: any }
			return { x = 12, z = 24, yaw = 0, speed = 0 }
		end
		local shifted = drive(def, {
			bench = two,
			others = { [2] = beside },
			seenOthers = {
				[2] = function(_time, s)
					s.x -= 8
				end,
			},
		})
		t.eq(#shifted, 1)
		t.eq(shifted[1].origin, "stream")
		local apart = drive(def, { bench = two, others = { [2] = beside } })
		t.eq(#apart, 0)
		-- the depth is the shortest way out
		t.near(
			Detect.obbOverlap({ x = 0, z = 0, yaw = 0, hw = 2, hl = 5 }, { x = 3, z = 0, yaw = 0, hw = 2, hl = 5 }),
			1,
			1e-9
		)
		t.truthy(
			Detect.obbOverlap({ x = 0, z = 0, yaw = 0, hw = 2, hl = 5 }, { x = 5, z = 0, yaw = 0.3, hw = 2, hl = 5 })
				< 0.6
		)
		t.truthy(
			Detect.obbOverlap({ x = 0, z = 0, yaw = 0, hw = 2, hl = 5 }, { x = 9, z = 0, yaw = 0, hw = 2, hl = 5 }) < 0
		)
	end)

	t.test("visibility: a pop out and in, a real appearance, a ghost that outstays its truth", function()
		local def = detectors.visibility
		local flicker = drive(def, {
			seen = function(time, s)
				if time >= 1 and time < 1.1 then
					s.vis = false
				end
			end,
		})
		t.eq(#flicker, 2)
		t.eq(flicker[1].kind, "disappear")
		t.eq(flicker[2].kind, "appear")
		t.eq(flicker[1].origin, "stream", "the truth never hid")
		t.truthy((flicker[1].detail :: any).inside > 0, "in the middle of the town")
		local real = drive(def, {
			truth = function(clock)
				local s = cruise(clock)
				s.visible = clock >= 1
				return s
			end,
		})
		t.eq(#real, 1)
		t.eq(real[1].kind, "appear")
		t.eq(real[1].origin, "sim")
		local ghost, counts = drive(def, {
			seen = function(time, s)
				if time >= 1 and time < 1.6 then
					s.vis = false
				end
			end,
		})
		t.eq(counts.ghost_visibility, 1)
		t.eq(#ghost, 3)
	end)

	t.test(
		"wire: unflagged jumps and heading snaps on the server, teleport flags that miss or lose their send",
		function()
			local def = detectors.wire
			local function send(n: number, clock: number, teleported: boolean, lost: boolean): Detect.Send
				local pose: any = { id = 1, teleported = teleported }
				return {
					n = n,
					wall = clock,
					clock = clock,
					stamp = clock,
					age = 0,
					poses = { [1] = pose },
					lost = lost,
					arrival = nil,
					processed = nil,
				}
			end
			local function wrapAt(tickOfWrap: number, sends: { Detect.Send }): ({ Detect.Incident }, { [string]: any })
				local bench = Detect.bench(def)
				for i = 1, 12 do
					local z = 20 * i / 30 - (if i >= tickOfWrap then 400 else 0)
					bench:tick(i / 30, { { id = 1, x = 0, z = z, yaw = 0, speed = 20, teleported = i == tickOfWrap } })
					for _, s in sends do
						if s.n == i then
							(bench.hooks.send :: any)(s)
						end
					end
				end
				local incidents = bench:finish()
				return incidents, bench.book.stats.wire
			end
			-- the wrap's tick is followed by a send that carries the flag
			local carried, stats = wrapAt(6, { send(6, 6 / 30, true, false) })
			t.eq(#carried, 0)
			t.eq(stats.teleportsFlagged, 1)
			t.eq(stats.teleportsCarried, 1)
			-- the next send comes a tick later: the flag is gone
			local dropped, dstats = wrapAt(6, { send(7, 7 / 30, false, false) })
			t.eq(#dropped, 1)
			t.eq(dropped[1].kind, "teleport_bit_dropped")
			t.near(dropped[1].magnitude, 400 - 20 / 30, 1e-6)
			t.eq(dstats.teleportsDropped, 1)
			-- the send carried it and the network lost it
			local lost = wrapAt(6, { send(6, 6 / 30, true, true) })
			t.eq(lost[1].kind, "teleport_bit_lost")
			local lostTwice = wrapAt(6, { send(6, 6 / 30, true, true), send(8, 8 / 30, true, true) })
			t.eq(#lostTwice, 1)
			t.eq(lostTwice[1].kind, "teleport_bit_lost")
			-- lost, but the next send carries the flag again and arrives: the flag was not lost
			local repeated, rstats = wrapAt(6, { send(6, 6 / 30, true, true), send(8, 8 / 30, true, false) })
			t.eq(#repeated, 0)
			t.eq(rstats.teleportsCarried, 1)
			-- a jump and a heading snap the server never flagged
			local bench = Detect.bench(def)
			for i = 1, 12 do
				local jumped = i >= 6
				bench:tick(i / 30, {
					{
						id = 1,
						x = if jumped then 28 else 0,
						z = 20 * i / 30,
						yaw = if jumped then math.pi else 0,
						speed = 20,
					},
				})
			end
			local incidents, counts = bench:finish()
			t.eq(counts.sim_jump_unflagged, 1)
			t.eq(counts.sim_yaw_snap, 1)
			t.eq(#incidents, 2)
			t.near(incidents[1].t, 6 / 30, 1e-9)
			t.eq(incidents[1].origin, "sim")
		end
	)

	t.test("obstacles: through a building, off the carriageway (the trolley may use its rails)", function()
		local def = detectors.obstacles
		local strips: { any } = {
			{ id = "street", kind = "asphalt", axis = "z", coord = 0, min = -10, max = 100, half = 10, offset = 0.1 },
			{ id = "walk", kind = "concrete", axis = "z", coord = 14, min = -10, max = 100, half = 4, offset = 0.2 },
			{ id = "rails", kind = "rail", axis = "z", coord = 40, min = -10, max = 100, half = 3, offset = 0 },
		}
		local town = Town.new(strips, {})
		local colliders = Colliders.new()
		Colliders.add(
			colliders,
			{ id = "shed", cx = 0, cz = 30, hw = 3, hd = 3, y0 = 0, eave = 9, peak = 9, ridge = nil }
		)
		local world = { town = town, colliders = colliders }
		-- down the middle of the street: on the road, and straight through the shed that stands on it
		local incidents, counts = drive(def, { bench = world })
		t.eq(counts.through_building, 1)
		t.eq(counts.off_road, nil)
		t.eq((incidents[1].detail :: any).building, "shed")
		t.eq(incidents[1].origin, "sim", "the server drove it there")
		t.truthy(incidents[1].magnitude > 2.5, "right through")
		-- along the sidewalk: 4 st beyond the kerb
		local function sidewalk(clock: number): { [string]: any }
			return { x = 14, z = 20 * clock, yaw = 0, speed = 20 }
		end
		local walked, onWalk = drive(def, { bench = world, truth = sidewalk })
		t.eq(onWalk.off_road, 1)
		t.eq(onWalk.through_building, nil)
		t.near(walked[1].magnitude, 4, 1e-6, "studs from the carriageway's edge")
		t.eq((walked[1].detail :: any).nearestRoad, "street")
		-- on the rails: fine for the trolley, off the road for a sedan
		local function rails(clock: number): { [string]: any }
			return { x = 40, z = 20 * clock, yaw = 0, speed = 20 }
		end
		local _, sedan = drive(def, { bench = world, truth = rails })
		t.eq(sedan.off_road, 1)
		local _, trolley = drive(def, {
			truth = rails,
			bench = {
				town = town,
				colliders = colliders,
				vehicles = { [1] = { name = "Trolley", kind = "trolley", class = "trolley" } },
			},
		})
		t.eq(total(trolley), 0)
		-- a car standing off the road is parked, not driving there
		local _, parked = drive(def, {
			bench = world,
			truth = function(_clock: number): { [string]: any }
				return { x = 60, z = 5, yaw = 0, speed = 0 }
			end,
		})
		t.eq(total(parked), 0)
	end)
end
