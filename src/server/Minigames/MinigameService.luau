--!strict
-- ServerScriptService.Server.Minigames.MinigameService
-- The minigame framework's server half (BUILD_PLAN §1.1 rule 13, §1.3 frame step 7, §3.16, D28; brief v2 §13a,
-- §15 "every minigame ironed out carefully"): one service for every table, lane and cabinet. Each station (from
-- Shared/Attractions/AlleyLayout.stations) gets a ProximityPrompt (E); a person who walks up and presses it takes
-- a seat in that station's Session (Minigames/Session: a short lobby for friends, or Space to start; turns from
-- the rules module; the idle-turn clock; players who walk away; the end card and play again). People only:
-- animals are refused, and so is anyone driving. One player is enough everywhere.
-- Inputs arrive on Net "Minigame.Input" { gameId = station id, seat, verb, args } (schema-checked and rate
-- limited by Shared/Net), are checked against the seat and the turn here, and drive the station's hardware:
--   bowling  BowlingLane (server-owned physics; "release" { offset, angle, power, spin }); the pinfall it counts
--            is scored as the rules' server verb "roll"; the overhead monitor is rewritten (Scoreboard)
--   darts    Dartboard ("throw" { aimX, aimY, timing } resolved by the rules' seeded scatter; "mode" 501/cricket)
--   fortune  FortuneCabinet (the prompt pulls the lever; reels; a printed fortune or taunt; never money)
--   pool, bumper pool, pinball: the prompt says plainly they are not in this build yet
-- Out: Net "Minigame.State" to the seated players: joined / state (Session.view + your seat) / event (banners)
-- / dart / fortune / left / refused. PlayerLike stubs (engine smoke) get the same payloads in player.events.
-- Steppable: step(dt) (Heartbeat in the game; by hand in Luau Execution, where debugRoll stands in for physics).
-- Interface: new(opts) -> Service; Service:join(player, stationId) -> (ok, why?); Service:leave(player, why?);
--   Service:input(player, payload) -> (ok, why?); Service:step(dt); Service:sessionOf(stationId);
--   Service:stationOf(player) -> id?; Service:debugRoll(stationId, pins) -> (ok, why?); Service:stations();
--   Service:stop(); GAMES

local Import = require("../Import")
local AlleyLayout =
	Import.shared("Attractions/AlleyLayout") :: typeof(require("../../shared/Attractions/AlleyLayout"))
local Session = Import.shared("Minigames/Session") :: typeof(require("../../shared/Minigames/Session"))
local Bowling =
	Import.shared("Minigames/MinigameRules/Bowling") :: typeof(require("../../shared/Minigames/MinigameRules/Bowling"))
local Darts =
	Import.shared("Minigames/MinigameRules/Darts") :: typeof(require("../../shared/Minigames/MinigameRules/Darts"))
local FortuneMachine = Import.shared("Minigames/MinigameRules/FortuneMachine")
	:: typeof(require("../../shared/Minigames/MinigameRules/FortuneMachine"))
local BowlingLane = require("./BowlingLane")
local Dartboard = require("./Dartboard")
local FortuneCabinet = require("./FortuneCabinet")
local Scoreboard = require("./Scoreboard")

local MinigameService = {}
MinigameService.__index = MinigameService

MinigameService.GAMES = {
	bowling = { rules = Bowling, opts = { lobbySeconds = 8, turnSeconds = 60, doneSeconds = 30 }, title = "Bowling" },
	darts = { rules = Darts, opts = { lobbySeconds = 8, turnSeconds = 45, doneSeconds = 25 }, title = "Darts" },
	fortune_machine = {
		rules = FortuneMachine,
		opts = { lobbySeconds = 0, turnSeconds = 0, doneSeconds = 4 },
		title = "Madame Acorna",
	},
}
MinigameService.SOON = {
	pool = "Pool is coming in the next build: the table is racked and waiting. Try the lanes, the darts or Madame Acorna!",
	bumper_pool = "Bumper pool is coming in the next build. Try the lanes, the darts or Madame Acorna!",
	pinball = "This pinball machine is out of order (a later build fixes it). Try the lanes, the darts or Madame Acorna!",
}
MinigameService.WANDER = 70 -- studs from the station before a seated player is taken off the table
MinigameService.PROMPT_DISTANCE = 9

export type Opts = {
	root: Instance?, -- Workspace.Attractions.BowlingAlley
	place: AlleyLayout.Place,
	tunnels: { [number]: { { number } } }?, -- pair -> tunnel route world points (the ball's way back)
	net: any?, -- Shared/Net instance (engine); nil = the events go to PlayerLike stubs only
	canPlay: ((player: any) -> (boolean, string?))?,
	bodyOf: ((player: any) -> Model?)?,
	physics: boolean?, -- false in Luau Execution
	prompts: boolean?, -- create ProximityPrompts (default true)
	seed: number?,
}

type Station = {
	id: string,
	game: string,
	kind: string,
	label: string,
	lane: number?,
	session: any?,
	hw: any?, -- BowlingLane | Dartboard | FortuneCabinet
	screen: Instance?, -- the scoreboard SurfaceGui
	prompt: ProximityPrompt?,
	anchor: Vector3,
	dirty: boolean,
	lastBroadcast: number,
	seen: { [any]: boolean }, -- players told they are seated
}

local function nameOf(player: any): string
	if typeof(player) == "Instance" then
		local p = player :: Player
		return if p.DisplayName ~= "" then p.DisplayName else p.Name
	end
	return tostring(player.Name or "Player")
end

function MinigameService.new(opts: Opts): any
	local self = setmetatable({}, MinigameService) :: any
	self.opts = opts
	self.place = opts.place
	self.root = opts.root
	self.net = opts.net
	self.clock = 0
	self.stations = {} :: { [string]: Station }
	self.order = {} :: { string }
	self.playerStation = {} :: { [any]: string }
	self.conns = {} :: { RBXScriptConnection }
	local root = opts.root
	local promptFolder: Instance? = nil
	if root and opts.prompts ~= false then
		promptFolder = Instance.new("Folder")
		promptFolder.Name = "MinigamePrompts"
		promptFolder.Parent = root
	end
	local lanes = root and root:FindFirstChild("Lanes")
	local boards = root and root:FindFirstChild("Scoreboards")
	local games = root and root:FindFirstChild("GamesRoom")
	for i, st in AlleyLayout.stations() do
		local x, y, z = AlleyLayout.toWorld(self.place, st.x, st.y, st.d)
		local station: Station = {
			id = st.id,
			game = st.game,
			kind = st.kind,
			label = st.label,
			lane = st.lane,
			session = nil,
			hw = nil,
			screen = nil,
			prompt = nil,
			anchor = Vector3.new(x, y, z),
			dirty = true,
			lastBroadcast = -math.huge,
			seen = {},
		}
		local def = MinigameService.GAMES[st.game]
		if def then
			station.session = Session.new(def.rules, {
				lobbySeconds = def.opts.lobbySeconds,
				turnSeconds = def.opts.turnSeconds,
				doneSeconds = def.opts.doneSeconds,
				seed = (opts.seed or 1) + i,
			})
		end
		if st.kind == "lane" and lanes then
			local laneModel = lanes:FindFirstChild(`Lane{st.lane}`)
			if laneModel then
				local pair = AlleyLayout.pairOf(st.lane :: number)
				station.hw = BowlingLane.new({
					lane = st.lane,
					model = laneModel,
					place = self.place,
					tunnel = opts.tunnels and opts.tunnels[pair],
					physics = opts.physics,
				})
			end
			local sb = boards and boards:FindFirstChild(`Lane{st.lane}`)
			local screen = sb and sb:FindFirstChild("Screen")
			station.screen = screen and screen:FindFirstChild("Score")
		elseif st.kind == "dartboard" then
			local dm = games and games:FindFirstChild("Dartboard")
			station.hw = Dartboard.new({ place = self.place, model = dm })
			local sbPart = dm and dm:FindFirstChild("ScoreBoard")
			station.screen = sbPart and sbPart:FindFirstChild("Score")
		elseif st.kind == "fortune" then
			station.hw = FortuneCabinet.new({ model = games and games:FindFirstChild("Fortune") })
		end
		if promptFolder then
			local part = Instance.new("Part")
			part.Name = st.id
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
			prompt:SetAttribute("Minigame", st.game)
			prompt:SetAttribute("Station", st.id)
			prompt.Parent = part
			part.Parent = promptFolder
			station.prompt = prompt
			table.insert(
				self.conns,
				prompt.Triggered:Connect(function(player: Player)
					local ok, err = pcall(function()
						self:join(player, st.id)
					end)
					if not ok then
						warn(`[Minigames] join {st.id} failed: {err}`)
					end
				end)
			)
		end
		self.stations[st.id] = station
		table.insert(self.order, st.id)
	end
	if self.net then
		self.net:on("Minigame.Input", function(player: any, payload: any)
			local ok, err = pcall(function()
				local good, why = self:input(player, payload)
				if not good and why then
					self:fire(player, { kind = "refused", text = why })
				end
			end)
			if not ok then
				warn(`[Minigames] input failed: {err}`)
			end
		end)
	end
	for _, id in self.order do
		self:_refresh(self.stations[id])
	end
	return self
end

-- Outbound ------------------------------------------------------------------------------------------------------
function MinigameService.fire(self: any, player: any, payload: { [string]: any })
	if typeof(player) == "Instance" then
		if self.net and (player :: Player).Parent ~= nil then
			self.net:fire(player, "Minigame.State", payload)
		end
	elseif type(player) == "table" then
		player.events = player.events or {}
		table.insert(player.events, payload)
	end
end

function MinigameService._seated(self: any, st: Station): { any }
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

local function promptTexts(st: Station): (string, string)
	local s = st.session
	if st.kind == "pool" or st.kind == "bumper_pool" then
		return "Play (soon)", st.label
	elseif st.kind == "pinball" then
		return "Play (out of order)", "Pinball"
	elseif st.kind == "fortune" then
		return "Pull the lever", "Madame Acorna (free)"
	end
	local verb = if st.kind == "lane" then "Bowl" else "Play darts"
	if s == nil then
		return verb, st.label
	end
	local n = 0
	for i = 1, #s.seats do
		if not s.gone[i] then
			n += 1
		end
	end
	if s.phase == "idle" or s.phase == "done" then
		return verb, `{st.label} - open`
	elseif s.phase == "lobby" then
		return "Join", `{st.label} - {n}/{s.rules.def.seats} joining`
	end
	return "In use", `{st.label} - game on ({n} playing)`
end

function MinigameService._refresh(self: any, st: Station)
	st.dirty = false
	local s = st.session
	local prompt = st.prompt
	if prompt then
		local action, object = promptTexts(st)
		prompt.ActionText = action
		prompt.ObjectText = object
	end
	if s == nil then
		return
	end
	local view = Session.view(s, self.clock)
	if st.screen then
		local ok, err = pcall(function()
			if st.kind == "lane" then
				if s.phase == "idle" then
					Scoreboard.idle(st.screen, `LANE {st.lane}`, "OPEN - walk up and press E")
				else
					Scoreboard.bowling(st.screen, st.lane :: number, view)
				end
			elseif st.kind == "dartboard" then
				Scoreboard.darts(st.screen, view)
			end
		end)
		if not ok then
			warn(`[Minigames] scoreboard {st.id}: {err}`)
		end
	end
	for _, p in self:_seated(st) do
		local seat = Session.seatOf(s, p)
		local ready = true
		if st.kind == "lane" and st.hw then
			ready = st.hw:ready()
		end
		self:fire(p, {
			kind = "state",
			station = st.id,
			game = st.game,
			label = st.label,
			lane = st.lane,
			you = seat,
			ready = ready,
			view = view,
		})
	end
	st.lastBroadcast = self.clock
end

-- Seats -----------------------------------------------------------------------------------------------------------
function MinigameService.stationOf(self: any, player: any): string?
	return self.playerStation[player]
end

function MinigameService.sessionOf(self: any, id: string): any?
	local st = self.stations[id]
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
	local soon = MinigameService.SOON[st.kind]
	if soon then
		self:fire(player, { kind = "refused", text = soon })
		return false, soon
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
	-- the fortune machine: every press is a pull (a fresh one-seat game)
	if st.kind == "fortune" then
		if st.hw and st.hw:busy() then
			local text = "Madame Acorna is still reading the last palm: one moment"
			self:fire(player, { kind = "refused", text = text })
			return false, text
		end
		if s.phase ~= "idle" then
			-- someone else's card is on the table; it belongs to whoever pulls now
			local others = self:_seated(st)
			for _, p in others do
				if p ~= player then
					self.playerStation[p] = nil
					self:fire(p, { kind = "left", station = id, why = "next" })
				end
			end
			Session.reset(s)
		end
	end
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
	})
	if st.kind == "fortune" then
		self:_pull(st, player)
	elseif s.phase == "playing" then
		self:_onStart(st)
	end
	st.dirty = true
	self:_refresh(st)
	return true
