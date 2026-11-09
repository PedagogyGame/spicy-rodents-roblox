--!strict
-- ServerScriptService.Server.Actors.BrainScheduler
-- Time-sliced brain ticks with distance LOD and a per-frame budget (BUILD_PLAN §1.4, D4): brains run
-- at 10 / 4 / 1 Hz for Near (< 150 st) / Mid (150-500 st) / Far (> 500 st) from the nearest focus
-- point (player bodies, the drone camera), staggered by a golden-ratio phase so ticks spread over
-- frames. When the frame's budget is spent, the remaining due brains carry over, round-robin.
-- Interface: new(params), register(id, brain, actor), unregister(id), setFocus(fn), step(dt, now),
-- metrics(), tierOf(actor)
-- Pure (os.clock only). Steppable: nothing runs until step() is called (rule 4).

local Common = require("./Brains/Common")

export type Params = {
	rates: { near: number, mid: number, far: number }, -- Hz
	ranges: { near: number, mid: number }, -- studs
	budgetMs: number, -- per frame, for think() calls
	historyFrames: number, -- rolling window for metrics
}

export type Focus = { x: number, z: number }

type Entry = {
	id: number,
	brain: Common.Brain,
	actor: Common.Actor,
	nextDue: number,
	lastTick: number,
	tier: string,
	ticks: number,
	ms: number,
}

export type FrameMetrics = {
	ticked: number,
	deferred: number,
	thinkMs: number,
	frameMs: number,
}

export type Metrics = {
	frames: number,
	avgMs: number,
	p99Ms: number,
	maxMs: number,
	ticksPerSecond: number,
	deferredTotal: number,
	tiers: { near: number, mid: number, far: number },
	brains: number,
	perKindMs: { [string]: number },
	perKindTicks: { [string]: number },
}

export type Scheduler = {
	params: Params,
	entries: { Entry },
	byId: { [number]: Entry },
	focus: { Focus },
	focusFn: (() -> { Focus })?,
	cursor: number,
	history: { number },
	historyIndex: number,
	frames: number,
	deferredTotal: number,
	ticksTotal: number,
	simSeconds: number,
	perKindMs: { [string]: number },
	perKindTicks: { [string]: number },
	forceTier: string?,
	register: (self: Scheduler, id: number, brain: Common.Brain, actor: Common.Actor, now: number) -> (),
	unregister: (self: Scheduler, id: number) -> (),
	setFocus: (self: Scheduler, fn: () -> { Focus }) -> (),
	tierOf: (self: Scheduler, actor: Common.Actor) -> string,
	step: (self: Scheduler, dt: number, now: number, ctx: Common.Ctx) -> FrameMetrics,
	metrics: (self: Scheduler) -> Metrics,
}

local BrainScheduler = {}

BrainScheduler.DEFAULTS = {
	rates = { near = 10, mid = 4, far = 1 },
	ranges = { near = 150, mid = 500 },
	budgetMs = 4,
	historyFrames = 600,
} :: Params

local GOLDEN = 0.6180339887498949

local Methods = {}
Methods.__index = Methods

function Methods.setFocus(self: Scheduler, fn: () -> { Focus })
	self.focusFn = fn
end

function Methods.tierOf(self: Scheduler, actor: Common.Actor): string
	if self.forceTier then
		return self.forceTier :: string
	end
	local best = math.huge
	local ax, az = actor.x, actor.z
	for _, f in self.focus do
		local dx, dz = f.x - ax, f.z - az
		local d2 = dx * dx + dz * dz
		if d2 < best then
			best = d2
		end
	end
	local near, mid = self.params.ranges.near, self.params.ranges.mid
	if best < near * near then
		return "near"
	elseif best < mid * mid then
		return "mid"
	end
	return "far"
end

local function intervalFor(self: Scheduler, tier: string): number
	local rates = self.params.rates
	local hz = if tier == "near" then rates.near elseif tier == "mid" then rates.mid else rates.far
	return 1 / hz
end

function Methods.register(self: Scheduler, id: number, brain: Common.Brain, actor: Common.Actor, now: number)
	if self.byId[id] then
		error(`BrainScheduler: {id} already registered`)
	end
	local n = #self.entries + 1
	local phase = (n * GOLDEN) % 1
	local tier = self:tierOf(actor)
	actor.tier = tier
	local entry: Entry = {
		id = id,
		brain = brain,
		actor = actor,
		nextDue = now + phase * intervalFor(self, tier),
		lastTick = now,
		tier = tier,
		ticks = 0,
		ms = 0,
	}
	self.entries[n] = entry
	self.byId[id] = entry
