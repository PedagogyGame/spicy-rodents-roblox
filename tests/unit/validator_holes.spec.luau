--!strict
-- The live validator's holes the combat re-review found (review_combat2, on w0-foundation f23d8ff), each a case that
-- failed then, and the variants found while fixing them. On the rig (tests/lib/LiveRig: the client's motor, a real
-- link, the server's MovementService with enforcement on) unless the case says the envelope alone:
--   hover   a client claiming a free fall but keeping its height (the arc's bound had a floor at 0); claiming a fall a
--           little slower than gravity each packet (the slack added up), or sending 60 packets a second (the slack
--           was more than a packet's gravity)
--   ladder  every packet a mid-air "launch" a hair above the last (only the motor's pounce launches in the air, and
--           once a cooldown; every launch ends at a speed gravity could bring a launch down to in the gap; a launch's
--           packet rises what that launch can reach, not a leap's speed over the gap)
--   pounce  a hop with a claimed window is not the motor's pounce (only a pounce-shaped launch is); a lunge held back
--           behind a silence, or behind a forward-dated click, is not tied to the click; every honest mid-air pounce is
--           seen; honest pounces on a jittery, lossy link and on a slow phone are tied to their click (the click carries
--           its motor clock, and both are dated on the packets' own clock)
--   ground  a packet on the ground has no vertical speed (one claiming 300 st/s up reached a roof, and the wall
--           test's rise trusted it)
--   duel    the Duel remote's calls and refusals are rate-limited; bites and blows are judged where the validated
--           motor state has the rodent, not at the root its client moves
local Tunables = require("@shared/Config/Tunables")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local Squirrel = require("@client/Controllers/Squirrel")
local CombatRules = require("@shared/Combat/CombatRules")
local CombatService = require("@server/Combat/CombatService")
local MoveValidator = require("@server/Movement/MoveValidator")
local Rng = require("@tests/cheat/Rng")
local TestWorld = require("@tests/cheat/TestWorld")
local LiveRig = require("@tests/lib/LiveRig")
local BiteRig = require("@tests/lib/BiteRig")
local Driver = require("@tests/cheat/Driver")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")

type State = SquirrelMotor.State

local QUIET = { latency = 0.1, jitter = 0.01, loss = 0 }
local CHEAT_AT = 5
local P = SquirrelMotor.params
local E = SquirrelMotor.envelopeParams

local function idle(): LiveRig.Keys
	return function(_now: number, _s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
		return SquirrelMotor.idleInput(-math.pi / 2)
	end
end

-- an honest leap at CHEAT_AT, then (from its apex) `mode(t)` decides each frame: "hover" holds the height while the
-- vertical speed keeps falling at gravity; "ladder" climbs 30 st/s while the vertical speed rises 10 st/s a second
-- (every packet a launch over the one before, with every other packet withheld: gaps of 0.1 s)
local function flyCheat(mode: (t: number) -> string): (LiveRig.Keys, any, any, { peak: number, from: number? })
	local g = P.gravity
	local info = { peak = 0, from = nil :: number? }
	local hv: number? = nil
	local hy = 0
	local lastT: number? = nil
	local odd = false
	local laddering = false
	local ground = 0
	local keys = function(now: number, s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
		local inp = SquirrelMotor.idleInput(-math.pi / 2)
		if now < CHEAT_AT then
			ground = s.y
		end
		inp.leap = now >= CHEAT_AT and now < CHEAT_AT + 0.05 and s.grounded
		return inp
	end
	local cheat = function(s: State, _inp: SquirrelMotor.Input, now: number, _w: any)
		local dt = if lastT then now - (lastT :: number) else 1 / 60
		lastT = now
		if now < CHEAT_AT + 0.1 then
			return
		end
		if hv == nil then
			if s.grounded or s.vy > 0 then
				return
			end
			hv, hy = s.vy, s.y -- the apex: the cheat starts
			info.from = now
		end
		local m = mode(now - (info.from :: number))
		if m == "ladder" then
			if not laddering then
				laddering = true
				hv = (hv :: number) + 4 -- (the first rung: a launch over the last packet's fall)
			end
			hv = (hv :: number) + 10 * dt
			hy += 30 * dt
		else
			hv = (hv :: number) - g * dt
		end
		s.y, s.vy, s.grounded, s.committedAirborne = hy, hv :: number, false, true
		s.vx, s.vz = 0, 0
		info.peak = math.max(info.peak, hy - ground)
	end
	local packetCheat = function(_snap: { [string]: any }, now: number): boolean?
		if info.from ~= nil and mode(now - (info.from :: number)) == "ladder" then
			odd = not odd
			if odd then
				return false
			end
		end
		return nil
	end
	return keys, cheat, packetCheat, info
end

-- the validator alone on open ground: an honest leap packet by packet at `dt` to its apex, then `after(s, dt)` edits each
-- packet for `secs`; returns the violations' codes after the apex and the height over the ground at the end
local function envelopeRun(dt: number, secs: number, after: (s: State, dt: number) -> ()): ({ [string]: number }, number)
	local world = TestWorld.build({ loaders = {} })
	local v = MoveValidator.new(world)
	local s = SquirrelMotor.new(-1400, world.groundHeight, -1000)
	local clock, seq = 0, 1
	v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(s) }, clock)
	local codes: { [string]: number } = {}
	local judging = false
	local function send()
		seq += 1
		s.clock = clock
		local out = v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(s) }, clock)
		if judging then
			for _, x in out.violations do
				codes[x.code] = (codes[x.code] or 0) + 1
			end
		end
	end
	s.grounded, s.committedAirborne = false, true
	s.vy = P.leapUp
	while s.vy > 0 do
		clock += dt
		local nv = s.vy - P.gravity * dt
		s.y += (s.vy + nv) / 2 * dt
		s.vy = nv
		send()
	end
	judging = true
	local t0 = clock
	while clock - t0 < secs do
		clock += dt
		after(s, dt)
		send()
	end
	return codes, s.y - world.groundHeight
end

local function count(codes: { [string]: number }): number
	local n = 0
	for _, k in codes do
		n += k
	end
	return n
end

-- the held squirrel's id on a rig's MovementService
local function heldId(rig: any): any
	for id in (rig.movement :: any).squirrels do
		return id
	end
	return nil
end

return function(t)
	local town = LiveRig.town()
	local CP = CombatRules.params()
	local windup = Tunables.get("pounce.windup")

	t.test("hover: a client hovering at a leap's apex while claiming a free fall is snapped within 1 s", function()
		local keys, cheat, _pc, info = flyCheat(function(_: number): string
			return "hover"
		end)
		local rig = LiveRig.new({ world = town.world, vworld = town.vworld, link = QUIET, seed = 21, cheat = cheat })
		rig:possess(town.openStart(), keys)
		rig:run(CHEAT_AT + 8)
		local r = rig:result()
		print(
			`      {LiveRig.describe("hover", r)}; hovering from {info.from} at {string.format("%.1f", info.peak)} st, client vy {string.format(
				"%.0f",
				(r.client :: State).vy
			)}`
		)
		t.truthy(info.from ~= nil, "the cheat ran")
		local from = info.from or math.huge
		t.truthy(r.snaps >= 1 and (r.firstSnap or math.huge) <= from + 1, `snapped within 1 s (first {r.firstSnap})`)
	end)

	t.test("hover: a fall slower than gravity within each packet's slack, at 20 and 60 packets a second", function()
		for _, dt in { 0.05, 1 / 60 } do
			-- (each packet claims the most the slack lets it: the vertical speed gravity's less the slack, the height
			-- risen at the mean of the two)
			local slack = P.gravity * E.gravityEps * 0.95
			local codes, high = envelopeRun(dt, 1, function(s: State, step: number)
				local nv = s.vy - P.gravity * step + slack
				s.y += (s.vy + nv) / 2 * step
				s.vy = nv
			end)
			-- and simply keeping the height and the vertical speed (at 60 a second the slack was more than gravity's)
			local held = envelopeRun(dt, 1, function(_s: State, _step: number) end)
			print(
				`      {string.format("%.0f", 1 / dt)} packets/s: a slow fall {count(codes)} violations ({string.format(
					"%.1f",
					high
				)} st up after 1 s), a held height {count(held)}`
			)
			t.truthy(count(codes) >= 1, `a slow fall at {string.format("%.0f", 1 / dt)} packets/s is flagged`)
			t.truthy(count(held) >= 1, `a held height at {string.format("%.0f", 1 / dt)} packets/s is flagged`)
		end
	end)

	t.test("hover: a fall past the motor's terminal speed is no fall", function()
		local codes = envelopeRun(0.05, 5, function(s: State, step: number)
			local nv = s.vy - P.gravity * step -- (gravity with no terminal speed)
			s.y += (s.vy + nv) / 2 * step
			s.vy = nv
		end)
		t.truthy((codes.gravity or 0) >= 1, "flagged once past the terminal speed")
		-- and the motor itself never falls faster
		local s = SquirrelMotor.new(0, 500, 0)
		s.grounded = false
		local world = TestWorld.build({ loaders = {} })
		for _ = 1, 300 do
			SquirrelMotor.step(s, SquirrelMotor.idleInput(0), 1 / 60, world :: any)
		end
		t.truthy(s.vy >= -P.terminalFall - 1e-9, `the motor's fall {s.vy}`)
	end)

	t.test("ladder: a client climbing on mid-air launches at 10 packets a second is snapped within 1 s", function()
		local keys, cheat, packetCheat, info = flyCheat(function(since: number): string
			return if since < 1 then "hover" else "ladder"
		end)
		local rig = LiveRig.new({
			world = town.world,
			vworld = town.vworld,
			link = QUIET,
			seed = 22,
			cheat = cheat,
			packetCheat = packetCheat,
		})
		rig:possess(town.openStart(), keys)
		rig:run(CHEAT_AT + 8)
		local r = rig:result()
		print(`      {LiveRig.describe("ladder", r)}; peak {string.format("%.1f", info.peak)} st over the ground`)
		t.truthy(info.from ~= nil, "the cheat ran")
		local from = (info.from or math.huge) + 1
		t.truthy(r.snaps >= 1 and (r.firstSnap or math.huge) <= from + 1, `snapped within 1 s (first {r.firstSnap})`)
	end)

	t.test("ladder: the envelope alone, from any fall, at 4 to 20 packets a second, flags the first rungs", function()
		for _, dt in { 0.05, 0.1, 0.25 } do
			local vy = -5000
			local codes, high = envelopeRun(dt, 2, function(s: State, step: number)
				vy = if vy < -100 then s.vy + 1 else vy + 1
				s.vy = vy
				s.y += P.leapUp * E.launchTol * step + E.posSlack * 0.9
			end)
			print(`      every {dt} s: {count(codes)} violations, {string.format("%.1f", high)} st up`)
			t.truthy((codes.launch or 0) >= math.floor(2 / dt) - 1, `every rung flagged at {dt} s`)
		end
	end)

	t.test("pounce: a 1.5 st/s hop claiming the pounce's window is not taken as the motor's pounce", function()
		local done = false
		local rig = LiveRig.new({
			world = town.world,
			vworld = town.vworld,
			link = QUIET,
			seed = 23,
			packetCheat = function(snap: { [string]: any }, now: number): boolean?
				if now >= CHEAT_AT and not done then
					done = true
					snap.grounded = false
					snap.vy = 1.5
					snap.y = (snap.y :: number) + 0.05
					snap.attackWindow = P.pounceWindow
				end
				return nil
			end,
		})
		rig:possess(town.openStart(), idle())
		rig:run(CHEAT_AT + 2)
		local r = rig:result()
		local sq = (rig.movement :: any).squirrels[heldId(rig)]
		print(`      {LiveRig.describe("micro-hop", r)}; pounceAt {sq.pounceAt}`)
		t.eq(r.snaps, 0, "(the hop itself is a move the envelope accepts)")
		t.eq(sq.pounceAt, nil, "a hop is not a pounce")
	end)

	-- a lunge held back after the click: `silent` withholds every packet from the click to the lunge (and the first
	-- packet after it claims a window dating the launch at the click's due); `forward` sends the click's clock as late as
	-- the lunge needs; otherwise the packets flow and the click is honest
	local function heldLunge(seed: number, late: number, silent: boolean, forward: boolean): (number?, number?, number)
		local click = CHEAT_AT
		local launch = CHEAT_AT + windup + late
		local pounced: number? = nil
		local clickAt: number? = nil
		local rig: any
		rig = LiveRig.new({
			world = town.world,
			vworld = town.vworld,
			link = QUIET,
			seed = seed,
			packetCheat = function(snap: { [string]: any }, now: number): boolean?
				if silent and now > click and pounced == nil then
					return false -- nothing sent while the lunge is held back
				end
				if silent and pounced ~= nil and now >= launch and (snap.attackWindow :: number) > 0 then
					local claimed = P.pounceWindow - (now - (click + windup))
					snap.attackWindow = math.min(snap.attackWindow :: number, claimed)
				end
				return nil
			end,
		})
		rig:possess(
			town.openStart(),
			function(now: number, s: State, events: { SquirrelMotor.Event }): SquirrelMotor.Input
				for _, e in events do
					if e.kind == "pounce" and pounced == nil then
						pounced = now
					end
				end
				if clickAt == nil and now >= click and rig.t then
					-- the click's remote: its motor clock (or one as late as the lunge, forward-dated), a trip later
					local k = if forward then s.clock + late else s.clock
					clickAt = -1
					rig:at(now + QUIET.latency, function()
						clickAt = (rig.movement :: any):clickAt(heldId(rig), k, rig.t)
					end)
				end
				local inp = SquirrelMotor.idleInput(-math.pi / 2)
				inp.pounce = now >= launch and pounced == nil
				return inp
			end
		)
		rig:run(CHEAT_AT + 2)
		local r = rig:result()
		local sq = (rig.movement :: any).squirrels[heldId(rig)]
		print(
			`      {LiveRig.describe("held lunge", r)}; the motor pounced at {pounced}, the server dates it {sq.pounceAt}, the click at {clickAt}`
		)
		return sq.pounceAt, clickAt, r.snaps
	end

	t.test("pounce: a lunge held 0.28 s behind a packet gap, or a forward-dated click, is not tied to the click", function()
		for _, c in
			{
				{ name = "behind a silence", silent = true, forward = false },
				{ name = "packets flowing", silent = false, forward = false },
				{ name = "the click's clock forward-dated", silent = false, forward = true },
			}
		do
			local pounceAt, clickAt, snaps = heldLunge(24, 0.28, c.silent, c.forward)
			t.truthy(clickAt ~= nil and (clickAt :: number) > 0, `{c.name}: the click was dated`)
			t.eq(snaps, 0, `{c.name}: (nothing else wrong with it)`)
			local tied = pounceAt ~= nil and CombatService.tied(CP, pounceAt :: number, (clickAt :: number) + windup)
			t.falsy(tied, `{c.name}: a lunge 0.28 s late is not tied (launch {pounceAt})`)
		end
		-- and on time it is
		local pounceAt, clickAt = heldLunge(25, 0, false, false)
		t.truthy(pounceAt ~= nil and CombatService.tied(CP, pounceAt :: number, (clickAt :: number) + windup), "on time")
	end)

	-- an honest rodent pouncing as fast as the duel lets it, weaving across the open ground, its click's remote on its own
	-- trip (a reliable remote: its own jitter, and a lost one resent about a round trip later): how many of the motor's
	-- pounces does the server date and tie to their click (CombatService.tied on the click's clickAt)?
	local function honestTies(link: any, seed: number, fps: number?): (number, number, number)
		local rng = Rng.new(seed)
		local rig: any
		rig = LiveRig.new({ world = town.world, vworld = town.vworld, link = link, seed = seed, fps = fps })
		local pending: number? = nil
		local dues: { number } = {}
		local seen: { number } = {}
		local lastSeen: number? = nil
		local pounces = 0
		local heading = 0
		local weave, weaveAt = 1, 0
		local secs = 90
		local made: { number } = {}
		rig:possess(town.startAt(rng), function(tt: number, state: State, events: { any }): SquirrelMotor.Input
			for _, e in events do
				if e.kind == "pounce" and tt < secs - 1 then -- (the last second's are still on their way)
					pounces += 1
					table.insert(made, tt)
				end
			end
			local sq = (rig.movement :: any).squirrels[heldId(rig)]
			if sq and sq.pounceAt ~= nil and sq.pounceAt ~= lastSeen then
				lastSeen = sq.pounceAt
				table.insert(seen, sq.pounceAt)
			end
			local input = SquirrelMotor.idleInput(heading + math.pi)
			if state.routeId ~= nil then
				input.drop = true
				return input
			end
			if tt >= weaveAt then
				weave = -weave
				weaveAt = tt + 0.3
				heading = rng.next() * math.pi * 2
			end
			input.fw, input.side = 1, weave
			local now, pend, tell = Squirrel.windup(pending, state.clock, true, windup, state.cooldown <= 0)
			pending = pend
			if tell then
				local k = state.clock
				local arrive = tt + link.latency + rng.next() * link.jitter
				if rng.next() < link.loss then
					arrive += 2 * link.latency + link.jitter + 0.2 -- (resent after a round trip and a timeout)
				end
				rig:at(arrive, function()
					-- (as Boot/Game: a click before the first packet is dated on its arrival)
					local at = (rig.movement :: any):clickAt(heldId(rig), k, rig.t)
					table.insert(dues, (at or rig.t) + windup)
				end)
			end
			input.pounce = now
			return input
		end)
		rig:run(secs)
		-- (each launch the server dated, up to the last pounce counted: dated a trip and a packet after it at most)
		local tied, dated = 0, 0
		local lastMade = made[#made] or 0
		for _, at in seen do
			if at <= lastMade + link.latency + 0.3 then
				dated += 1
				local best = math.huge
				for _, due in dues do
					if CombatService.tied(CP, at, due) then
						tied += 1
						best = 0
						break
					end
					best = math.min(best, at - due)
				end
				if best ~= 0 then
					print(`      untied: a launch at {at}, the nearest click's due {best} s before`)
				end
			end
		end
		return pounces, dated, tied
	end

	for _, c in
		{
			{ name = "80 ms + 250 ms jitter, 2 % loss", link = { latency = 0.08, jitter = 0.25, loss = 0.02 }, seed = 31 },
			{ name = "a slow phone at 300 ms", link = { latency = 0.3, jitter = 0.1, loss = 0.02 }, fps = 20, seed = 32 },
		}
	do
		t.test(`pounce: honest pounces on {c.name}: >= 99 % dated and tied to their click`, function()
			local pounces, seen, tied = honestTies(c.link, c.seed, c.fps)
			print(
				`      {pounces} pounces, {seen} dated, {tied} tied to their click: {string.format(
					"%.1f",
					100 * (pounces - tied) / math.max(1, pounces)
				)} % lost`
			)
			t.truthy(pounces >= 60, "pounces made")
			t.truthy(tied >= 0.99 * pounces, "honest pounces bite when they land")
		end)
	end

	-- a grounded packet's vertical speed is never judged, yet upCap (the rise allowed) and the wall test's `rise` (how
	-- far over the higher end the body could have arced) both trusted it
	local b = town.boxes[1]
	local cz = (b.minZ + b.maxZ) / 2
	local roofY = b.top + town.world.groundHeight

	t.test(
		"ground: a client 'standing' with 300 st/s upward speed is not let onto a 14-stud roof in one packet",
		function()
			local onRoof: number? = nil
			local rig = LiveRig.new({
				world = town.noWalls,
				vworld = town.vworld,
				link = QUIET,
				seed = 26,
				cheat = function(s: State, _inp: SquirrelMotor.Input, now: number, _w: any)
					if now < CHEAT_AT then
						return
					end
					onRoof = onRoof or now
					s.x, s.y, s.z = b.minX + 1.5, roofY, cz
					s.vx, s.vz = 0, 0
					s.grounded = true
					s.vy = if now < (onRoof :: number) + 0.12 then 300 else 0
				end,
			})
			rig:possess(SquirrelMotor.new(b.minX - 0.5, town.world.groundHeight, cz), idle())
			rig:run(CHEAT_AT + 3)
			local r = rig:result()
			print(
				`      {LiveRig.describe("roof in one packet", r)}; root at y {string.format("%.1f", r.root.y)} (roof {roofY})`
			)
			t.truthy(r.snaps >= 1, "snapped")
		end
	)

	t.test(
		"ground: packets sprinting through a house while claiming 300 st/s upward on the ground are flagged",
		function()
			local rig = LiveRig.new({
				world = town.noWalls,
				vworld = town.vworld,
				link = QUIET,
				seed = 27,
				packetCheat = function(snap: { [string]: any }, now: number): boolean?
					if now >= CHEAT_AT and snap.grounded == true then
						snap.vy = 300
					end
					return nil
				end,
			})
			rig:possess(
				SquirrelMotor.new(b.minX - 15, town.world.groundHeight, cz),
				function(now: number, _s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
					local inp = SquirrelMotor.idleInput(-math.pi / 2)
					inp.fw = if now >= CHEAT_AT then 1 else 0
					inp.sprint = true
					return inp
				end
			)
			rig:run(CHEAT_AT + 3)
			local r = rig:result()
			local through = r.client ~= nil and (r.client :: State).x > b.maxX
			print(`      {LiveRig.describe("through a house", r)}; went through: {through}`)
			t.truthy(#r.violations >= 1, "the envelope flags the packets")
		end
	)

	t.test("ground: the wall test's rise is a leap's apex at most, whatever speed a packet claims", function()
		-- (the envelope alone: an airborne packet pair beside the house claiming a huge upward speed at the start, the
		-- straight line through the wall low down: the rise over the higher end may not lift the line over the roof)
		local world = town.vworld
		local prev = SquirrelMotor.new(b.minX - 1, town.world.groundHeight + 2, cz)
		prev.grounded, prev.vy = false, 300
		local next = SquirrelMotor.new(b.minX + 2, town.world.groundHeight + 2.2, cz)
		next.grounded, next.vy = false, 300 - P.gravity * 0.1
		next.clock = prev.clock + 0.1
		local found = SquirrelMotor.envelope(prev, next, 0.1, world, false)
		local wall = false
		for _, v in found do
			wall = wall or v.code == "wall"
		end
		t.truthy(wall, "a wall")
	end)

	t.test("ground: a silent client's root walked through a garden wall beside a tree is a wall (the rail no excuse)", function()
		-- (the server's own root wall test was off within MovementService.C.RAIL_NEAR of any rail; now only while the
		-- packets have the body on a rail)
		local base = TestWorld.build()
		local trunk = Driver.targetsAround(base, 0, 0, 200)[1]
		local foot = base.registry:foot(trunk)
		local box = { minX = foot.x + 2, maxX = foot.x + 3, minZ = foot.z - 6, maxZ = foot.z + 6, top = 14 }
		local world = TestWorld.build({ boxes = { box } })
		local function wall(ox: number, oy: number, oz: number, dx: number, _dy: number, dz: number): boolean
			return TestWorld.segmentCrossesBox({ box }, ox, oz, ox + dx, oz + dz, oy)
		end
		local function down(ox: number, oy: number, oz: number, _dx: number, dy: number, _dz: number): boolean
			local lo = oy + dy
			if lo <= 0 and oy >= 0 then
				return true
			end
			return ox > box.minX and ox < box.maxX and oz > box.minZ and oz < box.maxZ and box.top >= lo and box.top <= oy
		end
		local vworld = ValidatorWorld.build(world, { wall = wall, down = down })
		local z = foot.z + 3
		local rig = LiveRig.new({
			world = world,
			vworld = vworld,
			link = QUIET,
			seed = 28,
			silent = function(tt: number): boolean
				return tt >= CHEAT_AT
			end,
			rootCheat = function(p: { x: number, y: number, z: number }, tt: number, _s: State)
				if tt >= CHEAT_AT then
					p.x, p.z = math.min(foot.x - 3 + 15 * (tt - CHEAT_AT), foot.x + 6), z
				end
			end,
		})
		rig:possess(SquirrelMotor.new(foot.x - 3, world.groundHeight, z), idle())
		rig:run(CHEAT_AT + 3)
		local r = rig:result()
		print(`      {LiveRig.describe("through a wall by a tree", r)}; first snap {r.firstSnap}`)
		t.truthy((r.reasons.wall or 0) >= 1, "a wall")
		t.truthy((r.firstSnap or math.huge) <= CHEAT_AT + 2, "within a rail packet's wait")
	end)

	-- an honest pounce in the air whose new vertical speed happens to lie within gravityEps of the arc's (the envelope
	-- took the move as a plain arc, saw no launch): the server never dated it, and it bit nobody
	t.test("pounce: every honest mid-air pounce (leap, then pounce 0.1-0.75 s later) is seen as a launch", function()
		local unseen, tried = {}, 0
		for k = 0, 26 do
			local delay = 0.1 + k * 0.025
			local leapAt, pounceAt = CHEAT_AT, CHEAT_AT + delay
			local pounced: number? = nil
			local rig = LiveRig.new({ world = town.world, vworld = town.vworld, link = QUIET, seed = 40 + k })
			rig:possess(
				town.openStart(),
				function(now: number, s: State, events: { SquirrelMotor.Event }): SquirrelMotor.Input
					for _, e in events do
						if e.kind == "pounce" and pounced == nil then
							pounced = now
						end
					end
					local inp = SquirrelMotor.idleInput(-math.pi / 2)
					inp.fw = 1
					inp.leap = now >= leapAt and now < leapAt + 0.05 and s.grounded
					inp.pounce = now >= pounceAt and pounced == nil and not s.grounded
					return inp
				end
			)
			rig:run(CHEAT_AT + 2)
			local sq = (rig.movement :: any).squirrels[heldId(rig)]
			if pounced ~= nil then
				tried += 1
				if sq.pounceAt == nil then
					table.insert(unseen, string.format("%.3f", delay))
				end
			end
		end
		print(
			`      {tried} mid-air pounces, {#unseen} never seen as a launch (after the leap by: {table.concat(
				unseen,
				", "
			)} s)`
		)
		t.truthy(tried >= 20, "pounces made")
		t.eq(#unseen, 0, "unseen honest pounces")
	end)

	t.test("duel: the Duel remote hears REMOTE_RATE calls a second and answers a refusal every REPLY_EVERY", function()
		local svc = CombatService.new({
			world = { actors = {}, actorsById = {}, brains = {}, possessed = {} },
			rodents = function(): { number }
				return {}
			end,
		})
		local heard = 0
		for i = 0, 99 do
			if svc:remoteGate("p", i * 0.01) then -- (a hundred calls in a second)
				heard += 1
			end
		end
		print(`      {heard} of 100 calls in a second heard`)
		t.truthy(heard <= CombatService.REMOTE_RATE + CombatService.REMOTE_BURST, "a flood is dropped")
		t.truthy(svc:remoteGate("q", 0), "another player is heard")
		local told = 0
		for i = 0, 19 do
			if svc:mayReply("p", 10 + i * 0.05) then
				told += 1
			end
		end
		t.eq(told, 2, "one refusal told every half second")
		-- an honest clicker (on the motor's cooldown) and feinter is always heard
		local fresh = CombatService.new({
			world = { actors = {}, actorsById = {}, brains = {}, possessed = {} },
			rodents = function(): { number }
				return {}
			end,
		})
		local all = true
		for i = 0, 40 do
			all = all and fresh:remoteGate("p", i * 0.4)
		end
		t.truthy(all, "a click every 0.4 s")
	end)

	t.test("duel: a bite and a blow are judged where the validated motor state has the rodent, not at its root", function()
		local rig = BiteRig.new({ seed = 4, duelRand = function(): number
			return 0
		end, motorCheck = true })
		local poses: { [number]: { number } } = {}
		rig.combat.opts.poseOf = function(id: number): (number?, number?, number?)
			local p = poses[id]
			if p then
				return p[1], p[2], p[3]
			end
			return nil, nil, nil
		end
		rig.step(20)
		local v = rig.calmNear(0, 0)
		rig.holdRodent()
		local rod = rig.world.actorsById[rig.rodent]
		-- the root in contact all through the pounce, the packets 12 studs off: no bite
		local far = function()
			rig.put(rig.rodent, v.x + 0.5, v.z)
			poses[rig.rodent] = { v.x + 12, rod.y - rod.hip, v.z }
		end
		far()
		t.truthy(rig.combat:rodentAct(rig.rodent, "pounce", rig.now()))
		local t0 = rig.time
		rig.step(1.2, function()
			far()
			local into = rig.time - t0 - CP.pounceWindup
			rig.motor[rig.rodent] = { age = 0, launchAgo = if into >= 0 then into else nil }
		end)
		t.eq(rig.combat:stats().bites, 0, "a root flicked onto the person bites nobody")
		-- the packets with it: the bite lands
		poses[rig.rodent] = nil
		rig.step(1)
		t.truthy(rig.lunge(v.id), "a pounce the packets show lands")
	end)

	t.test("duel: a blow lands where the validated motor state has the rodent, not on its root", function()
		local rig = BiteRig.new({ seed = 6, duelRand = function(): number
			return 0
		end })
		local poses: { [number]: { number } } = {}
		rig.combat.opts.poseOf = function(id: number): (number?, number?, number?)
			local p = poses[id]
			if p then
				return p[1], p[2], p[3]
			end
			return nil, nil, nil
		end
		rig.step(20)
		local vig: any = nil
		for id in rig.combat.flags do
			local a = rig.world.actorsById[id]
			if vig == nil or a.id < vig.id then
				vig = a
			end
		end
		t.truthy(vig ~= nil, "the town has vigilantes")
		rig.holdRodent()
		local rod = rig.world.actorsById[rig.rodent]
		local fx, fz = math.sin(vig.yaw), math.cos(vig.yaw)
		local rx, rz = vig.x + fx * 25, vig.z + fz * 25
		rig.put(rig.rodent, rx, rz)
		-- the root where the vigilante comes to kick it, the packets 30 studs further on: nothing lands
		rig.step(5, function()
			poses[rig.rodent] = { rx + fx * 30, rod.y - rod.hip, rz + fz * 30 }
		end)
		local strikes = rig.combat:stats().strikes
		print(`      {strikes} strikes, {#rig.blows} blows on the root alone`)
		t.truthy(strikes >= 1, "it struck")
		t.eq(#rig.blows, 0, "no blow lands on the root alone")
		-- the packets with the root: the blows land
		poses[rig.rodent] = nil
		t.truthy(
			rig.runUntil(6, function(): boolean
				return #rig.blows > 0
			end),
			"with the packets in reach a blow lands"
		)
	end)
end
