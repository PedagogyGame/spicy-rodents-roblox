--!strict
-- ServerScriptService.Server.Minigames.Games.WhackAMole
-- Whack-a-mole's server half on the minigame framework (Server/Minigames/ServerGame): the owner's cabinet in the
-- bowling alley's games room (station whack_a_mole_1; Shared/Minigames/WhackAMole). THE SERVER IS THE SCORE OF
-- RECORD: it keeps the round (WhackAMole/Round through its Rules, stepped by the Session on the service's clock)
-- and judges every strike.
--   A strike comes in as "whack" { hole, stamp }: which hole the player struck and when, on the clock both sides
--   share (the client's ctx.stamp()). It is turned into round seconds against the round's GO on that same clock
--   (start: the shared-clock time of round second 0, fixed when the round starts) and handed to the rules through
--   ctx.apply (which feeds the idle clock). The rules judge the hole as it was at that moment, so a player 150 ms
--   away scores what they saw; a strike before GO, from the future, too late, out of order or quicker than one
--   mallet can swing is refused with words and scores nothing (Round's header).
--   Every screen near the cabinet draws the same moles from one stream: "whack_rise" { g, id, hole, at, dur } for
--   each mole as the rules decide it (Round.LEAD before it rises, so it rises on time on every screen), and
--   "whack_hit" { g, id?, hole, at, result ("hit" | "miss" | "again"), from?, score } for every strike taken (the mallet swings, the mole drops,
--   the score window changes). Round seconds throughout; `start` turns them into the shared clock. A person who
--   walks up (within WATCH studs, looked for every LOOK seconds) is sent "whack_round": the round as it stands
--   (start, score, the moles still up), and the seated player gets the same when the round starts.
--   The end: "whack_over" { g, score, hits, misses, board, place, best, newBest } to everyone following; the board
--   of best rounds (WhackAMole/HighScores, for as long as the server runs) is written on the cabinet (attribute
--   "Best") for every client, and each player's best is ctx.town.best's ("whack_a_mole").
--   A player who walks away (the station's reach), leaves or is taken off idle ends the round where it stands. When
--   the cabinet is free again, the people near it and everyone who was sent this round (a watcher who has since
--   walked out of the ring included) are told so ("whack_idle", one by one), so no screen keeps a round that ended.
-- Nothing on the cabinet is moved here: every client near it draws the moles, the mallet and the windows from the
-- stream (Client/Minigames/WhackAMole/Cabinet). With no cabinet on the site (another game's rig, a bare test) hw is
-- nil and nobody is looked for: only the seated player is sent anything. Where the cabinet stands, the owner's
-- meshes are put over it at boot once uploaded (Server/Boot/Game calls Server/Assets/WhackArt.startIn).
-- Interface: a ServerGame { game = "whack_a_mole", new(ctx) -> Table }; WATCH, LOOK, WORDS (why -> words);
--   Table.hw { model }; Table.board; Table:round() -> Round.State?; Table:debug("hit" | "miss") (a strike at the
--   server's own round time on the mole that is up, or on an empty hole: for the engine checks)

local Import = require("../../Import")
local HighScores =
	Import.shared("Minigames/WhackAMole/HighScores") :: typeof(require("../../../shared/Minigames/WhackAMole/HighScores"))
local Layout =
	Import.shared("Minigames/WhackAMole/Layout") :: typeof(require("../../../shared/Minigames/WhackAMole/Layout"))
local Round =
	Import.shared("Minigames/WhackAMole/Round") :: typeof(require("../../../shared/Minigames/WhackAMole/Round"))
local Rules =
	Import.shared("Minigames/WhackAMole/Rules") :: typeof(require("../../../shared/Minigames/WhackAMole/Rules"))
local ServerGame = require("../ServerGame")

local Game = {}
Game.game = Rules.GAME
Game.MODEL = "WhackAMole" -- the cabinet's model under the games room
Game.WATCH = Layout.WATCH -- studs from the cabinet within which a bystander is sent the round
Game.LOOK = 0.5 -- seconds between two looks for who stands near
Game.BEST = "whack_a_mole" -- the personal best's name (ctx.town.best)

-- What a refused strike says (Round.strike's reasons).
Game.WORDS = {
	["early"] = "Wait for GO!",
	["ahead"] = "That swing did not match the cabinet's clock",
	["late"] = "That swing reached the cabinet too late",
	["out of order"] = "One swing at a time",
	["too fast"] = "One swing at a time",
	["time is up"] = "Time is up",
	["no such hole"] = "There are five holes: 1 to 5",
	["no time"] = "That swing did not reach the cabinet",
}

local function isComputer(key: any): boolean
	return type(key) == "table" and key.ai == true
end

-- (round seconds as they travel: a thousandth is plenty, and the messages stay short)
local function ms(t: number): number
	return math.floor(t * 1000 + 0.5) / 1000
end

local function riseMsg(g: number, r: any): { [string]: any }
	return { kind = "whack_rise", g = g, id = r.id, hole = r.hole, at = ms(r.at), dur = ms(r.dur) }
end

function Game.new(ctx: ServerGame.Ctx): ServerGame.Table
	local room = ctx.root and (ctx.root :: Instance):FindFirstChild("GamesRoom")
	local model = room and room:FindFirstChild(Game.MODEL)
	local self: any = {
		ctx = ctx,
		hw = if model then { model = model } else nil,
		board = HighScores.new(),
		games = 0, -- rounds started here (each message carries its round's number)
		start = nil :: number?, -- the shared-clock time of this round's GO
		sent = 0, -- moles streamed so far this round
		watchers = {}, -- people near, not seated: key -> true
		told = {}, -- everyone sent anything of this round: key -> true (each is told when the cabinet is free)
		lookAt = -math.huge,
		over = nil, -- the last round's end, for a watcher who walks up during the end card
		mine = nil, -- the last round's place on the board and personal best, for the state message
	}

	local function round(): any
		local s = ctx.session
		local g = s.game
		if g == nil or (s.phase ~= "playing" and s.phase ~= "done") then
			return nil
		end
		return Rules.round(g.state)
	end
	function self.round(_self: any): any
		return round()
	end

	local function writeBoard()
		if self.hw then
			self.hw.model:SetAttribute("Best", table.concat(HighScores.lines(self.board), "\n"))
		end
	end
	writeBoard()

	-- everyone who follows the round: the seated player and the watchers
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

	local function tell(key: any, payload: { [string]: any })
		self.told[key] = true
		ctx.send(key, payload)
	end

	local function toAll(payload: { [string]: any })
		for _, key in followers() do
			tell(key, table.clone(payload))
		end
	end

	-- the round as it stands, for someone who has not been following it
	local function snapshot(): { [string]: any }?
		local r = round()
		local start = self.start
		if r == nil or start == nil then
			return nil
		end
		local up = {}
		for _, rise in r.rises do
			-- (the moles still up, or still to come of those decided)
			if rise.at + rise.dur > r.now - 0.5 then
				table.insert(up, {
					id = rise.id,
					hole = rise.hole,
					at = ms(rise.at),
					dur = ms(rise.dur),
					hitAt = if rise.hitAt then ms(rise.hitAt) else nil,
					from = rise.from,
				})
			end
		end
		return {
			kind = "whack_round",
			g = self.games,
			start = start,
			score = r.score,
			rises = up,
			done = ctx.session.phase == "done",
		}
	end

	local function stream()
		local r = round()
		if r == nil or self.start == nil then
			return
		end
		while self.sent < #r.rises do
			self.sent += 1
			toAll(riseMsg(self.games, r.rises[self.sent]))
		end
	end

	-- who stands near the cabinet: a newcomer is sent the round as it stands, or the last round's end
	local function lookAround()
		self.lookAt = ctx.now()
		local near: { [any]: boolean } = {}
		local phase = ctx.session.phase
		for _, person in ctx.town.people() do
			if ctx.seatOf(person.key) == nil and not isComputer(person.key) then
				local d = Vector3.new(person.x, person.y, person.z) - ctx.anchor
				if d.Magnitude <= Game.WATCH then
					near[person.key] = true
					if not self.watchers[person.key] and (phase == "playing" or phase == "done") then
						local snap = snapshot()
						if snap then
							tell(person.key, snap)
						end
						if phase == "done" and self.over then
							tell(person.key, table.clone(self.over))
						end
					end
				end
			end
		end
		self.watchers = near
	end

	function self.step(_self: any, _dt: number)
		stream()
		if self.hw and ctx.now() - self.lookAt >= Game.LOOK and ctx.session.phase ~= "idle" then
			lookAround()
		end
	end

	-- A second Space or Play again that crossed the first on the way is taken without words.
	function self.command(_self: any, player: any, verb: string, _args: { any }): (boolean, boolean?, string?)
		if ctx.seatOf(player) == nil then
			return false
		end
		local phase = ctx.session.phase
		if (verb == "start" or verb == "again") and phase == "playing" then
			return true, true
		end
		if verb == "whack" and phase == "done" then
			return true, true -- (a swing that arrived after the end card went up: no words)
		end
		return false
	end

	local function strike(key: any, hole: any, t: number): (boolean, string?)
		local ok, why = ctx.apply(key, "whack", { hole, t })
		if not ok then
			return false, Game.WORDS[why or ""] or why
		end
		local r = round()
		local out = r and r.last
		if r and out then
			toAll({
				kind = "whack_hit",
				g = self.games,
				id = out.id,
				hole = out.hole,
				at = ms(out.t),
				result = out.kind,
				from = out.from,
				score = r.score,
			})
		end
		ctx.dirty()
		return true
	end

	function self.input(_self: any, player: any, _seat: number, verb: string, args: { any }): (boolean?, string?)
		if verb ~= "whack" then
			return nil
		end
		local start = self.start
		if start == nil or round() == nil then
			return false, "Wait for GO!"
		end
		local stamp = args[2]
		if type(stamp) ~= "number" or stamp ~= stamp or math.abs(stamp) == math.huge then
			return false, Game.WORDS["no time"]
		end
		return strike(player, args[1], stamp - start)
	end

	function self.event(_self: any, e: ServerGame.Event)
		if e.kind == "start" then
			self.games += 1
			self.sent = 0
			self.over = nil
			self.mine = nil
			local r = round()
			-- round second 0 on the shared clock (the round's own clock is the service's; durations agree)
			self.start = if r then ctx.stamp() - r.now else nil
			local snap = snapshot()
			if snap then
				toAll(snap)
			end
			ctx.dirty()
		elseif e.kind == "done" then
			local s = ctx.session
			local result = s.result
			local key = s.seats[1]
			if result == nil or key == nil then
				return
			end
			local score = (result.scores and result.scores[1]) or 0
			local place = if result.stopped then nil else HighScores.add(self.board, s.names[1] or "?", score)
			local best, newBest = score, false
			if not isComputer(key) then
				local before = ctx.town.best(key, Game.BEST)
				best = ctx.town.best(key, Game.BEST, score, false) or score
				newBest = score > 0 and (before == nil or score > before)
			end
			writeBoard()
			self.mine = { place = place or 0, best = best, newBest = newBest }
			self.over = {
				kind = "whack_over",
				g = self.games,
				score = score,
				hits = result.hits or 0,
				misses = result.misses or 0,
				board = HighScores.list(self.board),
			}
			for _, k in followers() do
				local msg = table.clone(self.over)
				if k == key then
					msg.place = place or 0
					msg.best = best
					msg.newBest = newBest
				end
				tell(k, msg)
			end
		elseif e.kind == "reset" then
			self.start = nil
			-- the people near, and everyone this round was sent to who is still in town, hear the cabinet is free
			-- (one by one: nobody is seated now)
			if self.hw then
				for _, person in ctx.town.people() do
					local d = Vector3.new(person.x, person.y, person.z) - ctx.anchor
					if (d.Magnitude <= Game.WATCH or self.told[person.key]) and not isComputer(person.key) then
						ctx.send(person.key, { kind = "whack_idle", board = HighScores.list(self.board) })
					end
				end
			end
			table.clear(self.watchers)
			table.clear(self.told)
		end
	end

	function self.state(_self: any, _player: any, _seat: number?): { [string]: any }?
		local mine = self.mine
		return {
			g = self.games,
			start = self.start,
			board = if mine then HighScores.list(self.board) else nil,
			place = if mine then mine.place else nil,
			best = if mine then mine.best else nil,
			newBest = if mine then mine.newBest else nil,
		}
	end

	function self.prompt(_self: any): (string?, string?)
		if ctx.session.phase == "playing" then
			return "In use", `Whack-a-Mole - in use by {ctx.nameOf(1)}: watch the moles`
		end
		return nil, nil
	end

	function self.doneText(_self: any, view: { [string]: any }): string?
		local r = view.result
		if r == nil or r.scores == nil then
			return nil
		end
		return `TIME!  {r.scores[1] or 0} points`
	end

	-- For the engine checks: a strike at the server's own round time, through the same path a player's takes:
	-- "hit" on a mole that can be hit now (false if none is up), "miss" on a hole with nothing in it.
	function self.debug(_self: any, what: any): (boolean, string?)
		local r = round()
		local key = ctx.seated()[1]
		if r == nil or key == nil or ctx.session.phase ~= "playing" then
			return false, "no round is on"
		end
		local t = math.max(r.now, r.lastStrike + Round.MIN_GAP)
		if what == "hit" then
			for hole = 1, Round.HOLES do
				local rise = Round.at(r, hole, t)
				if rise and Round.hittable(rise, t) then
					return strike(key, hole, t)
				end
			end
			return false, "no mole is up"
		elseif what == "miss" then
			for hole = 1, Round.HOLES do
				if Round.at(r, hole, t) == nil then
					return strike(key, hole, t)
				end
			end
			return false, "no hole is empty"
		end
		return false, "only a hit or a miss can be scripted"
	end

	return self
end

return Game
