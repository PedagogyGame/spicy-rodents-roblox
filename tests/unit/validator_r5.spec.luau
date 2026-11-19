--!strict
-- Validator round 5 (the round-4 review's findings, fixed): the motor packet's field audit, and attack cases for every
-- allowance added or changed this round, played by a greedy adversary (each packet the most the validator passes) at 2
-- to 30 packets a second, with clocks x0.5 to x1.3, alternating packet types and rail touches:
--   fields     every wire field has a bound (SquirrelMotor.FIELD_BOUNDS); each range, enum and length is enforced; a
--              transfer's start and easing cannot hold a body beside a rail
--   railspeed  a long gap on one rail: the faster of the run and a leap's chord (the grab radius no longer added)
--   exit       off a rail: across a launch's flight, up a launch's rise; a hidden rail visit only near and reachable;
--              rail touches (off, back on, off) climb no faster than the rail and a leap
--   roofed     a leap's rise over a wall only under open sky: no way into a roofed house at any rate
--   float      a grounded packet where the stand height is unknown needs a floor just under it; on a car's roof a third
--   clicks     the click's copy in the packets: once per click, no earlier dating than the remote's, the order judged
--              when the pounce is dated (a lunge held behind the click is not tied)
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local SquirrelWire = require("@shared/Movement/SquirrelWire")
local Tunables = require("@shared/Config/Tunables")
local CombatRules = require("@shared/Combat/CombatRules")
local CombatService = require("@server/Combat/CombatService")
local MoveValidator = require("@server/Movement/MoveValidator")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local Solid = require("@shared/Traffic/Solid")
local TestWorld = require("@tests/cheat/TestWorld")
local LiveRig = require("@tests/lib/LiveRig")
local Driver = require("@tests/cheat/Driver")
local Motion = require("@shared/Routes/Motion")
local Units = require("@shared/Config/Units")

type State = SquirrelMotor.State

local QUIET = { latency = 0.1, jitter = 0.01, loss = 0 }
local CHEAT_AT = 5
local P = SquirrelMotor.params
local E = SquirrelMotor.envelopeParams
local RATES = { 2, 4, 10, 20, 30 } -- packets a second
local CLOCKS = { 0.5, 1, 1.3 } -- the client's clock against real time

-- the S3 world with open ground (y 0), `boxes` as solid houses (hollow ones as four walls, `roofs` as floors at their
-- top), and its validator world (cars: a Traffic/Solid floors set the floor rays also meet)
local function worldWith(boxes: { TestWorld.Box }, roofs: { TestWorld.Box }?, cars: any?): (any, any)
	local world = TestWorld.build({ boxes = boxes })
	local function wall(ox: number, oy: number, oz: number, dx: number, _dy: number, dz: number): boolean
		return TestWorld.segmentCrossesBox(boxes, ox, oz, ox + dx, oz + dz, oy)
	end
	local function down(ox: number, oy: number, oz: number, _dx: number, dy: number, _dz: number): boolean
		local lo = oy + dy
		if lo <= 0 and oy >= 0 then
			return true
		end
		for _, b in roofs or boxes do
			if ox > b.minX and ox < b.maxX and oz > b.minZ and oz < b.maxZ and b.top >= lo and b.top <= oy then
				return true
			end
		end
		return false
	end
	return world, ValidatorWorld.build(world, { wall = wall, down = down, cars = cars })
end

local function codesOf(list: { { code: string } }): string
	local out = {}
	for _, v in list do
		table.insert(out, v.code)
	end
	return table.concat(out, ",")
end

-- the largest x in [lo, hi] that `ok` passes (nil when lo does not): 20 halvings
local function most(lo: number, hi: number, ok: (x: number) -> boolean): number?
	if not ok(lo) then
		return nil
	end
	if ok(hi) then
		return hi
	end
	for _ = 1, 20 do
		local mid = (lo + hi) / 2
		if ok(mid) then
			lo = mid
		else
			hi = mid
		end
	end
	return lo
end

-- does the validator's envelope and field check pass the move (the greedy adversary's oracle)? A long line through a
-- wall the envelope leaves to the validator to weigh as a gap's (a third, a second inside 20 s a whole flag) is no pass
local function clean(v: any, prev: State, next: State, dt: number): boolean
	if #SquirrelMotor.fieldCheck(SquirrelMotor.serialize(next), v.world) > 0 then
		return false
	end
	local found, _, _, judged = SquirrelMotor.envelope(prev, next, dt, v.world, false)
	return #found == 0 and not judged.longWall
end

local function longestWire(world: any): any
	local best: any = nil
	for _, r in world.registry:all() do
		if r.kind == "wire" and (best == nil or r.length > best.length) then
			best = r
		end
	end
	return best
end

local function onRail(world: any, r: any, tt: number): State
	local p = world.registry:pointAt(r, tt)
	local s = SquirrelMotor.new(p.x, p.y, p.z)
	s.routeId, s.railT, s.grounded = r.id, tt, false
	return s