end

function MinigameService.leave(self: any, player: any, why: string?)
	local id = self.playerStation[player]
	if id == nil then
		return
	end
	self.playerStation[player] = nil
	local st = self.stations[id] :: Station
	st.seen[player] = nil
	local s = st.session
	local wasTurn = Session.turnKey(s) == player
	Session.leave(s, player, self.clock)
	if st.kind == "lane" and st.hw and wasTurn then
		st.hw:hold(nil)
	end
	if s.phase == "idle" and st.hw then
		if st.kind == "lane" then
			st.hw:reset(true)
		elseif st.kind == "dartboard" then
			st.hw:clear()
			st.hw:idle(true)
		end
	end
	self:fire(player, { kind = "left", station = id, why = why or "left" })
	st.dirty = true
end

function MinigameService._onStart(self: any, st: Station)
	if st.kind == "lane" and st.hw then
		st.hw:reset(true)
	elseif st.kind == "dartboard" and st.hw then
		st.hw:clear()
		st.hw:idle(false)
	end
	self:_broadcast(st, { kind = "event", station = st.id, text = "Game on!", big = true })
end

function MinigameService._pull(self: any, st: Station, player: any)
	local s = st.session
	local ok = Session.apply(s, player, "pull", nil, self.clock)
	if not ok then
		return
	end
	local r = s.result
	if r and st.hw then
		st.hw:pull(r)
	end
	self:fire(player, {
		kind = "fortune",
		station = st.id,
		reels = r and r.reels,
		line = r and r.line,
		card = r and r.kind,
		reveal = FortuneCabinet.SHOW_SECONDS,
	})
