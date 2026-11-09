--!strict
-- ServerScriptService.Server.Actors.ActorService
-- Actor registry and lifecycle; bodies created once, never destroyed (BUILD_PLAN §1.4, §1.5, D1).
-- W0 (spike S2) implements the registry and body modes; spawn/query/nearest/kill and the
-- Possessed/Released/Died signals arrive with W1's Population wiring.
--   AI mode     : root anchored, moved kinematically (BulkMoveTo on roots, rule 4); Humanoids run
--                 with EvaluateStateMachine = false.
--   player mode : root unanchored (network ownership needs an unanchored assembly), Humanoid state
--                 machine on, momentum carried from the brain's snapshot.
-- Instances are touched only through `BodyOps`, so the Lune unit tests drive the same code with
-- table bodies. Requiring has no side effects.
-- Interface: new(ops?) -> Registry; Registry:register(actor), get(id), all(), count(),
-- setBodyMode(actor, mode, snapshot?), poseOf(actor); engineOps(); signals via onModeChanged.

export type Brain = {
	-- Freezes the brain and returns snapshot fields (x, z, yaw, vx, vz, mode, brain, clip, clipT).
	suspend: () -> { [string]: any },
	-- Re-enters AI control from the body's last validated pose (studs).
	resume: (x: number, y: number, z: number) -> (),
}

export type Actor = {
	id: string,
	species: string,
	variant: string,
	body: any, -- Model in the engine; a table in Lune tests
	brain: Brain,
	possessable: boolean,
	mode: "ai" | "player",
	driver: any?, -- the Player (or PlayerLike) while possessed
	possessions: number,
	releasedAt: number?,
}

export type BodyOps = {
	-- Current pivot of the body: position (studs) and yaw (radians about +Y).
	pose: (body: any) -> (number, number, number, number),
	-- Applies the physical side of a body mode. `snapshot` carries vx, vy, vz on "player".
	setMode: (body: any, mode: "ai" | "player", snapshot: { [string]: any }?) -> (),
	-- True while the body Instance still exists in the world (never destroyed: the soak checks it).
	alive: (body: any) -> boolean,
}

export type Registry = {
	ops: BodyOps,
	byId: { [string]: Actor },
	order: { Actor },
	register: (self: Registry, actor: Actor) -> Actor,
	get: (self: Registry, id: string) -> Actor?,
	all: (self: Registry) -> { Actor },
	count: (self: Registry) -> number,
	setBodyMode: (self: Registry, actor: Actor, mode: "ai" | "player", snapshot: { [string]: any }?) -> (),
	poseOf: (self: Registry, actor: Actor) -> (number, number, number, number),
	onModeChanged: ((actor: Actor, mode: "ai" | "player") -> ())?,
}

local ActorService = {}

local function humanoidOf(body: Model): Humanoid?
	return body:FindFirstChildOfClass("Humanoid")
end

local function rootOf(body: Model): BasePart
	return body.PrimaryPart or error(`ActorService: body {body:GetFullName()} has no PrimaryPart`)
end

-- Engine BodyOps (Instances). Humanoid states other than Dead stay enabled; Dead is disabled on
-- the server here and on the owning client by the controller, so Reset can never kill a body.
function ActorService.engineOps(): BodyOps
	return {
		pose = function(body: any): (number, number, number, number)
			local cf = (body :: Model):GetPivot()
			local look = cf.LookVector
			return cf.X, cf.Y, cf.Z, math.atan2(-look.X, -look.Z)
		end,
		setMode = function(body: any, mode: "ai" | "player", snapshot: { [string]: any }?)
			local model = body :: Model
			local root = rootOf(model)
			local humanoid = humanoidOf(model)
			if mode == "player" then
				root.Anchored = false
				if humanoid then
					humanoid:SetStateEnabled(Enum.HumanoidStateType.Dead, false)
					humanoid.EvaluateStateMachine = true
					humanoid.AutoRotate = true
				end
				if snapshot then
					root.AssemblyLinearVelocity = Vector3.new(snapshot.vx or 0, snapshot.vy or 0, snapshot.vz or 0)
				end
			else
				if humanoid then
					humanoid:Move(Vector3.zero)
					humanoid.EvaluateStateMachine = false
					humanoid.AutoRotate = false
				end
				-- Upright at the current pivot: a released player body may be mid-jump or tilted.
				local cf = model:GetPivot()
				local look = cf.LookVector
				local yaw = math.atan2(-look.X, -look.Z)
				root.Anchored = true
				root.AssemblyLinearVelocity = Vector3.zero
				root.AssemblyAngularVelocity = Vector3.zero
				model:PivotTo(CFrame.new(cf.Position) * CFrame.Angles(0, yaw, 0))
			end
		end,
		alive = function(body: any): boolean
			local model = body :: Model
			return model.Parent ~= nil and model.PrimaryPart ~= nil and model.PrimaryPart.Parent == model
		end,
	}
end

function ActorService.new(ops: BodyOps?): Registry
	local registry = {
		ops = ops or ActorService.engineOps(),
		byId = {},
		order = {},
	} :: Registry

	function registry.register(self: Registry, actor: Actor): Actor
		if self.byId[actor.id] then
			error(`ActorService.register: duplicate actor id {actor.id}`)
		end
		self.byId[actor.id] = actor
		table.insert(self.order, actor)
		return actor
	end

	function registry.get(self: Registry, id: string): Actor?
		return self.byId[id]
	end

	function registry.all(self: Registry): { Actor }
		return self.order
	end

	function registry.count(self: Registry): number
		return #self.order
	end

	function registry.setBodyMode(self: Registry, actor: Actor, mode: "ai" | "player", snapshot: { [string]: any }?)
		self.ops.setMode(actor.body, mode, snapshot)
		actor.mode = mode
		local cb = self.onModeChanged
		if cb then
			cb(actor, mode)
		end
	end

	function registry.poseOf(self: Registry, actor: Actor): (number, number, number, number)
		return self.ops.pose(actor.body)
	end

	return registry
end

-- Convenience constructor with the defaults every W0 caller wants.
function ActorService.actor(
	id: string,
	species: string,
	variant: string,
	body: any,
	brain: Brain,
	possessable: boolean?
): Actor
	return {
		id = id,
		species = species,
		variant = variant,
		body = body,
		brain = brain,
		possessable = possessable ~= false,
		mode = "ai",
		driver = nil,
		possessions = 0,
		releasedAt = nil,
	}
end

return ActorService
