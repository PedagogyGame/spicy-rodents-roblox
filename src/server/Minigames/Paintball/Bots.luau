--!strict
-- ServerScriptService.Server.Minigames.Paintball.Bots
-- The bots that fill a paintball match (checklist PB-6, PB-10), as a pure model: no Instances, no
-- remotes. A bot is a seat of the match held by one of the framework's computer players
-- (Contract.BOTS), with a brain here; it has NO body in the world. The service keeps one table of
-- poses for every slot (arena frame), a bot's brain moves its own entry, and every client draws bots
-- and people alike from the snapshot stream (Shared/Minigames/Paintball/Clock).
-- OWNED BY THE MATCH-AND-BOTS LANE. THIS IS A STUB: the functions keep their names and signatures.
--
-- WHAT THE REAL BOTS DO, AND WITH WHAT:
--   * move kinematically over the arena's navigation graph (arena.nodes, arena.links: "walk" links
--     in a straight line, "stair" links along the ramp, feet on arena.ground) at the body's own
--     speeds (Body.speed), crouching with Body.crouchStep; they use both stairs of a storey, cross
--     and overlook the atrium, never stand in a spawn room once out of it, never stop for good
--     (PB-10: "never get stuck");
--   * see an opponent only along a clear line (arena.sweep from eye to chest), notice it 250 to 450
--     ms late, and aim with Ballistics.aim at where it will be, plus error, more of it at a low
--     `skill`; a fair player beats the average bot (skill 0.5) about three times in five;
--   * take cover (arena.cover: stand behind high cover, crouch behind low cover and rails), peek, and
--     fall back to reload;
--   * respect the match: they fire only when Rules.canFire says so, with the same five-ball magazine
--     and reload as a person, and never while sprinting.
-- A bot's shot is a command for the service, which calls Rules.fire and Projectiles.fire with no
-- rewind: a bot sees the server's present. Every `now` here is the shared clock (Clock): the same
-- time the State was synced to.
-- Interface: new(arena, opts?) -> Bots; sync(bots, state, who, poses, now); place(bots, id, pose,
--   now); step(bots, state, poses, now, dt) -> { Command }

-- (types only: typeof never runs its require; see "HOW TO IMPORT" in Shared/Minigames/Paintball/Contract)
type Arena = typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Arena).T.Arena)
type Pose = typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Contract).T.Pose)
type State = typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Rules).T.State)

-- What a bot asks the service to do this tick.
--   fire    a ball from (ox, oy, oz), the bot's eye point, with velocity (vx, vy, vz) of Rules.ballSpeed
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
-- with no entry is not a bot. The service calls this after every seat taken or left. A new brain
-- starts from poses[id].
function Bots.sync(_bots: Bots, _state: State, _who: { [number]: number }, _poses: { [number]: Pose }, _now: number) end

-- The service put this bot somewhere (the briefing, a respawn): forget the old path.
function Bots.place(_bots: Bots, _id: number, _pose: Pose, _now: number) end

-- One server tick. `poses` holds every slot's present pose; a bot reads the others and writes its
-- own (x, y, z, yaw, pitch, crouch, and of bits only BIT.crouch, BIT.sprint and BIT.air). A bot that
-- is out stands still. Returns what the bots want done.
function Bots.step(_bots: Bots, _state: State, _poses: { [number]: Pose }, _now: number, _dt: number): { Command }
	return {}
end

return Bots
