--!strict
-- ReplicatedStorage.Shared.Minigames.Pool.EightBall
-- Eight-ball on the pool tables: the rules as a state machine in the shape of Minigame.Rules, and the table
-- itself. The state holds where every ball lies; a player's inputs are the ones a person at the table gives
-- (set the cue ball down when it is in hand, call a pocket for the 8, strike), and "shoot" runs the table
-- model (Shot) on the spot, judges what happened and keeps the shot's script for every client to play. So
-- the same pure module is the referee on the server, the game a computer player plays, and a whole game
-- under Lune. It corrects MinigameRules/Pool8Ball (which stays for the old "shot" verb) on the checklist's
-- lines:
--   POOL-R1 any break leaves the table open; the first legal pot after the break gives solids (1-7) or
--           stripes (9-15); fouls are the cue ball potted ("scratch"), touching no ball ("no_hit"), the
--           wrong ball first ("wrong_ball") and no cushion and no pot after the contact ("no_rail"); a foul
--           gives the other player the cue ball in hand; the 8 potted on the break comes back on the foot
--           spot; the 8 potted legally after your group is cleared wins; the 8 early or with a foul loses;
--           a legal pot of your own ball keeps the table.
--           The break is the shot that first touches the rack: a cue ball that touches nothing (a tap, a
--           miss, a scratch on the way) is a foul and the rack is still to be broken, by the other player,
--           from behind the head string (a cue ball that stopped past it goes back on the head spot). A cue
--           ball that meets two balls lying together at the same instant has hit whichever of them is legal
--           (a referee could not separate them either).
--   POOL-R2 the 8 needs a called pocket (only the 8 is called): the 8 in any other pocket loses.
--   POOL-R3 a scratch on the break gives ball in hand behind the head string; every other foul, anywhere.
--   POOL-R4 on an open table a shot that pots a solid and a stripe leaves the table open (and the shooter on
--           it); pots are taken in the order the balls dropped.
--   POOL-R5 no ball can leave the table (the model never lifts one), so there is no such foul.
--   POOL-R6 seats = 1 is practice: the same rules against no one; the result is shots taken and best run.
--           A run is the balls a player pots for themselves in one visit: their own group (on the break,
--           and while the table is open, everything that drops) and the winning 8. The other player's balls
--           going down do not lengthen it.
--   POOL-R7 an idle turn is a foul (skipTurn): the other player has the ball in hand.
--   A player who leaves a game against someone else forfeits it (gone): the other wins, "left the table".
-- Pure and seeded: the same seed and the same inputs give the same game, byte for byte. Lune-tested
-- (tests/unit/pool_eightball.spec.luau).
-- Interface: def, verbs; init(seats, seed, breaker?) -> State; input(state, seat, verb, args) with verbs
--   "place" { x, z }, "call" { pocket 1..6 }, "shoot" { angle, power, tipX?, tipY?, pocket? }; turn(state);
--   skipTurn(state); gone(state, seat) (a forfeit); result(state); view(state); script(state) -> the last shot's Shot.Script?;
--   apply(state, outcome, rest?) -> event (the referee alone: "foul" | "continue" | "pass" | "win" |
--   "lose"); groupOf(ball); onEight(state, seat); legal(state, seat) -> { ball ids the seat may hit first };
--   left(state, seat) -> balls of its group still up (7 while the table is open); canPlace(state, x, z);
--   FOUL_TEXT, HOW_TEXT (plain words for the HUD)

local Cue = require("./Cue")
local Shot = require("./Shot")
local Tables = require("./Tables")

local EightBall = {}

EightBall.def = {
	game = "pool",
	title = "Eight-ball",
	class = "shared_table" :: "shared_table",
	seats = 2,
	authority = "server",
	money = "none",
}
EightBall.verbs = { place = true, call = true, shoot = true }