end

function Methods.unregister(self: Scheduler, id: number)
	local entry = self.byId[id]
	if not entry then
		return
	end
	self.byId[id] = nil
	for i, e in self.entries do
		if e == entry then
			table.remove(self.entries, i)
			break
		end
	end
	if self.cursor > #self.entries then
		self.cursor = 1
	end
end

-- One frame: tick every brain whose due time has passed, in round-robin order from the cursor,
-- until the budget is spent. A ticked brain gets dt = time since its own last tick, and its tier is
-- re-evaluated then (so a brain whose player walked away slows down at its next tick, not sooner).
function Methods.step(self: Scheduler, dt: number, now: number, ctx: Common.Ctx): FrameMetrics
	local frameStart = os.clock()
	if self.focusFn then
		self.focus = self.focusFn()
	end
	local budget = self.params.budgetMs / 1000
	local entries = self.entries
	local n = #entries
	local ticked, deferred = 0, 0
	local thinkTotal = 0
	if n > 0 then
		local start = self.cursor
		if start > n then
			start = 1
		end
		local i = start
		for _ = 1, n do
			local entry = entries[i]
			if entry.nextDue <= now then
				if thinkTotal >= budget then
					deferred += 1
				else
					local actor = entry.actor
					local tickDt = now - entry.lastTick
					local t0 = os.clock()
					entry.brain:think(tickDt, ctx)
					local cost = os.clock() - t0
					thinkTotal += cost
					entry.ms += cost
					entry.ticks += 1
					entry.lastTick = now
					ticked += 1
					local kind = entry.brain.kind
					self.perKindMs[kind] = (self.perKindMs[kind] or 0) + cost
					self.perKindTicks[kind] = (self.perKindTicks[kind] or 0) + 1
					local tier = self:tierOf(actor)
					entry.tier = tier
					actor.tier = tier
					entry.nextDue = now + intervalFor(self, tier)
				end
			end
			i += 1
			if i > n then
				i = 1
			end
		end
		-- next frame starts after the last brain we reached, so deferred brains come first
		self.cursor = if deferred > 0 then i else start
	end
	self.deferredTotal += deferred
	self.ticksTotal += ticked
	self.simSeconds += dt
	self.frames += 1
	local frameMs = (os.clock() - frameStart) * 1000
	self.historyIndex = self.historyIndex % self.params.historyFrames + 1
	self.history[self.historyIndex] = frameMs
	return { ticked = ticked, deferred = deferred, thinkMs = thinkTotal * 1000, frameMs = frameMs }
end

function Methods.metrics(self: Scheduler): Metrics
	local hist = {}
	local sum, maxMs = 0, 0
	for _, v in self.history do
		table.insert(hist, v)
		sum += v
		if v > maxMs then
			maxMs = v
		end
	end
	table.sort(hist)
	local count = #hist
	local p99 = if count > 0 then hist[math.max(1, math.ceil(count * 0.99))] else 0
	local tiers = { near = 0, mid = 0, far = 0 }
	for _, e in self.entries do
		tiers[e.tier] += 1
	end
	return {
		frames = self.frames,
		avgMs = if count > 0 then sum / count else 0,
		p99Ms = p99,
		maxMs = maxMs,
		ticksPerSecond = if self.simSeconds > 0 then self.ticksTotal / self.simSeconds else 0,
		deferredTotal = self.deferredTotal,
		tiers = tiers,
		brains = #self.entries,
		perKindMs = table.clone(self.perKindMs),
		perKindTicks = table.clone(self.perKindTicks),
	}
end

function BrainScheduler.new(params: Params?): Scheduler
	local p = params or BrainScheduler.DEFAULTS
	local self = setmetatable({
		params = p,
		entries = {},
		byId = {},
		focus = {},
		focusFn = nil,
		cursor = 1,
		history = {},
		historyIndex = 0,
		frames = 0,
		deferredTotal = 0,
		ticksTotal = 0,
		simSeconds = 0,
		perKindMs = {},
		perKindTicks = {},
		forceTier = nil,
	}, Methods)
	return (self :: any) :: Scheduler
end

return BrainScheduler
