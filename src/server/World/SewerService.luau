--!strict
-- ServerScriptService.Server.World.SewerService
-- The storm drains on the server (BRIEF_ADDENDUM D8: "a few underground pipes that the squirrel can run through";
-- brief v2 §8: "the rodent therefore needs refuges between bites: hollows, the sewer, poles and trees"). The pipes
-- are enclosed routes (Shared/World/SewerLayout over Shared/Routes/Enclosure; the motor runs them); this is what
-- being down there means to the rest of the town:
--   * The carve: start() clears the terrain out of every box of SewerLayout.carveBoxes() (FillBlock Air, the
--     4-stud grid), so the pipes the bake draws are open air. It runs when start() is called: Boot/Game calls it
--     after the terrain is written (any later terrain write would fill the pipes again).
--   * Cover: a squirrel the layout says is underground (SewerLayout.contains) is out of AI/TownAI's threat grid
--     (TownAI.addCover: one cover among any others, removed again by stop), so people do not see or hear it, the fox does not hunt it, the deer do not start; and
--     Infection/InfectionService leaves it out of the crowd's fears. As in v5.4, where the sewer hid the player.
--   * Seen going down: when a squirrel goes under, the people who saw it at the grate (Actors/Perception's spot
--     test on the mouth, or a spot of it in the last C.witnessWindow) react. Up to C.speakers bystanders say a
--     "drain" line (Speech/SpeechRules limits). If it was the Spicy Rodent, every officer who saw it is sent to
--     stand over that grate for Tunables sewer.stakeoutSecs (Brains/Officer's stakeout: there it says "It went
--     down the drain!", then back to the beat). Officers never go to the other end. The officer stands
--     C.standOff from the grate, out of the rodent's bite (Combat/PlayRules BITE_RANGE). One grate is watched
--     once per sewer.stakeoutSecs: diving in and out of it again sends nobody new and renews nothing. If the
--     rodent comes up out of a watched grate's pipe where a watching officer sees it, that officer's watch ends
--     and he goes after it (Officer "respond" to where it came up). onLost reports it (the place for
--     Police/PoliceCoord when it exists).
--   * No bites from cover: mayBite(id) is false while the cover hides the rodent (Boot/Game asks before every
--     bite), so a rodent nobody can see never bites anyone either.
--   * Let go underground: a body a player lets go of in a pipe is put at the nearest mouth of that pipe, standing,
--     facing out, before the AI takes it (TownAI.resume asks the cover).
--   * Refuge: the rodent heals in a pipe at the hollow rate (Tunables rodent.regenHollow) only while fed (bit
--     someone within rodent.fedWindowDays game days, D33 rev 4): healRate / heal, for the code that keeps health.
--   * The rodent's re-entry after a death (BUILD_PLAN R5 S-10, Roles/Ladder rodentReentry): reentry() picks the
--     mouth (SewerLayout.reentryMouth, away from the death, nobody near).
--   * The fashion stand's new home (brief v2 decision 20; BUILD_PLAN W4 #9): fashionStand() is the anchor in P1's
--     chamber for Cosmetics/FashionStand to read.
--   * The alligator (v5.4's idle predator in the sewer): a sound and a line only, never seen. idleWarning(id)
--     gives the line and the cue for the idle release's warning (D34) when the body is down a drain.
-- Sound: named cue points only (CUES); every id is empty until audio exists. Nothing is uploaded.
-- Interface: new(opts) -> Service (pure: installs the cover, unless opts.cover is false, and a listener on the
--   TownAI world); start(opts) -> Service (new, then the carve on workspace.Terrain unless opts.carve is false);
--   carve(terrain, boxes) -> count; fed(lastBiteAt?, now) -> boolean; Service: :underground(id) -> space?;
--   :mayBite(id); :isRefuge(id); :healRate(id, fed) ->
--   hp/s; :heal(id, health, maxHealth, dt, fed) -> health; :surface(x, y, z) -> (x, y, z, yaw)?; :reentry(deathX,
--   deathZ) -> Mouth?; :fashionStand() -> Anchor?; :idleWarning(id) -> Warning?; :lost() -> { Lost } (the
--   newest C.keepLost); :stop(); C; HISS; CUES
-- Studs and the HTML yaw (Brains/Common). Engine calls only in start and carve. No side effects on require.

local Import = require("../Import")
local SewerLayout = Import.shared("World/SewerLayout") :: typeof(require("../../shared/World/SewerLayout"))
local SpeechRules = Import.shared("Speech/SpeechRules") :: typeof(require("../../shared/Speech/SpeechRules"))
local Tunables = Import.shared("Config/Tunables") :: typeof(require("../../shared/Config/Tunables"))
local Perception = require("../Actors/Perception")
local TownAI = require("../AI/TownAI")

type Layout = typeof(SewerLayout.new(nil :: any))
type Mouth = typeof(((nil :: any) :: Layout).mouths[1])
type Box = typeof(((nil :: any) :: Layout).carves[1])
type Anchor = typeof(((nil :: any) :: Layout).anchors[1])
type SpeechState = typeof(SpeechRules.new())

local SewerService = {}
SewerService.__index = SewerService

SewerService.C = {
	witnessWindow = 1.0, -- s: a person who spotted the squirrel this long before it went under saw it go
	witnessRadius = Perception.constants.sightCap, -- studs from the mouth: nobody farther saw it at the grate
	speakers = 2, -- bystanders who may remark on one squirrel going down (each still under SpeechRules)
	-- studs from the mouth point to where an officer stands watching the grate: out of the rodent's bite
	-- (Combat/PlayRules BITE_RANGE 3.5) with 2.5 to spare, so one coming up there cannot bite him at once
	standOff = 6.0,
	respondSecs = 8, -- s: an officer who sees the rodent come up out of the grate he watches goes after it this long
	keepLost = 16, -- the newest reports kept by lost()
	keepSpots = 8, -- spots remembered per squirrel
}

-- v5.4's idle predator in the sewer (L8188), as a warning only: a sound and a line, nothing to see
SewerService.HISS = table.freeze({
	predator = "small alligator",
	text = "A low hiss and a ripple in the sewer water.",
	cue = "sewer.hiss",
})

-- named cue points (docs/AUDIO_BUDGET.md lists the sewer cues; lane S3 plays them): no ids until audio exists
SewerService.CUES = table.freeze({
	["sewer.hiss"] = "",
})

export type Lost = {
	actor: number, -- the TownAI id of the squirrel
	mouth: string, -- SewerLayout mouth id ("P1.NW")
	space: string,
	x: number,
	z: number,
	t: number, -- world time
	witnesses: { number }, -- people who saw it go, nearest first
	officers: { number }, -- officers sent to watch the grate
}

export type Warning = { predator: string, text: string, cue: string }

export type Opts = {
	world: TownAI.World,
	layout: Layout?, -- default SewerLayout.default()
	-- the town's speech limits are one: pass Infection/InfectionService's state (infection.speech) and its clock
	speech: SpeechState?,
	clock: (() -> number)?, -- the speech clock (default: the world's time)
	rand: (() -> number)?, -- uniform [0, 1) (default math.random)
	setAttr: ((id: number, name: string, value: any) -> ())?, -- Say and SayAt on the body
	serverTime: (() -> number)?, -- SayAt's clock (default: the speech clock)
	controllerOf: ((id: number) -> string)?, -- "ai" | "player" (default: TownAI's possessed list)
	onLost: ((lost: Lost) -> ())?,
	cover: boolean?, -- default true: hide what is underground from the town (false: the pipes are not drawn)
	concealment: Perception.Concealment?, -- default Perception.defaultConcealment()
	-- start only
	carve: boolean?, -- default true
	terrain: any?, -- default workspace.Terrain
}

type Spot = { by: number, t: number }
-- a grate the police are watching: since when, and who
type Watch = { since: number, officers: { number } }

export type Service = typeof(setmetatable(
	{} :: {
		world: TownAI.World,
		layout: Layout,
		speech: SpeechState,
		clock: () -> number,
		rand: () -> number,
		setAttr: (id: number, name: string, value: any) -> (),
		serverTime: () -> number,
		controllerOf: (id: number) -> string,
		onLost: (lost: Lost) -> (),
		pctx: Perception.Ctx,
		spots: { [number]: { Spot } },
		lostLog: { Lost },
		watch: { [string]: Watch? },
		unlisten: () -> (),
		uncover: () -> (),
		carved: number,
	},
	SewerService
))

-- the mouth of `space` nearest (x, z), level
local function nearestMouthOf(layout: Layout, space: string, x: number, z: number): Mouth?
	local best: Mouth? = nil
	local bestD = math.huge
	for _, m in layout.mouths do
		if m.space == space then
			local d = (m.x - x) ^ 2 + (m.z - z) ^ 2
			if d < bestD then
				best, bestD = m, d
			end
		end
	end
	return best
end

-- the yaw facing out of a mouth (HTML yaw: 0 faces +z, Brains/Common.yawOf)
local function outYaw(m: Mouth): number
	return math.atan2(m.out.x, m.out.z)
end

function SewerService.new(opts: Opts): Service
	local layout = opts.layout or SewerLayout.default()
	assert(layout, "SewerService: no sewer layout (generated/Sewers.luau is not compiled)")
	local world = opts.world
	local clock = opts.clock or function(): number
		return world.now
	end
	local self = setmetatable({
		world = world,
		layout = layout,
		speech = opts.speech or SpeechRules.new(),
		clock = clock,
		rand = opts.rand or math.random,
		setAttr = opts.setAttr or function() end,
		serverTime = opts.serverTime or clock,
		controllerOf = opts.controllerOf or function(id: number): string
			return if world.possessed[id] then "player" else "ai"
		end,
		onLost = opts.onLost or function() end,
		pctx = { time = 0, hotHere = false, concealment = opts.concealment or Perception.defaultConcealment() },
		spots = {},
		lostLog = {},
		watch = {},
		unlisten = function() end,
		uncover = function() end,
		carved = 0,
	}, SewerService)
	if opts.cover ~= false then
		self.uncover = TownAI.addCover(world, {
			under = layout.contains,
			surface = function(x: number, y: number, z: number): (number?, number?, number?, number?)
				return self:surface(x, y, z)
			end,
		})
	end
	self.unlisten = TownAI.listen(world, function(ev: TownAI.Event)
		if ev.kind == "spotted" and ev.other then
			self:_spotted(ev.other, ev.id, ev.t)
		elseif ev.kind == "covered" and ev.space then
			self:_wentUnder(ev.id, ev.space, ev.t)
		elseif ev.kind == "uncovered" and ev.space then
			self:_cameUp(ev.id, ev.space, ev.t)
		elseif ev.kind == "stakeout" then
			self:_say(ev.id, "stakeout", true)
		end
	end)
	return self
end

-- carve(terrain, boxes): FillBlock Air over each box (world studs, axis-aligned). Returns how many.
function SewerService.carve(terrain: any, boxes: { Box }): number
	local n = 0
	for _, b in boxes do
		local centre = CFrame.new((b.x0 + b.x1) / 2, (b.y0 + b.y1) / 2, (b.z0 + b.z1) / 2)
		local size = Vector3.new(b.x1 - b.x0, b.y1 - b.y0, b.z1 - b.z0)
		terrain:FillBlock(centre, size, Enum.Material.Air)
		n += 1
	end
	return n
end

-- start(opts): the service, and the terrain carved out of the pipes now (call it after the terrain is written)
function SewerService.start(opts: Opts): Service
	local self = SewerService.new(opts)
	if opts.carve ~= false then
		local terrain = opts.terrain or workspace.Terrain
		self.carved = SewerService.carve(terrain, self.layout.carveBoxes())
	end
	return self
end

-- fed(lastBiteAt, now): the rodent bit someone within Tunables rodent.fedWindowDays game days (real seconds on the
-- same clock as `now`)
function SewerService.fed(lastBiteAt: number?, now: number): boolean
	if lastBiteAt == nil then
		return false
	end
	local window = Tunables.get("rodent.fedWindowDays") * Tunables.get("clock.realSecondsPerDay")
	return now - lastBiteAt <= window
end

-- what it hears ---------------------------------------------------------------------------------------------------

function SewerService._spotted(self: Service, threat: number, by: number, t: number)
	local list = self.spots[threat]
	if list == nil then
		list = {}
		self.spots[threat] = list
	end
	table.insert(list, { by = by, t = t })
	while #list > SewerService.C.keepSpots do
		table.remove(list, 1)
	end
end

function SewerService._say(self: Service, id: number, situation: string, force: boolean): boolean
	if self.controllerOf(id) ~= "ai" then
		return false
	end
	local line = SpeechRules.request(self.speech, self.clock(), id, situation, self.rand, { force = force })
	if line == nil then
		return false
	end
	self.setAttr(id, SpeechRules.ATTR.Say, line)
	self.setAttr(id, SpeechRules.ATTR.SayAt, self.serverTime())
	return true
end

-- the people who saw squirrel `actor` at mouth `m` as it went under, nearest first
function SewerService._witnesses(self: Service, actor: any, m: Mouth, t: number): { any }
	local C = SewerService.C
	local recent: { [number]: boolean } = {}
	local spots = self.spots[actor.id]
	if spots then
		for _, s in spots do
			if t - s.t <= C.witnessWindow then
				recent[s.by] = true
			end
		end
	end
	local target: Perception.Target = {
		x = m.x,
		y = m.y + actor.hip,
		z = m.z,
		groundY = m.y,
		moveSpeed = actor.speed,
		focus = false,
		inInterior = false,
	}
	self.pctx.time = t
	type Seen = { a: any, d: number }
	local seen: { Seen } = {}
	for _, a in self.world.actors do
		if a.species ~= "human" or self.controllerOf(a.id) ~= "ai" then
			continue
		end
		local d = math.sqrt((a.x - m.x) ^ 2 + (a.z - m.z) ^ 2)
		local saw = recent[a.id] == true
		if not saw and d <= C.witnessRadius then
			local obs: Perception.Observer = { x = a.x, y = a.y - a.hip, z = a.z, facing = a.yaw }
			saw = Perception.spotted(obs, target, self.pctx)
		end
		if saw then
			table.insert(seen, { a = a, d = d })
		end
	end
	table.sort(seen, function(p: Seen, q: Seen): boolean
		if p.d ~= q.d then
			return p.d < q.d
		end
		return p.a.id < q.a.id
	end)
	local out = {}
	for i, s in seen do
		out[i] = s.a
	end
	return out
end

function SewerService._wentUnder(self: Service, id: number, space: string, t: number)
	local actor = self.world.actorsById[id]
	if actor == nil or actor.species ~= "squirrel" then
		return
	end
	local m = nearestMouthOf(self.layout, space, actor.x, actor.z)
	if m == nil then
		return
	end
	local C = SewerService.C
	local witnesses = self:_witnesses(actor, m, t)
	local report: Lost =
		{ actor = id, mouth = m.id, space = space, x = m.x, z = m.z, t = t, witnesses = {}, officers = {} }
	local spoke = 0
	local secs = Tunables.get("sewer.stakeoutSecs")
	local watched: Watch? = self.watch[m.id]
	if watched and t - watched.since >= secs then
		self.watch[m.id] = nil
		watched = nil
	end
	for _, w in witnesses do
		table.insert(report.witnesses, w.id)
		local brain = self.world.brains[w.id]
		local officer = brain ~= nil and brain.kind == "Officer"
		if officer then
			-- the police lose the rodent at the drain and watch that grate; any other squirrel is not their business
			if actor.variant == "spicy" and watched == nil then
				local dx, dz = w.x - m.x, w.z - m.z
				local l = math.sqrt(dx * dx + dz * dz)
				if l < 1e-6 then
					dx, dz, l = m.out.x, m.out.z, 1
				end
				brain:onEvent({
					type = "stakeout",
					x = m.x + dx / l * C.standOff,
					z = m.z + dz / l * C.standOff,
					faceX = m.x,
					faceZ = m.z,
					secs = secs,
					mouth = m.id,
				})
				table.insert(report.officers, w.id)
			end
		elseif spoke < C.speakers then
			if self:_say(w.id, "drain", false) then
				spoke += 1
			end
		end
	end
	if #report.officers > 0 then
		self.watch[m.id] = { since = t, officers = table.clone(report.officers) }
	end
	self.spots[id] = nil
	table.insert(self.lostLog, report)
	while #self.lostLog > C.keepLost do
		table.remove(self.lostLog, 1)
	end
	self.onLost(report)
end

-- the rodent came up out of pipe `space`: an officer watching one of its grates who sees it now goes after it
function SewerService._cameUp(self: Service, id: number, space: string, t: number)
	local actor = self.world.actorsById[id]
	if actor == nil or actor.variant ~= "spicy" then
		return
	end
	local target: Perception.Target = {
		x = actor.x,
		y = actor.y,
		z = actor.z,
		groundY = actor.y - actor.hip,
		moveSpeed = actor.speed,
		focus = false,
		inInterior = false,
	}
	self.pctx.time = t
	for mouthId, watch in self.watch do
		local m = self.layout.mouth(mouthId)
		if watch == nil or m == nil or m.space ~= space then
			continue
		end
		for _, oid in watch.officers do
			local o = self.world.actorsById[oid]
			local brain = self.world.brains[oid] :: any
			if o == nil or brain == nil or brain.stakeout == nil or brain.stakeout.mouth ~= mouthId then
				continue -- not watching it any more
			end
			local obs: Perception.Observer = { x = o.x, y = o.y - o.hip, z = o.z, facing = o.yaw }
			if Perception.spotted(obs, target, self.pctx) then
				brain:onEvent({ type = "stakeoutEnd" })
				brain:onEvent({
					type = "respond",
					x = actor.x,
					z = actor.z,
					untilTime = self.world.now + SewerService.C.respondSecs,
				})
			end
		end
	end
end

-- what the town asks -----------------------------------------------------------------------------------------------

-- the space hiding actor `id` (as of the last AI frame), nil in the open
function SewerService.underground(self: Service, id: number): string?
	return TownAI.covered(self.world, id)
end

-- mayBite: the rodent bites only from where it can be seen (never out of cover: hidden and biting are never both
-- true)
function SewerService.mayBite(self: Service, id: number): boolean
	return TownAI.covered(self.world, id) == nil
end

-- a refuge counts like a hollow tree for the rodent's resting regen
function SewerService.isRefuge(self: Service, id: number): boolean
	return TownAI.covered(self.world, id) ~= nil
end

-- hp per second the body heals here: the hollow rate for the Spicy Rodent in a pipe while fed, else 0
function SewerService.healRate(self: Service, id: number, fed: boolean): number
	local actor = self.world.actorsById[id]
	if actor == nil or actor.variant ~= "spicy" or not fed or not self:isRefuge(id) then
		return 0
	end
	return Tunables.get("rodent.regenHollow")
end

-- heal: health after dt seconds here (never above maxHealth; the dead stay dead)
function SewerService.heal(
	self: Service,
	id: number,
	health: number,
	maxHealth: number,
	dt: number,
	fed: boolean
): number
	if health <= 0 or health >= maxHealth then
		return health
	end
	return math.min(maxHealth, health + self:healRate(id, fed) * dt)
end

-- surface(x, y, z): where a body let go at that point is put: the mouth of its pipe nearest to it (ground level),
-- facing out; nothing when the point is not in a pipe
function SewerService.surface(self: Service, x: number, y: number, z: number): (number?, number?, number?, number?)
	local space = self.layout.contains(x, y, z)
	if space == nil then
		return nil, nil, nil, nil
	end
	local m = nearestMouthOf(self.layout, space, x, z)
	if m == nil then
		return nil, nil, nil, nil
	end
	return m.x, m.y, m.z, outYaw(m)
end

-- reentry(deathX, deathZ): the mouth a dead rodent climbs back out of, away from the death and from people
function SewerService.reentry(self: Service, deathX: number, deathZ: number): Mouth?
	local people: { { number } } = {}
	for _, a in self.world.actors do
		if a.species == "human" then
			table.insert(people, { a.x, a.z })
		end
	end
	return self.layout.reentryMouth(deathX, deathZ, people)
end

-- the fashion stand's home: the anchor in P1's chamber (position on the chamber floor, facing, space)
function SewerService.fashionStand(self: Service): Anchor?
	for _, a in self.layout.anchors do
		if a.kind == "fashionStand" then
			return a
		end
	end
	return nil
end

-- idleWarning(id): the sewer's idle predator line and cue when the body is down a drain, nil elsewhere
function SewerService.idleWarning(self: Service, id: number): Warning?
	if not self:isRefuge(id) then
		return nil
	end
	local h = SewerService.HISS
	return { predator = h.predator, text = h.text, cue = h.cue }
end

function SewerService.lost(self: Service): { Lost }
	return table.clone(self.lostLog)
end

-- stop: no more cover (everything in the open again) and no more listening
function SewerService.stop(self: Service)
	self.unlisten()
	self.uncover()
end

return SewerService