EightBall.FOUL_TEXT = {
	scratch = "the cue ball went in",
	no_hit = "the cue ball hit nothing",
	wrong_ball = "the cue ball hit the wrong ball first",
	no_rail = "no ball reached a cushion",
	idle = "the clock ran out",
} :: { [string]: string }
EightBall.HOW_TEXT = {
	eight = "potted the 8 in the called pocket",
	eight_early = "potted the 8 too early",
	eight_foul = "fouled on the 8",
	eight_wrong_pocket = "potted the 8 in the wrong pocket",
	left = "left the table",
} :: { [string]: string }

export type PotAt = { ball: number, hole: number }
export type Outcome = {
	firstHit: number, -- the first ball the cue ball touched (0: none)
	firstAll: { number }?, -- every ball it touched at that first instant (nil: only firstHit)
	pots: { PotAt }, -- in the order they dropped; the cue ball is ball 0
	railAfter: boolean, -- after the first contact some ball reached a cushion
}
export type Last = {
	seat: number,
	event: string, -- "foul" | "continue" | "pass" | "win" | "lose"
	foul: string?, -- a key of FOUL_TEXT
	pots: { number }, -- balls in drop order
	holes: { number }, -- and the pocket each went in
	firstHit: number, -- the ball the shot is judged to have hit first (0: none)
	breakShot: boolean, -- the rack had not been broken when it was played
}
export type State = {
	seats: number,
	seed: number,
	seat: number,
	spots: { Tables.Spot }, -- every ball on the table (the cue ball is id 0)
	onTable: { [number]: boolean }, -- 1..15
	group: { [number]: string? }, -- seat -> "solids" | "stripes"
	broken: boolean,
	inHand: string, -- "none" | "kitchen" (behind the head string) | "anywhere"
	called: number, -- the pocket called for the 8 (0: none)
	done: boolean,
	winner: number?,
	how: string?, -- a key of HOW_TEXT
	shotNo: number,
	shots: { number }, -- per seat
	run: { number }, -- balls potted this visit
	bestRun: { number },
	fouls: { number },
	down: { number }, -- object balls potted, in order (the rack window)
	last: Last?,
	lastScript: Shot.Script?,
}

function EightBall.groupOf(ball: number): string
	if ball >= 1 and ball <= 7 then
		return "solids"
	elseif ball >= 9 and ball <= 15 then
		return "stripes"
	elseif ball == 8 then
		return "eight"
	end
	return "cue"
end

function EightBall.init(seats: number, seed: number, breaker: number?): State
	local onTable: { [number]: boolean } = {}
	for b = 1, 15 do
		onTable[b] = true
	end
	local first = if breaker and breaker >= 1 and breaker <= seats then breaker else 1
	return {
		seats = seats,
		seed = seed,
		seat = first,
		spots = Tables.rack(seed),
		onTable = onTable,
		group = {},
		broken = false,
		inHand = "kitchen",
		called = 0,
		done = false,
		winner = nil,
		how = nil,
		shotNo = 0,
		shots = table.create(seats, 0),
		run = table.create(seats, 0),
		bestRun = table.create(seats, 0),
		fouls = table.create(seats, 0),
		down = {},
		last = nil,
		lastScript = nil,
	}
end

local function other(state: State, seat: number): number
	return if state.seats < 2 then seat else (seat % state.seats) + 1
end

function EightBall.left(state: State, seat: number): number
	local g = state.group[seat]
	if g == nil then
		return 7
	end
	local n = 0
	for b = 1, 15 do
		if b ~= 8 and state.onTable[b] and EightBall.groupOf(b) == g then
			n += 1
		end
	end
	return n
end

-- Is this seat shooting at the 8 (its group is cleared)?
function EightBall.onEight(state: State, seat: number): boolean
	return state.group[seat] ~= nil and EightBall.left(state, seat) == 0
end

-- The balls this seat may legally touch first.
function EightBall.legal(state: State, seat: number): { number }
	local out: { number } = {}
	local mine = state.group[seat]
	local eight = EightBall.onEight(state, seat)
	for b = 1, 15 do
		if state.onTable[b] then
			local ok: boolean
			if not state.broken then
				ok = true
			elseif mine == nil then
				ok = b ~= 8
			elseif eight then
				ok = b == 8
			else
				ok = EightBall.groupOf(b) == mine
			end
			if ok then
				table.insert(out, b)
			end
		end
	end
	return out
