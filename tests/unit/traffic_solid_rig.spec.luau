--!strict
-- Cars are solid to the squirrel, end to end on the live rig (tests/lib/LiveRig: the client's real SquirrelMotor, a
-- real link, the server's MovementService over MoveValidator with enforcement on). Owner's playtest 2026-11-18: "I did
-- run right through a car".
--   * the client's motor meets the cars as its client draws them (Traffic/Solid.squirrelWorld over the boxes of the
--     cars drawn `lag` seconds behind the server's: the playout delay and the link), as Client/World/ClientWorld does;
--   * the server's validator meets the traffic service's boxes (Server/Traffic/TrafficService.fillSolids, the very
--     function each traffic tick runs: walls where a car stood still SETTLE seconds, floors under every car stretched
--     behind it; Server/Movement/ValidatorWorld.build's `cars`);
--   * honest play round a stopped car, a parked trolley, a slow car, a car that pulls up, and on and off a roof: never
--     inside a drawn car, 0 snaps; a client that walks through a stopped car is snapped back;
--   * a squirrel run over still dies (Server/Traffic/SweptCollision on the server's car), its motor blocked by the
--     drawn one;
--   * the cost of the car boxes: client and server, 25 cars.
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local Solid = require("@shared/Traffic/Solid")
local Boxes = require("@shared/Traffic/Boxes")
local Units = require("@shared/Config/Units")
local ValidatorWorld = require("@server/Movement/ValidatorWorld")
local TrafficService = require("@server/Traffic/TrafficService")
local SweptCollision = require("@server/Traffic/SweptCollision")
local Harness = require("@tests/cheat/Harness")
local LiveRig = require("@tests/lib/LiveRig")

type State = SquirrelMotor.State

-- a scripted car: where the server has it at time t (studs, HTML yaw, studs/s)
type Car = {
	id: number,
	kind: string,
	pose: (t: number) -> (number, number, number, number, boolean), -- x, z, yaw, speed, visible
	stillSince: number?, -- it has stood still since before the run (a parked car)
}

local TICK = 1 / 30
local BODY = Solid.BODY

-- the open ground of the S3 harness (no route, no house), its middle
local G = Harness.OPEN_GROUND
local MX, MZ = Units.st((G.minX + G.maxX) / 2), Units.st((G.minZ + G.maxZ) / 2)

local function yawToward(dx: number, dz: number): number
	return math.atan2(-dx, -dz) -- the camera yaw whose forward is (dx, dz)
end

local function parked(id: number, kind: string, x: number, z: number, yaw: number): Car
	return {
		id = id,
		kind = kind,
		stillSince = -10,
		pose = function(_t: number)
			return x, z, yaw, 0, true
		end,
	}
end

-- moving along +z from z0 at `speed`, until `stopAt` (then stood still there)
local function driving(id: number, kind: string, x: number, z0: number, speed: number, stopAt: number?): Car
	return {
		id = id,
		kind = kind,
		pose = function(t: number)
			local run = if stopAt then math.min(t, stopAt) else t
			local moving = stopAt == nil or t < stopAt
			return x, z0 + speed * math.max(run, 0), 0, if moving then speed else 0, true
		end,
	}
end

export type Scene = {
	cars: { Car },
	start: State,
	keys: (t: number, state: State) -> SquirrelMotor.Input,
	seconds: number,
	lag: number, -- how far behind the server's the client draws the cars (playout delay and the way down)
	link: LiveRig.Link?,
	walkThrough: boolean?, -- the client's motor ignores the cars (a cheat)
	seed: number?,
}

export type Outcome = {
	result: LiveRig.Result,
	inside: number, -- client frames the body's core stood inside a drawn car
	frames: number,
	top: number, -- the highest the body's feet stood
	trace: { { number } }, -- the client's x, y, z per frame
}

local function play(town: any, scene: Scene): Outcome
	local solids = { walls = Solid.newSet(), floors = Solid.newSet() }
	local still: { [number]: number } = {}
	local prev: { [number]: { x: number, z: number, visible: boolean } } = {}
	local base = town.world.groundHeight - Units.st(0.18) -- the road (the squirrel stands 0.18 u over it)
	local function vehiclesAt(t: number): { any }
		local list = {}
		for _, c in scene.cars do
			local x, z, yaw, speed, visible = c.pose(t)
			table.insert(list, {
				id = c.id,
				kind = c.kind,
				x = x,
				y = base + Units.st(0.04),
				z = z,
				yaw = yaw,
				speed = speed,
				visible = visible,
			})
		end
		return list
	end
	for _, c in scene.cars do
		if c.stillSince then
			-- stood there since before the run: its last tick, and how long it has stood
			still[c.id] = -c.stillSince
			local x, z, _, _, visible = c.pose(-TICK)
			prev[c.id] = { x = x, z = z, visible = visible }
		end
	end
	local vworld = ValidatorWorld.build(town.world, { wall = town.wall, down = town.down, cars = solids })
	local drawn = Solid.newSet()
	local world = if scene.walkThrough then town.world else Solid.squirrelWorld(town.world, drawn)
	local rig = LiveRig.new({ world = world, vworld = vworld, link = scene.link, seed = scene.seed or 1 })
	-- the server's traffic ticks
	local n = math.ceil(scene.seconds / TICK)
	for k = 0, n do
		local t = k * TICK
		rig:at(t, function()
			local list = vehiclesAt(t)
			TrafficService.fillSolids(solids, still, list, prev, TICK)
			for _, v in list do
				prev[v.id] = { x = v.x, z = v.z, visible = v.visible }
			end
		end)
	end
	local out = { inside = 0, frames = 0, top = -math.huge, trace = {} }
	rig:possess(scene.start, function(t: number, state: State): SquirrelMotor.Input
		-- this frame's drawn cars (the client refills them every frame, Render/VehicleView)
		Solid.clear(drawn)
		local seen = t - scene.lag
		for _, c in scene.cars do
			local x, z, yaw, _, visible = c.pose(seen)
			if visible then
				Solid.add(drawn, Solid.hull(c.kind, x, base, z, yaw))
			end
		end
		out.frames += 1
		if Solid.core(drawn, state.x, state.z, state.y) then
			out.inside += 1
		end
		out.top = math.max(out.top, state.y)
		table.insert(out.trace, { state.x, state.y, state.z })
		return scene.keys(t, state)
	end)
	rig:run(scene.seconds)
	return {
		result = rig:result(),
		inside = out.inside,
		frames = out.frames,
		top = out.top,
		trace = out.trace,
	}
end

-- keys that run at a point (sprinting or not), then at the next
local function toward(points: { { number } }, sprint: boolean?): (t: number, state: State) -> SquirrelMotor.Input
	return function(t: number, state: State): SquirrelMotor.Input
		local p = points[#points]
		for _, q in points do
			if t < q[3] then
				p = q
				break
			end
		end
		local input = SquirrelMotor.idleInput(yawToward(p[1] - state.x, p[2] - state.z))
		local dx, dz = p[1] - state.x, p[2] - state.z
		if dx * dx + dz * dz > 0.25 then
			input.fw = 1
			input.sprint = sprint == true
		end
		return input
	end
end

local LINKS: { { name: string, link: LiveRig.Link, lag: number } } = {
	{ name = "80 ms", link = { latency = 0.08, jitter = 0.05, loss = 0.02 }, lag = 0.08 + 0.13 + 0.05 },
	{ name = "300 ms, 150 ms jitter", link = { latency = 0.3, jitter = 0.15, loss = 0.02 }, lag = 0.3 + 0.13 + 0.15 },
}

local function report(name: string, o: Outcome)
	print(`      {LiveRig.describe(name, o.result)}; {o.inside} of {o.frames} frames inside a drawn car`)
	for _, v in o.result.violations do
		print(`      VIOLATION {v}`)
	end
end

return function(t)
	local town = LiveRig.town()
	local ground = town.world.groundHeight
	local sedan = Boxes.get("sedan")

	for _, L in LINKS do
		t.test(`a squirrel runs into a stopped car's side and round it ({L.name}): never inside, 0 snaps`, function()
			-- a sedan across the way (heading +x), the squirrel runs at its middle, then for a point behind it
			local car = parked(1, "sedan", MX, MZ, math.pi / 2)
			local o = play(town, {
				cars = { car },
				start = SquirrelMotor.new(MX, ground, MZ - 12),
				keys = toward({ { MX, MZ + 12, 3 }, { MX + 9, MZ + 8, 7 }, { MX, MZ + 12, 99 } }, true),
				seconds = 11,
				lag = L.lag,
				link = L.link,
			})
			report("stopped sedan", o)
			t.eq(o.inside, 0, "frames inside the car")
			t.eq(o.result.snaps, 0, "snaps")
			-- it was stopped at the car's side for the first seconds, and got round it
			local early = o.trace[math.floor(o.frames * 2.5 / 11)]
			t.truthy(early[3] < MZ - sedan.width / 2 - BODY.HALF + 0.3, `held at the side (z {early[3] - MZ})`)
			local last = o.trace[#o.trace]
			t.truthy(last[3] > MZ + sedan.width / 2, `went round (z {last[3] - MZ})`)
		end)
	end

	t.test("a squirrel runs into a parked trolley (turned) and along it: never inside, 0 snaps", function()
		local car = parked(1, "trolley", MX, MZ, 0.6)
		local o = play(town, {
			cars = { car },
			start = SquirrelMotor.new(MX - 14, ground, MZ),
			keys = toward({ { MX + 14, MZ, 4 }, { MX + 14, MZ + 20, 9 }, { MX + 14, MZ - 20, 99 } }, true),
			seconds = 14,
			lag = 0.3,
			link = { latency = 0.15, jitter = 0.1, loss = 0.02 },
		})
		report("parked trolley", o)
		t.eq(o.inside, 0)
		t.eq(o.result.snaps, 0)
	end)

	t.test("a client that walks through a stopped car is snapped back (the validator sees the car)", function()
		local car = parked(1, "sedan", MX, MZ, math.pi / 2)
		local o = play(town, {
			cars = { car },
			start = SquirrelMotor.new(MX, ground, MZ - 20),
			keys = toward({ { MX, MZ + 12, 6 }, { MX, MZ - 12, 10 }, { MX, MZ + 12, 99 } }, false),
			seconds = 14,
			lag = 0.2,
			link = { latency = 0.1, jitter = 0.05, loss = 0 },
			walkThrough = true,
		})
		report("walks through", o)
		t.truthy(o.result.snaps >= 1, "snapped")
	end)

	for _, L in LINKS do
		t.test(
			`a slow car (2 st/s): the squirrel presses on its side and its tail ({L.name}): never inside, 0 snaps`,
			function()
				-- the car crawls north; the squirrel runs at its side, then follows it pressed on its tail
				local car = driving(1, "sedan", MX, MZ - 20, 2)
				local o = play(town, {
					cars = { car },
					start = SquirrelMotor.new(MX - 10, ground, MZ - 18),
					keys = function(tt: number, state: State): SquirrelMotor.Input
						local _, cz = car.pose(tt - L.lag)
						if tt < 4 then
							return toward({ { MX + 6, cz, 99 } }, false)(tt, state)
						end
						return toward({ { MX, cz - 30, 6 }, { MX, cz + 30, 99 } }, false)(tt, state)
					end,
					seconds = 12,
					lag = L.lag,
					link = L.link,
				})
				report("slow car", o)
				t.eq(o.inside, 0)
				t.eq(o.result.snaps, 0)
			end
		)
	end

	for _, L in LINKS do
		t.test(`a car pulls up beside the squirrel's way and it walks round it ({L.name}): 0 snaps`, function()
			-- the car comes up at 8 st/s and stops at MZ at t = 2; the squirrel crosses its nose after it stops
			local car = driving(1, "sedan", MX, MZ - 16, 8, 2)
			local o = play(town, {
				cars = { car },
				start = SquirrelMotor.new(MX - 12, ground, MZ),
				keys = toward({ { MX - 12, MZ, 2.5 }, { MX + 12, MZ, 6 }, { MX - 12, MZ + 1, 99 } }, true),
				seconds = 10,
				lag = L.lag,
				link = L.link,
			})
			report("pulls up", o)
			t.eq(o.inside, 0)
			t.eq(o.result.snaps, 0)
		end)
	end

	t.test("onto a parked car's roof and off it, and off a roof the car drives from under: 0 snaps", function()
		-- v5.4 (traffic.md §7): a roof is ground; a moving car slides out from under (it does not carry the squirrel)
		local car = {
			id = 1,
			kind = "sedan",
			stillSince = -10,
			pose = function(tt: number)
				-- parked until t = 6, then pulls away north at 3 st/s
				local run = math.max(tt - 6, 0)
				return MX, MZ + 3 * run, 0, if tt > 6 then 3 else 0, true
			end,
		} :: Car
		local leapAt = 1.2
		local o = play(town, {
			cars = { car },
			start = SquirrelMotor.new(MX - 7, ground, MZ),
			keys = function(tt: number, state: State): SquirrelMotor.Input
				local input = SquirrelMotor.idleInput(yawToward(1, 0))
				if tt < 4 then
					-- run east at the car, leap as it nears, stand on the roof
					input.fw = if state.x < MX - 0.3 then 1 else 0
					input.leap = tt >= leapAt and tt < leapAt + 0.05
				end
				return input
			end,
			seconds = 10,
			lag = 0.3,
			link = { latency = 0.15, jitter = 0.1, loss = 0.02 },
		})
		report("roof", o)
		local roofTop = ground - Units.st(0.18) + sedan.height
		t.truthy(o.top > roofTop - 0.2, `stood on the roof (feet {o.top}, roof {roofTop})`)
		local last = o.trace[#o.trace]
		t.truthy(last[2] < ground + 0.3, `fell off once the car drove from under (feet {last[2]})`)
		t.eq(o.inside, 0)
		t.eq(o.result.snaps, 0)
	end)

	t.test(
		"a squirrel a drawn car came over walks out of it by any side (sedan, van, RV, trolley, dump truck)",
		function()
			-- review 2026-11-18 (P1): the car pulled up or appeared over the body on its client, or the body was handed over
			-- or put back under it; the walls the body is already inside are left out (Solid.caught), as the validator's
			-- rays do; once out the car is a wall again
			local road = ground - Units.st(0.18)
			for _, kind in { "sedan", "ice_cream_van", "rv", "trolley", "dump_truck" } do
				local box = Boxes.get(kind)
				for _, at in { { box.width / 2 - 0.5, 0 }, { 0, box.length / 2 - 0.3 }, { 0, 0 } } do
					for _, dir in { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } } do
						local drawn = Solid.newSet()
						Solid.add(drawn, Solid.hull(kind, MX, road, MZ, 0))
						local cw = Solid.squirrelWorld(town.world, drawn)
						local s = SquirrelMotor.new(MX + at[1], ground, MZ + at[2])
						local wasInside = Solid.core(drawn, s.x, s.z, s.y)
						for _ = 1, 180 do
							local input = SquirrelMotor.idleInput(yawToward(dir[1], dir[2]))
							input.fw = 1
							SquirrelMotor.step(s, input, 1 / 60, cw)
						end
						local where = `{kind} at ({at[1]}, {at[2]}) running ({dir[1]}, {dir[2]})`
						t.truthy(wasInside, `{where}: starts inside`)
						t.falsy(Solid.core(drawn, s.x, s.z, s.y), `{where}: got out`)
						t.falsy(Solid.inside(drawn.hulls[1], s.x, s.z), `{where}: left the footprint`)
					end
				end
			end
			-- and out, the car is a wall again: back at its side, the body is held there
			local drawn = Solid.newSet()
			Solid.add(drawn, Solid.hull("sedan", MX, road, MZ, 0))
			local cw = Solid.squirrelWorld(town.world, drawn)
			local s = SquirrelMotor.new(MX + sedan.width / 2 - 0.5, ground, MZ)
			for i = 1, 360 do
				local input = SquirrelMotor.idleInput(yawToward(if i <= 120 then 1 else -1, 0))
				input.fw = 1
				SquirrelMotor.step(s, input, 1 / 60, cw)
			end
			t.truthy(s.x > MX + sedan.width / 2, `held at the side once out (x {s.x - MX})`)
			t.falsy(Solid.core(drawn, s.x, s.z, s.y), "not back inside")
		end
	)

	t.test("a car pulls up over a squirrel crossing its stop (80 ms): it walks out and crosses, 0 snaps", function()
		-- review 2026-11-18 (P4): the server's car stops first (no run-over); the drawn car arrives 0.26 s later over
		-- the body. Before: frozen inside the drawn car for 232 of 357 frames
		local zLine = MZ + 5.0
		for _, tgo in { 1.78, 1.83, 1.88 } do
			local car = driving(1, "sedan", MX, MZ - 16, 8, 2)
			local o = play(town, {
				cars = { car },
				start = SquirrelMotor.new(MX - 7, ground, zLine),
				keys = function(tt: number, state: State): SquirrelMotor.Input
					local goal = if tt < tgo then MX - 7 else MX + 9
					local input = SquirrelMotor.idleInput(yawToward(goal - state.x, zLine - state.z))
					if math.abs(goal - state.x) > 0.5 then
						input.fw = 1
						input.sprint = true
					end
					return input
				end,
				seconds = 6,
				lag = LINKS[1].lag,
				link = { latency = 0.08, jitter = 0.05, loss = 0 },
				seed = 7,
			})
			report(`pulls up over it, go {tgo}`, o)
			t.truthy(o.inside <= 15, `inside a drawn car at most a quarter second ({o.inside} frames)`)
			local last = o.trace[#o.trace]
			t.truthy(last[1] > MX + 8, `crossed (x {last[1] - MX})`)
			t.eq(o.result.snaps, 0, "snaps")
		end
	end)

	-- the server's fatal test on the squirrel's reported moves against the server's car, the client's motor meeting the
	-- car drawn `lag` behind: true when the car ran it over, and when
	local function runOver(
		keys: (tt: number, state: State) -> SquirrelMotor.Input,
		car: Car,
		lag: number
	): (boolean, number)
		local drawn = Solid.newSet()
		local cw = Solid.squirrelWorld(town.world, drawn)
		local swept = SweptCollision.new()
		local state = SquirrelMotor.new(MX - 6, ground, MZ)
		local road = ground - Units.st(0.18)
		local prevCar: { number }? = nil
		local prevBody: { number }? = nil
		local tt = 0
		while tt < 8 do
			Solid.clear(drawn)
			local dx, dz, dyaw = car.pose(tt - lag)
			Solid.add(drawn, Solid.hull(car.kind, dx, road, dz, dyaw))
			SquirrelMotor.step(state, keys(tt, state), 1 / 60, cw)
			tt += 1 / 60
			local x, z, yaw = car.pose(tt)
			local base = road + Units.st(0.04)
			local pose = {
				id = car.id,
				kind = car.kind,
				x = x,
				y = base,
				z = z,
				yaw = yaw,
				prevX = if prevCar then prevCar[1] else x,
				prevY = base,
				prevZ = if prevCar then prevCar[2] else z,
				prevYaw = yaw,
				visible = true,
				prevVisible = true,
			}
			prevCar = { x, z }
			local body = { state.x, state.y, state.z }
			local hits = swept:step({
				{
					id = "squirrel",
					x = body[1],
					y = body[2],
					z = body[3],
					prevX = if prevBody then prevBody[1] else body[1],
					prevY = if prevBody then prevBody[2] else body[2],
					prevZ = if prevBody then prevBody[3] else body[3],
				},
			}, { pose :: any }, 1 / 60)
			prevBody = body
			if #hits > 0 then
				return true, tt
			end
		end
		return false, tt
	end

	t.test(
		"a squirrel run over still dies: the server's car meets it (a drawn car stops a body, never a car)",
		function()
			-- a car that does not stop (the scripted car; the fleet's own brake for a squirrel ahead is unchanged), 12 st/s
			local car = driving(1, "sedan", MX, MZ - 40, 12)
			-- standing in the road: the squirrel runs to the lane's middle and waits
			local hit, at = runOver(toward({ { MX, MZ, 99 } }, false), car, 0.3)
			print(`      standing in the road: run over at t {string.format("%.2f", at)} s`)
			t.truthy(hit, "standing in the road")
			-- darting across just ahead of the car (it is drawn 0.3 s behind, so the client sees a clear road)
			hit, at = runOver(function(tt: number, state: State): SquirrelMotor.Input
				return toward({ { MX - 6, MZ, 2.3 }, { MX + 12, MZ, 99 } }, false)(tt, state)
			end, car, 0.3)
			print(`      darting across: run over at t {string.format("%.2f", at)} s`)
			t.truthy(hit, "darting across")
			-- a parked car never kills (v5.4: no displacement, no hit), however hard the squirrel presses on it
			hit = runOver(toward({ { MX + 12, MZ, 99 } }, true), parked(1, "sedan", MX, MZ, math.pi / 2), 0.3)
			t.falsy(hit, "a parked car")
		end
	)

	t.test("the cost: 25 cars, the client's motor and the server's validator rays (Lune)", function()
		-- 25 cars spread over 300 x 300 studs, as many as the fleet has
		local set = Solid.newSet()
		local seed = 3
		local function rnd(): number
			seed = (seed * 1103515245 + 12345) % 2147483648
			return seed / 2147483648
		end
		local kinds = { "sedan", "sedan", "rv", "dump_truck", "trolley", "ice_cream_van", "motorcycle", "ambulance" }
		for i = 1, 25 do
			Solid.add(set, Solid.hull(kinds[(i % #kinds) + 1], rnd() * 300, 0, rnd() * 300, rnd() * 6.28))
		end
		local N = 200000
		local t0 = os.clock()
		local any = 0
		for _ = 1, N do
			if Solid.body(set, rnd() * 300, rnd() * 300, 0.45, BODY.HALF) then
				any += 1
			end
		end
		local bodyUs = (os.clock() - t0) / N * 1e6
		t0 = os.clock()
		for _ = 1, N do
			local x, z = rnd() * 300, rnd() * 300
			if Solid.ray(set, x, 1.1, z, (rnd() - 0.5) * 8, 0, (rnd() - 0.5) * 8) then
				any += 1
			end
		end
		local rayUs = (os.clock() - t0) / N * 1e6
		-- the motor asks its wall test about twice per 0.24-stud step and axis: a sprinting frame ~ 12 asks, plus a
		-- ground ask per substep
		print(
			`      one body test against 25 cars {string.format("%.2f", bodyUs)} us, one ray {string.format(
				"%.2f",
				rayUs
			)} us ({any} hits)`
		)
		print(
			`      client: ~16 asks a frame = {string.format("%.3f", 16 * bodyUs / 1000)} ms; server: worst packet 97 rays = {string.format(
				"%.3f",
				97 * rayUs / 1000
			)} ms, a typical packet ~8 rays x 20 Hz x 30 players = {string.format("%.3f", 8 * 20 * 30 * rayUs / 1000)} ms a second`
		)
		t.truthy(bodyUs < 20 and rayUs < 20, "cheap")
	end)
end
