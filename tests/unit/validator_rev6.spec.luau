--!strict
-- Adversarial review, round 6 (the displacement governor): failing cases.
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local MoveValidator = require("@server/Movement/MoveValidator")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local TestWorld = require("@tests/cheat/TestWorld")
local Height = require("@shared/World/Height")
local Data = require("@shared/Data")
local BakedWorld = require("@tests/lib/BakedWorld")
local LiveRig = require("@tests/lib/LiveRig")
local Driver = require("@tests/cheat/Driver")
local fs = require("@lune/fs")

type State = SquirrelMotor.State

local S = Height.STUDS_PER_UNIT
local RIVER = Height.RIVER

local function worldWith(boxes: { TestWorld.Box }): (any, any)
	local world = TestWorld.build({ boxes = boxes })
	local function wall(ox: number, oy: number, oz: number, dx: number, _dy: number, dz: number): boolean
		return TestWorld.segmentCrossesBox(boxes, ox, oz, ox + dx, oz + dz, oy)
	end
	local function down(_ox: number, oy: number, _oz: number, _dx: number, dy: number, _dz: number): boolean
		local lo = oy + dy
		return lo <= 0 and oy >= 0
	end
	return world, ValidatorWorld.build(world, { wall = wall, down = down })
end

-- the west quay's line at z (studs): where Recovery.riverFall puts a body that fell in from the west
local function quayX(z: number): number
	return (Height.riverCenterU(z / S) - (RIVER.halfWidth + 5)) * S
end
local BANK = (RIVER.bankY + 0.18) * S

