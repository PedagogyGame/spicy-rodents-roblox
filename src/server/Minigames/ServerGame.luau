--!strict
-- ServerScriptService.Server.Minigames.ServerGame
-- What a minigame's server half looks like to MinigameService (the registry is Server/Minigames/ServerGames; the
-- game's line in Shared/Minigames/Games says the rest). A ServerGame is { game, new(ctx) -> Table }: the service
-- calls new() once per station and from then on talks to the Table it returns. Every member of a Table is
-- optional; a game with no Table at all still works if its rules need nothing but inputs (the service applies
-- a seated player's verbs to the Session itself).
-- The Ctx is the Table's whole view of the service: its station, its Session, where it stands, its seeded
-- stream, who is seated, and how to speak (send / broadcast / everyone add `station` to a payload that lacks it).
-- The Table's hooks, in the order the service uses them:
--   hw            the raw hardware (kept as station.hw; tests and the engine checks reach it)
--   join          before a player is seated: (false, why) refuses with words; may clear the table first
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
-- Interface: types Place, StationDef, Event, Ctx, Table, ServerGame; num(v, default) -> number (a finite number
--   from a client's argument, or the default)

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
}
export type Event = { kind: string, seat: number?, key: any?, why: string? }

export type Ctx = {
	station: StationDef,
	spec: any, -- Shared/Minigames/GameSpec.Spec
	session: any, -- Shared/Minigames/Session.Session
	place: Place, -- the site's frame (AlleyLayout.toWorld(place, X, Y, D))
	root: Instance?, -- the site's baked model under Workspace.Attractions (nil in a bare test)
	anchor: Vector3, -- the station's prompt, world
	rng: any, -- Util/Rng: this station's seeded stream
	opts: { [string]: any }, -- the service's options (tunnels, animals, knock, instantRack, ...)
	net: any?, -- Shared/Net (a game with remotes of its own)
	now: () -> number, -- the service clock, seconds
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
	addComputer: () -> (boolean, string?),
}

export type Table = {
	hw: any?,
	join: ((self: any, player: any) -> (boolean, string?))?,
	joined: ((self: any, player: any, seat: number?) -> ())?,
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
