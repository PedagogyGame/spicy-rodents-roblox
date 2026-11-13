--!strict
-- ServerScriptService.Server.Minigames.MinigameService
-- The minigame framework's server half (BUILD_PLAN §1.1 rule 13, §1.3 frame step 7, §3.16, D28; brief v2 §13,
-- §15 "every minigame ironed out carefully"): one service for every table, lane, court and cabinet, and it names
-- no game. The games are in the registry: Shared/Minigames/Games (each game's Spec: rules, flow, words, where its
-- stations stand) and Server/Minigames/ServerGames (each game's Table: hardware, inputs, computer player, world
-- scoreboard; Server/Minigames/ServerGame says what a Table may supply).
-- Each station gets a ProximityPrompt (E) in its site's MinigamePrompts folder; a person who walks up and
-- presses it takes a seat in that station's Session (Minigames/Session: a short lobby for friends, or Space to
-- start; turns from the rules; the idle clock; players who walk away; the end card and play again). People only:
-- animals are refused, and so is anyone driving (opts.canPlay). One player is enough everywhere. A station whose
-- game is not built yet (Spec.soon) says so on its prompt and to whoever presses it. A station whose def says
-- `joins` is a second way in to another station's game (the far side of a net): it has a prompt of its own and
-- no Session; pressing it seats the player at the station it names, and that game's Table is told which one was
-- pressed.
-- One game cannot take another down: a Table that fails to build, or whose step throws, is logged and its
-- station alone is put out of order (whoever is seated is let go with words; a step that throws is forgiven
-- twice, the table reset each time); every other station carries on in the same frame.
-- Inputs arrive on Net "Minigame.Input" { gameId = station id, seat, verb, args } (schema-checked and rate
-- limited by Shared/Net; the verb list is the registry's), are checked against the seat, the phase and (in a
-- turn-based game) the turn here, and go to the game's Table, or straight to its rules when the Table takes no
-- inputs. A refusal is never silent: the player is sent "refused" with words.
-- Out: Net "Minigame.State" to the seated players: joined (with the site's place) / state (Session.view + your
-- seat + the Table's extras) / event (banners) / left / refused, and whatever the game's Table sends (bowling's
-- "roll" goes to everyone, so watchers see the same throw). PlayerLike stubs (engine smoke) get the same
-- payloads in player.events.
-- Steppable: step(dt) (Heartbeat in the game; by hand in Luau Execution).
-- Interface: new(opts) -> Service; Service:join(player, stationId) -> (ok, why?); Service:leave(player, why?);
--   Service:input(player, payload) -> (ok, why?); Service:step(dt); Service:sessionOf(stationId);
--   Service:stationOf(player) -> id?; Service:debug(stationId, ...) -> (ok, why?) (a scripted outcome through the
--   game's own path, for the engine checks); Service:debugRoll(stationId, pins) and Service:debugDart(stationId,
--   xmm, ymm) (the same, but only at a station whose Table answers to that name: Table.debugName "roll" /
--   "dart"; anywhere else they refuse and change nothing); Service:stations(); Service:stop(); WANDER;
--   PROMPT_DISTANCE; AI_DELAY; STRIKES;
--   opts.sites = { [siteId]: { root: Instance?, place } } (or the older opts.root + opts.place for the bowling
--   alley alone); opts.games = what the games may ask of the rest of the town (ServerGame.Town: people, body,
--   release, charge, pass, best; every member optional, each with a harmless stand-in here); the rest of opts is
--   handed to the games as ctx.opts (bowling reads tunnels, animals, knock, instantRack)

local Import = require("../Import")
local AlleyLayout = Import.shared("Attractions/AlleyLayout") :: typeof(require("../../shared/Attractions/AlleyLayout"))
local Games = Import.shared("Minigames/Games") :: typeof(require("../../shared/Minigames/Games"))
local Session = Import.shared("Minigames/Session") :: typeof(require("../../shared/Minigames/Session"))
local Rng = Import.shared("Util/Rng") :: typeof(require("../../shared/Util/Rng"))
local Tunables = Import.shared("Config/Tunables") :: typeof(require("../../shared/Config/Tunables"))
local EconomyRules = Import.shared("Economy/EconomyRules") :: typeof(require("../../shared/Economy/EconomyRules"))
local ServerGame = require("./ServerGame")
local ServerGames = require("./ServerGames")

local MinigameService = {}
MinigameService.__index = MinigameService

MinigameService.WANDER = 70 -- studs from the station before a seated player is taken off the table
MinigameService.PROMPT_DISTANCE = 9
MinigameService.AI_DELAY = 2.2 -- a computer player thinks this long before its go
MinigameService.STRIKES = 3 -- a station whose step has thrown this many times is out of order for good

export type Place = ServerGame.Place
export type Site = { root: Instance?, place: Place }

export type Opts = {
	sites: { [string]: Site }?, -- every baked place with games in it, by site id
	root: Instance?, -- Workspace.Attractions.BowlingAlley (with `place`: the site "bowling_alley")
	place: Place?, -- AlleyLayout.Place
	tunnels: { [number]: { { number } } }?, -- pair -> tunnel route world points (the ball's way back)
	net: any?, -- Shared/Net instance (engine); nil = the events go to PlayerLike stubs only
	canPlay: ((player: any) -> (boolean, string?))?,
	bodyOf: ((player: any) -> Model?)?,
	animals: (() -> { { [string]: any } })?, -- squirrel-family bodies: { id, kind, x, y, z } in world studs
	knock: ((id: any, x: number, y: number, z: number, text: string) -> ())?, -- move one clear, tell its player
	instantRack: boolean?, -- skip the pinsetter's animation (tests)
	prompts: boolean?, -- create ProximityPrompts (default true)
	seed: number?,
	-- what the games may ask of the rest of the town (ServerGame.Town); every member optional
	games: {
		people: (() -> { ServerGame.Person })?,
		body: ((name: string, cframe: CFrame) -> Model?)?,
		release: ((model: Model) -> ())?,
		charge: ((player: any, cents: number, why: string) -> (boolean, string?))?,
		pass: ServerGame.Pass?, -- the town's one timed pass (Boot/Game: wallet.pass)
		best: ((player: any, key: string, value: number?, lower: boolean?) -> number?)?,
	}?,
}

type Station = {
	id: string,
	game: string,
	label: string,
	lane: number?, -- the station's index (lane 3, table 2), under the name the first clients read
	def: ServerGame.StationDef,
	spec: any, -- Shared/Minigames/GameSpec.Spec
	site: string,
	place: Place,
	root: Instance?,
	session: any, -- Minigames/Session (nil for the stations that are not in this build)
	tbl: ServerGame.Table?, -- the game's Table for this station
	hw: any, -- the Table's hardware (nil when the station's model is missing)
	prompt: ProximityPrompt?,
	anchor: Vector3,
	dirty: boolean,
	lastBroadcast: number,
	seen: { [any]: boolean }, -- players told they are seated
	screenSig: string?, -- what the world scoreboard shows now
	aiAt: number?, -- when the computer player acts
	rng: any, -- this station's seeded stream (throw seeds, computer players)
	joins: string?, -- a second way in: the id of the station whose game this prompt seats you at
	doors: { Station }, -- the stations that join this one (their prompts say what this table is doing)
	strikes: number, -- how many times this station's step has thrown
	broken: boolean, -- out of order: no joins, no inputs, no steps
}

local function nameOf(player: any): string
	if typeof(player) == "Instance" then
		local p = player :: Player
		return if p.DisplayName ~= "" then p.DisplayName else p.Name
	end
	return tostring(player.Name or "Player")
end

local function isComputer(key: any): boolean
	return type(key) == "table" and key.ai == true
end

-- The clock both sides share (clients read the same one): what an input stamped by a client is judged against.
-- (Outside the engine there is none: a spec that cares installs one on its fake workspace.)
local function sharedClock(): number
	local ok, t = pcall(function(): number
		return workspace:GetServerTimeNow()
	end)
	return if ok and type(t) == "number" then t else os.clock()
end

-- The stand-in for the town's timed pass, for a service that was handed none (a bare test; the game hands in
-- the wallet's: Boot/Game). It is the same pass on the same terms (Economy/EconomyRules.pass: the price, the
-- length and the words), paid through `charge` and kept by user id for as long as this service runs, on the
-- clock both sides share.
local function passOn(charge: (player: any, cents: number, why: string) -> (boolean, string?)): ServerGame.Pass
	local ends: { [any]: number } = {} -- who -> the shared-clock second the pass runs out
	local function who(player: any): any
		if (type(player) == "table" or typeof(player) == "Instance") and player.UserId ~= nil then
			return player.UserId
		end
		return player
	end
	local function daySeconds(): number
		local secs = Tunables.get("clock.realSecondsPerDay")
		return if type(secs) == "number" and secs > 0 then secs else 720
	end
	local function spec(): any
		return EconomyRules.pass(EconomyRules.PASS)
	end
	local function left(player: any): number
		local e = ends[who(player)]
		return if e then math.max(0, e - sharedClock()) / daySeconds() else 0
	end
	local function has(player: any): boolean
		return left(player) > 0
	end
	return {
		has = has,
		buy = function(player: any): (boolean, string)
			local s = spec()
			if has(player) then
				return false, s.has
			end
			local ok, words = charge(player, s.cents, s.why)
			if not ok then
				return false, if type(words) == "string" and words ~= "" then words else s.offer
			end
			ends[who(player)] = sharedClock() + s.days * daySeconds()
			return true, s.bought
		end,
		left = left,
		untilDay = function(player: any): number?
			local e = ends[who(player)]
			return if e then e / daySeconds() else nil
		end,
		words = function(player: any): string
			return EconomyRules.passLeftWords(left(player), daySeconds())
		end,
		offer = function(): (number, number, string)
			local s = spec()
			return s.cents, s.days, s.offer
		end,
	}
