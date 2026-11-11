--!strict
-- ServerScriptService.Server.Minigames.Games.Darts
-- Darts' server half on the minigame framework (Server/Minigames/ServerGame; brief v2 §13a): the Table around
-- the Dartboard hardware in the bowling alley's games room.
--   "throw" { aimX, aimY, timing } is resolved by the rules' seeded scatter (Minigames/MinigameRules/Darts) and
--     shown by the board: the dart flies from the thrower's hand and sticks; everyone seated is sent a "dart"
--     message with what it was and what the banner says.
--   A turn's darts are pulled out a beat after the turn passes, and at the latest when the next turn's first
--     dart is thrown (never together with it), or at once when the turn is skipped.
--   A computer player is a pub darts player (the Spec's names): treble 20s, then a set-up and a double in 501;
--     down the numbers in cricket (aim); its timing lands near the sweet spot.
--   The chalkboard beside the board is Scoreboard.darts.
-- Interface: a ServerGame { game = "darts", new(ctx) -> Table } plus aim(rulesState, seat) -> (xmm, ymm) (a
--   computer's next dart); Table.hw is the Dartboard; Table:debug(xmm, ymm) -> (ok, why?) (a dart landed
--   exactly there for whoever is throwing: the rules' server verb "land")

local Import = require("../../Import")
local Session = Import.shared("Minigames/Session") :: typeof(require("../../../shared/Minigames/Session"))
local Darts =
	Import.shared("Minigames/MinigameRules/Darts") :: typeof(require("../../../shared/Minigames/MinigameRules/Darts"))
local Dartboard = require("../Dartboard")
local Scoreboard = require("../Scoreboard")
local ServerGame = require("../ServerGame")

local num = ServerGame.num

local Game = {}
Game.__index = Game

-- The middle of a ring of segment n on the dartboard (mm): r 103 the treble, 166 the double, 134 the fat single.
local function ringPoint(n: number, r: number): (number, number)
	local idx = table.find(Darts.ORDER, n) or 1
	local a = math.rad((idx - 1) * 18)
	return r * math.sin(a), r * math.cos(a)
end

-- Where a computer points its next dart (board mm; g is the rules' state). 501: treble 20 while there is plenty
-- left, then a single that leaves a double, then that double (50 is the bull). Cricket: the treble of the first
-- number it has not closed, the bull last; with everything closed and still behind, a number a rival has open.
local function aim(g: any, seat: number): (number, number)
	local p = g.players[seat]
	if p == nil then
		return 0, 0
	end
	if g.mode == "501" then
		local left = p.score
		if left == 50 then
			return 0, 0
		elseif left <= 40 and left % 2 == 0 then
			return ringPoint(left // 2, 166)
		elseif left <= 40 then
			return ringPoint(1, 134) -- an odd number: a single 1 leaves a double
		elseif left <= 60 then
			return ringPoint(left - 40, 134) -- leaves double 20
		elseif left < 100 then
			return ringPoint(20, 134)
		end
		return ringPoint(20, 103)
	end
	local want: number? = nil
	for _, n in Darts.CRICKET do
		if p.marks[n] < 3 then
			want = n
			break
		end
	end
	if want == nil then
		for _, n in Darts.CRICKET do
			for i, q in g.players do
				if i ~= seat and q.marks[n] < 3 then
					want = want or n
				end
			end
		end
	end
	if want == nil or want == 25 then
		return 0, 0
	end
	return ringPoint(want, 103)
end

local function new(ctx: ServerGame.Ctx): ServerGame.Table
	local self = setmetatable({}, Game) :: any
	self.ctx = ctx
	self.clearAt = nil :: number? -- when the thrown darts come out of the board
	local root = ctx.root
	local games = root and root:FindFirstChild("GamesRoom")
	local dm = games and games:FindFirstChild("Dartboard")
	self.hw = Dartboard.new({ place = ctx.place, model = dm })
	local sbPart = dm and dm:FindFirstChild("ScoreBoard")
	self.screenGui = sbPart and sbPart:FindFirstChild("Score")
	return self
end

-- The thrower's points before a dart (cricket only: what the dart then adds is what the banner says it scored).
function Game._cricketPoints(self: any, seat: number?): number?
	local g = self.ctx.session.game
	local state = g and g.state
	local p = state and seat and state.players and state.players[seat]
	return if p and state.mode == "cricket" then p.score else nil
end

-- What the banner says of a dart. 501: what it was and what it took off (or the bust, or the checkout). Cricket:
-- a hit on the board is worth nothing by itself; only closing a number and the points it scored are said.
local function dartText(hit: any, cricket: boolean, gained: number): string
	if hit.event == "bust" then
		return `BUST! ({hit.label})`
	elseif hit.event == "checkout" then
		return `CHECKOUT! {hit.label}`
	elseif hit.event == "win" then
		return `{hit.label} - closes it out!`
	elseif not cricket then
		return if hit.points > 0 then `{hit.label}  (+{hit.points})` else hit.label
	end
	local text = hit.label
	if hit.event == "closed" then
		text ..= " - closed"
	elseif hit.event == "nothing" and hit.label ~= "MISS" then
		text ..= " - no score"
	end
	if gained > 0 then
		text ..= `  (+{gained})`
	end
	return text
end

function Game._afterDart(self: any, seat: number?, was: number?)
	local ctx = self.ctx
	local s = ctx.session
	local g = s.game
	local hit = g and g.state.lastHit
	if hit and self.hw then
		-- the turn before's darts are still in the board (the next thrower was quick): they come out now, never
		-- a beat later together with this one
		if self.clearAt ~= nil then
			self.clearAt = nil
			self.hw:clear()
		end
		-- the dart leaves the thrower's hand when there is one
		local from: Vector3? = nil
		local key = seat and s.seats[seat]
		local body = key and ctx.bodyOf(key)
		local hand = body and (body:FindFirstChild("RightHand") or body:FindFirstChild("Right Arm"))
		if hand and hand:IsA("BasePart") then
			from = hand.Position + Vector3.new(0, 0.6, 0)
		end
		self.hw:land(hit.x, hit.y, seat, from)
		local cricket = g.state.mode == "cricket"
		local line = seat and g.state.players[seat]
		local gained = if cricket and was ~= nil and line then math.max(0, line.score - was) else 0
		ctx.broadcast({
			kind = "dart",
			station = ctx.station.id,
			x = hit.x,
			y = hit.y,
			label = hit.label,
			points = hit.points,
			gained = if cricket then gained else nil,
			event = hit.event,
			text = dartText(hit, cricket, gained),
			seat = hit.seat,
		})
		-- the turn passed (three darts or a bust): pull the darts out after a beat
		if g.state.dart == 1 and not g.state.done then
			self.clearAt = ctx.now() + 1.6
		end
	end
	ctx.dirty()
end

function Game.input(self: any, player: any, seat: number, verb: string, args: { any }): (boolean?, string?)
	if verb ~= "throw" then
		return nil
	end
	local board = self.hw
	if board and board:busy() then
		return false, "Wait for the dart to land"
	end
	local was = self:_cricketPoints(seat)
	local ok, why = self.ctx.apply(player, "throw", { num(args[1], 0), num(args[2], 0), num(args[3], 0.5) })
	if ok then
		self:_afterDart(seat, was)
	end
	return ok, why
end

-- The computer's go: a pub darts player (aim, timing near the sweet spot), a dart every 1.1 s.
function Game.computer(self: any, key: any, seat: number): number?
	local ctx = self.ctx
	if self.hw == nil or self.hw:busy() then
		return nil
	end
	local g = ctx.session.game and (ctx.session.game :: any).state
	local aimX, aimY = 0, 103 -- T20
	if g and seat then
		aimX, aimY = aim(g, seat)
	end
	local was = self:_cricketPoints(seat)
	local ok = ctx.apply(key, "throw", { aimX, aimY, 0.5 + ctx.rng.range(-0.09, 0.09) })
	if ok then
		self:_afterDart(seat, was)
	end
	return 1.1
end

function Game.step(self: any, dt: number)
	self.hw:step(dt)
	if self.clearAt and self.ctx.now() >= self.clearAt then
		self.clearAt = nil
		self.hw:clear()
	end
end

function Game.busy(self: any): boolean
	return self.hw:busy()
end

function Game.sig(_self: any, view: { [string]: any }): any
	local g = view.game
	return { g and g.dart or false, g and g.mode or false }
end

function Game.screen(self: any, view: { [string]: any })
	if self.screenGui then
		Scoreboard.darts(self.screenGui, view)
	end
end

function Game.event(self: any, e: ServerGame.Event)
	local board = self.hw
	if e.kind == "start" then
		self.clearAt = nil
		board:clear()
		board:idle(false)
	elseif e.kind == "reset" then
		self.clearAt = nil
		board:clear()
		board:idle(true)
	elseif e.kind == "timeout" then
		-- the darts of the turn that was cut short come out with it
		self.clearAt = nil
		board:clear()
	elseif e.kind == "skipped" then
		-- (a thrower who left: the rest of their turn was played out as misses.) Darts they left in the board
		-- come out now; but when the turn before theirs has only just ended, its last dart may still be in the
		-- air, and those come out on their own beat
		if self.clearAt == nil then
			board:clear()
		end
	elseif e.kind == "done" then
		self.clearAt = self.ctx.now() + 3
	end
end

-- debug: a dart landed exactly at (xmm, ymm) for whoever is throwing (the rules' server verb "land"; tests).
function Game.debug(self: any, xmm: number, ymm: number): (boolean, string?)
	local seat = Session.turn(self.ctx.session)
	local was = self:_cricketPoints(seat)
	local ok, why = self.ctx.apply("server", "land", { xmm, ymm })
	if ok then
		self:_afterDart(seat, was)
	end
	return ok, why
end

return { game = "darts", new = new, aim = aim }
