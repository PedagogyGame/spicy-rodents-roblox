--!strict
-- ServerScriptService.Server.Actors.Possession
-- THE single handoff mechanism (BUILD_PLAN §1.5, D1, D3; spike S2).
--   possess(player, actor): stream around the body first (the only yield), then in one server
--     step: brain:suspend() -> body to player mode with the snapshot's momentum -> network owner
--     -> player.Character = body -> ledger -> Granted(payload). Nothing about the animation
--     changes hands (D3): every client animates every body locally, so the stride continues.
--   release(player, why): ledger -> Character = nil -> network owner nil -> body anchored (AI
--     mode) -> brain:resume(last validated pose). On PlayerRemoving it runs before anything else.
--   swap(player, toActor): stream to the new body, then release + possess in one server step.
--   recover(player): the Roblox menu's Reset, routed here; never kills or respawns a body.
-- Players are anything with `UserId` (and, in the engine, a real Player): the S2 soak drives the
-- same code with PlayerLike stubs through an injected `Engine`.
-- W1 hooks (`onHandoff`): SweptCollision.markTeleported(actor), MoveValidator.reset(actor),
-- AvatarBlendService.apply(actor, player) (§1.5 steps 6-7).
-- No side effects on require.
-- Interface: new(deps) -> Service; Service:possess, release, swap, recover, actorOf(player),
-- controllerOf(actor), check() -> (ok, errors), stats

local Import = require("../Import")
local PossessionState =
	Import.shared("Actors/PossessionState") :: typeof(require("../../shared/Actors/PossessionState"))
local ActorServiceT = require("./ActorService")

type Actor = ActorServiceT.Actor
type Registry = ActorServiceT.Registry
-- Shapes of Shared/Actors/PossessionState.Snapshot and GrantPayload (exported types do not
-- cross the Import shim, so they are restated loosely here).
type Snapshot = { [string]: any }
type GrantPayload = { [string]: any }

export type Engine = {
	-- Ask the client to stream around a position before the handoff (may yield; must not error).
	streamAround: (player: any, x: number, y: number, z: number, timeout: number) -> (),
	-- root:SetNetworkOwner(player or nil). Errors propagate (the caller rolls back).
	setOwner: (root: any, player: any?) -> (),
	-- player.Character = model or nil.
	setCharacter: (player: any, model: any?) -> (),
	-- The body's root part (the assembly whose owner is set).
	rootOf: (body: any) -> any,
	-- Mark the body with its driver for clients (attribute DriverUserId; 0 = AI).
	markDriver: (body: any, userId: number) -> (),
	-- Moves a body to a safe pose (recovery); never changes health.
	teleport: (body: any, x: number, y: number, z: number, yaw: number) -> (),
	-- Seconds: os.clock in the engine, an injected clock in tests.
	now: () -> number,
	-- Server time stamped into the payload (workspace:GetServerTimeNow()).
	serverTime: () -> number,
}

export type Deps = {
	actors: Registry,
	engine: Engine?,
	streamTimeout: number?, -- seconds (default 2)
	onGranted: ((player: any, payload: GrantPayload) -> ())?,
	onReleased: ((player: any, actorId: string, why: string) -> ())?,
	onHandoff: ((actor: Actor, player: any?, kind: "possess" | "release") -> ())?,
	-- Recovery target for a body (default: where it stands, lifted 3 studs).
	safePose: ((actor: Actor) -> (number, number, number, number))?,
}

export type Stats = {
	possessed: number,
	released: number,
	swapped: number,
	recovered: number,
	refused: number,
	rolledBack: number,
	maxPossessMs: number,
	maxReleaseMs: number,
}

export type Service = {
	deps: Deps,
	engine: Engine,
	ledger: { byActor: { [string]: number }, byDriver: { [number]: string } },
	drivers: { [number]: any }, -- userId -> player
	owners: { [string]: number }, -- actorId -> userId whose SetNetworkOwner succeeded (bookkeeping)
	stats: Stats,
	possess: (self: Service, player: any, actor: Actor) -> (boolean, string?),
	release: (self: Service, player: any, why: string?) -> string?,
	swap: (self: Service, player: any, toActor: Actor) -> (boolean, string?),
	recover: (self: Service, player: any) -> boolean,
	actorOf: (self: Service, player: any) -> Actor?,
	controllerOf: (self: Service, actor: Actor) -> any,
	check: (self: Service) -> (boolean, { string }),
}

local Possession = {}

