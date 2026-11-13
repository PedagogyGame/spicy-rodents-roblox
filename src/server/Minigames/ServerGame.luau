--!strict
-- ServerScriptService.Server.Minigames.ServerGame
-- What a minigame's server half looks like to MinigameService (the registry is Server/Minigames/ServerGames; the
-- game's line in Shared/Minigames/Games says the rest). A ServerGame is { game, new(ctx) -> Table }: the service
-- calls new() once per station and from then on talks to the Table it returns. Every member of a Table is
-- optional; a game with no Table at all still works if its rules need nothing but inputs (the service applies
-- a seated player's verbs to the Session itself).
-- The Ctx is the Table's whole view of the service: its station, its Session, where it stands, its seeded
-- stream, who is seated, and how to speak (send / broadcast / everyone add `station` to a payload that lacks it).
-- Two clocks, never mixed: ctx.now() is the service's own (seconds of stepping since boot; for durations on the
-- server: a thinking pause, a countdown); ctx.stamp() is the clock clients share (workspace:GetServerTimeNow;
-- the client's Ctx.stamp reads the same one), the only one an input stamped by a client may be judged against
-- (which pose a hitter was seeing, when a swing met the ball). A history kept on now() and read with a
-- client's stamp is wrong by the server's uptime.
-- ctx.town is what a game may ask of the rest of the town (the Town type below). Every member is always there;
-- what is behind it depends on the build: people() lists everyone with a body in the game itself (in a bare
-- test: whoever is seated); body() lends a townsperson to stand in for a computer player and returns nil while
-- there is nobody to lend (draw the computer on the clients from your script then, as the ball is); charge()
-- takes money from the player's wallet: in the game it is the town's (Server/Economy/Credits: wallet.spend,
-- wired in Boot/Game), so it returns (true, "Paid 20c for a pass. You have S$2.80.") or (false, "You need 20c;
-- you have 7c.") and the words can be shown as they are; only a bare test's service, given no wallet, says yes
-- to everything and takes nothing. `pass` is the town's ONE timed pass (the paintball arena and both lounges
-- read the same one): in the game it is the wallet's (wallet.pass: has, buy, left, untilDay, words, offer). A
-- game that sells or checks the pass (paintball's desk) uses ctx.town.pass and NEVER a ledger of its own, or a
-- pass bought at its desk would not open the lounges and one bought at a lounge door would not open the
-- arena; a service given none keeps a stand-in for as long as it runs, charged through its own charge(), so a
-- bare test still has a desk that sells. best() keeps a personal best for as long as the server runs until
-- there is a profile to keep it in.
-- Computer players: the Spec names them; ctx.addComputer(name?) seats one (by name, else the next one not at
-- this table) and returns ok, why, key. After the start it works only in a game whose rules say
-- def.lateJoin = true (with rules.join). ctx.removeComputer(key) takes one off (the rules' gone() hears it; a
-- person who joins next is given the vacated seat). ctx.again() starts the next game with whoever is still
-- seated, from the end card, exactly as the Play again button does.
-- A Table must never take the other games down: built on a site whose model lacks its furniture it exposes
-- hw = nil, does nothing in step and sends nothing; it sends nothing to everyone while nobody is seated. The
-- service protects itself all the same (a new() or step() that throws puts that one station out of order).
-- The Table's hooks, in the order the service uses them:
--   hw            the raw hardware (kept as station.hw; tests and the engine checks reach it)
--   join          before a player is seated: (false, why) refuses with words; may clear the table first.
--                 `via` is the def of the station whose prompt was pressed: the Table's own, or a station that
--                 `joins` it (the far side of the net)
--   joined        after the player has been told "joined" (a one-press machine acts here)
--   command       verbs that work in any phase, asked before the service's own (leave, start, again, addai,
--                 mode): return handled, ok, why
--   input         a seated player's verb while a game is on (after the turn gate when flow is "turns"):
--                 return ok, why; nil = "That does not work at this game"
--   step          every server step, before the Session's own step
--   busy          true pauses the turn clock (the ball is rolling, the dart is in the air)
--   event         what happened at the table: the Session's events (start, turn, timeout, skipped, removed,
--                 done, reset) plus "left" (a seated player went; why = "turn" if it was their go). "reset" also
--                 comes when the table empties or only computers are left: put the hardware to rest
--   computer      a computer player's go: return nil (could not act: asked again next step), 0 (acted: the
--                 thinking pause starts again) or seconds until its next action
--   screen        redraw the world scoreboard (only called when sig or the session's own signature changed)
--   sig           what else the world scoreboard shows (anything JSON-friendly)
--   state         extra fields for a player's "state" message (bowling: ready)
--   prompt        the ProximityPrompt's two lines, when the Spec's words are not enough
--   doneText      the end banner ("" = say nothing; nil = the service's own "X wins!")
--   inPlay        is this seated player still at the game? (replaces the walk-away radius: an arena)
--   debug         a scripted outcome for the engine checks (MinigameService:debug(stationId, ...))
--   debugName     the older name its scripted outcome also answers to ("roll": MinigameService:debugRoll;
--                 "dart": debugDart). Those refuse at any station whose Table does not say that name
-- Interface: types Place, StationDef, Event, Person, Town, Ctx, Table, ServerGame; num(v, default) -> number (a
--   finite number from a client's argument, or the default)

-- (A type cannot be named across roots (Import gives values), so the shared shapes are written out again here:
-- Shared/Minigames/GameSpec.Place and .StationDef, Shared/Minigames/Session.Event. Spec and Session are `any`.)
export type Place = { x: number, z: number, floorY: number, yaw: number }
export type StationDef = {
	id: string,
	game: string,
	label: string,
	site: string,
	x: number,
	y: number,
	d: number,
	index: number?,
	variant: string?,
	reach: number?,
	joins: string?,
}
export type Event = { kind: string, seat: number?, key: any?, why: string? }

-- Somebody in the town with a body: a player (key = the Player) or a test's stub; world studs.
export type Person = { key: any, name: string, x: number, y: number, z: number, [string]: any }
-- The town's one timed pass, as Server/Economy/Credits' wallet.pass has it.
export type Pass = {
	has: (player: any) -> boolean,
	buy: (player: any) -> (boolean, string), -- (true, "Pass bought: ...") or (false, the words to show)
	left: (player: any) -> number, -- in-game days (0 without one)
	untilDay: (player: any) -> number?, -- the in-game day it runs out
	words: (player: any) -> string, -- "4.2 in-game days left (about 50 minutes)" or "No pass"
	offer: () -> (number, number, string), -- cents, in-game days, "A pass is 20c for five in-game days of ..."
}
export type Town = {
	people: () -> { Person }, -- everyone with a body, wherever they are (a loose ball, a near-only show)
	body: (name: string, cframe: CFrame) -> Model?, -- a townsperson lent to stand in for a computer (nil: none yet)
	release: (model: Model) -> (), -- hand a lent body back
	charge: (player: any, cents: number, why: string) -> (boolean, string?), -- the wallet: ok, and words to show
	pass: Pass, -- the town's one timed pass (paintball and both lounges): never keep another
	-- a personal best: hand in a value (lower = true when less is better), get the best so far; nil value reads
	best: (player: any, key: string, value: number?, lower: boolean?) -> number?,
}

export type Ctx = {
	station: StationDef,
	spec: any, -- Shared/Minigames/GameSpec.Spec
	session: any, -- Shared/Minigames/Session.Session
	place: Place, -- the site's frame (AlleyLayout.toWorld(place, X, Y, D))
	root: Instance?, -- the site's baked model under Workspace.Attractions (nil in a bare test)
	anchor: Vector3, -- the station's prompt, world
	rng: any, -- Util/Rng: this station's seeded stream
	opts: { [string]: any }, -- the service's options (tunnels, animals, knock, instantRack, ...)
	net: any?, -- Shared/Net. NOT for a game's own remotes: a game speaks through send / broadcast / everyone
	town: Town, -- the rest of the town (always there; see the header for what stands behind each member)
	now: () -> number, -- the service clock, seconds (durations on the server; never compared with a client's stamp)
	stamp: () -> number, -- the clock clients share (the client's Ctx.stamp): what a stamped input is judged against
	seated: () -> { any }, -- the keys at the table now (players, PlayerLike stubs, computers)
	seatOf: (key: any) -> number?,
	nameOf: (seat: number) -> string,
	bodyOf: (key: any) -> Model?,
	send: (player: any, payload: { [string]: any }) -> (),
	broadcast: (payload: { [string]: any }) -> (), -- to the seated
	everyone: (payload: { [string]: any }) -> (), -- to every client (watchers too) and every seated stub
	apply: (key: any, verb: string, args: { any }?) -> (boolean, string?), -- Session.apply: key's input, or "server"
	server: (verb: string, args: { any }?, seat: number?) -> (boolean, string?), -- a server verb for a seat (default: the turn's, else 1)
	touch: () -> (), -- restart the turn clock
	dirty: () -> (), -- the state changed: send it this step
	join: (player: any) -> (boolean, string?), -- as if the player pressed the prompt
	leave: (player: any, why: string?, text: string?) -> (),
	addComputer: (name: string?) -> (boolean, string?, any?), -- ok, why, the computer's key
	removeComputer: (key: any) -> boolean,
	again: () -> (boolean, string?), -- the next game with whoever is still seated (from the end card)
}

export type Table = {
	hw: any?,
	join: ((self: any, player: any, via: StationDef) -> (boolean, string?))?,
	joined: ((self: any, player: any, seat: number?, via: StationDef) -> ())?,
	command: ((self: any, player: any, verb: string, args: { any }) -> (boolean, boolean?, string?))?,
	input: ((self: any, player: any, seat: number, verb: string, args: { any }) -> (boolean?, string?))?,
	step: ((self: any, dt: number) -> ())?,
	busy: ((self: any) -> boolean)?,
	event: ((self: any, e: Event) -> ())?,
	computer: ((self: any, key: any, seat: number) -> number?)?,
	screen: ((self: any, view: { [string]: any }) -> ())?,
	sig: ((self: any, view: { [string]: any }) -> any)?,
	state: ((self: any, player: any, seat: number?) -> { [string]: any }?)?,
	prompt: ((self: any) -> (string?, string?))?,
	doneText: ((self: any, view: { [string]: any }) -> string?)?,
	inPlay: ((self: any, player: any, body: Model?) -> boolean)?,
	debug: ((self: any, ...any) -> (boolean, string?))?,
	debugName: string?,
}

export type ServerGame = { game: string, new: (ctx: Ctx) -> Table }

local ServerGame = {}

function ServerGame.num(v: any, default: number): number
	if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
		return v
	end
	return default
end

return ServerGame
