--!strict
-- tests/lib/FakeGames.luau: tiny games that exist only in specs, registered at run time through the three
-- registries (Shared/Minigames/Games, Server/Minigames/ServerGames, Client/Minigames/ClientGames) exactly as a
-- real game's three lines would register it. They prove the framework names no game (nothing under src/ has
-- heard of them) and they are the smallest worked example of each KIND of game the registry carries:
--   test_coin     flow "turns"   call the coin, two calls each: hardware found by name under the site's Model,
--                                a server-decided outcome told to everyone, computer players (the next one, or
--                                one asked for by name from a button), a world scoreboard, a controller with
--                                its own keys, camera shot, scorecard and end card
--   test_rally    flow "live"    a ball between two ends: rules.step moves it, either seat may hit at any
--                                moment, a per-hit message to the controllers stamped on the SHARED clock
--                                (ctx.stamp on both sides), a computer opponent that plays in real time, a
--                                server verb for a named seat, the idle clock without turns, and a second
--                                prompt at the far end that joins the same game (StationDef.joins)
--   test_machine  flow "solo"    one seat, a ball under gravity and a flipper: the client runs the fixed-step
--                                sim at once and keeps a log of its inputs by tick; ten times a second it
--                                sends the next segment of that log, and the server replays each segment up
--                                to the tick the client declared (never by its own clock) and settles the
--                                score; watchers are sent the pose
--   test_match    flow "match"   two sides against the clock: computers fill the sides at the start, a
--                                player joins while it is on (a computer makes room when the arena is full),
--                                the arena replaces the walk-away radius, the game keeps Q and gamepad B for
--                                itself (a crouch that slows the walk through ctx.pace), the result is a
--                                winning side with its own words, and the arena can roll into its next match
--   test_plain    a Spec and rules and nothing else: no server half, no client half (the framework's defaults)
--   test_soon     a Spec that says `soon`: a station that turns people away with words
-- All stand on one site that no data knows, "test_hall" (SITE, PLACE): hand `sites = { [SITE] = PLACE }` and
-- `furnish = FakeGames.furnish` to tests/lib/MinigameRig.
-- Requiring this file registers the games (once). Require it BEFORE anything that requires Shared/Net/Schemas:
-- the wire's verb list is read from the registry when that module loads.
-- Interface: SITE; PLACE; STATIONS { coin, rally, rallyFar, machine, match, plain, soon }; furnish(roots,
--   places); Coin, Rally, Machine, Match, Plain (the rules); MachineSim { new, advance, pack, unpack, TICK,
--   SEGMENT, SLACK, MAX_SEGMENT }; seen (what the games' `watch` hooks were handed: { game, msg, place });
--   controllers[game] (the controller last made); tables[stationId] (the server Table last made)
local AlleyLayout = require("@shared/Attractions/AlleyLayout")
local GameSpec = require("@shared/Minigames/GameSpec")
local Games = require("@shared/Minigames/Games")
local ServerGames = require("@server/Minigames/ServerGames")
local ClientGames = require("@client/Minigames/ClientGames")
local FakeEngine = require("@tests/lib/FakeEngine")
local roblox = require("@lune/roblox")

local FakeGames = {}

FakeGames.SITE = "test_hall"
FakeGames.PLACE = { x = 500, z = -200, floorY = 10, yaw = 0.4 } :: GameSpec.Place
FakeGames.STATIONS = {
	coin = "test_coin_1",
	rally = "test_rally_1",
	rallyFar = "test_rally_far", -- the far end's prompt: it joins test_rally_1
	machine = "test_machine_2",
	match = "test_match_1",
	plain = "test_plain_1",
	soon = "test_soon_1",
}
FakeGames.seen = {} :: { { game: string, msg: any, place: any } }
FakeGames.controllers = {} :: { [string]: any }
FakeGames.tables = {} :: { [string]: any }

local SITE = FakeGames.SITE
-- where each station stands in the hall (X across, D into it); the match is a long way from the rest
local AT = {
	coin = { x = 0, d = 0 },
	rally = { x = 30, d = 0 },
	machine = { x = 60, d = 0 },
	plain = { x = 90, d = 0 },
	soon = { x = 120, d = 0 },
	match = { x = 0, d = 400 },
}

local function stationsOf(
	game: string,
	id: string,
	label: string,
	at: { x: number, d: number },
	more: { [string]: any }?
): (sites: { [string]: GameSpec.Place }) -> { GameSpec.StationDef }
	return function(sites: { [string]: GameSpec.Place }): { GameSpec.StationDef }
		if sites[SITE] == nil then
			return {}
		end
		local def: any = { id = id, game = game, label = label, site = SITE, x = at.x, y = 3, d = at.d }
		for k, v in more or {} do
			def[k] = v
		end
		return { def }
	end
end

local function cf(place: GameSpec.Place, x: number, y: number, d: number): any
	return roblox.CFrame.new(AlleyLayout.toWorld(place, x, y, d))
end

-- What a bake would have put under the site's Model: each game's furniture, its moving parts named.
function FakeGames.furnish(roots: { [string]: any }, places: { [string]: GameSpec.Place })
	local root, place = roots[SITE], places[SITE]
	if root == nil then
		return
	end
	local coinTable = FakeEngine.model("CoinTable", cf(place, AT.coin.x, 3, AT.coin.d + 2), root)
	FakeEngine.part("Coin", cf(place, AT.coin.x, 3.1, AT.coin.d + 2), coinTable)
	FakeEngine.part("Board", cf(place, AT.coin.x, 6, AT.coin.d + 4), coinTable)
	local court = FakeEngine.model("RallyCourt", cf(place, AT.rally.x, 0, AT.rally.d), root)
	FakeEngine.part("Ball", cf(place, AT.rally.x, 3, AT.rally.d + 5), court)
	local machine = FakeEngine.model("Machine2", cf(place, AT.machine.x, 0, AT.machine.d), root)
	FakeEngine.part("Ball", cf(place, AT.machine.x, 3, AT.machine.d + 2), machine)
end

-- test_coin: turns ------------------------------------------------------------------------------------------------
local Coin = {}
FakeGames.Coin = Coin
Coin.def = {
	game = "test_coin",
	title = "Coin toss",
	class = "no_stakes",
	seats = 2,
	authority = "server",
	money = "none",
}
Coin.CALLS = 2
Coin.verbs = { flip = true }
Coin.serverVerbs = { flip = true } -- the table flips; a player only calls

function Coin.init(seats: number, _seed: number): any
	return { n = seats, turn = 1, calls = table.create(seats, 0), score = table.create(seats, 0), last = false }
end

function Coin.result(state: any): any
	for i = 1, state.n do
		if state.calls[i] < Coin.CALLS then
			return nil
		end
	end
	local winner: number? = nil
	local best, tied = -1, false
	for i = 1, state.n do
		if state.score[i] > best then
			best, winner, tied = state.score[i], i, false
		elseif state.score[i] == best then
			tied = true
		end
	end
	return { done = true, scores = table.clone(state.score), winner = if tied then nil else winner }
end

function Coin.turn(state: any): number?
	return if Coin.result(state) then nil else state.turn
end

local function coinNext(state: any)
	state.calls[state.turn] += 1
	state.turn = state.turn % state.n + 1
end

function Coin.input(state: any, seat: number, verb: string, args: { any }?): (boolean, string?)
	local call, side = args and args[1], args and args[2]
	if verb ~= "flip" or seat ~= state.turn then
		return false, "Not your call"
	end
	if (call ~= "heads" and call ~= "tails") or (side ~= "heads" and side ~= "tails") then
		return false, "Call heads or tails"
	end
	if call == side then
		state.score[seat] += 1
	end
	state.last = { seat = seat, call = call, side = side }
	coinNext(state)
	return true
end

function Coin.skipTurn(state: any)
	state.last = false
	coinNext(state)
end

function Coin.view(state: any): { [string]: any }
	local seats = {}
	for i = 1, state.n do
		seats[i] = { score = state.score[i], calls = state.calls[i] }
	end
	return { seats = seats, last = state.last }
end

local CoinSpec: GameSpec.Spec = {
	game = "test_coin",
	title = "Coin toss",
	rules = Coin,
	flow = "turns",
	session = { lobbySeconds = 6, turnSeconds = 10, doneSeconds = 8 },
	verbs = { "call" }, -- (not one of the wire's first verbs: it reaches the Net schema by being listed here)
	prompt = { action = "Flip a coin", busy = "wait for the next toss" },
	words = { unit = "call", removed = "You were taken off the coin table" },
	computers = { { name = "Heads-up Hal", bias = "heads" }, { name = "Tails Tina", bias = "tails" } },
	stations = stationsOf("test_coin", FakeGames.STATIONS.coin, "Coin table", AT.coin, { reach = 12 }),
}

local function coinServer(ctx: any): any
	local self: any = { ctx = ctx, flips = 0, events = {}, draws = 0 }
	local model = ctx.root and ctx.root:FindFirstChild("CoinTable")
	local coin = model and model:FindFirstChild("Coin")
	local board = model and model:FindFirstChild("Board")
	local home = coin and coin.CFrame
	self.hw = { coin = coin, board = board }
	FakeGames.tables[ctx.station.id] = self

	local function flip(seat: number, call: string, forced: string?): (boolean, string?)
		local side = forced or (if ctx.rng.next() < 0.5 then "heads" else "tails")
		-- (a turn-based game's own verbs go in as "server": the Session knows whose turn it is)
		local ok, why = ctx.apply("server", "flip", { call, side })
		if not ok then
			return false, why
		end
		self.flips += 1
		if coin then
			coin.CFrame = if side == "heads" then home else home * roblox.CFrame.Angles(math.pi, 0, 0)
			coin:SetAttribute("Side", side)
		end
		ctx.everyone({ kind = "coin_flip", seat = seat, call = call, side = side, n = self.flips })
		ctx.dirty()
		return true
	end

	function self.input(_self: any, _player: any, seat: number, verb: string, args: { any }): (boolean?, string?)
		if verb ~= "call" then
			return nil
		end
		local call = args[1]
		if call ~= "heads" and call ~= "tails" then
			return false, "Call heads or tails"
		end
		return flip(seat, call)
	end

	function self.computer(_self: any, key: any, seat: number): number?
		-- (what the Spec says of a computer rides on its key)
		flip(seat, key.bias or "tails")
		return 0
	end

	function self.event(_self: any, e: any)
		table.insert(self.events, e.kind)
		if (e.kind == "reset" or e.kind == "start") and coin then
			coin.CFrame = home
			coin:SetAttribute("Side", nil)
		end
	end

	function self.sig(_self: any, view: any): any
		return view.game and view.game.last
	end

	function self.screen(_self: any, view: any)
		self.draws += 1
		if board then
			local parts = {}
			for i, seat in view.seats do
				local g = view.game and view.game.seats[i]
				table.insert(parts, `{seat.name} {if g then g.score else 0}`)
			end
			board:SetAttribute("Text", if #parts > 0 then table.concat(parts, " - ") else "COIN TOSS")
		end
	end

	function self.state(_self: any, _player: any, _seat: number?): { [string]: any }?
		return { flips = self.flips }
	end

	function self.debug(_self: any, side: string): (boolean, string?)
		local g = ctx.session.game
		local seat = g and Coin.turn(g.state)
		if seat == nil then
			return false, "no call is due"
		end
		return flip(seat, "heads", side)
	end

	return self
end

local function coinClient(): any
	local Key = roblox.Enum.KeyCode
	return {
		game = "test_coin",
		help = {
			how = { "Call the coin: two calls each, the most right calls wins." },
			keys = { "Z  heads", "X  tails", "Q  leave" },
		},
		title = function(msg: any): string
			return `Coin toss - {msg.label}`
		end,
		buttons = function(phase: string, _view: any): { { string } }?
			if phase == "joined" or phase == "lobby" then
				-- ("verb:word": the verb with one word. Here: the computer player of that name)
				return {
					{ "start", "Start now" },
					{ "addai", "Add a computer" },
					{ "addai:Tails Tina", "Add Tails Tina" },
					{ "leave", "Leave (Q)" },
				}
			elseif phase == "done" then
				return { { "again", "Play again" }, { "leave", "Leave (Q)" } }
			end
			return { { "leave", "Leave (Q)" } }
		end,
		new = function(ctx: any): any
			local self: any = { ctx = ctx, mine = false, messages = {}, refused = 0, states = 0, stopped = false }
			FakeGames.controllers.test_coin = self
			local uis = (game :: any):GetService("UserInputService")
			local conn = uis.InputBegan:Connect(function(io: any, processed: boolean)
				if processed or not self.mine then
					return
				end
				if io.KeyCode == Key.Z then
					ctx.send("call", { "heads" })
				elseif io.KeyCode == Key.X then
					ctx.send("call", { "tails" })
				end
			end)
			function self.onState(_self: any, msg: any)
				self.states += 1
				local view = msg.view
				local mine = view.phase == "playing" and view.turn == msg.you
				if mine and not self.mine then
					-- my call: the table's own shot, and the keys are the game's
					ctx.controls(false)
					local p = ctx.place
					local eye = roblox.Vector3.new(AlleyLayout.toWorld(p, AT.coin.x, 7, AT.coin.d - 4))
					local look = roblox.Vector3.new(AlleyLayout.toWorld(p, AT.coin.x, 3, AT.coin.d + 2))
					ctx.camera(roblox.CFrame.lookAt(eye, look), 50, true)
				elseif self.mine and not mine then
					ctx.controls(true)
					ctx.releaseCamera()
				end
				self.mine = mine
				ctx.ui:status(
					if mine
						then "Your call: Z heads, X tails"
						elseif view.phase == "playing" then "Waiting for the other call"
						else ""
				)
			end
			function self.onMessage(_self: any, msg: any, watched: any)
				table.insert(self.messages, { kind = msg.kind, watched = watched })
				if msg.kind == "coin_flip" then
					ctx.sound("test_coin.flip")
				end
			end
			function self.onRefused(_self: any, _msg: any)
				self.refused += 1
			end
			function self.stop(_self: any)
				self.stopped = true
				conn:Disconnect()
			end
			return self
		end,
		card = function(frame: any, view: any, you: number?, kit: any)
			for i, seat in view.seats do
				local g = view.game and view.game.seats[i]
				kit.label(
					frame,
					`{seat.name}{if i == you then " (you)" else ""}: {if g then g.score else 0} right`,
					UDim2.new(1, -8, 0, 24),
					UDim2.fromOffset(4, 4 + (i - 1) * 26)
				)
			end
		end,
		cardSig = function(view: any): any
			return view.game and view.game.last
		end,
		endCard = function(view: any, _you: number?): any
			local r = view.result
			local rows = {}
			for i, seat in view.seats do
				table.insert(rows, {
					seat = i,
					name = seat.name,
					gone = seat.gone,
					total = r.scores[i],
					place = if r.winner == i or r.winner == nil then 1 else 2,
				})
			end
			return {
				title = "COIN TOSS",
				line = if r.winner then `{view.seats[r.winner].name} called it best` else "All square",
				rows = rows,
			}
		end,
		kinds = { "coin_flip" },
		watch = function(msg: any, place: any): any
			table.insert(FakeGames.seen, { game = "test_coin", msg = msg, place = place })
			return { flip = msg.n }
		end,
		sounds = { ["test_coin.flip"] = "" },
		words = { finished = "The coin table is free again." },
	}
end

-- test_rally: live ------------------------------------------------------------------------------------------------
local Rally = {}
FakeGames.Rally = Rally
Rally.def = {
	game = "test_rally",
	title = "Rally",
	class = "shared_table",
	seats = 2,
	authority = "server",
	money = "none",
}
Rally.LENGTH = 10 -- seat 1 defends 0, seat 2 defends LENGTH
Rally.REACH = 3
Rally.SPEED = 2.5
Rally.TO = 3
Rally.verbs = { hit = true, fault = true }
Rally.serverVerbs = { fault = true }

function Rally.init(seats: number, _seed: number): any
	return { n = seats, pos = Rally.LENGTH / 2, dir = 1, score = { 0, 0 }, hits = 0, forfeit = false }
end

local function rallyPoint(state: any, to: number)
	state.score[to] += 1
	state.pos = Rally.LENGTH / 2
	state.dir = if to == 1 then 1 else -1 -- served at whoever lost the point
end

-- the game moves by itself: the ball flies; an end it passes is a point to the other seat
function Rally.step(state: any, dt: number)
	state.pos += state.dir * Rally.SPEED * dt
	if state.pos >= Rally.LENGTH then
		if state.n < 2 then
			state.pos, state.dir = Rally.LENGTH, -1 -- alone: the far end is a wall
		else
			rallyPoint(state, 1)
		end
	elseif state.pos <= 0 then
		rallyPoint(state, 2)
	end
end

function Rally.input(state: any, seat: number, verb: string, _args: { any }?): (boolean, string?)
	if verb == "fault" then
		rallyPoint(state, if seat == 1 then 2 else 1)
		return true
	end
	local coming = if seat == 1 then state.dir < 0 else state.dir > 0
	local near = if seat == 1 then state.pos <= Rally.REACH else state.pos >= Rally.LENGTH - Rally.REACH
	if not coming then
		return false, "The ball is going away from you"
	elseif not near then
		return false, "Too early: wait for the ball"
	end
	state.dir = -state.dir
	state.hits += 1
	return true
end

function Rally.gone(state: any, seat: number)
	state.forfeit = seat
end

function Rally.result(state: any): any
	local winner: number? = nil
	if state.forfeit and state.n > 1 then
		winner = if state.forfeit == 1 then 2 else 1
	elseif state.score[1] >= Rally.TO then
		winner = 1
	elseif state.score[2] >= Rally.TO then
		winner = 2
	end
	if winner == nil then
		return nil
	end
	return { done = true, scores = { state.score[1], state.score[2] }, winner = winner, hits = state.hits }
end

function Rally.view(state: any): { [string]: any }
	return { pos = state.pos, dir = state.dir, score = { state.score[1], state.score[2] }, hits = state.hits }
end

local RallySpec: GameSpec.Spec = {
	game = "test_rally",
	title = "Rally",
	rules = Rally,
	flow = "live",
	session = { lobbySeconds = 5, doneSeconds = 6, idleSeconds = 6 },
	verbs = { "hit" },
	prompt = { action = "Play a rally" },
	words = { removed = "You were taken off the court: you stood still too long" },
	computers = { { name = "Wall", reach = 2 } },
	-- one court, a prompt at each end: the far one is only a second way in to the same game
	stations = function(sites: { [string]: GameSpec.Place }): { GameSpec.StationDef }
		if sites[SITE] == nil then
			return {}
		end
		return {
			{
				id = FakeGames.STATIONS.rally,
				game = "test_rally",
				label = "Rally court",
				site = SITE,
				x = AT.rally.x,
				y = 3,
				d = AT.rally.d,
			},
			{
				id = FakeGames.STATIONS.rallyFar,
				game = "test_rally",
				label = "Rally court (far end)",
				site = SITE,
				x = AT.rally.x,
				y = 3,
				d = AT.rally.d + Rally.LENGTH,
				joins = FakeGames.STATIONS.rally,
			},
		}
	end,
}

local function rallyServer(ctx: any): any
	local self: any = { ctx = ctx, legs = 0 }
	local court = ctx.root and ctx.root:FindFirstChild("RallyCourt")
	local ball = court and court:FindFirstChild("Ball")
	self.hw = { ball = ball }
	FakeGames.tables[ctx.station.id] = self

	local function leg(seat: number)
		local g = ctx.session.game
		self.legs += 1
		-- one message per hit: every controller draws the same flight from it (no stream of positions). It is
		-- stamped on the SHARED clock (ctx.stamp), which the client reads too: ctx.now() is the service's own
		-- and means nothing on a client
		ctx.broadcast({ kind = "rally_leg", seat = seat, from = g.state.pos, dir = g.state.dir, at = ctx.stamp() })
		ctx.dirty()
	end

	-- which prompt each player came in by (the court's own, or the far end's)
	self.via = {}
	function self.join(_self: any, player: any, via: any): (boolean, string?)
		self.via[player] = via.id
		return true
	end

	function self.input(_self: any, player: any, seat: number, verb: string, _args: { any }): (boolean?, string?)
		if verb ~= "hit" then
			return nil
		end
		local ok, why = ctx.apply(player, "hit")
		if ok then
			leg(seat)
		end
		return ok, why
	end

	-- the computer opponent plays in real time, here (nobody has a turn for the service to hand it)
	function self.step(_self: any, _dt: number)
		local g = ctx.session.game
		if ctx.session.phase ~= "playing" or g == nil then
			return
		end
		for _, key in ctx.seated() do
			local seat = ctx.seatOf(key)
			if type(key) == "table" and key.ai and seat then
				local s = g.state
				local coming = if seat == 1 then s.dir < 0 else s.dir > 0
				local dist = if seat == 1 then s.pos else Rally.LENGTH - s.pos
				if coming and dist <= key.reach and ctx.apply(key, "hit") then
					leg(seat)
				end
			end
		end
		if ball then
			ball.CFrame = cf(ctx.place, AT.rally.x, 3, AT.rally.d + g.state.pos)
		end
	end

	-- (a server verb for a named seat: nobody's turn says whose it is)
	function self.debug(_self: any, what: string, seat: number): (boolean, string?)
		if what ~= "fault" then
			return false, "only a fault can be scripted"
		end
		return ctx.server("fault", {}, seat)
	end

	return self
end

local function rallyClient(): any
	local Key = roblox.Enum.KeyCode
	return {
		game = "test_rally",
		help = {
			how = { "Hit the ball back when it reaches your end. First to three." },
			keys = { "F  hit", "Q  leave" },
		},
		new = function(ctx: any): any
			local self: any = { ctx = ctx, legs = {}, refused = {}, view = nil }
			FakeGames.controllers.test_rally = self
			local uis = (game :: any):GetService("UserInputService")
			-- (a rally keeps the player's own legs and camera: no ctx.controls(false), no ctx.camera)
			local conn = uis.InputBegan:Connect(function(io: any, processed: boolean)
				if not processed and io.KeyCode == Key.F and self.view and self.view.phase == "playing" then
					ctx.send("hit")
				end
			end)
			function self.onState(_self: any, msg: any)
				self.view = msg.view
				local g = msg.view.game
				ctx.ui:status(if g then `{g.score[1]} - {g.score[2]}` else "")
			end
			function self.onMessage(_self: any, msg: any, _watched: any)
				if msg.kind == "rally_leg" then
					table.insert(self.legs, msg)
				end
			end
			-- where the ball is NOW, from the last hit's one message: its stamp is on the shared clock, and so
			-- is ctx.stamp() here
			function self.ballNow(_self: any): number?
				local last = self.legs[#self.legs]
				if last == nil then
					return nil
				end
				return last.from + last.dir * Rally.SPEED * (ctx.stamp() - last.at)
			end
			function self.onRefused(_self: any, msg: any)
				table.insert(self.refused, msg.text)
			end
			function self.stop(_self: any)
				conn:Disconnect()
			end
			return self
		end,
	}
end

-- test_machine: solo ----------------------------------------------------------------------------------------------
-- The machine's fixed-step model, the same on both sides. The client steps it at once for its own ball and keeps
-- a log of what it did (the tick of each flip). It does NOT send a message per input: Minigame.Input carries 20
-- messages a second and a dropped one is never answered, and one lost flip would make the server's game a
-- different game. About ten times a second it sends the next SEGMENT of the log as one "log" message:
-- { fromTick, toTick, packed flips } (arguments are at most 8 numbers, booleans or strings of 200 characters, so
-- the flips travel packed in one string). The server replays each segment as it arrives, up to the tick the
-- client declared and never by a clock of its own: a client that falls behind (one long frame) is replayed a
-- little later and loses nothing. The server refuses only a segment that does not start where the last one
-- ended, or that claims more ticks than the time since the launch allows (plus SLACK).
local MachineSim = {}
FakeGames.MachineSim = MachineSim
MachineSim.TICK = 1 / 60
MachineSim.SEGMENT = 6 -- ticks before the client sends the next segment: ten messages a second
MachineSim.SLACK = 30 -- ticks a client may be ahead of the server's own count of the time since the launch
MachineSim.MAX_SEGMENT = 120 -- the longest segment the server takes in one message (a client catching up)

-- The flips of a segment as one string: each flip's tick counted from the segment's first, "2,5".
function MachineSim.pack(flips: { number }, fromTick: number): string
	local out = {}
	for _, tick in flips do
		table.insert(out, tostring(tick - fromTick))
	end
	return table.concat(out, ",")
end

-- The ticks that flip in (fromTick, toTick], or nil if the string is not a packed segment.
function MachineSim.unpack(packed: any, fromTick: number, toTick: number): { [number]: boolean }?
	local flips: { [number]: boolean } = {}
	if type(packed) ~= "string" then
		return nil
	end
	local last = 0
	for word in string.gmatch(packed, "[^,]+") do
		local n = tonumber(word)
		if n == nil or n % 1 ~= 0 or n <= last or fromTick + n > toTick then
			return nil
		end
		last = n
		flips[fromTick + n] = true
	end
	return flips
end

function MachineSim.new(): any
	return { tick = 0, y = 10, vy = 0, score = 0, over = false }
end

function MachineSim.advance(sim: any, flip: boolean)
	if sim.over then
		return
	end
	sim.tick += 1
	if flip and sim.y <= 3 and sim.vy < 0 then
		sim.vy = 14
		sim.score += 10
	end
	sim.vy -= 20 * MachineSim.TICK
	sim.y += sim.vy * MachineSim.TICK
	if sim.y <= 0 then
		sim.y, sim.over = 0, true
	end
end

local Machine = {}
FakeGames.Machine = Machine
Machine.def = {
	game = "test_machine",
	title = "Machine",
	class = "no_stakes",
	seats = 1,
	authority = "server",
	money = "none",
}
Machine.verbs = { plunge = true, log = true, machine_settle = true }
Machine.serverVerbs = { machine_settle = true }

function Machine.init(_seats: number, _seed: number): any
	return { launched = false, lastTick = 0, final = false }
end

function Machine.input(state: any, _seat: number, verb: string, args: { any }?): (boolean, string?)
	if verb == "plunge" then
		if state.launched then
			return false, "The ball is already in play"
		end
		state.launched = true
		return true
	elseif verb == "log" then
		-- (the Table has replayed the segment; the rules only keep how far the game has been played)
		local to = args and args[2]
		if not state.launched then
			return false, "Launch the ball first (Space)"
		end
		if type(to) ~= "number" or to <= state.lastTick then
			return false, "That part of the game arrived out of order"
		end
		state.lastTick = to
		return true
	end
	state.final = { score = args and args[1], ticks = args and args[2] }
	return true
end

function Machine.result(state: any): any
	local f = state.final
	if not f then
		return nil
	end
	return { done = true, scores = { f.score }, winner = 1, ticks = f.ticks }
end

function Machine.view(state: any): { [string]: any }
	return { launched = state.launched }
end

local MachineSpec: GameSpec.Spec = {
	game = "test_machine",
	title = "Machine",
	rules = Machine,
	flow = "solo",
	session = { lobbySeconds = 0, doneSeconds = 5, idleSeconds = 3 },
	verbs = { "plunge", "log" },
	prompt = { action = "Play", object = "The machine" },
	words = { start = "", removed = "The machine timed out" },
	stations = stationsOf(
		"test_machine",
		FakeGames.STATIONS.machine,
		"Machine 2",
		AT.machine,
		{ index = 2, variant = "retro" }
	),
}

local function machineServer(ctx: any): any
	local self: any = { ctx = ctx, sim = nil, t0 = 0, sent = 0, segments = 0 }
	local model = ctx.root and ctx.root:FindFirstChild(`Machine{ctx.station.index}`)
	local ball = model and model:FindFirstChild("Ball")
	self.hw = { ball = ball }
	FakeGames.tables[ctx.station.id] = self

	-- One segment of the player's log: checked, then replayed to the tick it declares.
	local function replay(player: any, from: any, to: any, packed: any): (boolean, string?)
		local sim = self.sim
		if sim == nil then
			return false, "Launch the ball first (Space)"
		end
		if
			type(from) ~= "number"
			or type(to) ~= "number"
			or from % 1 ~= 0
			or to % 1 ~= 0
			or from ~= sim.tick -- it starts where the last one ended
			or to <= from
			or to - from > MachineSim.MAX_SEGMENT
		then
			return false, "That part of the game arrived out of order"
		end
		-- the only use of the server's clock: a bound on how far the game can have got since the launch (a
		-- duration, so ctx.now() is the right clock for it). Being BEHIND that is always fine
		local possible = math.floor((ctx.now() - self.t0) / MachineSim.TICK) + MachineSim.SLACK
		if to > possible then
			return false, "That part of the game is ahead of the clock"
		end
		local flips = MachineSim.unpack(packed, from, to)
		if flips == nil then
			return false, "That part of the game could not be read"
		end
		-- (through the Session: an accepted segment is what keeps the idle clock from taking the seat)
		local ok, why = ctx.apply(player, "log", { from, to })
		if not ok then
			return false, why
		end
		self.segments += 1
		while sim.tick < to and not sim.over do
			MachineSim.advance(sim, flips[sim.tick + 1] == true)
			-- watchers: the pose a few times a second (reliable; nobody needs every tick)
			if sim.tick % 15 == 0 then
				self.sent += 1
				ctx.everyone({ kind = "machine_pose", y = sim.y, score = sim.score, tick = sim.tick })
			end
		end
		if ball then
			ball.CFrame = cf(ctx.place, AT.machine.x, 3 + sim.y, AT.machine.d + 2)
		end
		if sim.over then
			self.sim = nil
			ctx.server("machine_settle", { sim.score, sim.tick }, 1)
		end
		return true
	end

	function self.input(_self: any, player: any, _seat: number, verb: string, args: { any }): (boolean?, string?)
		if verb == "plunge" then
			local ok, why = ctx.apply(player, "plunge")
			if ok then
				self.sim, self.t0, self.sent, self.segments = MachineSim.new(), ctx.now(), 0, 0
			end
			return ok, why
		elseif verb == "log" then
			return replay(player, args[1], args[2], args[3])
		end
		return nil
	end

	function self.event(_self: any, e: any)
		if e.kind == "reset" or e.kind == "start" then
			self.sim = nil
		end
	end

	function self.doneText(_self: any, view: any): string?
		return `Ball lost: {view.result.scores[1]} points`
	end

	return self
end

local function machineClient(): any
	local Key = roblox.Enum.KeyCode
	return {
		game = "test_machine",
		help = { how = { "Keep the ball up." }, keys = { "Space  launch", "F  flip", "Q  leave" } },
		title = function(msg: any): string
			return `Machine {msg.index} ({msg.variant})`
		end,
		placeless = true,
		new = function(ctx: any): any
			local self: any = {
				ctx = ctx,
				sim = nil,
				flip = false,
				acc = 0,
				refused = {},
				final = nil,
				poses = 0,
				flips = {}, -- the log not sent yet: the tick of each flip
				sentTo = 0, -- the tick the server has been told up to
			}
			FakeGames.controllers.test_machine = self
			local uis = (game :: any):GetService("UserInputService")
			local run = (game :: any):GetService("RunService")
			local conns = {
				uis.InputBegan:Connect(function(io: any, processed: boolean)
					if processed then
						return
					end
					if io.KeyCode == Key.Space and self.sim == nil and self.final == nil then
						-- the ball is in play on this screen at once; the server starts its copy when this lands
						self.sim, self.acc, self.sentTo = MachineSim.new(), 0, 0
						table.clear(self.flips)
						ctx.controls(false)
						ctx.send("plunge")
					elseif io.KeyCode == Key.F and self.sim and not self.sim.over then
						-- flip on the next tick here. Nothing is sent now: the flip goes into the log
						self.flip = true
					end
				end),
				run.RenderStepped:Connect(function(dt: number)
					local sim = self.sim
					if sim == nil or sim.over then
						return
					end
					self.acc += dt
					while self.acc >= MachineSim.TICK - 1e-9 and not sim.over do
						self.acc -= MachineSim.TICK
						if self.flip then
							table.insert(self.flips, sim.tick + 1)
						end
						MachineSim.advance(sim, self.flip)
						self.flip = false
					end
					-- the next segment of the log, once enough ticks have gone by (or the ball is lost): at
					-- most one message a frame and about ten a second, however hard the keys are mashed
					if sim.tick > self.sentTo and (sim.over or sim.tick - self.sentTo >= MachineSim.SEGMENT) then
						ctx.send("log", { self.sentTo, sim.tick, MachineSim.pack(self.flips, self.sentTo) })
						self.sentTo = sim.tick
						table.clear(self.flips)
					end
					ctx.ui:status(`Score {sim.score}`)
				end),
			}
			function self.onState(_self: any, msg: any)
				local r = msg.view.result
				if msg.view.phase == "done" and r then
					self.final = r.scores[1]
				end
			end
			function self.onMessage(_self: any, msg: any, _watched: any)
				if msg.kind == "machine_pose" then
					self.poses += 1
				end
			end
			function self.onRefused(_self: any, msg: any)
				table.insert(self.refused, msg.text)
			end
			function self.stop(_self: any)
				for _, c in conns do
					c:Disconnect()
				end
			end
			return self
		end,
		kinds = { "machine_pose" },
		watch = function(msg: any, place: any): any
			table.insert(FakeGames.seen, { game = "test_machine", msg = msg, place = place })
			return nil
		end,
	}
end

-- test_match: a team match ----------------------------------------------------------------------------------------
local Match = {}
FakeGames.Match = Match
Match.def = {
	game = "test_match",
	title = "Tag match",
	class = "arena",
	seats = 6,
	authority = "server",
	money = "none",
	lateJoin = true,
}
Match.SECONDS = 8
Match.ARENA = 150 -- half the arena's side: far more than the walk-away radius
Match.verbs = { tag = true }
Match.serverVerbs = { tag = true }

function Match.teamOf(seat: number): string
	return if seat % 2 == 1 then "red" else "blue"
end

function Match.init(seats: number, _seed: number): any
	return { n = seats, left = Match.SECONDS, tags = { red = 0, blue = 0 }, out = {} }
end

function Match.step(state: any, dt: number)
	state.left -= dt
end

function Match.join(state: any, seat: number)
	state.n = math.max(state.n, seat)
	state.out[seat] = nil
end

function Match.gone(state: any, seat: number)
	state.out[seat] = true
end

function Match.input(state: any, seat: number, _verb: string, args: { any }?): (boolean, string?)
	local victim = args and args[1]
	if type(victim) ~= "number" or victim < 1 or victim > state.n or victim % 1 ~= 0 then
		return false, "Nobody there"
	end
	if Match.teamOf(victim) == Match.teamOf(seat) then
		return false, "That is your own side"
	end
	if state.out[victim] or state.out[seat] then
		return false, "They have left the match"
	end
	state.tags[Match.teamOf(seat)] += 1
	return true
end

function Match.result(state: any): any
	if state.left > 0 then
		return nil
	end
	local red, blue = state.tags.red, state.tags.blue
	local side = if red > blue then "red" elseif blue > red then "blue" else nil
	local winners, scores = {}, {}
	for seat = 1, state.n do
		scores[seat] = state.tags[Match.teamOf(seat)]
		if side and Match.teamOf(seat) == side and not state.out[seat] then
			table.insert(winners, seat)
		end
	end
	return {
		done = true,
		scores = scores,
		winners = winners,
		side = side or "draw",
		text = if side then `The {side} side wins {math.max(red, blue)}-{math.min(red, blue)}` else "A draw",
	}
end

function Match.view(state: any): { [string]: any }
	return { left = math.max(0, math.ceil(state.left)), red = state.tags.red, blue = state.tags.blue }
end

local MatchSpec: GameSpec.Spec = {
	game = "test_match",
	title = "Tag match",
	rules = Match,
	flow = "match",
	session = { lobbySeconds = 5, doneSeconds = 6 },
	verbs = { "fire" },
	prompt = { action = "Join the match" },
	computers = { { name = "Bot A" }, { name = "Bot B" }, { name = "Bot C" } },
	fill = 4,
	stations = stationsOf("test_match", FakeGames.STATIONS.match, "Tag arena", AT.match),
}

local function matchServer(ctx: any): any
	local self: any = { ctx = ctx, botAt = 0, tags = 0, rollOn = false, nextAt = nil }
	FakeGames.tables[ctx.station.id] = self

	-- A person at a full arena: a computer makes room. The service seats the person in the seat it left (the
	-- vacated seat first), so the sides stay as they were.
	function self.join(_self: any, player: any, _via: any): (boolean, string?)
		local s = ctx.session
		if s.phase ~= "playing" or ctx.seatOf(player) ~= nil or #ctx.seated() < s.rules.def.seats then
			return true
		end
		for _, key in ctx.seated() do
			if type(key) == "table" and key.ai then
				ctx.removeComputer(key)
				return true
			end
		end
		return false, "The arena is full of people: wait for the next match"
	end

	local function tag(seat: number, victim: number): (boolean, string?)
		local ok, why = ctx.server("tag", { victim }, seat)
		if ok then
			self.tags += 1
			ctx.broadcast({ kind = "match_tag", by = seat, victim = victim })
		end
		return ok, why
	end

	function self.input(_self: any, _player: any, seat: number, verb: string, args: { any }): (boolean?, string?)
		if verb ~= "fire" then
			return nil
		end
		return tag(seat, tonumber(args[1]) or 0)
	end

	-- after the start the match is the Table's: here the bots
	function self.step(_self: any, _dt: number)
		-- the arena rolls into its next match by itself (rollOn): two seconds of end card, then the same people
		-- and computers again, through the service's own play-again path
		if ctx.session.phase == "done" and self.rollOn then
			self.nextAt = self.nextAt or (ctx.now() + 2)
			if ctx.now() >= self.nextAt then
				self.nextAt = nil
				ctx.again()
			end
			return
		end
		if ctx.session.phase ~= "playing" or ctx.now() < self.botAt then
			return
		end
		self.botAt = ctx.now() + 1
		for _, key in ctx.seated() do
			local seat = ctx.seatOf(key)
			if type(key) == "table" and key.ai and seat == 3 then
				tag(seat, 2) -- (one red bot, once a second)
			end
		end
	end

	function self.event(_self: any, e: any)
		if e.kind == "start" then
			self.botAt = ctx.now() + 1
		end
	end

	-- the arena, not the walk-away radius: anywhere inside the square is in the match
	function self.inPlay(_self: any, _player: any, body: any): boolean
		if body == nil or body.PrimaryPart == nil then
			return true
		end
		local p = body.PrimaryPart.Position
		local x, _, d = AlleyLayout.toLocal(ctx.place, p.X, p.Y, p.Z)
		return math.abs(x - AT.match.x) <= Match.ARENA and math.abs(d - AT.match.d) <= Match.ARENA
	end

	return self
end

local function matchClient(): any
	local Key = roblox.Enum.KeyCode
	return {
		game = "test_match",
		help = {
			how = { "Tag the other side before the clock runs out." },
			keys = { "C / gamepad B  crouch", "Leave with the button" },
		},
		placeless = true,
		-- The game's keys are read before the framework's: gamepad B crouches here and Q does nothing (leaving a
		-- match is a deliberate press of the button), so both are swallowed and the controller reads B itself.
		keys = { ButtonB = "", Q = "" },
		buttons = function(phase: string, _view: any): { { string } }?
			if phase == "joined" or phase == "lobby" then
				return { { "start", "Start now" }, { "leave", "Leave the match" } }
			elseif phase == "done" then
				return { { "again", "Play again" }, { "leave", "Leave the match" } }
			end
			return { { "leave", "Leave the match" } }
		end,
		new = function(ctx: any): any
			local self: any = { ctx = ctx, tags = 0, view = nil, you = nil, crouched = false }
			FakeGames.controllers.test_match = self
			local uis = (game :: any):GetService("UserInputService")
			-- a crouch: half the walking pace and no sprint while the key is down (the framework puts the pace
			-- back when the game closes, crouched or not)
			local function crouch(on: boolean)
				self.crouched = on
				if on then
					ctx.pace(0.5, false)
				else
					ctx.pace(nil, nil)
				end
			end
			local conns = {
				uis.InputBegan:Connect(function(io: any, processed: boolean)
					if not processed and (io.KeyCode == Key.C or io.KeyCode == Key.ButtonB) then
						crouch(true)
					end
				end),
				uis.InputEnded:Connect(function(io: any, _processed: boolean)
					if io.KeyCode == Key.C or io.KeyCode == Key.ButtonB then
						crouch(false)
					end
				end),
			}
			function self.onState(_self: any, msg: any)
				self.view, self.you = msg.view, msg.you
				local g = msg.view.game
				if g then
					ctx.ui:status(`Red {g.red} - Blue {g.blue}   {g.left} s`)
				end
			end
			function self.onMessage(_self: any, msg: any, _watched: any)
				if msg.kind == "match_tag" then
					self.tags += 1
				end
			end
			function self.stop(_self: any)
				for _, c in conns do
					c:Disconnect()
				end
			end
			return self
		end,
		endCard = function(view: any, _you: number?): any
			local r = view.result
			local rows = {}
			for i, seat in view.seats do
				table.insert(rows, {
					seat = i,
					name = seat.name,
					gone = seat.gone,
					side = string.upper(Match.teamOf(i)),
					total = r.scores[i],
					place = if table.find(r.winners, i) then 1 else 2,
				})
			end
			return {
				title = "FULL TIME",
				line = r.text,
				rows = rows,
				cols = {
					{ title = "", key = "place", x = 0.02, w = 0.07 },
					{ title = "PLAYER", key = "name", x = 0.1, w = 0.45 },
					{ title = "SIDE", key = "side", x = 0.56, w = 0.2 },
					{ title = "TAGS", key = "total", x = 0.78, w = 0.2, strong = true },
				},
				foot = "The arena reopens in %d s.",
			}
		end,
	}
end

-- test_plain: a Spec and its rules, nothing else ------------------------------------------------------------------------
local Plain = {}
FakeGames.Plain = Plain
Plain.def =
	{ game = "test_plain", title = "Tilt", class = "no_stakes", seats = 1, authority = "server", money = "none" }
Plain.verbs = { tilt = true }

function Plain.init(_seats: number, _seed: number): any
	return { tilts = 0 }
end

function Plain.input(state: any, _seat: number, _verb: string, _args: { any }?): (boolean, string?)
	state.tilts += 1
	return true
end

function Plain.result(state: any): any
	return if state.tilts >= 3 then { done = true, scores = { state.tilts }, winner = 1 } else nil
end

local PlainSpec: GameSpec.Spec = {
	game = "test_plain",
	title = "Tilt",
	rules = Plain,
	flow = "solo",
	session = { lobbySeconds = 0, doneSeconds = 5 },
	verbs = { "tilt" },
	prompt = { action = "Tilt it" },
	stations = stationsOf("test_plain", FakeGames.STATIONS.plain, "Tilt box", AT.plain),
}

local SoonSpec: GameSpec.Spec = {
	game = "test_soon",
	title = "Not yet",
	soon = "This one opens in a later build. Try the coin table!",
	flow = "turns",
	verbs = {},
	prompt = { action = "Play (soon)" },
	stations = stationsOf("test_soon", FakeGames.STATIONS.soon, "Covered table", AT.soon),
}

-- The three lines a real game adds, done at run time: one per registry.
if Games.get("test_coin") == nil then
	for _, spec in { CoinSpec, RallySpec, MachineSpec, MatchSpec, PlainSpec, SoonSpec } do
		Games.register(spec)
	end
	ServerGames.register({ game = "test_coin", new = coinServer })
	ServerGames.register({ game = "test_rally", new = rallyServer })
	ServerGames.register({ game = "test_machine", new = machineServer })
	ServerGames.register({ game = "test_match", new = matchServer })
	ClientGames.register(coinClient())
	ClientGames.register(rallyClient())
	ClientGames.register(machineClient())
	ClientGames.register(matchClient())
end

return FakeGames
