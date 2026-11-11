--!strict
-- ServerScriptService.Server.Minigames.Games.Bowling
-- Bowling's server half on the minigame framework (Server/Minigames/ServerGame; brief v2 §13a; HANDOFF §4a): one
-- Table per lane around its BowlingLane hardware.
--   "release" { offset, angle, power, spin }: the throw is decided at once by the pure models in
--     Shared/Minigames/Bowling and sent to EVERY client as one "roll" script to play back; when the lane has
--     played it the count is scored through Bowling/Referee (only onto the sheet of the bowler who threw it);
--     the lane is re-racked whenever it disagrees with the rules (a skipped frame); "rack" tells every client a
--     throw was cut short.
--   A squirrel or the Spicy Rodent on a lane cannot break a game: the ball (or the sweep bar) knocks it into the
--     gutter, the throw counts, and both sides are told (Bowling/Intruders; ctx.opts.animals / ctx.opts.knock).
--   The computer bowlers are Referee's (the pocket on a full rack, the nearest pin on a spare, with their own
--     aim and power error); the overhead monitor is Scoreboard.bowling; the end banner is Referee.summary's line.
--   Service options it reads: tunnels (pair -> the ball's way home), animals, knock, instantRack.
-- Interface: a ServerGame { game = "bowling", new(ctx) -> Table }; Table.hw is the BowlingLane;
--   Table:debug(pins) -> (ok, why?) (a scripted pinfall through the same path as a real roll)

local Import = require("../../Import")
local AlleyLayout =
	Import.shared("Attractions/AlleyLayout") :: typeof(require("../../../shared/Attractions/AlleyLayout"))
local Session = Import.shared("Minigames/Session") :: typeof(require("../../../shared/Minigames/Session"))
local Intruders =
	Import.shared("Minigames/Bowling/Intruders") :: typeof(require("../../../shared/Minigames/Bowling/Intruders"))
local Referee =
	Import.shared("Minigames/Bowling/Referee") :: typeof(require("../../../shared/Minigames/Bowling/Referee"))
local BowlingLane = require("../BowlingLane")
local Scoreboard = require("../Scoreboard")
local ServerGame = require("../ServerGame")

local num = ServerGame.num

local Bowling = {}
Bowling.__index = Bowling

-- The animals near the lanes are asked for once a step at most, however many lanes are rolling: one list per
-- service (keyed by its options table), stamped with the service clock.
local animalLists: { [any]: { at: number, list: { any } } } = setmetatable({}, { __mode = "k" }) :: any

local function new(ctx: ServerGame.Ctx): ServerGame.Table
	local self = setmetatable({}, Bowling) :: any
	self.ctx = ctx
	self.lane = ctx.station.index :: number
	self.hw = nil
	self.screenGui = nil
	self.knocked = {} :: { [any]: boolean } -- animals already bowled over by the throw in flight
	self.lastT = nil :: number? -- how far into the throw the lane was last step
	self.lastSweep = nil :: number? -- where the sweep bar was last step
	local root = ctx.root
	local lanes = root and root:FindFirstChild("Lanes")
	local boards = root and root:FindFirstChild("Scoreboards")
	if lanes then
		local laneModel = lanes:FindFirstChild(`Lane{self.lane}`)
		if laneModel then
			local pair = AlleyLayout.pairOf(self.lane)
			local tunnels = ctx.opts.tunnels
			self.hw = BowlingLane.new({
				lane = self.lane,
				model = laneModel,
				place = ctx.place,
				tunnel = tunnels and tunnels[pair],
				-- a throw was cut short (the table emptied, the game ended): every client stops playing it
				onRack = function(mask: { boolean })
					ctx.everyone({ kind = "rack", station = ctx.station.id, lane = self.lane, mask = mask })
				end,
			})
		end
		local sb = boards and boards:FindFirstChild(`Lane{self.lane}`)
		local screen = sb and sb:FindFirstChild("Screen")
		self.screenGui = screen and screen:FindFirstChild("Score")
	end
	return self
end

-- A bowling throw, a person's or a computer's: the lane decides it at once; everyone is sent the script.
function Bowling._release(self: any, thrower: any, params: any): (boolean, string?)
	local ctx = self.ctx
	local seat = ctx.seatOf(thrower)
	local ok, why, script = self.hw:release(params, seat, ctx.rng.int(1, 2147483646))
	if not ok then
		return false, why
	end
	ctx.touch()
	self:_announce(seat, script)
	return true
end

function Bowling._announce(self: any, seat: number?, script: any)
	local ctx = self.ctx
	self.knocked = {}
	self.lastT = 0
	ctx.dirty()
	ctx.everyone({
		kind = "roll",
		station = ctx.station.id,
		lane = self.lane,
		seat = seat,
		name = seat and ctx.session.names[seat],
		script = script,
	})
end

function Bowling.input(self: any, player: any, _seat: number, verb: string, args: { any }): (boolean?, string?)
	if verb ~= "release" then
		return nil
	end
	local lane = self.hw
	if lane == nil then
		return false, "this lane has no hardware"
	end
	if not lane:ready() then
		return false, "Wait for the pinsetter and the ball"
	end
	return self:_release(player, {
		offset = num(args[1], 0),
		angle = num(args[2], 0),
		power = num(args[3], 0.6),
		spin = num(args[4], 0),
	})
end

-- The computer's go: a bowler of its own skill (Bowling/Referee).
function Bowling.computer(self: any, key: any, _seat: number): number?
	local lane = self.hw
	if lane and lane:ready() then
		local params =
			Referee.aiThrow(self.ctx.rng, key.skill or Referee.skillOf(tostring(key.Name)), lane:standingMask())
		self:_release(key, params)
		return 0
	end
	return nil
end

function Bowling.busy(self: any): boolean
	return self.hw ~= nil and not self.hw:ready()
end

function Bowling.state(self: any, _player: any, _seat: number?): { [string]: any }?
	return { ready = if self.hw then self.hw:ready() else true }
end

function Bowling.screen(self: any, view: { [string]: any })
	local gui = self.screenGui
	if gui == nil then
		return
	end
	if view.phase == "idle" then
		Scoreboard.idle(gui, `LANE {self.lane}`, "OPEN - walk up and press E")
	else
		Scoreboard.bowling(gui, self.lane, view)
	end
end

function Bowling.doneText(_self: any, view: { [string]: any }): string?
	return Referee.summary(view).line
end

function Bowling.event(self: any, e: Session.Event)
	local lane = self.hw
	if lane == nil then
		return
	end
	if e.kind == "start" or e.kind == "reset" then
		lane:reset(true)
	elseif e.kind == "left" then
		if e.why == "turn" then
			lane:hold(nil)
		end
	elseif e.kind == "timeout" then
		lane:hold(nil)
		lane.heldBy = nil
	end
end

-- debug: a scripted pinfall on the lane (Luau Execution; tests) through the same path as a real roll.
function Bowling.debug(self: any, pins: number): (boolean, string?)
	local lane = self.hw
	local s = self.ctx.session
	if lane == nil then
		return false, "no lane"
	end
	if s.phase ~= "playing" then
		return false, "no game"
	end
	if not lane:ready() then
		return false, "lane busy"
	end
	local seat = Session.turn(s)
	local ok, why, script = lane:debugRoll(pins, seat)
	if ok then
		self:_announce(seat, script)
	end
	return ok, why
end

-- Per frame -------------------------------------------------------------------------------------------------------
-- Animals near this lane in its own frame (x across from the lane centre, y up, d down-lane). Asked for once a
-- step at most, and only while some lane is rolling or sweeping.
function Bowling._animals(self: any): { any }
	local ctx = self.ctx
	local source = ctx.opts.animals
	if source == nil then
		return {}
	end
	local cache = animalLists[ctx.opts]
	local now = ctx.now()
	if cache == nil or cache.at ~= now then
		local ok, list = pcall(source)
		cache = { at = now, list = if ok and type(list) == "table" then list else {} }
		animalLists[ctx.opts] = cache
	end
	local out = {}
	local lx = AlleyLayout.laneX(self.lane)
	for _, a in cache.list do
		local X, Y, D = AlleyLayout.toLocal(ctx.place, a.x, a.y, a.z)
		if math.abs(X - lx) < AlleyLayout.PITCH and D > -2 and D < AlleyLayout.PIT_END + 1 then
			table.insert(out, { id = a.id, kind = a.kind, x = X - lx, y = Y, d = D })
		end
	end
	return out
end

-- The rule for a squirrel or the Spicy Rodent on a lane (Bowling/Intruders): the ball, or the sweep bar, knocks
-- it into the gutter; the throw counts; the bowlers and the animal's player are told.
function Bowling._intruders(self: any)
	local ctx = self.ctx
	local lane = self.hw
	local knocks: { any } = {}
	local swept = false
	local animals: { any } = {}
	local tNow = lane:scriptTime()
	if tNow ~= nil then
		local script = lane:script()
		if script and script.path and tNow > (self.lastT or 0) then
			animals = self:_animals()
			if #animals > 0 then
				knocks = Intruders.struck(script, self.lastT or 0, tNow, animals)
			end
		end
		self.lastT = tNow
		self.lastSweep = nil
	else
		local d, low = lane:sweep()
		if d ~= nil and low then
			animals = self:_animals()
			if #animals > 0 then
				knocks = Intruders.swept(self.lastSweep or d, d, animals)
				swept = true
			end
			self.lastSweep = d
		else
			self.lastSweep = nil
		end
	end
	for _, k in knocks do
		if self.knocked[k.id] then
			continue
		end
		self.knocked[k.id] = true
		local kind = "squirrel"
		for _, a in animals do
			if a.id == k.id and a.kind == "rodent" then
				kind = "Spicy Rodent"
			end
		end
		local wx, wy, wz = AlleyLayout.toWorld(ctx.place, AlleyLayout.laneX(self.lane) + k.x, 0.4, k.d)
		local knock = ctx.opts.knock
		if knock then
			local ok, err =
				pcall(knock, k.id, wx, wy, wz, if swept then Intruders.TEXT.animalSwept else Intruders.TEXT.animal)
			if not ok then
				warn(`[Minigames] knock failed: {err}`)
			end
		end
		local article = if kind == "squirrel" then "A squirrel" else "The Spicy Rodent"
		ctx.broadcast({
			kind = "event",
			station = ctx.station.id,
			text = `{article} {if swept then Intruders.TEXT.swept else Intruders.TEXT.bowlers}`,
			intruder = true,
		})
	end
end

function Bowling.step(self: any, dt: number)
	local ctx = self.ctx
	local lane = self.hw
	if lane == nil then
		return
	end
	local instant = ctx.opts.instantRack == true
	lane:step(dt)
	local s = ctx.session
	if not lane:ready() then
		self:_intruders()
	end
	local result = lane:takeResult()
	if result ~= nil then
		-- only ever onto the sheet of the bowler who threw it (Referee: they may have left while it rolled)
		local wasPlaying = s.phase == "playing"
		local verdict = Referee.score(s, result, ctx.now())
		if wasPlaying then
			lane:setRack(verdict.rack, instant)
		else
			lane:setRack("full", true)
		end
		if verdict.applied then
			ctx.broadcast({
				kind = "event",
				station = ctx.station.id,
				text = verdict.text,
				big = verdict.big,
				pins = verdict.pins,
				mark = verdict.mark,
				ok = true,
			})
		elseif wasPlaying then
			ctx.broadcast({
				kind = "event",
				station = ctx.station.id,
				text = "That ball's bowler has left: it does not count. Fresh pins.",
				pins = 0,
				ok = false,
			})
		end
		ctx.dirty()
	end
	-- the pins on the deck must be what the rules expect (a skipped or timed-out frame leaves a stale rack)
	if lane:ready() then
		local order = Referee.sync(s, lane:standingCount())
		if order then
			if s.phase == "playing" then
				lane:hold(nil)
				lane.heldBy = nil
				lane:setRack(order, instant)
			else
				lane:reset(true)
			end
			ctx.dirty()
		end
	end
	-- the ball in the bowler's hand once the lane is ready
	if lane:ready() and s.phase == "playing" then
		local key = Session.turnKey(s)
		local body = key and ctx.bodyOf(key)
		if body ~= lane.heldBy then
			lane.heldBy = body
			lane:hold(body)
			ctx.dirty()
		elseif body and lane.held == nil then
			lane:hold(body)
		end
	elseif lane.heldBy ~= nil and lane:ready() then
		lane.heldBy = nil
		lane:hold(nil)
	end
	if lane.wasReady ~= lane:ready() then
		lane.wasReady = lane:ready()
		ctx.dirty()
	end
end

local entry: ServerGame.ServerGame = { game = "bowling", new = new }

return entry
