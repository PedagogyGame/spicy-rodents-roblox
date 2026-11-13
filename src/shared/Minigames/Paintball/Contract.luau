--!strict
-- ReplicatedStorage.Shared.Minigames.Paintball.Contract
-- THE PAINTBALL CONTRACT (brief v2 §13, §14; checklist PB-1 to PB-15). Four lanes build paintball at
-- the same time and cannot talk to each other; everything they share is fixed here and in the modules
-- beside this one, as code. FROZEN: no lane edits a frozen file or changes a stub's exported names and
-- signatures; a lane that needs more adds a module of its own.
--   Contract  (this file) the rules' numbers, the feel table, the teams, the phases, the match as others
--             see it, the events a match emits, the end card, the reasons a request is refused, who is
--             trusted, the margins between a client's gate and the server's, the cost shares
--   Body      the player body: heights, hit shape, eye, speeds, crouch, look angles
--   Hit       THE test of a ball against a body, used by the server, the shooter's client and the bots
--   Clock     the rates, the view time, how a shot is stamped and clamped (lag compensation)
--   Wire      every message: the five remotes of paintball's own and its kinds on Minigame.State
--   Arena     the building as data: the frame, boxes, ramps, spawns, navigation, the ball test
--   Spec      paintball's line in the minigame registry: flow, session, verbs, stations (frozen too)
-- The tested S18 core stays where it is and is built on:
--   Shared/Paintball  Config      the S18 numbers; FEEL and Rules below take their defaults from it, and
--                                 NOTHING ELSE OF THE MATCH READS IT (the feel of a match is the match's
--                                 own table; the S18 harness and its spec go on reading Config)
--                     Ballistics  the ball's flight and the box test; the client's predicted ball, the
--                                 server's ball and the bots' aim all use it (frozen)
--                     Magazine    five shots, auto and manual reload; the client predicts with it, the
--                                 match model keeps the real one per slot (frozen)
--   Server/Paintball  PoseHistory, Projectiles, Splats, Layout, Harness: the server lane's (what it does
--                     with each is in Server/Minigames/Paintball/PaintballService)
--
-- WHERE PAINTBALL SITS IN THE MINIGAME FRAMEWORK (Shared/Minigames/Games; Server/Minigames/ServerGame;
-- Client/Minigames/ClientGame). It is a game of the registry like every other, flow "match":
--   the framework gives   the station and its prompt (at the arena door in the lobby) and a second
--                         prompt at the pass desk (`joins`); people only; seats (a seat IS a slot of the
--                         match, 1..16) and leaving (the Leave button, walking out, being taken off);
--                         computer players for the bots (the Spec's `computers` and `fill`); late
--                         joining; the "state" message once a second and when the roster or the phase
--                         changes (MatchView); the end card and the roll into the next match
--                         (ctx.again); the world scoreboard hook (the monitors); the client
--                         controller's life, ctx.pace for crouch and sprint, ctx.controls for the legs,
--                         ctx.camera for the one-frame turn of the look, the game's keys
--   paintball adds        the match model as the Spec's rules (Rules), the arena, and FIVE REMOTES OF ITS
--                         OWN for what the framework's wire cannot carry (Wire says why): the move
--                         stream with stance and look, the click, the snapshots, the balls, the splats.
--                         Every other message (a tag, a respawn, a reload, the shooter's ack, a
--                         correction, a call-out, the audience coming and going) is a kind on
--                         Minigame.State, sent with ctx.send / ctx.broadcast like any game's.
--   how a session maps    Session "idle": nobody is in, nothing is stepped or sent. A join starts the
--                         game at once (lobbySeconds = 0): Session "playing" is the match, whose own
--                         phases are "briefing" (bodies in their spawn rooms, the controls card, nobody
--                         fires) then "live". When the clock runs out Rules.result() ends it: Session
--                         "done" is phase "ended", the end card. The service calls ctx.again() when
--                         Rules.endCardSecs of it have passed and the next match begins with everyone
--                         still seated; if only bots are left the framework resets the table. NOBODY
--                         JOINS DURING THE END CARD (the framework would wipe the table for the newcomer
--                         without telling the service whom it dropped): the door refuses with
--                         Contract.nextMatch(seconds) and the newcomer joins the match that follows.
--
-- THE FOUR LANES AND THEIR FILES (no file is in two lanes; "new files" are ones the lane creates; the
-- checklist ids are the ones each lane answers for)
--   match-and-bots  PB-2, PB-6, PB-7, PB-10, PB-14 (the clock and the phases).
--                   Shared/Minigames/Paintball/Rules.luau and new files beside it named Match*.luau;
--                   Server/Minigames/Paintball/Bots.luau and new files beside it named Bot*.luau;
--                   tools/games/paintball/bots/ (calibration printouts); the specs
--                   tests/unit/paintball_match*.spec.luau and paintball_bots*.spec.luau
--   arena           PB-5, and the navigation PB-10 walks on.
--                   Shared/Minigames/Paintball/ArenaData.luau and new files beside it named
--                   ArenaData*.luau or ArenaGrid*.luau; tools/bake/games/Paintball.luau (the registry's
--                   bake stub) and tools/games/paintball/arena/; tests/unit/paintball_arena*.spec.luau
--   server          PB-3, PB-4, PB-6 (the roster), PB-11, PB-12, PB-14 (in and out), PB-15.
--                   Server/Minigames/Games/Paintball.luau (the registry's server stub),
--                   Server/Minigames/Paintball/PaintballService.luau and any new file there not named
--                   Bot*.luau; Server/Paintball/ (PoseHistory, Projectiles, Splats, Layout, Harness);
--                   tests/unit/paintball_hitreg.spec.luau and paintball_server*.spec.luau,
--                   tests/isolated/paintball_server*.luau, tests/engine/PaintballFlow.luau,
--                   tools/cloud/tasks/paintball_*.luau, tools/games/paintball/server/
--   client          PB-1, PB-2 (the prediction and the pips), PB-4 (the paint), PB-7 (HUD, scoreboard,
--                   end card), PB-8, PB-9, the controls and the rating; brief §14 (first person).
--                   Client/Minigames/Games/Paintball.luau (the registry's client stub) and all of
--                   Client/Minigames/Paintball/; tests/unit/paintball_client*.spec.luau,
--                   tests/isolated/paintball_client*.luau, tools/games/paintball/client/
--   (PB-13, garb, and decision D7, paint that fades on a player outside, come after the mechanics:
--   no lane builds them now and nothing here depends on them. The gamepad's "mild aim slow-down" of the
--   checklist is struck for this round: the look is the stock first-person camera's and no setting a
--   script may write is known to scale a gamepad's look; nobody builds on it.)
-- Nobody edits: the frozen files (this folder's Contract, Body, Hit, Clock, Wire, Arena, Spec;
-- Shared/Paintball's Config, Ballistics, Magazine), Net/Schemas.luau, tests/unit/paintball_contract.spec.luau,
-- tests/lib/PaintballRig.luau, tests/isolated/paintball_contract.luau, the note on paintball in the
-- header of Minigames/Games.luau, and everything the framework's recipe says a game never
-- edits (the four registries, MinigameService, MinigameClient, MinigameUI, Session, Human.luau,
-- InputMap, Boot/Game, Main.client, tests/lib, tools/ci.sh, Config/Tunables). Nothing needs joining to
-- the boot at the end: the registries already hold paintball's four lines, and the game appears in
-- the world the day the arena lane's bake has a `build`.
--
-- THE DECISIONS, AND WHERE EACH IS WRITTEN DOWN
--    0 the framework for everything but the stream; five
--      remotes of paintball's own for the stream            Wire (the reasons), above (the split)
--    1 a person's movement: client moves, server checks     below, "who is trusted for what"
--    2 crouch on a Humanoid body: eye, hit shape and pace
--      only; nothing about the Humanoid's collision         Body
--    3 bots: seats of the Session held by the framework's
--      computer players, pure poses on the server, no body
--      in the world; every screen draws bots and people
--      alike as puppets from the snapshot stream            Clock, Server/Minigames/Paintball/Bots
--    4 first person: the client's controller sets its own
--      body's CameraZone attribute while the game is open;
--      the camera's CFrame is written only inside a
--      ctx.camera hold of one frame, to turn the look to
--      the yaw of a RESPAWN (a paintball_correct never
--      turns the look: its yaw is the last pose the server
--      took, up to a second old)                            Client/Minigames/Paintball/PaintballClient
--    5 in and out: the player keeps the body they walked in
--      with; put in a spawn room on joining, in the lobby
--      on leaving; the town goes on outside; bodies in a
--      match pass through each other                        Server/Minigames/Paintball/PaintballService
--    6 who sees what: the AUDIENCE (anyone the town lists
--      within Arena.AUDIENCE_MARGIN of the arena volume,
--      which takes in the lobby) is sent the streams and
--      draws the match; a player further off is sent
--      nothing, and sees a closed building                  Server/Minigames/Paintball/PaintballService
--    7 splats: reliable records in two pools (the walls',
--      and each body's own); a body's splat is an offset in
--      that body's frame and rides on the puppet            Wire
--    8 what is sent how often, and the bytes                Wire, Clock
--    9 a client that stops sending: holds its pose and
--      cannot fire after 0.5 s; after 5 s it is taken off
--      and a bot takes the seat; so is a player who has
--      not moved, looked or fired for Rules.idleSecs        Clock
--   10 a ball is its centre line, against walls and bodies
--      alike; a body is hit where the line ENTERS its
--      shape, and only if no wall stands between that
--      point and the body's middle                          Hit
--   11 a team is the slot's own (SlotView.team), dealt by
--      seat parity and changed by the "side" verb; people
--      who played together stay together                    Rules, PaintballService ("the roster")
--   12 the spawn room: on the middle storey, two ways out;
--      inside your own you cannot be hit and cannot fire;
--      the other team's is shut to you                      Arena, PaintballService
--   13 the feel numbers are one table the match holds
--      (FEEL below), told to every client, tunable between
--      matches                                              below, Rules.tune
--   14 every gate the server keeps is looser than the
--      client's by a named margin, so an honest client is
--      never refused                                        MARGIN below
--
-- WHO IS TRUSTED FOR WHAT (TRUST below holds the numbers; PaintballService, "the remotes", holds the
-- procedure step by step)
--   The client moves its own body: it is the possessed R15 Humanoid body the player walked in with,
--   network-owned by that client, moved by the stock controls at the pace the framework's ctx.pace
--   sets. SEND_HZ times a second it reports the pose (Wire Move: when it was sampled, the feet point,
--   the look, the crouch and sprint bits, and the number of the last placement it obeyed).
--   The server accepts a pose only if all of this holds:
--     placement  its `place` is the slot's current placement number. A Move that names an older one was
--                sampled before the client had been moved (a respawn, a correction): it is DROPPED, not
--                refused and not counted, and the pose the server placed stands until one matches. A
--                slot that is tagged out has its Moves dropped the same way, from the tag to the respawn.
--     time       its t is later than the last accepted Move's, not after now + clockSlack and not older
--                than moveAge (else dropped: the stream is unreliable and unordered).
--     inside     in the arena volume, not inside a box, and not in the other team's spawn room.
--     height     on or above the walking surface under it (arena.ground; groundSlack below it at most).
--                SUPPORTED means no higher than that surface + Body.JUMP_HEIGHT + jumpSlack. A pose that
--                is not supported is falling: it is accepted while it does not rise (riseSlack) and has
--                not been unsupported, by the Moves' own t, for longer than fallSecs. So stepping off
--                a stair or a landing and dropping is free, and flying or hovering is not.
--     walls      Arena.clearPath from the last accepted pose: the straight line between the two at
--                chest height, or either of the two L-shaped paths (x then z, z then x), is clear. One
--                or two lost Moves round a corner leave the straight line through the corner and the L
--                the body walked clear. (A refused pose never becomes the anchor: the next is tested
--                from the last ACCEPTED one. Accepting "any pose in the open after a refusal" was
--                considered and rejected: it lets a body through any wall for the price of one pose.)
--     distance   a budget of HORIZONTAL distance: each accepted Move adds Body.speed(crouch fraction,
--                its own sprint bit, feel) x speedTolerance x (its t - the last accepted t, at most
--                moveGap); the budget holds at most speedWindow seconds' worth at that rate; the
--                horizontal step from the last accepted pose is taken from it and refused if it is not
--                there. Time is the Moves' own t, never arrival, so jitter costs nothing.
--     the body   within bodySlack of where the replicated body really is.
--   A refused pose is dropped and the last accepted one stands; after refusalsBeforeCorrect inside
--   refusalWindow the server puts the real body back on it, bumps the placement number and says so
--   ("paintball_correct").
--   THE SPRINT BIT IS THE FACT, THE BUDGET IS THE ENFORCEMENT. The server never reads "sprinting" from
--   measured speed. A Move without the bit is held to walking pace by the budget; a Move with it buys
--   sprint pace and closes the marker (below). A client that hides the bit simply walks.
--   The client says where it looks, whether it wants to crouch and that it clicked. The server alone
--   decides: the crouch fraction and so the hit shape (Body.crouchStep from the crouch bit); whether a
--   click was a shot; where the ball goes, what it hits, every tag, every point, every respawn, every
--   splat, the clock and the pass. A click is a shot when, at the clamped fire time f (Clock.stamp):
--     the match   Rules.fire(state, id, f, m) agrees: phase, out and protection judged AT f (a slot
--                 tagged at T may still fire with f < T: a click made before the tag counts), the
--                 magazine judged at m;
--     sprint      no accepted Move carrying BIT.sprint has t later than f - Body.SPRINT_FIRE_DELAY +
--                 MARGIN.sprint;
--     the room    the slot's own pose at f is not inside a spawn room;
--     the origin  within originSlack (horizontal) of the eye over the slot's own pose at f, plus
--                 walking pace x however far f lies past its newest Move; vertically between Body.eye
--                 of the server's crouch fraction and Body.eye of where the newest Move's crouch bit is
--                 heading (0 or 1), give or take originSlackY, and Body.JUMP_HEIGHT more while the
--                 newest Move says BIT.air; and Arena.clearPath from that eye to the origin at the
--                 origin's height.
--   "The slot's own pose at f" is read from the last few accepted Moves by their own t: the straight
--   line between the two either side of f, held at the newest.
--   The client predicts its own ball and magazine at once and draws them, and ends its own ball on the
--   first opposing puppet it enters (Hit.body against the drawn pose, the body the server rewinds to)
--   with a small puff; the hit marker, the hit sound, the score and the splat on a body come only on
--   the server's word ("paintball_tag").
--
-- HOW TO IMPORT THE CONTRACT FROM SERVER OR CLIENT CODE, so that the type check really holds you to it.
--   The repo's usual line, `local X = Import.shared("P") :: typeof(require("../../shared/P"))`, leaves X
--   untyped under tools/typecheck (the on-disk path does not resolve through the sourcemap and a cast
--   from `any` hides it), so a wrong field name or a wrong payload would pass. In paintball code write
--   the type as an ANNOTATION with the instance path, which does resolve:
--     local Contract: typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Contract)) =
--         Import.shared("Minigames/Paintball/Contract")
--     type Pose = typeof(Contract.T.Pose)
--   and for types alone:
--     type Arena = typeof(require(game.ReplicatedStorage.Shared.Minigames.Paintball.Arena).T.Arena)
--   (typeof never runs its require, so Lune is untouched.) An exported type cannot be named through
--   the shim, which is what the T tables of Contract, Arena, Wire and Rules are for. Inside one root,
--   and in the specs, plain requires carry everything.
-- Interface: VERSION; GAME, SITE, STATION, DESK; Rules; FEEL, FEEL_KEYS, FEEL_RANGE, feel(over?) -> Feel,
--   tuned(feel, key, value) -> (Feel?, why?); TEAMS, teamOf(slot); PHASES; TRUST; MARGIN; COST; BOT; BOTS;
--   COLLISION_GROUP; WHY, textFor(why) -> string, passShort(need, have), nextMatch(seconds); LINES; types
--   Phase, Feel, Pose, SlotView, MatchView, CardRow, Award, EndCard, Result, Event, Extras; T (type witnesses)

local Config = require("../../Paintball/Config")

-- The match's own phases, inside the Session's "playing" and "done" (see the header).
export type Phase = "briefing" | "live" | "ended"

-- THE FEEL OF A MATCH (decision 13): the numbers the owner will want to turn at the playtest, as one
-- table that a match holds from its start to its end (Rules.State.feel). The server tells it to every
-- client (in "paintball_watch" and in the Extras of "state"); the client's predicted ball and magazine,
-- each slot's real magazine, the server's balls, the speed budget and the bots all read THE MATCH'S
-- table, never FEEL or Config directly. A change (the service's debug("tune", key, value); see
-- PaintballService) takes effect at the next match, so no two screens ever disagree inside one.
export type Feel = {
	ballSpeed: number, -- studs/s
	ballDrop: number, -- studs/s^2
	fireInterval: number, -- seconds between balls
	reloadSecs: number,
	sprintMult: number, -- sprint speed over walking speed
	crouchSecs: number, -- standing to fully crouched, and back
	respawnSecs: number, -- tagged out for this long
	protectSecs: number, -- after a respawn: cannot be hit, cannot fire
}

-- A body's pose in the arena frame (Arena, Body): feet point, look angles, crouch fraction, and the
-- Wire.BIT flags.
export type Pose = { x: number, y: number, z: number, yaw: number, pitch: number, crouch: number, bits: number }

-- One slot of a match, as every player sees it. A slot's id is its SEAT in the framework's Session
-- (1..Rules.slots) and the body's id everywhere: in snapshots, shots, splats and tags. A bot and a
-- person are the same kind of slot: its name is the Session's (view.seats[id]), and whether a bot
-- holds it is in the service's Extras. A slot that is not `on` is an empty seat.
-- ITS TEAM IS ITS OWN (decision 11): `team` here, in "paintball_watch" and in Rules.Slot is the only
-- source; nobody works a team out from the id. (teamOf below is only how Rules deals a first seat.)
export type SlotView = {
	id: number,
	team: number, -- 1 or 2
	on: boolean, -- somebody (a person or a bot) holds the seat
	tags: number, -- opponents this slot has tagged out, this match
	outs: number, -- times it was tagged out
	shots: number,
	hits: number, -- balls of its own that tagged somebody
}

-- The match as the seated see it: Rules.view(state), which the framework sends as `view.game` of its
-- "state" message, once a second and whenever the service says the roster or the phase changed
-- (ctx.dirty). A tag does NOT send it: "paintball_tag" carries the new scores and tallies, and the
-- next once-a-second "state" puts right whatever a client missed.
export type MatchView = {
	phase: Phase,
	endsAt: number, -- the shared clock (Clock) when the phase ends; clients count down from it themselves
	size: number, -- players a side now, Rules.teamMin..teamMax
	scores: { number }, -- { team 1, team 2 }: tags made
	slots: { SlotView }, -- by id, no gaps: 1..the highest seat taken so far
}

export type CardRow = {
	id: number,
	team: number,
	tags: number,
	outs: number,
	shots: number,
	hits: number,
	accuracy: number, -- hits / shots, 0..1 (0 with no shots)
}
export type Award = { title: string, id: number } -- "Most Paint Wasted" and friends (the WBLW sports bulletin)
export type EndCard = {
	winner: number, -- 1, 2, or 0 for a draw
	scores: { number },
	rows: { CardRow }, -- every slot that is on, most tags first
	awards: { Award },
}

-- Rules.result(state) once the clock has run out (a Minigame.Result: the framework reads done, scores,
-- winners and text; the client's end card reads `card`, with names from view.seats).
export type Result = {
	done: boolean,
	scores: { [number]: number }, -- by seat: that slot's tags
	winners: { number }, -- the seats of the winning team that are on; empty for a draw
	text: string, -- the end banner: "Orange wins 14 - 9" / "A draw, 9 all"
	card: EndCard,
}

-- What the match model (Rules, pure) tells the service that runs it; Rules.drain(state) hands them
-- over, oldest first. One flat record; every time is on the shared clock. The fields a kind uses:
--   phase    phase, at (= endsAt)                      the phase changed
--   tag      by, id (the one tagged), at (= when it respawns)
--   respawn  id, team, spawn (index into arena.spawns[team]), at (= when its protection ends): the
--            slot is to stand at that spawn point now, with a full magazine (the briefing, a late join,
--            back from being out, a change of side)
--   reload   id, at (= when the magazine is full again)
-- (Seats taken and left are the framework's to tell: Table.joined, Table.event "left".)
export type Event = {
	kind: "phase" | "tag" | "respawn" | "reload",
	phase: Phase?,
	id: number?,
	by: number?,
	team: number?,
	spawn: number?,
	at: number?,
}

-- What the service's Table adds to each player's "state" message (ServerGame.Table.state), beside the
-- framework's own fields (view, you = your slot id).
--   THE PIPS. The client's magazine is its own prediction. It is put right from the server only by
--   "paintball_ack" (rounds as they stood after shot `shot`: the client shows that minus the clicks it
--   has sent since), by "paintball_respawn" for itself (full, no reload running) and, ONCE, by the
--   first "state" after it joined. `rounds`, `reloadAt` and `shot` here are for that first state: a
--   client with clicks in flight never applies them (its pips would flick back and forth).
export type Extras = {
	match: number, -- counts up on this server, 1 for the first match: splats and tallies belong to one match
	bots: { boolean }, -- by slot id, as long as view.game.slots: a bot holds that seat
	rounds: number, -- your magazine, as the server has it
	reloadAt: number, -- the shared clock when your reload ends; 0 when you are not reloading
	shot: number, -- the counter of your last click the server judged (0: none yet)
	feel: Feel, -- this match's feel
}

local Contract = {}

Contract.VERSION = 3

-- The registry's names (Shared/Minigames/Paintball/Spec).
Contract.GAME = "paintball"
Contract.SITE = "f3_tv_station" -- the venue of generated/Expansion the arena stands on
Contract.STATION = "paintball_arena" -- the station: its prompt is at Arena.GATE, the arena door
Contract.DESK = "paintball_desk" -- the second prompt, at Arena.DESK: it `joins` STATION and sells the pass

-- The fixed numbers of the owner's minimum bar (brief v2 §13; Tunables paintball.* and economy.*). The
-- contract spec pins each against the checklist. (What the owner may turn at the playtest is FEEL.)
Contract.Rules = table.freeze({
	-- PB-1: a ball that has hit nothing is gone after this long; and how big it is DRAWN (a ball is
	-- tested as its centre line against walls and bodies alike: Hit)
	ballTtl = Config.projectile.ttl, -- 1.5 s
	ballRadius = Config.projectile.radius, -- 0.25
	-- PB-2: five shots; one click, one ball; reload by itself when empty, or on R when not full
	magazine = Config.magazine, -- 5
	-- PB-4: splats stay for the match, the oldest replaced: on the walls the newest splatPool of the
	-- building, on a body the newest bodySplats of that slot
	splatPool = Config.splatPool, -- 400
	bodySplats = 24,
	-- PB-6: team deathmatch 4v4 to 8v8, bots fill; one hit tags you out
	teamMin = 4,
	teamMax = 8,
	slots = 16, -- 2 x teamMax: the seats of the Session, and the highest slot id
	friendlyFire = false, -- a ball passes through a team-mate
	-- PB-7, PB-14: briefing in the spawn rooms, the match, the end card, the next match
	briefingSecs = 10,
	matchSecs = 480,
	endCardSecs = 15, -- of end card before the service rolls into the next match (ctx.again)
	-- the Session's doneSeconds is endCardSecs + this: the service rolls on with this much of it left, so
	-- the table never resets first and the card's own countdown ("starts in N s") ends on 1
	endCardSpare = 1,
	-- a person who has not moved, turned or fired for this long of "live" is taken off ("idle") and a
	-- bot takes the seat (decision 9)
	idleSecs = 60,
	-- PB-12: the pass
	passCents = 20,
	passDays = 5, -- in-game days
})

-- The default feel (PB-1, PB-2, PB-6, PB-9), and what each number may be turned to. The ranges keep
-- the rest of the contract true: the slowest ball still crosses the arena inside ballTtl, the fastest
-- fire still fits Paintball.Fire's rate limit, the fastest sprint still fits the framework's pace.
Contract.FEEL = table.freeze({
	ballSpeed = Config.projectile.speed, -- 90: 45 studs in half a second
	ballDrop = Config.projectile.drop, -- 9.8: 1.2 studs low over those 45
	fireInterval = Config.fireInterval, -- 0.25
	reloadSecs = Config.reloadSecs, -- 1.6
	sprintMult = 1.4, -- Tunables paintball.sprintMult: 23.8 studs/s
	crouchSecs = 0.2,
	respawnSecs = 4, -- "3 to 5 s"
	protectSecs = 2,
}) :: Feel

Contract.FEEL_KEYS = table.freeze({
	"ballSpeed",
	"ballDrop",
	"fireInterval",
	"reloadSecs",
	"sprintMult",
	"crouchSecs",
	"respawnSecs",
	"protectSecs",
})

Contract.FEEL_RANGE = table.freeze({
	ballSpeed = table.freeze({ 80, 200 }),
	ballDrop = table.freeze({ 0, 40 }),
	fireInterval = table.freeze({ 0.15, 1 }),
	reloadSecs = table.freeze({ 0.5, 4 }),
	sprintMult = table.freeze({ 1, 1.6 }),
	crouchSecs = table.freeze({ 0.05, 0.5 }),
	respawnSecs = table.freeze({ 1, 10 }),
	protectSecs = table.freeze({ 0, 5 }),
}) :: { [string]: { number } }

-- A fresh feel table: the defaults, with any of `over` that is a known key and a finite number, held
-- inside its range.
function Contract.feel(over: { [string]: any }?): Feel
	local out: { [string]: number } = {}
	for _, key in Contract.FEEL_KEYS do
		local v = (Contract.FEEL :: any)[key] :: number
		local given = if over then over[key] else nil
		if type(given) == "number" and given == given then
			local range = Contract.FEEL_RANGE[key]
			v = math.clamp(given, range[1], range[2])
		end
		out[key] = v
	end
	return (out :: any) :: Feel
end

-- One number of a feel table changed: a new table, or nil and the reason in words.
function Contract.tuned(feel: Feel, key: string, value: any): (Feel?, string?)
	local range = Contract.FEEL_RANGE[key]
	if range == nil then
		return nil, `no such feel number '{key}' (one of {table.concat(Contract.FEEL_KEYS, ", ")})`
	end
	if type(value) ~= "number" or value ~= value or value < range[1] or value > range[2] then
		return nil, `{key} must be a number from {range[1]} to {range[2]}`
	end
	local out = Contract.feel(feel :: any)
	local open = out :: any
	open[key] = value
	return out, nil
end

-- Decision D4: orange against teal; never blood red.
Contract.TEAMS = table.freeze({
	table.freeze({ id = 1, key = "orange", name = "Orange", color = table.freeze({ 255, 140, 26 }) }),
	table.freeze({ id = 2, key = "teal", name = "Teal", color = table.freeze({ 0, 170, 170 }) }),
})

-- How Rules deals a seat that has no team yet when the sides are level: odd seats team 1, even seats
-- team 2. NOT a slot's team: that is the slot's own (SlotView.team) and may have been changed since.
function Contract.teamOf(slot: number): number
	return if slot % 2 == 1 then 1 else 2
end

--   briefing  bodies stand in their spawn rooms; nobody can fire or be hit; the controls card is up
--   live      the match
--   ended     the end card (the Session's "done"); nobody can fire or be hit; then the next briefing
Contract.PHASES = table.freeze({ "briefing", "live", "ended" })

-- The numbers behind "who is trusted for what" (see the header).
Contract.TRUST = table.freeze({
	speedTolerance = 1.15, -- on Body.speed, for the distance budget
	speedWindow = 0.5, -- seconds of distance the budget holds
	moveGap = 0.15, -- the most seconds one Move adds to the budget, however far its t lies past the last
	moveAge = 1.0, -- a Move whose t is older than this is dropped
	clockSlack = 0.05, -- a client's stamp may lead the server's clock by this (the clocks agree to a few ms)
	groundSlack = 0.5, -- a pose may be this far below the walking surface under it
	jumpSlack = 1.0, -- supported: no higher than ground + Body.JUMP_HEIGHT + this
	riseSlack = 0.1, -- an unsupported pose may be this much higher than the last accepted one
	fallSecs = 1.5, -- the longest a body may stay unsupported (the whole building is a 0.85 s fall)
	bodySlack = 8, -- studs between a reported pose and the replicated body before it is refused
	originSlack = 1.0, -- studs (horizontal) between a shot's origin and the eye over the slot's pose at f
	originSlackY = 0.4, -- and vertically, beyond the eye heights the crouch allows
	refusalsBeforeCorrect = 3, -- refused poses inside refusalWindow before the body is put back
	refusalWindow = 1.0,
	placeGrace = 1.0, -- seconds after the server moved a body in which the framework's inPlay says yes unasked
})
-- SETTLED AT THE JOIN: the server lane's readings of the move rules above, each one rule in
-- Server/Minigames/Paintball/Stream (whose header gives the reasons), are the contract's:
--   for the honest player  a body has a footprint up to a stud past a floor's edge; an unsupported pose
--                          may be a hop above the surface last stood on; the body rule holds only the
--                          sideways distance while falling and for 0.25 s after, and is not kept for
--                          placeGrace after a placement; silence is counted from a placement as well as
--                          from a Move; a click later than its own delay explains is judged at its own
--                          stamp for where it left from, no further back than Stream.lateWindow (at most
--                          Clock.MAG_LATE), while the sprint, the spawn rooms and the stance are held to f
--                          as well
--   against the liar       a fall must come down at a quarter of gravity or faster from hop height (not
--                          walk level for fallSecs); the distance budget is EMPTY after a correction; a
--                          correction anchored in mid-air puts the body on the walking surface under it;
--                          the 'side' verb is honoured once in 3 s a person, and only in the briefing or
--                          while tagged out in the first minute of live play (a later change would make a
--                          winner of a loser on the end card)
--   one way of two         'sprint' counts only Moves stamped at or before f; the origin's allowance for
--                          a body in the air also applies below the eye; at 'start' a side's teamMax
--                          counts the people going to it
--   idleness               a respawn moves the idle pose to the placed pose and does not restart the count;
--                          a correction moves neither; while a slot is out no Move is judged, so nothing
--                          the body does while out counts as being there (the client's warning follows it)

-- Decision 14: where the client and the server judge the same thing from different knowledge, the
-- client's gate is the stricter by a named margin, so an honest client's shot is never refused after
-- its ball was drawn. The CLIENT keeps the left-hand rule, the SERVER the right-hand one.
--   sprint  the client fires no sooner than Body.SPRINT_FIRE_DELAY after the frame its sprint ended
--           (it clears BIT.sprint in that frame); the server refuses only a shot with a sprint Move
--           stamped later than f - SPRINT_FIRE_DELAY + sprint.
--   room    the client does not fire while its eye is inside a spawn room or within `room` studs of
--           one (Arena.inRoom with that margin); the server refuses only inside the room itself.
--   gate    the client waits this long past any time the server named (the end of protection in
--           "paintball_respawn", the phase's endsAt) before it acts on it; the server judges at f.
--   click   a fire press that only the fire interval, a reload with no more than this left, or the
--           sprint delay objects to is HELD and fired the instant it may (ft = that instant): clicking
--           faster than the marker never loses a ball. Only one click is held; a later one replaces it.
Contract.MARGIN = table.freeze({
	sprint = 0.05, -- seconds (one send interval)
	room = 2.0, -- studs
	gate = 0.02, -- seconds
	click = 0.2, -- seconds
})

-- PB-15, shared out: the arena adds under 1.5 ms a server frame beside the full town. Each share is
-- measured by the lane that owns it and reported in PaintballService.Stats.
--   balls   Projectiles.step with `atBalls` balls in flight against 16 bodies (the server lane)
--   bots    Bots.step with `atBots` bots, their sight checks spread over ticks (the match-and-bots lane)
--   rest    everything else in the service's step: moves, snapshots, events, the audience
-- Each share is a MEAN per tick. In the engine (tests/engine/PaintballFlow) the whole step's mean and 95th
-- centile are held under totalMs and its worst under a quarter of a frame. A single route search of the
-- bots costs about 0.2 ms on the real building, so a tick where several re-route at once runs past the
-- bots' mean: the bots' Report gives the tick 99 in 100 come under (0.10 ms with 8 bots), not pinned here.
Contract.COST = table.freeze({
	ballsMs = 0.4,
	atBalls = 48,
	botsMs = 0.5,
	atBots = 15,
	restMs = 0.3,
	totalMs = 1.5,
})

-- What makes a bot fair to play against (Server/Minigames/Paintball/Bots says how each is used).
Contract.BOT = table.freeze({
	reactMin = 0.25, -- seconds between a bot seeing or hearing something and acting on it
	reactMax = 0.45,
	sightHalf = math.rad(60), -- it sees inside this angle either side of where it looks
	-- studs: a ball of the other side's that passes or lands this near is heard (a team-mate's tells a bot
	-- nothing it needs), and so is a team-mate tagged; the service hands them over with a ball's "ended"
	-- before its "tag" in the same tick
	hear = 6,
	turn = 2 * math.pi, -- radians a second: the fastest its yaw and its pitch change
	aimSlack = math.rad(3), -- a fire command further than this from the bot's own look is dropped
	sightHz = 10, -- line-of-sight checks a bot a second, at most
	faced = 0.25, -- seconds a bot's puppet should have faced a player before a ball that tags them
})

-- The engine collision group every seated person's body is put in while seated (it does not collide
-- with itself): bodies in a match pass through each other, as they pass through the bots (decision 5).
Contract.COLLISION_GROUP = "PaintballBody"

-- The bots, as the Spec's computer players (the framework seats them and shows each as
-- "<name> (computer)"; `skill` rides on the key the service is handed: 0.5 is the average bot of
-- PB-10, whom a fair player beats about three times in five). Sixteen, so one is always free to seat.
Contract.BOTS = table.freeze({
	table.freeze({ name = "Rusty", skill = 0.5 }),
	table.freeze({ name = "Static", skill = 0.5 }),
	table.freeze({ name = "Gaffer", skill = 0.6 }),
	table.freeze({ name = "Boom Mike", skill = 0.4 }),
	table.freeze({ name = "Cue Card", skill = 0.5 }),
	table.freeze({ name = "Test Pattern", skill = 0.4 }),
	table.freeze({ name = "Rerun", skill = 0.5 }),
	table.freeze({ name = "Teleprompter", skill = 0.6 }),
	table.freeze({ name = "Dead Air", skill = 0.5 }),
	table.freeze({ name = "Laugh Track", skill = 0.4 }),
	table.freeze({ name = "Weather Wally", skill = 0.5 }),
	table.freeze({ name = "Antenna", skill = 0.6 }),
	table.freeze({ name = "Key Grip", skill = 0.5 }),
	table.freeze({ name = "Snow", skill = 0.4 }),
	table.freeze({ name = "Sign-Off", skill = 0.5 }),
	table.freeze({ name = "Vertical Hold", skill = 0.6 }),
})

-- Why a request was refused: a code (the `why` of an ack, a correction, a left), and the words shown.
-- A refusal that goes through the framework (a join, a pass, a reload, a change of side) is sent as
-- these words.
Contract.WHY = table.freeze({
	full = "The match is full of people: wait for the next one.",
	pass = "You need a pass. The pass desk sells one for 20c.",
	infected = "See a doctor first.",
	closed = "The arena is closed.",
	soon = "The next match is about to start.", -- (the door during the end card: nextMatch below has the seconds)
	has_pass = "You already have a pass.",
	bought = "Pass bought: five days of paintball and both lounges.",
	phase = "Not now.",
	out = "You are tagged out.",
	safe = "You cannot fire yet.",
	sprint = "You cannot fire while sprinting.",
	empty = "Reloading.",
	fast = "Too fast.",
	origin = "That shot did not come from you.",
	stale = "Connection trouble.",
	wall = "You cannot go that way.",
	speed = "Too fast.", -- a correction: the distance budget ran out
	exit = "You walked out of the match.",
	dropped = "You stopped responding and were taken out of the match.",
	idle = "You stood still too long and were taken out of the match.",
	side = "You can change sides in the briefing or while tagged out, when the other side has a bot to trade with.",
})

function Contract.textFor(why: string): string
	return (Contract.WHY :: { [string]: string })[why] or "Not now."
end

-- PB-12: "You need 20c; you have 7c".
function Contract.passShort(need: number, have: number): string
	return `You need {need}c; you have {have}c`
end

-- The door during the end card: "The next match starts in 7 s."
function Contract.nextMatch(seconds: number): string
	return `The next match starts in {math.max(1, math.ceil(seconds))} s.`
end

-- What a bot may call out ("paintball_say"): a code on the wire, the words on screen.
Contract.LINES = table.freeze({
	reloading = "Reloading!",
	floor = "They are on %d!", -- the floor, 1..5
	tagged = "Got one!",
	out = "I am out!",
	cover = "Covering!",
})

-- Type witnesses (see HOW TO IMPORT in the header): each exported type is also a value that is nil at
-- run time, so that another root can name it with typeof.
Contract.T = ({} :: any) :: {
	Phase: Phase,
	Feel: Feel,
	Pose: Pose,
	SlotView: SlotView,
	MatchView: MatchView,
	CardRow: CardRow,
	Award: Award,
	EndCard: EndCard,
	Result: Result,
	Event: Event,
	Extras: Extras,
}

return Contract
