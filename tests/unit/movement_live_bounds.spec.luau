--!strict
-- The live squirrel validator against the second adversarial review (2026-11-18): what one packet or one silence may
-- cost the server (bounded, timed at the worst a client can choose), a client that never sends a packet, joining while
-- the town streams in, the server's view of the body against the packets, the server's sprint meter, a slow link after
-- a server move, the paintball sweep, and a clock a little fast. Each cheat must be snapped; each honest case must not.
local Data = require("@shared/Data")
local Height = require("@shared/World/Height")
local RailWorld = require("@shared/Movement/RailWorld")
local Motion = require("@shared/Routes/Motion")
local Curve = require("@shared/Routes/Curve")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local SquirrelWire = require("@shared/Movement/SquirrelWire")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local MoveValidator = require("@server/Movement/MoveValidator")
local MovementService = require("@server/Movement/MovementService")
local MotorLink = require("@client/Controllers/MotorLink")
local LiveRig = require("@tests/lib/LiveRig")

type State = SquirrelMotor.State

-- the live town's rails (Data.default: the harvest, the drains, the hollows, the alley), as Boot/Game.movement has them
local rail = RailWorld.get(Data.default(), Height.at)

-- an honest floor: the terrain
local function terrain(ox: number, oy: number, oz: number, _dx: number, dy: number, _dz: number): boolean
	local g = Height.at(ox, oz)
	return g <= oy and g >= oy + dy
end
-- the worst rays a client can meet: every wall ray stopped but the last of each six (a line laid along a wall with a
-- gap: every chord of a long line costs its six rays and none is a crossing); the floor the terrain (a body high up
-- has none under it: every height check runs to the end); each counted
local rays, wallRays = 0, 0
local function wallAlways(_ox: number, _oy: number, _oz: number, _dx: number, _dy: number, _dz: number): boolean
	rays += 1
	wallRays += 1
	return wallRays % 6 ~= 0
end
local function floorCounted(ox: number, oy: number, oz: number, dx: number, dy: number, dz: number): boolean
	rays += 1
	return terrain(ox, oy, oz, dx, dy, dz)
end
local function noWall(): boolean
	return false
end

