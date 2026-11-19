--!strict
-- Review round 3 (adversarial) of the validator holes fix merged at w0-foundation 983333c: failing cases only.
--   flight  the new "came down on something inside the gap and went off its edge" allowance (a mid-air packet whose
--           vertical speed is not gravity's passes when a floor lies within the gap's fall reach, and that reach grows
--           with the fall speed the packet before claimed): a client hovers, and with a leap from the hover (a floor in
--           reach is also "from the ground") climbs to ~23 studs and flies over houses at 2 packets a second
--   railexit leaving a rail (section 4) has no wall test: a step off a trunk lands on the far side of a garden wall
--   clock   the pounce is dated on the lowest arrival offset of 2 s; a client that slows its clock while it holds the
--           lunge raises its offsets, so the old low offset dates the late lunge back onto the click (held lunge tied)
--   early   the click's clock may be up to CLICK_EARLY (1 s) before it arrived while the wind-up is 0.12 s: the motor
--           lunges first, untold, and the click is sent once the lunge has reached the person: tied
--   pose    bites and blows read the last CLEAN packet; packets with a tiny violation are accepted (fresh, not
--           flagged) but never clean, so the pose the duel judges stays where the rodent was: blows miss it
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local Tunables = require("@shared/Config/Tunables")
local CombatRules = require("@shared/Combat/CombatRules")
local CombatService = require("@server/Combat/CombatService")
local MoveValidator = require("@server/Movement/MoveValidator")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local TestWorld = require("@tests/cheat/TestWorld")
local LiveRig = require("@tests/lib/LiveRig")
local Driver = require("@tests/cheat/Driver")

type State = SquirrelMotor.State

local QUIET = { latency = 0.1, jitter = 0.01, loss = 0 }
local CHEAT_AT = 5
local P = SquirrelMotor.params
local E = SquirrelMotor.envelopeParams

local function heldId(rig: any): any
	for id in (rig.movement :: any).squirrels do
		return id
	end
	return nil
end

