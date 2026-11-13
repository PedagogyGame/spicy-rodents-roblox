--!strict
-- ServerScriptService.Server.Minigames.Paintball.BotBrain
-- One paintball bot's brain (checklist PB-10): what it knows, where it is going, where it is looking
-- and when it pulls the trigger. Pure numbers; Bots (beside this file) owns the list of brains, tells
-- each what was heard, and calls `step` once a server tick. A brain keeps its own exact pose and
-- writes it to the service's table every tick; it never reads its own entry back (the service
-- quantises what it snapshots).
--
-- WHAT A BRAIN DOES IN A TICK, IN ORDER
--   senses   a ball that was heard becomes an ALERT after the reaction time: the bot turns to where
--            it came from, and ducks, sidesteps or runs for cover rather than stand there. A SIGHT
--            CHECK (one arena.sweep, eye to chest; at most Profile.sightHz a second, the bots'
--            checks falling on different ticks) is spent on one opponent inside the sight cone: the
--            present target every other check, otherwise whoever has gone longest unlooked-at. An
--            opponent seen starts a SIGHTING; it is acted on only once the sighting is older than
--            this bot's reaction time, and fired on only once it is older than BOT.faced as well.
--            A sighting that lapses (no clear line for LAPSE) starts again from nothing.
--   thinks   (ten times a second) chooses the target (the nearest sighting, with some loyalty to the
--            present one); decides how to fight (stand, keep walking, or go to cover: mostly cover
--            when reloading, nearly empty or already shot at, and never standing in its spawn room
--            or on its way out to its storey); moves on when shot at where it stands, and after
--            eight seconds of fighting from one spot; reloads when it is quiet; and when there is
--            nobody to fight walks the building: a goal (mostly cover spots; on a storey chosen so
--            the team spreads: each life has a storey of its own, the one its team has fewest on,
--            and goes there first; then that storey, its neighbours, and wherever opponents were
--            last seen), a route with its own taste (BotNav), a few seconds' watch there, then
--            another. Behind low cover it bobs: crouched it is wholly hidden, standing it sees and
--            shoots. Behind a pillar it steps out to a peek point and back, and looks past the
--            pillar's edges, not at it. A bot that has not been anywhere else for ten seconds is
--            sent somewhere, whatever it was doing (PB-10: never stuck).
--   moves    along the links of the graph in straight lines, feet on arena.ground, at Body's speeds
--            with the match's feel; sprints only when nothing has been seen or heard for a while.
--   looks    turns its yaw and pitch towards what it wants to look at, never faster than
--            Profile.turn: along its path, round its post, at a noise, at where a target vanished
--            (the place, not the target: see "aims"), or along its AIM.
--   aims     at where the target is AS FAR AS IT KNOWS: where its last sight check saw it, carried
--            on at the speed it was going then (it never reads where a body it cannot see has got
--            to, so a target that turns between two checks is led wrongly, as a person would lead
--            it). Ballistics.aim at where that will be when the ball arrives (x a lead factor that
--            is redrawn for every ball), plus an ERROR in yaw and pitch, so many sigmas, redrawn
--            for every ball and keeping some of the last one's (it walks its balls in). A sigma is
--            what the moment makes it: wider with range, with the target's speed, with the bot's
--            own, at a low skill, and widest on the first ball at a new target (the warning splat).
--   fires    only along its own look, when the look has settled on the aim, in bursts with pauses;
--            only when Rules.canFire says so and the target may be hit; never while sprinting or
--            within Body.SPRINT_FIRE_DELAY of it; never from a spawn room, at somebody inside one, or
--            at somebody on their own doorstep who has not fired for DOOR_TRUCE (BotNav.atDoor:
--            nobody is tagged by a bot in the first strides out of their spawn room, and nobody
--            fights from their doorstep unanswered).
-- A PROFILE is the set of numbers that make a brain the kind of player it is. DEFAULT is the bot
-- (the fairness numbers are Contract.BOT's); tools/games/paintball/bots passes another to stand in
-- for a fair human player when it measures how hard the bots are.
-- Interface: DEFAULT; new(nav, id, team, skill, seed, profile) -> Brain; place(b, squad, x, y, z,
--   yaw, state, now); alert(b, x, y, z, now); say(b, squad, now, out, line, n?); step(b, squad, state,
--   poses, now, dt, out); types
--   Profile, Brain, Squad, Track

local Import = require("../../Import")
local ArenaModule: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Arena)) =
	Import.shared("Minigames/Paintball/Arena")
local Ballistics: typeof(require(game.ReplicatedStorage.Shared.Paintball.Ballistics)) =
	Import.shared("Paintball/Ballistics")
local Body: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Body)) =
	Import.shared("Minigames/Paintball/Body")
local Contract: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Contract)) =
	Import.shared("Minigames/Paintball/Contract")
local Rules: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Rules)) =
	Import.shared("Minigames/Paintball/Rules")
local Rng: typeof(require(game.ReplicatedStorage.Shared.Util.Rng)) = Import.shared("Util/Rng")
local Wire: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Wire)) =
	Import.shared("Minigames/Paintball/Wire")
local BotNav = require("./BotNav")

type Pose = typeof(Contract.T.Pose)
type State = typeof(Rules.T.State)
type Slot = typeof(Rules.T.Slot)
-- (the part of Shared/Util/Rng a brain uses; its generic members do not survive a typeof)
type RngT = { next: () -> number, range: (a: number, b: number) -> number, int: (a: number, b: number) -> number }

export type Profile = {
	reactMin: number, -- seconds from a sighting or a noise to acting on it
	reactMax: number,
	sightHalf: number, -- radians either side of the look inside which an opponent can be seen
	sightHz: number, -- sight checks a second, at most
	hear: number, -- studs
	turn: number, -- radians a second, the fastest the look turns
	gain: number, -- how briskly the look closes on what it wants (1/s), before the cap
	faced: number, -- seconds a sighting must have lasted before a ball is fired at it
	errLo: number, -- radians: the aim error (one sigma, yaw) of skill 1 ...
	errHi: number, -- ... and of skill 0, at close range on a still target
	errFar: number, -- studs at which range alone has doubled the error
	errSpeed: number, -- more error for each Body.WALK of the target's speed
	errMove: number, -- and for each Body.WALK of the bot's own
	first: number, -- the error on the first ball at a new target, as a multiple
	second: number, -- and on the second
	keep: number, -- how much of one ball's error the next keeps (0..1)
	leadSd: number, -- the spread of the lead factor round 1, at skill 0.5
	settle: number, -- radians: the look is on the aim when it is this near
	range: number, -- seconds of ball flight: the furthest target it fires at
	burstMax: number, -- balls in a burst, at most
	pauseMin: number, -- seconds between bursts
	pauseMax: number,
}

-- A sighting of one opponent.
type Contact = {
	seen: number, -- when a clear line was last confirmed
	first: number, -- when this sighting began
	react: number, -- this sighting is acted on once it is this old
	checked: number, -- when a sight check was last spent on it
	x: number, -- where it was when last seen ...
	y: number,
	z: number,
	vx: number, -- ... how fast it was going over the floor ...
	vz: number,
	crouch: number, -- ... and how far it was crouched
}

