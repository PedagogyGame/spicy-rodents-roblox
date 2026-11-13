--!strict
-- ServerScriptService.Server.Minigames.Paintball.Bots
-- The bots that fill a paintball match (checklist PB-6, PB-10), as a pure model: no Instances, no
-- remotes. A bot is a seat of the match held by one of the framework's computer players
-- (Contract.BOTS), with a brain here; it has NO body in the world. The service keeps one table of
-- poses for every slot (arena frame), a bot's brain moves its own entry, and every client draws bots
-- and people alike from the snapshot stream (Shared/Minigames/Paintball/Clock).
-- OWNED BY THE MATCH-AND-BOTS LANE. The functions keep the names and signatures the contract gave them.
-- This file is the list of brains and what they share; BotBrain (beside it) is one bot's thinking,
-- BotNav what a bot knows of the building.
--
-- WHAT THE BOTS DO, AND WITH WHAT (Contract.BOT holds the numbers named here):
--   * move kinematically over the arena's navigation graph (arena.nodes, arena.links: "walk" links
--     in a straight line, "stair" links along the ramp, feet on arena.ground) at the body's own
--     speeds (Body.speed with state.feel); a bot OWNS ITS CROUCH: it eases its own pose.crouch with
--     Body.crouchStep(c, want, dt, state.feel) every tick and the service never touches it. They use
--     both stairs of a storey, cross and overlook the atrium, never stop for good (PB-10: "never get
--     stuck"), walk out of their own spawn room after a respawn and do not go back in, and never
--     enter, stand at the door of, or shoot into the other team's (nodes with team ~= 0);
--   * SEE an opponent only along a clear line (one arena.sweep from the bot's eye to the other's
--     chest; when that finds something in the way, the bot's next check of them is to their HEAD: a
--     body that stands behind a rail or low cover shows from the shoulders up, is seen, and is aimed
--     at where it shows; crouched behind it, it is hidden) and only inside
--     BOT.sightHalf of where they are looking; a sight check per bot runs at most BOT.sightHz times a
--     second and the bots' checks are spread over the ticks (no tick does more than its share);

--   * HEAR what the service tells them (`heard`, below): an OPPONENT'S ball that is born, passes or
--     lands within BOT.hear studs of a bot, and a team-mate tagged where the bot could see, make it
--     aware of the direction the ball came from. A bot that is shot at and missed does not stand
--     there: it turns, ducks or moves. (A team-mate's ball going by tells it nothing it needs.)
--   * act on anything seen or heard only after a reaction time between BOT.reactMin and BOT.reactMax;
--   * TURN at no more than BOT.turn (yaw and pitch each), and fire ONLY ALONG THEIR OWN LOOK: a
--     bot's pose yaw and pitch are where its marker points (the aim, lead and drop included), and the
--     service drops a "fire" whose direction is more than BOT.aimSlack from Body.look(pose.yaw,
--     pose.pitch). So a bot must be seen to turn on a player before it can tag them: the puppet is the
--     tell. A ball is never fired at a sighting younger than BOT.faced. Between sight checks a
--     bot aims at where it last SAW its target, carried on at the speed it had: it never follows
--     a body it has no line to;
--   * aim with Ballistics.aim(..., state.feel.ballSpeed, state.feel.ballDrop) at where the target
--     will be, plus error, more of it at a low `skill`, and MOST OF IT ON THE FIRST BALL at a new
--     target: the first ball is the warning splat. A fair player beats the average bot (skill 0.5)
--     about three times in five;
--   * take cover (arena.cover: stand behind high cover, crouch behind low cover and rails), peek, and
--     fall back to reload; and MOVE UP on somebody they can see and cannot reach (further off than
--     their range of ball flight) instead of standing to look at them;

--   * respect the match: they fire only when Rules.canFire(state, id, now) says so, with the same
--     magazine and reload as a person, never while BIT.sprint is set in their pose or within
--     Body.SPRINT_FIRE_DELAY of it, and never from inside a spawn room;
--   * do not spawn-trap: no bot fires at somebody inside their spawn room, nor (BotBrain, THE TRUCES)
--     at somebody on their own doorstep (BotNav.DOORSTEP) who has not fired a ball in the last few
--     seconds, nor at somebody in their first 1.5 s out of their spawn room who has not yet fired,
--     unless they have come within 15 studs of that bot or held their look on it; and no bot
--     chooses to stand within BotNav.KEEP_OFF of the other team's doors.

-- A bot's shot is a command for the service, which checks the look (above), calls Rules.fire(state,
-- id, now) and Projectiles.fire with no rewind: a bot sees the server's present. Every `now` here is
-- the shared clock (Clock): the same time the State is synced to.
-- WHAT THE BOTS SHARE (the Squad): where every body is and how fast it is going (worked out here
-- once a tick from `poses`; a bot takes a target's speed from it only at a sight check); which post
-- each bot has taken, so two do not choose one; the storey each bot has made its own; when each
-- slot last fired; and what each TEAM knows: the storey and the place it last saw an opponent,
-- which is what "They are on three!" says aloud and what draws its bots towards a fight.
-- TEAM-MATES TO A PERSON. A seat that is on and has no brain in this list is a person, as far as the
-- bots can tell (the service never says who is who, and need not). What a person's play shows
-- anybody, their team's bots take in: where a person's ball lands is where their team takes the
-- other side to be, as if a bot had seen somebody there; where one of the team is tagged out
-- likewise, when it knows of nothing newer. And one bot of a person's team (two, of a team with more
-- than four bots) KEEPS THEM COMPANY: it takes its posts within a short run of them, goes after them
-- to another storey at once and across a storey when they stop, and is back beside them after either
-- has been out (BotBrain, COMPANY). Nothing in it reads more of anybody than any team-mate sees.
-- THE CALL-OUTS (Contract.LINES; one a bot every twelve seconds, one a team every eight): "reloading"
-- when it reloads with somebody about (one a team every twenty seconds: somebody always is), "floor"
-- (n = the storey, 1 to 5) when it first sees
-- somebody on a storey its team has not just called, "cover" when it joins a team-mate's fight,
-- "tagged" when its ball tags, "out" when it is tagged.
-- A BOT WITHOUT A POSE DOES NOTHING: a brain made by sync before the service has placed its slot
-- (the "respawn" event comes a step or two after the seat is taken) waits for place().
-- COST (Contract.COST): Bots.step with COST.atBots bots costs under COST.botsMs a tick on average;
-- the lane measures it in its calibration tool and the service reports it (Stats.botsMs).
-- THE CALIBRATION TOOL (tools/games/paintball/bots/) takes a feel as input and prints its results
-- (how often a scripted fair player beats the average bot; stuck, camping and one-stair checks; the
-- facing figure above; the step's cost) at ball speeds 90, 120 and 150, so a faster ball can be
-- judged at the owner's playtest without waiting for a new calibration.
-- Interface: new(arena, opts?) -> Bots; sync(bots, state, who, poses, now); place(bots, id, pose,
--   now); step(bots, state, poses, heard, now, dt) -> { Command }; types Command, Heard, Opts, Bots

local Import = require("../../Import")
local BodyModule: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Body)) =
	Import.shared("Minigames/Paintball/Body")
