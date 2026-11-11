--!strict
-- ServerScriptService.Server.Paintball.PaintballService
-- The paintball server (checklist PB-3, PB-4, PB-6, PB-11, PB-12, PB-14, PB-15): it owns the match
-- loop, the remotes, validation, lag-compensated hits, splats, the audience and the access pass.
-- OWNED BY THE SERVER LANE. THIS IS A STUB: `new`, `start` and the Service's methods keep their names
-- and signatures; the lane writes the bodies and may add files beside this one (not Match.luau or
-- Bots.luau, which are the match-and-bots lane's).
--
-- THE LOOP (step(dt), every Heartbeat; now = engine.now(), server time):
--   1. Match.step(match, now); Match.drain(match) -> wire messages (Wire State "match", "tag",
--      "respawn", "reload", "end"). A "respawn" places the slot: a person's real body is teleported
--      to arena.spawns[team][spawn] (world: Arena.toWorld with the place) and told; a bot's pose is
--      set and Bots.place called. A "roster" calls Bots.sync.
--   2. People: a slot whose move stream has been silent for Clock.STALE_SECS holds its last pose and
--      may not fire; after Clock.DROP_SECS it leaves (why "dropped") and a bot takes the slot.
--   3. Bots.step(bots, match, poses, now, dt): the bots move their own poses; each "fire" command
--      goes through Match.fire(match, id, now) and then Projectiles with no rewind.
--   4. Balls: Projectiles.step against arena.sweep and the pose histories of every slot that
--      Match.canBeHit; a ball that ends on a body -> Match.hit(by, id, now) (a tag makes the "tag"
--      message, with the ball's id and the hit point); every ball that ends on something -> one
--      Splat record (wall: point and face; body: Wire.toBody offset), batched per tick. Born balls
--      -> one Shot batch per tick.
--   5. Every 1 / Clock.SNAP_HZ seconds, the snapshot tick: each slot's crouch fraction takes one
--      Body.crouchStep towards its crouch bit; every slot's pose is quantised (Wire.quantPose),
--      pushed into its PoseHistory at the snapshot's time, and sent (Wire.encodeSnap) to the audience.
--      THE HISTORY IS THE SNAPSHOT STREAM (Shared/Paintball/Clock): nothing else is ever pushed.
--   6. Twice a second: the audience. A player whose body is within Arena.AUDIENCE_MARGIN of the arena
--      volume gets "watch" (the match, the place, every splat so far) and from then on everything;
--      one who goes away gets "unwatch". Nothing at all is sent to anybody else, and while the match
--      is idle nothing is stepped (PB-15).
-- THE REMOTES (Shared/Paintball/Wire; Shared/Net checks shape and rate before these are called):
--   onMove   a person's pose. Accept or refuse by Contract.TRUST: inside the arena, on or just above
--            arena.ground, no wall between the last accepted pose and this one (arena.sweep at
--            Arena.CHEST), inside the distance budget of Body.speed, near the replicated body
--            (engine.positionOf). A pose inside an arena.exits room is a leave. Refused poses are
--            dropped; after TRUST.refusalsBeforeCorrect in a second the real body is put back on the
--            last accepted pose and the client told ("correct").
--   onFire   a click. Clock.stamp(now, vt, ft, lastFt, estimate) gives the fire time, how late the
--            ball is and the rewind; refuse (ack ok = false with a why) when the slot is stale or
--            sprinting (Body.isSprinting of the measured speed, or within Body.SPRINT_FIRE_DELAY of
--            it), when the origin is further than TRUST.originSlack from the slot's own eye point or
--            a wall stands between them, or when Match.fire(match, id, fireTime) refuses. Otherwise
--            the ball is born at the fire time with velocity = the unit direction x Rules.ballSpeed,
--            flown forward by `late` at once, and acknowledged with the server's magazine.
--   onCmd    "pass" -> buyPass; "join" -> join; "leave" -> leave; "reload" -> Match.reload.
-- IN AND OUT OF A MATCH. join: the player must be a person who may play (deps.canPlay: people only,
--   not infected), hold a pass (deps.pass.has; a pass is checked only here, so a match in progress
--   always finishes: decision D5) and stand within JOIN_RADIUS of the pass desk; then Match.join, the
--   body is teleported to its team's spawn room, its CameraZone attribute set to "lockFirstPerson"
--   (engine.setZone: the existing Client/Possession applies Camera/CameraPolicy "lockFirst" from that
--   attribute, and releases it when the attribute is cleared), and "joined" is sent. The player keeps
--   possessing the body it walked in with the whole time. leave (asked for, an exit, dropped, the
--   player gone, the body lost): Match.leave, the zone cleared, the body put at arena.lobby, "left".
-- THE S18 CORE in this folder is this lane's to extend, keeping tests/unit/paintball_hitreg.spec green:
--   PoseHistory  gains a crouch channel beside x, y, z (same ring, same interpolation), so a crouched
--                body is judged crouched (PB-3); built with Clock.HISTORY_SECS at Clock.SNAP_HZ here.
--   Projectiles  tests the building through arena.sweep instead of scanning a box list, bodies with
--                Body.capsule(crouch) instead of Config.body, can fly one new ball forward by `late`
--                against the bodies of those past moments, and reports the hit point.
--   Splats       the pool of Rules.splatPool; its seq is the Splat record's seq; cleared with the match.
--   Layout, Harness  the S18 greybox and its hit-agreement harness: kept as the regression test of
--                the rewind, and given a condition that stamps shots the contract's way (Clock.stamp,
--                history at SNAP_HZ, view time from Clock.viewTime) with the 95 % bar at 150 ms.
-- Interface: new(deps) -> Service; start(opts?) -> Service? (engine: binds the remotes and Heartbeat);
--   Service:buyPass(player) -> (ok, text); join(player) -> (ok, why?); leave(player, why?);
--   onMove(player, rec); onFire(player, rec); onCmd(player, payload); step(dt); watching(player) ->
--   boolean; stats() -> Stats; stop(); JOIN_RADIUS

local Import = require("../Import")
local ArenaModule: typeof(require(game.ReplicatedStorage.Shared.Paintball.Arena)) = Import.shared("Paintball/Arena")
local ArenaData: typeof(require(game.ReplicatedStorage.Shared.Paintball.ArenaData)) =
	Import.shared("Paintball/ArenaData")
local Contract: typeof(require(game.ReplicatedStorage.Shared.Paintball.Contract)) = Import.shared("Paintball/Contract")
local Bots = require("./Bots")
local Match = require("./Match")

type Arena = typeof(ArenaModule.T.Arena)
type Place = typeof(ArenaModule.T.Place)
type Pose = typeof(Contract.T.Pose)

-- Everything that touches the engine, injected so the whole service runs under Lune with stubs.
-- World coordinates here; the service converts with Arena.toWorld / toLocal and its place.
export type Engine = {
	now: () -> number, -- server time (workspace:GetServerTimeNow())
	positionOf: (body: any) -> (number?, number?, number?), -- the real body's feet point; nil if gone
	teleport: (body: any, x: number, y: number, z: number, yaw: number) -> (), -- feet point and yaw
	setZone: (body: any, zone: string?) -> (), -- the body's CameraZone attribute
	pingOf: (player: any) -> number?, -- seconds of round trip, if known
}

-- The access pass (PB-12): 20 spicy cents for five in-game days. The service only asks; where the
-- pass and the money are kept is behind this port.
export type PassDesk = {
	has: (player: any) -> boolean,
	-- Sell one: (true, words, the game day it runs out) or (false, words such as
	-- Contract.passShort(20, 7), nil). Never sells a second pass to a holder ("has_pass").
	buy: (player: any) -> (boolean, string, number?),
}

export type Deps = {
	net: any?, -- a Shared/Net instance: handlers are bound and messages go out through it
	send: ((player: any, remote: string, payload: any) -> ())?, -- instead of net (tests capture here)
	arena: Arena?, -- default ArenaData.build()
	place: Place?, -- where the arena is in the world; default Arena.PLACE
	engine: Engine?, -- default: stubs that know nothing (Lune)
	seed: number?,
	players: (() -> { any })?, -- everyone on the server, for the audience scan
	bodyOf: ((player: any) -> any?)?, -- the body a player possesses
	canPlay: ((player: any) -> (boolean, string?))?, -- people only, not infected: (false, WHY code)
	pass: PassDesk?, -- default: everybody holds a pass (tests)
}

export type Stats = {
	steps: number,
	snapshots: number,
	balls: number,
	tags: number,
	movesAccepted: number,
	movesRefused: number,
	shotsRefused: number,
	corrections: number,
	stepMs: number, -- the last step's cost
}

export type Service = {
	deps: Deps,
	arena: Arena,
	place: Place,
	match: Match.Match,
	bots: Bots.Bots,
	poses: { [number]: Pose }, -- every slot's present pose, arena frame, by slot id
	audience: { [any]: boolean },
	buyPass: (self: Service, player: any) -> (boolean, string),
	join: (self: Service, player: any) -> (boolean, string?),
	leave: (self: Service, player: any, why: string?) -> (),
	onMove: (self: Service, player: any, rec: { [string]: number }) -> (),
	onFire: (self: Service, player: any, rec: { [string]: number }) -> (),
	onCmd: (self: Service, player: any, payload: { verb: string, t: number? }) -> (),
	step: (self: Service, dt: number) -> (),
	watching: (self: Service, player: any) -> boolean,
	stats: (self: Service) -> Stats,
	stop: (self: Service) -> (),
}

local PaintballService = {}

PaintballService.JOIN_RADIUS = 14 -- studs from Arena.DESK within which "join" and "pass" are heard

function PaintballService.new(deps: Deps): Service
	local arena = deps.arena or ArenaData.build()
	local stats: Stats = {
		steps = 0,
		snapshots = 0,
		balls = 0,
		tags = 0,
		movesAccepted = 0,
		movesRefused = 0,
		shotsRefused = 0,
		corrections = 0,
		stepMs = 0,
	}
	local service = {
		deps = deps,
		arena = arena,
		place = deps.place or ArenaModule.PLACE,
		match = Match.new({ seed = deps.seed }),
		bots = Bots.new(arena, { seed = deps.seed }),
		poses = {},
		audience = {},
	} :: Service

	function service.buyPass(_self: Service, _player: any): (boolean, string)
		return false, Contract.textFor("closed")
	end

	function service.join(_self: Service, _player: any): (boolean, string?)
		return false, "closed"
	end

	function service.leave(_self: Service, _player: any, _why: string?) end

	function service.onMove(_self: Service, _player: any, _rec: { [string]: number }) end

	function service.onFire(_self: Service, _player: any, _rec: { [string]: number }) end

	function service.onCmd(_self: Service, _player: any, _payload: { verb: string, t: number? }) end

	function service.step(_self: Service, _dt: number)
		stats.steps += 1
	end

	function service.watching(self: Service, player: any): boolean
		return self.audience[player] == true
	end

	function service.stats(_self: Service): Stats
		return stats
	end

	function service.stop(_self: Service) end

	return service
end

export type StartOpts = {
	net: any?,
	place: Place?,
	bodyOf: ((player: any) -> any?)?,
	canPlay: ((player: any) -> (boolean, string?))?,
	pass: PassDesk?,
	heartbeat: boolean?, -- default true
}

-- Engine wiring, called once by the boot when paintball is joined to the game: builds the Engine,
-- binds Paintball.Move, Paintball.Fire and Paintball.Cmd on the Net instance, steps on Heartbeat,
-- leaves a player who quits. The stub starts nothing.
function PaintballService.start(_opts: StartOpts?): Service?
	return nil
end

return PaintballService