end

-- What the games may ask of the rest of the town, each member with a harmless stand-in when the caller gave
-- none: nobody to lend a body (nil), nothing charged (true; the game hands in the town's wallet: Boot/Game),
-- a pass desk of the service's own on that charge (the game hands in the wallet's pass), bests kept only as
-- long as this server runs, and the only people known being the ones at the tables.
local function townOf(self: any, games: { [string]: any }?): ServerGame.Town
	local g: { [string]: any } = games or {}
	local bests: { [any]: { [string]: number } } = {}
	local function charge(player: any, cents: number, why: string): (boolean, string?)
		if g.charge then
			return g.charge(player, cents, why)
		end
		return true
	end
	return {
		people = function(): { ServerGame.Person }
			if g.people then
				return g.people()
			end
			local out: { ServerGame.Person } = {}
			local bodyOf = self.opts.bodyOf
			for player in self.playerStation do
				local body = bodyOf and bodyOf(player)
				local root = body and body.PrimaryPart
				if root then
					local q = root.Position
					table.insert(out, { key = player, name = nameOf(player), x = q.X, y = q.Y, z = q.Z })
				end
			end
			return out
		end,
		body = function(name: string, cframe: CFrame): Model?
			return if g.body then g.body(name, cframe) else nil
		end,
		release = function(model: Model)
			if g.release then
				g.release(model)
			end
		end,
		charge = charge,
		pass = g.pass or passOn(charge),
		best = function(player: any, key: string, value: number?, lower: boolean?): number?
			if g.best then
				return g.best(player, key, value, lower)
			end
			-- (by user id where there is one: a Player object is gone when its player leaves)
			local who: any = player
			if (type(player) == "table" or typeof(player) == "Instance") and player.UserId ~= nil then
				who = player.UserId
			end
			local mine = bests[who]
			if mine == nil then
				mine = {}
				bests[who] = mine
			end
			local had = mine[key]
			if value ~= nil and value == value and (had == nil or (if lower then value < had else value > had)) then
				mine[key] = value
			end
			return mine[key]
		end,
	}
