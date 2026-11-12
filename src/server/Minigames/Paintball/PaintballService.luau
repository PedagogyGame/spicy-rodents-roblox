--!strict
-- ServerScriptService.Server.Minigames.Paintball.PaintballService
-- The paintball server (checklist PB-3, PB-4, PB-6, PB-11, PB-12, PB-14, PB-15): everything behind
-- paintball's Table in the minigame framework (Server/Minigames/Games/Paintball hands each hook of
-- the Table to a method here). It owns the match loop, the five remotes, validation,
-- lag-compensated hits, splats, the roster, the audience and the access pass.
-- OWNED BY THE SERVER LANE. THIS IS A STUB: `new`, `port` and the Service's methods keep their names
-- and signatures; the lane writes the bodies and may add files beside this one (not named Bot*.luau:
-- those are the match-and-bots lane's). The stub seats nobody ("The arena is closed.").
--
-- WHAT IT IS BUILT FROM. new(ctx, deps): ctx is the framework's ServerGame.Ctx for the arena's
-- station; deps is ctx.opts.paintball (a spec's stand-ins; nil in the game). The arena is pure data
-- (ArenaData.build()) placed with Arena.placeOf(ctx.place). The FURNITURE is the baked model
-- ctx.root[Arena.MODEL]: without it `hw` is nil and the service is inert, as the framework asks of
-- every game (no remote bound, nothing stepped, nothing sent, "The arena is closed." to a join). The
-- PORT is how it reaches paintball's own remotes: deps.port, else PaintballService.port(ctx.net).
-- It is bound only when hw is there, so nobody else's test ever sees a paintball remote; a spec that
-- wants the stream passes tests/lib/PaintballRig's port. The match model is the Session's:
-- state() = ctx.session.game.state while ctx.session.phase is "playing" or "done" (a Rules.State).
-- ONE CLOCK: every `now` below is ctx.stamp(), the shared clock (Clock). ctx.now() is read for one
-- thing only, how long the end card has been up (ctx.session.doneEnds is on that clock).
--
-- THE FRAMEWORK'S HOOKS (ServerGame.Table), in the order the service uses them
--   join(player, via)     via.id == Contract.DESK: the pass desk. pass.buy(player) and return false
--                         with its words (the framework shows them and seats nobody). Otherwise the
--                         door: refuse with words when deps.fit says no ("infected": decision D6),
--                         when the player holds no pass (pass.has; a pass is checked only here, so a
--                         match in progress always finishes: D5), or when all Rules.slots seats are
--                         people ("full"). A player who is already seated: true, nothing done.
--                         Then THE ROSTER: if a match is on and a bot is seated, take
--                         one off with ctx.removeComputer (the bot on the side with fewer people; a
--                         tie: the lower seat) and the framework gives the person that seat.
--   joined(player, seat)  the person is seated (the first one has just started the match: "start"
--                         came first). Put their body in the spawn room (the "respawn" event Rules
--                         emitted does it in the next step), send them every splat so far, put them
--                         in the audience now ("paintball_watch"). If the seats are now odd, seat a
--                         bot (ctx.addComputer). Bots.sync.
--   command(player, verb, args)   the framework's own table verbs are not a player's to send in a
--                         match that starts itself, rolls on by itself and seats its own bots:
--                         "start", "again", "addai" and "mode" are refused with words. ("leave" is
--                         left to the framework.)
--   input(player, seat, verb, args)   "reload" { t }: t clamped as a fire time is (Clock.stamp), then
--                         Rules.reload(state, seat, t); false with words when it does nothing. Always
--                         answered here (never nil: the framework would hand the raw t to the rules).
--   step(dt)              THE LOOP, below. Runs before the Session's own step.
--   event(e)              "start": a match begins. match += 1; Rules.sync(state, now); every splat,
--                         ball and pose history is dropped; the audience is told (a new `match`). The
--                         framework then seats bots up to the Spec's fill, each through Rules.join; in
--                         the next step, if the seats are odd, one more bot.
--                         "left": a seat was left. A person: forget their stream, put their body at
--                         arena.lobby (if they still have one), and while the match is on and a
--                         person remains, seat a bot at once (ctx.addComputer: it takes the vacated
--                         seat). Bots.sync either way.
--                         "done": the clock ran out; the framework shows Rules.result's card.
--                         "reset": nobody is left: drop everything, "paintball_unwatch" to the audience.
--   state(player, seat)   Contract.Extras for that player's "state" message.
--   inPlay(player, body)  the framework's walk-away check, for an arena: true while the body is
--                         inside the arena volume (Arena.inVolume with a few studs to spare), and for
--                         TRUST.placeGrace after the server moved it. False takes the player off.
--   screen(view), sig(view)   the monitors: every part named Arena.MONITOR under hw (the lobby's,
--                         and the old sets on each floor: the arena lane's bake) shows the phase, the
--                         clock and both scores; idle, it shows the station's name.
--   prompt()              one action line for both prompts ("Paintball"): each label says the rest.
--   doneText(view)        the end banner: Result.text.
--   debug(...)            scripted outcomes for the engine check (tests/engine/PaintballFlow): at
--                         least "tag" (by, id) and "end" (the clock runs out now).
-- ROLLING ON. While ctx.session.phase is "done": when Rules.endCardSecs of end card have passed
-- (ctx.session.doneEnds - ctx.now() <= Rules.endCardSpare), take every bot off (ctx.removeComputer)
-- and call ctx.again(). The people still seated are dealt seats 1, 2, 3 ... in their old order, so
-- they alternate between the teams; "start" and the fill then rebuild the sides at the size the
-- people present need (never under teamMin a side). If only bots are left the framework resets.
--
-- THE LOOP (step(dt), every server step; now = ctx.stamp())
--   0. Nothing at all unless hw is there and ctx.session.phase is "playing" (PB-15: an idle arena
--      costs nothing). If state.now has strayed Clock.SYNC_SLACK from now: Rules.sync.
--   1. Rules.drain(state) -> messages (Wire: "paintball_tag", "paintball_respawn",
--      "paintball_reload" by ctx.broadcast; a "phase" needs only ctx.dirty(): the view carries it).
--      A "respawn" places the slot at arena.spawns[team][spawn]: a person's real body is moved there
--      (engine.teleport, world: Arena.toWorld with the place) and their pose set; a bot's pose is set
--      and Bots.place called. A "tag" also calls ctx.dirty() (the scores changed).
--   2. People: a slot whose move stream has been silent for Clock.STALE_SECS holds its last pose and
--      may not fire; after Clock.DROP_SECS: ctx.leave(player, "dropped", words) and, through
--      "left", a bot takes the seat. A pose inside an arena.exits room: ctx.leave(player, "exit").
--   3. Bots.step(bots, state, poses, now, dt): the bots move their own poses; each "fire" command
--      goes through Rules.fire(state, id, now) and then Projectiles with no rewind; "reload" through
--      Rules.reload; "say" out as "paintball_say".
--   4. Balls: Projectiles.step against arena.sweep and the pose histories of every slot that
--      Rules.canBeHit; a ball that ends on a body -> Rules.tag(state, by, id, now) (a tag makes the
--      "paintball_tag" message, with the ball's id and the hit point); every ball that ends on
--      something -> one Splat record (wall: point and face; body: Wire.toBody offset), batched per
--      tick. Born balls -> one Shot batch per tick (Wire.SHOTS_PER_MESSAGE at most in a message).
--   5. Every 1 / Clock.SNAP_HZ seconds, the snapshot tick: each slot's crouch fraction takes one
--      Body.crouchStep towards its crouch bit; every slot that is on has its pose quantised
--      (Wire.quantPose), pushed into its PoseHistory at the snapshot's time, and sent
--      (Wire.encodeSnap with the match number) to the audience. THE HISTORY IS THE SNAPSHOT STREAM
--      (Clock): nothing else is ever pushed.
--   6. Every Clock.AUDIENCE_SECS: the audience. Of ctx.town.people(), whoever stands within
--      Arena.AUDIENCE_MARGIN of the arena volume (Arena.toLocal, Arena.inVolume), and everybody
--      seated, is in it: on coming in they get "paintball_watch" (ctx.send: the match number and who
--      holds which slot) and every splat so far as one Splat batch; on going out
--      "paintball_unwatch". The streams go to the audience and to nobody else. "paintball_watch"
--      goes out again to all of it when the roster changes and when a match starts.
-- THE REMOTES (Wire; Shared/Net has checked shape and rate before the port hands a record over)
--   onMove   a person's pose. Accept or refuse by Contract.TRUST: inside the arena, on or just above
--            arena.ground, no wall between the last accepted pose and this one (arena.sweep at
--            Arena.CHEST), inside the distance budget of Body.speed, near the replicated body
--            (engine.positionOf). Refused poses are dropped; after TRUST.refusalsBeforeCorrect in a
--            second the real body is put back on the last accepted pose and the client told
--            ("paintball_correct" by ctx.send). A record from somebody not seated is dropped.
--   onFire   a click. Clock.stamp(now, vt, ft, lastFt, estimate) gives the fire time, how late the
--            ball is and the rewind; refuse (a "paintball_ack" with ok = false and a why) when the
--            slot is stale or sprinting (Body.isSprinting of the measured speed, or within
--            Body.SPRINT_FIRE_DELAY of it), when the origin is further than TRUST.originSlack from
--            the slot's own eye point or a wall stands between them, or when Rules.fire(state, id,
--            fireTime) refuses. Otherwise the ball is born at the fire time with velocity = the unit
--            direction x Rules.ballSpeed, flown forward by `late` at once, and acknowledged with the
--            server's magazine.
-- IN AND OUT OF A MATCH, AND THE TOWN. The player keeps possessing the body they walked in with the
-- whole time; the town's own systems go on outside and never reach in (the arena volume is sealed:
-- Arena). Joining moves that body to its team's spawn room; leaving (the framework's Leave, walking
-- into an exit, dropped, the player gone, the body lost: each arrives as "left") moves it to
-- arena.lobby. First person is the client's own doing (Client/Minigames/Games/Paintball).
-- THE PASS (PB-12). `pass` is deps.pass, else the lane's own on ctx.town.charge(player,
-- Rules.passCents, "a paintball pass") (a stand-in that takes nothing until the town has a wallet;
-- honour a false and show its words): a pass runs Rules.passDays in-game days from deps.day(), and
-- until there is a profile it is remembered for as long as the server runs.
-- THE S18 CORE in Server/Paintball is this lane's to extend, keeping tests/unit/paintball_hitreg.spec green:
--   PoseHistory  gains a crouch channel beside x, y, z (same ring, same interpolation), so a crouched
--                body is judged crouched (PB-3); built with Clock.HISTORY_SECS at Clock.SNAP_HZ here.
--   Projectiles  tests the building through arena.sweep instead of scanning a box list, bodies with
--                Body.capsule(crouch) instead of Config.body, can fly one new ball forward by `late`
--                against the bodies of those past moments, and reports the hit point.
--   Splats       the pool of Rules.splatPool; its seq is the Splat record's seq; cleared with the match.
--   Layout, Harness  the S18 greybox and its hit-agreement harness: kept as the regression test of
--                the rewind, and given a condition that stamps shots the contract's way (Clock.stamp,
--                history at SNAP_HZ, view time from Clock.viewTime) with the 95 % bar at 150 ms.
-- Interface: new(ctx, deps?) -> Service; port(net) -> Port; types Port, Engine, PassDesk, Deps, Stats,
--   Service. Service: hw; join(player, via) -> (ok, why?); joined(player, seat, via); command(player,
--   verb, args) -> (handled, ok?, why?); input(player, seat, verb, args) -> (ok?, why?); step(dt);
--   event(e); state(player, seat) -> Extras?; inPlay(player, body) -> boolean; screen(view);
--   sig(view) -> any; prompt() -> (action?, object?); doneText(view) -> string?; debug(...) -> (ok,
--   why?); onMove(player, rec); onFire(player, rec); watching(player) -> boolean; stats() -> Stats

