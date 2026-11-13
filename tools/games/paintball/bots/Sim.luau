--!strict
-- tools/games/paintball/bots/Sim.luau: a whole paintball match played headless, for the match-and-bots
-- lane's specs (tests/unit/paintball_bots*.spec.luau) and its tools (match.luau, calibrate.luau beside
-- this file). It is the lane's own small copy of the part of the server that matters to a bot
-- (Server/Minigames/Paintball/PaintballService, "the loop"), built from the real pieces:
--   the match   the real Session on the real Rules, synced to the sim's clock every tick, as the
--               service does: seats are taken through Session.join, placements come from the
--               "respawn" events Rules emits, the match ends when result() says so
--   the bots    the real Bots.step, handed `heard` from the sim's own ball loop
--   the balls   Ballistics for the flight, arena.sweep for the building, Hit.body for a body, Rules.tag
--               for the verdict: a ball is its centre line, the first thing along the step wins, a
--               tie goes to the wall, a body in its own spawn room is passed over
--   the bodies  judged where the snapshot stream has them (a 20 Hz history of quantised poses, straight
--               lines between, held at the newest), at the ball's time less its rewind
-- EVERYBODY IS JUDGED BY ONE FUNCTION. A click (a bot's "fire" command, a stand-in person's) goes
-- through `judge`: the direction within BOT.aimSlack of the pose's own look, the origin at the pose's
-- eye, not from inside a spawn room, no sprint bit within Body.SPRINT_FIRE_DELAY less MARGIN.sprint,
-- then Rules.fire. Nothing in it asks who is a bot. Every refusal is counted with its reason.
-- THE STAND-IN PERSON ("the fair player") is a second list of brains with a Profile of its own
-- (FAIR below: a person's reaction, a person's narrower view, a steadier hand, a faster wrist). It is
-- shown the others where they were `delay` seconds ago (a client draws its view time in the past) and
-- its balls are judged against the bodies of that moment (the server's rewind), and the bots are shown
-- it where its last snapshot put it. It is how the calibration says "a fair player beats the average
-- bot about three times in five"; it is nobody's idea of a real person and the owner's playtest is
-- the judge.
-- THE LEGS. A bot has no body for the server to check, so the sim checks every step every brain takes
-- by the rules a person's reported pose is held to (Contract, "the server accepts a pose only if"):
-- inside the building and no box, never in the other team's spawn room, feet on the walking surface,
-- a clear path from the last pose (Arena.clearPath at chest height), and no further than Body.speed
-- allows for the crouch it had and the sprint bit it shows, with none of a person's tolerances (no
-- speedTolerance, no fall, no hop). Every step that fails is counted in rec.legs with its reason.
-- THE RECORD (sim.rec) is what the specs pin and the tools print: every shot and whether it tagged
-- its target, every tag with the range, the target's speed and whether the shooter had been facing
-- it, each slot's time by storey, in its room, at cover, crouched and standing still, the stairs
-- used, lives and how they ended, call-outs, refused commands, and the cost of Bots.step.
-- Interface: FAIR; new(opts) -> Sim; tick(sim); run(sim, untilTime?) -> Sim (to the end of the match
--   by default); legs(sim, who, isBot) (the legs' check, as tick runs it, for a spec to try by hand); judge(sim, id, ox, oy, oz, vx, vy, vz) -> (ok, why?); shoot(sim, id, ox, oy, oz, vx,
--   vy, vz, list?, rewind?) -> (ok, why?); teleport(sim, id, x, y, z, yaw); types Opts, Sim, Record
local Ballistics = require("@shared/Paintball/Ballistics")
local Arena = require("@shared/Minigames/Paintball/Arena")
local ArenaData = require("@shared/Minigames/Paintball/ArenaData")
local Body = require("@shared/Minigames/Paintball/Body")
local Clock = require("@shared/Minigames/Paintball/Clock")
local Contract = require("@shared/Minigames/Paintball/Contract")
local Hit = require("@shared/Minigames/Paintball/Hit")
local Rules = require("@shared/Minigames/Paintball/Rules")
local Spec = require("@shared/Minigames/Paintball/Spec")
local Wire = require("@shared/Minigames/Paintball/Wire")
local Minigame = require("@shared/Minigames/Minigame")
local Session = require("@shared/Minigames/Session")
local BotBrain = require("@server/Minigames/Paintball/BotBrain")
local BotNav = require("@server/Minigames/Paintball/BotNav")
local Bots = require("@server/Minigames/Paintball/Bots")

type Pose = Contract.Pose

export type Opts = {
	seed: number?,
	perSide: number?, -- 4..8 (default 4)
	people: number?, -- how many seats the fair player's stand-ins take (they join first); default 0
	feel: Contract.Feel?,
	dt: number?, -- the step (default 1 / Clock.TICK_HZ)
	arena: Arena.Arena?,
	profile: BotBrain.Profile?, -- the stand-in's (default FAIR)
	delay: number?, -- seconds late a stand-in sees the others (default 0.15)
	skill: number?, -- every bot's skill (default: Contract.BOTS in order)
	audit: boolean?, -- also look for bots that follow somebody through a wall (costs sweeps)
	start: number?, -- the shared clock when the match starts (default 1000)
	-- SCRIPTED PEOPLE: this many seats, taken before anybody else's, with no brain at all. Each tick
	-- `script` is handed each one that is in play and moves its pose as it likes (a target that
	-- stands, walks a beat, hides): a person the spec controls to the stud.
	dummies: number?,
	script: ((sim: any, id: number, pose: Contract.Pose, now: number, dt: number) -> ())?,
	frozen: boolean?, -- no brain is stepped at all: the spec moves every pose and fires every ball itself
}

type Ball = {
	id: number,
	by: number,
	team: number,
	born: number,
	age: number,
	rewind: number,
	ox: number,
	oy: number,
	oz: number,
	vx: number,
	vy: number,
	vz: number,
	shot: Shot,
}

