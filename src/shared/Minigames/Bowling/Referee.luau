--!strict
-- ReplicatedStorage.Shared.Minigames.Bowling.Referee
-- The decisions around a bowling throw that used to live inside the server service where no test could reach
-- them: WHOSE sheet a counted throw goes on (only the bowler who threw it, and only if it is still their turn:
-- a ball thrown by someone who then walked off is never scored against the next bowler), when the pins on the
-- lane no longer match what the rules expect and a fresh rack must be ordered (after a skipped or timed-out
-- frame), what the screen says about a throw (STRIKE, TURKEY, SPARE, SPLIT, Gutter ball, Missed everything, N
-- pins), the end-of-game summary, and the computer players (three skills; they aim at the pocket on a full
-- rack and at the pin nearest them on a spare, with aim and power error by skill, from a seeded stream).
-- Pure; Lune-tested (tests/unit/bowling_referee.spec.luau).
-- Interface: score(session, result, now) -> Verdict { applied, pins, rack, event?, mark?, text?, big, seat?,
--   over }; sync(session, standingCount) -> "full"?; callout(mark, pins, flags, streak, over) -> (text, big);
--   summary(view) -> Summary { rows = { { seat, name, total, strikes, spares, misses, gone, place } }, winner?,
--   tie, line }; AI = { { name, skill } }; SKILLS; skillOf(name) -> skill; aimAngle(offset, power, spin, x, d)
--   -> angle; aiThrow(rng, skill, mask) -> Params; playGame(skill, seed) -> (score, rolls)

local Rng = require("../../Util/Rng")
local Bowling = require("../MinigameRules/Bowling")
local Session = require("../Session")
local BallPath = require("./BallPath")
local PinModel = require("./PinModel")
local RollScript = require("./RollScript")

local Referee = {}

export type Verdict = {
	applied: boolean,
	pins: number,
	rack: string, -- what the pinsetter sets next: "full" | "keep"
	event: string?,
	mark: string?, -- the box just written: "X", "/", "-" or a digit
	text: string?,
	big: boolean,
	seat: number?,
	over: boolean,
}

-- What the banner says about a throw. mark is the scoreboard box it wrote.
function Referee.callout(
	mark: string,
	pins: number,
	flags: RollScript.Flags?,
	streak: number,
	over: boolean
): (string, boolean)
	local text: string
	local big = false
	if mark == "X" then
		big = true
		if streak >= 4 then
			text = `{streak} STRIKES IN A ROW!`
		elseif streak == 3 then
			text = "TURKEY! Three strikes in a row"
		elseif streak == 2 then
			text = "DOUBLE! Two strikes in a row"
		else
			text = "STRIKE!"
		end
	elseif mark == "/" then
		big = true
		text = "SPARE!"
	elseif flags and flags.gutter then
		text = "Gutter ball"
	elseif pins == 0 then
		text = "Missed everything"
	elseif flags and flags.split and flags.splitName then
		text = `SPLIT! The {flags.splitName} is left`
	else
		text = `{pins} pin{if pins == 1 then "" else "s"}`
	end
	if over then
		text ..= " - that is the game!"
	end
	return text, big
end

