--!strict
-- The bowling alley's roof run, its data (BRIEF_ADDENDUM D9, D10; Shared/Attractions/AlleyRoof):
--   * the routes are well formed, their ids clear of the alley's own (9001-9018) and of the harvest, every flag
--     explicit, every point in the alley's footprint or the yard annex, none on a venue's site, the backstage
--     reserve or lounge one, and no other route of the town near enough to be grabbed by mistake;
--   * the joints the motor's end-of-route switch needs (Motion.C.autoSwitchGap), the bough across the ridge's line
--     with a 3-st stub past the catch, through the trunk's top and drooping over the parapet to end just over the
--     roof, the vent's run inside the duct boxes and off the platform's grating (the apron in front of the louvre);
--   * the vent's enclosure record: checked by Shared/Routes/Enclosure (the enclosed-run contract) when that module
--     is in the tree, else by the same rules written out here;
--   * THE CHAIN WITH THE REAL MOTOR: Movement/SquirrelMotor, scripted keys at 60 Hz on a stand-in world (the
--     terrain, the games wing's roof): run into the downspout, climb, the gutter, the ridge, leap west off its end
--     (W held, Shift held, no key: every one lands on the house bough), down the bough and on along the crossing, Q
--     onto the wing roof, and walk to the louvre;
--   * where the leap works: Space swept over the ridge's last third with each key, E in the air, at 30/60/240 Hz;
--   * on the bough, W with the camera turned any way runs to the roof (or 3 st up to the house end, then on);
--   * the house is the only way up (owner question Q11's default): no route end, ground leap or trunk reaches the
--     bough. The house and the tree are drawn by tools/bake/alley/Yard (tests/unit/alley_yard_bake.spec.luau holds
--     the drawing to these routes).
local fs = require("@lune/fs")
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local AlleyRoof = require("@shared/Attractions/AlleyRoof")
local Curve = require("@shared/Routes/Curve")
local Data = require("@shared/Data")
local Graph = require("@shared/Routes/Graph")
local Height = require("@shared/World/Height")
local Motion = require("@shared/Routes/Motion")
local Registry = require("@shared/Routes/Registry")
local SpatialIndex = require("@shared/Routes/SpatialIndex")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local Expansion = require("../../tools/compile/lib/Expansion")

local R = AlleyRoof

type Trace = {
	visits: { number }, -- route ids in the order they were ridden (air and ground as 0)
	events: { [string]: number },
	catches: { number },
	maxMove: number,
	maxMoveAt: string?,
	attachMove: number?,
	frames: number,
	phase: string,
}

return function(t)
	local data = Data.default()
	local mod = data:module("Attractions") :: any
	local alley = mod.attractions[1]
	local place: AlleyLayout.Place = alley.place
	local fp = alley.footprint
	local records = R.records(place, alley.id)
	local byId: { [number]: any } = {}
	for _, r in records do
		byId[r.id] = r
	end
	local registry = Registry.fromRecords(records :: any)
	local function pt(id: number, tt: number): Curve.Vec3
		return registry:pointAt(registry:get(id) :: Registry.Route, tt)
	end
	local function dist(a: Curve.Vec3, b: Curve.Vec3): number
		return math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2 + (a.z - b.z) ^ 2)
	end
	local function toLocal(p: Curve.Vec3): (number, number, number)
		return AlleyLayout.toLocal(place, p.x, p.y, p.z)
	end

	t.test("the routes: ids, kinds, explicit flags, clear of the alley's own routes and of the harvest", function()
		local seen: { [number]: boolean } = {}
		local kinds: { [string]: boolean } = { tunnel = true }
		for _, k in Registry.KINDS do
			kinds[k] = true
		end
		for _, r in alley.routes do
			seen[r.id] = true
		end
		local town = data:routes()
		for _, r in R.routes() do
			t.truthy(r.id >= 9101 and r.id <= 9140, `id {r.id} in the roof's block`)
			t.truthy(not seen[r.id], `id {r.id} is unique and clear of data/attractions.json`)
			seen[r.id] = true
			t.eq(town:get(r.id), nil, `id {r.id} is not a route of the town`)
			t.truthy(kinds[r.kind], `kind {r.kind}`)
			t.truthy(#r.points >= 2, `route {r.id} has a line`)
			for _, k in { "autoGrabExcluded", "isPole", "isGiant", "fixedSurfaceZ", "treeTravel" } do
				t.eq(type((r.flags :: any)[k]), "boolean", `route {r.id} flag {k} is explicit`)
			end
			t.eq(r.enclosure ~= nil, r.kind == "tunnel", `route {r.id}: only the tunnel carries an enclosure`)
			t.truthy(byId[r.id].length > 1 and byId[r.id].sampleCount >= 21, `route {r.id} compiled`)
		end
		-- the house's downspout is walked into (unlike the town's); the gutter and the rafters are not
		t.eq(byId[9101].flags.autoGrabExcluded, false)
		t.eq(byId[9101].flags.fixedSurfaceZ, true)
		t.eq(byId[9102].flags.autoGrabExcluded, true)
		t.eq(byId[9105].flags.treeTravel, true)
		t.eq(#R.routes(), 5 + 8 + 9 + 2)
		-- the trunk's climb and the separate crossing are retired (Q11: the house is the only way up)
		for _, id in R.RETIRED do
			t.eq(byId[id], nil, `route {id} is retired`)
		end
		for id = R.FIRST_RAFTER, R.LAST_RAFTER do
			t.truthy(R.isRafter(id) == (byId[id] ~= nil), `rafter {id}`)
		end
		t.eq(byId[9128], nil, "no chord route over the pinsetters (the backstage's ground)")
		t.truthy(not R.isRafter(R.VENT) and not R.isRafter(9105))
	end)

	t.test(
		"the ground: in the footprint or the yard annex, off every venue site, the reserve and lounge one",
		function()
			local an = R.ANNEX
			-- the annex lies outside the footprint and the backstage reserve
			t.truthy(an.x0 >= fp.x1, "the annex starts east of the footprint")
			t.truthy(an.d1 < alley.reserve.d0, "the annex ends north of the backstage reserve")
			local annexPoly = {}
			for _, c in { { an.x0, an.d0 }, { an.x1, an.d0 }, { an.x1, an.d1 }, { an.x0, an.d1 } } do
				local x, _, z = AlleyLayout.toWorld(place, c[1], 0, c[2])
				table.insert(annexPoly, { x, z })
			end
			local venues = {}
			for _, v in (data:module("Expansion") :: any).venues do
				if type(v.place) == "table" or v.position then
					local ok, poly = pcall(Expansion.sitePoly, v)
					if ok then
						table.insert(venues, { id = v.id, poly = poly })
					end
				end
			end
			t.truthy(#venues > 20, `{#venues} venue sites to keep clear of`)
			local function check(X: number, D: number, what: string)
				local inFoot = X >= fp.x0 and X <= fp.x1 and D >= fp.d0 and D <= fp.d1
				t.truthy(inFoot or R.inAnnex(X, D), `{what} at ({X}, {D}) lies in the footprint or the annex`)
				local rs = alley.reserve
				t.truthy(not (X >= rs.x0 and X <= rs.x1 and D >= rs.d0 and D <= rs.d1), `{what}: off the backstage`)
				local x, _, z = AlleyLayout.toWorld(place, X, 0, D)
				for _, v in venues do
					t.truthy(not Expansion.contains(v.poly, x, z), `{what} at ({x}, {z}) is on {v.id}'s site`)
				end
			end
			for _, r in R.routes() do
				for _, p in r.points do
					check(p[1], p[3], `route {r.id}`)
				end
			end
			local h = R.HOUSE
			for _, c in { { h.x0 - h.overhang, h.d0 - h.overhang }, { h.x1 + h.overhang, h.d1 + h.overhang } } do
				check(c[1], c[2], "the house")
			end
			check(R.TREE.x - R.TREE.trunkR, R.TREE.d + R.TREE.trunkR, "the tree's foot")
			check(R.TREE.x + R.TREE.baffle.r, R.TREE.d + R.TREE.baffle.r, "the tree's baffle")
			-- the annex's corners are clear of every venue site too (lounge one is the nearest, north of it)
			for _, c in annexPoly do
				for _, v in venues do
					t.truthy(not Expansion.contains(v.poly, c[1], c[2]), `annex corner on {v.id}'s site`)
				end
			end
		end
	)

	t.test("no other route near the roof run (nothing else to grab by mistake)", function()
		local town = data:routes()
		local samples: { Curve.Vec3 } = {}
		local rafters: { Curve.Vec3 } = {}
		for _, r in records do
			local route = registry:get(r.id) :: Registry.Route
			for _, s in registry:samples(route) do
				table.insert(if R.isRafter(r.id) then rafters else samples, s)
			end
		end
		local nearest, nearestRafter = math.huge, math.huge
		for _, route in town:all() do
			if route.id >= 9101 and route.id <= 9140 then
				continue
			end
			for _, p in route.points do
				for _, s in samples do
					nearest = math.min(nearest, (p.x - s.x) ^ 2 + (p.y - s.y) ^ 2 + (p.z - s.z) ^ 2)
				end
				for _, s in rafters do
					nearestRafter = math.min(nearestRafter, (p.x - s.x) ^ 2 + (p.y - s.y) ^ 2 + (p.z - s.z) ^ 2)
				end
			end
		end
		-- the yard, the crossing and the vent: nothing within 10; the rafters: nothing within E's reach in the air
		-- (the alley's own ball-return mouths on the racks are the nearest, 9 under the light rails)
		t.truthy(math.sqrt(nearest) > 10, `the nearest other route point is {math.sqrt(nearest)} st away`)
		t.truthy(
			math.sqrt(nearestRafter) > Motion.C.airGrab,
			`the nearest other route point to a rafter is {math.sqrt(nearestRafter)} st away`
		)
	end)

	t.test(
		"the joints: downspout, gutter, ridge; the bough through the trunk's top; the vent's boot onto the chord",
		function()
			local gap = Motion.C.autoSwitchGap
			t.truthy(dist(pt(9101, 1), pt(9102, 0)) < 1e-3, "the downspout's head is the gutter's foot")
			t.truthy(gap > 0 and dist(pt(9102, 1), pt(9103, 0)) < 1e-3, "the gutter's head is the ridge's east end")
			t.truthy(dist(pt(9107, 1), pt(9120, 0)) < 1e-3, "the boot opens onto the chord")
			-- the bough passes through the trunk's top (where the tree bake joins them)
			local fork = R.TREE.spine[#R.TREE.spine]
			local fx, fy, fz = AlleyLayout.toWorld(place, fork[1], fork[2], fork[3])
			t.truthy(dist(pt(9105, R.BOUGH_FORK_T), Curve.vec3(fx, fy, fz)) < 0.05, "the bough meets the trunk's top")
			t.truthy(R.BOUGH_FORK_T > 0.15 and R.BOUGH_FORK_T < 0.5, `the trunk's top at t {R.BOUGH_FORK_T}`)
			-- the downspout's foot is a step above the ground at it; the trunk stands on the ground
			local foot = pt(9101, 0)
			local g = Height.at(foot.x, foot.z)
			t.truthy(foot.y - g > 0 and foot.y - g < 0.8, `the downspout's foot is {foot.y - g} over the ground`)
			local s = R.TREE.spine[1]
			local tx, ty, tz = AlleyLayout.toWorld(place, s[1], s[2], s[3])
			t.truthy(
				math.abs(ty - Height.at(tx, tz)) < 0.8,
				`the trunk's foot is {ty - Height.at(tx, tz)} from the ground`
			)
			-- the downspout stands 0.4 off the north wall (its pipe drawn round the line)
			local _, _, D = toLocal(foot)
			t.near(R.HOUSE.d0 - D, 0.4, 1e-6)
		end
	)

	t.test("the leap's geometry: the bough crosses the ridge's line above and beyond its end", function()
		-- where the bough (above the trunk's top) passes D 20 (the ridge's line)
		local bough = registry:get(9105) :: Registry.Route
		local best, bestT = math.huge, 0
		for i = 0, 400 do
			local u = R.BOUGH_FORK_T * i / 400
			local p = registry:pointAt(bough, u)
			local _, _, D = toLocal(p)
			if math.abs(D - R.HOUSE.ridgeD) < best then
				best, bestT = math.abs(D - R.HOUSE.ridgeD), u
			end
		end
		local X, Y = toLocal(registry:pointAt(bough, bestT))
		local endX, endY = toLocal(pt(9103, 1))
		t.truthy(endX - X > 12 and endX - X < 16, `the bough crosses the ridge's line {endX - X} west of its end`)
		t.truthy(Y - endY > 4.5 and Y - endY < 6.2, `and {Y - endY} above it`)
		-- the house end is a short stub past the catch (3 st: room for a landing, not a climb to a dead end)
		local stub = registry:get(9105).length * bestT
		t.truthy(stub > 2.5 and stub < 4, `the bough runs {stub} st past where the leap lands`)
		-- the crossing: over the wing's east parapet clear of the coping, and its end over the roof membrane
		local crossing = registry:get(9105) :: Registry.Route
		for i = 0, 400 do
			local cx, cy, cd = toLocal(registry:pointAt(crossing, i / 400))
			if cx >= R.WING_ROOF.x1 and cx <= R.WING_ROOF.outerX1 and cd <= R.WING_ROOF.outerD1 then
				t.truthy(cy - R.WING_ROOF.copingY >= 0.8, `{cy - R.WING_ROOF.copingY} over the coping at X {cx}`)
			end
		end
		local ex, ey, ed = toLocal(pt(9105, 1))
		t.truthy(ex > R.WING_ROOF.x0 + 30 and ex < R.WING_ROOF.x1 - 1 and ed < R.WING_ROOF.d1 - 2, "ends over the roof")
		t.truthy(ey - R.WING_ROOF.y > 0.5 and ey - R.WING_ROOF.y < 1.0, `ends {ey - R.WING_ROOF.y} over the membrane`)
		-- it droops: past the trunk's top it never rises, and it falls far more steeply toward the tip
		local prevY = math.huge
		for i = 0, 40 do
			local u = R.BOUGH_FORK_T + (1 - R.BOUGH_FORK_T) * i / 40
			local _, y = toLocal(pt(9105, u))
			t.truthy(y <= prevY + 0.01, `the crossing rises at t {u}`)
			prevY = y
		end
		local function drop(u0: number, u1: number): number
			local _, y0 = toLocal(pt(9105, R.BOUGH_FORK_T + (1 - R.BOUGH_FORK_T) * u0))
			local _, y1 = toLocal(pt(9105, R.BOUGH_FORK_T + (1 - R.BOUGH_FORK_T) * u1))
			return y0 - y1
		end
		t.truthy(drop(0.75, 1) > 3 * drop(0.2, 0.45), `the tip droops ({drop(0.75, 1)} against {drop(0.2, 0.45)})`)
	end)

	t.test(
		"the vent's run: the mouth on the membrane, every sample inside the unit, the duct, the elbow or the boot",
		function()
			local vent = registry:get(R.VENT) :: Registry.Route
			local _, my = toLocal(pt(R.VENT, 0))
			t.truthy(math.abs(my - R.WING_ROOF.y) <= 0.05, "the mouth's sill is the membrane")
			local h = R.AHU.housing
			local boxes = {
				{ x0 = h.x0, x1 = R.MOUTH.x + 0.01, y0 = R.AHU.curb.y0, y1 = h.y1, d0 = h.d0, d1 = h.d1 },
				R.DUCT,
				R.ELBOW,
				R.BOOT,
			}
			for i = 0, 200 do
				local X, Y, D = toLocal(registry:pointAt(vent, i / 200))
				local inside = false
				for _, b in boxes do
					-- (the curve rounds the elbow's foot 0.07 under the boot's floor line)
					if
						X >= b.x0 - 0.05
						and X <= b.x1 + 0.05
						and Y >= b.y0 - 0.1
						and Y <= b.y1
						and D >= b.d0
						and D <= b.d1
					then
						inside = true
					end
				end
				t.truthy(inside, `vent sample {i} at ({X}, {Y}, {D}) is inside the unit and its duct`)
			end
			-- no grating over the vent's run: the mouth and the first stretch lie on the bare apron in front of the
			-- louvre, a body's half-width (0.8) clear of the platform's louvre strip; the guard stands on the strip
			for i = 0, 200 do
				local X, _, D = toLocal(registry:pointAt(vent, i / 200))
				t.eq(R.inPlatform(X, D), nil, `vent sample {i} at ({X}, {D}) lies under the platform's grating`)
				t.eq(R.inPlatform(X + 0.8, D), nil, `vent sample {i}: the body's half-width reaches the grating`)
			end
			local a = R.APRON
			t.truthy(R.MOUTH.x > a.x0 and R.MOUTH.x < a.x1 and R.MOUTH.d > a.d0 and R.MOUTH.d < a.d1, "on the apron")
			t.eq(R.inPlatform(R.GUARD.x, R.GUARD.d), "louvre strip", "the guard stands on the louvre strip")
			for _, e in R.guardEyes() do
				t.truthy(R.inPlatform(e[1], e[3]) ~= nil, `the lookout at ({e[1]}, {e[3]}) is on the platform`)
			end
			-- a person on the platform at the louvre: their kick (7 st) reaches the mouth, not the boot
			local g = R.GUARD
			t.truthy(math.abs(R.MOUTH.x - g.x) < 7, "the guard's kick reaches the louvre")
			t.truthy(math.abs(R.BOOT.x0 - g.x) > 7, "and not the boot")
			-- the rafters sit out of a person's reach and under the raised deck with a leap's room
			t.truthy(R.CHORD.y1 - 3 > 5, "a person's root is more than 5 below the chords")
			t.truthy(
				R.HALL_ROOF.deckY0 >= R.CHORD.y1 + SquirrelMotor.leapApex() + 1.7,
				"a leap from a chord stays under the deck"
			)
		end
	)

	t.test("the vent's enclosure record (the enclosed-run contract of feat/run-through)", function()
		local rec = byId[R.VENT]
		local e = rec.enclosure
		-- Shared/Routes/Enclosure when it is in the tree (feat/run-through), by a computed path so this file loads
		-- without it
		local encPath = "@shared/Routes/" .. "Enclosure"
		if fs.isFile("src/shared/Routes/Enclosure.luau") then
			local Enclosure = (require :: any)(encPath)
			local errs = Enclosure.validateSet(records)
			t.eq(#errs, 0, table.concat(errs, "; "))
			local spec = Enclosure.fromRecord(e)
			local route = { id = R.VENT, kind = rec.kind, length = rec.length, enclosure = spec }
			local chord = { id = 9120, kind = "fence", length = byId[9120].length }
			t.truthy(Enclosure.allows(route, 1, chord, 0), "the boot hands over to the chord")
			t.truthy(Enclosure.hidden(route, 0.5), "inside the duct a squirrel is out of sight")
		end
		-- the same rules written out (Enclosure.validate and validateSet as of feat/run-through ff0c127)
		t.eq(rec.kind, "tunnel")
		t.eq(type(e.id), "string")
		t.truthy(e.width >= 1.6 and e.height >= 1.7, "the section takes the body (1.6 x 1.7)")
		t.eq(e.hidden, true)
		t.eq(#e.mouths, 2)
		local louvre, boot = e.mouths[1], e.mouths[2]
		t.eq(louvre.t, 0)
		t.eq(louvre.opens, "ground")
		local o = louvre.out
		t.near(math.sqrt(o[1] ^ 2 + o[2] ^ 2 + o[3] ^ 2), 1, 0.02)
		-- out points outside: from the mouth away from the run
		local inward = registry:tangentAt(registry:get(R.VENT) :: Registry.Route, 0)
		t.truthy(o[1] * inward.x + o[3] * inward.z < -0.9, "the louvre's out points away from the duct")
		t.eq(boot.t, 1)
		t.eq(boot.opens, "link")
		t.eq(#boot.links, 1)
		t.eq(boot.links[1].route, 9120)
		t.eq(boot.links[1].t, 0)
		t.eq(boot.links[1].dir, 1)
		t.truthy(rec.length > 2 * 1.2 + 2 * 1.2, "the two mouths' windows do not overlap")
	end)

	-- THE CHAIN WITH THE REAL MOTOR ------------------------------------------------------------------------------
	local index = SpatialIndex.build(registry)
	local graph = Graph.build(registry, index, nil)
	local roofY = place.floorY + R.WING_ROOF.y
	-- the stand-in world: the terrain, and the games wing's roof (the membrane inside its parapets) for a body that
	-- comes down onto it from above. No walls: the house, the tree and the unit are not built into this world.
	local function groundAt(x: number, z: number, refY: number): number
		local X, _, D = AlleyLayout.toLocal(place, x, 0, z)
		local w = R.WING_ROOF
		if X >= w.x0 and X <= w.x1 and D >= w.d0 and D <= w.d1 and refY + 1.5 >= roofY then
			return roofY
		end
		return Height.at(x, z)
	end
	local world = {
		registry = registry,
		index = index,
		graph = graph,
		trampolines = {},
		groundAt = groundAt,
		blocked = function(_x: number, _z: number, _y: number): boolean
			return false
		end,
		clamp = nil,
	}
	local function yawToward(state: SquirrelMotor.State, p: Curve.Vec3): number
		-- the camera behind the squirrel looking at p (forward = (-sin yaw, -cos yaw))
		return math.atan2(-(p.x - state.x), -(p.z - state.z))
	end
	local mouthX, mouthY, mouthZ = AlleyLayout.toWorld(place, R.MOUTH.x, R.MOUTH.y, R.MOUTH.d)
	local mouth = Curve.vec3(mouthX, mouthY, mouthZ)

	local FORK_T = R.BOUGH_FORK_T
	local LIFT = Motion.C.visualBranchLift

	local function deepCopy(v: any): any
		if type(v) ~= "table" then
			return v
		end
		local out = {}
		for k, x in v do
			out[k] = deepCopy(x)
		end
		return out
	end

	type Opts = {
		leapAtX: number?, -- local X on the ridge to press Space at (else its end, where W stops the squirrel)
		hz: number?, -- frames per second (60)
		grabNear: boolean?, -- press E in the air whenever the bough is the route within E's reach
		boughYaw: number?, -- the camera's (world) yaw when W is first pressed on the bough (else down it)
		stopAfterCatch: boolean?,
		world: any?, -- the world to run in (else the stand-in)
		from: SquirrelMotor.State?, -- start from this state (a copy) ...
		startPhase: string?, -- ... in this phase ("pipe")
	}

	local function newTrace(): Trace
		return {
			visits = {},
			events = {},
			catches = {},
			maxMove = 0,
			maxMoveAt = nil,
			attachMove = nil,
			frames = 0,
			phase = "pipe",
		}
	end

	-- run(sprint, leapKeys, opts): the whole way from the ground north of the downspout to the louvre. leapKeys:
	-- "walk" (W held through the leap), "sprint" (Shift and W), "none" (Space alone, nothing held in the air).
	local function run(sprint: boolean, leapKeys: string, opts: Opts?): (Trace, SquirrelMotor.State, { [string]: any })
		local o: Opts = opts or {}
		local hz = o.hz or 60
		local dt = 1 / hz
		local state: SquirrelMotor.State
		if o.from then
			state = deepCopy(o.from)
		else
			local foot = pt(9101, 0)
			local sx, sz = foot.x, foot.z + 7 -- seven studs north of the pipe (world +Z), facing it
			state = SquirrelMotor.new(sx, Height.at(sx, sz), sz)
			state.yaw = 0
		end
		local trace = newTrace()
		trace.phase = o.startPhase or "pipe"
		local info: { [string]: any } = {}
		local onBough, release = 0, 0
		local boughYaw = o.boughYaw
		for frame = 1, hz * 40 do
			trace.frames = frame
			local input = SquirrelMotor.idleInput(0)
			local phase = trace.phase
			local rid = state.routeId
			if phase == "pipe" then
				-- run at the pipe (camera behind, looking south), up it, up the gutter; on the ridge look west
				input.fw, input.sprint = 1, sprint
				input.cameraYaw = if rid == 9103 then math.pi / 2 else 0
				if rid == 9103 then
					local X = toLocal(Curve.vec3(state.x, state.y, state.z))
					if info.ridge == nil then
						info.ridge = deepCopy(state)
					end
					if state.railT >= 1 or (o.leapAtX ~= nil and X <= o.leapAtX) then
						trace.phase = "leap"
						info.leapX = X
					end
				end
			elseif phase == "leap" then
				input.cameraYaw = math.pi / 2
				input.leap = true
				input.fw = if leapKeys == "none" then 0 else 1
				input.sprint = leapKeys == "sprint"
				trace.phase = "air"
			elseif phase == "air" then
				input.cameraYaw = math.pi / 2
				input.fw = if leapKeys == "none" then 0 else 1
				input.sprint = leapKeys == "sprint"
				if o.grabNear then
					local near =
						Motion.nearestRoute((o.world or world) :: any, state.x, state.y, state.z, Motion.C.airGrab)
					input.grab = near ~= nil and near.routeId == R.BOUGH
				end
				if rid == R.BOUGH then
					trace.phase = "bough"
					info.caught = deepCopy(state)
					info.catchT = state.railT
					if o.stopAfterCatch then
						break
					end
				elseif rid == 9103 then
					trace.phase = "back on the ridge"
					break
				elseif state.grounded then
					trace.phase = "missed"
					info.landed = toLocal(Curve.vec3(state.x, state.y, state.z))
					break
				end
			elseif phase == "bough" then
				-- let go of the keys, look down the bough (or where boughYaw says), run on; at the house end of the
				-- bough, let go, look down it and go again
				onBough += 1
				input.cameraYaw = boughYaw or yawToward(state, pt(R.BOUGH, if state.railT < FORK_T then FORK_T else 1))
				input.fw = if onBough <= 3 or release > 0 then 0 else 1
				input.sprint = sprint
				release = math.max(0, release - 1)
				if rid ~= R.BOUGH then
					trace.phase = "lost on " .. tostring(rid)
					break
				elseif state.railT >= 1 then
					trace.phase = "drop"
				elseif state.railT <= 0 and onBough > 10 and release == 0 and boughYaw ~= nil then
					info.houseEnd = deepCopy(state)
					boughYaw = nil
					release = 3
				end
				if math.abs(state.railT - FORK_T) < 0.01 then
					info.pastFork = true
				end
			elseif phase == "drop" then
				input.cameraYaw = yawToward(state, mouth)
				input.drop = true
				trace.phase = "down"
			elseif phase == "down" then
				input.cameraYaw = yawToward(state, mouth)
				if state.grounded then
					trace.phase = "roof"
				end
			elseif phase == "roof" then
				input.cameraYaw = yawToward(state, mouth)
				input.fw, input.sprint = 1, sprint
				if math.sqrt((state.x - mouth.x) ^ 2 + (state.z - mouth.z) ^ 2) < 1.2 then
					trace.phase = "louvre"
					break
				end
			end
			local ox, oy, oz = state.x, state.y, state.z
			local _, events = SquirrelMotor.step(state, input, dt, (o.world or world) :: any)
			for _, e in events do
				trace.events[e.kind] = (trace.events[e.kind] or 0) + 1
				if e.kind == "catch" and e.routeId then
					table.insert(trace.catches, e.routeId)
				end
			end
			if rid == nil and state.routeId == R.BOUGH then
				-- the catch: how far the drawn feet move up onto the bough's top (a bough's top is the rail + 1.25)
				info.catchRise = state.y + LIFT - oy
			end
			local moved = math.sqrt((state.x - ox) ^ 2 + (state.y - oy) ^ 2 + (state.z - oz) ^ 2)
			-- (the walk-in grab puts the body on the pipe's line in one frame, as v5.4's did: up to the walk-in
			-- reach; the drawn body stands off the pipe on its +Z side, Motion.visualPose)
			local attached = rid == nil and state.routeId ~= nil and trace.events.attach == 1
			if attached then
				trace.attachMove = moved
			elseif moved > trace.maxMove then
				trace.maxMove = moved
				trace.maxMoveAt = `{phase} frame {frame} route {tostring(rid)} -> {tostring(state.routeId)}`
			end
			local here = state.routeId or 0
			if trace.visits[#trace.visits] ~= here then
				table.insert(trace.visits, here)
			end
		end
		return trace, state, info
	end

	for _, case in
		{
			{ sprint = false, leap = "walk" },
			{ sprint = true, leap = "sprint" },
			{ sprint = false, leap = "none" },
			{ sprint = true, leap = "none" },
		}
	do
		local label = `{if case.sprint then "sprinting" else "walking"}, leap with {case.leap}`
		t.test(
			`the chain with the real motor ({label}): pipe, gutter, ridge, leap onto the bough, crossing, roof, louvre`,
			function()
				local trace, state, info = run(case.sprint, case.leap)
				if trace.phase ~= "louvre" then
					local ev = {}
					for k, n in trace.events do
						table.insert(ev, `{k} {n}`)
					end
					print(
						`      events: {table.concat(ev, ", ")}; at ({state.x}, {state.y}, {state.z}) route {state.routeId} t {state.railT}`
					)
				end
				local seq = table.concat(trace.visits, " ")
				t.eq(trace.phase, "louvre", `got as far as "{trace.phase}" (routes {seq}) after {trace.frames} frames`)
				t.eq(seq, "0 9101 9102 9103 0 9105 0", "the routes in order")
				t.eq(trace.catches[1], R.BOUGH, "the leap off the ridge catches the house bough")
				t.truthy(info.pastFork, "down the bough, past the trunk's top, on along the crossing")
				t.truthy(
					(trace.attachMove or 0) <= Motion.C.walkInReach + 0.5,
					`the walk-in grab moves {trace.attachMove}`
				)
				t.truthy(trace.maxMove <= 1.5, `no frame moves more than 1.5 st ({trace.maxMove} at {trace.maxMoveAt})`)
				t.near(state.y, roofY, 0.05, "on the wing roof's membrane")
				local seconds = trace.frames / 60
				t.truthy(seconds < 25, `ground to louvre in {seconds} s`)
				print(`      {label}: ground to louvre in {string.format("%.1f", seconds)} s`)
			end
		)
	end

	-- the climb to the ridge, once per pace (the sweeps below start from the squirrel as it steps onto the ridge)
	local onRidge: { [boolean]: SquirrelMotor.State } = {}
	local function ridgeStart(sprint: boolean): SquirrelMotor.State
		if not onRidge[sprint] then
			local _, _, info = run(sprint, "walk", { stopAfterCatch = true })
			onRidge[sprint] = info.ridge
		end
		return onRidge[sprint]
	end

	t.test(
		"where the leap works: the last third of the ridge swept, W, Shift+W and no key, at 30, 60 and 240 Hz",
		function()
			local endX = toLocal(pt(9103, 1))
			local startX = toLocal(pt(9103, 0))
			local third = (startX - endX) / 3
			local rows = {}
			local windows: { [string]: number } = {}
			for _, mode in { "walk", "sprint", "none", "walk+E" } do
				local keys = if mode == "walk+E" then "walk" else mode
				local sprint = mode == "sprint"
				-- (from the ridge's end, Space with the squirrel stopped there; then from points short of it)
				local window, misses = 0, {}
				local back = 0
				local rises = {}
				for k = 0, 16 do
					local short = third * k / 16
					local _, _, info = run(sprint, keys, {
						from = ridgeStart(sprint),
						leapAtX = if k == 0 then nil else endX + short,
						stopAfterCatch = true,
						grabNear = mode == "walk+E",
					})
					if info.caught then
						if #misses == 0 then
							window = short
						end
						table.insert(rises, info.catchRise)
					elseif info.landed then
						table.insert(misses, string.format("%.1f", short))
					else
						back += 1
					end
				end
				windows[mode] = window
				local maxRise = 0
				for _, r in rises do
					maxRise = math.max(maxRise, r)
				end
				table.insert(
					rows,
					`{mode}: catches from the end to {string.format("%.1f", window)} st short of it (falls from {misses[1] or "-"} st short; {back} back on the ridge; the drawn body rises {string.format(
						"%.2f",
						rises[1] or 0
					)} at the catch from the end, up to {string.format("%.2f", maxRise)})`
				)
			end
			print(`      the ridge's last third ({string.format("%.1f", third)} st): {table.concat(rows, "; ")}`)
			t.truthy(windows.walk >= 3.5, `holding W, the leap catches from up to {windows.walk} st short of the end`)
			t.truthy(windows.none >= 3.5, `no key held, the leap catches from up to {windows.none} st short of the end`)
			t.truthy(windows.sprint >= third - 0.01, `sprinting, up to {windows.sprint} st short`)
			t.truthy(windows["walk+E"] >= windows.walk, "E in the air never makes it worse")
			-- from the end it catches at every frame rate, with every key, and lands the body on the bough's top within the
			-- motor's catch reach
			for _, hz in { 30, 60, 240 } do
				for _, keys in { "walk", "sprint", "none" } do
					local _, _, info = run(keys == "sprint", keys, { from = ridgeStart(keys == "sprint"), hz = hz })
					t.truthy(info.caught ~= nil, `{hz} Hz, {keys}: the leap from the ridge's end catches the bough`)
					t.truthy(
						math.abs(info.catchRise or math.huge) <= Motion.C.airCatch + LIFT,
						`{hz} Hz, {keys}: the body moves {info.catchRise} at the catch`
					)
				end
			end
		end
	)

	t.test("on the bough: looking anywhere, W runs on to the roof, or up 3 st to the house end and then on", function()
		local _, _, caught = run(false, "walk", { from = ridgeStart(false), stopAfterCatch = true })
		local start = caught.caught :: SquirrelMotor.State
		t.truthy(start ~= nil, "caught")
		local catchP = Curve.vec3(start.x, start.y, start.z)
		local up, down = {}, {}
		for deg = 0, 345, 15 do
			local trace, state, info =
				run(false, "walk", { from = start, startPhase = "bough", boughYaw = math.rad(deg) })
			local _ = trace
			t.truthy(state.routeId ~= nil or trace.phase ~= "missed", `yaw {deg}: fell off`)
			if info.houseEnd then
				local h = info.houseEnd :: SquirrelMotor.State
				local d = dist(Curve.vec3(h.x, h.y, h.z), catchP)
				t.truthy(d <= 4, `yaw {deg}: the house end is {d} st from the catch`)
				table.insert(up, deg)
			else
				table.insert(down, deg)
			end
			t.eq(trace.phase, "louvre", `yaw {deg}: ended "{trace.phase}" (routes {table.concat(trace.visits, " ")})`)
		end
		print(
			`      W first pressed looking at yaw (deg): down the bough {table.concat(down, ",")}; up to the house end {table.concat(
				up,
				","
			)}`
		)
	end)

	t.test(
		"the house is the only way up: nothing reaches the bough from the ground, the trunk or another route",
		function()
			local bough = registry:get(R.BOUGH) :: Registry.Route
			local samples = registry:samples(bough)
			-- no other route's end is within E's reach on a rail or the end-of-route switch of the bough
			local reach = Motion.C.eSearch + Motion.C.autoSwitchGap
			for _, r in records do
				if r.id ~= R.BOUGH then
					local route = registry:get(r.id) :: Registry.Route
					for _, u in { 0, 1 } do
						local e = registry:pointAt(route, u)
						for _, s in samples do
							t.truthy(dist(e, s) > reach, `route {r.id}'s end at t {u} is {dist(e, s)} from the bough`)
						end
					end
				end
			end
			-- from the ground (outside the wing), a leap's apex plus E's reach falls short of every point of the bough
			local apex = SquirrelMotor.leapApex()
			local nearest = math.huge
			for _, s in samples do
				local X = toLocal(s)
				if X > R.WING_ROOF.outerX1 + 0.5 then
					nearest = math.min(nearest, s.y - Height.at(s.x, s.z) - apex)
				end
			end
			t.truthy(nearest > Motion.C.airGrab + 1, `from the ground the bough is {nearest} past a leap's apex`)
			-- with the motor: run at the trunk from eight sides, leap at it, E at the top of the leap: never on a route
			local T = R.TREE
			local trunkWorld = table.clone(world) :: any
			trunkWorld.blocked = function(x: number, z: number, y: number): boolean
				local X, Y, D = AlleyLayout.toLocal(place, x, y, z)
				return Y < T.spine[#T.spine][2] and (X - T.x) ^ 2 + (D - T.d) ^ 2 <= (T.trunkR + 0.4) ^ 2
			end
			local tx, _, tz = AlleyLayout.toWorld(place, T.x, 0, T.d)
			for k = 0, 7 do
				local a = k * math.pi / 4
				local sx, sz = tx + 8 * math.sin(a), tz + 8 * math.cos(a)
				local state = SquirrelMotor.new(sx, Height.at(sx, sz), sz)
				local face = math.atan2(-(tx - sx), -(tz - sz)) -- the camera behind, looking at the trunk
				local onRoute: number? = nil
				for frame = 1, 60 * 6 do
					local input = SquirrelMotor.idleInput(face)
					input.fw = 1
					input.leap = frame % 60 == 0
					input.grab = state.vy < 0.5 and not state.grounded
					SquirrelMotor.step(state, input, 1 / 60, trunkWorld)
					onRoute = onRoute or state.routeId
				end
				t.eq(onRoute, nil, `from side {k}: the squirrel got onto route {onRoute}`)
			end
		end
	)

	-- THE CHAIN ON THE BAKED GEOMETRY: when tests/lib/BakedWorld (the enclosed-runs harness, feat/run-through) is in
	-- the tree, the eighteen-lane alley and the yard are baked in memory by their own bake code and the chain runs
	-- against their parts (the house's roof and plinth, the trunk, the wing's parapets and roof), not the stand-in.
	t.test("the chain on the baked alley and yard (tests/lib/BakedWorld, when it is in the tree)", function()
		if not fs.isFile("tests/lib/BakedWorld.luau") then
			print("      (tests/lib/BakedWorld is not in this tree: the chain ran on the stand-in world above)")
			return
		end
		local roblox = require("@lune/roblox")
		local serde = require("@lune/serde")
		local BakedWorld = (require :: any)("../lib/" .. "BakedWorld")
		local Kit = require("../../tools/bake/alley/Kit")
		local Shell = (require :: any)("../../tools/bake/alley/" .. "Shell")
		local Lanes = (require :: any)("../../tools/bake/alley/" .. "Lanes")
		local Rooms = (require :: any)("../../tools/bake/alley/" .. "Rooms")
		local GameBakes = (require :: any)("../../tools/bake/" .. "GameBakes")
		local Yard = require("../../tools/bake/alley/Yard")
		local raw = serde.decode("json", fs.readFile("data/attractions.json")).attractions[1]
		local kit = Kit.new(roblox, place)
		local root = GameBakes.siteModel(roblox, "BowlingAlley", raw.id, place)
		Shell.build(kit, root, raw)
		Lanes.build(kit, root)
		Rooms.build(kit, root)
		Yard.build(kit, root)
		local baked = BakedWorld.fromModel(root, { adjust = BakedWorld.alleyRuntime })
		local motorWorld = baked:motorWorld(BakedWorld.recordsData(records))
		for _, case in { { sprint = false, leap = "walk" }, { sprint = true, leap = "none" } } do
			local trace, state = run(case.sprint, case.leap, { world = motorWorld })
			local seq = table.concat(trace.visits, " ")
			local label = `{if case.sprint then "sprinting" else "walking"}, leap with {case.leap}`
			t.truthy(
				trace.phase == "louvre" or state.routeId == R.VENT,
				`{label}: got as far as "{trace.phase}" (routes {seq}) at ({state.x}, {state.y}, {state.z})`
			)
			local want = "0 9101 9102 9103 0 9105 0"
			t.eq(string.sub(seq, 1, #want), want, `{label}: {seq}`)
			t.truthy(trace.maxMove <= 1.5, `{label}: a frame moves {trace.maxMove} ({trace.maxMoveAt})`)
			print(
				`      on the baked alley and yard, {label}: routes {seq} in {string.format("%.1f", trace.frames / 60)} s`
			)
		end
	end)
end
