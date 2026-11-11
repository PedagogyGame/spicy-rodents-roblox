--!strict
-- ReplicatedStorage.Shared.Minigames.Games
-- The registry of minigames (BUILD_PLAN §1.1 rule 13 "frameworks before content", §3.16, D28; brief v2 §13): ONE
-- LINE PER GAME in ALL below. A game supplies everything about itself from its own files:
--   its Spec (this registry; Shared/Minigames/<Game>/Spec.luau): rules, how it flows, its verbs, its words, where
--     its stations stand;
--   its server half (Server/Minigames/ServerGames, one line; Server/Minigames/Games/<Game>.luau): hardware,
--     inputs, the computer player, the world scoreboard;
--   its client half (Client/Minigames/ClientGames, one line; Client/Minigames/Games/<Game>.luau): controller,
--     help card, buttons, scorecard, end card, what watchers see;
--   its furniture (tools/bake/GameBakes, one line; tools/bake/games/<Game>.luau).
-- MinigameService, MinigameClient, MinigameUI and Session name no game: adding one touches only new files and
-- those lines. A Spec with `soon` is a game that is not built yet: its stations get a prompt that says so.
-- The smallest worked example of each flow is tests/lib/FakeGames (six games registered only in a spec); the rig
-- that plays any registered game on the fake engine, real service against real client, is tests/lib/MinigameRig
-- (tests/isolated/minigames_registry.luau uses both).
-- flow:
--   "turns"  one seat acts at a time (rules.turn); the turn clock plays out an idle turn (bowling, darts, pool)
--   "solo"   one seat, a machine (the fortune teller, pinball, the labyrinth); rules.turn may return 1 so that
--            the turn clock is its idle clock
--   "live"   everyone seated may act at any moment (a rally); rules.step(state, dt) moves the game;
--            session.idleSeconds takes an idle seat off
--   "match"  a team game that runs on its own clock (rules.step), takes players while it is on (rules.def.lateJoin)
--            and has a winning side (Result.winners); `fill` computers join at the start
-- A site is a baked place with its own local frame (Attractions/AlleyLayout's: X across, Y up from the floor, D
-- away from the entrance; toWorld / toLocal): "bowling_alley" (data/attractions.json) or a venue id of
-- generated/Expansion ("f3_racquet_club", "f3_steakhouse", "f2_doctor", "f3_tv_station"). A station is where a
-- player walks up and presses E; stations(sites) returns a game's stations for the sites that exist. A station
-- with `joins = "<another station's id>"` is a second way in to that station's game (same game, and the station
-- it names has a game of its own): a prompt and nothing else.
-- WHAT EVERY GAME KEEPS TO (each is held by a spec: tests/isolated/minigames_framework.luau, minigames_registry):
--   1. On the wire a game has Minigame.Input (its verbs, from its Spec) and Minigame.State (ctx.send / broadcast
--      / everyone), and no remote of its own. Minigame.Input carries 20 messages a second (40 at once) and a
--      dropped one is never answered; its arguments are at most 8 numbers, booleans or strings of 200 characters.
--      So a stream of input (flippers, a tilt, a pull) is never a message per key or per frame: the client keeps
--      a log by tick and sends its next segment about ten times a second, { fromTick, toTick, packed events },
--      and the server replays to the tick the segment declares (tests/lib/FakeGames' machine is the example).
--   2. Two clocks. The service's own (ServerGame.Ctx.now) is for durations on the server. Anything a client
--      stamps and the server judges by time uses the shared clock: ctx.stamp() on both sides (or "which script,
--      and how many seconds into it", which needs no clock at all).
--   3. A game never takes another down. Its Table builds and steps on a site that lacks its furniture (hw = nil,
--      nothing done, nothing sent), and says nothing to everyone while nobody is seated at it.
--   4. A game's numbers live in its own Layout / Config module (Config/Tunables is read, never added to); its
--      tools live in tools/games/<game>/ (already formatted and linted by tools/ci.sh).
--   5. The player's walking pace is changed only through the client's ctx.pace; a game's keys are its `keys`
--      (looked at before Q, gamepad B and Space; "" swallows one).
--   6. A model two games share has one owner. The pool table model (Minigames/Pool: physics, cloth, tables, the
--      shot script) is pool's: bumper pool reads it and keeps its own rules in Minigames/BumperPool. The rally
--      model (Minigames/Rally: a ball in flight, a stamped swing and its reach) is racquetball's: volleyball
--      reads it. The reader asks the owner for a change; it does not edit the other's folder.
-- Pure. Interface: ALL; SERVICE_VERBS; get(game) -> Spec?; stations(sites) -> { StationDef } (registry order,
--   ids unique); station(id, sites) -> StationDef?; verbs() -> { string } (everything a client may send, for
--   Net/Schemas); check(spec) -> (ok, err?); register(spec) (tests: a game added at run time)

local GameSpec = require("./GameSpec")
local Minigame = require("./Minigame")

export type Place = GameSpec.Place
export type StationDef = GameSpec.StationDef
export type Flow = GameSpec.Flow
export type Spec = GameSpec.Spec

local Games = {}

-- Verbs the service itself understands at every station.
Games.SERVICE_VERBS = { "leave", "start", "again", "addai", "mode" }
-- Verbs kept on the wire from the first Net contract (W1): any game may use them without declaring them.
Games.COMMON_VERBS = { "aim", "power", "release", "tilt", "pull", "place", "serve", "hit", "throw" }

-- ONE LINE PER GAME. The order is the station order (and so each station's seeded stream): append, never reorder.
Games.ALL = {
	require("./Bowling/Spec"),
	require("./Darts/Spec"),
	require("./Fortune/Spec"),
	require("./Pool/Spec"),
	require("./BumperPool/Spec"),
	require("./Pinball/Spec"),
	require("./Racquetball/Spec"),
	require("./Volleyball/Spec"),
	require("./Jenga/Spec"),
	require("./Labyrinth/Spec"),
	require("./Paintball/Spec"),
} :: { Spec }

local FLOWS: { [string]: boolean } = { turns = true, solo = true, live = true, match = true }

function Games.check(spec: any): (boolean, string?)
	if type(spec) ~= "table" or type(spec.game) ~= "string" or spec.game == "" then
		return false, "game"
	end
	if type(spec.title) ~= "string" then
		return false, `{spec.game}: title`
	end
	if not FLOWS[spec.flow] then
		return false, `{spec.game}: flow`
	end
	if type(spec.verbs) ~= "table" then
		return false, `{spec.game}: verbs`
	end
	for _, v in spec.verbs do
		if type(v) ~= "string" or #v == 0 or #v > 24 then
			return false, `{spec.game}: verb {tostring(v)}`
		end
	end
	if type(spec.prompt) ~= "table" or type(spec.prompt.action) ~= "string" then
		return false, `{spec.game}: prompt.action`
	end
	if type(spec.stations) ~= "function" then
		return false, `{spec.game}: stations`
	end
	if spec.soon ~= nil then
		if type(spec.soon) ~= "string" or spec.soon == "" then
			return false, `{spec.game}: soon`
		end
		return true
	end
	local ok, err = Minigame.check(spec.rules)
	if not ok then
		return false, `{spec.game}: rules: {err}`
	end
	if spec.rules.def.game ~= spec.game then
		return false, `{spec.game}: rules.def.game is {spec.rules.def.game}`
	end
	if spec.flow == "turns" and type(spec.rules.turn) ~= "function" then
		return false, `{spec.game}: a turn-based game needs rules.turn`
	end
	for _, v in spec.verbs do
		-- (a client verb need not be a rules verb: bowling's "release" is the lane's, which rolls for the rules)
		if spec.rules.serverVerbs and spec.rules.serverVerbs[v] then
			return false, `{spec.game}: verb {v} is a server verb`
		end
	end
	if spec.computers ~= nil then
		for _, c in spec.computers do
			if type(c) ~= "table" or type(c.name) ~= "string" then
				return false, `{spec.game}: computers need a name`
			end
		end
	end
	return true
end

function Games.get(game: string): Spec?
	for _, spec in Games.ALL do
		if spec.game == game then
			return spec
		end
	end
	return nil
end

-- register: a game added at run time (the registry's own specs do this; the game's lines above are the real way).
function Games.register(spec: Spec)
	assert(Games.check(spec))
	assert(Games.get(spec.game) == nil, `Games.register: {spec.game} is already registered`)
	table.insert(Games.ALL, spec)
end

function Games.stations(sites: { [string]: Place }): { StationDef }
	local out: { StationDef } = {}
	local seen: { [string]: string } = {}
	for _, spec in Games.ALL do
		for _, st in spec.stations(sites) do
			assert(st.game == spec.game, `Games.stations: {st.id} is listed by {spec.game} but says {st.game}`)
			assert(seen[st.id] == nil, `Games.stations: {st.id} is listed by {seen[st.id]} and {spec.game}`)
			seen[st.id] = spec.game
			table.insert(out, st)
		end
	end
	-- a second way in leads to a station of the same game that has a game of its own
	local byId: { [string]: StationDef } = {}
	for _, st in out do
		byId[st.id] = st
	end
	for _, st in out do
		if st.joins ~= nil then
			local target = byId[st.joins]
			assert(target ~= nil, `Games.stations: {st.id} joins {st.joins}, which is not a station`)
			assert(target.game == st.game, `Games.stations: {st.id} joins {st.joins}, a station of {target.game}`)
			assert(target.joins == nil, `Games.stations: {st.id} joins {st.joins}, which itself joins another`)
		end
	end
	return out
end

function Games.station(id: string, sites: { [string]: Place }): StationDef?
	for _, st in Games.stations(sites) do
		if st.id == id then
			return st
		end
	end
	return nil
end

-- Every verb a client may send (sorted, no duplicates): the Net schema of Minigame.Input is built from this.
function Games.verbs(): { string }
	local set: { [string]: boolean } = {}
	for _, list in { Games.SERVICE_VERBS, Games.COMMON_VERBS } do
		for _, v in list do
			set[v] = true
		end
	end
	for _, spec in Games.ALL do
		for _, v in spec.verbs do
			set[v] = true
		end
	end
	local out = {}
	for v in set do
		table.insert(out, v)
	end
	table.sort(out)
	return out
end

return Games