-- What the whole match's bots share (Bots owns it).
export type Track = { x: number, y: number, z: number, vx: number, vz: number, t: number }
export type Squad = {
	track: { [number]: Track }, -- by slot: where each body is and how fast it is going
	claimed: { [number]: number }, -- by node: the bot that is going to, or standing on, it
	heat: { { number } }, -- by team, by floor + 1: when that team last saw an opponent there
	spot: { { x: number, y: number, z: number, at: number } }, -- by team: its last sighting
	saidAt: { number }, -- by team: when one of its bots last called out
	calledFloor: { number }, -- by team: the storey it last called ("They are on three!")
	calledAt: { number },
	home: { [number]: number }, -- by bot: the storey it has made its own for this life
	side: { [number]: number }, -- by bot: its team
	firedAt: { [number]: number }, -- by slot: when it last fired a ball (everybody hears a marker)
	people: { [number]: number }, -- by slot: the team of a seat that is on and is not one of these bots (a person)
	escort: { [number]: number }, -- by bot: the person of its team it is keeping company (see COMPANY)
	sightLeft: number, -- sight checks left this tick (the tick's share: Bots.step sets it)
	routeLeft: number, -- route searches left this tick
	tick: number,
	sweeps: number, -- sight checks made this match (the cost report)
	routes: number,
}

export type Brain = {
	id: number,
	team: number,
	skill: number,
	profile: Profile,
	rng: RngT,
	nav: BotNav.Nav,
	taste: { number },
	placed: boolean,
	fresh: boolean, -- placed, and not yet set out: its first goal is on its own storey
	outbound: boolean, -- on its way to that first goal
	-- the body
	x: number,
	y: number,
	z: number,
	yaw: number,
	pitch: number,
	crouch: number,
	wantCrouch: boolean,
	sprint: boolean,
	sprintAt: number, -- when the sprint bit was last set
	speed: number, -- over the floor, this tick
	wasOut: boolean,
	-- the way
	mode: "wait" | "travel" | "hold",
	goAt: number,
	at: number, -- the node it last stood on
	path: { number }?,
	leg: number, -- the index in path of the node it is walking to
	goal: number, -- the node it means to stand on (0: none)
	halt: boolean, -- stopped where it is to fight
	pushUntil: number, -- it does not stop to fight before this (it has stood about long enough)
	holdUntil: number,
	bobAt: number, -- when it next changes between crouched and standing behind low cover
	peekX: number?, -- the peek point it is at, or walking to
	peekZ: number?,
	peekBack: boolean, -- walking back from it to the node
	peekAt: number, -- when it next steps out, or back
	movedAt: number, -- when it was last somewhere else (the stuck watch)
	watchAt: number, -- when the stuck watch may next send it off
	movedX: number,
	movedZ: number,
	-- the senses
	con: { [number]: Contact },
	nextSight: number,
	nextThink: number,
	sightTurn: number,
	alertAt: number?, -- a noise becomes known at this time ...
	alertX: number, -- ... from here
	alertY: number,
	alertZ: number,
	alarm: number, -- when it last knew it was being shot at
	whizz: { { at: number, x: number, y: number, z: number, by: number, seq: number } },
	-- the fight
	target: number?,
	stance: "stand" | "push" | "cover",
	fightAt: number, -- when this fight began from where it stands
	shiftAt: number, -- when it last moved because it was shot at
	lostAt: number,
	lostX: number,
	lostY: number,
	lostZ: number,
	balls: number, -- fired at the present target
	errYaw: number, -- the error of the next ball, in sigmas (spread() says how wide a sigma is)
	errPitch: number,
	lead: number,
	burst: number, -- balls left in the burst
	pauseUntil: number,
	contactAt: number, -- when it last saw anybody
	-- the look when there is nobody to aim at
	lookUntil: number, -- looking at (lookX, lookY, lookZ) until then
	lookX: number,
	lookY: number,
	lookZ: number,
	scanAt: number,
	scanYaw: number,
	scanPitch: number,
	wantYaw: number,
	wantPitch: number,
	aimed: number?, -- the target the look was following last tick (its aim's own turning is added to the look's)
	aimYaw: number,
	aimPitch: number,
	huntable: boolean, -- it has just lost sight of somebody and has not yet decided whether to go and see
	saidAt: number,
}

type Command = {
	id: number,
	kind: "fire" | "reload" | "say",
	ox: number?,
	oy: number?,
	oz: number?,
	vx: number?,
	vy: number?,
	vz: number?,
	line: string?,
	n: number?,
}

local BIT = Wire.BIT
local BOT = Contract.BOT

local BotBrain = {}

BotBrain.DEFAULT = table.freeze({
	reactMin = BOT.reactMin,
	reactMax = BOT.reactMax,
	sightHalf = BOT.sightHalf,
	sightHz = BOT.sightHz,
	hear = BOT.hear,
	turn = BOT.turn,
	gain = 9,
	faced = BOT.faced,
	errLo = math.rad(0.7),
	errHi = math.rad(2.5),
	errFar = 90,
	errSpeed = 0.9,
	errMove = 0.7,
	first = 2.0,
	second = 1.25,
	keep = 0.3,
	leadSd = 0.3,
	settle = math.rad(0.8),
	range = 0.8,
	burstMax = 3,
	pauseMin = 0.35,
	pauseMax = 0.95,
}) :: Profile

local VIS = 0.36 -- a clear line confirmed this recently: the opponent is in sight
local LAPSE = 0.6 -- a sighting with no clear line for this long is over
local SIGHT = 150 -- studs: nobody is looked for further off
local THINK = 0.1 -- seconds between thoughts
local QUIET = 3 -- seconds with nothing seen or heard before a bot sprints or reloads at leisure
local SAY_EVERY = 12 -- seconds between one bot's call-outs
local TEAM_SAY_EVERY = 8 -- and between one team's
local DOOR_TRUCE = 4 -- seconds since its last ball that somebody on their own doorstep may still be fired at
local CHEST = ArenaModule.CHEST
-- COMPANY: a person is never left to play alone in a five-storey building. Up to ESCORTS bots of a
-- person's team choose their posts within a short run of where that person is (their team-mates know
-- where they are, as any player does from the name tags), move on when the person does, and so are
-- beside them when the paint flies. The rest of the team plays its own game.
local ESCORTS = 2 -- bots that keep one person company, at most
local ESCORT_NEAR, ESCORT_FAR = 8, 28 -- studs from the person a post is looked for between
local ESCORT_LEFT = 40 -- studs: the person has gone, the bot leaves its post to follow

local function wrap(a: number): number
	return (a + math.pi) % (2 * math.pi) - math.pi
end

local function gauss(rng: RngT): number
	local u = math.max(rng.next(), 1e-9)
	return math.sqrt(-2 * math.log(u)) * math.cos(2 * math.pi * rng.next())
end

-- the height above the feet a body is looked for at: its chest, lower as it crouches
local function chestOf(crouch: number): number
	return CHEST * Body.top(crouch) / Body.STAND_TOP
end

