--!strict
-- ReplicatedStorage.Shared.Minigames.AirHockey.Referee
-- The match as the server decides it: ONE simulation (Sim, the owner's), stepped tick by tick from the hands'
-- logs, and the stream everyone else replays (Wire's "air_hockey" message).
-- Time is counted in ticks of 1/240 s from t0 on the shared clock; tick k is the k-th step, and a hand's event
-- "on tick k" is applied just before it. Each side is a person (their log decides their mallet) or the computer
-- (the simulation's own opponent). The referee never steps a tick by a clock of its own:
--   one person against the computer: it steps exactly as far as that person's log has arrived (their own
--     screen ran the same simulation with the same numbers at once, so what they saw is what is decided here);
--   two people: it steps as far as BOTH logs have arrived. A hand that is more than Wire.MAX_BEHIND ticks behind
--     the clock is not waited for: the match plays on with that mallet held where it was aimed, and the late
--     part of that log is dropped when it comes (it is still taken, so that player's log stays in one piece;
--     the stream tells them what was played instead). Only as a match starts is a hand waited for longer
--     (Wire.START_WAIT), until its first segment has come.
-- A log segment is refused only if it does not start where that player's last one ended, is too long, or claims
-- ticks the shared clock has not reached (plus Wire.SLACK).
-- Pure. Interface: new(opts { t0, game, human = { [0] = bool, [1] = bool }, difficulty }) -> Referee;
--   accept(r, side, from, to, strings, nowTick) -> (ok, why?); advance(r, nowTick) -> (message?, { goal }) (the
--   stream message for the ticks just decided, and the goals scored in them: { side, score0, score1, winner });
--   snapshot(r) -> message (no ticks: the state as it stands, for someone arriving); control(r, side, human);
--   mode(r) -> "0" | "1" | "2" | nil; expects(r, side) -> the tick that side's next segment must start from;
--   over(r) -> bool

local Sim = require("./Sim")
local Wire = require("./Wire")

local Referee = {}

export type Goal = { side: number, score0: number, score1: number, winner: number }
export type Referee = {
	sim: Sim.State,
	n: number, -- ticks decided
	t0: number, -- when tick 0 was, on the shared clock
	game: number, -- which match this is (a client holding another match's state starts afresh)
	human: { [number]: boolean },
	got: { [number]: number }, -- side -> where that player's next segment must start (their log, in one piece)
	recv: { [number]: number }, -- side -> the tick up to which that side's hand is known or was played without
	events: { [number]: { [number]: any } }, -- side -> the events not yet played, by tick
	cuts: number, -- ticks played without waiting for a late hand
	fresh: { [number]: boolean }, -- side -> a person there from the start whose first segment has not come yet
}

function Referee.new(opts: { t0: number, game: number, human: { [number]: boolean }, difficulty: number? }): Referee
	local sim = Sim.new()
	sim.difficulty = opts.difficulty or 1
	return {
		sim = sim,
		n = 0,
		t0 = opts.t0,
		game = opts.game,
		human = { [0] = opts.human[0] == true, [1] = opts.human[1] == true },
		got = { [0] = 0, [1] = 0 },
		recv = { [0] = 0, [1] = 0 },
		events = { [0] = {}, [1] = {} },
		cuts = 0,
		fresh = { [0] = opts.human[0] == true, [1] = opts.human[1] == true },
	}
end

function Referee.over(r: Referee): boolean
	return r.sim.winner >= 0
end

function Referee.mode(r: Referee): string?
	if r.human[0] and r.human[1] then
		return "2"
	elseif r.human[0] then
		return "0"
	elseif r.human[1] then
		return "1"
	end
	return nil
end

function Referee.expects(r: Referee, side: number): number
	return r.got[side]
end

-- A side changes hands (a person sits down at the computer's end, or leaves it to the computer). A person's log
-- starts at the tick the match has reached.
function Referee.control(r: Referee, side: number, human: boolean)
	r.human[side] = human
	r.got[side] = r.n
	r.recv[side] = r.n
	r.fresh[side] = false
	table.clear(r.events[side])
end

function Referee.accept(
	r: Referee,
	side: number,
	from: any,
	to: any,
	strings: { any },
	nowTick: number
): (boolean, string?)
	if not r.human[side] then
		return false, "The computer is playing that end"
	end
	if
		type(from) ~= "number"
		or type(to) ~= "number"
		or from % 1 ~= 0
		or to % 1 ~= 0
		or from ~= r.got[side]
		or to <= from
		or to - from > Wire.MAX_SEGMENT
	then
		return false, "That part of the game arrived out of order"
	end
	if to > nowTick + Wire.SLACK then
		return false, "That part of the game is ahead of the clock"
	end
	local events = Wire.unpack(strings, from, to)
	if events == nil then
		return false, "That part of the game could not be read"
	end
	local mine = r.events[side]
	for tick, e in events do
		-- (ticks already played without this hand are gone)
		if tick > r.n then
			mine[tick] = e
		end
	end
	r.got[side] = to
	r.recv[side] = math.max(r.recv[side], to)
	r.fresh[side] = false
	return true
end

local function message(r: Referee, n0: number, a: string, b: string): { [string]: any }
	return {
		kind = "air_hockey",
		g = r.game,
		n0 = n0,
		n = r.n,
		m = Referee.mode(r) or "",
		a = a,
		b = b,
		s = Wire.state(r.sim),
		t0 = r.t0,
	}
end

function Referee.snapshot(r: Referee): { [string]: any }
	return message(r, r.n, "", "")
end

-- Step as far as the hands allow. nowTick is the shared clock's tick (only a bound on how long a late hand is
-- waited for).
function Referee.advance(r: Referee, nowTick: number): ({ [string]: any }?, { Goal })
	local goals: { Goal } = {}
	local sim = r.sim
	local mode = Referee.mode(r)
	if mode == nil or sim.winner >= 0 then
		return nil, goals
	end
	local target: number
	if mode == "2" then
		local slow = math.min(r.recv[0], r.recv[1])
		local fast = math.max(r.recv[0], r.recv[1])
		-- wait for both hands, but not for long: past MAX_BEHIND the match goes on (never beyond the hand that
		-- did arrive, and never beyond the clock)
		target = math.max(slow, math.min(fast, nowTick - Wire.MAX_BEHIND))
		if (r.fresh[0] or r.fresh[1]) and nowTick < Wire.START_WAIT then
			-- (as a match starts, a player who has only just been told is waited for a little longer: nothing
			-- of the hand they had on the table before the first serve is thrown away)
			target = slow
		end
	else
		target = r.recv[if mode == "0" then 0 else 1]
	end
	if target <= r.n then
		return nil, goals
	end
	local n0 = r.n
	local human = if mode == "1" then 1 else 0
	local computer = mode ~= "2"
	local played: { [number]: { [number]: any } } = { [0] = {}, [1] = {} }
	while r.n < target and sim.winner < 0 do
		local tick = r.n + 1
		for side = 0, 1 do
			if r.human[side] then
				local e = r.events[side][tick]
				if e then
					r.events[side][tick] = nil
					played[side][tick] = e
					if e[3] and sim.countdown > 0 then
						Sim.serve(sim)
					end
					if e[1] then
						local x, y = Wire.target(side, e[1], e[2])
						Sim.setTarget(sim, side, x, y)
					end
				end
				if tick > r.recv[side] then
					-- played without this hand: its log, when it comes, starts after this tick
					r.cuts += 1
				end
			end
		end
		local goalsBefore = sim.goalSerial
		Sim.play(sim, human, computer)
		r.n = tick
		if sim.goalSerial ~= goalsBefore then
			table.insert(goals, { side = sim.lastGoal, score0 = sim.score0, score1 = sim.score1, winner = sim.winner })
		end
	end
	for side = 0, 1 do
		if r.human[side] and r.recv[side] < r.n then
			r.recv[side] = r.n
			-- (anything of that hand's that was already here for the ticks cut is void)
			for tick in r.events[side] do
				if tick <= r.n then
					r.events[side][tick] = nil
				end
			end
		end
	end
	return message(r, n0, Wire.join(played[0], n0), Wire.join(played[1], n0)), goals
end

return Referee