end

function MinigameService.new(opts: Opts): any
	local self = setmetatable({}, MinigameService) :: any
	self.opts = opts
	self.net = opts.net
	self.clock = 0
	self.stations = {} :: { [string]: Station }
	self.order = {} :: { string }
	self.playerStation = {} :: { [any]: string }
	self.conns = {} :: { RBXScriptConnection }
	self.aiCount = 0
	self.town = townOf(self, opts.games)
	local sites: { [string]: Site } = {}
	if opts.sites then
		for id, site in opts.sites do
			sites[id] = site
		end
	end
	if opts.place and sites.bowling_alley == nil then
		sites.bowling_alley = { root = opts.root, place = opts.place }
	end
	self.sites = sites
	local alley = sites.bowling_alley
	self.place = alley and alley.place
	self.root = alley and alley.root
	local places: { [string]: Place } = {}
	local promptFolders: { [string]: Instance } = {}
	for id, site in sites do
		places[id] = site.place
		if site.root and opts.prompts ~= false then
			local folder = Instance.new("Folder")
			folder.Name = "MinigamePrompts"
			folder.Parent = site.root
			promptFolders[id] = folder
		end
	end
	for i, def in Games.stations(places) do
		local site = sites[def.site]
		local spec = Games.get(def.game) :: any
		if site == nil then
			-- (a Spec that lists a station on a site that was not baked: there is nowhere to put it)
			continue
		end
		local x, y, z = AlleyLayout.toWorld(site.place, def.x, def.y, def.d)
		local station: Station = {
			id = def.id,
			game = def.game,
			label = def.label,
			lane = def.index,
			def = def,
			spec = spec,
			site = def.site,
			place = site.place,
			root = site.root,
			session = nil,
			tbl = nil,
			hw = nil,
			prompt = nil,
			anchor = Vector3.new(x, y, z),
			dirty = true,
			lastBroadcast = -math.huge,
			seen = {},
			rng = Rng.new((opts.seed or 1) * 9973 + i * 7919),
			joins = def.joins,
			doors = {},
			strikes = 0,
			broken = false,
		}
		if spec.soon == nil and def.joins == nil then
			local so = spec.session or {}
			station.session = Session.new(spec.rules, {
				lobbySeconds = so.lobbySeconds,
				turnSeconds = so.turnSeconds,
				doneSeconds = so.doneSeconds,
				idleSeconds = so.idleSeconds,
				maxTimeouts = so.maxTimeouts,
				seed = (opts.seed or 1) + i,
			})
			local serverGame = ServerGames.get(def.game)
			if serverGame then
				-- (one game's Table failing to build must not keep every other game shut)
				local built, tbl = pcall(serverGame.new, self:_ctx(station))
				if built then
					station.tbl = tbl
					station.hw = tbl.hw
				else
					station.broken = true
					warn(`[Minigames] {def.id} is out of order (its Table could not be built): {tbl}`)
				end
			end
		end
		local promptFolder = promptFolders[def.site]
		if promptFolder then
			local part = Instance.new("Part")
			part.Name = def.id
			part.Anchored = true
			part.CanCollide = false
			part.CanQuery = false
			part.CanTouch = false
			part.Transparency = 1
			part.Size = Vector3.new(0.4, 0.4, 0.4)
			part.CFrame = CFrame.new(station.anchor)
			local prompt = Instance.new("ProximityPrompt")
			prompt.Name = "MinigamePrompt"
			prompt.KeyboardKeyCode = Enum.KeyCode.E
			prompt.GamepadKeyCode = Enum.KeyCode.ButtonY
			prompt.HoldDuration = 0
			prompt.RequiresLineOfSight = false
			prompt.MaxActivationDistance = MinigameService.PROMPT_DISTANCE
			prompt.Style = Enum.ProximityPromptStyle.Default
			prompt:SetAttribute("Minigame", def.game)
			prompt:SetAttribute("Station", def.id)
			prompt.Parent = part
			part.Parent = promptFolder
			station.prompt = prompt
			table.insert(
				self.conns,
				prompt.Triggered:Connect(function(player: Player)
					local ok, err = pcall(function()
						self:join(player, def.id)
					end)
					if not ok then
						warn(`[Minigames] join {def.id} failed: {err}`)
					end
				end)
			)
		end
		self.stations[def.id] = station
		table.insert(self.order, def.id)
	end
	if self.net then
		self.net:on("Minigame.Input", function(player: any, payload: any)
			local ok, err = pcall(function()
				local good, why = self:input(player, payload)
				if not good then
					-- never silently: the player reads why, and their controller learns its input did not go in
					self:fire(player, {
						kind = "refused",
						text = why or "That did not work",
						verb = if type(payload) == "table" then payload.verb else nil,
						station = if type(payload) == "table" then payload.gameId else nil,
					})
				end
			end)
			if not ok then
				warn(`[Minigames] input failed: {err}`)
			end
		end)
	end
	-- a second way in knows the station it leads to, and that station knows its doors
	for _, id in self.order do
		local st = self.stations[id] :: Station
		local target = if st.joins then self.stations[st.joins] :: Station? else nil
		if target then
			table.insert(target.doors, st)
		end
	end
	for _, id in self.order do
		self:_refresh(self.stations[id])
	end
	return self
end

-- What a game's Table sees of the service (Server/Minigames/ServerGame.Ctx).
function MinigameService._ctx(self: any, st: Station): ServerGame.Ctx
	local s = st.session
	local function stamped(payload: { [string]: any }): { [string]: any }
		if payload.station == nil then
			payload.station = st.id
		end
		return payload
	end
	return {
		station = st.def,
		spec = st.spec,
		session = s,
		place = st.place,
		root = st.root,
		anchor = st.anchor,
		rng = st.rng,
		opts = self.opts :: any,
		net = self.net,
		town = self.town,
		now = function(): number
			return self.clock
		end,
		stamp = sharedClock,
		seated = function(): { any }
			return self:_seated(st)
		end,
		seatOf = function(key: any): number?
			return Session.seatOf(s, key)
		end,
		nameOf = function(seat: number): string
			return s.names[seat] or "?"
		end,
		bodyOf = function(key: any): Model?
			local bodyOf = self.opts.bodyOf
			return if bodyOf then bodyOf(key) else nil
		end,
		send = function(player: any, payload: { [string]: any })
			self:fire(player, stamped(payload))
		end,
		broadcast = function(payload: { [string]: any })
			self:_broadcast(st, stamped(payload))
		end,
		everyone = function(payload: { [string]: any })
			-- (a watcher never joined: the site tells its client where the station stands)
			if payload.site == nil then
				payload.site = st.site
			end
			self:_everyone(st, stamped(payload))
		end,
		apply = function(key: any, verb: string, args: { any }?): (boolean, string?)
			return Session.apply(s, key, verb, args, self.clock)
		end,
		server = function(verb: string, args: { any }?, seat: number?): (boolean, string?)
			st.dirty = true
			return Session.applyAs(s, seat or Session.turn(s) or 1, verb, args, self.clock)
		end,
		touch = function()
			Session.touch(s, self.clock)
		end,
		dirty = function()
			st.dirty = true
		end,
		join = function(player: any): (boolean, string?)
			return self:join(player, st.id)
		end,
		leave = function(player: any, why: string?, text: string?)
			if self.playerStation[player] == st.id then
				self:leave(player, why, text)
			end
		end,
		addComputer = function(name: string?): (boolean, string?, any?)
			return self:_addAi(st, true, name)
		end,
		removeComputer = function(key: any): boolean
			if not isComputer(key) or Session.seatOf(s, key) == nil then
				return false
			end
			local seat = Session.leave(s, key, self.clock)
			self:_event(st, { kind = "left", key = key, seat = seat })
			if s.phase == "idle" then
				self:_event(st, { kind = "reset" })
			end
			st.dirty = true
			return true
		end,
		again = function(): (boolean, string?)
			return self:_again(st)
		end,
	}
end

-- Outbound ------------------------------------------------------------------------------------------------------
function MinigameService.fire(self: any, player: any, payload: { [string]: any })
	if typeof(player) == "Instance" then
		if self.net and (player :: Player).Parent ~= nil then
			self.net:fire(player, "Minigame.State", payload)
		end
	elseif type(player) == "table" and not player.ai then
		player.events = player.events or {}
		table.insert(player.events, payload)
	end
end

function MinigameService._seated(_self: any, st: Station): { any }
	local out = {}
	local s = st.session
	if s then
		for i, k in s.seats do
			if not s.gone[i] then
				table.insert(out, k)
			end
		end
	end
	return out
end

function MinigameService._broadcast(self: any, st: Station, payload: { [string]: any })
	for _, p in self:_seated(st) do
		self:fire(p, payload)
	end
end

-- To every client, seated or only watching (and to the seated PlayerLike stubs, who have no net).
function MinigameService._everyone(self: any, st: Station, payload: { [string]: any })
	if self.net then
		self.net:fireAll("Minigame.State", payload)
	end
	for _, p in self:_seated(st) do
		if typeof(p) ~= "Instance" then
			self:fire(p, payload)
		end
	end
end

function MinigameService._event(_self: any, st: Station, e: ServerGame.Event)
	local tbl = st.tbl
	local heard = tbl and tbl.event
	if heard then
		heard(tbl, e)
	end
end

-- Computer players ("Add a computer" in a lobby; a match fills its sides with them) -----------------------------
-- The Spec names them; whatever else it says of one (a skill) rides on the key the Table is handed on its go.
-- Which one: the one asked for by name, else the first on the Spec's list who is not at THIS table yet (the
-- list again from the top once they all are). What another table has done never changes who a player gets.
-- Returns ok, why, and the computer's key.
function MinigameService._addAi(self: any, st: Station, late: boolean?, name: string?): (boolean, string?, any?)
	local s = st.session
	local list = st.spec.computers
	if s.phase ~= "lobby" and not (late and s.phase == "playing" and s.rules.def.lateJoin) then
		return false, "Computers join in the lobby, before the game starts"
	end
	if list == nil or #list == 0 then
		return false, "No computer players for this game"
	end
	local here: { [string]: boolean } = {}
	local count = 0
	for _, k in self:_seated(st) do
		if isComputer(k) then
			here[k.name] = true
			count += 1
		end
	end
	local who: { [string]: any }? = nil
	if name ~= nil then
		for _, c in list do
			if c.name == name then
				who = c
			end
		end
		if who == nil then
			return false, "There is no computer player of that name here"
		elseif here[name] then
			return false, `{name} is already at the table`
		end
	else
		for _, c in list do
			if not here[c.name] then
				who = c
				break
			end
		end
	end
	local pick: { [string]: any } = who or list[count % #list + 1]
	self.aiCount += 1
	local shown = pick.name .. " (computer)"
	local key: { [string]: any } = table.clone(pick)
	key.ai = true
	key.Name = shown
	key.UserId = -self.aiCount
	local ok, why = Session.join(s, key, shown, self.clock)
	st.dirty = true
	return ok, why, if ok then key else nil
end

-- The same players again from the end card (the Play again button; a match that rolls into its next one).
function MinigameService._again(self: any, st: Station): (boolean, string?)
	local ok, why = Session.again(st.session, self.clock)
	if ok then
		self:_onStart(st)
		st.dirty = true
	end
	return ok, if ok then nil else why
end

-- A computer's go in a turn-based game: after a thinking pause, the game's Table plays it.
function MinigameService._aiTurn(self: any, st: Station, key: any)
	if st.aiAt == nil then
		st.aiAt = self.clock + MinigameService.AI_DELAY
		return
	end
	if self.clock < st.aiAt then
		return
	end
	local tbl = st.tbl
	local seat = Session.seatOf(st.session, key)
	local play = tbl and tbl.computer
	if play and seat then
		local wait = play(tbl, key, seat)
		if wait ~= nil then
			st.aiAt = if wait > 0 then self.clock + wait else nil
		end
	end
end

-- The two lines of a station's prompt. `label` is the name on the prompt (a second way in to the same table
-- shows what the table is doing under its own name).
local function promptTexts(st: Station, label: string): (string, string)
	local s = st.session
	local words = st.spec.prompt
	if st.broken then
		return "Out of order", label
	end
	local tbl = st.tbl
	local own = tbl and tbl.prompt
	if own then
		local action, object = own(tbl)
		if action then
			return action, object or label
		end
	end
	if s == nil or words.object then
		return words.action, words.object or label
	end
	local n = 0
	for i = 1, #s.seats do
		if not s.gone[i] then
			n += 1
		end
	end
	local def = s.rules.def
	if s.phase == "idle" or s.phase == "done" then
		local open = if st.spec.computers
			then "open (alone, with friends, or against a computer)"
			elseif def.seats > 1 then "open (alone or with friends)"
			else "open"
		return words.action, `{label} - {open}`
	elseif s.phase == "lobby" then
		return "Join", `{label} - {n}/{def.seats} joining, starting soon`
	end
	if def.lateJoin and n < def.seats then
		return "Join", `{label} - game on ({n} playing): join in`
	end
	return "In use", `{label} - game on ({n} playing): {words.busy or "try another"}`
