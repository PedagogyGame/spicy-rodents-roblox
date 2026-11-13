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
-- THE FEEL: service.feel is the feel the NEXT match will be played with (deps.feel, else the
-- defaults); the match in play keeps its own (state.feel), and everything below that says `feel`
-- means state.feel.
--
-- WHAT THE SERVICE KEEPS FOR A PERSON. It is kept BY PLAYER, not by seat (the people still seated are
-- dealt new seats at every new match, and their clients' controllers live on across it); "the slot's"
-- below means "of the person who holds that slot". All of it starts afresh when a person is seated
-- (joined); at a new match (`start`) `place`, `up`, `lastM` and `shot` carry on and the rest starts afresh.
--   place     the placement number (Wire.nextPlace each time the server moves the body; 0 until the
--             first placement: until then the person's Moves are dropped and inPlay says yes)
--   moves     the last Clock.MOVES_KEPT accepted Moves, by their own t; emptied by every placement
--   anchor    the last accepted pose (after a placement: the pose the server placed)
--   up        a Clock.View fed by Clock.observe(up, move.t, now) for every Move that gets as far as
--             being judged: the smoothed upstream delay
--   budget    the horizontal distance it may still move (Contract, "distance"); full after a placement
--   crouch    the crouch fraction, eased by the service (step 5)
--   lastM     the magazine time of its last accepted shot; shot: the counter of its last judged click
--   heardAt   when a Move last got as far as being judged (silence is measured from it)
--   idle      the pose and the time its idleness is measured from
-- "THE SLOT'S POSE AT t" (used at a snapshot tick and at a fire time): the straight line between the
-- two Moves of `moves` either side of t (x, y, z); held at the newest Move when t is past it, at the
-- oldest when t is before it; the anchor when `moves` is empty. Yaw, pitch and the client's bits
-- (crouch, sprint, air) are the newer of the two Moves'.
--
-- THE FRAMEWORK'S HOOKS (ServerGame.Table), in the order the service uses them
--   join(player, via)     via.id == Contract.DESK: the pass desk. pass.buy(player) and return false
--                         with its words (the framework shows them and seats nobody). Otherwise the
--                         door, in this order: a player who is already seated: true, nothing done.
--                         While ctx.session.phase is "done" (the end card): false with
--                         Contract.nextMatch(seconds until the service rolls on); the framework would
--                         otherwise wipe the table for the newcomer and tell nobody who was dropped.
--                         Then refuse with words when deps.fit says no ("infected": decision D6),
--                         when the player holds no pass (pass.has; a pass is checked only here, so a
--                         match in progress always finishes: D5), or when all Rules.slots seats are
--                         people ("full"). Then THE ROSTER: if a match is on and a bot is seated,
--                         take one off with ctx.removeComputer (a bot on the side with fewer people;
--                         of those, the lowest seat) and the framework gives the person that seat,
--                         and Rules.join that bot's team.
--   joined(player, seat)  the person is seated (the first one has just started the match: "start"
--                         came first). Start their slot afresh (above), remember that the service
--                         has placed them, engine.ghost(body, true), put them in the audience now
--                         ("paintball_watch" and the splat pools). Their body goes to the spawn room
--                         by the "respawn" event Rules emitted, in the next step. Then balance (below),
--                         Bots.sync, and "paintball_watch" again to the whole audience (the roster
--                         changed).
--   command(player, verb, args)   the framework's own table verbs are not a player's to send in a
--                         match that starts itself, rolls on by itself and seats its own bots:
--                         "start", "again", "addai" and "mode" are refused with words. ("leave" is
--                         left to the framework.)
--   input(player, seat, verb, args)   always answered here (never nil).
--                         "reload" { t }: m = the magazine time of t (the fifth result of
--                         Clock.stamp(now, now, t, lastM, up)); Rules.reload(state, seat, m); false
--                         with words when it does nothing.
--                         "side" {}: honoured when the phase is "briefing" or the sender is tagged
--                         out, the sender has no ball in flight, and the other team has a bot (take
--                         the lowest seat): Rules.assign the sender to the other team and that bot to
--                         the sender's, Bots.sync, ctx.dirty(), "paintball_watch" to the audience.
--                         Otherwise false with Contract.textFor("side").
--   step(dt)              THE LOOP, below. Runs before the Session's own step.
--   event(e)              "start": a match begins. match += 1; Rules.tune(state, service.feel);
--                         Rules.sync(state, now); every splat, ball, pose history and Move buffer is
--                         dropped. PEOPLE KEEP THEIR SIDES: every seated person whose team at the end
--                         of the last match is remembered is put back on it (Rules.assign), in seat
--                         order, unless that team already has Rules.teamMax people. Everybody the
--                         service had placed who is no longer seated is put at arena.lobby. The
--                         audience is told (a new `match`). The framework then seats bots up to the
--                         Spec's fill, each on the smaller side (Rules.join); the next step balances.
--                         "left": a seat was left. A person: forget their slot's stream,
--                         engine.ghost(body, false), put their body at arena.lobby (if they still
--                         have one), forget that they were placed; while the match is on and a person
--                         remains, seat a bot at once (ctx.addComputer: it takes the vacated seat and
--                         its team). Bots.sync and "paintball_watch" to the audience either way.
--                         "done": the clock ran out; the framework shows Rules.result's card. Remember
--                         each seated person's team (for the next "start").
--                         "reset": the table was emptied (nobody left, only bots left, the end card
--                         timed out, a fault): everybody the service had placed is put at arena.lobby
--                         and un-ghosted, everything is dropped, the remembered sides are forgotten,
--                         "paintball_unwatch" to the audience.
--   state(player, seat)   Contract.Extras for that player's "state" message.
--   inPlay(player, body)  the framework's walk-away check, for an arena: true while the body is
--                         inside the arena volume (Arena.inVolume with 4 studs to spare), until the
--                         server has first placed it, and for TRUST.placeGrace after the server
--                         moved it. False takes the player off.
--   screen(view), sig(view)   the monitors: every part named Arena.MONITOR under hw (the lobby's,
--                         and the old sets on each floor: the arena lane's bake) shows the phase, the
--                         clock and both scores; idle, it shows the station's name.
--   prompt()              one action line for both prompts ("Paintball"): each label says the rest.
--   doneText(view)        the end banner: Result.text.
--   debug(...)            scripted outcomes for the engine check (tests/engine/PaintballFlow) and the
--                         playtest: "tag" (by, id); "end" (the clock runs out now); "tune" (key,
--                         value): service.feel = Contract.tuned(service.feel, key, value), in force
--                         from the next match, (false, words) for a bad key or value (written in the
--                         stub already).
-- THE ROSTER, AND BALANCE. A slot's team is its own (Rules, "teams"). The service changes who is on
-- which side in three ways only: it chooses WHICH bot gives its seat to a person who joins (above);
-- it trades a person and a bot on the "side" verb; it puts people back on their sides at "start".
-- BALANCE, after the fill at a start (in the next step) and after every seat taken or left: while
-- the two sides are not the same size, or either is under Rules.teamMin, and a seat is free:
-- ctx.addComputer() (the bot joins the smaller side). It never takes a bot off to balance.
-- ROLLING ON. While ctx.session.phase is "done": when Rules.endCardSecs of end card have passed
-- (ctx.session.doneEnds - ctx.now() <= Rules.endCardSpare), take every bot off (ctx.removeComputer)
-- and call ctx.again(). The people still seated are dealt seats 1, 2, 3 ... in their old order;
-- "start" puts them back on their sides and the fill and the balance rebuild the rest (never under
-- teamMin a side). If only bots are left the framework resets.
--
-- THE LOOP (step(dt), every server step; now = ctx.stamp())
--   0. Nothing at all unless hw is there and ctx.session.phase is "playing" or "done" (PB-15: an
--      idle arena costs nothing). Rules.sync(state, now): the model is slaved to the shared clock
--      (Rules, "time"). DURING THE END CARD ("done") people may still walk about and see each other:
--      of the steps below only 1, the silence of 2 (no idleness), 5 and 6 run, the bots stand where
--      they stood, nothing is fired (Rules refuses: the phase), and the roll into the next match is
--      watched for (above).
--   1. Rules.drain(state):
--      "phase"    ctx.dirty() (the view carries it).
--      "respawn"  place the slot at arena.spawns[team][spawn]. A person: place = Wire.nextPlace(place);
--                 engine.teleport (world: Arena.toWorld and Arena.yawToWorld with the place); the
--                 anchor is the spawn point, `moves` is emptied, the budget is full, crouch is 0; the
--                 slot is in play again. A bot: its pose is set and Bots.place called. Either way
--                 ctx.broadcast "paintball_respawn" { id, x, y, z, yaw, at, place (a bot: 0) }.
--      "reload"   a person's: ctx.send "paintball_reload" to that player alone. A bot's: nothing
--                 (everybody hears a reload from BIT.reload in the snapshots).
--      "tag"      nothing: the message went out where Rules.tag said yes (step 4).
--   2. People. SILENCE is measured from heardAt, and not at all while the slot is out or within
--      TRUST.placeGrace of a placement (a client sends nothing while out): after Clock.STALE_SECS the
--      slot may not fire ("stale"); after Clock.DROP_SECS ctx.leave(player, "dropped", its words).
--      IDLENESS, counted only while the phase is "live": a person whose accepted pose has stayed
--      within 0.5 studs and 0.05 rad (yaw and pitch) of the `idle` pose and who has fired no accepted
--      shot for Rules.idleSecs: ctx.leave(player, "idle", its words). A Move beyond those bounds, or
--      an accepted shot, restarts it; a placement by the server does not. A pose inside an
--      arena.exits room: ctx.leave(player, "exit", its words). Each arrives back as "left".
--   3. Bots.step(bots, state, poses, heard, now, dt): `heard` is every ball born, ball ended and tag
--      since the last tick (people's and bots'). The bots move their own poses. A "fire" command is
--      DROPPED unless its direction is within BOT.aimSlack of Body.look(pose.yaw, pose.pitch), the
--      bot's pose is in no spawn room, and Rules.fire(state, id, now) agrees; then the ball is born
--      now with no rewind. "reload" goes through Rules.reload; "say" out as "paintball_say".
--      Its cost is Stats.botsMs.
--   4. Balls (Stats.ballsMs): Projectiles.step against arena.sweep and, with Hit.body, against every
--      slot that is on, is on the other team from the ball (the ball keeps the team it was born with),
--      Rules.canBeHit(state, id, now), and whose REWOUND pose (its history at now - ball.rewind) is
--      not inside its own team's spawn room (Arena.inRoom, feet + 0.1). BEFORE a slot's history is
--      sampled it is passed over if its newest snapshot pose is further from the box round the ball's
--      step than Body.RADIUS + Body.speed(0, true, feel) x TRUST.speedTolerance x (Clock.MAX_REWIND
--      + Clock.MAX_LATE) sideways, or 2 x Arena.FLOOR_HEIGHT up or down: nothing that near could
--      have been there. A ball that ends on a body: Rules.tag(state, by, id, now, ball's birth); on
--      true, ctx.broadcast "paintball_tag" (the ball's id, the ENTRY point, state.scores, by's tags,
--      id's outs, at = id's outUntil), and from that moment the tagged person's Moves are dropped and
--      its pose held where it stood, until its respawn. NO ctx.dirty() for a tag. Every ball that
--      ends on something makes one Splat record (wall: point and face; body: Wire.toBody offset from
--      the rewound pose, yaw from the newest), kept in the pools (Wire, "two pools") and batched per
--      tick to the audience. Born balls go out as one Shot batch per tick (Wire.SHOTS_PER_MESSAGE at
--      most in a message).
--   5. Every 1 / Clock.SNAP_HZ seconds, the snapshot tick T = now. For every slot that is on:
--      a person   crouch = Body.crouchStep(crouch, the crouch bit of its newest Move, 1 / SNAP_HZ,
--                 feel); its pose is "the slot's pose at Clock.poseTime(up, T)" with that crouch
--                 fraction (while out: the pose it was tagged in, unchanged);
--      a bot      its pose as its brain left it (the brain eases its own crouch: never the service);
--      the bits   the client's or the brain's crouch, sprint and air, with Rules.bits(state, id, T)
--                 (out, safe, reload) and BIT.safe when the pose is inside its own team's spawn room.
--      The pose is quantised (Wire.quantPose), pushed into the slot's PoseHistory at T (x, y, z and
--      the crouch fraction), written to service.poses[id] (what the bots read) and sent
--      (Wire.encodeSnap with the match number) to the audience. THE HISTORY IS THE SNAPSHOT STREAM
--      (Clock): nothing else is ever pushed.
--   6. Every Clock.AUDIENCE_SECS: the audience. Of ctx.town.people(), whoever stands within
--      Arena.AUDIENCE_MARGIN of the arena volume (Arena.toLocal, Arena.inVolume), and everybody
--      seated, is in it: on coming in they get "paintball_watch" (ctx.send: the match number, who
--      holds which slot on which team, the feel) and both splat pools as one Splat batch; on going
--      out "paintball_unwatch". The streams go to the audience and to nobody else. "paintball_watch"
--      goes out again to all of it when the roster changes and when a match starts.
--      THE SWEEP, in the same pass: anybody of ctx.town.people() whose position is inside the arena
--      volume itself (no margin) and who is not seated here is put at arena.lobby (engine.teleport
--      of ctx.bodyOf(key)). That, with "start" and "reset", is what makes "nobody outside the match
--      is ever inside the arena" true whatever the framework did to the table.
--   Everything in the step that is not 3 or 4 is Stats.restMs. The shares are Contract.COST.
-- THE REMOTES (Wire; Shared/Net has checked shape and rate before the port hands a record over)
--   onMove   a person's pose (Contract, "who is trusted", is the rule; this is the order).
--            a. Not seated here, or the session is neither "playing" nor "done": dropped.
--            b. The slot has not been placed yet (place = 0), is out, or rec.place is not the slot's
--               place: dropped (Stats.movesDropped).
--            c. rec.t not later than the last accepted Move's t, later than now + TRUST.clockSlack, or
--               older than now - TRUST.moveAge: dropped (movesDropped).
--            d. Clock.observe(up, rec.t, now); heardAt = now.
--            e. Judge it against the anchor, first failure wins and names the `why`:
--               inside ("wall": outside the volume; arena.sweep of the point at Arena.CHEST above the
--               feet reports a box; inside the other team's spawn room), height ("wall"), walls
--               ("wall": Arena.clearPath(arena.sweep, anchor, this, at Arena.CHEST above the higher
--               feet point)), distance ("speed"), the body ("wall": further than TRUST.bodySlack
--               from engine.positionOf, when that is known).
--            f. Accepted (movesAccepted): it is the anchor, goes into `moves`, its horizontal step
--               leaves the budget; the idle check.
--            g. Refused (movesRefused): nothing changes. The TRUST.refusalsBeforeCorrect-th refusal
--               inside TRUST.refusalWindow is a CORRECTION (Stats.corrections): place =
--               Wire.nextPlace(place), engine.teleport to the anchor, `moves` emptied, the budget
--               full, ctx.send "paintball_correct" { x, y, z, yaw, why (the last refusal's), place }.
--   onFire   a click. Not seated here, or the session neither "playing" nor "done": dropped without a
--            word. Otherwise EVERY Fire gets one "paintball_ack" (ctx.send) carrying the slot's
--            magazine as it then stands, and `shot` becomes rec.shot. In order, the first failure
--            refuses (ok = false, its why; Stats.shotsRefused):
--            a. the slot is silent (step 2): "stale";
--            b. f, late, rewind, clamped, m = Clock.stamp(now, rec.vt, rec.ft, lastM, up.lag)
--               (clamped counts in Stats.rewindsClamped);
--            c. sprint: a Move in `moves` with BIT.sprint and t > f - Body.SPRINT_FIRE_DELAY +
--               MARGIN.sprint: "sprint";
--            d. the room: the slot's pose at f is inside a spawn room (either): "safe";
--            e. the origin (Contract, "the origin"; the eye is Body.eyePoint over the slot's pose at
--               f; "however far f lies past its newest Move" is max(0, f - that Move's t), costed at
--               Body.speed(crouch, false, feel)); a direction of no length: "origin";
--            f. Rules.fire(state, id, f, m): its why.
--            Accepted: the ball is born at f at the claimed origin with velocity = the unit direction
--            x feel.ballSpeed, the slot's team and that rewind; it is flown forward by `late` at
--            once (in steps of 1 / TICK_HZ, each against the bodies of its own moment); lastM = m;
--            its idleness restarts; the ack carries ok = true and the ball's id.
-- IN AND OUT OF A MATCH, AND THE TOWN. The player keeps possessing the body they walked in with the
-- whole time; the town's own systems go on outside and never reach in (the arena volume is sealed:
-- Arena). Joining moves that body to its team's spawn room; leaving (the framework's Leave, walking
-- into an exit, dropped, idle, the player gone, the body lost: each arrives as "left") moves it to
-- arena.lobby. BODIES IN A MATCH PASS THROUGH EACH OTHER (they pass through bots, which have no body,
-- and a hidden person would otherwise block a corridor a stud to one side of where their puppet is
-- drawn): engine.ghost(body, true) puts every part of a seated body in the collision group
-- Contract.COLLISION_GROUP, which does not collide with itself and collides with everything else as
-- the default group does; engine.ghost(body, false) puts the parts back in the group they were in.
-- First person is the client's own doing (Client/Minigames/Paintball/PaintballClient).
-- THE PASS (PB-12). `pass` is deps.pass, else the lane's own on ctx.town.charge(player,
-- Rules.passCents, "a paintball pass") (a stand-in that takes nothing until the town has a wallet;
-- honour a false and show its words): a pass runs Rules.passDays in-game days from deps.day(), and
-- until there is a profile it is remembered for as long as the server runs.
-- THE S18 CORE in Server/Paintball is this lane's to extend, keeping tests/unit/paintball_hitreg.spec green:
--   PoseHistory  gains a crouch channel beside x, y, z (same ring, same interpolation), so a crouched
--                body is judged crouched (PB-3); built with Clock.HISTORY_SECS at Clock.SNAP_HZ here.
--   Projectiles  tests the building through arena.sweep instead of scanning a box list and bodies
--                with Hit.body (the ball is its centre line, the contact is the ENTRY point and counts
--                only if nothing solid stands between it and the body's middle: Hit) instead of
--                Ballistics.segmentCapsule with the ball's radius added; takes the drop and the speed
--                from the match's feel and the ttl from Contract.Rules; keeps each ball's birth time
--                and team; can fly one new ball forward by `late` against the bodies of those past
--                moments; passes over a body by its newest pose before sampling it (step 4); clamps a
--                rewind to Clock.MAX_REWIND; reports the entry point.
--   Splats       two pools with one seq: the walls' ring of Rules.splatPool and a ring of
--                Rules.bodySplats for each slot; a slot's ring is emptied when its occupant changes,
--                both when the match does; the join batch is those rings, oldest first.
--   Layout, Harness  the S18 greybox and its hit-agreement harness: kept as the regression test of
--                the rewind, and given a condition that judges shots the contract's way (Clock.stamp
--                with `up`, history at SNAP_HZ, view time from Clock.viewTime, Hit.body) with the
--                95 % bar at 150 ms.
-- Interface: new(ctx, deps?) -> Service; port(net) -> Port; types Port, Engine, PassDesk, Deps, Stats,
--   Service. Service: hw; feel; join(player, via) -> (ok, why?); joined(player, seat, via);
--   command(player, verb, args) -> (handled, ok?, why?); input(player, seat, verb, args) -> (ok?,
--   why?); step(dt); event(e); state(player, seat) -> Extras?; inPlay(player, body) -> boolean;
--   screen(view); sig(view) -> any; prompt() -> (action?, object?); doneText(view) -> string?;
--   debug(...) -> (ok, why?); onMove(player, rec); onFire(player, rec); watching(player) -> boolean;
--   stats() -> Stats

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
type Feel = typeof(Contract.T.Feel)

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
	-- on: every part of the body into Contract.COLLISION_GROUP (bodies in a match pass through each
	-- other); off: back into the group each part was in. The real engine registers the group once.
	ghost: (body: any, on: boolean) -> (),
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
	feel: Feel?, -- the feel of the first match; default Contract.feel()
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
	movesDropped: number, -- a stale placement number, an out slot, a bad or old t
	shotsRefused: number,
	corrections: number,
	rewindsClamped: number, -- shots whose claimed rewind was outside the server's bounds
	stepMs: number, -- the last step's cost; its three shares (Contract.COST):
	ballsMs: number,
	botsMs: number,
	restMs: number,
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
	feel: Feel, -- the feel of the next match (the one in play keeps its own: state.feel)
	poses: { [number]: Pose }, -- every slot's pose as last put in a snapshot (a bot's: its present one), arena frame
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
		ghost = function(_body: any, _on: boolean) end,
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
		movesDropped = 0,
		shotsRefused = 0,
		corrections = 0,
		rewindsClamped = 0,
		stepMs = 0,
		ballsMs = 0,
		botsMs = 0,
		restMs = 0,
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
		feel = Contract.feel(d.feel :: any),
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
		return {
			match = self.match,
			bots = {},
			rounds = Contract.Rules.magazine,
			reloadAt = 0,
			shot = 0,
			feel = self.feel,
		}
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

	function service.debug(self: Service, ...: any): (boolean, string?)
		local what, key, value = ...
		if what == "tune" then
			-- one number of the next match's feel (the owner's playtest: a faster ball, a shorter reload)
			local feel, why = Contract.tuned(self.feel, tostring(key), value)
			if feel == nil then
				return false, why
			end
			self.feel = feel
			return true, nil
		end
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