-- Engine implementation (real Players and Instances).
function Possession.engine(): Engine
	return {
		streamAround = function(player: any, x: number, y: number, z: number, timeout: number)
			pcall(function()
				(player :: Player):RequestStreamAroundAsync(Vector3.new(x, y, z), timeout)
			end)
		end,
		setOwner = function(root: any, player: any?)
			(root :: BasePart):SetNetworkOwner(player :: Player?)
		end,
		setCharacter = function(player: any, model: any?)
			(player :: Player).Character = model :: Model?
		end,
		rootOf = function(body: any): any
			return (body :: Model).PrimaryPart
		end,
		markDriver = function(body: any, userId: number)
			local model = body :: Model
			model:SetAttribute(PossessionState.ATTR.Driver, userId)
			-- a person a player drives carries the player's name; back to the AI, no label (stubs
			-- in engine tests have no Player, so their bodies stay unlabelled)
			local player = if userId ~= 0 then game:GetService("Players"):GetPlayerByUserId(userId) else nil
			ActorServiceT.nameLabel(model, if player then player.DisplayName else nil)
		end,
		teleport = function(body: any, x: number, y: number, z: number, yaw: number)
			local model = body :: Model
			local root = model.PrimaryPart
			model:PivotTo(CFrame.new(x, y, z) * CFrame.Angles(0, yaw, 0))
			if root and not root.Anchored then
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
			end
		end,
		now = os.clock,
		serverTime = function(): number
			return workspace:GetServerTimeNow()
		end,
	}
end

local function keyOf(player: any): number
	local id = player.UserId
	if type(id) ~= "number" then
		error("Possession: player has no numeric UserId")
	end
	return id
end