local Import = require("../../Import")
local ArenaModule: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Arena)) =
	Import.shared("Minigames/Paintball/Arena")
local ArenaData: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.ArenaData)) =
	Import.shared("Minigames/Paintball/ArenaData")
local Contract: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Contract)) =
	Import.shared("Minigames/Paintball/Contract")
local ServerGame = require("../ServerGame")
local Bots = require("./Bots")

type Arena = typeof(ArenaModule.T.Arena)
type Place = typeof(ArenaModule.T.Place)
type Pose = typeof(Contract.T.Pose)
type Extras = typeof(Contract.T.Extras)

-- The service's link to paintball's own remotes (Wire.REMOTES).
--   on    hear a client-to-server remote ("Paintball.Move", "Paintball.Fire"): the record is already
--         decoded from its layout, checked finite and rate-limited by Shared/Net
--   fire  send a server-to-client buffer ("Paintball.Snap", "Paintball.Shot", "Splat") to one player
export type Port = {
	on: (remote: string, fn: (player: any, record: { [string]: number }) -> ()) -> (),
	fire: (player: any, remote: string, payload: buffer) -> (),
}

-- Everything that touches a body in the world, injected so the whole service runs under Lune.
-- World coordinates here; the service converts with Arena.toWorld / toLocal and its place.
export type Engine = {
	positionOf: (body: any) -> (number?, number?, number?), -- the real body's feet point; nil if gone
	teleport: (body: any, x: number, y: number, z: number, yaw: number) -> (), -- feet point and yaw
	pingOf: (player: any) -> number?, -- seconds of round trip, if known
}

