--!strict
-- ServerScriptService.Server.Minigames.Paintball.Bots
-- The bots that fill a paintball match (checklist PB-6, PB-10), as a pure model: no Instances, no
-- remotes. A bot is a seat of the match held by one of the framework's computer players
-- (Contract.BOTS), with a brain here; it has NO body in the world. The service keeps one table of
-- poses for every slot (arena frame), a bot's brain moves its own entry, and every client draws bots
-- and people alike from the snapshot stream (Shared/Minigames/Paintball/Clock).
-- OWNED BY THE MATCH-AND-BOTS LANE. THIS IS A STUB: the functions keep their names and signatures.
--
-- WHAT THE REAL BOTS DO, AND WITH WHAT (Contract.BOT holds the numbers named here):
--   * move kinematically over the arena's navigation graph (arena.nodes, arena.links: "walk" links
--     in a straight line, "stair" links along the ramp, feet on arena.ground) at the body's own
--     speeds (Body.speed with state.feel); a bot OWNS ITS CROUCH: it eases its own pose.crouch with
--     Body.crouchStep(c, want, dt, state.feel) every tick and the service never touches it. They use
--     both stairs of a storey, cross and overlook the atrium, never stop for good (PB-10: "never get
--     stuck"), walk out of their own spawn room after a respawn and do not go back in, and never
--     enter, stand at the door of, or shoot into the other team's (nodes with team ~= 0);
--   * SEE an opponent only along a clear line (arena.sweep from eye to chest) and only inside
--     BOT.sightHalf of where they are looking; a sight check per bot runs at most BOT.sightHz times a
--     second and the bots' checks are spread over the ticks (no tick does more than its share);
--   * HEAR what the service tells them (`heard`, below): a ball that is born, passes or lands within
--     BOT.hear studs of a bot, whoever fired it, and a team-mate tagged where the bot could see,
--     make it aware of the direction the ball came from. A bot that is shot at and missed does not
--     stand there: it turns, ducks or moves;
--   * act on anything seen or heard only after a reaction time between BOT.reactMin and BOT.reactMax;
--   * TURN at no more than BOT.turn (yaw and pitch each), and fire ONLY ALONG THEIR OWN LOOK: a
--     bot's pose yaw and pitch are where its marker points (the aim, lead and drop included), and the
--     service drops a "fire" whose direction is more than BOT.aimSlack from Body.look(pose.yaw,
--     pose.pitch). So a bot must be seen to turn on a player before it can tag them: the puppet is the
--     tell. (The calibration tool reports how often a bot's pose had been within the sight cone of
--     the player it tagged for BOT.faced seconds before the ball: the aim is nearly always.)
--   * aim with Ballistics.aim(..., state.feel.ballSpeed, state.feel.ballDrop) at where the target
--     will be, plus error, more of it at a low `skill`, and MOST OF IT ON THE FIRST BALL at a new
--     target: the first ball is the warning splat. A fair player beats the average bot (skill 0.5)
--     about three times in five;
--   * take cover (arena.cover: stand behind high cover, crouch behind low cover and rails), peek, and
--     fall back to reload;
--   * respect the match: they fire only when Rules.canFire(state, id, now) says so, with the same
--     magazine and reload as a person, never while BIT.sprint is set in their pose or within
--     Body.SPRINT_FIRE_DELAY of it, and never from inside a spawn room.
-- A bot's shot is a command for the service, which checks the look (above), calls Rules.fire(state,
-- id, now) and Projectiles.fire with no rewind: a bot sees the server's present. Every `now` here is
-- the shared clock (Clock): the same time the State is synced to.
-- COST (Contract.COST): Bots.step with COST.atBots bots costs under COST.botsMs a tick on average;
-- the lane measures it in its calibration tool and the service reports it (Stats.botsMs).
-- THE CALIBRATION TOOL (tools/games/paintball/bots/) takes a feel as input and prints its results
-- (how often a scripted fair player beats the average bot; stuck, camping and one-stair checks; the
-- facing figure above; the step's cost) at ball speeds 90, 120 and 150, so a faster ball can be
-- judged at the owner's playtest without waiting for a new calibration.
-- Interface: new(arena, opts?) -> Bots; sync(bots, state, who, poses, now); place(bots, id, pose,
--   now); step(bots, state, poses, heard, now, dt) -> { Command }; types Command, Heard, Opts, Bots

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
}

export type Bots = {
	arena: Arena,
	seed: number,
	brains: { [number]: any }, -- by slot id; the lane's own shape
}

local Bots = {}

function Bots.new(arena: Arena, opts: Opts?): Bots
	local o: Opts = opts or {}
	return { arena = arena, seed = o.seed or 1, brains = {} }
end

-- Make the brains match the match: one for every slot a bot holds, none for a slot a person took or
-- that is off. `who[id]` is that bot's skill (Contract.BOTS: 0..1, 0.5 the average bot); a slot
-- with no entry is not a bot. The service calls this after every seat taken or left and after a
-- change of side. A new brain starts from poses[id]; a brain whose slot changed team forgets its plan.
function Bots.sync(_bots: Bots, _state: State, _who: { [number]: number }, _poses: { [number]: Pose }, _now: number) end

-- The service put this bot somewhere (the briefing, a respawn, a change of side): forget the old path.
function Bots.place(_bots: Bots, _id: number, _pose: Pose, _now: number) end

-- One server tick. `poses` holds every slot's present pose (a person's is the one last put in a
-- snapshot); a bot reads the others and writes its own (x, y, z, yaw, pitch, crouch, and of bits only
-- BIT.crouch, BIT.sprint and BIT.air). A bot that is out stands still. `heard` is what happened since
-- the last tick. Returns what the bots want done.
function Bots.step(
	_bots: Bots,
	_state: State,
	_poses: { [number]: Pose },
	_heard: { Heard },
	_now: number,
	_dt: number
): { Command }
	return {}
end

return Bots