-- score: a counted throw goes onto the sheet of the bowler who threw it, if it is still their turn. Otherwise
-- (they left or were timed out while the ball rolled, or the game ended) nothing is scored and the lane is
-- re-racked for whoever is up now.
function Referee.score(
	session: any,
	result: { pins: number, seat: number?, flags: RollScript.Flags? },
	now: number
): Verdict
	local g = session.game
	local turn = Session.turn(session)
	if session.phase ~= "playing" or g == nil or turn == nil or result.seat ~= turn then
		return { applied = false, pins = result.pins, rack = "full", big = false, seat = result.seat, over = false }
	end
	local state = g.state
	local pins = math.clamp(math.floor(result.pins), 0, Bowling.standing(state))
	local ok = Session.apply(session, "server", "roll", { pins }, now)
	if not ok then
		return { applied = false, pins = pins, rack = "full", big = false, seat = turn, over = false }
	end
	local rolls = state.rolls[turn]
	local marks = Bowling.marks(rolls)
	local boxes = marks[#marks]
	local mark = boxes[#boxes]
	local over = state.done == true
	local text, big = Referee.callout(mark, pins, result.flags, Bowling.streak(rolls), over)
	return {
		applied = true,
		pins = pins,
		rack = if over then "full" else Bowling.rackFor(state),
		event = state.lastEvent,
		mark = mark,
		text = text,
		big = big,
		seat = turn,
		over = over,
	}
end

-- sync: the lane is ready and shows `standingCount` pins. If the rules expect a fresh ten (a frame was skipped
-- or timed out with pins down) and the lane shows fewer, a full rack must be set before anyone bowls.
function Referee.sync(session: any, standingCount: number): string?
	local g = session.game
	if session.phase ~= "playing" or g == nil then
		return if standingCount ~= Bowling.PINS then "full" else nil
	end
	if Bowling.standing(g.state) == Bowling.PINS and standingCount ~= Bowling.PINS then
		return "full"
	end
	return nil
end

export type Row = {
	seat: number,
	name: string,
	total: number,
	strikes: number,
	spares: number,
	misses: number,
	gone: boolean,
	place: number,
}
export type Summary = { rows: { Row }, winner: string?, tie: boolean, line: string }

-- summary: the end card from a session view (Session.view with Bowling.view inside): ranked rows and one line
-- that says who won.
function Referee.summary(view: { [string]: any }): Summary
	local rows: { Row } = {}
	local g = view.game
	for s, seat in view.seats or {} do
		local gs = g and g.seats and g.seats[s]
		local st = gs and gs.stats
		table.insert(rows, {
			seat = s,
			name = tostring(seat.name),
			total = if gs then gs.total else 0,
			strikes = if st then st.strikes else 0,
			spares = if st then st.spares else 0,
			misses = if st then st.misses else 0,
			gone = seat.gone == true,
			place = 0,
		})
	end
	table.sort(rows, function(a, b)
		if a.total ~= b.total then
			return a.total > b.total
		end
		return a.seat < b.seat
	end)
	for i, r in rows do
		r.place = if i > 1 and rows[i - 1].total == r.total then rows[i - 1].place else i
	end
	local line, winner, tie = "Game over", nil :: string?, false
	if #rows == 1 then
		line = `Final score: {rows[1].total}`
	elseif #rows > 1 then
		if rows[2].place == 1 then
			tie = true
			line = `A tie at {rows[1].total}!`
		else
			winner = rows[1].name
			line = `{rows[1].name} wins with {rows[1].total}!`
		end
	end
	return { rows = rows, winner = winner, tie = tie, line = line }
end

-- Computer players ----------------------------------------------------------------------------------------------
-- aim: the largest aiming error (radians); step: error in where they stand (offset units); power: the range
-- they throw in (the sweet band is 0.55 to 0.85); hook: the spin they put on a first ball.
Referee.SKILLS = {
	easy = { aim = 0.065, step = 0.32, power = { 0.25, 1.0 }, hook = 0 },
	normal = { aim = 0.03, step = 0.15, power = { 0.5, 0.92 }, hook = 0 },
	sharp = { aim = 0.008, step = 0.04, power = { 0.6, 0.82 }, hook = -0.6 },
}
Referee.AI = {
	{ name = "Bowlbot", skill = "normal" },
	{ name = "Gutter Gus", skill = "easy" },
	{ name = "Strike Sally", skill = "sharp" },
}

function Referee.skillOf(name: string): string
	for _, a in Referee.AI do
		if string.find(name, a.name, 1, true) then
			return a.skill
		end
	end
	return "normal"
end

-- The angle that puts the ball's centre at x across the lane when it is d down it, for a throw from this
-- offset with this power and spin (a few corrections against the real path, so hooks are allowed for).
function Referee.aimAngle(offset: number, power: number, spin: number, x: number, d: number): number
	local run = d - BallPath.RELEASE_D
	local limit = BallPath.RANGES.angle
	local angle = math.clamp(math.atan((x - BallPath.releaseX(offset)) / run), -limit, limit)
	if spin == 0 then
		return angle
	end
	for _ = 1, 5 do
		local path = BallPath.trace({ offset = offset, angle = angle, power = power, spin = spin })
		local e = path.entry
		local at: number
		if e then
			at = e.x + e.vx / e.vd * (d - PinModel.DECK_START)
		else
			-- it hooked off the lane: aim back the other way
			at = (path.gutterSide or 1) * 3
		end
		angle = math.clamp(angle - (at - x) / run, -limit, limit)
	end
	return angle
end

-- What a computer player throws at the pins that stand.
function Referee.aiThrow(rng: { next: () -> number }, skill: string, mask: { boolean }): BallPath.Params
	local S = (Referee.SKILLS :: any)[skill] or Referee.SKILLS.normal
	local targetX, targetD = 0.25, PinModel.DECK_START + 1.3
	local spin = 0
	local offset
	if PinModel.count(mask) == 10 then
		-- the pocket; a hooker stands to the right and lets the ball walk in
		spin = S.hook
		targetX = if spin ~= 0 then 0.27 else 0.25
		offset = if spin ~= 0 then 0.55 else 0.16
	else
		-- a spare: the pin nearest the bowler, leaning toward the rest of the leave
		local key = 1
		for n = 1, 10 do
			if mask[n] then
				key = n
				break
			end
		end
		local kx, kd = PinModel.spot(key)
		local sum, others = 0, 0
		for n = key + 1, 10 do
			if mask[n] then
				local ox = PinModel.spot(n)
				sum += ox
				others += 1
			end
		end
		targetX, targetD = kx, kd
		if others > 0 then
			targetX += math.clamp((sum / others - kx) * 0.35, -0.22, 0.22)
		end
		offset = math.clamp(targetX / BallPath.releaseX(1), -0.9, 0.9)
	end
	local lo, hi = S.power[1], S.power[2]
	local power = lo + (hi - lo) * rng.next()
	offset += (rng.next() * 2 - 1) * S.step
	-- three draws make the error bunch around zero: mostly close, sometimes well off
	local err = (rng.next() + rng.next() + rng.next() - 1.5) / 1.5
	local angle = Referee.aimAngle(offset, power, spin, targetX, targetD) + err * S.aim
	return BallPath.clamp({ offset = offset, angle = angle, power = power, spin = spin })
end

-- A whole solo game by a computer player through the real models (tests, tools/bowling/calibrate).
function Referee.playGame(skill: string, seed: number): (number, { number })
	local rng = Rng.new(seed)
	local state = Bowling.init(1, seed)
	local mask = PinModel.fullRack()
	local guard = 0
	while not state.done and guard < 30 do
		guard += 1
		local params = Referee.aiThrow(rng, skill, mask)
		local script = RollScript.build(params, mask, math.floor(rng.next() * 2147483647))
		local _, rack = Bowling.roll(state, 1, script.down)
		mask = if rack == "full" then PinModel.fullRack() else script.standing
	end
	return Bowling.total(state.rolls[1]), state.rolls[1]
end

return Referee