end

-- Inputs ---------------------------------------------------------------------------------------------------------
local function num(v: any, default: number): number
	if type(v) == "number" and v == v and v ~= math.huge and v ~= -math.huge then
		return v
	end
	return default
end

function MinigameService.input(self: any, player: any, payload: any): (boolean, string?)
	if type(payload) ~= "table" then
		return false, nil
	end
	local id = payload.gameId
	local verb = payload.verb
	local args = if type(payload.args) == "table" then payload.args else {}
	local st = self.stations[id] :: Station?
	if st == nil or st.session == nil then
		return false, nil
	end
	if self.playerStation[player] ~= id then
		return false, "You are not at that game: walk up and press E"
	end
	local s = st.session
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
		if st.kind == "fortune" then
			return self:join(player, id)
		end
		local ok, why = Session.again(s, self.clock)
		if ok then
			self:_onStart(st)
			st.dirty = true
		end
		return ok, if ok then nil else why
	elseif verb == "mode" then
		local ok, why = Session.apply(s, player, "mode", { args[1] }, self.clock)
		st.dirty = true
		return ok, if ok then nil else why
	elseif verb == "pull" and st.kind == "fortune" then
		return self:join(player, id)
	end
	if s.phase ~= "playing" then
		return false, if s.phase == "lobby" then "Waiting for the game to start (Space starts it now)" else nil
	end
	if Session.turnKey(s) ~= player then
		return false, "Not your turn yet"
	end
	if verb == "release" and st.kind == "lane" then
		local lane = st.hw
		if lane == nil then
			return false, "this lane has no hardware"
		end
		if not lane:ready() then
			return false, "Wait for the pinsetter and the ball"
		end
		local ok, why = lane:release({
			offset = num(args[1], 0),
			angle = num(args[2], 0),
			power = num(args[3], 0.6),
			spin = num(args[4], 0),
		})
		if ok then
			Session.touch(s, self.clock)
			self:_broadcast(st, { kind = "rolled", station = st.id })
			st.dirty = true
		end
		return ok, why
	elseif verb == "throw" and st.kind == "dartboard" then
		local board = st.hw
		if board and board:busy() then
			return false, nil
		end
		local seat = Session.seatOf(s, player)
		local ok, why = Session.apply(s, player, "throw", { num(args[1], 0), num(args[2], 0), num(args[3], 0.5) }, self.clock)
		if ok then
			self:_afterDart(st, seat)
		end
		return ok, why
	end
	return false, nil