end

function MinigameService._refresh(self: any, st: Station)
	local target = if st.joins then self.stations[st.joins] :: Station? else nil
	if target then
		-- (a second way in shows what the table it leads to is doing)
		self:_refresh(target)
		return
	end
	st.dirty = false
	local s = st.session
	local prompt = st.prompt
	if prompt then
		local action, object = promptTexts(st, st.label)
		prompt.ActionText = action
		prompt.ObjectText = object
	end
	for _, door in st.doors do
		local doorPrompt = door.prompt
		if doorPrompt then
			local action, object = promptTexts(st, door.label)
			doorPrompt.ActionText = action
			doorPrompt.ObjectText = object
		end
	end
	if s == nil or st.broken then
		return
	end
	local tbl = st.tbl
	local view = Session.view(s, self.clock)
	-- the world screen is rebuilt only when what it shows changed (it replicates to every player)
	local draw = tbl and tbl.screen
	if draw then
		local sig = nil
		local also = tbl and tbl.sig
		pcall(function()
			local g = view.game
			-- (no holes: a nil in the middle of a list is where an encoder may stop reading it)
			sig = game:GetService("HttpService"):JSONEncode({
				if also then also(tbl, view) else false,
				view.phase,
				view.lobbyLeft or false,
				view.turn or false,
				view.seats,
				(g and g.seats) or false,
				view.mode or false,
				(view.result and view.result.winner) or false,
			})
		end)
		if sig == nil or sig ~= st.screenSig then
			st.screenSig = sig
			local ok, err = pcall(function()
				draw(tbl, view)
			end)
			if not ok then
				warn(`[Minigames] scoreboard {st.id}: {err}`)
			end
		end
	end
	local more = tbl and tbl.state
	for _, p in self:_seated(st) do
		local seat = Session.seatOf(s, p)
		local payload: { [string]: any } = {
			kind = "state",
			station = st.id,
			game = st.game,
			label = st.label,
			lane = st.lane,
			you = seat,
			ready = true,
			view = view,
		}
		local extra = if more then more(tbl, p, seat) else nil
		if extra then
			for k, v in extra do
				payload[k] = v
			end
		end
		self:fire(p, payload)
	end
	st.lastBroadcast = self.clock
