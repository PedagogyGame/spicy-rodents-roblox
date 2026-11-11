--!strict
-- ReplicatedStorage.Shared.Paintball.Contract
-- THE PAINTBALL CONTRACT (brief v2 §13, §14; checklist PB-1 to PB-15). Four lanes build paintball at
-- the same time and cannot talk to each other; everything they share is fixed here and in the four
-- modules beside this one, as code. FROZEN: no lane edits these files or changes a stub's exported
-- names and signatures; a lane that needs more adds a module of its own.
--   Contract  (this file) the rules, the teams, the phases, the match as others see it, the events a
--             match emits, the end card, the reasons a request is refused, who is trusted for what
--   Body      the player body: heights, hit shape, eye, speeds, crouch, look angles
--   Clock     the rates, the view time, how a shot is stamped and clamped (lag compensation)
--   Wire      every message on every remote: payload, direction, reliability, rate, bytes
--   Arena     the building as data: the frame, boxes, ramps, spawns, navigation, the ball test
-- The tested S18 core stays as it is and is built on:
--   Shared  Config      the six projectile and magazine numbers; Rules below reads them (frozen)
--           Ballistics  the ball's flight and the segment tests; the client's predicted ball, the
--                       server's ball and the bots' aim all use it (frozen)
--           Magazine    five shots, auto and manual reload; the client predicts with it, the match
--                       keeps the real one per slot (frozen)
--   Server  PoseHistory, Projectiles, Splats, Layout, Harness: the server lane's (see PaintballService)
--
-- THE FOUR LANES AND THEIR FILES (no file is in two lanes)
--   match-and-bots  Server/Paintball/Match.luau, Bots.luau (+ new files named Match*.luau, Bot*.luau
--                   there), tests/unit/paintball_match*.spec.luau, paintball_bots*.spec.luau
--   arena           Shared/Paintball/ArenaData.luau (+ new Arena?*.luau beside it, never Arena.luau),
--                   tools/bake/paintball.luau and tools/bake/paintball/, tests/unit/paintball_arena*.spec.luau
--   server          Server/Paintball/PaintballService.luau, PoseHistory, Projectiles, Splats, Layout,
--                   Harness (+ any other new file there), tests/unit/paintball_hitreg.spec.luau,
--                   paintball_server*.spec.luau, tests/isolated/paintball_service.luau,
--                   tests/engine/Paintball.luau, tools/cloud/tasks/paintball_*.luau
--   client          Client/Paintball/ (all of it), tests/unit/paintball_client*.spec.luau,
--                   tests/isolated/paintball_client*.luau
-- Nobody edits: this folder's frozen files, Net/Schemas.luau, tests/unit/paintball_contract.spec.luau,
-- Boot/Game.luau, Main.client.luau, the project files, or anything under Minigames/ (another agent is
-- reshaping it). Joining the service and the client to the boot is done once, at the end.
--
-- WHO IS TRUSTED FOR WHAT (TRUST below holds the numbers)
--   The client moves its own body: it is the possessed R15 Humanoid body the player walked in with,
--   network-owned by that client, moved by the stock controls. SEND_HZ times a second it reports the
--   pose (Wire Move). The server accepts a pose only if it is inside the arena, on or just above a
--   walking surface, not through a wall since the last accepted pose (arena.sweep at chest height) and
--   within the distance its speed allows (a budget that fills at Body.speed x speedTolerance and holds
--   speedWindow seconds); it also checks the report against where the replicated body really is
--   (bodySlack). A refused pose is dropped and the last accepted one stands; after
--   refusalsBeforeCorrect in a second the server puts the real body back on it and says so ("correct").
--   The client says where it looks, whether it wants to crouch and that it clicked. The server alone
--   decides: the crouch fraction and so the hit shape (Body.crouchStep), whether a click was a shot
--   (phase, out, protection, sprint, the magazine at the clamped fire time, the origin within
--   originSlack of the server's own eye point for that body and not through a wall from it), where the
--   ball goes, what it hits, every tag, every point, every respawn, every splat, the clock and the pass.
--   The client predicts its own ball and magazine at once and draws them; a hit marker, a hit sound, a
--   score and a splat on a body come only on the server's word.
-- HOW TO IMPORT THE CONTRACT FROM SERVER OR CLIENT CODE, so that the type check really holds you to it.
--   The repo's usual line, `local X = Import.shared("P") :: typeof(require("../../shared/P"))`, leaves X
--   untyped under tools/typecheck (the on-disk path does not resolve through the sourcemap and a cast
--   from `any` hides it), so a wrong field name or a wrong payload would pass. In paintball code write
--   the type as an ANNOTATION with the instance path, which does resolve:
--     local Contract: typeof(require(game.ReplicatedStorage.Shared.Paintball.Contract)) =
--         Import.shared("Paintball/Contract")
--     type Pose = typeof(Contract.T.Pose)
--   and for types alone:
--     type Arena = typeof(require(game.ReplicatedStorage.Shared.Paintball.Arena).T.Arena)
--   (typeof never runs its require, so Lune is untouched.) An exported type cannot be named through
--   the shim, which is what the T tables of Contract, Arena and Wire are for. Inside one root, and in
--   the specs, plain requires carry everything.
-- Interface: VERSION; Rules; TEAMS; PHASES; TRUST; WHY, textFor(why) -> string, passShort(need, have);
--   LINES; types Phase, Pose, SlotView, MatchView, CardRow, Award, EndCard, Event; T (type witnesses)

local Config = require("./Config")

export type Phase = "idle" | "briefing" | "live" | "ended"

-- A body's pose in the arena frame (Arena, Body): feet point, look angles, crouch fraction, and the
-- Wire.BIT flags.
export type Pose = { x: number, y: number, z: number, yaw: number, pitch: number, crouch: number, bits: number }

-- One of the 2 x size slots of a match, as every client sees it. A slot's id (1..Rules.slots) is the
-- body's id everywhere: in snapshots, shots, splats and tags. A bot and a person are the same kind of
-- slot; when a person joins they take a bot's slot (same id, same team) and when they leave a bot
-- takes it back.
export type SlotView = {
	id: number,
	team: number, -- 1 or 2 (TEAMS)
	name: string,
	bot: boolean,
	userId: number, -- 0 for a bot
	tags: number, -- opponents this slot has tagged out, this match
	outs: number, -- times it was tagged out
}

-- The match as every client sees it (Wire State kinds "joined", "watch" and "match").
export type MatchView = {
	matchId: number, -- counts up; splats and tallies belong to one match
	phase: Phase,
	endsAt: number, -- server time the phase ends (0 while idle); clients count down from it themselves
	size: number, -- players a side, Rules.teamMin..teamMax
	scores: { number }, -- { team 1, team 2 }: tags made
	slots: { SlotView },
}

export type CardRow = {
	id: number,
	name: string,
	team: number,
	bot: boolean,
	tags: number,
	outs: number,
	shots: number,
	hits: number,
	accuracy: number, -- hits / shots, 0..1 (0 with no shots)
}
export type Award = { title: string, id: number, name: string }
export type EndCard = {
	matchId: number,
	winner: number, -- 1, 2, or 0 for a draw
	scores: { number },
	rows: { CardRow }, -- most tags first
	awards: { Award }, -- "Most Paint Wasted" and friends (the WBLW sports bulletin)
	nextAt: number, -- server time the next match's briefing starts
}

-- What a match (Server/Paintball/Match, pure) tells the service that runs it. One flat record; the
-- fields a kind uses:
--   phase    phase, at (= endsAt), matchId          the phase changed
--   roster                                          slots changed (join, leave, bot fill, resize)
--   tag      by, id (the one tagged), at (= server time it respawns)
--   respawn  id, team, spawn (index into arena.spawns[team]), at (= server time protection ends)
--   reload   id, at (= server time the magazine is full again)
--   end      card
export type Event = {
	kind: "phase" | "roster" | "tag" | "respawn" | "reload" | "end",
	phase: Phase?,
	matchId: number?,
	id: number?,
	by: number?,
	team: number?,
	spawn: number?,
	at: number?,
	card: EndCard?,
}

local Contract = {}

Contract.VERSION = 1

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
	slots = 16, -- 2 x teamMax: the most bodies in a match, and the highest slot id
	respawnSecs = 4, -- tagged out for this long ("3 to 5 s"), then back in the spawn room
	protectSecs = 2, -- after a respawn: cannot be hit, cannot fire
	friendlyFire = false, -- a ball passes through a team-mate
	-- PB-7, PB-14: briefing in the spawn rooms, the match, the end card, the next match
	briefingSecs = 10,
	matchSecs = 480,
	endCardSecs = 15,
	-- PB-12: the pass
	passCents = 20,
	passDays = 5, -- in-game days
})

