--!strict
-- Validator round 10 (the round-9 review, scratchpad review_validator_r9.md; its failing cases are validator_r9rv): the
-- greedy attack cases for each change, driven straight at MoveValidator and MovementService (and the rig where the
-- root is the attack). Each sweeps what a client controls; each must find no way in.
--   reach        MoveValidator.reachable from outside a closed room (roofed and open-topped) to inside it: every
--                held place on the ground outside 0.5 to 8 st off a wall (and on a trunk's rail 3 to 4 st off it),
--                every packet inside 0.5 to 14 st in and from the floor to a leap's apex over it, through the walls and
--                across the corners: never reachable (the round-9 review's MEDIUM 1 a, b, c)
--   gate         a gate on a trunk's rail beside a closed room, the first packet inside within ROUTE_NEAR of the trunk:
--                every one a whole wall flag (MEDIUM 1 c through a snap's gate)
--   chain        invariant E's chain (a gap, or a wall third a way round a corner explains, judged from the held place:
--                the clean packets after it are held): a gap into a closed room at every length and side is never
--                chained, and its clean packets inside never held
--   rail slab    drops off every rail over a closed storey in the baked town, the first packet 0.2 to 0.8 s on and up to
--                2 st aside; a body inside the storey onto the rail over it: every one judged (MEDIUM 2); an honest Q off
--                a sample of every route with its packets held back: no slab flag
--   silence      a doubt of each kind (a long line, a resync, a grace), then nothing, or packets only under a stale
--                epoch: snapped back within DOUBT_SNAP + DOUBT_QUIET (LOW-MEDIUM 3)
--   root creep   the root written through a closed room's wall at 0.1 to 1.5 st/s, 15 samples a second, and kept
--                inside after each snap: never more than a moment inside (LOW-MEDIUM 4)
--   face         a packet on a wall's face, then a chord in, with rays that meet nothing from an origin on a face: flagged
--                (LOW 5: every chord starts CHORD_BACK behind)
--   oblique      straight runs through a 1-st wall at every angle, step and phase, with the engine's rays (nothing from
--                inside a part): every one flagged (found by this round: the wall anchor's centre line)
--   meter        an endless sprint hidden in gaps (one packet every 0.55 to 1.0 s): snapped for the meter or the gaps
-- About 20 s (`lune run tests/run.luau validator_r10`); the rail slab cases need build/Town.rbxm (bake first).
local fs = require("@lune/fs")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local SquirrelWire = require("@shared/Movement/SquirrelWire")
local BakedWorld = require("@tests/lib/BakedWorld")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local MoveValidator = require("@server/Movement/MoveValidator")
local MovementService = require("@server/Movement/MovementService")
local TestWorld = require("@tests/cheat/TestWorld")
local Driver = require("@tests/cheat/Driver")
local LiveRig = require("@tests/lib/LiveRig")
local Height = require("@shared/World/Height")
local Data = require("@shared/Data")

type State = SquirrelMotor.State
type V3 = { x: number, y: number, z: number }
type B3 = { minX: number, maxX: number, minY: number, maxY: number, minZ: number, maxZ: number }

-- a closed room 60 x 60 st (walls 1 st thick, 0 to 14 high) at (ox, oz) (x ox..ox+60, z oz-30..oz+30), no door;
-- `roof`: a slab 0.6 thick over it (14 to 14.6)
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

-- the engine's rays over boxes (as validator_r9rv): a horizontal ray meets a box whose height range holds it, never one
-- its origin is on or inside (`face`: as the engine may treat an origin on a face); a vertical one a box whose column it
-- is in, never one it starts inside; the ground at y 0. `count` adds the rays cast
local function rays(boxes: { B3 }, face: boolean?, count: { n: number }?): (any, any)
	local function wall(ox: number, oy: number, oz: number, dx: number, _dy: number, dz: number): boolean
		if count then
			count.n += 1
		end
		for _, b in boxes do
			if oy >= b.minY and oy <= b.maxY then
				local onOrIn = ox >= b.minX and ox <= b.maxX and oz >= b.minZ and oz <= b.maxZ
				if not (face and onOrIn) then
					local flat: { TestWorld.Box } =
						{ { minX = b.minX, maxX = b.maxX, minZ = b.minZ, maxZ = b.maxZ, top = math.huge } }
					if TestWorld.segmentCrossesBox(flat, ox, oz, ox + dx, oz + dz, oy) then
						return true
					end
				end
			end
		end
		return false
	end
	local function down(ox: number, oy: number, oz: number, _dx: number, dy: number, _dz: number): boolean
		if count then
			count.n += 1
		end
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

local function worlds(boxes: { B3 }, base: any?, face: boolean?, count: { n: number }?): (any, any)
	local world = base or TestWorld.build({})
	local wall, down = rays(boxes, face, count)
	local noWalls: any = table.clone(world)
	noWalls.blocked, noWalls.blockedCore, noWalls.blockedHalf = nil, nil, nil
	return noWalls, ValidatorWorld.build(world, { wall = wall, down = down })
end

-- one squirrel straight on a MovementService (enforcing; the engine's hands recorded): send(state, dt) and watch
local function service(vworld: any, at: V3)
	local snaps: { string } = {}
	local ms = MovementService.new({
		validator = MoveValidator.new(vworld),
		enforce = true,
		poseOf = function(_a: any): (number, number, number)
			return at.x, at.y, at.z
		end,
		engine = {
			correct = function(_id: any, msg: any)
				if msg.snap then
					table.insert(snaps, msg.why)
				end
			end,
			pin = function(): boolean
				return true
			end,
			hold = function() end,
		},
	})
	ms:onHandoff({ id = "a", species = "squirrel" }, nil, "possess")
	local seq, now = 0, 100
	local function send(st: State, dt: number, epoch: number?): any
		seq += 1
		now += dt
		st.clock = now - 90
		local _, e, dec =
			SquirrelWire.decode(SquirrelWire.encode(seq, epoch or ms:epochOf("a"), SquirrelMotor.serialize(st)))
		local v = ms:packet("a", "squirrel", { seq = seq, epoch = e, snapshot = dec }, now)
		return v
	end
	local function watch(x: number, y: number, z: number, dt: number?)
		now += dt or 0
		ms:watch("a", x, y, z, now)
	end
	return {
		ms = ms,
		send = send,
		watch = watch,
		snaps = snaps,
		now = function(): number
			return now
		end,
		pass = function(dt: number)
			now += dt
		end,
	}
end

return function(t)
	-- reach -------------------------------------------------------------------------------------------------------------
	t.test(
		"reach: from the ground outside a closed room (roofed, open-topped) to anywhere inside, through a wall or across a corner: never reachable",
		function()
			local tried, reached, worstRays = 0, 0, 0
			local examples = {}
			for _, roof in { true, false } do
				local count = { n = 0 }
				local _, vworld = worlds(roomBoxes(0, 0, roof), nil, false, count)
				local v = MoveValidator.new(vworld)
				local inside = insideOf(0, 0)
				local leap = MoveValidator.leapRise()
				-- (outside: off the west wall, and off the south-west corner on both sides of it)
				local froms: { V3 } = {}
				for _, off in { 0.5, 1.2, 2.5, 4, 8 } do
					for _, z in { 0, 20, 28.5 } do
						table.insert(froms, { x = -1 - off, y = 0, z = z })
					end
					table.insert(froms, { x = -1 - off, y = 0, z = -31 - off })
					table.insert(froms, { x = 3, y = 0, z = -31 - off })
				end
				for _, from in froms do
					for _, depth in { 0.5, 2, 5, 9, 14 } do
						for _, along in { -6, 0, 6 } do
							for _, y in { 0, 2, 4.7, leap * 0.8, leap } do
								local next = SquirrelMotor.new(depth, y, math.clamp(from.z + along, -29.5, 29.5))
								next.grounded = y == 0
								if from.z < -30 then
									-- (across the corner: inside past the south wall)
									next.x, next.z = math.clamp(from.x + depth + 2, 0.5, 59.5), -30 + depth
								end
								if inside(next) then
									tried += 1
									count.n = 0
									if v:reachable(from :: any, next, 60) then
										reached += 1
										if #examples < 5 then
											table.insert(
												examples,
												`{if roof then "roofed" else "open"}: {from.x}, {from.z} -> {next.x}, {next.y}, {next.z}`
											)
										end
									end
									worstRays = math.max(worstRays, count.n)
								end
							end
						end
					end
				end
			end
			print(`      {tried} lines into a closed room: {reached} reachable; at most {worstRays} rays a call`)
			for _, e in examples do
				print(`        {e}`)
			end
			t.eq(reached, 0, "no line into a closed room is reachable")
		end
	)

	-- the rail rule: a held place on a trunk 3 to 4 st off a closed room ---------------------------------------------------
	local function trunkRoom(gap: number): (any, any, any, any, (p: V3) -> boolean)
		local base = TestWorld.build({})
		local trunk: any = nil
		for _, r in Driver.targetsAround(base, 0, 0, 400) do
			local foot = base.registry:foot(r)
			if math.abs(foot.y - base.groundHeight) < 1 then
				trunk = r
				break
			end
		end
		local foot = base.registry:foot(trunk)
		local ox, oz = foot.x + gap, foot.z
		local world, vworld = worlds(roomBoxes(ox, oz, true), base)
		return world, vworld, trunk, foot, insideOf(ox, oz)
	end

	t.test(
		"reach from a rail: the held place on a trunk 3 to 4 st from a closed room, a clean packet inside within ROUTE_NEAR: never reachable",
		function()
			local tried, reached = 0, 0
			for _, gap in { 3, 3.5, 4 } do
				local world, vworld, trunk, foot, inside = trunkRoom(gap)
				local v = MoveValidator.new(vworld)
				for _, tt in { 0, 0.02, 0.05, 0.1 } do
					local p = world.registry:pointAt(trunk, tt)
					local from = { x = p.x, y = p.y, z = p.z, routeId = trunk.id }
					for _, dx in { gap + 0.6, gap + 2, gap + 4, gap + 5.5 } do
						for _, dz in { -3, 0, 3 } do
							local next = SquirrelMotor.new(foot.x + dx, world.groundHeight, foot.z + dz)
							if inside(next) then
								tried += 1
								if v:reachable(from, next) then
									reached += 1
								end
							end
						end
					end
				end
			end
			print(`      {tried} lines off a trunk into a closed room: {reached} reachable`)
			t.truthy(tried > 50, "lines tried")
			t.eq(reached, 0, "no line off a rail into a closed room is reachable")
		end
	)

	t.test(
		"gate: a gate on a trunk beside a closed room (the snap's target claims the trunk), every first packet inside within ROUTE_NEAR: a whole wall flag",
		function()
			local tried, passed = 0, 0
			for _, gap in { 3, 3.5, 4 } do
				local world, vworld, trunk, foot, inside = trunkRoom(gap)
				local v = MoveValidator.new(vworld)
				for _, tt in { 0.02, 0.05 } do
					local p = world.registry:pointAt(trunk, tt)
					local from = { x = p.x, y = p.y, z = p.z, routeId = trunk.id }
					for _, dx in { gap + 0.6, gap + 2, gap + 4, gap + 5.5 } do
						for _, dz in { -3, 0, 3 } do
							for _, span in { 0.1, 0.4, 0.7 } do
								local next = SquirrelMotor.new(foot.x + dx, world.groundHeight, foot.z + dz)
								if inside(next) then
									tried += 1
									local whole = false
									for _, x in (v:hop("a", from, next, span, 100, true)) do
										whole = whole or (x.code == "wall" and x.severity >= 1)
									end
									if not whole then
										passed += 1
									end
								end
							end
						end
					end
				end
			end
			print(`      {tried} gates off a trunk into a closed room: {passed} without a whole wall flag`)
			t.truthy(tried > 50, "gates tried")
			t.eq(passed, 0, "every one is a whole wall flag")
		end
	)

	-- chain -----------------------------------------------------------------------------------------------------------
	t.test(
		"chain: a gap into a closed room at every length (0.55 to 1.2 s, 4 to 45 st) and side, then clean packets inside: never chained, never held",
		function()
			local tried, held, chained = 0, 0, 0
			for _, roof in { true, false } do
				local world, vworld = worlds(roomBoxes(0, 0, roof))
				local inside = insideOf(0, 0)
				local g = world.groundHeight
				for _, dt in { 0.55, 0.8, 1.2 } do
					for _, into in { 2, 6, 15, 30 } do
						for _, z in { -24, 0, 24 } do
							for _, offAxis in { 0, 1 } do
								tried += 1
								local at = { x = -6 - 10 * offAxis, y = g, z = z - 12 * offAxis }
								local r = service(vworld, at)
								-- (standing outside, clean, then one packet inside after a gap, then clean packets inside)
								for _ = 1, 20 do
									r.send(SquirrelMotor.new(at.x, at.y, at.z), 0.05)
									r.watch(at.x, at.y, at.z)
								end
								local s = SquirrelMotor.new(into, g, z)
								r.send(s, dt)
								local sq = r.ms.squirrels.a
								if sq.chain then
									chained += 1
								end
								for _ = 1, 30 do
									r.send(SquirrelMotor.new(into, g, z), 0.05)
									r.watch(at.x, at.y, at.z)
									local hx, hy, hz = r.ms:heldPlace("a")
									if hx and inside({ x = hx, y = hy :: number, z = hz :: number }) then
										held += 1
										break
									end
								end
							end
						end
					end
				end
			end
			print(`      {tried} gaps into a closed room: {chained} chained, {held} held inside`)
			t.eq(chained, 0, "no gap into a closed room is chained")
			t.eq(held, 0, "the held place never inside")
		end
	)

	-- rail slab (the baked town) ------------------------------------------------------------------------------------------
	local town: any, bw: any, bvworld: any
	local function baked(): boolean
		if town then
			return true
		end
		if not fs.isFile("build/Town.rbxm") then
			return false
		end
		Height.configure(Data.default():module("TerrainExtensions"))
		town = BakedWorld.load("build/Town.rbxm")
		bw = town:motorWorld(Data.default())
		local wall, down, cover = BakedWorld.validatorRays(town)
		bvworld = ValidatorWorld.build(bw, { wall = wall, down = down, cover = cover })
		return true
	end

	t.test(
		"rail slab: off every rail over a closed storey, the first packet off it 0.2 to 0.8 s on and 0 to 2 st aside, and back onto it from inside: every one judged (needs build/Town.rbxm)",
		function()
			if not baked() then
				t.truthy(false, "build/Town.rbxm (lune run tools/bake/main.luau)")
				return
			end
			local reg = bw.registry
			local function solid(p: any): boolean
				local parentName = string.match(p.path, "([^%.]+)%.[^%.]+$") or ""
				return p.squirrelSolid and not ValidatorWorld.isBough(p.name, parentName)
			end
			-- every rail sample with a slab within 10 st under it and a closed storey under that (validator_r9rv's)
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
								table.insert(drops, { r = r, t = k / n, p = p, under = under, fy = fy })
							end
						end
					end
				end
			end
			local judged, total, upJudged, upTotal = 0, 0, 0, 0
			local missed: { string } = {}
			for _, d in drops do
				local p = d.p
				for _, tau in { 0.2, 0.35, 0.5, 0.65, 0.8 } do
					for _, aside in { 0, 1, 2 } do
						-- (the first packet off the rail tau later, under the slab: falling, or on the storey's floor)
						local y1 = math.max(d.fy, p.y - 0.5 * 75 * tau * tau)
						-- (only where the end's own column has the slab over it: 2 st aside may be past the ceiling's edge)
						local over = town.raycast(p.x + aside, y1 + 0.6, p.z, 0, d.under - y1 - 0.4, 0, solid) ~= nil
						if y1 < d.under - 1 and over then
							total += 1
							local v = MoveValidator.new(bvworld)
							local on = SquirrelMotor.new(p.x, p.y, p.z)
							on.routeId, on.railT, on.grounded, on.clock = d.r.id, d.t, false, 1
							v:reset("a", SquirrelMotor.serialize(on), 1)
							local off = SquirrelMotor.new(p.x + aside, y1, p.z)
							off.grounded, off.vy = y1 <= d.fy, if y1 <= d.fy then 0 else -75 * tau
							off.clock = 1 + tau
							local r = v:accept("a", { seq = 1, snapshot = SquirrelMotor.serialize(off) }, 1 + tau)
							local hit = false
							for _, x in r.violations do
								hit = hit or (x.code == "slab" and x.severity >= 1)
							end
							if hit then
								judged += 1
							elseif #missed < 6 then
								local codes = {}
								for _, x in r.violations do
									table.insert(codes, x.code)
								end
								table.insert(
									missed,
									`{d.r.kind} {d.r.id} t {string.format("%.2f", d.t)}: {tau} s, {aside} st aside, to y {string.format(
										"%.1f",
										y1
									)} (rail {string.format("%.1f", p.y)}, slab under {string.format(
										"%.1f",
										d.under
									)}, floor {string.format("%.1f", d.fy)}): [{table.concat(codes, ", ")}]`
								)
							end
						end
					end
				end
				-- back up: from the storey's floor under the slab onto the rail over it
				for _, tau in { 0.3, 0.6 } do
					upTotal += 1
					local v = MoveValidator.new(bvworld)
					local from = SquirrelMotor.new(p.x, d.fy, p.z)
					from.clock = 1
					v:reset("a", SquirrelMotor.serialize(from), 1)
					local on = SquirrelMotor.new(p.x, p.y, p.z)
					on.routeId, on.railT, on.grounded, on.clock = d.r.id, d.t, false, 1 + tau
					local r = v:accept("a", { seq = 1, snapshot = SquirrelMotor.serialize(on) }, 1 + tau)
					local hit = false
					for _, x in r.violations do
						hit = hit or x.code == "slab"
					end
					if hit then
						upJudged += 1
					end
				end
			end
			print(
				`      {#drops} rail samples over a closed storey: {judged} of {total} drops through the slab judged; {upJudged} of {upTotal} climbs onto the rail from inside`
			)
			for _, m in missed do
				print(`        missed: {m}`)
			end
			t.truthy(total > 100, "drops tried")
			t.eq(judged, total, "every drop through a slab off a rail is judged")
			t.eq(upJudged, upTotal, "every climb from under a slab onto the rail over it is judged")
		end
	)

	t.test(
		"rail slab, honest: Q off every fourth route of the baked town (trunks too), the packets after the drop held back 0, 0.3 or 0.5 s: no slab flag (needs build/Town.rbxm)",
		function()
			if not baked() then
				t.truthy(false, "build/Town.rbxm (lune run tools/bake/main.luau)")
				return
			end
			local routes = {}
			for _, r in bw.registry:all() do
				if not r.enclosure then
					table.insert(routes, r)
				end
			end
			table.sort(routes, function(a: any, b: any): boolean
				return a.id < b.id
			end)
			local drops, flagged = 0, 0
			local examples = {}
			for i = 1, #routes, 4 do
				local r = routes[i]
				for _, at in { 0.3, 0.7 } do
					for _, hold in { 0, 0.3, 0.5 } do
						drops += 1
						local q = bw.registry:pointAt(r, at)
						local s = SquirrelMotor.new(q.x, q.y, q.z)
						s.grounded = false
						s.routeId, s.railT, s.railDir = r.id, at, 1
						s.clock = 1
						local v = MoveValidator.new(bvworld)
						v:accept("a", { seq = 0, snapshot = SquirrelMotor.serialize(s) }, 1)
						local seq, bad = 0, false
						local yaw = (r.id * 0.618) % 1 * 2 * math.pi
						for frame = 1, 120 do
							local now = frame / 60
							SquirrelMotor.step(
								s,
								BakedWorld.keys(yaw, { drop = now < 0.1, fw = if now > 1.2 then 1 else 0 }),
								1 / 60,
								bw
							)
							s.clock = 1 + now
							if frame % 3 == 0 and (now < 0.06 or now > hold) then
								seq += 1
								local res = v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(s) }, 1 + now)
								for _, x in res.violations do
									if x.code == "slab" and not bad then
										bad = true
										if #examples < 5 then
											table.insert(examples, `{r.kind} {r.id} at {at}, held {hold}: {x.detail}`)
										end
									end
								end
							end
						end
						if bad then
							flagged += 1
						end
					end
				end
			end
			print(`      {drops} honest drops: {flagged} with a slab flag`)
			for _, e in examples do
				print(`        {e}`)
			end
			-- (one known pre-existing case, both ends off the rails: trunk 1210 at 0.8, a 0.27 st step down a flare)
			t.truthy(flagged <= 1, `honest drops flagged for a slab ({flagged})`)
		end
	)

	-- silence -----------------------------------------------------------------------------------------------------------
	t.test(
		"silence: a doubt of each kind, then no packet, or packets only under a stale epoch: snapped back within DOUBT_SNAP + DOUBT_QUIET",
		function()
			local C = MovementService.C
			local _, vworld = worlds(roomBoxes(0, 0, true))
			local cases, inTime = 0, 0
			local lines = {}
			for _, kind in { "into the room", "two doubts" } do
				for _, after in { "nothing", "stale epoch" } do
					cases += 1
					local at = { x = -5, y = 0, z = 20 }
					local r = service(vworld, at)
					for _ = 1, 20 do
						r.send(SquirrelMotor.new(at.x, at.y, at.z), 0.05)
						r.watch(at.x, at.y, at.z)
					end
					local epoch = r.ms:epochOf("a")
					if kind == "into the room" then
						-- (a 0.3 s line 9.7 st through the wall)
						r.send(SquirrelMotor.new(4.7, 0, 20), 0.3)
					else
						-- (a gap along the wall outside, a doubt the chain reaches; then a second gap from that doubtful
						-- place: the chain broken, the doubt standing)
						r.send(SquirrelMotor.new(-5, 0, 29), 0.6)
						r.send(SquirrelMotor.new(-5, 0, 20), 0.6)
					end
					local doubtAt = r.ms.squirrels.a.doubtAt
					local snappedAt: number? = nil
					for _ = 1, 60 do
						r.watch(-1.2, 0, 20, 1 / 15)
						if after == "stale epoch" then
							r.send(SquirrelMotor.new(4.7, 0, 20), 0, epoch - 1)
						end
						if #r.snaps > 0 and snappedAt == nil then
							snappedAt = r.now()
						end
					end
					-- (snapped for the packet itself, before any doubt stood: at once)
					local took = if snappedAt and doubtAt
						then snappedAt - doubtAt
						elseif snappedAt and #r.snaps > 0 and r.snaps[1] ~= "unreached" then 0
						else math.huge
					if took <= C.DOUBT_SNAP + C.DOUBT_QUIET + 0.1 then
						inTime += 1
					end
					table.insert(
						lines,
						`{kind}, then {after}: doubt {if doubtAt then "standing" else "none"}, snapped after {took} s ({table.concat(
							r.snaps,
							", "
						)})`
					)
				end
			end
			for _, l in lines do
				print(`      {l}`)
			end
			t.eq(inTime, cases, "every doubt snapped back in time")
		end
	)

	-- root creep (the rig) --------------------------------------------------------------------------------------------------
	t.test(
		"root creep: the root written through a closed room's wall at 0.1 to 1.5 st/s and kept inside after each snap: inside at most a moment",
		function()
			local worst, total = 0, 0
			for _, speed in { 0.1, 0.5, 1.5 } do
				for _, packets in { true, false } do
					local boxes = roomBoxes(0, 0, true)
					local inside = insideOf(0, 0)
					local world, vworld = worlds(boxes)
					local g = world.groundHeight
					local x0 = -2.2
					local rig = LiveRig.new({
						world = world,
						vworld = vworld,
						link = { latency = 0.05, jitter = 0, loss = 0 },
						seed = 101,
						silent = function(at: number): boolean
							return not packets and at >= 4
						end,
						rootCheat = function(p: V3, now: number, _s: State)
							p.x, p.y, p.z = math.min(3, x0 + math.max(0, now - 1) * speed), g, 0
						end,
					})
					rig:possess(SquirrelMotor.new(x0, g, 0), function(_now: number, _s: State): SquirrelMotor.Input
						return SquirrelMotor.idleInput(0)
					end)
					local insideSamples, samples = 0, 0
					for _ = 1, 400 do
						rig:run(0.05)
						if rig.t > 1 + (2 / speed) then
							samples += 1
							if inside(rig:result().root) then
								insideSamples += 1
							end
						end
					end
					local share = if samples > 0 then insideSamples / samples else 0
					worst = math.max(worst, share)
					total += 1
					print(
						`      {speed} st/s, packets {packets}: the root inside {insideSamples} of {samples} samples once through; {LiveRig.describe(
							"",
							rig:result()
						)}`
					)
				end
			end
			t.truthy(worst <= 0.25, `the root inside at most a quarter of the time ({worst})`)
		end
	)

	-- face --------------------------------------------------------------------------------------------------------------
	t.test(
		"face: a packet on a wall's face (and 1e-13 to 1e-2 off it), then a chord in, with rays that meet nothing from an origin on a face: flagged",
		function()
			local world, vworld = worlds(roomBoxes(0, 0, true), nil, true)
			local g = world.groundHeight
			local flagged, tried = 0, 0
			for _, d in { 0, 1e-13, 1e-6, 1e-2 } do
				for _, step in { 0.3, 1, 2 } do
					tried += 1
					local v = MoveValidator.new(vworld)
					local a = SquirrelMotor.new(-1 - d, g, 0)
					a.clock = 1
					v:reset("a", SquirrelMotor.serialize(a), 1)
					local b = SquirrelMotor.new(-1 - d + step, g, 0)
					b.clock = 1.05
					local r = v:accept("a", { seq = 1, snapshot = SquirrelMotor.serialize(b) }, 1.05)
					local hit = false
					for _, x in r.violations do
						hit = hit or x.code == "wall"
					end
					if hit then
						flagged += 1
					end
				end
			end
			print(`      {flagged} of {tried} chords in from a wall's face flagged`)
			t.eq(flagged, tried, "every chord in from a face is a wall")
		end
	)

	-- oblique (found by this round's sweeps) ------------------------------------------------------------------------------
	-- A move whose side ray alone missed a wall is no crossing for the lenient test (a corner rounded unseen); a packet a
	-- little way into a wall obliquely was such a move, and every ray of the next move started inside the wall, where the
	-- engine's ray meets nothing: before round 10, 142 of these 180 straight runs through a 1-st wall were never flagged
	-- with the engine's rays (39 with the test worlds' rays, which meet a part they start inside)
	t.test(
		"oblique: straight through a 1-st wall at 0 to 80 degrees, 0.4 to 1.2 st a packet, every phase, with the engine's rays and the test worlds': every run flagged",
		function()
			local unflagged = { [false] = 0, [true] = 0 }
			local tried = 0
			for _, engine in { false, true } do
				local wallBox = { minX = -1, maxX = 0, minZ = -300, maxZ = 300 }
				local function wall(ox: number, oy: number, oz: number, dx: number, _dy: number, dz: number): boolean
					if oy < 0 or oy > 14 then
						return false
					end
					if
						engine
						and ox >= wallBox.minX
						and ox <= wallBox.maxX
						and oz >= wallBox.minZ
						and oz <= wallBox.maxZ
					then
						return false -- (the engine's ray meets nothing of a part it starts inside)
					end
					local flat: { TestWorld.Box } = {
						{
							minX = wallBox.minX,
							maxX = wallBox.maxX,
							minZ = wallBox.minZ,
							maxZ = wallBox.maxZ,
							top = math.huge,
						},
					}
					return TestWorld.segmentCrossesBox(flat, ox, oz, ox + dx, oz + dz, oy)
				end
				local function down(_ox: number, oy: number, _oz: number, _dx: number, dy: number, _dz: number): boolean
					return oy + dy <= 0 and oy >= 0
				end
				local w = TestWorld.build({})
				local vw = ValidatorWorld.build(w, { wall = wall, down = down })
				local g = w.groundHeight
				for _, ang in { 0, 30, 45, 60, 70, 80 } do
					for phase = 0, 9 do
						for _, step in { 0.4, 0.8, 1.2 } do
							tried += 1
							local v = MoveValidator.new(vw)
							local ux, uz = math.cos(math.rad(ang)), math.sin(math.rad(ang))
							local x, z = -3 + phase * step / 10, 0
							local a = SquirrelMotor.new(x, g, z)
							a.clock = 1
							v:reset("a", SquirrelMotor.serialize(a), 1)
							local clock, bad, seq = 1, false, 0
							while x < 2 do
								x, z = x + ux * step, z + uz * step
								clock += 0.05
								seq += 1
								local s = SquirrelMotor.new(x, g, z)
								s.clock = clock
								s.vx, s.vz = ux * step / 0.05, uz * step / 0.05
								local r = v:accept("a", { seq = seq, snapshot = SquirrelMotor.serialize(s) }, clock)
								bad = bad or #r.violations > 0
							end
							if not bad then
								unflagged[engine] += 1
							end
						end
					end
				end
			end
			print(
				`      {tried} runs through a 1-st wall: unflagged {unflagged[true]} with the engine's rays, {unflagged[false]} with the test worlds'`
			)
			t.eq(unflagged[true] + unflagged[false], 0, "every run through the wall flagged")
		end
	)

	-- meter -------------------------------------------------------------------------------------------------------------
	t.test(
		"meter: an endless sprint hidden in gaps (one packet every 0.55 to 1.0 s, the rest lost): snapped for the meter or the gaps",
		function()
			local _, vworld = worlds({})
			local caught = 0
			local rows = {}
			for _, every in { 0.55, 0.7, 1.0 } do
				local at = { x = 0, y = 0, z = -200 }
				local r = service(vworld, at)
				local x = at.x
				for _ = 1, 10 do
					r.send(SquirrelMotor.new(x, 0, at.z), 0.05)
					r.watch(x, 0, at.z)
				end
				local speed = SquirrelMotor.params.sprint
				for _ = 1, math.floor(30 / every) do
					x += speed * every
					local s = SquirrelMotor.new(x, 0, at.z)
					s.vx = speed
					r.send(s, every)
					r.watch(x, 0, at.z)
					if #r.snaps > 0 then
						break
					end
				end
				if #r.snaps > 0 then
					caught += 1
				end
				table.insert(rows, `every {every} s: {table.concat(r.snaps, ", ")}`)
			end
			for _, row in rows do
				print(`      {row}`)
			end
			t.eq(caught, 3, "every endless sprint in gaps is snapped")
		end
	)
end