end

function MinigameService._afterDart(self: any, st: Station, seat: number?)
	local s = st.session
	local g = s.game
	local hit = g and g.state.lastHit
	if hit and st.hw then
		st.hw:land(hit.x, hit.y, seat)
		local text: string
		if hit.event == "bust" then
			text = `BUST! ({hit.label})`
		elseif hit.event == "checkout" then
			text = `CHECKOUT! {hit.label}`
		elseif hit.event == "win" then
			text = `{hit.label} - closes it out!`
		elseif hit.event == "closed" then
			text = `{hit.label} - closed`
		else
			text = if hit.points > 0 then `{hit.label}  (+{hit.points})` else hit.label
		end
		self:_broadcast(st, {
			kind = "dart",
			station = st.id,
			x = hit.x,
			y = hit.y,
			label = hit.label,
			points = hit.points,
			event = hit.event,
			text = text,
			seat = hit.seat,
		})
		-- the turn passed (three darts or a bust): pull the darts out after a beat
		if g.state.dart == 1 and not g.state.done then
			st.clearAt = self.clock + 1.6
		end
	end
	st.dirty = true
end

-- debugRoll: a scripted pinfall on a lane (Luau Execution; tests) through the same path as a real roll.
function MinigameService.debugRoll(self: any, id: string, pins: number): (boolean, string?)
	local st = self.stations[id] :: Station?
	if st == nil or st.kind ~= "lane" or st.hw == nil then
		return false, "no lane"
	end
	if st.session.phase ~= "playing" then
		return false, "no game"
	end
	if not st.hw:ready() then
		return false, "lane busy"
	end
	return st.hw:debugRoll(pins)