function BotBrain.new(nav: BotNav.Nav, id: number, team: number, skill: number, seed: number, profile: Profile): Brain
	local rng: RngT = Rng.new(seed * 9973 + id * 7919 + 17) :: any
	return {
		id = id,
		team = team,
		skill = math.clamp(skill, 0, 1),
		profile = profile,
		rng = rng,
		nav = nav,
		taste = BotNav.taste(nav, seed * 31 + id * 131),
		placed = false,
		fresh = false,
		outbound = false,
		x = 0,
		y = 0,
		z = 0,
		yaw = 0,
		pitch = 0,
		crouch = 0,
		wantCrouch = false,
		sprint = false,
		sprintAt = -math.huge,
		speed = 0,
		wasOut = false,
		mode = "wait",
		goAt = 0,
		at = 1,
		path = nil,
		leg = 1,
		goal = 0,
		halt = false,
		pushUntil = -math.huge,
		holdUntil = 0,
		bobAt = 0,
		peekX = nil,
		peekZ = nil,
		peekBack = false,
		peekAt = 0,
		movedAt = 0,
		watchAt = 0,
		movedX = 0,
		movedZ = 0,
		con = {},
		nextSight = 0,
		nextThink = 0,
		sightTurn = 0,
		alertAt = nil,
		alertX = 0,
		alertY = 0,
		alertZ = 0,
		alarm = -math.huge,
		whizz = {},
		target = nil,
		stance = "stand",
		fightAt = 0,
		shiftAt = -math.huge,
		lostAt = -math.huge,
		lostX = 0,
		lostY = 0,
		lostZ = 0,
		balls = 0,
		errYaw = 0,
		errPitch = 0,
		lead = 1,
		burst = 1,
		pauseUntil = 0,
		contactAt = -math.huge,
		lookUntil = -math.huge,
		lookX = 0,
		lookY = 0,
		lookZ = 0,
		scanAt = 0,
		scanYaw = 0,
		scanPitch = 0,
		wantYaw = 0,
		wantPitch = 0,
		aimed = nil,
		aimYaw = 0,
		aimPitch = 0,
		huntable = false,
		saidAt = -math.huge,
	}
end

local function release(b: Brain, squad: Squad)
	if b.goal ~= 0 and squad.claimed[b.goal] == b.id then
		squad.claimed[b.goal] = nil
	end
	b.goal = 0
end

-- The service put this bot somewhere (a spawn point): everything it was doing is forgotten.
function BotBrain.place(b: Brain, squad: Squad, x: number, y: number, z: number, yaw: number, state: State, now: number)
	local nav = b.nav
	release(b, squad)
	b.placed = true
	b.x, b.y, b.z, b.yaw, b.pitch = x, y, z, yaw, 0
	b.crouch, b.wantCrouch, b.sprint, b.speed = 0, false, false, 0
	b.wasOut = false
	b.mode = "wait"
	b.path, b.leg, b.halt = nil, 1, false
	b.peekX, b.peekZ, b.peekBack = nil, nil, false
	-- the node to walk to first: its spawn point's, else the nearest it may stand on
	local entry = 0
	local points = nav.arena.spawns[b.team]
	if points ~= nil then
		for index, sp in points do
			if math.abs(sp.x - x) < 0.6 and math.abs(sp.z - z) < 0.6 and math.abs(sp.y - y) < 1 then
				entry = nav.entry[b.team][index] or 0
				break
			end
		end
	end
	b.at = if entry ~= 0 then entry else BotNav.nearest(nav, x, y, z, b.team)
	-- a storey of its own for this life: one the team has fewest on
	local floors = nav.arena.floors
	local least, chosen = math.huge, 0
	local first = b.rng.int(0, floors - 1)
	for k = 0, floors - 1 do
		local f = (first + k) % floors
		local mates = 0
		for id, storey in squad.home do
			if id ~= b.id and storey == f and squad.side[id] == b.team then
				mates += 1
			end
		end
		if mates < least and #nav.goals[f + 1] > 0 then
			least, chosen = mates, f
		end
	end
	squad.home[b.id] = chosen
	squad.side[b.id] = b.team
	-- out of the room a moment after it may go: not everybody at once
	local live = if state.phase == "briefing" then state.liveAt else now
	b.goAt = math.max(now, live) + (if state.phase == "briefing" then b.rng.range(0.1, 1.4) else b.rng.range(0.05, 0.5))
	b.fresh = true
	b.outbound = false
	b.movedAt, b.movedX, b.movedZ = math.max(now, live), x, z
	table.clear(b.con)
	table.clear(b.whizz)
	b.target = nil
	b.alertAt = nil
	b.alarm = -math.huge
	b.lostAt = -math.huge
	b.contactAt = -math.huge
	b.lookUntil = -math.huge
	b.scanAt = now
	b.scanYaw, b.scanPitch = yaw, 0
	b.wantYaw, b.wantPitch = yaw, 0
	b.aimed = nil
	b.huntable = false
	b.burst = 1
	b.pauseUntil = now
	b.nextSight = now + (b.id % 6) / (6 * b.profile.sightHz)
	b.nextThink = now + (b.id % 6) * THINK / 6
end

local function reaction(b: Brain): number
	local p = b.profile
	local quick = math.clamp(b.skill + b.rng.range(-0.3, 0.3), 0, 1)
	return p.reactMax - (p.reactMax - p.reactMin) * quick
end

-- A noise from (x, y, z): known after the reaction time.
function BotBrain.alert(b: Brain, x: number, y: number, z: number, now: number)
	if b.alertAt ~= nil then
		return -- one thing at a time: the first noise is still sinking in
	end
	b.alertAt = now + reaction(b)
	b.alertX, b.alertY, b.alertZ = x, y, z
end

local function say(b: Brain, squad: Squad, now: number, out: { Command }, line: string, n: number?)
	if now - b.saidAt < SAY_EVERY or now - squad.saidAt[b.team] < TEAM_SAY_EVERY then
		return
	end
	b.saidAt = now
	squad.saidAt[b.team] = now
	table.insert(out, { id = b.id, kind = "say", line = line, n = n })
end

BotBrain.say = say

local function lookAt(b: Brain, x: number, y: number, z: number, now: number, secs: number)
	b.lookUntil = now + secs
	b.lookX, b.lookY, b.lookZ = x, y, z
end

