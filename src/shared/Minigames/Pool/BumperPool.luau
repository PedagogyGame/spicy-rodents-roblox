--!strict
-- ReplicatedStorage.Shared.Minigames.Pool.BumperPool
-- Bumper pool: the rules as a state machine in the shape of Minigame.Rules, and the table itself (the state
-- holds where every ball lies; "shoot" runs the table model, judges the shot and keeps its script for every
-- client to play). There is no cue ball: a player strikes one of their own five. Seat 1 owns balls 1..5 (1 is
-- the marked one), starts round the head-end cup and shoots at the cup at the foot end (hole 2); seat 2 owns
-- 6..10 (6 marked), starts at the foot end and shoots at the head cup (hole 1). The published game, line by
-- line against the checklist:
--   BP-R2 five each, one marked, starting on the spots round the cup at their own end (Tables.bumperStart).
--   BP-R3 the opening: both players strike their marked ball in the SAME model run (each sends "shoot"; the
--         table plays when both are in), banking it off the side cushion on their own RIGHT (seat 1: +x,
--         seat 2: -x), so the two balls cross the table without meeting. Whoever sinks theirs shoots next; if
--         neither does, the ball lying nearer its cup; if both do, each side's next ball goes on the marked
--         ball's spot and they open again. An opener whose first touch is anything but that cushion (the
--         other side's line, a bumper, another ball, nothing at all) is "offside": its ball stays where it
--         went, but it cannot win the next shot from an opener that was played fairly.
--         In the opening a ball that goes down answers to the player whose strike reached it through the
--         chain of contacts, and to nobody if both strikes did: your opponent knocking your resting ball (or
--         your marked ball as it runs) into a cup is BP-R5's "counts for the opponent, no penalty", never
--         your own foul.
--   BP-R4 the marked ball must be sunk first: sink another of your own before it and the opponent drops two
--         of their own balls straight into their cup (the table picks them as a player would: their marked
--         ball if it is still up, then the balls lying farthest from their cup).
--   BP-R5 sinking one of your own gives another shot; an opponent's ball that goes down counts for the
--         opponent, with no penalty; your own ball in the opponent's cup counts as down but the opponent
--         drops two of theirs; your LAST ball in the opponent's cup loses the game.
--   BP-R6 nothing jumps (the model never lifts a ball); the first to have all five down wins.
--   BP-R7 an idle turn passes the shot (in the opening: that player's ball is simply not struck).
--   A player who leaves a game against someone else forfeits it (gone): the other wins, "left the table".
--   Decision D2's fallback: init(seats, seed, false) leaves the opening out and plays in turn from seat 1
--   (the marked ball must still go down first).
--   Practice (seats = 1): only your five are on the table; sink them in the far cup in the fewest shots. A
--   ball that drops in the cup beside its starting spots is put back on its spot, and the shot is counted.
--   "Banks made" counts your own balls sunk off at least one cushion touched BEFORE the ball reached the cup's
--   rim (the cushion just behind the cup, touched on the way down, does not make a straight shot a bank).
-- Pure and seeded. Lune-tested (tests/unit/pool_bumper.spec.luau).
-- Interface: def, verbs; init(seats, seed, together?) -> State; input(state, seat, "shoot", { ball, angle,
--   power, tipX?, tipY? }); turn(state) (in the opening: the first seat that has not struck yet);
--   waiting(state) -> { seats that may strike now }; skipTurn(state); gone(state, seat) (a forfeit);
--   result(state); view(state);
--   script(state) -> Shot.Script?; settle(state, pots, shooterOf, rest?) (the referee alone; shooterOf may
--   answer 0: nobody's shot); sideOf(ball); cupOf(seat) -> hole index; markedOf(seat) -> ball id;
--   rightCushion(seat) -> the table segment an opener must bank off; mine(state, seat) -> { ball ids on the
--   table }; HOW_TEXT

local Cue = require("./Cue")
local Physics = require("./Physics")
local Shot = require("./Shot")
local Tables = require("./Tables")

local BumperPool = {}

BumperPool.def = {
	game = "bumper_pool",
	title = "Bumper pool",
	class = "shared_table" :: "shared_table",
	seats = 2,
	authority = "server",
	money = "none",
}
BumperPool.verbs = { shoot = true }

BumperPool.HOW_TEXT = {
	five = "sank all five",
	last_ball_wrong_cup = "sank the last ball in the wrong cup",
	left = "left the table",
} :: { [string]: string }

export type PotAt = { ball: number, hole: number, cushions: number }
export type Last = {
	shooters: { number }, -- one seat, or both in the opening
	event: string, -- "opening" | "continue" | "pass" | "win" | "lose" | "idle"
	pots: { number }, -- balls in drop order
	holes: { number },
	dropped: { number }, -- balls dropped in as a penalty award
	awarded: number, -- the seat that was given them (0: no penalty)
	respotted: { number }, -- practice: balls that went down the near cup and are back on their spots
	offside: { number }, -- the opening: seats whose ball did not go off their right-hand cushion first
}
export type State = {
	seats: number,
	seed: number,
	seat: number,
	spots: { Tables.Spot },
	phase: string, -- "opening" | "play"
	pending: { [number]: Shot.Strike | boolean }, -- the opening: seat -> its strike (false: it passed)
	openers: { number }, -- the ball each seat strikes in the opening
	sunk: { number }, -- per seat, 0..5
	markedDown: { boolean },
	done: boolean,
	winner: number?,
	how: string?,
	shotNo: number,
	shots: { number },
	banks: { number }, -- own balls sunk off at least one cushion
	last: Last?,
	lastScript: Shot.Script?,
}

function BumperPool.sideOf(ball: number): number
	return if ball <= 5 then 1 else 2
end

function BumperPool.cupOf(seat: number): number
	return if seat == 1 then 2 else 1
end

function BumperPool.markedOf(seat: number): number
	return (seat - 1) * 5 + 1
end

-- The side cushion on a player's right as they face their cup: the table's segment 2 (+x) for seat 1, who
-- shoots up the table, and segment 1 (-x) for seat 2, who shoots down it. The opening is banked off it.
function BumperPool.rightCushion(seat: number): number
	return if seat == 1 then 2 else 1
end

function BumperPool.init(seats: number, seed: number, together: boolean?): State
	local two = seats >= 2
	return {
		seats = seats,
		seed = seed,
		seat = 1,
		spots = Tables.bumperStart({ true, two }),
		phase = if two and together ~= false then "opening" else "play",
		pending = {},
		openers = if two then { 1, 6 } else { 1 },
		sunk = table.create(seats, 0),
		markedDown = table.create(seats, false),
		done = false,
		winner = nil,
		how = nil,
		shotNo = 0,
		shots = table.create(seats, 0),
		banks = table.create(seats, 0),
		last = nil,
		lastScript = nil,
	}
end

function BumperPool.mine(state: State, seat: number): { number }
	local out: { number } = {}
	for _, s in state.spots do
		if BumperPool.sideOf(s.id) == seat then
			table.insert(out, s.id)
		end
	end
	table.sort(out)
	return out
end

function BumperPool.waiting(state: State): { number }
	if state.done then
		return {}
	end
	if state.phase ~= "opening" then
		return { state.seat }
	end
	local out: { number } = {}
	for s = 1, state.seats do
		if state.pending[s] == nil then
			table.insert(out, s)
		end
	end
	return out
end

function BumperPool.turn(state: State): number?
	return BumperPool.waiting(state)[1]
end

local function removeSpot(spots: { Tables.Spot }, id: number): boolean
	for i = #spots, 1, -1 do
		if spots[i].id == id then
			table.remove(spots, i)
			return true
		end
	end
	return false
end

local function win(state: State, seat: number?, how: string)
	if not state.done then
		state.done = true
		state.winner = seat
		state.how = how
	end
end

-- The penalty award: `seat` drops two of its own balls straight into its cup. The rule lets the player choose;
-- the table chooses as a player would: the marked ball if it is still up (with it down, every other ball is
-- free to be sunk), then the balls lying farthest from the cup (the lower ball of two equally far).
local function award(state: State, seat: number, dropped: { number })
	local own = BumperPool.mine(state, seat)
	local marked = BumperPool.markedOf(seat)
	local cup = Tables.bumper().holes[BumperPool.cupOf(seat)]
	local far: { [number]: number } = {}
	for _, s in state.spots do
		far[s.id] = (s.x - cup.x) * (s.x - cup.x) + (s.z - cup.z) * (s.z - cup.z)
	end
	table.sort(own, function(a, b)
		if (a == marked) ~= (b == marked) then
			return a == marked
		end
		if far[a] ~= far[b] then
			return far[a] > far[b]
		end
		return a < b
	end)
	for k = 1, math.min(2, #own) do
		local ball = own[k]
		removeSpot(state.spots, ball)
		state.sunk[seat] += 1
		if ball == marked then
			state.markedDown[seat] = true
		end
		table.insert(dropped, ball)
	end
	if state.sunk[seat] >= 5 then
		win(state, seat, "five")
	end
end

-- The referee: the balls that went down, in order, applied to the game. shooterOf(ball) is the seat whose
-- strike is answerable for that ball (the one shooter in ordinary play; in the opening, see resolveOpening),
-- or 0 if nobody's is. Returns the seats that sank one of their own in their own cup (they shoot again) and
-- fills `last`.
function BumperPool.settle(
	state: State,
	pots: { PotAt },
	shooterOf: (ball: number) -> number,
	rest: { Tables.Spot }?
): { [number]: boolean }
	if rest then
		state.spots = rest
	end
	local again: { [number]: boolean } = {}
	local potIds: { number }, potHoles: { number }, dropped: { number } = {}, {}, {}
	local respotted: { number } = {}
	local awarded = 0
	for _, p in pots do
		if state.done then
			break
		end
		local owner = BumperPool.sideOf(p.ball)
		if owner > state.seats or (rest == nil and not removeSpot(state.spots, p.ball)) then
			continue
		end
		local shooter = shooterOf(p.ball)
		local opp = if state.seats > 1 then 3 - owner else 0
		local marked = p.ball == BumperPool.markedOf(owner)
		table.insert(potIds, p.ball)
		table.insert(potHoles, p.hole)
		if opp == 0 and p.hole ~= BumperPool.cupOf(owner) then
			-- practice: the cup beside the starting spots is not the target. Back on its spot (or the nearest
			-- free place up the table from it)
			local tb = Tables.bumper()
			for _, sp in Tables.bumperStart({ owner == 1, owner == 2 }) do
				if sp.id == p.ball then
					local x, z = Tables.freeSpot(tb, sp.x, sp.z, state.spots, if owner == 1 then 1 else -1)
					table.insert(state.spots, { id = p.ball, x = x, z = z })
				end
			end
			table.insert(respotted, p.ball)
			continue
		end
		state.sunk[owner] += 1
		if p.hole == BumperPool.cupOf(owner) then
			if owner == shooter then
				again[owner] = true
				if p.cushions > 0 then
					state.banks[owner] += 1
				end
				if not marked and not state.markedDown[owner] and opp ~= 0 then
					-- BP-R4: another ball before the marked one
					awarded = opp
					award(state, opp, dropped)
				end
			end
		elseif owner == shooter then
			-- BP-R5: your own ball in the opponent's cup
			if state.sunk[owner] >= 5 then
				win(state, opp, "last_ball_wrong_cup")
			else
				awarded = opp
				award(state, opp, dropped)
			end
		end
		if marked then
			state.markedDown[owner] = true
		end
		if state.sunk[owner] >= 5 then
			win(state, owner, "five")
		end
	end
	state.last = {
		shooters = {},
		event = "pass",
		pots = potIds,
		holes = potHoles,
		dropped = dropped,
		awarded = awarded,
		respotted = respotted,
		offside = {},
	}
	return again
end

local function cupDistance(state: State, seat: number, ball: number): number
	local tb = Tables.bumper()
	local cup = tb.holes[BumperPool.cupOf(seat)]
	for _, s in state.spots do
		if s.id == ball then
			local dx, dz = s.x - cup.x, s.z - cup.z
			return math.sqrt(dx * dx + dz * dz)
		end
	end
	return math.huge
end

local function potsOf(script: Shot.Script): { PotAt }
	local out: { PotAt } = {}
	for _, p in Shot.pots(script) do
		table.insert(out, { ball = p.ball, hole = p.hole, cushions = p.cushions })
	end
	return out
end

-- Both openers are in (or passed): the table plays them together.
local function resolveOpening(state: State)
	local tb = Tables.bumper()
	local strikes: { Shot.Strike } = {}
	local shooters: { number } = {}
	for s = 1, state.seats do
		local st = state.pending[s]
		if type(st) == "table" then
			table.insert(strikes, st)
			table.insert(shooters, s)
			state.shots[s] += 1
		end
	end
	state.pending = {}
	state.shotNo += 1
	if #strikes == 0 then
		-- nobody struck: ordinary play from seat 1
		state.phase = "play"
		state.seat = 1
		state.lastScript = nil
		state.last = {
			shooters = {},
			event = "idle",
			pots = {},
			holes = {},
			dropped = {},
			awarded = 0,
			respotted = {},
			offside = {},
		}
		return
	end
	local script = Shot.run(tb, state.spots, strikes)
	state.lastScript = script
	-- who answers for each ball that went down: the one player whose strike reached it (a struck ball that
	-- nothing of the other side's touched is its striker's; a resting ball is whoever's chain of contacts
	-- knocked it in); nobody, if both strikes had a hand in it
	local answers: { [number]: number } = {}
	for _, p in Shot.pots(script) do
		local shooter = 0
		for k, seat in shooters do
			if p.by == bit32.lshift(1, k - 1) then
				shooter = seat
			end
		end
		answers[p.ball] = shooter
	end
	local again = BumperPool.settle(state, potsOf(script), function(ball: number): number
		return answers[ball] or 0
	end, Shot.rest(script))
	-- was each opener a bank off the player's own right-hand cushion? (one that was not struck at all is no
	-- fairer than one that went the wrong way, though only a struck one is called offside)
	local fair: { [number]: boolean } = { false, false }
	local last = state.last :: Last
	for k, seat in shooters do
		local kind, what = Shot.firstTouch(script, strikes[k].id)
		fair[seat] = kind == Physics.EV.cushion and what == BumperPool.rightCushion(seat)
		if not fair[seat] then
			table.insert(last.offside, seat)
		end
	end
	last.shooters = shooters
	if state.done then
		last.event = "win"
		return
	end
	last.event = "opening"
	local won1, won2 = again[1] == true and fair[1], again[2] == true and fair[2]
	if won1 and won2 then
		-- both sank: each side's next ball goes on the marked ball's spot and they open again
		for s = 1, 2 do
			local own = BumperPool.mine(state, s)
			local ball = own[1]
			state.openers[s] = ball
			removeSpot(state.spots, ball)
			local sz = if s == 1 then -1 else 1
			local z = sz * Tables.CUP_Z - sz * Tables.MARKED_OFF
			local x, zz = Tables.freeSpot(tb, 0, z, state.spots, -sz)
			table.insert(state.spots, { id = ball, x = x, z = zz })
		end
		return
	end
	state.phase = "play"
	if won1 or won2 then
		state.seat = if won1 then 1 else 2
	elseif fair[1] ~= fair[2] then
		-- one of them was not played off its right-hand cushion (or not played at all): the other shoots
		state.seat = if fair[1] then 1 else 2
	else
		local d1 = cupDistance(state, 1, state.openers[1])
		local d2 = cupDistance(state, 2, state.openers[2])
		state.seat = if d2 < d1 then 2 else 1
	end
end

local function num(v: any): number?
	if type(v) == "number" and v == v and v > -1e6 and v < 1e6 then
		return v
	end
	return nil
end

function BumperPool.input(state: State, seat: number, verb: string, args: { any }?): (boolean, string?)
	if verb ~= "shoot" then
		return false, "verb"
	end
	if state.done then
		return false, "game over"
	end
	local a: { any } = args or {}
	local ball, angle, power = num(a[1]), num(a[2]), num(a[3])
	if ball == nil or angle == nil or power == nil then
		return false, "args"
	end
	local tipX, tipY = num(a[4]) or 0, num(a[5]) or 0
	local onTable = false
	for _, s in state.spots do
		if s.id == ball then
			onTable = true
		end
	end
	if not onTable or BumperPool.sideOf(ball) ~= seat then
		return false, "not your ball"
	end
	local strike = Cue.strike(ball, angle, power, tipX, tipY, state.seed * 7919 + state.shotNo * 2 + seat)
	if state.phase == "opening" then
		if seat > state.seats or state.pending[seat] ~= nil then
			return false, "already struck"
		end
		if ball ~= state.openers[seat] then
			return false, "the opening is played with the marked ball"
		end
		state.pending[seat] = strike
		if #BumperPool.waiting(state) == 0 then
			resolveOpening(state)
		end
		return true, nil
	end
	if seat ~= state.seat then
		return false, "not your turn"
	end
	state.shotNo += 1
	state.shots[seat] += 1
	local script = Shot.run(Tables.bumper(), state.spots, { strike })
	state.lastScript = script
	local again = BumperPool.settle(state, potsOf(script), function(_ball: number): number
		return seat
	end, Shot.rest(script))
	local last = state.last :: Last
	last.shooters = { seat }
	if state.done then
		last.event = if state.winner == seat then "win" else "lose"
	elseif again[seat] then
		last.event = "continue"
	else
		last.event = "pass"
		if state.seats > 1 then
			state.seat = 3 - seat
		end
	end
	return true, nil
end

-- An idle (or vacated) turn passes the shot; in the opening that player's ball is not struck.
function BumperPool.skipTurn(state: State)
	if state.done then
		return
	end
	if state.phase == "opening" then
		local seat = BumperPool.turn(state)
		if seat then
			state.pending[seat] = false
			if #BumperPool.waiting(state) == 0 then
				resolveOpening(state)
			end
		end
		return
	end
	state.last = {
		shooters = { state.seat },
		event = "idle",
		pots = {},
		holes = {},
		dropped = {},
		awarded = 0,
		respotted = {},
		offside = {},
	}
	state.lastScript = nil
	if state.seats > 1 then
		state.seat = 3 - state.seat
	end
end

-- A seat has left a game against someone else: they forfeit it, and the one still at the table wins.
function BumperPool.gone(state: State, seat: number)
	if state.done or state.seats < 2 then
		return
	end
	win(state, 3 - seat, "left")
	state.pending = {}
	state.last = {
		shooters = { seat },
		event = "lose",
		pots = {},
		holes = {},
		dropped = {},
		awarded = 0,
		respotted = {},
		offside = {},
	}
	state.lastScript = nil
end

function BumperPool.script(state: State): Shot.Script?
	return state.lastScript
end

function BumperPool.result(state: State): { [string]: any }?
	if not state.done then
		return nil
	end
	local scores: { [number]: number } = {}
	for s = 1, state.seats do
		scores[s] = state.sunk[s]
	end
	return {
		done = true,
		scores = scores,
		winner = state.winner,
		how = state.how,
		shots = table.clone(state.shots),
		banks = table.clone(state.banks),
	}
end

function BumperPool.view(state: State): { [string]: any }
	local balls: { number } = {}
	for _, s in state.spots do
		table.insert(balls, s.id)
		table.insert(balls, s.x)
		table.insert(balls, s.z)
	end
	return {
		kind = "bumper_pool",
		phase = state.phase,
		turn = BumperPool.turn(state),
		waiting = BumperPool.waiting(state),
		openers = table.clone(state.openers),
		balls = balls,
		sunk = table.clone(state.sunk),
		markedDown = table.clone(state.markedDown),
		shots = table.clone(state.shots),
		banks = table.clone(state.banks),
		done = state.done,
		winner = state.winner,
		how = state.how,
		last = state.last,
	}
end

return BumperPool
