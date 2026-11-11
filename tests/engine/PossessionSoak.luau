--!strict
-- ServerStorage.EngineTests.PossessionSoak (also required by tests/unit/possession.spec.luau)
-- Spike S2's automated possess / release / swap / leave / recover soak (BUILD_PLAN §4.3 S2:
-- "500 automated possess/release cycles with fake drivers: 0 leaked bodies, 0 errors, network
-- owner always matches driver; on leave the AI resumes within 0.2 s"). Pure driver: it only calls
-- the Possession service, RoleService and the injected AI stepper, so Lune (table bodies) and
-- the engine (real Models, PlayerLike stubs) run the same sequence for the same seed.
-- Interface: run(opts) -> Result; capCheck(roles, makePlayer, n) -> CapResult

export type PlayerLike = { UserId: number, Name: string, Character: any, kicked: string? }

export type Opts = {
	possession: any, -- Server/Actors/Possession Service
	actors: any, -- Server/Actors/ActorService Registry
	roles: any, -- Server/Roles/RoleService Roles
	players: { PlayerLike },
	cycles: number?, -- possess/release pairs to complete (default 500)
	seed: number?,
	dt: number?, -- simulated frame (default 1/60)
	advance: (dt: number) -> (), -- advances the injected clock
	stepAI: (dt: number) -> (), -- one AI frame over every AI-mode actor
	aiTicks: (actor: any) -> number, -- brain ticks so far (resume probe)
	bodyCount: (() -> number)?, -- independent count of body Instances (engine: Bodies folder)
	maxOps: number?,
}

export type Result = {
	ok: boolean,
	ops: number,
	possessed: number,
	released: number,
	swaps: number,
	leaves: number,
	recovers: number,
	refusedAsExpected: number,
	errors: { string },
	invariantFailures: { string },
	leakedBodies: number,
	bodyCountStart: number,
	bodyCountEnd: number,
	resumeMaxSeconds: number,
	resumeSamples: number,
	resumeOver200ms: number,
	stats: { [string]: any },
}

local Soak = {}

local function rng(seed: number): () -> number
	local s = seed % 2147483647
	if s <= 0 then
		s += 2147483646
	end
	return function(): number
		s = (s * 48271) % 2147483647
		return s / 2147483647
	end
end