export type Shot = {
	t: number,
	by: number,
	bot: boolean,
	target: number?, -- whom the brain was firing at
	range: number, -- studs to it
	speed: number, -- its speed over the floor
	nth: number, -- 1 for the first ball at this target
	storeys: number, -- how many storeys apart the shooter and that target stood (0: on one floor)
	tagged: boolean, -- the ball tagged that target
	faced: boolean, -- the shooter's look had had that target inside the sight cone for BOT.faced
	-- when the ball left, that target was on its own doorstep (BotNav.atDoor) and had not fired a ball
	-- for DOOR_TRUCE: the ball a bot never fires
	trap: boolean,
	-- when the ball left, that target had been out of its own spawn room for less than OUT_TRUCE and
	-- had not fired a ball since: the other ball a bot never fires
	fresh: boolean,
}

export type Tag = {
	t: number,
	by: number,
	id: number,
	byBot: boolean,
	idBot: boolean,
	range: number, -- from where the ball was born to where it struck
	faced: boolean, -- the shooter's look had the victim inside the sight cone for BOT.faced before the ball
	sinceRoom: number, -- seconds since the victim left its spawn room
	doorstep: boolean, -- the victim was on its own doorstep (BotNav.atDoor)
	quiet: boolean, -- and had not fired a ball for DOOR_TRUCE
	stray: boolean, -- the ball was fired at somebody else
	aware: boolean, -- the victim (a brain) had seen whoever tagged it within the last second
	fought: boolean, -- and had fired at them
}

type Life = { from: number, leftRoom: number?, ended: number? }

export type SlotRecord = {
	id: number,
	bot: boolean,
	team: number,
	play: number, -- seconds in play (live, not out)
	floors: { number }, -- seconds by storey
	inRoom: number, -- seconds in its own spawn room while live and in play
	atCover: number,
	crouched: number,
	still: number, -- the longest spell without going anywhere (3 studs), in play
	stillFrom: number,
	stillX: number,
	stillZ: number,
	walked: number, -- studs
	camping: number, -- seconds standing still near the other team's door with a line to it
	stares: number, -- times it followed an opponent through a wall (audit only)
	company: number, -- seconds with a bot of its own team within COMPANY studs on its storey
	aimed: number, -- seconds a bot had a target ...
	stared: number, -- ... and of those, seconds it stood where it was with that target too far off to fire at
	stareNow: number, -- the present spell of that
	stareMax: number, -- and the longest
	post: number, -- seconds a bot stood at a post, on its feet, with nobody to fight ...
	nose: number, -- ... and of those, seconds its look ended on something within NOSE studs (a wall in its face)
	lives: { Life },
	sprinted: number,
	lastX: number,
	lastY: number,
	lastZ: number,
	storey: number,
}

export type Record = {
	shots: { Shot },
	tags: { Tag },
	slots: { [number]: SlotRecord },
	stairs: { [number]: number }, -- by link index: times a body went up or down it
	says: { [string]: number },
	refused: { [string]: number }, -- "<bot|person>:<why>" -> count
	events: { Contract.Event },
	botMs: number, -- total milliseconds in the bots' Bots.step
	botMsMax: number,
	ticks: number, -- ticks the bots were stepped while live
	sweepsMax: number, -- the most sight checks in one tick
	sweepsSecond: number, -- the most by one list in any whole second
	firedTooSoon: number, -- balls fired sooner after the last than the fire interval (must be 0)
	-- steps a brain's body took that the server would have refused from a person (see "THE LEGS"):
	-- "<bot|person>:<inside|room|height|walls|distance>" -> count (must be empty), and the first one, in words
	legs: { [string]: number },
	legsFirst: string?,
}

export type Sim = {
	opts: Opts,
	arena: Arena.Arena,
	nav: BotNav.Nav,
	session: Session.Session,
	state: Rules.State,
	now: number,
	dt: number,
	start: number,
	bots: Bots.Bots,
	folk: Bots.Bots?,
	botWho: { [number]: number },
	folkWho: { [number]: number },
	dummyWho: { [number]: boolean },
	poses: { [number]: Pose }, -- the truth
	seenByBots: { [number]: Pose },
	seenByFolk: { [number]: Pose },
	history: { [number]: { { t: number, x: number, y: number, z: number, yaw: number, pitch: number, crouch: number } } },
	balls: { Ball },
	heard: { Bots.Heard },
	sprintAt: { [number]: number },
	homeAt: { [number]: number }, -- by slot: when its body was last inside its own spawn room
	lastShot: { [number]: number },
	nextSnap: number,
	nextSample: number,
	nextBall: number,
	delay: number,
	done: boolean,
	rec: Record,
	audit: { [number]: { [number]: { secs: number, bearing: number, x: number, z: number, told: boolean } } },
	sweepWindow: { number },
	sweepLast: number,
	legsAt: { [number]: { x: number, y: number, z: number, crouch: number } }, -- by slot: where its last step left it
}

local R = Contract.Rules
local BOT = Contract.BOT
local BIT = Wire.BIT
local SNAP = 1 / Clock.SNAP_HZ
local SAMPLE = 0.25 -- seconds between looks at what everybody is doing, for the record
local DOOR_TRUCE = 4 -- seconds: the truce a bot keeps with somebody on their own doorstep (BotBrain)
local OUT_TRUCE = 4 -- seconds: and with somebody just out of their spawn room who has not fired (BotBrain)
local COMPANY = 35 -- studs: a team-mate this near on the same storey is company
local NOSE = 5 -- studs: a look that ends this near is a look at a wall
local PERSON_POSE_LAG = 0.1 -- a person's snapshot pose is read this far back (Clock.poseTime: up + a send interval)

local Sim = {}

