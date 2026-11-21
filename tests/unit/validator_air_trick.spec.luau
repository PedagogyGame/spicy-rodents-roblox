--!strict
-- The validator and the air trick (owner D17, redone by D18): the re-aim turns and scales a wiggle's flight by what the
-- packet says it applied (aimYaw, aimReach), each at the motor's rate; the envelope undoes it before judging the move
-- (SquirrelMotor.envelope 0c), the server's air bound scales by its own reach (MoveValidator._stamina: the motor's
-- trickReachAt on the server's own footing), a fresh wiggle pays trickCost from the server's meter, and a roll after a
-- flight the server saw holds the speed for its length. The wiggle's burst (owner D20: the flight turned, popped and
-- shifted at the press) is the motor's own, once a flight by the server's count: the envelope takes the turn back, the
-- pop off the speed and the shift's part off the distance (0c), and the server's air bound takes the same off the move
-- (_stamina). Here:
--   honest            the client's motor, the link and MovementService (tests/lib/LiveRig) with a trick every flight:
--                     the wiggle pressed at a random moment mid-jump and the aim swung to and fro (either side, out and
--                     in), the button held on the way down for the roll as it lands; the S3 driver in town (leaps,
--                     pounces, grabs, transfers) and hopping on open ground, on a clean link and through loss bursts:
--                     0 snaps (the camera swung round on half the presses, so the burst turns the flight);
--   the burst         an honest press, 20 packets a second: clean; the same flight with the claim left out, with a
--                     burst twice the motor's, or with a second wiggle claimed later in the flight and its burst
--                     taken again: flagged;
--   crafted claims    a stream that claims a wiggle and its full re-aim out every flight (and a roll every landing) gains
--                     no pace past an honest player's: the greedy grab-leap chain along the river bridge's parapet
--                     (validator_r15rv's) at 20 and 4 packets a second, and a greedy stream over open ground, each with
--                     and without the claims, against the honest trick's own pace there.
-- SPICY_TRICK_RUNS=<n> plays n runs of each honest kind (default 2); SPICY_TRICK_OFF=1 the same with no trick. 20 s.
local process = require("@lune/process")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local MoveValidator = require("@server/Movement/MoveValidator")
local TestWorld = require("@tests/cheat/TestWorld")
local Rng = require("@tests/cheat/Rng")
local LiveRig = require("@tests/lib/LiveRig")
local Units = require("@shared/Config/Units")

type State = SquirrelMotor.State

local P = SquirrelMotor.params
local RUNS = tonumber(process.env.SPICY_TRICK_RUNS) or 2
-- (SPICY_TRICK_OFF=1: the same runs with the button never pressed, the reference a snap is compared with)
local OFF = process.env.SPICY_TRICK_OFF ~= nil
local SECONDS = 40

-- (a copy of the validator's state for one actor, its tables shared as they are: a candidate packet tried and undone)
local function deep(v: any, memo: { [any]: any }): any
	if type(v) ~= "table" then
		return v
	end
	if memo[v] then
		return memo[v]
	end
	local c = {}
	memo[v] = c
	for k, x in v do
		c[deep(k, memo)] = deep(x, memo)
	end
	return setmetatable(c, getmetatable(v))
end

-- a loss schedule: a burst lo..hi s long every every0..every1 s (movement_live_lossy's)
local function bursts(
	rng: Rng.Rng,
	seconds: number,
	lo: number,
	hi: number,
	e0: number,
	e1: number
): (number) -> boolean
	local spans: { { number } } = {}
	local at = 1 + rng.next() * e1
	while at < seconds do
		local len = lo + rng.next() * (hi - lo)
		table.insert(spans, { at, at + len })
		at += math.max(len + 0.5, e0 + rng.next() * (e1 - e0))
	end
	return function(t: number): boolean
		for _, s in spans do
			if t >= s[1] and t < s[2] then
				return true
			end
		end
		return false
	end
end

return function(t)
	local town = LiveRig.town()

	-- a trick every flight: the wiggle at a random moment mid-jump, the aim swung to and fro from then (either side, out
	-- and in), the button held on the way down (the roll as it lands); sometimes the roll pressed on the landing frame
	local function tricky(keys: LiveRig.Keys, rng: Rng.Rng): (LiveRig.Keys, { n: number })
		local count = { n = 0 }
		local airFrom, pressAfter, aimedAt = 0, 0.2, 0
		local yawTo, reachTo, sweep = 0, 0, 1
		local wasFoot = true
		return function(now: number, s: State, e: { SquirrelMotor.Event }): SquirrelMotor.Input
			local inp = keys(now, s, e)
			if OFF then
				return inp
			end
			local foot = s.grounded or s.routeId ~= nil
			if foot then
				if not wasFoot and s.grounded and rng.next() < 0.3 then
					inp.trick = true
				end
			else
				if wasFoot then
					airFrom, pressAfter = now, 0.03 + rng.next() * 0.45
					yawTo, reachTo, sweep = (rng.next() * 2 - 1) * 0.8, rng.next() * 2 - 1, 2 + rng.next() * 6
				end
				if s.trickKind == 0 and now - airFrom >= pressAfter then
					inp.trick = true
					aimedAt = now
					-- (owner D20: the burst goes the way the camera faces at the press: half the time swung round, any way)
					if rng.next() < 0.5 then
						inp.cameraYaw += (rng.next() * 2 - 1) * math.pi
					end
				elseif s.trickKind == 2 then
					local a = now - aimedAt
					inp.aimYaw = yawTo * math.sin(sweep * a)
					inp.aimReach = reachTo * math.cos(sweep * a * 0.7)
					inp.trick = s.vy < 0
				end
			end
			if inp.trick then
				count.n += 1
			end
			wasFoot = foot
			return inp
		end,
			count
	end
	-- hopping north on open ground, the keys swung left or right for each flight
	local function hopper(): LiveRig.Keys
		local flights, wasGrounded = 0, true
		return function(_now: number, s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
			local inp = SquirrelMotor.idleInput(math.pi)
			inp.fw = 1
			if s.grounded and wasGrounded == false then
				flights += 1
			end
			wasGrounded = s.grounded
			inp.leap = s.grounded
			inp.side = if s.grounded then 0 elseif flights % 2 == 0 then 1 else -1
			return inp
		end
	end

	local function play(
		name: string,
		link: LiveRig.Link?,
		start: State,
		keys: LiveRig.Keys,
		seed: number
	): LiveRig.Result
		local rig = LiveRig.new({ world = town.world, vworld = town.vworld, link = link, seed = seed })
		rig:possess(start, keys)
		rig:run(SECONDS)
		local r = rig:result()
		if r.snaps > 0 then
			print(`      {LiveRig.describe(name, r)}`)
			for i, v in r.violations do
				if i <= 6 then
					print(`        {v}`)
				end
			end
		end
		return r
	end

	for _, lossy in { false, true } do
		t.test(
			`honest with a trick every flight, {if lossy
				then "loss bursts of 0.3 to 1 s every 2 to 5 s"
				else "a clean link"}: the town driver and open-ground hops, 0 snaps`,
			function()
				local snaps, moves, packets = 0, 0, 0
				for run = 1, RUNS do
					local seed = (if lossy then 7100 else 7000) + run
					local rng = Rng.new(seed)
					local link: LiveRig.Link? = if lossy
						then {
							latency = 0.12,
							jitter = 0.1,
							loss = 0.02,
							dropAt = bursts(rng, SECONDS + 5, 0.3, 1.0, 2, 5),
						}
						else nil
					local k1, c1 = tricky(town.driven(rng), rng)
					local r1 = play(`town run {run}`, link, town.startAt(rng), k1, seed)
					local k2, c2 = tricky(hopper(), rng)
					local r2 = play(`open-ground hops run {run}`, link, town.openStart(), k2, seed + 50)
					snaps += r1.snaps + r2.snaps
					moves += c1.n + c2.n
					packets += r1.packets + r2.packets
				end
				print(`      {RUNS} runs x 2 kinds x {SECONDS} s: {moves} presses, {packets} packets, {snaps} snaps`)
				t.truthy(OFF or moves > 20 * RUNS, "tricks were done")
				t.eq(snaps, 0, "snaps")
			end
		)
	end

	-- the burst, by the server's count ------------------------------------------------------------------------------
	t.test(
		"the burst: an honest press clean; left unclaimed, doubled, or taken a second time in the flight: flagged",
		function()
			-- a sprint leap north on the open ground, the wiggle pressed 16 frames in, a packet every three frames; `edit`
			-- changes each packet before it is sent (the frames since the press, or nil before it)
			local function flight(edit: ((State, number?) -> ())?): ({ string }, number)
				local v = MoveValidator.new(town.vworld)
				local seq = 0
				local flags: { string } = {}
				local s = town.openStart()
				local z0 = s.z
				local pressed: number? = nil
				local function feed()
					local c = SquirrelMotor.clone(s)
					if edit then
						edit(c, pressed)
					end
					seq += 1
					local r = v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(c) }, s.clock + 1)
					for _, x in r.violations do
						table.insert(flags, `{x.code}: {x.detail}`)
					end
				end
				feed()
				local frame, air = 0, 0
				local leapt = false
				while frame < 200 and not (leapt and s.grounded and s.footAgo > 0.3) do
					frame += 1
					local i = SquirrelMotor.idleInput(math.pi)
					i.fw, i.sprint = 1, true
					i.leap = frame == 60
					leapt = leapt or frame == 60
					if not s.grounded then
						air += 1
						i.trick = air == 16
					end
					SquirrelMotor.step(s, i, 1 / 60, town.world)
					if pressed then
						pressed += 1
					elseif s.trickKind == 2 then
						pressed = 0
					end
					if frame % 3 == 0 then
						feed()
					end
				end
				return flags, s.z - z0
			end
			local honest, far = flight(nil)
			t.eq(#honest, 0, `an honest press: {honest[1]}`)
			-- the claim left out: the burst's move with nothing to explain it
			local bare = flight(function(c: State, pressed: number?)
				if pressed then
					c.trickKind, c.trickTime, c.trickTurn, c.aimYaw, c.aimReach = 0, 0, 0, 0, 0
				end
			end)
			t.truthy(#bare > 0, "the burst with no wiggle claimed is no honest move")
			-- twice the motor's shift, claimed as one burst
			local double = flight(function(c: State, pressed: number?)
				if pressed then
					c.z += P.trickShift * SquirrelMotor.shiftDone(pressed / 60)
				end
			end)
			t.truthy(#double > 0, "a burst twice the motor's is flagged")
			-- a second wiggle claimed 0.3 s after the first, its shift taken again
			local again = flight(function(c: State, pressed: number?)
				if pressed and pressed >= 18 and c.trickKind == 2 then
					local since = (pressed - 18) / 60
					c.trickTime = math.max(0, P.trickWiggle - since)
					c.z += P.trickShift * SquirrelMotor.shiftDone(since)
				end
			end)
			t.truthy(#again > 0, "a second burst in the same flight is flagged (once a flight, the server's count)")
			print(
				string.format(
					"      a sprint leap with the press, 20 packets a second: %d flags honest (%.1f st); unclaimed %d, doubled %d, a second burst %d",
					#honest,
					far,
					#bare,
					#double,
					#again
				)
			)
		end
	)

	-- crafted streams ---------------------------------------------------------------------------------------------
	local function flat(): (any, any)
		local tw = TestWorld.build({ boxes = {} })
		local function wall(): boolean
			return false
		end
		local function down(_ox: number, oy: number, _oz: number, _dx: number, dy: number, _dz: number): boolean
			return oy >= 0 and math.min(oy, oy + dy) <= 0
		end
		return tw, ValidatorWorld.build(tw, { wall = wall, down = down })
	end
	local function rig(vworld: any): ((State) -> any, (State) -> (boolean, number), any)
		local v = MoveValidator.new(vworld)
		local seq = 0
		local function feed(s: State): any
			seq += 1
			return v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(s) }, s.clock + 1)
		end
		local function try(s: State): (boolean, number)
			local a, m = v._actors.a, v._marks.a
			local memo = {}
			v._actors.a, v._marks.a = deep(a, memo), deep(m, memo)
			local seq0 = seq
			local r = feed(s)
			local meter = v._marks.a.stamina
			v._actors.a, v._marks.a = a, m
			seq = seq0
			return #r.violations == 0, meter
		end
		return feed, try, v
	end
	-- (claims the trick on a candidate packet `c` after the baseline `b`: in the air a wiggle, fresh at the flight's start,
	-- its re-aim out as fast as the motor's rate goes; on the ground a roll at each landing; none on a rail)
	local function claim(c: State, on: boolean, b: State?, dt: number)
		c.trickKind, c.trickTime, c.aimYaw, c.aimReach = 0, 0, 0, 0
		if not on or c.routeId ~= nil then
			return
		end
		local prevKind = if b then b.trickKind else 0
		if not c.grounded then
			c.trickKind = 2
			c.trickTime = if prevKind == 2 and b then math.max(0, b.trickTime - dt) else P.trickWiggle
			local from = if prevKind == 2 and b then b.aimReach else 0
			c.aimReach = math.min(1, from + P.trickReachRate * dt)
		elseif b and (not b.grounded or (prevKind == 1 and b.trickTime > dt)) then
			c.trickKind = 1
			c.trickTime = if prevKind == 1 then b.trickTime - dt else P.trickRoll
		end
	end
	-- the greedy grab-leap chain along a long rail (validator_r15rv's): every `dt` a packet on the rail's line in the
	-- air, launching at the next of four speeds up, as far along as the validator takes cleanly with the meter undrained
	local function chain(tw: any, vworld: any, dt: number, h: number, claimed: boolean): number
		local id, t0 = 1075, 0.02
		local reg = tw.registry
		local r = reg:get(id)
		local a, b = reg:pointAt(r, t0), reg:pointAt(r, 1)
		local l = math.sqrt((b.x - a.x) ^ 2 + (b.z - a.z) ^ 2)
		local ux, uz = (b.x - a.x) / l, (b.z - a.z) / l
		local yaw = math.atan2(-ux, -uz)
		local function gone(s: State): number
			return (s.x - a.x) * ux + (s.z - a.z) * uz
		end
		local feed, try, v = rig(vworld)
		local s = SquirrelMotor.new(a.x, a.y, a.z)
		s.routeId, s.railT, s.grounded, s.clock, s.yaw = id, t0, false, 0, yaw
		feed(s)
		for _ = 1, 10 do
			for _ = 1, 3 do
				SquirrelMotor.step(s, SquirrelMotor.idleInput(yaw), 1 / 60, tw)
			end
			feed(s)
		end
		local i = SquirrelMotor.idleInput(yaw)
		i.fw, i.sprint, i.leap = 1, true, true
		SquirrelMotor.step(s, i, 1 / 60, tw)
		for _ = 1, 2 do
			local j = SquirrelMotor.idleInput(yaw)
			j.fw, j.sprint = 1, true
			SquirrelMotor.step(s, j, 1 / 60, tw)
		end
		feed(s)
		local vys = { 5, 15, 25, 33 }
		local k, start = 0, s.clock
		local g0: number? = nil
		local c0 = 0
		while s.clock - start < 8 do
			k += 1
			if g0 == nil and s.clock - start >= 1 then
				g0, c0 = gone(s), s.clock
			end
			local m0 = v._marks.a.stamina
			local best: State? = nil
			local D = math.max(8, 60 * dt)
			while D >= -2 and best == nil do
				local p = reg:pointAt(
					r,
					math.clamp(t0 + (gone(s) - gone(SquirrelMotor.new(a.x, a.y, a.z)) + D) / r.length, 0, 1)
				)
				local c = SquirrelMotor.new(p.x, p.y + h, p.z)
				c.vx, c.vz, c.yaw = ux * 42, uz * 42, yaw
				c.grounded, c.vy, c.clock = false, vys[(k - 1) % #vys + 1], s.clock + dt
				claim(c, claimed, s, dt)
				local ok, m = try(c)
				if ok and m >= math.min(m0, 1) - 1e-4 then
					best = c
				end
				D -= 0.25
			end
			if best == nil then
				local n = SquirrelMotor.clone(s)
				n.vy = s.vy - P.gravity * dt
				n.y = s.y + (s.vy + n.vy) / 2 * dt
				n.clock = s.clock + dt
				claim(n, claimed, s, dt)
				best = n
			end
			feed(best :: State)
			s = SquirrelMotor.clone(v._actors.a.last)
		end
		return (gone(s) - (g0 or 0)) / (s.clock - c0)
	end

	t.test(
		"the burst: two short hops, each with a wiggle: the second's burst only when trickBurstRest after the first",
		function()
			local _, vworld = flat()
			-- two hops north over flat ground, 20 packets a second, a wiggle claimed a packet into each; the first takes the
			-- motor's shift; the second takes it too when `second`, after `wait` s on the ground between the hops
			local function hops(second: boolean, wait: number): ({ string }, number)
				local v = MoveValidator.new(vworld)
				local seq = 0
				local flags: { string } = {}
				local s = SquirrelMotor.new(-1400, 0, -1360)
				s.clock = 0
				local function feed()
					seq += 1
					local r = v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(s) }, s.clock + 1)
					for _, x in r.violations do
						table.insert(flags, `{x.code}: {x.detail}`)
					end
				end
				local dt, pace = 0.05, 15
				feed()
				local firstPress, secondPress = 0, 0
				local function stand(secs: number)
					for _ = 1, math.floor(secs / dt + 0.5) do
						s.clock += dt
						feed()
					end
				end
				local function hop(shifted: boolean): number
					local press = 0
					local k = 0
					s.vx, s.vz = 0, pace
					repeat
						k += 1
						local vy = if k == 1 then 10 else s.vy - P.gravity * dt
						local y = if k == 1 then 0.5 else math.max(0, s.y + (s.vy + vy) / 2 * dt)
						s.clock += dt
						s.z += pace * dt
						s.grounded, s.y, s.vy = y <= 0, y, if y <= 0 then 0 else vy
						if s.grounded then
							s.trickKind, s.trickTime, s.vz = 0, 0, 0
						elseif k >= 2 then
							-- (pressed at the start of the second packet's gap)
							local since = (k - 1) * dt
							if k == 2 then
								press = s.clock - dt
							end
							s.trickKind, s.trickTime = 2, math.max(0, P.trickWiggle - since)
							if shifted then
								s.z += P.trickShift * (SquirrelMotor.shiftDone(since) - SquirrelMotor.shiftDone(
									since - dt
								))
							end
						end
						feed()
					until s.grounded
					return press
				end
				stand(0.2)
				firstPress = hop(true)
				stand(wait)
				secondPress = hop(second)
				stand(0.2)
				return flags, secondPress - firstPress
			end
			local plain, gap = hops(false, 0)
			t.truthy(gap < P.trickBurstRest, `the hops' presses {gap} s apart: inside the rest`)
			t.eq(#plain, 0, `the first hop's burst and a second wiggle with none: clean ({plain[1]})`)
			local both = hops(true, 0)
			t.truthy(#both > 0, "a second burst inside trickBurstRest is flagged")
			local rested, gap2 = hops(true, 0.2)
			t.truthy(gap2 >= P.trickBurstRest, `after {gap2} s`)
			t.eq(#rested, 0, `a second burst after the rest: clean ({rested[1]})`)
			print(
				string.format(
					"      two hops, a burst claimed in each: presses %.2f s apart %d flags; %.2f s apart %d flags (the rest: %.1f s)",
					gap,
					#both,
					gap2,
					#rested,
					P.trickBurstRest
				)
			)
		end
	)

	t.test(
		"crafted claims: a move claimed in every packet buys the greedy grab-leap chain along a rail no pace",
		function()
			local tw, vworld = flat()
			for _, case in { { dt = 0.05, h = 0, name = "20 Hz" }, { dt = 0.25, h = -1, name = "4 Hz" } } do
				local plain = chain(tw, vworld, case.dt, case.h, false)
				local claimed = chain(tw, vworld, case.dt, case.h, true)
				print(
					string.format(
						"      %s packets along the parapet: greedy %.1f st/s, claiming a move every packet %.1f st/s",
						case.name,
						plain,
						claimed
					)
				)
				-- (the claim may add only the swing. Validator round 17: a first grab's snap is the band's reach across from the
				-- body, and the claimed swing widens that reach too. Owner D19: with the chained leaps' slower arc the swing's
				-- share is larger, up to the re-aim's own reach out, 9 % of a flight's carry)
				t.truthy(claimed <= plain * 1.09 + 0.1, `{case.name}: claimed {claimed} st/s against {plain}`)
			end
		end
	)

	t.test("crafted claims: over open ground a move claimed in every packet buys a greedy stream nothing", function()
		local _, vworld = flat()
		local function greedy(claimed: boolean): number
			local feed, try = rig(vworld)
			local x0 = -1400
			local s = SquirrelMotor.new(x0, 0, -1360)
			s.clock = 0
			feed(s)
			local dt = 0.05
			while s.clock < 12 do
				local best: State? = nil
				-- (a claimed burst's packet may reach further: the flight's own and the shift's part)
				local D = if claimed then 8 else 4
				while D >= 0 and best == nil do
					for _, vy in { 0, 10, 20, 32 } do
						local c = SquirrelMotor.clone(s)
						c.z = s.z + D
						c.clock = s.clock + dt
						c.vz = D / dt
						c.vx = 0
						if vy == 0 and s.y <= 0.01 then
							c.grounded, c.vy, c.y = true, 0, 0
						else
							c.grounded = false
							c.vy = vy
							c.y = math.max(0.5, s.y + vy * dt)
						end
						claim(c, claimed, s, dt)
						if try(c) then
							best = c
							break
						end
					end
					D -= 0.1
				end
				if best == nil then
					local n = SquirrelMotor.clone(s)
					n.clock = s.clock + dt
					n.vx, n.vz = 0, 0
					if not n.grounded then
						n.vy = s.vy - P.gravity * dt
						n.y = math.max(0, s.y + (s.vy + n.vy) / 2 * dt)
						n.grounded = n.y <= 0
						if n.grounded then
							n.vy = 0
						end
					end
					claim(n, claimed, s, dt)
					best = n
				end
				feed(best :: State)
				s = best :: State
			end
			return (s.z + 1360) / s.clock
		end
		local plain, claimed = greedy(false), greedy(true)
		print(
			string.format(
				"      open ground: greedy %.1f st/s, claiming a move every packet %.1f st/s (honest: walk 18, hop on landing 24.1 while the meter lasts, 20.5 winded)",
				plain,
				claimed
			)
		)
		-- (owner D20: a claimed wiggle now carries the motor's burst, once a flight, and pays the motor's cost: no more
		-- than the honest trick's own hopping, below)
		t.truthy(claimed <= math.max(plain + 0.1, 24.4), `claimed {claimed} st/s against {plain}`)
	end)

	-- the honest trick's own pace, for the crafted streams above (the motor alone, 60 fps, flat open ground and the parapet)
	t.test(
		"the honest trick's pace: hopping with the wiggle out at its best, a roll's carry, the parapet chain",
		function()
			local tw = TestWorld.build({ boxes = {} })
			-- hopping north (W + Shift), Space on landing (or after the roll, `roll`), the wiggle `at` frames into each
			-- flight with the aim full out (nil: no trick); the pace over `secs` from a full or an empty meter
			local function hops(at: number?, roll: boolean, secs: number, empty: boolean): number
				local s = SquirrelMotor.new(Units.st(-560), tw.groundHeight, Units.st(-545))
				if empty then
					s.stamina, s.winded = 0, true
				end
				local z0 = s.z
				local f, inAir = 0, 0
				for _ = 1, math.floor(secs * 60) do
					local i = SquirrelMotor.idleInput(math.pi)
					i.fw, i.sprint = 1, true
					if s.grounded then
						inAir = 0
						i.leap = not roll or s.trickKind ~= 1
						i.trick = roll and s.footAgo <= 0.02
					else
						inAir += 1
						i.trick = at ~= nil and (inAir == at or (roll and s.trickKind == 2 and s.vy < 0))
						i.aimReach = 1
					end
					SquirrelMotor.step(s, i, 1 / 60, tw)
					f += 1
				end
				return (s.z - z0) / secs
			end
			local rows = {
				{ "no trick", nil, false },
				{ "wiggle out at frame 15", 15, false },
				{ "wiggle out + roll, then leap", 15, true },
			}
			for _, r in rows do
				print(
					string.format(
						"      open ground, %-30s full meter 6 s %.1f st/s, from empty 30 s %.1f st/s",
						r[1],
						hops(r[2], r[3], 6, false),
						hops(r[2], r[3], 30, true)
					)
				)
			end
			-- (owner D20: the burst and farther out together add about a fifth to a jump at most, so to a hop's pace)
			t.truthy(
				hops(15, false, 6, false) <= hops(nil, false, 6, false) * (1 + P.trickTotal + 0.03),
				"the trick's hop no more than about a fifth on"
			)
			t.truthy(
				hops(15, false, 30, true) <= hops(nil, false, 30, true) * (1 + P.trickTotal + 0.03),
				"nor from an empty meter"
			)
		end
	)
end