end

-- Per frame -------------------------------------------------------------------------------------------------------
local ROLL_TEXT: { [string]: string } = { strike = "STRIKE!", spare = "SPARE!" }

function MinigameService._laneStep(self: any, st: Station, dt: number)
	local lane = st.hw
	if lane == nil then
		return
	end
	lane:step(dt)
	local s = st.session
	local pins = lane:takeResult()
	if pins ~= nil and s.phase == "playing" then
		local g = s.game
		local before = Bowling.standing(g.state)
		local ballNo = g.state.ballOf[g.state.seat]
		local ok = Session.apply(s, "server", "roll", { math.min(pins, before) }, self.clock)
		local event = g.state.lastEvent or "next"
		local rack = if g.state.done then "full" else Bowling.rackFor(g.state)
		lane:setRack(rack, not self.opts.physics and self.opts.instantRack == true)
		local text = ROLL_TEXT[event]
		if text == nil then
			if pins == 0 then
				text = if ballNo == 1 then "Gutter ball..." else "Missed it"
			elseif event == "gameover" then
				text = `{pins} - that's the game!`
			else
				text = `{pins} pin{if pins == 1 then "" else "s"}`
			end
		end
		self:_broadcast(st, {
			kind = "event",
			station = st.id,
			text = text,
			big = event == "strike" or event == "spare",
			pins = pins,
			ok = ok,
		})
		st.dirty = true
	elseif pins ~= nil then
		lane:setRack("full", true)
	end
	-- the ball in the bowler's hand once the lane is ready
	if lane:ready() and s.phase == "playing" then
		local key = Session.turnKey(s)
		local body = key and self.opts.bodyOf and self.opts.bodyOf(key)
		if body ~= lane.heldBy then
			lane.heldBy = body
			lane:hold(body)
			st.dirty = true
		elseif body and lane.held == nil then
			lane:hold(body)
		end
	elseif lane.heldBy ~= nil and lane:ready() then
		lane.heldBy = nil
		lane:hold(nil)
	end
	if lane.wasReady ~= lane:ready() then
		lane.wasReady = lane:ready()
		st.dirty = true
	end
