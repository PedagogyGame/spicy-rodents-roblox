--!strict
-- ServerScriptService.Server.Minigames.Games.AirHockey
-- Air hockey's server half on the minigame framework (Server/Minigames/ServerGame): the Table around the owner's
-- AER / 01 table in the bowling alley's games room. THE SERVER DECIDES THE MATCH: the table's referee
-- (Shared/Minigames/AirHockey/Referee) steps the one simulation that counts (Shared/Minigames/AirHockey/Sim, his,
-- unchanged) from the players' hands, which arrive as logs by tick ("log": AirHockey/Wire), and the score the
-- rules keep is the referee's.
--   Ends: the prompt you pressed is the end you asked for (the Glacier end's is the table's own station, the
--     Ember end's joins it); the first seat gets its wish, the second the other end, with words if it wished the
--     same one.
--   The computer: when a match starts with one person, the computer of the lobby's difficulty (the Spec's Lounge,
--     Club, Pro) takes the other end. A person who presses a prompt while it plays takes its place at once, at
--     its end, mid-match; a person who leaves a two-person match hands their end to the computer.
--   The stream: every stretch of ticks the referee decides goes out as one "air_hockey" message (with the whole
--     state at its end) to the seated and to everyone standing within WATCH studs: their clients replay it
--     through the same simulation, so a watcher sees the same match. Nothing is sent while nobody is seated.
--   A log that has lost a segment on the way is not refused with words: that player is sent the tick their log
--     is expected from ("air_hockey_seat" with again = true) and their Seat sends it again from there. A player
--     whose hand keeps arriving too late to be waited for (two people, a slow line) is told so in words.
--   Between two people a press of the serve button is passed on to the other player the moment it arrives
--     ("air_hockey_press"): the puck leaves Sim.SERVE_LEAD after the press, on the same tick on both screens.
--   The hardware (GamesRoom.AirHockey: Puck, MalletGlacier, MalletEmber, ScoreBoard) is found by name; where it
--     is missing the Table still runs the match and touches nothing. The clients draw the puck and the mallets
--     every frame from their own replay; the server only moves its own copies ten times a second, so that the
--     world is right for someone who was sent nothing, and puts them home when the table resets.
-- Interface: a ServerGame { game = "air_hockey", new(ctx) -> Table }; Table.hw { model, puck, mallets, labels,
--   prints (each end's score label in the bed) };
--   Table.ref (the Referee while a match is on); ASK_EVERY; SLOW_WINDOW, SLOW_TICKS, SLOW_AGAIN, SLOW_WORDS;
--   Table:debug("goal", side) (the puck is put in front of that
--   end's opponent's goal, travelling in: the next ticks score it through the simulation's own goal line) and
--   Table:debug("score", glacier, ember); WATCH; MOVE_EVERY

local Import = require("../../Import")
local Layout =
	Import.shared("Minigames/AirHockey/Layout") :: typeof(require("../../../shared/Minigames/AirHockey/Layout"))
local Referee =
	Import.shared("Minigames/AirHockey/Referee") :: typeof(require("../../../shared/Minigames/AirHockey/Referee"))
local Rules = Import.shared("Minigames/AirHockey/Rules") :: typeof(require("../../../shared/Minigames/AirHockey/Rules"))
local Sim = Import.shared("Minigames/AirHockey/Sim") :: typeof(require("../../../shared/Minigames/AirHockey/Sim"))
local Wire = Import.shared("Minigames/AirHockey/Wire") :: typeof(require("../../../shared/Minigames/AirHockey/Wire"))
local ServerGame = require("../ServerGame")

local Game = {}
Game.game = "air_hockey"
Game.WATCH = 80 -- studs from the table within which a bystander is sent the match
Game.MOVE_EVERY = 0.1 -- seconds between the server's own moves of the puck and the mallets
Game.ASK_EVERY = 0.25 -- seconds between two requests to one player to send their log again
Game.SLOW_WINDOW = 2 -- seconds: a hand played without for more than SLOW_TICKS of them is told so...
Game.SLOW_TICKS = 120
Game.SLOW_AGAIN = 12 -- ...and not again for this long
Game.SLOW_WORDS = "Your connection is too slow for a live match: your mallet is arriving late"

local function isComputer(key: any): boolean
	return type(key) == "table" and key.ai == true
end

-- The table's parts, by name (nil where the site has no air hockey table).
local function hardware(root: Instance?): any
	local room = root and root:FindFirstChild("GamesRoom")
	local model = room and room:FindFirstChild(Layout.MODEL)
	if model == nil then
		return nil
	end
	local puck = model:FindFirstChild(Layout.PUCK)
	local glacier = model:FindFirstChild(Layout.MALLETS[0])
	local ember = model:FindFirstChild(Layout.MALLETS[1])
	if puck == nil or glacier == nil or ember == nil then
		return nil
	end
	local labels: { any } = {}
	local board = model:FindFirstChild(Layout.SCORE)
	if board then
		for _, d in board:GetDescendants() do
			if d.Name == "Score" then
				table.insert(labels, d)
			end
		end
	end
	local prints: { [number]: any } = {}
	for side = 0, 1 do
		local plate = model:FindFirstChild(Layout.SCORE_PRINTS[side])
		if plate then
			for _, d in plate:GetDescendants() do
				if d.Name == "Score" then
					prints[side] = d
				end
			end
		end
	end
	return {
		prints = prints,
		model = model,
		puck = puck,
		mallets = { [0] = glacier, [1] = ember },
		labels = labels,
	}
end

function Game.new(ctx: ServerGame.Ctx): ServerGame.Table
	local self: any = {
		ctx = ctx,
		hw = hardware(ctx.root),
		ref = nil, -- the Referee while a match is on
		games = 0,
		wish = {}, -- key -> the end whose prompt they pressed
		sideOf = {}, -- key -> the end they play
		watchers = {}, -- bystanders who are being sent the stream
		askedAt = {}, -- key -> when they were last asked to send their log again
		cutAt = 0, -- when the hands' lateness was last looked at, what it was then, and who was last told
		cutWas = { [0] = 0, [1] = 0 },
		toldSlow = {},
		watchAt = 0,
		movedAt = 0,
	}

	-- a piece of the hardware slid across the bed to a point of the model (its pivot is on its own axis; its
	-- height and its turn stay as the bake made them)
	local function slide(piece: any, x: number, y: number)
		local wx, _, wz = Layout.toWorld(ctx.place, x, y)
		local pivot = piece:GetPivot()
		piece:PivotTo(pivot + Vector3.new(wx - pivot.Position.X, 0, wz - pivot.Position.Z))
	end

	local function show(sim: any)
		local hw = self.hw
		if hw == nil then
			return
		end
		if sim == nil then
			-- at rest: where the bake stood them
			local hp, hm = Layout.HOME_PUCK, Layout.HOME_MALLET
			slide(hw.puck, hp[1], hp[2])
			slide(hw.mallets[0], hm[0][1], hm[0][2])
			slide(hw.mallets[1], hm[1][1], hm[1][2])
			return
		end
		slide(hw.puck, sim.px, sim.py)
		slide(hw.mallets[0], sim.p0x, sim.p0y)
		slide(hw.mallets[1], sim.p1x, sim.p1y)
	end

	local function nowTick(): number
		local ref = self.ref
		return if ref then math.floor((ctx.stamp() - ref.t0) / Sim.STEP) else 0
	end

	-- everyone who is sent the match: the seated people, and the bystanders near the table
	local function tell(payload: { [string]: any })
		payload.site = ctx.station.site
		for _, key in ctx.seated() do
			if not isComputer(key) then
				ctx.send(key, payload)
			end
		end
		for key in self.watchers do
			if ctx.seatOf(key) == nil then
				ctx.send(key, payload)
			end
		end
	end

	-- Who stands near enough to be sent the match (looked at twice a second). Someone new is handed the state as
	-- it stands; the stream carries on from there.
	local function lookAround()
		local near: { [any]: boolean } = {}
		for _, person in ctx.town.people() do
			if ctx.seatOf(person.key) == nil and not isComputer(person.key) then
				local d = Vector3.new(person.x, person.y, person.z) - ctx.anchor
				if d.Magnitude <= Game.WATCH then
					near[person.key] = true
					if not self.watchers[person.key] and self.ref then
						local snap = Referee.snapshot(self.ref)
						snap.site = ctx.station.site
						ctx.send(person.key, snap)
					end
				end
			end
		end
		self.watchers = near
	end

	-- The referee steps as far as the hands allow; what it decided goes out, and its goals go to the rules.
	local function pump()
		local ref = self.ref
		if ref == nil or ctx.session.phase ~= "playing" then
			return
		end
		local msg, goals = Referee.advance(ref, nowTick())
		if msg then
			tell(msg)
		end
		for _, goal in goals do
			ctx.server("goal", { goal.side, goal.score0, goal.score1 }, 1)
		end
	end

	-- The referee's word to one player: this end is yours from tick `from` (again = true: you hold it already,
	-- and your log is expected from `from`: send it again from there).
	local function seatMessage(key: any, side: number, again: boolean?)
		local ref = self.ref
		ctx.send(key, {
			kind = "air_hockey_seat",
			g = ref.game,
			side = side,
			from = Referee.expects(ref, side),
			t0 = ref.t0,
			again = again == true,
		})
	end

	-- A match begins: ends by wish, the computer at the empty end, the referee, and everyone told.
	local function begin()
		local session = ctx.session
		local first = session.seats[1]
		local side1 = self.wish[first] or 0
		ctx.server("sides", { side1 }, 1)
		local mode = session.game.state.mode
		local seated = ctx.seated()
		if #seated < 2 then
			ctx.addComputer(Rules.computerFor(mode))
			seated = ctx.seated()
		end
		table.clear(self.sideOf)
		local human = { [0] = false, [1] = false }
		local difficulty = Sim.DIFFICULTY.medium
		for _, key in seated do
			local seat = ctx.seatOf(key)
			local side = if seat == 1 then side1 else 1 - side1
			self.sideOf[key] = side
			if isComputer(key) then
				difficulty = ServerGame.num(key.difficulty, difficulty)
			else
				human[side] = true
				if self.wish[key] ~= nil and self.wish[key] ~= side then
					ctx.send(key, {
						kind = "event",
						text = `That end was taken: you play the {Layout.SIDE_NAMES[side]} end`,
					})
				end
			end
		end
		self.games += 1
		self.ref = Referee.new({ t0 = ctx.stamp(), game = self.games, human = human, difficulty = difficulty })
		self.cutAt, self.cutWas = ctx.now(), { [0] = 0, [1] = 0 }
		table.clear(self.toldSlow)
		table.clear(self.askedAt)
		lookAround()
		for _, key in seated do
			if not isComputer(key) then
				seatMessage(key, self.sideOf[key])
			end
		end
		tell(Referee.snapshot(self.ref))
		show(self.ref.sim)
		ctx.dirty()
	end

	function self.join(_self: any, player: any, via: ServerGame.StationDef): (boolean, string?)
		self.wish[player] = Layout.sideOfStation(via.id) or 0
		local session = ctx.session
		if ctx.seatOf(player) ~= nil or (session.phase ~= "playing" and session.phase ~= "lobby") then
			return true
		end
		local seated = ctx.seated()
		if #seated < session.rules.def.seats then
			return true
		end
		-- both ends are taken: a person takes the computer's
		for _, key in seated do
			if isComputer(key) then
				ctx.removeComputer(key)
				return true
			end
		end
		return false, "Both ends are taken: watch this one, or wait for the next match"
	end

	function self.joined(_self: any, player: any, seat: number?, _via: ServerGame.StationDef)
		local ref = self.ref
		local session = ctx.session
		if ref == nil or seat == nil or session.phase ~= "playing" or self.sideOf[player] ~= nil then
			return
		end
		-- a person sat down while the match is on: the end the seat already had is theirs from this tick
		local state = session.game.state
		local side = state.sideOf[seat] or 0
		self.sideOf[player] = side
		Referee.control(ref, side, true)
		seatMessage(player, side)
		tell(Referee.snapshot(ref))
		if self.wish[player] ~= side then
			ctx.send(player, { kind = "event", text = `You play the {Layout.SIDE_NAMES[side]} end` })
		end
		ctx.dirty()
	end

	-- "log": a segment of a hand's log. Taken in any phase (a segment that arrives after the last goal is not an
	-- error and gets no words); everything else is the service's.
	function self.command(_self: any, player: any, verb: string, args: { any }): (boolean, boolean?, string?)
		if verb ~= "log" then
			-- A second Space or a second click on Play again that crossed the first on the way: what it asked
			-- for has happened, so it is taken without words (not refused as "already playing").
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
		local ref = self.ref
		local side = self.sideOf[player]
		if ref == nil or side == nil or ctx.session.phase ~= "playing" or ctx.seatOf(player) == nil then
			return true, true
		end
		local strings = {}
		for i = 3, 8 do
			if args[i] ~= nil then
				table.insert(strings, args[i])
			end
		end
		local ok, why, behind = Referee.accept(ref, side, args[1], args[2], strings, nowTick())
		if not ok then
			if behind then
				-- A segment before this one never came (lost, or dropped by the rate limit as a stalled line
				-- delivered its queue), or this one is ahead of the clock. No words: the player is told the
				-- tick their log is expected from, and their Seat sends it again from there.
				if ctx.now() - (self.askedAt[player] or -1e9) >= Game.ASK_EVERY then
					self.askedAt[player] = ctx.now()
					seatMessage(player, side, true)
				end
				return true, true
			end
			return true, false, why
		end
		-- between two people a press of the serve button is passed on to the other player at once: the puck
		-- leaves Sim.SERVE_LEAD after the press, and their screen should know before it does
		if Referee.mode(ref) == "2" then
			local presses = Wire.presses(strings, args[1], args[2])
			if presses and #presses > 0 then
				for _, key in ctx.seated() do
					if key ~= player and not isComputer(key) then
						for _, tick in presses do
							if tick > ref.n then
								ctx.send(key, { kind = "air_hockey_press", g = ref.game, side = side, tick = tick })
							end
						end
					end
				end
			end
		end
		-- (through the Session: an accepted segment is what keeps the idle clock from taking the seat)
		ctx.apply(player, "log", { args[1], args[2] })
		pump()
		return true, true
	end

	function self.step(_self: any, _dt: number)
		local ref = self.ref
		if ref == nil then
			return
		end
		if ctx.session.phase == "playing" then
			pump()
			if ctx.now() - self.watchAt >= 0.5 then
				self.watchAt = ctx.now()
				lookAround()
			end
			if ctx.now() - self.cutAt >= Game.SLOW_WINDOW then
				-- a hand the match keeps playing on without: that player is told why their mallet is late
				self.cutAt = ctx.now()
				for _, key in ctx.seated() do
					local side = self.sideOf[key]
					if side ~= nil and not isComputer(key) then
						local cut = ref.cut[side]
						if
							cut - self.cutWas[side] > Game.SLOW_TICKS
							and ctx.now() - (self.toldSlow[key] or -1e9) >= Game.SLOW_AGAIN
						then
							self.toldSlow[key] = ctx.now()
							ctx.send(key, { kind = "event", text = Game.SLOW_WORDS })
						end
						self.cutWas[side] = cut
					end
				end
			end
		end
		if ctx.now() - self.movedAt >= Game.MOVE_EVERY then
			self.movedAt = ctx.now()
			show(ref.sim)
		end
	end

	function self.event(_self: any, e: ServerGame.Event)
		if e.kind == "start" then
			begin()
		elseif e.kind == "left" or e.kind == "removed" then
			-- (left: walked off, pressed Q, was taken out of the body; removed: their log stopped arriving)
			local key = e.key
			local side = self.sideOf[key]
			self.sideOf[key] = nil
			self.wish[key] = nil
			local ref = self.ref
			if isComputer(key) or ref == nil or side == nil or ctx.session.phase ~= "playing" then
				return
			end
			-- a person left a match that is on: if the other is still there, the computer takes the end
			local stays = false
			for _, other in ctx.seated() do
				if not isComputer(other) then
					stays = true
				end
			end
			if stays and not Referee.over(ref) then
				local leaver = ctx.nameOf(e.seat or 0)
				local ok, _, computer = ctx.addComputer(Rules.computerFor(ctx.session.game.state.mode))
				if ok and computer then
					self.sideOf[computer] = side
					ref.sim.difficulty = ServerGame.num(computer.difficulty, ref.sim.difficulty)
					Referee.control(ref, side, false)
					tell(Referee.snapshot(ref))
					tell({
						kind = "event",
						text = `{leaver} left: the computer takes the {Layout.SIDE_NAMES[side]} end`,
					})
				end
			end
		elseif e.kind == "done" then
			pump()
			if self.ref then
				show(self.ref.sim)
			end
		elseif e.kind == "reset" then
			local wasOn = self.ref ~= nil
			self.ref = nil
			table.clear(self.sideOf)
			show(nil)
			if wasOn then
				-- everyone near is told the table is at rest (each screen moved the pieces itself; nobody is
				-- seated now, so this goes to the people nearby one by one, never to everyone)
				local told: { [any]: boolean } = {}
				for key in self.watchers do
					told[key] = true
				end
				for _, person in ctx.town.people() do
					local d = Vector3.new(person.x, person.y, person.z) - ctx.anchor
					if d.Magnitude <= Game.WATCH and not isComputer(person.key) then
						told[person.key] = true
					end
				end
				for key in told do
					ctx.send(key, { kind = "air_hockey_rest", site = ctx.station.site })
				end
			end
			table.clear(self.watchers)
		end
	end

	function self.state(_self: any, player: any, _seat: number?): { [string]: any }?
		-- (the end they play, or before a match the end they asked for)
		return { side = self.sideOf[player] or self.wish[player] }
	end

	-- while the computer has an end, the prompts say that a person may take it
	function self.prompt(_self: any): (string?, string?)
		if ctx.session.phase == "playing" then
			for _, key in ctx.seated() do
				if isComputer(key) then
					return "Take the computer's end", nil
				end
			end
		end
		return nil, nil
	end

	function self.sig(_self: any, view: { [string]: any }): any
		local g = view.game
		return if g then `{g.score[1]}-{g.score[2]}` else ""
	end

	-- the board over the table: both ends' scores while a match is on, the game's name otherwise; and each
	-- end's score print in the bed (in a player's sight, which the board is not)
	function self.screen(_self: any, view: { [string]: any })
		local hw = self.hw
		if hw == nil then
			return
		end
		local g = view.game
		local text = "AIR HOCKEY  ·  FIRST TO 7"
		local on = g ~= nil and (view.phase == "playing" or view.phase == "done")
		if on then
			text = `GLACIER  {g.score[1]}  :  {g.score[2]}  EMBER`
		end
		for _, label in hw.labels do
			label.Text = text
		end
		-- (and in the bed at each end: that end's own goals first)
		for side = 0, 1 do
			local label = hw.prints[side]
			if label then
				label.Text = if on then `{g.score[side + 1]} : {g.score[2 - side]}` else ""
			end
		end
	end

	function self.doneText(_self: any, view: { [string]: any }): string?
		local r = view.result
		if r == nil or r.side == nil then
			return nil
		end
		local seat = r.winner
		local who = if seat and view.seats[seat] then view.seats[seat].name else Layout.SIDE_NAMES[r.side]
		local a, b = r.score[1], r.score[2]
		return `{who} wins {math.max(a, b)}-{math.min(a, b)}`
	end

	-- Scripted outcomes for the engine checks. ("goal", side): the puck is stood in front of the goal `side`
	-- attacks, travelling in; the simulation scores it itself on the ticks that follow (when the hands' logs next
	-- arrive). ("score", a, b): the score so far is set (both under seven). Everyone is sent the state as it
	-- then stands, so every screen carries on from it.
	function self.debug(_self: any, what: any, side: any, other: any): (boolean, string?)
		local ref = self.ref
		if ref == nil or ctx.session.phase ~= "playing" then
			return false, "no match is on"
		end
		local sim = ref.sim
		if what == "score" then
			local a, b = ServerGame.num(side, -1), ServerGame.num(other, -1)
			if a < 0 or b < 0 or a >= Sim.WIN or b >= Sim.WIN or a % 1 ~= 0 or b % 1 ~= 0 then
				return false, "a score is two whole numbers under seven"
			end
			sim.score0, sim.score1 = a, b
			ctx.server("goal", { 0, a, b }, 1)
			tell(Referee.snapshot(ref))
			return true
		end
		if what ~= "goal" or (side ~= 0 and side ~= 1) then
			return false, "only a goal for end 0 or 1, or a score, can be scripted"
		end
		local s = if side == 0 then 1 else -1
		sim.countdown = 0
		sim.px, sim.py, sim.vx, sim.vy = 0, s * 1.2, 0, s * 5
		tell(Referee.snapshot(ref))
		return true
	end

	return self
end

return Game
