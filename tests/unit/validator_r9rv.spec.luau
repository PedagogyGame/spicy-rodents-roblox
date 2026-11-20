--!strict
-- Adversarial review, round 9 (the validator at w0-foundation b8d30d7, invariant E): failing cases.
--   cover        the held place reaches a clean packet inside a closed room after one long packet through its wall
--                (a third: longer than AROUND_MAX) and a leap inside. ROOFED: MoveValidator.reachable asks aroundFar,
--                whose first leg (start to corner) is asked for no cover over its far end (ValidatorWorld.around, "the
--                lenient way"): its high rays at the higher END's feet + TOP + leapRise (the packet at the leap's height,
--                4.7 st or more over the floor) clear the 14 st wall and the 0.6 st roof, the corner (x1, z0) is inside,
--                and leg 2 is indoors. OPEN-TOPPED: the straight line itself clears the 14 st wall by the same rays (the
--                higher end's height + a whole leap's rise over the whole line, though the low end stood on the ground
--                outside). A release puts the body inside and a retake hands it back there.
--   rail         reachable() takes a line "on the rails" (both ends within ROUTE_NEAR, 8.5 st, of the route one of
--                them claims) with no wall test: the held place on a tree trunk beside a closed room, one long packet
--                through the wall, then clean packets inside within 8.5 st of the trunk: held inside. (In the baked town
--                every core house has its trunk within 8.5 st of its sealed storey.) Also through a snap's gate: snapped back
--                onto the trunk, the new epoch's first packet 6 st inside passes the gate (onRails along) with no doubt.
--   root creep   the root's wall test (MovementService._rootPath: crosses) judges no move shorter than MIN_CHORD: a root
--                written 0.033 st a watch sample walks through any wall while clean packets stand outside (within
--                DRIFT_BASE and SILENT_MOVE), and stays there (the duel's pose is the root once the packets stop).
--   silent       the "unreached" snap is judged only when a packet arrives (MovementService.packet): one doubtful packet
--                into a closed room, then no packet at all: the doubt stands for good, never snapped back. In the grace
--                (handed over 70 st away, the root test off past STREAMED), the root goes in too.
--   slab drop    MoveValidator.throughSlab skips any move with an end on a rail: a drop (Q) off a bridge or a branch over
--                a house, the packets held back 0.48 to 0.6 s so the first one off the rail is already under the
--                ceiling, is never judged for the slab, and every packet after it is clean: the held place lands in the
--                sealed storey with no doubt at all (build/Town.rbxm, the server's rays: the four core houses and the
--                treehouse; 40 of 56 drops).
-- About 10 s: `lune run tests/run.luau validator_r9rv` (the slab drop needs build/Town.rbxm: bake first).
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local BakedWorld = require("@tests/lib/BakedWorld")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local TestWorld = require("@tests/cheat/TestWorld")
local LiveRig = require("@tests/lib/LiveRig")
local Driver = require("@tests/cheat/Driver")
local SquirrelWire = require("@shared/Movement/SquirrelWire")
local MoveValidator = require("@server/Movement/MoveValidator")
local MovementService = require("@server/Movement/MovementService")
local Height = require("@shared/World/Height")
local Data = require("@shared/Data")
local fs = require("@lune/fs")

type State = SquirrelMotor.State
type V3 = { x: number, y: number, z: number }
type B3 = { minX: number, maxX: number, minY: number, maxY: number, minZ: number, maxZ: number }

-- a closed room 60 x 60 st (walls 1 st thick, 0 to 14 high), x 0..60, z -30..30, no door; `roof`: a slab 0.6 thick
-- over it (14 to 14.6), as the baked town's flat roofs (Lots.hospital_main.Roof, 0.60)
local SIZE = 60
local function roomBoxes(ox: number, oz: number, roof: boolean): { B3 }
	local h = SIZE / 2
	local list: { B3 } = {
		{ minX = ox - 1, maxX = ox, minY = 0, maxY = 14, minZ = oz - h - 1, maxZ = oz + h + 1 },
		{ minX = ox + SIZE, maxX = ox + SIZE + 1, minY = 0, maxY = 14, minZ = oz - h - 1, maxZ = oz + h + 1 },
		{ minX = ox - 1, maxX = ox + SIZE + 1, minY = 0, maxY = 14, minZ = oz - h - 1, maxZ = oz - h },
		{ minX = ox - 1, maxX = ox + SIZE + 1, minY = 0, maxY = 14, minZ = oz + h, maxZ = oz + h + 1 },
	}
	if roof then
		table.insert(
			list,
			{ minX = ox - 1, maxX = ox + SIZE + 1, minY = 14, maxY = 14.6, minZ = oz - h - 1, maxZ = oz + h + 1 }
		)
	end
	return list
end

local function insideOf(ox: number, oz: number): (p: V3) -> boolean
	return function(p: V3): boolean
		return p.x > ox and p.x < ox + SIZE and p.z > oz - SIZE / 2 and p.z < oz + SIZE / 2
	end
end

-- the engine's rays over boxes: a horizontal ray meets a box whose height range holds it; a vertical one a box whose
-- column it is in, never one it starts inside (the engine's ray meets nothing it starts in), and the ground at y 0
local function rays(boxes: { B3 }): (any, any)
	local function wall(ox: number, oy: number, oz: number, dx: number, _dy: number, dz: number): boolean
		for _, b in boxes do
			if oy >= b.minY and oy <= b.maxY then
				local flat: { TestWorld.Box } =
					{ { minX = b.minX, maxX = b.maxX, minZ = b.minZ, maxZ = b.maxZ, top = math.huge } }
				if TestWorld.segmentCrossesBox(flat, ox, oz, ox + dx, oz + dz, oy) then
					return true
				end
			end
		end
		return false
	end
	local function down(ox: number, oy: number, oz: number, _dx: number, dy: number, _dz: number): boolean
		local lo, hi = math.min(oy, oy + dy), math.max(oy, oy + dy)
		if oy >= 0 and lo <= 0 then
			return true
		end
		for _, b in boxes do
			if ox > b.minX and ox < b.maxX and oz > b.minZ and oz < b.maxZ then
				local startsIn = oy > b.minY and oy < b.maxY
				if not startsIn and lo <= b.maxY and hi >= b.minY then
					return true
				end
			end
		end
		return false
	end
	return wall, down
end

local function worlds(boxes: { B3 }, base: any?): (any, any)
	local world = base or TestWorld.build({})
	local wall, down = rays(boxes)
	-- (the client's motor with no walls: a client that ignores them)
	local noWalls: any = table.clone(world)
	noWalls.blocked, noWalls.blockedCore, noWalls.blockedHalf = nil, nil, nil
	return noWalls, ValidatorWorld.build(world, { wall = wall, down = down })
end

local function idle(_now: number): SquirrelMotor.Input
	return SquirrelMotor.idleInput(0)
end

return function(t)
	-- cover ------------------------------------------------------------------------------------------------------------
	for _, roof in { false, true } do
		t.test(
			`cover: one long packet into a closed {if roof then "ROOFED" else "open-topped"} room, a leap inside: the held place reaches it, the release and retake put the body inside`,
			function()
				local boxes = roomBoxes(0, 0, roof)
				local inside = insideOf(0, 0)
				local world, vworld = worlds(boxes)
				local g = world.groundHeight
				local outside: V3 = { x = -2.2, y = g, z = 0 }
				local into: V3 = { x = 6, y = g, z = 0 }
				local jumped, jumpedAt = false, math.huge
				local leapt = false
				local rig: any
				rig = LiveRig.new({
					world = world,
					vworld = vworld,
					link = { latency = 0.05, jitter = 0, loss = 0 },
					seed = 91,
					-- (a pause in the packets: the long line, 8.2 st, is one packet)
					silent = function(at: number): boolean
						return at >= 3 and at < 3.3
					end,
					cheat = function(state: State, _input: any, at: number, _w: any)
						if not jumped and at >= 3.28 then
							jumped, jumpedAt = true, at
							state.x, state.z = into.x, into.z
						end
					end,
					-- (the root the client writes stays outside, 8.2 st from the packets: drift's bound, then follows)
					rootCheat = function(p: V3, now: number, _s: State)
						if jumped and now < jumpedAt + 1.2 then
							p.x, p.y, p.z = outside.x, outside.y, outside.z
						end
					end,
				})
				-- (0.1 s after the long packet, one leap on the spot: an honest motor's arc, every packet of it clean)
				local yaw = 0
				local function keys(at: number, _s: State): SquirrelMotor.Input
					local i = SquirrelMotor.idleInput(yaw)
					if jumped and not leapt and at >= jumpedAt + 0.1 then
						leapt = true
						i.leap = true
					end
					return i
				end
				rig:possess(SquirrelMotor.new(outside.x, outside.y, outside.z), keys)
				rig:run(3)
				local before = rig:result().snaps
				local inHeld, firstIn = 0, nil :: number?
				for _ = 1, 30 do
					rig:run(0.05)
					local h = rig:place()
					if h and inside(h) then
						inHeld += 1
						firstIn = firstIn or rig.t
					end
				end
				local held = rig:place() :: V3
				-- a swap: Possession.releaseNow lets the body go at the held place; the same body taken back
				local rel = rig:release() :: V3
				rig:run(0.75)
				rig.server.count -= 1
				rig:possess(SquirrelMotor.new(rel.x, rel.y, rel.z), idle)
				rig:run(2)
				local where = rig:place() :: V3
				local r = rig:result()
				print(
					string.format(
						"      held place inside for %d of 30 samples (first %.2f s after the long packet); held %.1f, %.1f, %.1f; released at %.1f, %.1f (inside %s); after the retake %.1f, %.1f (inside %s), root %.1f, %.1f; snaps %d %s",
						inHeld,
						if firstIn then firstIn - jumpedAt else -1,
						held.x,
						held.y,
						held.z,
						rel.x,
						rel.z,
						tostring(inside(rel)),
						where.x,
						where.z,
						tostring(inside(where)),
						r.root.x,
						r.root.z,
						r.snaps - before,
						LiveRig.describe("", r)
					)
				)
				for _, v in r.violations do
					print("        " .. v)
				end
				t.eq(inHeld, 0, "the held place never inside a closed room")
				t.truthy(
					not inside(rel) and not inside(where),
					"a body outside a closed room is never let go inside it"
				)
			end
		)
	end
	-- rail -------------------------------------------------------------------------------------------------------------
	for _, viaGate in { false, true } do
		t.test(
			if viaGate
				then "rail (gate): on a trunk beside a closed room, snapped back onto it (any bad packet), the new epoch's first packet inside within 8.5 st of the trunk: passes the gate, held inside"
				else "rail: the held place on a trunk beside a closed room, one long packet through the wall, clean packets inside within 8.5 st of the trunk: held inside",
			function()
				local base = TestWorld.build({})
				-- (a trunk of the generated town near the middle, its foot on the ground)
				local trunk: any = nil
				for _, r in Driver.targetsAround(base, 0, 0, 400) do
					local foot = base.registry:foot(r)
					if math.abs(foot.y - base.groundHeight) < 1 then
						trunk = r
						break
					end
				end
				local foot = base.registry:foot(trunk)
				-- (the room's west wall 3 to 4 st east of the trunk's centreline)
				local ox, oz = foot.x + 4, foot.z
				local boxes = roomBoxes(ox, oz, true)
				local inside = insideOf(ox, oz)
				local world, vworld = worlds(boxes, base)
				local g = world.groundHeight
				local jumped = false
				local rootAt: V3? = nil
				local rig: any
				rig = LiveRig.new({
					world = world,
					vworld = vworld,
					link = { latency = 0.05, jitter = 0, loss = 0 },
					seed = 92,
					silent = function(at: number): boolean
						return at >= 4 and at < (if viaGate then 4.45 else 4.25)
					end,
					-- (gate: one packet 30 st off, a teleport: snapped back to the held place, the trunk, under a new epoch)
					packetCheat = function(snap: { [string]: any }, at: number): boolean?
						if viaGate and at >= 3.95 and at < 4 then
							snap.x += 30
						end
						return nil
					end,
					-- (off the trunk and 9 st east of it, inside, at the end of the pause: one long line through the wall;
					-- gate: 6 st east of it, the new epoch's first packet)
					cheat = function(state: State, _input: any, at: number, _w: any)
						if not jumped and at >= (if viaGate then 4.43 else 4.23) then
							jumped = true
							SquirrelMotor.place(state, foot.x + (if viaGate then 6 else 9), g, foot.z, true)
						end
					end,
					-- (the root stays where the trunk had it)
					rootCheat = function(p: V3, _now: number, _s: State)
						if not jumped then
							rootAt = { x = p.x, y = p.y, z = p.z }
						elseif rootAt then
							p.x, p.y, p.z = rootAt.x, rootAt.y, rootAt.z
						end
					end,
				})
				local west = BakedWorld.cameraYawToward(-1, 0)
				local onTrunkAt: any = nil
				local function keys(at: number, s: State): SquirrelMotor.Input
					if at < 4 then
						-- (onto the trunk: E within its grab)
						local i = SquirrelMotor.idleInput(west)
						i.grab = at > 1 and at < 1.05
						if s.routeId ~= nil and onTrunkAt == nil then
							onTrunkAt = { id = s.routeId, x = s.x, y = s.y, z = s.z }
						end
						return i
					end
					-- (inside: walk back west to within 7 st of the trunk, then stand)
					if s.x > foot.x + 7 then
						return BakedWorld.keys(west, { fw = 1 })
					end
					return SquirrelMotor.idleInput(west)
				end
				rig:possess(SquirrelMotor.new(foot.x - 2, g, foot.z), keys)
				rig:run(4)
				local before = rig:place() :: V3
				local beforeSnaps = rig:result().snaps
				local inHeld = 0
				for _ = 1, 30 do
					rig:run(0.05)
					local h = rig:place()
					if h and inside(h) then
						inHeld += 1
					end
				end
				local held = rig:place() :: V3
				local rel = rig:release() :: V3
				rig:run(0.75)
				rig.server.count -= 1
				rig:possess(SquirrelMotor.new(rel.x, rel.y, rel.z), idle)
				rig:run(2)
				local where = rig:place() :: V3
				local r = rig:result()
				print(
					string.format(
						"      trunk %s foot %.1f, %.1f; on it %s; held before %.1f, %.1f, %.1f; held place inside %d of 30 samples; held %.1f, %.1f, %.1f; released at %.1f, %.1f (inside %s); after the retake %.1f, %.1f (inside %s); snaps %d %s",
						tostring(trunk.id),
						foot.x,
						foot.z,
						if onTrunkAt then string.format("route %d at y %.1f", onTrunkAt.id, onTrunkAt.y) else "never",
						before.x,
						before.y,
						before.z,
						inHeld,
						held.x,
						held.y,
						held.z,
						rel.x,
						rel.z,
						tostring(inside(rel)),
						where.x,
						where.z,
						tostring(inside(where)),
						r.snaps - beforeSnaps,
						LiveRig.describe("", r)
					)
				)
				for _, v in r.violations do
					print("        " .. v)
				end
				t.truthy(onTrunkAt ~= nil, "the body was on the trunk")
				t.eq(inHeld, 0, "the held place never inside a closed room")
				t.truthy(
					not inside(rel) and not inside(where),
					"a body outside a closed room is never let go inside it"
				)
			end
		)
	end
	-- creep (the root) --------------------------------------------------------------------------------------------------
	t.test(
		"root creep: the root the client writes creeps through a closed room's wall at 0.5 st/s (0.033 st a watch sample) while clean packets stand outside, then the packets stop: never snapped",
		function()
			local boxes = roomBoxes(0, 0, true)
			local inside = insideOf(0, 0)
			local world, vworld = worlds(boxes)
			local g = world.groundHeight
			local x0 = -2.2
			local rig = LiveRig.new({
				world = world,
				vworld = vworld,
				link = { latency = 0.05, jitter = 0, loss = 0 },
				seed = 93,
				-- (no packets from 10 s on)
				silent = function(at: number): boolean
					return at >= 10
				end,
				rootCheat = function(p: V3, now: number, _s: State)
					p.x, p.y, p.z = math.min(2, x0 + math.max(0, now - 1) * 0.5), g, 0
				end,
			})
			rig:possess(SquirrelMotor.new(x0, g, 0), idle)
			rig:run(10)
			local r10 = rig:result()
			local root10 = r10.root
			rig:run(20)
			local r = rig:result()
			local held = rig:place() :: V3
			print(
				string.format(
					"      at 10 s (packets clean outside): root %.2f, %.2f (inside %s), snaps %d; at 30 s (20 s with no packet): root %.2f, %.2f (inside %s), held place %.1f, %.1f, snaps %d",
					root10.x,
					root10.z,
					tostring(inside(root10)),
					r10.snaps,
					r.root.x,
					r.root.z,
					tostring(inside(r.root)),
					held.x,
					held.z,
					r.snaps
				)
			)
			t.truthy(not inside(root10), "the root never creeps into a closed room unjudged")
			t.truthy(not inside(r.root), "nor stays there")
		end
	)

	-- silent -----------------------------------------------------------------------------------------------------------
	t.test(
		"silent: one doubtful packet into a closed room, then no packet at all: the doubt is never snapped back",
		function()
			local boxes = roomBoxes(0, 0, true)
			local inside = insideOf(0, 0)
			local world, vworld = worlds(boxes)
			local g = world.groundHeight
			local outside: V3 = { x = -3.4, y = g, z = 0 }
			local jumped = false
			local rig: any
			rig = LiveRig.new({
				world = world,
				vworld = vworld,
				link = { latency = 0.05, jitter = 0, loss = 0 },
				seed = 94,
				-- (a pause, one packet 8.1 st on through the wall, then nothing more)
				silent = function(at: number): boolean
					return (at >= 3 and at < 3.3) or at >= 3.4
				end,
				cheat = function(state: State, _input: any, at: number, _w: any)
					if not jumped and at >= 3.28 then
						jumped = true
						state.x, state.z = 4.7, 0
					end
				end,
				-- (the root against the wall's outer face from the pause on: 5.9 st from that packet, within SILENT_MOVE 6)
				rootCheat = function(p: V3, now: number, _s: State)
					if now >= 3 then
						p.x, p.y, p.z = -1.2, g, 0
					end
				end,
			})
			rig:possess(SquirrelMotor.new(outside.x, outside.y, outside.z), idle)
			rig:run(3)
			local before = rig:result().snaps
			rig:run(20)
			local r = rig:result()
			local shot = rig.movement:motorOf("squirrel_1") or { x = 0 / 0, y = 0 / 0, z = 0 / 0 }
			for _, v in r.violations do
				print("        " .. v)
			end
			print("        " .. LiveRig.describe("", r))
			local doubt = rig.movement.squirrels["squirrel_1"].doubtAt
			print(
				string.format(
					"      20 s after one doubtful packet and no more: snaps %d; the last accepted packet %.1f, %.1f (inside %s); doubt standing since %.1f s (%.1f s)",
					r.snaps - before,
					shot.x,
					shot.z,
					tostring(inside({ x = shot.x, y = shot.y, z = shot.z })),
					doubt or -1,
					if doubt then rig.t - doubt else -1
				)
			)
			t.truthy(doubt == nil, "a doubt never stands longer than DOUBT_SNAP (1 s), packets or none")
		end
	)
	-- silent, in the stream grace --------------------------------------------------------------------------------------
	t.test(
		"silent in the grace: handed the body 70 st from a closed room, sprint through its wall (graced, the root test off), stop sending: never snapped",
		function()
			local boxes = roomBoxes(0, 0, true)
			local inside = insideOf(0, 0)
			local world, vworld = worlds(boxes)
			local g = world.groundHeight
			local east = BakedWorld.cameraYawToward(1, 0)
			local inAt = math.huge
			local rig: any
			rig = LiveRig.new({
				world = world,
				vworld = vworld,
				link = { latency = 0.05, jitter = 0, loss = 0 },
				seed = 95,
				silent = function(at: number): boolean
					return at >= inAt + 0.15
				end,
			})
			local function keys(at: number, s: State): SquirrelMotor.Input
				if s.x < 4 then
					return BakedWorld.keys(east, { fw = 1, sprint = true })
				end
				inAt = math.min(inAt, at)
				return SquirrelMotor.idleInput(east)
			end
			rig:possess(SquirrelMotor.new(-70, g, 0), keys)
			rig:run(25)
			local r = rig:result()
			local sq = rig.movement.squirrels["squirrel_1"]
			local held = rig:place() :: V3
			print(
				string.format(
					"      inside %.2f s after the hand-off; 25 s on: root %.1f, %.1f (inside %s), held place %.1f, %.1f, doubt standing %.1f s; %s",
					inAt - 0,
					r.root.x,
					r.root.z,
					tostring(inside(r.root)),
					held.x,
					held.z,
					if sq.doubtAt then rig.t - sq.doubtAt else -1,
					LiveRig.describe("", r)
				)
			)
			t.truthy(not inside(r.root), "a body that went through a wall in the grace is put back, packets or none")
		end
	)

	-- slab drop (the baked town) ---------------------------------------------------------------------------------------
	t.test(
		"slab drop: off a rail over a house, the first packet off it already under the ceiling (a 0.48 to 0.6 s gap): never judged for the slab (needs build/Town.rbxm)",
		function()
			if not fs.isFile("build/Town.rbxm") then
				t.truthy(false, "build/Town.rbxm (lune run tools/bake/main.luau)")
				return
			end
			Height.configure(Data.default():module("TerrainExtensions"))
			local town = BakedWorld.load("build/Town.rbxm")
			local w = town:motorWorld(Data.default())
			local reg = w.registry
			local function solid(p: any): boolean
				local parentName = string.match(p.path, "([^%.]+)%.[^%.]+$") or ""
				return p.squirrelSolid and not ValidatorWorld.isBough(p.name, parentName)
			end
			-- every rail sample with a slab (a roof, a ceiling) within 10 st under it and a closed storey under that
			local drops = {}
			for _, r in reg:all() do
				local n = math.clamp(math.floor((r.length or 50) / 2), 2, 400)
				for k = 0, n do
					local p = reg:pointAt(r, k / n)
					local tt, part = town.raycast(p.x, p.y - 0.3, p.z, 0, -10, 0, solid)
					if tt and part then
						local top = p.y - 0.3 - 10 * tt
						local under = part.y0 - 0.05
						local t2, floor = town.raycast(p.x, under, p.z, 0, -40, 0, solid)
						local fy = if t2 then under - 40 * t2 else town.terrainAt(p.x, p.z)
						if under - fy >= 2.5 and top - under < 3 and floor then
							local closed = true
							for _, d in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
								if town.raycast(p.x, fy + 1.1, p.z, d[1] * 30, 0, d[2] * 30, solid) == nil then
									closed = false
								end
							end
							if closed then
								table.insert(
									drops,
									{ r = r, t = k / n, p = p, under = under, fy = fy, path = part.path }
								)
							end
						end
					end
				end
			end
			local wall, down, cover = BakedWorld.validatorRays(town)
			local vworld = ValidatorWorld.build(w, { wall = wall, down = down, cover = cover })
			local held, total = 0, 0
			local where: { [string]: number } = {}
			for _, d in drops do
				for _, tau in { 0.48, 0.6 } do
					total += 1
					local p = d.p
					local ms = MovementService.new({
						validator = MoveValidator.new(vworld),
						enforce = true,
						poseOf = function(_a: any): (number, number, number)
							return p.x, p.y, p.z
						end,
						engine = {
							correct = function() end,
							pin = function(): boolean
								return true
							end,
							hold = function() end,
						},
					})
					ms:onHandoff({ id = "a", species = "squirrel" }, nil, "possess")
					local epoch = ms:epochOf("a")
					local seq, now = 0, 100
					local function send(st: any, dt: number)
						seq += 1
						now += dt
						st.clock = now - 90
						local _, e, dec =
							SquirrelWire.decode(SquirrelWire.encode(seq, epoch, SquirrelMotor.serialize(st)))
						ms:packet("a", "squirrel", { seq = seq, epoch = e, snapshot = dec }, now)
						ms:watch("a", st.x, st.y, st.z, now)
						epoch = ms:epochOf("a")
					end
					-- on the rail, then a drop (Q) with the packets held back: the first off it tau later, then the fall
					for _ = 1, 15 do
						local st = SquirrelMotor.new(p.x, p.y, p.z)
						st.routeId, st.railT, st.grounded = d.r.id, d.t, false
						send(st, 1 / 30)
					end
					local y1 = p.y - 0.5 * 75 * tau * tau
					local st = SquirrelMotor.new(p.x, math.max(y1, d.fy), p.z)
					st.grounded, st.vy = y1 <= d.fy, if y1 <= d.fy then 0 else -75 * tau
					send(st, tau)
					local yy, vy = st.y, st.vy
					while yy > d.fy do
						vy -= 75 / 30
						yy = math.max(d.fy, yy + vy / 30)
						local s2 = SquirrelMotor.new(p.x, yy, p.z)
						s2.grounded = yy <= d.fy
						s2.vy = if s2.grounded then 0 else vy
						send(s2, 1 / 30)
					end
					for _ = 1, 20 do
						send(SquirrelMotor.new(p.x, d.fy, p.z), 1 / 30)
					end
					local _, hy = ms:heldPlace("a")
					if hy ~= nil and hy < d.under - 1 then
						held += 1
						local key = `{d.r.kind} {d.r.id} over {d.path}`
						where[key] = (where[key] or 0) + 1
					end
				end
			end
			for k, v in where do
				print(`      {k}: held inside the storey under it after {v} drops`)
			end
			print(`      {held} of {total} drops off a rail over a closed storey held inside it`)
			t.eq(held, 0, "a drop off a rail through a roof or a ceiling is judged")
		end
	)
end