end

function EightBall.turn(state: State): number?
	return if state.done then nil else state.seat
end

local function removeSpot(spots: { Tables.Spot }, id: number)
	for i = #spots, 1, -1 do
		if spots[i].id == id then
			table.remove(spots, i)
		end
	end
end

-- The referee: one shot's outcome applied to the game. `rest` is where the balls stopped (from the model);
-- without it (a spec, or the old table) the balls stay where the state has them and the potted ones go.
function EightBall.apply(state: State, o: Outcome, rest: { Tables.Spot }?): string
	local tb = Tables.eightBall()
	local seat = state.seat
	local opp = other(state, seat)
	local mine = state.group[seat]
	local breakShot = not state.broken
	local onEight = EightBall.onEight(state, seat)
	local called = state.called
	state.shotNo += 1
	state.shots[seat] += 1
	-- the rack is broken by the shot that first touches a ball; until then every shot is a break
	if o.firstHit ~= 0 then
		state.broken = true
	end
	state.inHand = "none"
	state.called = 0
	if rest then
		state.spots = rest
	end
	local scratch = false
	local eightHole = 0
	local solids, stripes = 0, 0
	local potIds: { number } = {}
	local potHoles: { number } = {}
	for _, p in o.pots do
		if p.ball == 0 then
			if not scratch then
				scratch = true
				table.insert(potIds, 0)
				table.insert(potHoles, p.hole)
				removeSpot(state.spots, 0)
			end
		elseif p.ball == 8 then
			if eightHole == 0 and state.onTable[8] then
				eightHole = p.hole
				table.insert(potIds, 8)
				table.insert(potHoles, p.hole)
				removeSpot(state.spots, 8)
			end
		elseif state.onTable[p.ball] then
			state.onTable[p.ball] = false
			table.insert(state.down, p.ball)
			table.insert(potIds, p.ball)
			table.insert(potHoles, p.hole)
			removeSpot(state.spots, p.ball)
			if p.ball < 8 then
				solids += 1
			else
				stripes += 1
			end
		end
	end
	local anyPot = solids + stripes > 0 or eightHole > 0
	-- was the first contact legal? Two balls met at the same instant: either will do
	local firstHit = o.firstHit
	local legalFirst = false
	if firstHit ~= 0 then
		local met: { number } = o.firstAll or { firstHit }
		for _, ball in met do
			local ok: boolean
			if breakShot then
				ok = true
			elseif mine == nil then
				ok = ball ~= 8
			elseif onEight then
				ok = ball == 8
			else
				ok = EightBall.groupOf(ball) == mine
			end
			if ok then
				legalFirst = true
				firstHit = ball
				break
			end
		end
	end
	local foul: string? = nil
	if scratch then
		foul = "scratch"
	elseif o.firstHit == 0 then
		foul = "no_hit"
	elseif not legalFirst then
		foul = "wrong_ball"
	elseif not anyPot and not o.railAfter and not breakShot then
		foul = "no_rail"
	end
	local event: string
	if eightHole > 0 and not breakShot then
		state.onTable[8] = false
		state.done = true
		if onEight and foul == nil and eightHole == called then
			state.winner = seat
			state.how = "eight"
			event = "win"
		else
			state.winner = if state.seats > 1 then opp else nil
			state.how = if not onEight then "eight_early" elseif foul ~= nil then "eight_foul" else "eight_wrong_pocket"
			event = "lose"
		end
	else
		if eightHole > 0 then
			-- the 8 on the break comes back on the foot spot (or the nearest free place behind it)
			local x, z = Tables.freeSpot(tb, 0, tb.footZ, state.spots, 1)
			table.insert(state.spots, { id = 8, x = x, z = z })
		end
		-- groups go to the first legal pot after the break; one of each leaves the table open
		if mine == nil and not breakShot and foul == nil and (solids > 0) ~= (stripes > 0) then
			local g = if solids > 0 then "solids" else "stripes"
			state.group[seat] = g
			if state.seats > 1 then
				state.group[opp] = if g == "solids" then "stripes" else "solids"
			end
			mine = g
		end
		local ownPot = (mine == "solids" and solids > 0) or (mine == "stripes" and stripes > 0)
		if foul ~= nil then
			event = "foul"
		elseif ownPot or (breakShot and anyPot) or (mine == nil and anyPot) then
			event = "continue"
		else
			event = "pass"
		end
	end
	if scratch and not state.done then
		-- the cue ball comes back on the head spot until the incoming player sets it down
		local x, z = Tables.freeSpot(tb, 0, tb.headZ, state.spots, -1)
		table.insert(state.spots, { id = 0, x = x, z = z })
	end
	if foul ~= nil then
		state.fouls[seat] += 1
	end
	if event == "continue" or event == "win" then
		-- a run is what the shooter potted for themselves: their own group (`mine` is the group this shot
		-- took, if it took one), or everything on the break and while the table stays open; and the winning 8
		local own = if breakShot or mine == nil then solids + stripes elseif mine == "solids" then solids else stripes
		state.run[seat] += own + (if event == "win" then 1 else 0)
		if state.run[seat] > state.bestRun[seat] then
			state.bestRun[seat] = state.run[seat]
		end
	else
		state.run[seat] = 0
	end
	if not state.done then
		if event == "foul" then
			state.seat = opp
			-- behind the head string after a scratch on the break (POOL-R3), and while the rack is unbroken
			state.inHand = if (breakShot and scratch) or not state.broken then "kitchen" else "anywhere"
			if state.inHand == "kitchen" then
				-- a cue ball lying past the head string (a tap that stopped short of the rack) is brought back
				-- to the head spot, so the break cannot be played from where it lies
				for _, sp in state.spots do
					if sp.id == 0 and not Tables.inKitchen(tb, sp.z) then
						sp.x, sp.z = 0, -1e6 -- out of the way while a free place is found
						sp.x, sp.z = Tables.freeSpot(tb, 0, tb.headZ, state.spots, -1)
					end
				end
			end
		elseif event == "pass" then
			state.seat = opp
		end
	end
	state.last = {
		seat = seat,
		event = event,
		foul = foul,
		pots = potIds,
		holes = potHoles,
		firstHit = firstHit,
		breakShot = breakShot,
	}
	return event
