--!strict
-- The validator and the air trick (owner D17): the trick swings a flight's heading at the speed it has, so the server
-- needs nothing new for its speed bounds; its only model is the grab search's swing (SquirrelMotor.envelope section 5:
-- the arc widened by v0 x trickTurn x tau^2 / 2 while a move may play). Here:
--   honest            the client's motor, the link and MovementService (tests/lib/LiveRig) with a move every flight (the
--                     button pressed whenever a move is left, roll then wiggle): the S3 driver in town (leaps, pounces,
--                     grabs, transfers) and hopping on open ground steering left and right, on a clean link and through
--                     loss bursts: 0 snaps;
--   crafted claims    a stream that claims a move in every packet gains no pace: the greedy grab-leap chain along the
--                     river bridge's parapet (validator_r15rv's) at 20 and 4 packets a second, and a greedy stream over
--                     open ground, each with and without the claim, against the motor's own.
-- SPICY_TRICK_RUNS=<n> plays n runs of each honest kind (default 2); SPICY_TRICK_OFF=1 the same with no move. 15 s.
local process = require("@lune/process")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local MoveValidator = require("@server/Movement/MoveValidator")
local AirTrickButton = require("@client/UI/AirTrickButton")
local TestWorld = require("@tests/cheat/TestWorld")
local Rng = require("@tests/cheat/Rng")
local LiveRig = require("@tests/lib/LiveRig")

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

	-- the button pressed whenever a move is left (a roll, then the wiggle as soon as the roll ends)
	local function tricky(keys: LiveRig.Keys): (LiveRig.Keys, { n: number })
		local count = { n = 0 }
		return function(now: number, s: State, e: { SquirrelMotor.Event }): SquirrelMotor.Input
			local inp = keys(now, s, e)
			if not OFF and AirTrickButton.shows(s :: any) then
				inp.trick = true
				count.n += 1
			end
			return inp
		end,
			count
	end
	-- hopping north on open ground, the keys swung left or right for each flight (the trick steers the landing)
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
			`honest with a move every flight, {if lossy
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
					local k1, c1 = tricky(town.driven(rng))
					local r1 = play(`town run {run}`, link, town.startAt(rng), k1, seed)
					local k2, c2 = tricky(hopper())
					local r2 = play(`open-ground hops run {run}`, link, town.openStart(), k2, seed + 50)
					snaps += r1.snaps + r2.snaps
					moves += c1.n + c2.n
					packets += r1.packets + r2.packets
				end
				print(
					`      {RUNS} runs x 2 kinds x {SECONDS} s: {moves} moves pressed, {packets} packets, {snaps} snaps`
				)
				t.truthy(OFF or moves > 20 * RUNS, "moves were done")
				t.eq(snaps, 0, "snaps")
			end
		)
	end

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
	-- (claims a move playing in a packet in the air: a roll with all of its time left, or none)
	local function claim(c: State, on: boolean)
		if on and not c.grounded and c.routeId == nil then
			c.trickKind, c.trickTime = 1, P.trickRoll
		else
			c.trickKind, c.trickTime = 0, 0
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
				claim(c, claimed)
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
				claim(n, claimed)
				best = n
			end
			feed(best :: State)
			s = SquirrelMotor.clone(v._actors.a.last)
		end
		return (gone(s) - (g0 or 0)) / (s.clock - c0)
	end

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
				-- (validator_r15rv's bar is the motor's own fastest chain there: 47.3 st/s; the claim may add only the swing.
				-- Validator round 17: a first grab's snap is the band's reach across from the body, sound for a sample over or
				-- under it, and the claimed swing widens that reach too: 3 %, still under the motor's own chain's bar)
				t.truthy(claimed <= plain * 1.03 + 0.1, `{case.name}: claimed {claimed} st/s against {plain}`)
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
				local D = 4
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
						claim(c, claimed)
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
					claim(n, claimed)
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
		t.truthy(claimed <= plain + 0.1, `claimed {claimed} st/s against {plain}`)
	end)
end