-- The stand-in for a fair human player: see the header. What is a bot's by contract (the reaction
-- window, the cone, the turn) is a person's own here.
Sim.FAIR = table.freeze({
	reactMin = 0.24,
	reactMax = 0.36,
	sightHalf = math.rad(50), -- a screen shows less than a bot's cone
	sightHz = 20,
	hear = 8,
	turn = 4 * math.pi, -- a wrist is faster than a bot is allowed to be
	gain = 11,
	faced = 0.2,
	errLo = math.rad(0.9),
	errHi = math.rad(2.1),
	errFar = 60,
	errSpeed = 0.8,
	errMove = 0.6,
	first = 1.5,
	second = 1.15,
	keep = 0.4,
	leadSd = 0.22,
	settle = math.rad(0.8),
	range = 0.9,
	burstMax = 3,
	pauseMin = 0.3,
	pauseMax = 0.7,
}) :: BotBrain.Profile

local function newSlotRecord(id: number, bot: boolean, team: number, floors: number): SlotRecord
	return {
		id = id,
		bot = bot,
		team = team,
		play = 0,
		floors = table.create(floors, 0),
		inRoom = 0,
		atCover = 0,
		crouched = 0,
		still = 0,
		stillFrom = 0,
		stillX = 0,
		stillZ = 0,
		walked = 0,
		camping = 0,
		stares = 0,
		company = 0,
		aimed = 0,
		stared = 0,
		stareNow = 0,
		stareMax = 0,
		post = 0,
		nose = 0,
		lives = {},
		sprinted = 0,
		lastX = 0,
		lastY = 0,
		lastZ = 0,
		storey = 0,
	}
end