-- The access pass (PB-12): 20 spicy cents for five in-game days.
export type PassDesk = {
	has: (player: any) -> boolean,
	-- Sell one: (true, Contract.textFor("bought")) or (false, words such as Contract.passShort(20, 7)
	-- or Contract.textFor("has_pass")). Never sells a second pass to a holder.
	buy: (player: any) -> (boolean, string),
}

-- A spec's stand-ins, handed over as the MinigameService option `paintball` (ctx.opts.paintball).
export type Deps = {
	port: Port?, -- default: port(ctx.net) (nil without a net: the stream goes nowhere)
	engine: Engine?, -- default: the real one, on the bodies ctx.bodyOf returns
	arena: Arena?, -- default ArenaData.build()
	seed: number?,
	pass: PassDesk?, -- default: the lane's own, on ctx.town.charge
	fit: ((player: any) -> (boolean, string?))?, -- fit to play? (false, a Contract.WHY code): "infected"
	day: (() -> number)?, -- the in-game day, for the pass
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
	ctx: ServerGame.Ctx,
	deps: Deps,
	hw: any?, -- the baked arena model (ctx.root[Arena.MODEL]); nil = inert
	arena: Arena,
	place: Place,
	port: Port?,
	bots: Bots.Bots,
	match: number, -- Contract.Extras.match
	poses: { [number]: Pose }, -- every slot's present pose, arena frame, by slot id
	audience: { [any]: boolean },
	join: (self: Service, player: any, via: ServerGame.StationDef) -> (boolean, string?),
	joined: (self: Service, player: any, seat: number?, via: ServerGame.StationDef) -> (),
	command: (self: Service, player: any, verb: string, args: { any }) -> (boolean, boolean?, string?),
	input: (self: Service, player: any, seat: number, verb: string, args: { any }) -> (boolean?, string?),
	step: (self: Service, dt: number) -> (),
	event: (self: Service, e: ServerGame.Event) -> (),
	state: (self: Service, player: any, seat: number?) -> Extras?,
	inPlay: (self: Service, player: any, body: Model?) -> boolean,
	screen: (self: Service, view: { [string]: any }) -> (),
	sig: (self: Service, view: { [string]: any }) -> any,
	prompt: (self: Service) -> (string?, string?),
	doneText: (self: Service, view: { [string]: any }) -> string?,
	debug: (self: Service, ...any) -> (boolean, string?),
	onMove: (self: Service, player: any, rec: { [string]: number }) -> (),
	onFire: (self: Service, player: any, rec: { [string]: number }) -> (),
	watching: (self: Service, player: any) -> boolean,
	stats: (self: Service) -> Stats,
}

