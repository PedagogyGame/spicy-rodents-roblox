--!strict
-- ReplicatedStorage.Shared.Minigames.GameSpec
-- The types of the minigame registry (Minigames/Games; read its header first). They live here, apart from the
-- registry, so that a game's own Spec.luau can be typed without requiring the registry that requires it.
-- Pure, types only. Interface: types Place, StationDef, Flow, Spec.

local Session = require("./Session")

export type Place = { x: number, z: number, floorY: number, yaw: number }

export type StationDef = {
	id: string, -- unique in the whole game: "bowling_lane_3", "pool_1"
	game: string,
	label: string, -- what the prompt and the toasts call it: "Lane 3"
	site: string,
	x: number, -- the prompt's anchor in the site's local frame (AlleyLayout.toWorld)
	y: number,
	d: number,
	index: number?, -- lane 3, table 2 (sent to the client as `index`, and as `lane`)
	variant: string?, -- one rules module, several looks: "acorn" | "rodent" | "space"
	reach: number?, -- studs from the anchor before a seated player is taken off (default MinigameService.WANDER)
}

export type Flow = "turns" | "solo" | "live" | "match"

export type Spec = {
	game: string, -- = rules.def.game
	title: string,
	rules: any?, -- Minigame.Rules (nil only with `soon`)
	soon: string?, -- not built yet: what a player who presses E is told
	flow: Flow,
	session: Session.Opts?, -- lobbySeconds, turnSeconds, doneSeconds, idleSeconds
	verbs: { string }, -- what a client may send besides SERVICE_VERBS (Net/Schemas takes the union)
	-- the prompt: `action` while the table is open ("Bowl"); `object` fixes the second line whatever the table
	-- is doing ("Madame Acorna (free)"); `busy` ends the line shown while a game is on ("try another")
	prompt: { action: string, object: string?, busy: string? },
	-- words the service says: start ("" = say nothing; default "Game on!"), unit (what an idle turn is called:
	-- "frame"; default "turn"), removed / finished (the toast of a player taken off idle / told the table reset)
	words: { start: string?, unit: string?, removed: string?, finished: string? }?,
	computers: { { [string]: any } }?, -- "Add a computer": { name, ... } (the fields ride on the computer's key)
	fill: number?, -- "match": computers join at the start until this many are seated
	stations: (sites: { [string]: Place }) -> { StationDef },
}

local GameSpec = {}

return GameSpec
