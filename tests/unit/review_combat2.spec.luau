--!strict
-- REVIEW (combat merge re-review, w0-foundation f23d8ff): failing cases for the anti-cheat changes. Each test states
-- what must hold; on f23d8ff each FAILS. Not game code; drop this file once the findings are fixed (or fold the cases
-- into movement_live_rig / combat_validator).
--   1 hover: a client claiming a free fall but keeping its height is never flagged (the "mean of its end speeds"
--     arc bound clamps at 0, so any falling arc may rise by the slack: a regression of a23cbb6)
--   2 ladder: every packet a mid-air "launch" (vy a hair above the last), each allowed a full-gap rise at the leap's
--     speed; the air-launch rate check runs only for gaps <= shortDt, and a launched packet's vy has no floor
--   3 micro-hop: any launch the envelope sees (a 1.5 st/s hop) with a claimed attackWindow is taken as the motor's
--     pounce (MovementService.pounceAt), so "a click with no real pounce bites nobody" does not hold
--   4 back-dated lunge: the server dates a launch by the client's own attackWindow anywhere inside the packet gap;
--     withholding packets ~0.4 s lets a lunge held back 0.28 s after the click be dated at the click
--   5 honest refusals: the click's own jitter (and a resent reliable click) is not in the 0.2 s tie; on a 250 ms
--     jitter, 2 % loss link a few % of honest pounces are untied and bite nobody, silently
--   6, 7 a grounded packet's vy is never judged, but the rise allowed (upCap) and the wall test's `rise` trust it: one
--     packet onto a 14-stud roof; packets through a house (only the root's own wall test, off near any rail, sees it)
--   8 an honest mid-air pounce whose vy happens to match the arc is taken as a plain arc: no launch, no bite
local Tunables = require("@shared/Config/Tunables")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local Squirrel = require("@client/Controllers/Squirrel")
local CombatRules = require("@shared/Combat/CombatRules")
local Rng = require("@tests/cheat/Rng")
local LiveRig = require("@tests/lib/LiveRig")

type State = SquirrelMotor.State

local QUIET = { latency = 0.1, jitter = 0.01, loss = 0 }
local CHEAT_AT = 5

local function idle(): LiveRig.Keys
	return function(_now: number, _s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
		return SquirrelMotor.idleInput(-math.pi / 2)
	end
end

-- an honest leap at CHEAT_AT, then (from its apex) `mode(t)` decides each frame: "hover" holds the height while the
-- vertical speed keeps falling at gravity; "ladder" climbs 30 st/s while the vertical speed rises 10 st/s a second
-- (every packet a launch over the one before, with every other packet withheld: gaps of 0.1 s)
local function flyCheat(mode: (t: number) -> string): (LiveRig.Keys, any, any, { peak: number, from: number? })
	local g = SquirrelMotor.params.gravity
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

return function(t)
	local town = LiveRig.town()

	t.test("REVIEW 1: a client hovering at a leap's apex while claiming a free fall is snapped within 1 s", function()
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

	t.test("REVIEW 2: a client climbing on mid-air launches at 10 packets a second is snapped within 1 s", function()
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
		for i = 1, math.min(4, #r.violations) do
			print(`      VIOLATION {r.violations[i]}`)
		end
		t.truthy(info.from ~= nil, "the cheat ran")
		local from = (info.from or math.huge) + 1
		t.truthy(r.snaps >= 1 and (r.firstSnap or math.huge) <= from + 1, `snapped within 1 s (first {r.firstSnap})`)
	end)

	t.test("REVIEW 3: a 1.5 st/s hop claiming the pounce's window is not taken as the motor's pounce", function()
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
					snap.attackWindow = SquirrelMotor.params.pounceWindow
				end
				return nil
			end,
		})
		rig:possess(town.openStart(), idle())
		rig:run(CHEAT_AT + 2)
		local r = rig:result()
		local pounceAt: number? = nil
		for _, sq in (rig.movement :: any).squirrels do
			pounceAt = sq.pounceAt
		end
		print(`      {LiveRig.describe("micro-hop", r)}; pounceAt {pounceAt}`)
		t.eq(r.snaps, 0, "(the hop itself is a move the envelope accepts)")
		t.eq(pounceAt, nil, "a hop is not a pounce")
	end)

	t.test("REVIEW 4: a lunge held 0.28 s behind a packet gap is not dated at the click", function()
		local P = CombatRules.params()
		local windup = Tunables.get("pounce.windup")
		local click = CHEAT_AT -- (the click's tell would reach the server at click + latency)
		local launch = CHEAT_AT + 0.4 -- the motor's pounce, 0.28 s later than the click said
		local pounced: number? = nil
		local rig = LiveRig.new({
			world = town.world,
			vworld = town.vworld,
			link = QUIET,
			seed = 24,
			packetCheat = function(snap: { [string]: any }, now: number): boolean?
				if now > click and pounced == nil then
					return false -- nothing sent while the lunge is held back
				end
				if pounced ~= nil and now >= launch and (snap.attackWindow :: number) > 0 then
					-- back-dated: the window claims the pounce started when the click said
					local claimed = SquirrelMotor.params.pounceWindow - (now - (click + windup))
					snap.attackWindow = math.min(snap.attackWindow :: number, claimed)
				end
				return nil
			end,
		})
		rig:possess(
			town.openStart(),
			function(now: number, _s: State, events: { SquirrelMotor.Event }): SquirrelMotor.Input
				for _, e in events do
					if e.kind == "pounce" and pounced == nil then
						pounced = now
					end
				end
				local inp = SquirrelMotor.idleInput(-math.pi / 2)
				inp.pounce = now >= launch and pounced == nil
				return inp
			end
		)
		rig:run(CHEAT_AT + 2)
		local r = rig:result()
		local pounceAt: number? = nil
		for _, sq in (rig.movement :: any).squirrels do
			pounceAt = sq.pounceAt
		end
		local due = click + QUIET.latency + windup -- CombatService's launchDue for that click
		print(
			`      {LiveRig.describe("held lunge", r)}; the motor pounced at {pounced}, the server dates it {pounceAt}, the click's due {due}`
		)
		t.truthy(pounced ~= nil and pounceAt ~= nil, "the pounce happened and the server saw it")
		t.eq(r.snaps, 0, "(nothing else wrong with it)")
		t.truthy(
			math.abs((pounceAt or due) - due) > P.rewind + P.launchSlack,
			`a launch {string.format("%.2f", (pounced or 0) - click - windup)} s late is not tied to the click`
		)
	end)

	t.test("REVIEW 5: honest pounces on 80 ms + 250 ms jitter, 2 % loss: >= 98 % tied to their click", function()
		-- as combat_validator's case, but the click has its own trip too (a reliable remote: its own jitter, and a
		-- lost one resent about a round trip later)
		local link = { latency = 0.08, jitter = 0.25, loss = 0.02 }
		local rng = Rng.new(31)
		local rig = LiveRig.new({ world = town.world, vworld = town.vworld, link = link, seed = 31 })
		local P = CombatRules.params()
		local windup = Tunables.get("pounce.windup")
		local pending: number? = nil
		local clickArrivals: { number } = {}
		local seen: { number } = {}
		local lastSeen: number? = nil
		local heading = 0
		local weave, weaveAt = 1, 0
		rig:possess(town.startAt(rng), function(tt: number, state: State, _e: { any }): SquirrelMotor.Input
			for _, sq in (rig.movement :: any).squirrels do
				if sq.pounceAt ~= nil and sq.pounceAt ~= lastSeen then
					lastSeen = sq.pounceAt
					table.insert(seen, sq.pounceAt)
				end
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
			local now, pend, tell = Squirrel.windup(pending, tt, true, windup, state.cooldown <= 0)
			pending = pend
			if tell then
				local arrive = tt + link.latency + rng.next() * link.jitter
				if rng.next() < link.loss then
					arrive += 2 * link.latency + link.jitter + 0.2 -- (resent after a round trip and a timeout)
				end
				table.insert(clickArrivals, arrive)
			end
			input.pounce = now
			return input
		end)
		rig:run(90)
		local tied, judged = 0, 0
		for _, at in seen do
			local best = math.huge
			for _, ca in clickArrivals do
				best = math.min(best, math.abs(at - (ca + windup)))
			end
			judged += 1
			if best <= P.rewind + P.launchSlack then
				tied += 1
			end
		end
		print(
			`      {judged} launches seen, {tied} tied to their click ({string.format(
				"%.1f",
				100 * tied / math.max(1, judged)
			)} %)`
		)
		t.truthy(judged >= 60, "pounces seen")
		t.truthy(tied >= 0.98 * judged, "honest pounces bite when they land")
	end)

	-- a grounded packet's vertical speed is never judged, yet upCap (the rise allowed) and the wall test's `rise` (how
	-- far over the higher end the body could have arced) both trust it
	local b = town.boxes[1]
	local cz = (b.minZ + b.maxZ) / 2
	local roofY = b.top + town.world.groundHeight

	t.test(
		"REVIEW 6: a client 'standing' with 300 st/s upward speed is not let onto a 14-stud roof in one packet",
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
			for i = 1, math.min(3, #r.violations) do
				print(`      VIOLATION {r.violations[i]}`)
			end
			t.truthy(r.snaps >= 1, "snapped")
		end
	)

	-- (on f23d8ff only the server's own root wall test catches it, and that test is off within a rail's reach of the
	-- root: a house beside a tree, a fence or a drainpipe)
	t.test(
		"REVIEW 7: packets sprinting through a house while claiming 300 st/s upward on the ground are flagged",
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
			for i = 1, math.min(3, #r.violations) do
				print(`      VIOLATION {r.violations[i]}`)
			end
			t.truthy(through, "(the client went through)")
			t.truthy(#r.violations >= 1, "the envelope flags a packet through the wall")
		end
	)
	-- an honest pounce in the air whose new vertical speed happens to lie within gravityEps of the arc's (the envelope
	-- takes the move as a plain arc, sees no launch): the server never dates it, and it bites nobody
	t.test("REVIEW 8: every honest mid-air pounce (leap, then pounce 0.1-0.75 s later) is seen as a launch", function()
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
			local seenAt: number? = nil
			for _, sq in (rig.movement :: any).squirrels do
				seenAt = sq.pounceAt
			end
			if pounced ~= nil then
				tried += 1
				if seenAt == nil then
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
end