end

-- Seats -----------------------------------------------------------------------------------------------------------
function MinigameService.stationOf(self: any, player: any): string?
	return self.playerStation[player]
end

function MinigameService.sessionOf(self: any, id: string): any?
	local st = self.stations[id]
	if st and st.joins then
		st = self.stations[st.joins]
	end
	return st and st.session
end

function MinigameService.stations(self: any): { [string]: Station }
	return self.stations
end

function MinigameService.join(self: any, player: any, id: string): (boolean, string?)
	local st = self.stations[id] :: Station?
	if st == nil then
		return false, "no such game"
	end
	-- a second way in: the seat is at the station it names, and that game's Table hears which prompt was pressed
	local via = st.def
	if st.joins then
		st = self.stations[st.joins] :: Station?
		if st == nil then
			return false, "no such game"
		end
		id = st.id
	end
	local soon = st.spec.soon
	if soon then
		self:fire(player, { kind = "refused", text = soon })
		return false, soon
	end
	if st.broken then
		local text = `{st.label} is out of order. Sorry!`
		self:fire(player, { kind = "refused", text = text })
		return false, text
	end
	local canPlay = self.opts.canPlay
	if canPlay then
		local ok, why = canPlay(player)
		if not ok then
			local text = why or "Only people can play here"
			self:fire(player, { kind = "refused", text = text })
			return false, text
		end
	end
	local current = self.playerStation[player]
	if current and current ~= id then
		self:leave(player, "switched")
	end
	local s = st.session
	local tbl = st.tbl
	-- the game's own say first (a one-press machine clears the last player's card, or asks for a moment)
	local ask = tbl and tbl.join
	if ask then
		local ok, why = ask(tbl, player, via)
		if not ok then
			local text = why or "Not just now"
			self:fire(player, { kind = "refused", text = text })
			return false, text
		end
	end
	if s.phase == "done" and Session.seatOf(s, player) == nil then
		-- a newcomer at a table still showing its end card starts a fresh table (Session.join). Whoever is still
		-- reading that card is told and let go; otherwise their card would stay up for good with nothing behind
		-- it, and they could not walk up to any other game
		for _, p in self:_seated(st) do
			self.playerStation[p] = nil
			st.seen[p] = nil
			self:fire(p, {
				kind = "left",
				station = id,
				why = "finished",
				text = `A new game is starting on {st.label}: that one is over`,
			})
		end
	end
	local was = s.phase
	local ok, why, seat = Session.join(s, player, nameOf(player), self.clock)
	if not ok then
		self:fire(player, { kind = "refused", text = why or "cannot join" })
		return false, why
	end
	self.playerStation[player] = id
	st.seen[player] = true
	self:fire(player, {
		kind = "joined",
		station = id,
		game = st.game,
		label = st.label,
		lane = st.lane,
		seat = seat,
		index = st.def.index,
		variant = st.def.variant,
		via = if via ~= st.def then via.id else nil,
		site = st.site,
		place = { x = st.place.x, z = st.place.z, floorY = st.place.floorY, yaw = st.place.yaw },
	})
	if s.phase == "playing" and was ~= "playing" then
		-- only the join that STARTED the game sets the table up. A player already seated who triggers the prompt
		-- again mid-game must not get a fresh one (a bowler's open frame would become a certain spare)
		self:_onStart(st)
	end
	local after = tbl and tbl.joined
	if after then
		after(tbl, player, seat, via)
	end
	st.dirty = true
	self:_refresh(st)
	return true
end

function MinigameService.leave(self: any, player: any, why: string?, text: string?)
	local id = self.playerStation[player]
	if id == nil then
		return
	end
	self.playerStation[player] = nil
	local st = self.stations[id] :: Station
	st.seen[player] = nil
	local s = st.session
	local wasTurn = Session.turnKey(s) == player
	local seat = Session.leave(s, player, self.clock)
	self:_event(st, { kind = "left", key = player, seat = seat, why = if wasTurn then "turn" else nil })
	if s.phase == "idle" then
		self:_event(st, { kind = "reset" })
	end
	self:fire(player, { kind = "left", station = id, why = why or "left", text = text })
	st.dirty = true
end

function MinigameService._onStart(self: any, st: Station)
	self:_event(st, { kind = "start" })
	local spec = st.spec
	-- a match fills its sides with computers (they join the game that has just begun)
	if spec.fill and spec.computers then
		local guard = 0
		while #self:_seated(st) < spec.fill and guard < 32 do
			guard += 1
			if not self:_addAi(st, true) then
				break
			end
		end
	end
	local text = if spec.words and spec.words.start ~= nil then spec.words.start else "Game on!"
	if text ~= "" then
		self:_broadcast(st, { kind = "event", station = st.id, text = text, big = true })
	end
end

-- Inputs ---------------------------------------------------------------------------------------------------------
function MinigameService.input(self: any, player: any, payload: any): (boolean, string?)
	if type(payload) ~= "table" then
		return false, "That did not reach the game: try again"
	end
	local id = payload.gameId
	local verb = payload.verb
	local args = if type(payload.args) == "table" then payload.args else {}
	local st = self.stations[id] :: Station?
	if st == nil or st.session == nil or st.broken then
		return false, "There is no game there"
	end
	if self.playerStation[player] ~= id then
		return false, "You are not at that game: walk up and press E"
	end
	local s = st.session
	local tbl = st.tbl
	-- the game's own verbs that work whatever the table is doing
	local command = tbl and tbl.command
	if command then
		local handled, ok, why = command(tbl, player, verb, args)
		if handled then
			return ok == true, if ok then nil else why
		end
	end
	if verb == "leave" then
		self:leave(player, "left")
		return true
	elseif verb == "start" then
		local ok, why = Session.start(s, self.clock)
		if ok then
			self:_onStart(st)
			st.dirty = true
		end
		return ok, if ok then nil else why
	elseif verb == "again" then
		return self:_again(st)
	elseif verb == "addai" then
		-- (with a word: the computer player of that name, as the Spec lists it)
		local ok, why = self:_addAi(st, false, if type(args[1]) == "string" then args[1] else nil)
		return ok, why
	elseif verb == "mode" then
		local ok, why = Session.apply(s, player, "mode", { args[1] }, self.clock)
		st.dirty = true
		return ok, if ok then nil else why
	end
	if s.phase ~= "playing" then
		return false,
			if s.phase == "lobby"
				then "Waiting for the game to start (Space starts it now)"
				elseif s.phase == "done" then "The game is over: Play again or Leave (Q)"
				else "No game is on here: walk up and press E"
	end
	if st.spec.flow == "turns" and Session.turnKey(s) ~= player then
		return false, "Not your turn yet"
	end
	local seat = Session.seatOf(s, player)
	if seat == nil then
		return false, "You are not at that game: walk up and press E"
	end
	local take = tbl and tbl.input
	if take then
		local ok, why = take(tbl, player, seat, verb, args)
		if ok ~= nil then
			return ok, why
		end
	end
	-- a verb the Table leaves alone goes to the rules as it is, if the game lists it and the rules know it
	local rules = s.rules
	if
		table.find(st.spec.verbs, verb)
		and rules.verbs[verb]
		and not (rules.serverVerbs and rules.serverVerbs[verb])
	then
		local ok, why = Session.apply(s, player, verb, args, self.clock)
		st.dirty = true
		return ok, why
	end
	return false, "That does not work at this game"
end

-- debug: a scripted outcome at a station through the game's own path (Luau Execution; tests): bowling takes a
-- pinfall, darts a landing point in board millimetres.
function MinigameService.debug(self: any, id: string, ...: any): (boolean, string?)
	local st = self.stations[id] :: Station?
	local tbl = st and st.tbl
	local scripted = tbl and tbl.debug
	if scripted == nil then
		return false, "nothing can be scripted there"
	end
	return scripted(tbl, ...)
end

-- The two older names: a scripted pinfall and a scripted dart. Each works only at a station whose Table answers
-- to that name (Table.debugName); at any other it refuses and changes nothing (a dart's arguments handed to a
-- lane would otherwise be rolled as a gutter ball and counted).
local function scriptedAs(name: string, refusal: string): (self: any, id: string, ...any) -> (boolean, string?)
	return function(self: any, id: string, ...: any): (boolean, string?)
		local st = self.stations[id] :: Station?
		local tbl = st and st.tbl
		if tbl == nil or tbl.debugName ~= name then
			return false, refusal
		end
		return MinigameService.debug(self, id, ...)
	end
end
MinigameService.debugRoll = scriptedAs("roll", "no lane")
MinigameService.debugDart = scriptedAs("dart", "no dartboard")

-- A station is put out of order: logged, whoever is seated is let go with words, the table reset. (After a
-- throw in step() the Table is kept and may try again, STRIKES times in all.)
function MinigameService._fault(self: any, st: Station, err: any)
	st.strikes += 1
	st.broken = st.strikes >= MinigameService.STRIKES
	warn(
		`[Minigames] {st.id} failed in its step ({st.strikes} of {MinigameService.STRIKES}{if st.broken
			then ": out of order"
			else ""}): {err}`
	)
	local s = st.session
	for _, p in self:_seated(st) do
		self.playerStation[p] = nil
		st.seen[p] = nil
		self:fire(p, {
			kind = "left",
			station = st.id,
			why = "fault",
			text = if st.broken
				then `{st.label} is out of order. Sorry!`
				else `Something went wrong at {st.label}: the game was reset. Press E there to play again.`,
		})
	end
	Session.reset(s)
	st.aiAt = nil
	pcall(function()
		self:_event(st, { kind = "reset" })
	end)
	st.dirty = false
	pcall(function()
		self:_refresh(st)
	end)
end

-- Per frame -------------------------------------------------------------------------------------------------------
function MinigameService.step(self: any, dt: number)
	self.clock += dt
	for _, id in self.order do
		local st = self.stations[id] :: Station
		if st.session == nil or st.broken then
			continue
		end
		-- (each station on its own: one game's error stops neither the stations after it nor the frame. pcall of a
		-- function that returns nothing still returns the error on failure; the checker counts one value)
		local ok, err = (pcall :: any)(MinigameService._stepStation, self, st, dt)
		if not ok then
			self:_fault(st, err)
		end
	end
end

function MinigameService._stepStation(self: any, st: Station, dt: number)
	local id = st.id
	local s = st.session
	local tbl = st.tbl
	local spec = st.spec
	local words = spec.words
	local advance = tbl and tbl.step
	if advance then
		advance(tbl, dt)
	end
	local isBusy = tbl and tbl.busy
	local busy = if isBusy then isBusy(tbl) else false
	local before = {}
	for _, p in self:_seated(st) do
		before[p] = true
	end
	local events = Session.step(s, self.clock, busy)
	for _, e in events do
		if e.kind == "start" then
			self:_onStart(st)
		elseif e.kind == "turn" then
			local name = s.names[e.seat] or "?"
			for _, p in self:_seated(st) do
				self:fire(p, {
					kind = "event",
					station = st.id,
					text = if p == e.key then "Your turn!" else `{name}'s turn`,
					big = p == e.key,
				})
			end
			self:_event(st, e)
		elseif e.kind == "timeout" then
			local what = (words and words.unit) or "turn"
			self:_broadcast(st, {
				kind = "event",
				station = st.id,
				text = `{s.names[e.seat] or "?"} took too long: that {what} is skipped`,
			})
			self:_event(st, e)
		elseif e.kind == "removed" and e.key ~= nil then
			self.playerStation[e.key] = nil
			st.seen[e.key] = nil
			self:fire(e.key, { kind = "left", station = st.id, why = "idle", text = words and words.removed })
			self:_event(st, e)
		elseif e.kind == "done" then
			local r = s.result
			local text = "Game over!"
			if r and type(r.text) == "string" then
				text = r.text
			elseif r and type(r.winners) == "table" and #r.winners > 0 then
				local names = {}
				for _, seat in r.winners do
					table.insert(names, s.names[seat] or "?")
				end
				text = `{table.concat(names, " and ")} {if #names > 1 then "win" else "wins"}!`
			elseif r and r.winner and s.names[r.winner] and #s.seats > 1 then
				text = `{s.names[r.winner]} wins!`
			end
			local say = tbl and tbl.doneText
			if say then
				local own = say(tbl, Session.view(s, self.clock))
				if own ~= nil then
					text = own
				end
			end
			if text ~= "" then
				self:_broadcast(st, { kind = "event", station = st.id, text = text, big = true, over = true })
			end
			self:_event(st, e)
		else
			-- (skipped, reset, and a removed seat with nobody behind it)
			self:_event(st, e)
		end
		st.dirty = true
	end
	-- anyone the session dropped (reset, end card timed out) hears they are off the table
	for p in before do
		if Session.seatOf(s, p) == nil and self.playerStation[p] == id then
			self.playerStation[p] = nil
			st.seen[p] = nil
			self:fire(p, { kind = "left", station = id, why = "finished", text = words and words.finished })
			st.dirty = true
		end
	end
	-- only computers left at the table: it resets
	if s.phase ~= "idle" then
		local human = false
		for _, p in self:_seated(st) do
			if not isComputer(p) then
				human = true
			end
		end
		if not human then
			Session.reset(s)
			self:_event(st, { kind = "reset" })
			st.dirty = true
		end
	end
	-- a computer player's turn
	local turnKey = Session.turnKey(s)
	if isComputer(turnKey) and s.phase == "playing" then
		self:_aiTurn(st, turnKey)
	else
		st.aiAt = nil
	end
	-- seated players who stopped being a person, or wandered off
	local inPlay = tbl and tbl.inPlay
	for _, p in self:_seated(st) do
		if isComputer(p) then
			continue
		end
		local canPlay = self.opts.canPlay
		local ok, whyNot = true, nil :: string?
		if canPlay then
			ok, whyNot = canPlay(p)
		end
		local body = self.opts.bodyOf and self.opts.bodyOf(p)
		local far = false
		if inPlay then
			far = not inPlay(tbl, p, body)
		elseif body and body.PrimaryPart then
			far = (body.PrimaryPart.Position - st.anchor).Magnitude > (st.def.reach or MinigameService.WANDER)
		end
		if far then
			self:leave(p, "too far", "You walked away from the game")
		elseif not ok then
			self:leave(p, "not a person", `You were taken out of the game. {whyNot or ""}`)
		end
	end
	if st.dirty or (s.phase ~= "idle" and self.clock - st.lastBroadcast >= 1) then
		self:_refresh(st)
	end
end

function MinigameService.stop(self: any)
	for _, c in self.conns do
		c:Disconnect()
	end
	table.clear(self.conns)
end

return MinigameService
