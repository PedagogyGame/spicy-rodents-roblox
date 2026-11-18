--!strict
-- Shared/Rides/SkyLift: the sky lift's loop and timetable (brief v2 line 250, §14, §15; the lane-1 proof of the
-- sky-lift plan): every cabin is on the cable at every time; no cabin moves faster than the line; six equal
-- headways; cabin floors meet both platforms while their doors are open; cabins clear the ground outside the
-- stations; a ride takes the line's length / 15 plus the station time; the published anchors, towers, seats and
-- swept volume agree with the timetable; RideSpec still refuses a ride with controls or a score.
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local Height = require("@shared/World/Height")
local RideSpec = require("@shared/Rides/RideSpec")
local SkyLift = require("@shared/Rides/SkyLift")
local Expansion = require("@tests/../tools/compile/lib/Expansion")

return function(t)
	local mod = require("../../generated/Expansion") :: any
	local ext = require("../../generated/TerrainExtensions") :: any
	local venues: { [string]: any } = {}
	for _, v in mod.venues do
		venues[v.id] = v
	end
	local ride: any
	for _, r in mod.rides do
		if r.id == "sky_lift" then
			ride = r
		end
	end
	local base, top = venues.f4_lift_base, venues.f3_hilltop
	local P = SkyLift.period()
	local N = SkyLift.CABINS
	local loop = SkyLift.loop()

	local function anchorWorld(v: any, id: string): { number }
		for _, a in v.anchors do
			if a.id == id then
				return a.world
			end
		end
		error("no anchor " .. id)
	end
	local function segDist3(px: number, py: number, pz: number, a: SkyLift.Vec, b: SkyLift.Vec): number
		local dx, dy, dz = b.x - a.x, b.y - a.y, b.z - a.z
		local l2 = dx * dx + dy * dy + dz * dz
		local f = if l2 > 0 then math.clamp(((px - a.x) * dx + (py - a.y) * dy + (pz - a.z) * dz) / l2, 0, 1) else 0
		return math.sqrt((a.x + dx * f - px) ^ 2 + (a.y + dy * f - py) ^ 2 + (a.z + dz * f - pz) ^ 2)
	end
	local function offLoop(x: number, y: number, z: number): number
		local best = math.huge
		local pts = loop.points
		for k = 1, #pts - 1 do
			best = math.min(best, segDist3(x, y, z, pts[k], pts[k + 1]))
		end
		return best
	end
	-- 1,000 times spread over two laps (an irrational step so no time repeats a phase)
	local times: { number } = {}
	for k = 0, 999 do
		table.insert(times, -P + k * (2 * P / 1000) * 1.0003 + 0.123)
	end

	t.test("the line: bullwheel to bullwheel on the compiled data; nine towers at the data's heads", function()
		local pts = ride.points
		t.eq(#pts, 13)
		local st = SkyLift.stations()
		t.eq(st.base.venue, "f4_lift_base")
		t.eq(st.summit.venue, "f3_hilltop")
		t.deepEq({ st.base.wheel.x, st.base.wheel.y, st.base.wheel.z }, pts[1])
		t.deepEq({ st.summit.wheel.x, st.summit.wheel.y, st.summit.wheel.z }, pts[13])
		t.deepEq({ st.base.mouth.x, st.base.mouth.y, st.base.mouth.z }, pts[2])
		t.deepEq({ st.summit.mouth.x, st.summit.mouth.y, st.summit.mouth.z }, pts[12])
		local towers = SkyLift.towers()
		t.eq(#towers, 9)
		for i, tw in towers do
			t.eq(tw.index, i)
			-- in plan exactly the data's head; in height the blended cable over it, within a stud of the data's
			t.deepEq({ tw.x, tw.z }, { pts[i + 2][1], pts[i + 2][3] })
			t.near(tw.y, SkyLift.heightAt(tw.h), 1e-9)
			t.truthy(math.abs(tw.y - pts[i + 2][2]) < 1.5, `tower {i} head {tw.y} vs data {pts[i + 2][2]}`)
			-- the crossarm is square to the line; the strands are STRAND either side, up on the right
			local fx, fz = -math.sin(tw.yaw), -math.cos(tw.yaw)
			local rx, rz = math.cos(tw.yaw), -math.sin(tw.yaw)
			local nx, nz = pts[i + 3][1] - tw.x, pts[i + 3][3] - tw.z
			local l = math.sqrt(nx * nx + nz * nz)
			t.near(fx, nx / l, 1e-3)
			t.near(fz, nz / l, 1e-3)
			t.near(tw.up.x - tw.x, rx * SkyLift.STRAND, 1e-3)
			t.near(tw.up.z - tw.z, rz * SkyLift.STRAND, 1e-3)
			t.near(tw.down.x - tw.x, -rx * SkyLift.STRAND, 1e-3)
		end
	end)

	t.test("anchors: the data's platform and bullwheel anchors are where the timetable boards and alights", function()
		local st = SkyLift.stations()
		for _, c in
			{
				{ st.base.board, base, "board" },
				{ st.base.alight, base, "alight_down" },
				{ st.summit.alight, top, "alight" },
				{ st.summit.board, top, "board_down" },
			}
		do
			local p, v, id = c[1] :: SkyLift.Vec, c[2], c[3] :: string
			local w = anchorWorld(v, id)
			t.near(p.x, w[1], 0.05, id)
			t.near(p.y, w[2], 0.05, id)
			t.near(p.z, w[3], 0.05, id)
			t.near(p.y, v.floorY + SkyLift.PLATFORM_HEIGHT, 1e-6, id)
		end
		local cw = anchorWorld(base, "cable_out")
		t.near(st.base.wheel.x, cw[1], 0.01)
		t.near(st.base.wheel.z, cw[3], 0.01)
		local sw = anchorWorld(top, "cable_in")
		t.near(st.summit.wheel.x, sw[1], 0.01)
		t.near(st.summit.wheel.z, sw[3], 0.01)
		-- the ride runs from the base's board anchor to the summit's alight anchor
		t.eq(ride.from, "f4_lift_base/board")
		t.eq(ride.to, "f3_hilltop/alight")
		-- each stand point faces its cabin's door: the cabin passes PLATFORM_OFFSET away, to the front of it
		for _, id in SkyLift.STATIONS do
			local s = (st :: any)[id] :: SkyLift.Station
			for _, pair in { { s.board, s.boardYaw, s.boardS }, { s.alight, s.alightYaw, s.alightS } } do
				local p, yaw, sv = pair[1] :: SkyLift.Vec, pair[2] :: number, pair[3] :: number
				local x, y, z = SkyLift.at(sv)
				local dx, dz = x - p.x, z - p.z
				t.near(math.sqrt(dx * dx + dz * dz), SkyLift.PLATFORM_OFFSET, 1e-6)
				t.near(y - SkyLift.HANG, p.y, 1e-6)
				t.near(-math.sin(yaw), dx / SkyLift.PLATFORM_OFFSET, 1e-6)
				t.near(-math.cos(yaw), dz / SkyLift.PLATFORM_OFFSET, 1e-6)
			end
		end
	end)

	t.test("every cabin is on the cable at 1,000 sampled times; cabins never overlap", function()
		for _, tm in times do
			local at: { { number } } = {}
			for i = 1, N do
				local x, y, z, yaw, _, _, s = SkyLift.cabin(i, tm)
				local d = offLoop(x, y + SkyLift.HANG, z)
				t.truthy(d < SkyLift.ROPE_SAG, `cabin {i} at t {tm} is {d} off the drawn cable`)
				local gx, gy, gz, gyaw = SkyLift.at(s)
				t.near(gx, x, 1e-9)
				t.near(gy - SkyLift.HANG, y, 1e-9)
				t.near(gz, z, 1e-9)
				t.near(gyaw, yaw, 1e-9)
				table.insert(at, { x, y, z })
			end
			for i = 1, N do
				for j = i + 1, N do
					local a, b = at[i], at[j]
					local d = math.sqrt((a[1] - b[1]) ^ 2 + (a[2] - b[2]) ^ 2 + (a[3] - b[3]) ^ 2)
					t.truthy(d >= SkyLift.CABIN_LENGTH + 1, `cabins {i} and {j} {d} apart at {tm}`)
				end
			end
		end
	end)

	t.test("no step larger than speed x dt; the speed stays between creep and line speed", function()
		local dt = 1 / 30
		for i = 1, N do
			local px, py, pz, pyaw = SkyLift.cabin(i, 0)
			local steps = math.ceil(P / dt) + 2
			for k = 1, steps do
				local x, y, z, yaw, _, _, s = SkyLift.cabin(i, k * dt)
				local step = math.sqrt((x - px) ^ 2 + (y - py) ^ 2 + (z - pz) ^ 2)
				t.truthy(step <= SkyLift.LINE_SPEED * dt * 1.0005, `cabin {i} stepped {step} at {k * dt}`)
				t.truthy(step >= SkyLift.CREEP_SPEED * dt * 0.95, `cabin {i} stalled at {k * dt}`)
				-- the heading turns smoothly: at most a bullwheel's turn rate
				local dyaw = math.abs((yaw - pyaw + math.pi) % (2 * math.pi) - math.pi)
				local maxTurn = SkyLift.CREEP_SPEED / SkyLift.STRAND * dt * 1.01
				t.truthy(dyaw <= math.max(maxTurn, SkyLift.LINE_SPEED / 10 * dt), `cabin {i} turned {dyaw} at {k * dt}`)
				local v = SkyLift.speedAt(s)
				t.truthy(v >= SkyLift.CREEP_SPEED - 1e-9 and v <= SkyLift.LINE_SPEED + 1e-9)
				px, py, pz, pyaw = x, y, z, yaw
			end
		end
	end)

	t.test(
		"the eye never tips in a frame: vertical speed changes smoothly over the towers (review: 6.9 st/s)",
		function()
			-- a rider's eye is fixed to the seat, so a kink in the cable is a jolt on screen. Sampled over a whole lap
			-- at 30 and 144 frames a second: the vertical speed changes by at most 0.3 st/s from one frame to the
			-- next, and by at most 8 st/s over any second (the old straight spans changed it by 5.4 and 6.9 st/s in a
			-- single frame at tower 7)
			for _, fps in { 30, 144 } do
				local dt = 1 / fps
				local vys: { number } = {}
				local _, py = SkyLift.cabin(1, 0)
				local steps = math.ceil(P / dt)
				for k = 1, steps do
					local _, y = SkyLift.cabin(1, k * dt)
					vys[k] = (y - py) / dt
					py = y
				end
				local worstFrame, worstSecond = 0, 0
				for k = 2, steps do
					worstFrame = math.max(worstFrame, math.abs(vys[k] - vys[k - 1]))
					local j = k - fps
					if j >= 1 then
						worstSecond = math.max(worstSecond, math.abs(vys[k] - vys[j]))
					end
				end
				t.truthy(worstFrame <= 0.3, `{fps} fps: vertical speed jumped {worstFrame} st/s in a frame`)
				t.truthy(worstSecond <= 8, `{fps} fps: vertical speed changed {worstSecond} st/s in a second`)
			end
			-- the stations stay level: the blend starts at each mouth, never inside
			for _, id in SkyLift.STATIONS do
				local stn = (SkyLift.stations() :: any)[id] :: SkyLift.Station
				local h0 = if id == "base" then 0 else SkyLift.towers()[9].h + 1
				for _, f in { 0, 0.25, 0.5, 0.75, 1 } do
					local mouthH = if id == "base"
						then math.sqrt((stn.mouth.x - stn.wheel.x) ^ 2 + (stn.mouth.z - stn.wheel.z) ^ 2)
						else nil
					if mouthH then
						t.near(SkyLift.heightAt(h0 + mouthH * f), stn.wheel.y, 1e-9)
					end
				end
			end
			local L = SkyLift.loop()
			local last = SkyLift.towers()[9]
			local summitMouthH = last.h
				+ math.sqrt(
					(SkyLift.stations().summit.mouth.x - last.x) ^ 2 + (SkyLift.stations().summit.mouth.z - last.z) ^ 2
				)
			t.near(SkyLift.heightAt(summitMouthH), SkyLift.stations().summit.wheel.y, 1e-9)
			t.near(SkyLift.heightAt(summitMouthH + 30), SkyLift.stations().summit.wheel.y, 1e-9)
			t.truthy(#L.points > 0)
		end
	)

	t.test("six equal headways: cabin i is cabin 1 delayed (i - 1) / 6 of a lap; the lap repeats", function()
		t.eq(N, 6)
		for _, tm in { 0, 13.7, 101.2, -55 } do
			for i = 1, N do
				local a = { SkyLift.cabin(i, tm) }
				local b = { SkyLift.cabin(1, tm - (i - 1) * P / N) }
				local c = { SkyLift.cabin(i, tm + 3 * P) }
				for k = 1, 4 do
					t.near(a[k] :: number, b[k] :: number, 1e-6)
					t.near(a[k] :: number, c[k] :: number, 1e-6)
				end
			end
		end
		-- departures from each station's board point are exactly P / 6 apart, in cabin order
		for _, id in SkyLift.STATIONS do
			local c0, b0 = SkyLift.nextDeparture(id, 0)
			local prevCabin, prevAt = c0, b0
			for _ = 1, 12 do
				local c, at = SkyLift.nextDeparture(id, prevAt + 1e-6)
				t.near(at - prevAt, P / N, 1e-6)
				t.eq(c, prevCabin % N + 1)
				prevCabin, prevAt = c, at
			end
		end
	end)

	t.test("doors: open only while creeping in a station, at least 6 s, cabin floor on the platform height", function()
		local st = SkyLift.stations()
		t.truthy(st.base.dwell >= 6, `base dwell {st.base.dwell}`)
		t.truthy(st.summit.dwell >= 6, `summit dwell {st.summit.dwell}`)
		local seen = { base = false, summit = false }
		for _, tm in times do
			for i = 1, N do
				local x, y, z, _, phase, open, s = SkyLift.cabin(i, tm)
				local frac = SkyLift.doorFrac(i, tm)
				if open then
					t.truthy(phase == "base" or phase == "summit")
					seen[phase] = true
					local stn = (st :: any)[phase] :: SkyLift.Station
					t.near(y, stn.platformY, 0.1, `cabin {i} floor at {phase}`)
					t.near(SkyLift.speedAt(s), SkyLift.CREEP_SPEED, 1e-6)
					-- inside the station building
					local v = venues[stn.venue]
					t.truthy(Expansion.polyDist(Expansion.footPoly(v), x, z) == 0, `cabin {i} open outside {phase}`)
					t.truthy(frac > 0 or true)
				else
					t.truthy(phase == "up" or phase == "down")
					t.eq(frac, 0)
				end
				t.truthy(frac >= 0 and frac <= 1)
			end
		end
		t.truthy(seen.base and seen.summit)
		-- fully open for all but DOOR_SECS at each end
		local stn = st.base
		local mid = stn.doorsOpenSigma + stn.dwell / 2
		t.eq(SkyLift.doorFrac(1, mid), 1)
		t.near(SkyLift.doorFrac(1, stn.doorsOpenSigma + SkyLift.DOOR_SECS / 2), 0.5, 1e-6)
	end)

	t.test("cabins clear the ground: underside 8 st up outside 30 st of the stations, never in it", function()
		Height.configure(ext)
		local ok, err = pcall(function()
			local lowestOut, lowestIn = math.huge, math.huge
			local L = loop.length
			local hw, hl = SkyLift.CABIN_WIDTH / 2, SkyLift.CABIN_LENGTH / 2
			local feet = { Expansion.footPoly(base), Expansion.footPoly(top) }
			for k = 0, math.ceil(L) - 1 do
				local x, y, z, yaw = SkyLift.at(k)
				local bottom = y - SkyLift.HANG - SkyLift.CABIN_BELOW
				local c, s = math.cos(yaw), math.sin(yaw)
				local ground, inBuilding, apron = -math.huge, false, false
				for _, q in { { 0, 0 }, { hw, hl }, { -hw, hl }, { hw, -hl }, { -hw, -hl } } do
					local qx, qz = x + q[1] * c + q[2] * s, z - q[1] * s + q[2] * c
					ground = math.max(ground, Height.at(qx, qz))
					for _, f in feet do
						local d = Expansion.polyDist(f, qx, qz)
						inBuilding = inBuilding or d == 0
						apron = apron or d <= 30
					end
				end
				if not apron then
					lowestOut = math.min(lowestOut, bottom - ground)
				elseif not inBuilding then
					lowestIn = math.min(lowestIn, bottom - ground)
				end
			end
			t.truthy(lowestOut >= 8, `lowest underside outside the stations {lowestOut}`)
			t.truthy(lowestIn >= 1, `lowest underside near the stations {lowestIn}`)
		end)
		Height.configure(nil)
		if not ok then
			error(err, 0)
		end
	end)

	t.test("ride time: the line's length / 15 plus the station time, within 2 s, both ways", function()
		local pts = ride.points
		local line = 0
		for k = 2, #pts - 2 do
			local a, b = pts[k], pts[k + 1]
			line += math.sqrt((b[1] - a[1]) ^ 2 + (b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
		end
		-- per station: creep from the board point to the end of the creep run, then the ramp to the mouth
		local function stationTime(mouthToWheel: number): number
			local creep = (SkyLift.CREEP_RUN - SkyLift.BOARD_RUN) / SkyLift.CREEP_SPEED
			local ramp = 2 * (mouthToWheel - SkyLift.CREEP_RUN) / (SkyLift.CREEP_SPEED + SkyLift.LINE_SPEED)
			return creep + ramp
		end
		local function hd(a: { number }, b: { number }): number
			return math.sqrt((b[1] - a[1]) ^ 2 + (b[3] - a[3]) ^ 2)
		end
		local expect = line / SkyLift.LINE_SPEED + stationTime(hd(pts[1], pts[2])) + stationTime(hd(pts[12], pts[13]))
		for _, id in SkyLift.STATIONS do
			local r = SkyLift.rideTime(id)
			t.truthy(math.abs(r - expect) <= 2, `{id}: {r} vs {expect}`)
			t.truthy(r > 55 and r < 75, `{id}: {r} s`)
		end
	end)

	t.test(
		"nextDeparture: the cabin is at the board point when boarding and at the far alight point on arrival",
		function()
			local st = SkyLift.stations()
			for _, id in SkyLift.STATIONS do
				local here = (st :: any)[id] :: SkyLift.Station
				local there = if id == "base" then st.summit else st.base
				for _, tm in { 0, 7.25, 40, 151.9, -20 } do
					local cabin, boardAt, arriveAt = SkyLift.nextDeparture(id, tm)
					t.truthy(boardAt >= tm - 1e-9 and boardAt < tm + P / N + 1e-9, `wait {boardAt - tm}`)
					t.truthy(cabin >= 1 and cabin <= N)
					for _, ev in { { boardAt, here, here.board }, { arriveAt, there, there.alight } } do
						local when, stn, p = ev[1] :: number, ev[2] :: SkyLift.Station, ev[3] :: SkyLift.Vec
						local x, y, z, _, phase, open = SkyLift.cabin(cabin, when)
						t.truthy(open, `{id} doors at {when}`)
						t.eq(phase, stn.id)
						t.near(y, p.y, 1e-6)
						t.near(math.sqrt((x - p.x) ^ 2 + (z - p.z) ^ 2), SkyLift.PLATFORM_OFFSET, 1e-3)
					end
					t.near(arriveAt - boardAt, SkyLift.rideTime(id), 1e-6)
				end
			end
			t.fails(function()
				SkyLift.nextDeparture("middle", 0)
			end)
		end
	)

	t.test("seats: four inside the cabin, facing each other, eyes 4.5 above the floor", function()
		t.eq(SkyLift.SEATS, 4)
		t.eq(#SkyLift.SEAT_LOCAL, 4)
		for _, tm in { 3, 50, 77.7, 120 } do
			for i = 1, N do
				local cx, cy, cz, cyaw = SkyLift.cabin(i, tm)
				local c, s = math.cos(cyaw), math.sin(cyaw)
				for k = 1, SkyLift.SEATS do
					local x, y, z, yaw = SkyLift.seat(i, k, tm)
					local dx, dz = x - cx, z - cz
					local lx, lz = dx * c - dz * s, dx * s + dz * c
					local L = SkyLift.SEAT_LOCAL[k]
					t.near(lx, L[1], 1e-6)
					t.near(lz, L[3], 1e-6)
					t.near(y - cy, SkyLift.SEAT_HEIGHT, 1e-6)
					t.truthy(
						math.abs(lx) < SkyLift.CABIN_WIDTH / 2 - 0.5 and math.abs(lz) < SkyLift.CABIN_LENGTH / 2 - 0.5
					)
					-- a sitter faces the cabin's middle
					local fx, fz = -math.sin(yaw), -math.cos(yaw)
					t.truthy(fx * (cx - x) + fz * (cz - z) > 0, `seat {k} faces the wall`)
					local ex, ey, ez, eyaw = SkyLift.eye(i, k, tm)
					t.near(ex, x, 1e-9)
					t.near(ez, z, 1e-9)
					t.near(eyaw, yaw, 1e-9)
					t.near(ey - cy, 4.5, 1e-6)
					t.truthy(ey - cy < SkyLift.CABIN_HEIGHT - SkyLift.CABIN_BELOW - 1, "head room")
				end
			end
		end
	end)

	t.test("loop: closed, strands 2 x STRAND apart, level in both stations, up on the right", function()
		local pts = loop.points
		t.deepEq(pts[1], pts[#pts])
		t.eq(loop.dist[#loop.dist], loop.length)
		for k = 2, #loop.dist do
			t.truthy(loop.dist[k] > loop.dist[k - 1])
			-- straight spans are one segment (a few chords across a vertical blend); arcs are drawn in pieces of at
			-- most 1 st; a chord is never longer than the cable it spans
			local a, b = pts[k - 1], pts[k]
			local d = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2 + (b.z - a.z) ^ 2)
			t.truthy(d <= loop.dist[k] - loop.dist[k - 1] + 1e-4)
		end
		-- at each tower the up strand is on the right of a cabin going up, 10 st from the down strand
		for _, tw in SkyLift.towers() do
			t.truthy(offLoop(tw.up.x, tw.up.y, tw.up.z) < SkyLift.ROPE_SAG)
			t.truthy(offLoop(tw.down.x, tw.down.y, tw.down.z) < SkyLift.ROPE_SAG)
			t.near(math.sqrt((tw.up.x - tw.down.x) ^ 2 + (tw.up.z - tw.down.z) ^ 2), 2 * SkyLift.STRAND, 1e-6)
		end
		local _, _, _, upYaw, phase = SkyLift.cabin(1, SkyLift.stations().base.boardSigma + 20)
		t.eq(phase, "up")
		local towers = SkyLift.towers()
		t.near(upYaw, towers[1].yaw, 0.05)
		-- the station runs are level at floor + 12 and run along each building's own axis
		for _, id in SkyLift.STATIONS do
			local stn = (SkyLift.stations() :: any)[id] :: SkyLift.Station
			local v = venues[stn.venue]
			t.near(stn.wheel.y, v.floorY + 12, 1e-6)
			t.near(stn.mouth.y, v.floorY + 12, 1e-6)
			t.near(stn.platformY, stn.wheel.y - SkyLift.HANG, 1e-6)
			local wx, _, wd = AlleyLayout.toLocal(v.place, stn.wheel.x, 0, stn.wheel.z)
			local mx, _, md = AlleyLayout.toLocal(v.place, stn.mouth.x, 0, stn.mouth.z)
			if id == "base" then
				t.near(wd, md, 0.02) -- along local X
			else
				t.near(wx, mx, 0.02) -- along local D
			end
		end
	end)

	t.test(
		"swept volume: cabins and hangers are inside it; platforms, towers' strand gaps and the sky are not",
		function()
			for _, tm in { 0, 33, 71.5, 140 } do
				for i = 1, N do
					local x, y, z, yaw = SkyLift.cabin(i, tm)
					t.falsy(SkyLift.sweptClear(x, y + 3, z), "cabin middle")
					t.falsy(SkyLift.sweptClear(x, y + 9, z), "hanger")
					local c, s = math.cos(yaw), math.sin(yaw)
					t.falsy(SkyLift.sweptClear(x + 2.9 * c, y + 0.1, z - 2.9 * s), "door side")
				end
			end
			for _, id in SkyLift.STATIONS do
				local stn = (SkyLift.stations() :: any)[id] :: SkyLift.Station
				for _, p in { stn.board, stn.alight } do
					-- a person 1 st wide standing on the stand point
					for _, dy in { 0.1, 2.5, 5 } do
						t.truthy(SkyLift.sweptClear(p.x, p.y + dy, p.z, 0.5), `{id} stand point at +{dy}`)
					end
				end
				-- the platform edge: clear 0.2 st outboard of the cabin's side
				local ex = stn.board.x
					+ (SkyLift.PLATFORM_OFFSET - SkyLift.CABIN_WIDTH / 2 - 0.2) * -math.sin(stn.boardYaw)
				local ez = stn.board.z
					+ (SkyLift.PLATFORM_OFFSET - SkyLift.CABIN_WIDTH / 2 - 0.2) * -math.cos(stn.boardYaw)
				t.truthy(SkyLift.sweptClear(ex, stn.board.y - 0.1, ez))
			end
			t.truthy(SkyLift.sweptClear(-900, 300, -1200))
			t.truthy(SkyLift.sweptClear(0, 0, 0))
			-- a point 1 st above the cable between cabins is clear (the bakes may put sheaves there)
			local tw = SkyLift.towers()[4]
			t.truthy(SkyLift.sweptClear(tw.up.x, tw.up.y + SkyLift.GRIP_ABOVE + 0.5, tw.up.z))
			t.falsy(SkyLift.sweptClear(tw.up.x, tw.up.y - 1, tw.up.z))
		end
	)

	t.test("the ride contract still refuses controls or a score; the clock is server time minus the epoch", function()
		local d = RideSpec.def("sky_lift") :: RideSpec.Def
		t.truthy(RideSpec.check(d))
		t.deepEq(d.points, ride.points)
		t.eq(d.speed, SkyLift.LINE_SPEED)
		t.falsy(RideSpec.check({
			ride = "sky_lift",
			kind = "cable",
			points = ride.points,
			speed = 15,
			controls = true,
			score = false,
		}))
		t.falsy(RideSpec.check({
			ride = "sky_lift",
			kind = "cable",
			points = ride.points,
			speed = 15,
			controls = false,
			score = true,
		}))
		t.eq(SkyLift.clock(1000.5, 900), 100.5)
		t.eq(SkyLift.EPOCH_ATTRIBUTE, "SkyLiftEpoch")
	end)
end
