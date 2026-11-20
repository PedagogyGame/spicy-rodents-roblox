--!strict
-- Adversarial review, round 8 (the validator at w0-foundation ee8df05, invariant D): failing cases.
--   wall     one long packet through a wall (MoveValidator: a gap's straight line through a wall, crossesLong, weighed
--            0.34, a whole flag only for the second in WALL_GAP_WINDOW) is ACCEPTED: the held place (MovementService
--            .heldPlace, which invariant D makes every system read) is inside, and so is the snap target (sq.good, the
--            next clean packet, from inside). The root never has to cross (DRIFT_BASE 8 st); when it does, the root
--            test's snap puts the body at sq.good: inside. A release (Possession: the held place) puts the body there
--            too. One wall per 20 s, kept.
--   grace    for STREAM_GRACE (3 s) after each hand-off's first packet a move through a wall or a slab alone is
--            logged and the bucket emptied (MovementService: "a house its client may not have streamed in yet"), and the
--            root is not wall-tested (_rootPath `fresh`): a client whose motor ignores walls walks into a closed room
--            right after it is given the body and stays there. A swap and a retake (0.75 s) gives a new grace.
--   meter    the next driver inherits the validator's sprint meter (MoveValidator.takeOver: "the meter no fuller than
--            left"), but its client's motor starts a new body full (SquirrelMotor.new stamina = 1) and is never told: an
--            honest player who takes a body its last driver ran winded, and sprints, is flagged and snapped.
--   sink     the slab ray is cast only for a move of SLAB_DY (0.05) or more, and from RAY_ABOVE (1.5) over the last
--            place: a grounded claim sinks 0.049 st a packet (the floor ray still meets the roof's top within 1.5 over
--            the feet), then one air step under 0.05 (a fall from rest at 30 packets a second: 0.042), and every ray after
--            starts inside the roof: the fall on through it into the sealed storey is never judged (needs build/Town.rbxm).
-- About 10 s: `lune run tests/run.luau validator_r8rv`.
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local BakedWorld = require("@tests/lib/BakedWorld")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local TestWorld = require("@tests/cheat/TestWorld")
local LiveRig = require("@tests/lib/LiveRig")
local MoveValidator = require("@server/Movement/MoveValidator")
local Height = require("@shared/World/Height")
local Data = require("@shared/Data")
local fs = require("@lune/fs")

type State = SquirrelMotor.State
type V3 = { x: number, y: number, z: number }

-- a closed room 20 x 20 st (walls 1 st thick, 14 high), x 0..20, z -10..10: the inside reachable by no door
local ROOM: { TestWorld.Box } = {
	{ minX = -1, maxX = 0, minZ = -11, maxZ = 11, top = 14 },
	{ minX = 20, maxX = 21, minZ = -11, maxZ = 11, top = 14 },
	{ minX = -1, maxX = 21, minZ = -11, maxZ = -10, top = 14 },
	{ minX = -1, maxX = 21, minZ = 10, maxZ = 11, top = 14 },
}

local function inside(p: V3): boolean
	return p.x > 0 and p.x < 20 and p.z > -10 and p.z < 10
end

local function room(): (any, any)
	local world = TestWorld.build({ boxes = ROOM })
	local function wall(ox: number, oy: number, oz: number, dx: number, _dy: number, dz: number): boolean
		return TestWorld.segmentCrossesBox(ROOM, ox, oz, ox + dx, oz + dz, oy)
	end
	local function down(_ox: number, oy: number, _oz: number, _dx: number, dy: number, _dz: number): boolean
		local lo = oy + dy
		return lo <= 0 and oy >= 0
	end
	return world, ValidatorWorld.build(world, { wall = wall, down = down })
end

local function idle(_now: number): SquirrelMotor.Input
	return SquirrelMotor.idleInput(0)
end

