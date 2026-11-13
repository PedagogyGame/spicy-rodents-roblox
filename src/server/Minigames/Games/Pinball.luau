--!strict
-- ServerScriptService.Server.Minigames.Games.Pinball
-- Pinball's server half on the minigame framework (Server/Minigames/ServerGame): one Table per cabinet in the
-- bowling alley's games room (stations pinball_1..3, each its own machine by `variant`). THE SERVER IS THE SCORE
-- OF RECORD, and it never runs ahead of the player: the player's own machine plays the model at once and sends
-- its input log about ten times a second ("log": fromTick, toTick, the changes packed, its Replay.sum); this
-- Table hands each segment to the rules (Pinball/Rules.game, through ctx.apply so the turn clock is fed), whose
-- replay is the game (Pinball/Replay.feed). Around that:
--   * the machine: when a game starts the station names its machine to the rules (server verb "machine"), and
--     everyone following the machine is sent its first SNAPSHOT (Pinball/Wire: the replay itself, a few kB);
--   * the clock: the server's time (ctx.now) goes to the replay before every segment and CLOCK_EVERY besides
--     (server verb "clock"): a segment more than Replay.AHEAD_SECONDS ahead of it is kept here and fed again
--     when the clock has caught up (never refused back to the player); a ball whose log has fallen more than
--     Replay.BEHIND_SECONDS behind is played out by the rules and the game is marked late;
--   * the relay: every segment the replay took goes on at once to the other seated players and to the
--     watchers (everyone within WATCH studs of the cabinet, looked for every LOOK seconds), as "pinball". They
--     play it on their own copies (Replay.follow) and draw about half a second behind;
--   * resync by snapshot ("pinball_sync"): to the player whose log the replay says has drifted (a sum that is
--     not the server's, a segment past the end of a ball, a gap in the log), to everyone whenever the server
--     played by itself (the replay's epoch rose: a ball skipped by the turn clock, a player who left, a ball
--     that lapsed), and to each watcher as they walk up;
--   * an animal that lands on the cabinet (ctx.opts.animals) thumps the glass: the rules grant one thump
--     (server verb "thump") and the player whose ball it is is told to let it into their log ("pinball_thump");
--   * a player whose buttons have not changed for IDLE seconds (a ball left on the plunger, a cradle held for
--     ever while others wait) is taken off: their ball is played out and their score kept (rules.gone);
--   * the board: each machine keeps its best scores for as long as the server runs (Pinball/HighScores; only a
--     fair game, Replay.fair, takes a place), each player's best on each machine is ctx.town.best's
--     ("pinball_<variant>"), and the board is written on the cabinet (attribute "Best") for every client;
--   * an idle machine: nothing is sent to anyone while nobody is seated, except "pinball_idle" to each person
--     who walks up near it (their client runs the attract show from the clock and the board).
-- Nothing on the cabinet is moved here: every client near it draws the ball, the flippers and the lamps from
-- its own copy of the game (Client/Minigames/Pinball/Cabinet). With no cabinet on the site (another game's
-- rig, a bare test) hw is nil and nobody is looked for or sent anything but the seated players' own messages.
-- Interface: a ServerGame { game = "pinball", new(ctx) -> Table }; WATCH, LOOK, CLOCK_EVERY, IDLE, ANIMAL_EVERY,
--   SYNC_AGAIN, IDLE_WORDS, THUMP_WORDS; Table.hw { model }; Table:replay() -> any; Table.board;
--   Table:debug("drain") (the ball in play is played out dead, as the turn clock would: for the engine checks)

local Import = require("../../Import")
local Cabinet =
	Import.shared("Minigames/Pinball/Cabinet") :: typeof(require("../../../shared/Minigames/Pinball/Cabinet"))
local HighScores =
	Import.shared("Minigames/Pinball/HighScores") :: typeof(require("../../../shared/Minigames/Pinball/HighScores"))
local Replay = Import.shared("Minigames/Pinball/Replay") :: typeof(require("../../../shared/Minigames/Pinball/Replay"))
local Rules = Import.shared("Minigames/Pinball/Rules") :: typeof(require("../../../shared/Minigames/Pinball/Rules"))
local Tables = Import.shared("Minigames/Pinball/Tables") :: typeof(require("../../../shared/Minigames/Pinball/Tables"))
local Wire = Import.shared("Minigames/Pinball/Wire") :: typeof(require("../../../shared/Minigames/Pinball/Wire"))
local AlleyLayout =
	Import.shared("Attractions/AlleyLayout") :: typeof(require("../../../shared/Attractions/AlleyLayout"))
local ServerGame = require("../ServerGame")

local Game = {}
Game.game = "pinball"
Game.WATCH = 40 -- studs from the cabinet within which a bystander is sent the game
Game.LOOK = 0.5 -- seconds between two looks for who stands near
Game.CLOCK_EVERY = 0.25 -- seconds between two tellings of the time to the replay (besides one before every segment)
Game.IDLE = 60 -- seconds without a change of the buttons before the player whose ball it is is taken off
Game.ANIMAL_EVERY = 0.25
Game.SYNC_AGAIN = 1 -- seconds: a player put right is not put right again sooner (their segments on the way)
Game.IDLE_WORDS = "You were taken off the pinball machine: nothing was pressed for a minute"
Game.THUMP_WORDS = "Something landed on the machine and thumped the glass!"

local function isComputer(key: any): boolean
	return type(key) == "table" and key.ai == true
end

local function hardware(root: Instance?, index: number?): any
	local room = root and root:FindFirstChild("GamesRoom")
	local model = room and index and room:FindFirstChild(Cabinet.model(index))
	if model == nil then
		return nil
	end
	return { model = model }
end

function Game.new(ctx: ServerGame.Ctx): ServerGame.Table
	local variant = ctx.station.variant
	local tableId = Tables.forVariant(variant) or Tables.IDS[1]
	local tbl = Tables.need(tableId)
	local self: any = {
		ctx = ctx,
		hw = hardware(ctx.root, ctx.station.index),
		board = HighScores.new(tableId),
		games = 0, -- games started here (each message carries its game's number)
		n = 0, -- segments relayed in this game
		epoch = 0, -- the replay's epoch as last seen
		pending = {}, -- segments refused "ahead", fed again when the clock catches up: { key, args }
		watchers = {}, -- people near, not seated: key -> true
		clockAt = -math.huge,
		lookAt = -math.huge,
		animalAt = -math.huge,
		over = nil, -- the last game's places on the board, by seat
		syncedAt = {}, -- key -> when they were last sent a snapshot
		waited = 0, -- segments that had to wait for the clock (for the record)
	}

	local function replay(): any
		local g = ctx.session.game
		if g == nil or (ctx.session.phase ~= "playing" and ctx.session.phase ~= "done") then
			return nil
		end
		return Rules.replay(g.state)
	end
	function self.replay(_self: any): any
		return replay()
	end

	local function writeBoard()
		local hw = self.hw
		if hw then
			hw.model:SetAttribute("Best", table.concat(HighScores.lines(self.board), "\n"))
		end
	end
	writeBoard()

	-- everyone who follows the game: the seated people and the watchers
	local function followers(): { any }
		local out = {}
		for _, key in ctx.seated() do
			if not isComputer(key) then
				table.insert(out, key)
			end
		end
		for key in self.watchers do
			if ctx.seatOf(key) == nil then
				table.insert(out, key)
			end
		end
		return out
	end

	local function sync(key: any, why: string)
		local r = replay()
		if r == nil then
			return
		end
		self.syncedAt[key] = ctx.now()
		ctx.send(key, {
			kind = "pinball_sync",
			g = self.games,
			n = self.n,
			why = why,
			table = tableId,
			snap = Wire.snapshot(r),
		})
	end

	local function syncAll(why: string)
		for _, key in followers() do
			sync(key, why)
		end
	end

	-- the replay played by itself (its epoch rose): every copy is put right
	local function checkEpoch()
		local r = replay()
		if r and r.epoch ~= self.epoch then
			self.epoch = r.epoch
			syncAll("epoch")
		end
	end

	local function clock()
		if ctx.session.phase ~= "playing" then
			return
		end
		self.clockAt = ctx.now()
		ctx.server("clock", { ctx.now() })
	end

	-- one segment of a player's log into the replay. Returns false when it must wait for the clock.
	local function feed(key: any, args: { any }): boolean
		local r = replay()
		if r == nil or ctx.session.phase ~= "playing" then
			return true
		end
		clock()
		r = replay()
		if r == nil or ctx.session.phase ~= "playing" then
			return true
		end
		local seat = ctx.seatOf(key)
		local from = ServerGame.num(args[1], -1)
		local ok, why = ctx.apply(key, "log", { args[1], args[2], args[3], args[4] })
		if ok then
			self.n += 1
			local msg = {
				kind = "pinball",
				g = self.games,
				n = self.n,
				seat = seat,
				from = args[1],
				to = args[2],
				packed = args[3],
			}
			for _, other in followers() do
				if other ~= key then
					ctx.send(other, table.clone(msg))
				end
			end
			if r.drift then
				r.drift = false
				sync(key, "drift")
			end
			-- (no ctx.dirty() here: the scorecard is redrawn by the service's own second-by-second state, the
			-- backglass on every screen is drawn from the game itself; a ball changing hands is the Session's turn)
			checkEpoch()
			return true
		end
		if why == "ahead" then
			return false
		end
		-- A segment that does not follow on (a part of the log never came, or the player's machine is on a game
		-- the server has left behind), or that the replay will not take (a thump it never granted): the player
		-- carries on from the server's game. Not more than once a SYNC_AGAIN: the segments already on their way
		-- when a snapshot went out do not follow on either, and need no second one. (A segment for a ball that
		-- is no longer theirs needs nothing: the snapshot that moved the game on has gone to them already.)
		if
			why ~= "not your ball"
			and why ~= "the game is over"
			and ctx.now() - (self.syncedAt[key] or -math.huge) >= Game.SYNC_AGAIN
		then
			sync(key, if why == "out of order" then (if from > r.tick then "gap" else "behind") else tostring(why))
		end
		return true
	end

	local function drain()
		while #self.pending > 0 do
			local item = self.pending[1]
			if ctx.seatOf(item.key) == nil then
				table.remove(self.pending, 1)
				continue
			end
			if not feed(item.key, item.args) then
				return
			end
			table.remove(self.pending, 1)
		end
	end

	-- A second Space or Play again that crossed the first on the way is taken without words.
	function self.command(_self: any, player: any, verb: string, args: { any }): (boolean, boolean?, string?)
		if verb ~= "log" then
			local phase = ctx.session.phase
			if ctx.seatOf(player) ~= nil then
				if verb == "start" and phase == "playing" then
					return true, true
				elseif verb == "again" and (phase == "lobby" or phase == "playing") then
					return true, true
				end
			end
			return false
		end
		if ctx.seatOf(player) == nil or ctx.session.phase ~= "playing" or replay() == nil then
			return true, true -- (a segment that arrived after the end: no words)
		end
		if #self.pending > 0 then
			table.insert(self.pending, { key = player, args = table.clone(args) })
			return true, true
		end
		if not feed(player, args) then
			self.waited += 1
			table.insert(self.pending, { key = player, args = table.clone(args) })
		end
		return true, true
	end

	-- who stands near the cabinet: newcomers are sent the game as it stands, or told the machine is idle
	local function lookAround()
		self.lookAt = ctx.now()
		local near: { [any]: boolean } = {}
		local r = replay()
		for _, person in ctx.town.people() do
			if ctx.seatOf(person.key) == nil and not isComputer(person.key) then
				local d = Vector3.new(person.x, person.y, person.z) - ctx.anchor
				if d.Magnitude <= Game.WATCH then
					near[person.key] = true
					if not self.watchers[person.key] then
						if r ~= nil and ctx.session.phase == "playing" then
							self.watchers[person.key] = true
							sync(person.key, "watch")
						else
							ctx.send(person.key, { kind = "pinball_idle", table = tableId })
						end
					end
				end
			end
		end
		self.watchers = near
	end

	-- an animal on the cabinet thumps the glass
	local function animals()
		self.animalAt = ctx.now()
		local source = ctx.opts.animals
		local r = replay()
		if source == nil or r == nil or Replay.over(r) then
			return
		end
		local ok, list = pcall(source)
		if not ok or type(list) ~= "table" then
			return
		end
		local index = ctx.station.index or 1
		local px, pd = Cabinet.at(index)
		local body = Cabinet.BODY
		for _, a in list do
			if type(a) ~= "table" or type(a.x) ~= "number" then
				continue
			end
			local X, Y, D = AlleyLayout.toLocal(ctx.place, a.x, a.y, a.z)
			local on = math.abs(X - px) <= body.half + 0.3
				and D >= pd + Cabinet.BACKBOX.back - 0.3
				and D <= pd + body.front + 0.3
				and Y >= Cabinet.PF_Y - 0.2
				and Y <= Cabinet.BACKBOX.y1 + 2
			if on then
				local granted = ctx.server("thump")
				if granted then
					local up = ctx.session.seats[r.m.up]
					if up and not isComputer(up) then
						ctx.send(up, { kind = "pinball_thump", g = self.games })
					end
					for _, key in followers() do
						ctx.send(key, { kind = "event", text = Game.THUMP_WORDS })
					end
				end
				return
			end
		end
	end

	function self.step(_self: any, _dt: number)
		local phase = ctx.session.phase
		if phase == "playing" and replay() ~= nil then
			if ctx.now() - self.clockAt >= Game.CLOCK_EVERY then
				clock()
				checkEpoch()
			end
			drain()
			checkEpoch()
			local r = replay()
			if r and ctx.session.phase == "playing" and Replay.idleSeconds(r) > Game.IDLE then
				local key = ctx.session.seats[r.m.up]
				if key and not isComputer(key) then
					ctx.leave(key, "idle", Game.IDLE_WORDS)
				end
			end
			if self.hw and ctx.now() - self.animalAt >= Game.ANIMAL_EVERY then
				animals()
			end
		end
		if self.hw and ctx.now() - self.lookAt >= Game.LOOK then
			lookAround()
		end
	end

	local function names(): string
		local list = {}
		for _, key in ctx.seated() do
			local seat = ctx.seatOf(key)
			if seat then
				table.insert(list, ctx.nameOf(seat))
			end
		end
		return table.concat(list, ", ")
	end

	function self.event(_self: any, e: ServerGame.Event)
		if e.kind == "start" then
			self.games += 1
			self.n = 0
			self.over = nil
			table.clear(self.pending)
			ctx.server("machine", { variant or tableId })
			clock()
			local r = replay()
			self.epoch = if r then r.epoch else 0
			syncAll("start")
			ctx.dirty()
		elseif e.kind == "left" or e.kind == "removed" or e.kind == "timeout" or e.kind == "skipped" then
			checkEpoch()
		elseif e.kind == "done" then
			local s = ctx.session
			local result = s.result
			local r = replay()
			if result and r then
				local places = {}
				for seat = 1, #s.seats do
					local score = (result.scores and result.scores[seat]) or 0
					local place = HighScores.add(self.board, s.names[seat] or "?", score, result.fair)
					places[seat] = place or 0
					local key = s.seats[seat]
					if not isComputer(key) then
						ctx.town.best(key, `pinball_{variant or tableId}`, score, false)
					end
				end
				self.over = places
				writeBoard()
				local msg = {
					kind = "pinball_over",
					g = self.games,
					board = HighScores.lines(self.board),
					places = places,
					fair = result.fair ~= false,
				}
				for _, key in followers() do
					ctx.send(key, table.clone(msg))
				end
			end
		elseif e.kind == "reset" then
			table.clear(self.pending)
			-- the people near hear that the machine is idle again (one by one: nobody is seated now)
			if self.hw then
				for _, person in ctx.town.people() do
					local d = Vector3.new(person.x, person.y, person.z) - ctx.anchor
					if d.Magnitude <= Game.WATCH and not isComputer(person.key) then
						ctx.send(person.key, { kind = "pinball_idle", table = tableId })
					end
				end
			end
			table.clear(self.watchers)
		end
	end

	function self.state(_self: any, _player: any, seat: number?): { [string]: any }?
		return {
			machine = tableId,
			board = if self.over then HighScores.lines(self.board) else nil,
			place = if self.over and seat then self.over[seat] else nil,
		}
	end

	function self.prompt(_self: any): (string?, string?)
		if ctx.session.phase == "playing" then
			return "In use", `{tbl.title} - in use by {names()}: watch the ball`
		end
		return nil, nil
	end

	function self.doneText(_self: any, view: { [string]: any }): string?
		local r = view.result
		if r == nil or r.scores == nil then
			return nil
		end
		if #view.seats <= 1 then
			return `GAME OVER  {HighScores.commas(r.scores[1] or 0)}`
		end
		local w = r.winner and view.seats[r.winner]
		if w then
			return `{w.name} wins with {HighScores.commas(r.scores[r.winner] or 0)}`
		end
		return "GAME OVER: a tie"
	end

	-- For the engine checks: the ball in play is played out dead (as the turn clock does), and everyone is put
	-- right from the server's game.
	function self.debug(_self: any, what: any): (boolean, string?)
		local r = replay()
		if r == nil or ctx.session.phase ~= "playing" then
			return false, "no game is on"
		end
		if what ~= "drain" then
			return false, "only a drain can be scripted"
		end
		Replay.skip(r)
		checkEpoch()
		ctx.dirty()
		return true
	end

	return self
end

return Game