local function idle(): LiveRig.Keys
	return function(_now: number, _s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
		return SquirrelMotor.idleInput(-math.pi / 2)
	end
end

return function(t)
	local town = LiveRig.town()
	local CP = CombatRules.params()
	local windup = Tunables.get("pounce.windup")
	local g = P.gravity
	local gEps = g * E.gravityEps

	-- the flight: from standing west of a house, packets `dt` apart; each pair a "leap" from the hover (vy one above the
	-- last, up to `climb` studs) and a hover (vy the most negative the allowance takes, the height held), walking east
	-- over the house at a walk. Returns the validator's violations and the highest point over the ground.
	local function flight(dt: number, secs: number): ({ string }, number)
		local ground = town.world.groundHeight
		local v = MoveValidator.new(town.vworld)
		local s = town.openStart()
		local clock, seq = 0, 1
		v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(s) }, clock)
		local out: { string } = {}
		local peak = 0
		local hoverVy = -(g * dt + gEps * 0.9)
		local n = 0
		local x0 = s.x
		while clock < secs do
			clock += dt
			n += 1
			s.clock = clock
			s.grounded, s.committedAirborne = false, true
			s.vx, s.vz = 2, 0
			s.x = x0 + 2 * clock
			if n % 2 == 0 then
				s.vy = s.vy + 1 -- a "leap" off the floor the gap could have reached
				-- (as high as the next hover's reach lets it stay, a leap's 6.8 at most)
				local reach = -s.vy * dt + 0.5 * g * dt * dt + E.posSlack
				s.y += math.clamp(reach - 0.2 - s.y, 0, 6.8) -- (the floor's top is y 0; the feet stand a little over it)
			else
				s.vy = hoverVy
			end
			seq += 1
			local r = v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(s) }, clock)
			for _, x in r.violations do
				table.insert(out, `{string.format("%.2f", clock)} {x.code}: {x.detail}`)
			end
			peak = math.max(peak, s.y - ground)
		end
		return out, peak
	end

	t.test(
		"flight: packets claiming a fall onto a floor in the gap's reach hover (and leap off the hover) for 6 s",
		function()
			local results = {}
			for _, dt in { 0.1, 0.25, 0.45 } do
				local out, peak = flight(dt, 6)
				print(
					`      every {dt} s: {#out} violations, held {string.format("%.1f", peak)} st over the open ground for 6 s{if #out
							> 0
						then " (first: " .. out[1] .. ")"
						else ""}`
				)
				table.insert(results, { dt = dt, n = #out, peak = peak })
			end
			-- a body that never falls is flying: the first seconds of it must be flagged
			for _, x in results do
				t.truthy(
					x.n >= 1,
					`every {x.dt} s: a body hovering {string.format("%.1f", x.peak)} st up for 6 s is flagged`
				)
			end
		end
	)

	t.test("flight: on the rig, a client flying over a house at 2 packets a second is snapped", function()
		local b = town.boxes[1]
		local cz = (b.minZ + b.maxZ) / 2
		local ground = town.world.groundHeight
		local dt = 0.45
		local hoverVy = -(g * dt + gEps * 0.9)
		local level, vy, n = ground, 0, 0
		local lastKept: number? = nil
		local from: number? = nil
		local x0 = b.minX - 40
		local peak = 0
		local rig = LiveRig.new({
			world = town.noWalls,
			vworld = town.vworld,
			link = QUIET,
			seed = 51,
			cheat = function(s: State, _inp: SquirrelMotor.Input, now: number, _w: any)
				if from == nil then
					return
				end
				s.x, s.z = x0 + P.walk * (now - (from :: number)), cz
				s.y = level
				s.vx, s.vz, s.vy = P.walk, 0, vy
				s.grounded, s.committedAirborne = false, true
			end,
			packetCheat = function(snap: { [string]: any }, now: number): boolean?
				if now < CHEAT_AT then
					return nil
				end
				local clock = snap.clock :: number
				if lastKept ~= nil and clock - (lastKept :: number) < dt - 0.01 then
					return false
				end
				if from == nil then
					from = now
					lastKept = clock
					return nil -- (the last honest packet, standing)
				end
				lastKept = clock
				n += 1
				if n % 2 == 0 then
					vy += 1
					local reach = -vy * dt + 0.5 * g * dt * dt + E.posSlack
					if level + 6.8 - ground <= reach - 0.1 then
						level += 6.8
					end
				else
					vy = hoverVy
				end
				snap.y, snap.vy, snap.grounded = level, vy, false
				snap.vx, snap.vz = P.walk, 0
				peak = math.max(peak, level - ground)
				return nil
			end,
		})
		rig:possess(SquirrelMotor.new(x0, ground, cz), idle())
		rig:run(CHEAT_AT + 8)
		local r = rig:result()
		local past = r.root.x - b.maxX
		print(
			`      {LiveRig.describe("flight", r)}; peak {string.format("%.1f", peak)} st, the root {string.format(
				"%.0f",
				past
			)} st past the house's far wall at y {string.format("%.1f", r.root.y - ground)}`
		)
		t.truthy(r.snaps >= 1, "snapped")
	end)

	-- a garden wall 2 studs east of a trunk's foot, 1 stud thick, 12 long, 14 high (the fix's own garden-wall case)
	local function gardenWall(): (any, any, any, any)
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
			return ox > box.minX
				and ox < box.maxX
				and oz > box.minZ
				and oz < box.maxZ
				and box.top >= lo
				and box.top <= oy
		end
		return world, ValidatorWorld.build(world, { wall = wall, down = down }), trunk, box
	end

	t.test("railexit: a step off a trunk through a 14-stud garden wall is a wall (envelope)", function()
		local world, vworld, trunk, box = gardenWall()
		local railT = 0.05
		local pt = world.registry:pointAt(trunk, railT)
		local codes: { [string]: number } = {}
		local control = 0
		for _, dt in { 0.05, 0.1 } do
			local prev = SquirrelMotor.new(pt.x, pt.y, pt.z)
			prev.routeId, prev.railT, prev.grounded = trunk.id, railT, false
			local next = SquirrelMotor.new(box.maxX + 0.6, world.groundHeight, pt.z)
			next.grounded = true
			next.clock = prev.clock + dt
			for _, v in SquirrelMotor.envelope(prev, next, dt, vworld, false) do
				codes[v.code] = (codes[v.code] or 0) + 1
			end
			-- (control: the same line from the ground beside the trunk is a wall)
			local from = SquirrelMotor.new(pt.x, world.groundHeight, pt.z)
			for _, v in SquirrelMotor.envelope(from, next, dt, vworld, false) do
				if v.code == "wall" then
					control += 1
				end
			end
		end
		local list = {}
		for k, n in codes do
			table.insert(list, `{k} {n}`)
		end
		print(
			`      off the trunk at x {string.format("%.1f", pt.x)} y {string.format("%.1f", pt.y)} over the wall {box.minX}..{box.maxX} to x {box.maxX + 0.6}: [{table.concat(
				list,
				", "
			)}]; the same line from the ground: {control} walls`
		)
		t.eq(control, 2, "(control: from the ground it is a wall)")
		t.truthy((codes.wall or 0) >= 2, "leaving a rail through a wall is a wall")
	end)

	t.test("railexit: on the rig, a client on a trunk steps off through a garden wall and is not snapped", function()
		local world, vworld, trunk, box = gardenWall()
		local foot = world.registry:foot(trunk)
		local moved: number? = nil
		local onRail: number? = nil
		local rig = LiveRig.new({
			world = world,
			vworld = vworld,
			link = QUIET,
			seed = 53,
			cheat = function(s: State, _inp: SquirrelMotor.Input, now: number, _w: any)
				if s.routeId ~= nil and onRail == nil then
					onRail = now
				end
				if now >= CHEAT_AT and moved == nil and s.routeId ~= nil then
					-- off the rail, on the ground beyond the wall (a drop's first frame)
					moved = now
					s.routeId, s.railT = nil, 0
					s.x, s.y, s.z = box.maxX + 0.6, world.groundHeight, foot.z
					s.vx, s.vy, s.vz = 0, 0, 0
					s.grounded = true
				end
			end,
		})
		rig:possess(
			SquirrelMotor.new(foot.x - 1.5, world.groundHeight, foot.z),
			function(now: number, s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
				local inp = SquirrelMotor.idleInput(-math.pi / 2)
				inp.grab = now > 1 and now < 1.1 and s.routeId == nil
				return inp
			end
		)
		rig:run(CHEAT_AT + 3)
		local r = rig:result()
		local beyond = r.root.x > box.maxX
		print(
			`      {LiveRig.describe("off a trunk through a wall", r)}; on the trunk from {onRail}, moved at {moved}; the root at x {string.format(
				"%.1f",
				r.root.x
			)} (the wall {box.minX}..{box.maxX}): beyond {beyond}`
		)
		t.truthy(onRail ~= nil and moved ~= nil, "(the client was on the trunk and stepped off)")
		t.truthy(r.snaps >= 1, "snapped")
	end)

	-- a lunge held back `hold` seconds after click + wind-up while the packets keep flowing, the client's clock slowed to
	-- a fifth of real time for the hold (its packets barely move, so they pass), its offsets rising: the lowest offset
	-- of 2 s ago maps the late launch back by what the clock lost
	local function slowClockLunge(seed: number, hold: number, slow: boolean): (number?, number?, number)
		local click = CHEAT_AT
		local launch = CHEAT_AT + windup + hold
		local pounced: number? = nil
		local clickAt: number? = nil
		local skew = 0
		local lastT: number? = nil
		local rig: any
		rig = LiveRig.new({
			world = town.world,
			vworld = town.vworld,
			link = QUIET,
			seed = seed,
			packetCheat = function(snap: { [string]: any }, now: number): boolean?
				local step = if lastT then now - (lastT :: number) else 0
				lastT = now
				if slow and now > click + windup * 0.5 and now < launch then
					skew += step * 0.8 -- (the clock runs at a fifth of real time while the lunge is held)
				end
				snap.clock = (snap.clock :: number) - skew
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
					local k = s.clock -- (an honest click: its clock as sent before the skew began)
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
			`      {LiveRig.describe("slowed clock", r)}; the motor pounced at {pounced}, the server dates it {sq.pounceAt}, the click at {clickAt}, skew {string.format(
				"%.3f",
				skew
			)}`
		)
		return sq.pounceAt, clickAt, r.snaps
	end

	t.test("clock: a lunge held 0.35 s while the client slows its clock is not tied to the click", function()
		-- (without the slowed clock the same hold is not tied: the fix's own case)
		local pa0, ca0 = slowClockLunge(61, 0.35, false)
		local honestTied = pa0 ~= nil and CombatService.tied(CP, pa0 :: number, (ca0 :: number) + windup)
		t.falsy(honestTied, "(control) the plain held lunge is not tied")
		local pounceAt, clickAt, snaps = slowClockLunge(61, 0.35, true)
		t.eq(snaps, 0, "(nothing else wrong with it)")
		local tied = pounceAt ~= nil
			and clickAt ~= nil
			and CombatService.tied(CP, pounceAt :: number, (clickAt :: number) + windup)
		t.falsy(tied, `a lunge 0.35 s late is not tied (launch {pounceAt}, click {clickAt})`)
	end)

	t.test(
		"early: a click sent 0.4 s after the motor lunged, its clock back-dated, is not tied to that lunge",
		function()
			local lunge = CHEAT_AT
			local pounced: number? = nil
			local clickAt: number? = nil
			local arrived: number? = nil
			local rig: any
			rig = LiveRig.new({ world = town.world, vworld = town.vworld, link = QUIET, seed = 62 })
			local launchClock: number? = nil
			rig:possess(
				town.openStart(),
				function(now: number, s: State, events: { SquirrelMotor.Event }): SquirrelMotor.Input
					for _, e in events do
						if e.kind == "pounce" and pounced == nil then
							pounced = now
							launchClock = s.clock
						end
					end
					if launchClock ~= nil and clickAt == nil and now >= (pounced :: number) + 0.4 then
						-- the click goes now (the lunge has reached whoever it was aimed at), its clock the wind-up before the
						-- lunge
						local k = (launchClock :: number) - windup
						clickAt = -1
						rig:at(now + QUIET.latency, function()
							arrived = rig.t
							clickAt = (rig.movement :: any):clickAt(heldId(rig), k, rig.t)
						end)
					end
					local inp = SquirrelMotor.idleInput(-math.pi / 2)
					inp.pounce = now >= lunge and pounced == nil
					return inp
				end
			)
			rig:run(CHEAT_AT + 2)
			local sq = (rig.movement :: any).squirrels[heldId(rig)]
			local pounceAt = sq.pounceAt
			print(
				`      the motor lunged at {pounced}, dated {pounceAt}; the click arrived at {arrived}, dated {clickAt} ({string.format(
					"%.2f",
					(arrived or 0) - (pounceAt or 0)
				)} s after the launch)`
			)
			t.truthy(pounceAt ~= nil and clickAt ~= nil and (clickAt :: number) > 0, "both dated")
			local tied = CombatService.tied(CP, pounceAt :: number, (clickAt :: number) + windup)
			-- (and the bite window this click opens, commitAt = arrival + wind-up, is still inside that launch's window)
			local open = (arrived :: number) + CP.pounceWindup <= (pounceAt :: number) + CP.pounceWindow + CP.rewind
			print(`      tied {tied}; the bite window opens inside the launch's window: {open}`)
			t.falsy(tied and open, "a tell sent after its lunge already flew is no tell for that lunge")
		end
	)

	t.test(
		"pose: packets each with a tiny violation keep the duel's pose of the rodent where it last was clean",
		function()
			local rig: any
			local walkFrom = CHEAT_AT
			local cap = SquirrelMotor.groundCap(false) * E.speedTol
			rig = LiveRig.new({
				world = town.world,
				vworld = town.vworld,
				link = QUIET,
				seed = 63,
				packetCheat = function(snap: { [string]: any }, now: number): boolean?
					if now >= walkFrom then
						-- (the claimed speed a hair over the cap: a "speed" violation of severity 0.001 a packet, accepted,
						-- never flagged; the body itself walks)
						local vx, vz = snap.vx :: number, snap.vz :: number
						local h = math.sqrt(vx * vx + vz * vz)
						if h < 1e-3 then
							vx, vz, h = 1, 0, 1
						end
						snap.vx, snap.vz = vx / h * cap * 1.001, vz / h * cap * 1.001
					end
					return nil
				end,
			})
			rig:possess(
				town.openStart(),
				function(now: number, _s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
					local inp = SquirrelMotor.idleInput(-math.pi / 2)
					inp.fw = if now >= walkFrom then 1 else 0
					return inp
				end
			)
			rig:run(CHEAT_AT + 4)
			local r = rig:result()
			local id = heldId(rig)
			local good, at = (rig.movement :: any):motorOf(id)
			local sq = (rig.movement :: any).squirrels[id]
			local off = math.sqrt((good.x - sq.lastX) ^ 2 + (good.z - sq.lastZ) ^ 2)
			print(
				`      {LiveRig.describe("dirty packets", r)}; the last accepted packet {string.format(
					"%.2f",
					rig.t - at
				)} s ago, the duel's pose of the rodent {string.format("%.1f", off)} st from it`
			)
			t.eq(r.snaps, 0, "(accepted, never flagged)")
			t.truthy(rig.t - at <= CP.motorFresh, "(the packets are fresh)")
			t.truthy(off <= 3, "the duel judges bites and blows where the accepted packets have the rodent")
		end
	)

	-- ===================================================================================================================
	-- The fixer's attack cases (round 4's rule: every allowance kept gets the cheater's own cases: alternate packet types,
	-- slow and fast clocks, 2 to 30 packets a second, tiny violations under the flag, rail touches)
	-- ===================================================================================================================

	local apex = (P.leapUp * E.launchTol) ^ 2 / (2 * g)

	-- the validator's view of a copy of `s` (what MoveValidator keeps: Judged)
	local function copy(s: State): State
		return SquirrelMotor.deserialize(SquirrelMotor.serialize(s))
	end

	-- A greedy hover: every packet the highest height that passes the envelope from what the validator kept, of a
	-- walk-off claiming a landing hidden in the gap (the most fall the gap allows), a leap off such a landing (vertical
	-- speed one over the last kept) and a plain arc, walking east at a walk. `rate` packets a second of server time, the
	-- client's clock running `clockRate` times as fast. Returns the highest point over the ground, the mean height, and
	-- the validator's violations (the clock's among them).
	local function greedyHover(rate: number, clockRate: number, secs: number): (number, number, number)
		local v = MoveValidator.new(town.vworld)
		local s = town.openStart()
		local ground = town.world.groundHeight
		v:accept("g", { seq = 1, snapshot = SquirrelMotor.serialize(s) }, 0)
		local dt = 1 / rate
		local cdt = dt * clockRate
		local server, clock, seq = 0, 0, 1
		local peak, sum, n, bad = 0, 0, 0, 0
		while server < secs do
			server += dt
			clock += cdt
			seq += 1
			local prev = v:last("g") :: State
			local best: State? = nil
			for _, kind in { "walk", "leap", "arc" } do
				local c = copy(prev)
				c.clock = clock
				c.grounded, c.committedAirborne = false, true
				c.x, c.vx, c.vz = prev.x + P.walk * cdt, P.walk, 0
				c.vy = if kind == "walk" then -g * cdt elseif kind == "leap" then prev.vy + 1 else prev.vy - g * cdt
				local top = prev.y + 12
				local y = top
				while y >= ground do
					c.y = y
					if #SquirrelMotor.envelope(prev, c, cdt, v.world, false) == 0 then
						break
					end
					y -= 0.1
				end
				if y >= ground and (best == nil or y > (best :: State).y) then
					best = copy(c)
				end
			end
			local next = best or copy(prev)
			if best == nil then
				-- (nothing in the air passes: it stands)
				next.clock, next.grounded, next.vy, next.y = clock, true, 0, ground
			end
			local r = v:accept("g", { seq = seq, snapshot = SquirrelMotor.serialize(next) }, server)
			bad += #r.violations
			peak = math.max(peak, next.y - ground)
			sum += next.y - ground
			n += 1
		end
		return peak, sum / math.max(1, n), bad
	end

	t.test("attack (hidden landing): the greediest hover at 2 to 30 packets a second stays under a leap", function()
		for _, rate in { 2, 4, 10, 20, 30 } do
			local peak, mean, bad = greedyHover(rate, 1, 4)
			print(
				`      {rate} packets/s: the highest a landing hidden in every gap holds is {string.format("%.2f", peak)} st, {string.format(
					"%.2f",
					mean
				)} st on average (a leap's apex {string.format("%.2f", apex)}); {bad} violations`
			)
			t.truthy(peak <= apex + E.floorSlack + E.posSlack + 0.1, `{rate}/s: never above a leap over the floor`)
			t.truthy(mean <= apex, `{rate}/s: no hover at a leap's top`)
		end
	end)

	t.test("attack (hidden landing): a slow clock buys no height, a fast one is a clock violation", function()
		for _, k in { 0.5, 0.8, 1.15, 1.3 } do
			local peak, mean, bad = greedyHover(4, k, 8)
			print(
				`      clock x{k} at 4 packets/s: peak {string.format("%.2f", peak)} st, mean {string.format(
					"%.2f",
					mean
				)} st; {bad} violations`
			)
			t.truthy(peak <= apex + E.floorSlack + E.posSlack + 0.1, `clock x{k}: never above a leap over the floor`)
			if k > 1.1 then
				t.truthy(bad >= 1, `clock x{k}: the clock shows`)
			end
		end
	end)

	t.test("attack (hidden landing): a hover claiming the walk-off of a landing is flagged above floorSlack", function()
		for _, rate in { 2, 4, 10, 30 } do
			for _, h in { E.floorSlack + 0.2, 2, 6 } do
				local v = MoveValidator.new(town.vworld)
				local s = town.openStart()
				local ground = town.world.groundHeight
				v:accept("h", { seq = 1, snapshot = SquirrelMotor.serialize(s) }, 0)
				local dt = 1 / rate
				local first: number? = nil
				for i = 1, rate * 2 do
					local c = copy(s)
					c.clock, c.grounded, c.committedAirborne = i * dt, false, true
					c.y = ground + h
					c.vy = -g * dt -- (the most fall a landing in the gap allows)
					local r = v:accept("h", { seq = i + 1, snapshot = SquirrelMotor.serialize(c) }, i * dt)
					if #r.violations > 0 and first == nil then
						first = i * dt
					end
				end
				print(`      {rate}/s, {string.format("%.2f", h)} st up: first flagged at {first}`)
				t.truthy(first ~= nil and (first :: number) <= 1, `{rate}/s at {h} st: flagged within a second`)
			end
		end
	end)

	-- the slow pounce near a wall: a window jump with the speed of a hop, beside the house's west wall
	t.test("attack (slow pounce near a wall): a hop in place 2.5 st off a wall it faces is no pounce", function()
		local b = town.boxes[1]
		local cz = (b.minZ + b.maxZ) / 2
		local ground = town.world.groundHeight
		local function hop(off: number, moveX: number, yaw: number, dt: number): boolean
			local prev = SquirrelMotor.new(b.minX - off - moveX, ground, cz)
			prev.grounded = true
			local next = copy(prev)
			next.clock = prev.clock + dt
			next.x = b.minX - off
			next.grounded, next.committedAirborne = false, true
			next.attackWindow = P.pounceWindow - 0.02
			next.vy = 9 - g * 0.02
			next.vx, next.vz = 2, 0
			next.yaw = yaw
			next.y = ground + 0.15
			local _, _, pounce = SquirrelMotor.envelope(prev, next, dt, town.vworld, false)
			return pounce ~= nil
		end
		local east, west = math.pi / 2, -math.pi / 2
		for _, dt in { 0.05, 0.1, 0.25 } do
			local inPlace = hop(2.5, 0, east, dt)
			local away = hop(2.5, -1, east, dt) -- (moving west, away from the wall it says it faces)
			local backTurned = hop(1, 0, west, dt) -- (touching the wall, facing away from it)
			local touching = hop(1, 0, east, dt) -- (control: a point-blank pounce into the wall)
			local toward = hop(1.2, 1.5, east, dt) -- (control: lunged 1.5 st at the wall and stopped against it)
			print(
				`      dt {dt}: in place 2.5 st off {inPlace}, moving away {away}, back to the wall {backTurned}; touching {touching}, toward it {toward}`
			)
			t.falsy(inPlace, `dt {dt}: a hop in place 2.5 st off the wall is no pounce`)
			t.falsy(away, `dt {dt}: a hop away from the wall is no pounce`)
			t.falsy(backTurned, `dt {dt}: facing away from the wall is no pounce`)
			t.truthy(touching, `dt {dt}: (control) a point-blank pounce into the wall`)
			t.truthy(toward, `dt {dt}: (control) a lunge stopped by the wall`)
		end
	end)

	-- the standing creep: grounded packets a little higher each time, alone or every other packet in the air, at 2 to
	-- 30 packets a second; the highest clean packet over the open ground
	t.test("attack (standing creep): a grounded body rising with no floor under it stops at FLOOR_NEAR", function()
		local near = ValidatorWorld.C.FLOOR_NEAR
		for _, rate in { 2, 10, 30 } do
			for _, step in { 0.02, E.posSlack, 1.3 } do
				for _, mode in { "ground", "alternate" } do
					local v = MoveValidator.new(town.vworld)
					local s = town.openStart()
					local ground = town.world.groundHeight
					v:accept("c", { seq = 1, snapshot = SquirrelMotor.serialize(s) }, 0)
					local dt = 1 / rate
					local y = ground
					local highest = 0
					local flagged: number? = nil
					for i = 1, rate * 4 do
						local c = copy(s)
						c.clock = i * dt
						local air = mode == "alternate" and i % 2 == 1
						if not air then
							y += step
						end
						c.y = y + (if air then step else 0)
						c.grounded = not air
						c.vy = if air then -g * dt else 0
						local r = v:accept("c", { seq = i + 1, snapshot = SquirrelMotor.serialize(c) }, i * dt)
						if #r.violations == 0 then
							highest = math.max(highest, c.y - ground)
						elseif flagged == nil then
							flagged = c.y - ground
						end
						if r.flagged then
							break
						end
					end
					print(
						`      {rate}/s, {step} st a step, {mode}: highest clean {string.format("%.2f", highest)} st; first flagged at {flagged}`
					)
					t.truthy(
						highest <= near + E.posSlack + step,
						`{rate}/s {step} {mode}: never stands more than FLOOR_NEAR over the floor`
					)
				end
			end
		end
	end)

	-- the gap and the rail: a step off a trunk landing beyond the garden wall at 2 to 20 packets a second, near (a short
	-- line) and far (a line longer than a chord: weighed as a gap's, a second one in 20 s a whole flag)
	t.test("attack (rail exit): off a trunk beyond a garden wall after a gap of 0.05 to 0.45 s", function()
		local world, vworld, trunk, box = gardenWall()
		local pt = world.registry:pointAt(trunk, 0.05)
		for _, dt in { 0.05, 0.1, 0.25, 0.45 } do
			for _, past in { 0.6, 3.5 } do
				local v = MoveValidator.new(vworld)
				local on = SquirrelMotor.new(pt.x, pt.y, pt.z)
				on.routeId, on.railT, on.grounded = trunk.id, 0.05, false
				local clock, flagged, codes = 0, false, {}
				for i = 1, 2 do
					-- (twice in 20 s: on the trunk, then off it beyond the wall; the validator keeps its marks)
					clock += 1
					on.clock = clock
					v:reset("r", SquirrelMotor.serialize(on), clock, i * 2 - 1)
					local off = SquirrelMotor.new(box.maxX + past, world.groundHeight, pt.z)
					off.grounded = true
					off.clock = clock + dt
					local r = v:accept("r", { seq = i * 2, snapshot = SquirrelMotor.serialize(off) }, clock + dt)
					for _, x in r.violations do
						table.insert(codes, x.code)
					end
					flagged = flagged or r.flagged
				end
				print(`      dt {dt}, {past} st past the wall: [{table.concat(codes, ", ")}], flagged {flagged}`)
				t.truthy(table.find(codes, "wall") ~= nil, `dt {dt}, {past} st past: a wall`)
				t.truthy(flagged, `dt {dt}, {past} st past: flagged by the second`)
			end
		end
	end)

	-- the rail wait: one packet on the trunk, then the root walked through the wall within the second the old test
	-- waited (silent, or the packets still on the rail); and in and out again
	local function railRoot(variant: string): (number, number?)
		local world, vworld, trunk, box = gardenWall()
		local foot = world.registry:foot(trunk)
		local from: number? = nil
		local rig = LiveRig.new({
			world = world,
			vworld = vworld,
			link = QUIET,
			seed = 71,
			silent = function(now: number): boolean
				return variant == "silent" and from ~= nil and now > (from :: number)
			end,
			rootCheat = function(p: { x: number, y: number, z: number }, now: number, s: State)
				if from == nil and now >= CHEAT_AT and s.routeId ~= nil then
					from = now
				end
				if from == nil then
					return
				end
				local k = (now - (from :: number)) / 0.4
				local x = if variant == "inout" and k > 1 then box.maxX + 0.6 - (k - 1) * 4 else foot.x + k * 4
				p.x = math.min(x, box.maxX + 0.6)
				p.y, p.z = world.groundHeight, foot.z
			end,
		})
		rig:possess(
			SquirrelMotor.new(foot.x - 1.5, world.groundHeight, foot.z),
			function(now: number, s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
				local inp = SquirrelMotor.idleInput(-math.pi / 2)
				inp.grab = now > 1 and now < 1.1 and s.routeId == nil
				return inp
			end
		)
		rig:run(CHEAT_AT + 3)
		local r = rig:result()
		print(
			`      {variant}: {LiveRig.describe("root through the wall by the trunk", r)}; first snap at {r.firstSnap}`
		)
		return r.snaps, r.firstSnap
	end

	t.test(
		"attack (rail wait): a root walked through a wall within a second of a packet on the trunk is a wall",
		function()
			for _, variant in { "silent", "railed", "inout" } do
				local snaps, at = railRoot(variant)
				t.truthy(snaps >= 1, `{variant}: snapped`)
				t.truthy(at ~= nil and (at :: number) <= CHEAT_AT + 2, `{variant}: within RAIL_RECENT of the crossing`)
			end
		end
	)

	-- the late/early tie, the cheater's ways: a slowed clock while holding (at 4 to 20 packets a second, with the
	-- link's jitter faked before the click by an uneven clock), and a click sent after the lunge
	local function heldWith(seed: number, hold: number, rate: number, fake: number): (boolean, number?, number?)
		local click = CHEAT_AT
		local launch = CHEAT_AT + windup + hold
		local pounced: number? = nil
		local clickAt: number? = nil
		local skew, lastT, lastSent = 0, nil :: number?, -math.huge
		local rig: any
		rig = LiveRig.new({
			world = town.world,
			vworld = town.vworld,
			link = QUIET,
			seed = seed,
			packetCheat = function(snap: { [string]: any }, now: number): boolean?
				local step = if lastT then now - (lastT :: number) else 0
				lastT = now
				if now > click + windup * 0.5 and now < launch then
					skew += step * 0.8
				end
				if now - lastSent < 1 / rate - 1e-3 then
					return false
				end
				lastSent = now
				-- (an uneven clock for the 2 s before the click, slowed then sped up again: the arrivals' spread looks like a
				-- jittery link's, the clock never goes back nor ahead of its arrivals)
				local u = (now - (click - 2)) / 2
				local fakeNow = if u > 0 and u < 1 then fake * (1 - math.abs(2 * u - 1)) else 0
				snap.clock = (snap.clock :: number) - skew - fakeNow
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
					local k = s.clock
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
		local sq = (rig.movement :: any).squirrels[heldId(rig)]
		local pounceAt = sq.pounceAt
		local tied = pounceAt ~= nil
			and clickAt ~= nil
			and (clickAt :: number) > 0
			and CombatService.tied(CP, pounceAt :: number, (clickAt :: number) + windup)
		return tied, pounceAt, clickAt
	end

	t.test(
		"attack (late tie): a held lunge with a slowed clock, at 4 to 20 packets a second, jitter faked or not",
		function()
			-- the most an honest link's jitter lets a lunge be late: the round trip the server measures (QUIET: 0.21) and
			-- launchLate; held longer, never tied
			local ping = 2 * QUIET.latency + QUIET.jitter
			for _, rate in { 4, 10, 20 } do
				for _, fake in { 0, 0.3 } do
					local hold = ping + CP.launchLate + 0.08
					local tied, pa, ca = heldWith(80 + rate, hold, rate, fake)
					print(
						`      {rate}/s, jitter faked {fake} s, held {string.format("%.2f", hold)} s with the clock slowed: tied {tied} (launch {pa}, click {ca})`
					)
					t.falsy(tied, `{rate}/s, faked {fake}: a lunge held {hold} s is not tied`)
				end
			end
			-- (control: on time it is, at 20 packets a second)
			local tied = heldWith(90, 0, 20, 0)
			t.truthy(tied, "(control) on time it is tied")
		end
	)

	local function lateClick(seed: number, after: number): (boolean, number?, number?)
		local pounced: number? = nil
		local clickAt: number? = nil
		local rig: any
		rig = LiveRig.new({ world = town.world, vworld = town.vworld, link = QUIET, seed = seed })
		local launchClock: number? = nil
		rig:possess(
			town.openStart(),
			function(now: number, s: State, events: { SquirrelMotor.Event }): SquirrelMotor.Input
				for _, e in events do
					if e.kind == "pounce" and pounced == nil then
						pounced = now
						launchClock = s.clock
					end
				end
				if launchClock ~= nil and clickAt == nil and now >= (pounced :: number) + after then
					local k = (launchClock :: number) - windup
					clickAt = -1
					rig:at(now + QUIET.latency, function()
						clickAt = (rig.movement :: any):clickAt(heldId(rig), k, rig.t)
					end)
				end
				local inp = SquirrelMotor.idleInput(-math.pi / 2)
				inp.pounce = now >= CHEAT_AT and pounced == nil
				return inp
			end
		)
		rig:run(CHEAT_AT + 2)
		local pounceAt = (rig.movement :: any).squirrels[heldId(rig)].pounceAt
		local tied = pounceAt ~= nil
			and clickAt ~= nil
			and (clickAt :: number) > 0
			and CombatService.tied(CP, pounceAt :: number, (clickAt :: number) + windup)
		return tied, pounceAt, clickAt
	end

	t.test("attack (early tie): a click sent 0.1 to 0.45 s after its lunge, back-dated onto it", function()
		-- up to the link's spread (QUIET: 0.01) and a packet (POUNCE_GAP 0.13) after the launch the server dated, the click
		-- may still be tied (an honest click on a jittery link arrives that late); later, never
		for _, after in { 0.05, 0.1, 0.2, 0.3, 0.45 } do
			local tied, pa, ca = lateClick(100 + math.floor(after * 100), after)
			print(`      the click {after} s after the lunge: tied {tied} (launch {pa}, click {ca})`)
			if after >= 0.2 then
				t.falsy(tied, `a click {after} s after the lunge is not tied`)
			end
		end
	end)

	t.test(
		"attack (gap rule): a lunge after a silence longer than a packet and the link's spread is not dated",
		function()
			for _, silence in { 0.2, 0.3, 0.45 } do
				local pounced: number? = nil
				local rig: any
				rig = LiveRig.new({
					world = town.world,
					vworld = town.vworld,
					link = QUIET,
					seed = 120,
					silent = function(now: number): boolean
						return now > CHEAT_AT and now < CHEAT_AT + silence
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
						-- (the lunge goes inside the silence; the packet after it shows its window)
						inp.pounce = now >= CHEAT_AT + silence - 0.06 and pounced == nil
						return inp
					end
				)
				rig:run(CHEAT_AT + 2)
				local pounceAt = (rig.movement :: any).squirrels[heldId(rig)].pounceAt
				print(`      a silence of {silence} s: the motor pounced at {pounced}, the server dates it {pounceAt}`)
				t.eq(pounceAt, nil, `after a {silence} s silence the lunge is not dated`)
			end
		end
	)
end