end

local function num(v: any): number?
	if type(v) == "number" and v == v and v > -1e6 and v < 1e6 then
		return v
	end
	return nil
end

-- May the cue ball be set down here (it is in hand)?
function EightBall.canPlace(state: State, x: number, z: number): boolean
	if state.inHand == "none" then
		return false
	end
	local tb = Tables.eightBall()
	if state.inHand == "kitchen" and not Tables.inKitchen(tb, z) then
		return false
	end
	return Tables.canPlace(tb, x, z, state.spots, 0)
end

function EightBall.input(state: State, seat: number, verb: string, args: { any }?): (boolean, string?)
	if state.done then
		return false, "game over"
	end
	if seat ~= state.seat then
		return false, "not your turn"
	end
	local a: { any } = args or {}
	if verb == "place" then
		local x, z = num(a[1]), num(a[2])
		if x == nil or z == nil then
			return false, "args"
		end
		if state.inHand == "none" then
			return false, "not in hand"
		end
		if not EightBall.canPlace(state, x, z) then
			return false, "cannot place there"
		end
		for _, s in state.spots do
			if s.id == 0 then
				s.x, s.z = x, z
			end
		end
		return true, nil
	elseif verb == "call" then
		local p = num(a[1])
		if p == nil or p % 1 ~= 0 or p < 1 or p > 6 then
			return false, "args"
		end
		if not EightBall.onEight(state, seat) then
			return false, "only the 8 is called"
		end
		state.called = p
		return true, nil
	elseif verb == "shoot" then
		local angle, power = num(a[1]), num(a[2])
		if angle == nil or power == nil then
			return false, "args"
		end
		local tipX, tipY = num(a[3]) or 0, num(a[4]) or 0
		if EightBall.onEight(state, seat) then
			local p = num(a[5])
			if p ~= nil and p % 1 == 0 and p >= 1 and p <= 6 then
				state.called = p
			end
			if state.called == 0 then
				return false, "call a pocket"
			end
		end
		local tb = Tables.eightBall()
		local strike = Cue.strike(0, angle, power, tipX, tipY, state.seed * 7919 + state.shotNo)
		local script = Shot.run(tb, state.spots, { strike })
		local pots: { PotAt } = {}
		for _, p in Shot.pots(script) do
			table.insert(pots, { ball = p.ball, hole = p.hole })
		end
		state.lastScript = script
		EightBall.apply(
			state,
			{ firstHit = script.first[1], firstAll = script.firstAll[1], pots = pots, railAfter = script.railAfter },
			Shot.rest(script)
		)
		return true, nil
	end
	return false, "verb"
