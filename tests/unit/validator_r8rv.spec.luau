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
-- About 5 s: `lune run tests/run.luau validator_r8rv`.
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local BakedWorld = require("@tests/lib/BakedWorld")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local TestWorld = require("@tests/cheat/TestWorld")
local LiveRig = require("@tests/lib/LiveRig")

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
end