end

return function(t)
	local base = TestWorld.build()
	local trunks = Driver.targetsAround(base, 0, 0, 2000)
	local trunk = Driver.targetsAround(base, 0, 0, 200)[1]
	local foot = base.registry:foot(trunk)
	-- the tallest trunk (a climb to rail touch along)
	local tall = trunk
	for _, r in trunks do
		if r.length > tall.length then
			tall = r
		end
	end

	-- fields -----------------------------------------------------------------------------------------------------------
	t.test("fields: every field on the wire has a bound, and every bound is a wire field", function()
		local onWire: { [string]: boolean } = {}
		for _, k in SquirrelWire.FIELDS do
			onWire[k] = true
			t.truthy(SquirrelMotor.FIELD_BOUNDS[k] ~= nil, `{k} has a bound`)
		end
		for k in SquirrelMotor.FIELD_BOUNDS do
			t.truthy(onWire[k], `{k} is a wire field`)
		end
		print(`      {#SquirrelWire.FIELDS} wire fields, each bounded`)
	end)

	t.test("fields: an honest packet passes; each field out of its bound is flagged", function()
		local world, vworld = worldWith({})
		local wire = longestWire(world)
		local function snap(edit: ((s: { [string]: any }) -> ())?): { [string]: any }
			local s = onRail(world, wire, 0.3)
			s.clock = 12.5
			local out = SquirrelMotor.serialize(s) :: any
			out.clickSeq, out.clickAgo = 3, 0.2
			if edit then
				edit(out)
			end
			-- (through the wire: what the server reads)
			local _, _, back = SquirrelWire.decode(SquirrelWire.encode(1, 1, out))
			for k, v in out do
				if back[k] == nil then
					back[k] = v
				end
			end
			if edit then
				edit(back)
			end
			return back
		end
		t.eq(#SquirrelMotor.fieldCheck(snap(), vworld), 0, "an honest packet")
		local bad: { { any } } = {
			{
				"trunkNormal x5",
				function(s)
					s.trunkNormalX, s.trunkNormalZ = 5, 0
				end,
			},
			{
				"trunkNormal x0",
				function(s)
					s.trunkNormalX, s.trunkNormalZ = 0, 0
				end,
			},
			{
				"railT 1.5",
				function(s)
					s.railT = 1.5
				end,
			},
			{
				"railT -0.2",
				function(s)
					s.railT = -0.2
				end,
			},
			{
				"vx 500",
				function(s)
					s.vx = 500
				end,
			},
			{
				"vy 100",
				function(s)
					s.vy = 100
				end,
			},
			{
				"vy -500",
				function(s)
					s.vy = -500
				end,
			},
			{
				"moveSpeed 200",
				function(s)
					s.moveSpeed = 200
				end,
			},
			{
				"moveSpeed -1",
				function(s)
					s.moveSpeed = -1
				end,
			},
			{
				"boostRemaining 1000",
				function(s)
					s.boostRemaining = 1000
				end,
			},
			{
				"cooldown 3",
				function(s)
					s.cooldown = 3
				end,
			},
			{
				"attack 2",
				function(s)
					s.attack = 2
				end,
			},
			{
				"attackWindow -0.1",
				function(s)
					s.attackWindow = -0.1
				end,
			},
			{
				"attackWindow 2",
				function(s)
					s.attackWindow = 2
				end,
			},
			{
				"cameraCommit 9",
				function(s)
					s.cameraCommit = 9
				end,
			},
			{
				"routeFreeLook 9",
				function(s)
					s.routeFreeLook = 9
				end,
			},
			{
				"stamina 1.5",
				function(s)
					s.stamina = 1.5
				end,
			},
			{
				"emergedEnd 0.5",
				function(s)
					s.emergedEnd = 0.5
				end,
			},
			{
				"emergedFw 3",
				function(s)
					s.emergedFw = 3
				end,
			},
			{
				"pendingFork 999999",
				function(s)
					s.pendingFork = 999999
				end,
			},
			{
				"selectedJunction 999999",
				function(s)
					s.selectedJunction = 999999
				end,
			},
			{
				"emergedFrom 999999",
				function(s)
					s.emergedFrom = 999999
				end,
			},
			{
				"railDir 0",
				function(s)
					s.railDir = 0
				end,
			},
			{
				"grounded 1",
				function(s)
					s.grounded = 1
				end,
			},
			{
				"clickSeq 1.5",
				function(s)
					s.clickSeq = 1.5
				end,
			},
			{
				"clickAgo 2",
				function(s)
					s.clickAgo = 2
				end,
			},
			{
				"clickAgo with no click",
				function(s)
					s.clickSeq, s.clickAgo = 0, 0.2
				end,
			},
			{
				"a transfer 30 st long",
				function(s)
					s.bridgeActive = true
					s.bfx, s.bfy, s.bfz = s.x + 30, s.y, s.z
					s.btx, s.bty, s.btz = s.x, s.y, s.z
					s.bElapsed, s.bDuration = 0, Motion.bridgeDuration(30)
				end,
			},
			{
				"a transfer's easing not its length's",
				function(s)
					s.bridgeActive = true
					s.bfx, s.bfy, s.bfz = s.x + 3, s.y, s.z
					s.btx, s.bty, s.btz = s.x, s.y, s.z
					s.bElapsed, s.bDuration = 0, Motion.C.bridgeMax + 5
				end,
			},
			{
				"a transfer before its start",
				function(s)
					s.bridgeActive = true
					s.bfx, s.bfy, s.bfz = s.x + 3, s.y, s.z
					s.btx, s.bty, s.btz = s.x, s.y, s.z
					s.bElapsed, s.bDuration = -0.5, Motion.bridgeDuration(3)
				end,
			},
			{
				"a transfer off any rail",
				function(s)
					s.routeId = -1
					s.bridgeActive = true
					s.bfx, s.bfy, s.bfz = s.x + 3, s.y, s.z
					s.btx, s.bty, s.btz = s.x, s.y, s.z
					s.bElapsed, s.bDuration = 0, Motion.bridgeDuration(3)
				end,
			},
		}
		for _, c in bad do
			local found = SquirrelMotor.fieldCheck(snap(c[2]), vworld)
			t.truthy(#found >= 1, `{c[1]} is flagged`)
		end
		print(`      {#bad} out-of-bound fields, each flagged`)
	end)

	t.test(
		"fields: a transfer's start held beside a rail (frozen, or a new one every packet) at 2 to 30 a second",
		function()
			local world, vworld = worldWith({})
			local wire = longestWire(world)
			local rows = {}
			for _, rate in RATES do
				for _, how in { "frozen", "renewed" } do
					local v = MoveValidator.new(vworld)
					local dt = 1 / rate
					local tt = 0.3
					local s = onRail(world, wire, tt)
					v:accept("a", { seq = 1, snapshot = SquirrelMotor.serialize(s) }, 0)
					local bad, sent = 0, 0
					local side = Motion.C.enterMaxGap -- (the widest a transfer starts from its target)
					for i = 1, math.ceil(3 * rate) do
						tt += 10 * dt / wire.length -- (a walk along the wire)
						local q = world.registry:pointAt(wire, tt)
						s.railT, s.x, s.y, s.z = tt, q.x, q.y, q.z
						s.clock = i * dt
						local fx, fy, fz = q.x + side, q.y, q.z
						if how == "frozen" and i > 1 then
							fx, fy, fz = (s.bridge :: any).fx, (s.bridge :: any).fy, (s.bridge :: any).fz
						end
						s.bridge = {
							fx = fx,
							fy = fy,
							fz = fz,
							tx = q.x,
							ty = q.y,
							tz = q.z,
							elapsed = 0,
							duration = Motion.bridgeDuration(
								math.sqrt((q.x - fx) ^ 2 + (q.y - fy) ^ 2 + (q.z - fz) ^ 2)
							),
						}
						-- (the body at the transfer's start: beside the rail)
						s.x, s.y, s.z = fx, fy, fz
						local r = v:accept("a", { seq = i + 1, snapshot = SquirrelMotor.serialize(s) }, s.clock)
						sent += 1
						if #r.violations > 0 then
							bad += 1
						end
					end
					table.insert(rows, `{rate}/s {how}: {bad}/{sent} flagged`)
					t.truthy(bad >= sent - 1, `{rate}/s, {how}: a body held a transfer's reach off the rail is flagged`)
				end
			end
			print(`      {table.concat(rows, "; ")}`)
		end
	)

	-- railspeed --------------------------------------------------------------------------------------------------------
	-- along a rail as fast as the validator passes, each packet the furthest railT it takes, at each rate and clock: the
	-- pace against the bound an honest body has (the faster of its run and a leap along it)
	local function railGreedy(
		world: any,
		vworld: any,
		r: any,
		rate: number,
		clockRate: number
	): (number, number, number)
		local v = MoveValidator.new(vworld)
		local tt = 0.02
		local s = onRail(world, r, tt)
		v:accept("a", { seq = 1, snapshot = SquirrelMotor.serialize(s) }, 0)
		local real = 1 / rate
		local dtc = real * clockRate
		local server, clock, moved, bad, n = 0, 0, 0, 0, 0
		while server < 2.5 and tt < 0.97 do
			server += real
			clock += dtc
			n += 1
			local prev = v:last("a")
			local best = most(0, 400 * dtc, function(d: number): boolean
				local cand = onRail(world, r, math.min(1, tt + d / r.length))
				cand.clock = clock
				return clean(v, prev, cand, dtc)
			end) or 0
			tt = math.min(1, tt + best / r.length)
			s = onRail(world, r, tt)
			s.clock = clock
			moved += best
			local res = v:accept("a", { seq = n + 1, snapshot = SquirrelMotor.serialize(s) }, server)
			bad += #res.violations
		end
		return moved / server, bad, n
	end

	t.test("railspeed: greedy along a wire and up a trunk at 2 to 30 packets a second, clocks x0.5 to x1.3", function()
		local world, vworld = worldWith({})
		local wire = longestWire(world)
		local rows = {}
		for _, r in { wire, tall } do
			local cap = SquirrelMotor.routeCap(r, false)
			local launchXZ = SquirrelMotor.launchCapXZ(false) * E.launchTol
			for _, rate in RATES do
				for _, k in CLOCKS do
					local pace, bad, n = railGreedy(world, vworld, r, rate, k)
					local dt = k / rate
					-- the bound an honest body has along it in a gap of the client's dt, per real second: its run, or (a long
					-- gap) the run and a leap along it and a grab back, the time shared (up a trunk the leap's rise)
					local honestRun = (cap * E.railTol * dt + cap * P.substep) / (1 / rate)
					local L = P.leapUp * E.launchTol
					local capT = cap * E.railTol
					local t2 = math.clamp((L - capT) / P.gravity, 0, dt)
					local along = if r.kind == "trunk"
						then capT * (dt - t2) + L * t2 - 0.5 * P.gravity * t2 * t2
						else math.max(capT, launchXZ) * dt
					local honest = if dt <= E.shortDt
						then honestRun
						else math.max(honestRun, (along + cap * P.substep + 3) * rate)
					table.insert(
						rows,
						`{r.kind} {rate}/s x{k}: {string.format("%.1f", pace)} st/s ({bad} viol. in {n}; honest bound {string.format(
							"%.1f",
							honest
						)}, cap {cap})`
					)
					if k <= 1 then
						t.truthy(
							pace <= honest * 1.01 + 0.5,
							`{r.kind} at {rate}/s x{k}: {pace} st/s within the honest bound`
						)
						t.eq(bad, 0, `{r.kind} at {rate}/s x{k}: the greedy packets pass`)
					else
						-- a clock run fast is the clock check's: the gain is the clock's, and flagged
						t.truthy(
							pace <= honest * k * 1.01 + 0.5,
							`{r.kind} at {rate}/s x{k}: no more than the clock's gain`
						)
					end
				end
			end
		end
		for _, row in rows do
			print(`      {row}`)
		end
	end)

	-- exit -------------------------------------------------------------------------------------------------------------
	t.test(
		"exit: greedy straight up and level off a trunk at every gap; another rail near only when reachable",
		function()
			local world, vworld = worldWith({})
			local v = MoveValidator.new(vworld)
			local launchUp = P.leapUp * E.launchTol
			local launchXZ = SquirrelMotor.launchCapXZ(false) * E.launchTol
			local rows = {}
			for _, rate in RATES do
				local dt = 1 / rate
				for _, tt in { 0.5, 1 } do
					local prev = onRail(world, tall, tt)
					local vis = SquirrelMotor.visualPose(prev, world)
					-- up: the highest `next` (any vertical speed it may claim) above the drawn pose
					local bestUp = -math.huge
					for vy = -P.gravity * dt, launchUp, 1 do
						local up = most(0, 80, function(h: number): boolean
							local n = SquirrelMotor.new(vis.x, vis.y + h, vis.z)
							n.grounded, n.committedAirborne, n.vy = false, true, vy
							n.clock = dt
							return clean(v, prev, n, dt)
						end)
						bestUp = math.max(bestUp, up or -math.huge)
					end
					-- level: the furthest across, out along the bark's normal
					local across = most(0, 120, function(d: number): boolean
						local n = SquirrelMotor.new(vis.x + d, vis.y, vis.z)
						n.grounded, n.committedAirborne, n.vy = false, true, 0
						n.clock = dt
						return clean(v, prev, n, dt)
					end) or 0
					local railCap = SquirrelMotor.routeCap(tall, false)
					-- (an honest body: up the trunk, a leap, a grab of a bough a grab's reach higher and a leap off it, the
					-- gap's time shared between the climb and the two leaps; a short gap hides no grab)
					local capT = railCap * E.railTol
					local n = if dt > E.shortDt then 2 else 1
					local t2 = math.clamp(n * (launchUp - capT) / P.gravity, 0, dt)
					local honestUp = capT * (dt - t2)
						+ launchUp * t2
						- P.gravity * t2 * t2 / (2 * n)
						+ (if dt > E.shortDt then Motion.C.airGrab + Motion.C.visualBranchLift else 0)
						-- (and the gravity tolerance on the launch's speed: E.gravityEps of gravity, about a stud of rise)
						+ P.gravity * E.gravityEps * launchUp / P.gravity
						+ 0.2
					local honestAcross = launchXZ * dt + 2 * Motion.C.airGrab + railCap * dt + 2
					table.insert(
						rows,
						`dt {string.format("%.3f", dt)} t {tt}: up {string.format("%.1f", bestUp)} (bound {string.format(
							"%.1f",
							honestUp
						)}), across {string.format("%.1f", across)} (bound {string.format("%.1f", honestAcross)})`
					)
					t.truthy(bestUp <= honestUp, `up off a trunk in {dt} s: {bestUp}`)
					t.truthy(across <= honestAcross, `across off a trunk in {dt} s: {across}`)
				end
			end
			for _, row in rows do
				print(`      {row}`)
			end
		end
	)

	-- the ledge allowance (a launch off a rail comes down on a floor a step over the feet and launches again: the alley's
	-- light rails under the rafters' beams): only where the server's own ray finds that floor, within a launch and a step
	t.test("exit: a ledge beside a trunk explains a second leap only within a leap and a step of the launch", function()
		local rows = {}
		for _, rate in RATES do
			local dt = 1 / rate
			for _, over in { 1, 3, 6, 12 } do
				-- (a box beside the trunk whose top is `over` studs over the drawn pose at t = 0.3)
				local pt = base.registry:pointAt(trunk, 0.3)
				local top = pt.y + over
				local box = { minX = foot.x + 3, maxX = foot.x + 13, minZ = foot.z - 5, maxZ = foot.z + 5, top = top }
				-- the greedy's highest off the trunk, with the box (its roof a ledge) and without it
				-- (over the ledge's roof: the feet from its top up)
				local function highest(boxes: { TestWorld.Box }): number
					local world, vworld = worldWith(boxes, boxes)
					local v = MoveValidator.new(vworld)
					local prev = onRail(world, trunk, 0.3)
					prev.trunkNormalX, prev.trunkNormalZ = 1, 0
					local vis = SquirrelMotor.visualPose(prev, world)
					local launchUp = P.leapUp * E.launchTol
					local best = -math.huge
					for vy = -P.gravity * dt, launchUp, 1.5 do
						local h = most(over, 40, function(x: number): boolean
							local n = SquirrelMotor.new(foot.x + 5, vis.y + x, foot.z)
							n.grounded, n.committedAirborne, n.vy, n.clock = false, true, vy, dt
							return clean(v, prev, n, dt)
						end)
						best = math.max(best, h or -math.huge)
					end
					return best
				end
				local launchUp = P.leapUp * E.launchTol
				local withLedge, without = highest({ box }), highest({})
				-- (an honest body: a launch rising in the gap, a step onto the ledge and a launch off it, as high as a
				-- launch from the ledge could rise in the gap; or, with no ledge in reach, the launch alone)
				local tu = math.min(dt, launchUp / P.gravity)
				local riseInDt = launchUp * tu - 0.5 * P.gravity * tu * tu
				local railCap = SquirrelMotor.routeCap(trunk, false) * E.railTol
				local reachable = over <= railCap * dt + riseInDt + Units.st(1.4) + E.floorSlack
				local G = P.gravity * dt + P.gravity * E.gravityEps
				local secondRise = G * (2 * launchUp - G) / (2 * P.gravity)
				local bound = if reachable
					then math.max(without, over + secondRise + E.floorSlack + E.posSlack + 0.05)
					else without
				table.insert(
					rows,
					`{rate}/s ledge {over} st over: up {string.format("%.1f", withLedge)}, {string.format(
						"%.1f",
						without
					)} with none (reachable {reachable}, bound {string.format("%.1f", bound)})`
				)
				t.truthy(withLedge <= bound + 1e-3, `{rate}/s, a ledge {over} st over: {withLedge} st up`)
			end
		end
		for _, row in rows do
			print(`      {row}`)
		end
	end)

	t.test("exit: rail touches (off the trunk, back on, off) climb no faster than the trunk and a leap", function()
		local world, vworld = worldWith({})
		local rows = {}
		for _, rate in RATES do
			for _, k in CLOCKS do
				local v = MoveValidator.new(vworld)
				local real = 1 / rate
				local dtc = real * k
				local tt = 0.05
				local s = onRail(world, tall, tt)
				v:accept("a", { seq = 1, snapshot = SquirrelMotor.serialize(s) }, 0)
				local y0 = s.y
				local server, clock, n, bad, peak = 0, 0, 1, 0, s.y
				local launchUp = P.leapUp * E.launchTol
				while server < 3 do
					server += real
					clock += dtc
					n += 1
					local prev = v:last("a")
					local cand: State
					if prev.routeId then
						-- off: the highest it passes, at the vertical speed that rises most
						local vis = SquirrelMotor.visualPose(prev, world)
						local bestH, bestVy = 0, 0
						for vy = -P.gravity * dtc, launchUp, 1.5 do
							local h = most(0, 60, function(x: number): boolean
								local c = SquirrelMotor.new(vis.x, vis.y + x, vis.z)
								c.grounded, c.committedAirborne, c.vy, c.clock = false, true, vy, clock
								return clean(v, prev, c, dtc)
							end)
							if h and h > bestH then
								bestH, bestVy = h, vy
							end
						end
						cand = SquirrelMotor.new(vis.x, vis.y + bestH, vis.z)
						cand.grounded, cand.committedAirborne, cand.vy, cand.clock = false, true, bestVy, clock
					else
						-- on: the highest point of the trunk the grab passes
						local d = most(0, 1, function(x: number): boolean
							local c = onRail(world, tall, x)
							c.clock = clock
							return clean(v, prev, c, dtc)
						end)
						if d == nil then
							-- (no grab within reach: on falling, the plain arc)
							cand = SquirrelMotor.clone(prev)
							cand.vy = math.max(prev.vy - P.gravity * dtc, -P.terminalFall)
							cand.y = prev.y + (prev.vy + cand.vy) / 2 * dtc
							cand.clock = clock
						else
							tt = d
							cand = onRail(world, tall, tt)
							cand.clock = clock
						end
					end
					local r = v:accept("a", { seq = n, snapshot = SquirrelMotor.serialize(cand) }, server)
					bad += #r.violations
					peak = math.max(peak, cand.y)
				end
				local rateUp = (peak - y0) / server
				local cap = SquirrelMotor.routeCap(tall, false) * E.railTol
				-- (an honest climber: the trunk's pace, and a leap and a grab of it higher up as often as it can: a leap's
				-- rise in the time a grab is within reach, about 4 studs in 0.15 s; the bound counts a leap's apex per
				-- packet on top of the pace, at most)
				table.insert(
					rows,
					`{rate}/s x{k}: {string.format("%.1f", rateUp)} st/s up ({bad} viol.; the trunk's own pace {string.format(
						"%.1f",
						cap
					)})`
				)
				if k <= 1 then
					t.truthy(
						rateUp <= 1.1 * cap,
						`rail touches at {rate}/s x{k}: {rateUp} st/s, about the trunk's pace`
					)
				else
					t.truthy(bad > 0, `rail touches at {rate}/s x{k}: the clock run fast is flagged`)
				end
			end
		end
		for _, row in rows do
			print(`      {row}`)
		end
	end)

	-- roofed -----------------------------------------------------------------------------------------------------------
	-- a hollow house (four walls 1 st thick, 14 high, a roof at 14) whose west wall is 1.5 st east of the trunk's foot
	local function roofedHouse(): (any, any, number)
		local x0, z0, W = foot.x + 1.5, foot.z - 8, 16
		local walls = {
			{ minX = x0, maxX = x0 + 1, minZ = z0, maxZ = z0 + W, top = 14 },
			{ minX = x0 + W - 1, maxX = x0 + W, minZ = z0, maxZ = z0 + W, top = 14 },
			{ minX = x0, maxX = x0 + W, minZ = z0, maxZ = z0 + 1, top = 14 },
			{ minX = x0, maxX = x0 + W, minZ = z0 + W - 1, maxZ = z0 + W, top = 14 },
		}
		local roof = { { minX = x0, maxX = x0 + W, minZ = z0, maxZ = z0 + W, top = 14 } }
		local world, vworld = worldWith(walls, roof)
		return world, vworld, x0
	end

	t.test(
		"roofed: no way into a roofed house off a trunk or from a leap beside it, at 2 to 30 packets a second",
		function()
			local world, vworld, x0 = roofedHouse()
			local v = MoveValidator.new(vworld)
			local launchUp = P.leapUp * E.launchTol
			local passed = {}
			local tried = 0
			for _, rate in RATES do
				local dt = 1 / rate
				-- off the trunk, any height up it, the bark facing the house or not, into the house at any height under the roof
				for h = 1, 13, 1 do
					for _, nx in { 1, 0 } do
						local prev = onRail(world, trunk, h / trunk.length)
						prev.trunkNormalX, prev.trunkNormalZ = nx, 1 - nx
						for _, inX in { x0 + 1.4, x0 + 2.5, x0 + 4 } do
							-- (feet anywhere from the floor to a body's height under the roof: inside it)
							for y = 0, 14 - world.groundHeight - ValidatorWorld.C.TOP, 1.5 do
								for _, vy in { -P.gravity * dt, 0, launchUp } do
									tried += 1
									local n = SquirrelMotor.new(inX, world.groundHeight + y, foot.z)
									n.grounded, n.committedAirborne, n.vy, n.clock = false, true, vy, dt
									if clean(v, prev, n, dt) then
										table.insert(passed, `{rate}/s off the trunk at {h} into ({inX - x0}, {y})`)
									end
								end
							end
						end
					end
				end
				-- from a leap beside the wall (outside, any height and vertical speed) onto the floor inside
				for h = 0, 13, 1 do
					for _, vy in { -P.gravity * dt, 0, launchUp / 2, launchUp } do
						tried += 1
						local prev = SquirrelMotor.new(x0 - 1, world.groundHeight + h, foot.z)
						prev.grounded, prev.vy, prev.committedAirborne = h == 0, if h == 0 then 0 else vy, h > 0
						local n = SquirrelMotor.new(x0 + 2.5, world.groundHeight, foot.z)
						n.grounded, n.clock = true, dt
						if clean(v, prev, n, dt) then
							table.insert(passed, `{rate}/s from a leap {h} st up`)
						end
					end
				end
			end
			print(`      {tried} ways in tried, {#passed} passed {table.concat(passed, "; ")}`)
			t.eq(#passed, 0, "no way through the wall of a roofed house")
		end
	)

	t.test("roofed: an open garden wall is still leapt (the honest leap over a fence under open sky)", function()
		-- (the same walls with no roof: a leap's rise clears a wall 1.5 st high)
		local x0 = foot.x + 1.5
		local wall = { { minX = x0, maxX = x0 + 1, minZ = foot.z - 8, maxZ = foot.z + 8, top = 1.5 } }
		local world, vworld = worldWith(wall, {})
		local v = MoveValidator.new(vworld)
		local prev = SquirrelMotor.new(x0 - 1.2, world.groundHeight + 1, foot.z)
		prev.grounded, prev.vy, prev.committedAirborne = false, 10, true
		local n = SquirrelMotor.new(x0 + 2, world.groundHeight + 1.2, foot.z)
		n.grounded, n.committedAirborne, n.vy, n.clock = false, true, 10 - P.gravity * 0.1, 0.1
		local found = SquirrelMotor.envelope(prev, n, 0.1, v.world, false)
		print(`      over a 1.5-st garden wall in 0.1 s: [{codesOf(found)}]`)
		t.eq(#found, 0, "an honest leap over a garden wall")
	end)

	-- float ------------------------------------------------------------------------------------------------------------
	t.test(
		"float: after a rail or a long gap, standing over the ground or a car's roof at 2 to 30 packets a second",
		function()
			local cars = { walls = Solid.newSet(), floors = Solid.newSet() }
			local world, vworld = worldWith({}, nil, cars)
			local rows = {}
			for _, onCar in { false, true } do
				for _, rate in RATES do
					for _, h in (if onCar then { 0.7, 1.4, 3 } else { 0.7, 1.5, 3 }) :: { number } do
						local v = MoveValidator.new(vworld)
						local dt = 1 / rate
						local s = onRail(world, trunk, 0.1)
						v:accept("a", { seq = 1, snapshot = SquirrelMotor.serialize(s) }, 0)
						local vis = SquirrelMotor.visualPose(s, world)
						local roof = 0
						Solid.clear(cars.floors)
						if onCar then
							-- (a car parked under the path, its roof 4 st up)
							local car = Solid.box(6, 60, 4, vis.x - 30, world.groundHeight, vis.z, math.pi / 2)
							Solid.add(cars.floors, car)
							roof = 4
						end
						local n = SquirrelMotor.new(vis.x - 1, world.groundHeight + roof + h, vis.z)
						n.grounded = true
						local flaggedAt: number? = nil
						local clock = 0
						-- (a third a packet on a car's roof: at 2 a second the bucket's leak takes most of it)
						for i = 1, math.ceil((if onCar then 6 else 3) * rate) do
							clock += dt
							n.clock = clock
							n.x -= 10 * dt -- (walking along)
							local r = v:accept("a", { seq = i + 1, snapshot = SquirrelMotor.serialize(n) }, clock)
							if r.flagged and flaggedAt == nil then
								flaggedAt = clock
							end
						end
						table.insert(
							rows,
							`{if onCar then "car" else "ground"} {rate}/s {h} st over: flagged at {flaggedAt or "never"}`
						)
						t.truthy(
							flaggedAt ~= nil,
							`{h} st over the {if onCar then "car" else "ground"} at {rate}/s is flagged`
						)
					end
				end
			end
			for _, row in rows do
				print(`      {row}`)
			end
		end
	)

	-- clicks -----------------------------------------------------------------------------------------------------------
	t.test("clicks: a click's number is taken once, the newer only, wrapping at 255", function()
		local rig = LiveRig.new({ world = base, vworld = (select(2, worldWith({}))), link = QUIET, seed = 3 })
		rig:possess(SquirrelMotor.new(foot.x - 20, base.groundHeight, foot.z), function(): SquirrelMotor.Input
			return SquirrelMotor.idleInput(0)
		end)
		rig:run(0.5)
		local m = rig.movement :: any
		local id: any = nil
		for k in m.squirrels do
			id = k
		end
		t.truthy(m:clickNew(id, 7), "a first click")
		t.falsy(m:clickNew(id, 7), "its copy")
		t.falsy(m:clickNew(id, 6), "an older one")
		t.truthy(m:clickNew(id, 8), "the next")
		t.truthy(m:clickNew(id, nil), "a remote with no number (an older client)")
		t.falsy(m:clickNew(id, 0), "no click")
		t.falsy(m:clickNew(id, 300), "out of range")
		t.falsy(m:clickNew(id, "x"), "no number")
		for _, k in { 100, 200, 255 } do
			t.truthy(m:clickNew(id, k), `{k}, newer`)
		end
		t.truthy(m:clickNew(id, 1), "255 wraps to 1")
		t.falsy(m:clickNew(id, 255), "and 255 is older then")
	end)

	-- a lunge made untold, every packet from it held back `hold` seconds and then let go together (so the gaps the server
	-- sees stay a packet's), and a click claiming to have come a wind-up before it: `copy` sends the click only as a copy
	-- in the held packets (claiming its age), else by the remote, sent to land just ahead of them (the round-4 review's
	-- finding 6). Returns whether the launch is tied to the click, and whether the server dated the launch at all.
	local CP = CombatRules.params()
	local windup = Tunables.get("pounce.windup")
	local function heldBehindClick(
		hold: number,
		copy: boolean,
		clockRate: number,
		seed: number
	): (boolean, boolean, string)
		local _, vworld = worldWith({})
		local launch = CHEAT_AT
		local pounced: number? = nil
		local dues: { number } = {}
		local rig: any
		local function id(): any
			for k in (rig.movement :: any).squirrels do
				return k
			end
			return nil
		end
		local function take(seq: number, clock: number, at: number)
			if (rig.movement :: any):clickNew(id(), seq) then
				local d = (rig.movement :: any):clickAt(id(), clock, at)
				table.insert(dues, (d or at) + windup)
			end
		end
		rig = LiveRig.new({
			world = base,
			vworld = vworld,
			-- (everything sent from the launch for `hold` seconds arrives together at its end)
			link = { latency = QUIET.latency, jitter = QUIET.jitter, loss = 0, holdEvery = launch, holdFor = hold },
			seed = seed,
			clockRate = clockRate,
			onClick = take,
			packetCheat = function(snap: { [string]: any }, now: number): boolean?
				if copy and pounced and now >= launch and now < launch + hold + 0.3 then
					-- (the click's copy, claiming the wind-up before the lunge)
					snap.clickSeq = 9
					snap.clickAgo =
						math.clamp((snap.clock :: number) - ((pounced :: number) - windup), 0, SquirrelWire.CLICK_COPY)
				end
				return nil
			end,
		})
		local sent = false
		rig:possess(
			SquirrelMotor.new(foot.x - 30, base.groundHeight, foot.z),
			function(now: number, s: State, events: { SquirrelMotor.Event }): SquirrelMotor.Input
				for _, e in events do
					if e.kind == "pounce" and pounced == nil then
						pounced = s.clock
					end
				end
				if not copy and pounced and not sent and now >= launch + hold - 0.03 then
					-- (the remote, to land just ahead of the held packets)
					sent = true
					local k = (pounced :: number) - windup
					rig:at(now + QUIET.latency - 0.02, function()
						take(9, k, rig.t)
					end)
				end
				local inp = SquirrelMotor.idleInput(-math.pi / 2)
				inp.pounce = now >= launch and pounced == nil
				return inp
			end
		)
		rig:run(CHEAT_AT + 2)
		local sq = (rig.movement :: any).squirrels[id()]
		local tied = false
		for _, due in dues do
			if sq.pounceAt and CombatService.tied(CP, sq.pounceAt, due) then
				tied = true
			end
		end
		return tied, sq.pounceAt ~= nil, `launch dated {sq.pounceAt}, {#dues} click(s) taken`
	end

	t.test(
		"clicks: a lunge held behind its click (the remote ahead of it, or a copy in the held packets) is not tied",
		function()
			local rows = {}
			for _, copy in { false, true } do
				for _, k in { 0.5, 1, 1.3 } do
					for _, hold in { 0.05, 0.2, 0.3, 0.45 } do
						local tied, dated, what = heldBehindClick(hold, copy, k, 60 + math.floor(hold * 100))
						local how = if copy then "copy" else "remote"
						table.insert(rows, `{how} x{k} held {hold} s: tied {tied} ({what})`)
						if hold > 0.14 then
							-- (past the link's spread and a packet: QUIET's 0.01 + 0.13)
							t.falsy(tied, `{how}, clock x{k}, held {hold} s: not tied`)
						elseif k == 1 then
							-- (the control: a hold the link's tolerance takes is dated and tied, as an honest late packet is)
							t.truthy(dated and tied, `{how}, held {hold} s: dated and tied (the link's tolerance)`)
						end
					end
				end
			end
			for _, row in rows do
				print(`      {row}`)
			end
		end
	)
end