return function(t)
	-- wall -------------------------------------------------------------------------------------------------------------
	for _, keepRoot in { false, true } do
		t.test(
			if keepRoot
				then "wall: one long packet through a wall, the root kept outside, then a release: the body put inside"
				else "wall: one long packet through a wall, the root following 0.4 s later: the root test's snap puts it inside",
			function()
				local world, vworld = room()
				local g = world.groundHeight
				local outside: V3 = { x = -3, y = g, z = 0 }
				local into: V3 = { x = 3, y = g, z = 0 }
				local jumped = false
				local jumpedAt = math.huge
				local rig: any
				rig = LiveRig.new({
					world = world,
					vworld = vworld,
					link = { latency = 0.05, jitter = 0, loss = 0 },
					seed = 81,
					-- (a pause in the packets: the gap the long line is judged over)
					silent = function(at: number): boolean
						return at >= 3 and at < 3.3
					end,
					-- (the client's motor put inside at the end of the pause: its next packet is 6 st on, through the wall)
					cheat = function(state: State, _input: any, at: number, _w: any)
						if not jumped and at >= 3.28 then
							jumped = true
							jumpedAt = at
							state.x, state.z = into.x, into.z
						end
					end,
					-- (variant: the root the client writes stays where it was, 6 st from the held place: in drift)
					-- (else the root held there for 0.4 s, while a clean packet or two from inside come in, then it follows)
					rootCheat = function(p: V3, now: number, _s: State)
						if jumped and (keepRoot or now < jumpedAt + 0.4) then
							p.x, p.y, p.z = outside.x, outside.y, outside.z
						end
					end,
				})
				rig:possess(SquirrelMotor.new(outside.x, outside.y, outside.z), idle)
				rig:run(3)
				local before = rig:result().snaps
				rig:run(1.5)
				local held = rig:place() :: V3
				local where: V3
				if keepRoot then
					-- a swap: Possession.releaseNow lets the body go at the held place; the same body taken back
					local rel = rig:release() :: V3
					rig:run(0.75)
					rig.server.count -= 1
					rig:possess(SquirrelMotor.new(rel.x, rel.y, rel.z), idle)
					rig:run(2)
					where = rig:place() :: V3
				else
					rig:run(2)
					where = rig:place() :: V3
				end
				local r = rig:result()
				print(
					string.format(
						"      held place after the long packet %.1f, %.1f (inside %s); at the end %.1f, %.1f (inside %s), root %.1f, %.1f; snaps %d",
						held.x,
						held.z,
						tostring(inside(held)),
						where.x,
						where.z,
						tostring(inside(where)),
						r.root.x,
						r.root.z,
						r.snaps - before
					)
				)
				t.truthy(not inside(where), "a body outside a closed room never ends inside it")
			end
		)
	end
	-- grace ------------------------------------------------------------------------------------------------------------
	t.test(
		"grace: walking through a closed room's wall in the 3 s after a hand-off: not snapped, the body stays in",
		function()
			local world, vworld = room()
			local g = world.groundHeight
			-- (the client's motor with no walls: a client that ignores them)
			local noWalls: any = table.clone(world)
			noWalls.blocked, noWalls.blockedCore, noWalls.blockedHalf = nil, nil, nil
			local rig = LiveRig.new({
				world = noWalls,
				vworld = vworld,
				link = { latency = 0.05, jitter = 0, loss = 0 },
				seed = 82,
			})
			local east = BakedWorld.cameraYawToward(1, 0)
			local start = rig.t
			local function walk(_now: number, s: State): SquirrelMotor.Input
				if s.x < 6 then
					return BakedWorld.keys(east, { fw = 1 })
				end
				return SquirrelMotor.idleInput(east)
			end
			rig:possess(SquirrelMotor.new(-3, g, 0), walk)
			rig:run(4)
			local p = rig:place() :: V3
			local r = rig:result()
			print(
				string.format(
					"      %.1f s after the hand-off: held place %.1f, %.1f (inside %s), root %.1f, %.1f; snaps %d",
					rig.t - start,
					p.x,
					p.z,
					tostring(inside(p)),
					r.root.x,
					r.root.z,
					r.snaps
				)
			)
			t.truthy(not inside(p), "a body outside a closed room never ends inside it")
		end
	)
	-- meter ------------------------------------------------------------------------------------------------------------
	t.test("meter: an honest driver sprints a body its last driver left winded: never snapped", function()
		local rows = {}
		local snapped = 0
		for _, wait in { 0.75, 12 } do
			local world, vworld = room()
			local g = world.groundHeight
			local rig = LiveRig.new({
				world = world,
				vworld = vworld,
				link = { latency = 0.05, jitter = 0, loss = 0 },
				seed = 83,
			})
			local west = BakedWorld.cameraYawToward(-1, 0)
			local function sprint(_now: number, _s: State): SquirrelMotor.Input
				return BakedWorld.keys(west, { fw = 1, sprint = true })
			end
			-- the first driver runs west, out of the meter (honest: its own motor winded)
			rig:possess(SquirrelMotor.new(-5, g, 0), sprint)
			rig:run(6)
			local mid = rig:result().snaps
			local rel = rig:release() :: V3
			rig:run(wait)
			-- the next driver (another player, or the same one back) takes it: a new motor, its meter full
			rig.server.count -= 1
			rig:possess(SquirrelMotor.new(rel.x, rel.y, rel.z), sprint)
			rig:run(4)
			local r = rig:result()
			local reasons = {}
			for k, v in r.reasons do
				table.insert(reasons, `{k}={v}`)
			end
			table.sort(reasons)
			if wait < 1 then
				snapped += r.snaps - mid
			end
			table.insert(
				rows,
				string.format(
					"taken back %.2f s later: first driver %d snaps, next driver %d (%s)",
					wait,
					mid,
					r.snaps - mid,
					table.concat(reasons, " ")
				)
			)
		end
		print(`      {table.concat(rows, "; ")}`)
		t.eq(snapped, 0, "an honest next driver is never snapped")
	end)
	-- sink -------------------------------------------------------------------------------------------------------------
	t.test(
		"sink: a grounded claim sinks under a roof's top by steps under 0.05 st, then falls through it: judged",
		function()
			if not fs.isFile("build/Town.rbxm") then
				t.truthy(false, "build/Town.rbxm (lune run tools/bake/main.luau)")
				return
			end
			Height.configure(Data.default():module("TerrainExtensions"))
			local town = BakedWorld.load("build/Town.rbxm")
			local w = town:motorWorld(Data.default())
			local wall, down, cover = BakedWorld.validatorRays(town)
			local vworld = ValidatorWorld.build(w, { wall = wall, down = down, cover = cover })
			local P = SquirrelMotor.params
			local rows = {}
			local passed = 0
			for _, path in { "Lots.hospital_main.Roof", "Lots.west_police_station.Roof" } do
				local roof: any = nil
				for _, p in town.parts do
					if p.path == path then
						roof = p
					end
				end
				if roof == nil then
					table.insert(rows, `{path}: not found`)
					continue
				end
				local cx, cz = (roof.x0 + roof.x1) / 2, (roof.z0 + roof.z1) / 2
				local top = town.groundAt(cx, cz, roof.y1 + 1)
				local under = town.groundAt(cx, cz, roof.y0 - 1.6)
				local rate = 30
				local v = MoveValidator.new(vworld)
				local s0 = SquirrelMotor.new(cx, top, cz)
				s0.grounded, s0.clock = true, 1
				v:accept("a", { seq = 0, snapshot = SquirrelMotor.serialize(s0) }, 1)
				local seq, now = 0, 1
				local codes: { [string]: number } = {}
				local n = 0
				local function send(st: State)
					seq += 1
					now += 1 / rate
					st.clock = now
					for _, x in v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(st) }, now).violations do
						n += 1
						codes[x.code] = (codes[x.code] or 0) + 1
					end
				end
				for _ = 1, rate do
					local st = SquirrelMotor.new(cx, top, cz)
					st.grounded = true
					send(st)
				end
				-- sink, grounded, 0.049 st a packet, to 1.49 under the top (the floor ray from 1.5 over the feet still meets it)
				local y = top
				while y - 0.049 > top - 1.49 do
					y -= 0.049
					local st = SquirrelMotor.new(cx, y, cz)
					st.grounded = true
					send(st)
				end
				local sunk = y
				-- then a fall from rest, every packet as gravity says, onto what lies under the roof
				local t0 = now
				while true do
					local tt = now + 1 / rate - t0
					local fy = sunk - 0.5 * P.gravity * tt * tt
					local st = SquirrelMotor.new(cx, math.max(fy, under), cz)
					if fy <= under then
						st.grounded = true
						send(st)
						break
					end
					st.grounded, st.vy = false, -P.gravity * tt
					send(st)
				end
				-- and a walk on the floor under it
				for i = 1, rate do
					local st = SquirrelMotor.new(cx + i * 0.25, under, cz)
					st.grounded, st.vx = true, 7.5
					send(st)
				end
				local list = {}
				for k, c in codes do
					table.insert(list, `{k}={c}`)
				end
				table.sort(list)
				if n == 0 then
					passed += 1
				end
				table.insert(
					rows,
					string.format(
						"%s (%.2f thick): sank to %.2f under its top %.1f, fell to %.1f: %d violations %s",
						path,
						roof.y1 - roof.y0,
						top - sunk,
						top,
						under,
						n,
						table.concat(list, " ")
					)
				)
			end
			Height.configure(nil)
			print(`      {table.concat(rows, "; ")}`)
			t.eq(passed, 0, "every sink through a roof judged")
		end
	)
end