end

function MinigameService.step(self: any, dt: number)
	self.clock += dt
	for _, id in self.order do
		local st = self.stations[id] :: Station
		local s = st.session
		if s == nil then
			continue
		end
		if st.kind == "lane" then
			self:_laneStep(st, dt)
		elseif st.hw then
			st.hw:step(dt)
		end
		if st.kind == "dartboard" and st.clearAt and self.clock >= st.clearAt then
			st.clearAt = nil
			st.hw:clear()
		end
		local busy = (st.kind == "lane" and st.hw ~= nil and not st.hw:ready())
			or (st.kind == "dartboard" and st.hw ~= nil and st.hw:busy())
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
			elseif e.kind == "timeout" then
				self:_broadcast(st, { kind = "event", station = st.id, text = `{s.names[e.seat] or "?"} took too long: turn skipped` })
				if st.kind == "lane" and st.hw then
					st.hw:hold(nil)
					st.hw.heldBy = nil
				end
			elseif e.kind == "removed" and e.key ~= nil then
				self.playerStation[e.key] = nil
				st.seen[e.key] = nil
				self:fire(e.key, { kind = "left", station = st.id, why = "idle" })
			elseif e.kind == "done" then
				local r = s.result
				local w = r and r.winner and s.names[r.winner]
				self:_broadcast(st, {
					kind = "event",
					station = st.id,
					text = if w and #s.seats > 1 then `{w} wins!` else "Game over!",
					big = true,
				})
				if st.kind == "dartboard" and st.hw then
					st.clearAt = self.clock + 3
				end
			elseif e.kind == "reset" then
				if st.kind == "lane" and st.hw then
					st.hw:reset(true)
				elseif st.kind == "dartboard" and st.hw then
					st.hw:clear()
					st.hw:idle(true)
				end
			end
			st.dirty = true
		end
		-- anyone the session dropped (reset, end card timed out) hears they are off the table
		for p in before do
			if Session.seatOf(s, p) == nil and self.playerStation[p] == id then
				self.playerStation[p] = nil
				st.seen[p] = nil
				self:fire(p, { kind = "left", station = id, why = "finished" })
				st.dirty = true
			end
		end
		-- seated players who stopped being a person, or wandered off
		for _, p in self:_seated(st) do
			local canPlay = self.opts.canPlay
			local ok = true
			if canPlay then
				ok = (canPlay(p))
			end
			local body = self.opts.bodyOf and self.opts.bodyOf(p)
			local far = false
			if body and body.PrimaryPart then
				far = (body.PrimaryPart.Position - st.anchor).Magnitude > MinigameService.WANDER
			end
			if not ok or far then
				self:leave(p, if far then "too far" else "not a person")
			end
		end
		if st.dirty or (s.phase ~= "idle" and self.clock - st.lastBroadcast >= 1) then
			self:_refresh(st)
		end
	end
end

function MinigameService.stop(self: any)
	for _, c in self.conns do
		c:Disconnect()
	end
	table.clear(self.conns)
end

return MinigameService
