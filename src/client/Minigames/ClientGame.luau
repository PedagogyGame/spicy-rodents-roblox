--!strict
-- StarterPlayer.StarterPlayerScripts.Client.Minigames.ClientGame
-- What a minigame's client half looks like to MinigameClient (the registry is Client/Minigames/ClientGames; the
-- game's line in Shared/Minigames/Games says the rest). Every member but `game` is optional: a game that
-- supplies nothing still opens with a plain card, Leave and Play again.
--   help       the How-to-play card: how = lines of rules, keys = lines of controls
--   title      the card's heading for a "joined" message (default: the Spec's title)
--   buttons    the button bar for a phase: "joined" (as the game opens), then the Session's "lobby", "playing",
--              "done" on every state message. nil = leave the bar as it is. A button's id is sent as a verb with
--              no arguments; an id that is one of the rules' MODES is sent as verb "mode" { id }. A game with
--              no `buttons` at all gets the framework's: Start now (and Add a computer, if its Spec names
--              computers) in a lobby, Play again at the end, Leave (Q) always.
--   keys       extra keys while the game is open: KeyCode name -> verb sent with no arguments (the fortune
--              teller's E = "again"). Q leaves, H hides the help card and Space starts a lobby in every game.
--   new        the controller for a seat at the game (it gets a Ctx). It is made only when the station's place
--              is known, unless `placeless`. A controller connects its own input and render steps and MUST
--              follow the three rules in MinigameClient's header (camera through ctx.camera / ctx.releaseCamera,
--              cursor through MinigameUI buttons, nothing left bound after stop()).
--   card       draw the scorecard into `frame` (already emptied) from a state message's view; called only when
--              the view's phase, turn, seats, game seats, mode or cardSig changed
--   cardSig    what else the scorecard shows (anything JSON-friendly)
--   endCard    the end card for a finished view (MinigameUI.summary's table), or nil for none
--   kinds      message kinds this game's Table sends to EVERYONE (ctx.everyone on the server): unique among games
--   watch      called for those kinds whether or not the player is in the game (a watcher sees the same throw);
--              what it returns is handed to the seated controller's onMessage as `watched`
--   sounds     cue -> asset id ("" = none yet), added to MinigameSounds; play them with ctx.sound(cue)
--   words      the toasts of a player taken off idle / told the table reset, when the server sent no words
--   linger     seconds the UI stays up after the server lets the player go at the end (the fortune card)
-- The Controller: onState(msg) for every "state" message of its station (msg.view = Session.view, msg.you =
-- your seat, plus the Table's extras); onMessage(msg, watched) for every other message of its station that the
-- framework does not own (the game's own kinds, and "event" after its banner is up); onRefused(msg) when the
-- server refused an input (never silent: the words are already on screen); stop() when the game closes.
-- Interface: types Place, Ctx, Controller, ClientGame. Types only.

export type Place = { x: number, z: number, floorY: number, yaw: number }

export type Ctx = {
	station: string,
	game: string,
	label: string,
	place: Place?, -- the site's frame (AlleyLayout.toWorld(place, X, Y, D))
	lane: number?, -- the station's index under its first name
	index: number?, -- lane 3, table 2
	variant: string?, -- "acorn" | "rodent" | "space"
	ui: any, -- Client/UI/MinigameUI
	send: (verb: string, args: { any }?) -> (),
	camera: (cf: CFrame, fov: number?, snap: boolean?) -> (),
	releaseCamera: () -> (),
	controls: (on: boolean) -> (), -- false takes the player's legs (the game reads the keys itself)
	setButtons: (list: { { string } }) -> (),
	toast: (text: string, seconds: number?) -> (),
	body: () -> Model?,
	sound: (cue: string, volume: number?) -> boolean,
}

export type Controller = {
	onState: ((self: any, msg: { [string]: any }) -> ())?,
	onMessage: ((self: any, msg: { [string]: any }, watched: any?) -> ())?,
	onRefused: ((self: any, msg: { [string]: any }) -> ())?,
	stop: (self: any) -> (),
}

export type ClientGame = {
	game: string,
	help: { how: { string }, keys: { string } }?,
	title: ((msg: { [string]: any }) -> string)?,
	buttons: ((phase: string, view: { [string]: any }?) -> { { string } }?)?,
	keys: { [string]: string }?,
	new: ((ctx: Ctx) -> Controller)?,
	placeless: boolean?,
	card: ((frame: Frame, view: { [string]: any }, you: number?, kit: any) -> ())?,
	cardSig: ((view: { [string]: any }) -> any)?,
	endCard: ((view: { [string]: any }, you: number?) -> { [string]: any }?)?,
	kinds: { string }?,
	watch: ((msg: { [string]: any }, place: Place?) -> any)?,
	sounds: { [string]: string }?,
	words: { idle: string?, finished: string? }?,
	linger: number?,
}

local ClientGame = {}

return ClientGame