-- One sight check: one opponent inside the cone, one sweep.
local function see(b: Brain, squad: Squad, state: State, poses: { [number]: Pose }, now: number)
	local p = b.profile
	b.nextSight = now + 1 / p.sightHz
	b.sightTurn += 1
	local nav = b.nav
	local lx, ly, lz = Body.look(b.yaw, b.pitch)
	local ex, ey, ez = b.x, b.y + Body.eye(b.crouch), b.z
	local cosHalf = math.cos(p.sightHalf)
	local pick: number? = nil
	local pickScore = -math.huge
	local px, py, pz = 0, 0, 0
	for eid, slot in state.slots do
		if not slot.on or slot.out or slot.team == b.team then
			continue
		end
		local pose = poses[eid]
		if pose == nil then
			continue
		end
		local tx, ty, tz = pose.x, pose.y + chestOf(pose.crouch), pose.z
		local dx, dy, dz = tx - ex, ty - ey, tz - ez
		local d = math.sqrt(dx * dx + dy * dy + dz * dz)
		if d > SIGHT or d < 1e-3 or dx * lx + dy * ly + dz * lz < cosHalf * d then
			continue
		end
		if BotNav.roomOf(nav, pose.x, pose.y, pose.z) ~= 0 then
			continue -- nobody looks into a spawn room
		end
		local c = b.con[eid]
		local age = if c ~= nil then now - c.checked else 10
		local score = age * (1 + 40 / (d + 10))
		if eid == b.target then
			-- the target has two checks of every three
			score = if b.sightTurn % 3 ~= 0 then math.huge else score * 0.5
		end
		if score > pickScore then
			pick, pickScore, px, py, pz = eid, score, tx, ty, tz
		end
	end
	if pick == nil then
		return
	end
	if squad.sightLeft <= 0 then
		b.nextSight = now -- this tick has done its share: first in line at the next
		return
	end
	squad.sightLeft -= 1
	squad.sweeps += 1
	local c = b.con[pick]
	if c == nil then
		c = {
			seen = -math.huge,
			first = -math.huge,
			react = 0,
			checked = now,
			x = 0,
			y = 0,
			z = 0,
			vx = 0,
			vz = 0,
			crouch = 0,
		}
		b.con[pick] = c
	end
	c.checked = now
	if nav.arena.sweep(ex, ey, ez, px, py, pz) ~= nil then
		return
	end
	if now - c.seen > LAPSE then
		-- a new sighting: it sinks in after the reaction time (sooner if the bot was already alarmed
		-- or has only just lost sight of this one)
		c.first = now
		c.react = if now - b.alarm < 2.5 or now - c.seen < 3 then p.reactMin else reaction(b)
	end
	c.seen = now
	local pose = poses[pick]
	c.x, c.y, c.z, c.crouch = pose.x, pose.y, pose.z, pose.crouch
	local track = squad.track[pick]
	c.vx, c.vz = if track ~= nil then track.vx else 0, if track ~= nil then track.vz else 0
	b.contactAt = now
	local floor = math.clamp(math.floor(pose.y / nav.arena.floorHeight + 0.5), 0, nav.arena.floors - 1)
	squad.heat[b.team][floor + 1] = now
	local spot = squad.spot[b.team]
	spot.x, spot.y, spot.z, spot.at = pose.x, pose.y, pose.z, now
end