return function(t)
	t.test("river: claimed quay landings, one a packet, run the quay at 300 st/s and reset the governor", function()
		local _, vworld = worldWith({})
		local fastest = 0
		for _, rate in { 2, 4, 10, 20 } do
			local v = MoveValidator.new(vworld)
			local dt = 1 / rate
			local z = -200 * S
			local s = SquirrelMotor.new(quayX(z), BANK, z)
			s.grounded, s.clock = true, 1
			local codes = {}
			v:accept("a", { seq = 1, snapshot = SquirrelMotor.serialize(s) }, 1)
			local z0, cleanAt = z, 1
			for i = 1, rate * 5 do
				local reach = 8.5 + v:fastest("a") * dt + 1
				local slack = v:fastest("a") * math.min(dt, 0.5) + 1
				-- the next landing: as far along as the quay rule's reach and slack allow, toward the water by the slack
				local nz = z + (reach + slack) * 0.97
				local nx = quayX(nz) + slack * 0.9
				local ns = SquirrelMotor.clone(s)
				ns.x, ns.y, ns.z, ns.clock = nx, BANK + 2 + slack, nz, 1 + i * dt
				local r = v:accept("a", { seq = i + 1, snapshot = SquirrelMotor.serialize(ns) }, 1 + i * dt)
				for _, x in r.violations do
					codes[x.code] = (codes[x.code] or 0) + 1
				end
				if r.accepted and r.ok then
					s, z, cleanAt = ns, nz, 1 + i * dt
				elseif r.accepted then
					-- (the live service snaps a violation back to the last clean packet, its history kept: the bare
					-- validator takes it as its baseline all the same, so the case does what the service does)
					v:reset("a", SquirrelMotor.serialize(s), 1 + i * dt, i + 1)
					v:anchor("a", s.x, s.y, s.z, 1 + i * dt, cleanAt)
				end
			end
			local c = {}
			for code, k in codes do
				table.insert(c, `{code}={k}`)
			end
			local pace = (z - z0) / 5
			fastest = math.max(fastest, pace)
			print(
				string.format(
					"      %d/s: %.0f st along the quay in 5 s (%.0f st/s), %s",
					rate,
					z - z0,
					pace,
					table.concat(c, " ")
				)
			)
		end
		local v = MoveValidator.new(vworld)
		local b = v:governorBounds(false)
		t.truthy(fastest <= b.vh + b.dh / 3, `the quay run at {fastest} st/s, the governor's bound {b.vh}`)
	end)

	t.test(
		"river: on the rig, the client runs the west quay at 150 st/s by claiming a river landing every packet",
		function()
			-- the quay as ground (the bank), the rest of the S3 world as it is
			local base = TestWorld.build()
			local world: any = table.clone(base)
			world.groundAt = function(x: number, z: number, refY: number): number
				return if x > 1800 then BANK else base.groundAt(x, z, refY)
			end
			local function wall(): boolean
				return false
			end
			local function down(ox: number, oy: number, _oz: number, _dx: number, dy: number, _dz: number): boolean
				local g = if ox > 1800 then BANK else 0
				return g >= oy + dy and g <= oy
			end
			local vworld = ValidatorWorld.build(world, { wall = wall, down = down })
			local z0 = -200 * S
			local started: number? = nil
			local rig = LiveRig.new({
				world = world,
				vworld = vworld,
				link = { latency = 0.1, jitter = 0.01, loss = 0 },
				seed = 3,
				cheat = function(s: State, _i: SquirrelMotor.Input, now: number, _w: any)
					if now < 3 then
						return
					end
					started = started or now
					local z = z0 + 150 * (now - (started :: number))
					s.x, s.y, s.z = quayX(z) + 2.5, BANK, z
					s.vx, s.vy, s.vz, s.grounded = 0, 0, 0, true
				end,
			})
			rig:possess(SquirrelMotor.new(quayX(z0), BANK, z0), function(): SquirrelMotor.Input
				return SquirrelMotor.idleInput(0)
			end)
			rig:run(8)
			local r = rig:result()
			local along = r.root.z - z0
			print(
				`      {LiveRig.describe("a river landing every packet", r)}; the root {string.format("%.0f", along)} st along the quay in 5 s`
			)
			t.truthy(along < 47.4 * 5 + 50, `the root ran {along} st along the quay in 5 s ({along / 5} st/s)`)
		end
	)

	t.test(
		"reset: Reset every 0.6 s with no packet and the root held still climbs 3 st a time into open air",
		function()
			-- Possession.recover (the Roblox menu's Reset, the remote `recover`: no rate limit) teleports the body to
			-- Recovery.resetTarget of the safe history (ActorsRuntime: the server's root sampled every 0.5 s while |vy| < 1)
			-- and 3 st over it: unstick finds no sample 4 st away across, so it is the newest, the place the last Reset put
			-- the body. Emulated here: the safe sample is where the server last put the root (the client holds it there)
			local world = TestWorld.build()
			local _, vworld = worldWith({})
			local held: { x: number, y: number, z: number }? = nil
			local resets = 0
			local rig: any
			rig = LiveRig.new({
				world = world,
				vworld = vworld,
				link = { latency = 0.1, jitter = 0.01, loss = 0 },
				seed = 5,
				silent = function(now: number): boolean
					return now >= 3
				end,
				cheat = function(s: State, _i: SquirrelMotor.Input, _now: number, _w: any)
					local h = held
					if h then
						s.x, s.y, s.z, s.vx, s.vy, s.vz = h.x, h.y, h.z, 0, 0, 0
					end
				end,
				rootCheat = function(p: { x: number, y: number, z: number }, _now: number, _s: State)
					local h = held
					if h then
						p.x, p.y, p.z = h.x, h.y, h.z
					end
				end,
			})
			local start = SquirrelMotor.new(0, world.groundHeight, 0)
			rig:possess(start, function(): SquirrelMotor.Input
				return SquirrelMotor.idleInput(0)
			end)
			for k = 0, 15 do
				rig:at(3.2 + k * 0.6, function()
					-- (validator fix 7: the Reset as the server now does it, LiveRig.reset: at most once per 3 s, to a place
					-- a clean grounded packet stood on a floor, the feet on it; the client holds its root there)
					if rig:reset() then
						local r = rig.server.root
						held = { x = r.x, y = r.y, z = r.z }
						resets += 1
					end
				end)
			end
			rig:run(13)
			local r = rig:result()
			local up = r.root.y - world.groundHeight
			print(
				`      {LiveRig.describe("Reset every 0.6 s", r)}; {resets} resets; the root {string.format("%.0f", up)} st over open ground`
			)
			t.truthy(up < 10, `the root stands {up} st over open ground after {resets} resets`)
		end
	)

	t.test(
		"bough: an honest drop (Q) off a branch stands on its bough cylinder, which the live floor ray looks past",
		function()
			if not fs.isFile("build/Town.rbxm") then
				t.truthy(false, "build/Town.rbxm (lune run tools/bake/main.luau)")
				return
			end
			Height.configure(Data.default():module("TerrainExtensions"))
			local town = BakedWorld.load("build/Town.rbxm")
			local w = town:motorWorld(Data.default())
			-- the live server's rays (ValidatorWorld.engineRays, by its own rule: BakedWorld.validatorRays). Round 6 had the
			-- floor ray look past the bough cylinders as the wall ray does; the floor now counts them (validator fix 7)
			local wall, down, cover = BakedWorld.validatorRays(town)
			local vworld = ValidatorWorld.build(w, { wall = wall, down = down, cover = cover })
			-- branches of the first big tree (Tree_220) and a wire over Tree_359, at two points each, 20 packets a second
			local rows, dirty = {}, 0
			for _, id in { 221, 224, 227, 65 } do
				local r = w.registry:get(id)
				for _, tt in { 0.35, 0.7 } do
					local p = w.registry:pointAt(r, tt)
					local s = SquirrelMotor.new(p.x, p.y, p.z)
					s.routeId, s.railT, s.grounded, s.clock = r.id, tt, false, 1
					local v = MoveValidator.new(vworld)
					local seq, codes, n = 0, {}, 0
					v:accept("a", { seq = 0, snapshot = SquirrelMotor.serialize(s) }, 1)
					for f = 1, 120 do
						local i = SquirrelMotor.idleInput(0)
						i.drop = f == 2
						SquirrelMotor.step(s, i, 1 / 60, w)
						if f % 3 == 0 then
							seq += 1
							local res = v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(s) }, s.clock)
							for _, x in res.violations do
								codes[x.code] = (codes[x.code] or 0) + 1
								n += 1
							end
						end
					end
					local _, part = town.groundPart(s.x, s.z, s.y)
					local c = {}
					for code, k in codes do
						table.insert(c, `{code}={k}`)
					end
					dirty += n
					table.insert(
						rows,
						string.format(
							"route %d t %.2f: stands %.1f st up on %s; %s",
							id,
							tt,
							s.y - town.terrainAt(s.x, s.z),
							if part then part.path else "terrain",
							table.concat(c, " ")
						)
					)
				end
			end
			for _, row in rows do
				print("      " .. row)
			end
			t.eq(dirty, 0, "an honest drop off a branch is never a violation")
		end
	)

	t.test(
		"short gap: off a trunk, 30 packets a second, each a 'hidden grab and leap' 13 st up: 135 st in 0.37 s",
		function()
			-- the envelope's round-6 allowance (section 5, "a short gap hides a grab and a leap"): any rail sample within a
			-- grab of the last place, not the nearest one, and the rise a launch's over that sample. Beside a vertical
			-- trunk the sample 8.5 st over the body is within a grab; the honest grab takes the nearest, at the body's height
			local world, vworld = worldWith({})
			local trunk: any = nil
			for _, r in Driver.targetsAround(world, 0, 0, 3000) do
				if trunk == nil or r.length > trunk.length then
					trunk = r
				end
			end
			local foot = world.registry:foot(trunk)
			local function climb(rate: number, govern: boolean): (number, number, string)
				local saved = MoveValidator._govern
				if not govern then
					MoveValidator._govern = function() end :: any
				end
				local v = MoveValidator.new(vworld)
				local dt = 1 / rate
				local s = SquirrelMotor.new(foot.x + 2.5, world.groundHeight, foot.z)
				s.grounded, s.clock = true, 1
				v:accept("a", { seq = 0, snapshot = SquirrelMotor.serialize(s) }, 1)
				local codes, y0, now = {}, s.y, 1
				for i = 1, rate * 3 do
					local prev = v:last("a") :: State
					local bestN, bestDy = prev, -1
					for _, vy in { -5, 0, 10, 20, 35 } do
						local lo, hi = 0, 40
						for _ = 1, 20 do
							local mid = (lo + hi) / 2
							local n = SquirrelMotor.clone(prev)
							n.y, n.vy, n.vx, n.vz, n.grounded, n.routeId, n.clock =
								prev.y + mid, vy, 0, 0, false, nil, prev.clock + dt
							if #SquirrelMotor.envelope(prev, n, dt, vworld, false) == 0 then
								lo = mid
							else
								hi = mid
							end
						end
						if lo > bestDy then
							bestDy = lo
							bestN = SquirrelMotor.clone(prev)
							bestN.y, bestN.vy, bestN.vx, bestN.vz, bestN.grounded, bestN.routeId, bestN.clock =
								prev.y + lo, vy, 0, 0, false, nil, prev.clock + dt
						end
					end
					now += dt
					local res = v:accept("a", { seq = i, snapshot = SquirrelMotor.serialize(bestN) }, now)
					for _, x in res.violations do
						codes[x.code] = (codes[x.code] or 0) + 1
					end
					if bestN.y > foot.y + trunk.length - 4 then
						break
					end
				end
				MoveValidator._govern = saved
				local c = {}
				for code, k in codes do
					table.insert(c, `{code}={k}`)
				end
				return (v:last("a") :: State).y - y0, now - 1, table.concat(c, " ")
			end
			local worst = 0
			for _, rate in { 30, 60 } do
				for _, govern in { false, true } do
					local up, secs, codes = climb(rate, govern)
					print(
						string.format(
							"      %d/s, governor %s: %.0f st up in %.2f s (%.0f st/s; the trunk's pace 19.2, the motor's E+Space 28.9); %s",
							rate,
							if govern then "on" else "off",
							up,
							secs,
							up / secs,
							codes
						)
					)
					if not govern and codes == "" then
						worst = math.max(worst, up / secs)
					end
				end
			end
			-- (the round-5 review's bound as the builder raised it, at 20 packets a second: 41.9 st/s)
			t.truthy(worst <= 41.9, `the envelope alone passed a climb at {worst} st/s beside a trunk`)
		end
	)
end