end

-- An idle (or vacated) turn is a foul: the other player has the ball in hand.
function EightBall.skipTurn(state: State)
	if state.done then
		return
	end
	local seat = state.seat
	state.fouls[seat] += 1
	state.run[seat] = 0
	state.called = 0
	state.last = {
		seat = seat,
		event = "foul",
		foul = "idle",
		pots = {},
		holes = {},
		firstHit = 0,
		breakShot = not state.broken,
	}
	state.lastScript = nil
	state.seat = other(state, seat)
	state.inHand = if state.broken then "anywhere" else "kitchen"
end

-- A seat has left a game against someone else: they forfeit it, and the one still at the table wins.
function EightBall.gone(state: State, seat: number)
	if state.done or state.seats < 2 then
		return
	end
	state.done = true
	state.winner = other(state, seat)
	state.how = "left"
	state.called = 0
	state.last = {
		seat = seat,
		event = "lose",
		pots = {},
		holes = {},
		firstHit = 0,
		breakShot = not state.broken,
	}
	state.lastScript = nil
end

function EightBall.script(state: State): Shot.Script?
	return state.lastScript
end

function EightBall.result(state: State): { [string]: any }?
	if not state.done then
		return nil
	end
	local scores: { [number]: number } = {}
	local left: { number } = {}
	for s = 1, state.seats do
		left[s] = EightBall.left(state, s)
		scores[s] = 7 - left[s]
	end
	return {
		done = true,
		scores = scores,
		winner = state.winner,
		how = state.how,
		left = left,
		shots = table.clone(state.shots),
		bestRun = table.clone(state.bestRun),
		fouls = table.clone(state.fouls),
	}
end

function EightBall.view(state: State): { [string]: any }
	local onTable: { number } = {}
	for b = 1, 15 do
		if state.onTable[b] then
			table.insert(onTable, b)
		end
	end
	local balls: { number } = {}
	for _, s in state.spots do
		table.insert(balls, s.id)
		table.insert(balls, s.x)
		table.insert(balls, s.z)
	end
	local left: { number } = {}
	for s = 1, state.seats do
		left[s] = EightBall.left(state, s)
	end
	return {
		kind = "pool",
		turn = if state.done then nil else state.seat,
		groups = { state.group[1] or "", state.group[2] or "" },
		open = state.group[1] == nil,
		broken = state.broken,
		onTable = onTable,
		balls = balls,
		left = left,
		inHand = state.inHand,
		onEight = not state.done and EightBall.onEight(state, state.seat),
		called = state.called,
		down = table.clone(state.down),
		shots = table.clone(state.shots),
		bestRun = table.clone(state.bestRun),
		done = state.done,
		winner = state.winner,
		how = state.how,
		last = state.last,
	}
end

return EightBall