local function still(_now: number, _s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
	return SquirrelMotor.idleInput(0)
end

return function(t)
	-- 1. COST ---------------------------------------------------------------------------------------------------------
	-- One squirrel on a MovementService over the live rails with the worst rays; `go` times one call and counts its rays.
	local worstMs, worstRays, worstName = 0, 0, ""
	local function timed(name: string, fn: () -> ()): (number, number)
		rays, wallRays = 0, 0
		local c0 = os.clock()
		fn()
		local ms = (os.clock() - c0) * 1000
		if ms > worstMs then
			worstMs, worstName = ms, name
		end
		worstRays = math.max(worstRays, rays)
		return ms, rays
	end
	local function costRig(x: number, z: number)
		local vworld = ValidatorWorld.build(rail, { wall = wallAlways, down = floorCounted })
		local ms = MovementService.new({
			validator = MoveValidator.new(vworld),
			enforce = true,
			poseOf = function(_a: any): (number?, number?, number?)
				return x, Height.at(x, z), z
			end,
			engine = {
				correct = function(_id: any, _msg: any) end,
				pin = function(_id: any, _on: boolean) end,
				hold = function(_id: any, _x: number, _y: number, _z: number, _s: number) end,
			},
		})
		ms:onHandoff({ id = "a", species = "squirrel" }, nil, "possess")
		local s = SquirrelMotor.new(x, Height.at(x, z), z)
		s.clock = 5
		local seq, now = 0, 100
		local function send(snap: State): any
			seq += 1
			local _, e, dec =
				SquirrelWire.decode(SquirrelWire.encode(seq, ms:epochOf("a"), SquirrelMotor.serialize(snap)))
			return ms:packet("a", "squirrel", { seq = seq, epoch = e, snapshot = dec }, now)
		end
		-- a second of honest standing: the gate passed, the body its driver's
		for _ = 1, 20 do
			s.clock += 0.05
			now += 0.05
			send(s)
			ms:watch("a", s.x, s.y, s.z, now)
		end
		assert(ms:stats().snaps == 0, "the honest second is clean")
		return {
			ms = ms,
			s = s,
			send = send,
			advance = function(dt: number)
				now += dt
			end,
			now = function(): number
				return now
			end,
		}
	end
	-- the densest places of the town's rails (where a rail scan meets the most samples) and a few in the open
	local spots: { { x: number, z: number } } = {}
	do
		local counts: { [string]: { n: number, x: number, z: number } } = {}
		for _, r in rail.registry:all() do
			for i = 0, 8 do
				local p = rail.registry:pointAt(r, i / 8)
				local key = `{math.floor(p.x / 60)},{math.floor(p.z / 60)}`
				local c = counts[key] or { n = 0, x = p.x, z = p.z }
				c.n += 1
				counts[key] = c
			end
		end
		local list = {}
		for _, c in counts do
			table.insert(list, c)
		end
		table.sort(list, function(a, b)
			return a.n > b.n
		end)
		for i = 1, math.min(6, #list) do
			table.insert(spots, { x = list[i].x, z = list[i].z })
		end
		table.insert(spots, { x = 300, z = 200 })
	end

	t.test("cost: no single packet, root sample or silence costs the server more than a small bounded time", function()
		local lines = {}
		for _, spot in spots do
			-- a silence of N s, still (no snap: the root never moved), then one packet whose clock moved N s, far away and
			-- high up, or within reach and laid along a wall
			for _, n in { 10, 60, 600 } do
				for _, shape in { "far and high", "along a wall", "on a far rail" } do
					local r = costRig(spot.x, spot.z)
					for _ = 1, math.floor(n * 15 + 0.5) do
						r.advance(1 / 15)
						r.ms:watch("a", r.s.x, r.s.y, r.s.z, r.now())
					end
					local p = SquirrelMotor.clone(r.s)
					p.clock += n
					if shape == "far and high" then
						p.x += 300
						p.y += 60
						p.grounded = false
					elseif shape == "along a wall" then
						p.x += math.min(MoveValidator.new(rail):fastest("a") * n * 0.9, 2000)
					else
						local far = rail.registry:all()[7]
						local q = rail.registry:pointAt(far, 0.5)
						p.x, p.y, p.z = q.x, q.y, q.z
						p.routeId, p.railT, p.grounded = far.id, 0.5, false
					end
					local msT, n2 = timed(`silent {n} s, {shape}`, function()
						r.send(p)
					end)
					table.insert(lines, `silent {n} s then {shape}: {string.format("%.2f", msT)} ms, {n2} rays`)
				end
			end
			-- numbers at the edge of the wire: a velocity of 9e6 then an air launch 0.05 s on; a packet 9e6 studs away
			do
				local r = costRig(spot.x, spot.z)
				local p = SquirrelMotor.clone(r.s)
				p.clock += 0.05
				p.vx, p.vy, p.vz = 9e6, 9e6, 9e6
				p.grounded = false
				r.advance(0.05)
				timed("a velocity of 9e6", function()
					r.send(p)
				end)
				local q = SquirrelMotor.clone(p)
				q.clock += 0.05
				q.vx, q.vy, q.vz = 30, 20, 0
				q.y += 1
				r.advance(0.05)
				local msT, n2 = timed("an air launch after it", function()
					r.send(q)
				end)
				table.insert(lines, `velocity 9e6 then an air launch: {string.format("%.2f", msT)} ms, {n2} rays`)
				local z = SquirrelMotor.clone(q)
				z.clock += 0.05
				z.x += 9e6
				r.advance(0.05)
				msT, n2 = timed("9e6 studs away", function()
					r.send(z)
				end)
				table.insert(lines, `9e6 studs away: {string.format("%.2f", msT)} ms, {n2} rays`)
			end
			-- the root: silent 4.9 s, then a jump of the root as long as the drift allows, along a wall
			do
				local r = costRig(spot.x, spot.z)
				for _ = 1, 73 do
					r.advance(1 / 15)
					r.ms:watch("a", r.s.x, r.s.y, r.s.z, r.now())
				end
				r.advance(1 / 15)
				-- (the silence rule fires past SILENT: this is the longest the drift lets a root jump be judged for walls)
				local msT, n2 = timed("a long jump of the root", function()
					r.ms:watch("a", r.s.x + 240, r.s.y, r.s.z, r.now())
				end)
				table.insert(lines, `root jump 240 st after 4.9 s: {string.format("%.2f", msT)} ms, {n2} rays`)
			end
			-- the gate: a move the server made, then the first packet held back 30 s and far off
			do
				local r = costRig(spot.x, spot.z)
				r.ms:teleported("a", r.s.x, r.s.y, r.s.z, "reset", r.now())
				r.advance(30)
				local p = SquirrelMotor.clone(r.s)
				p.clock += 30
				p.x += 30
				p.y += 40
				p.grounded = false
				local msT, n2 = timed("the gate's first packet", function()
					local _, _, dec =
						SquirrelWire.decode(SquirrelWire.encode(999, r.ms:epochOf("a"), SquirrelMotor.serialize(p)))
					r.ms:packet("a", "squirrel", { seq = 999, epoch = r.ms:epochOf("a"), snapshot = dec }, r.now())
				end)
				table.insert(lines, `gate after 30 s: {string.format("%.2f", msT)} ms, {n2} rays`)
			end
		end
		print(`      worst {string.format("%.2f", worstMs)} ms ({worstName}), at most {worstRays} rays per call`)
		for i = 1, math.min(#lines, 14) do
			print(`        {lines[i]}`)
		end
		-- the rays an engine pays: one wall judgement of the envelope (6), a long line's chords (C.MAX_CHORDS x 6), the
		-- floor and the air (a few)
		t.truthy(worstRays <= ValidatorWorld.C.MAX_CHORDS * 6 + 12, `rays per call bounded ({worstRays})`)
		-- (Lune's time; generous for a loaded machine: the bound is what matters, before this fix 60 s cost 1,200 ms)
		t.truthy(worstMs < 8, `the worst call {worstName} took {worstMs} ms`)
	end)

	-- 2. A CLIENT THAT NEVER SENDS ---------------------------------------------------------------------------------------
	local town = LiveRig.town()

	t.test(
		"cheat: never a packet, the root run at 100 st/s through the houses with 200-stud blinks: never moves",
		function()
			local s0 = town.openStart()
			local rig = LiveRig.new({
				world = town.noWalls,
				vworld = town.vworld,
				link = { latency = 0.1, jitter = 0.05, loss = 0.02 },
				seed = 41,
				silent = function(_now: number): boolean
					return true
				end,
				rootCheat = function(p: { x: number, y: number, z: number }, now: number, _s: State)
					local a = now * 100 / 150
					p.x = math.cos(a) * 150 + (if (now % 10) < 0.5 then 200 else 0)
					p.z = math.sin(a) * 150
				end,
			})
			local moved = 0
			rig:possess(s0, still)
			for _ = 1, 60 do
				rig:run(1)
				local root = rig.server.root
				moved = math.max(moved, math.sqrt((root.x - s0.x) ^ 2 + (root.z - s0.z) ^ 2))
			end
			local r = rig:result()
			print(
				`      {LiveRig.describe("never a packet", r)}; the server's body moved {moved} st; pinned {rig.movement:stats().pins}`
			)
			t.eq(rig.server.pinned, true, "the body is still the server's")
			t.eq(moved, 0, "the server's body never moved")
		end
	)

	for _, c in { { name = "80 ms", lat = 0.08, jit = 0.15 }, { name = "300 ms", lat = 0.3, jit = 0.15 } } do
		t.test(`honest: a body taken while the town streams in for 8 s, then played ({c.name}): 0 snaps`, function()
			local Rng = require("@tests/cheat/Rng")
			local rng = Rng.new(61)
			local rig = LiveRig.new({
				world = town.world,
				vworld = town.vworld,
				link = { latency = c.lat, jitter = c.jit, loss = 0.02 },
				seed = 61,
				loadSeconds = 8,
			})
			rig:possess(town.startAt(rng), town.driven(rng))
			rig:at(4, function()
				-- (the Reset button pressed while it loads: the correction waits for the new body, never lost)
				rig:teleport(rig.server.root.x, rig.server.root.y, rig.server.root.z, "reset")
			end)
			rig:run(40)
			local r = rig:result()
			print(`      {LiveRig.describe("streaming 8 s", r)}`)
			t.eq(r.snaps, 0, "no snap")
			t.eq(rig.server.pinned, false, "the body is its driver's after the first packet")
			t.truthy(r.accepted > 400, `packets judged ({r.accepted})`)
		end)
	end

	-- 3. THE SERVER'S BODY AGAINST THE PACKETS ---------------------------------------------------------------------------
	-- (the server's root is what bites, hollows, the drains and the arena read: it may not sit far from the packets)
	t.test("cheat: standing still, the root flicked 35 studs out and back every second: snapped every time", function()
		local s0 = town.openStart()
		local rig = LiveRig.new({
			world = town.noWalls,
			vworld = town.vworld,
			link = { latency = 0.1, jitter = 0.05, loss = 0 },
			seed = 11,
			rootCheat = function(p: { x: number, y: number, z: number }, now: number, _s: State)
				if now > 3 and (now % 1) < 0.1 then
					p.x += 35
				end
			end,
		})
		rig:possess(s0, still)
		-- every flick the server's root showed (out of a hold, where the server has the body) must be snapped
		local shown, out = 0, false
		for k = 1, 30 * 60 do
			rig:at(k / 60, function()
				local off = math.abs(rig.server.root.x - s0.x) > 20
				if off and not out then
					shown += 1
				end
				out = off
			end)
		end
		rig:run(30)
		local r = rig:result()
		print(
			`      {LiveRig.describe("root flicked 35 st", r)}; flicks the server's root showed {shown}, holds {r.holds}`
		)
		t.truthy(shown >= 5, "flicks shown")
		t.truthy((r.reasons.drift or 0) >= shown, `every flick snapped ({r.reasons.drift or 0} of {shown})`)
	end)

	t.test(
		"cheat: the root kept 30 studs off honest packets driving through the town: snapped within a second",
		function()
			local Rng = require("@tests/cheat/Rng")
			local rng = Rng.new(12)
			local rig = LiveRig.new({
				world = town.world,
				vworld = town.vworld,
				link = { latency = 0.1, jitter = 0.05, loss = 0 },
				seed = 12,
				rootCheat = function(p: { x: number, y: number, z: number }, now: number, _s: State)
					if now > 3 then
						p.x += 30
					end
				end,
			})
			rig:possess(town.startAt(rng), town.driven(rng))
			rig:run(30)
			local r = rig:result()
			print(`      {LiveRig.describe("root 30 st off", r)}`)
			t.truthy((r.reasons.drift or 0) >= 5, `snapped for drift ({r.reasons.drift or 0})`)
			t.truthy(r.firstSnap ~= nil and (r.firstSnap :: number) < 4.2, `first snap at {r.firstSnap}`)
		end
	)

	-- 4. THE SERVER'S SPRINT METER -----------------------------------------------------------------------------------------
	-- a client that keeps its own meter full and runs faster than a walk on the ground, hiding it three ways
	local function speedTo(target: number): (s: State, _inp: SquirrelMotor.Input, now: number, _w: any) -> ()
		return function(s: State, _inp: SquirrelMotor.Input, now: number, _w: any)
			if now < 2 then
				return
			end
			s.stamina, s.winded = 1, false
			local v = math.sqrt(s.vx ^ 2 + s.vz ^ 2)
			if v > 1 and s.grounded and s.routeId == nil then
				local k = target / v
				s.x += s.vx * (k - 1) / 60
				s.z += s.vz * (k - 1) / 60
			end
		end
	end
	local function backAndForth(sprint: boolean): LiveRig.Keys
		return function(now: number, _s: State, _e: { SquirrelMotor.Event }): SquirrelMotor.Input
			local inp = SquirrelMotor.idleInput(if math.floor(now / 3) % 2 == 0 then -math.pi / 2 else math.pi / 2)
			inp.fw = 1
			inp.sprint = sprint
			return inp
		end
	end
	for _, c in
		{
			{
				name = "every other packet says it is in the air (vy 0, at the same height), 44 st/s",
				speed = 44,
				flip = 2,
			},
			{ name = "every third packet says it is in the air, 44 st/s", speed = 44, flip = 3 },
			{ name = "one packet every 2.6 s (four gaps in ten seconds), 46 st/s", speed = 46, sparse = 2.6 },
			{ name = "a walk 1.19 x the walk's pace, for ever", speed = 21.4, walk = true },
		}
	do
		t.test(`cheat: an endless sprint, {c.name}: snapped for the sprint meter`, function()
			local n = 0
			local rig = LiveRig.new({
				world = town.noWalls,
				vworld = town.vworld,
				link = { latency = 0.12, jitter = 0.1, loss = 0.02 },
				seed = 14,
				cheat = speedTo(c.speed),
				packetCheat = if c.flip
					then function(snap: { [string]: any }, now: number): boolean?
						n += 1
						if now > 2 and n % c.flip == 0 and snap.grounded and snap.routeId == -1 then
							snap.grounded = false
							snap.vy = 0
						end
						return true
					end
					else nil,
				silent = if c.sparse
					then function(now: number): boolean
						return now > 3 and (now % c.sparse) >= 0.04
					end
					else nil,
			})
			rig:possess(town.openStart(), backAndForth(not c.walk))
			rig:run(40)
			local r = rig:result()
			print(`      {LiveRig.describe(c.name, r)}`)
			t.truthy((r.reasons.stamina or 0) >= 1, `snapped for the meter ({r.reasons.stamina or 0})`)
		end)
	end

	-- 6. A SLOW LINK AND A SERVER MOVE -------------------------------------------------------------------------------------
	for _, c in { { 1.0, 0.2 }, { 1.0, 0.5 }, { 0.8, 0.3 } } do
		t.test(`honest: {c[1]} s one way + {c[2]} s jitter, the Reset button at 10 s, played on: 0 snaps`, function()
			local Rng = require("@tests/cheat/Rng")
			local rng = Rng.new(31)
			local rig = LiveRig.new({
				world = town.world,
				vworld = town.vworld,
				link = { latency = c[1], jitter = c[2], loss = 0.02 },
				seed = 31,
			})
			local s0 = town.startAt(rng)
			rig:possess(s0, town.driven(rng))
			rig:at(10, function()
				rig:teleport(s0.x, s0.y, s0.z, "reset")
			end)
			rig:run(50)
			local r = rig:result()
			print(`      {LiveRig.describe(`{c[1]} + {c[2]}`, r)}; holds {r.holds}`)
			t.eq(r.snaps, 0, "no snap")
			t.truthy(r.accepted > 300, `packets judged ({r.accepted})`)
		end)
	end

	-- 5. JOINING ON A BIG TRUNK WHILE THE TOWN STREAMS IN ----------------------------------------------------------------
	t.test(
		"honest: a body taken high on any big trunk, 8 s of streaming, then on the bark: 0 snaps on every trunk",
		function()
			local vworld = ValidatorWorld.build(rail, { wall = noWall, down = terrain })
			local reg, index = rail.registry, rail.index
			local tried, snapped = 0, 0
			for _, r in reg:all() do
				if r.kind ~= "trunk" then
					continue
				end
				for i = 4, 36 do
					local tt = i / 40
					local p = reg:pointAt(r, tt)
					local v = Motion.visualPose(rail, r, tt, Curve.vec3(p.x, p.y, p.z), 1, 0)
					if index:nearest(v.x, v.y, v.z, 3) == nil and v.y - Height.at(v.x, v.z) > 16 then
						tried += 1
						local pins = 0
						local ms = MovementService.new({
							validator = MoveValidator.new(vworld),
							enforce = true,
							poseOf = function(_a: any): (number?, number?, number?)
								return v.x, v.y, v.z
							end,
							engine = {
								correct = function(_id: any, _msg: any) end,
								hold = function(_id: any, _x: number, _y: number, _z: number, _s: number) end,
								pin = function(_id: any, on: boolean)
									pins += if on then 1 else -1
								end,
							},
						})
						ms:onHandoff({ id = "p", species = "squirrel" }, "player", "possess")
						local now = 1000
						for _ = 1, 15 * 8 do
							now += 1 / 15
							ms:watch("p", v.x, v.y, v.z, now)
						end
						-- the controller starts: the motor on the trunk, the root drawn on the bark
						local s = SquirrelMotor.new(p.x, p.y, p.z)
						s.routeId, s.railT, s.grounded = r.id, tt, false
						s.clock = 3
						for seq = 1, 40 do
							s.clock += 0.05
							now += 0.05
							local _, e, dec = SquirrelWire.decode(
								SquirrelWire.encode(seq, ms:epochOf("p"), SquirrelMotor.serialize(s))
							)
							ms:packet("p", "squirrel", { seq = seq, epoch = e, snapshot = dec }, now)
							ms:watch("p", v.x, v.y, v.z, now)
						end
						if ms:stats().snaps > 0 then
							snapped += 1
						end
						t.eq(pins, 0, `route {r.id}: pinned, then given back`)
						break
					end
				end
			end
			print(
				`      {tried} big trunks with a drawn spot off the rail samples and over 16 st up: {snapped} snapped`
			)
			t.truthy(tried >= 20, "the big trunks were tried")
			t.eq(snapped, 0, "no snap")
		end
	)

	t.test(
		"MotorLink: the grant's epoch keeps a newer correction already queued (a move while the body loaded)",
		function()
			local link = MotorLink.new(function(_b: buffer) end)
			link:setEpoch(3)
			link:offer({ epoch = 7, x = 1, y = 2, z = 3, snap = false })
			link:setEpoch(5) -- (the grant of epoch 5 taken after the body streamed in)
			local s = SquirrelMotor.new(50, 0, 50)
			local applied = link:apply(s, 1)
			t.truthy(applied, "the correction is still there")
			t.eq(link.epoch, 7, "and its epoch is taken")
			link:offer({ epoch = 4, x = 0, y = 0, z = 0 })
			t.eq(#link.pending, 0, "an older one is not")
		end
	)
end