function Soak.run(o: Opts): Result
	local rand = rng(o.seed or 20261109)
	local dt = o.dt or 1 / 60
	local target = o.cycles or 500
	local maxOps = o.maxOps or target * 20
	local possession, actors, roles = o.possession, o.actors, o.roles
	local joined: { [number]: boolean } = {}
	local errors: { string } = {}
	local invariantFailures: { string } = {}
	local counts = { swaps = 0, leaves = 0, recovers = 0, refused = 0 }
	-- actor id -> { ticks at release, frames since release }
	local pending: { [string]: { ticks: number, frames: number } } = {}
	local resumeMax, resumeSamples, resumeOver = 0, 0, 0
	local function bodies(): number
		return if o.bodyCount then o.bodyCount() else actors:count()
	end
	local startCount = bodies()

	local function freeActors(): { any }
		local out = {}
		for _, a in actors:all() do
			if a.possessable and possession:controllerOf(a) == "ai" then
				table.insert(out, a)
			end
		end
		return out
	end

	local function markReleased(id: string?)
		if id then
			local a = actors:get(id)
			pending[id] = { ticks = o.aiTicks(a), frames = 0 }
		end
	end

	local function frame()
		o.advance(dt)
		o.stepAI(dt)
		for id, p in pending do
			p.frames += 1
			local a = actors:get(id)
			if a.mode ~= "ai" then
				pending[id] = nil -- re-possessed before its first AI frame: not a resume sample
			elseif o.aiTicks(a) > p.ticks then
				local secs = p.frames * dt
				resumeSamples += 1
				resumeMax = math.max(resumeMax, secs)
				if secs > 0.2 + 1e-9 then
					resumeOver += 1
				end
				pending[id] = nil
			end
		end
	end

	local ops = 0
	while (possession.stats.released < target or possession.stats.possessed < target) and ops < maxOps do
		ops += 1
		local p = o.players[math.floor(rand() * #o.players) + 1]
		local r = rand()
		local ok, err = pcall(function(): ...any
			if not joined[p.UserId] then
				joined[p.UserId] = true
				roles:onJoin(p)
				return
			end
			local current = possession:actorOf(p)
			if r < 0.35 then
				local free = freeActors()
				if #free > 0 then
					local before = current and current.id
					local a = free[math.floor(rand() * #free) + 1]
					local done = possession:possess(p, a)
					if done and before then
						counts.swaps += 1
						markReleased(before)
					end
				end
			elseif r < 0.6 then
				markReleased(possession:release(p, "release"))
			elseif r < 0.7 then
				if current then
					possession:recover(p)
					counts.recovers += 1
				end
			elseif r < 0.82 then
				local id = current and current.id
				roles:onLeave(p)
				joined[p.UserId] = nil
				counts.leaves += 1
				markReleased(id)
			else
				-- try to take a body someone else drives: must be refused, nothing may change
				for _, a in actors:all() do
					local c = possession:controllerOf(a)
					if c ~= "ai" and c ~= p then
						local done = possession:possess(p, a)
						if done then
							error("possessed a body another player drives")
						end
						counts.refused += 1
						break
					end
				end
			end
		end)
		if not ok then
			table.insert(errors, `op {ops}: {err}`)
		end
		local good, why = possession:check()
		if not good then
			for _, w in why do
				if #invariantFailures < 50 then
					table.insert(invariantFailures, `op {ops}: {w}`)
				end
			end
		end
		for _ = 1, 1 + math.floor(rand() * 3) do
			frame()
		end
	end
	-- everyone leaves at the end: every body must be back in AI hands
	for _, p in o.players do
		if joined[p.UserId] then
			local id = possession:actorOf(p)
			roles:onLeave(p)
			markReleased(id and id.id)
		end
	end
	for _ = 1, 30 do
		frame()
	end
	for _, a in actors:all() do
		if a.mode ~= "ai" or possession:controllerOf(a) ~= "ai" then
			table.insert(invariantFailures, `end: {a.id} still driven`)
		end
		if not actors.ops.alive(a.body) then
			table.insert(invariantFailures, `end: {a.id} body gone`)
		end
	end
	for id in pending do
		table.insert(invariantFailures, `end: {id} AI never resumed`)
	end
	local endCount = bodies()
	local result: Result = {
		ok = false,
		ops = ops,
		possessed = possession.stats.possessed,
		released = possession.stats.released,
		swaps = counts.swaps,
		leaves = counts.leaves,
		recovers = counts.recovers,
		refusedAsExpected = counts.refused,
		errors = errors,
		invariantFailures = invariantFailures,
		leakedBodies = math.abs(endCount - startCount),
		bodyCountStart = startCount,
		bodyCountEnd = endCount,
		resumeMaxSeconds = resumeMax,
		resumeSamples = resumeSamples,
		resumeOver200ms = resumeOver,
		stats = possession.stats,
	}
	result.ok = #errors == 0
		and #invariantFailures == 0
		and result.leakedBodies == 0
		and resumeOver == 0
		and result.possessed >= target
		and result.released >= target
	return result
end

export type CapResult = { ok: boolean, admitted: number, kicked: number, kickedHadBody: boolean, message: string? }

-- n arrivals; with the 49 cap the 50th (and later) are kicked before any body is assigned.
function Soak.capCheck(roles: any, possession: any, makePlayer: (i: number) -> PlayerLike, n: number): CapResult
	local players = {}
	local kickedHadBody = false
	local message: string? = nil
	for i = 1, n do
		local p = makePlayer(i)
		players[i] = p
		local r = roles:onJoin(p)
		if r == "kicked" then
			message = p.kicked
			if p.Character ~= nil or possession:actorOf(p) ~= nil then
				kickedHadBody = true
			end
		end
	end
	local result = {
		ok = false,
		admitted = roles:admittedCount(),
		kicked = roles.kicked,
		kickedHadBody = kickedHadBody,
		message = message,
	}
	for _, p in players do
		roles:onLeave(p)
	end
	result.ok = result.admitted == math.min(n, 49)
		and result.kicked == math.max(0, n - 49)
		and not kickedHadBody
		and roles:admittedCount() == 0
	return result
end

return Soak
