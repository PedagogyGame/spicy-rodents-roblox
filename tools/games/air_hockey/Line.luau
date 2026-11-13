--!strict
-- tools/games/air_hockey/Line: a whole air hockey match over a made-up network, with no engine at all. The
-- table's referee (Shared/Minigames/AirHockey/Referee), one Seat for each person (their own prediction and
-- log) and any number of watchers' Replicas are joined by queues that deliver every message a chosen number of
-- frames late, each way. It is what the netcode's specs (tests/unit/air_hockey_netcode.spec.luau) and the
-- measurements (tools/games/air_hockey/netcode.luau) are run on: how far what a player is shown is from what
-- the referee decided for the same instant.
-- Interface: new(opts) -> Line; frame(line, dt?) (one frame of everybody); run(line, seconds) ; play(line,
--   limitSeconds) -> won; tell(line, msg) (a stream message to everyone, late like any other); hands.chaser(vigour?)
--   / hands.still / hands.swinger(period) / hands.pointer(noise?) / hands.keeper (a hand is fn(side, sim, tick)
--   -> (x, y, serve?): where that player's hand is, given what their own screen shows);
--   Line.ref / .seats[side] / .watchers / .truth (the referee's puck and mallets by tick) / .samples[side]
--   (what that seat was shown each frame); errors(line, side) -> { n, mean, p95, max } for: near / far (the
--   puck against the referee's for the same instant, by the half it was in), own / other (the mallets, the
--   same), puckShown / farShown (the puck and the far mallet against the referee's for the moment each was
--   drawn at), puckLate / farLate (how far behind the clock that moment was, seconds), and nearLive (the share
--   of the frames with the puck in this player's own half on which it was drawn where it was, to 5 mm);
--   smooth(line, side);
--   opts = { humans = { [0] = bool, [1] = bool }, lag = { [0] = frames, [1] = frames } (each way), hands =
--   { [side] = hand }, difficulty?, fps? (60), watchers? (how many, each `watchLag` frames away) }

local Referee = require("../../../src/shared/Minigames/AirHockey/Referee")
local Replica = require("../../../src/shared/Minigames/AirHockey/Replica")
local Seat = require("../../../src/shared/Minigames/AirHockey/Seat")
local Sim = require("../../../src/shared/Minigames/AirHockey/Sim")

local Line = {}

export type Hand = (side: number, sim: Sim.State, tick: number) -> (number, number, boolean?)

Line.hands = {}

-- A mallet that never moves.
function Line.hands.still(side: number, _sim: Sim.State, _tick: number): (number, number, boolean?)
	return 0, if side ~= 0 then 0.8 else -0.8, false
end

-- A player who goes for the puck: behind it when it is in their half, then through it at the far goal (the
-- computer's own plan, played with a person's faster hand), with a wobble so that no two rallies are alike.
function Line.hands.chaser(vigour: number?): Hand
	local scratch = Sim.new()
	local k = vigour or 1
	return function(side: number, sim: Sim.State, tick: number): (number, number, boolean?)
		Sim.copy(scratch, sim)
		Sim.ai(scratch, side)
		local x = if side ~= 0 then scratch.t1x else scratch.t0x
		local y = if side ~= 0 then scratch.t1y else scratch.t0y
		local wobble = math.sin(tick * 0.011 + side) * 0.03 * k
		return x + wobble, y + math.cos(tick * 0.007) * 0.02 * k, sim.countdown > 0 and tick % 97 == 0
	end
end

-- The plainest mouse hand there is: the pointer is put on the puck whenever the puck is in this player's half (a
-- shade behind it, with a wobble of `noise` metres), and waits in front of the goal otherwise. It is what a new
-- player does, and it is the hand that presses pucks into rails. (The wobble is a triangle wave, plain
-- arithmetic: recorded results of matches played with this hand are the same on every machine.)
function Line.hands.pointer(noise: number?): Hand
	local n = noise or 0.02
	return function(side: number, sim: Sim.State, tick: number): (number, number, boolean?)
		local s = if side ~= 0 then 1 else -1
		if sim.py * s > 0.02 then
			local wobble = 4 * math.abs((tick / 480) % 1 - 0.5) - 1
			return sim.px + wobble * n, sim.py + s * 0.03, false
		end
		return sim.px * 0.5, s * 0.9, false
	end
end

-- A goalkeeper: along the goal line under the puck, never striking.
function Line.hands.keeper(side: number, sim: Sim.State, _tick: number): (number, number, boolean?)
	return math.clamp(sim.px, -0.2, 0.2), if side ~= 0 then 1.0 else -1.0, false
end

-- A hand that sweeps from side to side across its half, whatever the puck does (the worst case for anyone
-- trying to guess it).
function Line.hands.swinger(period: number): Hand
	return function(side: number, _sim: Sim.State, tick: number): (number, number, boolean?)
		local s = if side ~= 0 then 1 else -1
		local a = tick / period * math.pi * 2
		return math.sin(a) * 0.45, s * (0.55 + math.cos(a * 1.7) * 0.3), false
	end
end

function Line.new(opts: { [string]: any }): any
	local humans = opts.humans or { [0] = true, [1] = false }
	local line: any = {
		fps = opts.fps or 60,
		time = 0,
		frames = 0,
		lag = opts.lag or { [0] = 0, [1] = 0 },
		hands = opts.hands or {},
		ref = Referee.new({ t0 = 0, game = 1, human = humans, difficulty = opts.difficulty }),
		seats = {},
		up = {}, -- { at = frame, side, from, to, strings }
		down = {}, -- { at = frame, to = seat | replica, msg }
		watchers = {},
		watchLag = opts.watchLag or 3,
		truth = {}, -- tick -> { px, py, p0x, p0y, p1x, p1y }
		truthRep = Replica.new(),
		samples = { [0] = {}, [1] = {} },
		sent = { [0] = 0, [1] = 0 },
		upAt = { [0] = 0, [1] = 0 },
		downAt = { [0] = 0, [1] = 0 },
		refused = {},
		goals = {},
	}
	local s = line.ref.sim
	line.truth[0] = { s.px, s.py, s.p0x, s.p0y, s.p1x, s.p1y }
	for side = 0, 1 do
		if humans[side] then
			local seat = Seat.new(side)
			line.seats[side] = seat
			-- (the referee's two words to a player as a match starts)
			table.insert(line.down, { at = line.lag[side], begin = { 1, 0 }, to = seat })
			table.insert(line.down, { at = line.lag[side], msg = Referee.snapshot(line.ref), to = seat })
		end
	end
	for i = 1, opts.watchers or 0 do
		line.watchers[i] = Replica.new()
	end
	Replica.push(line.truthRep, Referee.snapshot(line.ref))
	return line
end

local function broadcast(line: any, msg: any)
	Replica.push(line.truthRep, msg)
	Replica.step(line.truthRep, nil, function(sim: Sim.State, tick: number)
		line.truth[tick] = { sim.px, sim.py, sim.p0x, sim.p0y, sim.p1x, sim.p1y }
	end)
	for side, seat in line.seats do
		-- (a line keeps its order: a message never overtakes the one sent before it)
		line.downAt[side] = math.max(line.downAt[side], line.frames + line.lag[side])
		table.insert(line.down, { at = line.downAt[side], msg = msg, to = seat })
	end
	for _, watcher in line.watchers do
		table.insert(line.down, { at = line.frames + line.watchLag, msg = msg, watcher = watcher })
	end
end

-- (a message from the referee to everyone, for a case that changes who plays an end)
Line.tell = broadcast

local function pump(line: any)
	local msg, goals = Referee.advance(line.ref, math.floor(line.time * 240))
	if msg then
		broadcast(line, msg)
	end
	for _, goal in goals do
		table.insert(line.goals, goal)
	end
end

function Line.frame(line: any, dtIn: number?)
	local dt = dtIn or (1 / line.fps)
	line.frames += 1
	line.time += dt
	local nowTick = line.time * 240
	-- what the players sent arrives
	local i = 1
	while i <= #line.up do
		local m = line.up[i]
		if m.at <= line.frames then
			table.remove(line.up, i)
			local ok, why = Referee.accept(line.ref, m.side, m.from, m.to, m.strings, math.floor(nowTick))
			if not ok then
				table.insert(line.refused, `{m.side}: {why}`)
			end
			pump(line)
		else
			i += 1
		end
	end
	pump(line)
	-- what the referee sent arrives
	i = 1
	while i <= #line.down do
		local m = line.down[i]
		if m.at <= line.frames then
			table.remove(line.down, i)
			if m.watcher then
				Replica.push(m.watcher, m.msg)
			elseif m.begin then
				Seat.begin(m.to, m.begin[1], m.begin[2])
			else
				Seat.push(m.to, m.msg)
			end
		else
			i += 1
		end
	end
	-- each player's frame: the hand, the prediction, the log
	for side, seat in line.seats do
		local hand = line.hands[side] or Line.hands.still
		if seat.ready then
			local x, y, serve = hand(side, seat.pred, seat.tick)
			Seat.aim(seat, x, y)
			if serve then
				Seat.serve(seat)
			end
		end
		Seat.relax(seat, dt)
		Seat.step(seat, nowTick, function(from: number, to: number, strings: { string })
			line.sent[side] += 1
			line.upAt[side] = math.max(line.upAt[side], line.frames + line.lag[side])
			table.insert(line.up, { at = line.upAt[side], side = side, from = from, to = to, strings = strings })
		end)
		if seat.ready then
			local px, py, ax, ay, bx, by = Seat.view(seat)
			table.insert(line.samples[side], { nowTick, px, py, ax, ay, bx, by, seat.resims, seat.puckAt, seat.farAt })
		end
	end
	-- watchers replay a little behind the newest tick they have
	for _, watcher in line.watchers do
		Replica.step(watcher, watcher.head - 24)
	end
end

function Line.run(line: any, seconds: number)
	for _ = 1, math.floor(seconds * line.fps + 0.5) do
		Line.frame(line)
	end
end

-- Play until the referee has a winner (false: not within the limit).
function Line.play(line: any, limitSeconds: number): boolean
	for _ = 1, math.floor(limitSeconds * line.fps) do
		if Referee.over(line.ref) then
			return true
		end
		Line.frame(line)
	end
	return Referee.over(line.ref)
end

-- The referee's positions at a moment between ticks (nil: not decided yet).
local function truthAt(line: any, tickTime: number): { number }?
	local t0 = math.floor(tickTime)
	local a, b = line.truth[t0], line.truth[t0 + 1]
	local f = tickTime - t0
	if a == nil or (b == nil and f > 0) then
		return nil
	end
	if f == 0 or b == nil then
		return a
	end
	local out = {}
	for i = 1, 6 do
		out[i] = a[i] + (b[i] - a[i]) * f
	end
	if math.abs(b[1] - a[1]) + math.abs(b[2] - a[2]) > 0.2 then
		-- (the puck is put back on its spot within this tick: nobody slides it there)
		if f < 0.5 then
			out[1], out[2] = a[1], a[2]
		else
			out[1], out[2] = b[1], b[2]
		end
	end
	return out
end

local function summary(list: { number }): { n: number, mean: number, p95: number, max: number }
	table.sort(list)
	local sum = 0
	for _, v in list do
		sum += v
	end
	local n = #list
	return {
		n = n,
		mean = if n > 0 then sum / n else 0,
		p95 = if n > 0 then list[math.max(1, math.ceil(n * 0.95))] else 0,
		max = if n > 0 then list[n] else 0,
	}
end

-- How far what `side` was shown was from what the referee decided for the same instant, metres: the puck while
-- it was in that player's own half and while it was in the far half, the player's own mallet and the other one.
function Line.errors(line: any, side: number): { [string]: any }
	local s = if side ~= 0 then 1 else -1
	local near, far, own, other = {}, {}, {}, {}
	local puckShown, farShown, puckLate, farLate = {}, {}, {}, {}
	local undecided = 0
	local nearFrames, nearLive = 0, 0
	for _, sample in line.samples[side] do
		-- against what the referee decided for the moments the puck and the far mallet were drawn at
		local atPuck, atFar = truthAt(line, sample[9]), truthAt(line, sample[10])
		if sample[1] > line.ref.n then
			atPuck, atFar = nil, nil -- (the match is over: the clock runs on, the table does not)
		end
		if atPuck then
			table.insert(puckShown, math.sqrt((sample[2] - atPuck[1]) ^ 2 + (sample[3] - atPuck[2]) ^ 2))
			table.insert(puckLate, (sample[1] - sample[9]) / 240)
		end
		if atFar then
			table.insert(
				farShown,
				math.sqrt(
					(sample[6 - side * 2] - atFar[5 - side * 2]) ^ 2 + (sample[7 - side * 2] - atFar[6 - side * 2]) ^ 2
				)
			)
			table.insert(farLate, (sample[1] - sample[10]) / 240)
		end
		local truth = truthAt(line, sample[1])
		if truth == nil then
			undecided += 1
			continue
		end
		local dp = math.sqrt((sample[2] - truth[1]) ^ 2 + (sample[3] - truth[2]) ^ 2)
		table.insert(if truth[2] * s > 0 then near else far, dp)
		if truth[2] * s > 0 then
			nearFrames += 1
			if dp < 0.005 then
				nearLive += 1
			end
		end
		local mine = math.sqrt(
			(sample[4 + side * 2] - truth[3 + side * 2]) ^ 2 + (sample[5 + side * 2] - truth[4 + side * 2]) ^ 2
		)
		local theirs = math.sqrt(
			(sample[6 - side * 2] - truth[5 - side * 2]) ^ 2 + (sample[7 - side * 2] - truth[6 - side * 2]) ^ 2
		)
		table.insert(own, mine)
		table.insert(other, theirs)
	end
	return {
		near = summary(near),
		far = summary(far),
		own = summary(own),
		other = summary(other),
		nearLive = if nearFrames > 0 then nearLive / nearFrames else 1,
		puckShown = summary(puckShown),
		farShown = summary(farShown),
		puckLate = summary(puckLate),
		farLate = summary(farLate),
		undecided = undecided,
		resims = line.seats[side].resims,
		frames = #line.samples[side],
	}
end

-- How smoothly `side` was shown the match, frame to frame: the speed of the drawn puck and of the drawn far
-- mallet between one frame and the next, against what the table allows (7.5 m/s for the puck, 3.5 for a hand).
-- { frames, jumps (frames the drawn puck moved half a metre or more, which no quickening does: it was put back
-- on its spot after a goal, or it teleported; line.goals says how many goals there were), puckOver (other frames the drawn puck
-- moved faster than 1.15 x 7.5 m/s), puckOver2 (than 15 m/s), puckMax, malletOver (the far mallet faster than
-- 1.15 x 3.5 m/s), malletMax }
function Line.smooth(line: any, side: number): { [string]: number }
	local s = line.samples[side]
	local fps = line.fps
	local out = { frames = 0, puckOver = 0, puckOver2 = 0, puckMax = 0, malletOver = 0, malletMax = 0, jumps = 0 }
	local fi = 6 - side * 2
	for i = 2, #s do
		local a, b = s[i - 1], s[i]
		local d = math.sqrt((b[2] - a[2]) ^ 2 + (b[3] - a[3]) ^ 2)
		if d >= 0.5 then
			out.jumps += 1
		else
			local v = d * fps
			out.frames += 1
			if v > 7.5 * 1.15 then
				out.puckOver += 1
			end
			if v > 15 then
				out.puckOver2 += 1
			end
			out.puckMax = math.max(out.puckMax, v)
		end
		local vm = math.sqrt((b[fi] - a[fi]) ^ 2 + (b[fi + 1] - a[fi + 1]) ^ 2) * fps
		if vm > 3.5 * 1.15 then
			out.malletOver += 1
		end
		out.malletMax = math.max(out.malletMax, vm)
	end
	return out
end

return Line
