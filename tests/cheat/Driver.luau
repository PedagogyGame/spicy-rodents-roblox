--!strict
-- tests/cheat/Driver: an honest scripted squirrel for the S3 harness. It produces SquirrelMotor inputs
-- that exercise every movement path a real player uses (routes_movement §7 state machine): ground
-- running and sprinting to a trunk, the walk-in grab, climbing, A/D fork choice and the W auto-take,
-- bough runs to the tip, the Space leap and the Q drop, E grabs from the ground and from the air,
-- pole-top auto-switches onto wires, E transfers at stalls, downspout -> gutter bridge -> roof ridge,
-- mid-air pounces. It only reads the public motor state and events, never the validator, so its
-- traces are honest by construction; the validator must accept all of them (0 false positives).
local Motion = require("@shared/Routes/Motion")
local Registry = require("@shared/Routes/Registry")
local SquirrelMotor = require("@shared/Movement/SquirrelMotor")
local Units = require("@shared/Config/Units")

local Driver = {}
Driver.__index = Driver

export type Rng = { next: () -> number } -- uniform [0, 1)

export type Driver = typeof(setmetatable(
	{} :: {
		world: SquirrelMotor.World,
		rng: Rng,
		targets: { Registry.Route },
		target: Registry.Route?,
		mode: string,
		timer: number,
		stuck: number,
		cameraYaw: number,
		sprint: boolean,
		wantFork: boolean,
		lastRoute: number?,
		plan: string, -- "leap" | "drop" | "transfer" at the end of the current rail
		pounceAt: number,
		log: { [string]: number },
	},
	Driver
))

-- Trunks worth climbing: every trunk (trees, poles, downspouts) with a foot inside `radius` of
-- `(cx, cz)` (studs). Trees and poles are reached by walking in; downspouts by E.
function Driver.targetsAround(world: SquirrelMotor.World, cx: number, cz: number, radius: number): { Registry.Route }
	local out: { Registry.Route } = {}
	for _, r in world.registry:all() do
		if r.kind == "trunk" then
			local foot = world.registry:foot(r)
			if math.sqrt((foot.x - cx) ^ 2 + (foot.z - cz) ^ 2) <= radius then
				table.insert(out, r)
			end
		end
	end
	return out
end

function Driver.new(world: SquirrelMotor.World, rng: Rng, targets: { Registry.Route }): Driver
	local self = setmetatable({
		world = world,
		rng = rng,
		targets = targets,
		target = nil,
		mode = "ground",
		timer = 0,
		stuck = 0,
		cameraYaw = math.pi,
		sprint = false,
		wantFork = false,
		lastRoute = nil,
		plan = "leap",
		pounceAt = 0,
		log = {},
	}, Driver)
	return self
end

local function count(self: Driver, key: string)
	self.log[key] = (self.log[key] or 0) + 1
end