-- Decision D4: orange against teal; never blood red.
Contract.TEAMS = table.freeze({
	table.freeze({ id = 1, key = "orange", name = "Orange", color = table.freeze({ 255, 140, 26 }) }),
	table.freeze({ id = 2, key = "teal", name = "Teal", color = table.freeze({ 0, 170, 170 }) }),
})

--   idle      nobody is in: no clock, no bots, nothing is sent
--   briefing  bodies stand in their spawn rooms; nobody can fire or be hit; the controls card is up
--   live      the match
--   ended     the end card; nobody can fire or be hit; then a briefing again if anyone is still in
Contract.PHASES = table.freeze({ "idle", "briefing", "live", "ended" })

-- The numbers behind "who is trusted for what" (see the header).
Contract.TRUST = table.freeze({
	speedTolerance = 1.15, -- on Body.speed, for the distance budget
	speedWindow = 0.5, -- seconds of distance the budget holds (absorbs bunched packets)
	jumpSlack = 1.0, -- a pose may be this far above ground + Body.JUMP_HEIGHT
	bodySlack = 8, -- studs between a reported pose and the replicated body before it is refused
	originSlack = 4, -- studs (horizontal) between a shot's origin and the server's eye point for that body
	originSlackY = 1.5, -- and vertically, beyond the standing and crouched eye heights and a jump
	refusalsBeforeCorrect = 3, -- refused poses inside one second before the body is put back
})

-- Why a request was refused: the code on the wire, and the words shown (the server may send better
-- words as `text`; "poor" is replaced by passShort).
Contract.WHY = table.freeze({
	full = "The match is full.",
	pass = "You need a pass. The pass desk sells one for 20c.",
	poor = "You need 20c.",
	person = "Paintball is for people only.",
	infected = "See a doctor first.",
	already = "You are already in the match.",
	away = "Come to the pass desk first.",
	phase = "Not now.",
	out = "You are tagged out.",
	safe = "You cannot fire yet.",
	sprint = "You cannot fire while sprinting.",
	empty = "Reloading.",
	fast = "Too fast.",
	origin = "That shot did not come from you.",
	stale = "Connection trouble.",
	left = "You left the match.",
	dropped = "You stopped responding and were taken out of the match.",
	closed = "The arena is closed.",
	has_pass = "You already have a pass.",
})

function Contract.textFor(why: string): string
	return (Contract.WHY :: { [string]: string })[why] or "Not now."
end

-- PB-12: "You need 20c; you have 7c".
function Contract.passShort(need: number, have: number): string
	return `You need {need}c; you have {have}c`
end

-- What a bot may call out (Wire State "say"): a code on the wire, the words on screen.
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
	Event: Event,
}

return Contract
