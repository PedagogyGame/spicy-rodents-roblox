--!strict
-- ReplicatedStorage.Shared.Minigames.Paintball.Contract
-- THE PAINTBALL CONTRACT (brief v2 §13, §14; checklist PB-1 to PB-15). Four lanes build paintball at
-- the same time and cannot talk to each other; everything they share is fixed here and in the modules
-- beside this one, as code. FROZEN: no lane edits a frozen file or changes a stub's exported names and
-- signatures; a lane that needs more adds a module of its own.
--   Contract  (this file) the rules' numbers, the teams, the phases, the match as others see it, the
--             events a match emits, the end card, the reasons a request is refused, who is trusted
--   Body      the player body: heights, hit shape, eye, speeds, crouch, look angles
--   Clock     the rates, the view time, how a shot is stamped and clamped (lag compensation)
--   Wire      every message: the five remotes of paintball's own and its kinds on Minigame.State
--   Arena     the building as data: the frame, boxes, ramps, spawns, navigation, the ball test
--   Spec      paintball's line in the minigame registry: flow, session, verbs, stations (frozen too)
-- The tested S18 core stays where it is and is built on:
--   Shared/Paintball  Config      the six projectile and magazine numbers; Rules below reads them (frozen)
--                     Ballistics  the ball's flight and the segment tests; the client's predicted ball,
--                                 the server's ball and the bots' aim all use it (frozen)
--                     Magazine    five shots, auto and manual reload; the client predicts with it, the
--                                 match model keeps the real one per slot (frozen)
--   Server/Paintball  PoseHistory, Projectiles, Splats, Layout, Harness: the server lane's (what it does
--                     with each is in Server/Minigames/Paintball/PaintballService)
--
-- WHERE PAINTBALL SITS IN THE MINIGAME FRAMEWORK (Shared/Minigames/Games; Server/Minigames/ServerGame;
-- Client/Minigames/ClientGame). It is a game of the registry like every other, flow "match":
--   the framework gives   the station and its prompt ("Join the match", at the arena door in the lobby)
--                         and a second prompt at the pass desk (`joins`); people only; seats (a seat IS a
--                         slot of the match, 1..16) and leaving (the Leave button, walking out, being
--                         taken off); computer players for the bots (the Spec's `computers` and `fill`);
--                         late joining; the "state" message once a second and when the match changes
--                         (the roster, the scores, the clock: MatchView); the end card and the roll into
--                         the next match (ctx.again); the world scoreboard hook (the lobby's monitor);
--                         the client controller's life, ctx.pace for crouch and sprint, the game's keys
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
--                         still seated; if only bots are left the framework resets the table.
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
--   no lane builds them now and nothing here depends on them.)
-- Nobody edits: the frozen files (this folder's Contract, Body, Clock, Wire, Arena, Spec; Shared/Paintball's
-- Config, Ballistics, Magazine), Net/Schemas.luau, tests/unit/paintball_contract.spec.luau,
-- tests/lib/PaintballRig.luau, tests/isolated/paintball_contract.luau, the note on paintball in the
-- header of Minigames/Games.luau, and everything the framework's recipe says a game never
-- edits (the four registries, MinigameService, MinigameClient, MinigameUI, Session, Human.luau,
-- InputMap, Boot/Game, Main.client, tests/lib, tools/ci.sh, Config/Tunables). Nothing needs joining to
-- the boot at the end: the registries already hold paintball's four lines, and the game appears in
-- the world the day the arena lane's bake has a `build`.
--
-- THE DECISIONS, AND WHERE EACH IS WRITTEN DOWN
--   0 the framework for everything but the stream; five
--     remotes of paintball's own for the stream            Wire (the reasons), above (the split)
--   1 a person's movement: client moves, server checks     below, "who is trusted for what"
--   2 crouch on a Humanoid body: eye, hit shape and pace
--     only; nothing about the Humanoid's collision         Body
--   3 bots: seats of the Session held by the framework's
--     computer players, pure poses on the server, no body
--     in the world; every screen draws bots and people
--     alike as puppets from the snapshot stream            Clock, Server/Minigames/Paintball/Bots
--   4 first person: the client's controller sets its own
--     body's CameraZone attribute while the game is open;
--     the existing camera code does the rest               Client/Minigames/Games/Paintball
--   5 in and out: the player keeps the body they walked in
--     with; put in a spawn room on joining, in the lobby
--     on leaving; the town goes on outside                 Server/Minigames/Paintball/PaintballService
--   6 who sees what: the AUDIENCE (anyone the town lists
--     within Arena.AUDIENCE_MARGIN of the arena volume,
--     which takes in the lobby) is sent the streams and
--     draws the match; a player further off is sent
--     nothing, and sees a closed building                  Server/Minigames/Paintball/PaintballService
--   7 splats: reliable records; a body's splat is an offset
--     in that body's frame and rides on the puppet         Wire
--   8 what is sent how often, and the bytes                Wire, Clock
--   9 a client that stops sending: holds its pose and
--     cannot fire after 0.5 s; after 5 s it is taken off
--     and a bot takes the seat                             Clock
--
-- WHO IS TRUSTED FOR WHAT (TRUST below holds the numbers)
--   The client moves its own body: it is the possessed R15 Humanoid body the player walked in with,
--   network-owned by that client, moved by the stock controls at the pace the framework's ctx.pace
--   sets. SEND_HZ times a second it reports the pose (Wire Move). The server accepts a pose only if it
--   is inside the arena, on or just above a walking surface, not through a wall since the last accepted
--   pose (arena.sweep at chest height) and within the distance its speed allows (a budget that fills at
--   Body.speed x speedTolerance and holds speedWindow seconds); it also checks the report against where
--   the replicated body really is (bodySlack). A refused pose is dropped and the last accepted one
--   stands; after refusalsBeforeCorrect in a second the server puts the real body back on it and says
--   so ("paintball_correct"). Nothing is refused for placeGrace seconds after the server itself moved
--   the body (a spawn, a respawn, a correction).
--   The client says where it looks, whether it wants to crouch and that it clicked. The server alone
--   decides: the crouch fraction and so the hit shape (Body.crouchStep), whether a click was a shot
--   (phase, out, protection, sprint, the magazine at the clamped fire time, the origin within
--   originSlack of the server's own eye point for that body and not through a wall from it), where the
--   ball goes, what it hits, every tag, every point, every respawn, every splat, the clock and the pass.
--   The client predicts its own ball and magazine at once and draws them; a hit marker, a hit sound, a
--   score and a splat on a body come only on the server's word.
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
-- Interface: VERSION; GAME, SITE, STATION, DESK; Rules; TEAMS, teamOf(slot); PHASES; TRUST; BOTS; WHY,
--   textFor(why) -> string, passShort(need, have); LINES; types Phase, Pose, SlotView, MatchView,
--   CardRow, Award, EndCard, Result, Event, Extras; T (type witnesses)

local Config = require("../../Paintball/Config")

-- The match's own phases, inside the Session's "playing" and "done" (see the header).
export type Phase = "briefing" | "live" | "ended"

-- A body's pose in the arena frame (Arena, Body): feet point, look angles, crouch fraction, and the
-- Wire.BIT flags.
export type Pose = { x: number, y: number, z: number, yaw: number, pitch: number, crouch: number, bits: number }

-- One slot of a match, as every player sees it. A slot's id is its SEAT in the framework's Session
-- (1..Rules.slots) and the body's id everywhere: in snapshots, shots, splats and tags. Its team is
-- teamOf(id). A bot and a person are the same kind of slot: its name is the Session's (view.seats[id]),
-- and whether a bot holds it is in the service's Extras. A slot that is not `on` is an empty seat.
export type SlotView = {
	id: number,
	team: number, -- teamOf(id)
	on: boolean, -- somebody (a person or a bot) holds the seat
	tags: number, -- opponents this slot has tagged out, this match
	outs: number, -- times it was tagged out
	shots: number,
	hits: number, -- balls of its own that tagged somebody
}

-- The match as the seated see it: Rules.view(state), which the framework sends as `view.game` of its
-- "state" message, once a second and whenever the service says the match changed (ctx.dirty).
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
--            slot is to stand at that spawn point now (the briefing, a late join, back from being out)
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
export type Extras = {
	match: number, -- counts up on this server, 1 for the first match: splats and tallies belong to one match
	bots: { boolean }, -- by slot id, as long as view.game.slots: a bot holds that seat
	rounds: number, -- your magazine, as the server has it
	reloadAt: number, -- the shared clock when your reload ends; 0 when you are not reloading
}

local Contract = {}

Contract.VERSION = 2

-- The registry's names (Shared/Minigames/Paintball/Spec).
Contract.GAME = "paintball"
Contract.SITE = "f3_tv_station" -- the venue of generated/Expansion the arena stands on
Contract.STATION = "paintball_arena" -- the station: its prompt is at Arena.GATE, "Join the match"
Contract.DESK = "paintball_desk" -- the second prompt, at Arena.DESK: it `joins` STATION and sells the pass

-- The numbers of the owner's minimum bar (brief v2 §13; Tunables paintball.* and economy.*). The
-- contract spec pins each against the checklist.
Contract.Rules = table.freeze({
	-- PB-1: a ball that travels and drops a little (45 studs in half a second, 1.2 studs low)
	ballSpeed = Config.projectile.speed, -- 90 studs/s
	ballDrop = Config.projectile.drop, -- 9.8 studs/s^2
	ballTtl = Config.projectile.ttl, -- 1.5 s: a ball that has hit nothing is gone
	ballRadius = Config.projectile.radius, -- 0.25
	-- PB-2: five shots; one click, one ball; reload by itself when empty, or on R when not full
	magazine = Config.magazine, -- 5
	fireInterval = Config.fireInterval, -- 0.25 s
	reloadSecs = Config.reloadSecs, -- 1.6 s
	-- PB-4: splats stay for the match, the oldest replaced
	splatPool = Config.splatPool, -- 400
	-- PB-6: team deathmatch 4v4 to 8v8, bots fill; one hit tags you out
	teamMin = 4,
	teamMax = 8,
	slots = 16, -- 2 x teamMax: the seats of the Session, and the highest slot id
	respawnSecs = 4, -- tagged out for this long ("3 to 5 s"), then back in the spawn room
	protectSecs = 2, -- after a respawn: cannot be hit, cannot fire
	friendlyFire = false, -- a ball passes through a team-mate
	-- PB-7, PB-14: briefing in the spawn rooms, the match, the end card, the next match
	briefingSecs = 10,
	matchSecs = 480,
	endCardSecs = 15, -- of end card before the service rolls into the next match (ctx.again)
	endCardSpare = 3, -- the Session's doneSeconds is endCardSecs + this, so the table never resets first
	-- PB-12: the pass
	passCents = 20,
	passDays = 5, -- in-game days
})

-- Decision D4: orange against teal; never blood red.
Contract.TEAMS = table.freeze({
	table.freeze({ id = 1, key = "orange", name = "Orange", color = table.freeze({ 255, 140, 26 }) }),
	table.freeze({ id = 2, key = "teal", name = "Teal", color = table.freeze({ 0, 170, 170 }) }),
})

-- A slot's team: odd seats are team 1, even seats team 2. The service keeps the sides even and the
-- people spread by choosing WHICH seat a bot gives up or takes (PaintballService, "the roster").
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
	speedWindow = 0.5, -- seconds of distance the budget holds (absorbs bunched packets)
	jumpSlack = 1.0, -- a pose may be this far above ground + Body.JUMP_HEIGHT
	bodySlack = 8, -- studs between a reported pose and the replicated body before it is refused
	originSlack = 4, -- studs (horizontal) between a shot's origin and the server's eye point for that body
	originSlackY = 1.5, -- and vertically, beyond the standing and crouched eye heights and a jump
	refusalsBeforeCorrect = 3, -- refused poses inside one second before the body is put back
	placeGrace = 1.0, -- seconds after the server moved a body in which no pose of it is refused
})

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
-- A refusal that goes through the framework (a join, a pass, a reload) is sent as these words.
Contract.WHY = table.freeze({
	full = "The match is full of people: wait for the next one.",
	pass = "You need a pass. The pass desk sells one for 20c.",
	infected = "See a doctor first.",
	closed = "The arena is closed.",
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
	exit = "You walked out of the match.",
	dropped = "You stopped responding and were taken out of the match.",
})

function Contract.textFor(why: string): string
	return (Contract.WHY :: { [string]: string })[why] or "Not now."
end

-- PB-12: "You need 20c; you have 7c".
function Contract.passShort(need: number, have: number): string
	return `You need {need}c; you have {have}c`
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