local function pick<T>(self: Driver, list: { T }): T
	return list[math.floor(self.rng.next() * #list) + 1]
end

local function chooseTarget(self: Driver, state: SquirrelMotor.State)
	-- prefer nearby trunks so the ground legs stay short; sometimes wander to a far one
	local best: { Registry.Route } = {}
	local radius = if self.rng.next() < 0.2 then Units.st(60) else Units.st(25)
	for _, r in self.targets do
		local foot = self.world.registry:foot(r)
		local d = math.sqrt((foot.x - state.x) ^ 2 + (foot.z - state.z) ^ 2)
		if d > Units.st(1.5) and d <= radius and r.id ~= self.lastRoute then
			table.insert(best, r)
		end
	end
	if #best == 0 then
		best = self.targets
	end
	self.target = pick(self, best)
	self.timer = 0
	self.stuck = 0
	self.sprint = self.rng.next() < 0.5
	count(self, "targets")
end

local function yawToward(fromX: number, fromZ: number, toX: number, toZ: number): number
	-- camera forward = (-sin yaw, -cos yaw) must point from -> to
	return math.atan2(-(toX - fromX), -(toZ - fromZ))
end

-- input(state, events, dt) -> Input for this frame.
function Driver.input(
	self: Driver,
	state: SquirrelMotor.State,
	events: { SquirrelMotor.Event },
	dt: number
): SquirrelMotor.Input
	local inp = SquirrelMotor.idleInput(self.cameraYaw)
	local world = self.world
	local rng = self.rng
	self.timer += dt
	self.pounceAt -= dt

	for _, e in events do
		if
			e.kind == "attach"
			or e.kind == "transfer"
			or e.kind == "autoSwitch"
			or e.kind == "forkTaken"
			or e.kind == "branchHop"
		then
			count(self, e.kind)
			self.timer = 0
			self.stuck = 0
			self.wantFork = rng.next() < 0.7
			local r = world.registry:get(state.routeId :: number)
			if r and r.kind == "trunk" then
				self.plan = "climb"
			else
				local roll = rng.next()
				self.plan = if roll < 0.55 then "leap" elseif roll < 0.75 then "drop" else "transfer"
			end
		elseif e.kind == "railEnd" then
			self.stuck += dt
		elseif e.kind == "land" then
			count(self, "land")
			self.mode = "ground"
			chooseTarget(self, state)
		elseif e.kind == "leap" or e.kind == "drop" or e.kind == "pounce" then
			count(self, e.kind)
		end
	end

	local route = if state.routeId then world.registry:get(state.routeId :: number) else nil

	if route then
		self.lastRoute = route.id
		-- camera behind the body so W keeps the current travel direction
		self.cameraYaw = state.yaw + math.pi
		inp.cameraYaw = self.cameraYaw
		inp.fw = 1
		inp.sprint = self.sprint
		if route.kind == "trunk" then
			-- choose a bough once (A or D), then let the W auto-take do the rest; downspouts have no forks
			if self.wantFork and self.timer > 0.4 and not state.pendingFork and #world.graph:forks(route.id) > 0 then
				inp.choose = if rng.next() < 0.5 then 1 else -1
				self.wantFork = false
				count(self, "choose")
			end
			if self.stuck > 0.5 then
				-- top of a pole without a clear switch, or a downspout top: try E, then leap
				if self.stuck < 1.2 then
					inp.grab = rng.next() < 0.15
					-- turning the camera resolves a junction stall
					self.cameraYaw += (rng.next() - 0.5) * 1.5
					inp.cameraYaw = self.cameraYaw
				else
					inp.leap = true
					self.stuck = 0
				end
			end
		else
			-- boughs, wires, bridges, roofs, fences: run to the end, then do the plan
			if route.kind == "branch" and state.railT < 0.2 and self.timer > 0.3 and rng.next() < 0.004 then
				inp.choose = if rng.next() < 0.5 then 1 else -1
				count(self, "sidestep")
			end
			if self.stuck > 0.15 then
				if self.plan == "transfer" and self.stuck < 0.9 then
					inp.grab = self.stuck > 0.3 and rng.next() < 0.3
					self.cameraYaw += (rng.next() - 0.5) * 1.2
					inp.cameraYaw = self.cameraYaw
				elseif self.plan == "drop" then
					inp.drop = true
					self.stuck = 0
				else
					inp.leap = true
					self.stuck = 0
				end
			end
			-- an occasional voluntary leap from a wire or roof mid-span
			if self.timer > 2.5 and rng.next() < 0.002 then
				inp.leap = true
				self.timer = 0
			end
		end
		return inp
	end

	-- airborne: drift with the camera, sometimes pounce (the motor enforces the 0.7 s cooldown)
	if not state.grounded then
		inp.cameraYaw = self.cameraYaw
		if self.pounceAt <= 0 and rng.next() < 0.01 then
			inp.pounce = true
			inp.cameraPitch = (rng.next() - 0.5) * 1.2
			self.pounceAt = 1.0
		end
		-- an E in the air near a route: the "leap then grab a wire" mechanic
		if rng.next() < 0.02 then
			local near = Motion.nearestRoute(world, state.x, state.y, state.z, Motion.C.airGrab)
			if near then
				inp.grab = true
				count(self, "airGrabTry")
			end
		end
		return inp
	end

	-- ground: walk to the target trunk's foot with the camera behind the squirrel
	if not self.target then
		chooseTarget(self, state)
	end
	local target = self.target :: Registry.Route
	local foot = world.registry:foot(target)
	local d = math.sqrt((foot.x - state.x) ^ 2 + (foot.z - state.z) ^ 2)
	self.cameraYaw = yawToward(state.x, state.z, foot.x, foot.z)
	inp.cameraYaw = self.cameraYaw
	inp.fw = 1
	inp.sprint = self.sprint and d > Units.st(4)
	if d < Units.st(2.6) then
		-- excluded trunks (downspouts, ladders) and awkward approaches need E
		if target.flags.autoGrabExcluded or self.timer > 1.5 then
			inp.grab = rng.next() < 0.2
		end
	end
	if self.timer > 6 then
		-- give up on this target: leap somewhere else and pick another
		inp.leap = rng.next() < 0.5
		chooseTarget(self, state)
	end
	return inp
end

return Driver