function Possession.new(deps: Deps): Service
	local engine = deps.engine or Possession.engine()
	local service = {
		deps = deps,
		engine = engine,
		ledger = PossessionState.newLedger(),
		drivers = {},
		owners = {},
		stats = {
			possessed = 0,
			released = 0,
			swapped = 0,
			recovered = 0,
			refused = 0,
			rolledBack = 0,
			maxPossessMs = 0,
			maxReleaseMs = 0,
		},
	} :: Service
	local timeout = deps.streamTimeout or 2

	-- The release half, no yields. Returns the released actor id.
	local function releaseNow(self: Service, player: any, why: string): string?
		local t0 = engine.now()
		local key = keyOf(player)
		local actorId = PossessionState.unbind(self.ledger, key)
		self.drivers[key] = nil
		if actorId == nil then
			return nil
		end
		local actor = deps.actors:get(actorId) :: Actor
		-- last validated state: the body's pose as the server holds it (W1: MoveValidator's last
		-- accepted state, which the client cannot push past the validator)
		local x, y, z = deps.actors:poseOf(actor)
		local ok, err = pcall(function()
			if player.Character == actor.body then
				engine.setCharacter(player, nil)
			end
			engine.setOwner(engine.rootOf(actor.body), nil)
		end)
		self.owners[actorId] = nil
		deps.actors:setBodyMode(actor, "ai", nil)
		engine.markDriver(actor.body, 0)
		actor.driver = nil
		actor.releasedAt = engine.now()
		actor.brain.resume(x, y, z)
		self.stats.released += 1
		local ms = (engine.now() - t0) * 1000
		if ms > self.stats.maxReleaseMs then
			self.stats.maxReleaseMs = ms
		end
		if deps.onHandoff then
			deps.onHandoff(actor, nil, "release")
		end
		if deps.onReleased then
			deps.onReleased(player, actorId, why)
		end
		if not ok then
			-- the body is back in AI hands either way; surface the engine error to the caller's log
			warn(`Possession.release: engine step failed for {actorId}: {err}`)
		end
		return actorId
	end

	-- The possess half, no yields. Assumes the player drives nothing and the actor is free.
	local function possessNow(self: Service, player: any, actor: Actor): (boolean, string?)
		local t0 = engine.now()
		local key = keyOf(player)
		local raw = actor.brain.suspend()
		local x, y, z, yaw = deps.actors:poseOf(actor)
		local snapshot: Snapshot = {
			x = x,
			y = y,
			z = z,
			yaw = yaw,
			vx = raw.vx or 0,
			vy = raw.vy or 0,
			vz = raw.vz or 0,
			mode = raw.mode or "idle",
			clip = raw.clip,
			clipT = raw.clipT,
			brain = raw.brain,
		}
		local ok, err = pcall(function()
			deps.actors:setBodyMode(actor, "player", snapshot :: any)
			engine.setOwner(engine.rootOf(actor.body), player)
			self.owners[actor.id] = key
			engine.setCharacter(player, actor.body)
		end)
		if not ok then
			-- roll back to AI so a failed handoff never strands a body
			self.owners[actor.id] = nil
			pcall(function()
				if player.Character == actor.body then
					engine.setCharacter(player, nil)
				end
				engine.setOwner(engine.rootOf(actor.body), nil)
			end)
			deps.actors:setBodyMode(actor, "ai", nil)
			actor.brain.resume(x, y, z)
			self.stats.rolledBack += 1
			return false, `possess failed: {err}`
		end
		PossessionState.bind(self.ledger, key, actor.id)
		self.drivers[key] = player
		engine.markDriver(actor.body, key)
		actor.driver = player
		actor.possessions += 1
		self.stats.possessed += 1
		if deps.onHandoff then
			deps.onHandoff(actor, player, "possess")
		end
		local ms = (engine.now() - t0) * 1000
		if ms > self.stats.maxPossessMs then
			self.stats.maxPossessMs = ms
		end
		if deps.onGranted then
			deps.onGranted(player, {
				actorId = actor.id,
				species = actor.species,
				snapshot = snapshot,
				serverTime = engine.serverTime(),
				holdSeconds = PossessionState.HOLD_SECONDS,
			})
		end
		return true, nil
	end

	local function refuse(self: Service, why: string): (boolean, string?)
		self.stats.refused += 1
		return false, why
	end

	local function free(self: Service, actor: Actor): boolean
		return PossessionState.driverOf(self.ledger, actor.id) == nil
	end

	function service.possess(self: Service, player: any, actor: Actor): (boolean, string?)
		if not actor.possessable then
			return refuse(self, "not possessable")
		end
		local key = keyOf(player)
		if PossessionState.driverOf(self.ledger, actor.id) == key then
			return true, nil -- already driving it
		end
		if not free(self, actor) then
			return refuse(self, "body is driven")
		end
		local x, y, z = deps.actors:poseOf(actor)
		engine.streamAround(player, x, y, z, timeout) -- the only yield
		-- re-validate after the yield: the world may have moved on
		if not free(self, actor) then
			return refuse(self, "body was taken while streaming")
		end
		if PossessionState.actorOf(self.ledger, key) ~= nil then
			releaseNow(self, player, "swap")
			self.stats.swapped += 1
		end
		return possessNow(self, player, actor)
	end

	function service.release(self: Service, player: any, why: string?): string?
		return releaseNow(self, player, why or "release")
	end

	function service.swap(self: Service, player: any, toActor: Actor): (boolean, string?)
		return self:possess(player, toActor)
	end

	function service.recover(self: Service, player: any): boolean
		local actor = self:actorOf(player)
		if actor == nil then
			return false
		end
		local x, y, z, yaw
		if deps.safePose then
			x, y, z, yaw = deps.safePose(actor)
		else
			x, y, z, yaw = deps.actors:poseOf(actor)
			y += 3
		end
		engine.teleport(actor.body, x, y, z, yaw)
		self.stats.recovered += 1
		return true
	end

	function service.actorOf(self: Service, player: any): Actor?
		local id = PossessionState.actorOf(self.ledger, keyOf(player))
		return if id then deps.actors:get(id) else nil
	end

	function service.controllerOf(self: Service, actor: Actor): any
		local key = PossessionState.driverOf(self.ledger, actor.id)
		return if key then self.drivers[key] else "ai"
	end

	-- Every invariant the S2 soak asserts after each operation.
	function service.check(self: Service): (boolean, { string })
		local ok, errors = PossessionState.check(self.ledger)
		if not ok then
			return false, errors
		end
		for _, actor in deps.actors:all() do
			local key = PossessionState.driverOf(self.ledger, actor.id)
			if not deps.actors.ops.alive(actor.body) then
				table.insert(errors, `{actor.id}: body gone`)
			end
			if key then
				local player = self.drivers[key]
				if actor.mode ~= "player" then
					table.insert(errors, `{actor.id}: driven by {key} but mode {actor.mode}`)
				end
				if actor.driver ~= player then
					table.insert(errors, `{actor.id}: actor.driver mismatch`)
				end
				if player == nil or player.Character ~= actor.body then
					table.insert(errors, `{actor.id}: driver {key} Character is not the body`)
				end
				if self.owners[actor.id] ~= key then
					table.insert(errors, `{actor.id}: network owner {self.owners[actor.id]} ~= driver {key}`)
				end
			else
				if actor.mode ~= "ai" then
					table.insert(errors, `{actor.id}: free but mode {actor.mode}`)
				end
				if actor.driver ~= nil then
					table.insert(errors, `{actor.id}: free but actor.driver set`)
				end
				if self.owners[actor.id] ~= nil then
					table.insert(errors, `{actor.id}: free but owner {self.owners[actor.id]}`)
				end
			end
		end
		return #errors == 0, errors
	end

	return service
end

return Possession