-- The error and the lead for the next ball at the present target: how many sigmas off, in yaw and
-- in pitch (each ball keeps some of the last one's), and the lead factor.
local function drawError(b: Brain)
	local p = b.profile
	local keep = if b.balls == 0 then 0 else p.keep
	local fresh = math.sqrt(1 - keep * keep)
	b.errYaw = b.errYaw * keep + gauss(b.rng) * fresh
	b.errPitch = b.errPitch * keep + gauss(b.rng) * fresh
	b.lead = 1 + gauss(b.rng) * p.leadSd * (1.5 - b.skill)
end

-- How wide the error is just now (one sigma of yaw, radians): by skill, range, the target's speed,
-- the bot's own, and which ball this is at this target.
local function spread(b: Brain, range: number, targetSpeed: number): number
	local p = b.profile
	local sigma = p.errHi + (p.errLo - p.errHi) * b.skill
	sigma *= 1 + range / p.errFar
	sigma *= 1 + p.errSpeed * targetSpeed / Body.WALK
	sigma *= 1 + p.errMove * b.speed / Body.WALK
	if b.balls == 0 then
		sigma *= p.first
	elseif b.balls == 1 then
		sigma *= p.second
	end
	return sigma
end

local function newBurst(b: Brain)
	local p = b.profile
	local most = math.max(1, p.burstMax)
	b.burst = 1 + math.floor(b.rng.next() * most * (0.6 + 0.4 * b.skill) + 0.2)
	b.burst = math.clamp(b.burst, 1, most)
end

-- A route to `to` from where the bot is; false when there is none.
local function routeTo(b: Brain, squad: Squad, to: number): boolean
	local path = b.path
	local from, alt = b.at, nil :: number?
	if path ~= nil and path[b.leg] ~= nil and b.peekX == nil then
		-- between two nodes: either end will do to set out from
		from, alt = path[b.leg], b.at
	end
	if squad.routeLeft <= 0 then
		return false -- one search a tick: this one waits its turn
	end
	squad.routeLeft -= 1
	squad.routes += 1
	local found = BotNav.route(b.nav, from, alt, 0, to, b.team, b.taste)
	if found == nil then
		return false
	end
	b.path, b.leg = found, 1
	if b.peekX ~= nil then
		b.peekBack = true -- back to the node first
	end
	return true
end

local function claim(b: Brain, squad: Squad, node: number)
	release(b, squad)
	b.goal = node
	squad.claimed[node] = b.id
end

-- Where to go and stand next. A storey first (this one or a neighbour mostly; where opponents were
-- last seen; fewer if team-mates are already there), then the best of a handful of its nodes.
-- The person this bot keeps company, where they are now; nil when it has nobody, they are out, or it
-- has gone off on its own for a while.
local function buddyOf(b: Brain, squad: Squad, state: State): Track?
	local rng = b.rng
	local had = squad.escort[b.id]
	if had ~= nil then
		local slot = state.slots[had]
		if slot == nil or not slot.on or slot.team ~= b.team or squad.people[had] == nil then
			squad.escort[b.id] = nil -- they left, changed sides, or a bot has the seat now
		elseif slot.out then
			return nil -- they are out: it plays on by itself until they are back
		elseif rng.next() < 0.85 then
			return squad.track[had]
		else
			squad.escort[b.id] = nil
			return nil
		end
	end
	-- the nearest person of its team who has fewer than ESCORTS bots with them
	local best: number? = nil
	local bestD = math.huge
	for pid, team in squad.people do
		local slot = state.slots[pid]
		local t = squad.track[pid]
		if team ~= b.team or t == nil or slot == nil or slot.out then
			continue
		end
		local with = 0
		for _, who in squad.escort do
			if who == pid then
				with += 1
			end
		end
		local d = (t.x - b.x) ^ 2 + (t.z - b.z) ^ 2 + ((t.y - b.y) * 3) ^ 2
		if with < ESCORTS and d < bestD then
			best, bestD = pid, d
		end
	end
	if best ~= nil and rng.next() < 0.6 then
		squad.escort[b.id] = best
		return squad.track[best]
	end
	return nil
end

-- A post beside the person it keeps company: on their storey, a short run from them, cover if there is
-- some; 0 when there is none to be had.
local function postBeside(b: Brain, squad: Squad, buddy: Track): number
	local nav = b.nav
	local arena = nav.arena
	local rng = b.rng
	local floor = math.clamp(math.floor(buddy.y / arena.floorHeight + 0.5), 0, arena.floors - 1)
	local keepOff = nav.keepOff[b.team]
	local best, bestScore = 0, -math.huge
	for _, id in nav.goals[floor + 1] do
		local node = nav.nodes[id]
		local d = math.sqrt((node.x - buddy.x) ^ 2 + (node.z - buddy.z) ^ 2)
		if d < ESCORT_NEAR or d > ESCORT_FAR or keepOff[id] or id == b.at then
			continue
		end
		local holder = squad.claimed[id]
		if holder ~= nil and holder ~= b.id then
			continue
		end
		local score = rng.next() * 1.5 - math.abs(d - 15) / 10
		local cover = nav.coverAt[id]
		if cover ~= nil then
			score += if cover.low then 1.2 else 0.9
		end
		if score > bestScore then
			best, bestScore = id, score
		end
	end
	return best
end

local function pickGoal(b: Brain, squad: Squad, state: State, now: number): number
	local nav = b.nav
	local arena = nav.arena
	local rng = b.rng
	local buddy = buddyOf(b, squad, state)
	if buddy ~= nil then
		local post = postBeside(b, squad, buddy)
		if post ~= 0 then
			return post
		end
	end
	local here = math.clamp(math.floor(b.y / arena.floorHeight + 0.5), 0, arena.floors - 1)
	local heat = squad.heat[b.team]
	local total = 0
	local weights: { number } = table.create(arena.floors, 0)
	local home = squad.home[b.id] or here
	for f = 0, arena.floors - 1 do
		local w = 0.3
		local away = math.abs(f - here)
		if away == 0 then
			w += 0.7
		elseif away == 1 then
			w += 0.6
		elseif away == 2 then
			w += 0.25
		end
		if f == home then
			w += 1.6
		end
		local seen = now - heat[f + 1]
		if seen < 15 then
			w += 1 - seen / 15
		end
		-- fewer where the team already is
		local mates = 0
		for id, storey in squad.home do
			if id ~= b.id and storey == f and squad.side[id] == b.team then
				mates += 1
			end
		end
		w /= 1 + 0.5 * mates
		if #nav.goals[f + 1] == 0 then
			w = 0
		end
		weights[f + 1] = w
		total += w
	end
	local roll = rng.next() * total
	local floor = here
	for f = 0, arena.floors - 1 do
		roll -= weights[f + 1]
		if roll <= 0 then
			floor = f
			break
		end
	end
	if b.fresh and weights[home + 1] > 0 and rng.next() < 0.8 then
		floor = home -- out of the spawn room: to its own storey
	end
	local list = nav.goals[floor + 1]
	if #list == 0 then
		return 0
	end
	local keepOff = nav.keepOff[b.team]
	local spot = squad.spot[b.team]
	local fresh = now - spot.at < 12
	local best, bestScore = 0, -math.huge
	for _ = 1, 9 do
		local id = list[rng.int(1, #list)]
		local holder = squad.claimed[id]
		if keepOff[id] or id == b.at or (holder ~= nil and holder ~= b.id) then
			continue
		end
		local node = nav.nodes[id]
		local flat = math.sqrt((node.x - b.x) ^ 2 + (node.z - b.z) ^ 2)
		local score = rng.next() * 1.5
		score -= math.abs(flat - 38) / 30
		local cover = nav.coverAt[id]
		if cover ~= nil then
			score += if cover.low then 1.6 else 1.2
		end
		if fresh and math.abs(node.y - spot.y) < arena.floorHeight * 0.5 then
			-- towards the fight, but not on top of it
			local d = math.sqrt((node.x - spot.x) ^ 2 + (node.z - spot.z) ^ 2)
			score -= math.abs(d - 30) / 25
		end
		if score > bestScore then
			best, bestScore = id, score
		end
	end
	return best
end

local function setOut(b: Brain, squad: Squad, to: number): boolean
	if to == 0 or not routeTo(b, squad, to) then
		return false
	end
	claim(b, squad, to)
	b.mode = "travel"
	b.halt = false
	b.wantCrouch = false
	return true
end

-- A cover spot near enough to run to, sheltered from (tx, tz); 0 when there is none.
local function coverFrom(b: Brain, squad: Squad, tx: number, tz: number, reach: number): number
	local nav = b.nav
	local keepOff = nav.keepOff[b.team]
	local best, bestD = 0, reach
	for id, cover in nav.coverAt do
		local node = nav.nodes[id]
		if math.abs(node.y - b.y) > 1 or keepOff[id] or node.team ~= 0 or nav.door[id] ~= 0 then
			continue
		end
		local holder = squad.claimed[id]
		if holder ~= nil and holder ~= b.id then
			continue
		end
		local d = math.sqrt((node.x - b.x) ^ 2 + (node.z - b.z) ^ 2)
		if d >= bestD then
			continue
		end
		-- sheltered from the threat: the spot's sheltered side faces it
		local ux, uz = tx - node.x, tz - node.z
		local len = math.sqrt(ux * ux + uz * uz)
		if len > 1e-3 and (ux * cover.nx + uz * cover.nz) / len > 0.6 then
			best, bestD = id, d
		end
	end
	return best
end

-- Shot at where it stands: a step to a neighbouring node, across the line of fire if it can.
local function sidestep(b: Brain, squad: Squad, now: number, tx: number, tz: number): boolean
	local nav = b.nav
	local list = nav.adjacent[b.at]
	local ux, uz = tx - b.x, tz - b.z
	local len = math.sqrt(ux * ux + uz * uz)
	if len < 1e-3 then
		return false
	end
	ux, uz = ux / len, uz / len
	local best, bestScore = 0, 0.15
	for k = 1, #list, 3 do
		local id = list[k]
		local node = nav.nodes[id]
		local holder = squad.claimed[id]
		if
			node.team ~= 0
			or nav.door[id] ~= 0
			or nav.keepOff[b.team][id]
			or nav.stair[list[k + 1]]
			or list[k + 2] > 26
			or (holder ~= nil and holder ~= b.id)
		then
			continue
		end
		local vx, vz = node.x - b.x, node.z - b.z
		local vl = math.sqrt(vx * vx + vz * vz)
		if vl < 1 then
			continue
		end
		local across = math.abs(vx * uz - vz * ux) / vl
		local score = across + b.rng.next() * 0.3 + (if nav.coverAt[id] ~= nil then 0.3 else 0)
		if score > bestScore then
			best, bestScore = id, score
		end
	end
	if best == 0 then
		return false
	end
	b.shiftAt = now
	return setOut(b, squad, best)
end

-- Ten times a second: the target, the fight, the reload, the walk.
local function think(b: Brain, squad: Squad, state: State, poses: { [number]: Pose }, now: number, out: { Command })
	local nav = b.nav
	local rng = b.rng
	local slot = state.slots[b.id]
	b.nextThink = now + THINK
	-- the target: the nearest opponent in sight whose sighting has sunk in
	local best: number? = nil
	local bestScore = math.huge
	for eid, c in b.con do
		if now - c.seen > VIS or now - c.first < c.react then
			continue
		end
		local other = state.slots[eid]
		local pose = poses[eid]
		if other == nil or pose == nil or not other.on or other.out or other.team == b.team then
			continue
		end
		local d = math.sqrt((c.x - b.x) ^ 2 + (c.y - b.y) ^ 2 + (c.z - b.z) ^ 2)
		local score = d * (if eid == b.target then 0.7 else 1)
		if score < bestScore then
			best, bestScore = eid, score
		end
	end
	local had = b.target
	if best ~= had then
		if had ~= nil then
			local c = b.con[had]
			local other = state.slots[had]
			if best == nil and c ~= nil and other ~= nil and other.on and not other.out then
				-- lost sight of it: look at where it went, and perhaps go and see
				b.lostAt = now
				b.huntable = true
				b.lostX, b.lostY, b.lostZ = c.x, c.y, c.z
				lookAt(b, c.x, c.y + CHEST, c.z, now, rng.range(1.0, 1.8))
			end
		end
		b.target = best
		b.balls = 0
		if best ~= nil then
			b.errYaw, b.errPitch = 0, 0
			drawError(b)
			newBurst(b)
			b.pauseUntil = math.max(b.pauseUntil, now)
			b.sprint = false
			local pose = b.con[best] -- (what it saw of it)
			if had == nil then
				b.fightAt = now
				local floor = math.clamp(math.floor(pose.y / nav.arena.floorHeight + 0.5), 0, nav.arena.floors - 1)
				-- somebody is shooting, and a team-mate is beside this bot: it says it is with them
				local beside = false
				if now - (squad.firedAt[best] or -math.huge) < 2 then
					for mid, mate in state.slots do
						local mp = poses[mid]
						if
							mid ~= b.id
							and mp ~= nil
							and mate.on
							and not mate.out
							and mate.team == b.team
							and math.abs(mp.y - b.y) < 5
							and (mp.x - b.x) ^ 2 + (mp.z - b.z) ^ 2 < 900
						then
							beside = true
							break
						end
					end
				end
				if beside then
					say(b, squad, now, out, "cover")
				elseif floor ~= squad.calledFloor[b.team] or now - squad.calledAt[b.team] > 30 then
					local said = b.saidAt
					say(b, squad, now, out, "floor", floor + 1)
					if b.saidAt ~= said then
						squad.calledFloor[b.team], squad.calledAt[b.team] = floor, now
					end
				end
				-- how to fight from here
				local mag = slot.mag
				local weak = mag.reloadDoneAt ~= nil or mag.rounds <= 1 or now - b.alarm < 1.5
				local onCover = b.mode == "hold" and nav.coverAt[b.at] ~= nil
				b.stance = "stand"
				local restless = now < b.pushUntil or BotNav.roomOf(nav, b.x, b.y, b.z) ~= 0
				local passing = b.outbound and not weak and rng.next() < 0.7
				if b.mode ~= "hold" and (restless or passing) then
					-- it has stood about long enough, or it is still in its spawn room (nobody fights
					-- from there), or it is on its way to its own storey and does not stop for
					-- everybody: it fights on the move
					b.stance = "push"
				elseif not onCover then
					local roll = rng.next()
					if weak or roll < 0.25 then
						local spot = coverFrom(b, squad, pose.x, pose.z, 20)
						if spot ~= 0 and setOut(b, squad, spot) then
							b.stance = "cover"
						end
					elseif roll < 0.5 and b.mode == "travel" then
						b.stance = "push"
					end
				end
				b.halt = b.stance == "stand" and b.mode == "travel"
			end
		end
	end
	local target = b.target
	local mag = slot.mag
	local reloading = mag.reloadDoneAt ~= nil and now < (mag.reloadDoneAt :: number)
	local cover = if b.mode == "hold" then nav.coverAt[b.at] else nil
	if target ~= nil then
		local pose = b.con[target] or b -- (what it saw of it)
		b.sprint = false
		-- shot at while standing in the open: move
		if b.alarm > b.shiftAt and b.alarm > b.fightAt and cover == nil and (b.halt or b.mode == "hold") then
			b.shiftAt = now
			if b.peekX == nil then
				local spot = coverFrom(b, squad, pose.x, pose.z, 16)
				if spot ~= 0 and spot ~= b.at and setOut(b, squad, spot) then
					b.stance = "cover"
				elseif b.mode == "hold" or b.path == nil then
					sidestep(b, squad, now, pose.x, pose.z)
				else
					b.stance = "push" -- on along its way rather than stand there
					b.halt = false
				end
			end
		end
		if cover ~= nil then
			if cover.low then
				-- up to shoot, down to reload and between bursts when shot at
				b.wantCrouch = reloading or (now < b.pauseUntil and now - b.alarm < 2)
			elseif b.peekX ~= nil and reloading then
				b.peekBack = true
			end
		elseif reloading and b.mode == "hold" and b.peekX == nil and now - b.shiftAt > 2 then
			-- empty in the open: to cover, or at least not where it was
			local spot = coverFrom(b, squad, pose.x, pose.z, 24)
			if spot == 0 or spot == b.at or not setOut(b, squad, spot) then
				sidestep(b, squad, now, pose.x, pose.z)
			end
			b.shiftAt = now
		end
		if reloading then
			say(b, squad, now, out, "reloading")
		end
		-- a fight from one spot does not go on for ever
		if now - b.fightAt > 8 and (b.mode == "hold" or b.halt) and b.peekX == nil then
			b.fightAt = now
			b.stance = "push"
			if not sidestep(b, squad, now, pose.x, pose.z) then
				setOut(b, squad, pickGoal(b, squad, state, now))
			end
		end
	else
		b.halt = false
		-- reload when it is quiet, or when nearly empty and nobody is in sight
		if not reloading and mag.rounds < mag.capacity then
			if mag.rounds <= 2 or now - b.contactAt > QUIET then
				table.insert(out, { id = b.id, kind = "reload" })
				if now - b.contactAt < QUIET then
					say(b, squad, now, out, "reloading")
				end
			end
		end
		if b.mode == "wait" then
			if now >= b.goAt and state.phase == "live" then
				if setOut(b, squad, pickGoal(b, squad, state, now)) then
					b.fresh = false
					b.outbound = true
				else
					b.goAt = now + 0.1
				end
			end
		elseif b.mode == "travel" then
			-- sprint when nothing has been seen or heard for a while and there is some way to go
			local path = b.path
			local quiet = now - b.contactAt > QUIET and now - b.alarm > QUIET and now - b.lostAt > QUIET
			b.sprint = quiet and path ~= nil and #path - b.leg >= 1 and not b.wantCrouch
		elseif b.mode == "hold" then
			b.sprint = false
			local hunted = false
			if b.huntable and now - b.lostAt < 0.5 and rng.next() < 0.55 then
				-- just lost somebody: go and see, if it is near and not where the bot may not stand
				local d = math.sqrt((b.lostX - b.x) ^ 2 + (b.lostZ - b.z) ^ 2)
				if d < 60 then
					local node = BotNav.nearest(nav, b.lostX, b.lostY, b.lostZ, b.team)
					if not nav.keepOff[b.team][node] and nav.nodes[node].team == 0 and node ~= b.at then
						hunted = setOut(b, squad, node)
					end
				end
			end
			b.huntable = false -- decided, once
			-- the person it keeps company has moved on: so does it
			local pal = squad.escort[b.id]
			local palAt = if pal ~= nil then squad.track[pal] else nil
			local palSlot = if pal ~= nil then state.slots[pal] else nil
			if
				palAt ~= nil
				and palSlot ~= nil
				and palSlot.on
				and not palSlot.out
				and (
					math.abs(palAt.y - b.y) > nav.arena.floorHeight * 0.5
					or (palAt.x - b.x) ^ 2 + (palAt.z - b.z) ^ 2 > ESCORT_LEFT * ESCORT_LEFT
				)
			then
				b.holdUntil = math.min(b.holdUntil, now + 0.4)
			end
			if not hunted and now >= b.holdUntil and b.peekX == nil then
				if not setOut(b, squad, pickGoal(b, squad, state, now)) then
					b.holdUntil = now + 0.5
				end
			elseif not hunted and cover ~= nil then
				if cover.low then
					-- bob: down out of sight, up to look
					if now >= b.bobAt then
						b.wantCrouch = not b.wantCrouch
						b.bobAt = now + (if b.wantCrouch then rng.range(0.8, 1.8) else rng.range(2.2, 4.5))
					end
				else
					local peeks = nav.peeks[b.at]
					if peeks ~= nil and #peeks > 0 and now >= b.peekAt then
						if b.peekX == nil then
							local peek = peeks[rng.int(1, #peeks)]
							b.peekX, b.peekZ, b.peekBack = peek.x, peek.z, false
							b.peekAt = now + rng.range(1.6, 3.2)
						else
							b.peekBack = true
							b.peekAt = now + rng.range(1.5, 3.5)
						end
					end
				end
			end
		end
	end
	-- the stuck watch: a bot in play that has not been anywhere else for a long time goes somewhere
	if (b.x - b.movedX) ^ 2 + (b.z - b.movedZ) ^ 2 > 9 then
		b.movedAt, b.movedX, b.movedZ = now, b.x, b.z
	elseif now - b.movedAt > 10 and state.phase == "live" then
		-- wherever it was going or whoever it was fighting: somewhere else, and on its feet
		if now >= b.watchAt then
			b.watchAt = now + 1
			b.peekBack = b.peekX ~= nil
			b.pushUntil = now + 8
			b.stance = "push"
			setOut(b, squad, pickGoal(b, squad, state, now))
		end
	end
end

-- Walk: to the peek point, back from it, or along the path.
local function move(b: Brain, state: State, now: number, dt: number)
	local nav = b.nav
	local tx: number? = nil
	local tz = 0
	local peeking = false
	local path = b.path
	if b.peekX ~= nil then
		peeking = true
		if b.peekBack then
			local node = nav.nodes[b.at]
			tx, tz = node.x, node.z
		else
			tx, tz = b.peekX, b.peekZ :: number
		end
	elseif path ~= nil and not b.halt and b.mode == "travel" then
		local node = nav.nodes[path[b.leg]]
		if node ~= nil then
			tx, tz = node.x, node.z
		end
	end
	b.speed = 0
	if tx == nil then
		b.sprint = false
		return
	end
	local sprint = b.sprint and not peeking and b.crouch <= 0
	b.sprint = sprint
	local speed = Body.speed(b.crouch, sprint, state.feel)
	local dx, dz = tx - b.x, tz - b.z
	local d = math.sqrt(dx * dx + dz * dz)
	local step = speed * dt
	if d <= step then
		b.x, b.z = tx, tz
		b.speed = if dt > 0 then d / dt else 0
		if peeking then
			if b.peekBack then
				b.peekX, b.peekZ, b.peekBack = nil, nil, false
			end
		elseif path ~= nil then
			b.at = path[b.leg]
			b.leg += 1
			if path[b.leg] == nil then
				-- there
				b.path = nil
				b.outbound = false
				b.mode = "hold"
				local cover = nav.coverAt[b.at]
				b.holdUntil = now + (if cover ~= nil then b.rng.range(3, 7) else b.rng.range(1, 2.6))
				b.bobAt = now + b.rng.range(0.3, 1.5)
				b.peekAt = now + b.rng.range(0.8, 2)
				b.scanAt = now
				b.sprint = false
			end
		end
	else
		b.x += dx / d * step
		b.z += dz / d * step
		b.speed = speed
	end
	local g = nav.arena.ground(b.x, b.y + 0.6, b.z)
	if g ~= nil then
		b.y = g
	end
	if b.sprint then
		b.sprintAt = now
	end
end

-- Where the look wants to be when there is nobody to aim at.
local function idleLook(b: Brain, squad: Squad, now: number)
	local nav = b.nav
	if now < b.lookUntil then
		local dx, dy, dz = b.lookX - b.x, b.lookY - (b.y + Body.eye(b.crouch)), b.lookZ - b.z
		if dx * dx + dz * dz > 0.25 then
			b.wantYaw, b.wantPitch = Body.yawPitch(dx, dy, dz)
			b.wantPitch = math.clamp(b.wantPitch, -1.1, 1.1)
		end
		return
	end
	local path = b.path
	if b.mode == "travel" and path ~= nil and not b.halt then
		-- along the way; near a corner, already round it
		local node = nav.nodes[path[b.leg]]
		local nextNode = nav.nodes[path[b.leg + 1]]
		if node ~= nil then
			local dx, dy, dz = node.x - b.x, node.y - b.y, node.z - b.z
			local d = math.sqrt(dx * dx + dz * dz)
			if nextNode ~= nil and d < 5 then
				local k = 1 - d / 5
				dx += (nextNode.x - node.x) * k
				dy += (nextNode.y - node.y) * k
				dz += (nextNode.z - node.z) * k
			end
			if dx * dx + dz * dz > 0.04 then
				b.wantYaw, b.wantPitch = Body.yawPitch(dx, dy, dz)
				b.wantPitch = math.clamp(b.wantPitch * 0.8, -0.6, 0.6)
			end
		end
		return
	end
	-- at a post: look about. Towards the side the cover faces, where the team last saw somebody,
	-- down the links from here; over the atrium, up and down as well
	if now >= b.scanAt then
		local rng = b.rng
		b.scanAt = now + rng.range(1.1, 2.6)
		local node = nav.nodes[b.at]
		local cover = nav.coverAt[b.at]
		local spot = squad.spot[b.team]
		local roll = rng.next()
		local yaw = b.yaw + rng.range(-1.6, 1.6)
		local pitch = 0
		if roll < 0.35 and now - spot.at < 15 then
			local dx, dy, dz = spot.x - b.x, spot.y + CHEST - (b.y + Body.eye(b.crouch)), spot.z - b.z
			if dx * dx + dz * dz > 1 then
				yaw, pitch = Body.yawPitch(dx, dy, dz)
				yaw += rng.range(-0.3, 0.3)
			end
		elseif roll < 0.7 and cover ~= nil then
			-- over low cover; past the edges of high cover, not at it
			local off = if cover.low
				then rng.range(-0.7, 0.7)
				else rng.range(0.6, 1.3) * (if rng.next() < 0.5 then -1 else 1)
			yaw = math.atan2(-cover.nx, -cover.nz) + off
		elseif node ~= nil then
			local list = nav.adjacent[b.at]
			if #list >= 3 then
				local k = (rng.int(1, #list // 3) - 1) * 3 + 1
				local to = nav.nodes[list[k]]
				yaw = math.atan2(-(to.x - node.x), -(to.z - node.z)) + rng.range(-0.25, 0.25)
			end
		end
		local arena = nav.arena
		if math.abs(b.x) < arena.atrium + 12 and math.abs(b.z) < arena.atrium + 12 and rng.next() < 0.6 then
			-- beside the atrium: across it, at the other storeys
			yaw = math.atan2(b.x, b.z) + rng.range(-0.6, 0.6)
			pitch = rng.range(-0.7, 0.45)
		end
		b.scanYaw, b.scanPitch = wrap(yaw), math.clamp(pitch, -1.1, 1.1)
	end
	b.wantYaw, b.wantPitch = b.scanYaw, b.scanPitch
end

-- One server tick of one bot. Appends its commands to `out`; writes its pose to `poses`.
function BotBrain.step(
	b: Brain,
	squad: Squad,
	state: State,
	poses: { [number]: Pose },
	now: number,
	dt: number,
	out: { Command }
)
	local slot: Slot? = state.slots[b.id]
	if slot == nil or not slot.on or not b.placed then
		return
	end
	local p = b.profile
	local pose = poses[b.id]
	if pose == nil then
		pose = { x = b.x, y = b.y, z = b.z, yaw = b.yaw, pitch = b.pitch, crouch = b.crouch, bits = 0 }
		poses[b.id] = pose
	end
	if slot.out then
		-- tagged: it stands where it stood until the service puts it somewhere
		if not b.wasOut then
			b.wasOut = true
			b.target = nil
			b.sprint = false
			b.speed = 0
			release(b, squad)
			say(b, squad, now, out, "out")
		end
		return
	end
	if state.phase ~= "live" then
		-- the briefing and the end card: it stands
		b.speed = 0
		pose.x, pose.y, pose.z, pose.yaw, pose.pitch, pose.crouch, pose.bits =
			b.x, b.y, b.z, b.yaw, b.pitch, b.crouch, 0
		return
	end
	-- the senses
	local whizz = b.whizz
	for i = #whizz, 1, -1 do
		local w = whizz[i]
		if w.at <= now then
			BotBrain.alert(b, w.x, w.y, w.z, now)
			table.remove(whizz, i)
		end
	end
	local alertAt = b.alertAt
	if alertAt ~= nil and now >= alertAt then
		b.alertAt = nil
		b.alarm = now
		if b.target == nil then
			lookAt(b, b.alertX, b.alertY, b.alertZ, now, b.rng.range(1.2, 2))
			local cover = if b.mode == "hold" then b.nav.coverAt[b.at] else nil
			if cover ~= nil and cover.low then
				b.wantCrouch = true -- duck
				b.bobAt = now + b.rng.range(0.6, 1.3)
			elseif cover ~= nil then
				b.peekBack = b.peekX ~= nil
				b.peekAt = now + b.rng.range(0.8, 1.6)
			elseif b.mode == "hold" and now - b.shiftAt > 1.5 then
				local spot = coverFrom(b, squad, b.alertX, b.alertZ, 18)
				if spot == 0 or spot == b.at or not setOut(b, squad, spot) then
					sidestep(b, squad, now, b.alertX, b.alertZ)
				end
				b.shiftAt = now
			end
		end
	end
	if now >= b.nextSight then
		see(b, squad, state, poses, now)
	end
	if now >= b.nextThink then
		think(b, squad, state, poses, now, out)
	end
	move(b, state, now, dt)
	b.crouch = Body.crouchStep(b.crouch, b.wantCrouch, dt, state.feel)
	-- the look
	local target = b.target
	local tpose = if target ~= nil then poses[target] else nil
	local contact = if target ~= nil then b.con[target] else nil
	local aiming = false
	local range = 0
	local leadYaw, leadPitch = 0, 0
	local ex, ey, ez = b.x, b.y + Body.eye(b.crouch), b.z
	local feel = state.feel
	-- where the target is, as far as this bot knows: where it last SAW it, carried on at the speed it
	-- was going then. It never reads where a body it cannot see has got to.
	local tx, ty, tz = 0, 0, 0
	if target ~= nil and tpose ~= nil and contact ~= nil and now - contact.seen <= VIS then
		aiming = true
		local since = now - contact.seen
		tx, ty, tz = contact.x + contact.vx * since, contact.y, contact.z + contact.vz * since
		local cy = ty + (Body.LOW + Body.top(contact.crouch) - Body.RADIUS) * 0.5 -- the middle of its shape
		local dx, dy, dz = tx - ex, cy - ey, tz - ez
		local d = math.sqrt(dx * dx + dy * dy + dz * dz)
		local flight = d / feel.ballSpeed * b.lead
		local ax, az = tx + contact.vx * flight, tz + contact.vz * flight
		local vx, vy, vz = Ballistics.aim(ex, ey, ez, ax, cy, az, feel.ballSpeed, feel.ballDrop)
		local yaw, pitch = Body.yawPitch(vx, vy, vz)
		local sigma = spread(b, d, math.sqrt(contact.vx * contact.vx + contact.vz * contact.vz))
		b.wantYaw = wrap(yaw + b.errYaw * sigma)
		b.wantPitch = math.clamp(pitch + b.errPitch * sigma * 0.6, -1.4, 1.4)
		-- a moving target turns the aim: the look turns with it as well as towards it
		if b.aimed == target then
			leadYaw, leadPitch = wrap(yaw - b.aimYaw), pitch - b.aimPitch
		end
		b.aimed, b.aimYaw, b.aimPitch = target, yaw, pitch
		range = d
	end
	if not aiming then
		b.aimed = nil
		idleLook(b, squad, now)
	end
	-- turn towards it, no faster than a body turns
	local most = p.turn * dt
	local k = math.min(1, p.gain * dt)
	b.yaw = wrap(b.yaw + math.clamp(wrap(b.wantYaw - b.yaw) * k + leadYaw, -most, most))
	b.pitch = math.clamp(b.pitch + math.clamp((b.wantPitch - b.pitch) * k + leadPitch, -most, most), -1.5, 1.5)
	-- fire? Only along the look as it now is, and only when it has settled on the aim
	if
		aiming
		and target ~= nil
		and tpose ~= nil
		and contact ~= nil
		and now >= b.pauseUntil
		and math.abs(wrap(b.wantYaw - b.yaw)) <= p.settle
		and math.abs(b.wantPitch - b.pitch) <= p.settle
		and now - contact.first >= math.max(contact.react, p.faced)
		and range <= p.range * feel.ballSpeed
		and not b.sprint
		and now - b.sprintAt >= Body.SPRINT_FIRE_DELAY + 0.02
		and BotNav.roomOf(b.nav, b.x, b.y, b.z) == 0
		and BotNav.roomOf(b.nav, tx, ty, tz) == 0
		and (now - (squad.firedAt[target] or -math.huge) < DOOR_TRUCE or not BotNav.atDoor(
			b.nav,
			3 - b.team,
			tx,
			ty,
			tz
		))
		and Rules.canBeHit(state, target, now)
		and Rules.canFire(state, b.id, now)
	then
		local lx, ly, lz = Body.look(b.yaw, b.pitch)
		table.insert(out, {
			id = b.id,
			kind = "fire",
			ox = ex,
			oy = ey,
			oz = ez,
			vx = lx * feel.ballSpeed,
			vy = ly * feel.ballSpeed,
			vz = lz * feel.ballSpeed,
		})
		b.balls += 1
		b.burst -= 1
		if b.burst <= 0 then
			newBurst(b)
			b.pauseUntil = now + b.rng.range(p.pauseMin, p.pauseMax) * (1.3 - 0.6 * b.skill)
		end
		drawError(b)
	end
	-- the pose everybody else is shown
	local bits = 0
	if b.wantCrouch then
		bits += BIT.crouch
	end
	if b.sprint then
		bits += BIT.sprint
	end
	pose.x, pose.y, pose.z, pose.yaw, pose.pitch, pose.crouch, pose.bits = b.x, b.y, b.z, b.yaw, b.pitch, b.crouch, bits
end

return BotBrain