local PaintballService = {}

-- The Port onto a Shared/Net instance (the game's: ServerGame.Ctx.net).
function PaintballService.port(net: any): Port
	return {
		on = function(remote: string, fn: (player: any, record: { [string]: number }) -> ())
			net:on(remote, fn)
		end,
		fire = function(player: any, remote: string, payload: buffer)
			net:fire(player, remote, payload)
		end,
	}
end

local function noEngine(): Engine
	return {
		positionOf = function(_body: any): (number?, number?, number?)
			return nil, nil, nil
		end,
		teleport = function(_body: any, _x: number, _y: number, _z: number, _yaw: number) end,
		pingOf = function(_player: any): number?
			return nil
		end,
	}
end

function PaintballService.new(ctx: ServerGame.Ctx, deps: Deps?): Service
	local d: Deps = deps or (ctx.opts.paintball :: Deps?) or {}
	local arena = d.arena or ArenaData.build()
	local root = ctx.root
	local hw = if root then root:FindFirstChild(ArenaModule.MODEL) else nil
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
		ctx = ctx,
		deps = d,
		hw = hw,
		arena = arena,
		place = ArenaModule.placeOf(ctx.place),
		port = nil,
		bots = Bots.new(arena, { seed = d.seed }),
		match = 0,
		poses = {},
		audience = {},
	} :: Service
	-- (the stub has no engine of its own to give: the lane builds the real one here)
	local _engine: Engine = d.engine or noEngine()

	function service.join(_self: Service, _player: any, _via: ServerGame.StationDef): (boolean, string?)
		return false, Contract.textFor("closed")
	end

	function service.joined(_self: Service, _player: any, _seat: number?, _via: ServerGame.StationDef) end

	function service.command(_self: Service, _player: any, verb: string, _args: { any }): (boolean, boolean?, string?)
		if verb == "start" or verb == "again" or verb == "addai" or verb == "mode" then
			return true, false, Contract.textFor("phase")
		end
		return false, nil, nil
	end

	function service.input(
		_self: Service,
		_player: any,
		_seat: number,
		_verb: string,
		_args: { any }
	): (boolean?, string?)
		return false, Contract.textFor("phase")
	end

	function service.step(_self: Service, _dt: number)
		stats.steps += 1
	end

	function service.event(_self: Service, _e: ServerGame.Event) end

	function service.state(self: Service, _player: any, _seat: number?): Extras?
		return { match = self.match, bots = {}, rounds = Contract.Rules.magazine, reloadAt = 0 }
	end

	function service.inPlay(_self: Service, _player: any, _body: Model?): boolean
		return true
	end

	function service.screen(_self: Service, _view: { [string]: any }) end

	function service.sig(_self: Service, _view: { [string]: any }): any
		return false
	end

	function service.prompt(_self: Service): (string?, string?)
		return "Paintball", nil
	end

	function service.doneText(_self: Service, view: { [string]: any }): string?
		local result = view.result
		return if type(result) == "table" and type(result.text) == "string" then result.text else nil
	end

	function service.debug(_self: Service, ...: any): (boolean, string?)
		local _asked = select("#", ...)
		return false, Contract.textFor("closed")
	end

	function service.onMove(_self: Service, _player: any, _rec: { [string]: number }) end

	function service.onFire(_self: Service, _player: any, _rec: { [string]: number }) end

	function service.watching(self: Service, player: any): boolean
		return self.audience[player] == true
	end

	function service.stats(_self: Service): Stats
		return stats
	end

	-- the remotes, only where the arena stands
	if hw ~= nil then
		local port = d.port or (if ctx.net then PaintballService.port(ctx.net) else nil)
		service.port = port
		if port then
			port.on("Paintball.Move", function(player: any, rec: { [string]: number })
				service:onMove(player, rec)
			end)
			port.on("Paintball.Fire", function(player: any, rec: { [string]: number })
				service:onFire(player, rec)
			end)
		end
	end

	return service
end

return PaintballService