local ContractModule: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Contract)) =
	Import.shared("Minigames/Paintball/Contract")
local ArenaModule: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Arena)) =
	Import.shared("Minigames/Paintball/Arena")
local BotBrain = require("./BotBrain")
local BotNav = require("./BotNav")

-- (types only: typeof never runs its require; see "HOW TO IMPORT" in Shared/Minigames/Paintball/Contract)
type Arena = typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Arena).T.Arena)
type Pose = typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Contract).T.Pose)
type State = typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Rules).T.State)

-- What a bot asks the service to do this tick.
--   fire    a ball from (ox, oy, oz), the bot's eye point (Body.eyePoint of its pose), with velocity
--           (vx, vy, vz) of length state.feel.ballSpeed along the bot's own look (see above)
--   reload  R
--   say     a call-out: `line` is a key of Contract.LINES, `n` its number if it has one
export type Command = {
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

-- What the service saw since the last tick, for the bots to hear (arena frame). Every ball is here,
-- people's and bots' alike.
--   born    slot `id` fired: (x, y, z) is the origin, (vx, vy, vz) the velocity
--   ended   a ball of slot `id` ended at (x, y, z), on a wall or on a body
--   tag     slot `id` was tagged out by slot `by`; (x, y, z) is where the ball struck
export type Heard = {
	kind: "born" | "ended" | "tag",
	id: number,
	by: number?,
	x: number,
	y: number,
	z: number,
	vx: number?,
	vy: number?,
	vz: number?,
}

export type Opts = {
	seed: number?,
	-- the kind of player every brain of this list is (BotBrain.Profile); nil = a bot. The calibration
	-- tool makes a second list with a profile of its own to stand in for a person.
	profile: BotBrain.Profile?,
}

-- A ball in flight, as the bots heard it born.
type Flight = { at: number, x: number, y: number, z: number, seq: number }

export type Bots = {
	arena: Arena,
	seed: number,
	brains: { [number]: any }, -- by slot id: BotBrain.Brain
	nav: BotNav.Nav,
	profile: BotBrain.Profile,
	squad: BotBrain.Squad,
	flights: { [number]: { Flight } }, -- by shooter: its balls in flight, oldest first
	seq: number,
	state: State?, -- the match the squad's knowledge belongs to
}

local RULES = ContractModule.Rules
local CHEST = ArenaModule.CHEST

local Bots = {}

local function newSquad(arena: Arena): BotBrain.Squad
	local never = -math.huge
	return {
		track = {},
		claimed = {},
		heat = { table.create(arena.floors, never), table.create(arena.floors, never) },
		spot = { { x = 0, y = 0, z = 0, at = never }, { x = 0, y = 0, z = 0, at = never } },
		saidAt = { never, never },
		reloadSaidAt = { never, never },
		calledFloor = { -1, -1 },
		calledAt = { never, never },
		home = {},
		side = {},
		firedAt = {},
		homeAt = {},
		leftAt = {},
		eyeOn = {},
		eyeOnAt = {},
		people = {},
		escort = {},
		sightLeft = 0,
		routeLeft = 0,
		tick = 0,
		sweeps = 0,
		routes = 0,
	}
end

function Bots.new(arena: Arena, opts: Opts?): Bots
	local o: Opts = opts or {}
	return {
		arena = arena,
		seed = o.seed or 1,
		brains = {},
		nav = BotNav.build(arena),
		profile = o.profile or BotBrain.DEFAULT,
		squad = newSquad(arena),
		flights = {},
		seq = 0,
		state = nil,
	}
end

-- A new match: nothing the bots knew of the last one is true of this one.
local function fresh(bots: Bots, state: State)
	if bots.state ~= state then
		bots.state = state
		bots.squad = newSquad(bots.arena)
		table.clear(bots.flights)
		table.clear(bots.brains)
	end
end

-- Make the brains match the match: one for every slot a bot holds, none for a slot a person took or
-- that is off. `who[id]` is that bot's skill (Contract.BOTS: 0..1, 0.5 the average bot); a slot
-- with no entry is not a bot. The service calls this after every seat taken or left and after a
-- change of side. A new brain starts from poses[id]; a brain whose slot changed team forgets its plan.
function Bots.sync(bots: Bots, state: State, who: { [number]: number }, poses: { [number]: Pose }, now: number)
	fresh(bots, state)
	local brains = bots.brains :: { [number]: BotBrain.Brain }
	for id, brain in brains do
		local slot = state.slots[id]
		if who[id] == nil or slot == nil or not slot.on or slot.team ~= brain.team then
			if brain.goal ~= 0 and bots.squad.claimed[brain.goal] == id then
				bots.squad.claimed[brain.goal] = nil
			end
			bots.squad.home[id] = nil
			bots.squad.side[id] = nil
			bots.squad.escort[id] = nil
			brains[id] = nil
		end
	end
	for id, skill in who do
		local slot = state.slots[id]
		if slot == nil or not slot.on or brains[id] ~= nil then
			continue
		end
		local brain = BotBrain.new(bots.nav, id, slot.team, skill, bots.seed, bots.profile)
		brains[id] = brain
		local pose = poses[id]
		if pose ~= nil and BotNav.roomOf(bots.nav, pose.x, pose.y, pose.z) ~= 3 - slot.team then
			-- (a slot that has just changed sides still stands in the room it is leaving: its brain
			-- waits for the placement that is on its way)
			BotBrain.place(brain, bots.squad, pose.x, pose.y, pose.z, pose.yaw, state, now)
		end
	end
end

-- The service put this bot somewhere (the briefing, a respawn, a change of side): forget the old path.
function Bots.place(bots: Bots, id: number, pose: Pose, now: number)
	local brain = (bots.brains :: { [number]: BotBrain.Brain })[id]
	local state = bots.state
	if brain == nil or state == nil then
		return
	end
	BotBrain.place(brain, bots.squad, pose.x, pose.y, pose.z, pose.yaw, state, now)
end

-- Where every body is and how fast it is going over the floor, from the poses as they change. (A
-- person's pose changes at the snapshot rate, a bot's every tick: the speed is taken over the time
-- between changes and smoothed.)
local function follow(
	nav: BotNav.Nav,
	profile: BotBrain.Profile,
	squad: BotBrain.Squad,
	brains: { [number]: BotBrain.Brain },
	state: State,
	poses: { [number]: Pose },
	now: number
)
	local track = squad.track
	local people = squad.people
	local courtesy = profile.courtesy
	local lookOn = math.cos(BotBrain.TRUCE.look)
	for id, slot in state.slots do
		local pose = poses[id]
		-- a seat that is on and is none of these bots is a person, as far as the bots can tell
		if slot.on and pose ~= nil and brains[id] == nil then
			people[id] = slot.team
		else
			people[id] = nil
		end
		if not slot.on or pose == nil then
			track[id] = nil
			squad.homeAt[id] = nil
			squad.leftAt[id] = nil
			squad.eyeOn[id] = nil
			continue
		end
		if BotNav.roomOf(nav, pose.x, pose.y, pose.z) == slot.team then
			squad.homeAt[id] = now -- in its own spawn room
		elseif (squad.leftAt[id] or -math.huge) < slot.spawnAt then
			squad.leftAt[id] = now -- its first step out since it was placed (BotBrain, THE TRUCES)
		end
		if courtesy then
			-- the bot of this list its look rests on, if any (BotBrain, THE TRUCES): what anybody sees of a
			-- marker pointed at them
			local on: number? = nil
			if not slot.out then
				local lx, ly, lz = BodyModule.look(pose.yaw, pose.pitch)
				local ex, ey, ez = BodyModule.eyePoint(pose.x, pose.y, pose.z, pose.crouch)
				local best = lookOn
				for bid, b in brains do
					if b.team == slot.team or not b.placed then
						continue
					end
					local dx, dy, dz = b.x - ex, b.y + CHEST - ey, b.z - ez
					local d = math.sqrt(dx * dx + dy * dy + dz * dz)
					if d > 1e-3 and d < 150 then
						local cos = (dx * lx + dy * ly + dz * lz) / d
						if cos > best then
							on, best = bid, cos
						end
					end
				end
			end
			if on ~= squad.eyeOn[id] then
				squad.eyeOn[id] = on
				squad.eyeOnAt[id] = now
			end
		end
		local t = track[id]
		if t == nil then
			track[id] = { x = pose.x, y = pose.y, z = pose.z, vx = 0, vz = 0, t = now }
			continue
		end
		local dt = now - t.t
		local dx, dz = pose.x - t.x, pose.z - t.z
		if dx ~= 0 or dz ~= 0 then
			if dt > 1e-4 and dx * dx + dz * dz < 36 then
				local k = math.min(1, dt / 0.12)
				t.vx += (dx / dt - t.vx) * k
				t.vz += (dz / dt - t.vz) * k
			else
				t.vx, t.vz = 0, 0 -- it was put somewhere else
			end
			t.x, t.y, t.z, t.t = pose.x, pose.y, pose.z, now
		elseif dt > 0.15 then
			t.vx, t.vz = 0, 0 -- it has stopped
			t.y = pose.y
		end
	end
end

-- A team is told of a place where there is a fight (a person's ball landed there, one of its own was
-- tagged there): the storey is hot, and that is where its bots take the other side to be.
local function told(bots: Bots, team: number, x: number, y: number, z: number, now: number)
	local arena = bots.arena
	local squad = bots.squad
	local floor = math.clamp(math.floor(y / arena.floorHeight + 0.5), 0, arena.floors - 1)
	squad.heat[team][floor + 1] = now
	local spot = squad.spot[team]
	spot.x, spot.y, spot.z, spot.at = x, floor * arena.floorHeight, z, now
end

-- What the service heard, shared out among the brains.
local function hear(
	bots: Bots,
	state: State,
	poses: { [number]: Pose },
	heard: { Heard },
	now: number,
	out: { Command }
)
	local brains = bots.brains :: { [number]: BotBrain.Brain }
	local squad = bots.squad
	local profile = bots.profile
	local reach = profile.hear * profile.hear
	local ttl = RULES.ballTtl
	for _, h in heard do
		local shooter = state.slots[if h.kind == "tag" then h.by or 0 else h.id]
		if h.kind == "born" then
			local vx, vy, vz = h.vx or 0, h.vy or 0, h.vz or 0
			local vv = vx * vx + vy * vy + vz * vz
			bots.seq += 1
			local list = bots.flights[h.id]
			if list == nil then
				list = {}
				bots.flights[h.id] = list
			end
			table.insert(list, { at = now, x = h.x, y = h.y, z = h.z, seq = bots.seq })
			bots.squad.firedAt[h.id] = now
			if shooter == nil or vv < 1 then
				continue
			end
			for id, b in brains do
				if b.team == shooter.team or not b.placed or id == h.id then
					continue
				end
				-- where the ball's line comes nearest this bot's chest, and when
				local cx, cy, cz = b.x - h.x, b.y + BodyModule.STAND_EYE * 0.6 - h.y, b.z - h.z
				local along = math.clamp((cx * vx + cy * vy + cz * vz) / vv, 0, ttl)
				local dx, dy, dz = cx - vx * along, cy - vy * along, cz - vz * along
				if dx * dx + dy * dy + dz * dz <= reach and #b.whizz < 6 then
					table.insert(b.whizz, { at = now + along, x = h.x, y = h.y, z = h.z, by = h.id, seq = bots.seq })
				end
			end
		elseif h.kind == "ended" then
			-- which ball: the shooter's oldest still in flight
			local list = bots.flights[h.id]
			local flight: Flight? = nil
			if list ~= nil then
				while #list > 0 and now - list[1].at > ttl + 0.1 do
					table.remove(list, 1)
				end
				flight = table.remove(list, 1)
			end
			if flight == nil or shooter == nil then
				continue
			end
			if squad.people[h.id] == shooter.team then
				-- a person's ball: their team's bots take it that somebody is where it went ("over
				-- there!"), as they would a sighting of their own
				told(bots, shooter.team, h.x, h.y, h.z, now)
			end
			for id, b in brains do
				if b.team == shooter.team or not b.placed or id == h.id then
					continue
				end
				-- it stopped before it got here: it never went by
				local whizz = b.whizz
				for i = #whizz, 1, -1 do
					if whizz[i].seq == flight.seq and whizz[i].at > now then
						table.remove(whizz, i)
					end
				end
				local dx, dy, dz = h.x - b.x, h.y - (b.y + BodyModule.STAND_EYE * 0.6), h.z - b.z
				if dx * dx + dy * dy + dz * dz <= reach then
					BotBrain.alert(b, flight.x, flight.y, flight.z, now) -- a splat beside it
				end
			end
		elseif h.kind == "tag" then
			local by = h.by or 0
			local tagger = brains[by]
			if tagger ~= nil and tagger.placed then
				BotBrain.say(tagger, bots.squad, now, out, "tagged")
			end
			local victim = state.slots[h.id]
			local from = poses[by]
			if victim == nil or from == nil then
				continue
			end
			-- "I am out!": the team knows where one of its own went down, if it knows nothing newer
			if now - squad.spot[victim.team].at > 3 then
				told(bots, victim.team, h.x, h.y - BodyModule.STAND_EYE * 0.6, h.z, now)
			end
			-- a team-mate tagged where a bot could see: it knows where that came from
			local cosHalf = math.cos(profile.sightHalf)
			for id, b in brains do
				if b.team ~= victim.team or not b.placed or id == h.id then
					continue
				end
				local dx, dy, dz = h.x - b.x, h.y - (b.y + BodyModule.eye(b.crouch)), h.z - b.z
				local d = math.sqrt(dx * dx + dy * dy + dz * dz)
				local lx, ly, lz = BodyModule.look(b.yaw, b.pitch)
				if d < 45 and d > 1e-3 and dx * lx + dy * ly + dz * lz >= cosHalf * d then
					BotBrain.alert(b, from.x, from.y + BodyModule.STAND_EYE, from.z, now)
				end
			end
		end
	end
end

-- One server tick. `poses` holds every slot's present pose (a person's is the one last put in a
-- snapshot); a bot reads the others and writes its own (x, y, z, yaw, pitch, crouch, and of bits only
-- BIT.crouch, BIT.sprint and BIT.air). A bot that is out stands still. `heard` is what happened since
-- the last tick. Returns what the bots want done.
function Bots.step(
	bots: Bots,
	state: State,
	poses: { [number]: Pose },
	heard: { Heard },
	now: number,
	dt: number
): { Command }
	local out: { Command } = {}
	local brains = bots.brains :: { [number]: BotBrain.Brain }
	if next(brains) == nil or bots.state ~= state then
		return out
	end
	local squad = bots.squad
	squad.tick += 1
	follow(bots.nav, bots.profile, squad, brains, state, poses, now)
	if #heard > 0 then
		hear(bots, state, poses, heard, now, out)
	end
	-- this tick's share of the sight checks (BOT.sightHz a bot a second, spread over the ticks) and one
	-- route search; whoever is first in line changes every tick, so nobody is always last
	local count = 0
	for _ in brains do
		count += 1
	end
	squad.sightLeft = math.max(1, math.ceil(count * bots.profile.sightHz * dt - 1e-6))
	squad.routeLeft = 1
	local first = squad.tick % RULES.slots
	for k = 1, RULES.slots do
		local brain = brains[(first + k - 1) % RULES.slots + 1]
		if brain ~= nil then
			BotBrain.step(brain, squad, state, poses, now, dt, out)
		end
	end
	return out
end

return Bots
