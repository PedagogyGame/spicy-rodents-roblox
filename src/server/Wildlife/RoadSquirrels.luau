--!strict
-- ServerScriptService.Server.Wildlife.RoadSquirrels
-- A car gets one of the computer's squirrels (owner D21, 2026-11-21: "make sure those regular squirrels can be run
-- over by cars, if they are not careful"). The squirrels cross the roads by themselves (Brains/Squirrel on
-- Shared/Wildlife/RoadCrossing: they look, and mostly wait; now and then one misjudges a fast car), the cars do not
-- brake for them (D15 #6), and the fleet's fatal sweep (Traffic/TrafficService RunOver) says when one is hit, exactly
-- as for a player's squirrel. A player's is knocked out and its player sent to the menu ("RUN OVER": Boot/Game); for
-- the computer's, Boot/Game calls `hit` here. Mildly (the rating: no gore, no blood, nothing left on the road):
--   * knocked flat: the squirrel lies still on its side where it was hit (the actor's `roll` and `lift`), with a puff
--     of dust and a fade on every client (the body's Flat attribute, the server time of the hit: Client/Render/
--     FlatView) and a toy squeak (SOUNDS: the duel's own soft thump, a library sound already in the game);
--   * gone: after C.lieSecs it is out of sight (sunk under the ground, as a patient in an ambulance is), out of every
--     grid and hunt (AI/TownAI: the actor's `gone`), not offered to a player (opts.setPossessable), eating no nuts
--     (Foraging/ForageService), its carried nuts lost (opts.onDown: Foraging/HollowService.drop);
--   * back: C.awaySecs later a squirrel is back in town on a tree (a trunk nobody is looking at, when there is one):
--     the same body (bodies are never destroyed, D1), as new. A tree it had claimed is still its own if it gets back
--     to it in time (Foraging/HollowClaim's lapse by absence does the rest).
-- BOUNDED: at most C.perMinute squirrels are knocked flat in any minute, town-wide; a hit over that is a near miss (the
-- squirrel runs on). So the town never runs out of squirrels: each is away under two minutes.
-- Only the computer's ORDINARY squirrels: a body a player holds, the Spicy Rodent and an infected squirrel are not
-- this service's (`hit` says no and changes nothing).
-- Interface: C; SOUNDS; new(opts) -> Service; :hit(id) -> boolean (a car's sweep hit this body: was it knocked flat?);
--   :step(dt); :down() -> n (squirrels flat or away now); :stats(); :stop() (everyone back at once)
-- Ids are TownAI actor ids. Studs. Step-driven: requiring this module starts nothing.

local Import = require("../Import")
local Species = Import.shared("Actors/Species") :: typeof(require("../../shared/Actors/Species"))
local HumanAIMotor = Import.shared("Movement/HumanAIMotor") :: typeof(require("../../shared/Movement/HumanAIMotor"))

export type Opts = {
	world: any, -- AI/TownAI.World
	rand: (() -> number)?,
	setAttr: ((id: number, name: string, value: any) -> ())?,
	setPossessable: ((id: number, value: boolean) -> ())?,
	onDown: ((id: number) -> ())?, -- the squirrel is out of the game for a while (its nuts are lost)
	cue: ((id: number, cue: string) -> ())?, -- a sound by cue name at the body (SOUNDS)
	serverTime: (() -> number)?, -- the Flat attribute's clock (default: the town's)
}

-- hits: squirrels knocked flat so far; flat: of those, how many are flat or away now; spared: near misses under the cap;
-- back: squirrels that have come back
export type Stats = { hits: number, flat: number, spared: number, back: number }

type Down = { id: number, at: number, backAt: number, sunk: boolean }

local RoadSquirrels = {}
RoadSquirrels.__index = RoadSquirrels

RoadSquirrels.C = table.freeze({
	lieSecs = 3, -- it lies on the road this long (the clients fade it over the last second)
	fadeSecs = 1,
	awaySecs = { 40, 90 }, -- then it is away this long before one is back at a tree
	perMinute = 2, -- squirrels knocked flat in any 60 s, town-wide, at most
	spareSecs = 2, -- a squirrel let off under the cap is counted once in this long
	roll = math.pi / 2, -- it lies on its side
	lieLift = -0.45, -- studs: its side on the road (the drawn body is this much lower)
	sink = -40, -- studs: out of sight while away (Infection/InfectionService.SINK's way of hiding a body)
	treeTries = 8, -- trees tried for one nobody is looking at
	treeAt = 0.5, -- how far up the trunk it is put (a share of the trunk)
	minTrunk = 12, -- studs: a shorter trunk is no tree to come back on
})

-- the sound of a hit: a soft thump and a squeak, no crunch (Squeaky Toy 2: the duel's "Duel.Blow", already in the game)
RoadSquirrels.SOUNDS = table.freeze({
	["Road.Flat"] = "rbxassetid://9119536562",
}) :: { [string]: string }

local C = RoadSquirrels.C

function RoadSquirrels.new(opts: Opts)
	return setmetatable({
		opts = opts,
		world = opts.world,
		rand = opts.rand or math.random,
		downs = {} :: { [number]: Down },
		recent = {} :: { number }, -- when the last few were knocked flat (the cap)
		spared = {} :: { [number]: number }, -- when each squirrel was last let off under the cap
		_stats = { hits = 0, flat = 0, spared = 0, back = 0 } :: Stats,
	}, RoadSquirrels)
end

local function setAttr(self: any, id: number, name: string, value: any)
	local f = self.opts.setAttr
	if f then
		f(id, name, value)
	end
end

local function possessable(self: any, id: number, value: boolean)
	local f = self.opts.setPossessable
	if f then
		f(id, value)
	end
end

-- hit(id): a car's sweep hit this body. True when it was knocked flat (one of the computer's ordinary squirrels, out
-- on the road, with room under the cap).
function RoadSquirrels.hit(self: any, id: number): boolean
	local world = self.world
	local a = world.actorsById[id]
	if
		a == nil
		or a.species ~= "squirrel"
		or Species.feared(a)
		or world.possessed[id]
		or a.gone
		or self.downs[id] ~= nil
	then
		return false
	end
	local now = world.now
	local recent = self.recent
	while #recent > 0 and now - recent[1] >= 60 do
		table.remove(recent, 1)
	end
	if #recent >= C.perMinute then
		-- a near miss: it runs on (counted once: the sweep may find it under the same car a few ticks running)
		if (self.spared[id] or -math.huge) < now - C.spareSecs then
			self._stats.spared += 1
		end
		self.spared[id] = now
		return false
	end
	local brain = world.brains[id]
	table.insert(recent, now)
	self._stats.hits += 1
	a.gone = true
	a.crossing = nil
	a.roll = C.roll
	a.lift = C.lieLift
	a.speed = 0
	if brain then
		brain:onEvent({ type = "runOver" })
	end
	world.grid:remove(id)
	local away = C.awaySecs
	self.downs[id] =
		{ id = id, at = now, backAt = now + C.lieSecs + away[1] + (away[2] - away[1]) * self.rand(), sunk = false }
	local st = self.opts.serverTime
	setAttr(self, id, "Flat", if st then st() else now)
	possessable(self, id, false)
	local onDown = self.opts.onDown
	if onDown then
		onDown(id)
	end
	local cue = self.opts.cue
	if cue then
		cue(id, "Road.Flat")
	end
	return true
end

-- a tree to come back on: a trunk (not an enclosed run), by choice one no player can see
local function tree(self: any): (any?, number)
	local world = self.world
	local routes = world.routes
	local trunks = self.trunks
	if trunks == nil then
		trunks = {}
		for _, r in routes.routes do
			if r.kind == "trunk" and r.length >= C.minTrunk and not routes.enclosed(r.id) then
				table.insert(trunks, r)
			end
		end
		self.trunks = trunks
	end
	if #trunks == 0 then
		return nil, 0
	end
	local seen = world.ctx.seen
	local pick = nil
	for _ = 1, C.treeTries do
		pick = trunks[math.min(#trunks, 1 + math.floor(self.rand() * #trunks))]
		local p = pick.points[1]
		if seen == nil or not seen(p[1], p[3]) then
			break
		end
	end
	return pick, pick.length * C.treeAt
end

local function back(self: any, d: Down)
	local world = self.world
	local a = world.actorsById[d.id]
	self.downs[d.id] = nil
	if a == nil then
		return
	end
	local route, s = tree(self)
	if route then
		-- (stood on the trunk before it is shown again: never drawn gliding up from the road)
		a.x, a.y, a.z = HumanAIMotor.railPose(route, s)
		local brain = world.brains[d.id]
		if brain then
			brain:onEvent({ type = "comeBack", routeId = route.id, s = s })
		end
	end
	a.gone = nil
	a.roll = nil
	a.lift = nil
	setAttr(self, d.id, "Flat", nil)
	possessable(self, d.id, true)
	self._stats.back += 1
end

function RoadSquirrels.step(self: any, _dt: number)
	if next(self.downs) == nil then
		return
	end
	local world = self.world
	local now = world.now
	for _, d in self.downs do
		local a = world.actorsById[d.id]
		if not d.sunk and now >= d.at + C.lieSecs then
			d.sunk = true
			if a then
				a.lift = C.sink
			end
		end
	end
	-- (one a step is plenty, and keeps the loop above off a table that changes under it)
	for _, d in self.downs do
		if now >= d.backAt then
			back(self, d)
			break
		end
	end
end

function RoadSquirrels.down(self: any): number
	local n = 0
	for _ in self.downs do
		n += 1
	end
	return n
end

function RoadSquirrels.stats(self: any): Stats
	local out = table.clone(self._stats)
	out.flat = self:down()
	return out
end

function RoadSquirrels.stop(self: any)
	local downs: { Down } = {}
	for _, d in self.downs do
		table.insert(downs, d)
	end
	for _, d in downs do
		back(self, d)
	end
end

return RoadSquirrels
