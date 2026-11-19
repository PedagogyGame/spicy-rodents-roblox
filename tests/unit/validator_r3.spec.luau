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
end
