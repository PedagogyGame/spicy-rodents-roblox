--!strict
-- The live squirrel validator on the rig (tests/lib/LiveRig): every honest situation a player meets is played through
-- the client's motor, a real link (latency 80 to 300 ms, jitter, 2 % loss, held-up and lost bursts) and the server's
-- MovementService with enforcement on, and must end with 0 snaps; every cheat must be snapped back.
-- The town here is the S3 world (tests/cheat/TestWorld: the harvest's 1,332 routes on v5.4's flat core) with houses
-- among the trees for walls, judged by the live wall and floor rays (Server/Movement/ValidatorWorld) over boxes; the
-- enclosed runs are the real ones on their baked geometry (the sewers' stand-in, the hollow trees' shell, the bowling
-- alley's ball returns and roof).
local process = require("@lune/process")
local Units = require("@shared/Config/Units")
local Height = require("@shared/World/Height")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local Driver = require("@tests/cheat/Driver")
local Harness = require("@tests/cheat/Harness")
local Rng = require("@tests/cheat/Rng")
local TestWorld = require("@tests/cheat/TestWorld")
local LiveRig = require("@tests/lib/LiveRig")

local FAST = process.env.SPICY_FAST ~= nil

type State = SquirrelMotor.State

return function(t)
	-- houses among the trees of the town's centre: boxes clear of every route by 4 studs
	local base = TestWorld.build()
	local boxes: { TestWorld.Box } = {}
	do
		local rng = Rng.new(99)
		local tries = 0
		while #boxes < 14 and tries < 400 do
			tries += 1
			local cx, cz = (rng.next() * 2 - 1) * Units.st(80), (rng.next() * 2 - 1) * Units.st(80)
			local hw, hd = 6 + rng.next() * 6, 6 + rng.next() * 6
			if base.index:nearest(cx, base.groundHeight + 3, cz, math.max(hw, hd) + 6) == nil then
				table.insert(boxes, { minX = cx - hw, maxX = cx + hw, minZ = cz - hd, maxZ = cz + hd, top = 14 })
			end
		end
	end
	local world = TestWorld.build({ boxes = boxes })
	local function wall(ox: number, oy: number, oz: number, dx: number, _dy: number, dz: number): boolean
		return TestWorld.segmentCrossesBox(boxes, ox, oz, ox + dx, oz + dz, oy)
	end
	local function down(ox: number, oy: number, oz: number, _dx: number, dy: number, _dz: number): boolean
		local lo = oy + dy
		if lo <= 0 and oy >= 0 then
			return true
		end
		for _, b in boxes do
			if ox > b.minX and ox < b.maxX and oz > b.minZ and oz < b.maxZ and b.top >= lo and b.top <= oy then
				return true
			end
		end
		return false
	end
	local vworld = ValidatorWorld.build(world, { wall = wall, down = down })
	local targets = Driver.targetsAround(world, 0, 0, Units.st(95))

	local function startAt(rng: Rng.Rng): State
		local trunk = targets[math.floor(rng.next() * #targets) + 1]
		local foot = world.registry:foot(trunk)
		local angle = rng.next() * math.pi * 2
		return SquirrelMotor.new(
			foot.x + math.sin(angle) * Units.st(6),
			world.groundHeight,
			foot.z + math.cos(angle) * Units.st(6)
		)
	end
	local function driven(rng: Rng.Rng, boosted: boolean?): LiveRig.Keys
		local d = Driver.new(world, rng, targets)
		return function(_t: number, state: State, events: { SquirrelMotor.Event }): SquirrelMotor.Input
			if boosted then
				state.boostRemaining = 30
			end
			return d:input(state, events, 1 / 60)
		end
	end

	local MINUTES = if FAST then 0.5 else 2
	local towns: { { name: string, link: LiveRig.Link, fps: any?, boosted: boolean?, seed: number } } = {
		{ name = "80 ms, 150 ms jitter, 2 % loss", link = { latency = 0.08, jitter = 0.15, loss = 0.02 }, seed = 1 },
		{ name = "300 ms, 150 ms jitter, 2 % loss", link = { latency = 0.3, jitter = 0.15, loss = 0.02 }, seed = 2 },
		{
			name = "held-up bursts: everything for 0.6 s every 4 s arrives at once",
			link = { latency = 0.12, jitter = 0.1, loss = 0.02, holdEvery = 4, holdFor = 0.6 },
			seed = 3,
		},
		{
			name = "lost bursts: nothing for 0.8 s every 5 s",
			link = { latency = 0.12, jitter = 0.1, loss = 0.02, dropEvery = 5, dropFor = 0.8 },
			seed = 4,
		},
		{ name = "a slow phone: 20 frames a second", link = { latency = 0.15 }, fps = 20, seed = 5 },
		{
			name = "a slower phone: 12 frames a second with a 0.4 s hitch every 3 s",
			link = { latency = 0.15 },
			fps = function(frame: number, _t: number): number
				return if frame % 36 == 0 then 0.4 else 1 / 12
			end,
			seed = 6,
		},
		{ name = "the chili rush (boost on, the server knows)", link = { latency = 0.15 }, boosted = true, seed = 7 },
	}
	for _, c in towns do
		t.test(`honest in town, leaps, pounces, sprints and transfers: {c.name}: 0 snaps`, function()
			local rng = Rng.new(c.seed)
			local rig = LiveRig.new({
				world = world,
				vworld = vworld,
				link = c.link,
				fps = c.fps,
				boosted = c.boosted,
				seed = c.seed,
			})
			rig:possess(startAt(rng), driven(rng, c.boosted))
			rig:run(60 * MINUTES)
			local r = rig:result()
			print(`      {LiveRig.describe(c.name, r)}`)
			for _, v in r.violations do
				print(`      VIOLATION {v}`)
			end
			print(`      server cost {string.format("%.4f", r.serverMsPerTick)} ms per squirrel per tick`)
			t.eq(r.snaps, 0, "snaps")
			t.truthy(r.accepted > 60 * MINUTES * 5, `packets judged ({r.accepted})`)
		end)
	end

	-- THE SERVER MOVES THE BODY (every such move tells the validator: Boot/Game, Actors/Possession onTeleport)
	local function zigzag(sprint: boolean): LiveRig.Keys
		return function(now: number, _s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
			local inp = SquirrelMotor.idleInput(if math.floor(now) % 2 == 0 then -math.pi / 2 else math.pi / 2)
			inp.fw = 1
			inp.sprint = sprint
			inp.leap = math.floor(now * 4) % 7 == 0
			return inp
		end
	end
	local function open(dx: number, dz: number): State
		local g = Harness.OPEN_GROUND
		return SquirrelMotor.new(
			Units.st((g.minX + g.maxX) / 2) + dx,
			world.groundHeight,
			Units.st((g.minZ + g.maxZ) / 2) + dz
		)
	end
	local slow: LiveRig.Link = { latency = 0.3, jitter = 0.15, loss = 0.02 }
	local fast: LiveRig.Link = { latency = 0.08, jitter = 0.15, loss = 0.02 }
	local events: { { name: string, script: (rig: LiveRig.Rig) -> () } } = {
		{
			name = "the Reset button: put 40 studs back, mid-sprint, three times",
			script = function(rig: LiveRig.Rig)
				for k = 1, 3 do
					rig:at(k * 4 + 0.37, function()
						local s = open(0, if k % 2 == 0 then 40 else -40)
						rig:teleport(s.x, s.y + 3, s.z, "reset")
					end)
				end
			end,
		},
		{
			name = "knocked clear of a table by a ball (3 studs), every 1.5 s",
			script = function(rig: LiveRig.Rig)
				for k = 1, 8 do
					rig:at(k * 1.5 + 0.11, function()
						local c = rig.client.state
						if c then
							rig:teleport(c.x + 3, world.groundHeight + 0.6, c.z, "knocked")
						end
					end)
				end
			end,
		},
		{
			name = "put out of the lounge's door (12 studs) by the sweep",
			script = function(rig: LiveRig.Rig)
				rig:at(3.2, function()
					local c = rig.client.state
					if c then
						rig:teleport(c.x - 12, world.groundHeight, c.z + 5, "lounge")
					end
				end)
			end,
		},
		{
			name = "the sky lift: board, ride 20 s, alight 300 studs away and run on",
			script = function(rig: LiveRig.Rig)
				rig:at(3, function()
					rig:board()
				end)
				rig:at(23, function()
					local s = open(0, 300)
					rig:alight(s.x, s.y, s.z)
				end)
			end,
		},
		{
			name = "a hand-off mid-sprint to a body 60 studs away (the old body's packets still arriving)",
			script = function(rig: LiveRig.Rig)
				rig:at(4.05, function()
					rig:handoff(open(10, 60), zigzag(true))
				end)
				rig:at(9.5, function()
					rig:handoff(open(-10, -50), zigzag(false))
				end)
			end,
		},
		{
			name = "knocked out, back to the menu, a new body 3 s later",
			script = function(rig: LiveRig.Rig)
				rig:at(4, function()
					rig:release()
				end)
				rig:at(7, function()
					rig:possess(open(20, 20), zigzag(true))
				end)
			end,
		},
	}
	for _, e in events do
		for _, l in { { name = "80 ms", link = fast }, { name = "300 ms", link = slow } } do
			t.test(`honest: {e.name} ({l.name}): 0 snaps`, function()
				local rig = LiveRig.new({ world = world, vworld = vworld, link = l.link, seed = 21 })
				rig:possess(open(0, 0), zigzag(true))
				e.script(rig)
				rig:run(32)
				local r = rig:result()
				print(`      {LiveRig.describe(e.name .. " (" .. l.name .. ")", r)}`)
				for _, v in r.violations do
					print(`      VIOLATION {v}`)
				end
				t.eq(r.snaps, 0, "snaps")
				t.truthy(r.accepted > 100, `packets judged ({r.accepted})`)
			end)
		end
	end

	t.test(
		"honest: walking off the river bank, the client's own recovery to the quay, again and again: 0 snaps",
		function()
			local river: any = table.clone(world)
			river.groundAt = function(x: number, z: number, _refY: number): number
				return Height.at(x, z) + TestWorld.STAND_HEIGHT
			end
			local riverV = ValidatorWorld.build(world, {
				wall = wall,
				down = function(ox: number, oy: number, oz: number, _dx: number, dy: number, _dz: number): boolean
					local g = Height.at(ox, oz)
					return g >= oy + dy and g <= oy
				end,
			})
			local R = Height.RIVER
			local x = (R.centerX - R.halfWidth - 3) * 2.5
			local z = 100 * 2.5
			local rig = LiveRig.new({ world = river, vworld = riverV, link = slow, seed = 31 })
			rig:possess(
				SquirrelMotor.new(x, river.groundAt(x, z, 100), z),
				function(_now: number, _s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
					local inp = SquirrelMotor.idleInput(-math.pi / 2)
					inp.fw = 1
					return inp
				end
			)
			rig:run(20)
			local r = rig:result()
			print(`      {LiveRig.describe("river", r)}; {r.recoveries} recoveries to the quay`)
			t.truthy(r.recoveries >= 3, "fell in and was put on the quay again and again")
			for _, v in r.violations do
				print(`      VIOLATION {v}`)
			end
			t.eq(r.snaps, 0, "snaps")
			t.truthy(r.accepted > 100, `packets judged ({r.accepted})`)
		end
	)

	-- CHEATS: a modified client, from 5 s on (the first 5 s are honest)
	local CHEAT_AT = 5
	-- sprinting east and west by turns, a second each way (the camera looks along -x: W runs east)
	local function sprintEast(): LiveRig.Keys
		return function(now: number, _s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
			local inp = SquirrelMotor.idleInput(if math.floor(now) % 2 == 0 then -math.pi / 2 else math.pi / 2)
			inp.fw = 1
			inp.sprint = true
			return inp
		end
	end
	-- the S3 harness's open ground (no route, no house), in the town's south-west corner
	local function openStart(): State
		local g = Harness.OPEN_GROUND
		return SquirrelMotor.new(Units.st((g.minX + g.maxX) / 2), world.groundHeight, Units.st((g.minZ + g.maxZ) / 2))
	end
	local noWalls: any = table.clone(world)
	noWalls.blocked, noWalls.blockedCore, noWalls.blockedHalf = nil, nil, nil
	local function cheating(now: number): boolean
		return now >= CHEAT_AT
	end
	local cheats: {
		{
			name: string,
			start: (() -> State)?,
			opts: { [string]: any },
			keys: LiveRig.Keys?,
			holds: boolean?,
			from: number?,
		}
	} =
		{
			{
				name = "speed x2 (the motor stepped twice a frame), sprinting",
				keys = function(now: number, _s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
					-- walking until the cheat (a full meter), then the sprint
					local inp = SquirrelMotor.idleInput(if math.floor(now) % 2 == 0 then -math.pi / 2 else math.pi / 2)
					inp.fw = 1
					inp.sprint = now >= CHEAT_AT
					return inp
				end,
				opts = {
					cheat = function(s: State, inp: SquirrelMotor.Input, now: number, w: any)
						if cheating(now) then
							local clock = s.clock
							SquirrelMotor.step(s, inp, 1 / 60, w)
							s.clock = clock
						end
					end,
				},
			},
			{
				name = "speed x2 as a time hack (the clock runs twice as fast too)",
				opts = {
					cheat = function(s: State, inp: SquirrelMotor.Input, now: number, w: any)
						if cheating(now) then
							SquirrelMotor.step(s, inp, 1 / 60, w)
						end
					end,
				},
			},
			{
				name = "teleport 30 studs",
				opts = {
					cheat = function(s: State, _inp: SquirrelMotor.Input, now: number, _w: any)
						if cheating(now) and now < CHEAT_AT + 0.02 then
							s.z += 30
						end
					end,
				},
			},
			{
				name = "fly: claims the ground 12 studs up",
				opts = {
					cheat = function(s: State, _inp: SquirrelMotor.Input, now: number, _w: any)
						if cheating(now) then
							s.y = world.groundHeight + 12
							s.vy = 0
							s.grounded = true
						end
					end,
				},
			},
			{
				name = "fly: hangs in the air at a fixed height",
				opts = {
					cheat = function(s: State, _inp: SquirrelMotor.Input, now: number, _w: any)
						if cheating(now) then
							s.y = world.groundHeight + 12
							s.vy = 0
							s.grounded = false
						end
					end,
				},
			},
			{
				name = "a client that stops sending and runs on at a sprint, through walls",
				opts = {
					world = noWalls,
					silent = cheating,
				},
			},
			{
				name = "a client that ignores its corrections (teleports again and again)",
				opts = {
					ignoreCorrections = true,
					cheat = function(s: State, _inp: SquirrelMotor.Input, now: number, _w: any)
						if cheating(now) and (now - CHEAT_AT) % 1 < 0.02 then
							s.z += 30
						end
					end,
				},
				holds = true,
			},
		}
	-- through a house: the client's own world has no walls; it sprints at the first house from 15 studs west of it
	do
		local b = boxes[1]
		local cz = (b.minZ + b.maxZ) / 2
		table.insert(cheats, {
			name = "through a wall (a house), at a sprint",
			start = function(): State
				return SquirrelMotor.new(b.minX - 15, world.groundHeight, cz)
			end,
			keys = function(_now: number, _s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
				local inp = SquirrelMotor.idleInput(-math.pi / 2)
				inp.fw = 1
				inp.sprint = true
				return inp
			end,
			opts = { world = noWalls },
			from = 0,
		})
	end
	for _, c in cheats do
		t.test(`cheat: {c.name}: snapped back within 1 s`, function()
			local o: any = {
				world = world,
				vworld = vworld,
				link = { latency = 0.12, jitter = 0.15, loss = 0.02 },
				seed = 11,
			}
			for k, v in c.opts do
				o[k] = v
			end
			local rig = LiveRig.new(o)
			rig:possess(if c.start then c.start() else openStart(), c.keys or sprintEast())
			rig:run(CHEAT_AT + 8)
			local r = rig:result()
			print(`      {LiveRig.describe(c.name, r)}; first snap at {r.firstSnap}`)
			t.truthy(r.snaps >= 1, "snapped")
			local first = r.firstSnap or math.huge
			local from = c.from or CHEAT_AT
			local within = if c.opts.silent then 6.5 else 1
			t.truthy(first >= from and first <= from + within, `first snap at {first}`)
			if c.holds then
				t.truthy(r.holds >= 1, "held after a run of snaps")
			end
		end)
	end
end