function Sim.new(opts: Opts?): Sim
	local o: Opts = opts or {}
	local arena = o.arena or ArenaData.build()
	local seed = o.seed or 1
	local perSide = math.clamp(o.perSide or R.teamMin, R.teamMin, R.teamMax)
	local people = math.clamp(o.people or 0, 0, 2 * perSide)
	local start = o.start or 1000
	local sessionOpts = table.clone(Spec.session)
	sessionOpts.seed = seed
	local session = Session.new(Rules, sessionOpts)
	local botWho: { [number]: number } = {}
	local folkWho: { [number]: number } = {}
	local dummyWho: { [number]: boolean } = {}
	for i = 1, o.dummies or 0 do
		local ok, _, seat = Session.join(session, `dummy{i}`, `Scripted {i}`, start)
		assert(ok and seat ~= nil, "a scripted person could not join")
		dummyWho[seat] = true
	end
	for i = 1, people do
		local ok, _, seat = Session.join(session, `person{i}`, `Person {i}`, start)
		assert(ok and seat ~= nil, "a person could not join")
		folkWho[seat] = 0.5
	end
	if people == 0 and (o.dummies or 0) == 0 then
		-- a match of bots alone: the framework never starts one, the sim does
		local first = Contract.BOTS[1]
		local ok, _, seat = Session.join(session, { ai = true, name = first.name }, first.name, start)
		assert(ok and seat ~= nil, "the first bot could not join")
		botWho[seat] = o.skill or first.skill
	end
	local state = (session.game :: Minigame.Game).state :: Rules.State
	if o.feel ~= nil then
		Rules.tune(state, o.feel)
	end
	Rules.sync(state, start)
	local k = #session.seats - people - (o.dummies or 0)
	while #session.seats < 2 * perSide do
		k += 1
		local def = Contract.BOTS[(k - 1) % #Contract.BOTS + 1]
		local ok, _, seat = Session.join(session, { ai = true, name = def.name }, def.name, start)
		assert(ok and seat ~= nil, "a bot could not join")
		botWho[seat] = o.skill or def.skill
	end
	local bots = Bots.new(arena, { seed = seed })
	local folk: Bots.Bots? = nil
	if people > 0 then
		folk = Bots.new(arena, { seed = seed + 7717, profile = o.profile or Sim.FAIR })
	end
	local rec: Record = {
		shots = {},
		tags = {},
		slots = {},
		stairs = {},
		says = {},
		refused = {},
		events = {},
		botMs = 0,
		botMsMax = 0,
		ticks = 0,
		sweepsMax = 0,
		sweepsSecond = 0,
		firedTooSoon = 0,
		legs = {},
		legsFirst = nil,
	}
	for id, slot in state.slots do
		rec.slots[id] = newSlotRecord(id, botWho[id] ~= nil, slot.team, arena.floors)
	end
	local sim: Sim = {
		opts = o,
		arena = arena,
		nav = bots.nav,
		session = session,
		state = state,
		now = start,
		dt = o.dt or 1 / Clock.TICK_HZ,
		start = start,
		bots = bots,
		folk = folk,
		botWho = botWho,
		folkWho = folkWho,
		dummyWho = dummyWho,
		poses = {},
		seenByBots = {},
		seenByFolk = {},
		history = {},
		balls = {},
		heard = {},
		sprintAt = {},
		homeAt = {},
		lastShot = {},
		nextSnap = start,
		nextSample = start,
		nextBall = 1,
		delay = o.delay or 0.15,
		done = false,
		rec = rec,
		audit = {},
		sweepWindow = {},
		sweepLast = 0,
		legsAt = {},
	}
	Bots.sync(bots, state, botWho, sim.seenByBots, start)
	if folk ~= nil then
		Bots.sync(folk, state, folkWho, sim.seenByFolk, start)
	end
	return sim
end

-- A slot's body where the snapshot stream had it at time t.
local function sample(sim: Sim, id: number, t: number): (number?, number, number, number, number, number)
	local list = sim.history[id]
	if list == nil or #list == 0 then
		return nil, 0, 0, 0, 0, 0
	end
	local newest = list[#list]
	if t >= newest.t then
		return newest.x, newest.y, newest.z, newest.crouch, newest.yaw, newest.pitch
	end
	for i = #list - 1, 1, -1 do
		local a = list[i]
		if t >= a.t then
			local b = list[i + 1]
			local k = (t - a.t) / (b.t - a.t)
			return a.x + (b.x - a.x) * k,
				a.y + (b.y - a.y) * k,
				a.z + (b.z - a.z) * k,
				a.crouch + (b.crouch - a.crouch) * k,
				a.yaw,
				a.pitch
		end
	end
	local oldest = list[1]
	return oldest.x, oldest.y, oldest.z, oldest.crouch, oldest.yaw, oldest.pitch
end

local function inAnyRoom(sim: Sim, x: number, y: number, z: number): boolean
	return BotNav.roomOf(sim.nav, x, y, z) ~= 0
end

local function count(map: { [string]: number }, key: string)
	map[key] = (map[key] or 0) + 1
end

-- THE judgment of a click, whoever made it. On yes the ball is born now.
function Sim.judge(
	sim: Sim,
	id: number,
	ox: number,
	oy: number,
	oz: number,
	vx: number,
	vy: number,
	vz: number
): (boolean, string?)
	local pose = sim.poses[id]
	local state = sim.state
	local slot = state.slots[id]
	if pose == nil or slot == nil then
		return false, "out"
	end
	local speed = math.sqrt(vx * vx + vy * vy + vz * vz)
	if speed < 1e-6 then
		return false, "origin"
	end
	local lx, ly, lz = Body.look(pose.yaw, pose.pitch)
	local cos = (vx * lx + vy * ly + vz * lz) / speed
	if cos < math.cos(BOT.aimSlack) then
		return false, "look"
	end
	local ex, ey, ez = Body.eyePoint(pose.x, pose.y, pose.z, pose.crouch)
	if math.abs(ox - ex) > 0.05 or math.abs(oy - ey) > 0.05 or math.abs(oz - ez) > 0.05 then
		return false, "origin"
	end
	if inAnyRoom(sim, pose.x, pose.y, pose.z) then
		return false, "safe"
	end
	local sprinted = sim.sprintAt[id]
	if
		Wire.has(pose.bits, BIT.sprint)
		or (sprinted ~= nil and sprinted > sim.now - Body.SPRINT_FIRE_DELAY + Contract.MARGIN.sprint)
	then
		return false, "sprint"
	end
	local ok, why = Rules.fire(state, id, sim.now)
	if not ok then
		return false, why
	end
	local last = sim.lastShot[id]
	if last ~= nil and sim.now - last < state.feel.fireInterval - 1e-9 then
		sim.rec.firedTooSoon += 1
	end
	sim.lastShot[id] = sim.now
	return true, nil
end

-- Had the shooter been facing the victim for BOT.faced before the ball was born?
local function faced(sim: Sim, by: number, id: number, born: number): boolean
	local cosHalf = math.cos(BOT.sightHalf + math.rad(2))
	for i = 0, 5 do
		local t = born - BOT.faced * i / 5
		local sx, sy, sz, sc, yaw, pitch = sample(sim, by, t)
		local vx, vy, vz, vc = sample(sim, id, t)
		if sx == nil or vx == nil then
			return false
		end
		local dx, dy, dz = vx - sx, (vy + Arena.CHEST * Body.top(vc) / Body.STAND_TOP) - (sy + Body.eye(sc)), vz - sz
		local d = math.sqrt(dx * dx + dy * dy + dz * dz)
		local lx, ly, lz = Body.look(yaw, pitch)
		if d > 1e-3 and dx * lx + dy * ly + dz * lz < cosHalf * d then
			return false
		end
	end
	return true
end

-- A click from slot `id`: judged, and on yes its ball is in flight. `list` is the list of brains the
-- slot belongs to, if it has one (for the record: whom it was firing at); `rewind` is how far back
-- the bodies are that this ball is judged against (a bot: 0; a person: what its screen showed).
function Sim.shoot(
	sim: Sim,
	id: number,
	ox: number,
	oy: number,
	oz: number,
	vx: number,
	vy: number,
	vz: number,
	list: Bots.Bots?,
	rewind: number?
): (boolean, string?)
	local isBot = sim.botWho[id] ~= nil
	local ok, why = Sim.judge(sim, id, ox, oy, oz, vx, vy, vz)
	if not ok then
		count(sim.rec.refused, `{if isBot then "bot" else "person"}:{why}`)
		return false, why
	end
	local state = sim.state
	local brain = if list ~= nil then (list.brains :: { [number]: BotBrain.Brain })[id] else nil
	local target = if brain ~= nil then brain.target else nil
	local shot: Shot = {
		t = sim.now,
		by = id,
		bot = isBot,
		target = target,
		range = 0,
		speed = 0,
		nth = if brain ~= nil then brain.balls else 1,
		storeys = 0,
		tagged = false,
		faced = false,
		trap = false,
		fresh = false,
	}
	local truth = if target ~= nil then sim.poses[target] else nil
	if target ~= nil and truth ~= nil then
		shot.trap = BotNav.atDoor(sim.nav, state.slots[target].team, truth.x, truth.y, truth.z)
			and sim.now - (sim.lastShot[target] or -math.huge) > DOOR_TRUCE
		local home = sim.homeAt[target] or -math.huge
		shot.fresh = sim.now - home < OUT_TRUCE and (sim.lastShot[target] or -math.huge) <= home
	end
	if target ~= nil and truth ~= nil and list ~= nil then
		shot.range = math.sqrt((truth.x - ox) ^ 2 + (truth.y - oy) ^ 2 + (truth.z - oz) ^ 2)
		local floorHeight = sim.arena.floorHeight
		local mine = math.floor(sim.poses[id].y / floorHeight + 0.5)
		shot.storeys = math.abs(math.floor(truth.y / floorHeight + 0.5) - mine)
		local track = list.squad.track[target]
		if track ~= nil then
			shot.speed = math.sqrt(track.vx * track.vx + track.vz * track.vz)
		end
	end
	if target ~= nil then
		shot.faced = faced(sim, id, target, sim.now)
	end
	table.insert(sim.rec.shots, shot)
	local ball: Ball = {
		id = sim.nextBall,
		by = id,
		team = state.slots[id].team,
		born = sim.now,
		age = 0,
		rewind = rewind or 0,
		ox = ox,
		oy = oy,
		oz = oz,
		vx = vx,
		vy = vy,
		vz = vz,
		shot = shot,
	}
	sim.nextBall += 1
	table.insert(sim.balls, ball)
	table.insert(sim.heard, { kind = "born", id = id, x = ox, y = oy, z = oz, vx = vx, vy = vy, vz = vz })
	return true, nil
end

local function fire(sim: Sim, list: Bots.Bots, cmd: Bots.Command, isBot: boolean)
	Sim.shoot(
		sim,
		cmd.id,
		cmd.ox or 0,
		cmd.oy or 0,
		cmd.oz or 0,
		cmd.vx or 0,
		cmd.vy or 0,
		cmd.vz or 0,
		list,
		if isBot then 0 else sim.delay
	)
end

local function stepBalls(sim: Sim)
	local state = sim.state
	local arena = sim.arena
	local feel = state.feel
	local dt = sim.dt
	local now = sim.now
	local balls = sim.balls
	for i = #balls, 1, -1 do
		local ball = balls[i]
		local t0 = ball.age
		local t1 = t0 + dt
		local p0x, p0y, p0z =
			Ballistics.position(ball.ox, ball.oy, ball.oz, ball.vx, ball.vy, ball.vz, feel.ballDrop, t0)
		local p1x, p1y, p1z =
			Ballistics.position(ball.ox, ball.oy, ball.oz, ball.vx, ball.vy, ball.vz, feel.ballDrop, t1)
		local wall = arena.sweep(p0x, p0y, p0z, p1x, p1y, p1z)
		local best: number? = wall
		local struck: number? = nil
		local hx, hy, hz = 0, 0, 0
		for id, slot in state.slots do
			if not slot.on or slot.team == ball.team or not Rules.canBeHit(state, id, now) then
				continue
			end
			local x, y, z, crouch = sample(sim, id, now - ball.rewind)
			if x == nil then
				continue
			end
			if BotNav.roomOf(sim.nav, x, y, z) == slot.team then
				continue -- in its own spawn room: it cannot be hit
			end
			local s, ax, ay, az = Hit.body(arena.sweep, p0x, p0y, p0z, p1x, p1y, p1z, x, y, z, crouch)
			if s ~= nil and (best == nil or s < best) then
				best, struck, hx, hy, hz = s, id, ax, ay, az
			end
		end
		if best == nil then
			ball.age = t1
			if t1 >= R.ballTtl then
				table.remove(balls, i)
			end
			continue
		end
		table.remove(balls, i)
		if struck == nil then
			local s = best
			hx, hy, hz = p0x + (p1x - p0x) * s, p0y + (p1y - p0y) * s, p0z + (p1z - p0z) * s
		end
		table.insert(sim.heard, { kind = "ended", id = ball.by, x = hx, y = hy, z = hz })
		if struck ~= nil and Rules.tag(state, ball.by, struck, now, ball.born) then
			table.insert(sim.heard, { kind = "tag", id = struck, by = ball.by, x = hx, y = hy, z = hz })
			if ball.shot.target == struck then
				ball.shot.tagged = true
			end
			local rs = sim.rec.slots[struck]
			local victim = sim.poses[struck]
			local onStep = victim ~= nil
				and BotNav.atDoor(sim.nav, state.slots[struck].team, victim.x, victim.y, victim.z)
			local life = if rs ~= nil then rs.lives[#rs.lives] else nil
			local sinceRoom = math.huge
			local aware, fought = false, false
			for _, list in { sim.bots, sim.folk :: any } do
				local vb = if list ~= nil then (list.brains :: { [number]: BotBrain.Brain })[struck] else nil
				if vb ~= nil then
					local c = (vb.con :: { [number]: any })[ball.by]
					aware = c ~= nil and now - c.seen < 1
					fought = vb.target == ball.by and vb.balls > 0
				end
			end
			if life ~= nil then
				life.ended = now
				sinceRoom = if life.leftRoom ~= nil then now - life.leftRoom else 0
			end
			table.insert(sim.rec.tags, {
				t = now,
				by = ball.by,
				id = struck,
				byBot = sim.botWho[ball.by] ~= nil,
				idBot = sim.botWho[struck] ~= nil,
				range = math.sqrt((hx - ball.ox) ^ 2 + (hy - ball.oy) ^ 2 + (hz - ball.oz) ^ 2),
				faced = faced(sim, ball.by, struck, ball.born),
				sinceRoom = sinceRoom,
				doorstep = onStep,
				quiet = onStep and now - (sim.lastShot[struck] or -math.huge) > DOOR_TRUCE,
				stray = ball.shot.target ~= struck,
				aware = aware,
				fought = fought,
			})
		end
	end
end

-- The snapshot tick: every body's pose, quantised as the wire carries it, into its history.
local function snapshot(sim: Sim)
	local now = sim.now
	for id, slot in sim.state.slots do
		local pose = sim.poses[id]
		if not slot.on or pose == nil then
			continue
		end
		local list = sim.history[id]
		if list == nil then
			list = {}
			sim.history[id] = list
		end
		local x, y, z, crouch = Wire.quantPose(pose.x, pose.y, pose.z, pose.crouch)
		table.insert(list, { t = now, x = x, y = y, z = z, yaw = pose.yaw, pitch = pose.pitch, crouch = crouch })
		while #list > 0 and now - list[1].t > Clock.HISTORY_SECS + 0.3 do
			table.remove(list, 1)
		end
	end
end

-- What each list of brains is shown of the others: the bots see a person where its snapshot pose is,
-- a stand-in person sees everybody else `delay` ago; each sees its own slots as they are.
local function show(sim: Sim)
	local now = sim.now
	local poses = sim.poses
	for id in sim.state.slots do
		local truth = poses[id]
		if truth == nil then
			continue
		end
		if sim.folkWho[id] ~= nil or sim.dummyWho[id] then
			if sim.folkWho[id] ~= nil then
				sim.seenByFolk[id] = truth
			end
			local seen = sim.seenByBots[id]
			if seen == nil or seen == truth then
				seen = table.clone(truth)
				sim.seenByBots[id] = seen
			end
			local x, y, z, crouch, yaw, pitch = sample(sim, id, now - PERSON_POSE_LAG)
			if x ~= nil then
				seen.x, seen.y, seen.z, seen.crouch, seen.yaw, seen.pitch = x, y, z, crouch, yaw, pitch
			end
			seen.bits = truth.bits
		else
			sim.seenByBots[id] = truth
			if sim.folk ~= nil then
				local seen = sim.seenByFolk[id]
				if seen == nil or seen == truth then
					seen = table.clone(truth)
					sim.seenByFolk[id] = seen
				end
				local x, y, z, crouch, yaw, pitch = sample(sim, id, now - sim.delay)
				if x ~= nil then
					seen.x, seen.y, seen.z, seen.crouch, seen.yaw, seen.pitch = x, y, z, crouch, yaw, pitch
				end
				seen.bits = truth.bits
			end
		end
	end
end

local function storeyOf(arena: Arena.Arena, y: number): number
	return math.clamp(math.floor(y / arena.floorHeight + 0.5), 0, arena.floors - 1)
end

-- Four times a second: what everybody is doing, for the record.
local function observe(sim: Sim, span: number)
	local state = sim.state
	local arena = sim.arena
	local nav = sim.nav
	local now = sim.now
	if state.phase ~= "live" then
		return
	end
	for id, slot in state.slots do
		local rs = sim.rec.slots[id]
		local pose = sim.poses[id]
		if rs == nil or pose == nil or not slot.on then
			continue
		end
		local life = rs.lives[#rs.lives]
		if slot.out then
			rs.stillFrom = now
			rs.stillX, rs.stillZ = pose.x, pose.z
			rs.lastX, rs.lastY, rs.lastZ = pose.x, pose.y, pose.z
			continue
		end
		rs.play += span
		local storey = storeyOf(arena, pose.y)
		rs.floors[storey + 1] += span
		local room = BotNav.roomOf(nav, pose.x, pose.y, pose.z)
		if room == slot.team then
			rs.inRoom += span
		elseif life ~= nil and life.leftRoom == nil then
			life.leftRoom = now
		end
		if pose.crouch > 0.5 then
			rs.crouched += span
		end
		if Wire.has(pose.bits, BIT.sprint) then
			rs.sprinted += span
		end
		local moved = math.sqrt((pose.x - rs.lastX) ^ 2 + (pose.z - rs.lastZ) ^ 2)
		if moved < 12 then
			rs.walked += moved
		end
		-- a stair: the body is half way between two storeys
		local between = pose.y / arena.floorHeight
		local wasBetween = rs.lastY / arena.floorHeight
		if math.floor(between + 0.5) ~= math.floor(wasBetween + 0.5) and moved < 12 then
			local best, bestD = 0, math.huge
			for index, link in arena.links do
				if link.kind == "stair" then
					local a, b = arena.nodes[link.a], arena.nodes[link.b]
					local d = (pose.x - (a.x + b.x) / 2) ^ 2
						+ (pose.y - (a.y + b.y) / 2) ^ 2
						+ (pose.z - (a.z + b.z) / 2) ^ 2
					if d < bestD then
						best, bestD = index, d
					end
				end
			end
			if best ~= 0 then
				sim.rec.stairs[best] = (sim.rec.stairs[best] or 0) + 1
			end
		end
		rs.lastX, rs.lastY, rs.lastZ = pose.x, pose.y, pose.z
		if (pose.x - rs.stillX) ^ 2 + (pose.z - rs.stillZ) ^ 2 > 9 then
			rs.stillFrom = now
			rs.stillX, rs.stillZ = pose.x, pose.z
		elseif room ~= slot.team then
			rs.still = math.max(rs.still, now - rs.stillFrom)
		end
		-- company: a bot of its own team near by on this storey
		for other, mate in state.slots do
			local mp = sim.poses[other]
			if
				other ~= id
				and mp ~= nil
				and mate.on
				and not mate.out
				and mate.team == slot.team
				and sim.botWho[other] ~= nil
				and math.abs(mp.y - pose.y) < 5
				and (mp.x - pose.x) ^ 2 + (mp.z - pose.z) ^ 2 < COMPANY * COMPANY
			then
				rs.company += span
				break
			end
		end
		-- its nose to a wall: at a post, standing, nobody to fight, and the look ends within NOSE studs
		local brain = if rs.bot then (sim.bots.brains :: { [number]: BotBrain.Brain })[id] else nil
		-- staring: it has a target, the target is further off than it fires, and it is not going anywhere
		local aimedAt = if brain ~= nil and brain.target ~= nil then sim.poses[brain.target] else nil
		if brain ~= nil and aimedAt ~= nil then
			rs.aimed += span
			local reach = brain.profile.range * state.feel.ballSpeed
			local off = (aimedAt.x - pose.x) ^ 2 + (aimedAt.y - pose.y) ^ 2 + (aimedAt.z - pose.z) ^ 2
			if off > reach * reach and brain.speed < 1 then
				rs.stared += span
				rs.stareNow += span
				rs.stareMax = math.max(rs.stareMax, rs.stareNow)
			else
				rs.stareNow = 0
			end
		else
			rs.stareNow = 0
		end
		if brain ~= nil and brain.mode == "hold" and brain.target == nil and pose.crouch < 0.3 then
			rs.post += span
			local ex, ey, ez = Body.eyePoint(pose.x, pose.y, pose.z, pose.crouch)
			local lx, ly, lz = Body.look(pose.yaw, pose.pitch)
			if arena.sweep(ex, ey, ez, ex + lx * NOSE, ey + ly * NOSE, ez + lz * NOSE) ~= nil then
				rs.nose += span
			end
		end
		-- at cover: within a stride of a cover spot of this storey
		for node, _ in nav.coverAt do
			local n = nav.nodes[node]
			if math.abs(n.y - pose.y) < 1 and (n.x - pose.x) ^ 2 + (n.z - pose.z) ^ 2 < 16 then
				rs.atCover += span
				break
			end
		end
		-- camping: standing still for some seconds near the other team's door, with a line to it
		if now - rs.stillFrom > 4 then
			for node, owner in nav.door do
				if owner ~= 0 and owner ~= slot.team then
					local n = nav.nodes[node]
					local flat = math.sqrt((n.x - pose.x) ^ 2 + (n.z - pose.z) ^ 2)
					if
						math.abs(n.y - pose.y) < 2
						and flat < BotNav.KEEP_OFF
						and arena.sweep(pose.x, pose.y + Arena.EYE, pose.z, n.x, n.y + Arena.CHEST, n.z) == nil
					then
						rs.camping += span
						break
					end
				end
			end
		end
		-- the audit: a bot whose look stays on an opponent it has no line to (within 4 degrees, at
		-- every look for a second or more) while that body goes further ACROSS the look than "on it"
		-- is wide at its range and its bearing from the bot swings by three times that width: the
		-- look is going with it through the wall. (A look that rests on the place somebody vanished,
		-- while they stand there or walk through it, follows nobody; nor does one that is on, or
		-- turning on to, somebody in plain sight within 20 degrees of it, aim error and lead
		-- included, with another behind the wall beyond.)
		if sim.opts.audit and rs.bot then
			local mine = sim.audit[id]
			if mine == nil then
				mine = {}
				sim.audit[id] = mine
			end
			local lx, ly, lz = Body.look(pose.yaw, pose.pitch)
			local ex, ey, ez = Body.eyePoint(pose.x, pose.y, pose.z, pose.crouch)
			local hidden: { [number]: boolean } = {}
			local explained = false
			for other, os in state.slots do
				local op = sim.poses[other]
				if os.team == slot.team or not os.on or os.out or op == nil then
					continue
				end
				local dx, dy, dz = op.x - ex, op.y + Arena.CHEST - ey, op.z - ez
				local d = math.sqrt(dx * dx + dy * dy + dz * dz)
				local cos = if d > 1e-3 then (dx * lx + dy * ly + dz * lz) / d else 1
				if cos > math.cos(math.rad(20)) then
					if arena.sweep(ex, ey, ez, op.x, op.y + Arena.CHEST, op.z) == nil then
						explained = true
					elseif d > 4 and cos > math.cos(math.rad(4)) then
						hidden[other] = true
					end
				end
			end
			for other, os in state.slots do
				local op = sim.poses[other]
				if os.team == slot.team or not os.on or os.out or op == nil then
					mine[other] = nil
					continue
				end
				if hidden[other] and not explained then
					local dx, dy, dz = op.x - ex, op.y + Arena.CHEST - ey, op.z - ez
					local d = math.sqrt(dx * dx + dy * dy + dz * dz)
					local bearing = math.atan2(-dx, -dz)
					local streak = mine[other]
					if streak == nil then
						streak = { secs = 0, bearing = bearing, x = op.x, z = op.z, told = false }
						mine[other] = streak
					end
					streak.secs += span
					local flat = math.max(1e-6, math.sqrt(lx * lx + lz * lz))
					local across = math.abs((op.x - streak.x) * lz - (op.z - streak.z) * lx) / flat
					local swung = math.abs((bearing - streak.bearing + math.pi) % (2 * math.pi) - math.pi)
					if
						streak.secs >= 1
						and across >= math.max(5, 0.2 * d)
						and swung >= math.rad(12)
						and not streak.told
					then
						streak.told = true
						rs.stares += 1
					end
				else
					mine[other] = nil
				end
			end
		end
	end
end

-- The legs (see the header): the step each brain's body has just taken, judged as a person's would be.
local function legs(sim: Sim, who: { [number]: number }, isBot: boolean)
	local state = sim.state
	local arena = sim.arena
	local feel = state.feel
	local half = arena.half
	for id in who do
		local slot = state.slots[id]
		local pose = sim.poses[id]
		if slot == nil or pose == nil or not slot.on then
			sim.legsAt[id] = nil
			continue
		end
		local was = sim.legsAt[id]
		if was == nil then
			was = { x = pose.x, y = pose.y, z = pose.z, crouch = pose.crouch }
			sim.legsAt[id] = was
		end
		local x, y, z = pose.x, pose.y, pose.z
		local why: string? = nil
		local flat = math.sqrt((x - was.x) ^ 2 + (z - was.z) ^ 2)
		local chest = y + Arena.CHEST
		local ground = arena.ground(x, y + 0.6, z)
		-- (out, or not live: it stands)
		local most = if slot.out or state.phase ~= "live"
			then 0
			else Body.speed(was.crouch, Wire.has(pose.bits, BIT.sprint), feel) * sim.dt
		local outside = x < -half or x > half or z < -half or z > half or y < 0 or y > arena.height
		if outside or arena.sweep(x, chest, z, x, chest + 0.01, z) ~= nil then
			why = "inside"
		elseif Arena.inRoom(arena.spawnRooms[3 - slot.team], x, y, z) then
			why = "room"
		elseif ground == nil or math.abs(y - ground) > 0.05 then
			why = "height"
		elseif flat > 0 and not Arena.clearPath(arena.sweep, was.x, was.z, x, z, math.max(was.y, y) + Arena.CHEST) then
			why = "walls"
		elseif flat > most + 1e-6 then
			why = "distance"
		end
		if why ~= nil then
			count(sim.rec.legs, `{if isBot then "bot" else "person"}:{why}`)
			if sim.rec.legsFirst == nil then
				sim.rec.legsFirst = string.format(
					"seat %d at %.1f s: %s, from (%.2f, %.2f, %.2f) to (%.2f, %.2f, %.2f)",
					id,
					sim.now - sim.start,
					why,
					was.x,
					was.y,
					was.z,
					x,
					y,
					z
				)
			end
		end
		was.x, was.y, was.z, was.crouch = x, y, z, pose.crouch
	end
end

Sim.legs = legs

local function handle(sim: Sim, list: Bots.Bots, commands: { Bots.Command }, isBot: boolean)
	for _, cmd in commands do
		if cmd.kind == "fire" then
			fire(sim, list, cmd, isBot)
		elseif cmd.kind == "reload" then
			Rules.reload(sim.state, cmd.id, sim.now)
		elseif cmd.kind == "say" then
			count(sim.rec.says, cmd.line or "?")
		end
	end
end

-- Put a scripted person somewhere at once (its history starts again: nobody is judged along the jump).
function Sim.teleport(sim: Sim, id: number, x: number, y: number, z: number, yaw: number)
	local pose = sim.poses[id]
	if pose == nil then
		return
	end
	pose.x, pose.y, pose.z, pose.yaw, pose.pitch = x, y, z, yaw, 0
	sim.history[id] = nil
	local seen = sim.seenByBots[id]
	if seen ~= nil and seen ~= pose then
		seen.x, seen.y, seen.z, seen.yaw, seen.pitch, seen.crouch = x, y, z, yaw, 0, pose.crouch
	end
end

-- One server step.
function Sim.tick(sim: Sim)
	if sim.done then
		return
	end
	local state = sim.state
	local arena = sim.arena
	sim.now += sim.dt
	local now = sim.now
	Rules.sync(state, now)
	-- 1. the match's events: placements
	for _, e in Rules.drain(state) do
		table.insert(sim.rec.events, e)
		if e.kind == "respawn" then
			local id = e.id :: number
			local sp = arena.spawns[e.team :: number][e.spawn :: number]
			local pose = sim.poses[id]
			if pose == nil then
				pose = { x = 0, y = 0, z = 0, yaw = 0, pitch = 0, crouch = 0, bits = 0 }
				sim.poses[id] = pose
			end
			pose.x, pose.y, pose.z, pose.yaw, pose.pitch, pose.crouch, pose.bits = sp.x, sp.y, sp.z, sp.yaw, 0, 0, 0
			sim.history[id] = nil
			sim.sprintAt[id] = nil
			sim.audit[id] = nil
			local rs = sim.rec.slots[id]
			if rs == nil then
				rs = newSlotRecord(id, sim.botWho[id] ~= nil, e.team :: number, arena.floors)
				sim.rec.slots[id] = rs
			end
			table.insert(rs.lives, { from = now })
			rs.lastX, rs.lastY, rs.lastZ = sp.x, sp.y, sp.z
			rs.stillFrom, rs.stillX, rs.stillZ = now, sp.x, sp.z
			show(sim)
			if sim.botWho[id] ~= nil then
				Bots.place(sim.bots, id, pose, now)
			elseif sim.folk ~= nil then
				Bots.place(sim.folk, id, pose, now)
			end
		end
	end
	-- 2. the brains
	local heard = sim.heard
	sim.heard = {}
	show(sim)
	if not sim.opts.frozen then
		local before = sim.bots.squad.sweeps
		local t0 = os.clock()
		local commands = Bots.step(sim.bots, state, sim.seenByBots, heard, now, sim.dt)
		local ms = (os.clock() - t0) * 1000
		if state.phase == "live" then
			sim.rec.botMs += ms
			sim.rec.botMsMax = math.max(sim.rec.botMsMax, ms)
			sim.rec.ticks += 1
			local swept = sim.bots.squad.sweeps - before
			sim.rec.sweepsMax = math.max(sim.rec.sweepsMax, swept)
			-- the most sight checks in any whole second
			table.insert(sim.sweepWindow, swept)
			sim.sweepLast += swept
			local span = math.floor(1 / sim.dt + 0.5)
			if #sim.sweepWindow > span then
				sim.sweepLast -= table.remove(sim.sweepWindow, 1) :: number
			end
			sim.rec.sweepsSecond = math.max(sim.rec.sweepsSecond, sim.sweepLast)
		end
		handle(sim, sim.bots, commands, true)
		local folk = sim.folk
		if folk ~= nil then
			handle(sim, folk, Bots.step(folk, state, sim.seenByFolk, heard, now, sim.dt), false)
		end
	end
	local script = sim.opts.script
	if script ~= nil then
		for id in sim.dummyWho do
			local slot = state.slots[id]
			local pose = sim.poses[id]
			if slot ~= nil and slot.on and not slot.out and pose ~= nil then
				script(sim, id, pose, now, sim.dt)
			end
		end
	end
	for id, pose in sim.poses do
		if Wire.has(pose.bits, BIT.sprint) then
			sim.sprintAt[id] = now
		end
		local slot = state.slots[id]
		if slot ~= nil and BotNav.roomOf(sim.nav, pose.x, pose.y, pose.z) == slot.team then
			sim.homeAt[id] = now
		end
	end

	-- 3. the balls
	stepBalls(sim)
	-- 4. the snapshot tick
	if now >= sim.nextSnap then
		sim.nextSnap += SNAP
		if sim.nextSnap < now then
			sim.nextSnap = now + SNAP
		end
		snapshot(sim)
	end
	if now >= sim.nextSample then
		sim.nextSample += SAMPLE
		observe(sim, SAMPLE)
	end
	-- 5. the Session's own step: the match model moves up to the clock
	Session.step(sim.session, now)
	if sim.session.phase ~= "playing" then
		sim.done = true
	end
end

-- To the end of the match (or to `untilTime` on the sim's clock).
function Sim.run(sim: Sim, untilTime: number?): Sim
	while not sim.done and (untilTime == nil or sim.now < untilTime) do
		Sim.tick(sim)
	end
	return sim
end

return Sim
