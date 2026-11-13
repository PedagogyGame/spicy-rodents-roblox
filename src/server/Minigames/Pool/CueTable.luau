--!strict
-- ServerScriptService.Server.Minigames.Pool.CueTable
-- The server half both cue games share (pool's eight-ball tables and the bumper pool table), on the minigame
-- framework (Server/Minigames/ServerGame): one Table per station around the table's balls (Pool/Hardware).
-- The rules modules (Shared/Minigames/Pool/EightBall, BumperPool) ARE the table: a "shoot" runs the table
-- model on the spot and judges the shot. This Table makes that a shot people watch:
--   a strike is TRIED on a copy of the game the moment it is made (so a shot the rules refuse is refused with
--     words, and the shot that will happen is known), its script is sent to EVERY client as one message
--     ("<game>_shot": Shared/Minigames/Pool/Wire text, played back by the clients on the baked balls, the
--     cue's stroke first, with `after`: where the rules lay every ball once they have judged it, so a
--     re-spotted 8 or a scratched cue ball ends where the game has it on every screen), and the turn clock
--     waits (busy) while the balls run;
--   when the script has played, the very same input goes through the Session's own door (ctx.apply): the
--     rules run the same seeded shot again and judge it, so the score, the turn, the banners and the end card
--     change when the last ball has stopped and not when the cue struck. If the shooter walked away while the
--     balls were rolling their turn has been played out as a miss by then; the shot does not count, and every
--     client is told to put the balls back ("<game>_rack");
--   "place" and "call" (eight-ball) stand at once; the balls on the server are laid out from the rules'
--     state after every change (Hardware.layout) and shown coarsely while a shot runs;
--   a computer player (the Spec's names; key.level) thinks with Shared/Minigames/Pool/Computer on a copy of
--     the game, a few milliseconds a step so the server never stalls, then plays its inputs like anyone
--     else's; its cue is drawn back on every screen for a second before it strikes, and it pauses between
--     its own shots;
--   an animal on the cloth cannot spoil a shot: the model never sees it, the first ball to reach it knocks it
--     off the table, and the shot counts (ctx.opts.animals / ctx.opts.knock, as on the lanes);
--   the winner of a game breaks the next one (the rules' `seat` is set as the game starts).
-- A table whose furniture is not there has hw = nil: the game still runs through the rules (stubs can play
-- it), and nothing in the world is touched.
-- Interface: new(ctx, game: Game) -> ServerGame.Table. Game = { game (the id and the message prefix), rules,
--   table (Tables.Table), idle(seed) -> spots (how the table lies when nobody plays), away(state) -> { [id]:
--   true }? (balls kept out of sight), think(state, seat, level, seed, breathe) -> { Input }, snapshot(state)
--   -> any, words(view, names, snapshot) -> string?, endWords(view, names) -> string, fix(state) (after a
--   scripted layout), opener(state, seat) (the winner of the last game starts this one), replay(state) ->
--   bool (the shot that ended the game is played again slowly on every screen: "<game>_shot" with replay =
--   true and a speed), board(game view?,
--   names, wins) -> string (the scoreboard beside the table; wins: games won by name this sitting) }.
--   Table:debug("layout", spots, fields?) sets the table for a check; Table:debug("shoot", args) plays the
--   turn's shot through the same path. TAIL, LEAD_PERSON, LEAD_COMPUTER, BETWEEN, ANIMAL_R

local Import = require("../../Import")
local AlleyLayout =
	Import.shared("Attractions/AlleyLayout") :: typeof(require("../../../shared/Attractions/AlleyLayout"))
local Furniture =
	Import.shared("Minigames/Pool/Furniture") :: typeof(require("../../../shared/Minigames/Pool/Furniture"))
local Shot = Import.shared("Minigames/Pool/Shot") :: typeof(require("../../../shared/Minigames/Pool/Shot"))
local Wire = Import.shared("Minigames/Pool/Wire") :: typeof(require("../../../shared/Minigames/Pool/Wire"))
local Words = Import.shared("Minigames/Pool/Words") :: typeof(require("../../../shared/Minigames/Pool/Words"))
local Hardware = require("./Hardware")
local ServerGame = require("../ServerGame")

local CueTable = {}
CueTable.__index = CueTable

CueTable.TAIL = 0.25 -- seconds after a script's end before the shot is judged
CueTable.LEAD_PERSON = 0.15 -- seconds before the strike: the cue's stroke
CueTable.LEAD_COMPUTER = 1.0 -- a computer player's cue is drawn back and brought through on every screen
CueTable.BETWEEN = 1.4 -- a computer player's pause between its own shots
CueTable.THINK_SLICE = 0.004 -- seconds of thinking in one server step
CueTable.REPLAY_SPEED = 0.4 -- the winning shot played again on every screen, this much slower
CueTable.REPLAY_LEAD = 1.5 -- seconds after the shot is judged
CueTable.ANIMAL_R = 0.45 -- studs: how near a rolling ball's centre comes to an animal before it is knocked off
CueTable.TEXT = {
	rolling = "Wait for the balls to stop",
	left = "That shot's player has left: it does not count.",
	knocked = "A pool ball knocked you off the table!",
}

export type Game = {
	game: string,
	rules: any,
	table: any,
	idle: (seed: number) -> { { id: number, x: number, z: number } },
	away: ((state: any) -> { [number]: boolean }?)?,
	think: (
		state: any,
		seat: number,
		level: number,
		seed: number,
		breathe: () -> ()
	) -> { { verb: string, args: { any } } },
	snapshot: (state: any) -> any,
	words: (view: { [string]: any }, names: { string }, snapshot: any) -> string?,
	endWords: (view: { [string]: any }, names: { string }) -> string,
	board: ((view: { [string]: any }?, names: { string }, wins: { [string]: number }) -> string)?,
	fix: ((state: any) -> ())?,
	replay: ((state: any) -> boolean)?,
	opener: ((state: any, seat: number) -> ())?,
}

-- A copy of a rules state to try a shot on (the last shot's script is not needed for that and is not copied).
local function copyState(v: any): any
	if type(v) ~= "table" then
		return v
	end
	local out = {}
	for k, x in v do
		if k ~= "lastScript" then
			out[k] = copyState(x)
		end
	end
	return out
end

-- flat { id, x, z ... } -> spots; { ids } -> set
local function spotsOf(flat: { number }): { { id: number, x: number, z: number } }
	local out = {}
	for k = 1, #flat - 2, 3 do
		table.insert(out, { id = flat[k], x = flat[k + 1], z = flat[k + 2] })
	end
	return out
end

local function setOf(ids: { number }): { [number]: boolean }?
	if #ids == 0 then
		return nil
	end
	local out: { [number]: boolean } = {}
	for _, id in ids do
		out[id] = true
	end
	return out
end

function CueTable.new(ctx: ServerGame.Ctx, game: Game): ServerGame.Table
	local self = setmetatable({}, CueTable) :: any
	self.ctx = ctx
	self.game = game
	self.pending = nil :: { [string]: any }? -- the shot in flight
	self.thinking = nil :: { [string]: any }? -- a computer player working out its turn
	self.pauseUntil = 0 -- a computer player does not strike before this
	self.shots = 0 -- shots sent from this table since the server started
	self.winner = nil :: any -- who won the last game here (they start the next)
	self.knocked = {} :: { [any]: boolean } -- animals already knocked off by the shot in flight
	self.laid = nil :: { spots: { any }, away: { [number]: boolean }? }? -- the balls as last laid out
	self.wins = {} :: { [string]: number } -- games won at this table, by name, since it was last empty
	self.replayUntil = 0 -- the winning shot's slow replay is playing on the clients until then
	self.judged = 0 -- the rules' shotNo when a shot was last sent to the clients (or the game started)
	self.openingFrom = 0 -- a computer opener at the second seat does not strike before this
	local root = ctx.root
	local room = root and root:FindFirstChild("GamesRoom")
	local model = room and room:FindFirstChild(Furniture.modelName(game.game, ctx.station.index))
	self.hw = Hardware.new({ model = model, place = ctx.place, station = ctx.station, table = game.table })
	return self
end

function CueTable._state(self: any): any
	local g = self.ctx.session.game
	return g and g.state
end

-- The balls on the server, as the rules have them (or as an idle table lies: its own fresh rack). What was
-- laid out is kept, so that the clients can be told the same.
function CueTable._sync(self: any)
	local state = self:_state()
	local spots = if state then state.spots else self.game.idle(self.ctx.rng.int(1, 2147483646))
	local hidden = if state and self.game.away then self.game.away(state) else nil
	self.laid = { spots = spots, away = hidden }
	local hw = self.hw
	if hw then
		hw:layout(spots, hidden)
	end
end

-- A rules state's balls for the wire: flat { id, x, z, ... } for every ball on the cloth, and the sorted ids of
-- the balls kept out of sight (every other ball is at home in the tray).
function CueTable.layoutOf(state: any, away: ((state: any) -> { [number]: boolean }?)?): ({ number }, { number })
	local flat: { number } = {}
	for _, s in state.spots do
		table.insert(flat, s.id)
		table.insert(flat, s.x)
		table.insert(flat, s.z)
	end
	local hidden: { number } = {}
	local out: { [number]: boolean } = (if away then away(state) else nil) or {}
	for id in out do
		table.insert(hidden, id)
	end
	table.sort(hidden)
	return flat, hidden
end

-- Every client puts the balls where they were last laid out (a shot was cut short, a new rack, a scripted
-- layout). fresh: every ball faces the way it was baked again.
function CueTable._rack(self: any, text: string?, fresh: boolean?)
	local ctx = self.ctx
	local laid = self.laid
	if laid == nil then
		return
	end
	local balls: { number } = {}
	local away: { number } = {}
	for _, s in laid.spots do
		table.insert(balls, s.id)
		table.insert(balls, s.x)
		table.insert(balls, s.z)
	end
	for id in laid.away or {} do
		table.insert(away, id)
	end
	table.sort(away)
	ctx.everyone({
		kind = self.game.game .. "_rack",
		index = ctx.station.index,
		balls = balls,
		away = away,
		fresh = fresh == true,
		text = text,
	})
end

-- A strike, a person's or a computer's: tried on a copy; if it sets the table running, the script goes to
-- everyone and the real game hears of it when the balls have stopped.
function CueTable._strike(
	self: any,
	key: any,
	seat: number,
	verb: string,
	args: { any },
	lead: number
): (boolean, string?)
	local ctx = self.ctx
	local state = self:_state()
	if state == nil then
		return false, "No game is on here"
	end
	local try = copyState(state)
	local ok, why = self.game.rules.input(try, seat, verb, args)
	if not ok then
		return false, Words.refusal(why)
	end
	local script = try.lastScript
	if script == nil or try.shotNo == state.shotNo then
		-- nothing ran on the table (bumper pool's first opening strike waits for the other one): it stands now
		local applied, refused = ctx.apply(key, verb, args)
		ctx.dirty()
		return applied, if applied then nil else Words.refusal(refused)
	end
	self.shots += 1
	self.knocked = {}
	-- where every ball lies once the rules have judged the shot (a re-spotted 8, a cue ball back on the head
	-- spot, a practice ball put back by its cup): every screen ends the shot there, not where the balls rolled
	local after, gone = CueTable.layoutOf(try, self.game.away)
	self.pending = {
		key = key,
		seat = seat,
		verb = verb,
		args = args,
		script = script,
		at = ctx.now(),
		lead = lead,
		ends = ctx.now() + lead + script.tEnd + CueTable.TAIL,
		n = self.shots,
		text = Wire.encode(script),
		after = after,
		gone = gone,
	}
	ctx.touch()
	ctx.everyone({
		kind = self.game.game .. "_shot",
		index = ctx.station.index,
		n = self.shots,
		seat = seat,
		lead = lead,
		text = self.pending.text,
		after = after,
		away = gone,
	})
	ctx.dirty()
	return true
end

-- The script has played: the shot goes into the real game. (A shot the rules have already played on the clock,
-- bumper pool's opening with one strike in, is only shown: it is judged already.)
function CueTable._land(self: any)
	local ctx = self.ctx
	local p = self.pending
	self.pending = nil
	local before = self:_state()
	local was = before and self.game.snapshot(before)
	local ok: boolean
	if p.display then
		ok = true
	elseif ctx.seatOf(p.key) == p.seat then
		ok = ctx.apply(p.key, p.verb, p.args)
	else
		-- (the shooter has left the table: their seat still answers for the shot if the turn is still theirs)
		ok = ctx.server(p.verb, p.args, p.seat)
	end
	local state = self:_state()
	if state then
		self.judged = state.shotNo
	end
	if ok and state then
		local hw = self.hw
		if hw then
			hw:landed(p.script)
		end
		self:_sync()
		if not state.done then
			local text = self.game.words(self.game.rules.view(state), ctx.session.names, was)
			if text then
				ctx.broadcast({ kind = "event", text = text, shot = p.n })
			end
		elseif self.game.replay and self.game.replay(state) then
			-- the shot that won the game, again and slowly, on every screen that can see the table
			ctx.everyone({
				kind = self.game.game .. "_shot",
				index = ctx.station.index,
				n = p.n,
				seat = p.seat,
				lead = CueTable.REPLAY_LEAD,
				replay = true,
				speed = CueTable.REPLAY_SPEED,
				text = p.text,
				after = p.after,
				away = p.gone,
			})
			self.replayUntil = ctx.now() + CueTable.REPLAY_LEAD + p.script.tEnd / CueTable.REPLAY_SPEED + 3
		end
		self.pauseUntil = ctx.now() + CueTable.BETWEEN
	elseif state and state.done and ctx.seatOf(p.key) == p.seat then
		-- the game ended while the balls rolled, and not by the shooter (the other player left and forfeited):
		-- the shot is seen to its end where it lies, and the forfeit has its own words
		self.laid = { spots = spotsOf(p.after), away = setOf(p.gone) }
		local hw = self.hw
		if hw then
			hw:landed(p.script)
			hw:layout(self.laid.spots, self.laid.away)
		end
	else
		-- the shooter went while the balls were rolling and the turn was played out as a miss
		self:_sync()
		self:_rack(CueTable.TEXT.left)
		ctx.broadcast({ kind = "event", text = CueTable.TEXT.left, shot = p.n })
	end
	ctx.dirty()
end

-- A shot the rules have just played by themselves (bumper pool's opening, decided on the clock with one strike
-- in): sent to every screen like any other, and only shown, as it is judged already. The words come when the
-- balls stop, and the turn clock waits for them.
function CueTable._show(self: any, state: any)
	local ctx = self.ctx
	local script = state.lastScript
	self.judged = state.shotNo
	self.shots += 1
	self.knocked = {}
	local after, gone = CueTable.layoutOf(state, self.game.away)
	local lead = CueTable.LEAD_PERSON
	local turn = self.game.rules.turn(state)
	self.pending = {
		display = true,
		key = nil,
		seat = 0,
		verb = "shoot",
		args = {},
		script = script,
		at = ctx.now(),
		lead = lead,
		ends = ctx.now() + lead + script.tEnd + CueTable.TAIL,
		n = self.shots,
		text = Wire.encode(script),
		after = after,
		gone = gone,
		turn = turn,
	}
	ctx.everyone({
		kind = self.game.game .. "_shot",
		index = ctx.station.index,
		n = self.shots,
		seat = 0,
		lead = lead,
		text = self.pending.text,
		after = after,
		away = gone,
	})
	ctx.dirty()
end

-- "aim": where the shooter's cue points as they line the shot up, about eight times a second while it moves.
-- Nothing in the game changes; every other screen draws that cue (Playback.aim), so the other player and
-- anyone watching see the shot being lined up. Only the seat whose go it is (either opener) is passed on.
function CueTable._aim(self: any, seat: number, args: { any })
	local ctx = self.ctx
	local state = self:_state()
	if state == nil or self.pending or state.done then
		return
	end
	local rules = self.game.rules
	local may = rules.turn(state) == seat
	if not may and rules.waiting and state.phase == "opening" then
		may = table.find(rules.waiting(state), seat) ~= nil
	end
	if not may then
		return
	end
	local ball, angle, power = ServerGame.num(args[1], -1), ServerGame.num(args[2], 0), ServerGame.num(args[3], 0)
	local tipX, tipY = ServerGame.num(args[4], 0), ServerGame.num(args[5], 0)
	if ball < 0 or ball > 15 or ball % 1 ~= 0 then
		return
	end
	ctx.everyone({
		kind = self.game.game .. "_aim",
		index = ctx.station.index,
		seat = seat,
		ball = ball,
		angle = angle % (2 * math.pi),
		power = math.clamp(power, 0, 1),
		tipX = math.clamp(tipX, -1, 1),
		tipY = math.clamp(tipY, -1, 1),
	})
end

-- Verbs taken before the service's turn gate: the cue's aim from the shooter, and in bumper pool's opening the
-- strike of EITHER opener, in either order (both bank their marked ball, and the table plays the two together
-- when the second is in: the gate would hand the input only to the first seat that has not struck).
function CueTable.command(self: any, player: any, verb: string, args: { any }): (boolean, boolean?, string?)
	if verb ~= "aim" and verb ~= "shoot" then
		return false
	end
	local ctx = self.ctx
	local state = self:_state()
	local seat = ctx.seatOf(player)
	if ctx.session.phase ~= "playing" or state == nil or seat == nil then
		return false
	end
	if verb == "aim" then
		self:_aim(seat, args)
		return true, true
	end
	local waiting = self.game.rules.waiting
	if waiting == nil or state.phase ~= "opening" or table.find(waiting(state), seat) == nil then
		return false
	end
	if self.pending then
		return true, false, CueTable.TEXT.rolling
	end
	local ok, why = self:_strike(player, seat, "shoot", args, CueTable.LEAD_PERSON)
	return true, ok, why
end

function CueTable.input(self: any, player: any, seat: number, verb: string, args: { any }): (boolean?, string?)
	local rules = self.game.rules
	if not rules.verbs[verb] then
		return nil
	end
	if self.pending then
		return false, CueTable.TEXT.rolling
	end
	if verb == "shoot" then
		return self:_strike(player, seat, verb, args, CueTable.LEAD_PERSON)
	end
	local ok, why = self.ctx.apply(player, verb, args)
	if ok then
		self:_sync()
		self.ctx.dirty()
	end
	return ok, if ok then nil else Words.refusal(why)
end

-- A computer player's go: think (a slice a step), then play what it decided like anyone else.
function CueTable.computer(self: any, key: any, seat: number): number?
	local ctx = self.ctx
	if self.pending or ctx.now() < self.pauseUntil then
		return nil
	end
	local state = self:_state()
	if state == nil then
		return nil
	end
	local th = self.thinking
	if th == nil or th.key ~= key or th.shotNo ~= state.shotNo then
		local level = tonumber(key.level) or 1
		local seed = ctx.rng.int(1, 2147483646)
		local snapshot = copyState(state)
		local fresh: { [string]: any } = { key = key, shotNo = state.shotNo, slice = 0 }
		local think = self.game.think
		fresh.co = coroutine.create(function()
			return think(snapshot, seat, level, seed, function()
				if os.clock() - fresh.slice > CueTable.THINK_SLICE then
					coroutine.yield()
				end
			end)
		end)
		th = fresh
		self.thinking = fresh
	end
	th.slice = os.clock()
	local ran, result = coroutine.resume(th.co)
	if not ran then
		self.thinking = nil
		error(`{self.game.game}: the computer player could not think: {tostring(result)}`)
	end
	if coroutine.status(th.co) ~= "dead" then
		return nil
	end
	self.thinking = nil
	local struck = false
	for _, input in result :: { { verb: string, args: { any } } } do
		if input.verb == "shoot" then
			struck = self:_strike(key, seat, "shoot", input.args, CueTable.LEAD_COMPUTER)
		elseif ctx.apply(key, input.verb, input.args) then
			self:_sync()
			ctx.dirty()
		end
	end
	if not struck then
		-- (never seen: a computer plays only what the rules take. Its turn runs out on the clock like anyone's)
		self.pauseUntil = ctx.now() + 5
		return nil
	end
	return 0
end

-- An animal on the cloth while a shot runs: the first ball to reach it knocks it off the table.
function CueTable._animals(self: any, script: any, t: number)
	local ctx = self.ctx
	local animals = ctx.opts.animals
	local knock = ctx.opts.knock
	if animals == nil or knock == nil then
		return
	end
	local tb = self.game.table
	local hw, hl = Furniture.outer(tb)
	local list: { any }? = nil
	for _, a in animals() do
		if self.knocked[a.id] then
			continue
		end
		local X, Y, D = AlleyLayout.toLocal(ctx.place, a.x, a.y, a.z)
		local x, z = X - ctx.station.x, D - ctx.station.d
		local y = Y - Furniture.BED_Y
		if math.abs(x) > hw or math.abs(z) > hl or y < -0.5 or y > 2.5 then
			continue
		end
		list = list or {}
		table.insert(list :: { any }, { id = a.id, x = x, z = z })
	end
	if list == nil then
		return
	end
	local lim = CueTable.ANIMAL_R + tb.ballR
	for i = 1, #script.ids do
		if #script.tracks[i] == 0 then
			continue
		end
		local bx, bz, _, mode, vx, vz = Shot.pose(script, i, t)
		if mode ~= 1 or (vx == 0 and vz == 0) then
			continue
		end
		for _, a in list :: { any } do
			local dx, dz = a.x - bx, a.z - bz
			if not self.knocked[a.id] and dx * dx + dz * dz <= lim * lim then
				self.knocked[a.id] = true
				-- off the nearer long side, onto the floor
				local side = if a.x >= 0 then 1 else -1
				local X, _, D = Furniture.bed(ctx.station, side * (hw + 1.2), a.z, 0)
				local wx, wy, wz = AlleyLayout.toWorld(ctx.place, X, 0.4, D)
				local done, err = pcall(knock, a.id, wx, wy, wz, CueTable.TEXT.knocked)
				if not done then
					warn(`[Minigames] knock failed: {err}`)
				end
				ctx.broadcast({
					kind = "event",
					text = "An animal was on the table: a ball knocked it off. The shot counts.",
					intruder = true,
					shot = self.shots,
				})
			end
		end
	end
end

function CueTable.step(self: any, _dt: number)
	local p = self.pending
	if p == nil then
		self:_openers()
		return
	end
	local ctx = self.ctx
	if ctx.now() >= p.ends then
		self:_land()
		return
	end
	local t = ctx.now() - p.at - p.lead
	if t >= 0 then
		local at = math.min(t, p.script.tEnd)
		if self.hw then
			self.hw:show(p.script, at)
		end
		self:_animals(p.script, at)
	end
end

-- Bumper pool's opening: a computer at a seat that is not the turn's (the person beside it may strike first or
-- second) strikes by itself, after a moment, as the turn's computer does when the service asks it.
function CueTable._openers(self: any)
	local ctx = self.ctx
	local waiting = self.game.rules.waiting
	local state = self:_state()
	if waiting == nil or state == nil or state.phase ~= "opening" or ctx.now() < self.openingFrom then
		return
	end
	if ctx.session.phase ~= "playing" then
		return
	end
	local turn = self.game.rules.turn(state)
	for _, seat in waiting(state) do
		local key = ctx.session.seats[seat]
		if seat ~= turn and type(key) == "table" and key.ai == true then
			self:computer(key, seat)
			return
		end
	end
end

function CueTable.busy(self: any): boolean
	return self.pending ~= nil
end

function CueTable.event(self: any, e: ServerGame.Event)
	local ctx = self.ctx
	local kind = e.kind
	if kind == "start" then
		self.pending = nil
		self.thinking = nil
		self.pauseUntil = 0
		local state = self:_state()
		-- the winner of the last game starts this one
		local opener = self.game.opener
		local seat = self.winner ~= nil and ctx.seatOf(self.winner) or nil
		if state and opener and seat and #ctx.seated() > 1 then
			opener(state, seat)
		end
		self.winner = nil
		self.judged = if state then state.shotNo else 0
		self.openingFrom = ctx.now() + 2
		if self.hw then
			self.hw:fresh()
		end
		self:_sync()
		self:_rack(nil, true)
	elseif kind == "reset" then
		-- (the table is empty: a new sitting begins)
		self.wins = {}
		local cut = self.pending ~= nil
		self.pending = nil
		self.thinking = nil
		self.winner = nil
		if self.hw then
			self.hw:fresh()
		end
		self:_sync()
		if cut or ctx.now() < self.replayUntil then
			-- (a shot, or the winning shot's replay, was playing when the table emptied: every screen stops it and
			-- shows the table as it now lies)
			self:_rack(nil, true)
		end
		self.replayUntil = 0
	elseif kind == "timeout" then
		-- an idle turn has been played out by the rules (eight-ball: a foul, the ball in hand)
		self.thinking = nil
		local state = self:_state()
		if state and state.lastScript and state.shotNo ~= self.judged and not self.pending then
			-- the rules played a shot on the clock (bumper pool's opening with one strike in): every screen sees it
			self:_show(state)
			return
		end
		self:_sync()
		if state and not state.done then
			local text = self.game.words(self.game.rules.view(state), ctx.session.names, self.game.snapshot(state))
			if text then
				-- (not a second banner: the service has just said who took too long. What it means for the table
				-- stays on screen a while)
				ctx.broadcast({ kind = self.game.game .. "_say", text = text })
			end
		end
	elseif kind == "removed" then
		-- taken off for idling: if that ended the game, the end card says so, not that they left
		local state = self:_state()
		local took = self.game.rules.takenOff
		if state and took and e.seat then
			took(state, e.seat)
		end
	elseif kind == "skipped" then
		self.thinking = nil
		self:_sync()
	elseif kind == "done" then
		local r = ctx.session.result
		local w = r and r.winner
		self.winner = if w then ctx.session.seats[w] else nil
		local name = if w then ctx.session.names[w] else nil
		if name then
			self.wins[name] = (self.wins[name] or 0) + 1
		end
	end
end

-- The scoreboard beside the table (when it is built): the game's own words for it, and the games won here this
-- sitting.
function CueTable.sig(self: any, view: { [string]: any }): any
	local board = self.game.board
	if board == nil or self.hw == nil then
		return ""
	end
	local names: { string } = {}
	for i, seat in view.seats or {} do
		names[i] = seat.name
	end
	return board(if view.phase == "playing" or view.phase == "done" then view.game else nil, names, self.wins)
end

function CueTable.screen(self: any, view: { [string]: any })
	local hw = self.hw
	if hw then
		hw:board(self:sig(view))
	end
end

function CueTable.doneText(self: any, view: { [string]: any }): string?
	local g = view.game
	if g == nil then
		return nil
	end
	local names: { string } = {}
	for i, seat in view.seats or {} do
		names[i] = seat.name
	end
	return self.game.endWords(g, names)
end

function CueTable.state(self: any, _player: any, _seat: number?): { [string]: any }?
	local p = self.pending
	return { rolling = p ~= nil, shot = self.shots }
end

-- debug: for the engine checks and the specs. "layout" sets the table (spots = { { id, x, z } }, and any
-- fields of the rules' state); "shoot" plays the turn's shot with these arguments through the same path as a
-- player's.
function CueTable.debug(self: any, what: string, a: any, b: any): (boolean, string?)
	local ctx = self.ctx
	local state = self:_state()
	if state == nil then
		return false, "no game"
	end
	if self.pending then
		return false, CueTable.TEXT.rolling
	end
	if what == "layout" then
		local spots = {}
		for _, s in a do
			table.insert(spots, { id = s.id, x = s.x, z = s.z })
		end
		state.spots = spots
		for k, v in b or {} do
			state[k] = copyState(v)
		end
		local fix = self.game.fix
		if fix then
			fix(state)
		end
		self.judged = state.shotNo
		self.thinking = nil
		self:_sync()
		self:_rack(nil)
		ctx.dirty()
		return true
	elseif what == "shoot" then
		local seat = self.game.rules.turn(state)
		local key = seat and ctx.session.seats[seat]
		if key == nil then
			return false, "nobody's turn"
		end
		return self:_strike(key, seat, "shoot", a, CueTable.LEAD_PERSON)
	end
	return false, "layout or shoot"
end

return CueTable
